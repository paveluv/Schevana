;;; (schevana screen) — the screen core0 shows, its events and its size
;;; (src/core1/screen.ss). It exports what the pieces above it and the world
;;; use of it.

(library (schevana screen)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana core0)
          (schevana theme-table) (schevana processes) (schevana draw)
          (schevana pacer) (schevana windows))

  (include-sources "src/core1/screen.ss")

  (define-exports screen-exports
    (export (world)
      (settable *screen-event-seen*) system-scale-percent screen-rescale!
      screen-init! screen-shutdown! fullscreen? set-fullscreen!
      toggle-fullscreen! screen-set-icon! screen-events)))
