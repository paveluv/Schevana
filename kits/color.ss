;;; kits/color.ss — color math: a color as an image's pixel; as hue,
;;; saturation and lightness, and back (Settings' color picker); as one
;;; #xRRGGBB fixnum; the text color that reads on it.

;; A color as one pixel: premultiplied, a native word of B, G, R and A bytes,
;; what an image holds. #xRRGGBB is opaque.
(define (color->pixel c)
  (if (fixnum? c)
      (fxior #xff000000 (fxand c #xffffff))
      (let-values ([(r g b a) (color-rgba c)])
        (let ([a (clamp a 0.0 1.0)])
          (define (byte v) (exact (round (* 255 v))))
          (fxior (fxsll (byte a) 24) (fxsll (byte (* r a)) 16)
                 (fxsll (byte (* g a)) 8) (byte (* b a)))))))

;; Hue in degrees, saturation and lightness in [0, 1].
(define (color->hsl c)
  (let-values ([(r g b a) (color-rgba c)])
    (let* ([hi (max r g b)] [lo (min r g b)] [l (/ (+ hi lo) 2)] [d (- hi lo)])
      (if (< d 1e-9)
          (values 0.0 0.0 l)
          (values (cond [(= hi r) (* 60 (mod (/ (- g b) d) 6))]
                        [(= hi g) (* 60 (+ (/ (- b r) d) 2))]
                        [else (* 60 (+ (/ (- r g) d) 4))])
                  (/ d (- 1 (abs (- (* 2 l) 1))))
                  l)))))

(define (color-from-hsl h s l)
  (let* ([c (* (- 1 (abs (- (* 2 l) 1))) s)]
         [hp (/ (mod h 360) 60)]
         [x (* c (- 1 (abs (- (mod hp 2) 1))))]
         [m (- l (/ c 2))])
    (define (byte v) (clamp (exact (round (* 255 (+ v m)))) 0 255))
    (let-values ([(r g b) (cond [(< hp 1) (values c x 0)]
                                [(< hp 2) (values x c 0)]
                                [(< hp 3) (values 0 c x)]
                                [(< hp 4) (values 0 x c)]
                                [(< hp 5) (values x 0 c)]
                                [else (values c 0 x)])])
      (rgb (byte r) (byte g) (byte b)))))

;; c as one #xRRGGBB fixnum, its alpha dropped.
(define (color->fixnum c)
  (let-values ([(r g b a) (color-rgba c)])
    (rgb (exact (round (* r 255)))
         (exact (round (* g 255)))
         (exact (round (* b 255))))))

;; Black or white, whichever reads better on color c.
(define (color-readable-on c)
  (let-values ([(r g b a) (color-rgba c)])
    (if (> (+ (* 0.299 r) (* 0.587 g) (* 0.114 b)) 0.45) #x111111 #xf4f4f4)))
