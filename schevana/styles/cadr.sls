;;; (schevana styles cadr) — the MIT CADR's TV windows (System 99), read
;;; from MIT's sources (BSD; .work/style/research/lispm.md part 2): the
;;; window system Genera grew from. The style has Genera's frame, who line
;;; and feel, with what the CADR did differently: a 1-pixel border and a
;;; 1-pixel white margin (baswin.lisp:864-871, :1012-1014), and the label
;;; upright in the code font (CPTFONT on the CADR) at the top of its strip,
;;; which lies below the content, with the margin and the border below it
;;; (baswin.lisp:1104-1119, :1180, :1215-1226). Plain windows have no gray
;;; over them, covered or not: the CADR's gray-deexposed mixins were
;;; optional (scrman.lisp:447-515).
;;;
;;; Its widgets are Genera's ((schevana styles genera)) as the CADR drew
;;; them (.work/style/research/lispm-apps.md part 4): command words in the
;;; code font, as in Peek and the Inspector; menus in MEDFNT, a size up;
;;; headings and the standout (Do It) in HL12I, a sans italic; choices in
;;; HL10 and HL10B; the mouse's box a pixel further out at the top and
;;; left; a choice box framed by a quarter of its side; popups with a
;;; 1-pixel border and nothing under them; a dialog's buttons as margin
;;; choices; and the gray of HES-GRAY, 12.5 % (scrman.lisp:437-443).

(library (schevana styles cadr)
  (export
    cadr-scrollbar cadr-scrollbar-areas cadr-slider cadr-progress cadr-scrim)
  (import (chezscheme)
          (only (schevana base) at-load clamp library-layer)
          (only (schevana core) define-bitmap-font define-style fill-box font
                font-line-height stipple theme theme-rule with-clip)
          (schevana styles cadr fonts)
          (only (schevana kits text) text-draw-centered)
          (only (schevana kits ui) ui-scrollbar-areas))

  (library-layer looks)

  ;; The CADR's scroll bar: the part of the text in view, as a solid
  ;; segment in the left margin, shown while the mouse is there
  ;; (mouse.lisp:936-1010). It is 3 pixels wide, as the Inspector's is, in
  ;; a wider strip that is easier to hit. SCROLL-BAR-DRAW
  ;; (mouse.lisp:961-978) keeps five pixels and scales both ends over the
  ;; rest, so that even a small part in view shows, with no least length.
  (define (cadr-scrollbar-areas x y w h start size)
    (let* ([room (max 0 (- h 5))]
           [top (floor (* room (clamp start 0 1)))]
           [bottom (min h (ceiling (+ (min 5 h)
                                      (* room (clamp (+ start size) 0 1)))))])
      (list (list 'thumb x (+ y top) w (max 0 (- bottom top))))))

  (define (cadr-scrollbar x y w h flags start size)
    (let ([t (cdr (assq 'thumb (ui-scrollbar-areas x y w h start size)))])
      (fill-box x (cadr t) (min 3 w) (cadddr t) 'text)))

  ;; The CADR had no slider either: this one is a 1-pixel rule with a solid
  ;; block the cursor's size at the value, the scroll bar's segment turned
  ;; sideways.
  (define (cadr-slider x y w h flags frac paint)
    (let ([cy (round (+ y (/ h 2)))] [kx (+ x (* frac w))])
      (if paint
          (with-clip (x (- cy 4) w 8) (paint x (- cy 4) w 8))
          (fill-box x cy w 1 'text))
      (fill-box (- kx 4) (- cy 6) 8 12 'text)))

  ;; Progress as the who line counted a file's, "37%"
  ;; (wholin.lisp:405-450), where the line has room; otherwise nothing,
  ;; since the count is shown beside it.
  (define (cadr-progress x y w h flags frac)
    (when (>= h (font-line-height 'ui-small))
      (text-draw-centered x y w h
                          (format "~a%" (exact (round (* 100 (min 1 frac)))))
                          'text 'ui-small)))

  ;; Nothing is drawn under a dialog: the CADR grayed only covered windows.
  (define (cadr-scrim x y w h flags) (void))

  ;; The CADR's fonts, registered as the style loads.
  (at-load
   (for-each (lambda (f) (define-bitmap-font (car f) (cdr f)))
             cadr-fonts))

  (at-load
   (define-style cadr "MIT CADR"
     'parent 'genera
     'genera-border 1
     'genera-margin 1
     'genera-label-font 'mono
     'genera-label-align 'top
     'genera-label-under 'content
     ;; the who line: one row of the mouse's documentation and one of
     ;; status, both in CPTFONT with no spacing (WHO-LINE-SETUP's :VSP 0,
     ;; wholin.lisp:52-106)
     'genera-who-line-spacing 0
     'genera-mouse-doc-lines 1
     'genera-mouse-doc-font 'mono
     'frame-over 'frame-over*
     ;; the fonts, the CADR's own, each at its cell's height ((schevana
     ;; styles cadr fonts); tvdefs.lisp:211-216, choice.lisp:911-914): the
     ;; CADR set nearly everything in the code font, CPTFONT; headings and
     ;; the standout in HL12I; choices in HL10 and HL10B; menus in MEDFNT;
     ;; the small italic of a hint TR10I
     'mono-font "CADR CPTFONT"
     'mono-font-size 12
     'ui-font "CADR HL12"
     'ui-font-size 14
     'mono (font "CADR CPTFONT" 12 'crisp)
     'mono-small (font "CADR CPTFONT" 12 'crisp)
     'mono-bold (font "CADR CPTFONT Bold" 12 'crisp)
     'mono-italic (font "CADR TR10 Italic" 12 'crisp)
     'ui-italic (font "CADR HL12 Italic" 14 'crisp)
     'ui-bold-italic (font "CADR HL12 Bold Italic" 14 'crisp)
     'title (font "CADR HL12 Bold" 14 'crisp)
     'heading (font "CADR HL12 Italic" 14 'crisp)
     'big (font "CADR HL12 Bold" 28 'crisp)
     'huge (font "CADR CPTFONT" 360 'crisp)
     'faint-text-font #f
     'genera-command-font 'mono
     'genera-standout-font 'ui-italic
     'genera-choice-font (font "CADR HL10" 12 'crisp)
     'genera-choice-bold (font "CADR HL10 Bold" 12 'crisp)
     'genera-heading-font 'ui
     'genera-heading-underline #f
     'menu-font (font "CADR MEDFNT" 13 'crisp)
     'label-hint-font (font "CADR TR10 Italic" 12 'crisp)
     ;; a menu's rows are a character cell and VSP 2, a blank one between
     ;; groups; its text at the top of its cell, its centering truncated,
     ;; and the chosen one boxed around its cell a pixel wider
     'menu-item-height
     (theme-rule (round (+ (font-line-height (theme 'menu-font)) 2)))
     'menu-separator-height (theme-rule (theme 'menu-item-height))
     'menu-pad 2
     'menu-text-x 2
     'menu-text-top #t
     'menu-snap-text 'floor
     'menu-highlight 'text
     'menu-highlight-extra 1
     'menu-highlight-outset 0
     'menu-hint-font (font "CADR HL12 Italic" 14 'crisp)
     ;; the widgets
     'genera-hover-nudge 1
     'genera-hover-ink-gap #f
     ;; a blinker's phase: HALF-PERIOD, 15 sixtieths (tvdefs.lisp:399)
     'text-blink-ms 250
     'genera-choice-padding 0
     ;; DRAW-CHOICE-BOX takes the font's blinker height, not its ascent:
     ;; CPTFONT's 12-pixel square, framed by 3
     'genera-choice-side (theme-rule (round (font-line-height 'mono)))
     'genera-panel-border 1
     'genera-shadow #f
     'genera-choice-heavy #t
     'places '((menu genera-separator-rule #f)
               (dialog genera-margin-choice #t))
     'genera-gray (stipple 'text #f "#..." "...." "..#." "....")
     'ui-draw-scrollbar 'cadr-scrollbar
     'ui-scrollbar-areas 'cadr-scrollbar-areas
     ;; the bar in the margin, shown while the mouse is there, worked by
     ;; three buttons, a double click going to the other end
     ;; (mouse.lisp:936-1010)
     'scrollbar-show 'bar
     'scrollbar-input 'lispm
     'scrollbar-double-click #t
     'ui-draw-slider 'cadr-slider
     'ui-draw-progress 'cadr-progress
     ;; a bar a line of the small font high, so that its percentage shows
     'progress-height (theme-rule (font-line-height 'ui-small))
     'ui-draw-scrim 'cadr-scrim)))
