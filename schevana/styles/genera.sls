;;; (schevana styles genera) — the Genera window style. Symbolics Genera
;;; was the Lisp Machine system of the 1980s. Programming the User
;;; Interface (Genera 7, 1986; the same in Genera 8) puts a pane's label
;;; "in the lower, left-hand corner of the pane (directly inside the
;;; border)", inside a 4-pixel white margin. Real Genera 8 screens, measured
;;; in captures from 1998, 2004 and 2024, draw that border 2 pixels thick
;;; (the manual's 1 is a bare pane's default) and the label in italic, in
;;; normal video. There is no title bar, no buttons and no mark of the
;;; selected window: Genera never had them (the buttons in some pictures
;;; belong to the X or Mac window around the whole Genera screen). Here you
;;; drag the label strip, and right-clicking it gives the window menu;
;;; Genera did both from its System menu instead. The research is in
;;; .work/reports/ ("Symbolics Genera window appearance").
;;;
;;; The screen is Genera's too: no top bar, and at the bottom the who line,
;;; with what the mouse buttons do in reverse video over a line of fields
;;; in character columns. A window that is not selected is grayed over;
;;; buttons are command words, boxed under the pointer and in inverse video
;;; while chosen. Its numbers are settings, so a style derived from it
;;; changes them (the CADR, (schevana styles cadr)).

(library (schevana styles genera)
  (export
    genera-insets genera-regions genera-draw-under genera-draw-over
    genera-who-line-areas genera-draw-who-line genera-busy-size genera-busy
    genera-mouse-doc-text genera-focus genera-button genera-button-size
    genera-checkbox genera-checkbox-size genera-toggle genera-toggle-size
    genera-tab genera-tabs-size genera-field genera-text-box-areas
    genera-text-box-size genera-dropdown genera-dropdown-size genera-chip
    genera-chip-size genera-chip-areas genera-card genera-scrollbar-areas
    genera-scrollbar genera-slider genera-progress genera-table-header
    genera-table-row genera-tree-row genera-dim genera-surface genera-panel
    genera-highlight genera-highlight-over genera-separator genera-tooltip
    genera-tooltip-size genera-dialog-size genera-dialog-areas genera-dialog
    genera-scrim genera-calendar-areas genera-calendar-size genera-calendar
    genera-day genera-5x5 genera-avatar-size genera-avatar genera-mark
    genera-due genera-board-slot genera-italic-of genera-draw-wallpaper
    genera-menu-grid-heading genera-menu-grid-item genera-inline-choice
    genera-inline-choice-size genera-keycap genera-choice-grid-cell
    genera-radio genera-live-badge genera-banner)
  (import (chezscheme)
          (only (schevana base) at-load clamp define-made library-layer
                string-join string-suffix?)
          (only (schevana core) *bitmap-fonts* *focus* *windows*
                color-default! define-bitmap-font define-style draw-scale
                draw-text fill-box fill-circle fill-wallpaper font font-ascent
                font-char-width
                font-family font-line-height font-size
                get-font
                screen-h screen-w stipple stroke-box stroke-circle text-width
                theme theme-default! theme-rule window-bg window-covered?
                window-h window-ref
                window-title window-w with-clip with-place)
          (only (schevana kits px) px-bitmap-text px-bits px-invert px-bevel)
          (schevana styles genera font-5x5)
          (schevana styles genera fonts)
          (only (schevana kits text) text-widest text-draw-centered text-fit
                text-ink)
          (only (schevana kits ui) ui-draw-mark* ui-initials ui-calendar-areas
                ui-dialog-areas ui-dialog-lines ui-tooltip-lines ui-draw-panel
                ui-draw-dim ui-draw-table-row ui-tree-areas ui-table-cell-inset
                ui-scrollbar-areas ui-chip-areas ui-small-glyph-size
                ui-text-box-top ui-scrollbar-width ui-control-height
                ui-draw-focus ui-draw-glyph ui-glyph-size ui-busy-frame-ms
                ui-italic-of ui-wrap-lines ui-fade ui-live-badge-mark
                ui-live-badge-back ui-draw-radio* ui-radio-text-x
                ui-banner-areas))

  (library-layer looks)

  ;; The label strip is the label's line and 2 pixels (the CADR's label
  ;; spacing), at least 14. Its top in the window lies under the white
  ;; margin, directly inside the border (Genera), or right under the
  ;; content, with the margin below the strip (the CADR).
  (define (genera-label-height)
    (exact (max 14 (round (+ (font-line-height (theme 'genera-label-font))
                             2)))))

  (define (genera-label-y win)
    (- (window-h win) (theme 'genera-border) (genera-label-height)
       (if (eq? (theme 'genera-label-under) 'content) (theme 'genera-margin)
           0)))

  (define (genera-insets win)
    (let* ([b (theme 'genera-border)] [m (theme 'genera-margin)] [s (+ b m)])
      (values s s s (+ b (genera-label-height) m))))

  ;; The label strip is the window's title area. The corners and the bottom
  ;; edge stay free for resizing.
  (define (genera-regions win)
    (list (list 'title 14 (genera-label-y win) (- (window-w win) 28)
                (- (genera-label-height) 4))))

  (define (genera-draw-under win x y w h focused? hover pressed)
    (let ([b (theme 'genera-border)] [m (theme 'genera-margin)]
          [f (theme 'genera-label-font)] [lh (genera-label-height)])
      (fill-box x y w h 'text)   ; on whole device pixels at any scale
      (fill-box (+ x b) (+ y b) (- w b b) (- h b b) (window-bg win))
      (with-clip (x y w h)   ; even "…" may not fit a narrow window
        (draw-text (+ x b m)
                   (+ y (genera-label-y win)
                      (if (eq? (theme 'genera-label-align) 'top)
                          0
                          (floor (/ (- lh (font-line-height f)) 2))))
                   (text-fit (window-title win) (- w (* 2 (+ b m))) f)
                   'text f))))

  ;; A window partly covered by another is grayed over, frame and all, as
  ;; Genera grays a window it has deexposed: a sparse stipple of ink on
  ;; clear paper (about 6 %, report:47). Exposure is not selection: a
  ;; window wholly in view stays clear, selected or not, and only a window
  ;; covers one, not a menu or what a dialog lies over (PUI p.1929).
  (define (genera-draw-over win x y w h focused? hover pressed)
    (when (window-covered? win)
      (fill-box x y w h 'genera-gray)))

  ;;; the who line

  ;; Its status row is the code font's line and the who line's spacing
  ;; (genera-who-line-spacing); above it, the mouse documentation's rows,
  ;; each a line of its font and the spacing: Genera keeps two of them and
  ;; a status row (UG p.2803), the CADR one row of each with no spacing,
  ;; all in CPTFONT (WHO-LINE-SETUP's :VSP 0, wholin.lisp:52-106).
  (define (genera-line)
    (exact (round (+ (font-line-height 'mono)
                     (theme 'genera-who-line-spacing)))))

  (define (genera-doc-line)
    (exact (round (+ (font-line-height (theme 'genera-mouse-doc-font))
                     (theme 'genera-who-line-spacing)))))

  (define (genera-doc-height)
    (* (theme 'genera-mouse-doc-lines) (genera-doc-line)))

  ;; The settings' defaults, so that Genera's parts draw in any look.
  (at-load
   (theme-default! 'genera-who-line-spacing 2))
  (at-load
   (theme-default! 'genera-mouse-doc-lines 2))
  (at-load
   (theme-default! 'genera-mouse-doc-font 'mono))
  (at-load
   (theme-default! 'genera-hover-ink-gap #f))
  (at-load
   (theme-default! 'genera-choice-padding 0))
  (at-load
   (theme-default! 'genera-choice-side (theme-rule (round (font-ascent 'ui)))))

  ;; Its fields, at character columns as on the CADR (lispm.md 2.1), in the
  ;; taskbar's strip, h high: what the mouse buttons do, across the top
  ;; rows; and below, the selected window, a field that counts the windows,
  ;; the run state (as on the CADR, after the package) and the status.
  (define (genera-who-line-areas h hint)
    (let* ([lh (genera-line)] [dh (genera-doc-height)]
           [y (- (screen-h) h)] [sy (+ y dh)]
           [cw (font-char-width 'mono)])
      (list (list 'mouse-doc 0 y (screen-w) dh)
            (list 'title cw sy (* 24 cw) lh)
            (list 'windows (* 26 cw) sy (* 11 cw) lh)
            (list 'state (* 38 cw) sy (* 12 cw) lh)
            (list 'status (* 51 cw) sy (max 0 (- (screen-w) (* 52 cw)))
                  lh))))

  ;; The who line in its fields (genera-who-line-areas): the mouse
  ;; documentation, doc, wrapped across its top rows in reverse video, and
  ;; the status's strings below.
  (define (genera-draw-who-line h as open? doc status hint)
    (let* ([lh (genera-line)] [dh (genera-doc-height)] [w (screen-w)]
           [dl (genera-doc-line)] [df (theme 'genera-mouse-doc-font)]
           [y (- (screen-h) h)] [cw (font-char-width 'mono)]
           [ty (lambda (y) (+ y (floor (/ (- lh (font-line-height 'mono)) 2))))]
           [field (lambda (what s)
                    (apply (lambda (fx fy fw fh)
                             (draw-text fx (ty fy) (text-fit s fw 'mono) 'text
                                        'mono))
                           (cdr (assq what as))))])
      (fill-box 0 y w dh 'text)
      (when doc
        (let-values ([(lines cut?)
                      (ui-wrap-lines doc (max 1 (- w cw cw)) df
                                     (theme 'genera-mouse-doc-lines))])
          (with-clip (0 y w dh)
            (let loop ([lines lines]
                       [ly (+ y (floor (/ (- dl (font-line-height df)) 2)))])
              (unless (null? lines)
                (draw-text cw ly (car lines) 'bg-1 df)
                (loop (cdr lines) (+ ly dl)))))))
      (fill-box 0 (+ y dh) w lh 'bg-1)
      (field 'title (if *focus* (window-title *focus*) "No selected window"))
      (field 'windows (let ([n (length *windows*)])
                        (format "~a window~a" n (if (= n 1) "" "s"))))
      (field 'state (genera-who-state))
      (field 'status (string-join (filter string? (map cdr status)) "  "))))

  ;; The run state: Run while the selected window is at work (its 'busy),
  ;; as the who line showed a process's state; otherwise nothing.
  (define (genera-who-state)
    (if (and *focus* (window-ref *focus* 'busy)) "Run" ""))

  ;; The busy mark where the work shows (a REPL's prompt): a terminal's
  ;; spinner, | / - \ turning in the code font, in one character's cell; the
  ;; mouse boxes it, as it boxes anything that tells more.
  (define (genera-busy-size)
    (values (font-char-width 'mono) (font-line-height 'mono)))

  (define (genera-busy x y w h flags ms)
    (draw-text x y (string (string-ref "|/-\\"
                                       (mod (quotient ms (ui-busy-frame-ms))
                                            4)))
               (if (memq 'bar flags) 'panel-text 'text) 'mono)
    (when (memq 'hover flags) (genera-hover x y w h)))

  ;; "Mouse-L: Move; Mouse-R: Window menu."
  (define (genera-mouse-doc-text doc)
    (if (null? doc)
        ""
        (string-append
         (string-join (map (lambda (b) (format "Mouse-~a: ~a" (car b) (cdr b)))
                           doc)
                      "; ")
         ".")))

  ;; A window that is not selected is grayed over with this: a sparse
  ;; stipple of ink on clear paper, Genera 8.3's 6 % in a 16 × 8 tile, one
  ;; dot a row, each row's six columns on from the one above (a 2024
  ;; capture of Genera 8.3). It is a color, which you may change and save.
  ;; Rows the search leaves out are grayed with it too.
  (at-load
   (color-default! 'genera-gray
                   (stipple 'text #f
                            "#..............."
                            "......#........."
                            "............#..."
                            "..#............."
                            "........#......."
                            "..............#."
                            "....#..........."
                            "..........#.....")))
  ;; A scroll bar's elevator: 33 %, diagonal (lispm-apps.md 2.4).
  (at-load
   (color-default! 'genera-elevator (stipple 'text #f "#.." ".#." "..#")))

  ;;; ------------------------------------------------------------------
  ;;; the widgets
  ;;; Each widget is the original's own where it had one, and otherwise
  ;;; what its authors would have made from their parts
  ;;; (.work/style/research/lispm-apps.md part 4): ink on paper and no
  ;;; color; a 1-pixel box for what the mouse is over, inverse video for
  ;;; what is chosen, bold for the current value, italic for a hint
  ;;; ('faint-text-font), and an underline for the keyboard's place. What
  ;;; can't be used now is in italic too, its marks drawn through the 50 %
  ;;; gray (disabled-fade), and the mouse boxes none of it. Where the CADR
  ;;; differs, a setting says how ((schevana styles cadr)).

  ;; Returns the ink of a mark (a box, a rule, a glyph) by the flags: the
  ;; text's, or faded while disabled.
  (define (genera-ink flags) (if (memq 'disabled flags) (ui-fade 'text) 'text))

  ;; Returns the ink of a word by the flags: the text's, or disabled
  ;; (italic, or the CADR's gray) while disabled.
  (define (genera-word-ink flags)
    (if (memq 'disabled flags) 'text-disabled 'text))

  ;; Whether the mouse's box shows: under the mouse (or pressed), and not
  ;; while disabled.
  (define (genera-hot? flags)
    (and (not (memq 'disabled flags))
         (or (memq 'hover flags) (memq 'pressed flags))))

  ;; A color that is another's: whatever the palette gives that one, so
  ;; that every hue is the palette's ink and every ground its paper, as on a
  ;; screen one bit deep (lispm-apps.md part 1).
  (define (genera-same key) (theme-rule (theme key)))

  ;; What the mouse is over gets a 1-pixel box; the CADR's sticks out a
  ;; pixel at the top and left, "the right thing for boxing text"
  ;; (sheet.lisp:2349-2364), as genera-hover-nudge sets.
  (define (genera-hover x y w h)
    (let ([n (theme 'genera-hover-nudge)])
      (stroke-box (- x n) (- y n) (+ w n) (+ h n) 'text)))

  ;; What the mouse is over, where it is a word drawn from (tx, ty): the
  ;; box, grown where the word's ink would touch it, so that a clear pixel
  ;; always lies between the ink and the box, glyphs that overhang their
  ;; advance too (genera-hover-ink-gap; the 2-pixel outset of Peek's
  ;; menus). The CADR boxes the cell as it is. The word lies on whole
  ;; pixels (genera-text-x, genera-text-y), so its ink is where it is
  ;; measured.
  (define (genera-hover-text x y w h tx ty label font)
    (if (not (theme 'genera-hover-ink-gap))
        (genera-hover x y w h)
        (let-values ([(l t iw ih) (text-ink label font)])
          (let* ([l (+ tx l)] [t (+ ty (font-ascent font) t)]
                 [left (min x (- l 2))] [top (min y (- t 2))])
            (genera-hover left top (- (max (+ x w) (+ l iw 2)) left)
                          (- (max (+ y h) (+ t ih 2)) top))))))

  ;; A box n pixels thick.
  (define (genera-box x y w h n . ink)
    (let ([c (if (null? ink) 'text (car ink))]) (px-bevel x y w h c c n)))

  ;; The top of a text in a box h high at y, so that its line is centered
  ;; in the box, on a whole pixel.
  (define (genera-text-y y h font)
    (floor (+ y (/ (- h (font-line-height font)) 2) 1/2)))

  ;; The left of a text centered in a box w wide at x, on a whole pixel.
  (define (genera-text-x x w text font)
    (floor (+ x (/ (- w (text-width text font)) 2) 1/2)))

  ;; The keyboard's place: underlined (UG p.2762).
  (define (genera-focus x y w h flags r) (fill-box x (+ y h -1) w 1 'text))

  ;; A command word (Peek's, the Inspector's): plain, boxed under the
  ;; mouse, and in inverse video while it is the one chosen (a segment). A
  ;; press shows nothing more (lispm-notes, answer 10). The default stands
  ;; out: bold in Genera, and in the CADR's standout italic. On the CADR a
  ;; dialog's words are margin choices, each followed by a choice box that
  ;; is on while the word is pressed (choice.lisp:441-526).
  (define (genera-button x y w h flags label glyph)
    (let* ([on? (lambda (f) (memq f flags))]
           [live? (not (on? 'disabled))]
           [rev? (and live? (on? 'selected))]
           [font (theme (if (on? 'primary)
                            'genera-standout-font
                            'genera-command-font))]
           [ink (cond [rev? 'window-bg] [live? 'text] [else 'text-disabled])]
           [box? (and label (theme 'genera-margin-choice))]
           [s (genera-choice-side)] [sp (font-char-width font)]
           [text (and label (not box?) (text-fit label (- w 4) font))]
           [tx (and text (genera-text-x x w text font))]
           [ty (genera-text-y y h font)])
      (cond [rev? (fill-box x y w h 'text)]
            [(and live? (or (on? 'hover) (on? 'pressed)))
             (if text
                 (genera-hover-text x y w h tx ty text font)
                 (genera-hover x y w h))])
      (cond
        [box?
         (let* ([text (text-fit label (- w 4 sp s) font)]
                [x0 (+ x (/ (- w (text-width text font) sp s) 2))]
                [end (draw-text x0 (genera-text-y y h font) text ink font)])
           (genera-choice-box (+ end sp) (+ y (/ (- h s) 2)) s
                              (on? 'pressed)))]
        [label (draw-text tx ty text ink font)]
        [glyph
         (let ([g (ui-glyph-size)])
           (ui-draw-glyph (+ x (/ (- w g) 2)) (+ y (/ (- h g) 2)) g g
                          (list (cons 'ink (if live? ink (ui-fade 'text))))
                          glyph))])
      (when (on? 'focused) (ui-draw-focus x y w h flags 0))))

  ;; The word and a little room, wide enough in either font.
  (define (genera-button-size label glyph)
    (let ([h (ui-control-height)])
      (values (if label
                  (+ 12 (max (text-width label (theme 'genera-command-font))
                             (text-width label (theme 'genera-standout-font))))
                  h)
              h)))

  ;; The choice box: a square genera-choice-side wide (Genera's as tall as
  ;; the body font's capitals, the CADR's its line), its frame a quarter of
  ;; its side thick on the CADR (genera-choice-heavy) and a pixel in
  ;; Genera, and, when on, an X in it, thick on the CADR
  ;; (choice.lisp:441-464).
  (define (genera-choice-side) (theme 'genera-choice-side))

  (define (genera-choice-box x y s on? . ink)
    (let* ([heavy? (theme 'genera-choice-heavy)]
           [ink (if (null? ink) 'text (car ink))]
           [f (if heavy? (max 1 (quotient s 4)) 1)] [n (- s f f)])
      (fill-box x y s s 'window-bg)
      (genera-box x y s s f ink)
      (when on?
        (do ([i 0 (+ i 1)]) ((= i n))
          (for-each (lambda (c)
                      (fill-box (+ x f c) (+ y f i) (if heavy? 2 1) 1 ink))
                    (if heavy?
                        (list (min i (- n 2)) (max 0 (- n 2 i)))
                        (list i (- n 1 i))))))))

  ;; A checkbox: its label, a space and the box (choice.lisp:505-512), all
  ;; boxed under the mouse; in Genera with genera-choice-padding of room at
  ;; either end, the box around the label's ink and the choice box with a
  ;; clear pixel, the CADR's around the cells.
  (define (genera-checkbox x y w h flags label)
    (let* ([s (genera-choice-side)] [sp (font-char-width 'ui)]
           [p (theme 'genera-choice-padding)] [tx (+ x p)]
           [ty (genera-text-y y h 'ui)]
           [text (and label (text-fit label (- w sp s p p) 'ui))]
           [end (if label
                    (draw-text tx ty text (genera-word-ink flags) 'ui)
                    tx)]
           [bx (if label (+ end sp) tx)] [by (+ y (/ (- h s) 2))])
      (genera-choice-box bx by s (memq 'checked flags) (genera-ink flags))
      (when (and (memq 'hover flags) (not (memq 'disabled flags)))
        (cond [(zero? p) (genera-hover x y (- (+ bx s 2) x) h)]
              [text (genera-hover-text (- bx 2) (- by 2) (+ s 4) (+ s 4)
                                       tx ty text 'ui)]
              [else (genera-hover (- bx 2) (- by 2) (+ s 4) (+ s 4))]))
      (when (memq 'focused flags)
        (ui-draw-focus x y (- (+ bx s) x) h flags 0))))

  (define (genera-checkbox-size label)
    (values (+ (text-width label 'ui) (font-char-width 'ui)
               (genera-choice-side) (* 2 (theme 'genera-choice-padding)))
            (ui-control-height)))

  ;; An on-off setting, as a boolean in the CADR's choose-variable-values:
  ;; "Name: Yes No", with the current word bold (choice.lisp:826-841). A
  ;; click sets the other word, so the mouse boxes that one.
  (define (genera-toggle x y w h flags label)
    (let* ([on? (memq 'checked flags)] [f (theme 'genera-choice-font)]
           [b (theme 'genera-choice-bold)] [sp (font-char-width 'ui)]
           [ink (genera-word-ink flags)]
           [x1 (if label
                   (draw-text x (genera-text-y y h 'ui)
                              (string-append label ":") ink 'ui)
                   x)])
      (let loop ([words '("Yes" "No")] [wx (+ x1 sp)] [current? on?])
        (unless (null? words)
          (let* ([font (if current? b f)]
                 [end (draw-text wx (genera-text-y y h font) (car words)
                                 ink font)])
            (when (and (not current?) (genera-hot? flags))
              (genera-hover-text (- wx 2) y (+ (- end wx) 4) h wx
                                 (genera-text-y y h font) (car words) font))
            (loop (cdr words) (+ wx (text-width (car words) b) sp)
                  (not current?)))))
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 0))))

  (define (genera-toggle-size label)
    (values (+ (if label (text-width (string-append label ":") 'ui) 0)
               (* 3 (font-char-width 'ui))
               (text-width "Yes" (theme 'genera-choice-bold))
               (text-width "No" (theme 'genera-choice-bold)))
            (ui-control-height)))

  ;; A tab, as one of Peek's modes (peek.lisp:117-148; J-peek): the word,
  ;; in inverse video while it is the current one, and boxed under the
  ;; mouse.
  (define (genera-tab x y w h flags label)
    (let* ([font (theme 'genera-command-font)] [sel? (memq 'selected flags)]
           [tx (genera-text-x x w label font)] [ty (genera-text-y y h font)])
      (cond [sel? (fill-box x y w h 'text)]
            [(genera-hot? flags) (genera-hover-text x y w h tx ty label font)])
      (draw-text tx ty label (if sel? 'window-bg (genera-word-ink flags)) font)
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 0))))

  (define (genera-tabs-size labels)
    (values (fold-left (lambda (acc l)
                         (+ acc 12 (text-width l (theme 'genera-command-font))))
                       0 labels)
            (ui-control-height)))

  ;; A value's place, as in an accept-values field: no box, only an
  ;; underline, heavier while it has the keyboard (lispm-notes, answer 4);
  ;; an area of lines is a pane (ZWEI's), boxed.
  (define (genera-field x y w h flags)
    ;; a device pixel at least, in Settings' miniatures too
    (let ([n (max (if (memq 'focused flags) 2 1)
                  (exact (ceiling (/ 1 (draw-scale)))))])
      (if (memq 'lines flags)
          (genera-box x y w h n (genera-ink flags))
          (fill-box x (- (+ y h) n) w n (genera-ink flags)))))

  ;; The text sits 2 pixels in, or after a search's magnifying glass; an
  ;; area of lines has its scroll bar at its left, as ZWEI's does.
  (define (genera-text-box-areas x y w h flags)
    (let* ([bw (ui-scrollbar-width)]
           [left (cond [(memq 'lines flags) (+ bw 4)]
                       [(memq 'search flags) (+ (ui-glyph-size) 14)]
                       [else 2])]
           [font (if (memq 'large flags) 'heading 'ui)]
           [top (ui-text-box-top h flags font 3)])
      (list (list 'edit (+ x left) (+ y top) (max 0 (- w left 3))
                  (max 0 (- h top top)) font)
            (list 'bar (+ x 2) (+ y 2) bw (max 0 (- h 4))))))

  (define (genera-text-box-size flags w rows)
    (with-place 'field
      (lambda ()
        (let ([large? (memq 'large flags)])
          (values w
                  (if (and (= rows 1) (not large?))
                      (ui-control-height)
                      (round (+ 6 (* rows (font-line-height
                                           (if large? 'heading 'ui)))))))))))

  ;; A choice, as an accept-values field shows one of a large type: only
  ;; the current value, in bold (UG p.2743-2744; lispm-notes, answer 5),
  ;; boxed under the mouse; a click opens the menu. A label shown instead
  ;; of a value is plain, and the placeholder for no value is faint.
  (define (genera-dropdown x y w h flags label)
    (let* ([font (if (or (memq 'label flags) (memq 'placeholder flags))
                     'ui
                     'ui-bold)]
           [ink (if (memq 'placeholder flags)
                    'text-faint
                    (genera-word-ink flags))]
           [text (text-fit label (- w 6) font)]
           [ty (genera-text-y y h font)])
      (when (or (genera-hot? flags) (memq 'open flags))
        (genera-hover-text x y w h (+ x 3) ty text
                           (if (memq 'placeholder flags)
                               (genera-italic-of (get-font font))
                               font)))
      (draw-text (+ x 3) ty text ink font)
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 0))))

  (define (genera-dropdown-size labels)
    (values (min (* 10 (font-line-height 'ui))
                 (+ 8 (text-widest labels 'ui-bold)))
            (ui-control-height)))

  ;; A tag as a Zmail keyword, in braces (E&M p.2434). A removable one has
  ;; a × after it, and the mouse's box goes around the × alone, which is
  ;; what a click removes.
  (define (genera-chip x y w h flags label)
    (let* ([removable? (memq 'removable flags)] [g (ui-small-glyph-size)]
           [room (- w (text-width "{}" 'ui) (if removable? (+ g 4) 0))])
      (draw-text x (genera-text-y y h 'ui)
                 (string-append "{" (text-fit label room 'ui) "}")
                 (genera-word-ink flags) 'ui)
      (when removable?
        (let ([a (cdr (assq 'remove (ui-chip-areas x y w h)))])
          (ui-draw-glyph (+ (car a) (/ (- (caddr a) g) 2))
                         (+ (cadr a) (/ (- (cadddr a) g) 2)) g g
                         (list (cons 'ink (genera-ink flags))) 'cross)
          (when (genera-hot? flags) (apply genera-hover a))))))

  (define (genera-chip-size label removable?)
    (values (+ (text-width (string-append "{" label "}") 'ui)
               (if removable? (+ (ui-small-glyph-size) 4) 0))
            (round (+ (font-line-height 'ui) 2))))

  (define (genera-chip-areas x y w h)
    (let ([g (ui-small-glyph-size)])
      (list (list 'remove (- (+ x w) g 4) y (+ g 4) h))))

  ;; A banner across a view is output in a border too, as a card is, its
  ;; words bold: no tint, which a screen one bit deep has none of.
  (define (genera-banner x y w h flags title label)
    (let ([t (cdr (assq 'title (ui-banner-areas x y w h title label)))])
      (fill-box x y w h 'window-bg)
      (genera-box x y w h 1)
      (draw-text (car t) (genera-text-y y h 'ui-bold)
                 (text-fit title (caddr t) 'ui-bold) 'text 'ui-bold)))

  ;; A card is a record, as Genera's output in a border (PUI p.1685,
  ;; p.1696): a 1-pixel box, 2 pixels while chosen (the CADR's box blinker,
  ;; sheet.lisp:2365; lispm-notes, answer 3), with the mouse's box just
  ;; outside it.
  (define (genera-card x y w h flags)
    (genera-box x y w h (if (memq 'selected flags) 2 1))
    (when (memq 'hover flags)
      (stroke-box (- x 2) (- y 2) (+ w 4) (+ h 4) 'text)))

  ;; Genera's scroll bar, as measured (lispm-apps.md 2.4; report:35-41) and
  ;; as the 1998 Peek and Listener captures show it pixel for pixel: dotted
  ;; 1-pixel sides, a box as wide as the bar at each end (up and down), and
  ;; between them the elevator, a 1-pixel outline on paper around a 33 %
  ;; stipple.
  (define (genera-scrollbar-areas x y w h start size)
    (let* ([e (min w (floor (/ h 3)))] [l (- h e e)]
           [th (min l (max w (* size l)))])
      (list (list 'thumb x
                  (+ y e (if (< size 1) (* (- l th) (/ start (- 1 size))) 0))
                  w th)
            (list 'track x (+ y e) w l)
            (list 'up x y w e)
            (list 'down x (- (+ y h) e) w e))))

  (define-made genera-dotted (stipple 'text #f "#" "."))

  (define (genera-scrollbar x y w h flags start size)
    (let ([e (min w (floor (/ h 3)))]
          [t (cdr (assq 'thumb (ui-scrollbar-areas x y w h start size)))])
      (fill-box x y w h 'window-bg)
      (fill-box x y 1 h genera-dotted)
      (fill-box (+ x w -1) y 1 h genera-dotted)
      (stroke-box x y w e 'text)
      (stroke-box x (- (+ y h) e) w e 'text)
      (apply (lambda (tx ty tw th)
               (fill-box tx ty tw th 'window-bg)
               (stroke-box tx ty tw th 'text)
               (fill-box (+ tx 1) (+ ty 1) (max 0 (- tw 2)) (max 0 (- th 2))
                         'genera-elevator))
             t)))

  ;; Neither machine had a slider; typed numbers did its job (CLIM2
  ;; p.1151). Its authors would have turned the scroll bar sideways: a
  ;; shaft of 1-pixel sides and a short stippled block at the value.
  (define (genera-slider x y w h flags frac paint)
    (let* ([cy (round (+ y (/ h 2)))] [kx (+ x (* frac w))]
           [ink (genera-ink flags)])
      (if paint
          (with-clip (x (- cy 4) w 8) (paint x (- cy 4) w 8))
          (begin (fill-box x (- cy 5) w 1 ink)
                 (fill-box x (+ cy 4) w 1 ink)))
      (fill-box (- kx 6) (- cy 5) 12 10 'window-bg)
      (stroke-box (- kx 6) (- cy 5) 12 10 ink)
      (unless (memq 'disabled flags)
        (fill-box (- kx 5) (- cy 4) 10 8 'genera-elevator))
      (when (genera-hot? flags)
        (genera-hover (- kx 8) (- cy 7) 16 14))))

  ;; A progress note's bar: thin, solid, from the left, with no track
  ;; (UG p.2740; J-zmail).
  (define (genera-progress x y w h flags frac)
    (when (> frac 0)
      (fill-box x (+ y (floor (/ (- h 2) 2))) (* w (min 1 frac)) 2 'text)))

  ;; A column's heading: Peek's plain line (peek.lisp:270-273), or the
  ;; PUI's italic and underlined (genera-heading-underline, PUI p.1886).
  ;; The sort is the character set's arrow after it, or before it over a
  ;; right-aligned column, so that the heading lines up with the column.
  (define (genera-table-header x y w h flags label dir)
    (let* ([f (theme 'genera-heading-font)]
           [mark (case dir [(up) "↑"] [(down) "↓"] [else #f])]
           [arrow (if mark (string-append " " mark) "")]
           [label (text-fit label (max 0 (- w 14 (text-width arrow f))) f)]
           [right? (memq 'right flags)]
           [s (cond [(not mark) label]
                    [right? (string-append mark " " label)]
                    [else (string-append label arrow)])]
           [ty (genera-text-y y h f)]
           [tx (if right?
                   (- (+ x w) (ui-table-cell-inset) (text-width s f))
                   (+ x (ui-table-cell-inset)))]
           [end (draw-text tx ty s 'text f)])
      (when (and (theme 'genera-heading-underline) (> (string-length s) 0))
        (fill-box tx (+ ty (font-ascent f) 1) (- end tx) 1 'text))
      (when (memq 'hover flags) (genera-hover x y w h))))

  ;; A row is boxed under the mouse. A chosen row is in inverse video: its
  ;; 2-pixel box is drawn here, and its inside is inverted by
  ;; ui-draw-highlight-over when its cells are drawn (lispm-notes,
  ;; answer 3).
  (define (genera-table-row x y w h flags)
    (cond [(memq 'selected flags) (genera-box x y w h 2)]
          [(memq 'hover flags) (genera-hover x y w h)]))

  ;; A tree shown by indentation, as FSEdit's (WB Fig. 39); a node's
  ;; triangle, from the MOUSE font, points right when closed and down when
  ;; open.
  (define (genera-tree-row x y w h flags w0 depth)
    (let ([areas (ui-tree-areas x y w0 h depth)]
          [g (round (* 3/4 (ui-glyph-size)))])
      (ui-draw-table-row x y w h flags)
      (when (memq 'kids flags)
        (let ([t (cdr (assq 'twisty areas))])
          (ui-draw-glyph (+ (car t) (/ (- (caddr t) g) 2)) (+ y (/ (- h g) 2))
                         g g '((ink . text))
                         (if (memq 'expanded flags) 'down 'right))))
      (ui-draw-dim x y (- (cadr (assq 'cell areas)) x) h flags)))

  ;; Rows the search leaves out are grayed over, as a window not in use
  ;; is.
  (define (genera-dim x y w h flags)
    (when (and (memq 'dim flags) (not (memq 'selected flags)))
      (fill-box x y w h 'genera-gray)))

  ;; Panes: a well is boxed, and a strip is ruled off where it meets the
  ;; rest.
  (define (genera-surface x y w h flags)
    (fill-box x y w h 'window-bg)
    (cond [(memq 'well flags) (stroke-box x y w h 'text)]
          [(memq 'toolbar flags) (fill-box x (+ y h -1) w 1 'text)]
          [(memq 'footer flags) (fill-box x y w 1 'text)]
          [(memq 'side flags) (fill-box x y 1 h 'text)]
          [(memq 'nav flags) (fill-box (+ x w -1) y 1 h 'text)]))

  ;; A popup: Genera's has a 2-pixel border, and the CADR's a 1-pixel one
  ;; with its white margin (lispm.md 2.8), as genera-panel-border sets.
  (define (genera-panel x y w h flags)
    ;; Genera's shadow: solid under what only the mouse uses, and a 50 %
    ;; stipple under what takes the keyboard too (report:51), a dialog, and
    ;; a menu, which takes arrows, Return and typing (UG p.2764); the CADR
    ;; had none.
    (when (theme 'genera-shadow)
      (fill-box (+ x 7) (+ y 7) w h
                (if (exists (lambda (f) (memq f flags)) '(toast tooltip))
                    'text
                    (stipple 'text #f "#." ".#"))))
    (fill-box x y w h 'window-bg)
    (genera-box x y w h (theme 'genera-panel-border)))

  ;; The entry under the mouse in a menu gets a 1-pixel box, inverted while
  ;; a button is held on it; one under the mouse elsewhere gets the box
  ;; too; the chosen one gets a 2-pixel box that ui-draw-highlight-over
  ;; fills in.
  (define (genera-highlight x y w h flags)
    (cond [(and (memq 'outline flags) (memq 'pressed flags))
           (fill-box x y w h 'text)]
          [(or (memq 'hover flags) (memq 'outline flags)) (genera-hover x y w
                                                                        h)]
          [else (genera-box x y w h 2)]))

  ;; Inverse video, inside the 2-pixel box (menu.lisp:855-893).
  (define (genera-highlight-over x y w h flags)
    (px-invert (+ x 2) (+ y 2) (- w 4) (- h 4)))

  ;; A light rule (UG p.2909), and in a menu a blank cell
  ;; (sysmen.lisp:277-282), as genera-separator-rule says.
  (define (genera-separator x y w h flags)
    (when (theme 'genera-separator-rule)
      (fill-box x (floor (+ y (/ h 2))) w 1 'text)))

  ;; A tooltip, the fallback for what the who line says: a pop-up
  ;; message's box (sysmen.lisp:612-628).
  (define (genera-tooltip x y w h flags text)
    (ui-draw-panel x y w h '(tooltip))
    (fold-left (lambda (ty line)
                 (draw-text (+ x 6) ty line 'text 'ui-small)
                 (+ ty (font-line-height 'ui-small)))
               (+ y 4) (ui-tooltip-lines text)))

  (define (genera-tooltip-size text)
    (let ([lines (ui-tooltip-lines text)])
      (values (+ 12 (min 280 (text-widest lines 'ui-small)))
              (+ 8 (* (length lines) (font-line-height 'ui-small))))))

  ;; A dialog, as Genera's accept-values window (UG Fig. 135) and the
  ;; CADR's choose-variable-values (choice.lisp:427-526, :916-922): the
  ;; title over a rule, the message, and below a rule its buttons, as words
  ;; in equal shares of the width.
  (define (genera-dialog-strip) (+ (ui-control-height) 4))

  (define (genera-dialog-size title message labels)
    (let* ([lh (font-line-height 'ui)] [b (theme 'genera-panel-border)]
           [in (* 2 (+ b 12))]
           [w (clamp (+ in (max (text-width title 'heading)
                                (text-width message 'ui)
                                (* (length labels)
                                   (+ 24 (text-widest
                                          labels
                                          (theme 'genera-command-font))))))
                     (* 22 lh) (* 32 lh))])
      (values w
              (round (+ b 6 (font-line-height 'heading) 6 1 10
                        (* lh (length (ui-dialog-lines message (- w in))))
                        10 1 (genera-dialog-strip) b)))))

  (define (genera-dialog-areas x y w h labels)
    (let* ([b (theme 'genera-panel-border)] [hh (font-line-height 'heading)]
           [sh (genera-dialog-strip)] [in (+ b 12)]
           [share (/ (- w b b) (max 1 (length labels)))])
      `((title ,(+ x in) ,(+ y b 6) ,(- w in in) ,hh)
        (message ,(+ x in) ,(+ y b 6 hh 6 1 10) ,(- w in in)
                 ,(- h b 6 hh 6 1 10 10 1 sh b))
        ,@(map (lambda (i)
                 (list 'button (+ x b (* i share)) (- (+ y h) b sh -2) share
                       (ui-control-height)))
               (iota (length labels))))))

  (define (genera-dialog x y w h flags title message)
    (let* ([areas (ui-dialog-areas x y w h '())]
           [t (cdr (assq 'title areas))] [m (cdr (assq 'message areas))]
           [b (theme 'genera-panel-border)])
      (ui-draw-panel x y w h '(dialog))
      (draw-text (car t) (cadr t) (text-fit title (caddr t) 'heading) 'text
                 'heading)
      (fill-box (+ x b) (+ (cadr t) (cadddr t) 6) (- w b b) 1 'text)
      (fold-left (lambda (ly line)
                   (draw-text (car m) ly line 'text 'ui)
                   (+ ly (font-line-height 'ui)))
                 (cadr m) (ui-dialog-lines message (caddr m)))
      (fill-box (+ x b) (- (+ y h) b (genera-dialog-strip) 1) (- w b b) 1
                'text)))

  ;; The kit's grids, key caps and inline choices, as the Lisp machines'
  ;; menus and accept-values drew them (PUI's choose-variable-values): a
  ;; menu's heading in its italic, its choices its menu's entries, boxed
  ;; under the mouse and reversed when chosen; a value among its fellows
  ;; in bold; a key in a lozenge of the 5X5 (shwarm.lisp:675-700); a
  ;; matrix's cell a choice box.
  (define (genera-menu-grid-heading x y w h flags label)
    (text-draw-centered x y w h label 'text
                        (or (theme 'menu-hint-font)
                            (genera-italic-of (get-font (theme 'menu-font))))))

  (define (genera-menu-grid-item x y w h flags label)
    (let* ([f (theme 'menu-font)] [text (text-fit label (- w 4) f)]
           [sel? (memq 'selected flags)]
           [tx (genera-text-x x w text f)] [ty (genera-text-y y h f)])
      (when sel? (fill-box x y w h 'text))
      (when (and (not (memq 'disabled flags))
                 (or (memq 'hover flags) (memq 'pressed flags)))
        (genera-hover-text x y w h tx ty text f))
      (draw-text tx ty text
                 (cond [sel? 'window-bg] [(memq 'disabled flags) 'text-disabled]
                       [else 'text])
                 f)
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 0))))

  (define (genera-inline-choice x y w h flags label)
    (let* ([f (theme (if (memq 'selected flags)
                         'genera-choice-bold
                         'genera-choice-font))]
           [tx (genera-text-x x w label f)] [ty (genera-text-y y h f)])
      (when (genera-hot? flags)
        (genera-hover-text x y w h tx ty label f))
      (draw-text tx ty label (genera-word-ink flags) f)
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 0))))

  (define (genera-inline-choice-size label)
    (values (+ 8 (text-width label (theme 'genera-choice-bold)))
            (ui-control-height)))

  (define (genera-keycap x y w h flags label)
    (when (genera-hot? flags)
      (genera-hover x y w h))
    (genera-lozenge (+ x (floor (/ (- w (genera-lozenge-width label)) 2)))
                    (+ y (floor (/ (- h 9) 2))) label (genera-ink flags))
    (when (memq 'focused flags) (ui-draw-focus x y w h flags 0)))

  ;; A choice of one among others listed: the kit's mark and label, which
  ;; are ink and paper here, the mouse's box around the mark and the label.
  (define (genera-radio x y w h flags label hint icon)
    (ui-draw-radio* x y w h (remq 'hover flags) label hint icon)
    (when (genera-hot? flags)
      (let* ([lh (font-line-height 'ui)]
             [ly (if hint (+ y 4) (+ y (/ (- h lh) 2)))]
             [tx (+ x (ui-radio-text-x icon))]
             [end (+ tx (text-width (text-fit label (- (+ x w) tx) 'ui) 'ui))])
        (genera-hover (- x 2) (- (floor ly) 1) (- end x -4) (+ lh 2)))))

  ;; Whether a view is live, as a command word: the mark (a dot, or the
  ;; pause bars) and the word, with no pill, boxed under the mouse.
  (define (genera-live-badge x y w h flags label)
    (let* ([live? (memq 'checked flags)] [f 'ui-small]
           [m (ui-live-badge-mark)] [ty (genera-text-y y h f)]
           [my (+ y (floor (/ (- h m) 2)))] [tx (+ x 8 m 6)]
           [ink (genera-ink flags)] [word (genera-word-ink flags)]
           [back (if live? 0 (text-width ui-live-badge-back f))]
           [label (text-fit label (max 0 (- (+ x w) tx back 10)) f)])
      (when (genera-hot? flags) (genera-hover x y w h))
      (if live?
          (fill-circle (+ x 8 (/ m 2)) (+ y (/ h 2)) (/ m 2) ink)
          (let ([bw (max 1 (quotient m 3))])
            (fill-box (+ x 8) my bw m ink)
            (fill-box (+ x 8 (- m bw)) my bw m ink)))
      (draw-text tx ty label word f)
      (unless live?
        (draw-text (+ tx (text-width label f)) ty ui-live-badge-back word f))
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 0))))

  (define (genera-choice-grid-cell x y w h flags)
    (let ([s (genera-choice-side)] [p (theme 'genera-choice-padding)])
      (genera-checkbox (+ x (/ (- w s) 2) (- p)) y (+ s p p) h flags #f)))

  ;; Nothing under a dialog: a temporary window neither deexposes nor grays
  ;; the window below it (PUI p.1929).
  (define (genera-scrim x y w h flags) (void))

  ;; The screen as Genera's: the chosen wallpaper and its colors, with
  ;; none of Schevana's own lettering on it.
  (define (genera-draw-wallpaper w h)
    (fill-wallpaper 0 0 w h (theme 'wallpaper) 'desktop-top 'desktop-bottom))

  ;; Neither machine had a calendar; dates were typed (UG Fig. 144). Its
  ;; authors would have set a month as a text table (lispm-apps.md 4.16;
  ;; lispm-notes, answer 9): headed by the weekdays as columns' headings,
  ;; each day in a column three characters wide, with its number at the
  ;; right.
  (define (genera-calendar-cell) (round (* 3 (font-char-width 'ui))))

  ;; Under the grid, Previous and Next, then Today and Clear, each in half
  ;; of the width, which their words (and the margin choices' boxes) set.
  (define (genera-calendar-areas x y w h)
    (let* ([cell (genera-calendar-cell)] [b (ui-control-height)]
           [lh (font-line-height 'ui)] [gx (+ x (/ (- w (* 7 cell)) 2))]
           [gy (+ y 6 b lh 4)] [fy (+ gy (* 6 cell) 6)] [half (/ (- w 20) 2)])
      `((title ,(+ x 8) ,(+ y 6) ,(- w 16) ,b)
        (week ,gx ,(+ y 6 b) ,(* 7 cell) ,(+ lh 4))
        (grid ,gx ,gy ,cell)
        (prev ,(+ x 8) ,fy ,half ,b)
        (next ,(+ x 12 half) ,fy ,half ,b)
        (today ,(+ x 8) ,(+ fy b 2) ,half ,b)
        (clear ,(+ x 12 half) ,(+ fy b 2) ,half ,b))))

  (define (genera-calendar-size)
    (let* ([word (+ (text-width "Previous" (theme 'genera-command-font))
                    (genera-choice-side) 20)]
           [w (max (+ 16 (* 7 (genera-calendar-cell))) (+ 20 (* 2 word)))]
           [t (cdr (assq 'today (ui-calendar-areas 0 0 w 0)))])
      (values w (round (+ (cadr t) (cadddr t) 8)))))

  (define (genera-calendar x y w h flags title)
    (let* ([areas (ui-calendar-areas x y w h)] [t (cdr (assq 'title areas))]
           [wk (cdr (assq 'week areas))] [cell (/ (caddr wk) 7)]
           [f (theme 'genera-heading-font)])
      (ui-draw-panel x y w h '())
      (apply text-draw-centered
             (append t (list title 'text (theme 'genera-standout-font))))
      (do ([i 0 (+ i 1)]) ((= i 7))
        (let* ([s (substring "MoTuWeThFrSaSu" (* 2 i) (+ 2 (* 2 i)))]
               [sx (- (+ (car wk) (* (+ i 1) cell)) 4 (text-width s f))]
               [ty (+ (cadr wk) 2)]
               [end (draw-text sx ty s 'text f)])
          (when (theme 'genera-heading-underline)
            (fill-box sx (+ ty (font-ascent f) 1) (- end sx) 1 'text))))))

  ;; A day: today is bold (the current value's emphasis), the chosen day
  ;; inverse, the keyboard's underlined, the one under the mouse boxed, and
  ;; another month's days and a disabled one faint.
  (define (genera-day x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))]
           [f (if (on? 'today) 'ui-bold 'ui)] [lh (font-line-height f)]
           [ty (genera-text-y y h f)] [sel? (on? 'selected)])
      (cond [sel? (fill-box x (- ty 1) w (+ lh 2) 'text)]
            [(genera-hot? flags)
             (genera-hover-text x (- ty 1) w (+ lh 2)
                                (- (+ x w) 4 (text-width label f)) ty label
                                (if (on? 'outside)
                                    (genera-italic-of (get-font f))
                                    f))])
      (draw-text (- (+ x w) 4 (text-width label f)) ty label
                 (cond [sel? 'window-bg] [(on? 'disabled) 'text-disabled]
                       [(on? 'outside) 'text-faint] [else 'text])
                 f)
      (when (on? 'cursor)
        (fill-box (+ x 2) (+ ty lh) (- w 4) 1 (if sel? 'window-bg 'text)))))

  ;; The CADR's lozenge: str in the 5X5's capitals in a box 9 high with
  ;; pointed ends, 9 plus 6 per character wide (shwarm.lisp:675-700, MIT).
  (define (genera-lozenge-width str) (+ 9 (* 6 (string-length str))))

  (define (genera-lozenge x y str color)
    (px-bits x y '("....#...."
                   "...#.#..."
                   "..#...#.."
                   ".#.....#."
                   "#.......#"
                   ".#.....#."
                   "..#...#.."
                   "...#.#..."
                   "....#....")
             (list (cons #\# color))
             'stretch (cons 4 (genera-lozenge-width str)))
    (px-bitmap-text (+ x 4) (+ y 2) (string-upcase str) genera-5x5 color))

  ;; A person: nothing where the name is written beside the avatar, or else
  ;; the initials in a lozenge.
  (define (genera-avatar-size flags name)
    (if (memq 'named flags)
        (values 0 0)
        (values (genera-lozenge-width (ui-initials name)) 9)))

  (define (genera-avatar x y w h flags name)
    (unless (memq 'named flags) (genera-lozenge x y (ui-initials name) 'text)))

  ;;; Marks (the kit's), each in ink: the shapes of Genera's MOUSE font (WB
  ;;; Fig. 14) and the CADR's choice box.

  ;; A level is its bars, those above it hollow, as a choice box that is
  ;; off; a circle and a lozenge are filled, and a square is a hollow box;
  ;; blocked is a fat circle with a minus in it; a state's dot is left out,
  ;; since its word is written beside it (lispm-apps.md part 5).
  (define (genera-mark x y s mark color)
    (case (if (pair? mark) (car mark) mark)
      [(dot) 0]
      [(level)
       (let* ([n (cadr mark)] [of (caddr mark)]
              [bw (max 3 (floor (/ (- s (- of 1)) of)))])
         (do ([i 0 (+ i 1)]) ((= i of) s)
           (let ([bh (round (* s (/ (+ i 2) (+ of 1))))]
                 [bx (+ x (* i (+ bw 1)))])
             (if (< i n)
                 (fill-box bx (- (+ y s) bh) bw bh 'text)
                 (stroke-box bx (- (+ y s) bh) bw bh 'text)))))]
      [(square) (stroke-box (+ x 2) (+ y 2) (- s 4) (- s 4) 'text) s]
      [(blocked)
       (stroke-circle (+ x (/ s 2)) (+ y (/ s 2)) (- (* s 0.45) 1) 'text 2)
       (fill-box (+ x (round (* s 0.3))) (+ y (floor (- (/ s 2) 1)))
                 (- s (* 2 (round (* s 0.3)))) 2 'text)
       s]
      [else (ui-draw-mark* x y s mark color)]))

  ;; A due date: bold once it has passed (lispm-notes, answer 8), otherwise
  ;; plain; "Today" speaks for itself.
  (define (genera-due x y w label when fnt)
    (let* ([f (get-font fnt)]
           [f (if (eq? when 'past)
                  (font (font-family f) (font-size f) 'bold)
                  f)])
      (draw-text x y (text-fit label w f) 'text f)))

  ;; Where a dragged card would land: a box over the gray.
  (define (genera-board-slot x y w h)
    (fill-box x y w h 'genera-gray)
    (stroke-box x y w h 'text))

  ;; On a plain white screen, ink on paper whatever the palette.
  ;; Genera's fonts, registered as the style loads.
  (at-load
   (for-each (lambda (f) (define-bitmap-font (car f) (cdr f)))
             genera-fonts))

  ;; Returns f's italic (faint-text-font): a bitmap font's own italic
  ;; strike, keeping its bold where the family has a bold italic (JESS has
  ;; none, so its bold's italic is its italic), else the kit's.
  (define (genera-italic-of f)
    (let* ([name (font-family f)]
           [bold? (string-suffix? " Bold" name)]
           [base (if bold?
                     (substring name 0 (- (string-length name) 5))
                     name)]
           [both (string-append base " Bold Italic")]
           [italic (string-append base " Italic")])
      (cond
        [(and bold? (hashtable-contains? *bitmap-fonts* both))
         (font both (font-size f) 'crisp)]
        [(hashtable-contains? *bitmap-fonts* italic)
         (font italic (font-size f) 'crisp)]
        [else (ui-italic-of f)])))

  (at-load
   (define-style genera "Genera"
     'palette 'genera
     'wallpaper 'flat
     'draw-wallpaper 'genera-draw-wallpaper
     'corner-radius 0   ; square, and so is everything drawn in it
     ;; a screen one bit deep: shapes crisp, every pixel ink or paper, and
     ;; what can't be used drawn through the 50 % gray, 50%-GRAY
     ;; (scrman.lisp:438), not in half ink
     'drawing-antialias #f
     'disabled-fade '(".#" "#.")
     'fill-glow #f
     'surface-tint 0
     'transcript-line-spacing 2
     'genera-border 2
     'genera-margin 4
     'genera-label-font 'ui-italic
     'genera-label-align 'center
     'genera-label-under 'margin
     'frame-insets 'genera-insets
     'frame-regions 'genera-regions
     'frame-under 'genera-draw-under
     'frame-over 'genera-draw-over
     ;; the screen: no top bar; the who line at the bottom
     'topbar-height 0
     'genera-who-line-spacing 2
     'genera-mouse-doc-lines 2
     'genera-mouse-doc-font (font "Genera SWISS12-CCAPS Bold" 14 'crisp)
     'taskbar-height (theme-rule (+ (genera-doc-height) (genera-line)))
     'draw-taskbar 'genera-draw-who-line
     'taskbar-areas 'genera-who-line-areas
     'ui-busy-size 'genera-busy-size
     'ui-draw-busy 'genera-busy
     'mouse-doc-text 'genera-mouse-doc-text
     ;; the fonts, Genera's own, each at its cell's height ((schevana styles
     ;; genera fonts)): what an app shows is in the code font (FIX,
     ;; CPTFONT), its command words in the sans (JESS13, JESS14 in menus),
     ;; titles in SWISS's large bold (HL14B), and a pane's heading in the
     ;; code font's italic (lispm-apps.md part 6)
     'mono-font "Genera CPTFONT"
     'mono-font-size 12
     'ui-font "Genera HL12"
     'ui-font-size 14
     'mono (font "Genera CPTFONT" 12 'crisp)
     'mono-small (font "Genera CPTFONT" 12 'crisp)
     'mono-bold (font "Genera CPTFONT Bold" 12 'crisp)
     'mono-italic (font "Genera CPTFONT Italic" 12 'crisp)
     'ui (theme-rule (theme 'mono))
     'ui-small (theme-rule (theme 'mono))
     'ui-bold (theme-rule (theme 'mono-bold))
     'ui-small-bold (theme-rule (theme 'mono-bold))
     'ui-italic (font "Genera HL12 Italic" 14 'crisp)
     'ui-bold-italic (font "Genera HL12 Bold Italic" 14 'crisp)
     'title (font "Genera HL14 Bold" 15 'crisp)
     'heading (font "Genera HL14 Bold" 15 'crisp)
     'big (font "Genera HL14 Bold" 30 'crisp)
     'genera-command-font (font "Genera JESS13" 13 'crisp)
     'genera-standout-font (font "Genera JESS13 Bold" 13 'crisp)
     'genera-choice-font 'mono
     'genera-choice-bold 'mono-bold
     'genera-heading-font 'mono-italic
     'genera-heading-underline #t
     'label-section-font 'ui-bold-italic
     'label-section-upcase #f
     'label-group-font 'ui-bold-italic
     'faint-text-font 'genera-italic-of
     'text-caret 'block
     'text-selection 'underline
     ;; the sizes: a line of the font and a little more
     'control-height (theme-rule (round (+ (font-line-height 'ui) 6)))
     'table-header-height (theme-rule (round (+ (font-line-height 'ui) 6)))
     'table-row-height (theme-rule (round (+ (font-line-height 'ui) 6)))
     ;; the menus: centered words, a blank cell between groups
     'menu-font (font "Genera JESS14" 14 'crisp)
     'menu-item-height
     (theme-rule (round (+ (font-line-height (theme 'menu-font)) 4)))
     'menu-separator-height (theme-rule (theme 'menu-item-height))
     'menu-pad 4
     'menu-text-x 6
     'menu-width-extra 0
     'menu-min-width 0
     'menu-align 'center
     'menu-snap-text #t
     ;; the chosen entry boxed around its ink, a clear pixel and the box
     ;; out from it (Peek's Reset menu)
     'menu-highlight 'ink
     'menu-highlight-outset 2
     ;; the filter's hint as the machine would type it, and the menu as
     ;; wide
     'menu-filter-hint "Type to filter..."
     'menu-fit-filter #t
     'menu-ink 'text
     'menu-ink-selected 'text
     'menu-ink-pressed 'window-bg
     'menu-icons #f
     'genera-separator-rule #t
     'places '((menu genera-separator-rule #f))
     'calendar-step-words #t
     ;; the widgets
     'surface-well-ring 1
     'genera-hover-nudge 0
     'genera-hover-ink-gap #t
     'genera-choice-padding 2
     'genera-choice-side (theme-rule (round (font-ascent 'ui)))
     'dropdown-selected-mark "  *"
     'genera-panel-border 2
     'genera-shadow #t
     'genera-choice-heavy #f
     'genera-margin-choice #f
     'ui-draw-button 'genera-button
     'ui-draw-menu-grid-heading 'genera-menu-grid-heading
     'ui-draw-menu-grid-item 'genera-menu-grid-item
     'ui-draw-inline-choice 'genera-inline-choice
     'ui-inline-choice-size 'genera-inline-choice-size
     'ui-draw-keycap 'genera-keycap
     'ui-draw-choice-grid-cell 'genera-choice-grid-cell
     'ui-draw-radio 'genera-radio
     'ui-draw-live-badge 'genera-live-badge
     'ui-draw-banner 'genera-banner
     'ui-button-size 'genera-button-size
     'ui-draw-checkbox 'genera-checkbox
     'ui-checkbox-size 'genera-checkbox-size
     'ui-draw-toggle 'genera-toggle
     'ui-toggle-size 'genera-toggle-size
     'ui-draw-tab 'genera-tab
     'ui-tabs-size 'genera-tabs-size
     'ui-draw-field 'genera-field
     'ui-text-box-areas 'genera-text-box-areas
     'ui-text-box-size 'genera-text-box-size
     'ui-draw-dropdown 'genera-dropdown
     'ui-dropdown-size 'genera-dropdown-size
     'ui-draw-chip 'genera-chip
     'ui-chip-size 'genera-chip-size
     'ui-chip-areas 'genera-chip-areas
     'ui-draw-card 'genera-card
     'ui-draw-scrollbar 'genera-scrollbar
     'ui-scrollbar-areas 'genera-scrollbar-areas
     'ui-draw-slider 'genera-slider
     'ui-draw-progress 'genera-progress
     'ui-draw-table-header 'genera-table-header
     'ui-draw-table-row 'genera-table-row
     'ui-draw-tree-row 'genera-tree-row
     'ui-draw-dim 'genera-dim
     'ui-draw-surface 'genera-surface
     'ui-draw-panel 'genera-panel
     'ui-draw-highlight 'genera-highlight
     'ui-draw-highlight-over 'genera-highlight-over
     'ui-draw-separator 'genera-separator
     'ui-draw-focus 'genera-focus
     'ui-draw-tooltip 'genera-tooltip
     'ui-tooltip-size 'genera-tooltip-size
     'ui-draw-dialog 'genera-dialog
     'ui-dialog-size 'genera-dialog-size
     'ui-dialog-areas 'genera-dialog-areas
     'ui-draw-scrim 'genera-scrim
     'ui-draw-calendar 'genera-calendar
     'ui-calendar-size 'genera-calendar-size
     'ui-calendar-areas 'genera-calendar-areas
     'ui-draw-day 'genera-day
     'ui-draw-avatar 'genera-avatar
     'ui-avatar-size 'genera-avatar-size
     'ui-draw-mark 'genera-mark
     'ui-draw-due 'genera-due
     'ui-draw-board-slot 'genera-board-slot
     'repl-paren-mark (stipple 'text #f "#..." "...." "..#." "....")
     'swatch-ring (stipple 'text 'window-bg "#." ".#")
     ;; a chart's series told apart by patterns of ink; a share of its bars
     ;; in solid ink (the accent's), and a marked bar grayed
     'chart-1 (stipple 'text #f "#." "#.")
     'chart-2 (stipple 'text #f "#.." "..." "...")
     'chart-3 (stipple 'text #f "##" "..")
     'chart-4 (stipple 'text #f "#.." ".#." "..#")
     'chart-5 (stipple 'text #f "#." ".#")
     'chart-6 (stipple 'text #f "#..." "...." "..#." "....")
     'chart-7 (stipple 'text #f "##" ".#")
     'chart-8 'text
     'chart-muted-1 (stipple 'text #f "#..." "...." "...." "....")
     'chart-muted-2 (stipple 'text #f "#" "." "." ".")
     'chart-mark 'genera-gray
     'chart-flag 'text
     'chart-ok (stipple 'text #f "#..." "...." "...." "....")
     ;; the feel
     'title-double-click 'none
     ;; a window moves and reshapes by a rectangle, not its contents
     ;; (MOUSE-SPECIFY-RECTANGLE, sysmen.lisp:200, :357)
     'drag-feedback 'outline
     'bell 'screen
     'menu-hover 'outline
     'mouse-doc #t
     'scrollbar-side 'left
     ;; the bar worked as the Lisp machines' was, by three buttons
     'scrollbar-input 'lispm
     'scrollbar-line-height (theme-rule (+ (font-line-height 'ui) 2))
     ;; the content kept clear of the scroll bar, as beside a pane's margin
     'scrollbar-margin 4
     'options '(palette
                accent
                wallpaper
                (genera-border "Border" 1 4)
                (genera-margin "White margin" 0 8)
                (genera-label-font "Label font"
                 (("Italic" . ui-italic)
                  ("Upright" . genera-command-font)
                  ("Code" . mono))))
     ;; no color
     'text-dim (genera-same 'text)
     'text-faint (genera-same 'text)
     'accent (genera-same 'text)
     'accent-2 (genera-same 'text)
     'red (genera-same 'text)
     'orange (genera-same 'text)
     'yellow (genera-same 'text)
     'green (genera-same 'text)
     'cyan (genera-same 'text)
     'teal (genera-same 'text)
     'magenta (genera-same 'text)
     'window-border (genera-same 'text)
     'window-border-focus (genera-same 'text)
     'bg-0 (genera-same 'bg-1)
     'bg-2 (genera-same 'bg-1)
     'bg-3 (genera-same 'bg-1))))
