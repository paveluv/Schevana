;;; apps/pipeline.ss — Pipeline: the way from a window's draw to the screen
;;; surface, on one screen, read through kits/inspect.ss.
;;;
;;; Five stages, chosen on the cards at the top:
;;;   Lists   the frame's list by who drew it, and each's records, decoded
;;;           in draw order, a run of glyphs as its text; a drawer's checkbox
;;;           off leaves it out of the small screen and the Tape
;;;   Who     what each drawer cost: main's time drawing it, its records, the
;;;           pixels they may touch, the runs they start, what changed
;;;   Course  a tick's stages in order, each as wide as its time, render
;;;           split into each drawer's draw and the rest
;;;   Inside  the record selected, decoded, and the shader it's drawn with,
;;;           its source and its helpers'
;;;   Memory  what draws, what it holds on the GPU, and the glyphs' atlas
;;; Right, the screen small, the selected record outlined, or shown another
;;; way: who drew each record, in its drawer's color, the selected one's
;;; bright; each record's kind; heat, a pixel as bright as how many records
;;; cover it; or what changed since the frame before. A press there
;;; lists the records that may touch that pixel. It draws again every tick, or
;;; as seldom as it's told, and it's on the screen it shows: so it's in itself,
;;; a tick older each time round. The wheel zooms it at the pointer and a drag
;;; moves it; a loupe magnifies the pixels at the pointer; and it pops out to a
;;; window of its own above the Pipeline, coming back when that one closes.
;;; Under them, the Tape: a mark a record in draw order, as tall as what it may
;;; cover, and in lanes who drew it and its kind. A press there, or its
;;; stepper, holds the frame and draws it as far as that record, the record
;;; selected; Play draws it record by record. What's selected in the list, or
;;; at a pixel, is marked on it, and named on its heading, with Clear (or
;;; Esc); a record selected opens its drawer in the tree, and stays with its
;;; drawer as the frame changes. A drawer keeps its color while it's open.
;;; Below, the River: a bar a tick as it flows, what main did, and in lanes
;;; over them what else happened. A press holds it and goes back to that
;;; tick's frame, the whole app showing it; a drag moves through them. Frames
;;; are kept for a few seconds, what's left of the River's reach, while it's
;;; open: closed, what's left of it is the core's few numbers a frame.
;;; While it flows it asks for a frame a tick, so it says what it takes itself.

(define-record-type pipeline-view
  (fields ui history river
          (mutable stage)      ; lists, who, course, inside, memory, latency
          (mutable shown)      ; (inspect-list), the one on view
          (mutable held?)      ; it stays
          (mutable looked)     ; when it was read, or due to be (now-ms)
          (mutable groups)     ; its spans: (label first count) ...
          (mutable selected)   ; a drawer's node or a record's row, or #f
          (mutable traced)     ; the records at a pixel, or #f: (x y n ...)
          (mutable upto)       ; the slider's record, or #f: all of them
          (mutable image)      ; the small screen on view, or #f
          (mutable back)       ; what its next picture is drawn on, or #f
          (mutable flip?)      ; back has a newer picture than image
          (mutable reach)      ; while held, where the River stops: (newest
                               ; . oldest)
          (mutable tick)       ; the tick picked, or #f
          (mutable order)      ; how the River's bars stack: columns
          (mutable own)        ; what it takes itself, ms a tick
          (mutable tip)        ; the last bar's tooltip: (seq . text)
          (mutable every)      ; the small screen draws every this many frames
          (mutable tape)       ; the Tape, a stream a record
          (mutable tape-of)    ; the records it holds: kept, as it was
          (mutable playing)    ; while it plays, how far it has: a number
          (mutable play-secs)  ; how long it plays the whole frame
          (mutable zoom)       ; device pixels a screen pixel, or #f: all of it
          (mutable center)     ; the screen's pixel at the middle: (x . y)
          (mutable loupe?)
          (mutable popped)     ; its window when it's popped out, or #f
          (mutable off)        ; the spans left out, by node: (label k) ...
          (mutable kept)       ; the records drawn of the list on view, a
                               ; vector in order: what the Tape goes through
          (mutable kept-of)    ; the list on view it's of
          (mutable look)       ; what the small screen shows: pipeline-looks
          (mutable painted)    ; a list repainted for it, used again
          (mutable who)        ; what each drew cost: (list . rows)
          (mutable course)     ; a tick's stages: (list . (seq items))
          (mutable course-sort) ; (key . up|down), or #f: in their order
          (mutable who-sort)   ; (key . up|down), or #f: in draw order
          latency              ; the Latency's stream, a tick a bar
          (mutable latency-words) ; (when . words), read twice a second
          colors))             ; each drawer's color, by node: an index

(define pipeline-period-ms 1000)

;; About 5 seconds at 60 Hz.
(define pipeline-frames-kept 300)
(define pipeline-river-rows 2048)
(define pipeline-bar-px 3)

(define (pipeline-show! v l)
  (let ([place (pipeline-selected-place v)])
    (pipeline-view-shown-set! v l)
    (pipeline-view-groups-set! v (inspect-list-labels l))
    ;; a new drawer's color, in draw order
    (for-each (lambda (node) (pipeline-color-index v node))
              (pipeline-span-nodes (inspect-list-labels l)))
    (when place
      (pipeline-view-selected-set! v (pipeline-place-row v place)))))

;; What a profiler's node took, ms a tick, over the half second to tick newest.
(define (pipeline-ms-over node newest)
  (let ([seqs (filter profile-tick-kept?
                      (map (lambda (i) (- newest i)) (iota 30)))])
    (/ (fold-left (lambda (ms seq) (+ ms (profile-tick-node-ms seq node)))
                  0.0 seqs)
       (max 1 (length seqs)))))

;; What the window takes itself, ms a tick, over the last half second.
(define (pipeline-own-ms)
  (let ([win (find-window 'pipeline)] [newest (profile-newest-tick)])
    (if (and win newest)
        (pipeline-ms-over (profile-subject-of win) newest)
        0.0)))

(define (pipeline-look! v)
  (unless (pipeline-view-held? v)
    (let ([history (pipeline-view-history v)] [newest (profile-newest-tick)])
      (inspect-history-add! history)
      (pipeline-show! v (or (inspect-history-ref
                             history (inspect-history-newest history))
                            (inspect-list)))
      (pipeline-view-own-set! v (pipeline-own-ms))
      (when newest
        (pipeline-view-order-set!
         v (monitor-bars-order
            (monitor-range (max (profile-oldest-tick)
                                (- newest pipeline-frames-kept))
                           newest))))))
  (pipeline-view-looked-set! v (now-ms)))

;; What's on view, drawn on image, but the spans left out. Live, it's drawn
;; with the next frame, as far as the slider says; held, what's kept of the
;; frame is. Showing who drew, it's a frame kept, repainted: live, the one
;; just drawn.
(define (pipeline-preview-on! v image)
  (let ([l (pipeline-view-shown v)] [upto (pipeline-view-upto v)]
        [left-out (pipeline-left-out-of v)])
    (cond
      [(not (eq? (pipeline-view-look v) 'picture))
       (let* ([h (pipeline-view-history v)]
              [from (if (pipeline-view-held? v)
                        l
                        (or (inspect-history-ref h (inspect-history-newest h))
                            l))])
         (inspect-preview-list! image (pipeline-painted v from)
                                (or upto (inspect-list-count from)) left-out))]
      [(pipeline-view-held? v)
       (inspect-preview-list! image l (or upto (inspect-list-count l))
                              left-out)]
      [else
       (inspect-preview! image (or upto (most-positive-fixnum)) left-out)])))

;; At once, on the image that frame shows. An image can't show itself as it's
;; drawn on, so its own box stays empty.
(define (pipeline-preview! v)
  (let ([image (pipeline-view-image v)])
    (when image (pipeline-preview-on! v image))))

;; A tick's, on the other image, so the frame showing the one on view is drawn
;; whole. It comes on view at the next tick: pipeline-flip!.
(define (pipeline-preview-back! v)
  (let ([back (pipeline-view-back v)])
    (when back
      (pipeline-preview-on! v back)
      (pipeline-view-flip?-set! v #t))))

(define (pipeline-flip! v)
  (when (pipeline-view-flip? v)
    (let ([image (pipeline-view-image v)])
      (pipeline-view-image-set! v (pipeline-view-back v))
      (pipeline-view-back-set! v image)
      (pipeline-view-flip?-set! v #f))))

;;; ---- going back

;; The frame on the screen when tick seq ended.
(define (pipeline-tick-frame seq) (- (profile-tick-ns seq 'frames) 1))

;; It stops flowing, and the frames stay as they are, the last one among them.
(define (pipeline-hold! v)
  (unless (pipeline-view-held? v)
    (inspect-history-add! (pipeline-view-history v))
    (pipeline-view-held?-set! v #t)
    (pipeline-view-flip?-set! v #f)
    (pipeline-view-tick-set! v (profile-newest-tick))
    (pipeline-view-reach-set! v (cons (profile-newest-tick)
                                      (profile-oldest-tick)))
    (pipeline-preview! v)))

(define (pipeline-resume! v)
  (pipeline-view-held?-set! v #f)
  (pipeline-view-tick-set! v #f)
  (pipeline-view-traced-set! v #f)
  (pipeline-view-playing-set! v #f)
  (pipeline-look! v)
  (pipeline-preview! v))

;; Goes back to tick seq: the whole app shows its frame, if it's still kept.
(define (pipeline-pick! v seq)
  (pipeline-hold! v)
  (when (profile-tick-kept? seq)
    (pipeline-view-tick-set! v seq)
    (let ([l (inspect-history-ref (pipeline-view-history v)
                                  (pipeline-tick-frame seq))])
      (when (and l (not (eq? l (pipeline-view-shown v))))
        (pipeline-show! v l)
        (pipeline-view-traced-set! v #f)
        (pipeline-preview! v)))))

;;; ---- the River

;; How bright a tick's collecting is: a level by its time, faint however short,
;; and at its brightest from this many ns.
(define pipeline-collector-levels 8)
(define pipeline-collector-full-ns 2000000)

(define (pipeline-collector-level ns)
  (+ 1 (quotient (* (- pipeline-collector-levels 1)
                    (min (max ns 0) pipeline-collector-full-ns))
                 pipeline-collector-full-ns)))

;; Bottom up, as monitor-bars-order stacks them, what main did; over them, the
;; lanes, a word each: late, or held by the screen; then a frame's way out:
;; sent, or no room; its GPU work, done in time or late; what the screen
;; says of it, shown in time, late, or dropped; then the collector, by how
;; long; input.
(define pipeline-draw-lanes
  `(("late" chart-flag chart-2)
    ("frame" chart-ok chart-flag)
    ("GPU" chart-ok chart-flag)
    ("screen" chart-ok chart-flag chart-2)
    ("collector"
     ,@(map (lambda (i)
              (alpha 'chart-7
                     (+ 0.2 (* 0.8 (/ i (- pipeline-collector-levels 1.0))))))
            (iota pipeline-collector-levels)))
    ("input" chart-1)))

;; What a lane's colors say, on its label.
(define pipeline-lane-tips
  `("Red: this tick came late, its own time past one and a half periods. \
     Orange: the screen held the host that long, which main doesn't count \
     as late. None: it was in time."
    "Green: core0 sent the tick's frame to the screen. Red: the window had no \
     room for it. None: no frame was drawn."
    "When core0 saw the frame's GPU work done. Green: in time for its \
     refresh. Red: after the refresh it missed, the GPU's fault, not the \
     screen's. None: not seen."
    "What the screen says of the tick's frame. Green: it showed a refresh \
     after the one before. Red: the one before showed again first, while \
     frames came a refresh apart. Orange: the compositor dropped it. None: \
     no frame, or no word from the screen (only Wayland's compositors say)."
    ,(format "A collection ran in this tick: the longer it took, the brighter, \
              at its brightest from ~a."
             (monitor-ns-text pipeline-collector-full-ns))
    "The keyboard or the mouse sent something."))

;; Whether tick seq drew a frame.
(define (pipeline-tick-drew? seq)
  (or (not (profile-tick-kept? (- seq 1)))
      (> (profile-tick-ns seq 'frames) (profile-tick-ns (- seq 1) 'frames))))

;; The frame tick seq drew, counting from 0 (inspect-frame-ref).
(define (pipeline-tick-frame-index seq) (- (profile-tick-ns seq 'frames) 1))

;; The lanes' readings of tick seq, in words, for its tooltip.
(define (pipeline-tick-lanes seq)
  (let* ([drew? (pipeline-tick-drew? seq)]
         [i (pipeline-tick-frame-index seq)]
         [ms (lambda (ns) (/ ns 1e6))])
    (string-append
     (if drew?
         (format "\nframe ~a~a~a~a"
                 (if (> (profile-tick-ns seq 'shown) 0)
                     "sent"
                     "had no room")
                 (case (inspect-frame-screen i)
                   [(shown) "; it showed in time"]
                   [(late) (format "; it showed late, ~a refresh~a missed"
                                   (inspect-frame-missed i)
                                   (if (eqv? (inspect-frame-missed i) 1)
                                       ""
                                       "es"))]
                   [(dropped) "; the compositor dropped it"]
                   [else ""])
                 (let ([l (inspect-frame-latency i)])
                   (if l
                       (format ", ~,1f ms after the input it shows" (ms l))
                       ""))
                 (let ([done (inspect-frame-report i 6)]
                       [sent (inspect-frame-report i 2)])
                   (if (and done (> done 0))
                       (format "; its GPU work seen done ~,1f ms after it \
                                was sent~a"
                               (ms (- done sent))
                               (if (eq? (inspect-frame-gpu i) 'late)
                                   ", too late"
                                   ""))
                       "")))
         "\nno frame drawn")
     (if (> (profile-tick-ns seq 'gcs) 0)
         (format "\ncollected for ~,2f ms"
                 (/ (profile-tick-ns seq 'gc-ns) 1000000.0))
         ""))))

(define (pipeline-river-word period)
  (let ([phases (length monitor-phases)])
    (lambda (seq j)
      (if (< j phases)
          (quotient (monitor-tick-phase-ns seq j) 1000)
          (let ([drew? (pipeline-tick-drew? seq)]
                [i (pipeline-tick-frame-index seq)])
            (case (- j phases)
              [(0) (cond [(profile-tick-late? seq period) 1]
                         [(profile-tick-held? seq period) 2]
                         [else 0])]
              [(1) (cond [(not drew?) 0]
                         [(> (profile-tick-ns seq 'shown) 0) 1]
                         [else 2])]
              [(2) (if drew?
                       (case (inspect-frame-gpu i)
                         [(done) 1] [(late) 2] [else 0])
                       0)]
              [(3) (if drew?
                       (case (inspect-frame-screen i)
                         [(shown) 1] [(late) 2] [(dropped) 3] [else 0])
                       0)]
              [(4) (if (> (profile-tick-ns seq 'gcs) 0)
                       (pipeline-collector-level (profile-tick-ns seq 'gc-ns))
                       0)]
              [else (if (> (profile-tick-ns seq 'input) 0) 1 0)]))))))

;; A bar's tooltip, worked out once: a held River draws for each move.
(define (pipeline-river-tip v seq period)
  (let ([tip (pipeline-view-tip v)])
    (if (and tip (eqv? (car tip) seq))
        (cdr tip)
        (let ([text (string-append
                     (monitor-tick-tip seq (monitor-clock-zero) period)
                     (pipeline-tick-lanes seq))])
          (pipeline-view-tip-set! v (cons seq text))
          text))))

;; A line where the frames kept end, left of it ticks whose frames are gone.
(define (pipeline-draw-reach v areas count newest)
  (let ([history (pipeline-view-history v)]
        [plot (cdr (assq 'plot areas))])
    (let loop ([i (- count 1)])
      (when (>= i 0)
        (let ([seq (+ newest (- i count -1))])
          (if (and (profile-tick-kept? seq)
                   (inspect-history-kept? history (pipeline-tick-frame seq)))
              (loop (- i 1))
              (let-values ([(bx bw) (ui-bar-chart-bar areas count i)])
                (when (and (< i (- count 1)) (>= bx (car plot)))
                  (fill-box (+ bx bw -1) (cadr plot) 1 (cadddr plot)
                            'chart-rule)))))))))

;; The tick picked stands out, whatever's on it.
(define (pipeline-draw-picked areas count newest tick)
  (let-values ([(bx bw) (ui-bar-chart-bar areas count
                                          (- count 1 (- newest tick)))])
    (let ([plot (cdr (assq 'plot areas))])
      (when (>= bx (car plot))
        (stroke-box (- bx 1) (cadr plot) (+ bw 1) (cadddr plot) 'accent 1)))))

;; The River's height for this width's legend, its heading and legend included.
(define (pipeline-river-height v w)
  (let-values ([(gw gh) (ui-label-size '(group) "River" w)]
               [(kw kh) (ui-legend-size (pipeline-river-keys v))])
    (+ gh 4 (ui-stream-room pipeline-draw-lanes) 96 4 kh)))

(define (pipeline-river-keys v)
  (map (lambda (j) (cdr (list-ref monitor-phases j)))
       (pipeline-view-order v)))

(define (pipeline-river-words v)
  (let ([tick (pipeline-view-tick v)] [held? (pipeline-view-held? v)])
    (if (and held? tick)
        (let ([l (and (profile-tick-kept? tick)
                      (inspect-history-ref (pipeline-view-history v)
                                           (pipeline-tick-frame tick)))])
          (if l
              (format "tick ~a, frame ~a: ~a records" tick
                      (inspect-list-frame l) (inspect-list-count l))
              (format "tick ~a: its frame is no longer kept" tick)))
        (format "a bar a tick; the last ~a frames kept; it takes ~,2f ms a \
                 tick itself"
                (inspect-history-count (pipeline-view-history v))
                (pipeline-view-own v)))))

;; The newest tick whose frame the screen has had time to report on, six
;; periods back: the River sends those after it again each time, till what
;; became of their frames is known. #f with none yet.
(define (pipeline-settled-tick period)
  (let ([oldest (profile-oldest-tick)] [since (- (now-ns) (* 6 period))])
    (let loop ([seq (profile-newest-tick)])
      (cond [(or (not seq) (not oldest) (< seq oldest)) #f]
            [(> (profile-tick-ns seq 'end) since) (loop (- seq 1))]
            [else seq]))))

(define (pipeline-river-pane v x y w h)
  (let*-values
      ([(ui) (pipeline-view-ui v)]
       [(river) (pipeline-view-river v)]
       [(period) (pacer-period)]
       [(top) (quotient (* 2 period) 1000)]
       [(rules) (append (pipeline-river-rules period)
                        (pipeline-gutter-rules period))]
       [(reach) (pipeline-view-reach v)]
       [(held?) (pipeline-view-held? v)]
       [(newest) (if held? (car reach) (profile-newest-tick))]
       [(oldest) (if held? (cdr reach) (profile-oldest-tick))]
       [(keys) (pipeline-river-keys v)]
       [(gw gh) (ui-label-size '(group) "River" w)]
       [(kw kh) (ui-legend-size keys)]
       [(sy) (+ y gh 4)]
       [(sh) (- h gh 4 4 kh)])
    (ui-draw-label x y w gh '(group) "River")
    (ui-draw-label x y w gh '(dim right) (pipeline-river-words v))
    (when (and newest (not held?))
      (ui-stream-resend! river (+ 1 (or (pipeline-settled-tick period)
                                        (- oldest 1))))
      (ui-stream-send! river oldest newest (pipeline-river-word period)))
    (ui-stream ui 'pipeline-river river x sy w sh newest oldest top rules
               (map (lambda (j) (cons j (cadr (list-ref monitor-phases j))))
                    (pipeline-view-order v))
               pipeline-bar-px
               'doc '((L . "Go back to this tick"))
               'strip-tips pipeline-lane-tips
               'tip (lambda (seq)
                      (and (profile-tick-kept? seq)
                           (pipeline-river-tip v seq period)))
               'on-pick (lambda (seq) (pipeline-pick! v seq))
               'marked (if (pipeline-view-tick v)
                           (list (pipeline-view-tick v))
                           '())
               'over (lambda (areas count)
                       (when newest
                         (pipeline-draw-reach v areas count newest)
                         (when (pipeline-view-tick v)
                           (pipeline-draw-picked areas count newest
                                                 (pipeline-view-tick v))))))
    (ui-draw-legend x (+ sy sh 4) w kh '() keys)))

;;; ---- Latency
;;; A bar a tick, over the River's and as wide, its frame's points stacked
;;; on one line, the publish: below it what led up to it, from its oldest
;;; input (by the compositor's own time, then SDL's stamp, then when core0
;;; first saw it) through main's tick and draw; above it what came after,
;;; core0 taking it, sending it, its GPU work done, and the screen showing
;;; it. Over the bars, the frames the screen froze a refresh for, or dropped.

;; The parts of a bar bottom up, each from the point before it: (point
;; color . label); the first, clear, lifts the bar to the publish line.
(define pipeline-draw-latency-parts
  '((#f #f . #f)
    (sdl chart-muted-1 . "the compositor's time to SDL's stamp")
    (pumped chart-7 . "to core0's pump")
    (tick chart-6 . "to main's tick")
    (draw chart-5 . "to its draw")
    (publish chart-1 . "drawing")
    (taken chart-2 . "to core0's take")
    (sent chart-3 . "to its send")
    (gpu chart-4 . "to the GPU's done")
    (shown chart-8 . "to the screen")))
(define pipeline-draw-latency-strips '(("screen" chart-flag text-faint)))
(define pipeline-latency-below 3)   ; refreshes under the publish line
(define pipeline-latency-above 4)   ; and over it

(define (pipeline-latency-new)
  (ui-stream-new pipeline-river-rows (length pipeline-draw-latency-parts)
                 pipeline-draw-latency-strips))

;; Frame i's point k of its bar (now-ns), lifted to the one before it when
;; missing or earlier: 0 its floor, the publish less the room below; 1 its
;; oldest input, or what comes first; then pipeline-draw-latency-parts'; all
;; within the bar's room.
(define (pipeline-latency-at i k p)
  (let* ([publish (inspect-frame-at i 'publish)]
         [low (- publish (* pipeline-latency-below p))]
         [high (+ publish (* pipeline-latency-above p))])
    (let loop ([j 1]
               [at (max low (or (inspect-frame-at i 'wl)
                                (inspect-frame-at i 'sdl)
                                (inspect-frame-at i 'pumped)
                                (inspect-frame-at i 'tick)
                                (inspect-frame-at i 'draw)
                                publish))])
      (cond
        [(= k 0) low]
        [(= j k) (min high at)]
        [else
         (loop (+ j 1)
               (max at (or (inspect-frame-at
                            i (car (list-ref pipeline-draw-latency-parts j)))
                           at)))]))))

;; Tick seq's word j, µs: a part of its frame's bar, then the screen's
;; strip (1 froze a refresh, 2 dropped); 0 with no frame.
(define (pipeline-latency-word p)
  (let ([word (pipeline-latency-frame-word p)])
    (lambda (seq j)
      (if (and (profile-tick-kept? seq) (pipeline-tick-drew? seq))
          (word (pipeline-tick-frame-index seq) j)
          0))))

;; The same of frame i.
(define (pipeline-latency-frame-word p)
  (lambda (i j)
    (cond
      [(not (inspect-frame-at i 'publish)) 0]
      [(= j (length pipeline-draw-latency-parts))
       (cond [(eqv? (inspect-frame-report i 1) 2) 2]
             [(let ([m (inspect-frame-missed i)]) (and m (> m 0))) 1]
             [else 0])]
      [else (quotient (- (pipeline-latency-at i (+ j 1) p)
                         (pipeline-latency-at i j p))
                      1000)])))

;; Frame i's points as a tooltip: each that came, ms from its publish.
(define (pipeline-latency-tip i)
  (let ([publish (inspect-frame-at i 'publish)])
    (and publish
         (string-join
          (cons
           (format "frame ~a~a" (inspect-frame-ref i 6)
                   (case (inspect-frame-screen i)
                     [(late) ", the screen froze a refresh before it"]
                     [(dropped) ", dropped by the screen"]
                     [else ""]))
           (filter values
                   (map (lambda (point label)
                          (let ([t (inspect-frame-at i point)])
                            (and t (format "~a: ~,2f ms" label
                                           (/ (- t publish) 1e6)))))
                        '(wl sdl pumped tick draw publish taken sent gpu
                          shown)
                        '("input, by the compositor" "input, by SDL"
                          "input, seen by core0" "tick" "draw" "publish"
                          "core0's take" "sent" "GPU done" "on screen"))))
          "\n"))))

;; Input to screen over the last 10 s, ms at the median and the 99th, by
;; the compositor's time, SDL's stamp and core0's pump: a phrase each, read
;; twice a second at most.
(define (pipeline-latency-words v)
  (let ([was (pipeline-view-latency-words v)])
    (if (and was (< (- (now-ms) (car was)) 500))
        (cdr was)
        (let ([words
               (map (lambda (point name)
                      (let-values ([(p50 p99 missed)
                                    (inspect-frames-truth 10000 point)])
                        (if p50
                            (format "~a ~,1f, ~,1f" name (/ p50 1e6)
                                    (/ p99 1e6))
                            (format "~a none" name))))
                    '(wl sdl pumped)
                    '("compositor" "SDL" "core0's pump"))])
          (pipeline-view-latency-words-set! v (cons (now-ms) words))
          words))))

(define (pipeline-latency-pane v x y w h)
  (let*-values
      ([(ui) (pipeline-view-ui v)]
       [(s) (pipeline-view-latency v)]
       [(p) (pacer-period)]
       [(top) (quotient (* (+ pipeline-latency-below pipeline-latency-above) p)
                        1000)]
       [(rules) (append (pipeline-latency-rules p)
                        (pipeline-gutter-rules p))]
       [(reach) (pipeline-view-reach v)]
       [(held?) (pipeline-view-held? v)]
       [(newest) (if held? (car reach) (profile-newest-tick))]
       [(oldest) (if held? (cdr reach) (profile-oldest-tick))]
       ;; a row before the publish, a row after
       [(keys) (map cdr (cdr pipeline-draw-latency-parts))]
       [(before) (list-head keys 5)]
       [(after) (list-tail keys 5)]
       [(gw gh) (ui-label-size '(group) "Latency" w)]
       [(kw kh) (ui-legend-size keys)]
       [(sy) (+ y gh 4)]
       [(sh) (- h gh 4 4 kh 2 kh)])
    (ui-draw-label x y w gh '(group) "Latency")
    ;; with no small screen beside it, Hold is here
    (let-values ([(tw th) (ui-label-size '(group) "Latency" w)]
                 [(cw chh) (ui-checkbox-size "Hold")])
      (ui-checkbox ui '(pipeline hold) (+ x tw 16) y cw gh "Hold" held?
                   (lambda (on?)
                     (if on? (pipeline-hold! v) (pipeline-resume! v)))
                   'tip "Hold the flow still, as a press on a bar does; \
                         Esc lets it go"))
    (ui-draw-label x y w gh '(dim right)
                   (string-append "input to screen, the last 10 s, ms at \
                                   the median and the 99th: "
                                  (string-join (pipeline-latency-words v)
                                               "; ")))
    (when (and newest (not held?))
      ;; the screen reports a few refreshes on
      (ui-stream-resend! s (+ 1 (or (pipeline-settled-tick p) (- oldest 1))))
      (ui-stream-send! s oldest newest (pipeline-latency-word p)))
    (ui-stream ui 'pipeline-latency s x sy w sh newest oldest top rules
               (map (lambda (part j) (cons j (cadr part)))
                    pipeline-draw-latency-parts
                    (iota (length pipeline-draw-latency-parts)))
               pipeline-bar-px
               'doc '((L . "Go back to this tick"))
               'strip-tips '("Frames the screen froze a refresh for, \
                              in red; dropped ones, faint.")
               'tip (lambda (seq)
                      (and (profile-tick-kept? seq) (pipeline-tick-drew? seq)
                           (pipeline-latency-tip
                            (pipeline-tick-frame-index seq))))
               'on-pick (lambda (seq) (pipeline-pick! v seq))
               'marked (if (pipeline-view-tick v)
                           (list (pipeline-view-tick v))
                           '())
               'over (lambda (areas count)
                       (when (and newest (pipeline-view-tick v))
                         (pipeline-draw-picked areas count newest
                                               (pipeline-view-tick v)))))
    (ui-draw-legend x (+ sy sh 4) w kh '() before)
    (ui-draw-legend x (+ sy sh 4 kh 2) w kh '() after)))

;; Latency's rules: the publish, and refreshes before and after it.
(define (pipeline-latency-rules p)
  (map (lambda (k)
         (cons (quotient (+ (* pipeline-latency-below p) (* k p)) 1000)
               (if (= k 0)
                   "publish"
                   (format "~a~,1f ms" (if (> k 0) "+" "") (/ (* k p) 1e6)))))
       '(-2 -1 0 1 2 3)))

;; Rules at #f, the River's labels and Latency's both, so that the two
;; charts' bars start at one x and line up a tick to a tick.
(define (pipeline-gutter-rules p)
  (map (lambda (label) (cons #f label))
       (append (map cdr (pipeline-latency-rules p))
               (map car pipeline-draw-latency-strips)
               (map cdr (pipeline-river-rules p))
               (map car pipeline-draw-lanes))))

;; The River's rules: a period and two.
(define (pipeline-river-rules period)
  (list (cons (quotient period 1000) (monitor-ns-text period))
        (cons (quotient (* 2 period) 1000) (monitor-ns-text (* 2 period)))))

;;; ---- the Tape

;; A record's mark: as tall as the log of the pixels it may cover, 100 a
;; doubling, to 16M; in lanes, who drew it, and its kind.
(define pipeline-tape-top 2400)
(define pipeline-tape-rules '((1000 . "1K px") (2000 . "1M px")))
(define pipeline-tape-kinds '(box segment polygon glyph shadow))
(define pipeline-draw-tape-who
  '(chart-1 chart-2 chart-3 chart-4 chart-5 chart-6 chart-7 chart-8))
(define pipeline-draw-tape-lanes
  `(("who" ,@pipeline-draw-tape-who)
    ;; box segment polygon glyph shadow
    ("kind" text-faint chart-4 chart-5 text chart-muted-1)))
(define pipeline-draw-tape-stack '((0 . chart-share)))
(define pipeline-tape-lane-tips
  '("Who drew the record: the legend under the Tape says whose each color is."
    "The record's kind: text for a glyph, faint for a box, gray for a shadow, \
     a color for a line or a polygon."))

;; A Tape holding n records, its rows a power of two.
(define (pipeline-tape-new n)
  (ui-stream-new (let loop ([rows 2048]) (if (< rows n) (loop (* 2 rows)) rows))
                 1 pipeline-draw-tape-lanes))

;; The Tape's rows of list l, a vector a record of those kept: (reach who
;; kind), who and kind each its lane's color, from 1, or 0.
(define (pipeline-tape-rows v l kept)
  (let* ([n (inspect-list-count l)]
         [who (make-vector n 0)]
         [colors (length pipeline-draw-tape-who)]
         [kinds (length pipeline-tape-kinds)]
         [spans (inspect-list-labels l)])
    (for-each (lambda (span node)
                (let ([c (+ 1 (modulo (pipeline-color-index v node) colors))])
                  (do ([k (cadr span) (+ k 1)])
                      ((>= k (min n (+ (cadr span) (caddr span)))))
                    (vector-set! who k c))))
              spans (pipeline-span-nodes spans))
    (let ([rows (make-vector (vector-length kept))])
      (do ([j 0 (+ j 1)]) ((= j (vector-length kept)) rows)
        (let* ([i (vector-ref kept j)]
               [r (inspect-reach l i)]
               [area (max 1 (* (- (caddr r) (car r)) (- (cadddr r) (cadr r))))]
               [kind (memq (inspect-kind l i) pipeline-tape-kinds)])
          (vector-set! rows j
                       (vector (exact (round (* 100 (log area 2))))
                               (vector-ref who i)
                               (if kind (+ 1 (- kinds (length kind))) 0))))))))

;; The Tape holds the records kept of the list on view: sent again when
;; they're others.
(define (pipeline-tape-send! v)
  (let ([kept (pipeline-kept v)])
    (unless (eq? kept (pipeline-view-tape-of v))
      (let ([n (vector-length kept)])
        (when (> n (ui-stream-rows (pipeline-view-tape v)))
          (ui-stream-release! (pipeline-view-tape v))
          (pipeline-view-tape-set! v (pipeline-tape-new n)))
        (let ([tape (pipeline-view-tape v)])
          (ui-stream-restart! tape)
          (when (> n 0)
            (let ([rows (pipeline-tape-rows v (pipeline-view-shown v)
                                            kept)])
              (ui-stream-send! tape 0 (- n 1)
                               (lambda (seq j)
                                 (vector-ref (vector-ref rows seq) j))))))
        (pipeline-view-tape-of-set! v kept)))))

(define (pipeline-tape-tip l i)
  (let ([label (inspect-label-at l i)])
    (format "record ~a, a ~a: ~a, ~a~a" i (inspect-kind l i)
            (inspect-what l i)
            (inspect-paint-text (inspect-record-paint l i))
            (if label (format "\ndrawn by ~a" label) ""))))

;; The marks on the Tape, where its records are: what's selected, and those at
;; the pixel traced, but those left out.
(define (pipeline-tape-marked v)
  (let* ([n (inspect-list-count (pipeline-view-shown v))]
         [kept (pipeline-kept v)]
         [selected (pipeline-view-selected v)]
         [first (and selected (pipeline-node-first v selected))]
         [traced (pipeline-view-traced v)])
    (fold-right
     (lambda (i acc)
       (let ([at (and (< i n) (pipeline-kept-at kept i))])
         (if at (cons at acc) acc)))
     '()
     (append
      (if (and first (< first n))
          (map (lambda (k) (+ first k))
               (iota (min (pipeline-node-count v selected) (- n first))))
          '())
      (if traced
          (map (lambda (node) (pipeline-node-first v node)) (caddr traced))
          '())))))

;; The small screen draws as far as k records, the last of them selected.
(define (pipeline-draw-upto! v k)
  (let* ([l (pipeline-view-shown v)] [n (inspect-list-count l)]
         [k (max 0 (min k n))])
    (pipeline-view-upto-set! v (and (< k n) k))
    (when (> k 0)
      (pipeline-view-selected-set! v (car (inspect-rows l (- k 1) 1))))
    (pipeline-preview! v)))

;; A press on the Tape, or its stepper: the frame stays, drawn as far as there.
(define (pipeline-tape-go! v k)
  (pipeline-hold! v)
  (pipeline-view-playing-set! v #f)
  (pipeline-draw-upto! v k))

;; Play goes through the records kept, from where the drawing stops: how far
;; it has is a place on the Tape.
(define (pipeline-play-toggle! v)
  (if (pipeline-view-playing v)
      (pipeline-view-playing-set! v #f)
      (let ([n (vector-length (pipeline-kept v))]
            [at (pipeline-tape-upto v)])
        (pipeline-hold! v)
        (pipeline-view-playing-set! v (if (< at n) at 0))
        (pipeline-draw-upto! v (pipeline-kept-upto
                                v (pipeline-view-playing v))))))

;; A tick of Play: on, by the share of the frame a tick of play-secs is.
(define (pipeline-play-tick! v)
  (let* ([n (vector-length (pipeline-kept v))]
         [at (+ (pipeline-view-playing v)
                (/ (* n (pacer-period))
                   (* (pipeline-view-play-secs v) 1000000000)))])
    (if (>= at n)
        (begin (pipeline-view-playing-set! v #f)
               (pipeline-draw-upto! v (pipeline-kept-upto v n)))
        (begin (pipeline-view-playing-set! v at)
               (pipeline-draw-upto! v (pipeline-kept-upto
                                       v (exact (floor at))))))))

;; Where the drawing stops: a line after the last record drawn.
(define (pipeline-draw-tape-at areas count upto)
  (let-values ([(bx bw) (ui-bar-chart-bar areas count (max 0 (- upto 1)))])
    (let ([plot (cdr (assq 'plot areas))])
      (fill-box (- (if (> upto 0) (+ bx bw) bx) 1) (cadr plot) 2 (cadddr plot)
                'accent))))

;; A drawer's color, kept while the Pipeline is open: the next free one the
;; first time it's seen, not its place, which moves when a window is raised.
(define (pipeline-color-index v node)
  (let ([colors (pipeline-view-colors v)])
    (or (hashtable-ref colors node #f)
        (let ([i (hashtable-size colors)])
          (hashtable-set! colors node i)
          i))))

;; Whose each color is, but the spans left out, which keep their colors.
(define (pipeline-tape-keys v)
  (let ([spans (pipeline-view-groups v)] [off (pipeline-view-off v)])
    (fold-right (lambda (span node acc)
                  (if (member node off)
                      acc
                      (cons (cons (pipeline-draw-who-color
                                   (pipeline-color-index v node))
                                  (pipeline-node-name span))
                            acc)))
                '() spans (pipeline-span-nodes spans))))

(define (pipeline-tape-height v w)
  (let-values ([(kw kh) (ui-legend-size (pipeline-tape-keys v))])
    (+ (ui-control-height) 4 (ui-stream-room pipeline-draw-tape-lanes) 40 4
       kh)))

;; Its heading and what plays it, the Tape, its legend.
(define (pipeline-tape-pane v x y w h)
  (let*-values
      ([(ui) (pipeline-view-ui v)]
       [(l) (pipeline-view-shown v)]
       [(kept) (pipeline-kept v)]
       [(n) (vector-length kept)]
       [(upto) (pipeline-view-upto v)]
       [(ch) (ui-control-height)]
       [(keys) (pipeline-tape-keys v)]
       [(kw kh) (ui-legend-size keys)]
       [(gw gh) (ui-label-size '(group) "Tape" w)]
       [(sy) (+ y ch 4)]
       [(sh) (- h ch 4 4 kh)]
       [(label!) (lambda (lx text)
                   (let ([tw (+ 8 (text-width text 'ui))])
                     (ui-draw-label lx y tw ch '(dim) text)
                     (+ lx tw)))])
    (pipeline-tape-send! v)
    (ui-draw-label x y gw ch '(group) "Tape")
    (let* ([px (+ x gw 16)]
           [pw (max 64 (+ 24 (text-width "Pause" 'ui)))]
           [lx (label! (+ px pw 12) "Drawn")]
           [sw (ui-stepper ui '(pipeline drawn) lx y (pipeline-tape-upto v)
                           0 n
                           (lambda (k)
                             (pipeline-tape-go! v (pipeline-kept-upto v k)))
                           'tip "How many of the frame's records the small \
                                 screen draws, in their order: an arrow steps \
                                 one record")]
           [lx (label! (+ lx sw 8) (format "of ~a records, played in" n))]
           [sw (ui-stepper ui '(pipeline play-secs) lx y
                           (pipeline-view-play-secs v) 1 60
                           (lambda (s) (pipeline-view-play-secs-set! v s))
                           'tip "How long Play takes over the whole frame")]
           [lx (label! (+ lx sw 8) "s")])
      (ui-button ui '(pipeline play) px y pw ch
                 (if (pipeline-view-playing v) "Pause" "Play")
                 (lambda () (pipeline-play-toggle! v))
                 'tip "Draw the frame on the small screen record by record, \
                       holding it")
      (pipeline-tape-caption v ui lx y (- (+ x w) lx) ch))
    (ui-stream ui 'pipeline-tape (pipeline-view-tape v) x sy w sh
               (and (> n 0) (- n 1)) 0 pipeline-tape-top pipeline-tape-rules
               pipeline-draw-tape-stack 1
               'fit #t
               'doc '((L . "Draw as far as this record"))
               'strip-tips pipeline-tape-lane-tips
               'tip (lambda (i)
                      (and (< i n) (pipeline-tape-tip l (vector-ref kept i))))
               'on-pick (lambda (i)
                          (pipeline-tape-go! v (pipeline-kept-upto v (+ i 1))))
               'marked (pipeline-tape-marked v)
               'over (lambda (areas count)
                       (when upto
                         (pipeline-draw-tape-at areas count
                                                (pipeline-tape-upto v)))))
    (ui-draw-legend x (+ sy sh 4) w kh '() keys)))

;;; ---- left out

;; A span whose checkbox is off is left out of the small screen and the Tape.
;; Its records in spans: ((first . count) ...), in order.
(define (pipeline-left-out off spans)
  (fold-right (lambda (span node acc)
                (if (member node off)
                    (cons (cons (cadr span) (caddr span)) acc)
                    acc))
              '() spans (pipeline-span-nodes spans)))

;; For the small screen, or #f when none is, so that a live frame's labels
;; aren't read for nothing.
(define (pipeline-left-out-of v)
  (let ([off (pipeline-view-off v)])
    (and (pair? off) (lambda (spans) (pipeline-left-out off spans)))))

(define (pipeline-show-span! v node on?)
  (pipeline-view-off-set! v (if on?
                                (remove node (pipeline-view-off v))
                                (cons node (pipeline-view-off v))))
  (pipeline-view-kept-of-set! v #f)
  (pipeline-preview! v))

(define (pipeline-node-off? v node)
  (let ([off (pipeline-view-off v)])
    (and (pair? off)
         (if (pair? node)
             (and (member node off) #t)
             (let ([i (vector-ref node 0)])
               (exists (lambda (r) (< -1 (- i (car r)) (cdr r)))
                       (pipeline-left-out off (pipeline-view-groups v))))))))

;; The records drawn of the list on view, but those left out: a vector, in
;; order, what the Tape and Play go through.
(define (pipeline-kept v)
  (let ([l (pipeline-view-shown v)])
    (unless (eq? l (pipeline-view-kept-of v))
      (let* ([n (inspect-list-count l)]
             [out (pipeline-left-out (pipeline-view-off v)
                                     (inspect-list-labels l))]
             [kept (make-vector (- n (apply + (map cdr out))))])
        (let loop ([i 0] [j 0] [out out])
          (cond [(= i n)]
                [(and (pair? out) (= i (caar out)))
                 (loop (+ i (cdar out)) j (cdr out))]
                [else (vector-set! kept j i) (loop (+ i 1) (+ j 1) out)]))
        (pipeline-view-kept-set! v kept)
        (pipeline-view-kept-of-set! v l)))
    (pipeline-view-kept v)))

;; How many of kept come before record i, kept being in order.
(define (pipeline-kept-below kept i)
  (let loop ([lo 0] [hi (vector-length kept)])
    (if (< lo hi)
        (let ([mid (quotient (+ lo hi) 2)])
          (if (< (vector-ref kept mid) i) (loop (+ mid 1) hi) (loop lo mid)))
        lo)))

;; Where record i is on the Tape, or #f when it's left out.
(define (pipeline-kept-at kept i)
  (let ([at (pipeline-kept-below kept i)])
    (and (< at (vector-length kept)) (= (vector-ref kept at) i) at)))

;; As far as k of the Tape's records, as far as which of the list's: all of
;; them at its end.
(define (pipeline-kept-upto v k)
  (let ([kept (pipeline-kept v)])
    (cond [(<= k 0) 0]
          [(>= k (vector-length kept))
           (inspect-list-count (pipeline-view-shown v))]
          [else (+ 1 (vector-ref kept (- k 1)))])))

;; How far the drawing goes on the Tape.
(define (pipeline-tape-upto v)
  (let ([kept (pipeline-kept v)] [upto (pipeline-view-upto v)])
    (if upto (pipeline-kept-below kept upto) (vector-length kept))))

;; The records drawn at a device pixel, the one on top first.
(define (pipeline-records-at v x y)
  (let ([kept (pipeline-kept v)])
    (filter (lambda (i) (pipeline-kept-at kept i))
            (inspect-records-at (pipeline-view-shown v) x y))))

;;; ---- what the tree holds

;; A node is a label's span or a row of it (a vector). A span's node is its
;; label and which of that label's spans it is, (label k), not where it is:
;; records before it and in it come and go (a caret blinks, the clock ticks),
;; and a span opened or selected stays so. Its records are looked up in the
;; list on view.
(define (pipeline-span-nodes spans)
  (let loop ([spans spans] [seen '()] [acc '()])
    (if (null? spans)
        (reverse acc)
        (let ([label (caar spans)])
          (loop (cdr spans) (cons label seen)
                (cons (list label (length (filter (lambda (l)
                                                    (equal? l label))
                                                  seen)))
                      acc))))))

;; The span of node (label k) among spans, (label first count), or #f when
;; it's gone.
(define (pipeline-span-in spans node)
  (let loop ([spans spans] [k (cadr node)])
    (cond [(null? spans) #f]
          [(not (equal? (caar spans) (car node))) (loop (cdr spans) k)]
          [(zero? k) (car spans)]
          [else (loop (cdr spans) (- k 1))])))

(define (pipeline-node-span v node)
  (pipeline-span-in (pipeline-view-groups v) node))

;; The node of the span that holds record i of the list on view, or #f.
(define (pipeline-span-node-at v i)
  (let loop ([spans (pipeline-view-groups v)]
             [nodes (pipeline-span-nodes (pipeline-view-groups v))])
    (cond [(null? spans) #f]
          [(< -1 (- i (cadar spans)) (caddar spans)) (car nodes)]
          [else (loop (cdr spans) (cdr nodes))])))

;; Who drew what's selected: its span's node, a record's being its span's.
(define (pipeline-selected-span v)
  (let ([selected (pipeline-view-selected v)])
    (cond [(not selected) #f]
          [(pair? selected) selected]
          [else (pipeline-span-node-at v (vector-ref selected 0))])))

(define (pipeline-children v node)
  (let ([span (and (pair? node) (pipeline-node-span v node))])
    (if span
        (inspect-rows (pipeline-view-shown v) (cadr span) (caddr span))
        '())))

;; Where a node's records start and how many, or #f for a span that's gone.
(define (pipeline-node-first v node)
  (if (pair? node)
      (let ([span (pipeline-node-span v node)]) (and span (cadr span)))
      (vector-ref node 0)))
(define (pipeline-node-count v node)
  (if (pair? node)
      (let ([span (pipeline-node-span v node)]) (and span (caddr span)))
      (vector-ref node 1)))

(define (pipeline-node-name node)
  (cond [(pair? node)
         (let ([label (car node)])
           (if (string? label) label (format "~a" label)))]
        [else (format "~a" (vector-ref node 2))]))

;; What a node is: a record's decoding; a drawer's lists, each its part and
;; how many records it holds; or the screen's, for a drawer drawn on it.
(define (pipeline-node-what v node)
  (if (pair? node)
      (let ([span (pipeline-node-span v node)])
        (let ([lists (and span
                          (inspect-span-lists (pipeline-view-shown v)
                                              (cadr span) (caddr span)))])
          (cond [(not span) ""]
                [(null? lists) "the screen's list"]
                [else (pipeline-lists-text lists)])))
      (vector-ref node 3)))

(define (pipeline-lists-text lists)
  (fold-left (lambda (text lst)
               (format "~a~a~a ~a records" text (if (equal? text "") "" ", ")
                       (inspect-list-part lst)
                       (cdr (assq 'records (inspect-list-facts lst)))))
             "" lists))

;; Whether lst, of the frame on view, wasn't in the frame before: a list
;; unchanged is the same copy in both.
(define (pipeline-list-changed? v lst)
  (let* ([l (pipeline-view-shown v)]
         [before (inspect-history-ref (pipeline-view-history v)
                                      (- (inspect-list-frame l) 1))])
    (and before (not (memq lst (inspect-list-lists before))))))

;; How long ago, on now-ns's clock, ns was.
(define (pipeline-ago ns)
  (let ([d (- (now-ns) ns)])
    (if (< d 1000000000)
        (format "~a ms ago" (quotient d 1000000))
        (format "~,1f s ago" (/ d 1e9)))))

;; The records at a device pixel, as nodes.
(define (pipeline-trace! v x y)
  (let* ([l (pipeline-view-shown v)]
         [rows (map (lambda (i) (car (inspect-rows l i 1)))
                    (pipeline-records-at v x y))])
    (pipeline-view-traced-set! v (list x y rows))
    (unless (null? rows) (pipeline-select! v (car rows)))))

;;; ---- what's selected: a drawer or a record, shown and named everywhere

;; Selects node, a drawer's or a record's, or nothing (#f), the small screen
;; and both windows drawn again for it.
(define (pipeline-select! v node)
  (pipeline-view-selected-set! v node)
  (pipeline-preview! v)
  (for-each (lambda (win) (when win (invalidate! win)))
            (list (find-window 'pipeline) (pipeline-view-popped v))))

;; Where a selected record is: its drawer's node and how far into its span,
;; so that it stays with its drawer as records before it come and go, or the
;; frame changes. #f for none, or a drawer selected.
(define (pipeline-selected-place v)
  (let ([selected (pipeline-view-selected v)])
    (and (vector? selected)
         (let ([node (pipeline-span-node-at v (vector-ref selected 0))])
           (and node
                (cons node (- (vector-ref selected 0)
                              (cadr (pipeline-node-span v node)))))))))

;; The record at place in the list on view; its drawer when its span is
;; shorter now; #f when the drawer's gone.
(define (pipeline-place-row v place)
  (let ([span (pipeline-node-span v (car place))])
    (cond [(not span) #f]
          [(< (cdr place) (caddr span))
           (car (inspect-rows (pipeline-view-shown v)
                              (+ (cadr span) (cdr place)) 1))]
          [else (car place)])))

;; What the tree shows selected: a record's row whole, the run of glyphs
;; it's in.
(define (pipeline-tree-selected v)
  (let ([selected (pipeline-view-selected v)])
    (if (vector? selected)
        (let* ([i (vector-ref selected 0)]
               [node (pipeline-span-node-at v i)]
               [span (and node (pipeline-node-span v node))])
          (or (and span
                   (find (lambda (row)
                           (< -1 (- i (vector-ref row 0)) (vector-ref row 1)))
                         (inspect-rows (pipeline-view-shown v) (cadr span)
                                       (caddr span))))
              selected))
        selected)))

;; What's selected, in words, or #f.
(define (pipeline-selected-text v)
  (let ([selected (pipeline-view-selected v)])
    (cond
      [(not selected) #f]
      [(pair? selected)
       (let ([span (pipeline-node-span v selected)])
         (if span
             (format "~a, records ~a–~a" (pipeline-node-name selected)
                     (cadr span) (+ (cadr span) (caddr span) -1))
             (format "~a, not in this frame" (pipeline-node-name selected))))]
      [else
       (let* ([i (vector-ref selected 0)] [n (vector-ref selected 1)]
              [kind (vector-ref selected 2)]
              [who (pipeline-span-node-at v i)])
         (format "~a, ~a~a"
                 (if (> n 1)
                     (format "records ~a–~a" i (+ i n -1))
                     (format "record ~a" i))
                 (if (eq? kind 'text)
                     (format "text “~a”" (vector-ref selected 3))
                     (format "a ~a" kind))
                 (if who (format " by ~a" (pipeline-node-name who)) "")))])))

;; The Tape's heading, at its right: what's selected and a button that
;; clears it, or, with nothing selected, what the Tape is.
(define (pipeline-tape-caption v ui x y w h)
  (let ([text (pipeline-selected-text v)])
    (if text
        (let* ([bw (+ 24 (text-width "Clear" 'ui))] [bx (- (+ x w) bw)])
          (ui-draw-label x y (max 0 (- bx 8 x)) h '(right)
                         (string-append "Selected: " text))
          (ui-button ui '(pipeline unselect) bx y bw h "Clear"
                     (lambda () (pipeline-select! v #f))
                     'tip "Select nothing (Esc)"))
        (ui-draw-label x y (max 0 w) h '(dim right)
                       "a mark a record, in draw order"))))

;; The tree opens the drawer of a record selected, and scrolls it into view,
;; and closes the one it opened for the record before; one opened by hand
;; stays open.
(define (pipeline-tree-open! ui node)
  (let ([id '(pipeline tree)] [was (ui-memo ui '(pipeline opened) #f)])
    (unless (equal? was node)
      (let ([states (ui-tree-states ui id)])
        (when (and was (eq? (hashtable-ref states was 'unset) #t))
          (ui-tree-expand! ui id was #f))
        (if (eq? (hashtable-ref states node 'unset) #t)
            (ui-memo! ui '(pipeline opened) #f)
            (begin (ui-tree-expand! ui id node #t)
                   (ui-memo! ui '(pipeline opened) node)))))))

;; Esc, in either window, selects nothing.
;; Esc: the selection cleared, or with none, the flow going on again.
(define (pipeline-key v win key mods)
  (and (eq? key 'escape) (null? mods)
       (cond [(pipeline-view-selected v) (pipeline-select! v #f) #t]
             [(pipeline-view-held? v) (pipeline-resume! v) #t]
             [else #f])))

;;; ---- who: what each drew cost

;; The profiler's name for who drew a span: a surface by its name, a window by
;; its id, found by its title among the windows drawn, the k-th of that title;
;; #f for a window gone since.
(define (pipeline-span-subject node)
  (let ([label (car node)])
    (if (symbol? label)
        label
        (let ([same (filter (lambda (w)
                              (and (visible? w)
                                   (equal? (window-title w) label)))
                            (reverse (windows)))])
          (and (< (cadr node) (length same))
               (profile-subject-of (list-ref same (cadr node))))))))

;; What main took to draw who subject is, a surface's draw or a window's frame
;; and its app's draw: ms a frame, over the last 30 ticks to tick newest that
;; drew it, of those the profiler keeps; #f when none did. A frame, not a
;; tick, so that a pause, held or idle, doesn't read as nothing.
(define (pipeline-drawing-ms subject newest)
  (let loop ([seq newest] [n 0] [ms 0.0])
    (if (or (fx= n 30) (not (profile-tick-kept? seq)))
        (and (fx> n 0) (/ ms n))
        (let ([t (+ (profile-tick-node-ms seq (list subject #f 'render))
                    (if (pair? subject)
                        (profile-tick-node-ms seq (list subject 'draw 'render))
                        0.0))])
          (if (> t 0)
              (loop (fx- seq 1) (fx+ n 1) (+ ms t))
              (loop (fx- seq 1) n ms))))))

;; What each span of the list on view cost, in draw order, a row each:
;; #(node i ms records pixels runs changed redrawn same marks), i its
;; color's index, ms what main took to draw it a frame, up to the frame's
;; tick, or #f, changed how many of its records differ from the frame
;; before's, #f when that one isn't kept; redrawn, same and marks as
;; pipeline-redraws says. Made again for each list.
(define (pipeline-who-rows v)
  (let ([l (pipeline-view-shown v)] [who (pipeline-view-who v)])
    (if (and who (eq? (car who) l))
        (cdr who)
        (let*-values
            ([(spans) (inspect-list-labels l)]
             [(before) (inspect-history-ref (pipeline-view-history v)
                                            (- (inspect-list-frame l) 1))]
             [(newest) (or (pipeline-view-tick v) (profile-newest-tick))]
             [(n copies) (inspect-history-copies (pipeline-view-history v)
                                                 (inspect-list-frame l))]
             [(row)
              (lambda (span node i)
                (let-values ([(pixels runs)
                              (inspect-span-cost l (cadr span) (caddr span))]
                             [(redrawn same marks)
                              (pipeline-redraws
                               n (map (lambda (lst)
                                        (hashtable-ref
                                         copies (inspect-list-original lst)
                                         #f))
                                      (inspect-span-lists l (cadr span)
                                                          (caddr span))))])
                  (let ([subject (pipeline-span-subject node)]
                        [b (and before
                                (pipeline-span-in
                                 (inspect-list-labels before) node))])
                    (vector node i
                            (and subject newest
                                 (pipeline-drawing-ms subject newest))
                            (caddr span) pixels runs
                            (and b (inspect-span-changed
                                    l (cadr span) (caddr span)
                                    before (cadr b) (caddr b)))
                            redrawn same marks))))]
             [(nodes) (pipeline-span-nodes spans)]
             [(rows) (map row spans nodes
                          (map (lambda (n) (pipeline-color-index v n))
                               nodes))])
          (pipeline-view-who-set! v (cons l rows))
          rows))))

;; How often a drawer was recorded again in the n frames kept, from its
;; lists' copies, a vector of n each, #f for a list not kept: (values
;; redrawn same marks), redrawn in how many frames one of its lists was
;; another copy than the frame before's, same in how many of those each such
;; copy held the very same records, and marks a frame's: 0, not redrawn, 1,
;; redrawn, 2, redrawn the same. Redrawn is #f with fewer than two frames or
;; no list of its own; same, while it wasn't redrawn.
(define (pipeline-redraws n copies)
  (let ([copies (filter values copies)] [marks (make-vector n 0)])
    (if (or (< n 2) (null? copies))
        (values #f #f marks)
        (let loop ([k 1] [redrawn 0] [same 0])
          (if (= k n)
              (values redrawn (and (> redrawn 0) same) marks)
              (let ([new (filter (lambda (v)
                                   (let ([a (vector-ref v (- k 1))]
                                         [b (vector-ref v k)])
                                     (and a b (not (eq? a b)))))
                                 copies)])
                (cond
                  [(null? new) (loop (+ k 1) redrawn same)]
                  [(for-all (lambda (v)
                              (eq? (inspect-list-basis (vector-ref v k))
                                   (inspect-list-basis
                                    (vector-ref v (- k 1)))))
                            new)
                   (vector-set! marks k 2)
                   (loop (+ k 1) (+ redrawn 1) (+ same 1))]
                  [else
                   (vector-set! marks k 1)
                   (loop (+ k 1) (+ redrawn 1) same)])))))))

;; A count of pixels, short.
(define (pipeline-pixels-text n)
  (cond [(>= n 1000000) (format "~,1f M" (/ n 1000000.0))]
        [(>= n 10000) (format "~a K" (round (/ n 1000)))]
        [else (number->string n)]))

;; Where a row keeps a column's number.
(define (pipeline-who-field key)
  (case key
    [(ms) 2]
    [(records) 3]
    [(pixels) 4]
    [(runs) 5]
    [(changed) 6]
    [(redrawn) 7]
    [else 8]))

;; A row's cell's text, and its share of its column's most, for its bar.
(define (pipeline-who-cell row key most)
  (let* ([records (vector-ref row 3)]
         [k (pipeline-who-field key)]
         [n (vector-ref row k)]
         [share (and n (> (most k) 0) (/ n (most k)))])
    (case key
      [(ms) (values (if n (format "~,2f" n) "—") share)]
      [(redrawn same) (values (if n (number->string n) "—") #f)]
      [(pixels) (values (pipeline-pixels-text n) share)]
      [(changed)
       (if (and n (> records 0))
           (values (format "~a%" (round (/ (* 100 n) records)))
                   (/ n records))
           (values "—" #f))]
      [else (values (number->string n) share)])))

;; Who's rows sorted ((key . up|down), or #f: in draw order) by what their
;; cells say, changed by its share; a row whose cell has nothing to say
;; last, either way.
(define (pipeline-who-sorted rows sort)
  (define (value row)
    (let ([key (car sort)])
      (case key
        [(name) (pipeline-node-name (vector-ref row 0))]
        [(changed)
         (let ([n (vector-ref row 6)] [records (vector-ref row 3)])
           (and n (> records 0) (/ n records)))]
        [else (vector-ref row (pipeline-who-field key))])))
  (if (not sort)
      rows
      (let ([up? (eq? (cdr sort) 'up)])
        (list-sort (lambda (a b)
                     (let ([x (value a)] [y (value b)])
                       (cond [(not x) #f]
                             [(not y) #t]
                             [(string? x)
                              (if up? (string<? x y) (string>? x y))]
                             [else (if up? (< x y) (> x y))])))
                   rows))))

;; Who: a row a drawer, in draw order or as sorted, what it cost; its
;; checkbox leaves it out as the tree's does, and selecting it selects its
;; span everywhere.
(define (pipeline-who-pane v x y w h)
  (let* ([ui (pipeline-view-ui v)]
         [rows (pipeline-who-sorted (pipeline-who-rows v)
                                    (pipeline-view-who-sort v))]
         [most (lambda (k)
                 (fold-left (lambda (m r) (max m (or (vector-ref r k) 0)))
                            0 rows))]
         [span (pipeline-selected-span v)]
         [columns
          `((name "Who" ,(max 140 (- (ui-table-room w) 72 76 84 60 84 84 64
                                     32)))
            (ms "Main" 72 right
                "What main took to draw it, ms a frame over its last 30")
            (records "Records" 76 right)
            (pixels "Pixels" 84 right
                    "What its records may touch: the pixels the GPU shades, \
                     a pixel each time a record covers it")
            (runs "Runs" 60 right
                  "The runs that start among its records: a draw call each, \
                   and a new one where a record needs another shader")
            (changed "Changed" 84 right
                     "Its records that differ from the frame before")
            (redrawn "Redrawn" 84 right
                     "In how many of the frames kept, up to this one, it was \
                      recorded again: a mark each, the oldest left")
            (same "Same" 64 right
                  "How many of those recorded the very same records again: \
                   work for nothing"))]
         [cell (lambda (row key cx cy cw ch flags)
                 (if (eq? key 'name)
                     (pipeline-draw-who-name
                      cx cy cw ch flags (vector-ref row 1)
                      (pipeline-node-name (vector-ref row 0)))
                     (let-values ([(text share) (pipeline-who-cell row key
                                                                   most)])
                       (case key
                         [(redrawn)
                          (pipeline-draw-marks cx cy cw ch (vector-ref row 9)
                                               1)]
                         [(same)
                          (pipeline-draw-marks cx cy cw ch (vector-ref row 9)
                                               2)]
                         [else
                          (when share
                            (pipeline-draw-share cx cy cw ch share))])
                       (ui-draw-cell cx cy cw ch flags text))))])
    (ui-table ui '(pipeline who) x y w h columns rows
              (find (lambda (r) (equal? (vector-ref r 0) span)) rows)
              (lambda (row) (pipeline-select! v (vector-ref row 0)))
              cell
              'checked (lambda (row)
                         (not (member (vector-ref row 0)
                                      (pipeline-view-off v))))
              'on-check (lambda (row)
                          (let ([node (vector-ref row 0)])
                            (pipeline-show-span!
                             v node
                             (and (member node (pipeline-view-off v)) #t))))
              'sort (pipeline-view-who-sort v)
              'on-sort (lambda (key)
                         (pipeline-view-who-sort-set!
                          v (pipeline-sort-next (pipeline-view-who-sort v)
                                                key))))))

;; The small screen showing list l another way than its picture, each record
;; solid in a color of what's asked: who drew it, the others dim while a
;; drawer's selected; its kind; or whether it changed since the frame
;; before. Heat adds a little of one color a record, so that a pixel is as
;; bright as how many records cover it.
(define (pipeline-painted v l)
  (let ([into (pipeline-view-painted v)] [n (inspect-list-count l)])
    (case (pipeline-view-look v)
      [(heat) (inspect-list-paint! into l (lambda (i) (pipeline-draw-heat-word))
                                   3)]
      [(kind)
       (let ([words (pipeline-draw-kind-words)])
         (inspect-list-paint!
          into l
          (lambda (i)
            (cdr (assq (inspect-kind l i) words)))
          0))]
      [(changed)
       (let ([marks (pipeline-changed-marks v l)])
         (let-values ([(new same) (pipeline-draw-changed-words)])
           (inspect-list-paint! into l
                                (lambda (i) (if (vector-ref marks i) new same))
                                0)))]
      [else
       (let-values ([(words other)
                     (pipeline-draw-who-words v (inspect-list-labels l)
                                              (pipeline-selected-span v))])
         (let ([by (make-vector n other)])
           (for-each (lambda (span w)
                       (do ([i (cadr span) (+ i 1)])
                           ((>= i (min n (+ (cadr span) (caddr span)))))
                         (vector-set! by i w)))
                     (inspect-list-labels l) words)
           (inspect-list-paint! into l (lambda (i) (vector-ref by i)) 0)))])))

;; Which records of l differ from the frame before's, a vector of booleans:
;; each compared with the record at its place in its drawer's span then, a
;; record past that span's, or of a drawer new since, changed; all of them
;; when the frame before isn't kept.
(define (pipeline-changed-marks v l)
  (let* ([n (inspect-list-count l)]
         [before (inspect-history-ref (pipeline-view-history v)
                                      (- (inspect-list-frame l) 1))]
         [marks (make-vector n (not before))])
    (when before
      (let ([spans (inspect-list-labels l)])
        (for-each
         (lambda (span node)
           (let ([b (pipeline-span-in (inspect-list-labels before) node)])
             (do ([k 0 (+ k 1)]) ((>= k (caddr span)))
               (let ([i (+ (cadr span) k)])
                 (when (< i n)
                   (vector-set! marks i
                                (or (not b) (>= k (caddr b))
                                    (not (inspect-record-same?
                                          l i before (+ (cadr b) k))))))))))
         spans (pipeline-span-nodes spans))))
    marks))

;;; ---- course: a tick's stages, in order, as wide as their time

;; The tick to lay out: the one picked on the River, or the newest kept that
;; drew a frame; #f when none is kept.
(define (pipeline-course-tick v)
  (or (pipeline-view-tick v)
      (let ([newest (profile-newest-tick)])
        (and newest
             (let loop ([seq newest] [left 30])
               (cond [(or (zero? left) (not (profile-tick-kept? seq))) newest]
                     [(> (pipeline-phase-ms (profile-tick-uses seq) 'render)
                         0.0)
                      seq]
                     [else (loop (- seq 1) (- left 1))]))))))

(define (pipeline-phase-ms uses phase)
  (fold-left (lambda (ms u)
               (if (eq? (profile-use-phase u) phase)
                   (+ ms (profile-use-ms u))
                   ms))
             0.0 uses))

;; What subject took to draw in uses, a tick's, ms.
(define (pipeline-render-ms uses subject)
  (fold-left (lambda (ms u)
               (if (and (eq? (profile-use-phase u) 'render)
                        (equal? (profile-use-subject u) subject))
                   (+ ms (profile-use-ms u))
                   ms))
             0.0 uses))

;; What a tick spent, in order: (name ms kind detail) each, kind phase (a
;; phase of monitor-phases), drawer (detail its span's node: render, its
;; draw), gpu (the rest of render: the list to the GPU and its wait) or idle
;; (what's left of the period).
(define (pipeline-course-items v seq)
  (let* ([uses (profile-tick-uses seq)]
         [spans (inspect-list-labels (pipeline-view-shown v))]
         [period (/ (pacer-period) 1e6)]
         [stages
          (apply append
                 (map (lambda (p)
                        (let ([ms (pipeline-phase-ms uses (car p))])
                          (cond
                            [(not (eq? (car p) 'render))
                             (if (> ms 0.0)
                                 (list (list (cddr p) ms 'phase (car p)))
                                 '())]
                            [else
                             (let* ([drawers
                                     (map (lambda (node)
                                            (list (pipeline-node-name node)
                                                  (pipeline-render-ms
                                                   uses
                                                   (pipeline-span-subject
                                                    node))
                                                  'drawer node))
                                          (pipeline-span-nodes spans))]
                                    [drawn (fold-left (lambda (m d)
                                                        (+ m (cadr d)))
                                                      0.0 drawers)])
                               (append (list (list (cddr p) ms 'total
                                                   'render))
                                       drawers
                                       (list (list "to the GPU"
                                                   (max 0.0 (- ms drawn))
                                                   'gpu 'render))))])))
                      (remp (lambda (p) (memq (car p)
                                              '(input-wait vsync-wait)))
                            monitor-phases)))]
         [busy (fold-left (lambda (m it)
                            (if (eq? (caddr it) 'total) m (+ m (cadr it))))
                          0.0 stages)])
    (append stages
            (list (list "till the next tick" (max 0.0 (- period busy))
                        'idle #f)))))

;; Course's items sorted ((key . up|down), or #f: as they come): the
;; stages among themselves, and render's parts, under it, among
;; themselves.
(define (pipeline-course-sorted items sort)
  (define (part? it) (memq (caddr it) '(drawer gpu)))
  (define (before? a b)
    (let ([up? (eq? (cdr sort) 'up)])
      (if (eq? (car sort) 'name)
          (if up? (string<? (car a) (car b)) (string>? (car a) (car b)))
          (if up? (< (cadr a) (cadr b)) (> (cadr a) (cadr b))))))
  (if (not sort)
      items
      ;; a stage and the parts after it, together
      (let* ([groups (reverse
                      (fold-left (lambda (gs it)
                                   (if (and (part? it) (pair? gs))
                                       (cons (append (car gs) (list it))
                                             (cdr gs))
                                       (cons (list it) gs)))
                                 '() items))])
        (apply append
               (map (lambda (g) (cons (car g) (list-sort before? (cdr g))))
                    (list-sort (lambda (a b) (before? (car a) (car b)))
                               groups))))))

;; The tick laid out and its stages, made again for each list on view: (seq
;; items), or #f.
(define (pipeline-course v)
  (let ([l (pipeline-view-shown v)] [c (pipeline-view-course v)])
    (if (and c (eq? (car c) l))
        (cdr c)
        (let* ([seq (pipeline-course-tick v)]
               [r (and seq (list seq (pipeline-course-items v seq)))])
          (pipeline-view-course-set! v (cons l r))
          r))))

;; Course: the tick as a bar, each stage as wide as its time of the period,
;; then the stages as a table.
(define (pipeline-course-pane v x y w h)
  (let ([c (pipeline-course v)] [ch (ui-control-height)]
        [ui (pipeline-view-ui v)])
    (if (not c)
        (ui-draw-label x y w ch '(dim) "No tick is kept yet.")
        (let* ([items (cadr c)]
               [period (/ (pacer-period) 1e6)]
               [whole (max period
                           (fold-left (lambda (m it)
                                        (if (eq? (caddr it) 'total)
                                            m
                                            (+ m (cadr it))))
                                      0.0 items))]
               [bar-y (+ y ch 6)]
               [bar-h 34]
               [rows (map (lambda (it) (list->vector it))
                          (pipeline-course-sorted items
                                                  (pipeline-view-course-sort
                                                   v)))])
          (ui-draw-label x y w ch '(dim)
                         (format "Tick ~a, in order, of a period of ~,2f ms"
                                 (car c) period))
          (pipeline-draw-course-bar v x bar-y w bar-h items whole)
          (ui-table ui '(pipeline course) x (+ bar-y bar-h 10) w
                    (max 0 (- h ch 6 bar-h 10))
                    `((name "Stage" ,(max 160 (- (ui-table-room w) 96 96)))
                      (ms "ms" 96 right)
                      (share "Of the period" 96 right))
                    rows #f (lambda (row) #f)
                    (lambda (row key cx cy cw rh flags)
                      (case key
                        [(name)
                         (ui-draw-cell cx cy cw rh flags
                                       (if (eq? (vector-ref row 2) 'drawer)
                                           (string-append
                                            "    " (vector-ref row 0))
                                           (vector-ref row 0)))]
                        [(ms)
                         (ui-draw-cell cx cy cw rh flags
                                       (format "~,2f" (vector-ref row 1)))]
                        [else
                         (pipeline-draw-share cx cy cw rh
                                              (/ (vector-ref row 1) whole))
                         (ui-draw-cell cx cy cw rh flags
                                       (format "~a%"
                                               (exact
                                                (round
                                                 (/ (* 100 (vector-ref row 1))
                                                    period)))))]))
                    'sort (pipeline-view-course-sort v)
                    'on-sort (lambda (key)
                               (pipeline-view-course-sort-set!
                                v (pipeline-sort-next
                                   (pipeline-view-course-sort v) key))))))))

;; A table's sort after a press on key's heading: a number the most first, a
;; name from A; again, the other way; a third time, in order.
(define (pipeline-sort-next s key)
  (let ([first (if (eq? key 'name) 'up 'down)])
    (cond [(not (and s (eq? (car s) key))) (cons key first)]
          [(eq? (cdr s) first) (cons key (if (eq? first 'up) 'down 'up))]
          [else #f])))

;;; ---- inside: a record decoded, and the shader it's drawn with

;; The record selected, its index in the list on view, or #f.
(define (pipeline-inside-record v)
  (let ([selected (pipeline-view-selected v)]
        [n (inspect-list-count (pipeline-view-shown v))])
    (and (vector? selected) (< (vector-ref selected 0) n)
         (vector-ref selected 0))))

;; A decoded value, in words.
(define (pipeline-value-text key value)
  (cond [(and (eq? key 'color) (integer? value)) (format "#~8,'0x" value)]
        [(flonum? value) (format "~,1f" value)]
        [(list? value)
         (apply string-append
                (map (lambda (x i)
                       (string-append (if (> i 0) " " "")
                                      (pipeline-value-text #f x)))
                     value (iota (length value))))]
        [(not value) "none"]
        [else (format "~a" value)]))

;; Record i's facts: what it is, its fields, its words, its run.
(define (pipeline-inside-facts v i)
  (let* ([l (pipeline-view-shown v)]
         [who (pipeline-span-node-at v i)]
         [run (inspect-record-run l i)]
         [runs (inspect-list-runs l)])
    (append
     (list (cons "Record"
                 (format "~a of ~a~a" i (inspect-list-count l)
                         (if who
                             (format ", by ~a" (pipeline-node-name who))
                             ""))))
     (map (lambda (field)
            (cons (format "~a" (car field))
                  (pipeline-value-text (car field) (cdr field))))
          (inspect-record l i))
     (list (cons "Words"
                 (apply string-append
                        (map (lambda (k)
                               (format (if (= k 0) "~8,'0x" " ~8,'0x")
                                       (fxand (inspect-word l i k)
                                              #xffffffff)))
                             (iota rec-row-words)))))
     (let-values ([(lst j) (inspect-record-list l i)])
       (list
        (cons "List"
              (if lst
                  (let ([f (inspect-list-facts lst)])
                    (format "~a's ~a, version ~a, its record ~a; recorded \
                             ~a in ~,2f ms"
                            (inspect-list-owner lst) (inspect-list-part lst)
                            (cdr (assq 'version f)) j
                            (pipeline-ago (cdr (assq 'recorded f)))
                            (/ (cdr (assq 'took f)) 1e6)))
                  (format "the screen's own, its record ~a" j)))))
     (if run
         (list (cons "Run"
                     (format "~a of ~a: records ~a–~a, ~a"
                             (+ 1 (list-index (lambda (r) (eq? r run)) runs))
                             (length runs) (caddr run)
                             (+ (caddr run) (cadddr run) -1)
                             (case (car run)
                               [(1 2) "inverting"]
                               [(3) "adding"]
                               [else "drawn over"]))))
         '()))))

;; Inside: the record selected, decoded, and its shader's source.
(define (pipeline-inside-pane v x y w h)
  (let ([i (pipeline-inside-record v)] [lh (font-line-height 'ui)]
        [ui (pipeline-view-ui v)])
    (if (not i)
        (ui-draw-label x y w 0 '(hint wrap)
                       "Select a record: a drawer's row opened in Lists, a \
                        mark on the Tape, or a press on the small screen. \
                        What its words say, and the shader it's drawn with, \
                        show here.")
        (let* ([facts (pipeline-inside-facts v i)]
               [run (inspect-record-run (pipeline-view-shown v) i)]
               [shader (and run (inspect-run-fragment run))]
               [sy (+ y (* (length facts) (+ lh 4)) 6)])
          (for-each (lambda (fact k)
                      (let ([ly (+ y (* k (+ lh 4)))])
                        (ui-draw-label x ly 90 lh '(dim) (car fact))
                        (ui-draw-label (+ x 94) ly (- w 94) lh '()
                                       (cdr fact))))
                    facts (iota (length facts)))
          (when shader
            (let ([lines (pipeline-inside-lines v shader)])
              (ui-draw-label x sy w lh '(dim)
                             (format "Shader ~a, ~a lines of its source"
                                     (shader-name shader) (length lines)))
              (pipeline-draw-source ui x (+ sy lh 6) w
                                    (max 0 (- (+ y h) sy lh 6))
                                    lines)))))))

;; A shader's lines, kept for the shader last shown: pretty-printing is dear.
(define (pipeline-inside-lines v shader)
  (let* ([ui (pipeline-view-ui v)] [had (ui-memo ui '(pipeline source) #f)])
    (if (and had (eq? (car had) shader))
        (cdr had)
        (let ([lines (inspect-shader-lines shader)])
          (ui-memo! ui '(pipeline source) (cons shader lines))
          lines))))

;;; ---- memory: what the GPU holds, and the atlas

;; Memory: the screen's facts, what's held for frames, as bars, and beside
;; them the atlas, the part of it in use.
(define (pipeline-memory-pane v x y w h)
  (let* ([lh (font-line-height 'ui)]
         ;; the device's facts: what it holds is the bars'
         [facts (list-head (pipeline-screen-facts v) 6)]
         [left-w (min 480 (quotient w 2))]
         [by (+ y (* (length facts) (+ lh 4)) 10)]
         [objects (append
                   (map (lambda (o) (cons (format "~a" (car o)) (cddr o)))
                        (inspect-gpu-objects))
                   (let ([image (pipeline-view-image v)])
                     (if image
                         (list (cons "small screen"
                                     (* 2 (inspect-preview-bytes image))))
                         '()))
                   (list (cons "frames kept, in RAM"
                               (inspect-history-bytes
                                (pipeline-view-history v)))))]
         [most (apply max 1 (map cdr objects))]
         [g (inspect-glyphs)]
         [ax (+ x left-w 16)]
         [aw (- w left-w 16)])
    (for-each (lambda (fact k)
                (let ([ly (+ y (* k (+ lh 4)))])
                  (ui-draw-label x ly 120 lh '(dim) (car fact))
                  (ui-draw-label (+ x 124) ly (- left-w 124) lh '()
                                 (cdr fact))))
              facts (iota (length facts)))
    (for-each (lambda (o k)
                (let ([ly (+ by (* k (+ lh 6)))])
                  (pipeline-draw-memory-bar (+ x 124) ly (- left-w 124) lh
                                            (/ (cdr o) most))
                  (ui-draw-label x ly 120 lh '(dim) (car o))
                  (ui-draw-label (+ x 128) ly (- left-w 132) lh '()
                                 (format "~a MB" (pipeline-mb (cdr o))))))
              objects (iota (length objects)))
    (ui-draw-label ax y aw lh '(dim)
                   (format "The atlas, ~a glyphs: drag to move"
                           (cdr (assq 'glyphs g))))
    (pipeline-atlas-view (pipeline-view-ui v) ax (+ y lh 6) aw
                         (max 0 (- h lh 6))
                         (* gpu-atlas-side (cdr (assq 'atlas-used g))))))

;; The atlas at x y w h, a pixel of it a device pixel, from where a drag
;; left it: used, the rows of it in use.
(define (pipeline-atlas-view ui x y w h used)
  (let* ([id '(pipeline atlas)]
         [grab (list id 'grab)]   ; (mx my ox oy)
         [s (draw-scale)]
         [most-x (max 0 (- gpu-atlas-side (* w s)))]
         [most-y (max 0 (- used (* h s)))]
         [at (ui-memo ui id '(0 . 0))]
         [ox (clamp (car at) 0 most-x)]
         [oy (clamp (cdr at) 0 most-y)])
    (ui-region! ui id x y w h
      'doc '((L . "Drag to move through the atlas"))
      'on (lambda (ev)
            (case (car ev)
              [(press)
               (and (eq? (list-ref ev 3) 'left)
                    (begin (ui-memo! ui grab (list (cadr ev) (caddr ev) ox oy))
                           #t))]
              [(drag)
               (let ([g (ui-memo ui grab #f)])
                 (and g
                      (begin
                        (ui-memo! ui id
                                  (cons (clamp (- (caddr g)
                                                  (* s (- (cadr ev) (car g))))
                                               0 most-x)
                                        (clamp (- (cadddr g)
                                                  (* s (- (caddr ev) (cadr g))))
                                               0 most-y)))
                        #t)))]
              [(release)
               (and (ui-memo ui grab #f)
                    (begin (ui-memo! ui grab #f) #t))]
              [else #f])))
    (pipeline-draw-atlas x y w h (/ ox s) (/ oy s) (/ used s) (/ s))))

;;; ---- drawing

;; A stage's card: its name and what it holds, lines of text; pressed, it
;; opens.
;; Its lines cut to fit, however narrow the window makes it.
(define (pipeline-draw-card x y w h selected? name lines)
  (fill-box x y w h (if selected? 'bg-3 'bg-1) 4)
  (when selected? (stroke-box x y w h 'accent 1 4))
  (let ([lh (font-line-height 'ui)] [tw (max 0 (- w 20))])
    (draw-text (+ x 10) (+ y 6) (text-fit name tw 'ui-bold) 'text 'ui-bold)
    (for-each (lambda (line i)
                (draw-text (+ x 10) (+ y 6 (* lh (+ i 1)))
                           (text-fit line tw 'ui) 'text-dim 'ui))
              lines (iota (length lines)))))

;; A record's paint in a cell: a solid one as a swatch of its color, alpha
;; and all, and its word; another by its kind.
(define (pipeline-draw-paint x y w h flags paint)
  (if (fixnum? paint)
      (let ([s 12] [sy (+ y (/ (- h 12) 2))])
        (fill-box (+ x 6) sy s s
                  (alpha (fxand paint #xffffff) (/ (fxsrl paint 24) 255.0)) 2)
        (stroke-box (+ x 6) sy s s (alpha 'text 0.35) 1 2)
        (ui-draw-cell (+ x s 12) y (max 0 (- w s 12)) h flags
                      (inspect-paint-text paint)))
      (ui-draw-cell x y w h flags (inspect-paint-text paint))))

;; A row's frames kept as marks across its cell, inside it as a share's bar
;; is, the oldest left: those marked at least least, run together where they
;; touch, a pixel wide at the least.
(define (pipeline-draw-marks x y w h marks least)
  (let ([n (vector-length marks)]
        [x (+ x pipeline-draw-inset)]
        [w (- w pipeline-draw-inset pipeline-draw-inset)])
    (let loop ([k 0] [from #f])
      (let ([on? (and (< k n) (>= (vector-ref marks k) least))])
        (cond
          [(and on? (not from)) (loop (+ k 1) k)]
          [(and from (not on?))
           (let ([x0 (+ x (* w (/ from n)))])
             (fill-box x0 (+ y 3) (max 1 (- (+ x (* w (/ k n))) x0)) (- h 6)
                       (alpha 'accent 0.22) 2))
           (when (< k n) (loop (+ k 1) #f))]
          [(< k n) (loop (+ k 1) from)])))))

;; Who drew span i, a color: the Tape's, so that a drawer's is the same
;; everywhere.
(define (pipeline-draw-who-color i)
  (list-ref pipeline-draw-tape-who (modulo i (length pipeline-draw-tape-who))))

;; A drawer's name in a cell, after a swatch of its color.
(define (pipeline-draw-who-name x y w h flags i name)
  (let ([s 10])
    (fill-box (+ x 6) (+ y (/ (- h s) 2)) s s (pipeline-draw-who-color i) 2)
    (ui-draw-cell (+ x s 8) y (max 0 (- w s 8)) h flags name)))

;; A number's share of its column's most, a bar behind it, inside the cell by
;; pipeline-draw-inset so that full ones side by side stay apart; none for a
;; share too small to tell from a line between columns.
(define (pipeline-draw-share x y w h share)
  (when (>= share 0.03)
    (let ([d pipeline-draw-inset])
      (fill-box (+ x d) (+ y 3) (* (- w d d) (min 1 share)) (- h 6)
                (alpha 'accent 0.22) 2))))

(define pipeline-draw-inset 3)

;; The words the small screen paints spans' records with, who drew them: dim
;; but the one selected, while one is. => (values words other), other for a
;; record under no label
(define (pipeline-draw-who-words v spans selected)
  (values (map (lambda (node)
                 (let ([c (pipeline-draw-who-color
                           (pipeline-color-index v node))])
                   ;; opaque, so that a drawer's layers don't add up
                   (color-word (if (and selected (not (equal? node selected)))
                                   (mix c 'bg-0 0.75)
                                   c))))
               (pipeline-span-nodes spans))
          (color-word 'text-faint)))

;; Kinds' words for the small screen, as the Tape's kind lane colors them.
(define (pipeline-draw-kind-words)
  (map (lambda (kind color) (cons kind (color-word color)))
       pipeline-tape-kinds (cdr (cadr pipeline-draw-tape-lanes))))

;; What a record adds where it covers, showing heat: a little of red, half as
;; much green and a quarter blue, so that a pixel goes dark red, orange,
;; yellow and white as more records cover it, red full at 16.
(define (pipeline-draw-heat-word) (color-word #x100804))

;; A record changed since the frame before, and one the same. => (values new
;; same)
(define (pipeline-draw-changed-words)
  (values (color-word 'chart-1) (color-word (mix 'text-faint 'bg-0 0.6))))

;; A tick's stages in a row, each as wide as its time of whole: a phase in
;; its River color, a drawer's draw in its color, the rest of render darker,
;; what's left of the period faint; a stage wide enough names itself.
(define (pipeline-draw-course-bar v x y w h items whole)
  (fill-box x y w h 'bg-1 3)
  (let loop ([items (remp (lambda (it) (eq? (caddr it) 'total)) items)]
             [at x])
    (unless (null? items)
      (let* ([it (car items)]
             [sw (* w (/ (cadr it) whole))]
             [color (case (caddr it)
                      [(phase) (cadr (assq (cadddr it) monitor-phases))]
                      [(drawer) (pipeline-draw-who-color
                                 (pipeline-color-index v (cadddr it)))]
                      [(gpu) (mix (cadr (assq 'render monitor-phases))
                                  'bg-0 0.45)]
                      [else (alpha 'text-faint 0.15)])])
        (fill-box at y (max 0 (- sw 1)) h color 2)
        (when (> sw (+ 12 (text-width (car it) 'ui-small)))
          (draw-text (+ at 5) (+ y (/ (- h (font-line-height 'ui-small)) 2))
                     (car it)
                     (if (eq? (caddr it) 'idle) 'text-dim 'bg-0)
                     'ui-small))
        (loop (cdr items) (+ at sw))))))

;; A shader's source, a line of the mono font each, scrolling.
(define (pipeline-draw-source ui x y w h lines)
  (let ([lh (font-line-height 'mono-small)])
    (fill-box x y w h 'bg-1 3)
    (ui-scroll ui '(pipeline source-view) x y w h
      (lambda (top)
        (for-each (lambda (line k)
                    (let ([ly (+ top 6 (* k lh))])
                      (when (and (> (+ ly lh) y) (< ly (+ y h)))
                        (draw-text (+ x 8) ly line 'text 'mono-small))))
                  lines (iota (length lines)))
        (+ top 12 (* lh (length lines)))))))

;; A share of the most held, a bar.
(define (pipeline-draw-memory-bar x y w h share)
  (fill-box x (+ y 2) (* w (max 0.004 (min 1 share))) (- h 4)
            (alpha 'accent 0.3) 2))

;; The atlas in w × h from (ox, oy), k of it a pixel; the rows in use,
;; used, as a texture viewer shows its one channel, in gray.
(define (pipeline-draw-atlas x y w h ox oy used k)
  (fill-box x y w h 'bg-1 3)
  (with-clip (x y w (max 0 (min h (- used oy))))
    (draw-image (inspect-atlas-image) (- x ox) (- y oy)
                (* k gpu-atlas-side) (* k gpu-atlas-side) 'gray))
  (stroke-box x y w h 'window-border 1 3))

;;; ---- the viewer: the screen small, zoomed, moved, magnified, popped out

(define pipeline-zoom-most 32)    ; device pixels a screen pixel, at most
(define pipeline-zoom-step 1.25)  ; a notch of the wheel
(define pipeline-loupe-size 128)
(define pipeline-loupe-zoom 8)    ; a screen pixel in the loupe, logical pixels

;; How many device pixels of a viewer w × h a pixel of the screen takes: all
;; of it, or as much more as asked.
(define (pipeline-viewer-fit w h)
  (let ([s (draw-scale)])
    (min (/ (* w s) *canvas-pw*) (/ (* h s) *canvas-ph*))))

(define (pipeline-viewer-zoom v w h)
  (let ([fit (pipeline-viewer-fit w h)])
    (max fit (or (pipeline-view-zoom v) fit))))

;; The screen's pixel at the viewer's middle, on the screen.
(define (pipeline-viewer-center v)
  (let ([c (and (pipeline-view-zoom v) (pipeline-view-center v))])
    (if c
        (cons (max 0 (min *canvas-pw* (car c)))
              (max 0 (min *canvas-ph* (cdr c))))
        (cons (/ *canvas-pw* 2) (/ *canvas-ph* 2)))))

;; The screen's pixel under (mx, my) of a viewer at x y w h.
(define (pipeline-viewer-pixel v x y w h mx my)
  (let ([k (/ (draw-scale) (pipeline-viewer-zoom v w h))]
        [c (pipeline-viewer-center v)])
    (cons (+ (car c) (* k (- mx (+ x (/ w 2)))))
          (+ (cdr c) (* k (- my (+ y (/ h 2))))))))

;; A notch of the wheel, or n: zoomed at (mx, my), the pixel there staying.
(define (pipeline-zoom-at! v x y w h mx my n)
  (let* ([fit (pipeline-viewer-fit w h)]
         [p (pipeline-viewer-pixel v x y w h mx my)]
         [z (max fit (min pipeline-zoom-most
                          (* (pipeline-viewer-zoom v w h)
                             (expt pipeline-zoom-step n))))]
         [k (/ (draw-scale) z)])
    (if (<= z (* fit 1.001))
        (begin (pipeline-view-zoom-set! v #f) (pipeline-view-center-set! v #f))
        (begin
          (pipeline-view-zoom-set! v z)
          (pipeline-view-center-set!
           v (cons (- (car p) (* k (- mx (+ x (/ w 2)))))
                   (- (cdr p) (* k (- my (+ y (/ h 2)))))))))))

;; What the loupe says under its pixels: where, and the top record there.
(define (pipeline-loupe-caption v px py)
  (let* ([l (pipeline-view-shown v)]
         [at (pipeline-records-at v px py)])
    (if (null? at)
        (format "~a, ~a" px py)
        (format "~a, ~a: ~a ~a" px py (inspect-kind l (car at)) (car at)))))

;; The viewer: the screen at its zoom, around its center, what's selected
;; outlined (box, screen pixels, or #f).
(define (pipeline-draw-viewer v image x y w h box)
  (let* ([z (pipeline-viewer-zoom v w h)]
         [k (/ z (draw-scale))]
         [c (pipeline-viewer-center v)]
         [at (lambda (p mid) (+ mid (* k p)))]
         [ox (- (+ x (/ w 2)) (* k (car c)))]
         [oy (- (+ y (/ h 2)) (* k (cdr c)))])
    (fill-box x y w h 'bg-0)
    (with-clip (x y w h)
      (when image
        (draw-image image ox oy (* k *canvas-pw*) (* k *canvas-ph*)))
      (when box
        (stroke-box (at (car box) ox) (at (cadr box) oy)
                    (max 3 (* k (- (caddr box) (car box))))
                    (max 3 (* k (- (cadddr box) (cadr box))))
                    'accent 1)))
    (stroke-box x y w h 'window-border)))

;; The loupe at lx, ly: the screen's pixels around (px, py), its own boxed.
(define (pipeline-draw-loupe image lx ly px py caption)
  (let* ([size pipeline-loupe-size] [m pipeline-loupe-zoom]
         [lh (font-line-height 'ui-small)] [mid (/ size 2)])
    (fill-box lx ly size (+ size lh 6) 'bg-2)
    (with-clip (lx ly size size)
      (draw-image image (- (+ lx mid) (* m (+ px 1/2)))
                  (- (+ ly mid) (* m (+ py 1/2)))
                  (* m *canvas-pw*) (* m *canvas-ph*)))
    (stroke-box (- (+ lx mid) (/ m 2)) (- (+ ly mid) (/ m 2)) m m 'accent 1)
    (stroke-box lx ly size (+ size lh 6) 'window-border)
    (draw-text (+ lx 4) (+ ly size 3) (text-fit caption (- size 8) 'ui-small)
               'text 'ui-small)))

;; In the viewer's place while it's popped out.
(define (pipeline-draw-popped-out x y w h)
  (fill-box x y w h 'bg-1)
  (stroke-box x y w h 'window-border))

;; The viewer at x y w h, in ui as id: the wheel zooms it at the pointer, a drag
;; moves it, a press lists the records at its pixel; with the loupe on, the
;; pixels at the pointer magnified beside it.
(define (pipeline-viewer v ui id x y w h)
  (let* ([l (pipeline-view-shown v)]
         [n (inspect-list-count l)]
         [selected (pipeline-view-selected v)]
         [grab (list id 'grab)]   ; (mx my center moved?)
         [mx (ui-state-mx ui)] [my (ui-state-my ui)]
         [win (current-window)]
         [over? (and win (eq? (window-hover win) 'content)
                     (point-in? mx my x y w h))])
    (ui-region! ui id x y w h
      'doc '((L . "List what may touch this pixel, or drag to move")
             (Wheel . "Zoom in or out"))
      'on (lambda (ev)
            (case (car ev)
              [(press)
               (and (eq? (list-ref ev 3) 'left)
                    (begin
                      (ui-memo! ui grab (list (cadr ev) (caddr ev)
                                              (pipeline-viewer-center v) #f))
                      #t))]
              [(drag)
               (let ([g (ui-memo ui grab #f)])
                 (and g
                      (let ([dx (- (cadr ev) (car g))]
                            [dy (- (caddr ev) (cadr g))]
                            [k (/ (draw-scale) (pipeline-viewer-zoom v w h))])
                        (when (or (cadddr g) (> (+ (abs dx) (abs dy)) 3))
                          (ui-memo! ui grab
                                    (list (car g) (cadr g) (caddr g) #t))
                          (when (pipeline-view-zoom v)
                            (pipeline-view-center-set!
                             v (cons (- (car (caddr g)) (* k dx))
                                     (- (cdr (caddr g)) (* k dy))))))
                        #t)))]
              [(release)
               (let ([g (ui-memo ui grab #f)])
                 (ui-memo! ui grab #f)
                 (and g
                      (begin
                        (unless (cadddr g)
                          (let ([p (pipeline-viewer-pixel
                                    v x y w h (cadr ev) (caddr ev))])
                            (pipeline-trace! v (exact (floor (car p)))
                                             (exact (floor (cdr p))))))
                        #t)))]
              [(wheel)
               (pipeline-zoom-at! v x y w h (ui-state-mx ui) (ui-state-my ui)
                                  (cadr ev))
               #t]
              [else #f])))
    (pipeline-draw-viewer
     v (pipeline-view-image v) x y w h
     (let ([first (and selected (pipeline-node-first v selected))])
       (and first (< first n) (inspect-reach l first))))
    (when (and over? (pipeline-view-loupe? v) (pipeline-view-image v))
      (let* ([p (pipeline-viewer-pixel v x y w h mx my)]
             [px (exact (floor (car p)))] [py (exact (floor (cdr p)))]
             [said (ui-memo ui (list id 'loupe) #f)]
             [caption (if (and said (equal? (car said) p))
                          (cdr said)
                          (let ([c (pipeline-loupe-caption v px py)])
                            (ui-memo! ui (list id 'loupe) (cons p c))
                            c))])
        (ui-later! ui
          (lambda (ww wh)
            (let ([size pipeline-loupe-size]
                  [tall (+ pipeline-loupe-size
                           (font-line-height 'ui-small) 6)])
              (pipeline-draw-loupe
               (pipeline-view-image v)
               (if (> (+ mx 20 size) ww) (- mx 20 size) (+ mx 20))
               (if (> (+ my 20 tall) wh) (- my 20 tall) (+ my 20))
               px py caption))))))))

;; Fit, 100%, the loupe, how far the viewer vw × vh is zoomed, and Pop out
;; unless it's out.
(define (pipeline-viewer-bar v ui x y w vw vh popped?)
  (let* ([ch (ui-control-height)] [gap 6]
         [fw (+ 24 (text-width "Fit" 'ui))]
         [hw (+ 24 (text-width "100%" 'ui))]
         [lx (+ x fw gap hw gap)])
    (ui-button ui '(pipeline fit) x y fw ch "Fit"
               (lambda ()
                 (pipeline-view-zoom-set! v #f)
                 (pipeline-view-center-set! v #f))
               'tip "Show the whole screen")
    (ui-button ui '(pipeline actual) (+ x fw gap) y hw ch "100%"
               (lambda ()
                 (unless (pipeline-view-zoom v)
                   (pipeline-view-center-set! v (pipeline-viewer-center v)))
                 (pipeline-view-zoom-set! v 1))
               'tip "A pixel of the screen for a pixel")
    (let-values ([(cw chh) (ui-checkbox-size "Loupe")])
      (ui-checkbox ui '(pipeline loupe) lx y cw ch "Loupe"
                   (pipeline-view-loupe? v)
                   (lambda (on?) (pipeline-view-loupe?-set! v on?))
                   'tip "Magnify the pixels at the pointer")
      (let* ([pw (if popped? 0 (+ 24 (text-width "Pop out" 'ui)))]
             [zx (+ lx cw gap)])
        (ui-draw-label zx y (max 0 (- (+ x w) pw gap zx)) ch '(dim)
                       (format "~a%"
                               (exact (round (* 100 (pipeline-viewer-zoom
                                                     v vw vh))))))
        (unless popped?
          (ui-button ui '(pipeline pop) (- (+ x w) pw) y pw ch "Pop out"
                     (lambda () (pipeline-pop-out! v (current-window)))
                     'tip "Show it in a window of its own, above the \
                           Pipeline")))))
  ;; under them, what it shows
  (let* ([ch (ui-control-height)] [y (+ y ch 6)]
         [lw (+ 8 (text-width "Show" 'ui))])
    (ui-draw-label x y lw ch '(dim) "Show")
    (ui-dropdown ui '(pipeline look) (+ x lw) y (min 150 (- w lw)) ch
                 pipeline-looks (pipeline-view-look v)
                 (lambda (look)
                   (pipeline-view-look-set! v look)
                   (pipeline-preview! v)))
    (ui-draw-label (+ x lw (min 150 (- w lw)) 8) y
                   (max 0 (- w lw (min 150 (- w lw)) 8)) ch '(dim)
                   (cdr (assq (pipeline-view-look v) pipeline-look-notes)))))

;; What the small screen may show, and in a word what each means.
(define pipeline-looks
  '(("Picture" . picture)
    ("Who drew" . who)
    ("Kind" . kind)
    ("Heat" . heat)
    ("Changed" . changed)))
(define pipeline-look-notes
  '((picture . "")
    (who . "a drawer a color")
    (kind . "as the Tape's kinds")
    (heat . "more records, brighter")
    (changed . "bright: changed")))

;; Its two rows' height.
(define (pipeline-viewer-bar-height)
  (+ (ui-control-height) 6 (ui-control-height)))

;; The viewer in a window of its own, kept above the Pipeline's, win: closed,
;; it's back in its place.
(define (pipeline-pop-out! v win)
  (unless (pipeline-view-popped v)
    (let* ([ui (make-ui)]
           [w 960]
           [h (exact (round (+ (* w (/ *canvas-ph* *canvas-pw*))
                               (pipeline-viewer-bar-height) (* 3 (ui-pad)))))])
      (pipeline-view-popped-set!
       v (apply open-window "Pipeline — the screen"
                'size (cons w h)
                'min-size '(320 . 240)
                'app (window-app win)
                'above win
                'draw (lambda (pop w h) (pipeline-popped-draw v ui w h))
                'close (lambda (pop)
                         (pipeline-view-popped-set! v #f)
                         (invalidate! win))
                (ui-handlers ui
                             'key (lambda (pop key mods)
                                    (pipeline-key v pop key mods))))))))

(define (pipeline-popped-draw v ui w h)
  (let ([pad (ui-pad)] [bh (pipeline-viewer-bar-height)])
    (ui-begin! ui)
    (let ([vw (- w pad pad)] [vh (- h pad bh pad pad)])
      (pipeline-viewer-bar v ui pad pad vw vw vh #t)
      (pipeline-viewer v ui '(pipeline viewer) pad (+ pad bh pad) vw vh))
    (ui-end! ui w h)))

;; With the loupe on, a move of the pointer in either window draws again.
(define (pipeline-loupe-follow! v win)
  (let ([popped (pipeline-view-popped v)])
    (for-each (lambda (ui)
                (let ([at (cons (ui-state-mx ui) (ui-state-my ui))])
                  (unless (equal? at (ui-memo ui '(pipeline pointer) #f))
                    (ui-memo! ui '(pipeline pointer) at)
                    (invalidate! win))))
              (cons (pipeline-view-ui v)
                    (if popped (list (window-ref popped 'ui)) '())))))

(define (pipeline-card-lines v stage)
  (case stage
    [(who)
     (let ([rows (pipeline-who-rows v)])
       (list (format "main drew in ~,2f ms"
                     (fold-left (lambda (ms r) (+ ms (or (vector-ref r 2) 0.0)))
                                0.0 rows))
             (if (null? rows)
                 "nothing drawn"
                 (format "the most pixels: ~a"
                         (pipeline-node-name
                          (vector-ref
                           (fold-left (lambda (a r)
                                        (if (> (vector-ref r 4)
                                               (vector-ref a 4))
                                            r
                                            a))
                                      (car rows) (cdr rows))
                           0))))))]
    [(lists)
     (let ([l (pipeline-view-shown v)])
       (list (format "~a records, ~a KB" (inspect-list-count l)
                     (quotient (inspect-list-bytes l) 1024))
             (let ([lists (inspect-list-lists l)])
               (format "~a drew, ~a lists, ~a changed"
                       (length (inspect-list-labels l)) (length lists)
                       (length (filter (lambda (lst)
                                         (pipeline-list-changed? v lst))
                                       lists))))))]
    [(course)
     (let ([c (pipeline-course v)])
       (if c
           (list (format "tick ~a, ~,2f ms busy" (car c)
                         (fold-left (lambda (ms it) (+ ms (cadr it))) 0.0
                                    (remp (lambda (it)
                                            (memq (caddr it) '(idle total)))
                                          (cadr c))))
                 (format "render ~,2f ms of it"
                         (fold-left (lambda (ms it)
                                      (if (memq (caddr it) '(drawer gpu))
                                          (+ ms (cadr it))
                                          ms))
                                    0.0 (cadr c))))
           (list "no tick kept" "")))]
    [(inside)
     (let ([i (pipeline-inside-record v)] [l (pipeline-view-shown v)])
       (if i
           (let ([run (inspect-record-run l i)])
             (list (format "record ~a, a ~a" i (inspect-kind l i))
                   (if run
                       (format "~a" (shader-name (inspect-run-fragment run)))
                       "")))
           (list "a record selected," "decoded")))]
    [(latency) (list-head (pipeline-latency-words v) 2)]
    [else
     (let ([d (inspect-device)] [g (inspect-glyphs)])
       (list (format "~a MB on the GPU"
                     (pipeline-mb (apply + (map cddr (inspect-gpu-objects)))))
             (format "the atlas ~a% used"
                     (exact (round (* 100 (cdr (assq 'atlas-used g))))))))]))

(define (pipeline-mb bytes) (format "~,1f" (/ bytes 1048576.0)))

;; Screen's pane: one fact a line.
(define (pipeline-screen-facts v)
  (let-values ([(d) (inspect-device)] [(g) (inspect-glyphs)]
               [(image) (pipeline-view-image v)]
               [(kept not-shown) (inspect-frames-kept)]
               [(p50 p99 missed) (inspect-frames-truth 10000)])
    (append
     (list (cons "Renderer" (if (eq? (cdr (assq 'renderer d)) 'cpu)
                                "lavapipe, on the CPU"
                                "the GPU"))
           (cons "Showing on" (if (cdr (assq 'window? d))
                                  "a window, by its swapchain"
                                  "a texture, no window"))
           (cons "Presenting"
                 (format "by ~a, of ~a" (cdr (assq 'present-mode d))
                         (cdr (assq 'present-modes d))))
           (cons "Pixels"
                 (format "~a × ~a at ~a%"
                         (cadr (assq 'pixels d)) (cddr (assq 'pixels d))
                         (exact (round (* 100 (cdr (assq 'scale d)))))))
           (cons "Frames kept"
                 (format "~a, ~a of them not shown" kept not-shown))
           (cons "Input to screen"
                 (if p50
                     (format "~,1f ms at the median, ~,1f at the 99th, the \
                              last 10 s"
                             (/ p50 1e6) (/ p99 1e6))
                     "no word from the screen in the last 10 s"))
           (cons "Refreshes missed"
                 (format "~a in the last 10 s, by the screen" missed))
           (cons "Glyphs"
                 (format "~a, the atlas ~a% used"
                         (cdr (assq 'glyphs g))
                         (exact (round (* 100 (cdr (assq 'atlas-used g))))))))
     (map (lambda (o)
            (cons (format "~a" (car o))
                  (format "~a, ~a KB" (cadr o) (quotient (cddr o) 1024))))
          (inspect-gpu-objects))
     (if image
         (list (cons "small screen"
                     (format "2 textures, ~a KB"
                             (quotient (* 2 (inspect-preview-bytes image))
                                       1024))))
         '()))))

(define (pipeline-lists-pane v x y w h)
  (let* ([ui (pipeline-view-ui v)] [traced (pipeline-view-traced v)]
         [columns `((name "Who" 190)
                    (first "Record" 72 right)
                    (count "Count" 64 right)
                    (paint "Paint" 140)
                    (what "What" ,(max 80 (- (ui-table-room w) 190 72 64
                                             140))))]
         [box (ui-checkbox-box)]
         ;; a span's name has its checkbox: off, it's left out
         [cell (lambda (node key cx cy cw ch flags)
                 (if (and (eq? key 'name) (pair? node))
                     (begin
                       (ui-checkbox ui (list 'pipeline 'shows node) cx cy box ch
                                    "" (not (member node (pipeline-view-off v)))
                                    (lambda (on?)
                                      (pipeline-show-span! v node on?))
                                    'focus 'keep
                                    'tip "Draw it on the small screen and the \
                                          Tape")
                       (ui-draw-cell (+ cx box 6) cy (max 0 (- cw box 6)) ch
                                     flags (pipeline-node-name node)))
                     (if (and (eq? key 'paint) (vector? node))
                         (pipeline-draw-paint
                          cx cy cw ch flags
                          (inspect-record-paint (pipeline-view-shown v)
                                                (vector-ref node 0)))
                         (ui-draw-cell
                      cx cy cw ch flags
                      (case key
                        [(name) (pipeline-node-name node)]
                        [(first)
                         (number->string (pipeline-node-first v node))]
                        [(count)
                         (number->string (pipeline-node-count v node))]
                        [(paint) ""]
                        [else (pipeline-node-what v node)])))))]
         [select! (lambda (node) (pipeline-select! v node))])
    (if traced
        (let ([ch (ui-control-height)])
          (ui-draw-label x y (- w 90) ch '(dim)
                         (format "Records at pixel ~a, ~a"
                                 (car traced) (cadr traced)))
          (ui-button ui '(pipeline untrace) (+ x w -80) y 80 ch "All"
                     (lambda () (pipeline-view-traced-set! v #f)))
          (ui-table ui '(pipeline traced) x (+ y ch 4) w (- h ch 4) columns
                    (caddr traced) (pipeline-view-selected v) select! cell))
        (let ([shown (pipeline-tree-selected v)])
          (when (vector? shown)
            (pipeline-tree-open! ui (pipeline-span-node-at
                                     v (vector-ref shown 0))))
          (ui-tree ui '(pipeline tree) x y w h columns
                   (pipeline-span-nodes (pipeline-view-groups v))
                   (lambda (node) (pipeline-children v node))
                   shown select! cell
                   'dim (lambda (node) (pipeline-node-off? v node))
                   'reveal (not (equal? shown (ui-memo ui '(pipeline revealed)
                                                       #f))))
          (ui-memo! ui '(pipeline revealed) shown)))))

;; The small screen's images, as big as the screen: the shader draws on real
;; pixels. Made again when the screen's size changes: a draw still waiting names
;; the old ones, so the new one's first picture takes its place.
(define (pipeline-image! v)
  (let ([image (pipeline-view-image v)] [pw *canvas-pw*] [ph *canvas-ph*])
    (if (and image (= (inspect-preview-w image) pw)
             (= (inspect-preview-h image) ph))
        image
        (begin
          (when image
            (inspect-preview-free! image)
            (inspect-preview-free! (pipeline-view-back v)))
          (pipeline-view-image-set! v (inspect-preview-image pw ph))
          (pipeline-view-back-set! v (inspect-preview-image pw ph))
          (pipeline-view-flip?-set! v #f)
          (pipeline-preview! v)
          (pipeline-view-image v)))))

(define (pipeline-draw v win w h)
  (let* ([ui (pipeline-view-ui v)] [pad (ui-pad)] [gap (ui-gap)]
         [lh (font-line-height 'ui)]
         [card-h (+ 12 (* 3 lh))]
         [river-h (pipeline-river-height v (- w pad pad))]
         [tape-h (pipeline-tape-height v (- w pad pad))]
         [side (min 360 (quotient w 2))]
         [top (+ pad card-h gap)]
         ;; Latency's bars stand over the River's, a tick each, as wide: no
         ;; small screen beside it, no Tape under it
         [latency? (eq? (pipeline-view-stage v) 'latency)]
         [bottom (max top (- h pad river-h gap
                             (if latency? 0 (+ tape-h gap))))]
         [l (pipeline-view-shown v)]
         [ch (ui-control-height)]
         [screen-w (- side pad)]
         [bh (pipeline-viewer-bar-height)]
         ;; as tall as the screen's shape says, but for its bar and the two
         ;; rows under it: the viewer fits the screen in whatever it's given
         [screen-h (max ch (min (exact (round (* screen-w (/ *canvas-ph*
                                                              *canvas-pw*))))
                                (- bottom top gap bh gap
                                   (* 2 (+ ch gap)))))])
    (ui-begin! ui)
    (let ([card-w (quotient (- w pad pad (* 5 gap)) 6)])
      (for-each
       (lambda (stage name i)
         (let ([cx (+ pad (* i (+ card-w gap)))])
           (ui-area ui (list 'pipeline stage) cx pad card-w card-h
                    (lambda () (pipeline-view-stage-set! v stage)))
           (pipeline-draw-card cx pad card-w card-h
                               (eq? stage (pipeline-view-stage v)) name
                               (pipeline-card-lines v stage))))
       '(lists who course inside memory latency)
       '("Lists" "Who" "Course" "Inside" "Memory" "Latency")
       '(0 1 2 3 4 5)))
    (let ([pane-w (if latency? (- w pad pad) (- w pad pad side gap))])
      (with-clip (pad top pane-w (- bottom top))
        (case (pipeline-view-stage v)
          [(lists) (pipeline-lists-pane v pad top pane-w (- bottom top))]
          [(who) (pipeline-who-pane v pad top pane-w (- bottom top))]
          [(course) (pipeline-course-pane v pad top pane-w (- bottom top))]
          [(inside) (pipeline-inside-pane v pad top pane-w (- bottom top))]
          [(latency)
           (pipeline-latency-pane v pad top pane-w (- bottom top))]
          [else (pipeline-memory-pane v pad top pane-w (- bottom top))]))
      ;; the small screen, or its place while it's out; its bar, Hold
      (unless latency? (pipeline-image! v))
      (unless latency?
        (let* ([sx (+ pad pane-w gap)]
               [sy (+ top screen-h gap)]
               [hy (+ sy bh gap)])
          (if (pipeline-view-popped v)
              (let ([bw (+ 24 (text-width "Bring it back" 'ui))])
                (pipeline-draw-popped-out sx top screen-w screen-h)
                (ui-draw-label sx (+ top (/ (- screen-h ch ch gap) 2)) screen-w
                               ch '(dim center) "In a window of its own")
                (ui-button ui '(pipeline unpop) (+ sx (/ (- screen-w bw) 2))
                           (+ top (/ (+ (- screen-h ch ch gap) ch ch gap) 2))
                           bw ch "Bring it back"
                           (lambda ()
                             (close-window! (pipeline-view-popped v)))))
              (begin
                (pipeline-viewer v ui '(pipeline viewer) sx top screen-w
                                 screen-h)
                (pipeline-viewer-bar v ui sx sy screen-w screen-w screen-h #f)))
          (ui-checkbox ui '(pipeline hold) sx hy
                       screen-w ch "Hold this frame" (pipeline-view-held? v)
                       (lambda (on?)
                         (if on? (pipeline-hold! v) (pipeline-resume! v))))
          (let* ([ey (+ hy ch gap)]
                 [every (pipeline-view-every v)]
                 [label "Draw it every"]
                 [lw (+ 8 (text-width label 'ui))])
            (ui-draw-label sx ey lw ch '(dim) label)
            (let ([sw (ui-stepper
                       ui '(pipeline every) (+ sx lw) ey every 1 60
                       (lambda (n) (pipeline-view-every-set! v n))
                       'tip "How often the small screen draws again, in \
                             frames: each time, the GPU goes over the whole \
                             frame once more")])
              (ui-draw-label (+ sx lw sw 8) ey (max 0 (- screen-w lw sw 8)) ch
                             '(dim) (if (= every 1) "tick" "ticks"))))
          ;; what a frame kept can't show
          (when (and (pipeline-view-held? v) (> (inspect-list-left-out l) 0))
            (ui-draw-label sx (+ hy ch gap ch gap)
                           screen-w 0 '(hint wrap)
                           "An image or a paint let go of since this frame \
                            is left out of it here.")))))
    (unless latency?
      (pipeline-tape-pane v pad (+ bottom gap) (- w pad pad) tape-h))
    (pipeline-river-pane v pad (- h pad river-h) (- w pad pad) river-h)
    (ui-end! ui w h)))

;; Each frame while it's seen and flows: the frame just drawn is kept, a new
;; bar drawn, and the small screen with it as often as it's told.
(define (pipeline-frame! v win)
  (when (pipeline-view-playing v)
    (pipeline-play-tick! v)
    (invalidate! win))
  (when (pipeline-view-loupe? v) (pipeline-loupe-follow! v win))
  (unless (pipeline-view-held? v)
    (pipeline-flip! v)
    (let ([history (pipeline-view-history v)])
      (inspect-history-add! history)
      ;; the small screen, while it's shown: Latency has none beside it
      (when (and (zero? (modulo (inspect-history-newest history)
                                (pipeline-view-every v)))
                 (or (pipeline-view-popped v)
                     (not (eq? (pipeline-view-stage v) 'latency))))
        (pipeline-preview-back! v)))
    (let ([newest (profile-newest-tick)])
      (when (and newest
                 (not (eqv? newest (ui-stream-sent (pipeline-view-river v)))))
        (invalidate! win)))
    ;; a period after the last read was due, not after it was done, so that
    ;; reads keep in step with the clock; one a period late or more starts
    ;; again from then
    (let* ([due (+ (pipeline-view-looked v) pipeline-period-ms)]
           [late (- (now-ms) due)])
      (when (>= late 0)
        (pipeline-look! v)
        (when (< late pipeline-period-ms) (pipeline-view-looked-set! v due))
        (invalidate! win)))))

(define-app (pipeline) "Pipeline"
  (let ([existing (find-window 'pipeline)])
    (if existing
        (begin (focus-window! existing) existing)
        (let* ([ui (make-ui)]
               [river (ui-stream-new pipeline-river-rows (length monitor-phases)
                                     pipeline-draw-lanes)]
               [v (make-pipeline-view ui (inspect-history-new
                                          pipeline-frames-kept)
                                      river 'lists (inspect-list) #f 0 '() #f #f
                                      #f #f #f #f #f #f '() 0.0 #f 1
                                      (pipeline-tape-new 0) #f #f 5
                                      #f #f #f #f '() #f #f 'picture
                                      (inspect-list-empty) #f #f #f #f
                                      (pipeline-latency-new) #f
                                      (make-hashtable equal-hash equal?))])
          (pipeline-look! v)
          (apply open-window "Pipeline"
                 'size '(1100 . 860)
                 'min-size '(640 . 560)
                 'state v
                 'draw (lambda (win w h) (pipeline-draw v win w h))
                 'close (lambda (win)
                          (let ([image (pipeline-view-image v)])
                            (when image
                              (inspect-preview-free! image)
                              (inspect-preview-free! (pipeline-view-back v)))
                            (pipeline-view-image-set! v #f)
                            (pipeline-view-back-set! v #f))
                          (ui-stream-release! river)
                          (ui-stream-release! (pipeline-view-tape v))
                          (ui-stream-release! (pipeline-view-latency v)))
                 (append
                  (ui-handlers ui
                               'key (lambda (win key mods)
                                      (pipeline-key v win key mods)))
                  (list 'open (lambda (win) (window-frame-soon! win))
                        'frame (lambda (win t)
                                 (window-frame-soon! win)
                                 (ui-frame ui win)
                                 (pipeline-frame! v win)))))))))
