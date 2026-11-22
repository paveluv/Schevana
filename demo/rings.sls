;;; (demo rings) — a program on drawing alone: no theme, no
;;; windows, no desktop. It hands the loop what a frame draws and where an
;;; event goes, the hooks the windows layer would fill, and runs: a shader
;;; of its own over the whole screen, a box that follows the mouse, a line
;;; of text. On the desktop (./desktop demo) the same, in
;;; a window.
;;;
;;;   ./rings-demo             a window
;;;   ./rings-demo --headless  a frame, read back and told

(library (demo rings)
  (export rings-main rings)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (schevana core))

  (library-layer apps)

  ;; Rings that spread with t from the middle.
  (define-paint (rings-paint x y)
    ([w fixnum]
     [h fixnum]
     [t flonum])
    (define (byte f) (flonum->fixnum (fl* 255.0 f)))
    (let* ([dx (fl- (fixnum->flonum x) (fl* 0.5 (fixnum->flonum w)))]
           [dy (fl- (fixnum->flonum y) (fl* 0.5 (fixnum->flonum h)))]
           [d (flsqrt (fl+ (fl* dx dx) (fl* dy dy)))]
           [ring (fl* 0.5 (fl+ 1.0 (flsin (fl- (fl* 0.05 d) t))))])
      (fxior (fxsll 255 24)
             (fxior (fxsll (byte (fl* 0.2 ring)) 16)
                    (fxior (fxsll (byte (fl* 0.5 ring)) 8) (byte ring))))))

  ;; The rings, w × h logical pixels at (0, 0) (pw × ph the screen's), a
  ;; box at (x, y) and the line of text, t seconds since began.
  (define (rings-draw w h pw ph x y began font)
    (fill-shader 0 0 w h rings-paint pw ph (/ (- (now-ms) began) 1000.0))
    (fill-box (- x 20) (- y 20) 40 40 #xffcc33 6)
    (draw-text 16 16 "drawing alone: no theme, no windows" #xffffff font))

  ;; On the desktop: the same in a window, the box following the pointer
  ;; over it, a frame after every frame.
  (define-app (rings) "Rings"
    (let ([began (now-ms)] [font (font "monospace" 16)])
      (open-window "Rings"
        'size '(480 . 320)
        'open (lambda (win) (window-frame-soon! win))
        'frame (lambda (win t) (window-frame-soon! win))
        'mouse-move (lambda (win x y)
                      (window-set! win 'box (cons x y)))
        'draw (lambda (win w h)
                (let ([box (or (window-ref win 'box) (cons 100 100))])
                  (rings-draw w h (round (* w *scale*)) (round (* h *scale*))
                              (car box) (cdr box) began font))))))

  ;; The pixel at (x, y) of bytes, the screen's, as (r g b).
  (define (rings-pixel bytes x y)
    (let ([at (* 4 (+ x (* y *canvas-pw*)))])
      (list (bytevector-u8-ref bytes (+ at 2))
            (bytevector-u8-ref bytes (+ at 1))
            (bytevector-u8-ref bytes at))))

  ;; The program, from the command line's args: the loop's hooks filled
  ;; here, so nothing of the windows layer runs. --headless draws a frame
  ;; and tells what it read back.
  (define (rings-main args)
    (let ([headless? (member "--headless" args)]
          [began (now-ms)]
          [font (font "monospace" 16)]
          [x 100]
          [y 100])
      (set! record-world!
        (lambda ()
          (rings-draw *canvas-w* *canvas-h* *canvas-pw* *canvas-ph* x y began
                      font)))
      (set! wm-event!
        (lambda (ev)
          (case (car ev)
            [(mouse-move)
             (set! x (cadr ev))
             (set! y (caddr ev))
             (request-frame!)]
            [(key-down) (when (eq? (cadr ev) 'escape) (quit!))]
            [else (void)])))
      (set! wm-tick! (lambda () (unless headless? (request-frame!))))
      (schevana-main (if headless? 'headless 'sdl) 640 400 #f
        (lambda ()
          (when headless?
            (after 100
              (lambda ()
                (screen-bytes-then
                 (lambda (bytes)
                   (printf "~a x ~a pixels; the box ~s, the middle ~s~n"
                           *canvas-pw* *canvas-ph*
                           (rings-pixel bytes 100 100)
                           (rings-pixel bytes (quotient *canvas-pw* 2)
                                        (quotient *canvas-ph* 2)))
                   (quit!)))))))))))
