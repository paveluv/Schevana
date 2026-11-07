;;; styles/cons.ss — the Cons window style.
;;; The title bar is a box-and-pointer diagram, drawn the way SICP draws a
;;; list: the window is ("Title" - +). Its first pair holds the title in
;;; its car and points to two more pairs, whose cars minimize and maximize;
;;; the chain ends, as every list does, in the nil slash, and clicking that
;;; end of the list closes the window. Drawn, not painted: outlined cells
;;; on the window's own background, in accent ink with a bolder stroke
;;; while the window has the focus, in faint ink when it has not. Under the
;;; mouse a cell fills with ink; nil fills red, its slash crossed out.
;;;
;;; The idea goes on below the title bar: everything on the screen is
;;; Lisp data, drawn the same way (the second half of this file). A
;;; button is a cell with its word in it, a checkbox a cell holding #t
;;; or #f, a text box a string in quotes, a dropdown a pair whose pointer
;;; leaves downward; tabs, chips, a column's cards, menus, toasts, the
;;; taskbar and a dialog are chains ending in nil, and in a dialog, as in
;;; a window, nil is where you cancel.

;; A cell is a square the title's line fits in, and an even number of
;; pixels so that the glyphs center: 20 at the default fonts. The chain
;; sits a quarter cell from the left, in the middle of the title bar.
(define (cons-line) (exact (round (font-line-height 'title))))
(define (cons-cell) (* 2 (quotient (+ (cons-line) 6) 2)))
(define (cons-left) (quotient (cons-cell) 4))

;; A pointer's length: 0.7 of a cell, shorter where the window is so
;; narrow that the chain would not fit with a car a cell wide.
(define (cons-gap win)
  (let ([c (cons-cell)])
    (max (quotient c 3)
         (min (quotient (* 7 c) 10)
              (quotient (- (window-w win) (* 2 (cons-left)) (* 6 c)) 2)))))

;; The title's car: as wide as the title, at least a cell, and narrow
;; enough to leave room for the rest of the chain.
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

;; A box's lines, lw thick inside it, and every fill below, on whole
;; device pixels (fill-box): a cell is crisp wherever it lies, at any
;; scale.
;; A line n thick, but a device pixel at least: in Settings' half-size
;; miniature, too.
(define (cons-thin n)
  (max n (/ 1 (draw-scale))))

(define (cons-ring! x y w h color . lw)
  (let ([n (cons-thin (if (pair? lw) (car lw) 1))])
    (fill-box x y w n color)
    (fill-box x (+ y h (- n)) w n color)
    (fill-box x (+ y n) n (- h n n) color)
    (fill-box (+ x w (- n)) (+ y n) n (- h n n) color)))

;; A pair at x of any height: a car w wide and a cdr cw wide, h high,
;; each maybe tinted. The divider lies in the car, so a cell's car is a
;; square inside.
(define (cons-pair-h! x y w h cw ink lw car-tint cdr-tint)
  (when car-tint (fill-box x y w h car-tint))
  (when cdr-tint (fill-box (+ x w) y cw h cdr-tint))
  (cons-ring! x y (+ w cw) h ink lw)
  (fill-box (+ x w (- lw)) y (cons-thin lw) h ink))

;; The title's pair: its cdr a square cell, c.
(define (cons-pair! x y w c ink lw car-tint cdr-tint)
  (cons-pair-h! x y w c c ink lw car-tint cdr-tint))

;; The dot's center in a cdr whose inside starts at x, cw wide, and in
;; one at y, h high: on a whole pixel for a 2-pixel stroke, between two
;; for a 1-pixel one, so the lines from it stay crisp.
(define (cons-dot-x x cw lw) (+ x (/ (- cw lw) 2)))
(define (cons-dot-y y h lw) (+ y (quotient (- h lw) 2) (/ lw 2)))

;; From the dot at (dx, my), an arrow right to x1 (the next cell's
;; edge); the dot a tenth of a cell, the head a third.
(define (cons-right! dx my x1 c ink lw)
  (let ([head (quotient c 3)] [half (quotient c 6)] [ly (- my (/ lw 2))])
    (fill-circle dx my (+ (/ c 10) (/ lw 2)) ink)
    (fill-box (floor dx) ly (- x1 head (floor dx) -1) (cons-thin lw) ink)
    (fill-polygon (list (cons x1 my) (cons (- x1 head) (- my half))
                        (cons (- x1 head) (+ my half)))
                  ink)))

;; From the dot at (dx, my), an arrow down to y1.
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

;; - or + in the cell at x, 2 pixels thick like the bold title's strokes.
(define (cons-sign! x y c plus? color lw)
  (let* ([i (- c lw lw)] [g (* 2 (quotient c 5))]
         [o (+ lw (quotient (- i g) 2))] [m (+ lw (quotient (- i 2) 2))])
    (fill-box (+ x o) (+ y m) g 2 color)
    (when plus? (fill-box (+ x m) (+ y o) 2 g color))))

;; nil: the slash across the cdr whose inside starts at x, crossed out in
;; the color cross. Clipped to the inside, so the box's lines stay clean.
(define (cons-nil! x y c ink lw cross)
  (let ([w (- c lw)] [h (- c lw lw)] [y (+ y lw)])
    (with-clip (x y w h)
      (draw-line x (+ y h) (+ x w) y (or cross ink) lw)
      (when cross (draw-line x y (+ x w) (+ y h) cross lw)))))

;; nil in a cdr cw wide and h high: the slash across a square of its
;; width in its middle.
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
  (cons-ring! x y w h (if focused? 'window-border-focus 'window-border)))

;;; ------------------------------------------------------------------
;;; the rest of the screen: Lisp data, drawn as the title is
;;; Cells are outlined boxes on the background, in the plain ink; what is
;;; focused, chosen or the default has the bold stroke in accent ink, as
;;; a focused window's chain; what is disabled, a hint or elsewhere is
;;; faint. A cell fills with its ink under the mouse, its word in the
;;; paper; pressed, at alpha 0.6, as the title's. Literals look like
;;; literals, in the code font: #t and #f, strings in quotes, the empty
;;; list as (). The chain reads where it reads best (tabs, chips, a
;;; column's cards, menus, toasts, the taskbar, a dialog); the rest are
;;; plain cells, so the diagram is not all arrows.

;; The plain ink, a color of its own: dim text, which you may change.
(color-default! 'cons-ink (theme-rule (theme 'text-dim)))

;; The spacing, from the cell c (20 at the default fonts), each length
;; even so that it lands on whole device pixels at 150 % too:
;;   g = 0.3 c (6): between two neighbors, and from the edge of the cell
;;       or box a thing sits in (a card in its column, a + in a heading,
;;       text in a cell);
;;   a = 0.7 c (14): between two things a pointer links (cards, chips,
;;       tabs, menu entries, toasts), as in the title bar;
;;   the pad, 2 g: a window's or a dialog's own margin.
;; A scroll bar is a thumb g wide with g between it and the edge it is
;; against; what scrolls keeps g clear of it (scrollbar-margin), and it
;; keeps g from the ends of its view. Things touch only where the
;; diagram says so: a pointer meets its cell, a cdr shares its car's edge.
(define (cons-space) (* 2 (round (* 3/20 (cons-cell)))))
(define (cons-arrow) (* 2 (round (* 7/20 (cons-cell)))))
;; A cdr is a square where its pair is a square (the title's, a menu's,
;; a chip's); in a control as tall as a button (a tab, a dropdown) it is
;; a slot as wide as a pointer is long, so that a toolbar of them stays a
;; row.
(define (cons-slot) (cons-arrow))

;; A cell's fill by its state: its ink under the mouse, at 0.6 while
;; pressed; none otherwise.
(define (cons-tint-of flags ink)
  (cond [(memq 'pressed flags) (alpha ink 0.6)]
        [(memq 'hover flags) ink]
        [else #f]))

;; A box n pixels thick, and the bold stroke of what is focused.
(define (cons-focus x y w h flags r) (cons-ring! x y w h 'accent 2))

;; A button is a cell with its word, or its glyph, in it: the default
;; one (primary), and every one in a dialog's chain (cons-chain, the
;; dialog place), in the bold accent stroke; danger in red ink; a quiet
;; one faint, filling with the plain ink under the mouse; disabled, faint
;; and still.
(define (cons-button x y w h flags label glyph)
  (let* ([on? (lambda (f) (memq f flags))]
         [live? (not (on? 'disabled))]
         [bold? (or (and (theme 'cons-chain) (not (on? 'quiet)))
                    (on? 'primary) (on? 'focused))]
         [ink (cond [(not live?) 'text-faint]
                    [(on? 'danger) 'red]
                    [(or bold? (on? 'selected)) 'accent]
                    [(on? 'quiet) 'text-faint]
                    [else 'cons-ink])]
         [tint (cond [(not live?) #f]
                     [(on? 'selected) ink]
                     [else (cons-tint-of flags
                                         (if (on? 'quiet) 'cons-ink ink))])]
         [fg (cond [tint 'window-bg]
                   [(not live?) 'text-faint]
                   [(on? 'danger) 'red]
                   [else 'text])]
         [lh (font-line-height 'ui)] [g (ui-glyph-size)]
         [gw (if glyph (* 3/2 g) 0)]   ; the glyph and its gap
         [label (and label (text-fit label (- w 12 gw) 'ui))]
         [cw (if label (+ gw (text-width label 'ui)) g)]
         [x0 (+ x (/ (- w cw) 2))])
    (when tint (fill-box x y w h tint))
    (cons-ring! x y w h ink (if bold? 2 1))
    (when glyph
      (ui-draw-glyph x0 (+ y (/ (- h g) 2)) g g (list (cons 'ink fg)) glyph))
    (when label
      (draw-text (+ x0 gw) (+ y (/ (- h lh) 2)) label fg 'ui))))

;; A glyph alone (a +, a ×) is a button a cell square, a word the
;; kit's width.
(define (cons-button-size label glyph)
  (if label
      (ui-button-size* label glyph)
      (let ([c (cons-cell)]) (values c c))))

;; A boolean is a cell holding #t or #f, in the code font: a checkbox is
;; one, and so is a toggle. #t in accent ink, #f dim; the cell as high as
;; the kit's box, as wide as the literal and a little; focused, bold.
;; Returns the cell's width.
(define (cons-bool-width) (round (+ 8 (text-width "#f" 'mono))))

(define (cons-bool! x y h flags on?)
  (let* ([bw (cons-bool-width)] [b (ui-checkbox-box)]
         [by (+ y (floor (/ (- h b) 2)))]
         [focused? (memq 'focused flags)]
         [ink (if focused? 'accent 'cons-ink)]
         [tint (cons-tint-of flags ink)])
    (when tint (fill-box x by bw b tint))
    (cons-ring! x by bw b ink (if focused? 2 1))
    (text-draw-centered x by bw b (if on? "#t" "#f")
                        (cond [tint 'window-bg] [on? 'accent] [else 'text-dim])
                        'mono)
    bw))

;; A thing to mark: the boolean, then its name, dim once it is #t (a
;; checklist's done items).
(define (cons-checkbox x y w h flags label)
  (let ([bw (cons-bool! x y h flags (memq 'checked flags))]
        [lh (font-line-height 'ui)])
    (when label
      (draw-text (+ x bw (cons-space)) (+ y (/ (- h lh) 2))
                 (text-fit label (- w bw (cons-space)) 'ui)
                 (if (memq 'checked flags) 'text-dim 'text) 'ui))))

(define (cons-checkbox-size label)
  (values (+ (cons-bool-width) (cons-space) (text-width label 'ui))
          (ui-control-height)))

;; "Show done": the same boolean, its name plain whatever it is.
(define (cons-toggle x y w h flags label)
  (let ([bw (cons-bool! x y h flags (memq 'checked flags))]
        [lh (font-line-height 'ui)])
    (when label
      (draw-text (+ x bw (cons-space)) (+ y (/ (- h lh) 2))
                 (text-fit label (- w bw (cons-space)) 'ui) 'text 'ui))))

;; Tabs are a list of symbols, [Board|•]→[List|•]→[Tree|/]: each a pair,
;; its car the word, its cdr a pointer to the next; the last one's (the
;; kit says which) holds nil. The current one's car is filled; the chain
;; stays in the plain ink, bold while a tab has the keyboard.
(define (cons-tab-car label) (+ (* 2 (cons-space)) (text-width label 'ui)))

(define (cons-tab x y w h flags label)
  (let* ([c (cons-slot)] [cw (- w c (cons-arrow))]
         [on? (lambda (f) (memq f flags))]
         [bold? (on? 'focused)]
         [ink (if bold? 'accent 'cons-ink)] [lw (if bold? 2 1)]
         [tint (if (on? 'selected) 'accent (cons-tint-of flags ink))])
    (cons-pair-h! x y cw h c ink lw tint #f)
    (text-draw-centered x y cw h (text-fit label (- cw 8) 'ui)
                        (if tint 'window-bg 'text) 'ui)
    (if (on? 'last)
        (cons-nil-h! (+ x cw) y c h ink lw #f)
        (cons-right! (cons-dot-x (+ x cw) c lw) (cons-dot-y y h lw) (+ x w)
                     (cons-cell) ink lw))))

;; Each tab is its car, its cdr and its pointer; as high as a control,
;; so that a row of them stands with the buttons.
(define (cons-tabs-size labels)
  (values (fold-left (lambda (acc l)
                       (+ acc (cons-tab-car l) (cons-slot) (cons-arrow)))
                     0 labels)
          (ui-control-height)))

;; A text box holds a literal, and its marks frame the box: the opening
;; one at its top-left corner, the closing one at its bottom-right, in
;; faint ink, for a field, an area of lines (clear of its scroll bar) and
;; a box of chips alike. A string is in quotes; a box of chips (chips)
;; holds a list, in parens, the field for its next element inside it.
;; The focused box has the bold stroke. A search box shows its glass
;; instead of marks.
(define (cons-mark-width) (text-width "\"" 'mono))

(define (cons-field x y w h flags)
  (let* ([on? (lambda (f) (memq f flags))]
         [focused? (on? 'focused)]
         [a (car (ui-text-box-areas x y w h flags))]
         [ty (list-ref a 2)] [lh (font-line-height (list-ref a 5))]
         [dy (/ (- lh (font-line-height 'mono)) 2)]
         [open (if (on? 'chips) "(" "\"")] [close (if (on? 'chips) ")" "\"")]
         [g (cons-space)]
         [bw (if (on? 'lines) (+ (ui-scrollbar-width) g) 0)])
    (cons-ring! x y w h (if focused? 'accent 'cons-ink) (if focused? 2 1))
    (unless (on? 'search)
      (draw-text (+ x g) (+ ty dy) open 'text-faint 'mono)
      (draw-text (- (+ x w) g bw (text-width close 'mono))
                 (+ (- (+ y h) g lh) dy) close 'text-faint 'mono))))

;; The marks g from the box's edges, and the text half a g past them
;; (a mark's glyph has little room of its own); in a box of lines the
;; closing mark keeps g clear of the scroll bar, which lies along the
;; box's right edge.
(define (cons-mark-room) (+ (cons-space) (cons-mark-width)
                            (quotient (cons-space) 2)))

(define (cons-text-box-areas x y w h flags)
  (let* ([bw (ui-scrollbar-width)] [g (cons-space)] [m (cons-mark-room)]
         ;; inside another box's marks (a chip input's field), none
         [left (cond [(memq 'search flags) (+ (ui-glyph-size) g g)]
                     [(memq 'inner flags) 0]
                     [else m])]
         [right (cond [(memq 'search flags) g]
                      [(memq 'lines flags) (+ bw m)]
                      [else m])])
    (list (list 'edit (+ x left) (+ y g) (max 0 (- w left right))
                (max 0 (- h g g)) (if (memq 'large flags) 'heading 'ui))
          (list 'bar (- (+ x w) bw) y bw h))))

;; A dropdown is a pair whose car holds the current value and whose
;; cdr's pointer leaves it downward: that is the arrow. Open, its cdr
;; fills, the menu below continuing the chain; a filter in use (set) is
;; bold accent; no value, a faint placeholder.
(define (cons-dropdown x y w h flags label)
  (let* ([c (cons-slot)] [cw (- w c)] [on? (lambda (f) (memq f flags))]
         [bold? (or (on? 'set) (on? 'open) (on? 'focused))]
         [ink (if bold? 'accent 'cons-ink)] [lw (if bold? 2 1)]
         [tint (cons-tint-of flags ink)]
         [lh (font-line-height 'ui)])
    (cons-pair-h! x y cw h c ink lw tint (and (on? 'open) ink))
    (draw-text (+ x (cons-space)) (+ y (/ (- h lh) 2))
               (text-fit label (- cw (* 2 (cons-space))) 'ui)
               (cond [tint 'window-bg]
                     [(on? 'set) 'accent]
                     [(on? 'placeholder) 'text-faint]
                     [else 'text])
               'ui)
    (cons-down! (cons-dot-x (+ x cw) c lw) (cons-dot-y y h lw)
                (- (+ y h) lw 2) (cons-cell) (if (on? 'open) 'window-bg ink)
                lw)))

;; The value, g in, and the cdr.
(define (cons-dropdown-size labels)
  (values (min (* 10 (font-line-height 'ui))
               (+ (* 2 (cons-space)) (cons-slot) (text-widest labels 'ui)))
          (ui-control-height)))

;; A tag is a symbol in a list: small chained cells, [perf|•]→[render|/],
;; a cdr a square of the chip's height. Every flow of chips (a card's, a
;; row's, the chip input's) leaves 4 between two, which the pointer
;; crosses to touch the next cell. A removable one keeps its × in its
;; car, after the label; the last one (the kit says) holds nil, and one
;; whose next is on the next row points there round the row's end.
(define cons-chip-gap 4)

(define (cons-chip-height) (round (+ (font-line-height 'ui-small) 8)))

;; A removable chip's ×: a small square, the glyph and a little room,
;; half a g after the label and half a g from the car's end.
(define (cons-chip-x-side) (+ (round (ui-small-glyph-size)) 4))

(define (cons-chip-car label removable?)
  (+ (* 2 (cons-space)) (text-width label 'ui-small)
     (if removable? (cons-chip-x-side) 0)))

;; The × square of a chip at x y, h high, its car cw wide.
(define (cons-chip-x-box x y cw h)
  (let ([s (cons-chip-x-side)])
    (values (- (+ x cw) (quotient (cons-space) 2) s)
            (+ y (floor (/ (- h s) 2))) s)))

;; A chip w wide, h high: its car's width, all of w when it is cut short
;; of its cdr (a chip cut to its row), and whether it is.
(define (cons-chip-car-width w h removable?)
  (let ([cw (- w h (cons-arrow) (- cons-chip-gap))])
    (if (< cw (+ 8 (if removable? (cons-chip-x-side) 0)))
        (values w #t)
        (values cw #f))))

;; A removable chip's × is in its car, after the label: a chip stays a
;; pair. Under the mouse (the kit's flags are the ×'s) a square behind
;; the × alone fills red, as a window's nil does, the × in the paper's
;; color, at 0.6 while pressed; the car stays as it is. A chip that is
;; not removable fills under the mouse.
(define (cons-chip x y w h flags label)
  (let*-values ([(removable?) (memq 'removable flags)]
                [(cw cut?) (cons-chip-car-width w h removable?)]
                [(g) (ui-small-glyph-size)]
                [(sh) (font-line-height 'ui-small)]
                [(tint) (and (not removable?) (cons-tint-of flags 'cons-ink))]
                [(close) (and removable? (cons-tint-of flags 'button-close))])
    (if cut?
        (begin (when tint (fill-box x y w h tint))
               (cons-ring! x y w h 'cons-ink 1))
        (cons-pair-h! x y cw h h 'cons-ink 1 tint #f))
    (draw-text (+ x (cons-space)) (+ y (/ (- h sh) 2))
               (text-fit label (- cw (* 2 (cons-space))
                                  (if removable? (cons-chip-x-side) 0))
                         'ui-small)
               (if tint 'window-bg 'text) 'ui-small)
    (when removable?
      (let-values ([(bx by bs) (cons-chip-x-box x y cw h)])
        (when close (fill-box bx by bs bs close))
        (ui-draw-glyph (+ bx (/ (- bs g) 2)) (+ by (/ (- bs g) 2)) g g
                       (list (cons 'ink (if close 'window-bg 'text-dim)))
                       'cross)))
    (unless cut?
      (let ([next (cons-flag flags 'next)]
            [dx (cons-dot-x (+ x cw) h 1)] [my (cons-dot-y y h 1)])
        (cond
          [(memq 'last flags) (cons-nil! (+ x cw) y h 'cons-ink 1 #f)]
          ;; the next one on another row: the pointer bends to it
          [(and next (> (abs (- (caddr next) y)) 1))
           (cons-bend! dx my (+ x w (- cons-chip-gap)) (+ y h)
                       (cadr next) (caddr next) h 'cons-ink)]
          [else (cons-right! dx my (+ x w cons-chip-gap) h 'cons-ink 1)])))))

;; The value of the flag (key . value) in flags, which mix symbols and
;; such pairs, or #f.
(define (cons-flag flags key)
  (find (lambda (f) (and (pair? f) (eq? (car f) key))) flags))

;; A pointer from the dot at (dx, my) in a row's last cdr to the first
;; pair of the next row, at (nx, ny), h high, as SICP draws a wrapped
;; list: out to the right to xr, down to midway between the rows (the
;; row's bottom at bottom), back left past the pair, and into it from
;; the left, at its middle. 1 pixel thick, as the chips' pointers.
(define (cons-bend! dx my xr bottom nx ny h ink)
  (let* ([head (quotient h 3)] [half (quotient h 6)]
         [ym (floor (/ (+ bottom ny) 2))] [xl (- nx head 3)]
         [ny2 (cons-dot-y ny h 1)] [ly (- my 1/2)] [n (cons-thin 1)])
    (fill-circle dx my (+ (/ h 10) 1/2) ink)
    (fill-box (floor dx) ly (- xr (floor dx)) n ink)
    (fill-box (- xr 1) ly n (- ym ly) ink)
    (fill-box xl ym (- xr xl) n ink)
    (fill-box xl ym n (- ny2 ym) ink)
    (fill-box xl (- ny2 1/2) (- nx head xl -1) n ink)
    (fill-polygon (list (cons nx ny2) (cons (- nx head) (- ny2 half))
                        (cons (- nx head) (+ ny2 half)))
                  ink)))

(define (cons-chip-size label removable?)
  (let ([h (cons-chip-height)])
    (values (+ (cons-chip-car label removable?) h (cons-arrow)
               (- cons-chip-gap))
            h)))

;; The × and a little room around it.
(define (cons-chip-areas x y w h)
  (let*-values ([(cw cut?) (cons-chip-car-width w h #t)]
                [(bx by bs) (cons-chip-x-box x y cw h)])
    (list (list 'remove (- bx 2) (- by 2) (+ bs 4) (+ bs 4)))))

;; The chips start half a g after the opening paren, as text does; the
;; kit's rows otherwise, the chips cons-chip-gap apart, which each one's
;; pointer crosses.
(define (cons-chip-input-areas x y w chips)
  (let*-values ([(pad ch) (values cons-chip-gap (ui-control-height))]
                [(in) (cons-mark-room)]
                [(sizes) (map (lambda (c)
                                (call-with-values
                                  (lambda () (ui-chip-size c #t))
                                  cons))
                              chips)]
                [(at height)
                 (ui-flow (+ x in) y (- w in pad) pad
                          (append (map (lambda (s) (cons (car s) ch)) sizes)
                                  (list (cons (min (- w in pad)
                                                   (* 8 (font-line-height 'ui)))
                                              ch))))])
    (let ([f (list-ref at (length chips))])
      (append (map (lambda (s p)
                     (list 'chip (car p)
                           (+ (cdr p) (floor (/ (- ch (cdr s)) 2)))
                           (car s) (cdr s)))
                   sizes (list-head at (length chips)))
              (list (list 'field (car f) (cdr f) (- (+ x w) pad (car f))
                          ch))))))

;; A card (a task, a style) is a box: the chosen or dragged one in the
;; bold stroke; under the mouse, a faint fill.
(define (cons-card x y w h flags)
  (let ([bold? (or (memq 'selected flags) (memq 'floating flags))])
    (when (memq 'hover flags) (fill-box x y w h (alpha 'cons-ink 0.08)))
    (cons-ring! x y w h (if bold? 'accent 'cons-ink) (if bold? 2 1))))

;; A scroll bar is a 1-pixel track; its thumb a cell, filling under the
;; mouse. Its region is the thumb and g beyond it, so that against an
;; edge (a well's, a window's) the thumb keeps g from it; the track
;; keeps g from the ends of the view.
(define (cons-scrollbar-areas x y w h start size)
  (let* ([g (cons-space)] [tw (max 1 (- w g))] [l (max 0 (- h g g))]
         [th (min l (max (* 2 (font-line-height 'ui)) (* size l)))])
    (list (list 'thumb x
                (+ y g (if (< size 1) (* (- l th) (/ start (- 1 size))) 0))
                tw th))))

(define (cons-scrollbar x y w h flags start size)
  (let* ([t (cdr (assq 'thumb (ui-scrollbar-areas x y w h start size)))]
         [g (cons-space)] [tw (caddr t)]
         [hot? (or (memq 'hover flags) (memq 'pressed flags))])
    (fill-box (+ x (quotient tw 2)) (+ y g) 1 (max 0 (- h g g)) 'text-faint)
    (fill-box x (cadr t) tw (cadddr t) (if hot? 'cons-ink 'window-bg))
    (cons-ring! x (cadr t) tw (cadddr t) 'cons-ink 1)))

;; A slider is a line, filled in accent up to its value; its knob a
;; small cell, bold under the mouse. A painted track (Settings' colors)
;; is a band under the knob.
(define (cons-slider x y w h flags frac paint)
  (let* ([cy (round (+ y (/ h 2)))] [kx (round (+ x (* frac w)))]
         [hot? (or (memq 'hover flags) (memq 'pressed flags))])
    (if paint
        (with-clip (x (- cy 3) w 6) (paint x (- cy 3) w 6))
        (begin (fill-box x cy w 1 'text-faint)
               (fill-box x (- cy 1) (max 0 (- kx x)) 2 'accent)))
    (fill-box (- kx 4) (- cy 7) 8 14 'window-bg)
    (cons-ring! (- kx 4) (- cy 7) 8 14 (if hot? 'accent 'cons-ink)
                 (if hot? 2 1))))

;; Progress is a cell filling with ink by the fraction; green when done.
(define (cons-progress x y w h flags frac)
  (when (> frac 0)
    (fill-box x y (* w (min 1 frac)) h (if (>= frac 1) 'green 'accent)))
  (cons-ring! x y w h 'cons-ink 1))

;; A column's heading, faint, its words underlined; the sort as a
;; pointer head; the words where a table's text is (ui-table-cell-inset).
(define (cons-table-header x y w h flags label dir)
  (let* ([sh (font-line-height 'ui-small)] [g (ui-small-glyph-size)]
         [tx (+ x (* 2 (cons-space)))]
         [s (text-fit label (max 0 (- w (* 3 (cons-space)) g)) 'ui-small)]
         [ty (+ y (/ (- h sh) 2))]
         [end (draw-text tx ty s (if (or dir (memq 'hover flags)) 'text
                                     'text-faint)
                         'ui-small)])
    (when (> (string-length s) 0)
      (fill-box tx (- (+ y h) (cons-space)) (- end tx) 1 'text-faint))
    (when dir
      (ui-draw-glyph (+ end 4) (+ y (/ (- h g) 2)) g g '((ink . cons-ink))
                     dir))))

;; Rows are the list's elements, a faint line under each, g in from the
;; table's left: the chosen one in the bold stroke, the mouse's with a
;; faint fill.
(define (cons-table-row x y w h flags)
  (let* ([g (cons-space)] [x (+ x g)] [w (- w g)])
    (cond [(memq 'selected flags) (cons-ring! x y w h 'accent 2)]
          [(memq 'hover flags) (fill-box x y w h (alpha 'cons-ink 0.08))])
    (fill-box x (- (+ y h) 1) w 1 (alpha 'text-faint 0.5))))

;; A tree is nested lists; a node's twisty is the pointer: a dot and an
;; arrow right while its children are hidden past it, down when they
;; show. Dimmed rows faint, as the kit dims them.
(define (cons-tree-row x y w h flags w0 depth)
  (let ([areas (ui-tree-areas x y w0 h depth)] [c (cons-cell)]
        [g (ui-glyph-size)])
    (ui-draw-table-row x y w h flags)
    (when (memq 'kids flags)
      (let* ([t (cdr (assq 'twisty areas))] [tx (car t)] [tw (caddr t)]
             [ink (if (memq 'hover flags) 'text 'cons-ink)])
        (if (memq 'expanded flags)
            (cons-down! (+ tx (/ (- tw 1) 2)) (+ y 7) (+ y h -5) c ink 1)
            (cons-right! (+ tx 5) (cons-dot-y y h 1) (+ tx tw -3) c ink 1))))
    (ui-draw-dim x y (- (cadr (assq 'cell areas)) x) h flags)))

;; Panes: a well is a faint box (the kit's views keep clear of it,
;; surface-well-ring), the rest the window's own background, a strip
;; ruled off where it meets the rest.
(define (cons-surface x y w h flags)
  (cond
    [(memq 'well flags) (cons-ring! x y w h 'text-faint 1)]
    [(memq 'nav flags) (fill-box (+ x w -1) y 1 h 'window-border)]
    [else
     (fill-box x y w h 'bg-1)
     (cond [(memq 'toolbar flags)
            (fill-box x (- (+ y h) 1) w 1 'window-border)]
           [(memq 'footer flags) (fill-box x y w 1 'window-border)]
           [(memq 'side flags) (fill-box x y 1 h 'window-border)])]))

;; A popup is an outlined box on the window's background, nothing under
;; it (drawn, not painted): a dialog's in the focused window's border, a
;; tooltip's faint, a menu's and a toast's in the plain ink.
(define (cons-panel x y w h flags)
  (fill-box x y w h 'window-bg)
  (cons-ring! x y w h
               (cond [(memq 'dialog flags) 'window-border-focus]
                     [(memq 'tooltip flags) 'text-faint]
                     [else 'cons-ink])))

;; The chosen entry of a list (Settings', the completion's): the bold
;; stroke; the mouse's, a plain box; a menu's by outline, as the kit
;; says, inverted while pressed.
(define (cons-highlight x y w h flags)
  (cond [(memq 'hover flags) (cons-ring! x y w h 'cons-ink 1)]
        [(not (memq 'outline flags)) (cons-ring! x y w h 'accent 2)]
        [(memq 'pressed flags) (fill-box x y w h 'cons-ink)]
        [else (cons-ring! x y w h 'cons-ink 1)]))

;; A faint line between groups (the completion's signature).
(define (cons-separator x y w h flags)
  (let ([my (+ y (/ h 2))]) (draw-line x my (+ x w) my 'text-faint)))

;; A tooltip is a string: a cell holding the text in quotes.
(define (cons-tooltip x y w h flags text)
  (let* ([lines (ui-tooltip-lines text)] [sh (font-line-height 'ui-small)]
         [mh (font-line-height 'mono-small)] [dy (/ (- sh mh) 2)]
         [q (text-width "\"" 'mono-small)] [g (cons-space)] [tx (+ x g q 2)]
         [last (list-ref lines (- (length lines) 1))]
         [ly (+ y 5 (* sh (- (length lines) 1)))])
    (ui-draw-panel x y w h '(tooltip))
    (draw-text (+ x g) (+ y 5 dy) "\"" 'text-faint 'mono-small)
    (fold-left (lambda (ty line)
                 (draw-text tx ty line 'text 'ui-small)
                 (+ ty sh))
               (+ y 5) lines)
    (draw-text (+ tx (text-width last 'ui-small) 2) (+ ly dy) "\""
               'text-faint 'mono-small)))

(define (cons-tooltip-size text)
  (let ([lines (ui-tooltip-lines text)])
    (values (+ 4 (* 2 (cons-space)) (* 2 (text-width "\"" 'mono-small))
               (min 280 (text-widest lines 'ui-small)))
            (+ 10 (* (length lines) (font-line-height 'ui-small))))))

;; A dialog is a window-shaped list, ("Delete TASK-16?" Cancel Delete): a
;; chain of cells across a title strip, as a window's, in the bold
;; accent; each button's cell is a car of the chain (cons-chain, the
;; dialog place), the last one's cdr holds nil, and clicking that end of
;; the list cancels, as closing a window does (the kit's dismiss area).
;; The message is in the box below the strip.
(define (cons-dialog-car label) (+ (* 2 (cons-space)) (text-width label 'ui)))

;; The chain after the title's car: its cdr, then each button's pointer,
;; car and cdr.
(define (cons-dialog-rest labels)
  (let ([c (cons-cell)] [a (cons-arrow)])
    (fold-left (lambda (acc l) (+ acc a (cons-dialog-car l) c)) c labels)))

(define (cons-dialog-size title message labels)
  (let* ([lh (font-line-height 'ui)] [left (cons-left)]
         [chain (+ left (text-width title 'title) (* 4/5 (cons-cell))
                   (cons-dialog-rest labels) left)]
         [pad (* 2 (cons-space))]
         [w (clamp (max (+ pad pad (text-width message 'ui)) (ceiling chain))
                   (* 20 lh) (* 32 lh))])
    (values w
            (round (+ (title-height) pad
                      (* lh (length (ui-dialog-lines message (- w pad pad))))
                      pad)))))

;; ((title x y w h) (message ..) (button x y w h) ... (dismiss x y w h)):
;; the chain across the strip from the left, the title's car taking what
;; the buttons leave; the dismiss area is the last cdr.
(define (cons-dialog-areas x y w h labels)
  (let* ([c (cons-cell)] [a (cons-arrow)] [th (title-height)]
         [left (cons-left)] [cy (+ y (quotient (- th c) 2))]
         [pad (* 2 (cons-space))]
         [tw (max c (- w left left (cons-dialog-rest labels)))])
    (let loop ([ls labels] [bx (+ x left tw c)] [acc '()])
      (if (null? ls)
          (append (list (list 'title (+ x left) cy tw c)
                        (list 'message (+ x pad) (+ y th pad) (- w pad pad)
                              (- h th pad pad)))
                  (reverse acc)
                  (list (list 'dismiss (- bx c) cy c c)))
          (let ([bw (cons-dialog-car (car ls))])
            (loop (cdr ls) (+ bx a bw c)
                  (cons (list 'button (+ bx a) cy bw c) acc)))))))

;; flags: (labels . the buttons'), and the dismiss area's state: nil
;; fills red under the mouse, its slash crossed out, as the title's.
(define (cons-dialog x y w h flags title message)
  (let* ([c (cons-cell)] [th (title-height)] [lw 2] [ink 'accent]
         [labels (let ([l (cons-flag flags 'labels)]) (if l (cdr l) '()))]
         [areas (ui-dialog-areas x y w h labels)]
         [t (cdr (assq 'title areas))] [m (cdr (assq 'message areas))]
         [cars (map cdr (filter (lambda (a) (eq? (car a) 'button)) areas))]
         [cy (cadr t)] [tw (caddr t)]
         [close (cons-tint-of flags 'button-close)]
         [s (text-fit title (- tw (* 4/5 c)) 'title)])
    (ui-draw-panel x y w h '(dialog))
    (fill-box x (+ y th -1) w 1 'window-border)
    (cons-pair! (car t) cy tw c ink lw #f #f)
    (draw-text (+ (car t) (floor (/ (- tw (text-width s 'title)) 2)))
               (cons-title-y cy c) s 'title-text 'title)
    ;; from each cdr a pointer to the next car, whose cell its button
    ;; draws, and that car's cdr; the last cdr nil
    (let loop ([cx (+ (car t) tw)] [cars cars])
      (if (null? cars)
          (begin
            (when close
              (fill-box cx (+ cy lw) (- c lw) (- c lw lw) close))
            (cons-nil! cx cy c ink lw (and close 'window-bg)))
          (let* ([b (car cars)] [nx (+ (car b) (caddr b))])
            (cons-right! (cons-dot-x cx c lw) (cons-dot-y cy c lw) (car b) c
                         ink lw)
            (cons-ring! (- nx lw) cy (+ c lw) c ink lw)
            (loop nx (cdr cars)))))
    (fold-left (lambda (ly line) (draw-text (car m) ly line 'text-dim 'ui)
                 (+ ly (font-line-height 'ui)))
               (cadr m) (ui-dialog-lines message (caddr m)))))

;; Under a dialog: the window faintly veiled.
(define (cons-scrim x y w h flags) (fill-box x y w h (alpha 'bg-0 0.4)))

;; A day is a cell: the chosen one filled, today bold, the keyboard's
;; bold in ink, another month's faint, the mouse's filled with ink.
(define (cons-day x y w h flags label)
  (let* ([on? (lambda (f) (memq f flags))] [s (- (min w h) (cons-space))]
         [cx (+ x (/ (- w s) 2))] [cy (+ y (/ (- h s) 2))]
         [sel? (on? 'selected)]
         [ink (cond [(or sel? (on? 'today)) 'accent]
                    [(on? 'outside) 'text-faint]
                    [else 'cons-ink])]
         [tint (cond [sel? 'accent] [(on? 'hover) ink] [else #f])])
    (when tint (fill-box cx cy s s tint))
    (cons-ring! cx cy s s ink (if (or (on? 'today) (on? 'cursor)) 2 1))
    (text-draw-centered x y w h label
                        (cond [tint 'window-bg]
                              [(on? 'outside) 'text-faint]
                              [else 'text])
                        'ui)))

;; A person is a cell with the initials, in the person's color.
(define (cons-avatar x y w h flags name)
  (let ([color (app-color (string->symbol (string-downcase name)))])
    (cons-ring! x y w w color 1)
    (text-draw-centered x y w w (ui-initials name) color 'ui-small)))

;;; Tasks' board: a column is a list of cards.

;; The pointer between two cards is the room between them.
;; The cards g from the well's sides and from its heading, the + g from
;; the heading's end; between two cards, a pointer.
(define (cons-tasks-column-insets)
  (let ([g (cons-space)]) (values g g (cons-arrow) g)))

;; A heading a cell high, g above and below it: the + cell sits g inside
;; the well's corner.
(define (cons-tasks-column-header-height) (+ (cons-cell) (* 2 (cons-space))))

;; A card's cdr stands at its right, a cell wide; past it the room the
;; scroll bar keeps (its margin g, its thumb, and g to the well's edge).
(define (cons-tasks-card-insets)
  (let ([g (cons-space)])
    (values (max g (ui-scrollbar-inset 'left))
            (+ (cons-cell) (max g (ui-scrollbar-inset 'right))))))

;; Inside a card everything is g from its edges; a table's text g inside
;; its row's box, which is g inside the table.
(define (cons-tasks-card-pad) (cons-space))
(define (cons-table-cell-inset) (* 2 (cons-space)))

;; The details' margin, the pad.
(define (cons-tasks-details-pad) (* 2 (cons-space)))

;; Each card's cdr beside it, sharing its edge; from the dot in it a
;; pointer down to the next card's, the last one's holding nil; a chosen
;; or dragged card's in the bold stroke, as its box.
(define (cons-tasks-link x y w h flags gap last?)
  (let* ([c (cons-cell)]
         [bold? (or (memq 'selected flags) (memq 'floating flags))]
         [ink (if bold? 'accent 'cons-ink)] [lw (if bold? 2 1)])
    (cons-ring! (+ x w (- lw)) y (+ c lw) h ink lw)
    (if last?
        (cons-nil-h! (+ x w) y c h ink lw #f)
        (cons-down! (cons-dot-x (+ x w) c lw) (cons-dot-y y h lw) (+ y h gap)
                    c ink lw))))

;; A column's well and heading: its status dot g in, its name and its
;; count g apart; empty, it shows ().
(define (cons-tasks-column x y w h flags status label count)
  (let* ([hh (tasks-column-header-height)] [g (cons-space)]
         [m (tasks-mark-size)] [lh (font-line-height 'ui-bold)]
         [sh (font-line-height 'ui-small)])
    (ui-draw-surface x y w h '(well))
    (let* ([dw (tasks-draw-mark (+ x g) (+ y (/ (- hh m) 2)) m 'status status)]
           [end (draw-text (if (> dw 0) (+ x g m g) (+ x g))
                           (+ y (/ (- hh lh) 2)) label 'text 'ui-bold)])
      (draw-text (+ end g) (+ y (/ (- hh sh) 2)) (number->string count)
                 'text-faint 'ui-small))
    (when (memq 'empty flags)
      (text-draw-centered x (+ y hh) w (min 120 (- h hh)) "()" 'text-faint
                          'mono))))

;; Dashes of 4 and gaps of 3 along the four edges of a box.
(define (cons-dashes! x y w h color)
  (do ([i 0 (+ i 7)]) ((>= i w))
    (let ([d (min 4 (- w i))])
      (fill-box (+ x i) y d 1 color)
      (fill-box (+ x i) (+ y h -1) d 1 color)))
  (do ([i 0 (+ i 7)]) ((>= i h))
    (let ([d (min 4 (- h i))])
      (fill-box x (+ y i) 1 d color)
      (fill-box (+ x w -1) (+ y i) 1 d color))))

;; Where a dragged card would land: a dashed pair.
(define (cons-tasks-slot x y w h)
  (cons-dashes! x y w h 'accent)
  (cons-dashes! (+ x w -1) y (+ (cons-cell) 1) h 'accent))

;;; The desktop layer: menus, the bars, toasts, the wallpaper.

;; A menu is a list drawn vertically: each entry a pair, its car the
;; entry and its cdr a cell at the right whose pointer goes down to the
;; next pair; the last one's holds nil; a separator is a longer pointer.
;; An entry's row is its pair and the gap below it (menu-item-height);
;; the filter's field, when it has one, is above.
(define (cons-menu-areas m)
  (let* ([es (menu-entries m)] [c (cons-cell)] [ih (theme 'menu-item-height)]
         [sh (theme 'menu-separator-height)] [pad (theme 'menu-pad)]
         [tx (theme 'menu-text-x)] [font (theme 'menu-font)]
         [head (if (menu-filter? m) (+ (ui-control-height) pad) 0)]
         [w (fold-left (lambda (acc e)
                         (if (pair? e)
                             (max acc (+ pad tx (text-width (car e) font) tx c
                                         pad))
                             acc))
                       (theme 'menu-min-width) es)]
         [h (fold-left (lambda (acc e) (+ acc (if (pair? e) ih sh)))
                       (+ pad pad head (- c ih)) es)]
         [x (clamp (menu-x m) 4 (- (screen-w) w 4))]
         [y (let-values ([(dx dy dw dh) (desktop-rect)])
              (clamp (menu-y m) (+ 2 dy) (- (screen-h) h 4)))])
    (cons (list 'menu x y w h)
          (append (if (menu-filter? m)
                      (list (list 'filter (+ x pad) (+ y pad) (- w pad pad)
                                  (ui-control-height)))
                      '())
                  (let loop ([es es] [i 0] [ey (+ y pad head)])
                    (if (null? es)
                        '()
                        (let ([eh (if (pair? (car es)) ih sh)])
                          (cons (list (if (pair? (car es)) i 'separator)
                                      x ey w eh)
                                (loop (cdr es) (+ i 1) (+ ey eh))))))))))

;; The entry under the mouse, or the keys', fills with ink; while a
;; button is held on it, at 0.6; blinking, in its on phases.
(define (cons-draw-menu)
  (when *menu*
    (with-place 'menu
      (lambda ()
        (let* ([m *menu*] [areas (menu-areas m)]
               [es (list->vector (menu-entries m))] [font (theme 'menu-font)]
               [lh (font-line-height font)] [c (cons-cell)]
               [pad (theme 'menu-pad)] [tx (theme 'menu-text-x)]
               [f (assq 'filter areas)] [b *menu-blink*])
          (apply ui-draw-panel (append (cdar areas) '((menu))))
          (when f
            (apply (lambda (fx fy fw fh) (cons-menu-filter! m fx fy fw fh))
                   (cdr f)))
          (let loop ([as (cdr areas)])
            (unless (null? as)
              (let ([a (car as)])
                (when (fixnum? (car a))
                  (apply
                   (lambda (i x y w h)
                     (let* ([next (find (lambda (a) (fixnum? (car a)))
                                        (cdr as))]
                            [sel? (if b   ; blinking: on in odd phases
                                      (and (= i (cadr b))
                                           (odd? (menu-phase b)))
                                      (= i (menu-sel m)))]
                            [tint (and sel?
                                       (if (memq 'pressed (menu-entry-flags i))
                                           (alpha 'cons-ink 0.6)
                                           'cons-ink))]
                            [px (+ x pad)] [pw (- w pad pad c)])
                       (cons-pair-h! px y pw c c 'cons-ink 1 tint #f)
                       (draw-text (+ px tx) (+ y (/ (- c lh) 2))
                                  (text-fit (car (vector-ref es i)) (- pw tx 4)
                                            font)
                                  (if tint 'window-bg (theme 'menu-ink)) font)
                       (if next
                           (cons-down! (cons-dot-x (+ px pw) c 1)
                                       (cons-dot-y y c 1) (caddr next) c
                                       'cons-ink 1)
                           (cons-nil! (+ px pw) y c 'cons-ink 1 #f))))
                   a))
                (loop (cdr as))))))))))

;; The launcher's filter: a string being typed, in the focused box.
(define (cons-menu-filter! m x y w h)
  (let* ([font (theme 'menu-font)] [lh (font-line-height font)]
         [f (menu-filter m)] [ty (+ y (/ (- h lh) 2))]
         [a (car (ui-text-box-areas x y w h '()))] [tx (cadr a)]
         [tw (cadddr a)])
    (ui-draw-field x y w h '(focused))
    (if (string=? f "")
        (draw-text tx ty "Type to filter…" 'text-faint font)
        (with-clip (tx y tw h)
          (let ([ex (draw-text (min tx (- (+ tx tw) 3 (text-width f font)))
                               ty f 'text font)])
            (fill-box (+ ex 1) (+ y (round (/ (- h lh 1) 2))) 1.5
                        (round (+ lh 1)) 'accent))))))

;; The mouse documentation as the data it is, in the code font:
;; ((L . "Select") (R . "Task menu")).
(define (cons-mouse-doc-text doc) (format "~s" doc))

;; The top bar as the built-in one, and after the title the mouse
;; documentation, faint, in what room the status leaves.
(define (cons-draw-topbar)
  (with-place 'bar
    (lambda ()
      (let* ([w (screen-w)] [h (topbar-height)] [areas (topbar-areas)]
             [ty (/ (- h (font-line-height 'ui)) 2)]
             [gap (max 11 (round (* 0.6 (font-line-height 'ui))))]
             [dot-w (text-width "·" 'ui)]
             [l (assq 'launcher areas)] [t (assq 'title areas)])
        (fill-box 0 0 w h (alpha 'panel 0.92))
        (draw-line 0 (- h 0.5) w (- h 0.5) (alpha 'panel-text 0.12))
        (when l
          (apply (lambda (x y lw lh)
                   (when (or (equal? *hover* '(surface topbar launcher))
                             (launcher-open?))
                     (fill-box (+ x 6) (+ y 4) (- lw 6) (- lh 8) 'panel-hover))
                   (draw-text (+ x 18) (+ y ty) "λ  Schevana" 'panel-accent
                              'ui-bold))
                 (cdr l)))
        (let* ([title-end
                (if t
                    (draw-text (+ (cadr t) 14) (+ (caddr t) ty)
                               (if *focus* (window-title *focus*) "Desktop")
                               'panel-text 'ui-bold)
                    0)]
               ;; the status from the right, while it fits beside the title
               [left (let loop ([segs (reverse (shown-status-strings))]
                                [x (- w 14)]
                                [first? #t])
                       (if (null? segs)
                           x
                           (let* ([s (car segs)]
                                  [right (if first? x (- x gap dot-w gap))]
                                  [x0 (- right (text-width s 'ui))])
                             (if (> x0 (+ title-end gap gap))
                                 (begin
                                   (unless first?
                                     (draw-text (- x gap dot-w) ty "·"
                                                'panel-dim 'ui))
                                   (draw-text x0 ty s 'panel-text 'ui)
                                   (loop (cdr segs) x0 #f))
                                 x))))]
               [doc (mouse-doc)])
          (unless (or (null? doc) (< (- left title-end) 120))
            (draw-text (+ title-end 24)
                       (/ (- h (font-line-height 'mono-small)) 2)
                       (text-fit (mouse-doc-text doc) (- left title-end 48)
                                 'mono-small)
                       'panel-dim 'mono-small)))))))

;; The taskbar's windows are a list, [Tasks|•]→[REPL|•]→[Clock|/]: each
;; window's area its pair and its pointer; a car as wide as its title and
;; a little, at most 160, narrower when the chain would not fit. The hint,
;; a comment, at the right while the chain leaves it room.
(define (cons-taskbar-areas)
  (let* ([w (screen-w)] [h (taskbar-height)] [y0 (- (screen-h) h)]
         [ws (sort (lambda (a b) (< (window-id a) (window-id b))) *windows*)]
         [n (length ws)] [c (cons-cell)] [a (cons-arrow)]
         [g (cons-space)]
         [hint-w (+ g g g g (text-width (string-append "; " taskbar-hint)
                                   'mono-small))]
         [cars (map (lambda (win)
                      (min 160 (+ g g (ceiling (text-width (window-title win)
                                                          'ui)))))
                    ws)]
         [chain (apply + (map (lambda (cw) (+ cw c a)) cars))]
         [hint? (<= (+ chain hint-w) (- w g g g g))]
         [room (- w g g g g (if hint? hint-w 0))]
         [cars (if (or (<= chain room) (zero? n))
                   cars
                   (let ([per (max c (floor (/ (- room (* n (+ c a))) n)))])
                     (map (lambda (cw) (min cw per)) cars)))])
    (append (if hint? (list (list 'hint (- w hint-w) y0 hint-w h)) '())
            (let loop ([ws ws] [cars cars] [x (+ g g)])
              (if (null? ws)
                  '()
                  (cons (list (car ws) x y0 (+ (car cars) c a) h)
                        (loop (cdr ws) (cdr cars) (+ x (car cars) c a))))))))

;; The focused window's car filled with the panel's accent, a minimized
;; one faint, the mouse's filled with the plain ink.
(define (cons-draw-taskbar)
  (with-place 'bar
    (lambda ()
      (let* ([w (screen-w)] [h (taskbar-height)] [y0 (- (screen-h) h)]
             [c (cons-cell)] [a (cons-arrow)] [cy (+ y0 (quotient (- h c) 2))]
             [lh (font-line-height 'ui)] [areas (taskbar-areas)]
             [hint (assq 'hint areas)])
        (fill-box 0 y0 w h (alpha 'panel 0.94))
        (draw-line 0 (+ y0 0.5) w (+ y0 0.5) (alpha 'panel-text 0.12))
        (when hint
          (draw-text (+ (cadr hint) (* 2 (cons-space)))
                     (+ y0 (/ (- h (font-line-height 'mono-small)) 2))
                     (string-append "; " taskbar-hint) 'panel-dim 'mono-small))
        (let loop ([as (filter (lambda (a) (window? (car a))) areas)])
          (unless (null? as)
            (apply
             (lambda (win x y bw bh)
               (let* ([cw (- bw c a)] [focused? (eq? win *focus*)]
                      [hover? (equal? *hover* (list 'surface 'taskbar win))]
                      [min? (not (visible? win))]
                      [ink (cond [focused? 'panel-accent]
                                 [min? 'panel-dim]
                                 [else 'cons-ink])]
                      [tint (and (or focused? hover?) ink)]
                      [s (text-fit (window-title win) (- cw 8) 'ui)])
                 (cons-pair! x cy cw c ink 1 tint #f)
                 (draw-text (+ x (floor (/ (- cw (text-width s 'ui)) 2)))
                            (+ cy (/ (- c lh) 2)) s
                            (cond [tint 'panel] [min? 'panel-dim]
                                  [else 'panel-text])
                            'ui)
                 (if (null? (cdr as))
                     (cons-nil! (+ x cw) cy c ink 1 #f)
                     (cons-pointer! (+ x cw) (cadr (cadr as)) cy c ink 1))))
             (car as))
            (loop (cdr as))))))))

;; Toasts are a list at the top right: each a pair, its car the text, the
;; dot in its cdr the notification's color, its pointer down to the next.
(define (cons-toast-boxes)
  (let ([c (cons-cell)] [a (cons-arrow)]
        [h (max (cons-cell) (round (+ (font-line-height 'ui) 10)))])
    (let-values ([(dx dy dw dh) (desktop-rect)])
      (let loop ([ts *toasts*] [y (+ dy (* 2 (cons-space)))] [acc '()])
        (if (null? ts)
            (reverse acc)
            (let* ([t (car ts)]
                   [text (text-fit (vector-ref t 1) (- (screen-w) 120) 'ui)]
                   [tw (+ (* 4 (cons-space)) c
                          (ceiling (text-width text 'ui)))])
              (loop (cdr ts) (+ y h a)
                    (cons (vector (- (+ dx dw) tw (* 2 (cons-space))) y tw h
                                  text
                                  (vector-ref t 2))
                          acc))))))))

(define (cons-draw-toasts)
  (with-place 'toast
    (lambda ()
      (let ([c (cons-cell)] [lh (font-line-height 'ui)])
        (let loop ([bs (toast-boxes)])
          (unless (null? bs)
            (let* ([b (car bs)] [x (vector-ref b 0)] [y (vector-ref b 1)]
                   [tw (vector-ref b 2)] [h (vector-ref b 3)] [cw (- tw c)])
              (fill-box x y tw h 'window-bg)
              (cons-pair-h! x y cw h c 'cons-ink 1 #f #f)
              (draw-text (+ x (* 2 (cons-space))) (+ y (/ (- h lh) 2))
                         (vector-ref b 4) 'text
                         'ui)
              (if (null? (cdr bs))
                  (cons-nil-h! (+ x cw) y c h 'cons-ink 1 #f)
                  (let ([dx (cons-dot-x (+ x cw) c 1)] [my (cons-dot-y y h 1)])
                    (cons-down! dx my (vector-ref (cadr bs) 1) c 'cons-ink 1)
                    (fill-circle dx my (+ (/ c 10) 1/2) (vector-ref b 5))))
              (loop (cdr bs)))))))))

;; The desktop: the wallpaper, and on it, faint, the world as data:
;; (λ "S C H E V A N A"), a chain of two cells ending in nil.
(define (cons-draw-wallpaper w h)
  (fill-wallpaper 0 0 w h (theme 'wallpaper) 'desktop-top 'desktop-bottom)
  (let* ([ink (alpha 'watermark 0.08)] [lw 2]
         [s (round (* 0.38 (min w h)))] [c (round (/ s 3))]
         [a (round (* 0.7 c))]
         [name "S C H E V A N A"]
         [nw (+ 40 (ceiling (text-width name 'ui-bold)))]
         [x0 (round (/ (- w s c a nw c) 2))] [y0 (round (/ (- h s) 2))]
         [x1 (+ x0 s c a)] [y1 (+ y0 (round (/ (- s c) 2)))])
    (cons-pair-h! x0 y0 s s c ink lw #f #f)
    (text-draw-centered x0 y0 s s "λ" ink 'huge)
    (cons-right! (cons-dot-x (+ x0 s) c lw) (cons-dot-y y0 s lw) x1 c ink lw)
    (cons-pair-h! x1 y1 nw c c ink lw #f #f)
    (text-draw-centered x1 y1 nw c name ink 'ui-bold)
    (cons-nil! (+ x1 nw) y1 c ink lw #f)))

(define-style cons "Cons"
  ;; square, and so is everything drawn in it (rrect-path!); every common
  ;; option but the radius
  'corner-radius 0
  'options (remq 'corner-radius (map car common-options))
  'frame-regions 'cons-regions
  'frame-under 'cons-draw-under
  'frame-over 'cons-draw-over
  ;; the desktop: a flat ground, the world drawn faint on it
  'wallpaper 'flat
  'draw-wallpaper 'cons-draw-wallpaper
  ;; drawn, not painted: cards and panels on the window's own background
  'bg-2 (theme-rule (theme 'bg-1))
  'surface-well-ring 1
  ;; the spacing (above): g between neighbors, the pad a window's margin,
  ;; a scroll bar a thumb g wide and g to its edge, g clear of content
  'gap (theme-rule (cons-space))
  'pad (theme-rule (* 2 (cons-space)))
  'scrollbar-width (theme-rule (* 2 (cons-space)))
  'scrollbar-margin (theme-rule (cons-space))
  'text-selection 'underline
  ;; the bars: the mouse documentation as data in the top bar, the
  ;; windows as a list in the taskbar
  'mouse-doc #t
  'mouse-doc-text 'cons-mouse-doc-text
  'draw-topbar 'cons-draw-topbar
  'taskbar-areas 'cons-taskbar-areas
  'draw-taskbar 'cons-draw-taskbar
  'toast-boxes 'cons-toast-boxes
  'draw-toasts 'cons-draw-toasts
  ;; the menus: a pair a cell high, a pointer to the next, g inside
  'menu-areas 'cons-menu-areas
  'draw-menu 'cons-draw-menu
  'menu-item-height (theme-rule (+ (cons-cell) (cons-arrow)))
  'menu-separator-height (theme-rule (cons-arrow))
  'menu-pad (theme-rule (cons-space))
  'menu-text-x (theme-rule (cons-space))
  'menu-min-width 150
  'menu-ink 'text
  ;; in a dialog every button is a cell of its chain
  'cons-chain #f
  'places '((dialog cons-chain #t))
  ;; the widgets
  'ui-draw-focus 'cons-focus
  'ui-draw-button 'cons-button
  'ui-button-size 'cons-button-size
  'ui-draw-checkbox 'cons-checkbox
  'ui-checkbox-size 'cons-checkbox-size
  'ui-draw-toggle 'cons-toggle
  'ui-toggle-size 'cons-checkbox-size
  'ui-draw-tab 'cons-tab
  'ui-tabs-size 'cons-tabs-size
  'ui-draw-field 'cons-field
  'ui-text-box-areas 'cons-text-box-areas
  'ui-draw-dropdown 'cons-dropdown
  'ui-dropdown-size 'cons-dropdown-size
  'ui-draw-chip 'cons-chip
  'ui-chip-size 'cons-chip-size
  'ui-chip-areas 'cons-chip-areas
  'ui-chip-input-areas 'cons-chip-input-areas
  'ui-draw-card 'cons-card
  'ui-draw-scrollbar 'cons-scrollbar
  'ui-scrollbar-areas 'cons-scrollbar-areas
  'ui-draw-slider 'cons-slider
  'ui-draw-progress 'cons-progress
  'ui-draw-table-header 'cons-table-header
  'ui-draw-table-row 'cons-table-row
  'ui-draw-tree-row 'cons-tree-row
  'ui-draw-surface 'cons-surface
  'ui-draw-panel 'cons-panel
  'ui-draw-highlight 'cons-highlight
  'ui-draw-separator 'cons-separator
  'ui-draw-tooltip 'cons-tooltip
  'ui-tooltip-size 'cons-tooltip-size
  'ui-draw-dialog 'cons-dialog
  'ui-dialog-size 'cons-dialog-size
  'ui-dialog-areas 'cons-dialog-areas
  'ui-draw-scrim 'cons-scrim
  'ui-draw-day 'cons-day
  'ui-draw-avatar 'cons-avatar
  ;; Tasks' board
  'tasks-column-insets 'cons-tasks-column-insets
  'tasks-column-header-height 'cons-tasks-column-header-height
  'tasks-card-pad 'cons-tasks-card-pad
  'ui-table-cell-inset 'cons-table-cell-inset
  'tasks-details-pad 'cons-tasks-details-pad
  'tasks-card-insets 'cons-tasks-card-insets
  'tasks-draw-link 'cons-tasks-link
  'tasks-draw-column 'cons-tasks-column
  'tasks-draw-slot 'cons-tasks-slot)
