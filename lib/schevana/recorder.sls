;;; (schevana recorder) — the bytes of frames and their writers
;;; (src/recorder/), between core0 and the core: what
;;; src/recorder/export.ss lists.

(library (schevana recorder)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana core0))

  (include-sources "src/recorder/bytes.ss" "src/recorder/export.ss"))
