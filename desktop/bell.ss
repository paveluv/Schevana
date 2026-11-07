;;; bell.ss — the bell: (bell) flashes the screen or the focused window
;;; for 100 ms, or does nothing, as the style's bell says (none, screen,
;;; window). The REPL rings it.

(theme-default! 'bell 'none)

(defvar *bell* #f)   ; (end-ms x y w h) while the flash shows

(define (bell)
  (let ([area (case (theme 'bell)
                [(screen) (list 0 0 (screen-w) (screen-h))]
                [(window) (and *focus* (call-with-values
                                         (lambda () (window-extent *focus*))
                                         list))]
                [else #f])])
    (when area
      (set! *bell* (cons (+ (now-ms) 100) area))
      (apply request-frame! area))))

;; White by the difference operator: what is there, inverted, in any
;; palette (the CADR complemented its screen; Medley flashes the window).
(define-part (draw-bell-flash x y w h)
  (invert-box x y w h))

(define (bell-draw) (when *bell* (apply draw-bell-flash (cdr *bell*))))

(define (bell-box)
  (if *bell* (apply values (cdr *bell*)) (values 0 0 0 0)))

(define (bell-tick)
  (when (and *bell* (>= (now-ms) (car *bell*)))
    (apply request-frame! (cdr *bell*))
    (set! *bell* #f)))

(define-surface bell 60 'draw 'bell-draw 'box 'bell-box 'tick 'bell-tick)
