;;; (schevana core) — the core as a library: the files of src/core1/ in one
;;; body (they name each other in a ring), exporting what
;;; src/core1/export.ss lists, each name read-only but the hooks. A program
;;; imports it and calls schevana-main:
;;;
;;;   (import (chezscheme) (schevana core))
;;;   (schevana-main 'sdl 640 400 #f
;;;     (lambda () (open-window ...)))
;;;
;;; Where the top level's chain makes "/" and loads the world's files into
;;; it (src/core1/boot.ss), a library has no world of its own: what it is
;;; handed is a procedure, never the name of one.

(library (schevana core)
  (export schevana-main)
  (import (chezscheme) (schevana layer) (schevana base) (schevana core0)
          (schevana recorder))

  ;; Whether this is core1, the world's thread: the one schevana-main runs
  ;; the world on; till then, the one that imports the library.
  (define core1-thread-id (box (get-thread-id)))
  (define (core1-thread?) (fx= (get-thread-id) (unbox core1-thread-id)))

  ;; The top level's environments, "/core1" and "/": a library has
  ;; neither.
  (defvar *core1-env* #f)
  (defvar *world-env* #f)

  ;; A procedure by its name, which the top level looks up in "/": a
  ;; library is handed the procedure itself.
  (define (world-value name)
    (errorf 'world-value
            "~s: a library is handed the procedure, not its name" name))

  (define (core1-exported) (exports-names core1-exports 'world))

  ;; What the top level's main.ss says: where the tree is, the core's
  ;; sources (none to load again), what the command line asked.
  (define *schevana-root* (tree-root))
  (defvar *schevana-core1-sources* '())
  (defvar *schevana-options* '())

  (include-sources "src/core1/ffi.ss" "src/core1/platform.ss"
                   "src/core1/shader.ss" "src/core1/theme.ss"
                   "src/core1/gpu.ss" "src/core1/font.ss" "src/core1/gfx.ss"
                   "src/core1/proc.ss" "src/core1/screen.ss"
                   "src/core1/socket.ss" "src/core1/wm.ss"
                   "src/core1/system.ss")

  ;; Boots the screen, mode sdl (a window w × h logical pixels, or full
  ;; screen) or headless, runs world, a thunk that opens what the program
  ;; shows, then the world till it quits, and ends the process. With a
  ;; window, core0 keeps this thread, the process's first, for the screen,
  ;; and the world runs on its own; headless, one thread plays both,
  ;; unless fork? asks for the two with no window (a test's).
  (define (schevana-main mode w h full? world . fork?)
    (define (run)
      (set-box! core1-thread-id (get-thread-id))
      (schevana-boot! mode w h full?)
      (world)
      (schevana-run!)
      (schevana-end!))
    (if (or (eq? mode 'sdl) (and (pair? fork?) (car fork?)))
        (core0-run! mode w h full? run)
        (run)))

  ;; The theme's defaults and the color keys are plain defines that their
  ;; file assigns.
  (assigned-variables default-theme color-keys)

  (include-sources "src/core1/export.ss"))
