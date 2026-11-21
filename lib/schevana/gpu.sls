;;; (schevana gpu) — the GPU's world side: images, buffers, lists, computes
;;; (src/core1/gpu.ss). It exports what the pieces above it and the world use
;;; of it.

(library (schevana gpu)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana shader)
          (schevana core0) (schevana recorder) (schevana processes))

  (library-layer core)

  (include-sources "src/core1/gpu.ss")

  (define-exports gpu-exports
    (export (world)
      gpu-ask! *gpu-bytes-made* *gpu-held-gone* gpu-held-sweep! gpu-image-make
      gpu-image-make-target gpu-image-release! gpu-atlas-image gpu-list-new
      gpu-list-release! make-gpu-buffer gpu-buffer-set! gpu-buffer-release!
      gpu-buffer-read! *gpu-reads* gpu-buffer-read-then! gpu-reads-send!
      gpu-make-call gpu-compute! *gpu-computes* gpu-compute-soon!
      gpu-take-asks! gpu-asks-pending? gpu-computes-send! gpu-frame-free!
      gpu-publish)))
