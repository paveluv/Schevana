;;; (schevana styles adwaita fields) — a part of the Adwaita style
;;; ((schevana styles adwaita)): entries, dropdowns, steppers and tags,
;;; cards, scroll bars and tables.

(library (schevana styles adwaita fields)
  (export
    adwaita-card adwaita-card-radius adwaita-chip adwaita-chip-size
    adwaita-dropdown adwaita-dropdown-size adwaita-field adwaita-scrollbar
    adwaita-scrollbar-areas adwaita-stepper-areas adwaita-table-cell-inset
    adwaita-table-divider adwaita-table-header adwaita-table-row
    adwaita-text-box-areas)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) alpha fill-box fill-circle font-line-height
                stroke-box text-width with-clip)
          (only (schevana kits app) app-color)
          (only (schevana kits text) text-fit text-widest)
          (only (schevana kits ui) ui-chip-areas ui-control-height ui-draw-glyph
                ui-glyph-size ui-joined-span ui-small-glyph-size ui-text-box-top
                ui-scrollbar-width ui-card-radius)
          (schevana styles adwaita text)
          (schevana styles adwaita controls))

  (library-layer looks)

  ;;; ------------------------------------------------------------------
  ;;; entries, dropdowns, steppers and tags

  ;; An entry (widgets/_entries.scss:1-40): the text at 10 % behind it, 9
  ;; round, with no border; focused, it has the ring inside it however the
  ;; focus came (17). A text area is drawn as one too.
  (define (adwaita-field x y w h flags)
    (adwaita-box x y w h (alpha 'text 0.1) 9 flags)
    (when (memq 'focused flags)
      (if (or (memq 'join-left flags) (memq 'join-right flags))
          (let-values ([(bx bw) (ui-joined-span x w 9 flags)])
            (with-clip (x y w h) (adwaita-ring bx y bw h 9)))
          (adwaita-ring x y w h 9))))

  ;; Its text is 9 in from either side (widgets/_entries.scss:5-6), or
  ;; after a search glyph and 6 (8); an area's lines start 6 down.
  (define (adwaita-text-box-areas x y w h flags)
    (let* ([left (if (memq 'search flags) (+ 9 (ui-glyph-size) 6) 9)]
           [bw (ui-scrollbar-width)]
           [font (if (memq 'large flags) 'heading 'ui)]
           [top (ui-text-box-top h flags font 6)])
      (list (list 'edit (+ x left) (+ y top) (max 0 (- w left 9))
                  (max 0 (- h top top)) font)
            (list 'bar (- (+ x w) bw) y bw h))))

  ;; A dropdown (widgets/_dropdowns.scss:1-14): a button holding the
  ;; choice, bold, 9 in, and the pan-down arrow, 16 square, 6 after the
  ;; text and 9 from the end; while open, it is pressed in.
  (define (adwaita-dropdown x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [g (ui-glyph-size)]
           [lh (font-line-height 'ui-bold)])
      (fill-box x y w h
                (alpha 'text (cond [(or (on? 'open) (on? 'pressed)) 0.3]
                                   [(on? 'hover) 0.15]
                                   [else 0.1]))
                9)
      (adwaita-text-in (+ x 9) y h
                       (text-fit label (max 0 (- w 9 6 g 9)) 'ui-bold)
                       (cond [(on? 'set) 'adwaita-link]
                             [(on? 'placeholder) 'text-dim]
                             [else 'text])
                       'ui-bold)
      (ui-draw-glyph (- (+ x w) 9 g) (adwaita-center y h g) g g
                     '((ink . text)) 'chevron-down)
      (when (on? 'focused) (adwaita-ring x y w h 9))))

  (define (adwaita-dropdown-size labels)
    (values (min (* 10 (font-line-height 'ui))
                 (+ 9 (text-widest labels 'ui-bold) 6 (ui-glyph-size) 9))
            (ui-control-height)))

  ;; A spin button (widgets/_spin-button.scss): the number at the start,
  ;; then - and +, each a control's square, in one box; each piece shares a
  ;; pixel with the next, where a line shows, as GTK's separators do.
  (define (adwaita-stepper-areas x y w h)
    (let ([b (ui-control-height)])
      (list (list 'field x y (- w b b -1) h 'join-right)
            (list 'down (- (+ x w) b b) y (+ b 1) h 'join-left 'join-right)
            (list 'up (- (+ x w) b) y b h 'join-left))))

  ;; A tag, which GNOME has no widget for, made as its designers make small
  ;; things: a pill of the text at 10 % (a toggle group's tint, widgets/
  ;; _toggle-group.scss:12-14), its label a caption (widgets/_labels.scss:
  ;; 68-71), and the tag's own color as a 6-pixel dot before it, as GNOME
  ;; marks what needs attention (_common.scss:106-120); a removable one's ×
  ;; is a round flat button at its end.
  (define (adwaita-chip x y w h flags label)
    (let* ([sh (font-line-height 'ui-small)] [g (ui-small-glyph-size)]
           [rem? (memq 'removable flags)])
      (fill-box x y w h (alpha 'text 0.1) (/ h 2))
      (fill-circle (+ x 13) (+ y (/ h 2)) 3
                   (app-color (string->symbol label)))
      (adwaita-text-in (+ x 22) y h
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
  ;; drew in it, so of the card's shadows, which would cover that, only its
  ;; hairline, the text at 12 %; under the pointer, a tint of 3 %; chosen or
  ;; dragged, the accent's ring, as GNOME rings a chosen picture.
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
  ;; pointer is over its view: at rest, a line 3 wide 4 from the edge, the
  ;; text at 20 %, outlined in the scroll bar outline color at 35 % (48-77,
  ;; 107-110); under the pointer, 8 wide on a trough of 10 %, the text at
  ;; 40 % (60 % pressed), the outline at 60 % (26-32, 79-81); and at least
  ;; 40 long (2).
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

  ;; A column view (widgets/_column-view.scss): a heading is a caption,
  ;; bold, the text at 40 % (70 % under the pointer), 6 in as the cells are
  ;; (12-53, 72-84); there is no line under it, nor between rows or columns
  ;; except where they are asked for (86-97).
  (define (adwaita-table-header x y w h flags label dir)
    (let* ([in 6] [f 'ui-small-bold] [g (ui-glyph-size)]
           [s (text-fit label (max 0 (- w in in (if dir (+ g 6) 0))) f)]
           [ink (alpha 'text (if (or (memq 'hover flags) (memq 'pressed flags))
                                 0.7
                                 0.4))]
           [right? (memq 'right flags)]
           [tx (if right? (- (+ x w) in (text-width s f)) (+ x in))]
           [end (adwaita-text-in tx y h s ink f)])
      (when dir
        (ui-draw-glyph (if right? (- tx 6 g) (+ end 6)) (adwaita-center y h g)
                       g g (list (cons 'ink ink))
                       (if (eq? dir 'up) 'chevron-up 'chevron-down)))))

  ;; A row: chosen, the accent at 25 % (32 % under the pointer); otherwise
  ;; under the pointer, the text at 4 % (widgets/_lists.scss:70-89,
  ;; _colors.scss:88-92).
  (define (adwaita-table-row x y w h flags)
    (cond [(memq 'selected flags)
           (fill-box x y w h
                     (alpha 'accent (if (memq 'hover flags) 0.32 0.25)))]
          [(memq 'hover flags) (fill-box x y w h (alpha 'text 0.04))]))

  ;; A column's edge, in the border color, and in the accent under the
  ;; pointer or while dragged.
  (define (adwaita-table-divider x y h flags)
    (if (or (memq 'hover flags) (memq 'pressed flags))
        (fill-box (- x 1) y 2 h 'adwaita-link)
        (fill-box x (+ y 4) 1 (- h 8) (alpha 'text 0.15))))

  (define (adwaita-table-cell-inset) 6))
