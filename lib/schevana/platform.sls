;;; (schevana platform) — which platform this is, as the core asks it, and the
;;; core's clocks (src/core1/platform.ss). It exports what the pieces above it
;;; and the world use of it.

(library (schevana platform)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana ffi)
          (schevana core0))

  (include-sources "src/core1/platform.ss")

  (define-exports platform-exports
    (export (world)
      platform-fact platform-windowing platform-gpu-api platform-predicates
      platform-process-bytes platform-machine-load now-ns now-ms thread-cpu-ns
      platform-pacer-margin-fade)))
