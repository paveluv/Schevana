;;; (schevana core0 platform) — what differs by platform, of core0's, and the
;;; screen's reports (src/core0/platform.ss). It exports what the pieces above
;;; it and the layers above core0 use of it.

(library (schevana core0 platform)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana ffi)
          (schevana sdl) (schevana core0 mail) (schevana core0 trace)
          (schevana core0 renderer) (schevana core0 present))

  (include-sources "src/core0/platform.ss")

  (define-exports platform-exports
    (export (world)
      platform-cpu-count *core0-platform* core0-platform-read!
      platform-report-ask! platform-reports-start! platform-reports-pump!
      platform-thread-interactive!)))
