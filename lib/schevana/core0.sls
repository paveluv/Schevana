;;; (schevana core0) — core0, below the core: what src/core0/export.ss
;;; lists, from the libraries core0 is made of (lib/schevana/core0/), and
;;; core0-run!, which starts the world's thread and runs core0's loop.

(library (schevana core0)
  (export core0-run!)
  (import (chezscheme) (schevana layer) (schevana base) (schevana ffi)
          (schevana shader) (schevana core0 mail) (schevana core0 trace)
          (schevana core0 renderer) (schevana core0 present)
          (schevana core0 platform) (schevana core0 gpu)
          (schevana core0 trace-file) (schevana core0 window))

  (include-sources "src/core0/export.ss"))
