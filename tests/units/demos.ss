;;; tests/units/demos.ss — the demos: each launcher at the tree's root runs
;;; its program on a screen of its own, headless, in a process of its own,
;;; and tells what it read back (a window that drew, its parts found in the
;;; program's "/"); a plain script among them, the checklist, its .sh
;;; giving scheme-script the tree as its library folder. On the desktop
;;; (--demo) each demo's library (schevana-demo/) registers its app, which
;;; opens a window that draws.

;; What launcher (a file at the tree's root: a launcher of Schevana's, or a
;; shell script) prints, run headless with args more and HOME a scratch
;; folder, and its exit status: (status . output).
(define (demos-run launcher . args)
  (let ([home (string-append out-dir "/demos-home")]
        [said (string-append out-dir "/demos-" launcher ".txt")]
        [file (string-append *schevana-root* "/" launcher)])
    (unless (file-directory? home) (mkdir home))
    (let ([status
           (units-system-within 120
             (string-append
              (if (equal? (path-extension launcher) "sh")
                  (format "exec env HOME=~a sh ~a --headless~{ ~a~}"
                          (test-sh-word home) (test-sh-word file)
                          (map test-sh-word args))
                  (apply test-chez (list (cons "HOME" home)) file "--headless"
                         args))
              " > " (test-sh-word said) " 2>&1"))])
      (cons status (call-with-input-file said get-string-all)))))

(for-each
 (lambda (launcher what)
   (let ([run (demos-run launcher)])
     (check (format "~a runs on a screen of its own and tells what it read \
                     back: ~a (~s)" launcher what (cdr run))
            (and (eqv? (car run) 0)
                 (string-contains-ci? (cdr run) "pixels")
                 (not (string-contains-ci? (cdr run) "crashed"))))))
 '("schevana-window-demo.sh" "schevana-rings-demo" "schevana-game-demo")
 '("a host app made of widgets, a plain script" "drawing alone" "a game"))

;; The checklist in a style of Schevana's own, a desktop's look among them
;; (Cons draws the desktop's bars too), host-main's --style: drawn in it,
;; no desktop with it; a name that is no style's is refused.
(let ([cons (demos-run "schevana-window-demo.sh" "--style" "cons")]
      [none (demos-run "schevana-window-demo.sh" "--style" "no-such")])
  (check (format "--style draws the checklist in a style by name, and refuses \
                  one that isn't ~s" (list cons none))
         (and (eqv? (car cons) 0)
              (string-contains-ci? (cdr cons) "in cons, drawn")
              (not (eqv? (car none) 0))
              (string-contains-ci? (cdr none) "no style no-such"))))

;; A program that takes a look of a desktop's, GNOME's, and no desktop: the
;; looks come before the desktop and bring none of it, no surface or key.
(let* ([home (string-append out-dir "/demos-home")]
       [prog (string-append out-dir "/demos-look.ss")]
       [said (string-append out-dir "/demos-look.txt")]
       [root (schevana-launch-root *schevana-root*)])
  (unless (file-directory? home) (mkdir home))
  (call-with-output-file prog
    (lambda (p)
      (for-each
       (lambda (x) (write x p) (newline p))
       `((load ,(string-append root "/src/launch.ss"))
         (schevana-libraries! ,root #f)
         (import (chezscheme) (schevana core) (only (schevana styles gnome)))
         (schevana-main 'headless 400 300 #f
           (lambda ()
             (set-style! 'gnome)
             (after 50
               (lambda ()
                 (guard (c [#t (display-condition c) (newline)])
                   (write (list (current-style)
                                (filter find-surface
                                        '(desktop taskbar topbar menu toasts))
                                *global-keys*))
                   (newline))
                 (quit!))))))))
    'replace)
  (let* ([status (units-system-within 120
                   (string-append (test-chez (list (cons "HOME" home)) prog)
                                  " > " (test-sh-word said) " 2>&1"))]
         [out (call-with-input-file said get-string-all)])
    (check (format "a program taking GNOME's look and no desktop has none of \
                    the desktop's surfaces or keys (~s)" out)
           (and (eqv? status 0)
                (equal? (guard (c [#t #f]) (read (open-input-string out)))
                        '(gnome () ()))))))

;; On the desktop: each demo's library invoked, as --demo has it.
(desktop-demos-load!)

(check (format "--demo registers each demo's app (~a)" (desktop-demos))
       (and (= (length (desktop-demos)) 2)
            (for-all (lambda (app) (memq app (apps)))
                     '(rings game))))

(for-each
 (lambda (app)
   (let ([before (length (windows))])
     (app-launch! app)
     (steps 3)
     (check (format "the ~a app opens a window that draws" app)
            (and (= (length (windows)) (+ before 1))
                 (window-title (car (windows)))))
     (close-window! (car (windows)))
     (steps 1)))
 '(rings game))
