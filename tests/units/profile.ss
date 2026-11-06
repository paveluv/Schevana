;;; tests/units/profile.ss — the profiler (services/profile.ss).

;;; the profiler (services/profile.ss)

(for-each close-window! (windows))
(steps 2)

;; Busy for ms of the profiler's clock.
(define (profile-test-busy ms)
  (let ([t0 (now-ns)])
    (let loop ()
      (when (< (- (now-ns) t0) (* ms 1000000)) (loop)))))

;; A tick's uses of x: a window's or a process's subject, or a key.
(define (profile-test-uses tick x)
  (filter (lambda (u) (equal? (profile-use-subject u) (profile-subject-of x)))
          (profile-tick-uses tick)))

(define (profile-test-near? a b) (< (abs (- a b)) 1e-6))

;; A tick's phases' ms, all of them.
(define (profile-test-phases tick)
  (map (lambda (p) (profile-tick-phase-ms tick p))
       (vector->list profile-phase-names)))

;; Bytes allocated by thunk, (statistics) aside.
(define (profile-test-bytes thunk)
  (let ([b0 (sstats-bytes (statistics))])
    (thunk)
    (- (sstats-bytes (statistics)) b0)))

(check "profiling is on at boot: the hooks are the profiler's, the collect \
        handler its own, and ticks are kept"
       (and (profile-on?) (pair? *profile-span*)
            (eq? (car *profile-span*) profile-begin!)
            (eq? (collect-request-handler) profile-collect)
            (pair? (profile-ticks))))

(check "off, the hook is #f: no tick is kept, the clock is read only for the \
        pacer's busy time, Chez's own collect handler is back; on again, \
        ticks are kept"
       (let ([reads 0] [clock now-ns] [before (profile-ticks)])
         (profile-on! #f)
         (set! now-ns
           (lambda () (set! reads (+ reads 1)) (clock)))
         (steps 5)
         (set! now-ns clock)
         (let ([off (and (not (profile-on?)) (not *profile-span*)
                         (equal? before (profile-ticks))
                         (<= reads (* 5 4))   ; a step's, only the pacer's
                         (eq? (collect-request-handler)
                              *profile-plain-collect*))])
           (profile-on! #t)
           (and off (= 3 (length (profile-test-ticks (lambda () (steps 3)))))
                *profile-span*))))

(check "a span allocates nothing, on or off: neither its hook's site nor \
        the profiler's books (a step's: its one guard)"
       (let* ([spans (lambda ()
                       (with-profile-span 'step #f
                         (with-profile-span 'render #f
                           (do ([i 0 (+ i 1)]) ((= i 10000))
                             (with-profile-span (+ 1000000 (mod i 30)) 'draw
                               (with-profile-span 'profile-test-x #f
                                 i))))))]
              [none (profile-test-bytes void)]   ; (statistics)'s own
              [on (begin (spans) (- (profile-test-bytes spans) none))]
              [off (begin (profile-on! #f)
                          (- (profile-test-bytes spans) none))])
         (profile-on! #t)
         (printf "  ~a bytes on, ~a off, for 20,000 spans and a step\n" on off)
         (and (< on 1000) (= off 0))))

(check "spans nest: each keeps its self time, the phases and the uses add \
        up to the step, idle is the step's own"
       (let* ([s (car (profile-test-ticks
                       (lambda ()
                         (with-profile-span 'step #f
                           (profile-test-busy 1)
                           (with-profile-span 'render #f
                             (profile-test-busy 2)
                             (with-profile-span 'profile-test-inner #f
                               (profile-test-busy 3)))))))]
              [use (lambda (k) (profile-use-ms
                                (car (profile-test-uses s k))))])
         (and (< 0.5 (profile-tick-phase-ms s 'input-wait) 1.5)
              (< 1.5 (use 'render) 2.5)
              (< 2.5 (use 'profile-test-inner) 3.5)
              (eq? (profile-use-phase (car (profile-test-uses
                                            s 'profile-test-inner)))
                   'render)
              (profile-test-near?
               (+ (profile-tick-phase-ms s 'render)
                  (profile-tick-phase-ms s 'gc))
               (apply + (map profile-use-ms (profile-tick-uses s))))
              (profile-test-near? (apply + (profile-test-phases s))
                                  (profile-tick-ms s)))))

(let ([life-win (life)])
  (move-window! life-win 600 300)
  (check "every step of the world adds up: its phases to its time, its uses \
          and its input-wait too, no part below 0"
         (let ([ss (profile-test-ticks (lambda () (steps 20)))])
           (close-window! life-win)
           (and (= (length ss) 20)
                (for-all
                 (lambda (s)
                   (let ([uses (profile-tick-uses s)])
                     (and (profile-test-near? (apply + (profile-test-phases s))
                                              (profile-tick-ms s))
                          (profile-test-near?
                           (+ (profile-tick-phase-ms s 'input-wait)
                              (apply + (map profile-use-ms uses)))
                           (profile-tick-ms s))
                          (for-all (lambda (u) (>= (profile-use-ms u) 0))
                                   uses)
                          (for-all (lambda (ms) (>= ms 0))
                                   (profile-test-phases s)))))
                 ss)))))

(let ([slow (open-window "Slow"
              'size '(200 . 100)
              'tick (lambda (win) (invalidate! win))
              'draw (lambda (win w h) (profile-test-busy 3)))]
      [life-win (life)])
  (check "a window whose draw is made slow comes first among Monitor's \
          consumers, its draw the most of its parts"
         (let* ([ss (profile-test-ticks (lambda () (steps 10)))]
                [ts (filter (lambda (t)
                              (monitor-subject? (profile-total-what t)))
                            (profile-totals ss #t))])
           (close-window! slow)
           (close-window! life-win)
           (and (pair? ts)
                (equal? (profile-total-what (car ts))
                        (profile-subject-of slow))
                (equal? (profile-total-what
                         (car (profile-total-parts (car ts))))
                        '(draw . render))
                (= (profile-total-ticks (car ts)) 10)
                (>= (/ (profile-total-ms (car ts)) 10) 3)))))

(let ([p (spawn "profile-test-busy" (lambda () (let loop () (loop))))])
  (check "a busy process shows its share: most of the processes' phase, in \
          one turn a step"
         (let ([ss (profile-test-ticks (lambda () (steps 10)))])
           (kill! p)
           (for-all
            (lambda (s)
              (let ([u (profile-test-uses s p)])
                (and (= (length u) 1)
                     (= (profile-use-calls (car u)) 1)
                     (> (profile-use-ms (car u))
                        (* 0.8 (profile-tick-phase-ms s 'procs))))))
            ss))))

(check "a (collect) shows in the memory numbers, and so does the heap; a \
        collection requested on the main loop is a span of its own, gc"
       (let* ([timer (profile-test-ticks
                      (lambda () (after 0 (lambda () (collect))) (steps 2)))]
              [g0 (collections)]
              [requested
               (car (profile-test-ticks
                     (lambda ()
                       (with-profile-span 'step #f
                         (with-profile-span 'event #f
                           (let loop ([keep '()])
                             (when (= (collections) g0)
                               (loop (cons (make-vector 100)
                                           (if (> (length keep) 50)
                                               '()
                                               keep))))))))))])
         (and (exists (lambda (s) (>= (profile-tick-ref s 'gcs) 1)) timer)
              (for-all (lambda (s) (> (profile-tick-ref s 'heap) 0)) timer)
              (>= (profile-tick-ref requested 'gcs) 1)
              (> (profile-tick-ref requested 'allocated) 0)
              (pair? (profile-test-uses requested 'gc))
              (eq? (profile-use-phase (car (profile-test-uses requested 'gc)))
                   'event)
              (> (profile-tick-phase-ms requested 'gc) 0)
              (> (profile-tick-ref requested 'gc-ms) 0))))

(let* ([w (open-window "Inner"
            'size '(200 . 100)
            'tick (lambda (win)
                    (safely 'profile-test-handler
                            (lambda () (profile-test-busy 1)))))]
       [p (spawn "inner"
                 (lambda ()
                   (let loop ()
                     (safely 'profile-test-process (lambda () (yield)))
                     (loop))))])
  (check "a span inside an engine (a handler, a process) is not timed: its \
          time is its handler's or its process's"
         (let ([ss (profile-test-ticks (lambda () (steps 5)))])
           (close-window! w)
           (kill! p)
           (for-all
            (lambda (s)
              (and (null? (profile-test-uses s 'profile-test-handler))
                   (null? (profile-test-uses s 'profile-test-process))
                   (exists (lambda (u)
                             (and (eq? (profile-use-part u) 'tick)
                                  (>= (profile-use-ms u) 1)))
                           (profile-test-uses s w))
                   (pair? (profile-test-uses s p))))
            ss))))

(check "a span on a thread other than the one profile-on! saw is untimed, \
        and so is one deeper than the stack: no step is lost, nothing \
        overflows"
       (let* ([thread *profile-thread*]
              [others (profile-test-ticks
                       (lambda ()
                         (set! *profile-thread* (+ thread 1))
                         (steps 3)
                         (set! *profile-thread* thread)))]
              [deep (profile-test-ticks
                     (lambda ()
                       (with-profile-span 'step #f
                         (let nest ([n 100])
                           (if (= n 0)
                               (profile-test-busy 1)
                               (with-profile-span 'render #f
                                 (nest (- n 1))))))))])
         (and (null? others) (= (length deep) 1)
              (profile-test-near? (apply + (profile-test-phases (car deep)))
                                  (profile-tick-ms (car deep)))
              (>= (profile-tick-phase-ms (car deep) 'render) 1))))

(check "a raise out of a span, caught in its parent, leaves it open: the \
        ends after it close a span each, the innermost, the step's end the \
        rest, and the step's phases still add up to it"
       (let ([s (car (profile-test-ticks
                      (lambda ()
                        (with-profile-span 'step #f
                          (with-profile-span 'render #f
                            (guard (e [#t 'caught])
                              (with-profile-span 'profile-test-raiser #f
                                (profile-test-busy 2)
                                (raise 'oops)))
                            (with-profile-span 'profile-test-after #f
                              (profile-test-busy 3)))))))]
             [ms (lambda (s k)
                   (apply + (map profile-use-ms (profile-test-uses s k))))])
         (and (profile-test-near? (apply + (profile-test-phases s))
                                  (profile-tick-ms s))
              (< 1.5 (ms s 'profile-test-raiser) 2.5)
              (< 2.5 (ms s 'profile-test-after) 3.5)
              (< (ms s 'render) 0.5)
              (eq? (profile-use-phase
                    (car (profile-test-uses s 'profile-test-after)))
                   'render))))

(check "a collector that raises turns itself off, says so once, and the \
        world goes on drawing"
       (let ([done profile-tick-done!] [errors 0] [report report-error!])
         (set! report-error! (lambda (who c)
                               (set! errors (+ errors 1))
                               (report who c)))
         (set! profile-tick-done! (lambda (now ns) (car '())))
         (steps 3)
         (set! profile-tick-done! done)
         (set! report-error! report)
         (let ([off (not (profile-on?))] [drawn *frames-drawn*])
           (invalidate!)
           (steps 2)
           (profile-on! #t)
           (set! *toasts* '())
           (and off (= errors 1) (> *frames-drawn* drawn)))))

(check "the history keeps no closed window and no ended process alive: \
        each is a subject, its id, and its title or name when first seen"
       (let* ([w (open-window "Kept?" 'size '(200 . 100)
                              'tick (lambda (win) (invalidate! win)))]
              [p (spawn "kept?" (lambda () (let loop () (yield) (loop))))]
              [w-ptr (weak-cons w #f)] [p-ptr (weak-cons p #f)])
         (steps 5)
         (let ([subjects (list (profile-subject-of w) (profile-subject-of p))]
               [ids (list (window-id w) (proc-id p))])
           (close-window! w)
           (kill! p)
           (set! w #f)
           (set! p #f)
           (steps 5)
           (collect (collect-maximum-generation))
           (and (bwp-object? (car w-ptr)) (bwp-object? (car p-ptr))
                (exists (lambda (s)
                          (member (car subjects)
                                  (map profile-use-subject
                                       (profile-tick-uses s))))
                        (profile-ticks))
                (equal? (map car subjects) '(window process))
                (equal? (map cdr subjects) ids)
                (equal? (map profile-subject-name subjects)
                        '("Kept?" "kept?"))))))

(let* ([a (open-window "Twin" 'size '(100 . 60))]
       [b (open-window "Twin" 'size '(100 . 60))]
       [c (open-window "Single" 'size '(100 . 60))]
       [seen (steps 1)]   ; the profiler takes their titles
       [subjects (map profile-subject-of (list a b c))]
       [labels (monitor-labels subjects)])
  (close-window! a)
  (check "two windows of one title get their ids in Monitor's labels, a \
          closed one says so, and a title of its own stays plain"
         (equal? (map cdr labels)
                 (list (format "Twin (window ~a)" (window-id a))
                       (format "Twin (window ~a)" (window-id b))
                       "Single")))
  (check "and once one of them is closed"
         (equal? (map cdr (monitor-labels subjects))
                 (list (format "Twin (window ~a, closed)" (window-id a))
                       (format "Twin (window ~a)" (window-id b))
                       "Single")))
  (for-each close-window! (list b c)))

(check "the history keeps the ticks of the last seconds (at most 100 a \
        second of them) and the seconds of the last minutes asked for \
        (profile-history!), by the clock"
       (let ([clock now-ns] [fake (expt 10 15)])
         (define (run! seconds)   ; 100 ms a step
           (do ([i 0 (+ i 1)]) ((= i (* 10 seconds)))
             (set! fake (+ fake (expt 10 8)))
             (schevana-step! 0)))
         (define (within? seconds)   ; the ticks kept span that, a second more
           (let ([ss (profile-ticks)])
             (and (pair? ss)
                  (> (profile-tick-end (car (last-pair ss)))
                     (- (profile-tick-end (car ss)) (* 1000 (+ seconds 1))))
                  (< (profile-tick-end (car (last-pair ss)))
                     (- (profile-tick-end (car ss)) (* 1000 (- seconds 1)))))))
         (set! now-ns (lambda () fake))
         (profile-clear!)
         (profile-history! 30 1)
         (run! 90)
         (let ([long (and (within? 30) (= (length (profile-seconds)) 60))])
           (profile-history! 5 2)
           (let ([now (within? 5)])
             (run! 150)
             (let ([later (and (within? 5)
                               (= (length (profile-seconds)) 120))])
               (set! now-ns clock)
               ;; back to back, thousands a second: at most 100 a second
               ;; of it
               (profile-history! 2 10)
               (steps 2000)
               (let ([most (= (length (profile-ticks)) 200)])
                 (profile-history! 30 10)
                 (profile-clear!)
                 (and long now later most)))))))

(check "Monitor's Consumers fit their columns to the tree's room: the last \
        (the minute's lines) ends clear of a scroll bar always shown"
       (let* ([m (monitor)] [ui (window-ref m 'ui)])
         (steps 3)
         (let-values ([(cx cy cw ch) (content-rect m)])   ; its Ticks
           (let* ([r (ui-find ui '(tab ticks))]
                  [x (exact (round (+ cx (ui-region-x r)
                                      (/ (ui-region-w r) 2))))]
                  [y (exact (round (+ cy (ui-region-y r)
                                      (/ (ui-region-h r) 2))))])
             (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))))
         (steps 3)
         (let-values ([(cx cy cw ch) (content-rect m)])
           (let* ([r (ui-find ui '(consumers header spark))]
                  [end (and r (+ (ui-region-x r) (ui-region-w r)))]
                  [room (- cw (ui-pad) (ui-scrollbar-inset 'right))])
             (close-window! m)
             (steps 1)
             (printf "  ~s ~s\n" end room)
             (and end (> (ui-scrollbar-inset 'right) 0) (<= end room))))))
