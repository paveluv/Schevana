;;; (schevana desktop arrange) — the desktop's commands over the windows, which
;;; its launcher and keys offer: cycle through them, close the focused one,
;;; tile them, cascade them. The window manager places a new window itself
;;; (place-window!); these only rearrange.

(library (schevana desktop arrange)
  (export
    cycle-windows! close-focused-window! tile-windows! cascade-windows!)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) *focus* *windows* cascade-reset! close-window!
                desktop-rect focus-window! place-window! request-frame!
                restore-window! set-geometry! unshade-window! visible?
                window-restore-set! window-state window-state-set!))

  (library-layer desktop)

  (define (cycle-windows!)
    (let ([ws (reverse *windows*)])
      (unless (null? ws)
        (focus-window! (car ws)))))

  (define (close-focused-window!) (when *focus* (close-window! *focus*)))

  (define (tile-windows!)
    (let ([ws (reverse (filter visible? *windows*))])
      (unless (null? ws)
        (let-values ([(dx dy dw dh) (desktop-rect)])
          (let* ([n (length ws)]
                 [cols (exact (ceiling (sqrt n)))]
                 [rows (exact (ceiling (/ n cols)))]
                 [gap 8]
                 [cw (/ (- dw gap) cols)]
                 [ch (/ (- dh gap) rows)])
            (let loop ([ws ws] [i 0])
              (unless (null? ws)
                (let ([win (car ws)])
                  (unshade-window! win)
                  (window-state-set! win 'normal)
                  (window-restore-set! win #f)
                  (set-geometry! win (+ dx gap (* cw (mod i cols)))
                                 (+ dy gap (* ch (quotient i cols)))
                                 (- cw gap) (- ch gap))
                  (loop (cdr ws) (+ i 1)))))))))
    (request-frame!))

  (define (cascade-windows!)
    (cascade-reset!)
    (for-each (lambda (win)
                (when (eq? (window-state win) 'maximized) (restore-window! win))
                (place-window! win #f))
              (reverse *windows*))
    (request-frame!)))
