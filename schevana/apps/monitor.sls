;;; (schevana apps monitor) — the world, live: its windows and processes,
;;; and where its time and memory go, from the profiler ((schevana services
;;; profile)). It has four tabs: Overview (the first), Ticks, Flags and
;;; Platform.
;;;
;;; Overview, updated twice a second, shows the World's facts in a grid,
;;; the windows (a click focuses one) and the processes (each with a Kill
;;; button).
;;;
;;; The Ticks tab has three sections: Ticks, Consumers and Memory. Ticks draws
;;; one bar per tick, holding all the time since the tick before (its waits too,
;;; since a wait delays the next tick as much as work does), stacked by phase:
;;; the work at the bottom (the phase that spent the most over the graph lowest)
;;; and the waits above. A line marks the pacer's period, and a tick that came
;;; late (profile-tick-late?) is flagged at the top. Hover over a bar to see
;;; where its time went; click it to pause there. The profiler's API tells the
;;; same to a reader that can't see the screen (profile-slow-ticks,
;;; profile-tick-phases). Consumers lists each window, surface and process, and
;;; the collector, by ms per second over the last 5 seconds, with the average
;;; and longest time in a tick, the calls and the kilobytes allocated per
;;; second, and the last minute. A
;;; window's row opens to its handlers and its frame. A selected row shows its
;;; share of every bar, until a second press deselects it. A window's name
;;; focuses it, and a process's Kill kills it. Memory charts the heap, and the
;;; bytes allocated and the collector's time per second, over the seconds kept.
;;; At the top are Profiling (on or off for the whole world), Pause (this view
;;; only), Clear, and how long the history is; with profiling off, the tab says
;;; how to turn it on.
;;;
;;; Flags lists the late ticks the profiler kept. Platform says which
;;; platform this is, with a button that copies the run as a row of
;;; docs/PLATFORMS.md. All of it is drawn by the widget kit: its tabs,
;;; charts, tree, tables and labels.

(library (schevana apps monitor)
  (export monitor)
  (import (chezscheme)
          (only (schevana base) define-made library-layer string-join)
          (only (schevana core) *canvas-h* *canvas-w* *frame-ms* *last-error*
                *scale* *timers* alpha apps clipboard-set! core0-frame-ns
                current-style define-app draw-line draw-polyline fill-box
                fill-circle fill-polygon find-proc find-style
                find-window focus-window! focused-window font-char-width
                font-line-height invalidate! kill! now-ms open-window
                pacer-busy-ms pacer-period pacer-rate pacer-ticks pi
                platform-process-bytes proc-id proc-name proc-started proc-ticks
                proc-wake proc? procs style-title text-width theme uptime-ms
                window-app window-error window-frame-soon! window-h window-id
                window-state window-title window-w window-x window-y window?
                windows)
          (only (schevana kits inspect) inspect-platform-row inspect-display-hz
                inspect-display-pixels inspect-platform inspect-refresh-grid
                inspect-refresh-estimated? inspect-frames-truth)
          (only (schevana kits ui) ui-frame ui-handlers ui-stream-release!
                ui-end! ui-pad ui-draw-surface ui-begin! ui-draw-line-chart
                ui-tree ui-draw-sparkline ui-pressable! ui-table-cell-inset
                ui-draw-legend ui-bar-chart-bar ui-stream ui-stream-send!
                ui-legend-size ui-stream-count ui-region! ui-toolbar
                ui-dropdown ui-checkbox ui-tabs ui-tabs-size ui-dropdown-size
                ui-checkbox-size make-ui ui-memo! ui-memo ui-table-room
                ui-table ui-draw-cell ui-table-header-height
                ui-table-row-height ui-button ui-button-size ui-draw-label
                ui-label-size ui-stream-new ui-icon-grid ui-icon-ink)
          (only (schevana services profile) profile-clock-zero
                profile-draw-phases profile-ms-label profile-ns-label
                profile-subject-label profile-subject-labels
                profile-subject-live profile-subject? profile-tick-band-ns
                profile-tick-tip profile-window-subject? profile-flags
                profile-flag-summary *profile-flag-log* profile-flag-lines
                profile-flag-ticks-text profile-flag-before-text
                profile-flag-why profile-flag-ns profile-ns-text
                profile-flag-clock profile-second-ref profile-total-bytes
                profile-total-calls
                profile-total-longest profile-total-ticks profile-second-node-ms
                profile-tick-node-ns profile-tick-kept? profile-oldest-tick
                profile-total-parts profile-subject-of profile-history!
                profile-clear! profile-on! *profile-minutes*
                *profile-tick-seconds* profile-seconds profile-newest-tick
                profile-on? profile-why-text profile-totals profile-total-ms
                profile-total-what profile-tick-late? profile-tick-rate))

  (library-layer apps)

  ;; How many seconds the Consumers sum over.
  (define monitor-consumer-seconds 5)

  ;; How long, in seconds, a consumer or a part stays listed after it last
  ;; ran; also the span of its row's "last minute".
  (define monitor-listed-seconds 60)

  ;; A bar's width in the Ticks, in pixels.
  (define monitor-bar-px 3)

  ;; The history lengths Monitor offers: (label . seconds) for how long
  ;; ticks are kept, and (label . minutes) for how long the per-second sums
  ;; are kept.
  (define monitor-tick-choices
    '(("10 s" . 10) ("30 s" . 30) ("1 min" . 60) ("2 min" . 120)))
  (define monitor-minute-choices
    '(("1 min" . 1) ("10 min" . 10) ("30 min" . 30) ("1 h" . 60)))


  ;;; ---------------------------------------------------------------- bars
  ;;; The Ticks' bars are a stream (the kit's ui-stream): a new tick costs a
  ;;; row of numbers, and the chart one record, however many bars flow past.

  (define monitor-ring-rows 2048)

  (define (monitor-ticks-stream)
    (ui-stream-new monitor-ring-rows (length profile-draw-phases)
                   '(("late" chart-flag))))

  ;; Tooltips that explain the Ticks where they are shown. Each is made
  ;; once, since a tooltip's text is asked for at every draw.
  (define monitor-ticks-tip
    "A bar a tick: all its time since the last, stacked by phase, the work at \
     the bottom and the waits above it. A wait counts, as it delays the next \
     tick as much as work does; a bar past the top loses a wait, never work.")
  (define monitor-late-tip
    "Came late: over one and a half ticks, its wait for the screen left out. \
     Not over one: a tick that missed a refresh waits for the next.")
  (define monitor-consumers-tip
    "A row pressed shows its share of every bar; pressed again, it lets it \
     go. A heading says what its column means.")
  (define-made monitor-tick-history-tip
    (format "How long every tick is kept, at most ~a a second"
            profile-tick-rate))

  ;; A tick's row of the stream: each phase's µs, in the order of
  ;; profile-draw-phases, then 1 if it came late, else 0. Returns the procedure
  ;; ui-stream-send! calls for each number of a row.
  (define (monitor-tick-word period)
    (lambda (seq j)
      (if (< j (length profile-draw-phases))
          (quotient (profile-tick-band-ns seq j) 1000)
          (if (profile-tick-late? seq period) 1 0))))

  ;;; ---------------------------------------------------------------- data

  ;;; The Ticks: one bar for each tick kept, named by its seq and read in
  ;;; place from the profiler's ring, in whole ns.

  ;; The fixnums from a to z, z included.
  (define (monitor-range a z)
    (let loop ([z z] [acc '()])
      (if (fx< z a) acc (loop (fx- z 1) (cons z acc)))))

  ;; The phases in the order the bars stack them, for the ticks seqs. The
  ;; work phases come first, the one that spent the most over all the ticks
  ;; first (at the bottom), so that the bands run on from bar to bar; then
  ;; the waits, in the order of profile-draw-phases, so that a bar past the
  ;; graph's top loses a wait, never work. A phase that spent nothing is
  ;; left out (and so is left out of the legend). Returns indexes into
  ;; profile-draw-phases.
  (define (monitor-bars-order seqs)
    (let* ([totals (filter (lambda (t) (fx> (cdr t) 0))
                           (map (lambda (j)
                                  (cons j (fold-left
                                           (lambda (ns seq)
                                             (fx+ ns (profile-tick-band-ns
                                                      seq j)))
                                           0 seqs)))
                                (iota (length profile-draw-phases))))]
           [wait? (lambda (t)
                    (memq (car (list-ref profile-draw-phases (car t)))
                          '(input-wait vsync-wait)))])
      (map car (append (list-sort (lambda (x y) (fx> (cdr x) (cdr y)))
                                  (remp wait? totals))
                       (filter wait? totals)))))

  ;; A row's node is a subject or one of its parts, (subject part phase).
  (define (monitor-part? node) (and (pair? node) (pair? (cdr node))))

  ;; A part's label: a handler's kind, a window's frame, or a phase of a
  ;; surface or of the collector (the collector's own phase, gc, is outside
  ;; the others).
  (define (monitor-part-label subject part phase)
    (cond [part (symbol->string part)]
          [(profile-window-subject? subject) "frame"]
          [(eq? phase 'gc) "outside the phases"]
          [(eq? subject 'gc) (format "during ~a" phase)]
          [(eq? phase 'render) "draw"]
          [else (symbol->string phase)]))

  ;; What a row's node is: a window, a process, a surface or the collector;
  ;; or, for a part, a handler, a window's frame or a phase.
  (define (monitor-node-type node)
    (cond [(monitor-part? node)
           (cond [(cadr node) "handler"]
                 [(profile-window-subject? (car node)) "frame"]
                 [else "phase"])]
          [(profile-window-subject? node) "window"]
          [(pair? node) "process"]
          [(eq? node 'gc) "collector"]
          [else "surface"]))

  ;;; ---------------------------------------------------------------- the app

  ;;; ---------------------------------------------------------------- overview

  ;; A rate as a table shows it: a decimal under 100, whole from there on.
  (define (monitor-rate-text r)
    (if (< r 99.95) (format "~,1f" r) (number->string (exact (round r)))))

  ;; A count with commas between its thousands: "30,312".
  (define (monitor-count n)
    (let loop ([n n] [acc ""])
      (if (< n 1000)
          (string-append (number->string n) acc)
          (loop (quotient n 1000)
                (string-append (let ([r (remainder n 1000)])
                                 (cond [(< r 10) (format ",00~a" r)]
                                       [(< r 100) (format ",0~a" r)]
                                       [else (format ",~a" r)]))
                               acc)))))

  ;; ms as a span: "42 s", "8 min 25 s", "3 h 12 min".
  (define (monitor-span-text ms)
    (let* ([s (quotient ms 1000)] [m (quotient s 60)] [h (quotient m 60)])
      (cond [(< m 1) (format "~a s" s)]
            [(< h 1) (format "~a min ~a s" m (remainder s 60))]
            [else (format "~a h ~a min" h (remainder m 60))])))

  ;; The time from input to screen over the last 10 s, from the screen's
  ;; reports: the median, the 99th percentile and the refreshes missed.
  ;; With no input in that time, only the refreshes missed are shown; where
  ;; the screen reports on no frame (its refresh grid is estimated), there
  ;; is nothing to show.
  (define (monitor-input-text)
    (let-values ([(p50 p99 missed) (inspect-frames-truth 10000)])
      (let ([missed (format "~a refresh~a missed, the last 10 s" missed
                            (if (= missed 1) "" "es"))])
        (cond
          [p50 (format "~,1f ms, ~,1f at the 99th; ~a" (/ p50 1e6) (/ p99 1e6)
                       missed)]
          [(inspect-refresh-estimated? (inspect-refresh-grid))
           "no word from the screen"]
          [else (format "no input; ~a" missed)]))))

  ;; The World group's facts, as (label . text) pairs in reading order.
  (define (monitor-world-facts)
    (let ([hz (exact (round (/ 1e9 (core0-frame-ns))))]
          [err *last-error*])
      (append
       (list (cons "Up" (monitor-span-text (uptime-ms)))
             (cons "Screen" (format "~a × ~a at ~a%, ~a Hz" *canvas-w*
                                    *canvas-h* (exact (round (* 100 *scale*)))
                                    hz))
             (cons "Ticks"
                   (format "~a a second~a, ~a so far"
                           (if (eq? (pacer-rate) 'screen) hz (pacer-rate))
                           (if (eq? (pacer-rate) 'screen) ", the screen's" "")
                           (monitor-count (pacer-ticks))))
             (cons "Last tick" (format "~,1f ms busy" (pacer-busy-ms)))
             (cons "Last frame" (format "~,1f ms" *frame-ms*))
             (cons "Input to screen" (monitor-input-text))
             (cons "Process" (let ([b (platform-process-bytes)])
                               (if b
                                   (format "~,1f MB" (/ b 1048576.0))
                                   "not known here")))
             (cons "Heap" (format "~,1f MB, ~a collections"
                                  (/ (bytes-allocated) 1048576.0)
                                  (monitor-count (collections))))
             (cons "Style" (let ([st (find-style (current-style))])
                             (if st (style-title st) "–")))
             (cons "Apps" (format "~a" (length (apps))))
             (cons "Timers" (format "~a waiting" (length *timers*)))
             (cons "Profiling" (if (profile-on?) "on" "off")))
       (if (> (cdr err) 0)
           (list (cons "Last error"
                       (format "~a ago: ~a"
                               (monitor-span-text (- (now-ms) (cdr err)))
                               (car err))))
           '()))))

  ;; Draws a group's facts from y down, in a column at x, w wide, under the
  ;; group's title and words. Each fact is a row of a label and its text,
  ;; in two columns where they fit (the first is wider, as its texts are
  ;; longer); a last error goes across both. Returns the y below.
  (define (monitor-draw-facts x y w title words facts)
    (let* ([lh (font-line-height 'ui)]
           [err (and (pair? facts)
                     (equal? (car (car (last-pair facts))) "Last error")
                     (car (last-pair facts)))]
           [facts (if err (list-head facts (- (length facts) 1)) facts)]
           [lw (+ 16 (apply max (map (lambda (f) (text-width (car f) 'ui))
                                     (cons '("Last error") facts))))]
           [cols (if (>= w (* 2 (+ lw 220))) 2 1)]
           [colx (if (= cols 2) (* w 0.58) w)]   ; where the second starts
           [row-h (+ lh 6)]
           [y (let-values ([(gw gh) (ui-label-size '(group) title w)])
                (ui-draw-label x y w gh '(group) title)
                (ui-draw-label x y w gh '(dim right) words)
                (+ y gh 8))]
           [rows (quotient (+ (length facts) cols -1) cols)])
      (define (fact! f fx fy fw)
        (ui-draw-label fx fy lw row-h '(dim) (car f))
        (ui-draw-label (+ fx lw) fy (- fw lw 8) row-h '() (cdr f)))
      (let loop ([fs facts] [i 0])
        (unless (null? fs)
          (let ([second? (>= i rows)])
            (fact! (car fs) (if second? (+ x colx) x)
                   (+ y (* row-h (remainder i rows)))
                   (if second? (- w colx) colx)))
          (loop (cdr fs) (+ i 1))))
      (let ([y (+ y (* row-h rows))])
        (when err (fact! err x y w))
        (+ y (if err row-h 0)))))

  ;; The Platform tab's groups, each (title words facts), the facts (label
  ;; . text) pairs like the World's. They say which platform this is
  ;; (inspect-platform), so that a run on another machine can be told
  ;; apart, and which of its predicates hold.
  (define (monitor-platform-groups)
    (let* ([p (inspect-platform)]
           [of (lambda (k) (cdr (assq k p)))]
           [known (lambda (x) (if x (format "~a" x) "not known here"))]
           [display (of 'display)]
           [device (of 'gpu-device)]
           [reports (of 'reports)]
           [commit (of 'commit)])
      (list
       (list "System" ""
             (list (cons "OS" (known (or (of 'system) (of 'os))))
                   (cons "Kernel" (known (of 'kernel)))
                   (cons "CPU" (format "~a, ~a threads" (of 'cpu)
                                                        (of 'threads)))
                   (cons "Chez Scheme"
                         (format "~a, ~a" (of 'chez) (of 'chez-machine)))))
       (list "Window" ""
             (list (cons "Windowing" (format "~a" (of 'windowing)))
                   (cons "Desktop"
                         (if (of 'desktop)
                             (format "~a, as the session names it"
                                     (of 'desktop))
                             "not known here"))
                   (cons "Display"
                         (if display
                             (format "~a pixels, ~a Hz; ~a × ~a at density ~a"
                                     (inspect-display-pixels display)
                                     (inspect-display-hz display) (car display)
                                     (cadr display) (list-ref display 4))
                             "none"))
                   (cons "Scale" (format "~a" (of 'scale)))))
       (list "Drawing" ""
             (list (cons "GPU's API" (known (of 'gpu-api)))
                   (cons "Device"
                         (if (and device (car device))
                             (string-join (filter values device) ", ")
                             (format "not told by SDL ~a" (of 'sdl))))
                   (cons "Renderer" (known (of 'renderer)))
                   (cons "Presenting"
                         (format "~a, of ~a" (of 'present-mode)
                                 (if (pair? (of 'present-modes))
                                     (string-join
                                      (map symbol->string (of 'present-modes))
                                      ", ")
                                     "none")))))
       (list "Screen reports" ""
             (if reports
                 (list (cons "Source" (format "~a" (car reports)))
                       (cons "Clock"
                             (if (eq? (cadr reports) (caddr reports))
                                 (format "~a" (cadr reports))
                                 (format "~a, it says; its times fit ~a"
                                         (cadr reports) (caddr reports))))
                       (cons "Flags"
                             (if (pair? (cadddr reports))
                                 (string-join (map symbol->string
                                                   (cadddr reports))
                                              ", ")
                                 "none yet")))
                 (list (cons "Source"
                             "none here: the screen's lanes stay empty"))))
       (list "Libraries" ""
             (list (cons "SDL" (known (of 'sdl)))
                   (cons "FreeType" (of 'freetype))
                   (cons "fontconfig" (of 'fontconfig))
                   (cons "Commit"
                         (if commit
                             (format "~a (~a)" (cdr commit)
                                     (or (car commit) "detached"))
                             "not known here"))))
       (list "Predicates" "those that hold"
             (list (cons "True"
                         (string-join (map symbol->string (of 'predicates))
                                      " ")))))))

  ;; Draws the Platform tab from y down, in a column at x, w wide: its
  ;; groups, then a button that copies the run as a row of
  ;; docs/PLATFORMS.md.
  (define (monitor-draw-platform ui x y w)
    (let loop ([gs (monitor-platform-groups)] [y y])
      (if (pair? gs)
          (loop (cdr gs)
                (+ 12 (apply monitor-draw-facts x y w (car gs))))
          (let-values ([(bw bh) (ui-button-size "Copy as a row" #f)])
            (ui-button ui 'monitor-platform-copy x y bw bh "Copy as a row"
                       (lambda () (clipboard-set! (inspect-platform-row)))
                       'tip "This run as a row of docs/PLATFORMS.md's Runs")))))

  ;; Draws the Overview from y down, in a column at x, w wide: the World's
  ;; facts in a grid, then the windows (a click focuses one) and the
  ;; processes (each with a Kill button) in the kit's tables, each under a
  ;; group's heading.
  (define (monitor-draw-overview ui x y w)
    (let* ([lh (font-line-height 'ui)]
           [rh (ui-table-row-height)]
           [heading (lambda (y title words)   ; returns the y below
                      (let-values ([(gw gh) (ui-label-size '(group) title w)])
                        (ui-draw-label x y w gh '(group) title)
                        (ui-draw-label x y w gh '(dim right) words)
                        (+ y gh 8)))]
           [table-h (lambda (n most)
                      (+ (ui-table-header-height) (* rh (max 1 (min n most)))))]
           [cell (lambda (text-of)   ; draws text-of's text for row, key
                   (lambda (row key cx cy cw ch flags)
                     (ui-draw-cell cx cy cw ch '() (text-of row key))))]
           [wins (sort (lambda (a b) (< (window-id a) (window-id b)))
                       (windows))]
           [ps (procs)])
      (let ([y (+ 16 (monitor-draw-facts x y w "World" ""
                                           (monitor-world-facts)))])
        (let* ([y (heading y "Windows"
                           (format "~a open · a click focuses one"
                                   (length wins)))]
               [wh (table-h (length wins) 8)])
          (ui-table ui 'monitor-windows x y w wh
                    (let ([w (ui-table-room w)])
                      `((id "Id" ,(* w 0.08)) (title "Title" ,(* w 0.32))
                        (app "App" ,(* w 0.17)) (state "State" ,(* w 0.15))
                        (size "Size" ,(* w 0.14))
                        (position "Position" ,(* w 0.14))))
                    wins (focused-window) focus-window!
                    (cell (lambda (win key)
                            (case key
                              [(id) (number->string (window-id win))]
                              [(title) (window-title win)]
                              [(app) (format "~a" (or (window-app win) "–"))]
                              [(state) (if (window-error win)
                                           "crashed"
                                           (symbol->string
                                            (window-state win)))]
                              [(size) (format "~a × ~a" (window-w win)
                                              (window-h win))]
                              [else (format "~a, ~a" (window-x win)
                                            (window-y win))]))))
          (let* ([y (heading (+ y wh 16) "Processes"
                             (if (null? ps)
                                 "none"
                                 (format "~a running" (length ps))))])
            (if (null? ps)
                (ui-draw-label x y w lh '(hint)
                               "Try (spawn \"x\" (lambda () (let l () \
                                (l)))) in a REPL")
                (let ([ph (table-h (length ps) 4)]
                      [picked (ui-memo ui 'monitor-proc #f)])
                  (ui-table ui 'monitor-procs x y w ph
                            (let ([w (ui-table-room w)])
                              `((id "Id" ,(* w 0.08))
                                (name "Name" ,(* w 0.32))
                                (state "State" ,(* w 0.17))
                                (ticks "Ticks" ,(* w 0.15))
                                (age "Running" ,(* w 0.14))
                                (kill "" ,(* w 0.14))))
                            ps (and (memq picked ps) picked)
                            (lambda (p) (ui-memo! ui 'monitor-proc p))
                            (lambda (p key cx cy cw ch flags)
                              (if (eq? key 'kill)
                                  (ui-button ui (list 'monitor-proc-kill
                                                      (proc-id p))
                                             (+ cx 4) (+ cy 3) (- cw 8)
                                             (- ch 6) "Kill"
                                             (lambda () (kill! p))
                                             'danger #t 'quiet #t)
                                  ((cell (lambda (p key)
                                           (case key
                                             [(id) (number->string
                                                    (proc-id p))]
                                             [(name) (proc-name p)]
                                             [(state)
                                              (if (> (proc-wake p) (now-ms))
                                                  "sleeping"
                                                  "running")]
                                             [(ticks)
                                              (format "~,1fM"
                                                      (/ (proc-ticks p) 1e6))]
                                             [else (monitor-span-text
                                                    (- (now-ms)
                                                       (proc-started p)))])))
                                   p key cx cy cw ch flags)))))))))))

  ;; The app's icon: a gauge, its needle well up.
  (define (monitor-draw-icon x y s flags)
    (define (ink c) (ui-icon-ink flags c))
    (define (at r a) (cons (+ 12 (* r (cos a))) (+ 15 (* r (sin a)))))
    (let ([arc (map (lambda (i) (at 10 (* pi (+ 1 (/ i 16))))) (iota 17))])
      (ui-icon-grid (x y s)
        (fill-polygon arc (ink (alpha 'cyan 0.18)))
        (draw-polyline (append arc (list (car arc))) (ink 'cyan) 1.75)
        (for-each (lambda (k)
                    (let ([a (* pi (+ 1 (/ k 4)))])
                      (draw-line (car (at 7 a)) (cdr (at 7 a))
                                 (car (at 8.5 a)) (cdr (at 8.5 a))
                                 (ink 'cyan) 1.25)))
                  '(1 2 3))
        (draw-line 12 15 (car (at 7.5 (* pi 1.7))) (cdr (at 7.5 (* pi 1.7)))
                   (ink 'text) 1.75)
        (fill-circle 12 15 1.6 (ink 'text)))))

  (define-app (monitor) "Monitor" 'icon monitor-draw-icon
    (let ([ui (make-ui)]
          [tab 'overview]    ; the tab shown: overview, ticks, flags, platform
          [view #f]          ; the history shown: (newest tick . seconds)
          [last 0]           ; when the view last moved on (now-ms)
          [paused? #f]
          [held #f]          ; while paused, the newest tick shown (seq)
          [pinned #f]        ; the bar clicked (its tick's seq)
          [selected #f]      ; the selected row: a subject, or (subject
                             ; part phase)
          [order '(rate . down)]   ; the Consumers' sort: (key . up|down)
          [parts (make-hashtable equal-hash
                                 equal?)]   ; subject -> (part . phase)s
          [shares (make-hashtable equal-hash equal?)]   ; (seq . selected) -> ns
          [tips (make-eqv-hashtable)]                   ; seq -> text
          [drawn #f]         ; the Ticks as last drawn: (newest hover)
          [memos (make-hashtable equal-hash equal?)]   ; figures for the view
          [memo-view #f]
          [ring (monitor-ticks-stream)])   ; the Ticks' bars
      (define (move-on!)
        (set! view (cons (profile-newest-tick) (profile-seconds)))
        (set! last (now-ms)))
      ;; the newest tick kept, or the one held
      (define (newest-tick) (or held (profile-newest-tick)))
      ;; thunk's value, computed once for each view: Monitor is drawn far
      ;; more often than its view moves on.
      (define (remember key thunk)
        (unless (eq? memo-view view)
          (hashtable-clear! memos)
          (set! memo-view view))
        (or (hashtable-ref memos key #f)
            (let ([v (thunk)]) (hashtable-set! memos key v) v)))
      (define (history)
        (unless view (move-on!))
        view)
      (define (pause! seq)
        (set! held (newest-tick))
        (set! paused? #t)
        (set! pinned seq))
      (define (resume!)
        (set! paused? #f)
        (set! held #f)
        (set! pinned #f)
        (move-on!))
      (define (toolbar w)
        (let*-values
            ([(ticks-label) (format "Ticks: ~a s" *profile-tick-seconds*)]
             [(minutes-label) (format "Seconds: ~a min" *profile-minutes*)]
             [(kw kh) (ui-checkbox-size "Profiling")]
             [(pw ph) (ui-button-size "Resume" #f)]
             [(cw ch) (ui-button-size "Clear" #f)]
             [(dw dh) (ui-dropdown-size (list ticks-label minutes-label))]
             [(tw th) (ui-tabs-size '("Overview" "Ticks" "Flags" "Platform"))]
             [(none?) (not (car (history)))]   ; no tick yet
             [(items)   ; the tabs, then the Ticks' own controls
              (list
               (list tw th
                     (lambda (x y w h)
                       (ui-tabs ui 'tab x y h
                                '(("Overview" . overview) ("Ticks" . ticks)
                                  ("Flags" . flags) ("Platform" . platform))
                                tab
                                (lambda (t) (set! tab t)))))
               (list kw kh
                     (lambda (x y w h)
                       (ui-checkbox ui 'profiling x y w h "Profiling"
                                    (profile-on?)
                                    (lambda (on?) (profile-on! on?))
                                    'tip "Profile the whole world, from boot, \
                                          Monitor open or not: \
                                          (profile-on! #t)")))
               (list pw ph
                     (lambda (x y w h)
                       (ui-button ui 'pause x y w h
                                  (if paused? "Resume" "Pause")
                                  (lambda () (if paused? (resume!) (pause! #f)))
                                  'disabled (and none? (not paused?))
                                  'tip "Hold this view still; the profiler \
                                        goes on")))
               (list cw ch
                     (lambda (x y w h)
                       (ui-button ui 'clear x y w h "Clear"
                                  (lambda ()
                                    (profile-clear!)
                                    (hashtable-clear! shares)
                                    (hashtable-clear! tips)
                                    (resume!))
                                  'quiet #t 'disabled none?
                                  'tip "Forget the history")))
               (list dw dh
                     (lambda (x y w h)
                       (ui-dropdown ui 'ticks x y w h monitor-tick-choices
                                    *profile-tick-seconds*
                                    (lambda (s)
                                      (profile-history! s *profile-minutes*))
                                    'label ticks-label
                                    'tip monitor-tick-history-tip)))
               (list dw dh
                     (lambda (x y w h)
                       (ui-dropdown ui 'minutes x y w h monitor-minute-choices
                                    *profile-minutes*
                                    (lambda (m)
                                      (profile-history! *profile-tick-seconds*
                                                        m))
                                    'label minutes-label
                                    'tip "How long each second's sums are \
                                          kept"))))]
             [(items) (case tab
                        [(overview platform) (list (car items))]
                        [(flags) (list (car items) (cadddr items))]
                        [else items])])
          (ui-toolbar 0 0 w items)))
      ;; Draws a group's heading at y with words at its right, and, given an
      ;; id and a tip, a tooltip on the heading. Returns the y below.
      (define (section x y w title words . tip)
        (let-values ([(gw gh) (ui-label-size '(group) title w)])
          (ui-draw-label x y w gh '(group) title)
          (ui-draw-label x y w gh '(dim right) words)
          (when (pair? tip)
            (ui-region! ui (car tip) x y gw gh 'tip (cadr tip)))
          (+ y gh 6)))
      ;; The Consumers' rows, as a list: the totals over the last complete
      ;; seconds (at most 5 of them); the subjects listed (those that ran in
      ;; the last minute, then the live windows and processes); their
      ;; labels; and how many seconds the totals span. A subject keeps the
      ;; parts it last had more than one of, so that its row doesn't fold
      ;; up by itself.
      (define (consumers seconds)
        (define (latest n)
          (filter (lambda (t) (profile-subject? (profile-total-what t)))
                  (profile-totals (list-head seconds
                                             (min n (length seconds))))))
        (remember 'consumers
          (lambda ()
            (let* ([listed (latest monitor-listed-seconds)]
                   [spent (map profile-total-what listed)]
                   [roots (append spent
                                  (remp (lambda (s) (member s spent))
                                        (map profile-subject-of
                                             (append (reverse (windows))
                                                     (procs)))))])
              (for-each (lambda (t)
                          (when (> (length (profile-total-parts t)) 1)
                            (hashtable-set! parts (profile-total-what t)
                                            (map profile-total-what
                                                 (profile-total-parts t)))))
                        listed)
              (list (latest monitor-consumer-seconds) roots
                    (profile-subject-labels roots)
                    (max 1 (min monitor-consumer-seconds (length seconds))))))))
      (define (label-of s seconds)
        (let ([l (assoc s (caddr (consumers seconds)))])
          (if l (cdr l) (profile-subject-label s))))
      ;; Draws a bar for each tick that fits, the newest at the right, with
      ;; the phases stacked in the order of what they spent. The scale goes
      ;; up to two of the pacer's periods (a longer tick reaches the top),
      ;; with the period's line halfway up, and a tick that came late is
      ;; flagged at the top. The legend goes under the bars, in the same
      ;; order; a bar's tooltip says where its time went.
      (define (draw-ticks x y w h seconds)
        (let*-values
            ([(period) (pacer-period)]
             [(top) (* 2 period)]
             ;; in the rows' units, µs
             [(rules) (list (cons (quotient period 1000)
                                  (profile-ns-label period))
                            (cons (quotient top 1000) (profile-ns-label top)))]
             [(newest) (newest-tick)]
             [(oldest) (profile-oldest-tick)]
             ;; as many bars as fit to the right of the scale
             [(count) (ui-stream-count ring x y w h newest oldest rules
                                       monitor-bar-px)]
             [(order) (remember
                       'order
                       (lambda ()
                         (monitor-bars-order
                          (if newest
                              (monitor-range (- newest count -1) newest)
                              '()))))]
             [(keys) (append (map (lambda (j)
                                  (cdr (list-ref profile-draw-phases j)))
                                  order)
                             (if selected
                                 (list (cons 'chart-share
                                             (if (monitor-part? selected)
                                                 (apply monitor-part-label
                                                        selected)
                                                 (label-of selected seconds))))
                                 '()))]
             [(kw kh) (ui-legend-size keys)]
             [(gh) (- h kh 4)]
             [(zero) (profile-clock-zero)])
          (when newest
            (ui-stream-send! ring oldest newest (monitor-tick-word period)))
          (let ([hover
                 (ui-stream
                  ui 'monitor-ticks ring x y w gh newest oldest
                  (quotient top 1000) rules
                  (map (lambda (j)
                       (cons j (cadr (list-ref profile-draw-phases j))))
                       order)
                  monitor-bar-px
                  'tip (lambda (seq)
                         (and (profile-tick-kept? seq)
                              (tip-of seq zero period)))
                  'on-pick (lambda (seq) (pause! seq))
                  'doc '((L . "Pause here"))
                  'strip-tips (list monitor-late-tip)
                  'marked (if pinned (list pinned) '())
                  ;; the selected row's share, drawn over the bars
                  'over
                  (lambda (areas count)
                    (when (and selected newest)
                      (let-values ([(px py pw ph)
                                    (apply values (cdr (assq 'bars areas)))])
                        (do ([i 0 (+ i 1)]) ((= i count))
                          (let-values ([(bx bw) (ui-bar-chart-bar areas count
                                                                  i)])
                            (let* ([ns (share-of (+ newest (- i count -1)))]
                                   [high (div (* ph (min ns top)) top)])
                              (when (and (>= bx px) (> high 0))
                                (fill-box bx (- (+ py ph) high)
                                          (- bw (if (>= bw 3) 1 0)) high
                                          'chart-share)))))))))])
            (set! drawn (list newest hover)))
          (ui-draw-legend x (+ y gh 4) w kh '() keys)))
      ;; Tick seq's tooltip, computed once.
      (define (tip-of seq zero period)
        (or (hashtable-ref tips seq #f)
            (let ([text (profile-tick-tip seq zero period)])
              (when (> (hashtable-size tips) 64) (hashtable-clear! tips))
              (hashtable-set! tips seq text)
              text)))
      ;; What the selected row spent in tick seq, in ns, computed once.
      (define (share-of seq)
        (let ([key (cons seq selected)])
          (or (hashtable-ref shares key #f)
              (let ([ns (profile-tick-node-ns seq selected)])
                (when (> (hashtable-size shares) 4096)
                  (hashtable-clear! shares))
                (hashtable-set! shares key ns)
                ns))))
      ;; Whether the Ticks would look different now: there is a new tick,
      ;; or a bar is under the pointer (for its tooltip).
      (define (ticks-moved?)
        (or (not drawn)
            (not (eqv? (car drawn) (newest-tick)))
            (cadr drawn)))
      (define (draw-consumers x y w h seconds)
        (let* ([c (consumers seconds)]
               [totals (car c)] [roots (cadr c)] [span (cadddr c)]
               [minute (remember 'minute
                         (lambda ()
                           (reverse (list-head seconds
                                               (min monitor-listed-seconds
                                                    (length seconds))))))]
               [cw (font-char-width 'ui)]
               [kind (+ (* 2 (ui-table-cell-inset))
                        (text-width "collector" 'ui))]
               [num (max (* 8 cw) (+ 28 (text-width "calls/s" 'ui-small)))]
               [spark (* 13 cw)]
               ;; each heading's tooltip says what its column means
               [columns
                `((name "Consumer"
                        ,(max 120 (- (ui-table-room w) kind (* 5 num) spark))
                        ,(format "What ran: a row of several parts opens to \
                                  them, and each stays listed ~a s since it \
                                  last ran"
                                 monitor-listed-seconds))
                  (type "Type" ,kind
                        "A window, a process, a surface or the collector; \
                         among a row's parts, a handler, a window's frame or \
                         a phase")
                  (rate "ms/s" ,num right
                        ,(format "Milliseconds it spent a second, on average \
                                  over the last ~a s: its share of core1's \
                                  loop's time" monitor-consumer-seconds))
                  (avg "avg" ,num right
                       "Milliseconds it took in a tick, on average over \
                        the ticks it ran in")
                  (max "max" ,num right
                       ,(format "The most milliseconds it took in one tick: \
                                 past a tick's period (~a), it alone held the \
                                 next tick back"
                                (profile-ns-label (pacer-period))))
                  (calls "calls/s" ,num right
                         "How many times a second it ran: a handler called, \
                          a frame drawn, a process's turn")
                  (bytes "KB/s" ,num right
                         ,(format "Kilobytes it allocated a second, on \
                                   average over the last ~a s, the spans \
                                   inside it left out"
                                  monitor-consumer-seconds))
                  (spark "last minute" ,spark
                         "Its milliseconds each second of the last minute, \
                          the newest at the right"))])
          (define (total-of node)
            (let ([t (find (lambda (t)
                             (equal? (profile-total-what t)
                                     (if (monitor-part? node) (car node) node)))
                           totals)])
              (and t (if (monitor-part? node)
                         (find (lambda (p)
                                 (equal? (profile-total-what p)
                                         (cons (cadr node) (caddr node))))
                               (profile-total-parts t))
                         t))))
          ;; node's ms in each second of the last minute, the oldest first
          (define (minute-of node)
            (remember (list 'spark node)
                      (lambda ()
                        (map (lambda (s) (profile-second-node-ms s node))
                             minute))))
          ;; what node sorts by in column key: its label or type, or a
          ;; number (0 for none; for the last minute, its sum)
          (define (sort-value node key)
            (let ([t (total-of node)])
              (case key
                [(name) (if (monitor-part? node)
                            (apply monitor-part-label node)
                            (label-of node seconds))]
                [(type) (monitor-node-type node)]
                [(rate) (if t (/ (profile-total-ms t) span) 0)]
                [(avg) (if (and t (> (profile-total-ticks t) 0))
                           (/ (profile-total-ms t) (profile-total-ticks t))
                           0)]
                [(max) (if t (profile-total-longest t) 0)]
                [(calls) (if t (/ (profile-total-calls t) span) 0)]
                [(bytes) (if t (/ (profile-total-bytes t) span) 0)]
                [else (apply + (minute-of node))])))
          ;; siblings in the order that order names, ties as they come
          (define (sorted nodes)
            (let ([key (car order)] [down? (eq? (cdr order) 'down)]
                  [less? (if (memq (car order) '(name type)) string-ci<? <)])
              (list-sort (lambda (a b)
                           (let ([va (sort-value a key)] [vb (sort-value b
                                                                         key)])
                             (if down? (less? vb va) (less? va vb))))
                         nodes)))
          ;; a subject's parts, as (subject part phase), once it has had
          ;; more than one
          (define (children node)
            (if (monitor-part? node)
                '()
                (sorted (map (lambda (what)
                               (list node (car what) (cdr what)))
                             (hashtable-ref parts node '())))))
          (define (cell node key cx cy cw ch flags)
            (let ([t (total-of node)] [in (ui-table-cell-inset)])
              (define (number v) (ui-draw-cell cx cy cw ch '(right) v))
              (case key
                [(name)
                 (let* ([s (if (monitor-part? node) (car node) node)]
                        [label (if (monitor-part? node)
                                   (monitor-part-label s (cadr node)
                                                       (caddr node))
                                   (label-of s seconds))]
                        [live (profile-subject-live s)]
                        [id (and live (cdr s))]
                        [kill? (and live (not (monitor-part? node))
                                    (proc? live))]
                        [bw (if kill? (+ 16 (text-width "Kill" 'ui)) 0)]
                        ;; after the twisty, where the heading's label starts
                        [nx (+ cx in)]
                        [room (- cw in bw 4)])
                   (ui-draw-label nx cy room ch
                                  (if (and (pair? s) (not live))
                                      '(dim)
                                      '())
                                  label)
                   ;; a press focuses the live window, looked up by its id
                   (when (and live (not (monitor-part? node)) (window? live))
                     (ui-pressable! ui (list 'monitor-focus id)
                                    nx cy (min room (text-width label 'ui)) ch
                                    (lambda ()
                                      (let ([w (find-window id)])
                                        (when w (focus-window! w))))
                                    '()
                                    (list 'focus 'keep 'tip
                                          (format "Focus ~a" label))
                                    '((L . "Focus"))))
                   (when kill?
                     (ui-button ui (list 'monitor-kill id)
                                (+ cx cw (- bw) -4) (+ cy 3) bw (- ch 6) "Kill"
                                (lambda ()
                                  (let ([p (find-proc id)]) (when p (kill! p))))
                                'danger #t 'quiet #t)))]
                [(type) (ui-draw-cell cx cy cw ch '(dim)
                                      (monitor-node-type node))]
                [(rate) (number (profile-ms-label
                                 (if t (/ (profile-total-ms t) span) 0.0)))]
                [(avg) (number (if (and t (> (profile-total-ticks t) 0))
                                   (profile-ms-label
                                    (/ (profile-total-ms t)
                                       (profile-total-ticks t)))
                                   "–"))]
                [(max) (number (if t
                                   (profile-ms-label (profile-total-longest t))
                                   "–"))]
                [(calls) (number (if t
                                     (monitor-rate-text
                                      (/ (profile-total-calls t) span))
                                     "–"))]
                [(bytes) (number (if t
                                     (monitor-rate-text
                                      (/ (profile-total-bytes t) span 1024.0))
                                     "–"))]
                [(spark)
                 (ui-draw-sparkline (+ cx 4) (+ cy 4) (- cw 12) (- ch 8) flags
                                    (minute-of node))])))
          (ui-tree ui 'consumers x y w h columns (sorted roots) children
                   selected
                   ;; a press on the selected row deselects it
                   (lambda (node)
                     (set! selected (if (equal? node selected) #f node)))
                   cell
                   'sort order
                   ;; a number column sorts the most first, a text column
                   ;; A to Z; a second press reverses the order
                   'on-sort (lambda (key)
                              (set! order
                                    (cond [(not (eq? key (car order)))
                                           (cons key (if (memq key '(name type))
                                                         'up
                                                         'down))]
                                          [(eq? (cdr order) 'up)
                                           (cons key 'down)]
                                          [else (cons key 'up)]))))))
      (define (draw-memory x y w h seconds)
        (let*-values
            ([(mb) (lambda (b) (/ b 1048576.0))]
             [(at) (lambda (s name) (profile-second-ref s name))]
             [(latest) (and (pair? seconds) (car seconds))]
             [(keys)
              (if latest
                  (list (cons 'chart-8
                              (format "heap ~,1f MB" (mb (at latest 'heap))))
                        (cons 'chart-1
                              (format "allocated ~,1f MB/s"
                                      (mb (at latest 'allocated))))
                        (cons 'chart-7
                              (format "collector ~a ms/s, ~a collections/s"
                                      (profile-ms-label (at latest 'gc-ms))
                                      (at latest 'gcs))))
                  (list (cons 'chart-8 "heap")
                        (cons 'chart-1 "allocated a second")
                        (cons 'chart-7 "collector's time a second")))]
             [(kw kh) (ui-legend-size keys)]
             [(gh) (- h kh 6)])
          (ui-draw-line-chart
           x y w gh '()
           (remember 'memory
             (lambda ()
               (let ([shown (reverse seconds)])
                 (list (cons 'chart-8
                             (map (lambda (s) (mb (at s 'heap))) shown))
                       (cons 'chart-1
                             (map (lambda (s) (mb (at s 'allocated))) shown))
                       (cons 'chart-7
                             (map (lambda (s) (at s 'gc-ms)) shown)))))))
          (ui-draw-legend x (+ y gh 6) w kh '() keys)))
      ;; Every flag kept, the newest first: when it was, how long the tick
      ;; took, what made it late and the ticks around it; a row's tooltip
      ;; says all that is known.
      (define (draw-flags x y w h flags)
        (if (null? flags)
            (ui-draw-label x y w 0 '(hint wrap)
                           (if (profile-on?)
                               "No tick has come late since the history was \
                                cleared."
                               "Profiling is off: no tick is timed."))
            (ui-table ui 'monitor-flags x y w h
                      (let ([w (ui-table-room w)])
                        `((when "When" ,(* w 0.10)) (took "Took" ,(* w 0.06))
                          (why "Why" ,(* w 0.46)
                               "The biggest thing in it that could make it \
                                late: a wait for events past its period, the \
                                collector or someone's work; never the screen \
                                holding core0")
                          (before "Before it" ,(* w 0.16)
                                  "What core0 said last before it")
                          (ticks "Ticks about it, ms" ,(* w 0.22)
                                 "The ticks about it, in ms, this one in \
                                  brackets")))
                      flags #f (lambda (f) #f)
                      (lambda (f key cx cy cw ch cell-flags)
                        (ui-draw-cell
                         cx cy cw ch '()
                         (case key
                           [(when) (profile-flag-clock f)]
                           [(took) (profile-ns-text (profile-flag-ns f))]
                           [(why) (profile-why-text (profile-flag-why f))]
                           [(before) (profile-flag-before-text f)]
                           [else (profile-flag-ticks-text f)])))
                      'tip (lambda (f)
                             (string-join (profile-flag-lines f) "\n")))))
      (define (draw win w h)
        (ui-begin! ui)
        (ui-draw-surface 0 0 w h '(page))
        (let ([y (toolbar w)] [pad (ui-pad)])
          (cond
            [(eq? tab 'overview)
             (monitor-draw-overview ui pad (+ y 12) (- w pad pad))]
            [(eq? tab 'platform)
             (monitor-draw-platform ui pad (+ y 12) (- w pad pad))]
            [(eq? tab 'flags)
             (let* ([cw (- w pad pad)]
                    [y (section pad (+ y 4) cw "Flags"
                                (if *profile-flag-log*
                                    (format "~a; each logged to ~a"
                                            (profile-flag-summary)
                                            *profile-flag-log*)
                                    (profile-flag-summary)))])
               (draw-flags pad y cw (- h y pad) (profile-flags)))]
            [(profile-on?)
             (let* ([h* (history)] [seconds (cdr h*)]
                    [x pad] [cw (- w pad pad)]
                    [lh (font-line-height 'ui-small)]
                    [ticks-h (round (* 9 lh))]
                    [memory-h (round (* 5 lh))]
                    [rate (if (pair? seconds)
                              (profile-second-ref (car seconds) 'ticks)
                              0)]
                    [y (section x (+ y 4) cw "Ticks"
                                (format "a bar a tick, flagged if it came \
                                         late, a click pauses there; ~a \
                                         ticks/s~a"
                                        rate (if paused? ", paused" ""))
                                'monitor-ticks-heading monitor-ticks-tip)]
                    [y (begin (draw-ticks x y cw ticks-h seconds)
                              (+ y ticks-h 8))]
                    [y (section x y cw "Consumers"
                                (format "a second's average over the \
                                         last ~a s"
                                        monitor-consumer-seconds)
                                'monitor-consumers-heading
                                monitor-consumers-tip)]
                    [consumers-h (max (* 3 (ui-table-row-height))
                                      (- h y memory-h 6 8 pad
                                         (font-line-height
                                          (theme 'label-group-font))))]
                    [y (begin (draw-consumers x y cw consumers-h seconds)
                              (+ y consumers-h 8))]
                    [y (section x y cw "Memory"
                                (let ([n (length seconds)])
                                  (if (< n 120)
                                      (format "over the last ~a s" n)
                                      (format "over the last ~a min"
                                              (quotient n 60)))))])
               (draw-memory x y cw (- h y pad) seconds))]
            [else
             (ui-draw-label pad (+ y 8) (- w pad pad) 0 '(hint wrap)
                            "Profiling is off: check Profiling, or type \
                             (profile-on! #t) in a REPL, to see where the \
                             world's time and memory go.")]))
        (ui-end! ui w h))
      (apply open-window "Monitor"
             'size (cons (max 640 (+ 160 (* 67 (font-char-width 'ui))))
                         (max 600 (* 21 (ui-table-row-height))))
             'min-size '(420 . 360)
             'draw (lambda (win w h) (draw win w h))
             'close (lambda (win)
                      (ui-stream-release! ring))
             (append
              (ui-handlers ui)
              ;; while the window is seen, the Ticks redraw at every new
              ;; tick and the rest twice a second
              (list 'open (lambda (win) (window-frame-soon! win))
                    'frame (lambda (win t)
                            (window-frame-soon! win)
                            (ui-frame ui win)
                            (unless paused?
                              (when (> (- (now-ms) last) 500)
                                (move-on!)
                                (invalidate! win))
                              (when (and (eq? tab 'ticks) (profile-on?)
                                         (ticks-moved?))
                                (invalidate! win))))))))))
