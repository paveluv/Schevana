;;; (demo sketch) — freehand drawing. The strokes are plain Scheme data:
;;; (window-ref win 'strokes) returns ((color width (x . y) ...) ...).

(library (demo sketch)
  (export sketch)
  (import (chezscheme)
          (schevana core))

  (define sketch-palette '(text red orange yellow green teal accent accent-2))

  (define (sketch-toolbar-height)
    (max 34 (round (+ (font-line-height 'ui-small) 21))))

  ;; The app's icon: a pencil at the end of its line, its eraser up. It
  ;; draws on the core alone, in 24 units across the icon.
  (define (sketch-draw-icon x y s flags)
    (define (ink c)
      (if (or (memq 'dim flags) (memq 'disabled flags)) (alpha c 0.5) c))
    (with-translation (x y)
      (with-scale ((/ s 24))
        (draw-polyline '((2.5 . 20.5) (4.5 . 16.5) (6.5 . 19.5) (9 . 17))
                       (ink 'accent) 1.75)
        (fill-polygon '((10.27 . 12.61) (18.44 . 4.44) (21.56 . 7.56)
                        (13.39 . 15.73))
                      (ink 'orange))
        (fill-polygon '((17.38 . 5.5) (18.44 . 4.44) (21.56 . 7.56)
                        (20.5 . 8.62))
                      (ink 'red))
        (fill-polygon '((9 . 17) (10.27 . 12.61) (13.39 . 15.73))
                      (ink (alpha 'orange 0.45)))
        (fill-polygon '((9 . 17) (9.45 . 15.43) (10.57 . 16.55))
                      (ink 'text)))))

  (define-app (sketch) "Sketch" 'icon sketch-draw-icon
    (let ([color 'accent] [width 3] [current #f])
      (define (strokes win) (window-ref win 'strokes '()))
      (define (swatch-at x y)
        (and (< y (sketch-toolbar-height))
             (let ([i (exact (floor (/ (- x 10) 28)))])
               (and (>= i 0) (< i (length sketch-palette))
                    (list-ref sketch-palette i)))))
      (open-window "Sketch"
        'size '(560 . 380)
        'cursor 'crosshair
        'mouse-doc '((L . "Draw"))
        'strokes '()
        'draw (lambda (win w h)
                (fill-box 0 0 w h 'bg-1)
                (for-each (lambda (s) (draw-polyline (cddr s) (car s) (cadr s)))
                          (reverse (strokes win)))
                (when current
                  (draw-polyline (cddr current) (car current) (cadr current)))
                (let* ([bar-h (sketch-toolbar-height)] [cy (/ bar-h 2)]
                       [hint "drag to draw · c clears · 1-9 width"])
                  (fill-box 0 0 w bar-h 'bg-2)
                  (let loop ([cs sketch-palette] [x 10])
                    (unless (null? cs)
                      (fill-circle (+ x 12) cy 9 (car cs))
                      (when (eq? (car cs) color)
                        (stroke-circle (+ x 12) cy 12 'text 1.5))
                      (loop (cdr cs) (+ x 28))))
                  (draw-text (max (+ 20 (* 28 (length sketch-palette)))
                                  (- w (max 210
                                            (+ 14 (text-width hint
                                                              'ui-small)))))
                             (ceiling (/ (- bar-h (font-line-height 'ui-small))
                                         2))
                             hint 'text-faint 'ui-small)))
        'mouse-down (lambda (win x y button clicks)
                      (cond
                        [(swatch-at x y) => (lambda (c) (set! color c))]
                        [(eq? button 'left)
                         (set! current (list color width (cons x y)))])
                      (invalidate! win))
        'mouse-move (lambda (win x y)
                      (when current
                        (set-cdr! (cdr current)
                                  (cons (cons x y) (cddr current)))
                        (invalidate! win)))
        'mouse-up (lambda (win x y button)
                    (when current
                      (window-set! win 'strokes (cons current (strokes win)))
                      (set! current #f)))
        'key (lambda (win key mods)
               (cond
                 [(eqv? key #\c) (window-set! win 'strokes '())]
                 [(and (char? key) (char<=? #\1 key #\9))
                  (set! width
                        (* 1.5 (- (char->integer key) (char->integer #\0))))])
               (invalidate! win))))))
