;;; (demo widgets charts) — the Widgets demo's page of charts: stacked
;;; bars, a stream of bars kept on the GPU, lines, a sparkline, a legend of
;;; every chart color, and avatars.

(library (demo widgets charts)
  (export widgets-charts-page widgets-stream-new)
  (import (chezscheme)
          (schevana core)
          (schevana kits ui)
          (demo widgets layout))

  ;; Returns the i-th of a made-up series of numbers from 0 to 99: the same
  ;; for the same i and seed, never random.
  (define (widgets-number i seed)
    (mod (+ 30 (* 23 (mod (* (+ i seed) 37) 11)) (* 7 (mod i 5))) 100))

  ;; The stream the page shows: 64 moments of two numbers each, and a strip
  ;; that flags some of them. The window keeps it, and lets it go when it
  ;; closes (ui-stream-release!).
  (define (widgets-stream-new)
    (ui-stream-new 64 2 '(("flag" chart-flag))))

  ;; Returns (values right bottom) of the page drawn from (x, y), w wide.
  (define (widgets-charts-page ui win x y w)
    (let* ([gap (ui-gap)] [cw (min w 560)]
           [lh (font-line-height 'ui-small)]
           [get (lambda (key default) (window-ref win key default))]
           [y (widgets-heading x y w "Bar chart")]
           [y (widgets-note x y cw
                "A press on a bar marks it; a bar under the pointer has a \
                 tooltip; the tallest are flagged at the top.")]
           [y (let ([bars (map (lambda (i)
                                 (cons (list (cons 'chart-1
                                                   (widgets-number i 1))
                                             (cons 'chart-3
                                                   (quotient
                                                    (widgets-number i 4) 2)))
                                       (and (= 0 (mod i 7))
                                            (widgets-number i 2))))
                               (iota 72))])
                (ui-bar-chart ui 'bars x y cw 140 bars 160
                              '((80 . "80") (160 . "160"))
                              (get 'bar #f)
                              (lambda (i) ((widgets-keep win 'bar) i))
                              'tip (lambda (i) (format "Bar ~a" i))
                              'flagged (lambda (i)
                                         (> (+ (widgets-number i 1)
                                               (quotient (widgets-number i 4)
                                                         2))
                                            120)))
                (+ y 140 gap))]
           [y (widgets-heading x y w "Stream")]
           [y (let ([s (window-ref win 'stream)])
                (ui-stream-send! s 0 63
                                 (lambda (seq j)
                                   (case j
                                     [(0) (widgets-number seq 3)]
                                     [(1) (quotient (widgets-number seq 5) 2)]
                                     [else (if (= 0 (mod seq 9)) 1 0)])))
                (ui-stream ui 'stream s x y cw 140 63 0 160
                           '((80 . "80") (160 . "160"))
                           '((0 . chart-2) (1 . chart-4)) #f
                           'fit #t
                           'tip (lambda (seq) (format "Moment ~a" seq))
                           'strip-tips '("Moments flagged in the strip")
                           'marked (list (get 'moment 60))
                           'on-pick (widgets-keep win 'moment))
                (+ y 140 gap))]
           [y (widgets-heading x y w "Lines, a sparkline and a legend")]
           [y (begin
                (ui-draw-line-chart x y cw 120 '()
                  (list (cons 'chart-1 (map (lambda (i) (widgets-number i 1))
                                            (iota 24)))
                        (cons 'chart-3 (map (lambda (i) (widgets-number i 6))
                                            (iota 24)))
                        (cons 'chart-5 (map (lambda (i) (* 2 i)) (iota 24)))))
                (+ y 120 4))]
           [y (begin
                (ui-draw-legend x y cw lh '()
                  '((chart-1 . "Reads") (chart-3 . "Writes")
                    (chart-5 . "Waits")))
                (+ y lh gap))]
           [y (let ([points (map (lambda (i) (widgets-number i 8)) (iota 20))])
                (ui-draw-sparkline x y 160 30 '() points)
                (ui-draw-sparkline (+ x 160 gap) y 160 30 '(selected) points)
                (ui-draw-label (+ x 320 gap gap) y 160 30 '(hint)
                               "Plain, and selected")
                (+ y 30 gap))]
           [y (widgets-heading x y w "Every chart color")]
           [y (let ([legend (lambda (y keys)
                              (ui-draw-legend x y cw lh '() keys)
                              (+ y lh 6))])
                (+ gap
                   (fold-left legend y
                     '(((chart-1 . "chart-1")
                        (chart-2 . "chart-2")
                        (chart-3 . "chart-3")
                        (chart-4 . "chart-4")
                        (chart-5 . "chart-5"))
                       ((chart-6 . "chart-6")
                        (chart-7 . "chart-7")
                        (chart-8 . "chart-8")
                        (chart-muted-1 . "chart-muted-1")
                        (chart-muted-2 . "chart-muted-2"))
                       ((chart-mark . "chart-mark")
                        (chart-share . "chart-share")
                        (chart-rule . "chart-rule")
                        (chart-flag . "chart-flag")
                        (chart-ok . "chart-ok"))
                       ((chart-level-1 . "chart-level-1")
                        (chart-level-2 . "2")
                        (chart-level-3 . "3")
                        (chart-level-4 . "4")
                        (chart-level-5 . "5")
                        (chart-level-6 . "6")
                        (chart-level-7 . "7")
                        (chart-level-8 . "8"))))))]
           [y (widgets-heading x y w "Avatars")]
           [y (let loop ([names '("Ada Lovelace" "Alan Turing" "Grace Hopper"
                                  "John McCarthy" "Claude")]
                         [ax x] [bottom y])
                (if (null? names)
                    (+ bottom gap)
                    (let-values ([(aw ah) (ui-avatar-size '() (car names))])
                      (ui-draw-avatar ax y aw ah '() (car names))
                      (loop (cdr names) (+ ax aw gap) (max bottom (+ y ah))))))]
           [y (let-values ([(aw ah) (ui-avatar-size '(named) "Grace Hopper")])
                (ui-draw-avatar x y aw ah '(named) "Grace Hopper")
                (ui-draw-label (+ x aw 6) y 200 (max ah lh) '()
                               "Grace Hopper, named beside it")
                (+ y (max ah lh) gap))])
      (values (+ x w) y))))
