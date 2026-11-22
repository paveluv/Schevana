;;; (schevana desktop toasts) — how notifications look: a stack of toasts at
;;; the top right, over everything. The queue and its expiry are the core's
;;; (notify, *toasts*); clicks go through them.

(library (schevana desktop toasts)
  (export
    toast-boxes toast-boxes* toasts-draw draw-toasts draw-toasts* toasts-box)
  (import (chezscheme)
          (only (schevana base) at-load define-hook library-layer)
          (only (schevana core) *toasts* define-part define-surface
                desktop-rect draw-text fill-box font-line-height screen-h
                screen-w text-width with-place world-value)
          (only (schevana kits text) text-fit)
          (only (schevana kits ui) ui-draw-panel))

  (library-layer desktop)

  ;; Where each toast goes: (#(x y w h text color) ...), top to bottom,
  ;; at the top right of where windows go.
  (define-part (toast-boxes)
    (let ([h (max 34 (round (+ (font-line-height 'ui) 19)))])
      (let-values ([(dx dy dw dh) (desktop-rect)])
        (let loop ([ts *toasts*] [y (+ dy 10)] [acc '()])
          (if (null? ts)
              (reverse acc)
              (let* ([t (car ts)]
                     [text (text-fit (vector-ref t 1) (- (screen-w) 120) 'ui)]
                     [tw (+ 40 (text-width text 'ui))])
                (loop (cdr ts) (+ y h 8)
                      (cons (vector (- (+ dx dw) tw 12) y tw h text
                                    (vector-ref t 2))
                            acc))))))))

  ;; The toasts, drawn in their place by the style's draw-toasts, called by
  ;; name, which is handed their boxes.
  (define (toasts-draw)
    (with-place 'toast
      (lambda () ((world-value 'draw-toasts) (toast-boxes)))))

  ;; The toasts in their boxes (toast-boxes).
  (define-part (draw-toasts boxes)
    (let ([lh (font-line-height 'ui)])
      (for-each (lambda (b)
                  (let ([x (vector-ref b 0)] [y (vector-ref b 1)]
                        [tw (vector-ref b 2)] [h (vector-ref b 3)])
                    (ui-draw-panel x y tw h '(toast))
                    (fill-box (+ x 8) (+ y 9) 4 (- h 18) (vector-ref b 5) 2)
                    (draw-text (+ x 22) (+ y (/ (- h lh) 2))
                               (vector-ref b 4) 'text 'ui)))
                boxes)))

  ;; The whole screen while any shows: their frames are whole.
  (define (toasts-box)
    (if (pair? *toasts*) (values 0 0 (screen-w) (screen-h)) (values 0 0 0 0)))

  (at-load
   (define-surface toasts 40 'draw 'toasts-draw 'box 'toasts-box)))
