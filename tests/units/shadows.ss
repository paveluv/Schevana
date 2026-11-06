;;; tests/units/shadows.ss — tiles against stacked shadows.   ; shadow

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
