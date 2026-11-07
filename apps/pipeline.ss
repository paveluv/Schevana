;;; apps/pipeline.ss — Pipeline: the way from a window's draw to the screen
;;; surface, on one screen, read through kits/inspect.ss.
;;;
;;; For now two stages, chosen on the cards at the top:
;;;   Lists   the frame's list by who drew it, and each's records, decoded
;;;           in draw order, a run of glyphs as its text
;;;   Screen  what draws, and what it holds on the GPU
;;; Right, the screen small, the selected record outlined: a press there
;;; lists the records that may touch that pixel, and the slider draws the
;;; list as far as a record.
;;; Below, the River: a bar a tick as it flows, what main did, and in lanes
;;; over them what else happened. A press holds it and goes back to that
;;; tick's frame, the whole app showing it; a drag moves through them. Frames
;;; are kept for a few seconds, what's left of the River's reach, while it's
;;; open: closed, what's left of it is the core's few numbers a frame.
;;; While it flows it asks for a frame a tick, so it says what it takes itself.

(define-record-type pipeline-view
  (fields ui history river
          (mutable stage)      ; lists or screen
          (mutable shown)      ; (inspect-list), the one on view
          (mutable held?)      ; it stays
          (mutable looked)     ; when it was read (now-ms)
          (mutable groups)     ; the tree's roots: (label first count) ...
          (mutable selected)   ; a tree node
          (mutable traced)     ; the records at a pixel, or #f: (x y n ...)
          (mutable upto)       ; the slider's record, or #f: all of them
          (mutable image)      ; the small screen, or #f
          (mutable reach)      ; while held, where the River stops: (newest
                               ; . oldest)
          (mutable tick)       ; the tick picked, or #f
          (mutable order)      ; how the River's bars stack: columns
          (mutable own)        ; what it takes itself, ms a tick
          (mutable tip)))      ; the last bar's tooltip: (seq . text)

(define pipeline-period-ms 250)

;; About 5 seconds at 60 Hz.
(define pipeline-frames-kept 300)
(define pipeline-river-rows 2048)
(define pipeline-bar-px 3)

(define (pipeline-show! v l)
  (pipeline-view-shown-set! v l)
  (pipeline-view-groups-set! v (inspect-list-labels l)))

;; What the window takes itself, ms a tick, over the last half second.
(define (pipeline-own-ms)
  (let ([win (find-window 'pipeline)] [newest (profile-newest-tick)])
    (if (and win newest)
        (let ([seqs (filter profile-tick-kept?
                            (map (lambda (i) (- newest i)) (iota 30)))]
              [subject (profile-subject-of win)])
          (/ (fold-left (lambda (ms seq)
                          (+ ms (profile-tick-node-ms seq subject)))
                        0.0 seqs)
             (max 1 (length seqs))))
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

;; The small screen shows what's on view. Live, it's drawn with the next frame;
;; held, what's kept of the frame is.
(define (pipeline-preview! v)
  (let ([image (pipeline-view-image v)] [l (pipeline-view-shown v)])
    (when image
      (let ([count (or (pipeline-view-upto v) (inspect-list-count l))])
        (if (pipeline-view-held? v)
            (inspect-preview-list! image l count)
            (inspect-preview! image count))))))

;;; ---- going back

;; The frame on the screen when tick seq ended.
(define (pipeline-tick-frame seq) (- (profile-tick-ns seq 'frames) 1))

;; It stops flowing, and the frames stay as they are, the last one among them.
(define (pipeline-hold! v)
  (unless (pipeline-view-held? v)
    (inspect-history-add! (pipeline-view-history v))
    (pipeline-view-held?-set! v #t)
    (pipeline-view-tick-set! v (profile-newest-tick))
    (pipeline-view-reach-set! v (cons (profile-newest-tick)
                                      (profile-oldest-tick)))
    (pipeline-preview! v)))

(define (pipeline-resume! v)
  (pipeline-view-held?-set! v #f)
  (pipeline-view-tick-set! v #f)
  (pipeline-view-traced-set! v #f)
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
;; lanes, a word each: late; a frame sent, shown or not; where the GPU stood
;; with the frame before: done, finishing, or not yet; the collector, by how
;; long; input.
(define pipeline-draw-lanes
  `(("late" chart-flag)
    ("frame" chart-ok chart-flag)
    ("GPU" chart-ok chart-2 chart-flag)
    ("collector"
     ,@(map (lambda (i)
              (alpha 'chart-7
                     (+ 0.2 (* 0.8 (/ i (- pipeline-collector-levels 1.0))))))
            (iota pipeline-collector-levels)))
    ("input" chart-1)))

;; What a lane's colors say, on its label.
(define pipeline-lane-tips
  `("Red: this tick came late, past one and a half periods. None: it was in \
     time."
    "Green: the tick's frame reached the screen. Red: the window had no room \
     for it. None: no frame was drawn."
    "Where the GPU stood with the frame before, as main asked for the next \
     image. Green: it had finished. Orange: it finished during the wait. Red: \
     it hadn't yet."
    ,(format "A collection ran in this tick: the longer it took, the brighter, \
              at its brightest from ~a."
             (monitor-ns-text pipeline-collector-full-ns))
    "The keyboard or the mouse sent something."))

;; The lanes' readings of tick seq, in words, for its tooltip.
(define (pipeline-tick-lanes seq)
  (let ([drew? (or (not (profile-tick-kept? (- seq 1)))
                   (> (profile-tick-ns seq 'frames)
                      (profile-tick-ns (- seq 1) 'frames)))])
    (string-append
     (if drew?
         (format "\nframe ~a; GPU ~a with the one before"
                 (if (> (profile-tick-ns seq 'shown) 0)
                     "reached the screen"
                     "had no room")
                 (vector-ref '#("had finished" "finished during the wait"
                                "hadn't finished")
                             (profile-tick-ns seq 'gpu)))
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
          (let ([drew? (or (not (profile-tick-kept? (- seq 1)))
                           (> (profile-tick-ns seq 'frames)
                              (profile-tick-ns (- seq 1) 'frames)))])
            (case (- j phases)
              [(0) (if (profile-tick-late? seq period) 1 0)]
              [(1) (cond [(not drew?) 0]
                         [(> (profile-tick-ns seq 'shown) 0) 1]
                         [else 2])]
              [(2) (if drew? (+ 1 (profile-tick-ns seq 'gpu)) 0)]
              [(3) (if (> (profile-tick-ns seq 'gcs) 0)
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
                   (inspect-history-ref history (pipeline-tick-frame seq)))
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

(define (pipeline-river-pane v x y w h)
  (let*-values
      ([(ui) (pipeline-view-ui v)]
       [(river) (pipeline-view-river v)]
       [(period) (pacer-period)]
       [(top) (quotient (* 2 period) 1000)]
       [(rules) (list (cons (quotient period 1000) (monitor-ns-text period))
                      (cons top (monitor-ns-text (* 2 period))))]
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

;;; ---- what the tree holds

;; A node is a label's span, (label first count), or a row of it (a vector).
(define (pipeline-children v node)
  (if (pair? node)
      (inspect-rows (pipeline-view-shown v) (cadr node) (caddr node))
      '()))

(define (pipeline-node-first node)
  (if (pair? node) (cadr node) (vector-ref node 0)))
(define (pipeline-node-count node)
  (if (pair? node) (caddr node) (vector-ref node 1)))

(define (pipeline-node-name node)
  (cond [(pair? node)
         (let ([label (car node)])
           (if (string? label) label (format "~a" label)))]
        [else (format "~a" (vector-ref node 2))]))

(define (pipeline-node-what node)
  (if (pair? node) "" (vector-ref node 3)))

;; The records at a device pixel, as nodes.
(define (pipeline-trace! v x y)
  (let* ([l (pipeline-view-shown v)]
         [at (inspect-records-at l x y)])
    (pipeline-view-traced-set!
     v (list x y (map (lambda (i) (car (inspect-rows l i 1))) at)))
    (unless (null? at)
      (pipeline-view-selected-set! v (car (inspect-rows l (car at) 1))))))

;;; ---- drawing

;; A stage's card: its name and what it holds, lines of text; pressed, it
;; opens.
(define (pipeline-draw-card x y w h selected? name lines)
  (fill-box x y w h (if selected? 'bg-3 'bg-1) 4)
  (when selected? (stroke-box x y w h 'accent 1 4))
  (let ([lh (font-line-height 'ui)])
    (draw-text (+ x 10) (+ y 6) name 'text 'ui-bold)
    (for-each (lambda (line i)
                (draw-text (+ x 10) (+ y 6 (* lh (+ i 1))) line 'text-dim 'ui))
              lines (iota (length lines)))))

;; The screen small, what's selected outlined. A pixel of the image is k
;; device pixels.
(define (pipeline-draw-screen image x y w h box k)
  (fill-box x y w h 'bg-0)
  (when image (draw-image image x y w h))
  (stroke-box x y w h 'window-border)
  (when box
    (let ([bx (+ x (/ (car box) k))] [by (+ y (/ (cadr box) k))])
      (stroke-box bx by
                  (max 3 (/ (- (caddr box) (car box)) k))
                  (max 3 (/ (- (cadddr box) (cadr box)) k))
                  'accent 1))))

(define (pipeline-card-lines v stage)
  (case stage
    [(lists)
     (let* ([l (pipeline-view-shown v)] [row (inspect-list-row l)])
       (list (format "~a records, ~a KB" (inspect-list-count l)
                     (quotient (inspect-list-bytes l) 1024))
             (format "~a drew, ~a runs"
                     (length (inspect-list-labels l))
                     (if row (cadddr row) 0))))]
    [else
     (let ([d (inspect-device)])
       (list (format "~a × ~a, on the ~a"
                     (cadr (assq 'pixels d)) (cddr (assq 'pixels d))
                     (if (eq? (cdr (assq 'renderer d)) 'cpu) "CPU" "GPU"))
             (format "last frame ~,1f ms" *frame-ms*)))]))

;; Screen's pane: one fact a line.
(define (pipeline-screen-facts)
  (let ([d (inspect-device)] [g (inspect-glyphs)]
        [frames (inspect-frames frame-ring-rows)])
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
                 (format "~a, ~a of them not shown"
                         (length frames)
                         (length (remp (lambda (f) (list-ref f 5)) frames))))
           (cons "Glyphs"
                 (format "~a, the atlas ~a% used"
                         (cdr (assq 'glyphs g))
                         (exact (round (* 100 (cdr (assq 'atlas-used g))))))))
     (map (lambda (o)
            (cons (format "~a" (car o))
                  (format "~a, ~a KB" (cadr o) (quotient (cddr o) 1024))))
          (inspect-gpu-objects)))))

(define (pipeline-lists-pane v x y w h)
  (let* ([ui (pipeline-view-ui v)] [traced (pipeline-view-traced v)]
         [columns `((name "Who" 170)
                    (first "Record" 72 right)
                    (count "Count" 64 right)
                    (what "What" ,(max 80 (- w 170 72 64 24))))]
         [cell (lambda (node key cx cy cw ch flags)
                 (ui-draw-label
                  cx cy cw ch flags
                  (case key
                    [(name) (pipeline-node-name node)]
                    [(first) (number->string (pipeline-node-first node))]
                    [(count) (number->string (pipeline-node-count node))]
                    [else (pipeline-node-what node)])))]
         [select! (lambda (node) (pipeline-view-selected-set! v node))])
    (if traced
        (let ([ch (ui-control-height)])
          (ui-draw-label x y (- w 90) ch '(dim)
                         (format "Records at pixel ~a, ~a"
                                 (car traced) (cadr traced)))
          (ui-button ui '(pipeline untrace) (+ x w -80) y 80 ch "All"
                     (lambda () (pipeline-view-traced-set! v #f)))
          (ui-table ui '(pipeline traced) x (+ y ch 4) w (- h ch 4) columns
                    (caddr traced) (pipeline-view-selected v) select! cell))
        (ui-tree ui '(pipeline tree) x y w h columns
                 (pipeline-view-groups v)
                 (lambda (node) (pipeline-children v node))
                 (pipeline-view-selected v) select! cell))))

(define (pipeline-screen-pane v x y w h)
  (let ([lh (font-line-height 'ui)])
    (for-each (lambda (fact i)
                (let ([ly (+ y (* i (+ lh 4)))])
                  (ui-draw-label x ly 120 lh '(dim) (car fact))
                  (ui-draw-label (+ x 124) ly (- w 124) lh '() (cdr fact))))
              (pipeline-screen-facts)
              (iota (length (pipeline-screen-facts))))))

;; The small screen's image, as big as the screen: the shader draws on real
;; pixels. Made again when the screen's size changes.
(define (pipeline-image! v)
  (let ([image (pipeline-view-image v)] [pw *canvas-pw*] [ph *canvas-ph*])
    (if (and image (= (inspect-preview-w image) pw)
             (= (inspect-preview-h image) ph))
        image
        (begin
          (when image (inspect-preview-free! image))
          (pipeline-view-image-set! v (inspect-preview-image pw ph))
          (when (pipeline-view-held? v) (pipeline-preview! v))
          (pipeline-view-image v)))))

(define (pipeline-draw v win w h)
  (let* ([ui (pipeline-view-ui v)] [pad (ui-pad)] [gap (ui-gap)]
         [lh (font-line-height 'ui)]
         [card-h (+ 12 (* 3 lh))]
         [river-h (pipeline-river-height v (- w pad pad))]
         [side (min 360 (quotient w 2))]
         [screen-w (- side pad)]
         [screen-h (exact (round (* screen-w (/ *canvas-ph* *canvas-pw*))))]
         [top (+ pad card-h gap)]
         [bottom (- h pad river-h gap)]
         [l (pipeline-view-shown v)]
         [selected (pipeline-view-selected v)]
         [ch (ui-control-height)])
    (ui-begin! ui)
    (let ([card-w (quotient (- w pad pad gap) 2)])
      (for-each
       (lambda (stage name i)
         (let ([cx (+ pad (* i (+ card-w gap)))])
           (ui-area ui (list 'pipeline stage) cx pad card-w card-h
                    (lambda () (pipeline-view-stage-set! v stage)))
           (pipeline-draw-card cx pad card-w card-h
                               (eq? stage (pipeline-view-stage v)) name
                               (pipeline-card-lines v stage))))
       '(lists screen) '("Lists" "Screen") '(0 1)))
    (let ([pane-w (- w pad pad side gap)])
      (with-clip (pad top pane-w (- bottom top))
        (if (eq? (pipeline-view-stage v) 'lists)
            (pipeline-lists-pane v pad top pane-w (- bottom top))
            (pipeline-screen-pane v pad top pane-w (- bottom top))))
      ;; the small screen, the slider and Hold under it
      (let* ([sx (+ pad pane-w gap)]
             [k (/ *canvas-pw* screen-w)]
             [image (pipeline-image! v)]
             [n (inspect-list-count l)]
             [upto (or (pipeline-view-upto v) n)]
             [sy (+ top screen-h gap)])
        (ui-area ui '(pipeline screen) sx top screen-w screen-h
                 #f
                 (lambda (mx my)
                   (pipeline-trace! v (exact (floor (* k (- mx sx))))
                                    (exact (floor (* k (- my top)))))))
        (pipeline-draw-screen
         image sx top screen-w screen-h
         (and selected
              (< (pipeline-node-first selected) n)
              (inspect-reach l (pipeline-node-first selected)))
         k)
        (ui-draw-label sx sy screen-w lh '(dim)
                       (if (pipeline-view-upto v)
                           (format "As far as record ~a of ~a" upto n)
                           (format "All ~a records" n)))
        (ui-slider ui '(pipeline upto) sx (+ sy lh 2) screen-w
                   (if (> n 0) (/ upto n) 1) 0 1
                   (lambda (f)
                     (pipeline-view-upto-set!
                      v (and (< f 1) (exact (floor (* f n)))))
                     (when (pipeline-view-held? v) (pipeline-preview! v))))
        (ui-checkbox ui '(pipeline hold) sx (+ sy lh 2 (ui-slider-height) gap)
                     screen-w ch "Hold this frame" (pipeline-view-held? v)
                     (lambda (on?)
                       (if on? (pipeline-hold! v) (pipeline-resume! v))))
        ;; what a frame kept can't show
        (when (and (pipeline-view-held? v) (> (inspect-list-left-out l) 0))
          (ui-draw-label sx (+ sy lh 2 (ui-slider-height) gap ch gap) screen-w
                         0 '(hint wrap)
                         "Images and paints aren't kept with a frame, so \
                          they're left out of it here."))))
    (pipeline-river-pane v pad (- h pad river-h) (- w pad pad) river-h)
    (ui-end! ui w h)))

;; Each tick while it flows: the frame just drawn is kept, and a new bar drawn.
(define (pipeline-tick! v win)
  (ui-tick (pipeline-view-ui v) win)
  (unless (pipeline-view-held? v)
    (inspect-history-add! (pipeline-view-history v))
    (let ([newest (profile-newest-tick)])
      (when (and newest
                 (not (eqv? newest (ui-stream-sent (pipeline-view-river v)))))
        (invalidate! win)))
    (when (> (- (now-ms) (pipeline-view-looked v)) pipeline-period-ms)
      (pipeline-look! v)
      (pipeline-preview! v)
      (invalidate! win))))

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
                                      #f #f #f #f '() 0.0 #f)])
          (pipeline-look! v)
          (apply open-window "Pipeline"
                 'size '(1100 . 760)
                 'min-size '(640 . 420)
                 'state v
                 'draw (lambda (win w h) (pipeline-draw v win w h))
                 'close (lambda (win)
                          (let ([image (pipeline-view-image v)])
                            (when image (inspect-preview-free! image))
                            (pipeline-view-image-set! v #f))
                          (ui-stream-release! river))
                 (append
                  (ui-handlers ui)
                  (list 'tick (lambda (win) (pipeline-tick! v win)))))))))
