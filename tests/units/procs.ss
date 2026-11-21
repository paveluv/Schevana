;;; tests/units/procs.ss — processes ((schevana core processes)): a process
;;; waits for what something done elsewhere hands a then (proc-wait).

(for-each close-window! (windows))
(steps 2)

;; A process that waits for what its start's done is given, done kept to
;; be called by hand: => (values process done-box result-box).
(define (procs-test-waiter)
  (let* ([done (box #f)] [result (box 'none)]
         [p (spawn "waiter"
                   (lambda ()
                     (set-box! result
                       (call-with-values
                         (lambda ()
                           (proc-wait 'procs-test
                                      (lambda (d) (set-box! done d))))
                         list))))])
    (values p done result)))

(let-values ([(p done result) (procs-test-waiter)])
  (steps 3)
  (let ([waiting? (and (memq p (procs)) (eq? (unbox result) 'none)
                       (not (proc-ready? p)))])
    ((unbox done) 1 2)
    (steps 2)
    (check "a process waits for what its then is given, never run \
            meanwhile, and goes on with those values once it comes"
           (and waiting? (equal? (unbox result) '(1 2))
                (not (memq p (procs)))))))

(let ([result (box 'none)])
  (spawn "at once"
         (lambda ()
           (set-box! result
                     (proc-wait 'procs-test (lambda (done) (done 'now))))))
  (steps 2)
  (check "a then given at once: the process goes on with it"
         (eq? (unbox result) 'now)))

(check "outside a process nothing waits: it raises, naming who asked, and \
        start is never called"
       (let ([started? #f])
         (and (guard (c [#t (eq? (condition-who c) 'procs-test)])
                (proc-wait 'procs-test
                           (lambda (done) (set! started? #t)))
                #f)
              (not started?))))

(let-values ([(p done result) (procs-test-waiter)])
  (steps 2)
  (kill! p)
  ((unbox done) 'late)
  (steps 2)
  (check "a process killed while it waits stays gone, and its then, \
          given late, changes nothing"
         (and (not (memq p (procs))) (eq? (unbox result) 'none))))

;; The test's own clock (tests/lib.ss): a process that never yields runs
;; till its share of a step is up by the world's clock, so under a clock
;; held still it would run without end. The verdict and what's printed are
;; this check's own for the while.
(let* ([p (spawn "never yields" (lambda () (let loop () (loop))))]
       [failed 0]
       [said (with-output-to-string
               (lambda ()
                 (fluid-let ([failures 0])
                   (test-clock-hold!)
                   (steps 3)
                   (test-clock-release!)
                   (set! failed failures))))])
  (kill! p)
  (steps 2)
  (check "a world that waits for the held clock fails the run, once, and \
          goes on: the clock moves from then till it's let go"
         (and (= failed 1)
              (string-contains-ci? said "FAIL the held clock")
              (not test-clock-ms)
              (not (memq p (procs))))))
