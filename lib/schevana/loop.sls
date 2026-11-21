;;; (schevana loop) — the loop: steps, events, boot, the collector; schevana-
;;; main runs a program on it (src/core1/system.ss). It exports what the pieces
;;; above it and the world use of it.

(library (schevana loop)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana core0)
          (schevana boot) (schevana platform) (schevana processes)
          (schevana gpu) (schevana theme) (schevana pacer) (schevana windows)
          (schevana screen))

  (include-sources "src/core1/system.ss")

  (define-exports loop-exports
    (export (world)
      *input-step?* post-core1! schevana-step! schevana-run! quit!
      schevana-end! uptime-ms load-user-init! user-directory schevana-boot!
      collector-declining? source-path source-files *source-texts*
      keep-source-text! load-file! (settable *app-loader*) load-user-folders!
      reload!)))
