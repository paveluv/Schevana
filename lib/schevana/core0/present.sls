;;; (schevana core0 present) — when each frame reached the screen, by the GPU's
;;; word and the screen's (src/core0/present.ss). It exports what the pieces
;;; above it and the layers above core0 use of it.

(library (schevana core0 present)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana sdl)
          (schevana core0 mail) (schevana core0 trace)
          (schevana core0 renderer))

  (include-sources "src/core0/present.ss")

  (define-exports present-exports
    (export (world)
      present-rows present-words *present-ring* *present-taken* present-taken!
      present-acquiring! present-acquired! present-at core0-frame-report
      present-sent! present-reported! *present-refresh-said* core0-refresh-ns!
      present-refresh-say! present-fence! present-poll!)))
