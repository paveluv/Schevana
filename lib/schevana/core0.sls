;;; (schevana core0) — core0, below the core, as a library: the files of
;;; src/core0/ in one body (they name each other in a ring), exporting what
;;; src/core0/export.ss lists. Where the top level's chain makes
;;; environments and loads the next link into them (src/core0/boot.ss), a
;;; library is imported, and core0-run! starts the world's thread.

(library (schevana core0)
  (export core0-run!)
  (import (chezscheme) (schevana layer) (schevana base))

  ;; Where the tree is, which the top level's main.ss says.
  (define *schevana-root* (tree-root))

  (include-sources "src/core0/ffi.ss" "src/core0/sdl.ss"
                   "src/core0/platform.ss" "src/core0/gpu.ss"
                   "src/core0/present.ss" "src/core0/trace.ss"
                   "src/core0/window.ss")

  ;; A job's procedure, by the name it was posted with (core0-run-job!):
  ;; the top level looks it up in core0's environment; a library has
  ;; none, and knows its jobs.
  (define (core0-job name)
    (case name
      [(core0-resize-now!) core0-resize-now!]
      [(core0-minimum-now!) core0-minimum-now!]
      [(core0-fullscreen-now!) core0-fullscreen-now!]
      [(core0-icon-now!) core0-icon-now!]
      [(core0-cursor-now!) core0-cursor-now!]
      [(core0-clipboard-now!) core0-clipboard-now!]
      [(core0-quit-now!) core0-quit-now!]
      [(core0-trace-write!) core0-trace-write!]
      [(present-refresh-say!) present-refresh-say!]
      [(gpu-submit-computes!) gpu-submit-computes!]
      [(gpu-reads-now!) gpu-reads-now!]
      [else (errorf 'core0-job "~s is no job of core0's" name)]))

  ;; What core0 exports, as an environment, for who asks to look: there
  ;; only while the program's libraries are visible (a whole program
  ;; hides them unless compiled to show them).
  (define core0-environment
    (let ([e #f])
      (lambda ()
        (unless e (set! e (environment '(chezscheme) '(schevana core0))))
        e)))

  (define core0-recorder-environment
    (let ([e #f])
      (lambda ()
        (unless e (set! e (environment '(chezscheme) '(schevana recorder))))
        e)))

  ;; A library is sealed: core0 takes no forms to evaluate.
  (define (core0-eval! forms width then)
    (errorf 'core0-eval! "core0 is a library, and evaluates no forms"))

  ;; Core0 on this thread, the process's first, and the world on its own
  ;; (src/core0/boot.ss's core0-fork!): with a window (mode sdl), core0
  ;; opens it, w × h logical pixels at the desktop's scale, or full screen,
  ;; and clears it; headless, its GPU draws to a target. Then it forks the
  ;; world's thread, which runs world, a thunk, and goes on with its own
  ;; loop till the world quits.
  (define (core0-run! mode w h full? world)
    (if (eq? mode 'headless)
        (core0-window-headless!)
        (begin
          (core0-window-open! w h full?)
          (unless full?
            (let-values ([(uw uh pw ph) (core0-window-sizes)])
              (let ([s (/ (if (> (core0-window-scale) 0)
                              (core0-window-scale)
                              1)
                          (/ pw (max uw 1)))])
                (core0-resize-now! (exact (round (* w s)))
                                   (exact (round (* h s)))))))
          (core0-window-show!)
          (set! *gpu-booting* #t)
          (gpu-boot-screen!)))
    (set! *core0-forked* #t)
    (fork-thread
     (lambda ()
       (platform-thread-interactive!)
       (guard (c [#t (display-condition c (console-error-port))
                     (newline (console-error-port))])
         (world))
       (core0-quit!)))
    (core0-loop!))

  (include-sources "src/core0/export.ss"))
