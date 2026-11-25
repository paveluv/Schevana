;;; (demo widgets panes) — the Widgets demo's pages of grids and panes,
;;; and of scrolling: the Lisp machines' menus of columns and their choice
;;; matrices, panes split side by side and one above the other, a side
;;; panel, and scroll views of every fill, nested, and wider than they
;;; are.

(library (demo widgets panes)
  (export widgets-grids-page widgets-scrolling-page)
  (import (chezscheme)
          (schevana core)
          (schevana kits ui)
          (demo widgets layout))

  ;; Draws a pane's well x y w h, with words in its middle.
  (define (widgets-pane x y w h text)
    (widgets-frame x y w h)
    (ui-draw-label x y w h '(dim center) text))

  ;; Returns (values right bottom) of the page drawn from (x, y), w wide.
  (define (widgets-grids-page ui win x y w)
    (let* ([ch (ui-control-height)] [gap (ui-gap)]
           [gw (min w 480)]
           [get (lambda (key default) (window-ref win key default))]
           [keep (lambda (key) (widgets-keep win key))]
           [columns '(("Size" ("Small" . small) ("Medium" . medium)
                       ("Large" . large))
                      ("Face" ("Serif" . serif) ("Sans" . sans)
                       ("Mono" . mono)))]
           [y (widgets-heading x y w "Menus of columns")]
           [y (widgets-note x y gw "Large can't be had now.")]
           [y (widgets-note x y gw "'policy 'single: one choice in all")]
           [y (+ gap
                 (ui-menu-grid ui 'grid-single x y gw columns
                               (get 'grid-single '(medium))
                               (keep 'grid-single)
                               'enabled? (lambda (v) (not (eq? v 'large)))))]
           [y (widgets-note x y gw "'policy 'multiple: each on and off")]
           [y (+ gap
                 (ui-menu-grid ui 'grid-multiple x y gw columns
                               (get 'grid-multiple '(small serif))
                               (keep 'grid-multiple)
                               'policy 'multiple
                               'enabled? (lambda (v) (not (eq? v 'large)))))]
           [y (widgets-note x y gw "'policy 'columns: one in each column")]
           [y (+ gap
                 (ui-menu-grid ui 'grid-columns x y gw columns
                               (get 'grid-columns '(medium sans))
                               (keep 'grid-columns)
                               'policy 'columns
                               'enabled? (lambda (v) (not (eq? v 'large)))))]
           [y (widgets-heading x y w "Choice matrices")]
           [y (widgets-note x y gw
                "Others can't run it: that cell is left blank, or drawn \
                 disabled with 'show-unavailable.")]
           [y (let* ([perms (get 'perms '((0 0) (1 0) (0 1)))]
                     [checked? (lambda (r c) (and (member (list r c) perms)
                                                  #t))]
                     [change (lambda (r c on?)
                               ((keep 'perms)
                                (if on?
                                    (cons (list r c) perms)
                                    (remove (list r c) perms))))]
                     [can? (lambda (r c) (not (and (= r 2) (= c 2))))]
                     [y (+ gap
                           (ui-choice-grid ui 'perms x y gw
                                           '("Read" "Write" "Run")
                                           '("Owner" "Group" "Others")
                                           checked? change
                                           'enabled? can?
                                           'heading "Who may"))])
                (+ gap
                   (ui-choice-grid ui 'perms-shown x y gw
                                   '("Read" "Write" "Run")
                                   '("Owner" "Group" "Others")
                                   checked? change
                                   'enabled? can?
                                   'show-unavailable #t
                                   'heading "Who may")))]
           [y (widgets-heading x y w "Split panes")]
           [y (widgets-note x y gw
                "Drag the line between the panes; a double click on it puts \
                 it back.")]
           [y (let* ([sw (min w 480)] [sh 120]
                     [left (ui-split ui 'split x y sw sh (quotient sw 2)
                                     80 80)])
                (widgets-pane x y left sh (format "~a wide" left))
                (widgets-pane (+ x left) y (- sw left) sh
                              (format "~a wide" (- sw left)))
                (+ y sh gap))]
           [y (let* ([sw (min w 480)] [sh 180]
                     [top (ui-split-stacked ui 'stacked x y sw sh
                                            (quotient sh 2) 40 40)])
                (widgets-pane x y sw top (format "~a high" top))
                (widgets-pane x (+ y top) sw (- sh top)
                              (format "~a high" (- sh top)))
                (+ y sh gap))]
           [y (widgets-heading x y w "Side panels")]
           [y (widgets-note x y gw
                "Its button hides the panel and shows it again. The second \
                 panel floats over the rest, which keeps its size.")]
           [y (let ([pw (min w 480)] [ph 140] [b (widgets-width #f 'gear)])
                (for-each
                 (lambda (id py floating?)
                   (ui-side-panel ui id x py pw ph 'right 160 120
                     (lambda (rx ry rw rh)
                       (widgets-pane rx ry rw rh (format "The rest, ~a wide"
                                                         rw)))
                     (lambda (px py pw ph)
                       (ui-draw-label (+ px 10) (+ py 10) (- pw 20) ch '()
                                      "The panel")
                       (ui-checkbox ui (list id 'check) (+ px 10)
                                    (+ py 10 ch) (- pw 20) ch "An option"
                                    (get 'panel-option #t)
                                    (keep 'panel-option)))
                     'floating floating?)
                   ;; the button at the rest's corner, where it stays as the
                   ;; panel comes and goes
                   (ui-side-panel-button ui id (+ x 6) (+ py 6) b b 'right))
                 '(side side-floating)
                 (list y (+ y ph gap))
                 '(#f #t))
                (+ y ph gap ph gap))])
      (values (+ x w) y)))

  ;; Draws rows of a list, from top, each rh high, in a view vx..vx+vw,
  ;; and returns where they end.
  (define (widgets-lines vx vw top n rh)
    (do ([i 0 (+ i 1)]) ((= i n))
      (ui-draw-label (+ vx 8) (+ top (* i rh)) (- vw 16) rh '()
                     (format "Row ~a of ~a" (+ i 1) n)))
    (+ top (* n rh)))

  ;; Returns (values right bottom) of the page drawn from (x, y), w wide.
  (define (widgets-scrolling-page ui win x y w)
    (let* ([ch (ui-control-height)] [gap (ui-gap)]
           [rh (round (+ (font-line-height 'ui) 8))]
           [vh (* 10 rh)]
           [vw (max 120 (min 180 (quotient (- w (* 3 gap)) 4)))]
           [y (widgets-heading x y w "Every fill")]
           [y (widgets-note x y w
                "Views 10 rows high: empty, short, exactly full, and over \
                 full. Top and Bottom scroll each view to its ends.")]
           [y (begin
                (for-each
                 (lambda (id n i)
                   (let* ([vx (+ x (* i (+ vw gap)))]
                          [bw (quotient (- vw 4) 2)]
                          [vy (+ y ch 4 ch 4)])
                     (ui-draw-label vx y vw ch '(dim)
                                    (format "~a rows" n))
                     (ui-button ui (list id 'top) vx (+ y ch 4) bw ch "Top"
                                (lambda () (ui-reveal! ui id 0 0 vh)))
                     (ui-button ui (list id 'bottom) (+ vx bw 4) (+ y ch 4) bw
                                ch "Bottom"
                                (lambda ()
                                  (ui-reveal! ui id (* n rh) (* n rh) vh)))
                     (widgets-frame vx vy vw vh)
                     (ui-scroll ui id vx vy vw vh
                       (lambda (top) (widgets-lines vx vw top n rh)))))
                 '(fill-0 fill-3 fill-10 fill-40)
                 '(0 3 10 40)
                 '(0 1 2 3))
                (+ y ch 4 ch 4 vh gap))]
           [y (widgets-heading x y w "Nested")]
           [y (let* ([ow (min w 420)] [oh 240] [iw (- ow 40)] [ih 100])
                (widgets-frame x y ow oh)
                (ui-scroll ui 'outer x y ow oh
                  (lambda (top)
                    (let* ([t (widgets-lines x ow top 4 rh)]
                           [t (begin
                                (widgets-frame (+ x 20) t iw ih)
                                (ui-scroll ui 'inner (+ x 20) t iw ih
                                  (lambda (top)
                                    (widgets-lines (+ x 20) iw top 20 rh)))
                                (+ t ih))])
                      (widgets-lines x ow t 8 rh))))
                (+ y oh gap))]
           [y (widgets-heading x y w "Wider than the view")]
           [y (widgets-note x y w
                "The bar across is the style's bar at the side, turned; \
                 the wheel turned sideways moves it too.")]
           [y (let* ([ww (min w 420)] [wh 180])
                (widgets-frame x y ww wh)
                (ui-scroll-wide ui 'wide x y ww wh
                  (lambda (left top)
                    (do ([i 0 (+ i 1)]) ((= i 24))
                      (ui-draw-label (+ left 8) (+ top (* i rh)) 900 rh '()
                                     (format "Row ~a, a line that runs on \
                                              past the view's right edge, \
                                              and on" (+ i 1))))
                    (values (+ left 900) (+ top (* 24 rh)))))
                (+ y wh gap))]
           [y (let* ([ww (min w 420)] [wh (* 3 rh)])
                (widgets-frame x y ww wh)
                (ui-scroll-wide ui 'wide-only x y ww wh
                  (lambda (left top)
                    (widgets-lines left 900 top 2 rh)
                    (values (+ left 900) (+ top (* 2 rh)))))
                (+ y wh gap))])
      (values (+ x w) y))))
