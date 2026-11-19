;;; tests/units/pacer.ss — the pacer (src/core1/pacer.ss): a turn a refresh
;;; while the work fits, each aimed at the refresh its frame shows at, on
;;; fake clocks and fake screens read as the pacer reads the real one; then
;;; the rule's clauses, each on rows laid out for it.

;;; ------------------------------------------------------------------
;;; fake clocks, rows and screens

;; The fake clock, ns; its ms; and a move of it, ms. Each run on it starts
;; at a base of its own, past the last run's: the profiler, which keeps the
;; ticks, sees no time go back.
(define pacer-test-t 0)
(define pacer-test-base 0)
(define (pacer-test-new-base!)
  (set! pacer-test-base (+ pacer-test-base 1000000000000))
  pacer-test-base)
(define (pacer-test-ns) pacer-test-t)
(define (pacer-test-ms) (quotient pacer-test-t 1000000))
(define (pacer-test-advance! ms)
  (set! pacer-test-t (+ pacer-test-t (* ms 1000000))))

;; Sixteen rows of frames given back unsent, frame 0's, that the pacer
;; passes over: the rows it reads from now on are only those added after.
;; The ring's count only grows, as the profiler, which keeps it with each
;; tick, has it.
(define (pacer-test-gap!)
  (do ([k 0 (+ k 1)]) ((= k 16))
    (let ([at (* frame-ring-words (modulo *frame-ring-n* frame-ring-rows))])
      (do ([w 0 (+ w 1)]) ((= w frame-ring-words))
        (fxvector-set! *frame-ring* (+ at w) 0))
      (fxvector-set! *frame-ring* (+ at 5) 2)
      (set! *frame-ring-n* (+ *frame-ring-n* 1)))))

;; thunk on the fake clock from ns on, with rows of its own (past a gap) and
;; the pacer as at a run's start; all as it was after.
(define (pacer-test-fresh ns thunk)
  (set! pacer-test-t ns)
  (pacer-test-gap!)
  (fluid-let ([now-ns pacer-test-ns] [now-ms pacer-test-ms]
              [*pacer-t* 0] [*pacer-hold* 0]
              [*pacer-floor* 0] [*pacer-proven* 0] [*pacer-probe* 0]
              [*pacer-probed* 0] [*pacer-soft?* #f] [*pacer-judged* 0]
              [*pacer-waited* 0] [*pacer-aim* 0] [*pacer-plan* 0]
              [*pacer-rate* 'screen])
    (pacer-forget!)
    (thunk)))

;; Core0's reports as the tests write them, by frame number: each word's
;; value, and when it's in (ns, on the fake clock).
(define pacer-test-reports (make-eqv-hashtable))

(define (pacer-test-report! n k v at)
  (let ([r (or (hashtable-ref pacer-test-reports n #f)
               (let ([r (cons (make-fxvector 12 0) (make-fxvector 12 0))])
                 (hashtable-set! pacer-test-reports n r)
                 r))])
    (fxvector-set! (car r) k v)
    (fxvector-set! (cdr r) k at)))

;; Word k of frame n's report as core0-frame-report says it: 0 till it's in.
(define (pacer-test-report n k)
  (let ([r (hashtable-ref pacer-test-reports n #f)])
    (and r (if (<= (fxvector-ref (cdr r) k) pacer-test-t)
               (fxvector-ref (car r) k)
               0))))

;; thunk with the pacer reading the tests' reports, and the screen's slot
;; empty.
(define (pacer-test-reported thunk)
  (hashtable-clear! pacer-test-reports)
  (fluid-let ([core0-frame-report pacer-test-report]
              [gpu-frame-waiting? (lambda () #f)])
    (thunk)))

;; A row as a frame's turn leaves it, the frame ring's next, with its
;; report, all in: its turn's begin and plan (0, begun at once), its aim,
;; its GPU work done (0, not yet), and what the screen said of it: 'out,
;; (shown S), 'dropped, or 'back (the window had no room); its refresh r.
;; Published 0.1 ms after its begin and taken 0.1 ms after that, with no
;; hold. => its frame's number
(define (pacer-test-row! b plan aim done what r)
  (let* ([i *frame-ring-n*] [n (+ i 1)] [p (+ b 100000)] [taken (+ p 100000)]
         [at (* frame-ring-words (modulo i frame-ring-rows))])
    (for-each (lambda (k v) (fxvector-set! *frame-ring* (+ at k) v))
              '(5 6 8 10 13 14)
              (list (if (eq? what 'back) 2 0) n b p aim plan))
    (set! *frame-ring-n* (+ i 1))
    (unless (eq? what 'back)
      (for-each (lambda (k v) (pacer-test-report! n k v 0))
                '(6 7 8 9)
                (list done taken taken taken))
      (cond [(pair? what)
             (pacer-test-report! n 1 1 0)
             (pacer-test-report! n 3 (cadr what) 0)
             (pacer-test-report! n 4 r 0)]
            [(eq? what 'dropped)
             (pacer-test-report! n 1 2 0)
             (pacer-test-report! n 4 r 0)]))
    n))

;; A frame of a flow: aimed at aim, begun on its plan half a refresh before
;; it, its GPU work done lead before it, and shown at aim, or at shown. Its
;; work is half a refresh less the lead and 0.1 ms.
(define (pacer-test-flow-row! aim lead r . shown)
  (let ([b (- aim (quotient r 2))])
    (pacer-test-row! b b aim (- aim lead)
                     (list 'shown (if (pair? shown) (car shown) aim)) r)))

;; The rows judged at now, nothing wanted.
(define (pacer-test-judge! now)
  (fluid-let ([*pacer-wanted?* #f] [*dirty* #f])
    (pacer-decide! now)))

;; A turn wanted from now: asked as the loop asks, then begun when the rule
;; says. => (begin . aim)
(define (pacer-test-turn! now)
  (fluid-let ([*dirty* #f])
    (set! *pacer-wanted?* #t)
    (let* ([a (pacer-decide! now)] [at (if (eq? a #t) now a)])
      (set! pacer-test-t at)
      (and (pacer-begin? at) (cons at *pacer-aim*)))))

;;; The fake screen, as core0 on a thread of its own has one. Core0 takes a
;;; frame published once its last acquire has returned; the acquire returns
;;; once the frame before has shown (FIFO, one image queued); its GPU work
;;; is done 1 ms after; the screen shows it at the first refresh 4 ms after
;;; that, one a refresh, and reports it there. Core0 wakes core1 at each
;;; frame's GPU-done, and core1's waits end up to 0.4 ms late. Its ways, an
;;; alist: (period . ns), the screen's refresh, by default the mode's;
;;; (phase . ns), where its refreshes fall; (reports . #f), a screen that
;;; says nothing, core0 sending each frame as it's published; (mailbox .
;;; #t), one that holds nothing, the newest frame done in time showing and
;;; the one it replaced dropped; (full . #t), a window with no room, each
;;; frame given back unsent; (away from . to), ms with no refresh;
;;; (descent . #t), the descent a run's start owes taken, where the loop's
;;; checks have none due.
(define pacer-test-ways '())
(define (pacer-test-way key default)
  (let ([w (assq key pacer-test-ways)]) (if w (cdr w) default)))

;; Frames so far; when core0's last acquire returned, and the newest frame
;; is taken; the refresh the last frame shows at; the GPU-done times to
;; come; frames given back unsent, not yet taken back; each frame shown,
;; (n . refresh), newest first; core1's wakes; when the flood's next key
;; comes (#f, none); waits with no end.
(define pacer-test-n 0)
(define pacer-test-returned 0)
(define pacer-test-taken 0)
(define pacer-test-last 0)
(define pacer-test-dones '())
(define pacer-test-backs '())
(define pacer-test-shows '())
(define pacer-test-wakes 0)
(define pacer-test-flood-at #f)
(define pacer-test-endless 0)

(define (pacer-test-period)
  (exact (round (pacer-test-way 'period (core0-frame-ns)))))

;; The first refresh at x or after, the screen there; the phase and the
;; time away from the run's base.
(define (pacer-test-refresh-from x)
  (let* ([p (pacer-test-period)]
         [ph (+ pacer-test-base (pacer-test-way 'phase 0))]
         [r (+ ph (* p (ceiling (/ (- x ph) p))))]
         [away (pacer-test-way 'away #f)])
    (if (and away (< (* (car away) 1000000) (- r pacer-test-base)
                     (* (cdr away) 1000000)))
        (pacer-test-refresh-from (+ r 1))
        r)))

;; A frame published (rec-present!): what core0 and the screen will do with
;; it, each word of its report in at its time. => its number
(define (pacer-test-publish!)
  (let* ([n (+ pacer-test-n 1)] [t pacer-test-t]
         [taken (max t pacer-test-returned)]
         [reports? (pacer-test-way 'reports #t)]
         [mailbox? (pacer-test-way 'mailbox #f)])
    (set! pacer-test-n n)
    (if (pacer-test-way 'full #f)
        (set! pacer-test-backs (cons n pacer-test-backs))
        (let* ([returned (if (or mailbox? (not reports?))
                             taken
                             (max taken pacer-test-last))]
               [done (+ returned 1000000)]
               [at (pacer-test-refresh-from (+ done 4000000))]
               [shown (and reports?
                           (if mailbox?
                               at
                               (max at (pacer-test-refresh-from
                                        (+ pacer-test-last 1)))))])
          (set! pacer-test-taken taken)
          (set! pacer-test-returned returned)
          (for-each (lambda (k v) (pacer-test-report! n k v v))
                    '(7 8 9 6)
                    (list taken taken returned done))
          (set! pacer-test-dones
            (append (filter (lambda (d) (> d t)) pacer-test-dones)
                    (list done)))
          (when shown
            (when (and mailbox? (pair? pacer-test-shows)
                       (= (cdar pacer-test-shows) shown))
              (pacer-test-report! (caar pacer-test-shows) 1 2 shown)
              (set! pacer-test-shows (cdr pacer-test-shows)))
            (pacer-test-report! n 1 1 shown)
            (pacer-test-report! n 3 shown shown)
            (pacer-test-report! n 4 (pacer-test-period) shown)
            (set! pacer-test-last shown)
            (set! pacer-test-shows (cons (cons n shown) pacer-test-shows)))))
    n))

;; Core1's wait for core0's events (screen-events): frames given back
;; unsent end it at once, taken back as render-frames-back! takes them;
;; else it lasts till wait ns pass, the next GPU-done, or the flood's key,
;; and ends a little late. A wait with no end is counted, and lasts a
;; second.
(define (pacer-test-events wait)
  (if (pair? pacer-test-backs)
      (begin
        (for-each (lambda (n) (frame-ring-set! n 5 2) (request-frame!))
                  pacer-test-backs)
        (set! pacer-test-backs '())
        '())
      (let* ([t pacer-test-t]
             [done (find (lambda (d) (> d t)) pacer-test-dones)]
             [ends (filter values (list (and wait (+ t wait)) done
                                        pacer-test-flood-at))]
             [to (if (null? ends)
                     (begin (set! pacer-test-endless (+ pacer-test-endless 1))
                            (+ t 1000000000))
                     (apply min ends))])
        (set! pacer-test-wakes (+ pacer-test-wakes 1))
        (set! pacer-test-t
          (max t (+ to (* 1000 (mod (* pacer-test-wakes 7919) 400)))))
        (if (and pacer-test-flood-at (<= pacer-test-flood-at pacer-test-t))
            (begin (set! pacer-test-flood-at (+ pacer-test-t 2000000))
                   '((key-down #\b ())))
            '()))))

;; thunk with core1's loop on the fake screen of ways, the fake clock from a
;; new base on, the pacer fresh and timers of its own; all as it was after.
(define (pacer-test-on-screen ways thunk)
  (set! pacer-test-ways ways)
  (set! pacer-test-n 0)
  (set! pacer-test-returned 0)
  (set! pacer-test-taken 0)
  (set! pacer-test-last 0)
  (set! pacer-test-dones '())
  (set! pacer-test-backs '())
  (set! pacer-test-shows '())
  (set! pacer-test-wakes 0)
  (set! pacer-test-flood-at #f)
  (set! pacer-test-endless 0)
  (pacer-test-fresh (pacer-test-new-base!)
    (lambda ()
      (unless (pacer-test-way 'descent #f)
        (set! *pacer-probed* pacer-test-t))
      (pacer-test-reported
       (lambda ()
         (fluid-let ([rec-present! pacer-test-publish!]
                     [screen-events pacer-test-events]
                     [gpu-frame-waiting?
                      (lambda () (> pacer-test-taken pacer-test-t))]
                     [*core0-forked* #t]
                     [*timers* '()])
           (thunk))))))
  (steps 1))

;; Core1's loop, paced, till the fake clock is at ns; at most 50 steps a ms
;; of it: past that the loop spins. => the steps
(define (pacer-test-loop-to ns)
  (let ([most (* 50 (max 1 (quotient (- ns pacer-test-t) 1000000)))])
    (let loop ([k 0])
      (if (and (< pacer-test-t ns) (< k most))
          (begin (schevana-step! (pacer-wait-ns) #t) (loop (+ k 1)))
          k))))

;; The gaps between times ts.
(define (pacer-test-gaps ts)
  (map - (cdr ts) (list-head ts (- (length ts) 1))))

;;; ------------------------------------------------------------------
;;; A turn a period while the work fits

;; Core1's loop for ms of the fake clock on a screen that says nothing:
;; in it, a window whose tick keeps books (3 ms) and never draws, one that
;; moves at every tick (2 ms of its tick, draw-ms of drawing), a busy
;; process (0.5 ms a slice) if opts has 'busy, a timer at 205 ms, a key at
;; 503 ms, and with 'flood a key every 2 ms besides, each ending the wait.
;; => an alist of what happened: the bookkeeper's ticks' times, the frames
;; drawn, the steps, the process's slices, when the timer ran, whether the
;; key came, the period, and the waits with no end.
(define (pacer-test-run draw-ms ms . opts)
  (let ([ticks '()] [frames 0] [slices 0] [fired #f] [keyed #f] [stepped 0]
        [period (core0-frame-ns)])
    (pacer-test-on-screen '((reports . #f))
      (lambda ()
        (let* ([keeper (open-window "Keeper" 'size '(80 . 60)
                                    'open window-frame-soon!
                                    'frame (lambda (win at)
                                             (window-frame-soon! win)
                                             (set! ticks
                                               (cons pacer-test-t ticks))
                                             (pacer-test-advance! 3)))]
               [mover (open-window "Mover" 'size '(80 . 60)
                                   'open window-frame-soon!
                                   'frame (lambda (win at)
                                            (window-frame-soon! win)
                                            (pacer-test-advance! 2)
                                            (invalidate! win))
                                   'key (lambda (win k mods) (set! keyed #t))
                                   'draw (lambda (win w h)
                                           (pacer-test-advance! draw-ms)
                                           (set! frames (+ frames 1))))]
               [p (and (memq 'busy opts)
                       (spawn "paced" (lambda ()
                                        (let loop ()
                                          (set! pacer-test-t
                                            (+ pacer-test-t 500000))
                                          (set! slices (+ slices 1))
                                          (engine-block)
                                          (loop)))))])
          (focus-window! mover)
          ;; 100 ms to settle (the first frame has no work to go by)
          (pacer-test-loop-to (+ pacer-test-base 100000000))
          (set! ticks '())
          (set! frames 0)
          (set! slices 0)
          (set! pacer-test-endless 0)
          (let ([start (now-ms)])
            (after 205 (lambda () (set! fired (- (now-ms) start)))))
          (when (memq 'flood opts) (set! pacer-test-flood-at pacer-test-t))
          (let ([end (+ pacer-test-t (* ms 1000000))]
                [key-at (+ pacer-test-t 503000000)])
            (let loop ()
              (when (and (< pacer-test-t end) (< stepped (* 50 ms)))
                (when (and key-at (>= pacer-test-t key-at))
                  (inject! '(key-down #\a ()))
                  (set! key-at #f))
                (schevana-step! (pacer-wait-ns) #t)
                (set! stepped (+ stepped 1))
                (loop))))
          (set! pacer-test-flood-at #f)
          (when p (kill! p))
          (close-window! keeper)
          (close-window! mover))))
    `((ticks . ,(reverse ticks)) (frames . ,frames) (steps . ,stepped)
      (slices . ,slices) (fired . ,fired) (keyed . ,keyed)
      (period . ,period) (endless . ,pacer-test-endless))))

(check "the pacer begins a turn a refresh apart while the work fits, with \
        bookkeeping that draws nothing, a busy process and input between: \
        a frame a turn, the process in the time left, a timer on its time, \
        and no wait with no end while turns are wanted"
       (let* ([r (pacer-test-run 5 1000 'busy)]
              [get (lambda (k) (cdr (assq k r)))]
              [ticks (get 'ticks)] [period (get 'period)]
              [gaps (pacer-test-gaps ticks)])
         (printf "  ~a ticks, ~a frames, ~a slices, gaps ~a..~a, timer at ~a\n"
                 (length ticks) (get 'frames) (get 'slices)
                 (apply min gaps) (apply max gaps) (get 'fired))
         ;; 1,000 ms of 16.7: 60 periods, 61 ticks at their ends
         (and (<= 60 (length ticks) 61)
              ;; a period apart on average, our own grid's 512th short of
              ;; it; each within the ms a busy process may run past its
              ;; begin, and a late wake
              (< (abs (- (quotient (- (car (last-pair ticks)) (car ticks))
                                   (length gaps))
                         period))
                 200000)
              (for-all (lambda (g) (< (abs (- g period)) 2000000)) gaps)
              (<= (abs (- (get 'frames) (length ticks))) 2)
              ;; the time left: far more than the 1 ms a tick they always
              ;; get
              (> (get 'slices) (* 4 (length ticks)))
              (get 'keyed)
              ;; at the step after its time: within a period
              (<= 205 (get 'fired) (+ 205 17))
              (= (get 'endless) 0))))

(check "with nothing else to do, the loop sleeps between turns: a step at \
        each frame's GPU-done and one to begin the next, and those of a \
        timer and a key"
       (let* ([r (pacer-test-run 5 1000)]
              [ticks (length (cdr (assq 'ticks r)))]
              [steps (cdr (assq 'steps r))])
         (printf "  ~a ticks, ~a steps\n" ticks steps)
         (and (<= 60 ticks 61) (<= steps (+ (* 2 ticks) 5)))))

(check "input that comes every 2 ms draws at the next turn: still a frame \
        a turn, a turn a period"
       (let* ([r (pacer-test-run 5 1000 'flood)]
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
                     (lambda () (set! r (pacer-test-run 5 1000 'flood))))]
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

(check "past a refresh of work, turns come as soon as the last frame's GPU \
        work is done, none closer than a period"
       (let* ([r (pacer-test-run 20 1000)]
              [ticks (cdr (assq 'ticks r))] [period (cdr (assq 'period r))]
              [gaps (pacer-test-gaps ticks)])
         (printf "  ~a ticks, gaps ~a..~a\n" (length ticks) (apply min gaps)
                 (apply max gaps))
         (and (< 20 (length ticks) 45)
              (for-all (lambda (g) (>= g period)) gaps))))

;;; ------------------------------------------------------------------
;;; Turns that follow a screen that reports

;; Core1's loop for ms of the fake clock against the fake screen of ways,
;; away (no refresh) from away-from to away-to ms, and fast ns faster than
;; the mode says. A mover asks a frame each tick, working 1 to 3 ms, and
;; draws at every one, or at every nth with (draw-every . n); with (long
;; at . ms), one tick at at ms works ms more; a timer counts every 10 ms;
;; with (rate . r), the pacer's rate for the run. => (refreshes frozen ts
;; frames-away timers-away shows leads ticks state): the refreshes that
;; showed a frame, those that showed none between two that did (but where
;; the screen was away and the first few), each 'frame's t, the 'frame
;; calls while the screen was away, the timers then, the refresh each
;; frame showed at, each 'frame's t less the clock then, the ticks, and
;; the pacer's hold, the hold a descent has proven and its floor at the
;; end. Times are ms from the run's base, but for the leads.
(define (pacer-test-lock ms away-from away-to fast . ways)
  (let* ([p (- (exact (round (* (or (let ([s (assq 'slow ways)])
                                      (and s (cdr s)))
                                    1)
                                (core0-frame-ns))))
               fast)]
         [draw-every (cond [(assq 'draw-every ways) => cdr] [else 1])]
         [long (cond [(assq 'long ways) => cdr] [else #f])]
         [ts '()] [leads '()] [away-frames 0] [away-timers 0] [n 0]
         [end (* ms 1000000)] [ticks (pacer-ticks)] [shows '()]
         [state #f])
    (define (away? at) (< (* away-from 1000000) at (* away-to 1000000)))
    (pacer-test-on-screen
     `((period . ,p) (away ,away-from . ,away-to) ,@ways)
     (lambda ()
       (let ([rate (assq 'rate ways)])
         (when rate
           (pacer-rate! (cdr rate))
           (set! *pacer-probed* pacer-test-t)))
       (let ([mover (open-window "Mover" 'size '(80 . 60)
                                 'open window-frame-soon!
                                 'frame (lambda (win at)
                                          (window-frame-soon! win)
                                          (set! n (+ n 1))
                                          (set! ts
                                            (cons (- at pacer-test-base) ts))
                                          (set! leads
                                            (cons (- at pacer-test-t) leads))
                                          (when (away? (- pacer-test-t
                                                          pacer-test-base))
                                            (set! away-frames
                                              (+ away-frames 1)))
                                          (set! pacer-test-t
                                            (+ pacer-test-t 1000000
                                               (* 500000 (mod (* n 7) 5))))
                                          (when (and long
                                                     (>= (- pacer-test-t
                                                            pacer-test-base)
                                                         (* (car long)
                                                            1000000)))
                                            (set! pacer-test-t
                                              (+ pacer-test-t
                                                 (* (cdr long) 1000000)))
                                            (set! long #f))
                                          (when (= 0 (mod n draw-every))
                                            (invalidate! win)))
                                 'draw (lambda (win w h)
                                         (pacer-test-advance! 1)))])
         (focus-window! mover)
         (let tick ()
           (after 10 (lambda ()
                       (when (away? (- pacer-test-t pacer-test-base))
                         (set! away-timers (+ away-timers 1)))
                       (when (< (- pacer-test-t pacer-test-base) end)
                         (tick)))))
         (pacer-test-loop-to (+ pacer-test-base end))
         (set! state (map pacer-state '(hold proven floor)))
         (close-window! mover)
         (set! shows (reverse (map (lambda (s) (- (cdr s) pacer-test-base))
                                   pacer-test-shows))))))
    (set! ticks (- (pacer-ticks) ticks))
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
          ticks state)))

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
                  screen there, finds a frame waiting (~a froze); each \
                  frame's t is whole refreshes after the last's, to 0.5 ms, \
                  though core1 wakes up to 0.4 ms late (~a..~a); and t is \
                  the refresh its frame shows at (~a..~a)"
                 (car r) (cadr r) (apply min steps) (apply max steps)
                 (apply min leads) (apply max leads))
         (and (> (car r) 100)
              (= (cadr r) 0)
              (for-all (lambda (d) (< (abs (- d (* p (round (/ d p)))))
                                      500000))
                       steps)
              ;; but the frames the screen's time away held up
              (for-all (lambda (d) (<= (abs d) p)) leads)
              (<= (length (filter (lambda (d) (> (abs d) 500000))
                                  (list-tail leads 3)))
                  2)))
  ;; the frame in the box, the one core0 holds in its acquire, and the one
  ;; the screen holds for after its time away
  (check (format "while the screen is away, turns run only till the frames \
                  out fill what it holds, and timers go on (~a frames, ~a \
                  timers)"
                 (cadddr r) (car (cddddr r)))
         (and (<= (cadddr r) 3) (> (car (cddddr r)) 20))))

(let ([r (pacer-test-lock 3000 0 0 100000)])
  (check (format "a screen a little faster than it says still gets a frame \
                  every refresh: the period is the reports' (~a refreshes, \
                  ~a froze)" (car r) (cadr r))
         (and (> (car r) 150) (= (cadr r) 0))))

(for-each
 (lambda (ways what)
   (let* ([r (apply pacer-test-lock 2000 0 0 0 ways)]
          [ticks (list-ref r 7)]
          [leads (list-tail (list-ref r 6) 5)]
          [p (core0-frame-ns)])
     (check (format "turns that send the screen no frame it holds keep to \
                     the refresh, and t to the clock: ~a, ~a turns in 2 s, t \
                     ~,1f to ~,1f ms ahead of the clock"
                    what ticks (/ (apply min leads) 1e6)
                    (/ (apply max leads) 1e6))
            (and (<= 118 ticks 124)
                 (for-all (lambda (d) (< 0 d (* 3 p))) leads)))))
 '(((draw-every . 30)) ((mailbox . #t)) ((full . #t)))
 '("a mover that draws every 30th turn" "frames presented by mailbox"
   "frames the screen has no room for"))

(let* ([r (pacer-test-lock 2000 0 0 0 '(slow . 3/2))]
       [p (* 3/2 (core0-frame-ns))]
       [steps (list-tail (pacer-test-gaps (caddr r)) 3)]
       [leads (list-tail (list-ref r 6) 5)])
  (check (format "with a screen slower than it says, each frame's t steps \
                  its whole refreshes (~a..~a ms) and keeps to the clock, \
                  ~,1f to ~,1f ms ahead"
                 (/ (apply min steps) 1e6) (/ (apply max steps) 1e6)
                 (/ (apply min leads) 1e6) (/ (apply max leads) 1e6))
         (and (for-all (lambda (d)
                         (< (abs (- d (* p (round (/ d p))))) 500000))
                       steps)
              (for-all (lambda (d) (< 0 d (* 3 p))) leads))))

(let* ([r (pacer-test-lock 2000 0 0 0 '(rate . 30))]
       [ticks (list-ref r 7)]
       [steps (list-tail (pacer-test-gaps (caddr r)) 3)])
  (check (format "(pacer-rate! 30) halves the frame turns, the screen at 60 \
                  Hz (~a in 2 s), and each frame's t is a 30th of a second \
                  after the last's, on a grid of its own (~a..~a)"
                 ticks (apply min steps) (apply max steps))
         (and (<= 58 ticks 62)
              (for-all (lambda (d) (< (abs (- d 33333333)) 500000))
                       steps))))

(check "(pacer-rate! 'screen) brings back the screen's period: with no \
        frame shown lately, the mode's"
       (let ([rate (pacer-rate)])
         (pacer-test-fresh 0
           (lambda ()
             (pacer-rate! 30)
             (let ([p30 (pacer-period)])
               (pacer-rate! 'screen)
               (let ([screen (pacer-period)])
                 (pacer-rate! rate)
                 (and (= p30 33333333) (= screen (core0-frame-ns)))))))))

;; From stillness, at four phases of the screen, with one tick of 30 ms
;; more at 3 s: the refreshes frozen once frames flow. That tick's frame
;; misses its refresh, and the next catches up.
(let ([frozen (map (lambda (phase)
                     (cadr (pacer-test-lock 6000 0 0 0
                                            (cons 'phase phase)
                                            '(long 3000 . 30))))
                   '(0 4000000 8000000 12000000))])
  (check (format "an animation started from stillness freezes no refresh, at \
                  four phases of the screen; a 30 ms tick at 3 s, two \
                  refreshes at most (~a)" frozen)
         (for-all (lambda (k) (<= k 2)) frozen)))

;; The descent a run's start owes, on a screen that shows a frame done 4 ms
;; before a refresh, whose frames' work varies by 2 ms: probes one at a
;; time bring the hold down from the first frame's lead, a probe's miss
;; ends it, and the hold lands. A probe done early, its work short, proves
;; a hold its frames with the most work can't keep: the landing may fall
;; under the cutoff, and a lone miss and a pair raise it again.
(let* ([r (pacer-test-lock 4000 0 0 0 '(descent . #t))]
       [state (list-ref r 8)] [shows (list-ref r 5)] [p (core0-frame-ns)]
       [frozen-after (let count ([s shows] [k 0])
                       (if (or (null? s) (null? (cdr s)))
                           k
                           (count (cdr s)
                                  (if (and (> (car s) 2000000000)
                                           (> (- (cadr s) (car s))
                                              (* 3/2 p)))
                                      (+ k 1)
                                      k))))])
  (check (format "a run's start owes a descent: one probe at a time brings \
                  the hold down from the first frame's lead to the screen's \
                  4 ms, and it ends; ~a refreshes froze, none in the last 2 \
                  s (hold, proven, floor ~a)"
                 (cadr r) state)
         (and (<= (cadr r) 3) (= frozen-after 0)
              (= (cadr state) 0)
              (<= 3000000 (car state) 5000000))))

;;; ------------------------------------------------------------------
;;; What a tick takes, but its waits: kept whether the profiler is on or not.

;; The screen held core1 from start to end: a wait, the profiler's
;; vsync-wait, and no work.
(define (pacer-test-screen-waited! start end)
  (profile-span-past! 'vsync-wait 'submit start end)
  (pacer-held! (- end start)))

;; thunk on a fake clock far from 0, the pacer fresh and no timer, with a
;; wait for events of pacer-test-wait ms, or as long as it's asked to, and
;; a frame that waits 7 ms for the screen, as the swapchain's may, its
;; report on the fake clock: taken and done as it's published.
(define pacer-test-wait 5)
(define (pacer-test-on-fake-clock thunk)
  (pacer-test-fresh (pacer-test-new-base!)
    (lambda ()
      (pacer-test-reported
       (lambda ()
         (fluid-let ([*timers* '()]
                     [screen-events
                      (lambda (wait)
                        (set! pacer-test-t
                          (+ pacer-test-t
                             (if (and wait (> wait 0))
                                 wait
                                 (* pacer-test-wait 1000000))))
                        '())]
                     [rec-present!
                      (let ([present rec-present!])
                        (lambda ()
                          (let ([n (present)] [t0 pacer-test-t])
                            (pacer-test-advance! 7)
                            (pacer-test-screen-waited! t0 pacer-test-t)
                            (for-each (lambda (k)
                                        (pacer-test-report! n k pacer-test-t 0))
                                      '(6 7 8 9))
                            n)))])
           (thunk)))))))

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
                ;; the wait the pacer asks: a tick, its 3 ms, and the 2
                (schevana-step! (pacer-wait-ns) 'paced)
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

;;; ------------------------------------------------------------------
;;; Ticks only when one is wanted: a redraw, a window's frame, or a look
;;; that input or a frame drawn asks for. On a fake clock, with no timers.

(for-each close-window! (windows))
(let* ([events '()] [endless 0]
       [ticks-in (lambda (n)   ; the ticks of n steps of core1's loop
                   (let ([before (pacer-ticks)])
                     (do ([i 0 (+ i 1)]) ((= i n))
                       (schevana-step! (pacer-wait-ns) #t))
                     (- (pacer-ticks) before)))])
  (pacer-test-fresh (pacer-test-new-base!)
    (lambda ()
      (fluid-let ([*timers* '()]
                  [screen-events (lambda (wait)
                                   (unless wait (set! endless (+ endless 1)))
                                   (set! pacer-test-t
                                     (+ pacer-test-t
                                        (max 1000000 (or wait 0))))
                                   (let ([e events]) (set! events '()) e))])
        (ticks-in 20)
        (set! endless 0)
        (let ([quiet (ticks-in 20)])
          (check "with nothing wanted the loop doesn't tick, and waits with \
                  no end, for input, mail or a timer to wake it"
                 (and (= quiet 0) (= endless 20))))
        (let ([ticks (begin (request-frame!) (ticks-in 6))])
          (check "a frame asked for ticks once to draw it, then once more to \
                  look at what it moved, and no more"
                 (and (= ticks 2) (not (pacer-wanted?)))))
        (let* ([seen 0]
               [win (open-window "Asks" 'size '(80 . 60)
                                 'frame (lambda (win at)
                                          (set! seen (+ seen 1))))])
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
                 (and (>= ticks 1) (= (ticks-in 6) 0))))))))

;;; ------------------------------------------------------------------
;;; What the loop's callers need of the rule

;; Rows of a flow at r = 10 ms from T on, nothing learned, no descent due.
(define pacer-test-r 10000000)
(define pacer-test-T 1000000000000)

(check "the two callers in the loop's order: asked before the sleep, the \
        rule says how long; asked once that has passed, the wait says 0, \
        and the begin is made with the plan slept to"
       (let ([r pacer-test-r] [T pacer-test-T])
         (pacer-test-fresh T
           (lambda ()
             (pacer-test-reported
              (lambda ()
                (fluid-let ([*timers* '()] [procs-ready? (lambda () #f)])
                  (set! *pacer-probed* T)
                  (do ([i 0 (+ i 1)]) ((= i 8))
                    (pacer-test-flow-row! (+ T (* i r)) 3000000 r))
                  (set! pacer-test-t (+ T (* 7 r)))
                  (set! *pacer-wanted?* #t)
                  (let* ([wait (pacer-wait-ns)] [planned *pacer-waited*])
                    (set! pacer-test-t planned)
                    (let* ([again (pacer-wait-ns)]
                           [kept *pacer-waited*]
                           [begun? (pacer-begin? (now-ns))])
                      (and (> wait 0) (= planned (+ T (* 7 r) wait))
                           (= again 0) (= kept planned) begun?
                           (= (pacer-state 'plan) planned)
                           (= (pacer-state 't) (+ T (* 8 r)))
                           (= (pacer-state 'waited) 0)))))))))))

(check "after a frame whose work was over two refreshes, the turn after it \
        begins at once, and of thirty turns that draw nothing all but the \
        first two come a refresh apart, t within three refreshes of the \
        clock"
       (let ([r pacer-test-r] [T pacer-test-T] [begins '()] [ahead '()])
         (pacer-test-fresh T
           (lambda ()
             (pacer-test-reported
              (lambda ()
                (fluid-let ([*timers* '()] [procs-ready? (lambda () #f)])
                  (set! *pacer-probed* T)
                  (do ([i 0 (+ i 1)]) ((= i 7))
                    (pacer-test-flow-row! (+ T (* i r)) 3000000 r))
                  ;; its work 22.9 ms: begun 26 ms before its aim, done 3
                  ;; ms before it
                  (let ([aim (+ T (* 7 r))])
                    (pacer-test-row! (- aim 26000000) (- aim 26000000) aim
                                     (- aim 3000000) (list 'shown aim) r))
                  (set! pacer-test-t (+ T (* 7 r)))
                  (let loop ([k 0])
                    (when (and (< (length begins) 31) (< k 200))
                      (set! *pacer-wanted?* #t)
                      (let ([wait (pacer-wait-ns)])
                        (set! pacer-test-t (+ pacer-test-t wait))
                        (when (pacer-begin? pacer-test-t)
                          (set! begins (cons pacer-test-t begins))
                          (set! ahead
                            (cons (- (pacer-state 't) pacer-test-t) ahead))))
                      (loop (+ k 1)))))))))
         (let ([gaps (pacer-test-gaps (reverse begins))])
           (printf "  ~a turns, gaps ~a..~a, t ahead ~a..~a\n"
                   (length begins) (apply min gaps) (apply max gaps)
                   (apply min ahead) (apply max ahead))
           (and (= (length begins) 31)
                (= (car (reverse begins)) (+ T (* 7 r)))
                (for-all (lambda (g) (<= (abs (- g r)) 500000))
                         (list-tail gaps 2))
                (for-all (lambda (a) (<= 0 a (* 3 r))) ahead)))))

(let ([woke #f] [fired '()] [start #f])
  (pacer-test-on-screen '((reports . #f))
    (lambda ()
      (for-each close-window! (windows))
      (pacer-test-loop-to (+ pacer-test-base 50000000))
      (set! start pacer-test-t)
      (spawn "sleeper" (lambda () (sleep-ms 50) (set! woke pacer-test-t)))
      (after 1/2 (lambda () (set! fired (cons 'half fired))))
      (after 50/3 (lambda () (set! fired (cons 'third fired))))
      (let loop ([k 0])
        (when (and (not woke) (< k 200))
          (schevana-step! (pacer-wait-ns) #t)
          (loop (+ k 1))))
))
  (check (format "a process asleep 50 ms in a still world runs again within \
                  60 ms (~a ms)"
                 (and woke (/ (- woke start) 1e6)))
         (and woke (<= (- woke start) 60000000)))
  (check "(after 1/2 thunk) and (after 50/3 thunk) fire, and the loop goes \
          on"
         (and (memq 'half fired) (memq 'third fired) woke #t)))

;;; ------------------------------------------------------------------
;;; The rule's clauses, each on rows laid out for it at r = 10 ms

;; thunk on rows of its own at T, its reports the tests', no descent due.
(define (pacer-test-rows thunk)
  (pacer-test-fresh pacer-test-T
    (lambda ()
      (pacer-test-reported
       (lambda ()
         (set! *pacer-probed* pacer-test-T)
         (thunk))))))

(check "the first frame shown gives the hold; one in time with less lead \
        lowers it, never under the floor; one with more lead, or late, \
        leaves it"
       (let ([r pacer-test-r] [T pacer-test-T] [ms 1000000])
         (pacer-test-rows
          (lambda ()
            (define (row! k lead . shown)
              (apply pacer-test-flow-row! (+ T (* k r)) lead r shown)
              (pacer-test-judge! (+ T (* (+ k 1) r)))
              (pacer-state 'hold))
            (let* ([first (row! 0 (* 6 ms))]
                   [closer (row! 1 (* 5 ms))]
                   [more (row! 2 (* 7 ms))]
                   [late (row! 3 (* 4 ms) (+ T (* 4 r)))]
                   [floored (begin (set! *pacer-floor* (* 9/2 ms))
                                   (row! 5 (* 3 ms)))])
              (equal? (list first closer more late floored)
                      (list (* 6 ms) (* 5 ms) (* 5 ms) (* 5 ms)
                            (* 9/2 ms))))))))

(check "a clean miss alone is the compositor's; a pair raises the hold a \
        look over the lead that failed; a third before a frame in time, a \
        refresh over, which owes a descent"
       (let ([r pacer-test-r] [T pacer-test-T] [ms 1000000]
             [L core0-look-ns])
         (pacer-test-rows
          (lambda ()
            ;; each late a refresh, the frame before it shown before its
            ;; aim, begun on plan and done at least the hold before it
            (define (miss! k x)
              (pacer-test-flow-row! (+ T (* k r)) x r (+ T (* (+ k 1) r)))
              (pacer-test-judge! (+ T (* (+ k 2) r)))
              (list (pacer-state 'hold) (pacer-state 'soft?)))
            (pacer-test-flow-row! T (* 6 ms) r)
            (pacer-test-judge! (+ T r))
            (let* ([alone (miss! 1 (* 7 ms))]
                   [pair (miss! 3 (* 8 ms))]
                   [third (miss! 5 (* 9 ms))]
                   [owed (- (+ T (* 7 r)) (pacer-state 'probed))])
              (and (equal? alone (list (* 6 ms) #f))
                   (equal? pair (list (+ (* 8 ms) L) #t))
                   (equal? third (list (+ (* 9 ms) r) #f))
                   (= owed pacer-descent-ns)))))))

(check "a descent begins after eight frames in time and on plan: one probe \
        at a time, a look under the hold proven, the frames around it at \
        the hold proven; a probe in time proves a look lower, and the next \
        frame probes"
       (let ([r pacer-test-r] [T pacer-test-T] [ms 1000000]
             [L core0-look-ns])
         (pacer-test-rows
          (lambda ()
            (set! *pacer-probed* 0)
            (do ([k 0 (+ k 1)]) ((= k 8))
              (pacer-test-flow-row! (+ T (* k r)) (* 3 ms) r))
            (pacer-test-judge! (+ T (* 8 r)))
            (let* ([begun (list (pacer-state 'proven) (pacer-state 'probe)
                                (pacer-state 'floor))]
                   ;; the work 1.9 ms, the slack two looks
                   [probe (pacer-test-turn! (+ T (* 7 r)))]
                   [probe-at (pacer-state 'probe)]
                   [next (pacer-test-turn! pacer-test-t)])
              (for-each (lambda (turn)
                          (pacer-test-row! (car turn) (car turn) (cdr turn)
                                           (- (cdr turn) (* 3 ms))
                                           (list 'shown (cdr turn)) r))
                        (list probe next))
              (pacer-test-judge! (+ T (* 10 r)))
              (let* ([proved (list (pacer-state 'proven) (pacer-state 'probe)
                                   (pacer-state 'hold))]
                     [again (pacer-test-turn! (+ T (* 9 r) ms))])
                (printf "  ~a ~a ~a ~a ~a\n" begun probe next proved again)
                (and (equal? begun (list (* 3 ms) 0 0))
                     (= (cdr probe) (+ T (* 8 r)) probe-at)
                     (= (- (cdr probe) (car probe))
                        (+ (- (* 3 ms) L) (* 19/10 ms) (* 2 L)))
                     (= (cdr next) (+ T (* 9 r)))
                     (= (- (cdr next) (car next))
                        (+ (* 3 ms) (* 19/10 ms) (* 2 L)))
                     (equal? proved (list (- (* 3 ms) L) 0 (* 3 ms)))
                     (= (pacer-state 'probe) (cdr again)))))))))

(check "a probe's clean miss ends the descent: the hold two looks over the \
        lead that failed, never over where it began, and the floor a look \
        over it"
       (let ([r pacer-test-r] [T pacer-test-T] [ms 1000000]
             [L core0-look-ns])
         (define (probe-miss! hold proven x)
           (pacer-test-rows
            (lambda ()
              (pacer-test-flow-row! T (* 9 ms) r)
              (pacer-test-judge! (+ T r))
              (set! *pacer-hold* hold)
              (set! *pacer-proven* proven)
              (set! *pacer-probe* (+ T r))
              (pacer-test-flow-row! (+ T r) x r (+ T (* 2 r)))
              (pacer-test-judge! (+ T (* 3 r)))
              (list (pacer-state 'hold) (pacer-state 'floor)
                    (pacer-state 'proven) (pacer-state 'probe)))))
         (let ([under (probe-miss! (* 9 ms) (* 7 ms) (* 7 ms))]
               [over (probe-miss! (* 6 ms) (* 6 ms) (* 6 ms))])
           (and (equal? under (list (+ (* 7 ms) (* 2 L)) (+ (* 7 ms) L) 0 0))
                (equal? over (list (* 6 ms) (+ (* 6 ms) L) 0 0))))))

(check "while a descent is in course, a clean miss of a frame not the \
        probe is the compositor's alone, and a pair raises the hold and \
        ends the descent; a descent down to a look ends there"
       (let ([r pacer-test-r] [T pacer-test-T] [ms 1000000]
             [L core0-look-ns])
         (pacer-test-rows
          (lambda ()
            (pacer-test-flow-row! T (* 9 ms) r)
            (pacer-test-judge! (+ T r))
            (set! *pacer-proven* (* 7 ms))
            (set! *pacer-probe* (+ T (* 20 r)))
            (pacer-test-flow-row! (+ T r) (* 8 ms) r (+ T (* 2 r)))
            (pacer-test-judge! (+ T (* 3 r)))
            (let ([alone (list (pacer-state 'hold) (pacer-state 'proven))])
              (pacer-test-flow-row! (+ T (* 3 r)) (* 15/2 ms) r (+ T (* 4 r)))
              (pacer-test-judge! (+ T (* 5 r)))
              (let ([pair (list (pacer-state 'hold) (pacer-state 'proven)
                                (pacer-state 'probe))])
                ;; down to a look
                (set! *pacer-proven* (* 2 L))
                (set! *pacer-probe* (+ T (* 5 r)))
                (pacer-test-flow-row! (+ T (* 5 r)) (* 6 ms) r)
                (pacer-test-judge! (+ T (* 6 r)))
                (and (equal? alone (list (* 9 ms) (* 7 ms)))
                     (equal? pair (list (+ (* 15/2 ms) L) 0 0))
                     (= (pacer-state 'hold) L)
                     (= (pacer-state 'proven) 0))))))))

(check "a frame shown at another rate, its refresh off the one before by \
        over a 64th, starts all that was learned over: the hold its own \
        lead, no floor, no descent, one owed"
       (let ([r pacer-test-r] [T pacer-test-T] [ms 1000000])
         (pacer-test-rows
          (lambda ()
            (pacer-test-flow-row! T (* 6 ms) r)
            (pacer-test-judge! (+ T r))
            (set! *pacer-floor* (* 3 ms))
            (set! *pacer-proven* (* 5 ms))
            (set! *pacer-soft?* #t)
            (let ([r2 (+ r (quotient r 32))])
              (pacer-test-flow-row! (+ T r2) (* 4 ms) r2)
              (pacer-test-judge! (+ T r2 r2))
              (and (= (pacer-state 'hold) (* 4 ms))
                   (= (pacer-state 'floor) 0)
                   (= (pacer-state 'proven) 0)
                   (not (pacer-state 'soft?))
                   (= (pacer-state 'probed)
                      (- (+ T r2 r2) pacer-descent-ns))))))))

(check "with no reports, an acquire the screen held leaves a refresh out of \
        our own grid only with three frames in flight, not two"
       (let ([T pacer-test-T] [L core0-look-ns])
         (define (aim-with in-flight)
           (pacer-test-rows
            (lambda ()
              (fluid-let ([*gpu-frames-in-flight* in-flight])
                (let ([n (pacer-test-row! (- T 1000000) (- T 1000000) T
                                          (+ T (* 2 L) 1000000) 'out
                                          pacer-test-r)])
                  (pacer-test-report! n 9 (+ T (* 2 L)) 0)
                  (set! *pacer-t* T)
                  (cdr (pacer-test-turn! (- T 1000000))))))))
         (let ([s (let ([p (core0-frame-ns)]) (- p (quotient p 512)))])
           (and (= (aim-with 3) (+ T s s)) (= (aim-with 2) (+ T s))))))

(check "a turn waits while the newest frame's GPU work isn't seen done, \
        eight refreshes at most; then, its frame still in the slot, a \
        refresh at a time; else it begins"
       (let ([T pacer-test-T])
         (pacer-test-rows
          (lambda ()
            (pacer-test-row! T T T 0 'out pacer-test-r)
            (set! *pacer-wanted?* #t)
            (let* ([p (pacer-period)]
                   [gate (pacer-decide! (+ T 1000000))]
                   [slot (fluid-let ([gpu-frame-waiting? (lambda () #t)])
                           (pacer-decide! (+ T (* 8 p))))]
                   [begin (pacer-decide! (+ T (* 8 p)))])
              (and (= gate (+ T (* 8 p)))
                   (= slot (+ T (* 9 p)))
                   (eq? begin #t)))))))

(check "a report stamped two seconds ahead of the clock gives no hold and is \
        not the grid: the wait it leaves has an end within nine refreshes"
       (let ([r pacer-test-r] [T pacer-test-T])
         (pacer-test-rows
          (lambda ()
            (pacer-test-flow-row! T 6000000 r (+ T 2000000000))
            (set! *pacer-wanted?* #t)
            (let ([a (pacer-decide! (+ T 1000000))])
              (and (= (pacer-state 'hold) 0)
                   (or (eq? a #t)
                       (<= a (+ T (* 9 (pacer-period)))))))))))
