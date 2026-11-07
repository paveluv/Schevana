;;; styles/curses.ss — the Curses window style.
;;; A window as a text-mode program draws one (curses, Turbo Vision, Emacs
;;; in a terminal): a ring of the mono font's character cells around the
;;; content, with a box ruled through the middle of the ring, so that the
;;; content sits in it like text in a terminal. The focused window's box is
;;; a double rule; the others' a single one, the middle of the double. The
;;; title rides on the top rule between brackets, ═[ REPL ]═, and so do the
;;; buttons: [■] closes at the left, [↓] and [↑] minimize and maximize at
;;; the right ([↕] restores). Under the mouse a button's cell becomes a
;;; block cursor. Other windows show their buttons only while the mouse is
;;; on their top rule, as text-mode windows showed none. Rules, brackets
;;; and glyphs are drawn in whole device pixels, not as box-drawing
;;; characters, so they stay crisp at every scale and in the miniature.

;; A cell of the mono font, 8 × 16 at the default size. The ring is a cell
;; wide at the sides and the bottom; the top row grows with the title bar
;; setting, to 18 by default, so that the buttons are big enough to hit.
(define (curses-cell) (font-char-width 'mono))
(define (curses-side) (exact (round (curses-cell))))
(define (curses-row) (exact (round (font-line-height 'mono))))
(define (curses-top) (max (curses-row) (- (title-height) 12)))

(define (curses-insets win)
  (values (curses-side) (curses-top) (curses-side) (curses-row)))

;; Three cells each: close after the top left corner and a cell of rule,
;; minimize and maximize before the top right one, a cell of rule apart.
(define (curses-regions win)
  (let ([c (curses-cell)] [s (curses-side)] [w (window-w win)])
    (map (lambda (kind x)
           (list kind (exact (round x)) 0 (exact (round (* 3 c)))
                 (curses-top)))
         '(close minimize maximize)
         (list (+ s c) (- w s (* 8 c)) (- w s (* 4 c))))))

;; The title's cells, "[ title ]": (title x width), or #f. In the middle
;; of the window, or as near as it fits between the buttons with a cell of
;; rule to spare. Only when it fits nowhere else does it take the room of
;; hidden buttons, so that the mouse passing by does not move it.
(define (curses-title win buttons?)
  (let ([c (curses-cell)] [s (curses-side)] [w (window-w win)])
    (define (fit lo hi)
      (let* ([title (text-fit (window-title win) (- hi lo (* 4 c)) 'mono)]
             [gw (+ (text-width title 'mono) (* 4 c))])
        (and (<= gw (- hi lo))
             (list title (max lo (min (- hi gw) (/ (- w gw) 2))) gw))))
    (and (not (string=? (window-title win) ""))
         (or (fit (+ s (* 5 c)) (- w s (* 9 c)))
             (and (not buttons?) (fit (+ s c) (- w s c)))))))

;; s in device pixels, k of them to the logical one, in the mono font
;; made k times bigger: its ink centered on x and its capitals' on y,
;; measured as drawn (hinting makes the capitals 10 pixels high at 100%,
;; 21 at 200%), on whole pixels.
(define (curses-text s x y k color)
  (let* ([mono (get-font 'mono)]
         [f (font (font-family mono) (* k (font-size mono)))])
    (define (middle str)   ; of the ink, from the pen: (values x y)
      (let-values ([(l t w h) (text-ink str f)])
        (values (+ l (/ w 2)) (+ t (/ h 2)))))
    (let-values ([(mx my) (middle s)] [(hx hy) (middle "H")])
      (draw-text (floor (- x mx -1/2))
                 (- (floor (- y hy)) (font-ascent f))
                 s color f))))

;; Drawn in device pixels, in pens: squares a line wide, 1 pixel at 100%
;; and 2 at 200%.
(define (curses-draw-under win x y w h focused? hover pressed)
  (let* ([k (draw-scale)] [p (max 1 (round k))]
         [c (curses-cell)] [bg (window-bg win)]
         [ink (if focused? 'accent 'text-faint)]
         [fg (if focused? 'title-text 'title-text-dim)]
         [buttons? (or focused?
                       (memq hover '(title close minimize maximize)))])
    ;; the device pixels' edge nearest a logical x or y, and how many pens a
    ;; logical length is
    (define (dev v) (exact (floor (+ (* k v) 1/2))))
    (define (pens v) (exact (round (/ (* k v) p))))
    ;; from an inset len wide's outer edge to the middle pen of the 3 of a
    ;; double rule through it
    (define (mid len) (exact (floor (/ (- (* k len) p) 2))))
    (let* ([L (+ (dev x) (mid (curses-side)))]
           [R (- (dev (+ x w)) (mid (curses-side)) p)]
           [T (+ (dev y) (mid (curses-top)))]
           [B (- (dev (+ y h)) (mid (curses-row)) p)]
           [e (pens (* 2/5 (curses-row)))] [arm (pens (* 0.45 c))]  ; brackets
           [a (pens (* 0.27 (curses-row)))] [n (pens (* 3/8 c))]    ; arrows
           [q (pens (/ c 4))] [b (pens (/ c 2))])
      ;; pens of the top rule, counted from the column cx and the rule
      (define (pen cx i j iw jh color)
        (fill-box (+ cx (* p i)) (+ T (* p j)) (* p iw) (* p jh) color))
      ;; cells gw wide at gx on the top rule: the rule cleared under them,
      ;; a bracket at each end, and (fill cx) in the middle
      (define (group gx gw fill)
        (let ([cx (dev (- (+ x gx (/ gw 2)) (/ p k 2)))]
              [d (pens (- (/ gw 2) (* 3/8 c)))])
          (pen cx (- (+ d q)) -1 (+ d d q q 1) 3 bg)
          (for-each (lambda (bar from)
                      (pen cx bar (- e) 1 (+ e e 1) ink)
                      (pen cx from (- e) arm 1 ink)
                      (pen cx from e arm 1 ink))
                    (list (- d) d) (list (- d) (- d arm -1)))
          (fill cx)))
      ;; an arrow 2a+1 pens high, its heads 45-degree trapezoids
      (define (arrow cx up? down? color)
        (define (head y dy)
          (let ([y1 (+ y (* dy n p))])
            (fill-polygon (list (cons cx y) (cons (+ cx p) y)
                                (cons (+ cx p (* n p)) y1)
                                (cons (- cx (* n p)) y1))
                          color)))
        (when up? (head (- T (* a p)) 1))
        (when down? (head (+ T (* (+ a 1) p)) -1))
        (pen cx 0 (- (if up? n 0) a) 1
             (- (+ a a 1) (if up? n 0) (if down? n 0)) color))
      (define (button kind gx gw)
        (let* ([hot? (or (eq? hover kind) (eq? pressed kind))]
               [cell (if (eq? kind 'close) 'button-close 'accent)]
               [color (if hot? bg fg)])
          (group gx gw
            (lambda (cx)
              (when hot?   ; a block cursor
                (pen cx (- b) (- e) (+ b b 1) (+ e e 1)
                     (if (eq? pressed kind) (mix cell bg 0.35) cell)))
              (case kind
                [(close) (pen cx (- q) (- q) (+ q q 1) (+ q q 1) color)]
                [(minimize) (arrow cx #f #t color)]
                [else (arrow cx #t (maximized? win) color)])))))
      (window-shadow win x y w h 0 focused?)
      (fill-box x y w h bg)
      (with-clip (x y w h)   ; a narrow window cuts its buttons
        (with-scale ((/ 1 k))   ; from here on, whole device pixels
          ;; the double rule's outer and inner lines, or the one
          ;; between
          (for-each (lambda (o)
                      (stroke-box (+ L o) (+ T o) (- (+ R p) L o o)
                                  (- (+ B p) T o o) ink p))
                    (if focused? (list (- p) p) '(0)))
          (when buttons?
            (for-each (lambda (bt)
                        (button (car bt) (cadr bt) (cadddr bt)))
                      (curses-regions win)))
          (let ([t (curses-title win buttons?)])
            (when t
              (group (cadr t) (caddr t)
                (lambda (cx)
                  (curses-text (car t) (+ cx (/ p 2)) (+ T (/ p 2)) k
                               fg))))))))))

;; A terminal's visual bell flashes the screen; menus box their entries.
(define-style curses "Curses"
  ;; square, and so is everything drawn in it (rrect-path!); every common
  ;; option but the radius
  'corner-radius 0
  'options (remq 'corner-radius (map car common-options))
  'bell 'screen
  'menu-hover 'outline
  'frame-insets 'curses-insets
  'frame-regions 'curses-regions
  'frame-under 'curses-draw-under)
