;;; tests/units/probe.ss — the probe and the counts ((schevana services
;;; allocation)): one piece of code run again and again for exactly what
;;; it allocates, and a library switched, while the world runs, to code
;;; that counts how often each of its lines runs.

(define probe-test-taskbar '(schevana desktop taskbar))

;; Returns the line of the taskbar's file that begins with text, from 1.
(define (probe-test-line text)
  (call-with-input-file (string-append *schevana-root*
                                       "/schevana/desktop/taskbar.sls")
    (lambda (p)
      (let loop ([n 1])
        (let ([l (get-line p)])
          (cond [(eof-object? l) #f]
                [(and (>= (string-length l) (string-length text))
                      (string=? (substring l 0 (string-length text)) text))
                 n]
                [else (loop (+ n 1))]))))))

(define probe-test-icon-line (probe-test-line "  (define (taskbar-icon-size)"))

(let ([r (allocation-probe (lambda () (make-bytevector 1000)) 10)])
  (check (format "a probe runs a thunk n times after two, and its least is \
                  what one call allocates: a bytevector of 1,000 bytes and \
                  its header (~s)" r)
         (and (= (cdr (assq 'runs r)) 10)
              (<= 1000 (cdr (assq 'least r)) 1100)
              (<= (cdr (assq 'least r)) (cdr (assq 'median r))
                  (cdr (assq 'most r)))
              (> (cdr (assq 'fastest r)) 0)
              (null? (cdr (assq 'lines r))))))

(check "a probe of a thunk that raises gives the error as text"
       (let ([r (allocation-probe (lambda () (car '())) 3)])
         (and (assq 'error r)
              (string? (cdr (assq 'error r))))))

(let* ([draws 0]
       [win (open-window "Probed" 'size '(120 . 80)
                         'draw (lambda (win w h)
                                 (set! draws (+ draws 1))
                                 (fill-box 0 0 w h 'accent)))])
  (steps 2)
  (let* ([before draws]
         [r (allocation-probe-draw win 5)])
    (close-window! win)
    (steps 1)
    (check (format "a probe of a window's draw runs its handler, two times to \
                    warm up and n more, into a list that nothing shows (~a \
                    draws; ~s)"
                   (- draws before) r)
           (and (= (- draws before) 7)
                (= (cdr (assq 'runs r)) 5)
                (not (window-error win))))))

(check "a probe of a surface's draw finds the surface by its name, and \
        anything else is refused"
       (and (memq 'taskbar (surfaces))
            (assq 'least (allocation-probe-draw 'taskbar 3))
            (guard (c [#t #t])
              (allocation-probe-draw 'no-such-surface 3)
              #f)))

(check "a name that is no library from a file can't be counted"
       (guard (c [#t #t])
         (allocation-count-library! '(no such library) #t)
         #f))

(check "a library whose lines aren't counted has no counts"
       (and (not (member probe-test-taskbar (allocation-counted-libraries)))
            (not (allocation-line-counts probe-test-taskbar))
            (assoc probe-test-taskbar (allocation-libraries))))

(if test-hacker?
    (let ([said '()])
      (fluid-let ([notify (lambda (text . rest) (set! said (cons text said)))])
        (allocation-count-library! probe-test-taskbar #t)
        (test-wait 20000 (lambda () (pair? said))))
      (allocation-count-library! probe-test-taskbar #f)
      (steps 3)
      (check (format "in the hacker edition a library's lines aren't \
                      counted, and a notice says so (~s)" said)
             (and (not (member probe-test-taskbar
                               (allocation-counted-libraries)))
                  (exists (lambda (s)
                            (and (string? s)
                                 (>= (string-length s) 12)
                                 (string=? (substring s 0 1) "(")))
                          said))))
    (begin
      (allocation-count-library! probe-test-taskbar #t)
      (check "a library switched on is evaluated again by a reload, its \
              code counting how often its lines run"
             (test-wait 20000
                        (lambda ()
                          (member probe-test-taskbar
                                  (allocation-counted-libraries)))))
      ;; This form was compiled before the reload, so the taskbar's
      ;; procedure is looked up again, as a REPL's next input would.
      (let* ([size (eval 'taskbar-icon-size)]
             [r (allocation-probe (lambda () (size)) 50)]
             [lines (cdr (assq 'lines r))]
             [taskbar (assoc probe-test-taskbar lines)])
        (check (format "a probe tells how often each line of a counted \
                        library ran in its n calls: the taskbar's icon \
                        size, line ~a, 50 times (~s)"
                       probe-test-icon-line lines)
               (and taskbar
                    (eqv? (cdr (assv probe-test-icon-line (cdr taskbar)))
                          50))))
      (let ([counted (test-wait
                      5000
                      (lambda ()
                        (for-each (lambda (i) ((eval 'taskbar-icon-size)))
                                  (iota 7))
                        (let* ([c (allocation-line-counts probe-test-taskbar)]
                               [n (and c (assv probe-test-icon-line
                                               (cdr (assq 'lines c))))])
                          (and n (>= (cdr n) 7) c))))])
        (check (format "a counted library's lines carry their runs since \
                        its counting began, and the ticks they ran in (~s)"
                       (and counted (cdr (assq 'ticks counted))))
               (and counted (>= (cdr (assq 'ticks counted)) 0))))
      (allocation-count-library! probe-test-taskbar #f)
      (check "a library switched off is evaluated plain again: its lines \
              aren't counted, and a probe has none of them"
             (and (test-wait 20000
                             (lambda ()
                               (not (member probe-test-taskbar
                                            (allocation-counted-libraries)))))
                  (not (allocation-line-counts probe-test-taskbar))
                  (null? (cdr (assq 'lines
                                    (allocation-probe
                                     (eval 'taskbar-icon-size)
                                     5))))))))
