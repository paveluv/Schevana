;;; (games prism-relay board) — Prism Relay's bench: its tiles, the ways
;;; light goes between them, and the trace that follows the light from the
;;; source.
;;;
;;; A board is a string of tiles, row after row, and its width in cells:
;;;
;;;   .        clear glass
;;;   #        a wall, which stops light
;;;   *        a crystal, to be lit
;;;   O        the ring, where the light must end
;;;   > v < ^  the source, shining east, south, west or north
;;;   / \      mirrors, which turn the light
;;;   Z N      half-silvered mirrors, leaning as / and as \, which let the
;;;            light through and turn it too
;;;
;;; A mirror of either kind turns between its two leanings.

(library (games prism-relay board)
  (export prism-neighbor prism-turnable? prism-turned prism-trace!
          prism-trace prism-cell-lit? prism-tally prism-solved?
          prism-next-optic prism-optic-toward)
  (import (chezscheme))

  ;; Directions run clockwise from east: 0 east, 1 south, 2 west, 3 north.

  ;; Returns the cell beside cell i in direction d, or #f past the edge.
  (define (prism-neighbor board cols i d)
    (let ([x (fxmod i cols)])
      (case d
        [(0) (and (fx< (fx+ x 1) cols) (fx+ i 1))]
        [(1) (and (fx< (fx+ i cols) (string-length board)) (fx+ i cols))]
        [(2) (and (fx> x 0) (fx- i 1))]
        [else (and (fx>= i cols) (fx- i cols))])))

  (define (prism-turnable? c)
    (case c [(#\/ #\\ #\Z #\N) #t] [else #f]))

  ;; Returns the tile that c becomes when it is turned.
  (define (prism-turned c)
    (case c
      [(#\/) #\\]
      [(#\\) #\/]
      [(#\Z) #\N]
      [(#\N) #\Z]
      [else c]))

  ;; Returns the way light going d leaves mirror c.
  (define (prism-bounce c d)
    (case c [(#\/ #\Z) (fxxor d 3)] [else (fxxor d 1)]))

  (define (prism-source-way c)
    (case c [(#\>) 0] [(#\v) 1] [(#\<) 2] [(#\^) 3] [else #f]))

  ;; Returns the source's cell, or #f.
  (define (prism-source-at board)
    (let loop ([i 0])
      (cond [(fx= i (string-length board)) #f]
            [(prism-source-way (string-ref board i)) i]
            [else (loop (fx+ i 1))])))

  ;; The ray map has a word for each cell: its tile's code in the low byte;
  ;; then four bits for each side (east, south, west, north): lit, outgoing,
  ;; and the light's distance from the source there, in cells, modulo four;
  ;; and in the top byte, the distance at which light first reached the
  ;; cell, at most 255. A side keeps the first light that crosses it.

  ;; Follows the light from the source over board, cols wide, into rays,
  ;; working in queue (four words a cell) and seen (a byte a cell). The
  ;; light spreads in order of distance, so each cell's top byte is its
  ;; least distance. A mirror whose byte in fixed is 0 is one the light
  ;; can't pass yet; fixed #f lets it pass every mirror. Returns the first
  ;; such mirror the light reaches, or #f once the light has gone
  ;; everywhere it goes.
  (define (prism-trace! board cols rays queue seen fixed)
    (let ([n (string-length board)] [tail 0])
      (define (light! i side steps outgoing?)
        (let ([word (fxvector-ref rays i)] [shift (fx+ 8 (fx* 4 side))])
          (when (fxzero? (fxand 15 (fxsrl word shift)))
            (fxvector-set! rays i
              (fxior word
                     (fxsll (fx+ 8 (if outgoing? 4 0) (fxand steps 3)) shift)
                     (if (fxzero? (fxand word #xFFFF00))
                         (fxsll (fxmin steps 255) 24)
                         0))))))
      (define (push! i d steps)
        (let ([s (bytevector-u8-ref seen i)] [bit (fxsll 1 d)])
          (when (fxzero? (fxand s bit))
            (bytevector-u8-set! seen i (fxior s bit))
            (fxvector-set! queue tail (fxior (fxsll steps 16) (fxsll i 2) d))
            (set! tail (fx+ tail 1)))))
      (do ([i 0 (fx+ i 1)]) ((fx= i n))
        (fxvector-set! rays i (char->integer (string-ref board i)))
        (bytevector-u8-set! seen i 0))
      (let ([src (prism-source-at board)])
        (when src (push! src (prism-source-way (string-ref board src)) 0)))
      (let loop ([head 0])
        (and (fx< head tail)
             (let* ([e (fxvector-ref queue head)] [d (fxand e 3)]
                    [i (fxand (fxsrl e 2) #x3FFF)] [steps (fxsrl e 16)]
                    [j (prism-neighbor board cols i d)]
                    [t (if j (string-ref board j) #\#)])
               (light! i d steps #t)
               (if (char=? t #\#)
                   (loop (fx+ head 1))
                   (let ([far (fx+ steps 1)])
                     (light! j (fxxor d 2) far #f)
                     (case t
                       [(#\. #\*) (push! j d far) (loop (fx+ head 1))]
                       [(#\/ #\\ #\Z #\N)
                        (if (and fixed (fxzero? (bytevector-u8-ref fixed j)))
                            j
                            (begin
                              (push! j (prism-bounce t d) far)
                              (when (memv t '(#\Z #\N)) (push! j d far))
                              (loop (fx+ head 1))))]
                       [else (loop (fx+ head 1))]))))))))

  ;; Returns the ray map of board, cols wide.
  (define (prism-trace board cols)
    (let* ([n (string-length board)] [rays (make-fxvector n 0)])
      (prism-trace! board cols rays (make-fxvector (fx* 4 n) 0)
                    (make-bytevector n 0) #f)
      rays))

  ;; Whether any light crosses the cell whose ray-map word is word.
  (define (prism-cell-lit? word) (not (fxzero? (fxand word #xFFFF00))))

  ;; Returns three values: the crystals that rays lights on board, the
  ;; crystals there are, and whether light reaches the ring.
  (define (prism-tally board rays)
    (let loop ([i 0] [lit 0] [total 0] [ring? #f])
      (if (fx= i (string-length board))
          (values lit total ring?)
          (let ([on? (prism-cell-lit? (fxvector-ref rays i))])
            (case (string-ref board i)
              [(#\*) (loop (fx+ i 1) (if on? (fx+ lit 1) lit) (fx+ total 1)
                           ring?)]
              [(#\O) (loop (fx+ i 1) lit total on?)]
              [else (loop (fx+ i 1) lit total ring?)])))))

  ;; Whether rays lights every crystal of board and reaches its ring.
  (define (prism-solved? board rays)
    (let-values ([(lit total ring?) (prism-tally board rays)])
      (and ring? (fx= lit total))))

  ;; Returns the next mirror after cell from in reading order (before it,
  ;; with step -1), going around at either end, or #f on a board with none.
  (define (prism-next-optic board from step)
    (let ([n (string-length board)])
      (let loop ([k 1])
        (and (fx<= k n)
             (let ([i (fxmod (fx+ from (fx* k step)) n)])
               (if (prism-turnable? (string-ref board i))
                   i
                   (loop (fx+ k 1))))))))

  ;; Returns the mirror nearest cell from in direction d, or #f when none
  ;; lies that way. Nearest counts the cells ahead, and each cell off the
  ;; line through from twice.
  (define (prism-optic-toward board cols from d)
    (let ([x0 (fxmod from cols)] [y0 (fxquotient from cols)])
      (let loop ([i 0] [best #f] [best-score 0])
        (if (fx= i (string-length board))
            best
            (let* ([dx (fx- (fxmod i cols) x0)]
                   [dy (fx- (fxquotient i cols) y0)]
                   [ahead (case d
                            [(0) dx]
                            [(1) dy]
                            [(2) (fx- dx)]
                            [else (fx- dy)])]
                   [score (fx+ ahead (fx* 2 (fxabs (if (even? d) dy dx))))])
              (if (and (fx> ahead 0) (prism-turnable? (string-ref board i))
                       (or (not best) (fx< score best-score)))
                  (loop (fx+ i 1) i score)
                  (loop (fx+ i 1) best best-score))))))))
