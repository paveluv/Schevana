;;; (schevana services allocation) — what the heap does: the allocation
;;; clock, which the profiler reads around each of its spans; a log of
;;; every collection: when it ran and how long, what each generation held
;;; before and after, how long it had been held off, and what was running
;;; when it was asked for; and the tap, which samples the stack to tell
;;; which procedures allocate.
;;;
;;;   (allocation-clock)               bytes allocated so far
;;;   (allocation-collections)         the collections kept, the newest first
;;;   (allocation-collection)          all that is known of the last one
;;;   (allocation-collection seq)      and of the one named
;;;   (allocation-record! #t)          starts the tap; #f stops it
;;;   (allocation-report)              the procedures that allocate most
;;;   (allocation-places)              the same as data, every one
;;;   (allocation-paths)               the tree of call paths
;;;   (allocation-sampled)             the recording's numbers
;;;   (allocation-clear!)              forgets the samples
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
          allocation-collections allocation-collection
          allocation-collection-count allocation-young
          allocation-request! allocation-record! allocation-recording?
          allocation-clear! allocation-paths allocation-places
          allocation-sampled allocation-report)
  (import (chezscheme)
          (only (schevana base) define-made define-state library-layer)
          (only (schevana core) collector-asking? collector-generation-bytes
                now-ns))

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

  ;; Returns how many collections were logged in all: the seq that the
  ;; next one gets.
  (define (allocation-collection-count) *allocation-count*)

  ;; Returns the young generation as the collector has it: bytes, what was
  ;; allocated since the last collection logged, and limit, the growth at
  ;; which Chez asks the collector for the next one, or #f while a request
  ;; is held off.
  (define (allocation-young)
    (let* ([n *allocation-count*]
           [since (if (> n 0)
                      (fxvector-ref allocation-clocks
                                    (modulo (- n 1) allocation-kept))
                      0)]
           [trip (if (and *allocation-recording?*
                          (fx>= *allocation-collected-at* 0))
                     *allocation-trip*
                     (collect-trip-bytes))])
      `((bytes . ,(max 0 (- (allocation-clock) since)))
        (limit . ,(and (< trip (expt 2 40)) trip)))))

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
             (loose . ,(= (ref 'loose) 1))))))

  ;;; ---------------------------------------------------------------- the tap
  ;;; Which procedures allocate: samples of core1's stack, taken a random
  ;;; number of bytes apart while a recording is on.
  ;;;
  ;;; The alarm is Chez's own request for a collection. Chez asks when the
  ;;; young generation has grown by the trip (collect-trip-bytes) since the
  ;;; last collection; while recording, the trip is set a stride ahead of
  ;;; that growth after each request, so Chez asks at the bytes chosen
  ;;; here. A request reaches the collector only when the collector asked
  ;;; for it itself, or when the growth has come to the trip that the
  ;;; collector left, so collections come when they would. The growth is
  ;;; what the clock has moved since the last collection, not a count of
  ;;; the strides asked for: a thread may notice a request long after the
  ;;; bytes that brought it (Chez 10.0.0, when its C code allocates).
  ;;;
  ;;; A sample is the stack as the handler finds it, read in place, weighed
  ;;; by what the clock moved since the request before, and tallied into a
  ;;; tree of call paths under the span that was open. The stack is seen at
  ;;; the thread's first trap after the allocation that passed the trip, so
  ;;; the callers are right and the innermost frame may be a neighbor's.
  ;;; When Chez has another thread run the handler, core1's stack is out of
  ;;; sight, and the bytes stay with the span.

  ;; The most frames of a sample's path that are kept, the innermost ones;
  ;; the most nodes the tree grows to; and the most samples a second: past
  ;; it the stride doubles, and it halves again, down to the stride asked
  ;; for, once samples come four times slower.
  (define allocation-depth-most 128)
  (define allocation-nodes-most 262144)
  (define allocation-samples-most 500)
  ;; The least stride: Chez looks at the trip as a thread takes a segment.
  (define allocation-segment 16384)

  (define-state *allocation-recording?* #f)
  ;; the mean bytes between samples, as asked for and as it is now
  (define-state *allocation-stride* 65536)
  (define-state *allocation-stride-now* 65536)
  ;; the clock at the last collection, which the young generation's growth
  ;; is counted from, or -1 while the tap waits for a collection to count
  ;; from; and the trip that the collector left
  (define-state *allocation-collected-at* -1)
  (define-state *allocation-trip* 0)
  ;; the collections so far and the clock, as a request last left them
  (define-state *allocation-seen* 0)
  (define-state *allocation-sampled-at* 0)
  ;; the samples, the bytes they stand for, and the bytes no sample saw
  (define-state *allocation-samples* 0)
  (define-state *allocation-sampled* 0)
  (define-state *allocation-unseen* 0)
  ;; the random strides' seed; the second samples are counted in (by
  ;; now-ns) and its samples
  (define-state *allocation-seed* 12345)
  (define-state *allocation-second* 0)
  (define-state *allocation-second-samples* 0)
  ;; a sample on its way to the walk: its span's node and its bytes
  (define-state *allocation-node* #f)
  (define-state *allocation-weight* 0)

  ;; The tree of call paths. Node 0 is the root, its children are spans
  ;; (key . part), and under a span lie the procedures (code objects) from
  ;; the outermost caller in. A node's key is in *allocation-node-keys*,
  ;; and its numbers at 5 × node in *allocation-nodes*: its parent, its
  ;; first child and its next sibling (0 for none), the bytes of the
  ;; samples that end at it, and how many they are.
  (define-state *allocation-node-keys* (make-vector 1024 #f))
  (define-state *allocation-nodes* (make-fxvector (* 5 1024) 0))
  (define-state *allocation-node-count* 1)
  ;; a sample's frames, the innermost first
  (define-made allocation-frames (make-vector allocation-depth-most #f))

  (define (allocation-node-ref node field)
    (fxvector-ref *allocation-nodes* (fx+ (fx* node 5) field)))

  (define (allocation-node-set! node field n)
    (fxvector-set! *allocation-nodes* (fx+ (fx* node 5) field) n))

  ;; Adds a node with key under parent and returns it, or #f when the tree
  ;; is as large as it gets. The vectors double as they fill.
  (define (allocation-node-add! parent key)
    (let ([i *allocation-node-count*])
      (and (fx< i allocation-nodes-most)
           (begin
             (when (fx= i (vector-length *allocation-node-keys*))
               (let ([keys (make-vector (fx* 2 i) #f)]
                     [nodes (make-fxvector (fx* 10 i) 0)])
                 (do ([j 0 (fx+ j 1)]) ((fx= j i))
                   (vector-set! keys j (vector-ref *allocation-node-keys* j)))
                 (do ([j 0 (fx+ j 1)]) ((fx= j (fx* 5 i)))
                   (fxvector-set! nodes j (fxvector-ref *allocation-nodes* j)))
                 (set! *allocation-node-keys* keys)
                 (set! *allocation-nodes* nodes)))
             (vector-set! *allocation-node-keys* i key)
             (allocation-node-set! i 0 parent)
             (allocation-node-set! i 2 (allocation-node-ref parent 1))
             (allocation-node-set! parent 1 i)
             (set! *allocation-node-count* (fx+ i 1))
             i))))

  ;; Returns node's child whose key is key (a code object, or a symbol),
  ;; added when there is none.
  (define (allocation-child! node key)
    (let find ([c (allocation-node-ref node 1)])
      (cond [(fx= c 0) (allocation-node-add! node key)]
            [(eq? (vector-ref *allocation-node-keys* c) key) c]
            [else (find (allocation-node-ref c 2))])))

  ;; Returns the root's child for the span key and part, added when there
  ;; is none.
  (define (allocation-span-node! key part)
    (let find ([c (allocation-node-ref 0 1)])
      (cond [(fx= c 0) (allocation-node-add! 0 (cons key part))]
            [(let ([span (vector-ref *allocation-node-keys* c)])
               (and (eqv? (car span) key) (eq? (cdr span) part)))
             c]
            [else (find (allocation-node-ref c 2))])))

  ;; Tallies the sample on its way: its n frames in allocation-frames,
  ;; under its span's node, the outermost first; deeper? when the stack
  ;; went on below them, and they hang under a node of that name. With no
  ;; node to be had the bytes are unseen.
  (define (allocation-tally! n deeper?)
    (let down ([node (if (and deeper? *allocation-node*)
                         (allocation-child! *allocation-node* 'deeper)
                         *allocation-node*)]
               [i (fx- n 1)])
      (cond
        [(not node)
         (set! *allocation-unseen*
           (fx+ *allocation-unseen* *allocation-weight*))]
        [(fx< i 0)
         (allocation-node-set! node 3 (fx+ (allocation-node-ref node 3)
                                           *allocation-weight*))
         (allocation-node-set! node 4 (fx+ (allocation-node-ref node 4) 1))
         (set! *allocation-samples* (fx+ *allocation-samples* 1))
         (set! *allocation-sampled* (fx+ *allocation-sampled*
                                         *allocation-weight*))]
        [else
         (down (allocation-child! node (vector-ref allocation-frames i))
               (fx- i 1))])))

  ;; Calls one of the procedures that Chez keeps for itself, by its name
  ;; there (a library's source is read as R6RS, which has no #% for them).
  (define-syntax allocation-chez
    (syntax-rules ()
      [(_ name argument ...) (($primitive name) argument ...)]))

  ;; The names of the frames that lie between the handler's continuation
  ;; and the code that a request interrupted: the profiler's handler and
  ;; the tap's own, and Chez's way into a handler (docs/CHEZ.md).
  (define allocation-way-in
    '("allocation-sample!" "allocation-request!" "profile-collect"
      "dynamic-wind" "enable-interrupts"))

  ;; Takes the handler's continuation k and tallies the sample on its way.
  ;; The frames are read where they lie, with Chez's own readers of a
  ;; continuation's stack (docs/CHEZ.md): nothing is split off or copied,
  ;; and nothing allocated.
  (define (allocation-walk! k)
    (let loop ([k k] [at #f] [n 0] [in? #t])
      (cond
        [(or (not (allocation-chez $continuation? k))
             (eq? k ($primitive $null-continuation)))
         (allocation-tally! n #f)]
        [(fx= n allocation-depth-most) (allocation-tally! n #t)]
        [else
         (let* ([code
                 (if at
                     (allocation-chez $continuation-stack-return-code k at)
                     (allocation-chez $continuation-return-code k))]
                [below
                 (if at
                     (fx- at
                          (allocation-chez
                           $continuation-stack-return-frame-words k at))
                     (fx- (allocation-chez $continuation-stack-clength k)
                          (allocation-chez
                           $continuation-return-frame-words k)))]
                [in? (and in?
                          (member (allocation-chez $code-name code)
                                  allocation-way-in)
                          #t)]
                [n (if in?
                       n
                       (begin (vector-set! allocation-frames n code)
                              (fx+ n 1)))])
           (if (fx> below 0)
               (loop k below n in?)
               (loop (allocation-chez $continuation-link k) #f n in?)))])))

  ;; Takes a sample of weight bytes for the span key and part: with here?,
  ;; this thread's stack is core1's and is walked; else the bytes stay with
  ;; the span.
  (define (allocation-sample! key part here? weight)
    (set! *allocation-node* (allocation-span-node! key part))
    (set! *allocation-weight* weight)
    (if here?
        (call/cc allocation-walk!)
        (allocation-tally! 0 #f)))

  ;; Counts a sample in its second, and at a second's turn sets the stride
  ;; by how many the last one had.
  (define (allocation-pace!)
    (let ([second (fxquotient (now-ns) 1000000000)])
      (if (fx= second *allocation-second*)
          (set! *allocation-second-samples*
            (fx+ *allocation-second-samples* 1))
          (begin
            (cond
              [(fx> *allocation-second-samples* allocation-samples-most)
               (set! *allocation-stride-now* (fx* 2 *allocation-stride-now*))]
              [(and (fx< (fx* 4 *allocation-second-samples*)
                         allocation-samples-most)
                    (fx> *allocation-stride-now* *allocation-stride*))
               (set! *allocation-stride-now*
                 (fxquotient *allocation-stride-now* 2))])
            (set! *allocation-second* second)
            (set! *allocation-second-samples* 1)))))

  ;; Returns the bytes to the next alarm: from half the stride to one and a
  ;; half, at random, so that no loop keeps step with the samples.
  (define (allocation-next-stride)
    (set! *allocation-seed*
      (fxlogand (fx+ (fx* *allocation-seed* 1103515) 12345) #x7fffffff))
    (fx+ (fxquotient *allocation-stride-now* 2)
         (fxmodulo (fxsrl *allocation-seed* 8) *allocation-stride-now*)))

  ;; Ends a request: sets the next alarm, a stride on from the young
  ;; generation's growth, which starts over when the request collected?.
  ;; An alarm short of the collector's trip never jumps past it. With
  ;; nothing to count from (not armed?, and no collection now), the
  ;; collector's trip stands.
  (define (allocation-alarm-next! collected? armed?)
    (let ([now (allocation-clock)])
      (set! *allocation-seen* (collections))
      (cond [collected? (set! *allocation-collected-at* now)]
            [(not armed?) (set! *allocation-collected-at* -1)])
      (if (fx< *allocation-collected-at* 0)
          (collect-trip-bytes *allocation-trip*)
          (let* ([growth (fxmax 0 (fx- now *allocation-collected-at*))]
                 [next (fx+ growth (allocation-next-stride))])
            (collect-trip-bytes
             (if (and (fx< growth *allocation-trip*)
                      (fx> next *allocation-trip*))
                 *allocation-trip*
                 next))))
      (set! *allocation-sampled-at* now)))

  ;; The profiler's collect-request handler comes here with each request:
  ;; the span that was open (key and part), whether this thread is core1
  ;; (here?), and proceed, which it calls with those three to pass the
  ;; request on to the collector. Off, every request is passed on. On, a
  ;; request that the collector did not ask for is the tap's alarm: a
  ;; sample, passed on only when the young generation has grown to the
  ;; trip that the collector left. Bytes from before the tap had a
  ;; collection to count from, or up to a collection that the collector
  ;; asked for, are no sample's: unseen.
  (define (allocation-request! proceed key part here?)
    (if (not *allocation-recording?*)
        (proceed key part here?)
        (let* ([ran (collections)]
               [now (allocation-clock)]
               ;; a collection that the tap did not see pass leaves it
               ;; with nothing to count from
               [armed? (and (fx>= *allocation-collected-at* 0)
                            (fx= ran *allocation-seen*))]
               [alarm? (and armed? (not (collector-asking?)))]
               [weight (fxmax 0 (fx- now *allocation-sampled-at*))])
          (if alarm?
              (begin
                (allocation-pace!)
                (allocation-sample! key part here? weight))
              (set! *allocation-unseen* (fx+ *allocation-unseen* weight)))
          (when (or (not alarm?)
                    (fx>= (fx- now *allocation-collected-at*)
                          *allocation-trip*))
            (proceed key part here?)
            (set! *allocation-trip* (collect-trip-bytes)))
          (allocation-alarm-next! (not (fx= (collections) ran)) armed?))))

  ;; (allocation-record! #t) starts a recording, with a sample every 64 KB
  ;; or so; (allocation-record! #t (* 16 1024)) with one every 16 KB, the
  ;; least; (allocation-record! #f) stops it, and gives the trip back to
  ;; the collector. The samples add up until (allocation-clear!). The tap
  ;; rides the profiler's handler, so it records only while the profiler
  ;; is on. A recording starts by asking for a collection, to count the
  ;; young generation's growth from; when a frame turn holds that off, it
  ;; starts with the collection at the turn's end.
  (define allocation-record!
    (case-lambda
      [(on?) (allocation-record! on? *allocation-stride*)]
      [(on? stride)
       (with-interrupts-disabled
         (when (and *allocation-recording?*
                    (fx>= *allocation-collected-at* 0))
           (collect-trip-bytes *allocation-trip*))
         (set! *allocation-recording?* (and on? #t))
         (set! *allocation-stride* (max allocation-segment stride))
         (set! *allocation-stride-now* *allocation-stride*)
         (set! *allocation-collected-at* -1)
         (set! *allocation-trip* (collect-trip-bytes))
         (set! *allocation-seen* (collections))
         (set! *allocation-sampled-at* (allocation-clock)))
       (when on? (collect-rendezvous))]))

  (define (allocation-recording?) *allocation-recording?*)

  ;; Forgets every sample.
  (define (allocation-clear!)
    (with-interrupts-disabled
      (set! *allocation-node-keys* (make-vector 1024 #f))
      (set! *allocation-nodes* (make-fxvector (* 5 1024) 0))
      (set! *allocation-node-count* 1)
      (vector-fill! allocation-frames #f)
      (set! *allocation-node* #f)
      (set! *allocation-samples* 0)
      (set! *allocation-sampled* 0)
      (set! *allocation-unseen* 0)
      (set! *allocation-sampled-at* (allocation-clock))))

  ;;; ---------------------------------------------------------------- the
  ;;; tap's readers. They run on core1 between requests; one that a request
  ;;; interrupts may miss the sample it brings.

  ;; What the inspector says of a code object, kept by the code object: a
  ;; reload's old code goes, and its entry with it.
  (define-state *allocation-places* (make-weak-eq-hashtable))

  ;; Returns (name file line) for a code object, each #f when unknown: the
  ;; procedure's name, and where its source begins.
  (define (allocation-place code)
    (or (eq-hashtable-ref *allocation-places* code #f)
        (let* ([name (allocation-chez $code-name code)]
               [place (call-with-values
                        (lambda () ((inspect/object code) 'source-path))
                        (case-lambda
                          [(path line char) (list name path line)]
                          [(path . position) (list name path #f)]
                          [() (list name #f #f)]))])
          (eq-hashtable-set! *allocation-places* code place)
          place)))

  ;; Returns whether a node's key is a code object.
  (define (allocation-code? key)
    (and key (not (pair? key)) (not (symbol? key))))

  ;; Returns a node's children.
  (define (allocation-children node)
    (let each ([c (allocation-node-ref node 1)] [acc '()])
      (if (fx= c 0) acc (each (allocation-node-ref c 2) (cons c acc)))))

  ;; Returns the tree of call paths as plain data. A node is (what self
  ;; total samples child ...): what it is, the bytes of the samples that
  ;; end at it, those bytes with its children's, the samples that end at
  ;; it, and its children, the heaviest first. The root is #f, its children
  ;; are spans, (span key . part), and under them a procedure is (name file
  ;; line); deeper stands for the callers of a path too deep to keep.
  (define (allocation-paths)
    (let node ([i 0])
      (let* ([key (vector-ref *allocation-node-keys* i)]
             [children (sort (lambda (a b) (> (caddr a) (caddr b)))
                             (map node (allocation-children i)))]
             [self (allocation-node-ref i 3)])
        (cons* (cond [(pair? key) (cons 'span key)]
                     [(allocation-code? key) (allocation-place key)]
                     [else key])
               self
               (apply + self (map caddr children))
               (allocation-node-ref i 4)
               children))))

  ;; Returns the procedures sampled, as association lists: name, file and
  ;; line; self, the bytes of the samples whose innermost frame it is; own,
  ;; those of the samples where it is the innermost frame with a source
  ;; (the place in a program's own code that a sample comes down to, when
  ;; the innermost frames are Chez's); total, those of the samples it is
  ;; anywhere in; and samples, how many have it innermost. The heaviest by
  ;; own come first, then by self.
  (define (allocation-places)
    (let ([rows (make-eq-hashtable)])
      (define (add! code field n)
        (let ([row (or (eq-hashtable-ref rows code #f)
                       (let ([row (make-vector 4 0)])
                         (eq-hashtable-set! rows code row)
                         row))])
          (vector-set! row field (+ (vector-ref row field) n))))
      ;; path holds the code objects from here out, and once those among
      ;; them that differ
      (let walk ([i 0] [path '()] [once '()])
        (let* ([key (vector-ref *allocation-node-keys* i)]
               [code? (allocation-code? key)]
               [path (if code? (cons key path) path)]
               [once (if (and code? (not (memq key once)))
                         (cons key once)
                         once)]
               [self (allocation-node-ref i 3)])
          (when (and code? (> self 0))
            (add! key 0 self)
            (add! key 3 (allocation-node-ref i 4))
            (let own ([path path])
              (cond [(null? path) (void)]
                    [(cadr (allocation-place (car path)))
                     (add! (car path) 1 self)]
                    [else (own (cdr path))]))
            (for-each (lambda (code) (add! code 2 self)) once))
          (for-each (lambda (c) (walk c path once))
                    (allocation-children i))))
      (let-values ([(codes counts) (hashtable-entries rows)])
        (map (lambda (entry)
               (let ([place (allocation-place (car entry))]
                     [n (cdr entry)])
                 `((name . ,(car place))
                   (file . ,(cadr place))
                   (line . ,(caddr place))
                   (self . ,(vector-ref n 0))
                   (own . ,(vector-ref n 1))
                   (total . ,(vector-ref n 2))
                   (samples . ,(vector-ref n 3)))))
             (sort (lambda (a b)
                     (let ([a (cdr a)] [b (cdr b)])
                       (or (> (vector-ref a 1) (vector-ref b 1))
                           (and (= (vector-ref a 1) (vector-ref b 1))
                                (> (vector-ref a 0) (vector-ref b 0))))))
                   (map cons (vector->list codes) (vector->list counts)))))))

  ;; Returns the recording's numbers: whether it is on, the stride asked
  ;; for and the stride now, the samples, the bytes they stand for, the
  ;; bytes no sample saw, and the tree's nodes.
  (define (allocation-sampled)
    `((recording . ,*allocation-recording?*)
      (stride . ,*allocation-stride*)
      (stride-now . ,*allocation-stride-now*)
      (samples . ,*allocation-samples*)
      (bytes . ,*allocation-sampled*)
      (unseen . ,*allocation-unseen*)
      (nodes . ,(- *allocation-node-count* 1))))

  ;; (allocation-report) prints the 20 procedures that allocate most, by
  ;; own, or (allocation-report 50) the first 50: each one's share of the
  ;; bytes sampled, its KB, its name, and its file and line.
  (define allocation-report
    (case-lambda
      [() (allocation-report 20)]
      [(most)
       (let ([rows (allocation-places)] [all (max 1 *allocation-sampled*)])
         (printf "~a samples of ~a KB; ~a KB unseen\n" *allocation-samples*
                 (quotient *allocation-sampled* 1024)
                 (quotient *allocation-unseen* 1024))
         (for-each
          (lambda (row)
            (let ([ref (lambda (name) (cdr (assq name row)))])
              (printf "~5,1f%  ~8d KB  ~a  ~a\n"
                      (/ (* 100.0 (ref 'own)) all)
                      (quotient (ref 'own) 1024)
                      (or (ref 'name) "(no name)")
                      (cond [(not (ref 'file)) ""]
                            [(ref 'line)
                             (format "~a:~a" (path-last (ref 'file))
                                     (ref 'line))]
                            [else (path-last (ref 'file))]))))
          (list-head rows (min most (length rows)))))])))
