;;; (schevana styles cons desktop) — a part of the Cons style ((schevana
;;; styles cons)): the desktop's parts, each handed what it draws: menus,
;;; the bars, toasts and the wallpaper.

(library (schevana styles cons desktop)
  (export
    cons-draw-menu cons-draw-taskbar cons-draw-toasts cons-draw-topbar
    cons-draw-wallpaper cons-menu-areas cons-mouse-doc-text cons-taskbar-areas
    cons-toast-boxes)
  (import (chezscheme)
          (only (schevana base) clamp library-layer)
          (only (schevana core) *focus* *hover* *toasts* *windows* alpha
                desktop-rect draw-line draw-text fill-box fill-circle
                fill-wallpaper font font-line-height screen-h screen-w
                text-width theme visible? window-id window-title window?
                with-clip)
          (only (schevana kits menu) menu-entries menu-entry-icon
                menu-filter menu-filter? menu-icon-size menu-label-key
                menu-label-text menu-label-width menu-x menu-y)
          (only (schevana kits text) text-draw-centered text-fit)
          (only (schevana kits ui) ui-draw-field ui-draw-panel ui-text-box-areas
                ui-control-height ui-draw-window-icon)
          (only (schevana styles cons cells) cons-cell cons-dot-x cons-dot-y
                cons-down! cons-nil! cons-nil-h! cons-pair! cons-pair-h!
                cons-pointer! cons-right!)
          (only (schevana styles cons widgets) cons-arrow cons-space))

  (library-layer looks)

  ;;; The desktop layer: menus, the bars, toasts and the wallpaper, each
  ;;; part handed what it draws.

  ;; A menu is a list drawn vertically: each entry is a pair whose car is
  ;; the entry and whose cdr, a cell at the right, points down to the next
  ;; pair; the last one's cdr holds nil, and a separator is a longer
  ;; pointer. An entry's row is its pair and the gap below it
  ;; (menu-item-height); the filter's field, when the menu has one, is
  ;; above the entries. An entry's icon goes in its car, before the text.
  (define (cons-menu-areas m)
    (let* ([es (menu-entries m)] [c (cons-cell)] [ih (theme 'menu-item-height)]
           [sh (theme 'menu-separator-height)] [pad (theme 'menu-pad)]
           [tx (theme 'menu-text-x)] [font (theme 'menu-font)]
           [icons (cons-menu-icon-room m font)]
           [head (if (menu-filter? m) (+ (ui-control-height) pad) 0)]
           [w (fold-left (lambda (acc e)
                           (if (pair? e)
                               (max acc
                                    (+ pad tx icons
                                       (menu-label-width (car e) font)
                                       tx c pad))
                               acc))
                         (theme 'menu-min-width) es)]
           [h (fold-left (lambda (acc e) (+ acc (if (pair? e) ih sh)))
                         (+ pad pad head (- c ih)) es)]
           [x (clamp (menu-x m) 4 (- (screen-w) w 4))]
           [y (let-values ([(dx dy dw dh) (desktop-rect)])
                (clamp (menu-y m) (+ 2 dy) (- (screen-h) h 4)))])
      (cons (list 'menu x y w h)
            (append (if (menu-filter? m)
                        (list (list 'filter (+ x pad) (+ y pad) (- w pad pad)
                                    (ui-control-height)))
                        '())
                    (let loop ([es es] [i 0] [ey (+ y pad head)])
                      (if (null? es)
                          '()
                          (let ([eh (if (pair? (car es)) ih sh)])
                            (cons (list (if (pair? (car es)) i 'separator)
                                        x ey w eh)
                                  (loop (cdr es) (+ i 1) (+ ey eh))))))))))

  ;; Returns the room that the icons of m's entries take before their
  ;; text: an icon's side and a gap, or none.
  (define (cons-menu-icon-room m font)
    (let ([is (menu-icon-size m font)]) (if (> is 0) (+ is 6) 0)))

  ;; The entry under the mouse, or the one the keys chose, fills with ink,
  ;; at 0.6 while a button is held on it; a blinking entry fills in its on
  ;; phases (on).
  (define (cons-draw-menu m areas on flags)
    (let* ([es (list->vector (menu-entries m))] [font (theme 'menu-font)]
           [lh (font-line-height font)] [c (cons-cell)]
           [pad (theme 'menu-pad)] [tx (theme 'menu-text-x)]
           [is (menu-icon-size m font)] [icons (cons-menu-icon-room m font)]
           [f (assq 'filter areas)])
      (apply ui-draw-panel (append (cdar areas) '((menu))))
      (when f
        (apply (lambda (fx fy fw fh) (cons-menu-filter! m fx fy fw fh))
               (cdr f)))
      (let loop ([as (cdr areas)])
        (unless (null? as)
          (let ([a (car as)])
            (when (fixnum? (car a))
              (apply
               (lambda (i x y w h)
                 (let* ([next (find (lambda (a) (fixnum? (car a))) (cdr as))]
                        [tint (and (eqv? i on)
                                   (if (memq 'pressed flags)
                                       (alpha 'cons-ink 0.6)
                                       'cons-ink))]
                        [px (+ x pad)] [pw (- w pad pad c)])
                   (cons-pair-h! px y pw c c 'cons-ink 1 tint #f)
                   (let* ([e (vector-ref es i)] [label (car e)]
                          [icon (menu-entry-icon e)]
                          [key (menu-label-key label)]
                          [kw (if key (+ (text-width key font) 12) 0)]
                          [ink (if tint 'window-bg (theme 'menu-ink))])
                     (when (and icon (> is 0))
                       (icon (+ px tx) (+ y (/ (- c is) 2)) is '()))
                     (draw-text (+ px tx icons) (+ y (/ (- c lh) 2))
                                (text-fit (menu-label-text label)
                                          (- pw tx icons 4 kw) font)
                                ink font)
                     (when key
                       (draw-text (- (+ px pw) tx (- kw 12))
                                  (+ y (/ (- c lh) 2)) key
                                  (if tint ink 'text-faint) font)))
                   (if next
                       (cons-down! (cons-dot-x (+ px pw) c 1)
                                   (cons-dot-y y c 1) (caddr next) c
                                   'cons-ink 1)
                       (cons-nil! (+ px pw) y c 'cons-ink 1 #f))))
               a))
            (loop (cdr as)))))))

  ;; The launcher's filter: a string being typed, in the focused box.
  (define (cons-menu-filter! m x y w h)
    (let* ([font (theme 'menu-font)] [lh (font-line-height font)]
           [f (menu-filter m)] [ty (+ y (/ (- h lh) 2))]
           [a (car (ui-text-box-areas x y w h '()))] [tx (cadr a)]
           [tw (cadddr a)])
      (ui-draw-field x y w h '(focused))
      (if (string=? f "")
          (draw-text tx ty "Type to filter…" 'text-faint font)
          (with-clip (tx y tw h)
            (let ([ex (draw-text (min tx (- (+ tx tw) 3 (text-width f font)))
                                 ty f 'text font)])
              (fill-box (+ ex 1) (+ y (round (/ (- h lh 1) 2))) 1.5
                          (round (+ lh 1)) 'accent))))))

  ;; The mouse documentation as the data it is, in the code font:
  ;; ((L . "Select") (R . "Task menu")).
  (define (cons-mouse-doc-text doc) (format "~s" doc))

  ;; The top bar as the built-in one draws it, with the mouse documentation
  ;; after the title, faint, in the room the status leaves.
  (define (cons-draw-topbar h areas open? doc status)
    (let* ([w (screen-w)] [ty (/ (- h (font-line-height 'ui)) 2)]
           [gap (max 11 (round (* 0.6 (font-line-height 'ui))))]
           [dot-w (text-width "·" 'ui)]
           [l (assq 'launcher areas)] [t (assq 'title areas)])
      (fill-box 0 0 w h (alpha 'panel 0.92))
      (draw-line 0 (- h 0.5) w (- h 0.5) (alpha 'panel-text 0.12))
      (when l
        (let ([x (cadr l)] [y (caddr l)] [lw (cadddr l)] [lh (car (cddddr l))])
          (when (or (equal? *hover* '(surface topbar launcher)) open?)
            (fill-box (+ x 6) (+ y 4) (- lw 6) (- lh 8) 'panel-hover))
          (draw-text (+ x 18) (+ y ty) "λ  Schevana" 'panel-accent 'ui-bold)))
      (let* ([title-end
              (if t
                  (draw-text (+ (cadr t) 14) (+ (caddr t) ty)
                             (if *focus* (window-title *focus*) "Desktop")
                             'panel-text 'ui-bold)
                  0)]
             ;; the status from the right, while it fits beside the title
             [left (let loop ([segs (reverse
                                     (filter string? (map cdr status)))]
                              [x (- w 14)]
                              [first? #t])
                     (if (null? segs)
                         x
                         (let* ([s (car segs)]
                                [right (if first? x (- x gap dot-w gap))]
                                [x0 (- right (text-width s 'ui))])
                           (if (> x0 (+ title-end gap gap))
                               (begin
                                 (unless first?
                                   (draw-text (- x gap dot-w) ty "·"
                                              'panel-dim 'ui))
                                 (draw-text x0 ty s 'panel-text 'ui)
                                 (loop (cdr segs) x0 #f))
                               x))))])
        (unless (or (not doc) (< (- left title-end) 120))
          (draw-text (+ title-end 24)
                     (/ (- h (font-line-height 'mono-small)) 2)
                     (text-fit doc (- left title-end 48) 'mono-small)
                     'panel-dim 'mono-small)))))

  ;; The taskbar's windows are a list, [Tasks|•]→[REPL|•]→[Clock|/]: each
  ;; window's area is its pair and its pointer, with a car as wide as its
  ;; icon and title and a little more, at most 160, and narrower when the
  ;; chain would not fit. The hint, a comment, sits at the right while the chain
  ;; leaves it room.
  (define (cons-taskbar-areas h hint)
    (let* ([w (screen-w)] [y0 (- (screen-h) h)]
           [ws (sort (lambda (a b) (< (window-id a) (window-id b))) *windows*)]
           [n (length ws)] [c (cons-cell)] [a (cons-arrow)]
           [g (cons-space)]
           [hint-w (+ g g g g (text-width (string-append "; " hint)
                                     'mono-small))]
           [cars (map (lambda (win)
                        (min 160 (+ g g (cons-taskbar-icon-room)
                                    (ceiling (text-width (window-title win)
                                                         'ui)))))
                      ws)]
           [chain (apply + (map (lambda (cw) (+ cw c a)) cars))]
           [hint? (<= (+ chain hint-w) (- w g g g g))]
           [room (- w g g g g (if hint? hint-w 0))]
           [cars (if (or (<= chain room) (zero? n))
                     cars
                     (let ([per (max c (floor (/ (- room (* n (+ c a))) n)))])
                       (map (lambda (cw) (min cw per)) cars)))])
      (append (if hint? (list (list 'hint (- w hint-w) y0 hint-w h)) '())
              (let loop ([ws ws] [cars cars] [x (+ g g)])
                (if (null? ws)
                    '()
                    (cons (list (car ws) x y0 (+ (car cars) c a) h)
                          (loop (cdr ws) (cdr cars) (+ x (car cars) c a))))))))

  ;; Returns the side of a window's icon in its car, and the room it takes
  ;; with the gap after it.
  (define (cons-taskbar-icon-size) (round (font-line-height 'ui)))
  (define (cons-taskbar-icon-room) (+ (cons-taskbar-icon-size) 5))

  ;; The focused window's car fills with the panel's accent, a minimized
  ;; window's is faint, and the one under the mouse fills with the plain
  ;; ink. The window's icon goes before its title, the two centered.
  (define (cons-draw-taskbar h areas open? doc status hint)
    (let* ([w (screen-w)] [y0 (- (screen-h) h)]
           [c (cons-cell)] [a (cons-arrow)] [cy (+ y0 (quotient (- h c) 2))]
           [lh (font-line-height 'ui)] [ha (assq 'hint areas)])
      (fill-box 0 y0 w h (alpha 'panel 0.94))
      (draw-line 0 (+ y0 0.5) w (+ y0 0.5) (alpha 'panel-text 0.12))
      (when ha
        (draw-text (+ (cadr ha) (* 2 (cons-space)))
                   (+ y0 (/ (- h (font-line-height 'mono-small)) 2))
                   (string-append "; " hint) 'panel-dim 'mono-small))
      (let loop ([as (filter (lambda (a) (window? (car a))) areas)])
        (unless (null? as)
          (apply
           (lambda (win x y bw bh)
             (let* ([cw (- bw c a)] [focused? (eq? win *focus*)]
                    [hover? (equal? *hover* (list 'surface 'taskbar win))]
                    [min? (not (visible? win))]
                    [ink (cond [focused? 'panel-accent]
                               [min? 'panel-dim]
                               [else 'cons-ink])]
                    [tint (and (or focused? hover?) ink)]
                    [is (cons-taskbar-icon-size)]
                    [room (cons-taskbar-icon-room)]
                    [s (text-fit (window-title win) (- cw 8 room) 'ui)]
                    [ix (+ x (floor (/ (- cw room (text-width s 'ui)) 2)))])
               (cons-pair! x cy cw c ink 1 tint #f)
               (ui-draw-window-icon win ix (+ cy (/ (- c is) 2)) is
                                    (if min? '(dim) '()))
               (draw-text (+ ix room) (+ cy (/ (- c lh) 2)) s
                          (cond [tint 'panel] [min? 'panel-dim]
                                [else 'panel-text])
                          'ui)
               (if (null? (cdr as))
                   (cons-nil! (+ x cw) cy c ink 1 #f)
                   (cons-pointer! (+ x cw) (cadr (cadr as)) cy c ink 1))))
           (car as))
          (loop (cdr as))))))

  ;; Toasts are a list at the top right: each toast is a pair whose car
  ;; holds the text and whose cdr's dot, in the notification's color,
  ;; points down to the next.
  (define (cons-toast-boxes)
    (let ([c (cons-cell)] [a (cons-arrow)]
          [h (max (cons-cell) (round (+ (font-line-height 'ui) 10)))])
      (let-values ([(dx dy dw dh) (desktop-rect)])
        (let loop ([ts *toasts*] [y (+ dy (* 2 (cons-space)))] [acc '()])
          (if (null? ts)
              (reverse acc)
              (let* ([t (car ts)]
                     [text (text-fit (vector-ref t 1) (- (screen-w) 120) 'ui)]
                     [tw (+ (* 4 (cons-space)) c
                            (ceiling (text-width text 'ui)))])
                (loop (cdr ts) (+ y h a)
                      (cons (vector (- (+ dx dw) tw (* 2 (cons-space))) y tw h
                                    text
                                    (vector-ref t 2))
                            acc))))))))

  (define (cons-draw-toasts boxes)
    (let ([c (cons-cell)] [lh (font-line-height 'ui)])
      (let loop ([bs boxes])
        (unless (null? bs)
          (let* ([b (car bs)] [x (vector-ref b 0)] [y (vector-ref b 1)]
                 [tw (vector-ref b 2)] [h (vector-ref b 3)] [cw (- tw c)])
            (fill-box x y tw h 'window-bg)
            (cons-pair-h! x y cw h c 'cons-ink 1 #f #f)
            (draw-text (+ x (* 2 (cons-space))) (+ y (/ (- h lh) 2))
                       (vector-ref b 4) 'text 'ui)
            (if (null? (cdr bs))
                (cons-nil-h! (+ x cw) y c h 'cons-ink 1 #f)
                (let ([dx (cons-dot-x (+ x cw) c 1)] [my (cons-dot-y y h 1)])
                  (cons-down! dx my (vector-ref (cadr bs) 1) c 'cons-ink 1)
                  (fill-circle dx my (+ (/ c 10) 1/2) (vector-ref b 5))))
            (loop (cdr bs)))))))

  ;; The desktop: the wallpaper, and on it, faint, the world as data,
  ;; (λ "S C H E V A N A"): a chain of two cells ending in nil.
  (define (cons-draw-wallpaper w h)
    (fill-wallpaper 0 0 w h (theme 'wallpaper) 'desktop-top 'desktop-bottom)
    (let* ([ink (alpha 'watermark 0.08)] [lw 2]
           [s (round (* 0.38 (min w h)))] [c (round (/ s 3))]
           [a (round (* 0.7 c))]
           [name "S C H E V A N A"]
           [nw (+ 40 (ceiling (text-width name 'ui-bold)))]
           [x0 (round (/ (- w s c a nw c) 2))] [y0 (round (/ (- h s) 2))]
           [x1 (+ x0 s c a)] [y1 (+ y0 (round (/ (- s c) 2)))])
      (cons-pair-h! x0 y0 s s c ink lw #f #f)
      (text-draw-centered x0 y0 s s "λ" ink 'huge)
      (cons-right! (cons-dot-x (+ x0 s) c lw) (cons-dot-y y0 s lw) x1 c ink lw)
      (cons-pair-h! x1 y1 nw c c ink lw #f #f)
      (text-draw-centered x1 y1 nw c name ink 'ui-bold)
      (cons-nil! (+ x1 nw) y1 c ink lw #f))))
