;;; (schevana kits inspect) — the rendering pipeline as plain data, for the
;;; Pipeline app, a REPL or a test. It only reads.
;;;
;;; A frame is recorded in the buffers it would be read from, so a list is
;;; read from a copy of the last frame's: (inspect-list), about 2 µs for 150
;;; KB. What is read from it comes in device pixels, the screen's.

(library (schevana kits inspect)
  (export
    inspect-frames inspect-frame-ref inspect-frame-report inspect-frame-shown?
    inspect-frame-sent inspect-frame-stamp-late inspect-frame-screen
    inspect-frame-at inspect-frame-latency inspect-clock-moves
    inspect-frames-kept inspect-frames-truth inspect-frames-truths
    inspect-refresh-grid inspect-refresh-period inspect-refresh-estimated?
    inspect-refresh-of inspect-refresh-time inspect-frame-refresh
    inspect-frame-target inspect-refresh-latch inspect-frame-input inspect-list
    inspect-list-empty inspect-record-list inspect-span-lists inspect-list-facts
    inspect-list-owner inspect-list-part inspect-list-lists
    inspect-list-original inspect-list-basis inspect-list-count
    inspect-list-labels inspect-list-bytes inspect-list-runs inspect-computes
    inspect-list-frame inspect-list-left-out inspect-history-newest
    inspect-history-new inspect-history-add! inspect-history-ref
    inspect-history-copies inspect-history-count inspect-history-bytes
    inspect-word inspect-clip inspect-kind inspect-reach inspect-record
    inspect-rows inspect-what inspect-record-paint inspect-paint-text
    inspect-records-at inspect-label-at inspect-platform inspect-display-pixels
    inspect-display-hz inspect-platform-row inspect-device inspect-glyphs
    inspect-gpu-objects inspect-gpu-held inspect-present-mode inspect-core0
    inspect-pacer inspect-pacer2 inspect-pacer-rows inspect-shader-constants
    inspect-shader-helpers
    inspect-shader-fields inspect-preview-image inspect-preview-w
    inspect-preview-h inspect-preview-free! inspect-preview-bytes
    inspect-preview! inspect-preview-list! inspect-list-paint! inspect-span-cost
    inspect-record-same? inspect-span-changed inspect-record-run
    inspect-run-fragment inspect-shader-lines inspect-atlas-image
    inspect-list-tree inspect-recordings inspect-reload inspect-auto-loads
    inspect-world-later)
  (import (chezscheme)
          (only (schevana base) define-made library-layer platform-cpu
                platform-os string-join string-prefix? string-suffix?)
          (only (schevana core) *world-later* auto-loads *atlas-row* *atlas-y*
                *canvas-ph* *canvas-pw* *canvas-ratio* *font-specs* *frame-ring*
                *frame-ring-n* *glyph-count* *gpu-bytes-made* *gpu-computes*
                *gpu-facts* *gpu-held-gone* *pacer-aimed* *pacer-counts*
                *pacer-depth* *pacer-due* *pacer-floor* *pacer-frame-ns*
                *pacer-gpu-taught* *pacer-latch* *pacer-latch-phase*
                *pacer-late-chain* *pacer-late-run* *pacer-lead* *pacer-made*
                *pacer-shown?* *rec-label-at* *rec-labels*
                *schevana-root* *shader-constants* *shader-fields*
                *shader-helpers* *windows* clip-row-parent clip-row-radius
                clip-row-rx0 clip-row-rx1 clip-row-ry0 clip-row-ry1
                clip-row-words clip-row-x0 clip-row-x1 clip-row-y0 clip-row-y1
                core0-display core0-flag-names core0-flags core0-frame-ns
                core0-frame-report core0-step-state core0-window-scale
                core0-window-sizes core0-app-id screen-system-theme
                *screen-least* font-advance font-library-versions font-ready
                font-sized frame-ring-rows frame-ring-words gfx-fragments
                glyph-row-character glyph-row-h glyph-row-left glyph-row-ref
                glyph-row-top glyph-row-w gpu-atlas-image gpu-atlas-side
                gpu-call-shader gpu-call? gpu-image-h gpu-image-levels
                gpu-image-make-target gpu-image-release! gpu-image-w
                gpu-list-extras gpu-list-extras-n gpu-list-id gpu-list-labels
                gpu-list-recorded gpu-list-recs gpu-list-recs-n gpu-list-runs
                gpu-list-took gpu-list-version gpu-run-gone? gpu-show-run?
                gradient-row-kind gradient-row-x0 gradient-row-x1
                gradient-row-y0 gradient-row-y1 now-ns pacer-margin pacer-period
                pacer-rate pacer-start pacer-ticks pacer2? pacer2-period
                pacer2-state core0-look-ns platform-cpu-count platform-fact
                platform-gpu-api platform-predicates platform-windowing
                rec-box-line rec-box-radius rec-glyph-number rec-glyph-pen-x
                rec-glyph-pen-y rec-gradient-radial rec-kind-glyph
                rec-kind-polygon rec-last-copy! rec-last-runs rec-last-sizes
                rec-list-copy rec-paint-gradient rec-paint-image
                rec-paint-stipple rec-past! rec-polygon-count rec-polygon-points
                rec-preview! rec-recordings rec-row-head rec-row-paint
                rec-row-words rec-row-x0 rec-row-x1 rec-row-y0 rec-row-y1
                rec-segment-width rec-shadow-size rec-variant reload-facts
                shader shader-name shader-source window-ref window-title
                world-value))

  (library-layer kits)

  ;; The names of (schevana core draw)'s record kinds and paints, by number;
  ;; a test holds the two together.
  (define inspect-kinds '#(box segment polygon glyph shadow))
  (define inspect-paints '#(solid gradient stipple image shader))

  ;;; -- frames

  ;; Returns the newest n frames at most, newest first, each as (us records
  ;; extras runs glyphs shown? screen latency), where screen and latency are
  ;; what the screen said of it (inspect-frame-screen, inspect-frame-latency).
  (define (inspect-frames n)
    (let ([have (min n *frame-ring-n* frame-ring-rows)])
      (map (lambda (k)
             (let* ([i (- *frame-ring-n* k 1)]
                    [at (* frame-ring-words (modulo i frame-ring-rows))]
                    [ring *frame-ring*])
               (list (fxvector-ref ring at)
                     (fxvector-ref ring (+ at 1))
                     (fxvector-ref ring (+ at 2))
                     (fxvector-ref ring (+ at 3))
                     (fxvector-ref ring (+ at 4))
                     (= 1 (fxvector-ref ring (+ at 5)))
                     (inspect-frame-screen i)
                     (inspect-frame-latency i))))
           (iota have))))

  ;;; -- what became of each frame
  ;;; Frame i counts from 0 for the first frame drawn, and is there as long
  ;;; as the ring keeps it; its report, the screen's (core0-frame-report), is
  ;;; found by its number.

  ;; Returns word k of frame i's row (in inspect-frames' order, then its
  ;; number, then when the oldest input it shows came, ...), or #f once the
  ;; frame is gone.
  (define (inspect-frame-ref i k)
    (and (< -1 i *frame-ring-n*)
         (> i (- *frame-ring-n* frame-ring-rows 1))
         (fxvector-ref *frame-ring*
                       (+ k (* frame-ring-words (modulo i frame-ring-rows))))))

  ;; Returns word k of frame i's report, or #f: 1 its kind (0 sent, 1 shown,
  ;; 2 dropped); 2 when it was sent; 3 when the refresh it showed at came, by
  ;; the screen's clock (now-ns); 4 that refresh's length; 5 that refresh's
  ;; number, counted from the reports' times; 6 when its GPU work was seen
  ;; done (0 for not yet); 7 when core0 took it, and 8 and 9 when core0's
  ;; acquire of a swapchain image for it began and returned; 10 the screen's
  ;; own stamp of its showing; 11 the last look that found its GPU work
  ;; still going (0 for none).
  (define (inspect-frame-report i k)
    (let ([n (inspect-frame-ref i 6)])
      (and n (> n 0) (core0-frame-report n k))))

  (define (inspect-frame-shown? i) (eqv? (inspect-frame-report i 1) 1))

  ;; Returns what core0 did with frame i: 'sent it to the screen, or found
  ;; that the window had 'no-room for it; #f until core0 gives it back.
  (define (inspect-frame-sent i)
    (case (inspect-frame-ref i 5)
      [(1) 'sent]
      [(2) 'no-room]
      [else #f]))

  ;; Returns how many refreshes showed frame i-1 again before frame i, while
  ;; frames came a period apart (sent within one and a half refreshes of
  ;; each other): the screen froze where an update was due. Returns 0 when
  ;; frame i showed in time, and #f when it can't be told (no report, or
  ;; frames further apart).
  (define (inspect-frame-missed i)
    (and (inspect-frame-shown? i) (inspect-frame-shown? (- i 1))
         (let ([p (inspect-frame-report i 4)]
               [gap (- (inspect-frame-report i 2)
                       (inspect-frame-report (- i 1) 2))])
           (and (> p 0) (< (* 2 gap) (* 3 p))
                (max 0 (- (inspect-frame-report i 5)
                          (inspect-frame-report (- i 1) 5)
                          1))))))

  ;; Returns how long, in ns, after the refresh frame i showed at (by the
  ;; screen's clock) the screen stamped it: how late the stamp ran (0 when
  ;; it didn't); #f when the frame didn't show.
  (define (inspect-frame-stamp-late i)
    (and (inspect-frame-shown? i)
         (max 0 (- (inspect-frame-report i 10) (inspect-frame-report i 3)))))

  ;; Returns what became of frame i on the screen: 'shown, 'late
  ;; (inspect-frame-missed), 'dropped by the compositor, or #f (no report
  ;; yet).
  (define (inspect-frame-screen i)
    (case (inspect-frame-report i 1)
      [(1) (let ([m (inspect-frame-missed i)])
             (if (and m (> m 0)) 'late 'shown))]
      [(2) 'dropped]
      [else #f]))

  ;; Returns when frame i reached point (now-ns), or #f. The points are: its
  ;; oldest input by SDL's stamp (sdl), by the compositor's own time (wl),
  ;; and as core0's pump first saw it (pumped); its tick as the pacer
  ;; planned it (planned), and its tick, its draw and its publish on core1
  ;; (tick, draw, publish); core0 taking it (taken), asking for a swapchain
  ;; image for it and getting one (acquiring, acquired), and sending it
  ;; (sent); its GPU work seen done (gpu); and on the screen, by the
  ;; screen's clock (shown) and by the screen's own stamp (stamped).
  (define (inspect-frame-at i point)
    (let ([t (case point
               [(sdl) (inspect-frame-ref i 7)]
               [(tick) (inspect-frame-ref i 8)]
               [(draw) (inspect-frame-ref i 9)]
               [(publish) (inspect-frame-ref i 10)]
               [(pumped) (inspect-frame-ref i 11)]
               [(wl) (inspect-frame-ref i 12)]
               [(planned) (inspect-frame-ref i 14)]
               [(taken) (inspect-frame-report i 7)]
               [(acquiring) (inspect-frame-report i 8)]
               [(acquired) (inspect-frame-report i 9)]
               [(sent) (inspect-frame-report i 2)]
               [(gpu) (inspect-frame-report i 6)]
               [(shown) (and (inspect-frame-shown? i)
                             (inspect-frame-report i 3))]
               [(stamped) (and (inspect-frame-shown? i)
                               (inspect-frame-report i 10))]
               [else #f])])
      (and t (> t 0) t)))

  ;; Returns the time in ns from the oldest input that frame i shows to its
  ;; showing, the input's time taken by point (sdl, wl or pumped); #f when
  ;; the frame shows no input, or hasn't shown.
  (define (inspect-frame-latency-from i point)
    (let ([in (inspect-frame-at i point)] [shown (inspect-frame-at i 'shown)])
      (and in shown (- shown in))))

  ;; The same, by SDL's stamp.
  (define (inspect-frame-latency i) (inspect-frame-latency-from i 'sdl))

  ;;; -- the screen's clock's drift
  ;; Returns how far core0's clock ((schevana core0 present)) moved, in ns,
  ;; at each refresh from refresh oldest on that a frame showed at: the
  ;; refresh's time past that of the frame shown before it and the periods
  ;; between them, negative when it came earlier. The result is ((refresh .
  ;; ns) ...), oldest first, with none for the first frame shown, for one
  ;; reported out of order, or on a screen with no steady refresh.
  (define (inspect-clock-moves oldest)
    (let loop ([i (- *frame-ring-n* 1)] [later #f] [moves '()])
      (cond
        [(not (inspect-frame-ref i 6)) moves]
        [(not (and (inspect-frame-shown? i) (> (inspect-frame-report i 4) 0)))
         (loop (- i 1) later moves)]
        [else
         (let ([t (inspect-frame-report i 3)] [k (inspect-frame-report i 5)])
           (cond
             [(not later) (if (< k oldest) moves
                              (loop (- i 1) (cons t k) moves))]
             [(> (cdr later) k)
              (let ([move (cons (cdr later)
                                (- (car later) t
                                   (* (- (cdr later) k)
                                      (inspect-frame-report i 4))))])
                (if (< k oldest)
                    (cons move moves)
                    (loop (- i 1) (cons t k) (cons move moves))))]
             [else (loop (- i 1) (cons t k) moves)]))])))

  ;; Returns (values kept not-shown): how many frames are kept, and how many
  ;; of them had no room on the screen.
  (define (inspect-frames-kept)
    (let ([n (min *frame-ring-n* frame-ring-rows)])
      (let loop ([k 0] [not-shown 0])
        (if (= k n)
            (values n not-shown)
            (loop (+ k 1)
                  (if (eqv? 2 (inspect-frame-ref (- *frame-ring-n* k 1) 5))
                      (+ not-shown 1)
                      not-shown))))))

  ;; Returns (values p50 p99 missed) for the frames published in the last ms
  ;; milliseconds: the 50th and 99th percentiles of their input-to-screen
  ;; times (in ns, #f with none), the input's time taken by point (as for
  ;; inspect-frame-latency-from), and the refreshes they missed.
  (define (inspect-frames-truth ms . point)
    (let-values ([(by missed) (inspect-frames-truths
                               ms (list (if (pair? point) (car point) 'sdl)))])
      (values (caar by) (cadar by) missed)))

  ;; Returns the same for each of points, in one walk of the frames, which is
  ;; most of the cost: (values ((p50 p99) ...) missed).
  (define (inspect-frames-truths ms points)
    (let ([since (- (now-ns) (* ms 1000000))])
      ;; chosen by when they were published: the newest frames, not yet
      ;; sent, have no report
      (let loop ([i (- *frame-ring-n* 1)] [lats (map (lambda (p) '()) points)]
                 [missed 0])
        (let ([publish (inspect-frame-at i 'publish)])
          (if (and publish (> publish since))
              (loop (- i 1)
                    (let ([shown (inspect-frame-at i 'shown)])
                      (if shown
                          (map (lambda (point ls)
                                 (let ([in (inspect-frame-at i point)])
                                   (if in (cons (- shown in) ls) ls)))
                               points lats)
                          lats))
                    (+ missed (or (inspect-frame-missed i) 0)))
              (values
               (map (lambda (ls)
                      (let* ([v (list->vector (sort <
                                                    ls))] [n (vector-length v)]
                             [at (lambda (q)
                                   (and (> n 0)
                                        (vector-ref v (min (- n 1)
                                                           (exact
                                                            (floor (* q
                                                                      n)))))))])
                        (list (at 0.5) (at 0.99))))
                    lats)
               missed))))))

  ;;; -- refreshes
  ;;; The screen's rhythm, with a number for each refresh: core0's count from
  ;;; the reports' times ((schevana core0 present)), anchored at the newest
  ;;; frame the screen reported showing. Where the screen reports none, the
  ;;; refreshes are an estimate, counted a period apart from now-ns's 0. A
  ;;; refresh's time is its vblank's (now-ns).

  ;; Returns the grid as it stands, as its anchor: #(refresh time period
  ;; estimated?).
  (define (inspect-refresh-grid)
    (let loop ([i (- *frame-ring-n* 1)] [k 0])
      (cond
        [(or (= k 64) (< i 0)) (vector 0 0 (core0-frame-ns) #t)]
        [(and (inspect-frame-shown? i) (> (inspect-frame-report i 4) 0))
         (vector (inspect-frame-report i 5) (inspect-frame-report i 3)
                 (inspect-frame-report i 4) #f)]
        [else (loop (- i 1) (+ k 1))])))

  (define (inspect-refresh-period g) (vector-ref g 2))
  (define (inspect-refresh-estimated? g) (vector-ref g 3))

  ;; Returns the refresh at t (now-ns), or the last one before it, by grid g.
  (define (inspect-refresh-of g t)
    (+ (vector-ref g 0) (div (- t (vector-ref g 1)) (vector-ref g 2))))

  ;; Returns refresh k's time, by grid g.
  (define (inspect-refresh-time g k)
    (+ (vector-ref g 1) (* (- k (vector-ref g 0)) (vector-ref g 2))))

  ;; Returns the refresh frame i showed at, by grid g: its report's. With no
  ;; reports, once core0 has sent it, the estimate is the refresh after it
  ;; was sent (or published, with no screen). #f when it didn't show, or
  ;; hasn't yet.
  (define (inspect-frame-refresh g i)
    (cond
      [(inspect-frame-shown? i) (inspect-frame-report i 5)]
      [(and (inspect-refresh-estimated? g) (eq? (inspect-frame-sent i) 'sent))
       (+ 1 (inspect-refresh-of g (or (inspect-frame-at i 'sent)
                                      (inspect-frame-at i 'publish))))]
      [else #f]))

  ;; Returns the refresh frame i was meant for: as the first pacer planned
  ;; it, the one after the latch its tick aimed at; as the second planned
  ;; it, the refresh its tick aimed at; with no aim, the second one after
  ;; its tick began; #f with no tick.
  (define (inspect-frame-target g i)
    (let ([aimed (inspect-frame-ref i 13)])
      (if (and aimed (> aimed 0))
          (+ (if (eqv? (inspect-frame-ref i 15) 2) 0 1)
             (inspect-refresh-of g aimed))
          (let ([tick (inspect-frame-at i 'tick)])
            (and tick (+ 2 (inspect-refresh-of g tick)))))))

  ;; Returns where the cutoff for refresh k lies as the pacer in use holds
  ;; it, or #f while it isn't known. For the first pacer, when the
  ;; compositor took the frame shown there: in the refresh before, at the
  ;; latch's phase as the pacer learned it. For the second, its hold before
  ;; the refresh, by which a frame's GPU work must be seen done.
  (define (inspect-refresh-latch g k)
    (if (pacer2?)
        (let ([hold (pacer2-state 'hold)])
          (and (> hold 0) (- (inspect-refresh-time g k) hold)))
        (and *pacer-latch-phase*
             (+ (inspect-refresh-time g (- k 1)) *pacer-latch-phase*))))

  ;; Returns when the oldest input that frame i shows came: by the
  ;; compositor's own time, else by SDL's stamp, else by core0's pump; #f
  ;; with none.
  (define (inspect-frame-input i)
    (or (inspect-frame-at i 'wl) (inspect-frame-at i 'sdl)
        (inspect-frame-at i 'pumped)))

  ;;; -- lists

  ;; Returns a copy of the last frame's list: #(records extras labels count
  ;; words row runs frame segments), where labels is ((label first-record
  ;; count) ...) in draw order, row is the frame's row in inspect-frames,
  ;; runs its runs, frame its number, and segments where its records came
  ;; from (inspect-record-list). The lists the frame shows are in it,
  ;; flattened: each one's records are where its runs draw them, moved to
  ;; where the list is shown and cut to its clip, so the copy draws the same
  ;; pixels from one list, and its records come in the order they are drawn.
  (define (inspect-list) (inspect-list-read! (inspect-list-empty)))

  (define (inspect-list-empty)
    (vector (make-bytevector 0) (make-bytevector 0) '() 0 0 #f '() -1 '()))

  ;; The last frame's records and extras as the kit reads them: its own copy
  ;; (the recorder lends a frame's bytes to no one), its buffers kept to grow.
  (define-made inspect-last-bytes
    (vector (make-bytevector 0) (make-bytevector 0)))
  (define (inspect-last-read!)
    (let-values ([(recs-n extras-n) (rec-last-sizes)])
      (let ([fit (lambda (k n)
                   (when (< (bytevector-length (vector-ref inspect-last-bytes
                                                           k))
                            n)
                     (vector-set! inspect-last-bytes k
                                  (make-bytevector (+ n (quotient n 4))))))])
        (fit 0 recs-n)
        (fit 1 extras-n)
        (rec-last-copy! (vector-ref inspect-last-bytes 0)
                        (vector-ref inspect-last-bytes 1))
        (values (vector-ref inspect-last-bytes 0) recs-n
                (vector-ref inspect-last-bytes 1) extras-n))))

  ;; Fills l with the last list recorded, the frame's, in l's own buffers
  ;; when they are big enough: they stay where they are, and a collection
  ;; needn't copy them.
  (define (inspect-list-read! l)
    (let-values ([(newest) (inspect-frames 1)]
                 [(recs recs-n extras extras-n) (inspect-last-read!)])
      ;; the runs of the frame whose records these are, not of what was
      ;; recorded since (a drawing, a window's icon)
      (inspect-list-flat! l recs recs-n extras extras-n (rec-last-runs)
                          (list->vector (list-head (vector->list *rec-labels*)
                                                   *rec-label-at*))
                          (and (pair? newest) (car newest))
                          (- *frame-ring-n* 1))))

  ;; Returns the list that record i of l came from, and its place there, as
  ;; (values list j), with list #f for the root's.
  (define (inspect-record-list l i)
    (let ([s (find (lambda (s) (< -1 (- i (vector-ref s 1)) (vector-ref s 2)))
                   (vector-ref l 8))])
      (if s
          (values (vector-ref s 0) (+ (vector-ref s 3) (- i (vector-ref s 1))))
          (values #f i))))

  ;; Returns the lists that records first to first + count of l came from,
  ;; each once, in order: the lists of a drawer.
  (define (inspect-span-lists l first count)
    (fold-left (lambda (acc s)
                 (let ([lst (vector-ref s 0)])
                   (if (and lst
                            (< -1 (- (vector-ref s 1) first) count)
                            (not (memq lst acc)))
                       (append acc (list lst))
                       acc)))
               '() (vector-ref l 8)))

  ;; Returns what a list is: ((owner . name) (version . n) (records . n)
  ;; (bytes . n) (recorded . ns) (took . ns)), recorded on now-ns's clock.
  (define (inspect-list-facts lst)
    `((owner . ,(inspect-list-owner lst))
      (version . ,(gpu-list-version lst))
      (records . ,(fxquotient (gpu-list-recs-n lst) 32))
      (bytes . ,(+ (gpu-list-recs-n lst) (gpu-list-extras-n lst)))
      (recorded . ,(gpu-list-recorded lst))
      (took . ,(gpu-list-took lst))))

  ;; Returns the recorder's recordings that x holds, newest first: a list's,
  ;; the root's (#f, the frames'), the copies drawn ahead of frames
  ;; ('earlier), the writes handed to core0 ('writes), or an image's loans.
  ;; Each is ((version . n) (until . frame) (free . bool)), with until #f
  ;; for the newest, which nothing has replaced, or for a loan not yet
  ;; handed.
  (define (inspect-recordings x)
    (map (lambda (r)
           `((version . ,(car r)) (until . ,(cadr r)) (free . ,(caddr r))))
         (rec-recordings x)))

  ;; Return whose a list is, in words, and which of its owner's lists it is:
  ;; a window's whole list, frame and all, is window, its content's is
  ;; content, and any other is list. A kept copy's are those of its list
  ;; when the copy was made.
  (define (inspect-list-owner lst) (car (inspect-list-whose lst)))
  (define (inspect-list-part lst) (cdr (inspect-list-whose lst)))

  (define (inspect-list-whose lst)
    (or (hashtable-ref inspect-owners lst #f)
        (let loop ([ws *windows*])
          (cond [(null? ws) '("a list" . list)]
                [(eq? (window-ref (car ws) 'wm-list) lst)
                 (cons (window-title (car ws)) 'window)]
                [(eq? (window-ref (car ws) 'wm-content-list) lst)
                 (cons (window-title (car ws)) 'content)]
                [else (loop (cdr ws))]))))

  ;; Returns the lists that l's records came from, each once, in order.
  (define (inspect-list-lists l)
    (inspect-span-lists l 0 (inspect-list-count l)))

  ;;; -- lists kept: one copy per version

  ;; Caches, which only save copying: each list's newest copy, and each
  ;; copy's owner, as said when it was made (inspect-list-whose); and each
  ;; copy's list and basis, (list . basis). They are ephemeron tables, not
  ;; weak ones: a copy is often its own basis, and a weak table's value
  ;; keeps its key.
  (define-made inspect-copies (make-ephemeron-eq-hashtable))
  (define-made inspect-owners (make-ephemeron-eq-hashtable))
  (define-made inspect-sources (make-ephemeron-eq-hashtable))

  ;; Returns the list that a copy is of; for a list that isn't a copy, the
  ;; list itself.
  (define (inspect-list-original copy)
    (let ([s (hashtable-ref inspect-sources copy #f)]) (if s (car s) copy)))

  ;; Returns the first of the copies in a row that hold the very same
  ;; records as copy: when a list is recorded again the same, its basis is
  ;; that of the copy before.
  (define (inspect-list-basis copy)
    (let ([s (hashtable-ref inspect-sources copy #f)]) (if s (cdr s) copy)))

  ;; Whether copies a and b hold the very same records and extras, and show
  ;; the same.
  (define (inspect-copy-same? a b)
    (and (bytevector=? (gpu-list-recs a) (gpu-list-recs b))
         (bytevector=? (gpu-list-extras a) (gpu-list-extras b))
         (= (length (gpu-list-runs a)) (length (gpu-list-runs b)))
         (for-all (lambda (r s)
                    (if (and (gpu-show-run? r) (gpu-show-run? s))
                        (and (eq? (inspect-list-basis (cadr r))
                                  (inspect-list-basis (cadr s)))
                             (equal? (cddr r) (cddr s)))
                        (equal? r s)))
                  (gpu-list-runs a) (gpu-list-runs b))))

  ;; Returns lst as it is now, to keep: a copy of its records and extras,
  ;; whose runs show copies of the lists it shows. It is the same copy as
  ;; the last time while lst and those lists haven't changed.
  (define (inspect-list-copy lst)
    (let ([runs (inspect-runs-copied (gpu-list-runs lst))]
          [old (hashtable-ref inspect-copies lst #f)])
      (if (and old
               (= (gpu-list-version old) (gpu-list-version lst))
               (for-all eq? runs (gpu-list-runs old)))
          old
          (let ([copy (rec-list-copy lst runs)])
            (hashtable-set! inspect-copies lst copy)
            (hashtable-set! inspect-owners copy (inspect-list-whose lst))
            (hashtable-set! inspect-sources copy
                            (cons lst
                                  (if (and old (inspect-copy-same? copy old))
                                          (inspect-list-basis old)
                                          copy)))
            copy))))

  ;; Returns runs, with each run that shows a list showing the list's copy
  ;; instead. The other runs are the same objects, and a show run is the
  ;; same as the last time while its copy is.
  (define (inspect-runs-copied runs)
    (map (lambda (run)
           (if (gpu-show-run? run)
               (let ([copy (inspect-list-copy (cadr run))]
                     [old (hashtable-ref inspect-shows run #f)])
                 (if (and old (eq? (cadr old) copy))
                     old
                     (let ([new (cons* 'show copy (cddr run))])
                       (hashtable-set! inspect-shows run new)
                       new)))
               run))
         runs))

  ;; For each show run, its copy that shows a list's copy: a cache too.
  (define-made inspect-shows (make-ephemeron-eq-hashtable))

  ;; Returns the bytes the flattened list takes, as (records . extras):
  ;; each list as often as it is shown, and a clip row for each show.
  (define (inspect-flat-size recs-n extras-n runs)
    (fold-left (lambda (n run)
                 (if (gpu-show-run? run)
                     (let* ([lst (cadr run)]
                            [in (inspect-flat-size (gpu-list-recs-n lst)
                                                   (gpu-list-extras-n lst)
                                                   (gpu-list-runs lst))])
                       (cons (+ (car n) (car in))
                             (+ (cdr n) (cdr in) (* 4 clip-row-words))))
                     n))
               (cons recs-n extras-n) runs))

  ;; Writes the list (recs, extras, its runs and labels, as the recorder
  ;; keeps them) and the lists it shows into to and to-extras, flattened.
  ;; Returns (labels count words runs segments): labels is ((first . label)
  ;; ...) in order, count the records, words the extras' words, and
  ;; segments where each stretch of records came from, #(list first count
  ;; its-first), with list #f for the root's.
  (define (inspect-flatten! to to-extras recs extras extras-n runs labels)
    (let ([count 0] [words 1] [out-runs '()] [out-labels '()]
          [segments '()])
      (define (word bv i) (bytevector-s32-native-ref bv (fx* 4 i)))
      (define (word! bv i v) (bytevector-s32-native-set! bv (fx* 4 i) v))
      ;; a label the same as the one before it just goes on
      (define (label! text)
        (unless (and (pair? out-labels) (equal? (cdar out-labels) text))
          (set! out-labels (cons (cons count text) out-labels))))
      ;; copies a list's extras, bytes long, after those so far, its rows
      ;; moved by (dx, dy) in 256ths and a clip's cut to box; then its
      ;; records, by recs-of, which is handed how to find and move its
      ;; rows. The extras' first word is the reserved one, and a list not
      ;; recorded yet has no extras at all.
      (define (extras! from bytes dx dy box recs-of)
        (let ([base (fx- words 1)] [seen (make-eqv-hashtable)]
              [n (fxmax 0 (fx- (fxquotient bytes 4) 1))])
          (when (fx> n 0)
            (bytevector-copy! from 4 to-extras (fx* 4 words) (fx* 4 n)))
          (set! words (fx+ words n))
          (let ([sr (and box
                         (let ([r words])
                           (for-each (lambda (k v) (word! to-extras (+ r k) v))
                                     (iota clip-row-words)
                                     (list (car box) (cadr box) (caddr box)
                                           (cadddr box) 0 0 (car box) (cadr box)
                                           (caddr box) (cadddr box)))
                           (set! words (fx+ words clip-row-words))
                           r))])
            (define (at row) (fx+ base row))
            (define (move! row k d)
              (let ([i (at (+ row k))])
                (word! to-extras i (+ d (word to-extras i)))))
            (define (clip! row)
              (unless (or (fx= row 0) (hashtable-ref seen row #f))
                (hashtable-set! seen row #t)
                (for-each (lambda (k d) (move! row k d))
                          (list clip-row-x0 clip-row-y0 clip-row-x1 clip-row-y1
                                clip-row-rx0 clip-row-ry0 clip-row-rx1
                                clip-row-ry1)
                          (list dx dy dx dy dx dy dx dy))
                (when box
                  (let ([cut (lambda (k f v)
                               (word! to-extras (at (+ row k))
                                      (f v (word to-extras (at (+ row k))))))])
                    (cut clip-row-x0 max (car box))
                    (cut clip-row-y0 max (cadr box))
                    (cut clip-row-x1 min (caddr box))
                    (cut clip-row-y1 min (cadddr box))))
                (let ([parent (word to-extras (at (+ row clip-row-parent)))])
                  (word! to-extras (at (+ row clip-row-parent))
                         (cond [(not (fx= parent 0)) (at parent)]
                               [sr sr]
                               [else 0]))
                  (clip! parent))))
            (define (paint! row kind)
              (unless (hashtable-ref seen row #f)
                (hashtable-set! seen row #t)
                (when (fx= kind rec-paint-gradient)
                  (move! row gradient-row-x0 dx)
                  (move! row gradient-row-y0 dy)
                  (unless (fx= (word to-extras (at (+ row gradient-row-kind)))
                               rec-gradient-radial)
                    (move! row gradient-row-x1 dx)
                    (move! row gradient-row-y1 dy)))))
            (define (points! row n)
              (unless (hashtable-ref seen row #f)
                (hashtable-set! seen row #t)
                (do ([k 0 (fx+ k 1)]) ((fx= k n))
                  (move! row (fx* 2 k) dx)
                  (move! row (fx+ 1 (fx* 2 k)) dy))))
            (recs-of at sr clip! paint! points!))))
      ;; copies a list's records first to first + n to the end of to, moved
      ;; by (dx, dy) in 256ths, their rows found by at
      (define (records! lst from first n dx dy at sr clip! paint! points!)
        (set! segments (cons (vector lst count n first) segments))
        (bytevector-copy! from (fx* 32 first) to (fx* 32 count) (fx* 32 n))
        (do ([i count (fx+ i 1)]) ((fx= i (fx+ count n)))
          (let* ([o (fx* i rec-row-words)]
                 [head (fxand (word to o) #xffffffff)]
                 [kind (fxand head 15)]
                 [paint (fxand (fxsrl head 4) 15)]
                 [clip (fxsrl head 8)])
            (define (move! k d) (word! to (+ o k) (+ d (word to (+ o k)))))
            (word! to o (fxior (fxand head 255)
                               (fxsll (cond [(not (fx= clip 0)) (at clip)]
                                            [sr sr]
                                            [else 0])
                                      8)))
            (clip! clip)
            (when (memv paint (list rec-paint-gradient rec-paint-stipple
                                    rec-paint-image))
              (word! to (+ o rec-row-paint)
                     (at (word to (+ o rec-row-paint))))
              (paint! (word from (+ (fx* (fx+ first (fx- i count))
                                         rec-row-words)
                                     rec-row-paint))
                      paint))
            (cond
              [(fx= kind rec-kind-glyph)
               (move! rec-glyph-pen-x (fxsra dx 8))
               (move! rec-glyph-pen-y (fxsra dy 8))]
              [else
               (move! rec-row-x0 dx)
               (move! rec-row-y0 dy)
               (move! rec-row-x1 dx)
               (move! rec-row-y1 dy)
               (when (fx= kind rec-kind-polygon)
                 (points! (word to (+ o rec-polygon-points))
                          (word to (+ o rec-polygon-count)))
                 (word! to (+ o rec-polygon-points)
                        (at (word to (+ o rec-polygon-points)))))])))
        (set! count (fx+ count n)))
      ;; flattens a list at (ox, oy) device pixels, inside box or none, its
      ;; runs in order, and its labels where they fall among them; no label
      ;; means outer, the label of what shows the list
      (define (flatten! lst recs extras extras-n runs labels ox oy box outer)
        (let ([dx (fx* ox 256)] [dy (fx* oy 256)] [li 0]
              [label-n (vector-length labels)])
          (define (labels-upto! k at-record)
            (let loop ()
              (when (and (fx< li (min k label-n))
                         (fx<= (vector-ref labels li) at-record))
                (label! (or (vector-ref labels (fx+ li 1)) outer))
                (set! li (fx+ li 2))
                (loop))))
          (label! outer)
          (extras! extras extras-n dx dy box
            (lambda (at sr clip! paint! points!)
              (let ([current #f])
                (for-each
                 (lambda (run)
                   (if (gpu-show-run? run)
                       (let* ([lst (cadr run)]
                              [own (and (list-ref run 4)
                                        (list-head (list-tail run 4) 4))]
                              [inner
                               (let ([b (and own
                                             (map (lambda (v d)
                                                    (fx* 256 (+ v d)))
                                                  own (list ox oy ox oy)))])
                                 (cond [(not b) box]
                                       [(not box) b]
                                       [else (list (max (car b) (car box))
                                                   (max (cadr b) (cadr box))
                                                   (min (caddr b) (caddr box))
                                                   (min (cadddr b)
                                                        (cadddr box)))]))])
                         (labels-upto! (list-ref run 8) (most-positive-fixnum))
                         (let ([shown (and (pair? out-labels)
                                           (cdar out-labels))])
                           ;; a list shown has its bytes read from its
                           ;; copy, kept while it stays the same
                           (let ([own (if (gpu-list-id lst)
                                          (inspect-list-copy lst)
                                          lst)])
                             (flatten! lst (gpu-list-recs own)
                                       (gpu-list-extras own)
                                       (gpu-list-extras-n own)
                                       (gpu-list-runs lst) (gpu-list-labels lst)
                                       (+ ox (caddr run)) (+ oy (cadddr run))
                                       inner shown))
                           (label! shown)))
                       (let ([first (caddr run)] [n (cadddr run)])
                         (let split ([first first] [n n])
                           ;; a label inside the run starts where it is
                           (labels-upto! label-n first)
                           (let ([next (and (fx< li label-n)
                                            (vector-ref labels li))])
                             (if (and next (fx< next (fx+ first n)))
                                 (let ([k (fx- next first)])
                                   (records! lst recs first k dx dy at sr clip!
                                             paint! points!)
                                   (split next (fx- n k)))
                                 (records! lst recs first n dx dy at sr clip!
                                           paint! points!))))
                         (set! out-runs
                           (cons (list (car run) (cadr run)
                                       (fx- count n) n (list-ref run 4))
                                 out-runs)))))
                 runs)
                (labels-upto! label-n (most-positive-fixnum)))))))
      (flatten! #f recs extras extras-n runs labels 0 0 #f #f)
      (list (reverse out-labels) count words (reverse out-runs)
            (reverse segments))))

  ;; Returns the labels' spans, (label first count), over the first count
  ;; records, from ((first . label) ...) in order: a label holds until the
  ;; next one, and an empty span, or one with no label, is left out.
  (define (inspect-label-spans labels count)
    (let loop ([ls labels] [acc '()])
      (if (null? ls)
          (reverse acc)
          (let* ([first (min count (caar ls))]
                 [end (if (null? (cdr ls)) count (min count (caadr ls)))])
            (loop (cdr ls)
                  (if (or (not (cdar ls)) (>= first end))
                      acc
                      (cons (list (cdar ls) first (- end first)) acc)))))))

  ;; Fills l with a root's records and extras (recs-n and extras-n bytes
  ;; long) and its runs and labels, flattened, and with the row and frame
  ;; number given. Returns l.
  (define (inspect-list-flat! l recs recs-n extras extras-n runs labels row
                              frame)
    (let ([need (inspect-flat-size recs-n extras-n runs)]
          [fit! (lambda (slot n)
                  (when (< (bytevector-length (vector-ref l slot)) n)
                    (vector-set! l slot
                                 (make-immobile-bytevector
                                  (+ n (quotient n 4))))))])
      (fit! 0 (car need))
      (fit! 1 (cdr need))
      (let ([flat (inspect-flatten! (vector-ref l 0) (vector-ref l 1)
                                    recs extras extras-n runs labels)])
        (vector-set! l 2 (inspect-label-spans (car flat) (cadr flat)))
        (vector-set! l 3 (cadr flat))
        (vector-set! l 4 (caddr flat))
        (vector-set! l 5 row)
        (vector-set! l 6 (cadddr flat))
        (vector-set! l 7 frame)
        (vector-set! l 8 (list-ref flat 4))
        l)))

  ;; Returns the lists the last frame shows, as a tree: ((x y records bytes
  ;; version children) ...) in draw order, with (x, y) in device pixels from
  ;; what shows the list, and version how many times it has been recorded.
  (define (inspect-list-tree)
    (let walk ([runs (rec-last-runs)])
      (map (lambda (run)
             (let ([lst (cadr run)])
               (list (caddr run) (cadddr run)
                     (fxquotient (gpu-list-recs-n lst) 32)
                     (+ (gpu-list-recs-n lst) (gpu-list-extras-n lst))
                     (gpu-list-version lst)
                     (walk (gpu-list-runs lst)))))
           (filter gpu-show-run? runs))))

  (define (inspect-list-count l) (vector-ref l 3))
  (define (inspect-list-labels l) (vector-ref l 2))
  (define (inspect-list-bytes l)
    (+ (* 32 (vector-ref l 3)) (* 4 (vector-ref l 4))))
  (define (inspect-list-row l) (vector-ref l 5))
  (define (inspect-list-runs l) (vector-ref l 6))
  ;; Returns the name of the fragment shader a run draws with: the variant
  ;; its records need.
  (define (inspect-run-shader run) (vector-ref gfx-fragments (list-ref run 4)))

  ;; Returns the compute runs waiting for the next frame, in the order they
  ;; will run, each as (shader-name w h), with w × h its cells.
  (define (inspect-computes)
    (map (lambda (run)
           (list (shader-name (gpu-call-shader (car run)))
                 (cadr run)
                 (caddr run)))
         (reverse *gpu-computes*)))
  (define (inspect-list-frame l) (vector-ref l 7))

  ;; Returns how many of l's runs show an image or a paint let go of since:
  ;; drawn again, the list leaves them out. Those still there show what they
  ;; hold now.
  (define (inspect-list-left-out l)
    (length (filter gpu-run-gone? (inspect-list-runs l))))

  ;;; -- the frames kept

  ;; The last frames, as many as the history was made for, by frame number:
  ;; a ring its caller holds. A frame keeps the root's records, in its
  ;; slot's buffers used again, and copies of the lists it shows; a list
  ;; unchanged since the frame before keeps the same copy. A frame is
  ;; flattened when it is asked for, and the last few flattened are kept.
  (define-record-type inspect-history
    (nongenerative schevana-inspect-history)
    (fields slots (mutable newest) (mutable flat)))

  (define (inspect-history-new n)
    (make-inspect-history (make-vector n #f) -1 '()))

  ;; A slot: #(records records-n extras extras-n runs labels row frame).
  (define (inspect-history-slot-empty)
    (vector (make-bytevector 0) 0 (make-bytevector 0) 0 '() '#() #f -1))

  ;; Keeps the frame drawn last, unless it is kept already.
  (define (inspect-history-add! h)
    (let ([frame (- *frame-ring-n* 1)] [slots (inspect-history-slots h)])
      (when (> frame (inspect-history-newest h))
        (let* ([i (modulo frame (vector-length slots))]
               [slot (or (vector-ref slots i) (inspect-history-slot-empty))]
               [newest (inspect-frames 1)])
          (define (fit! k n)
            (when (< (bytevector-length (vector-ref slot k)) n)
              (vector-set! slot k (make-bytevector (+ n (quotient n 4))))))
          (let-values ([(recs-n extras-n) (rec-last-sizes)])
            (fit! 0 recs-n)
            (fit! 2 extras-n)
            (rec-last-copy! (vector-ref slot 0) (vector-ref slot 2))
            (vector-set! slot 1 recs-n)
            (vector-set! slot 3 extras-n))
          (vector-set! slot 4 (inspect-runs-copied (rec-last-runs)))
          (vector-set! slot 5 (list->vector
                               (list-head (vector->list *rec-labels*)
                                          *rec-label-at*)))
          (vector-set! slot 6 (and (pair? newest) (car newest)))
          (vector-set! slot 7 frame)
          (vector-set! slots i slot)
          (inspect-history-newest-set! h frame)))))

  ;; Returns frame n's slot while the frame is kept, or #f; and whether it
  ;; is kept, without flattening it.
  (define (inspect-history-slot h n)
    (let* ([slots (inspect-history-slots h)]
           [slot (and (>= n 0)
                      (vector-ref slots (modulo n (vector-length slots))))])
      (and slot (= (vector-ref slot 7) n) slot)))

  ;; Returns frame n's list, flattened, while the frame is kept; or #f. Each
  ;; frame's list is its own, which asking for another frame doesn't touch.
  (define (inspect-history-ref h n)
    (let ([slot (inspect-history-slot h n)])
      (and slot
           (cond
             [(assv n (inspect-history-flat h)) => cdr]
             [else
              (let ([l (inspect-list-flat! (inspect-list-empty)
                                           (vector-ref slot 0)
                                           (vector-ref slot 1)
                                           (vector-ref slot 2)
                                           (vector-ref slot 3)
                                           (vector-ref slot 4)
                                           (vector-ref slot 5)
                                           (vector-ref slot 6) n)]
                    [flat (inspect-history-flat h)])
                (inspect-history-flat-set!
                 h (cons (cons n l)
                         (if (< (length flat) 3) flat (list-head flat 2))))
                l)]))))

  ;; Returns the lists that the kept frames up to frame upto showed, frame
  ;; by frame, without flattening any: (values n table), where n is how many
  ;; frames there are, and table holds each list's copies, a vector of n,
  ;; the oldest frame first, with #f where the list wasn't shown.
  (define (inspect-history-copies h upto)
    (let* ([len (vector-length (inspect-history-slots h))]
           [slots (filter values
                          (map (lambda (k)
                                 (inspect-history-slot h (+ upto (- len) 1 k)))
                               (iota len)))]
           [n (length slots)]
           [table (make-eq-hashtable)])
      (for-each
       (lambda (slot k)
         (let walk ([runs (vector-ref slot 4)])
           (for-each (lambda (run)
                       (when (gpu-show-run? run)
                         (let* ([copy (cadr run)]
                                [lst (inspect-list-original copy)]
                                [copies (or (hashtable-ref table lst #f)
                                            (let ([v (make-vector n #f)])
                                              (hashtable-set! table lst v)
                                              v))])
                           (vector-set! copies k copy)
                           (walk (gpu-list-runs copy)))))
                     runs)))
       slots (iota n))
      (values n table)))

  ;; Return how many frames are kept, and the bytes they hold now: each
  ;; slot's, and each list's copy once.
  (define (inspect-history-count h)
    (length (filter values (vector->list (inspect-history-slots h)))))

  (define (inspect-history-bytes h)
    (let ([seen (make-eq-hashtable)] [n 0])
      (define (lists! runs)
        (for-each (lambda (run)
                    (let ([copy (and (gpu-show-run? run) (cadr run))])
                      (when (and copy (not (hashtable-contains? seen copy)))
                        (hashtable-set! seen copy #t)
                        (set! n (+ n (gpu-list-recs-n copy)
                                   (gpu-list-extras-n copy)))
                        (lists! (gpu-list-runs copy)))))
                  runs))
      (vector-for-each
       (lambda (slot)
         (when slot
           (lists! (vector-ref slot 4))
           (set! n (+ n (bytevector-length (vector-ref slot 0))
                      (bytevector-length (vector-ref slot 2))))))
       (inspect-history-slots h))
      n))

  (define (inspect-word l i k)
    (bytevector-s32-native-ref (vector-ref l 0)
                               (fx* 4 (fx+ (fx* rec-row-words i) k))))

  (define (inspect-pixels n) (fl/ (fixnum->flonum n) 256.0))

  ;; Returns a record's clip row, if it has one: (x0 y0 x1 y1 radius rx0 ry0
  ;; rx1 ry1), where radius is that of the rounded box it lies in.
  (define (inspect-clip l i)
    (let ([row (fxsrl (fxand (inspect-word l i rec-row-head) #xffffffff) 8)])
      (and (not (fx= row 0))
           (map (lambda (k)
                  (inspect-pixels
                   (bytevector-s32-native-ref (vector-ref l 1)
                                              (fx* 4 (fx+ row k)))))
                (list clip-row-x0 clip-row-y0 clip-row-x1 clip-row-y1
                      clip-row-radius
                      clip-row-rx0 clip-row-ry0 clip-row-rx1 clip-row-ry1)))))

  ;; Returns the character of record i, a glyph.
  (define (inspect-glyph-char l i)
    (glyph-row-ref (inspect-word l i rec-glyph-number) glyph-row-character))

  (define (inspect-kind l i)
    (vector-ref inspect-kinds (fxand (inspect-word l i rec-row-head) 15)))

  (define (inspect-paint l i)
    (vector-ref inspect-paints
                (fxand (fxsrl (inspect-word l i rec-row-head) 4) 15)))

  ;; Returns what a record may touch, its clip left out: (x0 y0 x1 y1).
  (define (inspect-reach l i)
    (let ([word (lambda (k) (inspect-word l i k))]
          [px (lambda (k) (inspect-pixels (inspect-word l i k)))])
      (case (inspect-kind l i)
        [(glyph)
         (let* ([n (word rec-glyph-number)]
                [x (fx+ (word rec-glyph-pen-x)
                        (glyph-row-ref n glyph-row-left))]
                [y (fx- (word rec-glyph-pen-y)
                        (glyph-row-ref n glyph-row-top))])
           (map fixnum->flonum (list x y (fx+ x (glyph-row-ref n glyph-row-w))
                                     (fx+ y (glyph-row-ref n glyph-row-h)))))]
        [else
         (let ([x0 (px rec-row-x0)] [y0 (px rec-row-y0)]
               [x1 (px rec-row-x1)] [y1 (px rec-row-y1)])
           (case (inspect-kind l i)
             [(segment)
              (let ([d (fl/ (px rec-segment-width) 2.0)])
                (list (fl- (flmin x0 x1) d) (fl- (flmin y0 y1) d)
                      (fl+ (flmax x0 x1) d) (fl+ (flmax y0 y1) d)))]
             [(shadow)
              (let ([d (px rec-shadow-size)])
                (list (fl- x0 d) (fl- y0 d) (fl+ x1 d) (fl+ y1 d)))]
             [else (list x0 y0 x1 y1)]))])))

  ;; Returns a record, for reading: ((kind . box) (paint . solid) (color .
  ;; #xff112233) (reach x0 y0 x1 y1) (clip x0 y0 x1 y1 radius rx0 ry0 rx1
  ;; ry1)), with more by kind: a box's radius and line, a glyph's char.
  (define (inspect-record l i)
    (let ([kind (inspect-kind l i)] [paint (inspect-paint l i)])
      `((kind . ,kind)
        (paint . ,paint)
        ,@(if (eq? paint 'solid)
              `((color . ,(fxand (inspect-word l i rec-row-paint) #xffffffff)))
              '())
        (reach ,@(inspect-reach l i))
        (clip . ,(inspect-clip l i))
        ,@(case kind
            [(box)
             `((radius . ,(inspect-pixels (inspect-word l i rec-box-radius)))
               (line . ,(inspect-pixels (inspect-word l i rec-box-line))))]
            [(glyph) `((char . ,(integer->char (inspect-glyph-char l i))))]
            [else '()]))))

  ;; Returns the font glyph g was made in, and at what scale: (font . key),
  ;; with key num × 65536 + den as the font's pages are kept; or #f. A
  ;; glyph's number is in one font's pages, at its character.
  (define (inspect-glyph-font g)
    (let* ([c (glyph-row-ref g glyph-row-character)]
           [at (fx* 4 (fxand c 255))]
           [in? (lambda (page)
                  (and page
                       (exists (lambda (k)
                                 (fx= (fxvector-ref page (fx+ at k)) g))
                               '(0 1 2 3))))])
      (exists (lambda (f)
                (let ([sized (find (lambda (s)
                                     (in? (vector-ref (cdr s) (fxsrl c 8))))
                                   (font-sized f))])
                  (and sized (cons f (car sized)))))
              (vector->list (hashtable-values *font-specs*)))))

  ;; Returns how many spaces lie between glyph records i and j on a line:
  ;; how far the pen went past i's advance, in spaces of i's font, whose pen
  ;; moves only by advances; 0 when the font is gone.
  (define (inspect-glyph-spaces l i j)
    (let ([found (inspect-glyph-font (inspect-word l i rec-glyph-number))])
      (if (not found)
          0
          (let* ([f (car found)]
                 [scale (/ (fxsrl (cdr found) 16)
                           (* 256 (fxand (cdr found) 65535)))]
                 [advance (lambda (c)
                            (* scale (font-advance f (font-ready f) c)))]
                 [gap (- (inspect-word l j rec-glyph-pen-x)
                         (inspect-word l i rec-glyph-pen-x)
                         (advance (inspect-glyph-char l i)))])
            (exact (round (/ gap (advance 32))))))))

  ;; Returns the records first .. first + count - 1 as rows for reading, each
  ;; #(first count kind what). A run of glyphs on one baseline in one paint
  ;; is one row whose what is its text, with its spaces read back from where
  ;; its glyphs are. A gap of more than a few spaces, or one going back,
  ;; starts another text.
  (define (inspect-rows l first count)
    (let loop ([i first] [end (+ first count)] [acc '()])
      (cond
        [(>= i end) (reverse acc)]
        [(eq? (inspect-kind l i) 'glyph)
         (let run ([j (+ i 1)]
                   [chars (list (inspect-glyph-char l i))])
           (let ([spaces (and (< j end) (eq? (inspect-kind l j) 'glyph)
                              (= (inspect-word l j rec-glyph-pen-y)
                                 (inspect-word l i rec-glyph-pen-y))
                              (= (inspect-word l j rec-row-paint)
                                 (inspect-word l i rec-row-paint))
                              (inspect-glyph-spaces l (- j 1) j))])
             (if (and spaces (<= 0 spaces 4))
                 (run (+ j 1) (cons (inspect-glyph-char l j)
                                    (append (make-list spaces 32) chars)))
                 (loop j end
                       (cons (vector i (- j i) 'text
                                     (list->string
                                      (map integer->char (reverse chars))))
                             acc)))))]
        [else
         (loop (+ i 1) end
               (cons (vector i 1 (inspect-kind l i) (inspect-what l i))
                     acc))])))

  ;; Returns a record's size as text, "w × h".
  (define (inspect-what l i)
    (let ([r (inspect-reach l i)])
      (format "~a × ~a"
              (exact (round (- (caddr r) (car r))))
              (exact (round (- (cadddr r) (cadr r)))))))

  ;; Returns a record's paint: a solid one's color, as its word #xAARRGGBB;
  ;; another's kind, as inspect-paint names it.
  (define (inspect-record-paint l i)
    (let ([paint (inspect-paint l i)])
      (if (eq? paint 'solid)
          (fxand (inspect-word l i rec-row-paint) #xffffffff)
          paint)))

  ;; Returns a paint, as inspect-record-paint gives it, as text: a color as
  ;; #RRGGBB, with its alpha first only when it isn't opaque.
  (define (inspect-paint-text paint)
    (cond [(not (fixnum? paint)) (symbol->string paint)]
          [(= (fxsrl paint 24) 255) (format "#~6,'0x" (fxand paint #xffffff))]
          [else (format "#~8,'0x" paint)]))

  ;; Whether record i touches the device pixel x, y, as far as its reach and
  ;; clip tell.
  (define (inspect-covers? l i x y)
    (let ([in? (lambda (b)
                 (and (<= (car b) x) (< x (caddr b))
                      (<= (cadr b) y) (< y (cadddr b))))]
          [clip (inspect-clip l i)])
      (and (in? (inspect-reach l i)) (or (not clip) (in? clip)))))

  ;; Returns the records that may touch a device pixel, the one on top first.
  (define (inspect-records-at l x y)
    (let loop ([i 0] [acc '()])
      (cond [(= i (inspect-list-count l)) acc]
            [(inspect-covers? l i x y) (loop (+ i 1) (cons i acc))]
            [else (loop (+ i 1) acc)])))

  ;; Returns the label that holds at record i, or #f.
  (define (inspect-label-at l i)
    (let ([span (find (lambda (s) (< -1 (- i (cadr s)) (caddr s)))
                      (inspect-list-labels l))])
      (and span (car span))))

  ;;; -- the platform

  ;; Returns which platform this is, as an alist with its keys in reading
  ;; order: the system, the window, the drawing, the screen's reports, the
  ;; libraries, the predicates that hold, and the checkout's commit. A value
  ;; is #f where it isn't known here.
  (define (inspect-platform)
    (let ([fact platform-fact]
          [gpu (lambda (k) (let ([f (assq k *gpu-facts*)]) (and f (cdr f))))])
      (let-values ([(ft fc) (font-library-versions)])
        `((os . ,(platform-os))
          (system . ,(fact 'system))
          (kernel . ,(fact 'kernel))
          (cpu . ,(platform-cpu))
          (threads . ,(platform-cpu-count))
          (chez . ,(inspect-chez-version))
          (chez-machine . ,(machine-type))
          (windowing . ,(platform-windowing))
          (desktop . ,(fact 'desktop))
          (display . ,(core0-display))
          (scale . ,*canvas-ratio*)
          (gpu-api . ,(platform-gpu-api))
          (gpu-device . ,(fact 'gpu-device))
          (renderer . ,(gpu 'renderer))
          (present-mode . ,(gpu 'present-mode))
          (present-modes . ,(gpu 'present-modes))
          (reports . ,(fact 'reports))
          (sdl . ,(fact 'sdl))
          (freetype . ,ft)
          (fontconfig . ,fc)
          (predicates . ,(map car (filter cdr (platform-predicates))))
          (commit . ,(inspect-commit))))))

  ;; Returns the checkout's commit as (branch . short hash), from its .git
  ;; folder; #f with none, and a detached head's branch as #f.
  (define (inspect-commit)
    (let ([git (string-append *schevana-root* "/.git")]
          [line (lambda (path)
                  (and (file-exists? path)
                       (call-with-input-file path get-line)))])
      (and (file-directory? git)
           (let ([head (line (string-append git "/HEAD"))])
             (cond
               [(not (string? head)) #f]
               [(string-prefix? "ref: " head)
                (let* ([ref (substring head 5 (string-length head))]
                       [hash (or (line (string-append git "/" ref))
                                 (inspect-packed-ref git ref))])
                  (and (string? hash) (>= (string-length hash) 7)
                       (cons (path-last ref) (substring hash 0 7))))]
               [(>= (string-length head) 7) (cons #f (substring head 0 7))]
               [else #f])))))

  ;; Returns ref's hash in git's packed-refs, or #f.
  (define (inspect-packed-ref git ref)
    (let ([path (string-append git "/packed-refs")])
      (and (file-exists? path)
           (call-with-input-file path
             (lambda (in)
               (let loop ()
                 (let ([l (get-line in)])
                   (cond [(eof-object? l) #f]
                         [(string-suffix? (string-append " " ref) l)
                          (substring l 0 40)]
                         [else (loop)]))))))))

  ;; Returns Chez's version alone, as "10.0.0".
  (define (inspect-chez-version)
    (let ([v (scheme-version)])
      (if (string-prefix? "Chez Scheme Version " v)
          (substring v 20 (string-length v))
          v)))

  ;; Returns the display's size in pixels, as "3840 × 2160", from (w h
  ;; numerator denominator density): SDL gives the size in points.
  (define (inspect-display-pixels display)
    (format "~a × ~a" (exact (round (* (car display) (list-ref display 4))))
            (exact (round (* (cadr display) (list-ref display 4))))))

  ;; Returns the display's refresh rate in Hz, from (w h numerator
  ;; denominator density).
  (define (inspect-display-hz display)
    (and display (> (cadddr display) 0)
         (/ (round (* 100 (/ (caddr display) (cadddr display)))) 100.0)))

  ;; Returns this run as a row of docs/PLATFORMS.md's Runs: what ran, with
  ;; its result left for the person to fill in.
  (define (inspect-platform-row)
    (let* ([p (inspect-platform)]
           [of (lambda (k) (cdr (assq k p)))]
           [d (current-date)]
           [display (of 'display)]
           [device (of 'gpu-device)]
           [commit (of 'commit)])
      (format "| ~4,'0d-~2,'0d-~2,'0d | ~a | ~a | ~a | ~a | ~a | ~a | ~a | \
               a real window | |"
              (date-year d) (date-month d) (date-day d)
              (if commit
                  (format "`~a` (~a)" (cdr commit) (or (car commit) "detached"))
                  "not recorded")
              (string-join (filter values (list (of 'system) (of 'kernel)))
                           ", ")
              (string-join (filter values
                                   (list (of 'desktop)
                                         (symbol->string (of 'windowing))))
                           ", ")
              (if (and device (car device))
                  (format "~a, ~a ~a" (car device) (or (cadr device) "")
                          (or (caddr device) ""))
                  (format "~a, its driver not told by SDL ~a" (of 'gpu-api)
                          (of 'sdl)))
              (if display
                  (format "~a, ~a Hz" (inspect-display-pixels display)
                          (inspect-display-hz display))
                  "none")
              (of 'sdl)
              (of 'chez))))

  ;; Returns what draws: ((renderer . gpu) (window? . #t) (pixels w . h)
  ;; ...), as core0 says it (*gpu-facts*). The display is core0-display's,
  ;; or #f.
  (define (inspect-device)
    (let ([fact (lambda (k) (cdr (assq k *gpu-facts*)))])
      `((renderer . ,(fact 'renderer))
        (window? . ,(fact 'windowed?))
        (pixels ,*canvas-pw* . ,*canvas-ph*)
        (scale . ,*canvas-ratio*)
        (driver . ,(fact 'driver))
        (present-mode . ,(fact 'present-mode))
        (present-modes . ,(fact 'present-modes))
        (display . ,(core0-display)))))

  ;; Returns how many glyphs were made, and how full the atlas is, as a
  ;; fraction of 1.
  (define (inspect-glyphs)
    `((glyphs . ,(- *glyph-count* 1))
      (atlas-side . ,gpu-atlas-side)
      (atlas-used . ,(/ (+ *atlas-y* *atlas-row*) (inexact gpu-atlas-side)))))

  ;; Returns what is held on the GPU for frames, ((name kind . bytes) ...),
  ;; as core0 says it.
  (define (inspect-gpu-objects) (cdr (assq 'objects *gpu-facts*)))

  ;; Returns facts of core1's handles: the GPU bytes made so far, which the
  ;; collector counts, and how many the guardian let go of once nothing held
  ;; them.
  (define (inspect-gpu-held)
    `((bytes-made . ,*gpu-bytes-made*)
      (let-go . ,*gpu-held-gone*)))

  ;; Returns how core0 presents now: vsync, mailbox or immediate.
  (define (inspect-present-mode)
    (let ([f (assq 'present-mode *gpu-facts*)]) (and f (cdr f))))

  ;; Returns facts of the libraries reloaded in place ((schevana reload)):
  ;; how many it holds the text of, the environments it imports them into
  ;; again, and what the last reload evaluated again, in order.
  (define (inspect-reload) (reload-facts))

  ;; Returns what of the world still waits to load after the screen has
  ;; shown ((schevana core sources)): its entries, in order.
  (define (inspect-world-later) *world-later*)

  ;; Returns every file and folder that loads with the world, in order.
  (define (inspect-auto-loads) (auto-loads))

  ;;; -- the pacer

  ;; Returns core0's step: the window's facts as core0 last read them; who
  ;; the window is to the desktop (its app id, the least size it may be
  ;; dragged to in logical pixels, and the desktop's light or dark); the
  ;; jobs posted to core0 and the steps' events not yet taken; and the last
  ;; job that raised.
  (define (inspect-core0)
    (let ([state (core0-step-state)])
      `((sizes . ,(call-with-values core0-window-sizes list))
        (app-id . ,core0-app-id)
        (least . ,*screen-least*)
        (system-theme . ,(screen-system-theme))
        (scale . ,(core0-window-scale))
        (flags . ,(core0-flag-names (core0-flags)))
        (frame-ns . ,(core0-frame-ns))
        (jobs . ,(cdr (assq 'jobs state)))
        (events . ,(cdr (assq 'events state)))
        (failed . ,(cdr (assq 'failed state)))
        ;; the refresh's length said in place of the screen's (0 for none)
        (refresh-said . ,(cdr (assq 'refresh-said state))))))

  ;; Returns the pacer's state: its period and its grid's next tick (ns);
  ;; whether the screen paces it (frames come back by vsync), and when the
  ;; last tick's frame should show; the compositor's last latch seen, and
  ;; the lead before one (pacer-just-in-time); its margin; its counts (the
  ;; frames judged, those late by its own fault, and those late by the
  ;; compositor's); the trial holding its choices (the pacer lab's); of the
  ;; frames that made their latch lately, how long before it the one sent
  ;; closest to it was sent; the newest late run's first frame, and how many
  ;; runs came in a chain; once a frame the GPU made late has taught it, the
  ;; frames judged since the last such frame (#f for none); the first latch
  ;; the next frame may take; the compositor's depth; the latch the last
  ;; tick aimed at; and when the next tick may begin.
  (define (inspect-pacer)
    `((period . ,(pacer-period))
      (due . ,*pacer-due*)
      (shown . ,*pacer-shown?*)
      (frame . ,*pacer-frame-ns*)
      (latch . ,*pacer-latch*)
      (lead . ,*pacer-lead*)
      (margin . ,(pacer-margin (core0-frame-ns)))
      (counts . ,(fxvector->list *pacer-counts*))
      (made . ,*pacer-made*)
      (late . ,*pacer-late-run*)
      (chain . ,*pacer-late-chain*)
      (gpu-taught . ,*pacer-gpu-taught*)
      (floor . ,*pacer-floor*)
      (depth . ,*pacer-depth*)
      (aimed . ,*pacer-aimed*)
      (start . ,(pacer-start))))

  ;; Returns the second pacer's state ((schevana core pacer2)): whether the
  ;; loop asks it (the setting pacer); the refresh's length (ns); whether
  ;; the platform states the display's rate, or the length is core0's
  ;; guess until a report gives one; its rate, the turns so far, how often
  ;; core0 looks; and what the rule keeps between frames: t, the last
  ;; turn's aim and plan, the hold and the floor under a closer call (ns; 0
  ;; for none), the hold that a descent has proven, its probe's aim and the
  ;; lead a probe missed by (0 for none), when the last descent began,
  ;; whether the last raise was a look, the rows judged, and the begin that
  ;; the loop sleeps to (0 for none).
  (define (inspect-pacer2)
    (let ([d (core0-display)])
      `((on . ,(pacer2?))
        (period . ,(pacer2-period))
        (period-stated? . ,(and d (> (caddr d) 0) (> (cadddr d) 0) #t))
        (rate . ,(pacer-rate))
        (ticks . ,(pacer-ticks))
        (look . ,core0-look-ns)
        ,@(map (lambda (key) (cons key (pacer2-state key)))
               '(t aim plan hold floor proven probe probe-miss probed soft?
                 judged waited)))))

  ;; Returns the last sixteen rows as the second pacer reads them, the
  ;; oldest first: each one's turn's begin, the begin planned (0 for at
  ;; once), the refresh aimed at, the publish, core0's take (0 while still
  ;; in the slot), how long the screen held core0 for it, when its GPU work
  ;; was seen done (0 for not yet), its kind (out, shown, dropped, or back:
  ;; the window had no room), the refresh that showed it and that
  ;; refresh's length (0 for none reported), and which pacer planned it.
  ;; Times are in ns.
  (define (inspect-pacer-rows)
    (let* ([n *frame-ring-n*] [lo (max 0 (- n 16))])
      (map (lambda (k)
             (let* ([i (+ lo k)]
                    [seen (lambda (k) (or (inspect-frame-report i k) 0))])
               `((b . ,(inspect-frame-ref i 8))
                 (plan . ,(inspect-frame-ref i 14))
                 (aim . ,(inspect-frame-ref i 13))
                 (p . ,(inspect-frame-ref i 10))
                 (taken . ,(seen 7))
                 (held . ,(- (seen 9) (seen 8)))
                 (done . ,(seen 6))
                 (kind . ,(if (eqv? (inspect-frame-ref i 5) 2)
                              'back
                              (case (seen 1)
                                [(1) 'shown]
                                [(2) 'dropped]
                                [else 'out])))
                 (shown . ,(seen 3))
                 (refresh . ,(seen 4))
                 (pacer . ,(inspect-frame-ref i 15)))))
           (iota (- n lo)))))

  ;;; -- what shaders share

  ;; Returns the constants a shader can name, by name: ((name . value) ...).
  (define (inspect-shader-constants)
    (let-values ([(names numbers) (hashtable-entries *shader-constants*)])
      (sort (lambda (a b)
              (string<? (symbol->string (car a)) (symbol->string (car b))))
            (map cons (vector->list names) (vector->list numbers)))))

  ;; Returns the sets of helpers, by name: ((set function ...) ...).
  (define (inspect-shader-helpers)
    (let-values ([(names sets) (hashtable-entries *shader-helpers*)])
      (sort (lambda (a b)
              (string<? (symbol->string (car a)) (symbol->string (car b))))
            (map (lambda (name forms)
                   (cons name (map caadr forms)))
                 (vector->list names) (vector->list sets)))))

  ;; Returns each layout's fields, by name: ((field reader . offset) ...).
  (define (inspect-shader-fields)
    (let-values ([(names rows) (hashtable-entries *shader-fields*)])
      (sort (lambda (a b)
              (string<? (symbol->string (car a)) (symbol->string (car b))))
            (map cons (vector->list names) (vector->list rows)))))

  ;;; -- the preview

  ;; Makes an image w × h for inspect-preview!, reads its size, and lets go
  ;; of it.
  (define (inspect-preview-image w h) (gpu-image-make-target w h))
  (define (inspect-preview-w image) (gpu-image-w image))
  (define (inspect-preview-h image) (gpu-image-h image))
  (define (inspect-preview-free! image) (gpu-image-release! image))

  ;; Returns the bytes a preview image holds on the GPU, its levels with it.
  (define (inspect-preview-bytes image)
    (let loop ([level 0] [w (gpu-image-w image)] [h (gpu-image-h image)] [n 0])
      (if (= level (gpu-image-levels image))
          n
          (loop (+ level 1) (max 1 (quotient w 2)) (max 1 (quotient h 2))
                (+ n (* 4 w h))))))

  ;; The frame that inspect-preview! draws: a cache, which only saves the
  ;; buffers.
  (define-made inspect-live (inspect-list-empty))

  ;; Draws a kept list's first count records on image ahead of the next
  ;; frame, except those left out, as inspect-preview! takes them.
  (define inspect-preview-list!
    (case-lambda
      [(image l count) (inspect-preview-list! image l count #f)]
      [(image l count left-out)
       (let ([runs (inspect-runs-upto (inspect-list-runs l) count image)])
         (rec-past! image (vector-ref l 0) (* 32 (inspect-list-count l))
                    (vector-ref l 1) (* 4 (vector-ref l 4))
                    (if left-out
                        (inspect-runs-without
                         runs (left-out (inspect-list-labels l)))
                        runs)))]))

  ;; Returns the runs, (mode image first count variant) ..., as far as
  ;; record n, except those that show image, which is being drawn on.
  (define (inspect-runs-upto runs n image)
    (let loop ([runs runs] [acc '()])
      (if (or (null? runs) (>= (caddr (car runs)) n))
          (reverse acc)
          (let ([run (car runs)])
            (loop (cdr runs)
                  (if (eq? (cadr run) image)
                      acc
                      (cons (list (car run) (cadr run) (caddr run)
                                  (min (cadddr run) (- n (caddr run)))
                                  (list-ref run 4))
                            acc)))))))

  ;; Returns the runs without the records in ranges, ((first . count) ...) in
  ;; order: a run with records left out in its middle is cut in two.
  (define (inspect-runs-without runs ranges)
    (if (null? ranges)
        runs
        (apply append
               (map (lambda (run) (inspect-run-pieces run ranges)) runs))))

  ;; With the next frame, draws its first count records on image, except
  ;; those that (left-out spans) gives as ((first . count) ...) in order,
  ;; where spans are the frame's labels' spans, as inspect-list-labels has
  ;; them. Without left-out, none are left out. The frame is read,
  ;; flattened, into a list kept for it.
  (define inspect-preview!
    (case-lambda
      [(image count) (inspect-preview! image count #f)]
      [(image count left-out)
       (rec-preview! image
                     (lambda ()
                       (let* ([l (inspect-list-read! inspect-live)]
                              [runs (inspect-runs-upto (inspect-list-runs l)
                                                       count image)])
                         (list (vector-ref l 0) (* 32 (inspect-list-count l))
                               (vector-ref l 1) (* 4 (vector-ref l 4))
                               (if left-out
                                   (inspect-runs-without
                                    runs (left-out (inspect-list-labels l)))
                                   runs)))))]))

  ;; Returns what is left of run without the records in ranges, as runs.
  (define (inspect-run-pieces run ranges)
    (let ([end (+ (caddr run) (cadddr run))]
          [piece (lambda (from to)
                   (list (car run) (cadr run) from (- to from)
                         (list-ref run 4)))])
      (let loop ([at (caddr run)] [ranges ranges])
        (if (or (>= at end) (null? ranges))
            (if (< at end) (list (piece at end)) '())
            (let* ([from (caar ranges)] [to (+ from (cdar ranges))])
              (cond [(<= to at) (loop at (cdr ranges))]
                    [(<= from at) (loop to (cdr ranges))]
                    [(>= from end) (list (piece at end))]
                    [else (cons (piece at from) (loop to (cdr ranges)))]))))))

  ;;; -- a list repainted, and what a span of it costs

  ;; Fills into, a list as inspect-list-empty makes, with l, every record's
  ;; paint made solid: record i's is (word-of i), a color's word. What each
  ;; record covers stays the same, in colors of the caller's choosing (by
  ;; who drew it, or its kind). Its runs are those that solid records need,
  ;; blended by mode, a run's (0 over, 3 adding); its extras are l's, and
  ;; its records go in into's own buffer when that is big enough. Returns
  ;; into.
  (define (inspect-list-paint! into l word-of mode)
    (let ([n (inspect-list-count l)])
      (when (< (bytevector-length (vector-ref into 0)) (* 32 n))
        (vector-set! into 0 (make-immobile-bytevector (+ (* 32 n) (* 8 n)))))
      (let* ([bytes (vector-ref into 0)]
             [at (lambda (i k) (fx* 4 (fx+ (fx* rec-row-words i) k)))]
             [paint! (lambda (i w)
                       (if (fx< w 0)
                           (bytevector-s32-native-set! bytes
                                                       (at i rec-row-paint)
                                                       w)
                           (bytevector-u32-native-set! bytes
                                                       (at i rec-row-paint)
                                                       w)))])
        (bytevector-copy! (vector-ref l 0) 0 bytes 0 (* 32 n))
        (do ([i 0 (fx+ i 1)]) ((fx= i n))
          (let ([head (bytevector-s32-native-ref bytes (at i rec-row-head))])
            (bytevector-s32-native-set! bytes (at i rec-row-head)
                                        (fxand head (fxnot #xf0)))
            (paint! i (word-of i))))
        (vector-set! into 1 (vector-ref l 1))
        (vector-set! into 2 (inspect-list-labels l))
        (vector-set! into 3 n)
        (vector-set! into 4 (vector-ref l 4))
        (vector-set! into 5 (inspect-list-row l))
        (vector-set! into 7 (inspect-list-frame l))
        ;; a run for each stretch of records that need the same variant
        (vector-set!
         into 6
         (let loop ([i 0] [first 0] [variant #f] [acc '()])
           (cond
             [(fx= i n)
              (reverse (if (fx> n first)
                           (cons (list mode #f first (fx- n first) variant) acc)
                           acc))]
             [else
              (let ([v (rec-variant
                        (bytevector-s32-native-ref bytes (at i rec-row-head)))])
                (if (or (not variant) (fx= v variant))
                    (loop (fx+ i 1) first v acc)
                    (loop (fx+ i 1) i v
                          (cons (list mode #f first (fx- i first) variant)
                                acc))))])))
        into)))

  ;; Returns how many device pixels record i may touch: its reach within its
  ;; clip and the screen, which is what the GPU shades for it.
  (define (inspect-record-pixels l i)
    (let* ([r (inspect-reach l i)]
           [c (or (inspect-clip l i) (list 0 0 *canvas-pw* *canvas-ph*))]
           [w (- (min (caddr r) (caddr c) *canvas-pw*) (max (car r) (car c) 0))]
           [h (- (min (cadddr r) (cadddr c) *canvas-ph*)
                 (max (cadr r) (cadr c) 0))])
      (if (and (> w 0) (> h 0)) (* w h) 0)))

  ;; Returns what count records of l from first cost, as (values pixels
  ;; runs): the device pixels they may touch, a pixel counted once for each
  ;; record over it, and how many runs start among them, each a draw call.
  (define (inspect-span-cost l first count)
    (values
     (let loop ([i first] [px 0.0])
       (if (>= i (+ first count))
           (exact (round px))
           (loop (+ i 1) (+ px (inspect-record-pixels l i)))))
     (length (filter (lambda (run) (< -1 (- (caddr run) first) count))
                     (inspect-list-runs l)))))

  ;; Whether record i of l says what record j of b does. What a record says
  ;; of where things are in the list's extras (its clip and its rows) moves
  ;; when something before it changes, so it isn't compared. It allocates
  ;; nothing: the Pipeline asks it of every record of a frame.
  (define (inspect-record-same? l i b j)
    (let ([head (inspect-word l i rec-row-head)])
      (and (fx= (fxand head #xff) (fxand (inspect-word b j rec-row-head) #xff))
           (let loop ([k 1])
             (or (fx= k rec-row-words)
                 (and (or (and (fx= k rec-row-paint)
                               (fx= (fxand (fxsrl head 4) 15) 1))
                          (and (fx= k rec-polygon-points)
                               (fx= (fxand head 15) 2))
                          (fx= (inspect-word l i k) (inspect-word b j k)))
                      (loop (fx+ k 1))))))))

  ;; Returns how many of count records of l from first differ from bcount
  ;; records of b from bfirst, compared one by one; a record past b's last
  ;; counts as changed.
  (define (inspect-span-changed l first count b bfirst bcount)
    (let loop ([k 0] [n 0])
      (cond [(= k count) n]
            [(or (>= k bcount)
                 (not (inspect-record-same? l (+ first k) b (+ bfirst k))))
             (loop (+ k 1) (+ n 1))]
            [else (loop (+ k 1) n)])))

  ;;; -- inside a record

  ;; Returns the run that draws record i of l, (mode image first count
  ;; variant), or #f.
  (define (inspect-record-run l i)
    (find (lambda (run) (< -1 (- i (caddr run)) (cadddr run)))
          (inspect-list-runs l)))

  ;; Returns the shader a run's records are drawn with: a paint's own, or
  ;; the variant of the fragment shader they need.
  (define (inspect-run-fragment run)
    (let ([x (cadr run)])
      (if (gpu-call? x)
          (gpu-call-shader x)
          (world-value (inspect-run-shader run)))))

  ;; Returns the helper groups a shader's source uses, wherever it uses
  ;; them, in order.
  (define (inspect-helpers-used form)
    (let walk ([form form] [acc '()])
      (cond [(not (pair? form)) acc]
            [(and (eq? (car form) 'use-shader-helpers) (pair? (cdr form)))
             (if (memq (cadr form) acc) acc (append acc (list (cadr form))))]
            [else (walk (cdr form) (walk (car form) acc))])))

  ;; Returns a shader's source, pretty-printed, followed by the helpers it
  ;; uses written out under their names, as a list of lines.
  (define (inspect-shader-lines shader)
    (let ([text (with-output-to-string
                  (lambda ()
                    (parameterize ([print-gensym #f])
                      (for-each pretty-print (shader-source shader))
                      (for-each
                       (lambda (name)
                         (printf ";; ~a\n" name)
                         (for-each pretty-print
                                   (hashtable-ref *shader-helpers* name '())))
                       (inspect-helpers-used (shader-source shader))))))])
      (let loop ([chars (string->list text)] [line '()] [acc '()])
        (cond [(null? chars)
               (reverse (if (null? line) acc (cons (list->string (reverse line))
                                                   acc)))]
              [(char=? (car chars) #\newline)
               (loop (cdr chars) '() (cons (list->string (reverse line)) acc))]
              [else (loop (cdr chars) (cons (car chars) line) acc)]))))

  ;; Returns the glyphs' atlas as an image to draw: one channel, coverage,
  ;; as the glyph records read it. It is core0's own, and never let go of
  ;; here.
  (define (inspect-atlas-image) (gpu-atlas-image)))
