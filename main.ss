;;; main.ss — boot Schevana.
;;;
;;;   scheme --script main.ss [--size 1280x800] [--fullscreen] [--headless]
;;;                           [--eval EXPR] ...
;;;   scheme --script main.ss --install-desktop     ; the app icon for GNOME
;;;                                                   and co.
;;;   scheme --script main.ss --uninstall-desktop
;;;
;;; --eval expressions run after boot, e.g.
;;;   --eval '(after 2000 (lambda () (png-write-screen "s.png") (quit!)))'

(define *schevana-root*
  (let ([dir (path-parent (car (command-line)))])
    (if (string=? dir "") "." dir)))

(load (string-append *schevana-root* "/load.ss"))
;; ~/.schevana.d's kits, desktop, styles, palettes, wallpapers and apps,
;; before the saved theme is loaded: it may name a style or palette of the
;; user's.
(load-user-folders!)
;; What you allowed apps in sandboxes (services/grant.ss).
(grant-file-load!)
;; Where the Debug REPL listens, while it's open (apps/debug-repl.ss).
(debug-repl-path! (debug-repl-default-path))
;; A checkout's private folder, if it has one, keeps every late tick, for
;; whoever is looking into them.
(let ([dir (string-append *schevana-root* "/.work")])
  (when (file-directory? dir)
    (profile-flag-log! (string-append dir "/flags.log"))))

(define (parse-size s)
  (let ([parts (string-split s #\x)])
    (cons (string->number (car parts)) (string->number (cadr parts)))))

(define start-fullscreen?
  (and (member "--fullscreen" (command-line-arguments)) #t))

;; Install or remove the desktop entry and icon, then stop.
(cond
  [(member "--install-desktop" (command-line-arguments))
   (theme-file-load!)
   (for-each (lambda (f) (printf "wrote ~a~%" f)) (install-desktop-entry!))
   (exit 0)]
  [(member "--uninstall-desktop" (command-line-arguments))
   (for-each (lambda (f) (printf "removed ~a~%" f)) (uninstall-desktop-entry!))
   (exit 0)])

(let loop ([args (remove "--fullscreen" (command-line-arguments))]
           [mode 'sdl]
           [size '(1280 . 800)]
           [evals '()])
  (cond
    [(null? args)
     (theme-file-load!)   ; first, so the window opens at the saved scale
     (schevana-boot! mode (car size) (cdr size) start-fullscreen?)
     (update-host-icon!)
     (load-user-init!)
     (let ([w (screen-w)])
       (clock)
       (move-window! (find-window 'clock) (- w 270) 60)
       (repl))
     (for-each (lambda (e) (eval (read (open-input-string e)))) (reverse evals))
     (schevana-run!)
     ;; Chez reads a script a form at a time: were this file changed during
     ;; the run, it would go on from where it was, in the middle of something
     (exit 0)]
    [(string=? (car args) "--headless") (loop (cdr args) 'headless size evals)]
    [(and (string=? (car args) "--size") (pair? (cdr args)))
     (loop (cddr args) mode (parse-size (cadr args)) evals)]
    [(and (string=? (car args) "--eval") (pair? (cdr args)))
     (loop (cddr args) mode size (cons (cadr args) evals))]
    [else
     (fprintf (current-error-port)
              "usage: schevana [--size WxH] [--fullscreen] [--headless] \
               [--eval EXPR]...\n       \
               schevana --install-desktop | --uninstall-desktop\n")
     (exit 1)]))
