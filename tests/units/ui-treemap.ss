;;; tests/units/ui-treemap.ss — the kit's treemap ((schevana kits ui)),
;;; tested by itself.

;; A tree of (label value child ...): a root of 100, a at 60 with two
;; children, one of them with a child of its own, b at 30 and c at 10.
(define ui-treemap-test-tree
  '("root" 100
    ("a" 60 ("a1" 40 ("a1x" 40)) ("a2" 20))
    ("b" 30)
    ("c" 10)))

;; Twelve children, 12 down to 1, for the boxes' shapes.
(define ui-treemap-test-many
  (cons* "many" 78 (map (lambda (i) (list (format "n~a" i) (- 12 i)))
                        (iota 12))))

(define ui-treemap-test-picked #f)
(define ui-treemap-test-win
  (test-kit-window "Treemap"
    (lambda (ui w h)
      (ui-treemap ui 't 0 0 400 300 ui-treemap-test-tree car cadr cddr
                  'tip (lambda (node) (format "~a: ~a" (car node) (cadr node)))
                  'on-pick (lambda (node)
                             (set! ui-treemap-test-picked (car node))))
      (ui-treemap ui 'many 0 300 400 300 ui-treemap-test-many car cadr cddr))
    '(400 . 600)))
(steps 2)

(define (ui-treemap-test-box id . path)
  (ui-find (window-ref ui-treemap-test-win 'ui) (list id 'box path)))

;; Returns a region as (x y w h).
(define (ui-treemap-test-rect r)
  (list (ui-region-x r) (ui-region-y r) (ui-region-w r) (ui-region-h r)))

;; Whether rect r's area is share of room's, to within its rounding: a
;; pixel along each edge.
(define (ui-treemap-test-share? r share room)
  (<= (abs (- (* (ui-region-w r) (ui-region-h r)) (* share room)))
      (+ (ui-region-w r) (ui-region-h r))))

;; Whether rect a lies within (x y w h).
(define (ui-treemap-test-within? a x y w h)
  (and (>= (ui-region-x a) x) (>= (ui-region-y a) y)
       (<= (+ (ui-region-x a) (ui-region-w a)) (+ x w))
       (<= (+ (ui-region-y a) (ui-region-h a)) (+ y h))))

;; Whether no two of rects overlap.
(define (ui-treemap-test-apart? rects)
  (let loop ([rs rects])
    (or (null? rs)
        (and (for-all
              (lambda (b)
                (let ([a (car rs)])
                  (or (<= (+ (ui-region-x a) (ui-region-w a)) (ui-region-x b))
                      (<= (+ (ui-region-x b) (ui-region-w b)) (ui-region-x a))
                      (<= (+ (ui-region-y a) (ui-region-h a)) (ui-region-y b))
                      (<= (+ (ui-region-y b) (ui-region-h b))
                          (ui-region-y a)))))
              (cdr rs))
             (loop (cdr rs))))))

(check "a treemap gives each child of the root its share of the room under \
        the root's strip, as boxes within it that don't overlap, each with \
        its tooltip"
       (let* ([root (ui-treemap-test-box 't)] [a (ui-treemap-test-box 't "a")]
              [b (ui-treemap-test-box 't "b")] [c (ui-treemap-test-box 't "c")]
              [top (and root (+ (ui-region-h root) 2))]
              [room (and root (* 400 (- 300 top)))])
         (printf "  ~s\n" (map (lambda (r) (and r (ui-treemap-test-rect r)))
                               (list root a b c)))
         (and root a b c
              (= (ui-region-w root) 400)
              (ui-treemap-test-share? a 0.6 room)
              (ui-treemap-test-share? b 0.3 room)
              (ui-treemap-test-share? c 0.1 room)
              (for-all (lambda (r) (ui-treemap-test-within? r 0 top 400 300))
                       (list a b c))
              (ui-treemap-test-apart? (list a b c))
              (equal? (ui-region-tip a) "a: 60"))))

(check "a child's children lie inside it, under its name, as their shares \
        of its room; a third level is left out"
       (let* ([a (ui-treemap-test-box 't "a")]
              [a1 (ui-treemap-test-box 't "a" "a1")]
              [a2 (ui-treemap-test-box 't "a" "a2")]
              [hh (ui-treemap-header-height)]
              [x (+ (ui-region-x a) 2)] [y (+ (ui-region-y a) hh)]
              [w (- (ui-region-w a) 4)] [h (- (ui-region-h a) hh 2)])
         (and a1 a2
              (ui-treemap-test-within? a1 x y w h)
              (ui-treemap-test-within? a2 x y w h)
              (ui-treemap-test-apart? (list a1 a2))
              (ui-treemap-test-share? a1 2/3 (* w h))
              (not (ui-treemap-test-box 't "a" "a1" "a1x")))))

(check "the boxes come out near squares: none is three times as long as it \
        is wide"
       (let ([rects (map (lambda (i) (ui-treemap-test-box 'many
                                                          (format "n~a" i)))
                         (iota 12))])
         (printf "  ~s\n" (map (lambda (r)
                                 (and r (list (ui-region-w r)
                                              (ui-region-h r))))
                               rects))
         (and (for-all (lambda (r) r) rects)
              (ui-treemap-test-apart? rects)
              (for-all (lambda (r)
                         (let ([w (ui-region-w r)] [h (ui-region-h r)])
                           (< (max (/ w h) (/ h w)) 3)))
                       rects))))

;; Presses box path of 't near its top left, on its name, which its
;; children lie under.
(define (ui-treemap-test-press! . path)
  (let ([r (apply ui-treemap-test-box 't path)])
    (let-values ([(cx cy cw ch) (content-rect ui-treemap-test-win)])
      (let ([x (+ cx (ui-region-x r) 6)] [y (+ cy (ui-region-y r) 4)])
        (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                 `(mouse-up ,x ,y left))
        (steps 1)))))

(check "a press on a box makes it the root shown and tells the app; a \
        press on the root's strip goes back out"
       (begin
         (ui-treemap-test-press! "a")
         (steps 1)
         (let ([strip (ui-treemap-test-box 't "a")]
               [child (ui-treemap-test-box 't "a" "a1")]
               [grandchild (ui-treemap-test-box 't "a" "a1" "a1x")]
               [gone (ui-treemap-test-box 't "b")])
           (ui-treemap-test-press! "a")
           (steps 1)
           (and (equal? ui-treemap-test-picked "a")
                strip (= (ui-region-w strip) 400) (= (ui-region-y strip) 0)
                child (> (ui-region-w child) 200)
                grandchild
                (not gone)
                (ui-treemap-test-box 't "b")
                (= (ui-region-w (ui-treemap-test-box 't)) 400)))))
