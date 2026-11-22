;;; (schevana desktop bell) — the bell: (bell) flashes the screen or the
;;; focused window for 100 ms, or does nothing, as the style's bell says (none,
;;; screen, window). The REPL rings it.

(library (schevana desktop bell)
  (export
    *bell* draw-bell-flash draw-bell-flash* bell-draw bell-box bell-end! bell)
  (import (chezscheme)
          (only (schevana base) at-load define-hook define-state library-layer)
          (only (schevana core) *focus* after define-part define-surface
                invert-box now-ms request-frame! screen-h screen-w theme
                theme-default! window window-extent))

  (library-layer desktop)

  (at-load
   (theme-default! 'bell 'none))

  (define-state *bell* #f)   ; (end-ms x y w h) while the flash shows

  ;; White by the difference operator: what is there, inverted, in any
  ;; palette (the CADR complemented its screen; Medley flashes the window).
  (define-part (draw-bell-flash x y w h)
    (invert-box x y w h))

  (define (bell-draw) (when *bell* (apply draw-bell-flash (cdr *bell*))))

  (define (bell-box)
    (if *bell* (apply values (cdr *bell*)) (values 0 0 0 0)))

  ;; The flash's timer: it ends, unless a ring since made it longer, whose
  ;; own timer ends it then.
  (define (bell-end!)
    (when (and *bell* (>= (now-ms) (car *bell*)))
      (apply request-frame! (cdr *bell*))
      (set! *bell* #f)))

  (define-hook (bell)
    (let ([area (case (theme 'bell)
                  [(screen) (list 0 0 (screen-w) (screen-h))]
                  [(window) (and *focus* (call-with-values
                                           (lambda () (window-extent *focus*))
                                           list))]
                  [else #f])])
      (when area
        (set! *bell* (cons (+ (now-ms) 100) area))
        (apply request-frame! area)
        (after 100 (lambda () (bell-end!))))))

  (at-load
   (define-surface bell 60 'draw 'bell-draw 'box 'bell-box)))
