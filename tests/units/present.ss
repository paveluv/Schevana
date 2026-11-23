;;; tests/units/present.ss — what the screen says about each frame: its
;;; reports ((schevana core0 present)), joined to the frames drawn and the
;;; input they show ((schevana kits inspect)). Headless, nothing reports, so
;;; the test writes the reports as the screen's callbacks would.

;; Returns how frame i's GPU work went: 'late when the frame came late and
;; its work was seen done only after the refresh it missed; 'done when it
;; was otherwise seen done; #f when it was not seen done.
(define (present-test-frame-gpu i)
  (let ([done (inspect-frame-report i 6)])
    (and done (> done 0)
         (if (and (eq? (inspect-frame-screen i) 'late)
                  (> done (+ (inspect-frame-report (- i 1) 3)
                             (inspect-frame-report i 4))))
             'late
             'done))))

;; Begins frame n's row as core0 does when it sends the frame at sent, with
;; no word from the screen yet.
(define (present-test-sent! n sent)
  (let ([at (present-at n)])
    (do ([k 1 (+ k 1)]) ((= k present-words))
      (fxvector-set! *present-ring* (+ at k) 0))
    (fxvector-set! *present-ring* (+ at 2) sent)
    (fxvector-set! *present-ring* at n)))

;; Takes the screen's word on frame n: kind (1 shown, 2 dropped), stamp,
;; and the refresh's length it says (0 for no steady refresh), on a display
;; whose mode says p ns (headless, with no mode, p is given in its place).
(define (present-test-reported! n kind stamp p refresh)
  (fluid-let ([*present-refresh-said* p])
    (present-reported! n kind stamp refresh)))

;; Writes the report of frame i (an index of the frames drawn), as core0
;; begins it at sent and the screen fills it in: kind (1 shown, 2 dropped),
;; the screen's stamp, and when the GPU was done.
(define (present-test-report! i sent kind stamp done)
  (let ([n (inspect-frame-ref i 6)])
    (present-test-sent! n sent)
    (fxvector-set! *present-ring* (+ (present-at n) 6) done)
    (present-test-reported! n kind stamp (core0-frame-ns) (core0-frame-ns))))

;; Runs thunk with the screen's clock as it is at boot: no refresh placed,
;; and no report held.
(define (present-test-fresh thunk)
  (fluid-let ([*present-refresh* 0] [*present-refresh-at* 0]
              [*present-late-run* 0] [*present-late-least* 0]
              [*present-shown* 0] [*present-sent* 0]
              [*present-held* -1] [*present-held-last* -1])
    (thunk)))

;; Draws four frames, the second showing input that came at
;; present-test-in; present-test-first is the first one's index.
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

(let* ([p (core0-frame-ns)]
       [t (+ (now-ns) (* 10 p))]
       [i present-test-first])
  ;; sent a refresh apart and shown 3 refreshes later; the third is a
  ;; refresh late (its GPU was done only after the refresh it missed), and
  ;; the fourth is dropped
  (present-test-fresh
   (lambda ()
     (present-test-report! i t 1 (+ t (* 3 p)) (+ t 1000000))
     (present-test-report! (+ i 1) (+ t p) 1 (+ t (* 4 p)) (+ t p 1000000))
     (present-test-report! (+ i 2) (+ t (* 2 p)) 1 (+ t (* 6 p))
                           (+ t (* 5 p) 1000000))
     (present-test-report! (+ i 3) (+ t (* 3 p)) 2 0 0)
     (let ([held (inspect-frame-screen (+ i 2))])
       ;; no report follows, so three refreshes later the late one stands
       (present-held-poll! (+ t (* 9 p)))
       (present-held-poll! (+ t (* 9 p) 1))
       (check "a report that says a refresh was missed says nothing till \
               the next frame's agrees, or three refreshes pass with none"
              (and (not held) (eq? (inspect-frame-screen (+ i 2)) 'late))))))
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
         (and (eq? (present-test-frame-gpu (+ i 1)) 'done)
              (eq? (present-test-frame-gpu (+ i 2)) 'late)
              (not (present-test-frame-gpu (+ i 3)))))
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
         (not (core0-frame-report (+ n present-rows) 1))))

;;; The screen's clock, inferred from the reports' stamps alone
;;; ((schevana core0 present)): frames with numbers that no frame drawn has,
;;; each sent and reported as the screen's callbacks would.

;; Sends frames from first on and reports each shown, in turn. Each is
;; (sent stamp) or (sent stamp refresh); the refresh is p ns long as the
;; display's mode says, and the screen's word on it is p unless a frame
;; gives its own.
(define (present-test-shown! first p frames)
  (for-each (lambda (f k)
              (present-test-sent! (+ first k) (car f))
              (present-test-reported! (+ first k) 1 (cadr f) p
                                      (if (pair? (cddr f)) (caddr f) p)))
            frames (iota (length frames))))

;; Sends and reports a flow of frames from first on: frame k is sent at t
;; plus k refreshes less two (two before its own), and stamped late ns
;; after refresh at, where (at late) is the kth pair of lates.
(define (present-test-flow first p t lates)
  (present-test-shown!
   first p
   (map (lambda (l)
          (list (+ t (* (- (car l) 2) p)) (+ t (* (cadr l) p) (caddr l))))
        (map (lambda (l k) (cons k l)) lates (iota (length lates))))))

(define (present-test-word n k) (core0-frame-report n k))
(define (present-test-step n) (- (present-test-word n 5)
                                 (present-test-word (- n 1) 5)))

(check "refreshes are counted from the reports' times, whatever the \
        display's own count says: issue 9's three frames, a second apart \
        at 30 Hz, show 30 and 31 refreshes apart, each in view at once"
       (present-test-fresh
        (lambda ()
          (let ([f 2000001])
            (present-test-shown! f 33354900
                                 '((256136000000 256199000000)
                                   (257137000000 257200000000)
                                   (258135000000 258233000000)))
            (and (= 30 (present-test-step (+ f 1)))
                 (= 31 (present-test-step (+ f 2)))
                 (eqv? 1 (present-test-word (+ f 2) 1))
                 (= 33354900 (present-test-word (+ f 2) 4)))))))

(check "a stamp that runs late in a flow is still its refresh's: the frame \
        showed a refresh after the one before, when the screen's clock \
        says, to the 4096th it may have drifted, and its stamp is kept; \
        the pacer reads the clock's time"
       (present-test-fresh
        (lambda ()
          (let* ([p (core0-frame-ns)] [t (* 1000 p)] [f 2000011])
            (present-test-flow f p t '((0 0) (1 0) (2 5000000) (3 0)))
            (and (= 1 (present-test-step (+ f 2)))
                 (= 1 (present-test-step (+ f 3)))
                 (<= 0 (- (present-test-word (+ f 2) 3) (+ t (* 2 p)))
                     (quotient p 4096))
                 (= (present-test-word (+ f 2) 10) (+ t (* 2 p) 5000000))
                 (= (present-test-word (+ f 3) 3) (+ t (* 3 p)))
                 (= (pacer-refresh-seen (+ f 2))
                    (present-test-word (+ f 2) 3)))))))

(check "a stamp that runs more than a refresh late reads as a refresh \
        missed, so its report is held; the next frame's, which leaves it \
        no room, settles it: a refresh before, and none missed"
       (present-test-fresh
        (lambda ()
          (let* ([p (core0-frame-ns)] [t (* 1000 p)] [f 2000021]
                 [late (quotient (* 13 p) 10)])
            (present-test-flow f p t `((0 0) (1 0) (2 ,late)))
            (let ([held? (and (eqv? 0 (present-test-word (+ f 2) 1))
                              (= *present-held* (+ f 2)))])
              ;; a kernel thread sends them in order, so the next stamp
              ;; comes right after the late one
              (present-test-flow (+ f 3) p t `((2 ,(+ late 2000))))
              (and held?
                   (eqv? 1 (present-test-word (+ f 2) 1))
                   (eqv? 1 (present-test-word (+ f 3) 1))
                   (= 1 (present-test-step (+ f 2)))
                   (= 1 (present-test-step (+ f 3)))
                   (<= 0 (- (present-test-word (+ f 2) 3) (+ t (* 2 p)))
                       (quotient p 1024))
                   (= *present-held* -1)))))))

(check "a frame that did miss a refresh is held too, and shown as it said \
        once the next frame's report agrees: a refresh after it"
       (present-test-fresh
        (lambda ()
          (let* ([p (core0-frame-ns)] [t (* 1000 p)] [f 2000031])
            (present-test-flow f p t '((0 0) (1 0) (3 0)))
            (let ([held? (eqv? 0 (present-test-word (+ f 2) 1))])
              (present-test-flow (+ f 3) p t '((4 0)))
              (and held?
                   (= 2 (present-test-step (+ f 2)))
                   (= 1 (present-test-step (+ f 3)))
                   (= (present-test-word (+ f 2) 3) (+ t (* 3 p)))))))))

(check "two stamps in a row that ran late, as a thread that stalled sends \
        them, are both held, and both settled by the frame after: each \
        showed a refresh before the next"
       (present-test-fresh
        (lambda ()
          (let* ([p (core0-frame-ns)] [t (* 1000 p)] [f 2000041]
                 [late (quotient (* 22 p) 10)])
            ;; frames 2 and 3 are stamped as the stall ends, 2.2 refreshes on
            (present-test-flow f p t `((0 0) (1 0) (2 ,late)
                                       (2 ,(+ late 2000))))
            (let ([held (list *present-held* *present-held-last*)])
              (present-test-flow (+ f 4) p t `((2 ,(+ late 4000)) (5 0)))
              (and (equal? held (list (+ f 2) (+ f 3)))
                   (for-all (lambda (k) (= 1 (present-test-step (+ f k))))
                            '(2 3 4 5))
                   (= *present-held* -1)))))))

(check "with no steady refresh said by the screen (a Mac's, a variable \
        one), each stamp is taken as it is, at the window's rate, to the \
        nearest refresh, and no report is held; one that comes out of \
        order is placed before the newest"
       (present-test-fresh
        (lambda ()
          (let* ([p (core0-frame-ns)] [t (* 1000 p)] [f 2000051]
                 [frame (lambda (k at)
                          (list (+ t (* (- k 2) p)) (+ t at) 0))])
            (present-test-shown!
             f p (list (frame 0 0) (frame 1 (quotient (* 17 p) 10))
                       (frame 3 (* 4 p)) (frame 2 (* 3 p))))
            (and (= 2 (present-test-step (+ f 1)))
                 (= (present-test-word (+ f 1) 3)
                    (+ t (quotient (* 17 p) 10)))
                 (= p (present-test-word (+ f 1) 4))
                 (eqv? 1 (present-test-word (+ f 1) 1))
                 (= -1 (- (present-test-word (+ f 3) 5)
                          (present-test-word (+ f 2) 5)))
                 (= *present-refresh-at* (+ t (* 4 p))))))))

(check "no two frames at one refresh: a frame whose stamp is the one \
        before's own is numbered the next"
       (present-test-fresh
        (lambda ()
          (let* ([p (core0-frame-ns)] [t (* 1000 p)] [f 2000061])
            (present-test-flow f p t '((0 0) (0 0)))
            (and (= 1 (present-test-step (+ f 1)))
                 (eqv? 1 (present-test-word (+ f 1) 1)))))))

(check "after a pause a stamp is read to the nearest refresh, early or \
        late, and shown at once; the flow that follows counts on from it"
       (present-test-fresh
        (lambda ()
          (let* ([p (core0-frame-ns)] [t (* 1000 p)] [f 2000071]
                 [early (- (quotient (* 4 p) 10))])
            (present-test-shown!
             f p (list (list (- t (* 2 p)) t)
                       (list (+ t (* 98 p)) (+ t (* 100 p) early))
                       (list (+ t (* 99 p)) (+ t (* 101 p)))))
            (and (= 100 (present-test-step (+ f 1)))
                 (eqv? 1 (present-test-word (+ f 1) 1))
                 (= 1 (present-test-step (+ f 2))))))))

(check "the clock follows an earlier stamp at once, and later ones only \
        when eight in a row say so, by the least of them: a screen whose \
        refreshes moved 2 ms later is followed at the eighth frame"
       (present-test-fresh
        (lambda ()
          (let* ([p (core0-frame-ns)] [t (* 1000 p)] [f 2000081]
                 [off (lambda (k) (- (present-test-word (+ f k) 3)
                                     (+ t (* k p))))])
            (present-test-flow
             f p t (cons '(0 0)
                         (map (lambda (k)
                                (list (+ k 1) (+ 2000000 (* k 1000))))
                              (iota 9))))
            ;; frames 1 to 9 are stamped 2 ms late and more; then one comes
            ;; in time
            (present-test-flow (+ f 10) p t '((10 0)))
            (and (< (off 7) 100000)
                 (<= 1900000 (off 8) 2010000)
                 (<= 1900000 (off 9) 2020000)
                 (= (off 10) 0)
                 (for-all (lambda (k) (= 1 (present-test-step (+ f k))))
                          (cdr (iota 11))))))))

;; Sends and reports frames from first on, the first shown at t. Each of
;; steps is a pair: how long after the frame before the screen stamped
;; this one, and how long after it was sent, in ns. A refresh is p ns by
;; the screen's word.
(define (present-test-steps first p t steps)
  (present-test-shown!
   first p
   (let walk ([steps steps] [stamp t] [frames (list (list (- t (* 2 p)) t))])
     (if (null? steps)
         (reverse frames)
         (let ([stamp (+ stamp (caar steps))])
           (walk (cdr steps) stamp
                 (cons (list (- stamp (cadar steps)) stamp) frames)))))))

(check "after a pause the clock is the stamp: a laptop's panel that stops \
        its timing when nothing new comes shows the next frame off the old \
        beat, later or earlier than the nearest refresh, and the flow that \
        follows keeps the new one (Intel's under GNOME 48.7 at 120 Hz, as \
        measured: stamps 11.305, 9, 11.103 and 10.629 refreshes apart, \
        then three a refresh apart)"
       (present-test-fresh
        (lambda ()
          (let ([p 8333000] [f 2000091] [sent 20000000])
            (present-test-steps
             f p (* 1000 p)
             `((94206000 ,sent) (75000000 ,sent) (92526000 ,sent)
               (88577000 ,sent) (8333331 ,sent) (8333331 ,sent)
               (8333331 ,sent)))
            (and (equal? (map (lambda (k) (present-test-step (+ f k)))
                              '(1 2 3 4 5 6 7))
                         '(11 9 11 11 1 1 1))
                 (for-all (lambda (k)
                            (and (eqv? 1 (present-test-word (+ f k) 1))
                                 (= (present-test-word (+ f k) 3)
                                    (present-test-word (+ f k) 10))))
                          '(1 2 3 4 5 6 7))
                 (= *present-held* -1))))))

;; Reports a frame after a pause of 20 refreshes, whose stamp ran late ns
;; after its refresh, then two frames in a flow stamped in time, with a
;; refresh of p ns. Returns how far the clock's time of each of the two is
;; off its refresh's, in ns, their steps, and the late frame's word 1 (1
;; once it is shown).
(define (present-test-late-after-pause first p late)
  (present-test-fresh
   (lambda ()
     (let ([t (* 1000 p)])
       (present-test-shown!
        first p
        (list (list (- t (* 2 p)) t)
              (list (+ t (* 18 p)) (+ t (* 20 p) late))
              (list (+ t (* 19 p)) (+ t (* 21 p) 20000))
              (list (+ t (* 20 p)) (+ t (* 22 p) 20000))))
       (list (- (present-test-word (+ first 2) 3) (+ t (* 21 p)))
             (- (present-test-word (+ first 3) 3) (+ t (* 22 p)))
             (present-test-step (+ first 2))
             (present-test-step (+ first 3))
             (present-test-word (+ first 1) 1))))))

(let* ([p (core0-frame-ns)]
       [runs (map (lambda (k late)
                    (present-test-late-after-pause (+ 2000101 (* 10 k)) p late))
                  '(0 1 2 3)
                  (list (quotient p 8) (quotient (* 3 p) 8)
                        (quotient (* 5 p) 8) (quotient (* 7 p) 8)))])
  (check (format "a stamp that ran late after a pause is taken too, with \
                  nothing to tell it by, and shown at once; the next \
                  frame's, in time, sets the clock right, whether it ran \
                  an eighth of a refresh late or seven: no stamp comes \
                  before its refresh, so one that reads as the refresh \
                  before's says the clock was late (~a)"
                 runs)
         (for-all (lambda (run)
                    (and (<= 0 (car run) 20000) (<= 0 (cadr run) 20000)
                         (= 1 (caddr run)) (= 1 (cadddr run))
                         (eqv? 1 (list-ref run 4))))
                  runs)))

;; Feeds a stream of n frames from first on, with a refresh p ns long as
;; the display's mode says. Each frame shows a refresh after the one before
;; (one in 53 two, as if the compositor held it), is sent two refreshes
;; before it shows, and is stamped tens of microseconds after its refresh
;; (one in 97 between 0.5 and 9 ms after), never before the stamp before
;; it, as one thread sends them. With every over 0, a pause of 3 to 40
;; refreshes comes before every every-th frame. Core0's step runs before
;; each report.
;; Returns (wrong off across): the steps counted wrong among the frames in
;; a flow, except for the last one before a pause, whose stamp no later
;; report can tell from a refresh missed; the most by which the clock's
;; time of a frame whose frame before was also in the flow is off its
;; refresh's, in ns; and the steps across a pause counted wrong.
(define (present-test-stream first p n every)
  (let ([t (* 1000 p)] [truth (make-vector n 0)] [flow (make-vector n #t)])
    (let feed ([k 0] [tick 0] [sent 0] [before 0])
      (when (< k n)
        (let* ([at (+ t (* tick p))]
               [late (+ 5000 (* 1000 (modulo (* k 7919) 31))
                        (if (= 0 (modulo (* k 7919) 97))
                            (+ 500000 (* 100000 (modulo (* k 31) 86)))
                            0))]
               [stamp (max (+ at late) (+ before 2000))]
               [pause (if (and (> every 0) (= 0 (modulo (+ k 1) every)))
                          (+ 3 (modulo (* k 7907) 38))
                          0)])
          (vector-set! truth k tick)
          (when (and (> pause 0) (< (+ k 1) n))
            (vector-set! flow (+ k 1) #f))
          (present-held-poll! stamp)
          (present-test-sent! (+ first k) (+ t (* (- sent 2) p)))
          (present-test-reported! (+ first k) 1 stamp p p)
          (feed (+ k 1) (+ tick pause (if (= 0 (modulo k 53)) 2 1))
                (+ sent pause 1) stamp))))
    (present-held-poll! (* 2 (+ t (* 2 n 41 p))))
    (let verdict ([k 1] [wrong 0] [off 0] [across 0])
      (if (= k n)
          (list wrong off across)
          (let ([right? (= (present-test-step (+ first k))
                           (- (vector-ref truth k) (vector-ref truth (- k 1))))]
                [flow? (vector-ref flow k)]
                [last? (and (< (+ k 1) n) (not (vector-ref flow (+ k 1))))])
            (verdict (+ k 1)
                     (if (or right? last? (not flow?)) wrong (+ wrong 1))
                     (if (and flow? (vector-ref flow (- k 1)))
                         (max off (abs (- (present-test-word (+ first k) 3)
                                          (+ t (* (vector-ref truth k) p)))))
                         off)
                     (if (or right? flow?) across (+ across 1))))))))

(let* ([p (core0-frame-ns)]
       [at-60 (present-test-fresh
               (lambda () (present-test-stream 2001001 p 3000 0)))]
       ;; at 120 and 144 Hz a stamp may run more than three quarters of a
       ;; refresh late, and at 144 Hz more than a whole one
       [at-120 (present-test-fresh
                (lambda () (present-test-stream 2025001 8333333 3000 0)))]
       [at-144 (present-test-fresh
                (lambda () (present-test-stream 2005001 6944444 3000 0)))])
  (check (format "3,000 frames stamped as a kernel thread stamps them, one \
                  in 97 late by 0.5 to 9 ms, one in 53 held a refresh by \
                  the compositor: every step is counted right, and each \
                  frame's time by the clock is within 0.1 ms of its \
                  refresh's, at the window's rate, at 120 Hz and at 144 Hz \
                  (~a wrong, ~a ns off; ~a, ~a; ~a, ~a)"
                 (car at-60) (cadr at-60) (car at-120) (cadr at-120)
                 (car at-144) (cadr at-144))
         (for-all (lambda (run) (and (= 0 (car run)) (< (cadr run) 100000)))
                  (list at-60 at-120 at-144))))

(let* ([p (core0-frame-ns)]
       [at-60 (present-test-fresh
               (lambda () (present-test-stream 2010001 p 3000 5)))]
       [at-144 (present-test-fresh
                (lambda () (present-test-stream 2015001 6944444 3000 5)))])
  (check (format "the same frames in bursts of five, a pause of 3 to 40 \
                  refreshes before each burst, on a screen that keeps its \
                  beat through them: every step within a burst is counted \
                  right, its last's aside, and from a burst's second frame \
                  on its time by the clock is within 0.1 ms of its \
                  refresh's at the window's rate (~a wrong, ~a ns off, ~a \
                  wrong across a pause; at 144 Hz ~a wrong, ~a ns off, ~a \
                  across)"
                 (car at-60) (cadr at-60) (caddr at-60)
                 (car at-144) (cadr at-144) (caddr at-144))
         (and (= 0 (car at-60)) (< (cadr at-60) 100000)
              (= 0 (car at-144)))))

;; Returns whether core0 awaits something of a frame at now, so that it
;; looks rather than waits for events (core0-sleep!): of the newest frame,
;; sent at sent, its report where the screen gives them (reports?), until
;; it is in or its kind is k; and, with fence?, a fence of its GPU work not
;; yet seen signaled.
(define (present-test-awaiting? now sent reports? k fence?)
  (let ([n 3001001] [fences (make-vector present-fence-slots 0)])
    (when fence? (vector-set! fences 2 1))
    (fluid-let ([*present-fences* fences] [*present-newest* n])
      (present-test-sent! n sent)
      (fxvector-set! *present-ring* (+ (present-at n) 1) k)
      (present-awaiting? now reports?))))

(let ([sent (now-ns)])
  (check "core0 awaits the newest frame's report until it comes, a second \
          from its send at most, where the screen reports; and a frame's \
          GPU work until its fence is seen signaled, report or not"
         (and (present-test-awaiting? sent sent #t 0 #f)
              (present-test-awaiting? (+ sent 999000000) sent #t 0 #f)
              (not (present-test-awaiting? (+ sent 1000000000) sent #t 0 #f))
              (not (present-test-awaiting? sent sent #t 1 #f))
              (not (present-test-awaiting? sent sent #t 2 #f))
              (not (present-test-awaiting? sent sent #f 0 #f))
              (present-test-awaiting? (+ sent 2000000000) sent #f 1 #t)
              (present-test-awaiting? sent sent #t 1 #t))))

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
                (<= t (inspect-frame-at i 'tick)
                    (inspect-frame-at i 'draw)
                    (inspect-frame-at i 'publish))))))

(check "the newest frames, not yet sent and so with no report, leave the \
        last seconds' sums to those before them"
       (let ([p (core0-frame-ns)])
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
           ;; one more frame, whose row still holds another frame's, since
           ;; core0 hasn't sent it
           (request-frame!)
           (steps 1)
           (let ([m (inspect-frame-ref (- *frame-ring-n* 1) 6)])
             (fxvector-set! r (present-at m) (- m present-rows)))
           ;; a walk that stopped at the newest would sum nothing
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

(check "a person may say the refresh's length in place of the display \
        mode's: from 1 to 100 ms, or 0 for the mode's again; anything else \
        is refused and changes nothing; the screen's own word on it is not \
        read"
       (present-test-fresh
        (lambda ()
          (fluid-let ([*present-refresh-said* 0])
            (let* ([word (lambda (frame stamp refresh)
                           (present-test-sent! frame stamp)
                           (present-reported! frame 1 stamp refresh)
                           (fxvector-ref *present-ring*
                                         (+ (present-at frame) 4)))]
                   [refused (map core0-refresh-ns!
                                 '(-1 999999 100000001 16.7 #f "16"))]
                   [unsaid *present-refresh-said*]
                   [own (word 1 1000000000 8333333)]
                   [taken (core0-refresh-ns! 16667505)]
                   [posted (begin (steps 1) *present-refresh-said*)]
                   [said (word 2 2000000000 8333333)]
                   [none (word 3 3000000000 0)]
                   [back (begin (core0-refresh-ns! 0) (steps 1)
                                (word 4 4000000000 8333333))])
              (present-refresh-say! 5)
              (and (equal? refused '(#f #f #f #f #f #f))
                   (= unsaid 0)
                   (= own (core0-frame-ns))
                   taken
                   (= posted 16667505)
                   (= said 16667505)
                   (= none 16667505)
                   (= back (core0-frame-ns))
                   (= *present-refresh-said* 0)
                   (= 0 (cdr (assq 'refresh-said (inspect-core0))))))))))
