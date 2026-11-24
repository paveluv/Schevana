;;; (schevana core pacer2) — the second pacer: when the world's next turn
;;; begins, and the time its frame is drawn for, the refresh it aims at.
;;; The loop asks it while the setting pacer is 2 ((schevana core pacer),
;;; pacer2?), which keeps what the two pacers share: what a turn is asked
;;; for, the rate, the turns so far, t, and the frame ring.
;;;
;;; Every frame published leaves a row (the frame ring's, and core0's
;;; report on it): its turn's begin and the begin it was planned for, its
;;; aim, when it was published and taken, how long the screen held core0
;;; for it, when its GPU work was first seen done, and which refresh showed
;;; it. Each question reads the last sixteen rows again. The grid is the
;;; newest refresh reported, or a grid of the pacer's own, a 512th fast;
;;; the work is the largest of the last eight rows'. A turn waits while the
;;; newest frame's GPU work isn't seen done (eight refreshes at most), aims
;;; at the first refresh that the frames out leave it (by VSync, a frame
;;; that the screen said nothing of a refresh and a half past its aim takes
;;; no refresh gone half a refresh), and begins a hold, a margin, the work
;;; and a slack before it. The hold, how long before a refresh a frame's
;;; GPU work must be seen done, is the one number learned: from the first
;;; frame shown, lowered by one shown in time with less lead, raised by a
;;; pair of clean misses, and tried lower once in a few minutes, one probe
;;; frame at a time. The margin is the screen's: its cutoff moves, and a
;;; frame done just over the hold still misses now and then.

(library (schevana core pacer2)
  (export
    pacer2-period pacer2-begin? pacer2-wait-ns pacer2-procs-ms pacer2-state)
  (import (chezscheme)
          (only (schevana base) define-state library-layer)
          (only (schevana core0) *gpu-facts* *gpu-frames-in-flight*
                core0-frame-ns core0-frame-report core0-look-ns core0-trace!
                gpu-frame-waiting?)
          (only (schevana core platform) now-ms now-ns)
          (only (schevana core processes) *timers* procs-ready?)
          (only (schevana core pacer) *frame-ring* *frame-ring-n*
                frame-ring-rows frame-ring-words pacer-rate pacer-ticks
                pacer-turn-begun! pacer-wanted?))

  (library-layer core)

  ;; One descent begun a period, ns: the few minutes in which a repeated
  ;; refresh may be risked.
  (define pacer2-descent-ns 180000000000)

  ;; Returns the margin over the hold, a part of the period p: how far past
  ;; the hold a frame done still misses more often than the compositor
  ;; loses a refresh of its own (GNOME's: a ms at 60 Hz, half of it at
  ;; 120).
  (define (pacer2-margin p) (fxquotient p 16))

  ;; Two clean misses this close are a pair, ns. A refresh that the
  ;; compositor loses on its own comes about one in 700 (GNOME's, 0.15%),
  ;; so its own misses seldom come this close, while a cutoff that its
  ;; busier refreshes move (another window's caret, blinking every 600 ms)
  ;; misses again well within it. It is wider than that needs: a refresh
  ;; shown again shows more than a ms of latency does.
  (define pacer2-pair-ns 3000000000)

  ;; What the rows can't give: the last turn's time, its aim; the hold (0
  ;; while not known); while a descent is in course, the hold proven (0
  ;; for none), the aim of its probe out (0 for none) and the lead a probe
  ;; missed by (0 for none), and when the last descent began; whether the
  ;; last raise was a look and no frame has been in time since; the aim of
  ;; the last clean miss (0 for none); the rows judged, of
  ;; *frame-ring-n*; the begin the loop sleeps to (0 for none); and this
  ;; turn's aim and plan, for its frame's row (0 for none).
  (define-state *pacer2-t* 0)
  (define-state *pacer2-hold* 0)
  (define-state *pacer2-proven* 0)
  (define-state *pacer2-probe* 0)
  (define-state *pacer2-probe-miss* 0)
  (define-state *pacer2-probed* (- pacer2-descent-ns))
  (define-state *pacer2-soft?* #f)
  (define-state *pacer2-missed* 0)
  (define-state *pacer2-judged* 0)
  (define-state *pacer2-waited* 0)
  (define-state *pacer2-aim* 0)
  (define-state *pacer2-plan* 0)
  ;; The turns so far as this pacer last began one, and the rate then: a
  ;; turn that the other pacer began, or another rate, starts it over, as
  ;; at a run's start.
  (define-state *pacer2-ticks* 0)
  (define-state *pacer2-rate* 'screen)

  ;; Returns the period, in ns: the refresh length that core0's clock gave
  ;; the newest row shown of the last sixteen; before any, the display
  ;; mode's (core0's guess where the platform states none); with a fixed
  ;; rate, the rate's.
  (define (pacer2-period)
    (if (eq? (pacer-rate) 'screen)
        (let loop ([i (fx- *frame-ring-n* 1)])
          (cond [(fx< i (fxmax 0 (fx- *frame-ring-n* 16))) (core0-frame-ns)]
                [(fx= (pacer2-kind i) 1) (pacer2-seen i 4)]
                [else (loop (fx- i 1))]))
        (quotient 1000000000 (pacer-rate))))

  ;; Forgets the hold and all that was learned with it, as at another rate:
  ;; a descent may begin at now.
  (define (pacer2-relearn! now)
    (set! *pacer2-hold* 0)
    (set! *pacer2-proven* 0)
    (set! *pacer2-probe* 0)
    (set! *pacer2-probe-miss* 0)
    (set! *pacer2-probed* (fx- now pacer2-descent-ns))
    (set! *pacer2-soft?* #f)
    (set! *pacer2-missed* 0))

  ;; Forgets everything, as at a run's start: the rows so far are passed
  ;; over.
  (define (pacer2-forget!)
    (pacer2-relearn! 0)
    (set! *pacer2-t* 0)
    (set! *pacer2-judged* *frame-ring-n*)
    (set! *pacer2-waited* 0)
    (set! *pacer2-ticks* (pacer-ticks))
    (set! *pacer2-rate* (pacer-rate)))

  ;;; ---- the rows: the frame ring's row i, and its report

  ;; Returns word k of row i, core1's: 5 given back (2 for unsent), 6 its
  ;; number, 8 its turn's begin, 10 its publish, 13 its aim, 14 its plan.
  (define (pacer2-own i k)
    (fxvector-ref *frame-ring*
                  (fx+ k (fx* frame-ring-words (fxmodulo i frame-ring-rows)))))

  ;; Returns word k of row i's report, core0's: 1 its kind, 3 the refresh
  ;; that showed it, 4 that refresh's length, 6 done, 7 taken, 8 and 9 the
  ;; screen's hold, 10 the screen's stamp, in as the report comes, though
  ;; core0 holds back one that says a refresh was missed, 12 when the
  ;; report came; 0 until core0 has written it.
  (define (pacer2-seen i k) (or (core0-frame-report (pacer2-own i 6) k) 0))

  ;; Returns row i's kind: 0 out, 1 shown, 2 dropped, 3 back.
  (define (pacer2-kind i) (if (fx= (pacer2-own i 5) 2) 3 (pacer2-seen i 1)))

  ;; Returns row i's refresh length; a dropped row's is the period.
  (define (pacer2-refresh i)
    (let ([r (pacer2-seen i 4)]) (if (fx= r 0) (pacer2-period) r)))

  (define (pacer2-on-time? i)
    (and (fx= (pacer2-kind i) 1)
         (fx<= (fx- (pacer2-seen i 3) (pacer2-own i 13))
               (fxquotient (pacer2-refresh i) 2))))

  ;;; ---- the hold a frame is planned with

  ;; Returns a probe's hold: a look under the hold proven, never under a
  ;; look.
  (define (pacer2-probe-hold)
    (fxmax core0-look-ns (fx- *pacer2-proven* core0-look-ns)))

  ;; Returns whether row i is the descent's probe.
  (define (pacer2-probe? i)
    (and (fx> *pacer2-probe* 0) (fx= (pacer2-own i 13) *pacer2-probe*)))

  ;; Returns the hold that row i was planned with: the learned one; while a
  ;; descent is in course, the one proven, and the probe's for the probe.
  (define (pacer2-hold-of i)
    (cond [(fx= *pacer2-proven* 0) *pacer2-hold*]
          [(pacer2-probe? i) (pacer2-probe-hold)]
          [else *pacer2-proven*]))

  ;;; ---- the judge

  ;; Returns the lead that failed for a clean miss, or else #f: a row begun
  ;; on its plan, its GPU work done at least the hold it was planned with
  ;; before its aim, and the frame before it shown before then. lo is the
  ;; oldest row read.
  (define (pacer2-missed i lo)
    (let ([kind (pacer2-kind i)] [aim (pacer2-own i 13)])
      (and (or (fx= kind 1) (fx= kind 2))
           (not (pacer2-on-time? i))
           (fx> (pacer2-seen i 6) 0)
           (fx> (pacer2-own i 14) 0)
           (or (fx= i lo)
               (and (fx= (pacer2-kind (fx- i 1)) 1)
                    (fx<= (pacer2-seen (fx- i 1) 3)
                          (fx- aim (fxquotient (pacer2-refresh i) 2)))))
           (let ([x (fx- aim (pacer2-seen i 6))])
             (and (fx<= (pacer2-hold-of i) x) x)))))

  ;; Returns whether row i came in a flow: the frame before it was shown
  ;; at the refresh before. A compositor that had nothing to show takes a
  ;; frame at once, and may stamp it with the refresh before it was sent,
  ;; so such a frame tells nothing of the hold that frames in a flow need.
  (define (pacer2-flowing? i lo)
    (and (fx> i lo)
         (fx= (pacer2-kind (fx- i 1)) 1)
         (let ([r (pacer2-refresh i)])
           (fx<= (fx- (pacer2-seen i 3) (pacer2-seen (fx- i 1) 3))
                 (fx+ r (fxquotient r 2))))))

  ;; Returns whether rows i-7 to i were all read, in time and begun on
  ;; their plans: a flow.
  (define (pacer2-settled? i lo)
    (and (fx>= (fx- i 7) lo)
         (let loop ([j (fx- i 7)])
           (or (fx> j i)
               (and (pacer2-on-time? j) (fx> (pacer2-own j 14) 0)
                    (loop (fx+ j 1)))))))

  ;; Judges row i, once its report is in, once. Its verdict is traced with
  ;; its number: 0 in time; 1 late, and no clean miss; 2 a clean miss alone
  ;; (a probe's first too); 3 a probe's second (the descent ends); 4 a pair
  ;; (a look up); 5 a miss after that (a refresh up); 6 the probe in time
  ;; (a look lower proven); 7 in time, and a descent begins.
  (define (pacer2-judge! i lo now)
    (let ([look core0-look-ns] [r (pacer2-refresh i)] [S (pacer2-seen i 3)]
          [done (pacer2-seen i 6)] [in-time? (pacer2-on-time? i)])
      ;; a probe whose aim this row's has passed never came: its turn drew
      ;; nothing, or its frame went back; the next turn probes
      (when (and (fx> *pacer2-probe* 0)
                 (fx> (pacer2-own i 13) *pacer2-probe*))
        (set! *pacer2-probe* 0))
      (when (fx= (pacer2-kind i) 1)
        ;; another rate: all that was learned starts over
        (when (and (fx> i lo) (fx= (pacer2-kind (fx- i 1)) 1)
                   (fx> (fxabs (fx- r (pacer2-refresh (fx- i 1))))
                        (fxquotient r 64)))
          (pacer2-relearn! now))
        ;; the first frame shown in a flow gives the hold; after that it
        ;; falls only by a descent, a look at a time, since a frame that made
        ;; it with less lead says nothing of the refreshes the compositor is
        ;; busier for. A lead is over 0, and no stamp is more than a refresh
        ;; ahead of the clock.
        (when (and (fx= *pacer2-hold* 0) (fx< 0 done S) (fx<= S (fx+ now r))
                   (pacer2-flowing? i lo))
          (set! *pacer2-hold* (fx- S done))))
      (core0-trace!
       19
       (fx+ (fx* 8 (pacer2-own i 6))
            (let* ([probe? (pacer2-probe? i)]
                   [x (and (not in-time?) (pacer2-missed i lo))]
                   [aim (pacer2-own i 13)]
                   [pair? (and x (fx> *pacer2-missed* 0)
                               (fx<= (fx- aim *pacer2-missed*)
                                     pacer2-pair-ns))])
              (when probe? (set! *pacer2-probe* 0))
              (when x (set! *pacer2-missed* aim))
              (cond
                [in-time?
                 (set! *pacer2-soft?* #f)
                 (cond
                   [probe?
                    (set! *pacer2-proven*
                      (fxmax look (fx- *pacer2-proven* look)))
                    ;; down to a look: nothing lower is tried
                    (when (fx= *pacer2-proven* look)
                      (set! *pacer2-hold* look)
                      (set! *pacer2-proven* 0))
                    6]
                   [(and (fx= *pacer2-proven* 0)
                         (fx>= (fx- now *pacer2-probed*) pacer2-descent-ns)
                         (pacer2-settled? i lo))
                    (set! *pacer2-proven* *pacer2-hold*)
                    (set! *pacer2-probe-miss* 0)
                    (set! *pacer2-probed* now)
                    7]
                   [else 0])]
                [(not x) 1]
                ;; a probe's first clean miss may be the compositor's, as
                ;; any frame's alone may be: the next frame probes the same
                ;; hold. The second lands the hold two looks over the
                ;; larger lead of the two that failed (one whose work ran
                ;; long failed with less), never over where it began
                [(and probe? (fx= *pacer2-probe-miss* 0))
                 (set! *pacer2-probe-miss* x)
                 2]
                [probe?
                 (set! *pacer2-hold*
                   (fxmin *pacer2-hold*
                          (fx+ (fxmax x *pacer2-probe-miss*) (fx* 2 look))))
                 (set! *pacer2-proven* 0)
                 3]
                ;; one clean miss alone is the compositor's; a pair, two
                ;; within pacer2-pair-ns, raises the hold a look over the
                ;; lead that failed, never past the margin over the hold it
                ;; was planned with (more lead failed by no cutoff: the
                ;; compositor held a refresh, or the GPU was slow); and a
                ;; miss after that, no frame in time between, raises it a
                ;; refresh, which owes a descent. A raise ends a descent in
                ;; course.
                [(or *pacer2-soft?* pair?)
                 (set! *pacer2-hold*
                   (if *pacer2-soft?*
                       (fx+ x r)
                       (fx+ (fxmin x (fx+ (pacer2-hold-of i)
                                          (pacer2-margin r)))
                            look)))
                 (when *pacer2-soft?*
                   (set! *pacer2-probed* (fx- now pacer2-descent-ns)))
                 (set! *pacer2-soft?* (not *pacer2-soft?*))
                 (set! *pacer2-proven* 0)
                 (set! *pacer2-probe* 0)
                 (if *pacer2-soft?* 4 5)]
                [else 2]))))))

  ;;; ---- the decision

  ;; Returns the grid's refresh at or after x: v a refresh, s its step.
  (define (pacer2-ceiling x v s) (fx- v (fx* s (fxdiv (fx- v x) s))))

  ;; Returns whether the screen takes the frames sent in order, one a
  ;; refresh: VSync's way.
  (define (pacer2-fifo?)
    (let ([mode (assq 'present-mode *gpu-facts*)])
      (and mode (eq? (cdr mode) 'vsync))))

  ;; Returns the refresh that the newest frame out takes, from row i on,
  ;; with S the newest reported: the chain. No frame out that the screen
  ;; has said nothing of a refresh past its aim takes a refresh before
  ;; gone (ns): while the screen takes frames in order, one it was silent on
  ;; didn't show there, and those behind it wait. A compositor that stalls
  ;; holds the next turn so, and its frame is drawn for the refresh it can
  ;; make; for eight refreshes past a frame's aim at most, as the gate
  ;; waits. A frame that missed only its own refresh shows at the next, its
  ;; stamp in by then: the frames behind it stay a refresh deep, and the
  ;; next turn's frame has that refresh to spare while the compositor's
  ;; cutoff moves.
  (define (pacer2-chain i n S v s need gone)
    (if (fx< i n)
        (pacer2-chain
         (fx+ i 1) n
         (if (fx= (pacer2-kind i) 0)
             (let ([aim (pacer2-own i 13)] [done (pacer2-seen i 6)])
               (fxmax (fx+ S s)
                      (if (fx> done 0) (pacer2-ceiling (fx+ done need) v s) aim)
                      (if (and (fx= (pacer2-seen i 10) 0)
                               (fx> gone (fx+ aim s)))
                          (pacer2-ceiling (fxmin gone (fx+ aim (fx* 8 s))) v s)
                          0)))
             S)
         v s need gone)
        S))

  ;; Returns how long the screen's word on a frame may take after its
  ;; showing, ns: the longest that a stamp of the rows lo to n took to
  ;; reach core0, and two looks; at least half a refresh s. A compositor
  ;; may send its words late, and at a rate it changes: GNOME over NVIDIA's
  ;; driver, 6 ms after the showing at 60 Hz in one run and 14 in the next.
  (define (pacer2-word-delay lo n s)
    (let loop ([i lo] [most (fxquotient s 2)])
      (if (fx< i n)
          (loop (fx+ i 1)
                (let ([stamp (pacer2-seen i 10)] [came (pacer2-seen i 12)])
                  (if (fx< 0 stamp came)
                      (fxmax most (fx+ (fx- came stamp) (fx* 2 core0-look-ns)))
                      most)))
          most)))

  ;; Returns whether row i is out, its GPU work not yet seen done.
  (define (pacer2-out? i)
    (and (fx>= i 0) (fx= (pacer2-kind i) 0) (fx= (pacer2-seen i 6) 0)))

  ;; Returns the newest row shown, from i down to lo, whose stamp is no more
  ;; than a refresh ahead of now; else -1.
  (define (pacer2-shown i lo now)
    (cond [(fx< i lo) -1]
          [(and (fx= (pacer2-kind i) 1)
                (fx<= (pacer2-seen i 3) (fx+ now (pacer2-refresh i))))
           i]
          [else (pacer2-shown (fx- i 1) lo now)]))

  ;; The question, at now. Returns #t when a turn may begin (its aim is in
  ;; *pacer2-aim*); else when to ask again (now-ns), or 0 for not until
  ;; something is wanted. The rows whose reports are in are judged first.
  ;; Asked again with nothing new, it answers the same: a begin is
  ;; pacer2-begin?'s to make. A turn that the other pacer began, or
  ;; another rate, starts it over first.
  (define (pacer2-decide! now)
    (unless (and (fx= (pacer-ticks) *pacer2-ticks*)
                 (eqv? (pacer-rate) *pacer2-rate*))
      (pacer2-forget!))
    (let* ([n *frame-ring-n*] [lo (fxmax 0 (fx- n 16))] [new (fx- n 1)]
           [p (pacer2-period)]
           [gate (fx+ (pacer2-own new 8) (fx* 8 p))])
      (let loop ([i (fxmax *pacer2-judged* lo)])
        (if (and (fx< i n) (not (fx= (pacer2-kind i) 0)))
            (begin
              (unless (fx= (pacer2-kind i) 3) (pacer2-judge! i lo now))
              (loop (fx+ i 1)))
            (set! *pacer2-judged* i)))
      (cond
        [(not (pacer-wanted?)) (set! *pacer2-waited* 0) 0]
        [(and (pacer2-out? new) (fx< now gate)) gate]
        [(and (pacer2-out? new) (gpu-frame-waiting?)) (fx+ now p)]
        [else (pacer2-plan! now n lo p)])))

  ;; Plans the turn: the grid from the newest row shown, or else the
  ;; pacer's own; the work and the lateness from the last eight rows; then
  ;; the chain, the aim and the begin. Returns #t, or when to ask again.
  (define (pacer2-plan! now n lo p)
    (let* ([reported (if (eq? (pacer-rate) 'screen)
                         (pacer2-shown (fx- n 1) lo now)
                         -1)]
           [v (cond [(fx>= reported 0) (pacer2-seen reported 3)]
                    [(fx= *pacer2-t* 0) now]
                    [else *pacer2-t*])]
           [s (if (fx>= reported 0)
                  (pacer2-refresh reported)
                  (fx- p (fxquotient p 512)))])
      (let loop ([i (fxmax lo (fx- n 8))] [most 0] [least 0] [last 0]
                 [late 0])
        (if (fx< i n)
            (let* ([done (pacer2-seen i 6)] [b (pacer2-own i 8)]
                   [plan (pacer2-own i 14)]
                   [work (if (fx> done 0)
                             (fx- (fx- done b)
                                  (fx+ (fx- (pacer2-seen i 7)
                                            (pacer2-own i 10))
                                       (fx- (pacer2-seen i 9)
                                            (pacer2-seen i 8))))
                             last)])
              (loop (fx+ i 1)
                    (fxmax most work)
                    (if (fx= least 0) work (fxmin least work))
                    work
                    (if (fx> plan 0) (fxmax late (fx- b plan)) late)))
            (let* ([look core0-look-ns]
                   [slack (fx+ late (fx* 2 look))]
                   [h (cond [(fx> *pacer2-proven* 0)
                             (if (fx= *pacer2-probe* 0)
                                 (pacer2-probe-hold)
                                 *pacer2-proven*)]
                            [(fx= *pacer2-hold* 0) p]
                            [else *pacer2-hold*])]
                   [need (fx- h slack)]
                   [F (fx+ s
                           (cond
                             ;; a refresh is gone once the screen's word on
                             ;; a frame shown there would be in, as long as
                             ;; its words take (at least half a refresh: a
                             ;; frame shown is on time within it)
                             [(fx>= reported 0)
                              (fxmax (pacer2-chain
                                      (fx+ reported 1) n v v s need
                                      (if (pacer2-fifo?)
                                          (fx- now (pacer2-word-delay lo n s))
                                          0))
                                     (pacer2-ceiling
                                      (fx- *pacer2-t* (fxquotient s 2)) v s))]
                             ;; with no reports, an acquire that the screen
                             ;; held leaves a slot out only with three
                             ;; frames in flight or more: with two it is the
                             ;; least depth the swapchain has
                             [(and (fx> n 0)
                                   (fx>= *gpu-frames-in-flight* 3)
                                   (fx> (fx- (pacer2-seen (fx- n 1) 9)
                                             (pacer2-seen (fx- n 1) 8))
                                        look))
                              (fx+ v s)]
                             [else v]))]
                   [A (fxmax F (pacer2-ceiling (fx+ now (fx+ least need)) v s))]
                   ;; the margin is the begin's alone: the chain and the aim
                   ;; ask where a frame can still make it, at the hold
                   [B (fx- (fx- A (fx+ h (pacer2-margin p)))
                           (fx+ most slack))])
              (cond
                ;; work over a refresh begins the next turn as the gate
                ;; opens: that turn, not the ones after it that draw nothing.
                ;; A grid that no report and no aim holds in place is drawn
                ;; from now, and a begin on it would move on with now, never
                ;; to come: such a turn begins at once.
                [(and (fx< now B) (fx< now F)
                      (or (fx>= reported 0) (fx> *pacer2-t* 0))
                      (or (fx< last s)
                          (fx> *pacer2-t* (pacer2-own (fx- n 1) 13))))
                 (set! *pacer2-waited* B)
                 B]
                [else
                 (set! *pacer2-aim* A)
                 #t]))))))

  ;;; ---- what the turn loop calls

  ;; Returns whether a turn may begin at now (ns), by the rule; the begin
  ;; is made here. t is the aim, the plan is the begin the loop slept to,
  ;; and while a descent is in course with no probe out, this turn's frame
  ;; is the probe.
  (define (pacer2-begin? now)
    (and (eq? (pacer2-decide! now) #t)
         (begin
           (set! *pacer2-t* (fxmax *pacer2-aim* *pacer2-t*))
           (set! *pacer2-plan* *pacer2-waited*)
           (when (and (fx> *pacer2-proven* 0) (fx= *pacer2-probe* 0))
             (set! *pacer2-probe* *pacer2-aim*))
           (set! *pacer2-waited* 0)
           (pacer-turn-begun! *pacer2-t* *pacer2-aim* *pacer2-plan*)
           (set! *pacer2-ticks* (pacer-ticks))
           (core0-trace! 22 *pacer2-plan*)
           (core0-trace! 16 *pacer2-aim*)
           (core0-trace! 17 *pacer2-t*)
           (core0-trace! 18 *pacer2-hold*)
           #t)))

  ;; Returns how long the loop may wait, in ns, or #f for until it is woken:
  ;; until the rule's time or the first timer's, and not at all while
  ;; processes are ready.
  (define (pacer2-wait-ns)
    (if (procs-ready?)
        0
        (let* ([now (now-ns)]
               [wake (pacer2-decide! now)]
               [ns (cond [(eq? wake #t) 0]
                         [(fx= wake 0) #f]
                         [else (fxmax 0 (fx- wake now))])])
          (if (pair? *timers*)
              (let ([due (max 0 (* 1000000
                                   (- (vector-ref (car *timers*) 0)
                                      (now-ms))))])
                (if ns (min ns due) due))
              ns))))

  ;; Returns how long processes may run, in whole ms: until the planned
  ;; begin, 10 at most; 1 while a turn is wanted and none is planned (its
  ;; frame is being made, or waits for the GPU); 10 with none wanted.
  (define (pacer2-procs-ms)
    (cond [(not (pacer-wanted?)) 10]
          [(fx> *pacer2-waited* 0)
           (fxmax 1 (fxmin 10 (fxquotient (fx- *pacer2-waited* (now-ns))
                                          1000000)))]
          [else 1]))

  ;; Returns the pacer's state by name, for inspect-pacer2 and the
  ;; Pipeline.
  (define (pacer2-state key)
    (case key
      [(t) *pacer2-t*]
      [(hold) *pacer2-hold*]
      [(proven) *pacer2-proven*]
      [(probe) *pacer2-probe*]
      [(probe-miss) *pacer2-probe-miss*]
      [(probed) *pacer2-probed*]
      [(soft?) *pacer2-soft?*]
      [(missed) *pacer2-missed*]
      [(aim) *pacer2-aim*]
      [(plan) *pacer2-plan*]
      [(judged) *pacer2-judged*]
      [(waited) *pacer2-waited*]
      [else #f])))
