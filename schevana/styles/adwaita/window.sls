;;; (schevana styles adwaita window) — a part of the Adwaita style
;;; ((schevana styles adwaita)): a libadwaita window, its title bar a
;;; header bar with the title in bold and the window's buttons.

(library (schevana styles adwaita window)
  (export
    adwaita-draw-over adwaita-draw-under adwaita-header-height adwaita-insets
    adwaita-radius adwaita-regions)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) alpha fill-box fill-circle linear-gradient
                maximized? stroke-box text-width theme window-bg window-shadow
                window-title window-w with-clip draw-line)
          (only (schevana kits text) text-fit)
          (only (schevana kits ui) ui-control-height ui-frame-glyph
                ui-glyph-size ui-title-icon)
          (only (schevana styles adwaita text) adwaita-center adwaita-text-in))

  (library-layer looks)

  ;;; ------------------------------------------------------------------
  ;;; the window: a libadwaita window, with a header bar for its title bar

  ;; A header bar is 46 high in a window: its buttons' 34, and 6 above and
  ;; below them (widgets/_header-bar.scss:2, 14-15, 83-89); a larger text
  ;; makes its buttons taller, and so the bar too.
  (define (adwaita-header-height) (+ 12 (ui-control-height)))

  (define (adwaita-insets win) (values 0 (adwaita-header-height) 0 0))

  ;; 15 round (_common.scss:16-17), and square while maximized (widgets/
  ;; _window.scss:52-55).
  (define (adwaita-radius win) (if (maximized? win) 0 (theme 'corner-radius)))

  ;; As GNOME lays out the window's buttons by default ("appmenu:close"),
  ;; close alone; with adwaita-window-buttons all, minimize and maximize
  ;; come before it, as GNOME Tweaks shows them.
  (define (adwaita-button-kinds)
    (if (eq? (theme 'adwaita-window-buttons) 'all)
        '(minimize maximize close)
        '(close)))

  ;; Each button is a control's square, 3 apart, 6 from the bar's end
  ;; (widgets/_header-bar.scss:9-15, 164-170).
  (define (adwaita-regions win)
    (let* ([b (ui-control-height)] [kinds (adwaita-button-kinds)]
           [n (length kinds)]
           [x0 (- (window-w win) 6 (* n b) (* 3 (- n 1)))]
           [y (quotient (- (adwaita-header-height) b) 2)])
      (map (lambda (k i) (list k (+ x0 (* i (+ b 3))) y b b)) kinds (iota n))))

  ;; The window and its header bar: flat, in the window's own color, or
  ;; raised, in the header bar's color (white in the light style) while the
  ;; window has the focus.
  (define (adwaita-draw-under win x y w h focused? hover pressed)
    (let ([hh (adwaita-header-height)] [r (adwaita-radius win)])
      (window-shadow win x y w h r focused?)
      (fill-box x y w h (window-bg win) r)
      (with-clip (x y w h r)
        (when (eq? (theme 'adwaita-header) 'raised)
          (fill-box x y w hh (if focused? 'adwaita-headerbar 'title-bg)))
        (adwaita-title win x y w hh focused?)
        (for-each (lambda (reg)
                    (adwaita-window-button win x y reg focused? hover pressed))
                  (adwaita-regions win)))))

  ;; The title, bold, in the bar's middle, clear of the buttons on either
  ;; side as GTK centers it (widgets/_header-bar.scss:199-205), after the
  ;; window's icon if its app gave one; an unfocused window's title is at
  ;; half strength (35-45).
  (define (adwaita-title win x y w hh focused?)
    (let* ([icon (ui-title-icon win)] [s (ui-glyph-size)]
           [side (+ 6 12 (* (length (adwaita-button-kinds))
                            (+ (ui-control-height) 3)))]
           [iw (if icon (+ s 6) 0)]
           [t (text-fit (window-title win) (max 0 (- w side side iw)) 'title)]
           [tw (text-width t 'title)]
           [tx (adwaita-center x w (+ tw iw))])
      (when icon
        (icon tx (adwaita-center y hh s) s (if focused? '() '(dim))))
      (adwaita-text-in (+ tx iw) y hh t
                       (if focused? 'title-text 'title-text-dim) 'title)))

  ;; A window button: a 24-pixel circle of the text at 10 %, 15 % under
  ;; the pointer and 30 % pressed, with its glyph in it (widgets/
  ;; _header-bar.scss:167-188); an unfocused window's is at half strength.
  (define (adwaita-window-button win x y reg focused? hover pressed)
    (let* ([kind (car reg)] [cx (+ x (cadr reg) (/ (cadddr reg) 2))]
           [cy (+ y (caddr reg) (/ (list-ref reg 4) 2))]
           [a (cond [(eq? pressed kind) 0.3] [(eq? hover kind) 0.15]
                    [else 0.1])])
      (fill-circle cx cy 12 (alpha 'text (if focused? a (/ a 2))))
      (adwaita-window-glyph (ui-frame-glyph win kind) cx cy
                            (if focused? 'text (alpha 'text 0.5)))))

  ;; The window's glyphs, after the Adwaita icons' shapes, in lines 2 wide:
  ;; close is an X 8 across, maximize a square, restore two squares, and
  ;; minimize a bar low down.
  (define (adwaita-window-glyph kind cx cy ink)
    (case kind
      [(close)
       (draw-line (- cx 3) (- cy 3) (+ cx 3) (+ cy 3) ink 2.2)
       (draw-line (+ cx 3) (- cy 3) (- cx 3) (+ cy 3) ink 2.2)]
      [(maximize) (stroke-box (- cx 4) (- cy 4) 8 8 ink 2 1)]
      [(restore)
       (stroke-box (- cx 4) (- cy 2) 6 6 ink 2 1)
       (fill-box (- cx 2) (- cy 4) 6 2 ink)
       (fill-box (+ cx 2) (- cy 4) 2 6 ink)]
      [(minimize) (fill-box (- cx 4) (+ cy 2) 8 2 ink 1)]))

  ;; Over the content: a raised bar's shade under it, a line and a short
  ;; shadow of the shade at half (widgets/_toolbars.scss:297-299); and the
  ;; window's inner edge, white at 7 % (widgets/_window.scss:11-12).
  (define (adwaita-draw-over win x y w h focused? hover pressed)
    (let ([r (adwaita-radius win)] [hh (adwaita-header-height)])
      (when (eq? (theme 'adwaita-header) 'raised)
        (with-clip (x y w h r)
          (fill-box x (+ y hh) w 1 (alpha 'adwaita-headerbar-shade 0.5))
          (fill-box x (+ y hh 1) w 4
                    (linear-gradient 0 (+ y hh 1) 0 (+ y hh 5)
                                     (alpha 'adwaita-headerbar-shade 0.5)
                                     (alpha 'adwaita-headerbar-shade 0)))))
      (unless (maximized? win)
        (stroke-box x y w h (alpha #xffffff 0.07) 1 r)))))
