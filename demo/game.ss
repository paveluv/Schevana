;;; demo/game.ss — a program on drawing alone: no theme, no windows, no
;;; desktop. It imports the pieces below them, hands the loop what a frame
;;; draws and where an event goes, and runs: a shader of its own over the
;;; whole screen, a box that follows the mouse, a line of text.
;;;
;;;   scheme --libdirs lib --program demo/game.ss             a window
;;;   scheme --libdirs lib --program demo/game.ss --headless  a frame,
;;;                                              read back and told

(import (chezscheme)
        (schevana platform) (schevana processes) (schevana fonts)
        (schevana draw) (schevana pacer) (schevana loop))

;; Rings that spread with t from the middle.
(define-paint (game-rings x y)
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

(define game-began (now-ms))
(define game-font (font "monospace" 16))
(define game-x 100)
(define game-y 100)

;; A frame: colors are numbers here, and the font is a font.
(define (game-draw)
  (fill-shader 0 0 *canvas-w* *canvas-h* game-rings *canvas-pw* *canvas-ph*
               (/ (- (now-ms) game-began) 1000.0))
  (fill-box (- game-x 20) (- game-y 20) 40 40 #xffcc33 6)
  (draw-text 16 16 "drawing alone: no theme, no windows" #xffffff
             game-font))

(define (game-event ev)
  (case (car ev)
    [(mouse-move)
     (set! game-x (cadr ev))
     (set! game-y (caddr ev))
     (request-frame!)]
    [(key-down) (when (eq? (cadr ev) 'escape) (quit!))]
    [else (void)]))

;; The pixel at (x, y) of bytes, a frame's, as (r g b).
(define (game-pixel bytes x y)
  (let ([at (* 4 (+ x (* y *canvas-pw*)))])
    (list (bytevector-u8-ref bytes (+ at 2))
          (bytevector-u8-ref bytes (+ at 1))
          (bytevector-u8-ref bytes at))))

(define game-headless? (member "--headless" (command-line-arguments)))

(set! *frame-drawing* game-draw)
(set! *loop-event* game-event)
;; a frame after every frame: the rings spread
(set! *pacer-turn* (lambda () (unless game-headless? (request-frame!))))

(loop-main (if game-headless? 'headless 'sdl) 640 400 #f
  (lambda ()
    (when game-headless?
      (after 100
        (lambda ()
          (screen-bytes-then
           (lambda (bytes)
             (printf "~a x ~a pixels; the box ~s, the middle ~s~n"
                     *canvas-pw* *canvas-ph*
                     (game-pixel bytes 100 100)
                     (game-pixel bytes (quotient *canvas-pw* 2)
                                 (quotient *canvas-ph* 2)))
             (quit!))))))))
