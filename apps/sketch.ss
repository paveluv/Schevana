;;; apps/sketch.ss — freehand drawing. Strokes are plain Scheme data:
;;; (window-ref win 'strokes) => ((color width (x . y) ...) ...)

(app-requests window draw)

(define sketch-palette '(text red orange yellow green teal accent accent-2))

(define (sketch-toolbar-height)
  (max 34 (round (+ (font-line-height 'ui-small) 21))))

(define-app (sketch) "Sketch"
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
                                          (+ 14 (text-width hint 'ui-small)))))
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
                      (set-cdr! (cdr current) (cons (cons x y) (cddr current)))
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
             (invalidate! win)))))
