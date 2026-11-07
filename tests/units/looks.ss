;;; tests/units/looks.ss — the styles' own looks: Genera, the CADR, Interlisp,
;;; Mac and ours, drawn and measured.

;;; Our styles, finished (step 9)

(define (style-insets st)
  (let ([w (open-window "Insets" 'size '(300 . 200) 'window-style st)])
    (let-values ([(l t r b) (frame-insets w)])
      (close-window! w)
      (list l t r b))))

(check "at the default fonts the insets are Genera's 6 6 6 23, the CADR's \
        2 2 2 and its label strip, the code font's line and 2, Interlisp's \
        4 17 4 4"
       (and (equal? (style-insets 'genera) '(6 6 6 23))
            (equal? (style-insets 'cadr)
                    (list 2 2 2 (+ 2 (exact (round (+ 2 (font-line-height
                                                         'mono)))))))
            (equal? (style-insets 'interlisp) '(4 17 4 4))))

(check "our styles' own behaviors, and the CADR's Genera's but its frame \
        and its gray"
       (let ([of (lambda (st . keys)
                   (with-style st (lambda () (map theme keys))))])
         (and (equal? (of 'fold 'title-double-click) '(shade))
              (equal? (of 'lambda 'title-wheel) '(shade))
              (equal? (of 'halo 'scrollbar-show) '(hover))
              (equal? (of 'reticle 'scrollbar-show 'drag-feedback
                          'draw-drag-outline)
                      '(hover outline reticle-drag-outline))
              (equal? (of 'draft 'drag-feedback 'draw-drag-outline)
                      '(outline draft-drag-outline))
              (equal? (of 'curses 'bell 'menu-hover) '(screen outline))
              (equal? (of 'genera 'mouse-doc 'bell 'menu-hover 'scrollbar-side
                          'title-double-click 'topbar-height)
                      '(#t screen outline left none 0))
              (equal? (of 'cadr 'mouse-doc 'draw-taskbar 'genera-border
                          'genera-margin 'genera-label-font
                          'genera-label-align 'frame-over)
                      '(#t genera-draw-who-line 1 1 mono top frame-over*))
              (equal? (of 'interlisp 'drag-feedback 'draw-drag-outline
                          'menu-choose 'menu-hover 'bell 'title-double-click
                          'scrollbar-side 'scrollbar-show 'scrollbar-width)
                      '(outline interlisp-drag-outline release outline window
                        none left hover 24))
              (equal? (of 'spine 'title-double-click 'title-wheel)
                      '(maximize none))
              (equal? (of 'mac 'drag-feedback 'bell 'mouse-doc)
                      '(live none #f)))))

;; An outline drawn on white at 100 and 150 %: what changed, and what
;; changed outside its rectangle.
(define (outline-changes st w h)
  (map (lambda (s)
         (with-style st
           (lambda ()
             (let* ([k (lambda (v) (exact (round (* v s))))]
                    [paint (lambda (outline?)
                             (image (k 300) (k 200) (inexact s)
                                    (lambda ()
                                      (fill-box 0 0 300 200 #xffffff)
                                      (when outline?
                                        (draw-drag-outline 20 30 w h)))))]
                    [blank (paint #f)] [drawn (paint #t)]
                    [r (list (max-diff blank drawn)
                             (max-diff blank drawn
                                       (list (k 20) (k 30) (k (+ 20 w))
                                             (k (+ 30 h)))))])
               (picture-free! blank)
               (picture-free! drawn)
               r))))
       '(1 3/2)))

(check "Draft's, Reticle's and Interlisp's outlines are drawn within their \
        rectangle, smaller than one of Reticle's brackets too"
       (for-all (lambda (st)
                  (for-all (lambda (wh)
                             (for-all (lambda (r)
                                        (and (> (car r) 0) (= (cadr r) 0)))
                                      (outline-changes st (car wh) (cdr wh))))
                           '((240 . 120) (30 . 20) (8 . 8))))
                '(draft reticle interlisp)))

(check "Draft's outline shows the live size, where it fits"
       (with-style 'draft
         (lambda ()
           (let* ([at (lambda (w)
                        (image 300 200 1
                               (lambda ()
                                 (fill-box 0 0 300 200 #xffffff)
                                 (draw-drag-outline 20 30 w 120))))]
                  [a (at 240)] [b (at 239)] [narrow (at 60)]
                  [plain (image 300 200 1
                                (lambda ()
                                  (fill-box 0 0 300 200 #xffffff)
                                  (stroke-box 20 30 60 120 'accent)))]
                  ;; the right edge moved; the label changed too
                  [r (list (max-diff a b '(250 0 300 200))
                           (max-diff narrow plain))])
             (for-each picture-free! (list a b narrow plain))
             (and (> (car r) 0) (= (cadr r) 0))))))

(check "Genera grays a window not selected with a sparse stipple, and not \
        the selected one"
       (let* ([a (open-window "A" 'size '(200 . 120) 'pos '(100 . 100)
                              'window-style 'genera)]
              [b (open-window "B" 'size '(200 . 120) 'pos '(500 . 100)
                              'window-style 'genera)])
         (steps 2)
         (let* ([dot (lambda (win)   ; the first stipple dot in its content
                       (let-values ([(cx cy cw ch) (content-rect win)])
                         (canvas-pixel (* 4 (ceiling (/ cx 4)))
                                       (* 4 (ceiling (/ cy 4))))))]
                [r (list (dot a) (dot b)
                         (with-style 'genera
                           (lambda () (list (color->pixel 'text)
                                            (color->pixel 'window-bg)))))])
           (close-window! a)
           (close-window! b)
           (steps 1)
           (equal? (list (car r) (cadr r)) (caddr r)))))

(check "Genera's buttons are command words: plain, boxed under the \
        pointer and while pressed, reversed while chosen"
       (with-style 'genera
         (lambda ()
           (let ([at (lambda (flags)
                       (let* ([img (image 120 40 1
                                          (lambda ()
                                            (fill-box 0 0 120 40 'window-bg)
                                            (ui-draw-button 10 5 100 30 flags
                                                            "Go" #f)))]
                              [ps (list (pixel-at img 10 5)
                                        (pixel-at img 60 8))])
                         (picture-free! img)
                         ps))]
                 [ink (color->pixel 'text)] [paper (color->pixel 'window-bg)])
             (and (equal? (at '()) (list paper paper))
                  (equal? (at '(hover)) (list ink paper))
                  (equal? (at '(pressed hover)) (list ink paper))
                  (equal? (at '(selected)) (list ink ink)))))))

(check "faint text is in its font's italic, bold kept, where a style says \
        so ('faint-text-font, Genera's); other text and styles keep theirs"
       (and (with-style 'mac
              (lambda () (eq? (faint-font 'text-faint (get-font 'ui))
                              (get-font 'ui))))
            (with-style 'genera
              (lambda ()
                (let ([f (faint-font 'text-faint (get-font 'mono-bold))])
                  (and (eq? (font-slant f) 'italic)
                       (eq? (font-weight f) 'bold)
                       (eq? (faint-font 'text (get-font 'mono))
                            (get-font 'mono))))))))

(check "the CADR's lozenge: 9 pixels high, 9 + 6 a character wide, pointed \
        ends, the name in capitals of MIT's 5X5"
       (let* ([img (image 30 12 1
                          (lambda ()
                            (fill-box 0 0 30 12 #xffffff)
                            (px-lozenge 0 0 "a" #x000000)))]
              [r (list (px-lozenge-width "AB")
                       (map (lambda (p) (= (apply pixel-at img p) #xff000000))
                            '((0 4) (3 1) (3 7) (4 0) (4 8) (14 4) (11 1)
                              (6 2) (5 2) (5 4) (9 4) (6 6) (5 6))))])
         (picture-free! img)
         (equal? r '(21 (#t #t #t #t #t #t #t #t #f #t #t #f #t)))))

(check "Genera chooses in inverse video: a row's 2-pixel box, its inside \
        turned once its cells are drawn (ui-draw-highlight-over); Mac turns \
        nothing"
       (let ([at (lambda (style)
                   (with-style style
                     (lambda ()
                       (let* ([img (image 100 24 1
                                          (lambda ()
                                            (fill-box 0 0 100 24 #xffffff)
                                            (ui-draw-table-row 0 0 100 24
                                                               '(selected))
                                            (fill-box 10 8 6 6 #x000000)
                                            (ui-draw-highlight-over
                                             0 0 100 24 '())))]
                              [ps (map (lambda (p) (apply pixel-at img p))
                                       '((0 0) (50 12) (12 10)))])
                         (picture-free! img)
                         ps))))])
         (and (equal? (at 'genera) '(#xff000000 #xff000000 #xffffffff))
              (= (caddr (at 'mac)) #xff000000))))

(check "a table calls ui-draw-highlight-over on its chosen row after the \
        row's cells, and on no other"
       (with-test-styles
        (lambda ()
          (let ([seen '()] [ui (make-ui)])
            (define-style test-over "Test"
              'ui-draw-highlight-over
              (lambda (x y w h flags) (set! seen (cons 'over seen))))
            (set-style! 'test-over)
            (let ([win (apply open-window "T" 'size '(300 . 200)
                              'pos '(100 . 100) 'ui ui
                              'draw (lambda (win w h)
                                      (ui-begin! ui)
                                      (ui-table ui 't 0 0 w h '((a "A" 100))
                                                '(1 2 3) 2 void
                                                (lambda (row k x y w h flags)
                                                  (set! seen (cons row seen))))
                                      (ui-end! ui w h))
                              (ui-handlers ui))])
              (steps 2)
              (close-window! win)
              (steps 1)
              (let loop ([s (reverse seen)] [prev #f] [overs 0])
                (cond [(null? s) (> overs 0)]
                      [(eq? (car s) 'over)
                       (and (eqv? prev 2) (loop (cdr s) 'over (+ overs 1)))]
                      [else (loop (cdr s) (car s) overs)])))))))

(check "a string among a column's flags is its heading's tooltip, sorted \
        or not, and never one of its cells' flags"
       (let* ([ui (make-ui)] [flags '()]
              [table (lambda (on-sort)
                       (lambda (win w h)
                         (ui-begin! ui)
                         (apply ui-table ui 't 0 0 w h
                                '((a "A" 100 right "What A means") (b "B" 100))
                                '(1 2) #f void
                                (lambda (row k x y w h fl)
                                  (set! flags (append fl flags)))
                                (if on-sort (list 'on-sort on-sort) '()))
                         (ui-end! ui w h)))]
              [tip-of (lambda (key)
                        (let ([r (ui-find ui (list 't 'header key))])
                          (and r (ui-region-tip r))))]
              [win (apply open-window "T" 'size '(300 . 200) 'pos '(100 . 100)
                          'ui ui 'draw (table #f) (ui-handlers ui))])
         (steps 2)
         (let ([plain (list (tip-of 'a) (tip-of 'b))])
           (window-on! win 'draw (table void))
           (invalidate! win)
           (steps 2)
           (let ([sorted (list (tip-of 'a) (tip-of 'b))])
             (close-window! win)
             (steps 1)
             (printf "  ~s ~s\n" plain sorted)
             (and (equal? plain '("What A means" #f))
                  (equal? sorted '("What A means" #f))
                  (memq 'right flags)
                  (not (exists string? flags)))))))

(check "Tasks' marks and avatars are a style's: Genera leaves out a status's \
        mark (its word is beside it) and an avatar beside the name, else \
        the initials in a lozenge"
       (let ([mark (lambda (style)
                     (with-style style
                       (lambda ()
                         (let* ([w #f]
                                [img (image 20 20 1
                                            (lambda ()
                                              (set! w (tasks-draw-mark
                                                       2 2 14 'status
                                                       'todo))))])
                           (picture-free! img)
                           w))))]
             [size (lambda (style flags)
                     (with-style style
                       (lambda ()
                         (call-with-values
                           (lambda () (ui-avatar-size flags "Pavel Uvarov"))
                           list))))])
         (and (= (mark 'mac) 14) (= (mark 'genera) 0)
              (equal? (size 'genera '()) '(21 9))
              (equal? (size 'genera '(named)) '(0 0))
              (equal? (size 'mac '(named)) (size 'mac '())))))

(check "Genera's caret is a block in reverse video and its selection an \
        underline (text-caret, text-selection)"
       (let ([probe   ; ink at x on any of the rows ys
              (lambda (style text at x ys)
                (set-style! style)
                (let-values ([(win ui) (field-window text)])
                  (focus-window! win)
                  (ui-focus! ui 'f at)
                  (invalidate! win)
                  (steps 2)
                  (let-values ([(cx cy cw ch) (content-rect win)])
                    (let ([ink? (exists (lambda (y)
                                          (= (canvas-pixel (+ cx x) (+ cy y))
                                             (color->pixel 'text)))
                                        ys)])
                      (close-window! win)
                      (steps 1)
                      ink?))))])
         ;; the block over the field's middle; the underline below the
         ;; text's baseline, wherever the font's size puts it
         (let ([r (list (probe 'genera "" 0 25 '(30))
                        (probe 'mac "" 0 25 '(30))
                        (probe 'genera "MMMM" #t 26 '(35 36 37 38 39 40)))])
           (set-style! 'mac)
           (equal? r '(#t #f #t)))))

(check "a style may center its menus' entries (menu-align, the Lisp \
        machines'), and a section label keep its case and take its font"
       (let ([first-ink
              (lambda (style)
                (set-style! style)
                (open-menu! 200 200 (list (cons "a much wider entry" void)
                                          (cons "ii" void)))
                (steps 2)
                (let* ([a (cdr (assv 1 (placed-menu-areas *menu*)))]
                       [x (car a)] [y (cadr a)] [w (caddr a)] [h (cadddr a)]
                       [bg (canvas-pixel (+ x w -6) (+ y (quotient h 2)))]
                       [at (let loop ([i 12])   ; clear of a round corner
                             (cond [(>= i (- w 12)) #f]
                                   [(exists (lambda (dy)
                                              (not (= bg (canvas-pixel
                                                          (+ x i) (+ y dy)))))
                                            (iota (exact (- h 4))))
                                    (/ i w)]
                                   [else (loop (+ i 1))]))])
                  (close-menu!)
                  (steps 1)
                  at))])
         (let ([r (list (first-ink 'genera) (first-ink 'mac))])
           (set-style! 'mac)
           (and (> (car r) 1/3) (< (cadr r) 1/3)
                (with-style 'genera
                  (lambda ()
                    (and (equal? (ui-label-text '(section) "Checklist")
                                 "Checklist")
                         (eq? (ui-label-font '(section)) 'ui-bold-italic))))
                (equal? (ui-label-text '(section) "Checklist")
                        "CHECKLIST")))))

(check "a dropdown showing its 'label, not a choice, says so (flag label), \
        so Genera sets a value in bold and a label plain"
       (with-test-styles
        (lambda ()
          (let ([seen '()] [ui (make-ui)])
            (define-style test-dd "Test"
              'ui-draw-dropdown
              (lambda (x y w h flags label)
                (set! seen (cons (cons label (and (memq 'label flags) #t))
                                 seen))))
            (set-style! 'test-dd)
            (let ([win (apply open-window "D" 'size '(300 . 100)
                              'pos '(100 . 100) 'ui ui
                              'draw (lambda (win w h)
                                      (ui-begin! ui)
                                      (ui-dropdown ui 'a 10 10 100 24
                                                   '(("One" . 1)) 1 void)
                                      (ui-dropdown ui 'b 10 40 100 24
                                                   '(("One" . 1)) #f void
                                                   'label "Kind")
                                      (ui-end! ui w h))
                              (ui-handlers ui))])
              (steps 2)
              (close-window! win)
              (steps 1)
              (and (equal? (assoc "One" seen) '("One" . #f))
                   (equal? (assoc "Kind" seen) '("Kind" . #t))))))))

;; Pixels of an image drawn by thunk in Genera, scale s, extra settings
;; over it: ((x y) ...) read in device pixels.
(define (genera-pixels pw ph s at thunk . extra)
  (apply with-style 'genera
         (lambda ()
           (let* ([img (image pw ph s thunk)]
                  [ps (map (lambda (p) (apply pixel-at img p)) at)])
             (picture-free! img)
             ps))
         extra))

(check "px-invert swaps ink and paper in any palette (Genera in Nord, \
        Paper), and black on white as XOR did"
       (for-all
        (lambda (palette)
          (with-style 'genera
            (lambda ()
              (equal? (genera-pixels 20 10 1 '((5 5) (15 5))
                                     (lambda ()
                                       (fill-box 0 0 20 10 'window-bg)
                                       (fill-box 10 0 10 10 'text)
                                       (px-invert 0 0 20 10))
                                     'palette palette)
                      (list (color->pixel 'text) (color->pixel 'window-bg))))
            'palette palette))
        '(nord paper genera)))

(check "a block caret is as wide as the character under it, the font's \
        width past the end"
       (and (= (ui-caret-block-width "iM" 0 'ui) (text-width "i" 'ui))
            (= (ui-caret-block-width "iM" 1 'ui) (text-width "M" 'ui))
            (= (ui-caret-block-width "iM" 2 'ui) (font-char-width 'ui))
            (< (text-width "i" 'ui) (text-width "M" 'ui))))

(check "a scroll view clips on whole device pixels: at 150 % what it cuts \
        ends in ink or paper"
       (let* ([img (image 30 30 1.5
                          (lambda ()
                            (fill-box 0 0 20 20 #xffffff)
                            (with-clip (1.3 1.3 10.4 10.4)
                              (fill-box 0 0 20 20
                                        #x000000))))]
              [ps (map (lambda (i) (pixel-at img i i)) (iota 20))])
         (picture-free! img)
         (for-all (lambda (p) (memv p '(#xff000000 #xffffffff))) ps)))

(check "a square clip inside a rounded one keeps its corners, however deep: \
        a window's content stays inside the window's; a rounded clip within \
        holds instead"
       (let* ([draw (lambda (thunk)
                      (image 40 40 1
                             (lambda ()
                               (fill-box 0 0 40 40 #xffffff)
                               (thunk))))]
              [paper #xffffffff] [ink #xff000000]
              [square (draw (lambda ()
                              (with-clip (0 0 40 40 12)
                                (with-clip (0 0 40 40)
                                  (with-clip (0 20 40 20)
                                    (fill-box 0 0 40 40 #x000000))))))]
              [rounded (draw (lambda ()
                               (with-clip (0 0 40 40 12)
                                 (with-clip (10 10 20 20 4)
                                   (fill-box 0 0 40 40 #x000000)))))]
              [ok (and (= (pixel-at square 1 38) paper)
                       (= (pixel-at square 38 38) paper)
                       (= (pixel-at square 20 38) ink)
                       (= (pixel-at square 1 22) ink)
                       (= (pixel-at square 20 18) paper)
                       (= (pixel-at rounded 10 10) paper)
                       (= (pixel-at rounded 12 12) ink)
                       (= (pixel-at rounded 20 8) paper))])
         (picture-free! square)
         (picture-free! rounded)
         ok))

(check "Genera's square things at 150 % on whole device pixels: a Tasks \
        card's paper, Settings' font sample's box"
       (begin
         (tasks-reset!)
         (let ([crisp? (lambda (ps)
                         (for-all (lambda (p) (memv p '(#xff000000
                                                        #xffffffff)))
                                  ps))]
               [row (map (lambda (x) (list x 30)) (iota 8))])
           (and (crisp? (genera-pixels 60 60 1.5 row
                                       (lambda ()
                                         (fill-box 0 0 40 40 'text)
                                         (tasks-draw-card 1.3 1.3 30 30 '()
                                                          (car *tasks*)
                                                          '(2026 10 31)))))
                (crisp? (genera-pixels 60 60 1.5 row
                                       (lambda ()
                                         (fill-box 0 0 40 40 'text)
                                         (settings-draw-font-sample
                                          1.3 1.3 30))))))))

(check "Genera inverts Settings' chosen tab, its mark inside it in ink, and \
        its chosen color row"
       (let ([ink #xff000000])
         (and (equal? (genera-pixels 100 24 1 '((2 12) (90 3))
                                     (lambda ()
                                       (fill-box 0 0 100 24 #xffffff)
                                       (ui-draw-nav-row 0 0 100 24
                                                        '(selected)
                                                        "Theme" #f)))
                      (list ink ink))
              (equal? (genera-pixels 200 28 1 '((150 4))
                                     (lambda ()
                                       (fill-box 0 0 200 28 #xffffff)
                                       (settings-draw-color-row
                                        0 0 200 28 'red '(selected))))
                      (list ink)))))

(check "Genera's field underline shows in a half-size miniature, and a \
        menu filter's caret is its block"
       (let ([ink #xff000000])
         (and (exists (lambda (p) (= p ink))
                      (genera-pixels 20 10 1/2
                                     (map (lambda (x) (list x 9)) (iota 20))
                                     (lambda ()
                                       (fill-box 0 0 40 20 #xffffff)
                                       (ui-draw-field 0 0 40 20 '()))))
              (with-style 'genera
                (lambda ()
                  (let ([x (+ 10 (text-width "ab" (theme 'menu-font)) 2)])
                    (equal? (genera-pixels
                             100 30 1 (list (list (exact (floor x)) 15))
                             (lambda ()
                               (draw-menu-filter (make-menu 0 0 '() 0 "ab" #t
                                                            #f)
                                                 0 0 100 30)))
                            (list ink))))))))

(check "the calendar's steps are the words Previous and Next under Genera \
        (calendar-step-words), glyphs elsewhere"
       (let ([doc
              (lambda (style)
                (set-style! style)
                (let* ([ui (make-ui)]
                       [win (apply open-window "C" 'size '(400 . 400)
                                   'pos '(100 . 100) 'ui ui
                                   'draw (lambda (win w h)
                                           (ui-begin! ui)
                                           (ui-date-field ui 'd 10 10 150 24
                                                          '(2026 11 2) void)
                                           (ui-end! ui w h))
                                   (ui-handlers ui))])
                  (steps 2)
                  (ui-state-popup-set! ui (cons 'd (ui-date->day
                                                    '(2026 11 2))))
                  (invalidate! win)
                  (steps 2)
                  (let ([r (ui-find ui '(d prev))])
                    (close-window! win)
                    (steps 1)
                    (and r (ui-region-doc r)))))])
         (let ([r (list (doc 'genera) (doc 'mac))])
           (set-style! 'mac)
           (equal? r '(((L . "Previous")) ((L . "Press")))))))

(check "a board column's ring shows under the card it cuts off (Genera: \
        the cards' view stops short of its well's ring, surface-well-ring)"
       (begin
         (set-style! 'genera)
         (tasks-reset!)
         (let* ([win (tasks)] [ui (window-ref win 'ui)])
           (focus-window! win)
           (steps 3)
           (let*-values ([(cx cy cw ch) (content-rect win)]
                         [(f) (ui-region-frame (ui-find ui '(column todo)))]
                         ;; the well's last row: the board's, a pad up
                         [(ps) (map (lambda (dx)
                                      (canvas-pixel (+ cx (car f) dx)
                                                    (+ cy ch (- (ui-pad)) -1)))
                                    '(40 60 80))]
                         [(ink) (color->pixel 'text)])
             (close-window! win)
             (steps 1)
             (set-style! 'mac)
             (for-all (lambda (p) (= p ink)) ps)))))

(check "Settings' chosen color row shows its swatch in its own color over \
        Genera's inverse video, its ring a stipple of ink and paper"
       (with-style 'genera
         (lambda ()
           (equal? (genera-pixels 200 28 1 '((20 14) (12 6) (13 6))
                                  (lambda ()
                                    (fill-box 0 0 200 28 #xffffff)
                                    (settings-draw-color-row
                                     0 0 200 28 'accent '(selected))))
                   (list (color->pixel 'accent) #xff000000 #xffffffff)))))

(check "Genera's who line: no top bar; what the mouse does reversed across \
        its top line, in Genera's words; its fields at character columns; \
        its windows field lists them, and one chosen is selected"
       (let ([a (open-window "Alpha" 'size '(300 . 160) 'pos '(200 . 200))]
             [b (open-window "Beta" 'size '(300 . 160) 'pos '(600 . 200))])
         (set-style! 'genera)
         (inject! '(mouse-move 900 600))
         (steps 2)
         (let* ([lh (genera-line)] [top (- (screen-h) (* 2 lh))]
                [areas (with-place 'bar taskbar-areas)]
                [cw (font-char-width 'mono)]
                [row (lambda () (map (lambda (x) (canvas-pixel x (+ top 8)))
                                     (iota 300)))]
                [desk (row)]
                [sizes (list (topbar-height) (taskbar-height) (* 2 lh))]
                [cols (map (lambda (a) (/ (cadr a) cw)) (cdr areas))]
                [colors (list (canvas-pixel 2 (+ top 1))
                              (canvas-pixel 2 (+ top lh 1))
                              (canvas-pixel 640 2))]
                [ink+paper (list (color->pixel 'text) (color->pixel 'bg-1)
                                 (color->pixel 'desktop-top))])
           (inject! `(mouse-move ,(+ (window-x a) 100)
                                 ,(+ (window-y a) (window-h a) -8)))
           (steps 2)
           (let ([over (row)] [doc (mouse-doc)]
                 [f (cdr (assq 'windows areas))])
             (inject! `(mouse-move ,(+ (car f) 4) ,(+ (cadr f) 4))
                      `(mouse-down ,(+ (car f) 4) ,(+ (cadr f) 4) left 1)
                      `(mouse-up ,(+ (car f) 4) ,(+ (cadr f) 4) left))
             (steps 1)
             (let ([listed (and (menu-open?)
                                (map car (menu-items *menu*)))])
               (when (menu-open?)
                 ((cdr (assoc "Alpha" (menu-items *menu*))))
                 (close-menu!))
               (let ([chosen (eq? *focus* a)])
                 (set-style! 'mac)
                 (close-window! a)
                 (close-window! b)
                 (steps 2)
                 (and (= (car sizes) 0) (= (cadr sizes) (caddr sizes))
                      (for-all integer? cols)
                      (equal? colors ink+paper)
                      (not (equal? desk over))
                      (equal? (genera-mouse-doc-text doc)
                              "Mouse-L: Move; Mouse-R: Window menu.")
                      (member "Alpha" listed) (member "Beta" listed)
                      chosen)))))))

(check "Interlisp's title shade fills its strip's title rows after the \
        title, the border's ink above and below"
       (let ([w (open-window "T" 'size '(300 . 160) 'pos '(200 . 200)
                             'window-style 'interlisp)])
         (steps 2)
         (let* ([x (+ (window-x w) 200)] [y (window-y w)]
                [px (lambda () (map (lambda (dy) (canvas-pixel x (+ y dy)))
                                    '(0 5 14)))]
                [ink (px)])
           (override! 'interlisp-title-shade #xffffff)
           (steps 2)
           (let ([shaded (px)])
             (override! 'interlisp-title-shade)
             (close-window! w)
             (steps 1)
             (let ([i #xff000000] [p #xffffffff])
               (and (equal? ink (list i i i))
                    (equal? shaded (list i p i))))))))

(check "Interlisp's desktop is Medley's #x8822: dashes two pixels tall, \
        moved two columns every two rows"
       (let* ([img (image 4 4 1 (lambda ()
                                  (fill-wallpaper 0 0 4 4 'shade #xffffff
                                                  #x000000)))]
              [rows (map (lambda (y)
                           (list->string
                            (map (lambda (x)
                                   (if (= (pixel-at img x y) #xff000000)
                                       #\# #\.))
                                 (iota 4))))
                         (iota 4))])
         (picture-free! img)
         (equal? rows '("#..." "#..." "..#." "..#."))))

(check "Interlisp's scroll bars beside the window: with the side Outside \
        its frame leaves Medley's 24 pixels at the left, and the bar shows \
        there under the pointer"
       (begin
         (override! 'scrollbar-side 'outside)
         (let ([w (scroll-window "Medley" 'window-style 'interlisp)])
           (steps 2)
           (let-values ([(l t r b) (frame-insets w)])
             (let ([mx (+ (window-x w) 12)] [my (+ (window-y w) 100)])
               (inject! `(mouse-move ,mx ,my))
               (steps 2)
               (let ([bar (window-ref w 'scrollbar #f)]
                     [region (window-region w mx my)])
                 (override! 'scrollbar-side)
                 (close-window! w)
                 (steps 1)
                 ;; from the title strip's bottom (15) to the frame's
                 (and (= l 28) (eq? region 'scrollbar) bar
                      (= (car bar) -28) (= (caddr bar) 24)
                      (= (cadr bar) (- 15 t))
                      (= (cadddr bar) (- (window-h w) 15)))))))))

(check "the REPL's scroll bar is on the style's side, and no wider than \
        its text's inset there (Interlisp's 24)"
       (let* ([r (repl)] [rs (window-ref r 'state)])
         (override! 'scrollbar-width 24)
         (do ([i 0 (+ i 1)]) ((= i 80)) (repl-add! rs 'output "a line"))
         (repl-scroll-set! rs 20)
         (invalidate!)
         (steps 2)
         (let-values ([(cx cy cw ch) (content-rect r)])
           (let* ([column (lambda (x)
                            (map (lambda (i) (canvas-pixel x (+ cy i)))
                                 (iota ch)))]
                  [right (list (column (+ cx 5)) (column (+ cx cw -5))
                               (column (+ cx 15)))])
             (override! 'scrollbar-side 'left)
             (invalidate!)
             (steps 2)
             (let ([left (list (column (+ cx 5)) (column (+ cx cw -5))
                               (column (+ cx 15)))])
               (override! 'scrollbar-side)
               (override! 'scrollbar-width)
               (close-window! r)
               (steps 1)
               (and (not (equal? (car right) (car left)))
                    (not (equal? (cadr right) (cadr left)))
                    (equal? (caddr right) (caddr left))))))))

(check "Mac draws no resize grip on a shaded window"
       (let ([w (open-window "Grip" 'size '(300 . 200) 'pos '(200 . 200)
                             'window-style 'mac)]
             [n 0])
         (steps 2)
         (let ([count (lambda ()
                        (set! n 0)
                        (fluid-let ([draw-resize-grip
                                     (lambda (x y) (set! n (+ n 1)))])
                          (screen-bytes))
                        n)])
           (let* ([open (count)] [shaded (begin (shade-window! w) (count))])
             (close-window! w)
             (steps 1)
             (= shaded (- open 1))))))

(check "a stipple's tile is made once for its rows and scale"
       (let* ([gray (stipple 'text #f "#..." "...." "...." "....")]
              [paint (lambda (s)
                       (picture-free!
                        (image 24 24 s (lambda () (fill-box 0 0 16 16 gray)
                                         (fill-box 0 0 8 8 gray)))))])
         (hashtable-clear! *stipple-tiles*)
         (paint 1)
         (let ([one (hashtable-size *stipple-tiles*)])
           (paint 1)
           (paint 1.5)
           (and (= one 1) (= (hashtable-size *stipple-tiles*) 2)))))

;;; the verifier's findings on steps 8 and 9

;; Runs the timers due within the next second: a save asked for soon.
(define (run-soon-timers!)
  (let ([real now-ms])
    (fluid-let ([now-ms (lambda () (+ (real) 1000))]) (steps 1))))

(check "Reset to defaults is saved, as a change is"
       (let ([saved (lambda ()
                      (cdr (assq 'changes
                                 (call-with-input-file *theme-file-path*
                                   read))))])
         (set-theme! 'corner-radius 3)
         (run-soon-timers!)
         (let ([before (saved)])
           (reset-theme!)
           (run-soon-timers!)
           (and (equal? before '((mac (corner-radius . 3))))
                (null? (saved))))))

(check "a title that reads as a number names a style that reads back as a \
        symbol, and save-style-as! writes any name so"
       (let ([reads-as-symbol?
              (lambda (name)
                (symbol? (read (open-string-input-port (format "~s" name)))))])
         (set! *settings-style-directory*
               (string-append out-dir "/saved-styles"))
         (let* ([names (map settings-style-name '("1984" "2" "-1" "1e3"))]
                [path (save-style-as! (string->symbol "12") "Twelve")]
                [form (call-with-input-file path read)])
           (set-style! 'mac)
           (set! *styles* (remp (lambda (s) (eq? (style-name s) '|12|))
                                *styles*))
           (delete-file path)
           (and (equal? names '(style-1984 style-2 style-1 style-1e3))
                (for-all reads-as-symbol? names)
                (eq? (cadr form) '|12|)))))

(check "the square styles honor every common option but the corner radius"
       (for-all (lambda (st)
                  (let ([fixed (with-style st (lambda () (theme 'fixed)))])
                    (and (equal? fixed '(corner-radius))
                         (not (memq 'title-height fixed)))))
                '(cons curses draft fold interlisp lambda reticle slab)))

;; A rounded rectangle's top-left pixel, drawn in style st: ink where the
;; corner is square, nothing where it is round.
(define (corner-pixel st)
  (pixel-at (image 40 20 1
                   (lambda ()
                     (with-style st
                       (lambda () (fill-box 0 0 40 20 #x000000 10)))))
            0 0))

(check "a style whose corner radius is 0 draws every rounded thing square, \
        an app's too; the rounded styles keep their round corners"
       (and (for-all (lambda (st) (= (corner-pixel st) #xff000000))
                     '(cons curses draft fold genera cadr interlisp lambda
                       reticle slab))
            (for-all (lambda (st) (zero? (corner-pixel st)))
                     '(mac windows spine halo))))

(check "the CADR's label strip lies under the content, its margin and \
        border under it; Genera's directly inside the border"
       (let ([strip-y (lambda (st)
                        (let ([w (open-window "Label" 'size '(300 . 150)
                                              'window-style st)])
                          (let-values ([(l t r b) (frame-insets w)])
                            (let ([y (caddr (assq 'title (frame-regions w)))]
                                  [h (window-h w)])
                              (close-window! w)
                              (list y (- h b) (- h 2 (- b 6)))))))])
         (let ([c (strip-y 'cadr)] [g (strip-y 'genera)])
           (and (= (car c) (cadr c)) (= (car g) (caddr g))))))

(check "an Override of another style's own option says whose it is and \
        that it does not apply here; in that style it does"
       (begin
         (override! 'genera-margin 3)
         (let ([label (settings-key-label 'genera-margin)]
               [here (settings-override-words 'genera-margin)])
           (set-style! 'genera)
           (let ([there (settings-override-words 'genera-margin)])
             (set-style! 'mac)
             (override! 'genera-margin)
             (and (equal? label "White margin (Genera)")
                  (equal? here "3 px; does not apply here")
                  (equal? there "3 px"))))))

(check "a pinned row reads Override; unpinned with the style's own value, \
        it leaves no change"
       (let ([o (assq 'corner-radius common-options)])
         (settings-pin! 'corner-radius #t)
         (let ([pinned (settings-row-label o)])
           (settings-pin! 'corner-radius #f)
           (and (equal? pinned "Corner radius · Override")
                (equal? (settings-row-label o) "Corner radius")
                (null? (style-changes-of 'mac))
                (null? (theme-overrides))))))

(check "a style's colors that are not options are saved and load back"
       (begin
         (set-style! 'interlisp)
         (set-theme! 'interlisp-title-shade #x808080)
         (set-theme! 'interlisp-scroll-shade #x404040)
         (theme-file-save!)
         (reset-theme!)
         (theme-file-load!)
         (let ([got (list (theme 'interlisp-title-shade)
                          (theme 'interlisp-scroll-shade))])
           (reset-theme!)
           (set-style! 'mac)
           (and (equal? got '(#x808080 #x404040))
                (theme-file-valid-value? 'genera-gray #x333333)))))

(check "the stipple tiles cached are at most 64"
       (begin
         (picture-free!
          (image 8 8 1 (lambda ()
                         (do ([i 0 (+ i 1)]) ((= i 70))
                           (fill-box 0 0 8 8 (stipple (* i 1000) #f "#."
                                                      ".#"))))))
         (<= (hashtable-size *stipple-tiles*) 64)))

(check "the who line counts one window, not one windows"
       (let ([w (open-window "Only" 'size '(200 . 100))] [texts '()])
         (set-style! 'genera)
         (steps 1)
         (let ([real draw-text])
           (fluid-let ([*windows* (list w)]
                       [draw-text (lambda (x y s . rest)
                                    (set! texts (cons s texts))
                                    (apply real x y s rest))])
             (screen-bytes)))
         (set-style! 'mac)
         (close-window! w)
         (steps 1)
         (and (member "1 window" texts) #t)))

(check "Settings' pane scroll bar is on the style's side, and shown on \
        hover only where the style says so, and not once the pointer has \
        left the window"
       (let ([s (settings)])
         (move-window! s 60 40)
         (focus-window! s)
         (steps 2)
         (let* ([ui (window-ref s 'ui)]
                [bar-x (lambda ()
                         (invalidate! s)
                         (steps 2)
                         (let ([r (ui-find ui 'pane-scrollbar)])
                           (and r (ui-region-x r))))]
                [sw (settings-sidebar-width)])
           (let-values ([(cx cy cw ch) (content-rect s)])
             (inject! `(mouse-move ,(+ cx 40) ,(+ cy 200)))   ; the sidebar
             (let ([right (bar-x)])
               (override! 'scrollbar-side 'left)
               (let ([left (bar-x)])
                 (override! 'scrollbar-show 'hover)
                 (let ([away (bar-x)])
                   (inject! `(mouse-move ,(+ cx sw 100) ,(+ cy 200)))
                   (let* ([over (bar-x)]
                          [gone (begin
                                  (inject! `(mouse-move ,(+ cx cw 30)
                                                        ,(+ cy 200)))
                                  (bar-x))])
                     (override! 'scrollbar-show)
                     (override! 'scrollbar-side)
                     (close-window! s)
                     (steps 1)
                     (and right (> right sw) (eqv? left (+ sw 1))
                          (not away) (eqv? over (+ sw 1)) (not gone))))))))))

(check "a change the style passes by is said, with its ↺"
       (let ([s (settings)] [texts '()])
         (set-style! 'curses)
         (set-theme! 'corner-radius 4)
         (steps 2)
         (let ([real draw-text])
           (fluid-let ([draw-text (lambda (x y str . rest)
                                    (set! texts (cons str texts))
                                    (apply real x y str rest))])
             (invalidate! s)
             (steps 1)))
         (let ([revert (and (ui-find (window-ref s 'ui) '(revert corner-radius))
                            #t)])
           (reset-style!)
           (set-style! 'mac)
           (close-window! s)
           (steps 1)
           (and revert
                (exists (lambda (t)
                          (string-contains-ci?
                           t "Curses sets this: 0 px; your change (4 px)"))
                        texts)))))

(check "Genera's and the CADR's frames lie on whole device pixels at 125, \
        150 and 175 %: their bottom rows are ink or paper, never between"
       (for-all
        (lambda (st)
          (for-all
           (lambda (k)
             (with-style st
               (lambda ()
                 (let* ([w (detached-window "Crisp" 'size '(200 . 100)
                                            'window-style st)]
                        [ww (window-w w)] [wh (window-h w)]
                        [img (image (exact (ceiling (* k (+ ww 4))))
                                    (exact (ceiling (* k (+ wh 4)))) k
                                    (lambda ()
                                      (genera-draw-under w 1 1 ww wh #t #f
                                                         #f)))]
                        [ink (color->pixel 'text)]
                        [paper (color->pixel (window-bg w))]
                        [x (exact (floor (* k (+ 1 (/ ww 2)))))]
                        [bottom (exact (floor (* k (+ 1 wh))))]
                        [rows (map (lambda (i)
                                     (pixel-at img x (- bottom i 1)))
                                   (iota 6))])
                   (picture-free! img)
                   (for-all (lambda (p) (or (= p ink) (= p paper)))
                            rows)))))
           '(1.25 1.5 1.75)))
        '(genera cadr)))
