;;; (schevana desktop start) — the desktop's start, in "/" once core1 has
;;; loaded the world there ((schevana desktop main)): the user's folders and
;;; settings, the window or the headless target, the first windows, then the
;;; run till it quits. What the command line asked is *schevana-options*.

(library (schevana desktop start)
  (export
    *desktop-start-thunks* desktop-at-start! desktop-start!)
  (import (chezscheme)
          (only (schevana base) define-state library-layer)
          (only (schevana core) *schevana-options* *schevana-root* find-window
                load-user-folders! load-user-init! move-window! schevana-boot!
                schevana-end! schevana-run! screen-w world-load-now!)
          (only (schevana kits app) app-launch!)
          (only (schevana services grant) grant-file-load!)
          (only (schevana services pacer-lab) pacer-lab-log-load!)
          (only (schevana services profile) profile-flag-log!)
          (only (schevana services theme-file) theme-file-load!)
          (only (schevana desktop icon) update-app-icon!
                uninstall-desktop-entry! install-desktop-entry!))

  (library-layer desktop)

  ;; What runs as the desktop starts, after the user's folders and before the
  ;; saved theme, the first first: an app's thunk of what its session needs
  ;; (desktop-at-start!), which a test's world, never started, doesn't run.
  (define-state *desktop-start-thunks* '())

  (define (desktop-at-start! thunk)
    (set! *desktop-start-thunks* (append *desktop-start-thunks* (list thunk))))

  (define (desktop-start!)
    (define (option key) (cdr (assq key *schevana-options*)))
    ;; ~/.schevana.d's kits, services, styles, palettes, wallpapers, desktop
    ;; and apps, before the saved theme is loaded: it may name a style or
    ;; palette of the user's.
    (load-user-folders!)
    ;; What you allowed apps in sandboxes ((schevana services grant)).
    (grant-file-load!)
    (for-each (lambda (thunk) (thunk)) *desktop-start-thunks*)
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
    ;; The pacer lab goes on if it was on ((schevana services pacer-lab)).
    (pacer-lab-log-load!)
    ;; The first apps, by the registry: their launchers' names come later
    ;; than this file, with the apps, which load after the screen shows but
    ;; for these two, loaded first.
    (world-load-now! "apps/clock.ss")
    (world-load-now! '(schevana apps repl))
    (let ([w (screen-w)])
      (app-launch! 'clock)
      (move-window! (find-window 'clock) (- w 270) 60)
      (app-launch! 'repl))
    (for-each (lambda (e) (eval (read (open-input-string e))))
              (option 'evals))
    (schevana-run!)
    (schevana-end!)))
