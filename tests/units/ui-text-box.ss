;;; tests/units/ui-text-box.ss — the kit's text field and text area
;;; ((schevana kits ui), ui-text-box), tested by themselves: typing,
;;; selecting, the clipboard, a double click, Return, and the keyboard taken
;;; away.

;; A window with a field and an area. Returns the window, a box for each
;; one's text as its on-change last gave it, and a box that counts how many
;; times the field's Return called its on-enter.
(define (ui-text-box-test-window)
  (let ([field (box "")] [area (box "")] [entered (box 0)])
    (values
     (test-kit-window "Text"
       (lambda (ui w h)
         (ui-text-field ui 'f 20 20 300 30 (unbox field)
                        (lambda (t) (set-box! field t))
                        'on-enter (lambda () (set-box! entered
                                                       (+ 1 (unbox entered)))))
         (ui-text-area ui 'a 20 70 300 80 (unbox area)
                       (lambda (t) (set-box! area t))))
       '(400 . 240))
     field area entered)))

(define (ui-text-box-test-type! s)
  (for-each (lambda (c) (inject! (list 'text (string c)))) (string->list s))
  (steps 1))

(define (ui-text-box-test-press! key . mods)
  (inject! (list 'key-down key mods))
  (steps 1))

(check "a text field takes typing once clicked, its on-change given the \
        text, the caret at its end"
       (let-values ([(win field area entered) (ui-text-box-test-window)])
         (steps 2)
         (test-click! win 'f)
         (ui-text-box-test-type! "Fix the toolbar")
         (let* ([ui (window-ref win 'ui)] [e (ui-state-edit ui)])
           (close-window! win)
           (and (equal? (unbox field) "Fix the toolbar")
                (edit? e)
                (= (edit-caret e) (string-length "Fix the toolbar"))))))

(check "Shift+Left selects and Ctrl+C copies the selection; End and Ctrl+V \
        paste it at the caret; Backspace erases; Ctrl+A and typing replace \
        it all"
       (let-values ([(win field area entered) (ui-text-box-test-window)])
         (steps 2)
         (test-click! win 'f)
         (ui-text-box-test-type! "Fix the toolbar")
         (ui-text-box-test-press! 'left 'shift)
         (ui-text-box-test-press! 'left 'shift)
         (ui-text-box-test-press! 'left 'shift)
         (ui-text-box-test-press! #\c 'ctrl)
         (let ([copied (clipboard-get)])
           (ui-text-box-test-press! 'end)
           (ui-text-box-test-press! #\v 'ctrl)
           (let ([pasted (unbox field)])
             (ui-text-box-test-press! 'backspace)
             (ui-text-box-test-press! 'backspace)
             (ui-text-box-test-press! 'backspace)
             (let ([erased (unbox field)])
               (ui-text-box-test-press! #\a 'ctrl)
               (ui-text-box-test-type! "Fix the menu")
               (close-window! win)
               (printf "  ~s\n" (list copied pasted erased (unbox field)))
               (and (equal? copied "bar")
                    (equal? pasted "Fix the toolbarbar")
                    (equal? erased "Fix the toolbar")
                    (equal? (unbox field) "Fix the menu")))))))

(check "a double click selects the word under it, wherever the font puts \
        it"
       (let-values ([(win field area entered) (ui-text-box-test-window)])
         (steps 2)
         (test-click! win 'f)
         (ui-text-box-test-type! "Fix the menu")
         (let* ([ui (window-ref win 'ui)]
                [r (test-region ui 'f)]
                [a (car (ui-text-box-areas (ui-region-x r) (ui-region-y r)
                                           (ui-region-w r) (ui-region-h r)
                                           '(field)))]
                ;; a point inside "menu", measured in the field's own font
                [x (+ (- (list-ref a 1) (ui-region-x r))
                      (text-width "Fix the me" (list-ref a 5)))])
           (test-click! win 'f 2 'at (exact (round x)))
           (let ([s (edit-selection (ui-state-edit ui))])
             (close-window! win)
             (equal? s "menu")))))

(check "Return calls a field's on-enter and changes nothing; in an area it \
        makes a new line"
       (let-values ([(win field area entered) (ui-text-box-test-window)])
         (steps 2)
         (test-click! win 'f)
         (ui-text-box-test-type! "one")
         (ui-text-box-test-press! 'return)
         (test-click! win 'a)
         (ui-text-box-test-type! "one")
         (ui-text-box-test-press! 'return)
         (ui-text-box-test-type! "two")
         (close-window! win)
         (and (= (unbox entered) 1) (equal? (unbox field) "one")
              (equal? (unbox area) "one\ntwo"))))

(check "a press elsewhere takes the keyboard from the field: typing then \
        goes nowhere"
       (let-values ([(win field area entered) (ui-text-box-test-window)])
         (steps 2)
         (test-click! win 'f)
         (ui-text-box-test-type! "kept")
         (let-values ([(cx cy cw ch) (content-rect win)])
           (let ([x (+ cx 360)] [y (+ cy 220)])   ; on no widget
             (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                      `(mouse-up ,x ,y left))))
         (steps 1)
         (ui-text-box-test-type! "lost")
         (let ([focus (ui-focused (window-ref win 'ui))])
           (close-window! win)
           (and (not focus) (equal? (unbox field) "kept")))))

(check "a box of 'max characters full: a key types nothing, nor does \
        Return in an area; a paste is cut to fit"
       (let* ([text (box (make-string 20 #\a))]
              [win (test-kit-window "Max"
                     (lambda (ui w h)
                       (ui-text-area ui 'a 20 20 300 80 (unbox text)
                                     (lambda (t) (set-box! text t))
                                     'max 20))
                     '(400 . 200))])
         (steps 2)
         (test-click! win 'a)
         (ui-text-box-test-press! 'end 'ctrl)
         (ui-text-box-test-type! "b")
         (ui-text-box-test-press! 'return)
         (let ([full (unbox text)])
           (do ([i 0 (+ i 1)]) ((= i 5)) (ui-text-box-test-press! 'backspace))
           (clipboard-set! (make-string 100 #\c))
           (ui-text-box-test-press! #\v 'ctrl)
           (close-window! win)
           (and (equal? full (make-string 20 #\a))
                (equal? (unbox text)
                        (string-append (make-string 15 #\a)
                                       (make-string 5 #\c)))))))

;; The open menu's entries, each label with whether it can be chosen now.
(define (ui-text-box-test-menu)
  (and *menu* (map (lambda (e) (cons (car e) (menu-entry-ready? e)))
                   (menu-entries *menu*))))

(check "a right press on a field gives it the keyboard and opens the text \
        menu: Paste, while the clipboard has text, types it; Copy, once \
        there is a selection, copies it, and a press inside the selection \
        keeps it"
       (let-values ([(win field area entered) (ui-text-box-test-window)])
         (define (right! . dx)
           (let-values ([(x y) (apply test-point win 'f dx)])
             (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y right 1)
                      `(mouse-up ,x ,y right))
             (steps 1)))
         (steps 2)
         (clipboard-set! "menu")
         (right!)
         (let ([focus (ui-focused (window-ref win 'ui))]
               [empty (ui-text-box-test-menu)])
           (menu-activate! 1)
           (steps 2)
           (let ([pasted (unbox field)])
             (ui-text-box-test-press! #\a 'ctrl)
             (clipboard-set! "")
             (let* ([ui (window-ref win 'ui)]
                    [r (test-region ui 'f)]
                    [a (car (ui-text-box-areas (ui-region-x r) (ui-region-y r)
                                               (ui-region-w r) (ui-region-h r)
                                               '(field)))]
                    ;; between "me" and "nu", in the field's own font
                    [x (+ (- (list-ref a 1) (ui-region-x r))
                          (text-width "me" (list-ref a 5)))])
               (right! 'at (exact (round x)))
               (let ([selected (ui-text-box-test-menu)])
                 (menu-activate! 0)
                 (steps 2)
                 (let ([copied (clipboard-get)])
                   (close-window! win)
                   (printf "  ~s\n" (list focus empty pasted selected copied))
                   (and (eq? focus 'f)
                        (equal? empty '(("Copy\tCtrl+C" . #f)
                                        ("Paste\tCtrl+V" . #t)))
                        (equal? pasted "menu")
                        (equal? selected '(("Copy\tCtrl+C" . #t)
                                           ("Paste\tCtrl+V" . #f)))
                        (equal? copied "menu")))))))))
