;;; demo/window.ss — a program on the core: its libraries and nothing
;;; else. No desktop, no styles, none of the world's files: a surface
;;; fills the screen with a paint, a shader of its own, and a window
;;; draws text over it.
;;;
;;;   scheme --libdirs lib --program demo/window.ss             a window
;;;   scheme --libdirs lib --program demo/window.ss --headless  a frame,
;;;                                                read back and told
;;;   ... --headless --fork                        on two threads

(import (chezscheme) (schevana core))

;; Bands that drift with t, redder to the right and bluer downward.
(define-paint (demo-waves x y)
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

(define demo-began (now-ms))

(define (demo-draw)
  (fill-shader 0 0 *canvas-w* *canvas-h* demo-waves *canvas-pw* *canvas-ph*
               (/ (- (now-ms) demo-began) 1000.0)))

;; The pixel at (x, y) of bytes, the screen's, as (r g b).
(define (demo-pixel bytes x y)
  (let ([at (* 4 (+ x (* y *canvas-pw*)))])
    (list (bytevector-u8-ref bytes (+ at 2))
          (bytevector-u8-ref bytes (+ at 1))
          (bytevector-u8-ref bytes at))))

(define demo-headless? (member "--headless" (command-line-arguments)))
;; --fork: the screen's thread and the world's, as with a window
(define demo-fork? (member "--fork" (command-line-arguments)))

(schevana-main (if demo-headless? 'headless 'sdl) 640 400 #f
  (lambda ()
    (define-surface demo -10
      'draw demo-draw
      ;; a frame after every frame: the bands drift
      'frame (lambda (t) (unless demo-headless? (request-frame!))))
    (open-window "A window on the stack"
      'size '(320 . 96)
      'draw (lambda (win w h)
              (fill-box 0 0 w h 'bg-1)
              (draw-text 16 16 "(import (schevana core))" 'text 'mono)))
    (when demo-headless?
      (after 100
        (lambda ()
          (screen-bytes-then
           (lambda (bytes)
             (printf "~a x ~a pixels; corners ~s ~s ~s~n"
                     *canvas-pw* *canvas-ph*
                     (demo-pixel bytes 0 0)
                     (demo-pixel bytes (- *canvas-pw* 1) 0)
                     (demo-pixel bytes 0 (- *canvas-ph* 1)))
             (quit!)))))))
  demo-fork?)
