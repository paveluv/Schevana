;;; tests/units/life.ss — Life: its kernels and its grid against a plain
;;; reference, its controls, the crew.

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
            (life-step-rows! 0 rows g next pix row-px dead cols rows)
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
            (life-step-rows! 0 rows g next pix row-px 0 cols rows)
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
         (life-step-rows! 10 27 g part pix (life-row-pixels 44) 0 72 44)
         (for-all (lambda (i)
                    (= (bytevector-u8-ref part i)
                       (if (<= (* 10 72) i (- (* 27 72) 1))
                           (bytevector-u8-ref whole i)
                           9)))
                  (iota (* 72 44)))))

(let* ([g (random-life-grid 72 44)]
       [next (make-bytevector (* 72 44) 0)]
       [pix (make-bytevector (* 4 72 44) 0)]
       [row-px (life-row-pixels 44)]
       [dead (color->pixel 'bg-0)])
  (life-step-rows! 0 44 g next pix row-px dead 72 44)
  (let ([b0 (bytes-total)])
    (do ([i 0 (fx+ i 1)]) ((fx= i 20))
      (life-step-rows! 0 44 g next pix row-px dead 72 44))
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
  (close-window! win))

;; Life's draw handler into an image, next to the cells drawn the old way:
;; bg-0 everywhere, each live cell a rectangle. Compared above the status
;; bar.
(define (life-matches-rects? s content-w content-h)
  (canvas-create! 1280 800 s)
  (let ([win (life)])
    (window-call win 'key #\h '())   ; the grid alone
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

;;; Its controls and the crew.

;; What Life's status line says at a draw: (generation running? cols rows
;; rate).
(define (life-status win)
  (let ([seen #f] [real (top-level-value 'life-status-text life-env)])
    (dynamic-wind
      (lambda ()
        (set-top-level-value! 'life-status-text
                              (lambda args
                                (set! seen args)
                                (apply real args))
                              life-env))
      (lambda ()
        (let-values ([(a drawn) (life-drawn win 1)])
          (cairo-surface-destroy a))
        seen)
      (lambda () (set-top-level-value! 'life-status-text real life-env)))))

(define (life-generation win) (car (life-status win)))

(define (life-size win)
  (let ([st (life-status win)]) (list (caddr st) (cadddr st))))

;; A press at frac of the track of win's slider id, as the mouse does it.
(define (life-slide! win id frac)
  (let ([r (ui-find (window-ref win 'ui) id)])
    (let ([x (+ (ui-region-x r) 8 (* frac (- (ui-region-w r) 16)))]
          [y (+ (ui-region-y r) (/ (ui-region-h r) 2))])
      (window-call win 'mouse-down x y 'left 1)
      (window-call win 'mouse-up x y 'left))))

(define (life-paused!)
  (let ([win (life)])
    (window-call win 'key #\space '())
    (life-size win)   ; a first draw: the panel's widgets are there
    win))

(define (life-speed! win label)
  (let ([speeds (top-level-value 'life-speeds life-env)])
    (life-slide! win 'speed
                 (/ (list-index (lambda (s) (string=? (car s) label)) speeds)
                    (- (length speeds) 1)))))

(check "Life opens as many cells as ever, 72 × 44 of 10 pixels, beside its \
        controls, which lie over it; H hides them and the grid stays as it \
        is, and a press on the button in the status line shows them again; a \
        window too narrow shows only the grid, the button off"
       (let* ([win (life-paused!)] [ui (window-ref win 'ui)]
              [press-button! (lambda ()
                               (let* ([r (ui-find ui '(life-controls button))]
                                      [x (+ (ui-region-x r)
                                            (/ (ui-region-w r) 2))]
                                      [y (+ (ui-region-y r)
                                            (/ (ui-region-h r) 2))])
                                 (window-call win 'mouse-down x y 'left 1)
                                 (window-call win 'mouse-up x y 'left)))])
         (let-values ([(w h) (window-content-size win)])
           (let* ([opened (life-size win)] [panel? (ui-find ui 'cell)])
             (window-call win 'key #\h '())
             (let* ([hidden (life-size win)] [gone? (not (ui-find ui 'cell))])
               (press-button!)
               (let ([shown (life-size win)] [back? (ui-find ui 'cell)])
                 (resize-window! win 300 h)
                 (let* ([narrow (life-size win)]
                        [none? (not (ui-find ui 'cell))])
                   (press-button!)
                   (life-size win)
                   (unless (ui-side-panel-open? ui 'life-controls)
                     (set! none? #f))
                   (close-window! win)
                   (and (equal? opened '(72 44)) panel? gone? back? none?
                        (equal? shown opened)
                        (equal? (car narrow) 30)
                        (equal? hidden opened)
                        (= w 720)))))))))

(check "Life: a new size keeps the cells that fit and seeds the new ground; \
        the old size then gets back what it had"
       (let* ([win (life-paused!)] [before (life-shown win)])
         (let-values ([(w h) (window-content-size win)])
           (resize-window! win (+ w 200) (+ h 100))
           (let* ([size (life-size win)] [grown (life-shown win)]
                  [cols (car size)] [rows (cadr size)]
                  [kept? (for-all
                          (lambda (y)
                            (for-all
                             (lambda (x)
                               (= (bytevector-u8-ref grown (+ x (* y cols)))
                                  (bytevector-u8-ref before (+ x (* y 72)))))
                             (iota 72)))
                          (iota 44))]
                  [new (let loop ([i (* 45 cols)] [n 0])
                         (if (= i (* cols rows))
                             n
                             (loop (+ i 1)
                                   (+ n (bytevector-u8-ref grown i)))))])
             (resize-window! win w h)
             (let ([again (life-shown win)])
               (close-window! win)
               (and (equal? size '(92 54)) kept? (> new 50)
                    (equal? again before)))))))

;; Life maximized at the first stop of its cell size, its controls hidden,
;; at scale s: the grid has the screen's own pixels, each cell one of them.
(define (life-one-to-one? s)
  (canvas-create! 1280 800 s)
  (let ([win (life-paused!)])
    (toggle-maximize! win)
    (life-size win)
    (life-slide! win 'cell 0)
    (window-call win 'key #\h '())
    (let*-values ([(cw ch) (window-content-size win)]
                  [(size) (life-size win)]
                  [(a seen) (life-drawn win s)])
      (let* ([gh (- ch (life-bar-height))]
             [ok (and (= (car size) (* s cw)) (= (cadr size) (* s gh))
                      (apply
                       (lambda (pixels cols rows cell ox oy)
                         (let rows-loop ([y 0])
                           (or (= y rows)
                               (and (let cols-loop ([x 0])
                                      (or (= x cols)
                                          (and (= (pixel-at a x y)
                                                  (pixmap-ref pixels x y))
                                               (cols-loop (+ x 1)))))
                                    (rows-loop (+ y 1))))))
                       seen))])
        (cairo-surface-destroy a)
        (close-window! win)
        (canvas-create! 1280 800 *host-scale*)
        ok))))

(check "Life: at the cell size's first stop, in a maximized window with its \
        controls hidden, a cell is a pixel of the screen, at 100% and 200%"
       (and (life-one-to-one? 1) (life-one-to-one? 2)))

(check "Life: every tick is a generation each tick, though the clock stands \
        still; flat out, several; at 12 a second, none till it is time"
       (let ([win (life)])
         (life-size win)
         (fluid-let ([now-ms (let ([t (now-ms)]) (lambda () t))])
           (window-call win 'tick)   ; maybe a generation: it was long ago
           (let* ([ticks (lambda (k)
                           (let ([g0 (life-generation win)])
                             (do ([i 0 (+ i 1)]) ((= i k))
                               (window-call win 'tick))
                             (- (life-generation win) g0)))]
                  [slow (ticks 3)]
                  [every (begin (life-speed! win "every tick") (ticks 5))]
                  [flat (begin (life-speed! win "flat out") (ticks 1))])
             (close-window! win)
             (printf "  ~a generations in a tick, flat out\n" flat)
             (and (= slow 0) (= every 5) (> flat 1))))))

(check "Life: a tick's generation allocates under 8 KB"
       (let ([win (life)])
         (life-size win)
         (life-speed! win "every tick")
         (window-call win 'tick)
         (let ([b0 (bytes-total)])
           (do ([i 0 (+ i 1)]) ((= i 20)) (window-call win 'tick))
           (let ([kb (/ (- (bytes-total) b0) 20 1024.0)])
             (close-window! win)
             (printf "  ~,1f KB\n" kb)
             (< kb 8)))))

(check "Life: the threads slider sets the crew, from none to one thread short \
        of the machine's"
       (let* ([win (life-paused!)] [size (crew-size)])
         (life-slide! win 'threads 0)
         (let ([least (crew-size)])
           (life-slide! win 'threads 1)
           (let ([most (crew-size)])
             (crew-size-set! size)
             (close-window! win)
             (and (= least 0) (= most (- (max 2 (host-cpu-count)) 1)))))))

(check "Life's generation on the crew equals the reference, and its seeding \
        is about 22% alive, no two rows alike"
       (let* ([cols 400] [rows 300] [n (* cols rows)]
              [g (make-bytevector n 0)] [next (make-bytevector n 0)]
              [pix (make-bytevector (* 4 n) 0)]
              [seeds (make-fxvector rows)]
              [chunk ((top-level-value 'life-chunk-rows life-env) cols)])
         (do ([y 0 (+ y 1)]) ((= y rows))
           (fxvector-set! seeds y (random 4294967296)))
         (crew-for* chunk 0 rows (top-level-value 'life-seed-rows! life-env)
                    g seeds cols)
         (let ([alive (apply + (bytevector->u8-list g))]
               [row (lambda (y)
                      (let ([r (make-bytevector cols)])
                        (bytevector-copy! g (* y cols) r 0 cols)
                        r))])
           (crew-for* chunk 0 rows life-step-rows! g next pix
                      (life-row-pixels rows) 0 cols rows)
           (and (< 0.2 (/ alive n 1.0) 0.24)
                (not (equal? (row 0) (row 1)))
                (equal? next (life-reference g cols rows))))))

(check "Life: a press draws a cell, or clears a live one, and a drag draws \
        all the way, however far the pointer jumped"
       (let* ([win (life-paused!)])
         (window-call win 'key #\c '())
         (window-call win 'mouse-down 25 25 'left 1)
         (window-call win 'mouse-move 125 25)
         (window-call win 'mouse-up 125 25 'left)
         (let ([drawn (life-shown win)])
           (window-call win 'mouse-down 25 25 'left 1)
           (window-call win 'mouse-up 25 25 'left)
           (let ([cleared (life-shown win)])
             (close-window! win)
             (and (= (apply + (bytevector->u8-list drawn)) 11)
                  (for-all (lambda (x)
                             (= 1 (bytevector-u8-ref drawn (+ x (* 2 72)))))
                           '(2 3 4 5 6 7 8 9 10 11 12))
                  (= 10 (apply + (bytevector->u8-list cleared))))))))
