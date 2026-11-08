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
;; runs frame), labels ((label first-record count) ...) in draw order, row the
;; frame's in inspect-frames, runs those that name no image or paint, frame its
;; number. Only one list so far: the root's.
(define (inspect-list) (inspect-list-read! (inspect-list-empty)))

(define (inspect-list-empty)
  (vector (make-bytevector 0) (make-bytevector 0) '() 0 0 #f '() -1))

;; l holds the last frame's list from now on, in its own buffers when they're
;; big enough: they stay where they are, and a collection needn't copy them.
(define (inspect-list-read! l)
  (let* ([newest (inspect-frames 1)]
         [row (and (pair? newest) (car newest))]
         [count (if row (cadr row) 0)]
         [words (if row (caddr row) 0)]
         [fit! (lambda (slot n)
                 (when (< (bytevector-length (vector-ref l slot)) n)
                   (vector-set! l slot
                                (make-immobile-bytevector
                                 (+ n (quotient n 4))))))])
    (fit! 0 (* 32 count))
    (fit! 1 (* 4 words))
    (bytevector-copy! *rec-bytes* 0 (vector-ref l 0) 0 (* 32 count))
    (bytevector-copy! *rec-extras* 0 (vector-ref l 1) 0 (* 4 words))
    (vector-set! l 2 (inspect-labels count))
    (vector-set! l 3 count)
    (vector-set! l 4 words)
    (vector-set! l 5 row)
    (vector-set! l 6 (filter (lambda (run) (not (cadr run)))
                             (reverse *rec-runs*)))
    (vector-set! l 7 (- *frame-ring-n* 1))
    l))

(define (inspect-list-count l) (vector-ref l 3))
(define (inspect-list-labels l) (vector-ref l 2))
(define (inspect-list-bytes l)
  (+ (* 32 (vector-ref l 3)) (* 4 (vector-ref l 4))))
(define (inspect-list-row l) (vector-ref l 5))
(define (inspect-list-runs l) (vector-ref l 6))
;; The name of the fragment shader a run draws with: the variant its records
;; need.
(define (inspect-run-shader run) (vector-ref gfx-fragments (list-ref run 4)))
(define (inspect-list-frame l) (vector-ref l 7))

;; How many of its runs showed an image or a paint, which aren't kept.
(define (inspect-list-left-out l)
  (let ([row (inspect-list-row l)])
    (if row (- (cadddr row) (length (inspect-list-runs l))) 0)))

;;; ---- the frames kept

;; The last frames' lists, as many as it was made for, by frame number: a ring
;; its caller holds, whose slots' buffers are used again.
(define-record-type inspect-history
  (fields slots (mutable newest)))

(define (inspect-history-new n) (make-inspect-history (make-vector n #f) -1))

;; Keeps the frame drawn last, unless it's kept already.
(define (inspect-history-add! h)
  (let ([frame (- *frame-ring-n* 1)] [slots (inspect-history-slots h)])
    (when (> frame (inspect-history-newest h))
      (let ([i (modulo frame (vector-length slots))])
        (vector-set! slots i
                     (inspect-list-read! (or (vector-ref slots i)
                                             (inspect-list-empty))))
        (inspect-history-newest-set! h frame)))))

;; Frame n's list, while it's kept; or #f.
(define (inspect-history-ref h n)
  (let* ([slots (inspect-history-slots h)]
         [l (and (>= n 0) (vector-ref slots (modulo n (vector-length slots))))])
    (and l (= (inspect-list-frame l) n) l)))

;; How many frames are kept, and the bytes they hold now.
(define (inspect-history-count h)
  (length (filter values (vector->list (inspect-history-slots h)))))
(define (inspect-history-bytes h)
  (fold-left (lambda (n l)
               (if l
                   (+ n (bytevector-length (vector-ref l 0))
                      (bytevector-length (vector-ref l 1)))
                   n))
             0 (vector->list (inspect-history-slots h))))

;; The labels' spans of the first count records: a label holds until the
;; next, and a span of none, or of no label, is left out.
(define (inspect-labels count)
  (let loop ([i (- *rec-label-at* 2)] [end count] [acc '()])
    (if (< i 0)
        acc
        (let ([first (min count (vector-ref *rec-labels* i))]
              [label (vector-ref *rec-labels* (+ i 1))])
          (loop (- i 2) first
                (if (or (not label) (>= first end))
                    acc
                    (cons (list label first (- end first)) acc)))))))

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

;; The records first .. first + count - 1 as rows for reading: #(first count
;; kind what), a run of glyphs on one baseline in one paint being one row
;; whose what is its text.
(define (inspect-rows l first count)
  (let loop ([i first] [end (+ first count)] [acc '()])
    (cond
      [(>= i end) (reverse acc)]
      [(eq? (inspect-kind l i) 'glyph)
       (let run ([j (+ i 1)]
                 [chars (list (inspect-glyph-char l i))])
         (if (and (< j end) (eq? (inspect-kind l j) 'glyph)
                  (= (inspect-word l j rec-glyph-pen-y)
                     (inspect-word l i rec-glyph-pen-y))
                  (= (inspect-word l j rec-row-paint)
                     (inspect-word l i rec-row-paint)))
             (run (+ j 1) (cons (inspect-glyph-char l j) chars))
             (loop j end
                   (cons (vector i (- j i) 'text
                                 (list->string
                                  (map integer->char (reverse chars))))
                         acc))))]
      [else
       (loop (+ i 1) end
             (cons (vector i 1 (inspect-kind l i) (inspect-what l i)) acc))])))

;; A record's paint and size, in words.
(define (inspect-what l i)
  (let ([r (inspect-reach l i)] [paint (inspect-paint l i)])
    (format "~a × ~a  ~a"
            (exact (round (- (caddr r) (car r))))
            (exact (round (- (cadddr r) (cadr r))))
            (if (eq? paint 'solid)
                (format "#~8,'0x"
                        (fxand (inspect-word l i rec-row-paint) #xffffffff))
                paint))))

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

;; What draws: ((renderer . gpu) (window? . #t) (pixels w . h) ...). The
;; display is host-display's, or #f.
(define (inspect-device)
  (let ([r *renderer*])
    `((renderer . ,(renderer-kind r))
      (window? . ,(not (eqv? 0 (renderer-window r))))
      (pixels ,*canvas-pw* . ,*canvas-ph*)
      (scale . ,*canvas-ratio*)
      (driver . ,(gpu-driver-name))
      (present-mode . ,*gpu-present-mode*)
      (present-modes . ,(gpu-present-modes))
      (display . ,(host-display)))))

;; The glyphs made, and how full the atlas is, of 1.
(define (inspect-glyphs)
  `((glyphs . ,(- *glyph-count* 1))
    (atlas-side . ,gpu-atlas-side)
    (atlas-used . ,(/ (+ *atlas-y* *atlas-row*) (inexact gpu-atlas-side)))))

;; What's held on the GPU for frames: ((name kind . bytes) ...).
(define (inspect-gpu-objects)
  (let ([r *renderer*])
    `((records buffer . ,(cdr (renderer-records r)))
      (extras buffer . ,(cdr (renderer-extras r)))
      (glyphs buffer . ,(cdr (renderer-glyphs r)))
      (atlas texture . ,(* gpu-atlas-side gpu-atlas-side))
      (transfer buffer . ,(cdr (renderer-transfer r)))
      (target texture . ,(* 4 (renderer-target-w r) (renderer-target-h r))))))

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

;; With the next frame, its first count records drawn on image.
(define (inspect-preview! image count) (rec-preview! image count))

;; Ahead of the next frame, a kept list's first count records drawn on image.
(define (inspect-preview-list! image l count)
  (rec-past! image (vector-ref l 0) (* 32 (inspect-list-count l))
             (vector-ref l 1) (* 4 (vector-ref l 4))
             (rec-runs-upto (inspect-list-runs l) count image)))
