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

;; A path is kept in full, as given to auto-load! or the library search:
;; from the current folder, ~ the home folder, . and .. resolved.
(check "paths are kept in full: relative, ~, . and .., a slash at the end"
       (and (equal? (path-full "a/./b/../c/")
                    (path-full (string-append (current-directory) "/a/c")))
            (equal? (path-full "/x/y/../../z") "/z")
            (equal? (path-full "~/apps")
                    (path-full (string-append (getenv "HOME") "/apps")))
            (equal? (path-full "/") "/")
            (for-all (lambda (p)
                       (and (path-absolute? p)
                            (not (string-contains-ci? p "/./"))))
                     (auto-loads))))

;; On the desktop: the demos' folder loaded with the world, as
;; ./schevana-desktop schevana-demo has it: each library in it runs, and
;; an app it defines registers itself.
(let ([dir (string-append *schevana-root* "/schevana-demo")])
  (auto-load! dir)
  (check (format "a folder auto-loaded loads its libraries, by their names \
                  from the tree: the demos' apps register ~s"
                 (auto-load-entries dir))
         (and (equal? (auto-load-entries dir)
                      '((schevana-demo game) (schevana-demo rings)))
              ;; made absolute, as the tree's root may not be (".")
              (string-suffix? "/schevana-demo" (car (last-pair (auto-loads))))
              (for-all (lambda (app) (memq app (apps))) '(rings game)))))

;; A folder of files of the test's own, read again at (reload!): a file
;; added since loads, and one taken away is let go of; folders inside it
;; are read too.
(let* ([dir (string-append out-dir "/auto")]
       [file (lambda (name)
               (call-with-output-file (string-append dir "/" name)
                 (lambda (p)
                   (write `(set! auto-counted
                             (cons ',(string->symbol (path-root
                                                      (path-last name)))
                                   auto-counted))
                          p))
                 'replace))])
  (system (format "rm -rf '~a' && mkdir -p '~a/inner'" dir dir))
  (eval '(define auto-counted '()) *world-env*)
  (file "a.ss")
  (file "inner/c.ss")
  (auto-load! dir)
  (let ([first (eval 'auto-counted *world-env*)])
    (file "b.ss")
    (delete-file (string-append dir "/a.ss"))
    (eval '(set! auto-counted '()) *world-env*)
    (reload!)
    (steps 2)
    (let ([again (eval 'auto-counted *world-env*)])
      (check (format "an auto-loaded folder loads its files, recursively, \
                      and (reload!) reads it again: what was added since \
                      loads, what was taken away doesn't ~s"
                     (list first again))
             (and (equal? first '(c a))
                  (equal? again '(c b)))))))

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

;; A library from outside the tree: its name from its first form, and the
;; folder its name is found from added to the library search, so that it
;; loads by its name and "/" has what it exports.
(let ([dir (string-append out-dir "/autolib")])
  (system (format "rm -rf '~a' && mkdir -p '~a/auto-test'" dir dir))
  (call-with-output-file (string-append dir "/auto-test/hello.sls")
    (lambda (p)
      (write '(library (auto-test hello)
                (export auto-hello)
                (import (chezscheme))
                (define auto-hello 'hello))
             p)))
  (auto-load! dir)
  (check (format "a library from outside the tree loads by the name its \
                  first form gives ~s" (auto-load-entries dir))
         (and (equal? (auto-load-entries dir) '((auto-test hello)))
              (eq? (eval 'auto-hello *world-env*) 'hello))))
