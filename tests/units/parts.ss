;;; tests/units/parts.ss — the kit, the bars and the menus through parts;
;;; places.

;;; the kit, the bars and the menus through parts; places

(for-each close-window! (windows))
(reset-theme!)
(set-style! 'mac)
(steps 1)

;; The leftmost column inside the field (content x 30 to 300) where its
;; text's ink is, in logical pixels.
(define (ink-left win)
  (let-values ([(cx cy cw ch) (content-rect win)])
    (let ([bg (canvas-pixel (+ cx 24) (+ cy 35))])
      (let loop ([x 24])
        (cond [(> x 300) #f]
              [(exists (lambda (dy) (not (= (canvas-pixel (+ cx x) (+ cy dy))
                                            bg)))
                       '(28 31 34 37 40))
               x]
              [else (loop (+ x 1))])))))

;; The caret's index after a click at content x 60.
(define (index-clicked win ui)
  (let-values ([(cx cy cw ch) (content-rect win)])
    (inject! `(mouse-move ,(+ cx 60) ,(+ cy 35))
             `(mouse-down ,(+ cx 60) ,(+ cy 35) left 1)
             `(mouse-up ,(+ cx 60) ,(+ cy 35) left))
    (steps 2)
    (edit-caret (ui-state-edit ui))))

(define (test-text-areas x y w h flags)
  (let ([a (ui-text-box-areas* x y w h flags)])
    (cons (cons* 'edit (+ (cadr (car a)) 40) (cddr (car a))) (cdr a))))

(check "a style that moves only ui-text-box-areas moves the text and where \
        a click puts the caret"
       (with-test-styles
        (lambda ()
          (let-values ([(win ui) (field-window "MMMMMMMMMMMM")])
            (steps 2)
            (let ([plain (list (ink-left win) (index-clicked win ui))])
              (define-style test-areas "Test"
                'ui-text-box-areas 'test-text-areas)
              (set-style! 'test-areas)
              (steps 2)
              (let ([moved (list (ink-left win) (index-clicked win ui))])
                (close-window! win)
                (printf "  ~s\n" (list plain moved))
                (and (car plain) (car moved)
                     (<= 39 (- (car moved) (car plain)) 41)
                     (< (cadr moved) (cadr plain)))))))))

(check "a style mapping the field place colors a text box's text, and only \
        inside it"
       (with-test-styles
        (lambda ()
          (let ([seen '()])
            (define-style test-place "Test"
              'places (list (list 'field 'text #xff0000))
              'ui-draw-text-box
              (lambda args
                (set! seen (cons (cons 'box (theme 'text)) seen))
                (apply ui-draw-text-box* args))
              'ui-draw-label
              (lambda args
                (set! seen (cons (cons 'label (theme 'text)) seen))
                (apply ui-draw-label* args)))
            (set-style! 'test-place)
            (let-values ([(win ui) (field-window "x")])
              (steps 2)
              (close-window! win)
              (and (equal? (assq 'box seen) '(box . #xff0000))
                   (equal? (assq 'label seen) (cons 'label (theme 'text)))
                   (not (= (theme 'text) #xff0000))))))))

(define (test-topbar-areas)
  (let ([h (topbar-height)])
    (list (list 'launcher 300 0 120 h) (list 'title 0 0 300 h))))

(check "a style that moves the launcher in the top bar's areas moves its \
        click"
       (with-test-styles
        (lambda ()
          (define (opened-at x)
            (inject! `(mouse-move ,x 10) `(mouse-down ,x 10 left 1)
                     `(mouse-up ,x 10 left))
            (steps 1)
            (let ([open? (launcher-open?)])
              (when (menu-open?) (close-menu!))
              (steps 1)
              open?))
          (let ([plain (list (opened-at 40) (opened-at 340))])
            (define-style test-launcher "Test"
              'topbar-areas 'test-topbar-areas)
            (set-style! 'test-launcher)
            (equal? (list plain (list (opened-at 40) (opened-at 340)))
                    '((#t #f) (#f #t)))))))

(check "the menu's entries are where menu-areas puts them: a taller entry \
        moves the click"
       (with-test-styles
        (lambda ()
          (define (entry-at-row row)
            (open-menu! 100 100 '(("One" . void) ("Two" . void)
                                  ("Three" . void)))
            (let-values ([(x y w h) (menu-geometry *menu*)])
              (let ([i (menu-entry-at (+ x 20)
                                      (+ y (theme 'menu-pad) row))])
                (close-menu!)
                i)))
          (let ([plain (entry-at-row 60)])
            (define-style test-menu "Test" 'menu-item-height 40)
            (set-style! 'test-menu)
            (equal? (list plain (entry-at-row 60)) '(2 1))))))

(check "the dialog place reaches the kit's dialog, drawn at ui-end!"
       (with-test-styles
        (lambda ()
          (let ([seen #f] [ui (make-ui)])
            (define-style test-dialog "Test"
              'places (list (list 'dialog 'bg-2 #xffff00))
              'ui-draw-dialog (lambda args
                                (set! seen (theme 'bg-2))
                                (apply ui-draw-dialog* args)))
            (set-style! 'test-dialog)
            (let ([w (apply open-window "Dialog" 'size '(420 . 260)
                            'ui ui
                            'draw (lambda (win w h)
                                    (ui-begin! ui)
                                    (ui-dialog ui 'd "A dialog" "Its message."
                                               (list (list "OK" void)) void)
                                    (ui-end! ui w h))
                            (ui-handlers ui))])
              (steps 2)
              (close-window! w)
              (eqv? seen #xffff00))))))

(check "a preview's extra settings lie over the Overrides, and over what \
        a style honors"
       (with-test-styles
        (lambda ()
          (define-style test-fixed-palette "Test" 'parent 'mac
            'options '(accent))
          (override! 'palette 'gruvbox)
          (let ([seen (list (with-style 'mac (lambda () (theme 'palette))
                                        'palette 'nord)
                            (with-style 'test-fixed-palette
                                        (lambda () (theme 'palette))
                                        'palette 'nord))])
            (override! 'palette)
            (equal? seen '(nord nord))))))

(check "a window of another style hears its input in that style's theme, \
        and a theme change its handler makes stays"
       (let* ([seen #f]
              [w (open-window "Genera input" 'size '(200 . 100)
                              'pos '(300 . 200) 'window-style 'genera
                              'mouse-down
                              (lambda (win x y button clicks)
                                (set! seen (theme 'palette))
                                (set-theme! 'accent #x123456)))])
         (steps 1)
         (let-values ([(cx cy cw ch) (content-rect w)])
           (inject! `(mouse-down ,(+ cx 20) ,(+ cy 20) left 1)
                    `(mouse-up ,(+ cx 20) ,(+ cy 20) left))
           (steps 1))
         (close-window! w)
         (let ([accent (theme 'accent)])
           (reset-style! 'accent)
           (and (eq? seen 'genera) (= accent #x123456)))))

(check "a menu whose place makes its entries taller takes a click where \
        it draws the entry"
       (with-test-styles
        (lambda ()
          (define-style test-tall-menu "Test"
            'places (list (list 'menu 'menu-item-height 50)))
          (set-style! 'test-tall-menu)
          (open-menu! 300 150 '(("One" . void) ("Two" . void)
                                ("Three" . void)))
          (let* ([two (assv 1 (with-place 'menu
                                (lambda () (menu-areas *menu*))))]
                 [hit (menu-entry-at (+ (cadr two) 20) (+ (caddr two) 25))])
            (close-menu!)
            (and (= (list-ref two 4) 50) (eqv? hit 1))))))

(check "an accent change is a change of colors only: the chrome stays"
       (let* ([n 0] [plain wm-chrome-changed!])
         (set! wm-chrome-changed! (lambda () (set! n (+ n 1)) (plain)))
         (set-theme! 'accent #xff9e64)
         (reset-style! 'accent)
         (set! wm-chrome-changed! plain)
         (= n 0)))

(check "a window of no style, focused or opened from another style's \
        handler, is in the chosen style's theme"
       (let* ([seen '()]
              [note (lambda (what)
                      (set! seen (cons (cons what (theme 'palette)) seen)))]
              [b (open-window "Plain" 'size '(100 . 60) 'pos '(600 . 400)
                              'focus (lambda (win) (note 'focus)))]
              [c #f]
              [g (open-window "Genera" 'size '(200 . 100) 'pos '(300 . 200)
                              'window-style 'genera
                              'mouse-down
                              (lambda (win x y button clicks)
                                (focus-window! b)
                                (set! c (open-window
                                         "Opened" 'size '(100 . 60)
                                         'open (lambda (win)
                                                 (note 'open))))))])
         (set! seen '())
         (steps 1)
         (let-values ([(cx cy cw ch) (content-rect g)])
           (inject! `(mouse-down ,(+ cx 20) ,(+ cy 20) left 1)
                    `(mouse-up ,(+ cx 20) ,(+ cy 20) left))
           (steps 1))
         (for-each close-window! (list b c g))
         (and (equal? (assq 'focus seen) '(focus . tokyo-night))
              (equal? (assq 'open seen) '(open . tokyo-night)))))

(check "a theme change of colors from another style's handler changes no \
        chrome"
       (let* ([n 0] [plain wm-chrome-changed!]
              [g (open-window "Genera" 'size '(200 . 100) 'pos '(300 . 200)
                              'window-style 'genera
                              'mouse-down
                              (lambda (win x y button clicks)
                                (set! n 0)
                                (set-theme! 'accent #x123456)))])
         (steps 1)
         (set! wm-chrome-changed! (lambda () (set! n (+ n 1)) (plain)))
         (let-values ([(cx cy cw ch) (content-rect g)])
           (inject! `(mouse-down ,(+ cx 20) ,(+ cy 20) left 1)
                    `(mouse-up ,(+ cx 20) ,(+ cy 20) left))
           (steps 1))
         (set! wm-chrome-changed! plain)
         (close-window! g)
         (reset-style! 'accent)
         (= n 0)))

(check "a text box whose place sets its text size takes a click where it \
        draws its text, as with the size set for the whole style"
       (with-test-styles
        (lambda ()
          (define (caret-at style)
            (set-style! style)
            (let-values ([(win ui) (field-window "MMMMMMMMMMMM")])
              (steps 2)
              (let ([i (index-clicked win ui)])
                (close-window! win)
                i)))
          (define-style test-big "Test" 'ui-font-size 26)
          (define-style test-big-field "Test"
            'places (list (list 'field 'ui-font-size 26)))
          (let* ([whole (caret-at 'test-big)]
                 [placed (caret-at 'test-big-field)])
            (printf "  ~s\n" (list whole placed))
            (= whole placed)))))

(check "the bars' place sizes their strips and places their clicks"
       (with-test-styles
        (lambda ()
          (define (launcher-at x)
            (inject! `(mouse-move ,x 10) `(mouse-down ,x 10 left 1)
                     `(mouse-up ,x 10 left))
            (steps 1)
            (let ([open? (launcher-open?)])
              (when (menu-open?) (close-menu!))
              (steps 1)
              open?))
          (define-style test-big-bars "Test"
            'places (list (list 'bar 'ui-font-size 26)))
          (let ([plain (launcher-at 150)])
            (set-style! 'test-big-bars)
            (let-values ([(dx dy dw dh) (desktop-rect)])
              (and (not plain) (launcher-at 150)
                   (= dy (topbar-height))
                   (> dy (theme 'topbar-height))))))))

(check "a tooltip is measured in its place, where it is drawn"
       (with-test-styles
        (lambda ()
          (let* ([seen #f] [ui (make-ui)] [fake (now-ms)] [real now-ms])
            (define-style test-big-tips "Test"
              'places (list (list 'tooltip 'ui-font-size 26))
              'ui-draw-tooltip
              (lambda (x y w h flags text)
                (set! seen (list (list w h)
                                 (call-with-values
                                   (lambda () (ui-tooltip-size text))
                                   list)))
                (ui-draw-tooltip* x y w h flags text)))
            (set-style! 'test-big-tips)
            (set! now-ms (lambda () fake))
            (let ([w (apply open-window "Tips" 'size '(400 . 200)
                            'pos '(200 . 200) 'ui ui
                            'draw (lambda (win w h)
                                    (ui-begin! ui)
                                    (ui-button ui 'b 20 20 100 30 "Button"
                                               void 'tip "A tip")
                                    (ui-end! ui w h))
                            (ui-handlers ui))])
              (steps 2)
              (let-values ([(cx cy cw ch) (content-rect w)])
                (inject! `(mouse-move ,(+ cx 50) ,(+ cy 30)))
                (steps 2)
                (set! fake (+ fake 2000))
                (invalidate! w)
                (steps 2))
              (set! now-ms real)
              (close-window! w)
              (and seen (equal? (car seen) (cadr seen))))))))
