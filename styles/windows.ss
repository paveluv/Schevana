;;; styles/windows.ss — the Windows window style.
;;; App icon and title on the left; minimize, maximize and close on the
;;; right as full-height buttons, close turning red on hover.

(define windows-button-width 46)

(define (windows-radius win)
  (if (maximized? win) 0 (min 8 (theme 'corner-radius))))

(define (windows-regions win)
  (let ([w (window-w win)] [bw windows-button-width] [th (title-height)])
    (list (list 'close (- w bw) 0 bw th)
          (list 'maximize (- w bw bw) 0 bw th)
          (list 'minimize (- w bw bw bw) 0 bw th))))

(define (windows-draw-button win kind bx by bw bh focused? hover pressed)
  (let* ([down? (eq? pressed kind)]
         [hot? (or down? (eq? hover kind))]
         [close? (eq? kind 'close)]
         [ink (cond [(and close? hot?) #xffffff]
                    [focused? 'title-text]
                    [else 'title-text-dim])]
         [cx (+ bx (quotient bw 2))]
         [cy (+ by (quotient bh 2))])
    (when hot?
      (fill-box bx by bw bh
                (if close?
                    (if down? #xf1707a #xe81123)
                    (alpha 'text (if down? 0.16 0.09)))))
    (ui-draw-glyph (- cx 5) (- cy 5) 10 10 (list (cons 'ink ink))
                   (ui-frame-glyph win kind))))

(define (windows-draw-under win x y w h focused? hover pressed)
  (let* ([th (title-height)] [r (windows-radius win)]
         [title (window-title win)]
         [icon (app-color (window-app win))]
         [is (max 16 (round (+ (font-line-height 'ui-small) 3)))])
    (window-shadow win x y w h r focused?)
    (fill-box x y w h (window-bg win) r)
    (with-clip (x y w h r)
      (fill-box x y w th (if focused? 'title-bg-focus 'title-bg))
      ;; the window's own icon, or its app's color and initial
      (if (ui-title-icon win)
          ((ui-title-icon win) (+ x 12) (+ y (quotient (- th is) 2)) is
                               (if focused? '() '(dim)))
          (begin
            (fill-box (+ x 12) (+ y (quotient (- th is) 2)) is is icon 4)
            (text-draw-centered (+ x 12) (+ y (quotient (- th is) 2)) is is
                                (if (string=? title "")
                                    "·"
                                    (string (char-upcase
                                             (string-ref title 0))))
                                (color-readable-on icon) 'ui-small)))
      (draw-text (+ x is 22) (+ y (/ (- th (font-line-height 'ui)) 2))
                 (text-fit title (- w is 22 (* 3 windows-button-width) 12)
                           'ui)
                 (if focused? 'title-text 'title-text-dim) 'ui)
      (for-each (lambda (b)
                  (windows-draw-button win (car b)
                                       (+ x (list-ref b 1))
                                       (+ y (list-ref b 2))
                                       (list-ref b 3) (list-ref b 4)
                                       focused? hover pressed))
                (windows-regions win)))))

(define (windows-draw-over win x y w h focused? hover pressed)
  (stroke-box x y w h (if focused? 'window-border-focus 'window-border) 1
              (windows-radius win)))

(define-style windows "Windows"
  ;; a divider's drag widens its column and moves the rest along, as
  ;; Explorer's details view
  'table-resize 'shift
  'frame-radius 'windows-radius
  'frame-regions 'windows-regions
  'frame-under 'windows-draw-under
  'frame-over 'windows-draw-over)
