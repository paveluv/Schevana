;;; tests/units/allocation.ss — what the core allocates as the world steps.
;;; Requirement 3 of the GPU design: the core's allocation stays out of the
;;; way, leaving the room to app writers. A guard is what's left: Chez's
;;; allocates a handler and a continuation each time, and the core keeps one
;;; around each part that may raise, so the budgets here are guards,
;;; measured in place, and a little more. Without surfaces, whose drawing is
;;; the desktop's, and with windows that ask no frames, whose frames are
;;; apps'.

(for-each close-window! (windows))

;; Bytes allocated, collections or not.
(define (allocation-now) (+ (bytes-allocated) (bytes-deallocated)))

;; The least that thunk allocates, of n calls.
(define (allocation-least n thunk)
  (thunk)
  (thunk)
  (let loop ([i 0] [least #f])
    (if (= i n)
        least
        (let ([a (allocation-now)])
          (thunk)
          (let ([d (- (allocation-now) a)])
            (loop (+ i 1) (if least (min least d) d)))))))

;; The least a step allocates, of 20, each after a call of before, which
;; isn't counted: a step now and then also keeps the profiler's second,
;; which allocates.
(define (allocation-step-least before)
  (before)
  (schevana-step! 0)
  (let loop ([i 0] [least #f])
    (if (= i 20)
        least
        (begin
          (before)
          (let ([a (allocation-now)])
            (schevana-step! 0)
            (let ([d (- (allocation-now) a)])
              (loop (+ i 1) (if least (min least d) d))))))))

(let* ([surfaces *surfaces*]
       [draws 0]
       [plain (lambda (title x)
                (open-window title 'size '(200 . 100) 'pos (cons x 200)
                             'draw (lambda (win cw ch)
                                     (set! draws (+ draws 1))
                                     (fill-box 0 0 cw ch 'accent))))]
       [one (plain "One" 100)])
  (set! *surfaces* '())
  (steps 3)
  (let* ([guard (allocation-least 20 (lambda () (safely 'test void)))]
         [extent (allocation-least
                  20 (lambda () (let-values ([(x y w h) (window-extent one)])
                                  x)))]
         [quiet (allocation-step-least void)]
         [frame (allocation-step-least request-frame!)]
         [others (list (plain "Two" 400) (plain "Three" 700))])
    (steps 3)
    (let* ([frame3 (allocation-step-least request-frame!)]
           [k 0]
           [drawn draws]
           [move3 (allocation-step-least
                   (lambda ()
                     (set! k (- 1 k))
                     (move-window! one (+ 100 k) 200)))]
           [moved-draws (- draws drawn)]
           [move (allocation-least
                  20 (lambda ()
                       (set! k (- 1 k))
                       (move-window! one (+ 100 k) 200)))]
           [window (quotient (- frame3 frame) 2)])
      (for-each close-window! (cons one others))
      (set! *surfaces* surfaces)
      (steps 1)
      (check (format "a quiet step allocates only its four guards (~a bytes, \
                      a guard ~a)" quiet guard)
             (<= quiet (+ (* 4 guard) 192)))
      (check (format "a frame nothing changed allocates only its guard and \
                      each window's two (~a bytes past a quiet step with a \
                      window; ~a a window more; a guard ~a, a window's \
                      extent ~a)"
                     (- frame quiet) window guard extent)
             (and (<= window (+ guard extent 160))
                  (<= (- frame quiet window) (+ guard 160))))
      (check (format "a window moved isn't drawn again: the move costs its \
                      extent's guard (~a bytes), the frame only the runs \
                      from it on (~a bytes past a frame; drawn ~a times)"
                     move (- move3 frame3) moved-draws)
             (and (= moved-draws 0)
                  (<= move (+ extent 192))
                  ;; its new run, and the list of runs made again
                  (<= (- move3 frame3) 640))))))

;;; Timers: one is linked in place, so setting it costs a vector and a pair
;;; however many are set; the world's own runs as it is, allocating
;;; nothing; one an app set (in an engine) runs in one, with a fuel.
(let ([noop (lambda () (void))])
  (define (set-cost n)   ; the bytes of after with n set before it
    (fluid-let ([*timers* '()])
      (do ([i 0 (+ i 1)]) ((= i n)) (after (+ 1000 i) noop))
      (allocation-least 5 (lambda () (after 5000 noop)))))
  (check "setting a timer costs the same with none set or a hundred"
         (let ([none (set-cost 0)] [many (set-cost 100)])
           (printf "  after: ~a bytes, with 100 set ~a\n" none many)
           (and (= none many) (<= none 64))))
  (check "a timer of the world's own allocates nothing as it runs"
         (fluid-let ([*timers* '()] [now-ms (lambda () (expt 10 15))])
           (let loop ([i 0] [least #f])
             (if (= i 5)
                 (= least 0)
                 (begin
                   (after 0 noop)
                   (let ([a (allocation-now)])
                     (run-timers!)
                     (let ([d (- (allocation-now) a)])
                       (loop (+ i 1) (if least (min least d) d)))))))))
  (check "one set in an engine runs in one: looping, its fuel ends it, and \
          the timers after it still run"
         (let ([later #f] [errors 0])
           (fluid-let ([*timers* '()]
                       [report-error! (lambda (who c)
                                        (set! errors (+ errors 1)))])
             (safe-call 'test
                        (lambda () (after 0 (lambda () (let loop () (loop)))))
                        void)
             (after 1 (lambda () (set! later #t)))
             (fluid-let ([now-ms (lambda () (expt 10 15))])
               (run-timers!)))
           (and later (= errors 1)))))
