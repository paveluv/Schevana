;;; tests/units/procs.ss — processes ((schevana core processes)): a process
;;; waits (proc-wait) for the values that work done elsewhere hands to a
;;; then, the procedure the work calls once it is done.

(for-each close-window! (windows))
(steps 2)

;; Spawns a process that waits for the values its start's done is called
;; with, and keeps done in a box for the test to call by hand. Returns
;; (values process done-box result-box).
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
;; until the world's clock says its share of a step is up, so under a held
;; clock it would run forever. Meanwhile this check keeps the failure count
;; and the printed output to itself.
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
