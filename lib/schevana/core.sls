;;; (schevana core) — the core, as a program has it: what
;;; src/core1/export.ss lists, each name read-only but the hooks, from the
;;; libraries the core is made of, and schevana-main, which runs a program
;;; on them:
;;;
;;;   (import (chezscheme) (schevana core))
;;;   (schevana-main 'sdl 640 400 #f
;;;     (lambda () (open-window ...)))

(library (schevana core)
  (export schevana-main)
  (import (chezscheme) (schevana layer) (schevana base) (schevana shader)
          (schevana socket) (schevana core0) (schevana recorder)
          (except (schevana boot) core1-exports) (schevana platform)
          (schevana theme-table) (schevana processes) (schevana gpu)
          (schevana fonts) (schevana draw) (schevana theme) (schevana pacer)
          (schevana windows) (schevana screen) (schevana loop))

  ;; Boots the screen, mode sdl (a window w × h logical pixels, or full
  ;; screen) or headless, runs world, a thunk that opens what the program
  ;; shows, then the world till it quits, and ends the process. With a
  ;; window, core0 keeps this thread, the process's first, for the screen,
  ;; and the world runs on its own; headless, one thread plays both,
  ;; unless fork? asks for the two with no window (a test's).
  (define (schevana-main mode w h full? world . fork?)
    (define (run)
      (core1-thread!)
      (schevana-boot! mode w h full?)
      (world)
      (schevana-run!)
      (schevana-end!))
    (if (or (eq? mode 'sdl) (and (pair? fork?) (car fork?)))
        (core0-run! mode w h full? run)
        (run)))

  (include-sources "src/core1/export.ss"))
