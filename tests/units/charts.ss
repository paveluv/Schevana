;;; tests/units/charts.ss — the kit's charts.

;;; the kit's charts

(for-each close-window! (windows))
(set-style! 'mac)
(steps 2)

;; A window whose draw is (draw ui), between the kit's begin and end.
;; => (values win ui)
(define (chart-test-window draw)
  (let ([ui (make-ui)])
    (values (apply open-window "Charts" 'size '(420 . 240) 'pos '(100 . 100)
                   'draw (lambda (win w h)
                           (ui-begin! ui)
                           (draw ui)
                           (ui-end! ui w h))
                   (ui-handlers ui))
            ui)))

;; Is any pixel of x y w h in win's content not its ground's?
(define (chart-test-inked? win x y w h)
  (let-values ([(cx cy cw ch) (content-rect win)])
    (let ([ground (canvas-pixel (+ cx 2) (+ cy 2))])
      (exists (lambda (i)
                (exists (lambda (j)
                          (not (= (canvas-pixel (+ cx x i) (+ cy y j))
                                  ground)))
                        (iota (exact (ceiling h)))))
              (iota (exact (ceiling w)))))))

;; What a drawing part, replaced by a style, is given: draw's flags and
;; data as the replacement records them, and whether the plain part
;; inked x y w h. => (values inked? given)
(define (chart-test-part key draw x y w h)
  (with-test-styles
   (lambda ()
     (let-values ([(win ui) (chart-test-window draw)])
       (steps 2)
       (let ([inked? (chart-test-inked? win x y w h)] [given #f])
         (define-style test-chart "Test" key
           (lambda args (set! given (list-tail args 4))))
         (set-style! 'test-chart)
         (invalidate! win)
         (steps 2)
         (let ([still? (chart-test-inked? win x y w h)])
           (close-window! win)
           (values (and inked? (not still?)) given)))))))

(check "the bar chart: its plot right of its scale's widest label, its bars \
        whole pixels 1 to 6 wide, the newest at the plot's right; the bar \
        under the pointer it reports and marks, a press calls on-press with \
        its index; its look is the ui-draw-bar-chart part's"
       (let* ([rules '((10 . "10 ms") (20 . "20 ms"))]
              [areas (ui-bar-chart-areas 10 10 300 100 5 rules)]
              [plot (cdr (assq 'plot areas))]
              [bars (map (lambda (i)
                           (cons (list (cons 'chart-1 (+ i 1))
                                       (cons 'chart-2 1))
                                 (and (= i 2) 1)))
                         (iota 5))]
              [hover #f] [pressed #f])
         (let-values ([(win ui) (chart-test-window
                                 (lambda (ui)
                                   (set! hover
                                     (ui-bar-chart ui 'chart 10 10 300 100 bars
                                                   20 rules 0
                                                   (lambda (i)
                                                     (set! pressed i))))))]
                      [(bx bw) (ui-bar-chart-bar areas 5 3)]
                      [(lx lw) (ui-bar-chart-bar areas 5 4)])
           (steps 2)
           (let-values ([(cx cy cw ch) (content-rect win)])
             (let ([x (+ cx bx (/ bw 2))] [y (+ cy 60)])
               (inject! `(mouse-move ,x ,y))
               (steps 2)
               (let ([hovered hover])
                 (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))
                 (steps 2)
                 (close-window! win)
                 (let-values ([(inked? given)
                               (chart-test-part
                                'ui-draw-bar-chart
                                (lambda (ui)
                                  (ui-bar-chart ui 'chart 10 10 300 100 bars 20
                                                rules 0 void))
                                10 10 300 100)])
                   (printf "  ~s\n" (list plot (assq 'bar areas) hovered
                                          pressed given))
                   (and (= (car plot)
                           (exact (ceiling (+ 10 12 (text-widest (map cdr rules)
                                                                 'ui-small)))))
                        (for-all (lambda (v) (and (exact? v) (integer? v)))
                                 plot)
                        (= (cadr (assq 'bar areas)) 6)
                        (= 1 (cadr (assq 'bar (ui-bar-chart-areas
                                               10 10 300 100 1000 rules))))
                        (= (+ lx lw) (+ (car plot) (caddr plot)))
                        (= bw 6) (= (+ bx bw) lx)
                        (eqv? hovered 3) (eqv? pressed 3) inked?
                        (equal? (map caddr (cadr given))
                                '(marked #f #f #f #f))
                        (equal? (map cadr (cadr given)) '(#f #f 1 #f #f))
                        (equal? (cddr given) (list 20 rules))))))))))

(check "the bar chart's tooltip: asked only for the bar under the pointer, \
        by its index, and shown once the pointer rests"
       (let* ([rules '((10 . "10 ms"))]
              [bars (map (lambda (i) (cons (list (cons 'chart-1 5)) #f))
                         (iota 5))]
              [asked '()])
         (let-values ([(win ui) (chart-test-window
                                 (lambda (ui)
                                   (ui-bar-chart ui 'chart 10 10 300 100 bars
                                                 10 rules #f void
                                                 'tip (lambda (i)
                                                        (set! asked
                                                          (cons i asked))
                                                        (format "bar ~a" i)))))]
                      [(bx bw) (ui-bar-chart-bar (ui-bar-chart-areas
                                                  10 10 300 100 5 rules)
                                                 5 1)])
           (steps 2)
           (let ([before asked])
             (let-values ([(cx cy cw ch) (content-rect win)])
               (inject! `(mouse-move ,(+ cx bx (/ bw 2)) ,(+ cy 60)))
               (steps 2)
               (let ([r (ui-find ui '(chart 1))] [o (ui-find ui '(chart 2))])
                 (close-window! win)
                 (and (null? before)
                      (for-all (lambda (i) (= i 1)) asked)
                      (equal? (ui-region-tip r) "bar 1")
                      (not (ui-region-tip o)))))))))

(check "the sparkline: values as a line, in chart-share when its row is \
        selected; its look is the ui-draw-sparkline part's"
       (let-values ([(inked? given)
                     (chart-test-part
                      'ui-draw-sparkline
                      (lambda (ui)
                        (ui-draw-sparkline 10 10 200 30 '(selected)
                                           '(1 3 2 5)))
                      10 10 200 30)])
         (and inked? (equal? given '((selected) (1 3 2 5))))))

(check "the line chart: series over one span, each to its own most, in a \
        well; its look is the ui-draw-line-chart part's"
       (let* ([series '((chart-1 1 2 3) (chart-2 30 10 20))]
              [inked+given
               (call-with-values
                 (lambda ()
                   (chart-test-part
                    'ui-draw-line-chart
                    (lambda (ui)
                      (ui-draw-line-chart 10 10 300 80 '() series))
                    10 10 300 80))
                 list)])
         (and (car inked+given)
              (equal? (cadr inked+given) (list '() series)))))

(check "the legend: a swatch and a label a key, its size its keys' in a \
        row; its look is the ui-draw-legend part's"
       (let*-values ([(keys) '((chart-1 . "events") (chart-2 . "timers"))]
                     [(lw lh) (ui-legend-size keys)]
                     [(inked? given)
                      (chart-test-part
                       'ui-draw-legend
                       (lambda (ui) (ui-draw-legend 10 10 300 lh '() keys))
                       10 10 300 lh)])
         (and inked? (= lh (font-line-height 'ui-small))
              (= lw (+ (ui-legend-key-width "events") 12
                       (ui-legend-key-width "timers")))
              (equal? given (list '() keys)))))

;;; Streams.

(check "a stream draws a bar a moment, the newest at the right, its columns \
        stacked as asked and its strips over them, on a row of numbers a moment"
       (let* ([s (ui-stream-new 16 2 '((#f #x0000ff)))]
              [word (lambda (seq j)
                      (list-ref (if (= seq 0) '(10 5 1) '(0 20 0)) j))])
         (ui-stream-send! s 0 1 word)
         (let* ([areas (ui-stream-areas s 0 0 60 44 2 '())]
                [p (image 60 44 1
                          (lambda ()
                            (ui-draw-stream 0 0 60 44 '() s areas 2 1 37 '()
                                            '((0 . #xff0000) (1 . #x00ff00))
                                            '() #f)))]
                [red #xffff0000] [green #xff00ff00] [blue #xff0000ff]
                [well (pixel-at p 20 20)]
                [ok (and (= (pixel-at p 46 40) red)     ; moment 0, up from the
                         (= (pixel-at p 46 31) green)   ; bottom
                         (= (pixel-at p 46 20) well)
                         (= (pixel-at p 46 5) blue)     ; its strip
                         (= (pixel-at p 52 40) green)   ; moment 1, at the right
                         (= (pixel-at p 52 25) green)
                         (= (pixel-at p 52 20) well)
                         (= (pixel-at p 52 5) well)     ; no strip
                         (= (pixel-at p 55 40) well))]) ; what's clear of a bar
           (picture-free! p)
           (ui-stream-release! s)
           ok)))

(check "a stream sends only what's new, as much as it holds, and starts again \
        when the history does; numbers stay what a paint can add up, and a \
        strip's word says which of its colors, among all the strips'"
       (let* ([s (ui-stream-new 16 1 '(("a" 1 2) ("b" 3)))]
              [calls 0]
              [word (lambda (seq j)
                      (set! calls (+ calls 1))
                      (case j
                        [(0) (* 2 ui-stream-most)]
                        [(1) 0]
                        [else 1]))]
              [sent (lambda (oldest newest)
                      (set! calls 0)
                      (ui-stream-send! s oldest newest word)
                      calls)]
              [words 3])
         (let* ([two (sent 0 1)]
                [none (sent 0 1)]
                [one (sent 0 2)]
                [most (sent 0 100)]
                [row (ui-stream-row s 100)]
                [behind (sent 5 6)]
                [at (ui-stream-sent s)])
           (ui-stream-release! s)
           (and (= two (* 2 words))
                (= none 0)
                (= one words)
                (= most (* 16 words))
                (equal? row (list ui-stream-most 0 3))
                (= behind (* 2 words))
                (= at 6)
                (not (ui-stream-buffer s))))))

(check "a moment under a stream's x: the nearest of those shown, off either end"
       (let* ([s (ui-stream-new 16 1 '())]
              [areas (ui-stream-areas s 0 0 60 44 4 '())]
              [plot (cdr (assq 'plot areas))]
              [right (+ (car plot) (caddr plot))]
              [bw (cadr (assq 'bar areas))]
              [at (lambda (x) (ui-stream-seq-at areas x 100 4))])
         (and (= (at (- right 1)) 100)
              (= (at (- right bw 1)) 99)
              (= (at (+ right 50)) 100)
              (= (at -500) 97))))
