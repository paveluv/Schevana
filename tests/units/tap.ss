;;; tests/units/tap.ss — the allocation tap ((schevana services
;;; allocation)): samples of the stack a random number of bytes apart,
;;; taken at Chez's own requests for a collection, which tell which
;;; procedures allocate.

;; Two procedures that allocate three to one, a vector and a pair (96
;; bytes) a turn, each in a loop of its own: a request is seen at the
;; loop's next turn, inside the procedure that allocated. The code that
;; allocates is in line, so the thread sees a request at once under both
;; versions.
(define tap-test-keep #f)
(define (tap-test-three)
  (do ([i 0 (fx+ i 1)]) ((fx= i 300))
    (set! tap-test-keep (cons (make-vector 8) i))))
(define (tap-test-one)
  (do ([i 0 (fx+ i 1)]) ((fx= i 100))
    (set! tap-test-keep (cons (make-vector 8) i))))

;; Allocates some mb MB, by the two in turns.
(define (tap-test-run mb)
  (do ([i 0 (+ i 1)]) ((= i (quotient (* mb 1024 1024) (* 400 96))))
    (tap-test-three)
    (tap-test-one)))

;; Allocates some mb MB through Chez's own make-vector, whose bytes its C
;; code hands out: under 10.0.0 a thread sees a request that those bring
;; many turns late.
(define (tap-test-fill mb)
  (do ([i 0 (+ i 1)]) ((= i (quotient (* mb 1024 1024) 816)))
    (set! tap-test-keep (make-vector 100 i))))

;; Returns thunk's result, with a fresh recording on while it runs: a
;; sample every stride bytes or so, from the same seed each time.
(define (tap-test-recording stride thunk)
  (allocation-clear!)
  (set! *allocation-seed* 12345)
  (fluid-let ([*collector-holding?* #f])
    (allocation-record! #t stride)
    (let ([result (thunk)])
      (allocation-record! #f)
      result)))

;; Returns a field of the place named name, or 0 when no sample has it.
(define (tap-test-place name field)
  (let ([row (find (lambda (row) (equal? (cdr (assq 'name row)) name))
                   (allocation-places))])
    (if row (cdr (assq field row)) 0)))

(define (tap-test-sampled field) (cdr (assq field (allocation-sampled))))

;; Returns whether tree, a node of (allocation-paths), has a node named
;; outer with a child named inner somewhere in it.
(define (tap-test-calls? tree outer inner)
  (let ([named? (lambda (node name)
                  (and (pair? (car node)) (equal? (caar node) name)))])
    (let look ([node tree])
      (or (and (named? node outer)
               (exists (lambda (c) (named? c inner)) (cddddr node)))
          (exists look (cddddr node))))))

(check "off, the trip is the collector's; a recording moves it, and gives \
        it back when it ends"
       (begin
         (collect-rendezvous)
         (let ([off (collect-trip-bytes)]
               [on (tap-test-recording 65536
                     (lambda ()
                       (tap-test-run 8)
                       (collect-trip-bytes)))])
           (and (= off collector-trip)
                (< on collector-trip)
                (= (collect-trip-bytes) collector-trip)
                (not (allocation-recording?))))))

(check "two procedures that allocate three to one are sampled three to \
        one, and the samples with the bytes none saw add up to what the \
        clock moved"
       (let* ([before (allocation-clock)]
              [moved (tap-test-recording 16384
                       (lambda ()
                         (tap-test-run 192)
                         (- (allocation-clock) before)))]
              [three (tap-test-place "tap-test-three" 'self)]
              [one (tap-test-place "tap-test-one" 'self)]
              [seen (+ (tap-test-sampled 'bytes) (tap-test-sampled 'unseen))])
         (printf "  ~a samples: three ~a KB, one ~a KB (~,1f% to ~,1f%); \
                  ~a of ~a KB seen or counted unseen\n"
                 (tap-test-sampled 'samples)
                 (quotient three 1024) (quotient one 1024)
                 (/ (* 100.0 three) (max 1 (+ three one)))
                 (/ (* 100.0 one) (max 1 (+ three one)))
                 (quotient seen 1024) (quotient moved 1024))
         ;; 10.0.0 sees a request when the thread's count of calls and
         ;; turns runs out, here some 96 KB on: a third of the samples
         (and (> (tap-test-sampled 'samples) 1000)
              (< 0.70 (/ three (max 1 (+ three one))) 0.80)
              ;; most of what was sampled is theirs
              (> (+ three one) (* 0.9 (tap-test-sampled 'bytes)))
              (<= seen moved)
              (> seen (* 0.9 moved)))))

(check "a sample's path is the callers from the outermost in, under the \
        span that was open, and none of the way into the handler"
       (begin
         (tap-test-recording 16384
           (lambda ()
             (with-profile-span 'step #f
               (with-profile-span 'render #f
                 (tap-test-run 32)))))
         (let* ([tree (allocation-paths)]
                [span (find (lambda (node)
                              (equal? (car node) '(span render . #f)))
                            (cddddr tree))])
           (and span
                (tap-test-calls? span "tap-test-run" "tap-test-three")
                (tap-test-calls? span "tap-test-run" "tap-test-one")
                ;; no sample ends at a frame of the way in
                (for-all (lambda (name) (= 0 (tap-test-place name 'samples)))
                         allocation-way-in)))))

(check "a procedure of the tree's is named with its file and line, and is \
        the place its samples come down to"
       (begin
         (tap-test-recording 16384
           (lambda ()
             (do ([i 0 (+ i 1)]) ((= i 40000))
               (set! tap-test-keep (allocation-collections)))))
         (let ([row (find (lambda (row)
                            (equal? (cdr (assq 'name row))
                                    "allocation-collections"))
                          (allocation-places))])
           (when row (printf "  ~s\n" row))
           (and row
                (string? (cdr (assq 'file row)))
                (string=? (path-last (cdr (assq 'file row))) "allocation.sls")
                (fixnum? (cdr (assq 'line row)))
                (> (cdr (assq 'own row)) 0)
                (>= (cdr (assq 'total row)) (cdr (assq 'own row)))))))

(check "with the tap on, collections come when they would, also where a \
        request is seen late: the young generation's growth is the clock's"
       (let* ([count (lambda (thunk)
                       (collect-rendezvous)
                       (let ([before (collections)])
                         (thunk)
                         (- (collections) before)))]
              [both (lambda (run)
                      (cons (count (lambda () (run 64)))
                            (count (lambda ()
                                     (tap-test-recording 65536
                                       (lambda () (run 64)))))))]
              [in-line (both tap-test-run)]
              [by-c (both tap-test-fill)])
         (printf "  collections for 64 MB, off and on: ~a in line, ~a \
                  through Chez's C\n" in-line by-c)
         ;; one more for the recording's start, and one either way at
         ;; each end; counted by the alarms asked for, 4 came where 28
         ;; were due
         (and (<= (abs (- (cdr in-line) (car in-line))) 4)
              (<= (abs (- (cdr by-c) (car by-c))) 4))))

(check "a collection that the collector asks for is passed on at once, \
        and is no sample"
       (tap-test-recording 65536
         (lambda ()
           (tap-test-run 8)
           (let ([ran (collections)] [samples (tap-test-sampled 'samples)])
             (collector-pass! 1 2)
             (and (> samples 0)
                  (= (collections) (+ ran 1))
                  (= (tap-test-sampled 'samples) samples))))))

;; a draw that allocates some 17 MB in one frame turn, which holds its
;; collection off: the tap goes on sampling the turn, and the collector is
;; asked once
(let ([win (open-window "Hog" 'size '(80 . 60)
                        'draw (lambda (win w h)
                                (let loop ([i 0] [keep '()])
                                  (when (< i 200000)
                                    (loop (+ i 1)
                                          (cons (make-vector 8)
                                                (if (> (length keep) 10)
                                                    '()
                                                    keep)))))))])
  (steps 1)
  (allocation-clear!)
  (allocation-record! #t 65536)
  (steps 1)
  (let ([before (car (allocation-collections))]
        [samples (tap-test-sampled 'samples)])
    (invalidate! win)
    (steps 1)
    (let ([held (map (lambda (seq)
                       (cdr (assq 'held (allocation-collection seq))))
                     (filter (lambda (seq) (> seq before))
                             (allocation-collections)))]
          [taken (- (tap-test-sampled 'samples) samples)])
      (allocation-record! #f)
      (close-window! win)
      (printf "  a turn of 17 MB: ~a samples, requests held ~a\n" taken held)
      (check "a frame turn that holds its collection off is sampled all \
              the way, and the collector is asked once"
             (and (> taken 100) (= (apply + held) 1))))))

(check "when another thread runs the handler, the stack is out of sight: \
        the bytes stay with the span, with no path"
       (begin
         (tap-test-recording 16384
           (lambda ()
             (with-profile-span 'step #f
               (with-profile-span 'render #f
                 (fluid-let ([*profile-thread* -1])
                   (tap-test-run 16))))))
         (let ([span (find (lambda (node)
                             (equal? (car node) '(span render . #f)))
                           (cddddr (allocation-paths)))])
           ;; all but a sample or two: one may come as the spans close,
           ;; on this thread again
           (and span
                (> (cadr span) (* 0.9 (caddr span)))
                (< (tap-test-place "tap-test-three" 'own)
                   (* 0.1 (cadr span)))))))

(check "past 500 samples in a second the stride doubles, and it halves \
        again, down to the stride asked for, once they come four times \
        slower"
       (let ([clock now-ns] [second 1000000000] [t 5000000000])
         (allocation-record! #t 65536)
         (allocation-record! #f)
         (set! now-ns (lambda () t))
         (allocation-pace!)
         (set! t (+ t second))
         (do ([i 0 (+ i 1)]) ((= i 600)) (allocation-pace!))
         (set! t (+ t second))
         (allocation-pace!)
         (let ([fast (tap-test-sampled 'stride-now)])
           (set! t (+ t second))
           (allocation-pace!)
           (let ([slow (tap-test-sampled 'stride-now)])
             (set! t (+ t second))
             (allocation-pace!)
             (set! now-ns clock)
             (and (= fast (* 2 65536))
                  (= slow 65536)
                  (= (tap-test-sampled 'stride-now) 65536))))))
