;;; tests/units/prism-relay.ss — Prism Relay, a game: its light, the
;;; search a player makes, the chambers it makes from their numbers, and
;;; its window's keys, mouse and frames.

;; Prism Relay's own names, pr:prism-trace and the rest (tests/reach.ss):
;; the app's, in (games prism-relay), and its parts', in games/prism-relay/.
(for-each (lambda (lib) (test-library lib 'pr:))
          '((games prism-relay board) (games prism-relay solver)
            (games prism-relay generator) (games prism-relay glass)
            (games prism-relay)))

;; Returns a chamber made by hand from its rows, cols wide, with the
;; solution and par given.
(define (pr-chamber solution . rows)
  (pr:make-prism-chamber 0 (string-length (car rows)) (length rows)
                         (apply string-append rows) (length solution) 0
                         solution))

;; Returns the board with the cells turned.
(define (pr-turned board cells)
  (let ([b (string-copy board)])
    (for-each (lambda (i) (string-set! b i (pr:prism-turned (string-ref b i))))
              cells)
    b))

(define (pr-solved? board cols)
  (pr:prism-solved? board (pr:prism-trace board cols)))

;; Returns what f gives for each of items, called in their order (map
;; may call it in any order).
(define (pr-in-order f items)
  (let loop ([items items] [given '()])
    (if (null? items)
        (reverse given)
        (loop (cdr items) (cons (f (car items)) given)))))

;; Steps the world until (ready?) holds, at most most steps; returns
;; whether it held.
(define (pr-steps-until ready? most)
  (let loop ([k 0])
    (cond [(ready?) #t]
          [(= k most) #f]
          [else (steps 1) (loop (+ k 1))])))

;; Opens a window and waits for its first chamber to be built.
(define (pr-open)
  (let ([win (pr:prism-relay)])
    (pr-steps-until (lambda () (window-ref win 'board)) 500)
    win))

;; Opens a window on a chamber made by hand.
(define (pr-open-on chamber)
  (let ([win (pr-open)])
    (pr:prism-start! win chamber)
    win))

;; Turns the mirrors of the solution of the chamber the window shows.
(define (pr-solve! win)
  (for-each (lambda (i) (pr:prism-turn! win i))
            (pr:prism-chamber-solution
             (hashtable-ref (window-ref win 'chambers)
                            (window-ref win 'chamber) #f))))

;; Returns the middle of cell i of the window's bench, in its content's
;; logical pixels.
(define (pr-cell-middle win i)
  (let*-values ([(w h) (window-content-size win)]
                [(cols) (window-ref win 'cols)]
                [(x y cell foot) (pr:prism-layout w h cols
                                                  (window-ref win 'rows))])
    (values (exact (floor (+ x (* cell (+ (mod i cols) 1/2)))))
            (exact (floor (+ y (* cell (+ (quotient i cols) 1/2))))))))

;; Returns the channel at shift (16 for red, 8 for green) of the window's
;; picture at (dx, dy) cells from the middle of cell i.
(define (pr-channel win i shift dx dy)
  (let*-values ([(w h) (window-content-size win)]
                [(cx cy) (pr-cell-middle win i)]
                [(x y cell foot) (pr:prism-layout w h (window-ref win 'cols)
                                                  (window-ref win 'rows))])
    (let ([pic (image w h 1 (lambda () (pr:prism-draw win w h)))])
      (fxand 255 (fxsrl (pixel-at pic (exact (floor (+ cx (* dx cell))))
                                  (exact (floor (+ cy (* dy cell)))))
                        shift)))))

(define (pr-green win i) (pr-channel win i 8 0 0))

;;; ------------------------------------------------------------ the light

(check "Light leaves the source the way it faces, turns at mirrors, goes \
        both ways at a half-silvered mirror, and stops at the ring and at \
        the bench's edge; a turned mirror sends it elsewhere"
  (let* ([board (string-append ">.\\.." "..*.#" "..N.O")]
         [lit (lambda (rays)
                (filter (lambda (i) (pr:prism-cell-lit? (fxvector-ref rays i)))
                        (iota (string-length board))))]
         [turned (pr-turned board '(2))])
    (let-values ([(on total ring?) (pr:prism-tally board
                                                   (pr:prism-trace board 5))]
                 [(on2 total2 ring2?) (pr:prism-tally
                                       turned (pr:prism-trace turned 5))])
      (and (equal? (lit (pr:prism-trace board 5)) '(0 1 2 7 12 13 14))
           (equal? (list on total ring?) '(1 1 #t))
           (pr-solved? board 5)
           (equal? (lit (pr:prism-trace turned 5)) '(0 1 2))
           (equal? (list on2 total2 ring2?) '(0 1 #f))))))

(check "A wall stops light: the ray map lights the cell before it, going \
        out east at distance 1 and in from the west, and not the wall"
  (let ([rays (pr:prism-trace ">.#." 4)])
    (and (= (fxvector-ref rays 0)
            (fxior (char->integer #\>) (fxsll (+ 8 4 0) 8)))
         (= (fxvector-ref rays 1)
            (fxior (char->integer #\.) (fxsll (+ 8 4 1) 8) (fxsll (+ 8 1) 16)
                   (fxsll 1 24)))
         (= (fxvector-ref rays 2) (char->integer #\#))
         (= (fxvector-ref rays 3) (char->integer #\.)))))

(check "Light crossing a crystal twice lights it once, each crossing keeps \
        its own distance on its sides, and the cell keeps the nearer"
  (let* ([board (string-append "...." ">.*\\" "...." "..\\/")]
         [rays (pr:prism-trace board 4)]
         [word (fxvector-ref rays 6)]
         [leg (lambda (side) (fxand 15 (fxsrl word (+ 8 (* 4 side)))))])
    (let-values ([(on total ring?) (pr:prism-tally board rays)])
      (and (= on 1) (= total 1)
           ;; east, going out at 2; south, coming in at 8; west, coming
           ;; in at 2; north, going out at 8
           (equal? (map leg '(0 1 2 3)) '(14 8 10 12))
           (= 2 (fxsrl word 24))))))

;;; ------------------------------------------------------------ the search

(check "The search counts the routes the light can take as the mirrors it \
        reaches turn, finds the one setting that solves, and stops past \
        the routes it is allowed"
  (let ([board (string-append ">./.." "..*.#" "..Z.O")])
    (let-values ([(routes solutions) (pr:prism-solve board 5 100)]
                 [(cut cut-solutions) (pr:prism-solve board 5 2)])
      (and (= routes 3) (equal? solutions '((2 12)))
           (not cut)))))

;;; ------------------------------------------------------------ the chambers

(define pr-chambers (map pr:prism-generate (iota 30)))

(check "A chamber is the same chamber each time it is made from its number"
  (for-all (lambda (n)
             (equal? (pr:prism-chamber-start (pr:prism-generate n))
                     (pr:prism-chamber-start (list-ref pr-chambers n))))
           '(0 7 16 29)))

(check "Chambers 1 to 30 each start unsolved, have exactly one setting of \
        the mirrors the light reaches that solves them, which their \
        solution's turns make in par turns, and each gives the light more \
        routes than the one before, within its band"
  (let loop ([n 0] [cs pr-chambers] [before 0])
    (or (null? cs)
        (let* ([c (car cs)] [board (pr:prism-chamber-start c)]
               [cols (pr:prism-chamber-cols c)]
               [solution (pr:prism-chamber-solution c)])
          (let-values ([(routes solutions) (pr:prism-solve board cols 100000)])
            (and (= routes (pr:prism-chamber-routes c))
                 (<= (pr:prism-routes-least n) routes)
                 (< routes (pr:prism-routes-least (+ n 1)))
                 (> routes before)
                 (equal? solutions (list solution))
                 (= (pr:prism-chamber-par c) (length solution))
                 (not (pr-solved? board cols))
                 (pr-solved? (pr-turned board solution) cols)
                 (loop (+ n 1) (cdr cs) routes)))))))

(check "The bench grows from 5 x 4 cells, never shrinking, to 12 x 8"
  (let ([sizes (map (lambda (c) (cons (pr:prism-chamber-cols c)
                                      (pr:prism-chamber-rows c)))
                    pr-chambers)])
    (and (equal? (car sizes) '(5 . 4))
         (equal? (car (last-pair sizes)) '(12 . 8))
         (let loop ([s sizes])
           (or (null? (cdr s))
               (and (<= (caar s) (caadr s)) (<= (cdar s) (cdadr s))
                    (loop (cdr s))))))))

(check "No chamber before prism-splitters-from has a half-silvered mirror, \
        and from it on, the solved light of each crosses one"
  (for-all
   (lambda (c n)
     (let* ([board (pr:prism-chamber-start c)]
            [solved (pr-turned board (pr:prism-chamber-solution c))]
            [rays (pr:prism-trace solved (pr:prism-chamber-cols c))]
            [halves (filter (lambda (i) (memv (string-ref board i) '(#\Z #\N)))
                            (iota (string-length board)))])
       (if (< n pr:prism-splitters-from)
           (null? halves)
           (exists (lambda (i) (pr:prism-cell-lit? (fxvector-ref rays i)))
                   halves))))
   pr-chambers (iota (length pr-chambers))))

;;; ------------------------------------------------------------ the window

(check "A window opens on chamber 1 once it is built, builds the next \
        meanwhile, records a solved chamber's turns, and Enter opens the \
        next at once"
  (let ([win (pr-open)])
    (let ([c (hashtable-ref (window-ref win 'chambers) 0 #f)])
      (let ([opened (and c (= 0 (window-ref win 'chamber))
                         (equal? (window-ref win 'board)
                                 (pr:prism-chamber-start c))
                         (= 0 (window-ref win 'turns))
                         (not (window-ref win 'solved?))
                         (pr:prism-turnable?
                          (string-ref (window-ref win 'board)
                                      (window-ref win 'selected))))])
        (pr-steps-until
         (lambda () (hashtable-ref (window-ref win 'chambers) 1 #f)) 500)
        (pr-solve! win)
        (let ([solved (and (window-ref win 'solved?)
                           (= (hashtable-ref (window-ref win 'best) 0 #f)
                              (pr:prism-chamber-par c)))])
          (window-call win 'key 'return '())
          (let ([ok (and opened solved (= 1 (window-ref win 'chamber))
                         (= 1 (window-ref win 'reached))
                         (window-ref win 'board)
                         (not (window-error win)))])
            (close-window! win)
            ok))))))

(check "Arrows select the nearest mirror that way, Tab and Shift+Tab go in \
        reading order, and Space and Enter turn the mirror selected"
  (let* ([win (pr-open-on (pr-chamber '() "/.\\.." ">...." "..Z./"))]
         [key (lambda (k . mods)
                (window-call win 'key k mods)
                (window-ref win 'selected))])
    ;; each key in turn, after the first selection
    (let ([moves (cons (window-ref win 'selected)
                       (pr-in-order (lambda (k) (apply key k))
                                    '((right) (down) (right) (left) (up)
                                      (tab) (tab shift) (tab) (tab)
                                      (tab))))])
      (key #\space)
      (let ([turned (string-ref (window-ref win 'board) 0)])
        (key 'return)
        (let ([ok (and (equal? moves '(0 2 12 14 12 2 12 2 12 14 0))
                       (char=? turned #\\)
                       (char=? (string-ref (window-ref win 'board) 0) #\/)
                       (= 2 (window-ref win 'turns)))])
          (close-window! win)
          ok)))))

(check "The mouse over a mirror lights its mount and selects it, and off \
        the mirrors lights none; a click turns the mirror under it"
  (let ([win (pr-open-on (pr-chamber '() "/.\\.." ">...." "..Z./"))])
    (define (move i)
      (let-values ([(x y) (pr-cell-middle win i)])
        (window-call win 'mouse-move x y)
        (list (window-ref win 'hover) (window-ref win 'selected))))
    (let* ([over (move 14)] [off (move 6)] [seen (list over off)])
      (let-values ([(x y) (pr-cell-middle win 12)])
        (window-call win 'mouse-down x y 'left 1))
      (let ([ok (and (equal? seen '((14 14) (-1 14)))
                     (char=? (string-ref (window-ref win 'board) 12) #\N)
                     (= 1 (window-ref win 'turns)))])
        (close-window! win)
        ok))))

(check "A turned mirror swings for some frames while the GPU keeps the old \
        light, then the new light shows; once solved, the flourish runs \
        along it and ends"
  (let ([win (pr-open-on (pr-chamber '(2) ">./" "..." "..*" "..O"))])
    (let ([dark (pr-green win 5)])
      (pr:prism-turn! win 2)
      (let* ([swinging (and (window-ref win 'solved?)
                            (= 2 (window-ref win 'swing-cell))
                            (< (pr-green win 5) (+ dark 40)))]
             [settled (pr-steps-until
                       (lambda () (< (window-ref win 'swing-cell) 0)) 300)]
             [lit (> (pr-green win 5) (+ dark 80))]
             [running? #f]
             [ended (pr-steps-until
                     (lambda ()
                       (let ([surge (window-ref win 'surge)])
                         (when (< -1.0 surge 1000.0) (set! running? #t))
                         (= surge 1000.0)))
                     600)])
        (let ([ok (and swinging settled lit running? ended
                       (not (window-error win)))])
          (close-window! win)
          ok)))))

(check "The ring glows weakly while the light reaches it with a crystal \
        still dark, and blooms once the chamber is solved"
  ;; red, which the light has little of, a little past the ring's middle
  ;; on the side away from the light
  (let ([dark (pr-open-on (pr-chamber '() ">.O" "..*"))]
        [solved (pr-open-on (pr-chamber '(2) ">./" "..." "..*" "..O"))])
    (pr:prism-turn! solved 2)
    (pr-steps-until (lambda () (= 1000.0 (window-ref solved 'surge))) 600)
    (window-set! dark 'phase 0.0)
    (window-set! solved 'phase 0.0)
    (let* ([weak (pr-channel dark 2 16 0.09 0)]
           [bloom (pr-channel solved 11 16 0 0.09)]
           [ok (and (not (window-ref dark 'solved?))
                    (= -1 (window-ref dark 'selected))
                    (window-ref solved 'solved?)
                    (> bloom (+ weak 60)))])
      (close-window! dark)
      (close-window! solved)
      ok)))

(check "Once a chamber is solved, a click anywhere opens the next, and a \
        click on a chamber's dot goes back to it"
  (let ([win (pr-open-on (pr-chamber '(2) ">./" "..." "..*" "..O"))])
    (let-values ([(x y) (pr-cell-middle win 2)])
      (window-call win 'mouse-down x y 'left 1))
    (let ([solved (window-ref win 'solved?)])
      (let-values ([(x y) (pr-cell-middle win 9)])
        (window-call win 'mouse-down x y 'left 1))
      (let ([next (window-ref win 'chamber)])
        (let*-values ([(w h) (window-content-size win)]
                      [(first last gap) (pr:prism-dots win w)])
          (window-call win 'mouse-down
                       (exact (floor (+ 14 (* gap (- 0 first)) (/ gap 2))))
                       (exact (floor (+ 9 (/ (font-line-height 'ui-small) 2))))
                       'left 1))
        (let ([ok (and solved (= next 1) (= 0 (window-ref win 'chamber))
                       (= 1 (window-ref win 'reached)))])
          (close-window! win)
          ok)))))

(check "R starts the chamber over, and [ ], Page Up and Page Down go among \
        the chambers reached and no further"
  (let ([win (pr-open)])
    (define (key k) (window-call win 'key k '()) (window-ref win 'chamber))
    (pr-solve! win)
    (key 'return)
    (pr-steps-until (lambda () (window-ref win 'board)) 500)
    (pr-solve! win)
    (key 'return)
    (pr-steps-until (lambda () (window-ref win 'board)) 500)
    (let* ([start (string-copy (window-ref win 'board))]
           [optic (window-ref win 'selected)])
      (pr:prism-turn! win optic)
      (let* ([turned (= 1 (window-ref win 'turns))]
             [reset (begin (key #\r)
                           (and (= 0 (window-ref win 'turns))
                                (equal? start (window-ref win 'board))))]
             [path (pr-in-order key
                                (list #\[ 'page-up #\[ #\] 'page-down #\]))])
        (let ([ok (and turned reset (equal? path '(1 0 0 1 2 2))
                       (= 2 (window-ref win 'reached)))])
          (close-window! win)
          ok)))))

(check "Each window has its own bench, and closing one stops the chamber \
        it is building"
  (let* ([a (pr-open)] [b (pr-open)]
         [board (string-copy (window-ref b 'board))])
    (pr:prism-turn! a (window-ref a 'selected))
    (let ([apart (and (= 1 (window-ref a 'turns)) (= 0 (window-ref b 'turns))
                      (equal? board (window-ref b 'board)))])
      (pr:prism-go! b 40)
      (let ([building (window-ref b 'building)])
        (close-window! a)
        (close-window! b)
        (and apart building (not (memq building (procs))))))))
