;;; wallpapers/shade.ss — Interlisp's desktop gray, Medley's
;;; WINDOWBACKGROUNDSHADE #x8822 (WINDOW:137): the top color with dashes
;;; of the bottom color two pixels tall, one in each 4 × 4 cell, moved two
;;; columns every two rows.

(define-wallpaper shade "Shade"
  (lambda (x y w h top bottom)
    (fill-box x y w h (stipple bottom top "#..." "#..." "..#." "..#."))))
