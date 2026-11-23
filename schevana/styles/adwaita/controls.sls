;;; (schevana styles adwaita controls) — a part of the Adwaita style
;;; ((schevana styles adwaita)): buttons, check boxes, radios and switches,
;;; scales and progress bars, tabs, labels and surfaces.

(library (schevana styles adwaita controls)
  (export
    adwaita-box adwaita-button adwaita-button-size adwaita-checkbox
    adwaita-checkbox-size adwaita-focus adwaita-label adwaita-progress
    adwaita-radio adwaita-radio-size adwaita-ring adwaita-slider
    adwaita-surface adwaita-tab adwaita-tabs-size adwaita-toggle
    adwaita-toggle-size adwaita-toggle-track)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) alpha draw-polyline draw-shadow fill-box
                fill-circle font-line-height stroke-box stroke-circle text-width
                theme with-clip)
          (only (schevana kits text) text-fit)
          (only (schevana kits ui) ui-button-radius ui-control-height
                ui-draw-glyph ui-glyph-size ui-joined-span ui-label-font
                ui-label-lines ui-label-size ui-label-text)
          (schevana styles adwaita text))

  (library-layer looks)

  ;;; ------------------------------------------------------------------
  ;;; buttons

  ;; The focus: a ring 2 wide of the accent at half strength, inside the
  ;; edge (_drawing.scss:12-23, _colors.scss:2, 116), or outside it past a
  ;; pixel's gap for a suggested button or a switch (widgets/
  ;; _buttons.scss:158, _switch.scss:11).
  (define (adwaita-ring x y w h r)
    (stroke-box x y w h (alpha 'adwaita-link 0.5) 2 r))

  (define (adwaita-ring-outside x y w h r)
    (stroke-box (- x 3) (- y 3) (+ w 6) (+ h 6) (alpha 'adwaita-link 0.5)
                2 (+ r 3)))

  ;; The kit's ring, for what does not draw its own: inside.
  (define (adwaita-focus x y w h flags r) (adwaita-ring x y w h r))

  ;; A box r round, square on its joined sides (flags join-left,
  ;; join-right): a linked button's, or a stepper's pieces' (widgets/
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
           [lw (if label (text-width label 'ui-bold) 0)]
           [x0 (adwaita-center x w (+ gw lw))])
      (when glyph
        (ui-draw-glyph x0 (adwaita-center y h g) g g (list (cons 'ink ink))
                       glyph))
      (when label (adwaita-text-in (+ x0 gw) y h label ink 'ui-bold))))

  ;; A button (widgets/_buttons.scss): the text at 10 % behind its label,
  ;; 15 % under the pointer, 30 % pressed and pressed in (selected), and 35
  ;; and 40 % pressed in and under the pointer or pressed (1-6, 17-56). A
  ;; flat one (quiet) has nothing at rest, 7 % under the pointer, 16 %
  ;; pressed and 10 % pressed in (234-274, _colors.scss:82-86). A suggested
  ;; one (primary) is the accent, its label white, with white at 10 % over
  ;; it under the pointer and rgb(0 0 6 / 20%) pressed (155-181, 220-228).
  ;; A destructive one (danger) has its label in the destructive red and
  ;; that red at 15 % behind it, 20 % under the pointer and 35 % pressed
  ;; (10-15, 183-211). Disabled, it is all at half strength, a flat one at
  ;; 30 % (58-64, 272-274); a joined piece (a stepper's) keeps its box at
  ;; full strength, as its neighbors do. A pill and a round one are round
  ;; at their ends (312-326); a segment is a toggle group's.
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
  ;; 9-102), a segmented choice's or a tab's. The group is the text at
  ;; 10 %, 9 round at its ends; each toggle sits 3 inside it, 6 round, a
  ;; pixel from its neighbors, with its label bold. The chosen one is
  ;; raised in the toggle color (white in the light style) with a card's
  ;; soft shadow; another is the text at 7 % under the pointer and 16 %
  ;; pressed.
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

  ;; A label's button reaches 17 on either side of it (widgets/
  ;; _buttons.scss:72-75), a glyph's and a label's 9 (77-91), and a
  ;; glyph's alone is a square.
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
  ;; _checks.scss:20-61). Empty, it is a ring 2 wide of the text at 15 %,
  ;; 20 % under the pointer, and a fill of 25 % pressed; checked, it is the
  ;; accent, with white at 10 % over it under the pointer and
  ;; rgb(0 0 6 / 20%) pressed.
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

  ;; Its label, 4 after the mark, and the whole widget's focus ring, 4 out
  ;; and 9 round (widgets/_checks.scss:3-13).
  (define (adwaita-check-label x y w h flags label)
    (let ([lh (font-line-height 'ui)] [by (+ y (floor (/ (- h 20) 2)))])
      (when label
        (adwaita-text-in (+ x 24) y h (text-fit label (max 0 (- w 24)) 'ui)
                         (if (memq 'disabled flags) (alpha 'text 0.5) 'text)
                         'ui))
      (when (memq 'focused flags)
        (adwaita-ring (- x 4) (- by 4)
                      (+ 28 (if label (+ 4 (text-width label 'ui)) 0)) 28 9))))

  ;; A check box: the mark 6 round, with its check in white, a stroke 2.5
  ;; wide through the points of the 14-pixel check icon (widgets/
  ;; _checks.scss:68-72).
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

  ;; The mark, 4, the label and the ring's 4 (a check button "Check"
  ;; measures 72 by 28).
  (define (adwaita-checkbox-size label)
    (values (+ 24 (text-width label 'ui) 4) 28))

  ;; Where a radio's label starts: after the mark and 4, and after an icon
  ;; and 6 if it has one.
  (define (adwaita-radio-text-x icon?)
    (+ 24 (if icon? (+ (ui-glyph-size) 6) 0)))

  ;; A control's height, or, if taller, its label with its hint wrapped
  ;; under it.
  (define (adwaita-radio-size label hint icon? w)
    (let* ([tw (max 0 (- w (adwaita-radio-text-x icon?)))]
           [hh (if hint
                   (let-values ([(hw hh) (ui-label-size '(hint wrap) hint tw)])
                     hh)
                   0)])
      (values w (max (ui-control-height)
                     (+ 8 (font-line-height 'ui) (if hint (+ 2 hh) 0))))))

  ;; A radio: the mark round, its bullet a white dot 8 across (widgets/
  ;; _checks.scss:75-79); then the label, with an icon before it and a hint
  ;; under it.
  (define (adwaita-radio x y w h flags label hint icon)
    (let* ([lh (font-line-height 'ui)] [g (ui-glyph-size)]
           [ly (if hint (+ y 4) (adwaita-text-top y h 'ui))]
           [by (+ ly (floor (/ (- lh 20) 2)))]
           [off? (memq 'disabled flags)]
           [ink (lambda (c) (if off? (alpha c 0.5) c))]
           [tx (+ x (adwaita-radio-text-x icon))])
      (adwaita-check-box x by flags 10)
      (when (memq 'checked flags)
        (fill-circle (+ x 10) (+ by 10) 4 (ink #xffffff)))
      (when icon (icon (+ x 24) (+ ly (/ (- lh g) 2)) g flags))
      (adwaita-text tx ly (text-fit label (max 0 (- (+ x w) tx)) 'ui)
                    (ink 'text) 'ui)
      (when hint
        (adwaita-lines (lambda (line) tx) (+ ly lh 2)
                       (ui-label-lines hint (max 0 (- (+ x w) tx)) 'ui-small)
                       (ink 'text-dim) 'ui-small))
      (when (memq 'focused flags)
        (adwaita-ring (- x 4) (- by 4)
                      (+ 28 4 (text-width label 'ui)) 28 9))))

  ;; A switch (widgets/_switch.scss): its track is 46 by 26 and round (GTK
  ;; makes it two knobs wide: gtkswitch.c), the text at 15 %, 20 % under
  ;; the pointer and 25 % pressed (1-9), and the accent when on (34-39);
  ;; its knob is a 20-pixel circle 3 in, in the slider color (white in the
  ;; light style), white under the pointer and when on, over a soft shadow
  ;; (17-32). Its label goes first and the switch at the end, as a switch
  ;; row has them (widgets/_lists.scss:124-163); focused, it has a ring
  ;; outside it (11).
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
        (adwaita-text-in x y h (text-fit label (max 0 (- w 46 12)) 'ui)
                         'text 'ui))
      (when (on? 'focused) (adwaita-ring-outside tx ty 46 26 13))))

  (define (adwaita-toggle-size label)
    (values (+ (text-width label 'ui) 12 46) (ui-control-height)))

  (define (adwaita-toggle-track) (values 46 26))

  ;;; ------------------------------------------------------------------
  ;;; scales and progress

  ;; A scale (widgets/_scale.scss): a trough 4 high and round, the text at
  ;; 15 % and 20 % under the pointer, with the accent up to the value (3-18,
  ;; 57-63; GTK sizes the trough from the knob, gtkrange.c); the knob is a
  ;; 20-pixel circle of the slider color, white under the pointer, ringed
  ;; in rgb(0 0 6 / 10%) over a soft shadow (44-54). A painted track
  ;; (Settings' colors) is 6 high under the knob.
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
  ;; text at 15 %, with the accent filling it; 8 high, the
  ;; progress-height.
  (define (adwaita-progress x y w h flags frac)
    (fill-box x y w h (alpha 'text 0.15) (/ h 2))
    (when (> frac 0)
      (fill-box x y (max h (* w (min 1 frac))) h 'accent (/ h 2))))

  ;;; ------------------------------------------------------------------
  ;;; tabs, labels and surfaces

  ;; Tabs are libadwaita 1.7's inline view switcher, a toggle group of the
  ;; views (adwaita-toggle-piece), round at the group's ends.
  (define (adwaita-tab x y w h flags label)
    (adwaita-toggle-piece x y w h
                          (append (if (memq 'first flags) '() '(join-left))
                                  (if (memq 'last flags) '() '(join-right))
                                  flags)
                          label #f))

  ;; Each tab is its label, bold, and 11 on either side (a toggle's 8 and
  ;; the group's 3), and a control high.
  (define (adwaita-tabs-size labels)
    (values (fold-left (lambda (acc l) (+ acc 22 (text-width l 'ui-bold))) 0
                       labels)
            (ui-control-height)))

  ;; A label: a heading and a group's label bold, in the text's color
  ;; (.heading: widgets/_labels.scss:55-57), a hint and a description
  ;; dimmed (13-15), and an error in the destructive red.
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
                        (adwaita-center x w (text-width s font))]
                       [else x]))])
      (if (memq 'wrap flags)
          (adwaita-lines at y (ui-label-lines text w font) color font)
          (let ([s (text-fit text w font)])
            (adwaita-text (at s) (max y (adwaita-text-top y h font)) s color
                          font)
            (+ y (max h lh))))))

  ;; Surfaces: a page has the window's color; a toolbar or a footer is a
  ;; top or a bottom bar, flat as the header is, or raised, in the header
  ;; bar's color with its shade's line toward the page
  ;; (widgets/_toolbars.scss:113-131, 187-208, 259-314); a side pane and a
  ;; column of places are a sidebar's color, with its border toward the
  ;; content (widgets/_sidebars.scss:1-32); and a well is a frame, the
  ;; view's color in a border, 12 round (widgets/_misc.scss:4-15).
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
        [else (fill-box x y w h (paper 'bg-1))]))))
