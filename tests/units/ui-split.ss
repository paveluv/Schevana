;;; tests/units/ui-split.ss — the kit's split ((schevana kits ui)), by itself:
;;; the line between two panes dragged, kept within their least widths, and a
;;; double click on it back to the app's width.

;; A split of 360 from x 20, its left pane 150 at first, at least 80 and
;; its right one at least 100; the left pane's width as the last draw
;; gave it.
(define (ui-split-test-window)
  (let ([left (box #f)])
    (values
     (test-kit-window "Split"
       (lambda (ui w h)
         (set-box! left (ui-split ui 'sp 20 20 360 200 150 80 100)))
       '(400 . 260))
     left)))

;; A press on the line, a drag of dx, and the release; a step.
(define (ui-split-test-drag! win dx)
  (let-values ([(x y) (test-point win 'sp)])
    (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
             `(mouse-move ,(+ x dx) ,y) `(mouse-up ,(+ x dx) ,y left))
    (steps 2)))

(check "a drag on the line between the panes moves it as far, within the \
        least widths of both; a double click on it puts it back"
       (let-values ([(win left) (ui-split-test-window)])
         (steps 2)
         (let ([start (unbox left)])
           (ui-split-test-drag! win 40)
           (let ([dragged (unbox left)])
             (ui-split-test-drag! win 400)    ; the right pane's least
             (let ([right-least (unbox left)])
               (ui-split-test-drag! win -400) ; the left pane's least
               (let ([left-least (unbox left)])
                 (test-click! win 'sp 2)
                 (steps 1)
                 (close-window! win)
                 (printf "  ~s\n" (list start dragged right-least left-least
                                       (unbox left)))
                 (and (= start 150) (= dragged 190)
                      (= right-least (- 360 100)) (= left-least 80)
                      (= (unbox left) 150))))))))
