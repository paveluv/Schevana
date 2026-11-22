;;; tests/units/ui-split.ss — the kit's split ((schevana kits ui)), tested by
;;; itself: a drag of the line between two panes, which stays within their
;;; least widths, and a double click on it, which puts it back at the app's
;;; width.

;; A window with a split 360 wide from x 20: its left pane starts 150 wide
;; and is at least 80, and its right pane is at least 100. Returns the
;; window and a box with the left pane's width as the last draw gave it.
(define (ui-split-test-window)
  (let ([left (box #f)])
    (values
     (test-kit-window "Split"
       (lambda (ui w h)
         (set-box! left (ui-split ui 'sp 20 20 360 200 150 80 100)))
       '(400 . 260))
     left)))

;; Presses on the line, drags it by dx and releases it, then steps.
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
             (ui-split-test-drag! win 400)    ; to the right pane's least width
             (let ([right-least (unbox left)])
               (ui-split-test-drag! win -400) ; to the left pane's least width
               (let ([left-least (unbox left)])
                 (test-click! win 'sp 2)
                 (steps 1)
                 (close-window! win)
                 (printf "  ~s\n" (list start dragged right-least left-least
                                       (unbox left)))
                 (and (= start 150) (= dragged 190)
                      (= right-least (- 360 100)) (= left-least 80)
                      (= (unbox left) 150))))))))
