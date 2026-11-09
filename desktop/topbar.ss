;;; topbar.ss — the bar at the top: the launcher, the focused window's
;;; title and the status segments (status.ss), redrawn once a second; or,
;;; in their place, the mouse documentation where the style shows it. A
;;; style that sets its height to 0 has none (Genera): it neither draws
;;; nor ticks.

(theme-default! 'topbar-height-min
                (theme-rule (exact (round (+ (font-line-height 'ui) 7)))))
;; (in the bars' place, as the bar is drawn: its strip and its drawing
;; agree)
(define (topbar-height)
  (with-place 'bar
    (lambda () (chrome-height 'topbar-height 'topbar-height-min))))

(define (topbar-box) (values 0 0 (screen-w) (topbar-height)))

;; The accent on the panels, or the panels' text color where the accent
;; would vanish (Genera's black accent on its black panels).
(color-default! 'panel-accent
  (theme-rule (let-values ([(ar ag ab aa) (color-rgba 'accent)]
                     [(pr pg pb pa) (color-rgba 'panel)])
          (define (lum r g b) (+ (* 0.299 r) (* 0.587 g) (* 0.114 b)))
          (theme (if (< (abs (- (lum ar ag ab) (lum pr pg pb))) 0.2)
                     'panel-text
                     'accent)))))

;; The launcher, then the focused window's title; the status segments
;; take the rest from the right.
(define-part (topbar-areas)
  (let ([h (topbar-height)] [lw (+ 30 (text-width "λ  Schevana" 'ui-bold))])
    (list (list 'launcher 0 0 lw h)
          (list 'title lw 0 (- (screen-w) lw) h))))

(define-part (draw-topbar)
  (with-place 'bar
    (lambda ()
      (let* ([w (screen-w)] [h (topbar-height)] [areas (topbar-areas)]
             [ty (/ (- h (font-line-height 'ui)) 2)]
             [gap (max 11 (round (* 0.6 (font-line-height 'ui))))]
             [dot-w (text-width "·" 'ui)]
             [l (assq 'launcher areas)] [t (assq 'title areas)])
        (fill-box 0 0 w h (alpha 'panel 0.92))
        (draw-line 0 (- h 0.5) w (- h 0.5) (alpha 'panel-text 0.12))
        (when l
          (apply (lambda (x y lw lh)
                   (when (or (equal? *hover* '(surface topbar launcher))
                             (launcher-open?))
                     (fill-box (+ x 6) (+ y 4) (- lw 6) (- lh 8) 'panel-hover
                               6))
                   (draw-text (+ x 18) (+ y ty) "λ  Schevana" 'panel-accent
                              'ui-bold))
                 (cdr l)))
        (let ([title-end
               (if t
                   (draw-text (+ (cadr t) 14) (+ (caddr t) ty)
                              (if *focus* (window-title *focus*) "Desktop")
                              'panel-text 'ui-bold)
                   0)])
          ;; status segments from the right, while they fit beside the title
          (let loop ([segs (if (theme 'mouse-doc)
                               (list (mouse-doc-text (mouse-doc)))
                               (reverse (shown-status-strings)))]
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
                  (loop (cdr segs) x0 #f))))))))))

(define (topbar-at x y)
  (and (< y (topbar-height)) (bar-at (with-place 'bar topbar-areas) x y)))

(define (topbar-mouse kind what x y button clicks)
  (bar-mouse (with-place 'bar topbar-areas) kind what x y button clicks))

(define (topbar-draw) (unless (zero? (topbar-height)) (draw-topbar)))

(define (topbar-frame t)
  (unless (zero? (topbar-height)) (mouse-doc-frame topbar-box)))

(define (topbar-doc what) (if (eq? what 'launcher) '((L . "Apps")) '()))

(define-surface topbar 20
  'draw 'topbar-draw 'box 'topbar-box 'at 'topbar-at 'mouse 'topbar-mouse
  'frame 'topbar-frame 'doc 'topbar-doc)
(define-strip topbar 'top 'topbar-height)
