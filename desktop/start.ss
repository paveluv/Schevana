;;; desktop/start.ss — the desktop's start, in "/" once core1 has loaded the
;;; world there ((schevana desktop main)): the user's folders and settings,
;;; the window or the headless target, the first windows, then the run till
;;; it quits. What the command line asked is *schevana-options*.

(define (desktop-start!)
  (define (option key) (cdr (assq key *schevana-options*)))
  ;; ~/.schevana.d's kits, desktop, styles, palettes, wallpapers and apps,
  ;; before the saved theme is loaded: it may name a style or palette of
  ;; the user's.
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
  ;; Install or remove the desktop entry and icon, then stop.
  (case (option 'desktop)
    [(install)
     (theme-file-load!)
     (for-each (lambda (f) (printf "wrote ~a~%" f)) (install-desktop-entry!))
     (exit 0)]
    [(uninstall)
     (for-each (lambda (f) (printf "removed ~a~%" f))
               (uninstall-desktop-entry!))
     (exit 0)])
  ;; The saved theme first, so the window opens at the saved scale.
  (theme-file-load!)
  (let ([size (option 'size)])
    (schevana-boot! (option 'mode) (car size) (cdr size)
                    (option 'full-screen?)))
  (update-app-icon!)
  (load-user-init!)
  ;; The pacer lab goes on if it was on (services/pacer-lab.ss).
  (pacer-lab-log-load!)
  ;; The first apps, by the registry: their launchers' names come later
  ;; than this file, with the apps.
  (let ([w (screen-w)])
    (app-launch! 'clock)
    (move-window! (find-window 'clock) (- w 270) 60)
    (app-launch! 'repl))
  (for-each (lambda (e) (eval (read (open-input-string e))))
            (option 'evals))
  (schevana-run!)
  (schevana-end!))
