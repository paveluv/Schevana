;;; (schevana kits pixmap) — pixel buffers. A pixmap is a small image an app
;;; fills pixel by pixel (one pixel per Life cell, say) and draws scaled up in
;;; one call, instead of drawing thousands of rectangles. Its pixels live on
;;; the GPU, each one a native 32-bit word in the GPU's premultiplied ARGB
;;; (color->pixel makes one). A pixel that is set goes up with the next
;;; frame. Rows painted together go up whole: (pixmap-rows! pm from to
;;; worklet arg ...) has the crew call (worklet y0 y1 bytes arg ...) on each
;;; share y0 .. y1 of those rows, where bytes holds the pixmap's pixels row
;;; after row. The worklet must write every pixel of its rows: what bytes
;;; held before is not the pixmap's last pixels.

(library (schevana kits pixmap)
  (export
    pixmap make-pixmap-record pixmap? pixmap-width pixmap-height pixmap-image
    pixmap-w pixmap-h make-pixmap pixmap-set! pixmap-set-pixel! pixmap-rows!
    pixmap-fill-rows! pixmap-fill! pixmap-draw)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) define-worklet draw-image gpu-image-id
                gpu-image-make rec-image-rows! rec-pixel-set! worklet
                worklet-spread)
          (only (schevana kits color) color->pixel))

  (library-layer kits)

  (define-record-type (pixmap make-pixmap-record pixmap?)
    (nongenerative schevana-pixmap-3)
    (fields width height image))

  (define (pixmap-w pm) (pixmap-width pm))
  (define (pixmap-h pm) (pixmap-height pm))

  ;; Makes a w × h pixmap, transparent or filled with color. Its GPU image is
  ;; released once the pixmap is gone.
  (define make-pixmap
    (case-lambda
      [(w h) (make-pixmap w h #f)]
      [(w h color)
       (unless (and (fixnum? w) (fixnum? h) (fx> w 0) (fx> h 0))
         (errorf 'make-pixmap "not a pixmap size: ~s × ~s" w h))
       (let ([pm (make-pixmap-record w h (gpu-image-make w h))])
         (pixmap-rows! pm 0 h pixmap-fill-rows!
                       (if color (color->pixel color) 0) w)
         pm)]))

  (define (pixmap-set! pm x y color)
    (pixmap-set-pixel! pm x y (color->pixel color)))

  (define (pixmap-set-pixel! pm x y px)
    (unless (and (fixnum? x) (fixnum? y)
                 (fx< -1 x (pixmap-w pm)) (fx< -1 y (pixmap-h pm)))
      (errorf 'pixmap-set-pixel! "(~s, ~s) is outside a ~a × ~a pixmap"
              x y (pixmap-w pm) (pixmap-h pm)))
    (rec-pixel-set! (gpu-image-id (pixmap-image pm)) x y px))

  ;; Has the crew paint rows from .. to: it calls (worklet y0 y1 bytes arg
  ;; ...) for each share of them, and the worklet writes every pixel of its
  ;; rows.
  (define (pixmap-rows! pm from to worklet . args)
    (let ([w (pixmap-w pm)])
      (rec-image-rows! (pixmap-image pm) from to
                       (lambda (bytes)
                         (apply worklet-spread (max 1 (quotient 8192 w)) from to
                                worklet bytes args)))))

  ;; Sets every pixel of rows y0 .. y1 of bytes, w pixels each, to px.
  (define-worklet (pixmap-fill-rows! y0 y1 bytes px w)
    (let ([end (fx* 4 (fx* y1 w))])
      (do ([i (fx* 4 (fx* y0 w)) (fx+ i 4)]) ((fx= i end))
        (bytevector-u32-native-set! bytes i px))))

  (define (pixmap-fill! pm color)
    (pixmap-rows! pm 0 (pixmap-h pm) pixmap-fill-rows! (color->pixel color)
                  (pixmap-w pm)))

  ;; Draws the pixmap scaled to w × h (by default, its own size), each pixel
  ;; a sharp block at its size or bigger (draw-image).
  (define pixmap-draw
    (case-lambda
      [(pm x y) (pixmap-draw pm x y (pixmap-w pm) (pixmap-h pm))]
      [(pm x y w h)
       (when (and (> w 0) (> h 0)) (draw-image (pixmap-image pm) x y w h))])))
