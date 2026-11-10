;;; apps/monitor.ss — the world, live: its windows and processes, and
;;; where its time and memory go, from the profiler (services/profile.ss).
;;; Two tabs: Overview, the first, and Ticks.
;;;
;;; Overview, twice a second: the World's facts in a grid, the windows (a
;;; click focuses one) and the processes (each with its Kill).
;;;
;;; Ticks: a bar a tick, all its time since the last (its waits too: a
;;; wait delays the next tick as much as work), stacked by phase, the
;;; work's at the bottom (the one that spent the most over the graph
;;; lowest) and the waits above, against a line at the pacer's period, a
;;; tick that came late (profile-tick-late?) flagged at the top; hover a
;;; bar for where its time went, click it to pause there. The profiler's
;;; API tells the same (profile-slow-ticks, profile-tick-phases), for a
;;; reader without eyes. Consumers: each window, surface and process, and
;;; the collector, by ms a second over the last 5 seconds, with the
;;; average and longest a tick, calls a second and the last minute; a
;;; window's row opens to its handlers and frame; a row selected shows
;;; its share of every bar, until a second press lets it go; a window's
;;; name focuses it, a process's Kill kills it. Memory: the heap, the bytes
;;; allocated and the collector's time a second, over the seconds kept. At
;;; the top: Profiling (on or off for the whole world), Pause (this view
;;; only), Clear, and how long the history is; with profiling off, how to
;;; turn it on. All of it is drawn by the widget kit: its tabs, charts, tree,
;;; tables and labels.

;; A bar's phases, all the profiler's (profile-phase-names), so that they
;; add up to the tick: (phase color . label), each a series of the kit's
;; charts, the two waits in its muted colors.
(define monitor-phases
  '((event chart-1 . "events")
    (timers chart-2 . "timers")
    (procs chart-3 . "processes")
    (tick chart-4 . "ticks")
    (render chart-5 . "render")
    (gc chart-7 . "collector")
    (other chart-8 . "other")
    (input-wait chart-muted-1 . "waiting for input")
    (vsync-wait chart-muted-2 . "waiting for the screen")))

;; How long the Consumers sum, in seconds.
(define monitor-consumer-seconds 5)

;; How long a consumer or a part stays listed since it last ran, in seconds:
;; the last minute its line shows.
(define monitor-listed-seconds 60)

;; A bar's width in the Ticks, pixels.
(define monitor-bar-px 3)

;; The history's lengths Monitor offers: (label . seconds of ticks), and
;; (label . minutes of seconds).
(define monitor-tick-choices
  '(("10 s" . 10) ("30 s" . 30) ("1 min" . 60) ("2 min" . 120)))
(define monitor-minute-choices
  '(("1 min" . 1) ("10 min" . 10) ("30 min" . 30) ("1 h" . 60)))

(define (monitor-ms ms)
  (if (< ms 9.995) (format "~,2f" ms) (format "~,1f" ms)))


;;; ------------------------------------------------------------------ bars
;;; The Ticks' bars are a stream: a new tick is a row of numbers, and nothing
;;; is recorded for the rest, however many bars flow past.

(define monitor-ring-rows 2048)

(define (monitor-ticks-stream)
  (ui-stream-new monitor-ring-rows (length monitor-phases) '((#f chart-flag))))

;; A tick's row: each phase's µs, as monitor-phases has them, then whether it
;; came late.
(define (monitor-tick-word period)
  (lambda (seq j)
    (if (< j (length monitor-phases))
        (quotient (monitor-tick-phase-ns seq j) 1000)
        (if (profile-tick-late? seq period) 1 0))))

;;; ------------------------------------------------------------------ data

;; ns as words: "250 ms", "1.6 ms", "3.2 s", rounded to a tenth, in
;; integers.
(define (monitor-ns-text ns)
  (let* ([s? (>= ns 1000000000)]
         [t (quotient (+ ns (if s? 50000000 50000)) (if s? 100000000 100000))])
    (format "~a~a ~a" (quotient t 10)
            (if (zero? (remainder t 10)) "" (format ".~a" (remainder t 10)))
            (if s? "s" "ms"))))

;;; The Ticks: a bar a tick kept, by its seq, read in place from the
;;; profiler's ring, in whole ns.

;; Tick seq's ns in phase j (of monitor-phases).
(define (monitor-tick-phase-ns seq j)
  (profile-tick-phase-ns seq (car (list-ref monitor-phases j))))

;; The fixnums from a to z, z included.
(define (monitor-range a z)
  (let loop ([z z] [acc '()]) (if (fx< z a) acc (loop (fx- z 1) (cons z acc)))))

;; The phases in the order the bars stack them, seqs the ticks shown: the
;; work's, the one that spent the most over them all first (at the
;; bottom), so that the bands run on from bar to bar; then the waits, as
;; monitor-phases has them, so that a bar past the graph's top loses a
;; wait, never work. One that spent nothing, none (nor in the legend).
;; => indexes into monitor-phases
(define (monitor-bars-order seqs)
  (let* ([totals (filter (lambda (t) (fx> (cdr t) 0))
                         (map (lambda (j)
                                (cons j (fold-left
                                         (lambda (ns seq)
                                           (fx+ ns (monitor-tick-phase-ns
                                                    seq j)))
                                         0 seqs)))
                              (iota (length monitor-phases))))]
         [wait? (lambda (t)
                  (memq (car (list-ref monitor-phases (car t)))
                        '(input-wait vsync-wait)))])
    (map car (append (list-sort (lambda (x y) (fx> (cdr x) (cdr y)))
                                (remp wait? totals))
                     (filter wait? totals)))))

;; A time of day from ms since midnight: "12:00:03.400".
(define (monitor-clock-text ms)
  (let ([two (lambda (n) (if (< n 10) (format "0~a" n) (format "~a" n)))]
        [ms (mod ms 86400000)])
    (format "~a:~a:~a.~a" (two (quotient ms 3600000))
            (two (remainder (quotient ms 60000) 60))
            (two (remainder (quotient ms 1000) 60))
            (let ([m (remainder ms 1000)])
              (cond [(< m 10) (format "00~a" m)]
                    [(< m 100) (format "0~a" m)]
                    [else (format "~a" m)])))))

;; The ms of the day at the profiler's clock's 0, by the clock now.
(define (monitor-clock-zero)
  (let ([d (current-date)] [ns (now-ns)])
    (- (+ (* 3600000 (date-hour d)) (* 60000 (date-minute d))
          (* 1000 (date-second d)) (quotient (date-nanosecond d) 1000000))
       (quotient ns 1000000))))

;; A subject is (window . id), (process . id), a surface's name or gc:
;; the subjects Monitor lists.
(define (monitor-subject? s)
  (or (pair? s) (eq? s 'gc) (and (symbol? s) (find-surface s) #t)))

(define (monitor-window? s) (and (pair? s) (eq? (car s) 'window)))

;; A row's node: a subject, or one of its parts, (subject part phase).
(define (monitor-part? node) (and (pair? node) (pair? (cdr node))))

;; A subject's window or process while it lives, found by its id; #f once
;; it is closed or ended (or for a surface or the collector).
(define (monitor-live s)
  (and (pair? s)
       (if (monitor-window? s) (find-window (cdr s)) (find-proc (cdr s)))))

;; A window's title, or the one it had; a process's name.
(define (monitor-title s)
  (let ([live (monitor-live s)])
    (cond [(and live (monitor-window? s)) (window-title live)]
          [live (proc-name live)]
          [else (or (profile-subject-name s)
                    (format "~a ~a" (car s) (cdr s)))])))

(define (monitor-subject-label s)
  (let ([live (monitor-live s)])
    (cond [(not (pair? s)) (if (eq? s 'gc) "Collector" (format "~a" s))]
          [(monitor-window? s)
           (if live (monitor-title s) (format "~a (closed)" (monitor-title s)))]
          [else (format "~a (process ~a~a)" (monitor-title s) (cdr s)
                        (if live "" ", ended"))])))

;; Labels of subjects, ((subject . label) ...): a window's title (the one
;; it had, once closed), with its id where another window among them has
;; the same; a process's name and id; a surface's name.
(define (monitor-labels subjects)
  (let ([titles (map (lambda (s) (and (monitor-window? s) (monitor-title s)))
                     subjects)])
    (map (lambda (s t)
           (cons s
                 (if (and t (> (length (filter (lambda (o) (equal? o t))
                                               titles))
                               1))
                     (format "~a (window ~a~a)" t (cdr s)
                             (if (monitor-live s) "" ", closed"))
                     (monitor-subject-label s))))
         subjects titles)))

;; A part: a handler's kind, or a window's frame, or a surface's or the
;; collector's phase (the collector's own, gc: outside them).
(define (monitor-part-label subject part phase)
  (cond [part (symbol->string part)]
        [(monitor-window? subject) "frame"]
        [(eq? phase 'gc) "outside the phases"]
        [(eq? subject 'gc) (format "during ~a" phase)]
        [(eq? phase 'render) "draw"]
        [else (symbol->string phase)]))

;; What a row's node is: a window, a process, a surface or the collector; a
;; part: a handler, a window's frame, or a phase.
(define (monitor-node-type node)
  (cond [(monitor-part? node)
         (cond [(cadr node) "handler"]
               [(monitor-window? (car node)) "frame"]
               [else "phase"])]
        [(monitor-window? node) "window"]
        [(pair? node) "process"]
        [(eq? node 'gc) "collector"]
        [else "surface"]))

;; Where tick seq's time went, a bar's tooltip, a line each: when it
;; ended (zero, the ms of the day at the clock's 0), how long it took
;; and whether it came late (period, ns), its phases
;; (profile-tick-phases) and its three largest consumers, the most first.
(define (monitor-tick-tip seq zero period)
  (let* ([ns (profile-tick-ns seq 'ns)]
         [phases (filter (lambda (p) (>= (cdr p) 50000))   ; 0.1 ms shown
                         (profile-tick-phases seq))]
         [top (filter (lambda (t) (and (monitor-subject? (profile-total-what t))
                                       (>= (profile-total-ms t) 0.05)))
                      (profile-totals (list seq) #t))]
         [top (list-head top (min 3 (length top)))]
         [labels (monitor-labels (map profile-total-what top))])
    (define (list-of items)   ; (name . words) a line each
      (apply string-append
             (map (lambda (x) (format "\n~a ~a" (car x) (cdr x))) items)))
    (string-append
     (format "tick ~a, ended ~a\n" seq
             (monitor-clock-text
              (+ zero (quotient (profile-tick-ns seq 'end) 1000000))))
     (format "~a, ~a (a tick is ~a)" (monitor-ns-text ns)
             (cond [(profile-tick-late? seq period) "late"]
                   [(profile-tick-held? seq period) "held by the screen"]
                   [else "in time"])
             (monitor-ns-text period))
     (if (profile-tick-late? seq period)
         (format "\n~a" (profile-why-text (profile-tick-why seq period)))
         "")
     (list-of (map (lambda (p)
                     (cons (cddr (assq (car p) monitor-phases))
                           (monitor-ns-text (cdr p))))
                   phases))
     (list-of (map (lambda (t)
                     (cons (cdr (assoc (profile-total-what t) labels))
                           (format "~a ms" (monitor-ms (profile-total-ms t)))))
                   top)))))

;;; ------------------------------------------------------------------ the app

;;; ------------------------------------------------------------------ overview

;; A count with its thousands apart: "30,312".
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

;; The World's facts, (label . words) a pair each, in reading order.
(define (monitor-world-facts)
  (let ([hz (exact (round (/ 1e9 (host-frame-ns))))]
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
           (cons "Process" (let ([b (status-process-bytes)])
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

;; The Overview, from y in a column x w wide: the World's facts in a grid,
;; then the windows (a click focuses one) and the processes (each with
;; its Kill) in the kit's tables, each under a group's heading.
(define (monitor-draw-overview ui x y w)
  (let* ([lh (font-line-height 'ui)]
         [rh (ui-table-row-height)]
         [heading (lambda (y title words)   ; => the y below
                    (let-values ([(gw gh) (ui-label-size '(group) title w)])
                      (ui-draw-label x y w gh '(group) title)
                      (ui-draw-label x y w gh '(dim right) words)
                      (+ y gh 8)))]
         [table-h (lambda (n most)
                    (+ (ui-table-header-height) (* rh (max 1 (min n most)))))]
         [cell (lambda (text-of)   ; a cell: its row's text for its key
                 (lambda (row key cx cy cw ch flags)
                   (ui-draw-cell cx cy cw ch '() (text-of row key))))]
         [wins (sort (lambda (a b) (< (window-id a) (window-id b))) (windows))]
         [ps (procs)])
    ;; the World: a label and its words a row, in two columns where they
    ;; fit (the first, its words the longer, wider), the last error across
    ;; both
    (let* ([facts (monitor-world-facts)]
           [err (and (equal? (car (last-pair facts)) "Last error")
                     (last-pair facts))]
           [facts (if err (list-head facts (- (length facts) 1)) facts)]
           [lw (+ 16 (apply max (map (lambda (f) (text-width (car f) 'ui))
                                     (cons '("Last error") facts))))]
           [cols (if (>= w (* 2 (+ lw 220))) 2 1)]
           [colx (if (= cols 2) (* w 0.58) w)]   ; where the second starts
           [row-h (+ lh 6)]
           [y (heading y "World" "")]
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
        (when err (fact! (car err) x y w))
        (let* ([y (+ y (if err row-h 0) 16)]
               [y (heading y "Windows"
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
                                   p key cx cy cw ch flags))))))))))))

(define-app (monitor) "Monitor"
  (let ([ui (make-ui)]
        [tab 'overview]    ; the tab shown: overview, ticks or flags
        [view #f]          ; the history shown: (newest tick . seconds)
        [last 0]           ; when it moved on (now-ms): twice a second
        [paused? #f]
        [held #f]          ; paused: the newest tick shown (its seq)
        [pinned #f]        ; the bar clicked (its tick's seq)
        [selected #f]      ; the row selected: a subject, or (subject part
                           ; phase)
        [order '(rate . down)]   ; the Consumers' sort: (key . up|down)
        [parts (make-hashtable equal-hash equal?)]   ; subject: (part . phase)s
        [shares (make-hashtable equal-hash equal?)]   ; (seq . selected): ns
        [tips (make-eqv-hashtable)]                   ; seq: text
        [drawn #f]         ; the Ticks as last drawn: (newest hover)
        [memos (make-hashtable equal-hash equal?)]   ; the view's figures
        [memo-view #f]
        [ring (monitor-ticks-stream)])   ; the Ticks' bars
    (define (move-on!)
      (set! view (cons (profile-newest-tick) (profile-seconds)))
      (set! last (now-ms)))
    ;; the newest tick kept, or the one held
    (define (newest-tick) (or held (profile-newest-tick)))
    ;; thunk's value, worked out once a view: Monitor is drawn again with
    ;; whatever frame holds it, far more often than its view moves on.
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
           [(tw th) (ui-tabs-size '("Overview" "Ticks" "Flags"))]
           [(none?) (not (car (history)))]   ; no tick yet
           [(items)   ; the tabs, then the Ticks' own controls
            (list
             (list tw th
                   (lambda (x y w h)
                     (ui-tabs ui 'tab x y h
                              '(("Overview" . overview) ("Ticks" . ticks)
                                ("Flags" . flags))
                              tab
                              (lambda (t) (set! tab t)))))
             (list kw kh
                   (lambda (x y w h)
                     (ui-checkbox ui 'profiling x y w h "Profiling"
                                  (profile-on?)
                                  (lambda (on?) (profile-on! on?))
                                  'tip "Profile the world: (profile-on! #t)")))
             (list pw ph
                   (lambda (x y w h)
                     (ui-button ui 'pause x y w h
                                (if paused? "Resume" "Pause")
                                (lambda () (if paused? (resume!) (pause! #f)))
                                'disabled (and none? (not paused?))
                                'tip "Hold this view still")))
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
                                  'tip "How long every tick is kept")))
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
                      [(overview) (list (car items))]
                      [(flags) (list (car items) (cadddr items))]
                      [else items])])
        (ui-toolbar 0 0 w items)))
    ;; A group's heading at y, and words at its right; the y below.
    (define (section x y w title words)
      (let-values ([(gw gh) (ui-label-size '(group) title w)])
        (ui-draw-label x y w gh '(group) title)
        (ui-draw-label x y w gh '(dim right) words)
        (+ y gh 6)))
    ;; The Consumers' rows: the totals over the last complete seconds (at
    ;; most 5 of them), the subjects listed (those that ran in the last
    ;; minute, then the live windows and processes) and their labels, and
    ;; the seconds' span. A subject keeps the parts it last had several of,
    ;; so that its row can't fold by itself.
    (define (consumers seconds)
      (define (latest n)
        (filter (lambda (t) (monitor-subject? (profile-total-what t)))
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
            (list (latest monitor-consumer-seconds) roots (monitor-labels roots)
                  (max 1 (min monitor-consumer-seconds (length seconds))))))))
    (define (label-of s seconds)
      (let ([l (assoc s (caddr (consumers seconds)))])
        (if l (cdr l) (monitor-subject-label s))))
    ;; A bar for each tick that fits, the newest at the right, in the
    ;; phases' order by what they spent, up to two of the pacer's periods
    ;; (a longer tick reaches the top), the period's line at half, a tick
    ;; that came late flagged at the top; the legend under them in the
    ;; same order; a bar's tooltip says where its time went.
    (define (draw-ticks x y w h seconds)
      (let*-values
          ([(period) (pacer-period)]
           [(top) (* 2 period)]
           ;; in the rows' numbers, µs
           [(rules) (list (cons (quotient period 1000) (monitor-ns-text period))
                          (cons (quotient top 1000) (monitor-ns-text top)))]
           [(newest) (newest-tick)]
           [(oldest) (profile-oldest-tick)]
           ;; as many bars as fit right of the scale
           [(count) (ui-stream-count ring x y w h newest oldest rules
                                     monitor-bar-px)]
           [(order) (remember
                     'order
                     (lambda ()
                       (monitor-bars-order
                        (if newest
                            (monitor-range (- newest count -1) newest)
                            '()))))]
           [(keys) (append (map (lambda (j) (cdr (list-ref monitor-phases j)))
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
           [(zero) (monitor-clock-zero)])
        (when newest
          (ui-stream-send! ring oldest newest (monitor-tick-word period)))
        (let ([hover
               (ui-stream
                ui 'monitor-ticks ring x y w gh newest oldest
                (quotient top 1000) rules
                (map (lambda (j) (cons j (cadr (list-ref monitor-phases j))))
                     order)
                monitor-bar-px
                'tip (lambda (seq)
                       (and (profile-tick-kept? seq)
                            (tip-of seq zero period)))
                'on-pick (lambda (seq) (pause! seq))
                'marked (if pinned (list pinned) '())
                ;; the row selected's share, over the bars
                'over
                (lambda (areas count)
                  (when (and selected newest)
                    (let-values ([(px py pw ph)
                                  (apply values (cdr (assq 'bars areas)))])
                      (do ([i 0 (+ i 1)]) ((= i count))
                        (let-values ([(bx bw) (ui-bar-chart-bar areas count i)])
                          (let* ([ns (share-of (+ newest (- i count -1)))]
                                 [high (div (* ph (min ns top)) top)])
                            (when (and (>= bx px) (> high 0))
                              (fill-box bx (- (+ py ph) high)
                                        (- bw (if (>= bw 3) 1 0)) high
                                        'chart-share)))))))))])
          (set! drawn (list newest hover)))
        (ui-draw-legend x (+ y gh 4) w kh '() keys)))
    ;; Tick seq's tooltip, worked out once.
    (define (tip-of seq zero period)
      (or (hashtable-ref tips seq #f)
          (let ([text (monitor-tick-tip seq zero period)])
            (when (> (hashtable-size tips) 64) (hashtable-clear! tips))
            (hashtable-set! tips seq text)
            text)))
    ;; What the row selected spent in tick seq, ns, worked out once.
    (define (share-of seq)
      (let ([key (cons seq selected)])
        (or (hashtable-ref shares key #f)
            (let ([ns (profile-tick-node-ns seq selected)])
              (when (> (hashtable-size shares) 4096)
                (hashtable-clear! shares))
              (hashtable-set! shares key ns)
              ns))))
    ;; Whether the Ticks would look different now: a new tick, or a bar
    ;; under the pointer (its tip).
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
             [kind (+ (* 2 (ui-table-cell-inset)) (text-width "collector" 'ui))]
             [num (max (* 8 cw) (+ 28 (text-width "calls/s" 'ui-small)))]
             [spark (* 13 cw)]
             ;; each heading's tooltip says what its column means
             [columns
              `((name "Consumer"
                      ,(max 120 (- (ui-table-room w) kind (* 4 num) spark))
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
                                over the last ~a s: its share of the main \
                                loop's time" monitor-consumer-seconds))
                (avg "avg" ,num right
                     "Milliseconds it took in a tick, on average over \
                      the ticks it ran in")
                (max "max" ,num right
                     ,(format "The most milliseconds it took in one tick: \
                               past a tick's period (~a), it alone held the \
                               next tick back"
                              (monitor-ns-text (pacer-period))))
                (calls "calls/s" ,num right
                       "How many times a second it ran: a handler called, \
                        a frame drawn, a process's turn")
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
        ;; what node sorts by in the column key: its label, or a number (0
        ;; for none; the last minute's sum)
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
              [else (apply + (minute-of node))])))
        ;; siblings in the order order names, ties as they come
        (define (sorted nodes)
          (let ([key (car order)] [down? (eq? (cdr order) 'down)]
                [less? (if (memq (car order) '(name type)) string-ci<? <)])
            (list-sort (lambda (a b)
                         (let ([va (sort-value a key)] [vb (sort-value b key)])
                           (if down? (less? vb va) (less? va vb))))
                       nodes)))
        ;; a subject's parts, (subject part phase), once it has had several
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
                                 (monitor-part-label s (cadr node) (caddr node))
                                 (label-of s seconds))]
                      [live (monitor-live s)]
                      [id (and live (cdr s))]
                      [kill? (and live (not (monitor-part? node)) (proc? live))]
                      [bw (if kill? (+ 16 (text-width "Kill" 'ui)) 0)]
                      ;; after the twisty, where the heading's label starts
                      [nx (+ cx in)]
                      [room (- cw in bw 4)])
                 (ui-draw-label nx cy room ch
                                (if (and (pair? s) (not live))
                                    '(dim)
                                    '())
                                label)
                 ;; the live window or process, looked up by its id
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
              [(rate) (number (monitor-ms (if t (/ (profile-total-ms t) span)
                                              0.0)))]
              [(avg) (number (if (and t (> (profile-total-ticks t) 0))
                                 (monitor-ms (/ (profile-total-ms t)
                                                (profile-total-ticks t)))
                                 "–"))]
              [(max) (number (if t (monitor-ms (profile-total-longest t)) "–"))]
              [(calls) (number (if t
                                   (let ([c (/ (profile-total-calls t) span)])
                                     (if (< c 99.95)
                                         (format "~,1f" c)
                                         (number->string (exact (round c)))))
                                   "–"))]
              [(spark)
               (ui-draw-sparkline (+ cx 4) (+ cy 4) (- cw 12) (- ch 8) flags
                                  (minute-of node))])))
        (ui-tree ui 'consumers x y w h columns (sorted roots) children selected
                 ;; a press on the row selected lets it go
                 (lambda (node)
                   (set! selected (if (equal? node selected) #f node)))
                 cell
                 'sort order
                 ;; by a number, the most first; again, the other way
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
                                    (monitor-ms (at latest 'gc-ms))
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
    ;; Every flag kept, the newest first: when, what it took, what made it
    ;; late and the ticks about it; a row's tooltip says all that's known.
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
                        (why "Why" ,(* w 0.46))
                        (before "Before it" ,(* w 0.16))
                        (ticks "Ticks about it, ms" ,(* w 0.22))))
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
          [(eq? tab 'flags)
           (let* ([cw (- w pad pad)]
                  [y (section pad (+ y 4) cw "Flags" (profile-flag-summary))])
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
                                       late; ~a ticks/s~a"
                                      rate (if paused? ", paused" "")))]
                  [y (begin (draw-ticks x y cw ticks-h seconds)
                            (+ y ticks-h 8))]
                  [y (section x y cw "Consumers"
                              (format "a second's average over the \
                                       last ~a s"
                                      monitor-consumer-seconds))]
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
           'size (cons (max 640 (+ 160 (* 58 (font-char-width 'ui))))
                       (max 600 (* 21 (ui-table-row-height))))
           'min-size '(420 . 360)
           'draw (lambda (win w h) (draw win w h))
           'close (lambda (win)
                    (ui-stream-release! ring))
           (append
            (ui-handlers ui)
            ;; the Ticks at every new tick, the rest twice a second, while
            ;; it's seen
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
                              (invalidate! win)))))))))
