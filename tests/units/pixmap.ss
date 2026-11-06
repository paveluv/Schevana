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

(check "pixmap set and ref round-trip"
       (let ([pm (make-pixmap 3 2)])
         (pixmap-set! pm 2 1 #x123456)
         (pixmap-set-pixel! pm 0 1 #x80402010)
         (and (= (pixmap-w pm) 3) (= (pixmap-h pm) 2)
              (= (pixmap-ref pm 2 1) #xff123456)
              (= (pixmap-ref pm 0 1) #x80402010)
              (= (pixmap-ref pm 0 0) 0)
              (= (bytevector-u32-native-ref (pixmap-bytes pm) (* 4 (+ 2 3)))
                 #xff123456)
              (raises? (lambda () (pixmap-ref pm 3 0)))
              (raises? (lambda () (pixmap-set! pm 0 -1 'red))))))

(check "pixmaps reject sizes that are not positive whole numbers"
       (and (raises? (lambda () (make-pixmap 0 4)))
            (raises? (lambda () (make-pixmap 2.5 4)))))

(check "make-pixmap and pixmap-fill! fill every pixel"
       (let ([pm (make-pixmap 7 5 #x00ff00)])
         (define (all? px)
           (for-all (lambda (i)
                      (= (bytevector-u32-native-ref (pixmap-bytes pm) (* 4 i))
                         px))
                    (iota 35)))
         (and (all? #xff00ff00)
              (begin (pixmap-fill! pm (alpha #xffffff 0.5))
                     (all? #x80808080)))))

(check "pixmap-load! copies raw pixels and rejects a wrong length"
       (let ([pm (make-pixmap 2 2)] [bv (make-bytevector 16 0)])
         (bytevector-u32-native-set! bv 12 #xff010203)
         (pixmap-load! pm bv)
         (bytevector-u32-native-set! bv 12 0)
         (and (= (pixmap-ref pm 1 1) #xff010203)
              (not (eq? (pixmap-bytes pm) bv))
              (raises? (lambda () (pixmap-load! pm (make-bytevector 12 0)))))))

(check "pixmap-from-bytevector wraps without copying"
       (let ([bv (make-bytevector 16 0)])
         (and (eq? (pixmap-bytes (pixmap-from-bytevector bv 2 2)) bv)
              (raises? (lambda () (pixmap-from-bytevector bv 3 2))))))

(check "pixmap-swap-bytes! installs a buffer and returns the old one"
       (let* ([pm (make-pixmap 2 2 #x0000ff)]
              [old (pixmap-bytes pm)]
              [new (make-pixmap-bytevector pm)])
         (bytevector-u32-native-set! new 0 #xffabcdef)
         (and (= (bytevector-length new) 16)
              (eq? (pixmap-swap-bytes! pm new) old)
              (eq? (pixmap-bytes pm) new)
              (= (pixmap-ref pm 0 0) #xffabcdef)
              (raises? (lambda ()
                         (pixmap-swap-bytes! pm (make-bytevector 8 0)))))))

;; Each device pixel of the drawn rect shows its pixmap pixel, and nothing
;; outside the rect changes.
(define (draws-nearest? s pm)
  (canvas-create! 1280 800 s)
  (let* ([before (image *canvas-pw* *canvas-ph* s
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
                                          (pixmap-ref
                                           pm
                                           (quotient (- x x0) (* s 10))
                                           (quotient (- y x0) (* s 10))))
                                       (= (pixel-at after x y)
                                          (pixel-at before x y)))
                                   (col (+ x 1)))))
                        (loop (+ y 1)))))])
    (cairo-surface-destroy before)
    (cairo-surface-destroy after)
    (canvas-create! 1280 800 *host-scale*)
    ok))

(define (quadrants bv)
  (let ([pm (pixmap-from-bytevector bv 2 2)])
    (for-each (lambda (i px) (pixmap-set-pixel! pm (mod i 2) (quotient i 2) px))
              '(0 1 2 3) '(#xffff0000 #xff00ff00 #xff0000ff #xff123456))
    pm))

(check "pixmap-draw is nearest-neighbor at 100%"
       (draws-nearest? 1 (quadrants (make-immobile-bytevector 16 0))))
(check "pixmap-draw is nearest-neighbor at 200%"
       (draws-nearest? 2 (quadrants (make-immobile-bytevector 16 0))))
(check "pixmap-draw works with an ordinary (movable) bytevector"
       (draws-nearest? 2 (quadrants (make-bytevector 16 0))))
