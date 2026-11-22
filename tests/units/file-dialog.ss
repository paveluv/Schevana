;;; tests/units/file-dialog.ss — the desktop's file dialog
;;; ((schevana desktop file-dialog)), by itself, over a tree of its own in the
;;; output folder: paths and crumbs, what the list shows, its keys, and a
;;; file picked or the dialog cancelled.

;; out-dir/files: folders a (inner.ss in it) and b, files one.ss,
;; two.txt and .hidden.ss.
(define file-dialog-test-tree
  (let ([root (file-dialog-resolve (current-directory)
                                   (string-append out-dir "/files"))])
    (for-each (lambda (d) (unless (file-directory? d) (mkdir d)))
              (list root (string-append root "/a") (string-append root "/b")))
    (for-each (lambda (f)
                (call-with-output-file (string-append root "/" f)
                  (lambda (p) (display "x" p))
                  'replace))
              '("one.ss" "two.txt" ".hidden.ss" "a/inner.ss"))
    root))

;; A window and the dialog over it, open on the tree, for Scheme files or
;; all; what it picked and whether it was cancelled, kept in boxes.
(define (file-dialog-test-open)
  (let* ([parent (open-window "Waits" 'size '(300 . 200) 'pos '(40 . 40))]
         [picked (box #f)] [cancelled (box 0)])
    (open-file-dialog parent "Load" "Load"
                      (lambda (p) (set-box! picked p))
                      'folder file-dialog-test-tree
                      'types '(("Scheme files" "ss") ("All files"))
                      'on-cancel
                      (lambda () (set-box! cancelled (+ 1 (unbox cancelled)))))
    (steps 2)
    (let* ([fd (focused-window)] [d (window-ref fd 'state)])
      ;; the keys are the dialog's with no field focused
      (ui-focus! (file-dialog-ui d) #f)
      (invalidate! fd)
      (steps 1)
      (values parent fd d picked cancelled))))

(define (file-dialog-test-names d)
  (map file-dialog-entry-name (or (file-dialog-shown d) '())))

(define (file-dialog-test-press! key . mods)
  (inject! (list 'key-down key mods))
  (steps 2))

(check "a path as the dialog reads it: ~ is home's, x is from the folder, \
        its . and .. worked out, no / at its end; its crumbs from Home when \
        it's in home, else from the Computer"
       (let ([home (file-dialog-home)])
         (and (equal? (file-dialog-resolve "/a/b" "../c/./d/") "/a/c/d")
              (equal? (file-dialog-resolve "/a" "/x//y/") "/x/y")
              (equal? (file-dialog-resolve "/a" "~") home)
              (equal? (file-dialog-resolve "/a" "~/p")
                      (file-dialog-join home "p"))
              (equal? (file-dialog-crumbs "/home/u/p" "/home/u")
                      '(("Home" . "/home/u") ("p" . "/home/u/p")))
              (equal? (file-dialog-crumbs "/srv/x" "/home/u")
                      '(("Computer" . "/") ("srv" . "/srv")
                        ("x" . "/srv/x"))))))

(check "it shows a folder's folders first, then the files of the type \
        chosen, by name; Ctrl+H the hidden ones too; typing filters"
       (let-values ([(parent fd d picked cancelled) (file-dialog-test-open)])
         (let ([scheme (file-dialog-test-names d)])
           (file-dialog-type-set! d 1)
           (let ([all (file-dialog-test-names d)])
             (file-dialog-test-press! #\h 'ctrl)
             (let ([hidden (file-dialog-test-names d)])
               (file-dialog-test-press! #\h 'ctrl)
               (ui-focus! (file-dialog-ui d) #f)
               (inject! '(text "on"))
               (steps 2)
               (let ([filtered (file-dialog-test-names d)])
                 (close-window! fd)
                 (close-window! parent)
                 (printf "  ~s\n" (list scheme all hidden filtered))
                 (and (equal? scheme '("a" "b" "one.ss"))
                      (equal? all '("a" "b" "one.ss" "two.txt"))
                      (member ".hidden.ss" hidden)
                      (equal? filtered '("one.ss")))))))))

(check "keys: Down selects, Return goes into the folder selected, \
        Backspace goes up, Alt+Left back and Alt+Right forward"
       (let-values ([(parent fd d picked cancelled) (file-dialog-test-open)])
         (let ([folder (lambda () (path-last (file-dialog-folder d)))])
           (file-dialog-test-press! 'down)          ; a
           (file-dialog-test-press! 'return)        ; into a
           (let ([into (folder)])
             (file-dialog-test-press! 'backspace)   ; up, to the tree
             (let ([up (folder)])
               (file-dialog-test-press! 'left 'alt) ; back, into a
               (let ([back (folder)])
                 (file-dialog-test-press! 'right 'alt)
                 (let ([forward (folder)])
                   (close-window! fd)
                   (close-window! parent)
                   (and (equal? into "a") (equal? up "files")
                        (equal? back "a") (equal? forward "files")))))))))

(check "Return on a file picks it: the dialog closes and the window that \
        waited gets its path; Escape cancels, telling it once"
       (let-values ([(parent fd d picked cancelled) (file-dialog-test-open)])
         (file-dialog-test-press! 'down)   ; a
         (file-dialog-test-press! 'down)   ; b
         (file-dialog-test-press! 'down)   ; one.ss
         (file-dialog-test-press! 'return)
         (let ([gone (not (memq fd (windows)))] [path (unbox picked)])
           (let-values ([(p2 fd2 d2 picked2 cancelled2)
                         (file-dialog-test-open)])
             (file-dialog-test-press! 'escape)
             (let ([cancel-gone (not (memq fd2 (windows)))])
               (close-window! parent)
               (close-window! p2)
               (and gone
                    (equal? path (file-dialog-join file-dialog-test-tree
                                                   "one.ss"))
                    cancel-gone (= (unbox cancelled2) 1)
                    (not (unbox picked2))))))))

(check "a click on a file selects it and names it; a double click on a \
        folder goes into it"
       (let-values ([(parent fd d picked cancelled) (file-dialog-test-open)])
         (let ([row (lambda (i) (list '(file-dialog list) 'row i))])
           (test-click! fd (row 2))          ; one.ss
           (let ([named (file-dialog-name d)])
             (test-click! fd (row 0) 2)      ; a
             (steps 1)
             (let ([into (path-last (file-dialog-folder d))])
               (close-window! fd)
               (close-window! parent)
               (and (equal? named "one.ss") (equal? into "a")))))))
