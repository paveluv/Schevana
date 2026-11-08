;;; tests/units/primitives.ss — the shared drawing primitives: stipples, ink,
;;; crisp fonts, pixel art, glyphs; and the core's that keep C away from the
;;; folders.

;;; shared drawing primitives: stipples, ink, crisp fonts, pixel art,
;;; glyphs

(for-each close-window! (windows))
(reset-theme!)

(define gray-light-dark
  '((#xff808080 . #\.) (#xffffffff . #\L) (#xff000000 . #\D)))

;; A bevel on gray in an 8 × 8 image at 100 %.
(define (bevel-rows h n . rule)
  (pixel-rows (image 8 8 1 (lambda ()
                             (fill-box 0 0 8 8 #x808080)
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
                              (fill-box 0 0 120 90 #x808080)
                              (with-translation (0.37 0.61)
                                (px-bevel 3 2 17 11 #xffffff #x000000 2)
                                (px-bevel 25 3 13 9 #x000000 #xffffff 2 'mac)
                                (stroke-box 41 4 9 7 #xcc3333)
                                (px-bits 3 20 '("aab.c" "abbcc" ".c.ba")
                                         pixel-art-roles)
                                (px-bits 20 20 '("abc" "bcb" "cba")
                                         pixel-art-roles
                                         'stretch '(1 . 11)))))])
            (for-all (lambda (row) (not (memv #\# (string->list row))))
                     (pixel-rows img (append gray-light-dark
                                             '((#xffcc3333 . #\c)))))))
        '(1.25 1.5 1.75)))
(check "px-bits stretches its column to the width and skips clear cells"
       (equal? (pixel-rows (image 8 2 1
                                  (lambda ()
                                    (fill-box 0 0 8 2 #x808080)
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
                                              (fill-box 0 0 w h st))))
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
                   (void)
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
                                [(eq? (= (pixel-at (screen-picture) x y) ink)
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
                                        (fill-box 0 0 120 20 #x808080)
                                        (thunk))))])
         (zero? (max-diff
                 (at (lambda ()
                       (do ([i 0 (+ i 1)]) ((= i 2400))
                         (let ([u (mod i 120)] [v (quotient i 120)])
                           (fill-box u v 1 1 (if (even? (+ u v))
                                                 #x000000
                                                 #xffffff))))))
                 (at (lambda ()
                       (fill-box 0 0 120 20
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

(check "font-descent is the font's"
       (and (= (font-descent 'ui) (vector-ref (font-metrics 'ui) 1))
            (> (font-descent 'ui) 0)))

;; How many pixels of text drawn on white are neither white nor black.
(define (gray-pixels font)
  (let ([img (image 120 30 1 (lambda ()
                               (fill-box 0 0 120 30 #xffffff)
                               (draw-text 4 4 "Crisp text" #x000000 font)))])
    (apply + (map (lambda (row) (length (filter (lambda (ch) (char=? ch #\#))
                                                (string->list row))))
                  (pixel-rows img '((#xffffffff . #\.) (#xff000000 . #\k)))))))
(check "a crisp font is its own record and draws no antialiased pixel"
       (let ([crisp (font "DejaVu Sans" 12 'crisp)]
             [plain (font "DejaVu Sans" 12)])
         (and (not (eq? crisp plain)) (eq? crisp (font "DejaVu Sans" 12 'crisp))
              (zero? (gray-pixels crisp)) (> (gray-pixels plain) 0))))

(check "px-fit cuts until the ink fits"
       (let ([s (px-fit "A rather long window title" 60 'ui)])
         (and (string-suffix? "…" s)
              (let-values ([(l t w h) (text-ink s 'ui)]) (<= w 60)))))

;; Each window glyph and triangle inks inside its box and nowhere else.
(check "ui-draw-glyph's window glyphs and triangles ink their box only"
       (for-all
        (lambda (name)
          (let ([rows (pixel-rows
                       (image 24 24 1
                              (lambda ()
                                (fill-box 0 0 24 24 #x808080)
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
    (picture-free! img)
    ps))

(define (same-drawing? w h s a b)
  (let* ([ia (image w h s a)] [ib (image w h s b)] [d (max-diff ia ib)])
    (picture-free! ia)
    (picture-free! ib)
    (zero? d)))

(check "invert-box takes each pixel from a sum, white by default; add-box \
        adds; with a pattern, its clear pixels are left alone; and \
        drawing covers again after each"
       (and (equal? (pixels-of 4 4 1
                               (lambda ()
                                 (fill-box 0 0 4 4 #x204060)
                                 (invert-box 0 0 4 4))
                               '(1 1))
                    '(#xffdfbf9f))
            (equal? (pixels-of 4 4 1
                               (lambda ()
                                 (fill-box 0 0 4 4 #x204060)
                                 (invert-box 0 0 4 4 #x808080))
                               '(1 1))
                    '(#xff604020))
            (equal? (pixels-of 4 4 1
                               (lambda ()
                                 (fill-box 0 0 4 4 #x102030)
                                 (add-box 0 0 4 4 #x010203))
                               '(1 1))
                    '(#xff112233))
            (equal? (pixels-of 4 2 1
                               (lambda ()
                                 (fill-box 0 0 4 2 #x204060)
                                 (invert-box 0 0 4 2
                                             (stipple #xffffff #f "#.")))
                               '(0 0) '(1 0))
                    '(#xffdfbf9f #xff204060))
            (equal? (pixels-of 4 4 1
                               (lambda ()
                                 (fill-box 0 0 4 4 #x204060)
                                 (invert-box 0 0 4 4)
                                 (fill-box 0 0 4 4 #x000000))
                               '(1 1))
                    '(#xff000000))))

(check "draw-scale says how many device pixels a logical one is where we draw"
       (let ([seen '()])
         (picture-free!
          (image 8 8 2
                 (lambda ()
                   (set! seen (cons (draw-scale) seen))
                   (with-scale (1/2)
                     (set! seen (cons (draw-scale) seen)))
                   (set! seen (cons (draw-scale) seen)))))
         (equal? seen '(2.0 1.0 2.0))))

(check "with-turn turns what it draws clockwise on the screen, \
        then no more"
       (same-drawing? 10 10 1
                      (lambda ()
                        (fill-box 0 0 10 10 #xffffff)
                        (with-translation (5 5)
                          (with-turn ((/ pi 2)) (fill-box 0 0 4 2 #x000000))
                          (fill-box 0 -5 1 1 #x000000)))
                      (lambda ()
                        (fill-box 0 0 10 10 #xffffff)
                        (fill-box 3 5 2 4 #x000000)
                        (fill-box 5 0 1 1 #x000000))))

;; A pixel's channel, by its shift: blue 0, green 8, red 16.
(define (channel-of p shift) (fxand (fxsrl p shift) 255))

(check "gradients are colors: a linear one runs from its first color to its \
        last by way of those between, evenly; a radial one out from its \
        center"
       (let ([ps (pixels-of 100 20 1
                            (lambda ()
                              (fill-box 0 0 100 20
                                        (linear-gradient 0 0 100 0
                                                         #x000000 #xff0000
                                                         #x000000)))
                            '(1 10) '(25 10) '(50 10) '(75 10) '(98 10))]
             [qs (pixels-of 100 100 1
                            (lambda ()
                              (fill-circle 50 50 40
                                           (radial-gradient 50 50 40
                                                            #x00ff00 #x000000)))
                            '(50 50) '(70 50) '(88 50) '(99 99))])
         (let ([red (map (lambda (p) (channel-of p 16)) ps)]
               [green (map (lambda (p) (channel-of p 8)) qs)])
           (and (< (car red) 10) (< 110 (cadr red) 145) (> (caddr red) 245)
                (< 110 (cadddr red) 145) (< (list-ref red 4) 10)
                (> (car green) 245) (< 110 (cadr green) 145)
                (< (caddr green) 20)
                (= 0 (cadddr qs))))))

(check "fill-gradient and fill-glow are fills of a gradient"
       (and (for-all
             (lambda (dir radius)
               (same-drawing?
                80 60 1.5
                (lambda ()
                  (fill-gradient 5 5 70 50 'desktop-top 'desktop-bottom dir
                                 radius))
                (lambda ()
                  (fill-box 5 5 70 50
                            (if (eq? dir 'horizontal)
                                (linear-gradient 5 0 75 0
                                                 'desktop-top 'desktop-bottom)
                                (linear-gradient 0 5 0 55
                                                 'desktop-top 'desktop-bottom))
                            radius))))
             '(vertical horizontal) '(9 0))
            (same-drawing?
             80 60 1.5
             (lambda () (fill-glow 40 30 35 (alpha 'accent 0.3)))
             (lambda ()
               (fill-circle 40 30 35
                            (radial-gradient 40 30 35 (alpha 'accent 0.3)
                                             (alpha (alpha 'accent 0.3) 0)))))))

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

;; Stripes a pixel wide on an image that's drawn on: white, black, white...
(define (primitives-stripes n)
  (let ([target (gpu-image-make-target n n)] [plain record-world!])
    (set! record-world!
      (lambda ()
        (fill-box 0 0 n n #x000000)
        (do ([x 0 (+ x 2)]) ((>= x n)) (fill-box x 0 1 n #xffffff))))
    (rec-preview! target
                  (lambda ()
                    (list *rec-bytes* *rec-at* *rec-extras*
                          (* 4 *rec-extra-at*) (rec-runs))))
    (request-frame!)
    (steps 1)
    (set! record-world! plain)
    (request-frame!)
    (steps 1)
    target))

(let* ([stripes (primitives-stripes 64)]
       [white #xffffffff]
       [black #xff000000]
       [shown (lambda (n . xs)
                (apply pixels-of n n 1
                       (lambda () (draw-image stripes 0 0 n n))
                       (map (lambda (x) (list x (quotient n 2))) xs)))]
       ;; every pixel across, all channels within a level or so of half
       [even? (lambda (n)
                (for-all
                 (lambda (p)
                   (and (= (logand p #xff000000) #xff000000)
                        (for-all (lambda (shift)
                                   (<= 124 (logand (ash p shift) 255) 131))
                                 '(0 -8 -16))))
                 (apply shown n (iota n))))])
  (check "an image drawn on has a chain of levels, and is shown from the last \
          at least as big as it's drawn"
         (and (= (gpu-image-levels stripes) 7)
              (= (rec-image-level stripes 100 100) 0)
              (= (rec-image-level stripes 64 64) 0)
              (= (rec-image-level stripes 32 32) 1)
              (= (rec-image-level stripes 13 13) 2)
              (= (rec-image-level stripes 8 8) 3)
              (= (rec-image-level stripes 1 1) 6)
              (= (rec-image-level stripes 13 40) 0)))
  (check "at its own size it's exact, and bigger each pixel is a sharp block"
         (and (equal? (shown 64 0 1 2 3) (list white black white black))
              (equal? (shown 128 0 1 2 3 4)
                      (list white white black black white))))
  (check "smaller, no pixel of it is skipped: stripes are an even gray, at \
          any size"
         (for-all even? '(32 20 13 8 5)))
  (gpu-image-release! stripes))

;; A list recorded once and shown: where show-list puts it, inside the
;; clip around it, shown again elsewhere without being recorded again, and
;; inside another list, at the sum of their places.
(let* ([inner (gpu-list-new)] [outer (gpu-list-new)]
       [red #xffff0000] [black #xff000000]
       [shown (lambda (thunk . points)
                (apply pixels-of 40 30 1
                       (lambda () (fill-box 0 0 40 30 #x000000) (thunk))
                       points))]
       [first (shown (lambda ()
                       (record-list! inner
                                     (lambda () (fill-box 0 0 4 2 #xff0000)))
                       (show-list inner 10 10)
                       (with-clip (20 0 2 30) (show-list inner 20 20)))
                     '(10 10) '(13 11) '(14 10) '(10 12) '(21 20) '(22 20))]
       [moved (shown (lambda () (show-list inner 2 3))
                     '(2 3) '(5 4) '(10 10))]
       [nested (shown (lambda ()
                        (record-list! outer (lambda () (show-list inner 5 5)))
                        (show-list outer 10 10))
                      '(15 15) '(14 15) '(19 15))])
  (check (format "a list shows where show-list puts it, inside the clip \
                  around it (~s); shown again, not recorded again (~s); \
                  in a list shown, at the sum of their places (~s)"
                 first moved nested)
         (and (equal? first (list red red black black red black))
              (equal? moved (list red red black))
              (equal? nested (list red black black))))
  (gpu-list-release! inner)
  (gpu-list-release! outer))

;; Given 'gray an image's first channel shows in all three, as the glyphs'
;; atlas of one channel does in the Pipeline.
(let ([target (gpu-image-make-target 4 4)] [plain record-world!])
  (set! record-world!
    (lambda ()
      (fill-box 0 0 4 4 #x0000ff)
      (fill-box 0 0 1 4 #xff0000)
      (fill-box 2 0 1 4 #xff4000)))
  (rec-preview! target
                  (lambda ()
                    (list *rec-bytes* *rec-at* *rec-extras*
                          (* 4 *rec-extra-at*) (rec-runs))))
  (request-frame!)
  (steps 1)
  (set! record-world! plain)
  (request-frame!)
  (steps 1)
  (check "an image drawn gray shows its first channel, red, as gray"
         (and (equal? (pixels-of 4 1 1
                                 (lambda () (draw-image target 0 0 4 1 'gray))
                                 '(0 0) '(1 0) '(2 0))
                      '(#xffffffff #xff000000 #xffffffff))
              (equal? (pixels-of 4 1 1
                                 (lambda () (draw-image target 0 0 4 1))
                                 '(0 0) '(1 0))
                      '(#xffff0000 #xff0000ff))))
  (gpu-image-release! target))

(check "pixels with no chain, shown smaller, blend what they have"
       (let ([bv (make-bytevector 8 0)])
         (bytevector-u32-native-set! bv 0 #xffff0000)
         (bytevector-u32-native-set! bv 4 #xff0000ff)
         (let ([p (car (pixels-of 1 1 1 (lambda () (draw-pixels bv 2 1 0 0 1 1))
                                  '(0 0)))])
           (and (<= 126 (logand (ash p -16) 255) 129)
                (<= 126 (logand p 255) 129)))))

;; A PNG file of stored blocks read back: (w h . the first row's bytes).
(define (png-file-rows path)
  (let* ([bv (call-with-port (open-file-input-port path) get-bytevector-all)]
         [w (bytevector-u32-ref bv 16 (endianness big))]
         [h (bytevector-u32-ref bv 20 (endianness big))]
         ;; signature, IHDR's 25, IDAT's length and type, zlib's 2, a block's 5
         [at (+ 8 25 8 2 5)])
    (cons* w h
           (bytevector->u8-list
            (let ([row (make-bytevector (* h (+ 1 (* 4 w))))])
              (bytevector-copy! bv at row 0 (bytevector-length row))
              row)))))

(check "png-write-drawing draws on a fresh transparent image and saves it, \
        with straight color"
       (let ([path (string-append out-dir "/primitive.png")])
         (png-write-drawing path 3 2
                            (lambda ()
                              (fill-box 1 0 2 1 #x336699)
                              (fill-box 0 1 1 1 (alpha #xff0000 0.5))))
         (let ([r (png-file-rows path)])
           (delete-file path)
           (and (= (car r) 3) (= (cadr r) 2)
                (equal? (list-head (cddr r) 13)
                        '(0 0 0 0 0 #x33 #x66 #x99 255 #x33 #x66 #x99 255))
                ;; the second row's filter, then red at half
                (let ([row2 (list-tail (cddr r) 13)])
                  (and (= (cadr row2) 255) (= (caddr row2) 0)
                       (< 120 (list-ref row2 4) 135)))))))
