;;; apps/pipeline.ss — Pipeline: the way from a window's draw to the screen
;;; surface, on one screen, read through kits/inspect.ss.
;;;
;;; For now two stages, chosen on the cards at the top:
;;;   Lists   the frame's list by who drew it, and each's records, decoded
;;;           in draw order, a run of glyphs as its text; a drawer's checkbox
;;;           off leaves it out of the small screen and the Tape
;;;   Screen  what draws, and what it holds on the GPU
;;; Right, the screen small, the selected record outlined: a press there
;;; lists the records that may touch that pixel. It draws again every tick, or
;;; as seldom as it's told, and it's on the screen it shows: so it's in itself,
;;; a tick older each time round. The wheel zooms it at the pointer and a drag
;;; moves it; a loupe magnifies the pixels at the pointer; and it pops out to a
;;; window of its own above the Pipeline, coming back when that one closes.
;;; Under them, the Tape: a mark a record in draw order, as tall as what it may
;;; cover, and in lanes who drew it and its kind. A press there, or its
;;; stepper, holds the frame and draws it as far as that record, the record
;;; selected; Play draws it record by record. What's selected in the list, or
;;; at a pixel, is marked on it.
;;; Below, the River: a bar a tick as it flows, what main did, and in lanes
;;; over them what else happened. A press holds it and goes back to that
;;; tick's frame, the whole app showing it; a drag moves through them. Frames
;;; are kept for a few seconds, what's left of the River's reach, while it's
;;; open: closed, what's left of it is the core's few numbers a frame.
;;; While it flows it asks for a frame a tick, so it says what it takes itself.

(define-record-type pipeline-view
  (fields ui history river
          (mutable stage)      ; lists or screen
          (mutable shown)      ; (inspect-list), the one on view
          (mutable held?)      ; it stays
          (mutable looked)     ; when it was read (now-ms)
          (mutable groups)     ; its spans: (label first count) ...
          (mutable selected)   ; a tree node
          (mutable traced)     ; the records at a pixel, or #f: (x y n ...)
          (mutable upto)       ; the slider's record, or #f: all of them
          (mutable image)      ; the small screen on view, or #f
          (mutable back)       ; what its next picture is drawn on, or #f
          (mutable flip?)      ; back has a newer picture than image
          (mutable reach)      ; while held, where the River stops: (newest
                               ; . oldest)
          (mutable tick)       ; the tick picked, or #f
          (mutable order)      ; how the River's bars stack: columns
          (mutable own)        ; what it takes itself, ms a tick
          (mutable tip)        ; the last bar's tooltip: (seq . text)
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
          (mutable kept-of)))  ; the list on view it's of

(define pipeline-period-ms 250)

;; About 5 seconds at 60 Hz.
(define pipeline-frames-kept 300)
(define pipeline-river-rows 2048)
(define pipeline-bar-px 3)

(define (pipeline-show! v l)
  (pipeline-view-shown-set! v l)
  (pipeline-view-groups-set! v (inspect-list-labels l)))

;; What the window takes itself, ms a tick, over the last half second.
(define (pipeline-own-ms)
  (let ([win (find-window 'pipeline)] [newest (profile-newest-tick)])
    (if (and win newest)
        (let ([seqs (filter profile-tick-kept?
                            (map (lambda (i) (- newest i)) (iota 30)))]
              [subject (profile-subject-of win)])
          (/ (fold-left (lambda (ms seq)
                          (+ ms (profile-tick-node-ms seq subject)))
                        0.0 seqs)
             (max 1 (length seqs))))
        0.0)))

(define (pipeline-look! v)
  (unless (pipeline-view-held? v)
    (let ([history (pipeline-view-history v)] [newest (profile-newest-tick)])
      (inspect-history-add! history)
      (pipeline-show! v (or (inspect-history-ref
                             history (inspect-history-newest history))
                            (inspect-list)))
      (pipeline-view-own-set! v (pipeline-own-ms))
      (when newest
        (pipeline-view-order-set!
         v (monitor-bars-order
            (monitor-range (max (profile-oldest-tick)
                                (- newest pipeline-frames-kept))
                           newest))))))
  (pipeline-view-looked-set! v (now-ms)))

;; What's on view, drawn on image, but the spans left out. Live, it's drawn
;; with the next frame, as far as the slider says; held, what's kept of the
;; frame is.
(define (pipeline-preview-on! v image)
  (let ([l (pipeline-view-shown v)] [upto (pipeline-view-upto v)]
        [left-out (pipeline-left-out-of v)])
    (if (pipeline-view-held? v)
        (inspect-preview-list! image l (or upto (inspect-list-count l))
                               left-out)
        (inspect-preview! image (or upto (most-positive-fixnum)) left-out))))

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
    (pipeline-view-reach-set! v (cons (profile-newest-tick)
                                      (profile-oldest-tick)))
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

;; How bright a tick's collecting is: a level by its time, faint however short,
;; and at its brightest from this many ns.
(define pipeline-collector-levels 8)
(define pipeline-collector-full-ns 2000000)

(define (pipeline-collector-level ns)
  (+ 1 (quotient (* (- pipeline-collector-levels 1)
                    (min (max ns 0) pipeline-collector-full-ns))
                 pipeline-collector-full-ns)))

;; Bottom up, as monitor-bars-order stacks them, what main did; over them, the
;; lanes, a word each: late; a frame sent, shown or not; where the GPU stood
;; with the frame before: done, finishing, or not yet; the collector, by how
;; long; input.
(define pipeline-draw-lanes
  `(("late" chart-flag)
    ("frame" chart-ok chart-flag)
    ("GPU" chart-ok chart-2 chart-flag)
    ("collector"
     ,@(map (lambda (i)
              (alpha 'chart-7
                     (+ 0.2 (* 0.8 (/ i (- pipeline-collector-levels 1.0))))))
            (iota pipeline-collector-levels)))
    ("input" chart-1)))

;; What a lane's colors say, on its label.
(define pipeline-lane-tips
  `("Red: this tick came late, past one and a half periods. None: it was in \
     time."
    "Green: the tick's frame reached the screen. Red: the window had no room \
     for it. None: no frame was drawn."
    "Where the GPU stood with the frame before, as main asked for the next \
     image. Green: it had finished. Orange: it finished during the wait. Red: \
     it hadn't yet."
    ,(format "A collection ran in this tick: the longer it took, the brighter, \
              at its brightest from ~a."
             (monitor-ns-text pipeline-collector-full-ns))
    "The keyboard or the mouse sent something."))

;; The lanes' readings of tick seq, in words, for its tooltip.
(define (pipeline-tick-lanes seq)
  (let ([drew? (or (not (profile-tick-kept? (- seq 1)))
                   (> (profile-tick-ns seq 'frames)
                      (profile-tick-ns (- seq 1) 'frames)))])
    (string-append
     (if drew?
         (format "\nframe ~a; GPU ~a with the one before"
                 (if (> (profile-tick-ns seq 'shown) 0)
                     "reached the screen"
                     "had no room")
                 (vector-ref '#("had finished" "finished during the wait"
                                "hadn't finished")
                             (profile-tick-ns seq 'gpu)))
         "\nno frame drawn")
     (if (> (profile-tick-ns seq 'gcs) 0)
         (format "\ncollected for ~,2f ms"
                 (/ (profile-tick-ns seq 'gc-ns) 1000000.0))
         ""))))

(define (pipeline-river-word period)
  (let ([phases (length monitor-phases)])
    (lambda (seq j)
      (if (< j phases)
          (quotient (monitor-tick-phase-ns seq j) 1000)
          (let ([drew? (or (not (profile-tick-kept? (- seq 1)))
                           (> (profile-tick-ns seq 'frames)
                              (profile-tick-ns (- seq 1) 'frames)))])
            (case (- j phases)
              [(0) (if (profile-tick-late? seq period) 1 0)]
              [(1) (cond [(not drew?) 0]
                         [(> (profile-tick-ns seq 'shown) 0) 1]
                         [else 2])]
              [(2) (if drew? (+ 1 (profile-tick-ns seq 'gpu)) 0)]
              [(3) (if (> (profile-tick-ns seq 'gcs) 0)
                       (pipeline-collector-level (profile-tick-ns seq 'gc-ns))
                       0)]
              [else (if (> (profile-tick-ns seq 'input) 0) 1 0)]))))))

;; A bar's tooltip, worked out once: a held River draws for each move.
(define (pipeline-river-tip v seq period)
  (let ([tip (pipeline-view-tip v)])
    (if (and tip (eqv? (car tip) seq))
        (cdr tip)
        (let ([text (string-append
                     (monitor-tick-tip seq (monitor-clock-zero) period)
                     (pipeline-tick-lanes seq))])
          (pipeline-view-tip-set! v (cons seq text))
          text))))

;; A line where the frames kept end, left of it ticks whose frames are gone.
(define (pipeline-draw-reach v areas count newest)
  (let ([history (pipeline-view-history v)]
        [plot (cdr (assq 'plot areas))])
    (let loop ([i (- count 1)])
      (when (>= i 0)
        (let ([seq (+ newest (- i count -1))])
          (if (and (profile-tick-kept? seq)
                   (inspect-history-ref history (pipeline-tick-frame seq)))
              (loop (- i 1))
              (let-values ([(bx bw) (ui-bar-chart-bar areas count i)])
                (when (and (< i (- count 1)) (>= bx (car plot)))
                  (fill-box (+ bx bw -1) (cadr plot) 1 (cadddr plot)
                            'chart-rule)))))))))

;; The tick picked stands out, whatever's on it.
(define (pipeline-draw-picked areas count newest tick)
  (let-values ([(bx bw) (ui-bar-chart-bar areas count
                                          (- count 1 (- newest tick)))])
    (let ([plot (cdr (assq 'plot areas))])
      (when (>= bx (car plot))
        (stroke-box (- bx 1) (cadr plot) (+ bw 1) (cadddr plot) 'accent 1)))))

;; The River's height for this width's legend, its heading and legend included.
(define (pipeline-river-height v w)
  (let-values ([(gw gh) (ui-label-size '(group) "River" w)]
               [(kw kh) (ui-legend-size (pipeline-river-keys v))])
    (+ gh 4 (ui-stream-room pipeline-draw-lanes) 96 4 kh)))

(define (pipeline-river-keys v)
  (map (lambda (j) (cdr (list-ref monitor-phases j)))
       (pipeline-view-order v)))

(define (pipeline-river-words v)
  (let ([tick (pipeline-view-tick v)] [held? (pipeline-view-held? v)])
    (if (and held? tick)
        (let ([l (and (profile-tick-kept? tick)
                      (inspect-history-ref (pipeline-view-history v)
                                           (pipeline-tick-frame tick)))])
          (if l
              (format "tick ~a, frame ~a: ~a records" tick
                      (inspect-list-frame l) (inspect-list-count l))
              (format "tick ~a: its frame is no longer kept" tick)))
        (format "a bar a tick; the last ~a frames kept; it takes ~,2f ms a \
                 tick itself"
                (inspect-history-count (pipeline-view-history v))
                (pipeline-view-own v)))))

(define (pipeline-river-pane v x y w h)
  (let*-values
      ([(ui) (pipeline-view-ui v)]
       [(river) (pipeline-view-river v)]
       [(period) (pacer-period)]
       [(top) (quotient (* 2 period) 1000)]
       [(rules) (list (cons (quotient period 1000) (monitor-ns-text period))
                      (cons top (monitor-ns-text (* 2 period))))]
       [(reach) (pipeline-view-reach v)]
       [(held?) (pipeline-view-held? v)]
       [(newest) (if held? (car reach) (profile-newest-tick))]
       [(oldest) (if held? (cdr reach) (profile-oldest-tick))]
       [(keys) (pipeline-river-keys v)]
       [(gw gh) (ui-label-size '(group) "River" w)]
       [(kw kh) (ui-legend-size keys)]
       [(sy) (+ y gh 4)]
       [(sh) (- h gh 4 4 kh)])
    (ui-draw-label x y w gh '(group) "River")
    (ui-draw-label x y w gh '(dim right) (pipeline-river-words v))
    (when (and newest (not held?))
      (ui-stream-send! river oldest newest (pipeline-river-word period)))
    (ui-stream ui 'pipeline-river river x sy w sh newest oldest top rules
               (map (lambda (j) (cons j (cadr (list-ref monitor-phases j))))
                    (pipeline-view-order v))
               pipeline-bar-px
               'doc '((L . "Go back to this tick"))
               'strip-tips pipeline-lane-tips
               'tip (lambda (seq)
                      (and (profile-tick-kept? seq)
                           (pipeline-river-tip v seq period)))
               'on-pick (lambda (seq) (pipeline-pick! v seq))
               'marked (if (pipeline-view-tick v)
                           (list (pipeline-view-tick v))
                           '())
               'over (lambda (areas count)
                       (when newest
                         (pipeline-draw-reach v areas count newest)
                         (when (pipeline-view-tick v)
                           (pipeline-draw-picked areas count newest
                                                 (pipeline-view-tick v))))))
    (ui-draw-legend x (+ sy sh 4) w kh '() keys)))

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
(define (pipeline-tape-rows l kept)
  (let* ([n (inspect-list-count l)]
         [who (make-vector n 0)]
         [colors (length pipeline-draw-tape-who)]
         [kinds (length pipeline-tape-kinds)])
    (for-each (lambda (span i)
                (do ([k (cadr span) (+ k 1)])
                    ((>= k (min n (+ (cadr span) (caddr span)))))
                  (vector-set! who k (+ 1 (modulo i colors)))))
              (inspect-list-labels l) (iota (length (inspect-list-labels l))))
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
            (let ([rows (pipeline-tape-rows (pipeline-view-shown v) kept)])
              (ui-stream-send! tape 0 (- n 1)
                               (lambda (seq j)
                                 (vector-ref (vector-ref rows seq) j))))))
        (pipeline-view-tape-of-set! v kept)))))

(define (pipeline-tape-tip l i)
  (let ([label (inspect-label-at l i)])
    (format "record ~a, a ~a: ~a~a" i (inspect-kind l i) (inspect-what l i)
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

;; Whose each color is, but the spans left out, which keep their colors.
(define (pipeline-tape-keys v)
  (let ([spans (pipeline-view-groups v)] [off (pipeline-view-off v)])
    (fold-right (lambda (span node i acc)
                  (if (member node off)
                      acc
                      (cons (cons (list-ref pipeline-draw-tape-who
                                            (modulo i (length
                                                       pipeline-draw-tape-who)))
                                  (pipeline-node-name span))
                            acc)))
                '() spans (pipeline-span-nodes spans) (iota (length spans)))))

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
      (ui-draw-label lx y (max 0 (- (+ x w) lx)) ch '(dim right)
                     "a mark a record, in draw order"))
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

;; The span of node (label k) in the list on view, (label first count), or #f
;; when it's gone.
(define (pipeline-node-span v node)
  (let loop ([spans (pipeline-view-groups v)] [k (cadr node)])
    (cond [(null? spans) #f]
          [(not (equal? (caar spans) (car node))) (loop (cdr spans) k)]
          [(zero? k) (car spans)]
          [else (loop (cdr spans) (- k 1))])))

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

(define (pipeline-node-what node)
  (if (pair? node) "" (vector-ref node 3)))

;; The records at a device pixel, as nodes.
(define (pipeline-trace! v x y)
  (let* ([l (pipeline-view-shown v)]
         [at (pipeline-records-at v x y)])
    (pipeline-view-traced-set!
     v (list x y (map (lambda (i) (car (inspect-rows l i 1))) at)))
    (unless (null? at)
      (pipeline-view-selected-set! v (car (inspect-rows l (car at) 1))))))

;;; ---- drawing

;; A stage's card: its name and what it holds, lines of text; pressed, it
;; opens.
(define (pipeline-draw-card x y w h selected? name lines)
  (fill-box x y w h (if selected? 'bg-3 'bg-1) 4)
  (when selected? (stroke-box x y w h 'accent 1 4))
  (let ([lh (font-line-height 'ui)])
    (draw-text (+ x 10) (+ y 6) name 'text 'ui-bold)
    (for-each (lambda (line i)
                (draw-text (+ x 10) (+ y 6 (* lh (+ i 1))) line 'text-dim 'ui))
              lines (iota (length lines)))))

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
                           Pipeline"))))))

;; The viewer in a window of its own, kept above the Pipeline's, win: closed,
;; it's back in its place.
(define (pipeline-pop-out! v win)
  (unless (pipeline-view-popped v)
    (let* ([ui (make-ui)]
           [w 960]
           [h (exact (round (+ (* w (/ *canvas-ph* *canvas-pw*))
                               (ui-control-height) (* 3 (ui-pad)))))])
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
                (append (ui-handlers ui)
                        (list 'tick (lambda (pop) (ui-tick ui pop)))))))))

(define (pipeline-popped-draw v ui w h)
  (let ([pad (ui-pad)] [ch (ui-control-height)])
    (ui-begin! ui)
    (let ([vw (- w pad pad)] [vh (- h pad ch pad pad)])
      (pipeline-viewer-bar v ui pad pad vw vw vh #t)
      (pipeline-viewer v ui '(pipeline viewer) pad (+ pad ch pad) vw vh))
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
    [(lists)
     (let* ([l (pipeline-view-shown v)] [row (inspect-list-row l)])
       (list (format "~a records, ~a KB" (inspect-list-count l)
                     (quotient (inspect-list-bytes l) 1024))
             (format "~a drew, ~a runs"
                     (length (inspect-list-labels l))
                     (if row (cadddr row) 0))))]
    [else
     (let ([d (inspect-device)])
       (list (format "~a × ~a, on the ~a"
                     (cadr (assq 'pixels d)) (cddr (assq 'pixels d))
                     (if (eq? (cdr (assq 'renderer d)) 'cpu) "CPU" "GPU"))
             (format "last frame ~,1f ms" *frame-ms*)))]))

;; Screen's pane: one fact a line.
(define (pipeline-screen-facts v)
  (let ([d (inspect-device)] [g (inspect-glyphs)]
        [frames (inspect-frames frame-ring-rows)]
        [image (pipeline-view-image v)])
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
                 (format "~a, ~a of them not shown"
                         (length frames)
                         (length (remp (lambda (f) (list-ref f 5)) frames))))
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
                    (what "What" ,(max 80 (- (ui-table-room w) 190 72 64))))]
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
                     (ui-draw-cell
                      cx cy cw ch flags
                      (case key
                        [(name) (pipeline-node-name node)]
                        [(first)
                         (number->string (pipeline-node-first v node))]
                        [(count)
                         (number->string (pipeline-node-count v node))]
                        [else (pipeline-node-what node)]))))]
         [select! (lambda (node) (pipeline-view-selected-set! v node))])
    (if traced
        (let ([ch (ui-control-height)])
          (ui-draw-label x y (- w 90) ch '(dim)
                         (format "Records at pixel ~a, ~a"
                                 (car traced) (cadr traced)))
          (ui-button ui '(pipeline untrace) (+ x w -80) y 80 ch "All"
                     (lambda () (pipeline-view-traced-set! v #f)))
          (ui-table ui '(pipeline traced) x (+ y ch 4) w (- h ch 4) columns
                    (caddr traced) (pipeline-view-selected v) select! cell))
        (ui-tree ui '(pipeline tree) x y w h columns
                 (pipeline-span-nodes (pipeline-view-groups v))
                 (lambda (node) (pipeline-children v node))
                 (pipeline-view-selected v) select! cell
                 'dim (lambda (node) (pipeline-node-off? v node))))))

(define (pipeline-screen-pane v x y w h)
  (let ([lh (font-line-height 'ui)])
    (for-each (lambda (fact i)
                (let ([ly (+ y (* i (+ lh 4)))])
                  (ui-draw-label x ly 120 lh '(dim) (car fact))
                  (ui-draw-label (+ x 124) ly (- w 124) lh '() (cdr fact))))
              (pipeline-screen-facts v)
              (iota (length (pipeline-screen-facts v))))))

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
         [river-h (pipeline-river-height v (- w pad pad))]
         [tape-h (pipeline-tape-height v (- w pad pad))]
         [side (min 360 (quotient w 2))]
         [top (+ pad card-h gap)]
         [bottom (max top (- h pad river-h gap tape-h gap))]
         [l (pipeline-view-shown v)]
         [ch (ui-control-height)]
         [screen-w (- side pad)]
         ;; as tall as the screen's shape says, but for the three rows under
         ;; it: the viewer fits the screen in whatever it's given
         [screen-h (max ch (min (exact (round (* screen-w (/ *canvas-ph*
                                                              *canvas-pw*))))
                                (- bottom top gap (* 3 (+ ch gap)))))])
    (ui-begin! ui)
    (let ([card-w (quotient (- w pad pad gap) 2)])
      (for-each
       (lambda (stage name i)
         (let ([cx (+ pad (* i (+ card-w gap)))])
           (ui-area ui (list 'pipeline stage) cx pad card-w card-h
                    (lambda () (pipeline-view-stage-set! v stage)))
           (pipeline-draw-card cx pad card-w card-h
                               (eq? stage (pipeline-view-stage v)) name
                               (pipeline-card-lines v stage))))
       '(lists screen) '("Lists" "Screen") '(0 1)))
    (let ([pane-w (- w pad pad side gap)])
      (with-clip (pad top pane-w (- bottom top))
        (if (eq? (pipeline-view-stage v) 'lists)
            (pipeline-lists-pane v pad top pane-w (- bottom top))
            (pipeline-screen-pane v pad top pane-w (- bottom top))))
      ;; the small screen, or its place while it's out; its bar, Hold
      (pipeline-image! v)
      (let* ([sx (+ pad pane-w gap)]
             [sy (+ top screen-h gap)])
        (if (pipeline-view-popped v)
            (let ([bw (+ 24 (text-width "Bring it back" 'ui))])
              (pipeline-draw-popped-out sx top screen-w screen-h)
              (ui-draw-label sx (+ top (/ (- screen-h ch ch gap) 2)) screen-w
                             ch '(dim center) "In a window of its own")
              (ui-button ui '(pipeline unpop) (+ sx (/ (- screen-w bw) 2))
                         (+ top (/ (+ (- screen-h ch ch gap) ch ch gap) 2))
                         bw ch "Bring it back"
                         (lambda () (close-window! (pipeline-view-popped v)))))
            (begin
              (pipeline-viewer v ui '(pipeline viewer) sx top screen-w screen-h)
              (pipeline-viewer-bar v ui sx sy screen-w screen-w screen-h #f)))
        (ui-checkbox ui '(pipeline hold) sx (+ sy ch gap)
                     screen-w ch "Hold this frame" (pipeline-view-held? v)
                     (lambda (on?)
                       (if on? (pipeline-hold! v) (pipeline-resume! v))))
        (let* ([ey (+ sy ch gap ch gap)]
               [every (pipeline-view-every v)]
               [label "Draw it every"]
               [lw (+ 8 (text-width label 'ui))])
          (ui-draw-label sx ey lw ch '(dim) label)
          (let ([sw (ui-stepper
                     ui '(pipeline every) (+ sx lw) ey every 1 60
                     (lambda (n) (pipeline-view-every-set! v n))
                     'tip "How often the small screen draws again, in frames: \
                           each time, the GPU goes over the whole frame once \
                           more")])
            (ui-draw-label (+ sx lw sw 8) ey (max 0 (- screen-w lw sw 8)) ch
                           '(dim) (if (= every 1) "tick" "ticks"))))
        ;; what a frame kept can't show
        (when (and (pipeline-view-held? v) (> (inspect-list-left-out l) 0))
          (ui-draw-label sx (+ sy ch gap ch gap ch gap)
                         screen-w 0 '(hint wrap)
                         "An image or a paint let go of since this frame \
                          is left out of it here."))))
    (pipeline-tape-pane v pad (+ bottom gap) (- w pad pad) tape-h)
    (pipeline-river-pane v pad (- h pad river-h) (- w pad pad) river-h)
    (ui-end! ui w h)))

;; Each tick while it flows: the frame just drawn is kept, a new bar drawn, and
;; the small screen with it as often as it's told.
(define (pipeline-tick! v win)
  (ui-tick (pipeline-view-ui v) win)
  (when (pipeline-view-playing v)
    (pipeline-play-tick! v)
    (invalidate! win))
  (when (pipeline-view-loupe? v) (pipeline-loupe-follow! v win))
  (unless (pipeline-view-held? v)
    (pipeline-flip! v)
    (let ([history (pipeline-view-history v)])
      (inspect-history-add! history)
      (when (zero? (modulo (inspect-history-newest history)
                           (pipeline-view-every v)))
        (pipeline-preview-back! v)))
    (let ([newest (profile-newest-tick)])
      (when (and newest
                 (not (eqv? newest (ui-stream-sent (pipeline-view-river v)))))
        (invalidate! win)))
    (when (> (- (now-ms) (pipeline-view-looked v)) pipeline-period-ms)
      (pipeline-look! v)
      (invalidate! win))))

(define-app (pipeline) "Pipeline"
  (let ([existing (find-window 'pipeline)])
    (if existing
        (begin (focus-window! existing) existing)
        (let* ([ui (make-ui)]
               [river (ui-stream-new pipeline-river-rows (length monitor-phases)
                                     pipeline-draw-lanes)]
               [v (make-pipeline-view ui (inspect-history-new
                                          pipeline-frames-kept)
                                      river 'lists (inspect-list) #f 0 '() #f #f
                                      #f #f #f #f #f #f '() 0.0 #f 1
                                      (pipeline-tape-new 0) #f #f 5
                                      #f #f #f #f '() #f #f)])
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
                          (ui-stream-release! (pipeline-view-tape v)))
                 (append
                  (ui-handlers ui)
                  (list 'tick (lambda (win) (pipeline-tick! v win)))))))))
