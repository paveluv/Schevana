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
          (schevana socket) (schevana reload) (schevana core0)
          (schevana recorder) (except (schevana boot) core1-exports)
          (schevana platform) (schevana theme-table) (schevana processes)
          (schevana gpu) (schevana fonts) (schevana draw) (schevana pacer)
          (schevana screen) (schevana loop) (schevana theme)
          (schevana windows))

  ;; A program on the whole core: the loop's main (loop-main), defined
  ;; here so that a program compiled as one carries this library, which
  ;; a REPL's environment is made of.
  (define (schevana-main mode w h full? world . fork?)
    (apply loop-main mode w h full? world fork?))

  (include-sources "src/core1/export.ss"))
