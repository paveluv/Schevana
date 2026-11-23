;;; (schevana styles cons cells) — a part of the Cons style ((schevana
;;; styles cons)): the cons cell, the style's one idea, as boxes, dots,
;;; pointers and nil; and the window drawn as a chain of cells, its title
;;; in the cars.

(library (schevana styles cons cells)
  (export
    cons-cell cons-dot-x cons-dot-y cons-down! cons-draw-over cons-draw-under
    cons-left cons-nil! cons-nil-h! cons-pair! cons-pair-h! cons-pointer!
    cons-regions cons-right! cons-ring! cons-thin cons-title-y)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) alpha draw-line draw-scale draw-text fill-box
                fill-circle fill-polygon font-ascent font-line-height text-width
                title-height window-bg window-shadow window-title window-w
                with-clip)
          (only (schevana kits text) text-fit text-ink))

  (library-layer looks)

  ;; A cell is a square that the title's line fits in, an even number of
  ;; pixels wide so that the glyphs center: 20 at the default fonts. The
  ;; chain sits a quarter of a cell from the left, in the middle of the
  ;; title bar.
  (define (cons-line) (exact (round (font-line-height 'title))))
  (define (cons-cell) (* 2 (quotient (+ (cons-line) 6) 2)))
  (define (cons-left) (quotient (cons-cell) 4))

  ;; A pointer's length: 0.7 of a cell, shorter (down to a third of a cell)
  ;; where the window is so narrow that the chain would not fit with a car
  ;; a cell wide.
  (define (cons-gap win)
    (let ([c (cons-cell)])
      (max (quotient c 3)
           (min (quotient (* 7 c) 10)
                (quotient (- (window-w win) (* 2 (cons-left)) (* 6 c)) 2)))))

  ;; The title's car: as wide as the title and a little more, at least a
  ;; cell, and narrow enough to leave room for the rest of the chain.
  (define (cons-car-width win)
    (let ([c (cons-cell)])
      (max c (min (exact (ceiling (+ (text-width (window-title win) 'title)
                                     (* 4/5 c))))
                  (- (window-w win) (* 2 (cons-left)) (* 5 c)
                     (* 2 (cons-gap win)))))))

  ;; Where the three pairs start: the title's, minimize's and maximize's.
  (define (cons-pairs win)
    (let* ([c (cons-cell)] [a (cons-gap win)]
           [x (+ (cons-left) (cons-car-width win) c a)])
      (list (cons-left) x (+ x c c a))))

  (define (cons-regions win)
    (let ([c (cons-cell)] [th (title-height)] [xs (cons-pairs win)])
      (list (list 'minimize (cadr xs) 0 c th)
            (list 'maximize (caddr xs) 0 c th)
            (list 'close (+ (caddr xs) c) 0 c th))))

  ;; A box's lines, lw thick inside it, and every fill below lie on whole
  ;; device pixels (fill-box), so a cell is crisp wherever it lies, at any
  ;; scale.
  ;; A line n thick, but at least a device pixel, in Settings' half-size
  ;; miniature too.
  (define (cons-thin n)
    (max n (/ 1 (draw-scale))))

  (define (cons-ring! x y w h color . lw)
    (let ([n (cons-thin (if (pair? lw) (car lw) 1))])
      (fill-box x y w n color)
      (fill-box x (+ y h (- n)) w n color)
      (fill-box x (+ y n) n (- h n n) color)
      (fill-box (+ x w (- n)) (+ y n) n (- h n n) color)))

  ;; A pair at x of any height: a car w wide and a cdr cw wide, h high,
  ;; each filled with its tint when it has one. The divider lies inside the
  ;; car, so that a cell's car is square inside.
  (define (cons-pair-h! x y w h cw ink lw car-tint cdr-tint)
    (when car-tint (fill-box x y w h car-tint))
    (when cdr-tint (fill-box (+ x w) y cw h cdr-tint))
    (cons-ring! x y (+ w cw) h ink lw)
    (fill-box (+ x w (- lw)) y (cons-thin lw) h ink))

  ;; The title's pair: its cdr is a square cell, c on a side.
  (define (cons-pair! x y w c ink lw car-tint cdr-tint)
    (cons-pair-h! x y w c c ink lw car-tint cdr-tint))

  ;; The dot's center in a cdr whose inside starts at x and is cw wide, and
  ;; in one at y that is h high: on a whole pixel for a 2-pixel stroke, and
  ;; between two for a 1-pixel one, so that the lines from it stay crisp.
  (define (cons-dot-x x cw lw) (+ x (/ (- cw lw) 2)))
  (define (cons-dot-y y h lw) (+ y (quotient (- h lw) 2) (/ lw 2)))

  ;; The dot at (dx, my) and an arrow from it right to x1 (the next cell's
  ;; edge). The dot's radius is a tenth of a cell, the head a third of a
  ;; cell long.
  (define (cons-right! dx my x1 c ink lw)
    (let ([head (quotient c 3)] [half (quotient c 6)] [ly (- my (/ lw 2))])
      (fill-circle dx my (+ (/ c 10) (/ lw 2)) ink)
      (fill-box (floor dx) ly (- x1 head (floor dx) -1) (cons-thin lw) ink)
      (fill-polygon (list (cons x1 my) (cons (- x1 head) (- my half))
                          (cons (- x1 head) (+ my half)))
                    ink)))

  ;; The dot at (dx, my) and an arrow from it down to y1.
  (define (cons-down! dx my y1 c ink lw)
    (let ([head (quotient c 3)] [half (quotient c 6)] [lx (- dx (/ lw 2))])
      (fill-circle dx my (+ (/ c 10) (/ lw 2)) ink)
      (fill-box lx (floor my) (cons-thin lw) (- y1 head (floor my) -1) ink)
      (fill-polygon (list (cons dx y1) (cons (- dx half) (- y1 head))
                          (cons (+ dx half) (- y1 head)))
                    ink)))

  ;; From a dot in the middle of the title's cdr whose inside starts at x,
  ;; an arrow to the box at x1.
  (define (cons-pointer! x x1 y c ink lw)
    (cons-right! (cons-dot-x x c lw) (cons-dot-y y c lw) x1 c ink lw))

  ;; - or + in the cell at x, 2 pixels thick like the bold title's
  ;; strokes.
  (define (cons-sign! x y c plus? color lw)
    (let* ([i (- c lw lw)] [g (* 2 (quotient c 5))]
           [o (+ lw (quotient (- i g) 2))] [m (+ lw (quotient (- i 2) 2))])
      (fill-box (+ x o) (+ y m) g 2 color)
      (when plus? (fill-box (+ x m) (+ y o) 2 g color))))

  ;; nil: the slash across the cdr whose inside starts at x, crossed out in
  ;; the color cross when one is given. It is clipped to the inside, so that
  ;; the box's lines stay clean.
  (define (cons-nil! x y c ink lw cross)
    (let ([w (- c lw)] [h (- c lw lw)] [y (+ y lw)])
      (with-clip (x y w h)
        (draw-line x (+ y h) (+ x w) y (or cross ink) lw)
        (when cross (draw-line x y (+ x w) (+ y h) cross lw)))))

  ;; nil in a cdr cw wide and h high: the slash across a square of the
  ;; cdr's width, in its middle.
  (define (cons-nil-h! x y cw h ink lw cross)
    (cons-nil! x (+ y (quotient (- h cw) 2)) cw ink lw cross))

  ;; The y to draw the title at so that its capitals sit in the middle of a
  ;; cell at cy, c high.
  (define (cons-title-y cy c)
    (let-values ([(l top w h) (text-ink "H" 'title)])
      (- (+ cy (/ c 2) (/ (- top) 2)) (font-ascent 'title))))

  (define (cons-tint kind hover pressed color)
    (cond [(eq? pressed kind) (alpha color 0.6)]
          [(eq? hover kind) color]
          [else #f]))

  (define (cons-draw-under win x y w h focused? hover pressed)
    (let* ([th (title-height)] [c (cons-cell)] [cy (+ y (quotient (- th c) 2))]
           [lw (if focused? 2 1)] [ink (if focused? 'accent 'text-faint)]
           [fg (if focused? 'title-text 'title-text-dim)] [bg (window-bg win)]
           [cw (cons-car-width win)]
           [xs (map (lambda (p) (+ x p)) (cons-pairs win))]
           [t (car xs)] [b (cadr xs)] [m (caddr xs)]
           [s (text-fit (window-title win) (- cw (* 4/5 c)) 'title)]
           [close (cons-tint 'close hover pressed 'button-close)])
      (define (sign x kind plus? cdr-tint)
        (let ([tint (cons-tint kind hover pressed 'accent)])
          (cons-pair! x cy c c ink lw tint cdr-tint)
          (cons-sign! x cy c plus? (if tint bg fg) lw)))
      (window-shadow win x y w h 0 focused?)
      (fill-box x y w h bg)
      (fill-box x (+ y th -1) w 1 'window-border)
      (with-clip (x y w th)
        (cons-pair! t cy cw c ink lw #f #f)
        (draw-text (+ t (floor (/ (- cw (text-width s 'title)) 2)))
                   (cons-title-y cy c) s fg 'title)
        (cons-pointer! (+ t cw) b cy c ink lw)
        (sign b 'minimize #f #f)
        (cons-pointer! (+ b c) m cy c ink lw)
        (sign m 'maximize #t close)
        (cons-nil! (+ m c) cy c ink lw (and close bg)))))

  (define (cons-draw-over win x y w h focused? hover pressed)
    (cons-ring! x y w h (if focused? 'window-border-focus 'window-border))))
