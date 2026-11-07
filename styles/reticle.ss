;;; styles/reticle.ss — the Reticle window style.
;;; A viewfinder locking onto its target: four L-shaped brackets in the
;;; accent color stand off a few pixels from the focused window's corners,
;;; the way a camera or a heads-up display frames what it has acquired.
;;; Every window is a plain card with a hairline edge, and the unfocused
;;; ones keep only that and recede. The title is a label in small
;;; letter-spaced capitals at the top left, like the wallpaper's name; the
;;; buttons are glyphs at the top right, maximize drawn as the brackets
;;; themselves, and the mouse locks onto a button with brackets of its own.

(define reticle-margin 5)   ; around the card: the brackets, then air
(define reticle-pad 10)     ; from the card's edge to the title, the glyphs
(define reticle-font 'ui-small)

(define (reticle-insets win)   ; the card's hairline is chrome too
  (let ([m (+ reticle-margin 1)]) (values m (title-height) m m)))

;; Device pixels per logical pixel where we draw: the picker's miniature
;; is drawn scaled down.
(define (reticle-k) (draw-scale))

;; Whole device pixels, so that lines are crisp at any scale: v to the
;; nearest one (or by floor or ceiling, to stay inside a box), and a
;; weight of n pixels, at least n device pixels.
(define (reticle-snap v . how)
  (let ([k (reticle-k)]) (/ ((if (pair? how) (car how) round) (* v k)) k)))
(define (reticle-px n) (let ([k (reticle-k)]) (/ (max n (floor (* n k))) k)))

;; A glyph's box at k device pixels per pixel: about the capitals' height,
;; in whole device pixels, odd under 1-pixel lines and even under 2-pixel
;; ones, so that the lines run through its middle.
(define (reticle-glyph k)
  (let ([s (font-size (get-font reticle-font))])
    (/ (+ (max 1 (floor k)) (* 2 (floor (* 2/5 s k)))) k)))

;; Cells around the glyphs. The last glyph ends as far from the card's
;; right edge as the title starts from its left.
(define (reticle-regions win)
  (let* ([g (reticle-glyph 1)] [c (max 18 (+ g 10))]
         [x (- (window-w win) reticle-margin 1 reticle-pad
               (quotient (+ c g) 2))])
    (map (lambda (kind i) (list kind (- x (* i c)) 0 c (title-height)))
         '(minimize maximize close) '(2 1 0))))

;; (values baseline middle): the baseline that centers the label's
;; capitals on cy, and the capitals' middle.
(define (reticle-caps cy)
  (let*-values ([(l top w h) (text-ink "H" reticle-font)]
                [(cap) (- top)]
                [(base) (reticle-snap (+ cy (/ cap 2)))])
    (values base (- base (/ cap 2)))))

(define (reticle-track)   ; between capitals: a sixth of the font's size
  (reticle-snap (/ (font-size (get-font reticle-font)) 6)))

;; The title in capitals, cut with an ellipsis to fit in room when spaced;
;; no title stays none, even where no room is left.
(define (reticle-label title room)
  (let ([t (reticle-track)])
    (if (string=? title "")
        ""
        (text-fit (string-upcase title) room reticle-font
                  (lambda (s) (+ (text-width s reticle-font)
                                 (* t (- (string-length s) 1))))))))

(define (reticle-draw-label x y s color)
  (let ([t (reticle-track)])
    (fold-left (lambda (x c)
                 (+ (draw-text x y (string c) color reticle-font) t))
               (reticle-snap x) (string->list s))))

;; Brackets on the corners of the box (x y w h), arms a long (at most
;; half the box) and lw thick, on whole device pixels inside it. Each
;; lies along two sides of its corner's a-square: the outer sides, or the
;; inner ones when turned in.
(define (reticle-corners x y w h a lw color in?)
  (let* ([lw (reticle-px lw)] [a (reticle-snap (min a (/ w 2) (/ h 2)))]
         [x0 (reticle-snap x ceiling)] [y0 (reticle-snap y ceiling)]
         [x1 (- (reticle-snap (+ x w) floor) a)]
         [y1 (- (reticle-snap (+ y h) floor) a)]
         [side (lambda (v first?) (if (eq? first? in?) (+ v a (- lw)) v))])
    (for-each (lambda (sx sy left? top?)
                (fill-box sx (side sy top?) a lw color)
                (fill-box (side sx left?) sy lw a color))
              (list x0 x1 x0 x1) (list y0 y0 y1 y1)
              '(#t #f #t #f) '(#t #t #f #f))))

;; −, ×, or the brackets (turned in to restore) in the g box at (x, y).
;; Under the mouse, brackets d out lock onto the glyph, closing in while
;; it is pressed; maximize's own brackets grow out to where they would be.
(define (reticle-draw-button win kind x y g d focused? hover pressed)
  (let* ([down? (eq? pressed kind)] [hot? (or down? (eq? hover kind))]
         [d (cond [down? (max 1 (- d 2))] [hot? d] [else 0])]
         [lw (reticle-px 1)]
         [ink (cond [(not hot?) (if focused? 'text-dim 'text-faint)]
                    [(eq? kind 'close) 'button-close]
                    [else 'accent])])
    (when (or hot? (eq? kind 'maximize))
      (reticle-corners (- x d) (- y d) (+ g d d) (+ g d d)
                       (if hot? (+ d 1) (round (/ g 3))) 1 ink
                       (and (eq? kind 'maximize) (maximized? win))))
    (case kind
      [(minimize) (fill-box x (+ y (/ (- g lw) 2)) g lw ink)]
      [(close)   ; corner to corner, as heavy as a 1-pixel line
       (let ([t (* 3/4 lw)] [b (+ y g)])
         (for-each (lambda (x0 x1 u)   ; from the top at x0 to the bottom at x1
                     (fill-polygon (list (cons x0 y) (cons (+ x0 u) y)
                                         (cons x1 (- b t)) (cons x1 b)
                                         (cons (- x1 u) b) (cons x0 (+ y t)))
                                   ink))
                   (list x (+ x g)) (list (+ x g) x) (list t (- t))))])))

(define (reticle-draw-under win x y w h focused? hover pressed)
  ;; The title row runs from under the card's hairline (from the frame's
  ;; top, maximized) down to the content.
  (let*-values ([(m) reticle-margin] [(th) (title-height)]
                [(top) (if (maximized? win) 0 (+ m 1))]
                [(g) (reticle-glyph (reticle-k))] [(bs) (reticle-regions win)]
                [(cx cy cw ch) (values (+ x m) (+ y m) (- w m m) (- h m m))]
                [(base mid) (reticle-caps (+ y (/ (+ top th) 2)))]
                [(gy) (reticle-snap (- mid (/ g 2)))]
                [(d) (min 4 (floor (/ (- th top g) 2)))]
                [(tx) (+ x m 1 reticle-pad)])
    (window-shadow win cx cy cw ch 0 focused?)
    (if (maximized? win)   ; the screen's edges are the card's
        (fill-box x y w h (window-bg win))
        (let ([x0 (reticle-snap cx ceiling)] [y0 (reticle-snap cy ceiling)])
          (fill-box cx cy cw ch (window-bg win))
          (stroke-box x0 y0 (- (reticle-snap (+ cx cw) floor) x0)
                      (- (reticle-snap (+ cy ch) floor) y0)
                      (if focused? 'window-border-focus 'window-border)
                      (reticle-px 1))))
    (when focused?
      (reticle-corners x y w h (round (* 0.7 th)) 2 'accent #f))
    (with-clip ((+ x top) (+ y top) (- w top top) (- th top))
      (reticle-draw-label tx (- base (font-ascent reticle-font))
                          (reticle-label (window-title win)
                                         (- (+ x (cadar bs)) tx 6))
                          (if focused? 'title-text 'title-text-dim))
      (for-each (lambda (b)
                  (reticle-draw-button
                   win (car b)
                   (reticle-snap (+ x (cadr b) (/ (- (cadddr b) g) 2)))
                   gy g d focused? hover pressed))
                bs))))

;; A move or a resize drags the brackets alone to where the window goes.
(define (reticle-drag-outline x y w h)
  (reticle-corners x y w h (round (* 0.7 (title-height))) 2 'accent #f))

;; Scroll bars show while the pointer is over what they scroll.
(define-style reticle "Reticle"
  ;; square, and so is everything drawn in it (rrect-path!); every common
  ;; option but the radius
  'corner-radius 0
  'options (remq 'corner-radius (map car common-options))
  'drag-feedback 'outline
  'draw-drag-outline 'reticle-drag-outline
  'scrollbar-show 'hover
  'frame-insets 'reticle-insets
  'frame-regions 'reticle-regions
  'frame-under 'reticle-draw-under)
