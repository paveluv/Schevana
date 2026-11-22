;;; tests/units/ui-dialog.ss — the kit's dialog ((schevana kits ui)), tested
;;; by itself: how it takes the keyboard, Return for its default button,
;;; Escape and a press outside it, and clicks on its buttons.

(define ui-dialog-test-title "Delete it?")
(define ui-dialog-test-message "It can't be undone.")

;; A window with a text field and, while the open box holds true, a dialog
;; over it with Cancel and Delete (Delete disabled when an argument is
;; given). Returns the window and boxes for open, the field's text and the
;; list of what the dialog called, latest first.
(define (ui-dialog-test-window . disabled)
  (let ([open (box #f)] [field (box "")] [said (box '())])
    (define (said! what) (set-box! said (cons what (unbox said))))
    (let-values ([(dw dh) (ui-dialog-size ui-dialog-test-title
                                          ui-dialog-test-message
                                          '("Cancel" "Delete"))])
      (values
       (test-kit-window "Dialog"
         (lambda (ui w h)
           (ui-text-field ui 'f 20 20 300 30 (unbox field)
                          (lambda (t) (set-box! field t)))
           (when (unbox open)
             (ui-dialog ui 'dlg ui-dialog-test-title ui-dialog-test-message
                        (list (list "Cancel" (lambda () (said! 'cancel)))
                              (append (list "Delete"
                                            (lambda () (said! 'delete)))
                                      (if (pair? disabled) '(disabled) '())))
                        (lambda () (said! 'dismiss)))))
         (cons (max 400 (+ dw 40)) (max 300 (+ dh 120))))
       open field said))))

(define (ui-dialog-test-open! win open)
  (set-box! open #t)
  (invalidate! win)
  (steps 2))

(define (ui-dialog-test-press! key . mods)
  (inject! (list 'key-down key mods))
  (steps 2))

(check "a dialog takes the keyboard from the field under it: typing then \
        goes nowhere"
       (let-values ([(win open field said) (ui-dialog-test-window)])
         (steps 2)
         (test-click! win 'f)
         (ui-dialog-test-open! win open)
         (inject! '(text "x"))
         (steps 2)
         (let ([focus (ui-focused (window-ref win 'ui))])
           (close-window! win)
           (and (equal? (unbox field) "") (not (equal? focus 'f))))))

(check "Return presses the default button, the last; Escape dismisses it"
       (let-values ([(win open field said) (ui-dialog-test-window)])
         (steps 2)
         (ui-dialog-test-open! win open)
         (ui-dialog-test-press! 'return)
         (ui-dialog-test-press! 'escape)
         (close-window! win)
         (equal? (reverse (unbox said)) '(delete dismiss))))

(check "a disabled default: Return presses nothing"
       (let-values ([(win open field said) (ui-dialog-test-window 'disabled)])
         (steps 2)
         (ui-dialog-test-open! win open)
         (ui-dialog-test-press! 'return)
         (close-window! win)
         (null? (unbox said))))

(check "a click on a button calls its own; a press outside the dialog \
        dismisses it"
       (let-values ([(win open field said) (ui-dialog-test-window)])
         (steps 2)
         (ui-dialog-test-open! win open)
         (test-click! win '(dlg 0))
         (let-values ([(cx cy cw ch) (content-rect win)])
           ;; a point outside the dialog (which is centered) and clear of
           ;; the frame's edges
           (let ([x (+ cx 20)] [y (+ cy ch -20)])
             (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                      `(mouse-up ,x ,y left))))
         (steps 2)
         (close-window! win)
         (printf "  ~s\n" (reverse (unbox said)))
         (equal? (reverse (unbox said)) '(cancel dismiss))))

;; A window with a sheet over a field. The sheet's body is a field of its
;; own, with an id under the sheet's. Returns the window and boxes for the
;; body's text and the list of what the sheet called.
(define (ui-dialog-test-sheet)
  (let ([body (box "")] [said (box '())])
    (values
     (test-kit-window "Sheet"
       (lambda (ui w h)
         (ui-text-field ui 'f 20 20 300 30 "" void)
         (ui-sheet ui 'sh "Name it" 260 (ui-control-height)
                   (lambda (x y w)
                     (ui-text-field ui '(sh name) x y w (ui-control-height)
                                    (unbox body)
                                    (lambda (t) (set-box! body t))))
                   (list (list "Cancel" (lambda ()
                                          (set-box! said (cons 'cancel
                                                               (unbox said)))))
                         (list "Name" (lambda ()
                                        (set-box! said (cons 'name
                                                             (unbox said))))))
                   (lambda () (set-box! said (cons 'dismiss (unbox said))))))
       '(500 . 360))
     body said)))

(check "a sheet's body takes the keyboard as a dialog's buttons do: a field \
        in it takes typing, and Return there presses the default button"
       (let-values ([(win body said) (ui-dialog-test-sheet)])
         (steps 2)
         (test-click! win '(sh name))
         (inject! '(text "draft"))
         (steps 1)
         (ui-dialog-test-press! 'return)
         (close-window! win)
         (and (equal? (unbox body) "draft") (equal? (unbox said) '(name)))))
