;;; tests/units/monitor.ss — Monitor's Ticks: a bar for each tick, its
;;; waits included, against the pacer's period; then the profiler and
;;; Monitor, driven.

;;; The Ticks: a bar for each tick, its waits included, against the pacer's
;;; period.


(check "a tick's waits are phases of their own, the screen's too, so that \
        its phases add up to it; profile-tick-phases says where its time \
        went, the most first, and profile-slow-ticks the ticks that came \
        late: past one and a half periods; Monitor stacks its bars' work \
        the same way, its waits above, and its tooltip says the same"
       (let* ([real now-ns] [fake (* 1000 1000000000)]
              [clock (lambda (ns) (set! fake (+ fake ns)))]
              [win (open-window "Grower" 'size '(120 . 80) 'pos '(600 . 400))])
         ;; a step by hand, with a tick of its own, as core1's loop makes
         ;; one (a window's handlers run in an engine, where spans are
         ;; untimed): 10 ms waiting for input (the step's own), 1 ms of
         ;; ticks, 3 ms of the window's drawing, and 2 ms waiting for the
         ;; screen in render
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
                                               profile-draw-phases))]
                [order (monitor-bars-order (list seq))]
                ;; the tick ended at 12:00:03.400 of the day
                [zero (- (+ (* 1000 (+ (* 12 3600) 3)) 400)
                         (quotient (profile-tick-ns seq 'end) 1000000))]
                [tip (profile-tick-tip seq zero 16666666)]
                [late (profile-tick-tip seq zero 3000000)]
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
                ;; every phase of the profiler's is a series of the bars
                (= (length profile-draw-phases) profile-phase-count)
                (for-all (lambda (p) (assq p profile-draw-phases))
                         (vector->list profile-phase-names))
                ;; 14 ms count: the wait for input, but not the screen's
                ;; 2 ms, which aren't core1's; so it is late for periods
                ;; under 28/3 ms
                (member seq (profile-slow-ticks 9333333))
                (not (member seq (profile-slow-ticks 9333334)))
                (not (member seq (profile-slow-ticks 16666666)))
                ;; the work ordered by what it spent, the waits above it
                (equal? order (map index '(render tick input-wait vsync-wait)))
                ;; the kit's tooltip shows each line as it is
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
         (let-values ([(cx cy cw ch) (content-rect m)])   ; to its Ticks
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
             (let ([row (list-head (test-stream-row ring seq)
                                   (length profile-draw-phases))])
               (steps 3)
               (let ([crashed (window-error m)])
                 (ui-stream-release! ring)
                 (close-window! m)
                 (and (not crashed)
                      (memv ui-stream-most row)
                      (< (apply + row) (expt 2 31)))))))))

(check "Monitor's Flags tab lists every late tick, the newest first, why it \
        came late and the ticks about it, a row's tooltip all that's known"
       ;; the clock is held still except for the one late tick, so that a
       ;; step a busy machine makes late doesn't count as one
       (let* ([real now-ns] [at (real)] [held 0]
              [m (monitor)] [ui (window-ref m 'ui)])
        (fluid-let ([now-ns (lambda () (+ at held))])
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
           (with-profile-span 'step #f (set! held (* 8671932088 1000)))
           (steps 5)
           (invalidate! m)
           (steps 2)
           (let ([rows (ui-find ui '(monitor-flags row 0))]
                 [flags (profile-flags)]
                 [crashed (window-error m)])
             (close-window! m)
             (printf "  ~s\n" (profile-flag-summary))
             (and (not none) rows (not crashed) (pair? flags)
                  (equal? (profile-why-text
                           (profile-flag-why (car (reverse flags))))
                          "core1 woke 8671.9 s past its time")))))))

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
         (and (= (length keys) 23)
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

(check "Monitor says what its Ticks are and what late means, that a click \
        pauses, that the profiler runs from boot and goes on when paused, \
        and what its Flags' columns mean"
       (let* ([m (monitor)] [ui (window-ref m 'ui)]
              [press-tab!
               (lambda (id)
                 (let-values ([(cx cy cw ch) (content-rect m)])
                   (let* ([r (ui-find ui id)]
                          [x (exact (round (+ cx (ui-region-x r)
                                              (/ (ui-region-w r) 2))))]
                          [y (exact (round (+ cy (ui-region-y r)
                                              (/ (ui-region-h r) 2))))])
                     (inject! `(mouse-down ,x ,y left 1)
                              `(mouse-up ,x ,y left))))
                 (steps 3))]
              [tip (lambda (id) (ui-region-tip-text (ui-find ui id)))]
              [has? (lambda (s part) (and s (string-contains-ci? s part)))])
         (steps 3)
         (press-tab! '(tab ticks))
         (let ([ticks (and (has? (tip 'monitor-ticks-heading) "a wait counts")
                           (has? (tip '(monitor-ticks strip 0))
                                 "one and a half")
                           (assq 'L (ui-region-doc
                                     (ui-find ui '(monitor-ticks))))
                           (has? (tip 'monitor-consumers-heading)
                                 "pressed again")
                           (has? (tip 'profiling) "from boot")
                           (has? (tip 'pause) "profiler goes on"))])
           (press-tab! '(tab flags))
           (let ([flags (and (has? (tip '(monitor-flags header why))
                                   "the collector")
                             (has? (tip '(monitor-flags header ticks))
                                   "brackets"))])
             (close-window! m)
             (and ticks flags)))))

;;; The profiler and Monitor, driven: the profiler is on at boot and
;;; collects with Monitor closed; Monitor's graphs, tables, rows and Kill.

;; Clicks Monitor's region id, then steps once to show what it changed.
(define (monitor-test-click! win id)
  (test-click! win id)
  (steps 1))

;; The profiler is on at boot and collects with Monitor closed. Monitor
;; draws its graphs; a window's name focuses the window, and a process's
;; Kill kills the process. The Profiling checkbox turns the profiler off,
;; and Monitor still lists the windows and processes in tables, where a
;; window's row focuses it and a process's Kill kills it; then the checkbox
;; turns the profiler on again.
(let ([m (find-window 'monitor)]) (when m (close-window! m)))
(steps 2)
(check "profiling is on at boot, and collects with Monitor closed"
       (let ([s (car (profile-ticks))])
         (steps 1)
         (and (profile-on?) (not (find-window 'monitor))
              (not (eqv? s (car (profile-ticks)))))))
(let* ([target (open-window "Target"   ; drawn at every step, slowly: a top row
                 'size '(200 . 100) 'pos '(1000 . 420)
                 'open window-frame-soon!
                 'frame (lambda (win at)
                          (window-frame-soon! win)
                          (invalidate! win))
                 'draw (lambda (win w h)
                         (let ([t (+ (real-time) 2)])
                           (let loop () (when (< (real-time) t) (loop))))))]
       [busy (lambda () (spawn "monitored" (lambda () (let loop () (loop)))))]
       [p (busy)]
       [m (monitor)]
       [ui (window-ref m 'ui)]
       [bars (lambda ()
               (filter (lambda (r)
                         (let ([id (ui-region-id r)])
                           ;; the bars, not the strip's label
                           (and (pair? id) (eq? (car id) 'monitor-ticks)
                                (not (and (pair? (cdr id))
                                          (eq? (cadr id) 'strip))))))
                       (ui-regions ui)))]
       [row (lambda (table x xs)   ; x's row in the table of xs, by id
              (list table 'row (list-index (lambda (y) (eq? y x)) xs)))]
       [window-row (lambda ()
                     (row 'monitor-windows target
                          (sort (lambda (a b) (< (window-id a) (window-id b)))
                                (windows))))])
  (move-window! m 20 40)
  (focus-window! m)
  (steps 2)
  (check "Monitor opens on its Overview: the windows and processes in \
          tables, no bars"
         (and (null? (bars)) (ui-find ui (window-row))
              (ui-find ui (row 'monitor-procs p (procs)))))
  (monitor-test-click! m '(tab ticks))
  ;; the Consumers sum up whole seconds: wait until one with Target in it
  ;; is done, and Monitor's view has moved on (twice a second) since
  (test-wait 10000
             (lambda ()
               (and (pair? (bars))
                    (ui-find ui (list 'monitor-kill (proc-id p)))
                    (ui-find ui (list 'monitor-focus (window-id target)))
                    (> (vector-length (ui-memo ui '(consumers rows) '#()))
                       2))))
  (steps 1)
  (test-png-write-screen (string-append out-dir "/monitor.png"))
  (check "Monitor draws its graphs: a bar a tick, a row a consumer"
         (and (not (window-error m)) (pair? (bars))
              (ui-find ui (list 'monitor-kill (proc-id p)))
              (ui-find ui (list 'monitor-focus (window-id target)))))
  ;; the Consumers sorted by a heading: by name, by name the other way, and
  ;; back to ms/s, the most first. Monitor's view moves on twice a second,
  ;; and its rows change with it (a consumer's first second, a window
  ;; opened), so Monitor is paused to hold the one view all three orders
  ;; are of
  (monitor-test-click! m 'pause)
  (let ([order (lambda (nodes)   ; the same nodes, in a fixed order
                 (list-sort string<? (map (lambda (n) (format "~s" n))
                                          nodes)))]
        [roots (lambda ()
                 (map ui-tree-row-node
                      (filter (lambda (r) (= 0 (ui-tree-row-depth r)))
                              (vector->list
                               (ui-memo ui '(consumers rows) '#())))))])
    (let ([by-rate (roots)])
      (monitor-test-click! m '(consumers header name))
      (let ([by-name (roots)])
        (monitor-test-click! m '(consumers header name))
        (let ([by-name-down (roots)])
          (monitor-test-click! m '(consumers header rate))
          (check "a Consumers heading sorts its rows by it, again the other \
                  way; the same rows each time"
                 (and (> (length by-rate) 2)
                      (not (equal? by-name by-name-down))
                      (equal? (reverse by-name) by-name-down)
                      (equal? (order by-rate) (order by-name))
                      (equal? (order by-rate) (order (roots)))))))))
  (monitor-test-click! m 'pause)
  ;; The rows drawn selected at a draw of Monitor's, as the y of each.
  (let ([selected-rows
         (lambda ()
           (let ([ys '()] [real ui-draw-highlight-over])
             (fluid-let ([ui-draw-highlight-over
                          (lambda (x y w h flags)
                            (set! ys (cons y ys))
                            (real x y w h flags))])
               (invalidate! m)
               (steps 1))
             ys))]
        ;; the Consumers' row drawn at y, as the last draw numbered it
        [row-at (lambda (y)
                  (let loop ([k 0])
                    (let ([r (ui-find ui (list 'consumers 'row k))])
                      (cond [(not r) #f]
                            [(= (ui-region-y r) y) k]
                            [else (loop (+ k 1))]))))])
    (monitor-test-click! m '(consumers row 0))
    ;; Monitor's view moves on twice a second, and its rows sort again by
    ;; what they spent, so the second press goes to the row drawn
    ;; selected, wherever it is by then, not to the first row again
    (let* ([chosen (selected-rows)]
           [k (and (pair? chosen) (row-at (car chosen)))])
      (when k (monitor-test-click! m (list 'consumers 'row k)))
      (let ([let-go (selected-rows)])
        (check (format "a press selects a Consumers row, and a second lets it \
                        go (~a, then ~a drawn selected)"
                       (length chosen) (length let-go))
               (and (= (length chosen) 1) k (null? let-go))))))
  (check "a Consumers heading says what its column means"
         (let ([r (ui-find ui '(consumers header avg))])
           (and r (string? (ui-region-tip-text r))
                (string-contains-ci? (ui-region-tip-text r) "average"))))
  (check "Consumers has what each allocated a second, and its heading says \
          so"
         (let ([r (ui-find ui '(consumers header bytes))])
           (and r (string? (ui-region-tip-text r))
                (string-contains-ci? (ui-region-tip-text r) "allocated"))))
  ;; the pointer rests on the newest bar, whose tooltip says what it spent
  (let ([r (car (bars))])
    (let-values ([(cx cy cw ch) (content-rect m)])
      (inject! `(mouse-move ,(+ cx (ui-region-x r) (ui-region-w r) -2)
                            ,(+ cy (ui-region-y r)
                                (quotient (ui-region-h r) 2)))))
    ;; wait until it has rested there for a tooltip's wait
    (test-wait 5000 (lambda ()
                      (< (+ (car (ui-state-rest ui)) ui-tip-ms 100)
                         (now-ms))))
    (test-png-write-screen (string-append out-dir "/monitor-tip.png"))
    (let ([tip (let ([rs (bars)])
                 (and (pair? rs) (ui-region-tip-text (car rs))))])
      (printf "  ~s\n" tip)
      (check "hovering a bar of Monitor's Ticks shows its tooltip: its \
              tick, whether it came late, and its phases"
             (and (string? tip)
                  (string-contains-ci? tip "tick ")
                  (string-contains-ci? tip "(a tick is ")
                  (< (+ (car (ui-state-rest ui)) ui-tip-ms) (now-ms))))))
  (monitor-test-click! m (list 'monitor-focus (window-id target)))
  (check "a window's name in Monitor focuses it" (eq? (focused-window) target))
  (focus-window! m)
  (steps 2)
  (monitor-test-click! m (list 'monitor-kill (proc-id p)))
  (check "a process's Kill in Monitor kills it" (not (memq p (procs))))
  (monitor-test-click! m 'profiling)
  (let ([p (busy)])
    (steps 2)
    (check "Monitor's Profiling turns it off: no bars"
           (and (not (profile-on?)) (not *profile-span*) (null? (bars))))
    (monitor-test-click! m '(tab overview))
    (check "its Overview lists the windows and processes in tables still \
            (a new one by its next view: twice a second)"
           (and (ui-find ui (window-row))
                (test-wait 10000
                           (lambda ()
                             (ui-find ui (row 'monitor-procs p (procs)))))))
    (monitor-test-click! m (window-row))
    (check "where a window's row focuses it" (eq? (focused-window) target))
    (focus-window! m)
    (steps 2)
    (monitor-test-click! m (row 'monitor-procs p (procs)))
    (check "a process's row only selects it" (memq p (procs)))
    (monitor-test-click! m (list 'monitor-proc-kill (proc-id p)))
    (check "and its Kill kills it" (not (memq p (procs)))))
  (monitor-test-click! m '(tab ticks))
  (monitor-test-click! m 'profiling)
  (test-wait 10000 (lambda () (pair? (bars))))
  (check "and on again: the bars come back"
         (and (profile-on?) (pair? *profile-span*)
              (pair? (bars)) (not (window-error m))))
  (close-window! m)
  (close-window! target)
  (steps 2))

;; Monitor's Input to screen: with no word from the screen; with reports
;; but no input on any frame (a hands-off run); and with input. The test
;; writes the newest frame's report as core0 would.
(begin
  (request-frame!)
  (steps 2)
  (let* ([i (- *frame-ring-n* 1)]
         [n (inspect-frame-ref i 6)]
         [at (present-at n)]
         [r *present-ring*]
         [saved (map (lambda (k) (fxvector-ref r (+ at k)))
                     (iota present-words))]
         [input (inspect-frame-ref i 7)]
         [publish (inspect-frame-at i 'publish)]
         [silent (monitor-input-text)])
    (fxvector-set! r at n)
    (fxvector-set! r (+ at 1) 1)
    (fxvector-set! r (+ at 2) publish)
    (fxvector-set! r (+ at 3) (+ publish 8000000))
    (fxvector-set! r (+ at 4) 16666667)
    (fxvector-set! r (+ at 5) 1000)
    (frame-ring-set! n 7 0)
    (let ([hands-off (monitor-input-text)])
      (frame-ring-set! n 7 (- publish 4000000))
      (let ([driven (monitor-input-text)])
        (frame-ring-set! n 7 input)
        (for-each (lambda (k v) (fxvector-set! r (+ at k) v))
                  (iota present-words) saved)
        (check (format "Input to screen has no word from a screen that \
                        reports on no frame; from one that does, the \
                        refreshes missed, with or without input in the \
                        last 10 s (~s; ~s; ~s)" silent hands-off driven)
               (and (string=? silent "no word from the screen")
                    (string=? hands-off
                              "no input; 0 refreshes missed, the last 10 s")
                    (string=? driven
                              "12.0 ms, 12.0 at the 99th; 0 refreshes \
                               missed, the last 10 s")))))))
