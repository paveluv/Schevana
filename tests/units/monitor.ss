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
         ;; a step by hand, a tick of its own, as core1's loop's (a
         ;; window's handlers run in an engine, where spans are untimed):
         ;; 10 ms waiting for input (the step's own), 1 of ticks, 3 of the
         ;; window's drawing, and 2 waiting for the screen in render
         (set! now-ns (lambda () fake))
         (profile-clear!)
         (with-profile-span 'step #f
           (clock 10000000)
           (with-profile-span 'tick #f (clock 1000000))
           (with-profile-span 'render #f
             (with-profile-span (window-id win) #f (clock 3000000))
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
                ;; 16 ms, its wait for input too, but the screen's 2 ms,
                ;; which aren't core1's: late past periods of 28/3 ms
                (member seq (profile-slow-ticks 9333333))
                (not (member seq (profile-slow-ticks 9333334)))
                (not (member seq (profile-slow-ticks 16666666)))
                ;; the work by what it spent, the waits above it
                (equal? order (map index '(render tick input-wait vsync-wait)))
                ;; the kit's tooltip shows it a line each, as it is
                (equal? (ui-tooltip-lines tip) lines)
                (equal? (cadr (ui-tooltip-lines late))
                        "16 ms, late (a tick is 3 ms)")
                (= 9 (length (ui-tooltip-lines
                              "1\n2\n3\n4\n5\n6\n7\n8\n9")))))))

(check "a tick hours long, the screen holding core1 all that time, is a bar \
        like any other: Monitor's Ticks go on drawing, on rows the paint can \
        add up in 32 bits"
       (let* ([real now-ns] [held 0]
              [m (monitor)] [ui (window-ref m 'ui)]
              [ring (monitor-ticks-stream)])
         (steps 3)
         (let-values ([(cx cy cw ch) (content-rect m)])   ; its Ticks
           (let* ([r (ui-find ui '(tab ticks))]
                  [x (exact (round (+ cx (ui-region-x r)
                                      (/ (ui-region-w r) 2))))]
                  [y (exact (round (+ cy (ui-region-y r)
                                      (/ (ui-region-h r) 2))))])
             (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))))
         (steps 3)
         (fluid-let ([now-ns (lambda () (+ (real) held))])
           (with-profile-span 'step #f
             (with-profile-span 'vsync-wait #f
               (set! held (* 8671932088 1000))))
           (let ([seq (profile-newest-tick)])
             (ui-stream-send! ring seq seq (monitor-tick-word (pacer-period)))
             (let ([row (list-head (ui-stream-row ring seq)
                                   (length monitor-phases))])
               (steps 3)
               (let ([crashed (window-error m)])
                 (ui-stream-release! ring)
                 (close-window! m)
                 (and (not crashed)
                      (memv ui-stream-most row)
                      (< (apply + row) (expt 2 31)))))))))

(check "Monitor's Flags tab lists every late tick, the newest first, why it \
        came late and the ticks about it, a row's tooltip all that's known"
       (let* ([real now-ns] [held 0]
              [m (monitor)] [ui (window-ref m 'ui)])
         (profile-clear!)
         (steps 3)
         (let-values ([(cx cy cw ch) (content-rect m)])
           (let* ([r (ui-find ui '(tab flags))]
                  [x (exact (round (+ cx (ui-region-x r)
                                      (/ (ui-region-w r) 2))))]
                  [y (exact (round (+ cy (ui-region-y r)
                                      (/ (ui-region-h r) 2))))])
             (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))))
         (steps 3)
         (let ([none (ui-find ui '(monitor-flags row 0))])
           (fluid-let ([now-ns (lambda () (+ (real) held))])
             (with-profile-span 'step #f (set! held (* 8671932088 1000)))
             (steps 5)
             (invalidate! m)
             (steps 2))
           (let ([rows (ui-find ui '(monitor-flags row 0))]
                 [flags (profile-flags)]
                 [crashed (window-error m)])
             (close-window! m)
             (printf "  ~s\n" (profile-flag-summary))
             (and (not none) rows (not crashed) (pair? flags)
                  (equal? (profile-why-text
                           (profile-flag-why (car (reverse flags))))
                          "core1 woke 8671.9 s past its time"))))))

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
         (and (= (length keys) 15)
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
