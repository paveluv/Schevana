;;; (demo widgets boards) — the Widgets demo's page of boards: columns of
;;; cards, as Tasks shows its tasks, with their marks, due dates and links,
;;; and the slot where a dragged card would land.

(library (demo widgets boards)
  (export widgets-boards-page)
  (import (chezscheme)
          (schevana core)
          (schevana kits ui)
          (demo widgets layout))

  ;; Draws a card at x y, cw wide: its fill, its outline (selected when
  ;; the window's card is its title), a level and a title, and its due
  ;; date. A press selects it. Returns the y under it.
  (define (widgets-card ui win x y cw title level due when)
    (let* ([p (ui-card-pad)] [m (ui-mark-size)]
           [lh (font-line-height 'ui)] [sh (font-line-height 'ui-small)]
           [h (+ p lh 6 sh p)] [id (list 'card title)])
      (ui-area ui id x y cw h
               (lambda () ((widgets-keep win 'card) title)))
      (fill-box x y cw h 'bg-2 (ui-card-radius))
      (ui-draw-card x y cw h
                    (apply ui-flags ui id
                           (if (equal? (window-ref win 'card #f) title)
                               '(selected)
                               '())))
      (ui-draw-mark (+ x p) (+ y p (/ (- lh m) 2)) m (list 'level level 4)
                    'orange)
      (ui-draw-label (+ x p m 6) (+ y p) (- cw p p m 6) lh '() title)
      (ui-draw-due (+ x p) (+ y p lh 6) (- cw p p) due when 'ui-small)
      (+ y h)))

  ;; Draws a column x y w h: its well and heading, and its cards, each
  ;; (title level due when), linked to the next; or, with none, the words
  ;; for an empty column; and the slot, after the cards, when slot? says
  ;; so.
  (define (widgets-column ui win x y w h label dot cards slot?)
    (let-values ([(side first between edge) (ui-board-column-insets)]
                 [(left right) (ui-board-card-insets)])
      (ui-draw-board-column x y w h (if (null? cards) '(empty) '()) label
                            (length cards) dot "No cards")
      (let ([cw (- w left right)] [cx (+ x left)])
        (let loop ([cs cards] [cy (+ y (ui-board-header-height) first)])
          (cond
            [(pair? cs)
             (let ([bottom (apply widgets-card ui win cx cy cw (car cs))])
               (ui-draw-board-link cx cy cw (- bottom cy) '() between
                                   (null? (cdr cs)))
               (loop (cdr cs) (+ bottom between)))]
            [slot? (ui-draw-board-slot cx cy cw 48)])))))

  ;; Returns (values right bottom) of the page drawn from (x, y), w wide.
  (define (widgets-boards-page ui win x y w)
    (let* ([gap (ui-gap)] [m (ui-mark-size)]
           [lh (font-line-height 'ui)]
           [y (widgets-heading x y w "A board")]
           [y (widgets-note x y w
                "A press on a card selects it. Doing shows where a dragged \
                 card would land; Done is empty.")]
           [y (let* ([cw (max 160 (min 220 (quotient (- w gap gap) 3)))]
                     [h 300])
                (widgets-column ui win x y cw h "To do" 'accent
                                '(("Write the docs" 3 "Due yesterday" past)
                                  ("Draw the icons" 1 "Due today" today)
                                  ("Ship it" 0 "Due Friday" #f))
                                #f)
                (widgets-column ui win (+ x cw gap) y cw h "Doing" 'orange
                                '(("Port the styles" 4 "Due today" today))
                                #t)
                (widgets-column ui win (+ x cw gap cw gap) y cw h "Done"
                                'green '() #f)
                (+ y h gap))]
           [y (widgets-heading x y w "Marks")]
           [y (let ([at (lambda (i) (+ x (* i (+ m gap))))])
                (for-each (lambda (n) (ui-draw-mark (at n) y m
                                                    (list 'level n 4) 'orange))
                          '(0 1 2 3 4))
                (ui-draw-mark (at 5) y m 'circle 'accent)
                (ui-draw-mark (at 6) y m 'diamond 'green)
                (ui-draw-mark (at 7) y m 'square 'magenta)
                (ui-draw-mark (at 8) y m 'blocked 'red)
                (ui-draw-mark (at 9) y m 'dot 'teal)
                (+ y m gap))]
           [y (widgets-heading x y w "Due dates")]
           [y (begin
                (ui-draw-due x y 160 "Due yesterday" 'past 'ui)
                (ui-draw-due (+ x 160 gap) y 160 "Due today" 'today 'ui)
                (ui-draw-due (+ x 320 gap gap) y 160 "Due Friday" #f 'ui)
                (+ y lh gap))])
      (values (+ x w) y))))
