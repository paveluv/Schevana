;;; tests/check.ss — what a run of checks needs, without the world: the
;;; folder it writes to, the watch on its heap, the checks, a failure for a
;;; form that raises (at its line), and the run's verdict. tests/lib.ss
;;; loads it for the suites, once the world is loaded; a focused topic
;;; (tests/units.ss) loads it alone, after its libraries and the basics
;;; (src/base.ss).
;;;
;;;   (load (string-append *schevana-root* "/tests/check.ss"))
;;;   (check "one is one" (= 1 1))
;;;   (test-verdict!)

;; The folder a run writes to: its first argument, or else the current
;; folder.
(define out-dir
  (if (pair? (command-line-arguments)) (car (command-line-arguments)) "."))

;; A run whose heap passes 2 GB (or SCHEVANA_TEST_HEAP_MB) has run away,
;; in a loop that allocates without end. It stops as a failure before the
;; machine runs out of memory, since forty topics may run at once. A
;; thread of its own watches, because a run that has run away never comes
;; back to a check, and a shell kills the process, because exit from a
;; thread ends only that thread. A normal run's heap is a few hundred MB.
(define test-heap-limit
  (* 1024 1024
     (or (string->number (or (getenv "SCHEVANA_TEST_HEAP_MB") "")) 2048)))

;; Made once, so that a look allocates nothing. Chez counts a thread's
;; allocation in every thread's bytes-allocated, a 16 KB segment at a time
;; as the thread takes one, so a time made at each look (48 bytes) added
;; 16 KB to whatever step a check was measuring, once every 34 s.
(define test-heap-nap (make-time 'time-duration 100000000 0))

;; One look of the watch, 100 ms after the last. Returns #f once it has
;; stopped the run.
(define (test-heap-look)
  (sleep test-heap-nap)
  (or (<= (bytes-allocated) test-heap-limit)
      (begin
        (fprintf (console-error-port)
                 "FAIL the heap passed ~a MB: a runaway, stopped~%"
                 (quotient test-heap-limit (* 1024 1024)))
        (flush-output-port (console-error-port))
        (system "kill -KILL $PPID")
        #f)))

(fork-thread
 (lambda ()
   (let loop ()
     (when (test-heap-look) (loop)))))

(define failures 0)

;; With SCHEVANA_CHECK set, a run stops after the first check whose name
;; contains its text (ignoring case). Everything before that check runs as
;; in a whole run, so the check sees what it would see there, and the
;; verdict is that of the checks run so far. The variable has a long name,
;; and an empty one counts as unset, so that a stray setting doesn't end
;; every run early.
(define test-only
  (let ([text (getenv "SCHEVANA_CHECK")])
    (and text (not (string=? text "")) text)))
(define (test-only-done name)
  (when (and test-only (string-contains-ci? name test-only))
    (printf "stopped after the check SCHEVANA_CHECK names\n")
    (exit (if (zero? failures) 0 1))))

;; What a check does after it runs: with the world, the collector's look
;; (tests/lib.ss); without it, nothing.
(define (test-collector-look!) (void))

(define-syntax check
  (syntax-rules ()
    [(_ name expr)
     (let ([ok (guard (c [#t (printf "  error: ~a\n" (condition->string c))
                             #f])
                 expr)])
       (unless ok (set! failures (+ failures 1)))
       (printf "~a ~a\n" (if ok "ok  " "FAIL") name)
       (test-collector-look!)
       (test-only-done name))]))

;; A form outside a check that raises counts as a failure at its line,
;; and the suite goes on with the next form: a region that a font leaves
;; out of view fails only the forms that need it. What the form itself
;; loads or evaluates (an app, a reload) raises as usual. A suite turns
;; this on with (current-eval test-form-eval) once it has booted, or loads
;; a file through it.
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

;; Returns where the loader read x, as "tests/smoke.ss:120".
(define (test-form-place x)
  (or (and (annotation? x)
           (call-with-values
            (lambda ()
              (locate-source-object-source (annotation-source x) #t #t))
            (case-lambda
              [(path line char) (format "~a:~a" path line)]
              [r #f])))
      "a line not known"))

(define (raises? thunk) (guard (c [#t #t]) (thunk) #f))

;; Returns thunk's value, and runs cleanup after it whether or not it
;; raises: a sequence changes back what it changed for itself, so a
;; failure affects only its own checks.
(define (test-finally thunk cleanup)
  (let ([v (guard (c [#t (cleanup) (raise c)]) (thunk))])
    (cleanup)
    v))

;; Ends the run: prints its verdict and exits with status 1 if a check
;; failed or SCHEVANA_CHECK matched no check's name, else 0.
(define (test-verdict!)
  (when test-only
    (printf "no check's name has ~s\n" test-only)
    (exit 1))
  (printf "~a\n" (if (zero? failures)
                     "all checks passed"
                     (format "~a check(s) FAILED" failures)))
  (exit (if (zero? failures) 0 1)))
