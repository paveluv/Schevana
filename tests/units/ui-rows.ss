;;; tests/units/ui-rows.ss — the kit's boxed lists, status page, banner and
;;; linked buttons ((schevana kits ui)), tested by themselves: where they
;;; lay out what they hold and what a press on them does; and the flags the
;;; kit gives the pieces of a segmented choice and of a row of tabs.

;; The rows of a group: an action row, a switch row, a check row, an entry
;; row and a row that does nothing, with their values in boxes.
(define (ui-rows-test-rows ui wifi agree server opened)
  (list (list "Proxy" "Manual" 0 #f
              'on-press (lambda () (set-box! opened (+ (unbox opened) 1)))
              'key 'proxy)
        (ui-switch-row ui 'wifi "Wi-Fi" (unbox wifi)
                       (lambda (v) (set-box! wifi v)))
        (ui-check-row ui 'agree "Agree" (unbox agree)
                      (lambda (v) (set-box! agree v)))
        (ui-entry-row ui 'server "Server" (unbox server)
                      (lambda (v) (set-box! server v)))
        (list "Version" "1.0" 0 #f 'key 'version)))

(define ui-rows-test-heading
  '(title "Network" description "How this machine connects to others"))

;; A window with the group, 300 wide at (20, 20). Returns the window, the
;; boxes of the rows' values, and boxes with the group's bottom and the
;; window's ui.
(define (ui-rows-test-window)
  (let ([wifi (box #f)] [agree (box #f)] [server (box "")] [opened (box 0)]
        [bottom (box #f)] [ui-of (box #f)])
    (values
     (test-kit-window "Rows"
       (lambda (ui w h)
         (set-box! ui-of ui)
         (set-box! bottom
           (apply ui-rows ui 'rows 20 20 300
                  (ui-rows-test-rows ui wifi agree server opened)
                  ui-rows-test-heading)))
       '(400 . 520))
     wifi agree server opened bottom ui-of)))

(check "a group of rows ends where ui-rows-height says, its heading over \
        it, each row as high as ui-row-height says"
       (let-values ([(win wifi agree server opened bottom ui-of)
                     (ui-rows-test-window)])
         (steps 2)
         (let* ([ui (unbox ui-of)]
                [rows (ui-rows-test-rows ui wifi agree server opened)]
                [r (list (- (unbox bottom) 20)
                         (apply ui-rows-height 300 rows ui-rows-test-heading)
                         (ui-region-h (test-region ui '(rows proxy)))
                         (ui-row-height "Proxy" "Manual")
                         (ui-region-y (test-region ui '(rows proxy)))
                         (ui-region-y (test-region ui '(rows wifi)))
                         (ui-region-y (test-region ui '(rows version))))])
           (close-window! win)
           (printf "  ~s\n" r)
           (and (= (car r) (cadr r))
                (= (caddr r) (cadddr r))
                ;; the heading above the first row, the rows in their order
                (> (list-ref r 4) 20)
                (= (list-ref r 5) (+ (list-ref r 4) (caddr r)))
                (= (+ 20 (car r))
                   (+ (list-ref r 6)
                      (ui-region-h (test-region ui '(rows version)))))))))

(check "a press anywhere on a switch row turns it, and on its switch once; \
        a press on a check row checks it"
       (let-values ([(win wifi agree server opened bottom ui-of)
                     (ui-rows-test-window)])
         (steps 2)
         (test-click! win '(rows wifi))
         (let ([row (unbox wifi)])
           (test-click! win '(wifi switch))
           (let ([switch (unbox wifi)])
             (test-click! win '(rows agree))
             (let ([r (list row switch (unbox agree))])
               (close-window! win)
               (equal? r '(#t #f #t)))))))

(check "a row with an on-press calls it on a press and on Space, and a row \
        without one takes no press"
       (let-values ([(win wifi agree server opened bottom ui-of)
                     (ui-rows-test-window)])
         (steps 2)
         (focus-window! win)
         (test-click! win '(rows proxy))
         (test-click! win '(rows version))
         (parameterize ([current-window win])
           (ui-focus! (unbox ui-of) '(rows proxy)))
         (test-press! #\space)
         (steps 1)
         (let ([r (list (unbox opened) (unbox wifi) (unbox agree))])
           (close-window! win)
           (equal? r '(2 #f #f)))))

(check "a box of rows may end in a row that adds one, ui-add-row-height \
        high and counted in ui-rows-height, a press or Return on it \
        calling its thunk; a box of none holds it alone"
       (let* ([added 0] [bottoms '()] [ui-of #f]
              [rows (list (list "One" #f 0 #f 'key 'one))]
              [add (list "Add Thing" (lambda () (set! added (+ added 1))))]
              [win (test-kit-window "Add"
                     (lambda (ui w h)
                       (set! ui-of ui)
                       (set! bottoms
                         (list (ui-rows ui 'rows 20 20 300 rows 'add add)
                               (ui-rows ui 'none 20 200 300 '() 'add add))))
                     '(400 . 320))])
         (steps 2)
         (focus-window! win)
         (test-click! win '(rows add))
         (parameterize ([current-window win])
           (ui-focus! ui-of '(none add)))
         (test-press! 'return)
         (steps 1)
         (let* ([a (test-region ui-of '(rows add))]
                [r (list added (car bottoms) (cadr bottoms)
                         (ui-region-y a) (ui-region-h a))])
           (close-window! win)
           (printf "  ~s\n" r)
           (and (= added 2)
                (= (car bottoms) (+ 20 (ui-rows-height 300 rows 'add add)))
                (= (cadr bottoms) (+ 200 (ui-add-row-height)))
                (= (list-ref r 3) (+ 20 (ui-row-height "One" #f)))
                (= (list-ref r 4) (ui-add-row-height))))))

(check "an entry row's title gives its field the keyboard, and what is \
        typed goes into it"
       (let-values ([(win wifi agree server opened bottom ui-of)
                     (ui-rows-test-window)])
         (steps 2)
         (focus-window! win)
         (test-click! win '(server title))
         (inject! '(text "example.org"))
         (steps 2)
         (let ([r (list (ui-focused (unbox ui-of)) (unbox server))])
           (close-window! win)
           (equal? r '(server "example.org")))))

(check "a status page's button is under its words and calls its thunk; a \
        banner is ui-banner-height high, its button pressing"
       (let* ([pressed '()]
              [win (test-kit-window "Empty"
                     (lambda (ui w h)
                       (ui-banner ui 'ban 0 0 w "Offline" "Retry"
                                  (lambda ()
                                    (set! pressed (cons 'ban pressed))))
                       (ui-status-page ui 'empty 0 (ui-banner-height) w
                                       (- h (ui-banner-height)) 'folder
                                       "No Items" "Add one to see it here"
                                       'button
                                       (list "Add"
                                             (lambda ()
                                               (set! pressed
                                                 (cons 'add pressed))))))
                     '(400 . 520))])
         (steps 2)
         (test-click! win '(empty button))
         (test-click! win '(ban button))
         (let* ([ui (window-ref win 'ui)]
                [b (test-region ui '(empty button))]
                [d (cdr (assq 'description
                              (ui-status-page-areas 0 (ui-banner-height) 400
                                                    (- 520 (ui-banner-height))
                                                    '() "No Items"
                                                    "Add one to see it here"
                                                    "Add")))]
                [r (list pressed
                         (ui-region-h (test-region ui 'ban))
                         (>= (ui-region-y b) (+ (cadr d) (cadddr d))))])
           (close-window! win)
           (equal? r (list '(ban add) (ui-banner-height) #t)))))

(check "linked buttons share their edges' pixel, the x after them where the \
        last ends, and each presses"
       (let* ([pressed #f] [after #f]
              [win (test-kit-window "Linked"
                     (lambda (ui w h)
                       (set! after
                         (ui-linked ui 'lk 20 20 (ui-control-height)
                                    (map (lambda (k l)
                                           (list k l
                                                 (lambda () (set! pressed k))))
                                         '(a b c) '("Left" "Middle" "Right")))))
                     '(400 . 120))])
         (steps 2)
         (test-click! win '(lk b))
         (let* ([ui (window-ref win 'ui)]
                [rs (map (lambda (k) (test-region ui (list 'lk k))) '(a b c))]
                [end (lambda (r) (+ (ui-region-x r) (ui-region-w r)))]
                [r (list pressed
                         (= (ui-region-x (cadr rs)) (- (end (car rs)) 1))
                         (= (ui-region-x (caddr rs)) (- (end (cadr rs)) 1))
                         (= after (end (caddr rs))))])
           (close-window! win)
           (equal? r '(b #t #t #t)))))

;; Returns the flags each piece is drawn with, by label, as (draw ui) draws
;; in a picture: a stand-in for the part ('button for ui-draw-button, else
;; ui-draw-tab) records them.
(define (ui-rows-test-flags part draw)
  (let ([seen '()] [win (open-window "Flags" 'size '(400 . 100))])
    (let ([record (lambda (x y w h flags label . more)
                    (set! seen (cons (cons label flags) seen)))])
      (picture-free!
       (image 400 100 1
              (lambda ()
                (parameterize ([current-window win])
                  (let ([ui (make-ui)])
                    (ui-begin! ui)
                    (case part
                      [(button) (fluid-let ([ui-draw-button record])
                                  (draw ui))]
                      [else (fluid-let ([ui-draw-tab record]) (draw ui))])))))))
    (close-window! win)
    (reverse seen)))

(check "a row that can't be used has its words in text-disabled, the row \
        that adds one too, its plus drawn as a disabled glyph"
       (let* ([seen '()] [see! (lambda (what) (set! seen (cons what seen)))]
              [draw (lambda (flags)
                      (set! seen '())
                      (fluid-let ([draw-text
                                   (lambda (x y s color . f)
                                     (see! (list s color))
                                     x)]
                                  [ui-draw-glyph
                                   (lambda (x y w h flags name)
                                     (see! (cons name flags)))])
                        (picture-free!
                         (image 300 100 1
                                (lambda ()
                                  (ui-draw-row 0 0 300 44 flags "T" "S" 10 200)
                                  (ui-draw-add-row 0 50 300 44 flags "A")))))
                      (reverse seen))]
              [r (list (draw '(activatable)) (draw '(activatable disabled)))])
         (printf "  ~s\n" r)
         (equal? r '((("T" text) ("S" text-dim) (plus (ink . accent))
                      ("A" accent))
                     (("T" text-disabled) ("S" text-disabled)
                      (plus (ink . accent) disabled)
                      ("A" text-disabled))))))

(check "a box of rows calls ui-draw-highlight-over on its chosen row, after \
        what the row holds, and on no other"
       (let* ([seen '()]
              [row (lambda (k . opts)
                     (cons* k #f 20
                            (lambda (x y w h) (set! seen (cons k seen)))
                            opts))]
              [win (fluid-let ([ui-draw-highlight-over
                                (lambda (x y w h flags)
                                  (set! seen (cons 'over seen)))])
                     (let ([win (test-kit-window "Rows"
                                  (lambda (ui w h)
                                    (set! seen '())
                                    (ui-rows ui 'rows 20 20 300
                                             (list (row "a")
                                                   (row "b" 'selected #t)
                                                   (row "c")))))])
                       (steps 2)
                       win))])
         (close-window! win)
         (equal? (reverse seen) '("a" "b" over "c"))))

(check "a segmented choice's pieces are flagged segment; with no gap they \
        are one group, their inner sides joined; tabs say which is first \
        and which last"
       (let* ([choices '(("S" . s) ("M" . m) ("L" . l))]
              [has (lambda (seen label f) (and (memq f (cdr (assoc label seen)))
                                               #t))]
              [gapped (ui-rows-test-flags 'button
                        (lambda (ui)
                          (ui-segmented ui 'seg 0 0 300 30 choices 'm
                                        (lambda (v) v))))]
              [joined (test-finally
                       (lambda ()
                         (set-theme! 'segmented-gap 0)
                         (ui-rows-test-flags 'button
                           (lambda (ui)
                             (ui-segmented ui 'seg 0 0 300 30 choices 'm
                                           (lambda (v) v)))))
                       (lambda () (reset-style! 'segmented-gap)))]
              [tabs (ui-rows-test-flags 'tab
                      (lambda (ui)
                        (ui-tabs ui 'tabs 0 0 30 choices 'm (lambda (v) v))))])
         (and (has gapped "S" 'segment)
              (not (has gapped "M" 'join-left))
              (has joined "M" 'join-left) (has joined "M" 'join-right)
              (not (has joined "S" 'join-left)) (has joined "S" 'join-right)
              (has joined "L" 'join-left) (not (has joined "L" 'join-right))
              (has tabs "S" 'first) (not (has tabs "S" 'last))
              (not (has tabs "M" 'first)) (not (has tabs "M" 'last))
              (has tabs "L" 'last))))

(check "a stepper puts its pieces where ui-stepper-areas says, joined as \
        they say"
       (with-test-styles
        (lambda ()
          (define-style test-stepper "Test"
            'ui-stepper-areas
            (lambda (x y w h)
              (let ([b (ui-control-height)])
                (list (list 'field x y (- w b b) h 'join-right)
                      (list 'down (- (+ x w) b b) y b h 'join-left 'join-right)
                      (list 'up (- (+ x w) b) y b h 'join-left)))))
          (set-style! 'test-stepper)
          (let* ([win (test-kit-window "Stepper"
                        (lambda (ui w h)
                          (ui-stepper ui 'st 20 20 5 0 9 (lambda (n) n)))
                        '(400 . 100))]
                 [seen (begin (steps 2)
                              (ui-rows-test-flags 'button
                                (lambda (ui)
                                  (ui-stepper ui 'st 20 20 5 0 9
                                              (lambda (n) n)))))])
            (steps 1)
            (let* ([ui (window-ref win 'ui)]
                   [x (lambda (k) (ui-region-x (test-region ui (list 'st k))))]
                   [r (list (< (x 'field) (x 'down) (x 'up))
                            (map (lambda (f) (and (memq f (cdr (car seen))) #t))
                                 '(join-left join-right))
                            (map (lambda (f)
                                   (and (memq f (cdr (cadr seen))) #t))
                                 '(join-left join-right)))])
              (close-window! win)
              (equal? r '(#t (#t #t) (#t #f))))))))
