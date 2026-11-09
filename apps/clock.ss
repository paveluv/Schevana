;;; apps/clock.ss — an analog clock. Shows a timer + 'draw.

(app-requests window draw timers)

;; The face at date d (default: now). Clock windows opened before a reload
;; still call it with w and h only.
(define draw-clock-face
  (case-lambda
    [(w h) (draw-clock-face (current-date) w h)]
    [(d w h)
     (let* ([hh (date-hour d)] [mm (date-minute d)] [ss (date-second d)]
           [digital-h (max 34 (round (+ (font-line-height 'mono) 18)))]
           [size (min w (- h digital-h))]
           [r (max 10 (- (/ size 2) 16))]
           [cx (/ w 2)]
           [cy (+ 8 (/ size 2))])
      (define (hand angle len color width)
        (draw-line cx cy (+ cx (* len (sin angle))) (- cy (* len (cos angle)))
                   color width))
      (fill-box 0 0 w h 'bg-1)
      (fill-glow cx cy (* r 1.6) (alpha 'accent 0.10))
      (fill-circle cx cy (+ r 8) 'bg-2)
      (stroke-circle cx cy (+ r 8) 'window-border 2)
      (do ([i 0 (+ i 1)]) ((= i 60))
        (let* ([a (* i (/ pi 30))] [major? (= 0 (mod i 5))]
               [r1 (if major? (- r 10) (- r 4))])
          (draw-line (+ cx (* r1 (sin a))) (- cy (* r1 (cos a)))
                     (+ cx (* r (sin a))) (- cy (* r (cos a)))
                     (if major? 'text 'text-faint) (if major? 2.5 1))))
      (hand (* (+ (mod hh 12) (/ mm 60)) (/ pi 6)) (* r 0.52) 'text 5)
      (hand (* (+ mm (/ ss 60)) (/ pi 30)) (* r 0.78) 'text-dim 3.5)
      (hand (* ss (/ pi 30)) (* r 0.86) 'red 1.5)
      (fill-circle cx cy 5 'red)
      (text-draw-centered 0 (- h digital-h) w digital-h
                          (format "~2,'0d:~2,'0d:~2,'0d" hh mm ss)
                          'text-dim 'mono))]))

(define-app (clock) "Clock"
  (let ([shown (current-date)]   ; the time on the face, taken each second
        [open? #t])
    ;; a timer at the start of each second, until the window closes
    (define (next-second! win)
      (after (- 1000 (quotient (date-nanosecond (current-date)) 1000000))
             (lambda ()
               (when open?
                 (set! shown (current-date))
                 (invalidate! win)
                 (next-second! win)))))
    (open-window "Clock"
      'size '(230 . 260)
      'min-size '(120 . 140)
      'open next-second!
      'close (lambda (win) (set! open? #f))
      'draw (lambda (win w h) (draw-clock-face shown w h)))))
