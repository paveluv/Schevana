;;; (schevana kits ui controls) — a part of the ui kit ((schevana kits ui)),
;;; which gives its names: the controls: buttons, the nav, the slider,
;;; checkboxes and toggles, live badges, radio buttons, tabs, a window's
;;; icons, avatars, progress and marks.

(library (schevana kits ui controls)
  (export
    ui-button ui-joined-span ui-button-radius ui-linked ui-draw-button
    ui-draw-button* ui-button-size ui-button-size* ui-segmented
    ui-stepper-areas ui-stepper-areas* ui-breadcrumbs ui-nav ui-draw-nav-row
    ui-draw-nav-row* ui-slider ui-slider-height ui-draw-slider ui-draw-slider*
    ui-checkbox ui-toggle ui-checkbox-box ui-draw-checkbox ui-draw-checkbox*
    ui-checkbox-size ui-checkbox-size* ui-live-badge ui-live-badge-back
    ui-live-badge-mark ui-live-badge-size ui-live-badge-size*
    ui-draw-live-badge ui-draw-live-badge* ui-toggle-track ui-toggle-track*
    ui-draw-toggle ui-draw-toggle* ui-toggle-size ui-toggle-size* ui-radio
    ui-radio-text-x ui-radio-size ui-radio-size* ui-draw-radio ui-draw-radio*
    ui-tabs ui-draw-tab ui-draw-tab* ui-tabs-size ui-tabs-size* ui-title-icon
    ui-icon-grid ui-icon-ink ui-draw-app-icon ui-draw-window-icon
    ui-draw-app-tile ui-draw-app-tile* ui-draw-env-icon ui-draw-env-icon*
    ui-busy-frame-ms
    ui-busy-size ui-busy-size* ui-draw-busy ui-draw-busy* ui-initials
    ui-avatar-size ui-avatar-size* ui-draw-avatar ui-draw-avatar*
    ui-draw-progress ui-draw-progress* ui-progress-height ui-mark-size
    ui-draw-mark ui-draw-mark* ui-draw-due ui-draw-due*)
  (import (chezscheme)
          (only (schevana base) at-load clamp define-hook library-layer
                plist-ref string-split)
          (only (schevana core) alpha app-icon app-title color-default!
                define-part draw-line draw-text fill-box fill-circle
                fill-polygon font font-family font-line-height get-font mix pi
                stroke-box stroke-circle text-width theme theme-default!
                theme-rule window-app window-ref window-title with-clip
                with-scale with-translation)
          (only (schevana kits app) app-find app-color)
          (only (schevana kits color) color-readable-on)
          (only (schevana kits text) text-draw-centered text-fit)
          (schevana kits ui base))

  (library-layer kits)


  ;;; ---------------------------------------------------------------- button

  ;; opts: 'glyph, 'tip, 'disabled, and the flags 'primary (the suggested
  ;; action), 'danger, 'quiet (flat: no box until the pointer is on it),
  ;; 'selected (pressed in), 'pill and 'circular (round ends; a round
  ;; button), 'join-left and 'join-right (square on that side, where a
  ;; linked neighbor touches it), and 'segment (a piece of a segmented
  ;; choice).
  (define (ui-button ui id x y w h label on-press . opts)
    (ui-pressable! ui id x y w h on-press '(#\space return) opts
                   (list (cons 'L (or label (plist-ref opts 'tip #f) "Press"))))
    (ui-draw-button x y w h
                    (apply ui-flags ui id
                           (ui-opt-flags opts '(selected primary danger quiet
                                                disabled pill circular
                                                join-left join-right
                                                segment)))
                    label (plist-ref opts 'glyph #f)))

  ;; A box x..x+w with corners of radius r, except on its joined sides
  ;; (flags join-left, join-right), is drawn as a rounded box that much
  ;; wider on those sides, cut to x..x+w (with-clip). Returns (values x w)
  ;; of that wider box.
  (define (ui-joined-span x w r flags)
    (let ([l (if (memq 'join-left flags) r 0)]
          [rt (if (memq 'join-right flags) r 0)])
      (values (- x l) (+ w l rt))))

  ;; Returns a button's corner radius: half its height when it is a pill or
  ;; round, else r.
  (define (ui-button-radius h flags r)
    (if (or (memq 'pill flags) (memq 'circular flags)) (/ h 2) r))

  ;; Buttons side by side, joined into one (a linked group). items are ((key
  ;; label thunk opt ...) ...), with opts as ui-button's; each button is as
  ;; wide as ui-button-size says unless it gives 'width, and neighbors share
  ;; their edge's pixel. Returns the x after the last button.
  (define (ui-linked ui id x y h items)
    (let loop ([is items] [bx x] [first? #t])
      (if (null? is)
          (+ bx 1)
          (let* ([it (car is)] [opts (cdddr it)]
                 [bw (or (plist-ref opts 'width #f)
                         (let-values ([(w bh) (ui-button-size
                                               (cadr it)
                                               (plist-ref opts 'glyph #f))])
                           w))])
            (apply ui-button ui (list id (car it)) bx y bw h (cadr it)
                   (caddr it) 'join-left (not first?)
                   'join-right (pair? (cdr is)) opts)
            (loop (cdr is) (+ bx bw -1) #f)))))

  ;; The ring around a color's swatch (a color picker's), which shows on
  ;; its row, chosen or not: a stipple of ink and paper where a style
  ;; inverts the chosen row (Genera).
  (at-load
   (color-default! 'swatch-ring (theme-rule (alpha 'text 0.25))))

  ;; The ink of what lies on the accent (a primary button's words, a radio's
  ;; dot, a chosen day's number): near black or near white, unless a palette
  ;; or a style says otherwise (one with an ink and a paper only).
  (at-load
   (color-default! 'accent-ink (theme-rule (color-readable-on 'accent))))

  ;; A primary button's fill while pressed, and under the pointer.
  (at-load
   (color-default! 'primary-pressed (theme-rule (mix 'accent 'bg-0 0.15))))
  (at-load
   (color-default! 'primary-hover (theme-rule (mix 'accent 'text 0.15))))

  ;; The built-in button's box: its fill and its outline, either of which
  ;; may be #f.
  (define (ui-draw-button-box x y w h fill stroke r)
    (when fill (fill-box x y w h fill r))
    (when stroke (stroke-box x y w h stroke 1 r)))

  ;; With only the flags hover and selected, this is the look Settings was
  ;; designed with.
  (define-part (ui-draw-button x y w h flags label glyph)
    (let* ([flags (if (memq 'disabled flags)   ; the pointer does nothing
                      (remp (lambda (f) (memq f '(hover pressed))) flags)
                      flags)]
           [on? (lambda (f) (memq f flags))]
           [ink (lambda (c) (if (on? 'disabled) (ui-fade c) c))]
           [hot? (or (on? 'hover) (on? 'pressed))]
           [fill (cond [(on? 'primary)
                        (cond [(on? 'pressed) 'primary-pressed]
                              [(on? 'hover) 'primary-hover]
                              [else 'accent])]
                       [(on? 'selected) (alpha 'accent 0.25)]
                       [(on? 'pressed) (mix 'bg-3 'text 0.08)]
                       [(and (on? 'danger) (on? 'hover)) (alpha 'red 0.15)]
                       [(on? 'hover) 'bg-3]
                       [(on? 'quiet) #f]
                       [else 'bg-2])]
           [stroke (cond [(or (on? 'primary) (and (on? 'quiet) (not hot?))) #f]
                         [(on? 'selected) 'accent]
                         [(on? 'danger) 'red]
                         [else 'window-border])]
           [color (cond [(on? 'primary) 'accent-ink]
                        [(on? 'danger) 'red]
                        [(or (on? 'hover) (on? 'selected)) 'text]
                        [else 'text-dim])]
           [lh (font-line-height 'ui)] [g (ui-glyph-size)]
           [gw (if glyph (* 3/2 g) 0)]   ; the glyph and its gap
           [label (and label (text-fit label (- w 12 gw) 'ui))]
           [cw (if label (+ gw (text-width label 'ui)) g)]
           [x0 (+ x (/ (- w cw) 2))]
           [r (ui-button-radius h flags 6)])
      (if (or (on? 'join-left) (on? 'join-right))
          (let-values ([(bx bw) (ui-joined-span x w r flags)])
            (with-clip (x y w h)
              (ui-draw-button-box bx y bw h (and fill (ink fill))
                                  (and stroke (ink stroke)) r)))
          (ui-draw-button-box x y w h (and fill (ink fill))
                              (and stroke (ink stroke)) r))
      (when glyph (ui-draw-glyph x0 (+ y (/ (- h g) 2)) g g flags glyph))
      (when label
        (draw-text (+ x0 gw) (+ y (/ (- h lh) 2)) label (ink color) 'ui))
      (when (on? 'focused) (ui-draw-focus x y w h flags r))))

  ;; A glyph alone makes a square button.
  (define-part (ui-button-size label glyph)
    (let ([h (ui-control-height)])
      (values (if label
                  (+ 24 (text-width label 'ui)
                     (if glyph (* 3/2 (ui-glyph-size)) 0))
                  h)
              h)))

  ;; A segmented control. choices: ((label . value) ...); the one equal? to
  ;; current is selected. opts: 'tip, shared by every choice. Each choice is
  ;; a button flagged segment, the style's segmented-gap apart; with no gap,
  ;; they form one group with its inner edges joined (join-left,
  ;; join-right).
  (define (ui-segmented ui id x y w h choices current on-select . opts)
    (let* ([n (length choices)] [gap (theme 'segmented-gap)]
           [bw (/ w n)] [joined? (zero? gap)])
      (for-each (lambda (c i)
                  (ui-button ui (list id (cdr c)) (+ x (* i bw)) y (- bw gap) h
                             (car c) (lambda () (on-select (cdr c)))
                             'selected (equal? current (cdr c))
                             'segment #t
                             'join-left (and joined? (> i 0))
                             'join-right (and joined? (< i (- n 1)))
                             'tip (plist-ref opts 'tip #f)))
                choices (iota n))))

  ;; The space between two choices of a segmented control.
  (at-load
   (theme-default! 'segmented-gap 6))

  ;; Where a stepper w × h puts its buttons and its field: ((down x y w h
  ;; flag ...) (field ...) (up ...)), each flag (join-left, join-right) a
  ;; side the piece shares with a neighbor. This one puts a button on either
  ;; side, each a square of the control height, and the field between them.
  (define-part (ui-stepper-areas x y w h)
    (let ([b (ui-control-height)])
      (list (list 'down x y b b)
            (list 'field (+ x b) y (- w b b) h)
            (list 'up (- (+ x w) b) y b b))))

  ;; The stepper's glyphs, (down . up).
  (at-load
   (theme-default! 'stepper-glyphs '(chevron-left . chevron-right)))

  ;; A path shown as crumbs: labels, oldest first, each a button that calls
  ;; (on-select i), with a chevron between them; all but the last are quiet,
  ;; and the last is the one you are in. What does not fit in w is hidden,
  ;; from the oldest on, behind a … that selects the newest of those it
  ;; hides.
  (define (ui-breadcrumbs ui id x y w h labels on-select)
    (let* ([g (ui-small-glyph-size)] [sep (+ g 6)]
           [widths (map (lambda (l)
                          (let-values ([(bw bh) (ui-button-size l #f)])
                                      (- bw 8)))
                        labels)]
           [n (length labels)]
           [dots (let-values ([(bw bh) (ui-button-size "…" #f)]) (- bw 8))]
           ;; how many of the oldest go into the …
           [hidden (let loop ([k 0])
                     (let ([need (+ (apply + (list-tail widths k))
                                    (* sep (- n k 1))
                                    (if (> k 0) (+ dots sep) 0))])
                       (if (or (<= need w) (>= k (- n 1))) k (loop (+ k 1)))))])
      (let loop ([i hidden] [cx (if (> hidden 0)
                                    (begin
                                      (ui-button ui (list id 'more) x y dots h
                                                 "…"
                                                 (lambda () (on-select
                                                             (- hidden 1)))
                                                 'quiet #t 'focus 'keep
                                                 'tip (list-ref labels
                                                                (- hidden 1)))
                                      (ui-draw-glyph (+ x dots 3)
                                                     (+ y (/ (- h g) 2)) g g
                                                     '(quiet) 'chevron-right)
                                      (+ x dots sep))
                                    x)])
        (when (< i n)
          (let ([bw (min (list-ref widths i) (max 0 (- (+ x w) cx)))])
            (ui-button ui (list id i) cx y bw h (list-ref labels i)
                       (lambda () (on-select i))
                       'quiet (< i (- n 1)) 'focus 'keep)
            (when (< i (- n 1))
              (ui-draw-glyph (+ cx bw 3) (+ y (/ (- h g) 2)) g g '(quiet)
                             'chevron-right))
            (loop (+ i 1) (+ cx bw sep)))))))

  ;;; ---------------------------------------------------------------- nav
  ;;; A column of places to go, one of which is where you are: Settings'
  ;;; tabs, a file dialog's places.

  ;; items: ((value label icon) ...), icon being #f or a (lambda (x y s
  ;; flags) ...) that draws one s square. The item equal? to current is
  ;; selected; a press, or Space or Return on a focused item, calls
  ;; (on-select value). The rows are ui-nav-row-height high and 6 apart,
  ;; from y. Returns the y below the last row and its gap.
  (define (ui-nav ui id x y w items current on-select)
    (let ([rh (ui-nav-row-height)])
      (fold-left
       (lambda (ry item)
         (let ([rid (list id (car item))])
           (ui-pressable! ui rid x ry w rh (lambda () (on-select (car item)))
                          '(#\space return) '() (list (cons 'L (cadr item))))
           (ui-draw-nav-row x ry w rh
                            (apply ui-flags ui rid
                                   (if (equal? (car item) current)
                                       '(selected)
                                       '()))
                            (cadr item) (caddr item))
           (+ ry rh 6)))
       y items)))

  (define (ui-nav-row-height) (max 32 (round (+ (font-line-height 'ui) 12))))

  ;; flags: selected, hover, focused, disabled. The selected row is
  ;; highlighted, with a mark at its left; the label comes after the icon,
  ;; if any.
  (define-part (ui-draw-nav-row x y w h flags label icon)
    (let* ([selected? (memq 'selected flags)] [g (ui-glyph-size)]
           [lx (if icon (+ x 14 g 8) (+ x 14))])
      (cond [selected? (ui-draw-highlight x y w h '())]
            [(memq 'hover flags) (ui-draw-highlight x y w h '(hover))])
      (when icon (icon (+ x 14) (+ y (/ (- h g) 2)) g flags))
      (ui-draw-label lx y (- (+ x w) lx 6) h
                     (cond [(memq 'disabled flags) '(disabled)]
                           [selected? '()]
                           [else '(dim)])
                     label)
      (when selected?
        (ui-draw-highlight-over x y w h '())
        ;; The mark comes after that, so that a style that inverts the row
        ;; keeps the mark whole (in ink on ink).
        (fill-box x (+ y (/ h 2) -8) 3 16 'accent 1.5))
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 5))))

  ;;; ---------------------------------------------------------------- slider

  ;; A horizontal slider. on-change receives the new value in [lo, hi].
  ;; paint-track, if given, draws the track: (lambda (x y w h) ...). opts:
  ;; 'tip.
  (define ui-slider
    (case-lambda
      [(ui id x y w value lo hi on-change)
       (ui-slider ui id x y w value lo hi on-change #f)]
      [(ui id x y w value lo hi on-change paint-track . opts)
       (let ([h (ui-slider-height)])
         (ui-area ui id (- x 8) y (+ w 16) h #f
                  (lambda (mx my)
                    (on-change
                     (+ lo (* (- hi lo) (clamp (/ (- mx x) w) 0 1)))))
                  'doc '((L . "Set")) 'tip (plist-ref opts 'tip #f))
         (ui-draw-slider x y w h (ui-flags ui id)
                         (clamp (/ (- value lo) (- hi lo)) 0 1) paint-track))]))

  (at-load
   (theme-default! 'slider-height 24))
  (define (ui-slider-height) (theme 'slider-height))

  (define-part (ui-draw-slider x y w h flags frac paint)
    (let* ([cy (+ y (/ h 2))] [kx (+ x (* frac w))]
           [r (if (or (memq 'hover flags) (memq 'pressed flags)) 8 7)])
      (if paint
          (with-clip (x (- cy 4) w 8 4) (paint x (- cy 4) w 8))
          (begin
            (fill-box x (- cy 3) w 6 'bg-3 3)
            (fill-box x (- cy 3) (max 6 (- kx x)) 6
                      (if (memq 'disabled flags) 'text-disabled 'accent) 3)))
      (fill-circle kx cy r #xf2f2f5)
      (stroke-circle kx cy r (alpha #x000000 0.35) 1)))

  ;;; ------------------------------------------------------------------
  ;;; checkbox and toggle: one behavior, two looks

  (define (ui-checkbox ui id x y w h label checked? on-change . opts)
    ;; A cut label gets a tooltip; a box alone (no label) has none.
    (let-values ([(kw kh) (if label (ui-checkbox-size label) (values 0 0))])
      (ui-pressable! ui id x y w h (lambda () (on-change (not checked?)))
                     '(#\space)
                     (cons* 'tip (or (plist-ref opts 'tip #f)
                                     (and (> kw w) label))
                            opts)
                     '((L . "Toggle"))))
    (ui-draw-checkbox x y w h
                      (apply ui-flags ui id
                             (append (if checked? '(checked) '())
                                     (if (plist-ref opts 'disabled #f)
                                         '(disabled)
                                         '())))
                      label))

  (define (ui-toggle ui id x y w h label on? on-change . opts)
    (ui-pressable! ui id x y w h (lambda () (on-change (not on?)))
                   '(#\space) opts '((L . "Toggle")))
    (ui-draw-toggle x y w h (apply ui-flags ui id (if on? '(checked) '()))
                    label))

  (define (ui-checkbox-box) (round (+ (font-line-height 'ui) 1)))

  ;; flags: checked, hover, focused, disabled (faded, and the pointer does
  ;; nothing).
  (define-part (ui-draw-checkbox x y w h flags label)
    (let* ([b (ui-checkbox-box)] [by (+ y (floor (/ (- h b) 2)))]
           [lh (font-line-height 'ui)] [checked? (memq 'checked flags)]
           [off? (memq 'disabled flags)]
           [flags (if off? (remq 'hover flags) flags)])
      (if checked?
          (begin (fill-box x by b b
                           (if off? (alpha 'accent 0.45) 'accent)
                           4)
                 (ui-draw-glyph x by b b '(primary) 'check))
          (begin (fill-box x by b b (if off? 'bg-1 'bg-0) 4)
                 (stroke-box x by b b
                             (cond [(memq 'hover flags) 'accent]
                                   [off? (alpha 'text-faint 0.5)]
                                   [else 'text-faint])
                             1 4)))
      (when label
        (draw-text (+ x b 8) (+ y (/ (- h lh) 2))
                   (text-fit label (- w b 8) 'ui)
                   (cond [off? 'text-disabled] [checked? 'text-dim]
                         [else 'text])
                   'ui))
      (when (memq 'focused flags) (ui-draw-focus x by b b flags 4))))

  (define-part (ui-checkbox-size label)
    (values (+ (ui-checkbox-box) 8 (text-width label 'ui)) (ui-control-height)))

  ;;; ------------------------------------------------------------------
  ;;; live: whether a view follows what happens, or holds still

  ;; A badge that says whether a view is live: "Live", with a dot; or, when
  ;; held, what it holds (held-label) and the way back. A press or Space
  ;; switches it, calling (on-change live?) with the other state.
  (define (ui-live-badge ui id x y w h live? held-label on-change . opts)
    (ui-pressable! ui id x y w h (lambda () (on-change (not live?)))
                   '(#\space) opts
                   (list (cons 'L (if live? "Hold still" "Back to live"))))
    (ui-draw-live-badge x y w h
                        (apply ui-flags ui id (if live? '(checked) '()))
                        (if live? "Live" held-label)))

  (define ui-live-badge-back " · back to live")

  ;; The dot's or the pause mark's width.
  (define (ui-live-badge-mark) (quotient (font-line-height 'ui-small) 2))

  (define-part (ui-live-badge-size live? held-label)
    (values (+ 8 (ui-live-badge-mark) 6
               (text-width (if live? "Live" held-label) 'ui-small)
               (if live? 0 (text-width ui-live-badge-back 'ui-small))
               10)
            (+ (font-line-height 'ui-small) 6)))

  ;; flags: checked (live), hover, pressed, focused, disabled. A pill: when
  ;; live, it is tinted with the accent and has a dot; when held, it is
  ;; plain, with a pause mark and the way back in the accent.
  (define-part (ui-draw-live-badge x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [off? (on? 'disabled)]
           [live? (on? 'checked)]
           [hot? (and (not off?) (or (on? 'hover) (on? 'pressed)))]
           [lh (font-line-height 'ui-small)] [m (ui-live-badge-mark)]
           [ty (+ y (/ (- h lh) 2))] [my (+ y (/ (- h m) 2))]
           [r (exact (floor (/ h 2)))]
           [tx (+ x 8 m 6)]
           [back (if live? 0 (text-width ui-live-badge-back 'ui-small))]
           [label (text-fit label (max 0 (- (+ x w) tx back 10)) 'ui-small)])
      (fill-box x y w h
                (cond [live? (alpha 'accent (if hot? 0.3 0.18))]
                      [hot? 'bg-3]
                      [else 'bg-2])
                r)
      (stroke-box x y w h
                  (cond [hot? 'accent]
                        [live? (alpha 'accent 0.6)]
                        [else 'window-border])
                  1 r)
      (if live?
          (fill-circle (+ x 8 (/ m 2)) (+ y (/ h 2)) (/ m 2)
                       (if off? 'text-disabled 'accent))
          (let ([bw (max 1 (quotient m 3))]
                [ink (if off? 'text-disabled 'text-dim)])
            (fill-box (+ x 8) my bw m ink)
            (fill-box (+ x 8 (- m bw)) my bw m ink)))
      (draw-text tx ty label
                 (cond [off? 'text-disabled] [live? 'text] [else 'text-dim])
                 'ui-small)
      (unless live?
        (draw-text (+ tx (text-width label 'ui-small)) ty ui-live-badge-back
                   (if off? 'text-disabled 'accent) 'ui-small))
      (when (on? 'focused) (ui-draw-focus x y w h flags r))))

  ;; Returns the size of a toggle's track, the pill its knob slides in, as
  ;; (values w h).
  (define-part (ui-toggle-track)
    (let ([th (+ (ui-glyph-size) 6)]) (values (- (* 2 th) 4) th)))

  (define-part (ui-draw-toggle x y w h flags label)
    (let*-values ([(tw th) (ui-toggle-track)]
                  [(ty) (+ y (floor (/ (- h th) 2)))]
                  [(on? r) (values (memq 'checked flags) (- (/ th 2) 2))]
                  [(kx) (if on? (+ x tw (- (/ th 2))) (+ x (/ th 2)))]
                  [(lh) (font-line-height 'ui)])
      (fill-box x ty tw th
                (cond [(and on? (memq 'disabled flags)) 'text-disabled]
                      [on? 'accent] [(memq 'hover flags) 'text-faint]
                      [else 'bg-3])
                (/ th 2))
      (fill-circle kx (+ ty (/ th 2)) r #xf2f2f5)
      (stroke-circle kx (+ ty (/ th 2)) r (alpha #x000000 0.35) 1)
      (when label
        (draw-text (+ x tw 8) (+ y (/ (- h lh) 2))
                   (text-fit label (- w tw 8) 'ui)
                   (cond [(memq 'disabled flags) 'text-disabled]
                         [(memq 'hover flags) 'text]
                         [else 'text-dim])
                   'ui))
      (when (memq 'focused flags) (ui-draw-focus x ty tw th flags (/ th 2)))))

  (define-part (ui-toggle-size label)
    (let-values ([(tw th) (ui-toggle-track)])
      (values (+ tw 8 (text-width label 'ui)) (ui-control-height))))

  ;;; ---------------------------------------------------------------- radio
  ;;; One choice among several: the app draws one radio per choice, and the
  ;;; chosen one is checked.

  ;; opts: 'hint, text under the label that says what the choice means;
  ;; 'icon, a (lambda (x y s flags) ...) that draws an icon s square before
  ;; the label (the app's drawing procedure); 'disabled; 'tip.
  (define (ui-radio ui id x y w h label chosen? on-choose . opts)
    (ui-pressable! ui id x y w h on-choose '(#\space return) opts
                   '((L . "Choose")))
    (ui-draw-radio x y w h
                   (apply ui-flags ui id
                          (append (if chosen? '(checked) '())
                                  (ui-opt-flags opts '(disabled))))
                   label (plist-ref opts 'hint #f) (plist-ref opts 'icon #f)))

  ;; The mark's side, the same as a checkbox's.
  (define (ui-radio-mark) (ui-checkbox-box))

  ;; Returns where the text starts, after the mark and any icon, as an
  ;; offset from the radio's x.
  (define (ui-radio-text-x icon?)
    (+ (ui-radio-mark) 8 (if icon? (+ (ui-glyph-size) 6) 0)))

  ;; Returns (values w h) of a radio w wide: h is a control's height, or the
  ;; height of its label with its hint wrapped under it, if that is taller.
  (define-part (ui-radio-size label hint icon? w)
    (let* ([tw (max 0 (- w (ui-radio-text-x icon?)))]
           [lh (font-line-height 'ui)]
           [hh (if hint (let-values ([(hw hh) (ui-label-size '(hint wrap) hint
                                                             tw)])
                          hh)
                   0)])
      (values w (max (ui-control-height) (+ 8 lh (if hint (+ 2 hh) 0))))))

  ;; flags: checked, disabled, hover, focused. The mark and the label go on
  ;; the first line, and the hint under the label.
  (define-part (ui-draw-radio x y w h flags label hint icon)
    (let* ([b (ui-radio-mark)] [lh (font-line-height 'ui)]
           [one? (not hint)]
           [ly (if one? (+ y (/ (- h lh) 2)) (+ y 4))]   ; the label's top
           [by (+ ly (floor (/ (- lh b) 2)))]
           [cx (+ x (/ b 2))] [cy (+ by (/ b 2))]
           [off? (memq 'disabled flags)]
           [ink (lambda (c) (if off? (ui-fade c) c))]
           [tx (+ x (ui-radio-text-x icon))])
      (if (memq 'checked flags)
          (begin (fill-circle cx cy (/ b 2) (ink 'accent))
                 (fill-circle cx cy (/ b 5) 'accent-ink))
          (begin (fill-circle cx cy (/ b 2) 'bg-0)
                 (stroke-circle cx cy (- (/ b 2) 0.5)
                                (ink (if (and (memq 'hover flags) (not off?))
                                         'accent
                                         'text-faint))
                                1)))
      (when icon
        (let ([g (ui-glyph-size)])
          (icon (+ x b 8) (+ ly (/ (- lh g) 2)) g flags)))
      (draw-text tx ly (text-fit label (- (+ x w) tx) 'ui)
                 (cond [off? 'text-disabled] [(memq 'hover flags) 'text]
                       [else 'text-dim])
                 'ui)
      (when hint
        (fold-left (lambda (hy line)
                     (draw-text tx hy line 'text-faint 'ui-small)
                     (+ hy (font-line-height 'ui-small)))
                   (+ ly lh 2)
                   (ui-label-lines hint (- (+ x w) tx) 'ui-small)))
      (when (memq 'focused flags) (ui-draw-focus x by b b flags (/ b 2)))))

  ;;; ---------------------------------------------------------------- tabs

  ;; choices: ((label . value) ...). Returns the x after the last tab. The
  ;; first and last tabs carry the flags first and last: a style that
  ;; chains its tabs ends the chain there, and one that groups them rounds
  ;; the group's ends.
  (define (ui-tabs ui id x y h choices current on-select)
    (let loop ([cs choices] [tx x])
      (if (null? cs)
          tx
          (let ([label (caar cs)] [value (cdar cs)] [tid (list id (cdar cs))])
            (let-values ([(tw th) (ui-tabs-size (list label))])
              (ui-pressable! ui tid tx y tw h (lambda () (on-select value))
                             '(#\space return) '() (list (cons 'L label)))
              (ui-draw-tab tx y tw h
                           (apply ui-flags ui tid
                                  (append
                                   (if (equal? value current) '(selected) '())
                                   (if (eq? cs choices) '(first) '())
                                   (if (null? (cdr cs)) '(last) '())))
                           label)
              (loop (cdr cs) (+ tx tw)))))))

  (define-part (ui-draw-tab x y w h flags label)
    (let ([selected? (memq 'selected flags)] [lh (font-line-height 'ui-bold)])
      (text-draw-centered x y w h label
                          (cond [(memq 'disabled flags) 'text-disabled]
                                [(or selected? (memq 'hover flags)) 'text]
                                [else 'text-dim])
                          'ui-bold)
      (when selected?
        (fill-box (+ x 10) (+ y (/ (+ h lh) 2) 3) (- w 20) 2 'accent 1))
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 6))))

  ;; Each tab is as wide as its label in 'ui-bold, plus 24.
  (define-part (ui-tabs-size labels)
    (values (fold-left (lambda (acc l) (+ acc 24 (text-width l 'ui-bold))) 0
                       labels)
            (round (+ (font-line-height 'ui) 15))))

  ;;; ------------------------------------------------------------------
  ;;; what a window's app says about the window, which each style shows in
  ;;; its own way

  ;; Returns a window's title icon: its 'title-icon, a (lambda (x y s flags)
  ;; ...) that draws it s square (with the flag dim for an unfocused
  ;; window), else its app's icon, or #f. A style draws it by the title,
  ;; elsewhere, or not at all.
  (define (ui-title-icon win)
    (or (window-ref win 'title-icon #f)
        (let ([a (app-find (window-app win))]) (and a (app-icon a)))))

  ;;; An icon (an app's, from define-app's 'icon, or a window's 'title-icon)
  ;;; is a procedure (x y s flags) that draws in the s-square at x, y, at any
  ;;; size, in the theme's colors, so that it follows the look as the
  ;;; glyphs do. The flags dim (an unfocused window's title, a minimized
  ;;; window's button) and disabled fade it. Every place that shows an app
  ;;; draws its icon: the launcher, the taskbar or dash, a title bar where
  ;;; the style has one; an app that gives none has a stand-in, its tile.

  ;; Draws body in a grid of 24 units across the s-square at x, y: (12, 12)
  ;; is its middle, and a line 2 wide is a twelfth of the icon at any size.
  (define-syntax ui-icon-grid
    (syntax-rules ()
      [(_ (x y s) body ...)
       (with-translation (x y) (with-scale ((/ s 24)) body ...))]))

  ;; Returns color c as an icon drawn with flags shows it: faded when they
  ;; hold dim or disabled (ui-fade).
  (define (ui-icon-ink flags c)
    (if (or (memq 'dim flags) (memq 'disabled flags)) (ui-fade c) c))

  ;; Draws the icon of the app named name in the s-square at x, y: the
  ;; app's own, or its tile.
  (define (ui-draw-app-icon x y s flags name)
    (let* ([a (app-find name)] [icon (and a (app-icon a))])
      (if icon
          (icon x y s flags)
          (ui-draw-app-tile x y s flags name (if a (app-title a) "")))))

  ;; Draws a window's icon in the s-square at x, y: its title icon, else
  ;; the tile of its app (or of no app), with the window's title.
  (define (ui-draw-window-icon win x y s flags)
    (let ([icon (ui-title-icon win)])
      (if icon
          (icon x y s flags)
          (ui-draw-app-tile x y s flags (window-app win) (window-title win)))))

  ;; The stand-in for the icon of an app that gives none: a tile in the
  ;; app's color (app-color, which takes #f for no app) with the first
  ;; letter of title, in bold at three fifths of the tile.
  (define-part (ui-draw-app-tile x y s flags name title)
    (let ([c (app-color name)])
      (fill-box x y s s (ui-icon-ink flags c) (/ s 4))
      (unless (string=? title "")
        (text-draw-centered x y s s
                            (string (char-upcase (string-ref title 0)))
                            (ui-icon-ink flags (color-readable-on c))
                            (font (font-family (get-font 'ui-bold))
                                  (max 6 (exact (round (* 3/5 s)))) 'bold)))))

  ;; An environment's icon by its kind ((schevana services env)): the
  ;; world's globe, a namespace's folder, a sandbox's box, and a thread's or
  ;; the worklets' gear, each in its kind's color, and faded when dim or
  ;; disabled.
  (define-part (ui-draw-env-icon x y s flags kind)
    (let-values ([(glyph ink)
                  (case kind
                    [(root) (values 'globe 'accent)]
                    [(worklets) (values 'gear 'yellow)]
                    [(thread) (values 'gear 'orange)]
                    [(sandbox) (values 'box 'teal)]
                    [(world) (values 'folder 'accent)]
                    [(private) (values 'folder 'accent-2)]
                    [(pure) (values 'folder 'green)]
                    [else (values 'folder 'text-dim)])])
      (ui-draw-glyph x y s s (list (cons 'ink (ui-icon-ink flags ink)))
                     glyph)))

  ;; An app says that its window is at work by the window's 'busy (the words
  ;; for it, or #f), and the window shows this as its style chooses. By
  ;; default the app draws a busy mark where the work shows (a REPL's
  ;; prompt), with its words in a tooltip over it; a style may give the
  ;; mark no size and show it in its frame or a bar instead, or animate it
  ;; its own way. The mark is drawn again every busy-frame-ms while it
  ;; shows.
  (at-load
   (theme-default! 'busy-frame-ms 100))
  (define (ui-busy-frame-ms) (theme 'busy-frame-ms))

  ;; Returns (values w h), the room the mark takes, or (values 0 0) for
  ;; none, when the style shows it elsewhere.
  (define-part (ui-busy-size)
    (let ([s (ui-glyph-size)]) (values s s)))

  ;; Draws the mark at ms (now): a spinner of eight spokes in a circle, with
  ;; the brightest moving on by one spoke every busy-frame-ms. flags: hover;
  ;; bar, on a bar, in the bar's ink (panel-text).
  (define-part (ui-draw-busy x y w h flags ms)
    (let* ([r (/ (min w h) 2)] [cx (+ x (/ w 2))] [cy (+ y (/ h 2))]
           [lead (mod (quotient ms (max 1 (ui-busy-frame-ms))) 8)]
           [ink (cond [(memq 'bar flags) 'panel-text]
                      [(memq 'hover flags) 'text]
                      [else 'text-dim])]
           [lw (max 1.5 (* r 0.22))])
      (do ([i 0 (+ i 1)]) ((= i 8))
        (let ([a (* pi (/ i 4))]
              [fade (/ (mod (- lead i) 8) 8)])
          (draw-line (+ cx (* 0.45 r (cos a))) (+ cy (* 0.45 r (sin a)))
                     (+ cx (* 0.95 r (cos a))) (+ cy (* 0.95 r (sin a)))
                     (alpha ink (- 1 (* 0.85 fade))) lw)))))

  ;;; ------------------------------------------------------------------
  ;;; avatar

  ;; "Pavel Uvarov" → "PU", "Claude" → "C".
  (define (ui-initials name)
    (let ([words (remp (lambda (w) (string=? w ""))
                       (string-split name #\space))])
      (if (null? words)
          "?"
          (list->string
           (map (lambda (w) (char-upcase (string-ref w 0)))
                (if (null? (cdr words))
                    words
                    (list (car words) (car (last-pair words)))))))))

  ;; Returns the size of a person's avatar, by name, as (values w h). flags
  ;; may hold named (the name is written beside it, so a style may leave the
  ;; avatar out: (values 0 0)).
  (define-part (ui-avatar-size flags name)
    (let ([s (round (+ (font-line-height 'ui-small) 7))]) (values s s)))

  ;; A circle in one color per person, however the name was typed (spaces
  ;; around it, capitals), with the initials.
  (define-part (ui-draw-avatar x y w h flags name)
    (let ([color (let trim ([i 0] [j (string-length name)])
                   (cond [(and (< i j) (char-whitespace? (string-ref name i)))
                          (trim (+ i 1) j)]
                         [(and (< i j)
                               (char-whitespace? (string-ref name (- j 1))))
                          (trim i (- j 1))]
                         [else (app-color (string->symbol
                                           (string-downcase
                                            (substring name i j))))]))])
      (fill-circle (+ x (/ w 2)) (+ y (/ w 2)) (/ w 2) color)
      (text-draw-centered x y w w (ui-initials name) (color-readable-on color)
                          'ui-small)))

  ;;; ------------------------------------------------------------------
  ;;; progress, tooltip

  (define-part (ui-draw-progress x y w h flags frac)
    (fill-box x y w h 'bg-3 (/ h 2))
    (when (> frac 0)
      (fill-box x y (max h (* w (min 1 frac))) h (if (>= frac 1) 'green 'accent)
                (/ h 2))))

  (at-load
   (theme-default! 'progress-height
                   (theme-rule (max 4 (round (* (font-line-height 'ui) 0.4))))))
  (define (ui-progress-height) (theme 'progress-height))

  ;;; ---------------------------------------------------------------- marks
  ;;; A mark is a small sign in a square a little under a line of text, for
  ;;; what an item is or how it stands: how important (a level), its kind
  ;;; (a shape, told by form and color both), that it is blocked, or its
  ;;; state (a dot beside the state's word).

  (define (ui-mark-size) (round (* (font-line-height 'ui) 0.8)))

  ;; Draws mark in the s-square at (x, y), in color, and returns the width
  ;; it took: s, or 0 for none (a style may leave out a mark whose word is
  ;; written beside it). mark is (level n of): of bars rising, the first n
  ;; in color and the rest faint; circle, diamond or square, filled; blocked,
  ;; a no-entry sign; or dot, a state's.
  (define-part (ui-draw-mark x y s mark color)
    (case (if (pair? mark) (car mark) mark)
      [(level)
       (let* ([n (cadr mark)] [of (caddr mark)] [bw (/ s (+ of 1))]
              [gap (if (> of 1) (/ (- s (* of bw)) (- of 1)) 0)])
         (do ([i 0 (+ i 1)]) ((= i of))
           (let ([bh (* s (/ (+ i 2) (+ of 1)))])
             (fill-box (+ x (* i (+ bw gap))) (+ y (- s bh)) bw bh
                       (if (< i n) color (alpha 'text-faint 0.35))
                       1))))]
      [(circle)
       (let ([c (/ s 2)]) (fill-circle (+ x c) (+ y c) (* c 0.85) color))]
      [(diamond)
       (let ([c (/ s 2)])
         (fill-polygon (list (cons (+ x c) y) (cons (+ x s) (+ y c))
                             (cons (+ x c) (+ y s)) (cons x (+ y c)))
                       color))]
      [(square) (fill-box (+ x 1) (+ y 1) (- s 2) (- s 2) color 2)]
      [(blocked)
       (fill-circle (+ x (/ s 2)) (+ y (/ s 2)) (* s 0.45) color)
       (fill-box (+ x (* s 0.25)) (+ y (* s 0.41)) (* s 0.5) (* s 0.18)
                 (color-readable-on color))]
      [(dot) (fill-circle (+ x (/ s 2)) (+ y (/ s 2)) (/ s 3) color)])
    s)

  ;; Draws a due date's label at (x, y), cut to w: when is past (red), today
  ;; (orange) or #f.
  (define-part (ui-draw-due x y w label when font)
    (draw-text x y (text-fit label w font)
               (case when [(past) 'red] [(today) 'orange] [else 'text-faint])
               font)))
