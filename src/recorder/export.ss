;;; recorder/export.ss — what "/recorder" gives core1, read-only
;;; (src/base.ss's define-exports): the world has of it only what core1
;;; gives it again (src/core1/export.ss).

(define-exports recorder-exports
  (export (core1)
    rec-write! rec-extra! rec-extra-u32! rec-extra-ref rec-extra-at
    rec-count rec-bytes-begin! rec-into-list! rec-freeze! rec-lend!
    rec-last-sizes rec-last-copy! rec-last-runs rec-drawing->bytes
    rec-bytes-copies
    rec-list-new rec-list-copy gpu-list-recs-n gpu-list-extras-n
    gpu-list-runs gpu-list-version gpu-list-recs gpu-list-extras
    rec-earlier-add! rec-recordings rec-buffer-set! rec-pixel-set!
    rec-image-rows! rec-writes-pending? rec-compute-now!
    rec-submit-computes! rec-buffer-read!))
