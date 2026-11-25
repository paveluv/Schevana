;;; tests/units/widgets.ss — the Widgets demo, which shows every widget and
;;; part of the kit: each of its pages, its overlays open, drawn in every
;;; style without an error.

(test-demos! 'widgets)

;; Draws win's page in each style, with the overlays page's dialog, sheet
;; and calendar open in turn, a step each; a window that crashes is noted
;; and opened again. Returns ((style page what) ...) for each crash.
(define (widgets-crashes)
  (let ([win (widgets)] [crashes '()])
    (define (draw! style page)
      (invalidate! win)
      (steps 1)
      (let ([e (window-error win)])
        (when e
          (set! crashes
            (cons (list style page (condition->string (cdr e))) crashes))
          (close-window! win)
          (set! win (widgets)))))
    (for-each
     (lambda (style)
       (set-style! style)
       (for-each (lambda (page)
                   (window-set! win 'page page)
                   (draw! style page))
                 '(controls text lists charts overlays grids scrolling boards
                   states))
       (window-set! win 'page 'overlays)
       (window-set! win 'dialog #t)
       (draw! style 'dialog)
       (window-set! win 'dialog #f)
       (window-set! win 'sheet #t)
       (draw! style 'sheet)
       (window-set! win 'sheet #f)
       (ui-state-popup-set! (window-ref win 'ui)
                            (cons 'calendar (ui-date->day '(2026 9 30))))
       (draw! style 'calendar))
     (styles))
    (close-window! win)
    (steps 1)
    (reverse crashes)))

(check "the Widgets demo draws each of its pages, and its dialog, sheet and \
        calendar, in every style without an error"
       (let* ([style (current-style)]
              [crashes (widgets-crashes)])
         (set-style! style)
         (for-each (lambda (c) (printf "  ~s\n" c)) crashes)
         (null? crashes)))

(check "on the Scrolling page no row lies under its view's scroll bar, with \
        the bar at the left (Genera's)"
       (let ([style (current-style)] [real draw-text] [rows '()])
         (set-style! 'genera)
         (let ([win (widgets)])
           (window-set! win 'page 'scrolling)
           (steps 2)
           (fluid-let ([draw-text
                        (lambda (x y s . rest)
                          (when (and (> (string-length s) 4)
                                     (string=? (substring s 0 4) "Row "))
                            (set! rows (cons (cons x y) rows)))
                          (apply real x y s rest))])
             (invalidate! win)
             (steps 2))
           (let* ([ui (window-ref win 'ui)]
                  [bars (filter values
                                (map (lambda (id)
                                       (let ([r (ui-find ui (list id 'bar))])
                                         (and r (ui-region-frame r))))
                                     '(fill-40 outer inner wide)))]
                  ;; the rows drawn over a bar or ending under it
                  [under (filter
                          (lambda (row)
                            (exists (lambda (f)
                                      (and (<= (car f) (car row))
                                           (< (car row)
                                              (+ (car f) (caddr f)))
                                           (<= (cadr f) (cdr row))
                                           (< (cdr row)
                                              (+ (cadr f) (cadddr f)))))
                                    bars))
                          rows)])
             (close-window! win)
             (set-style! style)
             (steps 1)
             (printf "  ~a rows, ~a bars, ~s under\n" (length rows)
                     (length bars) under)
             (and (pair? rows) (>= (length bars) 2) (null? under))))))
