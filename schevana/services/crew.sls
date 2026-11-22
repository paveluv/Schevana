;;; (schevana services crew) — a crew of worker threads for data-parallel
;;; loops.
;;;
;;;   (crew-for 0 rows step! grid next)   calls (step! lo hi grid next) on
;;;                                       disjoint [lo, hi) that cover the
;;;                                       range
;;;   (crew-for* 8 0 rows step! grid next)
;;;                                       the same, with at least 8 indices
;;;                                       per call
;;;   (crew-map square list)              (map square list), on the crew
;;;   (crew-size) (crew-size-set! 4)      the number of workers
;;;
;;; The crew calls only worklets (define-worklet, in (schevana core
;;; processes)): a worklet touches only what it is handed, and each call
;;; writes only its own slice. What a worklet is handed holds no procedure
;;; other than worklets: crew-for refuses any other procedure among its
;;; arguments, or inside the pairs, vectors and boxes they hold (the
;;; containers a worklet can open). The caller takes part in the work, and
;;; crew-for returns when every call has returned. A call should take 20 to
;;; 200 µs and allocate nothing, since allocation stops every thread. When
;;; a call raises, no new calls start, and its condition is raised in the
;;; caller once the running calls are done. On core1 the caller waits at
;;; most crew-core1-ms; then it cancels its calls (a worker's timer escapes
;;; from a call within microseconds) and raises a timeout, as a runaway
;;; handler does. In a process (a REPL evaluation) the caller only waits,
;;; checking once a millisecond, and killing the process cancels its calls.
;;; With no workers, or with a range of one chunk, crew-for simply calls
;;; (worklet start end arg ...).
;;;
;;; The crew's state changes only through box-cas!: the only threads that
;;; wait are the idle workers, on the crew's one lock, outside any call.
;;; Workers run no engine: inside a region, a worker's timer fires every
;;; crew-fuel ticks and checks whether the region was canceled.
;;;
;;; A call costs a claim and nothing else: it allocates nothing, since
;;; allocation stops every thread. A worker sets up its guard and its
;;; escape once and keeps them for as long as nothing goes wrong; set up
;;; around every call, they would cost about 3 KB a call. A worker counts
;;; as running in a region from when it joins until it leaves, not call by
;;; call, so that a call costs one box-cas!. A region costs its record (a
;;; few hundred bytes), and an idle worker costs nothing.

(library (schevana services crew)
  (export
    crew-fuel crew-core1-ms crew-idle-wait crew-nap crew-wait-spins crew-region
    make-crew-region crew-region? crew-region-start crew-region-end
    crew-region-chunk crew-region-proc crew-region-args crew-region-next
    crew-region-running crew-region-error crew-region-cancelled
    crew-region-deadline crew-region-process crew-default-size *crew-size*
    *crew-workers* *crew-regions* *crew-mutex* *crew-wake* crew-worker
    make-crew-worker crew-worker? crew-worker-index crew-worker-region
    crew-worker-region-set! crew-worker-escape crew-worker-escape-set!
    crew-worker-call crew-size crew-size-set! crew-ensure! crew-fork!
    crew-worker-step! crew-join! crew-leave! crew-failed! crew-error!
    crew-left! crew-wake! crew-timer! crew-add! crew-cancelled? crew-open?
    crew-open-region crew-done? crew-push! crew-remove! crew-prune! crew-claim!
    crew-calls! crew-take-part! crew-wait! crew-stray crew-stray-among crew-for
    crew-for* crew-map-chunk crew-map)
  (import (chezscheme)
          (only (schevana base) define-made define-state library-layer
                set-hook!)
          (only (schevana core) current-proc define-worklet
                make-timeout-condition now-ms platform-cpu-count proc
                proc-state sleep-ms worklet-spread worklet?))

  (library-layer services)

  (define crew-fuel 20000)          ; timer ticks between a worker's checks
  (define-state crew-core1-ms 100)         ; how long core1 waits for a region
  ;; Made once, so that a wait allocates nothing: an idle worker waits at
  ;; most crew-idle-wait, and a caller waiting for a region naps crew-nap.
  (define-made crew-idle-wait (make-time 'time-duration 50000000 0))
  (define-made crew-nap
    (make-time 'time-duration 20000 0))
  (define crew-wait-spins 2000)     ; times a waiter looks before it naps

  ;; A running loop: its range, its chunk, its worklet and the arguments
  ;; after lo and hi; then boxes for the next index, the number of workers
  ;; in it, the first condition raised and whether it was canceled; then
  ;; core1's deadline (ms) or #f, and the process that waits for it, or #f.
  (define-record-type crew-region
    (nongenerative schevana-crew-region-3)
    (fields start end chunk proc args next running error cancelled deadline
            process))

  ;; SCHEVANA_WORKERS when it is set, or else one less than the machine's
  ;; threads, at least 1 and at most 8 (more workers that allocate slow core1
  ;; down).
  (define (crew-default-size)
    (let ([n (let ([s (getenv "SCHEVANA_WORKERS")])
               (and s (string->number s)))])
      (if (and (fixnum? n) (>= n 0))
          n
          (max 1 (min 8 (- (platform-cpu-count) 1))))))

  (define-state *crew-size* (crew-default-size))
  (define-state *crew-workers* '())         ; the workers' threads, oldest first
  (define-state *crew-regions*
    (box '()))   ; the running loops, newest first
  (define-state *crew-mutex* (make-mutex))
  (define-state *crew-wake* (make-condition))
  ;; A worker's own state: its index, the region it is in, its escape, and
  ;; the list it passes a call as its arguments. These are fields, not thread
  ;; parameters, because setting a thread parameter allocates 80 bytes.
  (define-record-type crew-worker
    (nongenerative schevana-crew-worker-1)
    (fields index (mutable region) (mutable escape) call))

  (define (crew-size) *crew-size*)

  ;; Sets the number of workers. New workers start at the next crew-for;
  ;; workers past n stay idle.
  (define (crew-size-set! n)
    (set! *crew-size* n)
    (crew-wake!))

  ;;; ---------------------------------------------------------------- workers

  ;; On core1: starts workers until there are (crew-size) of them.
  (define (crew-ensure!)
    (let loop ([i (length *crew-workers*)])
      (when (< i (crew-size))
        (set! *crew-workers* (append *crew-workers* (list (crew-fork! i))))
        (loop (+ i 1)))))

  ;; Starts worker i. It sets up its own timer, its escape and its guard,
  ;; then takes turns, each a call by name, so that a redefinition reaches
  ;; them in the hacker edition. Only an error or a cancel ends the turns;
  ;; then the worker leaves the region it was in and starts again.
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

  ;; A worker's turn: it makes an open region's calls, or waits for one. It
  ;; calls the lock's procedures directly: a worker has no engine that could
  ;; stop it while it holds the lock, and with-mutex would allocate.
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

  ;; Joins r. The worker is counted before it claims a call, so the caller
  ;; never sees none running while a call is under way; a closed region stays
  ;; closed, so no call starts once the caller has seen r closed with none
  ;; running. The fences make what the caller wrote before it pushed r
  ;; visible here, and the count visible before the claim (box-cas! orders
  ;; no memory, and ARM keeps no order of its own).
  (define (crew-join! me r)
    (memory-order-acquire)
    (crew-add! (crew-region-running r) 1)
    (memory-order-release)
    (crew-worker-region-set! me r)
    (set-timer crew-fuel)
    (crew-calls! r #f (crew-worker-call me))
    (set-timer 0)
    (crew-leave! me r))

  ;; Leaves r, keeping none of its arguments; the fence makes the worker's
  ;; slices visible before it is counted out.
  (define (crew-leave! me r)
    (set-cdr! (cdr (crew-worker-call me)) '())
    (crew-worker-region-set! me #f)
    (memory-order-release)
    (crew-add! (crew-region-running r) -1))

  ;; What a worker's guard does with a condition: it becomes its region's
  ;; first, unless another came before.
  (define (crew-failed! me c)
    (let ([r (crew-worker-region me)])
      (when r (crew-error! r c))))

  ;; Records c as r's first condition. box-cas! may fail on ARM even with
  ;; nothing in its way (Chez's guide), so it is tried until the box holds a
  ;; condition.
  (define (crew-error! r c)
    (let ([b (crew-region-error r)])
      (let loop () (unless (or (unbox b) (box-cas! b #f c)) (loop)))))

  ;; Runs after an error or a cancel. With no region to leave, something
  ;; outside a call is broken (a bad redefinition), so the worker sleeps
  ;; rather than fail again at full speed.
  (define (crew-left! me)
    (set-timer 0)
    (let ([r (crew-worker-region me)])
      (if r
          (crew-leave! me r)
          (sleep crew-idle-wait))))

  ;; Wakes the idle workers. The lock is only tried, with interrupts off, so
  ;; that an engine never stops while it holds the lock; if every try fails,
  ;; a worker wakes when its wait ends, and the caller works meanwhile.
  (define (crew-wake!)
    (let try ([n 0])
      (unless (or (with-interrupts-disabled
                   (and (mutex-acquire *crew-mutex* #f)
                        (begin (condition-broadcast *crew-wake*)
                               (mutex-release *crew-mutex*)
                               #t)))
                  (= n 1000))
        (try (+ n 1)))))

  ;; A worker's timer: it escapes from the worker's region when that was
  ;; canceled, and otherwise sets the timer again.
  (define (crew-timer! me)
    (let ([r (crew-worker-region me)])
      (when r
        (if (crew-cancelled? r)
            ((crew-worker-escape me) #f)
            (set-timer crew-fuel)))))

  ;;; ---------------------------------------------------------------- regions

  (define (crew-add! b n)
    (let loop ()
      (let ([v (unbox b)]) (unless (box-cas! b v (fx+ v n)) (loop)))))

  ;; Whether r was canceled: by its caller, by passing core1's deadline, or
  ;; by its process no longer running. Once canceled, r stays so, in the box
  ;; that a claim reads.
  (define (crew-cancelled? r)
    (or (unbox (crew-region-cancelled r))
        (and (or (let ([d (crew-region-deadline r)]) (and d (> (now-ms) d)))
                 (let ([p (crew-region-process r)])
                   (and p (not (eq? (proc-state p) 'running)))))
             (begin (set-box! (crew-region-cancelled r) #t) #t))))

  ;; Whether r has calls left to start. It reads no clock: a worker's timer
  ;; and the caller check the deadline.
  (define (crew-open? r)
    (and (fx< (unbox (crew-region-next r)) (crew-region-end r))
         (not (unbox (crew-region-error r)))
         (not (unbox (crew-region-cancelled r)))))

  (define (crew-open-region) (find crew-open? (unbox *crew-regions*)))

  ;; Whether r has no call left to start and none under way, with the
  ;; workers' slices visible. The first fence reads the count after the
  ;; claims, in the order crew-join! wrote them.
  (define (crew-done? r)
    (and (not (crew-open? r))
         (begin (memory-order-acquire)
                (fx= 0 (unbox (crew-region-running r))))
         (begin (memory-order-acquire) #t)))

  ;; Adds r to the running loops, after what the caller wrote is visible,
  ;; so that a worker joining r sees it.
  (define (crew-push! r)
    (memory-order-release)
    (let loop ()
      (let ([rs (unbox *crew-regions*)])
        (unless (box-cas! *crew-regions* rs (cons r rs)) (loop)))))

  (define (crew-remove! r)
    (let loop ()
      (let ([rs (unbox *crew-regions*)])
        (unless (box-cas! *crew-regions* rs (remq r rs)) (loop)))))

  ;; Removes the regions whose caller left without removing them (a
  ;; handler's engine dropped while it waited).
  (define (crew-prune!)
    (for-each (lambda (r)
                (when (or (crew-cancelled? r)
                          (and (not (crew-open? r))
                               (fx= 0 (unbox (crew-region-running r)))))
                  (when (fx= 0 (unbox (crew-region-running r)))
                    (crew-remove! r))))
              (unbox *crew-regions*)))

  ;; Claims the next call. Returns its start, or #f when none is left.
  (define (crew-claim! r)
    (let ([next (crew-region-next r)] [chunk (crew-region-chunk r)])
      (let loop ()
        (let ([lo (unbox next)])
          (cond [(not (crew-open? r)) #f]
                [(box-cas! next lo (fx+ lo chunk)) lo]
                [else (loop)])))))

  ;; Makes r's calls until none is left to start. The caller checks the
  ;; clock itself (watch?), since it has no timer of the crew's. Each call's
  ;; lo and hi are set in call, a list of two with the region's arguments on
  ;; its end: (apply proc lo hi args) would cons them, 32 bytes a call.
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

  ;; The caller's share of the calls. A call that raises stops others from
  ;; starting; once the running ones are done, its condition is raised again
  ;; (or the first one, if another call's came first). There is no guard,
  ;; since a guard costs a stack segment per region.
  (define (crew-take-part! r)
    (with-exception-handler
     (lambda (c)
       (crew-error! r c)
       (crew-wait! r)
       (crew-remove! r)
       (raise (unbox (crew-region-error r))))
     (lambda () (crew-calls! r #t (list 0 0)))))

  ;; Waits until no worker is in r, which is closed by now; on core1, at
  ;; most crew-core1-ms past r's deadline (for the canceled calls to
  ;; escape). It spins first, since the calls left are short and a nap lasts
  ;; much longer than it asks for.
  (define (crew-wait! r)
    (let ([give-up (let ([d (crew-region-deadline r)])
                     (and d (+ d crew-core1-ms)))])
      (let loop ([spins 0])
        (unless (crew-done? r)
          (if (fx< spins crew-wait-spins)
              (loop (fx+ spins 1))
              (begin
                (crew-cancelled? r)
                (unless (and give-up (> (now-ms) give-up))
                  (sleep crew-nap)
                  (loop spins))))))))

  ;;; ---------------------------------------------------------------- the API

  ;; Returns the first procedure within x's reach that is not a worklet, or
  ;; #f. A worklet opens only pairs, vectors and boxes (the accessors of
  ;; records and hashtables are out of its reach), so only those are walked,
  ;; each once.
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

  ;; Returns the first stray among a call's arguments (a fresh list from a
  ;; rest argument). Most arguments hold nothing to walk, so they make no
  ;; table.
  (define (crew-stray-among args)
    (and (pair? args)
         (or (crew-stray (car args)) (crew-stray-among (cdr args)))))

  ;; (crew-for start end worklet arg ...) calls (worklet lo hi arg ...) for
  ;; each chunk of [start, end); a chunk is the range divided by four times
  ;; the threads (the workers and the caller).
  (define (crew-for start end proc . args)
    (let ([parts (* 4 (+ (crew-size) 1))])
      (apply crew-for* (max 1 (quotient (+ (- end start) parts -1) parts))
             start end proc args)))

  ;; crew-for with at least chunk indices per call.
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
                                   (and (not p) (+ (now-ms) crew-core1-ms)) p)])
         (crew-prune!)
         (crew-ensure!)
         (crew-push! r)
         (crew-wake!)
         (if p
             (let wait ()   ; a process takes no part, so the desktop runs on
               (unless (crew-done? r)
                 (sleep-ms 1)
                 (crew-cancelled? r)
                 (wait)))
             (begin (crew-take-part! r) (crew-wait! r)))
         (crew-remove! r)
         ;; A region whose calls all ran is done, whatever the clock says
         ;; by now: only one canceled while it ran raises the timeout.
         (cond [(unbox (crew-region-error r)) => raise]
               [(unbox (crew-region-cancelled r))
                (raise (make-timeout-condition 'crew-for))]))]))

  ;; The crew shares out what the core spreads over threads.
  (set-hook! (worklet-spread chunk start end proc . args)
    (apply crew-for* chunk start end proc args))

  ;; A chunk of crew-map: applies f to in's items, and writes the results
  ;; into out.
  (define-worklet (crew-map-chunk lo hi f in out)
    (do ([i lo (fx+ i 1)]) ((fx= i hi))
      (vector-set! out i (f (vector-ref in i)))))

  ;; (map worklet l), with the calls spread over the crew. Returns the
  ;; results in order.
  (define (crew-map f l)
    (let* ([in (list->vector l)] [out (make-vector (vector-length in))])
      (crew-for 0 (vector-length in) crew-map-chunk f in out)
      (vector->list out))))
