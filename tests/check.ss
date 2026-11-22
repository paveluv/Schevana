;;; tests/check.ss — what a run of checks needs, and no world: where it
;;; writes, the watch on its heap, the checks, a form that raises failing
;;; at its line, and the run's verdict. tests/lib.ss loads it, for the
;;; suites, once the world is loaded; a focused topic (tests/units.ss)
;;; loads it alone, after its library and the basics (src/base.ss).
;;;
;;;   (load (string-append *schevana-root* "/tests/check.ss"))
;;;   (check "one is one" (= 1 1))
;;;   (test-verdict!)

;; Where a run writes: its first argument, else here.
(define out-dir
  (if (pair? (command-line-arguments)) (car (command-line-arguments)) "."))

;; A run whose heap passes 2 GB has run away (a loop that allocates without
;; end): it stops, as a failure, before the machine runs out, as forty
;; topics run at once. A thread of its own looks, for one that runs away
;; never comes back to a check, and the shell ends the process, as exit
;; from a thread ends only the thread. A run's heap is a few hundred MB.
(define test-heap-limit
  (* 1024 1024
     (or (string->number (or (getenv "SCHEVANA_TEST_HEAP_MB") "")) 2048)))

;; Made once, so that a look allocates nothing: Chez counts a thread's
;; allocation in every thread's bytes-allocated, by the 16 KB segment as
;; the thread takes one, and a time made each look (48 bytes) put 16 KB
;; into whatever step a check was measuring, every 34 s.
(define test-heap-nap (make-time 'time-duration 100000000 0))

;; The watch's look, 100 ms after the last: #f once it has stopped the run.
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

;; What a check does once it has run, with the world (tests/lib.ss): the
;; collector's look. With none, nothing.
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

(define (raises? thunk) (guard (c [#t #t]) (thunk) #f))

;; thunk's value, cleanup run after it, raise or not: what a sequence
;; changed for itself it changes back, so a failure takes only its own.
(define (test-finally thunk cleanup)
  (let ([v (guard (c [#t (cleanup) (raise c)]) (thunk))])
    (cleanup)
    v))

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
