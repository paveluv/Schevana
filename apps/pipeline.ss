;;; apps/pipeline.ss — Pipeline: the way from a window's draw to the screen
;;; surface, on one screen, read through kits/inspect.ss.
;;;
;;; Five stages, chosen on the cards at the top:
;;;   Lists   the frame's list by who drew it, and each's records, decoded
;;;           in draw order, a run of glyphs as its text; a drawer's checkbox
;;;           off leaves it out of the small screen and the Tape
;;;   Who     what each drawer cost: main's time drawing it, its records, the
;;;           pixels they may touch, the runs they start, what changed
;;;   Course  a tick's stages in order, each as wide as its time, render
;;;           split into each drawer's draw and the rest
;;;   Inside  the record selected, decoded, and the shader it's drawn with,
;;;           its source and its helpers'
;;;   Memory  what draws, what it holds on the GPU, and the glyphs' atlas
;;; Right, the screen small, the selected record outlined, or shown another
;;; way: who drew each record, in its drawer's color, the selected one's
;;; bright; each record's kind; heat, a pixel as bright as how many records
;;; cover it; or what changed since the frame before. A press there
;;; lists the records that may touch that pixel. It draws again every tick, or
;;; as seldom as it's told, and it's on the screen it shows: so it's in itself,
;;; a tick older each time round. The wheel zooms it at the pointer and a drag
;;; moves it; a loupe magnifies the pixels at the pointer; and it pops out to a
;;; window of its own above the Pipeline, coming back when that one closes.
;;; Under them, the Tape: a mark a record in draw order, as tall as what it may
;;; cover, and in lanes who drew it and its kind. A press there, or its
;;; stepper, holds the frame and draws it as far as that record, the record
;;; selected; Play draws it record by record. What's selected in the list, or
;;; at a pixel, is marked on it, and named on its heading, with Clear (or
;;; Esc); a record selected opens its drawer in the tree, and stays with its
;;; drawer as the frame changes. A drawer keeps its color while it's open.
;;; Below, the River: a column a refresh of the screen's, each the frame on
;;; the screen then from the refresh before its tick to its showing, the
;;; screen's word over them and who was busy under them. A press holds it and
;;; goes back to that frame, the whole app showing it; a drag moves through
;;; them. Frames
;;; are kept for a few seconds, what's left of the River's reach, while it's
;;; open: closed, what's left of it is the core's few numbers a frame.
;;; While it flows it asks for a frame a tick, so it says what it takes itself.

(define-record-type pipeline-view
  (fields ui history river
          ticks                ; the tick breakdown under the River
          (mutable stage)      ; lists, who, course, inside, memory, latency
          (mutable shown)      ; (inspect-list), the one on view
          (mutable held?)      ; it stays
          (mutable looked)     ; when it was read, or due to be (now-ms)
          (mutable groups)     ; its spans: (label first count) ...
          (mutable selected)   ; a drawer's node or a record's row, or #f
          (mutable traced)     ; the records at a pixel, or #f: (x y n ...)
          (mutable upto)       ; the slider's record, or #f: all of them
          (mutable image)      ; the small screen on view, or #f
          (mutable back)       ; what its next picture is drawn on, or #f
          (mutable flip?)      ; back has a newer picture than image
          (mutable reach)      ; while held, the River's now: a refresh
          (mutable tick)       ; the tick picked, or #f
          (mutable own)        ; what it takes itself, ms a tick
          (mutable tip)        ; the last bar's tooltip: ((k . now) . text)
          (mutable every)      ; the small screen draws every this many frames
          (mutable tape)       ; the Tape, a stream a record
          (mutable tape-of)    ; the records it holds: kept, as it was
          (mutable playing)    ; while it plays, how far it has: a number
          (mutable play-secs)  ; how long it plays the whole frame
          (mutable zoom)       ; device pixels a screen pixel, or #f: all of it
          (mutable center)     ; the screen's pixel at the middle: (x . y)
          (mutable loupe?)
          (mutable popped)     ; its window when it's popped out, or #f
          (mutable off)        ; the spans left out, by node: (label k) ...
          (mutable kept)       ; the records drawn of the list on view, a
                               ; vector in order: what the Tape goes through
          (mutable kept-of)    ; the list on view it's of
          (mutable look)       ; what the small screen shows: pipeline-looks
          (mutable painted)    ; a list repainted for it, used again
          (mutable who)        ; what each drew cost: (list . rows)
          (mutable course)     ; a tick's stages: (list . (seq items))
          (mutable course-sort) ; (key . up|down), or #f: in their order
          (mutable who-sort)   ; (key . up|down), or #f: in draw order
          (mutable latency-words) ; (when . words), read twice a second
          (mutable ticks-by-frame?) ; the tick breakdown by frame, not when
          colors))             ; each drawer's color, by node: an index

(define pipeline-period-ms 1000)

;; About 5 seconds at 60 Hz.
(define pipeline-frames-kept 300)
(define pipeline-river-rows 2048)
(define pipeline-bar-px 3)

(define (pipeline-show! v l)
  (let ([place (pipeline-selected-place v)])
    (pipeline-view-shown-set! v l)
    (pipeline-view-groups-set! v (inspect-list-labels l))
    ;; a new drawer's color, in draw order
    (for-each (lambda (node) (pipeline-color-index v node))
              (pipeline-span-nodes (inspect-list-labels l)))
    (when place
      (pipeline-view-selected-set! v (pipeline-place-row v place)))))

;; What a profiler's node took, ms a tick, over the half second to tick newest.
(define (pipeline-ms-over node newest)
  (let ([seqs (filter profile-tick-kept?
                      (map (lambda (i) (- newest i)) (iota 30)))])
    (/ (fold-left (lambda (ms seq) (+ ms (profile-tick-node-ms seq node)))
                  0.0 seqs)
       (max 1 (length seqs)))))

;; What the window takes itself, ms a tick, over the last half second.
(define (pipeline-own-ms)
  (let ([win (find-window 'pipeline)] [newest (profile-newest-tick)])
    (if (and win newest)
        (pipeline-ms-over (profile-subject-of win) newest)
        0.0)))

(define (pipeline-look! v)
  (unless (pipeline-view-held? v)
    (let ([history (pipeline-view-history v)])
      (inspect-history-add! history)
      (pipeline-show! v (or (inspect-history-ref
                             history (inspect-history-newest history))
                            (inspect-list)))
      (pipeline-view-own-set! v (pipeline-own-ms))))
  (pipeline-view-looked-set! v (now-ms)))

;; What's on view, drawn on image, but the spans left out. Live, it's drawn
;; with the next frame, as far as the slider says; held, what's kept of the
;; frame is. Showing who drew, it's a frame kept, repainted: live, the one
;; just drawn.
(define (pipeline-preview-on! v image)
  (let ([l (pipeline-view-shown v)] [upto (pipeline-view-upto v)]
        [left-out (pipeline-left-out-of v)])
    (cond
      [(not (eq? (pipeline-view-look v) 'picture))
       (let* ([h (pipeline-view-history v)]
              [from (if (pipeline-view-held? v)
                        l
                        (or (inspect-history-ref h (inspect-history-newest h))
                            l))])
         (inspect-preview-list! image (pipeline-painted v from)
                                (or upto (inspect-list-count from)) left-out))]
      [(pipeline-view-held? v)
       (inspect-preview-list! image l (or upto (inspect-list-count l))
                              left-out)]
      [else
       (inspect-preview! image (or upto (most-positive-fixnum)) left-out)])))

;; At once, on the image that frame shows. An image can't show itself as it's
;; drawn on, so its own box stays empty.
(define (pipeline-preview! v)
  (let ([image (pipeline-view-image v)])
    (when image (pipeline-preview-on! v image))))

;; A tick's, on the other image, so the frame showing the one on view is drawn
;; whole. It comes on view at the next tick: pipeline-flip!.
(define (pipeline-preview-back! v)
  (let ([back (pipeline-view-back v)])
    (when back
      (pipeline-preview-on! v back)
      (pipeline-view-flip?-set! v #t))))

(define (pipeline-flip! v)
  (when (pipeline-view-flip? v)
    (let ([image (pipeline-view-image v)])
      (pipeline-view-image-set! v (pipeline-view-back v))
      (pipeline-view-back-set! v image)
      (pipeline-view-flip?-set! v #f))))

;;; ---- going back

;; The frame on the screen when tick seq ended.
(define (pipeline-tick-frame seq) (- (profile-tick-ns seq 'frames) 1))

;; It stops flowing, and the frames stay as they are, the last one among them.
(define (pipeline-hold! v)
  (unless (pipeline-view-held? v)
    (inspect-history-add! (pipeline-view-history v))
    (pipeline-view-held?-set! v #t)
    (pipeline-view-flip?-set! v #f)
    (pipeline-view-tick-set! v (profile-newest-tick))
    (pipeline-view-reach-set! v (pipeline-river-target (inspect-refresh-grid)))
    (pipeline-preview! v)))

(define (pipeline-resume! v)
  (pipeline-view-held?-set! v #f)
  (pipeline-view-tick-set! v #f)
  (pipeline-view-traced-set! v #f)
  (pipeline-view-playing-set! v #f)
  (pipeline-look! v)
  (pipeline-preview! v))

;; Goes back to tick seq: the whole app shows its frame, if it's still kept.
(define (pipeline-pick! v seq)
  (pipeline-hold! v)
  (when (profile-tick-kept? seq)
    (pipeline-view-tick-set! v seq)
    (let ([l (inspect-history-ref (pipeline-view-history v)
                                  (pipeline-tick-frame seq))])
      (when (and l (not (eq? l (pipeline-view-shown v))))
        (pipeline-show! v l)
        (pipeline-view-traced-set! v #f)
        (pipeline-preview! v)))))

;;; ---- the River
;;; A column a refresh of the screen's, the newest at the right: the one
;;; before now, the refresh the frame drawn will show at
;;; (pipeline-river-target). The newest frames are on their way, under
;;; the refreshes they're meant for.
;;; A column's bar is the frame on the screen at that refresh, a tail
;;; hanging from zero, its showing: down, its way back to its tick, and
;;; under that its input's, from the compositor to the tick. Shown again
;;; while the next frame was late, the time since is red, at the top; with
;;; nothing due, the column is empty. Over the bars, the screen's word on
;;; each refresh.

;; How bright a tick's collecting is: a level by its time, faint however short,
;; and at its brightest from this many ns.
(define pipeline-collector-levels 8)
(define pipeline-collector-full-ns 2000000)

(define (pipeline-collector-level ns)
  (+ 1 (quotient (* (- pipeline-collector-levels 1)
                    (min (max ns 0) pipeline-collector-full-ns))
                 pipeline-collector-full-ns)))

;; Whether tick seq drew a frame.
(define (pipeline-tick-drew? seq)
  (or (not (profile-tick-kept? (- seq 1)))
      (> (profile-tick-ns seq 'frames) (profile-tick-ns (- seq 1) 'frames))))

;; The frame tick seq drew, counting from 0 (inspect-frame-ref).
(define (pipeline-tick-frame-index seq) (- (profile-tick-ns seq 'frames) 1))

;; The tick that drew frame i, among those kept, or #f.
(define (pipeline-frame-tick i)
  (let loop ([seq (profile-newest-tick)])
    (and seq (profile-tick-kept? seq) (> (profile-tick-ns seq 'frames) i)
         (if (and (profile-tick-kept? (- seq 1))
                  (> (profile-tick-ns (- seq 1) 'frames) i))
             (loop (- seq 1))
             seq))))

;; Refreshes kept; the bars' room in refreshes, under zero.
(define pipeline-river-kept 300)
(define pipeline-river-depth 5)

;; A tail's parts bottom up, the oldest first, a word each: (color .
;; label), the first clear, lifting the tail to hang from zero.
(define pipeline-draw-river-parts
  '((#f . #f)
    (chart-muted-1 . "input, to SDL's stamp")
    (chart-muted-2 . "to core0's pump")
    (chart-5 . "to main's tick")
    (chart-1 . "main")
    (chart-2 . "in the box")
    (chart-3 . "core0")
    (chart-4 . "the GPU")
    (chart-6 . "ready, to the latch")
    (chart-8 . "the compositor")
    (chart-flag . "shown again, the next frame late")))

;; Over the bars, the screen's word: new, shown again while a newer was
;; due, a frame dropped.
(define pipeline-draw-river-strips '(("screen" chart-ok chart-flag chart-2)))

(define pipeline-river-screen-tip
  "Green: a new frame showed at this refresh. Red: the one before showed \
   again, the next frame late, or, by VSync, the compositor dropped one, \
   two having come in one refresh. Orange: the compositor dropped one for \
   a newer, as Mailbox does. None: nothing new was due, or no word yet. \
   A pip: the screen's count and its times disagree on how far its frame \
   came after the one before.")

(define (pipeline-river-new)
  (ui-stream-new pipeline-river-rows (length pipeline-draw-river-parts)
                 pipeline-draw-river-strips))

;; Whether frame i may still show: not dropped, and core0 found room for it.
(define (pipeline-frame-on-way? i)
  (not (or (eqv? (inspect-frame-report i 1) 2)
           (eq? (inspect-frame-sent i) 'no-room))))

;; Where frames began to show, by grid g, from refresh from on: each frame
;; the screen reported at its refresh, the last before from among them;
;; then those on their way at the one each is meant for, or the next free
;; one. => ((k i on-way?) ...) by k
(define (pipeline-river-starts g from)
  (define (refresh i) (and (inspect-frame-ref i 6) (inspect-frame-refresh g i)))
  (let find ([i (- *frame-ring-n* 1)] [on-way '()])
    (if (and (inspect-frame-ref i 6) (not (refresh i)))
        (find (- i 1) (if (pipeline-frame-on-way? i) (cons i on-way) on-way))
        (let ([last (refresh i)])
          (append
           (let older ([i i] [acc '()])
             (let ([k (refresh i)])
               (cond [(not (inspect-frame-ref i 6)) acc]
                     [(not k) (older (- i 1) acc)]
                     [(< k from) (cons (list k i #f) acc)]
                     [else (older (- i 1) (cons (list k i #f) acc))])))
           (let place ([is on-way] [k (if last (+ last 1) from)])
             (if (null? is)
                 '()
                 (let ([at (max k (or (inspect-frame-target g (car is)) k))])
                   (cons (list at (car is) #t)
                         (place (cdr is) (+ at 1)))))))))))

;; The frame on the screen at refresh k by grid g, or #f.
(define (pipeline-river-frame-at g k)
  (let loop ([starts (pipeline-river-starts g k)] [i #f])
    (if (and (pair? starts) (<= (car (car starts)) k))
        (loop (cdr starts) (cadr (car starts)))
        i)))

;; The refresh frame i shows at, or is meant for, by grid g.
(define (pipeline-frame-column g i)
  (or (inspect-frame-refresh g i) (inspect-frame-target g i)))

;; Whether a frame between i0 and i was dropped.
(define (pipeline-dropped-between? i0 i)
  (let loop ([j (+ i0 1)])
    (and (< j i)
         (or (eqv? (inspect-frame-report j 1) 2) (loop (+ j 1))))))

;; Frame i's tail into row (µs), by grid g, down from zero, refresh at's
;; time and extra ns on (shown again): back from its showing to its tick,
;; then its input's way to it; on its way, as far as it has gone by now,
;; under the refresh it's meant for, the compositor's part from the latch
;; it should make. Cut at the column's depth.
(define (pipeline-river-parts! row g i at extra on-way?)
  (let* ([r (inspect-refresh-period g)]
         [top (+ (inspect-refresh-time g at) extra)]
         [bottom (- top (* pipeline-river-depth r))]
         [tick (inspect-frame-at i 'tick)]
         [shown (or (inspect-frame-at i 'shown)
                    (and (not on-way?) (inspect-refresh-time g at)))]
         [latch (or (inspect-refresh-latch g at) shown)]
         [end (if on-way? (min top (now-ns)) top)]
         [input (map (lambda (point)
                       (let ([t (inspect-frame-at i point)])
                         (and t tick (min t tick))))
                     '(wl sdl pumped))]
         [us (lambda (ns) (quotient (max 0 ns) 1000))])
    (when tick
      ;; each point no earlier than the one before, a missing one taking
      ;; no time
      (let ([start (max bottom (apply min tick (filter values input)))])
        (fxvector-set! row 0 (us (- start bottom)))
        (let loop ([points (append (cdr input)
                                   (list tick
                                         (inspect-frame-at i 'publish)
                                         (inspect-frame-at i 'taken)
                                         (inspect-frame-at i 'sent)
                                         (inspect-frame-at i 'gpu)
                                         latch shown))]
                   [k 1] [at start] [now? #f])
          (unless (null? points)
            (let* ([p (car points)]
                   [t (min end (max at (cond [p p]
                                             [now? (now-ns)]
                                             [else at])))])
              (fxvector-set! row k (us (- t at)))
              ;; the tick is point 3: after it, on its way, the first
              ;; missing is now
              (loop (cdr points) (+ k 1) t
                    (cond [(< k 3) #f]
                          [(= k 3) on-way?]
                          [else (and now? p #t)])))))))
    (fxvector-set! row 10 (us extra))))

;; The River's words of refresh k, by grid g, now the refresh now, from
;; starts (pipeline-river-starts): the parts of the bar of the frame on the
;; screen then, and the screen's word. Rows come by k: each is worked out
;; once, its words read in turn.
(define (pipeline-river-word g now starts)
  (let* ([n (length pipeline-draw-river-parts)]
         [row (make-fxvector (+ n 1) 0)]
         [vsync? (eq? (inspect-present-mode) 'vsync)]
         [at #f] [left starts] [start #f] [prev #f])
    (lambda (k j)
      (unless (eqv? k at)
        (set! at k)
        (let advance ()
          (when (and (pair? left) (<= (car (car left)) k))
            (set! prev start)
            (set! start (car left))
            (set! left (cdr left))
            (advance)))
        (fxvector-fill! row 0)
        (when start
          (let* ([shown-at (car start)] [i (cadr start)]
                 [on-way? (caddr start)]
                 [new? (= shown-at k)]
                 [target (and (< (+ i 1) *frame-ring-n*)
                              (inspect-frame-target g (+ i 1)))]
                 [due? (and (not new?) (<= k now) target (<= target k))])
            (when (or new? due?)
              (pipeline-river-parts!
               row g i shown-at
               (if new?
                   0
                   (- (inspect-refresh-time g k)
                      (inspect-refresh-time g shown-at)))
               on-way?))
            (fxvector-set!
             row n
             (cond [(and new? on-way?) 0]
                   [(and new? prev (pipeline-dropped-between? (cadr prev) i))
                    (if vsync? 2 3)]
                   [new? 1]
                   [due? 2]
                   [else 0])))))
      (fxvector-ref row j))))

;; The rules: a refresh at a time under zero, the screen, which is at the
;; top.
(define (pipeline-river-rules r)
  (map (lambda (m)
         (cons (quotient (* (- pipeline-river-depth m) r) 1000)
               (format "−~a" m)))
       '(1 2 3 4)))

;; Refresh k on the River, in words, worked out once while it's pointed at.
(define (pipeline-river-tip v g now k)
  (let ([tip (pipeline-view-tip v)] [key (cons k now)])
    (if (and tip (equal? (car tip) key))
        (cdr tip)
        (let ([text (pipeline-river-text g now k)])
          (pipeline-view-tip-set! v (cons key text))
          text))))

(define (pipeline-river-text g now k)
  (let* ([r (inspect-refresh-period g)]
         [ms (lambda (ns) (format "~,1f" (/ ns 1e6)))]
         [i (pipeline-river-frame-at g k)]
         [head (format "refresh ~a~a, ~a ms before this picture shows"
                       k (if (inspect-refresh-estimated? g) " (estimated)" "")
                       (ms (* (- now k) r)))])
    (if (not i)
        (string-append head "\nno frame")
        (let* ([at (pipeline-frame-column g i)]
               [shown (inspect-frame-at i 'shown)]
               [tick (inspect-frame-at i 'tick)]
               [in (inspect-frame-input i)]
               [seq (pipeline-frame-tick i)]
               [point (lambda (p) (inspect-frame-at i p))])
          (string-append
           head
           (format "\nframe ~a, ~a" (inspect-frame-ref i 6)
                   (cond [(not shown) "on its way to the screen"]
                         [(= at k) "new at this refresh"]
                         [else "shown again"]))
           (if (and in shown)
               (format "\ninput to screen ~a ms" (ms (- shown in)))
               "")
           (if (and tick shown)
               (format "~atick to screen ~a ms" (if in "; " "\n")
                       (ms (- shown tick)))
               "")
           (if (and (= at k) (inspect-frame-seq-off? i))
               (format "\nafter the frame before, in refreshes: ~a by \
                        the screen's count, ~,2f by its times"
                       (- at (inspect-frame-report (- i 1) 5))
                       (inexact
                        (/ (- shown (inspect-frame-at (- i 1) 'shown))
                           (inspect-frame-report i 4))))
               "")
           (apply string-append
                  (map (lambda (from to name)
                         (let ([a (point from)] [b (point to)])
                           (if (and a b)
                               (format "\n~a ~a ms" name (ms (- b a)))
                               "")))
                       '(wl sdl pumped tick publish taken sent)
                       '(sdl pumped tick publish taken sent gpu)
                       '("input, to SDL's stamp" "to core0's pump"
                         "to main's tick" "main" "in the box" "core0"
                         "the GPU")))
           (if (and seq (profile-tick-kept? seq))
               (string-append "\n\n" (monitor-tick-tip seq (monitor-clock-zero)
                                                       (pacer-period)))
               ""))))))

;; Over the frames, main's ticks, a column a refresh as the frames': the
;; ticks whose work began in it, or each frame's own, over the refresh it
;; showed at. Monitor's phases, rising to the screen's lane, two refreshes
;; tall, a refresh as tall as under it; over them, whether a tick came
;; late and when a collection ran.
(define pipeline-river-ticks-high 2)

(define pipeline-draw-river-tick-strips
  `(("late" chart-flag)
    ("collector"
     ,@(map (lambda (i)
              (alpha 'chart-7
                     (+ 0.2 (* 0.8 (/ i (- pipeline-collector-levels 1.0))))))
            (iota pipeline-collector-levels)))))

(define pipeline-river-ticks-tips
  (list "Red: main's own work in a tick here took more than one and a half \
         periods, and came late."
        (format "A collection ran in a tick here: the longer it took, the \
                 brighter, at its brightest from ~a."
                (monitor-ns-text pipeline-collector-full-ns))))

(define (pipeline-river-ticks-new)
  (ui-stream-new pipeline-river-rows (length monitor-phases)
                 pipeline-draw-river-tick-strips))

;; When tick seq's own work began (now-ns): after its wait for the screen.
(define (pipeline-tick-began seq)
  (- (profile-tick-ns seq 'end)
     (- (profile-tick-ns seq 'ns) (profile-tick-phase-ns seq 'vsync-wait))))

;; The ticks of refresh k, by grid g, from starts (pipeline-river-starts):
;; under frames, the one that drew the frame new there; else those whose
;; work began in it, from ran (pipeline-river-ticks-ran).
(define (pipeline-river-ticks-of g k by-frame? starts ran)
  (if by-frame?
      (let ([start (assv k starts)])
        (let ([seq (and start (pipeline-frame-tick (cadr start)))])
          (if seq (list seq) '())))
      (hashtable-ref ran k '())))

;; The ticks kept whose work began from refresh from on, by grid g: refresh
;; -> (seq ...).
(define (pipeline-river-ticks-ran g from)
  (let ([t (make-eqv-hashtable)] [since (inspect-refresh-time g from)])
    (let loop ([seq (profile-newest-tick)])
      (when (and seq (profile-tick-kept? seq))
        (let ([began (pipeline-tick-began seq)])
          (when (>= began since)
            (hashtable-update! t (inspect-refresh-of g began)
                               (lambda (seqs) (cons seq seqs)) '())
            (loop (- seq 1))))))
    t))

;; The tick breakdown's words of refresh k: its ticks' phases summed (µs),
;; then whether one came late, and the collector's level, by its longest.
(define (pipeline-river-tick-word g by-frame? starts ran)
  (let ([phases (length monitor-phases)] [period (pacer-period)])
    (lambda (k j)
      (let ([seqs (pipeline-river-ticks-of g k by-frame? starts ran)])
        (cond
          [(< j phases)
           (fold-left (lambda (sum seq)
                        (+ sum (quotient (monitor-tick-phase-ns seq j) 1000)))
                      0 seqs)]
          [(= j phases)
           (if (exists (lambda (seq) (profile-tick-late? seq period)) seqs)
               1
               0)]
          [else
           (fold-left (lambda (level seq)
                        (if (> (profile-tick-ns seq 'gcs) 0)
                            (max level (pipeline-collector-level
                                        (profile-tick-ns seq 'gc-ns)))
                            level))
                      0 seqs)])))))

;; The tick breakdown's rules: a refresh and two over its foot.
(define (pipeline-river-tick-rules r)
  (map (lambda (i)
         (cons (quotient (* (+ i 1) r) 1000) (format "+~a" (+ i 1))))
       (iota pipeline-river-ticks-high)))

;; Labels another chart's gutter has, as rules with no line: the frames'
;; and the ticks' columns then start at the same x.
(define (pipeline-river-gutter rules strips)
  (map (lambda (label) (cons #f label))
       (append (map cdr rules) (filter values (map car strips)))))

;; Refresh k's ticks, in words.
(define (pipeline-river-ticks-text g k by-frame? starts)
  (let ([seqs (pipeline-river-ticks-of
               g k by-frame? starts
               (if by-frame? #f (pipeline-river-ticks-ran g k)))]
        [period (pacer-period)])
    (if (null? seqs)
        (format "refresh ~a: no tick~a" k
                (if by-frame? " drew a frame new here" " began here"))
        (apply string-append
               (map (lambda (seq at)
                      (string-append
                       (if (= at 0) "" "\n\n")
                       (monitor-tick-tip seq (monitor-clock-zero) period)
                       (if (> (profile-tick-ns seq 'gcs) 0)
                           (format "\ncollected for ~,2f ms"
                                   (/ (profile-tick-ns seq 'gc-ns) 1e6))
                           "")))
                    seqs (iota (length seqs)))))))

;; The picked tick's column.
(define (pipeline-river-tick-marked v g by-frame?)
  (let ([tick (pipeline-view-tick v)])
    (cond [by-frame? (pipeline-river-marked v g)]
          [(and tick (profile-tick-kept? tick))
           (list (inspect-refresh-of g (pipeline-tick-began tick)))]
          [else '()])))

;; The refreshes from oldest on where the screen's count and its times
;; disagree on how far the frame there came after the one before
;; (inspect-frame-seq-off?): none on an estimated grid, which has no word.
(define (pipeline-river-seq-off g oldest)
  (if (inspect-refresh-estimated? g)
      '()
      (let loop ([i (- *frame-ring-n* 1)] [ks '()])
        (if (not (inspect-frame-ref i 6))
            ks
            (let ([k (and (inspect-frame-shown? i) (inspect-frame-report i 5))])
              (cond [(and k (< k oldest)) ks]
                    [(and k (inspect-frame-seq-off? i))
                     (loop (- i 1) (cons k ks))]
                    [else (loop (- i 1) ks)]))))))

;; A pip in the screen's cell of each refresh in ks, over its color.
(define (pipeline-draw-river-seq-off areas count newest ks)
  (let ([py (cadr (cdr (assq 'plot areas)))]
        [lane (- (cadr (assq 'lane areas)) (caddr (assq 'lane areas)))])
    (for-each
     (lambda (k)
       (let ([i (- count 1 (- newest k))])
         (when (>= i 0)
           (let-values ([(bx bw) (ui-bar-chart-bar areas count i)])
             ;; a bar may be a fraction of a pixel wide when fitted
             (let ([pw (max 1 (exact (floor (/ bw 3))))]
                   [ph (max 1 (quotient lane 2))])
               (fill-box (exact (round (+ bx (/ (- bw pw) 2))))
                         (+ py (quotient (- lane ph) 2)) pw ph 'text))))))
     ks)))

;; The River's height for this width's legends, its heading, the ticks
;; and the legends included, with the frames' bars about h tall.
(define (pipeline-river-height w bars)
  (+ (pipeline-river-fixed w)
     (* (+ pipeline-river-depth pipeline-river-ticks-high)
        (quotient bars pipeline-river-depth))))

;; What of the River's height isn't bars: its heading, legends, and each
;; stream's strips and the inset over its plot.
(define (pipeline-river-fixed w)
  (let-values ([(kw kh) (ui-legend-size (pipeline-river-keys))]
               [(tw th) (ui-legend-size (pipeline-river-tick-keys))])
    (+ (pipeline-river-heading-h w) 4 th 4
       pipeline-river-inset (ui-stream-room pipeline-draw-river-tick-strips)
       pipeline-river-inset (ui-stream-room pipeline-draw-river-strips)
       4 kh)))

;; The River's heading row: its name, whether it's live, the checkbox,
;; the words.
(define (pipeline-river-heading-h w)
  (let-values ([(gw gh) (ui-label-size '(group) "River" w)]
               [(cw ch) (pipeline-river-tick-choice-size)]
               [(lw lh) (ui-live-badge-size #t "")])
    (max gh ch lh)))

;; What a held Pipeline holds, on its badge.
(define (pipeline-river-held-label v)
  (let* ([tick (pipeline-view-tick v)]
         [l (and tick (profile-tick-kept? tick)
                 (inspect-history-ref (pipeline-view-history v)
                                      (pipeline-tick-frame tick)))])
    (if l (format "Held at frame ~a" (inspect-list-frame l)) "Held")))

(define pipeline-river-live-tip
  "Live: the Pipeline follows each frame. A press here, or on a bar, holds \
   it still on one frame; here again, or Esc, lets it go.")

;; Which ticks stand over a refresh: those whose work began in it, or the
;; one that drew the frame new there.
(define pipeline-river-tick-choices
  '(("Ticks when they ran" . ran)
    ("Each over its frame" . frame)))

;; The choice's room: a button as wide as the widest, each.
(define (pipeline-river-tick-choice-size)
  (let ([sizes (map (lambda (c)
                      (call-with-values (lambda () (ui-button-size (car c) #f))
                        cons))
                    pipeline-river-tick-choices)])
    (values (* (length sizes) (+ 6 (apply max (map car sizes))))
            (apply max (map cdr sizes)))))

;; A stream's plot begins this far under its top (ui-bar-chart-areas).
(define pipeline-river-inset 4)

(define (pipeline-river-keys)
  (filter cdr (cdr pipeline-draw-river-parts)))

(define (pipeline-river-tick-keys)
  (map cdr monitor-phases))

(define (pipeline-river-words v g)
  (let ([tick (pipeline-view-tick v)] [held? (pipeline-view-held? v)])
    (if (and held? tick)
        (let ([l (and (profile-tick-kept? tick)
                      (inspect-history-ref (pipeline-view-history v)
                                           (pipeline-tick-frame tick)))])
          (if l
              (format "tick ~a, frame ~a: ~a records" tick
                      (inspect-list-frame l) (inspect-list-count l))
              (format "tick ~a: its frame is no longer kept" tick)))
        (format "a column a refresh, ~,1f ms~a; ~a frames kept; it takes \
                 ~,2f ms a tick itself"
                (/ (inspect-refresh-period g) 1e6)
                (if (inspect-refresh-estimated? g)
                    ", estimated: this screen doesn't report"
                    "")
                (inspect-history-count (pipeline-view-history v))
                (pipeline-view-own v)))))

;; The picked frame's column.
(define (pipeline-river-marked v g)
  (let ([tick (pipeline-view-tick v)])
    (if (and tick (profile-tick-kept? tick) (pipeline-tick-drew? tick))
        (let ([k (pipeline-frame-column g (pipeline-tick-frame-index tick))])
          (if k (list k) '()))
        '())))

;; Goes back to the frame on the screen at refresh k.
(define (pipeline-pick-refresh! v g k)
  (let* ([i (pipeline-river-frame-at g k)]
         [seq (and i (pipeline-frame-tick i))])
    (when seq (pipeline-pick! v seq))))

;; The refresh on the River's now: the one the frame drawn now will show
;; at (pipeline-river-target); while held, as it was.
(define (pipeline-river-now v g)
  (if (pipeline-view-held? v)
      (pipeline-view-reach v)
      (pipeline-river-target g)))

;; The refresh the frame being drawn will show at, by grid g, should frames
;; keep coming a refresh apart: the one after the newest frame placed on a
;; refresh, one more for each since on its way to the screen; never before
;; the next refresh. So the River moves a column a frame while the screen
;; takes them so, the screen's late word no matter, and a frame that comes
;; late moves it with the jump it makes.
(define (pipeline-river-target g)
  (let ([next (+ (inspect-refresh-of g (now-ns)) 1)])
    (let loop ([i (- *frame-ring-n* 1)] [ahead 1] [n 0])
      (if (or (= n 64) (not (inspect-frame-ref i 6)))
          (+ next ahead -1)
          (let ([k (inspect-frame-refresh g i)])
            (cond [k (max next (+ k ahead))]
                  [(pipeline-frame-on-way? i)
                   (loop (- i 1) (+ ahead 1) (+ n 1))]
                  [else (loop (- i 1) ahead (+ n 1))]))))))

(define (pipeline-river-pane v x y w h)
  (let*-values
      ([(ui) (pipeline-view-ui v)]
       [(river) (pipeline-view-river v)]
       [(ticks) (pipeline-view-ticks v)]
       [(by-frame?) (pipeline-view-ticks-by-frame? v)]
       [(g) (inspect-refresh-grid)]
       [(r) (inspect-refresh-period g)]
       [(top) (quotient (* pipeline-river-depth r)
                        1000)]
       [(rules) (pipeline-river-rules r)]
       [(tick-rules) (pipeline-river-tick-rules r)]
       [(frame-rules) (append rules
                              (pipeline-river-gutter
                               tick-rules pipeline-draw-river-tick-strips))]
       [(tick-rules*) (append tick-rules
                              (pipeline-river-gutter
                               rules pipeline-draw-river-strips))]
       [(now) (pipeline-river-now v g)]
       ;; now's own frame is the one being drawn
       [(newest) (- now 1)]
       [(oldest) (- newest (min pipeline-river-kept (max 1 (quotient w 2)))
                    -1)]
       [(keys) (pipeline-river-keys)]
       [(tick-keys) (pipeline-river-tick-keys)]
       [(gw gh) (ui-label-size '(group) "River" w)]
       [(kw kh) (ui-legend-size keys)]
       [(tw th) (ui-legend-size tick-keys)]
       [(cw ch) (pipeline-river-tick-choice-size)]
       [(live?) (not (pipeline-view-held? v))]
       [(held-label) (if live? "" (pipeline-river-held-label v))]
       [(lw lh) (ui-live-badge-size live? held-label)]
       [(row) (pipeline-river-heading-h w)]
       ;; a refresh's height in pixels, the same up and down
       [(unit) (max 1 (quotient (- h (pipeline-river-fixed w))
                                (+ pipeline-river-depth
                                   pipeline-river-ticks-high)))]
       [(ticks-h) (+ pipeline-river-inset
                     (ui-stream-room pipeline-draw-river-tick-strips)
                     (* pipeline-river-ticks-high unit))]
       ;; the heading, then the ticks rising to the screen's lane, and the
       ;; frames' tails hanging from it
       [(ty) (+ y row 4 th 4)]
       [(sy) (+ ty ticks-h)]
       [(sh) (+ pipeline-river-inset
                (ui-stream-room pipeline-draw-river-strips)
                (* pipeline-river-depth unit))])
    (let ([ly (+ y (quotient (- row gh) 2))])
      (ui-draw-label x ly w gh '(group) "River")
      (ui-draw-label x ly w gh '(dim right) (pipeline-river-words v g)))
    (unless (pipeline-view-held? v)
      ;; the screen reports a few refreshes on, and what's on its way moves
      (ui-stream-resend! river (- now 8))
      (ui-stream-resend! ticks (- now 8))
      (let* ([from (if (< newest (ui-stream-sent river))
                       oldest
                       (max oldest (+ (ui-stream-sent river) 1)))]
             [ticks-from (if (< newest (ui-stream-sent ticks))
                             oldest
                             (max oldest (+ (ui-stream-sent ticks) 1)))]
             [starts (pipeline-river-starts g (min from ticks-from))])
        (ui-stream-send! river oldest newest
                         (pipeline-river-word g now starts))
        (ui-stream-send! ticks oldest newest
                         (pipeline-river-tick-word
                          g by-frame? starts
                          (and (not by-frame?)
                               (pipeline-river-ticks-ran g ticks-from))))))
    (ui-stream ui 'pipeline-river river x sy w sh newest oldest top
               frame-rules
               (map (lambda (part j) (cons j (car part)))
                    pipeline-draw-river-parts
                    (iota (length pipeline-draw-river-parts)))
               1
               'fit 'whole
               'doc '((L . "Go back to this frame"))
               'strip-tips (list pipeline-river-screen-tip)
               'tip (lambda (k) (pipeline-river-tip v g now k))
               'on-pick (lambda (k) (pipeline-pick-refresh! v g k))
               'marked (pipeline-river-marked v g)
               'over (lambda (areas count)
                       (pipeline-draw-river-seq-off
                        areas count newest
                        (pipeline-river-seq-off g oldest))))
    (ui-draw-legend x (+ sy sh 4) w kh '() keys)
    (ui-draw-legend x (+ y row 4) w th '() tick-keys)
    (ui-live-badge ui '(pipeline hold) (+ x gw 12) (+ y (quotient (- row lh) 2))
             lw lh live? held-label
             (lambda (on?)
               (if on? (pipeline-resume! v) (pipeline-hold! v)))
             'tip pipeline-river-live-tip)
    (ui-segmented ui '(pipeline ticks) (+ x gw 12 lw 16)
                  (+ y (quotient (- row ch) 2)) cw ch
                  pipeline-river-tick-choices (if by-frame? 'frame 'ran)
                  (lambda (choice)
                    (unless (eq? (eq? choice 'frame) by-frame?)
                      (pipeline-view-ticks-by-frame?-set! v (eq? choice 'frame))
                      (ui-stream-restart! ticks))))
    (ui-stream ui 'pipeline-river-ticks ticks x ty w ticks-h newest oldest
               (quotient (* pipeline-river-ticks-high r) 1000)
               tick-rules*
               (map (lambda (phase j) (cons j (cadr phase)))
                    monitor-phases (iota (length monitor-phases)))
               1
               'fit 'whole
               'doc '((L . "Go back to this tick"))
               'strip-tips pipeline-river-ticks-tips
               'tip (lambda (k)
                      (pipeline-river-ticks-text
                       g k by-frame? (if by-frame?
                                         (pipeline-river-starts g k)
                                         '())))
               'on-pick (lambda (k)
                          (let ([seqs (pipeline-river-ticks-of
                                       g k by-frame?
                                       (if by-frame?
                                           (pipeline-river-starts g k)
                                           '())
                                       (if by-frame?
                                           #f
                                           (pipeline-river-ticks-ran g k)))])
                            (when (pair? seqs) (pipeline-pick! v (car seqs)))))
               'marked (pipeline-river-tick-marked v g by-frame?))))

;;; ---- Latency
;;; The refresh clock, the last six refreshes as they went, and the
;;; numbers of the newest frame shown, over the River, which is the chart.

;; Input to screen, the last 10 s, ms at the median and the 99th, by each
;; input's point, read twice a second.
(define (pipeline-latency-words v)
  (let ([was (pipeline-view-latency-words v)])
    (if (and was (< (- (now-ms) (car was)) 500))
        (cdr was)
        (let ([words
               (map (lambda (point name)
                      (let-values ([(p50 p99 missed)
                                    (inspect-frames-truth 10000 point)])
                        (if p50
                            (format "~a ~,1f, ~,1f" name (/ p50 1e6)
                                    (/ p99 1e6))
                            (format "~a none" name))))
                    '(wl sdl pumped)
                    '("compositor" "SDL" "core0's pump"))])
          (pipeline-view-latency-words-set! v (cons (now-ms) words))
          words))))

(define (pipeline-latency-pane v x y w h)
  (let*-values
      ([(ui) (pipeline-view-ui v)]
       [(gw gh) (ui-label-size '(group) "Latency" w)]
       [(ty) (+ y gh 4)])
    (ui-draw-label x y w gh '(group) "Latency")
    (ui-draw-label x y w gh '(dim right)
                   (string-append "input to screen, the last 10 s, ms at \
                                   the median and the 99th: "
                                  (string-join (pipeline-latency-words v)
                                               "; ")))
    (pipeline-draw-refresh-clock x ty pipeline-clock-size
                                 (pipeline-timeline-last v))
    (ui-region! ui '(pipeline clock) x ty pipeline-clock-size
                pipeline-clock-size
      'tip "A lap is a refresh, the screen's at the top. The newest frames \
            wind out from their oldest input, or their tick, to the screen, \
            in the lanes' colors, the newest bright: the laps a frame takes \
            are the refreshes it shows old. The square on the rim is where \
            the latch falls.")
    (pipeline-draw-timeline (+ x pipeline-clock-size 8) ty
                            (- w pipeline-clock-size 8)
                            (pipeline-timeline-height) v)
    (pipeline-draw-readout (+ x pipeline-clock-size 8)
                           (+ ty (pipeline-timeline-height) 8)
                           (- w pipeline-clock-size 8)
                           (pipeline-latency-readout
                            (pipeline-timeline-last v)))
    (ui-region! ui '(pipeline timeline) (+ x pipeline-clock-size 8) ty
                (- w pipeline-clock-size 8) (pipeline-timeline-height)
      'tip "The last six refreshes as they went, a frame a color: its \
            oldest input, main drawing it, its wait in the box, core0's \
            wait for an image (a mark at the latch its tick aimed at), its \
            time on the screen, red where a refresh repeated. Lines are \
            the screen's refreshes. Held, it ends with the tick picked.")))

;; Latency's height over the River: its heading and the clock or the strip.
(define (pipeline-latency-height w)
  (let-values ([(gw gh) (ui-label-size '(group) "Latency" w)])
    (+ gh 4 (max pipeline-clock-size (pipeline-timeline-height)))))

;; The live strip beside the clock: the last six refreshes, each frame
;; across its lanes as it went, its oldest input, main's draw, its wait in
;; the box, core0's wait for an image, and its time on the screen, a
;; refresh repeated red; the refreshes the screen reported, and the latch
;; each tick aimed at. Held, it shows the frame of the tick picked.
(define pipeline-timeline-lanes '("input" "main" "box" "core0" "screen"))
(define pipeline-timeline-refreshes 6)

(define (pipeline-timeline-height)
  (+ 4 (* (length pipeline-timeline-lanes)
          (+ 4 (font-line-height 'ui-small)))))

;; The refresh clock's width and height.
(define pipeline-clock-size 150)

;; The frame the strip ends with: the picked tick's, held; else the newest.
(define (pipeline-timeline-last v)
  (let ([tick (and (pipeline-view-held? v) (pipeline-view-tick v))])
    (if (and tick (profile-tick-kept? tick) (pipeline-tick-drew? tick))
        (pipeline-tick-frame-index tick)
        (- *frame-ring-n* 1))))

;; When the strip ends (now-ns): a refresh after the newest frame shown
;; among the last few up to frame last; else a refresh after its publish.
(define (pipeline-timeline-end last r)
  (let loop ([i last] [k 0])
    (cond
      [(or (= k 8) (< i 0))
       (+ r (or (inspect-frame-at last 'publish) (now-ns)))]
      [(inspect-frame-at i 'shown) => (lambda (shown) (+ shown r))]
      [else (loop (- i 1) (+ k 1))])))

(define (pipeline-draw-timeline x y w h v)
  (let* ([r (host-frame-ns)]
         [span (* pipeline-timeline-refreshes r)]
         [last (pipeline-timeline-last v)]
         [end (pipeline-timeline-end last r)]
         [start (- end span)]
         [lh (+ 4 (font-line-height 'ui-small))]
         [gutter (+ 12 (text-widest pipeline-timeline-lanes 'ui-small))]
         [px (+ x gutter)]
         [pw (max 1 (- w gutter 4))]
         [at (lambda (t) (+ px (quotient (* (- (max start (min end t)) start)
                                            pw)
                                         span)))]
         [lane-y (lambda (k) (+ y 2 (* k lh)))]
         ;; a span of lane k, from t0 to t1, its part of the window
         [span! (lambda (k t0 t1 color)
                  (when (and t0 t1 (< t0 end) (> t1 start))
                    (let ([a (at t0)] [b (at t1)])
                      (fill-box a (+ (lane-y k) 2) (max 1 (- b a)) (- lh 4)
                                color))))])
    (ui-draw-surface x y w h '(well))
    (for-each (lambda (name k)
                (draw-text (+ x 6) (lane-y k) name 'text-faint 'ui-small))
              pipeline-timeline-lanes (iota (length pipeline-timeline-lanes)))
    ;; the refreshes, a reported one and a period apart from it
    (let ([seen (inspect-frame-at last 'shown)])
      (when seen
        (do ([t (- seen (* r (quotient (- seen start) r))) (+ t r)])
            ((> t end))
          (let ([a (at t)])
            (draw-line a (+ y 2) a (+ y h -2) 'chart-rule)))))
    (let loop ([i last] [next-shown #f])
      (let ([publish (inspect-frame-at i 'publish)])
        (when (and publish (> publish (- start (* 2 r))))
          (let ([input (or (inspect-frame-at i 'wl) (inspect-frame-at i 'sdl))]
                [tick (inspect-frame-at i 'tick)]
                [taken (inspect-frame-at i 'taken)]
                [acquired (inspect-frame-at i 'acquired)]
                [shown (inspect-frame-at i 'shown)]
                [aimed (inspect-frame-ref i 13)]
                [color (if (even? i) 'chart-8 'chart-5)])
            (when (and input tick (< start tick) (< input end))
              (let ([a (at input)])
                (fill-box (- a 2) (+ (lane-y 0) 3) 4 (- lh 6) 'chart-7)
                (draw-line a (+ (lane-y 0) (quotient lh 2)) (at tick)
                           (+ (lane-y 1) (quotient lh 2)) 'text-faint)))
            (span! 1 tick publish 'chart-1)
            (span! 2 publish taken 'chart-2)
            (span! 3 taken acquired 'chart-3)
            (when (and aimed (> aimed start) (< aimed end))
              (fill-box (- (at aimed) 1) (lane-y 3) 2 lh 'text))
            (when shown
              (let ([until (or next-shown end)])
                (span! 4 shown (min until (+ shown r)) color)
                ;; the screen showed it longer than a refresh: it froze
                (when (> until (+ shown (quotient (* 3 r) 2)))
                  (span! 4 (+ shown r) until 'chart-flag))))
            (loop (- i 1) (or shown next-shown))))))))

;; The refresh clock, left of the strip: a lap is a refresh, the screen's
;; at the top. The newest frames each wind out from their oldest input (or
;; their tick) to the screen, a lap a refresh, their parts in the lanes'
;; colors, the newest reported bright and the rest faint: how many laps a
;; frame takes is how many refreshes old it shows. A mark on the rim where
;; the latch falls.
(define pipeline-clock-frames 8)
(define pipeline-clock-steps 64)    ; points a lap
(define pipeline-clock-laps 3)      ; the most the clock holds
;; The unit circle, a point a step, from the top clockwise, scaled 4096.
(define pipeline-clock-unit
  (let ([v (make-vector (* 2 pipeline-clock-steps))])
    (do ([k 0 (+ k 1)]) ((= k pipeline-clock-steps) v)
      (let ([a (* 2 3.141592653589793 (/ k pipeline-clock-steps))])
        (vector-set! v (* 2 k) (exact (round (* 4096 (sin a)))))
        (vector-set! v (+ 1 (* 2 k)) (exact (round (* -4096 (cos a)))))))))

(define (pipeline-draw-refresh-clock x y d last)
  (let* ([r (host-frame-ns)]
         [cx (+ x (quotient d 2))] [cy (+ y (quotient d 2))]
         [rim (- (quotient d 2) 4)] [hub (quotient rim 4)]
         [ring (quotient (- rim hub) pipeline-clock-laps)]
         ;; the newest frame the screen reported on, and when it showed
         [newest (let loop ([i last] [k 0])
                   (and (< k 8) (>= i 0)
                        (if (inspect-frame-at i 'shown)
                            i
                            (loop (- i 1) (+ k 1)))))]
         [seen (and newest (inspect-frame-at newest 'shown))]
         [step (quotient r 16)])
    (stroke-circle cx cy hub 'chart-rule)
    (stroke-circle cx cy rim 'chart-rule)
    (when seen
      ;; a point t ns after from: k 0 its x, 1 its y; a lap a refresh out
      (let ([point (lambda (t from k)
                     (let ([unit (vector-ref
                                  pipeline-clock-unit
                                  (+ k (* 2 (quotient
                                             (* pipeline-clock-steps
                                                (modulo (- t seen) r))
                                             r))))]
                           [rad (if from
                                    (min rim
                                         (+ hub (quotient (* (- t from) ring)
                                                          r)))
                                    rim)])
                       (+ (if (= k 0) cx cy) (quotient (* rad unit) 4096))))])
        ;; the screen's refresh at the top; the latch on the rim
        (draw-line cx (- cy rim 3) cx (- cy rim -5) 'text 2)
        (when *pacer-latch*
          (fill-box (- (point *pacer-latch* #f 0) 3)
                    (- (point *pacer-latch* #f 1) 3) 6 6 'chart-3))
        ;; its age at the hub, in refreshes
        (let* ([from (or (inspect-frame-at newest 'wl)
                         (inspect-frame-at newest 'sdl)
                         (inspect-frame-at newest 'tick))]
               [laps (and from (format "~,1f" (/ (- seen from) r)))])
          (when laps
            (draw-text (- cx (quotient (text-width laps 'ui-small) 2))
                       (- cy (quotient (font-line-height 'ui-small) 2))
                       laps 'text 'ui-small)))
        (do ([i (- newest pipeline-clock-frames -1) (+ i 1)]) ((> i newest))
          (let ([from (or (inspect-frame-at i 'wl) (inspect-frame-at i 'sdl)
                          (inspect-frame-at i 'tick))]
                [shown (inspect-frame-at i 'shown)]
                [newest? (= i newest)])
            (when (and from shown (< from shown))
              (let wind ([t from]
                         [px (point from from 0)] [py (point from from 1)])
                (when (< t shown)
                  (let* ([u (min shown (+ t step))]
                         [nx (point u from 0)] [ny (point u from 1)])
                    (draw-line px py nx ny
                               (if newest?
                                   (pipeline-draw-clock-color i t)
                                   'text-faint)
                               (if newest? 3 1))
                    (wind u nx ny)))))))))))

;; The lane's color frame i is in at t: its input's wait, main's draw, the
;; box, the wait for an image, then the compositor and the screen.
(define (pipeline-draw-clock-color i t)
  (cond [(< t (or (inspect-frame-at i 'tick) 0)) 'chart-7]
        [(< t (or (inspect-frame-at i 'publish) 0)) 'chart-1]
        [(< t (or (inspect-frame-at i 'taken) 0)) 'chart-2]
        [(< t (or (inspect-frame-at i 'acquired) 0)) 'chart-3]
        [else 'chart-8]))

;; The numbers under the strip, of the newest frame the screen reported
;; on, and the pacer's now: (label . words) each.
(define (pipeline-latency-readout last)
  (let* ([r (host-frame-ns)]
         [i (let loop ([i last] [k 0])
              (and (< k 8) (>= i 0)
                   (if (inspect-frame-at i 'shown) i (loop (- i 1) (+ k 1)))))]
         [ms (lambda (a b)
               (if (and i (inspect-frame-at i a) (inspect-frame-at i b))
                   (format "~,1f ms" (/ (- (inspect-frame-at i b)
                                           (inspect-frame-at i a))
                                        1e6))
                   "–"))]
         [input (and i (if (inspect-frame-at i 'wl) 'wl 'sdl))])
    (list (cons "input to screen" (if input (ms input 'shown) "–"))
          (cons "publish to screen" (ms 'publish 'shown))
          (cons "in the box" (ms 'publish 'taken))
          (cons "for an image" (ms 'acquiring 'acquired))
          (cons "tick before latch" (format "~,1f ms" (/ *pacer-lead* 1e6)))
          (cons "margin" (format "~,1f ms" (/ *pacer-margin* 1e6)))
          (cons "latch before refresh"
                (if (and i *pacer-latch*)
                    (format "~,1f ms"
                            (/ (modulo (- (inspect-frame-at i 'shown)
                                          *pacer-latch*)
                                       r)
                               1e6))
                    "–")))))

(define (pipeline-draw-readout x y w items)
  (let ([cw (quotient w (length items))] [lh (font-line-height 'ui-small)])
    (for-each (lambda (item k)
                (let ([ix (+ x (* k cw))])
                  (draw-text ix y (car item) 'text-faint 'ui-small)
                  (draw-text ix (+ y lh 2) (cdr item) 'text 'ui)))
              items (iota (length items)))))

;;; ---- the Tape

;; A record's mark: as tall as the log of the pixels it may cover, 100 a
;; doubling, to 16M; in lanes, who drew it, and its kind.
(define pipeline-tape-top 2400)
(define pipeline-tape-rules '((1000 . "1K px") (2000 . "1M px")))
(define pipeline-tape-kinds '(box segment polygon glyph shadow))
(define pipeline-draw-tape-who
  '(chart-1 chart-2 chart-3 chart-4 chart-5 chart-6 chart-7 chart-8))
(define pipeline-draw-tape-lanes
  `(("who" ,@pipeline-draw-tape-who)
    ;; box segment polygon glyph shadow
    ("kind" text-faint chart-4 chart-5 text chart-muted-1)))
(define pipeline-draw-tape-stack '((0 . chart-share)))
(define pipeline-tape-lane-tips
  '("Who drew the record: the legend under the Tape says whose each color is."
    "The record's kind: text for a glyph, faint for a box, gray for a shadow, \
     a color for a line or a polygon."))

;; A Tape holding n records, its rows a power of two.
(define (pipeline-tape-new n)
  (ui-stream-new (let loop ([rows 2048]) (if (< rows n) (loop (* 2 rows)) rows))
                 1 pipeline-draw-tape-lanes))

;; The Tape's rows of list l, a vector a record of those kept: (reach who
;; kind), who and kind each its lane's color, from 1, or 0.
(define (pipeline-tape-rows v l kept)
  (let* ([n (inspect-list-count l)]
         [who (make-vector n 0)]
         [colors (length pipeline-draw-tape-who)]
         [kinds (length pipeline-tape-kinds)]
         [spans (inspect-list-labels l)])
    (for-each (lambda (span node)
                (let ([c (+ 1 (modulo (pipeline-color-index v node) colors))])
                  (do ([k (cadr span) (+ k 1)])
                      ((>= k (min n (+ (cadr span) (caddr span)))))
                    (vector-set! who k c))))
              spans (pipeline-span-nodes spans))
    (let ([rows (make-vector (vector-length kept))])
      (do ([j 0 (+ j 1)]) ((= j (vector-length kept)) rows)
        (let* ([i (vector-ref kept j)]
               [r (inspect-reach l i)]
               [area (max 1 (* (- (caddr r) (car r)) (- (cadddr r) (cadr r))))]
               [kind (memq (inspect-kind l i) pipeline-tape-kinds)])
          (vector-set! rows j
                       (vector (exact (round (* 100 (log area 2))))
                               (vector-ref who i)
                               (if kind (+ 1 (- kinds (length kind))) 0))))))))

;; The Tape holds the records kept of the list on view: sent again when
;; they're others.
(define (pipeline-tape-send! v)
  (let ([kept (pipeline-kept v)])
    (unless (eq? kept (pipeline-view-tape-of v))
      (let ([n (vector-length kept)])
        (when (> n (ui-stream-rows (pipeline-view-tape v)))
          (ui-stream-release! (pipeline-view-tape v))
          (pipeline-view-tape-set! v (pipeline-tape-new n)))
        (let ([tape (pipeline-view-tape v)])
          (ui-stream-restart! tape)
          (when (> n 0)
            (let ([rows (pipeline-tape-rows v (pipeline-view-shown v)
                                            kept)])
              (ui-stream-send! tape 0 (- n 1)
                               (lambda (seq j)
                                 (vector-ref (vector-ref rows seq) j))))))
        (pipeline-view-tape-of-set! v kept)))))

(define (pipeline-tape-tip l i)
  (let ([label (inspect-label-at l i)])
    (format "record ~a, a ~a: ~a, ~a~a" i (inspect-kind l i)
            (inspect-what l i)
            (inspect-paint-text (inspect-record-paint l i))
            (if label (format "\ndrawn by ~a" label) ""))))

;; The marks on the Tape, where its records are: what's selected, and those at
;; the pixel traced, but those left out.
(define (pipeline-tape-marked v)
  (let* ([n (inspect-list-count (pipeline-view-shown v))]
         [kept (pipeline-kept v)]
         [selected (pipeline-view-selected v)]
         [first (and selected (pipeline-node-first v selected))]
         [traced (pipeline-view-traced v)])
    (fold-right
     (lambda (i acc)
       (let ([at (and (< i n) (pipeline-kept-at kept i))])
         (if at (cons at acc) acc)))
     '()
     (append
      (if (and first (< first n))
          (map (lambda (k) (+ first k))
               (iota (min (pipeline-node-count v selected) (- n first))))
          '())
      (if traced
          (map (lambda (node) (pipeline-node-first v node)) (caddr traced))
          '())))))

;; The small screen draws as far as k records, the last of them selected.
(define (pipeline-draw-upto! v k)
  (let* ([l (pipeline-view-shown v)] [n (inspect-list-count l)]
         [k (max 0 (min k n))])
    (pipeline-view-upto-set! v (and (< k n) k))
    (when (> k 0)
      (pipeline-view-selected-set! v (car (inspect-rows l (- k 1) 1))))
    (pipeline-preview! v)))

;; A press on the Tape, or its stepper: the frame stays, drawn as far as there.
(define (pipeline-tape-go! v k)
  (pipeline-hold! v)
  (pipeline-view-playing-set! v #f)
  (pipeline-draw-upto! v k))

;; Play goes through the records kept, from where the drawing stops: how far
;; it has is a place on the Tape.
(define (pipeline-play-toggle! v)
  (if (pipeline-view-playing v)
      (pipeline-view-playing-set! v #f)
      (let ([n (vector-length (pipeline-kept v))]
            [at (pipeline-tape-upto v)])
        (pipeline-hold! v)
        (pipeline-view-playing-set! v (if (< at n) at 0))
        (pipeline-draw-upto! v (pipeline-kept-upto
                                v (pipeline-view-playing v))))))

;; A tick of Play: on, by the share of the frame a tick of play-secs is.
(define (pipeline-play-tick! v)
  (let* ([n (vector-length (pipeline-kept v))]
         [at (+ (pipeline-view-playing v)
                (/ (* n (pacer-period))
                   (* (pipeline-view-play-secs v) 1000000000)))])
    (if (>= at n)
        (begin (pipeline-view-playing-set! v #f)
               (pipeline-draw-upto! v (pipeline-kept-upto v n)))
        (begin (pipeline-view-playing-set! v at)
               (pipeline-draw-upto! v (pipeline-kept-upto
                                       v (exact (floor at))))))))

;; Where the drawing stops: a line after the last record drawn.
(define (pipeline-draw-tape-at areas count upto)
  (let-values ([(bx bw) (ui-bar-chart-bar areas count (max 0 (- upto 1)))])
    (let ([plot (cdr (assq 'plot areas))])
      (fill-box (- (if (> upto 0) (+ bx bw) bx) 1) (cadr plot) 2 (cadddr plot)
                'accent))))

;; A drawer's color, kept while the Pipeline is open: the next free one the
;; first time it's seen, not its place, which moves when a window is raised.
(define (pipeline-color-index v node)
  (let ([colors (pipeline-view-colors v)])
    (or (hashtable-ref colors node #f)
        (let ([i (hashtable-size colors)])
          (hashtable-set! colors node i)
          i))))

;; Whose each color is, but the spans left out, which keep their colors.
(define (pipeline-tape-keys v)
  (let ([spans (pipeline-view-groups v)] [off (pipeline-view-off v)])
    (fold-right (lambda (span node acc)
                  (if (member node off)
                      acc
                      (cons (cons (pipeline-draw-who-color
                                   (pipeline-color-index v node))
                                  (pipeline-node-name span))
                            acc)))
                '() spans (pipeline-span-nodes spans))))

(define (pipeline-tape-height v w)
  (let-values ([(kw kh) (ui-legend-size (pipeline-tape-keys v))])
    (+ (ui-control-height) 4 (ui-stream-room pipeline-draw-tape-lanes) 40 4
       kh)))

;; Its heading and what plays it, the Tape, its legend.
(define (pipeline-tape-pane v x y w h)
  (let*-values
      ([(ui) (pipeline-view-ui v)]
       [(l) (pipeline-view-shown v)]
       [(kept) (pipeline-kept v)]
       [(n) (vector-length kept)]
       [(upto) (pipeline-view-upto v)]
       [(ch) (ui-control-height)]
       [(keys) (pipeline-tape-keys v)]
       [(kw kh) (ui-legend-size keys)]
       [(gw gh) (ui-label-size '(group) "Tape" w)]
       [(sy) (+ y ch 4)]
       [(sh) (- h ch 4 4 kh)]
       [(label!) (lambda (lx text)
                   (let ([tw (+ 8 (text-width text 'ui))])
                     (ui-draw-label lx y tw ch '(dim) text)
                     (+ lx tw)))])
    (pipeline-tape-send! v)
    (ui-draw-label x y gw ch '(group) "Tape")
    (let* ([px (+ x gw 16)]
           [pw (max 64 (+ 24 (text-width "Pause" 'ui)))]
           [lx (label! (+ px pw 12) "Drawn")]
           [sw (ui-stepper ui '(pipeline drawn) lx y (pipeline-tape-upto v)
                           0 n
                           (lambda (k)
                             (pipeline-tape-go! v (pipeline-kept-upto v k)))
                           'tip "How many of the frame's records the small \
                                 screen draws, in their order: an arrow steps \
                                 one record")]
           [lx (label! (+ lx sw 8) (format "of ~a records, played in" n))]
           [sw (ui-stepper ui '(pipeline play-secs) lx y
                           (pipeline-view-play-secs v) 1 60
                           (lambda (s) (pipeline-view-play-secs-set! v s))
                           'tip "How long Play takes over the whole frame")]
           [lx (label! (+ lx sw 8) "s")])
      (ui-button ui '(pipeline play) px y pw ch
                 (if (pipeline-view-playing v) "Pause" "Play")
                 (lambda () (pipeline-play-toggle! v))
                 'tip "Draw the frame on the small screen record by record, \
                       holding it")
      (pipeline-tape-caption v ui lx y (- (+ x w) lx) ch))
    (ui-stream ui 'pipeline-tape (pipeline-view-tape v) x sy w sh
               (and (> n 0) (- n 1)) 0 pipeline-tape-top pipeline-tape-rules
               pipeline-draw-tape-stack 1
               'fit #t
               'doc '((L . "Draw as far as this record"))
               'strip-tips pipeline-tape-lane-tips
               'tip (lambda (i)
                      (and (< i n) (pipeline-tape-tip l (vector-ref kept i))))
               'on-pick (lambda (i)
                          (pipeline-tape-go! v (pipeline-kept-upto v (+ i 1))))
               'marked (pipeline-tape-marked v)
               'over (lambda (areas count)
                       (when upto
                         (pipeline-draw-tape-at areas count
                                                (pipeline-tape-upto v)))))
    (ui-draw-legend x (+ sy sh 4) w kh '() keys)))

;;; ---- left out

;; A span whose checkbox is off is left out of the small screen and the Tape.
;; Its records in spans: ((first . count) ...), in order.
(define (pipeline-left-out off spans)
  (fold-right (lambda (span node acc)
                (if (member node off)
                    (cons (cons (cadr span) (caddr span)) acc)
                    acc))
              '() spans (pipeline-span-nodes spans)))

;; For the small screen, or #f when none is, so that a live frame's labels
;; aren't read for nothing.
(define (pipeline-left-out-of v)
  (let ([off (pipeline-view-off v)])
    (and (pair? off) (lambda (spans) (pipeline-left-out off spans)))))

(define (pipeline-show-span! v node on?)
  (pipeline-view-off-set! v (if on?
                                (remove node (pipeline-view-off v))
                                (cons node (pipeline-view-off v))))
  (pipeline-view-kept-of-set! v #f)
  (pipeline-preview! v))

(define (pipeline-node-off? v node)
  (let ([off (pipeline-view-off v)])
    (and (pair? off)
         (if (pair? node)
             (and (member node off) #t)
             (let ([i (vector-ref node 0)])
               (exists (lambda (r) (< -1 (- i (car r)) (cdr r)))
                       (pipeline-left-out off (pipeline-view-groups v))))))))

;; The records drawn of the list on view, but those left out: a vector, in
;; order, what the Tape and Play go through.
(define (pipeline-kept v)
  (let ([l (pipeline-view-shown v)])
    (unless (eq? l (pipeline-view-kept-of v))
      (let* ([n (inspect-list-count l)]
             [out (pipeline-left-out (pipeline-view-off v)
                                     (inspect-list-labels l))]
             [kept (make-vector (- n (apply + (map cdr out))))])
        (let loop ([i 0] [j 0] [out out])
          (cond [(= i n)]
                [(and (pair? out) (= i (caar out)))
                 (loop (+ i (cdar out)) j (cdr out))]
                [else (vector-set! kept j i) (loop (+ i 1) (+ j 1) out)]))
        (pipeline-view-kept-set! v kept)
        (pipeline-view-kept-of-set! v l)))
    (pipeline-view-kept v)))

;; How many of kept come before record i, kept being in order.
(define (pipeline-kept-below kept i)
  (let loop ([lo 0] [hi (vector-length kept)])
    (if (< lo hi)
        (let ([mid (quotient (+ lo hi) 2)])
          (if (< (vector-ref kept mid) i) (loop (+ mid 1) hi) (loop lo mid)))
        lo)))

;; Where record i is on the Tape, or #f when it's left out.
(define (pipeline-kept-at kept i)
  (let ([at (pipeline-kept-below kept i)])
    (and (< at (vector-length kept)) (= (vector-ref kept at) i) at)))

;; As far as k of the Tape's records, as far as which of the list's: all of
;; them at its end.
(define (pipeline-kept-upto v k)
  (let ([kept (pipeline-kept v)])
    (cond [(<= k 0) 0]
          [(>= k (vector-length kept))
           (inspect-list-count (pipeline-view-shown v))]
          [else (+ 1 (vector-ref kept (- k 1)))])))

;; How far the drawing goes on the Tape.
(define (pipeline-tape-upto v)
  (let ([kept (pipeline-kept v)] [upto (pipeline-view-upto v)])
    (if upto (pipeline-kept-below kept upto) (vector-length kept))))

;; The records drawn at a device pixel, the one on top first.
(define (pipeline-records-at v x y)
  (let ([kept (pipeline-kept v)])
    (filter (lambda (i) (pipeline-kept-at kept i))
            (inspect-records-at (pipeline-view-shown v) x y))))

;;; ---- what the tree holds

;; A node is a label's span or a row of it (a vector). A span's node is its
;; label and which of that label's spans it is, (label k), not where it is:
;; records before it and in it come and go (a caret blinks, the clock ticks),
;; and a span opened or selected stays so. Its records are looked up in the
;; list on view.
(define (pipeline-span-nodes spans)
  (let loop ([spans spans] [seen '()] [acc '()])
    (if (null? spans)
        (reverse acc)
        (let ([label (caar spans)])
          (loop (cdr spans) (cons label seen)
                (cons (list label (length (filter (lambda (l)
                                                    (equal? l label))
                                                  seen)))
                      acc))))))

;; The span of node (label k) among spans, (label first count), or #f when
;; it's gone.
(define (pipeline-span-in spans node)
  (let loop ([spans spans] [k (cadr node)])
    (cond [(null? spans) #f]
          [(not (equal? (caar spans) (car node))) (loop (cdr spans) k)]
          [(zero? k) (car spans)]
          [else (loop (cdr spans) (- k 1))])))

(define (pipeline-node-span v node)
  (pipeline-span-in (pipeline-view-groups v) node))

;; The node of the span that holds record i of the list on view, or #f.
(define (pipeline-span-node-at v i)
  (let loop ([spans (pipeline-view-groups v)]
             [nodes (pipeline-span-nodes (pipeline-view-groups v))])
    (cond [(null? spans) #f]
          [(< -1 (- i (cadar spans)) (caddar spans)) (car nodes)]
          [else (loop (cdr spans) (cdr nodes))])))

;; Who drew what's selected: its span's node, a record's being its span's.
(define (pipeline-selected-span v)
  (let ([selected (pipeline-view-selected v)])
    (cond [(not selected) #f]
          [(pair? selected) selected]
          [else (pipeline-span-node-at v (vector-ref selected 0))])))

(define (pipeline-children v node)
  (let ([span (and (pair? node) (pipeline-node-span v node))])
    (if span
        (inspect-rows (pipeline-view-shown v) (cadr span) (caddr span))
        '())))

;; Where a node's records start and how many, or #f for a span that's gone.
(define (pipeline-node-first v node)
  (if (pair? node)
      (let ([span (pipeline-node-span v node)]) (and span (cadr span)))
      (vector-ref node 0)))
(define (pipeline-node-count v node)
  (if (pair? node)
      (let ([span (pipeline-node-span v node)]) (and span (caddr span)))
      (vector-ref node 1)))

(define (pipeline-node-name node)
  (cond [(pair? node)
         (let ([label (car node)])
           (if (string? label) label (format "~a" label)))]
        [else (format "~a" (vector-ref node 2))]))

;; What a node is: a record's decoding; a drawer's lists, each its part and
;; how many records it holds; or the screen's, for a drawer drawn on it.
(define (pipeline-node-what v node)
  (if (pair? node)
      (let ([span (pipeline-node-span v node)])
        (let ([lists (and span
                          (inspect-span-lists (pipeline-view-shown v)
                                              (cadr span) (caddr span)))])
          (cond [(not span) ""]
                [(null? lists) "the screen's list"]
                [else (pipeline-lists-text lists)])))
      (vector-ref node 3)))

(define (pipeline-lists-text lists)
  (fold-left (lambda (text lst)
               (format "~a~a~a ~a records" text (if (equal? text "") "" ", ")
                       (inspect-list-part lst)
                       (cdr (assq 'records (inspect-list-facts lst)))))
             "" lists))

;; Whether lst, of the frame on view, wasn't in the frame before: a list
;; unchanged is the same copy in both.
(define (pipeline-list-changed? v lst)
  (let* ([l (pipeline-view-shown v)]
         [before (inspect-history-ref (pipeline-view-history v)
                                      (- (inspect-list-frame l) 1))])
    (and before (not (memq lst (inspect-list-lists before))))))

;; How long ago, on now-ns's clock, ns was.
(define (pipeline-ago ns)
  (let ([d (- (now-ns) ns)])
    (if (< d 1000000000)
        (format "~a ms ago" (quotient d 1000000))
        (format "~,1f s ago" (/ d 1e9)))))

;; The records at a device pixel, as nodes.
(define (pipeline-trace! v x y)
  (let* ([l (pipeline-view-shown v)]
         [rows (map (lambda (i) (car (inspect-rows l i 1)))
                    (pipeline-records-at v x y))])
    (pipeline-view-traced-set! v (list x y rows))
    (unless (null? rows) (pipeline-select! v (car rows)))))

;;; ---- what's selected: a drawer or a record, shown and named everywhere

;; Selects node, a drawer's or a record's, or nothing (#f), the small screen
;; and both windows drawn again for it.
(define (pipeline-select! v node)
  (pipeline-view-selected-set! v node)
  (pipeline-preview! v)
  (for-each (lambda (win) (when win (invalidate! win)))
            (list (find-window 'pipeline) (pipeline-view-popped v))))

;; Where a selected record is: its drawer's node and how far into its span,
;; so that it stays with its drawer as records before it come and go, or the
;; frame changes. #f for none, or a drawer selected.
(define (pipeline-selected-place v)
  (let ([selected (pipeline-view-selected v)])
    (and (vector? selected)
         (let ([node (pipeline-span-node-at v (vector-ref selected 0))])
           (and node
                (cons node (- (vector-ref selected 0)
                              (cadr (pipeline-node-span v node)))))))))

;; The record at place in the list on view; its drawer when its span is
;; shorter now; #f when the drawer's gone.
(define (pipeline-place-row v place)
  (let ([span (pipeline-node-span v (car place))])
    (cond [(not span) #f]
          [(< (cdr place) (caddr span))
           (car (inspect-rows (pipeline-view-shown v)
                              (+ (cadr span) (cdr place)) 1))]
          [else (car place)])))

;; What the tree shows selected: a record's row whole, the run of glyphs
;; it's in.
(define (pipeline-tree-selected v)
  (let ([selected (pipeline-view-selected v)])
    (if (vector? selected)
        (let* ([i (vector-ref selected 0)]
               [node (pipeline-span-node-at v i)]
               [span (and node (pipeline-node-span v node))])
          (or (and span
                   (find (lambda (row)
                           (< -1 (- i (vector-ref row 0)) (vector-ref row 1)))
                         (inspect-rows (pipeline-view-shown v) (cadr span)
                                       (caddr span))))
              selected))
        selected)))

;; What's selected, in words, or #f.
(define (pipeline-selected-text v)
  (let ([selected (pipeline-view-selected v)])
    (cond
      [(not selected) #f]
      [(pair? selected)
       (let ([span (pipeline-node-span v selected)])
         (if span
             (format "~a, records ~a–~a" (pipeline-node-name selected)
                     (cadr span) (+ (cadr span) (caddr span) -1))
             (format "~a, not in this frame" (pipeline-node-name selected))))]
      [else
       (let* ([i (vector-ref selected 0)] [n (vector-ref selected 1)]
              [kind (vector-ref selected 2)]
              [who (pipeline-span-node-at v i)])
         (format "~a, ~a~a"
                 (if (> n 1)
                     (format "records ~a–~a" i (+ i n -1))
                     (format "record ~a" i))
                 (if (eq? kind 'text)
                     (format "text “~a”" (vector-ref selected 3))
                     (format "a ~a" kind))
                 (if who (format " by ~a" (pipeline-node-name who)) "")))])))

;; The Tape's heading, at its right: what's selected and a button that
;; clears it, or, with nothing selected, what the Tape is.
(define (pipeline-tape-caption v ui x y w h)
  (let ([text (pipeline-selected-text v)])
    (if text
        (let* ([bw (+ 24 (text-width "Clear" 'ui))] [bx (- (+ x w) bw)])
          (ui-draw-label x y (max 0 (- bx 8 x)) h '(right)
                         (string-append "Selected: " text))
          (ui-button ui '(pipeline unselect) bx y bw h "Clear"
                     (lambda () (pipeline-select! v #f))
                     'tip "Select nothing (Esc)"))
        (ui-draw-label x y (max 0 w) h '(dim right)
                       "a mark a record, in draw order"))))

;; The tree opens the drawer of a record selected, and scrolls it into view,
;; and closes the one it opened for the record before; one opened by hand
;; stays open.
(define (pipeline-tree-open! ui node)
  (let ([id '(pipeline tree)] [was (ui-memo ui '(pipeline opened) #f)])
    (unless (equal? was node)
      (let ([states (ui-tree-states ui id)])
        (when (and was (eq? (hashtable-ref states was 'unset) #t))
          (ui-tree-expand! ui id was #f))
        (if (eq? (hashtable-ref states node 'unset) #t)
            (ui-memo! ui '(pipeline opened) #f)
            (begin (ui-tree-expand! ui id node #t)
                   (ui-memo! ui '(pipeline opened) node)))))))

;; Esc, in either window, selects nothing.
;; Esc: the selection cleared, or with none, the flow going on again.
(define (pipeline-key v win key mods)
  (and (eq? key 'escape) (null? mods)
       (cond [(pipeline-view-selected v) (pipeline-select! v #f) #t]
             [(pipeline-view-held? v) (pipeline-resume! v) #t]
             [else #f])))

;;; ---- who: what each drew cost

;; The profiler's name for who drew a span: a surface by its name, a window by
;; its id, found by its title among the windows drawn, the k-th of that title;
;; #f for a window gone since.
(define (pipeline-span-subject node)
  (let ([label (car node)])
    (if (symbol? label)
        label
        (let ([same (filter (lambda (w)
                              (and (visible? w)
                                   (equal? (window-title w) label)))
                            (reverse (windows)))])
          (and (< (cadr node) (length same))
               (profile-subject-of (list-ref same (cadr node))))))))

;; What main took to draw who subject is, a surface's draw or a window's frame
;; and its app's draw: ms a frame, over the last 30 ticks to tick newest that
;; drew it, of those the profiler keeps; #f when none did. A frame, not a
;; tick, so that a pause, held or idle, doesn't read as nothing.
(define (pipeline-drawing-ms subject newest)
  (let loop ([seq newest] [n 0] [ms 0.0])
    (if (or (fx= n 30) (not (profile-tick-kept? seq)))
        (and (fx> n 0) (/ ms n))
        (let ([t (+ (profile-tick-node-ms seq (list subject #f 'render))
                    (if (pair? subject)
                        (profile-tick-node-ms seq (list subject 'draw 'render))
                        0.0))])
          (if (> t 0)
              (loop (fx- seq 1) (fx+ n 1) (+ ms t))
              (loop (fx- seq 1) n ms))))))

;; What each span of the list on view cost, in draw order, a row each:
;; #(node i ms records pixels runs changed redrawn same marks), i its
;; color's index, ms what main took to draw it a frame, up to the frame's
;; tick, or #f, changed how many of its records differ from the frame
;; before's, #f when that one isn't kept; redrawn, same and marks as
;; pipeline-redraws says. Made again for each list.
(define (pipeline-who-rows v)
  (let ([l (pipeline-view-shown v)] [who (pipeline-view-who v)])
    (if (and who (eq? (car who) l))
        (cdr who)
        (let*-values
            ([(spans) (inspect-list-labels l)]
             [(before) (inspect-history-ref (pipeline-view-history v)
                                            (- (inspect-list-frame l) 1))]
             [(newest) (or (pipeline-view-tick v) (profile-newest-tick))]
             [(n copies) (inspect-history-copies (pipeline-view-history v)
                                                 (inspect-list-frame l))]
             [(row)
              (lambda (span node i)
                (let-values ([(pixels runs)
                              (inspect-span-cost l (cadr span) (caddr span))]
                             [(redrawn same marks)
                              (pipeline-redraws
                               n (map (lambda (lst)
                                        (hashtable-ref
                                         copies (inspect-list-original lst)
                                         #f))
                                      (inspect-span-lists l (cadr span)
                                                          (caddr span))))])
                  (let ([subject (pipeline-span-subject node)]
                        [b (and before
                                (pipeline-span-in
                                 (inspect-list-labels before) node))])
                    (vector node i
                            (and subject newest
                                 (pipeline-drawing-ms subject newest))
                            (caddr span) pixels runs
                            (and b (inspect-span-changed
                                    l (cadr span) (caddr span)
                                    before (cadr b) (caddr b)))
                            redrawn same marks))))]
             [(nodes) (pipeline-span-nodes spans)]
             [(rows) (map row spans nodes
                          (map (lambda (n) (pipeline-color-index v n))
                               nodes))])
          (pipeline-view-who-set! v (cons l rows))
          rows))))

;; How often a drawer was recorded again in the n frames kept, from its
;; lists' copies, a vector of n each, #f for a list not kept: (values
;; redrawn same marks), redrawn in how many frames one of its lists was
;; another copy than the frame before's, same in how many of those each such
;; copy held the very same records, and marks a frame's: 0, not redrawn, 1,
;; redrawn, 2, redrawn the same. Redrawn is #f with fewer than two frames or
;; no list of its own; same, while it wasn't redrawn.
(define (pipeline-redraws n copies)
  (let ([copies (filter values copies)] [marks (make-vector n 0)])
    (if (or (< n 2) (null? copies))
        (values #f #f marks)
        (let loop ([k 1] [redrawn 0] [same 0])
          (if (= k n)
              (values redrawn (and (> redrawn 0) same) marks)
              (let ([new (filter (lambda (v)
                                   (let ([a (vector-ref v (- k 1))]
                                         [b (vector-ref v k)])
                                     (and a b (not (eq? a b)))))
                                 copies)])
                (cond
                  [(null? new) (loop (+ k 1) redrawn same)]
                  [(for-all (lambda (v)
                              (eq? (inspect-list-basis (vector-ref v k))
                                   (inspect-list-basis
                                    (vector-ref v (- k 1)))))
                            new)
                   (vector-set! marks k 2)
                   (loop (+ k 1) (+ redrawn 1) (+ same 1))]
                  [else
                   (vector-set! marks k 1)
                   (loop (+ k 1) (+ redrawn 1) same)])))))))

;; A count of pixels, short.
(define (pipeline-pixels-text n)
  (cond [(>= n 1000000) (format "~,1f M" (/ n 1000000.0))]
        [(>= n 10000) (format "~a K" (round (/ n 1000)))]
        [else (number->string n)]))

;; Where a row keeps a column's number.
(define (pipeline-who-field key)
  (case key
    [(ms) 2]
    [(records) 3]
    [(pixels) 4]
    [(runs) 5]
    [(changed) 6]
    [(redrawn) 7]
    [else 8]))

;; A row's cell's text, and its share of its column's most, for its bar.
(define (pipeline-who-cell row key most)
  (let* ([records (vector-ref row 3)]
         [k (pipeline-who-field key)]
         [n (vector-ref row k)]
         [share (and n (> (most k) 0) (/ n (most k)))])
    (case key
      [(ms) (values (if n (format "~,2f" n) "—") share)]
      [(redrawn same) (values (if n (number->string n) "—") #f)]
      [(pixels) (values (pipeline-pixels-text n) share)]
      [(changed)
       (if (and n (> records 0))
           (values (format "~a%" (round (/ (* 100 n) records)))
                   (/ n records))
           (values "—" #f))]
      [else (values (number->string n) share)])))

;; Who's rows sorted ((key . up|down), or #f: in draw order) by what their
;; cells say, changed by its share; a row whose cell has nothing to say
;; last, either way.
(define (pipeline-who-sorted rows sort)
  (define (value row)
    (let ([key (car sort)])
      (case key
        [(name) (pipeline-node-name (vector-ref row 0))]
        [(changed)
         (let ([n (vector-ref row 6)] [records (vector-ref row 3)])
           (and n (> records 0) (/ n records)))]
        [else (vector-ref row (pipeline-who-field key))])))
  (if (not sort)
      rows
      (let ([up? (eq? (cdr sort) 'up)])
        (list-sort (lambda (a b)
                     (let ([x (value a)] [y (value b)])
                       (cond [(not x) #f]
                             [(not y) #t]
                             [(string? x)
                              (if up? (string<? x y) (string>? x y))]
                             [else (if up? (< x y) (> x y))])))
                   rows))))

;; Who: a row a drawer, in draw order or as sorted, what it cost; its
;; checkbox leaves it out as the tree's does, and selecting it selects its
;; span everywhere.
(define (pipeline-who-pane v x y w h)
  (let* ([ui (pipeline-view-ui v)]
         [rows (pipeline-who-sorted (pipeline-who-rows v)
                                    (pipeline-view-who-sort v))]
         [most (lambda (k)
                 (fold-left (lambda (m r) (max m (or (vector-ref r k) 0)))
                            0 rows))]
         [span (pipeline-selected-span v)]
         [columns
          `((name "Who" ,(max 140 (- (ui-table-room w) 72 76 84 60 84 84 64
                                     32)))
            (ms "Main" 72 right
                "What main took to draw it, ms a frame over its last 30")
            (records "Records" 76 right)
            (pixels "Pixels" 84 right
                    "What its records may touch: the pixels the GPU shades, \
                     a pixel each time a record covers it")
            (runs "Runs" 60 right
                  "The runs that start among its records: a draw call each, \
                   and a new one where a record needs another shader")
            (changed "Changed" 84 right
                     "Its records that differ from the frame before")
            (redrawn "Redrawn" 84 right
                     "In how many of the frames kept, up to this one, it was \
                      recorded again: a mark each, the oldest left")
            (same "Same" 64 right
                  "How many of those recorded the very same records again: \
                   work for nothing"))]
         [cell (lambda (row key cx cy cw ch flags)
                 (if (eq? key 'name)
                     (pipeline-draw-who-name
                      cx cy cw ch flags (vector-ref row 1)
                      (pipeline-node-name (vector-ref row 0)))
                     (let-values ([(text share) (pipeline-who-cell row key
                                                                   most)])
                       (case key
                         [(redrawn)
                          (pipeline-draw-marks cx cy cw ch (vector-ref row 9)
                                               1)]
                         [(same)
                          (pipeline-draw-marks cx cy cw ch (vector-ref row 9)
                                               2)]
                         [else
                          (when share
                            (pipeline-draw-share cx cy cw ch share))])
                       (ui-draw-cell cx cy cw ch flags text))))])
    (ui-table ui '(pipeline who) x y w h columns rows
              (find (lambda (r) (equal? (vector-ref r 0) span)) rows)
              (lambda (row) (pipeline-select! v (vector-ref row 0)))
              cell
              'checked (lambda (row)
                         (not (member (vector-ref row 0)
                                      (pipeline-view-off v))))
              'on-check (lambda (row)
                          (let ([node (vector-ref row 0)])
                            (pipeline-show-span!
                             v node
                             (and (member node (pipeline-view-off v)) #t))))
              'sort (pipeline-view-who-sort v)
              'on-sort (lambda (key)
                         (pipeline-view-who-sort-set!
                          v (pipeline-sort-next (pipeline-view-who-sort v)
                                                key))))))

;; The small screen showing list l another way than its picture, each record
;; solid in a color of what's asked: who drew it, the others dim while a
;; drawer's selected; its kind; or whether it changed since the frame
;; before. Heat adds a little of one color a record, so that a pixel is as
;; bright as how many records cover it.
(define (pipeline-painted v l)
  (let ([into (pipeline-view-painted v)] [n (inspect-list-count l)])
    (case (pipeline-view-look v)
      [(heat) (inspect-list-paint! into l (lambda (i) (pipeline-draw-heat-word))
                                   3)]
      [(kind)
       (let ([words (pipeline-draw-kind-words)])
         (inspect-list-paint!
          into l
          (lambda (i)
            (cdr (assq (inspect-kind l i) words)))
          0))]
      [(changed)
       (let ([marks (pipeline-changed-marks v l)])
         (let-values ([(new same) (pipeline-draw-changed-words)])
           (inspect-list-paint! into l
                                (lambda (i) (if (vector-ref marks i) new same))
                                0)))]
      [else
       (let-values ([(words other)
                     (pipeline-draw-who-words v (inspect-list-labels l)
                                              (pipeline-selected-span v))])
         (let ([by (make-vector n other)])
           (for-each (lambda (span w)
                       (do ([i (cadr span) (+ i 1)])
                           ((>= i (min n (+ (cadr span) (caddr span)))))
                         (vector-set! by i w)))
                     (inspect-list-labels l) words)
           (inspect-list-paint! into l (lambda (i) (vector-ref by i)) 0)))])))

;; Which records of l differ from the frame before's, a vector of booleans:
;; each compared with the record at its place in its drawer's span then, a
;; record past that span's, or of a drawer new since, changed; all of them
;; when the frame before isn't kept.
(define (pipeline-changed-marks v l)
  (let* ([n (inspect-list-count l)]
         [before (inspect-history-ref (pipeline-view-history v)
                                      (- (inspect-list-frame l) 1))]
         [marks (make-vector n (not before))])
    (when before
      (let ([spans (inspect-list-labels l)])
        (for-each
         (lambda (span node)
           (let ([b (pipeline-span-in (inspect-list-labels before) node)])
             (do ([k 0 (+ k 1)]) ((>= k (caddr span)))
               (let ([i (+ (cadr span) k)])
                 (when (< i n)
                   (vector-set! marks i
                                (or (not b) (>= k (caddr b))
                                    (not (inspect-record-same?
                                          l i before (+ (cadr b) k))))))))))
         spans (pipeline-span-nodes spans))))
    marks))

;;; ---- course: a tick's stages, in order, as wide as their time

;; The tick to lay out: the one picked on the River, or the newest kept that
;; drew a frame; #f when none is kept.
(define (pipeline-course-tick v)
  (or (pipeline-view-tick v)
      (let ([newest (profile-newest-tick)])
        (and newest
             (let loop ([seq newest] [left 30])
               (cond [(or (zero? left) (not (profile-tick-kept? seq))) newest]
                     [(> (pipeline-phase-ms (profile-tick-uses seq) 'render)
                         0.0)
                      seq]
                     [else (loop (- seq 1) (- left 1))]))))))

(define (pipeline-phase-ms uses phase)
  (fold-left (lambda (ms u)
               (if (eq? (profile-use-phase u) phase)
                   (+ ms (profile-use-ms u))
                   ms))
             0.0 uses))

;; What subject took to draw in uses, a tick's, ms.
(define (pipeline-render-ms uses subject)
  (fold-left (lambda (ms u)
               (if (and (eq? (profile-use-phase u) 'render)
                        (equal? (profile-use-subject u) subject))
                   (+ ms (profile-use-ms u))
                   ms))
             0.0 uses))

;; What a tick spent, in order: (name ms kind detail) each, kind phase (a
;; phase of monitor-phases), drawer (detail its span's node: render, its
;; draw), gpu (the rest of render: the list to the GPU and its wait) or idle
;; (what's left of the period).
(define (pipeline-course-items v seq)
  (let* ([uses (profile-tick-uses seq)]
         [spans (inspect-list-labels (pipeline-view-shown v))]
         [period (/ (pacer-period) 1e6)]
         [stages
          (apply append
                 (map (lambda (p)
                        (let ([ms (pipeline-phase-ms uses (car p))])
                          (cond
                            [(not (eq? (car p) 'render))
                             (if (> ms 0.0)
                                 (list (list (cddr p) ms 'phase (car p)))
                                 '())]
                            [else
                             (let* ([drawers
                                     (map (lambda (node)
                                            (list (pipeline-node-name node)
                                                  (pipeline-render-ms
                                                   uses
                                                   (pipeline-span-subject
                                                    node))
                                                  'drawer node))
                                          (pipeline-span-nodes spans))]
                                    [drawn (fold-left (lambda (m d)
                                                        (+ m (cadr d)))
                                                      0.0 drawers)])
                               (append (list (list (cddr p) ms 'total
                                                   'render))
                                       drawers
                                       (list (list "to the GPU"
                                                   (max 0.0 (- ms drawn))
                                                   'gpu 'render))))])))
                      (remp (lambda (p) (memq (car p)
                                              '(input-wait vsync-wait)))
                            monitor-phases)))]
         [busy (fold-left (lambda (m it)
                            (if (eq? (caddr it) 'total) m (+ m (cadr it))))
                          0.0 stages)])
    (append stages
            (list (list "till the next tick" (max 0.0 (- period busy))
                        'idle #f)))))

;; Course's items sorted ((key . up|down), or #f: as they come): the
;; stages among themselves, and render's parts, under it, among
;; themselves.
(define (pipeline-course-sorted items sort)
  (define (part? it) (memq (caddr it) '(drawer gpu)))
  (define (before? a b)
    (let ([up? (eq? (cdr sort) 'up)])
      (if (eq? (car sort) 'name)
          (if up? (string<? (car a) (car b)) (string>? (car a) (car b)))
          (if up? (< (cadr a) (cadr b)) (> (cadr a) (cadr b))))))
  (if (not sort)
      items
      ;; a stage and the parts after it, together
      (let* ([groups (reverse
                      (fold-left (lambda (gs it)
                                   (if (and (part? it) (pair? gs))
                                       (cons (append (car gs) (list it))
                                             (cdr gs))
                                       (cons (list it) gs)))
                                 '() items))])
        (apply append
               (map (lambda (g) (cons (car g) (list-sort before? (cdr g))))
                    (list-sort (lambda (a b) (before? (car a) (car b)))
                               groups))))))

;; The tick laid out and its stages, made again for each list on view: (seq
;; items), or #f.
(define (pipeline-course v)
  (let ([l (pipeline-view-shown v)] [c (pipeline-view-course v)])
    (if (and c (eq? (car c) l))
        (cdr c)
        (let* ([seq (pipeline-course-tick v)]
               [r (and seq (list seq (pipeline-course-items v seq)))])
          (pipeline-view-course-set! v (cons l r))
          r))))

;; Course: the tick as a bar, each stage as wide as its time of the period,
;; then the stages as a table.
(define (pipeline-course-pane v x y w h)
  (let ([c (pipeline-course v)] [ch (ui-control-height)]
        [ui (pipeline-view-ui v)])
    (if (not c)
        (ui-draw-label x y w ch '(dim) "No tick is kept yet.")
        (let* ([items (cadr c)]
               [period (/ (pacer-period) 1e6)]
               [whole (max period
                           (fold-left (lambda (m it)
                                        (if (eq? (caddr it) 'total)
                                            m
                                            (+ m (cadr it))))
                                      0.0 items))]
               [bar-y (+ y ch 6)]
               [bar-h 34]
               [rows (map (lambda (it) (list->vector it))
                          (pipeline-course-sorted items
                                                  (pipeline-view-course-sort
                                                   v)))])
          (ui-draw-label x y w ch '(dim)
                         (format "Tick ~a, in order, of a period of ~,2f ms"
                                 (car c) period))
          (pipeline-draw-course-bar v x bar-y w bar-h items whole)
          (ui-table ui '(pipeline course) x (+ bar-y bar-h 10) w
                    (max 0 (- h ch 6 bar-h 10))
                    `((name "Stage" ,(max 160 (- (ui-table-room w) 96 96)))
                      (ms "ms" 96 right)
                      (share "Of the period" 96 right))
                    rows #f (lambda (row) #f)
                    (lambda (row key cx cy cw rh flags)
                      (case key
                        [(name)
                         (ui-draw-cell cx cy cw rh flags
                                       (if (eq? (vector-ref row 2) 'drawer)
                                           (string-append
                                            "    " (vector-ref row 0))
                                           (vector-ref row 0)))]
                        [(ms)
                         (ui-draw-cell cx cy cw rh flags
                                       (format "~,2f" (vector-ref row 1)))]
                        [else
                         (pipeline-draw-share cx cy cw rh
                                              (/ (vector-ref row 1) whole))
                         (ui-draw-cell cx cy cw rh flags
                                       (format "~a%"
                                               (exact
                                                (round
                                                 (/ (* 100 (vector-ref row 1))
                                                    period)))))]))
                    'sort (pipeline-view-course-sort v)
                    'on-sort (lambda (key)
                               (pipeline-view-course-sort-set!
                                v (pipeline-sort-next
                                   (pipeline-view-course-sort v) key))))))))

;; A table's sort after a press on key's heading: a number the most first, a
;; name from A; again, the other way; a third time, in order.
(define (pipeline-sort-next s key)
  (let ([first (if (eq? key 'name) 'up 'down)])
    (cond [(not (and s (eq? (car s) key))) (cons key first)]
          [(eq? (cdr s) first) (cons key (if (eq? first 'up) 'down 'up))]
          [else #f])))

;;; ---- inside: a record decoded, and the shader it's drawn with

;; The record selected, its index in the list on view, or #f.
(define (pipeline-inside-record v)
  (let ([selected (pipeline-view-selected v)]
        [n (inspect-list-count (pipeline-view-shown v))])
    (and (vector? selected) (< (vector-ref selected 0) n)
         (vector-ref selected 0))))

;; A decoded value, in words.
(define (pipeline-value-text key value)
  (cond [(and (eq? key 'color) (integer? value)) (format "#~8,'0x" value)]
        [(flonum? value) (format "~,1f" value)]
        [(list? value)
         (apply string-append
                (map (lambda (x i)
                       (string-append (if (> i 0) " " "")
                                      (pipeline-value-text #f x)))
                     value (iota (length value))))]
        [(not value) "none"]
        [else (format "~a" value)]))

;; Record i's facts: what it is, its fields, its words, its run.
(define (pipeline-inside-facts v i)
  (let* ([l (pipeline-view-shown v)]
         [who (pipeline-span-node-at v i)]
         [run (inspect-record-run l i)]
         [runs (inspect-list-runs l)])
    (append
     (list (cons "Record"
                 (format "~a of ~a~a" i (inspect-list-count l)
                         (if who
                             (format ", by ~a" (pipeline-node-name who))
                             ""))))
     (map (lambda (field)
            (cons (format "~a" (car field))
                  (pipeline-value-text (car field) (cdr field))))
          (inspect-record l i))
     (list (cons "Words"
                 (apply string-append
                        (map (lambda (k)
                               (format (if (= k 0) "~8,'0x" " ~8,'0x")
                                       (fxand (inspect-word l i k)
                                              #xffffffff)))
                             (iota rec-row-words)))))
     (let-values ([(lst j) (inspect-record-list l i)])
       (list
        (cons "List"
              (if lst
                  (let ([f (inspect-list-facts lst)])
                    (format "~a's ~a, version ~a, its record ~a; recorded \
                             ~a in ~,2f ms"
                            (inspect-list-owner lst) (inspect-list-part lst)
                            (cdr (assq 'version f)) j
                            (pipeline-ago (cdr (assq 'recorded f)))
                            (/ (cdr (assq 'took f)) 1e6)))
                  (format "the screen's own, its record ~a" j)))))
     (if run
         (list (cons "Run"
                     (format "~a of ~a: records ~a–~a, ~a"
                             (+ 1 (list-index (lambda (r) (eq? r run)) runs))
                             (length runs) (caddr run)
                             (+ (caddr run) (cadddr run) -1)
                             (case (car run)
                               [(1 2) "inverting"]
                               [(3) "adding"]
                               [else "drawn over"]))))
         '()))))

;; Inside: the record selected, decoded, and its shader's source.
(define (pipeline-inside-pane v x y w h)
  (let ([i (pipeline-inside-record v)] [lh (font-line-height 'ui)]
        [ui (pipeline-view-ui v)])
    (if (not i)
        (ui-draw-label x y w 0 '(hint wrap)
                       "Select a record: a drawer's row opened in Lists, a \
                        mark on the Tape, or a press on the small screen. \
                        What its words say, and the shader it's drawn with, \
                        show here.")
        (let* ([facts (pipeline-inside-facts v i)]
               [run (inspect-record-run (pipeline-view-shown v) i)]
               [shader (and run (inspect-run-fragment run))]
               [sy (+ y (* (length facts) (+ lh 4)) 6)])
          (for-each (lambda (fact k)
                      (let ([ly (+ y (* k (+ lh 4)))])
                        (ui-draw-label x ly 90 lh '(dim) (car fact))
                        (ui-draw-label (+ x 94) ly (- w 94) lh '()
                                       (cdr fact))))
                    facts (iota (length facts)))
          (when shader
            (let ([lines (pipeline-inside-lines v shader)])
              (ui-draw-label x sy w lh '(dim)
                             (format "Shader ~a, ~a lines of its source"
                                     (shader-name shader) (length lines)))
              (pipeline-draw-source ui x (+ sy lh 6) w
                                    (max 0 (- (+ y h) sy lh 6))
                                    lines)))))))

;; A shader's lines, kept for the shader last shown: pretty-printing is dear.
(define (pipeline-inside-lines v shader)
  (let* ([ui (pipeline-view-ui v)] [had (ui-memo ui '(pipeline source) #f)])
    (if (and had (eq? (car had) shader))
        (cdr had)
        (let ([lines (inspect-shader-lines shader)])
          (ui-memo! ui '(pipeline source) (cons shader lines))
          lines))))

;;; ---- memory: what the GPU holds, and the atlas

;; Memory: the screen's facts, what's held for frames, as bars, and beside
;; them the atlas, the part of it in use.
(define (pipeline-memory-pane v x y w h)
  (let* ([lh (font-line-height 'ui)]
         ;; the device's facts: what it holds is the bars'
         [facts (list-head (pipeline-screen-facts v) 6)]
         [left-w (min 480 (quotient w 2))]
         [by (+ y (* (length facts) (+ lh 4)) 10)]
         [objects (append
                   (map (lambda (o) (cons (format "~a" (car o)) (cddr o)))
                        (inspect-gpu-objects))
                   (let ([image (pipeline-view-image v)])
                     (if image
                         (list (cons "small screen"
                                     (* 2 (inspect-preview-bytes image))))
                         '()))
                   (list (cons "frames kept, in RAM"
                               (inspect-history-bytes
                                (pipeline-view-history v)))))]
         [most (apply max 1 (map cdr objects))]
         [g (inspect-glyphs)]
         [ax (+ x left-w 16)]
         [aw (- w left-w 16)])
    (for-each (lambda (fact k)
                (let ([ly (+ y (* k (+ lh 4)))])
                  (ui-draw-label x ly 120 lh '(dim) (car fact))
                  (ui-draw-label (+ x 124) ly (- left-w 124) lh '()
                                 (cdr fact))))
              facts (iota (length facts)))
    (for-each (lambda (o k)
                (let ([ly (+ by (* k (+ lh 6)))])
                  (pipeline-draw-memory-bar (+ x 124) ly (- left-w 124) lh
                                            (/ (cdr o) most))
                  (ui-draw-label x ly 120 lh '(dim) (car o))
                  (ui-draw-label (+ x 128) ly (- left-w 132) lh '()
                                 (format "~a MB" (pipeline-mb (cdr o))))))
              objects (iota (length objects)))
    (ui-draw-label ax y aw lh '(dim)
                   (format "The atlas, ~a glyphs: drag to move"
                           (cdr (assq 'glyphs g))))
    (pipeline-atlas-view (pipeline-view-ui v) ax (+ y lh 6) aw
                         (max 0 (- h lh 6))
                         (* gpu-atlas-side (cdr (assq 'atlas-used g))))))

;; The atlas at x y w h, a pixel of it a device pixel, from where a drag
;; left it: used, the rows of it in use.
(define (pipeline-atlas-view ui x y w h used)
  (let* ([id '(pipeline atlas)]
         [grab (list id 'grab)]   ; (mx my ox oy)
         [s (draw-scale)]
         [most-x (max 0 (- gpu-atlas-side (* w s)))]
         [most-y (max 0 (- used (* h s)))]
         [at (ui-memo ui id '(0 . 0))]
         [ox (clamp (car at) 0 most-x)]
         [oy (clamp (cdr at) 0 most-y)])
    (ui-region! ui id x y w h
      'doc '((L . "Drag to move through the atlas"))
      'on (lambda (ev)
            (case (car ev)
              [(press)
               (and (eq? (list-ref ev 3) 'left)
                    (begin (ui-memo! ui grab (list (cadr ev) (caddr ev) ox oy))
                           #t))]
              [(drag)
               (let ([g (ui-memo ui grab #f)])
                 (and g
                      (begin
                        (ui-memo! ui id
                                  (cons (clamp (- (caddr g)
                                                  (* s (- (cadr ev) (car g))))
                                               0 most-x)
                                        (clamp (- (cadddr g)
                                                  (* s (- (caddr ev) (cadr g))))
                                               0 most-y)))
                        #t)))]
              [(release)
               (and (ui-memo ui grab #f)
                    (begin (ui-memo! ui grab #f) #t))]
              [else #f])))
    (pipeline-draw-atlas x y w h (/ ox s) (/ oy s) (/ used s) (/ s))))

;;; ---- drawing

;; A stage's card: its name and what it holds, lines of text; pressed, it
;; opens.
;; Its lines cut to fit, however narrow the window makes it.
(define (pipeline-draw-card x y w h selected? name lines)
  (fill-box x y w h (if selected? 'bg-3 'bg-1) 4)
  (when selected? (stroke-box x y w h 'accent 1 4))
  (let ([lh (font-line-height 'ui)] [tw (max 0 (- w 20))])
    (draw-text (+ x 10) (+ y 6) (text-fit name tw 'ui-bold) 'text 'ui-bold)
    (for-each (lambda (line i)
                (draw-text (+ x 10) (+ y 6 (* lh (+ i 1)))
                           (text-fit line tw 'ui) 'text-dim 'ui))
              lines (iota (length lines)))))

;; A record's paint in a cell: a solid one as a swatch of its color, alpha
;; and all, and its word; another by its kind.
(define (pipeline-draw-paint x y w h flags paint)
  (if (fixnum? paint)
      (let ([s 12] [sy (+ y (/ (- h 12) 2))])
        (fill-box (+ x 6) sy s s
                  (alpha (fxand paint #xffffff) (/ (fxsrl paint 24) 255.0)) 2)
        (stroke-box (+ x 6) sy s s (alpha 'text 0.35) 1 2)
        (ui-draw-cell (+ x s 12) y (max 0 (- w s 12)) h flags
                      (inspect-paint-text paint)))
      (ui-draw-cell x y w h flags (inspect-paint-text paint))))

;; A row's frames kept as marks across its cell, inside it as a share's bar
;; is, the oldest left: those marked at least least, run together where they
;; touch, a pixel wide at the least.
(define (pipeline-draw-marks x y w h marks least)
  (let ([n (vector-length marks)]
        [x (+ x pipeline-draw-inset)]
        [w (- w pipeline-draw-inset pipeline-draw-inset)])
    (let loop ([k 0] [from #f])
      (let ([on? (and (< k n) (>= (vector-ref marks k) least))])
        (cond
          [(and on? (not from)) (loop (+ k 1) k)]
          [(and from (not on?))
           (let ([x0 (+ x (* w (/ from n)))])
             (fill-box x0 (+ y 3) (max 1 (- (+ x (* w (/ k n))) x0)) (- h 6)
                       (alpha 'accent 0.22) 2))
           (when (< k n) (loop (+ k 1) #f))]
          [(< k n) (loop (+ k 1) from)])))))

;; Who drew span i, a color: the Tape's, so that a drawer's is the same
;; everywhere.
(define (pipeline-draw-who-color i)
  (list-ref pipeline-draw-tape-who (modulo i (length pipeline-draw-tape-who))))

;; A drawer's name in a cell, after a swatch of its color.
(define (pipeline-draw-who-name x y w h flags i name)
  (let ([s 10])
    (fill-box (+ x 6) (+ y (/ (- h s) 2)) s s (pipeline-draw-who-color i) 2)
    (ui-draw-cell (+ x s 8) y (max 0 (- w s 8)) h flags name)))

;; A number's share of its column's most, a bar behind it, inside the cell by
;; pipeline-draw-inset so that full ones side by side stay apart; none for a
;; share too small to tell from a line between columns.
(define (pipeline-draw-share x y w h share)
  (when (>= share 0.03)
    (let ([d pipeline-draw-inset])
      (fill-box (+ x d) (+ y 3) (* (- w d d) (min 1 share)) (- h 6)
                (alpha 'accent 0.22) 2))))

(define pipeline-draw-inset 3)

;; The words the small screen paints spans' records with, who drew them: dim
;; but the one selected, while one is. => (values words other), other for a
;; record under no label
(define (pipeline-draw-who-words v spans selected)
  (values (map (lambda (node)
                 (let ([c (pipeline-draw-who-color
                           (pipeline-color-index v node))])
                   ;; opaque, so that a drawer's layers don't add up
                   (color-word (if (and selected (not (equal? node selected)))
                                   (mix c 'bg-0 0.75)
                                   c))))
               (pipeline-span-nodes spans))
          (color-word 'text-faint)))

;; Kinds' words for the small screen, as the Tape's kind lane colors them.
(define (pipeline-draw-kind-words)
  (map (lambda (kind color) (cons kind (color-word color)))
       pipeline-tape-kinds (cdr (cadr pipeline-draw-tape-lanes))))

;; What a record adds where it covers, showing heat: a little of red, half as
;; much green and a quarter blue, so that a pixel goes dark red, orange,
;; yellow and white as more records cover it, red full at 16.
(define (pipeline-draw-heat-word) (color-word #x100804))

;; A record changed since the frame before, and one the same. => (values new
;; same)
(define (pipeline-draw-changed-words)
  (values (color-word 'chart-1) (color-word (mix 'text-faint 'bg-0 0.6))))

;; A tick's stages in a row, each as wide as its time of whole: a phase in
;; its River color, a drawer's draw in its color, the rest of render darker,
;; what's left of the period faint; a stage wide enough names itself.
(define (pipeline-draw-course-bar v x y w h items whole)
  (fill-box x y w h 'bg-1 3)
  (let loop ([items (remp (lambda (it) (eq? (caddr it) 'total)) items)]
             [at x])
    (unless (null? items)
      (let* ([it (car items)]
             [sw (* w (/ (cadr it) whole))]
             [color (case (caddr it)
                      [(phase) (cadr (assq (cadddr it) monitor-phases))]
                      [(drawer) (pipeline-draw-who-color
                                 (pipeline-color-index v (cadddr it)))]
                      [(gpu) (mix (cadr (assq 'render monitor-phases))
                                  'bg-0 0.45)]
                      [else (alpha 'text-faint 0.15)])])
        (fill-box at y (max 0 (- sw 1)) h color 2)
        (when (> sw (+ 12 (text-width (car it) 'ui-small)))
          (draw-text (+ at 5) (+ y (/ (- h (font-line-height 'ui-small)) 2))
                     (car it)
                     (if (eq? (caddr it) 'idle) 'text-dim 'bg-0)
                     'ui-small))
        (loop (cdr items) (+ at sw))))))

;; A shader's source, a line of the mono font each, scrolling.
(define (pipeline-draw-source ui x y w h lines)
  (let ([lh (font-line-height 'mono-small)])
    (fill-box x y w h 'bg-1 3)
    (ui-scroll ui '(pipeline source-view) x y w h
      (lambda (top)
        (for-each (lambda (line k)
                    (let ([ly (+ top 6 (* k lh))])
                      (when (and (> (+ ly lh) y) (< ly (+ y h)))
                        (draw-text (+ x 8) ly line 'text 'mono-small))))
                  lines (iota (length lines)))
        (+ top 12 (* lh (length lines)))))))

;; A share of the most held, a bar.
(define (pipeline-draw-memory-bar x y w h share)
  (fill-box x (+ y 2) (* w (max 0.004 (min 1 share))) (- h 4)
            (alpha 'accent 0.3) 2))

;; The atlas in w × h from (ox, oy), k of it a pixel; the rows in use,
;; used, as a texture viewer shows its one channel, in gray.
(define (pipeline-draw-atlas x y w h ox oy used k)
  (fill-box x y w h 'bg-1 3)
  (with-clip (x y w (max 0 (min h (- used oy))))
    (draw-image (inspect-atlas-image) (- x ox) (- y oy)
                (* k gpu-atlas-side) (* k gpu-atlas-side) 'gray))
  (stroke-box x y w h 'window-border 1 3))

;;; ---- the viewer: the screen small, zoomed, moved, magnified, popped out

(define pipeline-zoom-most 32)    ; device pixels a screen pixel, at most
(define pipeline-zoom-step 1.25)  ; a notch of the wheel
(define pipeline-loupe-size 128)
(define pipeline-loupe-zoom 8)    ; a screen pixel in the loupe, logical pixels

;; How many device pixels of a viewer w × h a pixel of the screen takes: all
;; of it, or as much more as asked.
(define (pipeline-viewer-fit w h)
  (let ([s (draw-scale)])
    (min (/ (* w s) *canvas-pw*) (/ (* h s) *canvas-ph*))))

(define (pipeline-viewer-zoom v w h)
  (let ([fit (pipeline-viewer-fit w h)])
    (max fit (or (pipeline-view-zoom v) fit))))

;; The screen's pixel at the viewer's middle, on the screen.
(define (pipeline-viewer-center v)
  (let ([c (and (pipeline-view-zoom v) (pipeline-view-center v))])
    (if c
        (cons (max 0 (min *canvas-pw* (car c)))
              (max 0 (min *canvas-ph* (cdr c))))
        (cons (/ *canvas-pw* 2) (/ *canvas-ph* 2)))))

;; The screen's pixel under (mx, my) of a viewer at x y w h.
(define (pipeline-viewer-pixel v x y w h mx my)
  (let ([k (/ (draw-scale) (pipeline-viewer-zoom v w h))]
        [c (pipeline-viewer-center v)])
    (cons (+ (car c) (* k (- mx (+ x (/ w 2)))))
          (+ (cdr c) (* k (- my (+ y (/ h 2))))))))

;; A notch of the wheel, or n: zoomed at (mx, my), the pixel there staying.
(define (pipeline-zoom-at! v x y w h mx my n)
  (let* ([fit (pipeline-viewer-fit w h)]
         [p (pipeline-viewer-pixel v x y w h mx my)]
         [z (max fit (min pipeline-zoom-most
                          (* (pipeline-viewer-zoom v w h)
                             (expt pipeline-zoom-step n))))]
         [k (/ (draw-scale) z)])
    (if (<= z (* fit 1.001))
        (begin (pipeline-view-zoom-set! v #f) (pipeline-view-center-set! v #f))
        (begin
          (pipeline-view-zoom-set! v z)
          (pipeline-view-center-set!
           v (cons (- (car p) (* k (- mx (+ x (/ w 2)))))
                   (- (cdr p) (* k (- my (+ y (/ h 2)))))))))))

;; What the loupe says under its pixels: where, and the top record there.
(define (pipeline-loupe-caption v px py)
  (let* ([l (pipeline-view-shown v)]
         [at (pipeline-records-at v px py)])
    (if (null? at)
        (format "~a, ~a" px py)
        (format "~a, ~a: ~a ~a" px py (inspect-kind l (car at)) (car at)))))

;; The viewer: the screen at its zoom, around its center, what's selected
;; outlined (box, screen pixels, or #f).
(define (pipeline-draw-viewer v image x y w h box)
  (let* ([z (pipeline-viewer-zoom v w h)]
         [k (/ z (draw-scale))]
         [c (pipeline-viewer-center v)]
         [at (lambda (p mid) (+ mid (* k p)))]
         [ox (- (+ x (/ w 2)) (* k (car c)))]
         [oy (- (+ y (/ h 2)) (* k (cdr c)))])
    (fill-box x y w h 'bg-0)
    (with-clip (x y w h)
      (when image
        (draw-image image ox oy (* k *canvas-pw*) (* k *canvas-ph*)))
      (when box
        (stroke-box (at (car box) ox) (at (cadr box) oy)
                    (max 3 (* k (- (caddr box) (car box))))
                    (max 3 (* k (- (cadddr box) (cadr box))))
                    'accent 1)))
    (stroke-box x y w h 'window-border)))

;; The loupe at lx, ly: the screen's pixels around (px, py), its own boxed.
(define (pipeline-draw-loupe image lx ly px py caption)
  (let* ([size pipeline-loupe-size] [m pipeline-loupe-zoom]
         [lh (font-line-height 'ui-small)] [mid (/ size 2)])
    (fill-box lx ly size (+ size lh 6) 'bg-2)
    (with-clip (lx ly size size)
      (draw-image image (- (+ lx mid) (* m (+ px 1/2)))
                  (- (+ ly mid) (* m (+ py 1/2)))
                  (* m *canvas-pw*) (* m *canvas-ph*)))
    (stroke-box (- (+ lx mid) (/ m 2)) (- (+ ly mid) (/ m 2)) m m 'accent 1)
    (stroke-box lx ly size (+ size lh 6) 'window-border)
    (draw-text (+ lx 4) (+ ly size 3) (text-fit caption (- size 8) 'ui-small)
               'text 'ui-small)))

;; In the viewer's place while it's popped out.
(define (pipeline-draw-popped-out x y w h)
  (fill-box x y w h 'bg-1)
  (stroke-box x y w h 'window-border))

;; The viewer at x y w h, in ui as id: the wheel zooms it at the pointer, a drag
;; moves it, a press lists the records at its pixel; with the loupe on, the
;; pixels at the pointer magnified beside it.
(define (pipeline-viewer v ui id x y w h)
  (let* ([l (pipeline-view-shown v)]
         [n (inspect-list-count l)]
         [selected (pipeline-view-selected v)]
         [grab (list id 'grab)]   ; (mx my center moved?)
         [mx (ui-state-mx ui)] [my (ui-state-my ui)]
         [win (current-window)]
         [over? (and win (eq? (window-hover win) 'content)
                     (point-in? mx my x y w h))])
    (ui-region! ui id x y w h
      'doc '((L . "List what may touch this pixel, or drag to move")
             (Wheel . "Zoom in or out"))
      'on (lambda (ev)
            (case (car ev)
              [(press)
               (and (eq? (list-ref ev 3) 'left)
                    (begin
                      (ui-memo! ui grab (list (cadr ev) (caddr ev)
                                              (pipeline-viewer-center v) #f))
                      #t))]
              [(drag)
               (let ([g (ui-memo ui grab #f)])
                 (and g
                      (let ([dx (- (cadr ev) (car g))]
                            [dy (- (caddr ev) (cadr g))]
                            [k (/ (draw-scale) (pipeline-viewer-zoom v w h))])
                        (when (or (cadddr g) (> (+ (abs dx) (abs dy)) 3))
                          (ui-memo! ui grab
                                    (list (car g) (cadr g) (caddr g) #t))
                          (when (pipeline-view-zoom v)
                            (pipeline-view-center-set!
                             v (cons (- (car (caddr g)) (* k dx))
                                     (- (cdr (caddr g)) (* k dy))))))
                        #t)))]
              [(release)
               (let ([g (ui-memo ui grab #f)])
                 (ui-memo! ui grab #f)
                 (and g
                      (begin
                        (unless (cadddr g)
                          (let ([p (pipeline-viewer-pixel
                                    v x y w h (cadr ev) (caddr ev))])
                            (pipeline-trace! v (exact (floor (car p)))
                                             (exact (floor (cdr p))))))
                        #t)))]
              [(wheel)
               (pipeline-zoom-at! v x y w h (ui-state-mx ui) (ui-state-my ui)
                                  (cadr ev))
               #t]
              [else #f])))
    (pipeline-draw-viewer
     v (pipeline-view-image v) x y w h
     (let ([first (and selected (pipeline-node-first v selected))])
       (and first (< first n) (inspect-reach l first))))
    (when (and over? (pipeline-view-loupe? v) (pipeline-view-image v))
      (let* ([p (pipeline-viewer-pixel v x y w h mx my)]
             [px (exact (floor (car p)))] [py (exact (floor (cdr p)))]
             [said (ui-memo ui (list id 'loupe) #f)]
             [caption (if (and said (equal? (car said) p))
                          (cdr said)
                          (let ([c (pipeline-loupe-caption v px py)])
                            (ui-memo! ui (list id 'loupe) (cons p c))
                            c))])
        (ui-later! ui
          (lambda (ww wh)
            (let ([size pipeline-loupe-size]
                  [tall (+ pipeline-loupe-size
                           (font-line-height 'ui-small) 6)])
              (pipeline-draw-loupe
               (pipeline-view-image v)
               (if (> (+ mx 20 size) ww) (- mx 20 size) (+ mx 20))
               (if (> (+ my 20 tall) wh) (- my 20 tall) (+ my 20))
               px py caption))))))))

;; Fit, 100%, the loupe, how far the viewer vw × vh is zoomed, and Pop out
;; unless it's out.
(define (pipeline-viewer-bar v ui x y w vw vh popped?)
  (let* ([ch (ui-control-height)] [gap 6]
         [fw (+ 24 (text-width "Fit" 'ui))]
         [hw (+ 24 (text-width "100%" 'ui))]
         [lx (+ x fw gap hw gap)])
    (ui-button ui '(pipeline fit) x y fw ch "Fit"
               (lambda ()
                 (pipeline-view-zoom-set! v #f)
                 (pipeline-view-center-set! v #f))
               'tip "Show the whole screen")
    (ui-button ui '(pipeline actual) (+ x fw gap) y hw ch "100%"
               (lambda ()
                 (unless (pipeline-view-zoom v)
                   (pipeline-view-center-set! v (pipeline-viewer-center v)))
                 (pipeline-view-zoom-set! v 1))
               'tip "A pixel of the screen for a pixel")
    (let-values ([(cw chh) (ui-checkbox-size "Loupe")])
      (ui-checkbox ui '(pipeline loupe) lx y cw ch "Loupe"
                   (pipeline-view-loupe? v)
                   (lambda (on?) (pipeline-view-loupe?-set! v on?))
                   'tip "Magnify the pixels at the pointer")
      (let* ([pw (if popped? 0 (+ 24 (text-width "Pop out" 'ui)))]
             [zx (+ lx cw gap)])
        (ui-draw-label zx y (max 0 (- (+ x w) pw gap zx)) ch '(dim)
                       (format "~a%"
                               (exact (round (* 100 (pipeline-viewer-zoom
                                                     v vw vh))))))
        (unless popped?
          (ui-button ui '(pipeline pop) (- (+ x w) pw) y pw ch "Pop out"
                     (lambda () (pipeline-pop-out! v (current-window)))
                     'tip "Show it in a window of its own, above the \
                           Pipeline")))))
  ;; under them, what it shows
  (let* ([ch (ui-control-height)] [y (+ y ch 6)]
         [lw (+ 8 (text-width "Show" 'ui))])
    (ui-draw-label x y lw ch '(dim) "Show")
    (ui-dropdown ui '(pipeline look) (+ x lw) y (min 150 (- w lw)) ch
                 pipeline-looks (pipeline-view-look v)
                 (lambda (look)
                   (pipeline-view-look-set! v look)
                   (pipeline-preview! v)))
    (ui-draw-label (+ x lw (min 150 (- w lw)) 8) y
                   (max 0 (- w lw (min 150 (- w lw)) 8)) ch '(dim)
                   (cdr (assq (pipeline-view-look v) pipeline-look-notes)))))

;; What the small screen may show, and in a word what each means.
(define pipeline-looks
  '(("Picture" . picture)
    ("Who drew" . who)
    ("Kind" . kind)
    ("Heat" . heat)
    ("Changed" . changed)))
(define pipeline-look-notes
  '((picture . "")
    (who . "a drawer a color")
    (kind . "as the Tape's kinds")
    (heat . "more records, brighter")
    (changed . "bright: changed")))

;; Its two rows' height.
(define (pipeline-viewer-bar-height)
  (+ (ui-control-height) 6 (ui-control-height)))

;; The viewer in a window of its own, kept above the Pipeline's, win: closed,
;; it's back in its place.
(define (pipeline-pop-out! v win)
  (unless (pipeline-view-popped v)
    (let* ([ui (make-ui)]
           [w 960]
           [h (exact (round (+ (* w (/ *canvas-ph* *canvas-pw*))
                               (pipeline-viewer-bar-height) (* 3 (ui-pad)))))])
      (pipeline-view-popped-set!
       v (apply open-window "Pipeline — the screen"
                'size (cons w h)
                'min-size '(320 . 240)
                'app (window-app win)
                'above win
                'draw (lambda (pop w h) (pipeline-popped-draw v ui w h))
                'close (lambda (pop)
                         (pipeline-view-popped-set! v #f)
                         (invalidate! win))
                (ui-handlers ui
                             'key (lambda (pop key mods)
                                    (pipeline-key v pop key mods))))))))

(define (pipeline-popped-draw v ui w h)
  (let ([pad (ui-pad)] [bh (pipeline-viewer-bar-height)])
    (ui-begin! ui)
    (let ([vw (- w pad pad)] [vh (- h pad bh pad pad)])
      (pipeline-viewer-bar v ui pad pad vw vw vh #t)
      (pipeline-viewer v ui '(pipeline viewer) pad (+ pad bh pad) vw vh))
    (ui-end! ui w h)))

;; With the loupe on, a move of the pointer in either window draws again.
(define (pipeline-loupe-follow! v win)
  (let ([popped (pipeline-view-popped v)])
    (for-each (lambda (ui)
                (let ([at (cons (ui-state-mx ui) (ui-state-my ui))])
                  (unless (equal? at (ui-memo ui '(pipeline pointer) #f))
                    (ui-memo! ui '(pipeline pointer) at)
                    (invalidate! win))))
              (cons (pipeline-view-ui v)
                    (if popped (list (window-ref popped 'ui)) '())))))

(define (pipeline-card-lines v stage)
  (case stage
    [(who)
     (let ([rows (pipeline-who-rows v)])
       (list (format "main drew in ~,2f ms"
                     (fold-left (lambda (ms r) (+ ms (or (vector-ref r 2) 0.0)))
                                0.0 rows))
             (if (null? rows)
                 "nothing drawn"
                 (format "the most pixels: ~a"
                         (pipeline-node-name
                          (vector-ref
                           (fold-left (lambda (a r)
                                        (if (> (vector-ref r 4)
                                               (vector-ref a 4))
                                            r
                                            a))
                                      (car rows) (cdr rows))
                           0))))))]
    [(lists)
     (let ([l (pipeline-view-shown v)])
       (list (format "~a records, ~a KB" (inspect-list-count l)
                     (quotient (inspect-list-bytes l) 1024))
             (let ([lists (inspect-list-lists l)])
               (format "~a drew, ~a lists, ~a changed"
                       (length (inspect-list-labels l)) (length lists)
                       (length (filter (lambda (lst)
                                         (pipeline-list-changed? v lst))
                                       lists))))))]
    [(course)
     (let ([c (pipeline-course v)])
       (if c
           (list (format "tick ~a, ~,2f ms busy" (car c)
                         (fold-left (lambda (ms it) (+ ms (cadr it))) 0.0
                                    (remp (lambda (it)
                                            (memq (caddr it) '(idle total)))
                                          (cadr c))))
                 (format "render ~,2f ms of it"
                         (fold-left (lambda (ms it)
                                      (if (memq (caddr it) '(drawer gpu))
                                          (+ ms (cadr it))
                                          ms))
                                    0.0 (cadr c))))
           (list "no tick kept" "")))]
    [(inside)
     (let ([i (pipeline-inside-record v)] [l (pipeline-view-shown v)])
       (if i
           (let ([run (inspect-record-run l i)])
             (list (format "record ~a, a ~a" i (inspect-kind l i))
                   (if run
                       (format "~a" (shader-name (inspect-run-fragment run)))
                       "")))
           (list "a record selected," "decoded")))]
    [(latency) (list-head (pipeline-latency-words v) 2)]
    [else
     (let ([d (inspect-device)] [g (inspect-glyphs)])
       (list (format "~a MB on the GPU"
                     (pipeline-mb (apply + (map cddr (inspect-gpu-objects)))))
             (format "the atlas ~a% used"
                     (exact (round (* 100 (cdr (assq 'atlas-used g))))))))]))

(define (pipeline-mb bytes) (format "~,1f" (/ bytes 1048576.0)))

;; Screen's pane: one fact a line.
(define (pipeline-screen-facts v)
  (let-values ([(d) (inspect-device)] [(g) (inspect-glyphs)]
               [(image) (pipeline-view-image v)]
               [(kept not-shown) (inspect-frames-kept)]
               [(p50 p99 missed) (inspect-frames-truth 10000)])
    (append
     (list (cons "Renderer" (if (eq? (cdr (assq 'renderer d)) 'cpu)
                                "lavapipe, on the CPU"
                                "the GPU"))
           (cons "Showing on" (if (cdr (assq 'window? d))
                                  "a window, by its swapchain"
                                  "a texture, no window"))
           (cons "Presenting"
                 (format "by ~a, of ~a" (cdr (assq 'present-mode d))
                         (cdr (assq 'present-modes d))))
           (cons "Pixels"
                 (format "~a × ~a at ~a%"
                         (cadr (assq 'pixels d)) (cddr (assq 'pixels d))
                         (exact (round (* 100 (cdr (assq 'scale d)))))))
           (cons "Frames kept"
                 (format "~a, ~a of them not shown" kept not-shown))
           (cons "Input to screen"
                 (if p50
                     (format "~,1f ms at the median, ~,1f at the 99th, the \
                              last 10 s"
                             (/ p50 1e6) (/ p99 1e6))
                     "no word from the screen in the last 10 s"))
           (cons "Refreshes missed"
                 (format "~a in the last 10 s, by the screen" missed))
           (cons "Glyphs"
                 (format "~a, the atlas ~a% used"
                         (cdr (assq 'glyphs g))
                         (exact (round (* 100 (cdr (assq 'atlas-used g))))))))
     (map (lambda (o)
            (cons (format "~a" (car o))
                  (format "~a, ~a KB" (cadr o) (quotient (cddr o) 1024))))
          (inspect-gpu-objects))
     (if image
         (list (cons "small screen"
                     (format "2 textures, ~a KB"
                             (quotient (* 2 (inspect-preview-bytes image))
                                       1024))))
         '()))))

(define (pipeline-lists-pane v x y w h)
  (let* ([ui (pipeline-view-ui v)] [traced (pipeline-view-traced v)]
         [columns `((name "Who" 190)
                    (first "Record" 72 right)
                    (count "Count" 64 right)
                    (paint "Paint" 140)
                    (what "What" ,(max 80 (- (ui-table-room w) 190 72 64
                                             140))))]
         [box (ui-checkbox-box)]
         ;; a span's name has its checkbox: off, it's left out
         [cell (lambda (node key cx cy cw ch flags)
                 (if (and (eq? key 'name) (pair? node))
                     (begin
                       (ui-checkbox ui (list 'pipeline 'shows node) cx cy box ch
                                    "" (not (member node (pipeline-view-off v)))
                                    (lambda (on?)
                                      (pipeline-show-span! v node on?))
                                    'focus 'keep
                                    'tip "Draw it on the small screen and the \
                                          Tape")
                       (ui-draw-cell (+ cx box 6) cy (max 0 (- cw box 6)) ch
                                     flags (pipeline-node-name node)))
                     (if (and (eq? key 'paint) (vector? node))
                         (pipeline-draw-paint
                          cx cy cw ch flags
                          (inspect-record-paint (pipeline-view-shown v)
                                                (vector-ref node 0)))
                         (ui-draw-cell
                      cx cy cw ch flags
                      (case key
                        [(name) (pipeline-node-name node)]
                        [(first)
                         (number->string (pipeline-node-first v node))]
                        [(count)
                         (number->string (pipeline-node-count v node))]
                        [(paint) ""]
                        [else (pipeline-node-what v node)])))))]
         [select! (lambda (node) (pipeline-select! v node))])
    (if traced
        (let ([ch (ui-control-height)])
          (ui-draw-label x y (- w 90) ch '(dim)
                         (format "Records at pixel ~a, ~a"
                                 (car traced) (cadr traced)))
          (ui-button ui '(pipeline untrace) (+ x w -80) y 80 ch "All"
                     (lambda () (pipeline-view-traced-set! v #f)))
          (ui-table ui '(pipeline traced) x (+ y ch 4) w (- h ch 4) columns
                    (caddr traced) (pipeline-view-selected v) select! cell))
        (let ([shown (pipeline-tree-selected v)])
          (when (vector? shown)
            (pipeline-tree-open! ui (pipeline-span-node-at
                                     v (vector-ref shown 0))))
          (ui-tree ui '(pipeline tree) x y w h columns
                   (pipeline-span-nodes (pipeline-view-groups v))
                   (lambda (node) (pipeline-children v node))
                   shown select! cell
                   'dim (lambda (node) (pipeline-node-off? v node))
                   'reveal (not (equal? shown (ui-memo ui '(pipeline revealed)
                                                       #f))))
          (ui-memo! ui '(pipeline revealed) shown)))))

;; The small screen's images, as big as the screen: the shader draws on real
;; pixels. Made again when the screen's size changes: a draw still waiting names
;; the old ones, so the new one's first picture takes its place.
(define (pipeline-image! v)
  (let ([image (pipeline-view-image v)] [pw *canvas-pw*] [ph *canvas-ph*])
    (if (and image (= (inspect-preview-w image) pw)
             (= (inspect-preview-h image) ph))
        image
        (begin
          (when image
            (inspect-preview-free! image)
            (inspect-preview-free! (pipeline-view-back v)))
          (pipeline-view-image-set! v (inspect-preview-image pw ph))
          (pipeline-view-back-set! v (inspect-preview-image pw ph))
          (pipeline-view-flip?-set! v #f)
          (pipeline-preview! v)
          (pipeline-view-image v)))))

(define (pipeline-draw v win w h)
  (let* ([ui (pipeline-view-ui v)] [pad (ui-pad)] [gap (ui-gap)]
         [lh (font-line-height 'ui)]
         [card-h (+ 12 (* 3 lh))]
         [tape-h (pipeline-tape-height v (- w pad pad))]
         [side (min 360 (quotient w 2))]
         [top (+ pad card-h gap)]
         ;; Latency is the clock over the River, which takes the rest: no
         ;; small screen beside it, no Tape under it
         [latency? (eq? (pipeline-view-stage v) 'latency)]
         [river-h (if latency?
                      (- h pad top (pipeline-latency-height (- w pad pad)) gap)
                      (pipeline-river-height (- w pad pad) 80))]
         [bottom (max top (- h pad river-h gap
                             (if latency? 0 (+ tape-h gap))))]
         [l (pipeline-view-shown v)]
         [ch (ui-control-height)]
         [screen-w (- side pad)]
         [bh (pipeline-viewer-bar-height)]
         ;; as tall as the screen's shape says, but for its bar and the two
         ;; rows under it: the viewer fits the screen in whatever it's given
         [screen-h (max ch (min (exact (round (* screen-w (/ *canvas-ph*
                                                              *canvas-pw*))))
                                (- bottom top gap bh gap ch gap)))])
    (ui-begin! ui)
    (let ([card-w (quotient (- w pad pad (* 5 gap)) 6)])
      (for-each
       (lambda (stage name i)
         (let ([cx (+ pad (* i (+ card-w gap)))])
           (ui-area ui (list 'pipeline stage) cx pad card-w card-h
                    (lambda () (pipeline-view-stage-set! v stage)))
           (pipeline-draw-card cx pad card-w card-h
                               (eq? stage (pipeline-view-stage v)) name
                               (pipeline-card-lines v stage))))
       '(lists who course inside memory latency)
       '("Lists" "Who" "Course" "Inside" "Memory" "Latency")
       '(0 1 2 3 4 5)))
    (let ([pane-w (if latency? (- w pad pad) (- w pad pad side gap))])
      (with-clip (pad top pane-w (- bottom top))
        (case (pipeline-view-stage v)
          [(lists) (pipeline-lists-pane v pad top pane-w (- bottom top))]
          [(who) (pipeline-who-pane v pad top pane-w (- bottom top))]
          [(course) (pipeline-course-pane v pad top pane-w (- bottom top))]
          [(inside) (pipeline-inside-pane v pad top pane-w (- bottom top))]
          [(latency)
           (pipeline-latency-pane v pad top pane-w (- bottom top))]
          [else (pipeline-memory-pane v pad top pane-w (- bottom top))]))
      ;; the small screen, or its place while it's out; its bar, how often
      (unless latency? (pipeline-image! v))
      (unless latency?
        (let* ([sx (+ pad pane-w gap)]
               [sy (+ top screen-h gap)]
               [hy (+ sy bh gap)])
          (if (pipeline-view-popped v)
              (let ([bw (+ 24 (text-width "Bring it back" 'ui))])
                (pipeline-draw-popped-out sx top screen-w screen-h)
                (ui-draw-label sx (+ top (/ (- screen-h ch ch gap) 2)) screen-w
                               ch '(dim center) "In a window of its own")
                (ui-button ui '(pipeline unpop) (+ sx (/ (- screen-w bw) 2))
                           (+ top (/ (+ (- screen-h ch ch gap) ch ch gap) 2))
                           bw ch "Bring it back"
                           (lambda ()
                             (close-window! (pipeline-view-popped v)))))
              (begin
                (pipeline-viewer v ui '(pipeline viewer) sx top screen-w
                                 screen-h)
                (pipeline-viewer-bar v ui sx sy screen-w screen-w screen-h #f)))
          (let* ([ey hy]
                 [every (pipeline-view-every v)]
                 [label "Draw it every"]
                 [lw (+ 8 (text-width label 'ui))])
            (ui-draw-label sx ey lw ch '(dim) label)
            (let ([sw (ui-stepper
                       ui '(pipeline every) (+ sx lw) ey every 1 60
                       (lambda (n) (pipeline-view-every-set! v n))
                       'tip "How often the small screen draws again, in \
                             frames: each time, the GPU goes over the whole \
                             frame once more")])
              (ui-draw-label (+ sx lw sw 8) ey (max 0 (- screen-w lw sw 8)) ch
                             '(dim) (if (= every 1) "tick" "ticks"))))
          ;; what a frame kept can't show
          (when (and (pipeline-view-held? v) (> (inspect-list-left-out l) 0))
            (ui-draw-label sx (+ hy ch gap)
                           screen-w 0 '(hint wrap)
                           "An image or a paint let go of since this frame \
                            is left out of it here.")))))
    (unless latency?
      (pipeline-tape-pane v pad (+ bottom gap) (- w pad pad) tape-h))
    (pipeline-river-pane v pad (- h pad river-h) (- w pad pad) river-h)
    (ui-end! ui w h)))

;; Each frame while it's seen and flows: the frame just drawn is kept, a new
;; bar drawn, and the small screen with it as often as it's told.
(define (pipeline-frame! v win)
  (when (pipeline-view-playing v)
    (pipeline-play-tick! v)
    (invalidate! win))
  (when (pipeline-view-loupe? v) (pipeline-loupe-follow! v win))
  (unless (pipeline-view-held? v)
    (pipeline-flip! v)
    (let ([history (pipeline-view-history v)])
      (inspect-history-add! history)
      ;; the small screen, while it's shown: Latency has none beside it
      (when (and (zero? (modulo (inspect-history-newest history)
                                (pipeline-view-every v)))
                 (or (pipeline-view-popped v)
                     (not (eq? (pipeline-view-stage v) 'latency))))
        (pipeline-preview-back! v)))
    ;; the River moves with every frame
    (invalidate! win)
    ;; a period after the last read was due, not after it was done, so that
    ;; reads keep in step with the clock; one a period late or more starts
    ;; again from then
    (let* ([due (+ (pipeline-view-looked v) pipeline-period-ms)]
           [late (- (now-ms) due)])
      (when (>= late 0)
        (pipeline-look! v)
        (when (< late pipeline-period-ms) (pipeline-view-looked-set! v due))
        (invalidate! win)))))

(define-app (pipeline) "Pipeline"
  (let ([existing (find-window 'pipeline)])
    (if existing
        (begin (focus-window! existing) existing)
        (let* ([ui (make-ui)]
               [river (pipeline-river-new)]
               [ticks (pipeline-river-ticks-new)]
               [v (make-pipeline-view ui (inspect-history-new
                                          pipeline-frames-kept)
                                      river ticks 'lists (inspect-list) #f 0
                                      '() #f #f
                                      #f #f #f #f #f #f 0.0 #f 1
                                      (pipeline-tape-new 0) #f #f 5
                                      #f #f #f #f '() #f #f 'picture
                                      (inspect-list-empty) #f #f #f #f
                                      #f #f
                                      (make-hashtable equal-hash equal?))])
          (pipeline-look! v)
          (apply open-window "Pipeline"
                 'size '(1100 . 860)
                 'min-size '(640 . 560)
                 'state v
                 'draw (lambda (win w h) (pipeline-draw v win w h))
                 'close (lambda (win)
                          (let ([image (pipeline-view-image v)])
                            (when image
                              (inspect-preview-free! image)
                              (inspect-preview-free! (pipeline-view-back v)))
                            (pipeline-view-image-set! v #f)
                            (pipeline-view-back-set! v #f))
                          (ui-stream-release! river)
                          (ui-stream-release! ticks)
                          (ui-stream-release! (pipeline-view-tape v)))
                 (append
                  (ui-handlers ui
                               'key (lambda (win key mods)
                                      (pipeline-key v win key mods)))
                  (list 'open (lambda (win) (window-frame-soon! win))
                        'frame (lambda (win t)
                                 (window-frame-soon! win)
                                 (ui-frame ui win)
                                 (pipeline-frame! v win)))))))))
