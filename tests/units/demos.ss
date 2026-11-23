;;; tests/units/demos.ss — the demos. Each launcher at the tree's root runs
;;; its program headless, on a screen of its own and in a process of its
;;; own, and tells what it read back (a window that drew, its parts found
;;; in the program's "/"). One of them, the checklist, is a plain script:
;;; its .sh gives scheme-script the tree as its library folder. On the
;;; desktop (with its folder auto-loaded), each demo's library (demo/)
;;; registers its app, which opens a window that draws, and the backlog
;;; enters Tasks' tasks.

;; Runs launcher (a file at the tree's root: one of Schevana's launchers,
;; or a shell script) headless, with args and with HOME set to a scratch
;; folder. Returns its exit status and what it printed: (status . output).
(define (demos-run launcher . args)
  (let ([home (string-append out-dir "/demos-home")]
        [said (string-append out-dir "/demos-" launcher ".txt")]
        [file (string-append *schevana-root* "/" launcher)])
    (unless (file-directory? home) (mkdir home))
    (let ([status
           (test-system-within 120
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
 '("window-demo.sh" "rings-demo" "game-demo")
 '("a host app made of widgets, a plain script" "drawing alone" "a game"))

;; The checklist in a style of Schevana's own that is also a desktop's
;; look (Cons draws the desktop's bars too), chosen by host-main's --style:
;; the checklist is drawn in it, with no desktop; a name that is no style's
;; is refused.
(let ([cons (demos-run "window-demo.sh" "--style" "cons")]
      [none (demos-run "window-demo.sh" "--style" "no-such")])
  (check (format "--style draws the checklist in a style by name, and refuses \
                  one that isn't ~s" (list cons none))
         (and (eqv? (car cons) 0)
              (string-contains-ci? (cdr cons) "in cons, drawn")
              (not (eqv? (car none) 0))
              (string-contains-ci? (cdr none) "no style no-such"))))

;; A program that takes a desktop's look, GNOME's, without the desktop:
;; the looks come before the desktop and bring none of it, no surface and
;; no key.
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
  (let* ([status (test-system-within 120
                   (string-append (test-chez (list (cons "HOME" home)) prog)
                                  " > " (test-sh-word said) " 2>&1"))]
         [out (call-with-input-file said get-string-all)])
    (check (format "a program taking GNOME's look and no desktop has none of \
                    the desktop's surfaces or keys (~s)" out)
           (and (eqv? status 0)
                (equal? (guard (c [#t #f]) (read (open-input-string out)))
                        '(gnome () ()))))))

;; A path given to auto-load! or the library search is kept in full:
;; relative to the current folder, with ~ as the home folder, and with .
;; and .. resolved.
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
;; ./desktop demo loads it. Each library in it runs, and an app it defines
;; registers itself. Boids 3D's parts, in demo/boids3d/, are no entries:
;; they load as its imports.
(let ([dir (string-append *schevana-root* "/demo")])
  (auto-load! dir)
  (check (format "a folder auto-loaded joins the library search and loads \
                  its libraries, by their names from the tree: the demos' \
                  apps register, Boids, Life and the rest among them, and \
                  Boids 3D's parts are no entries; a file is no folder to \
                  load ~s"
                 (auto-load-entries dir))
         (and (equal? (auto-load-entries dir)
                      '((demo backlog) (demo boids) (demo boids3d)
                        (demo life) (demo rings) (demo sketch)
                        (demo springies)))
              ;; made absolute, as the tree's root may not be (".")
              (string-suffix? "/demo" (car (last-pair (auto-loads))))
              (for-all (lambda (app) (memq app (apps)))
                       '(boids boids3d life rings sketch springies))
              ;; a folder of the library search, which a file can't be
              (exists (lambda (d)
                        (equal? (path-full (if (pair? d) (car d) d))
                                (path-full dir)))
                      (library-directories))
              (guard (c [#t #t])
                (auto-load! (string-append *schevana-root* "/README.md"))
                #f))))

;; The backlog, entered with Tasks' own procedures as the folder loaded:
;; its tasks in their columns, with the ids they were entered with (TASK-25
;; deleted again), what each waits for, and four long descriptions: the
;; README, the kit's source cut to the most a description holds, the
;; titles as one paragraph, and the start of the kit in base64, with no
;; space. A reload that evaluates it again enters nothing.
(check "the backlog enters Schevana's tasks once, as the folder loads, in \
        their columns and with their links, four with long descriptions; \
        a reload enters none"
       (let* ([ids (lambda (status) (map task-id (tasks-list 'status status)))]
              [text (lambda (id) (task-description (find-task id)))]
              [readme (call-with-input-file
                        (string-append *schevana-root* "/README.md")
                        get-string-all)]
              [has? (lambda (s c)
                      (exists (lambda (i) (char=? (string-ref s i) c))
                              (iota (string-length s))))]
              [entered (length *tasks*)])
         (test-reload-library! '(demo backlog))
         (and (= entered (length *tasks*) 32)
              (not (find-task 25))
              (equal? (ids 'todo) '(16 11 12 13 31 14 22 15 17 18 19 20 21 26
                                    23 24 27 28 29 30))
              (equal? (ids 'doing) '(9 33 10))
              (equal? (ids 'review) '(7 8))
              (equal? (ids 'done) '(1 2 3 4 5 6 32))
              (equal? (task-blocked-by (find-task 13)) '(31 10))
              (equal? (text 27)
                      (substring readme 0 (min (string-length readme)
                                               tasks-description-max)))
              (= 65536 (string-length (text 28)) (string-length (text 29))
                 (string-length (text 30)))
              (not (has? (text 29) #\newline)) (not (has? (text 30) #\space))
              ;; ";;; (schevana k", the kit's first bytes
              (string-prefix? "Ozs7IChzY2hldmFuYSBr" (text 30)))))

;; A folder of the test's own files, read again at (reload!): a file added
;; since then loads, and one taken away is let go; folders inside it are
;; read too.
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
 '(rings))

;; A library from outside the tree: its name comes from its first form,
;; and the folder from which its name is found is added to the library
;; search, so that it loads by its name and "/" has what it exports. The
;; folder beside it of its name holds its part, which loads as its import
;; and is none of the world's: in the library edition "/" hasn't the
;; part's names. A change to the part, made before any reload, is seen by
;; the next one, which evaluates the library again.
(let* ([dir (string-append out-dir "/autolib")]
       [part (lambda (word)
               (call-with-output-file
                 (string-append dir "/auto-test/hello/word.sls")
                 (lambda (p)
                   (write `(library (auto-test hello word)
                             (export auto-hello-word)
                             (import (chezscheme))
                             (define auto-hello-word ',word))
                          p))
                 'replace))])
  (system (format "rm -rf '~a' && mkdir -p '~a/auto-test/hello'" dir dir))
  (part 'hello)
  (call-with-output-file (string-append dir "/auto-test/hello.sls")
    (lambda (p)
      (write '(library (auto-test hello)
                (export auto-hello)
                (import (chezscheme) (auto-test hello word))
                (define (auto-hello) auto-hello-word))
             p)))
  (auto-load! dir)
  (let ([first (eval '(auto-hello) *world-env*)])
    (part 'hi)
    (reload!)
    (steps 2)
    (let ([again (eval '(auto-hello) *world-env*)])
      (check (format "a library from outside the tree loads by the name its \
                      first form gives; the folder of its name holds its \
                      part, which loads as its import, not as the world's, \
                      and a reload sees a change to the part ~s"
                     (list (auto-load-entries dir) first again))
             (and (equal? (auto-load-entries dir) '((auto-test hello)))
                  (eq? first 'hello)
                  (eq? again 'hi)
                  (or test-hacker?
                      (not (top-level-bound? 'auto-hello-word
                                             *world-env*))))))))
