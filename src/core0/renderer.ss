;;; renderer.ss — the record everything that touches a device hangs off
;;; (src/core0/gpu.ss fills it), and the one in use: below what times its
;;; frames (src/core0/present.ss) and what asks which driver it is
;;; (src/core0/platform.ss).

(define-record-type renderer
  (nongenerative schevana-renderer-1)
  (fields kind device sampler atlas blank
          (mutable pipelines)      ; (format . vector of pipelines by mode)
          (mutable paints)         ; shader: ((format . pipeline) ...)
          (mutable records)        ; each (buffer . capacity)
          (mutable extras)
          (mutable glyphs)
          (mutable transfer)       ; (transfer buffer . capacity)
          (mutable sdl-window)     ; core0's window it draws to, or 0
          (mutable target)         ; an offscreen texture, or 0
          (mutable target-w)
          (mutable target-h)
          (mutable fence)))        ; the last frame's, or #f

(defvar *renderer* #f)

;; The driver's name.
(define (gpu-driver-name) (sdl-gpu-driver (renderer-device *renderer*)))
