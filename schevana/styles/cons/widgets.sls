;;; (schevana styles cons widgets) — a part of the Cons style ((schevana
;;; styles cons)): the widgets as Lisp data, drawn as the title is:
;;; buttons, check boxes and toggles, tabs, fields and dropdowns, chips,
;;; cards, scroll bars, sliders and progress, tables, trees and surfaces.

(library (schevana styles cons widgets)
  (export
    cons-arrow cons-button cons-button-size cons-card cons-checkbox
    cons-checkbox-size cons-chip cons-chip-areas cons-chip-input-areas
    cons-chip-size cons-dropdown cons-dropdown-size cons-field cons-flag
    cons-focus cons-highlight cons-panel cons-progress cons-scrollbar
    cons-scrollbar-areas cons-separator cons-slider cons-space cons-surface
    cons-tab cons-table-header cons-table-row cons-tabs-size
    cons-text-box-areas cons-tint-of cons-toggle cons-tree-row)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) alpha draw-line draw-text fill-box fill-circle
                fill-polygon font font-line-height text-width theme with-clip)
          (only (schevana kits text) text-widest text-draw-centered text-fit)
          (only (schevana kits ui) ui-draw-dim ui-draw-table-row ui-tree-areas
                ui-scrollbar-areas ui-flow ui-chip-size ui-small-glyph-size
                ui-text-box-top ui-scrollbar-width ui-text-box-areas
                ui-control-height ui-checkbox-box ui-button-size* ui-draw-glyph
                ui-glyph-size)
          (schevana styles cons cells))

  (library-layer looks)

  ;; The spacing, from the cell c (20 at the default fonts), each length
  ;; even so that it lands on whole device pixels at 150 % too:
  ;;   g = 0.3 c (6): between two neighbors, and from the edge of the cell
  ;;       or box a thing sits in (a card in its column, a + in a heading,
  ;;       text in a cell);
  ;;   a = 0.7 c (14): between two things a pointer links (cards, chips,
  ;;       tabs, menu entries, toasts), as in the title bar;
  ;;   the pad, 2 g: a window's or a dialog's own margin.
  ;; A scroll bar is a thumb g wide, with g between it and the edge it lies
  ;; against; what scrolls keeps g clear of it (scrollbar-margin), and the
  ;; thumb keeps g from the ends of its view. Things touch only where the
  ;; diagram says so: a pointer meets its cell, and a cdr shares its car's
  ;; edge.
  (define (cons-space) (* 2 (round (* 3/20 (cons-cell)))))
  (define (cons-arrow) (* 2 (round (* 7/20 (cons-cell)))))
  ;; A cdr is square in the title's pairs, a menu's and a chip's; in a
  ;; control as tall as a button (a tab, a dropdown) it is a slot as wide
  ;; as a pointer is long, so that a toolbar of them stays a row.
  (define (cons-slot) (cons-arrow))

  ;; A cell's fill by its state: its ink under the mouse, at 0.6 while
  ;; pressed, and none otherwise, nor while it is disabled.
  (define (cons-tint-of flags ink)
    (cond [(memq 'disabled flags) #f]
          [(memq 'pressed flags) (alpha ink 0.6)]
          [(memq 'hover flags) ink]
          [else #f]))

  ;; The focus: the bold stroke, a box 2 pixels thick in accent ink.
  (define (cons-focus x y w h flags r) (cons-ring! x y w h 'accent 2))

  ;; A button is a cell with its word, or its glyph, in it. The default
  ;; one (primary), a focused one, and every one in a dialog's chain
  ;; (cons-chain, set by the dialog place) have the bold accent stroke; a
  ;; dangerous one has red ink; a quiet one is faint and fills with the
  ;; plain ink under the mouse; a disabled one is faint and does not
  ;; respond to the mouse.
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

  ;; A button with a glyph alone (a +, a ×) is a cell square; one with a
  ;; word is as wide as the kit makes it.
  (define (cons-button-size label glyph)
    (if label
        (ui-button-size* label glyph)
        (let ([c (cons-cell)]) (values c c))))

  ;; A boolean is a cell holding #t or #f, in the code font: a checkbox is
  ;; one, and so is a toggle. #t is in accent ink and #f dim; the cell is as
  ;; high as the kit's box and a little wider than the literal, and bold
  ;; when focused. cons-bool! returns the cell's width.
  (define (cons-bool-width) (round (+ 8 (text-width "#f" 'mono))))

  (define (cons-bool! x y h flags on?)
    (let* ([bw (cons-bool-width)] [b (ui-checkbox-box)]
           [by (+ y (floor (/ (- h b) 2)))]
           [focused? (memq 'focused flags)] [off? (memq 'disabled flags)]
           [ink (cond [off? 'text-faint] [focused? 'accent] [else 'cons-ink])]
           [tint (cons-tint-of flags ink)])
      (when tint (fill-box x by bw b tint))
      (cons-ring! x by bw b ink (if focused? 2 1))
      (text-draw-centered x by bw b (if on? "#t" "#f")
                          (cond [tint 'window-bg] [off? 'text-faint]
                                [on? 'accent] [else 'text-dim])
                          'mono)
      bw))

  ;; A boolean's label: faint while disabled, else the given ink.
  (define (cons-bool-label-ink flags ink)
    (if (memq 'disabled flags) 'text-faint ink))

  ;; A checkbox: the boolean, then its label, dim once it is #t (a
  ;; checklist's done items).
  (define (cons-checkbox x y w h flags label)
    (let ([bw (cons-bool! x y h flags (memq 'checked flags))]
          [lh (font-line-height 'ui)])
      (when label
        (draw-text (+ x bw (cons-space)) (+ y (/ (- h lh) 2))
                   (text-fit label (- w bw (cons-space)) 'ui)
                   (cons-bool-label-ink flags
                                        (if (memq 'checked flags)
                                            'text-dim
                                            'text))
                   'ui))))

  (define (cons-checkbox-size label)
    (values (+ (cons-bool-width) (cons-space) (text-width label 'ui))
            (ui-control-height)))

  ;; A toggle ("Show done"): the same boolean, its label plain whatever
  ;; its value.
  (define (cons-toggle x y w h flags label)
    (let ([bw (cons-bool! x y h flags (memq 'checked flags))]
          [lh (font-line-height 'ui)])
      (when label
        (draw-text (+ x bw (cons-space)) (+ y (/ (- h lh) 2))
                   (text-fit label (- w bw (cons-space)) 'ui)
                   (cons-bool-label-ink flags 'text) 'ui))))

  ;; Tabs are a list of symbols, [Board|•]→[List|•]→[Tree|/]: each tab is a
  ;; pair whose car is the word and whose cdr points to the next; the last
  ;; one's cdr (the kit says which tab is last) holds nil. The current
  ;; tab's car is filled; the chain stays in the plain ink, and is bold in
  ;; accent ink while a tab has the keyboard.
  (define (cons-tab-car label) (+ (* 2 (cons-space)) (text-width label 'ui)))

  (define (cons-tab x y w h flags label)
    (let* ([c (cons-slot)] [cw (- w c (cons-arrow))]
           [on? (lambda (f) (memq f flags))]
           [bold? (on? 'focused)] [off? (on? 'disabled)]
           [ink (cond [off? 'text-faint] [bold? 'accent] [else 'cons-ink])]
           [lw (if bold? 2 1)]
           [tint (cond [(on? 'selected) (if off? 'text-faint 'accent)]
                       [else (cons-tint-of flags ink)])])
      (cons-pair-h! x y cw h c ink lw tint #f)
      (text-draw-centered x y cw h (text-fit label (- cw 8) 'ui)
                          (cond [tint 'window-bg] [off? 'text-faint]
                                [else 'text])
                          'ui)
      (if (on? 'last)
          (cons-nil-h! (+ x cw) y c h ink lw #f)
          (cons-right! (cons-dot-x (+ x cw) c lw) (cons-dot-y y h lw) (+ x w)
                       (cons-cell) ink lw))))

  ;; Each tab is its car, its cdr and its pointer, as high as a control, so
  ;; that a row of them lines up with the buttons.
  (define (cons-tabs-size labels)
    (values (fold-left (lambda (acc l)
                         (+ acc (cons-tab-car l) (cons-slot) (cons-arrow)))
                       0 labels)
            (ui-control-height)))

  ;; A text box holds a literal, and its marks frame the box: the opening
  ;; mark at its top-left corner and the closing one at its bottom-right,
  ;; in faint ink, for a field, an area of lines (clear of its scroll bar)
  ;; and a box of chips alike. A string is in quotes; a box of chips
  ;; (chips) holds a list, in parens, with the field for its next element
  ;; inside it. The focused box has the bold stroke. A search box shows its
  ;; magnifying glass instead of marks.
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
      (cons-ring! x y w h
                  (cond [focused? 'accent] [(on? 'disabled) 'text-faint]
                        [else 'cons-ink])
                  (if focused? 2 1))
      (unless (on? 'search)
        (draw-text (+ x g) (+ ty dy) open 'text-faint 'mono)
        (draw-text (- (+ x w) g bw (text-width close 'mono))
                   (+ (- (+ y h) g lh) dy) close 'text-faint 'mono))))

  ;; The marks sit g from the box's edges, and the text half a g past them
  ;; (a mark's glyph has little room of its own); in a box of lines the
  ;; closing mark keeps g clear of the scroll bar, which lies along the
  ;; box's right edge.
  (define (cons-mark-room) (+ (cons-space) (cons-mark-width)
                              (quotient (cons-space) 2)))

  (define (cons-text-box-areas x y w h flags)
    (let* ([bw (ui-scrollbar-width)] [g (cons-space)] [m (cons-mark-room)]
           ;; no room inside another box's marks (a chip input's field)
           [left (cond [(memq 'search flags) (+ (ui-glyph-size) g g)]
                       [(memq 'inner flags) 0]
                       [else m])]
           [right (cond [(memq 'search flags) g]
                        [(memq 'lines flags) (+ bw m)]
                        [else m])]
           [font (if (memq 'large flags) 'heading 'ui)]
           [top (ui-text-box-top h flags font g)])
      (list (list 'edit (+ x left) (+ y top) (max 0 (- w left right))
                  (max 0 (- h top top)) font)
            (list 'bar (- (+ x w) bw) y bw h))))

  ;; A dropdown is a pair whose car holds the current value and whose
  ;; cdr's pointer leaves it downward: that pointer is the arrow. While the
  ;; dropdown is open, its cdr fills and the menu below continues the
  ;; chain; a filter in use (set) is bold accent; with no value, it shows a
  ;; faint placeholder.
  (define (cons-dropdown x y w h flags label)
    (let* ([c (cons-slot)] [cw (- w c)] [on? (lambda (f) (memq f flags))]
           [off? (on? 'disabled)]
           [bold? (or (on? 'set) (on? 'open) (on? 'focused))]
           [ink (cond [off? 'text-faint] [bold? 'accent] [else 'cons-ink])]
           [lw (if bold? 2 1)]
           [tint (cons-tint-of flags ink)]
           [lh (font-line-height 'ui)])
      (cons-pair-h! x y cw h c ink lw tint (and (on? 'open) ink))
      (draw-text (+ x (cons-space)) (+ y (/ (- h lh) 2))
                 (text-fit label (- cw (* 2 (cons-space))) 'ui)
                 (cond [tint 'window-bg]
                       [(or off? (on? 'placeholder)) 'text-faint]
                       [(on? 'set) 'accent]
                       [else 'text])
                 'ui)
      (cons-down! (cons-dot-x (+ x cw) c lw) (cons-dot-y y h lw)
                  (- (+ y h) lw 2) (cons-cell) (if (on? 'open) 'window-bg ink)
                  lw)))

  ;; The widest value, g in from each side, and the cdr; at most ten lines
  ;; wide.
  (define (cons-dropdown-size labels)
    (values (min (* 10 (font-line-height 'ui))
                 (+ (* 2 (cons-space)) (cons-slot) (text-widest labels 'ui)))
            (ui-control-height)))

  ;; A tag is a symbol in a list: small chained cells, [perf|•]→[render|/],
  ;; each cdr a square of the chip's height. Every flow of chips (a card's,
  ;; a row's, the chip input's) leaves 4 pixels between two chips, which
  ;; the pointer crosses to touch the next cell. A removable chip keeps its
  ;; × in its car, after the label; the last one (the kit says which) holds
  ;; nil, and one whose next chip is on the next row points there around
  ;; the row's end.
  (define cons-chip-gap 4)

  (define (cons-chip-height) (round (+ (font-line-height 'ui-small) 8)))

  ;; A removable chip's ×: a small square holding the glyph and a little
  ;; room, half a g after the label and half a g from the car's end.
  (define (cons-chip-x-side) (+ (round (ui-small-glyph-size)) 4))

  (define (cons-chip-car label removable?)
    (+ (* 2 (cons-space)) (text-width label 'ui-small)
       (if removable? (cons-chip-x-side) 0)))

  ;; The × square, (values x y side), of a chip at x y that is h high and
  ;; whose car is cw wide.
  (define (cons-chip-x-box x y cw h)
    (let ([s (cons-chip-x-side)])
      (values (- (+ x cw) (quotient (cons-space) 2) s)
              (+ y (floor (/ (- h s) 2))) s)))

  ;; For a chip w wide and h high: its car's width, which is all of w when
  ;; the chip is cut short of its cdr (a chip cut to fit its row), and
  ;; whether it is.
  (define (cons-chip-car-width w h removable?)
    (let ([cw (- w h (cons-arrow) (- cons-chip-gap))])
      (if (< cw (+ 8 (if removable? (cons-chip-x-side) 0)))
          (values w #t)
          (values cw #f))))

  ;; A removable chip's × is in its car, after the label, so the chip stays
  ;; a pair. Under the mouse (the kit's flags are the ×'s), only a square
  ;; behind the × fills red, as a window's nil does, with the × in the
  ;; paper's color, at 0.6 while pressed; the car stays as it is. A chip
  ;; that is not removable fills under the mouse.
  (define (cons-chip x y w h flags label)
    (let*-values ([(removable?) (memq 'removable flags)]
                  [(cw cut?) (cons-chip-car-width w h removable?)]
                  [(g) (ui-small-glyph-size)]
                  [(sh) (font-line-height 'ui-small)]
                  [(off?) (memq 'disabled flags)]
                  [(ink) (if off? 'text-faint 'cons-ink)]
                  [(tint) (and (not removable?) (cons-tint-of flags ink))]
                  [(close) (and removable? (cons-tint-of flags 'button-close))])
      (if cut?
          (begin (when tint (fill-box x y w h tint))
                 (cons-ring! x y w h ink 1))
          (cons-pair-h! x y cw h h ink 1 tint #f))
      (draw-text (+ x (cons-space)) (+ y (/ (- h sh) 2))
                 (text-fit label (- cw (* 2 (cons-space))
                                    (if removable? (cons-chip-x-side) 0))
                           'ui-small)
                 (cond [tint 'window-bg] [off? 'text-faint] [else 'text])
                 'ui-small)
      (when removable?
        (let-values ([(bx by bs) (cons-chip-x-box x y cw h)])
          (when close (fill-box bx by bs bs close))
          (ui-draw-glyph (+ bx (/ (- bs g) 2)) (+ by (/ (- bs g) 2)) g g
                         (list (cons 'ink (cond [close 'window-bg]
                                                [off? 'text-faint]
                                                [else 'text-dim])))
                         'cross)))
      (unless cut?
        (let ([next (cons-flag flags 'next)]
              [dx (cons-dot-x (+ x cw) h 1)] [my (cons-dot-y y h 1)])
          (cond
            [(memq 'last flags) (cons-nil! (+ x cw) y h ink 1 #f)]
            ;; the next one on another row: the pointer bends to it
            [(and next (> (abs (- (caddr next) y)) 1))
             (cons-bend! dx my (+ x w (- cons-chip-gap)) (+ y h)
                         (cadr next) (caddr next) h ink)]
            [else (cons-right! dx my (+ x w cons-chip-gap) h ink 1)])))))

  ;; The flag (key . value) in flags, which mix symbols and such pairs, or
  ;; #f.
  (define (cons-flag flags key)
    (find (lambda (f) (and (pair? f) (eq? (car f) key))) flags))

  ;; A pointer from the dot at (dx, my) in a row's last cdr to the first
  ;; pair of the next row, at (nx, ny), h high, as SICP draws a wrapped
  ;; list: out to the right to xr, down to midway between the rows (the
  ;; row's bottom is at bottom), back left past the pair, and into it from
  ;; the left, at its middle. It is 1 pixel thick, as the chips' pointers
  ;; are.
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

  ;; The remove area: the × and a little room around it.
  (define (cons-chip-areas x y w h)
    (let*-values ([(cw cut?) (cons-chip-car-width w h #t)]
                  [(bx by bs) (cons-chip-x-box x y cw h)])
      (list (list 'remove (- bx 2) (- by 2) (+ bs 4) (+ bs 4)))))

  ;; The chips start half a g after the opening paren, as text does, and
  ;; otherwise flow in the kit's rows, cons-chip-gap apart, a gap that each
  ;; chip's pointer crosses.
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
                                                     (* 8
                                                        (font-line-height 'ui)))
                                                ch))))])
      (let ([f (list-ref at (length chips))])
        (append (map (lambda (s p)
                       (list 'chip (car p)
                             (+ (cdr p) (floor (/ (- ch (cdr s)) 2)))
                             (car s) (cdr s)))
                     sizes (list-head at (length chips)))
                (list (list 'field (car f) (cdr f) (- (+ x w) pad (car f))
                            ch))))))

  ;; A card (a task, a style) is a box: the chosen or dragged one has the
  ;; bold stroke, and the one under the mouse a faint fill.
  (define (cons-card x y w h flags)
    (let ([bold? (or (memq 'selected flags) (memq 'floating flags))])
      (when (memq 'hover flags) (fill-box x y w h (alpha 'cons-ink 0.08)))
      (cons-ring! x y w h (if bold? 'accent 'cons-ink) (if bold? 2 1))))

  ;; A scroll bar is a 1-pixel track, and its thumb a cell that fills under
  ;; the mouse. Its region is the thumb and g beyond it, so that against an
  ;; edge (a well's, a window's) the thumb keeps g from that edge; the
  ;; track keeps g from the ends of the view.
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

  ;; A slider is a line, filled in accent up to its value; its knob is a
  ;; small cell, bold under the mouse. A painted track (Settings' colors)
  ;; is a band under the knob.
  (define (cons-slider x y w h flags frac paint)
    (let* ([cy (round (+ y (/ h 2)))] [kx (round (+ x (* frac w)))]
           [off? (memq 'disabled flags)]
           [hot? (and (not off?)
                      (or (memq 'hover flags) (memq 'pressed flags)))])
      (if paint
          (with-clip (x (- cy 3) w 6) (paint x (- cy 3) w 6))
          (begin (fill-box x cy w 1 'text-faint)
                 (fill-box x (- cy 1) (max 0 (- kx x)) 2
                           (if off? 'text-faint 'accent))))
      (fill-box (- kx 4) (- cy 7) 8 14 'window-bg)
      (cons-ring! (- kx 4) (- cy 7) 8 14
                  (cond [hot? 'accent] [off? 'text-faint] [else 'cons-ink])
                  (if hot? 2 1))))

  ;; Progress is a cell that fills with accent ink by the fraction, and
  ;; green when done.
  (define (cons-progress x y w h flags frac)
    (when (> frac 0)
      (fill-box x y (* w (min 1 frac)) h (if (>= frac 1) 'green 'accent)))
    (cons-ring! x y w h 'cons-ink 1))

  ;; A column's heading: faint, its words underlined, and the sort shown as
  ;; a pointer head; the words sit where a table's text does
  ;; (ui-table-cell-inset).
  (define (cons-table-header x y w h flags label dir)
    (let* ([sh (font-line-height 'ui-small)] [g (ui-small-glyph-size)]
           [in (* 2 (cons-space))]
           [s (text-fit label (max 0 (- w (* 3 (cons-space)) g)) 'ui-small)]
           ;; over a right-aligned column, at its numbers' edge
           [right? (memq 'right flags)]
           [tx (if right? (- (+ x w) in (text-width s 'ui-small)) (+ x in))]
           [ty (+ y (/ (- h sh) 2))]
           [end (draw-text tx ty s (if (or dir (memq 'hover flags)) 'text
                                       'text-faint)
                           'ui-small)])
      (when (> (string-length s) 0)
        (fill-box tx (- (+ y h) (cons-space)) (- end tx) 1 'text-faint))
      (when dir
        (ui-draw-glyph (if right? (- tx 4 g) (+ end 4)) (+ y (/ (- h g) 2)) g g
                       '((ink . cons-ink))
                       dir))))

  ;; Rows are the list's elements, with a faint line under each, g in from
  ;; the table's left: the chosen row has the bold stroke, and the one
  ;; under the mouse a faint fill.
  (define (cons-table-row x y w h flags)
    (let* ([g (cons-space)] [x (+ x g)] [w (- w g)])
      (cond [(memq 'selected flags) (cons-ring! x y w h 'accent 2)]
            [(memq 'hover flags) (fill-box x y w h (alpha 'cons-ink 0.08))])
      (fill-box x (- (+ y h) 1) w 1 (alpha 'text-faint 0.5))))

  ;; A tree is nested lists; a node's twisty is the pointer: a dot and an
  ;; arrow pointing right while its children are hidden past it, and down
  ;; when they show. Dimmed rows are faint, as the kit dims them.
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
  ;; surface-well-ring); the others have the window's own background, a
  ;; strip ruled off where it meets the rest.
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

  ;; A popup is an outlined box on the window's background with nothing
  ;; under it (drawn, not painted): a dialog's in the focused window's
  ;; border color, a tooltip's faint, and a menu's and a toast's in the
  ;; plain ink.
  (define (cons-panel x y w h flags)
    (fill-box x y w h 'window-bg)
    (cons-ring! x y w h
                 (cond [(memq 'dialog flags) 'window-border-focus]
                       [(memq 'tooltip flags) 'text-faint]
                       [else 'cons-ink])))

  ;; The chosen entry of a list (Settings', the completion's) has the bold
  ;; stroke, and the one under the mouse a plain box; a menu's entry,
  ;; outlined as the kit asks, is inverted while pressed.
  (define (cons-highlight x y w h flags)
    (cond [(memq 'hover flags) (cons-ring! x y w h 'cons-ink 1)]
          [(not (memq 'outline flags)) (cons-ring! x y w h 'accent 2)]
          [(memq 'pressed flags) (fill-box x y w h 'cons-ink)]
          [else (cons-ring! x y w h 'cons-ink 1)]))

  ;; A faint line between groups (the completion's signature).
  (define (cons-separator x y w h flags)
    (let ([my (+ y (/ h 2))]) (draw-line x my (+ x w) my 'text-faint))))
