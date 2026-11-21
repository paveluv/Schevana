;;; (schevana core0 window) — core0's window, its events and its steps;
;;; core0-run! runs it with the world on a thread of its own
;;; (src/core0/window.ss). It exports what the pieces above it and the layers
;;; above core0 use of it.

(library (schevana core0 window)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana ffi)
          (schevana sdl) (schevana core0 mail) (schevana core0 trace)
          (schevana core0 renderer) (schevana core0 present)
          (schevana core0 platform) (schevana core0 gpu)
          (schevana core0 trace-file))

  (include-sources "src/core0/window.ss")

  ;; Core0's loop finds a job's procedure by its name in core0's
  ;; environment (core0-run-job!). A library is no environment: this one
  ;; is made for the jobs, and has nothing else of core0's.
  (define core0-environment
    (let ([e (copy-environment (scheme-environment) #t)])
      (for-each (lambda (job) (define-top-level-value (car job) (cdr job) e))
                `((core0-resize-now! . ,core0-resize-now!)
                  (core0-minimum-now! . ,core0-minimum-now!)
                  (core0-fullscreen-now! . ,core0-fullscreen-now!)
                  (core0-icon-now! . ,core0-icon-now!)
                  (core0-cursor-now! . ,core0-cursor-now!)
                  (core0-clipboard-now! . ,core0-clipboard-now!)
                  (core0-quit-now! . ,core0-quit-now!)
                  (core0-trace-write! . ,core0-trace-write!)
                  (present-refresh-say! . ,present-refresh-say!)
                  (gpu-submit-computes! . ,gpu-submit-computes!)
                  (gpu-reads-now! . ,gpu-reads-now!)))
      (lambda () e)))

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

  (define-exports window-exports
    (export (world)
      *core0-mode* core0-app-id core0-window-headless! core0-window-open!
      core0-window-show! core0-window-close! core0-window-sizes
      core0-window-resize! core0-window-minimum! core0-window-scale
      core0-window-fullscreen? core0-window-fullscreen! core0-window-icon!
      core0-flags core0-flag-names core0-error-text core0-event-name
      core0-hidden? core0-input-ns-take! core0-set-cursor! clipboard-get
      clipboard-set! core0-post-submit! core0-post-reads! core0-quit!
      core0-step! core0-window-events core0-step-state core0-environment
      core0-recorder-environment core0-eval! core0-run!)))
