;;; (schevana recorder) — the recorder (lib/schevana/recorder/), between
;;; core0 and the core, as the core has it: how the core writes what it
;;; records and hands it over, and nothing else of it, so that the core
;;; names no byte core0 reads.

(library (schevana recorder)
  (export
    rec-write! rec-extra! rec-extra-u32! rec-extra-ref rec-extra-at
    rec-count rec-bytes-begin! rec-into-list! rec-freeze! rec-lend!
    rec-last-sizes rec-last-copy! rec-last-runs rec-drawing->bytes
    rec-bytes-copies
    rec-list-new rec-list-copy gpu-list-recs-n gpu-list-extras-n
    gpu-list-runs gpu-list-version gpu-list-recs gpu-list-extras
    rec-earlier-add! rec-recordings rec-buffer-set! rec-pixel-set!
    rec-image-rows! rec-writes-pending? rec-compute-now!
    rec-submit-computes! rec-buffer-read! rec-buffer-read-then!)
  (import (chezscheme)
          (schevana base)
          (schevana recorder bytes))

  (library-layer recorder facade))
