;;; taskbar.ss — the bar at the bottom: a button for each window (left
;;; focuses or minimizes, middle closes, right opens its menu) and a hint.
;;; A style may make it another bar, with its areas, drawing and tick
;;; (Genera's who line).

(theme-default! 'taskbar-height-min
                (theme-rule (exact (round (+ (font-line-height 'ui) 13)))))
;; (in the bars' place, as the bar is drawn)
(define (taskbar-height)
  (with-place 'bar
    (lambda () (chrome-height 'taskbar-height 'taskbar-height-min))))

(define (taskbar-box)
  (let ([h (taskbar-height)]) (values 0 (- (screen-h) h) (screen-w) h)))

;; The hint at the right while the buttons leave it room, and a button for
;; each window, left to right: ((hint x y w h) (window x y w h) ...).
(define-part (taskbar-areas)
  (let* ([w (screen-w)] [h (taskbar-height)] [y0 (- (screen-h) h)]
         [ws (sort (lambda (a b) (< (window-id a) (window-id b))) *windows*)]
         [n (length ws)]
         [button-w (lambda (hint-w)
                     (if (zero? n)
                         0
                         (min 210 (/ (- w 16 hint-w (* 6 (- n 1))) n))))]
         ;; the hint gives way when the buttons would be too narrow for their
         ;; titles
         [hint-w (let ([hw (+ 24 (text-width taskbar-hint 'ui-small))]
                       [want (min 210 (+ 48 (text-widest (map window-title ws)
                                                         'ui)))])
                   (if (>= (button-w hw) want) hw 0))]
         [bw (button-w hint-w)])
    (append (if (> hint-w 0) (list (list 'hint (- w hint-w) y0 hint-w h)) '())
            (map (lambda (win i) (list win (+ 8 (* i (+ bw 6))) y0 bw h))
                 ws (iota n)))))

(define taskbar-hint "F1 apps  ·  Ctrl+Tab switch  ·  right-click desktop")

(define-part (draw-taskbar)
  (with-place 'bar
    (lambda ()
      (let* ([w (screen-w)] [h (taskbar-height)] [y0 (- (screen-h) h)]
             [lh (font-line-height 'ui)])
        (fill-box 0 y0 w h (alpha 'panel 0.94))
        (draw-line 0 (+ y0 0.5) w (+ y0 0.5) (alpha 'panel-text 0.12))
        (for-each
         (lambda (a)
           (apply
            (lambda (what x y bw h)
              (if (eq? what 'hint)
                  (draw-text x (+ y (/ (- h (font-line-height 'ui-small)) 2))
                             taskbar-hint 'panel-dim 'ui-small)
                  (let ([focused? (eq? what *focus*)]
                        [hover? (equal? *hover* (list 'surface 'taskbar what))]
                        [min? (not (visible? what))]
                        [color (app-color (window-app what))])
                    (when (or focused? hover?)
                      (fill-box x (+ y 5) bw (- h 10)
                                (if focused?
                                    'panel-hover
                                    (alpha 'panel-hover 0.6))
                                6))
                    (when focused?
                      (fill-box (+ x 12) (- (+ y h) 6) (- bw 24) 2
                                'panel-accent 1))
                    (fill-circle (+ x 15) (+ y (/ h 2)) 4
                                 (if min? (alpha color 0.35) color))
                    (draw-text (+ x 27) (+ y (/ (- h lh) 2))
                               (text-fit (window-title what) (- bw 36) 'ui)
                               (if min? 'panel-dim 'panel-text) 'ui))))
            a))
         (taskbar-areas))))))

(define (taskbar-at x y)
  (and (>= y (- (screen-h) (taskbar-height)))
       (bar-at (with-place 'bar taskbar-areas) x y)))

(define (taskbar-mouse kind what x y button clicks)
  (bar-mouse (with-place 'bar taskbar-areas) kind what x y button clicks))

(define (taskbar-doc what)
  (cond [(window? what)
         '((L . "Focus or minimize") (M . "Close") (R . "Window menu"))]
        [(eq? what 'windows) '((L . "Choose a window"))]
        [else '()]))

;; Before each frame, t when it shows: the built-in bar shows nothing that
;; changes by itself.
(define-part (taskbar-frame t) (void))

(define-surface taskbar 10
  'draw 'draw-taskbar 'box 'taskbar-box 'at 'taskbar-at
  'mouse 'taskbar-mouse 'frame 'taskbar-frame 'doc 'taskbar-doc)
(define-strip taskbar 'bottom 'taskbar-height)
