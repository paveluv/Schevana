;;; tests/units/demos.ss — the demos (schevana-demo/): each launcher at the
;;; tree's root runs its program on a screen of its own, headless, in a
;;; process of its own, and tells what it read back; on the desktop
;;; (--demo) each demo's library registers its app, which opens a window
;;; that draws.

;; What launcher (a file at the tree's root) prints, run headless with
;; HOME a scratch folder, and its exit status: (status . output).
(define (demos-run launcher)
  (let ([home (string-append out-dir "/demos-home")]
        [said (string-append out-dir "/demos-" launcher ".txt")])
    (unless (file-directory? home) (mkdir home))
    (let ([status
           (units-system-within 120
             (string-append
              (test-chez (list (cons "HOME" home))
                         (string-append *schevana-root* "/" launcher)
                         "--headless")
              " > " (test-sh-word said) " 2>&1"))])
      (cons status (call-with-input-file said get-string-all)))))

(for-each
 (lambda (launcher what)
   (let ([run (demos-run launcher)])
     (check (format "~a runs on a screen of its own and tells what it read \
                     back: ~a (~s)" launcher what (cdr run))
            (and (eqv? (car run) 0)
                 (string-contains-ci? (cdr run) "pixels")))))
 '("schevana-window-demo" "schevana-rings-demo" "schevana-game-demo")
 '("a surface and a window" "drawing alone" "a game"))

;; On the desktop: each demo's library invoked, as --demo has it.
(desktop-demos-load!)

(check (format "--demo registers each demo's app (~a)" (desktop-demos))
       (and (= (length (desktop-demos)) 3)
            (for-all (lambda (app) (memq app (apps)))
                     '(window-demo rings game))))

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
 '(window-demo rings game))
