;;; tests/units/ui-date-field.ss — the kit's date field and its calendar
;;; ((schevana kits ui)), tested by themselves: the calendar opened by a
;;; press or a key, a day picked by a click or by keys, Escape, and the date
;;; cleared.

;; A window with a date field, as tall as the calendar under the field needs
;; in the current font. Returns the window and a box that holds the date its
;; on-select was last given.
(define (ui-date-field-test-window)
  (let ([date (box #f)])
    (let-values ([(cw ch) (ui-calendar-size)])
      (values
       (test-kit-window "Date"
         (lambda (ui w h)
           (ui-date-field ui 'd 20 20 200 (ui-control-height) (unbox date)
                          (lambda (d) (set-box! date d))))
         (cons (max 400 (+ cw 60))
               (+ 20 (ui-control-height) 4 ch 40)))
       date))))

(define (ui-date-field-test-open? win)
  (exists (lambda (r)
            (let ([id (ui-region-id r)])
              (and (pair? id) (eq? (car id) 'd) (pair? (cdr id))
                   (eq? (cadr id) 'day))))
          (ui-state-regions (window-ref win 'ui))))

(define (ui-date-field-test-press! key . mods)
  (inject! (list 'key-down key mods))
  (steps 2))

;; The 20th of this month, as a day number.
(define ui-date-field-test-day20
  (let ([d (ui-today)]) (ui-date->day (list (car d) (cadr d) 20))))

(check "a press opens the calendar; a day clicked is the date, and the \
        calendar closes"
       (let-values ([(win date) (ui-date-field-test-window)])
         (steps 2)
         (test-click! win 'd)
         (steps 1)
         (let ([opened (ui-date-field-test-open? win)])
           (test-click! win (list 'd 'day ui-date-field-test-day20))
           (steps 1)
           (let ([closed (not (ui-date-field-test-open? win))])
             (close-window! win)
             (and opened closed
                  (equal? (unbox date)
                          (ui-day->date ui-date-field-test-day20)))))))

(check "opened again on its date, Right Right Return picks two days later; \
        Page Down then Escape closes it, the date as it was"
       (let-values ([(win date) (ui-date-field-test-window)])
         (steps 2)
         (set-box! date (ui-day->date ui-date-field-test-day20))
         (invalidate! win)
         (steps 1)
         (test-click! win 'd)
         (ui-date-field-test-press! 'right)
         (ui-date-field-test-press! 'right)
         (ui-date-field-test-press! 'return)
         (let ([later (unbox date)])
           (test-click! win 'd)
           (ui-date-field-test-press! 'page-down)
           (ui-date-field-test-press! 'escape)
           (let ([open? (ui-date-field-test-open? win)])
             (close-window! win)
             (and (equal? later (ui-day->date (+ ui-date-field-test-day20 2)))
                  (not open?) (equal? (unbox date) later))))))

(check "with the keyboard, Return, Space and Down each open it, and Delete \
        and Backspace clear the date"
       (let-values ([(win date) (ui-date-field-test-window)])
         (steps 2)
         (let ([ui (window-ref win 'ui)])
           (define (opens? key)
             (ui-focus! ui 'd)
             (invalidate! win)
             (steps 1)
             (ui-date-field-test-press! key)
             (let ([open? (ui-date-field-test-open? win)])
               (ui-date-field-test-press! 'escape)
               open?))
           (define (clears? key)
             (set-box! date (ui-day->date ui-date-field-test-day20))
             (ui-focus! ui 'd)
             (invalidate! win)
             (steps 1)
             (ui-date-field-test-press! key)
             (not (unbox date)))
           (let ([opened (map opens? '(return #\space down))]
                 [cleared (map clears? '(delete backspace))])
             (close-window! win)
             (and (equal? opened '(#t #t #t))
                  (equal? cleared '(#t #t)))))))
