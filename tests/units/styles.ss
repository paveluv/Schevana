;;; tests/units/styles.ss — styles and parts: derived styles, parts given by
;;; name, and a window with a style of its own.

;;; styles and parts

(reset-theme!)
(set-style! 'mac)

(define (insets-of w) (call-with-values (lambda () (frame-insets w)) list))
(define (test-insets win) (values 3 17 3 3))

(check "a derived style is its parent with one setting changed, and its \
        parent defined again shows in it"
       (with-test-styles
        (lambda ()
          (define-style test-base "Test base"
            'frame-insets 'test-insets 'corner-radius 5)
          (define-style test-flat "Test flat"
            'parent 'test-base 'corner-radius 0)
          (set-style! 'test-flat)
          (let* ([w (open-window "Derived" 'size '(100 . 50))]
                 [got (list (map style-name (style-chain 'test-flat))
                            (insets-of w) (theme 'corner-radius)
                            (theme-source 'corner-radius)
                            (theme-source 'frame-insets))])
            (define-style test-base "Test base" 'corner-radius 5)
            (let ([again (insets-of w)])
              (close-window! w)
              (equal? (list got again)
                      (list (list '(test-flat test-base) '(3 17 3 3) 0
                                  '(style test-flat 0)
                                  '(style test-base test-insets))
                            (list 0 (title-height) 0 0))))))))

;; A part that a style gives by name is looked up at each call, so once it
;; is redefined at the REPL, the next frame draws the new definition.
(define test-drawn #f)
(define (test-under win x y w h focused? hover pressed)
  (set! test-drawn 'first))
(check "a part given by name shows its redefinition at the next frame"
       (with-test-styles
        (lambda ()
          (define-style test-part "Test part" 'frame-under 'test-under)
          (set-style! 'test-part)
          (let ([w (open-window "Part" 'size '(100 . 50))])
            (steps 1)
            (let ([first test-drawn])
              (set! test-under (lambda args (set! test-drawn 'second)))
              (invalidate!)
              (steps 1)
              (close-window! w)
              (equal? (list first test-drawn) '(first second)))))))

(define-part (test-meter n) (* n 2))
(check "define-part: the built-in is name*, and name calls the style's part"
       (with-test-styles
        (lambda ()
          (let ([plain (test-meter 3)])
            (define-style test-tenfold "Test" 'test-meter (lambda (n) (* n 10)))
            (set-style! 'test-tenfold)
            (equal? (list plain (test-meter 3) (test-meter* 3)
                          (theme-default 'test-meter))
                    '(6 30 6 test-meter*))))))

(check "a title's right click opens the style's window menu, a part"
       (with-test-styles
        (lambda ()
          (let ([opened #f])
            (define-style test-menu "Test"
              'open-window-menu (lambda (win x y) (set! opened win)))
            (set-style! 'test-menu)
            (let ([w (open-window "Menu" 'size '(200 . 100) 'pos '(300 . 200))])
              (inject! '(mouse-move 400 205) '(mouse-down 400 205 right 1)
                       '(mouse-up 400 205 right))
              (steps 1)
              (close-window! w)
              (eq? opened w))))))

(check "a window of another style is drawn and hit-tested in that style's \
        theme, its content included"
       (let* ([seen #f]
              [w (open-window "Genera here" 'size '(200 . 100)
                              'pos '(300 . 200) 'window-style 'genera
                              'draw (lambda (win cw ch)
                                      (set! seen (list (theme 'palette)
                                                       (theme 'wallpaper)))))])
         (invalidate!)
         (steps 1)
         ;; In Genera, the label at the bottom is the title
         (let ([insets (insets-of w)]
               [hit (window-region w 400 (+ 200 (window-h w) -10))])
           (close-window! w)
           (printf "  ~s\n" (list seen insets hit))
           (and (equal? seen '(genera flat)) (eq? (theme 'palette) 'tokyo-night)
                (equal? insets (test-genera-insets)) (eq? hit 'title)))))

(check "choosing Genera brings its palette and wallpaper; a palette chosen \
        for it stays with it"
       (begin
         (set-style! 'genera)
         (let ([own (list (theme 'palette) (theme 'wallpaper))])
           (set-theme! 'palette 'nord)
           (set-style! 'mac)
           (let ([mac (list (theme 'palette) (theme 'wallpaper))])
             (set-style! 'genera)
             (let ([back (theme 'palette)])
               (reset-theme!)
               (set-style! 'mac)
               (equal? (list own mac back)
                       '((genera flat) (tokyo-night gradient) nord)))))))

(check "with-style: another style's theme, or this one's with a setting"
       (equal? (list (with-style 'interlisp
                       (lambda () (list (theme 'palette) (theme 'wallpaper))))
                     (with-style 'mac (lambda () (theme 'palette))
                                 'palette 'nord)
                     (theme 'palette))
               '((interlisp shade) nord tokyo-night)))

;; Each style draws a menu entry's icon in its menu, its own or the
;; built-in, unless it shows none (menu-icons): the Lisp machines', OPEN
;; LOOK's and Curses' menus are words alone.
(check "every style's menu draws an entry's icon, but those whose menus are \
        words alone (menu-icons #f)"
       (let ([drawn (map (lambda (style)
                           (let ([seen #f])
                             (set-style! style)
                             (open-menu! 200 200
                                         (list (list "One" void
                                                     (lambda (x y s flags)
                                                       (set! seen #t)))
                                               (cons "Two" void))
                                         'tag 'launcher)
                             (steps 1)
                             (close-menu!)
                             (cons style seen)))
                         (styles))])
         (set-style! 'mac)
         (printf "  ~s\n" drawn)
         (for-all (lambda (d)
                    (eq? (cdr d)
                         (not (memq (car d)
                                    '(genera cadr interlisp open-look
                                      curses)))))
                  drawn)))
