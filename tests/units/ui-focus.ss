;;; tests/units/ui-focus.ss — the keyboard's focus ((schevana kits ui)),
;;; tested by itself: Tab and Shift+Tab move through the widgets in the
;;; order they're drawn, and a scroll view brings the widget that gets the
;;; keyboard into view (a text area taller than the view, by its caret's
;;; row).

;; A window with five fields in a column.
(define (ui-focus-test-fields)
  (test-kit-window "Fields"
    (lambda (ui w h)
      (do ([i 0 (+ i 1)]) ((= i 5))
        (ui-text-field ui (list 'f i) 20 (+ 10 (* i 40)) 200 30 "" void)))
    '(400 . 240)))

;; A window with a scroll view three fields high over ten fields and, below
;; them, a text area of 30 lines, as tall as its lines need in the current
;; font.
(define ui-focus-test-text
  (apply string-append
         (map (lambda (i) (format "line ~a\n" i)) (iota 29))))

(define (ui-focus-test-scroll)
  (test-kit-window "Scroll"
    (lambda (ui w h)
      (let ([ch (ui-control-height)])
        (ui-scroll ui 'v 20 20 300 (* 3 (+ ch 10))
          (lambda (top)
            (do ([i 0 (+ i 1)]) ((= i 10))
              (ui-text-field ui (list 'g i) 30 (+ top 10 (* i (+ ch 10)))
                             240 ch "" void))
            (let-values ([(aw ah) (ui-text-area-size ui 'a '() 240
                                                     ui-focus-test-text 1 40)])
              (let ([at (+ top 10 (* 10 (+ ch 10)))])
                (ui-text-area ui 'a 30 at 240 ah ui-focus-test-text void)
                (+ at ah 10)))))))
    '(400 . 300)))

(define (ui-focus-test-press! key . mods)
  (inject! (list 'key-down key mods))
  (steps 2))

;; Whether region id lies wholly within the scroll view v, judged by its
;; frame (where it is), not by its rectangle as the view clips it.
(define (ui-focus-test-shown? ui id)
  (let ([f (ui-region-frame (test-region ui id))] [v (test-region ui 'v)])
    (and (>= (cadr f) (ui-region-y v))
         (<= (+ (cadr f) (cadddr f)) (+ (ui-region-y v) (ui-region-h v))))))

(check "Tab gives the keyboard to the next widget in the order they're \
        drawn, Shift+Tab to the one before, each wrapping at the ends"
       (let ([win (ui-focus-test-fields)])
         (steps 2)
         (let ([ui (window-ref win 'ui)])
           (test-click! win '(f 3))
           (let* ([at (lambda (key . mods)
                        (apply ui-focus-test-press! key mods)
                        (ui-focused ui))]
                  [last (at 'tab)] [wrapped (at 'tab)] [after (at 'tab)]
                  [back (at 'tab 'shift)] [around (at 'tab 'shift)])
             (close-window! win)
             (equal? (list last wrapped after back around)
                     '((f 4) (f 0) (f 1) (f 0) (f 4)))))))

(check "Tab and Shift+Tab bring the field they reach in a scroll view into \
        view, wrapping from the first to the last"
       (let ([win (ui-focus-test-scroll)])
         (steps 2)
         (let ([ui (window-ref win 'ui)])
           (test-click! win '(g 0))
           (ui-focus-test-press! 'tab 'shift)   ; past the first, to the area
           (ui-focus-test-press! 'tab 'shift)   ; then the last field
           (let ([last (and (equal? (ui-focused ui) '(g 9))
                            (ui-focus-test-shown? ui '(g 9)))])
             (ui-focus-test-press! 'tab)
             (ui-focus-test-press! 'tab)        ; the area, then the first
             (let ([first (and (equal? (ui-focused ui) '(g 0))
                               (ui-focus-test-shown? ui '(g 0)))])
               (close-window! win)
               (and last first))))))

(check "a text area taller than the view, given the keyboard, is scrolled \
        to its caret's row, at its end"
       (let ([win (ui-focus-test-scroll)])
         (steps 2)
         (let ([ui (window-ref win 'ui)])
           (ui-focus! ui 'a)
           (invalidate! win)
           (steps 3)
           (let* ([f (ui-region-frame (test-region ui 'a))]
                  [v (test-region ui 'v)]
                  [a (car (apply ui-text-box-areas
                                 (append f '((lines)))))]
                  [lh (font-line-height (list-ref a 5))]
                  ;; the caret's row: the last one, the 30th
                  [row (+ (list-ref a 2) (* 29 lh))])
             (close-window! win)
             (printf "  row at ~a, the view from ~a to ~a\n" row
                     (ui-region-y v) (+ (ui-region-y v) (ui-region-h v)))
             (and (< (cadr f) (ui-region-y v))
                  (>= row (ui-region-y v))
                  (<= (+ row lh) (+ (ui-region-y v) (ui-region-h v))))))))
