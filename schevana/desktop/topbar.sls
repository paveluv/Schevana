;;; (schevana desktop topbar) — the bar at the top: the launcher, the focused
;;; window's title and the status segments ((schevana desktop status)), which
;;; are redrawn once a second; or, in the status's place, the mouse
;;; documentation when the style shows it. A style that sets the bar's height
;;; to 0 has no top bar (Genera): it then draws nothing and does no work each
;;; frame. Its parts are handed what they draw, a style's parts just as the
;;; built-in ones.

(library (schevana desktop topbar)
  (export
    topbar-height topbar-box topbar-areas topbar-areas* topbar-draw draw-topbar
    draw-topbar* topbar-at topbar-mouse topbar-frame topbar-doc)
  (import (chezscheme)
          (only (schevana base) at-load define-hook library-layer)
          (only (schevana core) *focus* *hover* alpha chrome-height
                color-default! color-rgba define-part define-strip
                define-surface draw-line draw-text fill-box font-line-height
                screen-w text-width theme theme-default! theme-rule
                window-title with-place world-value)
          (only (schevana desktop bar) bar-mouse bar-at)
          (only (schevana desktop menu) launcher-open?)
          (only (schevana desktop mousedoc) mouse-doc-frame mouse-doc-line)
          (only (schevana desktop status) *status-shown*))

  (library-layer desktop)

  (at-load
   (theme-default! 'topbar-height-min
                   (theme-rule (exact (round (+ (font-line-height 'ui) 7))))))
  ;; (computed in the bars' place, as the bar is drawn, so that its strip
  ;; and its drawing agree)
  (define (topbar-height)
    (with-place 'bar
      (lambda () (chrome-height 'topbar-height 'topbar-height-min))))

  (define (topbar-box) (values 0 0 (screen-w) (topbar-height)))

  ;; The accent on the panels, or the panels' text color when the accent
  ;; would vanish against them (Genera's black accent on its black panels).
  (at-load
   (color-default! 'panel-accent
     (theme-rule (let-values ([(ar ag ab aa) (color-rgba 'accent)]
                        [(pr pg pb pa) (color-rgba 'panel)])
             (define (lum r g b) (+ (* 0.299 r) (* 0.587 g) (* 0.114 b)))
             (theme (if (< (abs (- (lum ar ag ab) (lum pr pg pb))) 0.2)
                        'panel-text
                        'accent))))))

  ;; Returns the areas of a bar h high: the launcher, then the focused
  ;; window's title, whose area runs to the right edge; the status segments
  ;; are drawn in the rest of it, from the right.
  (define-part (topbar-areas h)
    (let ([lw (+ 30 (text-width "λ  Schevana" 'ui-bold))])
      (list (list 'launcher 0 0 lw h)
            (list 'title lw 0 (- (screen-w) lw) h))))

  ;; The bar's areas as it draws them, computed in the bars' place: what the
  ;; pointer finds where.
  (define (placed-topbar-areas)
    (with-place 'bar (lambda () (topbar-areas (topbar-height)))))

  ;; Draws the bar in the bars' place with the style's draw-topbar, which is
  ;; called by name and handed what it shows.
  (define (topbar-draw)
    (unless (zero? (topbar-height))
      (with-place 'bar
        (lambda ()
          (let ([h (topbar-height)])
            ((world-value 'draw-topbar) h (topbar-areas h) (launcher-open?)
                                        (mouse-doc-line) *status-shown*))))))

  ;; Draws the bar, h high, at the screen's top, in its areas
  ;; (topbar-areas). open? says whether the launcher is open. doc is the
  ;; mouse documentation's line (mouse-doc-line), or #f; when the style shows
  ;; it ('mouse-doc), it takes the place of the status. status is the status
  ;; segments, ((name . string or #f) ...), as last read.
  (define-part (draw-topbar h areas open? doc status)
    (let* ([w (screen-w)] [ty (/ (- h (font-line-height 'ui)) 2)]
           [gap (max 11 (round (* 0.6 (font-line-height 'ui))))]
           [dot-w (text-width "·" 'ui)]
           [l (assq 'launcher areas)] [t (assq 'title areas)])
      (fill-box 0 0 w h (alpha 'panel 0.92))
      (draw-line 0 (- h 0.5) w (- h 0.5) (alpha 'panel-text 0.12))
      (when l
        (let ([x (cadr l)] [y (caddr l)] [lw (cadddr l)] [lh (car (cddddr l))])
          (when (or (equal? *hover* '(surface topbar launcher)) open?)
            (fill-box (+ x 6) (+ y 4) (- lw 6) (- lh 8) 'panel-hover 6))
          (draw-text (+ x 18) (+ y ty) "λ  Schevana" 'panel-accent 'ui-bold)))
      (let ([title-end
             (if t
                 (draw-text (+ (cadr t) 14) (+ (caddr t) ty)
                            (if *focus* (window-title *focus*) "Desktop")
                            'panel-text 'ui-bold)
                 0)])
        ;; the status segments from the right, as long as they fit beside the
        ;; title
        (let loop ([segs (if (theme 'mouse-doc)
                             (if doc (list doc) '())
                             (reverse (filter string? (map cdr status))))]
                   [x (- w 14)]
                   [first? #t])
          (unless (null? segs)
            (let* ([s (car segs)]
                   ;; room for the separator
                   [right (if first? x (- x gap dot-w gap))]
                   [x0 (- right (text-width s 'ui))])
              (when (> x0 (+ title-end gap gap))
                (unless first?
                  (draw-text (- x gap dot-w) ty "·" 'panel-dim 'ui))
                (draw-text x0 ty s 'panel-text 'ui)
                (loop (cdr segs) x0 #f))))))))

  (define (topbar-at x y)
    (and (< y (topbar-height)) (bar-at (placed-topbar-areas) x y)))

  (define (topbar-mouse kind what x y button clicks)
    (bar-mouse (placed-topbar-areas) kind what x y button clicks))

  (define (topbar-frame t)
    (unless (zero? (topbar-height)) (mouse-doc-frame topbar-box)))

  (define (topbar-doc what) (if (eq? what 'launcher) '((L . "Apps")) '()))

  (at-load
   (define-surface topbar 20
     'draw 'topbar-draw 'box 'topbar-box 'at 'topbar-at 'mouse 'topbar-mouse
     'frame 'topbar-frame 'doc 'topbar-doc))
  (at-load
   (define-strip topbar 'top 'topbar-height)))
