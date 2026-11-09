;;; menu.ss — the desktop's one menu at a time: the launcher, a window's
;;; menu, a dropdown's (the widget kit opens it by name, open-menu!). A
;;; menu is a list of entries: (label . thunk) or 'separator. While one
;;; is open it takes every press, key and text (its surface's box is the
;;; whole screen); a press outside it closes it. How it feels is the
;;; style's: menu-choose (click: a press chooses; release: the entry the
;;; button is released over, so a press can open a menu and the release
;;; choose, and one released elsewhere stays open), menu-blink (how many
;;; times a chosen entry blinks before its action runs) and menu-hover
;;; (fill, or outline: a box, inverted while a button is held on it).

(define-record-type menu
  (nongenerative schevana-menu)
  (fields x y items (mutable sel) (mutable filter) filter? tag))

(defvar *menu* #f)

;; The menu's numbers are settings, a style's to give: an entry's height
;; (a rule from the font), a separator's, the room above the first entry
;; and below the last, the text's inset, the least width, the font and
;; the entries' ink, chosen and not, and where their text goes.
(theme-default! 'menu-item-height
                (theme-rule (max 26 (round (+ (font-line-height 'ui) 11)))))
(theme-default! 'menu-separator-height 9)
(theme-default! 'menu-pad 5)
(theme-default! 'menu-text-x 18)
(theme-default! 'menu-min-width 230)
(theme-default! 'menu-font 'ui)
(theme-default! 'menu-ink 'text-dim)
(theme-default! 'menu-ink-selected 'text)
(theme-default! 'menu-ink-pressed 'bg-2)   ; on an outline's inversion
(theme-default! 'menu-choose 'click)
(theme-default! 'menu-blink 0)
(theme-default! 'menu-hover 'fill)
;; the entries' text: left, menu-text-x in, or center (the Lisp machines')
(theme-default! 'menu-align 'left)

(defvar *menu-blink* #f)   ; (start-ms entry thunk) while a chosen one blinks
;; (x y entry): where a press held down opened the menu, and the entry
;; there, until the pointer has left both: a release before only ends the
;; press that opened it (a menu may open under the pointer)
(defvar *menu-held-at* #f)
(defvar *menu-under* #f)   ; the entry under the pointer: a press shows it

(define (menu-item-height) (theme 'menu-item-height))

(define (menu-open?) (and *menu* #t))

(define (open-menu! x y items . opts)
  (set! *menu* (make-menu x y items 0 "" (plist-ref opts 'filter #f)
                          (plist-ref opts 'tag #f)))
  (set! *menu-blink* #f)   ; an old menu's blink ends with it
  (set! *menu-held-at*
    (and *mouse-button*
         (list *mouse-x* *mouse-y* (menu-entry-at *mouse-x* *mouse-y*))))
  (set! *menu-under* #f)
  (menu-select-next! 0)
  (let ([i (plist-ref opts 'selected #f)])   ; a dropdown's current entry
    (when i (menu-sel-set! *menu* i)))
  (request-frame!))

(define (close-menu!)
  (set! *menu* #f)
  (request-frame!))

(define (menu-entries m)
  (let ([f (menu-filter m)] [items (menu-items m)])
    (cond [(procedure? items) (items f)]   ; (lambda (filter) entries)
          [(string=? f "") items]
          [else (filter (lambda (e)
                          (and (pair? e) (string-contains-ci? (car e) f)))
                        items)])))

;; Where menu m and its pieces are, which its drawing, its clicks and the
;; pointer read: (menu x y w h), then (filter x y w h) when it filters,
;; then each entry's (i x y w h) or separator's (separator x y w h), top
;; to bottom.
(define-part (menu-areas m)
  (let* ([es (menu-entries m)] [ih (theme 'menu-item-height)]
         [sh (theme 'menu-separator-height)] [pad (theme 'menu-pad)]
         [head (if (menu-filter? m) (+ ih 8) 0)]
         [w (fold-left (lambda (acc e)
                         (if (pair? e)
                             (max acc (+ 8 (* 2 (theme 'menu-text-x))
                                         (text-width (car e)
                                                     (theme 'menu-font))))
                             acc))
                       (theme 'menu-min-width) es)]
         [h (fold-left (lambda (acc e) (+ acc (if (pair? e) ih sh)))
                       (+ pad pad head) es)]
         [x (clamp (menu-x m) 4 (- (screen-w) w 4))]
         [y (let-values ([(dx dy dw dh) (desktop-rect)])
              (clamp (menu-y m) (+ 2 dy) (- (screen-h) h 4)))])
    (cons (list 'menu x y w h)
          (append (if (menu-filter? m)
                      (list (list 'filter (+ x 6) (+ y 6) (- w 12) ih))
                      '())
                  (let loop ([es es] [i 0] [ey (+ y pad head)])
                    (if (null? es)
                        '()
                        (let ([eh (if (pair? (car es)) ih sh)])
                          (cons (list (if (pair? (car es)) i 'separator)
                                      x ey w eh)
                                (loop (cdr es) (+ i 1) (+ ey eh))))))))))

;; The areas of menu m where it draws them, in its place: what the
;; pointer reads too.
(define (placed-menu-areas m) (with-place 'menu (lambda () (menu-areas m))))

;; The menu's box: (values x y w h).
(define (menu-geometry m) (apply values (cdar (placed-menu-areas m))))

(define (point-in-menu? px py)
  (apply point-in? px py (cdar (placed-menu-areas *menu*))))

;; Index of the entry under (px, py), or #f.
(define (menu-entry-at px py)
  (let ([a (find (lambda (a)
                   (and (fixnum? (car a)) (apply point-in? px py (cdr a))))
                 (placed-menu-areas *menu*))])
    (and a (car a))))

(define (menu-select-next! dir)
  (let* ([es (list->vector (menu-entries *menu*))] [n (vector-length es)])
    (unless (zero? n)
      (let loop ([i (if (zero? dir) 0 (+ (menu-sel *menu*) dir))] [tries 0])
        (when (< tries n)
          (let ([i (mod i n)])
            (if (pair? (vector-ref es i))
                (menu-sel-set! *menu* i)
                (loop (+ i (if (zero? dir) 1 dir)) (+ tries 1)))))))
    (request-frame!)))

(define (menu-activate! i)
  (let ([es (menu-entries *menu*)])
    (when (and i (< i (length es)) (pair? (list-ref es i)) (not *menu-blink*))
      (let ([thunk (cdr (list-ref es i))])
        (if (> (theme 'menu-blink) 0)
            (begin (set! *menu-blink* (list (now-ms) i thunk))
                   (menu-blink!))
            (menu-run! thunk))))))

(define (menu-run! thunk)
  (close-menu!)
  (safe-call 'menu thunk (lambda (c) (report-error! 'menu c))))

;; A blink's phases are 60 ms each: off, on, off, on...; when they are
;; done the menu closes and the chosen entry's action runs.
(define (menu-phase b) (quotient (- (now-ms) (car b)) 60))

;; A phase of the blink drawn, and a timer for the next one's start.
(define (menu-blink!)
  (let ([b *menu-blink*])
    (when b
      (cond [(not *menu*) (set! *menu-blink* #f)]
            [(< (menu-phase b) (* 2 (theme 'menu-blink)))
             (menu-request!)
             (after (- (+ (car b) (* 60 (+ (menu-phase b) 1))) (now-ms))
                    (lambda () (menu-blink!)))]
            [else (set! *menu-blink* #f) (menu-run! (caddr b))]))))

(define (menu-mouse-move x y)
  (let ([i (menu-entry-at x y)] [at *menu-held-at*])
    (when (and i (not (= i (menu-sel *menu*))))
      (menu-sel-set! *menu* i)
      (request-frame!))
    (when (and at (> (+ (abs (- x (car at))) (abs (- y (cadr at)))) 4)
               (not (eqv? i (caddr at))))
      (set! *menu-held-at* #f))
    (unless (eqv? i *menu-under*)   ; held, the press moves with it
      (set! *menu-under* i)
      (when *mouse-button* (menu-request!)))))

;; Asks for the menu's own box.
(define (menu-request!)
  (call-with-values (lambda () (menu-geometry *menu*)) request-frame!))

(define (menu-mouse-down x y)
  (menu-activate! (menu-entry-at x y)))

(define (menu-key key mods)
  (case key
    [(escape) (close-menu!)]
    [(up) (menu-select-next! -1)]
    [(down tab) (menu-select-next! 1)]
    [(return) (menu-activate! (menu-sel *menu*))]
    [(backspace)
     (let ([f (menu-filter *menu*)])
       (when (> (string-length f) 0)
         (menu-filter-set! *menu* (substring f 0 (- (string-length f) 1)))
         (menu-select-next! 0)))]))

(define (menu-text str)
  (when (menu-filter? *menu*)
    (menu-filter-set! *menu* (string-append (menu-filter *menu*) str))
    (menu-select-next! 0)))

(define-part (draw-menu)
  (when *menu*
    (with-place 'menu
      (lambda ()
        (let* ([m *menu*] [areas (menu-areas m)]
               [es (list->vector (menu-entries m))] [font (theme 'menu-font)]
               [lh (font-line-height font)] [f (assq 'filter areas)])
          (apply ui-draw-panel (append (cdar areas) '((menu))))
          (when f
            (apply (lambda (fx fy fw fh) (draw-menu-filter m fx fy fw fh))
                   (cdr f)))
          (for-each
           (lambda (a)
             (apply
              (lambda (what x y w h)
                (cond
                  [(eq? what 'separator)
                   (ui-draw-separator (+ x 12) y (- w 24) h '())]
                  [(fixnum? what)
                   (let* ([b *menu-blink*]
                          [sel? (if b   ; blinking: on in odd phases
                                    (and (= what (cadr b))
                                         (odd? (menu-phase b)))
                                    (= what (menu-sel m)))]
                          [flags (if sel? (menu-entry-flags what) '())])
                     (when sel? (ui-draw-highlight (+ x 5) y (- w 10) h flags))
                     (draw-text (if (eq? (theme 'menu-align) 'center)
                                    (+ x (/ (- w (text-width
                                                  (car (vector-ref es what))
                                                  font))
                                            2))
                                    (+ x (theme 'menu-text-x)))
                                (+ y (/ (- h lh) 2))
                                (car (vector-ref es what))
                                (theme (cond [(not sel?) 'menu-ink]
                                             [(and (memq 'outline flags)
                                                   (memq 'pressed flags))
                                              'menu-ink-pressed]
                                             [else 'menu-ink-selected]))
                                font))]))
              a))
           areas))))))

;; An entry's highlight's flags: outline as the style's menu-hover says,
;; pressed while a button is held on it.
(define (menu-entry-flags i)
  (append (if (eq? (theme 'menu-hover) 'outline) '(outline) '())
          (if (and *mouse-button*
                   (eqv? i (menu-entry-at *mouse-x* *mouse-y*)))
              '(pressed)
              '())))

;; The filter's field: what is typed, or a hint; a longer filter scrolls,
;; so its end and the caret stay in view.
(define (draw-menu-filter m x y w h)
  (let* ([font (theme 'menu-font)] [lh (font-line-height font)]
         [f (menu-filter m)] [ty (+ y (/ (- h lh) 2))])
    (fill-box x y w h 'bg-0 6)
    (if (string=? f "")
        (draw-text (+ x 10) ty "Type to filter…" 'text-faint font)
        (with-clip (x y w h)
          (let ([ex (draw-text (min (+ x 10)
                                    (- (+ x w) 13 (text-width f font)))
                               ty f 'text font)])
            (if (eq? (theme 'text-caret) 'block)   ; the kit's caret
                (px-invert ex ty (font-char-width font) lh)
                (fill-box (+ ex 1) (+ y (round (/ (- h lh 1) 2))) 1.5
                          (round (+ lh 1)) 'accent)))))))

;;; The surface: over the bars, under the toasts.

(define (menu-box)
  (if *menu* (values 0 0 (screen-w) (screen-h)) (values 0 0 0 0)))

(define (menu-at x y) (and *menu* 'menu))

(define (menu-mouse kind what x y button clicks)
  (let ([release? (eq? (theme 'menu-choose) 'release)])
    (case kind
      [(down) (cond [(menu-double-press x y clicks)
                     => (lambda (act) (close-menu!) (act))]
                    [(point-in-menu? x y)
                     (if release? (request-frame!) (menu-mouse-down x y))]
                    [else (close-menu!)])]
      [(up) (cond [(not release?) (void)]
                  [*menu-held-at* (set! *menu-held-at* #f)]   ; just opened
                  [else (menu-mouse-down x y)])]
      ;; held in a window that opened it, the pointer chooses on release
      [(move) (when (or release? (not button)) (menu-mouse-move x y))])))

;; A second press on the frame button that opened a window's menu is a
;; double click there (CDE's menu button closes the window): a thunk for
;; the action its style names in button-double-click, or #f.
(define (menu-double-press x y clicks)
  (let ([tag (menu-tag *menu*)])
    (and (>= clicks 2) (pair? tag) (eq? (car tag) 'window)
         (let* ([win (cdr tag)]
                [a (and (eq? (window-at x y) win)
                        (assq (window-region win x y)
                              (window-setting win 'button-double-click)))])
           (and a (lambda () (window-action! win (cdr a))))))))

(define (menu-takes kind value mods)
  (and *menu*
       (begin (if (eq? kind 'key) (menu-key value mods) (menu-text value))
              #t)))

(define-surface menu 30
  'draw 'draw-menu 'box 'menu-box 'at 'menu-at 'mouse 'menu-mouse
  'key 'menu-takes 'doc (lambda (what) '((L . "Choose"))))

;;; The launcher: every registered app, plus a few system actions.

;; at: where the apps' windows open (see new-window-position), or #f.
(define (launcher-items at)
  (append
   (map (lambda (a)
          (cons (app-title a)
                (lambda ()
                  (parameterize ([new-window-position at])
                    (launch-app-asking! a)))))
        (sort (lambda (a b) (string<? (app-title a) (app-title b))) *apps*))
   (list 'separator
         (cons "Tile windows" (lambda () (tile-windows!)))
         (cons "Cascade windows" (lambda () (cascade-windows!)))
         (cons (if (fullscreen?) "Leave full screen" "Full screen")
               (lambda () (toggle-fullscreen!)))
         (cons "Reload sources" (lambda () (spawn "reload" reload!)))
         (cons "Quit Schevana" (lambda () (quit!))))))

(define (launcher-open?) (and *menu* (eq? (menu-tag *menu*) 'launcher)))

(define (open-launcher! x y . at)
  (open-menu! x y (launcher-items (and (pair? at) (car at)))
              'filter #t 'tag 'launcher))

(define (toggle-launcher!)
  (if (launcher-open?)
      (close-menu!)
      (open-launcher! 6 (+ 2 (topbar-height)))))

;; A window's menu: a right click on its title or a press on a frame's
;; menu button (the window manager calls the part), or a right click on
;; its taskbar button. Shade is there where its style shades.
(define-part (open-window-menu win x y)
  (open-menu! x y
              `(("Bind to $w for the REPL"
                 . ,(lambda ()
                      (define-top-level-value '$w win)
                      (notify (format "$w = ~s" win))))
                (,(if (eq? (window-state win) 'maximized) "Restore" "Maximize")
                 . ,(lambda () (toggle-maximize! win)))
                ("Minimize" . ,(lambda () (minimize-window! win)))
                ,@(if (or (shaded? win) (shades? win))
                      `((,(if (shaded? win) "Unshade" "Shade")
                         . ,(lambda () (toggle-shade! win))))
                      '())
                separator
                ("Close" . ,(lambda () (close-window! win))))
              'tag (cons 'window win)))

;; Does win's style shade it: a shade button, or a double click or the
;; wheel on its title?
(define (shades? win)
  (or (and (assq 'shade (frame-regions win)) #t)
      (eq? (window-setting win 'title-double-click) 'shade)
      (eq? (window-setting win 'title-wheel) 'shade)))
