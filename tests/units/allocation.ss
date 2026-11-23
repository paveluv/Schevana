;;; tests/units/allocation.ss — what the core allocates as the world steps.
;;; Requirement 3 of the GPU design: the core's allocation stays out of the
;;; way, leaving the room to app writers. What is left is the guards:
;;; Chez's guard allocates a handler and a continuation each time, and the
;;; core keeps one around each part that may raise, so the budgets here are
;;; a number of guards, measured in place, plus a little more. The checks
;;; run without surfaces, whose drawing is the desktop's, and with windows
;;; that ask for no frames, since their frames are the apps'.

(for-each close-window! (windows))

;; Bytes allocated, collections or not.
(define (allocation-now) (+ (bytes-allocated) (bytes-deallocated)))

;; The least that thunk allocates over n calls, after two to warm up.
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

;; What every check here measures counts every thread's allocation, so
;; the suites' own thread, the heap's watch (tests/check.ss), must
;; allocate nothing as it looks.
(let ([look (allocation-least 3 test-heap-look)])
  (check (format "the heap's watch allocates nothing a look (~a bytes)" look)
         (= look 0)))

;; Returns thunk's value, run on a clock that moves on a microsecond each
;; time it is read; afterward the clock is the machine's again, once the
;; machine's has caught up.
(define (allocation-on-clock thunk)
  (let* ([ns now-ns] [ms now-ms] [t (ns)])
    (dynamic-wind
      (lambda ()
        (set! now-ns (lambda () (set! t (+ t 1000)) t))
        (set! now-ms (lambda () (set! t (+ t 1000)) (quotient t 1000000))))
      thunk
      (lambda ()
        (set! now-ns ns)
        (set! now-ms ms)
        (let wait () (when (< (ns) t) (wait)))))))

;; The least that a step allocates over 20 steps, each after a call of
;; before, which isn't counted: now and then a step also keeps the
;; profiler's second, which allocates. The steps run on a clock of their
;; own: by the machine's, each step of a slow run comes late, which the
;; profiler flags and keeps for three ticks (some 11 KB), and with a second
;; between steps each would have what the world does once a second
;; (40 KB). The least of 20 leaves out only what some steps lack.
(define (allocation-step-least before)
  (allocation-on-clock
   (lambda ()
     (before)
     (test-step!)
     (let loop ([i 0] [least #f])
       (if (= i 20)
           least
           (begin
             (before)
             (let ([a (allocation-now)])
               (test-step!)
               (let ([d (- (allocation-now) a)])
                 (loop (+ i 1) (if least (min least d) d))))))))))

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

;;; Timers: a timer is linked in place, so setting one costs a vector and a
;;; pair however many are set; a timer of the world's own runs as it is,
;;; allocating nothing; a timer that an app set (in an engine) runs in an
;;; engine, with fuel.
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

;;; Core0's pacing parts: core1's wait and both wakes, and core0's sleep
;;; woken before it, as each frame has them; and a step of core0's at which
;;; nothing comes, as at each of its looks while frames flow, thousands a
;;; second, with its window's facts read again as at each. The sleep takes
;;; and gives up its lock with nothing to unwind: a winder would allocate,
;;; and a second Ctrl-C, which drops core0's stack where it stands, would
;;; run it.
(fluid-let ([*core0-forked* #t] [*core0-world-woken* #f] [*core0-woken* #f])
  (check "core1's wait, its wake and core0's, and core0's sleep woken \
          before it, allocate nothing"
         (= 0 (allocation-least 20 (lambda ()
                                     (core0-world-wake!)
                                     (core0-world-wait-ns! 1000000)
                                     (core0-wake!)
                                     (core0-sleep!))))))
(fluid-let ([*core0-mode* 'sdl] [*core0-facts* *core0-facts*])
  (let ([step (allocation-least 20 core0-step!)])
    ;; 16: Chez 10.0.0 conses a pair for each collect-safe call into C,
    ;; here SDL's poll of its queue
    (check (format "a step of core0's at which nothing comes allocates \
                    nothing but Chez's for its call into SDL's queue (~a \
                    bytes)"
                   step)
           (<= step 16))))

;;; A frame's way back, by its own link, and onto core1's chain to fill
;;; again; and core0's hold of a frame with no window, on a thread of its
;;; own, a frame each refresh.
(let ([f (gpu-frame-make)])
  (fluid-let ([*gpu-frames-free* #f])
    (check "a frame given back, taken back and kept to fill again allocates \
            nothing"
           (= 0 (allocation-least 20 (lambda ()
                                       (gpu-give-back! f)
                                       (gpu-frame-free! (gpu-frames-back!))
                                       (set! *gpu-frames-free* #f)))))))
(check "core0's hold of a frame with no window allocates nothing"
       (= 0 (allocation-least 5 gpu-headless-hold!)))

;;; The second pacer's calls ((schevana core pacer2)), on sixteen rows
;;; written as a turn and core0 write them: fourteen frames of a flow, then
;;; two that missed their refresh, done the hold before it, a pair. The
;;; loop's wait, with a timer and without; a turn begun and one not;
;;; processes' share; and the question, judging the rows and raising the
;;; hold, then planning.
(let* ([r 10000000] [T 1000000000000] [ms 1000000] [first 7000001]
       [row! (lambda (k aim done shown)
               (let ([f (+ first k)] [b (- aim (quotient r 2))]
                     [at (* frame-ring-words
                            (modulo *frame-ring-n* frame-ring-rows))]
                     [pa (present-at (+ first k))])
                 (for-each (lambda (w v)
                             (fxvector-set! *frame-ring* (+ at w) v))
                           '(5 6 8 10 13 14 15)
                           (list 0 f b (+ b 100000) aim b 2))
                 (set! *frame-ring-n* (+ *frame-ring-n* 1))
                 (for-each (lambda (w v)
                             (fxvector-set! *present-ring* (+ pa w) v))
                           '(1 3 4 6 7 8 9)
                           (list 1 shown r done (+ b 200000) (+ b 200000)
                                 (+ b 200000)))
                 (fxvector-set! *present-ring* pa f)))])
  (do ([k 0 (+ k 1)]) ((= k 14))
    (let ([aim (+ T (* k r))]) (row! k aim (- aim (* 3 ms)) aim)))
  (row! 14 (+ T (* 14 r)) (- (+ T (* 14 r)) (* 4 ms)) (+ T (* 15 r)))
  (row! 15 (+ T (* 16 r)) (- (+ T (* 16 r)) (* 5 ms)) (+ T (* 17 r)))
  (pacer2-forget!)
  (fluid-let ([*pacer2-t* 0] [*pacer2-hold* 0] [*pacer2-floor* 0]
              [*pacer2-proven* 0] [*pacer2-probe* 0]
              [*pacer2-probe-miss* 0] [*pacer2-probed* T]
              [*pacer2-soft?* #f] [*pacer2-waited* 0] [*pacer2-aim* 0]
              [*pacer2-plan* 0] [*pacer-rate* 'screen] [*dirty* #f]
              [*pacer-wanted?* #f] [*timers* '()]
              [*pacer2-judged* (- *frame-ring-n* 16)])
    (let* ([lo (- *frame-ring-n* 16)] [now (+ T (* 18 r))]
           [judging (allocation-least 20
                      (lambda ()
                        (set! *pacer2-judged* lo)
                        (set! *pacer2-hold* (* 3 ms))
                        (set! *pacer2-soft?* #f)
                        (pacer2-decide! now)))]
           [raised *pacer2-hold*]
           [planning (allocation-least 20
                       (lambda ()
                         (set! *pacer-wanted?* #t)
                         (pacer2-decide! now)))]
           [begun (allocation-least 20
                    (lambda ()
                      (set! *pacer-wanted?* #t)
                      (pacer2-begin? (+ now r))))]
           [not-begun (allocation-least 20
                        (lambda ()
                          (set! *pacer-wanted?* #t)
                          (pacer2-begin? (- now (* 5 r)))))]
           [share (allocation-least 20 pacer2-procs-ms)]
           [wait (allocation-on-clock
                  (lambda () (allocation-least 20 pacer2-wait-ns)))]
           [wait-timer (fluid-let ([*timers* '()])
                         (after 60000 void)
                         (allocation-on-clock
                          (lambda ()
                            (allocation-least 20 pacer2-wait-ns))))])
      (check (format "the second pacer allocates nothing: judging rows with \
                      a pair of misses (~a bytes; the hold raised to ~a), \
                      planning (~a), a turn begun and not (~a ~a), \
                      processes' share (~a), the loop's wait without a \
                      timer and with (~a ~a)"
                     judging raised planning begun not-begun share wait
                     wait-timer)
             ;; the pair's 5 ms of lead over the hold of 3 by more than
             ;; the margin: raised to the margin and a look over it
             (and (= raised (+ (* 3 ms) (pacer2-margin r) core0-look-ns))
                  (for-all zero? (list judging planning begun not-begun
                                       share wait wait-timer)))))))

;;; A library's procedures carry nothing. A variable of a library's own is
;;; held by every procedure that reads it, and by every procedure that
;;; calls one of those, so a closure made at run time that only calls one
;;; of them carries it, and is allocated where the same closure at the top
;;; level, which named a global, was not. So what a library makes as it
;;; loads is a state or a made value (define-state, define-made:
;;; schevana/base.sls), and a procedure it defines is no closure at all.
;;; Chez's inspector is asked this of each procedure that a library of the
;;; core's defines and exports; what a state, a made value or a hook holds
;;; is its own business.
(let ()
  ;; a library's file, read: (library name (export ...) (import ...) . body)
  (define (library-form file)
    (call-with-input-file (string-append *schevana-root* "/" file) read))
  ;; the names its body defines as procedures
  (define (procedures-defined body)
    (filter-map
     (lambda (x)
       (and (pair? x) (pair? (cdr x))
            (case (car x)
              [(define)
               (cond [(pair? (cadr x)) (caadr x)]
                     [(and (pair? (cddr x)) (pair? (caddr x))
                           (memq (car (caddr x)) '(lambda case-lambda)))
                      (cadr x)]
                     [else #f])]
              [(define-foreign define-foreign/collect-safe) (cadr x)]
              [else #f])))
     body))
  (define (carries p) ((inspect/object p) 'length))
  (check "no procedure a library of the core's defines carries anything"
         (let ([found
                (apply
                 append
                 (map (lambda (file)
                        (let* ([form (library-form file)]
                               [name (cadr form)]
                               [exported (library-exports name)]
                               [e (environment name)])
                          (filter-map
                           (lambda (p)
                             (and (memq p exported)
                                  (let ([v (eval p e)])
                                    (and (procedure? v) (> (carries v) 0)
                                         (format "~s: ~a carries ~a" name p
                                                 (carries v))))))
                           (procedures-defined (cddddr form)))))
                      test-core-libraries))])
           (for-each (lambda (f) (printf "  ~a\n" f)) found)
           (null? found))))
