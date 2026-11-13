;;; services/profile.ss — the profiler: where the world's time and memory
;;; go, tick by tick, whether or not Monitor shows it. Level 1: Schevana's
;;; own accounting, through the core's hook (with-profile-span,
;;; src/proc.ss); nothing in an app's code is instrumented.
;;;
;;; The unit is a tick: the steps of core1's loop (schevana-step!) from the
;;; one after a tick's to the next tick's, the steps between ticks (input
;;; handled as it comes) summed into the tick they lead up to; a step not
;;; paced (a test's) ticks, a tick of its own. In it each span (a phase of
;;; core1's loop, a window's handler or drawing, a surface's draw or
;;; tick, a process's turn, the collector) keeps its self time: its time
;;; less the spans inside it, so that the parts add up to the tick; two
;;; are waits, input-wait the steps' own (mostly the wait for core0's
;;; events) and vsync-wait the screen's (with core0 on a thread of its
;;; own, core1's wait for core0 to take its frame), for a wait delays the
;;; next tick as much as work. Each tick's sums go into a ring of the
;;; last 30 seconds (at most 100 ticks a second, and as many uses as its
;;; ring holds), and into per-second sums kept for 10 minutes, with what
;;; each key spent for the last minute.
;;;
;;;   (profile-on! #f)           off: no records, no clock reads; #t: on
;;;   (profile-history! 30 10)   seconds of ticks, minutes of seconds
;;;   (profile-totals (profile-seconds))   by subject, the most first
;;;   (map profile-tick-phases (profile-slow-ticks))   the ticks that came
;;;                              late, and where their time went
;;;   (profile-flag-report)      every late tick kept since, and why
;;;
;;; In the hot path it allocates nothing: the clock is fixnum ns (now-ns),
;;; the spans open a stack of fixed depth, a tick's and a second's sums go
;;; into tables cleared, not made again, and the history into rings made
;;; once and used again in place. Keys are ids and symbols: a window or a
;;; process is kept as its id (and its title or name when first seen), so
;;; the history keeps no closed window or ended process alive. A step's
;;; books are kept under one guard: an error turns the profiler off, said
;;; once, and the world goes on. On at boot; its state is in defvars, so
;;; a reload keeps the history and the flag.

(defvar *profile-on?* #t)
;; how long the history is: seconds of ticks, minutes of seconds
(defvar *profile-tick-seconds* 30)
(defvar *profile-minutes* 10)

;; At most so many ticks a second are kept (back to back, the tests'
;; steps tick thousands a second), so many seconds of ticks and minutes
;; of seconds at the most, and so many ticks' uses in all.
(define profile-tick-rate 100)
(define profile-most-tick-seconds 120)
(define profile-most-minutes 60)
(define profile-tick-uses-kept 131072)
;; the seconds that keep what each key spent, each at most so many
(define profile-detail-seconds 60)
(define profile-second-uses-most 512)
(define profile-second-subjects-most 128)

;; A tick's phases, by index: its self times go to them.
(define profile-phase-names
  '#(input-wait event timers procs tick render gc other vsync-wait))
(define profile-phase-count (vector-length profile-phase-names))

(define (profile-phase-index key)
  (case key
    [(event) 1] [(timers) 2] [(procs) 3] [(tick) 4] [(render) 5]
    [(gc) 6] [(vsync-wait) 8] [else 7]))

;;; ------------------------------------------------------------------ tables
;;; Open addressing in vectors made once: a slot a (key part phase), its
;;; ns, calls, ticks and longest, and the tick that last added to it (by
;;; seq) and what it spent in that tick; the slots in use listed, so that
;;; a table is cleared by them.

(defvar *profile-none* (list 'none))   ; an empty slot's key

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

;; The slot of (key part phase) in t, claimed if new; #f once t is three
;; quarters full: a use is dropped rather than overflow.
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

;; ns and calls of tick seq added to (key part phase) in t: its ticks
;; count the ticks it ran in, and its longest is its most in one.
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

;; A use's subject's kind: a window's (window), a process's (#t: its
;; turn's part), or #f, the key its own.
(define (profile-kind key part)
  (cond [(not (fixnum? key)) #f] [(eq? part #t) #t] [else 'window]))

;;; ------------------------------------------------------------------ rings
;;; The history, made once and used again in place: a ring of ticks (a
;;; tick's slot its seq modulo the ring's size), its uses in a ring of
;;; entries, and a ring of seconds, the last minute's uses and subjects in
;;; rings of their own.

(define-record-type profile-ring
  (nongenerative schevana-profile-ring)
  (fields seqs fields phases))   ; fields: a vector of fxvectors

;; A ring of n slots, each its seq, k fields and its phases.
(define (profile-new-ring n k)
  (make-profile-ring (make-fxvector n -1)
                     (list->vector (map (lambda (i) (make-fxvector n 0))
                                        (iota k)))
                     (make-fxvector (fx* n profile-phase-count) 0)))

;; A tick's fields: its end and length (ns), collections, their ns, bytes
;; allocated, heap, where its uses start in their ring and how many; then
;; the frames that reached the screen, what core1 itself ran (ns, by the
;; thread's CPU clock), core0's window's flags, core0's events, the
;; frames tried so far (what became of each is inspect-frame-…'s), and the
;; records of the frame last recorded.
(define profile-tick-fields
  '(end ns gcs gc-ns allocated heap start count
    shown cpu flags input frames records))
;; A second's: its clock second, ticks, ns, the longest tick's ns, the
;; rest as a tick's, and its subjects' start and count.
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

;; n entries of k fields: keys and parts (vectors); phases, ns, calls,
;; and with k 7 ticks and longest (a tick's: 1, and its ns).
(define (profile-new-entries n k)
  (list->vector (map (lambda (f) (if (fx< f 2)
                                     (make-vector n #f)
                                     (make-fxvector n 0)))
                     (iota k))))

;; Slot i of table t into entry at of entries e.
(define (profile-put! e at t i)
  (let ([j (fxmodulo at (vector-length (vector-ref e 0)))])
    (vector-set! (vector-ref e 0) j (vector-ref (profile-table-keys t) i))
    (vector-set! (vector-ref e 1) j (vector-ref (profile-table-parts t) i))
    (fxvector-set! (vector-ref e 2) j (fxvector-ref (profile-table-phases t) i))
    (fxvector-set! (vector-ref e 3) j (fxvector-ref (profile-table-ns t) i))
    (fxvector-set! (vector-ref e 4) j (fxvector-ref (profile-table-calls t) i))
    (when (fx= (vector-length e) 7)
      (fxvector-set! (vector-ref e 5) j
                     (fxvector-ref (profile-table-ticks t) i))
      (fxvector-set! (vector-ref e 6) j
                     (fxvector-ref (profile-table-longest t) i)))))

(defvar *profile-ticks-ring*
  (profile-new-ring (* profile-tick-rate profile-most-tick-seconds)
                    (length profile-tick-fields)))
(defvar *profile-tick-uses* (profile-new-entries profile-tick-uses-kept 5))
(defvar *profile-seconds-ring*
  (profile-new-ring (* 60 profile-most-minutes)
                    (length profile-second-fields)))
(defvar *profile-second-uses*
  (profile-new-entries (* profile-detail-seconds profile-second-uses-most) 7))
(defvar *profile-second-subjects*
  (profile-new-entries (* profile-detail-seconds profile-second-subjects-most)
                       7))
;; the ticks kept, by seq: the oldest and the newest (none: newest is
;; oldest less 1), and how many entries their uses have taken in all
(defvar *profile-tick-oldest* 0)
(defvar *profile-tick-newest* -1)
(defvar *profile-tick-entries* 0)
;; the seconds: the oldest kept, the one ticks go into now (none: -1),
;; and the entries their uses and subjects have taken
(defvar *profile-second-oldest* 0)
(defvar *profile-second-now* -1)
(defvar *profile-second-entries* 0)
(defvar *profile-subject-entries* 0)

;;; ------------------------------------------------------------------ state

;; The spans open, by depth: key, part, phase, start and the time of the
;; spans closed inside each (ns); how many; and how many opened past the
;; stack's depth, untimed.
(define profile-stack-size 64)
(defvar *profile-keys* (make-vector profile-stack-size #f))
(defvar *profile-parts* (make-vector profile-stack-size #f))
(defvar *profile-phase* (make-fxvector profile-stack-size 0))
(defvar *profile-start* (make-fxvector profile-stack-size 0))
(defvar *profile-inner* (make-fxvector profile-stack-size 0))
(defvar *profile-depth* 0)
(defvar *profile-past* 0)
;; this tick's self time by phase, and its uses, and its steps' ns so far
;; (the steps between ticks it sums)
(defvar *profile-phase-ns* (make-fxvector profile-phase-count 0))
(defvar *profile-tick-table* (profile-new-table 512))
(defvar *profile-tick-ns* 0)
;; the second's uses and subjects
(defvar *profile-second-table* (profile-new-table 1024))
(defvar *profile-second-subject-table* (profile-new-table 256))
;; the collector's ns in all (timed in its request handler); the memory
;; at the last tick's end: collections, bytes allocated, the collector's
(defvar *profile-gc-ns* 0)
(defvar *profile-memory* (make-fxvector 3 0))
;; at the last tick's end, the frames drawn and core1's CPU ns; and when
;; core0's window was last seen hidden
(defvar *profile-frames* 0)
(defvar *profile-cpu* 0)
(defvar *profile-hidden-at* 0)
;; the thread profiled; Chez's own handler of a collect request
(defvar *profile-thread* 0)
(defvar *profile-plain-collect* (collect-request-handler))
;; windows' titles and processes' names when first seen, by id
(defvar *profile-window-names* (make-eqv-hashtable))
(defvar *profile-process-names* (make-eqv-hashtable))

(define (profile-thread-id) (if (threaded?) (get-thread-id) 0))

(define (profile-ms ns) (/ ns 1e6))

;; What this thread has run so far, by its CPU clock: ns.
(define (profile-thread-cpu) (thread-cpu-ns))

;;; ------------------------------------------------------------------ spans

;; Spans in an engine (a process, a handler: one can be suspended
;; halfway) or on another thread than the one profile-on! saw are untimed.
(define (profile-untimed?)
  (or (in-engine?) (not (eqv? (profile-thread-id) *profile-thread*))))

;; A span opens, on the stack: untimed outside a step, and past the
;; stack's depth. A step starts the stack afresh, closing one a raise
;; left open.
(define profile-begin!
  (case-lambda
    [(key part) (profile-open! key part)]
    ;; a span already over, from start to end on now-ns's clock: as if it
    ;; had been open inside the one open innermost
    [(key part start end)
     (let ([d *profile-depth*] [past *profile-past*])
       (profile-open! key part)
       (if (fx> *profile-depth* d)
           (begin
             (fxvector-set! *profile-start* d start)
             (profile-close-at! d end))
           (set! *profile-past* past)))]))

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

;; The span open innermost closes; or with outer? (the step's end) the
;; step, closing all the spans a raise left open with it. (A raise out of
;; a span leaves it open: the ends after it close one span each, the one
;; innermost, until the step's.)
(define (profile-end! outer?)
  (unless (profile-untimed?)
    (cond [outer? (when (fx> *profile-depth* 0) (profile-close! 0))]
          [(fx> *profile-past* 0) (set! *profile-past* (fx- *profile-past* 1))]
          [(fx> *profile-depth* 1) (profile-close! (fx- *profile-depth* 1))])))

;; The span at depth d closes, and those above it with it: their time is
;; its own, and what closed inside them is inside it, so the books add
;; up. Its self time goes to its phase (the collector's to gc, the wait
;; for the screen's to vsync-wait) and to its use; the step's closes the
;; step, and the tick with it unless the step came between ticks.
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

;; The collector's work: timed in all, and a span of its own, gc; a
;; request the collector holds off for later (collector-declining?) is
;; neither.
(define (profile-collect)
  (if (collector-declining?)
      (*profile-plain-collect*)
      (begin
        (profile-begin! 'gc #f)
        (let ([t0 (now-ns)])
          (*profile-plain-collect*)
          (set! *profile-gc-ns* (fx+ *profile-gc-ns* (fx- (now-ns) t0))))
        (profile-end! #f))))

;;; ------------------------------------------------------------------ ticks

;; The step ended at now, ns long, idle of it its own (its input-wait):
;; summed into the tick, which ends with it unless it came between ticks
;; (*pacer-between?*). Its books are kept under one guard: an error turns
;; the profiler off, and is said once.
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

;; The tick's slot in the ring: its fields and phases, its uses into the
;; uses' ring and the second's table, and by subject into the second's.
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
    (profile-ring-set! r names 'shown slot (- *frames-drawn* *profile-frames*))
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
        ;; new in this second: a window's or a process's name kept
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

;; A window's title or a process's name (kind window or #t), kept when
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

;; Only the ticks kept: those of the last *profile-tick-seconds*, at most
;; profile-tick-rate a second of them, whose uses their ring still holds.
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

;; The second a tick that ended at now goes into: a new one puts the last
;; one done, its uses and subjects into their rings, and starts afresh.
(define (profile-second-at! now)
  (let* ([r *profile-seconds-ring*] [names profile-second-fields]
         [second (fxquotient now 1000000000)])
    (unless (and (fx>= *profile-second-now* 0)
                 (fx= second (profile-ring-ref
                              r names 'second
                              (profile-slot-of r *profile-second-now*))))
      (when (fx>= *profile-second-now* 0) (profile-second-done!))
      (let* ([seq (fx+ *profile-second-now* 1)] [slot (profile-slot-of r seq)])
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

;; The second now is done: its uses and subjects into their rings (as
;; many as each holds a second), its tables cleared.
(define (profile-second-done!)
  (let* ([r *profile-seconds-ring*] [names profile-second-fields]
         [slot (profile-slot-of r *profile-second-now*)])
    (define (keep! t e at most start count)
      (let ([n (fxmin most (profile-table-count t))])
        (do ([j 0 (fx+ j 1)]) ((fx= j n))
          (profile-put! e (fx+ at j) t (fxvector-ref (profile-table-used t) j)))
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

;;; ------------------------------------------------------------------ core0
;;; What core0 said lately, by the clock, in a ring made once, so that a
;;; flag can say what came just before it. The mouse's motion is too common
;;; to keep: like every event, it only counts into its tick.

(define profile-core0-kept 256)
(defvar *profile-core0-at* (make-fxvector profile-core0-kept 0))
(defvar *profile-core0-types* (make-fxvector profile-core0-kept 0))
(defvar *profile-core0-count* 0)
(defvar *profile-input* 0)   ; this tick's events

(define (profile-core0-event! type)
  (when *profile-on?*
    (set! *profile-input* (fx+ *profile-input* 1))
    (unless (eq? (core0-event-name type) 'mouse-motion)
      (let ([i (fxmodulo *profile-core0-count* profile-core0-kept)])
        (fxvector-set! *profile-core0-at* i (now-ns))
        (fxvector-set! *profile-core0-types* i type)
        (set! *profile-core0-count* (fx+ *profile-core0-count* 1))))))

;; What it said from seconds before end (by the clock) on, the most kept the
;; newest: ((name . ns after end) ...), the oldest first.
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

;;; ------------------------------------------------------------------ flags
;;; A tick that came late is a flag. The ticks' ring lets it go in seconds;
;;; the flags keep it, with all there is to explain it. One is written a few
;;; ticks on, to say what came after it too. Few ticks come late, so a flag
;;; may allocate.

(define profile-flags-kept 1024)
(define profile-flag-reach 3)   ; the ticks it keeps, each side of it

;; A flag: tick seq, the date it ended, what it took and the period it's
;; late against (ns), why (profile-tick-why), its phases ((phase . ns) ...),
;; what core1 ran, the frames that reached the screen, how long core0's
;; window had been showing (ns),
;; the ticks about it (profile-tick-row), oldest first, what core0 said
;; about then ((name . ns after its end) ...) and lines of what else there
;; was to see.
(define-record-type profile-flag
  (nongenerative schevana-profile-flag-3)
  (fields seq date ns period why phases cpu shown shown-for beside events
          notes))

(defvar *profile-flags* (make-vector profile-flags-kept #f))
(defvar *profile-flag-count* 0)   ; all told, since the history was cleared
;; the file each flag goes to as it comes, and how many have this run
(defvar *profile-flag-log* #f)
(defvar *profile-flag-logged* 0)
(define profile-flag-log-most 20000)

;; The tick a few back, if it came late, into the flags.
(define (profile-flag-check!)
  (let ([seq (fx- *profile-tick-newest* profile-flag-reach)])
    (when (and (profile-tick-kept? seq)
               (profile-tick-late? seq (pacer-period)))
      (profile-flag-keep! seq (pacer-period)))))

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

;; A tick as a flag keeps those about it: its seq, what it took, how long
;; it slept, worked and the screen held core0 (all ns), its events, the
;; records of the frame last recorded.
(define (profile-tick-row seq)
  (let ([slept (profile-tick-phase-ns seq 'input-wait)]
        [screen (profile-tick-phase-ns seq 'vsync-wait)]
        [ns (profile-tick-ns seq 'ns)])
    (list seq ns slept (- ns slept screen) screen
          (profile-tick-ns seq 'input) (profile-tick-ns seq 'records))))

;; What else there is to see of tick seq, as lines: its frame, core0's
;; window, the world's windows and processes, its memory, the machine's load
;; and SDL's last error, those last read a few ticks on.
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

;; The flags kept, the newest first.
(define (profile-flags)
  (let ([n *profile-flag-count*])
    (let loop ([i (max 0 (- n profile-flags-kept))] [acc '()])
      (if (= i n)
          acc
          (loop (+ i 1)
                (cons (vector-ref *profile-flags* (modulo i profile-flags-kept))
                      acc))))))

(define (profile-flag-count) *profile-flag-count*)

;; What made tick seq late: the biggest single thing in it that could, of
;; what profile-tick-late? counts, so never the screen's hold. The wait for
;; events, but only past a period, for up to that is the wait for its tick,
;; and in two kinds: core1 asleep, or running in it (in SDL, for no span
;; covers that); the collector; or someone's work. => (kind ns . who): kind
;; asleep, pump, gc or work; who, work's (subject . part).
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

;; ns in words: "31.2 ms", "8671.9 s".
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

;; The ticks about a flag: "16.7 16.6 [31.2] 2.4 16.8", in ms.
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

;; The clock's time of a flag: "19:15:08.123".
(define (profile-flag-clock f)
  (let ([d (profile-flag-date f)]
        [two (lambda (n) (if (< n 10) (format "0~a" n) (format "~a" n)))])
    (format "~a:~a:~a.~a" (two (date-hour d)) (two (date-minute d))
            (two (date-second d))
            (let ([ms (quotient (date-nanosecond d) 1000000)])
              (cond [(< ms 10) (format "00~a" ms)]
                    [(< ms 100) (format "0~a" ms)]
                    [else ms])))))

;; An event as a flag says it: "focus-gained -1203.4 ms".
(define (profile-event-text e)
  (format "~a ~,1f ms" (car e) (/ (cdr e) 1e6)))

;; What came last before a flag's tick ended, for a glance; or "".
(define (profile-flag-before-text f)
  (let ([before (filter (lambda (e) (< (cdr e) 0)) (profile-flag-events f))])
    (if (null? before)
        ""
        (let ([e (car (last-pair before))])
          (format "~a, ~a ago" (car e) (profile-ns-text (- (cdr e))))))))

;; All that's known of a flag, a line each.
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
                  (string-join (map profile-event-text (profile-flag-events f))
                               ", "))))
     (profile-flag-notes f))))

;; What draws, a line each: once a report or a log.
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

;; The flags in a line: "12 flags: 9 asleep, 3 work"; past what's kept,
;; "5936 flags, the last 1024: 1024 asleep".
(define (profile-flag-summary)
  (let* ([kinds (map (lambda (f) (car (profile-flag-why f))) (profile-flags))]
         [counts (map (lambda (k)
                        (cons k (length (filter (lambda (x) (eq? x k)) kinds))))
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
  (for-each (lambda (line) (fprintf port "~a\n" line)) (profile-flag-lines f)))

;; Every flag kept, the oldest first, to a port (by default the current
;; output's).
(define profile-flag-report
  (case-lambda
    [() (profile-flag-report (current-output-port))]
    [(port)
     (for-each (lambda (line) (fprintf port "~a\n" line))
               (profile-device-lines))
     (fprintf port "~a\n" (profile-flag-summary))
     (for-each (lambda (f) (profile-flag-write f port))
               (reverse (profile-flags)))]))

;; From now on each flag also goes to the end of the file at path as it
;; comes, to outlive this run; #f, to none. A run writes so many at most, and
;; a file it can't write it gives up.
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

;;; ------------------------------------------------------------------ the API

;; (profile-on! #f) turns the profiler off: the hooks go, and with them
;; every clock read and record; (profile-on! #t) turns it on, for the
;; thread that calls it. The history stays; the spans open are dropped.
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

;; (profile-history! 30 10): keep every tick of the last 30 seconds (at
;; most 100 a second, and 120 seconds), and each second's sums for the
;; last 10 minutes (at most 60).
(define (profile-history! seconds minutes)
  (set! *profile-tick-seconds* (min seconds profile-most-tick-seconds))
  (set! *profile-minutes* (min minutes profile-most-minutes))
  (when (fx>= *profile-tick-newest* 0) (profile-trim-ticks! (now-ns))))

(define (profile-clear!)
  (set! *profile-flag-count* 0)
  (set! *profile-tick-oldest* (fx+ *profile-tick-newest* 1))
  (set! *profile-second-oldest* (fx+ *profile-second-now* 1)))

;;; What the history tells, read in place by seq: a tick's or a second's
;;; (a fixnum, the newest the largest). A seq is good while its ring
;;; keeps it: a view that holds seqs (Monitor paused) loses the oldest as
;;; new ticks and seconds take their slots.

;; The ticks kept, and the seconds done, the newest first.
(define (profile-ticks)
  (let loop ([seq *profile-tick-oldest*] [acc '()])
    (if (fx> seq *profile-tick-newest*) acc (loop (fx+ seq 1) (cons seq acc)))))

(define (profile-seconds)
  (let loop ([seq (fxmax *profile-second-oldest*
                         (fx- *profile-second-now* (fx* 60 *profile-minutes*)))]
             [acc '()])
    (if (fx>= seq *profile-second-now*)
        acc
        (loop (fx+ seq 1) (cons seq acc)))))

;; The newest tick kept, or the oldest; or #f.
(define (profile-newest-tick)
  (and (profile-tick-kept? *profile-tick-newest*) *profile-tick-newest*))

(define (profile-oldest-tick)
  (and (profile-tick-kept? *profile-tick-oldest*) *profile-tick-oldest*))

(define (profile-tick-kept? seq)
  (and (fx>= seq *profile-tick-oldest*) (fx<= seq *profile-tick-newest*)))

;; A tick's field: end (ms, by the clock), ms, gcs, gc-ms, allocated or
;; heap (bytes); a second's: second (the clock's), ticks, ms, longest
;; (ms), and the rest as a tick's.
(define (profile-tick-ref seq name)
  (profile-ref *profile-ticks-ring* profile-tick-fields seq name))

(define (profile-second-ref seq name)
  (profile-ref *profile-seconds-ring* profile-second-fields seq name))

(define (profile-ref r names seq name)
  (let ([v (profile-ring-ref r names
                             (case name [(ms) 'ns] [(gc-ms) 'gc-ns] [else name])
                             (profile-slot-of r seq))])
    (if (memq name '(end ms longest gc-ms)) (profile-ms v) v)))

;; A tick's field as kept, or its phase: whole ns, by the clock (now-ns).
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

;; A tick's time but its waits.
(define (profile-busy seq)
  (- (profile-tick-ms seq) (profile-tick-phase-ms seq 'input-wait)
     (profile-tick-phase-ms seq 'vsync-wait)))

;; Where tick seq's time went: ((phase . ns) ...), every phase that took
;; any (its waits too), the most first. They add up to the tick's ns.
(define (profile-tick-phases seq)
  (list-sort (lambda (a b) (fx> (cdr a) (cdr b)))
             (filter (lambda (p) (fx> (cdr p) 0))
                     (map (lambda (phase)
                            (cons phase (profile-tick-phase-ns seq phase)))
                          (vector->list profile-phase-names)))))

;; Did tick seq come late: its time but its wait for the screen, past one
;; and a half periods of period-ns? Half past, not just past: a tick ends
;; about at a refresh, a little before or after it, and one that missed a
;; refresh waited for the next. The wait for the screen (vsync-wait; with
;; core0 on a thread of its own, core1's wait for core0 to take its frame)
;; is the screen's or core0's, which core1 can't shorten: past one and a
;; half periods the tick was held instead, which is shown apart.
(define (profile-tick-late? seq period-ns)
  (fx> (fx* 2 (fx- (profile-tick-ns seq 'ns)
                   (profile-tick-phase-ns seq 'vsync-wait)))
       (fx* 3 period-ns)))

(define (profile-tick-held? seq period-ns)
  (fx> (fx* 2 (profile-tick-phase-ns seq 'vsync-wait)) (fx* 3 period-ns)))

;; The ticks kept that came late (period-ns, by default the pacer's:
;; pacer-period), the newest first.
(define profile-slow-ticks
  (case-lambda
    [() (profile-slow-ticks (pacer-period))]
    [(period-ns)
     (filter (lambda (seq) (profile-tick-late? seq period-ns))
             (profile-ticks))]))

;; A use's subject as readers see it: (window . id), (process . id), or
;; the key itself; profile-subject-of gives a live window's or process's.
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
;; in and its most in one (ms).
(define-record-type profile-use
  (nongenerative schevana-profile-use-5)
  (fields subject part phase ms calls ticks longest))

;; count entries of e from at as uses, new records; none if e has taken
;; their entries again.
(define (profile-uses e at count held whole?)
  (let ([n (vector-length (vector-ref e 0))] [tick? (fx= (vector-length e) 5)])
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

;; A tick's uses; a second's (of the last minute), or its subjects'
;; (whole? true: part and phase #f).
(define (profile-tick-uses seq)
  (profile-uses *profile-tick-uses* (profile-tick-ref seq 'start)
                (profile-tick-ref seq 'count) *profile-tick-entries* #f))

(define (profile-second-uses seq . whole?)
  (let ([whole? (and (pair? whole?) (car whole?))])
    (profile-uses (if whole? *profile-second-subjects* *profile-second-uses*)
                  (profile-second-ref seq (if whole? 'subjects-start 'start))
                  (profile-second-ref seq (if whole? 'subjects-count 'count))
                  (if whole? *profile-subject-entries* *profile-second-entries*)
                  whole?)))

;; Is the entry of key and part (a use's, or a subject's kind) of
;; subject?
(define (profile-subject-is? subject key part)
  (if (pair? subject)
      (and (eqv? key (cdr subject))
           (eq? (eq? part #t) (eq? (car subject) 'process)))
      (eqv? key subject)))

;; What a node spent in count entries of e from at, read in place: a
;; subject's ns, or with use, (part phase), that use's.
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

;; What node, a subject or (subject part phase), spent in a tick (ms, or
;; whole ns), or a second of the last minute.
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

;; What subject spent in uses.
(define (profile-subject-ms uses subject)
  (fold-left (lambda (ms u)
               (if (equal? (profile-use-subject u) subject)
                   (+ ms (profile-use-ms u))
                   ms))
             0.0 uses))

;; What a subject, or one of its parts, spent over some ticks or seconds:
;; ms in all, calls, the ticks it ran in, its most in one tick; and a
;; subject's parts, each a total whose what is (part . phase).
(define-record-type profile-total
  (nongenerative schevana-profile-total-2)
  (fields what (mutable ms) (mutable calls) (mutable ticks)
          (mutable longest) (mutable parts)))

;; By subject, what seconds (seqs) spent, or ticks (ticks? true), the
;; most first, each with its parts, the most first.
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
              (add! (or (find (lambda (p) (equal? (profile-total-what p) what))
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
                                         (apply + (map profile-use-calls mine))
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

;; Loading this file (at boot, or in a reload) sets the hooks as the flag
;; says, the spans open dropped.
(profile-on! *profile-on?*)
(set! *screen-event-seen* (lambda (type) (profile-core0-event! type)))
