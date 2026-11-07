;;; kits/pixmap.ss — pixel buffers.
;;; A pixmap is a small image an app fills pixel by pixel (one pixel per
;;; Life cell, say) and draws scaled up in one call, instead of drawing
;;; thousands of rectangles. Its pixels are a Scheme bytevector of 4·w·h
;;; bytes, row after row, each pixel one native 32-bit word in the GPU's
;;; premultiplied ARGB (color->pixel makes one). Tight loops can write
;;; (pixmap-bytes pm) directly; a worker thread can fill a buffer from
;;; make-pixmap-bytevector and hand it over with pixmap-swap-bytes!.

(define-record-type (pixmap make-pixmap-record pixmap?)
  (nongenerative schevana-pixmap-2)
  (fields width height (mutable bytes)))

(define (pixmap-w pm) (pixmap-width pm))
(define (pixmap-h pm) (pixmap-height pm))

;; Transparent, or filled with color.
(define make-pixmap
  (case-lambda
    [(w h) (make-pixmap w h #f)]
    [(w h color)
     (unless (and (fixnum? w) (fixnum? h) (fx> w 0) (fx> h 0))
       (errorf 'make-pixmap "not a pixmap size: ~s × ~s" w h))
     (let ([pm (make-pixmap-record
                w h (make-immobile-bytevector (fx* 4 (fx* w h)) 0))])
       (when color (pixmap-fill! pm color))
       pm)]))

;; A zeroed buffer the size of pm's pixels, for a worker to fill.
(define (make-pixmap-bytevector pm)
  (make-immobile-bytevector (fx* 4 (fx* (pixmap-w pm) (pixmap-h pm))) 0))

;; Wraps bv (4·w·h bytes of pixels) without copying it.
(define (pixmap-from-bytevector bv w h)
  (unless (and (fixnum? w) (fixnum? h) (fx> w 0) (fx> h 0)
               (bytevector? bv) (= (bytevector-length bv) (* 4 w h)))
    (errorf 'pixmap-from-bytevector "need ~a bytes for ~s × ~s pixels"
            (* 4 w h) w h))
  (make-pixmap-record w h bv))

(define (pixmap-check-bytes who pm bv)
  (unless (and (bytevector? bv)
               (= (bytevector-length bv) (* 4 (pixmap-w pm) (pixmap-h pm))))
    (errorf who "need ~a bytes of pixels for a ~a × ~a pixmap"
            (* 4 (pixmap-w pm) (pixmap-h pm)) (pixmap-w pm) (pixmap-h pm))))

(define (pixmap-index who pm x y)
  (unless (and (fixnum? x) (fixnum? y)
               (fx< -1 x (pixmap-w pm)) (fx< -1 y (pixmap-h pm)))
    (errorf who "(~s, ~s) is outside a ~a × ~a pixmap"
            x y (pixmap-w pm) (pixmap-h pm)))
  (fx* 4 (fx+ x (fx* y (pixmap-w pm)))))

(define (pixmap-set! pm x y color)
  (pixmap-set-pixel! pm x y (color->pixel color)))

(define (pixmap-set-pixel! pm x y px)
  (bytevector-u32-native-set! (pixmap-bytes pm)
                              (pixmap-index 'pixmap-set-pixel! pm x y) px))

;; The raw pixel.
(define (pixmap-ref pm x y)
  (bytevector-u32-native-ref (pixmap-bytes pm)
                             (pixmap-index 'pixmap-ref pm x y)))

(define (pixmap-fill! pm color)
  (let* ([bv (pixmap-bytes pm)] [px (color->pixel color)]
         [row (fx* 4 (pixmap-w pm))] [n (bytevector-length bv)])
    (do ([i 0 (fx+ i 4)]) ((fx= i row)) (bytevector-u32-native-set! bv i px))
    (let loop ([done row])   ; then double what is filled
      (when (fx< done n)
        (let ([k (fxmin done (fx- n done))])
          (bytevector-copy! bv 0 bv done k)
          (loop (fx+ done k)))))))

;; bv holds raw pixels, exactly as many as pm has.
(define (pixmap-load! pm bv)
  (pixmap-check-bytes 'pixmap-load! pm bv)
  (bytevector-copy! bv 0 (pixmap-bytes pm) 0 (bytevector-length bv)))

;; Installs bv (from make-pixmap-bytevector, say) as pm's pixels without
;; copying; returns the old buffer.
(define (pixmap-swap-bytes! pm bv)
  (pixmap-check-bytes 'pixmap-swap-bytes! pm bv)
  (let ([old (pixmap-bytes pm)])
    (pixmap-bytes-set! pm bv)
    old))

;; Draws the pixmap scaled to w × h (default: its own size), each pixel a
;; sharp block (the core's draw-pixels).
(define pixmap-draw
  (case-lambda
    [(pm x y) (pixmap-draw pm x y (pixmap-w pm) (pixmap-h pm))]
    [(pm x y w h)
     (draw-pixels (pixmap-bytes pm) (pixmap-w pm) (pixmap-h pm) x y w h)]))
