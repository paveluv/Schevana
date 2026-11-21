;;; (schevana core0 trace) — the trace's ring, which every step writes to
;;; (src/core0/trace.ss). It exports what the pieces above it and the layers
;;; above core0 use of it.

(library (schevana core0 trace)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana core0 mail))

  (include-sources "src/core0/trace.ss")

  (define-exports trace-exports
    (export (world)
      core0-trace-rows (settable *core0-trace-dir*) *core0-trace-rings*
      (settable *core0-trace-thread*) core0-trace!)))
