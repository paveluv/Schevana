;;; styles/cadr.ss — the MIT CADR's TV windows (System 99), read from
;;; MIT's sources (BSD; .work/style/research/lispm.md part 2): the window
;;; system Genera grew from. Genera's frame, who line and feel, with what
;;; the CADR did otherwise: a 1-pixel border and a 1-pixel white margin
;;; (baswin.lisp:864-871, :1012-1014), and the label upright in the code
;;; font, CPTFONT on the CADR, at the top of its strip, which lies under
;;; the content, the margin and the border under it (baswin.lisp:1104-1119,
;;; :1180, :1215-1226). No gray over windows not selected: the CADR grayed
;;; only covered windows (lispm.md 2.5-2.6), and Schevana covers none.
;;;
;;; Its widgets are Genera's (styles/genera.ss) as the CADR drew them
;;; (.work/style/research/lispm-apps.md part 4): command words in the code
;;; font, as Peek's and the Inspector's; menus in MEDFNT, a size up;
;;; headings and the standout (Do It) in HL12I, a sans italic; choices in
;;; HL10 and HL10B; the mouse's box a pixel out at the top and left; a
;;; choice box framed a quarter of its side; popups of a 1-pixel border and
;;; nothing under them; a dialog's buttons margin choices; the gray
;;; HES-GRAY's 12.5 % (scrman.lisp:437-443).

;; The CADR's scroll bar: the part of the text in view as a solid segment
;; in the left margin, shown while the mouse is there (mouse.lisp:936-1010),
;; 3 pixels as the Inspector's, in a strip wider to hit.
(define (cadr-scrollbar x y w h flags start size)
  (let ([t (cdr (assq 'thumb (ui-scrollbar-areas x y w h start size)))])
    (fill-box x (cadr t) 3 (cadddr t) 'text)))

;; No slider either: a 1-pixel rule, and a solid block the cursor's size
;; at the value, the scroll bar's segment turned sideways.
(define (cadr-slider x y w h flags frac paint)
  (let ([cy (round (+ y (/ h 2)))] [kx (+ x (* frac w))])
    (if paint
        (with-clip (x (- cy 4) w 8) (paint x (- cy 4) w 8))
        (fill-box x cy w 1 'text))
    (fill-box (- kx 4) (- cy 6) 8 12 'text)))

;; Progress as the who line counted a file's, "37%" (wholin.lisp:405-450),
;; where the line has room; else none, the count is beside it.
(define (cadr-progress x y w h flags frac)
  (when (>= h (font-line-height 'ui-small))
    (text-draw-centered x y w h
                        (format "~a%" (exact (round (* 100 (min 1 frac)))))
                        'text 'ui-small)))

;; Nothing under a dialog: the CADR grayed only covered windows.
(define (cadr-scrim x y w h flags) (void))

(define-style cadr "MIT CADR"
  'parent 'genera
  'genera-border 1
  'genera-margin 1
  'genera-label-font 'mono
  'genera-label-align 'top
  'genera-label-under 'content
  'frame-over 'frame-over*
  ;; the fonts (tvdefs.lisp:211-216, choice.lisp:911-914): all in the
  ;; code font, so at its own size, not Genera's
  'mono-font-size 14
  'genera-command-font 'mono
  'genera-standout-font 'ui-italic
  'heading (theme-font-rule 'ui 1 'italic)
  'genera-choice-font (theme-font-rule 'ui -2)
  'genera-choice-bold 'ui-small-bold
  'genera-heading-font 'ui
  'genera-heading-underline #f
  'menu-font (theme-font-rule 'mono 1)
  ;; the widgets
  'genera-hover-nudge 1
  'genera-panel-border 1
  'genera-shadow #f
  'genera-choice-heavy #t
  'places '((menu genera-separator-rule #f)
            (dialog genera-margin-choice #t))
  'genera-gray (stipple 'text #f "#..." "...." "..#." "....")
  'ui-draw-scrollbar 'cadr-scrollbar
  'ui-scrollbar-areas 'ui-scrollbar-areas*
  'scrollbar-show 'hover
  'ui-draw-slider 'cadr-slider
  'ui-draw-progress 'cadr-progress
  'ui-draw-scrim 'cadr-scrim)
