;;; (schevana styles gnome) — GNOME's desktop: GNOME Shell 48.7's top bar,
;;; menus, notifications and dash, around libadwaita's windows as the Adwaita
;;; style draws them ((schevana styles adwaita), this style's parent). The
;;; Shell stays dark unless the person prefers light: a black top bar, with
;;; the Activities dots at its left and the clock in its middle. The
;;; desktop's menus are the Shell's popup menus, and a window's dropdowns are
;;; libadwaita's popovers; notifications are the Shell's banners at the top;
;;; since GNOME has no taskbar, the windows are a dash at the bottom, like
;;; the one the overview shows; and the launcher is the overview's app grid.
;;; Facts only, from GNOME Shell's stylesheet and code (GPL-2.0+), each
;;; cited as file:line: the stylesheet's under data/theme/gnome-shell-sass/,
;;; marked shell, and the code's under js/ui/; no SCSS, code, icon or image
;;; is copied.
;;;
;;; Adwaita is kept apart from this style: a program that takes Adwaita's
;;; look (a host app, (schevana kits host)) has GNOME's own Shell around its
;;; window, and this style is the Shell's part. Like every look, it imports
;;; nothing of the desktop's: the desktop's parts are handed what they draw.

(library (schevana styles gnome)
  (export
    gnome-topbar-areas gnome-draw-topbar gnome-taskbar-areas gnome-draw-taskbar
    gnome-toast-boxes gnome-draw-toasts gnome-menu-areas gnome-draw-menu
    gnome-app-grid-areas gnome-draw-app-grid gnome-draw-wallpaper)
  (import (chezscheme)
          (only (schevana base) at-load clamp filter-map library-layer
                string-suffix?)
          (only (schevana core) *focus* *hover* *toasts* *windows* alpha
                define-style desktop-rect draw-shadow draw-text fill-box
                fill-circle fill-wallpaper font-line-height mix screen-h
                screen-w stroke-box text-width theme theme-rule visible?
                wallpaper-shown window-id window? with-clip)
          (only (schevana kits menu) menu-entries menu-entry-icon
                menu-filter menu-filter? menu-icon-size menu-label-key
                menu-label-text menu-tag menu-x menu-y)
          (only (schevana kits text) text-draw-centered text-fit)
          (only (schevana kits ui) ui-control-height ui-draw-app-icon
                ui-draw-glyph ui-draw-panel ui-draw-window-icon ui-glyph-size)
          (only (schevana styles adwaita) adwaita-em adwaita-ring))

  (library-layer looks)

  ;;; ------------------------------------------------------------------
  ;;; the top bar: GNOME Shell's panel

  ;; The Activities button (shell widgets/_panel.scss:21-24, 49-61): a pill
  ;; 3 pixels inside the bar (_drawing.scss:393-407), with 12 on either side
  ;; of its workspace dots, which sit 3 in and 5 apart. There are two: the
  ;; current workspace's is 3.625 times a dot's 8 (js/ui/panel.js:392-408),
  ;; and the next one's is a dot.
  (define (gnome-activities-width) (+ 3 12 3 29 5 8 3 12 3))

  (define (gnome-topbar-areas h)
    (list (list 'launcher 0 0 (gnome-activities-width) h)))

  ;; The clock as GNOME shows it by default: the month, the day and the
  ;; time (org.gnome.desktop.interface clock-show-date, clock-format).
  (define (gnome-clock-text)
    (let ([d (current-date)])
      (format "~a ~a  ~2,'0d:~2,'0d"
              (vector-ref '#("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug"
                             "Sep" "Oct" "Nov" "Dec")
                          (- (date-month d) 1))
              (date-day d) (date-hour d) (date-minute d))))

  ;; The status the right of the bar shows, in the system's place: every
  ;; segment of status but the clock, which is in the middle; or, when the
  ;; style shows the mouse documentation, doc, what the mouse buttons do.
  (define (gnome-status-strings doc status)
    (if (theme 'mouse-doc)
        (if doc (list doc) '())
        (filter-map (lambda (s) (and (not (eq? (car s) 'clock)) (cdr s)))
                    status)))

  ;; GNOME Shell's panel (shell widgets/_panel.scss:13-17): 2.2 em high and
  ;; black (_colors.scss:24), with bold white text, and clear over the
  ;; overview, the app grid here (100-104). Activities is at its left, with
  ;; the text color at 17 % behind it under the pointer, 28 % while the app
  ;; grid shows (_drawing.scss:393-437); the current workspace's dot is
  ;; white, and the next one's is three quarters its size at half its
  ;; strength (js/ui/panel.js:50, 297-302). The clock is in the middle, and
  ;; the status at the right, 12 from the end.
  (define (gnome-draw-topbar h areas open? doc status)
    (let* ([w (screen-w)] [f 'ui-bold]
           [ty (/ (- h (font-line-height f)) 2)] [cy (/ h 2)]
           [l (cdr (assq 'launcher areas))]
           [lx (car l)] [lw (caddr l)]
           [grid? (eq? open? 'grid)]
           [clock (gnome-clock-text)]
           [cw (text-width clock f)] [cx (/ (- w cw) 2)])
      (unless grid?
        (fill-box 0 0 w h 'panel))
      (when (or grid? (equal? *hover* '(surface topbar launcher)))
        (fill-box (+ lx 3) 3 (- lw 6) (- h 6)
                  (alpha 'panel-text (if grid? 0.28 0.17)) (/ (- h 6) 2)))
      (let ([dx (+ lx 3 12 3)])
        (fill-box dx (- cy 4) 29 8 'panel-text 4)
        (fill-circle (+ dx 29 5 4) cy 3 (alpha 'panel-text 0.5)))
      (draw-text cx ty clock 'panel-text f)
      (let loop ([ss (reverse (gnome-status-strings doc status))] [x (- w 12)])
        (unless (null? ss)
          (let ([x0 (- x (text-width (car ss) f))])
            (when (> x0 (+ cx cw 24))
              (draw-text x0 ty (car ss) 'panel-text f)
              (loop (cdr ss) (- x0 18))))))))

  ;;; ------------------------------------------------------------------
  ;;; the dash

  ;; GNOME has no taskbar; the dock its designers made is the dash the
  ;; overview shows (shell widgets/_dash.scss), so the windows are a dash
  ;; floating at the bottom, sized in proportion to a bar's room: 6 from the
  ;; screen's edge (12 at the overview's size, 8), in the system's overlay
  ;; color (4, _colors.scss:49), with a tile for each window 6 inside it, 2
  ;; apart (19-25, 49-55) and 12 round, and a tile's 6 around its icon. The
  ;; dash's corners are the tiles' plus its padding (9); after a line comes
  ;; Show Apps (83-93). Returns, for a strip h high, (values the dash's
  ;; height, a tile's side, an icon's side).
  (define (gnome-dash-sizes h)
    (let* ([bh (- h 12)] [t (- bh 12)])
      (values bh t (- t 12))))

  ;; Returns the tiles, centered: ((launcher x y w h) (window x y w h) ...).
  (define (gnome-taskbar-areas h hint)
    (let*-values ([(bh t icon) (gnome-dash-sizes h)]
                  [(ws) (sort (lambda (a b) (< (window-id a) (window-id b)))
                              *windows*)]
                  [(n) (length ws)]
                  [(room) (- (screen-w) 24 4 13 (+ t 4) 4)]
                  [(pitch) (if (zero? n) (+ t 4) (min (+ t 4) (/ room n)))]
                  [(dw) (+ 4 (* n pitch) (if (zero? n) 0 9) (+ t 4) 4)]
                  [(x0) (floor (/ (- (screen-w) dw) 2))]
                  [(ty) (+ (- (screen-h) h) 6 6)])
      (cons (list 'launcher (- (+ x0 dw) 6 t) ty t t)
            (map (lambda (win i) (list win (+ x0 4 2 (* i pitch)) ty
                                       (- pitch 4) t))
                 ws (iota n)))))

  ;; Draws the dash: its box; the tiles, lighter under the pointer and for
  ;; the focused window (shell widgets/_dash.scss:57-68), each with its
  ;; window's icon, dimmed while the window is minimized, and a dot 5
  ;; across under it (_app-grid.scss:45-51); the line, of white at 10 %
  ;; (83-87); and Show Apps, with its grid of nine, checked while the app
  ;; grid shows (68).
  (define (gnome-draw-taskbar h areas open? doc status hint)
    (let*-values ([(bh t icon) (gnome-dash-sizes h)]
                  [(l) (cdr (assq 'launcher areas))]
                  [(wins) (filter (lambda (a) (window? (car a))) areas)]
                  [(y0) (+ (- (screen-h) h) 6)]
                  [(x0) (- (if (null? wins) (car l) (cadr (car wins))) 6)]
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
           (ui-draw-window-icon win ix (+ y 6) icon
                                (if (visible? win) '() '(dim)))
           (fill-circle (+ x (/ tw 2)) (+ y t 3) 2.5
                        (if (visible? win)
                            'adwaita-dash-text
                            (alpha 'adwaita-dash-text 0.5)))))
       wins)
      (unless (null? wins)
        (fill-box (- (car l) 6 1) (+ y0 12) 1 (- bh 24)
                  (alpha 'adwaita-dash-text 0.1)))
      (cond [(eq? open? 'grid)
             (fill-box (car l) (cadr l) t t 'adwaita-dash-checked 12)]
            [(equal? *hover* '(surface taskbar launcher))
             (fill-box (car l) (cadr l) t t 'adwaita-dash-hover 12)])
      (let ([gx (+ (car l) (/ (- t 16) 2))]
            [gy (+ (cadr l) (/ (- t 16) 2))])
        (do ([i 0 (+ i 1)]) ((= i 9))
          (fill-box (+ gx (* 6 (mod i 3))) (+ gy (* 6 (quotient i 3))) 4 4
                    'adwaita-dash-text 1)))))

  ;;; ------------------------------------------------------------------
  ;;; notifications: GNOME Shell's banners

  ;; The world's notices belong to the desktop, not to a window, as the
  ;; Shell's do, so they are its banners (shell widgets/_notifications.scss,
  ;; _message-list.scss): at the top in the middle, under the bar, 34 em
  ;; wide and at least 64 high (3-12), 8 apart. Returns (#(x y w h text
  ;; color) ...).
  (define (gnome-toast-boxes)
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
  ;; 88-94). 6 inside it is its header, 24 high, with the source dimmed:
  ;; its icon 16 across, here a dot of the notice's color, and Schevana in
  ;; bold (108-133). Under the header is the notice.
  (define (gnome-draw-toasts boxes)
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
       boxes)))

  ;;; ------------------------------------------------------------------
  ;;; menus

  ;; The desktop's own menus, the launcher and a window's menu, are GNOME
  ;; Shell's popup menus; the rest (a dropdown's) are libadwaita's
  ;; popovers.
  (define (gnome-shell-menu? m)
    (let ([t (menu-tag m)])
      (or (eq? t 'launcher) (and (pair? t) (eq? (car t) 'window)))))

  ;; The kit marks the current choice of a dropdown's menu with a check
  ;; after its label. Returns (values the label, whether it is chosen); the
  ;; check is drawn as a glyph at the item's end, as GTK's dropdown has it
  ;; (widgets/_dropdowns.scss:22-37).
  (define (gnome-menu-choice text)
    (if (string-suffix? "  ✓" text)
        (values (substring text 0 (- (string-length text) 3)) #t)
        (values text #f)))

  ;; The width of an item's text, its check, and the key that does the same
  ;; thing.
  (define (gnome-menu-label-width label)
    (let-values ([(text chosen?) (gnome-menu-choice
                                  (menu-label-text label))])
      (+ (text-width text 'ui)
         (if chosen? (+ 12 (ui-glyph-size)) 0)
         (let ([key (menu-label-key label)])
           (if key (+ 24 (text-width key 'ui)) 0)))))

  ;; An item's icon (shell widgets/_popovers.scss:70-72) is 16 pixels in
  ;; em (_common.scss:60, _drawing.scss:6-9), 6 before its text
  ;; (_common.scss:31, 131-133): its side, and the room it takes, or 0 when
  ;; the menu's entries have none.
  (define (gnome-menu-icon-size m)
    (if (> (menu-icon-size m 'ui) 0) (round (* 1.091 (adwaita-em))) 0))
  (define (gnome-menu-icon-room m)
    (let ([s (gnome-menu-icon-size m)]) (if (> s 0) (+ s 6) 0)))

  ;; A Shell menu (shell widgets/_popovers.scss:15-33) has 6 inside it and
  ;; is at least 15 em wide; an item is its text with 9 above and below it
  ;; and 12 beside it (_common.scss:131-136). A popover menu
  ;; (widgets/_menus.scss) has 6 inside it (58-66) and is at least 120 wide
  ;; (1-4), with items 32 high and 12 in (130-134), and a separator line 6
  ;; from what is above and below it (68-70). The filter's field sits over
  ;; the items.
  (define (gnome-menu-areas m)
    (let* ([shell? (gnome-shell-menu? m)] [es (menu-entries m)]
           [ih (if shell? (round (+ (font-line-height 'ui) 18)) 32)]
           [sh 13] [pad 6] [tx 12] [icons (gnome-menu-icon-room m)]
           [head (if (menu-filter? m) (+ (ui-control-height) pad) 0)]
           [w (fold-left (lambda (acc e)
                           (if (pair? e)
                               (max acc (+ pad tx icons
                                           (gnome-menu-label-width (car e))
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

  ;; Draws a Shell menu's box: #36363a in a hairline of #424247, 20 round,
  ;; over a shadow (shell widgets/_popovers.scss:27-33).
  (define (gnome-shell-panel x y w h)
    (draw-shadow x y w h 20 6)
    (fill-box x y w h 'adwaita-shell-bg 20)
    (stroke-box x y w h 'adwaita-shell-border 1 20))

  ;; Draws the filter: an entry with what is typed in it, or a dimmed hint.
  (define (gnome-menu-filter m x y w h shell?)
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

  ;; Draws the menu and its items. The chosen item (by the keys or the
  ;; pointer) is lighter: 12 round in the Shell's menu (shell
  ;; widgets/_popovers.scss:36-39), and in a popover the text color at 10 %,
  ;; 9 round, or 19 % while held. A key that does the same thing is dimmed
  ;; at the right (widgets/_menus.scss:76-81).
  (define (gnome-draw-menu m areas on flags)
    (let* ([shell? (gnome-shell-menu? m)]
           [es (list->vector (menu-entries m))] [lh (font-line-height 'ui)]
           [ink (if shell? 'adwaita-shell-text 'text)]
           [dim (if shell? 'adwaita-shell-dim 'text-dim)]
           [is (gnome-menu-icon-size m)] [icons (gnome-menu-icon-room m)]
           [f (assq 'filter areas)])
      (apply (lambda (x y w h)
               (if shell?
                   (gnome-shell-panel x y w h)
                   (ui-draw-panel x y w h '(menu))))
             (cdar areas))
      (when f
        (apply (lambda (fx fy fw fh) (gnome-menu-filter m fx fy fw fh shell?))
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
               (let* ([sel? (eqv? what on)]
                      [held? (and sel? (memq 'pressed flags))]
                      [icon (menu-entry-icon (vector-ref es what))]
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
                 (when (and icon (> is 0))
                   (icon (+ x 18) (+ y (/ (- h is) 2)) is '()))
                 (let-values ([(text chosen?)
                               (gnome-menu-choice (menu-label-text label))])
                   (draw-text (+ x 18 icons) ty
                              (text-fit text
                                        (max 0
                                             (- w 36 icons
                                                (if key
                                                    (+ 12 (text-width key 'ui))
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
       (cdr areas))))

  ;;; ------------------------------------------------------------------
  ;;; the app grid: the overview's apps

  ;; Returns (values rows columns a tile's side) for a page w by h within
  ;; its padding. A page is 8 rows of 3, 6 of 4, 4 of 6 or 3 of 8, whichever
  ;; is nearest its shape (js/ui/iconGrid.js:29-46, 1224-1244), with the
  ;; largest icon of 96, 64, 48, 32, 24 and 16 whose tiles fit, 12 apart
  ;; (16-23, 360-399; shell widgets/_app-grid.scss:7-11). A tile is square:
  ;; its icon, 6, and its name, with 12 around them (iconGrid.js:61-62;
  ;; _app-grid.scss:21-37).
  (define (gnome-grid-mode w h)
    (let* ([lh (font-line-height 'ui)] [ratio (/ w (max h 1))]
           [near (lambda (m) (abs (- ratio (/ (cdr m) (car m)))))]
           [mode (fold-left (lambda (best m) (if (< (near m) (near best))
                                                 m
                                                 best))
                            '(8 . 3) '((6 . 4) (4 . 6) (3 . 8)))]
           [rows (car mode)] [cols (cdr mode)]
           [tile (lambda (s) (exact (round (+ s 6 lh 24))))]
           [fits? (lambda (s)
                    (and (<= (+ (* cols (tile s)) (* 12 (- cols 1))) w)
                         (< (+ (* rows (tile s)) (* 12 (- rows 1))) h)))])
      (values rows cols (tile (or (find fits? '(96 64 48 32 24 16)) 16)))))

  ;; Returns (values the room before the first of n tiles t across, the
  ;; pitch from one to the next) in room r: the tiles spread out to fill
  ;; it, up to 36 apart, and the rest is split on both sides
  ;; (js/ui/iconGrid.js:572-646; shell widgets/_app-grid.scss:10-11).
  (define (gnome-grid-spread r t n)
    (let* ([empty (- r (* n t) (* 12 (- n 1)))]
           [gap (+ 12 (/ empty (- n 1)))])
      (if (> gap 36)
          (values (max 0 (/ (- empty (* 24 (- n 1))) 2)) (+ t 36))
          (values 0 (+ t gap)))))

  ;; GNOME Shell's app grid, as the overview shows it after Show Apps
  ;; (js/ui/overviewControls.js:154-247): from the top bar down, the search
  ;; entry, a gap of 2 % of the overview's height (22, 160), the grid, the
  ;; same gap, and the dash. The overview's small view of the workspace,
  ;; between the entry and the grid (100-105), is left out, and its room
  ;; goes to the grid. The entry is a pill 24 em wide, 12 under the bar and
  ;; 6 over the gap (shell widgets/_search-entry.scss:2-8), its text 9 from
  ;; its top and bottom (_common.scss:175-177). A page leaves 24 above and
  ;; below its tiles and 18 beside them (_app-grid.scss:12-15), and beside
  ;; that a tenth of the width, where the pages next to it peek in, or the
  ;; 72 that their arrows take (js/ui/appDisplay.js:49, 161-170, 225-236;
  ;; _app-grid.scss:172-177). Under the page, when there is more than one,
  ;; are their dots, each in a button 12 wider than it on either side and 6
  ;; taller (_app-grid.scss:119-132; js/ui/pageIndicators.js:86;
  ;; appDisplay.js:598-604). Returns the areas as app-grid-areas does.
  (define (gnome-app-grid-areas n page)
    (let*-values ([(dx dy dw dh) (desktop-rect)]
                  [(gap) (exact (round (* 0.02 (- (screen-h) dy))))]
                  [(eh) (exact (round (+ (font-line-height 'ui) 18)))]
                  [(ew) (min (exact (round (* 24 (adwaita-em)))) (- dw 24))]
                  [(gy) (+ dy 12 eh 6 gap)]
                  [(gh) (- (+ dy dh) gap gy)]
                  [(side) (+ 18 (max (exact (round (* 0.1 dw))) 72))]
                  [(pw) (- dw side side)]
                  [(rows cols t) (gnome-grid-mode pw (- gh 48))]
                  [(ph) (if (> n (* rows cols)) (- gh 16) gh)]
                  [(rows cols t) (gnome-grid-mode pw (- ph 48))]
                  [(per) (* rows cols)]
                  [(pages) (max 1 (quotient (+ n per -1) per))]
                  [(x0 dx1) (gnome-grid-spread pw t cols)]
                  [(y0 dy1) (gnome-grid-spread (- ph 48) t rows)])
      (append
       (list (list 'search (+ dx (quotient (- dw ew) 2)) (+ dy 12) ew eh))
       (if (> pages 1)
           (let ([px (+ dx (quotient (- dw (* pages 34)) 2))])
             (map (lambda (k) (list (cons 'page k) (+ px (* k 34)) (+ gy ph)
                                    34 16))
                  (iota pages)))
           '())
       (map (lambda (j)
              (list (+ (* page per) j)
                    (exact (round (+ dx side x0 (* (remainder j cols) dx1))))
                    (exact (round (+ gy 24 y0 (* (quotient j cols) dy1))))
                    t t))
            (iota (max 0 (min per (- n (* page per)))))))))

  ;; Draws the search entry: a pill in the system's entry color with a
  ;; magnifier 16 across, 4 from its text (shell widgets/_search-entry.scss:
  ;; 2-14), and "Type to search" at 70 % (js/ui/overviewControls.js:329;
  ;; _common.scss:344) until something is typed. While it has the keys'
  ;; focus (focus?), it shows its caret, and a ring 2 inside it in the
  ;; Shell's accent (the accent mixed 40 % with white) at 80 %
  ;; (_default-colors.scss:8, 47; _drawing.scss:57-66).
  (define (gnome-grid-search x y w h text focus?)
    (let* ([lh (font-line-height 'ui)] [ty (+ y (/ (- h lh) 2))]
           [g (ui-glyph-size)] [tx (+ x 9 g 4)]
           [ink 'adwaita-dash-text])
      (fill-box x y w h 'adwaita-overview-entry (/ h 2))
      (ui-draw-glyph (+ x 9) (+ y (/ (- h g) 2)) g g
                     (list (cons 'ink (alpha ink 0.7))) 'search)
      (when focus?
        (stroke-box x y w h (alpha (mix 'accent #xffffff 0.4) 0.8) 2 (/ h 2)))
      (with-clip (tx y (- (+ x w) tx 9) h)
        (let ([ex (if (string=? text "")
                      (begin
                        (draw-text tx ty "Type to search" (alpha ink 0.7) 'ui)
                        tx)
                      (draw-text (min tx (- (+ x w) 10 (text-width text 'ui)))
                                 ty text ink 'ui))])
          (when focus? (fill-box ex ty 1 lh ink))))))

  ;; Draws the app grid on the overview's color (shell widgets/
  ;; _overview.scss:7-9): its search entry; its tiles, 24 round
  ;; (_app-grid.scss:25), lighter under the pointer and ringed as the entry
  ;; is when the keys choose them, each with its icon and its name in the
  ;; system's text; an action's icon is a circle of the text at 10 %, as a
  ;; system action's (139-147). The current page's dot is white, and the
  ;; others two thirds its size at half its strength, or whole under the
  ;; pointer (120-131; js/ui/pageIndicators.js:6-9, 89-102).
  (define (gnome-draw-app-grid entries areas filter focus? page sel)
    (let ([es (list->vector entries)] [lh (font-line-height 'ui)]
          [ink 'adwaita-dash-text])
      (fill-box 0 0 (screen-w) (screen-h) 'adwaita-overview)
      (for-each
       (lambda (a)
         (apply
          (lambda (what x y w h)
            (let ([hover? (equal? *hover* (list 'surface 'app-grid what))])
              (cond
                [(eq? what 'search)
                 (gnome-grid-search x y w h filter focus?)]
                [(pair? what)
                 (let ([on? (= (cdr what) page)])
                   (fill-circle (+ x (/ w 2)) (+ y 6 5) (if on? 5 10/3)
                                (if (or on? hover?) ink (alpha ink 0.5))))]
                [else
                 (let* ([e (vector-ref es what)] [s (round (- w 30 lh))]
                        [ix (+ x (/ (- w s) 2))] [iy (+ y 12)])
                   (when hover?
                     (fill-box x y w h 'adwaita-overview-hover 24))
                   (when (eqv? what sel)
                     (stroke-box x y w h (alpha (mix 'accent #xffffff 0.4) 0.8)
                                 2 24))
                   (if (cadr e)
                       (ui-draw-app-icon ix iy s '() (cadr e))
                       (begin
                         (fill-circle (+ ix (/ s 2)) (+ iy (/ s 2)) (/ s 2)
                                      (alpha ink 0.1))
                         (text-draw-centered ix iy s s
                                             (string (char-upcase
                                                      (string-ref (car e) 0)))
                                             ink 'big)))
                   (text-draw-centered (+ x 12) (+ iy s 6) (- w 24) lh
                                       (text-fit (car e) (- w 24) 'ui)
                                       ink 'ui))])))
          a))
       areas)))

  ;;; ------------------------------------------------------------------
  ;;; the desktop

  ;; After the blue shapes of GNOME 48's default wallpaper, the Adwaita one
  ;; (gnome-backgrounds 48; facts only, no image): the desktop's colors
  ;; shading down, and over them three great circles, darker and lighter,
  ;; which the screen's edges cut. Any other wallpaper is drawn alone.
  (define (gnome-draw-wallpaper w h)
    (fill-wallpaper 0 0 w h (theme 'wallpaper) 'desktop-top 'desktop-bottom)
    (when (eq? (wallpaper-shown (theme 'wallpaper)) 'gradient)
      (let ([s (max w h)])
        (fill-circle (* w 0.1) (* h 1.15) (* s 0.55)
                     (alpha (mix 'desktop-bottom #x000000 0.3) 0.45))
        (fill-circle (* w 0.96) (* h -0.1) (* s 0.42)
                     (alpha (mix 'desktop-top #xffffff 0.35) 0.3))
        (fill-circle (* w 0.72) (* h 1.05) (* s 0.36)
                     (alpha (mix 'desktop-top 'desktop-bottom 0.4) 0.55)))))

  ;;; ------------------------------------------------------------------

  (at-load
   (define-style gnome "GNOME"
     'parent 'adwaita
     ;; the top bar, 2.2 em of GNOME's text (shell widgets/_panel.scss:10),
     ;; 32 at its 11 pt; and the dash's strip
     'topbar-height (theme-rule (max 32 (round (* 2.2 (adwaita-em)))))
     'taskbar-height 64
     'draw-topbar 'gnome-draw-topbar
     'topbar-areas 'gnome-topbar-areas
     'taskbar-areas 'gnome-taskbar-areas
     'draw-taskbar 'gnome-draw-taskbar
     'toast-boxes 'gnome-toast-boxes
     'draw-toasts 'gnome-draw-toasts
     'menu-areas 'gnome-menu-areas
     'draw-menu 'gnome-draw-menu
     ;; the launcher, the overview's app grid
     'launcher-form 'grid
     'app-grid-areas 'gnome-app-grid-areas
     'draw-app-grid 'gnome-draw-app-grid
     'draw-wallpaper 'gnome-draw-wallpaper)))
