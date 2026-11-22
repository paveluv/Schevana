;;; (schevana wallpapers flat) — the top color alone.

(library (schevana wallpapers flat)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-wallpaper fill-box))

  (library-layer looks)

  (at-load
   (define-wallpaper flat "Flat"
     (lambda (x y w h top bottom) (fill-box x y w h top)))))
