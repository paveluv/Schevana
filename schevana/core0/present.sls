;;; (schevana core0 present) — what became of each frame core0 presents, by the
;;; screen's own reports where the platform gives them ((schevana core0
;;; platform)). For each frame: when core0 sent it; the refresh it showed at,
;;; by number, and when that refresh came, on core0-now-ns's clock, with the
;;; refresh's length, or that the compositor dropped it; and when core0 first
;;; saw its GPU work done. Where the screen says nothing (X11, headless) only
;;; the GPU's times are kept.
;;;
;;; The reports are a ring by frame number that only core0 writes, and the
;;; world reads (core0-frame-report): a row is its frame's once it bears its
;;; number, written last, and what a report brings is in view once the
;;; row's kind says so, written after it.

(library (schevana core0 present)
  (export
    present-rows present-words *present-ring* *present-taken* present-taken!
    present-acquiring! present-acquired! present-at core0-frame-report
    present-sent! present-reported! present-publish! *present-refresh*
    *present-refresh-at* *present-late-run* *present-late-least*
    *present-shown* *present-sent* *present-held* *present-held-last*
    *present-refresh-said* core0-refresh-ns! present-refresh-say!
    present-held-poll! present-fence! present-poll!)
  (import (chezscheme)
          (schevana base)
          (schevana sdl)
          (schevana core0 mail)
          (schevana core0 trace)
          (schevana core0 renderer))

  (library-layer core0)

  (define present-rows 8192)
  (define present-words 12)
  ;; A row: the frame's number; its kind (0 sent, 1 shown, 2 dropped); when it
  ;; was sent (core0-now-ns); when the refresh it showed at came, by the
  ;; screen's clock (core0-now-ns); the refresh (ns); that refresh's number;
  ;; when its GPU work was seen done (core0-now-ns; 0, not yet); when core0 took
  ;; it from core1, and when its acquire of a swapchain image began and returned
  ;; (core0-now-ns); the screen's own stamp of its showing (core0-now-ns; 0,
  ;; none); and the last look that found its GPU work not done yet
  ;; (core0-now-ns; 0, none): seen done tells only when core0 looked, which an
  ;; acquire the screen holds puts off; this, that the work was still going.
  (define-state *present-ring* (make-fxvector (* present-rows present-words) 0))

  ;; When core0 took the frame it presents now from core1, and when it asked
  ;; for an image for it and had one.
  (define-state *present-taken* 0)
  (define-state *present-acquiring* 0)
  (define-state *present-acquired* 0)
  (define (present-taken!) (set! *present-taken* (core0-now-ns)))
  (define (present-acquiring!) (set! *present-acquiring* (core0-now-ns)))
  (define (present-acquired!) (set! *present-acquired* (core0-now-ns)))

  (define (present-at frame) (fx* present-words (fxmodulo frame present-rows)))

  ;; Word k of frame's row, or #f once the row is another frame's.
  (define (core0-frame-report frame k)
    (let ([at (present-at frame)])
      (and (fx= (fxvector-ref *present-ring* at) frame)
           (begin (memory-order-acquire)
                  (fxvector-ref *present-ring* (fx+ at k))))))

  ;; Frame's row begun, as core0 sends it; who sends it asks the screen to
  ;; report on it (platform-report-ask!, (schevana core0 platform)).
  (define (present-sent! frame)
    (let ([r *present-ring*] [at (present-at frame)])
      (fxvector-set! r (fx+ at 1) 0)
      (fxvector-set! r (fx+ at 2) (core0-now-ns))
      (do ([k 3 (fx+ k 1)]) ((fx= k 7))
        (fxvector-set! r (fx+ at k) 0))
      (fxvector-set! r (fx+ at 7) *present-taken*)
      (fxvector-set! r (fx+ at 8) *present-acquiring*)
      (fxvector-set! r (fx+ at 9) *present-acquired*)
      (fxvector-set! r (fx+ at 10) 0)
      (fxvector-set! r (fx+ at 11) 0)
      (memory-order-release)
      (fxvector-set! r at frame)))

  ;; The screen's word on frame: dropped (kind 2), or shown (1) at stamp
  ;; (core0-now-ns), a refresh refresh ns long by the screen's word (0, none: it
  ;; keeps no steady refresh, or doesn't say).
  (define (present-reported! frame kind stamp refresh)
    (let ([at (present-at frame)])
      (when (fx= (fxvector-ref *present-ring* at) frame)
        (if (fx= kind 1)
            (present-shown! frame at stamp refresh)
            (present-publish! at kind)))))

  ;; The row at at in view, its kind: what its report brought is written.
  (define (present-publish! at kind)
    (memory-order-release)
    (fxvector-set! *present-ring* (fx+ at 1) kind))

  ;;; ---- the screen's clock
  ;;; A screen that refreshes steadily is a clock, and a report's stamp is
  ;;; that clock read late: by nothing where the display stamps its own
  ;;; refresh, by a kernel thread's turn where a driver stamps the flip's
  ;;; event as it sends it (NVIDIA's with no vblank support). So the clock is
  ;;; inferred from the stamps alone: a refresh comes its period after the
  ;;; one before; a stamp earlier than that moves the clock at once, a later
  ;;; one only as far as the clock may have drifted, a 4096th, and eight
  ;;; later in a row by the least of them. That holds while frames flow: a
  ;;; display may stop its timing when nothing new comes (a laptop's panel,
  ;;; some ten refreshes on) and start it anew with the next frame, off the
  ;;; old beat, so after a pause the clock is the stamp, as it is. A report
  ;;; then says the refresh its frame showed at, by number, and when that
  ;;; refresh came by the clock. A stamp may run a whole refresh late, which
  ;;; only the next frame's report can tell: a frame shows at a later refresh
  ;;; than the one before it. So a report that says a refresh was missed is
  ;;; held till one agrees with it. The display's own count of its refreshes
  ;;; is read nowhere: a compositor may send none (KWin), or count frames
  ;;; where the driver counts nothing (Mutter over NVIDIA's).

  ;; The newest refresh a report placed, by number, and when it came by the
  ;; screen's clock (core0-now-ns; 0, none yet); the reports that came later
  ;; than the clock since one agreed with it, and the least by how much.
  (define-state *present-refresh* 0)
  (define-state *present-refresh-at* 0)
  (define-state *present-late-run* 0)
  (define-state *present-late-least* 0)
  ;; The refresh the newest frame published as shown showed at; when the
  ;; newest frame reported shown was sent; and the frames held for a report
  ;; that agrees with theirs, the oldest and the newest (-1, none).
  (define-state *present-shown* 0)
  (define-state *present-sent* 0)
  (define-state *present-held* -1)
  (define-state *present-held-last* -1)

  ;; The refresh's length a person says in place of the screen's own (ns),
  ;; where the screen says one; or 0, the screen's word.
  (define-state *present-refresh-said* 0)

  ;; Whether ns may be said: 0, or a refresh from 1 to 100 ms long.
  (define (present-refresh-ok? ns)
    (and (fixnum? ns) (or (fx= ns 0) (fx<= 1000000 ns 100000000))))

  ;; A job: the screen's refreshes taken as ns long from the next report on,
  ;; or by the screen's own word again (0). => #f for a length refused
  (define (core0-refresh-ns! ns)
    (and (present-refresh-ok? ns)
         (begin (core0-post! (list present-refresh-say! ns)) #t)))
  (define (present-refresh-say! ns)
    (when (present-refresh-ok? ns) (set! *present-refresh-said* ns)))

  ;; Frame, its row at at, showed, by its stamp and the screen's refresh
  ;; (present-reported!): the refresh it showed at, published at once; or
  ;; held, where the screen keeps a clock and the report says a refresh was
  ;; missed in a flow of frames, each sent within a refresh and a half of the
  ;; one before. In a flow a stamp is read as late, by up to three quarters
  ;; of a refresh, and hardly early; after a pause, or with no clock, as the
  ;; nearest refresh, which the clock then takes from it.
  (define (present-shown! frame at stamp refresh)
    (let* ([r *present-ring*]
           [refresh (if (and (fx> refresh 0) (fx> *present-refresh-said* 0))
                        *present-refresh-said*
                        refresh)]
           [p (if (fx> refresh 0) refresh (core0-frame-ns))]
           [sent (fxvector-ref r (fx+ at 2))]
           ;; a clock to read the stamp against: kept, and a flow
           [clock? (and (fx> refresh 0) (fx> *present-refresh-at* 0)
                        (fx< (fx* 2 (fx- sent *present-sent*)) (fx* 3 p)))]
           [n (fxdiv (fx+ (fx- stamp *present-refresh-at*)
                          (fxquotient p (if clock? 4 2)))
                     p)])
      (fxvector-set! r (fx+ at 4) p)
      (fxvector-set! r (fx+ at 10) stamp)
      (cond
        [(fx< n 0)
         ;; shown before the newest: reported out of order
         (fxvector-set! r (fx+ at 3) stamp)
         (fxvector-set! r (fx+ at 5) (fx+ *present-refresh* n))
         (present-publish! at 1)]
        [else
         (set! *present-sent* sent)
         (present-clock! stamp (fx* n p) clock?)
         (set! *present-refresh* (fx+ *present-refresh* n))
         (fxvector-set! r (fx+ at 3) *present-refresh-at*)
         (fxvector-set! r (fx+ at 5) *present-refresh*)
         (when (fx>= *present-held* 0) (present-held-settle! p))
         (cond
           [(fx>= *present-held* 0) (set! *present-held-last* frame)]
           [(and clock? (fx> *present-refresh* (fx+ *present-shown* 1)))
            (set! *present-held* frame)
            (set! *present-held-last* frame)]
           [else
            ;; no two frames at one refresh: one whose stamp says so is
            ;; numbered on from the newest shown. No stamp comes before its
            ;; refresh, so the clock was late (set by a stamp that ran late,
            ;; the first or one after a pause), and takes this one
            (when (fx<= *present-refresh* *present-shown*)
              (set! *present-refresh* (fx+ *present-shown* 1))
              (set! *present-refresh-at* stamp)
              (set! *present-late-run* 0)
              (fxvector-set! r (fx+ at 3) stamp)
              (fxvector-set! r (fx+ at 5) *present-refresh*))
            (set! *present-shown* *present-refresh*)
            (present-publish! at 1)])])))

  ;; The screen's clock moved on to the refresh a report places, since ns
  ;; after the newest by the clock: when its stamp says, unless, in a flow
  ;; (clock?), that's later than the clock may have drifted.
  (define (present-clock! stamp since clock?)
    (let ([latest (fx+ *present-refresh-at* since (fxquotient since 4096))])
      (set! *present-refresh-at*
        (cond
          [(and clock? (fx> stamp latest))
           (set! *present-late-least*
             (if (fx= *present-late-run* 0)
                 (fx- stamp latest)
                 (fxmin (fx- stamp latest) *present-late-least*)))
           (set! *present-late-run* (fx+ *present-late-run* 1))
           (cond [(fx= *present-late-run* 8)
                  (set! *present-late-run* 0)
                  (fx+ latest *present-late-least*)]
                 [else latest])]
          [else (set! *present-late-run* 0) stamp]))))

  ;; Whether frame's report is held: its stamp in, its kind not yet.
  (define (present-held? frame)
    (let ([at (present-at frame)])
      (and (fx= (fxvector-ref *present-ring* at) frame)
           (fx= (fxvector-ref *present-ring* (fx+ at 1)) 0)
           (fx> (fxvector-ref *present-ring* (fx+ at 10)) 0))))

  ;; The frames held are published as they stand, the oldest first.
  (define (present-held-publish!)
    (do ([f *present-held* (fx+ f 1)]) ((fx> f *present-held-last*))
      (when (present-held? f)
        (set! *present-shown*
          (fxvector-ref *present-ring* (fx+ (present-at f) 5)))
        (present-publish! (present-at f) 1)))
    (set! *present-held* -1)
    (set! *present-held-last* -1))

  ;; The frames held, as a report places a refresh, the newest. After
  ;; theirs, it agrees with them; or it leaves them no room after the newest
  ;; shown, its stamp early: they showed when they said. Else their stamps
  ;; ran late: each showed a refresh before the next, a refresh p ns, and
  ;; once the oldest is back in step with the newest shown, they're settled.
  (define (present-held-settle! p)
    (let ([r *present-ring*])
      (if (or (fx> *present-refresh*
                   (fxvector-ref r (fx+ (present-at *present-held-last*) 5)))
              (fx<= (fx- *present-refresh* *present-shown* 1)
                    (fx- *present-held-last* *present-held*)))
          (present-held-publish!)
          (let back ([f *present-held-last*] [next *present-refresh*])
            (cond
              [(fx< f *present-held*)
               (when (fx= next (fx+ *present-shown* 1))
                 (present-held-publish!))]
              [(present-held? f)
               (let* ([at (present-at f)]
                      [was (fxvector-ref r (fx+ at 5))]
                      [to (fxmin was (fx- next 1))])
                 (fxvector-set! r (fx+ at 5) to)
                 (fxvector-set! r (fx+ at 3)
                                (fx- (fxvector-ref r (fx+ at 3))
                                     (fx* (fx- was to) p)))
                 (back (fx- f 1) to))]
              [else (back (fx- f 1) next)])))))

  ;; Frames held three refreshes, at now, with no report after them are
  ;; published as they stand.
  (define (present-held-poll! now)
    (when (fx>= *present-held* 0)
      (let ([at (present-at *present-held-last*)])
        (when (fx> now (fx+ (fxvector-ref *present-ring* (fx+ at 10))
                            (fx* 3 (fxvector-ref *present-ring* (fx+ at 4)))))
          (present-held-publish!)))))

  ;;; ---- the GPU's times
  ;;; Each frame's fence, kept till core0 sees it signaled at a step of its
  ;;; own: when, to the step, its GPU work was done; and each look before
  ;;; that, the last time it was still going.

  (define present-fence-slots 4)
  (define-state *present-fences* (make-vector present-fence-slots 0))
  (define-state *present-fence-frames* (make-fxvector present-fence-slots 0))

  ;; Frame's fence, to look at: a free slot, else the oldest given up.
  (define (present-fence! frame fence)
    (let ([dev (renderer-device *renderer*)] [fs *present-fences*])
      (let loop ([i 0] [oldest 0])
        (cond
          [(fx= i present-fence-slots)
           (sdl-release-gpu-fence dev (vector-ref fs oldest))
           (vector-set! fs oldest fence)
           (fxvector-set! *present-fence-frames* oldest frame)]
          [(eqv? (vector-ref fs i) 0)
           (vector-set! fs i fence)
           (fxvector-set! *present-fence-frames* i frame)]
          [else
           (loop (fx+ i 1)
                 (if (fx< (fxvector-ref *present-fence-frames* i)
                          (fxvector-ref *present-fence-frames* oldest))
                     i
                     oldest))]))))

  ;; The fences signaled since the last look: their frames' GPU times. And
  ;; the reports held too long (present-held-poll!).
  (define (present-poll!)
    (present-held-poll! (core0-now-ns))
    (when *renderer*
      (let ([dev (renderer-device *renderer*)] [fs *present-fences*])
        (do ([i 0 (fx+ i 1)]) ((fx= i present-fence-slots))
          (let ([fence (vector-ref fs i)])
            (unless (eqv? fence 0)
              (let* ([frame (fxvector-ref *present-fence-frames* i)]
                     [at (present-at frame)]
                     [done? (sdl-query-gpu-fence dev fence)])
                (when (fx= (fxvector-ref *present-ring* at) frame)
                  (fxvector-set! *present-ring* (fx+ at (if done? 6 11))
                                 (core0-now-ns)))
                (when done?
                  (core0-trace! 12 frame)
                  (sdl-release-gpu-fence dev fence)
                  (vector-set! fs i 0))))))))))
