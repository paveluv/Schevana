;;; tests/units/ui-table.ss — the kit's table ((schevana kits ui)), by itself: a
;;; row selected, opened and its menu asked for, a heading's press, a
;;; row's checkbox, and the selected row scrolled into view. Its columns'
;;; handles and headings' places are behaviors.ss's; its steps by keys
;;; ui.ss's (ui-table-step).

(define ui-table-test-rows (map (lambda (i) (format "row ~a" i)) (iota 30)))

;; A table of 30 rows of two columns; what was selected, sorted, opened,
;; its menu asked for and checked, kept in boxes.
(define (ui-table-test-window)
  (let ([selected (box #f)] [sorted (box #f)] [opened (box #f)]
        [menu (box #f)] [checked (box '())])
    (values
     (test-kit-window "Table"
       (lambda (ui w h)
         (ui-table ui 't 20 20 360 (- h 40) '((name "Name" 200) (n "N" 80))
                   ui-table-test-rows (unbox selected)
                   (lambda (r) (set-box! selected r))
                   (lambda (r key x y w h flags)
                     (draw-text (+ x 4) y (if (eq? key 'name) r "1")
                                'text 'ui))
                   'on-sort (lambda (key) (set-box! sorted key))
                   'on-open (lambda (r) (set-box! opened r))
                   'on-menu (lambda (r x y) (set-box! menu r))
                   'checked (lambda (r) (and (member r (unbox checked)) #t))
                   'on-check (lambda (r) (set-box! checked
                                                   (cons r (unbox checked))))
                   'reveal #t))
       '(400 . 260))
     selected sorted opened menu checked)))

(check "a click on a row selects it, a double click opens it, and a right \
        press asks for its menu"
       (let-values ([(win selected sorted opened menu checked)
                     (ui-table-test-window)])
         (steps 2)
         (test-click! win '(t row 2))
         (let ([clicked (unbox selected)])
           (test-click! win '(t row 3) 2)
           (let-values ([(x y) (test-point win '(t row 1))])
             (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y right 1)
                      `(mouse-up ,x ,y right)))
           (steps 1)
           (close-window! win)
           (and (equal? clicked "row 2") (equal? (unbox opened) "row 3")
                (equal? (unbox menu) "row 1")))))

(check "a press on a heading asks for its column's sort; on a row's \
        checkbox, for that row's check, not its selection"
       (let-values ([(win selected sorted opened menu checked)
                     (ui-table-test-window)])
         (steps 2)
         (test-click! win '(t header n))
         (test-click! win '(t check 4))
         (close-window! win)
         (and (eq? (unbox sorted) 'n) (equal? (unbox checked) '("row 4"))
              (not (unbox selected)))))

(check "with 'reveal, the selected row is scrolled into view"
       (let-values ([(win selected sorted opened menu checked)
                     (ui-table-test-window)])
         (steps 2)
         (set-box! selected (list-ref ui-table-test-rows 27))   ; eq?
         (invalidate! win)
         (steps 3)
         (let* ([ui (window-ref win 'ui)]
                [f (ui-region-frame (test-region ui '(t row 27)))]
                [b (test-region ui '(t body))])
           (close-window! win)
           (and (>= (cadr f) (ui-region-y b))
                (<= (+ (cadr f) (cadddr f))
                    (+ (ui-region-y b) (ui-region-h b)))))))
