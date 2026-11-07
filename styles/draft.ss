;;; styles/draft.ss — the Draft window style.
;;; Every window is a technical drawing of itself: a fine outline, and
;;; along its top a dimension line from the left edge to the title block,
;;; with the title and the window's live size in logical pixels in a gap
;;; at its middle, "REPL · 662 × 470"; resize the window and its dimension
;;; follows. The buttons are the title block, the boxed table in the corner
;;; of a drawing, its top and right sides the outline's. No title bar
;;; fill: the band is the sheet's margin. One ink for everything, as on
;;; paper: the accent while the window has the focus, faded while not.

(define draft-arrow 8)   ; an arrowhead's length; it is 5 pixels wide
(define draft-pad 6)     ; between the dimension line and its text

;; The band on top. Odd, so that the dimension line runs through its
;; middle row, with the block's cells as tall above it as below.
(define (draft-band)
  (let ([t (title-height)]) (if (even? t) (+ t 1) t)))

;; A cell of the title block. Even, so that its inside is odd and a
;; glyph's 1-pixel lines fall on its middle pixel.
(define (draft-cell) (max 20 (* 2 (round (* 2/5 (title-height))))))

;; A 1-pixel outline, none at the screen's edges.
(define (draft-edge win) (if (maximized? win) 0 1))
(define (draft-insets win)
  (let ([e (draft-edge win)]) (values e (draft-band) e e)))

;; Where the title block's left rule is, in the window.
(define (draft-block-x win) (- (window-w win) 1 (* 3 (draft-cell))))

(define (draft-regions win)
  (let ([bx (draft-block-x win)] [c (draft-cell)] [b (draft-band)])
    (map (lambda (kind i) (list kind (+ bx (* i c)) 0 c b))
         '(minimize maximize close) '(0 1 2))))

;; The baseline that centers the title's capitals on the line through cy.
(define (draft-baseline cy)
  (let-values ([(l top w h) (text-ink "H" 'title)])
    (+ cy (/ (- top) 2))))

;; The dimension's text in room, as (values title size): both where they
;; fit, else the title cut to fit, else nothing: the line reads better
;; unbroken than cut by a stub such as "A …". The title comes first.
(define (draft-label win room)
  (let* ([title (window-title win)]
         [size (format "~a~a × ~a" (if (string=? title "") "" " · ")
                       (exact (round (window-w win)))
                       (exact (round (window-h win))))]
         [cut (text-fit title room 'title)])
    (cond [(<= (+ (text-width title 'title) (text-width size 'ui)) room)
           (values title size)]
          [(or (string=? cut title) (> (string-length cut) 5))
           (values cut "")]
          [else (values "" "")])))

;; An arrowhead with its tip at (x, y) and its base dir lengths away.
(define (draft-arrowhead x y dir ink)
  (let ([bx (+ x (* dir draft-arrow))])
    (fill-polygon `((,x . ,y) (,bx . ,(- y 5/2)) (,bx . ,(+ y 5/2))) ink)))

;; A button's mark, 2k + 1 pixels across around the middle of the pixel
;; at (cx, cy), in 1-pixel lines like the rest of the drawing (the ×'s
;; from pixel middle to pixel middle).
(define (draft-glyph win kind cx cy k ink)
  (let ([flags (list (cons 'ink ink))])
    (if (eq? kind 'close)
        (ui-draw-glyph (- cx k) (- cy k) (* 2 k) (* 2 k) flags 'close)
        (ui-draw-glyph (- cx k 1/2) (- cy k 1/2) (+ k k 1) (+ k k 1) flags
                       (ui-frame-glyph win kind)))))

;; The title block: a box the band's height, ruled into cells. The cell
;; under the mouse lights in the accent, even on an unfocused window.
(define (draft-block win x y hover pressed ink)
  (let ([c (draft-cell)] [b (draft-band)])
    (stroke-box (+ x (draft-block-x win)) y (+ 1 (* 3 c)) b ink)
    (for-each
     (lambda (bt)
       (let* ([kind (car bt)] [cx (+ x (cadr bt))]
              [down? (eq? pressed kind)] [hot? (or down? (eq? hover kind))]
              [red? (and hot? (eq? kind 'close))])
         (fill-box cx y 1 b ink)
         (when hot?
           (fill-box (+ cx 1) (+ y 1) (- c 1) (- b 2)
                     (cond [(not red?) (alpha 'accent (if down? 0.3 0.15))]
                           [down? (mix 'button-close #x000000 0.2)]
                           [else 'button-close])))
         (draft-glyph win kind (+ cx (/ c 2) 1/2) (+ y (quotient b 2) 1/2)
                      (quotient c 6)
                      (cond [red? (color-readable-on 'button-close)]
                            [hot? 'accent]
                            [else ink]))))
     (draft-regions win))))

(define (draft-draw-under win x y w h focused? hover pressed)
  ;; Unfocused lines fade toward the sheet, as faint ink alone is too
  ;; close to Genera's black; their text keeps the dim title color.
  (let*-values ([(ink) (if focused? 'accent
                           (mix 'text-faint (window-bg win) 0.3))]
                [(a) draft-arrow]
                [(left) (+ x (draft-edge win))]   ; the arrows' tips
                [(right) (+ x (draft-block-x win))]
                [(ly) (+ y (quotient (draft-band) 2))]   ; the line's row
                ;; with at least 6 pixels of line either side of the text
                [(title size)
                 (draft-label win (- right left (* 2 (+ a 6 draft-pad))))]
                [(lw) (ceiling (+ (text-width title 'title)
                                  (text-width size 'ui)))]
                [(pad) (if (zero? lw) 0 draft-pad)]
                [(lx) (round (/ (+ left right (- lw)) 2))]
                [(base) (draft-baseline (+ ly 1/2))])
    (window-shadow win x y w h 0 focused?)
    (fill-box x y w h (window-bg win))
    (with-clip (x y w h)   ; a window narrower than its block cuts it
      (unless (maximized? win) (stroke-box x y w h ink))
      (when (> (- right left) (* 2 a))
        (fill-box (+ left a -1) ly (- lx pad left a -1) 1 ink)
        (fill-box (+ lx lw pad) ly (- right a -1 lx lw pad) 1 ink)
        (draft-arrowhead left (+ ly 1/2) 1 ink)
        (draft-arrowhead right (+ ly 1/2) -1 ink))
      (draw-text (draw-text lx (- base (font-ascent 'title)) title
                            (if focused? 'title-text 'title-text-dim)
                            'title)
                 (- base (font-ascent 'ui)) size
                 (if focused? ink 'title-text-dim) 'ui)
      (draft-block win x y hover pressed ink))))

;; A move or a resize drags a drawing of where the window goes: its
;; outline and, along its top, the dimension line with the live size,
;; within it, where they fit.
(define (draft-drag-outline x y w h)
  (let* ([a draft-arrow] [p draft-pad] [ly (+ y (quotient (draft-band) 2))]
         [size (format "~a × ~a" (exact (round w)) (exact (round h)))]
         [sw (ceiling (text-width size 'ui))]
         [lx (round (+ x (/ (- w sw) 2)))])
    (stroke-box x y w h 'accent)
    (when (and (> w (+ sw (* 2 (+ a 8 p)))) (> h (draft-band)))
      (fill-box (+ x a) ly (- lx p x a) 1 'accent)
      (fill-box (+ lx sw p) ly (- (+ x w) a lx sw p) 1 'accent)
      (draft-arrowhead (+ x 1) (+ ly 1/2) 1 'accent)
      (draft-arrowhead (+ x w -1) (+ ly 1/2) -1 'accent)
      (draw-text lx (- (draft-baseline (+ ly 1/2)) (font-ascent 'ui)) size
                 'accent 'ui))))

(define-style draft "Draft"
  ;; square, and so is everything drawn in it (rrect-path!); every common
  ;; option but the radius
  'corner-radius 0
  'options (remq 'corner-radius (map car common-options))
  'drag-feedback 'outline
  'draw-drag-outline 'draft-drag-outline
  'frame-insets 'draft-insets
  'frame-regions 'draft-regions
  'frame-under 'draft-draw-under)
