;;; toasts.ss — how notifications look: a stack of toasts at the top right,
;;; over everything. The queue and its expiry are the core's (notify,
;;; *toasts*); clicks go through them.

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

(define-part (draw-toasts)
  (with-place 'toast
    (lambda ()
      (let ([lh (font-line-height 'ui)])
        (for-each (lambda (b)
                    (let ([x (vector-ref b 0)] [y (vector-ref b 1)]
                          [tw (vector-ref b 2)] [h (vector-ref b 3)])
                      (ui-draw-panel x y tw h '(toast))
                      (fill-box (+ x 8) (+ y 9) 4 (- h 18) (vector-ref b 5) 2)
                      (draw-text (+ x 22) (+ y (/ (- h lh) 2))
                                 (vector-ref b 4) 'text 'ui)))
                  (toast-boxes))))))

;; The whole screen while any shows: their frames are whole.
(define (toasts-box)
  (if (pair? *toasts*) (values 0 0 (screen-w) (screen-h)) (values 0 0 0 0)))

(define-surface toasts 40 'draw 'draw-toasts 'box 'toasts-box)
