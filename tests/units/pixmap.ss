;;; tests/units/pixmap.ss — pixmaps (kits/pixmap.ss).

(check "color->pixel"
       (and (= (color->pixel #x123456) #xff123456)
            (let ([p (color->pixel (alpha #xffffff 0.5))])
              (and (= (fxsrl p 24) #x80) (= (fxand (fxsrl p 16) 255) #x80)
                   (= (fxand (fxsrl p 8) 255) #x80) (= (fxand p 255) #x80)))
            (= (color->pixel (alpha #x000000 0)) 0)
            (let-values ([(r g b a) (color-rgba 'accent)])
              (= (color->pixel 'accent)
                 (fxior #xff000000 (fxsll (exact (round (* 255 r))) 16)
                        (fxsll (exact (round (* 255 g))) 8)
                        (exact (round (* 255 b))))))))

(check "a pixmap's pixels set are what the GPU holds; it starts transparent"
       (let ([pm (make-pixmap 3 2)])
         (pixmap-set! pm 2 1 #x123456)
         (pixmap-set-pixel! pm 0 1 #x80402010)
         (let ([p (pixmap-picture pm)])
           (and (= (pixmap-w pm) 3) (= (pixmap-h pm) 2)
                (= (pixel-at p 2 1) #xff123456)
                (= (pixel-at p 0 1) #x80402010)
                (= (pixel-at p 0 0) 0)
                (raises? (lambda () (pixmap-set-pixel! pm 3 0 0)))
                (raises? (lambda () (pixmap-set! pm 0 -1 'red)))))))

(check "pixmaps reject sizes that are not positive whole numbers"
       (and (raises? (lambda () (make-pixmap 0 4)))
            (raises? (lambda () (make-pixmap 2.5 4)))))

(check "make-pixmap and pixmap-fill! fill every pixel"
       (let ([pm (make-pixmap 7 5 #x00ff00)])
         (define (all? px)
           (let ([p (pixmap-picture pm)])
             (for-all (lambda (i) (= (pixel-at p (mod i 7) (quotient i 7)) px))
                      (iota 35))))
         (and (all? #xff00ff00)
              (begin (pixmap-fill! pm (alpha #xffffff 0.5))
                     (all? #x80808080)))))

;; Rows y0 .. y1 of a w-wide pixmap's bytes: each pixel its row's number.
(define-worklet (pixmap-test-rows! y0 y1 bytes w)
  (do ([y y0 (fx+ y 1)]) ((fx= y y1))
    (do ([x 0 (fx+ x 1)]) ((fx= x w))
      (bytevector-u32-native-set! bytes (fx* 4 (fx+ x (fx* y w)))
                                  (fxior #xff000000 y)))))

(check "pixmap-rows! paints the rows asked for, shared by the crew, and \
        leaves the others; a worklet only"
       (let ([pm (make-pixmap 300 90 #x0000ff)])
         (pixmap-rows! pm 10 80 pixmap-test-rows! 300)
         (let ([p (pixmap-picture pm)])
           (and (for-all (lambda (y)
                           (= (pixel-at p 299 y)
                              (if (<= 10 y 79) (fxior #xff000000 y)
                                  #xff0000ff)))
                         (iota 90))
                (raises? (lambda ()
                           (pixmap-rows! pm 0 1 (lambda (y0 y1 bytes) 0))))
                (raises? (lambda () (pixmap-rows! pm 80 91 pixmap-test-rows!
                                                  300)))))))

;; Each device pixel of the drawn rect shows its pixmap pixel, and nothing
;; outside the rect changes.
(define (draws-nearest? s pm)
  (canvas-create! 1280 800 s)
  (let* ([own (pixmap-picture pm)]
         [before (image *canvas-pw* *canvas-ph* s
                        (lambda ()
                          (fill-gradient 0 0 300 300 #x204060 #x806040)))]
         [after (image *canvas-pw* *canvas-ph* s
                       (lambda ()
                         (fill-gradient 0 0 300 300 #x204060 #x806040)
                         (pixmap-draw pm 100 100 20 20)))]
         [x0 (exact (* s 100))] [x1 (exact (* s 120))]
         [ok (let loop ([y 0])
               (or (= y (exact (* s 300)))
                   (and (let col ([x 0])
                          (or (= x (exact (* s 300)))
                              (and (if (and (<= x0 x) (< x x1)
                                            (<= x0 y) (< y x1))
                                       (= (pixel-at after x y)
                                          (pixel-at
                                           own
                                           (quotient (- x x0) (* s 10))
                                           (quotient (- y x0) (* s 10))))
                                       (= (pixel-at after x y)
                                          (pixel-at before x y)))
                                   (col (+ x 1)))))
                        (loop (+ y 1)))))])
    (picture-free! before)
    (picture-free! after)
    (canvas-create! 1280 800 *host-scale*)
    ok))

(define (quadrants)
  (let ([pm (make-pixmap 2 2)])
    (for-each (lambda (i px) (pixmap-set-pixel! pm (mod i 2) (quotient i 2) px))
              '(0 1 2 3) '(#xffff0000 #xff00ff00 #xff0000ff #xff123456))
    pm))

;; A frame's new glyphs go up a byte a pixel: one size of them or another
;; leaves an odd offset, which Metal would shift pixels after them by.
(check "a pixmap arrives whole, whatever new glyphs the frame sends before it"
       (for-all
        (lambda (i)
          (let ([pm (make-pixmap 4 4)])
            (pixmap-fill! pm #x123456)
            (let ([img (image 60 40 1
                              (lambda ()
                                (fill-box 0 0 60 40 #x000000)
                                (draw-text 0 0 "gQ" 'text
                                           (font "sans-serif" (+ 17 i)))
                                (pixmap-draw pm 50 30 4 4)))])
              (= (pixel-at img 51 31) #xff123456))))
        (iota 8)))

(check "pixmap-draw is nearest-neighbor at 100%" (draws-nearest? 1 (quadrants)))
(check "pixmap-draw is nearest-neighbor at 200%" (draws-nearest? 2 (quadrants)))
