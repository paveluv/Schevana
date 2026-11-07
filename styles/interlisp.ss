;;; styles/interlisp.ss — the Interlisp window style.
;;; Medley Interlisp (Xerox PARC, then Venue; Interlisp.org's sources, MIT
;;; licensed; .work/style/research/lispm.md part 1). A window's border is
;;; 4: 2 pixels of ink, then 2 of paper. Above them the title strip, the
;;; border's ink as tall again as the title font, holds the title in paper
;;; at x 4 from a pixel below the top, then, 2 pixels after it, the title
;;; shade to the right ring: ink, unless interlisp-title-shade says
;;; otherwise (WINDOW:1551-1646). No buttons: everything is in the
;;; right-button menu (here: right-click the title). Moving and shaping
;;; drag a 2-pixel outline of its dashed shade; menus choose on release
;;; and box the entry under the pointer; the bell flashes the window;
;;; scroll bars are 24 pixels at the left, shown on hover, or, with the
;;; scroll bar side Outside, beside the window as Medley's own. Ink is
;;; the theme's text color, paper the window's background, so any palette
;;; gets the inverse-video look.

(define interlisp-ink 2)   ; the border's ink, then as much paper
(define interlisp-bar 24)   ; Medley's scroll bar beside the window

;; The title strip: the border's ink and the title font's line.
(define (interlisp-strip)
  (exact (max 15 (- (title-height) 15)
              (+ interlisp-ink (round (font-line-height 'ui-small))))))

;; Left of the frame, the margin an outside scroll bar shows in.
(define (interlisp-margin)
  (if (eq? (theme 'scrollbar-side) 'outside) interlisp-bar 0))

(define (interlisp-insets win)
  (let ([k (* 2 interlisp-ink)])
    (values (+ (interlisp-margin) k) (+ (interlisp-strip) interlisp-ink)
            k k)))

;; The outside scroll bar's margin, from below the title strip down.
(define (interlisp-regions win)
  (let ([s (interlisp-strip)])
    (if (zero? (interlisp-margin))
        '()
        (list (list 'scrollbar 0 s interlisp-bar (- (window-h win) s))))))

(define (interlisp-draw-under win x y w h focused? hover pressed)
  (let* ([o (interlisp-margin)] [x (+ x o)] [w (- w o)] [k interlisp-ink]
         [s (interlisp-strip)])
    (fill-box x y w h 'text)
    (fill-box (+ x k) (+ y s) (- w k k) (- h s k) (window-bg win))
    (with-clip (x y w s)   ; even "…" may not fit a narrow window
      (let ([end (draw-text (+ x 4) (+ y 1)
                            (text-fit (window-title win) (- w 8) 'ui-small)
                            (window-bg win) 'ui-small)])
        (when (< (+ end 2) (- (+ x w) k))
          (fill-box (+ end 2) (+ y 1) (- (+ x w) k end 2) (- s k)
                    'interlisp-title-shade))))))

;; The outside scroll bar, while it shows.
(define (interlisp-draw-over win x y w h focused? hover pressed)
  (ui-frame-scrollbar win))

;; Medley's scroll bar: a window of border 2, 1 pixel of ink and 1 of
;; paper; the thumb a box of ink over the part in view, its inside, 1
;; pixel in at the sides and 2 at the ends, in a 12.5 % shade
;; (WINDOWSCROLL:368, :569-641).
(define (interlisp-scrollbar x y w h flags start size)
  (fill-box x y w h 'text)
  (fill-box (+ x 1) (+ y 1) (- w 2) (- h 2) 'window-bg)
  (apply (lambda (tx ty tw th)
           (fill-box (+ tx 2) ty (- tw 4) th 'text)
           (fill-box (+ tx 3) (+ ty 2) (- tw 6) (- th 4)
                     'interlisp-scroll-shade))
         (cdr (assq 'thumb (ui-scrollbar-areas x y w h start size)))))

;; Medley's ghost box for Move and Shape: 2 pixels of its dashed shade,
;; 8 x 8 blocks, inverting what is under it (HLDISPLAY:817-841, :1383).
(define interlisp-dashes
  (let ([run (lambda (a b) (string-append (make-string 8 a)
                                          (make-string 8 b)))])
    (apply stipple #xffffff #f (append (make-list 8 (run #\. #\#))
                                       (make-list 8 (run #\# #\.))))))

(define (interlisp-drag-outline x y w h)
  (invert-box x y w 2 interlisp-dashes)
  (invert-box x (+ y h -2) w 2 interlisp-dashes)
  (invert-box x (+ y 2) 2 (- h 4) interlisp-dashes)
  (invert-box (+ x w -2) (+ y 2) 2 (- h 4) interlisp-dashes))

;; Its colors, which you may change and save as any color: the title
;; shade, ink; the thumb's 12.5 % shade (SCROLLBARSHADE, WINDOWSCROLL:34).
(color-default! 'interlisp-title-shade 'text)
(color-default! 'interlisp-scroll-shade
                (stipple 'text 'window-bg "#..." "...." "..#." "...."))

;; Its palette over Medley's dashed gray.
(define-style interlisp "Interlisp"
  ;; square, and so is everything drawn in it (rrect-path!); every common
  ;; option but the radius
  'corner-radius 0
  'options (remq 'corner-radius (map car common-options))
  'palette 'interlisp
  'wallpaper 'shade
  'frame-insets 'interlisp-insets
  'frame-regions 'interlisp-regions
  'frame-under 'interlisp-draw-under
  'frame-over 'interlisp-draw-over
  'ui-draw-scrollbar 'interlisp-scrollbar
  'draw-drag-outline 'interlisp-drag-outline
  ;; the feel
  'drag-feedback 'outline
  'menu-choose 'release
  'menu-hover 'outline
  'bell 'window
  'title-double-click 'none
  'scrollbar-side 'left
  'scrollbar-show 'hover
  'scrollbar-width 24)
