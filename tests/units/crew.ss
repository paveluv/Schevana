;;; tests/units/crew.ss — the crew (services/crew.ss).

;;; The crew (services/crew.ss).

;; Main's budget is for runaways, and on a busy machine an ordinary region here
;; could run into it. So it's long in this file, but for the check about it.
(define crew-test-budget crew-main-ms)
(set! crew-main-ms 60000)

;; About us µs of work, without allocating; the thread's id noted in ids
;; (a box of a list) the first time.
(define-worklet (crew-test-busy us ids)
  (let ([id (get-thread-id)])
    (let note ()
      (let ([seen (unbox ids)])
        (unless (or (memv id seen) (box-cas! ids seen (cons id seen)))
          (note)))))
  (let ([until (+ (now-ns) (* 1000 us))])
    (let loop () (when (< (now-ns) until) (loop)))))

(define-worklet (crew-test-add! b n)
  (let loop ()
    (let ([v (unbox b)]) (unless (box-cas! b v (+ v n)) (loop)))))

;; Each index of [lo, hi) counted in counts, after us µs.
(define-worklet (crew-test-count lo hi counts us ids)
  (crew-test-busy us ids)
  (do ([i lo (fx+ i 1)]) ((fx= i hi))
    (bytevector-u8-set! counts i (fx+ 1 (bytevector-u8-ref counts i)))))

;; As crew-test-count, but no call ends till the caller and a worker have both
;; taken part, however slow a thread is to wake; at most 10 s.
(define-worklet (crew-test-together lo hi counts main ids)
  (crew-test-count lo hi counts 0 ids)
  (let ([until (+ (now-ns) 10000000000)])
    (let wait ()
      (let ([seen (unbox ids)])
        (unless (or (and (memv main seen) (pair? (cdr seen)))
                    (> (now-ns) until))
          (wait))))))

(define-worklet (crew-test-square x) (* x x))

(check "crew-for calls a worklet on disjoint chunks that cover the range \
        once each, on the caller and the workers; crew-map is map, in \
        order; a procedure that is no worklet is refused"
       (let ([counts (make-bytevector 20000 0)] [ids (box '())])
         (crew-for* 100 0 20000 crew-test-together counts (get-thread-id) ids)
         (printf "  ~a workers, ~a threads took part\n" (crew-size)
                 (length (unbox ids)))
         (and (> (crew-size) 0)
              (for-all (lambda (i) (= 1 (bytevector-u8-ref counts i)))
                       (iota 20000))
              (> (length (unbox ids)) 1)
              (memv (get-thread-id) (unbox ids))
              (equal? (crew-map crew-test-square (iota 1000))
                      (map (lambda (x) (* x x)) (iota 1000)))
              (guard (c [#t (string-contains-ci? (condition-message c)
                                                 "worklets only")])
                (crew-for 0 10 (lambda (lo hi) #f))
                #f))))

(define-worklet (crew-test-ignore lo hi x) #f)

(check "crew-for hands a worklet no procedure but worklets: none among its \
        arguments, nor in the pairs, vectors and boxes they hold; data \
        that holds itself is walked once"
       (let ([refused?
              (lambda (thunk)
                (guard (c [#t (string-contains-ci? (condition-message c)
                                                   "worklets only")])
                  (thunk)
                  #f))]
             [ring (list 1 2 3)])
         (set-cdr! (cddr ring) ring)
         (and (refused? (lambda () (crew-map (lambda (x) x) '(1 2))))
              (refused? (lambda () (crew-map crew-test-square (list 1 car))))
              (refused? (lambda ()
                          (crew-for 0 10 crew-test-ignore
                                    (vector 1 (list 2 (box car))))))
              (not (refused? (lambda ()
                               (crew-for 0 10 crew-test-ignore
                                         (vector ring crew-test-square
                                                 (box ring)))))))))

(define-worklet (crew-test-fail lo hi started finished)
  (crew-test-add! started 1)
  (when (fx= lo 200) (error 'crew-test "chunk 200"))
  (crew-test-busy 1000 (box '()))
  (crew-test-add! finished 1))

(check "a call that raises: the calls not started never start, those \
        running finish, and the caller raises its condition"
       ;; so many that the rest can't all start while the thread that raises
       ;; waits its turn on a busy machine: a second of calls and more
       (let* ([started (box 0)] [finished (box 0)]
              [c (guard (c [#t c])
                   (crew-for* 10 0 100000 crew-test-fail started finished)
                   #f)])
         (printf "  ~a of 10,000 calls started, ~a finished\n" (unbox started)
                 (unbox finished))
         (and c (string=? (condition-message c) "chunk 200")
              (< (unbox started) 10000)
              (= (unbox finished) (- (unbox started) 1)))))

;; Forever, but on main's thread: a millisecond there, so that the
;; workers, however slow to wake, get some of the calls.
(define-worklet (crew-test-runaway lo hi main)
  (if (fx= (get-thread-id) main)
      (crew-test-busy 1000 (box '()))
      (let loop () (loop))))

(check "on main a runaway call is cancelled at the caller's budget: the \
        caller raises the timeout, the worker escapes, and the crew works \
        on"
       (let* ([t0 (now-ms)]
              [c (fluid-let ([crew-main-ms crew-test-budget])
                   (guard (c [#t c])
                     (crew-for* 1 0 64 crew-test-runaway (get-thread-id))
                     #f))]
              [ms (- (now-ms) t0)] [ids (box '())])
         (printf "  raised after ~a ms: ~a\n" ms
                 (and c (condition? c) (condition->string c)))
         (crew-for* 1 0 64 crew-test-together (make-bytevector 64 0)
                    (get-thread-id) ids)
         ;; at its budget, not after it: how long past it is the machine's
         (and c (string-contains-ci? (condition-message c) "time budget")
              (>= ms crew-test-budget)
              (< ms 10000)
              (> (length (unbox ids)) 1))))

(define-worklet (crew-test-calls lo hi out) (set-box! out (list lo hi)))

(check "with no workers, crew-for is the worklet over the whole range"
       (let ([out (box #f)] [size (crew-size)])
         (crew-size-set! 0)
         (crew-for 3 900 crew-test-calls out)
         (crew-size-set! size)
         (equal? (unbox out) '(3 900))))

(define-worklet (crew-test-allocate lo hi sum)
  (crew-test-add! sum (vector-length (make-vector 20000 0))))

(check "while workers and main allocate, collections run: no thread waits \
        for good"
       (let ([sum (box 0)] [n0 (collections)])
         (do ([k 0 (+ k 1)]) ((= k 20))
           (crew-for* 1 0 64 crew-test-allocate sum)
           (make-vector 20000 0))
         (printf "  ~a collections\n" (- (collections) n0))
         (= (unbox sum) (* 20 64 20000))))

(check "in a process (a REPL evaluation), crew-for waits without taking \
        part, and the world steps meanwhile"
       (let* ([ids (box '())] [done #f] [steps0 0]
              [p (spawn "crew"
                        (lambda ()
                          (crew-for* 1 0 32 crew-test-count
                                     (make-bytevector 32 0) 100000 ids)
                          (set! done #t)))])
         (let ([until (+ (real-time) 30000)])   ; at most 30 s
           (let loop ()
             (when (and (memq p (procs)) (< (real-time) until))
               (steps 1)
               (set! steps0 (+ steps0 1))
               (loop))))
         (printf "  ~a steps while it waited\n" steps0)
         (and done (> steps0 3) (pair? (unbox ids))
              (not (memv (get-thread-id) (unbox ids))))))

;;; What the crew costs, itself: nothing a call, nothing idle.

(define-worklet (crew-test-nothing lo hi) (void))
(define-worklet (crew-test-six lo hi a b c d e f) (void))

;; The least of a few runs: any one may share its time with a collection,
;; whose copying the counters count. Workers going back to idle count too, as
;; they are scheduled, a thread's memory by the chunk of 48 KB, however few
;; calls ran. So the limit is what the calls would show: 20,000 of them
;; consing once each take 320 KB.
(let ([size (crew-size)])
  (crew-size-set! (max 2 size))
  (let* ([least-bytes
          (lambda (thunk)
            (thunk)
            (let loop ([i 0] [least #f])
              (if (= i 5)
                  least
                  (let ([b0 (bytes-total)])
                    (thunk)
                    (let ([b (- (bytes-total) b0)])
                      (loop (+ i 1) (if least (min least b) b)))))))]
         [none (least-bytes
                (lambda () (crew-for* 1 0 20000 crew-test-nothing)))]
         [six (least-bytes
               (lambda () (crew-for* 1 0 20000 crew-test-six 1 2 3 4 5 6)))]
         [idle (let ([wait (make-time 'time-duration 200000000 0)])
                 (sleep wait)
                 (let ([b0 (bytes-total)])
                   (sleep wait)
                   (- (bytes-total) b0)))])
    (crew-size-set! size)
    (check (format "the crew allocates nothing a call and nothing idle: a \
                    region of 20,000 calls takes ~a bytes, with six arguments \
                    ~a, 200 ms of idle workers ~a" none six idle)
           (and (< none 64000) (< six 64000) (< idle 512)))))
