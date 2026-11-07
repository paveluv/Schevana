;;; kits/px.ss — pixel art: bevels and small pictures, of boxes on whole
;;; device pixels at any scale and translation (Settings' half-size
;;; miniatures too). The recorder snaps a box's corners: logical pixel u
;;; covers the device pixels from round(u·s) to round((u+1)·s), s of them to
;;; a logical pixel (ZacOS's rule), so at 150 % a 1-pixel line is 1 or 2
;;; device pixels by turns, always in its own color.

;; n rings of 1 pixel from the outside in: the top and left in light, the
;; bottom and right in dark (light dark: raised; dark light: sunken).
;; Who owns the two off corners differs by look, a fact from each source:
;; rule motif (Xm/Draw.c:98-116): ring i's top row runs from the left
;; edge to the right less i, its left side from n down; the dark sides
;; start a pixel in and are drawn last, so a 1-pixel bevel gives its off
;; corners to the light side and a 2-pixel one stairs. Rule mac
;; (platinum.md 5.1): the light sides stop a pixel short and the dark
;; ones start a pixel in, so the off corners keep what is under them.
(define (px-bevel x y w h light dark n . rule)
  (let ([mac? (and (pair? rule) (eq? (car rule) 'mac))])
    (do ([i 0 (+ i 1)]) ((= i n))
      (if mac?
          (begin (fill-box (+ x i) (+ y i) (- w i i 1) 1 light)
                 (fill-box (+ x i) (+ y i) 1 (- h i i 1) light))
          (begin (fill-box x (+ y i) (- w i) 1 light)
                 (fill-box (+ x i) (+ y n) 1 (- h n i) light))))
    (do ([i 0 (+ i 1)]) ((= i n))
      (let ([j (if mac? i 0)])   ; the mac rule's rings are inset both ways
        (fill-box (+ x i 1) (+ y h (- i) -1) (- w i j 1) 1 dark)
        (fill-box (+ x w (- i) -1) (+ y i 1) 1 (- h i j 1) dark)))))

;; A small picture: rows of characters, a logical pixel each; roles,
;; ((char . color) ...), colors them (a key, a color, a stipple; #f
;; clear), and other characters are clear. A row's runs of one character
;; are filled as one box. With 'stretch (col . width), column col
;; repeats until the picture is width wide: a 9-slice's middle.
(define (px-bits x y rows roles . opts)
  (let ([st (plist-ref opts 'stretch #f)])
    (define (stretch row)
      (let ([col (car st)] [n (string-length row)])
        (string-append (substring row 0 col)
                       (make-string (- (cdr st) n -1) (string-ref row col))
                       (substring row (+ col 1) n))))
    (for-each
     (lambda (row j)
       (let* ([row (if st (stretch row) row)] [n (string-length row)])
         (let loop ([i 0])
           (when (< i n)
             (let* ([ch (string-ref row i)]
                    [end (let run ([k i])
                           (if (and (< k n) (char=? (string-ref row k) ch))
                               (run (+ k 1))
                               k))]
                    [color (let ([r (assv ch roles)]) (and r (cdr r)))])
               (when color (fill-box (+ x i) (+ y j) (- end i) 1 color))
               (loop end))))))
     rows (iota (length rows)))))

;; str cut with "…" until its ink fits in w (ZacOS's truncation).
(define (px-fit str w font)
  (text-fit str w font
            (lambda (s) (let-values ([(l t iw ih) (text-ink s font)]) iw))))

;; Swaps ink and paper in the rectangle, as the Lisp machines' XOR did:
;; what is drawn there shows in reverse video, in any palette. A pixel p
;; becomes ink + paper - p, a channel at a time: 255 - p, less what ink
;; and paper fall short of 255, plus what they pass it by.
(define (px-invert x y w h)
  (let* ([ink (color->pixel 'text)] [paper (color->pixel 'window-bg)]
         [k (lambda (f)   ; f of ink + paper - 255, in each channel
              (fold-left (lambda (acc s)
                           (fxior acc (fxsll (f (- (+ (fxand (fxsrl ink s) 255)
                                                      (fxand (fxsrl paper s)
                                                             255))
                                                   255))
                                             s)))
                         0 '(16 8 0)))]
         [short (k (lambda (d) (max 0 (- d))))]
         [over (k (lambda (d) (max 0 d)))])
    (invert-box x y w h (fxxor #xffffff short))
    (unless (zero? over) (add-box x y w h over))))

;;; Bitmap text: a font of cells w × h pixels, one number a character
;;; from the first on, row y's pixel x its bit w·y + x.

;; The MIT CADR's 5X5, for the names in lozenges, characters 32 to 96
;; (its small letters are its capitals): decoded from MIT System 99's
;; fonts/5x5.qfasl, Copyright (c) 1980 Massachusetts Institute of
;; Technology, BSD license (see README).
(define px-5x5
  (list 32 6 5
   '#(#x0          ; space
      #x8008208    ; !
      #x514        ; "
      #x12fd2fd2   ; #
      #x1ea1c2bc   ; $
      #x32108426   ; %
      #x2c4ac284   ; &
      #x108        ; '
      #x8104108    ; (
      #x4208204    ; )
      #x2273e722   ; *
      #x823e208    ; +
      #x4200000    ; ,
      #x3e000      ; -
      #x8000000    ; .
      #x2108420    ; /
      #xc49248c    ; 0
      #x1c20820c   ; 1
      #x3e21089c   ; 2
      #x1c89889c   ; 3
      #x1043e492   ; 4
      #x1e81e0be   ; 5
      #x1e89e09c   ; 6
      #x841083e    ; 7
      #x1c89c89c   ; 8
      #x1e83c89c   ; 9
      #x8008000    ; :
      #x4200200    ; ;
      #x10204210   ; <
      #x780780     ; =
      #x4210204    ; >
      #x410848c    ; ?
      #x3c09a89c   ; @
      #x228be89c   ; A
      #x1e89e89e   ; B
      #x3c0820bc   ; C
      #x1e92491e   ; D
      #x3e09e0be   ; E
      #x208e0be    ; F
      #x1c8b20bc   ; G
      #x228be8a2   ; H
      #x3e20823e   ; I
      #xc49043e    ; J
      #x12286292   ; K
      #x1e082082   ; L
      #x228aada2   ; M
      #x228b2aa6   ; N
      #x1c8a289c   ; O
      #x209e89e    ; P
      #x1429248c   ; Q
      #x2249e89e   ; R
      #x1e81c0bc   ; S
      #x820823e    ; T
      #x1c8a28a2   ; U
      #x85228a2    ; V
      #x22daa8a2   ; W
      #x22508522   ; X
      #x8208522    ; Y
      #x3e10843e   ; Z
      #xc10410c    ; [
      #x20408102   ; \
      #xc20820c    ; ]
      #x508        ; ^
      #x3e000000   ; _
      #x204)))     ; `

;; str in bitmap font f, (first w h glyphs), its cells' top left at x y;
;; a character it lacks is blank. Each run of a row is one box.
(define (px-bitmap-text x y str f color)
  (apply (lambda (first w h glyphs)
           (do ([i 0 (+ i 1)]) ((= i (string-length str)))
             (let* ([k (- (char->integer (string-ref str i)) first)]
                    [g (if (< -1 k (vector-length glyphs))
                           (vector-ref glyphs k)
                           0)])
               (do ([r 0 (+ r 1)]) ((= r h))
                 (let run ([c 0])
                   (when (< c w)
                     (if (fxbit-set? g (+ (* r w) c))
                         (let end ([e c])
                           (if (and (< e w) (fxbit-set? g (+ (* r w) e)))
                               (end (+ e 1))
                               (begin (fill-box (+ x (* i w) c) (+ y r)
                                                (- e c) 1 color)
                                      (run e))))
                         (run (+ c 1)))))))))
         f))

;; The CADR's lozenge: str in capitals of the 5X5 in a box 9 high with
;; pointed ends, 9 + 6 a character wide (shwarm.lisp:675-700, MIT).
(define (px-lozenge-width str) (+ 9 (* 6 (string-length str))))

(define (px-lozenge x y str color)
  (px-bits x y '("....#...."
                 "...#.#..."
                 "..#...#.."
                 ".#.....#."
                 "#.......#"
                 ".#.....#."
                 "..#...#.."
                 "...#.#..."
                 "....#....")
           (list (cons #\# color))
           'stretch (cons 4 (px-lozenge-width str)))
  (px-bitmap-text (+ x 4) (+ y 2) (string-upcase str) px-5x5 color))
