;;; crash.ss — what a crashed window shows in place of its content: the
;;; handler that raised, the condition, and how to go on (for an app that
;;; lacked a permission, where to allow it). The window manager calls the
;;; part draw-crash-panel inside the window's content.

(define-part (draw-crash-panel win w h)
  (let ([err (window-error win)])
    (fill-box 0 0 w h (mix 'bg-1 'red 0.10))
    (let* ([y1 (round (+ 14 (font-line-height 'ui-bold) 5))]
           [y2 (round (+ y1 (font-line-height 'ui) 9))]
           [hint-h (round (+ (font-line-height 'ui-small) 13))]
           [hint? (> h (+ y2 hint-h 66))])
      (draw-text 16 14 "This app crashed" 'red 'ui-bold)
      (draw-text 16 y1 (format "in its '~a handler:" (car err)) 'text-dim 'ui)
      (draw-wrapped-text 16 y2 (- w 32) (- h y2 (if hint? (+ hint-h 4) 4))
                         (condition->string (cdr err)) 'text 'mono-small)
      (when hint?
        (draw-text 16 (- h hint-h)
                   (if (grant-needed? (cdr err))   ; an app's stub
                       "Settings, Permissions allows it."
                       "Click to retry.  Fix it live: (window-on! win 'draw \
                        ...)")
                   'text-faint 'ui-small)))))

;; Character-wrapped text for monospace fonts; returns the y after the text.
(define (draw-wrapped-text x y w h str color font)
  (let* ([cw (font-char-width font)] [lh (+ 2 (font-line-height font))]
         [cols (max 1 (exact (floor (/ w cw))))]
         [bottom (+ y h)])
    (let loop ([rows (wrap-lines str cols)] [y y])
      (if (or (null? rows) (> (+ y lh) bottom))
          y
          (begin
            (draw-text x y (car rows) color font)
            (loop (cdr rows) (+ y lh)))))))

(define (wrap-lines str cols)
  (apply append
         (map (lambda (line)
                (let chunk ([s line] [acc '()])
                  (if (<= (string-length s) cols)
                      (reverse (cons s acc))
                      (chunk (substring s cols (string-length s))
                             (cons (substring s 0 cols) acc)))))
              (string-split str #\newline))))
