;;; wallpaper.ss — the desktop under the windows. A wallpaper fills it
;;; from the theme's two desktop colors. Each is a file in wallpapers/,
;;; and the theme key 'wallpaper names the one in use:
;;;
;;;   (define-wallpaper flat "Flat"
;;;     (lambda (x y w h top bottom) (fill-box x y w h top)))

;; ((name title fill) ...) in registration order
(defvar *wallpapers* '())

(define (register-wallpaper! name title fill)
  (set! *wallpapers* (registry-add *wallpapers* (list name title fill) car))
  (request-frame!))

;; (define-wallpaper name "Title" fill) adds a wallpaper, or replaces the
;; one of that name. (fill x y w h top bottom) fills the rectangle.
(define-syntax define-wallpaper
  (syntax-rules ()
    [(_ name title fill) (register-wallpaper! 'name title fill)]))

(define (wallpapers) (map car *wallpapers*))

;; An error in draw-wallpaper is reported, and the rest of the desktop goes
;; on.
(define (draw-desktop)
  (guard (c [#t (report-error! 'desktop c)])
    (draw-wallpaper *canvas-w* *canvas-h*)))

;; The name of the wallpaper drawn for name: the default for one that is
;; gone, #f when that is gone too.
(define (wallpaper-shown name)
  (let ([wp (or (assq name *wallpapers*)
                (assq (theme-default 'wallpaper) *wallpapers*))])
    (and wp (car wp))))

;; The desktop's background in a rectangle: the wallpaper named pattern (a
;; value of the theme key 'wallpaper) from the colors top and bottom, or a
;; plain fill when none is there.
(define (fill-wallpaper x y w h pattern top bottom)
  (let ([wp (assq (wallpaper-shown pattern) *wallpapers*)])
    (if wp
        ((caddr wp) x y w h top bottom)
        (fill-box x y w h top))))

(define-part (draw-wallpaper w h)
  (fill-wallpaper 0 0 w h (theme 'wallpaper) 'desktop-top 'desktop-bottom)
  (when (eq? (wallpaper-shown (theme 'wallpaper)) 'gradient)
    (fill-glow (* w 0.80) (* h 0.22) (* 0.55 (max w h)) (alpha 'accent-2 0.10))
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
(define (desktop-tick)
  (icon-follow-theme!))

(define-surface desktop -10
  'draw 'draw-desktop 'at (lambda (x y) 'desktop) 'mouse 'desktop-mouse
  'tick 'desktop-tick 'doc (lambda (what) '((L . "Unfocus") (R . "Apps"))))
