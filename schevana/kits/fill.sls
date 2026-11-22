;;; (schevana kits fill) — fills shaded with the core's gradients: a box that
;;; goes from one color to another (the gradient wallpaper, the Mac style's
;;; title bars), and a glow that fades out from a point (on the wallpaper and
;;; the clock).

(library (schevana kits fill)
  (export
    fill-gradient fill-glow)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) alpha fill-box fill-circle linear-gradient
                radial-gradient))

  (library-layer kits)

  ;; Fills a box with a linear gradient from c1 to c2. dir is 'vertical (the
  ;; default) or 'horizontal; radius, if given, rounds the corners.
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

  ;; A radial glow: color at the center, fading to transparent at radius r.
  (define (fill-glow cx cy r color)
    (fill-circle cx cy r (radial-gradient cx cy r color (alpha color 0)))))
