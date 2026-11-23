;;; (games prism-relay generator) — the chambers, each made from its
;;; number. Chamber n's random numbers come from a seed of its own, so it is
;;; the same chamber on every machine and in every run.
;;;
;;; A chamber is built path first. The light's way runs from a source on
;;; the edge, a few clear cells at a time, to a mirror that turns it, and
;;; after the last mirror to the ring. A half-silvered mirror on the way
;;; sends a second beam off to a wall or past the edge. Crystals go on the
;;; clear cells the light crosses and walls on the cells it doesn't, and
;;; two in three of the way's mirrors are turned wrong.
;;;
;;; The solver keeps such a base only when exactly one setting of the
;;; mirrors the light can reach solves it, and when that setting takes
;;; enough turns. Then decoy mirrors go, one at a time, on the cells the
;;; solved light doesn't cross, each kept only when it gives the light more
;;; routes and leaves the solution the only one, until the routes fall in
;;; the chamber's band: at least (prism-routes-least n) and fewer than
;;; (prism-routes-least (+ n 1)). The bands rise and never overlap, so
;;; every chamber gives more to search than the one before.

(library (games prism-relay generator)
  (export prism-chamber-cols prism-chamber-rows prism-chamber-start
          prism-chamber-par prism-chamber-solution prism-most-cells
          prism-splitters-from prism-generate)
  (import (chezscheme)
          (games prism-relay board)
          (games prism-relay solver))

  ;; A chamber: its number (from 0), its size, its board as it starts, the
  ;; fewest turns that solve it, the routes its light can take, and the
  ;; cells those turns turn, in reading order.
  (define-record-type prism-chamber
    (nongenerative games-prism-relay-chamber)
    (fields number cols rows start par routes solution))

  ;; The largest bench, which the chambers grow to.
  (define prism-most-cols 12)
  (define prism-most-rows 8)
  (define prism-most-cells (* prism-most-cols prism-most-rows))

  ;; The first chamber, counting from 0, with half-silvered mirrors.
  (define prism-splitters-from 8)

  (define (prism-routes-least n) (+ 2 n (quotient (* n n) 6)))

  ;; Park and Miller's generator, as Fireflies has it: the box holds the
  ;; seed. Returns the next number in [0, n).
  (define (prism-random! r n)
    (let ([s (fxmod (fx* (unbox r) 48271) 2147483647)])
      (set-box! r s)
      (fxmod s n)))

  ;; Returns one of the list's items, drawn from r.
  (define (prism-pick r items)
    (list-ref items (prism-random! r (length items))))

  ;; Returns a board cols × rows built path first, with optics mirrors on
  ;; its way (about splitters of them half-silvered), the crystals and the
  ;; walls; or #f when the way comes to a cell from which it can't go on,
  ;; or when it was to have half-silvered mirrors and has none.
  (define (prism-build r cols rows optics splitters crystals walls)
    (call/1cc
     (lambda (give-up)
       (let* ([n (fx* cols rows)] [board (make-string n #\.)]
              ;; #f, or how light crosses the cell (h, v or x for both
              ;; ways), or fixed for a cell with a tile of its own
              [use (make-vector n #f)]
              [clear '()] [way '()] [halves 0])
         (define (draw k) (prism-random! r k))
         (define (go i d) (prism-neighbor board cols i d))
         (define (axis d) (if (even? d) 'h 'v))
         ;; Light going d may cross cell i: across an earlier beam, never
         ;; along one.
         (define (passable? i d)
           (let ([u (vector-ref use i)])
             (or (not u) (and (memq u '(h v)) (not (eq? u (axis d)))))))
         (define (pass! i d)
           (vector-set! use i (if (vector-ref use i) 'x (axis d)))
           (unless (memv i clear) (set! clear (cons i clear))))
         (define (take! i c)
           (vector-set! use i 'fixed)
           (string-set! board i c))
         ;; Returns the ways light from cell i going d can stop at a free
         ;; cell: (k . j), for k clear cells (up to 3) and then cell j.
         (define (runs i d)
           (let loop ([k 0] [i i] [found '()])
             (let ([j (go i d)])
               (if (or (not j) (fx> k 3))
                   found
                   (let ([found (if (vector-ref use j)
                                    found
                                    (cons (cons k j) found))])
                     (if (passable? j d) (loop (fx+ k 1) j found) found))))))
         ;; Crosses the k clear cells from cell i going d.
         (define (cross! i d k)
           (unless (fx= k 0)
             (let ([j (go i d)]) (pass! j d) (cross! j d (fx- k 1)))))
         ;; Returns the ways a second beam from cell i going d can end: (k
         ;; . j) for k clear cells and then a wall in free cell j, or (k .
         ;; #f) when it leaves the bench after k clear cells.
         (define (ends i d)
           (let loop ([k 0] [i i] [found '()])
             (let ([j (go i d)])
               (cond [(not j) (cons (cons k #f) found)]
                     [(fx> k 3) found]
                     [else
                      (let ([found (if (vector-ref use j)
                                       found
                                       (cons (cons k j) found))])
                        (if (passable? j d)
                            (loop (fx+ k 1) j found)
                            found))]))))
         (let* ([side (draw 4)]
                [src (case side
                       [(0) (fx* cols (draw rows))]
                       [(1) (draw cols)]
                       [(2) (fx+ (fx* cols (draw rows)) (fx- cols 1))]
                       [else (fx+ (fx* cols (fx- rows 1)) (draw cols))])])
           ;; the source shines in from the edge it sits on
           (take! src (string-ref ">v<^" side))
           (let walk ([i src] [d side] [optics optics] [splitters splitters])
             (let ([found (runs i d)])
               (when (null? found) (give-up #f))
               (let* ([run (prism-pick r found)] [j (cdr run)])
                 (cross! i d (car run))
                 (if (fx= optics 0)
                     (take! j #\O)
                     (let* ([turns (filter (lambda (t) (go j t))
                                           (list (fxmod (fx+ d 1) 4)
                                                 (fxmod (fx+ d 3) 4)))]
                            [turn (if (null? turns)
                                      (give-up #f)
                                      (prism-pick r turns))]
                            [mirror (if (fx= turn (fxxor d 3)) #\/ #\\)]
                            [through? (fxzero? (draw 2))]
                            [second (if through? turn d)]
                            [endings (if (fx< (draw optics) splitters)
                                         (ends j second)
                                         '())])
                       (set! way (cons j way))
                       (if (null? endings)
                           (begin
                             (take! j mirror)
                             (walk j turn (fx- optics 1) splitters))
                           (let ([end (prism-pick r endings)])
                             (set! halves (fx+ halves 1))
                             (take! j (if (char=? mirror #\/) #\Z #\N))
                             (cross! j second (car end))
                             (when (cdr end) (take! (cdr end) #\#))
                             (walk j (if through? d turn) (fx- optics 1)
                                   (fx- splitters 1))))))))))
         (when (and (fx> splitters 0) (fx= halves 0)) (give-up #f))
         (let ([clear (list->vector clear)])
           (when (fx< (vector-length clear) crystals) (give-up #f))
           (prism-shuffle! r clear)
           (do ([k 0 (fx+ k 1)]) ((fx= k crystals))
             (string-set! board (vector-ref clear k) #\*)))
         (let ([free (list->vector
                      (filter (lambda (i) (not (vector-ref use i))) (iota n)))])
           (prism-shuffle! r free)
           (do ([k 0 (fx+ k 1)]) ((fx= k (fxmin walls (vector-length free))))
             (take! (vector-ref free k) #\#)))
         (let ([wrong (filter (lambda (i) (not (fxzero? (draw 3)))) way)])
           (for-each (lambda (i)
                       (string-set! board i
                                    (prism-turned (string-ref board i))))
                     (if (null? wrong) (list (car way)) wrong)))
         board))))

  ;; Shuffles vector v in place, drawing from r.
  (define (prism-shuffle! r v)
    (do ([m (fx- (vector-length v) 1) (fx- m 1)]) ((fx<= m 0))
      (let* ([j (prism-random! r (fx+ m 1))] [x (vector-ref v j)])
        (vector-set! v j (vector-ref v m))
        (vector-set! v m x))))

  ;; Returns the cells of board, cols wide, where a decoy may go: clear
  ;; cells that the light doesn't cross once the solution's cells are
  ;; turned.
  (define (prism-decoy-cells board cols solution)
    (let ([solved (string-copy board)])
      (for-each (lambda (i)
                  (string-set! solved i (prism-turned (string-ref solved i))))
                solution)
      (let ([rays (prism-trace solved cols)])
        (filter (lambda (i)
                  (and (char=? (string-ref board i) #\.)
                       (not (prism-cell-lit? (fxvector-ref rays i)))))
                (iota (string-length board))))))

  ;; Returns chamber n, which grows with n: its bench, the mirrors on its
  ;; way, its crystals and walls, and, from prism-splitters-from on, its
  ;; half-silvered mirrors.
  (define (prism-generate n)
    (let* ([r (box (fx+ 1 (fxmod (fx+ (fx* n 1000003) 7) 2147483646)))]
           [cols (fxmin prism-most-cols (fx+ 5 (fxquotient n 4)))]
           [rows (fxmin prism-most-rows (fx+ 4 (fxquotient n 6)))]
           [optics (fxmin 16 (fx+ 1 (fxquotient n 2)))]
           [splitters (if (fx< n prism-splitters-from)
                          0
                          (fxmin 3 (fx+ 1 (fxquotient
                                           (fx- n prism-splitters-from) 10))))]
           [crystals (fxmin 10 (fx+ 1 (fxquotient n 3)))]
           [walls (fxmin 10 (fxquotient n 3))]
           [least (prism-routes-least n)]
           [most (fx- (prism-routes-least (fx+ n 1)) 1)]
           [par-least (fxmax 1 (fxquotient optics 2))]
           [decoys (if (fx> splitters 0) "/\\/\\ZN" "/\\")])
      (let build ()
        (let ([board (prism-build r cols rows optics splitters crystals
                                  walls)])
          (if (not board)
              (build)
              (let-values ([(routes solutions) (prism-solve board cols most)])
                (if (not (and routes (fx= 1 (length solutions))
                              (fx>= (length (car solutions)) par-least)))
                    (build)
                    (let ([solution (car solutions)]
                          [cells (list->vector
                                  (prism-decoy-cells board cols
                                                     (car solutions)))])
                      (prism-shuffle! r cells)
                      (let climb ([k 0] [routes routes])
                        (cond
                          [(fx>= routes least)
                           (make-prism-chamber n cols rows board
                                               (length solution) routes
                                               solution)]
                          [(fx= k (vector-length cells)) (build)]
                          [else
                           (let ([i (vector-ref cells k)])
                             (string-set! board i
                               (string-ref decoys
                                 (prism-random! r (string-length decoys))))
                             (let-values ([(more solutions)
                                           (prism-solve board cols most)])
                               (if (and more (fx> more routes)
                                        (equal? solutions (list solution)))
                                   (climb (fx+ k 1) more)
                                   (begin
                                     (string-set! board i #\.)
                                     (climb (fx+ k 1) routes)))))])))))))))))
