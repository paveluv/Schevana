;;; tests/units/vat.ss — vats (services/vat.ss): threads with a mailbox and a
;;; sandbox; jobs, their deliveries on main, and their kills.

;;; Vats (services/vat.ss): threads with a mailbox and a sandbox; jobs,
;;; their deliveries on main, and their kills.

;; Steps the world until (pred), for at most 2 s.
(define (vat-test-until pred)
  (let ([until (+ (real-time) 2000)])
    (let loop ()
      (cond [(pred) #t]
            [(> (real-time) until) #f]
            [else (steps 1) (loop)]))))

(define-worklet (vat-test-add a b) (fx+ a b))
(define-worklet (vat-test-where) (get-thread-id))
(define-worklet (vat-test-spin) (let loop () (loop)))
(define-worklet (vat-test-fail) (error 'vat-test "failed on purpose"))

(define vat-test (vat-start! (env-child (env-root) 'vat-test 'core)))

(check "a vat runs a worklet on its own thread, and the job's then runs on \
        main at a later step, once"
       (let* ([got '()]
              [j (vat-send! vat-test vat-test-where '()
                            (lambda (id)
                              (set! got (cons (list id (get-thread-id))
                                              got))))])
         (and (vat-job-pending? j)
              (null? got)
              (vat-test-until (lambda () (pair? got)))
              (begin (steps 3) (= (length got) 1))
              (not (= (caar got) (get-thread-id)))
              (= (cadar got) (get-thread-id))
              (not (vat-job-pending? j)))))

(check "a vat keeps state in its sandbox: forms define it, and jobs by \
        name change it, in the order sent"
       (let ([got '()])
         (vat-eval! vat-test '(define vat-test-tally 0) #f)
         (vat-eval! vat-test
                    '(define (vat-test-tally! k)
                       (set! vat-test-tally (+ vat-test-tally k))
                       vat-test-tally)
                    #f)
         (for-each (lambda (k)
                     (vat-send! vat-test 'vat-test-tally! (list k)
                                (lambda (n) (set! got (cons n got)))))
                   '(1 2 3))
         (and (vat-test-until (lambda () (= (length got) 3)))
              (equal? (reverse got) '(1 3 6))
              (not (top-level-bound? 'vat-test-tally)))))

(check "a job carries no procedure but worklets, a vat runs only in a \
        sandbox, and the pool takes neither forms nor names"
       (let ([refused?
              (lambda (thunk)
                (guard (c [#t (string-contains-ci? (condition-message c)
                                                   "no procedure but")])
                  (thunk)
                  #f))]
             [chez (env-child (env-root) 'vat-chez 'chez)])
         (let ([ok (and (refused? (lambda () (vat-send! vat-test car '() #f)))
                        (refused? (lambda ()
                                    (vat-send! vat-test vat-test-add
                                               (list 1 (vector car)) #f)))
                        (refused? (lambda () (vat-eval! vat-test `',car #f)))
                        (raises? (lambda () (vat-start! chez)))
                        (raises? (lambda () (vat-eval! (vat-pool) 1 #f)))
                        (raises? (lambda ()
                                   (vat-send! (vat-pool) 'vat-test-add
                                              '(1 2) #f))))])
           (env-drop! chez)
           ok)))

(check "a job's then runs as a handler of the window it was sent from: \
        (current-window) is it, and its error crashes it"
       (let ([w (open-window "Then" 'size '(200 . 100))] [seen #f])
         (parameterize ([current-window w])
           (vat-send! vat-test vat-test-add '(1 2)
                      (lambda (v)
                        (set! seen (list v (current-window)))
                        (error 'then "then failed"))))
         (let ([ok (and (vat-test-until (lambda () seen))
                        (equal? seen (list 3 w))
                        (window-error w)
                        (string-contains-ci?
                         (condition->string (cdr (window-error w)))
                         "then failed"))])
           (close-window! w)
           ok)))

(check "a job that raises crashes its window, which kills the window's \
        other jobs: the running one escapes, and the vat goes on"
       (let ([w (open-window "Jobs" 'size '(200 . 100))] [ran #f]
             [after (box #f)])
         (let* ([fail (parameterize ([current-window w])
                        (vat-send! vat-test vat-test-fail '() #f))]
                [spin (parameterize ([current-window w])
                        (vat-send! vat-test vat-test-spin '()
                                   (lambda () (set! ran #t))))])
           (vat-send! vat-test vat-test-add '(2 2)
                      (lambda (v) (set-box! after v)))
           (let ([ok (and (vat-test-until (lambda () (unbox after)))
                          (= (unbox after) 4)
                          (eq? (car (window-error w)) 'job)
                          (string-contains-ci?
                           (condition->string (cdr (window-error w)))
                           "failed on purpose")
                          (not (vat-job-pending? fail))
                          (not (vat-job-pending? spin))
                          (not ran))])
             (close-window! w)
             ok))))

(check "a killed job never starts, or, running, escapes; its then never \
        runs; and closing a window kills the jobs sent from it"
       (let* ([ran #f] [after (box #f)]
              [w (open-window "Closed" 'size '(200 . 100))]
              [spin (vat-send! vat-test vat-test-spin '()
                               (lambda () (set! ran 'spin)))]
              [queued (vat-send! vat-test vat-test-add '(1 1)
                                 (lambda (v) (set! ran 'queued)))]
              [closed (parameterize ([current-window w])
                        (vat-send! vat-test vat-test-spin '()
                                   (lambda () (set! ran 'closed))))])
         (vat-job-kill! queued)
         (sleep (make-time 'time-duration 20000000 0))   ; spin is running
         (vat-job-kill! spin)
         (close-window! w)
         (vat-send! vat-test vat-test-add '(3 4)
                    (lambda (v) (set-box! after v)))
         (and (not (exists vat-job-pending? (list spin queued closed)))
              (vat-test-until (lambda () (unbox after)))
              (= (unbox after) 7)
              (begin (steps 3) (not ran)))))

(check "a result that is a sandbox's own procedure is refused on main"
       (let ([w (open-window "Leak" 'size '(200 . 100))] [got #f])
         (parameterize ([current-window w])
           (vat-eval! vat-test 'vat-test-tally! (lambda (p) (set! got p))))
         (let ([ok (and (vat-test-until (lambda () (window-error w)))
                        (not got)
                        (string-contains-ci?
                         (condition->string (cdr (window-error w)))
                         "returns no procedure but"))])
           (close-window! w)
           ok)))

(check "the pool runs worklets on its own threads"
       (let ([ids (box '())])
         (do ([i 0 (+ i 1)]) ((= i 8))
           (vat-send! (vat-pool) vat-test-where '()
                      (lambda (id) (set-box! ids (cons id (unbox ids))))))
         (and (vat-test-until (lambda () (= (length (unbox ids)) 8)))
              (not (memv (get-thread-id) (unbox ids))))))

(check "the pool's size is settable: threads past it stop, more start, \
        and the jobs run on; none is refused"
       (let ([size (vat-pool-size)] [done (box 0)])
         (define (run! n)
           (do ([i 0 (+ i 1)]) ((= i n))
             (vat-send! (vat-pool) vat-test-add '(1 1)
                        (lambda (v) (set-box! done (+ (unbox done) v))))))
         (vat-pool-size-set! 1)
         (run! 4)
         (let ([one (length (vat-threads (vat-pool)))])
           (vat-pool-size-set! 6)
           (run! 4)
           (let ([six (length (vat-threads (vat-pool)))])
             (let ([ok (and (= one 1) (= six 6) (= (vat-pool-size) 6)
                            (vat-test-until (lambda () (= (unbox done) 16)))
                            (raises? (lambda () (vat-pool-size-set! 0))))])
               (vat-pool-size-set! size)
               (and ok (= (length (vat-threads (vat-pool))) size)))))))

(check "vat-repl! evaluates forms on the vat's thread and prints there \
        what they return, procedures too, and an error as its text"
       (let* ([e (env-child (env-root) 'vat-repl 'core)]
              [v (vat-start! e)] [got #f] [err #f])
         (vat-repl! v '((define x 2) (* x 21) (lambda () x)) 60
                    (lambda (texts) (set! got texts))
                    (lambda (text) (set! err text)))
         (vat-repl! v '((car 1)) 60
                    (lambda (texts) (set! got 'no))
                    (lambda (text) (set! err text)))
         (let ([ok (and (vat-test-until (lambda () err))
                        (eq? (vat-of e) v)
                        (equal? (car got) "42")
                        (string-prefix? "#<procedure" (cadr got))
                        (string-contains-ci? err "car"))])
           (vat-drop-env! e)
           (and ok (not (vat-of e)) (not (env-find "/vat-repl"))))))

(check "a job sent with a fail gives it the condition, and its window \
        stays up"
       (let ([w (open-window "Fail" 'size '(200 . 100))] [got #f])
         (parameterize ([current-window w])
           (vat-send! vat-test vat-test-fail '() #f (lambda (c) (set! got c))))
         (let ([ok (and (vat-test-until (lambda () got))
                        (condition? got)
                        (not (window-error w)))])
           (close-window! w)
           ok)))

(check "dropping a vat kills its jobs and refuses new ones"
       (let* ([e (env-child (env-root) 'vat-drop 'core)]
              [v (vat-start! e)]
              [j (vat-send! v vat-test-spin '() #f)])
         (vat-drop! v)
         (vat-drop! vat-test)
         (env-drop! e)
         (env-drop! (vat-env vat-test))
         (and (not (vat-job-pending? j))
              (raises? (lambda () (vat-send! v vat-test-add '(1 1) #f)))
              (equal? (format "~s" v) "#<vat /vat-drop>"))))
