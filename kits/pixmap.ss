;;; kits/pixmap.ss — pixel buffers.
;;; A pixmap is a small image an app fills pixel by pixel (one pixel per
;;; Life cell, say) and draws scaled up in one call, instead of drawing
;;; thousands of rectangles. Its pixels are on the GPU, each one native
;;; 32-bit word in the GPU's premultiplied ARGB (color->pixel makes one).
;;; A pixel set goes up with the next frame; rows painted at once go up
;;; whole: (pixmap-rows! pm from to worklet arg ...) has the crew call
;;; (worklet y0 y1 bytes arg ...) on rows y0 .. y1 of them, bytes the
;;; pixmap's pixels row after row, of which it writes every one in its
;;; rows. What bytes held before is not the pixmap's last pixels.

(define-record-type (pixmap make-pixmap-record pixmap?)
  (nongenerative schevana-pixmap-3)
  (fields width height image))

(define (pixmap-w pm) (pixmap-width pm))
(define (pixmap-h pm) (pixmap-height pm))

;; Transparent, or filled with color. Its image goes once the pixmap does.
(define make-pixmap
  (case-lambda
    [(w h) (make-pixmap w h #f)]
    [(w h color)
     (unless (and (fixnum? w) (fixnum? h) (fx> w 0) (fx> h 0))
       (errorf 'make-pixmap "not a pixmap size: ~s × ~s" w h))
     (let ([pm (make-pixmap-record w h (gpu-image-make w h))])
       (gpu-image-held! pm (pixmap-image pm))
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

;; Rows from .. to painted by the crew: (worklet y0 y1 bytes arg ...) for
;; each share of them, every pixel of its rows written.
(define (pixmap-rows! pm from to worklet . args)
  (let ([w (pixmap-w pm)])
    (rec-image-rows! (pixmap-image pm) from to
                     (lambda (bytes)
                       (apply worklet-spread (max 1 (quotient 8192 w)) from to
                              worklet bytes args)))))

;; Rows y0 .. y1 of bytes, w pixels each, all px.
(define-worklet (pixmap-fill-rows! y0 y1 bytes px w)
  (let ([end (fx* 4 (fx* y1 w))])
    (do ([i (fx* 4 (fx* y0 w)) (fx+ i 4)]) ((fx= i end))
      (bytevector-u32-native-set! bytes i px))))

(define (pixmap-fill! pm color)
  (pixmap-rows! pm 0 (pixmap-h pm) pixmap-fill-rows! (color->pixel color)
                (pixmap-w pm)))

;; Draws the pixmap scaled to w × h (default: its own size), each pixel a
;; sharp block.
(define pixmap-draw
  (case-lambda
    [(pm x y) (pixmap-draw pm x y (pixmap-w pm) (pixmap-h pm))]
    [(pm x y w h)
     (when (and (> w 0) (> h 0)) (draw-image (pixmap-image pm) x y w h))]))
