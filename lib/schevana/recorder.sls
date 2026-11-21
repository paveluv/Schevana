;;; (schevana recorder) — the recorder (lib/schevana/recorder/), between
;;; core0 and the core: what src/recorder/export.ss lists, and nothing else
;;; of it, so that the core names no byte core0 reads.

(library (schevana recorder)
  (export)
  (import (chezscheme) (only (schevana base) library-layer) (schevana layer)
          (schevana recorder bytes))

  (library-layer recorder facade)

  (include-sources "src/recorder/export.ss"))
