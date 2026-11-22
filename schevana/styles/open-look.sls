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
;;; under it in the title's font. Everything comes in OPEN LOOK's four sizes,
;;; 10, 12, 14 and 19 point, whichever is nearest the text size. The fixed
;;; parts are OLGX's own glyphs (its fonts, at this file's end) pixel for
;;; pixel, the numbers are olwm's (winframe.c), and the shades follow OLGX's
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
    open-look-size-near open-look-size open-look-by-size open-look-3d?
    open-look-arm open-look-header open-look-top open-look-corner
    open-look-button-w open-look-button-h open-look-pin-w open-look-pin-h
    open-look-ascent open-look-footer-h open-look-footer-base open-look-pop-up?
    open-look-gadget open-look-insets open-look-regions open-look-hsv
    open-look-rgb open-look-shade open-look-glyph open-look-box
    open-look-menu-mark open-look-draw-band open-look-draw-lines
    open-look-draw-corners open-look-draw-button open-look-draw-pin
    open-look-cut open-look-fit-title open-look-text open-look-draw-title
    open-look-draw-footer open-look-draw-under open-look-font-glyph
    open-look-fonts)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) color-default! define-style draw-text fill-box
                font font-ascent rgb stroke-box text-width theme theme-rule
                window-h window-ref window-title window-w)
          (only (schevana kits color) color->fixnum)
          (only (schevana kits text) text-within))

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

  ;; The window color and the ink, which you may change and save, and the
  ;; shades OLGX derives from the window color.
  (at-load
   (color-default! 'open-look-window 'window-bg))
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
     ;; only the corners resize
     'frame-edge 0))

  ;;; ------------------------------------------------------------------
  ;;; OLGX's glyph fonts, the pictures its parts are drawn from. OLGX draws
  ;;; nearly every fixed-size part (resize corners, pushpins, the window
  ;;; button, menu marks, the ends of buttons) as characters of a glyph
  ;;; font, one font for each scale, each drawn by hand at 10, 12, 14 and
  ;;; 19 pixels (75 dpi, one pixel per point). Here are the glyphs the frame
  ;;; draws, generated from olgl10/12/14/19.bdf (X11R6 contrib,
  ;;; fonts/bdf/misc), with the fonts' notice, which every copy must carry:
  ;;;
  ;;;  Copyright 1989 by Sun Microsystems, Inc. Mountain View, CA.
  ;;;
  ;;;  Permission to use, copy, modify, and distribute this software and
  ;;;  its documentation for any purpose and without fee is hereby granted,
  ;;;  provided that the above copyright notices appear in all copies and
  ;;;  that both those copyright notices and this permission notice appear
  ;;;  in supporting documentation, and that the name of Sun Microsystems
  ;;;  not be used in advertising or publicity pertaining to distribution
  ;;;  of the software without specific, written prior permission.  Sun
  ;;;  Microsystems make no representations about the suitability of this
  ;;;  software for any purpose.  It is provided "as is" without express or
  ;;;  implied warranty.
  ;;;
  ;;;  SUN MICROSYSTEMS DISCLAIM ALL WARRANTIES WITH REGARD TO THIS
  ;;;  SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
  ;;;  FITNESS, IN NO EVENT SHALL SUN MICROSYSTEMS BE LIABLE FOR ANY
  ;;;  SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER
  ;;;  RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF
  ;;;  CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
  ;;;  CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

  ;; Returns (w h row ...) of the glyph OLGX calls name (olgx.h, in lower
  ;; case with OLG_ dropped) in the font for size 10, 12, 14 or 19: each row
  ;; is w bits wide, with its leftmost pixel in the highest bit; #f for a
  ;; glyph not here. Its top-left pixel is where OLGX draws it.
  (define (open-look-font-glyph size name)
    (let ([font (assv size open-look-fonts)])
      (and font (let ([g (assq name (cdr font))]) (and g (cdr g))))))

  (define open-look-fonts
    '((10
       ;; 19 OLG_MENU_PIN_OUT
       (menu-pin-out 26 12 #x1c00 #x1206 #x1209 #x13f9 #x1209 #x1ff209 #xff209
         #x13f9 #x18013ff #x2401e0f #x2401e06 #x1801c00)
       ;; 20 OLG_MENU_PIN_IN
       (menu-pin-in 13 13 #x38 #x1c6 #x682 #x901 #x901 #x1101 #x1182 #x10c6
         #x18fe #x83c #xe1c #x1ff8 #x19e0)
       ;; 22 OLG_ABBREV_MENU_BUTTON
       (abbrev-menu-button 14 13 #x1ffc #x2002 #x2003 #x27f3 #x2413 #x2223
         #x2223 #x2143 #x2143 #x2083 #x2003 #x1fff #xffe)
       ;; 23 OLG_ABBREV_MENU_BUTTON_INVERTED
       (abbrev-menu-button-inverted 14 13 #x1ffc #x2002 #x2ffb #x280b #x2beb
         #x2ddb #x2ddb #x2ebb #x2ebb #x2f7b #x2003 #x1fff #xffe)
       ;; 45 VERT_MENU_MARK_UL
       (vert-menu-mark-ul 7 7 #x7f #x40 #x20 #x20 #x10 #x10 #x0)
       ;; 46 VERT_MENU_MARK_LR
       (vert-menu-mark-lr 7 7 #x0 #x1 #x2 #x2 #x4 #x4 #x8)
       ;; 47 VERT_MENU_MARK_FILL
       (vert-menu-mark-fill 7 7 #x0 #x3e #x1c #x1c #x8 #x8 #x0)
       ;; 51 ABBREV_MENU_UL
       (abbrev-menu-ul 14 12 #x1ffe #x2000 #x2000 #x2000 #x2000 #x2000 #x2000
         #x2000 #x2000 #x2000 #x2000 #x0)
       ;; 52 ABBREV_MENU_LR
       (abbrev-menu-lr 14 12 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1ffe)
       ;; 53 ABBREV_MENU_FILL
       (abbrev-menu-fill 14 12 #x0 #x1ffe #x1ffe #x1ffe #x1ffe #x1ffe #x1ffe
         #x1ffe #x1ffe #x1ffe #x1ffe #x0)
       ;; 88 UL_RESIZE_UL
       (ul-resize-ul 10 10 #x3ff #x200 #x200 #x200 #x200 #x200 #x200 #x200 #x200
         #x200)
       ;; 89 UL_RESIZE_LR
       (ul-resize-lr 10 10 #x0 #x1 #x1 #x1 #x3f #x20 #x20 #x20 #x20 #x1e0)
       ;; 90 UL_RESIZE_FILL
       (ul-resize-fill 10 10 #x0 #x1fe #x1fe #x1fe #x1c0 #x1c0 #x1c0 #x1c0 #x1c0
         #x0)
       ;; 91 UR_RESIZE_UL
       (ur-resize-ul 10 10 #x3ff #x200 #x200 #x200 #x200 #x10 #x10 #x10 #x10
         #x10)
       ;; 92 UR_RESIZE_LR
       (ur-resize-lr 10 10 #x0 #x1 #x1 #x1 #x1f1 #x1 #x1 #x1 #x1 #xf)
       ;; 93 UR_RESIZE_FILL
       (ur-resize-fill 10 10 #x0 #x1fe #x1fe #x1fe #xe #xe #xe #xe #xe #x0)
       ;; 94 LR_RESIZE_UL
       (lr-resize-ul 10 10 #x1f #x10 #x10 #x10 #x10 #x3f0 #x200 #x200 #x200
         #x200)
       ;; 95 LR_RESIZE_LR
       (lr-resize-lr 10 10 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1ff)
       ;; 96 LR_RESIZE_FILL
       (lr-resize-fill 10 10 #x0 #xe #xe #xe #xe #xe #x1fe #x1fe #x1fe #x0)
       ;; 97 LL_RESIZE_UL
       (ll-resize-ul 10 10 #x3e0 #x200 #x200 #x200 #x200 #x23f #x200 #x200 #x200
         #x200)
       ;; 98 LL_RESIZE_LR
       (ll-resize-lr 10 10 #x0 #x20 #x20 #x20 #x20 #x0 #x1 #x1 #x1 #x1ff)
       ;; 99 LL_RESIZE_FILL
       (ll-resize-fill 10 11 #x0 #x1c0 #x1c0 #x1c0 #x1c0 #x1c0 #x1fe #x1fe #x1fe
         #x0 #x0)
       ;; 100 PUSHPIN_OUT_TOP
       (pushpin-out-top 26 12 #x1c00 #x1006 #x1008 #x11f8 #x1008 #x1ff008 #x1008
         #x1008 #x1000 #x401000 #x401000 #x1801000)
       ;; 101 PUSHPIN_OUT_BOTTOM
       (pushpin-out-bottom 26 12 #x0 #x200 #x201 #x201 #x201 #x201 #xfe209 #x3f9
         #x18003ff #x2000f0f #x2000e06 #xc00)
       ;; 102 PUSHPIN_OUT_MIDDLE
       (pushpin-out-middle 26 12 #x0 #xc00 #xc06 #xc06 #xdf6 #xdf6 #xdf6 #xc06
         #xc00 #x1800000 #x1800000 #x0)
       ;; 103 PUSHPIN_IN_TOP
       (pushpin-in-top 13 13 #x38 #x1c4 #x680 #x900 #x900 #x1100 #x1180 #x1000
         #x1800 #x800 #x800 #x1000 #x0)
       ;; 104 PUSHPIN_IN_BOTTOM
       (pushpin-in-bottom 13 13 #x0 #x2 #x2 #x1 #x1 #x1 #x2 #xc6 #xfe #x3c #x61c
         #xff8 #x19e0)
       ;; 105 PUSHPIN_IN_MIDDLE
       (pushpin-in-middle 13 13 #x0 #x38 #x17c #x6fe #x6fe #xefe #xe7c #xf38
         #x700 #x7c0 #x1e0 #x0 #x0)
       ;; 162 UL_RESIZE_OUTLINE
       (ul-resize-outline 10 10 #x3ff #x201 #x201 #x201 #x23f #x220 #x220 #x220
         #x220 #x3e0)
       ;; 163 UR_RESIZE_OUTLINE
       (ur-resize-outline 10 10 #x3ff #x201 #x201 #x201 #x3f1 #x11 #x11 #x11
         #x11 #x1f)
       ;; 164 LR_RESIZE_OUTLINE
       (lr-resize-outline 10 10 #x1f #x11 #x11 #x11 #x11 #x3f1 #x201 #x201 #x201
         #x3ff)
       ;; 165 LL_RESIZE_OUTLINE
       (ll-resize-outline 10 10 #x3e0 #x220 #x220 #x220 #x220 #x23f #x201 #x201
         #x201 #x3ff))
      (12
       ;; 19 OLG_MENU_PIN_OUT
       (menu-pin-out 26 12 #x1c00 #x1206 #x1209 #x13f9 #x1209 #x1ff209 #xff209
         #x13f9 #x18013ff #x2401e0f #x2401e06 #x1801c00)
       ;; 20 OLG_MENU_PIN_IN
       (menu-pin-in 13 13 #x38 #x1c6 #x682 #x901 #x901 #x1101 #x1182 #x10c6
         #x18fe #x83c #xe1c #x1ff8 #x19e0)
       ;; 22 OLG_ABBREV_MENU_BUTTON
       (abbrev-menu-button 16 15 #x7ffc #x8002 #x8003 #x8003 #x8fe3 #x8823
         #x8443 #x8443 #x8283 #x8283 #x8103 #x8003 #x8003 #x7fff #x3ffe)
       ;; 23 OLG_ABBREV_MENU_BUTTON_INVERTED
       (abbrev-menu-button-inverted 16 15 #x7ffc #x8002 #xbffb #xbffb #xb01b
         #xb7db #xbbbb #xbbbb #xbd7b #xbd7b #xbefb #xbffb #x8003 #x7ffe #x3ffc)
       ;; 45 VERT_MENU_MARK_UL
       (vert-menu-mark-ul 7 7 #x7f #x40 #x20 #x20 #x10 #x10 #x0)
       ;; 46 VERT_MENU_MARK_LR
       (vert-menu-mark-lr 7 7 #x0 #x1 #x2 #x2 #x4 #x4 #x8)
       ;; 47 VERT_MENU_MARK_FILL
       (vert-menu-mark-fill 7 7 #x0 #x3e #x1c #x1c #x8 #x8 #x0)
       ;; 51 ABBREV_MENU_UL
       (abbrev-menu-ul 16 15 #x7ffe #x8000 #x8000 #x8000 #x8000 #x8000 #x8000
         #x8000 #x8000 #x8000 #x8000 #x8000 #x8000 #x8000 #x0)
       ;; 52 ABBREV_MENU_LR
       (abbrev-menu-lr 16 15 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x7ffe)
       ;; 53 ABBREV_MENU_FILL
       (abbrev-menu-fill 16 15 #x0 #x7ffe #x7ffe #x7ffe #x7ffe #x7ffe #x7ffe
         #x7ffe #x7ffe #x7ffe #x7ffe #x7ffe #x7ffe #x7ffe #x0)
       ;; 88 UL_RESIZE_UL
       (ul-resize-ul 11 11 #x7ff #x400 #x400 #x400 #x400 #x400 #x400 #x400 #x400
         #x400 #x400)
       ;; 89 UL_RESIZE_LR
       (ul-resize-lr 11 11 #x0 #x1 #x1 #x1 #x7f #x40 #x40 #x40 #x40 #x40 #x3c0)
       ;; 90 UL_RESIZE_FILL
       (ul-resize-fill 11 11 #x0 #x3fe #x3fe #x3fe #x380 #x380 #x380 #x380 #x380
         #x380 #x0)
       ;; 91 UR_RESIZE_UL
       (ur-resize-ul 11 11 #x7ff #x400 #x400 #x400 #x400 #x10 #x10 #x10 #x10
         #x10 #x10)
       ;; 92 UR_RESIZE_LR
       (ur-resize-lr 11 11 #x0 #x1 #x1 #x1 #x3f1 #x1 #x1 #x1 #x1 #x1 #xf)
       ;; 93 UR_RESIZE_FILL
       (ur-resize-fill 11 11 #x0 #x3fe #x3fe #x3fe #xe #xe #xe #xe #xe #xe #x0)
       ;; 94 LR_RESIZE_UL
       (lr-resize-ul 11 11 #x1f #x10 #x10 #x10 #x10 #x10 #x7f0 #x400 #x400 #x400
         #x400)
       ;; 95 LR_RESIZE_LR
       (lr-resize-lr 11 11 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x3ff)
       ;; 96 LR_RESIZE_FILL
       (lr-resize-fill 11 11 #x0 #xe #xe #xe #xe #xe #xe #x3fe #x3fe #x3fe #x0)
       ;; 97 LL_RESIZE_UL
       (ll-resize-ul 11 11 #x7c0 #x400 #x400 #x400 #x400 #x400 #x43f #x400 #x400
         #x400 #x400)
       ;; 98 LL_RESIZE_LR
       (ll-resize-lr 11 11 #x0 #x40 #x40 #x40 #x40 #x40 #x40 #x1 #x1 #x1 #x3ff)
       ;; 99 LL_RESIZE_FILL
       (ll-resize-fill 11 11 #x0 #x380 #x380 #x380 #x380 #x380 #x380 #x3fe #x3fe
         #x3fe #x0)
       ;; 100 PUSHPIN_OUT_TOP
       (pushpin-out-top 26 12 #x1c00 #x1006 #x1008 #x11f8 #x1008 #x1ff008 #x1008
         #x1008 #x1000 #x401000 #x401000 #x1801000)
       ;; 101 PUSHPIN_OUT_BOTTOM
       (pushpin-out-bottom 26 12 #x0 #x200 #x201 #x201 #x201 #x201 #xfe209 #x3f9
         #x18003ff #x2000f0f #x2000e06 #xc00)
       ;; 102 PUSHPIN_OUT_MIDDLE
       (pushpin-out-middle 26 12 #x0 #xc00 #xc06 #xc06 #xdf6 #xdf6 #xdf6 #xc06
         #xc00 #x1800000 #x1800000 #x0)
       ;; 103 PUSHPIN_IN_TOP
       (pushpin-in-top 13 13 #x38 #x1c4 #x680 #x900 #x900 #x1100 #x1180 #x1000
         #x1800 #x800 #x800 #x1000 #x0)
       ;; 104 PUSHPIN_IN_BOTTOM
       (pushpin-in-bottom 13 13 #x0 #x2 #x2 #x1 #x1 #x1 #x2 #xc6 #xfe #x3c #x61c
         #xff8 #x19e0)
       ;; 105 PUSHPIN_IN_MIDDLE
       (pushpin-in-middle 13 13 #x0 #x38 #x17c #x6fe #x6fe #xefe #xe7c #xf38
         #x700 #x7c0 #x1e0 #x0 #x0)
       ;; 162 UL_RESIZE_OUTLINE
       (ul-resize-outline 11 11 #x7ff #x401 #x401 #x401 #x47f #x440 #x440 #x440
         #x440 #x440 #x7c0)
       ;; 163 UR_RESIZE_OUTLINE
       (ur-resize-outline 11 11 #x7ff #x401 #x401 #x401 #x7f1 #x11 #x11 #x11
         #x11 #x11 #x1f)
       ;; 164 LR_RESIZE_OUTLINE
       (lr-resize-outline 11 11 #x1f #x11 #x11 #x11 #x11 #x11 #x7f1 #x401 #x401
         #x401 #x7ff)
       ;; 165 LL_RESIZE_OUTLINE
       (ll-resize-outline 11 11 #x7c0 #x440 #x440 #x440 #x440 #x440 #x47f #x401
         #x401 #x401 #x7ff))
      (14
       ;; 19 OLG_MENU_PIN_OUT
       (menu-pin-out 29 14 #x3800 #x2406 #x2409 #x27f9 #x2409 #x2409 #xffe409
         #x7fe409 #x2409 #x27f9 #xc0027ff #x12003c0f #x12003c06 #xc003800)
       ;; 20 OLG_MENU_PIN_IN
       (menu-pin-in 15 15 #x70 #x38c #xe02 #x1202 #x2401 #x2401 #x4401 #x4603
         #x4202 #x638e #x21fc #x307c #x3c38 #x7ff0 #x6000)
       ;; 22 OLG_ABBREV_MENU_BUTTON
       (abbrev-menu-button 18 17 #x1fffc #x20002 #x20003 #x20003 #x23fe3 #x22023
         #x21043 #x21043 #x20883 #x20883 #x20503 #x20503 #x20203 #x20003 #x20003
         #x1ffff #xfffe)
       ;; 23 OLG_ABBREV_MENU_BUTTON_INVERTED
       (abbrev-menu-button-inverted 18 17 #x1fffc #x20002 #x2fffb #x2fffb
         #x2c01b #x2dfdb #x2efbb #x2efbb #x2f77b #x2f77b #x2fafb #x2fafb #x2fdfb
         #x2fffb #x20003 #x1ffff #xfffe)
       ;; 45 VERT_MENU_MARK_UL
       (vert-menu-mark-ul 11 11 #x7ff #x400 #x200 #x200 #x100 #x100 #x80 #x80
         #x40 #x40 #x0)
       ;; 46 VERT_MENU_MARK_LR
       (vert-menu-mark-lr 11 11 #x0 #x1 #x2 #x2 #x4 #x4 #x8 #x8 #x10 #x10 #x20)
       ;; 47 VERT_MENU_MARK_FILL
       (vert-menu-mark-fill 11 11 #x0 #x3fe #x1fc #x1fc #xf8 #xf8 #x70 #x70 #x20
         #x20 #x0)
       ;; 51 ABBREV_MENU_UL
       (abbrev-menu-ul 18 16 #x1fffe #x20000 #x20000 #x20000 #x20000 #x20000
         #x20000 #x20000 #x20000 #x20000 #x20000 #x20000 #x20000 #x20000 #x20000
         #x0)
       ;; 52 ABBREV_MENU_LR
       (abbrev-menu-lr 18 16 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x1 #x1fffe)
       ;; 53 ABBREV_MENU_FILL
       (abbrev-menu-fill 18 16 #x0 #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe
         #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe #x1fffe
         #x0)
       ;; 88 UL_RESIZE_UL
       (ul-resize-ul 12 12 #xfff #x800 #x800 #x800 #x800 #x800 #x800 #x800 #x800
         #x800 #x800 #x800)
       ;; 89 UL_RESIZE_LR
       (ul-resize-lr 12 12 #x0 #x1 #x1 #x1 #x1 #x7f #x40 #x40 #x40 #x40 #x40
         #x7c0)
       ;; 90 UL_RESIZE_FILL
       (ul-resize-fill 12 12 #x0 #x7fe #x7fe #x7fe #x7fe #x780 #x780 #x780 #x780
         #x780 #x780 #x0)
       ;; 91 UR_RESIZE_UL
       (ur-resize-ul 12 12 #xfff #x800 #x800 #x800 #x800 #x800 #x20 #x20 #x20
         #x20 #x20 #x20)
       ;; 92 UR_RESIZE_LR
       (ur-resize-lr 12 12 #x0 #x1 #x1 #x1 #x1 #x7e1 #x1 #x1 #x1 #x1 #x1 #x1f)
       ;; 93 UR_RESIZE_FILL
       (ur-resize-fill 12 12 #x0 #x7fe #x7fe #x7fe #x7fe #x1e #x1e #x1e #x1e
         #x1e #x1e #x0)
       ;; 94 LR_RESIZE_UL
       (lr-resize-ul 12 12 #x3f #x20 #x20 #x20 #x20 #x20 #xfe0 #x800 #x800 #x800
         #x800 #x800)
       ;; 95 LR_RESIZE_LR
       (lr-resize-lr 12 12 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x7ff)
       ;; 96 LR_RESIZE_FILL
       (lr-resize-fill 12 12 #x0 #x1e #x1e #x1e #x1e #x1e #x1e #x7fe #x7fe #x7fe
         #x7fe #x0)
       ;; 97 LL_RESIZE_UL
       (ll-resize-ul 12 12 #xf80 #x800 #x800 #x800 #x800 #x800 #x87f #x800 #x800
         #x800 #x800 #x800)
       ;; 98 LL_RESIZE_LR
       (ll-resize-lr 12 12 #x0 #x40 #x40 #x40 #x40 #x40 #x0 #x1 #x1 #x1 #x1
         #x7ff)
       ;; 99 LL_RESIZE_FILL
       (ll-resize-fill 12 12 #x0 #x780 #x780 #x780 #x780 #x780 #x780 #x7fe #x7fe
         #x7fe #x7fe #x0)
       ;; 100 PUSHPIN_OUT_TOP
       (pushpin-out-top 28 14 #x1c00 #x1006 #x1008 #x11f8 #x1008 #x1008 #x7ff008
         #x1008 #x1008 #x1008 #x1000 #x1001000 #x1001000 #x6001000)
       ;; 101 PUSHPIN_OUT_BOTTOM
       (pushpin-out-bottom 28 14 #x0 #x200 #x201 #x201 #x201 #x201 #x201
         #x3fe209 #x3f9 #x3ff #x600020f #x8000e06 #x8000e00 #xc00)
       ;; 102 PUSHPIN_OUT_MIDDLE
       (pushpin-out-middle 28 14 #x0 #xc00 #xc06 #xc06 #xdf6 #xdf6 #xdf6 #xdf6
         #xdf6 #xc06 #xc00 #x6000000 #x6000000 #x0)
       ;; 103 PUSHPIN_IN_TOP
       (pushpin-in-top 15 15 #x70 #x388 #xe00 #x1200 #x2400 #x2400 #x4400 #x4600
         #x4000 #x6000 #x2000 #x2000 #x2000 #x4000 #x0)
       ;; 104 PUSHPIN_IN_BOTTOM
       (pushpin-in-bottom 15 15 #x0 #x4 #x2 #x2 #x1 #x1 #x1 #x3 #x202 #x38e
         #x1fc #x107c #x1c38 #x3ff0 #x63c0)
       ;; 105 PUSHPIN_IN_MIDDLE
       (pushpin-in-middle 15 15 #x0 #x70 #x1fc #xdfc #x1bfe #x1bfe #x3bfe #x39fc
         #x3dfc #x1c70 #x1e00 #xf80 #x3c0 #x0 #x0)
       ;; 162 UL_RESIZE_OUTLINE
       (ul-resize-outline 12 12 #xfff #x801 #x801 #x801 #x801 #x87f #x840 #x840
         #x840 #x840 #x840 #xfc0)
       ;; 163 UR_RESIZE_OUTLINE
       (ur-resize-outline 12 12 #xfff #x801 #x801 #x801 #x801 #xfe1 #x21 #x21
         #x21 #x21 #x21 #x3f)
       ;; 164 LR_RESIZE_OUTLINE
       (lr-resize-outline 12 12 #x3f #x21 #x21 #x21 #x21 #x21 #xfe1 #x801 #x801
         #x801 #x801 #xfff)
       ;; 165 LL_RESIZE_OUTLINE
       (ll-resize-outline 12 12 #xfc0 #x840 #x840 #x840 #x840 #x840 #x87f #x801
         #x801 #x801 #x801 #xfff))
      (19
       ;; 19 OLG_MENU_PIN_OUT
       (menu-pin-out 29 14 #x3800 #x2406 #x2409 #x27f9 #x2409 #x2409 #xffe409
         #x7fe409 #x2409 #x27f9 #xc0027ff #x12003c0f #x12003c06 #xc003800)
       ;; 20 OLG_MENU_PIN_IN
       (menu-pin-in 15 15 #x70 #x38c #xe02 #x1202 #x2401 #x2401 #x4401 #x4603
         #x4202 #x638e #x21fc #x307c #x3c38 #x7ff0 #x6000)
       ;; 22 OLG_ABBREV_MENU_BUTTON
       (abbrev-menu-button 22 21 #xffff8 #x100004 #x200002 #x200003 #x200003
         #x21ffc3 #x210043 #x208083 #x208083 #x204103 #x204103 #x202203 #x202203
         #x201403 #x201403 #x200803 #x200003 #x200003 #x100007 #xffffe #x7fffc)
       ;; 23 OLG_ABBREV_MENU_BUTTON_INVERTED
       (abbrev-menu-button-inverted 22 21 #xffff8 #x100004 #x27fff2 #x2ffffb
         #x2ffffb #x2e003b #x2effbb #x2f7f7b #x2f7f7b #x2fbefb #x2fbefb #x2fddfb
         #x2fddfb #x2febfb #x2febfb #x2ff7fb #x2ffffb #x27fff3 #x100007 #xffffe
         #x7fffc)
       ;; 45 VERT_MENU_MARK_UL
       (vert-menu-mark-ul 13 13 #x1fff #x1000 #x800 #x800 #x400 #x400 #x200
         #x200 #x100 #x100 #x80 #x80 #x0)
       ;; 46 VERT_MENU_MARK_LR
       (vert-menu-mark-lr 13 13 #x0 #x1 #x2 #x2 #x4 #x4 #x8 #x8 #x10 #x10 #x20
         #x20 #x40)
       ;; 47 VERT_MENU_MARK_FILL
       (vert-menu-mark-fill 13 13 #x0 #xffe #x7fc #x7fc #x3f8 #x3f8 #x1f0 #x1f0
         #xe0 #xe0 #x40 #x40 #x0)
       ;; 51 ABBREV_MENU_UL
       (abbrev-menu-ul 21 21 #x7fffc #x80000 #x100000 #x100000 #x100000 #x100000
         #x100000 #x100000 #x100000 #x100000 #x100000 #x100000 #x100000 #x100000
         #x100000 #x100000 #x100000 #x100000 #x100000 #x80000 #x0)
       ;; 52 ABBREV_MENU_LR
       (abbrev-menu-lr 21 21 #x0 #x2 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x1 #x1 #x1 #x1 #x1 #x2 #x7fffc)
       ;; 53 ABBREV_MENU_FILL
       (abbrev-menu-fill 21 21 #x0 #x7fffc #xffffe #xffffe #xffffe #xffffe
         #xffffe #xffffe #xffffe #xffffe #xffffe #xffffe #xffffe #xffffe #xffffe
         #xffffe #xffffe #xffffe #xffffe #x7fffc #x0)
       ;; 88 UL_RESIZE_UL
       (ul-resize-ul 14 14 #x3fff #x2000 #x2000 #x2000 #x2000 #x2000 #x2000
         #x2000 #x2000 #x2000 #x2000 #x2000 #x2000 #x2000)
       ;; 89 UL_RESIZE_LR
       (ul-resize-lr 14 14 #x0 #x1 #x1 #x1 #x1 #x1ff #x100 #x100 #x100 #x100
         #x100 #x100 #x100 #x1f00)
       ;; 90 UL_RESIZE_FILL
       (ul-resize-fill 14 14 #x0 #x1ffe #x1ffe #x1ffe #x1ffe #x1e00 #x1e00
         #x1e00 #x1e00 #x1e00 #x1e00 #x1e00 #x1e00 #x0)
       ;; 91 UR_RESIZE_UL
       (ur-resize-ul 14 14 #x3fff #x2000 #x2000 #x2000 #x2000 #x2000 #x20 #x20
         #x20 #x20 #x20 #x20 #x20 #x20)
       ;; 92 UR_RESIZE_LR
       (ur-resize-lr 14 14 #x0 #x1 #x1 #x1 #x1 #x1fc1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1 #x1f)
       ;; 93 UR_RESIZE_FILL
       (ur-resize-fill 14 14 #x0 #x1ffe #x1ffe #x1ffe #x1ffe #x1e #x1e #x1e #x1e
         #x1e #x1e #x1e #x1e #x0)
       ;; 94 LR_RESIZE_UL
       (lr-resize-ul 14 14 #x3f #x20 #x20 #x20 #x20 #x20 #x20 #x20 #x3fe0 #x2000
         #x2000 #x2000 #x2000 #x2000)
       ;; 95 LR_RESIZE_LR
       (lr-resize-lr 14 14 #x0 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1 #x1
         #x1fff)
       ;; 96 LR_RESIZE_FILL
       (lr-resize-fill 14 14 #x0 #x1e #x1e #x1e #x1e #x1e #x1e #x1e #x1e #x1ffe
         #x1ffe #x1ffe #x1ffe #x0)
       ;; 97 LL_RESIZE_UL
       (ll-resize-ul 14 14 #x3f00 #x2000 #x2000 #x2000 #x2000 #x2000 #x2000
         #x2000 #x20ff #x2000 #x2000 #x2000 #x2000 #x2000)
       ;; 98 LL_RESIZE_LR
       (ll-resize-lr 14 14 #x0 #x100 #x100 #x100 #x100 #x100 #x100 #x100 #x0 #x1
         #x1 #x1 #x1 #x1fff)
       ;; 99 LL_RESIZE_FILL
       (ll-resize-fill 13 13 #x0 #xf00 #xf00 #xf00 #xf00 #xf00 #xf00 #xf00 #xf00
         #xfff #xfff #xfff #xfff)
       ;; 100 PUSHPIN_OUT_TOP
       (pushpin-out-top 28 14 #x1c00 #x1006 #x1008 #x11f8 #x1008 #x1008 #x7ff008
         #x1008 #x1008 #x1008 #x1000 #x1001000 #x1001000 #x6001000)
       ;; 101 PUSHPIN_OUT_BOTTOM
       (pushpin-out-bottom 28 14 #x0 #x200 #x201 #x201 #x201 #x201 #x201
         #x3fe209 #x3f9 #x3ff #x600020f #x8000e06 #x8000e00 #xc00)
       ;; 102 PUSHPIN_OUT_MIDDLE
       (pushpin-out-middle 28 14 #x0 #xc00 #xc06 #xc06 #xdf6 #xdf6 #xdf6 #xdf6
         #xdf6 #xc06 #xc00 #x6000000 #x6000000 #x0)
       ;; 103 PUSHPIN_IN_TOP
       (pushpin-in-top 15 15 #x70 #x388 #xe00 #x1200 #x2400 #x2400 #x4400 #x4600
         #x4000 #x6000 #x2000 #x2000 #x2000 #x4000 #x0)
       ;; 104 PUSHPIN_IN_BOTTOM
       (pushpin-in-bottom 15 15 #x0 #x4 #x2 #x2 #x1 #x1 #x1 #x3 #x202 #x38e
         #x1fc #x107c #x1c38 #x3ff0 #x63c0)
       ;; 105 PUSHPIN_IN_MIDDLE
       (pushpin-in-middle 15 15 #x0 #x70 #x1fc #xdfc #x1bfe #x1bfe #x3bfe #x39fc
         #x3dfc #x1c70 #x1e00 #xf80 #x3c0 #x0 #x0)
       ;; 162 UL_RESIZE_OUTLINE
       (ul-resize-outline 14 14 #x3fff #x2001 #x2001 #x2001 #x2001 #x21ff #x2100
         #x2100 #x2100 #x2100 #x2100 #x2100 #x2100 #x3f00)
       ;; 163 UR_RESIZE_OUTLINE
       (ur-resize-outline 14 14 #x3fff #x2001 #x2001 #x2001 #x2001 #x3fe1 #x21
         #x21 #x21 #x21 #x21 #x21 #x21 #x3f)
       ;; 164 LR_RESIZE_OUTLINE
       (lr-resize-outline 14 14 #x3f #x21 #x21 #x21 #x21 #x21 #x21 #x21 #x3fe1
         #x2001 #x2001 #x2001 #x2001 #x3fff)
       ;; 165 LL_RESIZE_OUTLINE
       (ll-resize-outline 14 14 #x3f00 #x2100 #x2100 #x2100 #x2100 #x2100 #x2100
         #x2100 #x21ff #x2001 #x2001 #x2001 #x2001 #x3fff)))))
