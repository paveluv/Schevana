;;; (demo boids3d rules-window) — Boids 3D's rules window. Like Boids'
;;; rules window, but with no threads slider (the GPU steps the flock) and
;;; with a switch for riding a timer: a slider for the count and for each
;;; rule, and buttons for what the keys do. It reads and sets the flock
;;; window's properties, so it shows them as they are, whoever changed
;;; them.

(library (demo boids3d rules-window)
  (export boids3d-open-rules)
  (import (chezscheme)
          (schevana core)
          (schevana kits text)
          (schevana kits ui)
          (demo boids3d rules)
          (demo boids3d shaders)
          (demo boids3d flock))

  (define (boids3d-setting-label key)
    (list->string (map (lambda (c) (if (char=? c #\-) #\space c))
                       (string->list (symbol->string key)))))

  (define (boids3d-weight? range) (pair? (cdddr range)))

  ;; Where v sits on range's slider, from 0 to 1 (boids3d-slider-t), and
  ;; back (boids3d-slider-value); a weight's slider follows a cube, as in
  ;; Boids.
  (define (boids3d-slider-t range v)
    (let ([t (/ (- v (cadr range)) (- (caddr range) (cadr range)))])
      (if (boids3d-weight? range) (expt (max t 0.0) 1/3) t)))

  (define (boids3d-slider-value range t)
    (+ (cadr range)
       (* (- (caddr range) (cadr range))
          (if (boids3d-weight? range) (* t t t) t))))

  (define (boids3d-readout range v)
    (case (car range)
      [(min-speed max-speed) (format "~,1f" v)]
      [(view-angle blocker-cone) (format "~a°" (exact (round v)))]
      [else (if (boids3d-weight? range)
                (format "~,4f" v)
                (format "~a" (exact (round v))))]))

  (define (boids3d-label-width)
    (+ 12 (text-widest (cons "birds"
                             (map (lambda (r) (boids3d-setting-label (car r)))
                                  boids3d-ranges))
                       'ui)))

  (define (boids3d-readout-width) (+ 12 (text-widest '("0.0000" "4096") 'ui)))

  (define boids3d-buttons
    '("Randomize (R)"
      "Defaults (D)"
      "Scatter (S)"))

  (define boids3d-ride-label
    "Fly on while hidden: steps on a timer, not frames")

  (define (boids3d-button-width)
    (apply max (map (lambda (label)
                      (let-values ([(w h) (ui-button-size label #f)]) w))
                    boids3d-buttons)))

  ;; Returns the rules window's content size: room for its rows, with
  ;; sliders 140 wide, for three buttons as wide as the widest one, and for
  ;; the timer's checkbox.
  (define (boids3d-rules-size)
    (let ([pad (ui-pad)] [gap (ui-gap)] [sh (ui-slider-height)])
      (values (+ pad pad
                 (max (+ (boids3d-label-width) 140 (boids3d-readout-width))
                      (+ (* 3 (boids3d-button-width)) (* 2 gap))
                      (let-values ([(cw ch) (ui-checkbox-size
                                             boids3d-ride-label)])
                        cw)))
              (+ pad (+ sh gap) (+ (ui-control-height) gap)
                 (+ (ui-control-height) (* 3 gap))
                 (* (length boids3d-ranges) (+ sh gap))
                 gap (font-line-height 'ui-small) pad))))

  ;; Draws the rows, top to bottom: the count, the buttons, the switch for
  ;; riding a timer, a slider for each rule, and a hint. Returns the y
  ;; below them.
  (define (boids3d-draw-rules ui flock-win w)
    (let* ([pad (ui-pad)] [gap (ui-gap)] [sh (ui-slider-height)]
           [lw (boids3d-label-width)] [rw (boids3d-readout-width)]
           [rules (window-ref flock-win 'rules)]
           [n (window-ref flock-win 'count)])
      (define (row y id label t readout set . tip)
        (ui-draw-label pad y lw sh '(dim) label)
        (ui-slider ui id (+ pad lw) y (- w pad lw rw pad) t 0.0 1.0 set #f
                   'tip (and (pair? tip) (car tip)))
        (ui-draw-label (- w pad rw) y rw sh '(right) readout)
        (+ y sh gap))
      (let* ([y (row pad 'count "birds"
                     (/ (- n 10) (- boids3d-most 10.0))
                     (number->string n)
                     (lambda (t)
                       (boids3d-resize! flock-win
                         (exact (round (+ 10 (* t (- boids3d-most 10))))))))]
             [y (let ([bw (/ (- w pad pad gap gap) 3)] [ch (ui-control-height)])
                  (for-each (lambda (i label id act! tip)
                              (ui-button ui id (+ pad (* i (+ bw gap))) y bw ch
                                         label (lambda () (act! flock-win))
                                         'tip tip))
                            '(0 1 2) boids3d-buttons
                            '(randomize defaults scatter)
                            (list boids3d-randomize! boids3d-defaults!
                                  boids3d-scatter!)
                            '(#f "Rules that make a murmuration" #f))
                  (+ y ch gap))]
             [y (let ([ch (ui-control-height)])
                  (ui-checkbox ui 'ride pad y (- w pad pad) ch
                               boids3d-ride-label
                               (eq? (window-ref flock-win 'ride) 'timer)
                               (lambda (on?)
                                 (boids3d-set-ride!
                                  flock-win (if on? 'timer 'frames))))
                  (+ y ch (* 3 gap)))]
             [y (fold-left
                 (lambda (y range)
                   (let* ([key (car range)] [v (boids3d-rule rules key)])
                     (row y key (boids3d-setting-label key)
                          (boids3d-slider-t range v) (boids3d-readout range v)
                          (lambda (t)
                            (window-set! flock-win 'rules
                              (boids3d-set-rule (window-ref flock-win 'rules)
                                                key
                                                (boids3d-slider-value range
                                                                      t))))
                          (and (eq? key 'home)
                               "How hard a bird outside the ball of its space \
                                turns back to the middle"))))
                 y boids3d-ranges)])
        (ui-draw-label pad (+ y gap) (- w pad pad) (font-line-height 'ui-small)
                       '(hint) "h hides this window · space pauses")
        (+ y gap (font-line-height 'ui-small) pad))))

  ;; Opens the rules window for the flock in flock-win, beside it and above
  ;; it. The rules window belongs to the flock window: it is raised,
  ;; minimized and closed with it. Returns the rules window; on-close is
  ;; called when it closes. Its keys go to the flock window.
  (define (boids3d-open-rules flock-win on-close)
    (let ([ui (make-ui)]
          [shown #f])   ; the rules, the count and the ride it last drew
      (define (now-shown)
        (list (window-ref flock-win 'rules) (window-ref flock-win 'count)
              (window-ref flock-win 'ride)))
      (let-values ([(w h) (boids3d-rules-size)])
        (let ([win
               (apply open-window "Boids 3D — Rules"
                      'size (cons w h)
                      'pos (cons (+ (window-x flock-win) (window-w flock-win)
                                    12)
                                 (window-y flock-win))
                      'app #f
                      'above flock-win
                      'draw (lambda (win w h)
                              (set! shown (now-shown))
                              (ui-begin! ui)
                              (ui-draw-surface 0 0 w h '(page))
                              (boids3d-draw-rules ui flock-win w)
                              (ui-end! ui w h))
                      'close (lambda (win) (on-close))
                      (append
                       (ui-handlers ui 'key (lambda (win key mods)
                                              (window-call flock-win 'key key
                                                           mods)
                                              #t))
                       (list 'open (lambda (win) (window-frame-soon! win))
                             'frame (lambda (win t)
                                     (window-frame-soon! win)
                                     (ui-frame ui win)
                                     (let-values ([(w h) (boids3d-rules-size)])
                                       (boids3d-grow-to! win w h))
                                     (unless (equal? shown (now-shown))
                                       (invalidate! win))))))])
          (boids3d-keep-on-desktop! win)
          win))))

  ;; Grows win's content to at least w × h, keeping win on the desktop; it
  ;; never shrinks win.
  (define (boids3d-grow-to! win w h)
    (let-values ([(cw ch) (window-content-size win)])
      (when (and (or (> w cw) (> h ch)) (not (shaded? win)))
        (resize-window! win (max w cw) (max h ch))
        (boids3d-keep-on-desktop! win))))

  ;; Moves win left or up as far as it takes to stay on the desktop.
  (define (boids3d-keep-on-desktop! win)
    (let-values ([(dx dy dw dh) (desktop-rect)])
      (move-window! win
        (max dx (min (window-x win) (- (+ dx dw) (window-w win))))
        (max dy (min (window-y win) (- (+ dy dh) (window-h win))))))))
