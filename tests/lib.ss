;;; tests/lib.ss — what the suites share, loaded once a suite has found the
;;; tree's root (*schevana-root*): the world loaded but not booted, the
;;; tests' reach into the core (tests/reach.ss), the scratch files, the
;;; checks and the verdict. Each suite boots the world itself, as it needs.
;;; The library edition's, or with SCHEVANA_HACKER set the hacker
;;; edition's (src/hacker.ss), where the tests have every name already.
;;;
;;;   (load (string-append *schevana-root* "/tests/lib.ss"))
;;;   ... checks ...
;;;   (test-verdict!)

;; The world, loaded but not booted, and the tests' reach.
(load (string-append *schevana-root* "/tests/boot.ss"))

;; A library evaluated again, and what imports it, as a reload does when
;; its file changed, in either edition: => the libraries evaluated again.
(define (test-reload-library! name)
  (if test-hacker?
      ((eval 'hacker-reload-libraries!) (source-held-libraries) name)
      (reload-libraries! (source-held-libraries) name)))

;; The launchers at the tree's root, schevana-desktop and the demos', each
;; a program of a few lines (src/launch.ss).
(define test-launchers
  (filter (lambda (f)
            (and (string-prefix? "schevana-" f)
                 (not (file-directory? (string-append *schevana-root* "/" f)))))
          (sort string<? (directory-list *schevana-root*))))

;; The libraries below the world, under schevana/: core0's, the
;; recorder's and the core's, and those they stand on, by the layer each
;; declares, in file-name order; each a path from the tree's root.
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

;; Where a run writes: its first argument, else here.
(define out-dir
  (if (pair? (command-line-arguments)) (car (command-line-arguments)) "."))

;; Never touch the user's real theme file.
(set! *theme-file-path* (string-append out-dir "/theme.ss"))
(when (file-exists? *theme-file-path*) (delete-file *theme-file-path*))

;; A run whose heap passes 2 GB has run away (a loop that allocates without
;; end): it stops, as a failure, before the machine runs out, as forty
;; topics run at once. A thread of its own looks, for one that runs away
;; never comes back to a check, and the shell ends the process, as exit
;; from a thread ends only the thread. A run's heap is a few hundred MB.
(define test-heap-limit
  (* 1024 1024
     (or (string->number (or (getenv "SCHEVANA_TEST_HEAP_MB") "")) 2048)))
(fork-thread
 (lambda ()
   (let loop ()
     (sleep (make-time 'time-duration 100000000 0))
     (if (> (bytes-allocated) test-heap-limit)
         (begin
           (fprintf (console-error-port)
                    "FAIL the heap passed ~a MB: a runaway, stopped~%"
                    (quotient test-heap-limit (* 1024 1024)))
           (flush-output-port (console-error-port))
           (system "kill -KILL $PPID"))
         (loop)))))

;; The crew's limit on core1 ((schevana services crew)) is 100 ms of the
;; machine's clock, for runaways. A busy machine keeps a worker waiting longer
;; than that in the middle of an ordinary call, and the caller then raises as
;; for a runaway: so the limit is long in every suite, and the crew's own topic
;; checks it, at what it is, with a call that never ends.
(define test-crew-budget crew-core1-ms)
(set! crew-core1-ms 60000)

(define failures 0)

;; With SCHEVANA_CHECK set, a run stops after the first check whose name
;; has its text: what ran before it is what a whole run runs, so the check
;; sees what it would there, and the run's verdict is theirs. A long name,
;; and one left empty means none, lest a stray one end every run early.
(define test-only
  (let ([text (getenv "SCHEVANA_CHECK")])
    (and text (not (string=? text "")) text)))
(define (test-only-done name)
  (when (and test-only (string-contains-ci? name test-only))
    (printf "stopped after the check SCHEVANA_CHECK names\n")
    (exit (if (zero? failures) 0 1))))

(define-syntax check
  (syntax-rules ()
    [(_ name expr)
     (let ([ok (guard (c [#t (printf "  error: ~a\n" (condition->string c))
                             #f])
                 expr)])
       (unless ok (set! failures (+ failures 1)))
       (printf "~a ~a\n" (if ok "ok  " "FAIL") name)
       (test-only-done name))]))

;; A form outside a check that raises fails, at its line, and the suite goes
;; on with the next: a region a font leaves out of view ends only what needs
;; it. What the form itself loads or evaluates (an app, a reload) raises as
;; it would. A suite turns it on with (current-eval test-form-eval) once
;; it has booted, or loads a file through it.
(define test-form-running #f)
(define test-form-eval
  (let ([eval* (current-eval)])
    (lambda (x . env)
      (if test-form-running
          (apply eval* x env)
          (guard (c [#t (set! failures (+ failures 1))
                        (printf "FAIL a form at ~a raised: ~a\n"
                                (test-form-place x) (condition->string c))])
            (fluid-let ([test-form-running #t]) (apply eval* x env)))))))

;; Where the loader read x: "tests/smoke.ss:120".
(define (test-form-place x)
  (or (and (annotation? x)
           (call-with-values
            (lambda ()
              (locate-source-object-source (annotation-source x) #t #t))
            (case-lambda
              [(path line char) (format "~a:~a" path line)]
              [r #f])))
      "a line not known"))

;; The test's clock: the world's milliseconds (now-ms, by which timers,
;; tooltips and carets go) held still, moving only when a test says, so a
;; delay is the same on any machine. now-ns stays the machine's: the pacer
;; and the profiler go by it. test-clock-ms is the time held, or #f while
;; the clock goes as the machine's; released, it goes on from where it was
;; held, the machine's plus what was skipped, so the world's time never
;; runs back.
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

;; The held clock, read. What waits for it to move waits forever: a process
;; that never yields runs till its share of a step is up by this clock
;; (run-procs!), collections held off meanwhile, until the machine is out
;; of memory. So a tick of the world's that reads it a hundred thousand
;; times fails the run, once, and from then on the clock moves a ms a
;; read till it's held anew, which ends such a wait.
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

;; The world's loop, n times, each after the held clock moves on ms.
(define (steps n . ms)
  (do ([i 0 (+ i 1)]) ((= i n))
    (when (pair? ms) (test-clock-advance! (car ms)))
    (schevana-step! 0)))

;; pred's first true value as the world goes on, a step each 5 ms, for up
;; to ms of the clock, held or the machine's; #f if it never is.
(define (test-wait ms pred)
  (if test-clock-ms
      (let loop ([left ms])
        (or (pred)
            (and (> left 0) (begin (steps 1 5) (loop (- left 5))))))
      (let ([until (+ (now-ms) ms)])
        (let loop ()
          (or (pred)
              (and (< (now-ms) until)
                   (begin (schevana-step! 5) (loop))))))))

(define (raises? thunk) (guard (c [#t #t]) (thunk) #f))

;; Text typed and a key pressed, as the screen would send them; not
;; stepped.
(define (test-type! str)
  (for-each (lambda (c) (inject! (list 'text (string c)))) (string->list str)))
(define (test-press! key . mods) (inject! (list 'key-down key mods)))

;; thunk's value, cleanup run after it, raise or not: what a sequence
;; changed for itself it changes back, so a failure takes only its own.
(define (test-finally thunk cleanup)
  (let ([v (guard (c [#t (cleanup) (raise c)]) (thunk))])
    (cleanup)
    v))

;; Region id of ui, as the last layout left it; a region not laid out
;; (out of view, or never drawn) fails the check it's in, by its id.
(define (test-region ui id)
  (or (ui-find ui id)
      (errorf 'test-region "no region ~s laid out" id)))

;; A window of kit widgets drawn by draw (ui w h), size (w . h) if given,
;; then an app's handlers as ui-handlers takes them ('key (win key mods)):
;; one widget, or a few, by themselves, as a widget's topic tests them. Its
;; ui is (window-ref win 'ui).
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

;; Region id of win's ui: its middle on the screen, dx to its right, or at
;; x within it (a number from the region's left) if given as 'at x; whole
;; pixels, whatever fractions the region is laid at.
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

;; The pointer moved over region id (test-point's dx), a step.
(define (test-move! win id . dx)
  (let-values ([(x y) (apply test-point win id dx)])
    (inject! `(mouse-move ,x ,y))
    (steps 1)))

;; A left click on region id, clicks times at once (2: a double click),
;; at test-point's dx; a step.
(define (test-click! win id . more)
  (let ([clicks (if (and (pair? more) (fixnum? (car more))) (car more) 1)]
        [dx (if (and (pair? more) (fixnum? (car more))) (cdr more) more)])
    (let-values ([(x y) (apply test-point win id dx)])
      (do ([k 1 (+ k 1)]) ((> k clicks))
        (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left ,k)
                 `(mouse-up ,x ,y left)))
      (steps 1))))

;; Wheels win's scroll view view (its region's id) until region id is
;; whole in it, so that a press on it lands with any font; a step each
;; notch, 40 at most.
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

;; Clicks the open menu's entry that starts with label, where menu-areas
;; puts it; a step or two.
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

;; thunk with status segments that never change, so the top bar stays put.
(define (test-with-quiet-status thunk)
  (let ([segs *status-segments*])
    (set! *status-segments* (list (cons 'quiet (lambda () "quiet"))))
    (steps 2)
    (let ([v (thunk)])
      (set! *status-segments* segs)
      (steps 1)
      v)))

;; The world as a scene starts from: no window, toast, hover, drag or menu.
(define (test-clear-world!)
  (for-each close-window! (windows))
  (set! *toasts* '())
  (set! *cascade* 0)
  (set! *hover* #f)
  (set! *drag* #f)
  (when (menu-open?) (close-menu!)))

;; A scene: thunk from a cleared world, its own state set by itself; one
;; that raises fails by its name, and the next starts afresh.
(define (test-scene name thunk)
  (test-clear-world!)
  (guard (c [#t (set! failures (+ failures 1))
                (printf "FAIL the scene ~a raised: ~a\n" name
                        (condition->string c))])
    (thunk)))

;; The run's end: its verdict, and its exit status, 1 if a check failed or
;; SCHEVANA_CHECK named none.
(define (test-verdict!)
  (when test-only
    (printf "no check's name has ~s\n" test-only)
    (exit 1))
  (printf "~a\n" (if (zero? failures)
                     "all checks passed"
                     (format "~a check(s) FAILED" failures)))
  (exit (if (zero? failures) 0 1)))
