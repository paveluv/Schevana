;;; (schevana core pacer) — when the world's ticks come, and what became of
;;; each frame: the pacer, which keeps ticks to the screen's refreshes, the
;;; numbers kept about the last frames, and the drawing of each frame
;;; (render-frame!). It sits below what draws the screen ((schevana core
;;; windows), which sets its hooks record-world! and wm-tick!), and under
;;; the loop ((schevana core loop)), which asks it when to tick.
;;;
;;; A second pacer, (schevana core pacer2), sits above it, and the
;;; setting pacer says which of the two the loop asks: 1, this one, by
;;; default, or 2. What a turn is, what it was asked for, the rate, the
;;; turns so far, t, and the frame ring are the two pacers' alike, and kept
;;; here.

(library (schevana core pacer)
  (export
    *pacer-due* *pacer-waits* *pacer-frame-ns* *pacer-shown?* *pacer-latch*
    *pacer-lead* *pacer-counts* *pacer-aimed* *pacer-floor* *pacer-latch-phase*
    *pacer-depth* *pacer-made* *pacer-gpu-taught* *pacer-late-run*
    *pacer-late-chain* *pacer-between?* *frame-ms* *frames-drawn* *frame-back*
    frame-ring-rows frame-ring-words *frame-ring* *frame-ring-n* *frame-number*
    frame-ticked! frame-input-came! frame-input-drop! pacer-waited!
    pacer-step-done! pacer-busy-ms pacer-peak-ms! pacer-rate pacer-ticks
    frame-turn-soon! pacer-wanted? pacer-frame-ns pacer-period pacer-start
    pacer-on-latch? pacer-trial! pacer-margin wm-tick! pacer-tick!
    pacer-procs-ms pacer-wait-ms record-world! record-safely render-frame!
    render-frames-back! render-answers! screen-bytes-then pacer-rate!
    pacer2? pacer-turn-begun!)
  (import (chezscheme)
          (only (schevana base) at-load define-hook define-state library-layer)
          (only (schevana core0) *core0-mode* *gpu-facts* core0-forked?
                core0-frame-ns core0-frame-report core0-hidden? core0-trace!
                gpu-frame-next gpu-frame-number gpu-frame-shown?
                gpu-frame-waiting?
                gpu-frames-back! gpu-take-answers!)
          (only (schevana recorder) rec-last-sizes)
          (only (schevana core theme-table) *pacer-trial* pacer-knob
                theme-table-default!)
          (only (schevana core platform) now-ms now-ns
                platform-pacer-margin-fade)
          (only (schevana core processes) *dirty* *frame-generation* *timers*
                after in-engine? procs-ready? request-frame! safely)
          (only (schevana core gpu) gpu-frame-free!)
          (only (schevana core fonts) *atlas-full?* *glyph-count* atlas-flush!)
          (only (schevana core draw) *canvas-ph* *canvas-pw* *canvas-ratio*
                *rec-clip* *rec-cx0* *rec-cx1* *rec-cy0* *rec-cy1* *rec-den*
                *rec-num* *rec-ox* *rec-oy* *rec-turn* drawing->bytes-then
                rec-begin! rec-present! rec-runs rec-state-restore!))

  (library-layer core)

  ;; The pacer: the world's ticks, its frame turns, come from it. Ticks keep
  ;; to a grid a period apart. With core0 on a thread of its own, a tick
  ;; also waits until core0 has taken the last frame (.work/gpu-design.md
  ;; 9.12), and once one of its frames has reached the screen by vsync, the
  ;; screen sets the pace instead (pacer-start). These are its rate ('screen
  ;; for one tick per refresh of the screen, or a number of ticks a second),
  ;; when the next tick may come on the grid (now-ns), and the ticks so far.
  (define-state *pacer-rate* 'screen)
  (define-state *pacer-due* 0)
  (define-state *pacer-ticks* 0)
  (define-state *pacer-waits* 0)   ; this step's waits, ns
  ;; the work of the steps since the last tick, ns
  (define-state *pacer-work* 0)
  (define-state *pacer-busy* 0)    ; the last tick's work, ns
  ;; the most work of any tick since it was last asked for, ns
  (define-state *pacer-peak* 0)
  (define-state *pacer-began* 0)   ; when the last tick began, ns
  ;; when the last tick's frame should show, ns
  (define-state *pacer-frame-ns* 0)
  ;; whether a tick is asked for, to look at what changed if not to draw
  (define-state *pacer-wanted?* #f)
  ;; whether the last frame core0 gave back reached the screen, which held it
  ;; (vsync, at the screen's rate): the screen paces the ticks while each
  ;; tick sends it a frame, until a frame comes back otherwise; and whether
  ;; the last tick drew a frame
  (define-state *pacer-shown?* #f)
  (define-state *pacer-drew?* #f)
  ;; when core0's last acquire that the screen held returned (now-ns), as
  ;; the compositor freed an image, or #f; the compositor's latches fall a
  ;; refresh apart from it. And how long before a latch a tick begins, in
  ;; ns: what frames took lately from their tick until core0 sent them, plus
  ;; the margin.
  (define-state *pacer-latch* #f)
  (define-state *pacer-lead* 4000000)
  ;; how long before its latch a frame must be sent to make it, as the
  ;; screen's reports teach: the compositor's deadline and the GPU's work;
  ;; or #f while nothing is taught yet (pacer-margin)
  (define-state *pacer-margin* #f)
  ;; what the pacer judged: the frames, those late by its own fault, and
  ;; those late by the compositor's
  (define-state *pacer-counts* (make-fxvector 3 0))
  ;; the latch that the last tick aimed its frame at, just in time, or 0;
  ;; and when the pacer meant that tick to begin (now-ns)
  (define-state *pacer-aimed* 0)
  (define-state *pacer-planned* 0)
  ;; the first latch the next frame may take, as the reports say, since the
  ;; frames before it on their way each take one; or 0
  (define-state *pacer-floor* 0)
  ;; the newest frame whose report the pacer has judged
  (define-state *pacer-judged* 0)
  ;; where the latches fall relative to the screen's refreshes, in ns after
  ;; one, as last seen, or #f. With it, each report of a refresh says where
  ;; the next latches are, whether or not an acquire waits for one.
  (define-state *pacer-latch-phase* #f)
  ;; how many refreshes after the first one past its latch a frame that the
  ;; compositor took there shows, as the reports teach; 0 for a compositor
  ;; that shows it at the refresh after its latch (pacer-margin!)
  (define-state *pacer-depth* 0)
  ;; of the frames that made their latch lately, how long before it the one
  ;; sent closest to it was sent, in ns (pacer-made!); or #f
  (define-state *pacer-made* #f)
  ;; once a frame whose GPU work was still going more than a refresh and an
  ;; eighth after its send has taught the pacer, the frames judged since the
  ;; last such frame (pacer-behind!); or #f
  (define-state *pacer-gpu-taught* #f)
  ;; the first frame of the newest late run (frames judged late one after
  ;; another); when the pacer judged that frame (now-ns), or 0 once a frame
  ;; is in time; and how many runs have come in a chain, each within 128
  ;; frames of the one before
  (define-state *pacer-late-run* 0)
  (define-state *pacer-late-seen* 0)
  (define-state *pacer-late-chain* 0)
  ;; whether this step came between ticks: the profiler sums such a step
  ;; into the next tick
  (define-state *pacer-between?* #f)

  ;; which pacer planned the last turn: 1, this one, or 2, the second
  ;; ((schevana core pacer2)); a frame's row keeps it
  (define-state *pacer-kind* 1)

  ;; the last frame's time in ms: its work, not its wait for the screen
  (define-state *frame-ms* 0.0)
  (define-state *frames-drawn* 0)
  ;; the number of the newest frame core0 gave back: sent, or with no room
  ;; found for it
  (define-state *frame-back* 0)

  ;; The last frames, for (schevana kits inspect): what each took and held;
  ;; what became of it (1 it reached the screen, 2 the window had no room, 0
  ;; not given back yet); its number (its report's, core0-frame-report); when
  ;; the oldest input it shows came (now-ns; 0 for none) by SDL's stamp; then
  ;; when its tick began, its draw began and it was published; when that
  ;; input came by core0's pump and by the compositor's time; what its tick
  ;; aimed at (0 for none): the latch for this pacer, the refresh itself for
  ;; the second; when the pacer meant its tick to begin (0 for at once,
  ;; with the second); and which pacer planned it (*pacer-kind*). They are
  ;; always kept: a few numbers per frame, for the last frame-ring-rows
  ;; frames.
  (define frame-ring-rows 2048)
  (define frame-ring-words 16)
  (define-state *frame-ring*
    (make-fxvector (* frame-ring-rows frame-ring-words) 0))
  (define-state *frame-ring-n* 0)   ; frames so far
  ;; the number of the frame being drawn, its times, and when the oldest
  ;; input not yet drawn came, by three clocks (core0-input-ns-take!)
  (define-state *frame-number* 0)
  (define-state *frame-tick-ns* 0)
  (define-state *frame-draw-ns* 0)
  (define-state *frame-publish-ns* 0)
  (define-state *frame-input-ns* 0)
  (define-state *frame-input-pumped* 0)
  (define-state *frame-input-wl* 0)

  (define (frame-number-set! n) (set! *frame-number* n))
  ;; Notes that the tick began at now (now-ns).
  (define (frame-ticked! now) (set! *frame-tick-ns* now))

  ;; Notes when input came (now-ns; 0 for none) by SDL's stamp, core0's pump
  ;; and the compositor: the next frame shows it, unless older input waits.
  (define (frame-input-came! ns pumped wl)
    (unless (or (eqv? ns 0) (not (eqv? *frame-input-ns* 0)))
      (set! *frame-input-ns* ns))
    (unless (or (eqv? pumped 0) (not (eqv? *frame-input-pumped* 0)))
      (set! *frame-input-pumped* pumped))
    (unless (or (eqv? wl 0) (not (eqv? *frame-input-wl* 0)))
      (set! *frame-input-wl* wl)))

  ;; Forgets input that asked for no frame, since no frame shows it.
  (define (frame-input-drop!)
    (set! *frame-input-ns* 0)
    (set! *frame-input-pumped* 0)
    (set! *frame-input-wl* 0))

  (define (frame-ring-add!)
    (let ([at (* frame-ring-words (modulo *frame-ring-n* frame-ring-rows))]
          [ring *frame-ring*])
      (fxvector-set! ring (+ at 6) *frame-number*)
      (fxvector-set! ring (+ at 7) *frame-input-ns*)
      (fxvector-set! ring (+ at 8) *frame-tick-ns*)
      (fxvector-set! ring (+ at 9) *frame-draw-ns*)
      (fxvector-set! ring (+ at 10) *frame-publish-ns*)
      (fxvector-set! ring (+ at 11) *frame-input-pumped*)
      (fxvector-set! ring (+ at 12) *frame-input-wl*)
      (fxvector-set! ring (+ at 13) *pacer-aimed*)
      (fxvector-set! ring (+ at 14) *pacer-planned*)
      (fxvector-set! ring (+ at 15) *pacer-kind*)
      (frame-input-drop!)
      (fxvector-set! ring at 0)
      ;; the frame's sizes: it is published, so the recorder writes nothing
      ;; into it now
      (let-values ([(recs-n extras-n) (rec-last-sizes)])
        (fxvector-set! ring (+ at 1) (fxquotient recs-n 32))
        (fxvector-set! ring (+ at 2) (fxquotient extras-n 4)))
      (fxvector-set! ring (+ at 3) (length (rec-runs)))
      (fxvector-set! ring (+ at 4) *glyph-count*)
      (fxvector-set! ring (+ at 5) 0))
    (set! *frame-ring-n* (+ *frame-ring-n* 1)))

  ;; Returns where frame n's row starts, among the newest sixteen rows,
  ;; which hold every frame not yet given back or judged; else #f.
  (define (frame-ring-at n)
    (let loop ([i (- *frame-ring-n* 1)] [j 0])
      (and (< j 16) (>= i 0)
           (let ([at (* frame-ring-words (modulo i frame-ring-rows))])
             (if (eqv? (fxvector-ref *frame-ring* (+ at 6)) n)
                 at
                 (loop (- i 1) (+ j 1)))))))

  ;; Sets word k of frame n's row to v, while the ring still has the row.
  (define (frame-ring-set! n k v)
    (let ([at (frame-ring-at n)])
      (when at (fxvector-set! *frame-ring* (+ at k) v))))

  ;;; ---------------------------------------------------------------- pacing

  ;; The pacer's choices, as fractions of a refresh, or in seconds for the
  ;; fades; and which pacer the loop asks, 1 or 2.
  (at-load
   (theme-table-default! 'pacer 1)
   (theme-table-default! 'pacer-margin-start 0)
   (theme-table-default! 'pacer-margin-step 1/8)
   (theme-table-default! 'pacer-miss-own 1/8)
   (theme-table-default! 'pacer-lead-fade 1/2)
   (theme-table-default! 'pacer-margin-fade platform-pacer-margin-fade))

  ;; Returns whether the loop asks the second pacer ((schevana core
  ;; pacer2)), as the setting pacer says.
  (define (pacer2?) (eqv? (pacer-knob 'pacer) 2))

  ;; Counts the time from since until now as a wait, for input or for the
  ;; screen.
  (define (pacer-waited! since) (pacer-held! (- (now-ns) since)))

  ;; Counts ns of waiting, for input or for the screen, told afterwards.
  (define (pacer-held! ns) (set! *pacer-waits* (+ *pacer-waits* ns)))

  ;; A step of ns ended: its work adds to the tick's, and the tick ends with
  ;; it unless the step came between ticks, as the profiler's ticks do.
  (define (pacer-step-done! ns)
    (set! *pacer-work* (+ *pacer-work* (- ns *pacer-waits*)))
    (unless *pacer-between?*
      (set! *pacer-busy* *pacer-work*)
      (set! *pacer-peak* (max *pacer-peak* *pacer-work*))
      (set! *pacer-work* 0)))

  ;; What the last tick took, apart from its waits, in ms: past a period,
  ;; the next tick is late.
  (define (pacer-busy-ms) (/ *pacer-busy* 1e6))

  ;; Returns the most that any tick took since the last call, in ms, so that
  ;; a single spike shows.
  (define (pacer-peak-ms!)
    (let ([ms (/ *pacer-peak* 1e6)])
      (set! *pacer-peak* 0)
      ms))

  ;; (pacer-rate! 60): 60 ticks a second from now on; (pacer-rate! 'screen),
  ;; the default: one tick per refresh of the screen. Apps that move by time
  ;; still read the clock, since the screen's rate is its own.
  (define (pacer-rate! rate)
    (set! *pacer-rate* rate)
    (set! *pacer-due* 0))
  (define (pacer-rate) *pacer-rate*)
  (define (pacer-ticks) *pacer-ticks*)

  ;; Asks for a tick: the windows' frames and the surfaces look at what
  ;; changed, and a frame is drawn if something asked for one (*dirty*).
  (define (frame-turn-soon!) (set! *pacer-wanted?* #t))
  (define (pacer-wanted?) (or *pacer-wanted?* *dirty*))

  ;; When the frame that the last tick made should show, in ns: the t of a
  ;; window's 'frame handler, a period after the last frame's and a few
  ;; periods after the tick.
  (define (pacer-frame-ns) *pacer-frame-ns*)

  ;; How many periods after its tick t sits while frames flow; the frames
  ;; show later still.
  (define pacer-lead-frames 2)

  ;; Returns when this tick's frame shows: a whole number of periods after
  ;; the last tick's frame, so that what moves by it moves as evenly as the
  ;; screen shows its frames, a refresh apart. The tick runs as core0 takes
  ;; the last frame, so it tells where that grid lies only to a millisecond
  ;; or so; t therefore follows the point pacer-lead-frames periods past the
  ;; tick slowly, moving a 256th of the way each tick and never more than
  ;; 0.1 ms. t moves a period per tick, unless that would put it behind the
  ;; tick itself (with ticks slower than the screen, a frame on every other
  ;; refresh); then it steps as many whole periods as keep it ahead. After a
  ;; pause (over three periods), t is a period after the tick: the frames
  ;; that follow fill the screen's queue faster than a period apart, and
  ;; carry t further ahead of its tick, toward where it follows.
  (define (pacer-next-frame-ns now)
    (let* ([p (if (eq? *pacer-rate* 'screen) (core0-frame-ns) (pacer-period))]
           [next (+ *pacer-frame-ns* p)]
           [behind (- (+ now (* pacer-lead-frames p)) next)])
      (cond [(> (- now *pacer-frame-ns*) (* 3 p)) (+ now p)]
            [(< next now) (+ next (* p (quotient (+ (- now next) p -1) p)))]
            [else (+ next (max -100000 (min 100000 (quotient behind 256))))])))

  ;; A tick's period, in ns: a 500th shorter than the refresh the screen
  ;; reports. That is more than a report is ever off by (a rate truncated to
  ;; the mHz, or rounded to the Hz), so that the grid never holds back a
  ;; tick the screen is ready for; and less than the 0.1 ms a tick's t may
  ;; move, so that with no screen to hold the ticks, t keeps to the clock.
  ;; With a fixed rate, the rate's period.
  (define (pacer-period)
    (if (eq? *pacer-rate* 'screen)
        (let ([p (core0-frame-ns)]) (- p (quotient p 500)))
        (quotient 1000000000 *pacer-rate*)))

  ;; Returns when the next tick may begin: a little before its time (2 ms),
  ;; room for the clock's and the screen's jitter, so that its frame is in
  ;; time for the refresh. Once a frame has reached the screen by vsync, the
  ;; screen sets the pace: the next tick also waits until core0 takes the
  ;; frame this one sent, so it may come as soon as half a period after this
  ;; one, and the grid never holds back a screen a little faster than its
  ;; report, or a queue refilling after a pause. Frames the screen had no
  ;; room for come back at once and put the grid back on. Where the screen's
  ;; reports place the compositor's latches (Wayland's do) and one was seen
  ;; in the last second, the tick begins just in time instead
  ;; (pacer-just-in-time).
  (define (pacer-start)
    (cond
      [(pacer-on-latch?) (pacer-just-in-time)]
      [*pacer-shown?* (- (+ *pacer-began* (quotient (pacer-period) 2)) 2000000)]
      [else (- *pacer-due* 2000000)]))

  ;; Whether ticks keep to the compositor's latches now: the screen is
  ;; pacing (the last frame back came by vsync), and the reports place a
  ;; latch seen in the last second. This holds also while this tick's frame
  ;; is on its way, when a tick by the grid would be one too many. A wait
  ;; for the next tick is then a wait for the screen.
  (define (pacer-on-latch?)
    (and *pacer-shown?* *pacer-latch* *pacer-latch-phase*
         (< (- (now-ns) *pacer-latch*) 1000000000)))

  ;; Returns when the next tick begins, just in time for the compositor's
  ;; next latch: the lead before the latch it aims at (pacer-aim), a later
  ;; one than this tick's. Its frame, published a lead later, goes straight
  ;; into an acquire that the latch ends, with the input that came until the
  ;; tick began, rather than a refresh early, waiting for an image with
  ;; input a refresh old.
  (define (pacer-just-in-time) (- (pacer-aim) *pacer-lead*))

  ;; Returns the latch the next tick aims at: the first one, on the grid a
  ;; refresh apart from the last latch seen, that comes a lead after this
  ;; tick began, after the latch this tick aimed at (which its frame holds),
  ;; and not before the floor, since a frame that came late moves the ones
  ;; after it.
  (define (pacer-aim)
    (let* ([r (core0-frame-ns)] [half (quotient r 2)]
           [after (- (max (+ *pacer-began* *pacer-lead*)
                          (+ *pacer-aimed* half)
                          (- *pacer-floor* half))
                     *pacer-latch*)])
      (+ *pacer-latch* (* r (if (> after 0) (quotient (+ after r -1) r) 0)))))

  ;; Learns from frame n, which core0 gave back. If the screen held its
  ;; acquire, the acquire's end is the compositor's latch; else the newest
  ;; report places the latch. The newest report also says where the frames
  ;; on their way will show, each a latch after the one before and the
  ;; compositor's depth past its own (the floor), and it is judged
  ;; (pacer-behind!); n's own time until its send teaches the lead. The
  ;; reports read are the newest in: how many frames behind they come
  ;; differs by compositor, GPU and rate (one frame back, or four under
  ;; Mutter's triple buffering at 120 Hz).
  (define (pacer-latch! n)
    (when (>= *pacer-judged* n)            ; frames numbered anew
      (set! *pacer-judged* 0))
    (let* ([r (core0-frame-ns)]
           [began (core0-frame-report n 8)] [ended (core0-frame-report n 9)]
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

  ;; Returns the newest frame before n that the screen has reported on,
  ;; shown or dropped, among the eight before it; else #f.
  (define (pacer-reported-before n)
    (let loop ([m (- n 1)])
      (and (> m (- n 9)) (> m 0)
           (if (memv (core0-frame-report m 1) '(1 2)) m (loop (- m 1))))))

  ;; Judges once (pacer-behind!) each frame up to m whose report is in and
  ;; that isn't judged yet, going at most eight frames back.
  (define (pacer-judge! m r)
    (let loop ([k (max (+ *pacer-judged* 1) (- m 8))])
      (unless (> k m)
        (set! *pacer-judged* k)
        (pacer-count! 0)
        (pacer-behind! k r)
        (loop (+ k 1)))))

  (define (pacer-count! k)
    (fxvector-set! *pacer-counts* k (fx+ 1 (fxvector-ref *pacer-counts* k))))

  ;; Starts a trial ('() for none), and forgets what the pacer learned under
  ;; the one before.
  (define (pacer-trial! alist)
    (set! *pacer-trial* alist)
    (pacer-relearn!))

  ;; A choice that is a fraction of refresh r, or a number of seconds, as ns.
  (define (pacer-of-refresh key r) (exact (floor (* (pacer-knob key) r))))
  (define (pacer-seconds key) (exact (floor (* (pacer-knob key) 1000000000))))

  ;; The margin, as the screen taught it, or else where it starts. It fades
  ;; as pacer-margin-fade says, which by default is the platform's: in a
  ;; minute on a Mac, and elsewhere never, since finding out whether the
  ;; compositor would take frames later again costs a late frame.
  (define (pacer-margin r)
    (or *pacer-margin* (pacer-of-refresh 'pacer-margin-start r)))

  ;; Forgets what the pacer learned, as at a run's start.
  (define (pacer-relearn!)
    (set! *pacer-margin* #f)
    (set! *pacer-floor* 0)
    (set! *pacer-depth* 0)
    (set! *pacer-made* #f)
    (set! *pacer-late-seen* 0)
    (set! *pacer-late-chain* 0)
    (set! *pacer-gpu-taught* #f)
    (set! *pacer-lead* (quotient (core0-frame-ns) 4)))

  ;; Judges frame n, whose report is in, against the latch it aimed at. It
  ;; is late if it showed a refresh or more after the one aimed for (the
  ;; first after the latch, plus the compositor's depth). If it was sent
  ;; about the margin before the latch, as the pacer sends frames (no more
  ;; than pacer-miss-own past the margin), the margin was too small: it
  ;; grows past that by a step (pacer-margin!); a run of late frames sent
  ;; alike raises it only once. If it was sent well before the latch, or no
  ;; closer to it than a frame that made its latch lately (pacer-made!), and
  ;; was late all the same, the compositor missed the refresh, not the
  ;; frame, and there is nothing to learn; unless this is the third late run
  ;; in a chain, as at a deadline that comes and goes, which a compositor's
  ;; occasional misses seldom make. Nothing is learned either from the
  ;; frames late behind the run's first that were sent before the pacer saw
  ;; it, since they waited behind it. A frame sent after that and still
  ;; late, however early, teaches: no single missed refresh makes that. A
  ;; late frame that teaches counts as the pacer's own, any other as the
  ;; compositor's. A frame sent as the pacer sends them and shown sooner
  ;; than the depth means that the compositor now keeps frames for less
  ;; long, so the depth falls to match. In time, the margin fades as
  ;; pacer-margin-fade says. What frames taught whose GPU work was still
  ;; going a refresh and an eighth after their send is the GPU's, not the
  ;; compositor's (a GPU too slow for the refresh: one slow to wake as an
  ;; app opens, which taught three refreshes of queue in a quarter second,
  ;; or an app too heavy for it). Once 240 frames are judged with none of
  ;; them so slow, the pacer learns afresh (pacer-relearn!). Returns whether
  ;; the frame was late.
  (define (pacer-behind! n r)
    (let ([aimed (pacer-aimed-of n)] [shown (pacer-refresh-seen n)]
          [sent (core0-frame-report n 2)] [going (core0-frame-report n 11)]
          [margin (pacer-margin r)])
      (and aimed shown sent going (> aimed 0)
           (let ([past (- (div (- shown aimed) r) *pacer-depth*)]
                 [ahead (- aimed sent)]
                 [usual? (< (- aimed sent)
                            (+ margin (pacer-of-refresh 'pacer-miss-own r)))]
                 [slow? (> going (+ sent r (quotient r 8)))])
             (when *pacer-made*
               (set! *pacer-made* (+ *pacer-made* (quotient r 1024))))
             (when *pacer-gpu-taught*
               (set! *pacer-gpu-taught* (if slow? 0 (+ *pacer-gpu-taught* 1))))
             (if (>= past 1)
                 (let ([first? (= *pacer-late-seen* 0)])
                   (when first?
                     (set! *pacer-late-chain*
                       (if (< 0 (- n *pacer-late-run*) 128)
                           (+ *pacer-late-chain* 1)
                           1))
                     (set! *pacer-late-run* n)
                     (set! *pacer-late-seen* (now-ns)))
                   (if (if first?
                           (and usual?
                                (or (>= *pacer-late-chain* 3)
                                    (pacer-made-closer? ahead)))
                           (> sent *pacer-late-seen*))
                       (begin
                         (pacer-count! 1)
                         (when slow? (set! *pacer-gpu-taught* 0))
                         (pacer-margin!
                          (+ ahead (pacer-of-refresh 'pacer-margin-step r))
                          r))
                       (pacer-count! 2))
                   #t)
                 (let ([fade (pacer-seconds 'pacer-margin-fade)])
                   (set! *pacer-late-seen* 0)
                   (when (and usual? (< past 0))
                     (set! *pacer-depth* (max 0 (+ *pacer-depth* past))))
                   (pacer-made! ahead)
                   (when (and *pacer-margin* (> fade 0))
                     (set! *pacer-margin*
                       (- *pacer-margin*
                          (quotient (* *pacer-margin* r) fade))))
                   (when (and *pacer-gpu-taught* (> *pacer-gpu-taught* 240))
                     (pacer-relearn!))
                   #f))))))

  ;; The deepest a compositor is taken to keep frames, in refreshes: one
  ;; more than the deepest seen (WindowServer's).
  (define pacer-depth-most 3)

  ;; Grows the margin to at least m. A margin of a refresh or more is really
  ;; the compositor's depth: frames sent a refresh earlier, for the latch
  ;; before, are frames sent for this one and shown a refresh later. So the
  ;; margin carries into the depth, which a compositor whose latch comes
  ;; after the acquire's end has (WindowServer frees an image at a refresh
  ;; and keeps a frame for two more), and the margin is learned afresh from
  ;; where it starts, since what is past the refresh came of frames sent
  ;; early. The depth goes up to pacer-depth-most at most.
  (define (pacer-margin! m r)
    (let ([m (max (pacer-margin r) m)])
      (if (and (>= m r) (< *pacer-depth* pacer-depth-most))
          (begin
            (set! *pacer-depth* (+ *pacer-depth* 1))
            (set! *pacer-margin* #f))
          (set! *pacer-margin* (min r m)))))

  ;; A frame made its latch, sent ahead ns before it. Of the frames that
  ;; did, the one sent closest to its latch is kept, and forgotten slowly
  ;; (by a 1024th of a refresh per frame judged, pacer-behind!), so that a
  ;; late frame sent no closer, as a compositor that misses a refresh now
  ;; and then makes them (WindowServer), teaches no margin, even after
  ;; frames went out early for a while as the lead grew.
  (define (pacer-made! ahead)
    (when (pacer-made-closer? ahead) (set! *pacer-made* ahead)))

  ;; Whether a frame sent ahead ns before its latch was sent closer to it
  ;; than one that made its latch lately, or none is known.
  (define (pacer-made-closer? ahead)
    (or (not *pacer-made*) (< ahead *pacer-made*)))

  ;; Returns the latch that frame n's tick aimed at, among the last few
  ;; frames; else #f.
  (define (pacer-aimed-of n) (pacer-frame-word n 13))

  ;; Returns word k of frame n's row in the frame ring (frame-ring-at),
  ;; where this pacer planned it; else #f. A row that the second pacer
  ;; planned aims at a refresh, not at a latch, and teaches this one
  ;; nothing.
  (define (pacer-frame-word n k)
    (let ([at (frame-ring-at n)])
      (and at (fx= (fxvector-ref *frame-ring* (+ at 15)) 1)
           (fxvector-ref *frame-ring* (+ at k)))))

  ;; Returns the refresh that frame n showed at (now-ns), once the screen's
  ;; report on it is in; else #f.
  (define (pacer-refresh-seen n)
    (and (eqv? (core0-frame-report n 1) 1) (core0-frame-report n 3)))

  ;; Frame n was sent: the lead follows what it took from when its tick was
  ;; meant to begin until core0 sent it (core1 waking late and core0 taking
  ;; it late count too), plus the margin. The lead takes that at once when
  ;; it is more, and else fades toward it (pacer-lead-fade, a spike's time
  ;; to fade); it is two refreshes at most, so that a lead longer than a
  ;; refresh still leaves a tick its time at 120 Hz. An acquire that the
  ;; screen held (over 1 ms, as in pacer-latch!), and the frame's wait for
  ;; core0 before it, held in the previous frame's acquire, are the
  ;; screen's time, not the frame's: a lead grown by them would send the
  ;; frames after it early, into the same full queue, to wait longer still,
  ;; until each waited a refresh once published and a refresh for its
  ;; image.
  (define (pacer-need! n r)
    (let ([tick (pacer-frame-word n 14)] [pub (pacer-frame-word n 10)]
          [sent (core0-frame-report n 2)]
          [began (core0-frame-report n 8)] [ended (core0-frame-report n 9)])
      (when (and tick sent (> tick 0) (> sent 0))
        (let ([own (if (> (- ended began) 1000000)
                       (+ (- pub tick) (- sent ended))
                       (- sent tick))])
          (set! *pacer-lead*
            (min (* 2 r)
                 (max (+ own (pacer-margin r))
                      (- *pacer-lead*
                         (quotient
                          (* *pacer-lead* r)
                          (max 1 (pacer-seconds 'pacer-lead-fade)))))))))))

  ;; Notes that a tick sent a frame, so the screen goes on pacing
  ;; (*pacer-shown?*). A frame held back (the window hidden) gives the
  ;; screen nothing to pace by.
  (define (pacer-drew!) (set! *pacer-drew?* #t))

  ;; What a tick does, its frame turn: what is on the screen looks at what
  ;; changed and asks for its frames. (schevana core windows) sets it; until
  ;; then it does nothing.
  (define-hook (wm-tick!) (void))

  ;; A tick, begun at now (now-ns): the frames that windows asked for and
  ;; the surfaces' (wm-tick!), then a frame if one is asked for. The next
  ;; tick may come a period after this one was due, or, when that is past
  ;; already (this one held for core0, or the first after a quiet spell), a
  ;; period from now; never more than two periods from now, since ticks
  ;; that came early, each adding a period, would put it off without end,
  ;; and the world with it.
  (define (pacer-tick! now)
    (set! *pacer-kind* 1)
    (set! *pacer-aimed* (if (pacer-on-latch?) (pacer-aim) 0))
    (set! *pacer-planned*
      (if (> *pacer-aimed* 0) (- *pacer-aimed* *pacer-lead*) now))
    (set! *pacer-began* now)
    (let ([next (+ *pacer-due* (pacer-period))])
      (set! *pacer-due*
        (if (> next now)
            (min next (+ now (* 2 (pacer-period))))
            (+ now (pacer-period)))))
    (set! *pacer-wanted?* #f)
    ;; a tick that sent the screen nothing leaves it nothing to pace by
    (unless *pacer-drew?* (set! *pacer-shown?* #f))
    (set! *pacer-drew?* #f)
    (set! *pacer-ticks* (+ *pacer-ticks* 1))
    (set! *pacer-frame-ns* (pacer-next-frame-ns now))
    (safely 'tick wm-tick!))

  ;; A turn that the second pacer begins ((schevana core pacer2)): t is when
  ;; its frame shows, never earlier than the last turn's; aim, the refresh
  ;; it aims at, and plan, the begin it was planned for (now-ns; 0 for at
  ;; once), which its frame's row keeps. wm-tick! is the loop's to call.
  (define (pacer-turn-begun! t aim plan)
    (set! *pacer-kind* 2)
    (set! *pacer-aimed* aim)
    (set! *pacer-planned* plan)
    (set! *pacer-wanted?* #f)
    (set! *pacer-ticks* (+ *pacer-ticks* 1))
    (set! *pacer-frame-ns* (max t *pacer-frame-ns*)))

  ;; Core0, on a thread of its own, gave back a frame that reached the screen
  ;; (shown?) or not. If it was shown by vsync at the screen's rate, the
  ;; screen held it, and so the screen paces the next tick (pacer-start).
  (define (pacer-frame-back! shown?)
    (set! *pacer-shown?*
      (and shown?
           (core0-forked?)
           (eq? *pacer-rate* 'screen)
           (equal? (assq 'present-mode *gpu-facts*) '(present-mode . vsync)))))

  ;; Returns how long processes may run, in ms: until the next tick may
  ;; begin, less what the last frame took to draw, at most 10 ms and at
  ;; least 1 ms, so that they run however full the frames are (that 1 ms is
  ;; a frame's work too); with no tick wanted, 10 ms.
  (define (pacer-procs-ms)
    (if (pacer-wanted?)
        (max 1 (min 10 (exact (floor (- (/ (- (pacer-start) (now-ns)) 1e6)
                                        *frame-ms*)))))
        10))

  ;; Returns how long a paced step may wait for core0's events, in whole ms
  ;; (input ends the wait at once): until the next tick may begin; a period
  ;; when no tick is wanted (so that mail is seen) or while core0 still has
  ;; the last frame to take (it wakes core1 as it takes it); or until the
  ;; first timer is due; and not at all while processes are ready. It rounds
  ;; up, since a step would otherwise spin through the last ms before the
  ;; tick (the 2 ms by which a tick may start early cover that one).
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

  ;;; ---------------------------------------------------------------- frames

  ;; What a frame draws, the whole screen: the windows and the surfaces.
  ;; (schevana core windows) sets it; until then it draws nothing.
  (define-hook (record-world!) (void))

  ;; Records thunk's drawing, which may crash. Whatever recorder state it
  ;; leaves behind goes: the state is kept in variables first and restored
  ;; after.
  (define (record-safely name thunk)
    (let ([num *rec-num*] [den *rec-den*] [ox *rec-ox*] [oy *rec-oy*]
          [turn *rec-turn*] [clip *rec-clip*] [cx0 *rec-cx0*] [cy0 *rec-cy0*]
          [cx1 *rec-cx1*] [cy1 *rec-cy1*])
      (safely name thunk)
      (rec-state-restore! num den ox oy turn clip cx0 cy0 cx1 cy1)))

  ;; Records one step's frame and sends it to the screen. When the screen
  ;; has no room for it yet, it asks again. A process may be switched out at
  ;; any call while core1's loop draws on, so (render-frame!) typed in a
  ;; REPL (a process) or called by a handler only asks for a frame.
  (define render-frame!
    (case-lambda
      [() (render-frame! #t)]
      [(asked?)
       (cond
         [(or (not asked?) (eq? *core0-mode* 'none) (eqv? *canvas-pw* 0))
          (void)]
         [(in-engine?) (request-frame!)]
         [(or (core0-hidden?) (gpu-frame-waiting?)) (request-frame!)]
         [else
          (let ([t0 (now-ns)] [waits *pacer-waits*])
            (core0-trace! 23 0)
            (set! *frame-draw-ns* t0)
            ;; An atlas that the last frame filled is emptied, and this
            ;; frame draws everything again (a new generation), since a list
            ;; holds its glyphs and tiles by their places there.
            (when *atlas-full?*
              (atlas-flush!)
              (set! *frame-generation* (+ *frame-generation* 1)))
            (rec-begin! *canvas-ratio*)
            (record-world!)
            (when *atlas-full?* (request-frame!))
            (frame-number-set! (rec-present!))
            (pacer-drew!)
            (set! *frame-publish-ns* (now-ns))
            (core0-trace! 24 *frame-number*)
            ;; its row first, since core0 may give it back at once
            (frame-ring-add!)
            (render-frames-back!)
            (set! *frame-ms* (fl/ (fixnum->flonum
                                   (- (now-ns) t0 (- *pacer-waits* waits)))
                                  1e6))
            (frame-ring-set! *frame-number* 0
                             (flonum->fixnum
                              (flround (fl* 1000.0 *frame-ms*)))))])]))

  ;; Hands each thing that core0 read back to its then.
  (define (render-answers!)
    (for-each (lambda (answer)
                (safely 'readback (lambda () ((car answer) (cdr answer)))))
              (gpu-take-answers!)))

  ;; Takes the frames core0 gave back, oldest first, from the chain they
  ;; come on, newest first: each is told to the pacer and marked in its row
  ;; as having reached the screen or not; it is counted if it did, and
  ;; otherwise a frame is asked for again. Then each thing core0 read back
  ;; is handed to its then.
  (define (render-frames-back!)
    (let back ([f (gpu-frames-back!)])
      (when f
        (back (gpu-frame-next f))
        (let ([shown? (gpu-frame-shown? f)])
          (set! *frame-back* (gpu-frame-number f))
          (pacer-frame-back! shown?)
          (pacer-latch! (gpu-frame-number f))
          (frame-ring-set! (gpu-frame-number f) 5 (if shown? 1 2))
          (if shown?
              (set! *frames-drawn* (+ *frames-drawn* 1))
              (request-frame!))
          (gpu-frame-free! f))))
    (render-answers!))

  ;; Hands then, on core1 and with nothing waiting, the screen as it would
  ;; be drawn now: its pixels, row after row, in premultiplied BGRA. This is
  ;; what screenshots see.
  (define (screen-bytes-then then)
    (drawing->bytes-then *canvas-pw* *canvas-ph* *canvas-ratio* record-world! #f
                         then)))
