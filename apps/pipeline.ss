;;; apps/pipeline.ss — Pipeline: the way from a window's draw to the screen
;;; surface, on one screen, read through kits/inspect.ss.
;;;
;;; For now two stages, chosen on the cards at the top:
;;;   Lists   the frame's list by who drew it, and each's records, decoded
;;;           in draw order, a run of glyphs as its text
;;;   Screen  what draws, and what it holds on the GPU
;;; Right, the screen small, the selected record outlined: a press there
;;; lists the records that may touch that pixel, and the slider draws the
;;; list as far as a record. Below, a bar a frame, against the tick.
;;; It looks 4 times a second, and only while it's open: closed, what's left
;;; of it is the core's few numbers a frame.

(define-record-type pipeline-view
  (fields ui
          (mutable stage)      ; lists or screen
          (mutable shown)      ; (inspect-list), the one on view
          (mutable held?)      ; it stays
          (mutable looked)     ; when it was read (now-ms)
          (mutable groups)     ; the tree's roots: (label first count) ...
          (mutable selected)   ; a tree node
          (mutable traced)     ; the records at a pixel, or #f: (x y n ...)
          (mutable upto)       ; the slider's record, or #f: all of them
          (mutable image)))    ; the small screen, or #f

(define pipeline-period-ms 250)

(define (pipeline-look! v)
  (unless (pipeline-view-held? v)
    (let ([l (inspect-list)])
      (pipeline-view-shown-set! v l)
      (pipeline-view-groups-set! v (inspect-list-labels l))))
  (pipeline-view-looked-set! v (now-ms)))

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

;; The last frames as bars, the newest at the right, against the tick;
;; frames that didn't reach the screen stand out.
(define (pipeline-draw-frames x y w h frames tick-ms)
  (fill-box x y w h 'bg-0)
  (let* ([per-ms (/ h (* 2 tick-ms))]
         [line (- (+ y h) (* tick-ms per-ms))])
    (let loop ([fs frames] [bx (- (+ x w) 3)])
      (when (and (pair? fs) (>= bx x))
        (let ([high (min h (max 1 (* per-ms (/ (car (car fs)) 1000))))])
          (fill-box bx (- (+ y h) high) 2 high
                    (if (list-ref (car fs) 5) 'chart-1 'red)))
        (loop (cdr fs) (- bx 3))))
    (fill-box x line w 1 (alpha 'text 0.4))))

(define (pipeline-card-lines v stage)
  (case stage
    [(lists)
     (let* ([l (pipeline-view-shown v)] [frames (inspect-frames 1)])
       (list (format "~a records, ~a KB" (inspect-list-count l)
                     (quotient (inspect-list-bytes l) 1024))
             (format "~a drew, ~a runs"
                     (length (inspect-list-labels l))
                     (if (null? frames) 0 (cadddr (car frames))))))]
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
          (pipeline-view-image v)))))

(define (pipeline-draw v win w h)
  (let* ([ui (pipeline-view-ui v)] [pad (ui-pad)] [gap (ui-gap)]
         [lh (font-line-height 'ui)]
         [card-h (+ 12 (* 3 lh))]
         [frames-h 56]
         [side (min 360 (quotient w 2))]
         [screen-w (- side pad)]
         [screen-h (exact (round (* screen-w (/ *canvas-ph* *canvas-pw*))))]
         [top (+ pad card-h gap)]
         [bottom (- h pad frames-h gap)]
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
                      v (and (< f 1) (exact (floor (* f n)))))))
        (ui-checkbox ui '(pipeline hold) sx (+ sy lh 2 (ui-slider-height) gap)
                     screen-w ch "Hold this frame" (pipeline-view-held? v)
                     (lambda (on?) (pipeline-view-held?-set! v on?)))))
    (pipeline-draw-frames pad (- h pad frames-h) (- w pad pad) frames-h
                          (inspect-frames frame-ring-rows)
                          (/ 1000.0 60))
    (ui-end! ui w h)))

(define-app (pipeline) "Pipeline"
  (let ([existing (find-window 'pipeline)])
    (if existing
        (begin (focus-window! existing) existing)
        (let* ([ui (make-ui)]
               [v (make-pipeline-view ui 'lists (inspect-list) #f 0 '() #f #f
                                      #f #f)])
          (pipeline-look! v)
          (apply open-window "Pipeline"
                 'size '(980 . 640)
                 'min-size '(640 . 420)
                 'state v
                 'draw (lambda (win w h) (pipeline-draw v win w h))
                 'close (lambda (win)
                          (let ([image (pipeline-view-image v)])
                            (when image (inspect-preview-free! image))
                            (pipeline-view-image-set! v #f)))
                 (append
                  (ui-handlers ui)
                  (list 'tick
                        (lambda (win)
                          (ui-tick ui win)
                          (when (> (- (now-ms) (pipeline-view-looked v))
                                   pipeline-period-ms)
                            (pipeline-look! v)
                            (when (pipeline-view-image v)
                              (inspect-preview!
                               (pipeline-view-image v)
                               (or (pipeline-view-upto v)
                                   (inspect-list-count
                                    (pipeline-view-shown v)))))
                            (invalidate! win))))))))))
