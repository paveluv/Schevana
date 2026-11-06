;;; tests/units/drawing.ss — the drawing layer: the measuring context, the host
;;; window, invalidation.

;;; measuring context

;; What text measures with *cr* on the canvas itself, as before.
(define (measured-on-canvas thunk)
  (let ([cr (cairo-create *canvas*)])
    (cairo-scale cr *scale* *scale*)
    (let ([v (fluid-let ([*cr* cr]) (thunk))])
      (cairo-destroy cr)
      v)))

(define (measures-like-canvas?)
  (let ([measure (lambda ()
                   (list (text-width "Schevana λ" 'ui)
                         (text-width "(define x 1)" 'mono)
                         (font-metrics (make-font* "sans" 13))
                         (font-metrics (make-font* "monospace" 11 'bold))))])
    (equal? (measure) (measured-on-canvas measure))))

(check "before the first frame *cr* is the measuring context"
       (and (zero? *frame-ms*) (not (eqv? *measure-cr* 0))
            (eqv? *cr* *measure-cr*) (= (cairo-matrix-xx *cr*) *scale*)))
(check
 "text-width and font-metrics work before the first frame, as on the canvas"
 (and (> (text-width "Schevana" 'ui) 0) (> (font-line-height 'ui) 0)
      (measures-like-canvas?)))

(steps 2)

(define (stray-drawing!)
  (fill-rect 0 0 600 400 'red)
  (draw-text 20 20 "stray" 'text 'big)
  (draw-shadow 100 100 300 200 9 14)   ; shadow
  (pixmap-draw (make-pixmap 2 2 #xff0000) 10 10 50 50))

(check "stray drawing between frames leaves the canvas untouched"
       (let ([before (canvas-bytes)])
         (stray-drawing!)
         (bytevector=? before (canvas-bytes))))

(set-theme! 'scale 200)
(steps 1)
(check "after a scale change *cr* measures at the new scale"
       (and (= *scale* 2.0) (eqv? *cr* *measure-cr*)
            (= (cairo-matrix-xx *cr*) 2.0)))
(check "text-width and font-metrics work after a scale change, as on the canvas"
       (and (> (text-width "Schevana" 'ui) 0) (measures-like-canvas?)))
(check "stray drawing at 200% leaves the canvas untouched"
       (let ([before (canvas-bytes)])
         (stray-drawing!)
         (bytevector=? before (canvas-bytes))))
(set-theme! 'scale 0)
(steps 1)

(check "a canvas context left in *cr* (code from before a reload) is replaced"
       (begin
         (set! *cr* (cairo-create *canvas*))
         (canvas-create! 1280 800 *scale*)
         (and (eqv? *cr* *measure-cr*) (measures-like-canvas?))))
(steps 1)

;; Measuring never depends on *cr*. (Once the fonts were made again, the
;; first measurement of 'mono could happen in Settings' Genera preview,
;; drawn at half scale, and the REPL's characters overlapped from then on.)
;; mono's char width and text-widths in 'mono and Genera's label font when
;; first measured inside (measure-in measure), on a fresh context scaled
;; like the canvas.
(define (first-measured-in measure-in)
  (fonts-rescaled!)
  (let* ([img (cairo-image-surface-create CAIRO_FORMAT_ARGB32 400 300)]
         [cr (cairo-create img)])
    (cairo-scale cr *scale* *scale*)
    (let ([v (fluid-let ([*cr* cr])
               (measure-in
                (lambda ()
                  (list (font-char-width 'mono)
                        (text-width "(set-theme! 'accent #xff9e64)" 'mono)
                        (text-width "Dynamic Lisp Listener" 'ui-italic)))))])
      (cairo-destroy cr)
      (cairo-surface-destroy img)
      v)))

(check "the first measurement of a font, in a half-scale style preview, is \
        the canvas's (100, 125, 150, 200%)"
       (let ([results
              (map (lambda (s)
                     (canvas-create! 1280 800 s)
                     (let ([normal (first-measured-in
                                    (lambda (measure) (measure)))]
                           [preview (first-measured-in
                                     (lambda (measure)
                                       ;; its label is in 'ui-italic
                                       (draw-style-preview
                                        'genera 0 0 200 150 0.5)
                                       (call-with-scale 0.5 measure)))])
                       (list s normal preview)))
                   '(1 1.25 1.5 2))])
         (canvas-create! 1280 800 *host-scale*)
         (fonts-rescaled!)
         (printf "  ~s\n" results)
         (for-all (lambda (r) (equal? (cadr r) (caddr r))) results)))
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
  (let-values ([(ex ey ew eh) (window-extent w)])
    (define (asked thunk) (set! *dirty* #f) (thunk) *dirty*)
    (check "(invalidate! win) and (invalidate! win x y w h) ask for its \
            extent; areas asked for make their bounding box, and the \
            whole screen holds them all"
           (and (equal? (asked (lambda () (invalidate! w)))
                        (list ex ey (+ ex ew) (+ ey eh)))
                (equal? (asked (lambda () (invalidate! w -5 10 30 500)))
                        (list ex ey (+ ex ew) (+ ey eh)))
                (equal? (asked (lambda ()
                                 (request-frame! 10 20 30 40)
                                 (request-frame! 100 5 10 10)))
                        '(10 5 110 60))
                (eq? (asked (lambda () (request-frame!) (invalidate! w)))
                     #t))))
  (let ([plain *styles*]
        [bleed-of (lambda (w)   ; how far w's extent reaches past its frame
                    (let-values ([(x y ew eh) (window-extent w)])
                      (- (window-x w) x)))])
    (define-style wide "Wide" 'frame-bleed (lambda (win) 5))
    (override! 'shadow 0)   ; shadow
    (window-set! w 'window-style 'wide)
    (let ([wide (bleed-of w)])
      (window-set! w 'window-style 'mac)
      (override! 'shadow -6)   ; shadow
      (let ([narrow (bleed-of w)])
        (override! 'shadow)   ; shadow
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
