;;; system.ss — the main loop, timers, boot and reload.

(defvar *running* #f)
(defvar *timers* '())     ; (#(due-ms thunk fueled?) ...) by due time
(defvar *injected* '())   ; synthetic events waiting to be handled
;; events that came while a reload held the world, newest first
(defvar *held-events* '())
;; whether this step handled events: work that can wait (a text's rows
;; for its scroll bar) waits, so that input's frame comes first
(defvar *input-step?* #f)
(defvar *boot-ms* (now-ms))
;; The pacer: the world's ticks, its frame turns, come from it. Ticks keep
;; to a grid a period apart. With core0 on a thread of its own a tick also
;; waits till core0 has taken the last frame (.work/gpu-design.md 9.12),
;; and once a frame of its has reached the screen by vsync, the screen
;; sets the pace instead (pacer-start). Its rate: screen (a tick a refresh
;; of the screen's) or ticks a second; when the next tick may come on the
;; grid (now-ns); the ticks so far, and when the last began (now-ms).
(defvar *pacer-rate* 'screen)
(defvar *pacer-due* 0)
(defvar *pacer-ticks* 0)
(defvar *pacer-tick-ms* 0)
(defvar *pacer-waits* 0)   ; this step's waits, ns
(defvar *pacer-work* 0)    ; the work of the steps since the last tick, ns
(defvar *pacer-busy* 0)    ; the last tick's work, ns
(defvar *pacer-peak* 0)    ; the most of any tick since it was last asked, ns
(defvar *pacer-began* 0)   ; when the last tick began, ns
(defvar *pacer-frame-ns* 0)   ; when the last tick's frame should show, ns
(defvar *pacer-wanted?* #f)   ; a tick is asked for, to look if not to draw
;; the last frame core0 gave back reached the screen, which held it (vsync,
;; at the screen's rate): the screen paces the ticks while each sends it a
;; frame, till one comes back otherwise; and whether the last tick drew one
(defvar *pacer-shown?* #f)
(defvar *pacer-drew?* #f)
;; when core0's last acquire that the screen held returned (now-ns), the
;; compositor freeing an image: its latches fall a refresh apart from it;
;; or #f. And how long before a latch a tick begins, ns: what frames took
;; lately from their tick till core0 sent them, and the margin.
(defvar *pacer-latch* #f)
(defvar *pacer-lead* 4000000)
;; how much before its latch a frame must be sent to make it, as the
;; screen's reports teach: the compositor's deadline and the GPU's work
(defvar *pacer-margin* 0)
;; the latch the last tick aimed its frame at, just in time; or 0; and
;; when the pacer meant it to begin (now-ns)
(defvar *pacer-aimed* 0)
(defvar *pacer-planned* 0)
;; the first latch the next frame may take, the reports say: the frames
;; before it on their way each take one; or 0
(defvar *pacer-floor* 0)
;; the newest frame whose report the pacer has judged
(defvar *pacer-judged* 0)
;; where the latches fall from the screen's refreshes, ns after one, as
;; last seen; or #f: with it, each report on a refresh says where the next
;; latches are, whether or not an acquire waits for one
(defvar *pacer-latch-phase* #f)
;; how many refreshes past the first after its latch a frame the
;; compositor took there shows, as the reports teach: 0, a compositor that
;; shows it at the refresh after its latch (pacer-margin!)
(defvar *pacer-depth* 0)
;; how long before its latch the frame sent closest to it was sent, ns,
;; among those that made their latch lately (pacer-made!); or #f
(defvar *pacer-made* #f)
;; the first frame of the newest late run, frames judged late one after
;; another; when the pacer judged it (now-ns), or 0 once one is in time;
;; and how many runs have come in a chain, each within 128 frames of the
;; one before
(defvar *pacer-late-run* 0)
(defvar *pacer-late-seen* 0)
(defvar *pacer-late-chain* 0)
;; this step is paced and came between ticks: the profiler sums it into
;; the next tick
(defvar *pacer-between?* #f)

;; (after 1000 (lambda () (notify "a second later"))). Linked in place,
;; after those due no later: a vector and a pair, however many are set.
;; One set in an engine (an app's handler, a process, a timer of theirs)
;; runs in one too, with a fuel; the world's own runs as it is.
(define (after ms thunk)
  (let* ([due (+ (now-ms) ms)]
         [t (vector due thunk (in-engine?))]
         [cell (list t)])
    (if (or (null? *timers*) (< due (vector-ref (car *timers*) 0)))
        (begin (set-cdr! cell *timers*) (set! *timers* cell))
        (let ins ([ts *timers*])
          (if (or (null? (cdr ts)) (< due (vector-ref (cadr ts) 0)))
              (begin (set-cdr! cell (cdr ts)) (set-cdr! ts cell))
              (ins (cdr ts)))))
    t))

;; The timers due, in order. An error in one of the world's own ends the
;; turn's (run-timers! runs under safely); those still due run next turn.
(define (run-timers!)
  (let loop ()
    (when (and (pair? *timers*) (<= (vector-ref (car *timers*) 0) (now-ms)))
      (let ([t (car *timers*)])
        (set! *timers* (cdr *timers*))
        (if (vector-ref t 2)
            (safe-call 'timer (vector-ref t 1)
                       (lambda (c) (report-error! 'timer c)))
            ((vector-ref t 1)))
        (loop)))))

;; (post-main! thunk), from any thread: thunk runs on the main thread at
;; its next step, after the events, in the order each thread posted it,
;; under safely (so a service's thunk calls an app's code under
;; safe-call). Lock-free: neither a post nor the step ever waits. The
;; fences hand main what the poster wrote before it posted: box-cas!
;; orders no memory, and ARM keeps no order of its own.
(defvar *main-mail* (box '()))   ; thunks, the newest first

(define (post-main! thunk)
  (memory-order-release)
  (let loop ()
    (let ([mail (unbox *main-mail*)])
      (unless (box-cas! *main-mail* mail (cons thunk mail)) (loop))))
  (host-world-wake!))

(define (run-main-mail!)
  (let loop ()
    (let ([mail (unbox *main-mail*)])
      (cond [(null? mail)]
            [(box-cas! *main-mail* mail '())
             (memory-order-acquire)
             (for-each (lambda (t) (safely 'jobs t)) (reverse mail))]
            [else (loop)]))))

;; Feed a synthetic event into the world, exactly as if the host sent it:
;; (inject! '(mouse-down 100 100 left 1))
(define (inject! . events)
  (set! *injected* (append *injected* events)))

(define (handle-event! ev)
  (case (car ev)
    [(mouse-move) (apply wm-mouse-move (cdr ev))]
    [(mouse-down) (apply wm-mouse-down (cdr ev))]
    [(mouse-up) (apply wm-mouse-up (cdr ev))]
    [(wheel) (apply wm-wheel (cdr ev))]
    [(key-down) (apply wm-key-down (cdr ev))]
    [(text) (wm-text (cadr ev))]
    [(resize) (wm-screen-resized!)]
    [(expose) (request-frame!)]
    [(mouse-leave) (set! *hover* #f) (request-frame!)]
    [(quit) (quit!)]))

;; A reload that failed or was killed: the world goes on as far as it got.
(define (reload-ended! msg)
  (set! *reloading* #f)
  (safely 'reload (lambda () (invalidate!) (notify msg 'red))))

;; While a process loads the sources (*reloading*, set by load-sources!),
;; the world holds still: no event, timer, tick, frame or other process
;; runs half-loaded code, and the screen stays as it was. A reload whose
;; process was killed ends here.
(define (reload-holding?)
  (when (and *reloading* (not (memq (car *reloading*) *procs*)))
    (reload-ended! (format "Reload stopped while loading ~a"
                           (cdr *reloading*))))
  (and *reloading* #t))

;; Ctrl+C kills the reload and quitting quits; other events wait for it.
(define (hold-event! ev)
  (cond
    [(and (eq? (car ev) 'key-down) (eqv? (cadr ev) #\c)
          (memq 'ctrl (caddr ev)))
     (kill! (car *reloading*))]
    [(eq? (car ev) 'quit) (quit!)]
    [else (set! *held-events* (cons ev *held-events*))]))

;; One turn of the world, and what it took but its waits. Kept with
;; profiling off too, at a few clock reads a step: it says whether a user
;; of the desktop will see a tick missed.
(define (schevana-step! wait-ms . paced)
  (let ([start (now-ns)])
    (set! *pacer-waits* 0)
    (schevana-turn! wait-ms paced)
    (pacer-step-done! (- (now-ns) start))))

;; One turn of the world: events, mail (post-main!), timers, a tick,
;; processes, and on a tick a frame if something asked for one. Paced (the
;; main loop's), it ticks only when a tick is wanted (pacer-wanted?) and
;; due, and its processes run until the frame must be drawn for the next
;; tick; else (a test's) it always ticks, and its processes run 10 ms. The
;; profiler sums the steps between ticks into the next tick.
(define (schevana-turn! wait-ms paced)
  (with-profile-span 'step #f
    (let* ([hold? (reload-holding?)]
           [evs (append (if hold? '() (reverse *held-events*))
                        (pacer-host-events (if (pair? *injected*) 0 wait-ms))
                        *injected*)])
      (unless hold? (set! *held-events* '()))
      (set! *injected* '())
      (set! *input-step?* (pair? evs))
      ;; input may change what's shown: the next tick looks
      (when (pair? evs) (frame-turn-soon!))
      (let each ([evs evs])
        (unless (null? evs)
          (let ([ev (car evs)])
            (safely 'event
                    (lambda () (if hold? (hold-event! ev) (handle-event! ev)))))
          (each (cdr evs)))))
    ;; frames core0 gave back, on its own thread since; on main's, they
    ;; come back as they're published. One sent, the collections its turn
    ;; held off.
    (when (host-forked?) (safely 'render render-frames-back!))
    (collector-after-sent!)
    (let ([ticked?
           (and (not (reload-holding?))
                (begin
                  (run-main-mail!)
                  (safely 'timers run-timers!)
                  (let ([now (and (pair? paced) (now-ns))])
                    (and (or (not now)
                             (and (pacer-wanted?) (>= now (pacer-start))
                                  (not (gpu-frame-waiting?))))
                         (begin
                           (host-trace! 22 0)
                           (collector-hold!)
                           (pacer-tick! now)
                           (frame-ticked! now)
                           #t)))))])
      ;; a step leads up to a tick only while one is wanted; one in a quiet
      ;; spell is its own, as a tick nothing asked for once was
      (set! *pacer-between?* (and (pair? paced) (not ticked?) (pacer-wanted?)))
      (unless (or ticked? (pacer-wanted?) *collector-after*)
        (collector-tick!))
      (safely 'procs
              (lambda () (run-procs! (if (null? paced) 10 (pacer-procs-ms)))))
      ;; a frame a tick at most
      ;; a tick nothing asked a frame of goes on with no guard
      ;; a frame drawn may have moved what's under a still pointer: the next
      ;; tick looks
      (when (and ticked? *dirty* (not (reload-holding?)))
        (set! *dirty* #f)
        (safely 'render render-frame!)
        (when (pair? paced) (pacer-drew!))
        (frame-turn-soon!))
      ;; the frame is out: the collections it held off, and the older
      ;; generations' passes, once core0 has sent it; input that asked for
      ;; no frame shows in none
      (when ticked?
        (collector-frame-out!)
        (unless *dirty* (frame-input-drop!)))
      ;; compute runs and writes no frame took go on their own
      (when (and (gpu-asks-pending?) (not (reload-holding?)))
        (safely 'render gpu-computes-send!)))))

;;; ------------------------------------------------------------------ pacer

;; The host's events, the wait for them no work.
(define (pacer-host-events wait-ms)
  (let* ([t (now-ns)] [events (host-events wait-ms)])
    (pacer-waited! t)
    events))

;; What since now was a wait, for input or for the screen.
(define (pacer-waited! since) (pacer-held! (- (now-ns) since)))

;; ns of waiting, for input or for the screen, told after.
(define (pacer-held! ns) (set! *pacer-waits* (+ *pacer-waits* ns)))

;; A step ended, ns long: its work sums into the tick, which ends with it
;; unless it came between ticks, as the profiler's do.
(define (pacer-step-done! ns)
  (set! *pacer-work* (+ *pacer-work* (- ns *pacer-waits*)))
  (unless *pacer-between?*
    (set! *pacer-busy* *pacer-work*)
    (set! *pacer-peak* (max *pacer-peak* *pacer-work*))
    (set! *pacer-work* 0)))

;; What the last tick took but its waits: past a period, the next is late.
(define (pacer-busy-ms) (/ *pacer-busy* 1e6))

;; The most any tick took since the last call: one spike shows.
(define (pacer-peak-ms!)
  (let ([ms (/ *pacer-peak* 1e6)])
    (set! *pacer-peak* 0)
    ms))

;; (pacer-rate! 60): 60 ticks a second from now on; (pacer-rate! 'screen),
;; the default: a tick a refresh of the screen's. Apps that move by time
;; still read the clock: the screen's rate is its own.
(define (pacer-rate! rate)
  (set! *pacer-rate* rate)
  (set! *pacer-due* 0))
(define (pacer-rate) *pacer-rate*)
(define (pacer-ticks) *pacer-ticks*)
(define (pacer-tick-ms) *pacer-tick-ms*)

;; A tick asked for: windows' frames and the surfaces' look at what
;; changed, and a frame if something asked for one (*dirty*).
(define (frame-turn-soon!) (set! *pacer-wanted?* #t))
(define (pacer-wanted?) (or *pacer-wanted?* *dirty*))

;; When the frame the last tick made should show, ns, the t of a window's
;; 'frame: a period after the last one's, a few after the tick; unpaced (a
;; test's), the tick's own ms, the one read of the clock it makes.
(define (pacer-frame-ns) *pacer-frame-ns*)

;; How many periods after its tick t sits while frames flow; they show
;; later still.
(define pacer-lead-frames 2)

;; When this tick's frame shows: a whole number of periods after the last
;; tick's, so that what moves by it moves as evenly as the screen shows its
;; frames, a refresh apart. The tick, which runs as core0 takes the last
;; frame, says where that grid lies only to a millisecond or so, so t
;; follows pacer-lead-frames periods past it slowly, a 256th of the way a
;; tick and never more than 0.1 ms; a period a tick, unless that would put
;; it behind the tick itself (ticks slower than the screen, a frame on
;; every other refresh), when it steps as many whole periods as keep it
;; ahead. After a pause, a period from the tick: the frames that follow
;; fill the screen's queue faster than a period apart, and carry t further
;; ahead of its tick, toward where it follows.
(define (pacer-next-frame-ns now)
  (let* ([p (if (eq? *pacer-rate* 'screen) (host-frame-ns) (pacer-period))]
         [next (+ *pacer-frame-ns* p)]
         [behind (- (+ now (* pacer-lead-frames p)) next)])
    (cond [(> (- now *pacer-frame-ns*) (* 3 p)) (+ now p)]
          [(< next now) (+ next (* p (quotient (+ (- now next) p -1) p)))]
          [else (+ next (max -100000 (min 100000 (quotient behind 256))))])))

;; A tick's period, ns: a 500th shorter than the refresh the screen
;; reports, more than a report is off (a rate truncated to the mHz, or
;; rounded to the Hz), so that the grid never holds back a tick the screen
;; is ready for; and less than the 0.1 ms a tick's t may move, so that
;; with no screen to hold the ticks t keeps to the clock. Or a fixed
;; rate's.
(define (pacer-period)
  (if (eq? *pacer-rate* 'screen)
      (let ([p (host-frame-ns)]) (- p (quotient p 500)))
      (quotient 1000000000 *pacer-rate*)))

;; When the next tick may begin: a little before its time (2 ms), room
;; for the clock's and the screen's jitter, so that its frame is in time
;; for the refresh. Once a frame has reached the screen by vsync, the
;; screen sets the pace: the next tick also waits till core0 takes the
;; frame this one sent, so it may come as soon as half a period after
;; this one, and a screen a little faster than its report, or a queue
;; refilling after a pause, is never held back by the grid. Frames the
;; screen had no room for come back at once, and put the grid back on.
;; Where the screen's reports place the compositor's latches (Wayland's,
;; as yet), with one seen in the last second, it begins just in time
;; instead (pacer-just-in-time).
(define (pacer-start)
  (cond
    [(pacer-on-latch?) (pacer-just-in-time)]
    [*pacer-shown?* (- (+ *pacer-began* (quotient (pacer-period) 2)) 2000000)]
    [else (- *pacer-due* 2000000)]))

;; Whether ticks keep to the compositor's latches now: the screen pacing
;; (the last frame back came by vsync), and the reports placing a latch
;; seen in the last second; so also while this tick's frame is on its way,
;; when a tick by the grid would be one too many. A wait for the next tick
;; is then a wait for the screen.
(define (pacer-on-latch?)
  (and *pacer-shown?* *pacer-latch* *pacer-latch-phase*
       (< (- (now-ns) *pacer-latch*) 1000000000)))

;; The next tick, just in time for the compositor's next latch: the lead
;; before the latch it aims at (pacer-aim), a later one than this tick's.
;; Its frame, published a lead later, goes straight into an acquire that
;; the latch ends, with the input that came till it began; rather than a
;; refresh early, waiting for an image with input a refresh old.
(define (pacer-just-in-time) (- (pacer-aim) *pacer-lead*))

;; The latch the next tick aims at: the first, a refresh apart from the
;; last seen, a lead after this tick began, after the latch this tick
;; aimed at, which its frame holds, and not before the floor: a frame
;; that came late moves the ones after it.
(define (pacer-aim)
  (let* ([r (host-frame-ns)] [half (quotient r 2)]
         [after (- (max (+ *pacer-began* *pacer-lead*)
                        (+ *pacer-aimed* half)
                        (- *pacer-floor* half))
                   *pacer-latch*)])
    (+ *pacer-latch* (* r (if (> after 0) (quotient (+ after r -1) r) 0)))))

;; A frame core0 gave back, its number n: if the screen held its acquire,
;; the acquire's end is the compositor's latch, else the newest report
;; places it. The newest report also says where the frames on their way
;; will show, each a latch after the one before, the compositor's depth
;; past its own (the floor), and is
;; judged (pacer-behind!); n's own time to its send teaches the lead. The
;; reports read are the newest in: how many frames behind they come
;; differs by compositor, GPU and rate (a frame back; four, under Mutter's
;; triple buffering at 120 Hz).
(define (pacer-latch! n)
  (when (>= *pacer-judged* n)            ; frames numbered anew
    (set! *pacer-judged* 0))
  (let* ([r (host-frame-ns)]
         [began (host-frame-report n 8)] [ended (host-frame-report n 9)]
         [held? (and began ended (> ended 0) (> (- ended began) 1000000))]
         [m (pacer-reported-before n)]
         [refresh (and m (pacer-refresh-seen m))])
    (when m (pacer-judge! m r))
    (cond
      [held?
       (set! *pacer-latch* ended)
       (when refresh
         (set! *pacer-latch-phase* (modulo (- ended refresh) r)))]
      [(and refresh *pacer-latch-phase*)
       (set! *pacer-latch* (+ refresh *pacer-latch-phase*))])
    (when (and refresh *pacer-latch-phase*)
      (set! *pacer-floor*
        (+ refresh *pacer-latch-phase*
           (* r (- *frame-number* m *pacer-depth*)))))
    (pacer-need! n r)))

;; The newest frame before n the screen has reported on, shown or dropped,
;; among the eight before it; else #f.
(define (pacer-reported-before n)
  (let loop ([m (- n 1)])
    (and (> m (- n 9)) (> m 0)
         (if (memv (host-frame-report m 1) '(1 2)) m (loop (- m 1))))))

;; Each frame up to m whose report is in, and not judged yet, judged once
;; (pacer-behind!), from at most eight back.
(define (pacer-judge! m r)
  (let loop ([k (max (+ *pacer-judged* 1) (- m 8))])
    (unless (> k m)
      (set! *pacer-judged* k)
      (pacer-behind! k r)
      (loop (+ k 1)))))

;; How fast what the pacer learned fades, ns: a frame's slow spike in half
;; a second; a margin the screen taught in a minute, so that a frame comes
;; late to probe it only now and then.
(define pacer-lead-fade 500000000)
(define pacer-margin-fade 60000000000)

;; Frame n, its report in, aimed at a latch: late if it showed a refresh
;; or more after the one aimed for, the first after the latch and the
;; compositor's depth on. Sent about the margin before the latch, as the
;; pacer sends them, that was too little: the margin grows past it, by an
;; eighth of a refresh (pacer-margin!); a run of late frames sent alike
;; raises it once. Sent well before it, or no closer to it than a frame
;; that made its latch lately (pacer-made!), and late all the same, the
;; compositor missed the refresh, not the frame: nothing to learn; unless
;; it's the third late run in a chain, as at a deadline that comes and
;; goes, which a compositor's misses now and then seldom make. Nor from
;; the frames late behind the run's first, sent before the pacer saw it:
;; they waited behind it. One sent since, and late still, however early,
;; teaches: no one missed refresh makes that. Sent as the pacer sends
;; them and shown sooner than the depth, the compositor keeps frames less
;; long now: the depth falls to it. In time, the margin fades. => whether
;; it was late
(define (pacer-behind! n r)
  (let ([aimed (pacer-aimed-of n)] [shown (pacer-refresh-seen n)]
        [sent (host-frame-report n 2)] [step (quotient r 8)])
    (and aimed shown sent (> aimed 0)
         (let ([past (- (div (- shown aimed) r) *pacer-depth*)]
               [ahead (- aimed sent)]
               [usual? (< (- aimed sent) (+ *pacer-margin* step))])
           (when *pacer-made*
             (set! *pacer-made* (+ *pacer-made* (quotient step 128))))
           (if (>= past 1)
               (let ([first? (= *pacer-late-seen* 0)])
                 (when first?
                   (set! *pacer-late-chain*
                     (if (< 0 (- n *pacer-late-run*) 128)
                         (+ *pacer-late-chain* 1)
                         1))
                   (set! *pacer-late-run* n)
                   (set! *pacer-late-seen* (now-ns)))
                 (when (if first?
                           (and usual?
                                (or (>= *pacer-late-chain* 3)
                                    (pacer-made-closer? ahead)))
                           (> sent *pacer-late-seen*))
                   (pacer-margin! (+ ahead step) r))
                 #t)
               (begin
                 (set! *pacer-late-seen* 0)
                 (when (and usual? (< past 0))
                   (set! *pacer-depth* (max 0 (+ *pacer-depth* past))))
                 (pacer-made! ahead)
                 (set! *pacer-margin*
                   (- *pacer-margin*
                      (quotient (* *pacer-margin* r) pacer-margin-fade)))
                 #f))))))

;; The deepest a compositor is taken to keep frames, refreshes: one more
;; than the deepest seen (WindowServer's).
(define pacer-depth-most 3)

;; The margin grown to m at least. A margin of a refresh or more is the
;; compositor's depth: frames sent a refresh earlier for the latch before
;; are frames sent for this one, shown a refresh later. So it carries into
;; the depth, which a compositor whose latch comes after the acquire's end
;; has (WindowServer frees an image at a refresh and keeps a frame two
;; more), and the margin is learned afresh: what's past the refresh came of
;; frames sent early; pacer-depth-most at most.
(define (pacer-margin! m r)
  (let ([m (max *pacer-margin* m)])
    (if (and (>= m r) (< *pacer-depth* pacer-depth-most))
        (begin
          (set! *pacer-depth* (+ *pacer-depth* 1))
          (set! *pacer-margin* 0))
        (set! *pacer-margin* (min r m)))))

;; A frame made its latch, sent ahead ns before it: the closest to its
;; latch of those that did is kept, forgotten slowly (a 1024th of a
;; refresh a frame judged, pacer-behind!), so that a late frame sent no
;; closer, which a compositor that now and then misses a refresh makes
;; (WindowServer), teaches no margin, though frames went out early a
;; while, as the lead grew.
(define (pacer-made! ahead)
  (when (pacer-made-closer? ahead) (set! *pacer-made* ahead)))

;; Whether a frame sent ahead ns before its latch was sent closer to it
;; than one that made its latch lately, or none is known.
(define (pacer-made-closer? ahead)
  (or (not *pacer-made*) (< ahead *pacer-made*)))

;; The latch frame n's tick aimed at, among the last few frames; else #f.
(define (pacer-aimed-of n) (pacer-frame-word n 13))

;; Word k of frame n's row in the frame ring (frame-ring-at); else #f.
(define (pacer-frame-word n k)
  (let ([at (frame-ring-at n)])
    (and at (fxvector-ref *frame-ring* (+ at k)))))

;; The refresh frame n showed at (now-ns), the screen's report on it in;
;; else #f.
(define (pacer-refresh-seen n)
  (and (eqv? (host-frame-report n 1) 1) (host-frame-report n 3)))

;; Frame n, sent: the lead follows what it took from when its tick was
;; meant to begin till core0 sent it (main waking late and core0 taking it
;; late among it), with the margin, at once when that's more, else fading;
;; two refreshes at most, so that a lead longer than a refresh still
;; leaves a tick its time at 120 Hz. A wait for an image past the latch it
;; aimed at, a later latch's, the compositor holding a frame more (one it
;; missed a refresh with, or ours queued behind it), is the screen's time,
;; not the frame's: a lead it grew would send the frames after it early.
(define (pacer-need! n r)
  (let ([tick (pacer-frame-word n 14)] [sent (host-frame-report n 2)]
        [aimed (pacer-aimed-of n)]
        [began (host-frame-report n 8)] [ended (host-frame-report n 9)])
    (when (and tick sent (> tick 0) (> sent 0))
      (let ([held (if (and aimed began ended (> aimed 0)
                           (> ended (+ aimed (quotient r 2))))
                      (- ended (max began aimed))
                      0)])
        (set! *pacer-lead*
          (min (* 2 r)
               (max (+ (- sent tick held) *pacer-margin*)
                    (- *pacer-lead*
                       (quotient (* *pacer-lead* r) pacer-lead-fade)))))))))

;; A tick drew a frame: the screen goes on pacing (*pacer-shown?*).
(define (pacer-drew!) (set! *pacer-drew?* #t))

;; A tick: the frames windows asked for and the surfaces' (wm-tick!), then
;; a frame if one is asked for. Paced (now, the ns it began, else #f), the
;; next may come a period after this one was due, or, when that is past
;; already (this one held for core0, or the first after a quiet spell), a
;; period from now.
(define (pacer-tick! now)
  (set! *pacer-aimed* (if (pacer-on-latch?) (pacer-aim) 0))
  (set! *pacer-planned*
    (if (> *pacer-aimed* 0) (- *pacer-aimed* *pacer-lead*) (or now 0)))
  (when now
    (set! *pacer-began* now)
    (let ([next (+ *pacer-due* (pacer-period))])
      (set! *pacer-due* (if (> next now) next (+ now (pacer-period))))))
  (set! *pacer-wanted?* #f)
  ;; a tick that sent the screen nothing leaves it nothing to pace by
  (unless *pacer-drew?* (set! *pacer-shown?* #f))
  (set! *pacer-drew?* #f)
  (set! *pacer-ticks* (+ *pacer-ticks* 1))
  (set! *pacer-tick-ms* (now-ms))
  (set! *pacer-frame-ns*
    (if now (pacer-next-frame-ns now) (* *pacer-tick-ms* 1000000)))
  (safely 'tick wm-tick!))

;; Core0, on a thread of its own, gave back a frame that reached the screen
;; (shown?) or not: by vsync, at the screen's rate, the screen held it, and
;; so paces the next tick (pacer-start).
(define (pacer-frame-back! shown?)
  (set! *pacer-shown?*
    (and shown?
         (host-forked?)
         (eq? *pacer-rate* 'screen)
         (equal? (assq 'present-mode *gpu-facts*) '(present-mode . vsync)))))

;; How long processes may run: until the next tick may begin, less what
;; the last frame took to draw, at most 10 ms, and at least 1 ms, so that
;; they run however full the frames are (that 1 ms is a frame's work too);
;; with no tick wanted, 10 ms.
(define (pacer-procs-ms)
  (if (pacer-wanted?)
      (max 1 (min 10 (exact (floor (- (/ (- (pacer-start) (now-ns)) 1e6)
                                      *frame-ms*)))))
      10))

;; How long a paced step may wait for host events (input ends the wait at
;; once): until the next tick may begin, a period with none wanted (so mail
;; is seen) or while core0 still has the last frame to take (it wakes main
;; as it takes it), or the first timer's time; not at all while processes
;; are ready. Whole ms, rounded up: a step would spin through the last ms
;; before the tick (the 2 ms it may start early hold that one).
(define (pacer-wait-ms)
  (if (procs-ready?)
      0
      (let* ([ms (ceiling (/ (if (and (pacer-wanted?)
                                      (not (gpu-frame-waiting?)))
                                 (- (pacer-start) (now-ns))
                                 (pacer-period))
                             1000000))]
             [ms (if (pair? *timers*)
                     (min ms (- (vector-ref (car *timers*) 0) (now-ms)))
                     ms)])
        (max 0 (exact (ceiling ms))))))

(define (schevana-run!)
  (set! *running* #t)
  (let loop ()
    (when *running*
      (schevana-step! (pacer-wait-ms) #t)
      (loop)))
  (host-shutdown!))

(define (quit!) (set! *running* #f))

;; The run is over, and the process ends: at once on one thread; with core0
;; on its own, once it has closed the window, main waiting for it.
(define (schevana-end!)
  (if (host-forked?)
      (let wait () (host-world-wait! 1000) (wait))
      (exit 0)))

(define (uptime-ms) (- (now-ms) *boot-ms*))

;;; ------------------------------------------------------------------ boot

(define user-init-file
  (format "~a/.schevana.ss" (or (getenv "HOME") ".")))

(define (load-user-init!)
  (when (file-exists? user-init-file)
    (safely 'init (lambda () (load-file! user-init-file)))))

;; The user's own folder: lib for libraries, and kits, desktop, styles,
;; palettes, wallpapers and apps like the tree's (see source-folders).
(define user-directory (format "~a/.schevana.d" (or (getenv "HOME") ".")))

;; (import (acme math)) also finds acme/math.sls here.
(define user-library-directory (string-append user-directory "/lib"))

;; Make import search dir before Chez's own library directories. It need
;; not exist yet.
(define (add-library-directory! dir)
  (let ([dir (if (string-prefix? "~/" dir)
                 (string-append (or (getenv "HOME") "")
                                (substring dir 1 (string-length dir)))
                 dir)])
    (unless (exists (lambda (e) (equal? (if (pair? e) (car e) e) dir))
                    (library-directories))
      (library-directories (cons (cons dir dir) (library-directories))))
    dir))

;; (schevana-boot! 'sdl 1280 800 #t) starts full screen.
(define (schevana-boot! mode w h . fullscreen?)
  (apply host-init! mode w h fullscreen?)
  (invalidate!)
  (collector-settle!))

;;; ------------------------------------------------------------------ collector
;;; A pause is what survived since the last one, whatever the heap holds:
;;; whoever asks, only the young generation is collected, and the world
;;; waits in the oldest. Older ones are collected when main decides, while
;;; nobody is typing or, past a limit on their growth, anyway.

(define collector-young-quiet (* 8 1024 1024))
(define collector-young-limit (* 64 1024 1024))
(define collector-old-quiet (* 64 1024 1024))
(define collector-old-limit (* 512 1024 1024))

;; What the next rendezvous collects, (generation . target); #f, the young.
(defvar *collector-pass* #f)
;; A frame turn, from its tick till core0 has sent its frame, holds the
;; young generation's collections off: one asked for then waits till after,
;; where its pause costs the frame nothing, the heap growing meanwhile by
;; what the turn allocates. A collection stops core0 too: right at the
;; publish, a long one held the frame past its latch. Whether a turn holds
;; them, whether one was asked for, and the frame they wait to see sent
;; (#f, none).
(defvar *collector-holding?* #f)
(defvar *collector-held?* #f)
(defvar *collector-after* #f)
(defvar *collector-check-ms* 0)
(defvar *collector-input-ms* 0)
;; generations 2 and 3 when last collected
(defvar *collector-old-kept* 0)

(define (collector-collect!)
  (if (collector-declining?)
      (set! *collector-held?* #t)
      (let ([pass *collector-pass*])
        (set! *collector-pass* #f)
        (if pass (collect (car pass) (cdr pass)) (collect 0 1)))))

;; A request now is held off: a frame turn's, and no pass of main's asked.
(define (collector-declining?)
  (and *collector-holding?* (not *collector-pass*)))

(define (collector-hold!) (set! *collector-holding?* #t))

;; A frame turn ended: what it held off waits for its frame, the one drawn
;; last, to be sent; for the earliest such, if one waits already, so that
;; frames sent always behind the next turn hold nothing off for long.
(define (collector-frame-out!)
  (unless *collector-after* (set! *collector-after* *frame-number*))
  (collector-after-sent!))

;; That frame sent (core0 gave it back; on main's thread, as it was
;; published): what its turn held off, now.
(define (collector-after-sent!)
  (when (and *collector-after* (>= *frame-back* *collector-after*))
    (set! *collector-after* #f)
    (host-trace! 25 0)
    (collector-after-frame!)
    (host-trace! 26 0)))

;; After a frame turn: the collection it held off, if one was asked for,
;; then the older generations' passes.
(define (collector-after-frame!)
  (set! *collector-holding?* #f)
  (when *collector-held?*
    (set! *collector-held?* #f)
    (collect-rendezvous))
  (collector-tick!))

(defvar *collector-handler*
  (let ([handler (lambda () (collector-collect!))])
    (collect-trip-bytes (* 2 1024 1024))
    (collect-request-handler handler)
    handler))

(define (collector-pass! generation target)
  (set! *collector-pass* (cons generation target))
  (collect-rendezvous))

(define (collector-old) (+ (bytes-allocated 2) (bytes-allocated 3)))

;; The world into the oldest generation, at boot and after a reload. Not
;; static: each reload would then leak the world it replaced.
(define (collector-settle!)
  (collector-pass! 4 4)
  (set! *collector-old-kept* 0))

;; On a tick: twice a second, an older generation if it has grown enough.
(define (collector-tick!)
  (let ([now (now-ms)])
    (when *input-step?* (set! *collector-input-ms* now))
    (when (>= now *collector-check-ms*)
      (set! *collector-check-ms* (+ now 500))
      (let ([quiet? (>= (- now *collector-input-ms*) 1000)])
        (cond
          [(>= (- (collector-old) *collector-old-kept*)
               (if quiet? collector-old-quiet collector-old-limit))
           (collector-pass! 3 3)
           (set! *collector-old-kept* (collector-old))]
          [(>= (bytes-allocated 1)
               (if quiet? collector-young-quiet collector-young-limit))
           (collector-pass! 1 2)])))))

;;; ------------------------------------------------------------------ sources
;;; The core is load.ss's list. After it come the folders, one definition
;;; per file, each folder's files in file-name order: drop a file in and it
;;; loads at the next boot or (reload!). A real session then loads the same
;;; folders from ~/.schevana.d.

;; The folders after the core, in load order.
(define source-folders
  '("kits" "services" "desktop" "styles" "palettes" "wallpapers" "apps"))

;; main.ss turns this on: a real session loads the user's folders too, at
;; boot and at every (reload!). The tests never do.
(defvar *user-folders?* #f)

;; A file name relative to the tree, or an absolute one (the user's).
(define (source-path f)
  (if (path-absolute? f) f (string-append *schevana-root* "/" f)))

;; The .ss files in the folder dir, by name; none if it does not exist.
;; Names starting with a dot (editors' lock files) are left out.
(define (folder-sources dir)
  (let ([path (source-path dir)])
    (if (file-directory? path)
        (map (lambda (f) (string-append dir "/" f))
             (sort string<?
                   (filter (lambda (f)
                             (and (string-suffix? ".ss" f)
                                  (not (string-prefix? "." f))))
                           (directory-list path))))
        '())))

(define (user-folder-files)
  (if *user-folders?*
      (apply append
             (map (lambda (d)
                    (folder-sources (string-append user-directory "/" d)))
                  source-folders))
      '()))

(define (folder-files)
  (append (apply append (map folder-sources source-folders))
          (user-folder-files)))

;; Every source file of the world, in load order. The REPL's docs and the
;; tests read this list.
(define (source-files) (append *schevana-sources* (folder-files)))

;; The text of every source as it was loaded (or, from a REPL, evaluated),
;; by its name: a file's path, or what the REPL calls its input. What reads
;; the sources (the REPL's descriptions) reads these, not the files as they
;; are now, so that it tells of the code that runs. (serial . text), the
;; serial counting the texts kept.
(defvar *source-texts* (make-hashtable string-hash string=?))
(defvar *source-serial* 0)

(define (keep-source-text! name text)
  (set! *source-serial* (+ *source-serial* 1))
  (hashtable-set! *source-texts* name (cons *source-serial* text)))

(define (file-text path) (call-with-input-file path get-string-all))

;; Loads a file, keeping its text (read just before load reads it).
(define (load-file! path)
  (keep-source-text! path (file-text path))
  (load path))

;; Loads an app's file (one in an apps folder, the tree's or the user's):
;; into the world, until services/grant.ss sets this hook to give each
;; app a sandbox of its own.
(defvar *app-loader* (lambda (path) (load-file! path)))

(define (load-source f)
  (let ([path (source-path f)])
    (if (equal? (path-last (path-parent path)) "apps")
        (*app-loader* path)
        (load-file! path))))

;; Loads files into the world (from a private REPL too). Run as a process
;; (the launcher's "Reload sources", (reload!) in a REPL), it names itself
;; and the file in *reloading* until it ends, so the world holds still
;; meanwhile (schevana-step!), yet it is still preempted and Ctrl+C kills it.
;; Not with dynamic-wind: an engine runs its exits at every preemption.
(define (load-sources! files)
  (let* ([p (current-proc)]
         [outer? (and p (not (and *reloading* (eq? (car *reloading*) p))))])
    (parameterize ([interaction-environment *world-env*])
      (guard (c [outer? (reload-ended!
                         (format "Reload failed in ~a: ~a"
                                 (cdr *reloading*) (condition->string c)))
                        (raise c)])
        (for-each (lambda (f i)
                    (when p (set! *reloading* (cons p f)))
                    (load-source f)
                    ;; the boot screen's bar
                    (host-loaded! (+ i 1) (length files)))
                  files (iota (length files)))
        (when outer? (set! *reloading* #f))))))

;; The user's folders, after the built-in ones (main.ss, before the saved
;; theme, which may name a user's style or palette). One file at a time, so
;; that one which raises is named in its toast and the rest still load.
(define (load-user-folders!)
  (set! *user-folders?* #t)
  (add-library-directory! user-library-directory)
  (for-each (lambda (f) (safely f (lambda () (load-sources! (list f)))))
            (user-folder-files)))

;; The source files load.ss lists, read from the file itself so that a
;; reload picks up new ones.
(define (read-source-list)
  (guard (c [#t *schevana-sources*])
    (call-with-input-file (string-append *schevana-root* "/load.ss")
      (lambda (p)
        (let loop ()
          (let ([x (read p)])
            (cond
              [(eof-object? x) *schevana-sources*]
              [(and (list? x) (= (length x) 3) (eq? (car x) 'define)
                    (eq? (cadr x) '*schevana-sources*)
                    (pair? (caddr x)) (eq? (car (caddr x)) 'quote)
                    (list? (cadr (caddr x))))
               (cadr (caddr x))]
              [else (loop)])))))))

;; Re-read every source file. Code changes take effect; state declared
;; with defvar (windows, theme, processes...) survives.
(define (reload!)
  (let ([files (read-source-list)])
    (set! *schevana-sources* files)
    (load-sources! files))
  (invalidate!)
  (collector-settle!)
  (notify "Sources reloaded" 'green))

;; load.ss loads the core before this file can keep its texts: kept now,
;; moments after (a reload keeps them as it loads them).
(for-each (lambda (f)
            (let ([path (source-path f)])
              (unless (hashtable-contains? *source-texts* path)
                (keep-source-text! path (file-text path)))))
          *schevana-sources*)

;; The folders load from here, the end of the last file in load.ss's list,
;; so that a reload by older code, which loads only that list, loads them
;; too. Their files may import the libraries shipped in lib/.
(add-library-directory! (string-append *schevana-root* "/lib"))
(load-sources! (folder-files))
