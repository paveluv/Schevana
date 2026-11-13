;;; tests/units/behaviors.ss — the behaviors a style chooses, each a setting,
;;; today's feel by default: edges, title clicks, shading, outlines, menus, the
;;; mouse's documentation, scroll bars.

;;; behaviors a style chooses (each a setting, today's feel by default)

(for-each close-window! (windows))
(reset-theme!)
(steps 1)

;; win's region at its own point (lx, ly).
(define (region-at win lx ly)
  (window-region win (+ (window-x win) lx) (+ (window-y win) ly)))

;; A left drag on the screen from (x0, y0) to (x1, y1).
(define (drag-on! x0 y0 x1 y1)
  (inject! `(mouse-move ,x0 ,y0) `(mouse-down ,x0 ,y0 left 1)
           `(mouse-move ,x1 ,y1) `(mouse-up ,x1 ,y1 left))
  (steps 1))

(define (geometry w) (list (window-x w) (window-y w) (window-w w) (window-h w)))

(let ([w (open-window "Edges" 'size '(300 . 200) 'pos '(200 . 150))])
  (define (at)
    (map (lambda (p) (region-at w (car p) (cdr p)))
         (list (cons (- (window-w w) 3) 100) (cons (- (window-w w) 7) 100)
               (cons (- (window-w w) 3) (- (window-h w) 17)))))
  (check "the resize edges are settings: frame-edge wide, frame-corner long, \
          an edge of 0 none"
         (and (equal? (at) '(resize-r content resize-r))
              (begin (set-theme! 'frame-edge 9) (set-theme! 'frame-corner 20)
                     (equal? (at) '(resize-r resize-r resize-br)))
              (begin (set-theme! 'frame-edge 0)
                     (equal? (at) '(content content content)))))
  (reset-theme!)
  (close-window! w))

;; A style resizing from its top edge and corners, the window manager's
;; edges off.
(define (test-top-regions win)
  (let ([w (window-w win)])
    (list (list 'resize-tl 0 0 8 8) (list 'resize-tr (- w 8) 0 8 8)
          (list 'resize-t 8 0 (- w 16) 4))))
(define-style test-top "Top resizes"
  'frame-regions 'test-top-regions 'frame-edge 0)

(check "a style's regions move the clicks: its top edge and corners resize \
        from the top, the other sides staying"
       (let ([w (open-window "Top" 'size '(300 . 200) 'pos '(300 . 300)
                             'window-style 'test-top)])
         (steps 1)
         (let* ([g0 (geometry w)] [x (car g0)] [y (cadr g0)]
                [r (+ x (caddr g0))] [b (+ y (cadddr g0))])
           (drag-on! (+ x 100) (+ y 2) (+ x 100) (- y 28))
           (let ([g1 (geometry w)])
             (drag-on! (+ x 3) (- y 27) (- x 17) (- y 37))
             (let ([g2 (geometry w)])
               (drag-on! (- r 3) (- y 37) (+ r 17) (- y 47))
               (let ([g3 (geometry w)] [cursor (region-cursor w 'resize-t)]
                     [edge (region-at w (- (window-w w) 3) 100)])
                 (close-window! w)
                 (and (equal? g1 (list x (- y 30) (caddr g0)
                                       (+ (cadddr g0) 30)))
                      (equal? g2 (list (- x 20) (- y 40) (+ (caddr g0) 20)
                                       (+ (cadddr g0) 40)))
                      (equal? g3 (list (- x 20) (- y 50) (+ (caddr g0) 40)
                                       (+ (cadddr g0) 50)))
                      (= b (+ (cadr g3) (cadddr g3)))
                      (eq? cursor 'resize-ns) (eq? edge 'content))))))))

;; A left double click at screen point (x, y).
(define (double-click! x y)
  (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left)
           `(mouse-down ,x ,y left 2) `(mouse-up ,x ,y left))
  (steps 1))

(check "a double click on the title does what title-double-click names: \
        maximize (by default), minimize or nothing"
       (let ([w (open-window "Twice" 'size '(300 . 200) 'pos '(250 . 200))])
         (define (twice!)
           (double-click! (+ (window-x w) 150) (+ (window-y w) 10))
           (window-state w))
         (let* ([a (twice!)]
                [b (begin (restore-window! w)
                          (set-theme! 'title-double-click 'none)
                          (twice!))]
                [c (begin (set-theme! 'title-double-click 'minimize)
                          (twice!))])
           (reset-theme!)
           (close-window! w)
           (equal? (list a b c) '(maximized normal minimized)))))

;; A style with a window-menu button, a double click on which closes the
;; window (CDE's).
(define (test-menu-regions win) (list (list 'menu 4 4 20 20)))
(define-style test-menu "Menu button"
  'frame-regions 'test-menu-regions 'button-double-click '((menu . close)))

(check "a press on a frame's menu button opens the window's menu; a double \
        click there does what button-double-click names"
       (let* ([w (open-window "Menu button" 'size '(300 . 200)
                              'pos '(250 . 200) 'window-style 'test-menu)]
              [x (+ (window-x w) 10)] [y (+ (window-y w) 10)])
         (steps 1)
         (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1))
         (steps 1)
         (let ([opened (and *menu*
                            (equal? (menu-tag *menu*) (cons 'window w)))])
           (inject! `(mouse-up ,x ,y left) `(mouse-down ,x ,y left 2)
                    `(mouse-up ,x ,y left))
           (steps 1)
           (and opened (not *menu*) (not (memq w (windows)))))))

;; A window counting its draws and resizes.
(define (counting-window title . opts)
  (let ([n (vector 0 0)])
    (values (apply open-window title 'size '(300 . 200) 'pos '(250 . 200)
                   'draw (lambda (win w h)
                           (vector-set! n 0 (+ 1 (vector-ref n 0))))
                   'resize (lambda (win w h)
                             (vector-set! n 1 (+ 1 (vector-ref n 1))))
                   opts)
            n)))

(check "a shaded window is its frame's top and bottom: its content is not \
        drawn, it keeps its content size, its app hears no resize, and a \
        move keeps it shaded"
       (let-values ([(w n) (counting-window "Shade me")])
         (steps 1)
         (let-values ([(cw ch) (window-content-size w)]
                      [(l t r b) (frame-insets w)])
           (shade-window! w)
           (vector-set! n 0 0)
           (invalidate!)
           (steps 1)
           (let ([shaded (list (shaded? w) (window-h w) (vector-ref n 0))])
             (move-window! w 260 220)
             (let ([moved (list (shaded? w) (window-h w))])
               (unshade-window! w)
               (steps 1)
               (let-values ([(cw2 ch2) (window-content-size w)])
                 (close-window! w)
                 (and (equal? shaded (list #t (+ t b) 0))
                      (equal? moved (list #t (+ t b)))
                      (= cw cw2) (= ch ch2) (zero? (vector-ref n 1))
                      (> (vector-ref n 0) 0))))))))

;; A style with a shade button at its top left.
(define (test-shade-regions win) (list (list 'shade 4 4 20 20)))
(define-style test-shade "Shade button" 'frame-regions 'test-shade-regions)

(check "a window shades by its style's triggers: a double click on the \
        title, the wheel on it (up shades, down unshades), a shade button, \
        the window menu; maximizing unshades"
       (let-values ([(w n) (counting-window "Triggers")])
         (define (title-x) (+ (window-x w) 150))
         (define (title-y) (+ (window-y w) 10))
         (define (wheel! dy)
           (inject! `(mouse-move ,(title-x) ,(title-y)) `(wheel 0 ,dy))
           (steps 1)
           (shaded? w))
         (set-theme! 'title-double-click 'shade)
         (double-click! (title-x) (title-y))
         (let ([a (shaded? w)])
           (double-click! (title-x) (title-y))
           (let ([b (shaded? w)])
             (set-theme! 'title-wheel 'shade)
             (let* ([c (wheel! 1)] [d (wheel! -1)])
               (reset-theme!)
               (let ([e (wheel! 1)])   ; title-wheel none again: nothing
                 (close-window! w)
                 (let ([s (open-window "Button" 'size '(300 . 200)
                                       'pos '(250 . 200)
                                       'window-style 'test-shade)])
                   (steps 1)
                   (drag-on! (+ (window-x s) 10) (+ (window-y s) 10)
                             (+ (window-x s) 10) (+ (window-y s) 10))
                   (let ([f (shaded? s)])
                     (inject! `(mouse-move ,(+ (window-x s) 150)
                                           ,(+ (window-y s) 10))
                              `(mouse-down ,(+ (window-x s) 150)
                                           ,(+ (window-y s) 10) right 1))
                     (steps 1)
                     (let ([offered (map car (filter pair?
                                                     (menu-entries *menu*)))])
                       (close-menu!)
                       (maximize-window! s)
                       (let ([g (list (shaded? s) (window-state s))])
                         (close-window! s)
                         (and (equal? (list a b c d e f) '(#t #f #t #f #f #t))
                              (member "Unshade" offered)
                              (equal? g '(#f maximized)))))))))))))

(check "the window menu offers Shade only where the style shades"
       (let ([w (open-window "Plain" 'size '(300 . 200) 'pos '(250 . 200))])
         (open-window-menu w 300 220)
         (let ([offered (map car (filter pair? (menu-entries *menu*)))])
           (close-menu!)
           (close-window! w)
           (not (member "Shade" offered)))))

;; A full render of the screen now.
(define (full-render)
  (make-picture (screen-bytes) *canvas-pw* *canvas-ph*))

;; Is the screen what a full render draws?
(define (screen-whole?)
  (let ([ref (full-render)])
    (let ([d (max-diff (shown-picture) ref)]) (picture-free! ref) (zero? d))))

(check "an outline drag leaves the window until the release lands it in \
        the outline, which the desktop draws; each move asks for a frame"
       (let ([w (open-window "Outline" 'size '(300 . 200) 'pos '(250 . 200))])
         (set-theme! 'drag-feedback 'outline)
         (steps 1)
         (let* ([g (geometry w)] [x0 (car g)] [y0 (cadr g)]
                [ww (caddr g)] [wh (cadddr g)]
                [tx (+ x0 150)] [ty (+ y0 10)])
           (wm-mouse-move tx ty)
           (wm-mouse-down tx ty 'left 1)
           (steps 1)
           (set! *dirty* #f)
           (wm-mouse-move (+ tx 40) (+ ty 30))
           (let ([first *dirty*] [o1 *drag-outline*] [g1 (geometry w)])
             (set! *dirty* #f)
             (wm-mouse-move (+ tx 60) (+ ty 50))
             (let ([second *dirty*])
               (steps 1)
               (let* ([whole1 (screen-whole?)]
                      [with (full-render)]
                      [without (fluid-let ([*drag-outline* #f]) (full-render))]
                      [drawn (> (max-diff with without) 0)])
                 (picture-free! with)
                 (picture-free! without)
                 (wm-mouse-up (+ tx 60) (+ ty 50) 'left)
                 (steps 1)
                 (let ([landed (geometry w)] [whole2 (screen-whole?)])
                   (reset-theme!)
                   (close-window! w)
                   (and (equal? g1 g)
                        (equal? o1 (list (+ x0 40) (+ y0 30) ww wh))
                        first second
                        drawn whole1 whole2 (not *drag-outline*)
                        (equal? landed (list (+ x0 60) (+ y0 50) ww wh))))))))))

(check "an outline resize lands the outline's size at the release"
       (let ([w (open-window "Outline" 'size '(300 . 200) 'pos '(250 . 200))])
         (set-theme! 'drag-feedback 'outline)
         (steps 1)
         (let* ([g (geometry w)] [r (+ (car g) (caddr g) -2)]
                [b (+ (cadr g) (cadddr g) -2)])
           (inject! `(mouse-move ,r ,b) `(mouse-down ,r ,b left 1)
                    `(mouse-move ,(+ r 30) ,(+ b 20)))
           (steps 1)
           (let ([during (geometry w)])
             (inject! `(mouse-up ,(+ r 30) ,(+ b 20) left))
             (steps 1)
             (let ([after (geometry w)])
               (reset-theme!)
               (close-window! w)
               (and (equal? during g)
                    (equal? after (list (car g) (cadr g) (+ (caddr g) 30)
                                        (+ (cadddr g) 20)))))))))

(check "raise-on-click #f: a press in a window's content gives it the \
        keyboard without raising it; a press on its title raises it"
       (let* ([a (open-window "Under" 'size '(300 . 200) 'pos '(200 . 200))]
              [b (open-window "Over" 'size '(300 . 200) 'pos '(350 . 260))]
              [press! (lambda (x y)
                        (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                                 `(mouse-up ,x ,y left))
                        (steps 1)
                        (list (focused-window) (car (windows))))])
         (steps 1)
         (set-theme! 'raise-on-click #f)
         (let* ([content (press! (+ (window-x a) 40) (+ (window-y a) 100))]
                [title (press! (+ (window-x a) 150) (+ (window-y a) 10))])
           (raise-window! b)
           (reset-theme!)
           (let ([default (press! (+ (window-x a) 40) (+ (window-y a) 100))])
             (close-window! a)
             (close-window! b)
             (and (equal? content (list a b)) (equal? title (list a a))
                  (equal? default (list a a)))))))

;; The canvas's pixel at the device pixel (x, y).
(define (device-pixel x y)
  (void)
  (pixel-at (screen-picture) x y))

(define (inverted p) (fxior #xff000000 (fxxor (fxand p #xffffff) #xffffff)))

(check "the bell flashes the screen (or the focused window) inverted for \
        100 ms, at 100 and 200 %, then the screen is as it was; none rings \
        nothing"
       (let* ([real now-ms] [t (now-ms)]
              [w (open-window "Bell" 'size '(300 . 200) 'pos '(250 . 200))])
         (set! now-ms (lambda () t))
         (let ([ok
                (for-all
                 (lambda (pct)
                   (set-theme! 'scale pct)
                   (steps 2)
                   (let* ([s *scale*]
                          [in (list (exact (round (* s 300)))
                                    (exact (round (* s 300))))]
                          [out (list (exact (round (* s 60)))
                                     (exact (round (* s 600))))]
                          [px (lambda (p) (apply device-pixel p))]
                          [before (map px (list in out))])
                     (define (rung how)
                       (set-theme! 'bell how)
                       (steps 1)
                       (bell)
                       (steps 1)
                       (let ([flash (map px (list in out))])
                         (set! t (+ t 99))
                         (steps 1)
                         (let ([still (px in)])
                           (set! t (+ t 1))
                           (steps 2)
                           (list flash still (map px (list in out))
                                 (screen-whole?)))))
                     (let ([screen (rung 'screen)] [window (rung 'window)]
                           [none (rung 'none)])
                       (and (equal? (car screen) (map inverted before))
                            (= (cadr screen) (inverted (car before)))
                            (equal? (caddr screen) before) (cadddr screen)
                            (equal? (car window) (list (inverted (car before))
                                                       (cadr before)))
                            (equal? (caddr window) before) (cadddr window)
                            (equal? (car none) before)))))
                 '(100 200))])
           (set! now-ms real)
           (reset-theme!)
           (set-theme! 'scale 0)
           (steps 1)
           (close-window! w)
           ok)))

;; The middle of the open menu's entry labeled label.
(define (menu-entry-point label)
  (let* ([i (list-index (lambda (e)
                          (and (pair? e)
                               (string=? (menu-label-text (car e)) label)))
                        (menu-entries *menu*))]
         [a (assv i (placed-menu-areas *menu*))])
    (values (+ (cadr a) (quotient (cadddr a) 2))
            (+ (caddr a) (quotient (list-ref a 4) 2)))))

(check "menu-choose release: a menu opened by a press chooses the entry the \
        button is released over; click (today's) leaves it open"
       (let ([w (open-window "Menus" 'size '(300 . 200) 'pos '(250 . 200))])
         (define (press-drag-release!)
           (let ([tx (+ (window-x w) 150)] [ty (+ (window-y w) 10)])
             (inject! `(mouse-move ,tx ,ty) `(mouse-down ,tx ,ty right 1))
             (steps 1)
             (let-values ([(mx my) (menu-entry-point "Minimize")])
               (inject! `(mouse-move ,mx ,my) `(mouse-up ,mx ,my right))
               (steps 1)
               (let ([r (list (window-state w) (and *menu* #t))])
                 (close-menu!)
                 (focus-window! w)
                 (steps 1)
                 r))))
         (let ([click (press-drag-release!)])
           (set-theme! 'menu-choose 'release)
           (let ([release (press-drag-release!)])
             (reset-theme!)
             (close-window! w)
             (and (equal? click '(normal #t))
                  (equal? release '(minimized #f)))))))

(check "menu-choose release: released over its opener the menu stays open, \
        and a click then chooses"
       (let ([w (open-window "Sticky" 'size '(300 . 200) 'pos '(250 . 200))])
         (set-theme! 'menu-choose 'release)
         (let ([tx (+ (window-x w) 150)] [ty (+ (window-y w) 10)])
           (inject! `(mouse-move ,tx ,ty) `(mouse-down ,tx ,ty right 1)
                    `(mouse-up ,tx ,ty right))
           (steps 1)
           (let ([open (and *menu* #t)])
             (let-values ([(mx my) (menu-entry-point "Minimize")])
               (inject! `(mouse-move ,mx ,my) `(mouse-down ,mx ,my left 1))
               (steps 1)
               (let ([held (list (window-state w) (and *menu* #t))])
                 (inject! `(mouse-up ,mx ,my left))
                 (steps 1)
                 (let ([done (window-state w)])
                   (reset-theme!)
                   (close-window! w)
                   (and open (equal? held '(normal #t))
                        (eq? done 'minimized)))))))))

(check "menu-blink: a chosen entry blinks (off, on) n times, 60 ms a phase, \
        then the menu closes and its action runs"
       (let ([real now-ms] [t (now-ms)] [ran 0] [drawn #f])
         (set! now-ms (lambda () t))
         (set-theme! 'menu-blink 2)
         (set-theme! 'ui-draw-highlight
                     (lambda (x y w h flags) (set! drawn #t)))
         (open-menu! 300 300 (list (cons "One" (lambda () (set! ran (+ ran 1))))
                                   (cons "Two" void)))
         (steps 1)
         (let-values ([(x y) (menu-entry-point "One")])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                    `(mouse-up ,x ,y left))
           (steps 1)
           (let ([phases   ; in order: map may call in any
                  (let loop ([ats '(30 60 60 60 30)])
                    (if (null? ats)
                        '()
                        (begin (set! t (+ t (car ats)))
                               (set! drawn #f)
                               (steps 1)
                               (cons (list ran (and *menu* #t) drawn)
                                     (loop (cdr ats))))))])
             (set! now-ms real)
             (reset-theme!)
             (equal? phases '((0 #t #f) (0 #t #t) (0 #t #f) (0 #t #t)
                              (1 #f #f)))))))

(check "menu-hover outline: the highlight is told outline, and pressed while \
        a button is held on the entry; drawn as a 1-pixel box, then filled"
       (let ([seen '()])
         (set-theme! 'ui-draw-highlight
                     (lambda (x y w h flags) (set! seen flags)))
         (set-theme! 'menu-hover 'outline)
         (set-theme! 'menu-choose 'release)
         (open-menu! 300 300 (list (cons "One" void) (cons "Two" void)))
         (steps 1)
         (let-values ([(x y) (menu-entry-point "One")])
           (inject! `(mouse-move ,x ,y))
           (steps 1)
           (let ([hover seen])
             (inject! `(mouse-down ,x ,y left 1))
             (steps 1)
             (let ([held seen])
               (inject! `(mouse-up ,x ,y left))
               (steps 1)
               (reset-theme!)
               (let ([box (lambda (flags)
                            (pixel-rows (image 8 6 1
                                               (lambda ()
                                                 (fill-box 0 0 8 6 #x808080)
                                                 (ui-draw-highlight 1 1 6 4
                                                                    flags)))
                                        (list (cons #xff808080 #\.)
                                              (cons (color->pixel 'text)
                                                    #\t))))])
                 (and (equal? hover '(outline)) (equal? held '(outline pressed))
                      (not *menu*)
                      (equal? (box '(outline))
                              '("........" ".tttttt." ".t....t." ".t....t."
                                ".tttttt." "........"))
                      (equal? (box '(outline pressed))
                              '("........" ".tttttt." ".tttttt." ".tttttt."
                                ".tttttt." "........")))))))))

;; Genera's recipe for a window it is not using: its frame-over grays the
;; content with a sparse stipple of ink on clear paper.
(define (test-gray-over win x y w h focused? hover pressed)
  (unless focused?
    (let-values ([(cx cy cw ch) (content-rect win)])
      (fill-box cx cy cw ch (stipple 'text #f "#..." "...." "...." "....")))))
(define-style test-gray "Gray when unfocused" 'frame-over 'test-gray-over)

(check "an unfocused window is drawn by its style: a stipple of clear paper \
        over its content grays one pixel in sixteen, lined up with the \
        screen; the focused one is untouched"
       (let* ([a (open-window "Unfocused" 'size '(200 . 120) 'pos '(201 . 203)
                              'window-style 'test-gray
                              'draw (lambda (win w h)
                                      (fill-box 0 0 w h #x000000)))]
              [b (open-window "Focused" 'size '(200 . 120) 'pos '(601 . 203)
                              'window-style 'test-gray
                              'draw (lambda (win w h)
                                      (fill-box 0 0 w h #x000000)))])
         (steps 1)
         (let ([ink (color->pixel 'text)])
           (define (dots win)   ; the inked device pixels of 40 × 40 inside
             (let-values ([(cx cy cw ch) (content-rect win)])
               (let loop ([i 0] [acc '()])
                 (if (= i 1600)
                     (reverse acc)
                     (let ([x (+ cx 10 (mod i 40))]
                           [y (+ cy 10 (quotient i 40))])
                       (loop (+ i 1)
                             (if (= (canvas-pixel x y) ink)
                                 (cons (cons (mod x 4) (mod y 4)) acc)
                                 acc)))))))
           (let ([da (dots a)] [db (dots b)])
             (close-window! a)
             (close-window! b)
             (and (= (length da) 100) (null? db)
                  (for-all (lambda (p) (equal? p '(0 . 0))) da))))))

;; The device rows that differ between two of canvas-bytes' copies.
(define (rows-between a b)
  (let ([stride (* 4 *canvas-pw*)])
    (filter (lambda (y)
              (not (bytevector=? (bytevector-copy-range a y stride)
                                 (bytevector-copy-range b y stride))))
            (iota (quotient (bytevector-length a) stride)))))

(define (bytevector-copy-range bv row stride)
  (let ([out (make-bytevector stride)])
    (bytevector-copy! bv (* row stride) out 0 stride)
    out))

;; A window of kit widgets, drawn by draw (ui w h).
(define (kit-window title draw)
  (let ([ui (make-ui)])
    (apply open-window title 'size '(400 . 200) 'pos '(300 . 200)
           'draw (lambda (win w h)
                   (ui-begin! ui) (draw ui w h) (ui-end! ui w h))
           (ui-handlers ui))))

(define (doc-at x y)
  (inject! `(mouse-move ,x ,y))
  (steps 1)
  (mouse-doc))

(check "(mouse-doc) is what each button does under the pointer: on a \
        title, a close button, a kit button (its label), a text box, a \
        taskbar button, the desktop"
       (let ([w (kit-window "Docs"
                            (lambda (ui w h)
                              (ui-button ui 'b 20 20 100 30 "Button" void)
                              (ui-text-field ui 't 20 70 200 30 "text"
                                             void)))])
         (steps 2)
         (let*-values ([(cx cy cw ch) (content-rect w)]
                       [(title) (doc-at (+ (window-x w) 200)
                                        (+ (window-y w) 10))]
                       [(close) (doc-at (+ (window-x w) 18)
                                        (+ (window-y w) 15))]
                       [(button) (doc-at (+ cx 50) (+ cy 35))]
                       [(text) (doc-at (+ cx 50) (+ cy 85))]
                       [(taskbar)
                        (let ([a (assq w (with-place 'bar taskbar-areas))])
                          (doc-at (+ (cadr a) 20) (+ (caddr a) 10)))]
                       [(desktop) (doc-at 100 600)])
           (close-window! w)
           (and (equal? title '((L . "Move") (L2 . "Maximize")
                                (R . "Window menu")))
                (equal? close '((L . "Close")))
                (equal? button '((L . "Button")))
                (equal? text '((L . "Place the caret")
                               (L2 . "Select a word")))
                (equal? taskbar '((L . "Focus or minimize") (M . "Close")
                                  (R . "Window menu")))
                (equal? desktop '((L . "Unfocus") (R . "Apps")))))))

;; Two tables and a tree with the same columns, each 50 high, from the
;; top; cells: (id key x w) of each first row's cells, as drawn.
(check "a column's handle: the pointer resize-ew and \"L: Resize column, \
        L2: Default width\" over it; a drag sets the width, the cells \
        follow, the minimum holds; a double click sets back the default; \
        the widths are per table or tree"
       (let* ([columns '((a "A" 100) (b "B" 100) (c "C" 100))]
              [cells '()] [ui #f]
              [cell (lambda (id)
                      (lambda (row key x y w h flags)
                        (when (eqv? row 1)
                          (set! cells (cons (list id key x w) cells)))))]
              [w (kit-window "Columns"
                             (lambda (u w h)
                               (set! ui u)
                               (set! cells '())
                               (ui-table u 't 0 0 w 50 columns '(1 2) #f void
                                         (cell 't))
                               (ui-table u 'u 0 50 w 50 columns '(1 2) #f
                                         void (cell 'u))
                               (ui-tree u 'r 0 100 w 50 columns '(1)
                                        (lambda (n) '()) #f void (cell 'r))))])
         (steps 2)
         (let*-values ([(cx cy cw ch) (content-rect w)]
                       [(hy) (+ cy (quotient (ui-table-header-height) 2))]
                       [(over) (doc-at (+ cx 101) hy)]
                       [(shape) (window-ref w 'cursor 'arrow)]
                       [(room) (ui-table-room cw)])
           (define (widths id)
             (map caddr (ui-table-columns ui id columns)))
           (define (drag! x0 x1 y)
             (inject! `(mouse-move ,x0 ,y) `(mouse-down ,x0 ,y left 1)
                      `(mouse-move ,x1 ,y) `(mouse-up ,x1 ,y left))
             (steps 2))
           (drag! (+ cx 101) (+ cx 141) hy)
           (let ([dragged (widths 't)] [drawn (reverse cells)]
                 [ry (+ cy 100 (quotient (ui-table-header-height) 2))])
             (drag! (+ cx 141) (+ cx 10) hy)
             (let ([narrow (widths 't)])
               (inject! `(mouse-down ,(+ cx (car narrow)) ,hy left 2)
                        `(mouse-up ,(+ cx (car narrow)) ,hy left))
               (steps 2)
               (let ([reset (widths 't)])
                 (drag! (+ cx 199) (+ cx 179) ry)
                 (let ([tree (list (widths 't) (widths 'u) (widths 'r))])
                   (close-window! w)
                   (steps 1)
                   (and (eq? shape 'resize-ew)
                        (equal? over '((L . "Resize column")
                                       (L2 . "Default width")))
                        (equal? dragged '(140 100 100))
                        ;; the last takes what the others leave
                        (equal? (filter (lambda (c) (eq? (car c) 't)) drawn)
                                `((t a 0 140) (t b 140 100)
                                  (t c 240 ,(max 100 (- room 240)))))
                        (equal? (filter (lambda (c) (eq? (car c) 'u)) drawn)
                                `((u a 0 100) (u b 100 100)
                                  (u c 200 ,(max 100 (- room 200)))))
                        (equal? narrow (list (ui-table-column-min) 100 100))
                        (equal? reset '(100 100 100))
                        (equal? tree '((100 100 100) (100 100 100)
                                       (100 80 100)))))))))))

(check "with 'resize 'pair a drag moves the width between the two \
        columns beside the handle, each at least the minimum, and a double \
        click sets back both; Mac and Windows shift the rest along, as the \
        Finder and Explorer do, the others resize the pair"
       (let* ([columns '((a "A" 100) (b "B" 100) (c "C" 100))] [ui #f]
              [w (kit-window "Pair"
                             (lambda (u w h)
                               (set! ui u)
                               (ui-table u 't 0 0 w 50 columns '(1 2) #f void
                                         (lambda (row key x y w h flags) #f)
                                         'resize 'pair)))])
         (steps 2)
         (let*-values ([(cx cy cw ch) (content-rect w)]
                       [(hy) (+ cy (quotient (ui-table-header-height) 2))])
           (define (widths)
             (map caddr (ui-table-columns ui 't columns)))
           (define (drag! x0 x1)
             (inject! `(mouse-move ,x0 ,hy) `(mouse-down ,x0 ,hy left 1)
                      `(mouse-move ,x1 ,hy) `(mouse-up ,x1 ,hy left))
             (steps 2))
           (drag! (+ cx 101) (+ cx 141))
           (let ([wider (widths)])
             (drag! (+ cx 141) (+ cx 290))
             (let ([most (widths)])
               (inject! `(mouse-down ,(+ cx (car most)) ,hy left 2)
                        `(mouse-up ,(+ cx (car most)) ,hy left))
               (steps 2)
               (let ([reset (widths)] [least (ui-table-column-min)])
                 (close-window! w)
                 (steps 1)
                 (and (equal? wider '(140 60 100))
                      (equal? most (list (- 200 least) least 100))
                      (equal? reset '(100 100 100))
                      (equal? (map (lambda (style)
                                     (with-style style
                                       (lambda () (theme 'table-resize))))
                                   '(mac windows cons genera))
                              '(shift shift pair pair)))))))))

(check "columns dragged narrower than the table leave the room to the \
        last, so the headings reach the edge; wider, they stay"
       (let ([columns '((a "A" 60) (b "B" 100 right "tip"))])
         (and (equal? (ui-table-filled columns 300)
                      '((a "A" 60) (b "B" 240 right "tip")))
              (equal? (ui-table-filled columns 120) columns)
              (equal? (ui-table-filled '() 100) '()))))

;; The columns a heading inks, (first . last), drawn 200 wide in style
;; with flags and dir; its bottom line left out.
;; The line between two headings is there at rest, under the pointer
;; in the accent, wider: found before the pointer changes.
(check "a divider marks each column's handle at rest, and is the accent \
        under the pointer"
       (let ([draw (lambda (flags)
                     (let* ([img (image 20 30 1
                                        (lambda ()
                                          (fill-box 0 0 20 30 'bg-1)
                                          (ui-draw-table-divider 10 0 30
                                                                 flags)))]
                            [bg (pixel-at img 2 15)]
                            [mid (pixel-at img 10 15)]
                            [left (pixel-at img 9 15)])
                       (picture-free! img)
                       (list (not (= mid bg)) (not (= left bg)) mid)))])
         (let ([rest (draw '())] [hot (draw '(hover))])
           (and (car rest) (not (cadr rest))
                (car hot) (cadr hot)
                (= (caddr hot) (color->pixel 'accent))))))

(check "where dividers show by the style's table-dividers: always at \
        rest, hover over the headings, handle only under the pointer"
       (with-test-styles
        (lambda ()
          (let ([shown (lambda (mode)
                         (define-style test-dividers "Test"
                           'table-dividers mode)
                         (set-style! 'test-dividers)
                         (map (lambda (args)
                                (apply ui-table-divider-shown? args))
                              '((#f #f) (#t #f) (#f #t))))])
            (and (equal? (shown 'always) '(#t #t #t))
                 (equal? (shown 'hover) '(#f #t #t))
                 (equal? (shown 'handle) '(#f #f #t))
                 (with-style 'mac
                   (lambda () (eq? (theme 'table-dividers) 'always))))))))

(check "Genera's removable tag under the mouse boxes its × alone, not \
        the tag: what a click removes"
       (with-style 'genera
         (lambda ()
           (let* ([draw (lambda (flags)
                          (image 120 30 1
                                 (lambda ()
                                   (fill-box 0 0 120 30 'bg-1)
                                   (ui-draw-chip 10 5 100 20 flags "tag"))))]
                  [rest (draw '(removable))] [hot (draw '(removable hover))]
                  [a (cdr (assq 'remove (ui-chip-areas 10 5 100 20)))]
                  ;; the columns where hovering changed a pixel
                  [changed (filter (lambda (x)
                                     (exists (lambda (y)
                                               (not (= (pixel-at rest x y)
                                                       (pixel-at hot x y))))
                                             (iota 30)))
                                   (iota 120))])
             (let ([r (and (pair? changed)
                           (>= (apply min changed) (- (car a) 3)))])
               (picture-free! rest)
               (picture-free! hot)
               r)))))

(define (heading-ink style flags dir)
  (with-style style
    (lambda ()
      (let* ([img (image 200 30 1
                         (lambda ()
                           (fill-box 0 0 200 30 'bg-1)
                           (ui-draw-table-header 0 0 200 30 flags "ms/s"
                                                 dir)))]
             [bg (pixel-at img 199 2)]
             [xs (filter (lambda (x)
                           (exists (lambda (y) (not (= (pixel-at img x y) bg)))
                                   (iota 27)))
                         (iota 200))])
        (picture-free! img)
        (cons (apply min xs) (apply max xs))))))

(define (cell-ink style flags)
  (with-style style
    (lambda ()
      (let* ([img (image 200 30 1
                         (lambda ()
                           (fill-box 0 0 200 30 'bg-1)
                           (ui-draw-cell 0 0 200 30 flags "ms/s")))]
             [bg (pixel-at img 199 2)]
             [xs (filter (lambda (x)
                           (exists (lambda (y) (not (= (pixel-at img x y) bg)))
                                   (iota 30)))
                         (iota 200))])
        (picture-free! img)
        (cons (apply min xs) (apply max xs))))))

(check "a heading lines up with its column's cells: from the left, its sort \
        arrow after it; over right-aligned ones (right), at the right, its \
        arrow before it: the kit's, Genera's and Cons's"
       (for-all
        (lambda (style)
          (let ([left (heading-ink style '() #f)]
                [left-sorted (heading-ink style '() 'down)]
                [right (heading-ink style '(right) #f)]
                [right-sorted (heading-ink style '(right) 'down)]
                [cells (cell-ink style '())]
                [right-cells (cell-ink style '(right))])
            (and (<= (abs (- (car left) (car cells))) 2) (< (cdr left) 100)
                 (= (car left-sorted) (car left))
                 (> (cdr left-sorted) (cdr left))
                 (<= (abs (- (cdr right) (cdr right-cells))) 2)
                 (> (car right) 100)
                 (= (cdr right-sorted) (cdr right))
                 (< (car right-sorted) (car right)))))
        '(mac genera cons)))

(check "a tree's headings: with 'on-sort a press on one calls it with its \
        key, the one 'sort names shows its direction; a column's flags are \
        its heading's and its cells'; without 'on-sort no heading takes a \
        press"
       (with-test-styles
        (lambda ()
          (let ([heads '()] [cells '()] [pressed #f] [ui #f]
                [columns '((a "A" 100) (b "B" 100 right))])
            (define-style test-heads "Test"
              'ui-draw-table-header
              (lambda (x y w h flags label dir)
                (set! heads (cons (list label flags dir) heads))))
            (set-style! 'test-heads)
            (let ([w (kit-window "Heads"
                       (lambda (u w h)
                         (set! ui u)
                         (set! heads '())
                         (set! cells '())
                         ;; drawn first: its headings are found after s's
                         (ui-tree u 'q 0 90 w 80 columns '(1) (lambda (n) '())
                                  #f void (lambda cell #f))
                         (ui-tree u 's 0 0 w 80 columns '(1) (lambda (n) '())
                                  #f void
                                  (lambda (n key x y w h flags)
                                    (set! cells (cons (cons key flags) cells)))
                                  'sort '(b . down)
                                  'on-sort (lambda (k) (set! pressed k)))))])
              (steps 2)
              (let-values ([(cx cy cw ch) (content-rect w)])
                (let* ([b-head (assoc "B" heads)]
                       [a-cell (cdr (assq 'a cells))]
                       [b-cell (cdr (assq 'b cells))]
                       [y (+ cy (quotient (ui-table-header-height) 2))])
                  (inject! `(mouse-move ,(+ cx 150) ,y)
                           `(mouse-down ,(+ cx 150) ,y left 1)
                           `(mouse-up ,(+ cx 150) ,y left))
                  (steps 2)
                  (close-window! w)
                  (steps 1)
                  (and (eq? pressed 'b)
                       (memq 'right (cadr b-head)) (eq? (caddr b-head) 'down)
                       (not (caddr (assoc "A" heads)))
                       (memq 'right b-cell) (not (memq 'right a-cell))
                       (ui-find ui '(s header a))
                       (not (ui-find ui '(q header a)))))))))))

;; A style whose shade button words itself.
(define (test-words-regions win)
  (list (list 'shade 30 4 20 20 '((L . "Roll up") (R . "Nothing")))))
(define-style test-words "Own words" 'frame-regions 'test-words-regions)

(check "a style's regions word themselves, and the actions its settings \
        name read: a shading title, a menu button closing on a double click"
       (let ([w (open-window "Words" 'size '(300 . 200) 'pos '(250 . 200)
                             'window-style 'test-menu)]
             [v (open-window "Own" 'size '(300 . 200) 'pos '(600 . 200)
                             'window-style 'test-words)])
         (override! 'title-double-click 'shade)
         (override! 'title-wheel 'shade)
         (steps 1)
         (let* ([title (doc-at (+ (window-x w) 150) (+ (window-y w) 10))]
                [menu (doc-at (+ (window-x w) 10) (+ (window-y w) 10))]
                [own (doc-at (+ (window-x v) 40) (+ (window-y v) 10))])
           (reset-theme!)
           (close-window! w)
           (close-window! v)
           (and (equal? title '((L . "Move") (L2 . "Shade")
                                (R . "Window menu") (W . "Shade")))
                (equal? menu '((L . "Window menu") (L2 . "Close")))
                (equal? own '((L . "Roll up") (R . "Nothing")))))))

(check "with mouse-doc on the top bar shows it, and a move between regions \
        of other words changes the bar's rows alone, one between regions of \
        the same words nothing"
       (let ([w (kit-window "Areas"
                            (lambda (ui w h)
                              (ui-area ui 'a 0 0 100 100 void #f
                                       'doc '((L . "One")))
                              (ui-area ui 'b 100 0 100 100 void #f
                                       'doc '((L . "Two")))
                              (ui-area ui 'c 200 0 100 100 void #f
                                       'doc '((L . "Two")))))])
         (set-theme! 'mouse-doc #t)
         (steps 2)
         (let-values ([(cx cy cw ch) (content-rect w)])
           (define (rows-after-move x)
             (let ([before (canvas-bytes)])
               (inject! `(mouse-move ,x ,(+ cy 50)))
               (steps 1)
               (rows-between before (canvas-bytes))))
           (rows-after-move (+ cx 50))
           (let* ([shown (mouse-doc)]
                  [text (mouse-doc-text shown)]
                  [other (rows-after-move (+ cx 150))]
                  [same (rows-after-move (+ cx 250))])
             (reset-theme!)
             (close-window! w)
             (and (equal? shown '((L . "One"))) (equal? text "L: One")
                  (pair? other)
                  (for-all (lambda (y) (< y (* *scale* (topbar-height))))
                           other)
                  (null? same))))))

(check "a scroll bar is on the right by default, on the left where the \
        style says so"
       (let ([w (scroll-window "Sides")])
         (steps 1)
         (let ([right (bar-x w)])
           (set-theme! 'scrollbar-side 'left)
           (steps 1)
           (let ([left (bar-x w)])
             (reset-theme!)
             (close-window! w)
             (and (= right (- 300 (ui-scrollbar-width))) (= left 0))))))

(check "a scroll bar shown on hover appears while the pointer is over the \
        view, over its content, which does not move"
       (let ([w (scroll-window "Hover")])
         (set-theme! 'scrollbar-show 'hover)
         (inject! '(mouse-move 100 700))
         (steps 2)
         (let-values ([(cx cy cw ch) (content-rect w)])
           (let* ([row (lambda () (map (lambda (dx) (canvas-pixel (+ cx dx)
                                                                  (+ cy 5)))
                                       '(10 100 200)))]
                  [away (list (bar-x w) (row))])
             (inject! `(mouse-move ,(+ cx 100) ,(+ cy 100)))
             (steps 2)
             (let ([over (list (bar-x w) (row))])
               (reset-theme!)
               (close-window! w)
               (and (not (car away)) (car over)
                    (equal? (cadr away) (cadr over))))))))

;; Medley's scroll bars: a 24-pixel margin at the left of the frame,
;; clear but for the bar while the pointer is there.
(define (test-out-insets win) (values 24 (title-height) 0 0))
(define (test-out-regions win)
  (list (list 'scrollbar 0 (title-height) 24
              (- (window-h win) (title-height)))))
(define (test-out-over win x y w h focused? hover pressed)
  (ui-frame-scrollbar win))
(define-style test-out "Outside scroll bars"
  'frame-insets 'test-out-insets 'frame-regions 'test-out-regions
  'frame-over 'test-out-over 'scrollbar-side 'outside 'scrollbar-width 24
  'scrollbar-show 'hover)

(check "a scroll bar outside the window: its margin clear, the bar there \
        while the pointer is, a press there the app's (it scrolls)"
       (let* ([w (scroll-window "Outside" 'window-style 'test-out)]
              [mx (+ (window-x w) 12)] [my (+ (window-y w) 150)])
         (inject! '(mouse-move 100 700))
         (steps 2)
         (let ([clear (canvas-pixel mx (+ (window-y w) 50))])
           (minimize-window! w)
           (steps 2)
           (let ([desk (canvas-pixel mx (+ (window-y w) 50))])
             (focus-window! w)
             (inject! `(mouse-move ,mx ,my))
             (steps 2)
             (let ([region (window-region w mx my)] [at (bar-x w)]
                   [shown (canvas-pixel mx (+ (window-y w) 50))])   ; thumb
               (inject! `(mouse-down ,mx ,my left 1) `(mouse-up ,mx ,my left))
               (steps 2)
               (let ([off (car (ui-memo (window-ref w 'ui) 'v '(0 . 0)))])
                 (close-window! w)
                 (and (= clear desk) (eq? region 'scrollbar)
                      (not (= shown desk)) (= at -24) (> off 0))))))))

;;; the verifier's findings on the behaviors switched on

(check "behavior settings survive a save and load, each of its kind; a \
        value of another kind is dropped"
       (let ([set '((title-double-click . shade) (raise-on-click . #f)
                    (bell . screen) (mouse-doc . #t) (frame-edge . 8)
                    (menu-blink . 2) (title-wheel . shade)
                    (drag-feedback . outline) (scrollbar-side . left)
                    (button-double-click . ((menu . close))))])
         (for-each (lambda (kv) (override! (car kv) (cdr kv))) set)
         (theme-file-save!)
         (reset-theme!)
         (theme-file-load!)
         (let ([got (map (lambda (kv) (theme (car kv))) set)])
           (reset-theme!)
           (theme-file-save!)
           (and (equal? got (map cdr set))
                (not (theme-file-valid-value? 'bell #t))
                (not (theme-file-valid-value? 'frame-edge 'wide))
                (not (theme-file-valid-value? 'no-such-key 3))))))

(check "menu-choose release: a menu that opens under the pointer stays open \
        when the press that opened it is released there (a taskbar \
        button's, the desktop's)"
       (let ([w (open-window "Under" 'size '(300 . 200) 'pos '(250 . 200))])
         (set-theme! 'menu-choose 'release)
         (steps 1)
         (let* ([a (assq w (with-place 'bar taskbar-areas))]
                [x (+ (cadr a) 20)] [y (+ (caddr a) 10)])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y right 1))
           (steps 1)
           (let ([under (and (menu-entry-at x y) #t)])
             (inject! `(mouse-up ,x ,y right))
             (steps 1)
             (let ([taskbar (list under (and *menu* #t)
                                  (and (memq w (windows)) #t))])
               (close-menu!)
               (inject! '(mouse-move 900 500) '(mouse-down 900 500 right 1)
                        '(mouse-up 900 500 right))
               (steps 1)
               (let ([desk (launcher-open?)])
                 (close-menu!)
                 (reset-theme!)
                 (when (memq w (windows)) (close-window! w))
                 (and (equal? taskbar '(#t #t #t)) desk)))))))

(check "menu-hover outline: moved off the menu with the button held, the \
        entry is drawn pressed no more"
       (begin
         (set-theme! 'menu-hover 'outline)
         (set-theme! 'menu-choose 'release)
         (open-menu! 300 300 (list (cons "One" void) (cons "Two" void)))
         (steps 1)
         (let-values ([(x y) (menu-entry-point "One")])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1))
           (steps 1)
           (inject! `(mouse-move ,x ,(- y 200)))
           (steps 1)
           (let ([whole (screen-whole?)])
             (inject! `(mouse-up ,x ,(- y 200) left))
             (steps 1)
             (close-menu!)
             (reset-theme!)
             whole))))

(check "a blinking entry asks for a frame at its next phase, by a timer"
       (let ([real now-ms] [t (now-ms)])
         (set! now-ms (lambda () t))
         (set-theme! 'menu-blink 2)
         (open-menu! 300 300 (list (cons "One" void) (cons "Two" void)))
         (steps 1)
         (let-values ([(x y) (menu-entry-point "One")])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                    `(mouse-up ,x ,y left))
           (steps 1)
           (set! t (+ t 70))
           (set! *dirty* #f)
           (run-timers!)
           (let ([asked *dirty*])
             (set! t (+ t 300))
             (steps 1)
             (set! now-ms real)
             (reset-theme!)
             (eq? asked #t)))))

;; An outside bar's style whose bars are narrower than its margin.
(define-style test-out-narrow "Outside, narrow"
  'parent 'test-out 'scrollbar-width 10)

(check "an outside scroll bar fills its margin, however narrow the style's \
        bars, and the wheel there scrolls its view"
       (let* ([w (scroll-window "Narrow" 'window-style 'test-out-narrow)]
              [mx (+ (window-x w) 3)]
              [off (lambda () (car (ui-memo (window-ref w 'ui) 'v '(0 . 0))))])
         (inject! `(mouse-move ,mx ,(+ (window-y w) 150)))
         (steps 2)
         (inject! `(mouse-down ,mx ,(+ (window-y w) 150) left 1)
                  `(mouse-up ,mx ,(+ (window-y w) 150) left))
         (steps 2)
         (let ([pressed (off)])
           (inject! `(mouse-move ,mx ,(+ (window-y w) 60)) '(wheel 0 1))
           (steps 2)
           (let ([wheeled (off)])
             (close-window! w)
             (and (> pressed 0) (< wheeled pressed))))))

(check "across a change of the chrome a shaded window stays shaded, in its \
        new frame's height, and its app hears the size it unshades to; \
        under a style that cannot shade it unshades, and hears it too"
       (let* ([heard '()]
              [w (open-window "Stays shaded" 'size '(300 . 200)
                              'pos '(250 . 200)
                              'resize (lambda (win cw ch)
                                        (set! heard (cons (cons cw ch)
                                                          heard))))]
              [content (lambda () (call-with-values
                                    (lambda () (window-content-size w))
                                    cons))])
         (steps 1)
         (shade-window! w)
         (set-theme! 'title-height 40)
         (steps 1)
         (let*-values ([(l t r b) (frame-insets w)]
                       [(after) (list (shaded? w) (window-h w))]
                       [(told) (car heard)])
           (unshade-window! w)
           (let ([unshaded (content)])
             (shade-window! w)
             (set-style! 'spine)
             (steps 1)
             (let ([spine (list (shaded? w) (equal? (car heard) (content)))])
               (set-style! 'mac)
               (reset-theme!)
               (close-window! w)
               (and (equal? after (list #t (+ t b))) (equal? told unshaded)
                    (equal? spine '(#f #t))))))))

(check "menu-choose release: a press that opened a menu under the pointer \
        and wobbles on its entry, then releases there, chooses nothing"
       (let ([w (open-window "Wobble" 'size '(300 . 200) 'pos '(250 . 200))])
         (set-theme! 'menu-choose 'release)
         (steps 1)
         (let* ([a (assq w (with-place 'bar taskbar-areas))]
                [x (+ (cadr a) 20)] [y (+ (caddr a) 10)])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y right 1))
           (steps 1)
           (let ([entry (menu-entry-at x y)])
             (inject! `(mouse-move ,(+ x 5) ,y) `(mouse-move ,x ,y)
                      `(mouse-up ,x ,y right))
             (steps 1)
             (let ([open (and *menu* #t)] [alive (and (memq w (windows)) #t)])
               (close-menu!)
               (reset-theme!)
               (when alive (close-window! w))
               (and entry open alive))))))

(check "scroll bars outside fall back to the right where the frame leaves \
        no margin"
       (let ([w (scroll-window "No margin")])
         (set-theme! 'scrollbar-side 'outside)
         (steps 1)
         (let ([x (bar-x w)])
           (reset-theme!)
           (close-window! w)
           (= x (- 300 (ui-scrollbar-width))))))

;; A style whose grow box resizes, the window manager's edges off.
(define (test-grow-regions win)
  (list (list 'resize-br (- (window-w win) 15) (- (window-h win) 15) 15 15)))
(define-style test-grow "Grow box"
  'frame-regions 'test-grow-regions 'frame-edge 0)

(check "a style's own resize region resizes a normal window only, not a \
        shaded or a maximized one"
       (let* ([w (open-window "Grow" 'size '(300 . 200) 'pos '(250 . 200)
                              'window-style 'test-grow)]
              [size (lambda () (list (window-w w) (window-h w)))]
              [grow! (lambda ()
                       (let ([x (+ (window-x w) (window-w w) -5)]
                             [y (+ (window-y w) (window-h w) -5)])
                         (drag-on! x y (+ x 30) (+ y 20))
                         (size)))])
         (steps 1)
         (let* ([s0 (size)] [normal (grow!)]
                [shaded (begin (shade-window! w) (let ([s (size)])
                                                   (list s (grow!))))]
                [maxed (begin (unshade-window! w) (maximize-window! w)
                              (let ([s (size)]) (list s (grow!))))])
           (close-window! w)
           (and (equal? normal (list (+ (car s0) 30) (+ (cadr s0) 20)))
                (equal? (car shaded) (cadr shaded))
                (equal? (car maxed) (cadr maxed))))))

(check "a top resize keeps the window's top on the desktop, its bottom \
        where it was"
       (let ([w (open-window "Top" 'size '(300 . 200) 'pos '(300 . 100)
                             'window-style 'test-top)])
         (steps 1)
         (let* ([g (geometry w)] [x (+ (car g) 100)] [y (+ (cadr g) 2)]
                [bottom (+ (cadr g) (cadddr g))])
           (drag-on! x y x 2)
           (let-values ([(dx dy dw dh) (desktop-rect)])
             (let ([g2 (geometry w)])
               (close-window! w)
               (and (= (cadr g2) dy) (= (+ (cadr g2) (cadddr g2)) bottom)))))))

(check "old calls keep working: ui-pressable! without a doc, the glyphs \
        sort-up and sort-down; a text field's 'doc is its own"
       (let* ([glyph (lambda (name)
                       (image 20 20 1 (lambda ()
                                        (ui-draw-glyph 2 2 16 16 '() name))))]
              [same (lambda (a b) (zero? (max-diff (glyph a) (glyph b))))]
              [w (kit-window "Old calls"
                             (lambda (ui w h)
                               (ui-pressable! ui 'p 20 20 100 30 void '() '())
                               (ui-text-field ui 't 20 70 200 30 "text" void
                                              'doc '((L . "Edit me")))))])
         (steps 2)
         (let-values ([(cx cy cw ch) (content-rect w)])
           (let ([doc (doc-at (+ cx 50) (+ cy 85))])
             (close-window! w)
             (and (same 'sort-up 'up) (same 'sort-down 'down)
                  (not (window-error w))
                  (equal? doc '((L . "Edit me"))))))))

(check "a menu shows the key that does what an entry does, at its right, \
        and filters by the entry's text alone; the launcher can take a \
        screenshot"
       (let* ([keys (lambda (entries)
                      (filter-map (lambda (e)
                                    (and (pair? e)
                                         (let ([k (menu-label-key (car e))])
                                           (and k (cons (menu-label-text
                                                         (car e))
                                                        k)))))
                                  entries))]
              [launcher (keys (launcher-items #f))]
              [w (open-window "Keys")])
         (open-window-menu w 10 10)
         (let ([window-keys (keys (menu-entries *menu*))])
           (menu-filter-set! *menu* "ctrl")
           (let ([filtered (menu-entries *menu*)])
             (close-menu!)
             (close-window! w)
             (and (equal? (assoc "Screenshot" launcher) '("Screenshot" . "F12"))
                  (equal? (assoc "Tile windows" launcher)
                          '("Tile windows" . "Ctrl+Shift+T"))
                  (equal? (assoc "Close" window-keys)
                          '("Close" . "Ctrl+Shift+W"))
                  (assoc "Minimize" window-keys)
                  (null? filtered)
                  (equal? (menu-label-text "Plain") "Plain")
                  (not (menu-label-key "Plain"))
                  (> (menu-label-width "Close\tCtrl+Shift+W" 'ui)
                     (+ (text-width "Close" 'ui)
                        (text-width "Ctrl+Shift+W" 'ui))))))))
