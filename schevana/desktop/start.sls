;;; (schevana desktop start) — the desktop's start, which runs in "/" once
;;; core1 has loaded the world there ((schevana desktop main)). It loads the
;;; user's folders and settings, opens the window or the headless target and
;;; the first windows, then runs until the desktop quits. What the command
;;; line asked for is in *schevana-options*.

(library (schevana desktop start)
  (export
    *desktop-start-thunks* desktop-at-start! desktop-start!)
  (import (chezscheme)
          (only (schevana base) define-state library-layer)
          (only (schevana core) *schevana-options* *schevana-root* find-window
                load-user-folders! load-user-init! move-window! schevana-boot!
                schevana-end! schevana-run! screen-w world-after-load!
                world-load-now!)
          (only (schevana kits app) app-launch!)
          (only (schevana services pacer-lab) pacer-lab-log-load!)
          (only (schevana services profile) profile-flag-log!)
          (only (schevana services theme-file) theme-file-load!)
          (only (schevana desktop icon) update-app-icon!
                uninstall-desktop-entry! install-desktop-entry!))

  (library-layer desktop)

  ;; Thunks that run as the desktop starts, after the user's folders load and
  ;; before the saved theme, in the order they were added: each does what an
  ;; app's session needs (desktop-at-start!). A world whose desktop never
  ;; starts doesn't run them.
  (define-state *desktop-start-thunks* '())

  (define (desktop-at-start! thunk)
    (set! *desktop-start-thunks* (append *desktop-start-thunks* (list thunk))))

  (define (desktop-start!)
    (define (option key) (cdr (assq key *schevana-options*)))
    ;; ~/.schevana.d's kits, services, styles, palettes, wallpapers, desktop
    ;; and apps load before the saved theme, which may name a style or a
    ;; palette of the user's.
    (load-user-folders!)
    (for-each (lambda (thunk) (thunk)) *desktop-start-thunks*)
    ;; A checkout's private folder (.work), if it has one, keeps a log of
    ;; every late tick, for whoever is looking into them.
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
    ;; The saved theme loads first, so the window opens at the saved scale.
    (theme-file-load!)
    (let ([size (option 'size)])
      (schevana-boot! (option 'mode) (car size) (cdr size)
                      (option 'full-screen?)))
    (update-app-icon!)
    ;; The pacer lab is turned on again if it was on
    ;; ((schevana services pacer-lab)).
    (pacer-lab-log-load!)
    ;; The first apps, launched through the registry: their launchers' names
    ;; are defined later than this file, with the apps, which load after the
    ;; screen shows; these two are loaded first.
    (world-load-now! '(schevana apps clock))
    (world-load-now! '(schevana apps repl))
    (let ([w (screen-w)])
      (app-launch! 'clock)
      (move-window! (find-window 'clock) (- w 270) 60)
      (app-launch! 'repl))
    ;; Your init file and the command line's expressions run once all of the
    ;; world has loaded, the apps that waited included, so that what they
    ;; name exists.
    (world-after-load!
     (lambda ()
       (load-user-init!)
       (for-each (lambda (e) (eval (read (open-input-string e))))
                 (option 'evals))))
    (schevana-run!)
    (schevana-end!)))
