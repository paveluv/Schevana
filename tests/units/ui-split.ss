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

;; A split in a scroll view 100 high, its panes 200 high, scrolled down by
;; 60: the line's handle is cut to the view, so that no press above or
;; below the view, where the line would run on, reaches it.
(check "a split in a scroll view is cut to the view: its line takes no \
        press outside it"
       (let* ([win (test-kit-window "Split"
                     (lambda (ui w h)
                       (ui-scroll ui 'view 20 40 360 100
                         (lambda (top)
                           (ui-split ui 'sp 20 top 360 200 150 80 100)
                           (+ top 200))))
                     '(400 . 200))]
              [ui (window-ref win 'ui)])
         (steps 2)
         (ui-memo! ui 'view (cons 60 100))
         (invalidate! win)
         (steps 2)
         (let* ([r (test-region ui 'sp)]
                [frame (and r (list (ui-region-x r) (ui-region-y r)
                                    (ui-region-w r) (ui-region-h r)))])
           (close-window! win)
           (printf "  ~s\n" frame)
           ;; the view is 40..140; the line's handle keeps within it
           (and frame (>= (cadr frame) 40)
                (<= (+ (cadr frame) (cadddr frame)) 140)))))
