;;; kits/inspect.ss — the rendering pipeline as plain data, for the Pipeline
;;; app, a REPL or a test. It only reads.
;;;
;;; A frame is recorded in the buffers it would be read from, so a list is
;;; read from a copy of the last frame's: (inspect-list), about 2 µs for 150
;;; KB. What's read of it comes in device pixels, the screen's.

;; What src/gfx.ss's record kinds and paints are, by number; a test holds
;; the two together.
(define inspect-kinds '#(box segment polygon glyph shadow))
(define inspect-paints '#(solid gradient stipple image shader))

;;; ---- frames

;; The newest n frames at most, newest first: each (us records extras runs
;; glyphs shown?).
(define (inspect-frames n)
  (let ([have (min n *frame-ring-n* frame-ring-rows)])
    (map (lambda (i)
           (let ([at (* frame-ring-words
                        (modulo (- *frame-ring-n* i 1) frame-ring-rows))]
                 [ring *frame-ring*])
             (list (fxvector-ref ring at)
                   (fxvector-ref ring (+ at 1))
                   (fxvector-ref ring (+ at 2))
                   (fxvector-ref ring (+ at 3))
                   (fxvector-ref ring (+ at 4))
                   (= 1 (fxvector-ref ring (+ at 5))))))
         (iota have))))

;;; ---- lists

;; A copy of the last frame's list: #(records extras labels count words row
;; runs frame segments), labels ((label first-record count) ...) in draw
;; order, row the frame's in inspect-frames, runs its runs, frame its
;; number, segments where its records came from (inspect-record-list). The
;; lists it shows are in it, flattened: each one's records where its runs
;; draw them, moved to where it's shown and cut to its clip, so it draws the
;; same pixels from one list, and its records come in the order they're
;; drawn.
(define (inspect-list) (inspect-list-read! (inspect-list-empty)))

(define (inspect-list-empty)
  (vector (make-bytevector 0) (make-bytevector 0) '() 0 0 #f '() -1 '()))

;; l holds the last list recorded from now on, the frame's, in its own
;; buffers when they're big enough: they stay where they are, and a
;; collection needn't copy them.
(define (inspect-list-read! l)
  (let ([newest (inspect-frames 1)])
    (inspect-list-flat! l *rec-bytes* (* 32 (rec-count)) *rec-extras*
                        (* 4 *rec-extra-at*) (rec-runs)
                        (list->vector (list-head (vector->list *rec-labels*)
                                                 *rec-label-at*))
                        (and (pair? newest) (car newest))
                        (- *frame-ring-n* 1))))

;; l as a root's records and extras, bytes long, its runs and labels,
;; flattened, its row and frame number those given.
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

;; The list record i of l came from, and its place there: (values list j),
;; list #f for the root's.
(define (inspect-record-list l i)
  (let ([s (find (lambda (s) (< -1 (- i (vector-ref s 1)) (vector-ref s 2)))
                 (vector-ref l 8))])
    (if s
        (values (vector-ref s 0) (+ (vector-ref s 3) (- i (vector-ref s 1))))
        (values #f i))))

;; The lists records first to first + count of l came from, each once, in
;; order: a drawer's.
(define (inspect-span-lists l first count)
  (fold-left (lambda (acc s)
               (let ([lst (vector-ref s 0)])
                 (if (and lst
                          (< -1 (- (vector-ref s 1) first) count)
                          (not (memq lst acc)))
                     (append acc (list lst))
                     acc)))
             '() (vector-ref l 8)))

;; What a list is: ((owner . name) (version . n) (records . n) (bytes . n)
;; (recorded . ns) (took . ns)), recorded on now-ns's clock.
(define (inspect-list-facts lst)
  `((owner . ,(inspect-list-owner lst))
    (version . ,(gpu-list-version lst))
    (records . ,(fxquotient (gpu-list-recs-n lst) 32))
    (bytes . ,(+ (gpu-list-recs-n lst) (gpu-list-extras-n lst)))
    (recorded . ,(gpu-list-recorded lst))
    (took . ,(gpu-list-took lst))))

;; Whose a list is, in words, and which of its owner's: a window's, its
;; frame and all, window, or its content, content; else list. A kept copy's
;; are its list's then.
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

;; The lists l's records came from, each once, in order.
(define (inspect-list-lists l)
  (inspect-span-lists l 0 (inspect-list-count l)))

;;; ---- lists kept: one copy a version

;; Caches, which only save copying: each list's newest copy, and each
;; copy's owner, said when it's made (inspect-list-whose); and each copy's
;; list and basis, (list . basis). Ephemeron tables, not weak ones: a copy
;; is often its own basis, and a weak table's value keeps its key.
(define inspect-copies (make-ephemeron-eq-hashtable))
(define inspect-owners (make-ephemeron-eq-hashtable))
(define inspect-sources (make-ephemeron-eq-hashtable))

;; The list a copy is of; a list that isn't one, itself.
(define (inspect-list-original copy)
  (let ([s (hashtable-ref inspect-sources copy #f)]) (if s (car s) copy)))

;; The first of the copies in a row that hold the very same records as
;; copy: a list recorded again the same, its basis is the copy before's.
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

;; lst as it is now, to keep: a copy of its records and extras, its runs
;; showing copies of the lists it shows, the same copy as the last time
;; while it and they haven't changed.
(define (inspect-list-copy lst)
  (let ([runs (inspect-runs-copied (gpu-list-runs lst))]
        [old (hashtable-ref inspect-copies lst #f)])
    (if (and old
             (= (gpu-list-version old) (gpu-list-version lst))
             (for-all eq? runs (gpu-list-runs old)))
        old
        (let ([copy (make-gpu-list
                     #f
                     (inspect-bytes-copy (gpu-list-recs lst)
                                         (gpu-list-recs-n lst))
                     (gpu-list-recs-n lst)
                     (inspect-bytes-copy (gpu-list-extras lst)
                                         (gpu-list-extras-n lst))
                     (gpu-list-extras-n lst)
                     runs (gpu-list-labels lst) (gpu-list-version lst)
                     (gpu-list-recorded lst) (gpu-list-took lst))])
          (hashtable-set! inspect-copies lst copy)
          (hashtable-set! inspect-owners copy (inspect-list-whose lst))
          (hashtable-set! inspect-sources copy
                          (cons lst (if (and old (inspect-copy-same? copy old))
                                        (inspect-list-basis old)
                                        copy)))
          copy))))

;; runs, those that show a list showing its copy instead: the same run
;; objects otherwise, and a show run the same as the last time while its
;; copy is.
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

;; Each show run's copy that shows a copy: a cache too.
(define inspect-shows (make-ephemeron-eq-hashtable))

(define (inspect-bytes-copy bv n)
  (let ([c (make-bytevector n)])
    (bytevector-copy! bv 0 c 0 n)
    c))

;; The bytes the flattened list takes: (records . extras), each list as
;; often as it's shown, and a clip row for each show.
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

;; Writes the list (recs, extras, its runs and labels, as the recorder keeps
;; them) and those it shows into to and to-extras, flattened. =>
;; (labels count words runs segments): labels a list ((first . label) ...)
;; in order, count the records, words the extras' words, segments where
;; each stretch of records came from, #(list first count its-first), list
;; #f for the root's.
(define (inspect-flatten! to to-extras recs extras extras-n runs labels)
  (let ([count 0] [words 1] [out-runs '()] [out-labels '()]
        [segments '()])
    (define (word bv i) (bytevector-s32-native-ref bv (fx* 4 i)))
    (define (word! bv i v) (bytevector-s32-native-set! bv (fx* 4 i) v))
    ;; a label the same as the one before goes on
    (define (label! text)
      (unless (and (pair? out-labels) (equal? (cdar out-labels) text))
        (set! out-labels (cons (cons count text) out-labels))))
    ;; a list's extras, bytes long, after those so far, its rows moved by
    ;; (dx, dy) in 256ths, a clip's cut to box; then its records, by
    ;; recs-of, handed how to find and move its rows
    (define (extras! from bytes dx dy box recs-of)
      (let ([base (fx- words 1)] [seen (make-eqv-hashtable)]
            [n (fxquotient bytes 4)])
        (bytevector-copy! from 4 to-extras (fx* 4 words) (fx* 4 (fx- n 1)))
        (set! words (fx+ words (fx- n 1)))
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
    ;; a list's records first to first + n, at the end of to, moved by
    ;; (dx, dy) in 256ths, their rows by at
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
    ;; a list at (ox, oy) device pixels, inside box or none, its runs in
    ;; order; its labels where they fall among them, none being outer, the
    ;; label of what shows it
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
                                           (map (lambda (v d) (fx* 256 (+ v d)))
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
                         (flatten! lst (gpu-list-recs lst) (gpu-list-extras lst)
                                   (gpu-list-extras-n lst) (gpu-list-runs lst)
                                   (gpu-list-labels lst)
                                   (+ ox (caddr run)) (+ oy (cadddr run))
                                   inner shown)
                         (label! shown)))
                     (let ([first (caddr run)] [n (cadddr run)])
                       (let split ([first first] [n n])
                         ;; a label inside the run starts where it falls
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

;; The labels' spans of the first count records, from ((first . label) ...)
;; in order: a label holds until the next, and a span of none, or of no
;; label, is left out.
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

;; The lists the last frame shows, as a tree: ((x y records bytes version
;; children) ...) in draw order, (x, y) in device pixels from what shows it,
;; version how many times it's been recorded.
(define (inspect-list-tree)
  (let walk ([runs (rec-runs)])
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
;; The name of the fragment shader a run draws with: the variant its records
;; need.
(define (inspect-run-shader run) (vector-ref gfx-fragments (list-ref run 4)))

;; The compute runs waiting for the next frame, in the order they'll run:
;; (shader-name w h) each, w × h its cells.
(define (inspect-computes)
  (map (lambda (run)
         (list (shader-name (gpu-call-shader (car run)))
               (cadr run)
               (caddr run)))
       (reverse *gpu-computes*)))
(define (inspect-list-frame l) (vector-ref l 7))

;; How many of its runs show an image or a paint let go of since: drawn again,
;; the list leaves them out. Those still there show what they hold now.
(define (inspect-list-left-out l)
  (length (filter gpu-run-gone? (inspect-list-runs l))))

;;; ---- the frames kept

;; The last frames, as many as it was made for, by frame number: a ring its
;; caller holds. A frame keeps the root's records, in its slot's buffers used
;; again, and copies of the lists it shows, a list unchanged since the
;; frame before the same copy; flattened as it's asked for, the last few
;; flattened kept.
(define-record-type inspect-history
  (fields slots (mutable newest) (mutable flat)))

(define (inspect-history-new n)
  (make-inspect-history (make-vector n #f) -1 '()))

;; A slot: #(records records-n extras extras-n runs labels row frame).
(define (inspect-history-slot-empty)
  (vector (make-bytevector 0) 0 (make-bytevector 0) 0 '() '#() #f -1))

;; Keeps the frame drawn last, unless it's kept already.
(define (inspect-history-add! h)
  (let ([frame (- *frame-ring-n* 1)] [slots (inspect-history-slots h)])
    (when (> frame (inspect-history-newest h))
      (let* ([i (modulo frame (vector-length slots))]
             [slot (or (vector-ref slots i) (inspect-history-slot-empty))]
             [recs-n (* 32 (rec-count))]
             [extras-n (* 4 *rec-extra-at*)]
             [newest (inspect-frames 1)])
        (define (fit! k n)
          (when (< (bytevector-length (vector-ref slot k)) n)
            (vector-set! slot k (make-bytevector (+ n (quotient n 4))))))
        (fit! 0 recs-n)
        (fit! 2 extras-n)
        (bytevector-copy! *rec-bytes* 0 (vector-ref slot 0) 0 recs-n)
        (bytevector-copy! *rec-extras* 0 (vector-ref slot 2) 0 extras-n)
        (vector-set! slot 1 recs-n)
        (vector-set! slot 3 extras-n)
        (vector-set! slot 4 (inspect-runs-copied (rec-runs)))
        (vector-set! slot 5 (list->vector
                             (list-head (vector->list *rec-labels*)
                                        *rec-label-at*)))
        (vector-set! slot 6 (and (pair? newest) (car newest)))
        (vector-set! slot 7 frame)
        (vector-set! slots i slot)
        (inspect-history-newest-set! h frame)))))

;; Frame n's slot while it's kept, or #f; whether it is, without flattening
;; it.
(define (inspect-history-slot h n)
  (let* ([slots (inspect-history-slots h)]
         [slot (and (>= n 0)
                    (vector-ref slots (modulo n (vector-length slots))))])
    (and slot (= (vector-ref slot 7) n) slot)))

(define (inspect-history-kept? h n) (and (inspect-history-slot h n) #t))

;; Frame n's list, flattened, while it's kept; or #f. A list asked for is
;; one of its own, which a later ask doesn't touch.
(define (inspect-history-ref h n)
  (let ([slot (inspect-history-slot h n)])
    (and slot
         (cond
           [(assv n (inspect-history-flat h)) => cdr]
           [else
            (let ([l (inspect-list-flat! (inspect-list-empty)
                                         (vector-ref slot 0) (vector-ref slot 1)
                                         (vector-ref slot 2) (vector-ref slot 3)
                                         (vector-ref slot 4) (vector-ref slot 5)
                                         (vector-ref slot 6) n)]
                  [flat (inspect-history-flat h)])
              (inspect-history-flat-set!
               h (cons (cons n l)
                       (if (< (length flat) 3) flat (list-head flat 2))))
              l)]))))

;; The lists the frames kept up to frame upto showed, frame by frame,
;; none of them flattened: (values n table), n how many frames, and table
;; each list's copies, a vector of n, the oldest frame first, #f where it
;; wasn't shown.
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

;; How many frames are kept, and the bytes they hold now: each slot's, and
;; each list's copy once.
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

;; A record's clip row, if it has one: (x0 y0 x1 y1 radius rx0 ry0 rx1 ry1), the
;; radius being that of the rounded box it lies in.
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

;; The character of record i, a glyph's.
(define (inspect-glyph-char l i)
  (glyph-row-ref (inspect-word l i rec-glyph-number) glyph-row-character))

(define (inspect-kind l i)
  (vector-ref inspect-kinds (fxand (inspect-word l i rec-row-head) 15)))

(define (inspect-paint l i)
  (vector-ref inspect-paints
              (fxand (fxsrl (inspect-word l i rec-row-head) 4) 15)))

;; (x0 y0 x1 y1): what a record may touch, its clip left out.
(define (inspect-reach l i)
  (let ([word (lambda (k) (inspect-word l i k))]
        [px (lambda (k) (inspect-pixels (inspect-word l i k)))])
    (case (inspect-kind l i)
      [(glyph)
       (let* ([n (word rec-glyph-number)]
              [x (fx+ (word rec-glyph-pen-x) (glyph-row-ref n glyph-row-left))]
              [y (fx- (word rec-glyph-pen-y) (glyph-row-ref n glyph-row-top))])
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

;; A record, for reading: ((kind . box) (paint . solid) (color . #xff112233)
;; (reach x0 y0 x1 y1) (clip x0 y0 x1 y1 radius)), with more by kind: a box's
;; radius and line, a glyph's char.
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

;; The font glyph g was made in, and at what scale: (font . key), key num ×
;; 65536 + den as its pages are kept; or #f. A glyph's number is in one
;; font's pages, at its character.
(define (inspect-glyph-font g)
  (let* ([c (glyph-row-ref g glyph-row-character)]
         [at (fx* 4 (fxand c 255))]
         [in? (lambda (page)
                (and page
                     (exists (lambda (k) (fx= (fxvector-ref page (fx+ at k)) g))
                             '(0 1 2 3))))])
    (exists (lambda (f)
              (let ([sized (find (lambda (s)
                                   (in? (vector-ref (cdr s) (fxsrl c 8))))
                                 (font-sized f))])
                (and sized (cons f (car sized)))))
            (vector->list (hashtable-values *font-specs*)))))

;; How many spaces lie between glyph records i and j on a line: how far the
;; pen went past i's advance, in spaces of i's font, whose pen moves only by
;; advances; 0 when its font is gone.
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

;; The records first .. first + count - 1 as rows for reading: #(first count
;; kind what), a run of glyphs on one baseline in one paint being one row
;; whose what is its text, its spaces read back from where its glyphs are.
;; A gap of more than a few spaces, or back, is another text's.
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
             (cons (vector i 1 (inspect-kind l i) (inspect-what l i)) acc))])))

;; A record's size, in words.
(define (inspect-what l i)
  (let ([r (inspect-reach l i)])
    (format "~a × ~a"
            (exact (round (- (caddr r) (car r))))
            (exact (round (- (cadddr r) (cadr r)))))))

;; A record's paint: a solid one's color, its word #xAARRGGBB; another's
;; kind, as inspect-paint names it.
(define (inspect-record-paint l i)
  (let ([paint (inspect-paint l i)])
    (if (eq? paint 'solid)
        (fxand (inspect-word l i rec-row-paint) #xffffffff)
        paint)))

;; A paint, as inspect-record-paint gives it, in words: a color #RRGGBB,
;; its alpha first only when it isn't opaque.
(define (inspect-paint-text paint)
  (cond [(not (fixnum? paint)) (symbol->string paint)]
        [(= (fxsrl paint 24) 255) (format "#~6,'0x" (fxand paint #xffffff))]
        [else (format "#~8,'0x" paint)]))

;; Does record i touch the device pixel x, y, as far as its reach and clip
;; tell?
(define (inspect-covers? l i x y)
  (let ([in? (lambda (b)
               (and (<= (car b) x) (< x (caddr b))
                    (<= (cadr b) y) (< y (cadddr b))))]
        [clip (inspect-clip l i)])
    (and (in? (inspect-reach l i)) (or (not clip) (in? clip)))))

;; The records that may touch a device pixel, the one on top first.
(define (inspect-records-at l x y)
  (let loop ([i 0] [acc '()])
    (cond [(= i (inspect-list-count l)) acc]
          [(inspect-covers? l i x y) (loop (+ i 1) (cons i acc))]
          [else (loop (+ i 1) acc)])))

;; The label that holds at record i, or #f.
(define (inspect-label-at l i)
  (let ([span (find (lambda (s) (< -1 (- i (cadr s)) (caddr s)))
                    (inspect-list-labels l))])
    (and span (car span))))

;;; ---- the screen

;; What draws: ((renderer . gpu) (window? . #t) (pixels w . h) ...), as
;; core0 says it (*gpu-facts*). The display is host-display's, or #f.
(define (inspect-device)
  (let ([fact (lambda (k) (cdr (assq k *gpu-facts*)))])
    `((renderer . ,(fact 'renderer))
      (window? . ,(fact 'windowed?))
      (pixels ,*canvas-pw* . ,*canvas-ph*)
      (scale . ,*canvas-ratio*)
      (driver . ,(fact 'driver))
      (present-mode . ,(fact 'present-mode))
      (present-modes . ,(fact 'present-modes))
      (display . ,(host-display)))))

;; The glyphs made, and how full the atlas is, of 1.
(define (inspect-glyphs)
  `((glyphs . ,(- *glyph-count* 1))
    (atlas-side . ,gpu-atlas-side)
    (atlas-used . ,(/ (+ *atlas-y* *atlas-row*) (inexact gpu-atlas-side)))))

;; What's held on the GPU for frames: ((name kind . bytes) ...), as core0
;; says it.
(define (inspect-gpu-objects) (cdr (assq 'objects *gpu-facts*)))

;;; ---- the pacer

;; What times the frames: its period and when the next tick is due (ns), and
;; how often the screen has re-timed it and frames were left out for it.
(define (inspect-pacer)
  `((period . ,(pacer-period))
    (margin . ,(theme 'pacer-margin))
    (due . ,*pacer-due*)
    (retimed . ,*pacer-retimed*)
    (skipped . ,*pacer-skipped*)))

;;; ---- what shaders share

;; The constants a shader can name, by name: ((name . value) ...).
(define (inspect-shader-constants)
  (let-values ([(names numbers) (hashtable-entries *shader-constants*)])
    (sort (lambda (a b)
            (string<? (symbol->string (car a)) (symbol->string (car b))))
          (map cons (vector->list names) (vector->list numbers)))))

;; The sets of helpers, by name: ((set function ...) ...).
(define (inspect-shader-helpers)
  (let-values ([(names sets) (hashtable-entries *shader-helpers*)])
    (sort (lambda (a b)
            (string<? (symbol->string (car a)) (symbol->string (car b))))
          (map (lambda (name forms)
                 (cons name (map caadr forms)))
               (vector->list names) (vector->list sets)))))

;; A layout's fields, by name: ((field reader . offset) ...).
(define (inspect-shader-fields)
  (let-values ([(names rows) (hashtable-entries *shader-fields*)])
    (sort (lambda (a b)
            (string<? (symbol->string (car a)) (symbol->string (car b))))
          (map cons (vector->list names) (vector->list rows)))))

;;; ---- the preview

;; An image w × h for inspect-preview!, and letting go of it.
(define (inspect-preview-image w h) (gpu-image-make-target w h))
(define (inspect-preview-w image) (gpu-image-w image))
(define (inspect-preview-h image) (gpu-image-h image))
(define (inspect-preview-free! image) (gpu-image-release! image))

;; What it holds on the GPU, its levels with it.
(define (inspect-preview-bytes image)
  (let loop ([level 0] [w (gpu-image-w image)] [h (gpu-image-h image)] [n 0])
    (if (= level (gpu-image-levels image))
        n
        (loop (+ level 1) (max 1 (quotient w 2)) (max 1 (quotient h 2))
              (+ n (* 4 w h))))))

;; With the next frame, its first count records drawn on image, but those
;; (left-out spans) gives: ((first . count) ...) in order, spans the frame's
;; labels' spans, as inspect-list-labels has them. Without left-out, none
;; are. The frame is read, flattened, into a list kept for it.
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

;; The frame inspect-preview! draws: a cache, which only saves the buffers.
(define inspect-live (inspect-list-empty))

;; Ahead of the next frame, a kept list's first count records drawn on image,
;; but those left out, as inspect-preview! has them.
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

;; The runs, (mode image first count variant) ..., as far as record n, but
;; those that show image, which is being drawn on.
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

;; The runs but for the records in ranges, ((first . count) ...) in order: a
;; run with records left out in its middle is cut in two.
(define (inspect-runs-without runs ranges)
  (if (null? ranges)
      runs
      (apply append
             (map (lambda (run) (inspect-run-pieces run ranges)) runs))))

;; What's left of run without the records in ranges, as runs.
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

;;; ---- a list repainted, and what a span of it costs

;; into, a list as inspect-list-empty makes, holds l from now on with every
;; record's paint solid, record i's (word-of i), a color's word: what each
;; covers stays, in colors of the caller's choosing (who drew it, its kind).
;; Its runs are those solid records need, blended by mode, a run's (0 over,
;; 3 adding); its extras are l's, its records in into's own buffer when it's
;; big enough. => into
(define (inspect-list-paint! into l word-of mode)
  (let ([n (inspect-list-count l)])
    (when (< (bytevector-length (vector-ref into 0)) (* 32 n))
      (vector-set! into 0 (make-immobile-bytevector (+ (* 32 n) (* 8 n)))))
    (let* ([bytes (vector-ref into 0)]
           [at (lambda (i k) (fx* 4 (fx+ (fx* rec-row-words i) k)))]
           [paint! (lambda (i w)
                     (if (fx< w 0)
                         (bytevector-s32-native-set! bytes (at i rec-row-paint)
                                                     w)
                         (bytevector-u32-native-set! bytes (at i rec-row-paint)
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
      ;; a run a stretch of records that need the same variant
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

;; How many device pixels record i may touch: its reach within its clip and
;; the screen, what the GPU shades for it.
(define (inspect-record-pixels l i)
  (let* ([r (inspect-reach l i)]
         [c (or (inspect-clip l i) (list 0 0 *canvas-pw* *canvas-ph*))]
         [w (- (min (caddr r) (caddr c) *canvas-pw*) (max (car r) (car c) 0))]
         [h (- (min (cadddr r) (cadddr c) *canvas-ph*)
               (max (cadr r) (cadr c) 0))])
    (if (and (> w 0) (> h 0)) (* w h) 0)))

;; What count records of l from first cost: the device pixels they may touch,
;; a pixel once a record over it, and how many runs start among them, each a
;; draw call. => (values pixels runs)
(define (inspect-span-cost l first count)
  (values
   (let loop ([i first] [px 0.0])
     (if (>= i (+ first count))
         (exact (round px))
         (loop (+ i 1) (+ px (inspect-record-pixels l i)))))
   (length (filter (lambda (run) (< -1 (- (caddr run) first) count))
                   (inspect-list-runs l)))))

;; Does record i of l say what record j of b does? What a record says of
;; where it is in the list's extras, its clip and its rows, moves when
;; something before it changes, so it isn't compared.
(define (inspect-record-same? l i b j)
  (let ([head (inspect-word l i rec-row-head)])
    (and (fx= (fxand head #xff) (fxand (inspect-word b j rec-row-head) #xff))
         (for-all (lambda (k)
                    (or (and (fx= k rec-row-paint)
                             (fx= (fxand (fxsrl head 4) 15) 1))
                        (and (fx= k rec-polygon-points)
                             (fx= (fxand head 15) 2))
                        (fx= (inspect-word l i k) (inspect-word b j k))))
                  (cdr (iota rec-row-words))))))

;; How many of count records of l from first differ from bcount records of b
;; from bfirst, one by one, a record past b's counting as changed.
(define (inspect-span-changed l first count b bfirst bcount)
  (let loop ([k 0] [n 0])
    (cond [(= k count) n]
          [(or (>= k bcount)
               (not (inspect-record-same? l (+ first k) b (+ bfirst k))))
           (loop (+ k 1) (+ n 1))]
          [else (loop (+ k 1) n)])))

;;; ---- inside a record

;; The run that draws record i of l, (mode image first count variant), or #f.
(define (inspect-record-run l i)
  (find (lambda (run) (< -1 (- i (caddr run)) (cadddr run)))
        (inspect-list-runs l)))

;; The shader a run's records are drawn with: a paint's own, or the variant
;; of the fragment shader they need.
(define (inspect-run-fragment run)
  (let ([x (cadr run)])
    (if (gpu-call? x)
        (gpu-call-shader x)
        (top-level-value (inspect-run-shader run)))))

;; The helper groups a shader's source takes, wherever it takes them, in
;; order.
(define (inspect-helpers-used form)
  (let walk ([form form] [acc '()])
    (cond [(not (pair? form)) acc]
          [(and (eq? (car form) 'use-shader-helpers) (pair? (cdr form)))
           (if (memq (cadr form) acc) acc (append acc (list (cadr form))))]
          [else (walk (cdr form) (walk (car form) acc))])))

;; A shader's source, pretty-printed, and after it the helpers it uses
;; written out, under their names: lines.
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

;; The glyphs' atlas as an image, to draw: one channel, coverage, as the
;; glyph records read it. Core0's own: it's never let go of here.
(define (inspect-atlas-image) (gpu-atlas-image))
