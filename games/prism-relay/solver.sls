;;; (games prism-relay solver) — the search a player makes: follow the
;;; light, and at each mirror it reaches, try both leanings. A route is
;;; where the light goes once every mirror it reaches is decided, so the
;;; routes are the different ways a player can send the light, and their
;;; number is how much there is to search. The mirrors the light never
;;; reaches stay as they are.

(library (games prism-relay solver)
  (export prism-solve)
  (import (chezscheme)
          (games prism-relay board))

  ;; Returns two values for board start, cols wide: how many routes its
  ;; light can take, and for each route that solves it, the cells turned
  ;; from start, in reading order. Past most routes the search stops, and
  ;; the routes are #f.
  (define (prism-solve start cols most)
    (let* ([n (string-length start)] [board (string-copy start)]
           [rays (make-fxvector n 0)] [queue (make-fxvector (fx* 4 n) 0)]
           [seen (make-bytevector n 0)] [fixed (make-bytevector n 0)]
           [routes 0] [solutions '()])
      (define (turned)
        (let loop ([i (fx- n 1)] [cells '()])
          (cond [(fx< i 0) cells]
                [(char=? (string-ref board i) (string-ref start i))
                 (loop (fx- i 1) cells)]
                [else (loop (fx- i 1) (cons i cells))])))
      (let search ()
        (when (fx<= routes most)
          (let ([j (prism-trace! board cols rays queue seen fixed)])
            (if j
                (let ([t (string-ref board j)])
                  (bytevector-u8-set! fixed j 1)
                  (search)
                  (string-set! board j (prism-turned t))
                  (search)
                  (string-set! board j t)
                  (bytevector-u8-set! fixed j 0))
                (begin
                  (set! routes (fx+ routes 1))
                  (when (prism-solved? board rays)
                    (set! solutions (cons (turned) solutions))))))))
      (values (and (fx<= routes most) routes) (reverse solutions)))))
