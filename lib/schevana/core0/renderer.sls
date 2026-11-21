;;; (schevana core0 renderer) — the record a device hangs off, and the one in
;;; use (src/core0/renderer.ss). It exports what the pieces above it and the
;;; layers above core0 use of it.

(library (schevana core0 renderer)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana sdl))

  (include-sources "src/core0/renderer.ss")

  (define-exports renderer-exports
    (export (world)
      renderer make-renderer renderer-kind renderer-device renderer-sampler
      renderer-atlas renderer-blank renderer-pipelines renderer-pipelines-set!
      renderer-paints renderer-records renderer-records-set! renderer-extras
      renderer-extras-set! renderer-glyphs renderer-glyphs-set!
      renderer-transfer renderer-transfer-set! renderer-sdl-window
      renderer-sdl-window-set! renderer-target renderer-target-set!
      renderer-target-w renderer-target-w-set! renderer-target-h
      renderer-target-h-set! renderer-fence renderer-fence-set!
      (settable *renderer*) gpu-driver-name)))
