;;; (schevana wallpapers gradient) — the top color fading into the bottom
;;; one; this is the default wallpaper. draw-wallpaper adds a glow over it.

(library (schevana wallpapers gradient)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-wallpaper)
          (only (schevana kits fill) fill-gradient))

  (library-layer looks)

  (at-load
   (define-wallpaper gradient "Gradient"
     (lambda (x y w h top bottom) (fill-gradient x y w h top bottom)))))
