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
