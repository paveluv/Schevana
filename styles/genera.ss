;;; styles/genera.ss — the Genera window style.
;;; Symbolics Genera, the Lisp Machine system of the 1980s. Programming
;;; the User Interface (Genera 7, 1986; the same in Genera 8) puts a pane's
;;; label "in the lower, left-hand corner of the pane (directly inside the
;;; border)", inside a 4-pixel white margin. Real Genera 8 screens, measured
;;; in captures from 1998, 2004 and 2024, draw that border 2 pixels thick
;;; (the manual's 1 is a bare pane's default) and the label in italic, in
;;; normal video. No title bar, no buttons and no mark of the selected
;;; window: Genera never had them (the buttons in some pictures belong to
;;; the X or Mac window around the whole Genera screen). The label strip is
;;; what you drag here, and right-clicking it gives the window menu; Genera
;;; did both from its System menu instead. The research is in
;;; .work/reports/ ("Symbolics Genera window appearance").
;;;
;;; The screen is Genera's too: no top bar, and at the bottom the who line,
;;; what the mouse buttons do in reverse video over a line of fields in
;;; character columns. A window not selected is grayed over; buttons are
;;; command words, boxed under the pointer and reversed while pressed.
;;; Its numbers are settings, so a style derived from it changes them (the
;;; CADR, styles/cadr.ss).

;; The label strip: the label's line and 2 (the CADR's label spacing).
;; Its top in the window: under the white margin, directly inside the
;; border (Genera), or under the content (the CADR, its margin below).
(define (genera-label-height)
  (exact (max 14 (round (+ (font-line-height (theme 'genera-label-font))
                           2)))))

(define (genera-label-y win)
  (- (window-h win) (theme 'genera-border) (genera-label-height)
     (if (eq? (theme 'genera-label-under) 'content) (theme 'genera-margin) 0)))

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

;; A window not selected is grayed over, as Genera grays one it is not
;; using: a sparse stipple of ink on clear paper (about 6 %, report:47).
(define (genera-draw-over win x y w h focused? hover pressed)
  (unless focused?
    (let-values ([(l t r b) (frame-insets win)])
      (fill-box (+ x l) (+ y t) (- w l r) (- h t b) 'genera-gray))))

;;; the who line

;; Each of its two lines: the code font's line and 2.
(define (genera-line) (exact (round (+ (font-line-height 'mono) 2))))

;; Its fields, at character columns as the CADR's (lispm.md 2.1): what
;; the mouse buttons do across the top line; below, the selected window,
;; a field that counts the windows, the run state (as the CADR's, after
;; the package) and the status.
(define (genera-who-line-areas)
  (let ([lh (genera-line)] [y (- (screen-h) (taskbar-height))]
        [cw (font-char-width 'mono)])
    (list (list 'mouse-doc 0 y (screen-w) lh)
          (list 'title cw (+ y lh) (* 24 cw) lh)
          (list 'windows (* 26 cw) (+ y lh) (* 11 cw) lh)
          (list 'state (* 38 cw) (+ y lh) (* 12 cw) lh)
          (list 'status (* 51 cw) (+ y lh) (max 0 (- (screen-w) (* 52 cw)))
                lh))))

(define (genera-draw-who-line)
  (let* ([as (taskbar-areas)] [lh (genera-line)] [w (screen-w)]
         [y (- (screen-h) (taskbar-height))] [cw (font-char-width 'mono)]
         [ty (lambda (y) (+ y (floor (/ (- lh (font-line-height 'mono)) 2))))]
         [field (lambda (what s)
                  (apply (lambda (fx fy fw fh)
                           (draw-text fx (ty fy) (text-fit s fw 'mono) 'text
                                      'mono))
                         (cdr (assq what as))))])
    (fill-box 0 y w lh 'text)
    (draw-text cw (ty y) (text-fit (mouse-doc-text (mouse-doc)) (- w cw cw)
                                   'mono)
               'bg-1 'mono)
    (fill-box 0 (+ y lh) w lh 'bg-1)
    (field 'title (if *focus* (window-title *focus*) "No selected window"))
    (field 'windows (let ([n (length *windows*)])
                      (format "~a window~a" n (if (= n 1) "" "s"))))
    (field 'state (genera-who-state))
    (field 'status (string-join (shown-status-strings) "  "))))

;; The run state: Run while the selected window is at work (its 'busy), as
;; the who line tells a process's; else nothing.
(define (genera-who-state)
  (if (and *focus* (window-ref *focus* 'busy)) "Run" ""))

;; The busy mark where the work shows (a REPL's prompt): a terminal's
;; spinner, | / - \ turning in the code font, a character's cell; the
;; mouse over it boxes it, as over anything that tells more.
(define (genera-busy-size)
  (values (font-char-width 'mono) (font-line-height 'mono)))

(define (genera-busy x y w h flags ms)
  (draw-text x y (string (string-ref "|/-\\"
                                     (mod (quotient ms (ui-busy-frame-ms)) 4)))
             'text 'mono)
  (when (memq 'hover flags) (genera-hover x y w h)))

;; It shows the mouse documentation and the status (the clock).
(define (genera-who-line-tick)
  (status-tick taskbar-box)
  (mouse-doc-tick taskbar-box))

;; "Mouse-L: Move; Mouse-R: Window menu."
(define (genera-mouse-doc-text doc)
  (if (null? doc)
      ""
      (string-append
       (string-join (map (lambda (b) (format "Mouse-~a: ~a" (car b) (cdr b)))
                         doc)
                    "; ")
       ".")))

;; A window not selected is grayed over with this: a sparse stipple of
;; ink on clear paper; a color, which you may change and save. Rows the
;; search leaves out and what lies under a dialog are grayed with it too.
(color-default! 'genera-gray (stipple 'text #f "#..." "...." "...." "...."))
;; A scroll bar's elevator: 33 %, diagonal (lispm-apps.md 2.4).
(color-default! 'genera-elevator (stipple 'text #f "#.." ".#." "..#"))

;;; ------------------------------------------------------------------
;;; the widgets
;;; Each the original's own where it had one, else what its authors would
;;; have made of their parts (.work/style/research/lispm-apps.md part 4):
;;; ink on paper and no color; a 1-pixel box for what the mouse is over,
;;; inverse video for what is chosen, bold for the current value, italic
;;; for a hint ('faint-text-font), an underline for the keyboard's place.
;;; Where the CADR differs, a setting says how (styles/cadr.ss).

;; A color that is another's: what a palette gives it, so that every hue
;; is the palette's ink and every ground its paper, as on a screen one bit
;; deep (lispm-apps.md part 1).
(define (genera-same key) (theme-rule (theme key)))

;; What the mouse is over: a 1-pixel box; the CADR's sticks out a pixel
;; at the top and left, "the right thing for boxing text"
;; (sheet.lisp:2349-2364): genera-hover-nudge.
(define (genera-hover x y w h)
  (let ([n (theme 'genera-hover-nudge)])
    (stroke-box (- x n) (- y n) (+ w n) (+ h n) 'text)))

;; A box n pixels thick.
(define (genera-box x y w h n) (px-bevel x y w h 'text 'text n))

;; A text's top in a box h high at y: centered on its line.
(define (genera-text-y y h font) (+ y (/ (- h (font-line-height font)) 2)))

;; The keyboard's place: underlined (UG p.2762).
(define (genera-focus x y w h flags r) (fill-box x (+ y h -1) w 1 'text))

;; A command word (Peek's, the Inspector's): plain, boxed under the
;; mouse, inverse video while it is the one chosen (a segment). A press
;; shows no more (lispm-notes, answer 10). The default stands out: bold
;; in Genera, the CADR's standout italic. On the CADR a dialog's words
;; are margin choices, a choice box after each, on while it acts
;; (choice.lisp:441-526).
(define (genera-button x y w h flags label glyph)
  (let* ([on? (lambda (f) (memq f flags))]
         [live? (not (on? 'disabled))]
         [rev? (and live? (on? 'selected))]
         [font (theme (if (on? 'primary)
                          'genera-standout-font
                          'genera-command-font))]
         [ink (cond [rev? 'window-bg] [live? 'text] [else 'text-faint])]
         [box? (and label (theme 'genera-margin-choice))]
         [s (genera-choice-side)] [sp (font-char-width font)])
    (cond [rev? (fill-box x y w h 'text)]
          [(and live? (or (on? 'hover) (on? 'pressed)))
           (genera-hover x y w h)])
    (cond
      [box?
       (let* ([text (text-fit label (- w 4 sp s) font)]
              [x0 (+ x (/ (- w (text-width text font) sp s) 2))]
              [end (draw-text x0 (genera-text-y y h font) text ink font)])
         (genera-choice-box (+ end sp) (+ y (/ (- h s) 2)) s
                            (on? 'pressed)))]
      [label
       (text-draw-centered x y w h (text-fit label (- w 4) font) ink font)]
      [glyph
       (let ([g (ui-glyph-size)])
         (ui-draw-glyph (+ x (/ (- w g) 2)) (+ y (/ (- h g) 2)) g g
                        (list (cons 'ink ink)) glyph))])
    (when (on? 'focused) (ui-draw-focus x y w h flags 0))))

;; The word and a little room, as wide in either font.
(define (genera-button-size label glyph)
  (let ([h (ui-control-height)])
    (values (if label
                (+ 12 (max (text-width label (theme 'genera-command-font))
                           (text-width label (theme 'genera-standout-font))))
                h)
            h)))

;; The choice box: a square as tall as the body font's capitals, its
;; frame a quarter of its side on the CADR (genera-choice-heavy), a pixel
;; in Genera, and when on a thick X in it (choice.lisp:441-464).
(define (genera-choice-side) (round (font-ascent 'ui)))

(define (genera-choice-box x y s on?)
  (let* ([heavy? (theme 'genera-choice-heavy)]
         [f (if heavy? (max 1 (quotient s 4)) 1)] [n (- s f f)])
    (fill-box x y s s 'window-bg)
    (genera-box x y s s f)
    (when on?
      (do ([i 0 (+ i 1)]) ((= i n))
        (for-each (lambda (c)
                    (fill-box (+ x f c) (+ y f i) (if heavy? 2 1) 1 'text))
                  (if heavy?
                      (list (min i (- n 2)) (max 0 (- n 2 i)))
                      (list i (- n 1 i))))))))

;; A thing to mark: its name, a space and the box (choice.lisp:505-512),
;; boxed under the mouse.
(define (genera-checkbox x y w h flags label)
  (let* ([s (genera-choice-side)] [sp (font-char-width 'ui)]
         [end (if label
                  (draw-text x (genera-text-y y h 'ui)
                             (text-fit label (- w sp s) 'ui) 'text 'ui)
                  x)]
         [bx (if label (+ end sp) x)])
    (genera-choice-box bx (+ y (/ (- h s) 2)) s (memq 'checked flags))
    (when (memq 'hover flags) (genera-hover x y (- (+ bx s 2) x) h))
    (when (memq 'focused flags) (ui-draw-focus x y (- (+ bx s) x) h flags 0))))

(define (genera-checkbox-size label)
  (values (+ (text-width label 'ui) (font-char-width 'ui) (genera-choice-side))
          (ui-control-height)))

;; An on-off setting as a boolean of the CADR's choose-variable-values:
;; "Name: Yes No", the current one bold (choice.lisp:826-841). A click
;; sets the other, so the mouse boxes that one.
(define (genera-toggle x y w h flags label)
  (let* ([on? (memq 'checked flags)] [f (theme 'genera-choice-font)]
         [b (theme 'genera-choice-bold)] [sp (font-char-width 'ui)]
         [x1 (if label
                 (draw-text x (genera-text-y y h 'ui)
                            (string-append label ":") 'text 'ui)
                 x)])
    (let loop ([words '("Yes" "No")] [wx (+ x1 sp)] [current? on?])
      (unless (null? words)
        (let* ([font (if current? b f)]
               [end (draw-text wx (genera-text-y y h font) (car words)
                               'text font)])
          (when (and (not current?) (memq 'hover flags))
            (genera-hover (- wx 2) y (+ (- end wx) 4) h))
          (loop (cdr words) (+ wx (text-width (car words) b) sp)
                (not current?)))))
    (when (memq 'focused flags) (ui-draw-focus x y w h flags 0))))

(define (genera-toggle-size label)
  (values (+ (if label (text-width (string-append label ":") 'ui) 0)
             (* 3 (font-char-width 'ui))
             (text-width "Yes" (theme 'genera-choice-bold))
             (text-width "No" (theme 'genera-choice-bold)))
          (ui-control-height)))

;; A mode among others, Peek's (peek.lisp:117-148; J-peek): the word,
;; inverse video while it is the current one, boxed under the mouse.
(define (genera-tab x y w h flags label)
  (let ([font (theme 'genera-command-font)] [sel? (memq 'selected flags)])
    (cond [sel? (fill-box x y w h 'text)]
          [(memq 'hover flags) (genera-hover x y w h)])
    (text-draw-centered x y w h label (if sel? 'window-bg 'text) font)
    (when (memq 'focused flags) (ui-draw-focus x y w h flags 0))))

(define (genera-tabs-size labels)
  (values (fold-left (lambda (acc l)
                       (+ acc 12 (text-width l (theme 'genera-command-font))))
                     0 labels)
          (ui-control-height)))

;; A value's place, as an accept-values field's: no box, an underline, a
;; heavier one while it has the keyboard (lispm-notes, answer 4); an area
;; of lines is a pane (ZWEI's), boxed.
(define (genera-field x y w h flags)
  ;; a device pixel at least, in Settings' miniatures too
  (let ([n (max (if (memq 'focused flags) 2 1)
                (exact (ceiling (/ 1 (draw-scale)))))])
    (if (memq 'lines flags)
        (genera-box x y w h n)
        (fill-box x (- (+ y h) n) w n 'text))))

;; The text 2 pixels in, after a search's glass; an area's scroll bar at
;; its left, as ZWEI's.
(define (genera-text-box-areas x y w h flags)
  (let* ([bw (ui-scrollbar-width)]
         [left (cond [(memq 'lines flags) (+ bw 4)]
                     [(memq 'search flags) (+ (ui-glyph-size) 14)]
                     [else 2])])
    (list (list 'edit (+ x left) (+ y 3) (max 0 (- w left 3))
                (max 0 (- h 6)) (if (memq 'large flags) 'heading 'ui))
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
;; boxed under the mouse; a click gives the menu. A label shown instead
;; of a value is plain, and no value faint.
(define (genera-dropdown x y w h flags label)
  (let ([font (if (or (memq 'label flags) (memq 'placeholder flags))
                  'ui
                  'ui-bold)])
    (when (or (memq 'hover flags) (memq 'open flags)) (genera-hover x y w h))
    (draw-text (+ x 3) (genera-text-y y h font) (text-fit label (- w 6) font)
               (if (memq 'placeholder flags) 'text-faint 'text) font)
    (when (memq 'focused flags) (ui-draw-focus x y w h flags 0))))

(define (genera-dropdown-size labels)
  (values (min (* 10 (font-line-height 'ui))
               (+ 8 (text-widest labels 'ui-bold)))
          (ui-control-height)))

;; A tag as a Zmail keyword, in braces (E&M p.2434); one that can go, a
;; × after it, the mouse's box around the × alone: what a click removes.
(define (genera-chip x y w h flags label)
  (let* ([removable? (memq 'removable flags)] [g (ui-small-glyph-size)]
         [room (- w (text-width "{}" 'ui) (if removable? (+ g 4) 0))])
    (draw-text x (genera-text-y y h 'ui)
               (string-append "{" (text-fit label room 'ui) "}") 'text 'ui)
    (when removable?
      (let ([a (cdr (assq 'remove (ui-chip-areas x y w h)))])
        (ui-draw-glyph (+ (car a) (/ (- (caddr a) g) 2))
                       (+ (cadr a) (/ (- (cadddr a) g) 2)) g g
                       '((ink . text)) 'cross)
        (when (memq 'hover flags) (apply genera-hover a))))))

(define (genera-chip-size label removable?)
  (values (+ (text-width (string-append "{" label "}") 'ui)
             (if removable? (+ (ui-small-glyph-size) 4) 0))
          (round (+ (font-line-height 'ui) 2))))

(define (genera-chip-areas x y w h)
  (let ([g (ui-small-glyph-size)])
    (list (list 'remove (- (+ x w) g 4) y (+ g 4) h))))

;; A record, Genera's output in a border (PUI p.1685, p.1696): a 1-pixel
;; box, 2 pixels while chosen (the CADR's box blinker, sheet.lisp:2365;
;; lispm-notes, answer 3); the mouse's box just outside it.
(define (genera-card x y w h flags)
  (genera-box x y w h (if (memq 'selected flags) 2 1))
  (when (memq 'hover flags) (stroke-box (- x 2) (- y 2) (+ w 4) (+ h 4) 'text)))

;; Genera's scroll bar, as measured (lispm-apps.md 2.4; report:35-41):
;; 1-pixel sides, a box as wide as the bar at each end, the elevator
;; between them in a 33 % stipple.
(define (genera-scrollbar-areas x y w h start size)
  (let* ([e (min w (floor (/ h 3)))] [l (- h e e)]
         [th (min l (max w (* size l)))])
    (list (list 'thumb x
                (+ y e (if (< size 1) (* (- l th) (/ start (- 1 size))) 0))
                w th))))

(define (genera-scrollbar x y w h flags start size)
  (let ([e (min w (floor (/ h 3)))]
        [t (cdr (assq 'thumb (ui-scrollbar-areas x y w h start size)))])
    (fill-box x y w h 'window-bg)
    (fill-box x y 1 h 'text)
    (fill-box (+ x w -1) y 1 h 'text)
    (stroke-box x y w e 'text)
    (stroke-box x (- (+ y h) e) w e 'text)
    (fill-box (+ x 1) (cadr t) (- w 2) (cadddr t) 'genera-elevator)))

;; Neither machine had a slider; typed numbers did its job (CLIM2
;; p.1151). Its authors would have turned the scroll bar sideways: a
;; shaft of 1-pixel sides and a short stippled block at the value.
(define (genera-slider x y w h flags frac paint)
  (let* ([cy (round (+ y (/ h 2)))] [kx (+ x (* frac w))])
    (if paint
        (with-clip (x (- cy 4) w 8) (paint x (- cy 4) w 8))
        (begin (fill-box x (- cy 5) w 1 'text)
               (fill-box x (+ cy 4) w 1 'text)))
    (fill-box (- kx 6) (- cy 5) 12 10 'window-bg)
    (stroke-box (- kx 6) (- cy 5) 12 10 'text)
    (fill-box (- kx 5) (- cy 4) 10 8 'genera-elevator)))

;; A progress note's bar: thin, solid, from the left, no track (UG
;; p.2740; J-zmail).
(define (genera-progress x y w h flags frac)
  (when (> frac 0)
    (fill-box x (+ y (floor (/ (- h 2) 2))) (* w (min 1 frac)) 2 'text)))

;; A column's heading: Peek's plain line (peek.lisp:270-273), or the
;; PUI's italic underlined (genera-heading-underline, PUI p.1886); the
;; sort as the character set's arrow after it.
(define (genera-table-header x y w h flags label dir)
  (let* ([f (theme 'genera-heading-font)]
         [mark (case dir [(up) "↑"] [(down) "↓"] [else #f])]
         [arrow (if mark (string-append " " mark) "")]
         [label (text-fit label (max 0 (- w 14 (text-width arrow f))) f)]
         [s (string-append label arrow)]
         [ty (genera-text-y y h f)]
         [tx (+ x (ui-table-cell-inset))]
         [end (draw-text tx ty s 'text f)])
    (when (and (theme 'genera-heading-underline) (> (string-length s) 0))
      (fill-box tx (+ ty (font-ascent f) 1) (- end tx) 1 'text))
    (when (memq 'hover flags) (genera-hover x y w h))))

;; A row: the mouse's box; chosen, inverse video: its 2-pixel box here,
;; and its inside turned by ui-draw-highlight-over when its cells are
;; drawn (lispm-notes, answer 3).
(define (genera-table-row x y w h flags)
  (cond [(memq 'selected flags) (genera-box x y w h 2)]
        [(memq 'hover flags) (genera-hover x y w h)]))

;; A tree shown by indentation, as FSEdit's (WB Fig. 39); a node's
;; triangle, the MOUSE font's, right when closed and down when open.
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

;; Left out (the search's): grayed over, as a window not in use.
(define (genera-dim x y w h flags)
  (when (and (memq 'dim flags) (not (memq 'selected flags)))
    (fill-box x y w h 'genera-gray)))

;; Panes: a well boxed, a strip ruled off where it meets the rest.
(define (genera-surface x y w h flags)
  (fill-box x y w h 'window-bg)
  (cond [(memq 'well flags) (stroke-box x y w h 'text)]
        [(memq 'toolbar flags) (fill-box x (+ y h -1) w 1 'text)]
        [(memq 'footer flags) (fill-box x y w 1 'text)]
        [(memq 'side flags) (fill-box x y 1 h 'text)]
        [(memq 'nav flags) (fill-box (+ x w -1) y 1 h 'text)]))

;; A popup: Genera's, a 2-pixel border; the CADR's, 1 pixel and its
;; white (lispm.md 2.8): genera-panel-border.
(define (genera-panel x y w h flags)
  ;; Genera's shadow: solid under what only the mouse uses, a 50 %
  ;; stipple under a dialog (report:51); the CADR had none.
  (when (theme 'genera-shadow)
    (fill-box (+ x 7) (+ y 7) w h
              (if (exists (lambda (f) (memq f flags)) '(menu toast tooltip))
                  'text
                  (stipple 'text #f "#." ".#"))))
  (fill-box x y w h 'window-bg)
  (genera-box x y w h (theme 'genera-panel-border)))

;; The entry under the mouse in a menu: a 1-pixel box, inverse while a
;; button is held on it; one under the mouse elsewhere, the box; the
;; chosen one, a 2-pixel box that ui-draw-highlight-over fills in.
(define (genera-highlight x y w h flags)
  (cond [(and (memq 'outline flags) (memq 'pressed flags))
         (fill-box x y w h 'text)]
        [(or (memq 'hover flags) (memq 'outline flags)) (genera-hover x y w h)]
        [else (genera-box x y w h 2)]))

;; Inverse video, inside the 2-pixel box (menu.lisp:855-893).
(define (genera-highlight-over x y w h flags)
  (px-invert (+ x 2) (+ y 2) (- w 4) (- h 4)))

;; A light rule (UG p.2909); in a menu a blank cell (sysmen.lisp:277-282):
;; genera-separator-rule.
(define (genera-separator x y w h flags)
  (when (theme 'genera-separator-rule)
    (fill-box x (floor (+ y (/ h 2))) w 1 'text)))

;; The fallback for what the who line says: a pop-up message's box
;; (sysmen.lisp:612-628).
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

;; A dialog: Genera's accept-values window (UG Fig. 135), the CADR's
;; choose-variable-values (choice.lisp:427-526, :916-922): the title over
;; a rule, the message, and under a rule its buttons as words in equal
;; shares of the width.
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

;; Under a dialog: the gray over a window not in use (UG p.2804).
(define (genera-scrim x y w h flags) (fill-box x y w h 'genera-gray))

;; Neither machine had a calendar; dates were typed (UG Fig. 144). Its
;; authors would have set a month as a text table (lispm-apps.md 4.16;
;; lispm-notes, answer 9): headed by the weekdays as a column's heading,
;; a day a column three characters wide, its number at the right.
(define (genera-calendar-cell) (round (* 3 (font-char-width 'ui))))

;; Under the grid, Previous and Next, then Today and Clear, each in half
;; of the width, which their words (and margin choices' boxes) set.
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

;; A day: today bold (the current value's emphasis); chosen, inverse; the
;; keyboard's, underlined; the mouse's, boxed; another month's, faint.
(define (genera-day x y w h flags label)
  (let* ([on? (lambda (f) (memq f flags))]
         [f (if (on? 'today) 'ui-bold 'ui)] [lh (font-line-height f)]
         [ty (genera-text-y y h f)] [sel? (on? 'selected)])
    (cond [sel? (fill-box x (- ty 1) w (+ lh 2) 'text)]
          [(on? 'hover) (genera-hover x (- ty 1) w (+ lh 2))])
    (draw-text (- (+ x w) 4 (text-width label f)) ty label
               (cond [sel? 'window-bg] [(on? 'outside) 'text-faint]
                     [else 'text])
               f)
    (when (on? 'cursor)
      (fill-box (+ x 2) (+ ty lh) (- w 4) 1 (if sel? 'window-bg 'text)))))

;; A person: the name, where it is written beside the avatar (so nothing
;; more), or else the initials in a lozenge (shwarm.lisp:675-700).
(define (genera-avatar-size flags name)
  (if (memq 'named flags)
      (values 0 0)
      (values (px-lozenge-width (ui-initials name)) 9)))

(define (genera-avatar x y w h flags name)
  (unless (memq 'named flags) (px-lozenge x y (ui-initials name) 'text)))

;;; Tasks' marks (apps/tasks.ss), each in ink: the shapes of Genera's
;;; MOUSE font (WB Fig. 14) and the CADR's choice box.

;; Priority, four bars, those above it hollow as a choice box off; a
;; bug a filled circle, a feature a filled lozenge, a chore a hollow box;
;; blocked a fat circle with a minus in it; a status none, its word is
;; written beside (lispm-apps.md part 5).
(define (genera-tasks-mark x y s what value)
  (case what
    [(status) 0]
    [(priority)
     (let ([level (case value [(urgent) 4] [(high) 3] [(normal) 2] [else 1])]
           [bw (max 3 (floor (/ (- s 3) 4)))])
       (do ([i 0 (+ i 1)]) ((= i 4) s)
         (let ([bh (round (* s (/ (+ i 2) 5)))] [bx (+ x (* i (+ bw 1)))])
           (if (< i level)
               (fill-box bx (- (+ y s) bh) bw bh 'text)
               (stroke-box bx (- (+ y s) bh) bw bh 'text)))))]
    [(kind)
     (if (eq? value 'chore)
         (begin (stroke-box (+ x 2) (+ y 2) (- s 4) (- s 4) 'text) s)
         (tasks-draw-mark* x y s what value))]
    [(blocked)
     (stroke-circle (+ x (/ s 2)) (+ y (/ s 2)) (- (* s 0.45) 1) 'text 2)
     (fill-box (+ x (round (* s 0.3))) (+ y (floor (- (/ s 2) 1)))
               (- s (* 2 (round (* s 0.3)))) 2 'text)
     s]
    [else (tasks-draw-mark* x y s what value)]))

;; A due date: bold when it has passed (lispm-notes, answer 8), else
;; plain; "Today" says itself.
(define (genera-tasks-due x y w t today fnt)
  (let* ([f (get-font fnt)]
         [f (if (tasks-overdue? t today)
                (font (font-family f) (font-size f) 'bold)
                f)])
    (draw-text x y (text-fit (tasks-due-label (task-due t) today) w f) 'text
               f)))

;; Where a dragged card would land: a box over the gray.
(define (genera-tasks-slot x y w h)
  (fill-box x y w h 'genera-gray)
  (stroke-box x y w h 'text))

;; On a plain white screen, ink on paper whatever the palette.
(define-style genera "Genera"
  'palette 'genera
  'wallpaper 'flat
  'corner-radius 0   ; square, and so is everything drawn in it
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
  'taskbar-height (theme-rule (* 2 (genera-line)))
  'draw-taskbar 'genera-draw-who-line
  'taskbar-areas 'genera-who-line-areas
  'taskbar-tick 'genera-who-line-tick
  'ui-busy-size 'genera-busy-size
  'ui-draw-busy 'genera-busy
  'mouse-doc-text 'genera-mouse-doc-text
  ;; the fonts: what an app shows in the code font (FIX, cptfont), its
  ;; command words in the sans (JESS), titles in sans bold (SWISS), menus
  ;; a size up, a pane's heading bold italic (lispm-apps.md part 6)
  ;; the code font the sans's size, so that an app's text and the command
  ;; words beside it stand as tall (one family: one x-height)
  'mono-font-size 13
  'ui (theme-rule (theme 'mono))
  'ui-small (theme-rule (theme 'mono-small))
  'ui-bold (theme-rule (theme 'mono-bold))
  'genera-command-font (theme-font-rule 'ui 0)
  'genera-standout-font 'title
  'genera-choice-font 'mono
  'genera-choice-bold 'mono-bold
  'genera-heading-font 'mono-italic
  'genera-heading-underline #t
  'label-section-font 'ui-bold-italic
  'label-section-upcase #f
  'label-group-font 'ui-bold-italic
  'faint-text-font 'ui-italic-of
  'text-caret 'block
  'text-selection 'underline
  ;; the sizes: a line of the font and a little
  'control-height (theme-rule (round (+ (font-line-height 'ui) 6)))
  'table-header-height (theme-rule (round (+ (font-line-height 'ui) 6)))
  'table-row-height (theme-rule (round (+ (font-line-height 'ui) 6)))
  ;; the menus: centered words, a blank cell between groups
  'menu-font (theme-font-rule 'ui 2)
  'menu-item-height
  (theme-rule (round (+ (font-line-height (theme 'menu-font)) 4)))
  'menu-pad 3
  'menu-text-x 14
  'menu-min-width 120
  'menu-align 'center
  'menu-ink 'text
  'menu-ink-selected 'text
  'menu-ink-pressed 'window-bg
  'genera-separator-rule #t
  'places '((menu genera-separator-rule #f))
  'calendar-step-words #t
  ;; the widgets
  'surface-well-ring 1
  'genera-hover-nudge 0
  'genera-panel-border 2
  'genera-shadow #t
  'genera-choice-heavy #f
  'genera-margin-choice #f
  'ui-draw-button 'genera-button
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
  'tasks-draw-mark 'genera-tasks-mark
  'tasks-draw-due 'genera-tasks-due
  'tasks-draw-slot 'genera-tasks-slot
  'repl-paren-mark (stipple 'text #f "#..." "...." "..#." "....")
  'settings-swatch-ring (stipple 'text 'window-bg "#." ".#")
  ;; a chart's series apart by patterns of ink; a share of its bars in
  ;; solid ink (the accent's), a bar marked grayed
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
  ;; the feel
  'title-double-click 'none
  'bell 'screen
  'menu-hover 'outline
  'mouse-doc #t
  'scrollbar-side 'left
  ;; the content clear of it, as beside a pane's margin
  'scrollbar-margin 4
  'options '(palette
             accent
             wallpaper
             ui-font
             ui-font-size
             mono-font
             mono-font-size
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
  'bg-3 (genera-same 'bg-1))
