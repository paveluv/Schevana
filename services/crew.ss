;;; services/crew.ss — a crew of worker threads for data-parallel loops.
;;;
;;;   (crew-for 0 rows step! grid next)   (step! lo hi grid next) on disjoint
;;;                                       [lo, hi) covering the range
;;;   (crew-for* 8 0 rows step! grid next)       at least 8 indices a call
;;;   (crew-map square list)              (map square list) on the crew
;;;   (crew-size) (crew-size-set! 4)      how many workers
;;;
;;; What the crew calls is a worklet (define-worklet, src/proc.ss): it
;;; touches only what it is handed, and each call writes only its own
;;; slice. What it is handed holds no procedure but worklets: crew-for
;;; refuses any other among its arguments, or in the pairs, vectors and
;;; boxes they hold, the containers a worklet can open. The caller takes
;;; part, and crew-for returns when every call has returned. A call
;;; should take 20 to 200 µs and allocate nothing:
;;; allocation stops every thread. A call that raises stops new ones from
;;; starting, and its condition is raised in the caller once the running
;;; ones are done. On main the caller waits at most crew-main-ms, then
;;; cancels its calls (a worker's timer escapes from one within
;;; microseconds) and raises, as a runaway handler does. In a process (a
;;; REPL evaluation) the caller only waits, a millisecond at a time, and
;;; killing the process cancels its calls. With no workers, or a range of
;;; one chunk, crew-for is (worklet start end arg ...).
;;;
;;; The crew's state changes only by box-cas!: no thread waits on another
;;; but the idle workers, on the one lock, outside any call. Workers run
;;; no engine: every crew-fuel ticks of a region, a worker's timer looks
;;; whether the region was cancelled.
;;;
;;; A call costs a claim and nothing else: no allocation, for allocation
;;; stops every thread. A worker's guard and its way out are set up once,
;;; for as long as nothing goes wrong: around every call they were most of
;;; what the crew allocated, about 3 KB a call. A worker counts as running
;;; in a region from when it joins until it leaves, not call by call, so
;;; that a call is one box-cas!. A region costs its record, a few hundred
;;; bytes, and an idle worker nothing.

(define crew-fuel 20000)          ; timer ticks between a worker's looks
(define crew-main-ms 100)         ; how long main waits for a region
;; made once: a wait allocates nothing
(define crew-idle-wait (make-time 'time-duration 50000000 0))   ; at most
(define crew-nap (make-time 'time-duration 20000 0))            ; a waiter's
(define crew-wait-spins 2000)     ; how long a waiter looks, before naps

;; A loop's range, chunk, worklet and the arguments after lo and hi; boxes:
;; the next index, the workers in it, the first condition raised, whether
;; it was cancelled; main's deadline (ms) or #f, and the process waiting
;; for it or #f.
(define-record-type crew-region
  (nongenerative schevana-crew-region-3)
  (fields start end chunk proc args next running error cancelled deadline
          process))

;; SCHEVANA_WORKERS, or one less than the machine's threads, at most 8
;; (more allocating workers slow the main thread down).
(define (crew-default-size)
  (let ([n (let ([s (getenv "SCHEVANA_WORKERS")]) (and s (string->number s)))])
    (if (and (fixnum? n) (>= n 0))
        n
        (max 1 (min 8 (- (host-cpu-count) 1))))))

(defvar *crew-size* (crew-default-size))
(defvar *crew-workers* '())         ; their threads, the oldest first
(defvar *crew-regions* (box '()))   ; the loops running, the newest first
(defvar *crew-mutex* (make-mutex))
(defvar *crew-wake* (make-condition))
;; A worker's own: its index, the region it is in, its way out, and the list
;; of a call's arguments. Fields, not thread parameters: setting one of those
;; allocates 80 bytes.
(define-record-type crew-worker
  (nongenerative schevana-crew-worker-1)
  (fields index (mutable region) (mutable escape) call))

(define (crew-size) *crew-size*)

;; More workers start at the next crew-for; workers past n stay idle.
(define (crew-size-set! n)
  (set! *crew-size* n)
  (crew-wake!))

;;; ------------------------------------------------------------------ workers

;; On main: workers up to the size.
(define (crew-ensure!)
  (let loop ([i (length *crew-workers*)])
    (when (< i (crew-size))
      (set! *crew-workers* (append *crew-workers* (list (crew-fork! i))))
      (loop (+ i 1)))))

;; Worker i: its own timer, its way out and its guard, then turns, each by
;; name, so a reload changes them. Only an error or a cancel comes out of
;; them; then it leaves the region it was in, and starts again.
(define (crew-fork! i)
  (fork-thread
   (lambda ()
     (let ([me (make-crew-worker i #f #f (list 0 0))])
       (timer-interrupt-handler (lambda () (crew-timer! me)))
       (let again ()
         (call/1cc
          (lambda (k)
            (crew-worker-escape-set! me k)
            (guard (c [#t (crew-failed! me c)])
              (let loop () (crew-worker-step! me) (loop)))))
         (crew-left! me)
         (again))))))

;; A worker's turn: an open region's calls, or a wait for one. Plain lock
;; calls: a worker has no engine to stop it holding the lock, and with-mutex
;; would allocate.
(define (crew-worker-step! me)
  (let* ([i (crew-worker-index me)]
         [r (and (< i (crew-size)) (crew-open-region))])
    (if r
        (crew-join! me r)
        (begin
          (mutex-acquire *crew-mutex*)
          (unless (and (< i (crew-size)) (crew-open-region))
            (condition-wait *crew-wake* *crew-mutex* crew-idle-wait))
          (mutex-release *crew-mutex*)))))

;; In r, counted before any claim, so its caller never sees none running
;; while one is under way; what is closed stays closed, so nothing starts
;; once the caller has seen it closed with none running. The fences: what
;; the caller wrote before it pushed r, in view; the count, seen before the
;; claim (box-cas! orders no memory, and ARM keeps no order of its own).
(define (crew-join! me r)
  (memory-order-acquire)
  (crew-add! (crew-region-running r) 1)
  (memory-order-release)
  (crew-worker-region-set! me r)
  (set-timer crew-fuel)
  (crew-calls! r #f (crew-worker-call me))
  (set-timer 0)
  (crew-leave! me r))

;; Out of r, holding on to nothing of its arguments, its slices written
;; before it's counted out.
(define (crew-leave! me r)
  (set-cdr! (cdr (crew-worker-call me)) '())
  (crew-worker-region-set! me #f)
  (memory-order-release)
  (crew-add! (crew-region-running r) -1))

;; What a worker's guard does with a condition: its region's first.
(define (crew-failed! me c)
  (let ([r (crew-worker-region me)])
    (when r (crew-error! r c))))

;; r's first condition. box-cas! may fail on ARM with nothing in its way
;; (Chez's guide), so it's tried until the box holds one.
(define (crew-error! r c)
  (let ([b (crew-region-error r)])
    (let loop () (unless (or (unbox b) (box-cas! b #f c)) (loop)))))

;; After an error or a cancel. With no region to leave, something outside
;; a call is broken (a bad redefinition): not at full speed, then.
(define (crew-left! me)
  (set-timer 0)
  (let ([r (crew-worker-region me)])
    (if r
        (crew-leave! me r)
        (sleep crew-idle-wait))))

;; Wakes the idle workers. The lock is only tried, with interrupts off, so
;; an engine never stops while holding it; if every try fails, a worker
;; wakes at its wait's end, and the caller works meanwhile.
(define (crew-wake!)
  (let try ([n 0])
    (unless (or (with-interrupts-disabled
                 (and (mutex-acquire *crew-mutex* #f)
                      (begin (condition-broadcast *crew-wake*)
                             (mutex-release *crew-mutex*)
                             #t)))
                (= n 1000))
      (try (+ n 1)))))

;; A worker's timer: out of its region when that was cancelled.
(define (crew-timer! me)
  (let ([r (crew-worker-region me)])
    (when r
      (if (crew-cancelled? r)
          ((crew-worker-escape me) #f)
          (set-timer crew-fuel)))))

;;; ------------------------------------------------------------------ regions

(define (crew-add! b n)
  (let loop ()
    (let ([v (unbox b)]) (unless (box-cas! b v (fx+ v n)) (loop)))))

;; By its caller, past main's deadline, or its process gone. It stays so,
;; in the box a claim reads.
(define (crew-cancelled? r)
  (or (unbox (crew-region-cancelled r))
      (and (or (let ([d (crew-region-deadline r)]) (and d (> (now-ms) d)))
               (let ([p (crew-region-process r)])
                 (and p (not (eq? (proc-state p) 'running)))))
           (begin (set-box! (crew-region-cancelled r) #t) #t))))

;; Calls left to start: no clock read, a worker's timer and the caller look.
(define (crew-open? r)
  (and (fx< (unbox (crew-region-next r)) (crew-region-end r))
       (not (unbox (crew-region-error r)))
       (not (unbox (crew-region-cancelled r)))))

(define (crew-open-region) (find crew-open? (unbox *crew-regions*)))

;; No call left to start and none under way, the workers' slices in view.
;; The first fence reads the count after the claims, as crew-join! made it.
(define (crew-done? r)
  (and (not (crew-open? r))
       (begin (memory-order-acquire)
              (fx= 0 (unbox (crew-region-running r))))
       (begin (memory-order-acquire) #t)))

;; What the caller wrote, before r is there for a worker to join.
(define (crew-push! r)
  (memory-order-release)
  (let loop ()
    (let ([rs (unbox *crew-regions*)])
      (unless (box-cas! *crew-regions* rs (cons r rs)) (loop)))))

(define (crew-remove! r)
  (let loop ()
    (let ([rs (unbox *crew-regions*)])
      (unless (box-cas! *crew-regions* rs (remq r rs)) (loop)))))

;; Regions whose caller left without removing them (a handler's engine
;; dropped while it waited).
(define (crew-prune!)
  (for-each (lambda (r)
              (when (or (crew-cancelled? r)
                        (and (not (crew-open? r))
                             (fx= 0 (unbox (crew-region-running r)))))
                (when (fx= 0 (unbox (crew-region-running r)))
                  (crew-remove! r))))
            (unbox *crew-regions*)))

;; The next call's start, or #f.
(define (crew-claim! r)
  (let ([next (crew-region-next r)] [chunk (crew-region-chunk r)])
    (let loop ()
      (let ([lo (unbox next)])
        (cond [(not (crew-open? r)) #f]
              [(box-cas! next lo (fx+ lo chunk)) lo]
              [else (loop)])))))

;; r's calls until none is left to start. A caller looks at the clock
;; itself (watch?): it has no timer of the crew's. Each call's lo and hi are
;; set in call, a list of two the region's arguments go on the end of:
;; (apply proc lo hi args) would cons them, 32 bytes a call.
(define (crew-calls! r watch? call)
  (let ([proc (crew-region-proc r)] [end (crew-region-end r)]
        [chunk (crew-region-chunk r)])
    (set-cdr! (cdr call) (crew-region-args r))
    (let loop ()
      (unless (and watch? (crew-cancelled? r))
        (let ([lo (crew-claim! r)])
          (when lo
            (set-car! call lo)
            (set-car! (cdr call) (fxmin end (fx+ lo chunk)))
            (apply proc call)
            (loop)))))))

;; The caller's calls. A call that raises stops the others starting; once
;; those running are done its condition goes on up, or the first if
;; another's came first. No guard: that is a stack segment a region.
(define (crew-take-part! r)
  (with-exception-handler
   (lambda (c)
     (crew-error! r c)
     (crew-wait! r)
     (crew-remove! r)
     (raise (unbox (crew-region-error r))))
   (lambda () (crew-calls! r #t (list 0 0)))))

;; Until no worker is in r, which is closed by now; on main, at most
;; crew-main-ms past its deadline (for the cancelled calls to escape).
;; Looks first, as the calls left are short, and a nap is much longer than
;; it asks for.
(define (crew-wait! r)
  (let ([give-up (let ([d (crew-region-deadline r)])
                   (and d (+ d crew-main-ms)))])
    (let loop ([spins 0])
      (unless (crew-done? r)
        (if (fx< spins crew-wait-spins)
            (loop (fx+ spins 1))
            (begin
              (crew-cancelled? r)
              (unless (and give-up (> (now-ms) give-up))
                (sleep crew-nap)
                (loop spins))))))))

;;; ------------------------------------------------------------------ the API

;; The first procedure in x's reach that is no worklet, or #f. A worklet
;; opens only pairs, vectors and boxes (the accessors of records and
;; hashtables are out of its reach), so only those are walked, each once.
(define (crew-stray x)
  (cond
    [(procedure? x) (and (not (worklet? x)) x)]
    [(not (or (pair? x) (vector? x) (box? x))) #f]
    [else
     (let ([seen (make-eq-hashtable)])
       (let walk ([x x])
         (cond
           [(procedure? x) (and (not (worklet? x)) x)]
           [(not (or (pair? x) (vector? x) (box? x))) #f]
           [(hashtable-contains? seen x) #f]
           [else
            (hashtable-set! seen x #t)
            (cond
              [(pair? x) (or (walk (car x)) (walk (cdr x)))]
              [(box? x) (walk (unbox x))]
              [else
               (let loop ([i 0])
                 (and (< i (vector-length x))
                      (or (walk (vector-ref x i)) (loop (+ i 1)))))])])))]))

;; The first stray among a call's arguments, a list fresh from its rest
;; argument: most hold nothing to walk, and make no table.
(define (crew-stray-among args)
  (and (pair? args)
       (or (crew-stray (car args)) (crew-stray-among (cdr args)))))

;; (crew-for start end worklet arg ...): (worklet lo hi arg ...) for each
;; chunk of [start, end), the range over four times the threads.
(define (crew-for start end proc . args)
  (let ([parts (* 4 (+ (crew-size) 1))])
    (apply crew-for* (max 1 (quotient (+ (- end start) parts -1) parts))
           start end proc args)))

;; crew-for, at least chunk indices a call.
(define (crew-for* chunk start end proc . args)
  (cond
    [(or (crew-stray proc) (crew-stray-among args))
     => (lambda (p)
          (errorf 'crew-for "the crew runs worklets only (define-worklet): ~s"
                  p))]
    [(<= end start) (void)]
    [(or (= (crew-size) 0) (<= (- end start) chunk))
     (apply proc start end args)]
    [else
     (let* ([p (current-proc)]
            [r (make-crew-region start end chunk proc args (box start) (box 0)
                                 (box #f) (box #f)
                                 (and (not p) (+ (now-ms) crew-main-ms)) p)])
       (crew-prune!)
       (crew-ensure!)
       (crew-push! r)
       (crew-wake!)
       (if p
           (let wait ()   ; a process: no part in it, the desktop runs on
             (unless (crew-done? r)
               (sleep-ms 1)
               (crew-cancelled? r)
               (wait)))
           (begin (crew-take-part! r) (crew-wait! r)))
       (crew-remove! r)
       (cond [(unbox (crew-region-error r)) => raise]
             [(crew-cancelled? r)
              (raise (make-timeout-condition 'crew-for))]))]))

;; What the core spreads over threads, the crew's to share.
(set! *worklet-spread*
  (lambda (chunk start end proc . args)
    (apply crew-for* chunk start end proc args)))

;; A chunk of crew-map: f of in's items, into out.
(define-worklet (crew-map-chunk lo hi f in out)
  (do ([i lo (fx+ i 1)]) ((fx= i hi))
    (vector-set! out i (f (vector-ref in i)))))

;; (map worklet l), the calls spread over the crew; the results in order.
(define (crew-map f l)
  (let* ([in (list->vector l)] [out (make-vector (vector-length in))])
    (crew-for 0 (vector-length in) crew-map-chunk f in out)
    (vector->list out)))
