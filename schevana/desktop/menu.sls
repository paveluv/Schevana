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
                draw-text fill-box focus-window! font font-ascent
                font-char-width font-line-height frame-regions get-font
                minimize-window! notify now-ms point-in?
                report-error! request-frame! safe-call screen-h screen-w
                shaded? text-width theme theme-default! theme-part theme-rule
                toggle-maximize! toggle-shade! window-action! window-at
                window-ref window-region window-setting window-state with-clip
                with-place world-value)
          (only (schevana kits menu) make-menu menu-x menu-y menu-sel
                menu-sel-set! menu-filter menu-filter-set! menu-filter?
                menu-tag menu-label-text menu-label-key menu-entries
                menu-entry-action menu-entry-ready? menu-entry-icon
                menu-icon-size)
          (only (schevana kits px) px-invert)
          (only (schevana kits text) text-ink)
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
  ;; the room a menu adds to its widest entry
  (at-load
   (theme-default! 'menu-width-extra 8))
  ;; what shows the chosen entry: its row, its text's cell (that and
  ;; menu-highlight-extra wide), or its text's ink, each grown by
  ;; menu-highlight-outset all round (Genera's: a clear pixel and the box,
  ;; as in Peek's Reset menu)
  (at-load
   (theme-default! 'menu-highlight 'row))
  (at-load
   (theme-default! 'menu-highlight-extra 0))
  (at-load
   (theme-default! 'menu-highlight-outset 0))
  ;; the text at the top of its row, not centered in it (the CADR's rows
  ;; are a character cell and its VSP below)
  (at-load
   (theme-default! 'menu-text-top #f))
  ;; the filter's hint (#f for none: the filter's row shows only once
  ;; something is typed), its font (#f for the menu's), and whether a menu
  ;; that filters is at least as wide as the hint
  (at-load
   (theme-default! 'menu-filter-hint "Type to filter…"))
  (at-load
   (theme-default! 'menu-hint-font #f))
  (at-load
   (theme-default! 'menu-fit-filter #f))
  ;; whether an entry's text starts on a whole pixel: #f, #t (the nearest)
  ;; or floor (down, as the CADR's centering truncated)
  (at-load
   (theme-default! 'menu-snap-text #f))
  ;; whether an entry's key shows at its right (the Lisp machines' menus
  ;; are words alone)
  (at-load
   (theme-default! 'menu-keys #t))
  ;; whether a menu opens with its first entry chosen, which the keys then
  ;; move; #f: nothing is chosen but the entry under the pointer, and
  ;; leaving the entries chooses none (the CADR's box under the mouse)
  (at-load
   (theme-default! 'menu-select-first #t))
  ;; where a menu opens: its corner at the point (corner), or with the
  ;; entry last chosen from a menu of its kind (a dropdown's current one)
  ;; under the point, and centered on the point when there is none
  ;; (last-choice, the CADR's :CENTER-AROUND)
  (at-load
   (theme-default! 'menu-open-at 'corner))
  ;; how far the pointer may leave a menu it has been in before the menu
  ;; closes, or #f to stay open until a press (the CADR's hysteresis)
  (at-load
   (theme-default! 'menu-leave-distance #f))

  (define-state *menu-blink*
    #f)   ; (start-ms entry thunk) while a chosen entry blinks
  ;; (x y entry): where a press that is held down opened the menu, and the
  ;; entry there, until the pointer has left both. A release before that
  ;; only ends the press that opened the menu (a menu may open under the
  ;; pointer).
  (define-state *menu-held-at* #f)
  (define-state *menu-under*
    #f)   ; the entry under the pointer, shown pressed while held
  (define-state *menu-entered*
    #f)   ; whether the pointer has been in the open menu
  ;; ((kind . label) ...): the label last chosen from each kind of menu
  ;; (menu-kind), for one that opens on its last choice
  (define-state *menu-last-choices* '())

  ;; Returns what menus share a last choice: a tag's kind (window, for
  ;; every window's menu), the tag itself, or #f for none.
  (define (menu-kind m)
    (let ([tag (menu-tag m)]) (if (pair? tag) (car tag) tag)))

  (define (menu-item-height) (theme 'menu-item-height))

  (define (open-menu! x y items . opts)
    (let ([filter? (plist-ref opts 'filter #f)] [tag (plist-ref opts 'tag #f)]
          [current (plist-ref opts 'selected #f)])   ; a dropdown's
      (set! *menu* (make-menu x y items 0 "" filter? tag))
      (when (eq? (theme 'menu-open-at) 'last-choice)
        (let-values ([(x y) (menu-open-point *menu* x y current)])
          (set! *menu* (make-menu x y items 0 "" filter? tag))))
      (set! *menu-blink* #f)   ; an old menu's blink ends with it
      (set! *menu-held-at*
        (and *mouse-button*
             (list *mouse-x* *mouse-y*
                   (menu-entry-at *mouse-x* *mouse-y*))))
      (set! *menu-under* #f)
      (set! *menu-entered* (point-in-menu? *mouse-x* *mouse-y*))
      (if (theme 'menu-select-first)
          (begin (menu-select-next! 0)
                 (when current (menu-sel-set! *menu* current)))
          (menu-sel-set! *menu* (menu-ready-at *mouse-x* *mouse-y*)))
      (request-frame!)))

  ;; Returns where menu m, asked to open at (x, y), goes so that the entry
  ;; last chosen from its kind (or current, an index) has the box around
  ;; its words at the point, the pixel before them and its row's top just
  ;; above it, as the CADR puts it (:CENTER-AROUND, menu.lisp:816-828), or,
  ;; with none, so that the menu's center is on the point.
  (define (menu-open-point m x y current)
    (let* ([areas (placed-menu-areas m)] [box (cdar areas)]
           [es (menu-entries m)]
           [last (let ([c (assq (menu-kind m) *menu-last-choices*)])
                   (and c (menu-kind m) (cdr c)))]
           [i (or current
                  (and last
                       (let loop ([es es] [i 0])
                         (cond [(null? es) #f]
                               [(and (pair? (car es))
                                     (equal? (caar es) last))
                                i]
                               [else (loop (cdr es) (+ i 1))]))))]
           [a (and i (assv i (cdr areas)))])
      (if a
          (apply (lambda (ex ey ew eh)
                   (let ([tx (with-place 'menu
                               (lambda ()
                                 (menu-text-left
                                  m ex ew
                                  (menu-entry-text-width (list-ref es i)))))])
                     (values (- x (- tx 1 (car box)))
                             (- y (- ey (cadr box)) 1))))
                 (cdr a))
          (values (- x (quotient (caddr box) 2))
                  (- y (quotient (cadddr box) 2))))))

  ;; Returns the index of the entry under (px, py) that can be chosen, or
  ;; -1, which is none.
  (define (menu-ready-at px py)
    (let ([i (menu-entry-at px py)])
      (if (and i (menu-entry-ready? (list-ref (menu-entries *menu*) i)))
          i
          -1)))

  ;; Returns where an entry's words start in its row at x, w wide, when
  ;; they are tw wide: centered in the room left of the keys (menu-align
  ;; center), or menu-text-x in, after the icons.
  (define (menu-text-left m x w tw)
    (if (eq? (theme 'menu-align) 'center)
        (let ([icons (menu-icon-room m)])
          (+ x icons (/ (- w icons (menu-key-room m) tw) 2)))
        (+ x (theme 'menu-text-x) (menu-icon-room m))))

  (define (close-menu!)
    (set! *menu* #f)
    (request-frame!))

  ;; Returns the room that the icons of m's entries take before their
  ;; text: an icon's side and a gap, or none (menu-icon-size).
  (define (menu-icon-room m)
    (let ([s (menu-icon-size m (theme 'menu-font))]) (if (> s 0) (+ s 8) 0)))

  ;; The font an entry's key is drawn in: the menu's, as faint text has it
  ;; (Genera's italic, 'faint-text-font).
  (define (menu-key-font)
    (let ([font (get-font (theme 'menu-font))]
          [make (theme-part 'faint-text-font)])
      (if make (make font) font)))

  ;; Returns how wide an entry's words are as they are drawn: in the menu's
  ;; font, or, for an entry that can't be chosen now, as faint text has it
  ;; (Genera's italic).
  (define (menu-entry-text-width e)
    (text-width (menu-label-text (car e))
                (if (menu-entry-ready? e)
                    (theme 'menu-font)
                    (menu-key-font))))

  ;; Returns the room an entry's own key takes after its words, or 0.
  (define (menu-own-key-room e)
    (let ([k (menu-label-key (car e))])
      (if k (+ 24 (text-width k (menu-key-font))) 0)))

  ;; Returns the room the keys of m's entries take after their text, in a
  ;; menu whose text is centered: the widest key and the gap before it, or
  ;; none. (Text at the left needs no column: each entry's key goes at the
  ;; right, past its own text.)
  (define (menu-key-room m)
    (if (and (theme 'menu-keys) (eq? (theme 'menu-align) 'center))
        (let ([w (fold-left (lambda (acc e)
                              (let ([k (and (pair? e)
                                            (menu-label-key (car e)))])
                                (if k (max acc (text-width k (menu-key-font)))
                                    acc)))
                            0 (menu-entries m))])
          (if (> w 0) (+ w 24) 0))
        0))

  ;; Returns where menu m and its pieces are, which its drawing, its clicks
  ;; and the pointer all read: (menu x y w h), then (filter x y w h) when it
  ;; filters, then each entry's (i x y w h) or each separator's (separator x
  ;; y w h), from top to bottom.
  (define-part (menu-areas m)
    (let* ([es (menu-entries m)] [ih (theme 'menu-item-height)]
           [sh (theme 'menu-separator-height)] [pad (theme 'menu-pad)]
           [head (if (and (menu-filter? m)
                          (or (theme 'menu-filter-hint)
                              (not (string=? (menu-filter m) ""))))
                     (+ ih 8)
                     0)]
           [icons (menu-icon-room m)] [keys (menu-key-room m)]
           [w (fold-left (lambda (acc e)
                           (if (pair? e)
                               (max acc (+ (theme 'menu-width-extra)
                                           (* 2 (theme 'menu-text-x)) icons
                                           (menu-entry-text-width e)
                                           (if (or (> keys 0)
                                                   (not (theme 'menu-keys)))
                                               keys
                                               (menu-own-key-room e))))
                               acc))
                         (if (and (menu-filter? m) (theme 'menu-fit-filter)
                                  (theme 'menu-filter-hint))
                             (max (theme 'menu-min-width)
                                  (+ 32 (text-width (theme 'menu-filter-hint)
                                                    (menu-hint-font))))
                             (theme 'menu-min-width))
                         es)]
           [h (fold-left (lambda (acc e) (+ acc (if (pair? e) ih sh)))
                         (+ pad pad head) es)]
           [x (clamp (menu-x m) 4 (- (screen-w) w 4))]
           [y (let-values ([(dx dy dw dh) (desktop-rect)])
                (clamp (menu-y m) (+ 2 dy) (- (screen-h) h 4)))])
      (cons (list 'menu x y w h)
            (append (if (> head 0)
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
        (let ([thunk (menu-entry-action (list-ref es i))]
              [kind (menu-kind *menu*)])
          (when kind
            (set! *menu-last-choices*
              (cons (cons kind (car (list-ref es i)))
                    (remp (lambda (c) (eq? (car c) kind))
                          *menu-last-choices*))))
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
                (cond [i (menu-ready-at x y)]
                      ;; off the entries, none, where only the pointer
                      ;; chooses
                      [(theme 'menu-select-first) #f]
                      [else -1]))])
      (menu-leave-check x y)
      (when *menu*   ; still open
        (when (and i (not (= i (menu-sel *menu*))))
          (menu-sel-set! *menu* i)
          (request-frame!))
        (when (and at (> (+ (abs (- x (car at))) (abs (- y (cadr at)))) 4)
                   (not (eqv? i (caddr at))))
          (set! *menu-held-at* #f))
        (unless (eqv? i *menu-under*)   ; held, the pressed look follows
          (set! *menu-under* i)
          (when *mouse-button* (menu-request!))))))

  ;; Closes the menu once the pointer, having been in it, is further from
  ;; it than menu-leave-distance (HYSTERETIC-WINDOW-MIXIN,
  ;; mouse.lisp:871-890).
  (define (menu-leave-check x y)
    (let ([d (theme 'menu-leave-distance)])
      (when d
        (let-values ([(mx my mw mh) (menu-geometry *menu*)])
          (cond [(point-in-menu? x y) (set! *menu-entered* #t)]
                [(and *menu-entered*
                      (or (< x (- mx d)) (>= x (+ mx mw d))
                          (< y (- my d)) (>= y (+ my mh d))))
                 (close-menu!)])))))

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
           [is (menu-icon-size m font)] [icons (menu-icon-room m)]
           [keys (menu-key-room m)] [kf (menu-key-font)])
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
                 (let* ([tw (menu-entry-text-width e)]
                        [tx (menu-snap (menu-text-left m x w tw))]
                        [ty (menu-snap (if (theme 'menu-text-top)
                                           y
                                           (+ y (/ (- h lh) 2))))]
                        [p (theme 'menu-highlight-outset)])
                   (when sel?
                     (case (theme 'menu-highlight)
                       [(ink)
                        (let-values ([(l t iw ih) (text-ink text font)])
                          (ui-draw-highlight (+ tx l (- p))
                                             (+ ty (font-ascent font) t (- p))
                                             (+ iw p p) (+ ih p p) flags))]
                       [(text)
                        (ui-draw-highlight (- tx p) (- ty p)
                                           (+ tw (theme 'menu-highlight-extra)
                                              p p)
                                           (+ lh p p) flags)]
                       [else (ui-draw-highlight (+ x 5) y (- w 10) h flags)]))
                   (when (and icon (> is 0))
                     (icon (+ x (theme 'menu-text-x)) (+ y (/ (- h is) 2)) is
                           '()))
                   (draw-text tx ty text ink font))
                 ;; the key that does the same, at the right, in the font
                 ;; of faint text whether or not the entry is chosen
                 (when (and key (theme 'menu-keys))
                   (draw-text (menu-snap (- (+ x w) (theme 'menu-text-x)
                                            (text-width key kf)))
                              (menu-snap
                               (if (theme 'menu-text-top)
                                   y
                                   (+ y (/ (- h (font-line-height kf)) 2))))
                              key (if sel? ink 'text-faint) kf)))]))
          a))
       areas)))

  ;; Returns v on a whole pixel where the style's menu-snap-text says so.
  (define (menu-snap v)
    (case (theme 'menu-snap-text)
      [(#f) v]
      [(floor) (floor v)]
      [else (floor (+ v 1/2))]))

  ;; The filter's hint's font.
  (define (menu-hint-font) (or (theme 'menu-hint-font) (theme 'menu-font)))

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
          (let ([hint (menu-hint-font)])
            (draw-text (+ x 10) (+ y (/ (- h (font-line-height hint)) 2))
                       (theme 'menu-filter-hint) 'text-faint hint))
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
