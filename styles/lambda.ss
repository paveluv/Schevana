;;; styles/lambda.ss — the Lambda window style.
;;; The λ is each window's emblem. The title sits in a tab on the top
;;; edge, only as wide as the title (as on BeOS), and the tab's right side
;;; is cut at the slant of the λ's long leg, so every tab leans like a λ.
;;; The tab starts with a λ drawn at that same slant and ends with the
;;; buttons, whose hover cells lean too; a thin frame continues from the
;;; tab's foot around the body. The focused window's tab and frame are the
;;; accent color; the others take the border's color and recede.

(define lambda-slant 0.55)   ; the long leg's run for each pixel of drop
(define lambda-rule 2)       ; the top rule, under the tab
(define lambda-gap 14)       ; between the title and the buttons

(define (lambda-tab-height) (- (title-height) lambda-rule))
(define (lambda-mark-size) (round (* 0.8 (font-line-height 'title))))
(define (lambda-button-width) (max 18 (round (* 1.8 (lambda-mark-size)))))
(define (lambda-pad) (round (* 0.36 (lambda-tab-height))))

;; A 1-pixel frame, none at the screen's edges.
(define (lambda-insets win)
  (let ([e (if (maximized? win) 0 1)])
    (values e (title-height) e e)))

;; Where the title (cut to fit) and the buttons start in the tab:
;; (values title tx bx). The tab's top edge ends after the buttons. A long
;; title is cut a slant short of the right edge, so even then the rule
;; runs on past the tab's foot and the tab still leans.
(define (lambda-tab win)
  (let* ([tx (+ (lambda-pad) (round (* 0.8 (lambda-mark-size))) 8)]
         [room (- (window-w win) tx lambda-gap (* 3 (lambda-button-width))
                  (* 2 lambda-slant (lambda-tab-height)))]
         [title (text-fit (window-title win) (max 0 room) 'title)]
         [gap (if (string=? title "") 0 lambda-gap)])
    (values title tx (round (+ tx (text-width title 'title) gap)))))

(define (lambda-regions win)
  (let-values ([(title tx bx) (lambda-tab win)])
    (let ([bw (lambda-button-width)] [th (lambda-tab-height)])
      (map (lambda (kind i) (list kind (+ bx (* i bw)) 0 bw th))
           '(minimize maximize close) '(0 1 2)))))

;; The λ, s high from (x, y): a hook, the long leg at the tab's slant, and
;; the short leg from the long one's middle.
(define (lambda-draw-mark x y s color)
  (let* ([hx (+ x (* 0.22 s))] [mx (+ hx (* lambda-slant s 0.45))]
         [lw (* 0.18 s)])
    (draw-polyline (list (cons x y) (cons hx y)
                         (cons (+ hx (* lambda-slant s)) (+ y s)))
                   color lw)
    (draw-line mx (+ y (* 0.45 s)) (- mx (* 0.33 s)) (+ y s) color lw)))

;; A cell leaning like the tab around (cx, cy), 2a wide and 2c high.
(define (lambda-lean cx cy a c color)
  (let ([d (* lambda-slant c)] [top (- cy c)] [bottom (+ cy c)])
    (fill-polygon (list (cons (- cx a d) top) (cons (- (+ cx a) d) top)
                        (cons (+ cx a d) bottom) (cons (+ (- cx a) d) bottom))
                  color)))

;; The glyphs are 2 wide on whole pixels, crisp at 100% and 200% and as
;; heavy as the bold title.
(define (lambda-draw-button kind bx by bw bh ink hover pressed)
  (let* ([cx (+ bx (floor (/ bw 2)))] [cy (+ by (floor (/ bh 2)))]
         [g (round (* 0.16 bw))]
         [down? (eq? pressed kind)] [hot? (or down? (eq? hover kind))]
         [red? (and hot? (eq? kind 'close))]
         [ink (if red? (color-readable-on 'button-close) ink)])
    (when hot?
      (lambda-lean cx cy (* 0.3 bw) (min (* 0.34 bh) (* 0.42 bw))
                   (cond [red? (if down? (mix 'button-close ink 0.25)
                                   'button-close)]
                         [else (alpha ink (if down? 0.3 0.16))])))
    (let ([flags (list (cons 'ink ink) '(width . 2))])
      (if (eq? kind 'close)
          (ui-draw-glyph (- cx g) (- cy g) (* 2 g) (* 2 g) flags 'close)
          (ui-draw-glyph (- cx g 1) (- cy g 1) (+ g g 2) (+ g g 2) flags
                         kind)))))

(define (lambda-draw-under win x y w h focused? hover pressed)
  (let*-values ([(th) (lambda-tab-height)] [(bw) (lambda-button-width)]
                [(s) (lambda-mark-size)]
                [(title tx bx) (lambda-tab win)]
                [(end) (+ x bx (* 3 bw))]
                [(tab) (if focused? 'accent 'window-border)]
                [(ink) (if focused?
                           (color-readable-on 'accent)
                           (mix 'title-text-dim 'title-text 0.3))])
    (window-shadow win x (+ y th) w (- h th) 0 focused?)
    ;; maximized, the tab stands on a strip, not on the windows behind
    (when (maximized? win) (fill-box x y w th 'title-bg))
    (fill-box x (+ y th) w lambda-rule tab)
    (stroke-box x (+ y th) w (- h th) tab)
    (with-clip (x y w h)   ; a narrow window cuts its tab
      (fill-polygon (list (cons x y) (cons end y)
                          (cons (+ end (* lambda-slant th)) (+ y th))
                          (cons x (+ y th)))
                    tab)
      (lambda-draw-mark (+ x (lambda-pad)) (+ y (/ (- th s) 2)) s ink)
      (draw-text (+ x tx) (+ y (/ (- th (font-line-height 'title)) 2))
                 title ink 'title)
      (for-each (lambda (kind i)
                  (lambda-draw-button kind (+ x bx (* i bw)) y bw th
                                      ink hover pressed))
                '(minimize maximize close) '(0 1 2)))))

;; The wheel on the tab rolls the window up into it (shades it) and down.
(define-style lambda "Lambda"
  ;; square, and so is everything drawn in it (rrect-path!); every common
  ;; option but the radius
  'corner-radius 0
  'options (remq 'corner-radius (map car common-options))
  'title-wheel 'shade
  'frame-insets 'lambda-insets
  'frame-regions 'lambda-regions
  'frame-under 'lambda-draw-under)
