;;; (schevana desktop taskbar) — the bar at the bottom: a button for each
;;; window (the left button focuses or minimizes it, the middle one closes it,
;;; the right one opens its menu) and a hint. A style may make it another kind
;;; of bar, with its own areas and drawing (Genera's who line); its parts are
;;; handed what they draw, just as the built-in ones are.

(library (schevana desktop taskbar)
  (export
    taskbar-height taskbar-box taskbar-areas taskbar-areas*
    placed-taskbar-areas taskbar-hint taskbar-doc-line taskbar-draw
    draw-taskbar draw-taskbar* taskbar-at taskbar-mouse taskbar-doc
    taskbar-frame)
  (import (chezscheme)
          (only (schevana base) at-load define-hook library-layer)
          (only (schevana core) *focus* *hover* *windows* alpha chrome-height
                define-part define-strip define-surface draw-line draw-text
                fill-box fill-circle font-line-height screen-h screen-w
                text-width theme-default! theme-rule visible? window-app
                window-id window-title window? with-place world-value)
          (only (schevana kits app) app-color)
          (only (schevana kits text) text-fit text-widest)
          (only (schevana desktop bar) bar-mouse bar-at)
          (only (schevana desktop menu) launcher-open?)
          (only (schevana desktop mousedoc) mouse-doc-frame mouse-doc-line)
          (only (schevana desktop status) *status-shown*)
          (only (schevana desktop topbar) topbar-height))

  (library-layer desktop)

  (at-load
   (theme-default! 'taskbar-height-min
                   (theme-rule (exact (round (+ (font-line-height 'ui) 13))))))
  ;; (computed in the bars' place, as the bar is drawn)
  (define (taskbar-height)
    (with-place 'bar
      (lambda () (chrome-height 'taskbar-height 'taskbar-height-min))))

  (define (taskbar-box)
    (let ([h (taskbar-height)]) (values 0 (- (screen-h) h) (screen-w) h)))

  ;; Returns the areas of a bar h high at the screen's bottom: the hint at the
  ;; right, while the buttons leave room for it, and a button for each
  ;; window, from left to right: ((hint x y w h) (window x y w h) ...).
  (define-part (taskbar-areas h hint)
    (let* ([w (screen-w)] [y0 (- (screen-h) h)]
           [ws (sort (lambda (a b) (< (window-id a) (window-id b))) *windows*)]
           [n (length ws)]
           [button-w (lambda (hint-w)
                       (if (zero? n)
                           0
                           (min 210 (/ (- w 16 hint-w (* 6 (- n 1))) n))))]
           ;; the hint is dropped when the buttons would be too narrow for
           ;; their titles
           [hint-w (let ([hw (+ 24 (text-width hint 'ui-small))]
                         [want (min 210 (+ 48 (text-widest (map window-title ws)
                                                           'ui)))])
                     (if (>= (button-w hw) want) hw 0))]
           [bw (button-w hint-w)])
      (append (if (> hint-w 0) (list (list 'hint (- w hint-w) y0 hint-w h)) '())
              (map (lambda (win i) (list win (+ 8 (* i (+ bw 6))) y0 bw h))
                   ws (iota n)))))

  (define taskbar-hint "F1 apps  ·  Ctrl+Tab switch  ·  right-click desktop")

  ;; The bar's areas as it draws them, computed in the bars' place: what the
  ;; pointer finds where.
  (define (placed-taskbar-areas)
    (with-place 'bar (lambda () (taskbar-areas (taskbar-height) taskbar-hint))))

  ;; The mouse documentation's line, when this bar shows it, which it does
  ;; when there is no top bar (Genera's who line).
  (define (taskbar-doc-line) (and (zero? (topbar-height)) (mouse-doc-line)))

  ;; Draws the bar in the bars' place with the style's draw-taskbar, which
  ;; is called by name and handed what it shows.
  (define (taskbar-draw)
    (with-place 'bar
      (lambda ()
        (let ([h (taskbar-height)])
          ((world-value 'draw-taskbar) h (taskbar-areas h taskbar-hint)
                                       (launcher-open?) (taskbar-doc-line)
                                       *status-shown* taskbar-hint)))))

  ;; Draws the bar, h high, at the screen's bottom, in its areas
  ;; (taskbar-areas). open? says whether the launcher is open. doc is the
  ;; mouse documentation's line when this bar shows it (taskbar-doc-line),
  ;; or #f. status is the status segments, ((name . string or #f) ...).
  ;; hint is the hint's text.
  (define-part (draw-taskbar h areas open? doc status hint)
    (let ([w (screen-w)] [y0 (- (screen-h) h)] [lh (font-line-height 'ui)]
          [ha (assq 'hint areas)])
      (fill-box 0 y0 w h (alpha 'panel 0.94))
      (draw-line 0 (+ y0 0.5) w (+ y0 0.5) (alpha 'panel-text 0.12))
      (when ha
        (draw-text (cadr ha)
                   (+ (caddr ha)
                      (/ (- (car (cddddr ha)) (font-line-height 'ui-small)) 2))
                   hint 'panel-dim 'ui-small))
      (for-each
       (lambda (a)
         (apply
          (lambda (what x y bw h)
            (unless (eq? what 'hint)
              (let ([focused? (eq? what *focus*)]
                    [hover? (equal? *hover* (list 'surface 'taskbar what))]
                    [min? (not (visible? what))]
                    [color (app-color (window-app what))])
                (when (or focused? hover?)
                  (fill-box x (+ y 5) bw (- h 10)
                            (if focused?
                                'panel-hover
                                (alpha 'panel-hover 0.6))
                            6))
                (when focused?
                  (fill-box (+ x 12) (- (+ y h) 6) (- bw 24) 2
                            'panel-accent 1))
                (fill-circle (+ x 15) (+ y (/ h 2)) 4
                             (if min? (alpha color 0.35) color))
                (draw-text (+ x 27) (+ y (/ (- h lh) 2))
                           (text-fit (window-title what) (- bw 36) 'ui)
                           (if min? 'panel-dim 'panel-text) 'ui))))
          a))
       areas)))

  (define (taskbar-at x y)
    (and (>= y (- (screen-h) (taskbar-height)))
         (bar-at (placed-taskbar-areas) x y)))

  (define (taskbar-mouse kind what x y button clicks)
    (bar-mouse (placed-taskbar-areas) kind what x y button clicks))

  (define (taskbar-doc what)
    (cond [(window? what)
           '((L . "Focus or minimize") (M . "Close") (R . "Window menu"))]
          [(eq? what 'windows) '((L . "Choose a window"))]
          [else '()]))

  ;; Called before each frame, at time t: when this bar shows the mouse
  ;; documentation, a change in it asks for the bar to be drawn again;
  ;; nothing else on the bar changes by itself.
  (define (taskbar-frame t)
    (when (zero? (topbar-height)) (mouse-doc-frame taskbar-box)))

  (at-load
   (define-surface taskbar 10
     'draw 'taskbar-draw 'box 'taskbar-box 'at 'taskbar-at
     'mouse 'taskbar-mouse 'frame 'taskbar-frame 'doc 'taskbar-doc))
  (at-load
   (define-strip taskbar 'bottom 'taskbar-height)))
