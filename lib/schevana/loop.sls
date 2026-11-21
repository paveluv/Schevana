;;; (schevana loop) — the loop: steps, events, boot, the collector; schevana-
;;; main runs a program on it (src/core1/system.ss). It exports what the pieces
;;; above it and the world use of it.

(library (schevana loop)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana core0)
          (schevana boot) (schevana platform) (schevana processes)
          (schevana gpu) (schevana pacer) (schevana screen))

  (include-sources "src/core1/system.ss")
  ;; Boots the screen, mode sdl (a window w × h logical pixels, or full
  ;; screen) or headless, runs world, a thunk that opens what the program
  ;; shows, then the world till it quits, and ends the process. With a
  ;; window, core0 keeps this thread, the process's first, for the screen,
  ;; and the world runs on its own; headless, one thread plays both,
  ;; unless fork? asks for the two with no window (a test's).
  (define (loop-main mode w h full? world . fork?)
    (define (run)
      (core1-thread!)
      (schevana-boot! mode w h full?)
      (world)
      (schevana-run!)
      (schevana-end!))
    (if (or (eq? mode 'sdl) (and (pair? fork?) (car fork?)))
        (core0-run! mode w h full? run)
        (run)))

  (define-exports loop-exports
    (export (world)
      *input-step?* post-core1! (settable *loop-event*) schevana-step!
      schevana-run! quit! schevana-end! uptime-ms load-user-init!
      user-directory schevana-boot! collector-declining? source-path
      source-files *source-texts* keep-source-text! load-file!
      (settable *app-loader*) load-user-folders! reload! loop-main)))
