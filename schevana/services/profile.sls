;;; (schevana services profile) — the profiler: where the world's time and
;;; memory go, tick by tick, whether or not Monitor shows it. It is
;;; Schevana's own accounting, through the core's hook (with-profile-span,
;;; (schevana core processes)); nothing in an app's code is instrumented.
;;;
;;; The unit is a tick: the steps of core1's loop (schevana-step!) from the
;;; one after a tick up to the next tick. The steps between ticks (input
;;; handled as it comes) are summed into the tick they lead up to; a step
;;; in a quiet spell, when no tick is wanted, is a tick of its own. In a
;;; tick, each span (a phase of core1's loop, a window's handler or
;;; drawing, a surface's draw or tick, a process's turn, the collector)
;;; keeps its self time: its time less that of the spans inside it, so
;;; that the parts add up to the tick. Two phases are waits, since a wait
;;; delays the next tick as much as work does: input-wait, the steps' own
;;; time (mostly the wait for core0's events), and vsync-wait, the
;;; screen's (with core0 on a thread of its own, core1's wait for core0 to
;;; take its frame). Each tick's sums go into a ring of the last 30
;;; seconds (at most 100 ticks a second, and as many uses as its ring
;;; holds), and into per-second sums kept for 10 minutes, with what each
;;; key spent for the last minute.
;;;
;;;   (profile-on! #f)           off: no records, no clock reads; #t: on
;;;   (profile-history! 30 10)   keeps 30 s of ticks, 10 min of seconds
;;;   (profile-totals (profile-seconds))   totals by subject, the most first
;;;   (map profile-tick-phases (profile-slow-ticks))   the ticks that came
;;;                              late, and where their time went
;;;   (profile-flag-report)      every late tick kept, and why
;;;
;;; In the hot path it allocates nothing: the clock is fixnum ns (now-ns),
;;; the open spans are a stack of fixed depth, a tick's and a second's sums
;;; go into tables that are cleared rather than made again, and the
;;; history goes into rings made once and used again in place. Keys are
;;; ids and symbols: a window or a process is kept as its id (and its title
;;; or name when first seen), so the history keeps no closed window or
;;; ended process alive. A step's books are kept under one guard: an error
;;; turns the profiler off, is reported once, and the world goes on. The
;;; profiler is on at boot; its state is kept in define-state, so a reload
;;; keeps the history and whether it is on.

(library (schevana services profile)
  (export
    *profile-on?* *profile-tick-seconds* *profile-minutes* profile-tick-rate
    profile-most-tick-seconds profile-most-minutes profile-tick-uses-kept
    profile-detail-seconds profile-second-uses-most
    profile-second-subjects-most profile-phase-names profile-phase-count
    profile-phase-index *profile-none* profile-table make-profile-table
    profile-table? profile-table-keys profile-table-parts profile-table-phases
    profile-table-ns profile-table-calls profile-table-ticks
    profile-table-longest profile-table-seen profile-table-this
    profile-table-used profile-table-count profile-table-count-set!
    profile-new-table profile-hash profile-slot! profile-fx+! profile-tally!
    profile-clear-table! profile-kind profile-ring make-profile-ring
    profile-ring? profile-ring-seqs profile-ring-fields profile-ring-phases
    profile-new-ring profile-tick-fields profile-second-fields profile-field
    profile-ring-ref profile-ring-set! profile-slot-of profile-new-entries
    profile-put! *profile-ticks-ring* *profile-tick-uses*
    *profile-seconds-ring* *profile-second-uses* *profile-second-subjects*
    *profile-tick-oldest* *profile-tick-newest* *profile-tick-entries*
    *profile-second-oldest* *profile-second-now* *profile-second-entries*
    *profile-subject-entries* profile-stack-size *profile-keys* *profile-parts*
    *profile-phase* *profile-start* *profile-inner* *profile-depth*
    *profile-past* *profile-phase-ns* *profile-tick-table* *profile-tick-ns*
    *profile-second-table* *profile-second-subject-table* *profile-gc-ns*
    *profile-memory* *profile-frames* *profile-cpu* *profile-hidden-at*
    *profile-thread* *profile-plain-collect* *profile-window-names*
    *profile-process-names* profile-thread-id profile-ms profile-thread-cpu
    profile-untimed? profile-begin! profile-open! profile-end! profile-close!
    profile-close-at! profile-collect profile-end-step! profile-tick-done!
    profile-name! profile-trim-ticks! profile-second-at! profile-second-done!
    profile-core0-kept *profile-core0-at* *profile-core0-types*
    *profile-core0-count* *profile-input* profile-core0-event!
    profile-core0-about profile-flags-kept profile-flag-reach profile-flag
    make-profile-flag profile-flag? profile-flag-seq profile-flag-date
    profile-flag-ns profile-flag-period profile-flag-why profile-flag-phases
    profile-flag-cpu profile-flag-shown profile-flag-shown-for
    profile-flag-beside profile-flag-events profile-flag-notes *profile-flags*
    *profile-flag-count* *profile-flag-log* *profile-flag-logged*
    profile-flag-log-most profile-flag-check! profile-flag-keep!
    profile-date-at profile-tick-row profile-tick-notes profile-flags
    profile-flag-count profile-tick-why profile-ns-text profile-why-text
    profile-flag-ticks-text profile-flag-ms-text profile-flag-row-text
    profile-flag-clock profile-event-text profile-flag-before-text
    profile-flag-lines profile-device-lines profile-flag-summary
    profile-flag-write profile-flag-report profile-flag-log!
    profile-flag-log-write! profile-on! profile-on? profile-history!
    profile-clear! profile-ticks profile-seconds profile-newest-tick
    profile-oldest-tick profile-tick-kept? profile-tick-ref profile-second-ref
    profile-ref profile-tick-ns profile-tick-phase-ns profile-tick-end
    profile-tick-ms profile-tick-phase-ms profile-second-phase-ms
    profile-phase-ms profile-phase-ns profile-busy profile-tick-phases
    profile-tick-late? profile-tick-held? profile-slow-ticks profile-subject
    profile-subject-of profile-subject-name profile-use make-profile-use
    profile-use? profile-use-subject profile-use-part profile-use-phase
    profile-use-ms profile-use-calls profile-use-ticks profile-use-longest
    profile-uses profile-tick-uses profile-second-uses profile-subject-is?
    profile-node-ns profile-tick-node-ns profile-tick-node-ms
    profile-second-node-ms profile-subject-ms profile-total make-profile-total
    profile-total? profile-total-what profile-total-ms profile-total-ms-set!
    profile-total-calls profile-total-calls-set! profile-total-ticks
    profile-total-ticks-set! profile-total-longest profile-total-longest-set!
    profile-total-parts profile-total-parts-set! profile-totals)
  (import (chezscheme)
          (only (schevana base) at-load define-hook define-made define-state
                library-layer set-hook! string-join)
          (only (schevana core) *frame-ring-n* *frames-drawn* *gpu-facts*
                *pacer-between?* *profile-span* collector-declining?
                core0-error-text core0-event-name core0-flag-names core0-flags
                core0-hidden? find-proc find-window focused-window in-engine?
                now-ns pacer-period platform-machine-load proc-id proc-name
                proc? procs rec-count report-error! screen-event-seen!
                thread-cpu-ns window window-id window-title window? windows)
          (only (schevana kits inspect) inspect-device inspect-frames))

  (library-layer services)

  (define-state *profile-on?* #t)
  ;; how long the history is: seconds of ticks, and minutes of seconds
  (define-state *profile-tick-seconds* 30)
  (define-state *profile-minutes* 10)

  ;; The most that is kept: ticks a second (a 240 Hz screen ticks 240 times
  ;; a second), seconds of ticks, minutes of seconds, and ticks' uses in
  ;; all.
  (define profile-tick-rate 100)
  (define profile-most-tick-seconds 120)
  (define profile-most-minutes 60)
  (define profile-tick-uses-kept 131072)
  ;; how many seconds keep what each key spent, and the most uses and
  ;; subjects each of them keeps
  (define profile-detail-seconds 60)
  (define profile-second-uses-most 512)
  (define profile-second-subjects-most 128)

  ;; A tick's phases, by index; its spans' self times go to them.
  (define profile-phase-names
    '#(input-wait event timers procs tick render gc other vsync-wait))
  (define-made profile-phase-count (vector-length profile-phase-names))

  (define (profile-phase-index key)
    (case key
      [(event) 1] [(timers) 2] [(procs) 3] [(tick) 4] [(render) 5]
      [(gc) 6] [(vsync-wait) 8] [else 7]))

  ;;; ---------------------------------------------------------------- tables
  ;;; Hash tables by open addressing, in vectors made once. A slot holds a
  ;;; (key part phase), its ns, calls, ticks and longest, the tick that last
  ;;; added to it (by seq) and what it spent in that tick. The slots in use
  ;;; are listed, so that clearing a table visits only them.

  (define-state *profile-none* (list 'none))   ; an empty slot's key

  (define-record-type profile-table
    (nongenerative schevana-profile-table-2)
    (fields keys parts phases ns calls ticks longest seen this used
            (mutable count)))

  (define (profile-new-table n)   ; n a power of 2
    (make-profile-table (make-vector n *profile-none*) (make-vector n #f)
                        (make-fxvector n 0) (make-fxvector n 0)
                        (make-fxvector n 0) (make-fxvector n 0)
                        (make-fxvector n 0) (make-fxvector n -1)
                        (make-fxvector n 0) (make-fxvector n 0) 0))

  (define (profile-hash x)
    (cond [(fixnum? x) (fxlogand x (greatest-fixnum))]
          [(symbol? x) (let ([h (symbol-hash x)]) (if (fixnum? h) h 0))]
          [(string? x) (string-hash x)]
          [(eq? x #t) 1]
          [else 0]))

  ;; Returns the slot of (key part phase) in t, claimed if new, or #f once t
  ;; is three quarters full: a use is dropped rather than overflow t.
  (define (profile-slot! t key part phase)
    (let* ([keys (profile-table-keys t)] [mask (fx- (vector-length keys) 1)]
           [parts (profile-table-parts t)] [phases (profile-table-phases t)])
      (let probe ([i (fxlogand (fxlogxor (profile-hash key)
                                         (fx* 31 (fxlogand (profile-hash part)
                                                           1023))
                                         (fx* 1031 phase))
                               mask)])
        (let ([k (vector-ref keys i)])
          (cond
            [(eq? k *profile-none*)
             (let ([n (profile-table-count t)])
               (and (fx< (fx* 4 n) (fx* 3 mask))
                    (begin
                      (vector-set! keys i key)
                      (vector-set! parts i part)
                      (fxvector-set! phases i phase)
                      (fxvector-set! (profile-table-ns t) i 0)
                      (fxvector-set! (profile-table-calls t) i 0)
                      (fxvector-set! (profile-table-ticks t) i 0)
                      (fxvector-set! (profile-table-longest t) i 0)
                      (fxvector-set! (profile-table-seen t) i -1)
                      (fxvector-set! (profile-table-used t) n i)
                      (profile-table-count-set! t (fx+ n 1))
                      i)))]
            [(and (eqv? k key) (eq? (vector-ref parts i) part)
                  (fx= (fxvector-ref phases i) phase))
             i]
            [else (probe (fxlogand (fx+ i 1) mask))])))))

  (define (profile-fx+! v i n) (fxvector-set! v i (fx+ (fxvector-ref v i) n)))

  ;; Adds ns and calls of tick seq to (key part phase) in t. Its ticks
  ;; count the ticks it ran in, and its longest is the most it spent in
  ;; one.
  (define (profile-tally! t seq key part phase ns calls)
    (let ([i (profile-slot! t key part phase)])
      (when i
        (let ([this (profile-table-this t)] [seen (profile-table-seen t)])
          (if (fx= (fxvector-ref seen i) seq)
              (profile-fx+! this i ns)
              (begin
                (fxvector-set! seen i seq)
                (fxvector-set! this i ns)
                (profile-fx+! (profile-table-ticks t) i 1)))
          (profile-fx+! (profile-table-ns t) i ns)
          (profile-fx+! (profile-table-calls t) i calls)
          (let ([v (profile-table-longest t)])
            (fxvector-set! v i (fxmax (fxvector-ref v i)
                                      (fxvector-ref this i))))))))

  (define (profile-clear-table! t)
    (let ([keys (profile-table-keys t)] [used (profile-table-used t)])
      (do ([j 0 (fx+ j 1)]) ((fx= j (profile-table-count t)))
        (vector-set! keys (fxvector-ref used j) *profile-none*))
      (profile-table-count-set! t 0)))

  ;; The kind of a use's subject: window for a window's, #t for a process's
  ;; (whose turn has the part #t), or #f when the key is its own subject.
  (define (profile-kind key part)
    (cond [(not (fixnum? key)) #f] [(eq? part #t) #t] [else 'window]))

  ;;; ---------------------------------------------------------------- rings
  ;;; The history, made once and used again in place: a ring of ticks (a
  ;;; tick's slot is its seq modulo the ring's size), with their uses in a
  ;;; ring of entries, and a ring of seconds, with the last minute's uses
  ;;; and subjects in rings of their own.

  (define-record-type profile-ring
    (nongenerative schevana-profile-ring)
    (fields seqs fields phases))   ; fields: a vector of fxvectors

  ;; A ring of n slots, each with its seq, k fields and its phases.
  (define (profile-new-ring n k)
    (make-profile-ring (make-fxvector n -1)
                       (list->vector (map (lambda (i) (make-fxvector n 0))
                                          (iota k)))
                       (make-fxvector (fx* n profile-phase-count) 0)))

  ;; A tick's fields: its end and length (ns), collections, their ns, bytes
  ;; allocated, heap, where its uses start in their ring and how many; then
  ;; the frames that reached the screen, what core1 itself ran (ns, by the
  ;; thread's CPU clock), core0's window's flags, core0's events, the
  ;; frames tried so far (inspect-frame-… tells what became of each), and
  ;; the records of the frame last recorded.
  (define profile-tick-fields
    '(end ns gcs gc-ns allocated heap start count
      shown cpu flags input frames records))
  ;; A second's fields: its second by the clock, its ticks, ns, the longest
  ;; tick's ns, the rest as a tick's, and its subjects' start and count.
  (define profile-second-fields
    '(second ticks ns longest gcs gc-ns allocated heap start count
      subjects-start subjects-count))

  (define (profile-field r names name)   ; the fxvector of a field
    (vector-ref (profile-ring-fields r)
                (let loop ([ns names] [i 0])
                  (if (eq? (car ns) name) i (loop (cdr ns) (fx+ i 1))))))

  (define (profile-ring-ref r names name slot)
    (fxvector-ref (profile-field r names name) slot))

  (define (profile-ring-set! r names name slot v)
    (fxvector-set! (profile-field r names name) slot v))

  (define (profile-slot-of r seq) (fxmodulo seq (fxvector-length
                                                 (profile-ring-seqs r))))

  ;; n entries of k fields: keys and parts (vectors); phases, ns and calls;
  ;; and, when k is 7, ticks and longest. A tick's entries have 5 fields:
  ;; for one tick, ticks is 1 and longest is its ns.
  (define (profile-new-entries n k)
    (list->vector (map (lambda (f) (if (fx< f 2)
                                       (make-vector n #f)
                                       (make-fxvector n 0)))
                       (iota k))))

  ;; Copies slot i of table t into entry at of entries e.
  (define (profile-put! e at t i)
    (let ([j (fxmodulo at (vector-length (vector-ref e 0)))])
      (vector-set! (vector-ref e 0) j (vector-ref (profile-table-keys t) i))
      (vector-set! (vector-ref e 1) j (vector-ref (profile-table-parts t) i))
      (fxvector-set! (vector-ref e 2) j
                     (fxvector-ref (profile-table-phases t) i))
      (fxvector-set! (vector-ref e 3) j (fxvector-ref (profile-table-ns t) i))
      (fxvector-set! (vector-ref e 4) j
                     (fxvector-ref (profile-table-calls t) i))
      (when (fx= (vector-length e) 7)
        (fxvector-set! (vector-ref e 5) j
                       (fxvector-ref (profile-table-ticks t) i))
        (fxvector-set! (vector-ref e 6) j
                       (fxvector-ref (profile-table-longest t) i)))))

  (define-state *profile-ticks-ring*
    (profile-new-ring (* profile-tick-rate profile-most-tick-seconds)
                      (length profile-tick-fields)))
  (define-state *profile-tick-uses*
    (profile-new-entries profile-tick-uses-kept 5))
  (define-state *profile-seconds-ring*
    (profile-new-ring (* 60 profile-most-minutes)
                      (length profile-second-fields)))
  (define-state *profile-second-uses*
    (profile-new-entries (* profile-detail-seconds profile-second-uses-most) 7))
  (define-state *profile-second-subjects*
    (profile-new-entries (* profile-detail-seconds profile-second-subjects-most)
                         7))
  ;; the ticks kept, by seq: the oldest and the newest (when none is kept,
  ;; newest is oldest less 1), and how many entries their uses have taken
  ;; in all
  (define-state *profile-tick-oldest* 0)
  (define-state *profile-tick-newest* -1)
  (define-state *profile-tick-entries* 0)
  ;; the seconds: the oldest kept, the one ticks go into now (-1 for none),
  ;; and how many entries their uses and their subjects have taken
  (define-state *profile-second-oldest* 0)
  (define-state *profile-second-now* -1)
  (define-state *profile-second-entries* 0)
  (define-state *profile-subject-entries* 0)

  ;;; ---------------------------------------------------------------- state

  ;; The open spans, by depth: key, part, phase, start, and the time of the
  ;; spans closed inside each (ns); how many are open; and how many opened
  ;; past the stack's depth, which go untimed.
  (define profile-stack-size 64)
  (define-state *profile-keys* (make-vector profile-stack-size #f))
  (define-state *profile-parts* (make-vector profile-stack-size #f))
  (define-state *profile-phase* (make-fxvector profile-stack-size 0))
  (define-state *profile-start* (make-fxvector profile-stack-size 0))
  (define-state *profile-inner* (make-fxvector profile-stack-size 0))
  (define-state *profile-depth* 0)
  (define-state *profile-past* 0)
  ;; this tick's self time by phase, its uses, and its steps' ns so far (a
  ;; tick sums the steps between ticks)
  (define-state *profile-phase-ns* (make-fxvector profile-phase-count 0))
  (define-state *profile-tick-table* (profile-new-table 512))
  (define-state *profile-tick-ns* 0)
  ;; this second's uses and subjects
  (define-state *profile-second-table* (profile-new-table 1024))
  (define-state *profile-second-subject-table* (profile-new-table 256))
  ;; the collector's ns in all (timed in its request handler); and the
  ;; memory at the last tick's end: collections, bytes allocated, and the
  ;; collector's ns
  (define-state *profile-gc-ns* 0)
  (define-state *profile-memory* (make-fxvector 3 0))
  ;; the frames drawn and core1's CPU ns at the last tick's end, and when
  ;; core0's window was last seen hidden
  (define-state *profile-frames* 0)
  (define-state *profile-cpu* 0)
  (define-state *profile-hidden-at* 0)
  ;; the thread being profiled, and Chez's own collect-request handler
  (define-state *profile-thread* 0)
  (define-state *profile-plain-collect* (collect-request-handler))
  ;; windows' titles and processes' names when first seen, by id
  (define-state *profile-window-names* (make-eqv-hashtable))
  (define-state *profile-process-names* (make-eqv-hashtable))

  (define (profile-thread-id) (if (threaded?) (get-thread-id) 0))

  (define (profile-ms ns) (/ ns 1e6))

  ;; Returns the CPU time this thread has used so far, in ns.
  (define (profile-thread-cpu) (thread-cpu-ns))

  ;;; ---------------------------------------------------------------- spans

  ;; Spans in an engine (a process or a handler, which can be suspended
  ;; halfway) or on a thread other than the one profile-on! saw go untimed.
  (define (profile-untimed?)
    (or (in-engine?) (not (eqv? (profile-thread-id) *profile-thread*))))

  ;; Opens a span on the stack. A span outside a step, or past the stack's
  ;; depth, goes untimed. A step starts the stack afresh, closing the spans
  ;; a raise left open.
  (define (profile-begin! key part) (profile-open! key part))

  (define (profile-open! key part)
    (unless (profile-untimed?)
      (let ([d (if (eq? key 'step) 0 *profile-depth*)])
        (when (and (eq? key 'step) (fx> *profile-depth* 0))
          (profile-close! 0))
        (cond
          [(and (fx= d 0) (not (eq? key 'step))) (void)]
          [(fx= d profile-stack-size)
           (set! *profile-past* (fx+ *profile-past* 1))]
          [else
           (vector-set! *profile-keys* d key)
           (vector-set! *profile-parts* d part)
           (fxvector-set! *profile-phase* d
             (cond [(fx= d 0) 0]
                   [(fx= d 1) (profile-phase-index key)]
                   [else (fxvector-ref *profile-phase* (fx- d 1))]))
           (fxvector-set! *profile-inner* d 0)
           (fxvector-set! *profile-start* d (now-ns))
           (set! *profile-depth* (fx+ d 1))]))))

  ;; Closes the innermost open span, or, with outer? (the step's end), the
  ;; step and with it every span a raise left open. (A raise out of a span
  ;; leaves it open: each end after it closes one span, the innermost,
  ;; until the step's end.)
  (define (profile-end! outer?)
    (unless (profile-untimed?)
      (cond [outer? (when (fx> *profile-depth* 0) (profile-close! 0))]
            [(fx> *profile-past* 0) (set! *profile-past*
                                          (fx- *profile-past* 1))]
            [(fx> *profile-depth*
                  1) (profile-close! (fx- *profile-depth* 1))])))

  ;; Closes the span at depth d and those above it: their time counts as
  ;; its own, and what closed inside them as inside it, so the books add
  ;; up. Its self time goes to its phase (the collector's to gc, the wait
  ;; for the screen to vsync-wait) and to its use. Closing the step's span
  ;; ends the step, and the tick with it unless the step came between
  ;; ticks.
  (define (profile-close! d) (profile-close-at! d (now-ns)))

  (define (profile-close-at! d now)
    (let ([inner *profile-inner*])
      (do ([j (fx- *profile-depth* 1) (fx- j 1)]) ((fx<= j d))
        (profile-fx+! inner d (fxvector-ref inner j)))
      (let* ([ns (fx- now (fxvector-ref *profile-start* d))]
             [self (fx- ns (fxvector-ref inner d))]
             [key (vector-ref *profile-keys* d)]
             [phase (fxvector-ref *profile-phase* d)])
        (set! *profile-depth* d)
        (set! *profile-past* 0)
        (if (fx= d 0)
            (profile-end-step! now ns self)
            (begin
              (profile-fx+! inner (fx- d 1) ns)
              (profile-fx+! *profile-phase-ns*
                            (case key [(gc) 6] [(vsync-wait) 8] [else phase])
                            self)
              (profile-tally! *profile-tick-table*
                              (fx+ *profile-tick-newest* 1) key
                              (vector-ref *profile-parts* d) phase self 1))))))

  ;; The collect-request handler: it times the collector's work in all, and
  ;; as a span of its own, gc. A request the collector holds off for later
  ;; (collector-declining?) is neither.
  (define (profile-collect)
    (if (collector-declining?)
        (*profile-plain-collect*)
        (begin
          (profile-begin! 'gc #f)
          (let ([t0 (now-ns)])
            (*profile-plain-collect*)
            (set! *profile-gc-ns* (fx+ *profile-gc-ns* (fx- (now-ns) t0))))
          (profile-end! #f))))

  ;;; ---------------------------------------------------------------- ticks

  ;; The step ended at now, ns long, idle ns of it its own self time (its
  ;; input-wait). It is summed into the tick, which ends with it unless the
  ;; step came between ticks (*pacer-between?*). The books are kept under
  ;; one guard: an error turns the profiler off and is reported once.
  (define (profile-end-step! now ns idle)
    (guard (c [#t (profile-on! #f) (report-error! 'profiler c)])
      (profile-fx+! *profile-phase-ns* 0 idle)
      (set! *profile-tick-ns* (fx+ *profile-tick-ns* ns))
      (unless *pacer-between?*
        (profile-second-at! now)
        (profile-tick-done! now *profile-tick-ns*)
        (set! *profile-tick-ns* 0)
        (profile-clear-table! *profile-tick-table*)
        (do ([i 0 (fx+ i 1)]) ((fx= i profile-phase-count))
          (fxvector-set! *profile-phase-ns* i 0))
        (profile-trim-ticks! now))))

  ;; Keeps a window's title or a process's name (kind window or #t) when
  ;; its id is first seen.
  (define (profile-name! key kind)
    (when kind
      (let ([names (if (eq? kind #t)
                       *profile-process-names*
                       *profile-window-names*)])
        (unless (hashtable-contains? names key)
          (let ([x (if (eq? kind #t) (find-proc key) (find-window key))])
            (hashtable-set! names key
                            (cond [(not x) "?"]
                                  [(eq? kind #t) (proc-name x)]
                                  [else (window-title x)])))))))

  ;; Drops the oldest ticks until those kept are of the last
  ;; *profile-tick-seconds*, at most profile-tick-rate a second of them,
  ;; with uses that their ring still holds.
  (define (profile-trim-ticks! now)
    (let* ([r *profile-ticks-ring*] [names profile-tick-fields]
           [since (fx- now (fx* *profile-tick-seconds* 1000000000))]
           [most (fxmin (fxvector-length (profile-ring-seqs r))
                        (fx* profile-tick-rate *profile-tick-seconds*))]
           [least (fx- *profile-tick-entries* profile-tick-uses-kept)])
      (let loop ()
        (let ([slot (profile-slot-of r *profile-tick-oldest*)])
          (when (and (fx<= *profile-tick-oldest* *profile-tick-newest*)
                     (or (fx>= (fx- *profile-tick-newest* *profile-tick-oldest*)
                               most)
                         (fx< (profile-ring-ref r names 'end slot) since)
                         (fx< (profile-ring-ref r names 'start slot) least)))
            (set! *profile-tick-oldest* (fx+ *profile-tick-oldest* 1))
            (loop))))))

  ;; Makes the second that a tick ending at now goes into the current one.
  ;; A new second first finishes the last one (its uses and subjects go
  ;; into their rings), then starts afresh.
  (define (profile-second-at! now)
    (let* ([r *profile-seconds-ring*] [names profile-second-fields]
           [second (fxquotient now 1000000000)])
      (unless (and (fx>= *profile-second-now* 0)
                   (fx= second (profile-ring-ref
                                r names 'second
                                (profile-slot-of r *profile-second-now*))))
        (when (fx>= *profile-second-now* 0) (profile-second-done!))
        (let* ([seq (fx+ *profile-second-now* 1)] [slot (profile-slot-of r
                                                                         seq)])
          (fxvector-set! (profile-ring-seqs r) slot seq)
          (for-each (lambda (name) (profile-ring-set! r names name slot 0))
                    names)
          (profile-ring-set! r names 'second slot second)
          (do ([i 0 (fx+ i 1)]) ((fx= i profile-phase-count))
            (fxvector-set! (profile-ring-phases r)
                           (fx+ (fx* slot profile-phase-count) i) 0))
          (set! *profile-second-now* seq)
          (set! *profile-second-oldest*
            (fxmax *profile-second-oldest*
                   (fx- seq (fx* 60 profile-most-minutes) -1)))))))

  ;; Finishes the current second: its uses and subjects go into their rings
  ;; (as many as each keeps for a second), and its tables are cleared.
  (define (profile-second-done!)
    (let* ([r *profile-seconds-ring*] [names profile-second-fields]
           [slot (profile-slot-of r *profile-second-now*)])
      (define (keep! t e at most start count)
        (let ([n (fxmin most (profile-table-count t))])
          (do ([j 0 (fx+ j 1)]) ((fx= j n))
            (profile-put! e (fx+ at j) t
                          (fxvector-ref (profile-table-used t) j)))
          (profile-ring-set! r names start slot at)
          (profile-ring-set! r names count slot n)
          (profile-clear-table! t)
          (fx+ at n)))
      (set! *profile-second-entries*
        (keep! *profile-second-table* *profile-second-uses*
               *profile-second-entries* profile-second-uses-most 'start 'count))
      (set! *profile-subject-entries*
        (keep! *profile-second-subject-table* *profile-second-subjects*
               *profile-subject-entries* profile-second-subjects-most
               'subjects-start 'subjects-count))))

  ;;; ---------------------------------------------------------------- core0
  ;;; What core0 said lately, by the clock, in a ring made once, so that a
  ;;; flag can say what came just before it. Mouse motion is too common to
  ;;; keep: it only counts into its tick, as every event does.

  (define profile-core0-kept 256)
  (define-state *profile-core0-at* (make-fxvector profile-core0-kept 0))
  (define-state *profile-core0-types* (make-fxvector profile-core0-kept 0))
  (define-state *profile-core0-count* 0)
  (define-state *profile-input* 0)   ; this tick's events

  (define (profile-core0-event! type)
    (when *profile-on?*
      (set! *profile-input* (fx+ *profile-input* 1))
      (unless (eq? (core0-event-name type) 'mouse-motion)
        (let ([i (fxmodulo *profile-core0-count* profile-core0-kept)])
          (fxvector-set! *profile-core0-at* i (now-ns))
          (fxvector-set! *profile-core0-types* i type)
          (set! *profile-core0-count* (fx+ *profile-core0-count* 1))))))

  ;; Returns what core0 said from seconds before end (by the clock) on, at
  ;; most `most` events (the newest), as ((name . ns after end) ...), the
  ;; oldest first.
  (define (profile-core0-about end seconds most)
    (let loop ([n (- *profile-core0-count* 1)] [left most] [acc '()])
      (if (or (< n 0) (= left 0)
              (<= n (- *profile-core0-count* profile-core0-kept 1)))
          acc
          (let* ([i (modulo n profile-core0-kept)]
                 [at (- (fxvector-ref *profile-core0-at* i) end)])
            (if (< at (* seconds -1000000000))
                acc
                (loop (- n 1) (- left 1)
                      (cons (cons (core0-event-name
                                   (fxvector-ref *profile-core0-types* i))
                                  at)
                            acc)))))))

  ;;; ---------------------------------------------------------------- flags
  ;;; A tick that came late makes a flag. The ticks' ring lets a tick go
  ;;; within seconds; the flags keep it, with all there is to explain it. A
  ;;; flag is made a few ticks later, so that it says what came after the
  ;;; tick too. Few ticks come late, so making a flag may allocate.

  (define profile-flags-kept 1024)
  (define profile-flag-reach 3)   ; the ticks a flag keeps on each side

  ;; A flag holds the tick's seq, the date it ended, its length and the
  ;; period it is late against (ns), why it was late (profile-tick-why), its
  ;; phases ((phase . ns) ...), what core1 ran, the frames that reached the
  ;; screen, how long core0's window had been showing (ns), the ticks around
  ;; it (profile-tick-row), the oldest first, what core0 said around then
  ;; ((name . ns after the tick's end) ...), and lines of what else there
  ;; was to see.
  (define-record-type profile-flag
    (nongenerative schevana-profile-flag-3)
    (fields seq date ns period why phases cpu shown shown-for beside events
            notes))

  (define-state *profile-flags* (make-vector profile-flags-kept #f))
  (define-state *profile-flag-count*
    0)   ; flags in all, since the history was cleared
  ;; the file each flag is written to as it comes, and how many this run
  ;; has written
  (define-state *profile-flag-log* #f)
  (define-state *profile-flag-logged* 0)
  (define profile-flag-log-most 20000)

  ;; Makes a flag of the tick profile-flag-reach ticks back, if it came
  ;; late.
  (define (profile-flag-check!)
    (let ([seq (fx- *profile-tick-newest* profile-flag-reach)])
      (when (and (profile-tick-kept? seq)
                 (profile-tick-late? seq (pacer-period)))
        (profile-flag-keep! seq (pacer-period)))))

  ;; Ends the tick: fills its slot in the ring with its fields and phases,
  ;; puts its uses into the uses' ring and the second's table, and sums
  ;; them by subject into the second's subjects. Then it adds the tick to
  ;; the second's sums and checks for a flag.
  (define (profile-tick-done! now ns)
    (let* ([r *profile-ticks-ring*] [names profile-tick-fields]
           [seq (fx+ *profile-tick-newest* 1)] [slot (profile-slot-of r seq)]
           [sr *profile-seconds-ring*] [sn profile-second-fields]
           [s (profile-slot-of sr *profile-second-now*)]
           [m *profile-memory*] [gcs (collections)]
           [allocated (+ (bytes-allocated) (bytes-deallocated))]
           [t *profile-tick-table*] [at *profile-tick-entries*]
           [count (profile-table-count t)]
           [subjects *profile-second-subject-table*])
      (fxvector-set! (profile-ring-seqs r) slot seq)
      (profile-ring-set! r names 'end slot now)
      (profile-ring-set! r names 'ns slot ns)
      (profile-ring-set! r names 'gcs slot (fx- gcs (fxvector-ref m 0)))
      (profile-ring-set! r names 'gc-ns slot
                         (fx- *profile-gc-ns* (fxvector-ref m 2)))
      (profile-ring-set! r names 'allocated slot
                         (- allocated (fxvector-ref m 1)))
      (profile-ring-set! r names 'heap slot (bytes-allocated))
      (profile-ring-set! r names 'start slot at)
      (profile-ring-set! r names 'count slot count)
      (profile-ring-set! r names 'shown slot
                         (- *frames-drawn* *profile-frames*))
      (set! *profile-frames* *frames-drawn*)
      (let ([cpu (profile-thread-cpu)])
        (profile-ring-set! r names 'cpu slot (- cpu *profile-cpu*))
        (set! *profile-cpu* cpu))
      (when (core0-hidden?) (set! *profile-hidden-at* now))
      (profile-ring-set! r names 'flags slot (core0-flags))
      (profile-ring-set! r names 'input slot *profile-input*)
      (set! *profile-input* 0)
      (profile-ring-set! r names 'frames slot *frame-ring-n*)
      (profile-ring-set! r names 'records slot (rec-count))
      (fxvector-set! m 0 gcs)
      (fxvector-set! m 1 allocated)
      (fxvector-set! m 2 *profile-gc-ns*)
      (do ([i 0 (fx+ i 1)]) ((fx= i profile-phase-count))
        (let ([n (fxvector-ref *profile-phase-ns* i)])
          (fxvector-set! (profile-ring-phases r)
                         (fx+ (fx* slot profile-phase-count) i) n)
          (profile-fx+! (profile-ring-phases sr)
                        (fx+ (fx* s profile-phase-count) i) n)))
      (do ([j 0 (fx+ j 1)]) ((fx= j count))
        (let* ([i (fxvector-ref (profile-table-used t) j)]
               [key (vector-ref (profile-table-keys t) i)]
               [part (vector-ref (profile-table-parts t) i)]
               [kind (profile-kind key part)]
               [n (fxvector-ref (profile-table-ns t) i)]
               [calls (fxvector-ref (profile-table-calls t) i)]
               [seen (profile-table-count subjects)])
          (profile-put! *profile-tick-uses* (fx+ at j) t i)
          (profile-tally! *profile-second-table* seq key part
                          (fxvector-ref (profile-table-phases t) i) n calls)
          (profile-tally! subjects seq key kind 0 n calls)
          ;; a subject new in this second: keep its window's or process's
          ;; name
          (unless (fx= seen (profile-table-count subjects))
            (profile-name! key kind))))
      (set! *profile-tick-entries* (fx+ at count))
      (set! *profile-tick-newest* seq)
      (profile-fx+! (profile-field sr sn 'ticks) s 1)
      (profile-fx+! (profile-field sr sn 'ns) s ns)
      (let ([v (profile-field sr sn 'longest)])
        (fxvector-set! v s (fxmax ns (fxvector-ref v s))))
      (profile-fx+! (profile-field sr sn 'gcs) s
                    (profile-ring-ref r names 'gcs slot))
      (profile-fx+! (profile-field sr sn 'gc-ns) s
                    (profile-ring-ref r names 'gc-ns slot))
      (profile-fx+! (profile-field sr sn 'allocated) s
                    (profile-ring-ref r names 'allocated slot))
      (profile-ring-set! sr sn 'heap s (profile-ring-ref r names 'heap slot))
      (profile-flag-check!)))

  (define (profile-flag-keep! seq period)
    (let* ([end (profile-tick-ns seq 'end)]
           [f (make-profile-flag
               seq (profile-date-at end) (profile-tick-ns seq 'ns) period
               (profile-tick-why seq period) (profile-tick-phases seq)
               (profile-tick-ns seq 'cpu) (profile-tick-ns seq 'shown)
               (- end *profile-hidden-at*)
               (map profile-tick-row
                    (filter profile-tick-kept?
                            (map (lambda (i) (+ seq i (- profile-flag-reach)))
                                 (iota (+ 1 (* 2 profile-flag-reach))))))
               (profile-core0-about end 10 12)
               (profile-tick-notes seq))])
      (vector-set! *profile-flags*
                   (modulo *profile-flag-count* profile-flags-kept) f)
      (set! *profile-flag-count* (+ *profile-flag-count* 1))
      (profile-flag-log-write! f)))

  ;; The date when the clock (now-ns) read ns.
  (define (profile-date-at ns)
    (let ([ago (max 0 (- (now-ns) ns))])
      (time-utc->date
       (subtract-duration (current-time)
                          (make-time 'time-duration (remainder ago 1000000000)
                                     (quotient ago 1000000000))))))

  ;; A tick as a flag keeps the ticks around it: its seq, its length, how
  ;; long it slept, worked and waited for the screen (all ns), its events,
  ;; and the records of the frame last recorded.
  (define (profile-tick-row seq)
    (let ([slept (profile-tick-phase-ns seq 'input-wait)]
          [screen (profile-tick-phase-ns seq 'vsync-wait)]
          [ns (profile-tick-ns seq 'ns)])
      (list seq ns slept (- ns slept screen) screen
            (profile-tick-ns seq 'input) (profile-tick-ns seq 'records))))

  ;; What else there is to see of tick seq, as lines: its frame, core0's
  ;; window and its memory; then, as they are a few ticks later, when the
  ;; flag is made, the world's windows and processes, how frames are
  ;; presented, the machine's load and SDL's last error.
  (define (profile-tick-notes seq)
    (let* ([frames (profile-tick-ns seq 'frames)]
           [before (if (profile-tick-kept? (- seq 1))
                       (profile-tick-ns (- seq 1) 'frames)
                       frames)]
           [rows (inspect-frames (+ 1 (- *frame-ring-n* frames)))]
           [frame (and (> frames before) (pair? rows) (car (last-pair rows)))]
           [names (map (lambda (w)
                         (if (eq? w (focused-window))
                             (format "~a*" (window-title w))
                             (window-title w)))
                       (windows))]
           [loaded (platform-machine-load)]
           [wrong (core0-error-text)])
      (append
       (list
        (if frame
            (format "its frame: ~,1f ms of work, ~a records, ~a extras, ~a \
                     runs, ~a glyphs"
                    (/ (car frame) 1000) (cadr frame) (caddr frame)
                    (cadddr frame) (list-ref frame 4))
            "it drew no frame")
        (format "core0's window: ~a"
                (string-join (map symbol->string
                                  (core0-flag-names
                                   (profile-tick-ns seq 'flags)))
                             " "))
        (format "windows: ~a; ~a processes" (string-join names ", ")
                (length (procs)))
        (format "memory: heap ~,1f MB, ~,1f MB allocated, ~a collections"
                (/ (profile-tick-ns seq 'heap) 1048576.0)
                (/ (profile-tick-ns seq 'allocated) 1048576.0)
                (profile-tick-ns seq 'gcs)))
       (list (format "presenting by ~a"
                     (cdr (assq 'present-mode *gpu-facts*))))
       (if loaded (list (format "the machine's load: ~a" loaded)) '())
       (if (string=? wrong "")
           '()
           (list (format "SDL's last error, maybe an old one: ~a" wrong))))))

  ;; Returns the flags kept, the newest first.
  (define (profile-flags)
    (let ([n *profile-flag-count*])
      (let loop ([i (max 0 (- n profile-flags-kept))] [acc '()])
        (if (= i n)
            acc
            (loop (+ i 1)
                  (cons (vector-ref *profile-flags*
                                    (modulo i profile-flags-kept))
                        acc))))))

  (define (profile-flag-count) *profile-flag-count*)

  ;; What made tick seq late: the biggest single thing in it that could
  ;; have, among what profile-tick-late? counts, so never the screen's hold.
  ;; It is the wait for events, counted only past a period (up to a period,
  ;; it is the wait for the tick), of two kinds: core1 asleep, or core1
  ;; running during it (in SDL, since no span covers that); or the
  ;; collector; or someone's work. Returns (kind ns . who): kind is asleep,
  ;; pump, gc or work, and who, for work, is (subject . part).
  (define (profile-tick-why seq period)
    (let* ([phase (lambda (p) (profile-tick-phase-ns seq p))]
           [over (max 0 (- (phase 'input-wait) period))]
           [work (- (profile-tick-ns seq 'ns) (phase 'input-wait)
                    (phase 'vsync-wait))]
           [ran (- (profile-tick-ns seq 'cpu) work)])
      (fold-left
       (lambda (best c) (if (> (cadr c) (cadr best)) c best))
       (list (if (> (* 2 ran) over) 'pump 'asleep) over)
       (cons* (list 'gc (phase 'gc))
              (map (lambda (u)
                     (cons* 'work (* 1e6 (profile-use-ms u))
                            (profile-use-subject u) (profile-use-part u)))
                   (remp (lambda (u)
                           (memq (profile-use-subject u) '(vsync-wait gc)))
                         (profile-tick-uses seq)))))))

  ;; ns as text: "31.2 ms", "8671.9 s".
  (define (profile-ns-text ns)
    (if (< ns 1000000000)
        (format "~,1f ms" (/ ns 1e6))
        (format "~,1f s" (/ ns 1e9))))

  ;; A why (profile-tick-why) in words.
  (define (profile-why-text why)
    (let ([took (profile-ns-text (cadr why))])
      (case (car why)
        [(asleep) (format "core1 woke ~a past its time" took)]
        [(pump) (format "core1 ran ~a past its time, waiting for events" took)]
        [(gc) (format "the collector took ~a" took)]
        [else
         (let* ([subject (caddr why)] [part (cdddr why)]
                [name (or (profile-subject-name subject)
                          (format "~a" subject))])
           (format "~a took ~a"
                   (if (symbol? part) (format "~a's ~a" name part) name)
                   took))])))

  ;; The ticks around a flag, in ms: "16.7 16.6 [31.2] 2.4 16.8".
  (define (profile-flag-ticks-text f)
    (profile-flag-ms-text f 1))

  (define (profile-flag-ms-text f k)
    (profile-flag-row-text
     f (lambda (b) (format "~,1f" (/ (list-ref b k) 1e6)))))

  (define (profile-flag-row-text f text-of)
    (string-join
     (map (lambda (b)
            (if (= (car b) (profile-flag-seq f))
                (format "[~a]" (text-of b))
                (text-of b)))
          (profile-flag-beside f))
     " "))

  ;; The time of day of a flag: "19:15:08.123".
  (define (profile-flag-clock f)
    (let ([d (profile-flag-date f)]
          [two (lambda (n) (if (< n 10) (format "0~a" n) (format "~a" n)))])
      (format "~a:~a:~a.~a" (two (date-hour d)) (two (date-minute d))
              (two (date-second d))
              (let ([ms (quotient (date-nanosecond d) 1000000)])
                (cond [(< ms 10) (format "00~a" ms)]
                      [(< ms 100) (format "0~a" ms)]
                      [else ms])))))

  ;; An event as a flag shows it: "focus-gained -1203.4 ms".
  (define (profile-event-text e)
    (format "~a ~,1f ms" (car e) (/ (cdr e) 1e6)))

  ;; The last event before a flag's tick ended, for a glance, or "".
  (define (profile-flag-before-text f)
    (let ([before (filter (lambda (e) (< (cdr e) 0)) (profile-flag-events f))])
      (if (null? before)
          ""
          (let ([e (car (last-pair before))])
            (format "~a, ~a ago" (car e) (profile-ns-text (- (cdr e))))))))

  ;; All that is known of a flag, as lines.
  (define (profile-flag-lines f)
    (let* ([of (lambda (p)
                 (let ([x (assq p (profile-flag-phases f))]) (if x (cdr x) 0)))]
           [work (- (profile-flag-ns f) (of 'input-wait) (of 'vsync-wait))]
           [text profile-ns-text])
      (append
       (list
        (format "~a, tick ~a: ~a (a tick is ~a)" (profile-flag-clock f)
                (profile-flag-seq f) (text (profile-flag-ns f))
                (text (profile-flag-period f)))
        (profile-why-text (profile-flag-why f))
        (format "work ~a, of which the collector ~a; core1 ran ~a" (text work)
                (text (of 'gc)) (text (profile-flag-cpu f)))
        (format "slept ~a; the screen ~a (~,1f refreshes)"
                (text (of 'input-wait)) (text (of 'vsync-wait))
                (/ (of 'vsync-wait) (profile-flag-period f) 1.0))
        (format "~a; the window showing for ~a"
                (if (zero? (profile-flag-shown f))
                    "no frame reached the screen"
                    "its frame reached the screen")
                (text (profile-flag-shown-for f)))
        (format "ticks about it, ms: ~a" (profile-flag-ticks-text f))
        (format "  slept: ~a" (profile-flag-ms-text f 2))
        (format "  work: ~a" (profile-flag-ms-text f 3))
        (format "  the screen: ~a" (profile-flag-ms-text f 4))
        (format "  core0's events: ~a"
                (profile-flag-row-text
                 f (lambda (b) (number->string (list-ref b 5)))))
        (format "  records: ~a"
                (profile-flag-row-text
                 f (lambda (b) (number->string (list-ref b 6)))))
        (format "core0 said: ~a"
                (if (null? (profile-flag-events f))
                    "nothing for 10 s"
                    (string-join (map profile-event-text
                                      (profile-flag-events f))
                                 ", "))))
       (profile-flag-notes f))))

  ;; The device that draws, as lines, written once at the top of a report
  ;; or of a run's log.
  (define (profile-device-lines)
    (let ([of (lambda (k) (cdr (assq k (inspect-device))))])
      (list
       (format "driver ~a, presenting by ~a, present modes offered ~a, \
                ~a × ~a pixels"
               (of 'driver) (of 'present-mode) (of 'present-modes)
               (car (of 'pixels)) (cdr (of 'pixels)))
       (let ([d (of 'display)])
         (if d
             (format "display ~a × ~a at ~a/~a Hz, density ~a" (car d) (cadr d)
                     (caddr d) (cadddr d) (list-ref d 4))
             "no display")))))

  ;; The flags in one line: "12 flags: 9 asleep, 3 work"; with more than are
  ;; kept, "5936 flags, the last 1024: 1024 asleep".
  (define (profile-flag-summary)
    (let* ([kinds (map (lambda (f) (car (profile-flag-why f))) (profile-flags))]
           [counts (map (lambda (k)
                          (cons k
                                (length (filter (lambda (x) (eq? x k)) kinds))))
                        '(asleep pump gc work))]
           [some (filter (lambda (c) (> (cdr c) 0)) counts)])
      (format "~a flag~a~a~a" *profile-flag-count*
              (if (= *profile-flag-count* 1) "" "s")
              (if (> *profile-flag-count* profile-flags-kept)
                  (format ", the last ~a" profile-flags-kept)
                  "")
              (if (null? some)
                  ""
                  (format ": ~a"
                          (string-join (map (lambda (c)
                                              (format "~a ~a" (cdr c) (car c)))
                                            some)
                                       ", "))))))

  (define (profile-flag-write f port)
    (newline port)
    (for-each (lambda (line) (fprintf port "~a\n" line))
              (profile-flag-lines f)))

  ;; Writes the device, the summary and every flag kept, the oldest first,
  ;; to port (by default the current output port).
  (define profile-flag-report
    (case-lambda
      [() (profile-flag-report (current-output-port))]
      [(port)
       (for-each (lambda (line) (fprintf port "~a\n" line))
                 (profile-device-lines))
       (fprintf port "~a\n" (profile-flag-summary))
       (for-each (lambda (f) (profile-flag-write f port))
                 (reverse (profile-flags)))]))

  ;; From now on, each flag is also appended to the file at path as it
  ;; comes, so that it outlives this run; with #f, to no file. A run writes
  ;; at most profile-flag-log-most flags, and gives up on a file it cannot
  ;; write.
  (define (profile-flag-log! path)
    (set! *profile-flag-log* path)
    (set! *profile-flag-logged* 0))

  (define (profile-flag-log-write! f)
    (when (and *profile-flag-log*
               (< *profile-flag-logged* profile-flag-log-most))
      (guard (c [#t (set! *profile-flag-log* #f)
                    (report-error! 'profiler c)])
        (call-with-output-file *profile-flag-log*
          (lambda (port)
            (when (zero? *profile-flag-logged*)
              (fprintf port "\n=== a run, its first flag ~a\n"
                       (profile-flag-clock f))
              (for-each (lambda (line) (fprintf port "~a\n" line))
                        (profile-device-lines)))
            (profile-flag-write f port))
          'append)
        (set! *profile-flag-logged* (+ *profile-flag-logged* 1)))))

  ;;; ---------------------------------------------------------------- the API

  ;; (profile-on! #f) turns the profiler off: the hooks are cleared, and
  ;; with them every clock read and record; (profile-on! #t) turns it on
  ;; for the thread that calls it. The history stays; the open spans are
  ;; dropped.
  (define (profile-on! on?)
    (with-interrupts-disabled
      (set! *profile-on?* (and on? #t))
      (set! *profile-depth* 0)
      (set! *profile-past* 0)
      (set! *profile-tick-ns* 0)
      (profile-clear-table! *profile-tick-table*)
      (do ([i 0 (fx+ i 1)]) ((fx= i profile-phase-count))
        (fxvector-set! *profile-phase-ns* i 0))
      (set! *profile-frames* *frames-drawn*)
      (set! *profile-cpu* (profile-thread-cpu))
      (fxvector-set! *profile-memory* 0 (collections))
      (fxvector-set! *profile-memory* 1 (+ (bytes-allocated)
                                           (bytes-deallocated)))
      (fxvector-set! *profile-memory* 2 *profile-gc-ns*)
      (set! *profile-thread* (profile-thread-id))
      (set! *profile-span* (and on? (cons profile-begin! profile-end!)))
      (collect-request-handler
       (if on? profile-collect *profile-plain-collect*))))

  (define (profile-on?) *profile-on?*)

  ;; (profile-history! 30 10) keeps every tick of the last 30 seconds (at
  ;; most 100 a second, and at most 120 seconds), and each second's sums
  ;; for the last 10 minutes (at most 60).
  (define (profile-history! seconds minutes)
    (set! *profile-tick-seconds* (min seconds profile-most-tick-seconds))
    (set! *profile-minutes* (min minutes profile-most-minutes))
    (when (fx>= *profile-tick-newest* 0) (profile-trim-ticks! (now-ns))))

  (define (profile-clear!)
    (set! *profile-flag-count* 0)
    (set! *profile-tick-oldest* (fx+ *profile-tick-newest* 1))
    (set! *profile-second-oldest* (fx+ *profile-second-now* 1)))

  ;;; What the history tells, read in place by seq, a tick's or a second's
  ;;; (a fixnum; the newest is the largest). A seq is good while its ring
  ;;; keeps it: a view that holds seqs (Monitor, paused) loses the oldest as
  ;;; new ticks and seconds take their slots.

  ;; Returns the ticks kept, and the seconds done, the newest first.
  (define (profile-ticks)
    (let loop ([seq *profile-tick-oldest*] [acc '()])
      (if (fx> seq *profile-tick-newest*) acc
          (loop (fx+ seq 1) (cons seq acc)))))

  (define (profile-seconds)
    (let loop ([seq (fxmax *profile-second-oldest*
                           (fx- *profile-second-now*
                                (fx* 60 *profile-minutes*)))]
               [acc '()])
      (if (fx>= seq *profile-second-now*)
          acc
          (loop (fx+ seq 1) (cons seq acc)))))

  ;; The newest tick kept, and the oldest; each is #f when none is kept.
  (define (profile-newest-tick)
    (and (profile-tick-kept? *profile-tick-newest*) *profile-tick-newest*))

  (define (profile-oldest-tick)
    (and (profile-tick-kept? *profile-tick-oldest*) *profile-tick-oldest*))

  (define (profile-tick-kept? seq)
    (and (fx>= seq *profile-tick-oldest*) (fx<= seq *profile-tick-newest*)))

  ;; Reads a tick's field: end (ms, by the clock), ms, gcs, gc-ms,
  ;; allocated or heap (bytes); or a second's: second (by the clock),
  ;; ticks, ms, longest (ms), and the rest as a tick's.
  (define (profile-tick-ref seq name)
    (profile-ref *profile-ticks-ring* profile-tick-fields seq name))

  (define (profile-second-ref seq name)
    (profile-ref *profile-seconds-ring* profile-second-fields seq name))

  (define (profile-ref r names seq name)
    (let ([v (profile-ring-ref r names
                               (case name [(ms) 'ns] [(gc-ms) 'gc-ns]
                                 [else name])
                               (profile-slot-of r seq))])
      (if (memq name '(end ms longest gc-ms)) (profile-ms v) v)))

  ;; A tick's field as kept, or one of its phases: times in whole ns, by
  ;; the clock (now-ns).
  (define (profile-tick-ns seq name)   ; any of profile-tick-fields
    (profile-ring-ref *profile-ticks-ring* profile-tick-fields name
                      (profile-slot-of *profile-ticks-ring* seq)))

  (define (profile-tick-phase-ns seq phase)
    (profile-phase-ns *profile-ticks-ring* seq phase))

  (define (profile-tick-end seq) (profile-tick-ref seq 'end))
  (define (profile-tick-ms seq) (profile-tick-ref seq 'ms))

  ;; The ms of phase (one of profile-phase-names) in a tick, or a second.
  (define (profile-tick-phase-ms seq phase)
    (profile-phase-ms *profile-ticks-ring* seq phase))

  (define (profile-second-phase-ms seq phase)
    (profile-phase-ms *profile-seconds-ring* seq phase))

  (define (profile-phase-ms r seq phase)
    (profile-ms (profile-phase-ns r seq phase)))

  (define (profile-phase-ns r seq phase)
    (let loop ([i 0])
      (if (eq? (vector-ref profile-phase-names i) phase)
          (fxvector-ref (profile-ring-phases r)
                        (fx+ (fx* (profile-slot-of r seq) profile-phase-count)
                             i))
          (loop (fx+ i 1)))))

  ;; A tick's time less its waits, in ms.
  (define (profile-busy seq)
    (- (profile-tick-ms seq) (profile-tick-phase-ms seq 'input-wait)
       (profile-tick-phase-ms seq 'vsync-wait)))

  ;; Where tick seq's time went: ((phase . ns) ...) for every phase that
  ;; took any (the waits too), the most first. They add up to the tick's
  ;; ns.
  (define (profile-tick-phases seq)
    (list-sort (lambda (a b) (fx> (cdr a) (cdr b)))
               (filter (lambda (p) (fx> (cdr p) 0))
                       (map (lambda (phase)
                              (cons phase (profile-tick-phase-ns seq phase)))
                            (vector->list profile-phase-names)))))

  ;; Whether tick seq came late: whether its time, less its wait for the
  ;; screen, is past one and a half periods of period-ns. Half a period
  ;; past, not just past: a tick ends at about a refresh, a little before
  ;; or after it, and one that missed a refresh waited for the next. The
  ;; wait for the screen (vsync-wait; with core0 on a thread of its own,
  ;; core1's wait for core0 to take its frame) is the screen's or core0's,
  ;; which core1 can't shorten: a wait past one and a half periods means
  ;; the tick was held instead (profile-tick-held?), which is shown apart.
  (define (profile-tick-late? seq period-ns)
    (fx> (fx* 2 (fx- (profile-tick-ns seq 'ns)
                     (profile-tick-phase-ns seq 'vsync-wait)))
         (fx* 3 period-ns)))

  (define (profile-tick-held? seq period-ns)
    (fx> (fx* 2 (profile-tick-phase-ns seq 'vsync-wait)) (fx* 3 period-ns)))

  ;; Returns the ticks kept that came late against period-ns (by default
  ;; the pacer's, pacer-period), the newest first.
  (define profile-slow-ticks
    (case-lambda
      [() (profile-slow-ticks (pacer-period))]
      [(period-ns)
       (filter (lambda (seq) (profile-tick-late? seq period-ns))
               (profile-ticks))]))

  ;; A use's subject as readers see it: (window . id), (process . id), or
  ;; the key itself. profile-subject-of gives the subject of a live window
  ;; or process.
  (define (profile-subject key part)
    (case (profile-kind key part)
      [(window) (cons 'window key)]
      [(#t) (cons 'process key)]
      [else key]))

  (define (profile-subject-of x)
    (cond [(window? x) (cons 'window (window-id x))]
          [(proc? x) (cons 'process (proc-id x))]
          [else x]))

  ;; A window's title or a process's name when the profiler first saw it.
  (define (profile-subject-name s)
    (and (pair? s)
         (hashtable-ref (if (eq? (car s) 'window)
                            *profile-window-names*
                            *profile-process-names*)
                        (cdr s) #f)))

  ;; What one key spent, as readers see it: its subject, part (a window
  ;; handler's kind, or #f), phase (a symbol), ms, calls, the ticks it ran
  ;; in, and the most it spent in one (ms).
  (define-record-type profile-use
    (nongenerative schevana-profile-use-5)
    (fields subject part phase ms calls ticks longest))

  ;; At a REPL: #<profile-use (window . 3) draw in render: 1.250 ms, 2 calls>.
  (at-load
   (record-writer (record-type-descriptor profile-use)
     (lambda (u p wr)
       (fprintf p "#<profile-use ~s~a in ~a: ~,3f ms, ~a calls>"
                (profile-use-subject u)
                (if (profile-use-part u) (format " ~s" (profile-use-part u)) "")
                (profile-use-phase u) (profile-use-ms u)
                (profile-use-calls u)))))

  ;; Returns count entries of e from at as uses, new records, or none if e
  ;; has since reused their entries. With whole?, each is a subject's.
  (define (profile-uses e at count held whole?)
    (let ([n (vector-length (vector-ref e 0))] [tick? (fx= (vector-length e)
                                                           5)])
      (if (fx< at (fx- held n))
          '()
          (let loop ([j 0] [acc '()])
            (if (fx= j count)
                acc
                (let* ([i (fxmodulo (fx+ at j) n)]
                       [key (vector-ref (vector-ref e 0) i)]
                       [part (vector-ref (vector-ref e 1) i)]
                       [ns (fxvector-ref (vector-ref e 3) i)])
                  (loop (fx+ j 1)
                        (cons (make-profile-use
                               (if whole?
                                   (profile-subject key
                                                    (if (eq? part #t) #t #f))
                                   (profile-subject key part))
                               (and (not whole?) (not (eq? part #t)) part)
                               (and (not whole?)
                                    (vector-ref profile-phase-names
                                                (fxvector-ref (vector-ref e 2)
                                                              i)))
                               (profile-ms ns)
                               (fxvector-ref (vector-ref e 4) i)
                               (if tick? 1 (fxvector-ref (vector-ref e 5) i))
                               (profile-ms (if tick?
                                               ns
                                               (fxvector-ref (vector-ref e 6)
                                                             i))))
                              acc))))))))

  ;; A tick's uses; a second's (of the last minute), or, with whole? true,
  ;; its subjects' (part and phase #f).
  (define (profile-tick-uses seq)
    (profile-uses *profile-tick-uses* (profile-tick-ref seq 'start)
                  (profile-tick-ref seq 'count) *profile-tick-entries* #f))

  (define (profile-second-uses seq . whole?)
    (let ([whole? (and (pair? whole?) (car whole?))])
      (profile-uses (if whole? *profile-second-subjects* *profile-second-uses*)
                    (profile-second-ref seq (if whole? 'subjects-start 'start))
                    (profile-second-ref seq (if whole? 'subjects-count 'count))
                    (if whole? *profile-subject-entries*
                        *profile-second-entries*)
                    whole?)))

  ;; Whether the entry of key and part (a use's part, or a subject's kind)
  ;; belongs to subject.
  (define (profile-subject-is? subject key part)
    (if (pair? subject)
        (and (eqv? key (cdr subject))
             (eq? (eq? part #t) (eq? (car subject) 'process)))
        (eqv? key subject)))

  ;; What a node spent in count entries of e from at, read in place: a
  ;; subject's ns, or, with use, (part phase), that use's ns.
  (define (profile-node-ns e at count held subject use)
    (let ([n (vector-length (vector-ref e 0))])
      (if (fx< at (fx- held n))
          0
          (let loop ([j 0] [ns 0])
            (if (fx= j count)
                ns
                (let* ([i (fxmodulo (fx+ at j) n)]
                       [part (vector-ref (vector-ref e 1) i)])
                  (loop (fx+ j 1)
                        (if (and (profile-subject-is?
                                  subject (vector-ref (vector-ref e 0) i) part)
                                 (or (not use)
                                     (and (eq? (if (eq? part #t) #f part)
                                               (car use))
                                          (eq? (vector-ref
                                                profile-phase-names
                                                (fxvector-ref (vector-ref e 2)
                                                              i))
                                               (cadr use)))))
                            (fx+ ns (fxvector-ref (vector-ref e 3) i))
                            ns))))))))

  ;; What node, a subject or (subject part phase), spent in a tick (in ms,
  ;; or in whole ns) or in a second of the last minute (in ms).
  (define (profile-tick-node-ns seq node)
    (profile-node-ns *profile-tick-uses* (profile-tick-ref seq 'start)
                     (profile-tick-ref seq 'count) *profile-tick-entries*
                     (if (and (pair? node) (pair? (cdr node))) (car node) node)
                     (and (pair? node) (pair? (cdr node)) (cdr node))))

  (define (profile-tick-node-ms seq node)
    (profile-ms (profile-tick-node-ns seq node)))

  (define (profile-second-node-ms seq node)
    (profile-ms
     (profile-node-ns *profile-second-uses* (profile-second-ref seq 'start)
                      (profile-second-ref seq 'count) *profile-second-entries*
                      (if (and (pair? node) (pair? (cdr node))) (car node) node)
                      (and (pair? node) (pair? (cdr node)) (cdr node)))))

  ;; The ms that subject spent in uses.
  (define (profile-subject-ms uses subject)
    (fold-left (lambda (ms u)
                 (if (equal? (profile-use-subject u) subject)
                     (+ ms (profile-use-ms u))
                     ms))
               0.0 uses))

  ;; What a subject, or one of its parts, spent over some ticks or seconds:
  ;; ms in all, calls, the ticks it ran in, and the most it spent in one
  ;; tick; and, for a subject, its parts, each a total whose what is
  ;; (part . phase).
  (define-record-type profile-total
    (nongenerative schevana-profile-total-2)
    (fields what (mutable ms) (mutable calls) (mutable ticks)
            (mutable longest) (mutable parts)))

  ;; At a REPL: #<profile-total render: 61.905 ms, 1 calls, 1 parts>.
  (at-load
   (record-writer (record-type-descriptor profile-total)
     (lambda (t p wr)
       (fprintf p "#<profile-total ~s: ~,3f ms, ~a calls, ~a parts>"
                (profile-total-what t) (profile-total-ms t)
                (profile-total-calls t) (length (profile-total-parts t))))))

  ;; Returns what seqs spent, as a total per subject, the most first, each
  ;; with its parts, the most first. The seqs are seconds, or ticks with
  ;; ticks? true.
  (define (profile-totals seqs . ticks?)
    (define (total what) (make-profile-total what 0.0 0 0 0.0 '()))
    (define (add! t u)
      (profile-total-ms-set! t (+ (profile-total-ms t) (profile-use-ms u)))
      (profile-total-calls-set! t (+ (profile-total-calls t)
                                     (profile-use-calls u)))
      (profile-total-ticks-set! t (+ (profile-total-ticks t)
                                     (profile-use-ticks u)))
      (profile-total-longest-set!
       t (max (profile-total-longest t) (profile-use-longest u))))
    (define (most-first ts)
      (sort (lambda (a b) (> (profile-total-ms a) (profile-total-ms b))) ts))
    (let ([totals (make-hashtable equal-hash equal?)]
          [ticks? (and (pair? ticks?) (car ticks?))])
      (define (total-of subject)
        (or (hashtable-ref totals subject #f)
            (let ([t (total subject)]) (hashtable-set! totals subject t) t)))
      (for-each
       (lambda (seq)
         (let ([uses (if ticks?
                         (profile-tick-uses seq)
                         (profile-second-uses seq))])
           (for-each
            (lambda (u)
              (let* ([t (total-of (profile-use-subject u))]
                     [what (cons (profile-use-part u) (profile-use-phase u))])
                (add! (or (find (lambda (p)
                                  (equal? (profile-total-what p) what))
                                (profile-total-parts t))
                          (let ([p (total what)])
                            (profile-total-parts-set!
                             t (cons p (profile-total-parts t)))
                            p))
                      u)))
            uses)
           (for-each
            (lambda (u) (add! (total-of (profile-use-subject u)) u))
            (if ticks?   ; a tick's subjects: its uses summed by subject
                (map (lambda (s)
                       (let ([mine (filter (lambda (u)
                                             (equal? (profile-use-subject u) s))
                                           uses)])
                         (make-profile-use s #f #f (profile-subject-ms mine s)
                                           (apply +
                                                  (map profile-use-calls mine))
                                           1 (profile-subject-ms mine s))))
                     (fold-left (lambda (ss u)
                                  (let ([s (profile-use-subject u)])
                                    (if (member s ss) ss (cons s ss))))
                                '() uses))
                (profile-second-uses seq #t)))))
       seqs)
      (most-first
       (map (lambda (t)
              (profile-total-parts-set! t (most-first (profile-total-parts t)))
              t)
            (vector->list (hashtable-values totals))))))

  ;; Loading this library (at boot, or in a reload) sets the hooks as
  ;; *profile-on?* says, and drops the open spans.
  (at-load
   (profile-on! *profile-on?*))
  (set-hook! (screen-event-seen! type) (profile-core0-event! type)))
