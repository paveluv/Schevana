;;; gfx.ss — the drawing API apps use.
;;;
;;; A draw paints nothing: it writes flat records of whole numbers into a
;;; list, with no C, no allocation and no questions asked of a renderer; the
;;; GPU draws the list. In logical pixels, and the window manager translates
;;; and clips to a window's content area before calling its draw handler:
;;;
;;;   (fill-box 10 10 100 40 'accent)
;;;   (draw-text 16 20 "hello" 'text 'mono)
;;;
;;; Colors are #xRRGGBB fixnums, theme keys ('accent), (alpha c 0.5),
;;; stipples, patterns used as colors (stipple, below), or gradients
;;; (linear-gradient, below).

(define pi (* 4 (atan 1)))

(defvar *canvas-w* 0)    ; logical size (what apps see)
(defvar *canvas-h* 0)
(defvar *scale* 1.0)     ; logical -> pixel (HiDPI)
(defvar *canvas-ratio* 1)   ; the same, exactly
;; pixel size of the screen
(defvar *canvas-pw* 0)
(defvar *canvas-ph* 0)

;; A canvas pw × ph pixels big, drawn scale times bigger than the logical
;; pixels apps use; its logical size is the whole part of pw / scale.
(define (canvas-create-pixels! pw ph scale)
  (let ([rescaled? (not (= (inexact scale) *scale*))])
    (set! *canvas-pw* pw)
    (set! *canvas-ph* ph)
    (set! *canvas-w* (exact (floor (/ pw scale))))
    (set! *canvas-h* (exact (floor (/ ph scale))))
    (set! *scale* (inexact scale))
    (set! *canvas-ratio* (rationalize (exact scale) 1/100000))
    (when (and *renderer* (eqv? 0 (renderer-window *renderer*)))
      (gpu-set-target! pw ph))
    (request-frame!)
    (when rescaled? (theme-changed!))))

;; A canvas of w × h logical pixels.
(define (canvas-create! w h scale)
  (canvas-create-pixels! (exact (round (* w scale)))
                         (exact (round (* h scale)))
                         scale))

(define (canvas-pixel-width) *canvas-pw*)
(define (canvas-pixel-height) *canvas-ph*)

;;; ------------------------------------------------------------------ colors

(define (rgb r g b) (fxior (fxsll r 16) (fxsll g 8) b))
(define (alpha c a) (cons c a))

;; A pattern used as a color: rows of one length, of #\# (ink) and of
;; anything else (paper; #f paper is clear), a logical pixel each, tiled
;; from the screen's device origin, so tiles line up across windows as
;; Medley's textures do. Plain data: it saves and prints.
;;   (stipple 'text 'bg-1 "#..." "...." "..#." "....")
(define (stipple ink paper . rows) (cons* 'stipple ink paper rows))
(define (stipple? c) (and (pair? c) (eq? (car c) 'stipple)))

;; A gradient used as a color: its colors spread evenly from (x0, y0) to
;; (x1, y1), or from the center (cx, cy) out to radius r, in the
;; coordinates it is drawn in. Plain data, as a stipple is.
;;   (fill-box 0 0 w h (linear-gradient 0 0 0 h 'accent 'bg-1))
(define (linear-gradient x0 y0 x1 y1 . colors)
  (cons* 'linear-gradient x0 y0 x1 y1 colors))
(define (radial-gradient cx cy r . colors)
  (cons* 'radial-gradient cx cy r colors))
(define (gradient? c)
  (and (pair? c) (memq (car c) '(linear-gradient radial-gradient)) #t))

(define (color-rgba c)
  (cond
    [(fixnum? c)
     (values (fl/ (fixnum->flonum (fxand (fxsra c 16) 255)) 255.0)
             (fl/ (fixnum->flonum (fxand (fxsra c 8) 255)) 255.0)
             (fl/ (fixnum->flonum (fxand c 255)) 255.0)
             1.0)]
    [(symbol? c) (color-rgba (theme c))]
    [(stipple? c)   ; its ink and paper mixed by coverage
     (let*-values ([(cells) (string->list (apply string-append (cdddr c)))]
                   [(k) (/ (length (filter (lambda (ch) (char=? ch #\#)) cells))
                           (length cells))]
                   [(r g b a) (color-rgba (cadr c))]
                   [(r2 g2 b2 a2) (color-rgba (or (caddr c) (alpha 0 0)))]
                   [(wi wp) (values (* k a) (* (- 1 k) a2))])
       (define (m x y)
         (if (zero? (+ wi wp)) 0.0 (/ (+ (* wi x) (* wp y)) (+ wi wp))))
       (values (m r r2) (m g g2) (m b b2) (+ wi wp)))]
    [(pair? c)
     (let-values ([(r g b a) (color-rgba (car c))])
       (values r g b (* a (cdr c))))]
    [else (errorf 'color "not a color: ~s" c)]))

;; Blend two colors: t=0 gives c1, t=1 gives c2.
(define (mix c1 c2 t)
  (let-values ([(r1 g1 b1 a1) (color-rgba c1)] [(r2 g2 b2 a2) (color-rgba c2)])
    (define (m a b) (exact (round (* 255 (+ a (* t (- b a)))))))
    (rgb (m r1 r2) (m g1 g2) (m b1 b2))))

;; A color as one pixel: premultiplied, a native word of B, G, R and A bytes,
;; what an image holds. #xRRGGBB is opaque.
(define (color->pixel c)
  (if (fixnum? c)
      (fxior #xff000000 (fxand c #xffffff))
      (let-values ([(r g b a) (color-rgba c)])
        (let ([a (clamp a 0.0 1.0)])
          (define (byte v) (exact (round (* 255 v))))
          (fxior (fxsll (byte a) 24) (fxsll (byte (* r a)) 16)
                 (fxsll (byte (* g a)) 8) (byte (* b a)))))))

;; A color as a record's word: straight, alpha on top. The GPU premultiplies.
(define (color-word c)
  (cond
    [(fixnum? c) (fxior #xff000000 (fxand c #xffffff))]
    [(symbol? c) (color-word (theme c))]
    [else
     (let-values ([(r g b a) (color-rgba c)])
       (let ([byte (lambda (v) (exact (round (* 255 (clamp v 0.0 1.0)))))])
         (fxior (fxsll (byte a) 24) (fxsll (byte r) 16)
                (fxsll (byte g) 8) (byte b))))]))

;;; ------------------------------------------------------------------ fonts
;;; (src/font.ss). The roles, from the four font settings (a style may give
;;; any): the ui or mono family at its size plus d (or twice it).

(define (theme-font-rule family d . opts)
  (theme-rule
   (let ([size (theme (if (eq? family 'ui) 'ui-font-size 'mono-font-size))])
     (apply font (theme (if (eq? family 'ui) 'ui-font 'mono-font))
            (if (eq? d 'twice) (* 2 size) (+ size d)) opts))))
(let loop ([roles (list 'ui (theme-font-rule 'ui 0)
                        'ui-bold (theme-font-rule 'ui 0 'bold)
                        'ui-small (theme-font-rule 'ui -2)
                        'ui-italic (theme-font-rule 'ui 0 'italic)
                        'title (theme-font-rule 'ui 0 'bold)
                        'heading (theme-font-rule 'ui 5 'bold)
                        'big (theme-font-rule 'ui 'twice 'bold)
                        'huge (theme-rule (font "serif" 360 'bold))
                        'mono (theme-font-rule 'mono 0)
                        'mono-small (theme-font-rule 'mono -2)
                        'mono-bold (theme-font-rule 'mono 0 'bold))])
  (unless (null? roles)
    (theme-default! (car roles) (cadr roles))
    (loop (cddr roles))))

;; Faint text's font: its own (#f), or what a style's procedure makes of
;; it, a part (Genera, with no gray, sets its hints in italic).
(theme-default! 'faint-text-font #f)
(define (faint-font color f)
  (let ([make (and (eq? color 'text-faint) (theme-part 'faint-text-font))])
    (if make (make f) f)))

;;; ------------------------------------------------------------------ records
;;; A record is eight 32-bit words, whole numbers: floats are what would
;;; allocate. The format is private to this file and its shaders.
;;;   0  kind (low 4 bits), paint kind (next 4), clip (the rest)
;;;   1  paint: a color's word, or where its row is in the extras
;;;   2 to 5  x0 y0 x1 y1, in 1/256ths of a device pixel
;;;   6, 7  two more, by kind
;;; Kinds:
;;;   box      radius, line width (0: filled)
;;;   segment  width; words 2 to 5 are its ends; round ends
;;;   polygon  where its points are in the extras, how many; words 2 to 5
;;;            hold a box around them
;;;   glyph    pen and baseline, whole pixels; the glyph's number in word 4;
;;;            word 6 is 3 if turned a quarter counterclockwise
;;;   shadow   radius, size; the box casting it
;;; Paint kinds: solid; gradient, whose row is radial?, x0 y0 x1 y1, n and
;;; n colors; stipple, whose row is u v w h, ink and paper; image, whose row
;;; is its width and height.
;;; The extras also hold clips: x0 y0 x1 y1, a radius, the clip it lies in, and
;;; the box that radius rounds: rx0 ry0 rx1 ry1. What's drawn has to be inside
;;; both boxes. Their word 0 is unused, so that clip 0 is no clip.

(define rec-kind-box 0)
(define rec-kind-segment 1)
(define rec-kind-polygon 2)
(define rec-kind-glyph 3)
(define rec-kind-shadow 4)
(define rec-paint-solid 0)
(define rec-paint-gradient 1)
(define rec-paint-stipple 2)
(define rec-paint-image 3)
(define rec-paint-shader 4)
(define rec-most-points 256)

(defvar *rec-bytes* (make-immobile-bytevector (* 32 16384) 0))
(defvar *rec-at* 0)               ; bytes written
(defvar *rec-extras* (make-immobile-bytevector (* 4 65536) 0))
(defvar *rec-extra-at* 1)         ; words written
;; the transform: num/den device pixels a logical pixel, the origin in
;; 1/256ths of a device pixel; a turn, as cos and sin, or #f
(defvar *rec-num* 1)
(defvar *rec-den* 1)
(defvar *rec-ox* 0)
(defvar *rec-oy* 0)
(defvar *rec-turn* #f)
;; the clip: where its row is, 0 for none; its box, while there's one
(defvar *rec-labels* (make-vector 256 #f))   ; (record label) ...
(defvar *rec-label-at* 0)
(defvar *rec-label* #f)
(defvar *rec-clip* 0)
(defvar *rec-cx0* 0)
(defvar *rec-cy0* 0)
(defvar *rec-cx1* 0)
(defvar *rec-cy1* 0)
;; runs, the newest first: (mode image first count); this one's mode, image
;; and first record
(defvar *rec-runs* '())
(defvar *rec-mode* 0)
(defvar *rec-image* #f)
(defvar *rec-run-first* 0)
(defvar *rec-images* '())         ; images with pixels to go up
;; what shaders' cost a list adds up to, as it's written: area in pixels
(defvar *rec-area* 0)

(define (rec-records-grow!)
  (let ([new (make-immobile-bytevector (* 2 (bytevector-length *rec-bytes*)))])
    (bytevector-copy! *rec-bytes* 0 new 0 *rec-at*)
    (set! *rec-bytes* new)))

(define (rec-put! w0 w1 x0 y0 x1 y1 a b)
  (let ([at *rec-at*])
    (when (fx= at (bytevector-length *rec-bytes*)) (rec-records-grow!))
    (let ([bv *rec-bytes*])
      (bytevector-u32-native-set! bv at w0)
      (bytevector-u32-native-set! bv (fx+ at 4) w1)
      (bytevector-s32-native-set! bv (fx+ at 8) x0)
      (bytevector-s32-native-set! bv (fx+ at 12) y0)
      (bytevector-s32-native-set! bv (fx+ at 16) x1)
      (bytevector-s32-native-set! bv (fx+ at 20) y1)
      (bytevector-s32-native-set! bv (fx+ at 24) a)
      (bytevector-s32-native-set! bv (fx+ at 28) b)
      (set! *rec-at* (fx+ at 32)))))

(define (rec-extras-room! n)
  (when (> (* 4 (+ *rec-extra-at* n)) (bytevector-length *rec-extras*))
    (let ([new (make-immobile-bytevector
                (* 2 (+ (bytevector-length *rec-extras*) (* 4 n))))])
      (bytevector-copy! *rec-extras* 0 new 0 (* 4 *rec-extra-at*))
      (set! *rec-extras* new))))

(define (rec-extra! v)
  (rec-extras-room! 1)
  (bytevector-s32-native-set! *rec-extras* (fx* 4 *rec-extra-at*) v)
  (set! *rec-extra-at* (fx+ *rec-extra-at* 1)))

(define (rec-extra-u32! v)
  (rec-extras-room! 1)
  (bytevector-u32-native-set! *rec-extras* (fx* 4 *rec-extra-at*) v)
  (set! *rec-extra-at* (fx+ *rec-extra-at* 1)))

;; Starts a list at a scale. A new list resets everything, so a draw that
;; crashed leaves nothing to unwind.
(define (rec-begin! ratio)
  (set! *rec-at* 0)
  (set! *rec-extra-at* 1)
  (set! *rec-num* (numerator ratio))
  (set! *rec-den* (denominator ratio))
  (set! *rec-ox* 0)
  (set! *rec-oy* 0)
  (set! *rec-turn* #f)
  (set! *rec-clip* 0)
  (set! *rec-label-at* 0)
  (set! *rec-label* #f)
  (set! *rec-runs* '())
  (set! *rec-mode* 0)
  (set! *rec-image* #f)
  (set! *rec-run-first* 0)
  (set! *rec-images* '())
  (set! *rec-area* 0))

(define (rec-count) (fxquotient *rec-at* 32))

;; The run so far ends here.
(define (rec-run-end!)
  (let ([n (rec-count)])
    (when (fx> n *rec-run-first*)
      (set! *rec-runs*
        (cons (list *rec-mode* *rec-image* *rec-run-first*
                    (fx- n *rec-run-first*))
              *rec-runs*))
      (set! *rec-run-first* n))))

(define (rec-run! mode image)
  (unless (and (eqv? mode *rec-mode*) (eq? image *rec-image*))
    (rec-run-end!)
    (set! *rec-mode* mode)
    (set! *rec-image* image)))

;; The state a window's draw starts from, to go back to when it crashes.
(define (rec-state)
  (vector *rec-num* *rec-den* *rec-ox* *rec-oy* *rec-turn* *rec-clip*
          *rec-cx0* *rec-cy0* *rec-cx1* *rec-cy1*))
(define (rec-state-set! s)
  (set! *rec-num* (vector-ref s 0))
  (set! *rec-den* (vector-ref s 1))
  (set! *rec-ox* (vector-ref s 2))
  (set! *rec-oy* (vector-ref s 3))
  (set! *rec-turn* (vector-ref s 4))
  (set! *rec-clip* (vector-ref s 5))
  (set! *rec-cx0* (vector-ref s 6))
  (set! *rec-cy0* (vector-ref s 7))
  (set! *rec-cx1* (vector-ref s 8))
  (set! *rec-cy1* (vector-ref s 9))
  (rec-run! 0 #f))

;;; ---- the transform

;; v, along an axis whose origin is o, in 1/256ths of a device pixel.
(define (rec-device v o)
  (if (fixnum? v)
      (fx+ o (fxdiv (fx* (fx* v *rec-num*) 256) *rec-den*))
      (fx+ o (exact (floor (+ 1/2 (/ (* (exact v) *rec-num* 256)
                                     *rec-den*)))))))

;; A length in 1/256ths of a device pixel.
(define (rec-length v) (rec-device v 0))

;; To the nearest whole pixel, half up: px's rule, so that no box is ever
;; blurred, and neighbors share an edge with no gap.
(define (rec-snap d) (fxand (fx+ d 128) -256))

;; Under a turn: (x, y) in 1/256ths of a device pixel, as a pair.
(define (rec-turned x y)
  (let* ([t *rec-turn*]
         [c (car t)]
         [s (cdr t)]
         [dx (* (inexact x) (/ *rec-num* *rec-den*) 256.0)]
         [dy (* (inexact y) (/ *rec-num* *rec-den*) 256.0)])
    (cons (+ *rec-ox* (exact (round (- (* c dx) (* s dy)))))
          (+ *rec-oy* (exact (round (+ (* s dx) (* c dy))))))))

;;; ---- paints

;; Sets the paint's kind in *rec-paint-kind*; => the record's word 1.
(defvar *rec-paint-kind* 0)
(define (rec-paint color)
  (cond
    [(fixnum? color)
     (set! *rec-paint-kind* 0)
     (fxior #xff000000 (fxand color #xffffff))]
    [(symbol? color) (rec-paint (theme color))]
    [(stipple? color) (rec-stipple color)]
    [(gradient? color) (rec-gradient color)]
    [else
     (set! *rec-paint-kind* 0)
     (color-word color)]))

(define (rec-head kind)
  (fxior kind (fxsll *rec-paint-kind* 4) (fxsll *rec-clip* 8)))

(define (rec-gradient c)
  (let* ([radial? (eq? (car c) 'radial-gradient)]
         [colors (list-tail c (if radial? 4 5))]
         [n (length colors)]
         [words (map color-word colors)]
         [row *rec-extra-at*])
    (rec-extra! (if radial? 1 0))
    (if radial?
        (apply (lambda (cx cy r)
                 (rec-extra! (rec-device cx *rec-ox*))
                 (rec-extra! (rec-device cy *rec-oy*))
                 (rec-extra! (rec-length r))
                 (rec-extra! 0))
               (list-head (cdr c) 3))
        (apply (lambda (x0 y0 x1 y1)
                 (rec-extra! (rec-device x0 *rec-ox*))
                 (rec-extra! (rec-device y0 *rec-oy*))
                 (rec-extra! (rec-device x1 *rec-ox*))
                 (rec-extra! (rec-device y1 *rec-oy*)))
               (list-head (cdr c) 4)))
    (rec-extra! n)
    (for-each rec-extra-u32! words)
    (set! *rec-paint-kind* rec-paint-gradient)
    row))

;; A stipple's tile in the atlas, on device pixels where px's rule puts them
;; at this scale (logical ceiling((d + 1/2)/s) - 1), whole periods: exact
;; anywhere. Coverage only: its colors stay in the record's row, so that a
;; palette's change needs no new tile. Made once per rows and scale.
(define (rec-stipple c)
  (let* ([s (/ *rec-num* *rec-den*)]
         [rows (cdddr c)]
         [key (cons s rows)]
         [tile (or (hashtable-ref *stipple-tiles* key #f)
                   (let ([t (stipple-tile rows s)])
                     (hashtable-set! *stipple-tiles* key t)
                     t))]
         [ink (color-word (cadr c))]
         [paper (if (caddr c) (color-word (caddr c)) 0)]
         [row *rec-extra-at*])
    (for-each rec-extra! tile)
    (rec-extra-u32! ink)
    (rec-extra-u32! paper)
    (set! *rec-paint-kind* rec-paint-stipple)
    row))

(define (stipple-tile rows s)
  (let* ([w (string-length (car rows))]
         [h (length rows)]
         [pw (numerator (* w s))]
         [ph (numerator (* h s))]
         [at (lambda (d n) (mod (- (ceiling (/ (+ d 1/2) s)) 1) n))]
         [us (list->vector (map (lambda (x) (at x w)) (iota pw)))]
         [bytes (make-bytevector (* pw ph) 0)])
    (do ([y 0 (+ y 1)]) ((= y ph))
      (let ([row (list-ref rows (at y h))])
        (do ([x 0 (+ x 1)]) ((= x pw))
          (when (char=? #\# (string-ref row (vector-ref us x)))
            (bytevector-u8-set! bytes (+ x (* y pw)) 255)))))
    (let ([place (atlas-place! pw ph bytes)])
      (list (car place) (cdr place) pw ph))))

;;; ---- shapes

;; Whether nothing of this box can show through the clip.
(define (rec-clipped? x0 y0 x1 y1)
  (and (not (fx= *rec-clip* 0))
       (or (fx>= x0 *rec-cx1*) (fx>= y0 *rec-cy1*)
           (fx<= x1 *rec-cx0*) (fx<= y1 *rec-cy0*))))

;; corner radius 0 makes a style square: all it draws, an app's too
(define (rec-radius r w h)
  (if (eqv? r 0)
      0
      (if (<= (theme 'corner-radius) 0)
          0
          (max 0 (rec-length (min r (/ (abs w) 2) (/ (abs h) 2)))))))

(define (rec-box! x y w h color radius line)
  (if *rec-turn*
      (fill-polygon (list (cons x y) (cons (+ x w) y)
                          (cons (+ x w) (+ y h)) (cons x (+ y h)))
                    color)
      (let* ([ax (rec-snap (rec-device x *rec-ox*))]
             [ay (rec-snap (rec-device y *rec-oy*))]
             [bx (rec-snap (rec-device (+ x w) *rec-ox*))]
             [by (rec-snap (rec-device (+ y h) *rec-oy*))]
             [x0 (fxmin ax bx)]
             [y0 (fxmin ay by)]
             [x1 (fxmax ax bx)]
             [y1 (fxmax ay by)])
        (unless (or (fx= x0 x1) (fx= y0 y1) (rec-clipped? x0 y0 x1 y1))
          (let ([paint (rec-paint color)])
            (rec-put! (rec-head rec-kind-box) paint x0 y0 x1 y1
                      radius line))))))

;; (fill-box x y w h color [r]): a rect, or with r a rounded one, a pill.
(define fill-box
  (case-lambda
    [(x y w h color) (rec-box! x y w h color 0 0)]
    [(x y w h color r) (rec-box! x y w h color (rec-radius r w h) 0)]))

;; A line lw wide inside the box, a whole number of pixels, at least one.
(define (rec-line-width lw)
  (fxmax 256 (rec-snap (rec-length lw))))

(define stroke-box
  (case-lambda
    [(x y w h color) (stroke-box x y w h color 1 0)]
    [(x y w h color lw) (stroke-box x y w h color lw 0)]
    [(x y w h color lw r)
     (rec-box! x y w h color (rec-radius r w h) (rec-line-width lw))]))

;; A circle isn't snapped: only straight edges want whole pixels.
(define (rec-circle! cx cy r color line)
  (let* ([x (rec-device cx *rec-ox*)]
         [y (rec-device cy *rec-oy*)]
         [d (rec-length r)]
         [o (fx+ d (fxquotient line 2))])
    (unless (rec-clipped? (fx- x o) (fx- y o) (fx+ x o) (fx+ y o))
      (let ([paint (rec-paint color)])
        (rec-put! (rec-head rec-kind-box) paint
                  (fx- x o) (fx- y o) (fx+ x o) (fx+ y o) o line)))))

(define (fill-circle cx cy r color) (rec-circle! cx cy r color 0))

(define stroke-circle
  (case-lambda
    [(cx cy r color) (stroke-circle cx cy r color 1)]
    [(cx cy r color lw) (rec-circle! cx cy r color (rec-length lw))]))

(define (rec-point-x x y)
  (if *rec-turn* (car (rec-turned x y)) (rec-device x *rec-ox*)))
(define (rec-point-y x y)
  (if *rec-turn* (cdr (rec-turned x y)) (rec-device y *rec-oy*)))

(define draw-line
  (case-lambda
    [(x1 y1 x2 y2 color) (draw-line x1 y1 x2 y2 color 1)]
    [(x1 y1 x2 y2 color lw)
     (let ([paint (rec-paint color)])
       (rec-put! (rec-head rec-kind-segment) paint
                 (rec-point-x x1 y1) (rec-point-y x1 y1)
                 (rec-point-x x2 y2) (rec-point-y x2 y2)
                 (rec-length lw) 0))]))

;; points: list of (x . y). A record a segment: one that's translucent
;; darkens a little at its joints.
(define draw-polyline
  (case-lambda
    [(points color) (draw-polyline points color 1)]
    [(points color lw)
     (unless (null? points)
       (if (null? (cdr points))
           (draw-line (caar points) (cdar points) (caar points) (cdar points)
                      color lw)
           (let loop ([a (car points)] [ps (cdr points)])
             (unless (null? ps)
               (draw-line (car a) (cdr a) (caar ps) (cdar ps) color lw)
               (loop (car ps) (cdr ps))))))]))

;; points: list of (x . y). Icons, not thousands of points: the shader's
;; loop has a bound, and the points past it are dropped.
(define (fill-polygon points color)
  (unless (null? points)
    (let* ([paint (rec-paint color)]
           [head (rec-head rec-kind-polygon)]
           [points (if (> (length points) rec-most-points)
                       (list-head points rec-most-points)
                       points)]
           [xs (map (lambda (p) (rec-point-x (car p) (cdr p))) points)]
           [ys (map (lambda (p) (rec-point-y (car p) (cdr p))) points)]
           [row *rec-extra-at*])
      (for-each (lambda (x y) (rec-extra! x) (rec-extra! y)) xs ys)
      (rec-put! head paint
                (apply min xs) (apply min ys) (apply max xs) (apply max ys)
                row (length points)))))

;; Each pixel becomes sum - pixel: reverse video, in any palette. With a
;; pattern, it inverts by how much of each pixel the pattern covers.
(define invert-box
  (case-lambda
    [(x y w h) (invert-box x y w h #xffffff)]
    [(x y w h sum)
     ;; a pattern inverts where it shows, and leaves its clear pixels alone
     (rec-run! (if (stipple? sum) 2 1) #f)
     (rec-box! x y w h sum 0 0)
     (rec-run! 0 #f)]))

;; Adds color to each pixel: what's past white from invert-box's sum.
(define (add-box x y w h color)
  (rec-run! 3 #f)
  (rec-box! x y w h color 0 0)
  (rec-run! 0 #f))

;; A box with a shadow under it, lower by a third of its size. The shader
;; fades it out over size pixels; a stack of translucent boxes would give
;; the same line. With turned drawing, none.
(define (rec-shadow! x y w h r size color)
  (unless *rec-turn*
    (let* ([x0 (rec-snap (rec-device x *rec-ox*))]
           [y0 (rec-snap (rec-device y *rec-oy*))]
           [x1 (rec-snap (rec-device (+ x w) *rec-ox*))]
           [y1 (rec-snap (rec-device (+ y h) *rec-oy*))]
           [d (rec-length size)]
           [paint (rec-paint color)])
      (unless (rec-clipped? (fx- x0 d) (fx- y0 d) (fx+ x1 d) (fx+ y1 d))
        (rec-put! (rec-head rec-kind-shadow) paint x0 y0 x1 y1
                  (rec-radius r w h) d)))))

;; A soft shadow under the box (x y w h) with corner radius r, spreading
;; size pixels, a little lower than the box.
(define (draw-shadow x y w h r size)
  (when (> size 0)
    (rec-shadow! x (+ y (/ size 3)) w h r size (alpha #x000000 0.11))))

;;; ---- text

;; Draws str with its top-left at (x, y). => the x where the text ends.
(define draw-text
  (case-lambda
    [(x y str) (draw-text x y str 'text 'ui)]
    [(x y str color) (draw-text x y str color 'ui)]
    [(x y str color font)
     (let* ([f (faint-font color (get-font font))]
            [ff (font-ready f)]
            [paint (rec-paint color)]
            [head (rec-head rec-kind-glyph)]
            [num *rec-num*]
            [den *rec-den*]
            [pages (font-glyph-pages f num den)]
            [crisp? (font-crisp? f)]
            [n (string-length str)]
            [start (rec-text-x x)]
            [turned? (and *rec-turn* #t)]
            [base-y (fxsra (rec-snap (rec-device (+ y (font-ascent f))
                                                 *rec-oy*))
                           8)]
            [base-x (fxsra (rec-snap (rec-device (+ y (font-ascent f))
                                                 *rec-ox*))
                           8)]
            [ox *rec-ox*]
            [oy *rec-oy*])
       (let loop ([i 0] [pen start])
         (if (fx= i n)
             (fl/ (fixnum->flonum pen) 256.0)
             (let* ([c (char->integer (string-ref str i))]
                    [along (fxdiv (fx* pen num) den)]
                    [d (if turned?
                           (fx+ 32 (fx- oy along))
                           (fx+ 32 (fx+ ox along)))]
                    [phase (if (or crisp? turned?) 0 (fxand (fxsra d 6) 3))]
                    [px (fxsra d 8)]
                    [g (font-glyph f pages num den c phase)])
               (when (fx> g 0)
                 (if turned?
                     (rec-put! head paint base-x px g 0 3 0)
                     (let ([gh (glyph-row-ref g 3)] [top (glyph-row-ref g 5)])
                       (unless (and (not (fx= *rec-clip* 0))
                                    (or (fx>= (fxsll px 8) *rec-cx1*)
                                        (fx>= (fxsll (fx- base-y top) 8)
                                              *rec-cy1*)
                                        (fx<= (fxsll (fx+ (fx- base-y top) gh)
                                                     8)
                                              *rec-cy0*)))
                         (rec-put! head paint px base-y g 0 0 0)))))
               (loop (fx+ i 1) (fx+ pen (font-advance f ff c)))))))]))

;; x, in 1/256ths of a logical pixel: a pen's start.
(define (rec-text-x x)
  (if (fixnum? x)
      (fxsll x 8)
      (exact (floor (* (exact x) 256)))))

;;; ---- images

;; An image for pixels a Scheme bytevector holds, by the bytevector, while
;; it lives; each drawing sends its pixels up again.
(defvar *pixel-images* (make-weak-eq-hashtable))

;; Draws the pw × ph pixels in bytes scaled to w × h at (x, y), each pixel
;; a sharp block.
(define (draw-pixels bytes pw ph x y w h)
  (when (and (> w 0) (> h 0))
    (let* ([image (let ([i (hashtable-ref *pixel-images* bytes #f)])
                    (if (and i (= (gpu-image-w i) pw) (= (gpu-image-h i) ph))
                        i
                        (let ([i (gpu-image-make pw ph)])
                          (hashtable-set! *pixel-images* bytes i)
                          i)))])
      (unless (memq image *rec-images*)
        (set! *rec-images* (cons image *rec-images*)))
      (gpu-image-write! image bytes)
      (draw-image image x y w h))))

;; An image on the GPU, scaled to w × h at (x, y), each pixel a sharp block.
(define (draw-image image x y w h)
  (let ([row *rec-extra-at*])
    (rec-extra! (gpu-image-w image))
    (rec-extra! (gpu-image-h image))
    (rec-run! 0 image)
    (let* ([x0 (rec-snap (rec-device x *rec-ox*))]
           [y0 (rec-snap (rec-device y *rec-oy*))]
           [x1 (rec-snap (rec-device (+ x w) *rec-ox*))]
           [y1 (rec-snap (rec-device (+ y h) *rec-oy*))])
      (set! *rec-paint-kind* rec-paint-image)
      (rec-put! (rec-head rec-kind-box) row x0 y0 x1 y1 0 0))
    (rec-run! 0 #f)))

;;; ------------------------------------------------------------------ paints
;;; A paint is a fragment shader the person writes: its body runs for each
;;; pixel of the box it fills, x and y from the box's corner in device pixels,
;;; and gives a color's word, #xAARRGGBB; 0 leaves the pixel alone. What's
;;; left, the clip and the blending, the wrapper around it does. Its buffers
;;; and numbers change without a thing recorded again.

(define-record-type gfx-paint
  (nongenerative schevana-gfx-paint-1)
  (fields shader params))   ; params: as it was given them, colors and all

;; The core's clip, then the body; the source the compiler is given.
(define (gfx-paint-source x y forms)
  `((define (word k) (fx-ref records (fx+ (fx* id 8) k)))
    (define (extra k) (fx-ref extras k))
    (define (pixels n) (fl/ (fixnum->flonum n) 256.0))
    (define (box-distance x0 y0 x1 y1 r)
      (let* ([qx (fl- (flabs (fl- px (fl* 0.5 (fl+ x0 x1))))
                      (fl- (fl* 0.5 (fl- x1 x0)) r))]
             [qy (fl- (flabs (fl- py (fl* 0.5 (fl+ y0 y1))))
                      (fl- (fl* 0.5 (fl- y1 y0)) r))]
             [ox (flmax qx 0.0)]
             [oy (flmax qy 0.0)])
        (fl- (fl+ (flsqrt (fl+ (fl* ox ox) (fl* oy oy)))
                  (flmin (flmax qx qy) 0.0))
             r)))
    (define (channel w shift)
      (fl/ (fixnum->flonum (fxand (fxsrl w shift) 255)) 255.0))
    (let* ([clip (fxsrl (word 0) 8)]
           [m (if (fx= clip 0)
                  1.0
                  (flmax
                   0.0
                   (flmin
                    1.0
                    (fl- 0.5
                         (flmax
                          (box-distance (pixels (extra clip))
                                        (pixels (extra (fx+ clip 1)))
                                        (pixels (extra (fx+ clip 2)))
                                        (pixels (extra (fx+ clip 3)))
                                        0.0)
                          (if (fx= (extra (fx+ clip 4)) 0)
                              -1.0
                              (box-distance
                               (pixels (extra (fx+ clip 6)))
                               (pixels (extra (fx+ clip 7)))
                               (pixels (extra (fx+ clip 8)))
                               (pixels (extra (fx+ clip 9)))
                               (pixels (extra (fx+ clip 4))))))))))]
           [,x (fx- (flonum->fixnum (flfloor px)) (fxsra (word 2) 8))]
           [,y (fx- (flonum->fixnum (flfloor py)) (fxsra (word 3) 8))]
           [c (let () ,@forms)]
           [a (fl* m (channel c 24))])
      (emit-color (fl* a (channel c 16))
                  (fl* a (channel c 8))
                  (fl* a (channel c 0))
                  a))))

(define-syntax define-paint
  (lambda (x)
    (syntax-case x ()
      [(k (name px py) params form ...)
       (let* ([given (datum params)]
              ;; to the compiler, a color is a whole number
              [plain (map (lambda (p)
                            (if (eq? (cadr p) 'color)
                                (list (car p) 'fixnum)
                                p))
                          given)]
              [source (gfx-paint-source (datum px) (datum py)
                                        (datum (form ...)))]
              [compiled (shader-compile 'fragment '(px py id)
                                        (append '((records fx-buffer)
                                                  (extras fx-buffer))
                                                plain)
                                        source)])
         (with-syntax ([code (datum->syntax #'k (car compiled))]
                       [price (datum->syntax #'k (cdr compiled))]
                       [plain (datum->syntax #'k plain)]
                       [source (datum->syntax #'k source)])
           #'(define name
               (make-gfx-paint
                (make-shader 'name 'fragment '(px py id)
                             (append '((records fx-buffer)
                                       (extras fx-buffer))
                                     'plain)
                             'source 'code price)
                'params))))])))

;; A box filled by a paint, its arguments in its parameters' order: a color
;; as ever (a theme key, say), whole numbers, floats, buffers.
(define (fill-shader x y w h paint . args)
  (let ([params (gfx-paint-params paint)])
    (rec-run! 0 (gpu-make-call
                 (gfx-paint-shader paint) '()
                 (map (lambda (p)
                        (if (eq? (cadr p) 'color) (list (car p) 'fixnum) p))
                      params)
                 (map (lambda (p a) (if (eq? (cadr p) 'color) (color-word a) a))
                      params args)))
    (let ([x0 (rec-snap (rec-device x *rec-ox*))]
          [y0 (rec-snap (rec-device y *rec-oy*))]
          [x1 (rec-snap (rec-device (+ x w) *rec-ox*))]
          [y1 (rec-snap (rec-device (+ y h) *rec-oy*))])
      (set! *rec-paint-kind* rec-paint-shader)
      (rec-put! (rec-head rec-kind-box) 0 x0 y0 x1 y1 0 0))
    (rec-run! 0 #f)))

;;; ------------------------------------------------------------------ state

;; What's drawn next is clipped to a box, rounded if r: nested clips intersect
;; their boxes, and a clip with no radius keeps the rounded box it lies in, so
;; that a window's content stays inside the window's corners. Of two rounded
;; ones, the innermost holds.
(define (rec-clip-enter! x y w h r)
  (let* ([clip *rec-clip*]
         [ax (rec-snap (rec-device x *rec-ox*))]
         [ay (rec-snap (rec-device y *rec-oy*))]
         [bx (rec-snap (rec-device (+ x w) *rec-ox*))]
         [by (rec-snap (rec-device (+ y h) *rec-oy*))]
         [x0 (if (fx= clip 0) ax (fxmax ax *rec-cx0*))]
         [y0 (if (fx= clip 0) ay (fxmax ay *rec-cy0*))]
         [x1 (fxmax x0 (if (fx= clip 0) bx (fxmin bx *rec-cx1*)))]
         [y1 (fxmax y0 (if (fx= clip 0) by (fxmin by *rec-cy1*)))]
         [radius (rec-radius r w h)]
         [own? (or (fx= clip 0) (not (eqv? radius 0)))]
         [row *rec-extra-at*])
    (rec-extra! x0)
    (rec-extra! y0)
    (rec-extra! x1)
    (rec-extra! y1)
    (rec-extra! (if own? radius (rec-extra-ref clip 4)))
    (rec-extra! clip)
    (rec-extra! (if own? ax (rec-extra-ref clip 6)))
    (rec-extra! (if own? ay (rec-extra-ref clip 7)))
    (rec-extra! (if own? bx (rec-extra-ref clip 8)))
    (rec-extra! (if own? by (rec-extra-ref clip 9)))
    (set! *rec-clip* row)
    (set! *rec-cx0* x0)
    (set! *rec-cy0* y0)
    (set! *rec-cx1* x1)
    (set! *rec-cy1* y1)))

(define (rec-extra-ref row k)
  (bytevector-s32-native-ref *rec-extras* (fx* 4 (fx+ row k))))

(define (rec-clip-leave!)
  (let ([clip (rec-extra-ref *rec-clip* 5)])
    (set! *rec-clip* clip)
    (unless (fx= clip 0)
      (set! *rec-cx0* (rec-extra-ref clip 0))
      (set! *rec-cy0* (rec-extra-ref clip 1))
      (set! *rec-cx1* (rec-extra-ref clip 2))
      (set! *rec-cy1* (rec-extra-ref clip 3)))))

;; These are forms, not procedures taking a thunk: no closure a call, and a
;; draw that raises leaves nothing to unwind (record-world! resets the state).
(define-syntax with-clip
  (syntax-rules ()
    [(_ (x y w h) body ...) (with-clip (x y w h 0) body ...)]
    [(_ (x y w h r) body ...)
     (begin
       (rec-clip-enter! x y w h r)
       (let ([value (let () body ...)])
         (rec-clip-leave!)
         value))]))

(define-syntax with-translation
  (syntax-rules ()
    [(_ (dx dy) body ...)
     (let ([ox *rec-ox*] [oy *rec-oy*])
       (rec-translate! dx dy)
       (let ([value (let () body ...)])
         (set! *rec-ox* ox)
         (set! *rec-oy* oy)
         value))]))

(define (rec-translate! dx dy)
  (let ([x (rec-point-x dx dy)] [y (rec-point-y dx dy)])
    (set! *rec-ox* x)
    (set! *rec-oy* y)))

(define-syntax with-scale
  (syntax-rules ()
    [(_ (s) body ...)
     (let ([num *rec-num*] [den *rec-den*])
       (rec-scale! s)
       (let ([value (let () body ...)])
         (set! *rec-num* num)
         (set! *rec-den* den)
         value))]))

(define (rec-scale! s)
  (let ([s (rationalize (exact s) 1/100000)])
    (set! *rec-num* (* *rec-num* (numerator s)))
    (set! *rec-den* (* *rec-den* (denominator s)))))

;; Turned by angle radians, clockwise on the screen. Lines and polygons turn
;; any way; boxes become polygons; text turns by a quarter counterclockwise
;; only, all that's asked of it.
(define-syntax with-turn
  (syntax-rules ()
    [(_ (angle) body ...)
     (let ([turn *rec-turn*])
       (rec-turn! angle)
       (let ([value (let () body ...)])
         (set! *rec-turn* turn)
         value))]))

(define (rec-turn! angle)
  (let ([a (inexact angle)])
    (set! *rec-turn* (cons (cos a) (sin a)))))

;; Names what's drawn inside, for the Pipeline: a label holds from a record
;; on, until the next.
(define-syntax with-label
  (syntax-rules ()
    [(_ (text) body ...)
     (let ([outer *rec-label*])
       (rec-label! text)
       (let ([value (let () body ...)])
         (rec-label! outer)
         value))]))

(define (rec-label! text)
  (when (fx= *rec-label-at* (vector-length *rec-labels*))
    (let ([new (make-vector (fx* 2 *rec-label-at*) #f)])
      (do ([i 0 (fx+ i 1)]) ((fx= i *rec-label-at*))
        (vector-set! new i (vector-ref *rec-labels* i)))
      (set! *rec-labels* new)))
  (vector-set! *rec-labels* *rec-label-at* (rec-count))
  (vector-set! *rec-labels* (fx+ *rec-label-at* 1) text)
  (set! *rec-label-at* (fx+ *rec-label-at* 2))
  (set! *rec-label* text))

;; Device pixels per logical pixel where we draw: the picker's miniature is
;; drawn scaled down.
(define (draw-scale) (/ (inexact *rec-num*) *rec-den*))

;;; ------------------------------------------------------------------ shaders
;;; One shader draws everything, in one instanced call and in order, but for
;;; what forces a new run: an image, or another blend.

(define-vertex-shader (gfx-vertex v i)
  ([records fx-buffer]
   [extras fx-buffer]
   [glyphs fx-buffer]
   [tw flonum]
   [th flonum]
   [first fixnum])
  (define (word k) (fx-ref records (fx+ (fx* (fx+ i first) 8) k)))
  (define (pixels n) (fl/ (fixnum->flonum n) 256.0))
  (define (whole n) (fixnum->flonum n))
  (let* ([head (word 0)]
         [kind (fxand head 15)]
         [clip (fxsrl head 8)]
         [glyph? (fx= kind 3)]
         [row (fx* (word 4) 7)]
         [gw (if glyph? (whole (fx-ref glyphs (fx+ row 2))) 0.0)]
         [gh (if glyph? (whole (fx-ref glyphs (fx+ row 3))) 0.0)]
         [gl (if glyph? (whole (fx-ref glyphs (fx+ row 4))) 0.0)]
         [gt (if glyph? (whole (fx-ref glyphs (fx+ row 5))) 0.0)]
         [pen-x (whole (word 2))]
         [pen-y (whole (word 3))]
         [turned? (fx= (word 6) 3)]
         [grow (if (fx= kind 0)
                   (if (and (fx= (word 6) 0) (fx= (word 7) 0)) 0.0 1.0)
                   (if (fx= kind 1)
                       (fl+ 1.0 (fl* 0.5 (pixels (word 6))))
                       (if (fx= kind 2)
                           1.0
                           (fl+ 1.0 (pixels (word 7))))))]
         [x0 (if glyph?
                 (if turned? (fl- pen-x gt) (fl+ pen-x gl))
                 (fl- (flmin (pixels (word 2)) (pixels (word 4))) grow))]
         [y0 (if glyph?
                 (if turned? (fl- (fl- pen-y gl) gw) (fl- pen-y gt))
                 (fl- (flmin (pixels (word 3)) (pixels (word 5))) grow))]
         [x1 (if glyph?
                 (if turned? (fl+ (fl- pen-x gt) gh) (fl+ (fl+ pen-x gl) gw))
                 (fl+ (flmax (pixels (word 2)) (pixels (word 4))) grow))]
         [y1 (if glyph?
                 (if turned? (fl- pen-y gl) (fl+ (fl- pen-y gt) gh))
                 (fl+ (flmax (pixels (word 3)) (pixels (word 5))) grow))]
         [clipped? (not (fx= clip 0))]
         [left (flfloor (if clipped?
                            (flmax x0 (pixels (fx-ref extras clip)))
                            x0))]
         [top (flfloor (if clipped?
                           (flmax y0 (pixels (fx-ref extras (fx+ clip 1))))
                           y0))]
         [right (flmax left
                       (flceiling
                        (if clipped?
                            (flmin x1 (pixels (fx-ref extras (fx+ clip 2))))
                            x1)))]
         [bottom (flmax top
                        (flceiling
                         (if clipped?
                             (flmin y1 (pixels (fx-ref extras (fx+ clip 3))))
                             y1)))]
         [px (if (or (fx= v 1) (fx= v 3) (fx= v 5)) right left)]
         [py (if (or (fx= v 2) (fx= v 4) (fx= v 5)) bottom top)])
    (emit-position (fl- (fl/ (fl* 2.0 px) tw) 1.0)
                   (fl- 1.0 (fl/ (fl* 2.0 py) th))
                   (fx+ i first))))

(define-fragment-shader (gfx-fragment px py id)
  ([atlas texture]
   [image texture]
   [records fx-buffer]
   [extras fx-buffer]
   [glyphs fx-buffer])
  (define (word k) (fx-ref records (fx+ (fx* id 8) k)))
  (define (pixels n) (fl/ (fixnum->flonum n) 256.0))
  (define (extra k) (fx-ref extras k))
  (define (clamp01 x) (flmax 0.0 (flmin 1.0 x)))
  ;; how far outside a rounded box the pixel's center is; inside, negative
  (define (box-distance x0 y0 x1 y1 r)
    (let* ([qx (fl- (flabs (fl- px (fl* 0.5 (fl+ x0 x1))))
                    (fl- (fl* 0.5 (fl- x1 x0)) r))]
           [qy (fl- (flabs (fl- py (fl* 0.5 (fl+ y0 y1))))
                    (fl- (fl* 0.5 (fl- y1 y0)) r))]
           [ox (flmax qx 0.0)]
           [oy (flmax qy 0.0)])
      (fl- (fl+ (flsqrt (fl+ (fl* ox ox) (fl* oy oy)))
                (flmin (flmax qx qy) 0.0))
           r)))
  ;; a channel of a color's word, 0 to 1
  (define (channel w shift)
    (fl/ (fixnum->flonum (fxand (fxsrl w shift) 255)) 255.0))
  ;; premultiplied: alpha is shift 24
  (define (premultiplied w shift)
    (if (fx= shift 24)
        (channel w 24)
        (fl* (channel w shift) (channel w 24))))
  (let* ([head (word 0)]
         [kind (fxand head 15)]
         [paint-kind (fxand (fxsrl head 4) 15)]
         [clip (fxsrl head 8)]
         [w1 (word 1)]
         [x0 (pixels (word 2))]
         [y0 (pixels (word 3))]
         [x1 (pixels (word 4))]
         [y1 (pixels (word 5))]
         [a (pixels (word 6))]
         [b (pixels (word 7))]
         [ipx (flonum->fixnum (flfloor px))]
         [ipy (flonum->fixnum (flfloor py))]
         [cover
          (if (fx= kind 0)
              ;; box: rect, round rect, circle; a line inside it if b
              (let ([d (box-distance x0 y0 x1 y1 a)])
                (clamp01
                 (fl- 0.5
                      (if (fl> b 0.0)
                          (fl- (flabs (fl+ d (fl* 0.5 b))) (fl* 0.5 b))
                          d))))
              (if (fx= kind 1)
                  ;; segment
                  (let* ([ax (fl- px x0)]
                         [ay (fl- py y0)]
                         [bx (fl- x1 x0)]
                         [by (fl- y1 y0)]
                         [len2 (fl+ (fl* bx bx) (fl* by by))]
                         [h (if (fl> len2 0.0)
                                (clamp01 (fl/ (fl+ (fl* ax bx) (fl* ay by))
                                              len2))
                                0.0)]
                         [dx (fl- ax (fl* bx h))]
                         [dy (fl- ay (fl* by h))])
                    (clamp01
                     (fl- 0.5 (fl- (flsqrt (fl+ (fl* dx dx) (fl* dy dy)))
                                   (fl* 0.5 a)))))
                  (if (fx= kind 2)
                      ;; polygon: distance to its edges, sign by crossings
                      (let ([o (word 6)] [n (word 7)])
                        (define (vx k) (pixels (extra (fx+ o (fx* 2 k)))))
                        (define (vy k)
                          (pixels (extra (fx+ o (fx+ 1 (fx* 2 k))))))
                        (define (edge2 k j)
                          (let* ([ex (fl- (vx j) (vx k))]
                                 [ey (fl- (vy j) (vy k))]
                                 [wx (fl- px (vx k))]
                                 [wy (fl- py (vy k))]
                                 [len (fl+ (fl* ex ex) (fl* ey ey))]
                                 [t (if (fl> len 0.0)
                                        (clamp01
                                         (fl/ (fl+ (fl* wx ex) (fl* wy ey))
                                              len))
                                        0.0)]
                                 [qx (fl- wx (fl* ex t))]
                                 [qy (fl- wy (fl* ey t))])
                            (fl+ (fl* qx qx) (fl* qy qy))))
                        (define (crosses? k j)
                          (let* ([ex (fl- (vx j) (vx k))]
                                 [ey (fl- (vy j) (vy k))]
                                 [wx (fl- px (vx k))]
                                 [wy (fl- py (vy k))]
                                 [c1 (fl>= py (vy k))]
                                 [c2 (fl< py (vy j))]
                                 [c3 (fl> (fl* ex wy) (fl* ey wx))])
                            (if c1
                                (and c2 c3)
                                (and (not c2) (not c3)))))
                        (clamp01
                         (fl- 0.5
                              (do-bounded 256
                                  ([k 0 (fx+ k 1)]
                                   [j (fx- n 1) k]
                                   [d2 1.0e12 (flmin d2 (edge2 k j))]
                                   [s 1.0 (if (crosses? k j) (fl- s) s)])
                                ((fx>= k n) (fl* s (flsqrt d2)))))))
                      (if (fx= kind 3)
                          ;; glyph: its place from the table
                          (let* ([row (fx* (word 4) 7)]
                                 [u (fx-ref glyphs row)]
                                 [v (fx-ref glyphs (fx+ row 1))]
                                 [gw (fx-ref glyphs (fx+ row 2))]
                                 [left (fx-ref glyphs (fx+ row 4))]
                                 [top (fx-ref glyphs (fx+ row 5))]
                                 [pen-x (word 2)]
                                 [pen-y (word 3)])
                            (if (fx= (word 6) 3)
                                (texture-ref
                                 atlas
                                 (fx+ u (fx- (fx- (fx- pen-y left) 1) ipy))
                                 (fx+ v (fx- ipx (fx- pen-x top)))
                                 0)
                                (texture-ref
                                 atlas
                                 (fx+ u (fx- ipx (fx+ pen-x left)))
                                 (fx+ v (fx- ipy (fx- pen-y top)))
                                 0)))
                          ;; shadow: fading out over its size
                          (let ([d (box-distance x0 y0 x1 y1 a)])
                            (clamp01 (fl- 1.0 (fl/ d (flmax b 1.0)))))))))]
         [clipping
          (if (fx= clip 0)
              1.0
              (clamp01
               (fl- 0.5
                    (flmax
                     (box-distance (pixels (extra clip))
                                   (pixels (extra (fx+ clip 1)))
                                   (pixels (extra (fx+ clip 2)))
                                   (pixels (extra (fx+ clip 3)))
                                   0.0)
                     (if (fx= (extra (fx+ clip 4)) 0)
                         -1.0
                         (box-distance (pixels (extra (fx+ clip 6)))
                                       (pixels (extra (fx+ clip 7)))
                                       (pixels (extra (fx+ clip 8)))
                                       (pixels (extra (fx+ clip 9)))
                                       (pixels (extra (fx+ clip 4)))))))))]
         [m (fl* cover clipping)]
         ;; a gradient: where the pixel falls between two of its colors
         [gradient? (fx= paint-kind 1)]
         [t (if gradient?
                (let ([ax (pixels (extra (fx+ w1 1)))]
                      [ay (pixels (extra (fx+ w1 2)))]
                      [bx (pixels (extra (fx+ w1 3)))]
                      [by (pixels (extra (fx+ w1 4)))])
                  (if (fx= (extra w1) 1)
                      (let ([dx (fl- px ax)] [dy (fl- py ay)])
                        (clamp01 (fl/ (flsqrt (fl+ (fl* dx dx) (fl* dy dy)))
                                      (flmax bx 1.0))))
                      (let* ([ex (fl- bx ax)]
                             [ey (fl- by ay)]
                             [len (flmax (fl+ (fl* ex ex) (fl* ey ey)) 1.0)])
                        (clamp01 (fl/ (fl+ (fl* (fl- px ax) ex)
                                           (fl* (fl- py ay) ey))
                                      len)))))
                0.0)]
         [stops (if gradient? (fx- (extra (fx+ w1 5)) 1) 0)]
         [place (fl* t (fixnum->flonum stops))]
         [low (flonum->fixnum place)]
         [low (if (fx>= low stops) (fx- stops 1) low)]
         [low (if (fx< low 0) 0 low)]
         [between (fl- place (fixnum->flonum low))]
         ;; less than a level either way, by the pixel: a slow gradient would
         ;; show its 8-bit steps as bands (interleaved gradient noise)
         [dither (if gradient?
                     (let* ([v (fl+ (fl* 0.06711056 px) (fl* 0.00583715 py))]
                            [f (fl* 52.9829189 (fl- v (flfloor v)))])
                       (fl/ (fl- (fl- f (flfloor f)) 0.5) 255.0))
                     0.0)]
         ;; a stipple: ink or paper, by its tile
         [solid-word
          (if (fx= paint-kind 2)
              (let* ([tu (extra w1)]
                     [tv (extra (fx+ w1 1))]
                     [tw (extra (fx+ w1 2))]
                     [th (extra (fx+ w1 3))])
                (if (fl> (texture-ref atlas
                                      (fx+ tu (fxmod ipx tw))
                                      (fx+ tv (fxmod ipy th))
                                      0)
                         0.5)
                    (extra (fx+ w1 4))
                    (extra (fx+ w1 5))))
              w1)]
         [image? (fx= paint-kind 3)]
         [iu (if image?
                 (flonum->fixnum
                  (fl/ (fl* (fl- (fixnum->flonum ipx) x0)
                            (fixnum->flonum (extra w1)))
                       (fl- x1 x0)))
                 0)]
         [iv (if image?
                 (flonum->fixnum
                  (fl/ (fl* (fl- (fixnum->flonum ipy) y0)
                            (fixnum->flonum (extra (fx+ w1 1))))
                       (fl- y1 y0)))
                 0)])
    (define (paint shift from-image)
      (fl* m
           (if image?
               from-image
               (if gradient?
                   (let ([c0 (premultiplied (extra (fx+ (fx+ w1 6) low))
                                            shift)]
                         [c1 (premultiplied
                              (extra (fx+ (fx+ w1 7) low)) shift)])
                     (fl+ (fl+ c0 (fl* between (fl- c1 c0)))
                          (if (fx= shift 24) 0.0 dither)))
                   (premultiplied solid-word shift)))))
    (emit-color
     (paint 16 (if image? (texture-ref image iu iv 0) 0.0))
     (paint 8 (if image? (texture-ref image iu iv 1) 0.0))
     (paint 0 (if image? (texture-ref image iu iv 2) 0.0))
     (paint 24 (if image? (texture-ref image iu iv 3) 0.0)))))

;; A reload may bring new shaders.
(gpu-forget-pipelines!)

;;; ------------------------------------------------------------------ frames

;; What's on its way up with a list: new atlas pieces, the glyph table if it
;; changed, and the images that have new pixels.
(define (rec-take-atlas-pieces!)
  (let ([p (reverse *atlas-pieces*)])
    (set! *atlas-pieces* '())
    p))

(define (rec-take-table!)
  (and *glyph-table-dirty?*
       (begin (set! *glyph-table-dirty?* #f) *glyph-table*)))

(define (rec-table-bytes) (* 4 glyph-row-words (+ *glyph-count* 1)))

;; The list written since rec-begin! goes to the screen. => #t if it got
;; there; #f if the screen had no room for it yet, and it should be tried
;; again.
(define (rec-present!)
  (rec-run-end!)
  (gpu-present-mode! (theme 'present-mode))
  (let ([table (rec-take-table!)]
        [pieces (rec-take-atlas-pieces!)]
        [runs (reverse *rec-runs*)]
        [preview *rec-preview*])
    (set! *rec-preview* #f)
    (gpu-frame! *rec-bytes* *rec-at* *rec-extras* (* 4 *rec-extra-at*)
                table (rec-table-bytes) pieces *rec-images* runs
                (and preview
                     (cons (car preview)
                           (rec-runs-upto runs (cdr preview)
                                          (car preview)))))))

;; With the next frame, its first count records drawn on image, as big as
;; the screen, for the Pipeline.
(defvar *rec-preview* #f)
(define (rec-preview! image count) (set! *rec-preview* (cons image count)))

;; The runs as far as record n, but those that show image, which is being
;; drawn on.
(define (rec-runs-upto runs n image)
  (let loop ([runs runs] [acc '()])
    (if (or (null? runs) (>= (caddr (car runs)) n))
        (reverse acc)
        (let ([run (car runs)])
          (loop (cdr runs)
                (if (eq? (cadr run) image)
                    acc
                    (cons (list (car run) (cadr run) (caddr run)
                                (min (cadddr run) (- n (caddr run))))
                          acc)))))))

;; What thunk draws, on an image pw × ph, scale times bigger, clear or black:
;; its pixels, row after row, premultiplied BGRA.
(define drawing->bytes
  (case-lambda
    [(pw ph scale thunk) (drawing->bytes pw ph scale thunk #t)]
    [(pw ph scale thunk clear?)
     (rec-begin! (rationalize (exact scale) 1/100000))
     (thunk)
     (rec-run-end!)
     (let ([table (rec-take-table!)]
           [pieces (rec-take-atlas-pieces!)])
       (gpu-drawing->bytes *rec-bytes* *rec-at*
                          *rec-extras* (* 4 *rec-extra-at*)
                          table (rec-table-bytes) pieces *rec-images*
                          (reverse *rec-runs*) pw ph clear?))]))
