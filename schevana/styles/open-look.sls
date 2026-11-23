;;; (schevana styles open-look) — the OPEN LOOK window style: Sun's OPEN LOOK
;;; as OpenWindows drew it, with olwm, its window manager, through OLGX, its
;;; drawing library (XView 3.2 on the X11R6 contrib tape; Sun's Functional
;;; Specification of 1989 where the code is silent). A window is its window
;;; color, BG1, in an outline of ink 2 pixels wide, or 3 while it has the
;;; focus. Its header holds the window button at the left (a click closes the
;;; window to the taskbar, as the button's default, Close, does) and the
;;; title, in bold, centered in the rest. A pop-up, a window opened 'above
;;; another, has a pushpin there instead, pinned in: pull it out and the
;;; window goes. An L-shaped resize corner sits at each corner, the only
;;; place a window resizes from. The focus is a band across the header, of
;;; ink in 2D and recessed in 3D, or, with open-look-focus set to lines,
;;; olwm's two lines. A window's 'footer, a string or (left . right), shows
;;; under it in the title's font. The controls are OLGX's as XView drew
;;; them, on panes of the window color in 3D and white in 2D: an oblong
;;; button, the default one ringed, a glyph alone in an abbreviated button,
;;; and an inactive one grayed over. Everything comes in OPEN LOOK's four
;;; sizes, 10, 12, 14 and 19 point, whichever is nearest the text size. The
;;; fixed parts are OLGX's own glyphs (its fonts, a part of their own:
;;; (schevana styles open-look fonts), under their notice) pixel for pixel,
;;; the numbers are olwm's (winframe.c), and the shades follow OLGX's
;;; arithmetic, translated from Sun's code, whose notice goes with it:
;;;
;;;   (c) Copyright 1989, 1990, 1991 Sun Microsystems, Inc. Sun design
;;;   patents pending in the U.S. and foreign countries. OPEN LOOK is a
;;;   trademark of USL. Used by written permission of the owners.
;;;
;;;   (c) Copyright Bigelow & Holmes 1986, 1985. Lucida is a registered
;;;   trademark of Bigelow & Holmes. Permission to use the Lucida
;;;   trademark is hereby granted only in association with the images
;;;   and fonts described in this file.

;; Chez's reader syntax, since the depth's setting is the symbol 3d.
#!chezscheme
(library (schevana styles open-look)
  (export
    open-look-insets open-look-regions open-look-draw-under open-look-button
    open-look-button-size)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) color-default! define-style draw-text fill-box
                font font-ascent rgb stipple stroke-box text-width theme
                theme-rule window-h window-ref window-title window-w)
          (only (schevana kits color) color->fixnum)
          (only (schevana kits text) text-within)
          (only (schevana kits ui) ui-draw-focus ui-draw-glyph ui-glyph-size)
          (schevana styles open-look fonts))

  (library-layer looks)

  ;; Returns the one of the four sizes nearest a text size n: 10, 12, 14 or
  ;; 19.
  (define (open-look-size-near n)
    (cond [(< n 11) 10] [(< n 13.5) 12] [(< n 16.5) 14] [else 19]))

  ;; The size in use: the one nearest the text size.
  (define (open-look-size) (open-look-size-near (theme 'ui-font-size)))

  ;; Returns one of four numbers, by the size.
  (define (open-look-by-size a b c d)
    (case (open-look-size) [(10) a] [(12) b] [(14) c] [else d]))

  (define (open-look-3d?) (eq? (theme 'open-look-depth) '3d))

  ;;; ------------------------------------------------------------------
  ;;; the frame's numbers, olwm's at each size (winframe.c:94-240)

  ;; The width of the sides and the bottom, the outline included: a resize
  ;; corner's arm.
  (define (open-look-arm) (open-look-by-size 5 5 6 6))
  ;; The header's height: the window button's, or the title font's plus 2.
  (define (open-look-header) (open-look-by-size 13 15 17 23))
  ;; The height above the pane: the header, an arm above it and one below.
  (define (open-look-top) (+ (open-look-header) (* 2 (open-look-arm))))
  ;; A resize corner's square: its arms' length.
  (define (open-look-corner) (open-look-by-size 10 11 12 14))
  ;; The sizes of the window button (an abbreviated menu button) and the
  ;; pushpin.
  (define (open-look-button-w) (open-look-by-size 14 16 18 21))
  (define (open-look-button-h) (- (open-look-button-w) 1))
  (define (open-look-pin-w) (open-look-by-size 26 26 28 28))
  (define (open-look-pin-h) (open-look-by-size 13 13 15 15))
  ;; The title's baseline under the header's top: Lucida Sans Bold's ascent.
  (define (open-look-ascent) (open-look-by-size 9 11 13 17))
  ;; The footer's height, the title font's height and an arm; and its
  ;; baseline's height over the bottom edge, the font's descent and an arm.
  (define (open-look-footer-h)
    (+ (open-look-by-size 11 13 15 21) (open-look-arm)))
  (define (open-look-footer-base) (open-look-by-size 7 7 8 10))

  ;; OPEN LOOK's pop-ups belong to a base window: here, a pop-up is a window
  ;; opened 'above another.
  (define (open-look-pop-up? win) (and (window-ref win 'above #f) #t))

  ;; Returns where the window button, or a pop-up's pushpin, sits: (x y w h),
  ;; centered in the header's height.
  (define (open-look-gadget win)
    (let ([x (+ (open-look-size) 2)] [a (open-look-arm)]
          [hh (open-look-header)])
      (if (open-look-pop-up? win)
          (list x (+ a (quotient (- hh (open-look-pin-h)) 2))
                (open-look-pin-w) (open-look-pin-h))
          (list x (+ a (quotient (- hh (open-look-button-h)) 2))
                (open-look-button-w) (open-look-button-h)))))

  (define (open-look-insets win)
    (let ([a (open-look-arm)])
      (values a (open-look-top) a
              (if (window-ref win 'footer #f) (+ a (open-look-footer-h)) a))))

  ;; The window button closes the window to the taskbar (minimize), and the
  ;; pushpin dismisses a pop-up (close); a base window's corners resize it
  ;; (a pop-up keeps its size, as XView's do).
  (define (open-look-regions win)
    (let ([w (window-w win)] [h (window-h win)] [c (open-look-corner)])
      (if (open-look-pop-up? win)
          (list (cons 'close (open-look-gadget win)))
          (list (cons 'minimize (open-look-gadget win))
                (list 'resize-tl 0 0 c c)
                (list 'resize-tr (- w c) 0 c c)
                (list 'resize-br (- w c) (- h c) c c)
                (list 'resize-bl 0 (- h c) c c)))))

  ;;; ------------------------------------------------------------------
  ;;; OLGX's colors (olgx_calculate_3Dcolors, ol_color.c:45-244)

  ;; Returns OLGX's HSV of #xRRGGBB: h from 0 to 359, s and v from 0 to
  ;; 1000, matching OLGX's integer arithmetic integer for integer.
  (define (open-look-hsv c)
    (let* ([r (fxand (fxsrl c 16) 255)] [g (fxand (fxsrl c 8) 255)]
           [b (fxand c 255)] [mx (max r g b)] [mn (min r g b)]
           [s (if (> mx 0) (quotient (* (- mx mn) 255) mx) 0)])
      (values
       (if (= s 0)
           0
           (let* ([d (- mx mn)]
                  [rc (quotient (* (- mx r) 255) d)]
                  [gc (quotient (* (- mx g) 255) d)]
                  [bc (quotient (* (- mx b) 255) d)]
                  [h (cond [(= r mx) (quotient (* (- bc gc) 60) 255)]
                           [(= g mx) (+ 120 (quotient (* (- rc bc) 60) 255))]
                           [else (+ 240 (quotient (* (- gc rc) 60) 255))])])
             (if (< h 0) (+ h 360) h)))
       (quotient (* s 1000) 255)
       (quotient (* mx 1000) 255))))

  (define (open-look-rgb h s v)
    (let* ([s (quotient (* s 255) 1000)] [v (quotient (* v 255) 1000)]
           [h (if (or (= h 360) (= s 0)) 0 h)]
           [f (remainder h 60)]
           [p (quotient (* v (- 255 s)) 255)]
           [q (quotient (* v (- 255 (quotient (* s f) 60))) 255)]
           [t (quotient (* v (- 255 (quotient (* s (- 60 f)) 60))) 255)])
      (case (quotient h 60)
        [(0) (rgb v t p)] [(1) (rgb q v p)] [(2) (rgb p v t)]
        [(3) (rgb p q v)] [(4) (rgb t p v)] [else (rgb v p q)])))

  ;; Returns a 3D shade of color c: bg2 has its value x 0.9; bg3, x 0.5; and
  ;; highlight, x 1.2, with its saturation halved if that passes the top and
  ;; its value at least 0.4. So #cccccc's shades are #b7b7b7, #666666 and
  ;; #f4f4f4.
  (define (open-look-shade c which)
    (let-values ([(h s v) (open-look-hsv (color->fixnum c))])
      (case which
        [(bg2) (open-look-rgb h s (quotient (* v 9) 10))]
        [(bg3) (open-look-rgb h s (quotient v 2))]
        [else (let ([v (quotient (* v 12) 10)])
                (open-look-rgb h (if (> v 1000) (quotient s 2) s)
                               (max 400 (min v 1000))))])))

  ;;; ------------------------------------------------------------------
  ;;; OLGX's drawing

  ;; Draws glyph name of the size's font with its top-left pixel at (x, y):
  ;; its set pixels in color, each run in a row as one box. If cut is given,
  ;; the glyph is cut to the cw × ch window that olwm draws it in (at 19
  ;; point some glyphs are a pixel larger than their windows).
  (define (open-look-glyph x y name color . cut)
    (let ([g (open-look-font-glyph (open-look-size) name)])
      (when g
        (let ([w (if (pair? cut) (min (car g) (car cut)) (car g))]
              [n (if (pair? cut) (cadr cut) (cadr g))])
          (let rows ([rs (cddr g)] [j 0])
            (unless (or (null? rs) (>= j n))
              (let ([on? (lambda (i) (and (< i w)
                                          (fxbit-set? (car rs)
                                                      (- (car g) 1 i))))])
                (let run ([i 0])
                  (cond
                    [(>= i w) (void)]
                    [(on? i)
                     (let end ([e (+ i 1)])
                       (if (on? e)
                           (end (+ e 1))
                           (begin (fill-box (+ x i) (+ y j) (- e i) 1 color)
                                  (run e))))]
                    [else (run (+ i 1))])))
              (rows (cdr rs) (+ j 1))))))))

  ;; olgx_draw_box (ol_draw.c:42-118): the top and left lines in ul, the
  ;; bottom and right ones in lr, which gets the top right pixel; and fill
  ;; inside.
  (define (open-look-box x y w h ul lr fill)
    (fill-box (+ x 1) (+ y 1) (- w 2) (- h 2) fill)
    (fill-box x y w 1 ul)
    (fill-box x y 1 h ul)
    (fill-box (+ x 1) (+ y h -1) (- w 1) 1 lr)
    (fill-box (+ x w -1) y 1 h lr))

  ;; Draws the vertical menu mark in 3D (olgx_draw_menu_mark,
  ;; ol_button.c:485-549).
  (define (open-look-menu-mark x y)
    (open-look-glyph x y 'vert-menu-mark-ul 'open-look-bg3)
    (open-look-glyph x y 'vert-menu-mark-lr 'open-look-highlight)
    (open-look-glyph x y 'vert-menu-mark-fill 'open-look-bg2))

  ;;; ------------------------------------------------------------------
  ;;; the frame

  ;; Draws the focus band, (x y) being the window's corner: ink in 2D, a
  ;; recessed box in 3D (winframe.c:545-574, 660-698).
  (define (open-look-draw-band x y w)
    (let ([a (open-look-arm)] [hh (open-look-header)])
      (if (open-look-3d?)
          (open-look-box (+ x a) (+ y a) (- w a a) hh
                         'open-look-bg3 'open-look-highlight 'open-look-bg2)
          (fill-box (+ x a) (+ y a -1) (- w a a) (+ hh 1) 'open-look-ink))))

  ;; Or draws olwm's two lines, 2 pixels each, one under the outline o
  ;; between the corners and one over the pane: ink, or raised in 3D
  ;; (winframe.c:577-630, 701-751).
  (define (open-look-draw-lines x y w o)
    (let ([a (open-look-arm)] [c (open-look-corner)])
      (define (line lx ly lw)
        (if (open-look-3d?)
            (begin (fill-box lx ly lw 1 'open-look-highlight)
                   (fill-box lx (+ ly 1) lw 1 'open-look-bg3))
            (fill-box lx ly lw 2 'open-look-ink)))
      (line (+ x c 1) (+ y o 1) (- w c c 2))
      (line (+ x a) (+ y (open-look-top) -3) (- w a a))))

  ;; Draws the resize corners (olgx_draw_resize_corner, ol_misc.c:17-68): in
  ;; 3D, an L of three layers, with the pressed corner's colors swapped; in
  ;; 2D, an outline of ink and its inside, which is ink when pressed.
  (define (open-look-draw-corners x y w h pressed)
    (let ([c (open-look-corner)])
      (for-each
       (lambda (corner region cx cy)
         (let ([down? (eq? pressed region)]
               [layer (lambda (l) (string->symbol
                                   (format "~a-resize-~a" corner l)))])
           (define (draw l color) (open-look-glyph cx cy (layer l) color c c))
           (if (open-look-3d?)
               (begin
                 (draw 'ul (if down? 'open-look-bg3 'open-look-highlight))
                 (draw 'lr (if down? 'open-look-highlight 'open-look-bg3))
                 (draw 'fill (if down? 'open-look-bg2 'open-look-window)))
               (begin
                 (draw 'outline 'open-look-ink)
                 (draw 'fill (if down? 'open-look-ink 'open-look-window))))))
       '(ul ur lr ll) '(resize-tl resize-tr resize-br resize-bl)
       (list x (+ x w (- c)) (+ x w (- c)) x)
       (list y y (+ y h (- c)) (+ y h (- c))))))

  ;; Draws the window button (olgx_draw_abbrev_button, ol_button.c:553-643)
  ;; on the window color that olwm erases it to (winbutton.c:226-276), and
  ;; on the 2D band in a ring of ink.
  (define (open-look-draw-button x y pressed? band?)
    (let ([bw (open-look-button-w)] [bh (open-look-button-h)])
      (define (draw name color) (open-look-glyph x y name color bw bh))
      (fill-box x y bw bh 'open-look-window)
      (if (open-look-3d?)
          (let ([m (open-look-by-size 7 7 11 13)])   ; the menu mark's size
            (draw 'abbrev-menu-ul
                  (if pressed? 'open-look-bg3 'open-look-highlight))
            (draw 'abbrev-menu-lr
                  (if pressed? 'open-look-highlight 'open-look-bg3))
            (draw 'abbrev-menu-fill
                  (if pressed? 'open-look-bg2 'open-look-window))
            (open-look-menu-mark (+ x (quotient (- bw m) 2))
                                 (+ y (quotient (- (+ 1 bh) m) 2))))
          (begin
            (draw (if pressed? 'abbrev-menu-button-inverted 'abbrev-menu-button)
                  'open-look-ink)
            (when band? (stroke-box x y bw bh 'open-look-ink))))))

  ;; Draws a pop-up's pushpin (olgx_draw_pushpin, ol_misc.c:70-147), pinned
  ;; in or pulled out, on what olwm erases under it (winpush.c:160-206); in
  ;; 2D on the band, it is the window color on ink.
  (define (open-look-draw-pin x y in? band?)
    (let ([pw (open-look-pin-w)] [ph (open-look-pin-h)])
      (define (draw name color) (open-look-glyph x y name color pw ph))
      (if (open-look-3d?)
          (begin
            (fill-box x y pw ph (if band? 'open-look-bg2 'open-look-window))
            (draw (if in? 'pushpin-in-top 'pushpin-out-top)
                  'open-look-highlight)
            (draw (if in? 'pushpin-in-bottom 'pushpin-out-bottom)
                  'open-look-bg3)
            (draw (if in? 'pushpin-in-middle 'pushpin-out-middle)
                  'open-look-bg2))
          (begin
            (fill-box x y pw ph (if band? 'open-look-ink 'open-look-window))
            (draw (if in? 'menu-pin-in 'menu-pin-out)
                  (if band? 'open-look-window 'open-look-ink))))))

  ;; Returns the longest start of str that fits within w pixels in font, cut
  ;; with no ellipsis.
  (define (open-look-cut str w font)
    (let ([s (text-within str w)])
      (if (<= (text-width s font) w)
          s
          (let loop ([lo 0] [hi (string-length s)])   ; lo fits, hi does not
            (if (<= (- hi lo) 1)
                (substring s 0 lo)
                (let ([m (quotient (+ lo hi) 2)])
                  (if (<= (text-width (substring s 0 m) font) w)
                      (loop m hi)
                      (loop lo m))))))))

  ;; olwm's title: when it is too wide, it loses everything up to its first
  ;; colon, then whatever does not fit at the right (winframe.c:1366-1396).
  (define (open-look-fit-title str w font)
    (let* ([n (string-length str)]
           [wide? (or (> n (+ 1 (max 0 w))) (> (text-width str font) w))]
           [colon (let loop ([i 0])
                    (cond [(= i n) #f]
                          [(char=? (string-ref str i) #\:) i]
                          [else (loop (+ i 1))]))])
      (open-look-cut (if (and wide? colon) (substring str (+ colon 1) n) str)
                     w font)))

  ;; Draws text with its baseline at y (draw-text puts it on a whole device
  ;; row).
  (define (open-look-text x y str color font)
    (draw-text x (- y (font-ascent font)) str color font))

  ;; Draws the title, centered to the right of the button or pushpin
  ;; (winframe.c:1313-1401), in the window color on the 2D band (inverse?).
  (define (open-look-draw-title win x y w inverse?)
    (let* ([g (open-look-gadget win)]
           [off (+ (car g) (caddr g) (quotient (open-look-size) 4))]
           [room (- w (open-look-arm) off)])
      (when (> room 0)
        (let* ([t (open-look-fit-title (window-title win) room 'title)]
               [tw (text-width t 'title)])
          (open-look-text (+ x off (floor (/ (- room tw) 2)))
                          (+ y (open-look-arm) (open-look-ascent)) t
                          (if inverse? 'open-look-window 'open-look-ink)
                          'title)))))

  ;; Draws the footer: its left text at the left margin and its right text
  ;; at the right; when both don't fit, the right text keeps at most a
  ;; quarter of the room (winframe.c:787-858).
  (define (open-look-draw-footer win x y w h)
    (let ([f (window-ref win 'footer #f)])
      (when f
        (let* ([left (if (pair? f) (car f) f)] [right (if (pair? f) (cdr f) "")]
               [m (+ (open-look-size) 2)] [gap (open-look-size)]
               [room (- w m m)] [base (+ y h (- (open-look-footer-base)))]
               [rw (text-width right 'title)]
               [right (if (> (+ (text-width left 'title) gap rw) room)
                          (open-look-cut right (min rw (/ room 4)) 'title)
                          right)]
               [rw (text-width right 'title)]
               [left (open-look-cut left (- room (if (string=? right "")
                                                     0
                                                     (+ gap rw)))
                                    'title)])
          (open-look-text (+ x m) base left 'open-look-ink 'title)
          (open-look-text (+ x w (- m) (- rw)) base right 'open-look-ink
                          'title)))))

  (define (open-look-draw-under win x y w h focused? hover pressed)
    (let* ([o (if focused? 3 2)] [c (open-look-corner)]
           [band? (and focused? (not (eq? (theme 'open-look-focus) 'lines)))]
           [g (open-look-gadget win)] [gx (+ x (car g))] [gy (+ y (cadr g))])
      (fill-box x y w h 'open-look-ink)
      (fill-box (+ x o) (+ y o) (- w o o) (- h o o) 'open-look-window)
      ;; a base window's corners lie over the outline, and the band over
      ;; them
      (unless (open-look-pop-up? win)
        (fill-box x y c c 'open-look-window)
        (fill-box (+ x w (- c)) y c c 'open-look-window)
        (fill-box (+ x w (- c)) (+ y h (- c)) c c 'open-look-window)
        (fill-box x (+ y h (- c)) c c 'open-look-window))
      (cond [band? (open-look-draw-band x y w)]
            [focused? (open-look-draw-lines x y w o)])
      (if (open-look-pop-up? win)
          (open-look-draw-pin gx gy (not (eq? pressed 'close)) band?)
          (begin (open-look-draw-corners x y w h pressed)
                 (open-look-draw-button gx gy (eq? pressed 'minimize) band?)))
      (open-look-draw-title win x y w (and band? (not (open-look-3d?))))
      (open-look-draw-footer win x y w h)))

  ;;; ------------------------------------------------------------------
  ;;; the controls, OLGX's (ol_button.c) as XView draws them on its panes:
  ;;; on BG1 in 3D and on white in 2D, the window-bg the style gives

  ;; An oblong button's numbers (OLGX's metrics, ol_init.c:148-268): its
  ;; height, 2D's with the shadow under it and 3D's a pixel less; an end's
  ;; width, where the label starts; the label's baseline under its top,
  ;; button_height less base_off.
  (define (open-look-oblong-h)
    (- (open-look-by-size 18 20 22 28) (if (open-look-3d?) 1 0)))
  (define (open-look-endcap) (open-look-by-size 8 9 11 18))
  (define (open-look-oblong-base) (open-look-by-size 12 13 15 19))

  ;; Glyph name, 1 pixel wide, drawn n wide from (x, y): a box for each run
  ;; of its rows.
  (define (open-look-glyph-across x y name n color)
    (let ([g (open-look-font-glyph (open-look-size) name)])
      (when (and g (> n 0))
        (let rows ([rs (cddr g)] [j 0] [from #f])   ; from: the run's first
          (let ([on? (and (pair? rs) (= (car rs) 1))])
            (cond
              [(and on? (not from)) (rows (cdr rs) (+ j 1) j)]
              [(and from (not on?))
               (fill-box x (+ y from) n (- j from) color)
               (when (pair? rs) (rows (cdr rs) (+ j 1) #f))]
              [(pair? rs) (rows (cdr rs) (+ j 1) from)]))))))

  ;; A run of glyphs as OLGX prints one (ol_draw.c:16-39): left, n pixels
  ;; of middle, right. OLGX sums the middle from pieces 16, 8, 4, 2 and 1
  ;; wide, each the 1-wide one repeated, so that one is drawn n wide; the
  ;; left one advances an end's width.
  (define (open-look-strip x y n left middle right color)
    (let ([e (open-look-endcap)])
      (open-look-glyph x y left color)
      (open-look-glyph-across (+ x e) y middle n color)
      (open-look-glyph (+ x e n) y right color)))

  ;; The oblong button w wide from (x, y) (olgx_draw_button, ol_button.c:
  ;; 64-224): in 3D its bevel and face, raised, or recessed when invoked;
  ;; in 2D its outline and shadow on white, filled with ink when invoked.
  ;; The default ring lies a pixel inside, in 2D only while not invoked.
  (define (open-look-draw-oblong x y w invoked? default?)
    (let ([n (- w (* 2 (open-look-endcap)) 1)])
      (define (strip left middle right color)
        (open-look-strip x y n left middle right color))
      (define (ring color)
        (strip 'dflt-button-left-endcap 'dflt-button-middle-1
               'dflt-button-right-endcap color))
      (if (open-look-3d?)
          (begin
            (strip 'button-ul 'button-top-1 'button-ur
                   (if invoked? 'open-look-bg3 'open-look-highlight))
            (strip 'button-ll 'button-bottom-1 'button-lr
                   (if invoked? 'open-look-highlight 'open-look-bg3))
            (strip 'button-left-endcap-fill 'button-fill-1
                   'button-right-endcap-fill
                   (if invoked? 'open-look-bg2 'window-bg))
            (when default? (ring 'open-look-bg3)))
          (begin
            ;; XView erases a button before it draws one (p_btn.c:667-743),
            ;; a column past it too: here within its own box
            (fill-box x y w (open-look-oblong-h) 'window-bg)
            (cond [invoked?
                   (strip 'button-fill-2d-leftendcap 'button-fill-2d-middle-1
                          'button-fill-2d-rightendcap 'open-look-ink)]
                  [default? (ring 'open-look-ink)])
            (strip 'button-outline-left-endcap 'button-outline-middle-1
                   'button-outline-right-endcap 'open-look-ink)))))

  ;; OLGX's abbreviated button from (x, y) (olgx_draw_abbrev_button,
  ;; ol_button.c:553-643), raised or invoked, with glyph inside where its
  ;; menu mark would be.
  (define (open-look-draw-abbrev x y invoked? glyph)
    (let* ([s (- (open-look-button-h) 5)]   ; inside, a pixel clear
           [ink (if (and invoked? (not (open-look-3d?)))
                    'window-bg
                    'open-look-ink)])
      (if (open-look-3d?)
          (begin
            (open-look-glyph x y 'abbrev-menu-ul
                             (if invoked? 'open-look-bg3 'open-look-highlight))
            (open-look-glyph x y 'abbrev-menu-lr
                             (if invoked? 'open-look-highlight 'open-look-bg3))
            (open-look-glyph x y 'abbrev-menu-fill
                             (if invoked? 'open-look-bg2 'window-bg)))
          (let ([aw (open-look-button-w)])
            (when invoked?
              (fill-box (+ x 2) (+ y 2) (- aw 4) (- aw 4) 'window-bg))
            (open-look-glyph x y (if invoked?
                                     'abbrev-menu-button-inverted
                                     'abbrev-menu-button)
                             'open-look-ink)
            ;; the 2D glyph holds its mark: cleared for the glyph
            (fill-box (+ x 2) (+ y 2) s s (if invoked? 'open-look-ink
                                              'window-bg))))
      (ui-draw-glyph (+ x 2) (+ y 2) s s (list (cons 'ink ink)) glyph)))

  ;; OLGX's cut (olgx_draw_text, ol_button.c:758-783): a label wider than w
  ;; loses the character that passes w and the one before it.
  (define (open-look-label-cut str w font)
    (if (<= (text-width str font) w)
        str
        (let loop ([i 0] [sum 0])   ; sum: the first i characters' width
          (if (> sum w)
              (substring str 0 (max 0 (- i 2)))
              (loop (+ i 1)
                    (+ sum (text-width (string (string-ref str i)) font)))))))

  ;; A button: an oblong one with its label, after its glyph if it has one,
  ;; or its glyph alone in an abbreviated one. Pressed or selected, it is
  ;; invoked; primary, the default; disabled, grayed over (OLGX_INACTIVE).
  ;; OPEN LOOK has no hover, and a danger or quiet button is a plain one.
  (define (open-look-button x y w h flags label glyph)
    (let ([on? (lambda (f) (memq f flags))] [x (floor x)])
      (let ([invoked? (or (on? 'pressed) (on? 'selected))])
        (if label
            (let* ([bh (open-look-oblong-h)] [w (floor w)]
                   [y (floor (+ y (/ (- h bh) 2)))]
                   [e (open-look-endcap)] [base (+ y (open-look-oblong-base))]
                   [g (if glyph (ui-glyph-size) 0)] [gw (* 3/2 g)]
                   [ink (if (and invoked? (not (open-look-3d?)))
                            'window-bg
                            'open-look-ink)])
              (open-look-draw-oblong x y w invoked? (on? 'primary))
              (when glyph
                (ui-draw-glyph (+ x e) (- base g) g g (list (cons 'ink ink))
                               glyph))
              (open-look-text (+ x e gw) base
                              (open-look-label-cut label (- w e e gw) 'ui)
                              ink 'ui)
              (when (on? 'disabled) (fill-box x y w bh 'open-look-inactive))
              (when (on? 'focused)
                (ui-draw-focus x y w bh flags (quotient bh 2))))
            (let* ([aw (open-look-button-w)] [ah (open-look-button-h)]
                   [x (floor (+ x (/ (- w aw) 2)))]
                   [y (floor (+ y (/ (- h ah) 2)))])
              (when glyph (open-look-draw-abbrev x y invoked? glyph))
              (when (on? 'disabled) (fill-box x y aw ah 'open-look-inactive))
              (when (on? 'focused) (ui-draw-focus x y aw ah flags 2)))))))

  ;; XView's width: the label's and an end each side (item_set.c:657-679);
  ;; a glyph alone, the abbreviated button's.
  (define (open-look-button-size label glyph)
    (if label
        (values (+ (exact (ceiling (+ (text-width label 'ui)
                                      (if glyph (* 3/2 (ui-glyph-size)) 0))))
                   (* 2 (open-look-endcap)))
                (open-look-oblong-h))
        (values (open-look-button-w) (open-look-button-h))))

  ;; OpenWindows' window color, which you may change and save: olwm's
  ;; frames, and in 3D XView's panes too (the style's window-bg). The ink,
  ;; and the shades OLGX derives from the window color.
  (at-load
   (color-default! 'open-look-window 'bg-1))
  (at-load
   (color-default! 'open-look-ink 'text))
  (at-load
   (color-default! 'open-look-bg2
                   (theme-rule (open-look-shade 'open-look-window 'bg2))))
  (at-load
   (color-default! 'open-look-bg3
                   (theme-rule (open-look-shade 'open-look-window 'bg3))))
  (at-load
   (color-default! 'open-look-highlight
                   (theme-rule (open-look-shade 'open-look-window 'highlight))))
  ;; OLGX_GREY_OUT (ol_init.c:1868-1882): the pane's color, BG1 or white,
  ;; over every pixel where x + y is odd. OLGX counts from its window's
  ;; corner and a stipple from the screen's, so the two agree where the
  ;; pane's corner lies at an even x + y.
  (at-load
   (color-default! 'open-look-inactive (stipple 'window-bg #f ".#" "#.")))

  (at-load
   (define-style open-look "OPEN LOOK"
     'options '(palette
                wallpaper
                ui-font
                ui-font-size
                mono-font
                mono-font-size
                (open-look-depth "Look" (("3D" . 3d) ("2D" . 2d)))
                (open-look-focus "Focus" (("Band" . band) ("Lines" . lines))))
     'palette 'open-look
     'wallpaper 'flat
     'ui-font "Lucida Sans"
     'ui-font-size 12
     'open-look-depth '3d
     'open-look-focus 'band
     'frame-insets 'open-look-insets
     'frame-regions 'open-look-regions
     'frame-under 'open-look-draw-under
     'menu-icons #f   ; olwm's menus are words alone
     ;; only the corners resize
     'frame-edge 0
     ;; XView's panes: the window color in 3D, white in 2D
     'window-bg (theme-rule
                 (theme (if (open-look-3d?) 'open-look-window 'bg-0)))
     ;; the controls
     'control-height (theme-rule (open-look-oblong-h))
     'ui-draw-button 'open-look-button
     'ui-button-size 'open-look-button-size)))
