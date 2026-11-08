;;; kits/text.ss — text in boxes, measured with the core's text-width and
;;; drawn with its draw-text: the widest of some strings, a string
;;; centered, cut to fit with an ellipsis, or broken into lines.

;; Width of the widest of strs (0 for none).
(define (text-widest strs font)
  (apply max 0 (map (lambda (s) (text-width s font)) strs)))

;; Text centered in a box.
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
  (let* ([width (if (pair? measure) (car measure)
                    (lambda (s) (text-width s font)))]
         [s (text-within str max-w)]
         [cut (lambda (n) (string-append (substring s 0 n) "…"))])
    (if (or (string=? s "") (and (eq? s str) (<= (width str) max-w)))
        s
        (let loop ([lo 0] [hi (- (string-length s) 1)])   ; lo fits, or is 0
          (let ([mid (quotient (+ lo hi 1) 2)])
            (cond [(>= lo hi) (cut lo)]
                  [(<= (width (cut mid)) max-w) (loop mid hi)]
                  [else (loop lo (- mid 1))]))))))

;; Break str into lines no wider than max-w, at spaces. Newlines are kept;
;; a single word wider than max-w gets a line of its own.
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
                           (loop (cdr words) (car words) (cons line acc))))])))
              (string-split str #\newline))))
