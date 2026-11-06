;;; tests/units/cons.ss — Cons, the idea through everything.

;;; Cons, the idea through everything: the parts and flags it reaches
;;; the widgets by, and its look at a few pixels.

(check "Tasks' column and card insets, its column and the link after each \
        card are parts: a style's own insets move the cards, its link is \
        called after each card with the gap and whether it is the last, \
        and its column draws the empty one"
       (with-test-styles
        (lambda ()
          (let ([links '()] [columns '()])
            (define-style test-chain "Test"
              'tasks-column-insets (lambda () (values 10 8 21 6))
              'tasks-card-insets (lambda () (values 12 30))
              'tasks-draw-link
              (lambda (x y w h flags gap last?)
                (set! links (cons (list w gap last?) links)))
              'tasks-draw-column
              (lambda (x y w h flags status label count)
                (set! columns (cons (list status (and (memq 'empty flags) #t))
                                    columns))
                (tasks-draw-column* x y w h flags status label count)))
            (set-style! 'test-chain)
            (tasks-reset!)
            (let* ([win (tasks)] [ui (window-ref win 'ui)])
              (focus-window! win)
              (steps 3)
              (let* ([col (ui-region-frame (ui-find ui '(column todo)))]
                     [img (image 200 100 1
                                 (lambda ()
                                   (tasks-draw-column 0 0 200 100 '(empty)
                                                      'todo "To do" 0)))]
                     [r (list (pair? (filter caddr links))
                              (for-all (lambda (l)
                                         (and (= (cadr l) 21)
                                              (= (car l) (- (caddr col) 42))))
                                       links)
                              (assq 'todo columns)
                              (assq 'done columns))])
                (cairo-surface-destroy img)
                (close-window! win)
                (steps 1)
                (equal? r (list #t #t '(todo #t) '(done #f)))))))))

(check "the kit flags the last tab and the last chip, a chip input's box \
        (chips), and makes a dialog's dismiss area, where a style's areas \
        have one, pressable: its dialog gets the labels and that area's \
        state"
       (with-test-styles
        (lambda ()
          (let ([tabs '()] [chips '()] [boxes '()] [dialog '()] [dismissed 0]
                [ui (make-ui)])
            (define-style test-last "Test"
              'ui-draw-tab
              (lambda (x y w h flags label)
                (set! tabs (cons (cons label (and (memq 'last flags) #t))
                                 tabs)))
              'ui-draw-chip
              (lambda (x y w h flags label)
                (set! chips (cons (cons label (and (memq 'last flags) #t))
                                  chips)))
              'ui-draw-field
              (lambda (x y w h flags)
                (set! boxes (cons (and (memq 'chips flags) #t) boxes)))
              'ui-dialog-areas
              (lambda (x y w h labels)
                (cons (list 'dismiss x y 20 20)
                      (ui-dialog-areas* x y w h labels)))
              'ui-draw-dialog
              (lambda (x y w h flags title message) (set! dialog flags)))
            (set-style! 'test-last)
            (let ([w (apply open-window "Last" 'size '(400 . 300)
                            'pos '(100 . 100) 'ui ui
                            'draw (lambda (win cw ch)
                                    (ui-begin! ui)
                                    (ui-tabs ui 'v 10 10 28
                                             '(("A" . a) ("B" . b) ("C" . c))
                                             'a void)
                                    (ui-chip-input ui 'tags 10 50 300
                                                   '("x" "y") "" void void
                                                   void)
                                    (ui-dialog ui 'd "Title" "Message"
                                               (list (list "OK" void))
                                               (lambda ()
                                                 (set! dismissed
                                                   (+ dismissed 1))))
                                    (ui-end! ui cw ch))
                            (ui-handlers ui))])
              (focus-window! w)
              (steps 2)
              (let*-values ([(cx cy cw ch) (content-rect w)]
                            [(r) (ui-find ui '(d dismiss))]
                            [(x y) (values (+ cx (ui-region-x r) 5)
                                           (+ cy (ui-region-y r) 5))])
                (inject! `(mouse-move ,x ,y))
                (steps 2)
                (let ([hovered (and (memq 'hover dialog) #t)])
                  (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))
                  (steps 2)
                  (let ([r (list (list-head (reverse tabs) 3)
                                 (list-head (reverse chips) 2)
                                 (car boxes) (assq 'labels dialog) hovered
                                 dismissed)])
                    (close-window! w)
                    (steps 1)
                    (equal? r '((("A" . #f) ("B" . #f) ("C" . #t))
                                (("x" . #f) ("y" . #t))
                                #t (labels "OK") #t 1))))))))))

(check "Cons draws a boolean as a cell holding #t or #f, filled with its \
        ink under the mouse; a chain's last cell holds nil, the slash \
        across its cdr; a menu's chosen entry fills with ink"
       (let ([pixels
              (lambda (pw ph thunk . ps)
                (with-style 'cons
                  (lambda ()
                    (let* ([img (image pw ph 1 thunk)]
                           [r (map (lambda (p)
                                     (apply pixel-at img
                                            (map (lambda (v)
                                                   (exact (floor v)))
                                                 p)))
                                   ps)])
                      (cairo-surface-destroy img)
                      r))))]
             [box (lambda (flags)
                    (lambda ()
                      (fill-rect 0 0 120 40 'window-bg)
                      (ui-draw-checkbox 10 5 100 30 flags "On")))]
             [bg (with-style 'cons (lambda () (color->pixel 'window-bg)))]
             [ink (with-style 'cons (lambda () (color->pixel 'cons-ink)))])
         (let*-values ([(b) (with-style 'cons ui-checkbox-box)]
                       [(by) (+ 5 (floor (/ (- 30 b) 2)))]
                       [(tw0 th) (with-style 'cons
                                   (lambda () (ui-tabs-size '("Tree"))))]
                       [(tw) (exact (ceiling tw0))]
                       [(cx) (- tw (* 2 (cons-arrow)))]
                       [(tab) (lambda (flags)
                                (lambda ()
                                  (fill-rect 0 0 tw 28 'window-bg)
                                  (ui-draw-tab 0 0 tw 28 flags "Tree")))])
           (dynamic-wind
             (lambda ()
               (set-style! 'cons)
               (open-menu! 200 200 (list (cons "One" void) (cons "Two" void)))
               (steps 2))
             (lambda ()
               (let* ([as (placed-menu-areas *menu*)] [pad (theme 'menu-pad)]
                      [entry (lambda (i)
                               (let ([a (cdr (assv i as))])
                                 (canvas-pixel (+ (car a) pad 2)
                                               (+ (cadr a) 2))))]
                      [r (list (pixels 120 40 (box '(checked))
                                       (list 10 by) (list 11 (+ by 1)))
                               (pixels 120 40 (box '(checked hover))
                                       (list 11 (+ by 1)))
                               (map (lambda (p) (= p bg))
                                    (append (pixels tw 28 (tab '(last))
                                                    (list (+ cx 3) 17))
                                            (pixels tw 28 (tab '())
                                                    (list (+ cx 3) 17))))
                               (entry 0) (entry 1))])
                 (equal? r (list (list ink bg) (list ink) '(#f #t) ink bg))))
             (lambda ()
               (when (menu-open?) (close-menu!))
               (steps 1)
               (set-style! 'mac))))))

;; A chain's flags: each element but the last says where the next starts.
(check "the kit's chain flags say last, or where the next element starts"
       (and (equal? (ui-chain-flags '((0 0 10 10) (5 20 10 10)) 0)
                    '((next 5 20)))
            (equal? (ui-chain-flags '((0 0 10 10) (5 20 10 10)) 1) '(last))))

(check "Cons keeps a removable chip a pair, its × in the car with no line \
        before it, and under the mouse fills a square behind the × alone, \
        the car's inside otherwise as it was"
       (with-style 'cons
         (lambda ()
           (let*-values ([(w h) (ui-chip-size "tag" #t)]
                         [(w) (exact (ceiling w))] [(h) (exact (ceiling h))]
                         [(cw cut?) (cons-chip-car-width w h #t)]
                         [(bx by bs) (cons-chip-x-box 0 0 cw h)])
             (let* ([bx (exact (floor bx))] [by (exact (floor by))]
                    [at (lambda (flags)
                          (let* ([img (image (+ w 4) (+ h 4) 1
                                             (lambda ()
                                               (fill-rect 0 0 (+ w 4) (+ h 4)
                                                          'window-bg)
                                               (ui-draw-chip 0 0 w h flags
                                                             "tag")))]
                                 [ps (list (pixel-at img 2 2)
                                           (pixel-at img (+ bx 1) (+ by 1))
                                           (pixel-at img (- bx 1)
                                                     (quotient h 2)))])
                            (cairo-surface-destroy img)
                            ps))]
                    [bg (color->pixel 'window-bg)]
                    [rest (at '(removable last))]
                    [hot (at '(removable hover last))])
               (and (= (car rest) (car hot) bg)
                    (= (cadr rest) bg)
                    (= (cadr hot) (color->pixel 'button-close))
                    ;; no divider just before the ×, at rest or hovered
                    (= (caddr rest) (caddr hot) bg)))))))

(check "Cons's spacing on Tasks' board: the + g inside its column's corner, \
        the scroll bar's thumb g from the cards' cdr cells and from the \
        well's edge, its top level with the first card's"
       (begin
         (set-style! 'cons)
         (tasks-reset!)
         (let* ([win (tasks)] [ui (window-ref win 'ui)])
           (focus-window! win)
           (steps 3)
           (let* ([g (with-style 'cons cons-space)]
                  [c (with-style 'cons cons-cell)]
                  [f (lambda (id) (ui-region-frame (ui-find ui id)))]
                  [col (f '(column todo))]
                  [add (f '(add todo))]
                  [bar (f '((column todo) bar))]
                  [card (f '(card 16))]
                  [right (+ (car col) (caddr col))]
                  [thumb (cdr (assq 'thumb
                                    (with-style 'cons
                                      (lambda ()
                                        (apply ui-scrollbar-areas
                                               (append bar '(0 1/2)))))))]
                  [r (list (- right (+ (car add) (caddr add)))
                           (- (cadr add) (- (cadr col)
                                            (with-style 'cons
                                              tasks-column-header-height)))
                           (- (car thumb) (+ (car card) (caddr card) c))
                           (- right (+ (car thumb) (caddr thumb)))
                           (- (cadr thumb) (cadr card)))])
             (close-window! win)
             (steps 1)
             (set-style! 'mac)
             (for-all = r (list g g g g 0))))))

(check "Cons's dialog is a chain: its dismiss area is the last button's \
        cdr, a cell beside it, and below the message only the pad"
       (with-style 'cons
         (lambda ()
           (let* ([as (ui-dialog-areas 0 0 400 200 '("Cancel" "Delete"))]
                  [d (cdr (assq 'dismiss as))]
                  [bs (map cdr (filter (lambda (a) (eq? (car a) 'button)) as))]
                  [b (car (last-pair bs))]
                  [m (cdr (assq 'message as))])
             (and (= (car d) (+ (car b) (caddr b)))
                  (= (cadr d) (cadr b))
                  (= (caddr d) (cons-cell))
                  (= (+ (cadr m) (cadddr m)) (- 200 (* 2 (cons-space)))))))))

(check "a mouse press on a style card takes the keyboard from where it was"
       (let ([s (settings)])
         (move-window! s 60 40)
         (focus-window! s)
         (steps 2)
         (let* ([ui (window-ref s 'ui)]
                [r (ui-find ui (list 'style (car (styles))))])
           (ui-focus! ui '(tab colors))
           (let-values ([(cx cy cw ch) (content-rect s)])
             (let ([x (+ cx (ui-region-x r) 20)] [y (+ cy (ui-region-y r) 20)])
               (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                        `(mouse-up ,x ,y left))
               (steps 2)
               (let ([focus (ui-focused ui)])
                 (set-style! 'mac)
                 (close-window! s)
                 (steps 1)
                 (not focus)))))))
