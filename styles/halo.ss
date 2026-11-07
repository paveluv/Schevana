;;; styles/halo.ss — the Halo window style.
;;; Calm, floating cards with no title bar. The title is a small pill
;;; threaded on the card's top edge, like a fieldset's legend breaking its
;;; border; the buttons are three dots in a second pill at the right that
;;; bloom into glyphs under the mouse. Focus is the halo: a thin ring
;;; running from accent to accent-2 around the card, with a faint glow
;;; around card and pills alike. Other cards keep a hairline and recede.

;; Even, so the line through the pills' middle stays crisp.
(define (halo-pill-height)
  (* 2 (exact (ceiling (/ (max 20 (+ (font-line-height 'ui) 6)) 2)))))

(define (halo-top) (max (title-height) (+ (halo-pill-height) 4)))

;; The card starts at the pills' middle. Maximized, it fills the window
;; and the pills drop to the middle of the top inset.
(define (halo-edge win)
  (if (maximized? win) 0 (quotient (halo-pill-height) 2)))

(define (halo-drop win)
  (if (maximized? win) (quotient (- (halo-top) (halo-pill-height)) 2) 0))

(define (halo-insets win) (values 0 (halo-top) 0 0))

;; The glow's strokes reach 5 pixels past the card (none when maximized).
(define (halo-bleed win) (if (maximized? win) 0 5))

;; Small enough that the content's top corners stay inside the card.
(define (halo-radius win)
  (if (maximized? win)
      0
      (min (theme 'corner-radius) (- (halo-top) (halo-edge win)))))

(define (halo-margin win) (max 12 (+ (halo-radius win) 7)))

;; Three cells in a pill at the right, with 2 pixels to spare at its ends.
;; The cells are an odd width, so that their middles are pixels' middles,
;; where the glyphs' 1-pixel lines are crisp.
(define (halo-regions win)
  (let* ([ph (halo-pill-height)] [c (- ph 3)]
         [x0 (- (window-w win) (halo-margin win) (* 3 c) 2)])
    (map (lambda (kind i) (list kind (+ x0 (* i c)) (halo-drop win) c ph))
         '(minimize maximize close) '(0 1 2))))

;; The pills as ((x width title) ...) in window coordinates: the title's,
;; unless the window is too narrow for it, and the buttons'. The title's
;; ends at most two thirds of the way across, so that some of the edge
;; shows between the pills however long the title is.
(define (halo-pills win)
  (let* ([ph (halo-pill-height)] [tx (halo-margin win)]
         [bx (- (cadr (car (halo-regions win))) 2)]
         [buttons (list bx (- (window-w win) tx bx) #f)]
         [title (text-fit (window-title win)
                          (- (min bx (* 2/3 (window-w win))) tx ph 4) 'ui)]
         [tw (+ (text-width title 'ui) ph -2)])
    (if (or (> (+ tx tw 6) bx) (string=? title ""))
        (list buttons)
        (list (list tx tw title) buttons))))

;; Each box (x y w h r) stroked by a line lw wide.
(define (halo-stroke-boxes boxes color lw)
  (for-each (lambda (b)
              (stroke-box (car b) (cadr b) (caddr b) (cadddr b) color lw
                          (car (cddddr b))))
            boxes))

;; The pills' outlines at y, as halo-stroke-boxes' boxes (x y w h r),
;; each grown by d at every side: a line 2d wide stroked inside one runs
;; along the pill's edge.
(define (halo-pill-boxes pills x y d)
  (map (lambda (p)
         (list (- (+ x (car p)) d) (- y d) (+ (cadr p) d d)
               (+ (halo-pill-height) d d) (/ (halo-pill-height) 2)))
       pills))

;; The halo's ink, accent at the top left turning to accent-2 at the
;; bottom right, at opacity a; unfocused, the plain border color.
(define (halo-ink x y w h focused? a)
  (apply linear-gradient x y (+ x w) (+ y h)
         (map (lambda (key) (alpha (if focused? key 'window-border) a))
              '(accent accent-2))))

;; ×, −, or two corners of a frame: pointing out to maximize, in to
;; restore. (x, y) is a pixel's middle.
(define (halo-glyph win kind x y ink)
  (define (line . points) (draw-polyline points ink 1.25))
  (case kind
    [(close) (ui-draw-glyph (- x 3.5) (- y 3.5) 7 7
                            (list (cons 'ink ink) '(width . 1.25)) 'close)]
    [(minimize) (line (cons (- x 3.5) y) (cons (+ x 3.5) y))]
    [else
     (let ([d (if (maximized? win) 1 3)] [a (if (maximized? win) -3 3)])
       (for-each (lambda (k)
                   (let ([px (- x (* k d))] [py (- y (* k d))] [a (* k a)])
                     (line (cons (+ px a) py) (cons px py) (cons px (+ py a)))))
                 '(1 -1)))]))

(define (halo-draw-under win x y w h focused? hover pressed)
  (let ([e (halo-edge win)] [r (halo-radius win)] [pills (halo-pills win)])
    (window-shadow win x (+ y e) w (- h e) r focused?)
    ;; the glow: strokes around card and pills together, fading outward;
    ;; the card and the pills then cover their inner halves
    (when (and focused? (not (maximized? win)))
      (for-each (lambda (lw)
                  (let ([d (/ lw 2)])
                    (halo-stroke-boxes
                     (cons (list (- x d) (- (+ y e) d) (+ w lw) (+ (- h e) lw)
                                 r)
                           (halo-pill-boxes pills x y d))
                     (halo-ink x y w h #t 0.05) lw)))
                '(2 4 6 8 10)))
    (fill-box x (+ y e) w (- h e) (window-bg win) r)))

(define (halo-draw-over win x y w h focused? hover pressed)
  (let* ([ph (halo-pill-height)] [lw (if focused? 1.5 1)]
         [e (halo-edge win)] [pills (halo-pills win)]
         [top (+ y (halo-drop win) (/ lw 2))]
         [mid (+ top (/ ph 2))]   ; the card's top edge
         [gy (+ (floor mid) 1/2)]   ; the glyphs' row
         [bloom? (memq hover '(close minimize maximize))]
         [ink (halo-ink x y w h focused? 1)])
    ;; the card's edge: maximized, a line lw high across the top
    (if (maximized? win)
        (fill-box x (- mid (/ lw 2)) w lw ink)
        (stroke-box x (+ y e) w (- h e) ink lw (halo-radius win)))
    (for-each (lambda (p)
                (fill-box (+ x (car p)) top (cadr p) ph (window-bg win)
                          (/ ph 2))
                (when (caddr p)
                  (text-draw-centered (+ x (car p)) top (cadr p) ph (caddr p)
                                      (if focused? 'title-text 'title-text-dim)
                                      'ui)))
              pills)
    (halo-stroke-boxes (halo-pill-boxes pills x top (/ lw 2)) ink lw)
    (for-each
     (lambda (b)
       (let ([kind (car b)] [gx (+ x (cadr b) (/ (cadddr b) 2))]
             [down? (eq? pressed (car b))] [close? (eq? (car b) 'close)])
         (cond
           [(not bloom?)
            (fill-circle gx gy 2 (if focused? 'text-dim 'text-faint))]
           [(eq? hover kind)
            (fill-circle gx gy (- (/ ph 2) 4)
                         (cond [(not close?) (alpha 'text (if down? 0.22 0.12))]
                               [down? (mix 'button-close 'text 0.3)]
                               [else 'button-close]))
            (halo-glyph win kind gx gy
                        (if close?
                            (color-readable-on 'button-close)
                            'title-text))]
           [else (halo-glyph win kind gx gy 'text-dim)])))
     (halo-regions win))))

;; Scroll bars show while the pointer is over what they scroll.
(define-style halo "Halo"
  'scrollbar-show 'hover
  'frame-insets 'halo-insets
  'frame-bleed 'halo-bleed
  'frame-radius 'halo-radius
  'frame-regions 'halo-regions
  'frame-under 'halo-draw-under
  'frame-over 'halo-draw-over)
