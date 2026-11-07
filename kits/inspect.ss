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

;; A copy of the last frame's list: #(records extras labels count), labels
;; ((label first-record count) ...) in draw order. Only one list so far: the
;; root's.
(define (inspect-list)
  (let* ([newest (inspect-frames 1)]
         [count (if (null? newest) 0 (cadr (car newest)))]
         [words (if (null? newest) 0 (caddr (car newest)))]
         [records (make-bytevector (* 32 count))]
         [extras (make-bytevector (* 4 words))])
    (bytevector-copy! *rec-bytes* 0 records 0 (* 32 count))
    (bytevector-copy! *rec-extras* 0 extras 0 (* 4 words))
    (vector records extras (inspect-labels count) count)))

(define (inspect-list-count l) (vector-ref l 3))
(define (inspect-list-labels l) (vector-ref l 2))
(define (inspect-list-bytes l)
  (+ (bytevector-length (vector-ref l 0)) (bytevector-length (vector-ref l 1))))

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
  (bytevector-s32-native-ref (vector-ref l 0) (fx* 4 (fx+ (fx* 8 i) k))))

(define (inspect-pixels n) (fl/ (fixnum->flonum n) 256.0))

;; A record's clip row, if it has one: (x0 y0 x1 y1 radius).
(define (inspect-clip l i)
  (let ([row (fxsrl (fxand (inspect-word l i 0) #xffffffff) 8)])
    (and (not (fx= row 0))
         (map (lambda (k)
                (inspect-pixels
                 (bytevector-s32-native-ref (vector-ref l 1)
                                            (fx* 4 (fx+ row k)))))
              '(0 1 2 3 4)))))

(define (inspect-kind l i)
  (vector-ref inspect-kinds (fxand (inspect-word l i 0) 15)))

(define (inspect-paint l i)
  (vector-ref inspect-paints (fxand (fxsrl (inspect-word l i 0) 4) 15)))

;; (x0 y0 x1 y1): what a record may touch, its clip left out.
(define (inspect-reach l i)
  (let ([word (lambda (k) (inspect-word l i k))]
        [px (lambda (k) (inspect-pixels (inspect-word l i k)))])
    (case (inspect-kind l i)
      [(glyph)
       (let* ([n (word 4)]
              [x (fx+ (word 2) (glyph-row-ref n 4))]
              [y (fx- (word 3) (glyph-row-ref n 5))])
         (map fixnum->flonum (list x y (fx+ x (glyph-row-ref n 2))
                                   (fx+ y (glyph-row-ref n 3)))))]
      [(segment)
       (let ([d (fl/ (px 6) 2.0)])
         (list (fl- (flmin (px 2) (px 4)) d) (fl- (flmin (px 3) (px 5)) d)
               (fl+ (flmax (px 2) (px 4)) d) (fl+ (flmax (px 3) (px 5)) d)))]
      [(shadow)
       (let ([d (px 7)])
         (list (fl- (px 2) d) (fl- (px 3) d) (fl+ (px 4) d) (fl+ (px 5) d)))]
      [else (list (px 2) (px 3) (px 4) (px 5))])))

;; A record, for reading: ((kind . box) (paint . solid) (color . #xff112233)
;; (reach x0 y0 x1 y1) (clip x0 y0 x1 y1 radius)), with more by kind: a box's
;; radius and line, a glyph's char.
(define (inspect-record l i)
  (let ([kind (inspect-kind l i)] [paint (inspect-paint l i)])
    `((kind . ,kind)
      (paint . ,paint)
      ,@(if (eq? paint 'solid)
            `((color . ,(fxand (inspect-word l i 1) #xffffffff)))
            '())
      (reach ,@(inspect-reach l i))
      (clip . ,(inspect-clip l i))
      ,@(case kind
          [(box)
           `((radius . ,(inspect-pixels (inspect-word l i 6)))
             (line . ,(inspect-pixels (inspect-word l i 7))))]
          [(glyph)
           `((char . ,(integer->char (glyph-row-ref (inspect-word l i 4) 6))))]
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
                 [chars (list (glyph-row-ref (inspect-word l i 4) 6))])
         (if (and (< j end) (eq? (inspect-kind l j) 'glyph)
                  (= (inspect-word l j 3) (inspect-word l i 3))
                  (= (inspect-word l j 1) (inspect-word l i 1)))
             (run (+ j 1) (cons (glyph-row-ref (inspect-word l j 4) 6) chars))
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
                (format "#~8,'0x" (fxand (inspect-word l i 1) #xffffffff))
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

;;; ---- the preview

;; An image w × h for inspect-preview!, and letting go of it.
(define (inspect-preview-image w h) (gpu-image-make-target w h))
(define (inspect-preview-w image) (gpu-image-w image))
(define (inspect-preview-h image) (gpu-image-h image))
(define (inspect-preview-free! image) (gpu-image-release! image))

;; With the next frame, its first count records drawn on image.
(define (inspect-preview! image count) (rec-preview! image count))
