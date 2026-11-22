;;; (schevana desktop wallpaper) — the desktop under the windows: the
;;; wallpaper the theme key 'wallpaper names, filled from the theme's two
;;; desktop colors. The wallpapers themselves are the core's registry, a
;;; layer of the look (define-wallpaper, (schevana core theme)); each is a
;;; file in wallpapers/.

(library (schevana desktop wallpaper)
  (export
    draw-desktop draw-wallpaper draw-wallpaper* desktop-mouse desktop-frame)
  (import (chezscheme)
          (only (schevana base) at-load define-hook library-layer)
          (only (schevana core) *canvas-h* *canvas-w* alpha define-part
                define-surface fill-wallpaper focus-window! report-error!
                theme wallpaper-shown)
          (only (schevana kits fill) fill-glow)
          (only (schevana kits text) text-draw-centered)
          (only (schevana desktop icon) icon-follow-theme!)
          (only (schevana desktop menu) open-launcher!))

  (library-layer desktop)

  ;; An error in draw-wallpaper is reported, and the rest of the desktop goes
  ;; on.
  (define (draw-desktop)
    (guard (c [#t (report-error! 'desktop c)])
      (draw-wallpaper *canvas-w* *canvas-h*)))

  (define-part (draw-wallpaper w h)
    (fill-wallpaper 0 0 w h (theme 'wallpaper) 'desktop-top 'desktop-bottom)
    (when (eq? (wallpaper-shown (theme 'wallpaper)) 'gradient)
      (fill-glow (* w 0.80) (* h 0.22) (* 0.55 (max w h))
                 (alpha 'accent-2 0.10))
      (fill-glow (* w 0.12) (* h 0.90) (* 0.50 (max w h)) (alpha 'accent 0.08)))
    (text-draw-centered 0 0 w (- h 60) "λ" (alpha 'watermark 0.05) 'huge)
    (text-draw-centered 0 (+ (/ h 2) 150) w 30 "S C H E V A N A"
                        (alpha 'watermark 0.10) 'ui-bold))

  (define (desktop-mouse kind what x y button clicks)
    (when (eq? kind 'down)
      (case button
        [(right) (open-launcher! x y (cons x y))]   ; apps open where clicked
        [(left) (focus-window! #f)])))

  ;; A new theme repaints the app icon too (icon-follow-theme!).
  (define (desktop-frame t)
    (icon-follow-theme!))

  (at-load
   (define-surface desktop -10
     'draw 'draw-desktop 'at (lambda (x y) 'desktop) 'mouse 'desktop-mouse
     'frame 'desktop-frame 'doc
     (lambda (what) '((L . "Unfocus") (R . "Apps"))))))
