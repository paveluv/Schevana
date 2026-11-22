;;; (schevana-demo window) — a program on the core: its libraries and
;;; nothing else. No desktop, no styles, none of the world's files: a
;;; surface fills the screen with a paint, a shader of its own, and a
;;; window draws text over it. On the desktop (./schevana-desktop --demo)
;;; the window is an app of its own.
;;;
;;;   ./schevana-window-demo             a window
;;;   ./schevana-window-demo --headless  a frame, read back and told
;;;   ... --headless --fork              on two threads

(library (schevana-demo window)
  (export window-demo-main window-demo window-demo-open)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (schevana core))

  (library-layer apps)

  ;; Bands that drift with t, redder to the right and bluer downward.
  (define-paint (window-demo-waves x y)
    ([w fixnum]
     [h fixnum]
     [t flonum])
    (define (byte f) (flonum->fixnum (fl* 255.0 f)))
    (let* ([u (fl/ (fixnum->flonum x) (fixnum->flonum w))]
           [v (fl/ (fixnum->flonum y) (fixnum->flonum h))]
           [band (fl* 0.5 (fl+ 1.0 (flsin (fl+ (fl* 20.0 (fl+ u v)) t))))])
      (fxior (fxsll 255 24)
             (fxior (fxsll (byte u) 16)
                    (fxior (fxsll (byte (fl* 0.6 band)) 8) (byte v))))))

  ;; The window, the demo's own, on whatever screen there is.
  (define (window-demo-open)
    (open-window "A window on the stack"
      'size '(320 . 96)
      'draw (lambda (win w h)
              (fill-box 0 0 w h 'bg-1)
              (draw-text 16 16 "(import (schevana core))" 'text 'mono))))

  (define-app (window-demo) "Window demo"
    (window-demo-open))

  ;; The pixel at (x, y) of bytes, the screen's, as (r g b).
  (define (window-demo-pixel bytes x y)
    (let ([at (* 4 (+ x (* y *canvas-pw*)))])
      (list (bytevector-u8-ref bytes (+ at 2))
            (bytevector-u8-ref bytes (+ at 1))
            (bytevector-u8-ref bytes at))))

  ;; The demo on a screen of its own, from the command line's args:
  ;; --headless draws a frame and tells what it read back; --fork, the
  ;; screen's thread and the world's, as with a window.
  (define (window-demo-main args)
    (let ([headless? (member "--headless" args)]
          [began (now-ms)])
      (schevana-main (if headless? 'headless 'sdl) 640 400 #f
        (lambda ()
          (define-surface window-demo -10
            'draw (lambda ()
                    (fill-shader 0 0 *canvas-w* *canvas-h* window-demo-waves
                                 *canvas-pw* *canvas-ph*
                                 (/ (- (now-ms) began) 1000.0)))
            ;; a frame after every frame: the bands drift
            'frame (lambda (t) (unless headless? (request-frame!))))
          (window-demo-open)
          (when headless?
            (after 100
              (lambda ()
                (screen-bytes-then
                 (lambda (bytes)
                   (printf "~a x ~a pixels; corners ~s ~s ~s~n"
                           *canvas-pw* *canvas-ph*
                           (window-demo-pixel bytes 0 0)
                           (window-demo-pixel bytes (- *canvas-pw* 1) 0)
                           (window-demo-pixel bytes 0 (- *canvas-ph* 1)))
                   (quit!)))))))
        (and (member "--fork" args) #t)))))
