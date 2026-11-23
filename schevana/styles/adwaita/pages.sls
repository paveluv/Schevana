;;; (schevana styles adwaita pages) — a part of the Adwaita style
;;; ((schevana styles adwaita)): boxed lists and their rows, status pages
;;; and banners.

(library (schevana styles adwaita pages)
  (export
    adwaita-add-row adwaita-add-row-height adwaita-banner adwaita-banner-height
    adwaita-row adwaita-row-areas adwaita-row-height adwaita-rows
    adwaita-rows-radius adwaita-rows-spacing adwaita-status-page
    adwaita-status-page-areas)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) alpha draw-shadow fill-box font-line-height mix
                stroke-box text-width)
          (only (schevana kits text) text-fit)
          (only (schevana kits ui) ui-control-height ui-draw-glyph ui-glyph-size
                ui-label-lines ui-status-page-areas ui-banner-areas)
          (only (schevana styles adwaita text) adwaita-center adwaita-lines
                adwaita-text adwaita-text-height adwaita-text-in)
          (only (schevana styles adwaita controls) adwaita-button-size
                adwaita-ring))

  (library-layer looks)

  ;;; ------------------------------------------------------------------
  ;;; boxed lists, status pages and banners

  ;; A preferences group (widgets/_preferences.scss:6-18): its title a
  ;; heading and its description dimmed, 6 apart, with the list 12 under
  ;; them.
  (define (adwaita-rows-spacing) (values 6 12))

  ;; An action row (widgets/_lists.scss:16-19, 118-163, 334-338): its
  ;; header is at least 50 high, with its title and subtitle 6 from its top
  ;; and bottom and 3 apart, inside 2 of padding, over a line of 1.
  (define (adwaita-row-height title subtitle)
    (+ 2 2 1 (max 50 (+ 12 (adwaita-text-height 'ui)
                        (if subtitle (+ 3 (adwaita-text-height 'ui-small))
                            0)))))

  ;; The header, 2 in from the row's edges and over its line; what it
  ;; holds sits 12 in from the header's sides, 6 apart, and a prefix 6 more
  ;; from the title (widgets/_lists.scss:124-163).
  (define (adwaita-row-areas x y w h pw sw)
    (let* ([hy (+ y 2)] [hh (max 0 (- h 5))]
           [tx (if (> pw 0) (+ x 14 pw 12) (+ x 14))]
           [sx (- (+ x w) 14 sw)]
           [te (if (> sw 0) (- sx 6) (- (+ x w) 14))])
      (list (list 'prefix (+ x 14) hy pw hh)
            (list 'title tx hy (max 0 (- te tx)) hh)
            (list 'suffix sx hy sw hh))))

  (define (adwaita-rows-radius) 12)

  ;; A boxed list is a card (widgets/_lists.scss:507-541, _misc.scss:
  ;; 194-201): the card's color, 12 round, over two soft shadows, in its
  ;; hairline of rgb(0 0 6 / 3%).
  (define (adwaita-rows x y w h flags)
    (if (memq 'over flags)
        (stroke-box x y w h (alpha #x000006 0.03) 1 12)
        (begin (draw-shadow x y w h 12 4)
               (fill-box x y w h 'adwaita-card 12))))

  ;; A row of it (widgets/_lists.scss:118-122, 334-352, 528-538): if a
  ;; press acts on it, the text at 3 % under the pointer and 8 % pressed;
  ;; chosen, the accent at 25 %; a line of the card's shade under each row
  ;; but the last; its title in the text's color, and its subtitle smaller
  ;; and dimmed; focused, the ring a pixel in.
  (define (adwaita-row x y w h flags title subtitle tx tw)
    (let* ([on? (lambda (f) (memq f flags))]
           [lh (adwaita-text-height 'ui)] [sh (adwaita-text-height 'ui-small)]
           [th (if subtitle (+ lh 3 sh) lh)]
           [ty (adwaita-center (+ y 2) (- h 5) th)]
           [ink (lambda (c) (if (on? 'disabled) (alpha c 0.5) c))])
      (cond [(on? 'selected) (fill-box x y w h (alpha 'accent 0.25))]
            [(and (on? 'activatable) (on? 'pressed))
             (fill-box x y w h (alpha 'text 0.08))]
            [(and (on? 'activatable) (on? 'hover))
             (fill-box x y w h (alpha 'text 0.03))])
      (unless (on? 'last)
        (fill-box x (+ y h -1) w 1 'adwaita-card-shade))
      (when title
        (adwaita-text tx ty (text-fit title tw 'ui) (ink 'text) 'ui))
      (when subtitle
        (adwaita-text tx (+ ty lh 3) (text-fit subtitle tw 'ui-small)
                      (ink 'text-dim) 'ui-small))
      (when (on? 'focused)
        (adwaita-ring (+ x 1) (+ y 1) (- w 2) (- h 2) 11))))

  ;; A button row (AdwButtonRow: widgets/_lists.scss:440-455, adw-button-
  ;; row.ui) that adds a row: inside the row's 2 of padding, a box 40 high,
  ;; 12 in from its sides, with a plus and the title, a heading, centered
  ;; in it together, 6 apart; under the pointer and pressed, as an
  ;; activatable row; it is the last row, so it has no line under it.
  (define (adwaita-add-row-height) 44)

  (define (adwaita-add-row x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [g (ui-glyph-size)]
           [bx (+ x 14)] [bw (max 0 (- w 28))] [by (+ y 2)] [bh (- h 4)]
           [label (text-fit label (max 0 (- bw g 6)) 'ui-bold)]
           [x0 (adwaita-center bx bw (+ g 6 (text-width label 'ui-bold)))]
           [ink (if (on? 'disabled) (alpha 'text 0.5) 'text)])
      (cond [(on? 'pressed) (fill-box x y w h (alpha 'text 0.08))]
            [(on? 'hover) (fill-box x y w h (alpha 'text 0.03))])
      (ui-draw-glyph x0 (adwaita-center by bh g) g g (list (cons 'ink ink))
                     'plus)
      (adwaita-text-in (+ x0 g 6) by bh label ink 'ui-bold)
      (when (on? 'focused)
        (adwaita-ring (+ x 1) (+ y 1) (- w 2) (- h 2) 11))))

  ;; A status page's title: .title-1, or .title-2 when compact (widgets/
  ;; _misc.scss:147-149, 166-168).
  (define (adwaita-status-title-font flags)
    (if (memq 'compact flags) 'heading 'adwaita-title-1))

  ;; A status page (widgets/_misc.scss:122-190): its icon 128 square (96
  ;; when compact), 36 over the title (its 24 margin and the 12 between; 24
  ;; when compact), the description 12 under the title, the button 36 under
  ;; them (24 when compact), and the text 12 in from the sides.
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

  ;; Its icon is the text at 55 % (widgets/_misc.scss:134-136), and the
  ;; title and the description are centered.
  (define (adwaita-status-page x y w h flags glyph title description label)
    (let* ([areas (ui-status-page-areas x y w h flags title description
                                        label)]
           [g (cdr (assq 'glyph areas))] [t (cdr (assq 'title areas))]
           [d (cdr (assq 'description areas))] [s (caddr g)]
           [tf (adwaita-status-title-font flags)])
      (if (procedure? glyph)
          (glyph (car g) (cadr g) s '(dim))
          (ui-draw-glyph (car g) (cadr g) s s '((ink . text-dim)) glyph))
      (adwaita-lines (lambda (line)
                       (adwaita-center (car t) (caddr t) (text-width line tf)))
                     (cadr t) (ui-label-lines title (caddr t) tf) 'text tf)
      (when description
        (adwaita-lines (lambda (line)
                         (adwaita-center (car d) (caddr d)
                                         (text-width line 'ui)))
                       (cadr d) (ui-label-lines description (caddr d) 'ui)
                       'text 'ui))))

  ;; A banner (AdwBanner: widgets/_toolbars.scss:235-254): its button sits
  ;; 6 inside it, so it is a control's height and 12 more; its color is
  ;; #7d7d83 mixed 30 % into the window's color, and its title a heading.
  (define (adwaita-banner-height) (+ 12 (ui-control-height)))

  (define (adwaita-banner x y w h flags title label)
    (let ([t (cdr (assq 'title (ui-banner-areas x y w h title label)))])
      (fill-box x y w h (mix 'bg-1 #x7d7d83 0.3))
      (adwaita-text-in (car t) y h (text-fit title (caddr t) 'ui-bold) 'text
                       'ui-bold))))
