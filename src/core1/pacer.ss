;;; pacer.ss — when the world's next turn begins, and the time its frame is
;;; drawn for: the refresh it aims at.
;;;
;;; Every published frame leaves a row (the frame ring's, and core0's report
;;; of it): its turn's begin and the begin it was planned for, its aim, when
;;; it was published and taken, how long the screen held core0 for it, when
;;; its GPU work was first seen done, and which refresh showed it. Each
;;; question reads the last sixteen rows again. The grid is the newest
;;; refresh reported, or our own a 512th fast; the work is the largest of
;;; the last eight rows'. A turn waits while the newest frame's GPU work is
;;; not seen done (eight refreshes at most), aims at the first refresh the
;;; frames out leave it, and begins a hold, the work and a slack before it.
;;; The hold, how long before a refresh GPU work must be seen done, is the
;;; one number learned: from the first frame shown, lowered by one shown in
;;; time with less lead, raised by a pair of clean misses, and tried lower
;;; once in a few minutes, one probe frame at a time.

;; One descent begun a period, ns: the few minutes a repeated refresh may be
;; risked in.
(define pacer-descent-ns 180000000000)

;; What the rows can't give: the last turn's time, its aim; the hold (0,
;; not known), and the floor a closer call stops at (0, none); while a
;; descent is in course, the hold proven (0, none) and the aim of its probe
;; out (0, none), and when the last began; the last raise was a look and no
;; frame has been in time since; the rows judged, of *frame-ring-n*; the
;; begin the loop sleeps to (0, none).
(defvar *pacer-t* 0)
(defvar *pacer-hold* 0)
(defvar *pacer-floor* 0)
(defvar *pacer-proven* 0)
(defvar *pacer-probe* 0)
(defvar *pacer-probed* (- pacer-descent-ns))
(defvar *pacer-soft?* #f)
(defvar *pacer-judged* 0)
(defvar *pacer-waited* 0)
;; The turn's own: one is asked for; the turns so far, and when the last
;; began (now-ms); the rate, screen or turns a second; and this turn's aim
;; and plan, for its frame's row (0, none).
(defvar *pacer-wanted?* #f)
(defvar *pacer-ticks* 0)
(defvar *pacer-tick-ms* 0)
(defvar *pacer-rate* 'screen)
(defvar *pacer-aim* 0)
(defvar *pacer-plan* 0)

;; A turn asked for: windows' frames and the surfaces' look at what
;; changed, and a frame if something asked for one (*dirty*).
(define (frame-turn-soon!) (set! *pacer-wanted?* #t))
(define (pacer-wanted?) (or *pacer-wanted?* *dirty*))
(define (pacer-ticks) *pacer-ticks*)
(define (pacer-rate) *pacer-rate*)

;; When the frame the last turn made shows, ns, the t of a window's 'frame:
;; the refresh it aims at, never earlier than the last; unpaced (a test's),
;; the turn's own ms.
(define (pacer-frame-ns) *pacer-t*)

;; (pacer-rate! 30): turns a 30th of a second apart, on a grid of our own;
;; (pacer-rate! 'screen), the default: a turn a refresh. Apps that move by
;; time still read the clock.
(define (pacer-rate! rate)
  (set! *pacer-rate* rate)
  (pacer-forget!))

;; The period, ns: the refresh length core0's clock gave the newest row
;; shown of the last sixteen; before any, the mode's (core0's guess when the
;; platform states none). A fixed rate's.
(define (pacer-period)
  (if (eq? *pacer-rate* 'screen)
      (let loop ([i (fx- *frame-ring-n* 1)])
        (cond [(fx< i (fxmax 0 (fx- *frame-ring-n* 16))) (core0-frame-ns)]
              [(fx= (pacer-kind i) 1) (pacer-seen i 4)]
              [else (loop (fx- i 1))]))
      (quotient 1000000000 *pacer-rate*)))

;; The hold and all that was learned with it, gone, as at another rate: a
;; descent may begin at now.
(define (pacer-relearn! now)
  (set! *pacer-hold* 0)
  (set! *pacer-floor* 0)
  (set! *pacer-proven* 0)
  (set! *pacer-probe* 0)
  (set! *pacer-probed* (fx- now pacer-descent-ns))
  (set! *pacer-soft?* #f))

;; As at a run's start.
(define (pacer-forget!)
  (pacer-relearn! 0)
  (set! *pacer-t* 0)
  (set! *pacer-judged* *frame-ring-n*)
  (set! *pacer-waited* 0))

;;; ---- the rows: the frame ring's row i, and its report

;; Word k of row i, core1's: 5 given back (2, unsent), 6 its number, 8 its
;; turn's begin, 10 its publish, 13 its aim, 14 its plan.
(define (pacer-own i k)
  (fxvector-ref *frame-ring*
                (fx+ k (fx* frame-ring-words (fxmodulo i frame-ring-rows)))))

;; Word k of row i's report, core0's: 1 its kind, 3 the refresh that showed
;; it, 4 that refresh's length, 6 done, 7 taken, 8 and 9 the screen's hold;
;; 0 till core0 has written it.
(define (pacer-seen i k) (or (core0-frame-report (pacer-own i 6) k) 0))

;; 0 out, 1 shown, 2 dropped, 3 back.
(define (pacer-kind i) (if (fx= (pacer-own i 5) 2) 3 (pacer-seen i 1)))

;; The row's refresh length; a dropped row's is the period.
(define (pacer-refresh i)
  (let ([r (pacer-seen i 4)]) (if (fx= r 0) (pacer-period) r)))

(define (pacer-on-time? i)
  (and (fx= (pacer-kind i) 1)
       (fx<= (fx- (pacer-seen i 3) (pacer-own i 13))
             (fxquotient (pacer-refresh i) 2))))

;;; ---- the hold a frame is planned with

;; A probe's: a look under the hold proven, never under a look.
(define (pacer-probe-hold)
  (fxmax core0-look-ns (fx- *pacer-proven* core0-look-ns)))

;; Row i is the descent's probe.
(define (pacer-probe? i)
  (and (fx> *pacer-probe* 0) (fx= (pacer-own i 13) *pacer-probe*)))

;; The hold row i was planned with: the learned one; while a descent is in
;; course, the one proven, and the probe's for the probe.
(define (pacer-hold-of i)
  (cond [(fx= *pacer-proven* 0) *pacer-hold*]
        [(pacer-probe? i) (pacer-probe-hold)]
        [else *pacer-proven*]))

;;; ---- the judge

;; A clean miss => the lead that failed; else #f: begun on its plan, done
;; at least the hold it was planned with before its aim, and the frame
;; before it shown before then. lo is the oldest row read.
(define (pacer-missed i lo)
  (let ([kind (pacer-kind i)] [aim (pacer-own i 13)])
    (and (or (fx= kind 1) (fx= kind 2))
         (not (pacer-on-time? i))
         (fx> (pacer-seen i 6) 0)
         (fx> (pacer-own i 14) 0)
         (or (fx= i lo)
             (and (fx= (pacer-kind (fx- i 1)) 1)
                  (fx<= (pacer-seen (fx- i 1) 3)
                        (fx- aim (fxquotient (pacer-refresh i) 2)))))
         (let ([x (fx- aim (pacer-seen i 6))])
           (and (fx<= (pacer-hold-of i) x) x)))))

(define (pacer-missed-before? i lo)
  (let loop ([j lo])
    (and (fx< j i) (or (pacer-missed j lo) (loop (fx+ j 1))))))

;; Rows i-7 to i all read, in time and begun on plan: a flow.
(define (pacer-settled? i lo)
  (and (fx>= (fx- i 7) lo)
       (let loop ([j (fx- i 7)])
         (or (fx> j i)
             (and (pacer-on-time? j) (fx> (pacer-own j 14) 0)
                  (loop (fx+ j 1)))))))

;; Row i, its report in: once. Its verdict is traced with its number: 0 in
;; time, 1 late and no clean miss, 2 a clean miss alone, 3 the probe's miss
;; (the descent ends), 4 a pair (a look up), 5 a miss after it (a refresh
;; up), 6 the probe in time (a look lower proven), 7 in time, and a descent
;; begins.
(define (pacer-judge! i lo now)
  (let ([look core0-look-ns] [r (pacer-refresh i)] [S (pacer-seen i 3)]
        [done (pacer-seen i 6)] [in-time? (pacer-on-time? i)])
    ;; a probe this row's aim has passed never came: its turn drew nothing,
    ;; or its frame went back; the next turn probes
    (when (and (fx> *pacer-probe* 0) (fx> (pacer-own i 13) *pacer-probe*))
      (set! *pacer-probe* 0))
    (when (fx= (pacer-kind i) 1)
      ;; another rate: all that was learned starts over
      (when (and (fx> i lo) (fx= (pacer-kind (fx- i 1)) 1)
                 (fx> (fxabs (fx- r (pacer-refresh (fx- i 1))))
                      (fxquotient r 64)))
        (pacer-relearn! now))
      ;; the first frame shown gives the hold; one in time with less lead
      ;; lowers it, never under the floor, and not while a descent tries
      ;; it. A lead is over 0, and no stamp is over a refresh ahead of the
      ;; clock.
      (let ([a (fxmax *pacer-floor* (fx- S done))])
        (when (and (fx< 0 done S) (fx<= S (fx+ now r))
                   (or (fx= *pacer-hold* 0)
                       (and in-time? (fx= *pacer-proven* 0)
                            (fx< a *pacer-hold*))))
          (set! *pacer-hold* a))))
    (core0-trace!
     19
     (fx+ (fx* 8 (pacer-own i 6))
          (let ([probe? (pacer-probe? i)]
                [x (and (not in-time?) (pacer-missed i lo))])
            (when probe? (set! *pacer-probe* 0))
            (cond
              [in-time?
               (set! *pacer-soft?* #f)
               (cond
                 [probe?
                  (set! *pacer-proven* (fxmax look (fx- *pacer-proven* look)))
                  ;; down to a look: nothing lower is tried
                  (when (fx= *pacer-proven* look)
                    (set! *pacer-hold* look)
                    (set! *pacer-proven* 0))
                  6]
                 [(and (fx= *pacer-proven* 0)
                       (fx>= (fx- now *pacer-probed*) pacer-descent-ns)
                       (pacer-settled? i lo))
                  (set! *pacer-proven* *pacer-hold*)
                  (set! *pacer-floor* 0)
                  (set! *pacer-probed* now)
                  7]
                 [else 0])]
              [(not x) 1]
              ;; it lands two looks over the lead that failed, never over
              ;; where it began; a closer call stops a look over it
              [probe?
               (set! *pacer-hold* (fxmin *pacer-hold* (fx+ x (fx* 2 look))))
               (set! *pacer-floor* (fx+ x look))
               (set! *pacer-proven* 0)
               3]
              ;; one clean miss alone is the compositor's; a pair raises the
              ;; hold a look over the lead that failed, and a miss after it,
              ;; no frame in time between, a refresh over, which owes a
              ;; descent. A raise ends a descent in course.
              [(or *pacer-soft?* (pacer-missed-before? i lo))
               (set! *pacer-hold* (fx+ x (if *pacer-soft?* r look)))
               (when *pacer-soft?*
                 (set! *pacer-probed* (fx- now pacer-descent-ns)))
               (set! *pacer-soft?* (not *pacer-soft?*))
               (set! *pacer-proven* 0)
               (set! *pacer-probe* 0)
               (if *pacer-soft?* 4 5)]
              [else 2]))))))

;;; ---- the decision

;; The grid's refresh at or after x: v a refresh, s its step.
(define (pacer-ceiling x v s) (fx- v (fx* s (fxdiv (fx- v x) s))))

;; The chain: the refresh the newest frame out takes, from row i on, S the
;; newest reported.
(define (pacer-chain i n S v s need)
  (if (fx< i n)
      (pacer-chain
       (fx+ i 1) n
       (if (fx= (pacer-kind i) 0)
           (fxmax (fx+ S s)
                  (let ([done (pacer-seen i 6)])
                    (if (fx> done 0)
                        (pacer-ceiling (fx+ done need) v s)
                        (pacer-own i 13))))
           S)
       v s need)
      S))

;; Row i is out, its GPU work not seen done.
(define (pacer-out? i)
  (and (fx>= i 0) (fx= (pacer-kind i) 0) (fx= (pacer-seen i 6) 0)))

;; The newest row shown, from i down to lo, its stamp no more than a
;; refresh ahead of now; else -1.
(define (pacer-shown i lo now)
  (cond [(fx< i lo) -1]
        [(and (fx= (pacer-kind i) 1)
              (fx<= (pacer-seen i 3) (fx+ now (pacer-refresh i))))
         i]
        [else (pacer-shown (fx- i 1) lo now)]))

;; The question, at now: => #t, a turn may begin (its aim is in *pacer-aim*);
;; else when to ask again (now-ns), or 0: not till something is wanted. The
;; rows whose reports are in are judged first. Asked again with nothing new
;; it answers the same: a begin is pacer-begin?'s to make.
(define (pacer-decide! now)
  (let* ([n *frame-ring-n*] [lo (fxmax 0 (fx- n 16))] [new (fx- n 1)]
         [p (pacer-period)]
         [gate (fx+ (pacer-own new 8) (fx* 8 p))])
    (let loop ([i (fxmax *pacer-judged* lo)])
      (if (and (fx< i n) (not (fx= (pacer-kind i) 0)))
          (begin
            (unless (fx= (pacer-kind i) 3) (pacer-judge! i lo now))
            (loop (fx+ i 1)))
          (set! *pacer-judged* i)))
    (cond
      [(not (pacer-wanted?)) (set! *pacer-waited* 0) 0]
      [(and (pacer-out? new) (fx< now gate)) gate]
      [(and (pacer-out? new) (gpu-frame-waiting?)) (fx+ now p)]
      [else (pacer-plan! now n lo p)])))

;; The grid from the newest row shown, else our own; the work and the
;; lateness from the last eight rows; then the chain, the aim and the begin.
(define (pacer-plan! now n lo p)
  (let* ([reported (if (eq? *pacer-rate* 'screen)
                       (pacer-shown (fx- n 1) lo now)
                       -1)]
         [v (cond [(fx>= reported 0) (pacer-seen reported 3)]
                  [(fx= *pacer-t* 0) now]
                  [else *pacer-t*])]
         [s (if (fx>= reported 0)
                (pacer-refresh reported)
                (fx- p (fxquotient p 512)))])
    (let loop ([i (fxmax lo (fx- n 8))] [most 0] [least 0] [last 0] [late 0])
      (if (fx< i n)
          (let* ([done (pacer-seen i 6)] [b (pacer-own i 8)]
                 [plan (pacer-own i 14)]
                 [work (if (fx> done 0)
                           (fx- (fx- done b)
                                (fx+ (fx- (pacer-seen i 7) (pacer-own i 10))
                                     (fx- (pacer-seen i 9) (pacer-seen i 8))))
                           last)])
            (loop (fx+ i 1)
                  (fxmax most work)
                  (if (fx= least 0) work (fxmin least work))
                  work
                  (if (fx> plan 0) (fxmax late (fx- b plan)) late)))
          (let* ([look core0-look-ns]
                 [slack (fx+ late (fx* 2 look))]
                 [h (cond [(fx> *pacer-proven* 0)
                           (if (fx= *pacer-probe* 0)
                               (pacer-probe-hold)
                               *pacer-proven*)]
                          [(fx= *pacer-hold* 0) p]
                          [else *pacer-hold*])]
                 [need (fx- h slack)]
                 [F (fx+ s
                         (cond
                           [(fx>= reported 0)
                            (fxmax (pacer-chain (fx+ reported 1) n v v s need)
                                   (pacer-ceiling
                                    (fx- *pacer-t* (fxquotient s 2)) v s))]
                           ;; with no reports, an acquire the screen held
                           ;; leaves a slot out only with three frames in
                           ;; flight or more: with two it is the least
                           ;; depth the swapchain has
                           [(and (fx> n 0)
                                 (fx>= *gpu-frames-in-flight* 3)
                                 (fx> (fx- (pacer-seen (fx- n 1) 9)
                                           (pacer-seen (fx- n 1) 8))
                                      look))
                            (fx+ v s)]
                           [else v]))]
                 [A (fxmax F (pacer-ceiling (fx+ now (fx+ least need)) v s))]
                 [B (fx- (fx- A h) (fx+ most slack))])
            (cond
              ;; work over a refresh begins the next turn as the gate
              ;; opens: that turn, not the ones after it that draw nothing
              [(and (fx< now B) (fx< now F)
                    (or (fx< last s)
                        (fx> *pacer-t* (pacer-own (fx- n 1) 13))))
               (set! *pacer-waited* B)
               B]
              [else
               (set! *pacer-aim* A)
               #t]))))))

;;; ---- what the turn loop calls

;; May a turn begin? Paced (now, ns): by the rule, and the begin is made
;; here: t is the aim, the plan the begin the loop slept to, and while a
;; descent is in course with no probe out, this turn's frame is the probe.
;; A test's step (#f): always, and its t is its own ms.
(define (pacer-begin? now)
  (and (or (not now) (eq? (pacer-decide! now) #t))
       (begin
         (set! *pacer-wanted?* #f)
         (set! *pacer-ticks* (fx+ *pacer-ticks* 1))
         (set! *pacer-tick-ms* (now-ms))
         (cond [now (set! *pacer-t* (fxmax *pacer-aim* *pacer-t*))
                    (set! *pacer-plan* *pacer-waited*)
                    (when (and (fx> *pacer-proven* 0) (fx= *pacer-probe* 0))
                      (set! *pacer-probe* *pacer-aim*))]
               [else (set! *pacer-t* (* *pacer-tick-ms* 1000000))
                     (set! *pacer-aim* 0)
                     (set! *pacer-plan* 0)])
         (set! *pacer-waited* 0)
         (core0-trace! 22 *pacer-plan*)
         (core0-trace! 16 *pacer-aim*)
         (core0-trace! 17 *pacer-t*)
         (core0-trace! 18 *pacer-hold*)
         #t)))

;; How long the loop may wait, ns; #f, till it's woken: to the rule's time
;; or the first timer's; not at all while processes are ready.
(define (pacer-wait-ns)
  (if (procs-ready?)
      0
      (let* ([now (now-ns)]
             [wake (pacer-decide! now)]
             [ns (cond [(eq? wake #t) 0]
                       [(fx= wake 0) #f]
                       [else (fxmax 0 (fx- wake now))])])
        (if (pair? *timers*)
            (let ([due (max 0 (* 1000000
                                 (- (vector-ref (car *timers*) 0) (now-ms))))])
              (if ns (min ns due) due))
            ns))))

;; How long processes may run, whole ms: till the planned begin, 10 at
;; most; 1 while a turn is wanted and none is planned (its frame is being
;; made, or waits for the GPU); 10 with none wanted.
(define (pacer-procs-ms)
  (cond [(not (pacer-wanted?)) 10]
        [(fx> *pacer-waited* 0)
         (fxmax 1 (fxmin 10 (fxquotient (fx- *pacer-waited* (now-ns))
                                        1000000)))]
        [else 1]))

;; The pacer's state by name, for inspect-pacer and the Pipeline.
(define (pacer-state key)
  (case key
    [(t) *pacer-t*]
    [(hold) *pacer-hold*]
    [(floor) *pacer-floor*]
    [(proven) *pacer-proven*]
    [(probe) *pacer-probe*]
    [(probed) *pacer-probed*]
    [(soft?) *pacer-soft?*]
    [(aim) *pacer-aim*]
    [(plan) *pacer-plan*]
    [(judged) *pacer-judged*]
    [(waited) *pacer-waited*]
    [else #f]))
