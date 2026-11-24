;;; tests/units/pacer2.ss — the second pacer ((schevana core pacer2)): a
;;; turn a refresh while the work fits, each aimed at the refresh its frame
;;; shows at, on fake clocks and fake screens that the pacer reads as it
;;; reads the real one; then the rule's clauses, each on rows laid out for
;;; it. The loop asks the second pacer here only where a check says so
;;; (pacer2?); a test's step (steps) asks the first, which
;;; tests/units/pacer.ss checks, with the books the two share.

;;; ------------------------------------------------------------------
;;; fake clocks, rows and screens

;; The fake clock, in ns; its ms; and a move of it by ms. Each run on it
;; starts at a base of its own, past the last run's, so that the profiler,
;; which keeps the ticks, sees no time go back.
(define pacer2-test-t 0)
(define pacer2-test-base 0)
(define (pacer2-test-new-base!)
  (set! pacer2-test-base (+ pacer2-test-base 1000000000000))
  pacer2-test-base)
(define (pacer2-test-ns) pacer2-test-t)
(define (pacer2-test-ms) (quotient pacer2-test-t 1000000))
(define (pacer2-test-advance! ms)
  (set! pacer2-test-t (+ pacer2-test-t (* ms 1000000))))

;; Adds sixteen rows of frames given back unsent, frame 0's, which the
;; pacer passes over, so that the rows it reads from now on are only those
;; added after. The ring's count only grows, as the profiler, which keeps
;; it with each tick, needs it to.
(define (pacer2-test-gap!)
  (do ([k 0 (+ k 1)]) ((= k 16))
    (let ([at (* frame-ring-words (modulo *frame-ring-n* frame-ring-rows))])
      (do ([w 0 (+ w 1)]) ((= w frame-ring-words))
        (fxvector-set! *frame-ring* (+ at w) 0))
      (fxvector-set! *frame-ring* (+ at 5) 2)
      (set! *frame-ring-n* (+ *frame-ring-n* 1)))))

;; Runs thunk on the fake clock from ns on, with rows of its own (past a
;; gap) and the pacer as at a run's start; all is as it was afterward.
(define (pacer2-test-fresh ns thunk)
  (set! pacer2-test-t ns)
  (pacer2-test-gap!)
  (fluid-let ([now-ns pacer2-test-ns] [now-ms pacer2-test-ms]
              [*pacer2-t* 0] [*pacer2-hold* 0]
              [*pacer2-missed* 0] [*pacer2-proven* 0] [*pacer2-probe* 0]
              [*pacer2-probe-miss* 0] [*pacer2-probed* 0] [*pacer2-soft?* #f]
              [*pacer2-judged* 0]
              [*pacer2-waited* 0] [*pacer2-aim* 0] [*pacer2-plan* 0]
              [*pacer-rate* 'screen] [*pacer-frame-ns* 0])
    (pacer2-forget!)
    (thunk)))

;; Core0's reports as the tests write them, by frame number: each word's
;; value, and when it is in (ns, on the fake clock).
(define pacer2-test-reports (make-eqv-hashtable))

(define (pacer2-test-report! n k v at)
  (let ([r (or (hashtable-ref pacer2-test-reports n #f)
               (let ([r (cons (make-fxvector 12 0) (make-fxvector 12 0))])
                 (hashtable-set! pacer2-test-reports n r)
                 r))])
    (fxvector-set! (car r) k v)
    (fxvector-set! (cdr r) k at)))

;; Returns word k of frame n's report as core0-frame-report gives it: 0
;; until it is in.
(define (pacer2-test-report n k)
  (let ([r (hashtable-ref pacer2-test-reports n #f)])
    (and r (if (<= (fxvector-ref (cdr r) k) pacer2-test-t)
               (fxvector-ref (car r) k)
               0))))

;; Runs thunk with the pacer reading the tests' reports, and with the
;; screen's slot empty.
(define (pacer2-test-reported thunk)
  (hashtable-clear! pacer2-test-reports)
  (fluid-let ([core0-frame-report pacer2-test-report]
              [gpu-frame-waiting? (lambda () #f)])
    (thunk)))

;; Adds a row as a frame's turn leaves it, the frame ring's next, with its
;; report all in: its turn's begin and plan (0 for begun at once), its aim,
;; when its GPU work was done (0 for not yet), and what the screen said of
;; it: 'out, (shown S), 'dropped, or 'back (the window had no room), with
;; its refresh r. It is published 0.1 ms after its begin and taken 0.1 ms
;; after that, with no hold. Returns its frame's number.
(define (pacer2-test-row! b plan aim done what r)
  (let* ([i *frame-ring-n*] [n (+ i 1)] [p (+ b 100000)] [taken (+ p 100000)]
         [at (* frame-ring-words (modulo i frame-ring-rows))])
    (for-each (lambda (k v) (fxvector-set! *frame-ring* (+ at k) v))
              '(5 6 8 10 13 14 15)
              (list (if (eq? what 'back) 2 0) n b p aim plan 2))
    (set! *frame-ring-n* (+ i 1))
    (unless (eq? what 'back)
      (for-each (lambda (k v) (pacer2-test-report! n k v 0))
                '(6 7 8 9)
                (list done taken taken taken))
      (cond [(pair? what)
             (pacer2-test-report! n 1 1 0)
             (pacer2-test-report! n 3 (cadr what) 0)
             (pacer2-test-report! n 4 r 0)]
            [(eq? what 'dropped)
             (pacer2-test-report! n 1 2 0)
             (pacer2-test-report! n 4 r 0)]))
    n))

;; Adds a frame of a flow: aimed at aim, begun on its plan half a refresh
;; before it, its GPU work done lead before it, and shown at aim, or at
;; shown. Its work is half a refresh, less the lead and 0.1 ms.
(define (pacer2-test-flow-row! aim lead r . shown)
  (let ([b (- aim (quotient r 2))])
    (pacer2-test-row! b b aim (- aim lead)
                     (list 'shown (if (pair? shown) (car shown) aim)) r)))

;; Judges the rows at now, with nothing wanted.
(define (pacer2-test-judge! now)
  (fluid-let ([*pacer-wanted?* #f] [*dirty* #f])
    (pacer2-decide! now)))

;; Asks for a turn from now, as the loop asks, and begins it when the rule
;; says. Returns (begin . aim).
(define (pacer2-test-turn! now)
  (fluid-let ([*dirty* #f])
    (set! *pacer-wanted?* #t)
    (let* ([a (pacer2-decide! now)] [at (if (eq? a #t) now a)])
      (set! pacer2-test-t at)
      (and (pacer2-begin? at) (cons at *pacer2-aim*)))))

;;; The fake screen, as core0 on a thread of its own has one. Core0 takes a
;;; frame published once its last acquire has returned; the acquire returns
;;; once the frame before has shown (FIFO, with one image queued); the
;;; frame's GPU work is done 1 ms later; and the screen shows it at the
;;; first refresh 4 ms after that, one frame a refresh, and reports it
;;; there. Core0 wakes core1 at each frame's GPU-done, and core1's waits end
;;; up to 0.4 ms late. The screen's ways are an alist: (period . ns), the
;;; screen's refresh, by default the mode's; (phase . ns), where its
;;; refreshes fall; (reports . #f), a screen that says nothing, with core0
;;; sending each frame as it is published; (mailbox . #t), one that holds
;;; nothing, the newest frame done in time showing and the one it replaced
;;; dropped; (deep . #t), two images queued, as GNOME's are with three
;;; frames in flight, the acquire returning once the frame two before has
;;; shown; (full . #t), a window with no room, each frame given back
;;; unsent; (away from . to), the ms with no refresh; (hung . #t), that time
;;; a hang, with the word on the refresh before it in as it ends; and
;;; (descent . #t), the descent that a run's start owes taken, where the
;;; loop's checks have none due.
(define pacer2-test-ways '())
(define (pacer2-test-way key default)
  (let ([w (assq key pacer2-test-ways)]) (if w (cdr w) default)))

;; The frames so far; when core0's last acquire returned, and when the
;; newest frame is taken; the refresh the last frame shows at; the GPU-done
;; times to come; the frames given back unsent and not yet taken back;
;; each frame shown, (n . refresh), the newest first; core1's wakes; when
;; the flood's next key comes (#f for none); and the waits with no end.
(define pacer2-test-n 0)
(define pacer2-test-returned 0)
(define pacer2-test-taken 0)
(define pacer2-test-last 0)
(define pacer2-test-dones '())
(define pacer2-test-backs '())
(define pacer2-test-shows '())
(define pacer2-test-wakes 0)
(define pacer2-test-flood-at #f)
(define pacer2-test-endless 0)

(define (pacer2-test-period)
  (exact (round (pacer2-test-way 'period (core0-frame-ns)))))

;; Returns the first refresh at x or after with the screen there; the
;; phase and the time away count from the run's base.
(define (pacer2-test-refresh-from x)
  (let* ([p (pacer2-test-period)]
         [ph (+ pacer2-test-base (pacer2-test-way 'phase 0))]
         [r (+ ph (* p (ceiling (/ (- x ph) p))))]
         [away (pacer2-test-way 'away #f)])
    (if (and away (< (* (car away) 1000000) (- r pacer2-test-base)
                     (* (cdr away) 1000000)))
        (pacer2-test-refresh-from (+ r 1))
        r)))

;; Returns when the screen's word on a refresh at x is in: then, except
;; that the word on the refresh before a time away that is a hang comes as
;; the hang ends, as GNOME's does while its loop is held.
(define (pacer2-test-word-at x)
  (let ([away (pacer2-test-way 'away #f)] [ms 1000000])
    (if (and away (pacer2-test-way 'hung #f)
             (<= (- (* (car away) ms) (pacer2-test-period))
                 (- x pacer2-test-base)
                 (* (car away) ms)))
        (+ pacer2-test-base (* (cdr away) ms))
        x)))

;; Publishes a frame (rec-present!): works out what core0 and the screen
;; will do with it, each word of its report in at its time. Returns its
;; number.
(define (pacer2-test-publish!)
  (let* ([n (+ pacer2-test-n 1)] [t pacer2-test-t]
         [taken (max t pacer2-test-returned)]
         [reports? (pacer2-test-way 'reports #t)]
         [mailbox? (pacer2-test-way 'mailbox #f)])
    (set! pacer2-test-n n)
    (if (pacer2-test-way 'full #f)
        (set! pacer2-test-backs (cons n pacer2-test-backs))
        (let* ([returned (cond [(or mailbox? (not reports?)) taken]
                               [(not (pacer2-test-way 'deep #f))
                                (max taken pacer2-test-last)]
                               [(and (pair? pacer2-test-shows)
                                     (pair? (cdr pacer2-test-shows)))
                                (max taken (cdadr pacer2-test-shows))]
                               [else taken])]
               [done (+ returned 1000000)]
               [at (pacer2-test-refresh-from (+ done 4000000))]
               [shown (and reports?
                           (if mailbox?
                               at
                               (max at (pacer2-test-refresh-from
                                        (+ pacer2-test-last 1)))))])
          (set! pacer2-test-taken taken)
          (set! pacer2-test-returned returned)
          (for-each (lambda (k v) (pacer2-test-report! n k v v))
                    '(7 8 9 6)
                    (list taken taken returned done))
          (set! pacer2-test-dones
            (append (filter (lambda (d) (> d t)) pacer2-test-dones)
                    (list done)))
          (when shown
            (when (and mailbox? (pair? pacer2-test-shows)
                       (= (cdar pacer2-test-shows) shown))
              (pacer2-test-report! (caar pacer2-test-shows) 1 2 shown)
              (set! pacer2-test-shows (cdr pacer2-test-shows)))
            (pacer2-test-report! n 1 1 (pacer2-test-word-at shown))
            (pacer2-test-report! n 3 shown (pacer2-test-word-at shown))
            (pacer2-test-report! n 4 (pacer2-test-period)
                                (pacer2-test-word-at shown))
            (set! pacer2-test-last shown)
            (set! pacer2-test-shows (cons (cons n shown) pacer2-test-shows)))))
    n))

;; Core1's wait for core0's events (screen-events). Frames given back
;; unsent end it at once, and are taken back as render-frames-back! takes
;; them; otherwise it lasts until wait ns pass, the next GPU-done or the
;; flood's key, and ends a little late. A wait with no end is counted, and
;; lasts a second.
(define (pacer2-test-events wait)
  (if (pair? pacer2-test-backs)
      (begin
        (for-each (lambda (n) (frame-ring-set! n 5 2) (request-frame!))
                  pacer2-test-backs)
        (set! pacer2-test-backs '())
        '())
      (let* ([t pacer2-test-t]
             [done (find (lambda (d) (> d t)) pacer2-test-dones)]
             [ends (filter values (list (and wait (+ t wait)) done
                                        pacer2-test-flood-at))]
             [to (if (null? ends)
                     (begin (set! pacer2-test-endless (+ pacer2-test-endless 1))
                            (+ t 1000000000))
                     (apply min ends))])
        (set! pacer2-test-wakes (+ pacer2-test-wakes 1))
        (set! pacer2-test-t
          (max t (+ to (* 1000 (mod (* pacer2-test-wakes 7919) 400)))))
        (if (and pacer2-test-flood-at (<= pacer2-test-flood-at pacer2-test-t))
            (begin (set! pacer2-test-flood-at (+ pacer2-test-t 2000000))
                   '((key-down #\b ())))
            '()))))

;; Runs thunk with core1's loop on the fake screen of ways, asking the
;; second pacer, fresh, with the fake clock from a new base on and timers
;; of its own; all is as it was afterward.
(define (pacer2-test-on-screen ways thunk)
  (set! pacer2-test-ways ways)
  (set! pacer2-test-n 0)
  (set! pacer2-test-returned 0)
  (set! pacer2-test-taken 0)
  (set! pacer2-test-last 0)
  (set! pacer2-test-dones '())
  (set! pacer2-test-backs '())
  (set! pacer2-test-shows '())
  (set! pacer2-test-wakes 0)
  (set! pacer2-test-flood-at #f)
  (set! pacer2-test-endless 0)
  (pacer2-test-fresh (pacer2-test-new-base!)
    (lambda ()
      (unless (pacer2-test-way 'descent #f)
        (set! *pacer2-probed* pacer2-test-t))
      (pacer2-test-reported
       (lambda ()
         ;; core0 says how it presents, as of a screen's
         (fluid-let ([rec-present! pacer2-test-publish!]
                     [screen-events pacer2-test-events]
                     [gpu-frame-waiting?
                      (lambda () (> pacer2-test-taken pacer2-test-t))]
                     [*gpu-facts*
                      (cons (cons 'present-mode
                                  (if (pacer2-test-way 'mailbox #f)
                                      'mailbox
                                      'vsync))
                            *gpu-facts*)]
                     [*core0-forked* #t]
                     [*timers* '()]
                     [pacer2? (lambda () #t)])
           (thunk))))))
  (steps 1))

;; Runs core1's loop until the fake clock is at ns, for at most 50 steps a
;; ms of it, since past that the loop spins. Returns the steps.
(define (pacer2-test-loop-to ns)
  (let ([most (* 50 (max 1 (quotient (- ns pacer2-test-t) 1000000)))])
    (let loop ([k 0])
      (if (and (< pacer2-test-t ns) (< k most))
          (begin (schevana-step! (pacer2-wait-ns)) (loop (+ k 1)))
          k))))

;; Returns the gaps between times ts.
(define (pacer2-test-gaps ts)
  (map - (cdr ts) (list-head ts (- (length ts) 1))))

;;; ------------------------------------------------------------------
;;; A turn a period while the work fits

;; Runs core1's loop for ms of the fake clock on a screen that says
;; nothing. In it are a window whose tick keeps books (3 ms) and never
;; draws; one that moves at every tick (2 ms of its tick, draw-ms of
;; drawing); a busy process (0.5 ms a slice) if opts has 'busy; a timer at
;; 205 ms; a key at 503 ms; and with 'flood, a key every 2 ms besides, each
;; ending the wait. Returns an alist of what happened: the bookkeeper's
;; tick times, the frames drawn, the steps, the process's slices, when the
;; timer ran, whether the key came, the period, and the waits with no
;; end.
(define (pacer2-test-run draw-ms ms . opts)
  (let ([ticks '()] [frames 0] [slices 0] [fired #f] [keyed #f] [stepped 0]
        [period (core0-frame-ns)])
    (pacer2-test-on-screen '((reports . #f))
      (lambda ()
        (let* ([keeper (open-window "Keeper" 'size '(80 . 60)
                                    'open window-frame-soon!
                                    'frame (lambda (win at)
                                             (window-frame-soon! win)
                                             (set! ticks
                                               (cons pacer2-test-t ticks))
                                             (pacer2-test-advance! 3)))]
               [mover (open-window "Mover" 'size '(80 . 60)
                                   'open window-frame-soon!
                                   'frame (lambda (win at)
                                            (window-frame-soon! win)
                                            (pacer2-test-advance! 2)
                                            (invalidate! win))
                                   'key (lambda (win k mods) (set! keyed #t))
                                   'draw (lambda (win w h)
                                           (pacer2-test-advance! draw-ms)
                                           (set! frames (+ frames 1))))]
               [p (and (memq 'busy opts)
                       (spawn "paced" (lambda ()
                                        (let loop ()
                                          (set! pacer2-test-t
                                            (+ pacer2-test-t 500000))
                                          (set! slices (+ slices 1))
                                          (engine-block)
                                          (loop)))))])
          (focus-window! mover)
          ;; 100 ms to settle (the first frame has no work to go by)
          (pacer2-test-loop-to (+ pacer2-test-base 100000000))
          (set! ticks '())
          (set! frames 0)
          (set! slices 0)
          (set! pacer2-test-endless 0)
          (let ([start (now-ms)])
            (after 205 (lambda () (set! fired (- (now-ms) start)))))
          (when (memq 'flood opts) (set! pacer2-test-flood-at pacer2-test-t))
          (let ([end (+ pacer2-test-t (* ms 1000000))]
                [key-at (+ pacer2-test-t 503000000)])
            (let loop ()
              (when (and (< pacer2-test-t end) (< stepped (* 50 ms)))
                (when (and key-at (>= pacer2-test-t key-at))
                  (inject! '(key-down #\a ()))
                  (set! key-at #f))
                (schevana-step! (pacer2-wait-ns))
                (set! stepped (+ stepped 1))
                (loop))))
          (set! pacer2-test-flood-at #f)
          (when p (kill! p))
          (close-window! keeper)
          (close-window! mover))))
    `((ticks . ,(reverse ticks)) (frames . ,frames) (steps . ,stepped)
      (slices . ,slices) (fired . ,fired) (keyed . ,keyed)
      (period . ,period) (endless . ,pacer2-test-endless))))

(check "the pacer begins a turn a refresh apart while the work fits, with \
        bookkeeping that draws nothing, a busy process and input between: \
        a frame a turn, the process in the time left, a timer on its time, \
        and no wait with no end while turns are wanted"
       (let* ([r (pacer2-test-run 5 1000 'busy)]
              [get (lambda (k) (cdr (assq k r)))]
              [ticks (get 'ticks)] [period (get 'period)]
              [gaps (pacer2-test-gaps ticks)])
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
       (let* ([r (pacer2-test-run 5 1000)]
              [ticks (length (cdr (assq 'ticks r)))]
              [steps (cdr (assq 'steps r))])
         (printf "  ~a ticks, ~a steps\n" ticks steps)
         (and (<= 60 ticks 61) (<= steps (+ (* 2 ticks) 5)))))

(check "input that comes every 2 ms draws at the next turn: still a frame \
        a turn, a turn a period"
       (let* ([r (pacer2-test-run 5 1000 'flood)]
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
                     (lambda () (set! r (pacer2-test-run 5 1000 'flood))))]
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
       (let* ([r (pacer2-test-run 20 1000)]
              [ticks (cdr (assq 'ticks r))] [period (cdr (assq 'period r))]
              [gaps (pacer2-test-gaps ticks)])
         (printf "  ~a ticks, gaps ~a..~a\n" (length ticks) (apply min gaps)
                 (apply max gaps))
         (and (< 20 (length ticks) 45)
              (for-all (lambda (g) (>= g period)) gaps))))

;;; ------------------------------------------------------------------
;;; Turns that follow a screen that reports

;; Runs core1's loop for ms of the fake clock against the fake screen of
;; ways, away (no refresh) from away-from to away-to ms, and fast ns faster
;; than the mode says. A mover asks for a frame each tick, working 1 to 3
;; ms, and draws at every one, or at every nth with (draw-every . n); with
;; (long at . ms), one tick at at ms works ms more; a timer counts every 10
;; ms; and with (rate . r), the pacer's rate is r for the run. Returns
;; (refreshes frozen ts frames-away timers-away shows leads ticks state):
;; the refreshes that showed a frame; those that showed none between two
;; that did (except where the screen was away, and the first few); each
;; 'frame's t; the 'frame calls while the screen was away, and the timers
;; then; the refresh each frame showed at; each 'frame's t less the clock
;; then; the ticks; and the pacer's hold, the hold a descent has proven and
;; the aim of its last clean miss at the end. Times are ms from the run's
;; base, except the leads.
(define (pacer2-test-lock ms away-from away-to fast . ways)
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
    (pacer2-test-on-screen
     `((period . ,p) (away ,away-from . ,away-to) ,@ways)
     (lambda ()
       ;; another rate starts the pacer over at its next question; here at
       ;; once, so that no descent is owed
       (let ([rate (assq 'rate ways)])
         (when rate
           (pacer-rate! (cdr rate))
           (pacer2-forget!)
           (set! *pacer2-probed* pacer2-test-t)))
       (let ([mover (open-window "Mover" 'size '(80 . 60)
                                 'open window-frame-soon!
                                 'frame (lambda (win at)
                                          (window-frame-soon! win)
                                          (set! n (+ n 1))
                                          (set! ts
                                            (cons (- at pacer2-test-base) ts))
                                          (set! leads
                                            (cons (- at pacer2-test-t) leads))
                                          (when (away? (- pacer2-test-t
                                                          pacer2-test-base))
                                            (set! away-frames
                                              (+ away-frames 1)))
                                          (set! pacer2-test-t
                                            (+ pacer2-test-t 1000000
                                               (* 500000 (mod (* n 7) 5))))
                                          (when (and long
                                                     (>= (- pacer2-test-t
                                                            pacer2-test-base)
                                                         (* (car long)
                                                            1000000)))
                                            (set! pacer2-test-t
                                              (+ pacer2-test-t
                                                 (* (cdr long) 1000000)))
                                            (set! long #f))
                                          (when (= 0 (mod n draw-every))
                                            (invalidate! win)))
                                 'draw (lambda (win w h)
                                         (pacer2-test-advance! 1)))])
         (focus-window! mover)
         (let tick ()
           (after 10 (lambda ()
                       (when (away? (- pacer2-test-t pacer2-test-base))
                         (set! away-timers (+ away-timers 1)))
                       (when (< (- pacer2-test-t pacer2-test-base) end)
                         (tick)))))
         (pacer2-test-loop-to (+ pacer2-test-base end))
         (set! state (map pacer2-state '(hold proven missed)))
         (close-window! mover)
         (set! shows (reverse (map (lambda (s) (- (cdr s) pacer2-test-base))
                                   pacer2-test-shows))))))
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

(let* ([r (pacer2-test-lock 2000 1000 1300 0)]
       [ts (caddr r)]
       [steps (list-tail (pacer2-test-gaps ts) 3)]
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

;; As GNOME stalls at 120 Hz now and then: frames queued, then six
;; refreshes that take nothing, with the screen's word on the one before
;; them held until they end. The start's descent is owed, as at a run's
;; start: the first hold, a frame's in a flow, holds the time it waited
;; in the queue, and only a descent finds the screen's own.
(let* ([r (pacer2-test-lock 2000 1000 1050 0 '(deep . #t) '(hung . #t)
                           '(slow . 1/2) '(descent . #t))]
       [ts (caddr r)] [shows (list-ref r 5)]
       [n (min (length ts) (length shows))]
       [frames (filter (lambda (f)
                         (< (* 1000 1000000) (cdr f) (* 1300 1000000)))
                       (map cons (list-head ts n) (list-head shows n)))]
       [late (filter (lambda (f) (> (- (cdr f) (car f)) 500000)) frames)])
  (check (format "by VSync, two images queued, when the screen takes nothing \
                  for six refreshes and holds its word of the one before, \
                  only two frames show late, those it queued (~a ms): with \
                  two frames out it said nothing of, the turn after them \
                  waits for its word, and every frame after shows at its t"
                 (map (lambda (f) (/ (- (cdr f) (car f)) 1e6)) late))
         (and (= (length late) 2) (> (length frames) 10))))

(let ([r (pacer2-test-lock 3000 0 0 100000)])
  (check (format "a screen a little faster than it says still gets a frame \
                  every refresh: the period is the reports' (~a refreshes, \
                  ~a froze)" (car r) (cadr r))
         (and (> (car r) 150) (= (cadr r) 0))))

(for-each
 (lambda (ways what)
   (let* ([r (apply pacer2-test-lock 2000 0 0 0 ways)]
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

(let* ([r (pacer2-test-lock 2000 0 0 0 '(slow . 3/2))]
       [p (* 3/2 (core0-frame-ns))]
       [steps (list-tail (pacer2-test-gaps (caddr r)) 3)]
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

(let* ([r (pacer2-test-lock 2000 0 0 0 '(rate . 30))]
       [ticks (list-ref r 7)]
       [steps (list-tail (pacer2-test-gaps (caddr r)) 3)])
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
         (pacer2-test-fresh 0
           (lambda ()
             (pacer-rate! 30)
             (let ([p30 (pacer2-period)])
               (pacer-rate! 'screen)
               (let ([screen (pacer2-period)])
                 (pacer-rate! rate)
                 (and (= p30 33333333) (= screen (core0-frame-ns)))))))))

;; From stillness, at four phases of the screen, with one tick of 30 ms
;; more at 3 s: the refreshes frozen once frames flow. That tick's frame
;; misses its refresh, and the next one catches up.
(let ([frozen (map (lambda (phase)
                     (cadr (pacer2-test-lock 6000 0 0 0
                                            (cons 'phase phase)
                                            '(long 3000 . 30))))
                   '(0 4000000 8000000 12000000))])
  (check (format "an animation started from stillness freezes no refresh, at \
                  four phases of the screen; a 30 ms tick at 3 s, two \
                  refreshes at most (~a)" frozen)
         (for-all (lambda (k) (<= k 2)) frozen)))

;; The descent that a run's start owes, on a screen that shows a frame done
;; 4 ms before a refresh, whose frames' work varies by 2 ms: probes, one at
;; a time, bring the hold down from the first frame's lead, a probe's miss
;; ends the descent, and the hold lands. A probe done early, its work
;; short, proves a hold that the frames with the most work can't keep, so
;; the landing may fall under the cutoff, and a lone miss and a pair raise
;; it again.
(let* ([r (pacer2-test-lock 4000 0 0 0 '(descent . #t))]
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
                  s (hold, proven, last miss ~a)"
                 (cadr r) state)
         (and (<= (cadr r) 3) (= frozen-after 0)
              (= (cadr state) 0)
              (<= 3000000 (car state) 5000000))))

;;; ------------------------------------------------------------------
;;; Ticks only when one is wanted: for a redraw, a window's frame, or a look
;;; that input or a frame drawn asks for. On a fake clock, with no timers,
;;; the loop asking the second pacer.

(for-each close-window! (windows))
(let* ([events '()] [endless 0]
       [ticks-in (lambda (n)   ; the ticks of n steps of core1's loop
                   (let ([before (pacer-ticks)])
                     (do ([i 0 (+ i 1)]) ((= i n))
                       (schevana-step! (pacer2-wait-ns)))
                     (- (pacer-ticks) before)))])
  (pacer2-test-fresh (pacer2-test-new-base!)
    (lambda ()
      (fluid-let ([*timers* '()]
                  [pacer2? (lambda () #t)]
                  [screen-events (lambda (wait)
                                   (unless wait (set! endless (+ endless 1)))
                                   (set! pacer2-test-t
                                     (+ pacer2-test-t
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

;; Rows of a flow at r = 10 ms from T on, with nothing learned and no
;; descent due.
(define pacer2-test-r 10000000)
(define pacer2-test-T 1000000000000)

(check "the two callers in the loop's order: asked before the sleep, the \
        rule says how long; asked once that has passed, the wait says 0, \
        and the begin is made with the plan slept to"
       (let ([r pacer2-test-r] [T pacer2-test-T])
         (pacer2-test-fresh T
           (lambda ()
             (pacer2-test-reported
              (lambda ()
                (fluid-let ([*timers* '()] [procs-ready? (lambda () #f)])
                  (set! *pacer2-probed* T)
                  (do ([i 0 (+ i 1)]) ((= i 8))
                    (pacer2-test-flow-row! (+ T (* i r)) 3000000 r))
                  (set! pacer2-test-t (+ T (* 7 r)))
                  (set! *pacer-wanted?* #t)
                  (let* ([wait (pacer2-wait-ns)] [planned *pacer2-waited*])
                    (set! pacer2-test-t planned)
                    (let* ([again (pacer2-wait-ns)]
                           [kept *pacer2-waited*]
                           [begun? (pacer2-begin? (now-ns))])
                      (and (> wait 0) (= planned (+ T (* 7 r) wait))
                           (= again 0) (= kept planned) begun?
                           (= (pacer2-state 'plan) planned)
                           (= (pacer2-state 't) (+ T (* 8 r)))
                           (= (pacer2-state 'waited) 0)))))))))))

(check "after a frame whose work was over two refreshes, the turn after it \
        begins at once, and of thirty turns that draw nothing all but the \
        first two come a refresh apart, t within three refreshes of the \
        clock"
       (let ([r pacer2-test-r] [T pacer2-test-T] [begins '()] [ahead '()])
         (pacer2-test-fresh T
           (lambda ()
             (pacer2-test-reported
              (lambda ()
                (fluid-let ([*timers* '()] [procs-ready? (lambda () #f)])
                  (set! *pacer2-probed* T)
                  (do ([i 0 (+ i 1)]) ((= i 7))
                    (pacer2-test-flow-row! (+ T (* i r)) 3000000 r))
                  ;; its work 22.9 ms: begun 26 ms before its aim, done 3
                  ;; ms before it
                  (let ([aim (+ T (* 7 r))])
                    (pacer2-test-row! (- aim 26000000) (- aim 26000000) aim
                                     (- aim 3000000) (list 'shown aim) r))
                  (set! pacer2-test-t (+ T (* 7 r)))
                  (let loop ([k 0])
                    (when (and (< (length begins) 31) (< k 200))
                      (set! *pacer-wanted?* #t)
                      (let ([wait (pacer2-wait-ns)])
                        (set! pacer2-test-t (+ pacer2-test-t wait))
                        (when (pacer2-begin? pacer2-test-t)
                          (set! begins (cons pacer2-test-t begins))
                          (set! ahead
                            (cons (- (pacer2-state 't) pacer2-test-t) ahead))))
                      (loop (+ k 1)))))))))
         (let ([gaps (pacer2-test-gaps (reverse begins))])
           (printf "  ~a turns, gaps ~a..~a, t ahead ~a..~a\n"
                   (length begins) (apply min gaps) (apply max gaps)
                   (apply min ahead) (apply max ahead))
           (and (= (length begins) 31)
                (= (car (reverse begins)) (+ T (* 7 r)))
                (for-all (lambda (g) (<= (abs (- g r)) 500000))
                         (list-tail gaps 2))
                (for-all (lambda (a) (<= 0 a (* 3 r))) ahead)))))

(let ([woke #f] [fired '()] [start #f])
  (pacer2-test-on-screen '((reports . #f))
    (lambda ()
      (for-each close-window! (windows))
      (pacer2-test-loop-to (+ pacer2-test-base 50000000))
      (set! start pacer2-test-t)
      (spawn "sleeper" (lambda () (sleep-ms 50) (set! woke pacer2-test-t)))
      (after 1/2 (lambda () (set! fired (cons 'half fired))))
      (after 50/3 (lambda () (set! fired (cons 'third fired))))
      (let loop ([k 0])
        (when (and (not woke) (< k 200))
          (schevana-step! (pacer2-wait-ns))
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

;; Runs thunk on rows of its own at T, with the tests' reports and no
;; descent due.
(define (pacer2-test-rows thunk)
  (pacer2-test-fresh pacer2-test-T
    (lambda ()
      (pacer2-test-reported
       (lambda ()
         (set! *pacer2-probed* pacer2-test-T)
         (thunk))))))

(check "the first frame shown in a flow, the frame before it shown at the \
        refresh before, gives the hold, and one after a pause doesn't; no \
        frame lowers it then, though one in time made it with less lead, in \
        a flow or after a pause; nor does one with more lead, or late"
       (let ([r pacer2-test-r] [T pacer2-test-T] [ms 1000000])
         (pacer2-test-rows
          (lambda ()
            (define (row! k lead . shown)
              (apply pacer2-test-flow-row! (+ T (* k r)) lead r shown)
              (pacer2-test-judge! (+ T (* (+ k 1) r)))
              (pacer2-state 'hold))
            (let* ([alone (row! -1 (* 2 ms))]
                   [first (row! 0 (* 6 ms))]
                   [closer (row! 1 (* 5 ms))]
                   [paused (row! 3 (* 1 ms))]
                   [more (row! 4 (* 7 ms))]
                   [late (row! 5 (* 4 ms) (+ T (* 6 r)))])
              (equal? (list alone first closer paused more late)
                      (list 0 (* 6 ms) (* 6 ms) (* 6 ms) (* 6 ms)
                            (* 6 ms))))))))

(check "a clean miss alone is the compositor's; a pair raises the hold a \
        look over the lead that failed, never past the margin over the \
        hold; a third before a frame in time, a refresh over, which owes a \
        descent"
       (let ([r pacer2-test-r] [T pacer2-test-T] [ms 1000000]
             [L core0-look-ns])
         ;; the hold 6 ms; the misses' leads 7 ms, then pair, then 9 ms
         (define (misses pair)
           (pacer2-test-rows
            (lambda ()
              ;; each late a refresh, the frame before it shown before its
              ;; aim, begun on plan and done at least the hold before it
              (define (miss! k x)
                (pacer2-test-flow-row! (+ T (* k r)) x r (+ T (* (+ k 1) r)))
                (pacer2-test-judge! (+ T (* (+ k 2) r)))
                (list (pacer2-state 'hold) (pacer2-state 'soft?)))
              ;; a frame before the first, so that it comes in a flow
              (pacer2-test-flow-row! (- T r) (* 6 ms) r)
              (pacer2-test-flow-row! T (* 6 ms) r)
              (pacer2-test-judge! (+ T r))
              (let* ([alone (miss! 1 (* 7 ms))]
                     [pair (miss! 3 pair)]
                     [third (miss! 5 (* 9 ms))]
                     [owed (- (+ T (* 7 r)) (pacer2-state 'probed))])
                (list alone pair third owed)))))
         (let ([near (misses (* 13/2 ms))] [far (misses (* 8 ms))])
           (and (equal? near
                        (list (list (* 6 ms) #f) (list (+ (* 13/2 ms) L) #t)
                              (list (+ (* 9 ms) r) #f) pacer2-descent-ns))
                (equal? (cadr far)
                        (list (+ (* 6 ms) (pacer2-margin r) L) #t))))))

(check "two clean misses within three seconds are a pair, however many \
        frames in time come between, as a refresh that the compositor is \
        busier for every 600 ms makes them; two further apart are each alone"
       (let ([r pacer2-test-r] [T pacer2-test-T] [ms 1000000]
             [L core0-look-ns])
         ;; the hold 6 ms; misses with 6.5 ms of lead, the second k
         ;; refreshes after the first, a frame in time just before it
         (define (second-miss-at k)
           (pacer2-test-rows
            (lambda ()
              (define (miss! k)
                (pacer2-test-flow-row! (+ T (* k r)) (* 13/2 ms) r
                                       (+ T (* (+ k 1) r)))
                (pacer2-test-judge! (+ T (* (+ k 2) r))))
              (pacer2-test-flow-row! (- T r) (* 6 ms) r)
              (pacer2-test-flow-row! T (* 6 ms) r)
              (pacer2-test-judge! (+ T r))
              (miss! 1)
              (pacer2-test-flow-row! (+ T (* (- k 1) r)) (* 6 ms) r)
              (pacer2-test-judge! (+ T (* k r)))
              (miss! k)
              (pacer2-state 'hold))))
         (let ([near (second-miss-at 60)] [far (second-miss-at 400)])
           (and (= near (+ (* 13/2 ms) L)) (= far (* 6 ms))))))

(check "a descent begins after eight frames in time and on plan: one probe \
        at a time, a look under the hold proven, the frames around it at \
        the hold proven; a probe in time proves a look lower, and the next \
        frame probes"
       (let ([r pacer2-test-r] [T pacer2-test-T] [ms 1000000]
             [L core0-look-ns])
         (pacer2-test-rows
          (lambda ()
            (set! *pacer2-probed* 0)
            (do ([k 0 (+ k 1)]) ((= k 8))
              (pacer2-test-flow-row! (+ T (* k r)) (* 3 ms) r))
            (pacer2-test-judge! (+ T (* 8 r)))
            (let* ([begun (list (pacer2-state 'proven) (pacer2-state 'probe))]
                   ;; the work 1.9 ms, the margin, the slack two looks
                   [probe (pacer2-test-turn! (+ T (* 7 r)))]
                   [probe-at (pacer2-state 'probe)]
                   [next (pacer2-test-turn! pacer2-test-t)])
              (for-each (lambda (turn)
                          (pacer2-test-row! (car turn) (car turn) (cdr turn)
                                           (- (cdr turn) (* 3 ms))
                                           (list 'shown (cdr turn)) r))
                        (list probe next))
              (pacer2-test-judge! (+ T (* 10 r)))
              (let* ([proved (list (pacer2-state 'proven) (pacer2-state 'probe)
                                   (pacer2-state 'hold))]
                     [again (pacer2-test-turn! (+ T (* 9 r) ms))])
                (printf "  ~a ~a ~a ~a ~a\n" begun probe next proved again)
                (and (equal? begun (list (* 3 ms) 0))
                     (= (cdr probe) (+ T (* 8 r)) probe-at)
                     (= (- (cdr probe) (car probe))
                        (+ (- (* 3 ms) L) (pacer2-margin r) (* 19/10 ms)
                           (* 2 L)))
                     (= (cdr next) (+ T (* 9 r)))
                     (= (- (cdr next) (car next))
                        (+ (* 3 ms) (pacer2-margin r) (* 19/10 ms) (* 2 L)))
                     (equal? proved (list (- (* 3 ms) L) 0 (* 3 ms)))
                     (= (pacer2-state 'probe) (cdr again)))))))))

(check "a probe's first clean miss is a miss alone: the descent goes on, \
        and the next frame probes the same hold"
       (let ([r pacer2-test-r] [T pacer2-test-T] [ms 1000000]
             [L core0-look-ns])
         (pacer2-test-rows
          (lambda ()
            (pacer2-test-flow-row! T (* 9 ms) r)
            (pacer2-test-judge! (+ T r))
            (set! *pacer2-hold* (* 9 ms))
            (set! *pacer2-proven* (* 7 ms))
            (set! *pacer2-probe* (+ T r))
            (pacer2-test-flow-row! (+ T r) (* 7 ms) r (+ T (* 2 r)))
            (pacer2-test-judge! (+ T (* 3 r)))
            (let* ([after (map pacer2-state
                               '(hold proven probe probe-miss))]
                   [next (pacer2-test-turn! (+ T (* 3 r)))])
              (and (equal? after (list (* 9 ms) (* 7 ms) 0 (* 7 ms)))
                   next
                   (= (pacer2-state 'probe) (cdr next))
                   (= (pacer2-probe-hold) (- (* 7 ms) L))))))))

(check "a probe's second clean miss ends the descent: the hold two looks \
        over the larger lead of the two that failed, never over where it \
        began"
       (let ([r pacer2-test-r] [T pacer2-test-T] [ms 1000000]
             [L core0-look-ns])
         (define (probe-miss! hold proven first x)
           (pacer2-test-rows
            (lambda ()
              (pacer2-test-flow-row! T (* 9 ms) r)
              (pacer2-test-judge! (+ T r))
              (set! *pacer2-hold* hold)
              (set! *pacer2-proven* proven)
              (set! *pacer2-probe* (+ T r))
              (set! *pacer2-probe-miss* first)
              (pacer2-test-flow-row! (+ T r) x r (+ T (* 2 r)))
              (pacer2-test-judge! (+ T (* 3 r)))
              (list (pacer2-state 'hold) (pacer2-state 'proven)
                    (pacer2-state 'probe)))))
         (let ([under (probe-miss! (* 9 ms) (* 7 ms) (* 13/2 ms) (* 7 ms))]
               [first (probe-miss! (* 9 ms) (* 7 ms) (* 15/2 ms) (* 7 ms))]
               [over (probe-miss! (* 6 ms) (* 6 ms) (* 6 ms) (* 6 ms))])
           (and (equal? under (list (+ (* 7 ms) (* 2 L)) 0 0))
                (equal? first (list (+ (* 15/2 ms) (* 2 L)) 0 0))
                (equal? over (list (* 6 ms) 0 0))))))

(check "while a descent is in course, a clean miss of a frame not the \
        probe is the compositor's alone, and a pair raises the hold and \
        ends the descent; a descent down to a look ends there"
       (let ([r pacer2-test-r] [T pacer2-test-T] [ms 1000000]
             [L core0-look-ns])
         (pacer2-test-rows
          (lambda ()
            ;; a frame before the first, so that it comes in a flow
            (pacer2-test-flow-row! (- T r) (* 9 ms) r)
            (pacer2-test-flow-row! T (* 9 ms) r)
            (pacer2-test-judge! (+ T r))
            (set! *pacer2-proven* (* 7 ms))
            (set! *pacer2-probe* (+ T (* 20 r)))
            (pacer2-test-flow-row! (+ T r) (* 8 ms) r (+ T (* 2 r)))
            (pacer2-test-judge! (+ T (* 3 r)))
            (let ([alone (list (pacer2-state 'hold) (pacer2-state 'proven))])
              (pacer2-test-flow-row! (+ T (* 3 r)) (* 15/2 ms) r (+ T (* 4 r)))
              (pacer2-test-judge! (+ T (* 5 r)))
              (let ([pair (list (pacer2-state 'hold) (pacer2-state 'proven)
                                (pacer2-state 'probe))])
                ;; down to a look
                (set! *pacer2-proven* (* 2 L))
                (set! *pacer2-probe* (+ T (* 5 r)))
                (pacer2-test-flow-row! (+ T (* 5 r)) (* 6 ms) r)
                (pacer2-test-judge! (+ T (* 6 r)))
                (and (equal? alone (list (* 9 ms) (* 7 ms)))
                     (equal? pair (list (+ (* 15/2 ms) L) 0 0))
                     (= (pacer2-state 'hold) L)
                     (= (pacer2-state 'proven) 0))))))))

(check "a frame shown at another rate, its refresh off the one before by \
        over a 64th, starts all that was learned over: the hold its own \
        lead, no clean miss kept, no descent, one owed"
       (let ([r pacer2-test-r] [T pacer2-test-T] [ms 1000000])
         (pacer2-test-rows
          (lambda ()
            (pacer2-test-flow-row! T (* 6 ms) r)
            (pacer2-test-judge! (+ T r))
            (set! *pacer2-missed* (+ T r))
            (set! *pacer2-proven* (* 5 ms))
            (set! *pacer2-soft?* #t)
            (let ([r2 (+ r (quotient r 32))])
              (pacer2-test-flow-row! (+ T r2) (* 4 ms) r2)
              (pacer2-test-judge! (+ T r2 r2))
              (and (= (pacer2-state 'hold) (* 4 ms))
                   (= (pacer2-state 'missed) 0)
                   (= (pacer2-state 'proven) 0)
                   (not (pacer2-state 'soft?))
                   (= (pacer2-state 'probed)
                      (- (+ T r2 r2) pacer2-descent-ns))))))))

(check "with no reports, an acquire the screen held leaves a refresh out of \
        our own grid only with three frames in flight, not two"
       (let ([T pacer2-test-T] [L core0-look-ns])
         (define (aim-with in-flight)
           (pacer2-test-rows
            (lambda ()
              (fluid-let ([*gpu-frames-in-flight* in-flight])
                (let ([n (pacer2-test-row! (- T 1000000) (- T 1000000) T
                                          (+ T (* 2 L) 1000000) 'out
                                          pacer2-test-r)])
                  (pacer2-test-report! n 9 (+ T (* 2 L)) 0)
                  (set! *pacer2-t* T)
                  (cdr (pacer2-test-turn! (- T 1000000))))))))
         (let ([s (let ([p (core0-frame-ns)]) (- p (quotient p 512)))])
           (and (= (aim-with 3) (+ T s s)) (= (aim-with 2) (+ T s))))))

(check "with no reports and no aim yet (a run's start, or the first pacer's \
        turns since the last), a turn begins at once, though the frames' \
        work would plan it later: a begin on a grid drawn from now would \
        move on with now and never come"
       (let ([T pacer2-test-T] [ms 1000000] [p (core0-frame-ns)])
         (pacer2-test-rows
          (lambda ()
            ;; eight frames before, 3 ms of work each, their GPU work done,
            ;; and nothing reported
            (do ([k 0 (+ k 1)]) ((= k 8))
              (let ([b (- T (* (- 8 k) p))])
                (pacer2-test-row! b b (+ b p) (+ b (* 3 ms)) 'out p)))
            (let ([turn (pacer2-test-turn! T)])
              (and turn (= (car turn) T)))))))

(check "a turn waits while the newest frame's GPU work isn't seen done, \
        eight refreshes at most; then, its frame still in the slot, a \
        refresh at a time; else it begins"
       (let ([T pacer2-test-T])
         (pacer2-test-rows
          (lambda ()
            (pacer2-test-row! T T T 0 'out pacer2-test-r)
            (set! *pacer-wanted?* #t)
            (let* ([p (pacer2-period)]
                   [gate (pacer2-decide! (+ T 1000000))]
                   [slot (fluid-let ([gpu-frame-waiting? (lambda () #t)])
                           (pacer2-decide! (+ T (* 8 p))))]
                   [begin (pacer2-decide! (+ T (* 8 p)))])
              (and (= gate (+ T (* 8 p)))
                   (= slot (+ T (* 9 p)))
                   (eq? begin #t)))))))

(check "by VSync, a frame out that the screen has said nothing of a \
        refresh and a half after its aim showed at neither refresh, nor \
        will those behind it: the next turn begins two refreshes later; \
        not before then (one that missed a refresh shows at the next), nor \
        by Mailbox, nor once its report is in though core0 holds it back; \
        eight refreshes past its aim, it begins at once"
       (let ([r pacer2-test-r] [T pacer2-test-T] [ms 1000000])
         ;; => when the next turn begins, or #t: now; with a stamp, the
         ;; first out's report in, held back
         (define (turn now mode . stamp)
           (pacer2-test-rows
            (lambda ()
              (fluid-let ([*gpu-facts* (cons (cons 'present-mode mode)
                                             *gpu-facts*)])
                (do ([i 7 (- i 1)]) ((< i 1))
                  (pacer2-test-flow-row! (- T (* i r)) (* 3 ms) r))
                ;; out: aimed at T, begun 4 ms before the refresh before
                ;; it, done 7 ms before its aim; the one behind it alike;
                ;; and the newest, begun 6 ms after T, done 8 ms before
                ;; its own
                (let ([n (pacer2-test-row! (- T r (* 4 ms)) (- T r (* 4 ms))
                                          T (- T (* 7 ms)) 'out r)])
                  (when (pair? stamp)
                    (pacer2-test-report! n 10 (car stamp) 0)))
                (pacer2-test-row! (- T (* 4 ms)) (- T (* 4 ms))
                                 (+ T r) (+ T (* 3 ms)) 'out r)
                (pacer2-test-row! (+ T (* 6 ms)) (+ T (* 6 ms)) (+ T r r)
                                 (+ T (* 12 ms)) 'out r)
                (set! *pacer-wanted?* #t)
                (pacer2-decide! now)))))
         (let ([before (turn (+ T (* 14 ms)) 'vsync)]
               [after (turn (+ T (* 16 ms)) 'vsync)]
               [mailbox (turn (+ T (* 16 ms)) 'mailbox)]
               [held (turn (+ T (* 16 ms)) 'vsync (+ T r))]
               [stuck (turn (+ T (* 12 r)) 'vsync)])
           (printf "  begins ~a, ~a, ~a, ~a ms after T; ~a\n"
                   (and (number? before) (/ (- before T) 1e6))
                   (and (number? after) (/ (- after T) 1e6))
                   (and (number? mailbox) (/ (- mailbox T) 1e6))
                   (and (number? held) (/ (- held T) 1e6))
                   stuck)
           (and (number? before) (number? after)
                (> before (+ T (* 16 ms)))
                (= (- after before) (* 2 r))
                (eqv? mailbox before)
                (eqv? held before)
                (eq? stuck #t)))))

(check "a report stamped two seconds ahead of the clock gives no hold and is \
        not the grid: the wait it leaves has an end within nine refreshes"
       (let ([r pacer2-test-r] [T pacer2-test-T])
         (pacer2-test-rows
          (lambda ()
            (pacer2-test-flow-row! T 6000000 r (+ T 2000000000))
            (set! *pacer-wanted?* #t)
            (let ([a (pacer2-decide! (+ T 1000000))])
              (and (= (pacer2-state 'hold) 0)
                   (or (eq? a #t)
                       (<= a (+ T (* 9 (pacer2-period)))))))))))
