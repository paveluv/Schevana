;;; pacer.ss — when the world's ticks come, and what became of each
;;; frame: the pacer, which keeps ticks to the screen's refreshes, and the
;;; numbers kept of the last frames. Below what draws the screen
;;; (src/core1/wm.ss), which tells it of each frame drawn and given back,
;;; and under the loop (src/core1/system.ss), which asks it when to tick.

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
;; screen's reports teach: the compositor's deadline and the GPU's work;
;; or #f, nothing taught yet (pacer-margin)
(defvar *pacer-margin* #f)
;; what the pacer judged: frames, those late of its own, the compositor's
(defvar *pacer-counts* (make-fxvector 3 0))
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
;; frames judged since the last whose GPU work was still going more than
;; a refresh and an eighth after its send, once such a frame taught the
;; pacer (pacer-behind!); or #f
(defvar *pacer-gpu-taught* #f)
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

;; the last frame's time: its work, not its wait for the screen
(defvar *frame-ms* 0.0)
(defvar *frames-drawn* 0)
;; the newest frame core0 gave back: sent, or found no room
(defvar *frame-back* 0)

;; The last frames, for kits/inspect.ss: what each took and held, and what
;; became of it (1 it reached the screen, 2 the window had no room, 0 not
;; given back yet); its number (its report's, core0-frame-report), and when
;; the oldest input it shows came (now-ns; 0, none) by SDL's stamp; then
;; when its tick began, its draw began and it was published, and when that
;; input came by core0's pump and by the compositor's time; the latch its
;; tick aimed at (0, none), and when the pacer meant its tick to begin.
;; Always kept: a few numbers a frame, for as many frames as the reports
;; keep.
(define frame-ring-rows 2048)
(define frame-ring-words 15)
(defvar *frame-ring* (make-fxvector (* frame-ring-rows frame-ring-words) 0))
(defvar *frame-ring-n* 0)   ; frames so far
;; the frame being drawn's number, its times, and the oldest input not
;; drawn yet three ways (core0-input-ns-take!)
(defvar *frame-number* 0)
(defvar *frame-tick-ns* 0)
(defvar *frame-draw-ns* 0)
(defvar *frame-publish-ns* 0)
(defvar *frame-input-ns* 0)
(defvar *frame-input-pumped* 0)
(defvar *frame-input-wl* 0)

(define (frame-number-set! n) (set! *frame-number* n))
;; The tick began at now (now-ns), or, unpaced, its ms: the pacer's read.
(define (frame-ticked! now)
  (set! *frame-tick-ns* (or now (* *pacer-tick-ms* 1000000))))

;; Input came (now-ns; 0, none), by SDL's stamp, core0's pump and the
;; compositor: the next frame shows it, if no older input waits.
(define (frame-input-came! ns pumped wl)
  (unless (or (eqv? ns 0) (not (eqv? *frame-input-ns* 0)))
    (set! *frame-input-ns* ns))
  (unless (or (eqv? pumped 0) (not (eqv? *frame-input-pumped* 0)))
    (set! *frame-input-pumped* pumped))
  (unless (or (eqv? wl 0) (not (eqv? *frame-input-wl* 0)))
    (set! *frame-input-wl* wl)))

;; Input that asked for no frame: no frame shows it.
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
    (frame-input-drop!)
    (fxvector-set! ring at 0)
    ;; the frame's, published: the recorder writes nothing now
    (let-values ([(recs-n extras-n) (rec-last-sizes)])
      (fxvector-set! ring (+ at 1) (fxquotient recs-n 32))
      (fxvector-set! ring (+ at 2) (fxquotient extras-n 4)))
    (fxvector-set! ring (+ at 3) (length (rec-runs)))
    (fxvector-set! ring (+ at 4) *glyph-count*)
    (fxvector-set! ring (+ at 5) 0))
  (set! *frame-ring-n* (+ *frame-ring-n* 1)))

;; Where frame n's row starts, among the newest sixteen, which hold every
;; frame not given back or judged yet; else #f.
(define (frame-ring-at n)
  (let loop ([i (- *frame-ring-n* 1)] [j 0])
    (and (< j 16) (>= i 0)
         (let ([at (* frame-ring-words (modulo i frame-ring-rows))])
           (if (eqv? (fxvector-ref *frame-ring* (+ at 6)) n)
               at
               (loop (- i 1) (+ j 1)))))))

;; Word k of frame n's row set to v, while the ring has it.
(define (frame-ring-set! n k v)
  (let ([at (frame-ring-at n)])
    (when at (fxvector-set! *frame-ring* (+ at k) v))))

;;; ------------------------------------------------------------------ pacing

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
  (let* ([p (if (eq? *pacer-rate* 'screen) (core0-frame-ns) (pacer-period))]
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
      (let ([p (core0-frame-ns)]) (- p (quotient p 500)))
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
  (let* ([r (core0-frame-ns)] [half (quotient r 2)]
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

;; The newest frame before n the screen has reported on, shown or dropped,
;; among the eight before it; else #f.
(define (pacer-reported-before n)
  (let loop ([m (- n 1)])
    (and (> m (- n 9)) (> m 0)
         (if (memv (core0-frame-report m 1) '(1 2)) m (loop (- m 1))))))

;; Each frame up to m whose report is in, and not judged yet, judged once
;; (pacer-behind!), from at most eight back.
(define (pacer-judge! m r)
  (let loop ([k (max (+ *pacer-judged* 1) (- m 8))])
    (unless (> k m)
      (set! *pacer-judged* k)
      (pacer-count! 0)
      (pacer-behind! k r)
      (loop (+ k 1)))))

(define (pacer-count! k)
  (fxvector-set! *pacer-counts* k (fx+ 1 (fxvector-ref *pacer-counts* k))))

;; A trial from now, '() for none; what the pacer learned under another
;; forgotten.
(define (pacer-trial! alist)
  (set! *pacer-trial* alist)
  (pacer-relearn!))

;; A choice as a fraction of refresh r, or seconds, as ns.
(define (pacer-of-refresh key r) (exact (floor (* (pacer-knob key) r))))
(define (pacer-seconds key) (exact (floor (* (pacer-knob key) 1000000000))))

;; The margin: as the screen taught it, else where it starts. It fades as
;; pacer-margin-fade has it, the platform's by default: on a Mac in a
;; minute; elsewhere never, as finding out whether the compositor would
;; take frames later again costs a frame late.
(define (pacer-margin r)
  (or *pacer-margin* (pacer-of-refresh 'pacer-margin-start r)))

;; What the pacer learned forgotten, as at a run's start.
(define (pacer-relearn!)
  (set! *pacer-margin* #f)
  (set! *pacer-floor* 0)
  (set! *pacer-depth* 0)
  (set! *pacer-made* #f)
  (set! *pacer-late-seen* 0)
  (set! *pacer-late-chain* 0)
  (set! *pacer-gpu-taught* #f)
  (set! *pacer-lead* (quotient (core0-frame-ns) 4)))

;; Frame n, its report in, aimed at a latch: late if it showed a refresh
;; or more after the one aimed for, the first after the latch and the
;; compositor's depth on. Sent about the margin before the latch, as the
;; pacer sends them (no more than pacer-miss-own past it), that was too
;; little: the margin grows past it by a step (pacer-margin!); a run of
;; late frames sent alike raises it once. Sent well before it, or no
;; closer to it than a frame that made its latch lately (pacer-made!), and
;; late all the same, the compositor missed the refresh, not the frame:
;; nothing to learn; unless it's the third late run in a chain, as at a
;; deadline that comes and goes, which a compositor's misses now and then
;; seldom make. Nor from the frames late behind the run's first, sent
;; before the pacer saw it: they waited behind it. One sent since, and
;; late still, however early, teaches: no one missed refresh makes that.
;; A late frame that teaches is counted the pacer's own, any other the
;; compositor's. Sent as the pacer sends them and shown sooner than the
;; depth, the compositor keeps frames less long now: the depth falls to
;; it. In time, the margin fades as pacer-margin-fade has it. What frames
;; whose GPU work was still going a refresh and an eighth after their send
;; taught is the GPU's, not the compositor's (a GPU too slow for the
;; refresh: one slow to wake as an app opens, three refreshes of queue
;; taught in a quarter second, or an app too heavy for it): once 240
;; frames are judged with none of them so slow, the pacer learns afresh
;; (pacer-relearn!). => whether it was late
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

;; The deepest a compositor is taken to keep frames, refreshes: one more
;; than the deepest seen (WindowServer's).
(define pacer-depth-most 3)

;; The margin grown to m at least. A margin of a refresh or more is the
;; compositor's depth: frames sent a refresh earlier for the latch before
;; are frames sent for this one, shown a refresh later. So it carries into
;; the depth, which a compositor whose latch comes after the acquire's end
;; has (WindowServer frees an image at a refresh and keeps a frame two
;; more), and the margin is learned afresh, from where it starts: what's
;; past the refresh came of frames sent early; pacer-depth-most at most.
(define (pacer-margin! m r)
  (let ([m (max (pacer-margin r) m)])
    (if (and (>= m r) (< *pacer-depth* pacer-depth-most))
        (begin
          (set! *pacer-depth* (+ *pacer-depth* 1))
          (set! *pacer-margin* #f))
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
  (and (eqv? (core0-frame-report n 1) 1) (core0-frame-report n 3)))

;; Frame n, sent: the lead follows what it took from when its tick was
;; meant to begin till core0 sent it (core1 waking late and core0 taking it
;; late among it), with the margin, at once when that's more, else fading
;; (pacer-lead-fade, a spike's time to fade); two refreshes at most, so
;; that a lead longer than a refresh still leaves a tick its time at 120
;; Hz. An acquire the screen held (over 1 ms, as pacer-latch! has it),
;; and the frame's wait for core0 before it, held in the frame before's,
;; are the screen's time, not the frame's: a lead they grew would send the
;; frames after it early, into the same full queue, to wait longer still,
;; till each waited a refresh published and a refresh for its image.
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

;; A tick sent a frame: the screen goes on pacing (*pacer-shown?*). One held
;; back (the window hidden) gives it nothing to pace by.
(define (pacer-drew!) (set! *pacer-drew?* #t))

;; What a tick does, its frame turn: what's on the screen looks at what
;; changed and draws (src/core1/wm.ss sets this); till then nothing.
(defvar *pacer-turn* void)

;; A tick: the frames windows asked for and the surfaces' (wm-tick!), then
;; a frame if one is asked for. Paced (now, the ns it began, else #f), the
;; next may come a period after this one was due, or, when that is past
;; already (this one held for core0, or the first after a quiet spell), a
;; period from now; never past two: ticks that came early, a period on each,
;; would put it off without end, and the world with it.
(define (pacer-tick! now)
  (set! *pacer-aimed* (if (pacer-on-latch?) (pacer-aim) 0))
  (set! *pacer-planned*
    (if (> *pacer-aimed* 0) (- *pacer-aimed* *pacer-lead*) (or now 0)))
  (when now
    (set! *pacer-began* now)
    (let ([next (+ *pacer-due* (pacer-period))])
      (set! *pacer-due*
        (if (> next now)
            (min next (+ now (* 2 (pacer-period))))
            (+ now (pacer-period))))))
  (set! *pacer-wanted?* #f)
  ;; a tick that sent the screen nothing leaves it nothing to pace by
  (unless *pacer-drew?* (set! *pacer-shown?* #f))
  (set! *pacer-drew?* #f)
  (set! *pacer-ticks* (+ *pacer-ticks* 1))
  (set! *pacer-tick-ms* (now-ms))
  (set! *pacer-frame-ns*
    (if now (pacer-next-frame-ns now) (* *pacer-tick-ms* 1000000)))
  (safely 'tick *pacer-turn*))

;; Core0, on a thread of its own, gave back a frame that reached the screen
;; (shown?) or not: by vsync, at the screen's rate, the screen held it, and
;; so paces the next tick (pacer-start).
(define (pacer-frame-back! shown?)
  (set! *pacer-shown?*
    (and shown?
         (core0-forked?)
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

;; How long a paced step may wait for core0's events (input ends the wait at
;; once): until the next tick may begin, a period with none wanted (so mail
;; is seen) or while core0 still has the last frame to take (it wakes core1
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
