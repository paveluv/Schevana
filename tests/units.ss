;;; tests/units.ss — the drawing layer piece by piece: the measuring
;;; context, pixmaps, Life's generations and grid, Boids' flocking,
;;; Springies' physics, and invalidation; the edit kit (editing, rows and
;;; their lazy layout), the
;;; widget kit's dates and layout, Tasks' own procedures, the window
;;; manager's surfaces and strips, and styles: derived ones, parts by
;;; name, a window's own; the shared drawing primitives and the behaviors
;;; a style chooses.
;;; Shadow tiles too.   ; shadow
;;;
;;;   scheme --script tests/units.ss [output-dir]
;;;
;;; Headless. output-dir only receives a scratch theme file.

(define *schevana-root*
  (let ([dir (path-parent (path-parent (car (command-line))))])
    (if (string=? dir "") "." dir)))

(load (string-append *schevana-root* "/load.ss"))

(define out-dir
  (if (pair? (command-line-arguments)) (car (command-line-arguments)) "."))

;; Never touch the user's real theme file, nor their apps' permissions.
(set! *theme-file-path* (string-append out-dir "/theme.ss"))
(when (file-exists? *theme-file-path*) (delete-file *theme-file-path*))
(set! *grant-file-path* (string-append out-dir "/permissions.ss"))
(when (file-exists? *grant-file-path*) (delete-file *grant-file-path*))

(define failures 0)

(define-syntax check
  (syntax-rules ()
    [(_ name expr)
     (let ([ok (guard (c [#t (printf "  error: ~a\n" (condition->string c))
                             #f])
                 expr)])
       (unless ok (set! failures (+ failures 1)))
       (printf "~a ~a\n" (if ok "ok  " "FAIL") name))]))

(define (steps n) (do ([i 0 (+ i 1)]) ((= i n)) (schevana-step! 0)))

(define (raises? thunk) (guard (c [#t #t]) (thunk) #f))

;;; ------------------------------------------------------------------ images

;; A fresh pw × ph image drawn by thunk with *cr* on it, scaled by s.
(define (image pw ph s thunk)
  (let* ([surface (cairo-image-surface-create CAIRO_FORMAT_ARGB32 pw ph)]
         [cr (cairo-create surface)])
    (cairo-scale cr s s)
    (fluid-let ([*cr* cr]) (thunk))
    (cairo-destroy cr)
    (cairo-surface-flush surface)
    surface))

(define (pixel-at surface x y)
  (foreign-ref 'unsigned-32 (cairo-image-surface-get-data surface)
               (+ (* y (cairo-image-surface-get-stride surface)) (* 4 x))))

;; The largest channel difference between two images of the same size,
;; outside the mask rects ((x0 y0 x1 y1) ...).
(define (max-diff a b . mask)
  (unless (and (= (cairo-image-surface-get-width a)
                  (cairo-image-surface-get-width b))
               (= (cairo-image-surface-get-height a)
                  (cairo-image-surface-get-height b)))
    (errorf 'max-diff "images differ in size"))
  (cairo-surface-flush a)
  (cairo-surface-flush b)
  (let ([pa (cairo-image-surface-get-data a)]
        [pb (cairo-image-surface-get-data b)]
        [sa (cairo-image-surface-get-stride a)]
        [sb (cairo-image-surface-get-stride b)]
        [w (cairo-image-surface-get-width a)]
        [h (cairo-image-surface-get-height a)])
    (define (masked? x y)
      (exists (lambda (r)
                (and (<= (car r) x) (< x (caddr r))
                     (<= (cadr r) y) (< y (cadddr r))))
              mask))
    (let row ([y 0] [worst 0])
      (cond
        [(= y h) worst]
        [(zero? (sdl-memcmp (+ pa (* y sa)) (+ pb (* y sb)) (* 4 w)))
         (row (+ y 1) worst)]
        [else
         (let col ([x 0] [worst worst])
           (if (= x w)
               (row (+ y 1) worst)
               (let ([p (foreign-ref 'unsigned-32 pa (+ (* y sa) (* 4 x)))]
                     [q (foreign-ref 'unsigned-32 pb (+ (* y sb) (* 4 x)))])
                 (col (+ x 1)
                      (if (or (fx= p q) (masked? x y))
                          worst
                          (fxmax worst (pixel-diff p q)))))))]))))

;; The largest difference of the four channels of two pixels.
(define (pixel-diff p q)
  (let loop ([k 0] [d 0])
    (if (fx= k 32)
        d
        (loop (fx+ k 8)
              (fxmax d (fxabs (fx- (fxand (fxsrl p k) 255)
                                   (fxand (fxsrl q k) 255))))))))

(define (report-worst worst where)
  (printf "  worst difference ~a~a\n"
          worst (if where (format " at ~s" where) "")))

(define (same-bytes? a b)
  (and (= (cairo-image-surface-get-width a) (cairo-image-surface-get-width b))
       (= (cairo-image-surface-get-height a) (cairo-image-surface-get-height b))
       (zero? (max-diff a b))))

;; The canvas's pixels, copied.
(define (canvas-bytes)
  (cairo-surface-flush *canvas*)
  (let* ([n (* (cairo-image-surface-get-stride *canvas*) (canvas-pixel-height))]
         [bv (make-immobile-bytevector n)])
    (sdl-memcpy (object->reference-address bv)
                (cairo-image-surface-get-data *canvas*)
                n)
    bv))

(define (cairo-matrix-xx cr)
  (cairo-get-matrix cr *scratch*)
  (foreign-ref 'double *scratch* 0))

;;; ------------------------------------------------------------------ boot

(schevana-boot! 'headless 1280 800)

;;; ------------------------------------------------------------------
;;; measuring context

;; What text measures with *cr* on the canvas itself, as before.
(define (measured-on-canvas thunk)
  (let ([cr (cairo-create *canvas*)])
    (cairo-scale cr *scale* *scale*)
    (let ([v (fluid-let ([*cr* cr]) (thunk))])
      (cairo-destroy cr)
      v)))

(define (measures-like-canvas?)
  (let ([measure (lambda ()
                   (list (text-width "Schevana λ" 'ui)
                         (text-width "(define x 1)" 'mono)
                         (font-metrics (make-font* "sans" 13))
                         (font-metrics (make-font* "monospace" 11 'bold))))])
    (equal? (measure) (measured-on-canvas measure))))

(check "before the first frame *cr* is the measuring context"
       (and (zero? *frame-ms*) (not (eqv? *measure-cr* 0))
            (eqv? *cr* *measure-cr*) (= (cairo-matrix-xx *cr*) *scale*)))
(check
 "text-width and font-metrics work before the first frame, as on the canvas"
 (and (> (text-width "Schevana" 'ui) 0) (> (font-line-height 'ui) 0)
      (measures-like-canvas?)))

(steps 2)

(define (stray-drawing!)
  (fill-rect 0 0 600 400 'red)
  (draw-text 20 20 "stray" 'text 'big)
  (draw-shadow 100 100 300 200 9 14)   ; shadow
  (pixmap-draw (make-pixmap 2 2 #xff0000) 10 10 50 50))

(check "stray drawing between frames leaves the canvas untouched"
       (let ([before (canvas-bytes)])
         (stray-drawing!)
         (bytevector=? before (canvas-bytes))))

(set-theme! 'scale 200)
(steps 1)
(check "after a scale change *cr* measures at the new scale"
       (and (= *scale* 2.0) (eqv? *cr* *measure-cr*)
            (= (cairo-matrix-xx *cr*) 2.0)))
(check "text-width and font-metrics work after a scale change, as on the canvas"
       (and (> (text-width "Schevana" 'ui) 0) (measures-like-canvas?)))
(check "stray drawing at 200% leaves the canvas untouched"
       (let ([before (canvas-bytes)])
         (stray-drawing!)
         (bytevector=? before (canvas-bytes))))
(set-theme! 'scale 0)
(steps 1)

(check "a canvas context left in *cr* (code from before a reload) is replaced"
       (begin
         (set! *cr* (cairo-create *canvas*))
         (canvas-create! 1280 800 *scale*)
         (and (eqv? *cr* *measure-cr*) (measures-like-canvas?))))
(steps 1)

;; Measuring never depends on *cr*. (Once the fonts were made again, the
;; first measurement of 'mono could happen in Settings' Genera preview,
;; drawn at half scale, and the REPL's characters overlapped from then on.)
;; mono's char width and text-widths in 'mono and Genera's label font when
;; first measured inside (measure-in measure), on a fresh context scaled
;; like the canvas.
(define (first-measured-in measure-in)
  (fonts-rescaled!)
  (let* ([img (cairo-image-surface-create CAIRO_FORMAT_ARGB32 400 300)]
         [cr (cairo-create img)])
    (cairo-scale cr *scale* *scale*)
    (let ([v (fluid-let ([*cr* cr])
               (measure-in
                (lambda ()
                  (list (font-char-width 'mono)
                        (text-width "(set-theme! 'accent #xff9e64)" 'mono)
                        (text-width "Dynamic Lisp Listener" 'ui-italic)))))])
      (cairo-destroy cr)
      (cairo-surface-destroy img)
      v)))

(check "the first measurement of a font, in a half-scale style preview, is \
        the canvas's (100, 125, 150, 200%)"
       (let ([results
              (map (lambda (s)
                     (canvas-create! 1280 800 s)
                     (let ([normal (first-measured-in
                                    (lambda (measure) (measure)))]
                           [preview (first-measured-in
                                     (lambda (measure)
                                       ;; its label is in 'ui-italic
                                       (draw-style-preview
                                        'genera 0 0 200 150 0.5)
                                       (call-with-scale 0.5 measure)))])
                       (list s normal preview)))
                   '(1 1.25 1.5 2))])
         (canvas-create! 1280 800 *host-scale*)
         (fonts-rescaled!)
         (printf "  ~s\n" results)
         (for-all (lambda (r) (equal? (cadr r) (caddr r))) results)))
(steps 1)

;;; ------------------------------------------------------------------
;;; host window

;; (w h scale ratio) -> window units: logical size × scale / pixel ratio.
(check
 "the host window opens at the logical size times the scale, in window units"
 (equal? (map (lambda (args)
                (call-with-values (lambda () (apply host-window-size args))
                                  list))
              '((1280 800 1 1) (1280 800 2 1) (1280 800 2 2) (1280 800 3/2 2)
                (1280 800 1 2) (1024 640 5/4 1) (1281 801 7/4 2)))
         '((1280 800) (2560 1600) (1280 800) (960 600) (640 400) (1280 800)
           (1121 701))))

;; shadow{

;;; ------------------------------------------------------------------
;;; shadow tiles

;; How many 'tiles images were drawn without looking up a tile.
(define untiled 0)

;; An image holding everything the shadow of the box can touch, over a
;; gradient that goes from opaque to translucent, with after-shadow drawn
;; on top. how is 'tiles (draw-shadow), 'stack (draw-shadow-directly,
;; layer by layer over the gradient) or 'stack-alone (the stack drawn on its
;; own, then composited once, as tiles are).
(define (shadow-image how s x y w h r size after-shadow)
  (let*-values ([(bx by bw bh) (shadow-bounds x y w h size)]
                [(pw ph) (values (+ (exact (ceiling (* s (+ bx bw)))) 3)
                                 (+ (exact (ceiling (* s (+ by bh)))) 3))])
    (let* ([alone (and (eq? how 'stack-alone)
                       (image pw ph s
                              (lambda ()
                                (draw-shadow-directly x y w h r size))))]
           [img (image pw ph s
                       (lambda ()
                         (fill-gradient 0 0 (+ bx bw 3) (+ by bh 3) #x3060a0
                                        (alpha #xe0c040 0.4) 'horizontal)
                         (case how
                           [(tiles)
                            (let ([lookups *shadow-tile-clock*])
                              (draw-shadow x y w h r size)
                              (when (= lookups *shadow-tile-clock*)
                                (set! untiled (+ untiled 1))))]
                           [(stack) (draw-shadow-directly x y w h r size)]
                           [else (cairo-save *cr*)
                                 (cairo-identity-matrix *cr*)
                                 (cairo-set-source-surface *cr* alone 0 0)
                                 (cairo-paint *cr*)
                                 (cairo-restore *cr*)])
                         (after-shadow)))])
      (when alone (cairo-surface-destroy alone))
      img)))

(define (shadow-diff how-a how-b s x y w h r size after-shadow)
  (let* ([a (shadow-image how-a s x y w h r size after-shadow)]
         [b (shadow-image how-b s x y w h r size after-shadow)]
         [d (max-diff a b)])
    (cairo-surface-destroy a)
    (cairo-surface-destroy b)
    d))

(define shadow-radii '(0 6 8 9))
(define shadow-sizes '(7 10 12 14 32))

;; Runs (test s x y w h r size) over radii, sizes, both boxes and the given
;; scales and sub-pixel phases (fractions of a logical pixel); returns the
;; worst result and the case that gave it.
(define (over-shadow-cases scales phases test)
  (let ([worst 0] [where #f])
    (for-each
     (lambda (s)
       (canvas-create! 1280 800 s)
       (for-each
        (lambda (r)
          (for-each
           (lambda (size)
             (for-each
              (lambda (wh)
                (for-each
                 (lambda (ph)
                   (let* ([x (+ size 2 (car ph))] [y (+ size 2 (cadr ph))]
                          [d (test s x y (car wh) (cadr wh) r size)])
                     (when (> d worst)
                       (set! worst d)
                       (set! where
                             (list 'scale s 'r r 'size size 'box wh 'at x y)))))
                 phases))
              (list (list (+ r r 5) (+ r r 5)) '(300 200))))
           shadow-sizes))
        shadow-radii))
     scales)
    (canvas-create! 1280 800 *host-scale*)
    (values worst where)))

;; Tiles composite the finished shadow once, so the reference is the stack
;; drawn on its own and then composited: any difference is geometry.
(check "shadow tiles match the stacked shadow (within 2 levels)"
       (let-values ([(worst where)
                     (over-shadow-cases
                      '(1 1.25 1.5 2) '((0 0) (0.25 0.6) (0.5 0.15) (0.77 0.9))
                      (lambda (s x y w h r size)
                        (shadow-diff 'tiles 'stack-alone
                                     s x y w h r size void)))])
         (report-worst worst where)
         (and (<= worst 2) (= untiled 0))))

(check "translucent boxes keep the shadow under them (within 2 levels)"
       (let-values ([(worst where)
                     (over-shadow-cases
                      '(1 1.25 1.5 2) '((0 0) (0.25 0.6) (0.5 0.15) (0.77 0.9))
                      (lambda (s x y w h r size)
                        (shadow-diff 'tiles 'stack-alone s x y w h r size
                                     (lambda ()
                                       (fill-round-rect
                                        x y w h r (alpha #xf0f0f0 0.35))))))])
         (report-worst worst where)
         (<= worst 2)))

;; Drawn layer by layer over a background, each faint layer of the stack
;; rounds to 8 bits by itself: up to half a level per layer, one layer per
;; 2 pixels of size.
(check "the stack drawn over a background differs only by its own rounding"
       (let ([raw 0])
         (let-values ([(excess where)
                       (over-shadow-cases
                        '(1 2) '((0 0) (0.25 0.6))
                        (lambda (s x y w h r size)
                          (let ([d (shadow-diff 'tiles 'stack
                                                s x y w h r size void)])
                            (set! raw (max raw d))
                            (- d (ceiling (/ size 4))))))])
           (printf "  worst difference ~a; worst beyond size/4 levels ~a~a\n"
                   raw excess (if where (format " at ~s" where) ""))
           (<= excess 2))))

(define (the-only-tile)
  (let ([vals (hashtable-values *shadow-tiles*)])
    (and (= 1 (vector-length vals)) (car (vector-ref vals 0)))))

(define (tile-surfaces t)
  (list (shadow-tile-template t) (shadow-tile-top t) (shadow-tile-bottom t)
        (shadow-tile-left t) (shadow-tile-right t) (shadow-tile-center t)))

(check "tiles do not depend on who built them"
       (begin
         (canvas-create! 1280 800 1.5)
         (flush-shadow-tiles!)
         (let* ([one (image 900 700 1.5
                            (lambda () (draw-shadow 40.3 30.7 200 120 8 14)))]
                [t1 (the-only-tile)])
           ;; same phases (whole multiples of 2 logical pixels at 150%),
           ;; another box size
           (let ([kept (map (lambda (s)
                              (image (cairo-image-surface-get-width s)
                                     (cairo-image-surface-get-height s) 1
                                     (lambda ()
                                       (cairo-set-source-surface *cr* s 0 0)
                                       (cairo-paint *cr*))))
                            (tile-surfaces t1))])
             (flush-shadow-tiles!)
             (let* ([two (image 900 700 1.5
                                (lambda ()
                                  (draw-shadow 140.3 230.7 300 180 8 14)))]
                    [t2 (the-only-tile)])
               (let ([ok (and t1 t2 (not (eq? t1 t2))
                              (for-all same-bytes? kept (tile-surfaces t2))
                              (for-all (lambda (f) (= (f t1) (f t2)))
                                       (list
                                        shadow-tile-tL0 shadow-tile-tcL
                                        shadow-tile-tcR shadow-tile-tR1
                                        shadow-tile-tT0 shadow-tile-tcT
                                        shadow-tile-tcB shadow-tile-tB1)))])
                 (for-each cairo-surface-destroy (cons* one two kept))
                 (canvas-create! 1280 800 *host-scale*)
                 ok))))))

(check "a shadow painted in parts equals one painted whole"
       (let* ([whole (image 400 300 1.25
                            (lambda () (draw-shadow 30.4 20.2 250 150 9 14)))]
              [parts
               (image 400 300 1.25
                      (lambda ()
                        (for-each
                         (lambda (r)
                           (call-with-clip (car r) (cadr r) (caddr r) (cadddr r)
                             (lambda () (draw-shadow 30.4 20.2 250 150 9 14))))
                         '((0 0 120 240) (120 0 200 100) (120 100 200 140)))))]
              [ok (same-bytes? whole parts)])
         (cairo-surface-destroy whole)
         (cairo-surface-destroy parts)
         ok))

(check "non-uniform transforms fall back to the stacked shadow, bit for bit"
       (let* ([draw (lambda (shadow)
                      (image 500 400 1
                             (lambda ()
                               (fill-gradient 0 0 500 400 #x3060a0 #xe0c040
                                              'horizontal)
                               (cairo-scale *cr* 0.5 1)
                               (shadow 60.3 40.6 300 200 8 14))))]
              [a (draw draw-shadow)] [b (draw draw-shadow-directly)]
              [ok (same-bytes? a b)])
         (cairo-surface-destroy a)
         (cairo-surface-destroy b)
         ok))

(check "uniform scales inside a frame (style previews) use tiles at that scale"
       (begin
         (flush-shadow-tiles!)
         (let ([a (image 400 300 1
                         (lambda ()
                           (call-with-scale 0.5
                             (lambda () (draw-shadow 60 40 300 200 8 14)))))])
           (cairo-surface-destroy a)
           (let ([t (the-only-tile)]
                 [keys (vector->list (hashtable-keys *shadow-tiles*))])
             (and t (= 1 (length keys)) (= 0.5 (list-ref (car keys) 4)))))))

(define (owned-tile-surfaces)
  (let-values ([(ks vs) (hashtable-entries *gfx-owned*)])
    (length (filter (lambda (tag) (eq? tag 'shadow-tile)) (vector->list vs)))))

(check "the tile cache stays within its budget"
       (begin
         (canvas-create! 1280 800 2)
         (flush-shadow-tiles!)
         (let ([s (image 1200 900 2 void)] [cr #f] [ok #t])
           (set! cr (cairo-create s))
           (cairo-scale cr 2 2)
           (fluid-let ([*cr* cr])
             (do ([i 0 (+ i 1)]) ((= i 300))
               ;; 300 different keys: phases (and so tiles) differ in x and y
               (draw-shadow (+ 40 (/ i 300)) (+ 40 (/ i 97)) 300 200 9 32)
               (unless (<= *shadow-tile-bytes* shadow-tile-budget)
                 (set! ok #f))))
           (cairo-destroy cr)
           (cairo-surface-destroy s)
           (let* ([n (hashtable-size *shadow-tiles*)]
                  [ok
                   (and ok (< 0 n 300)
                        (= (* 6 n) (owned-tile-surfaces))
                        (= *shadow-tile-bytes*
                           (apply +
                                  (map (lambda (e) (shadow-tile-bytes (car e)))
                                       (vector->list
                                        (hashtable-values *shadow-tiles*))))))])
             (printf "  ~a of 300 tiles kept, ~,1f MB\n"
                     n (/ *shadow-tile-bytes* 1048576.0))
             (canvas-create! 1280 800 *host-scale*)
             ok))))

;; A tree without shadows, reloaded live, resets without flushing the
;; tiles first, and leaves draw-shadow bound for whoever still calls it.
(define (one-tile-then-unflushed-reset)
  (flush-shadow-tiles!)
  (let* ([one (image 400 300 1 (lambda () (draw-shadow 30 20 250 150 9 14)))]
         [t (the-only-tile)])
    (fluid-let ([flush-shadow-tiles! void]) (free-owned-surfaces!))
    (values one t)))

(check "tiles freed by a reset that does not flush them are not drawn from"
       (let*-values ([(one t) (one-tile-then-unflushed-reset)]
                     [(two) (image 400 300 1
                                   (lambda ()
                                     (draw-shadow 30 20 250 150 9 14)))]
                     [(t2) (the-only-tile)])
         (let ([ok (and t t2 (not (eq? t t2))
                        (= *shadow-tile-bytes* (shadow-tile-bytes t2))
                        (same-bytes? one two))])
           (cairo-surface-destroy one)
           (cairo-surface-destroy two)
           ok)))

(check "nor freed again by a flush, when a new owned surface has their address"
       (let*-values ([(one t) (one-tile-then-unflushed-reset)]
                     [(a) (shadow-tile-template t)])
         (hashtable-set! *gfx-owned* a 'test)
         (flush-shadow-tiles!)
         (let ([ok (eq? 'test (hashtable-ref *gfx-owned* a #f))])
           (hashtable-delete! *gfx-owned* a)
           (cairo-surface-destroy one)
           ok)))

(check "flushing frees every tile surface"
       (begin (flush-shadow-tiles!)
              (and (= 0 (owned-tile-surfaces)) (= 0 *shadow-tile-bytes*)
                   (= 0 (hashtable-size *shadow-tiles*)))))
;; shadow}

;;; ------------------------------------------------------------------ pixmaps

(check "color->pixel"
       (and (= (color->pixel #x123456) #xff123456)
            (let ([p (color->pixel (alpha #xffffff 0.5))])
              (and (= (fxsrl p 24) #x80) (= (fxand (fxsrl p 16) 255) #x80)
                   (= (fxand (fxsrl p 8) 255) #x80) (= (fxand p 255) #x80)))
            (= (color->pixel (alpha #x000000 0)) 0)
            (let-values ([(r g b a) (color-rgba 'accent)])
              (= (color->pixel 'accent)
                 (fxior #xff000000 (fxsll (exact (round (* 255 r))) 16)
                        (fxsll (exact (round (* 255 g))) 8)
                        (exact (round (* 255 b))))))))

(check "pixmap set and ref round-trip"
       (let ([pm (make-pixmap 3 2)])
         (pixmap-set! pm 2 1 #x123456)
         (pixmap-set-pixel! pm 0 1 #x80402010)
         (and (= (pixmap-w pm) 3) (= (pixmap-h pm) 2)
              (= (pixmap-ref pm 2 1) #xff123456)
              (= (pixmap-ref pm 0 1) #x80402010)
              (= (pixmap-ref pm 0 0) 0)
              (= (bytevector-u32-native-ref (pixmap-bytes pm) (* 4 (+ 2 3)))
                 #xff123456)
              (raises? (lambda () (pixmap-ref pm 3 0)))
              (raises? (lambda () (pixmap-set! pm 0 -1 'red))))))

(check "pixmaps reject sizes that are not positive whole numbers"
       (and (raises? (lambda () (make-pixmap 0 4)))
            (raises? (lambda () (make-pixmap 2.5 4)))))

(check "make-pixmap and pixmap-fill! fill every pixel"
       (let ([pm (make-pixmap 7 5 #x00ff00)])
         (define (all? px)
           (for-all (lambda (i)
                      (= (bytevector-u32-native-ref (pixmap-bytes pm) (* 4 i))
                         px))
                    (iota 35)))
         (and (all? #xff00ff00)
              (begin (pixmap-fill! pm (alpha #xffffff 0.5))
                     (all? #x80808080)))))

(check "pixmap-load! copies raw pixels and rejects a wrong length"
       (let ([pm (make-pixmap 2 2)] [bv (make-bytevector 16 0)])
         (bytevector-u32-native-set! bv 12 #xff010203)
         (pixmap-load! pm bv)
         (bytevector-u32-native-set! bv 12 0)
         (and (= (pixmap-ref pm 1 1) #xff010203)
              (not (eq? (pixmap-bytes pm) bv))
              (raises? (lambda () (pixmap-load! pm (make-bytevector 12 0)))))))

(check "pixmap-from-bytevector wraps without copying"
       (let ([bv (make-bytevector 16 0)])
         (and (eq? (pixmap-bytes (pixmap-from-bytevector bv 2 2)) bv)
              (raises? (lambda () (pixmap-from-bytevector bv 3 2))))))

(check "pixmap-swap-bytes! installs a buffer and returns the old one"
       (let* ([pm (make-pixmap 2 2 #x0000ff)]
              [old (pixmap-bytes pm)]
              [new (make-pixmap-bytevector pm)])
         (bytevector-u32-native-set! new 0 #xffabcdef)
         (and (= (bytevector-length new) 16)
              (eq? (pixmap-swap-bytes! pm new) old)
              (eq? (pixmap-bytes pm) new)
              (= (pixmap-ref pm 0 0) #xffabcdef)
              (raises? (lambda ()
                         (pixmap-swap-bytes! pm (make-bytevector 8 0)))))))

;; Each device pixel of the drawn rect shows its pixmap pixel, and nothing
;; outside the rect changes.
(define (draws-nearest? s pm)
  (canvas-create! 1280 800 s)
  (let* ([before (image *canvas-pw* *canvas-ph* s
                        (lambda ()
                          (fill-gradient 0 0 300 300 #x204060 #x806040)))]
         [after (image *canvas-pw* *canvas-ph* s
                       (lambda ()
                         (fill-gradient 0 0 300 300 #x204060 #x806040)
                         (pixmap-draw pm 100 100 20 20)))]
         [x0 (exact (* s 100))] [x1 (exact (* s 120))]
         [ok (let loop ([y 0])
               (or (= y (exact (* s 300)))
                   (and (let col ([x 0])
                          (or (= x (exact (* s 300)))
                              (and (if (and (<= x0 x) (< x x1)
                                            (<= x0 y) (< y x1))
                                       (= (pixel-at after x y)
                                          (pixmap-ref
                                           pm
                                           (quotient (- x x0) (* s 10))
                                           (quotient (- y x0) (* s 10))))
                                       (= (pixel-at after x y)
                                          (pixel-at before x y)))
                                   (col (+ x 1)))))
                        (loop (+ y 1)))))])
    (cairo-surface-destroy before)
    (cairo-surface-destroy after)
    (canvas-create! 1280 800 *host-scale*)
    ok))

(define (quadrants bv)
  (let ([pm (pixmap-from-bytevector bv 2 2)])
    (for-each (lambda (i px) (pixmap-set-pixel! pm (mod i 2) (quotient i 2) px))
              '(0 1 2 3) '(#xffff0000 #xff00ff00 #xff0000ff #xff123456))
    pm))

(check "pixmap-draw is nearest-neighbor at 100%"
       (draws-nearest? 1 (quadrants (make-immobile-bytevector 16 0))))
(check "pixmap-draw is nearest-neighbor at 200%"
       (draws-nearest? 2 (quadrants (make-immobile-bytevector 16 0))))
(check "pixmap-draw works with an ordinary (movable) bytevector"
       (draws-nearest? 2 (quadrants (make-bytevector 16 0))))

;;; ------------------------------------------------------------------ Life

;; Life runs in its sandbox (services/grant.ss): its procedures, from
;; there.
(define life-env (env-environment (grant-env 'life)))
(define (life-row-pixels . args)
  (apply (top-level-value 'life-row-pixels life-env) args))
(define life-step-rows! (top-level-value 'life-step-rows! life-env))
(define (life-bar-height) ((top-level-value 'life-bar-height life-env)))

;; The next generation on a torus, the obvious way: the reference.
(define (life-reference grid cols rows)
  (let ([next (make-bytevector (* cols rows) 0)])
    (define (at x y)
      (bytevector-u8-ref grid (+ (mod x cols) (* (mod y rows) cols))))
    (do ([y 0 (+ y 1)]) ((= y rows) next)
      (do ([x 0 (+ x 1)]) ((= x cols))
        (let ([n (apply + (map (lambda (d) (at (+ x (car d)) (+ y (cdr d))))
                               '((-1 . -1) (0 . -1) (1 . -1)
                                 (-1 . 0) (1 . 0)
                                 (-1 . 1) (0 . 1) (1 . 1))))])
          (bytevector-u8-set! next (+ x (* y cols))
                              (if (or (= n 3) (and (= n 2) (= 1 (at x y))))
                                  1
                                  0)))))))

;; A grid from lines of text, # for a live cell.
(define (life-grid . lines)
  (let* ([cols (string-length (car lines))]
         [g (make-bytevector (* cols (length lines)) 0)])
    (for-each (lambda (line y)
                (for-each (lambda (x)
                            (when (char=? #\# (string-ref line x))
                              (bytevector-u8-set! g (+ x (* y cols)) 1)))
                          (iota cols)))
              lines (iota (length lines)))
    g))

(define (random-life-grid cols rows)
  (let ([g (make-bytevector (* cols rows) 0)])
    (do ([i 0 (+ i 1)]) ((= i (* cols rows)) g)
      (bytevector-u8-set! g i (if (< (random 1.0) 0.3) 1 0)))))

;; The grid moved by (dx, dy) on the torus.
(define (life-shift grid cols rows dx dy)
  (let ([g (make-bytevector (* cols rows) 0)])
    (do ([i 0 (+ i 1)]) ((= i (* cols rows)) g)
      (bytevector-u8-set! g
                          (+ (mod (+ (mod i cols) dx) cols)
                             (* cols (mod (+ (quotient i cols) dy) rows)))
                          (bytevector-u8-ref grid i)))))

;; k generations by the kernel, checking every generation against the
;; reference and every pixel against its cell.
(define (life-kernel-ok? grid cols rows k)
  (let ([row-px (life-row-pixels rows)]
        [dead (color->pixel 'bg-0)]
        [pix (make-bytevector (* 4 cols rows) 0)])
    (let loop ([i 0] [g grid])
      (or (= i k)
          (let ([next (make-bytevector (* cols rows) 0)])
            (life-step-rows! g next pix row-px dead cols rows 0 rows)
            (and (equal? next (life-reference g cols rows))
                 (for-all (lambda (c)
                            (= (bytevector-u32-native-ref pix (* 4 c))
                               (if (= 1 (bytevector-u8-ref next c))
                                   (fxvector-ref row-px (quotient c cols))
                                   dead)))
                          (iota (* cols rows)))
                 (loop (+ i 1) next)))))))

;; k generations by the kernel alone.
(define (life-kernel-run grid cols rows k)
  (let ([row-px (life-row-pixels rows)]
        [pix (make-bytevector (* 4 cols rows) 0)])
    (let loop ([i 0] [g grid])
      (if (= i k)
          g
          (let ([next (make-bytevector (* cols rows) 0)])
            (life-step-rows! g next pix row-px 0 cols rows 0 rows)
            (loop (+ i 1) next))))))

(let ([block (life-grid "......" ".##..." ".##..." "......" "......")]
      [blinker (life-grid "....." "....." ".###." "....." ".....")]
      [glider (life-grid ".#......" "..#....." "###....." "........"
                         "........" "........" "........" "........")])
  (check "Life's kernel: a block stays, a blinker turns"
         (and (equal? (life-kernel-run block 6 5 1) block)
              (equal? (life-kernel-run blinker 5 5 1)
                      (life-grid "....." "..#.." "..#.." "..#.." "....."))
              (equal? (life-kernel-run blinker 5 5 2) blinker)))
  (check "Life's kernel: a glider moves one cell down and right in 4 \
          generations, and around an 8 × 8 torus in 32"
         (and (equal? (life-kernel-run glider 8 8 4)
                      (life-shift glider 8 8 1 1))
              (equal? (life-kernel-run glider 8 8 12)
                      (life-shift glider 8 8 3 3))
              (equal? (life-kernel-run glider 8 8 32) glider))))

(random-seed 1717)
(check "Life's kernel equals the reference on random grids over 20 \
        generations, its pixels its cells (72 × 44, 37 × 23, 5 × 3, 3 × 3, \
        1 × 5, 4 × 1)"
       (for-all (lambda (size)
                  (life-kernel-ok? (random-life-grid (car size) (cadr size))
                                   (car size) (cadr size) 20))
                '((72 44) (37 23) (5 3) (3 3) (1 5) (4 1))))

(check "Life's kernel on rows [y0, y1) writes those rows of the generation \
        and nothing else"
       (let* ([g (random-life-grid 72 44)]
              [whole (life-reference g 72 44)]
              [part (make-bytevector (* 72 44) 9)]
              [pix (make-bytevector (* 4 72 44) 0)])
         (life-step-rows! g part pix (life-row-pixels 44) 0 72 44 10 27)
         (for-all (lambda (i)
                    (= (bytevector-u8-ref part i)
                       (if (<= (* 10 72) i (- (* 27 72) 1))
                           (bytevector-u8-ref whole i)
                           9)))
                  (iota (* 72 44)))))

(define (bytes-total) (+ (bytes-allocated) (bytes-deallocated)))

(let* ([g (random-life-grid 72 44)]
       [next (make-bytevector (* 72 44) 0)]
       [pix (make-bytevector (* 4 72 44) 0)]
       [row-px (life-row-pixels 44)]
       [dead (color->pixel 'bg-0)])
  (life-step-rows! g next pix row-px dead 72 44 0 44)
  (let ([b0 (bytes-total)])
    (do ([i 0 (fx+ i 1)]) ((fx= i 20))
      (life-step-rows! g next pix row-px dead 72 44 0 44))
    (let ([b (- (bytes-total) b0)])
      ;; an 8-argument + made each generation allocate about 300 KB
      (check (format "Life's kernel allocates nothing (~a bytes in 20 \
                      generations at 72 × 44)" b)
             (< b 1024)))))

;; Life's draw handler into a pw × ph image at scale s, and what it gave
;; draw-life-cells: (pixels cols rows cell ox oy).
(define (life-drawn win s)
  (let-values ([(cw ch) (window-content-size win)])
    (let* ([seen #f]
           [real (top-level-value 'draw-life-cells life-env)]
           [a (dynamic-wind
                (lambda ()
                  (set-top-level-value! 'draw-life-cells
                                        (lambda args
                                          (set! seen args)
                                          (apply real args))
                                        life-env))
                (lambda ()
                  (image (exact (ceiling (* s cw))) (exact (ceiling (* s ch)))
                         s
                         (lambda ()
                           ((hashtable-ref (window-handlers win) 'draw #f)
                            win cw ch))))
                (lambda ()
                  (set-top-level-value! 'draw-life-cells real life-env)))])
      (values a seen))))

;; The live cells a window shows: those whose pixel is not bg-0's.
(define (life-shown win)
  (let-values ([(a seen) (life-drawn win 1)])
    (cairo-surface-destroy a)
    (apply (lambda (pixels cols rows cell ox oy)
             (let ([g (make-bytevector (* cols rows) 0)]
                   [dead (color->pixel 'bg-0)])
               (do ([i 0 (+ i 1)]) ((= i (* cols rows)) g)
                 (unless (= dead
                            (pixmap-ref pixels (mod i cols) (quotient i cols)))
                   (bytevector-u8-set! g i 1)))))
           seen)))

(let ([win (life)])
  (window-call win 'key #\space '())   ; paused
  (let ([shown (life-shown win)])
    (window-call win 'key #\n '())
    (check "Life's n key shows the next generation"
           (and (> (apply + (bytevector->u8-list shown)) 100)
                (equal? (life-shown win) (life-reference shown 72 44)))))
  (window-call win 'key #\n '())
  (let ([b0 (bytes-total)])
    (do ([i 0 (+ i 1)]) ((= i 20)) (window-call win 'key #\n '()))
    (let ([kb (/ (- (bytes-total) b0) 20 1024.0)])
      ;; the handler's call and (invalidate! win) take about 2.4 KB of it
      (check (format "a step of Life (its n key) allocates under 8 KB: \
                      ~,1f KB (about 300 KB before its kernel)" kb)
             (< kb 8))))
  (close-window! win))

;; Life's draw handler into an image, next to the cells drawn the old way:
;; bg-0 everywhere, each live cell a rectangle. Compared above the status
;; bar.
(define (life-matches-rects? s content-w content-h)
  (canvas-create! 1280 800 s)
  (let ([win (life)])
    (resize-window! win content-w content-h)
    (let-values ([(cw ch) (window-content-size win)]
                 [(a seen) (life-drawn win s)])
      (let* ([pw (cairo-image-surface-get-width a)]
             [ph (cairo-image-surface-get-height a)]
             [dead (color->pixel 'bg-0)] [live 0]
             [b (apply (lambda (pixels cols rows cell ox oy)
                         (image pw ph s
                                (lambda ()
                                  (fill-rect 0 0 cw ch 'bg-0)
                                  (do ([y 0 (+ y 1)]) ((= y rows))
                                    (do ([x 0 (+ x 1)]) ((= x cols))
                                      (unless (= dead (pixmap-ref pixels x y))
                                        (set! live (+ live 1))
                                        (fill-rect
                                         (+ ox (* x cell) 1) (+ oy (* y cell) 1)
                                         (- cell 1) (- cell 1)
                                         (mix 'green 'cyan (/ y rows)))))))))
                       seen)]
             [grid-bottom (exact (floor (* s (- ch (life-bar-height)))))]
             [ok (and (> live 100)
                      (= 0 (max-diff a b (list 0 grid-bottom pw ph))))])
        (cairo-surface-destroy a)
        (cairo-surface-destroy b)
        (close-window! win)
        (canvas-create! 1280 800 *host-scale*)
        ok))))

(check "Life's pixmap drawing equals per-cell rectangles at 100%"
       (and (life-matches-rects? 1 720 466) (life-matches-rects? 1 803 515)))
(check "Life's pixmap drawing equals per-cell rectangles at 200%"
       (and (life-matches-rects? 2 720 466) (life-matches-rects? 2 803 515)))

;;; ------------------------------------------------------------------ Boids
;;; The Niva version's tests (tests/flockTest.niva in boids-niva), and the
;;; screen's rules.

;; Boids runs in its sandbox (services/grant.ss): its names, forwarded here.
(define boids-box (grant-env 'boids))

(check "Boids runs in its sandbox, holding its bundles, allowed by the table, \
        and its names stay there: vec is none of the world's; its rules \
        window is no app's"
       (let* ([held (environment-symbols (env-environment boids-box))]
              [world (environment-symbols *world-env*)]
              [win (boids)]
              [rw (find-window "Boids — Rules")]
              [ok (and (equal? (env-path boids-box) "/apps/boids")
                       (equal? (grant-requested 'boids)
                               '(window draw ui timers))
                       (null? (grant-undecided 'boids))
                       (memq 'ui-slider held) (not (memq 'notify held))
                       (memq 'vec held) (memq 'boids-step held)
                       (not (memq 'vec world)) (not (memq 'vec+ world))
                       (not (memq 'boids-step world))
                       (eq? (window-app win) 'boids)
                       (not (window-app rw)))])
         (close-window! win)
         ok))

;; For the checks below, here and not in the world they test: this suite's
;; own view of the sandbox.
(for-each (lambda (n)
            (define-top-level-syntax n
              (forwarder-to (datum->syntax (env-anchor boids-box) n))))
          '(make-vec vec? vec-x vec-y vec-dot make-boid boid? boid-position
            boid-velocity boid-neighbors boid-sees? boid-step-aside
            boid-back-off boids-step boids-demo boids-default-rules boids-rule
            boids-resize boids-scatter boids-step-on boids-random-rules
            boids-ranges boids-set-rule boids-slider-value boids-slider-t
            boids-draw-rules boids-max-count))

(define (test-boid x y vx vy) (make-boid (make-vec x y) (make-vec vx vy)))

(define (test-boid-numbers b)
  (let ([p (boid-position b)] [v (boid-velocity b)])
    (list (vec-x p) (vec-y p) (vec-x v) (vec-y v))))

;; To the last digit, so any change to the rules shows. They are the Niva
;; version's numbers: the same flonum operations, in the same order.
(check "Boids: the demo's first step is the Niva version's"
       (equal? (map test-boid-numbers
                    (boids-step boids-demo boids-default-rules))
               '((0.9869999999999999 0.054 0.9869999999999999 0.054)
                 (1.0 2.002 0.0 1.002)
                 (3.003 0.999 1.003 0.999))))

(check "Boids: a step leaves the flock it steps as it was"
       (let ([before (map test-boid-numbers boids-demo)])
         (boids-step boids-demo boids-default-rules)
         (equal? (map test-boid-numbers boids-demo) before)))

(check "Boids: a boid is not its own neighbor"
       (let ([b (test-boid 0.0 0.0 1.0 0.0)])
         (null? (boid-neighbors b (list b) 50.0 360.0))))

;; Heading right, with one boid ahead, one to the side and one behind.
(check "Boids: what the view angle lets a boid see"
       (let ([b (test-boid 0.0 0.0 1.0 0.0)]
             [ahead (test-boid 3.0 0.0 1.0 0.0)]
             [side (test-boid 0.0 3.0 1.0 0.0)]
             [behind (test-boid -3.0 0.0 1.0 0.0)])
         (and (boid-sees? b ahead 180.0)
              (not (boid-sees? b side 180.0))
              (not (boid-sees? b behind 180.0))
              (boid-sees? b side 270.0)
              (not (boid-sees? b behind 270.0))
              (boid-sees? b behind 360.0)
              (boid-sees? b ahead 10.0))))

;; Heading right: of these, only the boid close and straight ahead.
(check "Boids: blockers are close and ahead"
       (let* ([b (test-boid 0.0 0.0 1.0 0.0)]
              [ahead (test-boid 10.0 0.0 1.0 0.0)]
              [flock (list b ahead
                           (test-boid 0.0 10.0 1.0 0.0)     ; to the side
                           (test-boid -10.0 0.0 1.0 0.0)    ; behind
                           (test-boid 50.0 0.0 1.0 0.0))])  ; too far
         (equal? (boid-neighbors b flock 40.0 90.0) (list ahead))))

;; One unit sideways, and one unit back. Heading a little upward, the
;; sideways step goes up too.
(check "Boids: clear view steps aside, back off steps back"
       (let ([b (test-boid 0.0 0.0 1.0 0.0)]
             [climbing (test-boid 0.0 0.0 1.0 0.2)]
             [ahead (list (test-boid 10.0 0.0 1.0 0.0))])
         (let ([numbers (lambda (v) (list (vec-x v) (vec-y v)))])
           (and (equal? (numbers (boid-step-aside b ahead)) '(0.0 -1.0))
                (equal? (numbers (boid-back-off b ahead)) '(-1.0 0.0))
                (> (vec-y (boid-step-aside climbing ahead)) 0.0)))))

(check "Boids: resizing a flock keeps the boids already there"
       (let ([fewer (boids-resize boids-demo 2 100 100)]
             [more (boids-resize boids-demo 5 100 100)])
         (and (= (length fewer) 2) (= (length more) 5)
              (equal? fewer (list-head boids-demo 2))
              (equal? (list-head more 3) boids-demo)
              (equal? (boids-resize boids-demo 3 100 100) boids-demo))))

;; 50 frames of 150 boids.
(check "Boids: a frame keeps every boid on screen, within the speed limits"
       (let ([lo (boids-rule boids-default-rules 'min-speed)]
             [hi (boids-rule boids-default-rules 'max-speed)])
         (let loop ([flock (boids-scatter 150 900 600)] [i 0])
           (or (= i 50)
               (let ([next (boids-step-on flock boids-default-rules 900 600)])
                 (and (for-all
                       (lambda (b)
                         (let* ([p (boid-position b)] [v (boid-velocity b)]
                                [s (sqrt (vec-dot v v))])
                           (and (<= 0.0 (vec-x p) 900.0)
                                (<= 0.0 (vec-y p) 600.0)
                                (<= (- lo 1e-9) s (+ hi 1e-9)))))
                       next)
                      (loop next (+ i 1))))))))

;; The record types are nongenerative: loading the file again keeps them,
;; so a flock in flight still works with the new procedures.
(check "Boids: boids made before the file loads again still work after"
       (let ([b (car boids-demo)])
         (load-source "apps/boids.ss")
         (and (boid? b) (vec? (boid-position b))
              (= (length (boids-step (list b) boids-default-rules)) 1))))

(check "Boids: random rules are the rules, each within its range"
       (let loop ([i 0])
         (or (= i 500)
             (let ([rules (boids-random-rules)])
               (and (equal? (plist-keys rules)
                            (plist-keys boids-default-rules))
                    (for-all (lambda (range)
                               (<= (cadr range) (boids-rule rules (car range))
                                   (caddr range)))
                             boids-ranges)
                    (<= (boids-rule rules 'min-speed)
                        (boids-rule rules 'max-speed))
                    (loop (+ i 1)))))))

;; The keys, through the window's own handler. A clock moved a second on
;; lets a tick step whether or not the last one was long ago.
(let ([win (boids)])
  (define (key! k) (window-call win 'key k '()))
  (define (flock) (window-ref win 'flock))
  (define (tick-later!)
    (fluid-let ([now-ms (let ([t (now-ms)]) (lambda () (+ t 1000)))])
      (steps 1)))
  (check "Boids: R picks random rules, D the defaults again"
         (begin
           (key! #\r)
           (and (not (equal? (window-ref win 'rules) boids-default-rules))
                (begin (key! #\d)
                       (eq? (window-ref win 'rules) boids-default-rules)))))
  (check "Boids: S scatters as many boids anew"
         (let ([before (flock)])
           (key! #\s)
           (and (= (length (flock)) (length before))
                (not (exists eq? (flock) before)))))
  (check "Boids: Space holds the flock still, and again sets it going"
         (let ([before (begin (key! #\space) (flock))])
           (tick-later!)
           (let ([held? (eq? (flock) before)])
             (key! #\space)
             (tick-later!)
             (and held? (not (eq? (flock) before))))))
  (close-window! win))

(check "Boids: setting a rule keeps the others, and their order"
       (let ([rules (boids-set-rule boids-default-rules 'view-angle 270.0)])
         (and (= (boids-rule rules 'view-angle) 270.0)
              (equal? (plist-keys rules) (plist-keys boids-default-rules))
              (= (boids-rule rules 'cohesion)
                 (boids-rule boids-default-rules 'cohesion)))))

(check "Boids: min and max speed can't cross; the one set pushes the other"
       (let ([faster (boids-set-rule boids-default-rules 'min-speed 4.5)]
             [slower (boids-set-rule boids-default-rules 'max-speed 0.6)])
         (and (= (boids-rule faster 'max-speed) 4.5)
              (= (boids-rule slower 'min-speed) 0.6)
              (= (boids-rule (boids-set-rule boids-default-rules
                                             'min-speed 2.0)
                             'max-speed)
                 4.0))))

(check "Boids: a weight's slider is a cube, the others straight"
       (let ([cohesion (assq 'cohesion boids-ranges)]
             [radius (assq 'cohesion-radius boids-ranges)])
         (and (< (abs (- (boids-slider-value cohesion 0.5) 0.025)) 1e-12)
              (< (abs (- (boids-slider-t cohesion 0.025) 0.5)) 1e-12)
              (= (boids-slider-value radius 0.5) 100.0)
              (= (boids-slider-t radius 100.0) 0.5))))

;; The rules window, opened with the flock, where both fit.
(let* ([win (parameterize ([new-window-position '(40 . 60)]) (boids))]
       [rules-win (lambda () (find-window "Boids — Rules"))]
       [press! (lambda (rw id)   ; the middle of the widget id
                 (let ([r (ui-find (window-ref rw 'ui) id)])
                   (let ([x (+ (ui-region-x r) (/ (ui-region-w r) 2))]
                         [y (+ (ui-region-y r) (/ (ui-region-h r) 2))])
                     (window-call rw 'mouse-down x y 'left 1)
                     (window-call rw 'mouse-up x y 'left))))])
  (render-frame!)
  (check "Boids: the rules window opens beside the flock, which has the keys"
         (let ([rw (rules-win)])
           (and rw (eq? (focused-window) win)
                (= (window-x rw) (+ (window-x win) (window-w win) 12))
                (= (window-y rw) (window-y win)))))
  (check "Boids: the rules window has room for all its rows"
         (let-values ([(w h) (window-content-size (rules-win))])
           (let* ([bottom #f]
                  [s (image (exact (ceiling w)) (exact (ceiling h)) 1
                            (lambda ()
                              (let ([ui (make-ui)])
                                (ui-begin! ui)
                                (set! bottom (boids-draw-rules ui win w)))))])
             (cairo-surface-destroy s)
             (<= bottom h))))
  (check "Boids: the rules window paints the style's page under its rows"
         (let*-values ([(rw) (rules-win)] [(w h) (window-content-size rw)])
           (let* ([surfaces '()]
                  [real ui-draw-surface]
                  [s (fluid-let ([ui-draw-surface
                                  (lambda (x y w h flags)
                                    (set! surfaces (cons flags surfaces))
                                    (real x y w h flags))])
                       (image (exact (ceiling w)) (exact (ceiling h)) 1
                              (lambda ()
                                (parameterize ([current-window rw])
                                  ((hashtable-ref (window-handlers rw) 'draw #f)
                                   rw w h)))))])
             (cairo-surface-destroy s)
             (and (member '(page) surfaces) #t))))
  (check "Boids: its slider sets the flock's rule, on a weight's cube"
         (begin
           (press! (rules-win) 'cohesion)
           (< (abs (- (boids-rule (window-ref win 'rules) 'cohesion) 0.025))
              1e-9)))
  (check "Boids: its buttons and keys act on the flock"
         (begin
           (press! (rules-win) 'randomize)
           (and (not (eq? (window-ref win 'rules) boids-default-rules))
                (begin (window-call (rules-win) 'key #\d '())
                       (eq? (window-ref win 'rules) boids-default-rules)))))
  (check "Boids: its count slider resizes the flock"
         (begin
           (press! (rules-win) 'count)
           (= (length (window-ref win 'flock))
              (round (+ 10 (/ (- boids-max-count 10) 2))))))
  (check "Boids: H closes the rules window and opens it again"
         (begin
           (window-call win 'key #\h '())
           (and (not (rules-win))
                (begin (window-call win 'key #\h '())
                       (rules-win) #t))))
  ;; as when fonts grow in Settings: the rows ask for more room
  (check "Boids: the rules window grows when its rows need more, on screen"
         (let-values ([(w h) (window-content-size (rules-win))]
                      [(dx dy dw dh) (desktop-rect)])
           (define (grown-by! dw)
             (let* ([env (env-environment boids-box)]
                    [real (top-level-value 'boids-rules-size env)])
               (set-top-level-value! 'boids-rules-size
                                     (lambda () (values (+ w dw) h)) env)
               (steps 1)
               (set-top-level-value! 'boids-rules-size real env))
             (let-values ([(w2 h2) (window-content-size (rules-win))])
               (and (= w2 (+ w dw)) (= h2 h))))
           (and (grown-by! 40)
                (= (window-x (rules-win))
                   (+ (window-x win) (window-w win) 12))   ; it fit there
                (grown-by! 400)
                (= (+ (window-x (rules-win)) (window-w (rules-win)))
                   (+ dx dw)))))                           ; it moved left
  (check "Boids: closing the flock closes its rules window"
         (begin (close-window! win) (not (rules-win)))))

;; Opened far to the right, the rules window is moved to fit, and the
;; flock moves left to clear it.
(let ([win (parameterize ([new-window-position '(400 . 60)]) (boids))])
  (check "Boids: opened where the rules can't fit beside, the flock moves"
         (let ([rw (find-window "Boids — Rules")])
           (and (< (window-x win) 400)
                (= (+ (window-x win) (window-w win) 12) (window-x rw)))))
  (close-window! win))

;;; ------------------------------------------------------------------ Springies
;;; The springs' laws as XSpringies has them, Runge-Kutta against motion
;;; known exactly, the walls, the models, and the window and its controls.

;; Springies runs in its sandbox (services/grant.ss): its names,
;; forwarded here.
(define springies-box (grant-env 'springies))

(check "Springies runs in its sandbox, holding its bundles, allowed by the \
        table, and its names stay there: pt is none of the world's; its \
        controls window is no app's"
       (let* ([held (environment-symbols (env-environment springies-box))]
              [world (environment-symbols *world-env*)]
              [win (springies)]
              [cw (find-window "Springies — Controls")]
              [ok (and (equal? (env-path springies-box) "/apps/springies")
                       (equal? (grant-requested 'springies)
                               '(window draw ui timers))
                       (null? (grant-undecided 'springies))
                       (memq 'ui-checkbox held) (not (memq 'notify held))
                       (memq 'pt held) (memq 'springies-step held)
                       (not (memq 'pt world)) (not (memq 'pt+ world))
                       (not (memq 'springies-step world))
                       (eq? (window-app win) 'springies)
                       (not (window-app cw)))])
         (close-window! win)
         ok))

;; For the checks below, here and not in the world they test: this suite's
;; own view of the sandbox.
(for-each (lambda (n)
            (define-top-level-syntax n
              (forwarder-to (datum->syntax (env-anchor springies-box) n))))
          '(make-pt pt-x pt-y pt-zero pt+ pt- pt* pt-norm make-particle
            particle? particle-position particle-velocity particle-mass
            particle-radius particle-bounce make-spring spring-a spring-b
            spring-rest-length spring-force make-tether tether-particle
            tether-point tether-force springies-forces springies-rate
            springies-rk4 springies-step springies-setting
            springies-set-setting springies-frame springies-model-particles
            springies-model-springs springies-model-settings springies-kick
            springies-ball springies-models springies-build springies-nearest
            springies-box-size springies-draw-controls))

(define (test-particle x y vx vy m e)
  (make-particle (make-pt x y) (make-pt vx vy) m e))

(define (test-close? a b tolerance) (<= (abs (- a b)) tolerance))

(define (test-pt-close? p x y tolerance)
  (and (test-close? (pt-x p) x tolerance) (test-close? (pt-y p) y tolerance)))

;; Two particles 10 apart on x, the first moving at (vx, vy), and a spring
;; between them of stiffness 100, damping 2 and the rest length given:
;; the force it pulls the first with.
(define (test-spring-pull rest vx vy)
  (spring-force (make-spring 0 1 100.0 2.0 rest)
                (vector (test-particle 0.0 0.0 vx vy 1.0 1.0)
                        (test-particle 10.0 0.0 0.0 0.0 1.0 1.0))))

(check "Springies: a spring at rest pulls nothing; stretched it pulls its \
        ends together, squeezed it pushes them apart"
       (and (test-pt-close? (test-spring-pull 10.0 0.0 0.0) 0.0 0.0 1e-12)
            (test-pt-close? (test-spring-pull 8.0 0.0 0.0) 200.0 0.0 1e-12)
            (test-pt-close? (test-spring-pull 12.0 0.0 0.0) -200.0 0.0 1e-12)))

(check "Springies: damping resists ends moving apart, not moving sideways"
       (and (test-pt-close? (test-spring-pull 10.0 -3.0 0.0) 6.0 0.0 1e-12)
            (test-pt-close? (test-spring-pull 10.0 0.0 5.0) 0.0 0.0 1e-12)))

(check "Springies: a spring of no length pulls nothing"
       (let ([ps (vector (test-particle 5.0 5.0 1.0 0.0 1.0 1.0)
                         (test-particle 5.0 5.0 0.0 0.0 1.0 1.0))])
         (and (eq? (spring-force (make-spring 0 1 100.0 2.0 10.0) ps) pt-zero)
              (eq? (spring-force (make-spring 0 1 100.0 2.0 0.0) ps)
                   pt-zero))))

(check "Springies: gravity pulls light and heavy alike"
       (let ([rate (springies-rate
                    (vector (test-particle 0.0 0.0 0.0 0.0 1.0 1.0)
                            (test-particle 9.0 0.0 0.0 0.0 10.0 1.0))
                    '() (make-pt 0.0 -980.0))])
         (for-all (lambda (p) (test-pt-close? (particle-velocity p)
                                              0.0 -980.0 0.0))
                  (vector->list rate))))

;; Six particles of random masses and springs between them all, moving at
;; random: m a summed over them is the springs' forces, which cancel.
(check "Springies: springs pull equal and opposite: momentum holds"
       (let* ([ps (list->vector
                   (map (lambda (i)
                          (test-particle (random 100.0) (random 100.0)
                                         (- (random 20.0) 10.0)
                                         (- (random 20.0) 10.0)
                                         (+ 0.5 (random 5.0)) 1.0))
                        (iota 6)))]
              [ss (apply append
                         (map (lambda (a)
                                (map (lambda (b)
                                       (make-spring a b (random 500.0)
                                                    (random 5.0)
                                                    (random 50.0)))
                                     (iota a)))
                              (iota 6)))]
              [rate (springies-rate ps ss pt-zero)]
              [sum (fold-left pt+ pt-zero
                              (map (lambda (p r)
                                     (pt* (particle-velocity r)
                                          (particle-mass p)))
                                   (vector->list ps) (vector->list rate)))])
         (test-pt-close? sum 0.0 0.0 1e-9)))

;; With gravity alone the acceleration is constant, which Runge-Kutta
;; follows exactly: x0 + v0 t + g t²/2.
(check "Springies: a fall under gravity is the parabola, to rounding"
       (let loop ([ps (vector (test-particle 100.0 100.0 3.0 40.0 1.0 1.0))]
                  [i 0])
         (if (< i 10)
             (loop (springies-rk4 (lambda (s)
                                    (springies-rate s '()
                                                    (make-pt 0.0 -980.0)))
                                  ps 0.05)
                   (+ i 1))
             (let ([p (vector-ref ps 0)])   ; half a second on
               (and (test-pt-close? (particle-position p)
                                    101.5 (+ 100.0 20.0 -122.5) 1e-9)
                    (test-pt-close? (particle-velocity p)
                                    3.0 (- 40.0 490.0) 1e-9))))))

;; Two particles of mass 1 on a spring of stiffness 100, stretched by 1
;; and let go: they swing at ω = √(k/μ), μ = 1/2 the reduced mass. Half a
;; period on, the spring is squeezed by 1.
(check "Springies: two particles on a spring swing at its period"
       (let* ([ss (list (make-spring 0 1 100.0 0.0 10.0))]
              [half-period (/ pi (sqrt 200.0))]
              [n 1000])
         (let loop ([ps (vector (test-particle 500.0 500.0 0.0 0.0 1.0 1.0)
                                (test-particle 511.0 500.0 0.0 0.0 1.0 1.0))]
                    [i 0])
           (if (< i n)
               (loop (springies-step ps ss pt-zero (/ half-period n) 1e6 1e6)
                     (+ i 1))
               (let ([a (particle-position (vector-ref ps 0))]
                     [b (particle-position (vector-ref ps 1))])
                 (test-close? (pt-norm (pt- b a)) 9.0 1e-6))))))

;; Radius 3, elasticity 1/2, in a 100 × 100 box.
(check "Springies: a particle past a wall is put back on it, and turns \
        back if it was moving out, keeping its elasticity of its speed"
       (let ([down (particle-bounce (test-particle 10.0 -2.0 4.0 -10.0 1.0 0.5)
                                    100.0 100.0)]
             [in (particle-bounce (test-particle 99.0 50.0 -6.0 2.0 1.0 0.5)
                                  100.0 100.0)]
             [free (test-particle 50.0 50.0 -6.0 2.0 1.0 0.5)])
         (and (test-pt-close? (particle-position down) 10.0 3.0 0.0)
              (test-pt-close? (particle-velocity down) 2.0 5.0 0.0)
              (test-pt-close? (particle-position in) 97.0 50.0 0.0)
              (test-pt-close? (particle-velocity in) -3.0 1.0 0.0)
              (eq? (particle-bounce free 100.0 100.0) free))))

(define (test-models) (map (lambda (name) (springies-build name 760.0 520.0))
                           springies-models))

;; Each pair once: two springs between the same particles would be one
;; spring twice as stiff.
(check "Springies: each model's springs join particles it has, each pair \
        once, each at rest"
       (for-all
        (lambda (m)
          (let ([ps (springies-model-particles m)]
                [ss (springies-model-springs m)])
            (define (ends s) (list (min (spring-a s) (spring-b s))
                                   (max (spring-a s) (spring-b s))))
            (and (for-all
                  (lambda (s)
                    (and (< -1 (spring-a s) (vector-length ps))
                         (< -1 (spring-b s) (vector-length ps))
                         (not (= (spring-a s) (spring-b s)))
                         (= (spring-rest-length s)
                            (pt-norm (pt- (particle-position
                                           (vector-ref ps (spring-a s)))
                                          (particle-position
                                           (vector-ref ps (spring-b s))))))))
                  ss)
                 (= (length ss)
                    (length (fold-left (lambda (seen s)
                                         (if (member (ends s) seen)
                                             seen
                                             (cons (ends s) seen)))
                                       '() ss))))))
        (test-models)))

;; 5 seconds at 60 frames a second; the snake kicked again halfway. Whole:
;; no spring stretched or squeezed by half.
(check "Springies: each model moves about and stays in its box, whole"
       (for-all
        (lambda (m)
          (let ([ss (springies-model-springs m)])
            (let loop ([ps (springies-model-particles m)] [i 0])
              (if (< i 300)
                  (loop (springies-frame (if (= i 150) (springies-kick ps) ps)
                                         ss (springies-model-settings m)
                                         760.0 520.0)
                        (+ i 1))
                  (and (not (for-all eq? (vector->list ps)
                                     (vector->list
                                      (springies-model-particles m))))
                       (for-all (lambda (p)
                                  (let ([q (particle-position p)]
                                        [r (particle-radius p)])
                                    (and (<= r (pt-x q) (- 760.0 r))
                                         (<= r (pt-y q) (- 520.0 r)))))
                                (vector->list ps))
                       (for-all
                        (lambda (s)
                          (< 0.5
                             (/ (pt-norm
                                 (pt- (particle-position
                                       (vector-ref ps (spring-a s)))
                                      (particle-position
                                       (vector-ref ps (spring-b s)))))
                                (spring-rest-length s))
                             1.5))
                        ss))))))
        (test-models)))

(check "Springies: only the snake starts without gravity"
       (equal? (map (lambda (m)
                      (springies-setting (springies-model-settings m)
                                         'gravity?))
                    (test-models))
               '(#t #t #f)))

(check "Springies: a kick moves every particle, from where it was"
       (let* ([ps (springies-model-particles (springies-ball 760.0 520.0))]
              [kicked (springies-kick ps)])
         (for-all (lambda (p q)
                    (and (eq? (particle-position p) (particle-position q))
                         (not (equal? (pt-x (particle-velocity p))
                                      (pt-x (particle-velocity q))))))
                  (vector->list ps) (vector->list kicked))))

(check "Springies: setting a setting keeps the others, and their order"
       (let* ([settings '(gravity 980.0 gravity? #t time-step 0.004 steps 4)]
              [set (springies-set-setting settings 'time-step 0.002)])
         (and (= (springies-setting set 'time-step) 0.002)
              (equal? (plist-keys set) (plist-keys settings))
              (= (springies-setting set 'steps) 4)
              (raises? (lambda () (springies-set-setting settings 'drag 1.0)))
              (raises? (lambda () (springies-setting settings 'drag))))))

;; The keys, through the window's own handler. A clock moved a second on
;; past the last such tick lets a tick step, however fast the checks run.
(let ([win (springies)] [later 0])
  (define (key! k) (window-call win 'key k '()))
  (define (particles) (window-ref win 'particles))
  (define (setting key) (springies-setting (window-ref win 'settings) key))
  (define (tick-later!)
    (set! later (+ later 1000))
    (fluid-let ([now-ms (let ([t (+ (now-ms) later)]) (lambda () t))])
      (steps 1)))
  (check "Springies: it opens on the ball, running"
         (and (eq? (window-ref win 'model) 'ball)
              (window-ref win 'running?)))
  (check "Springies: 1, 2 and 3 choose the ball, the tire and the snake, \
          each with its settings"
         (begin
           (key! #\3)
           (and (eq? (window-ref win 'model) 'snake)
                (not (setting 'gravity?))
                (begin (key! #\2) (eq? (window-ref win 'model) 'tire))
                (= (setting 'time-step) 0.003)
                (begin (key! #\1) (eq? (window-ref win 'model) 'ball)))))
  (check "Springies: G turns gravity off and on; R starts over, keeping it"
         (begin
           (key! #\g)
           (tick-later!)
           (let ([moved (particles)])
             (key! #\r)
             (and (not (setting 'gravity?))
                  (not (eq? (particles) moved))
                  (eq? (window-ref win 'model) 'ball)
                  (begin (key! #\g) (setting 'gravity?))))))
  (check "Springies: K kicks"
         (let ([before (particles)])
           (key! #\k)
           (not (eq? (particles) before))))
  (check "Springies: Space holds the particles still, and again sets them \
          going"
         (let ([before (begin (key! #\space) (particles))])
           (tick-later!)
           (let ([held? (eq? (particles) before)])
             (key! #\space)
             (tick-later!)
             (and held? (window-ref win 'running?)
                  (not (eq? (particles) before))))))
  (close-window! win))

(check "Springies: a tether pulls its particle to its point, damped against \
        the particle's speed; among springs, it pulls that one alone"
       (let* ([ps (vector (test-particle 10.0 20.0 0.0 0.0 1.0 1.0)
                          (test-particle 50.0 50.0 2.0 -1.0 1.0 1.0))]
              [t (make-tether 1 (make-pt 60.0 40.0) 100.0 5.0)]
              [forces (springies-forces ps (list t))])
         (and (test-pt-close? (tether-force t ps) 990.0 -995.0 0.0)
              (eq? (vector-ref forces 0) pt-zero)
              (test-pt-close? (vector-ref forces 1) 990.0 -995.0 0.0))))

(check "Springies: the particle nearest a point, within reach"
       (let ([ps (vector (test-particle 0.0 0.0 0.0 0.0 1.0 1.0)
                         (test-particle 30.0 0.0 0.0 0.0 1.0 1.0)
                         (test-particle 60.0 0.0 0.0 0.0 1.0 1.0))])
         (and (= (springies-nearest ps (make-pt 40.0 5.0) 50.0) 1)
              (= (springies-nearest ps (make-pt 100.0 0.0) 50.0) 2)
              (not (springies-nearest ps (make-pt 200.0 0.0) 50.0)))))

;; The mouse, through the window's handlers, at a particle's place on the
;; screen: y flipped.
(let ([win (springies)] [later 0])
  (define (particle i) (vector-ref (window-ref win 'particles) i))
  (define (screen-of i)
    (let-values ([(w h) (springies-box-size win)])
      (let ([q (particle-position (particle i))])
        (values (pt-x q) (- h (pt-y q))))))
  (define (tick-later!)
    (set! later (+ later 1000))
    (fluid-let ([now-ms (let ([t (+ (now-ms) later)]) (lambda () t))])
      (steps 1)))
  (check "Springies: a press near a particle holds it on the pointer's \
          tether, one far from all holds none"
         (let-values ([(x y) (screen-of 5)])
           (window-call win 'mouse-down (+ x 4) (- y 3) 'left 1)
           (let ([t (window-ref win 'tether)])
             (window-call win 'mouse-up (+ x 4) (- y 3) 'left)
             (and t (= (tether-particle t) 5)
                  (test-pt-close? (tether-point t)
                                  (+ (pt-x (particle-position (particle 5))) 4)
                                  (+ (pt-y (particle-position (particle 5))) 3)
                                  1e-9)
                  (not (window-ref win 'tether))
                  (begin (window-call win 'mouse-down 1 1 'left 1)
                         (not (window-ref win 'tether)))))))
  ;; held 100 pixels up, against two frames let be
  (check "Springies: the held particle follows the pointer, until let go"
         (let*-values ([(x y) (screen-of 5)] [(w h) (springies-box-size win)])
           (window-call win 'mouse-down x y 'left 1)
           (window-call win 'mouse-move x (- y 100))
           (let* ([frame (lambda (ps)
                           (springies-frame ps (window-ref win 'springs)
                                            (window-ref win 'settings) w h))]
                  [let-be (vector-ref (frame (frame (window-ref win
                                                                'particles)))
                                      5)])
             (tick-later!)
             (tick-later!)
             (let ([pulled (> (pt-y (particle-position (particle 5)))
                              (+ (pt-y (particle-position let-be)) 1.0))])
               (window-call win 'mouse-up x (- y 100) 'left)
               (and pulled (not (window-ref win 'tether)))))))
  (check "Springies: choosing a model, or starting over, lets go"
         (let-values ([(x y) (screen-of 5)])
           (window-call win 'mouse-down x y 'left 1)
           (window-call win 'key #\2 '())
           (and (not (window-ref win 'tether))
                (let-values ([(x y) (screen-of 5)])
                  (window-call win 'mouse-down x y 'left 1)
                  (window-call win 'key #\r '())
                  (not (window-ref win 'tether))))))
  (close-window! win))

;; The controls window, opened with the box, where both fit.
(let* ([win (parameterize ([new-window-position '(40 . 60)]) (springies))]
       [controls (lambda () (find-window "Springies — Controls"))]
       [setting (lambda (key)
                  (springies-setting (window-ref win 'settings) key))]
       [press! (lambda (cw id)   ; the middle of the widget id
                 (let ([r (ui-find (window-ref cw 'ui) id)])
                   (let ([x (+ (ui-region-x r) (/ (ui-region-w r) 2))]
                         [y (+ (ui-region-y r) (/ (ui-region-h r) 2))])
                     (window-call cw 'mouse-down x y 'left 1)
                     (window-call cw 'mouse-up x y 'left))))])
  (render-frame!)
  (check "Springies: the controls open beside the box, which has the keys"
         (let ([cw (controls)])
           (and cw (eq? (focused-window) win)
                (= (window-x cw) (+ (window-x win) (window-w win) 12))
                (= (window-y cw) (window-y win)))))
  (check "Springies: the controls window has room for all its rows"
         (let-values ([(w h) (window-content-size (controls))])
           (let* ([bottom #f]
                  [s (image (exact (ceiling w)) (exact (ceiling h)) 1
                            (lambda ()
                              (let ([ui (make-ui)])
                                (ui-begin! ui)
                                (set! bottom
                                      (springies-draw-controls ui win w)))))])
             (cairo-surface-destroy s)
             (<= bottom h))))
  (check "Springies: the controls window paints the style's page under its \
          rows"
         (let*-values ([(cw) (controls)] [(w h) (window-content-size cw)])
           (let* ([surfaces '()]
                  [real ui-draw-surface]
                  [s (fluid-let ([ui-draw-surface
                                  (lambda (x y w h flags)
                                    (set! surfaces (cons flags surfaces))
                                    (real x y w h flags))])
                       (image (exact (ceiling w)) (exact (ceiling h)) 1
                              (lambda ()
                                (parameterize ([current-window cw])
                                  ((hashtable-ref (window-handlers cw) 'draw #f)
                                   cw w h)))))])
             (cairo-surface-destroy s)
             (and (member '(page) surfaces) #t))))
  (check "Springies: its model buttons choose the model"
         (begin
           (press! (controls) 'snake)
           (and (eq? (window-ref win 'model) 'snake)
                (not (setting 'gravity?))
                (begin (press! (controls) 'ball)
                       (eq? (window-ref win 'model) 'ball)))))
  (check "Springies: its buttons and keys act on the box"
         (let ([before (window-ref win 'particles)])
           (press! (controls) 'kick)
           (let ([kicked (window-ref win 'particles)])
             (press! (controls) 'reset)
             (window-call (controls) 'key #\g '())
             (and (not (eq? kicked before))
                  (not (eq? (window-ref win 'particles) kicked))
                  (not (setting 'gravity?))))))
  (check "Springies: its switches turn gravity and the pause on and off"
         (begin
           (press! (controls) 'gravity)
           (press! (controls) 'pause)
           (and (setting 'gravity?)
                (not (window-ref win 'running?))
                (begin (press! (controls) 'pause)
                       (window-ref win 'running?)))))
  (check "Springies: its sliders set the time step, and whole steps a frame"
         (begin
           (press! (controls) 'time-step)
           (press! (controls) 'steps)
           (and (< (abs (- (setting 'time-step) 0.00525)) 1e-9)
                (eqv? (setting 'steps) 8))))
  (check "Springies: H closes the controls and opens them again"
         (begin
           (window-call win 'key #\h '())
           (and (not (controls))
                (begin (window-call win 'key #\h '())
                       (controls) #t))))
  (check "Springies: the controls grow when their rows need more, on screen"
         (let-values ([(w h) (window-content-size (controls))]
                      [(dx dy dw dh) (desktop-rect)])
           (define (grown-by! dw)
             (let* ([env (env-environment springies-box)]
                    [real (top-level-value 'springies-controls-size env)])
               (set-top-level-value! 'springies-controls-size
                                     (lambda () (values (+ w dw) h)) env)
               (steps 1)
               (set-top-level-value! 'springies-controls-size real env))
             (let-values ([(w2 h2) (window-content-size (controls))])
               (and (= w2 (+ w dw)) (= h2 h))))
           (and (grown-by! 40)
                (grown-by! 900)
                (= (+ (window-x (controls)) (window-w (controls)))
                   (+ dx dw)))))
  (check "Springies: closing the box closes its controls"
         (begin (close-window! win) (not (controls)))))

;; Opened far to the right, the controls are moved to fit, and the box
;; moves left to clear them.
(let ([win (parameterize ([new-window-position '(400 . 60)]) (springies))])
  (check "Springies: opened where the controls can't fit beside, the box \
          moves"
         (let ([cw (find-window "Springies — Controls")])
           (and (< (window-x win) 400)
                (= (+ (window-x win) (window-w win) 12) (window-x cw)))))
  (close-window! win))

(check "Springies: a frame leaves the particles it steps as they were"
       (let* ([m (springies-ball 760.0 520.0)]
              [ps (springies-model-particles m)]
              [before (vector->list ps)])
         (springies-frame ps (springies-model-springs m)
                          (springies-model-settings m) 760.0 520.0)
         (for-all eq? (vector->list ps) before)))

;; The record types are nongenerative, as Boids' are.
(check "Springies: particles made before the file loads again still work"
       (let ([m (springies-ball 760.0 520.0)])
         (load-source "apps/springies.ss")
         (and (particle? (vector-ref (springies-model-particles m) 0))
              (vector? (springies-frame (springies-model-particles m)
                                        (springies-model-springs m)
                                        (springies-model-settings m)
                                        760.0 520.0)))))

;;; ------------------------------------------------------------------
;;; invalidation

(let ([w (open-window "Dirty" 'size '(200 . 100))])
  (define (asks? thunk) (set! *dirty* #f) (thunk) *dirty*)
  (check "(invalidate!), (invalidate! #f), (invalidate! win), \
          (invalidate! win x y w h) and (request-frame!) ask for a frame"
         (for-all asks? (list (lambda () (invalidate!))
                              (lambda () (invalidate! #f))
                              (lambda () (invalidate! w))
                              (lambda () (invalidate! w 1 2 3 4))
                              request-frame!)))
  (let-values ([(ex ey ew eh) (window-extent w)])
    (define (asked thunk) (set! *dirty* #f) (thunk) *dirty*)
    (check "(invalidate! win) and (invalidate! win x y w h) ask for its \
            extent; areas asked for make their bounding box, and the \
            whole screen holds them all"
           (and (equal? (asked (lambda () (invalidate! w)))
                        (list ex ey (+ ex ew) (+ ey eh)))
                (equal? (asked (lambda () (invalidate! w -5 10 30 500)))
                        (list ex ey (+ ex ew) (+ ey eh)))
                (equal? (asked (lambda ()
                                 (request-frame! 10 20 30 40)
                                 (request-frame! 100 5 10 10)))
                        '(10 5 110 60))
                (eq? (asked (lambda () (request-frame!) (invalidate! w)))
                     #t))))
  (let ([plain *styles*]
        [bleed-of (lambda (w)   ; how far w's extent reaches past its frame
                    (let-values ([(x y ew eh) (window-extent w)])
                      (- (window-x w) x)))])
    (define-style wide "Wide" 'frame-bleed (lambda (win) 5))
    (override! 'shadow 0)   ; shadow
    (window-set! w 'window-style 'wide)
    (let ([wide (bleed-of w)])
      (window-set! w 'window-style 'mac)
      (override! 'shadow -6)   ; shadow
      (let ([narrow (bleed-of w)])
        (override! 'shadow)   ; shadow
        (set! *styles* plain)
        (check (format "a style's 'bleed widens its windows' extent (~a); \
                        nothing makes it smaller than the frame (~a)"
                       wide narrow)
               (and (= wide 5) (= narrow 0))))))
  (window-call w 'key #\a '())   ; no key handler: nothing to see
  (window-on! w 'key (lambda (win key mods) (void)))
  (check "input to a handler asks for a frame"
         (asks? (lambda () (window-call w 'key #\a '()))))
  (window-on! w 'key (lambda (win key mods) (current-window)))
  (check "handlers run with (current-window) set"
         (and (eq? w (window-call w 'key #\a '())) (not (current-window))))
  (close-window! w))

;;; ------------------------------------------------------------------
;;; long text: cut, colored and searched in time at any length

;; Whether thunk ends within the fuel an app's handler gets.
(define (within-fuel? thunk)
  ((make-engine thunk) handler-fuel (lambda (left . r) #t) (lambda (e) #f)))

;; text-fit as plainly as it can be said: a character shorter at a time.
(define (fit-plainly str max-w font)
  (if (<= (text-width str font) max-w)
      str
      (let loop ([n (- (string-length str) 1)])
        (let ([s (string-append (substring str 0 (max n 0)) "…")])
          (if (or (<= n 0) (<= (text-width s font) max-w)) s (loop (- n 1)))))))

(check "text-fit cuts where cutting a character at a time does: window, \
        task and made-up titles, other scripts, in five fonts and many \
        widths"
       (let ([strings
              (append
               (list "" "a" "…" "REPL" "REPL — running · Ctrl+C to interrupt"
                     "Life" "Sketch" "Settings" "Tasks" "Clock" "Monitor"
                     "Überschrift: Größenänderung — ½ × 東京 λ"
                     "Ελληνικά και Русский текст с ударени́ем"
                     "emoji 😀 and a tab\tand spaces    end"
                     (make-string 40 #\λ) (make-string 60 #\i)
                     (make-string 26 #\W))
               (begin (tasks-reset!) (map task-title *tasks*))
               (let ([abc "aW i.λ東Ü\x301;😀-"])   ; made up, the same each run
                 (map (lambda (i)
                        (list->string
                         (map (lambda (j)
                                (string-ref abc (mod (* (+ i 3) (+ j 7) 37)
                                                     (string-length abc))))
                              (iota (mod (* i 17) 90)))))
                      (iota 30))))])
         (for-all (lambda (font)
                    (for-all (lambda (w)
                               (for-all (lambda (s)
                                          (equal? (text-fit s w font)
                                                  (fit-plainly s w font)))
                                        strings))
                             '(-1 0 6 13 25 40 64 100 150 220 320)))
                  '(ui title ui-small mono-small heading))))

(check "text-fit measures log n times: 100,000 characters in at most 18"
       (let* ([n 0] [orig text-width]
              [s (dynamic-wind
                   (lambda ()
                     (set! text-width
                           (lambda args (set! n (+ n 1)) (apply orig args))))
                   (lambda () (text-fit (make-string 100000 #\W) 300 'ui))
                   (lambda () (set! text-width orig)))]
              [k (- (string-length s) 1)])
         (and (<= 1 n 18)
              (<= (text-width s 'ui) 300)
              (> (text-width (string-append (make-string (+ k 1) #\W) "…")
                             'ui)
                 300))))

;; The characters text-width is given while thunk runs.
(define (characters-measured thunk)
  (let ([n 0] [plain text-width])
    (dynamic-wind
      (lambda ()
        (set! text-width
              (case-lambda
                [(s) (set! n (+ n (string-length s))) (plain s)]
                [(s f) (set! n (+ n (string-length s))) (plain s f)])))
      thunk
      (lambda () (set! text-width plain)))
    n))

;; words, then spaces, to n characters: "words words wo".
(define (words-of n)
  (substring (apply string-append (make-list (+ 1 (quotient n 6)) "words "))
             0 n))

(check "text-fit looks at no more characters than its width could show: as \
        many measured to fit 100,000 characters into 300 pixels as to fit \
        2,000, with words or without"
       (for-all (lambda (make)
                  (= (characters-measured
                      (lambda () (text-fit (make 2000) 300 'ui)))
                     (characters-measured
                      (lambda () (text-fit (make 100000) 300 'ui)))))
                (list words-of (lambda (n) (make-string n #\W)))))

(check "text-within: a string cut to one character more than its width in \
        pixels, the string itself when it is no longer"
       (let ([s "a short one"])
         (and (equal? (text-within (make-string 500 #\i) 40.7)
                      (make-string 41 #\i))
              (eq? (text-within s 40) s) (eq? (text-within s 10) s)
              (equal? (text-within s 3) "a sh")
              (equal? (text-within s -5) "a"))))

(check "Reticle's spaced title: cut with … to its room, and an empty one \
        stays empty however little room is left"
       (and (equal? (reticle-label "Tasks" 1000) "TASKS")
            (string-suffix? "…" (reticle-label (make-string 40 #\m) 100))
            (for-all (lambda (room) (equal? (reticle-label "" room) ""))
                     '(-40 -3 -1 0 50))))

(check "app-color: the color the whole hash gives, and a name of 100,000 \
        characters within a handler's fuel"
       (and (for-all
             (lambda (name)
               (eq? (app-color name)
                    (list-ref (theme 'app-colors)
                              (mod (fold-left (lambda (h c)
                                                (+ (* h 31) (char->integer c)))
                                              7
                                              (string->list
                                               (symbol->string name)))
                                   (length (theme 'app-colors))))))
             '(repl life settings tasks clock |Pavel Uvarov| perf λ ||))
            (let ([long (string->symbol (make-string 100000 #\a))])
              (within-fuel? (lambda () (app-color long))))))

(check "string-contains-ci?: case ignored, the empty string found, and a \
        word missing from 100,000 characters looked for within a handler's \
        fuel"
       (and (string-contains-ci? "Hello World" "O w")
            (string-contains-ci? "ΛΑΜΒΔΑ λ" "λαμ")
            (string-contains-ci? "abc" "") (string-contains-ci? "" "")
            (not (string-contains-ci? "abc" "abcd"))
            (not (string-contains-ci? "" "a"))
            (string-contains-ci? "xxabcab" "cab")
            (let ([s (apply string-append (make-list 12500 "abcdefg "))]
                  [w (make-string 1000 #\z)])
              (within-fuel? (lambda () (string-contains-ci? s w))))))

;;; ------------------------------------------------------------------
;;; the edit kit, the widget kit and Tasks, pure
;;; Text editing, rows, dates, flow and table keys, and Tasks' own
;;; procedures, with no window: text measures 7 px a character.

(define (m7 s) (* 7 (string-length s)))
(define (lay-of text width . measure)
  (edit-layout-of #f text width #f (if (pair? measure) (car measure) m7) #f))
(define (ed text caret . anchor)
  (make-edit text caret (if (pair? anchor) (car anchor) caret) #f #f))
(define (state e) (list (edit-text e) (edit-caret e) (edit-anchor e)))
(define (key e k . mods)
  (edit-key e k mods (lay-of (edit-text e) 1000) 1))
(define fbq "foo-bar  baz.qux")

(check "insert at a caret, over a selection, at both ends, into empty text"
       (and (equal? (state (edit-insert (ed "abc" 1) "X")) '("aXbc" 2 2))
            (equal? (state (edit-insert (ed "abcd" 1 3) "X")) '("aXd" 2 2))
            (equal? (state (edit-insert (ed "abc" 0) "X")) '("Xabc" 1 1))
            (equal? (state (edit-insert (ed "abc" 3) "X")) '("abcX" 4 4))
            (equal? (state (edit-insert (ed "" 0) "X")) '("X" 1 1))
            (equal? (state (edit-insert (ed "abc" 1 2) "")) '("ac" 1 1))))

(check "with a most, typing stops at it, a paste is cut to fit, and a \
        selection makes room; no most is no limit"
       (and (equal? (state (edit-insert (ed "abc" 3) "X" 3)) '("abc" 3 3))
            (equal? (state (edit-insert (ed "abc" 1) "XYZ" 5)) '("aXYbc" 3 3))
            (equal? (state (edit-insert (ed "abcd" 1 3) "XYZ" 4))
                    '("aXYd" 3 3))
            (equal? (state (edit-insert (ed "abc" 3) "XY" #f))
                    '("abcXY" 5 5))))

(check "what changes nothing keeps the very string: an empty insert, an \
        erase of nothing, a move, a text clean already"
       (let ([t "abc"])
         (and (eq? t (edit-text (edit-insert (ed t 1) "")))
              (eq? t (edit-text (key (ed t 0) 'backspace)))
              (eq? t (edit-text (key (ed t 1) 'right)))
              (eq? t (edit-text (edit-insert (ed t 3) "X" 3)))
              (eq? t (edit-clean t #t)))))

(check "an edit says what it changed, the text before and the range \
        replaced; a caret move keeps that word, and so does an edit \
        that changes nothing"
       (let* ([t "abcdef"] [e1 (edit-insert (ed t 2 4) "XYZ")]
              [e2 (key e1 'left)] [e3 (edit-insert e2 "")]
              [e4 (key (ed t 3) 'backspace)])
         (and (equal? (edit-change e1) (list t 2 4))
              (eq? (car (edit-change e1)) t)
              (eq? (edit-change e2) (edit-change e1))
              (eq? (edit-change e3) (edit-change e1))
              (equal? (edit-change e4) (list t 2 3))
              (not (edit-change (ed t 3))))))

(check "Backspace at the start and Delete at the end change nothing; \
        they erase a character, a selection, or a word with Ctrl"
       (and (equal? (state (key (ed "abc" 0) 'backspace)) '("abc" 0 0))
            (equal? (state (key (ed "abc" 3) 'delete)) '("abc" 3 3))
            (equal? (state (key (ed "abc" 2) 'backspace)) '("ac" 1 1))
            (equal? (state (key (ed "abc" 1) 'delete)) '("ac" 1 1))
            (equal? (state (key (ed "abcd" 3 1) 'backspace)) '("ad" 1 1))
            (equal? (state (key (ed fbq 16) 'backspace 'ctrl))
                    '("foo-bar  baz." 13 13))
            (equal? (state (key (ed fbq 9) 'backspace 'ctrl)) '("baz.qux" 0 0))
            (equal? (state (key (ed fbq 0) 'delete 'ctrl)) '("  baz.qux" 0 0))))

(check "Left and Right collapse a selection to its side; Shift extends it \
        and shrinks it across the anchor; Ctrl moves by words; Home, End"
       (and (equal? (state (key (ed "abcd" 3 1) 'left)) '("abcd" 1 1))
            (equal? (state (key (ed "abcd" 1 3) 'right)) '("abcd" 3 3))
            (equal? (state (key (ed "abcd" 2) 'right 'shift)) '("abcd" 3 2))
            (equal? (state (key (key (key (ed "abcd" 2) 'right 'shift)
                                     'left 'shift)
                                'left 'shift))
                    '("abcd" 1 2))
            (equal? (state (key (ed fbq 0) 'right 'ctrl)) (list fbq 7 7))
            (equal? (state (key (ed fbq 7) 'right 'ctrl)) (list fbq 12 12))
            (equal? (state (key (ed fbq 13) 'left 'ctrl)) (list fbq 9 9))
            (equal? (state (key (ed fbq 12) 'left 'ctrl 'shift))
                    (list fbq 9 12))
            (equal? (state (key (ed "abc" 1) 'home)) '("abc" 0 0))
            (equal? (state (key (ed "abc" 1) 'end 'shift)) '("abc" 3 1))))

(define (bounds f text i) (call-with-values (lambda () (f text i)) list))
(check "a double click's word: at its start, end and inside, on spaces, \
        across - and _, on a word's last character; a triple click's line"
       (and (equal? (bounds edit-word-bounds "foo bar" 0) '(0 3))
            (equal? (bounds edit-word-bounds "foo bar" 7) '(4 7))
            (equal? (bounds edit-word-bounds "foo bar" 1) '(0 3))
            (equal? (bounds edit-word-bounds "foo bar" 3) '(0 3))
            (equal? (bounds edit-word-bounds "a   b" 2) '(1 4))
            (equal? (bounds edit-word-bounds "foo-bar_baz qux" 5) '(0 11))
            (equal? (bounds edit-word-bounds "a.b" 1) '(0 1))
            (equal? (bounds edit-word-bounds "a.b" 2) '(2 3))
            (equal? (bounds edit-line-bounds "ab\ncd\nef" 4) '(3 5))))

(check "Ctrl+A selects everything; λ is one character"
       (let ([e (key (ed "λx y" 1) #\a 'ctrl)])
         (and (equal? (state e) '("λx y" 4 0))
              (equal? (edit-selection e) "λx y")
              (equal? (state (key (ed "λx" 0) 'right)) '("λx" 1 1)))))

(check "edit-key leaves Return, Escape, Tab, typed keys and Ctrl+C"
       (for-all (lambda (k) (not (apply key (ed "abc" 1) k)))
                '((return) (escape) (tab) (#\a) (#\c ctrl))))

(define (wrap text width . measure)
  (vector->list (edit-wrap text width (if (pair? measure) (car measure) m7))))
(check "wrapping: a row, newlines, empty text, a trailing newline; a soft \
        break keeps its space; a word wider than the width, and a width \
        under one character, break between characters; a last space \
        hangs"
       (and (equal? (wrap "hello" 100) '((0 . 5)))
            (equal? (wrap "ab\ncd" 100) '((0 . 2) (3 . 5)))
            (equal? (wrap "" 100) '((0 . 0)))
            (equal? (wrap "ab\n" 100) '((0 . 2) (3 . 3)))
            (equal? (wrap "aaa bbb ccc" 56) '((0 . 8) (8 . 11)))
            (equal? (wrap "aaa bbb ccc" 42) '((0 . 4) (4 . 8) (8 . 11)))
            (equal? (wrap "abcdefgh" 21) '((0 . 3) (3 . 6) (6 . 8)))
            (equal? (wrap "abc" 3) '((0 . 1) (1 . 2) (2 . 3)))
            (equal? (wrap "hello " 35) '((0 . 6)))))

;; Widths that differ: a space and narrow letters 3, wide ones 11, the
;; rest 7.
(define (mp s)
  (let loop ([i 0] [w 0])
    (if (= i (string-length s))
        w
        (loop (+ i 1) (+ w (case (string-ref s i)
                             [(#\space #\i #\l) 3]
                             [(#\m #\w) 11]
                             [else 7]))))))

;; The wrapping rule as plainly as it can be said: each row measures the
;; rest of its paragraph, then every space, then every prefix.
(define (wrap-plainly text width . measure)
  (let* ([n (string-length text)]
         [m (if (pair? measure) (car measure) m7)]
         [fits? (lambda (s e) (<= (m (substring text s e)) width))]
         [end (lambda (p)
                (let loop ([q p])
                  (if (or (= q n) (char=? (string-ref text q) #\newline))
                      q
                      (loop (+ q 1)))))])
    (let para ([p 0] [rows '()])
      (let ([q (end p)])
        (define (next rows) (if (< q n) (para (+ q 1) rows) (reverse rows)))
        (let row ([s p] [rows rows])
          (cond
            [(and (= s q) (> s p)) (next rows)]
            [(fits? s q) (next (cons (cons s q) rows))]
            [else
             (let* ([ks (filter (lambda (k) (and (char=? (string-ref text k)
                                                         #\space)
                                                 (fits? s k)))
                                (map (lambda (i) (+ s i)) (iota (- q s))))]
                    [e (if (pair? ks)
                           (+ 1 (apply max ks))
                           (let loop ([j (+ s 1)])
                             (if (and (< j q) (fits? s (+ j 1)))
                                 (loop (+ j 1))
                                 j)))])
               (row e (cons (cons s e) rows)))]))))))

(define (next-random x) (mod (+ (* x 1103515245) 12345) 2147483648))

;; A made-up text of len characters from seed, of the letters in abc.
(define (made-up len seed abc)
  (let fill ([k 0] [x seed] [acc '()])
    (if (= k len)
        (values (list->string acc) x)
        (fill (+ k 1) (next-random x)
              (cons (string-ref abc (mod (quotient x 9) (string-length abc)))
                    acc)))))

;; The rows as a typist breaks them, a character at a time, sharing no
;; code or search with the kit: a row takes characters while what it
;; holds fits, minding the last space before which it fit; at one that
;; does not fit, it breaks after that space (which hangs past the width),
;; else before the character, keeping one at least. A newline ends a row.
(define (wrap-by-character text width m)
  (let ([n (string-length text)])
    (define (end? j) (or (= j n) (char=? (string-ref text j) #\newline)))
    (define (fits? s e) (<= (m (substring text s e)) width))
    (let row ([s 0] [p 0] [rows '()])   ; a row from s, its paragraph's p
      (if (and (> s p) (end? s))   ; a break ended the paragraph
          (if (= s n) (reverse rows) (row (+ s 1) (+ s 1) rows))
          (let walk ([j s] [space #f])   ; [s, j) fits
            (if (end? j)
                (let ([rows (cons (cons s j) rows)])
                  (if (= j n) (reverse rows) (row (+ j 1) (+ j 1) rows)))
                (let ([space (if (char=? (string-ref text j) #\space)
                                 j
                                 space)])
                  (if (fits? s (+ j 1))
                      (walk (+ j 1) space)
                      (let ([e (if space (+ space 1) (max j (+ s 1)))])
                        (row e p (cons (cons s e) rows)))))))))))

(check "a character at a time breaks the made-up texts where the plain \
        rule does"
       (let loop ([i 0] [seed 5])
         (or (= i 500)
             (let-values ([(text x) (made-up (mod (quotient seed 7) 41) seed
                                             "aimw  \n")])
               (let ([width (mod x 78)] [m (if (even? i) m7 mp)])
                 (and (equal? (wrap-by-character text width m)
                              (wrap-plainly text width m))
                      (loop (+ i 1) (next-random x))))))))

(check "wrapping breaks every text where the plain rule does: 2000 made-up \
        texts of letters, spaces and newlines, at widths from 0 to 11 \
        characters, measured alike and unlike"
       (let loop ([i 0] [seed 7])
         (or (= i 2000)
             (let-values ([(text x) (made-up (mod (quotient seed 7) 41) seed
                                             "aimw  \n")])
               (let ([width (mod x 78)] [m (if (even? i) m7 mp)])
                 (and (equal? (wrap text width m) (wrap-plainly text width m))
                      (loop (+ i 1) (next-random x))))))))

;; A layout's rows, computed to the end.
(define (rows-of lay)
  (edit-layout-extend! lay (string-length (edit-layout-text lay)))
  (map (lambda (r) (call-with-values (lambda () (edit-row lay r)) cons))
       (iota (edit-layout-count lay))))

(check "the lazy layout follows edits: after each of 3000 random \
        insertions, deletions and replacements, told where or not, the \
        rows it keeps, takes back and computes, partly or to the end, are \
        those a character at a time finds"
       (let loop ([i 0] [seed 11] [text ""] [lay #f] [width 40] [m m7])
         (cond
           [(= i 3000) #t]
           [(zero? (mod i 100))   ; a new width and measure, a new text
            (let-values ([(t x) (made-up 300 seed "aaimw  \n")])
              (loop (+ i 1) (next-random x) t #f (+ 10 (mod x 90))
                    (if (even? (quotient i 100)) m7 mp)))]
           [else
            (let*-values ([(n) (string-length text)]
                          [(lo) (mod seed (+ n 1))]
                          [(hi) (if (zero? (mod i 3))   ; an insertion
                                    lo
                                    (min n (+ lo (mod (quotient seed 5)
                                                      (if (zero? (mod i 11))
                                                          90
                                                          9)))))]
                          [(ins x) (made-up (if (= (mod i 3) 1)
                                                0
                                                (mod (quotient seed 3) 7))
                                            (next-random seed) "aimw \n")]
                          [(new) (string-append (substring text 0 lo) ins
                                                (substring text hi n))]
                          ;; told where, as by an edit, or compared
                          [(lay) (edit-layout-of lay new width #f m
                                                 (and (even? (quotient i 2))
                                                      (list text lo hi)))])
              ;; as a draw would: rows as far as some index, sometimes all
              (if (zero? (mod x 5))
                  (edit-layout-extend! lay (string-length new))
                  (edit-row-at lay (mod x (+ 1 (string-length new)))))
              (and (or (not (zero? (mod i 7)))
                       (equal? (rows-of (lay-of new width m)) (rows-of lay)))
                   (equal? (wrap-by-character new width m) (rows-of lay))
                   (loop (+ i 1) (next-random x) new lay width m)))])))

(check "a layout computes rows only as far as they are asked for, and \
        remembers them; its total is a count once they reach the end, \
        an estimate before"
       (let* ([n 0] [count (lambda (s) (set! n (+ n 1)) (m7 s))]
              [text (apply string-append (make-list 2000 "words of a row "))]
              [lay (lay-of text 280 count)])
         (edit-layout-extend! lay 14)
         (let ([first (edit-layout-count lay)]
               [estimate (edit-layout-total lay)])
           (edit-row-at lay 3000)
           (let ([again n])
             (edit-row-at lay 3000)
             (and (= first 15) (= again n) (not (edit-layout-done? lay))
                  (edit-layout-scan! lay 1000) (edit-layout-done? lay)
                  (= (edit-layout-total lay) (edit-layout-count lay)
                     (length (wrap text 280)))
                  (< (abs (- estimate (edit-layout-count lay)))
                     (* 1/10 (edit-layout-count lay))))))))

;; The worst cases' texts at m7 and 280 px (40 characters a row): one
;; paragraph of words; no spaces; every row exactly full, so that a
;; character typed at its start moves a word down each row (a cascade).
(define (worst-case which n)
  (let ([o (open-output-string)])
    (let loop ([i 0])
      (when (< i n)
        (case which
          [(words) (put-string o (vector-ref '#("the " "quick " "brown "
                                                 "fox " "jumps " "a ")
                                             (mod i 6)))]
          [(none) (put-string o "0123456789abcdef")]
          [(full) (put-string o "aaaaaaaaa bbbbbbbbb ccccccccc dddddddddd ")])
        (loop (+ i 1))))
    (substring (get-output-string o) 0 n)))

;; What a keystroke measures, as a text area 14 rows high does it: the
;; layout follows the new text, the rows down to the caret's view are
;; computed (the view follows the caret), and the caret's x. Before it,
;; the view showed the caret at k: rows to there were computed then.
(define (keystroke-measures text k op)
  (let* ([n 0] [count (lambda (s) (set! n (+ n 1)) (m7 s))]
         [lay (lay-of text 280 count)])
    (define (view! lay caret)
      (edit-layout-extend! lay (+ (edit-row-at lay caret) 15))
      (edit-caret-x lay caret))
    (view! lay k)
    (set! n 0)
    (let* ([e (op (ed text k) lay)]
           [lay (edit-layout-of lay (edit-text e) 280 #f count
                                (edit-change e))])
      (view! lay (edit-caret e))
      n)))

(check "a keystroke in each worst case measures in proportion to the rows \
        in view, at most 4 a row, at 16,384 characters as at 65,536: \
        typing at the start, middle and end, Backspace, Delete, a paste of \
        a few words, everything selected and deleted, the wheel"
       (let ([ops
              (list (cons 0 (lambda (e lay) (edit-insert e "x")))
                    (cons 1/2 (lambda (e lay) (edit-insert e "x")))
                    (cons 1 (lambda (e lay) (edit-insert e "x")))
                    (cons 1/2 (lambda (e lay)
                                (edit-key e 'backspace '() lay 14)))
                    (cons 1/2 (lambda (e lay) (edit-key e 'delete '() lay 14)))
                    (cons 1/2 (lambda (e lay) (edit-insert e "pasted words ")))
                    (cons 1/2 (lambda (e lay)
                                (edit-key (edit-all (edit-text e)) 'backspace
                                          '() lay 14)))
                    (cons 0 (lambda (e lay)   ; three rows down, no change
                              (edit-move e (edit-row-last lay 3) #f))))])
         (for-all
          (lambda (which)
            (for-all
             (lambda (op)
               (let ([at (lambda (n)
                           (let ([text (worst-case which n)])
                             (keystroke-measures
                              text (exact (floor (* (car op) n))) (cdr op))))])
                 (let ([small (at 16384)] [big (at 65536)])
                   (or (and (<= small (* 4 17)) (<= big (* 4 17)))
                       (begin (printf "  ~a: ~a then ~a measures\n" which
                                      small big)
                              #f)))))
             ops))
          '(words none full))))

(check "Ctrl+End computes the rows to the end once, and a second one \
        measures none of them again"
       (let* ([n 0] [count (lambda (s) (set! n (+ n 1)) (m7 s))]
              [text (worst-case 'words 65536)]
              [lay (lay-of text 280 count)])
         (edit-layout-extend! lay 15)
         (let* ([e (edit-key (ed text 0) 'end '(ctrl) lay 14)]
                [r (edit-row-at lay (edit-caret e))] [first n])
           (edit-row-at lay (edit-caret e))
           (edit-key (ed text 0) 'end '(ctrl) lay 14)
           (and (= (edit-caret e) 65536) (edit-layout-done? lay)
                (> first 1000) (= n first)))))

;; Short lines, as in a log or base64: each a paragraph of its own.
(define (short-lines n)
  (substring (apply string-append
                    (map (lambda (i) (format "line ~a of short lines\n" i))
                         (iota (quotient n 20))))
             0 n))

(check "an edit takes back the rows past it: typed at the start or the \
        middle of 65,536 characters of words, or of short lines, or a \
        line deleted there, the rows to the end come back with a few \
        measured, and they are a whole wrap's"
       (for-all
        (lambda (text op)
          (let* ([n 0] [count (lambda (s) (set! n (+ n 1)) (m7 s))]
                 [lay (lay-of text 280 count)])
            (edit-layout-extend! lay (string-length text))
            (set! n 0)
            (let* ([e (op text)]
                   [lay (edit-layout-of lay (edit-text e) 280 #f count
                                        (edit-change e))])
              (edit-layout-extend! lay (string-length (edit-text e)))
              (or (and (<= n 20) (edit-layout-done? lay)
                       (equal? (rows-of lay)
                               (rows-of (lay-of (edit-text e) 280))))
                  (begin (printf "  ~a measures, ~a\n" n
                                 (substring (edit-text e) 0 50))
                         #f)))))
        (list (worst-case 'words 65536) (worst-case 'words 65536)
              (short-lines 65536) (short-lines 65536) (short-lines 65536))
        (list (lambda (t) (edit-insert (ed t 0) "x"))
              (lambda (t) (edit-insert (ed t 32768) "x"))
              (lambda (t) (edit-insert (ed t 3) "x"))
              (lambda (t) (edit-erase (ed t 30000) 30001))
              (lambda (t) (edit-erase (ed t 40 63) 0)))))

;; What an engine counts of a thunk: a tick for each procedure call or
;; turn of a loop, so a character looked at in a loop is one; a copy
;; (string-copy!, fxvector-copy) is one call.
(define (ticks thunk)
  ((make-engine thunk) 1000000000 (lambda (left . r) (- 1000000000 left))
   (lambda (e) +inf.0)))

(check "a keystroke's text work, in an engine's ticks, is about 500 a row \
        in view (8,500 for 17 rows) at 65,535 characters as at 16,383, in \
        each worst case, where a look at every character would be 16,383 \
        at least: the edit (as a description's box makes it), Tasks taking \
        the text from the box, the rows that follow it to the caret's \
        view, and the editor's line and column"
       (let ([ops (list (cons 0 (lambda (e lay) (edit-insert e "x" 65536)))
                        (cons 1/2 (lambda (e lay) (edit-insert e "x" 65536)))
                        (cons 1 (lambda (e lay) (edit-insert e "x" 65536)))
                        (cons 1/2 (lambda (e lay)
                                    (edit-insert e "\n" 65536)))
                        (cons 1/2 (lambda (e lay)
                                    (edit-key e 'backspace '() lay 14)))
                        (cons 1 (lambda (e lay)
                                  (edit-key e 'backspace '() lay 14)))
                        (cons 1/2 (lambda (e lay)
                                    (edit-key e 'delete '() lay 14))))])
         (define (work text k op)   ; the ticks of op at k in text
           (let* ([lay (lay-of text 280)]
                  [view! (lambda (lay caret)
                           (edit-layout-extend! lay (+ (edit-row-at lay caret)
                                                       15))
                           (edit-caret-x lay caret))]
                  [editor (make-tasks-editor #f #f #f text text #f #f)]
                  [e (ed text k)])
             (view! lay k)
             (tasks-editor-line-column editor e)
             (ticks (lambda ()
                      (let* ([e (op e lay)]
                             [d (tasks-normalize 'task-set! 'description
                                                 (edit-text e))]
                             [lay (edit-layout-of lay d 280 #f m7
                                                  (edit-change e))])
                        (view! lay (edit-caret e))
                        (tasks-editor-line-column editor e))))))
         (for-all
          (lambda (which)
            (for-all
             (lambda (op)
               (let ([at (lambda (n)
                           (let ([text (worst-case which n)])
                             (work text (exact (floor (* (car op) n)))
                                   (cdr op))))])
                 (let ([small (at 16383)] [big (at 65535)])
                   (or (< (max small big) (* 500 17))
                       (begin (printf "  ~a: ~a then ~a ticks\n" which
                                      small big)
                              #f)))))
             ops))
          '(words none full))))

(check "the editor's line and column, counted on from the last count, are \
        a plain count's through 3000 random edits, moves and clicks, \
        counted after each or after two"
       (let ([editor (make-tasks-editor #f #f #f "" "" #f #f)])
         (define (plainly t c)
           (let loop ([i 0] [line 1] [column 1])
             (cond [(= i c) (list line column)]
                   [(char=? (string-ref t i) #\newline)
                    (loop (+ i 1) (+ line 1) 1)]
                   [else (loop (+ i 1) line (+ column 1))])))
         (define (next e seed)   ; an edit, a move or a click
           (let*-values ([(t) (edit-text e)] [(n) (string-length t)]
                         [(ins x) (made-up (mod seed 5) seed "ab\n\n")])
             (values (case (mod (quotient seed 7) 6)
                       [(0 1) (edit-insert e ins)]
                       [(2) (edit-erase e (- (edit-caret e) 1))]
                       [(3) (edit-erase e (+ (edit-caret e) 1))]
                       [(4) (edit-move e (mod x (+ n 1)) (odd? x))]
                       [else (edit-at t (mod x (+ n 1)))])
                     (next-random x))))
         (let loop ([i 0] [seed 3] [e (ed "" 0)])
           (or (= i 3000)
               (let-values ([(line column)
                             (tasks-editor-line-column editor e)])
                 (and (equal? (list line column)
                              (plainly (edit-text e) (edit-caret e)))
                      (let*-values ([(e seed) (next e seed)]
                                    [(e seed) (if (zero? (mod i 5))
                                                  (next e seed)
                                                  (values e seed))])
                        (loop (+ i 1) seed e))))))))

(check "a search looks through a task's texts once for each change of \
        them: matched again, a 65,536-character description is not \
        searched, and changed, it is"
       (let ([t (make-task 0 "Title" (worst-case 'words 65536) 'todo
                           'feature 'normal #f '() #f '() '() 0 0)]
             [words (tasks-words "zebra")])
         (define (match) (tasks-match? t words #f #f #f #f #t))
         (let* ([first (ticks match)] [again (ticks match)])
           (task-description-set! t (string-append (task-description t)
                                                   " zebra"))
           (and (> first 65536) (< again 100) (match)))))

(check "wrapping measures a row about twice, not the paragraph's rest: a \
        6000-character paragraph and a 2000-character word measure under \
        5 characters per character"
       (let* ([n 0]
              [count (lambda (s) (set! n (+ n (string-length s))) (m7 s))]
              [measured (lambda (text)
                          (set! n 0)
                          (edit-wrap text 280 count)
                          (/ n (string-length text)))])
         (and (< (measured (apply string-append (make-list 1200 "word ")))
                 5)
              (< (measured (make-string 2000 #\W)) 5))))

(check "wrapping scans a row, not the rest of a long word: 100,000 \
        characters wrap within a handler's fuel, as one word or as words"
       (and (within-fuel? (lambda () (edit-wrap (make-string 100000 #\W) 280
                                                m7)))
            (within-fuel?
             (lambda ()
               (edit-wrap (apply string-append (make-list 20000 "word ")) 280
                          m7)))))

;; The index nearest x as plainly as it can be said: a character at a time.
(define (index-plainly lay r x)
  (let-values ([(s e) (edit-row lay r)])
    (let ([text (edit-layout-text lay)] [last (edit-row-last lay r)])
      (let loop ([j s])
        (if (or (>= j last)
                (< x (/ (+ (m7 (substring text s j))
                           (m7 (substring text s (+ j 1))))
                        2)))
            j
            (loop (+ j 1)))))))

(check "a click lands where a character at a time finds it, in log n \
        measures: 34 at most in a row of 100,000 characters"
       (let* ([n 0] [count (lambda (s) (set! n (+ n 1)) (m7 s))]
              [long (make-string 100000 #\W)]
              [at (edit-index-at (lay-of long #f count) 0 350003)])
         (and (= at 50000) (<= n 34)
              (for-all
               (lambda (text)
                 (let ([lay (lay-of text 30)])
                   (edit-layout-extend! lay (string-length text))
                   (for-all
                    (lambda (r)
                      (for-all (lambda (x)
                                 (= (edit-index-at lay r x)
                                    (index-plainly lay r x)))
                               (map (lambda (i) (- (/ i 2) 5)) (iota 90))))
                    (iota (edit-layout-count lay)))))
               '("" "a" "abc def" "aaa bbb ccc ddd" "ab\ncd\n"
                 "abcdefghijk")))))

(check "a wrapped label breaks a word wider than it, and its lines end \
        without the space a soft break leaves"
       (let-values ([(w h) (ui-label-size '(wrap) (make-string 200 #\W) 100)])
         (and (> h (* 5 (font-line-height 'ui)))
              (for-all (lambda (l) (<= (text-width l 'ui) 100))
                       (ui-label-lines (make-string 200 #\W) 100 'ui))
              (equal? (ui-label-lines "No task matches this, with Kind: Bug."
                                      120 'ui)
                      (text-wrap "No task matches this, with Kind: Bug."
                                 120 'ui)))))

(let ([soft (lay-of "aaa bbb ccc" 42)] [hard (lay-of "ab\ncd" 100)]
      [three (lay-of "abcdef\nab\nabcdef" 100)])
  (define (vert e lay dir) (state (edit-vertical e lay dir #f)))
  (check "a caret at a soft break shows on the next row, at a hard break on \
          its own; a click lands nearest a character's middle"
         (and (= 1 (edit-row-at soft 4)) (= 0 (edit-row-at soft 3))
              (= 0 (edit-row-at hard 2)) (= 1 (edit-row-at hard 3))
              (= 1 (edit-index-at (lay-of "abcd" 100) 0 10))
              (= 2 (edit-index-at (lay-of "abcd" 100) 0 11))
              (= 0 (edit-index-at (lay-of "abcd" 100) 0 3))))
  (check "Up and Down keep the goal across a short row; Up from the first \
          row goes to 0, Down from the last to the end; End stops before a \
          soft row's space"
         (let* ([e (ed "abcdef\nab\nabcdef" 5)]
                [d1 (edit-vertical e three 1 #f)]
                [d2 (edit-vertical d1 three 1 #f)])
           (and (= 9 (edit-caret d1)) (= 15 (edit-caret d2))
                (equal? (vert e three -1) '("abcdef\nab\nabcdef" 0 0))
                (equal? (vert d2 three 1) '("abcdef\nab\nabcdef" 16 16))
                (= 7 (edit-caret (edit-key (ed "aaa bbb ccc" 4) 'end '()
                                           soft 1)))))))

(check "Page Down and Up move a page of rows keeping the goal; past the \
        first or last row a page goes to it, and from it to the text's \
        start or end"
       (let* ([text (apply string-append
                           (map (lambda (i) (format "line ~2,'0d\n" i))
                                (iota 30)))]
              [lay (lay-of text 1000)]
              [at (lambda (line column) (+ (* 8 line) column))]
              [page (lambda (c k) (edit-caret (edit-key (ed text c) k '() lay
                                                        10)))])
         (and (= (page (at 2 3) 'page-down) (at 12 3))
              (= (page (at 12 3) 'page-up) (at 2 3))
              (= (page (at 5 3) 'page-up) (at 0 3))
              (= (page (at 0 3) 'page-up) 0)
              (= (page (at 25 3) 'page-down) (at 30 0))
              (= (page (at 30 0) 'page-down) (string-length text)))))

(check "edit-clean drops control characters, but a tab becomes a \
        space; without newlines they do too"
       (and (equal? (edit-clean "a\tb\r\nc\x1;" #t) "a b\nc")
            (equal? (edit-clean "a\tb\r\nc" #f) "a b c")
            (equal? (edit-clean "a\x7f;b" #t) "ab")))

(check "ui-flow places, wraps and centers"
       (and (equal? (call-with-values
                      (lambda () (ui-flow 0 0 100 5 '((10 . 10) (20 . 20)
                                                       (30 . 10))))
                      list)
                    '(((0 . 5) (15 . 0) (40 . 5)) 20))
            (equal? (call-with-values
                      (lambda () (ui-flow 0 0 40 5 '((10 . 10) (20 . 20)
                                                      (30 . 10))))
                      list)
                    '(((0 . 5) (15 . 0) (0 . 25)) 35))))

(check "ui-form puts a label beside its control, or over it where the \
        control would be narrower than its least; a hint goes under the \
        control, and a row without a label spans the form"
       (let* ([gap (ui-gap)] [lh (font-line-height 'ui)]
              [lw (+ (text-widest '("Name" "Kind") 'ui) gap gap)]
              [none (lambda (x y w) #f)]
              [rows (list (list "Name" 20 none)
                          (list "Kind" 30 none 'hint "Why")
                          (list #f (lambda (w) (quotient w 10)) none))]
              [walk (lambda (w)
                      (let* ([placed '()]
                             [bottom (ui-form-walk
                                      rows 0 0 w
                                      (lambda (row inline? lx ly lw lh cx cy
                                               cw ch hint hh)
                                        (set! placed
                                          (cons (list inline? cx cy cw ch)
                                                placed)))
                                      (lambda a #f))])
                        (cons bottom (reverse placed))))]
              [hh (let-values ([(w h) (ui-label-size '(hint wrap) "Why"
                                                     (- 400 lw))])
                    h)]
              [wide (walk 400)]
              [y2 (+ (max 20 lh) gap)]
              [y3 (+ (max (+ y2 30 4 hh) (+ y2 lh)) gap)]
              [narrow (walk (+ lw 100))])
         (and (equal? (cdr wide)
                      (list (list #t lw 0 (- 400 lw) 20)
                            (list #t lw y2 (- 400 lw) 30)
                            (list #f 0 y3 400 40)))
              (= (car wide) (+ y3 40) (ui-form-height rows 400))
              (equal? (cadr narrow) (list #f 0 (+ lh 4) (+ lw 100) 20)))))

(check "ui-suggestions ranks by segments, an exact name first, at most n; \
        none for nothing typed, nor the one that is what was typed"
       (and (equal? (ui-suggestions "abc" '("abcd" "abc" "xyz") 5)
                    '("abc" "abcd"))
            (member "draw-text-centered"
                    (ui-suggestions "dtc" '("draw-text-centered" "x") 5))
            (= (length (ui-suggestions "d" '("da" "db" "dc") 2)) 2)
            (null? (ui-suggestions "" '("a") 5))
            (null? (ui-suggestions "abc" '("abc") 5))))

(check "ui-table-fit gives the flexible column the rest, dropping \
        columns in order while it would be narrower than the least, the \
        others' flags kept"
       (let ([cols '((a "A" 50) (name "Name" #f) (b "B" 40 right)
                     (c "C" 30))])
         (and (equal? (ui-table-fit 300 cols '(c b a) 100)
                      '((a "A" 50) (name "Name" 180) (b "B" 40 right)
                        (c "C" 30)))
              (equal? (ui-table-fit 200 cols '(c b a) 100)
                      '((a "A" 50) (name "Name" 110) (b "B" 40 right)))
              (equal? (ui-table-fit 120 cols '(c b a) 100)
                      '((name "Name" 120))))))

(check "ui-table-step at both ends, by pages, from no row, with no rows"
       (equal? (map (lambda (a) (apply ui-table-step a))
                    '((0 5 2 up) (4 5 2 down) (#f 5 2 down) (#f 5 2 up)
                      (1 5 2 page-down) (4 5 2 page-down) (3 5 2 page-up)
                      (2 5 2 home) (2 5 2 end) (#f 0 2 down) (2 5 2 left)))
               '(0 4 0 4 3 4 1 0 4 #f #f)))

(check "dates: day numbers round-trip from 1970 to 2100; 2026-10-31 is a \
        Saturday; February's lengths; months added clamp the day"
       (and (let loop ([n 0])
              (or (> n (ui-date->day '(2100 12 31)))
                  (and (= n (ui-date->day (ui-day->date n))) (loop (+ n 1)))))
            (equal? (ui-day->date 0) '(1970 1 1))
            (= 5 (ui-week-day (ui-date->day '(2026 10 31))))
            (equal? (map (lambda (y) (ui-days-in-month y 2))
                         '(2024 2025 2100 2000))
                    '(29 28 28 29))
            (equal? (map (lambda (d k)
                           (ui-day->date (ui-add-months (ui-date->day d) k)))
                         '((2026 1 31) (2026 12 15) (2026 1 31)) '(1 1 -2))
                    '((2026 2 28) (2027 1 15) (2025 11 30)))))

(define (mk id title status kind priority who tags due . description)
  (make-task id title (if (pair? description) (car description) "") status
             kind priority who tags due '() '() 0 id))
(define t1 (mk 1 "Fix the menu" 'todo 'bug 'high "Pavel" '("ui") '(2026 11 2)))
(define t2 (mk 2 "Style system" 'doing 'feature 'urgent #f '("style" "kit") #f
               "parts and derived styles"))
(define t3 (mk 3 "Threads spec" 'todo 'chore 'low "Claude" '() '(2026 10 30)))
(define t4 (mk 4 "Old one" 'done 'feature 'normal "Pavel" '("ui") #f))
(define ts (list t1 t2 t3 t4))
(define (ids l) (map task-id l))

(check "tasks-sorted by every key both ways, stable, the empty last"
       (equal? (map (lambda (k)
                      (list (ids (tasks-sorted ts k 'up))
                            (ids (tasks-sorted ts k 'down))))
                    '(id title status kind priority assignee due updated))
               '(((1 2 3 4) (4 3 2 1)) ((1 4 2 3) (3 2 4 1))
                 ((1 3 2 4) (4 2 1 3)) ((1 2 4 3) (3 2 4 1))
                 ((2 1 4 3) (3 4 1 2)) ((3 1 4 2) (1 4 3 2))
                 ((3 1 2 4) (1 3 2 4)) ((1 2 3 4) (4 3 2 1)))))

(check "tasks-words: lowercase, each once, at most 16, each cut to 64 \
        characters"
       (and (equal? (tasks-words " B a  b C ") '("b" "a" "c"))
            (equal? (tasks-words (apply string-append
                                        (map (lambda (i) (format "w~a " i))
                                             (iota 40))))
                    (map (lambda (i) (format "w~a" i)) (iota 16)))
            (equal? (tasks-words (string-append (make-string 100 #\A) " "
                                                (make-string 70 #\a)))
                    (list (make-string 64 #\a)))))

(check "tasks-match?: near misses of 64 and 1,001 characters looked for in \
        a 100,000-character title within a handler's fuel"
       (let ([t (mk 5 (make-string 100000 #\a) 'todo 'bug 'low #f '() #f)])
         (for-all (lambda (n)
                    (let ([words (tasks-words
                                  (string-append (make-string (- n 1) #\a)
                                                 "b"))])
                      (within-fuel?
                       (lambda () (tasks-match? t words #f #f #f #f #t)))))
                  '(64 1001))))

(define (matching words . filters)
  (ids (filter (lambda (t) (apply tasks-match? t (tasks-words words) filters))
               ts)))
(check "tasks-match?: by id, title, description, tag and assignee; each \
        filter; words all match; done tasks hidden"
       (and (equal? (matching "task-1" #f #f #f #f #t) '(1))
            (equal? (matching "4" #f #f #f #f #t) '(4))
            (equal? (matching "MENU" #f #f #f #f #t) '(1))
            (equal? (matching "derived" #f #f #f #f #t) '(2))
            (equal? (matching "kit" #f #f #f #f #t) '(2))
            (equal? (matching "claude" #f #f #f #f #t) '(3))
            (equal? (matching "" 'bug #f #f #f #t) '(1))
            (equal? (matching "" #f 'low #f #f #t) '(3))
            (equal? (matching "" #f #f "pavel" #f #t) '(1 4))
            (equal? (matching "" #f #f 'none #f #t) '(2))
            (equal? (matching "" #f #f #f "ui" #t) '(1 4))
            (equal? (matching "fix menu" #f #f #f #f #t) '(1))
            (equal? (matching "fix style" #f #f #f #f #t) '())
            (equal? (matching "" #f #f #f #f #f) '(1 2 3))))

(check "tasks-move: across columns, up and down a column, to the end, into \
        an empty column"
       (and (equal? (ids (tasks-move ts t1 'doing #f)) '(2 1 3 4))
            (equal? (ids (tasks-move ts t3 'todo t1)) '(3 1 2 4))
            (equal? (ids (tasks-move ts t1 'todo #f)) '(2 3 1 4))
            (equal? (ids (tasks-move ts t1 'done #f)) '(2 3 4 1))
            (equal? (ids (tasks-move ts t2 'review #f)) '(1 3 4 2))))

(check "tasks-slot: above the first card, between cards, past the last, \
        with none"
       (and (equal? (map (lambda (py) (tasks-slot '(8 60 120) '(40 40 40) py))
                         '(10 70 500))
                    '(0 1 3))
            (= 0 (tasks-slot '() '() 100))))

(check "an assignee is one name whatever its case and the spaces around \
        it: the filter lists it once and finds every spelling"
       (let ([t5 (mk 5 "Typed" 'todo 'bug 'low "pavel " '() #f)])
         (and (equal? (tasks-names (list t1 t5 t3)) '("Claude" "Pavel"))
              (equal? (tasks-names (list t5 t1)) '("pavel"))
              (tasks-match? t5 '() #f #f "Pavel" #f #t)
              (tasks-match? t1 '() #f #f " pavel" #f #t))))

(check "a card's tags: as many chips as fit beside \"+k\" for the rest, the \
        first cut when even it does not fit, never past the card's edge"
       (let ([fits?
              (lambda (w tags)
                (let-values ([(ws k) (tasks-card-tags
                                      w (mk 6 "x" 'todo 'bug 'low #f tags #f))])
                  (and (pair? ws) (= (+ (length ws) k) (length tags))
                       (<= (+ (apply + ws) (* 4 (- (length ws) 1))
                              (if (> k 0)
                                  (+ 4 (text-width (format "+~a" k)
                                                   'ui-small))
                                  0))
                           (- w 20))
                       (list (length ws) k))))])
         (and (equal? (fits? 200 '("ui" "kit")) '(2 0))
              (equal? (fits? 145 '("abcdefghijkl" "abcdefgh" "b")) '(1 2))
              (equal? (fits? 200 '("abcdefghijklmnopqrstuvwx" "b")) '(1 1))
              (equal? (fits? 100 '("abcdefghijklmnopqrstuvwx")) '(1 0)))))

(check "tasks-neighbor, tasks-tag, ui-initials"
       (and (eq? (tasks-neighbor ts t2) t3) (eq? (tasks-neighbor ts t4) t3)
            (not (tasks-neighbor (list t1) t1))
            (equal? (map tasks-tag '("  My Tag " "a,b" "" "   "))
                    '("my-tag" "ab" #f #f))
            (= 24 (string-length (tasks-tag (make-string 30 #\a))))
            ;; a space at the cut would end it in "-"
            (equal? (tasks-tag "dÜnï Cödé Long Tag Name Here")
                    "dünï-cödé-long-tag-name")
            (equal? (tasks-tag "ends-in-") "ends-in-")
            (equal? (map ui-initials '("Pavel Uvarov" "Claude"
                                       "ada lovelace byron"))
                    '("PU" "C" "AB"))))

(check "a task's tags: made by tasks-tag, each once, in the order given, \
        at most 64"
       (let ([names (lambda (n) (map (lambda (i) (format "t~a" i)) (iota n)))])
         (and (equal? (tasks-normalize 'set-task! 'tags
                                       '(" UI" "perf" "ui" "" "," "Perf "))
                      '("ui" "perf"))
              (equal? (tasks-normalize 'set-task! 'tags (names 100))
                      (names 64)))))

(check "tasks-due-label and tasks-overdue?"
       (let ([today '(2026 10 31)])
         (and (equal? (map (lambda (d) (tasks-due-label d today))
                           '((2026 10 31) (2026 11 1) (2026 10 30)
                             (2026 11 15) (2027 1 2)))
                      '("Today" "Tomorrow" "Yesterday" "Nov 15" "Jan 2, 2027"))
              (tasks-overdue? t3 today) (not (tasks-overdue? t1 today))
              (not (tasks-overdue? (mk 5 "x" 'done 'bug 'low #f '()
                                       '(2026 1 1))
                                   today)))))

(check "ids are never reused, and the REPL's procedures name what is valid"
       (let* ([a (add-task! "first")] [_ (delete-task! a)]
              [b (add-task! "second")])
         (delete-task! b)
         (and (> (task-id b) (task-id a))
              (equal? (guard (c [#t (condition->string c)])
                        (set-task! (car *tasks*) 'priority 'hgih))
                      "Exception in set-task!: priority must be one of \
                       urgent high normal low, not hgih"))))

(check "the REPL's edges: a blank name finds no task; an assignee filter \
        that is not a name says so; a description is cleaned as typing \
        cleans it; an assignee is trimmed, but the details' field keeps a \
        space typed after a name; a blank one is nobody; a name is at most \
        64 characters"
       (let ([t (add-task! "Edges" 'description "a\r\nb\tc"
                           'assignee "  Ada  ")]
             [v (tasks-view-new (make-ui))])
         (let ([ok (and (not (find-task "")) (not (find-task "  "))
                        (equal? (guard (c [#t (condition->string c)])
                                  (tasks-list 'assignee 'pavel))
                                "Exception in tasks-list: assignee must be \
                                 a name or none, not pavel")
                        (list? (tasks-list 'assignee 'none))
                        (equal? (task-description t) "a\nb c")
                        (equal? (task-assignee t) "Ada")
                        (equal? (task-assignee (set-task! t 'assignee " B "))
                                "B")
                        (begin (task-set! v t 'assignee " Ada ")
                               (equal? (task-assignee t) "Ada "))
                        (not (task-assignee (set-task! t 'assignee "  ")))
                        (let ([long (make-string 99 #\a)])
                          (= 64 (string-length
                                 (task-assignee
                                  (set-task! t 'assignee long))))))])
           (delete-task! t)
           ok)))

(check "a description holds at most 65,536 characters: what the REPL \
        gives is cut to them"
       (let ([t (add-task! "Long" 'description (make-string 70000 #\a))])
         (let ([n (string-length (task-description t))])
           (set-task! t 'description (make-string 65536 #\b))
           (let ([ok (and (= n 65536)
                          (= 65536 (string-length (task-description t))))])
             (delete-task! t)
             ok))))

(check "the seed's long descriptions: the README and the kit's source \
        cut to the most, the backlog as one paragraph and a base64 \
        blob with no spaces, the same at every seeding; with the files \
        gone, the paragraph"
       (let* ([text (lambda (what) (tasks-seed-text what))]
              [readme (call-with-input-file
                        (string-append *schevana-root* "/README.md")
                        get-string-all)]
              [has? (lambda (s c)
                      (exists (lambda (i) (char=? (string-ref s i) c))
                              (iota (string-length s))))]
              [blob (text 'blob)] [paragraph (text 'changelog)]
              [gone (fluid-let ([*schevana-root* "/no/such/tree"])
                      (text 'readme))])
         (and (equal? (text 'readme)
                      (substring readme 0 (min (string-length readme)
                                               tasks-description-max)))
              (= 65536 (string-length (text 'kit-source)))
              (= 65536 (string-length paragraph) (string-length blob))
              (not (has? paragraph #\newline)) (not (has? blob #\space))
              (string-prefix? "Ozs7IGtpdHMvdWkuc3M" blob)   ; ";;; kits/ui.ss"
              (equal? blob (text 'blob)) (equal? gone paragraph)
              (for-all (lambda (id)
                         (<= (string-length (task-description (find-task id)))
                             tasks-description-max))
                       '(27 28 29 30)))))

(check "a tooltip and a dialog show at most six lines of a long text, the \
        last cut with …"
       (let ([long (apply string-append (make-list 300 "words "))])
         (let-values ([(lines cut?) (ui-wrap-lines long 100 'ui 3)]
                      [(all whole?) (ui-wrap-lines "a b" 100 'ui 3)]
                      [(tw th) (ui-tooltip-size long)]
                      [(dw dh) (ui-dialog-size "Delete?" long '("OK"))]
                      [(dw1 dh1) (ui-dialog-size "Delete?" "short" '("OK"))])
           (and (= 3 (length lines)) cut?
                (string=? "…" (substring (caddr lines)
                                         (- (string-length (caddr lines)) 1)
                                         (string-length (caddr lines))))
                (equal? all '("a b")) (not whole?)
                (= th (+ 10 (* 6 (font-line-height 'ui-small))))
                (< (abs (- dh dh1 (* 5 (font-line-height 'ui)))) 1)))))

(check "blocked-by: ids, each once, of tasks named any way; whom a task \
        blocks worked out; a cycle refused, the error naming it, and the \
        task unchanged; a deleted task blocks nothing"
       (let* ([a (add-task! "Dep A")]
              [b (add-task! "Dep B" 'blocked-by (list a))]
              [c (add-task! "Dep C" 'blocked-by (list (task-id b) (task-label a)
                                                      (task-id b)))]
              [refused (lambda (x ids)
                         (guard (e [#t (condition->string e)])
                           (set-task! x 'blocked-by ids)))]
              [cycle (lambda ts
                       (format "Exception in set-task!: ~a would wait for \
                                itself: ~a (each waits for the next)"
                               (task-label (car ts))
                               (string-join (map task-label ts) " → ")))])
         (let ([ok (and (equal? (task-blocked-by c) (map task-id (list b a)))
                        (equal? (task-blockers c) (list b a))
                        (equal? (task-blocks a) (list b c))
                        (null? (task-blocks c))
                        (equal? (refused a (list c)) (cycle a c b a))
                        (equal? (refused a (list a)) (cycle a a))
                        (null? (task-blocked-by a))
                        (raises? (lambda () (set-task! a 'blocked-by '(0))))
                        (raises? (lambda () (set-task! a 'blocked-by 3)))
                        (begin (delete-task! b)
                               (and (equal? (task-blocked-by c)
                                            (list (task-id a)))
                                    (equal? (task-blocks a) (list c)))))])
           (for-each delete-task! (list a c))
           ok)))

;; Made-up tasks: id, then the ids it waits for.
(define (linked . specs)
  (map (lambda (s)
         (let ([t (mk (car s) (format "T~a" (car s)) 'todo 'bug 'low #f '()
                      #f)])
           (task-blocked-by-set! t (cdr s))
           t))
       specs))

(check "tasks-forest: the roots are the tasks nothing waits for, then any \
        cycle left over; a blocker shared by several shows its own under \
        the first, depth first; tasks-cycle finds the path back"
       (let ([ts (linked '(1 2 3) '(2) '(3 5) '(4 3) '(5) '(6) '(7 8) '(8 7))])
         (let-values ([(roots homes order) (tasks-forest ts)])
           (let ([by-id (tasks-id-table ts)])
             (and (equal? roots '(1 4 6 7))
                  (equal? order '(1 2 3 5 4 6 7 8))
                  (equal? (map (lambda (id) (hashtable-ref homes id 'none))
                               '(1 2 3 5 4 6 7 8))
                          '(#f 1 1 3 #f #f #f 7))
                  (equal? (ids (tasks-cycle by-id (list-ref ts 2) '(4)))
                          '(3 4 3))
                  (equal? (ids (tasks-cycle by-id (list-ref ts 4) '(1)))
                          '(5 1 3 5))
                  (not (tasks-cycle by-id (car ts) '(6)))
                  (equal? (sort < (vector->list
                                   (hashtable-keys
                                    (tasks-waiters (tasks-inverse ts)
                                                   (list-ref ts 4)))))
                          '(1 3 4))
                  (equal? (ids (hashtable-ref (tasks-inverse ts) 3 '()))
                          '(1 4)))))))

(check "the seed's links: no cycle; (tasks-tree) nests what each task waits \
        for, a shared blocker under its first waiter and its id under the \
        others; Add offers what would make no cycle, nor is done"
       (let ([tree (tasks-tree)] [choices (map task-id (tasks-blocker-choices
                                                       (find-task 14)))])
         (let-values ([(roots homes order)
                       (tasks-forest (tasks-board-order *tasks*))])
           (and (= (length order) (length *tasks*))
                (for-all (lambda (id) (null? (task-blocks id))) roots)
                (equal? (assv 11 tree) '(11 (9)))
                (equal? (assv 13 tree) '(13 (31) (10)))
                (equal? (assv 17 tree) '(17 31))
                (equal? (assv 22 tree) '(22 (14 (33 9))))
                (equal? (assv 15 tree) '(15 (32)))
                (not (find (lambda (id) (memv id '(14 22 33 1 32))) choices))
                (memv 9 choices) (memv 16 choices) #t))))

(check "what is worked out from which tasks there are, their order, \
        statuses and links is kept while only a title or a description \
        changes, and worked out again when a link or a status does"
       (let* ([forest (tasks-whole-forest)] [order (tasks-ordered)]
              [kept? (begin (set-task! 13 'title "Kept" 'description "x")
                            (and (eq? forest (tasks-whole-forest))
                                 (eq? order (tasks-ordered))))]
              [linked (begin (set-task! 16 'blocked-by '(12))
                             (tasks-whole-forest))]
              [blocks (task-blocks 12)])
         (set-task! 16 'blocked-by '())
         (let* ([moved (begin (set-task! 16 'status 'review) (tasks-ordered))]
                [ok (and kept? (not (eq? linked forest))
                         (memq (find-task 16) blocks) (not (eq? moved order))
                         (eq? (find-task 16)
                              (car (last-pair (tasks-in 'review moved)))))])
           (tasks-reset!)
           ok)))

(check "Add's menu: the choices whose id or title holds what was typed, \
        the one it names by id first, as many as there is room for, the \
        last saying how many more"
       (let* ([cs (map (lambda (i)
                         (mk (+ 1 i) (format "Chain ~a" (- 30 i)) 'todo
                             'feature 'normal #f '() #f))
                       (iota 30))]
              [picked #f]
              [labels (lambda (f room)
                        (map car (tasks-blocker-entries
                                  cs f room (lambda (c) (set! picked c)))))])
         (and (equal? (labels "" 4)
                      '("TASK-1  Chain 30" "TASK-2  Chain 29" "TASK-3  Chain 28"
                        "… 27 more: type to narrow"))
              (equal? (labels "chain 2" 3)
                      '("TASK-2  Chain 29" "TASK-3  Chain 28"
                        "… 9 more: type to narrow"))
              (equal? (labels "task-12" 30) '("TASK-12  Chain 19"))
              (equal? (labels "20" 3)
                      '("TASK-20  Chain 11" "TASK-11  Chain 20"))
              (null? (labels "zz" 5))
              (let ([pick (cdar (tasks-blocker-entries
                                 cs "TASK-7" 5 (lambda (c) (set! picked c))))])
                (pick)
                (eq? picked (list-ref cs 6))))))

;; What a draw by thunk shows as text: ((x . string) ...), in order.
(define (texts-drawn thunk)
  (let ([drawn '()] [plain draw-text])
    (dynamic-wind
      (lambda ()
        (set! draw-text (lambda (x y s . more)
                          (set! drawn (cons (cons x s) drawn))
                          (apply plain x y s more))))
      (lambda () (image 400 40 1 thunk))
      (lambda () (set! draw-text plain)))
    (reverse drawn)))
(define (strings-drawn thunk) (map cdr (texts-drawn thunk)))

(check "four-digit ids keep clear of the titles in the Tree, three digits \
        wide at least"
       (let ([next *tasks-next-id*] [t (find-task 31)])
         (define (room)   ; from the id's start to the title's
           (let ([texts (texts-drawn
                         (lambda () (tasks-draw-node 0 0 400 30 '() t #f)))])
             (- (car (cadr texts)) (car (car texts)))))
         (let ([seed (room)])
           (set! *tasks-next-id* 1234)
           (let* ([new (add-task! "Four digits")] [wide (room)])
             (delete-task! new)
             (set! *tasks-next-id* next)
             (and (= seed (+ 8 (text-width "TASK-000" 'mono-small)))
                  (>= wide (+ 8 (text-width "TASK-1234" 'mono-small)))
                  (= (room) seed))))))

(check "a later row's title keeps at least half its room: the note where \
        its own row is gets shorter, then goes, as the cell narrows"
       (let* ([t (find-task 31)] [title (tasks-shown-title t)]
              [long (text-width "↑ under TASK-13" 'ui-small)]
              [short (text-width "↑ TASK-13" 'ui-small)]
              [w (lambda (room)   ; the cell's width for that room
                   (+ room (* 2 (ui-table-cell-inset)) 8
                      (text-width "TASK-100" 'mono-small)))]   ; the seed's
              [shown (lambda (room)   ; => (title-shown note ...)
                       (cdr (strings-drawn
                             (lambda ()
                               (tasks-draw-node 0 0 (w room) 30 '(reference)
                                                t "TASK-13")))))]
              [rooms (list 1000 (+ long short 16) (+ short 8))]
              [all (map shown rooms)])
         (and (equal? (map cdr all)
                      '(("↑ under TASK-13") ("↑ TASK-13") ()))
              (> (text-width title 'ui) (/ (+ long short 16) 2))
              (for-all (lambda (s room)   ; less at most what a cut takes
                         (>= (+ (text-width (car s) 'ui) (text-width "W…" 'ui))
                             (min (text-width title 'ui) (/ room 2))))
                       all rooms))))

(check "a record of task's from before a reload that changed its fields is \
        carried over by name, a new field empty"
       (let ([rtd (make-record-type-descriptor
                   'task #f 'units-old-task #f #f
                   '#((immutable id) (immutable title) (immutable checklist)
                      (immutable created)))])
         (let ([t (tasks-carried ((record-constructor
                                   (make-record-constructor-descriptor
                                    rtd #f #f))
                                  7 "Kept" '(("a" . #t)) 99))])
           (and (task? t) (= 7 (task-id t)) (equal? "Kept" (task-title t))
                (equal? '(("a" . #t)) (task-checklist t))
                (null? (task-blocked-by t)) (= 99 (task-created t))
                (eq? 'todo (task-status t)) (eq? t (tasks-carried t))))))

;; A tree of symbols: what each has under it.
(define tree-kids '((a b c) (b d) (c) (d)))
(define (tree-rows expanded?)
  (map (lambda (r) (list (ui-tree-row-node r) (ui-tree-row-depth r)
                         (ui-tree-row-parent r) (ui-tree-row-kids? r)
                         (ui-tree-row-expanded? r)))
       (vector->list (ui-tree-rows '(a) (lambda (n) (cdr (assq n tree-kids)))
                                   expanded?))))

(check "a tree's rows: the expanded nodes' children, depth first, and only \
        theirs asked for; a key's step: Up, Down, End and Page Down as a \
        table's, Right expands or goes to the first child, Left collapses or \
        goes to the parent, Space toggles, Return opens"
       (let* ([asked '()]
              [rows (ui-tree-rows '(a)
                                  (lambda (n)
                                    (set! asked (cons n asked))
                                    (cdr (assq n tree-kids)))
                                  (lambda (n) (not (eq? n 'b))))]
              [all (ui-tree-rows '(a) (lambda (n) (cdr (assq n tree-kids)))
                                 (lambda (n) #t))]
              [step (lambda (i key) (ui-tree-step all i 2 key))])
         (and (equal? (tree-rows (lambda (n) #t))
                      '((a 0 #f #t #t) (b 1 0 #t #t) (d 2 1 #f #f)
                        (c 1 0 #f #f)))
              (equal? (tree-rows (lambda (n) #f)) '((a 0 #f #t #f)))
              (= 3 (vector-length rows)) (not (memq 'd asked))
              (equal? (map (lambda (a) (apply step a))
                           '((0 down) (0 up) (#f down) (1 end) (0 page-down)
                             (0 right) (1 right) (2 right) (0 left) (2 left)
                             (3 left) (1 #\space) (2 #\space) (2 return)
                             (#f right) (#f left)))
                      '((select . 1) (select . 0) (select . 0) (select . 3)
                        (select . 2) (select . 1) (select . 2) #f
                        (collapse . 0) (select . 1) (select . 0)
                        (collapse . 1) #f (open . 2) #f #f))
              (equal? (ui-tree-step rows 1 2 'right) '(expand . 1))
              (equal? (ui-tree-step rows 1 2 #\space) '(expand . 1))
              (= 1 (ui-tree-index rows 'b)) (not (ui-tree-index rows 'd)))))

(check "a row under another at any depth, and not under its siblings"
       (let ([all (ui-tree-rows '(a) (lambda (n) (cdr (assq n tree-kids)))
                                (lambda (n) #t))])   ; a b d c
         (and (ui-tree-under? all 2 0) (ui-tree-under? all 2 1)
              (ui-tree-under? all 3 0) (not (ui-tree-under? all 3 1))
              (not (ui-tree-under? all 1 2)) (not (ui-tree-under? all 0 0))
              (not (ui-tree-under? all #f 0)))))

(check "a dimmed tree row shades its indentation and twisty as the cells \
        shade themselves, and nothing of its cell; selected, it is not \
        dimmed"
       (let* ([cx (cadr (assq 'cell (ui-tree-areas 0 0 200 30 1)))]
              [row (lambda (flags)
                     (image 300 30 1
                            (lambda ()
                              (fill-rect 0 0 300 30 'bg-1)
                              (ui-draw-tree-row 0 0 300 30 flags 200 1))))]
              [cell (lambda (flags)
                      (image 300 30 1
                             (lambda ()
                               (fill-rect 0 0 300 30 'bg-1)
                               (ui-draw-dim 0 0 cx 30 flags))))]
              [plain (row '(kids expanded))] [dim (row '(kids expanded dim))]
              [picked (row '(kids expanded selected))]
              [dim-picked (row '(kids expanded dim selected))]
              [shade (cell '(dim))])
         (and (> (max-diff plain dim (list cx 0 300 30)) 0)
              (= 0 (max-diff plain dim (list 0 0 cx 30)))
              (= 0 (max-diff picked dim-picked))
              (= (pixel-at dim 2 2) (pixel-at shade 2 2))
              (not (= (pixel-at dim 2 2) (pixel-at plain 2 2))))))

(check "a deep row's indentation stops at half its column, so its cell \
        keeps room"
       (let* ([at (lambda (depth k)
                    (cdr (assq k (ui-tree-areas 0 0 200 20 depth))))]
              [twisty (at 1 'twisty)] [cell (at 1 'cell)] [deep (at 500 'cell)])
         (and (< (car twisty) (car cell))
              (= (+ (car cell) (caddr cell)) 200)
              (>= (caddr deep) 80)
              (equal? deep (at 1000 'cell)))))

(let ([at (lambda (key)
            (cdr (assq key (ui-calendar-areas 0 0 230 0))))])
  (set-theme! 'ui-font-size 24)
  (let-values ([(cw ch) (ui-calendar-size)])
    (let ([prev (at 'prev)] [week (at 'week)] [today (at 'today)])
      (set-theme! 'ui-font-size 13)
      (check "the calendar at 24 px fonts: the weekdays below its arrows, \
              Today inside it"
             (and (>= (cadr week) (+ (cadr prev) (cadddr prev)))
                  (<= (+ (cadr today) (cadddr today)) ch))))))

(let ([v (tasks-view-new (make-ui))])
  (define (mode w) (call-with-values (lambda () (tasks-layout v w 700 44))
                     (lambda (m view details) m)))
  (let ([at-13 (list (mode 1205) (mode 760))])
    (set-theme! 'ui-font-size 24)
    (let ([at-24 (list (mode 1205) (mode 2400))])
      (set-theme! 'ui-font-size 13)
      (check "tasks-layout: the details beside the view when they fit, at 13 \
              and 24 px fonts"
             (equal? (list at-13 at-24) '((wide narrow) (narrow wide)))))))

;; A keystroke in 13's description, Tasks maximized, with a long title on
;; TASK-10, which 13 and others wait for (cards, rows and tooltips fit its
;; title): the characters it measures do not grow with that title.
(let* ([w (tasks)] [v (window-ref w 'state)] [ui (window-ref w 'ui)])
  (define (measured mode title)
    (set-task! 10 'title title)
    (set-task! 13 'description "")
    (tasks-view-mode-set! v mode)
    (tasks-select! v (find-task 13))
    (ui-focus! ui 'description 0)
    (invalidate! w)
    (steps 3)
    (characters-measured (lambda () (inject! '(text "a")) (steps 1))))
  (maximize-window! w)
  (steps 2)
  (let ([counts (map (lambda (mode)
                       (map (lambda (make) (measured mode (make 10000)))
                            (list words-of (lambda (n) (make-string n #\W))
                                  (lambda (n) (words-of (* 10 n)))
                                  (lambda (n) (make-string (* 10 n) #\W)))))
                     '(board list tree))])
    (tasks-reset!)
    (close-window! w)
    (steps 2)
    (check (format "a keystroke in Tasks measures as many characters with a \
                    100,000-character title on a task others wait for as \
                    with one of 10,000, in the Board, the List and the Tree, \
                    words or one long word: ~a" counts)
           (for-all (lambda (c) (and (= (car c) (caddr c))
                                     (= (cadr c) (cadddr c))))
                    counts))))

;;; ------------------------------------------------------------------
;;; surfaces and strips

;; The canvas's pixel at logical point (x, y).
(define (canvas-pixel x y)
  (cairo-surface-flush *canvas*)
  (pixel-at *canvas* (exact (floor (* x *scale*)))
            (exact (floor (* y *scale*)))))

;; With no surface registered (no desktop layer) the world draws its
;; windows on black, maximizes them to the whole screen, and a press,
;; a key or the wheel where nothing is goes nowhere.
(let* ([ss *surfaces*] [strips *strips*] [keys 0]
       [w (open-window "Alone" 'size '(200 . 100) 'pos '(300 . 200)
                       'draw (lambda (win cw ch)
                               (fill-rect 0 0 cw ch #x336699))
                       'key (lambda (win key mods) (set! keys (+ keys 1))))])
  (set! *surfaces* '())
  (set! *strips* '())
  (invalidate!)
  (steps 1)
  (let-values ([(cx cy cw ch) (content-rect w)])
    (let ([inside (canvas-pixel (+ cx 50) (+ cy 50))]
          [around (map (lambda (p) (canvas-pixel (car p) (cdr p)))
                       '((5 . 5) (640 . 790) (1270 . 400)))])
      (inject! '(mouse-move 20 400) '(mouse-down 20 400 left 1)
               '(mouse-up 20 400 left) '(wheel 0 1) '(key-down #\a ()))
      (steps 1)
      (maximize-window! w)
      (let ([whole (list (window-x w) (window-y w) (window-w w) (window-h w))]
            [hover *hover*])
        (set! *surfaces* ss)
        (set! *strips* strips)
        (close-window! w)
        (steps 1)
        (check (format "with no surface registered the windows are drawn on \
                        black (#x~x, ~s), maximize to the screen (~s), and \
                        input where nothing is goes nowhere (~s; keys \
                        to the window ~a)"
                       inside around whole hover keys)
               (and (= inside #xff336699)
                    (equal? around '(#xff000000 #xff000000 #xff000000))
                    (equal? whole (list 0 0 (screen-w) (screen-h)))
                    (not hover) (= keys 1)))))))

;; A surface of one's own with a strip on the left: it is drawn over the
;; windows, takes the presses and releases on it, and maximized windows
;; go beside it.
(let* ([pressed '()]
       [w (open-window "Beside" 'size '(200 . 100) 'pos '(300 . 200))])
  (define-surface dock 15
    'draw (lambda () (fill-rect 0 0 64 (screen-h) #xcc3300))
    'box (lambda () (values 0 0 64 (screen-h)))
    'at (lambda (x y) (and (< x 64) 'dock))
    'mouse (lambda (kind what x y button clicks)
             (set! pressed (cons (list kind what button) pressed))))
  (define-strip dock 'left (lambda () 64))
  (maximize-window! w)
  (steps 1)
  (let-values ([(dx dy dw dh) (desktop-rect)])
    (let ([at (list (window-x w) (window-y w) (window-w w) (window-h w))]
          [px (canvas-pixel 30 400)])
      (inject! '(mouse-move 30 400) '(mouse-down 30 400 left 1)
               '(mouse-up 30 400 left))
      (steps 1)
      (let ([hover *hover*])
        (set! *surfaces* (remp (lambda (s) (eq? (surface-name s) 'dock))
                               *surfaces*))
        (set! *strips* (remp (lambda (s) (eq? (car s) 'dock)) *strips*))
        (wm-screen-resized!)
        (let ([back (window-x w)])
          (close-window! w)
          (steps 1)
          (check (format "a surface with a strip on the left: maximized \
                          windows beside it ~s, drawn over them (#x~x), \
                          its presses ~s, hovered ~s; gone, they fill the \
                          left again (~a)" at px pressed hover back)
                 (and (equal? at (list 64 (topbar-height) (- (screen-w) 64)
                                       (- (screen-h) (topbar-height)
                                          (taskbar-height))))
                      (equal? (list dx dy dw dh) at)
                      (= px #xffcc3300)
                      (equal? pressed '((up dock left) (down dock left)
                                        (move dock #f)))
                      (equal? hover '(surface dock dock))
                      (= back 0))))))))

;;; ------------------------------------------------------------------
;;; settings in layers

;; thunk run with mac given these settings too (its own options, say);
;; your changes and Overrides cleared before and after.
(define (with-mac-settings settings thunk)
  (let ([plain *styles*])
    (dynamic-wind
      (lambda ()
        (register-style! 'mac "Mac"
                         (append settings (style-settings (find-style 'mac))))
        (set-style! 'mac)
        (reset-theme!))
      thunk
      (lambda ()
        (set! *styles* plain)
        (reset-theme!)))))

;; The accent and where it comes from, after each layer gives one.
(check "a setting comes from the first layer that has it: the Overrides, \
        your changes to the style, the style, its palette, the built-ins"
       (let ([at (lambda () (list (theme 'accent) (theme-source 'accent)))])
         (equal?
          (list (with-mac-settings '() at)
                (with-mac-settings '()
                  (lambda () (set-theme! 'palette 'nord) (at)))
                (with-mac-settings '(accent #x112233)
                  (lambda () (set-theme! 'palette 'nord) (at)))
                (with-mac-settings '(accent #x112233)
                  (lambda () (set-theme! 'accent #x445566) (at)))
                (with-mac-settings '(accent #x112233)
                  (lambda ()
                    (set-theme! 'accent #x445566)
                    (override! 'accent #x778899)
                    (let ([over (at)])
                      (override! 'accent)
                      (let ([cleared (at)])
                        (reset-style! 'accent)
                        (list over cleared (at)))))))
          '((#x7aa2f7 (built-in #x7aa2f7))
            (#x88c0d0 (palette nord #x88c0d0))
            (#x112233 (style mac #x112233))
            (#x445566 (changes mac #x445566))
            ((#x778899 (overrides #x778899))
             (#x445566 (changes mac #x445566))
             (#x112233 (style mac #x112233)))))))

;; A style that lists its options honors only those of the common ones:
;; the others keep its value under your changes and Overrides; keys that
;; are not common options are always yours.
(check "a style honors the common options it lists, and every other key"
       (equal?
        (with-mac-settings '(options (accent) corner-radius 3)
          (lambda ()
            (override! 'corner-radius 12)
            (set-theme! 'ui-font-size 20)
            (override! 'accent #x778899)
            (set-theme! 'red #x010203)
            (map theme '(corner-radius ui-font-size accent red))))
        '(3 13 #x778899 #x010203)))

(check "a rule computed from itself is named, and the theme stays"
       (with-mac-settings '()
         (lambda ()
           (set-changes! 'mac (list 'loop-a (theme-rule (theme 'loop-b))
                                    'loop-b (theme-rule (theme 'loop-a))))
           (let* ([before *theme*]
                  [msg (guard (c [#t (condition->string c)])
                         (theme-changed!)
                         #f)])
             (set-changes! 'mac '())
             (and msg (string-contains-ci? msg "computed from itself")
                  (or (string-contains-ci? msg "loop-a")
                      (string-contains-ci? msg "loop-b"))
                  (eq? *theme* before))))))

(check "a base color changed re-derives what its rules derive from it"
       (with-mac-settings '()
         (lambda ()
           (set-theme! 'accent #xff9e64)
           (set-theme! 'bg-3 #x404040)
           (and (= (theme 'selection) (mix #xff9e64 'bg-1 0.65))
                (= (theme 'window-border-focus) (mix #x404040 #xff9e64 0.45))
                (= (theme 'panel-hover) #x404040)
                (= (theme 'button-idle) (mix #x404040 'text 0.15))))))

;; Files today's tree wrote (tests' fixtures, from .work): Tokyo Night
;; with an accent and a radius, Nord with a radius, Genera with its
;; palette and an accent of its own, and one naming a style and a palette
;; since removed. Each loads to what today's tree resolved from it: its
;; own values, the built-in ones elsewhere; its style and palette chosen
;; (mac and Tokyo Night where gone), and only your choices kept as changes.
(define old-theme-files
  '((default (accent . #xff9e64) (selection . #x6a493c)
             (window-border-focus . #x896051) (corner-radius . 4))
    (nord (bg-0 . #x242933) (bg-1 . #x2e3440) (bg-2 . #x353c4a)
          (bg-3 . #x3b4252) (text . #xeceff4) (text-dim . #xd8dee9)
          (text-faint . #x6d7a96) (accent . #x88c0d0) (accent-2 . #xb48ead)
          (red . #xbf616a) (orange . #xd08770) (yellow . #xebcb8b)
          (green . #xa3be8c) (cyan . #x8fbcbb) (teal . #x8fbcbb)
          (magenta . #xb48ead) (selection . #x4e6572)
          (desktop-top . #x252a34) (desktop-bottom . #x3a4660)
          (panel . #x1f232b) (panel-text . #xeceff4) (panel-dim . #x6d7a96)
          (panel-hover . #x3b4252) (window-bg . #x2e3440)
          (window-border . #x49505f) (window-border-focus . #x5e7b8b)
          (title-bg . #x353c4a) (title-bg-focus . #x3b4252)
          (title-text . #xeceff4) (title-text-dim . #x6d7a96)
          (button-close . #xbf616a) (button-min . #xebcb8b)
          (button-max . #xa3be8c) (button-idle . #x565c6a)
          (corner-radius . 4) (preset . nord))
    (genera (bg-0 . #xffffff) (bg-1 . #xffffff) (bg-2 . #xf0f0f0)
            (bg-3 . #xd8d8d8) (text . #x000000) (text-dim . #x222222)
            (text-faint . #x666666) (accent . #x3366cc) (accent-2 . #x444444)
            (red . #x8b0000) (orange . #x6b4400) (yellow . #x5c5c00)
            (green . #x1f5f1f) (cyan . #x1f5566) (teal . #x1f5f55)
            (magenta . #x661f66) (selection . #xb8c9ed)
            (desktop-top . #xffffff) (desktop-bottom . #xffffff)
            (watermark . #x000000) (panel . #x000000) (panel-text . #xffffff)
            (panel-dim . #xb4b4b4) (panel-hover . #x383838)
            (window-bg . #xffffff) (window-border . #xc7c7c7)
            (window-border-focus . #x8ea5d3) (title-bg . #xf0f0f0)
            (title-bg-focus . #xd8d8d8) (title-text . #x000000)
            (title-text-dim . #x666666) (button-close . #x8b0000)
            (button-min . #x5c5c00) (button-max . #x1f5f1f)
            (button-idle . #xb8b8b8) (window-style . genera)
            (preset . genera) (desktop-pattern . flat))
    (deleted (window-style . amiga) (preset . workbench) (corner-radius . 4))))

(define (write-theme-file! data)
  (call-with-output-file *theme-file-path* (lambda (p) (write data p))
    'replace))

;; The colors a palette gives or derives (not those kits and styles add).
(define palette-keys
  (append (plist-keys base-colors) (plist-keys derived-colors)))

(let* ([fresh (let ([t (resolve-theme 'mac '() '())])
                (compute-rules! t)
                t)]
       [loaded
        (map (lambda (f)
               (let ([file (cdr f)])
                 (write-theme-file! file)
                 (theme-file-load!)
                 (list (car f)
                       (for-all (lambda (k)
                                  (equal? (theme k)
                                          (let ([p (assq k file)])
                                            (if p
                                                (cdr p)
                                                (hashtable-ref fresh k #f)))))
                                palette-keys)
                       (theme 'window-style) (theme 'palette)
                       (theme 'corner-radius) (theme 'wallpaper)
                       *style-changes*)))
             old-theme-files)])
  (set-style! 'mac)
  (reset-theme!)
  (check (format "old theme files load to the colors today's tree resolved \
                  from them, and your choices as the style's changes: ~s"
                 loaded)
         (equal? loaded
                 '((default #t mac tokyo-night 4 gradient
                            ((mac palette tokyo-night accent #xff9e64
                                  corner-radius 4)))
                   (nord #t mac nord 4 gradient
                         ((mac palette nord corner-radius 4)))
                   ;; a v1 file holds every color: those the Genera
                   ;; style inks are its changes
                   (genera #t genera genera 0 flat
                           ((genera palette genera bg-2 #xf0f0f0
                                    bg-3 #xd8d8d8 text-dim #x222222
                                    text-faint #x666666 accent #x3366cc
                                    accent-2 #x444444 red #x8b0000
                                    orange #x6b4400 yellow #x5c5c00
                                    green #x1f5f1f cyan #x1f5566
                                    teal #x1f5f55 magenta #x661f66
                                    window-border #xc7c7c7
                                    window-border-focus #x8ea5d3)))
                   (deleted #t mac tokyo-night 4 gradient
                            ((mac palette tokyo-night corner-radius 4)))))))

;; Saved, cleared and loaded: the chosen style, the scale, the Overrides
;; and every style's changes come back; the file is plain data, its colors
;; in hex.
(check "the theme file round-trips: style, scale, Overrides, changes"
       (let ([text (lambda ()
                     (call-with-input-file *theme-file-path* get-string-all))])
         (set-style! 'genera)
         (set-theme! 'palette 'nord)
         (set-theme! 'corner-radius 4)
         (set-style! 'mac)
         (set-theme! 'accent #xff9e64)
         (override! 'ui-font-size 15)
         (let ([state (list *style-name* *scale-setting* *theme-overrides*
                            *style-changes*)]
               [file (begin (theme-file-save!) (text))])
           (set-style! 'windows)
           (reset-theme!)
           (theme-file-load!)
           (let ([back (list *style-name* *scale-setting* *theme-overrides*
                             *style-changes*)])
             (reset-theme!)
             (set-style! 'mac)
             (and (equal? back state)
                  (string-contains-ci? file "(accent . #xff9e64)")
                  (string-contains-ci? file "(version . 2)")
                  (equal? (theme 'ui-font-size) 13))))))

;; Every palette, Tokyo Night too, derives what it does not give as
;; today's tree derived it (derive-colors, as it was).
(define (derived-as-today palette)
  (define (ref k) (plist-ref palette k #f))
  (define (unless-given p)
    (cond [(null? p) '()]
          [(ref (car p)) (unless-given (cddr p))]
          [else (cons* (car p) (cadr p) (unless-given (cddr p)))]))
  (append palette
          (unless-given
           (list 'selection (mix (ref 'accent) (ref 'bg-1) 0.65)
                 'panel-text (ref 'text) 'panel-dim (ref 'text-faint)
                 'panel-hover (ref 'bg-3) 'window-bg (ref 'bg-1)
                 'window-border (mix (ref 'bg-3) (ref 'text) 0.08)
                 'window-border-focus (mix (ref 'bg-3) (ref 'accent) 0.45)
                 'title-bg (ref 'bg-2) 'title-bg-focus (ref 'bg-3)
                 'title-text (ref 'text) 'title-text-dim (ref 'text-faint)
                 'button-close (ref 'red) 'button-min (ref 'yellow)
                 'button-max (ref 'green)
                 'button-idle (mix (ref 'bg-3) (ref 'text) 0.15)))))

(check (format "every palette resolves to its colors derived as today's \
                tree derived them (~a)" (palettes))
       (for-all (lambda (name)
                  (let* ([given (let ([p (palette-colors name)])
                                  (if (null? p) base-colors p))]
                         [today (derived-as-today given)]
                         [now (theme-palette-preview name)])
                    (for-all (lambda (k)
                               (equal? (plist-ref now k #f)
                                       (plist-ref today k #f)))
                             palette-keys)))
                (palettes)))

;;; ------------------------------------------------------------------
;;; styles and parts

(reset-theme!)
(set-style! 'mac)

;; thunk's result, with the styles registered meanwhile gone after it.
(define (with-test-styles thunk)
  (let ([plain *styles*])
    (dynamic-wind void thunk
                  (lambda () (set! *styles* plain) (set-style! 'mac)))))

(define (insets-of w) (call-with-values (lambda () (frame-insets w)) list))
(define (test-insets win) (values 3 17 3 3))

(check "a derived style is its parent with one setting changed, and its \
        parent defined again shows in it"
       (with-test-styles
        (lambda ()
          (define-style test-base "Test base"
            'frame-insets 'test-insets 'corner-radius 5)
          (define-style test-flat "Test flat"
            'parent 'test-base 'corner-radius 0)
          (set-style! 'test-flat)
          (let* ([w (open-window "Derived" 'size '(100 . 50))]
                 [got (list (map style-name (style-chain 'test-flat))
                            (insets-of w) (theme 'corner-radius)
                            (theme-source 'corner-radius)
                            (theme-source 'frame-insets))])
            (define-style test-base "Test base" 'corner-radius 5)
            (let ([again (insets-of w)])
              (close-window! w)
              (equal? (list got again)
                      (list (list '(test-flat test-base) '(3 17 3 3) 0
                                  '(style test-flat 0)
                                  '(style test-base test-insets))
                            (list 0 (title-height) 0 0))))))))

;; A part a style names is looked up at each call: redefined at the REPL,
;; the next frame draws the new definition.
(define test-drawn #f)
(define (test-under win x y w h focused? hover pressed)
  (set! test-drawn 'first))
(check "a part given by name shows its redefinition at the next frame"
       (with-test-styles
        (lambda ()
          (define-style test-part "Test part" 'frame-under 'test-under)
          (set-style! 'test-part)
          (let ([w (open-window "Part" 'size '(100 . 50))])
            (steps 1)
            (let ([first test-drawn])
              (set! test-under (lambda args (set! test-drawn 'second)))
              (invalidate!)
              (steps 1)
              (close-window! w)
              (equal? (list first test-drawn) '(first second)))))))

(define-part (test-meter n) (* n 2))
(check "define-part: the built-in is name*, and name calls the style's part"
       (with-test-styles
        (lambda ()
          (let ([plain (test-meter 3)])
            (define-style test-tenfold "Test" 'test-meter (lambda (n) (* n 10)))
            (set-style! 'test-tenfold)
            (equal? (list plain (test-meter 3) (test-meter* 3)
                          (theme-default 'test-meter))
                    '(6 30 6 test-meter*))))))

(check "a title's right click opens the style's window menu, a part"
       (with-test-styles
        (lambda ()
          (let ([opened #f])
            (define-style test-menu "Test"
              'open-window-menu (lambda (win x y) (set! opened win)))
            (set-style! 'test-menu)
            (let ([w (open-window "Menu" 'size '(200 . 100) 'pos '(300 . 200))])
              (inject! '(mouse-move 400 205) '(mouse-down 400 205 right 1)
                       '(mouse-up 400 205 right))
              (steps 1)
              (close-window! w)
              (eq? opened w))))))

(check "a window of another style is drawn and hit-tested in that style's \
        theme, its content included"
       (let* ([seen #f]
              [w (open-window "Genera here" 'size '(200 . 100)
                              'pos '(300 . 200) 'window-style 'genera
                              'draw (lambda (win cw ch)
                                      (set! seen (list (theme 'palette)
                                                       (theme 'wallpaper)))))])
         (invalidate!)
         (steps 1)
         ;; Genera's label, at the bottom, is its title
         (let ([insets (insets-of w)]
               [hit (window-region w 400 (+ 200 (window-h w) -10))])
           (close-window! w)
           (printf "  ~s\n" (list seen insets hit))
           (and (equal? seen '(genera flat)) (eq? (theme 'palette) 'tokyo-night)
                (equal? insets '(6 6 6 23)) (eq? hit 'title)))))

(check "choosing Genera brings its palette and wallpaper; a palette chosen \
        for it stays with it"
       (begin
         (set-style! 'genera)
         (let ([own (list (theme 'palette) (theme 'wallpaper))])
           (set-theme! 'palette 'nord)
           (set-style! 'mac)
           (let ([mac (list (theme 'palette) (theme 'wallpaper))])
             (set-style! 'genera)
             (let ([back (theme 'palette)])
               (reset-theme!)
               (set-style! 'mac)
               (equal? (list own mac back)
                       '((genera flat) (tokyo-night gradient) nord)))))))

(check "with-style: another style's theme, or this one's with a setting"
       (equal? (list (with-style 'interlisp
                       (lambda () (list (theme 'palette) (theme 'wallpaper))))
                     (with-style 'mac (lambda () (theme 'palette))
                                 'palette 'nord)
                     (theme 'palette))
               '((interlisp shade) nord tokyo-night)))

;;; ------------------------------------------------------------------
;;; fonts and sizes as settings

(check "a font is a setting: two themes asking for one font share its \
        record, and a font changed and back is the very one"
       (let ([ui (theme 'ui)]
             [other (with-style 'windows (lambda () (theme 'ui)))])
         (set-theme! 'ui-font-size 15)
         (let ([bigger (theme 'ui)])
           (reset-style! 'ui-font-size)
           (and (eq? ui other) (eq? ui (theme 'ui))
                (= 15 (font-size bigger)) (eq? (theme 'title) (theme 'ui-bold))
                (eq? (get-font 'ui) ui)))))

(check "a text's layout stays across a color change, and goes with a font \
        change"
       (let* ([ui (make-ui)]
              [lay (lambda ()
                     (ui-text-layout ui 'probe "some words to wrap here" 120
                                     'ui #t))]
              [a (lay)])
         (set-theme! 'accent #x123456)
         (let ([b (lay)])
           (set-theme! 'ui-font-size 15)
           (let ([c (lay)])
             (reset-style! 'accent 'ui-font-size)
             (and (eq? a b) (not (eq? b c)))))))

(check "a title's or bar's height: the setting grown to its text's need, 0 \
        none, and a style's own pixels where it fixes it"
       (with-test-styles
        (lambda ()
          (set-theme! 'title-height 10)
          (set-theme! 'taskbar-height 0)
          (let ([mac (list (title-height) (taskbar-height)
                           (theme 'title-height-min))])
            (reset-style! 'title-height 'taskbar-height)
            (define-style test-fixed "Test" 'options '(palette)
              'title-height 12)
            (set-style! 'test-fixed)
            (override! 'title-height 40)
            (let ([fixed (list (title-height) (theme 'fixed))])
              (override! 'title-height)
              (and (equal? (cdr mac) (list 0 (car mac))) (> (car mac) 10)
                   (= (car fixed) 12) (memq 'title-height (cadr fixed))
                   #t))))))

;;; ------------------------------------------------------------------
;;; the kit, the bars and the menus through parts; places

(for-each close-window! (windows))
(reset-theme!)
(set-style! 'mac)
(steps 1)

;; A window holding a text field, a label under it: (values win ui).
(define (field-window text)
  (let ([ui (make-ui)])
    (values (apply open-window "Field" 'size '(400 . 120) 'pos '(200 . 200)
                   'ui ui
                   'draw (lambda (win w h)
                           (ui-begin! ui)
                           (ui-text-field ui 'f 20 20 300 30 text void)
                           (ui-draw-label 20 70 300 20 '() "a label")
                           (ui-end! ui w h))
                   (ui-handlers ui))
            ui)))

;; The leftmost column inside the field (content x 30 to 300) where its
;; text's ink is, in logical pixels.
(define (ink-left win)
  (let-values ([(cx cy cw ch) (content-rect win)])
    (let ([bg (canvas-pixel (+ cx 24) (+ cy 35))])
      (let loop ([x 24])
        (cond [(> x 300) #f]
              [(exists (lambda (dy) (not (= (canvas-pixel (+ cx x) (+ cy dy))
                                            bg)))
                       '(28 31 34 37 40))
               x]
              [else (loop (+ x 1))])))))

;; The caret's index after a click at content x 60.
(define (index-clicked win ui)
  (let-values ([(cx cy cw ch) (content-rect win)])
    (inject! `(mouse-move ,(+ cx 60) ,(+ cy 35))
             `(mouse-down ,(+ cx 60) ,(+ cy 35) left 1)
             `(mouse-up ,(+ cx 60) ,(+ cy 35) left))
    (steps 2)
    (edit-caret (ui-state-edit ui))))

(define (test-text-areas x y w h flags)
  (let ([a (ui-text-box-areas* x y w h flags)])
    (cons (cons* 'edit (+ (cadr (car a)) 40) (cddr (car a))) (cdr a))))

(check "a style that moves only ui-text-box-areas moves the text and where \
        a click puts the caret"
       (with-test-styles
        (lambda ()
          (let-values ([(win ui) (field-window "MMMMMMMMMMMM")])
            (steps 2)
            (let ([plain (list (ink-left win) (index-clicked win ui))])
              (define-style test-areas "Test"
                'ui-text-box-areas 'test-text-areas)
              (set-style! 'test-areas)
              (steps 2)
              (let ([moved (list (ink-left win) (index-clicked win ui))])
                (close-window! win)
                (printf "  ~s\n" (list plain moved))
                (and (car plain) (car moved)
                     (<= 39 (- (car moved) (car plain)) 41)
                     (< (cadr moved) (cadr plain)))))))))

(check "a style mapping the field place colors a text box's text, and only \
        inside it"
       (with-test-styles
        (lambda ()
          (let ([seen '()])
            (define-style test-place "Test"
              'places (list (list 'field 'text #xff0000))
              'ui-draw-text-box
              (lambda args
                (set! seen (cons (cons 'box (theme 'text)) seen))
                (apply ui-draw-text-box* args))
              'ui-draw-label
              (lambda args
                (set! seen (cons (cons 'label (theme 'text)) seen))
                (apply ui-draw-label* args)))
            (set-style! 'test-place)
            (let-values ([(win ui) (field-window "x")])
              (steps 2)
              (close-window! win)
              (and (equal? (assq 'box seen) '(box . #xff0000))
                   (equal? (assq 'label seen) (cons 'label (theme 'text)))
                   (not (= (theme 'text) #xff0000))))))))

(define (test-topbar-areas)
  (let ([h (topbar-height)])
    (list (list 'launcher 300 0 120 h) (list 'title 0 0 300 h))))

(check "a style that moves the launcher in the top bar's areas moves its \
        click"
       (with-test-styles
        (lambda ()
          (define (opened-at x)
            (inject! `(mouse-move ,x 10) `(mouse-down ,x 10 left 1)
                     `(mouse-up ,x 10 left))
            (steps 1)
            (let ([open? (launcher-open?)])
              (when (menu-open?) (close-menu!))
              (steps 1)
              open?))
          (let ([plain (list (opened-at 40) (opened-at 340))])
            (define-style test-launcher "Test"
              'topbar-areas 'test-topbar-areas)
            (set-style! 'test-launcher)
            (equal? (list plain (list (opened-at 40) (opened-at 340)))
                    '((#t #f) (#f #t)))))))

(check "the menu's entries are where menu-areas puts them: a taller entry \
        moves the click"
       (with-test-styles
        (lambda ()
          (define (entry-at-row row)
            (open-menu! 100 100 '(("One" . void) ("Two" . void)
                                  ("Three" . void)))
            (let-values ([(x y w h) (menu-geometry *menu*)])
              (let ([i (menu-entry-at (+ x 20)
                                      (+ y (theme 'menu-pad) row))])
                (close-menu!)
                i)))
          (let ([plain (entry-at-row 60)])
            (define-style test-menu "Test" 'menu-item-height 40)
            (set-style! 'test-menu)
            (equal? (list plain (entry-at-row 60)) '(2 1))))))

(check "the dialog place reaches the kit's dialog, drawn at ui-end!"
       (with-test-styles
        (lambda ()
          (let ([seen #f] [ui (make-ui)])
            (define-style test-dialog "Test"
              'places (list (list 'dialog 'bg-2 #xffff00))
              'ui-draw-dialog (lambda args
                                (set! seen (theme 'bg-2))
                                (apply ui-draw-dialog* args)))
            (set-style! 'test-dialog)
            (let ([w (apply open-window "Dialog" 'size '(420 . 260)
                            'ui ui
                            'draw (lambda (win w h)
                                    (ui-begin! ui)
                                    (ui-dialog ui 'd "A dialog" "Its message."
                                               (list (list "OK" void)) void)
                                    (ui-end! ui w h))
                            (ui-handlers ui))])
              (steps 2)
              (close-window! w)
              (eqv? seen #xffff00))))))

(check "a preview's extra settings lie over the Overrides, and over what \
        a style honors"
       (with-test-styles
        (lambda ()
          (define-style test-fixed-palette "Test" 'parent 'mac
            'options '(accent))
          (override! 'palette 'gruvbox)
          (let ([seen (list (with-style 'mac (lambda () (theme 'palette))
                                        'palette 'nord)
                            (with-style 'test-fixed-palette
                                        (lambda () (theme 'palette))
                                        'palette 'nord))])
            (override! 'palette)
            (equal? seen '(nord nord))))))

(check "a window of another style hears its input in that style's theme, \
        and a theme change its handler makes stays"
       (let* ([seen #f]
              [w (open-window "Genera input" 'size '(200 . 100)
                              'pos '(300 . 200) 'window-style 'genera
                              'mouse-down
                              (lambda (win x y button clicks)
                                (set! seen (theme 'palette))
                                (set-theme! 'accent #x123456)))])
         (steps 1)
         (let-values ([(cx cy cw ch) (content-rect w)])
           (inject! `(mouse-down ,(+ cx 20) ,(+ cy 20) left 1)
                    `(mouse-up ,(+ cx 20) ,(+ cy 20) left))
           (steps 1))
         (close-window! w)
         (let ([accent (theme 'accent)])
           (reset-style! 'accent)
           (and (eq? seen 'genera) (= accent #x123456)))))

(check "a menu whose place makes its entries taller takes a click where \
        it draws the entry"
       (with-test-styles
        (lambda ()
          (define-style test-tall-menu "Test"
            'places (list (list 'menu 'menu-item-height 50)))
          (set-style! 'test-tall-menu)
          (open-menu! 300 150 '(("One" . void) ("Two" . void)
                                ("Three" . void)))
          (let* ([two (assv 1 (with-place 'menu
                                (lambda () (menu-areas *menu*))))]
                 [hit (menu-entry-at (+ (cadr two) 20) (+ (caddr two) 25))])
            (close-menu!)
            (and (= (list-ref two 4) 50) (eqv? hit 1))))))

(check "an accent change is a change of colors only: the chrome stays"
       (let* ([n 0] [plain wm-chrome-changed!])
         (set! wm-chrome-changed! (lambda () (set! n (+ n 1)) (plain)))
         (set-theme! 'accent #xff9e64)
         (reset-style! 'accent)
         (set! wm-chrome-changed! plain)
         (= n 0)))

(check "a window of no style, focused or opened from another style's \
        handler, is in the chosen style's theme"
       (let* ([seen '()]
              [note (lambda (what)
                      (set! seen (cons (cons what (theme 'palette)) seen)))]
              [b (open-window "Plain" 'size '(100 . 60) 'pos '(600 . 400)
                              'focus (lambda (win) (note 'focus)))]
              [c #f]
              [g (open-window "Genera" 'size '(200 . 100) 'pos '(300 . 200)
                              'window-style 'genera
                              'mouse-down
                              (lambda (win x y button clicks)
                                (focus-window! b)
                                (set! c (open-window
                                         "Opened" 'size '(100 . 60)
                                         'open (lambda (win)
                                                 (note 'open))))))])
         (set! seen '())
         (steps 1)
         (let-values ([(cx cy cw ch) (content-rect g)])
           (inject! `(mouse-down ,(+ cx 20) ,(+ cy 20) left 1)
                    `(mouse-up ,(+ cx 20) ,(+ cy 20) left))
           (steps 1))
         (for-each close-window! (list b c g))
         (and (equal? (assq 'focus seen) '(focus . tokyo-night))
              (equal? (assq 'open seen) '(open . tokyo-night)))))

(check "a theme change of colors from another style's handler changes no \
        chrome"
       (let* ([n 0] [plain wm-chrome-changed!]
              [g (open-window "Genera" 'size '(200 . 100) 'pos '(300 . 200)
                              'window-style 'genera
                              'mouse-down
                              (lambda (win x y button clicks)
                                (set! n 0)
                                (set-theme! 'accent #x123456)))])
         (steps 1)
         (set! wm-chrome-changed! (lambda () (set! n (+ n 1)) (plain)))
         (let-values ([(cx cy cw ch) (content-rect g)])
           (inject! `(mouse-down ,(+ cx 20) ,(+ cy 20) left 1)
                    `(mouse-up ,(+ cx 20) ,(+ cy 20) left))
           (steps 1))
         (set! wm-chrome-changed! plain)
         (close-window! g)
         (reset-style! 'accent)
         (= n 0)))

(check "a text box whose place sets its text size takes a click where it \
        draws its text, as with the size set for the whole style"
       (with-test-styles
        (lambda ()
          (define (caret-at style)
            (set-style! style)
            (let-values ([(win ui) (field-window "MMMMMMMMMMMM")])
              (steps 2)
              (let ([i (index-clicked win ui)])
                (close-window! win)
                i)))
          (define-style test-big "Test" 'ui-font-size 26)
          (define-style test-big-field "Test"
            'places (list (list 'field 'ui-font-size 26)))
          (let* ([whole (caret-at 'test-big)]
                 [placed (caret-at 'test-big-field)])
            (printf "  ~s\n" (list whole placed))
            (= whole placed)))))

(check "the bars' place sizes their strips and places their clicks"
       (with-test-styles
        (lambda ()
          (define (launcher-at x)
            (inject! `(mouse-move ,x 10) `(mouse-down ,x 10 left 1)
                     `(mouse-up ,x 10 left))
            (steps 1)
            (let ([open? (launcher-open?)])
              (when (menu-open?) (close-menu!))
              (steps 1)
              open?))
          (define-style test-big-bars "Test"
            'places (list (list 'bar 'ui-font-size 26)))
          (let ([plain (launcher-at 150)])
            (set-style! 'test-big-bars)
            (let-values ([(dx dy dw dh) (desktop-rect)])
              (and (not plain) (launcher-at 150)
                   (= dy (topbar-height))
                   (> dy (theme 'topbar-height))))))))

(check "a tooltip is measured in its place, where it is drawn"
       (with-test-styles
        (lambda ()
          (let* ([seen #f] [ui (make-ui)] [fake (now-ms)] [real now-ms])
            (define-style test-big-tips "Test"
              'places (list (list 'tooltip 'ui-font-size 26))
              'ui-draw-tooltip
              (lambda (x y w h flags text)
                (set! seen (list (list w h)
                                 (call-with-values
                                   (lambda () (ui-tooltip-size text))
                                   list)))
                (ui-draw-tooltip* x y w h flags text)))
            (set-style! 'test-big-tips)
            (set! now-ms (lambda () fake))
            (let ([w (apply open-window "Tips" 'size '(400 . 200)
                            'pos '(200 . 200) 'ui ui
                            'draw (lambda (win w h)
                                    (ui-begin! ui)
                                    (ui-button ui 'b 20 20 100 30 "Button"
                                               void 'tip "A tip")
                                    (ui-end! ui w h))
                            (ui-handlers ui))])
              (steps 2)
              (let-values ([(cx cy cw ch) (content-rect w)])
                (inject! `(mouse-move ,(+ cx 50) ,(+ cy 30)))
                (steps 2)
                (set! fake (+ fake 2000))
                (invalidate! w)
                (steps 2))
              (set! now-ms real)
              (close-window! w)
              (and seen (equal? (car seen) (cadr seen))))))))

;;; ------------------------------------------------------------------
;;; shared drawing primitives: stipples, ink, crisp fonts, pixel art,
;;; glyphs

(for-each close-window! (windows))
(reset-theme!)

;; An image's pixels as rows of characters, by colors ((pixel . char)
;; ...); # for any other.
(define (pixel-rows surface key)
  (let ([w (cairo-image-surface-get-width surface)]
        [h (cairo-image-surface-get-height surface)])
    (map (lambda (y)
           (list->string
            (map (lambda (x)
                   (let ([p (assv (pixel-at surface x y) key)])
                     (if p (cdr p) #\#)))
                 (iota w))))
         (iota h))))

(define gray-light-dark
  '((#xff808080 . #\.) (#xffffffff . #\L) (#xff000000 . #\D)))

;; A bevel on gray in an 8 × 8 image at 100 %.
(define (bevel-rows h n . rule)
  (pixel-rows (image 8 8 1 (lambda ()
                             (fill-rect 0 0 8 8 #x808080)
                             (apply px-bevel 1 1 6 h #xffffff #x000000 n
                                    rule)))
              gray-light-dark))

;; Written from the sources' facts: Motif's segments (Xm/Draw.c:98-116:
;; the top rows to the right less their depth, the left sides from the
;; depth down, the dark sides a pixel in, drawn last) and Platinum's
;; window edge (platinum.md 5.1: the highlight to W-3 and H-3, the shade
;; from 2, its two off corners the face's).
(check "px-bevel at 1 and 2 pixels, Motif's corners: light owns them, then \
        stairs"
       (and (equal? (bevel-rows 5 1)
                    '("........" ".LLLLLL." ".L....D." ".L....D." ".L....D."
                      ".LDDDDD." "........" "........"))
            (equal? (bevel-rows 6 2)
                    '("........" ".LLLLLL." ".LLLLLD." ".LL..DD." ".LL..DD."
                      ".LLDDDD." ".LDDDDD." "........"))))
(check "px-bevel at 1 and 2 pixels, the Mac's corners keep what is under"
       (and (equal? (bevel-rows 5 1 'mac)
                    '("........" ".LLLLL.." ".L....D." ".L....D." ".L....D."
                      "..DDDDD." "........" "........"))
            (equal? (bevel-rows 6 2 'mac)
                    '("........" ".LLLLL.." ".LLLL.D." ".LL..DD." ".LL..DD."
                      ".L.DDDD." "..DDDDD." "........"))))

;; At a fractional scale and translation (a miniature), every pixel of
;; bevels, rings and pictures is one of their colors: none antialiased.
(define pixel-art-roles
  (list (cons #\a #xffffff) (cons #\b #x000000) (cons #\c #xcc3333)))
(check "at 125, 150 and 175 % every pixel of a bevel or a map is its color"
       (for-all
        (lambda (s)
          (let ([img (image 120 90 s
                            (lambda ()
                              (fill-rect 0 0 120 90 #x808080)
                              (cairo-translate *cr* 0.37 0.61)
                              (px-bevel 3 2 17 11 #xffffff #x000000 2)
                              (px-bevel 25 3 13 9 #x000000 #xffffff 2 'mac)
                              (px-ring 41 4 9 7 #xcc3333)
                              (px-bits 3 20 '("aab.c" "abbcc" ".c.ba")
                                       pixel-art-roles)
                              (px-bits 20 20 '("abc" "bcb" "cba")
                                       pixel-art-roles 'stretch '(1 . 11))))])
            (for-all (lambda (row) (not (memv #\# (string->list row))))
                     (pixel-rows img (append gray-light-dark
                                             '((#xffcc3333 . #\c)))))))
        '(1.25 1.5 1.75)))
(check "px-bits stretches its column to the width and skips clear cells"
       (equal? (pixel-rows (image 8 2 1
                                  (lambda ()
                                    (fill-rect 0 0 8 2 #x808080)
                                    (px-bits 1 0 '("abd" "d.b")
                                             pixel-art-roles
                                             'stretch '(1 . 6))))
                           gray-light-dark)
               '(".LDDDD.." "......D.")))

;; A stipple in two windows at odd places, at scales Settings offers and
;; others (Xft.dpi 128 is 133 %): every device pixel their content covers
;; whole is as px's rule places the pattern: device pixel d is logical
;; pixel ceiling((d + 1/2)/s) - 1 (half up, a tie the lower).
(define-style test-plain "Plain")
(check "a stipple lines up across two windows at 100, 125, 133, 150, 165, \
        175, 200 and 270 %, every pixel of their content as px places it"
       (let* ([rows '("#.." ".#." "#.#")]
              [st (apply stipple #x000000 #xffffff rows)]
              [ws (map (lambda (pos)
                         (open-window "Stippled" 'size '(201 . 101) 'pos pos
                                      'window-style 'test-plain
                                      'draw (lambda (win w h)
                                              (fill-rect 0 0 w h st))))
                       '((101 . 101) (357 . 163)))]
              [ink (color->pixel #x000000)])
         (define (inked? s x y)
           (let ([u (- (ceiling (/ (+ x 1/2) s)) 1)]
                 [v (- (ceiling (/ (+ y 1/2) s)) 1)])
             (char=? #\# (string-ref (list-ref rows (mod v 3)) (mod u 3)))))
         (let ([ok
                (for-all
                 (lambda (pct)
                   (set-theme! 'scale pct)
                   (steps 2)
                   (cairo-surface-flush *canvas*)
                   (let ([s (/ pct 100)])
                     (for-all
                      (lambda (w)
                        (let-values ([(cx cy cw ch) (content-rect w)])
                          (let ([x0 (ceiling (* s cx))] [y0 (ceiling (* s cy))]
                                [x1 (floor (* s (+ cx cw)))]
                                [y1 (floor (* s (+ cy ch)))])
                            (let loop ([x x0] [y y0])
                              (cond
                                [(>= y y1) #t]
                                [(>= x x1) (loop x0 (+ y 1))]
                                [(eq? (= (pixel-at *canvas* x y) ink)
                                      (inked? s x y))
                                 (loop (+ x 1) y)]
                                [else #f])))))
                      ws)))
                 '(100 125 133 150 165 175 200 270))])
           (set-theme! 'scale 0)
           (steps 1)
           (for-each close-window! ws)
           ok)))

(check "at 113 % (a tie in floating point a hair off) px-fill's checker is \
        a stipple's, pixel for pixel"
       (let ([at (lambda (thunk)
                   (image 136 23 1.13 (lambda ()
                                        (fill-rect 0 0 120 20 #x808080)
                                        (thunk))))])
         (zero? (max-diff
                 (at (lambda ()
                       (do ([i 0 (+ i 1)]) ((= i 2400))
                         (let ([u (mod i 120)] [v (quotient i 120)])
                           (px-fill u v 1 1 (if (even? (+ u v))
                                                #x000000
                                                #xffffff))))))
                 (at (lambda ()
                       (px-fill 0 0 120 20
                                (stipple #x000000 #xffffff "#." ".#"))))))))

(define (rgba c) (call-with-values (lambda () (color-rgba c)) list))
(check "a stipple's color-rgba is its coverage average, a clear paper's too"
       (and (equal? (rgba (stipple #xffffff #x000000 "#..." "...."))
                    '(0.125 0.125 0.125 1.0))
            (equal? (rgba (stipple #xff0000 #f "#." ".."))
                    '(1.0 0.0 0.0 0.25))
            ;; a theme key's stipple, through mix
            (begin (set-theme! 'test-gray (stipple 'text #f "#." ".."))
                   (equal? (mix 'test-gray 'test-gray 0.5)
                           (color->fixnum 'text)))))
(reset-theme!)

(check "a stipple given as a color is saved and loads back"
       (let ([gray (stipple 'text #f "#." "..")])
         (set-theme! 'accent-2 gray)
         (theme-file-save!)
         (reset-theme!)
         (theme-file-load!)
         (let ([back (theme 'accent-2)])
           (reset-theme!)
           (theme-file-save!)
           (equal? back gray))))

(check "text-ink: a capital's ink stands on the baseline, as wide as it \
        inks; font-descent is the font's"
       (let-values ([(l top w h) (text-ink "H" 'ui)]
                    [(l2 top2 w2 h2) (text-ink "Hi there" 'ui)])
         (and (< top 0) (< (abs (+ top h)) 1) (> w 0) (> w2 w)
              (= (font-descent 'ui) (vector-ref (font-metrics 'ui) 1))
              (> (font-descent 'ui) 0))))

;; How many pixels of text drawn on white are neither white nor black.
(define (gray-pixels font)
  (let ([img (image 120 30 1 (lambda ()
                               (fill-rect 0 0 120 30 #xffffff)
                               (draw-text 4 4 "Crisp text" #x000000 font)))])
    (apply + (map (lambda (row) (length (filter (lambda (ch) (char=? ch #\#))
                                                (string->list row))))
                  (pixel-rows img '((#xffffffff . #\.) (#xff000000 . #\k)))))))
(check "a crisp font is its own record and draws no antialiased pixel"
       (let ([crisp (font "DejaVu Sans" 12 'crisp)]
             [plain (font "DejaVu Sans" 12)])
         (and (not (eq? crisp plain)) (eq? crisp (font "DejaVu Sans" 12 'crisp))
              (zero? (gray-pixels crisp)) (> (gray-pixels plain) 0))))

(check "px-text puts the baseline and the pen on whole device pixels; \
        px-fit cuts until the ink fits"
       (let ([at (lambda (thunk) (image 100 40 1.5 thunk))])
         (and (zero? (max-diff
                      (at (lambda () (px-text 10.3 20.4 "Etched" 'text 'ui)))
                      (at (lambda ()
                            (draw-text (/ 15 1.5) (- (/ 31 1.5)
                                                     (font-ascent 'ui))
                                       "Etched" 'text 'ui)))))
              (let ([s (px-fit "A rather long window title" 60 'ui)])
                (and (string-suffix? "…" s)
                     (let-values ([(l t w h) (text-ink s 'ui)]) (<= w 60)))))))

;; Each window glyph and triangle inks inside its box and nowhere else.
(check "ui-draw-glyph's window glyphs and triangles ink their box only"
       (for-all
        (lambda (name)
          (let ([rows (pixel-rows
                       (image 24 24 1
                              (lambda ()
                                (fill-rect 0 0 24 24 #x808080)
                                (ui-draw-glyph 6 6 12 12
                                               '((ink . #x000000)) name)))
                       '((#xff808080 . #\.)))])
            (and (exists (lambda (r) (memv #\# (string->list r))) rows)
                 (for-all (lambda (y)
                            (or (<= 5 y 18)
                                (not (memv #\# (string->list
                                                (list-ref rows y))))))
                          (iota 24)))))
        '(close minimize maximize restore shade up down left right)))

;;; The core's primitives that keep C away from the folders: operators,
;;; the device's transform and pixels, rotation, gradients as colors,
;;; several boxes stroked at once, raw pixels, a PNG file.

;; thunk's pixels at (x, y) ..., drawn on a fresh w × h image at scale s.
(define (pixels-of w h s thunk . points)
  (let* ([img (image w h s thunk)]
         [ps (map (lambda (p) (pixel-at img (car p) (cadr p))) points)])
    (cairo-surface-destroy img)
    ps))

(define (same-drawing? w h s a b)
  (let* ([ia (image w h s a)] [ib (image w h s b)] [d (max-diff ia ib)])
    (cairo-surface-destroy ia)
    (cairo-surface-destroy ib)
    (zero? d)))

(check "call-with-operator: white by difference turns a color to its \
        inverse, add adds, drawing covers again after, and an unknown \
        operator raises"
       (and (equal? (pixels-of 4 4 1
                               (lambda ()
                                 (fill-rect 0 0 4 4 #x204060)
                                 (call-with-operator 'difference
                                   (lambda () (fill-rect 0 0 4 4 #xffffff))))
                               '(1 1))
                    '(#xffdfbf9f))
            (equal? (pixels-of 4 4 1
                               (lambda ()
                                 (fill-rect 0 0 4 4 #x102030)
                                 (call-with-operator 'add
                                   (lambda () (fill-rect 0 0 4 4 #x010203))))
                               '(1 1))
                    '(#xff112233))
            (equal? (pixels-of 4 4 1
                               (lambda ()
                                 (fill-rect 0 0 4 4 #x204060)
                                 (call-with-operator 'difference void)
                                 (fill-rect 0 0 4 4 #x000000))
                               '(1 1))
                    '(#xff000000))
            (raises? (lambda () (call-with-operator 'xor void)))))

(check "device-transform: the scale and where the origin is in device \
        pixels; call-with-device-pixels draws on them from the corner, \
        then no more"
       (let* ([seen '()]
              [see! (lambda ()
                      (set! seen (cons (call-with-values device-transform
                                         list)
                                       seen)))]
              [img (image 8 8 2
                          (lambda ()
                            (fill-rect 0 0 4 4 #xffffff)
                            (call-with-translation 1 1.5
                              (lambda ()
                                (see!)
                                (call-with-device-pixels
                                  (lambda ()
                                    (see!)
                                    (fill-rect 0 0 1 1 #x000000)))
                                (see!)
                                (fill-rect 1 0.5 1 1 #x000000)))))]
              [rows (pixel-rows img '((#xffffffff . #\.)
                                      (#xff000000 . #\k)))])
         (cairo-surface-destroy img)
         (and (equal? (reverse seen) '((2.0 2.0 3.0) (1.0 0.0 0.0)
                                       (2.0 2.0 3.0)))
              (equal? rows '("k......." "........" "........" "........"
                             "....kk.." "....kk.." "........" "........")))))

(check "call-with-rotation turns what it draws clockwise on the screen, \
        then no more"
       (same-drawing? 10 10 1
                      (lambda ()
                        (fill-rect 0 0 10 10 #xffffff)
                        (call-with-translation 5 5
                          (lambda ()
                            (call-with-rotation (/ pi 2)
                              (lambda () (fill-rect 0 0 4 2 #x000000)))
                            (fill-rect 0 -5 1 1 #x000000))))
                      (lambda ()
                        (fill-rect 0 0 10 10 #xffffff)
                        (fill-rect 3 5 2 4 #x000000)
                        (fill-rect 5 0 1 1 #x000000))))

;; A pattern's stops at the offsets given, then the pattern as the source.
(define (stops-by-hand! pat offsets colors)
  (for-each (lambda (at c)
              (let-values ([(r g b a) (color-rgba c)])
                (cairo-pattern-add-color-stop-rgba pat at r g b a)))
            offsets colors)
  (cairo-set-source *cr* pat)
  (cairo-pattern-destroy pat))

(check "gradients are colors: a linear and a radial one paint as cairo's \
        patterns of their colors, spread evenly; fill-gradient and \
        fill-glow as they did by hand"
       (and (same-drawing?
             80 60 1.5
             (lambda ()
               (fill-rect 0 0 80 60
                          (linear-gradient 3 2 70 50 'accent #x000000
                                           (alpha 'red 0.5))))
             (lambda ()
               (stops-by-hand! (cairo-pattern-create-linear 3 2 70 50)
                               '(0 1/2 1)
                               (list 'accent #x000000 (alpha 'red 0.5)))
               (cairo-rectangle *cr* 0 0 80 60)
               (cairo-fill *cr*)))
            (same-drawing?
             80 60 1.5
             (lambda ()
               (fill-circle 40 30 25 (radial-gradient 40 30 25 'accent-2
                                                      #xffffff)))
             (lambda ()
               (stops-by-hand! (cairo-pattern-create-radial 40 30 0 40 30 25)
                               '(0 1) '(accent-2 #xffffff))
               (cairo-new-sub-path *cr*)
               (cairo-arc *cr* 40 30 25 0 (* 2 pi))
               (cairo-fill *cr*)))
            (for-all
             (lambda (dir radius)
               (same-drawing?
                80 60 1.5
                (lambda ()
                  (fill-gradient 5 5 70 50 'desktop-top 'desktop-bottom dir
                                 radius))
                (lambda ()   ; HEAD's fill-gradient
                  (stops-by-hand! (if (eq? dir 'horizontal)
                                      (cairo-pattern-create-linear 5 0 75 0)
                                      (cairo-pattern-create-linear 0 5 0 55))
                                  '(0 1) '(desktop-top desktop-bottom))
                  (rrect-path! 5 5 70 50 radius)
                  (cairo-fill *cr*))))
             '(vertical horizontal) '(9 0))
            (same-drawing?
             80 60 1.5
             (lambda () (fill-glow 40 30 35 (alpha 'accent 0.3)))
             (lambda ()   ; HEAD's fill-glow
               (let ([pat (cairo-pattern-create-radial 40 30 0 40 30 35)])
                 (let-values ([(cr cg cb ca) (color-rgba (alpha 'accent 0.3))])
                   (cairo-pattern-add-color-stop-rgba pat 0 cr cg cb ca)
                   (cairo-pattern-add-color-stop-rgba pat 1 cr cg cb 0))
                 (cairo-set-source *cr* pat)
                 (cairo-new-path *cr*)
                 (cairo-arc *cr* 40 30 35 0 (* 2 pi))
                 (cairo-fill *cr*)
                 (cairo-pattern-destroy pat))))))

(check "stroke-round-rects strokes its boxes as one path, painting once \
        where their lines cross; one box is stroke-round-rect"
       (let* ([half (alpha #x000000 0.5)]
              ;; where they cross, then on each one's line alone
              [ps (pixels-of 40 30 1
                             (lambda ()
                               (fill-rect 0 0 40 30 #xffffff)
                               (stroke-round-rects '((2 2 20 20 4)
                                                     (12 6 20 20 4))
                                                   half 4))
                             '(20 8) '(20 15) '(14 16))])
         (and (apply = ps) (not (= (car ps) #xffffffff))
              (same-drawing? 40 30 1.5
                             (lambda ()
                               (stroke-round-rects '((2 2 20 20 4)) half 3))
                             (lambda ()
                               (stroke-round-rect 2 2 20 20 4 half 3))))))

(check "draw-pixels draws raw pixels as sharp blocks, and nothing at no size"
       (let ([bv (make-bytevector 8 0)])
         (bytevector-u32-native-set! bv 0 #xffff0000)
         (bytevector-u32-native-set! bv 4 #xff0000ff)
         (equal? (pixels-of 8 4 1
                            (lambda ()
                              (draw-pixels bv 2 1 1 1 4 2)
                              (draw-pixels bv 2 1 6 0 0 3))
                            '(1 1) '(2 2) '(3 1) '(4 2) '(5 1) '(6 1))
                 '(#xffff0000 #xffff0000 #xff0000ff #xff0000ff 0 0))))

(define png-surface
  (foreign-procedure "cairo_image_surface_create_from_png" (string) uptr))

(check "write-image-png draws on a fresh transparent image and saves it"
       (let ([path (string-append out-dir "/primitive.png")])
         (write-image-png path 3 2 (lambda () (fill-rect 1 0 2 1 #x336699)))
         (let* ([img (png-surface path)]
                [r (list (cairo-image-surface-get-width img)
                         (cairo-image-surface-get-height img)
                         (pixel-at img 0 0) (pixel-at img 1 0)
                         (pixel-at img 2 0) (pixel-at img 2 1))])
           (cairo-surface-destroy img)
           (delete-file path)
           (equal? r '(3 2 0 #xff336699 #xff336699 0)))))

;;; ------------------------------------------------------------------
;;; behaviors a style chooses (each a setting, today's feel by default)

(for-each close-window! (windows))
(reset-theme!)
(steps 1)

;; win's region at its own point (lx, ly).
(define (region-at win lx ly)
  (window-region win (+ (window-x win) lx) (+ (window-y win) ly)))

;; A left drag on the screen from (x0, y0) to (x1, y1).
(define (drag-on! x0 y0 x1 y1)
  (inject! `(mouse-move ,x0 ,y0) `(mouse-down ,x0 ,y0 left 1)
           `(mouse-move ,x1 ,y1) `(mouse-up ,x1 ,y1 left))
  (steps 1))

(define (geometry w) (list (window-x w) (window-y w) (window-w w) (window-h w)))

(let ([w (open-window "Edges" 'size '(300 . 200) 'pos '(200 . 150))])
  (define (at)
    (map (lambda (p) (region-at w (car p) (cdr p)))
         (list (cons (- (window-w w) 3) 100) (cons (- (window-w w) 7) 100)
               (cons (- (window-w w) 3) (- (window-h w) 17)))))
  (check "the resize edges are settings: frame-edge wide, frame-corner long, \
          an edge of 0 none"
         (and (equal? (at) '(resize-r content resize-r))
              (begin (set-theme! 'frame-edge 9) (set-theme! 'frame-corner 20)
                     (equal? (at) '(resize-r resize-r resize-br)))
              (begin (set-theme! 'frame-edge 0)
                     (equal? (at) '(content content content)))))
  (reset-theme!)
  (close-window! w))

;; A style resizing from its top edge and corners, the window manager's
;; edges off.
(define (test-top-regions win)
  (let ([w (window-w win)])
    (list (list 'resize-tl 0 0 8 8) (list 'resize-tr (- w 8) 0 8 8)
          (list 'resize-t 8 0 (- w 16) 4))))
(define-style test-top "Top resizes"
  'frame-regions 'test-top-regions 'frame-edge 0)

(check "a style's regions move the clicks: its top edge and corners resize \
        from the top, the other sides staying"
       (let ([w (open-window "Top" 'size '(300 . 200) 'pos '(300 . 300)
                             'window-style 'test-top)])
         (steps 1)
         (let* ([g0 (geometry w)] [x (car g0)] [y (cadr g0)]
                [r (+ x (caddr g0))] [b (+ y (cadddr g0))])
           (drag-on! (+ x 100) (+ y 2) (+ x 100) (- y 28))
           (let ([g1 (geometry w)])
             (drag-on! (+ x 3) (- y 27) (- x 17) (- y 37))
             (let ([g2 (geometry w)])
               (drag-on! (- r 3) (- y 37) (+ r 17) (- y 47))
               (let ([g3 (geometry w)] [cursor (region-cursor w 'resize-t)]
                     [edge (region-at w (- (window-w w) 3) 100)])
                 (close-window! w)
                 (and (equal? g1 (list x (- y 30) (caddr g0)
                                       (+ (cadddr g0) 30)))
                      (equal? g2 (list (- x 20) (- y 40) (+ (caddr g0) 20)
                                       (+ (cadddr g0) 40)))
                      (equal? g3 (list (- x 20) (- y 50) (+ (caddr g0) 40)
                                       (+ (cadddr g0) 50)))
                      (= b (+ (cadr g3) (cadddr g3)))
                      (eq? cursor 'resize-ns) (eq? edge 'content))))))))

;; A left double click at screen point (x, y).
(define (double-click! x y)
  (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left)
           `(mouse-down ,x ,y left 2) `(mouse-up ,x ,y left))
  (steps 1))

(check "a double click on the title does what title-double-click names: \
        maximize (by default), minimize or nothing"
       (let ([w (open-window "Twice" 'size '(300 . 200) 'pos '(250 . 200))])
         (define (twice!)
           (double-click! (+ (window-x w) 150) (+ (window-y w) 10))
           (window-state w))
         (let* ([a (twice!)]
                [b (begin (restore-window! w)
                          (set-theme! 'title-double-click 'none)
                          (twice!))]
                [c (begin (set-theme! 'title-double-click 'minimize)
                          (twice!))])
           (reset-theme!)
           (close-window! w)
           (equal? (list a b c) '(maximized normal minimized)))))

;; A style with a window-menu button, a double click on which closes the
;; window (CDE's).
(define (test-menu-regions win) (list (list 'menu 4 4 20 20)))
(define-style test-menu "Menu button"
  'frame-regions 'test-menu-regions 'button-double-click '((menu . close)))

(check "a press on a frame's menu button opens the window's menu; a double \
        click there does what button-double-click names"
       (let* ([w (open-window "Menu button" 'size '(300 . 200)
                              'pos '(250 . 200) 'window-style 'test-menu)]
              [x (+ (window-x w) 10)] [y (+ (window-y w) 10)])
         (steps 1)
         (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1))
         (steps 1)
         (let ([opened (and *menu*
                            (equal? (menu-tag *menu*) (cons 'window w)))])
           (inject! `(mouse-up ,x ,y left) `(mouse-down ,x ,y left 2)
                    `(mouse-up ,x ,y left))
           (steps 1)
           (and opened (not *menu*) (not (memq w (windows)))))))

;; A window counting its draws and resizes.
(define (counting-window title . opts)
  (let ([n (vector 0 0)])
    (values (apply open-window title 'size '(300 . 200) 'pos '(250 . 200)
                   'draw (lambda (win w h)
                           (vector-set! n 0 (+ 1 (vector-ref n 0))))
                   'resize (lambda (win w h)
                             (vector-set! n 1 (+ 1 (vector-ref n 1))))
                   opts)
            n)))

(check "a shaded window is its frame's top and bottom: its content is not \
        drawn, it keeps its content size, its app hears no resize, and a \
        move keeps it shaded"
       (let-values ([(w n) (counting-window "Shade me")])
         (steps 1)
         (let-values ([(cw ch) (window-content-size w)]
                      [(l t r b) (frame-insets w)])
           (shade-window! w)
           (vector-set! n 0 0)
           (invalidate!)
           (steps 1)
           (let ([shaded (list (shaded? w) (window-h w) (vector-ref n 0))])
             (move-window! w 260 220)
             (let ([moved (list (shaded? w) (window-h w))])
               (unshade-window! w)
               (steps 1)
               (let-values ([(cw2 ch2) (window-content-size w)])
                 (close-window! w)
                 (and (equal? shaded (list #t (+ t b) 0))
                      (equal? moved (list #t (+ t b)))
                      (= cw cw2) (= ch ch2) (zero? (vector-ref n 1))
                      (> (vector-ref n 0) 0))))))))

;; A style with a shade button at its top left.
(define (test-shade-regions win) (list (list 'shade 4 4 20 20)))
(define-style test-shade "Shade button" 'frame-regions 'test-shade-regions)

(check "a window shades by its style's triggers: a double click on the \
        title, the wheel on it (up shades, down unshades), a shade button, \
        the window menu; maximizing unshades"
       (let-values ([(w n) (counting-window "Triggers")])
         (define (title-x) (+ (window-x w) 150))
         (define (title-y) (+ (window-y w) 10))
         (define (wheel! dy)
           (inject! `(mouse-move ,(title-x) ,(title-y)) `(wheel 0 ,dy))
           (steps 1)
           (shaded? w))
         (set-theme! 'title-double-click 'shade)
         (double-click! (title-x) (title-y))
         (let ([a (shaded? w)])
           (double-click! (title-x) (title-y))
           (let ([b (shaded? w)])
             (set-theme! 'title-wheel 'shade)
             (let* ([c (wheel! 1)] [d (wheel! -1)])
               (reset-theme!)
               (let ([e (wheel! 1)])   ; title-wheel none again: nothing
                 (close-window! w)
                 (let ([s (open-window "Button" 'size '(300 . 200)
                                       'pos '(250 . 200)
                                       'window-style 'test-shade)])
                   (steps 1)
                   (drag-on! (+ (window-x s) 10) (+ (window-y s) 10)
                             (+ (window-x s) 10) (+ (window-y s) 10))
                   (let ([f (shaded? s)])
                     (inject! `(mouse-move ,(+ (window-x s) 150)
                                           ,(+ (window-y s) 10))
                              `(mouse-down ,(+ (window-x s) 150)
                                           ,(+ (window-y s) 10) right 1))
                     (steps 1)
                     (let ([offered (map car (filter pair?
                                                     (menu-entries *menu*)))])
                       (close-menu!)
                       (maximize-window! s)
                       (let ([g (list (shaded? s) (window-state s))])
                         (close-window! s)
                         (and (equal? (list a b c d e f) '(#t #f #t #f #f #t))
                              (member "Unshade" offered)
                              (equal? g '(#f maximized)))))))))))))

(check "the window menu offers Shade only where the style shades"
       (let ([w (open-window "Plain" 'size '(300 . 200) 'pos '(250 . 200))])
         (open-window-menu w 300 220)
         (let ([offered (map car (filter pair? (menu-entries *menu*)))])
           (close-menu!)
           (close-window! w)
           (not (member "Shade" offered)))))

;; A full render of the screen now.
(define (full-render)
  (let ([s (cairo-image-surface-create CAIRO_FORMAT_ARGB32 *canvas-pw*
                                       *canvas-ph*)])
    (render-full-into! s)
    s))

;; Is the screen what a full render draws?
(define (screen-whole?)
  (let ([ref (full-render)])
    (let ([d (max-diff *canvas* ref)]) (cairo-surface-destroy ref) (zero? d))))

(check "an outline drag leaves the window until the release lands it in \
        the outline, which the desktop draws; each move asks for the old \
        and the new outline only, and the frames stay the whole screen's"
       (let ([w (open-window "Outline" 'size '(300 . 200) 'pos '(250 . 200))])
         (set-theme! 'drag-feedback 'outline)
         (steps 1)
         (let* ([g (geometry w)] [x0 (car g)] [y0 (cadr g)]
                [ww (caddr g)] [wh (cadddr g)]
                [tx (+ x0 150)] [ty (+ y0 10)])
           (wm-mouse-move tx ty)
           (wm-mouse-down tx ty 'left 1)
           (steps 1)
           (set! *dirty* #f)
           (wm-mouse-move (+ tx 40) (+ ty 30))
           (let ([first *dirty*] [o1 *drag-outline*] [g1 (geometry w)])
             (set! *dirty* #f)
             (wm-mouse-move (+ tx 60) (+ ty 50))
             (let ([second *dirty*])
               (steps 1)
               (let* ([whole1 (screen-whole?)]
                      [with (full-render)]
                      [without (fluid-let ([*drag-outline* #f]) (full-render))]
                      [drawn (> (max-diff with without) 0)])
                 (cairo-surface-destroy with)
                 (cairo-surface-destroy without)
                 (wm-mouse-up (+ tx 60) (+ ty 50) 'left)
                 (steps 1)
                 (let ([landed (geometry w)] [whole2 (screen-whole?)])
                   (reset-theme!)
                   (close-window! w)
                   (and (equal? g1 g)
                        (equal? o1 (list (+ x0 40) (+ y0 30) ww wh))
                        (equal? first (list (+ x0 40) (+ y0 30)
                                            (+ x0 40 ww) (+ y0 30 wh)))
                        (equal? second (list (+ x0 40) (+ y0 30)
                                             (+ x0 60 ww) (+ y0 50 wh)))
                        drawn whole1 whole2 (not *drag-outline*)
                        (equal? landed (list (+ x0 60) (+ y0 50) ww wh))))))))))

(check "an outline resize lands the outline's size at the release"
       (let ([w (open-window "Outline" 'size '(300 . 200) 'pos '(250 . 200))])
         (set-theme! 'drag-feedback 'outline)
         (steps 1)
         (let* ([g (geometry w)] [r (+ (car g) (caddr g) -2)]
                [b (+ (cadr g) (cadddr g) -2)])
           (inject! `(mouse-move ,r ,b) `(mouse-down ,r ,b left 1)
                    `(mouse-move ,(+ r 30) ,(+ b 20)))
           (steps 1)
           (let ([during (geometry w)])
             (inject! `(mouse-up ,(+ r 30) ,(+ b 20) left))
             (steps 1)
             (let ([after (geometry w)])
               (reset-theme!)
               (close-window! w)
               (and (equal? during g)
                    (equal? after (list (car g) (cadr g) (+ (caddr g) 30)
                                        (+ (cadddr g) 20)))))))))

(check "raise-on-click #f: a press in a window's content gives it the \
        keyboard without raising it; a press on its title raises it"
       (let* ([a (open-window "Under" 'size '(300 . 200) 'pos '(200 . 200))]
              [b (open-window "Over" 'size '(300 . 200) 'pos '(350 . 260))]
              [press! (lambda (x y)
                        (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                                 `(mouse-up ,x ,y left))
                        (steps 1)
                        (list (focused-window) (car (windows))))])
         (steps 1)
         (set-theme! 'raise-on-click #f)
         (let* ([content (press! (+ (window-x a) 40) (+ (window-y a) 100))]
                [title (press! (+ (window-x a) 150) (+ (window-y a) 10))])
           (raise-window! b)
           (reset-theme!)
           (let ([default (press! (+ (window-x a) 40) (+ (window-y a) 100))])
             (close-window! a)
             (close-window! b)
             (and (equal? content (list a b)) (equal? title (list a a))
                  (equal? default (list a a)))))))

;; The canvas's pixel at the device pixel (x, y).
(define (device-pixel x y)
  (cairo-surface-flush *canvas*)
  (pixel-at *canvas* x y))

(define (inverted p) (fxior #xff000000 (fxxor (fxand p #xffffff) #xffffff)))

(check "the bell flashes the screen (or the focused window) inverted for \
        100 ms, at 100 and 200 %, then the screen is as it was; none rings \
        nothing"
       (let* ([real now-ms] [t (now-ms)]
              [w (open-window "Bell" 'size '(300 . 200) 'pos '(250 . 200))])
         (set! now-ms (lambda () t))
         (let ([ok
                (for-all
                 (lambda (pct)
                   (set-theme! 'scale pct)
                   (steps 2)
                   (let* ([s *scale*]
                          [in (list (exact (round (* s 300)))
                                    (exact (round (* s 300))))]
                          [out (list (exact (round (* s 60)))
                                     (exact (round (* s 600))))]
                          [px (lambda (p) (apply device-pixel p))]
                          [before (map px (list in out))])
                     (define (rung how)
                       (set-theme! 'bell how)
                       (steps 1)
                       (bell)
                       (steps 1)
                       (let ([flash (map px (list in out))])
                         (set! t (+ t 99))
                         (steps 1)
                         (let ([still (px in)])
                           (set! t (+ t 1))
                           (steps 2)
                           (list flash still (map px (list in out))
                                 (screen-whole?)))))
                     (let ([screen (rung 'screen)] [window (rung 'window)]
                           [none (rung 'none)])
                       (and (equal? (car screen) (map inverted before))
                            (= (cadr screen) (inverted (car before)))
                            (equal? (caddr screen) before) (cadddr screen)
                            (equal? (car window) (list (inverted (car before))
                                                       (cadr before)))
                            (equal? (caddr window) before) (cadddr window)
                            (equal? (car none) before)))))
                 '(100 200))])
           (set! now-ms real)
           (reset-theme!)
           (set-theme! 'scale 0)
           (steps 1)
           (close-window! w)
           ok)))

;; The middle of the open menu's entry labeled label.
(define (menu-entry-point label)
  (let* ([i (list-index (lambda (e) (and (pair? e) (string=? (car e) label)))
                        (menu-entries *menu*))]
         [a (assv i (placed-menu-areas *menu*))])
    (values (+ (cadr a) (quotient (cadddr a) 2))
            (+ (caddr a) (quotient (list-ref a 4) 2)))))

(check "menu-choose release: a menu opened by a press chooses the entry the \
        button is released over; click (today's) leaves it open"
       (let ([w (open-window "Menus" 'size '(300 . 200) 'pos '(250 . 200))])
         (define (press-drag-release!)
           (let ([tx (+ (window-x w) 150)] [ty (+ (window-y w) 10)])
             (inject! `(mouse-move ,tx ,ty) `(mouse-down ,tx ,ty right 1))
             (steps 1)
             (let-values ([(mx my) (menu-entry-point "Minimize")])
               (inject! `(mouse-move ,mx ,my) `(mouse-up ,mx ,my right))
               (steps 1)
               (let ([r (list (window-state w) (and *menu* #t))])
                 (close-menu!)
                 (focus-window! w)
                 (steps 1)
                 r))))
         (let ([click (press-drag-release!)])
           (set-theme! 'menu-choose 'release)
           (let ([release (press-drag-release!)])
             (reset-theme!)
             (close-window! w)
             (and (equal? click '(normal #t))
                  (equal? release '(minimized #f)))))))

(check "menu-choose release: released over its opener the menu stays open, \
        and a click then chooses"
       (let ([w (open-window "Sticky" 'size '(300 . 200) 'pos '(250 . 200))])
         (set-theme! 'menu-choose 'release)
         (let ([tx (+ (window-x w) 150)] [ty (+ (window-y w) 10)])
           (inject! `(mouse-move ,tx ,ty) `(mouse-down ,tx ,ty right 1)
                    `(mouse-up ,tx ,ty right))
           (steps 1)
           (let ([open (and *menu* #t)])
             (let-values ([(mx my) (menu-entry-point "Minimize")])
               (inject! `(mouse-move ,mx ,my) `(mouse-down ,mx ,my left 1))
               (steps 1)
               (let ([held (list (window-state w) (and *menu* #t))])
                 (inject! `(mouse-up ,mx ,my left))
                 (steps 1)
                 (let ([done (window-state w)])
                   (reset-theme!)
                   (close-window! w)
                   (and open (equal? held '(normal #t))
                        (eq? done 'minimized)))))))))

(check "menu-blink: a chosen entry blinks (off, on) n times, 60 ms a phase, \
        then the menu closes and its action runs"
       (let ([real now-ms] [t (now-ms)] [ran 0] [drawn #f])
         (set! now-ms (lambda () t))
         (set-theme! 'menu-blink 2)
         (set-theme! 'ui-draw-highlight
                     (lambda (x y w h flags) (set! drawn #t)))
         (open-menu! 300 300 (list (cons "One" (lambda () (set! ran (+ ran 1))))
                                   (cons "Two" void)))
         (steps 1)
         (let-values ([(x y) (menu-entry-point "One")])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                    `(mouse-up ,x ,y left))
           (steps 1)
           (let ([phases   ; in order: map may call in any
                  (let loop ([ats '(30 60 60 60 30)])
                    (if (null? ats)
                        '()
                        (begin (set! t (+ t (car ats)))
                               (set! drawn #f)
                               (steps 1)
                               (cons (list ran (and *menu* #t) drawn)
                                     (loop (cdr ats))))))])
             (set! now-ms real)
             (reset-theme!)
             (equal? phases '((0 #t #f) (0 #t #t) (0 #t #f) (0 #t #t)
                              (1 #f #f)))))))

(check "menu-hover outline: the highlight is told outline, and pressed while \
        a button is held on the entry; drawn as a 1-pixel box, then filled"
       (let ([seen '()])
         (set-theme! 'ui-draw-highlight
                     (lambda (x y w h flags) (set! seen flags)))
         (set-theme! 'menu-hover 'outline)
         (set-theme! 'menu-choose 'release)
         (open-menu! 300 300 (list (cons "One" void) (cons "Two" void)))
         (steps 1)
         (let-values ([(x y) (menu-entry-point "One")])
           (inject! `(mouse-move ,x ,y))
           (steps 1)
           (let ([hover seen])
             (inject! `(mouse-down ,x ,y left 1))
             (steps 1)
             (let ([held seen])
               (inject! `(mouse-up ,x ,y left))
               (steps 1)
               (reset-theme!)
               (let ([box (lambda (flags)
                            (pixel-rows (image 8 6 1
                                               (lambda ()
                                                 (fill-rect 0 0 8 6 #x808080)
                                                 (ui-draw-highlight 1 1 6 4
                                                                    flags)))
                                        (list (cons #xff808080 #\.)
                                              (cons (color->pixel 'text)
                                                    #\t))))])
                 (and (equal? hover '(outline)) (equal? held '(outline pressed))
                      (not *menu*)
                      (equal? (box '(outline))
                              '("........" ".tttttt." ".t....t." ".t....t."
                                ".tttttt." "........"))
                      (equal? (box '(outline pressed))
                              '("........" ".tttttt." ".tttttt." ".tttttt."
                                ".tttttt." "........")))))))))

;; Genera's recipe for a window it is not using: its frame-over grays the
;; content with a sparse stipple of ink on clear paper.
(define (test-gray-over win x y w h focused? hover pressed)
  (unless focused?
    (let-values ([(cx cy cw ch) (content-rect win)])
      (fill-rect cx cy cw ch (stipple 'text #f "#..." "...." "...." "....")))))
(define-style test-gray "Gray when unfocused" 'frame-over 'test-gray-over)

(check "an unfocused window is drawn by its style: a stipple of clear paper \
        over its content grays one pixel in sixteen, lined up with the \
        screen; the focused one is untouched"
       (let* ([a (open-window "Unfocused" 'size '(200 . 120) 'pos '(201 . 203)
                              'window-style 'test-gray
                              'draw (lambda (win w h)
                                      (fill-rect 0 0 w h #x000000)))]
              [b (open-window "Focused" 'size '(200 . 120) 'pos '(601 . 203)
                              'window-style 'test-gray
                              'draw (lambda (win w h)
                                      (fill-rect 0 0 w h #x000000)))])
         (steps 1)
         (let ([ink (color->pixel 'text)])
           (define (dots win)   ; the inked device pixels of 40 × 40 inside
             (let-values ([(cx cy cw ch) (content-rect win)])
               (let loop ([i 0] [acc '()])
                 (if (= i 1600)
                     (reverse acc)
                     (let ([x (+ cx 10 (mod i 40))]
                           [y (+ cy 10 (quotient i 40))])
                       (loop (+ i 1)
                             (if (= (canvas-pixel x y) ink)
                                 (cons (cons (mod x 4) (mod y 4)) acc)
                                 acc)))))))
           (let ([da (dots a)] [db (dots b)])
             (close-window! a)
             (close-window! b)
             (and (= (length da) 100) (null? db)
                  (for-all (lambda (p) (equal? p '(0 . 0))) da))))))

;; The device rows that differ between two of canvas-bytes' copies.
(define (rows-between a b)
  (let ([stride (cairo-image-surface-get-stride *canvas*)])
    (filter (lambda (y)
              (not (bytevector=? (bytevector-copy-range a y stride)
                                 (bytevector-copy-range b y stride))))
            (iota (quotient (bytevector-length a) stride)))))

(define (bytevector-copy-range bv row stride)
  (let ([out (make-bytevector stride)])
    (bytevector-copy! bv (* row stride) out 0 stride)
    out))

;; A window of kit widgets, drawn by draw (ui w h).
(define (kit-window title draw)
  (let ([ui (make-ui)])
    (apply open-window title 'size '(400 . 200) 'pos '(300 . 200)
           'draw (lambda (win w h)
                   (ui-begin! ui) (draw ui w h) (ui-end! ui w h))
           (ui-handlers ui))))

(define (doc-at x y)
  (inject! `(mouse-move ,x ,y))
  (steps 1)
  (mouse-doc))

(check "(mouse-doc) is what each button does under the pointer: on a \
        title, a close button, a kit button (its label), a text box, a \
        taskbar button, the desktop"
       (let ([w (kit-window "Docs"
                            (lambda (ui w h)
                              (ui-button ui 'b 20 20 100 30 "Button" void)
                              (ui-text-field ui 't 20 70 200 30 "text"
                                             void)))])
         (steps 2)
         (let*-values ([(cx cy cw ch) (content-rect w)]
                       [(title) (doc-at (+ (window-x w) 200)
                                        (+ (window-y w) 10))]
                       [(close) (doc-at (+ (window-x w) 18)
                                        (+ (window-y w) 15))]
                       [(button) (doc-at (+ cx 50) (+ cy 35))]
                       [(text) (doc-at (+ cx 50) (+ cy 85))]
                       [(taskbar)
                        (let ([a (assq w (with-place 'bar taskbar-areas))])
                          (doc-at (+ (cadr a) 20) (+ (caddr a) 10)))]
                       [(desktop) (doc-at 100 600)])
           (close-window! w)
           (and (equal? title '((L . "Move") (L2 . "Maximize")
                                (R . "Window menu")))
                (equal? close '((L . "Close")))
                (equal? button '((L . "Button")))
                (equal? text '((L . "Place the caret")
                               (L2 . "Select a word")))
                (equal? taskbar '((L . "Focus or minimize") (M . "Close")
                                  (R . "Window menu")))
                (equal? desktop '((L . "Unfocus") (R . "Apps")))))))

;; Two tables and a tree with the same columns, each 50 high, from the
;; top; cells: (id key x w) of each first row's cells, as drawn.
(check "a column's handle: the pointer resize-ew and \"L: Resize column, \
        L2: Default width\" over it; a drag sets the width, the cells \
        follow, the minimum holds; a double click sets back the default; \
        the widths are per table or tree"
       (let* ([columns '((a "A" 100) (b "B" 100) (c "C" 100))]
              [cells '()] [ui #f]
              [cell (lambda (id)
                      (lambda (row key x y w h flags)
                        (when (eqv? row 1)
                          (set! cells (cons (list id key x w) cells)))))]
              [w (kit-window "Columns"
                             (lambda (u w h)
                               (set! ui u)
                               (set! cells '())
                               (ui-table u 't 0 0 w 50 columns '(1 2) #f void
                                         (cell 't))
                               (ui-table u 'u 0 50 w 50 columns '(1 2) #f
                                         void (cell 'u))
                               (ui-tree u 'r 0 100 w 50 columns '(1)
                                        (lambda (n) '()) #f void (cell 'r))))])
         (steps 2)
         (let*-values ([(cx cy cw ch) (content-rect w)]
                       [(hy) (+ cy (quotient (ui-table-header-height) 2))]
                       [(over) (doc-at (+ cx 101) hy)]
                       [(shape) (window-ref w 'cursor 'arrow)])
           (define (widths id)
             (map caddr (ui-table-columns ui id columns)))
           (define (drag! x0 x1 y)
             (inject! `(mouse-move ,x0 ,y) `(mouse-down ,x0 ,y left 1)
                      `(mouse-move ,x1 ,y) `(mouse-up ,x1 ,y left))
             (steps 2))
           (drag! (+ cx 101) (+ cx 141) hy)
           (let ([dragged (widths 't)] [drawn (reverse cells)]
                 [ry (+ cy 100 (quotient (ui-table-header-height) 2))])
             (drag! (+ cx 141) (+ cx 10) hy)
             (let ([narrow (widths 't)])
               (inject! `(mouse-down ,(+ cx (car narrow)) ,hy left 2)
                        `(mouse-up ,(+ cx (car narrow)) ,hy left))
               (steps 2)
               (let ([reset (widths 't)])
                 (drag! (+ cx 199) (+ cx 179) ry)
                 (let ([tree (list (widths 't) (widths 'u) (widths 'r))])
                   (close-window! w)
                   (steps 1)
                   (and (eq? shape 'resize-ew)
                        (equal? over '((L . "Resize column")
                                       (L2 . "Default width")))
                        (equal? dragged '(140 100 100))
                        (equal? (filter (lambda (c) (eq? (car c) 't)) drawn)
                                '((t a 0 140) (t b 140 100) (t c 240 100)))
                        (equal? (filter (lambda (c) (eq? (car c) 'u)) drawn)
                                '((u a 0 100) (u b 100 100) (u c 200 100)))
                        (equal? narrow (list (ui-table-column-min) 100 100))
                        (equal? reset '(100 100 100))
                        (equal? tree '((100 100 100) (100 100 100)
                                       (100 80 100)))))))))))

;; The columns a heading inks, (first . last), drawn 200 wide in style
;; with flags and dir; its bottom line left out.
;; The line between two headings is there at rest, under the pointer
;; in the accent, wider: found before the pointer changes.
(check "a divider marks each column's handle at rest, and is the accent \
        under the pointer"
       (let ([draw (lambda (flags)
                     (let* ([img (image 20 30 1
                                        (lambda ()
                                          (fill-rect 0 0 20 30 'bg-1)
                                          (ui-draw-table-divider 10 0 30
                                                                 flags)))]
                            [bg (pixel-at img 2 15)]
                            [mid (pixel-at img 10 15)]
                            [left (pixel-at img 9 15)])
                       (cairo-surface-destroy img)
                       (list (not (= mid bg)) (not (= left bg)) mid)))])
         (let ([rest (draw '())] [hot (draw '(hover))])
           (and (car rest) (not (cadr rest))
                (car hot) (cadr hot)
                (= (caddr hot) (color->pixel 'accent))))))

(check "where dividers show by the style's table-dividers: always at \
        rest, hover over the headings, handle only under the pointer"
       (with-test-styles
        (lambda ()
          (let ([shown (lambda (mode)
                         (define-style test-dividers "Test"
                           'table-dividers mode)
                         (set-style! 'test-dividers)
                         (map (lambda (args)
                                (apply ui-table-divider-shown? args))
                              '((#f #f) (#t #f) (#f #t))))])
            (and (equal? (shown 'always) '(#t #t #t))
                 (equal? (shown 'hover) '(#f #t #t))
                 (equal? (shown 'handle) '(#f #f #t))
                 (with-style 'mac
                   (lambda () (eq? (theme 'table-dividers) 'always))))))))

(check "Genera's removable tag under the mouse boxes its × alone, not \
        the tag: what a click removes"
       (with-style 'genera
         (lambda ()
           (let* ([draw (lambda (flags)
                          (image 120 30 1
                                 (lambda ()
                                   (fill-rect 0 0 120 30 'bg-1)
                                   (ui-draw-chip 10 5 100 20 flags "tag"))))]
                  [rest (draw '(removable))] [hot (draw '(removable hover))]
                  [a (cdr (assq 'remove (ui-chip-areas 10 5 100 20)))]
                  ;; the columns where hovering changed a pixel
                  [changed (filter (lambda (x)
                                     (exists (lambda (y)
                                               (not (= (pixel-at rest x y)
                                                       (pixel-at hot x y))))
                                             (iota 30)))
                                   (iota 120))])
             (let ([r (and (pair? changed)
                           (>= (apply min changed) (- (car a) 3)))])
               (cairo-surface-destroy rest)
               (cairo-surface-destroy hot)
               r)))))

(define (heading-ink style flags dir)
  (with-style style
    (lambda ()
      (let* ([img (image 200 30 1
                         (lambda ()
                           (fill-rect 0 0 200 30 'bg-1)
                           (ui-draw-table-header 0 0 200 30 flags "ms/s"
                                                 dir)))]
             [bg (pixel-at img 199 2)]
             [xs (filter (lambda (x)
                           (exists (lambda (y) (not (= (pixel-at img x y) bg)))
                                   (iota 27)))
                         (iota 200))])
        (cairo-surface-destroy img)
        (cons (apply min xs) (apply max xs))))))

(check "a heading starts 10 pixels from its left, its sort arrow after \
        it, whether its column's cells are right-aligned (right) or not: \
        the kit's, Genera's and Cons's"
       (for-all
        (lambda (style)
          (let ([left (heading-ink style '() #f)]
                [left-sorted (heading-ink style '() 'down)]
                [right (heading-ink style '(right) #f)]
                [right-sorted (heading-ink style '(right) 'down)])
            (and (<= 9 (car left) 12) (< (cdr left) 100)
                 (= (car left-sorted) (car left))
                 (> (cdr left-sorted) (cdr left))
                 (equal? right left)
                 (equal? right-sorted left-sorted))))
        '(mac genera cons)))

(check "a tree's headings: with 'on-sort a press on one calls it with its \
        key, the one 'sort names shows its direction; a column's flags are \
        its heading's and its cells'; without 'on-sort no heading takes a \
        press"
       (with-test-styles
        (lambda ()
          (let ([heads '()] [cells '()] [pressed #f] [ui #f]
                [columns '((a "A" 100) (b "B" 100 right))])
            (define-style test-heads "Test"
              'ui-draw-table-header
              (lambda (x y w h flags label dir)
                (set! heads (cons (list label flags dir) heads))))
            (set-style! 'test-heads)
            (let ([w (kit-window "Heads"
                       (lambda (u w h)
                         (set! ui u)
                         (set! heads '())
                         (set! cells '())
                         ;; drawn first: its headings are found after s's
                         (ui-tree u 'q 0 90 w 80 columns '(1) (lambda (n) '())
                                  #f void (lambda cell #f))
                         (ui-tree u 's 0 0 w 80 columns '(1) (lambda (n) '())
                                  #f void
                                  (lambda (n key x y w h flags)
                                    (set! cells (cons (cons key flags) cells)))
                                  'sort '(b . down)
                                  'on-sort (lambda (k) (set! pressed k)))))])
              (steps 2)
              (let-values ([(cx cy cw ch) (content-rect w)])
                (let* ([b-head (assoc "B" heads)]
                       [a-cell (cdr (assq 'a cells))]
                       [b-cell (cdr (assq 'b cells))]
                       [y (+ cy (quotient (ui-table-header-height) 2))])
                  (inject! `(mouse-move ,(+ cx 150) ,y)
                           `(mouse-down ,(+ cx 150) ,y left 1)
                           `(mouse-up ,(+ cx 150) ,y left))
                  (steps 2)
                  (close-window! w)
                  (steps 1)
                  (and (eq? pressed 'b)
                       (memq 'right (cadr b-head)) (eq? (caddr b-head) 'down)
                       (not (caddr (assoc "A" heads)))
                       (memq 'right b-cell) (not (memq 'right a-cell))
                       (ui-find ui '(s header a))
                       (not (ui-find ui '(q header a)))))))))))

;; A style whose shade button words itself.
(define (test-words-regions win)
  (list (list 'shade 30 4 20 20 '((L . "Roll up") (R . "Nothing")))))
(define-style test-words "Own words" 'frame-regions 'test-words-regions)

(check "a style's regions word themselves, and the actions its settings \
        name read: a shading title, a menu button closing on a double click"
       (let ([w (open-window "Words" 'size '(300 . 200) 'pos '(250 . 200)
                             'window-style 'test-menu)]
             [v (open-window "Own" 'size '(300 . 200) 'pos '(600 . 200)
                             'window-style 'test-words)])
         (override! 'title-double-click 'shade)
         (override! 'title-wheel 'shade)
         (steps 1)
         (let* ([title (doc-at (+ (window-x w) 150) (+ (window-y w) 10))]
                [menu (doc-at (+ (window-x w) 10) (+ (window-y w) 10))]
                [own (doc-at (+ (window-x v) 40) (+ (window-y v) 10))])
           (reset-theme!)
           (close-window! w)
           (close-window! v)
           (and (equal? title '((L . "Move") (L2 . "Shade")
                                (R . "Window menu") (W . "Shade")))
                (equal? menu '((L . "Window menu") (L2 . "Close")))
                (equal? own '((L . "Roll up") (R . "Nothing")))))))

(check "with mouse-doc on the top bar shows it, and a move between regions \
        of other words changes the bar's rows alone, one between regions of \
        the same words nothing"
       (let ([w (kit-window "Areas"
                            (lambda (ui w h)
                              (ui-area ui 'a 0 0 100 100 void #f
                                       'doc '((L . "One")))
                              (ui-area ui 'b 100 0 100 100 void #f
                                       'doc '((L . "Two")))
                              (ui-area ui 'c 200 0 100 100 void #f
                                       'doc '((L . "Two")))))])
         (set-theme! 'mouse-doc #t)
         (steps 2)
         (let-values ([(cx cy cw ch) (content-rect w)])
           (define (rows-after-move x)
             (let ([before (canvas-bytes)])
               (inject! `(mouse-move ,x ,(+ cy 50)))
               (steps 1)
               (rows-between before (canvas-bytes))))
           (rows-after-move (+ cx 50))
           (let* ([shown (mouse-doc)]
                  [text (mouse-doc-text shown)]
                  [other (rows-after-move (+ cx 150))]
                  [same (rows-after-move (+ cx 250))])
             (reset-theme!)
             (close-window! w)
             (and (equal? shown '((L . "One"))) (equal? text "L: One")
                  (pair? other)
                  (for-all (lambda (y) (< y (* *scale* (topbar-height))))
                           other)
                  (null? same))))))

;; A window whose content is a scroll view of 40 bars, 800 high.
(define (scroll-window title . opts)
  (let ([ui (make-ui)])
    (apply open-window title 'size '(300 . 200) 'pos '(300 . 200)
           'draw (lambda (win w h)
                   (ui-begin! ui)
                   (ui-scroll ui 'v 0 0 w h
                     (lambda (top)
                       (do ([i 0 (+ i 1)]) ((= i 40))
                         (fill-rect 10 (+ top (* i 20)) 260 10 'accent))
                       (+ top 800)))
                   (ui-end! ui w h))
           (append opts (ui-handlers ui)))))

;; Where the window's view has its bar: its region's x, or #f for none.
(define (bar-x win)
  (let ([r (ui-find (window-ref win 'ui) '(v bar))]) (and r (ui-region-x r))))

(check "a scroll bar is on the right by default, on the left where the \
        style says so"
       (let ([w (scroll-window "Sides")])
         (steps 1)
         (let ([right (bar-x w)])
           (set-theme! 'scrollbar-side 'left)
           (steps 1)
           (let ([left (bar-x w)])
             (reset-theme!)
             (close-window! w)
             (and (= right (- 300 (ui-scrollbar-width))) (= left 0))))))

(check "a scroll bar shown on hover appears while the pointer is over the \
        view, over its content, which does not move"
       (let ([w (scroll-window "Hover")])
         (set-theme! 'scrollbar-show 'hover)
         (inject! '(mouse-move 100 700))
         (steps 2)
         (let-values ([(cx cy cw ch) (content-rect w)])
           (let* ([row (lambda () (map (lambda (dx) (canvas-pixel (+ cx dx)
                                                                  (+ cy 5)))
                                       '(10 100 200)))]
                  [away (list (bar-x w) (row))])
             (inject! `(mouse-move ,(+ cx 100) ,(+ cy 100)))
             (steps 2)
             (let ([over (list (bar-x w) (row))])
               (reset-theme!)
               (close-window! w)
               (and (not (car away)) (car over)
                    (equal? (cadr away) (cadr over))))))))

;; Medley's scroll bars: a 24-pixel margin at the left of the frame,
;; clear but for the bar while the pointer is there.
(define (test-out-insets win) (values 24 (title-height) 0 0))
(define (test-out-regions win)
  (list (list 'scrollbar 0 (title-height) 24
              (- (window-h win) (title-height)))))
(define (test-out-over win x y w h focused? hover pressed)
  (ui-frame-scrollbar win))
(define-style test-out "Outside scroll bars"
  'frame-insets 'test-out-insets 'frame-regions 'test-out-regions
  'frame-over 'test-out-over 'scrollbar-side 'outside 'scrollbar-width 24
  'scrollbar-show 'hover)

(check "a scroll bar outside the window: its margin clear, the bar there \
        while the pointer is, a press there the app's (it scrolls)"
       (let* ([w (scroll-window "Outside" 'window-style 'test-out)]
              [mx (+ (window-x w) 12)] [my (+ (window-y w) 150)])
         (inject! '(mouse-move 100 700))
         (steps 2)
         (let ([clear (canvas-pixel mx (+ (window-y w) 50))])
           (minimize-window! w)
           (steps 2)
           (let ([desk (canvas-pixel mx (+ (window-y w) 50))])
             (focus-window! w)
             (inject! `(mouse-move ,mx ,my))
             (steps 2)
             (let ([region (window-region w mx my)] [at (bar-x w)]
                   [shown (canvas-pixel mx (+ (window-y w) 50))])   ; thumb
               (inject! `(mouse-down ,mx ,my left 1) `(mouse-up ,mx ,my left))
               (steps 2)
               (let ([off (car (ui-memo (window-ref w 'ui) 'v '(0 . 0)))])
                 (close-window! w)
                 (and (= clear desk) (eq? region 'scrollbar)
                      (not (= shown desk)) (= at -24) (> off 0))))))))

;;; the verifier's findings on the behaviors switched on

(check "behavior settings survive a save and load, each of its kind; a \
        value of another kind is dropped"
       (let ([set '((title-double-click . shade) (raise-on-click . #f)
                    (bell . screen) (mouse-doc . #t) (frame-edge . 8)
                    (menu-blink . 2) (title-wheel . shade)
                    (drag-feedback . outline) (scrollbar-side . left)
                    (button-double-click . ((menu . close))))])
         (for-each (lambda (kv) (override! (car kv) (cdr kv))) set)
         (theme-file-save!)
         (reset-theme!)
         (theme-file-load!)
         (let ([got (map (lambda (kv) (theme (car kv))) set)])
           (reset-theme!)
           (theme-file-save!)
           (and (equal? got (map cdr set))
                (not (theme-file-valid-value? 'bell #t))
                (not (theme-file-valid-value? 'frame-edge 'wide))
                (not (theme-file-valid-value? 'no-such-key 3))))))

(check "menu-choose release: a menu that opens under the pointer stays open \
        when the press that opened it is released there (a taskbar \
        button's, the desktop's)"
       (let ([w (open-window "Under" 'size '(300 . 200) 'pos '(250 . 200))])
         (set-theme! 'menu-choose 'release)
         (steps 1)
         (let* ([a (assq w (with-place 'bar taskbar-areas))]
                [x (+ (cadr a) 20)] [y (+ (caddr a) 10)])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y right 1))
           (steps 1)
           (let ([under (and (menu-entry-at x y) #t)])
             (inject! `(mouse-up ,x ,y right))
             (steps 1)
             (let ([taskbar (list under (and *menu* #t)
                                  (and (memq w (windows)) #t))])
               (close-menu!)
               (inject! '(mouse-move 900 500) '(mouse-down 900 500 right 1)
                        '(mouse-up 900 500 right))
               (steps 1)
               (let ([desk (launcher-open?)])
                 (close-menu!)
                 (reset-theme!)
                 (when (memq w (windows)) (close-window! w))
                 (and (equal? taskbar '(#t #t #t)) desk)))))))

(check "menu-hover outline: moved off the menu with the button held, the \
        entry is drawn pressed no more"
       (begin
         (set-theme! 'menu-hover 'outline)
         (set-theme! 'menu-choose 'release)
         (open-menu! 300 300 (list (cons "One" void) (cons "Two" void)))
         (steps 1)
         (let-values ([(x y) (menu-entry-point "One")])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1))
           (steps 1)
           (inject! `(mouse-move ,x ,(- y 200)))
           (steps 1)
           (let ([whole (screen-whole?)])
             (inject! `(mouse-up ,x ,(- y 200) left))
             (steps 1)
             (close-menu!)
             (reset-theme!)
             whole))))

(check "a blinking entry asks for the menu's box, not the screen"
       (let ([real now-ms] [t (now-ms)])
         (set! now-ms (lambda () t))
         (set-theme! 'menu-blink 2)
         (open-menu! 300 300 (list (cons "One" void) (cons "Two" void)))
         (steps 1)
         (let-values ([(x y) (menu-entry-point "One")])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                    `(mouse-up ,x ,y left))
           (steps 1)
           (set! t (+ t 70))
           (set! *dirty* #f)
           (wm-tick!)
           (let ([asked *dirty*]
                 [box (call-with-values (lambda () (menu-geometry *menu*))
                        (lambda (mx my mw mh)
                          (list mx my (+ mx mw) (+ my mh))))])
             (set! t (+ t 300))
             (steps 1)
             (set! now-ms real)
             (reset-theme!)
             (equal? asked box)))))

;; An outside bar's style whose bars are narrower than its margin.
(define-style test-out-narrow "Outside, narrow"
  'parent 'test-out 'scrollbar-width 10)

(check "an outside scroll bar fills its margin, however narrow the style's \
        bars, and the wheel there scrolls its view"
       (let* ([w (scroll-window "Narrow" 'window-style 'test-out-narrow)]
              [mx (+ (window-x w) 3)]
              [off (lambda () (car (ui-memo (window-ref w 'ui) 'v '(0 . 0))))])
         (inject! `(mouse-move ,mx ,(+ (window-y w) 150)))
         (steps 2)
         (inject! `(mouse-down ,mx ,(+ (window-y w) 150) left 1)
                  `(mouse-up ,mx ,(+ (window-y w) 150) left))
         (steps 2)
         (let ([pressed (off)])
           (inject! `(mouse-move ,mx ,(+ (window-y w) 60)) '(wheel 0 1))
           (steps 2)
           (let ([wheeled (off)])
             (close-window! w)
             (and (> pressed 0) (< wheeled pressed))))))

(check "across a change of the chrome a shaded window stays shaded, in its \
        new frame's height, and its app hears the size it unshades to; \
        under a style that cannot shade it unshades, and hears it too"
       (let* ([heard '()]
              [w (open-window "Stays shaded" 'size '(300 . 200)
                              'pos '(250 . 200)
                              'resize (lambda (win cw ch)
                                        (set! heard (cons (cons cw ch)
                                                          heard))))]
              [content (lambda () (call-with-values
                                    (lambda () (window-content-size w))
                                    cons))])
         (steps 1)
         (shade-window! w)
         (set-theme! 'title-height 40)
         (steps 1)
         (let*-values ([(l t r b) (frame-insets w)]
                       [(after) (list (shaded? w) (window-h w))]
                       [(told) (car heard)])
           (unshade-window! w)
           (let ([unshaded (content)])
             (shade-window! w)
             (set-style! 'spine)
             (steps 1)
             (let ([spine (list (shaded? w) (equal? (car heard) (content)))])
               (set-style! 'mac)
               (reset-theme!)
               (close-window! w)
               (and (equal? after (list #t (+ t b))) (equal? told unshaded)
                    (equal? spine '(#f #t))))))))

(check "menu-choose release: a press that opened a menu under the pointer \
        and wobbles on its entry, then releases there, chooses nothing"
       (let ([w (open-window "Wobble" 'size '(300 . 200) 'pos '(250 . 200))])
         (set-theme! 'menu-choose 'release)
         (steps 1)
         (let* ([a (assq w (with-place 'bar taskbar-areas))]
                [x (+ (cadr a) 20)] [y (+ (caddr a) 10)])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y right 1))
           (steps 1)
           (let ([entry (menu-entry-at x y)])
             (inject! `(mouse-move ,(+ x 5) ,y) `(mouse-move ,x ,y)
                      `(mouse-up ,x ,y right))
             (steps 1)
             (let ([open (and *menu* #t)] [alive (and (memq w (windows)) #t)])
               (close-menu!)
               (reset-theme!)
               (when alive (close-window! w))
               (and entry open alive))))))

(check "scroll bars outside fall back to the right where the frame leaves \
        no margin"
       (let ([w (scroll-window "No margin")])
         (set-theme! 'scrollbar-side 'outside)
         (steps 1)
         (let ([x (bar-x w)])
           (reset-theme!)
           (close-window! w)
           (= x (- 300 (ui-scrollbar-width))))))

;; A style whose grow box resizes, the window manager's edges off.
(define (test-grow-regions win)
  (list (list 'resize-br (- (window-w win) 15) (- (window-h win) 15) 15 15)))
(define-style test-grow "Grow box"
  'frame-regions 'test-grow-regions 'frame-edge 0)

(check "a style's own resize region resizes a normal window only, not a \
        shaded or a maximized one"
       (let* ([w (open-window "Grow" 'size '(300 . 200) 'pos '(250 . 200)
                              'window-style 'test-grow)]
              [size (lambda () (list (window-w w) (window-h w)))]
              [grow! (lambda ()
                       (let ([x (+ (window-x w) (window-w w) -5)]
                             [y (+ (window-y w) (window-h w) -5)])
                         (drag-on! x y (+ x 30) (+ y 20))
                         (size)))])
         (steps 1)
         (let* ([s0 (size)] [normal (grow!)]
                [shaded (begin (shade-window! w) (let ([s (size)])
                                                   (list s (grow!))))]
                [maxed (begin (unshade-window! w) (maximize-window! w)
                              (let ([s (size)]) (list s (grow!))))])
           (close-window! w)
           (and (equal? normal (list (+ (car s0) 30) (+ (cadr s0) 20)))
                (equal? (car shaded) (cadr shaded))
                (equal? (car maxed) (cadr maxed))))))

(check "a top resize keeps the window's top on the desktop, its bottom \
        where it was"
       (let ([w (open-window "Top" 'size '(300 . 200) 'pos '(300 . 100)
                             'window-style 'test-top)])
         (steps 1)
         (let* ([g (geometry w)] [x (+ (car g) 100)] [y (+ (cadr g) 2)]
                [bottom (+ (cadr g) (cadddr g))])
           (drag-on! x y x 2)
           (let-values ([(dx dy dw dh) (desktop-rect)])
             (let ([g2 (geometry w)])
               (close-window! w)
               (and (= (cadr g2) dy) (= (+ (cadr g2) (cadddr g2)) bottom)))))))

(check "old calls keep working: ui-pressable! without a doc, the glyphs \
        sort-up and sort-down; a text field's 'doc is its own"
       (let* ([glyph (lambda (name)
                       (image 20 20 1 (lambda ()
                                        (ui-draw-glyph 2 2 16 16 '() name))))]
              [same (lambda (a b) (zero? (max-diff (glyph a) (glyph b))))]
              [w (kit-window "Old calls"
                             (lambda (ui w h)
                               (ui-pressable! ui 'p 20 20 100 30 void '() '())
                               (ui-text-field ui 't 20 70 200 30 "text" void
                                              'doc '((L . "Edit me")))))])
         (steps 2)
         (let-values ([(cx cy cw ch) (content-rect w)])
           (let ([doc (doc-at (+ cx 50) (+ cy 85))])
             (close-window! w)
             (and (same 'sort-up 'up) (same 'sort-down 'down)
                  (not (window-error w))
                  (equal? doc '((L . "Edit me"))))))))

;;; Settings' Theme tab (step 8)

;; A style with options of its own: a size, a choice.
(define-style test-own "Own options"
  'test-own-width 3  'test-own-ink 'dim
  'options '(palette (test-own-width "Width" 1 6)
             (test-own-ink "Ink" (("Dim" . dim) ("Bright" . bright)))))

(check "a style's own option's value saves and loads back, of the kind the \
        style gives it; one of another kind is dropped"
       (begin
         (set-style! 'test-own)
         (set-theme! 'test-own-width 5)
         (set-theme! 'test-own-ink 'bright)
         (theme-file-save!)
         (reset-theme!)
         (theme-file-load!)
         (let ([got (list (theme 'test-own-width) (theme 'test-own-ink))])
           (reset-theme!)
           (set-style! 'mac)
           (and (equal? got '(5 bright))
                (theme-file-valid-value? 'test-own-width 2)
                (not (theme-file-valid-value? 'test-own-width 'wide))
                (not (theme-file-valid-value? 'test-own-ink 4))))))

(check "Settings shows a style's own options, and the common ones it does \
        not honor as fixed"
       (begin
         (set-style! 'test-own)
         (let ([own (map car (settings-own-options))]
               [words (settings-value-words 'test-own-ink 'bright)]
               [fixed (theme 'fixed)])
           (set-style! 'mac)
           (and (equal? own '(test-own-width test-own-ink))
                (equal? words "Bright")
                (memq 'corner-radius fixed) (not (memq 'palette fixed))
                (null? (settings-own-options))
                (not (settings-option 'test-own-ink))))))

(check "a detached window is a window in its style that is not on screen"
       (let ([w (detached-window "Away" 'size '(200 . 100)
                                 'window-style 'genera)])
         (let-values ([(l t r b) (frame-insets w)])
           (and (not (memq w (windows)))
                (= (window-w w) (+ 200 l r)) (= (window-h w) (+ 100 t b))
                (eq? (window-ref w 'window-style) 'genera)))))

(check "save-style-as! writes a define-style of your changes over the \
        chosen style, loads it and chooses it; a name in use is refused"
       (let ([dir (string-append out-dir "/saved-styles")])
         (set! *settings-style-directory* dir)
         (when (file-exists? (string-append dir "/test-saved.ss"))
           (delete-file (string-append dir "/test-saved.ss")))
         (set-style! 'test-own)
         (set-theme! 'test-own-width 4)
         (set-theme! 'palette 'nord)
         (let* ([path (save-style-as! 'test-saved "Test saved")]
                [form (call-with-input-file path read)]
                [ok (list (current-style) (style-changes-of 'test-own)
                          (theme 'test-own-width) (theme 'palette)
                          (raises? (lambda () (save-style-as! 'mac "Mac"))))])
           (set-style! 'mac)
           (reset-theme!)
           (set! *styles* (remp (lambda (s) (memq (style-name s)
                                                  '(test-saved test-own)))
                                *styles*))
           (and (equal? form '(define-style test-saved "Test saved"
                                'parent 'test-own 'palette 'nord
                                'test-own-width 4))
                (equal? ok '(test-saved () 4 nord #t))))))

(check "a new style's name comes from its title"
       (and (eq? (settings-style-name "My Genera") 'my-genera)
            (eq? (settings-style-name "  CDE: Broica II ") 'cde-broica-ii)
            (not (settings-style-name " - "))))

;;; Our styles, finished (step 9)

(define (style-insets st)
  (let ([w (open-window "Insets" 'size '(300 . 200) 'window-style st)])
    (let-values ([(l t r b) (frame-insets w)])
      (close-window! w)
      (list l t r b))))

(check "at the default fonts the insets are Genera's 6 6 6 23, the CADR's \
        2 2 2 and its label strip, the code font's line and 2, Interlisp's \
        4 17 4 4"
       (and (equal? (style-insets 'genera) '(6 6 6 23))
            (equal? (style-insets 'cadr)
                    (list 2 2 2 (+ 2 (exact (round (+ 2 (font-line-height
                                                         'mono)))))))
            (equal? (style-insets 'interlisp) '(4 17 4 4))))

(check "our styles' own behaviors, and the CADR's Genera's but its frame \
        and its gray"
       (let ([of (lambda (st . keys)
                   (with-style st (lambda () (map theme keys))))])
         (and (equal? (of 'fold 'title-double-click) '(shade))
              (equal? (of 'lambda 'title-wheel) '(shade))
              (equal? (of 'halo 'scrollbar-show) '(hover))
              (equal? (of 'reticle 'scrollbar-show 'drag-feedback
                          'draw-drag-outline)
                      '(hover outline reticle-drag-outline))
              (equal? (of 'draft 'drag-feedback 'draw-drag-outline)
                      '(outline draft-drag-outline))
              (equal? (of 'curses 'bell 'menu-hover) '(screen outline))
              (equal? (of 'genera 'mouse-doc 'bell 'menu-hover 'scrollbar-side
                          'title-double-click 'topbar-height)
                      '(#t screen outline left none 0))
              (equal? (of 'cadr 'mouse-doc 'draw-taskbar 'genera-border
                          'genera-margin 'genera-label-font
                          'genera-label-align 'frame-over)
                      '(#t genera-draw-who-line 1 1 mono top frame-over*))
              (equal? (of 'interlisp 'drag-feedback 'draw-drag-outline
                          'menu-choose 'menu-hover 'bell 'title-double-click
                          'scrollbar-side 'scrollbar-show 'scrollbar-width)
                      '(outline interlisp-drag-outline release outline window
                        none left hover 24))
              (equal? (of 'spine 'title-double-click 'title-wheel)
                      '(maximize none))
              (equal? (of 'mac 'drag-feedback 'bell 'mouse-doc)
                      '(live none #f)))))

;; An outline drawn on white at 100 and 150 %: what changed, and what
;; changed outside its rectangle.
(define (outline-changes st w h)
  (map (lambda (s)
         (with-style st
           (lambda ()
             (let* ([k (lambda (v) (exact (round (* v s))))]
                    [paint (lambda (outline?)
                             (image (k 300) (k 200) (inexact s)
                                    (lambda ()
                                      (fill-rect 0 0 300 200 #xffffff)
                                      (when outline?
                                        (draw-drag-outline 20 30 w h)))))]
                    [blank (paint #f)] [drawn (paint #t)]
                    [r (list (max-diff blank drawn)
                             (max-diff blank drawn
                                       (list (k 20) (k 30) (k (+ 20 w))
                                             (k (+ 30 h)))))])
               (cairo-surface-destroy blank)
               (cairo-surface-destroy drawn)
               r))))
       '(1 3/2)))

(check "Draft's, Reticle's and Interlisp's outlines are drawn within their \
        rectangle, smaller than one of Reticle's brackets too"
       (for-all (lambda (st)
                  (for-all (lambda (wh)
                             (for-all (lambda (r)
                                        (and (> (car r) 0) (= (cadr r) 0)))
                                      (outline-changes st (car wh) (cdr wh))))
                           '((240 . 120) (30 . 20) (8 . 8))))
                '(draft reticle interlisp)))

(check "Draft's outline shows the live size, where it fits"
       (with-style 'draft
         (lambda ()
           (let* ([at (lambda (w)
                        (image 300 200 1
                               (lambda ()
                                 (fill-rect 0 0 300 200 #xffffff)
                                 (draw-drag-outline 20 30 w 120))))]
                  [a (at 240)] [b (at 239)] [narrow (at 60)]
                  [plain (image 300 200 1
                                (lambda ()
                                  (fill-rect 0 0 300 200 #xffffff)
                                  (stroke-rect 20 30 60 120 'accent)))]
                  ;; the right edge moved; the label changed too
                  [r (list (max-diff a b '(250 0 300 200))
                           (max-diff narrow plain))])
             (for-each cairo-surface-destroy (list a b narrow plain))
             (and (> (car r) 0) (= (cadr r) 0))))))

(check "Genera grays a window not selected with a sparse stipple, and not \
        the selected one"
       (let* ([a (open-window "A" 'size '(200 . 120) 'pos '(100 . 100)
                              'window-style 'genera)]
              [b (open-window "B" 'size '(200 . 120) 'pos '(500 . 100)
                              'window-style 'genera)])
         (steps 2)
         (let* ([dot (lambda (win)   ; the first stipple dot in its content
                       (let-values ([(cx cy cw ch) (content-rect win)])
                         (canvas-pixel (* 4 (ceiling (/ cx 4)))
                                       (* 4 (ceiling (/ cy 4))))))]
                [r (list (dot a) (dot b)
                         (with-style 'genera
                           (lambda () (list (color->pixel 'text)
                                            (color->pixel 'window-bg)))))])
           (close-window! a)
           (close-window! b)
           (steps 1)
           (equal? (list (car r) (cadr r)) (caddr r)))))

(check "Genera's buttons are command words: plain, boxed under the \
        pointer and while pressed, reversed while chosen"
       (with-style 'genera
         (lambda ()
           (let ([at (lambda (flags)
                       (let* ([img (image 120 40 1
                                          (lambda ()
                                            (fill-rect 0 0 120 40 'window-bg)
                                            (ui-draw-button 10 5 100 30 flags
                                                            "Go" #f)))]
                              [ps (list (pixel-at img 10 5)
                                        (pixel-at img 60 8))])
                         (cairo-surface-destroy img)
                         ps))]
                 [ink (color->pixel 'text)] [paper (color->pixel 'window-bg)])
             (and (equal? (at '()) (list paper paper))
                  (equal? (at '(hover)) (list ink paper))
                  (equal? (at '(pressed hover)) (list ink paper))
                  (equal? (at '(selected)) (list ink ink)))))))

(check "faint text is in its font's italic, bold kept, where a style says \
        so ('faint-text-font, Genera's); other text and styles keep theirs"
       (and (with-style 'mac
              (lambda () (eq? (faint-font 'text-faint (get-font 'ui))
                              (get-font 'ui))))
            (with-style 'genera
              (lambda ()
                (let ([f (faint-font 'text-faint (get-font 'mono-bold))])
                  (and (eq? (font-slant f) 'italic)
                       (eq? (font-weight f) 'bold)
                       (eq? (faint-font 'text (get-font 'mono))
                            (get-font 'mono))))))))

(check "the CADR's lozenge: 9 pixels high, 9 + 6 a character wide, pointed \
        ends, the name in capitals of MIT's 5X5"
       (let* ([img (image 30 12 1
                          (lambda ()
                            (fill-rect 0 0 30 12 #xffffff)
                            (px-lozenge 0 0 "a" #x000000)))]
              [r (list (px-lozenge-width "AB")
                       (map (lambda (p) (= (apply pixel-at img p) #xff000000))
                            '((0 4) (3 1) (3 7) (4 0) (4 8) (14 4) (11 1)
                              (6 2) (5 2) (5 4) (9 4) (6 6) (5 6))))])
         (cairo-surface-destroy img)
         (equal? r '(21 (#t #t #t #t #t #t #t #t #f #t #t #f #t)))))

(check "Genera chooses in inverse video: a row's 2-pixel box, its inside \
        turned once its cells are drawn (ui-draw-highlight-over); Mac turns \
        nothing"
       (let ([at (lambda (style)
                   (with-style style
                     (lambda ()
                       (let* ([img (image 100 24 1
                                          (lambda ()
                                            (fill-rect 0 0 100 24 #xffffff)
                                            (ui-draw-table-row 0 0 100 24
                                                               '(selected))
                                            (fill-rect 10 8 6 6 #x000000)
                                            (ui-draw-highlight-over
                                             0 0 100 24 '())))]
                              [ps (map (lambda (p) (apply pixel-at img p))
                                       '((0 0) (50 12) (12 10)))])
                         (cairo-surface-destroy img)
                         ps))))])
         (and (equal? (at 'genera) '(#xff000000 #xff000000 #xffffffff))
              (= (caddr (at 'mac)) #xff000000))))

(check "a table calls ui-draw-highlight-over on its chosen row after the \
        row's cells, and on no other"
       (with-test-styles
        (lambda ()
          (let ([seen '()] [ui (make-ui)])
            (define-style test-over "Test"
              'ui-draw-highlight-over
              (lambda (x y w h flags) (set! seen (cons 'over seen))))
            (set-style! 'test-over)
            (let ([win (apply open-window "T" 'size '(300 . 200)
                              'pos '(100 . 100) 'ui ui
                              'draw (lambda (win w h)
                                      (ui-begin! ui)
                                      (ui-table ui 't 0 0 w h '((a "A" 100))
                                                '(1 2 3) 2 void
                                                (lambda (row k x y w h flags)
                                                  (set! seen (cons row seen))))
                                      (ui-end! ui w h))
                              (ui-handlers ui))])
              (steps 2)
              (close-window! win)
              (steps 1)
              (let loop ([s (reverse seen)] [prev #f] [overs 0])
                (cond [(null? s) (> overs 0)]
                      [(eq? (car s) 'over)
                       (and (eqv? prev 2) (loop (cdr s) 'over (+ overs 1)))]
                      [else (loop (cdr s) (car s) overs)])))))))

(check "a string among a column's flags is its heading's tooltip, sorted \
        or not, and never one of its cells' flags"
       (let* ([ui (make-ui)] [flags '()]
              [table (lambda (on-sort)
                       (lambda (win w h)
                         (ui-begin! ui)
                         (apply ui-table ui 't 0 0 w h
                                '((a "A" 100 right "What A means") (b "B" 100))
                                '(1 2) #f void
                                (lambda (row k x y w h fl)
                                  (set! flags (append fl flags)))
                                (if on-sort (list 'on-sort on-sort) '()))
                         (ui-end! ui w h)))]
              [tip-of (lambda (key)
                        (let ([r (ui-find ui (list 't 'header key))])
                          (and r (ui-region-tip r))))]
              [win (apply open-window "T" 'size '(300 . 200) 'pos '(100 . 100)
                          'ui ui 'draw (table #f) (ui-handlers ui))])
         (steps 2)
         (let ([plain (list (tip-of 'a) (tip-of 'b))])
           (window-on! win 'draw (table void))
           (invalidate! win)
           (steps 2)
           (let ([sorted (list (tip-of 'a) (tip-of 'b))])
             (close-window! win)
             (steps 1)
             (printf "  ~s ~s\n" plain sorted)
             (and (equal? plain '("What A means" #f))
                  (equal? sorted '("What A means" #f))
                  (memq 'right flags)
                  (not (exists string? flags)))))))

(check "Tasks' marks and avatars are a style's: Genera leaves out a status's \
        mark (its word is beside it) and an avatar beside the name, else \
        the initials in a lozenge"
       (let ([mark (lambda (style)
                     (with-style style
                       (lambda ()
                         (let* ([w #f]
                                [img (image 20 20 1
                                            (lambda ()
                                              (set! w (tasks-draw-mark
                                                       2 2 14 'status
                                                       'todo))))])
                           (cairo-surface-destroy img)
                           w))))]
             [size (lambda (style flags)
                     (with-style style
                       (lambda ()
                         (call-with-values
                           (lambda () (ui-avatar-size flags "Pavel Uvarov"))
                           list))))])
         (and (= (mark 'mac) 14) (= (mark 'genera) 0)
              (equal? (size 'genera '()) '(21 9))
              (equal? (size 'genera '(named)) '(0 0))
              (equal? (size 'mac '(named)) (size 'mac '())))))

(check "Genera's caret is a block in reverse video and its selection an \
        underline (text-caret, text-selection)"
       (let ([probe   ; ink at x on any of the rows ys
              (lambda (style text at x ys)
                (set-style! style)
                (let-values ([(win ui) (field-window text)])
                  (focus-window! win)
                  (ui-focus! ui 'f at)
                  (invalidate! win)
                  (steps 2)
                  (let-values ([(cx cy cw ch) (content-rect win)])
                    (let ([ink? (exists (lambda (y)
                                          (= (canvas-pixel (+ cx x) (+ cy y))
                                             (color->pixel 'text)))
                                        ys)])
                      (close-window! win)
                      (steps 1)
                      ink?))))])
         ;; the block over the field's middle; the underline below the
         ;; text's baseline, wherever the font's size puts it
         (let ([r (list (probe 'genera "" 0 25 '(30))
                        (probe 'mac "" 0 25 '(30))
                        (probe 'genera "MMMM" #t 26 '(35 36 37 38 39 40)))])
           (set-style! 'mac)
           (equal? r '(#t #f #t)))))

(check "a style may center its menus' entries (menu-align, the Lisp \
        machines'), and a section label keep its case and take its font"
       (let ([first-ink
              (lambda (style)
                (set-style! style)
                (open-menu! 200 200 (list (cons "a much wider entry" void)
                                          (cons "ii" void)))
                (steps 2)
                (let* ([a (cdr (assv 1 (placed-menu-areas *menu*)))]
                       [x (car a)] [y (cadr a)] [w (caddr a)] [h (cadddr a)]
                       [bg (canvas-pixel (+ x w -6) (+ y (quotient h 2)))]
                       [at (let loop ([i 12])   ; clear of a round corner
                             (cond [(>= i (- w 12)) #f]
                                   [(exists (lambda (dy)
                                              (not (= bg (canvas-pixel
                                                          (+ x i) (+ y dy)))))
                                            (iota (exact (- h 4))))
                                    (/ i w)]
                                   [else (loop (+ i 1))]))])
                  (close-menu!)
                  (steps 1)
                  at))])
         (let ([r (list (first-ink 'genera) (first-ink 'mac))])
           (set-style! 'mac)
           (and (> (car r) 1/3) (< (cadr r) 1/3)
                (with-style 'genera
                  (lambda ()
                    (and (equal? (ui-label-text '(section) "Checklist")
                                 "Checklist")
                         (eq? (ui-label-font '(section)) 'ui-bold-italic))))
                (equal? (ui-label-text '(section) "Checklist")
                        "CHECKLIST")))))

(check "a dropdown showing its 'label, not a choice, says so (flag label), \
        so Genera sets a value in bold and a label plain"
       (with-test-styles
        (lambda ()
          (let ([seen '()] [ui (make-ui)])
            (define-style test-dd "Test"
              'ui-draw-dropdown
              (lambda (x y w h flags label)
                (set! seen (cons (cons label (and (memq 'label flags) #t))
                                 seen))))
            (set-style! 'test-dd)
            (let ([win (apply open-window "D" 'size '(300 . 100)
                              'pos '(100 . 100) 'ui ui
                              'draw (lambda (win w h)
                                      (ui-begin! ui)
                                      (ui-dropdown ui 'a 10 10 100 24
                                                   '(("One" . 1)) 1 void)
                                      (ui-dropdown ui 'b 10 40 100 24
                                                   '(("One" . 1)) #f void
                                                   'label "Kind")
                                      (ui-end! ui w h))
                              (ui-handlers ui))])
              (steps 2)
              (close-window! win)
              (steps 1)
              (and (equal? (assoc "One" seen) '("One" . #f))
                   (equal? (assoc "Kind" seen) '("Kind" . #t))))))))

;; Pixels of an image drawn by thunk in Genera, scale s, extra settings
;; over it: ((x y) ...) read in device pixels.
(define (genera-pixels pw ph s at thunk . extra)
  (apply with-style 'genera
         (lambda ()
           (let* ([img (image pw ph s thunk)]
                  [ps (map (lambda (p) (apply pixel-at img p)) at)])
             (cairo-surface-destroy img)
             ps))
         extra))

(check "px-invert swaps ink and paper in any palette (Genera in Nord, \
        Paper), and black on white as XOR did"
       (for-all
        (lambda (palette)
          (with-style 'genera
            (lambda ()
              (equal? (genera-pixels 20 10 1 '((5 5) (15 5))
                                     (lambda ()
                                       (fill-rect 0 0 20 10 'window-bg)
                                       (fill-rect 10 0 10 10 'text)
                                       (px-invert 0 0 20 10))
                                     'palette palette)
                      (list (color->pixel 'text) (color->pixel 'window-bg))))
            'palette palette))
        '(nord paper genera)))

(check "a block caret is as wide as the character under it, the font's \
        width past the end"
       (and (= (ui-caret-block-width "iM" 0 'ui) (text-width "i" 'ui))
            (= (ui-caret-block-width "iM" 1 'ui) (text-width "M" 'ui))
            (= (ui-caret-block-width "iM" 2 'ui) (font-char-width 'ui))
            (< (text-width "i" 'ui) (text-width "M" 'ui))))

(check "a scroll view clips on whole device pixels: at 150 % what it cuts \
        ends in ink or paper"
       (let* ([img (image 30 30 1.5
                          (lambda ()
                            (fill-rect 0 0 20 20 #xffffff)
                            (ui-call-with-pixel-clip 1.3 1.3 10.4 10.4
                                             (lambda ()
                                               (fill-rect 0 0 20 20
                                                          #x000000)))))]
              [ps (map (lambda (i) (pixel-at img i i)) (iota 20))])
         (cairo-surface-destroy img)
         (for-all (lambda (p) (memv p '(#xff000000 #xffffffff))) ps)))

(check "Genera's square things at 150 % on whole device pixels: a Tasks \
        card's paper, Settings' font sample's box"
       (begin
         (tasks-reset!)
         (let ([crisp? (lambda (ps)
                         (for-all (lambda (p) (memv p '(#xff000000
                                                        #xffffffff)))
                                  ps))]
               [row (map (lambda (x) (list x 30)) (iota 8))])
           (and (crisp? (genera-pixels 60 60 1.5 row
                                       (lambda ()
                                         (fill-rect 0 0 40 40 'text)
                                         (tasks-draw-card 1.3 1.3 30 30 '()
                                                          (car *tasks*)
                                                          '(2026 10 31)))))
                (crisp? (genera-pixels 60 60 1.5 row
                                       (lambda ()
                                         (fill-rect 0 0 40 40 'text)
                                         (settings-draw-font-sample
                                          1.3 1.3 30))))))))

(check "Genera inverts Settings' chosen tab, its mark inside it in ink, and \
        its chosen color row"
       (let ([ink #xff000000])
         (and (equal? (genera-pixels 100 24 1 '((2 12) (90 3))
                                     (lambda ()
                                       (fill-rect 0 0 100 24 #xffffff)
                                       (ui-draw-nav-row 0 0 100 24
                                                        '(selected)
                                                        "Theme" #f)))
                      (list ink ink))
              (equal? (genera-pixels 200 28 1 '((150 4))
                                     (lambda ()
                                       (fill-rect 0 0 200 28 #xffffff)
                                       (settings-draw-color-row
                                        0 0 200 28 'red '(selected))))
                      (list ink)))))

(check "Genera's field underline shows in a half-size miniature, and a \
        menu filter's caret is its block"
       (let ([ink #xff000000])
         (and (exists (lambda (p) (= p ink))
                      (genera-pixels 20 10 1/2
                                     (map (lambda (x) (list x 9)) (iota 20))
                                     (lambda ()
                                       (fill-rect 0 0 40 20 #xffffff)
                                       (ui-draw-field 0 0 40 20 '()))))
              (with-style 'genera
                (lambda ()
                  (let ([x (+ 10 (text-width "ab" (theme 'menu-font)) 2)])
                    (equal? (genera-pixels
                             100 30 1 (list (list (exact (floor x)) 15))
                             (lambda ()
                               (draw-menu-filter (make-menu 0 0 '() 0 "ab" #t
                                                            #f)
                                                 0 0 100 30)))
                            (list ink))))))))

(check "the calendar's steps are the words Previous and Next under Genera \
        (calendar-step-words), glyphs elsewhere"
       (let ([doc
              (lambda (style)
                (set-style! style)
                (let* ([ui (make-ui)]
                       [win (apply open-window "C" 'size '(400 . 400)
                                   'pos '(100 . 100) 'ui ui
                                   'draw (lambda (win w h)
                                           (ui-begin! ui)
                                           (ui-date-field ui 'd 10 10 150 24
                                                          '(2026 11 2) void)
                                           (ui-end! ui w h))
                                   (ui-handlers ui))])
                  (steps 2)
                  (ui-state-popup-set! ui (cons 'd (ui-date->day
                                                    '(2026 11 2))))
                  (invalidate! win)
                  (steps 2)
                  (let ([r (ui-find ui '(d prev))])
                    (close-window! win)
                    (steps 1)
                    (and r (ui-region-doc r)))))])
         (let ([r (list (doc 'genera) (doc 'mac))])
           (set-style! 'mac)
           (equal? r '(((L . "Previous")) ((L . "Press")))))))

(check "a board column's ring shows under the card it cuts off (Genera: \
        the cards' view stops short of its well's ring, surface-well-ring)"
       (begin
         (set-style! 'genera)
         (tasks-reset!)
         (let* ([win (tasks)] [ui (window-ref win 'ui)])
           (focus-window! win)
           (steps 3)
           (let*-values ([(cx cy cw ch) (content-rect win)]
                         [(f) (ui-region-frame (ui-find ui '(column todo)))]
                         ;; the well's last row: the board's, a pad up
                         [(ps) (map (lambda (dx)
                                      (canvas-pixel (+ cx (car f) dx)
                                                    (+ cy ch (- (ui-pad)) -1)))
                                    '(40 60 80))]
                         [(ink) (color->pixel 'text)])
             (close-window! win)
             (steps 1)
             (set-style! 'mac)
             (for-all (lambda (p) (= p ink)) ps)))))

(check "Settings' chosen color row shows its swatch in its own color over \
        Genera's inverse video, its ring a stipple of ink and paper"
       (with-style 'genera
         (lambda ()
           (equal? (genera-pixels 200 28 1 '((20 14) (12 6) (13 6))
                                  (lambda ()
                                    (fill-rect 0 0 200 28 #xffffff)
                                    (settings-draw-color-row
                                     0 0 200 28 'accent '(selected))))
                   (list (color->pixel 'accent) #xff000000 #xffffffff)))))

(check "Genera's who line: no top bar; what the mouse does reversed across \
        its top line, in Genera's words; its fields at character columns; \
        its windows field lists them, and one chosen is selected"
       (let ([a (open-window "Alpha" 'size '(300 . 160) 'pos '(200 . 200))]
             [b (open-window "Beta" 'size '(300 . 160) 'pos '(600 . 200))])
         (set-style! 'genera)
         (inject! '(mouse-move 900 600))
         (steps 2)
         (let* ([lh (genera-line)] [top (- (screen-h) (* 2 lh))]
                [areas (with-place 'bar taskbar-areas)]
                [cw (font-char-width 'mono)]
                [row (lambda () (map (lambda (x) (canvas-pixel x (+ top 8)))
                                     (iota 300)))]
                [desk (row)]
                [sizes (list (topbar-height) (taskbar-height) (* 2 lh))]
                [cols (map (lambda (a) (/ (cadr a) cw)) (cdr areas))]
                [colors (list (canvas-pixel 2 (+ top 1))
                              (canvas-pixel 2 (+ top lh 1))
                              (canvas-pixel 640 2))]
                [ink+paper (list (color->pixel 'text) (color->pixel 'bg-1)
                                 (color->pixel 'desktop-top))])
           (inject! `(mouse-move ,(+ (window-x a) 100)
                                 ,(+ (window-y a) (window-h a) -8)))
           (steps 2)
           (let ([over (row)] [doc (mouse-doc)]
                 [f (cdr (assq 'windows areas))])
             (inject! `(mouse-move ,(+ (car f) 4) ,(+ (cadr f) 4))
                      `(mouse-down ,(+ (car f) 4) ,(+ (cadr f) 4) left 1)
                      `(mouse-up ,(+ (car f) 4) ,(+ (cadr f) 4) left))
             (steps 1)
             (let ([listed (and (menu-open?)
                                (map car (menu-items *menu*)))])
               (when (menu-open?)
                 ((cdr (assoc "Alpha" (menu-items *menu*))))
                 (close-menu!))
               (let ([chosen (eq? *focus* a)])
                 (set-style! 'mac)
                 (close-window! a)
                 (close-window! b)
                 (steps 2)
                 (and (= (car sizes) 0) (= (cadr sizes) (caddr sizes))
                      (for-all integer? cols)
                      (equal? colors ink+paper)
                      (not (equal? desk over))
                      (equal? (genera-mouse-doc-text doc)
                              "Mouse-L: Move; Mouse-R: Window menu.")
                      (member "Alpha" listed) (member "Beta" listed)
                      chosen)))))))

(check "Interlisp's title shade fills its strip's title rows after the \
        title, the border's ink above and below"
       (let ([w (open-window "T" 'size '(300 . 160) 'pos '(200 . 200)
                             'window-style 'interlisp)])
         (steps 2)
         (let* ([x (+ (window-x w) 200)] [y (window-y w)]
                [px (lambda () (map (lambda (dy) (canvas-pixel x (+ y dy)))
                                    '(0 5 14)))]
                [ink (px)])
           (override! 'interlisp-title-shade #xffffff)
           (steps 2)
           (let ([shaded (px)])
             (override! 'interlisp-title-shade)
             (close-window! w)
             (steps 1)
             (let ([i #xff000000] [p #xffffffff])
               (and (equal? ink (list i i i))
                    (equal? shaded (list i p i))))))))

(check "Interlisp's desktop is Medley's #x8822: dashes two pixels tall, \
        moved two columns every two rows"
       (let* ([img (image 4 4 1 (lambda ()
                                  (fill-wallpaper 0 0 4 4 'shade #xffffff
                                                  #x000000)))]
              [rows (map (lambda (y)
                           (list->string
                            (map (lambda (x)
                                   (if (= (pixel-at img x y) #xff000000)
                                       #\# #\.))
                                 (iota 4))))
                         (iota 4))])
         (cairo-surface-destroy img)
         (equal? rows '("#..." "#..." "..#." "..#."))))

(check "Interlisp's scroll bars beside the window: with the side Outside \
        its frame leaves Medley's 24 pixels at the left, and the bar shows \
        there under the pointer"
       (begin
         (override! 'scrollbar-side 'outside)
         (let ([w (scroll-window "Medley" 'window-style 'interlisp)])
           (steps 2)
           (let-values ([(l t r b) (frame-insets w)])
             (let ([mx (+ (window-x w) 12)] [my (+ (window-y w) 100)])
               (inject! `(mouse-move ,mx ,my))
               (steps 2)
               (let ([bar (window-ref w 'scrollbar #f)]
                     [region (window-region w mx my)])
                 (override! 'scrollbar-side)
                 (close-window! w)
                 (steps 1)
                 ;; from the title strip's bottom (15) to the frame's
                 (and (= l 28) (eq? region 'scrollbar) bar
                      (= (car bar) -28) (= (caddr bar) 24)
                      (= (cadr bar) (- 15 t))
                      (= (cadddr bar) (- (window-h w) 15)))))))))

(check "the REPL's scroll bar is on the style's side, and no wider than \
        its text's inset there (Interlisp's 24)"
       (let* ([r (repl)] [rs (window-ref r 'state)])
         (override! 'scrollbar-width 24)
         (do ([i 0 (+ i 1)]) ((= i 80)) (repl-add! rs 'output "a line"))
         (repl-scroll-set! rs 20)
         (invalidate!)
         (steps 2)
         (let-values ([(cx cy cw ch) (content-rect r)])
           (let* ([column (lambda (x)
                            (map (lambda (i) (canvas-pixel x (+ cy i)))
                                 (iota ch)))]
                  [right (list (column (+ cx 5)) (column (+ cx cw -5))
                               (column (+ cx 15)))])
             (override! 'scrollbar-side 'left)
             (invalidate!)
             (steps 2)
             (let ([left (list (column (+ cx 5)) (column (+ cx cw -5))
                               (column (+ cx 15)))])
               (override! 'scrollbar-side)
               (override! 'scrollbar-width)
               (close-window! r)
               (steps 1)
               (and (not (equal? (car right) (car left)))
                    (not (equal? (cadr right) (cadr left)))
                    (equal? (caddr right) (caddr left))))))))

(check "Mac draws no resize grip on a shaded window"
       (let ([w (open-window "Grip" 'size '(300 . 200) 'pos '(200 . 200)
                             'window-style 'mac)]
             [n 0])
         (steps 2)
         (let ([count (lambda ()
                        (set! n 0)
                        (fluid-let ([draw-resize-grip
                                     (lambda (x y) (set! n (+ n 1)))])
                          (render-full-into! *canvas*))
                        n)])
           (let* ([open (count)] [shaded (begin (shade-window! w) (count))])
             (close-window! w)
             (steps 1)
             (= shaded (- open 1))))))

(check "a baseline lands on a whole device row in a half-size miniature, \
        and moved half a device pixel"
       (let ([rows '()])
         (cairo-surface-destroy
          (image 10 10 1
                 (lambda ()
                   (cairo-scale *cr* 0.5 0.5)
                   (set! rows (list (* 0.5 (px-baseline 10.6 round))))
                   (cairo-translate *cr* 0 1)
                   (set! rows (cons (+ 0.5 (* 0.5 (px-baseline 10.6 round)))
                                    rows)))))
         (for-all integer? rows)))

(check "a stipple's tile is made once for its rows, colors and scale"
       (let* ([gray (stipple 'text #f "#..." "...." "...." "....")]
              [paint (lambda (s)
                       (cairo-surface-destroy
                        (image 24 24 s (lambda () (fill-rect 0 0 16 16 gray)
                                         (fill-rect 0 0 8 8 gray)))))])
         (vector-for-each free-owned-surface!
                          (hashtable-values *stipple-tiles*))
         (hashtable-clear! *stipple-tiles*)
         (paint 1)
         (let ([one (hashtable-size *stipple-tiles*)])
           (paint 1)
           (paint 1.5)
           (and (= one 1) (= (hashtable-size *stipple-tiles*) 2)))))

;;; the verifier's findings on steps 8 and 9

;; Runs the timers due within the next second: a save asked for soon.
(define (run-soon-timers!)
  (let ([real now-ms])
    (fluid-let ([now-ms (lambda () (+ (real) 1000))]) (steps 1))))

(check "Reset to defaults is saved, as a change is"
       (let ([saved (lambda ()
                      (cdr (assq 'changes
                                 (call-with-input-file *theme-file-path*
                                   read))))])
         (set-theme! 'corner-radius 3)
         (run-soon-timers!)
         (let ([before (saved)])
           (reset-theme!)
           (run-soon-timers!)
           (and (equal? before '((mac (corner-radius . 3))))
                (null? (saved))))))

(check "a title that reads as a number names a style that reads back as a \
        symbol, and save-style-as! writes any name so"
       (let ([reads-as-symbol?
              (lambda (name)
                (symbol? (read (open-string-input-port (format "~s" name)))))])
         (set! *settings-style-directory*
               (string-append out-dir "/saved-styles"))
         (let* ([names (map settings-style-name '("1984" "2" "-1" "1e3"))]
                [path (save-style-as! (string->symbol "12") "Twelve")]
                [form (call-with-input-file path read)])
           (set-style! 'mac)
           (set! *styles* (remp (lambda (s) (eq? (style-name s) '|12|))
                                *styles*))
           (delete-file path)
           (and (equal? names '(style-1984 style-2 style-1 style-1e3))
                (for-all reads-as-symbol? names)
                (eq? (cadr form) '|12|)))))

(check "the square styles honor every common option but the corner radius"
       (for-all (lambda (st)
                  (let ([fixed (with-style st (lambda () (theme 'fixed)))])
                    (and (equal? fixed '(corner-radius))
                         (not (memq 'title-height fixed)))))
                '(cons curses draft fold interlisp lambda reticle slab)))

;; A rounded rectangle's top-left pixel, drawn in style st: ink where the
;; corner is square, nothing where it is round.
(define (corner-pixel st)
  (pixel-at (image 40 20 1
                   (lambda ()
                     (with-style st
                       (lambda () (fill-round-rect 0 0 40 20 10 #x000000)))))
            0 0))

(check "a style whose corner radius is 0 draws every rounded thing square, \
        an app's too; the rounded styles keep their round corners"
       (and (for-all (lambda (st) (= (corner-pixel st) #xff000000))
                     '(cons curses draft fold genera cadr interlisp lambda
                       reticle slab))
            (for-all (lambda (st) (zero? (corner-pixel st)))
                     '(mac windows spine halo))))

(check "the CADR's label strip lies under the content, its margin and \
        border under it; Genera's directly inside the border"
       (let ([strip-y (lambda (st)
                        (let ([w (open-window "Label" 'size '(300 . 150)
                                              'window-style st)])
                          (let-values ([(l t r b) (frame-insets w)])
                            (let ([y (caddr (assq 'title (frame-regions w)))]
                                  [h (window-h w)])
                              (close-window! w)
                              (list y (- h b) (- h 2 (- b 6)))))))])
         (let ([c (strip-y 'cadr)] [g (strip-y 'genera)])
           (and (= (car c) (cadr c)) (= (car g) (caddr g))))))

(check "an Override of another style's own option says whose it is and \
        that it does not apply here; in that style it does"
       (begin
         (override! 'genera-margin 3)
         (let ([label (settings-key-label 'genera-margin)]
               [here (settings-override-words 'genera-margin)])
           (set-style! 'genera)
           (let ([there (settings-override-words 'genera-margin)])
             (set-style! 'mac)
             (override! 'genera-margin)
             (and (equal? label "White margin (Genera)")
                  (equal? here "3 px; does not apply here")
                  (equal? there "3 px"))))))

(check "a pinned row reads Override; unpinned with the style's own value, \
        it leaves no change"
       (let ([o (assq 'corner-radius common-options)])
         (settings-pin! 'corner-radius #t)
         (let ([pinned (settings-row-label o)])
           (settings-pin! 'corner-radius #f)
           (and (equal? pinned "Corner radius · Override")
                (equal? (settings-row-label o) "Corner radius")
                (null? (style-changes-of 'mac))
                (null? (theme-overrides))))))

(check "a style's colors that are not options are saved and load back"
       (begin
         (set-style! 'interlisp)
         (set-theme! 'interlisp-title-shade #x808080)
         (set-theme! 'interlisp-scroll-shade #x404040)
         (theme-file-save!)
         (reset-theme!)
         (theme-file-load!)
         (let ([got (list (theme 'interlisp-title-shade)
                          (theme 'interlisp-scroll-shade))])
           (reset-theme!)
           (set-style! 'mac)
           (and (equal? got '(#x808080 #x404040))
                (theme-file-valid-value? 'genera-gray #x333333)))))

(check "the stipple tiles cached are at most 64"
       (begin
         (cairo-surface-destroy
          (image 8 8 1 (lambda ()
                         (do ([i 0 (+ i 1)]) ((= i 70))
                           (fill-rect 0 0 8 8 (stipple (* i 1000) #f "#."
                                                       ".#"))))))
         (<= (hashtable-size *stipple-tiles*) 64)))

(check "the who line counts one window, not one windows"
       (let ([w (open-window "Only" 'size '(200 . 100))] [texts '()])
         (set-style! 'genera)
         (steps 1)
         (let ([real draw-text])
           (fluid-let ([*windows* (list w)]
                       [draw-text (lambda (x y s . rest)
                                    (set! texts (cons s texts))
                                    (apply real x y s rest))])
             (render-full-into! *canvas*)))
         (set-style! 'mac)
         (close-window! w)
         (steps 1)
         (and (member "1 window" texts) #t)))

(check "Settings' pane scroll bar is on the style's side, and shown on \
        hover only where the style says so, and not once the pointer has \
        left the window"
       (let ([s (settings)])
         (move-window! s 60 40)
         (focus-window! s)
         (steps 2)
         (let* ([ui (window-ref s 'ui)]
                [bar-x (lambda ()
                         (invalidate! s)
                         (steps 2)
                         (let ([r (ui-find ui 'pane-scrollbar)])
                           (and r (ui-region-x r))))]
                [sw (settings-sidebar-width)])
           (let-values ([(cx cy cw ch) (content-rect s)])
             (inject! `(mouse-move ,(+ cx 40) ,(+ cy 200)))   ; the sidebar
             (let ([right (bar-x)])
               (override! 'scrollbar-side 'left)
               (let ([left (bar-x)])
                 (override! 'scrollbar-show 'hover)
                 (let ([away (bar-x)])
                   (inject! `(mouse-move ,(+ cx sw 100) ,(+ cy 200)))
                   (let* ([over (bar-x)]
                          [gone (begin
                                  (inject! `(mouse-move ,(+ cx cw 30)
                                                        ,(+ cy 200)))
                                  (bar-x))])
                     (override! 'scrollbar-show)
                     (override! 'scrollbar-side)
                     (close-window! s)
                     (steps 1)
                     (and right (> right sw) (eqv? left (+ sw 1))
                          (not away) (eqv? over (+ sw 1)) (not gone))))))))))

(check "a change the style passes by is said, with its ↺"
       (let ([s (settings)] [texts '()])
         (set-style! 'curses)
         (set-theme! 'corner-radius 4)
         (steps 2)
         (let ([real draw-text])
           (fluid-let ([draw-text (lambda (x y str . rest)
                                    (set! texts (cons str texts))
                                    (apply real x y str rest))])
             (invalidate! s)
             (steps 1)))
         (let ([revert (and (ui-find (window-ref s 'ui) '(revert corner-radius))
                            #t)])
           (reset-style!)
           (set-style! 'mac)
           (close-window! s)
           (steps 1)
           (and revert
                (exists (lambda (t)
                          (string-contains-ci?
                           t "Curses sets this: 0 px; your change (4 px)"))
                        texts)))))

(check "Genera's and the CADR's frames lie on whole device pixels at 125, \
        150 and 175 %: their bottom rows are ink or paper, never between"
       (for-all
        (lambda (st)
          (for-all
           (lambda (k)
             (with-style st
               (lambda ()
                 (let* ([w (detached-window "Crisp" 'size '(200 . 100)
                                            'window-style st)]
                        [ww (window-w w)] [wh (window-h w)]
                        [img (image (exact (ceiling (* k (+ ww 4))))
                                    (exact (ceiling (* k (+ wh 4)))) k
                                    (lambda ()
                                      (genera-draw-under w 1 1 ww wh #t #f
                                                         #f)))]
                        [ink (color->pixel 'text)]
                        [paper (color->pixel (window-bg w))]
                        [x (exact (floor (* k (+ 1 (/ ww 2)))))]
                        [bottom (exact (floor (* k (+ 1 wh))))]
                        [rows (map (lambda (i)
                                     (pixel-at img x (- bottom i 1)))
                                   (iota 6))])
                   (cairo-surface-destroy img)
                   (for-all (lambda (p) (or (= p ink) (= p paper)))
                            rows)))))
           '(1.25 1.5 1.75)))
        '(genera cadr)))

;;; Cons, the idea through everything: the parts and flags it reaches
;;; the widgets by, and its look at a few pixels.

(check "Tasks' column and card insets, its column and the link after each \
        card are parts: a style's own insets move the cards, its link is \
        called after each card with the gap and whether it is the last, \
        and its column draws the empty one"
       (with-test-styles
        (lambda ()
          (let ([links '()] [columns '()])
            (define-style test-chain "Test"
              'tasks-column-insets (lambda () (values 10 8 21 6))
              'tasks-card-insets (lambda () (values 12 30))
              'tasks-draw-link
              (lambda (x y w h flags gap last?)
                (set! links (cons (list w gap last?) links)))
              'tasks-draw-column
              (lambda (x y w h flags status label count)
                (set! columns (cons (list status (and (memq 'empty flags) #t))
                                    columns))
                (tasks-draw-column* x y w h flags status label count)))
            (set-style! 'test-chain)
            (tasks-reset!)
            (let* ([win (tasks)] [ui (window-ref win 'ui)])
              (focus-window! win)
              (steps 3)
              (let* ([col (ui-region-frame (ui-find ui '(column todo)))]
                     [img (image 200 100 1
                                 (lambda ()
                                   (tasks-draw-column 0 0 200 100 '(empty)
                                                      'todo "To do" 0)))]
                     [r (list (pair? (filter caddr links))
                              (for-all (lambda (l)
                                         (and (= (cadr l) 21)
                                              (= (car l) (- (caddr col) 42))))
                                       links)
                              (assq 'todo columns)
                              (assq 'done columns))])
                (cairo-surface-destroy img)
                (close-window! win)
                (steps 1)
                (equal? r (list #t #t '(todo #t) '(done #f)))))))))

(check "the kit flags the last tab and the last chip, a chip input's box \
        (chips), and makes a dialog's dismiss area, where a style's areas \
        have one, pressable: its dialog gets the labels and that area's \
        state"
       (with-test-styles
        (lambda ()
          (let ([tabs '()] [chips '()] [boxes '()] [dialog '()] [dismissed 0]
                [ui (make-ui)])
            (define-style test-last "Test"
              'ui-draw-tab
              (lambda (x y w h flags label)
                (set! tabs (cons (cons label (and (memq 'last flags) #t))
                                 tabs)))
              'ui-draw-chip
              (lambda (x y w h flags label)
                (set! chips (cons (cons label (and (memq 'last flags) #t))
                                  chips)))
              'ui-draw-field
              (lambda (x y w h flags)
                (set! boxes (cons (and (memq 'chips flags) #t) boxes)))
              'ui-dialog-areas
              (lambda (x y w h labels)
                (cons (list 'dismiss x y 20 20)
                      (ui-dialog-areas* x y w h labels)))
              'ui-draw-dialog
              (lambda (x y w h flags title message) (set! dialog flags)))
            (set-style! 'test-last)
            (let ([w (apply open-window "Last" 'size '(400 . 300)
                            'pos '(100 . 100) 'ui ui
                            'draw (lambda (win cw ch)
                                    (ui-begin! ui)
                                    (ui-tabs ui 'v 10 10 28
                                             '(("A" . a) ("B" . b) ("C" . c))
                                             'a void)
                                    (ui-chip-input ui 'tags 10 50 300
                                                   '("x" "y") "" void void
                                                   void)
                                    (ui-dialog ui 'd "Title" "Message"
                                               (list (list "OK" void))
                                               (lambda ()
                                                 (set! dismissed
                                                   (+ dismissed 1))))
                                    (ui-end! ui cw ch))
                            (ui-handlers ui))])
              (focus-window! w)
              (steps 2)
              (let*-values ([(cx cy cw ch) (content-rect w)]
                            [(r) (ui-find ui '(d dismiss))]
                            [(x y) (values (+ cx (ui-region-x r) 5)
                                           (+ cy (ui-region-y r) 5))])
                (inject! `(mouse-move ,x ,y))
                (steps 2)
                (let ([hovered (and (memq 'hover dialog) #t)])
                  (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))
                  (steps 2)
                  (let ([r (list (list-head (reverse tabs) 3)
                                 (list-head (reverse chips) 2)
                                 (car boxes) (assq 'labels dialog) hovered
                                 dismissed)])
                    (close-window! w)
                    (steps 1)
                    (equal? r '((("A" . #f) ("B" . #f) ("C" . #t))
                                (("x" . #f) ("y" . #t))
                                #t (labels "OK") #t 1))))))))))

(check "Cons draws a boolean as a cell holding #t or #f, filled with its \
        ink under the mouse; a chain's last cell holds nil, the slash \
        across its cdr; a menu's chosen entry fills with ink"
       (let ([pixels
              (lambda (pw ph thunk . ps)
                (with-style 'cons
                  (lambda ()
                    (let* ([img (image pw ph 1 thunk)]
                           [r (map (lambda (p)
                                     (apply pixel-at img
                                            (map (lambda (v)
                                                   (exact (floor v)))
                                                 p)))
                                   ps)])
                      (cairo-surface-destroy img)
                      r))))]
             [box (lambda (flags)
                    (lambda ()
                      (fill-rect 0 0 120 40 'window-bg)
                      (ui-draw-checkbox 10 5 100 30 flags "On")))]
             [bg (with-style 'cons (lambda () (color->pixel 'window-bg)))]
             [ink (with-style 'cons (lambda () (color->pixel 'cons-ink)))])
         (let*-values ([(b) (with-style 'cons ui-checkbox-box)]
                       [(by) (+ 5 (floor (/ (- 30 b) 2)))]
                       [(tw0 th) (with-style 'cons
                                   (lambda () (ui-tabs-size '("Tree"))))]
                       [(tw) (exact (ceiling tw0))]
                       [(cx) (- tw (* 2 (cons-arrow)))]
                       [(tab) (lambda (flags)
                                (lambda ()
                                  (fill-rect 0 0 tw 28 'window-bg)
                                  (ui-draw-tab 0 0 tw 28 flags "Tree")))])
           (dynamic-wind
             (lambda ()
               (set-style! 'cons)
               (open-menu! 200 200 (list (cons "One" void) (cons "Two" void)))
               (steps 2))
             (lambda ()
               (let* ([as (placed-menu-areas *menu*)] [pad (theme 'menu-pad)]
                      [entry (lambda (i)
                               (let ([a (cdr (assv i as))])
                                 (canvas-pixel (+ (car a) pad 2)
                                               (+ (cadr a) 2))))]
                      [r (list (pixels 120 40 (box '(checked))
                                       (list 10 by) (list 11 (+ by 1)))
                               (pixels 120 40 (box '(checked hover))
                                       (list 11 (+ by 1)))
                               (map (lambda (p) (= p bg))
                                    (append (pixels tw 28 (tab '(last))
                                                    (list (+ cx 3) 17))
                                            (pixels tw 28 (tab '())
                                                    (list (+ cx 3) 17))))
                               (entry 0) (entry 1))])
                 (equal? r (list (list ink bg) (list ink) '(#f #t) ink bg))))
             (lambda ()
               (when (menu-open?) (close-menu!))
               (steps 1)
               (set-style! 'mac))))))

;; A chain's flags: each element but the last says where the next starts.
(check "the kit's chain flags say last, or where the next element starts"
       (and (equal? (ui-chain-flags '((0 0 10 10) (5 20 10 10)) 0)
                    '((next 5 20)))
            (equal? (ui-chain-flags '((0 0 10 10) (5 20 10 10)) 1) '(last))))

(check "Cons keeps a removable chip a pair, its × in the car with no line \
        before it, and under the mouse fills a square behind the × alone, \
        the car's inside otherwise as it was"
       (with-style 'cons
         (lambda ()
           (let*-values ([(w h) (ui-chip-size "tag" #t)]
                         [(w) (exact (ceiling w))] [(h) (exact (ceiling h))]
                         [(cw cut?) (cons-chip-car-width w h #t)]
                         [(bx by bs) (cons-chip-x-box 0 0 cw h)])
             (let* ([bx (exact (floor bx))] [by (exact (floor by))]
                    [at (lambda (flags)
                          (let* ([img (image (+ w 4) (+ h 4) 1
                                             (lambda ()
                                               (fill-rect 0 0 (+ w 4) (+ h 4)
                                                          'window-bg)
                                               (ui-draw-chip 0 0 w h flags
                                                             "tag")))]
                                 [ps (list (pixel-at img 2 2)
                                           (pixel-at img (+ bx 1) (+ by 1))
                                           (pixel-at img (- bx 1)
                                                     (quotient h 2)))])
                            (cairo-surface-destroy img)
                            ps))]
                    [bg (color->pixel 'window-bg)]
                    [rest (at '(removable last))]
                    [hot (at '(removable hover last))])
               (and (= (car rest) (car hot) bg)
                    (= (cadr rest) bg)
                    (= (cadr hot) (color->pixel 'button-close))
                    ;; no divider just before the ×, at rest or hovered
                    (= (caddr rest) (caddr hot) bg)))))))

(check "Cons's spacing on Tasks' board: the + g inside its column's corner, \
        the scroll bar's thumb g from the cards' cdr cells and from the \
        well's edge, its top level with the first card's"
       (begin
         (set-style! 'cons)
         (tasks-reset!)
         (let* ([win (tasks)] [ui (window-ref win 'ui)])
           (focus-window! win)
           (steps 3)
           (let* ([g (with-style 'cons cons-space)]
                  [c (with-style 'cons cons-cell)]
                  [f (lambda (id) (ui-region-frame (ui-find ui id)))]
                  [col (f '(column todo))]
                  [add (f '(add todo))]
                  [bar (f '((column todo) bar))]
                  [card (f '(card 16))]
                  [right (+ (car col) (caddr col))]
                  [thumb (cdr (assq 'thumb
                                    (with-style 'cons
                                      (lambda ()
                                        (apply ui-scrollbar-areas
                                               (append bar '(0 1/2)))))))]
                  [r (list (- right (+ (car add) (caddr add)))
                           (- (cadr add) (- (cadr col)
                                            (with-style 'cons
                                              tasks-column-header-height)))
                           (- (car thumb) (+ (car card) (caddr card) c))
                           (- right (+ (car thumb) (caddr thumb)))
                           (- (cadr thumb) (cadr card)))])
             (close-window! win)
             (steps 1)
             (set-style! 'mac)
             (for-all = r (list g g g g 0))))))

(check "Cons's dialog is a chain: its dismiss area is the last button's \
        cdr, a cell beside it, and below the message only the pad"
       (with-style 'cons
         (lambda ()
           (let* ([as (ui-dialog-areas 0 0 400 200 '("Cancel" "Delete"))]
                  [d (cdr (assq 'dismiss as))]
                  [bs (map cdr (filter (lambda (a) (eq? (car a) 'button)) as))]
                  [b (car (last-pair bs))]
                  [m (cdr (assq 'message as))])
             (and (= (car d) (+ (car b) (caddr b)))
                  (= (cadr d) (cadr b))
                  (= (caddr d) (cons-cell))
                  (= (+ (cadr m) (cadddr m)) (- 200 (* 2 (cons-space)))))))))

(check "a mouse press on a style card takes the keyboard from where it was"
       (let ([s (settings)])
         (move-window! s 60 40)
         (focus-window! s)
         (steps 2)
         (let* ([ui (window-ref s 'ui)]
                [r (ui-find ui (list 'style (car (styles))))])
           (ui-focus! ui '(tab colors))
           (let-values ([(cx cy cw ch) (content-rect s)])
             (let ([x (+ cx (ui-region-x r) 20)] [y (+ cy (ui-region-y r) 20)])
               (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                        `(mouse-up ,x ,y left))
               (steps 2)
               (let ([focus (ui-focused ui)])
                 (set-style! 'mac)
                 (close-window! s)
                 (steps 1)
                 (not focus)))))))

;;; ------------------------------------------------------------------
;;; the kit's charts

(for-each close-window! (windows))
(set-style! 'mac)
(steps 2)

;; A window whose draw is (draw ui), between the kit's begin and end.
;; => (values win ui)
(define (chart-test-window draw)
  (let ([ui (make-ui)])
    (values (apply open-window "Charts" 'size '(420 . 240) 'pos '(100 . 100)
                   'draw (lambda (win w h)
                           (ui-begin! ui)
                           (draw ui)
                           (ui-end! ui w h))
                   (ui-handlers ui))
            ui)))

;; Is any pixel of x y w h in win's content not its ground's?
(define (chart-test-inked? win x y w h)
  (let-values ([(cx cy cw ch) (content-rect win)])
    (let ([ground (canvas-pixel (+ cx 2) (+ cy 2))])
      (exists (lambda (i)
                (exists (lambda (j)
                          (not (= (canvas-pixel (+ cx x i) (+ cy y j))
                                  ground)))
                        (iota (exact (ceiling h)))))
              (iota (exact (ceiling w)))))))

;; What a drawing part, replaced by a style, is given: draw's flags and
;; data as the replacement records them, and whether the plain part
;; inked x y w h. => (values inked? given)
(define (chart-test-part key draw x y w h)
  (with-test-styles
   (lambda ()
     (let-values ([(win ui) (chart-test-window draw)])
       (steps 2)
       (let ([inked? (chart-test-inked? win x y w h)] [given #f])
         (define-style test-chart "Test" key
           (lambda args (set! given (list-tail args 4))))
         (set-style! 'test-chart)
         (invalidate! win)
         (steps 2)
         (let ([still? (chart-test-inked? win x y w h)])
           (close-window! win)
           (values (and inked? (not still?)) given)))))))

(check "the bar chart: its plot right of its scale's widest label, its bars \
        whole pixels 1 to 6 wide, the newest at the plot's right; the bar \
        under the pointer it reports and marks, a press calls on-press with \
        its index; its look is the ui-draw-bar-chart part's"
       (let* ([rules '((10 . "10 ms") (20 . "20 ms"))]
              [areas (ui-bar-chart-areas 10 10 300 100 5 rules)]
              [plot (cdr (assq 'plot areas))]
              [bars (map (lambda (i)
                           (cons (list (cons 'chart-1 (+ i 1))
                                       (cons 'chart-2 1))
                                 (and (= i 2) 1)))
                         (iota 5))]
              [hover #f] [pressed #f])
         (let-values ([(win ui) (chart-test-window
                                 (lambda (ui)
                                   (set! hover
                                     (ui-bar-chart ui 'chart 10 10 300 100 bars
                                                   20 rules 0
                                                   (lambda (i)
                                                     (set! pressed i))))))]
                      [(bx bw) (ui-bar-chart-bar areas 5 3)]
                      [(lx lw) (ui-bar-chart-bar areas 5 4)])
           (steps 2)
           (let-values ([(cx cy cw ch) (content-rect win)])
             (let ([x (+ cx bx (/ bw 2))] [y (+ cy 60)])
               (inject! `(mouse-move ,x ,y))
               (steps 2)
               (let ([hovered hover])
                 (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))
                 (steps 2)
                 (close-window! win)
                 (let-values ([(inked? given)
                               (chart-test-part
                                'ui-draw-bar-chart
                                (lambda (ui)
                                  (ui-bar-chart ui 'chart 10 10 300 100 bars 20
                                                rules 0 void))
                                10 10 300 100)])
                   (printf "  ~s\n" (list plot (assq 'bar areas) hovered
                                          pressed given))
                   (and (= (car plot)
                           (exact (ceiling (+ 10 12 (text-widest (map cdr rules)
                                                                 'ui-small)))))
                        (for-all (lambda (v) (and (exact? v) (integer? v)))
                                 plot)
                        (= (cadr (assq 'bar areas)) 6)
                        (= 1 (cadr (assq 'bar (ui-bar-chart-areas
                                               10 10 300 100 1000 rules))))
                        (= (+ lx lw) (+ (car plot) (caddr plot)))
                        (= bw 6) (= (+ bx bw) lx)
                        (eqv? hovered 3) (eqv? pressed 3) inked?
                        (equal? (map caddr (cadr given))
                                '(marked #f #f #f #f))
                        (equal? (map cadr (cadr given)) '(#f #f 1 #f #f))
                        (equal? (cddr given) (list 20 rules))))))))))

(check "the bar chart's tooltip: asked only for the bar under the pointer, \
        by its index, and shown once the pointer rests"
       (let* ([rules '((10 . "10 ms"))]
              [bars (map (lambda (i) (cons (list (cons 'chart-1 5)) #f))
                         (iota 5))]
              [asked '()])
         (let-values ([(win ui) (chart-test-window
                                 (lambda (ui)
                                   (ui-bar-chart ui 'chart 10 10 300 100 bars
                                                 10 rules #f void
                                                 'tip (lambda (i)
                                                        (set! asked
                                                          (cons i asked))
                                                        (format "bar ~a" i)))))]
                      [(bx bw) (ui-bar-chart-bar (ui-bar-chart-areas
                                                  10 10 300 100 5 rules)
                                                 5 1)])
           (steps 2)
           (let ([before asked])
             (let-values ([(cx cy cw ch) (content-rect win)])
               (inject! `(mouse-move ,(+ cx bx (/ bw 2)) ,(+ cy 60)))
               (steps 2)
               (let ([r (ui-find ui '(chart 1))] [o (ui-find ui '(chart 2))])
                 (close-window! win)
                 (and (null? before)
                      (for-all (lambda (i) (= i 1)) asked)
                      (equal? (ui-region-tip r) "bar 1")
                      (not (ui-region-tip o)))))))))

(check "the sparkline: values as a line, in chart-share when its row is \
        selected; its look is the ui-draw-sparkline part's"
       (let-values ([(inked? given)
                     (chart-test-part
                      'ui-draw-sparkline
                      (lambda (ui)
                        (ui-draw-sparkline 10 10 200 30 '(selected)
                                           '(1 3 2 5)))
                      10 10 200 30)])
         (and inked? (equal? given '((selected) (1 3 2 5))))))

(check "the line chart: series over one span, each to its own most, in a \
        well; its look is the ui-draw-line-chart part's"
       (let* ([series '((chart-1 1 2 3) (chart-2 30 10 20))]
              [inked+given
               (call-with-values
                 (lambda ()
                   (chart-test-part
                    'ui-draw-line-chart
                    (lambda (ui)
                      (ui-draw-line-chart 10 10 300 80 '() series))
                    10 10 300 80))
                 list)])
         (and (car inked+given)
              (equal? (cadr inked+given) (list '() series)))))

(check "the legend: a swatch and a label a key, its size its keys' in a \
        row; its look is the ui-draw-legend part's"
       (let*-values ([(keys) '((chart-1 . "events") (chart-2 . "timers"))]
                     [(lw lh) (ui-legend-size keys)]
                     [(inked? given)
                      (chart-test-part
                       'ui-draw-legend
                       (lambda (ui) (ui-draw-legend 10 10 300 lh '() keys))
                       10 10 300 lh)])
         (and inked? (= lh (font-line-height 'ui-small))
              (= lw (+ (ui-legend-key-width "events") 12
                       (ui-legend-key-width "timers")))
              (equal? given (list '() keys)))))

;;; ------------------------------------------------------------------
;;; the profiler (services/profile.ss)

(for-each close-window! (windows))
(steps 2)

;; Busy for ms of the profiler's clock.
(define (profile-test-busy ms)
  (let ([t0 (now-ns)])
    (let loop ()
      (when (< (- (now-ns) t0) (* ms 1000000)) (loop)))))

;; The ticks recorded by thunk, the newest first.
(define (profile-test-ticks thunk)
  (let ([before (profile-ticks)])
    (thunk)
    (let loop ([l (profile-ticks)] [acc '()])
      (if (or (null? l) (memv (car l) before))
          (reverse acc)
          (loop (cdr l) (cons (car l) acc))))))

;; A tick's uses of x: a window's or a process's subject, or a key.
(define (profile-test-uses tick x)
  (filter (lambda (u) (equal? (profile-use-subject u) (profile-subject-of x)))
          (profile-tick-uses tick)))

(define (profile-test-near? a b) (< (abs (- a b)) 1e-6))

;; A tick's phases' ms, all of them.
(define (profile-test-phases tick)
  (map (lambda (p) (profile-tick-phase-ms tick p))
       (vector->list profile-phase-names)))

;; Bytes allocated by thunk, (statistics) aside.
(define (profile-test-bytes thunk)
  (let ([b0 (sstats-bytes (statistics))])
    (thunk)
    (- (sstats-bytes (statistics)) b0)))

(check "profiling is on at boot: the hooks are the profiler's, the collect \
        handler its own, and ticks are kept"
       (and (profile-on?) (pair? *profile-span*)
            (eq? (car *profile-span*) profile-begin!)
            (eq? (collect-request-handler) profile-collect)
            (pair? (profile-ticks))))

(check "off, the hook is #f: no tick is kept, the clock is never read, \
        Chez's own collect handler is back; on again, ticks are kept"
       (let ([reads 0] [clock now-ns] [before (profile-ticks)])
         (profile-on! #f)
         (set! now-ns
           (lambda () (set! reads (+ reads 1)) (clock)))
         (steps 5)
         (set! now-ns clock)
         (let ([off (and (not (profile-on?)) (not *profile-span*)
                         (equal? before (profile-ticks)) (= reads 0)
                         (eq? (collect-request-handler)
                              *profile-plain-collect*))])
           (profile-on! #t)
           (and off (= 3 (length (profile-test-ticks (lambda () (steps 3)))))
                *profile-span*))))

(check "a span allocates nothing, on or off: neither its hook's site nor \
        the profiler's books (a step's: its one guard)"
       (let* ([spans (lambda ()
                       (with-profile-span 'step #f
                         (with-profile-span 'render #f
                           (do ([i 0 (+ i 1)]) ((= i 10000))
                             (with-profile-span (mod i 30) 'draw
                               (with-profile-span 'profile-test-x #f
                                 i))))))]
              [none (profile-test-bytes void)]   ; (statistics)'s own
              [on (begin (spans) (- (profile-test-bytes spans) none))]
              [off (begin (profile-on! #f)
                          (- (profile-test-bytes spans) none))])
         (profile-on! #t)
         (printf "  ~a bytes on, ~a off, for 20,000 spans and a step\n" on off)
         (and (< on 1000) (= off 0))))

(check "spans nest: each keeps its self time, the phases and the uses add \
        up to the step, idle is the step's own"
       (let* ([s (car (profile-test-ticks
                       (lambda ()
                         (with-profile-span 'step #f
                           (profile-test-busy 1)
                           (with-profile-span 'render #f
                             (profile-test-busy 2)
                             (with-profile-span 'profile-test-inner #f
                               (profile-test-busy 3)))))))]
              [use (lambda (k) (profile-use-ms
                                (car (profile-test-uses s k))))])
         (and (< 0.5 (profile-tick-phase-ms s 'input-wait) 1.5)
              (< 1.5 (use 'render) 2.5)
              (< 2.5 (use 'profile-test-inner) 3.5)
              (eq? (profile-use-phase (car (profile-test-uses
                                            s 'profile-test-inner)))
                   'render)
              (profile-test-near?
               (+ (profile-tick-phase-ms s 'render)
                  (profile-tick-phase-ms s 'gc))
               (apply + (map profile-use-ms (profile-tick-uses s))))
              (profile-test-near? (apply + (profile-test-phases s))
                                  (profile-tick-ms s)))))

(let ([life-win (life)])
  (move-window! life-win 600 300)
  (check "every step of the world adds up: its phases to its time, its uses \
          and its input-wait too, no part below 0"
         (let ([ss (profile-test-ticks (lambda () (steps 20)))])
           (close-window! life-win)
           (and (= (length ss) 20)
                (for-all
                 (lambda (s)
                   (let ([uses (profile-tick-uses s)])
                     (and (profile-test-near? (apply + (profile-test-phases s))
                                              (profile-tick-ms s))
                          (profile-test-near?
                           (+ (profile-tick-phase-ms s 'input-wait)
                              (apply + (map profile-use-ms uses)))
                           (profile-tick-ms s))
                          (for-all (lambda (u) (>= (profile-use-ms u) 0))
                                   uses)
                          (for-all (lambda (ms) (>= ms 0))
                                   (profile-test-phases s)))))
                 ss)))))

(let ([slow (open-window "Slow"
              'size '(200 . 100)
              'tick (lambda (win) (invalidate! win))
              'draw (lambda (win w h) (profile-test-busy 3)))]
      [life-win (life)])
  (check "a window whose draw is made slow comes first among Monitor's \
          consumers, its draw the most of its parts"
         (let* ([ss (profile-test-ticks (lambda () (steps 10)))]
                [ts (filter (lambda (t)
                              (monitor-subject? (profile-total-what t)))
                            (profile-totals ss #t))])
           (close-window! slow)
           (close-window! life-win)
           (and (pair? ts)
                (equal? (profile-total-what (car ts))
                        (profile-subject-of slow))
                (equal? (profile-total-what
                         (car (profile-total-parts (car ts))))
                        '(draw . render))
                (= (profile-total-ticks (car ts)) 10)
                (>= (/ (profile-total-ms (car ts)) 10) 3)))))

(let ([p (spawn "profile-test-busy" (lambda () (let loop () (loop))))])
  (check "a busy process shows its share: most of the processes' phase, in \
          one turn a step"
         (let ([ss (profile-test-ticks (lambda () (steps 10)))])
           (kill! p)
           (for-all
            (lambda (s)
              (let ([u (profile-test-uses s p)])
                (and (= (length u) 1)
                     (= (profile-use-calls (car u)) 1)
                     (> (profile-use-ms (car u))
                        (* 0.8 (profile-tick-phase-ms s 'procs))))))
            ss))))

(check "a (collect) shows in the memory numbers, and so does the heap; a \
        collection requested on the main loop is a span of its own, gc"
       (let* ([timer (profile-test-ticks
                      (lambda () (after 0 (lambda () (collect))) (steps 2)))]
              [g0 (collections)]
              [requested
               (car (profile-test-ticks
                     (lambda ()
                       (with-profile-span 'step #f
                         (with-profile-span 'event #f
                           (let loop ([keep '()])
                             (when (= (collections) g0)
                               (loop (cons (make-vector 100)
                                           (if (> (length keep) 50)
                                               '()
                                               keep))))))))))])
         (and (exists (lambda (s) (>= (profile-tick-ref s 'gcs) 1)) timer)
              (for-all (lambda (s) (> (profile-tick-ref s 'heap) 0)) timer)
              (>= (profile-tick-ref requested 'gcs) 1)
              (> (profile-tick-ref requested 'allocated) 0)
              (pair? (profile-test-uses requested 'gc))
              (eq? (profile-use-phase (car (profile-test-uses requested 'gc)))
                   'event)
              (> (profile-tick-phase-ms requested 'gc) 0)
              (> (profile-tick-ref requested 'gc-ms) 0))))

(let* ([w (open-window "Inner"
            'size '(200 . 100)
            'tick (lambda (win)
                    (safely 'profile-test-handler
                            (lambda () (profile-test-busy 1)))))]
       [p (spawn "inner"
                 (lambda ()
                   (let loop ()
                     (safely 'profile-test-process (lambda () (yield)))
                     (loop))))])
  (check "a span inside an engine (a handler, a process) is not timed: its \
          time is its handler's or its process's"
         (let ([ss (profile-test-ticks (lambda () (steps 5)))])
           (close-window! w)
           (kill! p)
           (for-all
            (lambda (s)
              (and (null? (profile-test-uses s 'profile-test-handler))
                   (null? (profile-test-uses s 'profile-test-process))
                   (exists (lambda (u)
                             (and (eq? (profile-use-part u) 'tick)
                                  (>= (profile-use-ms u) 1)))
                           (profile-test-uses s w))
                   (pair? (profile-test-uses s p))))
            ss))))

(check "a span on a thread other than the one profile-on! saw is untimed, \
        and so is one deeper than the stack: no step is lost, nothing \
        overflows"
       (let* ([thread *profile-thread*]
              [others (profile-test-ticks
                       (lambda ()
                         (set! *profile-thread* (+ thread 1))
                         (steps 3)
                         (set! *profile-thread* thread)))]
              [deep (profile-test-ticks
                     (lambda ()
                       (with-profile-span 'step #f
                         (let nest ([n 100])
                           (if (= n 0)
                               (profile-test-busy 1)
                               (with-profile-span 'render #f
                                 (nest (- n 1))))))))])
         (and (null? others) (= (length deep) 1)
              (profile-test-near? (apply + (profile-test-phases (car deep)))
                                  (profile-tick-ms (car deep)))
              (>= (profile-tick-phase-ms (car deep) 'render) 1))))

(check "a raise out of a span, caught in its parent, leaves it open: the \
        ends after it close a span each, the innermost, the step's end the \
        rest, and the step's phases still add up to it"
       (let ([s (car (profile-test-ticks
                      (lambda ()
                        (with-profile-span 'step #f
                          (with-profile-span 'render #f
                            (guard (e [#t 'caught])
                              (with-profile-span 'profile-test-raiser #f
                                (profile-test-busy 2)
                                (raise 'oops)))
                            (with-profile-span 'profile-test-after #f
                              (profile-test-busy 3)))))))]
             [ms (lambda (s k)
                   (apply + (map profile-use-ms (profile-test-uses s k))))])
         (and (profile-test-near? (apply + (profile-test-phases s))
                                  (profile-tick-ms s))
              (< 1.5 (ms s 'profile-test-raiser) 2.5)
              (< 2.5 (ms s 'profile-test-after) 3.5)
              (< (ms s 'render) 0.5)
              (eq? (profile-use-phase
                    (car (profile-test-uses s 'profile-test-after)))
                   'render))))

(check "a collector that raises turns itself off, says so once, and the \
        world goes on drawing"
       (let ([done profile-tick-done!] [errors 0] [report report-error!])
         (set! report-error! (lambda (who c)
                               (set! errors (+ errors 1))
                               (report who c)))
         (set! profile-tick-done! (lambda (now ns) (car '())))
         (steps 3)
         (set! profile-tick-done! done)
         (set! report-error! report)
         (let ([off (not (profile-on?))] [drawn *frames-drawn*])
           (invalidate!)
           (steps 2)
           (profile-on! #t)
           (set! *toasts* '())
           (and off (= errors 1) (> *frames-drawn* drawn)))))

(check "the history keeps no closed window and no ended process alive: \
        each is a subject, its id, and its title or name when first seen"
       (let* ([w (open-window "Kept?" 'size '(200 . 100)
                              'tick (lambda (win) (invalidate! win)))]
              [p (spawn "kept?" (lambda () (let loop () (yield) (loop))))]
              [w-ptr (weak-cons w #f)] [p-ptr (weak-cons p #f)])
         (steps 5)
         (let ([subjects (list (profile-subject-of w) (profile-subject-of p))]
               [ids (list (window-id w) (proc-id p))])
           (close-window! w)
           (kill! p)
           (set! w #f)
           (set! p #f)
           (steps 5)
           (collect (collect-maximum-generation))
           (and (bwp-object? (car w-ptr)) (bwp-object? (car p-ptr))
                (exists (lambda (s)
                          (member (car subjects)
                                  (map profile-use-subject
                                       (profile-tick-uses s))))
                        (profile-ticks))
                (equal? (map car subjects) '(window process))
                (equal? (map cdr subjects) ids)
                (equal? (map profile-subject-name subjects)
                        '("Kept?" "kept?"))))))

(let* ([a (open-window "Twin" 'size '(100 . 60))]
       [b (open-window "Twin" 'size '(100 . 60))]
       [c (open-window "Single" 'size '(100 . 60))]
       [seen (steps 1)]   ; the profiler takes their titles
       [subjects (map profile-subject-of (list a b c))]
       [labels (monitor-labels subjects)])
  (close-window! a)
  (check "two windows of one title get their ids in Monitor's labels, a \
          closed one says so, and a title of its own stays plain"
         (equal? (map cdr labels)
                 (list (format "Twin (window ~a)" (window-id a))
                       (format "Twin (window ~a)" (window-id b))
                       "Single")))
  (check "and once one of them is closed"
         (equal? (map cdr (monitor-labels subjects))
                 (list (format "Twin (window ~a, closed)" (window-id a))
                       (format "Twin (window ~a)" (window-id b))
                       "Single")))
  (for-each close-window! (list b c)))

(check "the history keeps the ticks of the last seconds (at most 100 a \
        second of them) and the seconds of the last minutes asked for \
        (profile-history!), by the clock"
       (let ([clock now-ns] [fake (expt 10 15)])
         (define (run! seconds)   ; 100 ms a step
           (do ([i 0 (+ i 1)]) ((= i (* 10 seconds)))
             (set! fake (+ fake (expt 10 8)))
             (schevana-step! 0)))
         (define (within? seconds)   ; the ticks kept span that, a second more
           (let ([ss (profile-ticks)])
             (and (pair? ss)
                  (> (profile-tick-end (car (last-pair ss)))
                     (- (profile-tick-end (car ss)) (* 1000 (+ seconds 1))))
                  (< (profile-tick-end (car (last-pair ss)))
                     (- (profile-tick-end (car ss)) (* 1000 (- seconds 1)))))))
         (set! now-ns (lambda () fake))
         (profile-clear!)
         (profile-history! 30 1)
         (run! 90)
         (let ([long (and (within? 30) (= (length (profile-seconds)) 60))])
           (profile-history! 5 2)
           (let ([now (within? 5)])
             (run! 150)
             (let ([later (and (within? 5)
                               (= (length (profile-seconds)) 120))])
               (set! now-ns clock)
               ;; back to back, thousands a second: at most 100 a second
               ;; of it
               (profile-history! 2 10)
               (steps 2000)
               (let ([most (= (length (profile-ticks)) 200)])
                 (profile-history! 30 10)
                 (profile-clear!)
                 (and long now later most)))))))

(check "Monitor's Consumers fit their columns to the tree's room: the last \
        (the minute's lines) ends clear of a scroll bar always shown"
       (let* ([m (monitor)] [ui (window-ref m 'ui)])
         (steps 3)
         (let-values ([(cx cy cw ch) (content-rect m)])   ; its Ticks
           (let* ([r (ui-find ui '(tab ticks))]
                  [x (exact (round (+ cx (ui-region-x r)
                                      (/ (ui-region-w r) 2))))]
                  [y (exact (round (+ cy (ui-region-y r)
                                      (/ (ui-region-h r) 2))))])
             (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))))
         (steps 3)
         (let-values ([(cx cy cw ch) (content-rect m)])
           (let* ([r (ui-find ui '(consumers header spark))]
                  [end (and r (+ (ui-region-x r) (ui-region-w r)))]
                  [room (- cw (ui-pad) (ui-scrollbar-inset 'right))])
             (close-window! m)
             (steps 1)
             (printf "  ~s ~s\n" end room)
             (and end (> (ui-scrollbar-inset 'right) 0) (<= end room))))))

;;; Threads, as the core sees them: thread parameters, the main thread's
;;; C, and the main thread's mail.

;; thunk run on a thread of its own; => its value, once the thread is done
(define (on-thread thunk)
  (let* ([out (box #f)] [t (fork-thread (lambda () (set-box! out (thunk))))])
    (thread-join t)
    (unbox out)))

(check "another thread's in-engine?, current-proc, current-app and \
        new-window-position are its own: binding them there leaves the \
        main thread's as they were"
       (let ([inside (box #f)] [go (box #f)])
         (let ([t (fork-thread
                   (lambda ()
                     (parameterize ([in-engine? #t] [current-proc 'worker]
                                    [current-app 'worker]
                                    [new-window-position '(1 . 2)])
                       (set-box! inside #t)
                       (let wait ()
                         (unless (unbox go)
                           (sleep (make-time 'time-duration 1000000 0))
                           (wait))))))])
           (let wait ([n 0])
             (unless (or (unbox inside) (> n 2000))
               (sleep (make-time 'time-duration 1000000 0))
               (wait (+ n 1))))
           (let ([main (list (in-engine?) (current-proc) (current-app)
                             (new-window-position))])
             (set-box! go #t)
             (thread-join t)
             (printf "  main's while the other's were bound: ~s\n" main)
             (and (unbox inside) (equal? main '(#f #f #f #f)))))))

(check "a worklet reaches only its environment: one that names a world \
        procedure, SDL, eval, a primitive, a condition's reader or a world \
        local, or sets a top-level name, is refused when defined; worklets \
        call worklets by name and see them redefined, and a worklet's set! \
        of another is refused"
       (let ([refused
              (map (lambda (form)
                     (guard (c [#t (and (pair? (condition-irritants c))
                                        (car (condition-irritants c)))])
                       (eval form)
                       'defined))
                   '((define-worklet (units-bad x) (draw-text x 0 "" 'text 'ui))
                     (define-worklet (units-bad) (sdl-get-ticks-ns))
                     (define-worklet (units-bad) (eval ''1))
                     (define-worklet (units-bad) (#%$top-level-value 'car))
                     (define-worklet (units-bad c) (condition-irritants c))
                     (let ([y 5]) (worklet (x) (fx+ x y)))
                     (define-worklet (units-bad) (set! units-twice 0))))])
         (eval '(define-worklet (units-twice x) (fx* x 2)))
         (eval '(define-worklet (units-quad x) (units-twice (units-twice x))))
         (let ([before ((eval 'units-quad) 1)])
           (eval '(define-worklet (units-twice x) (fx* x 3)))
           (printf "  refused: ~s\n" refused)
           (and (equal? refused '(draw-text sdl-get-ticks-ns eval
                                  $top-level-value condition-irritants y
                                  units-twice))
                (= before 4) (= ((eval 'units-quad) 1) 9)
                (guard (c [#t (syntax-violation? c)])
                  (eval '(define-worklet (units-bad) (set! units-twice 0)))
                  #f)
                (worklet? (eval 'units-quad)) (not (worklet? car))))))

(define-worklet (units-clock) (now-ns))

(check "a worklet's clock is the world's now-ns, redefined too"
       (let* ([world now-ns]
              [seen (begin (set! now-ns (lambda () 42))
                           (guard (c [#t c]) (units-clock)))])
         (set! now-ns world)
         (and (eqv? seen 42) (fixnum? (units-clock)))))

(check "post-main!: thunks from four threads run at the next step, on the \
        main thread, once each and in each thread's order; one that \
        raises is reported, and the rest still run"
       (let ([seen '()] [reported 0])
         (for-each thread-join
                   (map (lambda (k)
                          (fork-thread
                           (lambda ()
                             (do ([i 0 (+ i 1)]) ((= i 100))
                               (post-main!
                                (lambda ()
                                  (set! seen (cons (list k i (main-thread?))
                                                   seen))))))))
                        '(0 1 2 3)))
         (post-main! (lambda () (error 'mail "posted to fail")))
         (post-main! (lambda () (set! seen (cons '(main 0 #t) seen))))
         (let ([before (length seen)])
           (fluid-let ([report-error! (lambda (who c)
                                        (set! reported (+ reported 1)))])
             (steps 1))
           (let ([seen (reverse seen)])
             (define (of k) (map cadr (filter (lambda (s) (eqv? (car s) k))
                                              seen)))
             (and (= before 0) (= (length seen) 401) (= reported 1)
                  (for-all caddr seen)
                  (for-all (lambda (k) (equal? (of k) (iota 100)))
                           '(0 1 2 3))
                  (equal? (car (last-pair seen)) '(main 0 #t))
                  (begin (steps 1) (= (length seen) 401)))))))

;;; The crew (services/crew.ss).

;; About us µs of work, without allocating; the thread's id noted in ids
;; (a box of a list) the first time.
(define-worklet (crew-test-busy us ids)
  (let ([id (get-thread-id)])
    (let note ()
      (let ([seen (unbox ids)])
        (unless (or (memv id seen) (box-cas! ids seen (cons id seen)))
          (note)))))
  (let ([until (+ (now-ns) (* 1000 us))])
    (let loop () (when (< (now-ns) until) (loop)))))

(define-worklet (crew-test-add! b n)
  (let loop ()
    (let ([v (unbox b)]) (unless (box-cas! b v (+ v n)) (loop)))))

;; Each index of [lo, hi) counted in counts, after us µs.
(define-worklet (crew-test-count lo hi counts us ids)
  (crew-test-busy us ids)
  (do ([i lo (fx+ i 1)]) ((fx= i hi))
    (bytevector-u8-set! counts i (fx+ 1 (bytevector-u8-ref counts i)))))

(define-worklet (crew-test-square x) (* x x))

(check "crew-for calls a worklet on disjoint chunks that cover the range \
        once each, on the caller and the workers; crew-map is map, in \
        order; a procedure that is no worklet is refused"
       (let ([counts (make-bytevector 20000 0)] [ids (box '())])
         (crew-for* 100 0 20000 crew-test-count counts 100 ids)
         (printf "  ~a workers, ~a threads took part\n" (crew-size)
                 (length (unbox ids)))
         (and (> (crew-size) 0)
              (for-all (lambda (i) (= 1 (bytevector-u8-ref counts i)))
                       (iota 20000))
              (> (length (unbox ids)) 1)
              (memv (get-thread-id) (unbox ids))
              (equal? (crew-map crew-test-square (iota 1000))
                      (map (lambda (x) (* x x)) (iota 1000)))
              (guard (c [#t (string-contains-ci? (condition-message c)
                                                 "worklets only")])
                (crew-for 0 10 (lambda (lo hi) #f))
                #f))))

(define-worklet (crew-test-ignore lo hi x) #f)

(check "crew-for hands a worklet no procedure but worklets: none among its \
        arguments, nor in the pairs, vectors and boxes they hold; data \
        that holds itself is walked once"
       (let ([refused?
              (lambda (thunk)
                (guard (c [#t (string-contains-ci? (condition-message c)
                                                   "worklets only")])
                  (thunk)
                  #f))]
             [ring (list 1 2 3)])
         (set-cdr! (cddr ring) ring)
         (and (refused? (lambda () (crew-map (lambda (x) x) '(1 2))))
              (refused? (lambda () (crew-map crew-test-square (list 1 car))))
              (refused? (lambda ()
                          (crew-for 0 10 crew-test-ignore
                                    (vector 1 (list 2 (box car))))))
              (not (refused? (lambda ()
                               (crew-for 0 10 crew-test-ignore
                                         (vector ring crew-test-square
                                                 (box ring)))))))))

(define-worklet (crew-test-fail lo hi started finished)
  (crew-test-add! started 1)
  (when (fx= lo 200) (error 'crew-test "chunk 200"))
  (crew-test-busy 300 (box '()))
  (crew-test-add! finished 1))

(check "a call that raises: the calls not started never start, those \
        running finish, and the caller raises its condition"
       (let* ([started (box 0)] [finished (box 0)]
              [c (guard (c [#t c])
                   (crew-for* 10 0 1000 crew-test-fail started finished)
                   #f)])
         (printf "  ~a of 100 calls started, ~a finished\n" (unbox started)
                 (unbox finished))
         (and c (string=? (condition-message c) "chunk 200")
              (< (unbox started) 100)
              (= (unbox finished) (- (unbox started) 1)))))

;; Forever, but on main's thread: a millisecond there, so that the
;; workers, however slow to wake, get some of the calls.
(define-worklet (crew-test-runaway lo hi main)
  (if (fx= (get-thread-id) main)
      (crew-test-busy 1000 (box '()))
      (let loop () (loop))))

(check "on main a runaway call is cancelled at the caller's budget: the \
        caller raises the timeout, the worker escapes, and the crew works \
        on"
       (let* ([t0 (now-ms)]
              [c (guard (c [#t c])
                   (crew-for* 1 0 64 crew-test-runaway (get-thread-id))
                   #f)]
              [ms (- (now-ms) t0)] [ids (box '())])
         (printf "  raised after ~a ms: ~a\n" ms
                 (and c (condition? c) (condition->string c)))
         (crew-for* 1 0 64 crew-test-count (make-bytevector 64 0) 2000 ids)
         (and c (string-contains-ci? (condition-message c) "time budget")
              (< ms 400)
              (> (length (unbox ids)) 1))))

(define-worklet (crew-test-calls lo hi out) (set-box! out (list lo hi)))

(check "with no workers, crew-for is the worklet over the whole range"
       (let ([out (box #f)] [size (crew-size)])
         (crew-size-set! 0)
         (crew-for 3 900 crew-test-calls out)
         (crew-size-set! size)
         (equal? (unbox out) '(3 900))))

(define-worklet (crew-test-allocate lo hi sum)
  (crew-test-add! sum (vector-length (make-vector 20000 0))))

(check "while workers and main allocate, collections run: no thread waits \
        for good"
       (let ([sum (box 0)] [n0 (collections)])
         (do ([k 0 (+ k 1)]) ((= k 20))
           (crew-for* 1 0 64 crew-test-allocate sum)
           (make-vector 20000 0))
         (printf "  ~a collections\n" (- (collections) n0))
         (= (unbox sum) (* 20 64 20000))))

(check "in a process (a REPL evaluation), crew-for waits without taking \
        part, and the world steps meanwhile"
       (let* ([ids (box '())] [done #f] [steps0 0]
              [p (spawn "crew"
                        (lambda ()
                          (crew-for* 1 0 32 crew-test-count
                                     (make-bytevector 32 0) 5000 ids)
                          (set! done #t)))])
         (let ([until (+ (real-time) 2000)])   ; at most 2 s
           (let loop ()
             (when (and (memq p (procs)) (< (real-time) until))
               (steps 1)
               (set! steps0 (+ steps0 1))
               (loop))))
         (printf "  ~a steps while it waited\n" steps0)
         (and done (> steps0 3) (pair? (unbox ids))
              (not (memv (get-thread-id) (unbox ids))))))

;;; Environments (services/env.ss): a child sees what its parent shares,
;;; live, and changes none of it.

(define units-env-value 1)
(define (units-env-get) units-env-value)
(define units-env-secret 'root)
(define units-env-size 1)
(define (units-env-size-set! v)
  (unless (fixnum? v) (errorf 'units-env-size-set! "no fixnum: ~s" v))
  (set! units-env-size v))

(define units-env (env-child (env-root) 'units 'chez))
(env-share! units-env '(units-env-get (value . units-env-value)))
(env-share-setter! units-env '(size . units-env-size) 'units-env-size-set!)

(check "a child's path is its name under its parent's, and finds it; a \
        sibling of the same name is numbered"
       (let* ([twin (env-child (env-root) 'units 'chez)]
              [inner (env-child units-env 'inner 'core)]
              [ok (and (equal? (env-path (env-root)) "/")
                       (equal? (env-path units-env) "/units")
                       (equal? (env-path twin) "/units-2")
                       (equal? (env-path inner) "/units/inner")
                       (eq? (env-find "/units/inner") inner)
                       (eq? (env-find "/") (env-root))
                       (eq? (env-find "/worklets/") (env-find "/worklets"))
                       (not (env-find "/units/none"))
                       (equal? (format "~s ~s" (env-root) inner)
                               "#<env /> #<env /units/inner core>"))])
         (env-drop! twin)
         (env-drop! inner)
         ok))

(check "what a child is shared is live: a set! and a redefinition in the \
        world reach it, a pair renames"
       (let ([before (env-eval units-env '(list (units-env-get) value))])
         (set! units-env-value 2)
         (set! units-env-get (lambda () (* 10 units-env-value)))
         (let ([after (env-eval units-env '(list (units-env-get) value))])
           (set! units-env-get (lambda () units-env-value))
           (and (equal? before '(1 1)) (equal? after '(20 2))))))

(check "a child's set! of a shared name is refused as an R6RS import's \
        is; a name not shared is unbound there, and the child's set! of it \
        makes its own"
       (and (guard (c [#t (and (syntax-violation? c)
                               (equal? (condition->string c)
                                       "Exception: attempt to assign \
                                        read-only variable value"))])
              (env-eval units-env '(set! value 5))
              #f)
            (guard (c [#t #t]) (env-eval units-env 'units-env-secret) #f)
            (begin (env-eval units-env '(set! units-env-secret 'child))
                   (eq? (env-eval units-env 'units-env-secret) 'child))
            (= units-env-value 2)
            (eq? units-env-secret 'root)))

(check "a child's define of a shared name makes its own; the world's is \
        unchanged"
       (let ([e (env-child (env-root) 'units-own 'chez)])
         (env-share! e '(units-env-get))
         (env-eval e '(define (units-env-get) 'mine))
         (let ([ok (and (eq? (env-eval e '(units-env-get)) 'mine)
                        (= (units-env-get) 2))])
           (env-drop! e)
           ok)))

(check "a setter: the child's set! calls the world's setter, which may \
        refuse"
       (begin
         (env-eval units-env '(set! size 4))
         (and (= units-env-size 4)
              (= (env-eval units-env 'size) 4)
              (guard (c [#t (= units-env-size 4)])
                (env-eval units-env '(set! size 'big))
                #f))))

(check "a grandchild shares its parent's own names, and its parent's \
        shares, still read-only and live"
       (let ([g (env-child units-env 'grand 'chez)])
         (env-eval units-env '(define units-env-mine 'child))
         (env-share! g '(units-env-mine value))
         (set! units-env-value 3)
         (let ([ok (and (equal? (env-eval g '(list units-env-mine value))
                                '(child 3))
                        (guard (c [#t (syntax-violation? c)])
                          (env-eval g '(set! value 0))
                          #f))])
           (env-drop! g)
           ok)))

(check "env-binding follows a share to the world's binding"
       (let-values ([(env name) (env-binding units-env 'value)]
                    [(own own-name) (env-binding units-env 'units-env-secret)])
         (and (eq? env *world-env*) (eq? name 'units-env-value)
              (eq? own (env-environment units-env))
              (eq? own-name 'units-env-secret))))

(check "env-load loads into the child: a shared defvar defines there, and \
        keeps its value at the next load"
       (let ([f (string-append out-dir "/units-env-file.ss")])
         (call-with-output-file f
           (lambda (p) (write '(defvar units-env-loaded value) p))
           'replace)
         (env-share! units-env '(defvar))
         (env-load units-env f)
         (set! units-env-value 9)
         (env-load units-env f)
         (set! units-env-value 3)
         (and (= (env-eval units-env 'units-env-loaded) 3)
              (not (top-level-bound? 'units-env-loaded)))))

(define units-env-world (env-child (env-root) 'units-world 'chez))
(env-share-world! units-env-world)
(env-eval units-env-world '(define units-env-later 'mine))
(define units-env-later 'world)
(define units-env-newer 'world)

(check "a world namespace has every name of the world's, and gains those \
        the world defines later, but for those it defined itself"
       (and (eqv? (env-eval units-env-world '(length (windows)))
                  (length (windows)))
            (eq? (env-eval units-env-world 'units-env-newer) 'world)
            (eq? (env-eval units-env-world 'units-env-later) 'mine)
            (guard (c [#t (syntax-violation? c)])
              (env-eval units-env-world '(set! units-env-newer 0))
              #f)))

(check "a private namespace sees its list of the world's, live, and only \
        it"
       (let ([e (env-fork (env-root) 'private)])
         (let ([ok (and (eq? (env-eval e '(windows)) (windows))
                        (guard (c [#t #t]) (env-eval e 'set-theme!) #f)
                        (guard (c [#t (syntax-violation? c)])
                          (env-eval e '(set! windows 0))
                          #f))])
           (env-drop! e)
           ok)))

(check "a sandbox's children are sandboxes on its base, shared what it \
        holds, its own names and its shares, read-only"
       (let ([box (env-child (env-root) 'units-box 'core)])
         (env-share! box '(units-env-get))
         (env-eval box '(define units-box-own 7))
         (let ([inner (env-child box 'inner 'core)])
           (env-share! inner '(units-box-own units-env-get))
           (let ([ok (and (raises? (lambda () (env-child box 'ns 'chez)))
                          (equal? (env-eval inner
                                            '(list units-box-own
                                                   (units-env-get)))
                                  (list 7 (units-env-get)))
                          (guard (c [#t (syntax-violation? c)])
                            (env-eval inner '(set! units-box-own 1))
                            #f))])
             (env-drop! box)
             ok))))

(check "an environment forks only the kinds its own allows, refuses \
        what is not its to share and options it does not take, and hands \
        forks down: a world namespace's makes all the world's, not an \
        app's sandbox, a sandbox's sandboxes and threads, a pure one holds \
        none"
       (let* ([w (env-fork (env-root) 'world)]
              [wf (env-eval w 'fork)]
              [s (env-find (wf 'sandbox))]
              [sf (env-eval s 'fork)]
              [p (env-find (wf 'pure))])
         (env-eval s '(define units-fork-own 3))
         (let* ([inner (env-find (sf 'sandbox 'share '(units-fork-own)))]
                [named (env-find (sf 'sandbox 'name 'units-named))]
                [t (env-find (sf 'thread))]
                [ok (and (equal? (wf) (env-forks (env-root)))
                         (not (memq 'app (wf)))
                         (raises? (lambda () (wf 'app)))
                         (equal? (sf) '(sandbox thread))
                         (raises? (lambda () (sf 'private)))
                         (raises? (lambda ()
                                    (sf 'sandbox 'share '(units-env-value))))
                         (raises? (lambda () (sf 'sandbox 'colour 1)))
                         (raises? (lambda () (sf 'sandbox 'name 'a/b)))
                         (raises? (lambda () (env-fork p 'pure)))
                         (= (env-eval inner 'units-fork-own) 3)
                         (eq? (env-parent inner) s)
                         (equal? (env-path named)
                                 (string-append (env-path s) "/units-named"))
                         (equal? ((env-eval inner 'fork)) '(sandbox thread))
                         (vat-of t)
                         (eq? (env-kind t) 'thread)
                         (null? (env-forks t))
                         (null? (env-forks p))
                         (not (top-level-bound? 'fork (env-environment p))))])
           (vat-drop-env! w)
           ok)))

(check "a fork shares what it is given, renamed and through setters, after \
        its kind's own; what a child holds is its shares and its own names"
       (let ([c (env-fork (env-root) 'pure 'name 'units-given
                          'share '(units-env-get (v . units-env-value))
                          'setters '(((sz . units-env-size)
                                      . units-env-size-set!)))])
         (env-eval c '(set! sz 6))
         (env-eval c '(define units-given-own 1))
         (let ([ok (and (equal? (env-path c) "/units-given")
                        (eq? (env-kind c) 'pure)
                        (= units-env-size 6)
                        (equal? (env-eval c '(list (units-env-get) v))
                                (list (units-env-get) units-env-value))
                        (equal? (env-shared-names c)
                                '((sz units-env-size units-env-size-set! #f)
                                  (units-env-get units-env-get #f #f)
                                  (v units-env-value #f #f)))
                        (equal? (env-own-names c) '(units-given-own))
                        (raises? (lambda ()
                                   (env-fork (env-root) 'pure
                                             'share '(units-not-a-name)))))])
           (env-drop! c)
           ok)))

(check "the file dialog's paths: crumbs from Home or the computer, names \
        resolved against the folder, whole and without . or .., sizes and \
        dates as people read them"
       (and (equal? (file-dialog-crumbs "/home/u/code/x" "/home/u")
                    '(("Home" . "/home/u") ("code" . "/home/u/code")
                      ("x" . "/home/u/code/x")))
            (equal? (file-dialog-crumbs "/etc" "/home/u")
                    '(("Computer" . "/") ("etc" . "/etc")))
            (equal? (file-dialog-crumbs "/" "/home/u") '(("Computer" . "/")))
            (equal? (file-dialog-resolve "/a/b" "c") "/a/b/c")
            (equal? (file-dialog-resolve "/a/b" "/x/") "/x")
            (equal? (file-dialog-resolve "/" "c") "/c")
            (equal? (file-dialog-resolve "/a/b" "../c/./d/") "/a/c/d")
            (equal? (file-dialog-resolve "/a" "..") "/")
            (equal? (file-dialog-resolve "." ".")
                    (file-dialog-clean (current-directory)))
            (equal? (file-dialog-crumbs (file-dialog-resolve "/" "/x/./y")
                                        "/home/u")
                    '(("Computer" . "/") ("x" . "/x") ("y" . "/x/y")))
            (equal? (file-dialog-above "/a/b") "/a")
            (equal? (file-dialog-above "/a") "/")
            (equal? (file-dialog-size-label 512) "512 bytes")
            (equal? (file-dialog-size-label 4200) "4.2 KB")
            (equal? (file-dialog-size-label 1300000) "1.3 MB")
            (let ([now (time-second (current-time))])
              (and (= 5 (string-length (file-dialog-date-label now now)))
                   (string-contains-ci? (file-dialog-date-label 86400 now)
                                        ", 1970")))))

(check "the world forks every kind, in the order registered; a bare child \
        forks nothing and is titled by its base"
       (let ([c (env-child (env-root) 'units-bare 'core)])
         (let ([ok (and (equal? (env-forks (env-root))
                                '(private world pure sandbox thread))
                        (null? (env-forks (env-worklets)))
                        (string=? (env-title (env-root)) "The world")
                        (string=? (env-title (env-worklets)) "Worklets")
                        (null? (env-forks c)) (not (env-kind c))
                        (string=? (env-title c) "Sandbox"))])
           (env-drop! c)
           ok)))

(check "a share as typed in Environments: a name, renamed with as, set \
        through a setter with via"
       (let ([read (lambda (s) (call-with-values
                                 (lambda () (envs-share-words s))
                                 list))])
         (and (equal? (read "now-ms") '(now-ms #f))
              (equal? (read "now-ms as clock") '((clock . now-ms) #f))
              (equal? (read "size via size-set!") '(size size-set!))
              (equal? (read " a  as b via c ") '((b . a) c))
              (equal? (read "a b") '(#f #f)))))

(check "a REPL's tinted background follows the style: one opened in Mac \
        and shown in Genera has Genera's, as one opened there"
       (let* ([rgb (lambda (w) (call-with-values
                                 (lambda () (color-rgba (window-bg w)))
                                 list))]
              [a (begin (set-style! 'mac) (repl 'private))]
              [in-mac (rgb a)]
              [b (begin (set-style! 'genera) (repl 'private))]
              [ok (and (not (equal? in-mac (rgb a)))
                       (equal? (rgb a) (rgb b)))])
         (close-window! a)
         (close-window! b)
         (set-style! 'mac)
         ok))

(check "a dialog stays above the window that waits on it and takes its \
        keyboard, where the style says so (modal-above); else the window \
        comes above it; closing the window closes the dialog"
       (let* ([p (open-window "Parent" 'size '(300 . 200))]
              [c (ui-open-modal p "Child" 200 100)])
         (focus-window! p)
         (let ([kept (and (eq? (focused-window) c) (eq? (car (windows)) c)
                          (eq? (cadr (windows)) p))])
           (override! 'modal-above #f)
           (focus-window! p)
           (let ([up (and (eq? (focused-window) p) (eq? (car (windows)) p))])
             (override! 'modal-above)
             (close-window! p)
             (steps 1)
             (and kept up (not (memq c (windows))))))))

(check "a window's title icon is drawn by the Mac and Windows styles' \
        frames, left of the title; Genera's busy mark is a terminal's \
        spinner in a character's cell, and its who line says Run"
       (let* ([at #f]
              [w (open-window "Iconic" 'size '(400 . 200)
                              'title-icon (lambda (x y s flags)
                                            (set! at (list x s flags))))]
              [drawn (lambda (style)
                       (set-style! style)
                       (set! at #f)
                       (invalidate!)
                       (steps 1)
                       at)])
         (let* ([mac (drawn 'mac)] [windows (drawn 'windows)])
           (set-style! 'genera)
           (focus-window! w)
           (window-set! w 'busy "Running")
           (let* ([state (genera-who-state)]
                  [idle (begin (window-set! w 'busy #f)
                               (genera-who-state))]
                  [size (call-with-values ui-busy-size list)]
                  [cell (list (font-char-width 'mono)
                              (font-line-height 'mono))])
             (set-style! 'mac)
             (close-window! w)
             (and mac (< (car mac) (+ (window-x w) (/ (window-w w) 2)))
                  (= (cadr mac) (ui-glyph-size)) (null? (caddr mac))
                  windows (< (car windows) (+ (window-x w) 40))
                  (equal? state "Run") (equal? idle "")
                  (assq 'windows (genera-who-line-areas))
                  (equal? size cell)
                  (equal? (call-with-values ui-busy-size list)
                          (list (ui-glyph-size) (ui-glyph-size))))))))

(check "a world namespace's next sync brings the names the world gained \
        since, but those it defined itself; env-sync! shares them now"
       (let ([w (env-fork (env-root) 'world 'name 'units-sync)])
         (eval '(define units-sync-later 1) *world-env*)
         (eval '(define units-sync-mine 2) *world-env*)
         ;; not by env-eval, which syncs first
         (eval '(define units-sync-mine 'its-own) (env-environment w))
         (let* ([before (env-unsynced w)]
                [ok (and (memq 'units-sync-later before)
                         (not (memq 'units-sync-mine before))
                         (begin (env-sync! w) (null? (env-unsynced w)))
                         (assq 'units-sync-later (env-shared-names w))
                         (eq? (env-eval w 'units-sync-mine) 'its-own)
                         (null? (env-unsynced units-env)))])
           (env-drop! w)
           ok)))

(check "the share dialog's names as fork and env-share! take them, and as \
        the Fork sheet's chips"
       (let-values ([(shares setters)
                     (envs-picked-shares '((a "" "") (b "bee" "")
                                           (c "" "c-set!")
                                           (d "dee" "d-set!")))])
         (and (equal? shares '(a (bee . b)))
              (equal? setters '((c . c-set!) ((dee . d) . d-set!)))
              (raises? (lambda () (envs-picked-shares '((a "a b" "")))))
              (equal? (envs-picked-chip '(d "dee" "d-set!"))
                      "d as dee via d-set!")
              (equal? (envs-chip-picked "d as dee via d-set!")
                      '(d "dee" "d-set!"))
              (equal? (envs-chip-picked "a") '(a "" "")))))

(check "dropping a child takes it, and its children, out of the tree and \
        marks them dropped; not the world, nor /worklets, nor /apps"
       (let ([g (env-child units-env-world 'grand 'chez)])
         (env-drop! units-env-world)
         (env-drop! units-env)
         (and (env-dropped? g)
              (env-dropped? units-env)
              (raises? (lambda () (env-child g 'more 'chez)))
              (raises? (lambda () (env-drop! (env-root))))
              (raises? (lambda () (env-drop! (env-worklets))))
              (raises? (lambda () (env-drop! (grant-apps-env))))
              (not (env-find "/units-world/grand"))
              (not (env-find "/units"))
              (not (memq units-env (env-children (env-root))))
              (equal? (map env-name (env-children (env-root)))
                      '(worklets apps)))))

;;; The confined base (services/env.ss): what is always safe, for apps.

(check "a confined sandbox has what is always safe, and nothing that \
        reaches past its arguments: no files, eval or environments, C, \
        threads or sleep, the clock, the inspector, the console's ports or \
        exit; its children are confined or core, never chez"
       (let* ([e (env-child (env-root) 'units-confined 'confined)]
              [held (environment-symbols (env-environment e))]
              [ok (and (for-all (lambda (n) (not (memq n held)))
                                '(eval expand load interaction-environment
                                  environment copy-environment top-level-value
                                  set-top-level-value! define-top-level-value
                                  foreign-procedure load-shared-object
                                  fork-thread make-mutex sleep open-input-file
                                  open-output-file open-file-input-port
                                  file-exists? delete-file directory-list
                                  system process getenv exit current-time
                                  real-time current-date record-rtd inspect
                                  inspect/object collect-request-handler
                                  print-radix syntax-case datum->syntax
                                  console-output-port current-input-port
                                  read))
                       (equal? (env-eval e '(let ([v (make-fxvector 2 1)])
                                              (fxvector-set! v 0 (fx+ 1 2 3))
                                              (list (fxvector->list v)
                                                    (sort < '(3 1 2))
                                                    (format "~a!" 'x))))
                               '((6 1) (1 2 3) "x!"))
                       (raises? (lambda () (env-child e 'units-wider 'chez)))
                       (eq? (env-base (env-child e 'units-narrower 'core))
                            'core)
                       (equal? (env-title e) "Sandbox"))])
         (env-drop! e)
         ok))

(check "a confined sandbox's record types are its own: one named by a uid \
        stays one type as it is defined again, and is never the world's"
       (let* ([e (env-child (env-root) 'units-records 'confined)]
              [named '(define-record-type env
                        (nongenerative schevana-env-3)
                        (fields a))])
         (env-eval e named)
         (let ([kept (env-eval e '(make-env 1))])
           (env-eval e named)
           (let ([ok (and (= 1 (env-eval e '(begin
                                              (define-record-type units-pt
                                                (fields x))
                                              (units-pt-x (make-units-pt 1)))))
                          ((env-eval e 'env?) kept)
                          (not ((env-eval e 'env?) (env-root)))
                          (eq? (record-type-uid
                                (env-eval e '(make-record-type-descriptor
                                              'q #f 'schevana-grant-app-1 #f
                                              #f '#())))
                               '/units-records:schevana-grant-app-1))])
             (env-drop! e)
             ok))))

(check "what a confined sandbox writes to the console goes to its log, and \
        to the caller's output too while root evaluates there (a REPL's)"
       (let* ([e (env-child (env-root) 'units-log 'confined)]
              [out (open-output-string)])
         (parameterize ([current-output-port out])
           (env-eval e '(begin (display "a") (newline) (printf "~a" 1)
                               (format #t "b") (write "c" (current-output-port))
                               (define (units-say) (display "!")))))
         ((env-eval e 'units-say))   ; no evaluation: the log alone
         (let ([ok (and (equal? (env-log e) "a\n1b\"c\"!")
                        (equal? (get-output-string out) "a\n1b\"c\""))])
           (env-drop! e)
           ok)))

;;; Apps in sandboxes (services/grant.ss): bundles, grants, stubs and the
;;; person's decisions.

(check "a tree app that requests bundles runs in its sandbox under /apps, \
        holding them, live, and nothing it did not request; the world's \
        apps run in the world, and (clock) there opens Clock"
       (let* ([c (grant-env 'clock)] [held (environment-symbols
                                            (env-environment c))]
              [w (clock)]
              [ok (and (equal? (env-path c) "/apps/clock")
                       (eq? (env-kind c) 'app) (eq? (env-base c) 'confined)
                       (eq? (env-eval c 'now-ms) now-ms)
                       (eq? (env-eval c 'fill-rect) fill-rect)
                       (not (memq 'notify held)) (not (memq 'windows held))
                       (not (memq 'draw-clock-face
                                  (environment-symbols *world-env*)))
                       (not (grant-env 'settings)) (not (grant-env 'repl))
                       (eq? (window-app w) 'clock)
                       (equal? (grant-requested 'clock)
                               '(window draw timers))
                       (null? (grant-undecided 'clock)))])
         (close-window! w)
         ok))

(check "an app's define-app registers its own app alone, a window it opens \
        is its own or no app's, never another's, and its defvar keeps a value \
        as it loads again, in its sandbox"
       (let* ([c (grant-env 'clock)]
              [w (env-eval c '(open-window "Units" 'app 'settings))]
              [none (env-eval c '(open-window "Units" 'app #f))]
              [ok (and (raises? (lambda ()
                                  (env-eval c '(define-app (units-not-clock)
                                                 "No" #f))))
                       (not (memq 'units-not-clock (apps)))
                       (eq? (window-app w) 'clock)
                       (not (window-app none))
                       (begin (env-eval c '(defvar units-kept 1))
                              (env-eval c '(set! units-kept 2))
                              (env-eval c '(defvar units-kept 1))
                              (= 2 (env-eval c 'units-kept)))
                       (not (memq 'units-kept
                                  (environment-symbols *world-env*))))])
         (close-window! w)
         (close-window! none)
         ok))

(check "an app the person approves: what it requests and no one decided \
        raises, naming it; a decision is saved, makes its sandbox again, \
        and is read back from the file; a denied bundle raises as denied"
       (let* ([before (grant-env 'sketch)]
              [asked (grant-undecided 'sketch)]
              [needed (guard (c [(grant-needed? c) c])
                        (env-eval before '(open-window "x")) #f)])
         (grant-decide! 'sketch '(window) '(draw))
         (let* ([after (grant-env 'sketch)]
                [saved (call-with-input-file *grant-file-path* get-string-all)]
                [denied (guard (c [(grant-needed? c) (condition-message c)])
                          (env-eval after '(fill-rect 0 0 1 1 'red)) #f)])
           (hashtable-clear! *grant-decisions*)
           (grant-file-load!)
           (let ([ok (and (equal? asked '(window draw))
                          needed (eq? (grant-needed-app needed) 'sketch)
                          (eq? (grant-needed-bundle needed) 'window)
                          (string-contains-ci? (condition-message needed)
                                               "Sketch needs Open windows")
                          (env-dropped? before) (not (env-dropped? after))
                          (equal? (env-path after) "/apps/sketch")
                          (string-contains-ci? saved "approved (window)")
                          denied (string-contains-ci? denied "denied")
                          (let-values ([(ok no) (grant-of 'sketch)])
                            (and (equal? ok '(window)) (equal? no '(draw))))
                          (eq? (grant-env 'sketch) after)
                          (null? (grant-undecided 'sketch)))])
             (grant-decide! 'sketch '(window draw) '())
             ok))))

(check "Environments says how an app's requests stand and which bundle \
        each name came in, and what it is there: the world's, or a stub; \
        other environments keep the parent's name, set! and where bound"
       (begin
         (grant-decide! 'sketch '(window) '(draw))
         (let* ([e (grant-env 'sketch)] [rows (env-shared-names e)]
                [text (lambda (n key)
                        (envs-names-text e 'shared (assq n rows) key))]
                [ok (and (eq? (grant-state 'sketch 'draw) 'denied)
                         (eq? (grant-state 'clock 'timers) 'allowed)
                         (eq? (grant-bundle-of 'fill-rect) 'draw)
                         (not (grant-bundle-of 'define-app))
                         (eq? (grant-app-in e) 'sketch)
                         (not (grant-app-in (grant-apps-env)))
                         (equal? (envs-bundle-label 'sketch 'window)
                                 "Open windows")
                         (equal? (envs-bundle-label 'sketch 'draw)
                                 "Draw in its windows · denied")
                         (equal? (envs-bundle-label #f 'toasts)
                                 "Show notifications · 1")
                         (equal? (text 'close-window! 'bundle) "Open windows")
                         (equal? (text 'close-window! 'held) "the world's")
                         (equal? (text 'fill-rect 'bundle)
                                 "Draw in its windows")
                         (equal? (text 'fill-rect 'held) "a stub: denied")
                         (equal? (text 'define-app 'bundle) "Every app's")
                         (equal? (map car (envs-names-columns e 'shared 300))
                                 '(name bundle held))
                         (equal? (map car (envs-names-columns (env-root)
                                                              'shared 300))
                                 '(name from set holder))
                         (begin
                           (hashtable-delete! *grant-decisions* 'sketch)
                           (equal? (envs-bundle-label 'sketch 'draw)
                                   "Draw in its windows · not decided")))])
           (grant-decide! 'sketch '(window draw) '())
           ok)))

(check "an app of the person's runs in a sandbox though it requests \
        nothing, and holds nothing of the world's then"
       (let ([dir (string-append out-dir "/apps")])
         (unless (file-directory? dir) (mkdir dir))
         (call-with-output-file (string-append dir "/units-mine.ss")
           (lambda (p)
             (write '(define-app (units-mine) "Mine" (open-window "Mine")) p))
           'replace)
         (grant-load-app! (string-append dir "/units-mine.ss"))
         (let ([e (grant-env 'units-mine)])
           (and e (equal? (env-path e) "/apps/units-mine")
                (memq 'units-mine (apps))
                (raises? (lambda () (app-launch! 'units-mine)))
                (not (memq 'open-window
                           (environment-symbols (env-environment e))))))))

;;; Vats (services/vat.ss): threads with a mailbox and a sandbox; jobs,
;;; their deliveries on main, and their kills.

;; Steps the world until (pred), for at most 2 s.
(define (vat-test-until pred)
  (let ([until (+ (real-time) 2000)])
    (let loop ()
      (cond [(pred) #t]
            [(> (real-time) until) #f]
            [else (steps 1) (loop)]))))

(define-worklet (vat-test-add a b) (fx+ a b))
(define-worklet (vat-test-where) (get-thread-id))
(define-worklet (vat-test-spin) (let loop () (loop)))
(define-worklet (vat-test-fail) (error 'vat-test "failed on purpose"))

(define vat-test (vat-start! (env-child (env-root) 'vat-test 'core)))

(check "a vat runs a worklet on its own thread, and the job's then runs on \
        main at a later step, once"
       (let* ([got '()]
              [j (vat-send! vat-test vat-test-where '()
                            (lambda (id)
                              (set! got (cons (list id (get-thread-id))
                                              got))))])
         (and (vat-job-pending? j)
              (null? got)
              (vat-test-until (lambda () (pair? got)))
              (begin (steps 3) (= (length got) 1))
              (not (= (caar got) (get-thread-id)))
              (= (cadar got) (get-thread-id))
              (not (vat-job-pending? j)))))

(check "a vat keeps state in its sandbox: forms define it, and jobs by \
        name change it, in the order sent"
       (let ([got '()])
         (vat-eval! vat-test '(define vat-test-tally 0) #f)
         (vat-eval! vat-test
                    '(define (vat-test-tally! k)
                       (set! vat-test-tally (+ vat-test-tally k))
                       vat-test-tally)
                    #f)
         (for-each (lambda (k)
                     (vat-send! vat-test 'vat-test-tally! (list k)
                                (lambda (n) (set! got (cons n got)))))
                   '(1 2 3))
         (and (vat-test-until (lambda () (= (length got) 3)))
              (equal? (reverse got) '(1 3 6))
              (not (top-level-bound? 'vat-test-tally)))))

(check "a job carries no procedure but worklets, a vat runs only in a \
        sandbox, and the pool takes neither forms nor names"
       (let ([refused?
              (lambda (thunk)
                (guard (c [#t (string-contains-ci? (condition-message c)
                                                   "no procedure but")])
                  (thunk)
                  #f))]
             [chez (env-child (env-root) 'vat-chez 'chez)])
         (let ([ok (and (refused? (lambda () (vat-send! vat-test car '() #f)))
                        (refused? (lambda ()
                                    (vat-send! vat-test vat-test-add
                                               (list 1 (vector car)) #f)))
                        (refused? (lambda () (vat-eval! vat-test `',car #f)))
                        (raises? (lambda () (vat-start! chez)))
                        (raises? (lambda () (vat-eval! (vat-pool) 1 #f)))
                        (raises? (lambda ()
                                   (vat-send! (vat-pool) 'vat-test-add
                                              '(1 2) #f))))])
           (env-drop! chez)
           ok)))

(check "a job's then runs as a handler of the window it was sent from: \
        (current-window) is it, and its error crashes it"
       (let ([w (open-window "Then" 'size '(200 . 100))] [seen #f])
         (parameterize ([current-window w])
           (vat-send! vat-test vat-test-add '(1 2)
                      (lambda (v)
                        (set! seen (list v (current-window)))
                        (error 'then "then failed"))))
         (let ([ok (and (vat-test-until (lambda () seen))
                        (equal? seen (list 3 w))
                        (window-error w)
                        (string-contains-ci?
                         (condition->string (cdr (window-error w)))
                         "then failed"))])
           (close-window! w)
           ok)))

(check "a job that raises crashes its window, which kills the window's \
        other jobs: the running one escapes, and the vat goes on"
       (let ([w (open-window "Jobs" 'size '(200 . 100))] [ran #f]
             [after (box #f)])
         (let* ([fail (parameterize ([current-window w])
                        (vat-send! vat-test vat-test-fail '() #f))]
                [spin (parameterize ([current-window w])
                        (vat-send! vat-test vat-test-spin '()
                                   (lambda () (set! ran #t))))])
           (vat-send! vat-test vat-test-add '(2 2)
                      (lambda (v) (set-box! after v)))
           (let ([ok (and (vat-test-until (lambda () (unbox after)))
                          (= (unbox after) 4)
                          (eq? (car (window-error w)) 'job)
                          (string-contains-ci?
                           (condition->string (cdr (window-error w)))
                           "failed on purpose")
                          (not (vat-job-pending? fail))
                          (not (vat-job-pending? spin))
                          (not ran))])
             (close-window! w)
             ok))))

(check "a killed job never starts, or, running, escapes; its then never \
        runs; and closing a window kills the jobs sent from it"
       (let* ([ran #f] [after (box #f)]
              [w (open-window "Closed" 'size '(200 . 100))]
              [spin (vat-send! vat-test vat-test-spin '()
                               (lambda () (set! ran 'spin)))]
              [queued (vat-send! vat-test vat-test-add '(1 1)
                                 (lambda (v) (set! ran 'queued)))]
              [closed (parameterize ([current-window w])
                        (vat-send! vat-test vat-test-spin '()
                                   (lambda () (set! ran 'closed))))])
         (vat-job-kill! queued)
         (sleep (make-time 'time-duration 20000000 0))   ; spin is running
         (vat-job-kill! spin)
         (close-window! w)
         (vat-send! vat-test vat-test-add '(3 4)
                    (lambda (v) (set-box! after v)))
         (and (not (exists vat-job-pending? (list spin queued closed)))
              (vat-test-until (lambda () (unbox after)))
              (= (unbox after) 7)
              (begin (steps 3) (not ran)))))

(check "a result that is a sandbox's own procedure is refused on main"
       (let ([w (open-window "Leak" 'size '(200 . 100))] [got #f])
         (parameterize ([current-window w])
           (vat-eval! vat-test 'vat-test-tally! (lambda (p) (set! got p))))
         (let ([ok (and (vat-test-until (lambda () (window-error w)))
                        (not got)
                        (string-contains-ci?
                         (condition->string (cdr (window-error w)))
                         "returns no procedure but"))])
           (close-window! w)
           ok)))

(check "the pool runs worklets on its own threads"
       (let ([ids (box '())])
         (do ([i 0 (+ i 1)]) ((= i 8))
           (vat-send! (vat-pool) vat-test-where '()
                      (lambda (id) (set-box! ids (cons id (unbox ids))))))
         (and (vat-test-until (lambda () (= (length (unbox ids)) 8)))
              (not (memv (get-thread-id) (unbox ids))))))

(check "the pool's size is settable: threads past it stop, more start, \
        and the jobs run on; none is refused"
       (let ([size (vat-pool-size)] [done (box 0)])
         (define (run! n)
           (do ([i 0 (+ i 1)]) ((= i n))
             (vat-send! (vat-pool) vat-test-add '(1 1)
                        (lambda (v) (set-box! done (+ (unbox done) v))))))
         (vat-pool-size-set! 1)
         (run! 4)
         (let ([one (length (vat-threads (vat-pool)))])
           (vat-pool-size-set! 6)
           (run! 4)
           (let ([six (length (vat-threads (vat-pool)))])
             (let ([ok (and (= one 1) (= six 6) (= (vat-pool-size) 6)
                            (vat-test-until (lambda () (= (unbox done) 16)))
                            (raises? (lambda () (vat-pool-size-set! 0))))])
               (vat-pool-size-set! size)
               (and ok (= (length (vat-threads (vat-pool))) size)))))))

(check "vat-repl! evaluates forms on the vat's thread and prints there \
        what they return, procedures too, and an error as its text"
       (let* ([e (env-child (env-root) 'vat-repl 'core)]
              [v (vat-start! e)] [got #f] [err #f])
         (vat-repl! v '((define x 2) (* x 21) (lambda () x)) 60
                    (lambda (texts) (set! got texts))
                    (lambda (text) (set! err text)))
         (vat-repl! v '((car 1)) 60
                    (lambda (texts) (set! got 'no))
                    (lambda (text) (set! err text)))
         (let ([ok (and (vat-test-until (lambda () err))
                        (eq? (vat-of e) v)
                        (equal? (car got) "42")
                        (string-prefix? "#<procedure" (cadr got))
                        (string-contains-ci? err "car"))])
           (vat-drop-env! e)
           (and ok (not (vat-of e)) (not (env-find "/vat-repl"))))))

(check "a job sent with a fail gives it the condition, and its window \
        stays up"
       (let ([w (open-window "Fail" 'size '(200 . 100))] [got #f])
         (parameterize ([current-window w])
           (vat-send! vat-test vat-test-fail '() #f (lambda (c) (set! got c))))
         (let ([ok (and (vat-test-until (lambda () got))
                        (condition? got)
                        (not (window-error w)))])
           (close-window! w)
           ok)))

(check "dropping a vat kills its jobs and refuses new ones"
       (let* ([e (env-child (env-root) 'vat-drop 'core)]
              [v (vat-start! e)]
              [j (vat-send! v vat-test-spin '() #f)])
         (vat-drop! v)
         (vat-drop! vat-test)
         (env-drop! e)
         (env-drop! (vat-env vat-test))
         (and (not (vat-job-pending? j))
              (raises? (lambda () (vat-send! v vat-test-add '(1 1) #f)))
              (equal? (format "~s" v) "#<vat /vat-drop>"))))

;;; The pacer: exactly one tick a period while the work fits.

;; The main loop for ms of a fake clock (ns), with a wait for host events
;; that only moves the clock, and a present that, with vsync?, waits for
;; the screen's next refresh after a frame drawn. In it: a window whose
;; tick keeps books (3 ms) and never draws, one that moves at every tick
;; (2 ms of its tick, draw-ms of drawing), a busy process (0.5 ms a
;; slice) if opts has 'busy, a timer at 205 ms, a key at 503 ms, and with
;; 'flood a key every 2 ms besides, each ending the wait. => an alist of
;; what happened: the bookkeeper's ticks' times, the frames drawn, the
;; steps, the process's slices, when the timer ran, and whether the key
;; came. At most 50 steps a ms of the clock: past that the loop spins.
(define (pacer-test-run vsync? draw-ms ms . opts)
  (let* ([real-ns now-ns] [real-ms now-ms] [real-events host-events]
         [real-present host-present-damage!] [rate (pacer-rate)]
         [real-vsync? *host-vsync?*]
         [period (pacer-period)]
         [t 0] [drawn? #f] [ticks '()] [frames 0] [slices 0] [fired #f]
         [keyed #f] [stepped 0] [flood-at #f]
         [advance (lambda (ns) (set! t (+ t ns)))])
    (set! now-ns (lambda () t))
    (set! now-ms (lambda () (quotient t 1000000)))
    ;; the wait for input ends at the next key of a flood
    (set! host-events
          (lambda (wait-ms)
            (let ([until (+ t (* wait-ms 1000000))])
              (if (and flood-at (<= flood-at until))
                  (begin (set! t (max t flood-at))
                         (set! flood-at (+ t 2000000))
                         '((key-down #\b ())))
                  (begin (set! t until) '())))))
    (set! *host-vsync?* vsync?)
    (set! host-present-damage!
          (lambda ()
            (when (and vsync? drawn?)   ; to the next refresh
              (set! t (* period (+ 1 (quotient t period)))))
            (set! drawn? #f)))
    (pacer-rate! 'screen)
    (let* ([keeper (open-window "Keeper" 'size '(80 . 60)
                                'tick (lambda (win)
                                        (set! ticks (cons t ticks))
                                        (advance 3000000)))]
           [mover (open-window "Mover" 'size '(80 . 60)
                               'tick (lambda (win)
                                       (advance 2000000)
                                       (invalidate! win))
                               'key (lambda (win k mods) (set! keyed #t))
                               'draw (lambda (win w h)
                                       (advance (* draw-ms 1000000))
                                       (set! drawn? #t)
                                       (set! frames (+ frames 1))))]
           [p (and (memq 'busy opts)
                   (spawn "paced" (lambda ()
                                    (let loop ()
                                      (advance 500000)
                                      (set! slices (+ slices 1))
                                      (engine-block)
                                      (loop)))))])
      (focus-window! mover)
      ;; 100 ms to settle (the first frame has no drawing time to go by)
      (let ([settled (+ t 100000000)])
        (let loop ()
          (when (< t settled) (schevana-step! (pacer-wait-ms) #t) (loop))))
      (set! ticks '())
      (set! frames 0)
      (set! slices 0)
      (let ([start (now-ms)])
        (after 205 (lambda () (set! fired (- (now-ms) start)))))
      (when (memq 'flood opts) (set! flood-at t))
      (let ([end (+ t (* ms 1000000))] [key-at (+ t 503000000)])
        (let loop ()
          (when (and (< t end) (< stepped (* 50 ms)))
            (when (and key-at (>= t key-at))
              (inject! '(key-down #\a ()))
              (set! key-at #f))
            (schevana-step! (pacer-wait-ms) #t)
            (set! stepped (+ stepped 1))
            (loop))))
      (when p (kill! p))
      (close-window! keeper)
      (close-window! mover)
      (set! now-ns real-ns)
      (set! now-ms real-ms)
      (set! host-events real-events)
      (set! host-present-damage! real-present)
      (set! *host-vsync?* real-vsync?)
      (pacer-rate! rate)
      (steps 1)
      `((ticks . ,(reverse ticks)) (frames . ,frames) (steps . ,stepped)
        (slices . ,slices) (fired . ,fired) (keyed . ,keyed)
        (period . ,period)))))

;; The gaps between ticks at times ts, ns.
(define (pacer-test-gaps ts)
  (map - (cdr ts) (list-head ts (- (length ts) 1))))

(check "the pacer ticks exactly once a period while the work fits, with \
        vsync or without, bookkeeping that draws nothing, a busy process \
        and input between: a frame a tick, the process in the time left, \
        a timer on its time"
       (for-all
        (lambda (vsync?)
          (let* ([r (pacer-test-run vsync? 5 1000 'busy)]
                 [get (lambda (k) (cdr (assq k r)))]
                 [ticks (get 'ticks)] [period (get 'period)]
                 [gaps (pacer-test-gaps ticks)])
            (printf "  vsync ~a: ~a ticks, ~a frames, ~a slices, gaps ~a..~a, \
                     timer at ~a\n"
                    vsync? (length ticks) (get 'frames) (get 'slices)
                    (apply min gaps) (apply max gaps) (get 'fired))
            ;; 1,000 ms of 16.7: 60 periods, 61 ticks at their ends
            (and (<= 60 (length ticks) 61)
                 ;; a period apart on average, to the ms
                 (< (abs (- (quotient (- (car (last-pair ticks)) (car ticks))
                                      (length gaps))
                            period))
                    1000000)
                 ;; and each: with vsync, give or take the 2 ms a tick may
                 ;; start early and the clock's ms; without, also a frame
                 ;; that input asked for (5 ms) drawn just before a tick
                 (for-all (lambda (g)
                            (< (abs (- g period)) (if vsync? 3000000 8000000)))
                          gaps)
                 (<= (abs (- (get 'frames) (length ticks))) 2)
                 (> (get 'slices) 0)
                 (get 'keyed)
                 ;; at the step after its time: within a period
                 (<= 205 (get 'fired) (+ 205 17)))))
        '(#t #f)))

(check "with nothing else to do, the loop sleeps between ticks: a step a \
        tick, and those of a timer and a key, with vsync or without"
       (for-all
        (lambda (vsync?)
          (let* ([r (pacer-test-run vsync? 5 1000)]
                 [ticks (length (cdr (assq 'ticks r)))]
                 [steps (cdr (assq 'steps r))])
            (printf "  vsync ~a: ~a ticks, ~a steps\n" vsync? ticks steps)
            (and (<= 60 ticks 61) (<= steps (+ ticks 5)))))
        '(#t #f)))

(check "without the screen's wait, input draws at the next tick: a key \
        every 2 ms, and still a frame a tick, a tick a period"
       (let* ([r (pacer-test-run #f 5 1000 'flood)]
              [ticks (cdr (assq 'ticks r))] [frames (cdr (assq 'frames r))]
              [steps (cdr (assq 'steps r))])
         (printf "  ~a ticks, ~a frames, ~a steps\n" (length ticks) frames
                 steps)
         (and (<= 60 (length ticks) 61) (<= frames (length ticks))
              (> steps 200))))

(check "the profiler keeps a tick, not a step: the steps between ticks \
        (a key every 2 ms) sum into the tick they lead up to, each about \
        a period long"
       (let* ([r #f]
              [made (profile-test-ticks
                     (lambda () (set! r (pacer-test-run #f 5 1000 'flood))))]
              [ticks (length (cdr (assq 'ticks r)))]
              [steps (cdr (assq 'steps r))]
              [period (cdr (assq 'period r))]
              ;; the run's, newest first: not the step after it, nor the
              ;; ticks of its 100 ms of settling
              [run (list-head (cdr made) (- ticks 1))]
              [lengths (map (lambda (seq) (profile-tick-ns seq 'ns)) run)])
         (printf "  ~a ticks, ~a steps, ~a kept, ~a..~a ns\n" ticks steps
                 (length made) (apply min lengths) (apply max lengths))
         (and (> steps (* 3 ticks)) (<= (length made) (+ ticks 10))
              (for-all (lambda (ns) (< (abs (- ns period)) 3000000))
                       lengths))))

(check "past a period of work, the pacer slows down: ticks come as soon \
        as the last is done, none skipped, none closer than a period"
       (let* ([r (pacer-test-run #t 20 1000)]
              [ticks (cdr (assq 'ticks r))] [period (cdr (assq 'period r))]
              [gaps (pacer-test-gaps ticks)])
         (printf "  ~a ticks, gaps ~a..~a\n" (length ticks) (apply min gaps)
                 (apply max gaps))
         (and (< 20 (length ticks) 45)
              (for-all (lambda (g) (>= g (- period 3000000))) gaps))))

(check "(pacer-rate! 30) halves the ticks in real time, and 'screen brings \
        the screen's back"
       (let ([rate (pacer-rate)])
         (pacer-rate! 30)
         (let ([p30 (pacer-period)])
           (pacer-rate! 'screen)
           (let ([screen (pacer-period)])
             (pacer-rate! rate)
             (and (= p30 33333333) (= screen (host-frame-ns)))))))

;;; The Ticks: a bar a tick, its waits too, against the pacer's period.


(check "a tick's waits are phases of their own, the screen's too, so that \
        its phases add up to it; profile-tick-phases says where its time \
        went, the most first, and profile-slow-ticks the ticks that came \
        late: past one and a half periods; Monitor stacks its bars' work \
        the same way, its waits above, and its tooltip says the same"
       (let* ([real now-ns] [fake (* 1000 1000000000)]
              [clock (lambda (ns) (set! fake (+ fake ns)))]
              [win (open-window "Grower" 'size '(120 . 80) 'pos '(600 . 400))])
         ;; a step by hand, a tick of its own, as the main loop's (a
         ;; window's handlers run in an engine, where spans are untimed):
         ;; 10 ms waiting for input (the step's own), 1 of ticks, 3 of the
         ;; window's drawing, and 2 waiting for the screen in present
         (set! now-ns (lambda () fake))
         (profile-clear!)
         (with-profile-span 'step #f
           (clock 10000000)
           (with-profile-span 'tick #f (clock 1000000))
           (with-profile-span 'render #f
             (with-profile-span (window-id win) #f (clock 3000000)))
           (with-profile-span 'present #f
             (with-profile-span 'vsync-wait #f (clock 2000000))))
         (set! now-ns real)
         (let* ([seq (profile-newest-tick)]
                [phases (profile-tick-phases seq)]
                [index (lambda (p) (list-index (lambda (q) (eq? (car q) p))
                                               monitor-phases))]
                [order (monitor-bars-order (list seq))]
                ;; the tick ended at 12:00:03.400 of the day
                [zero (- (+ (* 1000 (+ (* 12 3600) 3)) 400)
                         (quotient (profile-tick-ns seq 'end) 1000000))]
                [tip (monitor-tick-tip seq zero 16666666)]
                [late (monitor-tick-tip seq zero 3000000)]
                [lines (list (format "tick ~a, ended 12:00:03.400" seq)
                             "16 ms, in time (a tick is 16.7 ms)"
                             "waiting for input 10 ms" "render 3 ms"
                             "waiting for the screen 2 ms" "ticks 1 ms"
                             "Grower 3.00 ms")])
           (close-window! win)
           (printf "  ~s\n  ~s\n" phases tip)
           (and (equal? phases '((input-wait . 10000000) (render . 3000000)
                                 (vsync-wait . 2000000) (tick . 1000000)))
                (= (profile-tick-ns seq 'ns) (apply + (map cdr phases)))
                ;; every phase of the profiler's a series of the bars'
                (= (length monitor-phases) profile-phase-count)
                (for-all (lambda (p) (assq p monitor-phases))
                         (vector->list profile-phase-names))
                ;; 16 ms, its wait for input too: late past periods of
                ;; 32/3 ms
                (member seq (profile-slow-ticks 10666666))
                (not (member seq (profile-slow-ticks 10666667)))
                (not (member seq (profile-slow-ticks 16666666)))
                ;; the work by what it spent, the waits above it
                (equal? order (map index '(render tick input-wait vsync-wait)))
                ;; the kit's tooltip shows it a line each, as it is
                (equal? (ui-tooltip-lines tip) lines)
                (equal? (cadr (ui-tooltip-lines late))
                        "16 ms, late (a tick is 3 ms)")
                (= 9 (length (ui-tooltip-lines
                              "1\n2\n3\n4\n5\n6\n7\n8\n9")))))))

(check "a bar chart flags at its top the bars 'flagged says, in chart-flag"
       (let* ([ui (make-ui)] [seen '()]
              [win (apply open-window "F" 'size '(300 . 160) 'pos '(100 . 100)
                          'ui ui
                          'draw (lambda (win w h)
                                  (ui-begin! ui)
                                  (ui-bar-chart ui 'f 0 0 w h
                                                (map (lambda (i)
                                                       (cons '((chart-1 . 5))
                                                             #f))
                                                     (iota 4))
                                                10 '() #f void
                                                'flagged (lambda (i) (= i 2)))
                                  (ui-end! ui w h))
                          (ui-handlers ui))])
         (with-test-styles
          (lambda ()
            (define-style test-flags "Test"
              'ui-draw-bar-chart
              (lambda (x y w h flags bars top rules)
                (set! seen (map cadddr bars))))
            (set-style! 'test-flags)
            (invalidate! win)
            (steps 2)))
         (close-window! win)
         (steps 1)
         (equal? seen '(#f #f #t #f))))

(check "the charts' colors are colors in every style; Settings' Colors tab \
        lists none of them, and its colors still go to hue and back"
       (let ([keys (filter (lambda (k)
                             (string-prefix? "chart-" (symbol->string k)))
                           color-keys)]
             [listed (apply append (map cdr (theme 'color-groups)))])
         (and (= (length keys) 14)
              (for-all
               (lambda (s)
                 (with-style (style-name s)
                   (lambda ()
                     (and (for-all (lambda (k)
                                     (call-with-values
                                       (lambda () (color-rgba (theme k)))
                                       (lambda (r g b a) (<= 0 a 1))))
                                   keys)
                          (for-all
                           (lambda (k)
                             (let ([c (theme k)])
                               (or (not (fixnum? c))
                                   (= c (call-with-values
                                          (lambda () (color->hsl c))
                                          color-from-hsl)))))
                           listed)))))
               *styles*)
              (not (exists (lambda (k) (memq k listed)) keys)))))

(check "reload reads the source list from load.ss"
       (and (equal? (read-source-list) *schevana-sources*)
            (member "src/wm.ss" *schevana-sources*)
            #t))

(steps 2)
(check "the world still renders after all this" (begin (render-frame!) #t))

(if (zero? failures)
    (printf "all checks passed\n")
    (printf "~a check(s) FAILED\n" failures))
(exit (if (zero? failures) 0 1))
