;;; tests/units/ui-chip-input.ss — the kit's chip input ((schevana kits ui)), by
;;; itself: chips added by Return, a comma or a paste, removed by Backspace
;;; or a chip's ×, and a suggestion picked by keys.

;; A chip input, its chips and draft kept where its procedures put them;
;; suggest, if given, as a text field's.
(define (ui-chip-input-test-window . suggest)
  (let ([chips (box '())] [draft (box "")])
    (values
     (test-kit-window "Chips"
       (lambda (ui w h)
         (apply ui-chip-input ui 'c 20 20 360 (unbox chips) (unbox draft)
                (lambda (s) (set-box! draft s))
                (lambda (new) (set-box! chips (append (unbox chips) new)))
                (lambda (i)
                  (set-box! chips (append (list-head (unbox chips) i)
                                          (list-tail (unbox chips) (+ i 1)))))
                (if (pair? suggest) (list 'suggest (car suggest)) '())))
       '(400 . 300))
     chips draft)))

(define (ui-chip-input-test-type! s)
  (for-each (lambda (c) (inject! (list 'text (string c)))) (string->list s))
  (steps 2))

(define (ui-chip-input-test-press! key . mods)
  (inject! (list 'key-down key mods))
  (steps 2))

(check "Return and a comma each add what was typed as a chip, and empty \
        the field"
       (let-values ([(win chips draft) (ui-chip-input-test-window)])
         (steps 2)
         (test-click! win '(c field))
         (ui-chip-input-test-type! "perf")
         (ui-chip-input-test-press! 'return)
         (ui-chip-input-test-type! "ui,")
         (close-window! win)
         (and (equal? (unbox chips) '("perf" "ui"))
              (equal? (unbox draft) ""))))

(check "Backspace in the empty field removes the last chip, and a chip's × \
        removes that one"
       (let-values ([(win chips draft) (ui-chip-input-test-window)])
         (set-box! chips '("a" "b" "c"))
         (steps 2)
         (test-click! win '(c field))
         (ui-chip-input-test-press! 'backspace)
         (let ([backed (unbox chips)])
           (test-click! win '(c remove 0))
           (close-window! win)
           (and (equal? backed '("a" "b"))
                (equal? (unbox chips) '("b"))))))

(check "a paste with commas adds a chip for each part at once and keeps the \
        last as the draft; 4,000 parts as well"
       (let-values ([(win chips draft) (ui-chip-input-test-window)])
         (steps 2)
         (test-click! win '(c field))
         (clipboard-set! "alpha, beta,gamma")
         (ui-chip-input-test-press! #\v 'ctrl)
         (let ([few (list (unbox chips) (unbox draft))])
           (set-box! chips '())
           (set-box! draft "")
           (invalidate! win)
           (steps 1)
           (clipboard-set! (apply string-append
                                  (map (lambda (i) (format "f~a," i))
                                       (iota 4000))))
           (ui-chip-input-test-press! #\v 'ctrl)
           (let ([many (length (unbox chips))] [crashed (window-error win)])
             (close-window! win)
             (and (equal? few '(("alpha" " beta") "gamma"))
                  (= many 4000) (not crashed))))))

(check "with suggestions, Down and Return add the one chosen, and empty the \
        field"
       (let-values ([(win chips draft)
                     (ui-chip-input-test-window
                      (lambda (text)
                        (filter (lambda (s) (string-prefix? text s))
                                '("render" "release" "perf"))))])
         (steps 2)
         (test-click! win '(c field))
         (ui-chip-input-test-type! "re")
         (ui-chip-input-test-press! 'down)
         (ui-chip-input-test-press! 'return)
         (close-window! win)
         (and (equal? (unbox chips) '("render"))
              (equal? (unbox draft) ""))))
