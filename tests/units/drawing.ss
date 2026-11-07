;;; tests/units/drawing.ss — the drawing layer: measuring, the host window,
;;; invalidation.

;;; measuring: arithmetic on a font's tables, with no device

(define (measured)
  (list (text-width "Schevana λ" 'ui)
        (text-width "(define x 1)" 'mono)
        (font-metrics (make-font* "sans" 13))
        (font-metrics (make-font* "monospace" 11 'bold))))

(check "text-width and font-metrics work before the first frame"
       (and (zero? *frame-ms*)
            (> (text-width "Schevana" 'ui) 0)
            (> (font-line-height 'ui) 0)))

(steps 2)

(define (stray-drawing!)
  (fill-box 0 0 600 400 'red)
  (draw-text 20 20 "stray" 'text 'big)
  (draw-shadow 100 100 300 200 9 14)
  (pixmap-draw (make-pixmap 2 2 #xff0000) 10 10 50 50))

(check "stray drawing between frames leaves the screen untouched"
       (let ([before (canvas-bytes)])
         (stray-drawing!)
         (bytevector=? before (canvas-bytes))))

(check "measuring doesn't depend on the scale (100, 125, 150, 200%), nor on \
        where it happens: in a half-scale style preview, it is the same"
       (let* ([at-100 (measured)]
              [same?
               (for-all
                (lambda (s)
                  (canvas-create! 1280 800 s)
                  (and (equal? at-100 (measured))
                       (equal? at-100
                               (begin
                                 (rec-begin! *canvas-ratio*)
                                 (draw-style-preview 'genera 0 0 200 150 0.5)
                                 (with-scale (0.5) (measured))))))
                '(1 5/4 3/2 2))])
         (canvas-create! 1280 800 *host-scale*)
         same?))
(steps 1)

(set-theme! 'scale 200)
(steps 1)
(check "stray drawing at 200% leaves the screen untouched"
       (let ([before (canvas-bytes)])
         (stray-drawing!)
         (bytevector=? before (canvas-bytes))))
(set-theme! 'scale 0)
(steps 1)

;;; ------------------------------------------------------------------
;;; host window

;; (w h scale ratio) -> window units: logical size × scale / pixel ratio.
(check
 "the host window opens at the logical size times the scale, in window units"
 (equal? (map (lambda (args)
                (call-with-values (lambda () (apply host-window-size args))
                                  list))
              '((1280 800 1 1) (1280 800 2 1) (1280 800 2 2) (1280 800 3/2 2)
                (1280 800 1 2) (1024 640 5/4 1) (1281 801 7/4 2)))
         '((1280 800) (2560 1600) (1280 800) (960 600) (640 400) (1280 800)
           (1121 701))))

;;; invalidation

(let ([w (open-window "Dirty" 'size '(200 . 100))])
  (define (asks? thunk) (set! *dirty* #f) (thunk) *dirty*)
  (check "(invalidate!), (invalidate! #f), (invalidate! win), \
          (invalidate! win x y w h) and (request-frame!) ask for a frame"
         (for-all asks? (list (lambda () (invalidate!))
                              (lambda () (invalidate! #f))
                              (lambda () (invalidate! w))
                              (lambda () (invalidate! w 1 2 3 4))
                              request-frame!)))
  (let ([plain *styles*]
        [bleed-of (lambda (w)   ; how far w's extent reaches past its frame
                    (let-values ([(x y ew eh) (window-extent w)])
                      (- (window-x w) x)))])
    (define-style wide "Wide" 'frame-bleed (lambda (win) 5))
    (override! 'shadow 0)
    (window-set! w 'window-style 'wide)
    (let ([wide (bleed-of w)])
      (window-set! w 'window-style 'mac)
      (override! 'shadow -6)
      (let ([narrow (bleed-of w)])
        (override! 'shadow)
        (set! *styles* plain)
        (check (format "a style's 'bleed widens its windows' extent (~a); \
                        nothing makes it smaller than the frame (~a)"
                       wide narrow)
               (and (= wide 5) (= narrow 0))))))
  (window-call w 'key #\a '())   ; no key handler: nothing to see
  (window-on! w 'key (lambda (win key mods) (void)))
  (check "input to a handler asks for a frame"
         (asks? (lambda () (window-call w 'key #\a '()))))
  (window-on! w 'key (lambda (win key mods) (current-window)))
  (check "handlers run with (current-window) set"
         (and (eq? w (window-call w 'key #\a '())) (not (current-window))))
  (close-window! w))
