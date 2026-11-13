;;; tests/units/present.ss — what the screen says of each frame: its reports
;;; (src/host/present.ss), joined to the frames drawn and the input they
;;; show (kits/inspect.ss). Headless, nothing reports, so the reports here
;;; are written as the screen's callbacks would write them.

;; Frame i's report, as core0 begins it at sent and the screen fills it:
;; kind (1 shown, 2 dropped), shown, the display's sequence, GPU done.
(define (present-test-report! i sent kind shown seq done)
  (let* ([n (inspect-frame-ref i 6)]
         [r *present-ring*]
         [at (* present-words (modulo n present-rows))])
    (fxvector-set! r at n)
    (fxvector-set! r (+ at 2) sent)
    (fxvector-set! r (+ at 6) done)
    (present-reported! n kind shown (host-frame-ns) seq)))

;; Four frames drawn, the second showing input that came at in.
(define present-test-in 0)
(define present-test-first
  (let ([first *frame-ring-n*])
    (do ([k 0 (+ k 1)]) ((= k 4))
      (when (= k 1)
        (set! present-test-in (now-ns))
        (frame-input-came! present-test-in 0 0))
      (request-frame!)
      (steps 1))
    first))

(let* ([p (host-frame-ns)]
       [t (+ (now-ns) (* 10 p))]
       [i present-test-first])
  ;; sent a refresh apart; shown 3 refreshes on, the third a refresh late
  ;; (its GPU done only after the refresh it missed), the fourth dropped
  (present-test-report! i t 1 (+ t (* 3 p)) 100 (+ t 1000000))
  (present-test-report! (+ i 1) (+ t p) 1 (+ t (* 4 p)) 101
                        (+ t p 1000000))
  (present-test-report! (+ i 2) (+ t (* 2 p)) 1 (+ t (* 6 p)) 103
                        (+ t (* 5 p) 1000000))
  (present-test-report! (+ i 3) (+ t (* 3 p)) 2 0 0 0)
  (check (format "a frame's report says where it went: shown in time, late \
                  by the refreshes the screen showed the one before again, \
                  or dropped (~a ~a ~a ~a, ~a missed)"
                 (inspect-frame-screen i) (inspect-frame-screen (+ i 1))
                 (inspect-frame-screen (+ i 2)) (inspect-frame-screen (+ i 3))
                 (inspect-frame-missed (+ i 2)))
         (and (memq (inspect-frame-screen i) '(shown #f))
              (eq? (inspect-frame-screen (+ i 1)) 'shown)
              (eq? (inspect-frame-screen (+ i 2)) 'late)
              (eqv? (inspect-frame-missed (+ i 2)) 1)
              (eq? (inspect-frame-screen (+ i 3)) 'dropped)))
  (check "a late frame's GPU was late when its work was seen done only after \
          the refresh it missed; otherwise it was done in time"
         (and (eq? (inspect-frame-gpu (+ i 1)) 'done)
              (eq? (inspect-frame-gpu (+ i 2)) 'late)
              (not (inspect-frame-gpu (+ i 3)))))
  (check (format "a frame that shows input says how long after it it showed \
                  (~a ns); one that shows none says nothing"
                 (inspect-frame-latency (+ i 1)))
         (and (= (inspect-frame-latency (+ i 1))
                 (- (+ t (* 4 p)) present-test-in))
              (not (inspect-frame-latency (+ i 2)))))
  (let-values ([(p50 p99 missed) (inspect-frames-truth 100000)])
    (check (format "the frames of the last seconds sum up: the input's time \
                    to the screen, and the refreshes missed (~a ~a ~a)"
                   p50 p99 missed)
           (and (= p50 p99 (inspect-frame-latency (+ i 1)))
                (= missed 1)))))

(check "a report taken over by a later frame's says nothing of the earlier"
       (let ([n (inspect-frame-ref present-test-first 6)])
         (not (host-frame-report (+ n present-rows) 1))))

(check "input that asked for no frame shows in none: the next frame says \
        nothing of it"
       (begin
         (frame-input-came! (now-ns) 0 0)
         (frame-turn-soon!)
         (steps 1)
         (request-frame!)
         (steps 1)
         (eqv? (inspect-frame-ref (- *frame-ring-n* 1) 7) 0)))

(check "a frame keeps when its tick, its draw and its publish came, in that \
        order, and its oldest input three ways: SDL's stamp, core0's pump, \
        the compositor's time"
       (let ([t (now-ns)])
         (frame-input-came! (- t 3000000) (- t 2000000) (- t 4000000))
         (request-frame!)
         (steps 1)
         (let ([i (- *frame-ring-n* 1)])
           (and (= (inspect-frame-at i 'sdl) (- t 3000000))
                (= (inspect-frame-at i 'pumped) (- t 2000000))
                (= (inspect-frame-at i 'wl) (- t 4000000))
                ;; unpaced, a tick's time is the pacer's ms
                (<= (- t 1000000) (inspect-frame-at i 'tick)
                    (inspect-frame-at i 'draw)
                    (inspect-frame-at i 'publish))))))

(check "the newest frames, not yet sent and so with no report, leave the \
        last seconds' sums to those before them"
       (let ([p (host-frame-ns)])
         (frame-input-came! (- (now-ns) 3000000) 0 0)
         (request-frame!)
         (steps 1)
         (let* ([i (- *frame-ring-n* 1)] [n (inspect-frame-ref i 6)]
                [publish (inspect-frame-at i 'publish)] [at (present-at n)]
                [r *present-ring*])
           (fxvector-set! r at n)
           (fxvector-set! r (+ at 1) 1)
           (fxvector-set! r (+ at 2) (+ publish 2000000))
           (fxvector-set! r (+ at 3) (+ publish p))
           ;; one more, its row another frame's: core0 hasn't sent it
           (request-frame!)
           (steps 1)
           (let ([m (inspect-frame-ref (- *frame-ring-n* 1) 6)])
             (fxvector-set! r (present-at m) (- m present-rows)))
           ;; stopped at the newest, nothing would be summed
           (let-values ([(p50 p99 missed) (inspect-frames-truth 10000)])
             (and p50 (<= p50 p99))))))

(check "the frames' truth for several inputs' points, in one walk, is each \
        point's own"
       (let-values ([(by missed) (inspect-frames-truths 1000000
                                                        '(sdl wl pumped))])
         (and (= (length by) 3)
              (caar by)             ; SDL's, from the check before
              (for-all (lambda (point p)
                         (let-values ([(p50 p99 m)
                                       (inspect-frames-truth 1000000 point)])
                           (and (equal? (list p50 p99) p) (= m missed))))
                       '(sdl wl pumped) by))))

(check "frames in flight is a setting that goes to core0 with each frame: \
        two, and core0 builds the swapchain so and says so; three again"
       (let ([in-flight (lambda ()
                          (request-frame!)
                          (steps 2)
                          (gpu-facts-refresh!)
                          (cons *gpu-frames-in-flight*
                                (cdr (assq 'frames-in-flight *gpu-facts*))))])
         (override! 'frames-in-flight 2)
         (let ([two (in-flight)])
           (override! 'frames-in-flight)
           (let ([three (in-flight)])
             (and (equal? two '(2 . 2)) (equal? three '(3 . 3)))))))
