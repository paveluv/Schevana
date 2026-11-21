;;; (schevana core0 gpu) — the GPU layer's device side (src/core0/gpu.ss). It
;;; exports what the pieces above it and the layers above core0 use of it.

(library (schevana core0 gpu)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana shader)
          (schevana sdl) (schevana core0 mail) (schevana core0 platform)
          (schevana core0 present) (schevana core0 renderer)
          (schevana core0 trace))

  (include-sources "src/core0/gpu.ss")

  (define-exports gpu-exports
    (export (world)
      gpu-atlas-side gpu-usage-sampler gpu-usage-target gpu-windowless-kind
      gpu-windowless-video gpu-open! gpu-idle! gpu-claim-window!
      gpu-take-answers! make-gpu-image gpu-image? gpu-image-id gpu-image-w
      gpu-image-h gpu-image-levels gpu-image-loans gpu-image-loans-set!
      gpu-image-gone?-set! make-gpu-buffer* gpu-buffer-id gpu-buffer-size
      gpu-buffer-gone?-set! make-gpu-call gpu-call? gpu-call-shader
      make-gpu-recording gpu-recording? gpu-recording-recs
      gpu-recording-recs-set! gpu-recording-recs-n gpu-recording-recs-n-set!
      gpu-recording-extras gpu-recording-extras-set! gpu-recording-extras-n
      gpu-recording-extras-n-set! gpu-recording-runs gpu-recording-runs-set!
      gpu-recording-version gpu-recording-version-set! gpu-recording-until
      gpu-recording-until-set! gpu-recording-next gpu-recording-next-set!
      make-gpu-list gpu-list-id gpu-list-recording gpu-list-recording-set!
      gpu-list-labels gpu-list-labels-set! gpu-list-recorded
      gpu-list-recorded-set! gpu-list-took gpu-list-took-set! gpu-show-run?
      gpu-run-gone? gpu-compute-now! gpu-submit-computes! gpu-reads-now!
      gpu-buffer-download! *gpu-facts* gpu-frame-root gpu-frame-root-set!
      gpu-frame-number gpu-frame-number-set! gpu-frame-table-set!
      gpu-frame-table-n-set! gpu-frame-pieces-set! gpu-frame-jobs-set!
      gpu-frame-writes-set! gpu-frame-computes-set! gpu-frame-mode-set!
      gpu-frame-in-flight-set! gpu-frame-earlier-set! gpu-frame-shown?
      gpu-frame-shown?-set! gpu-frame-make *gpu-frame-back* *gpu-published*
      *gpu-given-back* gpu-publish! gpu-frame-waiting? gpu-frames-back!
      gpu-present! (settable *gpu-booting*) core0-world-loaded!
      gpu-boot-screen! gpu-drawing->bytes)))
