;;; tests/bench.ss — what a frame costs on the render ladder's four scenes.
;;;
;;;   scheme --script tests/bench.ss [output-dir [frames]]
;;;
;;; Headless, 1280 × 800 logical pixels, at 100% and 200%:
;;;   S30T  30 Life windows, tiled: no two overlap
;;;   S5    a typical desktop: a REPL with a screenful of text, Settings,
;;;         Clock, Life and Monitor, overlapping
;;;   S30   30 Life windows, cascaded
;;;   S30M  S30 under a maximized REPL
;;; A fake clock moves 81 ms a step, so every Life window steps, and asks
;;; for a frame, at every step. Everything runs on the main thread, on
;;; lavapipe, whose work on its own threads the main thread only hands over.
;;; Each scene: 10 steps to warm up, then frames (default 100) measured, each
;;; one step:
;;;   main    the main thread's CPU time (median): events, ticks, recording
;;;           the frame, sending it
;;;   wall    the step's time, steps back to back (median, and 90th
;;;           percentile)
;;;   upload  the bytes of the list sent (mean)
;;;   GCs     collections (mean)
;;; Also a keystroke in S5's REPL (the clock still: the frame shows the
;;; new character), an idle step (30 paused Life windows, the clock
;;; standing still), a theme change on S30 (it paints the wallpaper
;;; again), the clock's second with no window and a keystroke in a REPL
;;; alone (each step one of them, at 100% and 200%, and at 200% on a
;;; 1920 × 1080 screen, a 4K one), Tasks maximized on that screen (an idle
;;; step, a keystroke in a title, two in one step, a card dragged), a
;;; keystroke in a long text's worst cases there, in the details and in
;;; the description's editor, maximized, the Tree there with the seed and
;;; with 2,000 tasks more in chains, a busy process's share of the main
;;; thread while S30T animates at 200%, and the profiler's cost: a step
;;; with profiling on and off (printed, not bounded), then the crew: Life
;;; at one pixel a cell, maximized on that screen, and Boids at 150, 450,
;;; 2,000 and 5,000, on one thread and more (printed, not bounded). Fails
;;; (exit 1) unless every measured step drew a frame, an idle step takes
;;; under 0.2 ms and sends nothing (with Tasks open too), a keystroke in
;;; a long text keeps within its budget, a step of the Tree with 2,000
;;; tasks within 1.5 times one with the seed, and the busy process and the
;;; animation both go on.

(define *schevana-root*
  (let ([dir (path-parent (path-parent (car (command-line))))])
    (if (string=? dir "") "." dir)))

(load (string-append *schevana-root* "/main.ss"))
(load (string-append *schevana-root* "/tests/core0.ss"))

(define args (command-line-arguments))
(define out-dir (if (pair? args) (car args) "."))
(define frames (if (> (length args) 1) (string->number (cadr args)) 100))
(set! *theme-file-path* (string-append out-dir "/theme.ss"))
(when (file-exists? *theme-file-path*) (delete-file *theme-file-path*))

(define fake-ms 1000000)
(set! now-ms (lambda () fake-ms))
(random-seed 4242)
(schevana-boot! 'headless 1280 800)

(define (ms-of t) (+ (* 1000.0 (time-second t)) (/ (time-nanosecond t) 1e6)))
(define (wall-ms) (ms-of (current-time 'time-monotonic)))
(define (main-ms) (ms-of (current-time 'time-thread)))

(define (median xs)
  (if (null? xs) 0.0 (list-ref (sort < xs) (quotient (length xs) 2))))
(define (percentile xs p)
  (if (null? xs)
      0.0
      (list-ref (sort < xs)
                (min (- (length xs) 1) (exact (floor (* p (length xs))))))))

;;; ------------------------------------------------------------------
;;; what goes up

;; The bytes of the lists frames have sent.
(define *upload-bytes* 0)
(define plain-present rec-present!)
(set! rec-present!
      (lambda ()
        (set! *upload-bytes*
          (+ *upload-bytes* (gpu-recording-recs-n *rec-now*)
             (gpu-recording-extras-n *rec-now*)))
        (plain-present)))

;;; ------------------------------------------------------------------ scenes

(define (steps n ms)
  (do ([i 0 (+ i 1)]) ((= i n))
    (set! fake-ms (+ fake-ms ms))
    (schevana-step! 0)))

;; Status segments that never change.
(define (fixed-status!)
  (set! *status-segments* '())
  (add-status-segment! 'a (lambda () "12.3 ms/tick"))
  (add-status-segment! 'b (lambda () "Thu 29 Oct   12:00:00")))

(define (clear-world!)
  (for-each close-window! (windows))
  (set! *toasts* '())
  (set! *cascade* 0)
  (set! *hover* #f)
  (set! *drag* #f)
  (when (menu-open?) (close-menu!)))

(define (lifes! layout)
  (do ([i 0 (+ i 1)]) ((= i 30)) (life))
  (case layout
    [(tiled) (tile-windows!)]
    [else (cascade-windows!)]))

(define repl-text-lines
  '((input . "(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))")
    (result . "fib")
    (input . "(map fib (iota 20))")
    (result . "(0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 \
               4181)")
    (input . "(windows)")
    (result . "(#<window 4 \"Life\" 720x496+520+290> \
               #<window 3 \"Clock\" 230x290+1020+50>")
    (result . " #<window 2 \"Settings\" 780x560+380+140> \
               #<window 1 \"REPL\" 692x470+30+45>)")
    (input . "(for-each (lambda (w) (printf \"~a ~a\\n\" (window-id w) \
              (window-title w))) (windows))")
    (output . "4 Life")
    (output . "3 Clock")
    (output . "2 Settings")
    (output . "1 REPL")
    (input . "(set-theme! 'accent #xff9e64)")
    (input . "(set-palette! 'tokyo-night)")
    (input . "(define-app (counter) \"Counter\" (let ([n 0]) \
              (open-window \"Counter\" 'size '(240 . 100))))")
    (result . "counter")
    (input . "(list (screen-w) (screen-h) *scale* (length (windows)) \
              (length (procs)) (apps))")
    (result . "(1280 800 1.0 5 0 (repl private-repl pure-repl clock life \
               sketch monitor settings))")
    (input . "(string-append \"The quick brown fox \" \
              \"jumps over the lazy dog, \" \"again and again.\")")
    (result . "\"The quick brown fox jumps over the lazy dog, again and \
               again.\"")
    (input . "(vector-map (lambda (x) (* x x)) '#(1 2 3 4 5 6 7 8 9 10 \
              11 12 13 14 15 16))")
    (result . "#(1 4 9 16 25 36 49 64 81 100 121 144 169 196 225 256)")
    (input . "(bytes-allocated)")
    (result . "48233472")))

(define (texted-repl!)
  (let* ([r (repl)] [rs (window-ref r 'state)])
    (for-each (lambda (l) (repl-add! rs (car l) (cdr l))) repl-text-lines)
    r))

(define (scene! name)
  (clear-world!)
  (random-seed 4242)
  (case name
    [(S30T) (lifes! 'tiled)]
    [(S30) (lifes! 'cascaded)]
    [(S30M) (lifes! 'cascaded) (steps 3 17) (toggle-maximize! (texted-repl!))]
    [(S5)
     (let* ([r (texted-repl!)]
            [s (settings)]
            [c (clock)]
            [l (life)]
            [m (monitor)])
       (move-window! r 30 45)
       (move-window! s 380 120)
       (move-window! c 1020 50)
       (move-window! l 520 290)
       (move-window! m 60 300)
       (toggle-maximize! s)
       (steps 1 17)
       (toggle-maximize! s)
       (for-each focus-window! (list s m l c r)))])   ; the REPL on top, focused
  (steps 3 17)
  (fixed-status!)
  (steps 2 17))

;;; ------------------------------------------------------------------
;;; the ladder

;; One scene at one scale: a property list of what it measured.
(define (run-scene name pct)
  (set-theme! 'scale pct)
  (steps 2 17)
  (scene! name)
  (steps 10 81)
  (let ([u0 *upload-bytes*] [g0 (collections)] [d0 *frames-drawn*])
    (let loop ([i 0] [walls '()] [mains '()])
      (if (< i frames)
          (let ([w0 (wall-ms)] [m0 (main-ms)])
            (steps 1 81)
            (let ([m (- (main-ms) m0)] [w (- (wall-ms) w0)])
              (loop (+ i 1) (cons w walls) (cons m mains))))
          (list 'scene name 'scale pct 'windows (length (windows))
                'drawn (- *frames-drawn* d0)
                'main (median mains) 'wall (median walls)
                'wall-p90 (percentile walls 0.9)
                'upload (/ (- *upload-bytes* u0) frames 1.0)
                'gcs (/ (- (collections) g0) frames 1.0))))))

(define (row r)
  (printf "~5a ~4a ~7a ~7,2f ~7,2f (~6,2f) ~9,2f ~5,2f\n"
          (plist-ref r 'scene #f) (plist-ref r 'scale #f)
          (plist-ref r 'windows #f) (plist-ref r 'main #f)
          (plist-ref r 'wall #f) (plist-ref r 'wall-p90 #f)
          (/ (plist-ref r 'upload #f) 1048576.0) (plist-ref r 'gcs #f)))

(printf "Per frame, ~a frames a scene; ms unless said.\n" frames)
(printf "~5a ~4a ~7a ~7a ~7a (~6a) ~9a ~5a\n"
        "scene" "%" "windows" "main" "wall" "p90" "upload MiB" "GCs")
(define results '())
(for-each (lambda (name)
            (for-each (lambda (pct)
                        (let ([r (run-scene name pct)])
                          (row r)
                          (set! results (cons r results))))
                      '(100 200)))
          '(S30T S5 S30 S30M))

(define (result name pct)
  (find (lambda (r)
          (and (eq? (plist-ref r 'scene #f) name)
               (eqv? (plist-ref r 'scale #f) pct)))
        results))

;;; ------------------------------------------------------------------
;;; idle steps and theme changes

;; Steps with 30 paused Life windows and the clock standing still: the
;; ones that draw no frame (all but the once-a-second one).
(define (idle-steps pct)
  (set-theme! 'scale pct)
  (scene! 'S30)
  (for-each (lambda (w) (window-call w 'key #\space '())) (windows))
  (quiet-steps))

;; 3000 steps with nothing happening: the median of those that draw no
;; frame, and the bytes they uploaded.
(define (quiet-steps)
  (steps 3 0)
  (let loop ([i 0] [times '()] [uploaded 0])
    (if (< i 3000)
        (let ([u *upload-bytes*] [n *frames-drawn*] [t0 (wall-ms)])
          (schevana-step! 0)
          (let ([t (- (wall-ms) t0)])
            (if (> *frames-drawn* n)
                (loop (+ i 1) times uploaded)
                (loop (+ i 1) (cons t times)
                      (+ uploaded (- *upload-bytes* u))))))
        (values (median times) uploaded))))

;; A theme change and the step after it, which paints the wallpaper's new
;; picture and draws the frame: (values wall main), medians.
(define (theme-change-ms pct)
  (set-theme! 'scale pct)
  (scene! 'S30)
  (for-each (lambda (w) (window-call w 'key #\space '())) (windows))
  (steps 3 17)
  (let loop ([colors
              '(#xff9e64 #x7aa2f7 #xff9e64 #x7aa2f7 #xff9e64 #x7aa2f7 #xff9e64)]
             [walls '()]
             [mains '()])
    (if (null? colors)
        (values (median walls) (median mains))
        (let ([w0 (wall-ms)] [m0 (main-ms)])
          (set-theme! 'accent (car colors))
          (steps 1 17)
          (loop (cdr colors)
                (cons (- (wall-ms) w0) walls)
                (cons (- (main-ms) m0) mains))))))

;; A key typed into S5's REPL, the clock standing still: the step that
;; handles it draws the frame that shows it. (values wall main) medians.
(define (keystroke-ms pct)
  (set-theme! 'scale pct)
  (scene! 'S5)
  (steps 3 0)
  (let loop ([i 0] [walls '()] [mains '()])
    (if (< i 40)
        (let ([w0 (wall-ms)] [m0 (main-ms)] [n *frames-drawn*])
          (inject! (list 'text (if (even? i) "a" "b")))
          (schevana-step! 0)
          (unless (= *frames-drawn* (+ n 1))
            (errorf 'keystroke-ms "a keystroke drew no frame"))
          (loop (+ i 1)
                (cons (- (wall-ms) w0) walls)
                (cons (- (main-ms) m0) mains)))
        (values (median walls) (median mains)))))

(newline)
(for-each (lambda (pct)
            (let-values ([(wall main) (keystroke-ms pct)])
              (printf "a keystroke in S5's REPL at ~a%: ~,2f ms until its \
                       frame is drawn (main thread ~,2f ms)\n"
                      pct wall main)))
          '(100 200))
(define-values (idle-100 idle-up-100) (idle-steps 100))
(define-values (idle-200 idle-up-200) (idle-steps 200))
(printf "idle step with 30 paused Life windows: ~,3f ms at 100%, \
         ~,3f ms at 200%\n"
        idle-100 idle-200)
(for-each (lambda (pct)
            (let-values ([(wall main) (theme-change-ms pct)])
              (printf "a theme change at ~a%: ~,1f ms until its frame is \
                       drawn, the wallpaper painted again \
                       (main thread ~,1f ms)\n"
                      pct wall main)))
          '(100 200))

;;; ------------------------------------------------------------------
;;; the clock's second and a keystroke, on a quiet desktop

;; The headless screen, w × h logical pixels at pct.
(define (screen! w h pct)
  (set! *headless-size* (cons w h))
  (set-theme! 'scale pct)
  (unless (and (= *canvas-w* w) (= *canvas-h* h))
    (canvas-create! w h *host-scale*)
    (wm-screen-resized!))
  (steps 2 17))

;; Steps that each draw the frame of one thing that changed (change!
;; makes it change): (values main wall upload), the medians of the main
;; thread's and the step's ms and the mean bytes uploaded.
(define (frame-steps change!)
  (steps 3 0)
  (let ([u0 *upload-bytes*])
    (let loop ([i 0] [walls '()] [mains '()])
      (if (< i frames)
          (let ([w0 (wall-ms)] [m0 (main-ms)] [n *frames-drawn*])
            (change! i)
            (schevana-step! 0)
            (unless (= *frames-drawn* (+ n 1))
              (errorf 'frame-steps "a change drew no frame"))
            (loop (+ i 1)
                  (cons (- (wall-ms) w0) walls)
                  (cons (- (main-ms) m0) mains)))
          (values (median mains) (median walls)
                  (/ (- *upload-bytes* u0) frames 1.0))))))

;; No window; the top bar's clock shows a new second at every step.
(define (idle-ticks)
  (clear-world!)
  (let ([second 0])
    (set! *status-segments* '())
    (add-status-segment! 'clock
      (lambda () (format "Thu 29 Oct   12:00:~2,'0d" (mod second 60))))
    (frame-steps (lambda (i)
                   (set! second (+ second 1))
                   (status-show!)))))

;; A REPL alone, where it opens, typed into.
(define (lone-keystrokes)
  (clear-world!)
  (fixed-status!)
  (texted-repl!)
  (frame-steps (lambda (i) (inject! (list 'text (if (even? i) "a" "b"))))))

(for-each
 (lambda (s)
   (apply screen! s)
   (let*-values ([(tick-main tick-wall tick-up) (idle-ticks)]
                 [(key-main key-wall key-up) (lone-keystrokes)])
     (printf "~ax~a at ~a%: the clock's second, no window: main ~,2f ms, \
              wall ~,2f, ~,3f MiB uploaded; a keystroke in a lone REPL: \
              main ~,2f ms, wall ~,2f, ~,3f MiB uploaded\n"
             (car s) (cadr s) (caddr s) tick-main tick-wall
             (/ tick-up 1048576.0) key-main key-wall (/ key-up 1048576.0))))
 '((1280 800 100) (1280 800 200) (1920 1080 200)))
(screen! 1280 800 100)

;;; ------------------------------------------------------------------
;;; Tasks, maximized on a 1920 × 1080 screen at 200%
;;; With nothing focused it asks for no frame. A keystroke in a task's
;;; title, two in one step (the second lays the window out again first)
;;; and a card dragged a step a move each draw the whole window.

(define (tasks-bench)
  (screen! 1920 1080 200)
  (clear-world!)
  (fixed-status!)
  (tasks-reset!)
  (let* ([win (tasks)] [ui (window-ref win 'ui)])
    (define (at id)   ; region id's middle on screen
      (let ([r (ui-find ui id)])
        (let-values ([(cx cy cw ch) (content-rect win)])
          (list (exact (floor (+ cx (ui-region-x r) (/ (ui-region-w r) 2))))
                (exact (floor (+ cy (ui-region-y r) (/ (ui-region-h r) 2))))))))
    (maximize-window! win)
    (steps 2 17)
    (apply inject! (let ([p (at '(card 9))])
                     `((mouse-move ,@p) (mouse-down ,@p left 1)
                       (mouse-up ,@p left))))
    (let*-values ([(idle idle-up) (quiet-steps)]
                  [(key-main key-wall key-up)
                   (begin
                     (inject! '(key-down return ()))
                     (frame-steps (lambda (i)
                                    (inject! (if (even? i)
                                                 '(text "a")
                                                 '(key-down backspace
                                                   ()))))))]
                  [(two-main two-wall two-up)
                   (frame-steps (lambda (i)
                                  (if (even? i)
                                      (inject! '(text "a") '(text "b"))
                                      (inject! '(key-down backspace ())
                                               '(key-down backspace ())))))]
                  [(drag-main drag-wall drag-up)
                   (let ([p (at '(card 10))] [a (at '(column review))]
                         [b (at '(column done))])
                     (inject! '(key-down escape ()) `(mouse-move ,@p)
                              `(mouse-down ,@p left 1))
                     (steps 1 0)
                     (frame-steps
                      (lambda (i)
                        (inject! `(mouse-move ,@(if (even? i) a b))))))])
      (inject! `(mouse-up ,@(at '(column todo)) left))
      (steps 2 0)
      (close-window! win)
      (printf "Tasks maximized on 1920x1080 at 200%: an idle step ~,3f ms, \
               ~a bytes uploaded; a keystroke in a title: main ~,2f ms, wall \
               ~,2f; two in one step: main ~,2f ms, wall ~,2f; a card \
               dragged, a move: main ~,2f ms, wall ~,2f\n"
              idle idle-up key-main key-wall two-main two-wall drag-main
              drag-wall)
      (values idle idle-up))))

(define-values (tasks-idle tasks-idle-up) (tasks-bench))
(screen! 1280 800 100)

;;; ------------------------------------------------------------------
;;; the Tree, in Tasks maximized on a 1920 × 1080 screen at 200%
;;; With the seed, and with 2,000 tasks more in 40 chains of 50 (each
;;; waits for the one before it, and every fifth also for its neighbor in
;;; the chain before: blockers shared), every node expanded: steps that
;;; each move the selection a row (Down, then Up), collapse or expand a
;;; chain (Space), or wheel the rows (down, then up), each drawing the
;;; window. The rows drawn are the rows in view; what grows with the tasks
;;; is walking the expanded nodes and Tasks' own passes over the tasks
;;; (its filters, the tree's shape): a step must stay within 1.5 times
;;; the seed's (the least of three rounds each).

;; The seed and 2,000 tasks in chains after it; => the first chain's top.
(define (chained-tasks!)
  (tasks-reset!)
  (let ([base *tasks-next-id*] [now (tasks-now)])
    (set! *tasks*
      (append *tasks*
              (map (lambda (i)
                     (let ([c (quotient i 50)] [k (remainder i 50)]
                           [id (+ base i)])
                       (make-task id (format "Chain ~a, link ~a" c k) ""
                                  'todo 'feature 'normal #f '() #f '()
                                  (append (if (> k 0) (list (- id 1)) '())
                                          (if (and (> c 0) (> k 0)
                                                   (= 0 (remainder k 5)))
                                              (list (- id 50))
                                              '()))
                                  now now)))
                   (iota 2000))))
    (set! *tasks-next-id* (+ base 2000))
    (tasks-changed!)
    (find-task (+ base 49))))

;; => (key space wheel rows): the median main-thread ms of each kind of
;; step, and the rows the tree showed.
(define (tree-steps chained?)
  (screen! 1920 1080 200)
  (clear-world!)
  (fixed-status!)
  (let* ([top (if chained? (chained-tasks!) (begin (tasks-reset!)
                                                   (find-task 13)))]
         [win (tasks)] [v (window-ref win 'state)] [ui (window-ref win 'ui)])
    (maximize-window! win)
    (tasks-view-mode-set! v 'tree)
    (tasks-select! v top)
    (invalidate! win)
    (steps 2 17)
    (let*-values
        ([(rows) (vector-length (ui-memo ui '(tree rows) '#()))]
         [(key-main key-wall key-up)
          (frame-steps (lambda (i)
                         (inject! (if (even? i)
                                      '(key-down down ())
                                      '(key-down up ())))))]
         [(space-main space-wall space-up)
          (frame-steps (lambda (i) (inject! '(key-down #\space ()))))]
         [(wheel-main wheel-wall wheel-up)
          (let ([r (ui-find ui '(tree body))])
            (let-values ([(cx cy cw ch) (content-rect win)])
              (inject! `(mouse-move ,(exact (floor (+ cx (ui-region-x r) 40)))
                                    ,(exact (floor (+ cy (ui-region-y r)
                                                      200))))))
            (frame-steps (lambda (i)
                           (inject! (if (even? i)
                                        '(wheel 0 -1)
                                        '(wheel 0 1))))))])
      (close-window! win)
      (tasks-reset!)
      (list key-main space-main wheel-main rows))))

(define tree-rounds 3)

;; ((seed key space wheel rows) (chained key space wheel rows)): each
;; kind's least of the rounds.
(define tree-results
  (let ([rounds (map (lambda (i) (list (tree-steps #f) (tree-steps #t)))
                     (iota tree-rounds))])
    (map (lambda (which j)
           (cons which
                 (map (lambda (k)
                        (if (= k 3)
                            (list-ref (list-ref (car rounds) j) 3)
                            (apply min (map (lambda (r)
                                              (list-ref (list-ref r j) k))
                                            rounds))))
                      '(0 1 2 3))))
         '(seed chained) '(0 1))))
(screen! 1280 800 100)
(for-each (lambda (r)
            (printf "the Tree in Tasks maximized on 1920x1080 at 200%, ~a \
                     (~a rows): a key ~,2f ms (main), Space ~,2f, the wheel \
                     ~,2f (the least of ~a rounds)\n"
                    (car r) (list-ref r 4) (cadr r) (caddr r) (cadddr r)
                    tree-rounds))
          tree-results)

;;; ------------------------------------------------------------------
;;; a long text, in Tasks maximized on a 1920 × 1080 screen at 200%
;;; A description of 65,535 characters under a title as long, in each
;;; worst case: one paragraph of words; no spaces at all (broken by
;;; character); every row exactly full, so that a key typed at its start
;;; moves a word down every row (a cascade). Keystrokes, each in a step of
;;; its own, as in the details and as in the editor maximized: typing (and
;;; Backspace) at the start, the middle and the end, Delete, everything
;;; selected and deleted. Each against the same in an empty text, in the
;;; same window: a keystroke's text work depends on the rows in view, so
;;; it costs what the empty one does, plus drawing the rows of text it
;;; shows. A jump far ahead, Ctrl+End or a paste of the whole text,
;;; computes the rows up to its target once (printed, with a looser
;;; budget). Every case is measured in three rounds, each round all of
;;; them, and keeps its least: a load on the machine that slows a round
;;; leaves the others. The budgets are what it may cost over the empty
;;; text's, in ms: a frame costs too little now for a ratio to mean much.

(define (long-text which n width)
  (let ([o (open-output-string)]
        [words '#("the " "quick " "brown " "fox " "jumps " "over " "a "
                  "lazy " "dog " "keystroke ")]
        [fits? (lambda (s) (<= (text-width s 'ui) width))])
    (define (put! s len) (put-string o s) (+ len (string-length s)))
    (let loop ([i 0] [len 0] [row ""])
      (if (>= len n)
          (substring (get-output-string o) 0 n)
          (let ([w (vector-ref words (mod (* i 7) 10))])
            (case which
              [(words) (loop (+ i 1) (put! w len) row)]
              [(none) (loop (+ i 1) (put! (number->string (* i 7919) 16) len)
                            row)]
              [else   ; words while they fit, the last grown to fill the row
               (if (fits? (string-append
                           row (substring w 0 (- (string-length w) 1))))
                   (loop (+ i 1) len (string-append row w))
                   (let grow ([r (substring row 0 (- (string-length row) 1))])
                     (if (fits? (string-append r "x"))
                         (grow (string-append r "x"))
                         (loop i (put! (string-append r " ") len) ""))))]))))))

;; Steps, each handling the next of keys (event lists, in turn): the
;; median main-thread ms of the steps at each place in the turn.
(define (key-turns keys turns)
  (steps 2 0)
  (let loop ([i 0] [times (map (lambda (k) '()) keys)])
    (if (= i (* turns (length keys)))
        (map median times)
        (let ([m0 (main-ms)] [j (mod i (length keys))])
          (apply inject! (list-ref keys j))
          (schevana-step! 0)
          (let ([dt (- (main-ms) m0)])
            (loop (+ i 1)
                  (map (lambda (ts k) (if (= k j) (cons dt ts) ts))
                       times (iota (length keys)))))))))

(define type-keys '(((text "a")) ((key-down backspace ()))))

(define long-text-rounds 3)

(define (long-text-bench)
  (screen! 1920 1080 200)
  (clear-world!)
  (fixed-status!)
  (tasks-reset!)
  (let* ([win (tasks)] [v (window-ref win 'state)] [tui (window-ref win 'ui)]
         [title (long-text 'words 65535 1000)]
         [t (add-task! title 'status 'review)]
         [texts (make-hashtable equal-hash equal?)])   ; made once a case
    ;; the text, its caret at k, in the details or the editor: its window
    ;; and ui, the text's id, and its width
    (define (show! where text k)
      (tasks-close-editor! v)
      (set-task! t 'description text)
      (tasks-select! v t)
      (ui-focus! tui #f)
      (ui-forget! tui 'description)
      (steps 1 0)
      (case where
        [(details)
         (ui-focus! tui 'description k)
         (invalidate! win)
         (steps 2 0)
         (values win tui 'description)]
        [else
         (let ([ed (tasks-open-editor! v t k)])
           (maximize-window! ed)
           (steps 2 0)
           (values ed (window-ref ed 'ui) 'text))]))
    (define (width where)
      (let-values ([(w ui id) (show! where "" 0)])
        (let ([r (ui-find ui id)])
          (list-ref (car (ui-text-box-areas 0 0 (ui-region-w r) 0 '())) 3))))
    (define (run where which)
      (let* ([text (or (hashtable-ref texts (cons where which) #f)
                       (let ([s (if (eq? which 'empty)
                                    ""
                                    (long-text which 65535 (width where)))])
                         (hashtable-set! texts (cons where which) s)
                         s))]
             [n (string-length text)]
             [at (lambda (k keys)
                   (show! where text k)
                   (key-turns keys 10))]
             [typing (apply max (map (lambda (k) (apply max (at k type-keys)))
                                     (list 0 (quotient n 2) n)))]
             [delete (car (at (quotient n 2)
                              '(((key-down delete ())) ((text "a"))
                                ((key-down left ())))))]
             [all (begin (clipboard-set! text)
                         (at n '(((key-down #\a (ctrl)))
                                 ((key-down backspace ()))
                                 ((key-down #\v (ctrl))))))]
             [jump (median
                    (map (lambda (i)
                           (show! where text 0)
                           (let ([m0 (main-ms)])
                             (inject! '(key-down end (ctrl)))
                             (schevana-step! 0)
                             (- (main-ms) m0)))
                         (iota 5)))])
        ;; typing, Delete, everything selected and deleted; jumps
        (list where which (max typing delete (car all) (cadr all))
              (max jump (caddr all)))))
    (maximize-window! win)
    (tasks-select! v t)
    (steps 2 17)
    (let* ([cases (apply append
                         (map (lambda (where)
                                (map (lambda (which) (cons where which))
                                     '(empty words none full)))
                              '(details editor)))]
           [rounds (map (lambda (i)
                          (map (lambda (c) (run (car c) (cdr c))) cases))
                        (iota long-text-rounds))])
      (tasks-close-editor! v)
      (close-window! win)
      ;; each case's least keystroke and jump
      (apply map
             (lambda rs
               (list (car (car rs)) (cadr (car rs))
                     (apply min (map caddr rs)) (apply min (map cadddr rs))))
             rounds))))

(define long-text-results (long-text-bench))
(screen! 1280 800 100)
(for-each (lambda (r)
            (printf "a long text in Tasks maximized on 1920x1080 at 200%, ~a, \
                     ~a: a keystroke at most ~,2f ms (main), a jump ~,2f \
                     (the least of ~a rounds)\n"
                    (car r) (cadr r) (caddr r) (cadddr r) long-text-rounds))
          long-text-results)

;;; ------------------------------------------------------------------
;;; a busy process

;; A REPL evaluation that computes (a loop counting) while S30T animates,
;; steps back to back as with a window: its loops a second, as a share of
;; what it gets with the Life windows paused, and the frames a second
;; meanwhile. The frames are drawn on the main thread, between the
;; process's slices. run-procs!' 10 ms budget needs a clock that moves:
;; the fake one goes on with real time, plus 81 ms a step, so every Life
;; window steps at every step.
(define (busy-run pct animate? ms)   ; (values loops a second, frames a second)
  (set-theme! 'scale pct)
  (scene! 'S30T)
  (unless animate?
    (for-each (lambda (w) (window-call w 'key #\space '())) (windows)))
  (steps 2 81)
  (let* ([count 0] [k 0] [n0 *frames-drawn*] [t0 (wall-ms)] [ms0 fake-ms]
         [p (spawn "busy"
                   (lambda ()
                     (let loop () (set! count (fx+ count 1)) (loop))))])
    (fluid-let ([now-ms (lambda ()
                          (+ ms0 (exact (floor (- (wall-ms) t0))) (* 81 k)))])
      (let loop ()
        (when (< (- (wall-ms) t0) ms)
          (set! k (+ k 1))
          (schevana-step! 0)
          (loop)))
      (let ([s (/ (- (wall-ms) t0) 1000.0)] [frames (- *frames-drawn* n0)])
        (kill! p)
        (set! fake-ms (now-ms))
        (values (/ count s) (/ frames s))))))

(define-values (busy-alone busy-idle-fps) (busy-run 200 #f 2000))
(define-values (busy-loops busy-fps) (busy-run 200 #t 2000))
(printf "a busy process while S30T animates at 200%: ~a% of its loops with \
         Life paused, ~,1f frames a second\n"
        (exact (round (* 100.0 (/ busy-loops busy-alone)))) busy-fps)

;;; ------------------------------------------------------------------
;;; the profiler's cost
;;; A step with profiling on and off, in turns of 20 steps, 10 turns
;;; each: S30T animating (the main thread's ms, medians), an idle step
;;; (30 paused Life windows), and a busy process with Life paused (its
;;; loops a second, 1 s each way, twice).

(define profile-cost-was (profile-on?))

(define (profile-cost-steps measure)   ; (values on off): medians
  (let loop ([turn 0] [on '()] [off '()])
    (if (= turn 20)
        (values (median on) (median off))
        (let ([on? (even? turn)])
          (profile-on! on?)
          (steps 2 81)
          (let ([ms (map (lambda (i) (measure)) (iota 20))])
            (if on?
                (loop (+ turn 1) (append ms on) off)
                (loop (+ turn 1) on (append ms off))))))))

(define (profile-cost-frames pct)
  (set-theme! 'scale pct)
  (scene! 'S30T)
  (profile-cost-steps (lambda ()
                        (let ([m0 (main-ms)]) (steps 1 81) (- (main-ms) m0)))))

(define (profile-cost-idle)
  (set-theme! 'scale 100)
  (scene! 'S30)
  (for-each (lambda (w) (window-call w 'key #\space '())) (windows))
  (steps 3 0)
  (profile-cost-steps (lambda ()
                        (let ([w0 (wall-ms)]) (schevana-step! 0)
                          (- (wall-ms) w0)))))

(newline)
(for-each
 (lambda (pct)
   (let-values ([(on off) (profile-cost-frames pct)])
     (printf "profiling's cost, S30T at ~a%: a step on ~,3f ms, off ~,3f ms \
              (~,1f%)\n"
             pct on off (* 100 (/ (- on off) off)))))
 '(100 200))
(let-values ([(on off) (profile-cost-idle)])
  (printf "profiling's cost, an idle step: on ~,4f ms, off ~,4f ms\n" on off))
(let* ([runs (map (lambda (on?)
                    (profile-on! on?)
                    (let-values ([(loops fps) (busy-run 100 #f 1000)]) loops))
                  '(#t #f #t #f))]
       [on (+ (car runs) (caddr runs))] [off (+ (cadr runs) (cadddr runs))])
  (printf "profiling's cost, a busy process: on ~a, off ~a loops a second \
           (~,1f%)\n"
          (exact (round (/ on 2))) (exact (round (/ off 2)))
          (* 100 (/ (- on off) off))))
(profile-on! profile-cost-was)

(define failures 0)
(define (assert! name ok)
  (unless ok (set! failures (+ failures 1)))
  (printf "~a ~a\n" (if ok "ok  " "FAIL") name))

;;; ------------------------------------------------------------------
;;; the crew: Life at one pixel a cell, Boids at its largest

;; Steps of Life, maximized on a 1920 × 1080 screen at 200% (a 4K one), one
;; pixel a cell, a generation every tick, its controls hidden; of them, the
;; tick's ms and the rest's (its frame and upload).
(define (life-extreme workers n)
  (clear-world!)
  (crew-size-set! workers)
  (let ([win (life)])
    (toggle-maximize! win)
    (steps 1 0)
    (let* ([ui (window-ref win 'ui)]
           [slide! (lambda (id frac)
                     (let* ([r (ui-find ui id)]
                            [x (+ (ui-region-x r) 8
                                  (* frac (- (ui-region-w r) 16)))]
                            [y (+ (ui-region-y r) (/ (ui-region-h r) 2))])
                       (window-call win 'mouse-down x y 'left 1)
                       (window-call win 'mouse-up x y 'left)))]
           [speeds (top-level-value 'life-speeds
                                    (env-environment (grant-env 'life)))])
      (slide! 'cell 0)
      (slide! 'speed (/ (- (length speeds) 2) (- (length speeds) 1)))
      (window-call win 'key #\h '())
      (steps 3 0)
      (let ([tick-total 0] [real wm-tick!] [t0 (wall-ms)])
        (fluid-let ([wm-tick! (lambda ()
                                (let ([t (wall-ms)])
                                  (real)
                                  (set! tick-total
                                        (+ tick-total (- (wall-ms) t)))))])
          (steps n 0))
        (let ([all (/ (- (wall-ms) t0) n)] [tick (/ tick-total n)])
          (values tick (- all tick)))))))

(let ([size (crew-size)])
  (screen! 1920 1080 200)
  (for-each
   (lambda (workers n)
     (let-values ([(tick rest) (life-extreme workers n)])
       (printf "Life at one pixel a cell, maximized on 1920x1080 at 200%, \
                on ~a thread~:p: a generation ~,1f ms, its frame and upload \
                ~,1f ms\n" (+ workers 1) tick rest)))
   '(0 8 47)
   '(10 50 50))
  (screen! 1280 800 100)
  (clear-world!)
  (crew-size-set! size))

(let* ([box (env-environment (grant-env 'boids))]
       [step-on (top-level-value 'boids-step-on box)]
       [scatter (top-level-value 'boids-scatter box)]
       [rules (top-level-value 'boids-default-rules box)]
       [size (crew-size)])
  (for-each
   (lambda (n)
     (let* ([flock (scatter n 1200 700)]
            [time-it (lambda (workers k)
                       (crew-size-set! workers)
                       (step-on flock rules 1200 700)
                       (let ([t0 (wall-ms)])
                         (do ([i 0 (+ i 1)]) ((= i k))
                           (step-on flock rules 1200 700))
                         (/ (- (wall-ms) t0) k)))]
            [one (time-it 0 10)]
            [crew (time-it 8 50)])
       (printf "Boids, ~a of them: a step ~,2f ms on one thread, ~,2f ms on \
                nine\n" n one crew)))
   '(150 450 2000 5000))
  (crew-size-set! size))

(newline)
(assert! "every measured step drew a frame"
         (for-all (lambda (r) (= frames (plist-ref r 'drawn #f))) results))
(assert! (format
          "an idle step takes under 0.2 ms (~,3f, ~,3f) and uploads nothing"
          idle-100 idle-200)
         (and (< (max idle-100 idle-200) 0.2) (= 0 idle-up-100 idle-up-200)))
(assert! (format "with Tasks open and nothing focused, an idle step takes \
                  under 0.2 ms (~,3f) and uploads nothing" tasks-idle)
         (and (< tasks-idle 0.2) (= 0 tasks-idle-up)))
(let ([budget
       (lambda (where key most)
         (let ([empty (key (find (lambda (r) (and (eq? (car r) where)
                                                  (eq? (cadr r) 'empty)))
                                 long-text-results))])
           (for-all (lambda (r)
                      (or (not (eq? (car r) where))
                          (<= (- (key r) empty) most)))
                    long-text-results)))])
  (assert! "a keystroke in a long text's worst cases costs at most 1 ms more \
            than in an empty text in the details, 2 ms in the editor \
            maximized (drawing its screenful of rows), and a jump at most \
            10 ms more"
           (and (budget 'details caddr 1) (budget 'editor caddr 2)
                (budget 'details cadddr 10) (budget 'editor cadddr 10))))
(assert! "a step of the Tree with 2,000 tasks more, in chains, costs at most \
          1.5 times one with the seed: a key, Space and the wheel"
         (let ([seed (cdr (assq 'seed tree-results))]
               [chained (cdr (assq 'chained tree-results))])
           (for-all (lambda (k) (<= (list-ref chained k)
                                    (* 1.5 (list-ref seed k))))
                    '(0 1 2))))
(assert! "a busy process and S30T's animation both go on"
         (and (> busy-loops 0) (> busy-fps 1)))
(printf "S30T main per frame: ~,2f ms at 100%, ~,2f ms at 200%\n"
        (plist-ref (result 'S30T 100) 'main #f)
        (plist-ref (result 'S30T 200) 'main #f))
(printf "~a\n" (if (zero? failures)
                   "all assertions hold"
                   (format "~a assertion(s) FAILED" failures)))
(exit (if (zero? failures) 0 1))
