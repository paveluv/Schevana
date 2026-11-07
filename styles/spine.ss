;;; styles/spine.ss — the Spine window style.
;;; Every window is a book on a shelf. Its title bar is the spine: a band
;;; down the left side in the app's own color (the color of its dot in the
;;; taskbar), with the buttons stacked at the head, the title reading
;;; bottom to top between two pairs of rules, and Schevana's λ at the foot,
;;; where a publisher prints its mark. The focused book is in full color;
;;; the others fade toward the shelf but keep a tint of their hue. The
;;; content gets the whole height of the window.

(define (spine-width) (- (title-height) 2))   ; 28 at the default 30

;; The height of a button, and of the λ's place at the foot.
(define (spine-cell) (exact (round (* (spine-width) 5/7))))   ; 20

(define (spine-radius win)
  (if (maximized? win) 0 (min 10 (theme 'corner-radius))))

(define (spine-insets win) (values (spine-width) 0 0 0))

;; The buttons, then the rest of the spine as the title, which drags. The
;; left edge and the bottom corner stay free for resizing.
(define (spine-regions win)
  (let ([s (spine-width)] [c (spine-cell)])
    (list (list 'close 0 4 s c)
          (list 'minimize 0 (+ 4 c) s c)
          (list 'maximize 0 (+ 4 c c) s c)
          (list 'title 5 0 (- s 5) (- (window-h win) 14)))))

;; (values band ink): the spine's color and the color drawn on it.
(define (spine-colors win focused?)
  (let ([app (app-color (window-app win))])
    (if focused?
        (values app (color-readable-on app))
        (let ([band (mix 'title-bg app 0.24)])
          (values band (mix band 'title-text 0.5))))))

;; 8 pixels square around (cx, cy), on whole pixels: crisp, on one axis.
(define (spine-glyph win kind cx cy ink)
  (ui-draw-glyph (- cx 4) (- cy 4) 8 8
                 (cons (cons 'ink ink)
                       (if (eq? kind 'close) '((width . 1.25)) '()))
                 (ui-frame-glyph win kind)))

(define (spine-draw-button win kind cx cy focused? hover pressed ink)
  (let* ([down? (eq? pressed kind)] [hot? (or down? (eq? hover kind))]
         [close? (eq? kind 'close)])
    (when hot?
      (fill-circle cx cy 9
                   (cond [(not close?) (alpha ink (if down? 0.3 0.16))]
                         [down? (mix 'button-close #x000000 0.2)]
                         [else 'button-close])))
    (spine-glyph win kind cx cy
                 (cond [(and hot? close?) (color-readable-on 'button-close)]
                       [hot? ink]
                       [else (alpha ink (if focused? 0.7 0.55))]))))

;; Two thin rules across the spine, as gilt on a binding.
(define (spine-rules x y s ink)
  (fill-box x y (- s 1) 1 ink)
  (fill-box x (+ y 3) (- s 1) 1 ink))

(define (spine-draw-under win x y w h focused? hover pressed)
  (let*-values ([(s) (spine-width)] [(c) (spine-cell)] [(r) (spine-radius win)]
                [(cx) (+ x (quotient s 2))]
                [(band ink) (spine-colors win focused?)]
                [(head) (+ y 7 (* 3 c))]       ; the rules under the buttons
                [(tail) (+ y h -11 (- c))]     ; and over the λ
                ;; a short spine gives the title the λ's place
                [(foot?) (> (- tail head)
                            (+ 12 (min 100 (text-width (window-title win)
                                                       'title))))]
                [(end) (if foot? tail (+ y h -4))]
                [(title) (text-fit (window-title win) (- end head 12) 'title)]
                [(a) (font-ascent 'title)])
    (window-shadow win x y w h r focused?)
    (fill-box x y w h (window-bg win) r)
    (with-clip (x y w h r)
      (fill-box x y s h band)
      (fill-box (+ x s -1) y 1 h (alpha #x000000 0.18))   ; the joint
      (for-each (lambda (b)
                  (unless (eq? (car b) 'title)
                    (spine-draw-button win (car b) cx
                                       (+ y (caddr b) (quotient c 2))
                                       focused? hover pressed ink)))
                (spine-regions win))
      (when foot?
        (spine-rules x tail s (alpha ink 0.35))
        (text-draw-centered x (+ tail 6) s c "λ" ink 'title))
      (unless (string=? title "…")   ; a spine too short for any title
        (spine-rules x head s (alpha ink 0.35))
        ;; turned to read upward, its capitals (about 3/4 of the
        ;; ascent) centered across the spine
        (with-translation ((- (round (+ cx (* 3/8 a))) a)
                           (round (+ (/ (+ head 4 end) 2)
                                     (/ (text-width title 'title) 2))))
          (with-turn ((* -1/2 pi)) (draw-text 0 0 title ink 'title)))))))

(define (spine-draw-over win x y w h focused? hover pressed)
  (stroke-box x y w h
              (if focused?
                  (mix (app-color (window-app win))
                       'window-border-focus 0.5)
                  'window-border)
              1 (spine-radius win)))

(define-style spine "Spine"
  'frame-insets 'spine-insets
  'frame-radius 'spine-radius
  'frame-regions 'spine-regions
  'frame-under 'spine-draw-under
  'frame-over 'spine-draw-over)
