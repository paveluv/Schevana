;;; present.ss — what became of each frame core0 presents, by the screen's
;;; own reports where the platform gives them (src/core0/platform.ss). For
;;; each frame: when core0 sent it; the refresh it showed at, by number, and
;;; when that refresh came, on now-ns's clock, with the refresh's length, or
;;; that the compositor dropped it; and when core0 first saw its GPU work
;;; done. Where the screen says nothing (X11, headless) only the GPU's
;;; times are kept.
;;;
;;; The reports are a ring by frame number that only core0 writes, and the
;;; world reads (core0-frame-report): a row is its frame's once it bears its
;;; number, written last, and what a report brings is in view once the
;;; row's kind says so, written after it.

(define present-rows 8192)
(define present-words 12)
;; A row: the frame's number; its kind (0 sent, 1 shown, 2 dropped); when
;; it was sent (now-ns); when the refresh it showed at came, by the
;; screen's clock (now-ns); the refresh (ns); that refresh's number; when
;; its GPU work was seen done (now-ns; 0, not yet); when core0 took it
;; from core1, and when its acquire of a swapchain image began and
;; returned, the submit's hold added (now-ns); the screen's own stamp of
;; its showing (now-ns; 0, none); and the last look that found its GPU
;; work not done yet (now-ns; 0, none): seen done tells only when core0
;; looked, which an acquire the screen holds puts off; this, that the work
;; was still going. With no window a frame has a row too, its GPU work
;; done as it goes back.
(defvar *present-ring* (make-fxvector (* present-rows present-words) 0))

;; When core0 took the frame it presents now from core1, when it asked for
;; an image for it and had one, and when it began to submit it.
(defvar *present-taken* 0)
(defvar *present-acquiring* 0)
(defvar *present-acquired* 0)
(defvar *present-submitting* 0)
(define (present-taken!) (set! *present-taken* (now-ns)))
(define (present-acquiring!) (set! *present-acquiring* (now-ns)))
(define (present-acquired!) (set! *present-acquired* (now-ns)))
(define (present-submitting!) (set! *present-submitting* (now-ns)))

(define (present-at frame) (fx* present-words (fxmodulo frame present-rows)))

;; Word k of frame's row, or #f once the row is another frame's.
(define (core0-frame-report frame k)
  (let ([at (present-at frame)])
    (and (fx= (fxvector-ref *present-ring* at) frame)
         (begin (memory-order-acquire)
                (fxvector-ref *present-ring* (fx+ at k))))))

;; The newest frame sent to the screen.
(defvar *present-newest* 0)

;; Frame's row begun, as core0 sends it: the screen asked to report on it.
(define (present-sent! frame)
  (set! *present-newest* frame)
  (let ([r *present-ring*] [at (present-at frame)])
    (fxvector-set! r (fx+ at 1) 0)
    (fxvector-set! r (fx+ at 2) (now-ns))
    (do ([k 3 (fx+ k 1)]) ((fx= k 7))
      (fxvector-set! r (fx+ at k) 0))
    (fxvector-set! r (fx+ at 7) *present-taken*)
    (fxvector-set! r (fx+ at 8) *present-acquiring*)
    (fxvector-set! r (fx+ at 9) *present-acquired*)
    (fxvector-set! r (fx+ at 10) 0)
    (fxvector-set! r (fx+ at 11) 0)
    (memory-order-release)
    (fxvector-set! r at frame))
  (platform-report-ask! frame))

;; Frame submitted: a screen may hold core0 in the submit in the acquire's
;; place, so a submit that took over a look is the screen's as the
;; acquire's is, and the row's acquire returns that much later. One
;; shorter is the submit's own work (Mesa on Intel: 58 µs at the median,
;; most over a tenth of a look). Core1 reads it once the frame is given
;; back, after this.
(define (present-submitted! frame)
  (let ([at (present-at frame)] [took (fx- (now-ns) *present-submitting*)])
    (when (and (fx> took core0-look-ns)
               (fx= (fxvector-ref *present-ring* at) frame))
      (fxvector-set! *present-ring* (fx+ at 9) (fx+ *present-acquired* took)))))

;; The screen's word on frame: dropped (kind 2), or shown (1) at stamp
;; (now-ns), at a refresh it keeps steady (refresh, its length by the
;; screen's word, over 0, which is not read: present-length) or not (0).
(define (present-reported! frame kind stamp refresh)
  (let ([at (present-at frame)])
    (when (fx= (fxvector-ref *present-ring* at) frame)
      (if (fx= kind 1)
          (present-shown! frame at stamp (fx> refresh 0))
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
;;; held till one agrees with it, and its stamp moves the clock not at all:
;;; one that ran late reads as a refresh on, and taken, would leave the
;;; clock early. The display's own count of its refreshes is read nowhere:
;;; a compositor may send none (KWin), or count frames where the driver
;;; counts nothing (Mutter over NVIDIA's). Nor is a report's own word on
;;; the refresh's length, but whether there is a steady one: the display's
;;; mode says how long it is. Where there's none (a Mac's, a variable one)
;;; each stamp is taken as it is: a Mac's are the display's own, and the
;;; clock there held a report after a refresh missed 9 ms where it comes in
;;; 1 (docs/PLATFORMS.md).

;; The newest refresh a report placed, by number, and when it came by the
;; screen's clock (now-ns; 0, none yet); the reports that came later than
;; the clock since one agreed with it, and the least by how much.
(defvar *present-refresh* 0)
(defvar *present-refresh-at* 0)
(defvar *present-late-run* 0)
(defvar *present-late-least* 0)
;; The refresh the newest frame published as shown showed at; when the
;; newest frame reported shown was sent; and the frames held for a report
;; that agrees with theirs, the oldest and the newest (-1, none).
(defvar *present-shown* 0)
(defvar *present-sent* 0)
(defvar *present-held* -1)
(defvar *present-held-last* -1)

;; The refresh's length a person says in place of the display mode's (ns);
;; or 0, the mode's.
(defvar *present-refresh-said* 0)

;; The refresh's length stamps are read by, ns: what a person said, else
;; the display mode's; 0 where neither says, and each stamp is then taken
;; as it is, to the nearest of core0's guess.
(define (present-length)
  (let ([d (core0-display)])
    (cond
      [(fx> *present-refresh-said* 0) *present-refresh-said*]
      [(and d (fx> (caddr d) 0) (fx> (cadddr d) 0)) (core0-frame-ns)]
      [else 0])))

;; Whether ns may be said: 0, or a refresh from 1 to 100 ms long.
(define (present-refresh-ok? ns)
  (and (fixnum? ns) (or (fx= ns 0) (fx<= 1000000 ns 100000000))))

;; A job: the screen's refreshes taken as ns long from the next report on,
;; or by the display mode's again (0). => #f for a length refused
(define (core0-refresh-ns! ns)
  (and (present-refresh-ok? ns)
       (begin (core0-post! (list 'present-refresh-say! ns)) #t)))
(define (present-refresh-say! ns)
  (when (present-refresh-ok? ns) (set! *present-refresh-said* ns)))

;; Frame, its row at at, showed, by its stamp (present-reported!): the
;; refresh it showed at, published at once; or held, where the screen
;; keeps a clock and the report says a refresh was missed in a flow of
;; frames, each sent within a refresh and a half of the one before, at the
;; refresh the clock puts it at. In a flow a stamp is read as late, by up
;; to three quarters of a refresh, and hardly early; after a pause, or with
;; no clock, as the nearest refresh, which the clock then takes from it.
;; Steady?: the screen says it keeps a steady refresh.
(define (present-shown! frame at stamp steady?)
  (let* ([r *present-ring*]
         [len (present-length)]
         [p (if (fx> len 0) len (core0-frame-ns))]
         [sent (fxvector-ref r (fx+ at 2))]
         ;; a clock to read the stamp against: kept, and a flow
         [clock? (and steady? (fx> len 0) (fx> *present-refresh-at* 0)
                      (fx< (fx* 2 (fx- sent *present-sent*)) (fx* 3 p)))]
         [n (fxdiv (fx+ (fx- stamp *present-refresh-at*)
                        (fxquotient p (if clock? 4 2)))
                   p)]
         [count (fx+ *present-refresh* n)])
    (fxvector-set! r (fx+ at 4) p)
    (fxvector-set! r (fx+ at 10) stamp)
    (fxvector-set! r (fx+ at 5) count)
    (cond
      [(fx< n 0)
       ;; shown before the newest: reported out of order
       (fxvector-set! r (fx+ at 3) stamp)
       (present-publish! at 1)]
      [else
       (set! *present-sent* sent)
       (when (fx>= *present-held* 0) (present-held-settle! count p))
       (cond
         [(and clock? (fx< *present-held* 0)
               (fx> count (fx+ *present-shown* 1)))
          ;; held at the clock's time for it, the clock as it was
          (fxvector-set! r (fx+ at 3) (fx+ *present-refresh-at* (fx* n p)))
          (set! *present-held* frame)
          (set! *present-held-last* frame)]
         [else
          (present-clock! stamp (fx* n p) clock?)
          (set! *present-refresh* count)
          (fxvector-set! r (fx+ at 3) *present-refresh-at*)
          (cond
            [(fx>= *present-held* 0) (set! *present-held-last* frame)]
            [else
             ;; no two frames at one refresh: one whose stamp says so is
             ;; numbered on from the newest shown. No stamp comes before
             ;; its refresh, so the clock was late (set by a stamp that ran
             ;; late, the first or one after a pause), and takes this one
             (when (fx<= *present-refresh* *present-shown*)
               (set! *present-refresh* (fx+ *present-shown* 1))
               (set! *present-refresh-at* stamp)
               (set! *present-late-run* 0)
               (fxvector-set! r (fx+ at 3) stamp)
               (fxvector-set! r (fx+ at 5) *present-refresh*))
             (set! *present-shown* *present-refresh*)
             (present-publish! at 1)])])])))

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

;; The frames held are published as they stand, the oldest first, each at
;; its stamp where that's earlier than the clock's time for it: no stamp
;; comes before its refresh, so the clock was late.
(define (present-held-publish!)
  (do ([f *present-held* (fx+ f 1)]) ((fx> f *present-held-last*))
    (when (present-held? f)
      (let ([r *present-ring*] [at (present-at f)])
        (fxvector-set! r (fx+ at 3) (fxmin (fxvector-ref r (fx+ at 3))
                                           (fxvector-ref r (fx+ at 10))))
        (set! *present-shown* (fxvector-ref r (fx+ at 5)))
        (present-publish! at 1))))
  (set! *present-held* -1)
  (set! *present-held-last* -1))

;; The frames held, as a report places refresh newest. After theirs, it
;; agrees with them; or it leaves them no room after the newest shown, its
;; stamp early: they showed when they said. Else their stamps ran late:
;; each showed a refresh before the next, a refresh p ns, and once the
;; oldest is back in step with the newest shown, they're settled.
(define (present-held-settle! newest p)
  (let ([r *present-ring*])
    (if (or (fx> newest
                 (fxvector-ref r (fx+ (present-at *present-held-last*) 5)))
            (fx<= (fx- newest *present-shown* 1)
                  (fx- *present-held-last* *present-held*)))
        (present-held-publish!)
        (let back ([f *present-held-last*] [next newest])
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
(defvar *present-fences* (make-vector present-fence-slots 0))
(defvar *present-fence-frames* (make-fxvector present-fence-slots 0))

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

;; Whether core0 awaits something of a frame at now, and so looks
;; (core0-sleep!): a fence not seen signaled yet; or, where the screen
;; reports, the newest frame's report, for a second after its send. Core0's
;; own queue brings the reports, and SDL's wait for events doesn't end for
;; them; one that never comes keeps core0 looking a second at most.
(define (present-awaiting? now)
  (or (let loop ([i 0])
        (and (fx< i present-fence-slots)
             (or (not (eqv? (vector-ref *present-fences* i) 0))
                 (loop (fx+ i 1)))))
      (let* ([r *present-ring*] [at (present-at *present-newest*)]
             [sent (fxvector-ref r (fx+ at 2))])
        (and (platform-reports?)
             (fx= (fxvector-ref r at) *present-newest*)
             (fx= (fxvector-ref r (fx+ at 1)) 0)
             (fx< 0 sent)
             (fx< now (fx+ sent 1000000000))))))

;; Frame's GPU work seen done, now: with no window, as it goes back. The
;; world is woken: its pacer waits for this before its next turn.
(define (present-done! frame)
  (let ([at (present-at frame)])
    (when (fx= (fxvector-ref *present-ring* at) frame)
      (fxvector-set! *present-ring* (fx+ at 6) (now-ns))))
  (core0-world-wake!))

;; The fences signaled since the last look: their frames' GPU times, and
;; the world woken for them (present-done!). And the reports held too long
;; (present-held-poll!).
(define (present-poll!)
  (present-held-poll! (now-ns))
  (when *renderer*
    (let ([dev (renderer-device *renderer*)] [fs *present-fences*])
      (do ([i 0 (fx+ i 1)]) ((fx= i present-fence-slots))
        (let ([fence (vector-ref fs i)])
          (unless (eqv? fence 0)
            (let ([frame (fxvector-ref *present-fence-frames* i)])
              (cond
                [(sdl-query-gpu-fence dev fence)
                 (present-done! frame)
                 (core0-trace! 12 frame)
                 (sdl-release-gpu-fence dev fence)
                 (vector-set! fs i 0)]
                [else
                 (let ([at (present-at frame)])
                   (when (fx= (fxvector-ref *present-ring* at) frame)
                     (fxvector-set! *present-ring* (fx+ at 11)
                                    (now-ns))))]))))))))
