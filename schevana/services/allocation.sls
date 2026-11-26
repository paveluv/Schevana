;;; (schevana services allocation) — what the heap does: the allocation
;;; clock, which the profiler reads around each of its spans, and a log of
;;; every collection: when it ran and how long, what each generation held
;;; before and after, how long it had been held off, and what was running
;;; when it was asked for.
;;;
;;;   (allocation-clock)               bytes allocated so far
;;;   (allocation-collections)         the collections kept, the newest first
;;;   (allocation-collection)          all that is known of the last one
;;;   (allocation-collection seq)      and of the one named
;;;
;;; A collection is logged from the collect-request handler, the
;;; profiler's ((schevana services profile)), so the log goes with the
;;; profiler: off, nothing is logged. The handler runs on whichever thread
;;; Chez picks, while every other thread is stopped, so a row is written
;;; there, into rings made once: writing one allocates nothing. A request
;;; that the collector holds off (a frame turn holds collections till its
;;; frame is out) is counted, with when the first one came, into the row
;;; of the collection that follows.
;;;
;;; What a generation holds is read on the handler's thread, and Chez
;;; reads low on a thread that did not do all of the collection before:
;;; what another thread moved then (it ran that collection, or lent a hand
;;; while it waited) stays out of this thread's sight until its segments
;;; fill. So a "before" can be low by that much, some KB; what a
;;; generation grew or fell by is still right, unless this collection
;;; collects that very generation.
;;;
;;; The clock is a thread's reading too, and Chez keeps it level across a
;;; collection only for the thread that performs it: on another thread it
;;; steps by what the two hold in the segments they are filling, some KB
;;; either way. The profiler reads the clock on core1. A collection that
;;; core1 asks for runs in a span of the collector's own, which takes the
;;; step; one that another thread performs while a span of a window's is
;;; open leaves the step in that span's bytes, and its row says so
;;; (loose).

(library (schevana services allocation)
  (export allocation-clock allocation-held! allocation-collect!
          allocation-collections allocation-collection)
  (import (chezscheme)
          (only (schevana base) define-made define-state library-layer)
          (only (schevana core) collector-generation-bytes now-ns))

  (library-layer services)

  ;; Returns the bytes allocated so far, by every thread, collected or not:
  ;; a clock that only moves on. Reading it allocates nothing. Another
  ;; thread's bytes arrive a 16 KB segment at a time, as that thread takes
  ;; one.
  (define (allocation-clock) (+ (bytes-allocated) (bytes-deallocated)))

  ;; How many collections are kept, and the generations a row reads: 0 to
  ;; 4, the oldest that the tree's collector uses.
  (define allocation-kept 4096)
  (define allocation-generations 5)

  ;; A collection's numbers, by name: when it ended and how long it took
  ;; (ns, by now-ns's clock), the allocation clock then, the requests held
  ;; off before it and the ns since the first of them, the thread that ran
  ;; it, and whether it left its step in a span's bytes (1) or not (0).
  (define allocation-fields '(at pause clock held held-ns thread loose))

  ;; The log, made once: a ring of rows by seq (a collection's count since
  ;; boot, modulo the ring's size). Each field is an fxvector; before and
  ;; after hold a generation's bytes at row × generations + generation;
  ;; keys and parts hold the span that was open, as the profiler names it.
  (define-state *allocation-rows*
    (map (lambda (name) (cons name (make-fxvector allocation-kept 0)))
         allocation-fields))
  (define-state *allocation-before*
    (make-fxvector (* allocation-kept allocation-generations) 0))
  (define-state *allocation-after*
    (make-fxvector (* allocation-kept allocation-generations) 0))
  (define-state *allocation-keys* (make-vector allocation-kept #f))
  (define-state *allocation-parts* (make-vector allocation-kept #f))
  ;; how many collections were logged in all; the requests held off since
  ;; the last one, and when the first of them came (ns)
  (define-state *allocation-count* 0)
  (define-state *allocation-held* 0)
  (define-state *allocation-held-at* 0)

  (define (allocation-field name) (cdr (assq name *allocation-rows*)))

  ;; The fields' fxvectors, found once, since the handler writes them.
  (define-made allocation-at (allocation-field 'at))
  (define-made allocation-pause (allocation-field 'pause))
  (define-made allocation-clocks (allocation-field 'clock))
  (define-made allocation-helds (allocation-field 'held))
  (define-made allocation-held-ns (allocation-field 'held-ns))
  (define-made allocation-threads (allocation-field 'thread))
  (define-made allocation-looses (allocation-field 'loose))

  ;; Notes a request that the collector held off.
  (define (allocation-held!)
    (when (fx= *allocation-held* 0) (set! *allocation-held-at* (now-ns)))
    (set! *allocation-held* (fx+ *allocation-held* 1)))

  ;; Writes each generation's bytes into v, at row i, as the collector
  ;; reads them: a reading that would be under 0 (the bytes out of this
  ;; thread's sight are more than the generation holds) is 0.
  (define (allocation-read! v i)
    (do ([g 0 (fx+ g 1)]) ((fx= g allocation-generations))
      (fxvector-set! v (fx+ (fx* i allocation-generations) g)
                     (collector-generation-bytes g))))

  ;; Calls handler, the collect-request handler below this one, and logs
  ;; the collection it runs, with key and part, the span that was open
  ;; when it was asked for, and loose?, whether that span's bytes take the
  ;; clock's step. A call that collected nothing leaves no row.
  (define (allocation-collect! handler key part loose?)
    (let ([i (fxmodulo *allocation-count* allocation-kept)]
          [ran (collections)] [t0 (now-ns)])
      (allocation-read! *allocation-before* i)
      (handler)
      (unless (fx= (collections) ran)
        (let ([t1 (now-ns)])
          (allocation-read! *allocation-after* i)
          (fxvector-set! allocation-at i t1)
          (fxvector-set! allocation-pause i (fx- t1 t0))
          (fxvector-set! allocation-clocks i (allocation-clock))
          (fxvector-set! allocation-helds i *allocation-held*)
          (fxvector-set! allocation-held-ns i
                         (if (fx> *allocation-held* 0)
                             (fx- t0 *allocation-held-at*)
                             0))
          (fxvector-set! allocation-threads i
                         (if (threaded?) (get-thread-id) 0))
          (fxvector-set! allocation-looses i (if loose? 1 0))
          (vector-set! *allocation-keys* i key)
          (vector-set! *allocation-parts* i part)
          (set! *allocation-held* 0)
          (set! *allocation-count* (fx+ *allocation-count* 1))))))

  ;;; ---------------------------------------------------------------- readers
  ;;; What the log tells, as plain data. A collection is named by its seq,
  ;;; a fixnum that only grows; a seq is good while the ring keeps it.

  ;; Returns the seqs of the collections kept, the newest first.
  (define (allocation-collections)
    (let ([n *allocation-count*])
      (let loop ([seq (max 0 (- n allocation-kept))] [acc '()])
        (if (= seq n) acc (loop (+ seq 1) (cons seq acc))))))

  (define (allocation-kept? seq)
    (and (fixnum? seq) (< -1 seq *allocation-count*)
         (>= seq (max 0 (- *allocation-count* allocation-kept)))))

  ;; A generation's bytes in row i of v, for each generation.
  (define (allocation-generations-of v i)
    (map (lambda (g) (fxvector-ref v (+ (* i allocation-generations) g)))
         (iota allocation-generations)))

  ;; Which of the collector's passes a collection was, told from what the
  ;; generations held: settle, when generation 4 changed (all into 4: no
  ;; other pass touches it); old, when generation 2 or 3 fell (the pass
  ;; that collects 3 into itself); middle, when generation 1 fell (the pass
  ;; from 1 into 2); else young. A pass that found the generations it
  ;; collects already empty reads as the pass below it.
  (define (allocation-pass before after)
    (let ([fell? (lambda (g) (< (list-ref after g) (list-ref before g)))])
      (cond [(not (= (list-ref after 4) (list-ref before 4))) 'settle]
            [(or (fell? 2) (fell? 3)) 'old]
            [(fell? 1) 'middle]
            [else 'young])))

  ;; Returns all that is known of collection seq (the last one, when none
  ;; is named), as an association list, or #f when there is none or the
  ;; ring has let it go: its seq; its pass (allocation-pass);
  ;; when it ended and its pause (ns); the bytes allocated since the
  ;; collection before it (#f for the oldest kept), and the bytes that
  ;; survived it, which are what the generations above 0 grew by; each
  ;; generation's bytes before and after; the requests held off before it,
  ;; and for how long (ns); the thread that ran it; the span that was open
  ;; when it was asked for, (key . part), as the profiler has it ((gc . #f)
  ;; when the collector itself asked); and whether it is loose: another
  ;; thread ran it while that span, not the collector's, was open, so the
  ;; span's bytes are off by some KB either way.
  (define allocation-collection
    (case-lambda
      [() (allocation-collection (- *allocation-count* 1))]
      [(seq) (allocation-collection-of seq)]))

  (define (allocation-collection-of seq)
    (and (allocation-kept? seq)
         (let* ([i (modulo seq allocation-kept)]
                [before (allocation-generations-of *allocation-before* i)]
                [after (allocation-generations-of *allocation-after* i)]
                [ref (lambda (name) (fxvector-ref (allocation-field name) i))])
           `((seq . ,seq)
             (pass . ,(allocation-pass before after))
             (at . ,(ref 'at))
             (pause . ,(ref 'pause))
             (allocated
              . ,(and (allocation-kept? (- seq 1))
                      (- (ref 'clock)
                         (fxvector-ref (allocation-field 'clock)
                                       (modulo (- seq 1) allocation-kept)))))
             (survived
              . ,(apply + (map (lambda (b a) (max 0 (- a b)))
                               (cdr before) (cdr after))))
             (before . ,before)
             (after . ,after)
             (held . ,(ref 'held))
             (held-ns . ,(ref 'held-ns))
             (thread . ,(ref 'thread))
             (span . ,(cons (vector-ref *allocation-keys* i)
                            (vector-ref *allocation-parts* i)))
             (loose . ,(= (ref 'loose) 1)))))))
