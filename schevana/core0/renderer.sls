;;; (schevana core0 renderer) — the record that everything touching a
;;; device hangs off ((schevana core0 gpu) fills it), and the one in use.
;;; It sits below what times the frames ((schevana core0 present)) and what
;;; asks which driver this is ((schevana core0 platform)).

(library (schevana core0 renderer)
  (export
    make-renderer renderer-kind renderer-device renderer-sampler renderer-atlas
    renderer-blank renderer-pipelines renderer-pipelines-set! renderer-paints
    renderer-records renderer-records-set! renderer-extras renderer-extras-set!
    renderer-glyphs renderer-glyphs-set! renderer-transfer
    renderer-transfer-set! renderer-sdl-window renderer-sdl-window-set!
    renderer-target renderer-target-set! renderer-target-w
    renderer-target-w-set! renderer-target-h renderer-target-h-set!
    renderer-fence renderer-fence-set! *renderer* gpu-driver-name)
  (import (chezscheme)
          (only (schevana base) define-state library-layer)
          (only (schevana sdl) sdl-gpu-driver))

  (library-layer core0)

  (define-record-type renderer
    (nongenerative schevana-renderer-1)
    (fields kind device sampler atlas blank
            (mutable pipelines)      ; (format . vector of pipelines by mode)
            (mutable paints)         ; shader: ((format . pipeline) ...)
            (mutable records)        ; each (buffer . capacity)
            (mutable extras)
            (mutable glyphs)
            (mutable transfer)       ; (transfer buffer . capacity)
            (mutable sdl-window)     ; the core0 window it draws to, or 0
            (mutable target)         ; an offscreen texture, or 0
            (mutable target-w)
            (mutable target-h)
            (mutable fence)))        ; the last frame's fence, or #f

  (define-state *renderer* #f)

  ;; The driver's name.
  (define (gpu-driver-name) (sdl-gpu-driver (renderer-device *renderer*))))
