;;; tests/units/threads.ss — threads as the core sees them: thread parameters,
;;; core1's C, its mail.

;;; Threads, as the core sees them: thread parameters, core1's C, and
;;; core1's mail.

;; thunk run on a thread of its own; => its value, once the thread is done
(define (on-thread thunk)
  (let* ([out (box #f)] [t (fork-thread (lambda () (set-box! out (thunk))))])
    (thread-join t)
    (unbox out)))

(check "another thread's in-engine?, current-proc, current-app and \
        new-window-position are its own: binding them there leaves the \
        core1's as they were"
       (let ([inside (box #f)] [go (box #f)])
         (let ([t (fork-thread
                   (lambda ()
                     (parameterize ([in-engine? #t] [current-proc 'worker]
                                    [current-app 'worker]
                                    [new-window-position '(1 . 2)])
                       (set-box! inside #t)
                       (let wait ()
                         (unless (unbox go)
                           (sleep (make-time 'time-duration 1000000 0))
                           (wait))))))])
           (let wait ([n 0])
             (unless (or (unbox inside) (> n 2000))
               (sleep (make-time 'time-duration 1000000 0))
               (wait (+ n 1))))
           (let ([core1 (list (in-engine?) (current-proc) (current-app)
                              (new-window-position))])
             (set-box! go #t)
             (thread-join t)
             (printf "  core1's while the other's were bound: ~s\n" core1)
             (and (unbox inside) (equal? core1 '(#f #f #f #f)))))))

(check "a worklet reaches only its environment: one that names a world \
        procedure, SDL, eval, a primitive, a condition's reader or a world \
        local, or sets a top-level name, is refused when defined; worklets \
        call worklets by name and see them redefined, and a worklet's set! \
        of another is refused"
       (let ([refused
              (map (lambda (form)
                     (guard (c [#t (and (pair? (condition-irritants c))
                                        (car (condition-irritants c)))])
                       (eval form)
                       'defined))
                   '((define-worklet (units-bad x) (draw-text x 0 "" 'text 'ui))
                     (define-worklet (units-bad) (sdl-get-ticks-ns))
                     (define-worklet (units-bad) (eval ''1))
                     (define-worklet (units-bad) (#%$top-level-value 'car))
                     (define-worklet (units-bad c) (condition-irritants c))
                     (let ([y 5]) (worklet (x) (fx+ x y)))
                     (define-worklet (units-bad) (set! units-twice 0))))])
         (eval '(define-worklet (units-twice x) (fx* x 2)))
         (eval '(define-worklet (units-quad x) (units-twice (units-twice x))))
         (let ([before ((eval 'units-quad) 1)])
           (eval '(define-worklet (units-twice x) (fx* x 3)))
           (printf "  refused: ~s\n" refused)
           (and (equal? refused '(draw-text sdl-get-ticks-ns eval
                                  $top-level-value condition-irritants y
                                  units-twice))
                (= before 4) (= ((eval 'units-quad) 1) 9)
                (guard (c [#t (syntax-violation? c)])
                  (eval '(define-worklet (units-bad) (set! units-twice 0)))
                  #f)
                (worklet? (eval 'units-quad)) (not (worklet? car))))))

(define-worklet (units-clock) (now-ns))

(check "a worklet's clock is the world's now-ns, redefined too"
       (let* ([world now-ns]
              [seen (begin (set! now-ns (lambda () 42))
                           (guard (c [#t c]) (units-clock)))])
         (set! now-ns world)
         (and (eqv? seen 42) (fixnum? (units-clock)))))

(check "post-core1!: thunks from four threads run at the next step, on \
        core1, once each and in each thread's order; one that \
        raises is reported, and the rest still run"
       (let ([seen '()] [reported 0])
         (for-each thread-join
                   (map (lambda (k)
                          (fork-thread
                           (lambda ()
                             (do ([i 0 (+ i 1)]) ((= i 100))
                               (post-core1!
                                (lambda ()
                                  (set! seen (cons (list k i (core1-thread?))
                                                   seen))))))))
                        '(0 1 2 3)))
         (post-core1! (lambda () (error 'mail "posted to fail")))
         (post-core1! (lambda () (set! seen (cons '(core1 0 #t) seen))))
         (let ([before (length seen)])
           (fluid-let ([report-error! (lambda (who c)
                                        (set! reported (+ reported 1)))])
             (steps 1))
           (let ([seen (reverse seen)])
             (define (of k) (map cadr (filter (lambda (s) (eqv? (car s) k))
                                              seen)))
             (and (= before 0) (= (length seen) 401) (= reported 1)
                  (for-all caddr seen)
                  (for-all (lambda (k) (equal? (of k) (iota 100)))
                           '(0 1 2 3))
                  (equal? (car (last-pair seen)) '(core1 0 #t))
                  (begin (steps 1) (= (length seen) 401)))))))
