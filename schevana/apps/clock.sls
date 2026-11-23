;;; (schevana apps clock) — an analog clock, an example of a timer and a 'draw
;;; handler.

(library (schevana apps clock)
  (export clock)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) after alpha define-app draw-line fill-box
                fill-circle font-line-height invalidate! open-window pi
                stroke-circle)
          (only (schevana kits fill) fill-glow)
          (only (schevana kits text) text-draw-centered)
          (only (schevana kits ui) ui-icon-grid ui-icon-ink))

  (library-layer apps)

  ;; Draws the face for date d (by default, now). Clock windows opened before
  ;; a reload still call it with w and h only.
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

  ;; The app's icon: the face at ten past ten, its hours marked at the
  ;; quarters, with the second hand's red hub.
  (define (clock-draw-icon x y s flags)
    (define (ink c) (ui-icon-ink flags c))
    (define (hand angle len width)
      (draw-line 12 12 (+ 12 (* len (sin angle))) (- 12 (* len (cos angle)))
                 (ink 'text) width))
    (ui-icon-grid (x y s)
      (fill-circle 12 12 10 (ink (alpha 'yellow 0.2)))
      (stroke-circle 12 12 10 (ink 'yellow) 1.75)
      (do ([i 0 (+ i 1)]) ((= i 4))
        (let ([a (* i (/ pi 2))])
          (draw-line (+ 12 (* 6.5 (sin a))) (- 12 (* 6.5 (cos a)))
                     (+ 12 (* 8 (sin a))) (- 12 (* 8 (cos a)))
                     (ink 'yellow) 1.5)))
      (hand (* (+ 10 1/6) (/ pi 6)) 4.5 2)
      (hand (* 10 (/ pi 30)) 7 1.5)
      (fill-circle 12 12 1.25 (ink 'red))))

  (define-app (clock) "Clock" 'icon clock-draw-icon
    (let ([shown (current-date)]   ; the time on the face, read each second
          [open? #t])
      ;; sets a timer for the start of the next second, until the window closes
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
        'draw (lambda (win w h) (draw-clock-face shown w h))))))
