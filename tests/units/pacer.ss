;;; tests/units/pacer.ss — the pacer: exactly one tick a period while the work
;;; fits.

;;; The pacer: exactly one tick a period while the work fits.

;; The main loop for ms of a fake clock (ns), with a wait for host events
;; that only moves the clock, and a frame that, with vsync?, waits for the
;; screen's next refresh. In it: a window whose
;; tick keeps books (3 ms) and never draws, one that moves at every tick
;; (2 ms of its tick, draw-ms of drawing), a busy process (0.5 ms a
;; slice) if opts has 'busy, a timer at 205 ms, a key at 503 ms, and with
;; 'flood a key every 2 ms besides, each ending the wait. => an alist of
;; what happened: the bookkeeper's ticks' times, the frames drawn, the
;; steps, the process's slices, when the timer ran, and whether the key
;; came. At most 50 steps a ms of the clock: past that the loop spins.
(define (pacer-test-run vsync? draw-ms ms . opts)
  (let* ([real-ns now-ns] [real-ms now-ms] [real-events host-events]
         [real-present rec-present!] [rate (pacer-rate)]
         [period (pacer-period)]
         [t 0] [ticks '()] [frames 0] [slices 0] [fired #f]
         [keyed #f] [stepped 0] [flood-at #f]
         [advance (lambda (ns) (set! t (+ t ns)))])
    (set! now-ns (lambda () t))
    (set! now-ms (lambda () (quotient t 1000000)))
    ;; the wait for input ends at the next key of a flood
    (set! host-events
          (lambda (wait-ms)
            (let ([until (+ t (* wait-ms 1000000))])
              (if (and flood-at (<= flood-at until))
                  (begin (set! t (max t flood-at))
                         (set! flood-at (+ t 2000000))
                         '((key-down #\b ())))
                  (begin (set! t until) '())))))
    (set! rec-present!
          (lambda ()
            (let ([shown? (real-present)])
              (when vsync?   ; to the next refresh
                (host-screen-wait
                 'submit
                 (lambda () (set! t (* period (+ 1 (quotient t period)))))))
              shown?)))
    (pacer-rate! 'screen)
    (let* ([keeper (open-window "Keeper" 'size '(80 . 60)
                                'tick (lambda (win)
                                        (set! ticks (cons t ticks))
                                        (advance 3000000)))]
           [mover (open-window "Mover" 'size '(80 . 60)
                               'tick (lambda (win)
                                       (advance 2000000)
                                       (invalidate! win))
                               'key (lambda (win k mods) (set! keyed #t))
                               'draw (lambda (win w h)
                                       (advance (* draw-ms 1000000))
                                       (set! frames (+ frames 1))))]
           [p (and (memq 'busy opts)
                   (spawn "paced" (lambda ()
                                    (let loop ()
                                      (advance 500000)
                                      (set! slices (+ slices 1))
                                      (engine-block)
                                      (loop)))))])
      (focus-window! mover)
      ;; 100 ms to settle (the first frame has no drawing time to go by)
      (let ([settled (+ t 100000000)])
        (let loop ()
          (when (< t settled) (schevana-step! (pacer-wait-ms) #t) (loop))))
      (set! ticks '())
      (set! frames 0)
      (set! slices 0)
      (let ([start (now-ms)])
        (after 205 (lambda () (set! fired (- (now-ms) start)))))
      (when (memq 'flood opts) (set! flood-at t))
      (let ([end (+ t (* ms 1000000))] [key-at (+ t 503000000)])
        (let loop ()
          (when (and (< t end) (< stepped (* 50 ms)))
            (when (and key-at (>= t key-at))
              (inject! '(key-down #\a ()))
              (set! key-at #f))
            (schevana-step! (pacer-wait-ms) #t)
            (set! stepped (+ stepped 1))
            (loop))))
      (when p (kill! p))
      (close-window! keeper)
      (close-window! mover)
      (set! now-ns real-ns)
      (set! now-ms real-ms)
      (set! host-events real-events)
      (set! rec-present! real-present)
      (pacer-rate! rate)
      (steps 1)
      `((ticks . ,(reverse ticks)) (frames . ,frames) (steps . ,stepped)
        (slices . ,slices) (fired . ,fired) (keyed . ,keyed)
        (period . ,period)))))

;; The gaps between ticks at times ts, ns.
(define (pacer-test-gaps ts)
  (map - (cdr ts) (list-head ts (- (length ts) 1))))

(check "the pacer ticks exactly once a period while the work fits, with \
        vsync or without, bookkeeping that draws nothing, a busy process \
        and input between: a frame a tick, the process in the time left, \
        a timer on its time"
       (for-all
        (lambda (vsync?)
          (let* ([r (pacer-test-run vsync? 5 1000 'busy)]
                 [get (lambda (k) (cdr (assq k r)))]
                 [ticks (get 'ticks)] [period (get 'period)]
                 [gaps (pacer-test-gaps ticks)])
            (printf "  vsync ~a: ~a ticks, ~a frames, ~a slices, gaps ~a..~a, \
                     timer at ~a\n"
                    vsync? (length ticks) (get 'frames) (get 'slices)
                    (apply min gaps) (apply max gaps) (get 'fired))
            ;; 1,000 ms of 16.7: 60 periods, 61 ticks at their ends
            (and (<= 60 (length ticks) 61)
                 ;; a period apart on average, to the ms
                 (< (abs (- (quotient (- (car (last-pair ticks)) (car ticks))
                                      (length gaps))
                            period))
                    1000000)
                 ;; and each: with vsync, give or take the 2 ms a tick may
                 ;; start early and the clock's ms; without, also a frame
                 ;; that input asked for (5 ms) drawn just before a tick
                 (for-all (lambda (g)
                            (< (abs (- g period)) (if vsync? 3000000 8000000)))
                          gaps)
                 (<= (abs (- (get 'frames) (length ticks))) 2)
                 ;; the time left, a wait for the screen no part of the
                 ;; frame's: far more than the 1 ms a tick they always get
                 (> (get 'slices) (* 4 (length ticks)))
                 (get 'keyed)
                 ;; at the step after its time: within a period
                 (<= 205 (get 'fired) (+ 205 17)))))
        '(#t #f)))

(check "with nothing else to do, the loop sleeps between ticks: a step a \
        tick, and those of a timer and a key, with vsync or without"
       (for-all
        (lambda (vsync?)
          (let* ([r (pacer-test-run vsync? 5 1000)]
                 [ticks (length (cdr (assq 'ticks r)))]
                 [steps (cdr (assq 'steps r))])
            (printf "  vsync ~a: ~a ticks, ~a steps\n" vsync? ticks steps)
            (and (<= 60 ticks 61) (<= steps (+ ticks 5)))))
        '(#t #f)))

(check "without the screen's wait, input draws at the next tick: a key \
        every 2 ms, and still a frame a tick, a tick a period"
       (let* ([r (pacer-test-run #f 5 1000 'flood)]
              [ticks (cdr (assq 'ticks r))] [frames (cdr (assq 'frames r))]
              [steps (cdr (assq 'steps r))])
         (printf "  ~a ticks, ~a frames, ~a steps\n" (length ticks) frames
                 steps)
         (and (<= 60 (length ticks) 61) (<= frames (length ticks))
              (> steps 200))))

(check "the profiler keeps a tick, not a step: the steps between ticks \
        (a key every 2 ms) sum into the tick they lead up to, each about \
        a period long"
       (let* ([r #f]
              [made (profile-test-ticks
                     (lambda () (set! r (pacer-test-run #f 5 1000 'flood))))]
              [ticks (length (cdr (assq 'ticks r)))]
              [steps (cdr (assq 'steps r))]
              [period (cdr (assq 'period r))]
              ;; the run's, newest first: not the step after it, nor the
              ;; ticks of its 100 ms of settling
              [run (list-head (cdr made) (- ticks 1))]
              [lengths (map (lambda (seq) (profile-tick-ns seq 'ns)) run)])
         (printf "  ~a ticks, ~a steps, ~a kept, ~a..~a ns\n" ticks steps
                 (length made) (apply min lengths) (apply max lengths))
         (and (> steps (* 3 ticks)) (<= (length made) (+ ticks 10))
              (for-all (lambda (ns) (< (abs (- ns period)) 3000000))
                       lengths))))

(check "past a period of work, the pacer slows down: ticks come as soon \
        as the last is done, none skipped, none closer than a period"
       (let* ([r (pacer-test-run #t 20 1000)]
              [ticks (cdr (assq 'ticks r))] [period (cdr (assq 'period r))]
              [gaps (pacer-test-gaps ticks)])
         (printf "  ~a ticks, gaps ~a..~a\n" (length ticks) (apply min gaps)
                 (apply max gaps))
         (and (< 20 (length ticks) 45)
              (for-all (lambda (g) (>= g (- period 3000000))) gaps))))

;; The main loop on a fake clock, for ms, against a screen as a Wayland log
;; has GNOME's: a frame goes up at the first of its cutoffs (one a period)
;; after it's sent and after the one before it showed, shows 5 ms later, and
;; says so 14 ms after that; with two frames not yet reported, main waits for
;; its image. The first frame sets the cutoffs just before it, so the rest,
;; each a little early or late by its tick, lie on the edge. => (ticks holds
;; shows margins): the ticks, and frame by frame what main waited, when it
;; showed, and how long before the next cutoff it went.
(define (pacer-test-screen ms)
  (let* ([real-ns now-ns] [real-ms now-ms] [real-events host-events]
         [real-present rec-present!] [rate (pacer-rate)]
         [period (pacer-period)]
         [t 0] [cuts #f] [last-show 0] [reports '()] [ticks 0] [n 0]
         [holds '()] [shows '()] [margins '()])
    (define (next-cut at)
      (+ cuts (* period (ceiling (/ (- at cuts) period)))))
    (set! now-ns (lambda () t))
    (set! now-ms (lambda () (quotient t 1000000)))
    (set! host-events
          (lambda (wait-ms) (set! t (+ t (* wait-ms 1000000))) '()))
    (set! rec-present!
          (lambda ()
            (let ([t0 t])
              (host-screen-wait
               'acquire
               (lambda ()
                 (set! reports (filter (lambda (r) (> r t)) reports))
                 (when (>= (length reports) 2)
                   (set! t (apply min reports)))))
              (set! holds (cons (- t t0) holds)))
            (set! t (+ t 200000))
            (unless cuts (set! cuts (- t 1700000)))
            (let* ([cut (max (next-cut t) (next-cut last-show))]
                   [show (+ cut 5000000)])
              (set! margins (cons (- (next-cut t) t) margins))
              (set! shows (cons show shows))
              (set! reports (cons (+ show 14000000) reports))
              (set! last-show show))
            #t))
    (pacer-rate! 'screen)
    (let ([mover (open-window "Mover" 'size '(80 . 60)
                              'tick (lambda (win)
                                      (set! ticks (+ ticks 1))
                                      (set! n (+ n 1))
                                      ;; 1 to 3 ms, as it comes
                                      (set! t (+ t 1000000
                                                 (* 500000 (mod (* n 7) 5))))
                                      (invalidate! win))
                              'draw (lambda (win w h)
                                      (set! t (+ t 1000000))))]
          [end (* ms 1000000)])
      (focus-window! mover)
      (let loop ()
        (when (< t end) (schevana-step! (pacer-wait-ms) #t) (loop)))
      (close-window! mover))
    (set! now-ns real-ns)
    (set! now-ms real-ms)
    (set! host-events real-events)
    (set! rec-present! real-present)
    (pacer-rate! rate)
    (steps 1)
    (list ticks (reverse holds) (reverse shows) (reverse margins) period)))

;; How many frames from the kth on came a refresh or more late on the
;; screen, and were held for their image; the least margin.
(define (pacer-test-screen-after result k)
  (let* ([period (list-ref result 4)]
         [holds (list-tail (cadr result) k)]
         [shows (list-tail (caddr result) k)]
         [margins (list-tail (cadddr result) k)])
    (list (length (filter (lambda (g) (> g (* 3/2 period)))
                          (pacer-test-gaps shows)))
          (length (filter (lambda (h) (>= h pacer-hold-least)) holds))
          (apply min margins))))

(check "the pacer times frames from the screen: past a cutoff once, a frame \
        keeps the screen's refresh from then on, no frame shown late, no \
        wait for an image, a quarter of a period clear of the cutoff or \
        more, however its ticks vary; every tick \
        goes on; left to itself, it goes on missing"
       (let* ([timed (pacer-test-screen 4000)]
              [untimed (fluid-let ([pacer-image-waited! (lambda (t) (void))])
                         (pacer-test-screen 4000))]
              [period (list-ref timed 4)]
              [after (pacer-test-screen-after timed 30)]
              [without (pacer-test-screen-after untimed 30)])
         (printf "  timed: ~a ticks, ~a frames; after a settling: late, held, \
                  margin ~a\n"
                 (car timed) (length (cadr timed)) after)
         (printf "  untimed: ~a ticks, ~a frames; ~a\n"
                 (car untimed) (length (cadr untimed)) without)
         (and (>= (car timed) (- (quotient 4000000000 period) 4))
              (= (car after) 0)
              (= (cadr after) 0)
              (> (caddr after) (quotient period 4))
              (> (+ (car without) (cadr without)) 0))))

(check "(pacer-rate! 30) halves the ticks in real time, and 'screen brings \
        the screen's back"
       (let ([rate (pacer-rate)])
         (pacer-rate! 30)
         (let ([p30 (pacer-period)])
           (pacer-rate! 'screen)
           (let ([screen (pacer-period)])
             (pacer-rate! rate)
             (and (= p30 33333333) (= screen (host-frame-ns)))))))

;;; What a tick takes, but its waits: kept whether the profiler is on or not.

;; thunk on a fake clock, far past any tick due, with a wait for events of
;; pacer-test-wait ms and a frame that waits 7 ms for the screen, as the
;; swapchain's may.
(define pacer-test-t 1000000000000)
(define pacer-test-wait 5)
(define (pacer-test-advance! ms)
  (set! pacer-test-t (+ pacer-test-t (* ms 1000000))))
(define (pacer-test-on-fake-clock thunk)
  (fluid-let ([now-ns (lambda () pacer-test-t)]
              [host-events (lambda (wait-ms)
                             (pacer-test-advance! pacer-test-wait)
                             '())]
              [rec-present!
               (let ([present rec-present!])
                 (lambda ()
                   (let ([shown? (present)])
                     (host-screen-wait 'submit
                                       (lambda () (pacer-test-advance! 7)))
                     shown?)))])
    (thunk)))

(let ([win (open-window "Busy" 'size '(80 . 60)
                        'tick (lambda (win)
                                (pacer-test-advance! 3)
                                (invalidate! win))
                        'key (lambda (win k mods) (pacer-test-advance! 2)))])
  (focus-window! win)
  (let* ([on #f]
         [profiled (profile-busy
                    (car (profile-test-ticks
                          (lambda ()
                            (pacer-test-on-fake-clock
                             (lambda ()
                               (steps 1)
                               (set! on (pacer-busy-ms))))))))]
         [off (begin
                (profile-on! #f)
                (let ([ms (pacer-test-on-fake-clock
                           (lambda () (steps 1) (pacer-busy-ms)))])
                  (profile-on! #t)
                  ms))])
    (check (format "a tick's busy time is its work, not its waits for input \
                    or the screen, profiling on (~a ms) or off (~a), and is \
                    the profiler's own (~a)" on off profiled)
           (and (= on 3.0) (= off 3.0) (= profiled 3.0))))
  (check "a frame's wait for the screen is the profiler's phase of its own, \
          not render, and no part of the frame's time or of what the pacer \
          keeps from processes"
         (let ([seq (car (profile-test-ticks
                          (lambda ()
                            (pacer-test-on-fake-clock
                             (lambda ()
                               (pacer-test-advance! 100)
                               (schevana-step! 0 'paced))))))])
           (and (= (profile-tick-phase-ms seq 'vsync-wait) 7)
                (zero? (profile-tick-phase-ms seq 'render))
                (zero? *frame-ms*))))
  (check "steps between ticks sum into the tick they lead up to"
         (pacer-test-on-fake-clock
          (lambda ()
            (schevana-step! 0 'paced)     ; a tick: the next is a period off
            (fluid-let ([pacer-test-wait 0])
              (inject! '(key-down #\a ()))
              (schevana-step! 0 'paced)   ; between ticks: the key's 2 ms
              (let ([between? *pacer-between?*] [before (pacer-busy-ms)])
                (pacer-test-advance! 100)
                (schevana-step! 0 'paced) ; a tick: its 3 ms, and the 2
                (and between? (= before 3.0) (= (pacer-busy-ms) 5.0)))))))
  (check "the peak is the most any tick took since it was last asked, and the \
          top bar shows it"
         (pacer-test-on-fake-clock
          (lambda ()
            (inject! '(key-down #\a ()))
            (steps 1)                     ; 3 ms and the key's 2
            (let* ([shown ((cdr (assq 'busy *status-segments*)))]
                   [after (begin (steps 1) (pacer-peak-ms!))])
              (and (not (assq 'frame *status-segments*))
                   (equal? shown "5.0 ms/tick")
                   (= after 3.0)
                   (= (pacer-peak-ms!) 0.0))))))
  (close-window! win))
