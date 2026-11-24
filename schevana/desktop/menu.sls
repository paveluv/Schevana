;;; (schevana desktop menu) — the desktop's menu, one open at a time: the
;;; launcher's ((schevana desktop launcher)), a window's menu, or a
;;; dropdown's (the widget kit opens it through its hook ui-menu-open!,
;;; which this file sets to open-menu!). A menu is a list of entries, each
;;; (label . thunk), (label thunk icon) or 'separator, as in the menu kit's
;;; data ((schevana kits menu)); a style lays it out and draws it. While a
;;; menu is open, it takes every press, key and text (its surface's box is
;;; the whole screen), and a press outside it closes it. How it feels is up
;;; to the style: menu-choose (click: a press chooses; release: the entry
;;; the button is released over is chosen, so a press can open a menu and
;;; the release choose from it, and a menu released elsewhere stays open),
;;; menu-blink (how many times a chosen entry blinks before its action
;;; runs) and menu-hover (fill, or outline: a box, inverted while a button
;;; is held on it).

(library (schevana desktop menu)
  (export
    menu-item-height open-menu! close-menu! menu-areas menu-areas* menu-draw
    draw-menu draw-menu* menu-box menu-at menu-mouse menu-takes
    open-window-menu open-window-menu*)
  (import (chezscheme)
          (only (schevana base) at-load clamp define-hook define-state
                library-layer plist-ref set-hook!)
          (only (schevana core) *mouse-button* *mouse-x* *mouse-y* after
                close-window! define-part define-surface desktop-rect
                draw-text fill-box focus-window! font font-char-width
                font-line-height frame-regions minimize-window! notify now-ms
                point-in?
                report-error! request-frame! safe-call screen-h screen-w
                shaded? text-width theme theme-default! theme-rule
                toggle-maximize! toggle-shade! window-action! window-at
                window-ref window-region window-setting window-state with-clip
                with-place world-value)
          (only (schevana kits menu) make-menu menu-x menu-y menu-sel
                menu-sel-set! menu-filter menu-filter-set! menu-filter?
                menu-tag menu-label-text menu-label-key menu-label-width
                menu-entries menu-entry-action menu-entry-ready?
                menu-entry-icon menu-icon-size)
          (only (schevana kits px) px-invert)
          (only (schevana kits ui) ui-menu-open-tag ui-menu-open!
                ui-draw-highlight ui-draw-separator ui-draw-panel))

  (library-layer desktop)

  (define-state *menu* #f)

  ;; The menu's numbers are settings, which a style may give: an entry's
  ;; height (a rule from the font), a separator's height, the room above the
  ;; first entry and below the last, the text's inset, the least width, the
  ;; font, the entries' ink (chosen and not), and where their text goes.
  (at-load
   (theme-default! 'menu-item-height
                   (theme-rule (max 26 (round (+ (font-line-height 'ui) 11))))))
  (at-load
   (theme-default! 'menu-separator-height 9))
  (at-load
   (theme-default! 'menu-pad 5))
  (at-load
   (theme-default! 'menu-text-x 18))
  (at-load
   (theme-default! 'menu-min-width 230))
  (at-load
   (theme-default! 'menu-font 'ui))
  (at-load
   (theme-default! 'menu-ink 'text-dim))
  (at-load
   (theme-default! 'menu-ink-selected 'text))
  (at-load
   (theme-default! 'menu-ink-pressed 'bg-2))   ; on an outline's inversion
  (at-load
   (theme-default! 'menu-choose 'click))
  (at-load
   (theme-default! 'menu-blink 0))
  (at-load
   (theme-default! 'menu-hover 'fill))
  ;; where the entries' text goes: left, menu-text-x in, or center (as on
  ;; the Lisp machines)
  (at-load
   (theme-default! 'menu-align 'left))

  (define-state *menu-blink*
    #f)   ; (start-ms entry thunk) while a chosen entry blinks
  ;; (x y entry): where a press that is held down opened the menu, and the
  ;; entry there, until the pointer has left both. A release before that
  ;; only ends the press that opened the menu (a menu may open under the
  ;; pointer).
  (define-state *menu-held-at* #f)
  (define-state *menu-under*
    #f)   ; the entry under the pointer, shown pressed while held

  (define (menu-item-height) (theme 'menu-item-height))

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

  ;; Returns the room that the icons of m's entries take before their
  ;; text: an icon's side and a gap, or none (menu-icon-size).
  (define (menu-icon-room m)
    (let ([s (menu-icon-size m (theme 'menu-font))]) (if (> s 0) (+ s 8) 0)))

  ;; Returns where menu m and its pieces are, which its drawing, its clicks
  ;; and the pointer all read: (menu x y w h), then (filter x y w h) when it
  ;; filters, then each entry's (i x y w h) or each separator's (separator x
  ;; y w h), from top to bottom.
  (define-part (menu-areas m)
    (let* ([es (menu-entries m)] [ih (theme 'menu-item-height)]
           [sh (theme 'menu-separator-height)] [pad (theme 'menu-pad)]
           [head (if (menu-filter? m) (+ ih 8) 0)]
           [icons (menu-icon-room m)]
           [w (fold-left (lambda (acc e)
                           (if (pair? e)
                               (max acc (+ 8 (* 2 (theme 'menu-text-x)) icons
                                           (menu-label-width
                                            (car e) (theme 'menu-font))))
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

  ;; The areas of menu m as it draws them, computed in its place, 'menu;
  ;; the pointer reads these too.
  (define (placed-menu-areas m) (with-place 'menu (lambda () (menu-areas m))))

  ;; Returns the menu's box as (values x y w h).
  (define (menu-geometry m) (apply values (cdar (placed-menu-areas m))))

  (define (point-in-menu? px py)
    (apply point-in? px py (cdar (placed-menu-areas *menu*))))

  ;; Returns the index of the entry under (px, py), or #f.
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
              (if (menu-entry-ready? (vector-ref es i))
                  (menu-sel-set! *menu* i)
                  (loop (+ i (if (zero? dir) 1 dir)) (+ tries 1)))))))
      (request-frame!)))

  (define (menu-activate! i)
    (let ([es (menu-entries *menu*)])
      (when (and i (>= i 0) (< i (length es))
                 (menu-entry-ready? (list-ref es i))
                 (not *menu-blink*))
        (let ([thunk (menu-entry-action (list-ref es i))])
          (if (> (theme 'menu-blink) 0)
              (begin (set! *menu-blink* (list (now-ms) i thunk))
                     (menu-blink!))
              (menu-run! thunk))))))

  (define (menu-run! thunk)
    (close-menu!)
    (safe-call 'menu thunk (lambda (c) (report-error! 'menu c))))

  ;; A blink's phases last 60 ms each: off, on, off, on, ...; when they are
  ;; done, the menu closes and the chosen entry's action runs.
  (define (menu-phase b) (quotient (- (now-ms) (car b)) 60))

  ;; Asks for the blink's current phase to be drawn, and sets a timer for
  ;; the start of the next phase.
  (define (menu-blink!)
    (let ([b *menu-blink*])
      (when b
        (cond [(not *menu*) (set! *menu-blink* #f)]
              [(< (menu-phase b) (* 2 (theme 'menu-blink)))
               (menu-request!)
               (after (- (+ (car b) (* 60 (+ (menu-phase b) 1))) (now-ms))
                      (lambda () (menu-blink!)))]
              [else (set! *menu-blink* #f) (menu-run! (caddr b))]))))

  ;; An entry that can't be chosen now shows no highlight under the
  ;; pointer: nothing is chosen while the pointer is on it.
  (define (menu-mouse-move x y)
    (let* ([at *menu-held-at*]
           [i (let ([i (menu-entry-at x y)])
                (and i (if (menu-entry-ready? (list-ref (menu-entries *menu*)
                                                        i))
                           i
                           -1)))])
      (when (and i (not (= i (menu-sel *menu*))))
        (menu-sel-set! *menu* i)
        (request-frame!))
      (when (and at (> (+ (abs (- x (car at))) (abs (- y (cadr at)))) 4)
                 (not (eqv? i (caddr at))))
        (set! *menu-held-at* #f))
      (unless (eqv? i *menu-under*)   ; held, the pressed look follows
        (set! *menu-under* i)
        (when *mouse-button* (menu-request!)))))

  ;; Asks for a frame of the menu's own box.
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

  ;; Draws the open menu in its place with the style's draw-menu (called by
  ;; name), which is handed what it shows: the menu, its areas, the entry
  ;; shown as chosen (during a blink, the blinking entry in the on phases
  ;; and none between them) and the flags of that entry's highlight.
  (define (menu-draw) (when *menu* (with-place 'menu menu-draw-placed)))

  (define (menu-draw-placed)
    (let* ([m *menu*] [b *menu-blink*]
           [on (if b (and (odd? (menu-phase b)) (cadr b)) (menu-sel m))])
      ((world-value 'draw-menu) m (menu-areas m) on
                                (if on (menu-entry-flags on) '()))))

  ;; Draws menu m in its areas (menu-areas), with entry on shown as chosen
  ;; (#f for none) and with its highlight's flags (menu-entry-flags). An
  ;; entry's icon goes at the text's inset, and the texts after the icons'
  ;; room.
  (define-part (draw-menu m areas on flags)
    (let* ([es (list->vector (menu-entries m))] [font (theme 'menu-font)]
           [lh (font-line-height font)] [f (assq 'filter areas)]
           [is (menu-icon-size m font)] [icons (menu-icon-room m)])
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
               (let* ([sel? (eqv? what on)]
                      [flags (if sel? flags '())]
                      [e (vector-ref es what)]
                      [label (car e)]
                      [icon (menu-entry-icon e)]
                      [text (menu-label-text label)]
                      [key (menu-label-key label)]
                      [ink (theme (cond [(not (menu-entry-ready? e))
                                         'menu-ink-unready]
                                        [(not sel?) 'menu-ink]
                                        [(and (memq 'outline flags)
                                              (memq 'pressed flags))
                                         'menu-ink-pressed]
                                        [else 'menu-ink-selected]))])
                 (when sel?
                   (ui-draw-highlight (+ x 5) y (- w 10) h flags))
                 (when (and icon (> is 0))
                   (icon (+ x (theme 'menu-text-x)) (+ y (/ (- h is) 2)) is
                         '()))
                 (draw-text (if (eq? (theme 'menu-align) 'center)
                                (+ x icons
                                   (/ (- w icons (text-width text font)) 2))
                                (+ x (theme 'menu-text-x) icons))
                            (+ y (/ (- h lh) 2)) text ink font)
                 ;; the key that does the same, at the right
                 (when key
                   (draw-text (- (+ x w) (theme 'menu-text-x)
                                 (text-width key font))
                              (+ y (/ (- h lh) 2)) key
                              (if sel? ink 'text-faint) font)))]))
          a))
       areas)))

  ;; Returns the flags of entry i's highlight: outline when the style's
  ;; menu-hover says so, and pressed while a button is held on the entry.
  (define (menu-entry-flags i)
    (append (if (eq? (theme 'menu-hover) 'outline) '(outline) '())
            (if (and *mouse-button*
                     (eqv? i (menu-entry-at *mouse-x* *mouse-y*)))
                '(pressed)
                '())))

  ;; Draws the filter's field: what has been typed, or a hint. A filter too
  ;; long for the field scrolls, so its end and the caret stay in view.
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

  ;;; The menu's surface, over the bars and under the toasts.

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
        ;; the pointer selects as it moves, but in click mode not while a
        ;; button is held (the press in the window that opened the menu)
        [(move) (when (or release? (not button)) (menu-mouse-move x y))])))

  ;; A second press on the frame button that opened a window's menu is a
  ;; double click on that button (CDE's menu button closes the window).
  ;; Returns a thunk for the action the style names in button-double-click,
  ;; or #f.
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

  (at-load
   (define-surface menu 30
     'draw 'menu-draw 'box 'menu-box 'at 'menu-at 'mouse 'menu-mouse
     'key 'menu-takes 'doc (lambda (what) '((L . "Choose")))))

  ;; Opens a window's menu, on a right click on its title or a press on a
  ;; frame's menu button (the window manager calls the part), or on a right
  ;; click on its taskbar button. It offers Shade when the window's style
  ;; shades windows, and Restore when the window is minimized. An icon's menu
  ;; ((schevana desktop icons)) opens its window or closes both.
  (define-part (open-window-menu win x y)
    (let ([main (window-ref win 'icon-for)])
      (if main
          (open-menu! x y
                      `(("Open" . ,(lambda () (focus-window! main)))
                        separator
                        ("Close" . ,(lambda () (close-window! win))))
                      'tag (cons 'window win))
          (open-window-menu-of win x y))))

  (define (open-window-menu-of win x y)
    (open-menu! x y
                `(,@(if (eq? (window-state win) 'minimized)
                        `(("Restore" . ,(lambda () (focus-window! win))))
                        '())
                  ("Bind to $w for the REPL"
                   . ,(lambda ()
                        (define-top-level-value '$w win)
                        (notify (format "$w = ~s" win))))
                  (,(if (eq? (window-state win) 'maximized)
                        "Restore\tCtrl+Shift+M"
                        "Maximize\tCtrl+Shift+M")
                   . ,(lambda () (toggle-maximize! win)))
                  ("Minimize\tCtrl+Shift+N" . ,(lambda ()
                                                 (minimize-window! win)))
                  ,@(if (or (shaded? win) (shades? win))
                        `((,(if (shaded? win) "Unshade" "Shade")
                           . ,(lambda () (toggle-shade! win))))
                        '())
                  separator
                  ("Close\tCtrl+Shift+W" . ,(lambda () (close-window! win))))
                'tag (cons 'window win)))

  ;; Whether win's style shades it: with a shade button, or with a double
  ;; click or the wheel on its title.
  (define (shades? win)
    (or (and (assq 'shade (frame-regions win)) #t)
        (eq? (window-setting win 'title-double-click) 'shade)
        (eq? (window-setting win 'title-wheel) 'shade)))

  ;; The widget kit's menus are this menu ((schevana kits ui)): these hooks
  ;; open them and give the tag of the one that is open.
  (set-hook! (ui-menu-open! x y entries . opts)
    (apply open-menu! x y entries opts))
  (set-hook! (ui-menu-open-tag) (and *menu* (menu-tag *menu*))))
