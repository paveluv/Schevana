;;; (schevana styles interlisp) — the Interlisp window style, after Medley
;;; Interlisp (Xerox PARC, then Venue; Interlisp.org's sources, MIT licensed;
;;; .work/style/research/lispm.md part 1). A window's border is 4 pixels: 2
;;; pixels of ink, then 2 of paper. Above them, the title strip, of the
;;; border's ink and as tall again as the title font, holds the title in
;;; paper at x 4, a pixel below the top; 2 pixels after the title, the title
;;; shade runs to the right ring, in ink unless interlisp-title-shade says
;;; otherwise (WINDOW:1551-1646); a title too long is cut at the ring, with
;;; no ellipsis. There are no buttons: everything is in the window menu
;;; (right-click the title), Medley's own: Close, Bury, Redisplay, Shrink.
;;; Menus are Medley's: a column of centered words in a 1-pixel outline, a
;;; box around the entry under the pointer, inverted while a button is held,
;;; choosing on release, and the window's and the desktop's opening just
;;; right of the pointer with their bottom at it. Moving and shaping drag a
;;; 2-pixel outline in Medley's gray; the bell flashes the window; scroll
;;; bars are 24 pixels wide, beside the window, shown on hover. There are no
;;; bars on the screen, and the desktop is Medley's shade alone. A minimized
;;; window shrinks to its icon, a bar of ink with the title, near where the
;;; window was; the left button moves it, the middle one expands it. All of
;;; its text is in Medley's own fonts, bitmaps drawn a font pixel to a
;;; logical pixel ((schevana styles interlisp fonts)): Gacha 10 for code and
;;; the REPL, Helvetica 10 for titles, menus and the rest, and Helvetica 12
;;; bold for headings (FONTPROFILE:186-225). Ink is
;;; the theme's text color and paper the window's background, so any palette
;;; gets the inverse-video look.

(library (schevana styles interlisp)
  (export
    interlisp-insets interlisp-regions interlisp-draw-under interlisp-draw-over
    interlisp-scrollbar interlisp-drag-outline interlisp-desk-icon-size
    interlisp-desk-icon-place interlisp-draw-desk-icon interlisp-menu-areas
    interlisp-draw-menu interlisp-panel interlisp-window-menu
    interlisp-wallpaper)
  (import (chezscheme)
          (only (schevana base) at-load clamp define-made library-layer)
          (only (schevana core) close-window! color-default! common-options
                define-bitmap-font define-style desktop-rect draw-text fill-box
                fill-wallpaper focus-window! font font-line-height invalidate!
                invert-box
                minimize-window! notify screen-h screen-w stipple stroke-box
                text-width theme theme-rule title-height window-action!
                window-bg window-h window-ref window-title window-w window-x
                window-y with-clip)
          (only (schevana kits menu) menu-entries menu-entry-ready?
                menu-filter menu-filter? menu-label-text menu-tag menu-x
                menu-y)
          (only (schevana kits ui) ui-draw-highlight ui-frame-scrollbar
                ui-menu-open! ui-scrollbar-areas)
          (schevana styles interlisp fonts))

  (library-layer looks)

  (define interlisp-ink 2)   ; the border's ink, then as much paper
  (define interlisp-bar 24)   ; Medley's scroll bar, beside the window

  ;; The title strip's height: the border's ink and the title font's line.
  (define (interlisp-strip)
    (exact (max 15 (- (title-height) 15)
                (+ interlisp-ink (round (font-line-height 'ui-small))))))

  ;; The margin left of the frame, where an outside scroll bar shows.
  (define (interlisp-margin)
    (if (eq? (theme 'scrollbar-side) 'outside) interlisp-bar 0))

  (define (interlisp-insets win)
    (let ([k (* 2 interlisp-ink)])
      (values (+ (interlisp-margin) k) (+ (interlisp-strip) interlisp-ink)
              k k)))

  ;; The outside scroll bar's margin, from the title strip's bottom down.
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
      ;; a long title is cut at the ring (WINDOW:1624-1626)
      (with-clip (x y (- w k) s)
        (let ([end (draw-text (+ x 4) (+ y 1) (window-title win)
                              (window-bg win) 'ui-small)])
          (when (< (+ end 2) (- (+ x w) k))
            (fill-box (+ end 2) (+ y 1) (- (+ x w) k end 2) (- s k)
                      'interlisp-title-shade))))))

  ;; Draws the outside scroll bar, while it shows.
  (define (interlisp-draw-over win x y w h focused? hover pressed)
    (ui-frame-scrollbar win))

  ;; Medley's scroll bar: a window with a border of 2, 1 pixel of ink and 1
  ;; of paper. The thumb is a box of ink over the part in view, with its
  ;; inside, 1 pixel in at the sides and 2 at the ends, in a 12.5 % shade
  ;; (WINDOWSCROLL:368, :569-641).
  (define (interlisp-scrollbar x y w h flags start size)
    (fill-box x y w h 'text)
    (fill-box (+ x 1) (+ y 1) (- w 2) (- h 2) 'window-bg)
    (apply (lambda (tx ty tw th)
             (fill-box (+ tx 2) ty (- tw 4) th 'text)
             (fill-box (+ tx 3) (+ ty 2) (- tw 6) (- th 4)
                       'interlisp-scroll-shade))
           (cdr (assq 'thumb (ui-scrollbar-areas x y w h start size)))))

  ;; Medley's ghost box for Move and Shape: 2 pixels of GRAYSHADE, a 50 %
  ;; pattern, inverting what is under it (HLDISPLAY:817-841, :982, :1036).
  (define-made interlisp-gray
    (stipple #xffffff #f "#.#." "#.#." ".#.#" ".#.#"))

  (define (interlisp-drag-outline x y w h)
    (invert-box x y w 2 interlisp-gray)
    (invert-box x (+ y h -2) w 2 interlisp-gray)
    (invert-box x (+ y 2) 2 (- h 4) interlisp-gray)
    (invert-box (+ x w -2) (+ y 2) 2 (- h 4) interlisp-gray))

  ;; Medley's panels, its menus' and its prompts': paper in a 1-pixel ink
  ;; outline, with no shadow (MENU:861-863, :951-957).
  (define (interlisp-panel x y w h flags)
    (fill-box x y w h 'window-bg)
    (stroke-box x y w h 'text))

  ;; Medley's menu (MENU:806-1040): a column as wide as the widest label and
  ;; 4, a row as tall as the menu font's line, with no separators and no
  ;; keys, in a 1-pixel outline. The window's menu and the desktop's open
  ;; with their bottom at the pointer, just right of it (MENUOFFSET (-1,
  ;; 0), MENU:1145-1150, WINDOW:713-717); others open at their point. What
  ;; is typed to filter shows over the entries once there is some.
  (define (interlisp-menu-areas m)
    (let* ([es (menu-entries m)] [font (theme 'menu-font)]
           [ih (theme 'menu-item-height)]
           [typed (and (menu-filter? m) (menu-filter m))]
           [head (if (and typed (not (string=? typed ""))) ih 0)]
           [w (+ 2 (fold-left (lambda (acc e)
                                (if (pair? e)
                                    (max acc (+ 4 (text-width
                                                   (menu-label-text (car e))
                                                   font)))
                                    acc))
                              (if (> head 0) (+ 4 (text-width typed font)) 26)
                              es))]
           [h (+ 2 head (* ih (length (filter pair? es))))]
           [tag (menu-tag m)]
           [pointed? (or (eq? tag 'launcher)
                         (and (pair? tag) (eq? (car tag) 'window)))]
           [x (clamp (if pointed? (+ (menu-x m) 1) (menu-x m))
                     0 (max 0 (- (screen-w) w)))]
           [y (clamp (if pointed? (- (menu-y m) h) (menu-y m))
                     0 (max 0 (- (screen-h) h)))])
      (cons (list 'menu x y w h)
            (append (if (> head 0)
                        (list (list 'filter (+ x 1) (+ y 1) (- w 2) head))
                        '())
                    (let loop ([es es] [i 0] [ey (+ y 1 head)])
                      (cond [(null? es) '()]
                            [(pair? (car es))
                             (cons (list i (+ x 1) ey (- w 2) ih)
                                   (loop (cdr es) (+ i 1) (+ ey ih)))]
                            [else (loop (cdr es) (+ i 1) ey)]))))))

  ;; The entry under the pointer gets a box that is its cell, inverted
  ;; while a button is held on it (\BOXITEM, \INVERTITEM, MENU:1217-1302).
  (define (interlisp-draw-menu m areas on flags)
    (let ([es (list->vector (menu-entries m))] [font (theme 'menu-font)])
      (apply interlisp-panel (append (cdar areas) '((menu))))
      (for-each
       (lambda (a)
         (apply
          (lambda (what x y w h)
            (let ([ty (+ y (/ (- h (font-line-height font)) 2))])
              (cond
                [(eq? what 'filter)
                 (draw-text (+ x 2) ty (menu-filter m) 'text font)]
                [(fixnum? what)
                 (let* ([sel? (eqv? what on)] [e (vector-ref es what)]
                        [text (menu-label-text (car e))])
                   (when sel? (ui-draw-highlight x y w h flags))
                   (draw-text (+ x (/ (- w (text-width text font)) 2)) ty
                              text
                              (cond [(not (menu-entry-ready? e)) 'text-faint]
                                    [(and sel? (memq 'pressed flags))
                                     'window-bg]
                                    [else 'text])
                              font))])))
          a))
       (cdr areas))))

  ;; Medley's window menu (WINDOW:142-166), what of it Schevana can do:
  ;; Close, Bury (to the bottom: the window is on top as its menu opens),
  ;; Redisplay and Shrink; then Schevana's own, $w. An icon's menu is
  ;; Medley's icon menu (WINDOWICON:20-28): Close, which closes its window
  ;; too, Bury and Expand.
  (define (interlisp-window-menu win x y)
    (let ([main (window-ref win 'icon-for)])
      (ui-menu-open!
       x y
       (if main
           `(("Close" . ,(lambda () (close-window! win)))
             ("Bury" . ,(lambda () (window-action! win 'depth)))
             ("Expand" . ,(lambda () (focus-window! main))))
           `(("Close" . ,(lambda () (close-window! win)))
             ("Bury" . ,(lambda () (window-action! win 'depth)))
             ("Redisplay" . ,(lambda () (invalidate! win)))
             ("Shrink" . ,(lambda () (minimize-window! win)))
             ("Bind to $w" . ,(lambda ()
                                (define-top-level-value '$w win)
                                (notify (format "$w = ~s" win))))))
       'tag (cons 'window win))))

  ;; Medley's desktop is its shade alone.
  (define (interlisp-wallpaper w h)
    (fill-wallpaper 0 0 w h (theme 'wallpaper) 'desktop-top 'desktop-bottom))

  ;; Medley's icon of a shrunk window, the title-bar icon (MAKETITLEBARICON,
  ;; WINDOWICON:75-108): a window that is all title bar, as tall as the
  ;; title font's line (WINDOWICON:90-100), solid ink, too short for the
  ;; border's paper, and as wide as the title and 8 more, at least 26
  ;; (MinWindowWidth, WINDOW:125); the title in paper, 4 pixels in.
  (define (interlisp-desk-icon-size win)
    (values (max 26 (+ 8 (exact (ceiling (text-width (window-title win)
                                                      'ui-small)))))
            (exact (round (font-line-height 'ui-small)))))

  (define (interlisp-draw-desk-icon win w h flags)
    (fill-box 0 0 w h 'text)
    (draw-text 4 0 (window-title win) (window-bg win) 'ui-small))

  ;; Where Medley puts an icon (ICONPOSITION.FROM.WINDOW, WINDOWICON:51-73):
  ;; at the window's left edge when the window is nearer the screen's left,
  ;; else ending at its right edge; at its bottom when it is nearer the
  ;; screen's bottom, else at its top.
  (define (interlisp-desk-icon-place win w h)
    (let-values ([(dx dy dw dh) (desktop-rect)])
      (let ([l (window-x win)] [r (+ (window-x win) (window-w win))]
            [t (window-y win)] [b (+ (window-y win) (window-h win))])
        (values (if (< (- l dx) (- (+ dx dw) r))
                    (max dx l)
                    (- (min (+ dx dw) r) w))
                (if (< (- (+ dy dh) b) (- t dy))
                    (- (min (+ dy dh) b) h)
                    (max dy t))))))

  ;; The style's colors, which you may change and save like any color: the
  ;; title shade, ink by default, and the thumb's 12.5 % shade
  ;; (SCROLLBARSHADE, WINDOWSCROLL:34).
  (at-load
   (color-default! 'interlisp-title-shade 'text))
  (at-load
   (color-default! 'interlisp-scroll-shade
                   (stipple 'text 'window-bg "#..." "...." "..#." "....")))

  ;; Medley's fonts, registered as the style loads.
  (at-load
   (for-each (lambda (f) (define-bitmap-font (car f) (cdr f)))
             interlisp-fonts))

  ;; The style's own palette, over Medley's dashed gray (the shade
  ;; wallpaper).
  (at-load
   (define-style interlisp "Interlisp"
     ;; square, and so is everything drawn in it (rec-radius); it honors
     ;; every common option but the radius
     'corner-radius 0
     'shadow 0
     ;; Medley's fonts are its own, each at its one size
     'options (remp (lambda (o)
                      (memq o '(corner-radius shadow ui-font ui-font-size
                                mono-font mono-font-size)))
                    (map car common-options))
     'ui-font "Medley Helvetica 10"
     'ui-font-size 10
     'mono-font "Medley Gacha 10"
     'mono-font-size 10
     'ui (font "Medley Helvetica 10" 10 'crisp)
     'ui-small (font "Medley Helvetica 10" 10 'crisp)
     'ui-italic (font "Medley Helvetica 10" 10 'crisp)
     'ui-bold (font "Medley Helvetica 10 Bold" 10 'crisp)
     'ui-small-bold (font "Medley Helvetica 10 Bold" 10 'crisp)
     'title (font "Medley Helvetica 10 Bold" 10 'crisp)
     'heading (font "Medley Helvetica 12 Bold" 12 'crisp)
     'big (font "Medley Helvetica 10 Bold" 20 'crisp)
     'mono (font "Medley Gacha 10" 10 'crisp)
     'mono-small (font "Medley Gacha 10" 10 'crisp)
     'mono-bold (font "Medley Gacha 10" 10 'crisp)
     ;; the white and the black of a console's tube, as they looked
     'palette 'p4
     'wallpaper 'shade
     'frame-insets 'interlisp-insets
     'frame-regions 'interlisp-regions
     'frame-under 'interlisp-draw-under
     'frame-over 'interlisp-draw-over
     'ui-draw-scrollbar 'interlisp-scrollbar
     'draw-drag-outline 'interlisp-drag-outline
     'ui-draw-panel 'interlisp-panel
     'menu-areas 'interlisp-menu-areas
     'draw-menu 'interlisp-draw-menu
     'open-window-menu 'interlisp-window-menu
     'draw-wallpaper 'interlisp-wallpaper
     ;; no bars: windows, icons and the desktop's menu are all there is
     'topbar-height 0
     'taskbar-height 0
     ;; Medley's menu font is its title font (FONTPROFILE:54)
     'menu-font 'ui-small
     'menu-item-height (theme-rule (round (font-line-height 'ui-small)))
     'menu-ink 'text
     'menu-ink-selected 'text
     'menu-ink-pressed 'window-bg
     ;; the matching paren in HIGHLIGHTSHADE (WINDOW:139)
     'repl-paren-mark (stipple 'text #f "#..." "...." "..#." "....")
     ;; the feel
     'drag-feedback 'outline
     'menu-choose 'release
     'menu-hover 'outline
     'menu-icons #f   ; its menus are words alone
     'bell 'window
     'title-double-click 'none
     'scrollbar-side 'outside
     'scrollbar-show 'hover
     'scrollbar-width 24
     ;; a minimized window shrinks to its icon, which the middle button
     ;; expands (ICONBUTTONEVENTFN, WINDOWICON:39-49)
     'minimize-to 'icons
     'desk-icon-expand 'middle
     'desk-icon-size 'interlisp-desk-icon-size
     'desk-icon-place 'interlisp-desk-icon-place
     'draw-desk-icon 'interlisp-draw-desk-icon)))
