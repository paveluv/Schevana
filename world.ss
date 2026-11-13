;;; world.ss — the world's boot, in "/" once core0 loaded the tree there
;;; (main.ss): the user's folders and settings, the window or the headless
;;; target, the first windows, then the run. What the command line asked,
;;; main.ss read: *schevana-options*.

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

;; What the command line asked (main-options in main.ss).
(define (schevana-option key) (cdr (assq key *schevana-options*)))

;; Install or remove the desktop entry and icon, then stop.
(case (schevana-option 'desktop)
  [(install)
   (theme-file-load!)
   (for-each (lambda (f) (printf "wrote ~a~%" f)) (install-desktop-entry!))
   (exit 0)]
  [(uninstall)
   (for-each (lambda (f) (printf "removed ~a~%" f)) (uninstall-desktop-entry!))
   (exit 0)])

;; The saved theme first, so the window opens at the saved scale.
(theme-file-load!)
(let ([size (schevana-option 'size)])
  (schevana-boot! (schevana-option 'mode) (car size) (cdr size)
                  (schevana-option 'full-screen?)))
(update-app-icon!)
(load-user-init!)
;; The pacer lab goes on if it was on (services/pacer-lab.ss).
(pacer-lab-log-load!)
(let ([w (screen-w)])
  (clock)
  (move-window! (find-window 'clock) (- w 270) 60)
  (repl))
(for-each (lambda (e) (eval (read (open-input-string e))))
          (schevana-option 'evals))

;; Chez reads a script a form at a time: were this file changed during the
;; run, it would go on from where it was, in the middle of something. So
;; the run and the end are one form.
(begin
  (schevana-run!)
  (schevana-end!))
