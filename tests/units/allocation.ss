;;; tests/units/allocation.ss — what the core allocates as the world steps.
;;; Requirement 3 of the GPU design: the core's allocation stays out of the
;;; way, leaving the room to app writers. A guard is what's left: Chez's
;;; allocates a handler and a continuation each time, and the core keeps one
;;; around each part that may raise, so the budgets here are guards,
;;; measured in place, and a little more. Without surfaces, whose drawing is
;;; the desktop's, and with windows that don't tick, whose ticks are apps'.

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
