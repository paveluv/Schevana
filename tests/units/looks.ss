;;; tests/units/looks.ss — the styles' own looks: Genera, the CADR, Interlisp,
;;; OPEN LOOK, Adwaita, Mac and ours, drawn and measured.

;;; The styles' own looks

(define (style-insets st)
  (let ([w (open-window "Insets" 'size '(300 . 200) 'window-style st)])
    (let-values ([(l t r b) (frame-insets w)])
      (close-window! w)
      (list l t r b))))

(check "the insets are Genera's 6 6 6 and its label strip, the CADR's 2 2 \
        2 and its label strip, the code font's line and 2, Interlisp's 4 \
        and its title strip, each by the font: in the machines' own fonts \
        Genera's 22 at the bottom (HL12I's 14 and 2) and the CADR's 16 \
        (CPTFONT's 12 and 2)"
       (let ([cadr-line (with-style 'cadr
                          (lambda () (font-line-height 'mono)))])
         (and (equal? (style-insets 'genera) (test-genera-insets))
              (equal? (style-insets 'genera) '(6 6 6 22))
              (equal? (style-insets 'cadr)
                      (list 2 2 2 (+ 2 (exact (round (+ 2 cadr-line))))))
              (equal? (style-insets 'cadr) '(2 2 2 16))
              (equal? (style-insets 'interlisp) (test-interlisp-insets)))))

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
                        none outside hover 24))
              (equal? (of 'spine 'title-double-click 'title-wheel)
                      '(maximize none))
              (equal? (of 'mac 'drag-feedback 'bell 'mouse-doc)
                      '(live none #f)))))

;; Draws an outline on white at 100 and 150 %, and returns for each scale
;; what changed, and what changed outside the outline's rectangle.
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

(check "Genera grays a window that another covers, selected or not, with \
        a sparse stipple, Genera 8.3's 16 by 8 tile, frame and all; one \
        wholly in view stays clear, selected or not (PUI p.1929); the CADR \
        grays none"
       (let* ([a (open-window "A" 'size '(200 . 120) 'pos '(100 . 100)
                              'window-style 'genera)]
              [b (open-window "B" 'size '(200 . 120) 'pos '(500 . 100)
                              'window-style 'genera)]
              ;; the first stipple dot in a's top-left corner, which b never
              ;; covers
              [dot (lambda ()
                     (canvas-pixel (* 16 (ceiling (/ (window-x a) 16)))
                                   (* 8 (ceiling (/ (window-y a) 8)))))]
              [colors (with-style 'genera
                        (lambda () (list (color->pixel 'text)
                                         (color->pixel 'window-bg))))])
         (focus-window! b)
         (steps 2)
         (let ([apart (dot)])
           (move-window! b 200 140)
           (focus-window! b)
           (steps 2)
           (let ([covered (dot)])
             (focus-window! a)
             (move-window! b 500 100)
             (focus-window! b)
             (steps 2)
             (let ([clear-again (dot)])
               (close-window! a)
               (close-window! b)
               ;; the CADR's, covered, stay clear
               (set! a (open-window "A" 'size '(200 . 120) 'pos '(100 . 100)
                                    'window-style 'cadr))
               (set! b (open-window "B" 'size '(200 . 120) 'pos '(200 . 140)
                                    'window-style 'cadr))
               (focus-window! b)
               (steps 2)
               (let ([cadr-dot (dot)])
                 (close-window! a)
                 (close-window! b)
                 (steps 1)
                 (printf "  ~s\n" (list apart covered clear-again cadr-dot))
                 (and (= apart (cadr colors)) (= covered (car colors))
                      (= clear-again (cadr colors))
                      (= cadr-dot (cadr colors)))))))))

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
        so ('faint-text-font, Genera's: its fonts' own italic strikes, and \
        JESS's italic for its bold, as JESS has no bold italic); other text \
        and styles keep theirs"
       (and (with-style 'mac
              (lambda () (eq? (faint-font 'text-faint (get-font 'ui))
                              (get-font 'ui))))
            (with-style 'genera
              (lambda ()
                (let ([of (lambda (f)
                            (font-family (faint-font 'text-faint f)))])
                  (and (equal? (of (get-font 'mono-bold))
                               "Genera CPTFONT Bold Italic")
                       (equal? (of (get-font 'genera-standout-font))
                               "Genera JESS13 Italic")
                       (equal? (of (get-font 'genera-command-font))
                               "Genera JESS13 Italic")
                       (eq? (faint-font 'text (get-font 'mono))
                            (get-font 'mono))))))))

(check "the CADR and Genera write in their own fonts, each at its cell's \
        height: CPTFONT for code and an app's text, the CADR's HL12 italic \
        and MEDFNT, Genera's HL14 bold for titles and JESS for commands and \
        menus"
       (let ([of (lambda (st . roles)
                   (with-style st
                     (lambda ()
                       (map (lambda (r)
                              (let ([f (get-font r)])
                                (list (font-family f) (font-size f))))
                            roles))))])
         (and (equal? (of 'cadr 'ui 'mono 'heading 'menu-font
                          'genera-choice-font)
                      '(("CADR CPTFONT" 12) ("CADR CPTFONT" 12)
                        ("CADR HL12 Italic" 14) ("CADR MEDFNT" 13)
                        ("CADR HL10" 12)))
              (equal? (of 'genera 'ui 'title 'genera-command-font
                          'menu-font 'ui-italic)
                      '(("Genera CPTFONT" 12) ("Genera HL14 Bold" 15)
                        ("Genera JESS13" 13) ("Genera JESS14" 14)
                        ("Genera HL12 Italic" 14))))))

;; Returns the rows of a bitmap glyph (char advance left top width row
;; ...) as text in a strip ascent high and descent below, o for a set bit,
;; with a column of . after it.
(define (looks-test-bitmap-rows g ascent height)
  (let ([w (list-ref g 4)] [top (list-ref g 3)] [rows (list-tail g 5)])
    (map (lambda (y)
           (let ([r (- y (- ascent top))])
             (list->string
              (map (lambda (x)
                     (if (and (< x w) (< -1 r (length rows))
                              (logbit? (- w 1 x) (list-ref rows r)))
                         #\o
                         #\.))
                   (iota (+ w 1))))))
         (iota height))))

(check "the CADR's and Genera's fonts draw every glyph as its data has \
        it, pixel for pixel, the glyphs drawn for them too: each face's, \
        side by side, light their bits and nothing else"
       (let ([bad
              (filter
               (lambda (face)
                 (let* ([name (car face)] [size (cadr face)]
                        [ascent (caddr face)]
                        [height (+ ascent (cadddr face))]
                        [gs (filter (lambda (g)
                                      (and (car g) (pair? (cddr g))
                                           (pair? (list-tail g 5))))
                                    (list-tail face 4))]
                        [ws (map (lambda (g) (+ 1 (list-ref g 4))) gs)]
                        [w (apply + ws)]
                        [f (font name size 'crisp)]
                        [want (apply map string-append
                                     (map (lambda (g)
                                            (looks-test-bitmap-rows
                                             g ascent height))
                                          gs))]
                        [got
                         (pixel-rows
                          (image w height 1
                                 (lambda ()
                                   (fill-box 0 0 w height #x000000)
                                   (let loop ([gs gs] [ws ws] [x 0])
                                     (unless (null? gs)
                                       (draw-text (- x (list-ref (car gs) 2))
                                                  0
                                                  (string (integer->char
                                                           (caar gs)))
                                                  #xffffff f)
                                       (loop (cdr gs) (cdr ws)
                                             (+ x (car ws)))))))
                          '((#xff000000 . #\.) (#xffffffff . #\o)))])
                   (not (equal? got want))))
               (append cadr-fonts genera-fonts))])
         (printf "  ~a faces, wrong: ~s\n"
                 (+ (length cadr-fonts) (length genera-fonts)) (map car bad))
         (null? bad)))

(check "the CADR's lozenge: 9 pixels high, 9 + 6 a character wide, pointed \
        ends, the name in capitals of MIT's 5X5"
       (let* ([img (image 30 12 1
                          (lambda ()
                            (fill-box 0 0 30 12 #xffffff)
                            (genera-lozenge 0 0 "a" #x000000)))]
              [r (list (genera-lozenge-width "AB")
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

(check "the kit's marks and avatars are a style's: Genera leaves out a \
        state's dot (its word is beside it) and an avatar beside the name, \
        else the initials in a lozenge"
       (let ([mark (lambda (style)
                     (with-style style
                       (lambda ()
                         (let* ([w #f]
                                [img (image 20 20 1
                                            (lambda ()
                                              (set! w (ui-draw-mark
                                                       2 2 14 'dot
                                                       'text-faint))))])
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
       (let ([probe   ; whether there is ink at x on any of the rows ys
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
                        (probe 'genera "MMMM" #t 26 '(40 41 42 43 44 45 46)))])
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

;; Returns the pixels at the points at, each (x y) in device pixels, of a
;; pw × ph image that thunk draws in Genera at scale s, with the extra
;; settings over the style's.
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
         (test-backlog!)
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
         (test-backlog!)
         (let* ([win (tasks)] [ui (window-ref win 'ui)])
           (focus-window! win)
           (steps 3)
           (let*-values ([(cx cy cw ch) (content-rect win)]
                         [(f) (ui-region-frame (ui-find ui '(column todo)))]
                         ;; the well's last row: a pad up from the board's
                         ;; bottom
                         [(ps) (map (lambda (dx)
                                      (canvas-pixel (+ cx (car f) dx)
                                                    (+ cy ch (- (ui-pad)) -1)))
                                    '(40 60 80))]
                         [(ink) (color->pixel 'text)])
             (close-window! win)
             (steps 1)
             (set-style! 'mac)
             (for-all (lambda (p) (= p ink)) ps)))))

(check "the CADR's progress bar is a line of its small font high, so that \
        its percentage shows: ink in the bar at 37 %"
       (with-style 'cadr
         (lambda ()
           (let* ([h (ui-progress-height)]
                  [ink (color->pixel 'text)]
                  [p (image 80 h 1
                            (lambda ()
                              (fill-box 0 0 80 h 'window-bg)
                              (ui-draw-progress 0 0 80 h '() 37/100)))]
                  [inked (exists (lambda (y)
                                   (exists (lambda (x) (= (pixel-at p x y) ink))
                                           (iota 80)))
                                 (iota h))])
             (printf "  ~a high, ~a\n" h inked)
             (and (>= h (font-line-height 'ui-small)) inked)))))

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
        its top, in two rows (UG p.2803), in Genera's words; its fields at \
        character columns; its windows field lists them, and one chosen is \
        selected"
       (let ([a (open-window "Alpha" 'size '(300 . 160) 'pos '(200 . 200))]
             [b (open-window "Beta" 'size '(300 . 160) 'pos '(600 . 200))])
         (set-style! 'genera)
         (inject! '(mouse-move 900 600))
         (steps 2)
         (let* ([lh (genera-line)] [dh (genera-doc-height)]
                [top (- (screen-h) dh lh)]
                [areas (placed-taskbar-areas)]
                [cw (font-char-width 'mono)]
                [row (lambda () (map (lambda (x) (canvas-pixel x (+ top 8)))
                                     (iota 300)))]
                [desk (row)]
                [sizes (list (topbar-height) (taskbar-height) (+ dh lh)
                             (* 2 (genera-doc-line)) dh)]
                [cols (map (lambda (a) (/ (cadr a) cw)) (cdr areas))]
                [colors (list (canvas-pixel 2 (+ top 1))
                              (canvas-pixel 2 (+ top dh 1))
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
             (let ([listed (and (test-menu-open?)
                                (map car (menu-items *menu*)))])
               (when (test-menu-open?)
                 ((cdr (assoc "Alpha" (menu-items *menu*))))
                 (close-menu!))
               (let ([chosen (eq? *focus* a)])
                 (set-style! 'mac)
                 (close-window! a)
                 (close-window! b)
                 (steps 2)
                 (and (= (car sizes) 0) (= (cadr sizes) (caddr sizes))
                      (= (cadddr sizes) (list-ref sizes 4))
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
         ;; the strip's top row, its middle and its last
         (let* ([x (+ (window-x w) 200)] [y (window-y w)]
                [strip (- (cadr (test-interlisp-insets)) 2)]
                [px (lambda () (map (lambda (dy) (canvas-pixel x (+ y dy)))
                                    (list 0 (quotient strip 2)
                                          (- strip 1))))]
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

(check "an Interlisp window shrinks to Medley's title-bar icon: a bar of \
        ink as tall as the title font's line and 8 wider than the title, at \
        the window's top left near the screen's top left and at its bottom \
        right near the bottom right; the middle button expands it"
       (let-values ([(dx dy dw dh) (desktop-rect)])
         (let* ([a (open-window "Shrunk" 'size '(300 . 160)
                                'pos (cons (+ dx 40) (+ dy 30))
                                'window-style 'interlisp)]
                [b (open-window "Shrunk too" 'size '(300 . 160)
                                'pos (cons (- (+ dx dw) 360)
                                           (- (+ dy dh) 220))
                                'window-style 'interlisp)]
                [icon (lambda (w) (find (lambda (i)
                                          (eq? (window-ref i 'icon-for) w))
                                        (windows)))])
           (steps 1)
           (minimize-window! a)
           (minimize-window! b)
           (steps 2)
           (let* ([ia (icon a)] [ib (icon b)]
                  [wide (lambda (w)
                          (in-window-theme w
                            (lambda ()
                              (max 26 (+ 8 (exact (ceiling
                                                   (text-width
                                                    (window-title w)
                                                    'ui-small))))))))]
                  [sized (and ia (= (window-w ia) (wide a))
                              (= (window-h ia)
                                 (in-window-theme a
                                   (lambda ()
                                     (exact (round (font-line-height
                                                    'ui-small)))))))]
                  [corners (and ia ib
                                (= (window-x ia) (window-x a))
                                (= (window-y ia) (window-y a))
                                (= (+ (window-x ib) (window-w ib))
                                   (+ (window-x b) (window-w b)))
                                (= (+ (window-y ib) (window-h ib))
                                   (+ (window-y b) (window-h b))))]
                  [ink (and ia (canvas-pixel (+ (window-x ia) 1)
                                             (+ (window-y ia) 1)))])
             (let ([x (+ (window-x ia) 2)] [y (+ (window-y ia) 2)])
               (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y middle 1)
                        `(mouse-up ,x ,y middle)))
             (steps 2)
             (let ([expanded (and (eq? (window-state a) 'normal)
                                  (not (icon a)))])
               (close-window! a)
               (close-window! b)
               (steps 2)
               (printf "  ~s\n" (list sized corners ink expanded))
               (and sized corners (eqv? ink #xff000000) expanded))))))

(check "Interlisp's text is in Medley's fonts, at their pixel sizes: Gacha \
        10 for code, 7 wide and 14 high, Helvetica 10 for the rest, 13 \
        high, so that its title strip is Medley's 15"
       (let ([of (with-style 'interlisp
                   (lambda ()
                     (list (font-family (get-font 'mono))
                           (font-family (get-font 'ui-small))
                           (font-family (get-font 'heading))
                           (font-char-width 'mono) (font-line-height 'mono)
                           (font-line-height 'ui-small))))])
         (printf "  ~s\n" of)
         (and (equal? of '("Medley Gacha 10" "Medley Helvetica 10"
                           "Medley Helvetica 12 Bold" 7.0 14 13))
              (= (cadr (test-interlisp-insets)) 17))))

(check "Adwaita's column view heading is a button's: at least 24 high, and \
        3 above and below"
       (with-style 'adwaita
         (lambda ()
           (let ([caption (round (font-line-height 'ui-small-bold))]
                 [h (theme 'table-header-height)])
             (if (<= caption 24) (= h 30) (= h (+ 6 caption)))))))

(check "GNOME's wallpaper draws a gone one as the wallpaper it falls back \
        to, its circles too, as the built-in wallpaper does"
       (let ([at (lambda (name)
                   (override! 'wallpaper name)
                   (image 80 50 1 (lambda () (gnome-draw-wallpaper 80 50))))])
         (let* ([shown (at (wallpaper-shown 'no-such-wallpaper))]
                [gone (at 'no-such-wallpaper)])
           (override! 'wallpaper)
           (let ([same (zero? (max-diff shown gone))])
             (picture-free! shown)
             (picture-free! gone)
             (and (eq? (wallpaper-shown 'no-such-wallpaper) 'gradient)
                  same)))))

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
                 ;; the bar runs from the title strip's bottom (the inset
                 ;; less the ink) to the frame's bottom
                 (let ([strip (- t 2)])
                   (and (= l 28) (eq? region 'scrollbar) bar
                        (= (car bar) -28) (= (caddr bar) 24)
                        (= (cadr bar) (- strip t))
                        (= (cadddr bar) (- (window-h w) strip))))))))))

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
                          (invalidate!)   ; windows keep what they drew
                          (test-screen-bytes))
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

;;; Saving, style names, options, corners and frames

;; Runs the timers due within the next second, such as a save asked for
;; soon.
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

(check "the square styles honor every common option but the corner radius, \
        and Interlisp, which draws no shadow and has Medley's own fonts, not \
        the shadow nor the fonts' options"
       (and (for-all (lambda (st)
                       (let ([fixed (with-style st (lambda () (theme 'fixed)))])
                         (and (equal? fixed '(corner-radius))
                              (not (memq 'title-height fixed)))))
                     '(cons curses draft fold lambda reticle slab))
            (let ([fixed (with-style 'interlisp (lambda () (theme 'fixed)))])
              (and (= (length fixed) 6)
                   (for-all (lambda (k) (memq k fixed))
                            '(corner-radius shadow ui-font ui-font-size
                              mono-font mono-font-size))))))

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
             (test-screen-bytes)))
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
             (inject! `(mouse-move ,(+ cx 40) ,(+ cy 200)))   ; over the sidebar
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

;;; OPEN LOOK: olwm's frame and OLGX's shades

(check "OLGX's shades of the window color: #cccccc's BG2, BG3 and \
        highlight are #b7b7b7, #666666 and #f4f4f4, the workspace's \
        #3a8fac, #204f5f and #4dc0e6, white's highlight white"
       (let ([of (lambda (c) (map (lambda (k) (open-look-shade c k))
                                  '(bg2 bg3 highlight)))])
         (and (equal? (of #xcccccc) '(#xb7b7b7 #x666666 #xf4f4f4))
              (equal? (of #x40a0c0) '(#x3a8fac #x204f5f #x4dc0e6))
              (equal? (of #xffffff) '(#xe5e5e5 #x7f7f7f #xffffff)))))

(check "OPEN LOOK has OLGX's four glyph fonts: resize corners 10, 11, 12 \
        and 14 square, the window button 14, 16, 18 and 22 wide, the \
        pushpin two sizes, 10's as 12's and 14's as 19's"
       (let* ([glyph open-look-font-glyph]
              [wh (lambda (size name)
                    (let ([g (glyph size name)])
                      (list (list-ref g 4) (length (list-tail g 5)))))])
         (and (equal? (map (lambda (s) (wh s 'ul-resize-outline))
                           '(10 12 14 19))
                      '((10 10) (11 11) (12 12) (14 14)))
              (equal? (map (lambda (s) (car (wh s 'abbrev-menu-button)))
                           '(10 12 14 19))
                      '(14 16 18 22))
              (equal? (glyph 10 'menu-pin-out) (glyph 12 'menu-pin-out))
              (equal? (glyph 14 'menu-pin-in) (glyph 19 'menu-pin-in))
              (not (equal? (glyph 12 'menu-pin-in) (glyph 14 'menu-pin-in)))
              (not (glyph 12 'no-such-glyph))
              (equal? (map open-look-size-near '(9 12 13 15 20))
                      '(10 12 12 14 19)))))

;; Returns the rows of OLGX's glyph name at size as text, o for a set bit
;; and . for the rest, with a column of . after it, h rows in all.
(define (looks-test-glyph-rows size name h)
  (let* ([g (open-look-font-glyph size name)]
         [w (list-ref g 4)]
         [rows (list-tail g 5)])
    (map (lambda (y)
           (list->string
            (map (lambda (x)
                   (if (and (< x w) (< y (length rows))
                            (logbit? (- w 1 x) (list-ref rows y)))
                       #\o
                       #\.))
                 (iota (+ w 1)))))
         (iota h))))

(check "OPEN LOOK draws each of OLGX's glyphs as text in the size's glyph \
        font, pixel for pixel: all fifty at each of the four sizes, side by \
        side, light the bits of their data and nothing else"
       (let* ([names (map car open-look-glyph-strings)]
              [drawn
               (lambda (size)
                 (let* ([gs (map (lambda (n) (open-look-font-glyph size n))
                                 names)]
                        [ws (map (lambda (g) (+ 1 (list-ref g 4))) gs)]
                        [w (apply + ws)]
                        [h (apply max (map (lambda (g)
                                             (length (list-tail g 5)))
                                           gs))]
                        [want (apply map string-append
                                     (map (lambda (n)
                                            (looks-test-glyph-rows size n h))
                                          names))]
                        [got
                         (pixel-rows
                          (image w h 1
                                 (lambda ()
                                   (fill-box 0 0 w h #x000000)
                                   (let loop ([ns names] [ws ws] [x 0])
                                     (unless (null? ns)
                                       (open-look-glyph x 0 (car ns) #xffffff)
                                       (loop (cdr ns) (cdr ws)
                                             (+ x (car ws)))))))
                          '((#xff000000 . #\.) (#xffffffff . #\o)))])
                   (equal? got want)))])
         (set-style! 'open-look)
         (let ([r (map (lambda (size)
                         (set-theme! 'ui-font-size size)
                         (drawn size))
                       '(10 12 14 19))])
           (reset-style!)
           (set-style! 'mac)
           (printf "  ~s\n" r)
           (equal? r '(#t #t #t #t)))))

(check "OPEN LOOK's frame is olwm's at each size: arms of 5, 5, 6 and 6, \
        23, 25, 29 and 35 above the pane, a footer's 16, 18, 21 and 27 \
        more below"
       (begin
         (set-style! 'open-look)
         (let ([r (map (lambda (size)
                         (set-theme! 'ui-font-size size)
                         (let ([w (open-window "F" 'size '(300 . 200)
                                               'footer "Left")])
                           (let-values ([(l t r b) (frame-insets w)])
                             (close-window! w)
                             (list size (style-insets 'open-look) b))))
                       '(10 12 14 19))])
           (reset-style!)
           (set-style! 'mac)
           (equal? r '((10 (5 23 5 5) 21) (12 (5 25 5 5) 23)
                       (14 (6 29 6 6) 27) (19 (6 35 6 6) 33))))))

(check "an OPEN LOOK window has a window button and four resize corners; \
        one opened 'above another is a pop-up, with a pushpin and no \
        corners"
       (begin
         (set-style! 'open-look)
         (let* ([w (open-window "Base" 'size '(300 . 200))]
                [p (open-window "Pop-up" 'size '(200 . 80) 'above w)]
                [r (list (map car (frame-regions w))
                         (map car (frame-regions p)))])
           (close-window! w)
           (reset-style!)
           (set-style! 'mac)
           (equal? r '((minimize resize-tl resize-tr resize-br resize-bl)
                       (close))))))

(check "a focused OPEN LOOK window has olwm's 3-pixel outline and its \
        header's recessed BG2 band in 3D, a band of ink in 2D; an \
        unfocused one, 2 pixels and BG1"
       (let ([probe
              (lambda (depth focus?)
                (set-style! 'open-look)
                (set-theme! 'open-look-depth depth)
                (let ([w (open-window "Probe" 'size '(300 . 200)
                                      'pos '(100 . 100))]
                      [other (open-window "Other" 'size '(100 . 80)
                                          'pos '(600 . 400))])
                  (focus-window! (if focus? w other))
                  (steps 2)
                  (let ([px (lambda (dx dy)
                              (canvas-pixel (+ (window-x w) dx)
                                            (+ (window-y w) dy)))])
                    (let ([r (list (= (px 2 60) (color->pixel 'text))
                                   (px 200 12))])
                      (close-window! w)
                      (close-window! other)
                      (steps 1)
                      r))))])
         (let ([r (list (probe '3d #t) (probe '2d #t) (probe '3d #f))])
           (reset-style!)
           (set-style! 'mac)
           (equal? r (list (list #t (color->pixel #xb7b7b7))
                           (list #t (color->pixel #x000000))
                           (list #f (color->pixel #xcccccc)))))))

;;; Adwaita: libadwaita's widgets and windows, GNOME Shell's desktop

;; Whether each of a pixel's channels is within 2 of color's: the GPU
;; rounds what it blends in its own way.
(define (adwaita-test-near? pixel color)
  (let ([want (color->pixel color)])
    (for-all (lambda (shift)
               (<= (abs (- (fxand (fxsra pixel shift) 255)
                           (fxand (fxsra want shift) 255)))
                   2))
             '(0 8 16))))

;; Returns the pixels at points of what draw draws in Adwaita, in a w × h
;; picture on the window's color.
(define (adwaita-test-pixels w h draw points)
  (with-style 'adwaita
    (lambda ()
      (let ([img (image w h 1 (lambda () (fill-box 0 0 w h 'window-bg)
                                (draw)))])
        (let ([ps (map (lambda (p) (pixel-at img (car p) (cdr p))) points)])
          (picture-free! img)
          ps)))))

(check "Adwaita's palettes are libadwaita 1.7's: the window #fafafb, the \
        text rgb(0 0 6 / 80%) on it, the accent GNOME's blue; dark, the \
        window #222226 and white text; the top bar black in both"
       (let ([of (lambda (p . keys)
                   (map (lambda (k) (plist-ref (palette-colors p) k #f))
                        keys))])
         (and (equal? (of 'adwaita 'bg-1 'bg-0 'text 'accent 'panel)
                      '(#xfafafb #xffffff #x323237 #x3584e4 #x000000))
              (equal? (of 'adwaita-dark 'bg-1 'bg-0 'text 'accent 'panel)
                      '(#x222226 #x1d1d20 #xffffff #x3584e4 #x000000))
              (with-style 'adwaita
                (lambda ()
                  (equal? (list (theme 'palette) (theme 'palette-dark))
                          '(adwaita adwaita-dark)))))))

(check "Adwaita's standalone colors are libadwaita's OKLab ones: blue \
        #0461be as text in the light style, #81d0ff in the dark, the \
        destructive red #c30000"
       (equal? (list (adwaita-standalone #x3584e4 #f)
                     (adwaita-standalone #x3584e4 #t)
                     (adwaita-standalone #xe01b24 #f))
               '(#x0461be #x81d0ff #xc30000)))

(check "an Adwaita button is a control high, 9 round, the text at 10 % \
        behind it; a suggested one the accent; a destructive one its red \
        at 15 %"
       (with-style 'adwaita
         (lambda ()
           (let* ([h (ui-control-height)]
                  [ps (adwaita-test-pixels 300 60
                        (lambda ()
                          (ui-draw-button 10 10 80 h '() "Go" #f)
                          (ui-draw-button 110 10 80 h '(primary) "Go" #f)
                          (ui-draw-button 210 10 80 h '(danger) "Go" #f))
                        ;; a point inside each, clear of its label, and a
                        ;; corner outside the radius of 9
                        '((14 . 20) (114 . 20) (214 . 20) (10 . 10)))])
             (and (= h (+ 10 (max 24 (round (font-line-height 'ui)))))
                  (= (theme 'adwaita-button-radius) 9)
                  (adwaita-test-near? (car ps) (mix 'window-bg 'text 0.1))
                  (adwaita-test-near? (cadr ps) 'accent)
                  (adwaita-test-near? (caddr ps)
                                      (mix 'window-bg 'adwaita-destructive-ink
                                           0.15))
                  (adwaita-test-near? (cadddr ps) 'window-bg))))))

(check "Adwaita sets a label as GTK does: its box the face's ascent and \
        descent rounded up, centered at a whole pixel, floored, the \
        baseline the unrounded ascent below its top; the kit's text the \
        same, where another style keeps the core's whole ascent"
       (let ([at '()])
         (with-style 'adwaita
           (lambda ()
             (let ([real draw-text] [h (ui-control-height)])
               (fluid-let ([draw-text (lambda (x y s . rest)
                                        (set! at (cons (list s x y) at))
                                        (apply real x y s rest))])
                 (image 120 60 1
                        (lambda () (ui-draw-button 10 10 81 h '() "Go" #f))))
               (let-values ([(a d) (text-face-extent 'ui-bold)])
                 (let ([top (+ 10 (floor (/ (- h (ceiling (+ a d))) 2)))])
                   (and (equal? (assoc "Go" at)
                                (list "Go"
                                      (+ 10 (floor (/ (- 81 (text-width
                                                             "Go" 'ui-bold))
                                                      2)))
                                      (+ top (- a (font-ascent 'ui-bold)))))
                        (let-values ([(a d) (text-face-extent 'ui)])
                          (= (ui-text-y 8 'ui)
                             (+ 8 (- a (font-ascent 'ui)))))
                        (with-style 'mac
                          (lambda () (= (ui-text-y 8 'ui) 8)))))))))))

(check "an Adwaita boxed list's row is libadwaita's: its header 50 high, \
        2 of padding round it and a line under it, 55; its title 14 in; \
        its button row that adds one 40 and 2 above and below, 44, its \
        plus and title, a heading, centered together, 6 apart"
       (let ([at '()])
         (with-style 'adwaita
           (lambda ()
             (let ([real draw-text])
               (fluid-let ([draw-text (lambda (x y s . rest)
                                        (set! at (cons (cons s x) at))
                                        (apply real x y s rest))])
                 (image 320 60 1
                        (lambda () (ui-draw-add-row 0 0 300 44 '() "Add"))))
               (and (= (ui-row-height "Title" #f) 55)
                    (= (ui-row-height "Title" "Subtitle") 55)
                    (= (ui-add-row-height) 44)
                    (= (cadr (assq 'title (ui-row-areas 0 0 300 55 0 0))) 14)
                    (equal? (assoc "Add" at)
                            (cons "Add"
                                  (+ 14 (floor (/ (- 272
                                                     (+ 16 6
                                                        (text-width
                                                         "Add" 'ui-bold)))
                                                  2))
                                     16 6)))))))))

(check "an Adwaita check box is 20 square, a ring of the text at 15 % \
        empty, the accent checked"
       (with-style 'adwaita
         (lambda ()
           (let ([ps (adwaita-test-pixels 100 30
                       (lambda ()
                         (ui-draw-checkbox 10 0 20 30 '() #f)
                         (ui-draw-checkbox 50 0 20 30 '(checked) #f))
                       ;; the box is 5 down: points on its ring's middle
                       ;; row, inside it, and in a checked box's corner,
                       ;; clear of the check
                       '((20 . 5) (20 . 15) (52 . 22) (31 . 15)))])
             (and (adwaita-test-near? (car ps) (mix 'window-bg 'text 0.15))
                  (adwaita-test-near? (cadr ps) 'window-bg)
                  (adwaita-test-near? (caddr ps) 'accent)
                  (adwaita-test-near? (cadddr ps) 'window-bg))))))

(check "an Adwaita switch is 46 by 26: its track the text at 15 % off and \
        the accent on, its knob 20 across, 3 in"
       (with-style 'adwaita
         (lambda ()
           (let-values ([(tw th) (ui-toggle-track)])
             (let ([ps (adwaita-test-pixels 120 30
                         (lambda ()
                           (ui-draw-toggle 0 0 46 26 '() #f)
                           (ui-draw-toggle 60 0 46 26 '(checked) #f))
                         ;; the off track at its right, the off knob's
                         ;; middle, the on track at its left, the on knob
                         '((41 . 13) (13 . 13) (65 . 13) (93 . 13)))])
               (and (equal? (list tw th) '(46 26))
                    (adwaita-test-near? (car ps) (mix 'window-bg 'text 0.15))
                    (adwaita-test-near? (cadr ps) 'adwaita-slider)
                    (adwaita-test-near? (caddr ps) 'accent)
                    (adwaita-test-near? (cadddr ps) #xffffff)))))))

(check "an Adwaita window's title bar is a header bar, 12 more than a \
        control; its only button is close, unless all three are asked for"
       (test-finally
        (lambda ()
          (set-style! 'adwaita)
          (let* ([w (open-window "Header" 'size '(400 . 200))]
                 [r (list (style-insets 'adwaita)
                          (map car (frame-regions w)))])
            (set-theme! 'adwaita-window-buttons 'all)
            (let ([all (map car (frame-regions w))])
              (close-window! w)
              (and (equal? (car r) (list 0 (+ 12 (ui-control-height)) 0 0))
                   (equal? (cadr r) '(close))
                   (equal? all '(minimize maximize close))))))
        (lambda ()
          (reset-style!)
          (set-style! 'mac))))

(let ([ps (adwaita-test-pixels 120 40
            (lambda ()
              (ui-draw-panel 10 5 100 30 '(toast))
              (ui-draw-panel 0 0 8 8 '(tooltip)))
            '((60 . 20) (4 . 4)))])
  ;; the tooltip over the light window's #fafafb
  (check (format "Adwaita's popups: a toast is libadwaita's #505053 pill, a \
                  tooltip black at 80 % ~s" ps)
         (and (adwaita-test-near? (car ps) #x505053)
              (adwaita-test-near? (cadr ps) #x323237))))

(check "GNOME's desktop is GNOME Shell's, around Adwaita's windows: the top \
        bar 2.2 em of GNOME's text, its 11 pt our 15, so 32; the Activities \
        button and the dash's Show Apps open the apps"
       (test-finally
        (lambda ()
          (set-style! 'gnome)
          (steps 1)
          (and (= (topbar-height)
                  (max 32 (round (* 2.2 44/45 (theme 'ui-font-size)))))
               (eq? (car (car (placed-topbar-areas))) 'launcher)
               (eq? (car (car (placed-taskbar-areas))) 'launcher)))
        (lambda () (set-style! 'mac))))

;; The distinct values of xs, from least to greatest.
(define (looks-distinct xs)
  (sort < (fold-left (lambda (acc x) (if (member x acc) acc (cons x acc)))
                     '() xs)))

(check "GNOME's launcher is GNOME Shell's app grid: its search entry 24 em \
        wide, 12 under the top bar; on a screen wider than tall, pages of 4 \
        rows of 6 square tiles, each 30 and a line more than one of the \
        Shell's icon sizes, 12 to 36 apart; and a dot for each page"
       (test-finally
        (lambda ()
          (set-style! 'gnome)
          (steps 1)
          (let*-values ([(dx dy dw dh) (desktop-rect)]
                        [(lh) (font-line-height 'ui)]
                        [(as) (app-grid-areas 30 0)]
                        [(tiles) (filter (lambda (a) (fixnum? (car a))) as)]
                        [(xs) (looks-distinct (map cadr tiles))]
                        [(ys) (looks-distinct (map caddr tiles))]
                        [(t) (cadddr (car tiles))]
                        [(pitch) (- (cadr xs) (car xs))])
            (printf "  tile ~s, pitch ~s\n" t pitch)
            (and (> (screen-w) (screen-h))
                 (= (length tiles) 24) (= (length xs) 6) (= (length ys) 4)
                 (for-all (lambda (a) (= (cadddr a) (car (cddddr a)) t))
                          tiles)
                 (exists (lambda (s) (= t (round (+ s 30 lh))))
                         '(96 64 48 32 24 16))
                 (<= (+ t 12) pitch (+ t 36))
                 (= 2 (length (filter (lambda (a) (pair? (car a))) as)))
                 (= 6 (length (filter (lambda (a) (fixnum? (car a)))
                                      (app-grid-areas 30 1))))
                 (equal? (cddr (assq 'search as))
                         (list (+ dy 12)
                               (min (exact (round (* 24 (adwaita-em))))
                                    (- dw 24))
                               (exact (round (+ lh 18))))))))
        (lambda () (set-style! 'mac))))

(check "GNOME's Show Apps opens the app grid, over which the top bar is \
        clear, showing the overview's color, and a second press closes it, \
        the bar black again"
       (test-finally
        (lambda ()
          (set-style! 'gnome)
          (for-each close-window! (windows))
          (steps 1)
          (let ([press! (lambda ()
                          (let* ([l (cdr (assq 'launcher
                                               (placed-taskbar-areas)))]
                                 [x (exact (round (+ (car l)
                                                     (/ (caddr l) 2))))]
                                 [y (exact (round (+ (cadr l)
                                                     (/ (cadddr l) 2))))])
                            (inject! `(mouse-move ,x ,y)
                                     `(mouse-down ,x ,y left 1)
                                     `(mouse-up ,x ,y left))
                            (steps 1)))])
            (press!)
            (let ([form (launcher-open?)] [over (canvas-pixel 200 2)])
              (press!)
              (and (eq? form 'grid)
                   (= over (color->pixel (theme 'adwaita-overview)))
                   (not (launcher-open?))
                   (= (canvas-pixel 200 2) (color->pixel (theme 'panel)))))))
        (lambda () (close-app-grid!) (set-style! 'mac))))

(check "a press on GNOME's search entry, with nothing typed, rings it"
       (test-finally
        (lambda ()
          (set-style! 'gnome)
          (steps 1)
          (toggle-launcher!)
          (steps 1)
          (let* ([a (cdr (assq 'search (app-grid-areas
                                        (length (app-grid-entries)) 0)))]
                 [x (car a)] [y (cadr a)] [w (caddr a)] [h (cadddr a)]
                 [ring (lambda () (canvas-pixel (+ x 1) (+ y (quotient h 2))))]
                 [before (ring)]
                 [cx (+ x (quotient w 2))] [cy (+ y (quotient h 2))])
            (inject! `(mouse-move ,cx ,cy) `(mouse-down ,cx ,cy left 1)
                     `(mouse-up ,cx ,cy left))
            (steps 1)
            (let ([after (ring)])
              (and (= before (color->pixel (theme 'adwaita-overview-entry)))
                   (not (= after before))
                   (launcher-open?)
                   (string=? *app-grid-filter* "")))))
        (lambda () (close-app-grid!) (set-style! 'mac))))

;;; OPEN LOOK's controls: OLGX's buttons on XView's panes

(check "OPEN LOOK's buttons are OLGX's: 18, 20, 22 and 28 high in 2D and \
        a pixel less in 3D, the control height; as wide as the label and \
        an end of 8, 9, 11 and 18 each side; a glyph alone an abbreviated \
        button, 14, 16, 18 and 21 wide and a pixel less high"
       (begin
         (set-style! 'open-look)
         (let ([r (map (lambda (depth)
                         (set-theme! 'open-look-depth depth)
                         (map (lambda (size)
                                (set-theme! 'ui-font-size size)
                                (let-values
                                    ([(w h) (ui-button-size "Button" #f)]
                                     [(aw ah) (ui-button-size #f 'plus)])
                                  (list h (ui-control-height)
                                        (- w (exact (ceiling
                                                     (text-width "Button"
                                                                 'ui))))
                                        aw ah)))
                              '(10 12 14 19)))
                       '(2d 3d))])
           (reset-style!)
           (set-style! 'mac)
           (equal? r '(((18 18 16 14 13) (20 20 18 16 15) (22 22 22 18 17)
                        (28 28 36 21 20))
                       ((17 17 16 14 13) (19 19 18 16 15) (21 21 22 18 17)
                        (27 27 36 21 20)))))))

(check "OPEN LOOK has OLGX's button glyphs: an end's top-left piece as \
        tall as the button, 2D's right end a pixel wider for the shadow, \
        and each middle a pixel wide, drawn as long as the run"
       (let* ([g open-look-font-glyph] [sizes '(10 12 14 19)]
              [w (lambda (s name) (list-ref (g s name) 4))])
         (and (equal? (map (lambda (s) (length (list-tail (g s 'button-ul) 5)))
                           sizes)
                      '(18 20 22 28))
              (equal? (map (lambda (s) (w s 'button-outline-right-endcap))
                           sizes)
                      '(9 10 12 19))
              (for-all (lambda (s)
                         (for-all (lambda (m) (= 1 (w s m)))
                                  '(button-top-1 button-bottom-1 button-fill-1
                                    dflt-button-middle-1
                                    button-outline-middle-1
                                    button-fill-2d-middle-1)))
                       sizes))))

(check "OLGX cuts a label too wide for its button by the character that \
        passes the width and the one before it; one that fits stays whole"
       (let* ([one (lambda (c) (text-width (string c) 'ui))]
              [w (+ 1/2 (apply + (map one (string->list "Butt"))))])
         (and (string=? (open-look-label-cut "Button" w 'ui) "But")
              (string=? (open-look-label-cut "Butt" w 'ui) "Butt"))))

(check "an OPEN LOOK button is OLGX's: in 3D a highlight top, a BG3 \
        default ring a pixel inside it, a BG2 face when pressed; in 2D an \
        outline of ink, the ring a pixel in, ink inside when pressed; the \
        pane BG1 in 3D and white in 2D; inactive, the pane's color over \
        every pixel where x + y is odd, counted from the pane's corner"
       (let ([probe
              (lambda (depth)
                (set-style! 'open-look)
                (set-theme! 'ui-font-size 12)
                (set-theme! 'open-look-depth depth)
                (let* ([h (ui-control-height)]
                       [w (open-window "Buttons" 'size '(200 . 120)
                                       'pos '(100 . 100)
                                       'draw (lambda (win ww wh)
                                               (ui-draw-button 10 10 60 h
                                                               '(primary)
                                                               "a" #f)
                                               (ui-draw-button 10 40 60 h
                                                               '(pressed)
                                                               "a" #f)
                                               (ui-draw-button 10 70 60 h
                                                               '(disabled)
                                                               "a" #f)))])
                  (focus-window! w)
                  (steps 2)
                  (let-values ([(l t r b) (frame-insets w)])
                    (let* ([ox (+ (window-x w) l)] [oy (+ (window-y w) t)]
                           [px (lambda (x y) (canvas-pixel (+ ox x)
                                                           (+ oy y)))]
                           [r (list (even? (+ ox oy))
                                    (px 40 10) (px 40 11) (px 40 12)
                                    (px 40 45) (px 5 5)
                                    (px 40 70) (px 41 70))])
                      (close-window! w)
                      (steps 1)
                      r))))])
         (let ([r3 (probe '3d)] [r2 (probe '2d)])
           (reset-style!)
           (set-style! 'mac)
           (let ([c color->pixel])
             (and (equal? r3 (list #t (c #xf4f4f4) (c #xcccccc) (c #x666666)
                                   (c #xb7b7b7) (c #xcccccc)
                                   (c #xf4f4f4) (c #xcccccc)))
                  (equal? r2 (list #t (c #x000000) (c #xffffff) (c #x000000)
                                   (c #x000000) (c #xffffff)
                                   (c #x000000) (c #xffffff))))))))

;;; the CADR's and Genera's behaviors, as Schevana2 ported them from their
;;; sources

(check "the CADR's numbers from its sources: a blinker's phase 250 ms \
        (HALF-PERIOD), a choice box CPTFONT's 12, a menu row MEDFNT's 13 \
        and VSP 2 (a blank one between groups), a who line of two CPTFONT \
        rows with no spacing, a hint in TR10I; its scroll bar keeps five \
        pixels and scales both ends (SCROLL-BAR-DRAW), with no least length"
       (with-style 'cadr
         (lambda ()
           (let ([thumb (lambda (start size)
                          (cdr (assq 'thumb (cadr-scrollbar-areas
                                             0 0 3 105 start size))))])
             (and (= (theme 'text-blink-ms) 250)
                  (= (genera-choice-side) 12)
                  (= (theme 'menu-item-height) 15)
                  (= (theme 'menu-separator-height) 15)
                  (= (taskbar-height) 24)
                  (equal? (font-family (get-font (theme 'label-hint-font)))
                          "CADR TR10 Italic")
                  (equal? (thumb 0 1/10) '(0 0 3 15))
                  (equal? (thumb 1/2 1/100) '(0 50 3 6)))))))

(check "Genera's settings: its dropdown marks the current choice with *, \
        which its fonts have; shapes crisp, no glow and no tint on a screen \
        one bit deep, a transcript's lines CPTFONT's 12 and 2; a glyph that \
        can't be used is drawn through the 50 % gray, not in half ink; \
        a window moves by its outline; a menu's chosen entry is boxed \
        around its ink, its separators a blank row; nothing under a dialog"
       (with-style 'genera
         (lambda ()
           (let ([scrim (image 10 10 1
                               (lambda ()
                                 (fill-box 0 0 10 10 'window-bg)
                                 (ui-draw-scrim 0 0 10 10 '())))])
             (and (equal? (theme 'dropdown-selected-mark) "  *")
                  (equal? (theme 'disabled-fade) '(".#" "#."))
                  (not (theme 'drawing-antialias))
                  (not (theme 'fill-glow))
                  (= (theme 'surface-tint) 0)
                  (= (transcript-line-height) 14)
                  (eq? (theme 'drag-feedback) 'outline)
                  (eq? (theme 'menu-highlight) 'ink)
                  (= (theme 'menu-separator-height) (theme 'menu-item-height))
                  (for-all (lambda (y)
                             (for-all (lambda (x)
                                        (= (pixel-at scrim x y)
                                           (color->pixel 'window-bg)))
                                      (iota 10)))
                           (iota 10)))))))

(check "Genera's scroll bar as the 1998 captures show it: dotted 1-pixel \
        sides, a box at each end, and the elevator a 1-pixel outline on \
        paper around its stipple"
       (with-style 'genera
         (lambda ()
           (let* ([t (cdr (assq 'thumb (ui-scrollbar-areas 0 0 10 100 0
                                                           3/10)))]
                  [ty (cadr t)]
                  [img (image 10 100 1
                              (lambda ()
                                (fill-box 0 0 10 100 'window-bg)
                                (ui-draw-scrollbar 0 0 10 100 '() 0 3/10)))]
                  [ink (color->pixel 'text)] [paper (color->pixel 'window-bg)]
                  [at (lambda (x y) (pixel-at img x y))]
                  [side (map (lambda (y) (at 0 (+ 40 y))) (iota 6))]
                  [r (list side
                           (map (lambda (x) (at (+ x 1) ty)) (iota 8))
                           (at 1 (+ ty 1)))])
             (printf "  ~s\n" r)
             (and (equal? side (list ink paper ink paper ink paper))
                  (for-all (lambda (p) (= p ink)) (cadr r))
                  (member (caddr r) (list ink paper)))))))

(check "Genera boxes the word under the mouse a clear pixel off its ink: \
        no pixel of the box touches the word, though the word fills the \
        button's height"
       (with-style 'genera
         (lambda ()
           (let* ([w 60] [h (font-line-height 'genera-command-font)]
                  [draw (lambda (flags)
                          (pixel-rows
                           (image (+ w 8) (+ h 8) 1
                                  (lambda ()
                                    (fill-box 0 0 (+ w 8) (+ h 8) #xffffff)
                                    (ui-draw-button 4 4 w h flags "Wjgy"
                                                    #f)))
                           '((#xffffffff . #\.))))]
                  [plain (draw '())] [boxed (draw '(hover))]
                  [at (lambda (rows x y)
                        (and (< -1 y (length rows))
                             (< -1 x (string-length (car rows)))
                             (char=? (string-ref (list-ref rows y) x) #\#)))]
                  [box (filter (lambda (p) (and (apply at boxed p)
                                                (not (apply at plain p))))
                               (apply append
                                      (map (lambda (y)
                                             (map (lambda (x) (list x y))
                                                  (iota (+ w 8))))
                                           (iota (+ h 8)))))])
             (and (pair? box)
                  (not (exists (lambda (p)
                                 (exists (lambda (d)
                                           (at plain (+ (car p) (car d))
                                               (+ (cadr p) (cadr d))))
                                         '((-1 0) (1 0) (0 -1) (0 1)
                                           (-1 -1) (1 1) (-1 1) (1 -1))))
                               box)))))))

(check "a Genera menu's chosen entry is boxed around its ink: the box, a \
        clear pixel, then the word"
       (begin
         (set-style! 'genera)
         (open-menu! 300 300 (list (cons "Alpha" void) (cons "Beta" void)))
         (steps 1)
         (let* ([a (map (lambda (v) (exact (floor v)))
                        (cdr (assv 0 (placed-menu-areas *menu*))))]
                [mx (+ (car a) (quotient (caddr a) 2))]
                [my (+ (cadr a) (quotient (cadddr a) 2))])
           (inject! `(mouse-move ,mx ,my))
           (steps 2)
           (let* ([ink (color->pixel 'text)]
                  [row (map (lambda (x) (canvas-pixel (+ (car a) x) my))
                            (iota (caddr a)))]
                  ;; past the menu's own border, the box's left side
                  [inside (list-index (lambda (p) (not (= p ink))) row)]
                  [first (and inside
                              (let ([i (list-index (lambda (p) (= p ink))
                                                   (list-tail row inside))])
                                (and i (+ inside i))))]
                  [r (and first (list (list-ref row first)
                                      (list-ref row (+ first 1))))])
             (close-menu!)
             (set-style! 'mac)
             (steps 1)
             (printf "  ~s\n" r)
             (and r (= (car r) ink) (not (= (cadr r) ink)))))))

;; A centered menu's keys stand in a column of their own: an entry's key,
;; at the right in the faint font (Genera's italic), never runs into its
;; words, which are centered left of the keys, and the menu is wide enough
;; to hold both.
(check "a Genera menu with keys keeps them in a column of their own: a \
        clear gap between an entry's words and its key, and the key whole \
        inside the menu"
       (begin
         (set-style! 'genera)
         (open-menu! 300 300 (list (cons "Bind to $w for the REPL" void)
                                   (cons "Maximize\tCtrl+Shift+M" void)
                                   (cons "Close\tCtrl+Shift+W" void)))
         (inject! '(mouse-move 10 10))
         (steps 2)
         (let* ([a (map (lambda (v) (exact (floor v)))
                        (cdr (assv 1 (placed-menu-areas *menu*))))]
                [x (car a)] [y (cadr a)] [w (caddr a)] [h (cadddr a)]
                [ink (color->pixel 'text)]
                ;; the columns inside the border with ink in the row
                [cols (filter (lambda (cx)
                                (exists (lambda (dy)
                                          (= (canvas-pixel cx (+ y dy)) ink))
                                        (iota h)))
                              (map (lambda (i) (+ x 2 i)) (iota (- w 4))))]
                [gap (let loop ([cs cols] [best 0])
                       (if (or (null? cs) (null? (cdr cs)))
                           best
                           (loop (cdr cs)
                                 (max best (- (cadr cs) (car cs) 1)))))]
                [r (list gap (and (pair? cols)
                                  (- (+ x w) (car (last-pair cols)))))])
           (close-menu!)
           (set-style! 'mac)
           (steps 1)
           (printf "  ~s\n" r)
           (and (>= gap 16) (cadr r) (> (cadr r) 2)))))

;; What only the mouse shows on the Lisp machines is the box around what it
;; is over; a part that had no box of its own there now has one, and
;; Interlisp's default button, its accent its ink, still changes under the
;; mouse.
(check "Genera and the CADR box a radio, a slider and the live badge under \
        the mouse; the CADR's faint text is as black as the rest; \
        Interlisp's default button changes under the mouse"
       (let* ([picture (lambda (draw flags)
                         (picture-bytes
                          (image 160 46 1
                                 (lambda ()
                                   (fill-box 0 0 160 46 'window-bg)
                                   (draw 8 8 140 30 flags)))))]
              [hot? (lambda (draw)
                      (not (bytevector=? (picture draw '())
                                         (picture draw '(hover)))))]
              [parts
               (list (lambda (x y w h f)
                       (ui-draw-radio x y w h f "Radio" #f #f))
                     (lambda (x y w h f)
                       (ui-draw-slider (+ x 8) y (- w 16) (ui-slider-height)
                                       f 3/5 #f))
                     (lambda (x y w h f)
                       (ui-draw-live-badge x y w 20 f "Live")))]
              [lispm (map (lambda (style)
                            (set-style! style)
                            (map hot? parts))
                          '(genera cadr))]
              [black? (begin (set-style! 'cadr)
                             (= (color->pixel 'text-faint)
                                (color->pixel 'text)))]
              [primary (begin (set-style! 'interlisp)
                              (hot? (lambda (x y w h f)
                                      (ui-draw-button x y w h
                                                      (cons 'primary f)
                                                      "Primary" #f))))])
         (set-style! 'mac)
         (printf "  ~s\n" (list lispm black? primary))
         (and (equal? lispm '((#t #t #t) (#t #t #t))) black? primary)))

(check "Genera's banner is output in a border, ink and paper alone, with \
        no tint"
       (begin
         (set-style! 'genera)
         (let* ([p (image 300 40 1
                          (lambda ()
                            (fill-box 0 0 300 40 'window-bg)
                            (ui-draw-banner 4 4 292 32 '() "You are offline"
                                            #f)))]
                [b (picture-bytes p)]
                [seen (make-eqv-hashtable)])
           (do ([i 0 (+ i 4)]) ((= i (bytevector-length b)))
             (hashtable-set! seen (bytevector-u32-native-ref b i) #t))
           (let ([corner (pixel-at p 4 4)] [ink (pixel-at p 4 20)])
             (set-style! 'mac)
             (printf "  ~s\n" (hashtable-size seen))
             (and (= (hashtable-size seen) 2) (= corner ink))))))

;; The CADR's menus, from its menu code (System 99's menu.lisp, mouse.lisp).
(define (cadr-menu-entries)
  (list (cons "Alpha\tCtrl+A" void) (cons "Beta\tCtrl+Shift+B" void)
        (cons "Gamma" void)))

(check "a CADR menu is its entries' names alone (no keys, no filter until \
        something is typed), boxed only under the mouse, and it goes once \
        the mouse leaves it by more than 25 pixels"
       (begin
         (set-style! 'cadr)
         (inject! '(mouse-move 10 10))
         (steps 1)
         (open-menu! 300 300 (cadr-menu-entries) 'filter #t 'tag 'cadr-test)
         (steps 1)
         (let* ([areas (placed-menu-areas *menu*)]
                [box (map (lambda (v) (exact (floor v))) (cdar areas))]
                [a0 (map (lambda (v) (exact (floor v)))
                         (cdr (assv 0 areas)))]
                [row-x (car a0)] [row-y (cadr a0)]
                [mid (list (+ row-x (quotient (caddr a0) 2))
                           (+ row-y (quotient (cadddr a0) 2)))]
                [no-filter? (not (assq 'filter areas))]
                [words-only?   ; the row's ink has no gap as wide as a key's
                 (let* ([ink (color->pixel 'text)]
                        [cols (filter
                               (lambda (cx)
                                 (exists (lambda (dy)
                                           (= (canvas-pixel cx (+ row-y dy))
                                              ink))
                                         (iota (cadddr a0))))
                               (map (lambda (i) (+ (car box) 2 i))
                                    (iota (- (caddr box) 4))))])
                   (let loop ([cs cols] [best 0])
                     (if (or (null? cs) (null? (cdr cs)))
                         (< best 16)
                         (loop (cdr cs)
                               (max best (- (cadr cs) (car cs) 1))))))]
                [start (menu-sel *menu*)])
           (inject! `(mouse-move ,(car mid) ,(cadr mid)))
           (steps 1)
           (let ([over (menu-sel *menu*)])
             ;; out of the menu by 10 pixels: none chosen, still open
             (inject! `(mouse-move ,(- (car box) 10) ,(cadr mid)))
             (steps 1)
             (let ([near (and *menu* (menu-sel *menu*))])
               ;; by 40: the menu goes
               (inject! `(mouse-move ,(- (car box) 40) ,(cadr mid)))
               (steps 1)
               (let ([gone? (not *menu*)])
                 (close-menu!)
                 (open-menu! 300 300 (cadr-menu-entries) 'filter #t
                             'tag 'cadr-test)
                 (inject! '(text "b"))
                 (steps 1)
                 (let* ([areas (placed-menu-areas *menu*)]
                        [typed? (and (assq 'filter areas) #t)]
                        [shown (map car (menu-entries *menu*))])
                   (close-menu!)
                   (set-style! 'mac)
                   (steps 1)
                   (let ([r (list no-filter? words-only? start over near gone?
                                  typed? (length shown))])
                     (printf "  ~s\n" r)
                     (equal? r '(#t #t -1 0 -1 #t #t 1))))))))))

(check "a CADR menu opens on the entry last chosen from menus of its kind: \
        its words under the pointer; with none yet, centered on it"
       (begin
         (set-style! 'cadr)
         (set! *menu-last-choices* '())
         (inject! '(mouse-move 500 400))
         (steps 1)
         (open-menu! 500 400 (cadr-menu-entries) 'tag 'cadr-kind)
         (let* ([box (cdar (placed-menu-areas *menu*))]
                [center (list (+ (car box) (quotient (caddr box) 2))
                              (+ (cadr box) (quotient (cadddr box) 2)))])
           (inject! `(mouse-move ,(car center) ,(+ (cadr center) 0)))
           ;; choose Beta by its area
           (let* ([a (cdr (assv 1 (placed-menu-areas *menu*)))])
             (menu-activate! 1)
             (let ([chosen (not *menu*)])
               (open-menu! 500 400 (cadr-menu-entries) 'tag 'cadr-kind)
               (let ([at (menu-entry-at 500 400)])
                 (close-menu!)
                 (open-menu! 500 400 (cadr-menu-entries) 'tag 'other)
                 (let* ([box (cdar (placed-menu-areas *menu*))]
                        [c (list (+ (car box) (quotient (caddr box) 2))
                                 (+ (cadr box) (quotient (cadddr box) 2)))])
                   (close-menu!)
                   (set! *menu-last-choices* '())
                   (set-style! 'mac)
                   (steps 1)
                   (let ([r (list chosen at
                                  (<= (abs (- (car c) 500)) 1)
                                  (<= (abs (- (cadr c) 400)) 1))])
                     (printf "  ~s\n" r)
                     (equal? r '(#t 1 #t #t))))))))))
