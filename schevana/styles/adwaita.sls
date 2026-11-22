;;; (schevana styles adwaita) — GNOME's look: libadwaita 1.7.6's widgets and
;;; windows, and GNOME Shell 48.7's top bar, menus and notifications, as GNOME
;;; 48 draws them with the blue accent, in its light style (the palette
;;; adwaita) or its dark one (adwaita-dark, which a desktop that prefers dark
;;; gets). Facts only, from libadwaita's stylesheet (LGPL-2.1+) and GNOME
;;; Shell's (GPL-2.0+): sizes, radii, colors and alphas, each cited as
;;; file:line at those tags, libadwaita's under src/stylesheet/ (adw-…c files
;;; under src/), the Shell's under data/theme/gnome-shell-sass/ and marked
;;; shell. No SCSS, icon or image is copied: the glyphs are drawn here from
;;; their geometry.
;;;
;;; Controls are flat tints of the text color, 10 % at rest, 15 % under the
;;; pointer, 30 % pressed, with no border or bevel; they are 34 high and 9
;;; round, cards and boxed lists 12, popovers, dialogs and windows 15. A
;;; window is a libadwaita window, its title bar a header bar 46 high, its
;;; title bold in the middle, and as GNOME lays its buttons out
;;; ("appmenu:close") only a close button, a 24-pixel circle: a double click
;;; on the title maximizes the window, its menu (a right click on the title)
;;; minimizes it, and adwaita-window-buttons all shows minimize and maximize
;;; too, as GNOME Tweaks does. The desktop is GNOME Shell's, which stays dark
;;; unless the person prefers light: a black top bar, the Activities dots at
;;; its left and the clock in its middle; the desktop's menus are the
;;; Shell's popup menus, a window's dropdowns libadwaita's popovers;
;;; notifications are the Shell's banners at the top; and as GNOME has no
;;; taskbar, the windows are a dash at the bottom, the one the overview
;;; shows.

(library (schevana styles adwaita)
  (export
    adwaita-em adwaita-luma adwaita-dark? adwaita-by-style adwaita-standalone
    adwaita-header-height adwaita-insets adwaita-radius adwaita-button-kinds
    adwaita-regions adwaita-draw-under adwaita-title adwaita-window-button
    adwaita-window-glyph adwaita-draw-over adwaita-ring adwaita-ring-outside
    adwaita-focus adwaita-box adwaita-button-content adwaita-button
    adwaita-toggle-piece adwaita-button-size adwaita-check-box
    adwaita-check-label adwaita-checkbox adwaita-checkbox-size
    adwaita-radio-text-x adwaita-radio-size adwaita-radio adwaita-toggle
    adwaita-toggle-size adwaita-toggle-track adwaita-slider adwaita-progress
    adwaita-tab adwaita-tabs-size adwaita-label adwaita-surface adwaita-field
    adwaita-text-box-areas adwaita-dropdown adwaita-dropdown-size
    adwaita-stepper-areas adwaita-chip adwaita-chip-size adwaita-card
    adwaita-card-radius adwaita-scrollbar-areas adwaita-scrollbar
    adwaita-table-header adwaita-table-row adwaita-table-divider
    adwaita-table-cell-inset adwaita-panel adwaita-highlight adwaita-separator
    adwaita-tooltip-lines adwaita-tooltip-size adwaita-tooltip
    adwaita-dialog-button-widths adwaita-dialog-size adwaita-dialog-areas
    adwaita-dialog adwaita-scrim adwaita-calendar adwaita-day
    adwaita-avatar-colors adwaita-avatar-index adwaita-avatar adwaita-busy
    adwaita-nav-row adwaita-live-badge adwaita-suggestion adwaita-split
    adwaita-rows-spacing adwaita-row-height adwaita-row-areas
    adwaita-rows-radius adwaita-rows adwaita-row adwaita-status-title-font
    adwaita-status-page-areas adwaita-status-page adwaita-banner-height
    adwaita-banner adwaita-activities-width adwaita-topbar-areas
    adwaita-clock-text adwaita-status-strings adwaita-draw-topbar
    adwaita-dash-sizes adwaita-taskbar-areas adwaita-dash-icon
    adwaita-draw-taskbar adwaita-toast-boxes adwaita-draw-toasts
    adwaita-shell-menu? adwaita-menu-choice adwaita-menu-label-width
    adwaita-menu-areas adwaita-shell-panel
    adwaita-menu-filter adwaita-draw-menu adwaita-draw-wallpaper)
  (import (chezscheme)
          (only (schevana base) at-load clamp filter-map library-layer
                string-suffix?)
          (only (schevana core) *focus* *hover* *toasts* *windows* alpha
                color-default! color-rgba define-style desktop-rect
                draw-polyline draw-shadow draw-text fill-box fill-circle
                font-line-height linear-gradient maximized? mix pi rgb
                screen-h screen-w stroke-box stroke-circle text-width theme
                theme-default! theme-font-rule theme-rule visible? window-app
                window-bg window-id window-shadow window-title window-w
                window? with-clip with-place draw-line)
          (only (schevana desktop menu) *menu* *menu-blink* launcher-open?
                menu-areas menu-entries menu-entry-flags menu-filter
                menu-filter? menu-label-key menu-label-text menu-phase
                menu-sel menu-tag menu-x menu-y)
          (only (schevana desktop mousedoc) mouse-doc mouse-doc-text)
          (only (schevana desktop status) *status-shown*)
          (only (schevana desktop taskbar) taskbar-areas taskbar-height)
          (only (schevana desktop toasts) toast-boxes)
          (only (schevana desktop topbar) topbar-areas topbar-height)
          (only (schevana desktop wallpaper) fill-wallpaper)
          (only (schevana kits app) app-color)
          (only (schevana kits text) text-draw-centered text-fit text-widest)
          (only (schevana kits ui) ui-button-radius ui-calendar-areas
                ui-chip-areas ui-control-height ui-dialog-areas ui-dialog-lines
                ui-draw-glyph ui-draw-panel ui-frame-glyph ui-glyph-size
                ui-initials ui-joined-span ui-label-font ui-label-lines
                ui-label-size ui-label-text ui-live-badge-back
                ui-live-badge-mark ui-small-glyph-size ui-status-page-areas
                ui-text-box-top ui-title-icon ui-wrap-lines ui-banner-areas
                ui-scrollbar-width ui-card-radius))

  (library-layer looks)

  ;;; ------------------------------------------------------------------
  ;;; colors

  ;; GNOME gives its sizes in a text of 11 pt, 14⅔ pixels; ours is 15, a
  ;; whole pixel Settings can show: an em of GNOME's is our text size less
  ;; a 45th.
  (define (adwaita-em) (* (theme 'ui-font-size) 44/45))

  (define (adwaita-luma c)
    (let-values ([(r g b a) (color-rgba c)])
      (+ (* 0.2126 r) (* 0.7152 g) (* 0.0722 b))))

  ;; The dark style is a palette whose window is dark.
  (at-load
   (theme-default! 'adwaita-dark (theme-rule (< (adwaita-luma 'bg-1) 0.5))))

  (define (adwaita-dark?) (theme 'adwaita-dark))

  ;; One value in the light style, another in the dark.
  (define (adwaita-by-style light dark) (if (adwaita-dark?) dark light))

  ;; c as text or a mark on a plain surface, a "standalone" color: its OKLab
  ;; lightness at most 0.5 in the light style, at least 0.85 in the dark,
  ;; its hue kept, clipped to sRGB (_defaults.scss:25-37, 90-111;
  ;; adw-accent-color.c:144-146). OKLab by Bjorn Ottosson's published
  ;; matrices.
  (define (adwaita-standalone c dark?)
    (define (lin v)
      (if (<= v 0.04045) (/ v 12.92) (expt (/ (+ v 0.055) 1.055) 2.4)))
    (define (gam v)
      (let ([v (max 0.0 (min 1.0 v))])
        (if (<= v 0.0031308)
            (* 12.92 v)
            (- (* 1.055 (expt v (/ 1 2.4))) 0.055))))
    (define (cbrt v) (if (< v 0) (- (expt (- v) 1/3)) (expt v 1/3)))
    (define (byte v) (exact (round (* 255 (gam v)))))
    (let*-values ([(r g b a) (color-rgba c)]
                  [(r g b) (values (lin r) (lin g) (lin b))]
                  [(l) (cbrt (+ (* 0.4122214708 r) (* 0.5363325363 g)
                                (* 0.0514459929 b)))]
                  [(m) (cbrt (+ (* 0.2119034982 r) (* 0.6806995451 g)
                                (* 0.1073969566 b)))]
                  [(s) (cbrt (+ (* 0.0883024619 r) (* 0.2817188376 g)
                                (* 0.6299787005 b)))]
                  [(L) (+ (* 0.2104542553 l) (* 0.7936177850 m)
                          (* -0.0040720468 s))]
                  [(A) (+ (* 1.9779984951 l) (* -2.4285922050 m)
                          (* 0.4505937099 s))]
                  [(B) (+ (* 0.0259040371 l) (* 0.7827717662 m)
                          (* -0.8086757660 s))]
                  [(L) (if dark? (max L 0.85) (min L 0.5))]
                  [(l) (expt (+ L (* 0.3963377774 A) (* 0.2158037573 B)) 3)]
                  [(m) (expt (+ L (* -0.1055613458 A) (* -0.0638541728 B)) 3)]
                  [(s) (expt (+ L (* -0.0894841775 A) (* -1.2914855480 B))
                             3)])
      (rgb (byte (+ (* 4.0767416621 l) (* -3.3077115913 m)
                    (* 0.2309699292 s)))
           (byte (+ (* -1.2684380046 l) (* 2.6097574011 m)
                    (* -0.3413193965 s)))
           (byte (+ (* -0.0041960863 l) (* -0.7034186147 m)
                    (* 1.7076147010 s))))))

  ;; The surfaces the Adwaita palettes give exactly (_defaults.scss:39-88);
  ;; under another palette, its window's color lightened as GNOME's dark
  ;; style lightens it, a header bar by 5 % of white, a card by 8 %, a
  ;; popover by 10 %, a sidebar a step toward the text.
  (at-load
   (color-default! 'adwaita-headerbar (theme-rule (mix 'bg-1 #xffffff 0.05))))
  (at-load
   (color-default! 'adwaita-card (theme-rule (mix 'bg-1 #xffffff 0.08))))
  (at-load
   (color-default! 'adwaita-popover (theme-rule (mix 'bg-1 #xffffff 0.1))))
  (at-load
   (color-default! 'adwaita-dialog
                   (theme-rule (adwaita-by-style (theme 'bg-1)
                                                 (theme 'adwaita-popover)))))
  (at-load
   (color-default! 'adwaita-sidebar (theme-rule (mix 'bg-1 'text 0.06))))
  ;; A knob: white mixed 80 % into the view (_colors.scss:98).
  (at-load
   (color-default! 'adwaita-slider (theme-rule (mix #xffffff 'bg-0 0.2))))
  (at-load
   (color-default! 'adwaita-destructive (theme-rule (theme 'red))))
  ;; The accent and the destructive red as text (_defaults.scss:25-36):
  ;; the accent's is GNOME's link color (_colors.scss:79), and its focus
  ;; ring's.
  (at-load
   (color-default! 'adwaita-link
                   (theme-rule (adwaita-standalone 'accent (adwaita-dark?)))))
  (at-load
   (color-default! 'adwaita-destructive-ink
                   (theme-rule (adwaita-standalone 'adwaita-destructive
                                                   (adwaita-dark?)))))
  ;; A toggle group's chosen toggle (_defaults.scss:113-119).
  (at-load
   (color-default! 'adwaita-toggle
                   (theme-rule (adwaita-by-style #xffffff
                                                 (alpha #xffffff 0.2)))))
  ;; The shades: a header bar's line (_defaults.scss:52), a boxed list's
  ;; line between rows (71), a sidebar's border (60), and what dims the
  ;; window under a dialog, the shade at twice its alpha (87,
  ;; widgets/_dialogs.scss:72-74).
  (at-load
   (color-default! 'adwaita-headerbar-shade
                   (theme-rule (alpha #x000006 (adwaita-by-style 0.12 0.36)))))
  (at-load
   (color-default! 'adwaita-card-shade
                   (theme-rule (alpha #x000006 (adwaita-by-style 0.07 0.36)))))
  (at-load
   (color-default! 'adwaita-sidebar-border
                   (theme-rule (alpha #x000006 (adwaita-by-style 0.07 0.36)))))
  (at-load
   (color-default! 'adwaita-dim
                   (theme-rule (alpha #x000006 (adwaita-by-style 0.14 0.5)))))
  ;; An overlay scroll bar's outline (_defaults.scss:88).
  (at-load
   (color-default! 'adwaita-scrollbar-outline
                   (theme-rule (adwaita-by-style #xffffff
                                                 (alpha #x00000c 0.95)))))
  ;; A tooltip's (widgets/_tooltip.scss:5), the same in both styles.
  (at-load
   (color-default! 'adwaita-tooltip (alpha #x000006 0.8)))
  ;; GNOME Shell's dark style: its menus' color, text, dimmed text (the fg
  ;; mixed half into the bg) and border (shell _colors.scss:12-13, 39,
  ;; 52), a menu item under the pointer and pressed (widgets/
  ;; _popovers.scss:5, _drawing.scss:381-390), a notification's card
  ;; (_message-list.scss:94), the dash and its tiles, lighter under the
  ;; pointer and while chosen (_colors.scss:49, widgets/_dash.scss:57-68).
  (at-load
   (color-default! 'adwaita-shell-bg #x36363a))
  (at-load
   (color-default! 'adwaita-shell-text #xffffff))
  (at-load
   (color-default! 'adwaita-shell-dim #x9b9b9d))
  (at-load
   (color-default! 'adwaita-shell-border #x424247))
  (at-load
   (color-default! 'adwaita-shell-hover #x53535a))
  (at-load
   (color-default! 'adwaita-shell-pressed #x58585f))
  (at-load
   (color-default! 'adwaita-shell-card #x54545a))
  (at-load
   (color-default! 'adwaita-dash #x38383b))
  (at-load
   (color-default! 'adwaita-dash-hover #x49494d))
  (at-load
   (color-default! 'adwaita-dash-checked #x4c4c4f))
  (at-load
   (color-default! 'adwaita-dash-text #xfafafb))

  ;; The style's own settings: a title-1 text, 181 % bold (widgets/
  ;; _labels.scss:35-38), a status page's; the radius of a button (9:
  ;; _common.scss:8), 12 in an alert, which a dialog's place gives; the
  ;; header bar flat, as a toolbar view has it, or raised (widgets/
  ;; _toolbars.scss:259-314); and the window buttons shown.
  (at-load
   (theme-default! 'adwaita-title-1 (theme-font-rule 'ui 12 'bold)))
  (at-load
   (theme-default! 'adwaita-button-radius 9))
  (at-load
   (theme-default! 'adwaita-header 'flat))
  (at-load
   (theme-default! 'adwaita-window-buttons 'close))

  ;;; ------------------------------------------------------------------
  ;;; the window: a libadwaita window, its title bar a header bar

  ;; A header bar is 46 high in a window: its buttons' 34 and 6 above and
  ;; below them (widgets/_header-bar.scss:2, 14-15, 83-89); a larger text
  ;; makes its buttons, and so it, taller.
  (define (adwaita-header-height) (+ 12 (ui-control-height)))

  (define (adwaita-insets win) (values 0 (adwaita-header-height) 0 0))

  ;; 15 round (_common.scss:16-17), square while maximized (widgets/
  ;; _window.scss:52-55).
  (define (adwaita-radius win) (if (maximized? win) 0 (theme 'corner-radius)))

  ;; As GNOME lays the window's buttons out by default ("appmenu:close"),
  ;; close alone; with adwaita-window-buttons all, minimize and maximize
  ;; before it, as GNOME Tweaks shows them.
  (define (adwaita-button-kinds)
    (if (eq? (theme 'adwaita-window-buttons) 'all)
        '(minimize maximize close)
        '(close)))

  ;; Each a control's square, 3 apart, 6 from the bar's end (widgets/
  ;; _header-bar.scss:9-15, 164-170).
  (define (adwaita-regions win)
    (let* ([b (ui-control-height)] [kinds (adwaita-button-kinds)]
           [n (length kinds)]
           [x0 (- (window-w win) 6 (* n b) (* 3 (- n 1)))]
           [y (quotient (- (adwaita-header-height) b) 2)])
      (map (lambda (k i) (list k (+ x0 (* i (+ b 3))) y b b)) kinds (iota n))))

  ;; The window, and its header bar: flat, the window's own color, or
  ;; raised, the header bar's (white in the light style) while the window
  ;; has the focus.
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

  ;; The title, bold, in the bar's middle, clear of the buttons either side
  ;; as GTK centers it (widgets/_header-bar.scss:199-205), after the
  ;; window's icon if its app gave one; an unfocused window's at half
  ;; strength (35-45).
  (define (adwaita-title win x y w hh focused?)
    (let* ([icon (ui-title-icon win)] [s (ui-glyph-size)]
           [side (+ 6 12 (* (length (adwaita-button-kinds))
                            (+ (ui-control-height) 3)))]
           [iw (if icon (+ s 6) 0)]
           [t (text-fit (window-title win) (max 0 (- w side side iw)) 'title)]
           [tw (text-width t 'title)]
           [tx (+ x (/ (- w tw iw) 2))])
      (when icon (icon tx (+ y (/ (- hh s) 2)) s (if focused? '() '(dim))))
      (text-draw-centered (+ tx iw) y tw hh t
                          (if focused? 'title-text 'title-text-dim) 'title)))

  ;; A window button: a 24-pixel circle of the text at 10 %, 15 % under
  ;; the pointer, 30 % pressed, its glyph in it (widgets/_header-bar.scss:
  ;; 167-188); an unfocused window's at half strength.
  (define (adwaita-window-button win x y reg focused? hover pressed)
    (let* ([kind (car reg)] [cx (+ x (cadr reg) (/ (cadddr reg) 2))]
           [cy (+ y (caddr reg) (/ (list-ref reg 4) 2))]
           [a (cond [(eq? pressed kind) 0.3] [(eq? hover kind) 0.15]
                    [else 0.1])])
      (fill-circle cx cy 12 (alpha 'text (if focused? a (/ a 2))))
      (adwaita-window-glyph (ui-frame-glyph win kind) cx cy
                            (if focused? 'text (alpha 'text 0.5)))))

  ;; The window's glyphs, after the Adwaita icons' shapes, 2 wide: close an
  ;; X 8 across, maximize a square, restore two, minimize a bar low down.
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
        (stroke-box x y w h (alpha #xffffff 0.07) 1 r))))

  ;;; ------------------------------------------------------------------
  ;;; buttons

  ;; The focus: a ring 2 wide of the accent at half strength inside the
  ;; edge (_drawing.scss:12-23, _colors.scss:2, 116); outside it, past a
  ;; pixel's gap, for a suggested button or a switch (widgets/
  ;; _buttons.scss:158, _switch.scss:11).
  (define (adwaita-ring x y w h r)
    (stroke-box x y w h (alpha 'adwaita-link 0.5) 2 r))

  (define (adwaita-ring-outside x y w h r)
    (stroke-box (- x 3) (- y 3) (+ w 6) (+ h 6) (alpha 'adwaita-link 0.5)
                2 (+ r 3)))

  ;; The kit's ring, for what draws its own: inside.
  (define (adwaita-focus x y w h flags r) (adwaita-ring x y w h r))

  ;; A box r round, square on its joined sides (flags join-left,
  ;; join-right): a linked button's, a stepper's pieces (widgets/
  ;; _linked.scss:14-45).
  (define (adwaita-box x y w h color r flags)
    (if (or (memq 'join-left flags) (memq 'join-right flags))
        (let-values ([(bx bw) (ui-joined-span x w r flags)])
          (with-clip (x y w h) (fill-box bx y bw h color r)))
        (fill-box x y w h color r)))

  ;; A button's glyph, 16 square, and its label, bold, centered together,
  ;; 6 apart (widgets/_buttons.scss:24, 618-627).
  (define (adwaita-button-content x y w h label glyph ink)
    (let* ([g (ui-glyph-size)] [gw (cond [(not glyph) 0] [label (+ g 6)]
                                         [else g])]
           [label (and label (text-fit label (max 0 (- w 18 gw)) 'ui-bold))]
           [x0 (+ x (/ (- w gw (if label (text-width label 'ui-bold) 0)) 2))])
      (when glyph
        (ui-draw-glyph x0 (+ y (/ (- h g) 2)) g g (list (cons 'ink ink)) glyph))
      (when label
        (draw-text (+ x0 gw) (+ y (/ (- h (font-line-height 'ui-bold)) 2))
                   label ink 'ui-bold))))

  ;; A button (widgets/_buttons.scss): the text at 10 % behind its label,
  ;; 15 % under the pointer, 30 % pressed and pressed in (selected), 35 and
  ;; 40 % pressed in and under the pointer or pressed (1-6, 17-56); flat
  ;; (quiet), nothing at rest, 7 % under the pointer, 16 % pressed, 10 %
  ;; pressed in (234-274, _colors.scss:82-86); suggested (primary), the
  ;; accent, its label white, white at 10 % over it under the pointer,
  ;; rgb(0 0 6 / 20%) pressed (155-181, 220-228); destructive (danger),
  ;; its label in the destructive red and that red at 15 % behind it, 20 %
  ;; under the pointer, 35 % pressed (10-15, 183-211). Disabled, it is all at
  ;; half strength, a flat one at 30 % (58-64, 272-274); a joined piece (a
  ;; stepper's) keeps its box, its neighbors' too. A pill and a round one
  ;; are round at their ends (312-326); a segment is a toggle group's.
  (define (adwaita-button x y w h flags label glyph)
    (if (memq 'segment flags)
        (adwaita-toggle-piece x y w h flags label glyph)
        (let* ([on? (lambda (f) (memq f flags))]
               [off? (on? 'disabled)]
               [hover? (and (not off?) (on? 'hover))]
               [pressed? (and (not off?) (on? 'pressed))]
               [sel? (on? 'selected)] [flat? (on? 'quiet)]
               [joined? (or (on? 'join-left) (on? 'join-right))]
               [fade (cond [(not off?) 1] [(and flat? (not sel?)) 0.3]
                           [else 0.5])]
               [ink (lambda (c) (if (= fade 1) c (alpha c fade)))]
               [box (lambda (c) (if joined? c (ink c)))]
               [r (ui-button-radius h flags (theme 'adwaita-button-radius))]
               [fill
                (cond
                  [(on? 'primary) 'accent]
                  [(on? 'danger)
                   (alpha 'adwaita-destructive-ink
                          (cond [pressed? (if sel? 0.45 0.35)]
                                [hover? (if sel? 0.4 0.2)]
                                [sel? 0.35]
                                [else 0.15]))]
                  [flat? (cond [pressed? (alpha 'text (if sel? 0.19 0.16))]
                               [sel? (alpha 'text (if hover? 0.13 0.1))]
                               [hover? (alpha 'text 0.07)]
                               [else #f])]
                  [else (alpha 'text (cond [pressed? (if sel? 0.4 0.3)]
                                           [hover? (if sel? 0.35 0.15)]
                                           [sel? 0.3]
                                           [else 0.1]))])]
               [over (and (on? 'primary)
                          (cond [pressed? (alpha #x000006 0.2)]
                                [hover? (alpha #xffffff 0.1)]
                                [sel? (alpha #x000006 0.15)]
                                [else #f]))])
          (when fill (adwaita-box x y w h (box fill) r flags))
          (when over (adwaita-box x y w h over r flags))
          (adwaita-button-content x y w h label glyph
                                  (ink (cond [(on? 'primary) #xffffff]
                                             [(on? 'danger)
                                              'adwaita-destructive-ink]
                                             [else 'text])))
          (when (on? 'focused)
            (if (on? 'primary)
                (adwaita-ring-outside x y w h r)
                (adwaita-ring x y w h r))))))

  ;; A piece of a toggle group (AdwToggleGroup: widgets/_toggle-group.scss:
  ;; 9-102), a segmented choice's or a tab's: the group the text at 10 %,
  ;; 9 round at its ends; 3 inside it each toggle, 6 round, a pixel from its
  ;; neighbors, its label bold; the chosen one raised in the toggle color
  ;; (white in the light style) with a card's soft shadow, another the
  ;; text at 7 % under the pointer, 16 % pressed.
  (define (adwaita-toggle-piece x y w h flags label glyph)
    (let* ([on? (lambda (f) (memq f flags))]
           [off? (on? 'disabled)]
           [ink (lambda (c) (if off? (alpha c 0.3) c))]
           [l (if (on? 'join-left) 1 3)] [rt (if (on? 'join-right) 1 3)]
           [cx (+ x l)] [cy (+ y 3)] [cw (- w l rt)] [ch (- h 6)])
      (adwaita-box x y w h (alpha 'text 0.1) (theme 'adwaita-button-radius)
                   flags)
      (cond [(on? 'selected)
             (unless off? (draw-shadow cx cy cw ch 6 3))
             (fill-box cx cy cw ch (ink 'adwaita-toggle) 6)]
            [(and (not off?) (on? 'pressed))
             (fill-box cx cy cw ch (alpha 'text 0.16) 6)]
            [(and (not off?) (on? 'hover))
             (fill-box cx cy cw ch (alpha 'text 0.07) 6)])
      (adwaita-button-content cx y cw h label glyph (ink 'text))
      (when (on? 'focused) (adwaita-ring cx cy cw ch 6))))

  ;; A label's button is 17 either side of it (widgets/_buttons.scss:
  ;; 72-75), a glyph's and a label's 9 (77-91), a glyph's alone a square.
  (define (adwaita-button-size label glyph)
    (let ([h (ui-control-height)])
      (values (cond [(not label) h]
                    [glyph (+ 9 (ui-glyph-size) 6 (text-width label 'ui-bold)
                              2 9)]
                    [else (+ 34 (text-width label 'ui-bold))])
              h)))

  ;;; ------------------------------------------------------------------
  ;;; check boxes, radios and switches

  ;; A check box's or a radio's mark, 20 square at x y, r round (widgets/
  ;; _checks.scss:20-61): empty, a ring 2 wide of the text at 15 %, 20 %
  ;; under the pointer, a fill of 25 % pressed; checked, the accent, white
  ;; at 10 % over it under the pointer, rgb(0 0 6 / 20%) pressed.
  (define (adwaita-check-box x y flags r)
    (let* ([on? (lambda (f) (memq f flags))] [off? (on? 'disabled)]
           [ink (lambda (c) (if off? (alpha c 0.5) c))]
           [hover? (and (not off?) (on? 'hover))]
           [pressed? (and (not off?) (on? 'pressed))])
      (if (on? 'checked)
          (begin
            (fill-box x y 20 20 (ink 'accent) r)
            (cond [pressed? (fill-box x y 20 20 (alpha #x000006 0.2) r)]
                  [hover? (fill-box x y 20 20 (alpha #xffffff 0.1) r)]))
          (if pressed?
              (fill-box x y 20 20 (alpha 'text 0.25) r)
              (stroke-box x y 20 20 (ink (alpha 'text (if hover? 0.2 0.15))) 2
                          r)))))

  ;; Its label, 4 after the mark, as the whole widget's focus ring has it,
  ;; 4 out and 9 round (widgets/_checks.scss:3-13).
  (define (adwaita-check-label x y w h flags label)
    (let ([lh (font-line-height 'ui)] [by (+ y (floor (/ (- h 20) 2)))])
      (when label
        (draw-text (+ x 24) (+ y (/ (- h lh) 2))
                   (text-fit label (max 0 (- w 24)) 'ui)
                   (if (memq 'disabled flags) (alpha 'text 0.5) 'text) 'ui))
      (when (memq 'focused flags)
        (adwaita-ring (- x 4) (- by 4)
                      (+ 28 (if label (+ 4 (text-width label 'ui)) 0)) 28 9))))

  ;; A check box: the mark 6 round, its check white, a stroke 2.5 wide
  ;; through the points of the 14-pixel check icon (widgets/_checks.scss:
  ;; 68-72).
  (define (adwaita-checkbox x y w h flags label)
    (let ([by (+ y (floor (/ (- h 20) 2)))])
      (adwaita-check-box x by flags 6)
      (when (memq 'checked flags)
        (draw-polyline (list (cons (+ x 4.9) (+ by 10.3))
                             (cons (+ x 8.75) (+ by 14.1))
                             (cons (+ x 15.3) (+ by 6.8)))
                       (if (memq 'disabled flags) (alpha #xffffff 0.5) #xffffff)
                       2.5))
      (adwaita-check-label x y w h flags label)))

  ;; The mark, 4, the label and the ring's 4 (a check button "Check" is 72
  ;; by 28, measured).
  (define (adwaita-checkbox-size label)
    (values (+ 24 (text-width label 'ui) 4) 28))

  ;; Where a radio's label starts: after the mark and 4, and an icon and 6.
  (define (adwaita-radio-text-x icon?)
    (+ 24 (if icon? (+ (ui-glyph-size) 6) 0)))

  ;; A control's height, or its label and its hint wrapped under it.
  (define (adwaita-radio-size label hint icon? w)
    (let* ([tw (max 0 (- w (adwaita-radio-text-x icon?)))]
           [hh (if hint
                   (let-values ([(hw hh) (ui-label-size '(hint wrap) hint tw)])
                     hh)
                   0)])
      (values w (max (ui-control-height)
                     (+ 8 (font-line-height 'ui) (if hint (+ 2 hh) 0))))))

  ;; A radio: the mark round, its bullet a white dot 8 across (widgets/
  ;; _checks.scss:75-79); the label, an icon before it, a hint under it.
  (define (adwaita-radio x y w h flags label hint icon)
    (let* ([lh (font-line-height 'ui)] [g (ui-glyph-size)]
           [ly (if hint (+ y 4) (+ y (/ (- h lh) 2)))]
           [by (+ ly (floor (/ (- lh 20) 2)))]
           [off? (memq 'disabled flags)]
           [ink (lambda (c) (if off? (alpha c 0.5) c))]
           [tx (+ x (adwaita-radio-text-x icon))])
      (adwaita-check-box x by flags 10)
      (when (memq 'checked flags)
        (fill-circle (+ x 10) (+ by 10) 4 (ink #xffffff)))
      (when icon (icon (+ x 24) (+ ly (/ (- lh g) 2)) g flags))
      (draw-text tx ly (text-fit label (max 0 (- (+ x w) tx)) 'ui) (ink 'text)
                 'ui)
      (when hint
        (fold-left (lambda (hy line)
                     (draw-text tx hy line (ink 'text-dim) 'ui-small)
                     (+ hy (font-line-height 'ui-small)))
                   (+ ly lh 2)
                   (ui-label-lines hint (max 0 (- (+ x w) tx)) 'ui-small)))
      (when (memq 'focused flags)
        (adwaita-ring (- x 4) (- by 4)
                      (+ 28 4 (text-width label 'ui)) 28 9))))

  ;; A switch (widgets/_switch.scss): its track 46 by 26, round (GTK makes
  ;; it two knobs wide: gtkswitch.c), the text at 15 %, 20 % under the
  ;; pointer, 25 % pressed (1-9), the accent when on (34-39); its knob a
  ;; 20-pixel circle 3 in, the slider color (white in the light style),
  ;; white under the pointer and when on, over a soft shadow (17-32). Its
  ;; label goes first and the switch at the end, as a switch row has them
  ;; (widgets/_lists.scss:124-163); focused, a ring outside it (11).
  (define (adwaita-toggle x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [checked? (on? 'checked)]
           [pressed? (on? 'pressed)] [hover? (on? 'hover)]
           [tx (if label (- (+ x w) 46) x)] [ty (+ y (floor (/ (- h 26) 2)))]
           [kx (if checked? (+ tx 33) (+ tx 13))] [ky (+ ty 13)])
      (fill-box tx ty 46 26
                (if checked?
                    'accent
                    (alpha 'text (cond [pressed? 0.25] [hover? 0.2]
                                       [else 0.15])))
                13)
      (when checked?
        (cond [pressed? (fill-box tx ty 46 26 (alpha #x000006 0.2) 13)]
              [hover? (fill-box tx ty 46 26 (alpha #xffffff 0.1) 13)]))
      (draw-shadow (- kx 10) (- ky 10) 20 20 10 4)
      (fill-circle kx ky 10
                   (if (or checked? hover? pressed?) #xffffff 'adwaita-slider))
      (when label
        (draw-text x (+ y (/ (- h (font-line-height 'ui)) 2))
                   (text-fit label (max 0 (- w 46 12)) 'ui) 'text 'ui))
      (when (on? 'focused) (adwaita-ring-outside tx ty 46 26 13))))

  (define (adwaita-toggle-size label)
    (values (+ (text-width label 'ui) 12 46) (ui-control-height)))

  (define (adwaita-toggle-track) (values 46 26))

  ;;; ------------------------------------------------------------------
  ;;; scales and progress

  ;; A scale (widgets/_scale.scss): a trough 4 high and round, the text at
  ;; 15 %, 20 % under the pointer, the accent up to the value (3-18, 57-63;
  ;; GTK sizes the trough from the knob, gtkrange.c); the knob a 20-pixel
  ;; circle of the slider color, white under the pointer, ringed in rgb(0
  ;; 0 6 / 10%) over a soft shadow (44-54). A painted track (Settings'
  ;; colors) is 6 high under the knob.
  (define (adwaita-slider x y w h flags frac paint)
    (let* ([cy (+ y (/ h 2))] [kx (+ x (* frac w))]
           [hot? (or (memq 'hover flags) (memq 'pressed flags))])
      (if paint
          (with-clip (x (- cy 3) w 6 3) (paint x (- cy 3) w 6))
          (begin
            (fill-box x (- cy 2) w 4 (alpha 'text (if hot? 0.2 0.15)) 2)
            (fill-box x (- cy 2) (max 4 (- kx x)) 4 'accent 2)
            (when hot?
              (fill-box x (- cy 2) (max 4 (- kx x)) 4 (alpha #xffffff 0.1)
                        2))))
      (draw-shadow (- kx 10) (- cy 10) 20 20 10 4)
      (fill-circle kx cy 10 (if hot? #xffffff 'adwaita-slider))
      (stroke-circle kx cy 10.5 (alpha #x000006 0.1) 1)
      (when (memq 'focused flags)
        (stroke-circle kx cy 11 (alpha 'adwaita-link 0.5) 2))))

  ;; A progress bar (widgets/_progress-bar.scss:1-56): a round trough, the
  ;; text at 15 %, the accent filling it; 8 high, the progress-height.
  (define (adwaita-progress x y w h flags frac)
    (fill-box x y w h (alpha 'text 0.15) (/ h 2))
    (when (> frac 0)
      (fill-box x y (max h (* w (min 1 frac))) h 'accent (/ h 2))))

  ;;; ------------------------------------------------------------------
  ;;; tabs, labels and surfaces

  ;; Tabs are libadwaita 1.7's inline view switcher, a toggle group of the
  ;; views (adwaita-toggle-piece), the group's ends round.
  (define (adwaita-tab x y w h flags label)
    (adwaita-toggle-piece x y w h
                          (append (if (memq 'first flags) '() '(join-left))
                                  (if (memq 'last flags) '() '(join-right))
                                  flags)
                          label #f))

  ;; Each its label, bold, and 11 either side (a toggle's 8, the group's
  ;; 3); a control high.
  (define (adwaita-tabs-size labels)
    (values (fold-left (lambda (acc l) (+ acc 22 (text-width l 'ui-bold))) 0
                       labels)
            (ui-control-height)))

  ;; A label: a heading's and a group's bold, in the text's color (.heading:
  ;; widgets/_labels.scss:55-57), a hint and a description dimmed (13-15),
  ;; an error in the destructive red.
  (define (adwaita-label x y w h flags text)
    (let* ([font (ui-label-font flags)]
           [color (cond [(memq 'error flags) 'adwaita-destructive-ink]
                        [(or (memq 'dim flags) (memq 'hint flags)
                             (memq 'mono flags))
                         'text-dim]
                        [else 'text])]
           [text (ui-label-text flags text)]
           [lh (font-line-height font)]
           [at (lambda (s)
                 (cond [(memq 'right flags) (- (+ x w) (text-width s font))]
                       [(memq 'center flags)
                        (+ x (/ (- w (text-width s font)) 2))]
                       [else x]))])
      (if (memq 'wrap flags)
          (fold-left (lambda (y line) (draw-text (at line) y line color font)
                       (+ y lh))
                     y (ui-label-lines text w font))
          (let ([s (text-fit text w font)])
            (draw-text (at s) (+ y (max 0 (/ (- h lh) 2))) s color font)
            (+ y (max h lh))))))

  ;; Surfaces: a page the window's color; a toolbar or a footer a top or a
  ;; bottom bar's, flat as the header is, or raised, the header bar's color
  ;; with its shade's line toward the page (widgets/_toolbars.scss:113-131,
  ;; 187-208, 259-314); a side pane and a column of places a sidebar's, its
  ;; border toward the content (widgets/_sidebars.scss:1-32); a well a
  ;; frame, the view's color in a border, 12 round (widgets/_misc.scss:4-15).
  (define (adwaita-surface x y w h flags)
    (let* ([floating? (memq 'floating flags)]
           [paper (lambda (c)
                    (if floating? (alpha c (theme 'floating-opacity)) c))]
           [raised? (eq? (theme 'adwaita-header) 'raised)]
           [bar (if raised? 'adwaita-headerbar 'bg-1)])
      (cond
        [(memq 'well flags)
         (fill-box x y w h 'bg-0 12)
         (stroke-box x y w h (alpha 'text 0.15) 1 12)]
        [(memq 'nav flags)
         (fill-box x y w h (paper 'adwaita-sidebar))
         (fill-box (+ x w -1) y 1 h 'adwaita-sidebar-border)]
        [(memq 'side flags)
         (fill-box x y w h (paper 'adwaita-sidebar))
         (fill-box x y 1 h 'adwaita-sidebar-border)]
        [(memq 'toolbar flags)
         (fill-box x y w h (paper bar))
         (when raised?
           (fill-box x (+ y h -1) w 1 'adwaita-headerbar-shade))]
        [(memq 'footer flags)
         (fill-box x y w h (paper bar))
         (when raised? (fill-box x y w 1 'adwaita-headerbar-shade))]
        [else (fill-box x y w h (paper 'bg-1))])))

  ;;; ------------------------------------------------------------------
  ;;; entries, dropdowns, steppers and tags

  ;; An entry (widgets/_entries.scss:1-40): the text at 10 % behind it,
  ;; 9 round, no border; focused, the ring inside it however the focus
  ;; came (17). A text area is one too.
  (define (adwaita-field x y w h flags)
    (adwaita-box x y w h (alpha 'text 0.1) 9 flags)
    (when (memq 'focused flags)
      (if (or (memq 'join-left flags) (memq 'join-right flags))
          (let-values ([(bx bw) (ui-joined-span x w 9 flags)])
            (with-clip (x y w h) (adwaita-ring bx y bw h 9)))
          (adwaita-ring x y w h 9))))

  ;; Its text 9 in from either side (widgets/_entries.scss:5-6), after a
  ;; search glyph and 6 (8); an area's lines 6 down.
  (define (adwaita-text-box-areas x y w h flags)
    (let* ([left (if (memq 'search flags) (+ 9 (ui-glyph-size) 6) 9)]
           [bw (ui-scrollbar-width)]
           [font (if (memq 'large flags) 'heading 'ui)]
           [top (ui-text-box-top h flags font 6)])
      (list (list 'edit (+ x left) (+ y top) (max 0 (- w left 9))
                  (max 0 (- h top top)) font)
            (list 'bar (- (+ x w) bw) y bw h))))

  ;; A dropdown (widgets/_dropdowns.scss:1-14): a button holding the
  ;; choice, bold, 9 in, and the pan-down arrow 16 square 6 after the text
  ;; and 9 from the end; open, pressed in.
  (define (adwaita-dropdown x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [g (ui-glyph-size)]
           [lh (font-line-height 'ui-bold)])
      (fill-box x y w h
                (alpha 'text (cond [(or (on? 'open) (on? 'pressed)) 0.3]
                                   [(on? 'hover) 0.15]
                                   [else 0.1]))
                9)
      (draw-text (+ x 9) (+ y (/ (- h lh) 2))
                 (text-fit label (max 0 (- w 9 6 g 9)) 'ui-bold)
                 (cond [(on? 'set) 'adwaita-link]
                       [(on? 'placeholder) 'text-dim]
                       [else 'text])
                 'ui-bold)
      (ui-draw-glyph (- (+ x w) 9 g) (+ y (/ (- h g) 2)) g g '((ink . text))
                     'chevron-down)
      (when (on? 'focused) (adwaita-ring x y w h 9))))

  (define (adwaita-dropdown-size labels)
    (values (min (* 10 (font-line-height 'ui))
                 (+ 9 (text-widest labels 'ui-bold) 6 (ui-glyph-size) 9))
            (ui-control-height)))

  ;; A spin button (widgets/_spin-button.scss): the number at the start,
  ;; then - and +, a control square each, in one box; each piece shares a
  ;; pixel with the next, where a line shows, as GTK's separators do.
  (define (adwaita-stepper-areas x y w h)
    (let ([b (ui-control-height)])
      (list (list 'field x y (- w b b -1) h 'join-right)
            (list 'down (- (+ x w) b b) y (+ b 1) h 'join-left 'join-right)
            (list 'up (- (+ x w) b) y b h 'join-left))))

  ;; A tag, which GNOME has no widget for, made as its designers make small
  ;; things: a pill of the text at 10 % (a toggle group's tint, widgets/
  ;; _toggle-group.scss:12-14), its label a caption (widgets/_labels.scss:
  ;; 68-71), the tag's own color a 6-pixel dot before it, as GNOME marks
  ;; what needs attention (_common.scss:106-120); a removable one's × a
  ;; round flat button at its end.
  (define (adwaita-chip x y w h flags label)
    (let* ([sh (font-line-height 'ui-small)] [g (ui-small-glyph-size)]
           [rem? (memq 'removable flags)])
      (fill-box x y w h (alpha 'text 0.1) (/ h 2))
      (fill-circle (+ x 13) (+ y (/ h 2)) 3
                   (app-color (string->symbol label)))
      (draw-text (+ x 22) (+ y (/ (- h sh) 2))
                 (text-fit label (max 0 (- w 32 (if rem? (+ g 4) 0)))
                           'ui-small)
                 'text 'ui-small)
      (when rem?
        (let* ([a (cdr (assq 'remove (ui-chip-areas x y w h)))]
               [cx (+ (car a) (/ (caddr a) 2))] [cy (+ y (/ h 2))])
          (when (memq 'hover flags)
            (fill-circle cx cy (/ (- h 4) 2)
                         (alpha 'text (if (memq 'pressed flags) 0.16 0.07))))
          (ui-draw-glyph (- cx (/ g 2)) (- cy (/ g 2)) g g '((ink . text))
                         'cross)))))

  (define (adwaita-chip-size label removable?)
    (values (+ 32 (text-width label 'ui-small)
               (if removable? (+ (ui-small-glyph-size) 4) 0))
            (round (+ (font-line-height 'ui-small) 10))))

  ;; A card's edge (widgets/_misc.scss:194-227), drawn over what the app
  ;; drew in it, so of the card's shadows, which would cover that, its
  ;; hairline alone, the text at 12 %; under the pointer a tint of 3 %;
  ;; chosen or dragged, the accent's ring, as GNOME rings a chosen picture.
  (define (adwaita-card x y w h flags)
    (let ([r (ui-card-radius)])
      (if (or (memq 'selected flags) (memq 'floating flags))
          (stroke-box x y w h 'accent 2 r)
          (begin
            (when (memq 'hover flags) (fill-box x y w h (alpha 'text 0.03) r))
            (stroke-box x y w h (alpha 'text 0.12) 1 r)))))

  ;; A card is 12 round (_common.scss:9).
  (define (adwaita-card-radius) 12)

  ;;; ------------------------------------------------------------------
  ;;; scroll bars and lists

  ;; An overlay scroll bar (widgets/_scrolling.scss), shown while the
  ;; pointer is over its view: at rest a line 3 wide 4 from the edge, the
  ;; text at 20 %, outlined in the scroll bar outline color at 35 % (48-77,
  ;; 107-110); under the pointer 8 wide on a trough of 10 %, the text at
  ;; 40 % (60 % pressed), the outline at 60 % (26-32, 79-81); at least 40
  ;; long (2).
  (define (adwaita-scrollbar-areas x y w h start size)
    (let* ([l (max 0 (- h 8))] [th (min l (max 40 (* size l)))])
      (list (list 'thumb x
                  (+ y 4 (if (< size 1) (* (- l th) (/ start (- 1 size))) 0))
                  w th))))

  (define (adwaita-scrollbar x y w h flags start size)
    (let* ([t (cdr (assq 'thumb (adwaita-scrollbar-areas x y w h start size)))]
           [ty (cadr t)] [th (cadddr t)]
           [pressed? (memq 'pressed flags)]
           [hot? (or pressed? (memq 'hover flags))]
           [sw (if hot? 8 3)] [sx (- (+ x w) 4 sw)])
      (when hot? (fill-box sx (+ y 4) sw (- h 8) (alpha 'text 0.1) 4))
      (stroke-box (- sx 1) (- ty 1) (+ sw 2) (+ th 2)
                  (alpha 'adwaita-scrollbar-outline (if hot? 0.6 0.35)) 1
                  (+ (/ sw 2) 1))
      (fill-box sx ty sw th
                (alpha 'text (cond [pressed? 0.6] [hot? 0.4] [else 0.2]))
                (/ sw 2))))

  ;; A column view (widgets/_column-view.scss): a heading a caption, bold,
  ;; the text at 40 % (70 % under the pointer), 6 in as the cells are (12-53,
  ;; 72-84); no line under it, nor between rows or columns but where they
  ;; are asked for (86-97).
  (define (adwaita-table-header x y w h flags label dir)
    (let* ([in 6] [f 'ui-small-bold] [g (ui-glyph-size)]
           [s (text-fit label (max 0 (- w in in (if dir (+ g 6) 0))) f)]
           [ink (alpha 'text (if (or (memq 'hover flags) (memq 'pressed flags))
                                 0.7
                                 0.4))]
           [right? (memq 'right flags)]
           [tx (if right? (- (+ x w) in (text-width s f)) (+ x in))]
           [end (draw-text tx (+ y (/ (- h (font-line-height f)) 2)) s ink f)])
      (when dir
        (ui-draw-glyph (if right? (- tx 6 g) (+ end 6)) (+ y (/ (- h g) 2)) g g
                       (list (cons 'ink ink))
                       (if (eq? dir 'up) 'chevron-up 'chevron-down)))))

  ;; A row: chosen, the accent at 25 % (32 % under the pointer); under the
  ;; pointer, the text at 4 % (widgets/_lists.scss:70-89, _colors.scss:
  ;; 88-92).
  (define (adwaita-table-row x y w h flags)
    (cond [(memq 'selected flags)
           (fill-box x y w h
                     (alpha 'accent (if (memq 'hover flags) 0.32 0.25)))]
          [(memq 'hover flags) (fill-box x y w h (alpha 'text 0.04))]))

  ;; A column's edge, the border color, and the accent while dragged.
  (define (adwaita-table-divider x y h flags)
    (if (or (memq 'hover flags) (memq 'pressed flags))
        (fill-box (- x 1) y 2 h 'adwaita-link)
        (fill-box x (+ y 4) 1 (- h 8) (alpha 'text 0.15))))

  (define (adwaita-table-cell-inset) 6)

  ;;; ------------------------------------------------------------------
  ;;; popups

  ;; A popup's box: a tooltip's (widgets/_tooltip.scss:1-15), rgb(0 0 6 /
  ;; 80%) in a hairline of white at 10 %, 9 round; a dialog's sheet
  ;; (widgets/_dialogs.scss:71-84), 15 round, its inner edge white at 7 %;
  ;; a toast, libadwaita's, #505053, round (widgets/_misc.scss:38-69); a
  ;; menu's and the rest a popover's (widgets/_popovers.scss:7-33), its
  ;; color in a hairline of black at 14 %, 15 round, two soft shadows.
  (define (adwaita-panel x y w h flags)
    (cond
      [(memq 'tooltip flags)
       (fill-box x y w h 'adwaita-tooltip 9)
       (stroke-box x y w h (alpha #xffffff 0.1) 1 9)]
      [(memq 'dialog flags)
       (draw-shadow x y w h 15 16)
       (fill-box x y w h 'adwaita-dialog 15)
       (stroke-box x y w h (alpha #xffffff 0.07) 1 15)]
      [(memq 'toast flags)
       (draw-shadow x y w h (/ h 2) 6)
       (fill-box x y w h 'adwaita-toast (/ h 2))]
      [else
       (draw-shadow x y w h 15 10)
       (fill-box x y w h 'adwaita-popover 15)
       (stroke-box x y w h (alpha #x000000 0.14) 1 15)]))

  ;; The chosen entry of a menu or a list: the text at 10 %, 9 round, as a
  ;; menu item under the pointer or the keys (widgets/_menus.scss:130-144),
  ;; 19 % held; one under the pointer not chosen, 7 % (a sidebar row's,
  ;; widgets/_sidebars.scss:105-108), 10 % on a popup.
  (define (adwaita-highlight x y w h flags)
    (fill-box x y w h
              (alpha 'text (cond [(memq 'pressed flags) 0.19]
                                 [(memq 'hover flags)
                                  (if (memq 'popup flags) 0.1 0.07)]
                                 [else 0.1]))
              9))

  ;; A line, the border color (widgets/_misc.scss:21-24).
  (define (adwaita-separator x y w h flags)
    (fill-box x (floor (+ y (/ (- h 1) 2))) w 1 (alpha 'text 0.15)))

  ;; A tooltip's lines: its text in the text's own size, wrapped at 360;
  ;; at most 6, or as many as it has.
  (define (adwaita-tooltip-lines text)
    (let ([n (fold-left (lambda (n c) (if (char=? c #\newline) (+ n 1) n))
                        1 (string->list text))])
      (let-values ([(lines cut?) (ui-wrap-lines text 360 'ui (max 6 n))])
        lines)))

  ;; 6 above and below the text, 10 beside it (widgets/_tooltip.scss:13).
  (define (adwaita-tooltip-size text)
    (let ([lines (adwaita-tooltip-lines text)])
      (values (+ 20 (min 360 (text-widest lines 'ui)))
              (+ 12 (* (length lines) (font-line-height 'ui))))))

  (define (adwaita-tooltip x y w h flags text)
    (ui-draw-panel x y w h '(tooltip))
    (fold-left (lambda (ty line)
                 (draw-text (+ x 10) ty line #xffffff 'ui)
                 (+ ty (font-line-height 'ui)))
               (+ y 6) (adwaita-tooltip-lines text)))

  ;; An alert (AdwAlertDialog: widgets/_message-dialog.scss, adw-alert-
  ;; dialog.c): 300 to 372 wide (175-178), wider when its buttons need it,
  ;; to 600; 32 above its heading, a .title-2 (the heading font), 10 to
  ;; the body, 9 under it, both centered, 24 from the sides (93-112); its
  ;; buttons in a row of equal widths (615-665), 44 high, 12 round, 12
  ;; apart, 24 from the edges and 12 under the body (114-125); 18 round (1).
  (define (adwaita-dialog-button-widths labels)
    (map (lambda (l) (max 60 (+ 40 (text-width l 'ui-bold)))) labels))

  (define (adwaita-dialog-size title message labels)
    (let* ([lh (font-line-height 'ui)] [n (length labels)]
           [need (+ 48 (* n (apply max 60 (adwaita-dialog-button-widths
                                              labels)))
                    (* 12 (max 0 (- n 1))))]
           [w (if (> need 372)
                  (min need 600)
                  (clamp (+ 48 (text-width title 'heading)) 300 372))]
           [ml (if (string=? message "")
                   0
                   (length (ui-dialog-lines message (- w 48))))])
      (values w (round (+ 32 (font-line-height 'heading)
                          (if (> ml 0) (+ 10 (* ml lh)) 0)
                          9 12 44 24)))))

  ;; ((title x y w h) (message ..) (button x y w h) ...).
  (define (adwaita-dialog-areas x y w h labels)
    (let* ([n (length labels)] [hl (font-line-height 'heading)]
           [bw (if (zero? n) 0 (/ (- w 48 (* 12 (- n 1))) n))]
           [by (- (+ y h) 24 44)])
      (append
       (list (list 'title (+ x 24) (+ y 32) (- w 48) hl)
             (list 'message (+ x 24) (+ y 32 hl 10) (- w 48)
                   (max 0 (- h 32 hl 10 9 12 44 24))))
       (map (lambda (i) (list 'button (+ x 24 (* i (+ bw 12))) by bw 44))
            (iota n)))))

  ;; The alert's box, under its sheet's shadows; its heading and its body
  ;; centered, the body as the dialog's text (widgets/_message-dialog.scss:
  ;; 53-66).
  (define (adwaita-dialog x y w h flags title message)
    (let* ([areas (ui-dialog-areas x y w h '())]
           [t (cdr (assq 'title areas))] [m (cdr (assq 'message areas))]
           [lh (font-line-height 'ui)])
      (draw-shadow x y w h 18 16)
      (fill-box x y w h 'adwaita-dialog 18)
      (stroke-box x y w h (alpha #xffffff 0.07) 1 18)
      (text-draw-centered (car t) (cadr t) (caddr t) (cadddr t)
                          (text-fit title (caddr t) 'heading) 'text 'heading)
      (fold-left (lambda (ly line)
                   (draw-text (+ (car m) (/ (- (caddr m) (text-width line 'ui))
                                            2))
                              ly line 'text 'ui)
                   (+ ly lh))
                 (cadr m) (ui-dialog-lines message (caddr m)))))

  ;; Under a dialog, the shade at twice its alpha (widgets/_dialogs.scss:
  ;; 72-74).
  (define (adwaita-scrim x y w h flags) (fill-box x y w h 'adwaita-dim))

  ;; The calendar (widgets/_calendar.scss) in a popover: its month bold,
  ;; the days of the week dimmed.
  (define (adwaita-calendar x y w h flags title)
    (let* ([areas (ui-calendar-areas x y w h)]
           [t (cdr (assq 'title areas))] [wk (cdr (assq 'week areas))]
           [cell (/ (caddr wk) 7)])
      (ui-draw-panel x y w h '())
      (apply text-draw-centered (append t (list title 'text 'ui-bold)))
      (do ([i 0 (+ i 1)]) ((= i 7))
        (text-draw-centered (+ (car wk) (* i cell)) (cadr wk) cell (cadddr wk)
                            (string (string-ref "MTWTFSS" i)) 'text-dim
                            'ui-small))))

  ;; A day (widgets/_calendar.scss:21-56): chosen, the accent, its number
  ;; white, 9 round; today, a line 2 high of the border color under it;
  ;; another month's at 30 %; under the pointer 7 %, the keys' ringed.
  (define (adwaita-day x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [s (- (min w h) 4)]
           [cx (+ x (/ (- w s) 2))] [cy (+ y (/ (- h s) 2))])
      (cond [(on? 'selected) (fill-box cx cy s s 'accent 9)]
            [(on? 'hover) (fill-box cx cy s s (alpha 'text 0.07) 9)])
      (when (and (on? 'today) (not (on? 'selected)))
        (fill-box (+ cx 4) (+ cy s -2) (- s 8) 2 (alpha 'text 0.15)))
      (when (on? 'cursor) (adwaita-ring cx cy s s 9))
      (text-draw-centered x y w h label
                          (cond [(on? 'selected) #xffffff]
                                [(on? 'outside) (alpha 'text 0.3)]
                                [else 'text])
                          'ui)))

  ;; A person (AdwAvatar: widgets/_avatar.scss:1-38): round, shaded down
  ;; between two of fourteen colors, its initials bold in a third; which of
  ;; them, by the name.
  (define adwaita-avatar-colors
    '#((#xcfe1f5 #x83b6ec #x337fdc)
       (#xcaeaf2 #x7ad9f1 #x0f9ac8)
       (#xcef8d8 #x8de6b1 #x29ae74)
       (#xe6f9d7 #xb5e98a #x6ab85b)
       (#xf9f4e1 #xf8e359 #xd29d09)
       (#xffead1 #xffcb62 #xd68400)
       (#xffe5c5 #xffa95a #xed5b00)
       (#xf8d2ce #xf78773 #xe62d42)
       (#xfac7de #xe973ab #xe33b6a)
       (#xe7c2e8 #xcb78d4 #x9945b5)
       (#xd5d2f5 #x9e91e8 #x7a59ca)
       (#xf2eade #xe3cf9c #xb08952)
       (#xe5d6ca #xbe916d #x785336)
       (#xd8d7d3 #xc0bfbc #x6e6d71)))

  ;; The same for a name however it was typed: spaces around it and
  ;; capitals aside.
  (define (adwaita-avatar-index name)
    (mod (fold-left (lambda (h c)
                      (if (char-whitespace? c)
                          h
                          (mod (+ (* 31 h) (char->integer c)) 1000003)))
                    7 (string->list (string-downcase name)))
         (vector-length adwaita-avatar-colors)))

  (define (adwaita-avatar x y w h flags name)
    (let ([c (vector-ref adwaita-avatar-colors (adwaita-avatar-index name))])
      (fill-box x y w w (linear-gradient 0 y 0 (+ y w) (cadr c) (caddr c))
                (/ w 2))
      (text-draw-centered x y w w (ui-initials name) (car c) 'ui-small-bold)))

  ;; The spinner (AdwSpinner: adw-spinner-paintable.c:18-35, 288-374): a
  ;; ring of the text at 15 % and an arc of it, round at its ends, going
  ;; round once in 1.2 s, its length growing and shrinking; 2.5 wide at a
  ;; radius of 8, 7 at 32, between in proportion.
  (define (adwaita-busy x y w h flags ms)
    (let* ([r (min 32 (/ (min w h) 2))]
           [lw (+ 2.5 (* 4.5 (clamp (/ (- r 8) 24) 0 1)))]
           [rr (- r (/ lw 2))] [cx (+ x (/ w 2))] [cy (+ y (/ h 2))]
           [a0 (+ (* 2 pi (/ (mod ms 1200) 1200.0)) (* 0.35 pi))]
           [len (* pi (+ 0.5 (* 0.4 (sin (* 2 pi (/ (mod ms 2400) 2400.0))))))])
      (stroke-circle cx cy rr (alpha 'text 0.15) lw)
      (draw-polyline (map (lambda (i)
                            (let ([a (+ a0 (* len (/ i 15)))])
                              (cons (+ cx (* rr (cos a)))
                                    (+ cy (* rr (sin a))))))
                          (iota 16))
                     'text lw)))

  ;; A navigation sidebar's row (widgets/_sidebars.scss:92-163): 6 in from
  ;; the sides, 9 round; chosen, the text at 10 % (13 % under the pointer),
  ;; another under the pointer 7 %; its icon 8 in, its label 12 after.
  (define (adwaita-nav-row x y w h flags label icon)
    (let* ([on? (lambda (f) (memq f flags))] [rx (+ x 6)] [rw (- w 12)]
           [g (ui-glyph-size)] [ix (+ rx 8)] [lx (if icon (+ ix g 12) ix)]
           [lh (font-line-height 'ui)])
      (cond [(on? 'selected)
             (fill-box rx y rw h (alpha 'text (if (on? 'hover) 0.13 0.1)) 9)]
            [(on? 'hover) (fill-box rx y rw h (alpha 'text 0.07) 9)])
      (when icon (icon ix (+ y (/ (- h g) 2)) g flags))
      (draw-text lx (+ y (/ (- h lh) 2))
                 (text-fit label (max 0 (- (+ rx rw) lx 8)) 'ui) 'text 'ui)
      (when (on? 'focused) (adwaita-ring rx y rw h 9))))

  ;; Whether a view is live, a pill as a toggle group's (widgets/
  ;; _toggle-group.scss:12-14): the text at 10 %, 15 % under the pointer;
  ;; live, the accent's dot before Live; held, the pause mark, and the way
  ;; back in the accent.
  (define (adwaita-live-badge x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [live? (on? 'checked)]
           [lh (font-line-height 'ui-small)] [m (ui-live-badge-mark)]
           [ty (+ y (/ (- h lh) 2))] [my (+ y (/ (- h m) 2))]
           [tx (+ x 8 m 6)]
           [back (if live? 0 (text-width ui-live-badge-back 'ui-small))]
           [label (text-fit label (max 0 (- (+ x w) tx back 10)) 'ui-small)])
      (fill-box x y w h
                (alpha 'text (if (or (on? 'hover) (on? 'pressed)) 0.15 0.1))
                (/ h 2))
      (if live?
          (fill-circle (+ x 8 (/ m 2)) (+ y (/ h 2)) (/ m 2) 'accent)
          (let ([bw (max 1 (quotient m 3))])
            (fill-box (+ x 8) my bw m 'text-dim)
            (fill-box (+ x 8 (- m bw)) my bw m 'text-dim)))
      (draw-text tx ty label 'text 'ui-small)
      (unless live?
        (draw-text (+ tx (text-width label 'ui-small)) ty ui-live-badge-back
                   'adwaita-link 'ui-small))
      (when (on? 'focused) (adwaita-ring x y w h (/ h 2)))))

  ;; A suggestion is a menu item (widgets/_menus.scss:130-144).
  (define (adwaita-suggestion x y w h flags label)
    (let ([on? (or (memq 'selected flags) (memq 'hover flags))])
      (when on? (fill-box x y w h (alpha 'text 0.1) 9))
      (draw-text (+ x 12) (+ y (/ (- h (font-line-height 'ui)) 2))
                 (text-fit label (max 0 (- w 24)) 'ui) 'text 'ui)))

  ;; The line between two panes, where a drag moves it: under the pointer a
  ;; line of the text at 30 %, dragged the accent's (a paned's handle,
  ;; widgets/_paned.scss).
  (define (adwaita-split x y h flags)
    (cond [(memq 'pressed flags) (fill-box x y 1 h 'adwaita-link)]
          [(memq 'hover flags) (fill-box x y 1 h (alpha 'text 0.3))]))

  ;;; ------------------------------------------------------------------
  ;;; boxed lists, status pages and banners

  ;; A preferences group (widgets/_preferences.scss:6-18): its title a
  ;; heading, its description dimmed, 6 apart, the list 12 under them.
  (define (adwaita-rows-spacing) (values 6 12))

  ;; An action row (widgets/_lists.scss:118-163): at least 50 high, its
  ;; title and subtitle 6 from its top and bottom, 3 apart.
  (define (adwaita-row-height title subtitle)
    (max 50 (round (+ 12 (font-line-height 'ui)
                      (if subtitle (+ 3 (font-line-height 'ui-small)) 0)))))

  ;; 12 in from the sides, 6 between what it holds, a prefix 6 more from
  ;; the title (widgets/_lists.scss:124-163).
  (define (adwaita-row-areas x y w h pw sw)
    (let* ([tx (if (> pw 0) (+ x 12 pw 12) (+ x 12))]
           [sx (- (+ x w) 12 sw)]
           [te (if (> sw 0) (- sx 6) (- (+ x w) 12))])
      (list (list 'prefix (+ x 12) y pw h)
            (list 'title tx y (max 0 (- te tx)) h)
            (list 'suffix sx y sw h))))

  (define (adwaita-rows-radius) 12)

  ;; A boxed list is a card (widgets/_lists.scss:507-541, _misc.scss:
  ;; 194-201): the card's color, 12 round, over two soft shadows, in its
  ;; hairline, rgb(0 0 6 / 3%).
  (define (adwaita-rows x y w h flags)
    (if (memq 'over flags)
        (stroke-box x y w h (alpha #x000006 0.03) 1 12)
        (begin (draw-shadow x y w h 12 4)
               (fill-box x y w h 'adwaita-card 12))))

  ;; A row of it (widgets/_lists.scss:118-122, 334-352, 528-538): if a press
  ;; acts, under the pointer the text at 3 %, pressed 8 %; chosen, the
  ;; accent at 25 %; a line of the card's shade under each but the last;
  ;; its title in the text's color, its subtitle smaller and dimmed;
  ;; focused, the ring a pixel in.
  (define (adwaita-row x y w h flags title subtitle tx tw)
    (let* ([on? (lambda (f) (memq f flags))]
           [lh (font-line-height 'ui)] [sh (font-line-height 'ui-small)]
           [th (if subtitle (+ lh 3 sh) lh)] [ty (+ y (/ (- h th) 2))]
           [ink (lambda (c) (if (on? 'disabled) (alpha c 0.5) c))])
      (cond [(on? 'selected) (fill-box x y w h (alpha 'accent 0.25))]
            [(and (on? 'activatable) (on? 'pressed))
             (fill-box x y w h (alpha 'text 0.08))]
            [(and (on? 'activatable) (on? 'hover))
             (fill-box x y w h (alpha 'text 0.03))])
      (unless (on? 'last)
        (fill-box x (+ y h -1) w 1 'adwaita-card-shade))
      (when title
        (draw-text tx ty (text-fit title tw 'ui) (ink 'text) 'ui))
      (when subtitle
        (draw-text tx (+ ty lh 3) (text-fit subtitle tw 'ui-small)
                   (ink 'text-dim) 'ui-small))
      (when (on? 'focused)
        (adwaita-ring (+ x 1) (+ y 1) (- w 2) (- h 2) 11))))

  ;; A status page's title: .title-1, .title-2 compact (widgets/
  ;; _misc.scss:147-149, 166-168).
  (define (adwaita-status-title-font flags)
    (if (memq 'compact flags) 'heading 'adwaita-title-1))

  ;; A status page (widgets/_misc.scss:122-190): its icon 128 square (96
  ;; compact), 36 over the title (its 24 margin and the 12 between, 24 and
  ;; 12 compact), the description 12 under the title, the button 36 under
  ;; them (24 compact), the text 12 in from the sides.
  (define (adwaita-status-page-areas x y w h flags title description label)
    (let*-values ([(compact?) (memq 'compact flags)]
                  [(s) (if compact? 96 128)]
                  [(gap) (if compact? 24 36)]
                  [(tw) (max 0 (- w 24))]
                  [(tf) (adwaita-status-title-font flags)]
                  [(th) (* (font-line-height tf)
                           (length (ui-label-lines title tw tf)))]
                  [(dh) (if description
                            (* (font-line-height 'ui)
                               (length (ui-label-lines description tw 'ui)))
                            0)]
                  [(bw bh) (if label
                               (let-values ([(bw bh) (adwaita-button-size
                                                      label #f)])
                                 (values (+ bw 30) (+ bh 10)))
                               (values 0 0))]
                  [(total) (+ s gap th (if description (+ 12 dh) 0)
                              (if label (+ gap bh) 0))]
                  [(top) (+ y (max 0 (/ (- h total) 2)))]
                  [(ty) (+ top s gap)]
                  [(dy) (+ ty th 12)]
                  [(by) (+ (if description (+ dy dh) (+ ty th)) gap)])
      (list (list 'glyph (+ x (/ (- w s) 2)) top s s)
            (list 'title (+ x 12) ty tw th)
            (list 'description (+ x 12) dy tw dh)
            (list 'button (+ x (/ (- w bw) 2)) by bw bh))))

  ;; Its icon the text at 55 % (widgets/_misc.scss:134-136), the title and
  ;; the description centered.
  (define (adwaita-status-page x y w h flags glyph title description label)
    (let* ([areas (ui-status-page-areas x y w h flags title description
                                        label)]
           [g (cdr (assq 'glyph areas))] [t (cdr (assq 'title areas))]
           [d (cdr (assq 'description areas))] [s (caddr g)]
           [tf (adwaita-status-title-font flags)])
      (if (procedure? glyph)
          (glyph (car g) (cadr g) s '(dim))
          (ui-draw-glyph (car g) (cadr g) s s '((ink . text-dim)) glyph))
      (fold-left (lambda (ly line)
                   (draw-text (+ (car t) (/ (- (caddr t) (text-width line tf))
                                            2))
                              ly line 'text tf)
                   (+ ly (font-line-height tf)))
                 (cadr t) (ui-label-lines title (caddr t) tf))
      (when description
        (fold-left (lambda (ly line)
                     (draw-text (+ (car d) (/ (- (caddr d)
                                                 (text-width line 'ui))
                                              2))
                                ly line 'text 'ui)
                     (+ ly (font-line-height 'ui)))
                   (cadr d) (ui-label-lines description (caddr d) 'ui)))))

  ;; A banner (AdwBanner: widgets/_toolbars.scss:235-254): its button 6
  ;; inside it, so it is a control and 12 high; #7d7d83 mixed 30 % into the
  ;; window's color, its title a heading.
  (define (adwaita-banner-height) (+ 12 (ui-control-height)))

  (define (adwaita-banner x y w h flags title label)
    (let ([t (cdr (assq 'title (ui-banner-areas x y w h title label)))])
      (fill-box x y w h (mix 'bg-1 #x7d7d83 0.3))
      (draw-text (car t) (+ y (/ (- h (font-line-height 'ui-bold)) 2))
                 (text-fit title (caddr t) 'ui-bold) 'text 'ui-bold)))

  ;;; ------------------------------------------------------------------
  ;;; the top bar: GNOME Shell's panel

  ;; The Activities button (shell widgets/_panel.scss:21-24, 49-61): a pill
  ;; 3 inside the bar (_drawing.scss:393-407), 12 either side of its
  ;; workspace dots, which sit 3 in and 5 apart: two of them, the current
  ;; workspace's 3.625 times a dot's 8 (js/ui/panel.js:392-408), the next
  ;; one's a dot.
  (define (adwaita-activities-width) (+ 3 12 3 29 5 8 3 12 3))

  (define (adwaita-topbar-areas)
    (list (list 'launcher 0 0 (adwaita-activities-width) (topbar-height))))

  ;; The clock as GNOME shows it by default, the month, the day and the
  ;; time (org.gnome.desktop.interface clock-show-date, clock-format).
  (define (adwaita-clock-text)
    (let ([d (current-date)])
      (format "~a ~a  ~2,'0d:~2,'0d"
              (vector-ref '#("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug"
                             "Sep" "Oct" "Nov" "Dec")
                          (- (date-month d) 1))
              (date-day d) (date-hour d) (date-minute d))))

  ;; The status the right of the bar shows, the system's place: every
  ;; segment but the clock, which the middle has; or, where the style shows
  ;; it, what the mouse buttons do.
  (define (adwaita-status-strings)
    (if (theme 'mouse-doc)
        (list (mouse-doc-text (mouse-doc)))
        (filter-map (lambda (s) (and (not (eq? (car s) 'clock)) (cdr s)))
                    *status-shown*)))

  ;; GNOME Shell's panel (shell widgets/_panel.scss:13-17): 2.2 em high,
  ;; black (_colors.scss:24), its text bold and white; Activities at its
  ;; left, the text at 17 % behind it under the pointer, 28 % while the
  ;; apps are open (_drawing.scss:393-437), the current workspace's dot
  ;; white, the next one's at three quarters its size and half its strength
  ;; (js/ui/panel.js:50, 297-302); the clock in its middle; the status at
  ;; its right, 12 from the end.
  (define (adwaita-draw-topbar)
    (with-place 'bar
      (lambda ()
        (let* ([w (screen-w)] [h (topbar-height)] [f 'ui-bold]
               [ty (/ (- h (font-line-height f)) 2)] [cy (/ h 2)]
               [l (cdr (assq 'launcher (topbar-areas)))]
               [lx (car l)] [lw (caddr l)]
               [open? (launcher-open?)]
               [clock (adwaita-clock-text)]
               [cw (text-width clock f)] [cx (/ (- w cw) 2)])
          (fill-box 0 0 w h 'panel)
          (when (or open? (equal? *hover* '(surface topbar launcher)))
            (fill-box (+ lx 3) 3 (- lw 6) (- h 6)
                      (alpha 'panel-text (if open? 0.28 0.17)) (/ (- h 6) 2)))
          (let ([dx (+ lx 3 12 3)])
            (fill-box dx (- cy 4) 29 8 'panel-text 4)
            (fill-circle (+ dx 29 5 4) cy 3 (alpha 'panel-text 0.5)))
          (draw-text cx ty clock 'panel-text f)
          (let loop ([ss (reverse (adwaita-status-strings))] [x (- w 12)])
            (unless (null? ss)
              (let ([x0 (- x (text-width (car ss) f))])
                (when (> x0 (+ cx cw 24))
                  (draw-text x0 ty (car ss) 'panel-text f)
                  (loop (cdr ss) (- x0 18))))))))))

  ;;; ------------------------------------------------------------------
  ;;; the dash

  ;; GNOME has no taskbar; its designers' dock is the dash the overview
  ;; shows (shell widgets/_dash.scss), so the windows are a dash floating
  ;; at the bottom, in proportion to a bar's room: 6 from the screen's
  ;; edge (12 at the overview's size, 8), its color the system's overlay
  ;; (4, _colors.scss:49), 6 inside it a tile a window, 2 apart (19-25,
  ;; 49-55), 12 round, a tile's 6 round its icon; its corners the tiles'
  ;; and its padding (9); after a line, Show Apps (83-93). => (values the
  ;; dash's height, a tile's side, an icon's)
  (define (adwaita-dash-sizes)
    (let* ([bh (- (taskbar-height) 12)] [t (- bh 12)])
      (values bh t (- t 12))))

  ;; ((launcher x y w h) (window x y w h) ...): the tiles, centered.
  (define (adwaita-taskbar-areas)
    (let*-values ([(bh t icon) (adwaita-dash-sizes)]
                  [(ws) (sort (lambda (a b) (< (window-id a) (window-id b)))
                              *windows*)]
                  [(n) (length ws)]
                  [(room) (- (screen-w) 24 4 13 (+ t 4) 4)]
                  [(pitch) (if (zero? n) (+ t 4) (min (+ t 4) (/ room n)))]
                  [(dw) (+ 4 (* n pitch) (if (zero? n) 0 9) (+ t 4) 4)]
                  [(x0) (floor (/ (- (screen-w) dw) 2))]
                  [(ty) (+ (- (screen-h) (taskbar-height)) 6 6)])
      (cons (list 'launcher (- (+ x0 dw) 6 t) ty t t)
            (map (lambda (win i) (list win (+ x0 4 2 (* i pitch)) ty
                                       (- pitch 4) t))
                 ws (iota n)))))

  ;; A window's icon, its app's where the app gives one (dimmed while it is
  ;; minimized), else its title's first letter on its app's color.
  (define (adwaita-dash-icon win x y s shown?)
    (let ([icon (ui-title-icon win)])
      (if icon
          (icon x y s (if shown? '() '(dim)))
          (let ([title (window-title win)]
                [c (app-color (window-app win))])
            (fill-box x y s s (if shown? c (alpha c 0.5)) (/ s 4))
            (unless (string=? title "")
              (text-draw-centered x y s s
                                  (string (char-upcase (string-ref title 0)))
                                  (if shown? #xffffff (alpha #xffffff 0.5))
                                  'ui-bold))))))

  ;; The dash: its box, the tiles lighter under the pointer and the focused
  ;; window's (shell widgets/_dash.scss:57-68), a dot 5 across under each
  ;; (_app-grid.scss:45-51); the line of white at 10 % (83-87), and Show
  ;; Apps, its grid of nine.
  (define (adwaita-draw-taskbar)
    (with-place 'bar
      (lambda ()
        (let*-values ([(bh t icon) (adwaita-dash-sizes)]
                      [(areas) (taskbar-areas)]
                      [(l) (cdr (assq 'launcher areas))]
                      [(wins) (filter (lambda (a) (window? (car a))) areas)]
                      [(y0) (+ (- (screen-h) (taskbar-height)) 6)]
                      [(x0) (- (if (null? wins) (car l) (cadr (car wins)))
                               6)]
                      [(x1) (+ (car l) t 6)])
          (fill-box x0 y0 (- x1 x0) bh 'adwaita-dash (+ 12 6))
          (for-each
           (lambda (a)
             (let* ([win (car a)] [x (cadr a)] [y (caddr a)] [tw (cadddr a)]
                    [hover? (equal? *hover* (list 'surface 'taskbar win))]
                    [focused? (eq? win *focus*)]
                    [ix (+ x (/ (- tw icon) 2))])
               (when (or hover? focused?)
                 (fill-box x y tw t
                           (if hover? 'adwaita-dash-hover 'adwaita-dash-checked)
                           12))
               (adwaita-dash-icon win ix (+ y 6) icon (visible? win))
               (fill-circle (+ x (/ tw 2)) (+ y t 3) 2.5
                            (if (visible? win)
                                'adwaita-dash-text
                                (alpha 'adwaita-dash-text 0.5)))))
           wins)
          (unless (null? wins)
            (fill-box (- (car l) 6 1) (+ y0 12) 1 (- bh 24)
                      (alpha 'adwaita-dash-text 0.1)))
          (when (or (launcher-open?)
                    (equal? *hover* '(surface taskbar launcher)))
            (fill-box (car l) (cadr l) t t 'adwaita-dash-hover 12))
          (let ([gx (+ (car l) (/ (- t 16) 2))]
                [gy (+ (cadr l) (/ (- t 16) 2))])
            (do ([i 0 (+ i 1)]) ((= i 9))
              (fill-box (+ gx (* 6 (mod i 3))) (+ gy (* 6 (quotient i 3))) 4 4
                        'adwaita-dash-text 1)))))))

  ;;; ------------------------------------------------------------------
  ;;; notifications: GNOME Shell's banners

  ;; The world's notices are the desktop's, not a window's, as the Shell's
  ;; are: so they are its banners (shell widgets/_notifications.scss,
  ;; _message-list.scss), at the top in the middle under the bar, 34 em
  ;; wide and at least 64 high (3-12), 8 apart. => (#(x y w h text color)
  ;; ...)
  (define (adwaita-toast-boxes)
    (let* ([bw (min (round (* 34 (adwaita-em))) (- (screen-w) 24))]
           [h (max 64 (round (+ 42 (font-line-height 'ui))))])
      (let-values ([(dx dy dw dh) (desktop-rect)])
        (let loop ([ts *toasts*] [y (+ dy 6)] [acc '()])
          (if (null? ts)
              (reverse acc)
              (let ([t (car ts)])
                (loop (cdr ts) (+ y h 8)
                      (cons (vector (+ dx (floor (/ (- dw bw) 2))) y bw h
                                    (text-fit (vector-ref t 1) (- bw 24) 'ui)
                                    (vector-ref t 2))
                            acc))))))))

  ;; A banner: a card 16 round, #54545a in the Shell's dark style, over its
  ;; shadow (shell widgets/_notifications.scss:7-12, _message-list.scss:
  ;; 88-94), 6 inside it; its header, 24 high, the source dimmed, its icon
  ;; 16 across, a dot of the notice's color, and Schevana bold (108-133);
  ;; under it the notice.
  (define (adwaita-draw-toasts)
    (with-place 'toast
      (lambda ()
        (let ([lh (font-line-height 'ui)])
          (for-each
           (lambda (b)
             (let ([x (vector-ref b 0)] [y (vector-ref b 1)]
                   [w (vector-ref b 2)] [h (vector-ref b 3)])
               (draw-shadow x y w h 16 8)
               (fill-box x y w h 'adwaita-shell-card 16)
               (fill-circle (+ x 12 8) (+ y 6 12) 7 (vector-ref b 5))
               (draw-text (+ x 12 16 6) (+ y 6 (/ (- 24 lh) 2)) "Schevana"
                          'adwaita-shell-dim 'ui-bold)
               (draw-text (+ x 12) (+ y 6 24 6) (vector-ref b 4)
                          'adwaita-shell-text 'ui)))
           (toast-boxes))))))

  ;;; ------------------------------------------------------------------
  ;;; menus

  ;; The desktop's own menus, the launcher and a window's, are GNOME
  ;; Shell's popup menus; the rest (a dropdown's) libadwaita's popovers.
  (define (adwaita-shell-menu? m)
    (let ([t (menu-tag m)])
      (or (eq? t 'launcher) (and (pair? t) (eq? (car t) 'window)))))

  ;; The current choice of a dropdown's menu, which the kit marks with a
  ;; check after its label: (values the label, and whether it is chosen),
  ;; the check a glyph at the item's end, as GTK's dropdown has it
  ;; (widgets/_dropdowns.scss:22-37).
  (define (adwaita-menu-choice text)
    (if (string-suffix? "  ✓" text)
        (values (substring text 0 (- (string-length text) 3)) #t)
        (values text #f)))

  ;; An item's text, its check, and the key that does the same, wide.
  (define (adwaita-menu-label-width label)
    (let-values ([(text chosen?) (adwaita-menu-choice
                                  (menu-label-text label))])
      (+ (text-width text 'ui)
         (if chosen? (+ 12 (ui-glyph-size)) 0)
         (let ([key (menu-label-key label)])
           (if key (+ 24 (text-width key 'ui)) 0)))))

  ;; A Shell menu (shell widgets/_popovers.scss:15-33): 6 inside it, at
  ;; least 15 em wide, an item its text and 9 above and below it, 12
  ;; beside it (_common.scss:131-136). A popover menu (widgets/_menus.scss):
  ;; 6 inside it (58-66), at least 120 wide (1-4), its items 32 high, 12 in
  ;; (130-134); a line 6 from what is above and below it (68-70). The
  ;; filter's field over the items.
  (define (adwaita-menu-areas m)
    (let* ([shell? (adwaita-shell-menu? m)] [es (menu-entries m)]
           [ih (if shell? (round (+ (font-line-height 'ui) 18)) 32)]
           [sh 13] [pad 6] [tx 12]
           [head (if (menu-filter? m) (+ (ui-control-height) pad) 0)]
           [w (fold-left (lambda (acc e)
                           (if (pair? e)
                               (max acc (+ pad tx (adwaita-menu-label-width
                                                   (car e))
                                           tx pad))
                               acc))
                         (if shell? (round (* 15 (adwaita-em))) 120) es)]
           [h (fold-left (lambda (acc e) (+ acc (if (pair? e) ih sh)))
                         (+ pad pad head) es)]
           [x (clamp (menu-x m) 4 (max 4 (- (screen-w) w 4)))]
           [y (let-values ([(dx dy dw dh) (desktop-rect)])
                (clamp (menu-y m) (+ 2 dy) (max (+ 2 dy) (- (screen-h) h 4))))])
      (cons (list 'menu x y w h)
            (append (if (menu-filter? m)
                        (list (list 'filter (+ x pad) (+ y pad) (- w pad pad)
                                    (ui-control-height)))
                        '())
                    (let loop ([es es] [i 0] [ey (+ y pad head)])
                      (if (null? es)
                          '()
                          (let ([eh (if (pair? (car es)) ih sh)])
                            (cons (list (if (pair? (car es)) i 'separator)
                                        x ey w eh)
                                  (loop (cdr es) (+ i 1) (+ ey eh))))))))))

  ;; A Shell menu's box: #36363a in a hairline of #424247, 20 round, over a
  ;; shadow (shell widgets/_popovers.scss:27-33).
  (define (adwaita-shell-panel x y w h)
    (draw-shadow x y w h 20 6)
    (fill-box x y w h 'adwaita-shell-bg 20)
    (stroke-box x y w h 'adwaita-shell-border 1 20))

  ;; The filter: an entry, what is typed in it, or a hint dimmed.
  (define (adwaita-menu-filter m x y w h shell?)
    (let* ([f (menu-filter m)] [lh (font-line-height 'ui)]
           [ink (if shell? 'adwaita-shell-text 'text)]
           [ty (+ y (/ (- h lh) 2))])
      (fill-box x y w h (alpha ink 0.1) 9)
      (adwaita-ring x y w h 9)
      (if (string=? f "")
          (draw-text (+ x 9) ty "Type to filter…"
                     (if shell? 'adwaita-shell-dim 'text-dim) 'ui)
          (with-clip (x y w h)
            (let ([ex (draw-text (min (+ x 9) (- (+ x w) 10 (text-width f 'ui)))
                                 ty f ink 'ui)])
              (fill-box ex ty 1 lh ink))))))

  ;; Its items: the chosen one (the keys' or the pointer's) lighter, in
  ;; the Shell's 12 round (shell widgets/_popovers.scss:36-39), the
  ;; popover's the text at 10 %, 9 round, 19 % held; a key that does the
  ;; same dimmed at the right (widgets/_menus.scss:76-81).
  (define (adwaita-draw-menu)
    (when *menu*
      (with-place 'menu
        (lambda ()
          (let* ([m *menu*] [shell? (adwaita-shell-menu? m)]
                 [areas (menu-areas m)] [es (list->vector (menu-entries m))]
                 [lh (font-line-height 'ui)] [b *menu-blink*]
                 [ink (if shell? 'adwaita-shell-text 'text)]
                 [dim (if shell? 'adwaita-shell-dim 'text-dim)]
                 [f (assq 'filter areas)])
            (apply (lambda (x y w h)
                     (if shell?
                         (adwaita-shell-panel x y w h)
                         (ui-draw-panel x y w h '(menu))))
                   (cdar areas))
            (when f
              (apply (lambda (fx fy fw fh)
                       (adwaita-menu-filter m fx fy fw fh shell?))
                     (cdr f)))
            (for-each
             (lambda (a)
               (apply
                (lambda (what x y w h)
                  (cond
                    [(eq? what 'separator)
                     (fill-box (+ x 6) (+ y (quotient h 2)) (- w 12) 1
                               (alpha ink (if shell? 0.1 0.15)))]
                    [(fixnum? what)
                     (let* ([sel? (if b
                                      (and (= what (cadr b))
                                           (odd? (menu-phase b)))
                                      (= what (menu-sel m)))]
                            [held? (and sel? (memq 'pressed
                                                   (menu-entry-flags what)))]
                            [label (car (vector-ref es what))]
                            [key (menu-label-key label)]
                            [g (ui-glyph-size)]
                            [ty (+ y (/ (- h lh) 2))])
                       (when sel?
                         (if shell?
                             (fill-box (+ x 6) y (- w 12) h
                                       (if held? 'adwaita-shell-pressed
                                           'adwaita-shell-hover)
                                       12)
                             (fill-box (+ x 6) y (- w 12) h
                                       (alpha 'text (if held? 0.19 0.1)) 9)))
                       (let-values ([(text chosen?)
                                     (adwaita-menu-choice
                                      (menu-label-text label))])
                         (draw-text (+ x 18) ty
                                    (text-fit text
                                              (max 0
                                                   (- w 36
                                                      (if key
                                                          (+ 12 (text-width
                                                                 key 'ui))
                                                          0)
                                                      (if chosen? (+ 12 g) 0)))
                                              'ui)
                                    ink 'ui)
                         (when chosen?
                           (ui-draw-glyph (- (+ x w) 18 g) (+ y (/ (- h g) 2))
                                          g g (list (cons 'ink ink)) 'check)))
                       (when key
                         (draw-text (- (+ x w) 18 (text-width key 'ui)) ty key
                                    dim 'ui)))]))
                a))
             (cdr areas)))))))

  ;;; ------------------------------------------------------------------
  ;;; the desktop

  ;; After GNOME 48's default wallpaper, the Adwaita one's blue shapes
  ;; (gnome-backgrounds 48; facts only, no image): the desktop's colors
  ;; shading down, and over them three great circles, darker and lighter,
  ;; which the screen's edges cut; another wallpaper alone.
  (define (adwaita-draw-wallpaper w h)
    (fill-wallpaper 0 0 w h (theme 'wallpaper) 'desktop-top 'desktop-bottom)
    (when (eq? (theme 'wallpaper) 'gradient)
      (let ([s (max w h)])
        (fill-circle (* w 0.1) (* h 1.15) (* s 0.55)
                     (alpha (mix 'desktop-bottom #x000000 0.3) 0.45))
        (fill-circle (* w 0.96) (* h -0.1) (* s 0.42)
                     (alpha (mix 'desktop-top #xffffff 0.35) 0.3))
        (fill-circle (* w 0.72) (* h 1.05) (* s 0.36)
                     (alpha (mix 'desktop-top 'desktop-bottom 0.4) 0.55)))))

  ;;; ------------------------------------------------------------------

  (at-load
   (define-style adwaita "Adwaita"
     'options '(palette
                (palette-dark "Dark palette" palette)
                accent
                wallpaper
                ui-font
                ui-font-size
                mono-font
                mono-font-size
                shadow
                (adwaita-header "Header bar" (("Flat" . flat)
                                              ("Raised" . raised)))
                (adwaita-window-buttons "Window buttons"
                                        (("Close" . close)
                                         ("All three" . all))))
     'palette 'adwaita
     'palette-dark 'adwaita-dark
     'wallpaper 'gradient
     ;; GNOME's text, this machine's: Cantarell 11, 15 here (adwaita-em);
     ;; a caption 82 % (widgets/_labels.scss:63-71)
     'ui-font "Cantarell"
     'ui-font-size 15
     'mono-font "monospace"
     'mono-font-size 15
     'ui-small (theme-font-rule 'ui -3)
     'ui-small-bold (theme-font-rule 'ui -3 'bold)
     'corner-radius 15
     'shadow 24
     ;; a control's text and 5 above and below it, 34 at least (widgets/
     ;; _buttons.scss:20-22)
     'control-height (theme-rule (+ 10 (max 24 (round (font-line-height
                                                        'ui)))))
     'title-height (theme-rule (adwaita-header-height))
     'topbar-height (theme-rule (max 32 (round (* 2.2 (adwaita-em)))))
     'taskbar-height 64
     'glyph-size 16
     'small-glyph-size 12
     ;; GNOME spaces by 6 between neighbors, 12 in from a box's edge
     'gap 6
     'pad 12
     'slider-height (theme-rule (theme 'control-height))
     'progress-height 8
     'segmented-gap 0
     'stepper-glyphs '(minus . plus)
     'scrollbar-width 16
     'scrollbar-show 'hover
     'surface-well-ring 1
     ;; a column view's heading a caption and 3 above and below; a cell's
     ;; text and 8 (widgets/_column-view.scss:12-20, 72-79)
     'table-header-height (theme-rule (round (+ 8 (font-line-height
                                                   'ui-small-bold))))
     'table-row-height (theme-rule (round (+ 16 (font-line-height 'ui))))
     'table-dividers 'handle
     'label-section-font 'ui-bold
     'label-section-upcase #f
     'label-group-font 'ui-bold
     'text-caret-width 1
     'text-caret-color 'text
     'text-placeholder-color 'text-dim
     'status-title-font 'adwaita-title-1
     'busy-frame-ms 50
     'title-double-click 'maximize
     'places '((dialog adwaita-button-radius 12))
     ;; the window
     'frame-insets 'adwaita-insets
     'frame-regions 'adwaita-regions
     'frame-radius 'adwaita-radius
     'frame-under 'adwaita-draw-under
     'frame-over 'adwaita-draw-over
     ;; the desktop
     'draw-topbar 'adwaita-draw-topbar
     'topbar-areas 'adwaita-topbar-areas
     'taskbar-areas 'adwaita-taskbar-areas
     'draw-taskbar 'adwaita-draw-taskbar
     'toast-boxes 'adwaita-toast-boxes
     'draw-toasts 'adwaita-draw-toasts
     'menu-areas 'adwaita-menu-areas
     'draw-menu 'adwaita-draw-menu
     'draw-wallpaper 'adwaita-draw-wallpaper
     ;; the widgets
     'ui-draw-focus 'adwaita-focus
     'ui-draw-field 'adwaita-field
     'ui-draw-button 'adwaita-button
     'ui-button-size 'adwaita-button-size
     'ui-draw-nav-row 'adwaita-nav-row
     'ui-draw-slider 'adwaita-slider
     'ui-draw-checkbox 'adwaita-checkbox
     'ui-checkbox-size 'adwaita-checkbox-size
     'ui-draw-live-badge 'adwaita-live-badge
     'ui-toggle-track 'adwaita-toggle-track
     'ui-draw-toggle 'adwaita-toggle
     'ui-toggle-size 'adwaita-toggle-size
     'ui-radio-size 'adwaita-radio-size
     'ui-draw-radio 'adwaita-radio
     'ui-draw-tab 'adwaita-tab
     'ui-tabs-size 'adwaita-tabs-size
     'ui-draw-label 'adwaita-label
     'ui-draw-surface 'adwaita-surface
     'ui-text-box-areas 'adwaita-text-box-areas
     'ui-draw-suggestion 'adwaita-suggestion
     'ui-scrollbar-areas 'adwaita-scrollbar-areas
     'ui-draw-scrollbar 'adwaita-scrollbar
     'ui-draw-busy 'adwaita-busy
     'ui-draw-split 'adwaita-split
     'ui-table-cell-inset 'adwaita-table-cell-inset
     'ui-draw-table-header 'adwaita-table-header
     'ui-draw-table-divider 'adwaita-table-divider
     'ui-draw-table-row 'adwaita-table-row
     'ui-draw-chip 'adwaita-chip
     'ui-chip-size 'adwaita-chip-size
     'ui-draw-avatar 'adwaita-avatar
     'ui-draw-progress 'adwaita-progress
     'ui-draw-panel 'adwaita-panel
     'ui-draw-highlight 'adwaita-highlight
     'ui-draw-separator 'adwaita-separator
     'ui-draw-card 'adwaita-card
     'ui-card-radius 'adwaita-card-radius
     'ui-tooltip-size 'adwaita-tooltip-size
     'ui-draw-tooltip 'adwaita-tooltip
     'ui-draw-dropdown 'adwaita-dropdown
     'ui-dropdown-size 'adwaita-dropdown-size
     'ui-draw-calendar 'adwaita-calendar
     'ui-draw-day 'adwaita-day
     'ui-dialog-size 'adwaita-dialog-size
     'ui-dialog-areas 'adwaita-dialog-areas
     'ui-draw-scrim 'adwaita-scrim
     'ui-draw-dialog 'adwaita-dialog
     'ui-stepper-areas 'adwaita-stepper-areas
     'ui-rows-spacing 'adwaita-rows-spacing
     'ui-row-height 'adwaita-row-height
     'ui-row-areas 'adwaita-row-areas
     'ui-rows-radius 'adwaita-rows-radius
     'ui-draw-rows 'adwaita-rows
     'ui-draw-row 'adwaita-row
     'ui-status-page-areas 'adwaita-status-page-areas
     'ui-draw-status-page 'adwaita-status-page
     'ui-banner-height 'adwaita-banner-height
     'ui-draw-banner 'adwaita-banner)))
