;;; (schevana core0 trace-file) — the trace, written to its file
;;; (src/core0/trace-file.ss). It exports what the pieces above it and the
;;; layers above core0 use of it.

(library (schevana core0 trace-file)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana core0 mail)
          (schevana core0 platform) (schevana core0 present)
          (schevana core0 trace) (schevana boot))

  (include-sources "src/core0/trace-file.ss")

  (define-exports trace-file-exports
    (export (world)
      core0-trace-start! core0-trace-watch! core0-trace-dump!
      core0-trace-write!)))
