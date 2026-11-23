;;; (schevana styles adwaita popups) — a part of the Adwaita style
;;; ((schevana styles adwaita)): popovers and their menus, tooltips, dialogs
;;; and their scrim, the calendar, avatars, the busy spinner, navigation
;;; rows, live badges, suggestions and split views.

(library (schevana styles adwaita popups)
  (export
    adwaita-avatar adwaita-busy adwaita-calendar adwaita-day adwaita-dialog
    adwaita-dialog-areas adwaita-dialog-size adwaita-highlight
    adwaita-live-badge adwaita-nav-row adwaita-panel adwaita-scrim
    adwaita-separator adwaita-split adwaita-suggestion adwaita-tooltip
    adwaita-tooltip-size)
  (import (chezscheme)
          (only (schevana base) clamp library-layer)
          (only (schevana core) alpha draw-polyline draw-shadow fill-box
                fill-circle font-line-height linear-gradient pi stroke-box
                stroke-circle text-width)
          (only (schevana kits text) text-fit text-widest)
          (only (schevana kits ui) ui-calendar-areas ui-dialog-areas
                ui-dialog-lines ui-draw-panel ui-glyph-size ui-initials
                ui-live-badge-back ui-live-badge-mark ui-wrap-lines)
          (only (schevana styles adwaita text) adwaita-center adwaita-lines
                adwaita-text adwaita-text-centered adwaita-text-in
                adwaita-text-top)
          (only (schevana styles adwaita controls) adwaita-ring))

  (library-layer looks)

  ;;; ------------------------------------------------------------------
  ;;; popups

  ;; A popup's box: a tooltip's (widgets/_tooltip.scss:1-15) is
  ;; rgb(0 0 6 / 80%) in a hairline of white at 10 %, 9 round; a dialog's
  ;; sheet (widgets/_dialogs.scss:71-84) is 15 round, with its inner edge
  ;; white at 7 %; a toast, libadwaita's, is #505053 and round
  ;; (widgets/_misc.scss:38-69); a menu's and the rest are a popover's
  ;; (widgets/_popovers.scss:7-33): its color in a hairline of black at
  ;; 14 %, 15 round, with two soft shadows.
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
  ;; and 19 % while held; one under the pointer but not chosen is 7 % (a
  ;; sidebar row's, widgets/_sidebars.scss:105-108), or 10 % on a popup.
  (define (adwaita-highlight x y w h flags)
    (fill-box x y w h
              (alpha 'text (cond [(memq 'pressed flags) 0.19]
                                 [(memq 'hover flags)
                                  (if (memq 'popup flags) 0.1 0.07)]
                                 [else 0.1]))
              9))

  ;; A line in the border color (widgets/_misc.scss:21-24).
  (define (adwaita-separator x y w h flags)
    (fill-box x (floor (+ y (/ (- h 1) 2))) w 1 (alpha 'text 0.15)))

  ;; A tooltip's lines: its text in the text's own size, wrapped at 360;
  ;; at most 6 lines, or as many as the text has if it has more.
  (define (adwaita-tooltip-lines text)
    (let ([n (fold-left (lambda (n c) (if (char=? c #\newline) (+ n 1) n))
                        1 (string->list text))])
      (let-values ([(lines cut?) (ui-wrap-lines text 360 'ui (max 6 n))])
        lines)))

  ;; 6 above and below the text, and 10 beside it
  ;; (widgets/_tooltip.scss:13).
  (define (adwaita-tooltip-size text)
    (let ([lines (adwaita-tooltip-lines text)])
      (values (+ 20 (min 360 (text-widest lines 'ui)))
              (+ 12 (* (length lines) (font-line-height 'ui))))))

  (define (adwaita-tooltip x y w h flags text)
    (ui-draw-panel x y w h '(tooltip))
    (adwaita-lines (lambda (line) (+ x 10)) (+ y 6)
                   (adwaita-tooltip-lines text) #xffffff 'ui))

  ;; An alert (AdwAlertDialog: widgets/_message-dialog.scss, adw-alert-
  ;; dialog.c): 300 to 372 wide (175-178), and wider when its buttons need
  ;; it, up to 600; 32 above its heading, a .title-2 (the heading font), 10
  ;; to the body and 9 under it, both centered, 24 from the sides (93-112);
  ;; its buttons in a row of equal widths (615-665), 44 high, 12 round, 12
  ;; apart, 24 from the edges and 12 under the body (114-125); and 18 round
  ;; (1).
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

  ;; Returns ((title x y w h) (message ..) (button x y w h) ...).
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

  ;; The alert's box, over its sheet's shadows, with its heading and its
  ;; body centered, the body as the dialog's text (widgets/
  ;; _message-dialog.scss:53-66).
  (define (adwaita-dialog x y w h flags title message)
    (let* ([areas (ui-dialog-areas x y w h '())]
           [t (cdr (assq 'title areas))] [m (cdr (assq 'message areas))]
           [lh (font-line-height 'ui)])
      (draw-shadow x y w h 18 16)
      (fill-box x y w h 'adwaita-dialog 18)
      (stroke-box x y w h (alpha #xffffff 0.07) 1 18)
      (adwaita-text-centered (car t) (cadr t) (caddr t) (cadddr t)
                             (text-fit title (caddr t) 'heading) 'text 'heading)
      (adwaita-lines (lambda (line)
                       (adwaita-center (car m) (caddr m)
                                       (text-width line 'ui)))
                     (cadr m) (ui-dialog-lines message (caddr m)) 'text 'ui)))

  ;; Under a dialog, the shade at twice its alpha (widgets/_dialogs.scss:
  ;; 72-74).
  (define (adwaita-scrim x y w h flags) (fill-box x y w h 'adwaita-dim))

  ;; The calendar (widgets/_calendar.scss) in a popover: its month bold,
  ;; and the days of the week dimmed.
  (define (adwaita-calendar x y w h flags title)
    (let* ([areas (ui-calendar-areas x y w h)]
           [t (cdr (assq 'title areas))] [wk (cdr (assq 'week areas))]
           [cell (/ (caddr wk) 7)])
      (ui-draw-panel x y w h '())
      (apply adwaita-text-centered (append t (list title 'text 'ui-bold)))
      (do ([i 0 (+ i 1)]) ((= i 7))
        (adwaita-text-centered (+ (car wk) (* i cell)) (cadr wk) cell
                               (cadddr wk) (string (string-ref "MTWTFSS" i))
                               'text-dim 'ui-small))))

  ;; A day (widgets/_calendar.scss:21-56): the chosen one is the accent,
  ;; its number white, 9 round; today has a line 2 high of the border color
  ;; under it; another month's days are at 30 %; the one under the pointer
  ;; is 7 %, and the keys' one is ringed.
  (define (adwaita-day x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [s (- (min w h) 4)]
           [cx (+ x (/ (- w s) 2))] [cy (+ y (/ (- h s) 2))])
      (cond [(on? 'selected) (fill-box cx cy s s 'accent 9)]
            [(on? 'hover) (fill-box cx cy s s (alpha 'text 0.07) 9)])
      (when (and (on? 'today) (not (on? 'selected)))
        (fill-box (+ cx 4) (+ cy s -2) (- s 8) 2 (alpha 'text 0.15)))
      (when (on? 'cursor) (adwaita-ring cx cy s s 9))
      (adwaita-text-centered x y w h label
                             (cond [(on? 'selected) #xffffff]
                                [(on? 'outside) (alpha 'text 0.3)]
                                [else 'text])
                          'ui)))

  ;; A person (AdwAvatar: widgets/_avatar.scss:1-38): round, shaded down
  ;; between two of fourteen colors, with the initials bold in a third; the
  ;; name picks which colors.
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

  ;; The same for a name however it was typed: spaces and capitals do not
  ;; count.
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
      (adwaita-text-centered x y w w (ui-initials name) (car c)
                             'ui-small-bold)))

  ;; The spinner (AdwSpinner: adw-spinner-paintable.c:18-35, 288-374): a
  ;; ring of the text at 15 % and an arc of the text, round at its ends,
  ;; going round once in 1.2 s while its length grows and shrinks; 2.5 wide
  ;; at a radius of 8 and 7 at 32, in proportion between them.
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
  ;; and another under the pointer 7 %; its icon 8 in, and its label 12
  ;; after the icon.
  (define (adwaita-nav-row x y w h flags label icon)
    (let* ([on? (lambda (f) (memq f flags))] [rx (+ x 6)] [rw (- w 12)]
           [g (ui-glyph-size)] [ix (+ rx 8)] [lx (if icon (+ ix g 12) ix)]
           [lh (font-line-height 'ui)])
      (cond [(on? 'selected)
             (fill-box rx y rw h (alpha 'text (if (on? 'hover) 0.13 0.1)) 9)]
            [(on? 'hover) (fill-box rx y rw h (alpha 'text 0.07) 9)])
      (when icon (icon ix (adwaita-center y h g) g flags))
      (adwaita-text-in lx y h (text-fit label (max 0 (- (+ rx rw) lx 8)) 'ui)
                       'text 'ui)
      (when (on? 'focused) (adwaita-ring rx y rw h 9))))

  ;; Whether a view is live, as a pill like a toggle group's (widgets/
  ;; _toggle-group.scss:12-14): the text at 10 %, 15 % under the pointer;
  ;; live, the accent's dot before Live; held, the pause mark, and the way
  ;; back in the accent.
  (define (adwaita-live-badge x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [live? (on? 'checked)]
           [lh (font-line-height 'ui-small)] [m (ui-live-badge-mark)]
           [ty (adwaita-text-top y h 'ui-small)] [my (adwaita-center y h m)]
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
      (adwaita-text tx ty label 'text 'ui-small)
      (unless live?
        (adwaita-text (+ tx (text-width label 'ui-small)) ty
                      ui-live-badge-back 'adwaita-link 'ui-small))
      (when (on? 'focused) (adwaita-ring x y w h (/ h 2)))))

  ;; A suggestion is a menu item (widgets/_menus.scss:130-144).
  (define (adwaita-suggestion x y w h flags label)
    (let ([on? (or (memq 'selected flags) (memq 'hover flags))])
      (when on? (fill-box x y w h (alpha 'text 0.1) 9))
      (adwaita-text-in (+ x 12) y h (text-fit label (max 0 (- w 24)) 'ui)
                       'text 'ui)))

  ;; The line between two panes, where a drag moves it: under the pointer,
  ;; a line of the text at 30 %, and while dragged the accent's (a paned's
  ;; handle, widgets/_paned.scss).
  (define (adwaita-split x y h flags)
    (cond [(memq 'pressed flags) (fill-box x y 1 h 'adwaita-link)]
          [(memq 'hover flags) (fill-box x y 1 h (alpha 'text 0.3))])))
