;;; tests/units/monitor.ss — the Ticks: a bar a tick, its waits too, against
;;; the pacer's period.

;;; The Ticks: a bar a tick, its waits too, against the pacer's period.


(check "a tick's waits are phases of their own, the screen's too, so that \
        its phases add up to it; profile-tick-phases says where its time \
        went, the most first, and profile-slow-ticks the ticks that came \
        late: past one and a half periods; Monitor stacks its bars' work \
        the same way, its waits above, and its tooltip says the same"
       (let* ([real now-ns] [fake (* 1000 1000000000)]
              [clock (lambda (ns) (set! fake (+ fake ns)))]
              [win (open-window "Grower" 'size '(120 . 80) 'pos '(600 . 400))])
         ;; a step by hand, a tick of its own, as the main loop's (a
         ;; window's handlers run in an engine, where spans are untimed):
         ;; 10 ms waiting for input (the step's own), 1 of ticks, 3 of the
         ;; window's drawing, and 2 waiting for the screen in present
         (set! now-ns (lambda () fake))
         (profile-clear!)
         (with-profile-span 'step #f
           (clock 10000000)
           (with-profile-span 'tick #f (clock 1000000))
           (with-profile-span 'render #f
             (with-profile-span (window-id win) #f (clock 3000000)))
           (with-profile-span 'present #f
             (with-profile-span 'vsync-wait #f (clock 2000000))))
         (set! now-ns real)
         (let* ([seq (profile-newest-tick)]
                [phases (profile-tick-phases seq)]
                [index (lambda (p) (list-index (lambda (q) (eq? (car q) p))
                                               monitor-phases))]
                [order (monitor-bars-order (list seq))]
                ;; the tick ended at 12:00:03.400 of the day
                [zero (- (+ (* 1000 (+ (* 12 3600) 3)) 400)
                         (quotient (profile-tick-ns seq 'end) 1000000))]
                [tip (monitor-tick-tip seq zero 16666666)]
                [late (monitor-tick-tip seq zero 3000000)]
                [lines (list (format "tick ~a, ended 12:00:03.400" seq)
                             "16 ms, in time (a tick is 16.7 ms)"
                             "waiting for input 10 ms" "render 3 ms"
                             "waiting for the screen 2 ms" "ticks 1 ms"
                             "Grower 3.00 ms")])
           (close-window! win)
           (printf "  ~s\n  ~s\n" phases tip)
           (and (equal? phases '((input-wait . 10000000) (render . 3000000)
                                 (vsync-wait . 2000000) (tick . 1000000)))
                (= (profile-tick-ns seq 'ns) (apply + (map cdr phases)))
                ;; every phase of the profiler's a series of the bars'
                (= (length monitor-phases) profile-phase-count)
                (for-all (lambda (p) (assq p monitor-phases))
                         (vector->list profile-phase-names))
                ;; 16 ms, its wait for input too: late past periods of
                ;; 32/3 ms
                (member seq (profile-slow-ticks 10666666))
                (not (member seq (profile-slow-ticks 10666667)))
                (not (member seq (profile-slow-ticks 16666666)))
                ;; the work by what it spent, the waits above it
                (equal? order (map index '(render tick input-wait vsync-wait)))
                ;; the kit's tooltip shows it a line each, as it is
                (equal? (ui-tooltip-lines tip) lines)
                (equal? (cadr (ui-tooltip-lines late))
                        "16 ms, late (a tick is 3 ms)")
                (= 9 (length (ui-tooltip-lines
                              "1\n2\n3\n4\n5\n6\n7\n8\n9")))))))

(check "a bar chart flags at its top the bars 'flagged says, in chart-flag"
       (let* ([ui (make-ui)] [seen '()]
              [win (apply open-window "F" 'size '(300 . 160) 'pos '(100 . 100)
                          'ui ui
                          'draw (lambda (win w h)
                                  (ui-begin! ui)
                                  (ui-bar-chart ui 'f 0 0 w h
                                                (map (lambda (i)
                                                       (cons '((chart-1 . 5))
                                                             #f))
                                                     (iota 4))
                                                10 '() #f void
                                                'flagged (lambda (i) (= i 2)))
                                  (ui-end! ui w h))
                          (ui-handlers ui))])
         (with-test-styles
          (lambda ()
            (define-style test-flags "Test"
              'ui-draw-bar-chart
              (lambda (x y w h flags bars top rules)
                (set! seen (map cadddr bars))))
            (set-style! 'test-flags)
            (invalidate! win)
            (steps 2)))
         (close-window! win)
         (steps 1)
         (equal? seen '(#f #f #t #f))))

(check "the charts' colors are colors in every style; Settings' Colors tab \
        lists none of them, and its colors still go to hue and back"
       (let ([keys (filter (lambda (k)
                             (string-prefix? "chart-" (symbol->string k)))
                           color-keys)]
             [listed (apply append (map cdr (theme 'color-groups)))])
         (and (= (length keys) 14)
              (for-all
               (lambda (s)
                 (with-style (style-name s)
                   (lambda ()
                     (and (for-all (lambda (k)
                                     (call-with-values
                                       (lambda () (color-rgba (theme k)))
                                       (lambda (r g b a) (<= 0 a 1))))
                                   keys)
                          (for-all
                           (lambda (k)
                             (let ([c (theme k)])
                               (or (not (fixnum? c))
                                   (= c (call-with-values
                                          (lambda () (color->hsl c))
                                          color-from-hsl)))))
                           listed)))))
               *styles*)
              (not (exists (lambda (k) (memq k listed)) keys)))))
