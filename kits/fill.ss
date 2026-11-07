;;; kits/fill.ss — fills shaded by the core's gradients: a box from one
;;; color to another (the wallpaper, the Mac's title bars), a glow fading
;;; out from a point (the wallpaper's, the clock's).

;; Linear gradient from c1 to c2; dir is 'vertical or 'horizontal.
(define fill-gradient
  (case-lambda
    [(x y w h c1 c2) (fill-gradient x y w h c1 c2 'vertical 0)]
    [(x y w h c1 c2 dir) (fill-gradient x y w h c1 c2 dir 0)]
    [(x y w h c1 c2 dir radius)
     (fill-box x y w h
               (if (eq? dir 'horizontal)
                   (linear-gradient x 0 (+ x w) 0 c1 c2)
                   (linear-gradient 0 y 0 (+ y h) c1 c2))
               radius)]))

;; A radial glow: color at the center fading to transparent at radius r.
(define (fill-glow cx cy r color)
  (fill-circle cx cy r (radial-gradient cx cy r color (alpha color 0))))
