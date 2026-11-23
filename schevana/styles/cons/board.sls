;;; (schevana styles cons board) — a part of the Cons style ((schevana
;;; styles cons)): a board (the kit's), each column a list of cards, the
;;; pointer from each card to the next.

(library (schevana styles cons board)
  (export
    cons-board-card-insets cons-board-column cons-board-column-insets
    cons-board-header-height cons-board-link cons-board-slot cons-card-pad
    cons-panel-pad cons-table-cell-inset)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) draw-text fill-box font-line-height)
          (only (schevana kits text) text-draw-centered)
          (only (schevana kits ui) ui-board-header-height ui-draw-mark
                ui-mark-size ui-draw-surface ui-scrollbar-inset)
          (schevana styles cons cells)
          (schevana styles cons widgets))

  (library-layer looks)

  ;;; A board (the kit's): a column is a list of cards.

  ;; The cards sit g from the well's sides and from its heading, and the +
  ;; g from the heading's end; the room between two cards is a pointer.
  (define (cons-board-column-insets)
    (let ([g (cons-space)]) (values g g (cons-arrow) g)))

  ;; A heading is a cell high, with g above and below it, so that the +
  ;; cell sits g inside the well's corner.
  (define (cons-board-header-height) (+ (cons-cell) (* 2 (cons-space))))

  ;; A card's cdr stands at its right, a cell wide; past it is the room the
  ;; scroll bar keeps (its margin g, its thumb, and g to the well's edge).
  (define (cons-board-card-insets)
    (let ([g (cons-space)])
      (values (max g (ui-scrollbar-inset 'left))
              (+ (cons-cell) (max g (ui-scrollbar-inset 'right))))))

  ;; Inside a card everything is g from its edges; a table's text is g
  ;; inside its row's box, which is g inside the table.
  (define (cons-card-pad) (cons-space))
  (define (cons-table-cell-inset) (* 2 (cons-space)))

  ;; The details' margin is the pad.
  (define (cons-panel-pad) (* 2 (cons-space)))

  ;; Each card's cdr stands beside it, sharing its edge; from the dot in it
  ;; a pointer goes down to the next card, and the last card's cdr holds
  ;; nil. A chosen or dragged card's cdr has the bold stroke, as its box
  ;; does.
  (define (cons-board-link x y w h flags gap last?)
    (let* ([c (cons-cell)]
           [bold? (or (memq 'selected flags) (memq 'floating flags))]
           [ink (if bold? 'accent 'cons-ink)] [lw (if bold? 2 1)])
      (cons-ring! (+ x w (- lw)) y (+ c lw) h ink lw)
      (if last?
          (cons-nil-h! (+ x w) y c h ink lw #f)
          (cons-down! (cons-dot-x (+ x w) c lw) (cons-dot-y y h lw) (+ y h gap)
                      c ink lw))))

  ;; A column's well and heading: its dot g in, then its name and its
  ;; count, g apart; an empty column shows ().
  (define (cons-board-column x y w h flags label count dot empty)
    (let* ([hh (ui-board-header-height)] [g (cons-space)] [m (ui-mark-size)]
           [lh (font-line-height 'ui-bold)] [sh (font-line-height 'ui-small)])
      (ui-draw-surface x y w h '(well))
      (let* ([dw (if dot
                     (ui-draw-mark (+ x g) (+ y (/ (- hh m) 2)) m 'dot dot)
                     0)]
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
  (define (cons-board-slot x y w h)
    (cons-dashes! x y w h 'accent)
    (cons-dashes! (+ x w -1) y (+ (cons-cell) 1) h 'accent)))
