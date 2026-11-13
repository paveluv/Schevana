;;; tests/units/pacer.ss — the pacer: exactly one tick a period while the work
;;; fits.

;;; The pacer: exactly one tick a period while the work fits.

;; The screen held core1 from start to end: a wait, the profiler's
;; vsync-wait, and no work.
(define (pacer-test-screen-waited! start end)
  (profile-span-past! 'vsync-wait 'submit start end)
  (pacer-held! (- end start)))

;; Core1's loop for ms of a fake clock (ns), with a wait for core0's events
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
  (let* ([real-ns now-ns] [real-ms now-ms] [real-events screen-events]
         [real-present rec-present!] [rate (pacer-rate)]
         [period (pacer-period)]
         [t 0] [ticks '()] [frames 0] [slices 0] [fired #f]
         [keyed #f] [stepped 0] [flood-at #f]
         [advance (lambda (ns) (set! t (+ t ns)))])
    (set! now-ns (lambda () t))
    (set! now-ms (lambda () (quotient t 1000000)))
    ;; the wait for input ends at the next key of a flood
    (set! screen-events
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
                (let ([t0 t])
                  (set! t (* period (+ 1 (quotient t period))))
                  (pacer-test-screen-waited! t0 t)))
              shown?)))
    (pacer-rate! 'screen)
    (let* ([keeper (open-window "Keeper" 'size '(80 . 60)
                                'open window-frame-soon!
                                'frame (lambda (win at)
                                         (window-frame-soon! win)
                                         (set! ticks (cons t ticks))
                                         (advance 3000000)))]
           [mover (open-window "Mover" 'size '(80 . 60)
                               'open window-frame-soon!
                               'frame (lambda (win at)
                                        (window-frame-soon! win)
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
      (set! screen-events real-events)
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

;; Core1's loop on a fake clock, for ms, against a screen as core0 on a
;; thread of its own has one: the frame it presents is held till the next
;; refresh, one a period, then its successor, waiting in the box, is taken
;; and held till the one after; core0 wakes core1 as it takes one, and core1
;; wakes up to 9 ms later, and gives each back as it shows. The screen is
;; away (holds) from away-from to away-to, and refreshes fast ns sooner
;; than the period it reports. Core1 runs as with core0 on a thread of its
;; own. A mover asks a frame each tick, working 1 to 3 ms, and draws at
;; every one; a timer counts every 10 ms. Options, a plist: 'rate, the
;; pacer's rate for the run; 'draw-every n, the mover drawing at every nth
;; tick only; 'mailbox #t, a screen that holds nothing, taking each frame
;; at once; 'full #t, a screen with no room, each frame given back at once,
;; not shown; 'slow r, a screen that refreshes r times the period it
;; reports. => (refreshes frozen ts
;; frames-away timers-away shows leads ticks): the refreshes that showed a
;; frame, those that showed none while the mover moved and the screen was
;; there, each 'frame's t, the 'frame calls while the screen was away, the
;; timers then, when each frame showed, each 'frame's t less the clock
;; then, and the ticks.
(define (pacer-test-lock ms away-from away-to fast . opts)
  (let* ([real-ns now-ns] [real-ms now-ms] [real-events screen-events]
         [real-present rec-present!] [real-waiting gpu-frame-waiting?]
         [rate (pacer-rate)] [mailbox? (plist-ref opts 'mailbox #f)]
         [full? (plist-ref opts 'full #f)]
         [draw-every (plist-ref opts 'draw-every 1)]
         [p (* (plist-ref opts 'slow 1) (- (core0-frame-ns) fast))]
         [t 0] [held-to #f] [boxed? #f]
         [shows '()] [ts '()] [leads '()] [away-frames 0] [away-timers 0]
         [n 0] [end (* ms 1000000)] [ticks (pacer-ticks)])
    (define (away? at) (< (* away-from 1000000) at (* away-to 1000000)))
    ;; the first refresh from at on, the screen there
    (define (refresh-from at) (if (away? at) (refresh-from (+ at p)) at))
    ;; core0 and the screen, up to the clock
    (define (screen!)
      (let loop ()
        (when (and held-to (<= held-to t))
          (set! shows (cons held-to shows))
          (pacer-frame-back! #t)
          (cond [boxed? (set! boxed? #f)
                        (set! held-to (refresh-from (+ held-to p)))]
                [else (set! held-to #f)])
          (loop))))
    (set! now-ns (lambda () t))
    (set! now-ms (lambda () (quotient t 1000000)))
    (set! gpu-frame-waiting? (lambda () (screen!) boxed?))
    (set! screen-events
          (lambda (wait-ms)
            (let ([until (+ t (* wait-ms 1000000))]
                  ;; core0 wakes core1 as it takes a frame; core1 wakes late
                  [woken (and boxed? held-to
                              (+ held-to
                                 (* 1000000
                                    (mod (* (length shows) 7919) 10))))])
              (set! t (if (and woken (< woken until)) woken until))
              (screen!)
              '())))
    (set! rec-present!
          (lambda ()
            (screen!)
            (cond [mailbox? (pacer-frame-back! #t)]
                  [full? (pacer-frame-back! #f)]
                  [held-to (set! boxed? #t)]
                  [else
                   (set! held-to (refresh-from (* p (+ 1 (quotient t p)))))])
            0))   ; its number: none the screen reports on
    (pacer-rate! (plist-ref opts 'rate 'screen))
    (let ([mover (open-window "Mover" 'size '(80 . 60)
                              'open window-frame-soon!
                              'frame (lambda (win at)
                                       (window-frame-soon! win)
                                       (set! n (+ n 1))
                                       (set! ts (cons at ts))
                                       (set! leads (cons (- at t) leads))
                                       (when (away? t)
                                         (set! away-frames (+ away-frames 1)))
                                       (set! t (+ t 1000000
                                                  (* 500000 (mod (* n 7) 5))))
                                       (when (= 0 (mod n draw-every))
                                         (invalidate! win)))
                              'draw (lambda (win w h) (set! t (+ t 1000000))))])
      (focus-window! mover)
      (let tick ()
        (after 10 (lambda ()
                    (when (away? t) (set! away-timers (+ away-timers 1)))
                    (when (< t end) (tick)))))
      ;; t starts on the fake clock: the real clock's is seconds ahead of
      ;; it, and t comes back to the screen only when it falls behind
      (fluid-let ([*core0-forked* #t]
                  [*pacer-frame-ns* 0]
                  [*gpu-facts* (cons (cons 'present-mode
                                           (if mailbox? 'mailbox 'vsync))
                                     *gpu-facts*)])
        (let loop ()
          (when (< t end) (schevana-step! (pacer-wait-ms) #t) (loop))))
      (close-window! mover))
    (set! now-ns real-ns)
    (set! now-ms real-ms)
    (set! screen-events real-events)
    (set! rec-present! real-present)
    (set! gpu-frame-waiting? real-waiting)
    (set! ticks (- (pacer-ticks) ticks))
    (pacer-rate! rate)
    (steps 1)
    (let ([shows (reverse shows)])
      (list (length shows)
            ;; a gap of more than a refresh between shows, but the screen's
            ;; time away and the first few
            (if (< (length shows) 4)
                0
                (let count ([s (list-tail shows 3)] [k 0])
                  (if (null? (cdr s))
                      k
                      (count (cdr s)
                             (if (and (> (- (cadr s) (car s)) (* 3/2 p))
                                      (not (<= (car s) (* away-from 1000000)
                                               (cadr s))))
                                 (+ k 1)
                                 k)))))
            (reverse ts) away-frames away-timers shows (reverse leads)
            ticks))))

(let* ([r (pacer-test-lock 2000 1000 1300 0)]
       [ts (caddr r)]
       [steps (list-tail (pacer-test-gaps ts) 3)]
       [shows (list-ref r 5)]
       [p (core0-frame-ns)]
       ;; t less when its frame showed, but for frames made before the
       ;; screen went away and shown after
       [leads (let lead ([ts ts] [shows shows])
                (cond [(or (null? ts) (null? shows)) '()]
                      [(< (car ts) (* 1300 1000000) (car shows))
                       (lead (cdr ts) (cdr shows))]
                      [else (cons (- (car ts) (car shows))
                                  (lead (cdr ts) (cdr shows)))]))])
  (check (format "frame turns follow the screen: every refresh of ~a, the \
                  screen there, finds a frame waiting (~a froze), each \
                  frame's t is a refresh after the last's, to 0.5 ms, \
                  however late core1 wakes, by half a frame too (~a..~a), \
                  and when it shows, to a refresh (~a..~a)"
                 (car r) (cadr r) (apply min steps) (apply max steps)
                 (apply min leads) (apply max leads))
         (and (> (car r) 100)
              (= (cadr r) 0)
              (for-all (lambda (d) (or (< (abs (- d p)) 500000)
                                       (> d (* 10 p))))
                       steps)
              (for-all (lambda (d) (<= (abs d) p)) leads)))
  (check (format "while the screen is away no frame turn runs, and timers go \
                  on (~a frames, ~a timers)" (cadddr r) (car (cddddr r)))
         (and (<= (cadddr r) 1) (> (car (cddddr r)) 20))))

(let ([r (pacer-test-lock 3000 0 0 100000)])
  (check (format "a screen a little faster than it says still gets a frame \
                  every refresh: core1's clock never holds one back (~a \
                  refreshes, ~a froze)" (car r) (cadr r))
         (and (> (car r) 150) (= (cadr r) 0))))

(for-each
 (lambda (opts what)
   (let* ([r (apply pacer-test-lock 2000 0 0 0 opts)]
          [ticks (list-ref r 7)]
          [leads (list-tail (list-ref r 6) 5)]
          [p (core0-frame-ns)])
     ;; t starts a period ahead and slides toward two; turns that ran
     ;; away would carry it seconds ahead
     (check (format "turns that send the screen no frame it holds keep to \
                     the pacer's period, and t to the clock: ~a, ~a turns \
                     in 2 s, t ~,1f to ~,1f ms ahead of the clock"
                    what ticks (/ (apply min leads) 1e6)
                    (/ (apply max leads) 1e6))
            (and (<= 118 ticks 124)
                 (for-all (lambda (d) (< 0 d (* 3 p))) leads)))))
 '((draw-every 30) (mailbox #t) (full #t))
 '("a mover that draws every 30th turn" "frames presented by mailbox"
   "frames the screen has no room for"))

(let* ([r (pacer-test-lock 2000 0 0 0 'slow 3/2)]
       [p (core0-frame-ns)]
       [steps (list-tail (pacer-test-gaps (caddr r)) 3)]
       [leads (list-tail (list-ref r 6) 5)])
  (check (format "with a screen slower than it says, each frame's t steps \
                  whole refreshes (~a..~a ms) and keeps to the clock, ~,1f \
                  to ~,1f ms ahead"
                 (/ (apply min steps) 1e6) (/ (apply max steps) 1e6)
                 (/ (apply min leads) 1e6) (/ (apply max leads) 1e6))
         (and (for-all (lambda (d)
                         (< (abs (- d (* p (round (/ d p))))) 500000))
                       steps)
              ;; just after a whole step, t may be under the clock
              (for-all (lambda (d) (< (- p) d (* 3 p))) leads))))

(let* ([r (pacer-test-lock 2000 0 0 0 'rate 30)]
       [ticks (list-ref r 7)]
       [steps (list-tail (pacer-test-gaps (caddr r)) 3)])
  (check (format "(pacer-rate! 30) halves the frame turns, the screen at 60 \
                  Hz (~a in 2 s), and each frame's t is a 30th of a second \
                  after the last's (~a..~a)"
                 ticks (apply min steps) (apply max steps))
         (and (<= 58 ticks 62)
              (for-all (lambda (d) (< (abs (- d 33333333)) 500000))
                       steps))))

(check "(pacer-rate! 'screen) brings back a period a 500th short of the \
        screen's refresh"
       (let ([rate (pacer-rate)])
         (pacer-rate! 30)
         (let ([p30 (pacer-period)])
           (pacer-rate! 'screen)
           (let ([screen (pacer-period)] [p (core0-frame-ns)])
             (pacer-rate! rate)
             (and (= p30 33333333)
                  (= screen (- p (quotient p 500))))))))

;; Core1's loop on a fake clock, for ms, against core0 and a compositor
;; that queues frames, as FIFO does, with three images: it latches 4 ms
;; before each refresh (the first at phase), takes the oldest queued frame
;; whose GPU work is done (1 ms after its submit) and frees the image that
;; one replaces; with none, the refresh shows the last frame again. Core0
;; takes a boxed frame 50 us after it's free and the frame is there, starts
;; the acquire 150 us later, which waits for a free image, and submits 200
;; us after it returns; it wakes core1 as it takes a frame and as it gives
;; one back. A mover starts from stillness, asks a frame each tick and
;; draws at every one, working 1 to 3 ms, and once, at long-at ms, long-ms
;; more. => the refreshes that showed no new frame once frames had shown.
(define (pacer-test-fifo ms phase long-at long-ms)
  (let* ([real-ns now-ns] [real-ms now-ms] [real-events screen-events]
         [real-present rec-present!] [real-waiting gpu-frame-waiting?]
         [rate (pacer-rate)] [p (core0-frame-ns)] [e 4000000] [g 1000000]
         [t 0] [end (* ms 1000000)] [next-latch (+ phase (- p e))]
         [free 3] [queue '()] [front? #f] [shown? #f]
         [state 'idle] [at 0] [boxed? #f] [box-t 0] [woken? #f]
         [frozen 0] [n 0] [long-done? #f])
    ;; the next event of core0's or the compositor's: (time . kind)
    (define (next-event)
      (let* ([ev (cons next-latch 'latch)]
             [ev (if (and (eq? state 'idle) boxed?)
                     (let ([take (+ (max at box-t) 50000)])
                       (if (< take (car ev)) (cons take 'take) ev))
                     ev)])
        (if (and (eq? state 'try) (< at (car ev))) (cons at 'try) ev)))
    (define (submit! now)
      (pacer-frame-back! #t)
      (set! free (- free 1))
      (set! queue (append queue (list (+ now 200000 g))))
      (set! state 'idle)
      (set! at (+ now 200000))
      (set! woken? #t))
    ;; one event; => #t if it woke core1
    (define (event! ev)
      (let ([now (car ev)])
        (case (cdr ev)
          [(latch)
           (set! next-latch (+ next-latch p))
           (if (and (pair? queue) (<= (car queue) now))
               (begin
                 (set! queue (cdr queue))
                 (when front? (set! free (+ free 1)))
                 (set! front? #t)
                 (set! shown? #t)
                 (and (eq? state 'wait) (begin (submit! now) #t)))
               (begin
                 (when (and shown? (< now end)) (set! frozen (+ frozen 1)))
                 #f))]
          [(take)
           (set! boxed? #f)
           (set! state 'try)
           (set! at (+ now 150000))
           (set! woken? #t)
           #t]
          [(try)
           (if (> free 0)
               (begin (submit! now) #t)
               (begin (set! state 'wait) #f))])))
    (define (screen!)
      (let loop ()
        (let ([ev (next-event)])
          (when (<= (car ev) t) (event! ev) (loop)))))
    (set! now-ns (lambda () t))
    (set! now-ms (lambda () (quotient t 1000000)))
    (set! gpu-frame-waiting? (lambda () (screen!) boxed?))
    (set! screen-events
          (lambda (wait-ms)
            (screen!)
            (if woken?
                (set! woken? #f)
                (let ([until (+ t (* wait-ms 1000000))])
                  (let loop ()
                    (let ([ev (next-event)])
                      (if (> (car ev) until)
                          (set! t until)
                          (begin
                            (set! t (car ev))
                            (if (event! ev) (set! woken? #f) (loop))))))))
            '()))
    (set! rec-present!
          (lambda () (screen!) (set! boxed? #t) (set! box-t t) 0))
    (pacer-rate! 'screen)
    (let ([mover (open-window "Mover" 'size '(80 . 60)
                              'open window-frame-soon!
                              'frame (lambda (win at)
                                       (window-frame-soon! win)
                                       (set! n (+ n 1))
                                       (set! t (+ t 1000000
                                                  (* 500000 (mod (* n 7) 5))))
                                       (when (and (not long-done?)
                                                  (>= t (* long-at 1000000)))
                                         (set! long-done? #t)
                                         (set! t (+ t (* long-ms 1000000))))
                                       (invalidate! win))
                              'draw (lambda (win w h) (set! t (+ t 1000000))))])
      (focus-window! mover)
      (fluid-let ([*core0-forked* #t]
                  [*pacer-frame-ns* 0]
                  [*gpu-facts* (cons '(present-mode . vsync) *gpu-facts*)])
        (let loop ()
          (when (< t end) (schevana-step! (pacer-wait-ms) #t) (loop))))
      (close-window! mover))
    (set! now-ns real-ns)
    (set! now-ms real-ms)
    (set! screen-events real-events)
    (set! rec-present! real-present)
    (set! gpu-frame-waiting? real-waiting)
    (pacer-rate! rate)
    (steps 1)
    frozen))

(let ([frozen (map (lambda (phase) (pacer-test-fifo 6000 phase 3000 30))
                   '(0 4000000 8000000 12000000))])
  (check (format "an animation started from stillness fills the compositor's \
                  queue and keeps it full: no refresh shows an old frame, \
                  with a 30 ms turn at 3 s, at four phases of the screen \
                  (~a)" frozen)
         (for-all zero? frozen)))

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
              [screen-events (lambda (wait-ms)
                             (pacer-test-advance! pacer-test-wait)
                             '())]
              [rec-present!
               (let ([present rec-present!])
                 (lambda ()
                   (let ([shown? (present)])
                     (let ([t0 pacer-test-t])
                       (pacer-test-advance! 7)
                       (pacer-test-screen-waited! t0 pacer-test-t))
                     shown?)))])
    (thunk)))

(let ([win (open-window "Busy" 'size '(80 . 60)
                        'open window-frame-soon!
                        'frame (lambda (win at)
                                 (window-frame-soon! win)
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
            ;; the bar reads the peak when the clock's second turns: not
            ;; here, so that only this check asks for it
            (fluid-let ([refresh-status! void])
              (pacer-peak-ms!)
              (inject! '(key-down #\a ()))
              (steps 1)                   ; 3 ms and the key's 2
              (let* ([shown ((cdr (assq 'busy *status-segments*)))]
                     [after (begin (steps 1) (pacer-peak-ms!))])
                (and (not (assq 'frame *status-segments*))
                     (equal? shown "busiest tick 5.0 ms")
                     (= after 3.0)
                     (= (pacer-peak-ms!) 0.0)))))))
  (close-window! win))

;;; Ticks only when one is wanted: a redraw, a window's frame, or a look
;;; that input or a frame drawn asks for. On a fake clock, with no timers.
(for-each close-window! (windows))
(let* ([t (* 3000 1000000000)] [events '()]
       [ticks-in (lambda (n)   ; the ticks of n steps of core1's loop
                   (let ([before (pacer-ticks)])
                     (do ([i 0 (+ i 1)]) ((= i n))
                       (schevana-step! (pacer-wait-ms) #t))
                     (- (pacer-ticks) before)))])
  (fluid-let ([*timers* '()]
              [now-ns (lambda () t)]
              [now-ms (lambda () (quotient t 1000000))]
              [screen-events (lambda (wait-ms)
                             (set! t (+ t (* (max 1 wait-ms) 1000000)))
                             (let ([e events]) (set! events '()) e))])
    (ticks-in 20)
    (let* ([t0 t]
           [quiet (ticks-in 20)]
           [waited (- t t0)])
      (check "with nothing wanted the loop ticks not at all, waiting a period \
              a step"
             (and (= quiet 0)
                  (>= waited (* 19 (pacer-period))))))
    (let ([ticks (begin (request-frame!) (ticks-in 6))])
      (check "a frame asked for ticks once to draw it, then once more to look \
              at what it moved, and no more"
             (and (= ticks 2) (not (pacer-wanted?)))))
    (let* ([seen 0]
           [win (open-window "Asks" 'size '(80 . 60)
                             'frame (lambda (win at) (set! seen (+ seen 1))))])
      (ticks-in 6)
      (window-frame-soon! win)
      (let ([ticks (ticks-in 6)])
        (check "a window's frame asked for ticks once, and nothing after"
               (and (= seen 1) (= ticks 1))))
      (close-window! win)
      (ticks-in 6))
    (set! events '((key-down #\z ())))
    (let ([ticks (ticks-in 6)])
      (check "input asks for a look: it ticks, and then the ticks stop"
             (and (>= ticks 1) (= (ticks-in 6) 0))))))

;;; just in time: the compositor's latches, seen as acquires the screen held

(check "an acquire the screen held marks the compositor's latch; one that \
        found an image free marks none"
       (let* ([n 1000007] [at (present-at n)] [r *present-ring*] [t (now-ns)])
         (fluid-let ([*pacer-latch* #f])
           (fxvector-set! r at n)
           (fxvector-set! r (+ at 8) (- t 6000000))
           (fxvector-set! r (+ at 9) (- t 200000))
           (pacer-latch! n)
           (let ([held *pacer-latch*])
             (fxvector-set! r (+ at 8) (- t 100000))
             (fxvector-set! r (+ at 9) t)
             (pacer-latch! n)
             (and (= held (- t 200000)) (= *pacer-latch* held))))))

(check "with a latch seen lately and the reports placing them, a tick \
        begins its lead before the first latch a lead after the last tick \
        began; with an old one, or no frame back by vsync, the grid's"
       (let* ([r (core0-frame-ns)] [t (now-ns)] [latch (- t 1000000)])
         (fluid-let ([*pacer-latch* latch] [*pacer-lead* 4000000]
                     [*pacer-latch-phase* 0] [*pacer-aimed* 0]
                     [*pacer-began* (- t 3000000)] [*pacer-shown?* #t]
                     [*pacer-due* (+ t 5000000)] [*pacer-floor* 0])
           (let ([jit (pacer-start)])
             (set! *pacer-latch* (- t 2000000000))
             (let ([stale (pacer-start)])
               (set! *pacer-latch* latch)
               (set! *pacer-shown?* #f)
               (and (= jit (- (+ latch r) 4000000))
                    (= stale (- (+ *pacer-began* (quotient (pacer-period) 2))
                                2000000))
                    (= (pacer-start) (- *pacer-due* 2000000))))))))

(check "the margin starts at nothing, before the screen has taught it \
        anything"
       (and (not *pacer-margin*)
            (= (pacer-margin (core0-frame-ns)) 0)))

;; Frame n as the pacer reads it: its row in the frame ring, the newest,
;; its tick (as begun and as planned) and aimed latch; its report sent,
;; and shown at shown or not reported (#f). Then thunk; the row as it was
;; after.
(define (pacer-test-frame n tick aimed sent shown thunk)
  (let* ([row (* frame-ring-words
                 (modulo (- *frame-ring-n* 1) frame-ring-rows))]
         [was (map (lambda (k) (fxvector-ref *frame-ring* (+ row k)))
                   '(6 8 13 14))]
         [at (present-at n)] [ring *present-ring*])
    (for-each (lambda (k v) (fxvector-set! *frame-ring* (+ row k) v))
              '(6 8 13 14) (list n tick aimed tick))
    (fxvector-set! ring at n)
    (do ([w 1 (+ w 1)]) ((= w present-words)) (fxvector-set! ring (+ at w) 0))
    (fxvector-set! ring (+ at 2) sent)
    (when shown
      (fxvector-set! ring (+ at 1) 1)
      (fxvector-set! ring (+ at 3) shown))
    (let ([v (thunk)])
      (for-each (lambda (k v) (fxvector-set! *frame-ring* (+ row k) v))
                '(6 8 13 14) was)
      v)))

(check "one frame a latch: with the last tick's frame aimed at the next \
        latch, the tick after aims at the one after it, though a lead \
        after the last tick began would make the next"
       (let* ([r (core0-frame-ns)] [t (now-ns)] [latch (- t 1000000)])
         (fluid-let ([*pacer-latch* latch] [*pacer-lead* 4000000]
                     [*pacer-latch-phase* 0] [*pacer-aimed* (+ latch r)]
                     [*pacer-began* (- t 3000000)] [*pacer-shown?* #t]
                     [*pacer-floor* 0])
           (= (pacer-start) (- (+ latch (* 2 r)) 4000000)))))

(check "a tick that drew a frame leaves the screen pacing: till its frame \
        comes back, the next waits for its latch, not the grid's, which \
        would make two frames for one; a tick that drew none, the grid's. \
        A tick on a latch was planned its lead before it"
       (let* ([r (core0-frame-ns)] [t (now-ns)] [latch (- t 1000000)])
         (fluid-let ([*pacer-latch* latch] [*pacer-lead* 4000000]
                     [*pacer-latch-phase* 0] [*pacer-aimed* 0]
                     [*pacer-began* (- t 3000000)] [*pacer-shown?* #t]
                     [*pacer-due* (- t (quotient r 2))] [*pacer-floor* 0]
                     [*pacer-ticks* 0] [*pacer-tick-ms* 0]
                     [*pacer-frame-ns* 0] [*pacer-wanted?* #f]
                     [*pacer-drew?* #t] [wm-tick! void])
           (pacer-tick! t)
           (let ([paced? (and *pacer-shown?* (pacer-on-latch?)
                              (= *pacer-aimed* (+ latch r))
                              ;; its frame's planned start, the lead before
                              (= *pacer-planned* (- (+ latch r) 4000000))
                              (= (pacer-start)
                                 (- (+ latch (* 2 r)) 4000000)))])
             ;; a tick that drew nothing: the grid's again
             (pacer-tick! (+ t 1000000))
             (and paced? (not *pacer-shown?*))))))

(check "the next tick is due two periods from now at most: ticks that \
        come early, a period on each, never put it off"
       (let* ([r (pacer-period)] [t (now-ns)])
         (fluid-let ([*pacer-due* (+ t (* 600 r))] [*pacer-began* 0]
                     [*pacer-ticks* 0] [*pacer-tick-ms* 0]
                     [*pacer-frame-ns* 0] [*pacer-wanted?* #f]
                     [*pacer-drew?* #f] [wm-tick! void])
           (pacer-tick! t)
           (let ([far (= *pacer-due* (+ t (* 2 r)))])
             (for-each (lambda (k) (pacer-tick! (+ t (* k (quotient r 3)))))
                       (iota 300))
             (and far
                  (<= *pacer-due*
                      (+ t (* 299 (quotient r 3)) (* 2 r))))))))

;; A frame held back is drawn by no one: the window hidden, render-frame!
;; asks again and sends nothing.
(check "a tick whose frame was held back, the window hidden, gives the \
        screen nothing to pace by; one sent does"
       (let ([drew? (lambda (hidden?)
                      (fluid-let ([core0-hidden? (lambda () hidden?)]
                                  [*pacer-drew?* #f] [*pacer-due* 0]
                                  [*pacer-shown?* #f])
                        (invalidate!)
                        (schevana-step! 0 #t)
                        *pacer-drew?*))])
         (and (not (drew? #t)) (drew? #f))))

(check "a frame that came late moves the ones after it: the next tick aims \
        no earlier than the floor, a latch for each frame on its way"
       (let* ([r (core0-frame-ns)] [t (now-ns)] [latch (- t 1000000)])
         (fluid-let ([*pacer-latch* latch] [*pacer-lead* 4000000]
                     [*pacer-latch-phase* 0] [*pacer-aimed* (+ latch r)]
                     [*pacer-began* (- t 3000000)] [*pacer-shown?* #t]
                     [*pacer-floor* (+ latch (* 3 r))])
           (= (pacer-start) (- (+ latch (* 3 r)) 4000000)))))

(check "the lead is what frames took lately from when their tick was \
        meant to begin till core0 sent them, with the margin: it follows \
        a longer one at once, fades over half a second, and is two \
        refreshes at most"
       (let* ([r (core0-frame-ns)] [n 1000003] [t (now-ns)])
         (fluid-let ([*pacer-lead* 4000000] [*pacer-margin* 1000000])
           (let* ([need! (lambda (took)
                           (pacer-test-frame n t 0 (+ t took) #f
                                             (lambda () (pacer-need! n r))))]
                  [long (begin (need! 6000000) *pacer-lead*)]
                  [after (begin (need! 1000000) *pacer-lead*)]
                  [faded (begin
                           (do ([i 0 (+ i 1)])
                               ((>= (* i r)
                                    (pacer-seconds 'pacer-lead-fade)))
                             (need! 1000000))
                           *pacer-lead*)]
                  [most (begin (need! (* 3 r)) *pacer-lead*)])
             (and (= long 7000000)
                  (= after (- 7000000 (quotient (* 7000000 r)
                                                (pacer-seconds
                                                 'pacer-lead-fade))))
                  (< faded 3500000) (>= faded 2000000)
                  (= most (* 2 r)))))))

(check "where no report places the latches (X11, Windows), the \
        pacing is the grid's, as it was"
       (let ([t (now-ns)])
         (fluid-let ([*pacer-latch* (- t 1000000)] [*pacer-latch-phase* #f]
                     [*pacer-began* (- t 3000000)] [*pacer-shown?* #t])
           (= (pacer-start) (- (+ *pacer-began* (quotient (pacer-period) 2))
                               2000000)))))

(check "a frame that showed a refresh after the one its tick aimed for was \
        late: the margin grows past how long before its latch it was sent, \
        by an eighth of a refresh; in time, it stays, but where the \
        platform has it fade"
       (let* ([r (core0-frame-ns)] [n 1000011] [t (now-ns)])
         (fluid-let ([*pacer-margin* 1000000] [*pacer-depth* 0]
                     [*pacer-made* #f] [*pacer-late-seen* 0])
           (let* ([late (pacer-test-frame n (- t 9000000) t (- t 3000000)
                                          (+ t r 4000000)
                                          (lambda () (pacer-behind! n r)))]
                  [after-late *pacer-margin*]
                  [in-time (pacer-test-frame n (- t 9000000) t (- t 3000000)
                                             (+ t 4000000)
                                             (lambda () (pacer-behind! n r)))])
             (and late (not in-time)
                  (= after-late (+ 3000000 (quotient r 8)))
                  (if (> (pacer-seconds 'pacer-margin-fade) 0)
                      (< *pacer-margin* after-late)
                      (= *pacer-margin* after-late)))))))

(check "the margin fades as pacer-margin-fade has it, the platform's by \
        default (a minute on a Mac, else never): a frame in time takes a \
        refresh's share of the fade off it; at 0, nothing"
       (let* ([r (core0-frame-ns)] [n 1000013] [t (now-ns)]
              [in-time (lambda ()
                         (set! *pacer-margin* 3000000)
                         (pacer-test-frame n (- t 9000000) t (- t 5000000)
                                           (+ t 4000000)
                                           (lambda () (pacer-behind! n r)))
                         *pacer-margin*)])
         (fluid-let ([*pacer-margin* #f] [*pacer-depth* 0]
                     [*pacer-made* #f] [*pacer-late-seen* 0])
           (override! 'pacer-margin-fade 60)
           (let ([faded (in-time)])
             (override! 'pacer-margin-fade 0)
             (let ([kept (in-time)])
               (override! 'pacer-margin-fade)
               (and (= (theme-default 'pacer-margin-fade)
                       platform-pacer-margin-fade)
                    (= faded (- 3000000 (quotient (* 3000000 r)
                                                  60000000000)))
                    (= kept 3000000)))))))

(check "while ticks keep to the latches, a tick wanted, core1's wait for the \
        next is the screen's"
       (let ([t (now-ns)])
         (fluid-let ([*pacer-latch* (- t 1000000)] [*pacer-latch-phase* 0]
                     [*pacer-shown?* #t])
           (and (pacer-on-latch?)
                (begin (set! *pacer-latch-phase* #f)
                       (not (pacer-on-latch?)))))))

(check "frames late in a row, as a stall makes them, sent alike, raise \
        the margin once"
       (let* ([r (core0-frame-ns)] [n 1000013] [t (now-ns)])
         (fluid-let ([*pacer-margin* 0] [*pacer-depth* 0]
                     [*pacer-made* #f] [*pacer-late-seen* 0])
           (pacer-test-frame n (- t 9000000) t (- t 2000000) (+ t r 4000000)
                             (lambda ()
                               (do ([k 0 (+ k 1)]) ((= k 10))
                                 (pacer-behind! n r))))
           (= *pacer-margin* (+ 2000000 (quotient r 8))))))

(check "the reports read are the newest in, however many frames behind: \
        four back, as under Mutter's triple buffering at 120 Hz, they \
        still place the latches, and the frames on their way the floor"
       (let* ([r (core0-frame-ns)] [n 1000027] [ring *present-ring*]
              [t (now-ns)] [at (present-at n)] [old (present-at (- n 4))])
         (fluid-let ([*pacer-latch* #f] [*pacer-latch-phase* #f]
                     [*pacer-judged* 0] [*pacer-floor* 0]
                     [*frame-number* n])
           (do ([k 1 (+ k 1)]) ((> k 3))   ; sent, no report yet
             (let ([a (present-at (- n k))])
               (fxvector-set! ring a (- n k))
               (fxvector-set! ring (+ a 1) 0)))
           (fxvector-set! ring old (- n 4))
           (fxvector-set! ring (+ old 1) 1)
           (fxvector-set! ring (+ old 3) (- t (* 3 r) 1500000))
           (fxvector-set! ring at n)
           (fxvector-set! ring (+ at 8) (- t 6000000))
           (fxvector-set! ring (+ at 9) t)
           (pacer-latch! n)
           (and (= *pacer-latch* t)
                (= *pacer-latch-phase* 1500000)
                (= *pacer-judged* (- n 4))
                (= *pacer-floor* (+ t r))))))

(check "each report is judged once: a late frame raises the margin once, \
        however many frames come back before the next report"
       (let* ([r (core0-frame-ns)] [n 1000033] [m (- n 2)] [ring *present-ring*]
              [t (now-ns)])
         (fluid-let ([*pacer-margin* 0] [*pacer-judged* (- m 1)]
                     [*pacer-latch-phase* #f] [*pacer-depth* 0]
                     [*pacer-made* #f] [*pacer-late-seen* 0])
           (pacer-test-frame
            m (- t 9000000) t (- t 2000000) (+ t r 4000000)
            (lambda ()
              (for-each (lambda (k)        ; sent since, no report yet
                          (let ([a (present-at k)])
                            (fxvector-set! ring a k)
                            (do ([w 1 (+ w 1)]) ((= w present-words))
                              (fxvector-set! ring (+ a w) 0))))
                        (list (- n 1) n (+ n 1)))
              (pacer-latch! n)
              (set! *pacer-margin* 0)      ; were it judged again, it'd show
              (pacer-latch! (+ n 1))))
           (and (= *pacer-margin* 0) (= *pacer-judged* m)))))

(check "a margin past a refresh carries into the compositor's depth: a \
        frame for the latch before, sent a refresh earlier, is one for \
        this latch shown a refresh later; the margin is learned afresh, \
        from where it starts; three refreshes at most"
       (let* ([r (core0-frame-ns)] [n 1000041] [t (now-ns)]
              [late! (lambda (shown)
                       (pacer-test-frame n (- t (* 2 r)) t
                                         (- t (- r 1000000)) shown
                                         (lambda () (pacer-behind! n r))))])
         (fluid-let ([*pacer-margin* (- r 1000000)] [*pacer-depth* 0]
                     [*pacer-made* #f] [*pacer-late-seen* 0])
           (late! (+ t r 4000000))
           (let ([depth *pacer-depth*] [margin *pacer-margin*])
             (set! *pacer-depth* 3)
             (set! *pacer-margin* (- r 1000000))
             (set! *pacer-late-seen* 0)       ; a run of its own
             (late! (+ t (* 4 r) 4000000))
             (and (= depth 1) (not margin)
                  (= *pacer-depth* 3) (= *pacer-margin* r))))))

(check "a frame sent well before its latch, past the margin and a step, \
        and late all the same, the compositor missed the refresh: the \
        margin learns nothing"
       (let* ([r (core0-frame-ns)] [n 1000043] [t (now-ns)])
         (fluid-let ([*pacer-margin* 1000000] [*pacer-depth* 0]
                     [*pacer-made* #f] [*pacer-late-seen* 0])
           (let ([late (pacer-test-frame
                        n (- t (* 2 r)) t (- t (quotient r 2))
                        (+ t r 4000000)
                        (lambda () (pacer-behind! n r)))])
             (and late (= *pacer-margin* 1000000))))))

(check "a compositor that keeps a frame two refreshes past the first after \
        its latch (WindowServer's): its frames come late, the margin grows \
        past them till refreshes of it carry into the depth, and then \
        they're in time"
       (let* ([r (core0-frame-ns)] [n 1000045]
              ;; sent as the pacer sends them, each after the last was seen
              [frame (lambda ()
                       (let ([t (+ (now-ns) (* 2 r))])
                         (pacer-test-frame n (- t 9000000) t
                                           (- t (pacer-margin r))
                                           (+ t (* 2 r) 4000000)
                                           (lambda () (pacer-behind! n r)))))])
         (fluid-let ([*pacer-margin* 0] [*pacer-depth* 0] [*pacer-made* #f]
                     [*pacer-late-seen* 0])
           (let loop ([k 0] [lates 0])
             (if (< k 40)
                 (loop (+ k 1) (if (frame) (+ lates 1) lates))
                 (and (= *pacer-depth* 2) (< (pacer-margin r) r)
                      (<= 16 lates 18) (not (frame))))))))

(check "a frame sent as the pacer sends them that shows sooner than the \
        depth: the compositor keeps frames less long now, and the depth \
        falls to it; one sent a refresh early tells nothing"
       (let* ([r (core0-frame-ns)] [n 1000047] [t (now-ns)]
              [frame (lambda (sent)
                       (pacer-test-frame n (- t 9000000) t sent
                                         (+ t r 4000000)
                                         (lambda () (pacer-behind! n r))))])
         (fluid-let ([*pacer-margin* 1000000] [*pacer-depth* 2]
                     [*pacer-made* #f] [*pacer-late-seen* 0])
           (let* ([early (frame (- t r))]
                  [after-early *pacer-depth*]
                  [usual (frame (- t 500000))])
             (and (not early) (= after-early 2)
                  (not usual) (= *pacer-depth* 1))))))

(check "the floor counts the compositor's depth: the newest report, two \
        refreshes past the first after its latch, places the latches the \
        frames on their way take two refreshes sooner than it would at \
        none"
       (let* ([r (core0-frame-ns)] [n 1000049] [ring *present-ring*]
              [t (now-ns)] [at (present-at n)] [old (present-at (- n 4))])
         (fluid-let ([*pacer-latch* #f] [*pacer-latch-phase* #f]
                     [*pacer-judged* 0] [*pacer-floor* 0]
                     [*pacer-depth* 2] [*frame-number* n])
           (do ([k 1 (+ k 1)]) ((> k 3))   ; sent, no report yet
             (let ([a (present-at (- n k))])
               (fxvector-set! ring a (- n k))
               (fxvector-set! ring (+ a 1) 0)))
           (fxvector-set! ring old (- n 4))
           (fxvector-set! ring (+ old 1) 1)
           (fxvector-set! ring (+ old 3) (- t (* 3 r) 1500000))
           (fxvector-set! ring at n)
           (fxvector-set! ring (+ at 8) (- t 6000000))
           (fxvector-set! ring (+ at 9) t)
           (pacer-latch! n)
           (= *pacer-floor* (- t r)))))

(check "a late frame sent no closer to its latch than one that made its \
        latch lately, the compositor missed the refresh (WindowServer, now \
        and then): the margin learns nothing; one sent closer teaches it"
       (let* ([r (core0-frame-ns)] [n 1000051] [t (now-ns)]
              [frame (lambda (k sent shown)
                       (pacer-test-frame (+ n k) (- t 9000000) t sent shown
                                         (lambda ()
                                           (pacer-behind! (+ n k) r))))])
         (fluid-let ([*pacer-margin* 2500000] [*pacer-depth* 0]
                     [*pacer-made* #f] [*pacer-late-seen* 0]
                     [*pacer-late-run* 0] [*pacer-late-chain* 0])
           (frame 0 (- t 2000000) (+ t 4000000))
           (let* ([made *pacer-made*]
                  [slip (frame 1 (- t 2500000) (+ t r 4000000))]
                  [after-slip *pacer-margin*])
             (frame 2 (- t 3000000) (+ t 4000000))
             (let ([close (frame 40 (- t 1000000) (+ t r 4000000))])
               (and (= made 2000000) slip close
                    (<= after-slip 2500000)    ; it didn't grow
                    (= *pacer-margin* (+ 1000000 (quotient r 8)))))))))

(check "the closest send that made its latch is kept, a closer one at \
        once, and forgotten slowly: a 1024th of a refresh a frame judged"
       (let* ([r (core0-frame-ns)] [n 1000071] [t (now-ns)])
         (fluid-let ([*pacer-made* #f] [*pacer-late-seen* 0]
                     [*pacer-margin* 1000000] [*pacer-depth* 0])
           (pacer-made! 3000000)
           (pacer-made! 2000000)
           (pacer-made! 4000000)
           (let ([kept *pacer-made*])
             (pacer-test-frame n (- t 9000000) t (- t 5000000)
                               (+ t 4000000)
                               (lambda () (pacer-behind! n r)))
             (and (= kept 2000000)
                  (= *pacer-made*
                     (+ 2000000 (quotient (quotient r 8) 128))))))))

(check "the third late run in a chain, each within 128 frames of the \
        one before, teaches the margin though sent no closer than one that \
        made its latch: frames that keep missing a deadline that comes and \
        goes (WindowServer's, near it) want sending sooner; a compositor's \
        misses now and then seldom chain so"
       (let* ([r (core0-frame-ns)] [n 1000081] [t (now-ns)]
              [frame (lambda (k sent shown)
                       (pacer-test-frame (+ n k) (- t 9000000) t sent shown
                                         (lambda ()
                                           (pacer-behind! (+ n k) r))))]
              [late (lambda (k) (frame k (- t 2500000) (+ t r 4000000)))]
              [in-time (lambda (k) (frame k (- t 3000000) (+ t 4000000)))])
         (fluid-let ([*pacer-margin* 2500000] [*pacer-depth* 0]
                     [*pacer-made* #f] [*pacer-late-seen* 0]
                     [*pacer-late-run* 0] [*pacer-late-chain* 0])
           (frame 0 (- t 2000000) (+ t 4000000))
           (late 10) (in-time 11)
           (late 100) (in-time 101)
           (let ([two *pacer-margin*])
             (late 200)
             (and (<= two 2500000)          ; nor did two runs
                  (= *pacer-margin* (+ 2500000 (quotient r 8))))))))

(check "frames late behind a run's first, sent before the pacer saw it, \
        teach nothing: they waited behind it, for an image; one sent since, \
        and late still, teaches, as at a deadline missed for good"
       (let* ([r (core0-frame-ns)] [n 1000101] [t (now-ns)]
              [frame (lambda (k aim sent)
                       (pacer-test-frame (+ n k) (- aim 9000000) aim sent
                                         (+ aim r 4000000)
                                         (lambda ()
                                           (pacer-behind! (+ n k) r))))])
         (fluid-let ([*pacer-margin* 2500000] [*pacer-depth* 0]
                     [*pacer-made* 2000000] [*pacer-late-seen* 0]
                     [*pacer-late-run* 0] [*pacer-late-chain* 0])
           (frame 0 t (- t 2500000))        ; WindowServer's miss
           (let ([after-miss *pacer-margin*])
             (frame 1 t (- t 500000))       ; behind it, sent late
             (let ([behind *pacer-margin*] [aim (+ (now-ns) 10000000)])
               (frame 2 aim (- aim 1000000))
               (and (= after-miss 2500000) (= behind 2500000)
                    (= *pacer-margin* (+ 1000000 (quotient r 8)))))))))

(check "a frame sent after the pacer saw its run, though well before its \
        latch, and late still teaches: no one missed refresh makes that, \
        but a compositor that keeps frames longer (a Mac's, as the world \
        starts)"
       (let* ([r (core0-frame-ns)] [n 1000131] [t (now-ns)]
              [frame (lambda (k aim sent)
                       (pacer-test-frame (+ n k) (- aim 9000000) aim sent
                                         (+ aim r 4000000)
                                         (lambda ()
                                           (pacer-behind! (+ n k) r))))])
         (fluid-let ([*pacer-margin* 1000000] [*pacer-depth* 0]
                     [*pacer-made* 2000000] [*pacer-late-seen* 0]
                     [*pacer-late-run* 0] [*pacer-late-chain* 0])
           (frame 0 t (- t 2500000))        ; no closer: taught nothing
           (let ([first *pacer-margin*] [aim (+ (now-ns) (* 2 r))])
             (frame 1 aim (- aim 8000000))
             (and (= first 1000000)
                  (= *pacer-margin* (+ 8000000 (quotient r 8))))))))

(check "a wait for an image past the latch a frame aimed at, the \
        compositor holding a frame more, is the screen's time, not the \
        frame's: the lead learns only the rest; a wait up to that latch is \
        the frame's"
       (let* ([r (core0-frame-ns)] [n 1000141] [t (now-ns)] [at (present-at n)]
              [need (lambda (ended)
                      (pacer-test-frame
                       n t (+ t 5000000) (+ ended 1000000) #f
                       (lambda ()
                         (fxvector-set! *present-ring* (+ at 8)
                                        (+ t 3000000))
                         (fxvector-set! *present-ring* (+ at 9) ended)
                         (pacer-need! n r)
                         *pacer-lead*)))])
         (fluid-let ([*pacer-lead* 1000000] [*pacer-margin* 0])
           (let ([past (need (+ t 5000000 r))])
             (set! *pacer-lead* 1000000)
             (let ([up-to (need (+ t 5000000))])
               (and (= past 6000000) (= up-to 6000000)))))))

(check "the pacer's choices are settings, read live: with a step of a \
        quarter refresh, a late frame of its own raises the margin by a \
        quarter, and counts as its own"
       (let* ([r (core0-frame-ns)] [n 1000047] [t (now-ns)]
              [own (fxvector-ref *pacer-counts* 1)])
         (fluid-let ([*pacer-margin* 0] [*pacer-depth* 0] [*pacer-made* #f]
                     [*pacer-late-seen* 0])
           (override! 'pacer-margin-step 1/4)
           (pacer-test-frame n (- t 9000000) t (- t 1000000) (+ t r 4000000)
                             (lambda () (pacer-behind! n r)))
           (override! 'pacer-margin-step)
           (and (= *pacer-margin* (+ 1000000 (quotient r 4)))
                (= (fxvector-ref *pacer-counts* 1) (+ own 1))))))

(check "with no room past the margin for a frame of the pacer's own, a late \
        frame sent past it is the compositor's: counted so, nothing learned"
       (let* ([r (core0-frame-ns)] [n 1000049] [t (now-ns)]
              [theirs (fxvector-ref *pacer-counts* 2)])
         (fluid-let ([*pacer-margin* 1000000] [*pacer-depth* 0]
                     [*pacer-made* #f] [*pacer-late-seen* 0])
           (override! 'pacer-miss-own 0)
           (pacer-test-frame n (- t 9000000) t (- t 1500000) (+ t r 4000000)
                             (lambda () (pacer-behind! n r)))
           (override! 'pacer-miss-own)
           (and (= *pacer-margin* 1000000)
                (= (fxvector-ref *pacer-counts* 2) (+ theirs 1))))))

(check "relearning forgets the margin taught, the floor, the depth, the \
        closest send, the late runs and the lead"
       (let ([r (core0-frame-ns)])
         (fluid-let ([*pacer-margin* 5000000] [*pacer-floor* 123]
                     [*pacer-lead* 9000000] [*pacer-depth* 2]
                     [*pacer-made* 3000000] [*pacer-late-seen* 5]
                     [*pacer-late-chain* 2])
           (pacer-relearn!)
           (and (not *pacer-margin*) (= *pacer-floor* 0) (= *pacer-depth* 0)
                (not *pacer-made*) (= *pacer-late-seen* 0)
                (= *pacer-late-chain* 0)
                (= *pacer-lead* (quotient r 4))
                (= (pacer-margin r) 0)))))

(check "a trial holds the pacer's choices before the settings, which it \
        leaves as they are, and starts it learning anew"
       (let ([r (core0-frame-ns)] [overrides (theme-overrides)])
         (fluid-let ([*pacer-margin* 5000000])
           (pacer-trial! '((pacer-margin-start . 1/4)))
           (let ([held (list (pacer-margin r) (pacer-knob 'pacer-margin-step)
                             (theme 'pacer-margin-start))])
             (pacer-trial! '())
             (and (equal? held (list (quotient r 4) (theme 'pacer-margin-step)
                                     0))
                  (= (pacer-margin r) 0)
                  (equal? (theme-overrides) overrides))))))
