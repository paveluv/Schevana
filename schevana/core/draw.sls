;;; (schevana core draw) — the drawing API apps use.
;;;
;;; A draw paints nothing: it writes flat records of whole numbers into a
;;; list, with no C, no allocation and no questions asked of a renderer; the
;;; GPU draws the list. Drawing is in logical pixels, and the window manager
;;; translates and clips to a window's content area before calling its draw
;;; handler:
;;;
;;;   (fill-box 10 10 100 40 'accent)
;;;   (draw-text 16 20 "hello" 'text 'mono)
;;;
;;; Colors are #xRRGGBB fixnums, theme keys ('accent), (alpha c 0.5),
;;; stipples, which are patterns used as colors (stipple, below), or
;;; gradients (linear-gradient, below).

(library (schevana core draw)
  (export
    pi *canvas-w* *canvas-h* *scale* *canvas-ratio* *canvas-pw* *canvas-ph*
    theme-changed! canvas-create-pixels! canvas-create! canvas-pixel-width
    canvas-pixel-height rgb alpha stipple stipple? linear-gradient
    radial-gradient color-rgba mix color-word rec-kind-polygon rec-kind-glyph
    rec-paint-gradient rec-paint-stipple rec-paint-image rec-gradient-radial
    rec-row-words rec-row-head rec-row-paint rec-row-x0 rec-row-y0 rec-row-x1
    rec-row-y1 rec-box-radius rec-box-line rec-segment-width rec-polygon-points
    rec-polygon-count rec-glyph-pen-x rec-glyph-pen-y rec-glyph-number
    rec-shadow-size gradient-row-kind gradient-row-x0 gradient-row-y0
    gradient-row-x1 gradient-row-y1 clip-row-words clip-row-x0 clip-row-y0
    clip-row-x1 clip-row-y1 clip-row-radius clip-row-parent clip-row-rx0
    clip-row-ry0 clip-row-rx1 clip-row-ry1 *rec-num* *rec-den* *rec-ox* *rec-oy*
    *rec-turn* *rec-labels* *rec-label-at* *rec-clip* *rec-cx0* *rec-cy0*
    *rec-cx1* *rec-cy1* rec-variant rec-begin! rec-runs rec-state-restore!
    record-list! show-list fill-box stroke-box fill-circle stroke-circle
    draw-line draw-polyline fill-polygon invert-box add-box draw-shadow
    draw-text draw-image define-paint fill-shader with-clip with-translation
    with-scale with-turn with-transpose with-label draw-scale gfx-fragments
    rec-present!
    rec-preview! rec-past! drawing->bytes-then drawing->bytes)
  (import (chezscheme)
          (only (schevana base) at-load clamp define-hook define-made
                define-state library-layer)
          (only (schevana shader) define-fragment-shader define-shader-constant
                define-shader-helpers define-shader-layout define-vertex-shader
                shader-make)
          (only (schevana core0) *core0-mode* core0-forked? core0-step!
                gpu-frame-number gpu-image-h gpu-image-levels gpu-image-w
                gpu-list-labels-set! gpu-list-recorded-set! gpu-list-took-set!
                gpu-publish!)
          (only (schevana recorder) gpu-list-runs rec-bytes-begin!
                rec-bytes-copies rec-count rec-drawing->bytes rec-earlier-add!
                rec-extra! rec-extra-at rec-extra-ref rec-extra-u32! rec-freeze!
                rec-lend! rec-list-begin! rec-list-end! rec-write!)
          (only (schevana core theme-table) *theme* theme theme-part
                theme-table-default!)
          (only (schevana core platform) now-ns)
          (only (schevana core processes) *profile-span* current-proc
                report-error! request-frame!)
          (only (schevana core gpu) gpu-ask! gpu-make-call gpu-publish
                gpu-take-asks!)
          (only (schevana core fonts) *atlas-pieces* *glyph-count* *glyph-table*
                *glyph-table-dirty?* *stipple-tiles* atlas-place! font
                font-advance font-ascent font-crisp? font-glyph font-glyph-pages
                font-ready get-font glyph-row-h glyph-row-left glyph-row-ref
                glyph-row-top glyph-row-u glyph-row-v glyph-row-w
                glyph-row-words))

  (library-layer core)

  (define-made pi (* 4 (atan 1)))

  (define-state *canvas-w* 0)    ; logical size (what apps see)
  (define-state *canvas-h* 0)
  (define-state *scale* 1.0)     ; logical -> pixel (HiDPI)
  (define-state *canvas-ratio* 1)   ; the same, exactly
  ;; pixel size of the screen
  (define-state *canvas-pw* 0)
  (define-state *canvas-ph* 0)

  ;; Called when anything in the look changes, to build the theme again.
  ;; (schevana core theme) sets it; with no theme it does nothing. It is
  ;; defined here because a canvas at another scale changes what a theme's
  ;; rules compute.
  (define-hook (theme-changed!) (void))

  ;; Makes a canvas of pw × ph pixels, drawn scale times bigger than the
  ;; logical pixels apps use; its logical size is the whole parts of
  ;; pw / scale and ph / scale.
  (define (canvas-create-pixels! pw ph scale)
    (let ([rescaled? (not (= (inexact scale) *scale*))])
      (set! *canvas-pw* pw)
      (set! *canvas-ph* ph)
      (set! *canvas-w* (exact (floor (/ pw scale))))
      (set! *canvas-h* (exact (floor (/ ph scale))))
      (set! *scale* (inexact scale))
      (set! *canvas-ratio* (rationalize (exact scale) 1/100000))
      ;; with no window, frames draw to a target this big
      (when (eq? *core0-mode* 'headless) (gpu-ask! (list 'target pw ph)))
      (request-frame!)
      (when rescaled? (theme-changed!))))

  ;; Makes a canvas of w × h logical pixels.
  (define (canvas-create! w h scale)
    (canvas-create-pixels! (exact (round (* w scale)))
                           (exact (round (* h scale)))
                           scale))

  (define (canvas-pixel-width) *canvas-pw*)
  (define (canvas-pixel-height) *canvas-ph*)

  ;;; ---------------------------------------------------------------- colors

  (define (rgb r g b) (fxior (fxsll r 16) (fxsll g 8) b))
  (define (alpha c a) (cons c a))

  ;; A pattern used as a color: rows of equal length, of #\# (ink) and
  ;; anything else (paper; a paper of #f is clear), each character a logical
  ;; pixel, tiled from the screen's device origin so that tiles line up
  ;; across windows, as Medley's textures do. It is plain data, so it saves
  ;; and prints.
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
                     [(k) (/ (length (filter (lambda (ch) (char=? ch #\#))
                                             cells))
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

  ;; Blends two colors: t=0 gives c1, t=1 gives c2.
  (define (mix c1 c2 t)
    (let-values ([(r1 g1 b1 a1) (color-rgba c1)]
                 [(r2 g2 b2 a2) (color-rgba c2)])
      (define (m a b) (exact (round (* 255 (+ a (* t (- b a)))))))
      (rgb (m r1 r2) (m g1 g2) (m b1 b2))))

  ;; Returns a color as a record's word: straight, with alpha in the top
  ;; byte. The GPU premultiplies.
  (define (color-word c)
    (cond
      [(fixnum? c) (fxior #xff000000 (fxand c #xffffff))]
      [(symbol? c) (color-word (theme c))]
      ;; a color under a flonum alpha: its word's alpha scaled, in flonums
      ;; that stay unboxed
      [(and (pair? c) (flonum? (cdr c)))
       (let ([w (color-word (car c))])
         (fxior (fxand w #xffffff)
                (fxsll (flonum->fixnum
                        (flround (fl* (fixnum->flonum (fxsrl w 24))
                                      (flmax 0.0 (flmin 1.0 (cdr c))))))
                       24)))]
      [else
       (let-values ([(r g b a) (color-rgba c)])
         (let ([byte (lambda (v) (exact (round (* 255 (clamp v 0.0 1.0)))))])
           (fxior (fxsll (byte a) 24) (fxsll (byte r) 16)
                  (fxsll (byte g) 8) (byte b))))]))

  ;; The font for faint text and for disabled text: the font itself (when
  ;; the setting is #f), or what a style's part makes of it (Genera, which
  ;; has no gray, sets its hints and what can't be used in italic).
  (at-load (theme-table-default! 'faint-text-font #f))
  (define (faint-font color f)
    (let ([make (and (memq color '(text-faint text-disabled))
                     (theme-part 'faint-text-font))])
      (if make (make f) f)))

  ;;; ---------------------------------------------------------------- records
  ;;; A record is eight 32-bit words, all whole numbers, since floats are
  ;;; what would allocate. The format is private to this file and its
  ;;; shaders.
  ;;;   0  kind (low 3 bits), crisp (rec-crisp-bit), paint kind (next 4),
  ;;;      clip (the rest)
  ;;;   1  paint: a color's word, or where its row is in the extras
  ;;;   2 to 5  x0 y0 x1 y1, in 1/256ths of a device pixel
  ;;;   6, 7  two more, by kind
  ;;; Kinds:
  ;;;   box      radius, line width (0: filled)
  ;;;   segment  width; words 2 to 5 are its ends; round ends
  ;;;   polygon  where its points are in the extras, how many; words 2 to 5
  ;;;            hold a box around them
  ;;;   glyph    pen and baseline, whole pixels; the glyph's number in word 4;
  ;;;            word 6 is rec-glyph-turned if turned a quarter counterclockwise
  ;;;   shadow   radius, size; the box casting it
  ;;; Paint kinds: solid; gradient, stipple and image, each with a row in the
  ;;; extras; and shader, a paint's, whose call is its run's. The extras also
  ;;; hold clips: what is drawn has to be inside both of a clip's boxes. The
  ;;; extras' word 0 is unused, so that clip 0 means no clip.

  (define-shader-constant rec-kind-box 0)
  (define-shader-constant rec-kind-segment 1)
  (define-shader-constant rec-kind-polygon 2)
  (define-shader-constant rec-kind-glyph 3)
  (define-shader-constant rec-kind-shadow 4)
  (define-shader-constant rec-paint-solid 0)
  (define-shader-constant rec-paint-gradient 1)
  (define-shader-constant rec-paint-stipple 2)
  (define-shader-constant rec-paint-image 3)
  (define-shader-constant rec-paint-shader 4)
  (define-shader-constant rec-glyph-turned 3)     ; a glyph's word 6
  (define-shader-constant rec-crisp-bit 8)        ; in a record's head
  (define-shader-constant rec-gradient-radial 1)  ; a gradient row's first word

  (define-shader-layout rec-row word (head paint x0 y0 x1 y1 a b))
  (define-shader-layout rec-box word (head paint x0 y0 x1 y1 radius line))
  (define-shader-layout rec-segment word (head paint x0 y0 x1 y1 width))
  (define-shader-layout rec-polygon word (head paint x0 y0 x1 y1 points count))
  (define-shader-layout rec-glyph word (head paint pen-x pen-y number pad turn))
  (define-shader-layout rec-shadow word (head paint x0 y0 x1 y1 radius size))
  ;; a radial one's center is x0 y0 and its radius x1; its stops' colors
  ;; start at color0
  (define-shader-layout gradient-row extra
    (kind x0 y0 x1 y1 stops color0 color1))
  (define-shader-layout stipple-row extra (u v w h ink paper))
  (define-shader-layout image-row extra (w h level gray))
  ;; its box, the radius of the rounded box it lies in, the clip around it,
  ;; and that rounded box
  (define-shader-layout clip-row extra
    (x0 y0 x1 y1 radius parent rx0 ry0 rx1 ry1))
  (define rec-most-points 256)

  ;; The bytes recorded into, records and extras, belong to the recorder,
  ;; sealed in (schevana recorder bytes): they are written only through
  ;; rec-write!, rec-extra! and rec-extra-u32!, and read through
  ;; rec-extra-ref, rec-extra-at and rec-count.
  ;; the transform: num/den device pixels per logical pixel, the origin in
  ;; 1/256ths of a device pixel, a turn, as cos and sin, or #f, and whether
  ;; x and y trade places (with-transpose)
  (define-state *rec-num* 1)
  (define-state *rec-den* 1)
  (define-state *rec-ox* 0)
  (define-state *rec-oy* 0)
  (define-state *rec-turn* #f)
  (define-state *rec-swap* #f)
  (define-state *rec-labels* (make-vector 256 #f))   ; (record label) ...
  (define-state *rec-label-at* 0)
  (define-state *rec-label* #f)
  ;; the clip: where its row is, 0 for none; its box, while there is one
  (define-state *rec-clip* 0)
  (define-state *rec-cx0* 0)
  (define-state *rec-cy0* 0)
  (define-state *rec-cx1* 0)
  (define-state *rec-cy1* 0)
  ;; the runs, newest first, each (mode image first count variant); and the
  ;; current run's mode, image, variant and first record. The runs of the
  ;; list recorded before are kept (*rec-runs-was*), and while the new runs
  ;; are the same they are used again: *rec-runs* holds only those made
  ;; since the first that differs, and *rec-runs-same* the old ones not yet
  ;; matched, or #f once one has differed.
  (define-state *rec-runs* '())
  (define-state *rec-runs-was* '())
  (define-state *rec-runs-same* '())
  (define-state *rec-mode* 0)
  (define-state *rec-image* #f)
  (define-state *rec-variant* 0)
  (define-state *rec-run-first* 0)
  ;; what the shaders' cost of a list adds up to as it is written: area in
  ;; pixels
  (define-state *rec-area* 0)

  ;; Returns which of the fragment shader's variants a record needs, by its
  ;; head: an index in gfx-fragments. A box or glyph in a solid color needs
  ;; the plain one; a segment or polygon, a shadow, or a paint (gradient,
  ;; stipple, image) needs the one with its code; a segment, polygon or
  ;; shadow in such a paint needs the full one. The vectors give the kinds
  ;; and the paints in their order.
  (define (rec-variant head)
    (let ([k (vector-ref '#(0 1 1 0 2) (fxand head 7))]
          [p (vector-ref '#(0 3 4 5 0) (fxand (fxsrl head 4) 15))])
      (cond [(fx= k 0) p] [(fx= p 0) k] [else 6])))

  (define (rec-put! w0 w1 x0 y0 x1 y1 a b)
    ;; a record that needs another variant starts a run
    (let ([v (rec-variant w0)])
      (unless (fx= v *rec-variant*)
        (rec-run-end!)
        (set! *rec-variant* v)))
    (rec-write! w0 w1 x0 y0 x1 y1 a b))

  ;; Starts the root's list at a scale of ratio device pixels per logical
  ;; pixel. A new list resets everything, so a draw that crashed leaves
  ;; nothing to unwind.
  (define (rec-begin! ratio)
    (rec-bytes-begin!)
    (set! *rec-num* (numerator ratio))
    (set! *rec-den* (denominator ratio))
    (set! *rec-ox* 0)
    (set! *rec-oy* 0)
    (set! *rec-turn* #f)
    (set! *rec-swap* #f)
    (set! *rec-clip* 0)
    (set! *rec-label-at* 0)
    (set! *rec-label* #f)
    (set! *rec-runs* '())
    (set! *rec-runs-same* *rec-runs-was*)
    (set! *rec-mode* 0)
    (set! *rec-image* #f)
    (set! *rec-variant* 0)
    (set! *rec-run-first* 0)
    (set! *rec-area* 0))

  ;; Whether the run recorded before at this place is the list of the
  ;; values e ..., each compared once, with nothing allocated.
  (define-syntax rec-run-is?
    (syntax-rules ()
      [(_ run) (null? run)]
      [(_ run e more ...)
       (let ([r run])
         (and (pair? r) (eqv? (car r) e) (rec-run-is? (cdr r) more ...)))]))

  ;; Ends the run so far here.
  (define (rec-run-end!)
    (let ([n (rec-count)])
      (when (fx> n *rec-run-first*)
        (let ([count (fx- n *rec-run-first*)])
          (if (and (pair? *rec-runs-same*)
                   (rec-run-is? (car *rec-runs-same*) *rec-mode* *rec-image*
                                *rec-run-first* count *rec-variant*))
              (set! *rec-runs-same* (cdr *rec-runs-same*))
              (rec-run-add! (list *rec-mode* *rec-image* *rec-run-first* count
                                  *rec-variant*))))
        (set! *rec-run-first* n))))

  ;; Adds a run that differs from the one recorded before at its place; the
  ;; runs that matched until then are copied in first.
  (define (rec-run-add! run)
    (when *rec-runs-same*
      (let copy ([was *rec-runs-was*])
        (unless (eq? was *rec-runs-same*)
          (set! *rec-runs* (cons (car was) *rec-runs*))
          (copy (cdr was))))
      (set! *rec-runs-same* #f))
    (set! *rec-runs* (cons run *rec-runs*)))

  ;; Ends the run so far and returns the runs recorded, in order: the same
  ;; list as last time when they are all the same. The next recording
  ;; starts from this list.
  (define (rec-runs)
    (rec-run-end!)
    (unless (null? *rec-runs-same*)
      (when *rec-runs-same*
        (rec-run-add! #f)
        (set! *rec-runs* (cdr *rec-runs*)))
      (set! *rec-runs-was* (reverse *rec-runs*))
      (set! *rec-runs* '())
      (set! *rec-runs-same* '()))
    *rec-runs-was*)

  (define (rec-run! mode image)
    (unless (and (eqv? mode *rec-mode*) (eq? image *rec-image*))
      (rec-run-end!)
      (set! *rec-mode* mode)
      (set! *rec-image* image)))

  ;; Restores the transform and clip as they were, given as values.
  (define (rec-state-restore! num den ox oy turn clip cx0 cy0 cx1 cy1)
    (set! *rec-num* num)
    (set! *rec-den* den)
    (set! *rec-ox* ox)
    (set! *rec-oy* oy)
    (set! *rec-turn* turn)
    (set! *rec-clip* clip)
    (set! *rec-cx0* cx0)
    (set! *rec-cy0* cy0)
    (set! *rec-cx1* cx1)
    (set! *rec-cy1* cy1)
    (rec-run! 0 #f))

  ;;; -- lists

  ;; Records what thunk draws into lst (gpu-list-new), in place of what lst
  ;; held, from lst's own origin and at the scale of the list being
  ;; recorded; a show-list of lst then draws it. The list being recorded
  ;; goes on afterwards as it was. While the profiler is on, lst keeps when
  ;; it was recorded and how long that took; with the profiler off, only
  ;; the pacer reads the clock. What the list nests in is kept aside in a
  ;; vector of its level's, made once (*rec-saves*: lists nest 64 deep at
  ;; most), and put back by a procedure of no closure, so a recording
  ;; allocates nothing of its own.
  (define-state *rec-saves* (make-vector 64 #f))
  (define-state *rec-depth* 0)

  ;; The state a list's recording keeps aside, from slot 4 of its level's
  ;; vector: (rec-kept rec-keep! s) keeps it, (rec-kept rec-put-back! s)
  ;; puts it back. Slots 0 to 3 hold lst, the recording it nests in, when
  ;; it began, and the level's own labels.
  (define-syntax rec-kept
    (syntax-rules ()
      [(_ op s)
       (op s 4 *rec-labels* *rec-label-at* *rec-label* *rec-runs* *rec-mode*
           *rec-image* *rec-variant* *rec-run-first* *rec-area* *rec-runs-was*
           *rec-runs-same* *rec-num* *rec-den* *rec-ox* *rec-oy* *rec-turn*
           *rec-clip* *rec-cx0* *rec-cy0* *rec-cx1* *rec-cy1*)]))
  (define-syntax rec-keep!
    (syntax-rules ()
      [(_ s i) (void)]
      [(_ s i v more ...)
       (begin (vector-set! s i v) (rec-keep! s (fx+ i 1) more ...))]))
  (define-syntax rec-put-back!
    (syntax-rules ()
      [(_ s i) (void)]
      [(_ s i v more ...)
       (begin (set! v (vector-ref s i)) (rec-put-back! s (fx+ i 1) more ...))]))

  ;; In a process, no slice of its engine ends inside a list's recording,
  ;; whose state is kept here, not in the continuation that a slice's end
  ;; leaves and its next slice enters again.
  (define (record-list! lst thunk)
    (if (current-proc)
        (with-interrupts-disabled (record-list-in! lst thunk))
        (record-list-in! lst thunk)))

  (define (record-list-in! lst thunk)
    (let ([d *rec-depth*])
      (let ([s (or (vector-ref *rec-saves* d)
                   (let ([s (make-vector 25 #f)])
                     (vector-set! *rec-saves* d s)
                     s))])
        (vector-set! s 0 lst)
        (vector-set! s 2 (and *profile-span* (now-ns)))
        (rec-kept rec-keep! s)
        (set! *rec-labels* (or (vector-ref s 3) (make-vector 16 #f)))
        (set! *rec-label-at* 0)
        (set! *rec-label* #f)
        (set! *rec-runs* '())
        (set! *rec-runs-was* (gpu-list-runs lst))
        (set! *rec-runs-same* *rec-runs-was*)
        (set! *rec-mode* 0)
        (set! *rec-image* #f)
        (set! *rec-variant* 0)
        (set! *rec-run-first* 0)
        (set! *rec-area* 0)
        (set! *rec-ox* 0)
        (set! *rec-oy* 0)
        (set! *rec-turn* #f)
        (set! *rec-swap* #f)
        (set! *rec-clip* 0)
        ;; its bytes, which are the recorder's, are written there
        (vector-set! s 1 (rec-list-begin! lst))
        (set! *rec-depth* (fx+ d 1))
        (dynamic-wind void thunk record-list-end!))))

  ;; Ends the innermost list being recorded: its runs end while they are
  ;; the ones being written, it keeps its labels (one shared vector when it
  ;; has none) and its times, and what it nests in goes on.
  (define (record-list-end!)
    (let* ([d (fx- *rec-depth* 1)] [s (vector-ref *rec-saves* d)]
           [lst (vector-ref s 0)] [t0 (vector-ref s 2)])
      (rec-list-end! lst (vector-ref s 1) (rec-runs))
      (gpu-list-labels-set! lst (if (fx= *rec-label-at* 0)
                                    '#()
                                    (vector-copy *rec-labels* 0
                                                 *rec-label-at*)))
      (when t0
        (let ([now (now-ns)])
          (gpu-list-recorded-set! lst now)
          (gpu-list-took-set! lst (- now t0))))
      (vector-set! s 3 *rec-labels*)
      (vector-set! s 0 #f)
      (rec-kept rec-put-back! s)
      (set! *rec-depth* d)))

  ;; Draws lst with its origin at (x, y), inside the clip. It adds no
  ;; record, only a run that shows lst, with how many labels came before it
  ;; (for (schevana kits inspect)). When lst moves, only this run changes;
  ;; lst isn't recorded again.
  (define (show-list lst x y)
    (rec-run-end!)
    (let* ([ox (fxsra (rec-snap (rec-device x *rec-ox*)) 8)]
           [oy (fxsra (rec-snap (rec-device y *rec-oy*)) 8)]
           [x0 (and (not (fx= *rec-clip* 0)) (fxsra *rec-cx0* 8))]
           [y0 (and x0 (fxsra *rec-cy0* 8))]
           [x1 (and x0 (fxsra *rec-cx1* 8))]
           [y1 (and x0 (fxsra *rec-cy1* 8))])
      (if (and (pair? *rec-runs-same*)
               (rec-run-is? (car *rec-runs-same*) 'show lst ox oy x0 y0 x1 y1
                            *rec-label-at*))
          (set! *rec-runs-same* (cdr *rec-runs-same*))
          (rec-run-add! (list 'show lst ox oy x0 y0 x1 y1 *rec-label-at*)))))

  ;;; -- the transform

  ;; Returns v, on an axis whose origin is o, in 1/256ths of a device pixel.
  (define (rec-device v o)
    (cond
      [(fixnum? v) (fx+ o (fxdiv (fx* (fx* v *rec-num*) 256) *rec-den*))]
      [(flonum? v)
       (fx+ o (flonum->fixnum
               (flfloor (fl+ 0.5 (fl/ (fl* v (fixnum->flonum
                                               (fx* *rec-num* 256)))
                                      (fixnum->flonum *rec-den*))))))]
      [else (fx+ o (exact (floor (+ 1/2 (/ (* (exact v) *rec-num* 256)
                                           *rec-den*)))))]))

  ;; A length in 1/256ths of a device pixel.
  (define (rec-length v) (rec-device v 0))

  ;; Rounds to the nearest whole pixel, half up (px's rule), so that no box
  ;; is ever blurred and neighbors share an edge with no gap.
  (define (rec-snap d) (fxand (fx+ d 128) -256))

  ;; Returns (x, y) under the turn, in 1/256ths of a device pixel, as a
  ;; pair.
  (define (rec-turned x y)
    (let* ([t *rec-turn*]
           [c (car t)]
           [s (cdr t)]
           [dx (* (inexact x) (/ *rec-num* *rec-den*) 256.0)]
           [dy (* (inexact y) (/ *rec-num* *rec-den*) 256.0)])
      (cons (+ *rec-ox* (exact (round (- (* c dx) (* s dy)))))
            (+ *rec-oy* (exact (round (+ (* s dx) (* c dy))))))))

  ;;; -- paints

  ;; rec-paint sets the paint's kind in *rec-paint-kind* and returns the
  ;; record's word 1.
  (define-state *rec-paint-kind* 0)
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
    (fxior kind (if (fx= kind rec-kind-glyph) 0 (rec-crisp))
           (fxsll *rec-paint-kind* 4) (fxsll *rec-clip* 8)))

  ;; A look drawn on a screen one bit deep (drawing-antialias #f, Genera's)
  ;; has its shapes crisp: each of its records says so (rec-crisp-bit), and
  ;; the shader then takes a pixel whole or not at all. The setting is read
  ;; again only when the theme in effect is another table.
  (at-load (theme-table-default! 'drawing-antialias #t))
  (define-state *rec-crisp-theme* #f)
  (define-state *rec-crisp* 0)
  (define (rec-crisp)
    (unless (eq? *theme* *rec-crisp-theme*)
      (set! *rec-crisp-theme* *theme*)
      (set! *rec-crisp* (if (theme 'drawing-antialias) 0 rec-crisp-bit)))
    *rec-crisp*)

  (define (rec-gradient c)
    (let* ([radial? (eq? (car c) 'radial-gradient)]
           [colors (list-tail c (if radial? 4 5))]
           [n (length colors)]
           [words (map color-word colors)]
           [row (rec-extra-at)])
      (rec-extra! (if radial? rec-gradient-radial 0))
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

  ;; A stipple's tile in the atlas, with its cells on the device pixels
  ;; where px's rule puts them at this scale (logical pixel
  ;; ceiling((d + 1/2)/s) - 1), in whole periods, so that it is exact
  ;; anywhere. The tile is coverage only: its colors stay in the record's
  ;; row, so that a change of palette needs no new tile. It is made once per
  ;; rows and scale.
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
           [row (rec-extra-at)])
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

  ;;; -- shapes

  ;; Whether nothing of this box can show through the clip.
  (define (rec-clipped? x0 y0 x1 y1)
    (and (not (fx= *rec-clip* 0))
         (or (fx>= x0 *rec-cx1*) (fx>= y0 *rec-cy1*)
             (fx<= x1 *rec-cx0*) (fx<= y1 *rec-cy0*))))

  ;; a corner radius of 0 makes a style square: everything it draws, an
  ;; app's drawing too
  (at-load (theme-table-default! 'corner-radius 9))
  ;; Returns a box's corner radius in 1/256ths of a device pixel: r, at
  ;; most half its shorter side. The sides are halved in those units, where
  ;; half an odd one is no fraction to allocate.
  (define (rec-radius r w h)
    (if (or (eqv? r 0) (<= (theme 'corner-radius) 0))
        0
        (fxmax 0 (fxmin (rec-length r) (fxsra (rec-length (abs w)) 1)
                        (fxsra (rec-length (abs h)) 1)))))

  (define (rec-box! x y w h color radius line)
    (cond
      [*rec-turn*   ; its corners trade places as points do
       (fill-polygon (list (cons x y) (cons (+ x w) y)
                           (cons (+ x w) (+ y h)) (cons x (+ y h)))
                     color)]
      [*rec-swap* (rec-box-at! y x h w color radius line)]
      [else (rec-box-at! x y w h color radius line)]))

  (define (rec-box-at! x y w h color radius line)
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
                    radius line)))))

  ;; (fill-box x y w h color [r]): a box, or with r a rounded one, up to a
  ;; pill.
  (define fill-box
    (case-lambda
      [(x y w h color) (rec-box! x y w h color 0 0)]
      [(x y w h color r) (rec-box! x y w h color (rec-radius r w h) 0)]))

  ;; The width of a line lw wide inside the box: a whole number of pixels,
  ;; at least one.
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
    (let* ([x (rec-device (if *rec-swap* cy cx) *rec-ox*)]
           [y (rec-device (if *rec-swap* cx cy) *rec-oy*)]
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
    (if *rec-swap* (rec-point-x* y x) (rec-point-x* x y)))
  (define (rec-point-y x y)
    (if *rec-swap* (rec-point-y* y x) (rec-point-y* x y)))
  (define (rec-point-x* x y)
    (if *rec-turn* (car (rec-turned x y)) (rec-device x *rec-ox*)))
  (define (rec-point-y* x y)
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

  ;; points: a list of (x . y). Each segment is a record, so a translucent
  ;; line darkens a little at its joints.
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

  ;; points: a list of (x . y). It is for icons, not thousands of points:
  ;; the shader's loop has a bound (rec-most-points), and the points past it
  ;; are dropped.
  (define (fill-polygon points color)
    (unless (null? points)
      (let* ([paint (rec-paint color)]
             [head (rec-head rec-kind-polygon)]
             [points (if (> (length points) rec-most-points)
                         (list-head points rec-most-points)
                         points)]
             [xs (map (lambda (p) (rec-point-x (car p) (cdr p))) points)]
             [ys (map (lambda (p) (rec-point-y (car p) (cdr p))) points)]
             [row (rec-extra-at)])
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

  ;; Adds color to each pixel: what goes past white in invert-box's sum.
  (define (add-box x y w h color)
    (rec-run! 3 #f)
    (rec-box! x y w h color 0 0)
    (rec-run! 0 #f))

  ;; The shadow of a box, which the shader fades out over size pixels; a
  ;; stack of translucent boxes would give the same line. Turned drawing has
  ;; no shadows.
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
  ;; size pixels, a third of size lower than the box.
  (define (draw-shadow x y w h r size)
    (when (> size 0)
      (rec-shadow! x (+ y (/ size 3)) w h r size (alpha #x000000 0.11))))

  ;;; -- text

  ;; Returns x in 1/256ths of a logical pixel: a pen's start.
  (define (rec-text-x x)
    (cond [(fixnum? x) (fxsll x 8)]
          [(flonum? x) (flonum->fixnum (flfloor (fl* x 256.0)))]
          [else (exact (floor (* (exact x) 256)))]))

  ;; Draws str with its top-left at (x, y). Returns the x where the text
  ;; ends, rounded up to a whole logical pixel as text-width is.
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
               (fxsra (fx+ pen 255) 8)
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
                       (rec-put! head paint base-x px g 0 rec-glyph-turned 0)
                       (let ([gh (glyph-row-ref g glyph-row-h)]
                             [top (glyph-row-ref g glyph-row-top)])
                         (unless (and (not (fx= *rec-clip* 0))
                                      (or (fx>= (fxsll px 8) *rec-cx1*)
                                          (fx>= (fxsll (fx- base-y top) 8)
                                                *rec-cy1*)
                                          (fx<= (fxsll (fx+ (fx- base-y top) gh)
                                                       8)
                                                *rec-cy0*)))
                           (rec-put! head paint px base-y g 0 0 0)))))
                 (loop (fx+ i 1) (fx+ pen (font-advance f ff c)))))))]))

  ;;; -- images

  ;; Returns the level of image's chain to show it at w × h device pixels:
  ;; the last one that is still at least that big. Two of its pixels blended
  ;; then cover more than a step between them, so that nothing is skipped.
  (define (rec-image-level image w h)
    (let loop ([level 0]
               [iw (quotient (gpu-image-w image) 2)]
               [ih (quotient (gpu-image-h image) 2)])
      (if (and (< (+ level 1) (gpu-image-levels image)) (>= iw w) (>= ih h))
          (loop (+ level 1) (quotient iw 2) (quotient ih 2))
          level)))

  ;; Draws an image on the GPU, scaled to w × h at (x, y). At its size or
  ;; bigger, each pixel is a sharp block; smaller, pixels are blended, from a
  ;; level of its chain if it has one. Given 'gray, its first channel shows
  ;; as gray, as a texture viewer shows an image of one channel.
  (define (draw-image image x y w h . gray)
    (let ([row (rec-extra-at)]
          [x0 (rec-snap (rec-device x *rec-ox*))]
          [y0 (rec-snap (rec-device y *rec-oy*))]
          [x1 (rec-snap (rec-device (+ x w) *rec-ox*))]
          [y1 (rec-snap (rec-device (+ y h) *rec-oy*))])
      (rec-extra! (gpu-image-w image))
      (rec-extra! (gpu-image-h image))
      (rec-extra! (rec-image-level image (fxsra (- x1 x0) 8)
                                   (fxsra (- y1 y0) 8)))
      (rec-extra! (if (null? gray) 0 1))
      (rec-run! 0 image)
      (set! *rec-paint-kind* rec-paint-image)
      (rec-put! (rec-head rec-kind-box) row x0 y0 x1 y1 0 0)
      (rec-run! 0 #f)))

  ;;; ---------------------------------------------------------------- paints
  ;;; A paint is a fragment shader that a person writes: its body runs for
  ;;; each pixel of the box it fills, with x and y from the box's corner in
  ;;; device pixels, and returns a color's word, #xAARRGGBB; 0 leaves the
  ;;; pixel alone. The wrapper around it does the rest: the clip and the
  ;;; blending. Its buffers and numbers can change with nothing else recorded
  ;;; again.

  (define-record-type gfx-paint
    (nongenerative schevana-gfx-paint-1)
    (fields shader params))   ; params as the paint was given them, colors too

  ;; A paint's source, as the compiler is given it, runs the core's clip and
  ;; then the body; these are the helpers it uses.
  (define-shader-helpers gfx-helpers
    (define (word k) (fx-ref records (fx+ (fx* id rec-row-words) k)))
    (define (extra k) (fx-ref extras k))
    (define (pixels n) (fl/ (fixnum->flonum n) 256.0))
    (define (clamp01 x) (flmax 0.0 (flmin 1.0 x)))
    (define (mixed a b t) (fl+ a (fl* t (fl- b a))))
    ;; a channel of a color's word, 0 to 1: times 1/255, since on Metal an
    ;; exact division by 255 took a third of a frame
    (define (channel w shift)
      (fl* (fixnum->flonum (fxand (fxsrl w shift) 255)) 0.00392156862745098))
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
    ;; how much of the pixel a clip's row leaves: its box, and the rounded
    ;; box that box lies in
    (define (clip-coverage clip)
      (if (fx= clip 0)
          1.0
          (clamp01
           (fl- 0.5
                (flmax
                 (box-distance (pixels (clip-row-x0 clip))
                               (pixels (clip-row-y0 clip))
                               (pixels (clip-row-x1 clip))
                               (pixels (clip-row-y1 clip))
                               0.0)
                 (if (fx= (clip-row-radius clip) 0)
                     -1.0
                     (box-distance (pixels (clip-row-rx0 clip))
                                   (pixels (clip-row-ry0 clip))
                                   (pixels (clip-row-rx1 clip))
                                   (pixels (clip-row-ry1 clip))
                                   (pixels (clip-row-radius clip))))))))))

  (define (gfx-paint-source x y forms)
    ;; the pixel in the list's own terms
    `((let ([px (fl- px (fixnum->flonum list-ox))]
            [py (fl- py (fixnum->flonum list-oy))])
        (use-shader-helpers gfx-helpers)
        (let* ([clip (fxsrl (rec-row-head) 8)]
               [m (clip-coverage clip)]
               [,x (fx- (flonum->fixnum (flfloor px)) (fxsra (rec-row-x0) 8))]
               [,y (fx- (flonum->fixnum (flfloor py)) (fxsra (rec-row-y0) 8))]
               [c (let () ,@forms)]
               [a (fl* m (channel c 24))])
          (emit-color (fl* a (channel c 16))
                      (fl* a (channel c 8))
                      (fl* a (channel c 0))
                      a)))))

  ;; What every paint is handed first: its list's records and extras, and
  ;; where the list is on the target, which the frame fills in.
  (define gfx-paint-hidden
    '((records fx-buffer)
      (extras fx-buffer)
      (list-ox fixnum)
      (list-oy fixnum)))

  ;; A paint's parameters as the compiler has them: to it, a color is a
  ;; whole number.
  (define (gfx-paint-plain params)
    (map (lambda (p) (if (eq? (cadr p) 'color) (list (car p) 'fixnum) p))
         params))

  ;; Makes the paint of a source, compiled where it is defined
  ;; (shader-make).
  (define (gfx-paint-of name x y params forms)
    (make-gfx-paint
     (shader-make name 'fragment '(px py id)
                  (append gfx-paint-hidden (gfx-paint-plain params))
                  (gfx-paint-source x y forms))
     params))

  (define-syntax define-paint
    (syntax-rules ()
      [(_ (name x y) params form ...)
       (define name (gfx-paint-of 'name 'x 'y 'params '(form ...)))]))

  ;; Fills a box with a paint, its arguments in its parameters' order: a
  ;; color as anywhere else (a theme key, say), whole numbers, floats,
  ;; buffers.
  (define (fill-shader x y w h paint . args)
    (let ([params (gfx-paint-params paint)])
      (rec-run! 0 (gpu-make-call
                   (gfx-paint-shader paint) '(0 0) (gfx-paint-plain params)
                   (map (lambda (p a)
                          (if (eq? (cadr p) 'color) (color-word a) a))
                        params args)))
      (let ([x0 (rec-snap (rec-device x *rec-ox*))]
            [y0 (rec-snap (rec-device y *rec-oy*))]
            [x1 (rec-snap (rec-device (+ x w) *rec-ox*))]
            [y1 (rec-snap (rec-device (+ y h) *rec-oy*))])
        (set! *rec-paint-kind* rec-paint-shader)
        (rec-put! (rec-head rec-kind-box) 0 x0 y0 x1 y1 0 0))
      (rec-run! 0 #f)))

  ;;; ---------------------------------------------------------------- state

  ;; Clips what is drawn next to a box, rounded if r: nested clips intersect
  ;; their boxes, and a clip with no radius keeps the rounded box it lies
  ;; in, so that a window's content stays inside the window's corners. Of
  ;; two rounded ones, the innermost holds.
  (define (rec-clip-enter! x y w h r)
    (if *rec-swap* (rec-clip-at! y x h w r) (rec-clip-at! x y w h r)))

  (define (rec-clip-at! x y w h r)
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
           [row (rec-extra-at)])
      (rec-extra! x0)
      (rec-extra! y0)
      (rec-extra! x1)
      (rec-extra! y1)
      (rec-extra! (if own? radius (rec-extra-ref clip clip-row-radius)))
      (rec-extra! clip)
      (rec-extra! (if own? ax (rec-extra-ref clip clip-row-rx0)))
      (rec-extra! (if own? ay (rec-extra-ref clip clip-row-ry0)))
      (rec-extra! (if own? bx (rec-extra-ref clip clip-row-rx1)))
      (rec-extra! (if own? by (rec-extra-ref clip clip-row-ry1)))
      (set! *rec-clip* row)
      (set! *rec-cx0* x0)
      (set! *rec-cy0* y0)
      (set! *rec-cx1* x1)
      (set! *rec-cy1* y1)))

  (define (rec-clip-leave!)
    (let ([clip (rec-extra-ref *rec-clip* clip-row-parent)])
      (set! *rec-clip* clip)
      (unless (fx= clip 0)
        (set! *rec-cx0* (rec-extra-ref clip clip-row-x0))
        (set! *rec-cy0* (rec-extra-ref clip clip-row-y0))
        (set! *rec-cx1* (rec-extra-ref clip clip-row-x1))
        (set! *rec-cy1* (rec-extra-ref clip clip-row-y1)))))

  ;; These are forms, not procedures taking a thunk: no closure per call,
  ;; and a draw that raises leaves nothing to unwind (record-safely and the
  ;; next rec-begin! reset the state).
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

  ;; What body draws is turned by angle radians, clockwise on the screen.
  ;; Lines and polygons turn any way; boxes become polygons; text turns only
  ;; by a quarter counterclockwise, which is all that is asked of it.
  (define-syntax with-turn
    (syntax-rules ()
      [(_ (angle) body ...)
       (let ([turn *rec-turn*])
         (rec-turn! angle)
         (let ([value (let () body ...)])
           (set! *rec-turn* turn)
           value))]))

  ;; What body draws trades x for y about the origin, as in a mirror along
  ;; the line x = y, so that a box stays a box: a style's vertical scroll
  ;; bar drawn across, its light still from the top left. Boxes, lines,
  ;; polygons, circles and clips trade; text, images and shadows are drawn
  ;; where they are.
  (define-syntax with-transpose
    (syntax-rules ()
      [(_ body ...)
       (let ([swap *rec-swap*])
         (set! *rec-swap* (not swap))
         (let ([value (let () body ...)])
           (set! *rec-swap* swap)
           value))]))

  (define (rec-turn! angle)
    (let ([a (inexact angle)])
      (set! *rec-turn* (cons (cos a) (sin a)))))

  ;; Names what is drawn inside, for the Pipeline: a label holds from its
  ;; first record until the next label.
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

  ;; Returns device pixels per logical pixel where drawing happens now: the
  ;; picker's miniature, say, is drawn scaled down.
  (define (draw-scale) (/ (inexact *rec-num*) *rec-den*))

  ;;; ---------------------------------------------------------------- shaders
  ;;; One shader draws everything, in order, in one instanced call, except
  ;;; where something forces a new run: an image, a paint, another blend, or
  ;;; a record that needs another variant of the fragment shader. The
  ;;; variants are made from one source, each with only some of its code
  ;;; (gfx-fragments), so that a pixel pays only for what its run draws.

  (define-vertex-shader (gfx-vertex v i)
    ([records fx-buffer]
     [extras fx-buffer]
     [glyphs fx-buffer]
     [tw flonum]
     [th flonum]
     [first fixnum]
     [ox fixnum]     ; where the list's origin is on the target: a list shown
     [oy fixnum])    ; by another is drawn where that one puts it
    (define (whole n) (fixnum->flonum n))
    (let ([id (fx+ i first)])
      (use-shader-helpers gfx-helpers)
      (let* ([head (rec-row-head)]
             [kind (fxand head 7)]
             [clip (fxsrl head 8)]
             [glyph? (fx= kind rec-kind-glyph)]
             [row (fx* (rec-glyph-number) glyph-row-words)]
             [gw (if glyph? (whole (glyph-row-w row)) 0.0)]
             [gh (if glyph? (whole (glyph-row-h row)) 0.0)]
             [gl (if glyph? (whole (glyph-row-left row)) 0.0)]
             [gt (if glyph? (whole (glyph-row-top row)) 0.0)]
             [pen-x (whole (rec-glyph-pen-x))]
             [pen-y (whole (rec-glyph-pen-y))]
             [turned? (fx= (rec-glyph-turn) rec-glyph-turned)]
             [grow (case kind
                     [(rec-kind-box)
                      (if (and (fx= (rec-box-radius) 0) (fx= (rec-box-line) 0))
                          0.0
                          1.0)]
                     [(rec-kind-segment)
                      (fl+ 1.0 (fl* 0.5 (pixels (rec-segment-width))))]
                     [(rec-kind-polygon) 1.0]
                     [else (fl+ 1.0 (pixels (rec-shadow-size)))])]
             [x0 (if glyph?
                     (if turned? (fl- pen-x gt) (fl+ pen-x gl))
                     (fl- (flmin (pixels (rec-row-x0)) (pixels (rec-row-x1)))
                          grow))]
             [y0 (if glyph?
                     (if turned? (fl- (fl- pen-y gl) gw) (fl- pen-y gt))
                     (fl- (flmin (pixels (rec-row-y0)) (pixels (rec-row-y1)))
                          grow))]
             [x1 (if glyph?
                     (if turned?
                         (fl+ (fl- pen-x gt) gh)
                         (fl+ (fl+ pen-x gl) gw))
                     (fl+ (flmax (pixels (rec-row-x0)) (pixels (rec-row-x1)))
                          grow))]
             [y1 (if glyph?
                     (if turned? (fl- pen-y gl) (fl+ (fl- pen-y gt) gh))
                     (fl+ (flmax (pixels (rec-row-y0)) (pixels (rec-row-y1)))
                          grow))]
             [clipped? (not (fx= clip 0))]
             [left (flfloor (if clipped?
                                (flmax x0 (pixels (clip-row-x0 clip)))
                                x0))]
             [top (flfloor (if clipped?
                               (flmax y0 (pixels (clip-row-y0 clip)))
                               y0))]
             [right (flmax left
                           (flceiling
                            (if clipped?
                                (flmin x1 (pixels (clip-row-x1 clip)))
                                x1)))]
             [bottom (flmax top
                            (flceiling
                             (if clipped?
                                 (flmin y1 (pixels (clip-row-y1 clip)))
                                 y1)))]
             [px (if (or (fx= v 1) (fx= v 3) (fx= v 5)) right left)]
             [py (if (or (fx= v 2) (fx= v 4) (fx= v 5)) bottom top)])
        (emit-position (fl- (fl/ (fl* 2.0 (fl+ px (whole ox))) tw) 1.0)
                       (fl- 1.0 (fl/ (fl* 2.0 (fl+ py (whole oy))) th))
                       id))))

  ;; How a record colors a pixel, with or without each feature: lines?
  ;; (segments and polygons), shadows?, gradients?, stipples? and images? are
  ;; #t or #f, known when the shader is compiled, so that a shader without a
  ;; feature has none of its code. Code that a pixel never runs still costs
  ;; it: on Metal, the image's code took a third of a frame, and the rest of
  ;; the code more than a third of what was left.
  (define-shader-helpers gfx-coloring
    ;; where p falls on an image n wide drawn from p0 to p1, in a level's
    ;; pixels: whole at their centers
    (define (image-at p p0 p1 n level)
      (fl- (fl/ (fl/ (fl* (fl- p p0) (fixnum->flonum n)) (fl- p1 p0))
                (fixnum->flonum (fxsll 1 level)))
           0.5))
    ;; the level's pixel after the one at b, or the last
    (define (image-next b n level)
      (flonum->fixnum
       (flmax 0.0 (flmin (fl+ (flfloor b) 1.0)
                         (fixnum->flonum (fx- (fxsrl n level) 1))))))
    ;; premultiplied; alpha is at shift 24
    (define (premultiplied w shift)
      (if (fx= shift 24)
          (channel w 24)
          (fl* (channel w shift) (channel w 24))))
    (define (pixel-color lines? shadows? gradients? stipples? images?)
      (let* ([head (rec-row-head)]
             [kind (fxand head 7)]
             [paint-kind (fxand (fxsrl head 4) 15)]
             [clip (fxsrl head 8)]
             [w1 (rec-row-paint)]
             [x0 (pixels (rec-row-x0))]
             [y0 (pixels (rec-row-y0))]
             [x1 (pixels (rec-row-x1))]
             [y1 (pixels (rec-row-y1))]
             ;; a box's radius and line, a segment's width, a shadow's radius
             ;; and size: read once, for all of them
             [a (pixels (rec-row-a))]
             [b (pixels (rec-row-b))]
             [ipx (flonum->fixnum (flfloor px))]
             [ipy (flonum->fixnum (flfloor py))]
             [cover
              (cond
                ;; box: a box, a rounded box or a circle, and a line inside
                ;; it if it has one
                [(fx= kind rec-kind-box)
                 (let* ([radius a]
                        [line b]
                        [d (box-distance x0 y0 x1 y1 radius)])
                   (clamp01
                    (fl- 0.5
                         (if (fl> line 0.0)
                             (fl- (flabs (fl+ d (fl* 0.5 line))) (fl* 0.5 line))
                             d))))]
                ;; segment
                [(and lines? (fx= kind rec-kind-segment))
                 (let* ([width a]
                        [ax (fl- px x0)]
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
                                  (fl* 0.5 width)))))]
                ;; polygon: the distance to its edges, its sign by crossings
                [(and lines? (fx= kind rec-kind-polygon))
                 (let ([o (rec-polygon-points)] [n (rec-polygon-count)])
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
                           ((fx>= k n) (fl* s (flsqrt d2)))))))]
                ;; glyph: its place from the table
                [(fx= kind rec-kind-glyph)
                 (let* ([row (fx* (rec-glyph-number) glyph-row-words)]
                        [u (glyph-row-u row)]
                        [v (glyph-row-v row)]
                        [gw (glyph-row-w row)]
                        [left (glyph-row-left row)]
                        [top (glyph-row-top row)]
                        [pen-x (rec-glyph-pen-x)]
                        [pen-y (rec-glyph-pen-y)])
                   (if (fx= (rec-glyph-turn) rec-glyph-turned)
                       (texture-ref
                        atlas
                        (fx+ u (fx- (fx- (fx- pen-y left) 1) ipy))
                        (fx+ v (fx- ipx (fx- pen-x top)))
                        0)
                       (texture-ref
                        atlas
                        (fx+ u (fx- ipx (fx+ pen-x left)))
                        (fx+ v (fx- ipy (fx- pen-y top)))
                        0)))]
                ;; shadow: fading out over its size
                [shadows?
                 (let* ([radius a]
                        [size b]
                        [d (box-distance x0 y0 x1 y1 radius)])
                   (clamp01 (fl- 1.0 (fl/ d (flmax size 1.0)))))]
                [else 0.0])]
             ;; a crisp shape covers a pixel wholly or not at all
             [m (fl* (if (fx= (fxand head rec-crisp-bit) 0)
                         cover
                         (if (fl>= cover 0.5) 1.0 0.0))
                     (clip-coverage clip))]
             ;; a gradient: where the pixel falls between two of its colors
             [gradient? (and gradients? (fx= paint-kind rec-paint-gradient))]
             [t (if gradient?
                    (let ([ax (pixels (gradient-row-x0 w1))]
                          [ay (pixels (gradient-row-y0 w1))]
                          [bx (pixels (gradient-row-x1 w1))]
                          [by (pixels (gradient-row-y1 w1))])
                      (if (fx= (gradient-row-kind w1) rec-gradient-radial)
                          (let ([dx (fl- px ax)] [dy (fl- py ay)])
                            (clamp01 (fl/ (flsqrt (fl+ (fl* dx dx) (fl* dy dy)))
                                          (flmax bx 1.0))))
                          (let* ([ex (fl- bx ax)]
                                 [ey (fl- by ay)]
                                 [len (flmax (fl+ (fl* ex ex) (fl* ey ey))
                                             1.0)])
                            (clamp01 (fl/ (fl+ (fl* (fl- px ax) ex)
                                               (fl* (fl- py ay) ey))
                                          len)))))
                    0.0)]
             [stops (if gradient? (fx- (gradient-row-stops w1) 1) 0)]
             [place (fl* t (fixnum->flonum stops))]
             [low (flonum->fixnum place)]
             [low (if (fx>= low stops) (fx- stops 1) low)]
             [low (if (fx< low 0) 0 low)]
             [between (fl- place (fixnum->flonum low))]
             ;; less than a level either way, by the screen's pixel, since a
             ;; slow gradient would show its 8-bit steps as bands
             ;; (interleaved gradient noise)
             [dither (if gradient?
                         (let* ([sx (fl+ px (fixnum->flonum ox))]
                                [sy (fl+ py (fixnum->flonum oy))]
                                [v (fl+ (fl* 0.06711056 sx)
                                        (fl* 0.00583715 sy))]
                                [f (fl* 52.9829189 (fl- v (flfloor v)))])
                           (fl* (fl- (fl- f (flfloor f)) 0.5)
                                0.00392156862745098))
                         0.0)]
             ;; a stipple: ink or paper, by its tile
             [solid-word
              (if (and stipples? (fx= paint-kind rec-paint-stipple))
                  (let* ([tu (stipple-row-u w1)]
                         [tv (stipple-row-v w1)]
                         [tw (stipple-row-w w1)]
                         [th (stipple-row-h w1)])
                    (if (fl> (texture-ref atlas
                                          ;; from the screen's origin
                                          (fx+ tu (fxmod (fx+ ipx ox) tw))
                                          (fx+ tv (fxmod (fx+ ipy oy) th))
                                          0)
                             0.5)
                        (stipple-row-ink w1)
                        (stipple-row-paper w1)))
                  w1)]
             [image? (and images? (fx= paint-kind rec-paint-image))]
             [iw (if image? (image-row-w w1) 0)]
             [ih (if image? (image-row-h w1) 0)]
             [level (if image? (image-row-level w1) 0)]
             [gray? (and image? (fx= (image-row-gray w1) 1))]
             [blend? (and image?
                          (or (fl< (fl- x1 x0) (fixnum->flonum iw))
                              (fl< (fl- y1 y0) (fixnum->flonum ih))))]
             ;; where the pixel's center falls, in the level's pixels' centers
             [bu (if blend? (image-at px x0 x1 iw level) 0.0)]
             [bv (if blend? (image-at py y0 y1 ih level) 0.0)]
             [fu (fl- bu (flfloor bu))]
             [fv (fl- bv (flfloor bv))]
             [iu (cond
                   [blend? (flonum->fixnum (flmax (flfloor bu) 0.0))]
                   [image? (flonum->fixnum
                            (fl/ (fl* (fl- (fixnum->flonum ipx) x0)
                                      (fixnum->flonum iw))
                                 (fl- x1 x0)))]
                   [else 0])]
             [iv (cond
                   [blend? (flonum->fixnum (flmax (flfloor bv) 0.0))]
                   [image? (flonum->fixnum
                            (fl/ (fl* (fl- (fixnum->flonum ipy) y0)
                                      (fixnum->flonum ih))
                                 (fl- y1 y0)))]
                   [else 0])]
             [iu1 (if blend? (image-next bu iw level) iu)]
             [iv1 (if blend? (image-next bv ih level) iv)])
        ;; a channel of the image at this pixel
        (define (image-channel c)
          (cond
            [blend?
             (mixed (mixed (texture-ref image iu iv c level)
                           (texture-ref image iu1 iv c level)
                           fu)
                    (mixed (texture-ref image iu iv1 c level)
                           (texture-ref image iu1 iv1 c level)
                           fu)
                    fv)]
            [image? (texture-ref image iu iv c 0)]
            [else 0.0]))
        (define (paint shift from-image)
          (fl* m
               (cond
                 [image? from-image]
                 [gradient?
                  (let ([c0 (premultiplied
                             (extra (fx+ (fx+ w1 gradient-row-color0) low))
                             shift)]
                        [c1 (premultiplied
                             (extra (fx+ (fx+ w1 gradient-row-color1) low))
                             shift)])
                    (fl+ (fl+ c0 (fl* between (fl- c1 c0)))
                         (if (fx= shift 24) 0.0 dither)))]
                 [else (premultiplied solid-word shift)])))
        (let ([red (image-channel 0)])
          (emit-color
           (paint 16 red)
           (paint 8 (if gray? red (image-channel 1)))
           (paint 0 (if gray? red (image-channel 2)))
           (paint 24 (image-channel 3)))))))

  ;; Defines a variant of the fragment shader, with each of its features on
  ;; or off.
  (define-syntax define-gfx-fragment
    (syntax-rules ()
      [(_ name lines? shadows? gradients? stipples? images?)
       (define-fragment-shader (name px py id)
         ([atlas texture]
          [image texture]
          [records fx-buffer]
          [extras fx-buffer]
          [glyphs fx-buffer]
          [ox fixnum]
          [oy fixnum])
         ;; the pixel in the list's own terms
         (let ([px (fl- px (fixnum->flonum ox))]
               [py (fl- py (fixnum->flonum oy))])
           (use-shader-helpers gfx-helpers)
           (use-shader-helpers gfx-coloring)
           (pixel-color lines? shadows? gradients? stipples? images?)))]))

  ;; The variants that draw a run, by what its records need (rec-variant):
  ;; boxes and glyphs in a solid color; the same with lines, shadows,
  ;; gradients, stipples or an image; and everything but images.
  (define-gfx-fragment gfx-fragment #f #f #f #f #f)
  (define-gfx-fragment gfx-line-fragment #t #f #f #f #f)
  (define-gfx-fragment gfx-shadow-fragment #f #t #f #f #f)
  (define-gfx-fragment gfx-gradient-fragment #f #f #t #f #f)
  (define-gfx-fragment gfx-stipple-fragment #f #f #f #t #f)
  (define-gfx-fragment gfx-image-fragment #f #f #f #f #t)
  (define-gfx-fragment gfx-full-fragment #t #t #t #t #f)

  ;; The variants by rec-variant's numbers: the shaders themselves, since
  ;; "/" has only the names the core's facade gives.
  (define-made gfx-fragments
    (vector gfx-fragment
            gfx-line-fragment
            gfx-shadow-fragment
            gfx-gradient-fragment
            gfx-stipple-fragment
            gfx-image-fragment
            gfx-full-fragment))

  ;; Core0 draws records with these, handed to it as they are (a reload may
  ;; bring new ones), never looked up by name. It gets a copy of its own,
  ;; which nothing in the world can change.
  (at-load
   (gpu-ask! (list 'shaders gfx-vertex (vector-copy gfx-fragments))))

  ;;; ---------------------------------------------------------------- frames

  ;; What goes up with a list: the new atlas pieces, and the glyph table if
  ;; it changed.
  (define (rec-take-atlas-pieces!)
    (let ([p (reverse *atlas-pieces*)])
      (set! *atlas-pieces* '())
      p))

  (define (rec-take-table!)
    (and *glyph-table-dirty?*
         (begin (set! *glyph-table-dirty?* #f) *glyph-table*)))

  (define (rec-table-bytes) (* 4 glyph-row-words (+ *glyph-count* 1)))

  ;; How a frame goes to the screen, and how many may be on their way.
  (at-load
   (theme-table-default! 'present-mode 'vsync)
   (theme-table-default! 'frames-in-flight 3))

  ;; Returns the list written since rec-begin! as the frame that core1 hands
  ;; core0, with the lists kept from earlier: the past one, and the
  ;; preview's, which the preview's procedure makes here, on core1, from the
  ;; frame just recorded.
  (define (rec-publish)
    (rec-freeze! (rec-runs))
    (let* ([preview *rec-preview*]
           [kept (and preview
                      (guard (c [#t (report-error! 'preview c) #f])
                        ((cdr preview))))])
      ;; the past one first; the recorder copies each as it is handed over
      (when *rec-past* (apply rec-earlier-add! *rec-past*))
      (when kept (apply rec-earlier-add! (car preview) kept))
      (set! *rec-preview* #f)
      (set! *rec-past* #f)
      ;; the recorder lends the frame its recording, the frozen one, and
      ;; those copies
      (let ([f (gpu-publish (rec-take-table!) (rec-table-bytes)
                            (rec-take-atlas-pieces!) (theme 'present-mode)
                            (theme 'frames-in-flight))])
        (rec-lend! f)
        f)))

  ;; Sends the list written since rec-begin! to the screen: core1 publishes
  ;; it, and core0 presents it, at once while core0 has no thread of its own
  ;; (render-frames-back! tells what came of it). Returns the frame's
  ;; number, which is also its report's (core0-frame-report).
  (define (rec-present!)
    (rec-run-end!)
    (let ([f (rec-publish)])
      (gpu-publish! f)
      (unless (core0-forked?) (core0-step!))
      (gpu-frame-number f)))

  ;; With the next frame, a list drawn on image too, as big as the screen,
  ;; for the Pipeline: what (list-of) returns as the frame is sent, made from
  ;; the frame just recorded, as (recs recs-n extras extras-n runs), which
  ;; can't show image; or #f for none.
  (define-state *rec-preview* #f)
  (define (rec-preview! image list-of)
    (set! *rec-preview* (cons image list-of)))

  ;; Ahead of the next frame, a list kept from earlier, drawn on image:
  ;; (image recs recs-n extras extras-n runs), with its images and paints as
  ;; they are now.
  (define-state *rec-past* #f)
  (define (rec-past! image recs recs-n extras extras-n runs)
    (set! *rec-past* (list image recs recs-n extras extras-n runs)))

  ;; drawing->bytes draws what thunk draws on an image of pw × ph, scale
  ;; times bigger, on clear or black, and returns its pixels, row after row,
  ;; in premultiplied BGRA. drawing->bytes-then does the same, but hands the
  ;; pixels to then on core1 once core0 has drawn them, with a frame soon,
  ;; so that nothing waits for them (.work/gpu-design.md 9.4); what was
  ;; recorded goes to core0 as its own copy.
  (define (drawing->bytes-then pw ph scale thunk clear? then)
    (rec-begin! (rationalize (exact scale) 1/100000))
    (thunk)
    (let-values ([(recs recs-n extras extras-n) (rec-bytes-copies)])
      (gpu-ask! (list 'read then recs recs-n extras extras-n (rec-take-table!)
                      (rec-table-bytes) (rec-take-atlas-pieces!) (rec-runs) pw
                      ph clear?)))
    (request-frame!))

  (define drawing->bytes
    (case-lambda
      [(pw ph scale thunk) (drawing->bytes pw ph scale thunk #t)]
      [(pw ph scale thunk clear?)
       (rec-begin! (rationalize (exact scale) 1/100000))
       (thunk)
       (let-values ([(jobs computes) (gpu-take-asks!)])
         (let ([table (rec-take-table!)]
               [pieces (rec-take-atlas-pieces!)])
           (rec-drawing->bytes jobs computes table (rec-table-bytes) pieces
                               (rec-runs) pw ph clear?)))])))
