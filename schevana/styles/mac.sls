;;; (schevana styles mac) — the Mac window style: traffic lights on the left,
;;; which show their glyphs on hover, and a centered title.

(library (schevana styles mac)
  (export
    draw-resize-grip mac-radius mac-regions mac-glyph mac-draw-under mac-title
    mac-draw-over)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) alpha color-default! define-style draw-line
                fill-box fill-circle maximized? mix shaded? stroke-box
                text-width theme theme-rule title-height window-bg
                window-shadow window-title with-clip)
          (only (schevana kits fill) fill-gradient)
          (only (schevana kits text) text-draw-centered text-fit)
          (only (schevana kits ui) ui-glyph-size ui-title-icon ui-draw-glyph))

  (library-layer looks)

  (define (draw-resize-grip x y)
    (for-each (lambda (d)
                (draw-line (- x d) (- y 3) (- x 3) (- y d) (alpha 'text 0.18)
                           1))
              '(7 11)))

  (define (mac-radius win) (if (maximized? win) 0 (theme 'corner-radius)))

  (define (mac-regions win)
    (let ([cy (/ (title-height) 2)])
      (map (lambda (kind cx) (list kind (- cx 9) (- cy 9) 18 18))
           '(close minimize maximize) '(18 38 58))))

  ;; Draws a button's mark as strokes around its circle's center (text is
  ;; centered by its line box, not its ink, so a text mark sat low), in
  ;; opaque ink so that crossing strokes don't darken where they meet.
  (define (mac-glyph kind cx cy ink)
    (let ([a 3] [lw 1.5])
      (case kind
        [(close) (ui-draw-glyph (- cx a) (- cy a) (* 2 a) (* 2 a)
                                (list (cons 'ink ink) (cons 'width lw))
                                'close)]
        [(minimize) (draw-line (- cx a) cy (+ cx a) cy ink lw)]
        [(maximize) (draw-line (- cx a) cy (+ cx a) cy ink lw)
                    (draw-line cx (- cy a) cx (+ cy a) ink lw)])))

  ;; The top of a focused title's gradient.
  (at-load
   (color-default! 'mac-title-top
                   (theme-rule (mix 'title-bg-focus 'text 0.04))))

  (define (mac-draw-under win x y w h focused? hover pressed)
    (let ([th (title-height)] [r (mac-radius win)]
          [glyphs? (memq hover '(close minimize maximize))])
      (window-shadow win x y w h r focused?)
      (fill-box x y w h (window-bg win) r)
      (with-clip (x y w h r)
        (fill-gradient x y w th
                       (if focused? 'mac-title-top 'title-bg)
                       (if focused? 'title-bg-focus 'title-bg))
        (draw-line x (+ y th -0.5) (+ x w) (+ y th -0.5) (alpha #x000000 0.5))
        (for-each (lambda (cx color glyph)
                    (let ([cy (+ y (/ th 2))])
                      (fill-circle (+ x cx) cy 6
                        (if (or focused? glyphs?) color 'button-idle))
                      (when glyphs?
                        (mac-glyph glyph (+ x cx) cy
                                   (mix color #x000000 0.6)))))
                  '(18 38 58) '(button-close button-min button-max)
                  '(close minimize maximize))
        (mac-title win x y w th focused?))))

  ;; Draws the title, centered between the buttons and their mirror image,
  ;; after the window's icon if its app gave one; the icon and the title are
  ;; centered together.
  (define (mac-title win x y w th focused?)
    (let* ([icon (ui-title-icon win)] [s (ui-glyph-size)]
           [room (if icon (+ s 6) 0)]
           [title (text-fit (window-title win) (- w 160 room) 'title)]
           [tw (text-width title 'title)]
           [tx (+ x 70 (/ (- w 140 tw room) 2))])
      (when icon (icon tx (+ y (/ (- th s) 2)) s (if focused? '() '(dim))))
      (text-draw-centered (+ tx room) y tw th title
                          (if focused? 'title-text 'title-text-dim) 'title)))

  (define (mac-draw-over win x y w h focused? hover pressed)
    (stroke-box x y w h (if focused? 'window-border-focus 'window-border) 1
                (mac-radius win))
    ;; (the grip reaches 11 pixels in; a shaded window has no corner)
    (unless (or (maximized? win) (shaded? win) (< w 14) (< h 14))
      (draw-resize-grip (+ x w) (+ y h))))

  (at-load
   (define-style mac "Mac"
     ;; a list's column lines show faintly, as the Finder's do
     'table-dividers 'always
     ;; a divider's drag widens its column and moves the rest along
     'table-resize 'shift
     'frame-radius 'mac-radius
     'frame-regions 'mac-regions
     'frame-under 'mac-draw-under
     'frame-over 'mac-draw-over)))
