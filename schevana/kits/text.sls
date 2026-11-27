;;; (schevana kits text) — text in boxes, measured with the core's text-width
;;; and drawn with its draw-text: the ink of a string, the widest of several
;;; strings, and a string centered, cut to fit with an ellipsis, or broken
;;; into lines.

(library (schevana kits text)
  (export
    text-ink text-face-extent text-shorten text-widest text-draw-centered
    text-within text-fit text-wrap)
  (import (chezscheme)
          (only (schevana base) library-layer string-split)
          (only (schevana core) draw-text font font-advance font-face-for
                font-file-ascender font-file-descender font-file-pages
                font-file-upem font-line-height font-ready font-size get-font
                text-width))

  (library-layer kits)

  ;; Returns the ink of str in font as (values left top width height),
  ;; measured from the pen on the baseline (a top < 0 is above it), in
  ;; logical pixels, from the core's font tables: each character's from the
  ;; face that draws it (font-face-for). Unhinted.
  (define (text-ink str font)
    (let* ([f (get-font font)]
           [ff (font-ready f)]
           [n (string-length str)])
      (let loop ([i 0] [pen 0] [x0 #f] [x1 0] [y0 #f] [y1 0])
        (if (fx= i n)
            (if x0
                (values (inexact x0) (inexact y0)
                        (inexact (- x1 x0)) (inexact (- y1 y0)))
                (values 0.0 0.0 0.0 0.0))
            (let* ([c (char->integer (string-ref str i))]
                   [face (font-face-for f ff c)]
                   [scale (/ (font-size f) (font-file-upem face))]
                   [page (vector-ref (font-file-pages face) (fxsrl c 8))]
                   [at (fx* 5 (fxand c 255))]
                   [w (if page (fxvector-ref page (fx+ at 3)) 0)]
                   [h (if page (fxvector-ref page (fx+ at 4)) 0)]
                   [left (if page (fxvector-ref page (fx+ at 1)) 0)]
                   [top (if page (fxvector-ref page (fx+ at 2)) 0)]
                   [next (fx+ pen (font-advance f ff c))])
              (if (or (fx<= w 0) (fx<= h 0))
                  (loop (fx+ i 1) next x0 x1 y0 y1)
                  (let ([ax (+ (/ pen 256) (* left scale))]
                        [ay (- (* top scale))])
                    (loop (fx+ i 1) next
                          (if x0 (min x0 ax) ax)
                          (max x1 (+ ax (* w scale)))
                          (if y0 (min y0 ay) ay)
                          (max y1 (+ ay (* h scale)))))))))))

  ;; Returns (values ascent descent) of font as its face gives them, in
  ;; logical pixels and unrounded (the core's font metrics are whole
  ;; numbers).
  (define (text-face-extent font)
    (let* ([f (get-font font)] [ff (font-ready f)]
           [scale (/ (font-size f) (font-file-upem ff))])
      (values (* scale (font-file-ascender ff))
              (* scale (- (font-file-descender ff))))))

  ;; Returns s cut to at most n characters, the last one an ellipsis when it
  ;; is cut.
  (define (text-shorten s n)
    (if (<= (string-length s) n)
        s
        (string-append (substring s 0 (max 0 (- n 1))) "…")))

  ;; Returns the width of the widest of strs (0 for none).
  (define (text-widest strs font)
    (apply max 0 (map (lambda (s) (text-width s font)) strs)))

  ;; Draws str centered in a box.
  (define (text-draw-centered x y w h str color font)
    (let ([tw (text-width str font)] [th (font-line-height font)])
      (draw-text (+ x (/ (- w tw) 2)) (+ y (/ (- h th) 2)) str color font)))

  ;; str cut to as many characters as w pixels could show (no glyph but a
  ;; zero-width one is narrower than about a pixel): all a fit measures.
  (define (text-within str w)
    (let ([n (+ 1 (max 0 (exact (floor w))))])
      (if (> (string-length str) n) (substring str 0 n) str)))

  ;; Shorten str with an ellipsis until it fits in max-w: the longest prefix
  ;; of str within max-w that does, found by halving (log n measures, not n).
  ;; measure, if given, is (lambda (s) width) instead of text-width in font.
  (define (text-fit str max-w font . measure)
    (if (pair? measure)
        (text-fit-cut str max-w (car measure))
        (let ([f (get-font font)]
              [kept (eq-hashtable-ref text-fit-cuts str #f)])
          (if (and kept (eqv? (vector-ref kept 0) max-w)
                   (eq? (vector-ref kept 1) f))
              (vector-ref kept 2)
              (let ([s (text-fit-cut str max-w
                                     (lambda (s) (text-width s font)))])
                (unless (eq? s str)
                  (eq-hashtable-set! text-fit-cuts str (vector max-w f s)))
                s)))))

  ;; What text-fit cut, by the string it was given: the width and the font
  ;; it was cut for, and the cut, so that a label drawn again as wide is
  ;; not cut again. A cache: its loss changes only speed.
  (define text-fit-cuts (make-weak-eq-hashtable))

  ;; text-fit's own work, with width measuring a string.
  (define (text-fit-cut str max-w width)
    (let* ([s (text-within str max-w)]
           [cut (lambda (n) (string-append (substring s 0 n) "…"))])
      (if (or (string=? s "") (and (eq? s str) (<= (width str) max-w)))
          s
          (let loop ([lo 0] [hi (- (string-length s) 1)])   ; lo fits, or is 0
            (let ([mid (quotient (+ lo hi 1) 2)])
              (cond [(>= lo hi) (cut lo)]
                    [(<= (width (cut mid)) max-w) (loop mid hi)]
                    [else (loop lo (- mid 1))]))))))

  ;; Returns str broken at spaces into lines no wider than max-w. Newlines
  ;; are kept; a single word wider than max-w gets a line of its own.
  (define (text-wrap str max-w font)
    (apply append
           (map (lambda (para)
                  (let loop ([words (string-split para #\space)]
                             [line #f]
                             [acc '()])
                    (cond
                      [(null? words) (reverse (if line (cons line acc) acc))]
                      [(not line) (loop (cdr words) (car words) acc)]
                      [else
                       (let ([longer (string-append line " " (car words))])
                         (if (<= (text-width longer font) max-w)
                             (loop (cdr words) longer acc)
                             (loop (cdr words) (car words)
                                   (cons line acc))))])))
                (string-split str #\newline)))))
