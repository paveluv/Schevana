;;; tests/units/ui-dropdown.ss — the kit's dropdown ((schevana kits ui)),
;;; tested by itself: the menu it opens on a press or a key, and what
;;; choosing an entry does.

(define ui-dropdown-test-choices
  '(("To do" . todo) ("In progress" . doing) ("Review" . review)
    ("Done" . done)))

;; A window with a dropdown of four choices. Returns the window and a box
;; that holds the value its on-select was last given.
(define (ui-dropdown-test-window)
  (let ([value (box 'todo)])
    (values
     (test-kit-window "Dropdown"
       (lambda (ui w h)
         (ui-dropdown ui 'd 20 20 200 (ui-control-height)
                      ui-dropdown-test-choices (unbox value)
                      (lambda (v) (set-box! value v))))
       '(400 . 300))
     value)))

(define (ui-dropdown-test-press! key . mods)
  (inject! (list 'key-down key mods))
  (steps 2))

(check "a press opens the menu under the dropdown, every choice in it, the \
        current one marked and selected"
       (let-values ([(win value) (ui-dropdown-test-window)])
         (steps 2)
         (test-click! win 'd)
         (steps 1)
         (let* ([open? (test-menu-open?)]
                [labels (and open? (map car (filter pair?
                                                    (menu-entries *menu*))))]
                [sel (and open? (menu-sel *menu*))]
                [r (test-region (window-ref win 'ui) 'd)])
           (let-values ([(cx cy cw ch) (content-rect win)]
                        [(mx my mw mh) (if open?
                                           (menu-geometry *menu*)
                                           (values 0 0 0 0))])
             (when open? (close-menu!))
             (close-window! win)
             (printf "  ~s ~s\n" labels sel)
             (and open? (= sel 0) (= (length labels) 4)
                  (string-suffix? "✓" (car labels))
                  (>= my (+ cy (ui-region-y r) (ui-region-h r) -1)))))))

(check "with the keyboard, Return, Space and Down each open it"
       (let-values ([(win value) (ui-dropdown-test-window)])
         (steps 2)
         (let ([ui (window-ref win 'ui)])
           (define (opens? key)
             (ui-focus! ui 'd)
             (invalidate! win)
             (steps 1)
             (ui-dropdown-test-press! key)
             (let ([open? (test-menu-open?)])
               (when open? (close-menu!))
               (steps 1)
               open?))
           (let ([opened (map opens? '(return #\space down))])
             (close-window! win)
             (equal? opened '(#t #t #t))))))

(check "Down and Return in its menu choose the next choice: on-select is \
        given its value, and the menu closes"
       (let-values ([(win value) (ui-dropdown-test-window)])
         (steps 2)
         (test-click! win 'd)
         (ui-dropdown-test-press! 'down)
         (ui-dropdown-test-press! 'return)
         (let ([open? (test-menu-open?)])
           (close-window! win)
           (and (eq? (unbox value) 'doing) (not open?)))))

(check "a click on an entry chooses it; Escape closes the menu choosing \
        nothing"
       (let-values ([(win value) (ui-dropdown-test-window)])
         (steps 2)
         (test-click! win 'd)
         (test-menu-click! "Review")
         (let ([clicked (unbox value)])
           (test-click! win 'd)
           (ui-dropdown-test-press! 'escape)
           (let ([open? (test-menu-open?)])
             (close-window! win)
             (and (eq? clicked 'review) (not open?)
                  (eq? (unbox value) 'review))))))
