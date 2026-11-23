;;; tests/units/tasks-editor.ss — the editor of a task's description
;;; ((schevana apps tasks)): a window of its own, modal to Tasks, opened by
;;; the button next to the Description label or by Ctrl+E in the
;;; description; Save (Ctrl+S) and Cancel (Escape, which asks first when
;;; there are changes); however it closes, Tasks goes on.

(test-backlog!)
(define tasks-editor-test-text
  (apply string-append (make-list 200 "scroll the long text row ")))
(define tasks-editor-test-task
  (add-task! "A long description" 'status 'review
             'description tasks-editor-test-text))

;; Opens Tasks wide (its details beside its view) with the task selected,
;; and returns its window.
(define (tasks-editor-test-tasks)
  (let* ([w (tasks)] [v (window-ref w 'state)])
    (let-values ([(mw mh) (tasks-min-size)])
      (move-window! w 0 (window-y w))
      (resize-window! w (max mw (tasks-wide-width v)) (max 660 mh)))
    (tasks-select! v tasks-editor-test-task)
    (invalidate! w)
    (steps 2)
    w))

(define tasks-editor-test-window (tasks-editor-test-tasks))
(define (tasks-editor-test-view) (window-ref tasks-editor-test-window 'state))
(define (tasks-editor-test-ui) (window-ref tasks-editor-test-window 'ui))
(define (tasks-editor-test-editor)
  (tasks-view-editor (tasks-editor-test-view)))
(define (tasks-editor-test-draft)
  (tasks-editor-text (window-ref (tasks-editor-test-editor) 'state)))
(define (tasks-editor-test-description)
  (task-description tasks-editor-test-task))
(define (tasks-editor-test-waiting?)
  (and (ui-find (tasks-editor-test-ui) '(ui modal-child)) #t))

;; Opens the editor from code with its caret at 0, runs two steps, and
;; returns the editor's window.
(define (tasks-editor-test-open!)
  (let ([ed (tasks-open-editor! (tasks-editor-test-view)
                                tasks-editor-test-task 0)])
    (steps 2)
    ed))

(define (tasks-editor-test-type! s) (test-type! s) (steps 2))
(define (tasks-editor-test-press! key . mods)
  (apply test-press! key mods)
  (steps 2))

(check "the button by the Description label opens the editor: focused, on \
        top, titled by the task, its text focused at the start, and Tasks \
        waits under a scrim"
       (let ([w tasks-editor-test-window])
         (test-show! w 'details 'edit-description)
         (test-click! w 'edit-description)
         (steps 1)
         (let ([ed (tasks-editor-test-editor)])
           (and (window? ed) (eq? ed (focused-window)) (eq? ed (car (windows)))
                (equal? (window-title ed)
                        (format "~a — Description"
                                (task-label tasks-editor-test-task)))
                (eq? 'text (ui-focused (window-ref ed 'ui)))
                (= 0 (ui-caret (window-ref ed 'ui)))
                (tasks-editor-test-waiting?)))))

(check "while it's open, focusing Tasks gives the editor the keyboard, \
        above Tasks; Tasks takes no key; a click in Tasks brings the \
        editor to the front"
       (let ([w tasks-editor-test-window] [v (tasks-editor-test-view)]
             [ed (tasks-editor-test-open!)] [n (length *tasks*)])
         (focus-window! w)
         (steps 1)
         (let ([focused (and (eq? ed (focused-window)) (eq? ed (car (windows)))
                             (eq? w (cadr (windows))))])
           ;; input handed to Tasks itself, as it would be under a style
           ;; that keeps no dialog above its window
           (window-call w 'text "n")
           (window-call w 'key 'delete '())
           (steps 2)
           (let ([untouched (and (= n (length *tasks*))
                                 (not (tasks-view-confirm v)))])
             (let-values ([(cx cy cw ch) (content-rect w)])
               (let ([x (+ cx 30)] [y (+ cy 80)])
                 (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                          `(mouse-up ,x ,y left))))
             (steps 2)
             (and focused untouched (eq? ed (focused-window))
                  (eq? ed (car (windows))))))))

(check "typed into the editor, the draft changes, not the task, and no \
        texts are compared; its status line counts the caret's line and \
        column as typing makes and joins lines; Ctrl+S saves and closes \
        it, and Tasks waits no more"
       (let ([ed (tasks-editor-test-open!)] [compared 0]
             [plain edit-difference])
         (define (status)
           (tasks-editor-status (window-ref ed 'state)
                                (ui-edit (window-ref ed 'ui))))
         (set! edit-difference
               (lambda (a b) (set! compared (+ compared 1)) (plain a b)))
         (tasks-editor-test-type! "Begun. ")
         (let ([drafted (and (string-prefix? "Begun. scroll"
                                             (tasks-editor-test-draft))
                             (string-prefix? "scroll"
                                             (tasks-editor-test-description))
                             (= compared 0))]
               [one (status)])
           (set! edit-difference plain)
           (tasks-editor-test-press! 'return)
           (tasks-editor-test-type! "ab")
           (let ([two (status)])
             (tasks-editor-test-press! 'backspace)
             (tasks-editor-test-press! 'backspace)
             (tasks-editor-test-press! 'backspace)
             (let ([joined (status)])
               (tasks-editor-test-press! #\s 'ctrl)
               (printf "  ~s\n" (list one two joined))
               (and drafted
                    (string-prefix? "Line 1, column 8  ·  5,007 of" one)
                    (string-prefix? "Line 2, column 3" two)
                    (string-prefix? "Line 1, column 8" joined)
                    (not (tasks-editor-test-editor))
                    (not (tasks-editor-test-waiting?))
                    (string-prefix? "Begun. scroll"
                                    (tasks-editor-test-description))))))))

(check "Ctrl+E in the description opens it, the caret where it was; Escape \
        with no changes closes it"
       (let ([w tasks-editor-test-window] [ui (tasks-editor-test-ui)])
         (ui-focus! ui 'description 2)
         (invalidate! w)
         (steps 2)
         (tasks-editor-test-press! #\e 'ctrl)
         (let* ([ed (tasks-editor-test-editor)]
                [caret (and ed (ui-caret (window-ref ed 'ui)))])
           (tasks-editor-test-press! 'escape)
           (and ed (eqv? caret 2) (not (tasks-editor-test-editor))
                (not (tasks-editor-test-waiting?))))))

(check "Escape with changes asks first; Keep editing goes back to the \
        text, the caret where it was; Cancel, then Discard, leaves the \
        description as it was, the editor gone"
       (let* ([ed (tasks-editor-test-open!)] [eui (window-ref ed 'ui)]
              [before (tasks-editor-test-description)])
         (tasks-editor-test-type! "XY")
         (tasks-editor-test-press! 'escape)
         (let ([asked (and (tasks-editor-test-editor)
                           (ui-find eui '(discard 1)) #t)])
           (test-click! ed '(discard 0))
           (steps 1)
           (let ([kept (and (tasks-editor-test-editor)
                            (not (ui-find eui 'discard))
                            (eq? 'text (ui-focused eui))
                            (= 2 (ui-caret eui)))])
             (test-click! ed 'cancel)
             (steps 1)
             (tasks-editor-test-press! 'return)
             (and asked kept (not (tasks-editor-test-editor))
                  (not (tasks-editor-test-waiting?))
                  (equal? (tasks-editor-test-description) before))))))

(check "maximized, it types at the end of the text; closed by its window, \
        it lets Tasks go, the draft lost"
       (let ([ed (tasks-editor-test-open!)])
         (toggle-maximize! ed)
         (steps 2)
         (tasks-editor-test-press! 'end 'ctrl)
         (tasks-editor-test-type! "!")
         (let ([typed (and (maximized? ed) (not (window-error ed))
                           (string-suffix? "!" (tasks-editor-test-draft)))])
           (close-window! ed)
           (steps 2)
           (and typed (not (tasks-editor-test-editor))
                (not (tasks-editor-test-waiting?)) (focused-window)
                (not (string-suffix? "!"
                                     (tasks-editor-test-description)))))))

(check "Save into a task deleted meanwhile keeps the draft in a new task \
        of its title, selected, and a toast names it"
       (let* ([v (tasks-editor-test-view)]
              [gone (add-task! "Gone soon" 'status 'review
                               'description "Old.")])
         (tasks-select! v gone)
         (steps 2)
         (let ([ed (tasks-open-editor! v gone 0)])
           (steps 2)
           (delete-task! gone)
           (steps 1)
           (set! *toasts* '())
           (tasks-editor-test-type! "Kept. ")
           (tasks-editor-test-press! #\s 'ctrl)
           (let* ([new (find (lambda (t)
                               (equal? (task-description t) "Kept. Old."))
                             *tasks*)]
                  [ok (and new (not (memq ed (windows)))
                           (not (tasks-editor-test-waiting?))
                           (equal? (task-title new) "Gone soon")
                           (eq? new (tasks-view-selected v))
                           (exists (lambda (t)
                                     (string-contains-ci? (vector-ref t 1)
                                                          (task-label new)))
                                   *toasts*))])
             (when new (delete-task! new))
             (set! *toasts* '())
             (tasks-select! v tasks-editor-test-task)
             (steps 2)
             ok))))

(check "closing Tasks closes its editor"
       (let ([ed (tasks-editor-test-open!)])
         (close-window! tasks-editor-test-window)
         (steps 1)
         (not (memq ed (windows)))))
(test-backlog!)
