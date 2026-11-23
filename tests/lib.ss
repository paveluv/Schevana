;;; tests/lib.ss — what the suites share, loaded once a suite has found
;;; the tree's root (*schevana-root*): the world, loaded but not booted,
;;; the tests' reach into the core (tests/reach.ss), the scratch files, the
;;; checks and the verdict. Each suite boots the world itself, as it needs
;;; it. The world is the library edition's, or with SCHEVANA_HACKER set the
;;; hacker edition's (src/hacker.ss), where the tests have every name
;;; already.
;;;
;;;   (load (string-append *schevana-root* "/tests/lib.ss"))
;;;   ... checks ...
;;;   (test-verdict!)

;; The world, loaded but not booted, and the tests' reach.
(load (string-append *schevana-root* "/tests/boot.ss"))

;; Loads the demos named into the world now, as the desktop loads the
;; folder it is given (./desktop demo): the tests' world has no demos but
;; the ones a test uses. (test-demos! 'life 'sketch)
(define (test-demos! . names)
  (load-sources! (map (lambda (name) (list 'demo name)) names)))

;; Gives up the rest of the calling process's slice.
(define (test-yield) (when (current-proc) (engine-block)))

;; Whether a menu is open.
(define (test-menu-open?) (and *menu* #t))

;; Returns the screen as it would be drawn now: its pixels, row after row,
;; in premultiplied BGRA, as a screenshot sees them.
(define (test-screen-bytes)
  (drawing->bytes *canvas-pw* *canvas-ph* *canvas-ratio* record-world! #f))

;; Writes what the screen shows now to a PNG file at path; returns path.
(define (test-png-write-screen path)
  (png-write path (test-screen-bytes) (canvas-pixel-width)
             (canvas-pixel-height))
  path)

;; Returns the ms of phase (one of profile-phase-names) in tick seq, as
;; the profiler keeps it.
(define (test-tick-phase-ms seq phase)
  (profile-ms (profile-phase-ns *profile-ticks-ring* seq phase)))

;; Gives Tasks the demos' backlog ((demo backlog)) as that demo enters it:
;; the first call loads the demo, and each later one gives Tasks a copy of
;; the tasks it entered, ids and all, in place of the tasks there, for a
;; test to start from. Returns how many tasks it holds.
(define test-backlog #f)   ; (next-id task ...), as the demo left them
(define (test-backlog!)
  (define (copy t)
    (make-task (task-id t) (task-title t) (task-description t)
               (task-status t) (task-kind t) (task-priority t)
               (task-assignee t) (task-tags t) (task-due t)
               (map (lambda (i) (cons (car i) (cdr i))) (task-checklist t))
               (task-blocked-by t) (task-created t) (task-updated t)))
  (unless test-backlog
    (test-demos! 'backlog)
    (set! test-backlog (cons *tasks-next-id* (map copy *tasks*))))
  (set! *tasks* (map copy (cdr test-backlog)))
  (set! *tasks-next-id* (car test-backlog))
  (tasks-changed!)
  (length *tasks*))

;; Evaluates library name again, with every library that imports it, as a
;; reload does when its file has changed, in either edition. Returns the
;; libraries evaluated again.
(define (test-reload-library! name)
  (if test-hacker?
      ((eval 'hacker-reload-libraries!) (source-held-libraries) name)
      (reload-libraries! (source-held-libraries) name)))

;; The programs at the tree's root: the launchers (the desktop's and the
;; demos', each a program of a few lines that loads src/launch.ss) and the
;; window demo's script. That is, each file there that starts with #! or
;; ends in .ss.
(define test-launchers
  (filter (lambda (f)
            (let ([path (string-append *schevana-root* "/" f)])
              (and (not (file-directory? path))
                   (or (string=? (path-extension f) "ss")
                       (call-with-input-file path
                         (lambda (p)
                           (and (eqv? (read-char p) #\#)
                                (eqv? (read-char p) #\!))))))))
          (sort string<? (directory-list *schevana-root*))))

;; The libraries below the world, under schevana/: core0's, the
;; recorder's and the core's, and the foundation they stand on, chosen by
;; the layer each declares, in file-name order, each as a path from the
;; tree's root.
(define test-core-libraries
  (let walk ([dir "schevana"])
    (apply append
           (map (lambda (f)
                  (let* ([path (string-append dir "/" f)]
                         [full (string-append *schevana-root* "/" path)])
                    (cond
                      [(file-directory? full) (walk path)]
                      [(and (string=? (path-extension f) "sls")
                            (let ([decl (assq 'library-layer
                                              (filter pair?
                                                      (cddddr
                                                       (call-with-input-file
                                                         full read))))])
                              (and decl
                                   (memq (cadr decl)
                                         '(foundation core0 recorder
                                           core)))))
                       (list path)]
                      [else '()])))
                (sort string<?
                      (directory-list
                       (string-append *schevana-root* "/" dir)))))))

;; The checks and the run's verdict, which need no world (tests/check.ss).
(load (string-append *schevana-root* "/tests/check.ss"))

;; Never touch the user's real theme file.
(set! *theme-file-path* (string-append out-dir "/theme.ss"))
(when (file-exists? *theme-file-path*) (delete-file *theme-file-path*))

;; The crew's limit on core1 ((schevana services crew)) is 100 ms of the
;; machine's clock, to catch runaways. A busy machine can keep a worker
;; waiting longer than that in the middle of an ordinary call, and the
;; caller then raises as if for a runaway. So the limit is long in every
;; suite, and the crew's own topic checks it, at its real value, with a
;; call that never ends.
(define test-crew-budget crew-core1-ms)
(set! crew-core1-ms 60000)

;; The collector looks at the older generations (collector-tick!) as the
;; world's loop steps, at most once every 500 ms of the clock. Under the
;; held clock it would never look, and what outlives a young collection
;; would pile up, gigabytes of it. So the tests stand in for the look:
;; while the clock is held, it goes through each time the world takes it,
;; as if the clock had moved on. It collects what the world would by its
;; own measure; and once the heap is past half the run's limit, it
;; collects every generation, so that garbage doesn't stop the run (while
;; busy, the world lets the old generations grow by 512 MB, and a test's
;; pictures to compare are 37 MB each at 300 %). The stand-in is a
;; procedure of the top level, which carries nothing, as the world's own
;; look carries nothing (tests/units/allocation.ss).
(define test-real-collector-tick! collector-tick!)
(define (test-collector-tick!)
  (when test-clock-ms (set! *collector-check-ms* 0))
  (test-real-collector-tick!)
  (when (> (bytes-allocated) (quotient test-heap-limit 2))
    (collector-pass! 3 3)
    (set! *collector-old-kept* (collector-grown))))
(set! collector-tick! test-collector-tick!)

;; The collector's look, taken right after each check (tests/check.ss): a
;; test that never steps the world never lets the world take it.
(define (test-collector-look!)
  (set! *collector-check-ms* 0)
  (collector-tick!))

;; The test's clock: the world's milliseconds (now-ms, which timers,
;; tooltips and carets go by) held still, moving only when a test says so,
;; so that a delay is the same on any machine. now-ns stays the machine's,
;; since the pacer and the profiler go by it. test-clock-ms is the time
;; held, or #f while the clock runs with the machine's. Once released, the
;; clock goes on from where it was held (the machine's time plus what was
;; skipped), so the world's time never runs backward.
(define test-real-now-ms now-ms)
(define test-clock-ms #f)
(define test-clock-skipped 0)
(define (test-clock-hold! . at)
  (set! test-clock-ms (if (pair? at) (car at) (now-ms)))
  (set! test-clock-stuck? #f)
  (set! now-ms test-clock-read))
(define (test-clock-release!)
  (when test-clock-ms
    (set! test-clock-skipped (max 0 (- test-clock-ms (test-real-now-ms))))
    (set! test-clock-ms #f)
    (set! now-ms (lambda () (+ (test-real-now-ms) test-clock-skipped)))))
(define (test-clock-advance! ms)
  (when test-clock-ms (set! test-clock-ms (+ test-clock-ms ms))))

;; Reads the held clock. Whatever waits for it to move waits forever: a
;; process that never yields runs until its share of a step is up by this
;; clock (run-procs!), with collections held off in the meantime, until
;; the machine runs out of memory. So a tick of the world's that reads the
;; clock 100,000 times fails the run, once, and from then on the clock
;; moves 1 ms per read until it is held again, which ends such a wait.
(define test-clock-reads 0)
(define test-clock-tick #f)
(define test-clock-stuck? #f)
(define (test-clock-read)
  (let ([tick (pacer-ticks)])
    (if (eqv? tick test-clock-tick)
        (set! test-clock-reads (+ test-clock-reads 1))
        (begin (set! test-clock-tick tick) (set! test-clock-reads 0))))
  (when (and (> test-clock-reads 100000) (not test-clock-stuck?))
    (set! test-clock-stuck? #t)
    (set! failures (+ failures 1))
    (printf "FAIL the held clock is not waited for: a tick of the world's \
             read it 100,000 times (a process that never yields?)\n"))
  (when test-clock-stuck? (set! test-clock-ms (+ test-clock-ms 1)))
  test-clock-ms)

;; Returns the words that a stream (the widget kit's) holds for moment
;; seq, read back from the GPU now.
(define (test-stream-row s seq)
  (let ([at (* (ui-stream-words s) (modulo seq (ui-stream-rows s)))]
        [bytes (gpu-buffer-read! (ui-stream-buffer s))])
    (map (lambda (j) (bytevector-s32-native-ref bytes (* 4 (+ at j))))
         (iota (ui-stream-words s)))))

;; How a test steps the world (tests/GUIDE.md). Core1's loop paces its
;; steps (schevana-step!): a step ticks only when a tick is wanted and due
;; (pacer-start), after waiting for it, and its processes run until the
;; next tick's frame must be drawn (pacer-procs-ms). A test steps the
;; world itself, each step a tick with no wait, as a screen ready for
;; every frame at once would have it. A test's step asks for a tick, as
;; input does, and the test makes the pacer's two decisions for the step:
;; the tick is due now, and the processes get 10 ms, the most the pacer
;; gives, since the next tick comes when the test steps again. These are
;; set for the step and put back after it, not by fluid-let: a process
;; first run in the step would keep the fluid-let's dynamic-wind, and wind
;; the test's values in again at every turn.
(define (test-tick-due) 0)
(define (test-procs-ms) 10)

;; One step of the world, a tick (except while a reload holds ticks back),
;; after waiting up to wait-ms for the screen's events (or not at all).
;; What it stood in for is put back, unless a reload in the step defined
;; it anew.
(define (test-step! . wait-ms)
  (let ([start pacer-start] [procs-ms pacer-procs-ms])
    (frame-turn-soon!)
    (set! pacer-start test-tick-due)
    (set! pacer-procs-ms test-procs-ms)
    (schevana-step! (if (pair? wait-ms) (car wait-ms) 0))
    (when (eq? pacer-start test-tick-due) (set! pacer-start start))
    (when (eq? pacer-procs-ms test-procs-ms) (set! pacer-procs-ms procs-ms))))

;; Runs n steps of the world, each after the held clock moves on by ms (if
;; given).
(define (steps n . ms)
  (do ([i 0 (+ i 1)]) ((= i n))
    (when (pair? ms) (test-clock-advance! (car ms)))
    (test-step!)))

;; Returns pred's first true value as the world goes on, a step each 5 ms,
;; for up to ms of the clock (the held one or the machine's); #f if pred
;; never returns true.
(define (test-wait ms pred)
  (if test-clock-ms
      (let loop ([left ms])
        (or (pred)
            (and (> left 0) (begin (steps 1 5) (loop (- left 5))))))
      (let ([until (+ (now-ms) ms)])
        (let loop ()
          (or (pred)
              (and (< (now-ms) until)
                   (begin (test-step! 5) (loop))))))))

;; Types text and presses a key, as the screen would send them, without
;; stepping.
(define (test-type! str)
  (for-each (lambda (c) (inject! (list 'text (string c)))) (string->list str)))
(define (test-press! key . mods) (inject! (list 'key-down key mods)))

;; Returns region id of ui, as the last layout left it. A region that is
;; not laid out (out of view, or never drawn) raises, failing the check it
;; is in, with its id.
(define (test-region ui id)
  (or (ui-find ui id)
      (errorf 'test-region "no region ~s laid out" id)))

;; Opens a window of kit widgets drawn by draw (ui w h), of size (w . h)
;; if given, followed by an app's handlers as ui-handlers takes them ('key
;; (win key mods)): one widget, or a few, by themselves, as a widget's
;; topic tests them. Its ui is (window-ref win 'ui).
(define (test-kit-window title draw . more)
  (let ([ui (make-ui)]
        [size (if (and (pair? more) (pair? (car more)))
                  (car more)
                  '(400 . 200))]
        [app (if (and (pair? more) (pair? (car more))) (cdr more) more)])
    (apply open-window title 'size size 'pos '(300 . 200)
           'draw (lambda (win w h)
                   (ui-begin! ui) (draw ui w h) (ui-end! ui w h))
           (apply ui-handlers ui app))))

;; Returns the point on screen of region id of win's ui: its middle, or dx
;; to the right of that, or x from the region's left if given as 'at x.
;; The point is in whole pixels, whatever fractions the region is laid out
;; at.
(define (test-point win id . dx)
  (let ([r (test-region (window-ref win 'ui) id)])
    (let-values ([(cx cy cw ch) (content-rect win)])
      (values (exact
               (floor (+ cx (ui-region-x r)
                         (if (and (pair? dx) (eq? (car dx) 'at))
                             (cadr dx)
                             (+ (/ (ui-region-w r) 2)
                                (if (pair? dx) (car dx) 0))))))
              (exact (floor (+ cy (ui-region-y r)
                               (/ (ui-region-h r) 2))))))))

;; Moves the pointer over region id (with test-point's dx), then steps.
(define (test-move! win id . dx)
  (let-values ([(x y) (apply test-point win id dx)])
    (inject! `(mouse-move ,x ,y))
    (steps 1)))

;; Left-clicks region id, clicks times in a row (2 for a double click),
;; at test-point's dx, then steps.
(define (test-click! win id . more)
  (let ([clicks (if (and (pair? more) (fixnum? (car more))) (car more) 1)]
        [dx (if (and (pair? more) (fixnum? (car more))) (cdr more) more)])
    (let-values ([(x y) (apply test-point win id dx)])
      (do ([k 1 (+ k 1)]) ((> k clicks))
        (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left ,k)
                 `(mouse-up ,x ,y left)))
      (steps 1))))

;; Turns the wheel over win's scroll view (view is its region's id) until
;; region id is wholly inside it, so that a press on it lands with any
;; font: a step for each notch, 40 at most.
(define (test-show! win view id)
  (let ([ui (window-ref win 'ui)])
    (let loop ([n 0])
      (let* ([v (test-region ui view)] [r (ui-find ui id)]
             [f (and r (ui-region-frame r))]
             [above? (and f (< (cadr f) (ui-region-y v)))]
             [below? (or (not f)
                         (> (+ (cadr f) (cadddr f))
                            (+ (ui-region-y v) (ui-region-h v))))])
        (when (and (< n 40) (or above? below?))
          (let-values ([(x y) (test-point win view)])
            (inject! `(mouse-move ,x ,y) `(wheel 0 ,(if above? 1 -1))))
          (steps 1)
          (loop (+ n 1)))))))

;; Clicks the open menu's entry that starts with label, where
;; placed-menu-areas puts it, then steps twice.
(define (test-menu-click! label)
  (let* ([es (menu-entries *menu*)]
         [i (list-index (lambda (e)
                          (and (pair? e) (string-prefix? label (car e))))
                        es)]
         [a (and i (assv i (placed-menu-areas *menu*)))])
    (unless a (errorf 'test-menu-click! "no entry ~s" label))
    (let ([x (+ (cadr a) 30)] [my (round (+ (caddr a) (/ (list-ref a 4) 2)))])
      (inject! `(mouse-move ,x ,my) `(mouse-down ,x ,my left 1)
               `(mouse-up ,x ,my left))
      (steps 2))))

;; Runs thunk with status segments that never change, so that the top bar
;; stays put, and returns its value.
(define (test-with-quiet-status thunk)
  (let ([segs *status-segments*])
    (set! *status-segments* (list (cons 'quiet (lambda () "quiet"))))
    (steps 2)
    (let ([v (thunk)])
      (set! *status-segments* segs)
      (steps 1)
      v)))

;; Clears the world for a scene to start from: no window, toast, hover,
;; drag, menu or app grid.
(define (test-clear-world!)
  (for-each close-window! (windows))
  (set! *toasts* '())
  (set! *cascade* 0)
  (set! *hover* #f)
  (set! *drag* #f)
  (when (test-menu-open?) (close-menu!))
  (close-app-grid!))

;; Runs a scene: thunk, from a cleared world, setting up its own state. A
;; scene that raises fails under its name, and the next starts afresh.
(define (test-scene name thunk)
  (test-clear-world!)
  (guard (c [#t (set! failures (+ failures 1))
                (printf "FAIL the scene ~a raised: ~a\n" name
                        (condition->string c))])
    (thunk)))
