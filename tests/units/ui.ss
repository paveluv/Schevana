;;; tests/units/ui.ss — the widget kit: flow, forms, suggestions, tables' keys,
;;; dates, trees, side panels; when a window is drawn again by itself.

;; A side panel and its button, where it says, laid out in w × h: (values
;; rest panel) as called, each its rectangle or #f. opts: ui-side-panel's.
(define (side-panel-layout ui side w h . opts)
  (let* ([rest #f] [panel #f]
         [drawn (image (exact w) (exact h) 1
                       (lambda ()
                         (ui-begin! ui)
                         (apply ui-side-panel ui 'p 0 0 w (- h 20) side 100 80
                                (lambda r (set! rest r))
                                (lambda r (set! panel r))
                                opts)
                         (ui-side-panel-button ui 'p 7 (- h 20) 24 20 side)
                         (ui-end! ui w h)))])
    (picture-free! drawn)
    (values rest panel)))

(let ([win (open-window "Sides" 'size '(400 . 300))])
  (parameterize ([current-window win])
    (let ([ui (make-ui)])
      (define (button) (ui-find ui '(p button)))
      (define (press-button!)
        (let ([r (button)])
          (ui-mouse-down ui (+ (ui-region-x r) 2) (+ (ui-region-y r) 2))
          (ui-mouse-up ui)))
      (let-values ([(rest panel) (side-panel-layout ui 'right 400 300)])
        (check "a side panel opens at its side, the rest beside it, and its \
                button is where the app laid it, over neither"
               (and (equal? rest '(0 0 300 280))
                    (equal? panel '(300 0 100 280))
                    (= (ui-region-x (button)) 7) (= (ui-region-y (button)) 280)
                    (ui-side-panel-open? ui 'p))))
      (press-button!)
      (let-values ([(rest panel) (side-panel-layout ui 'right 400 300)])
        (check "a press on the button hides it and the rest has all the room; \
                the button stays put"
               (and (equal? rest '(0 0 400 280)) (not panel)
                    (= (ui-region-x (button)) 7)
                    (not (ui-side-panel-open? ui 'p)))))
      (press-button!)
      (let-values ([(rest panel) (side-panel-layout ui 'left 400 300)])
        (check "a second press shows it again; on the left it all mirrors"
               (and (equal? rest '(100 0 300 280))
                    (equal? panel '(0 0 100 280)))))
      (ui-side-panel-toggle! ui 'p)
      (let-values ([(rest panel) (side-panel-layout ui 'left 400 300)])
        (check "toggling by a key is what the button does; Tab reaches the \
                button and Space presses it"
               (and (equal? rest '(0 0 400 280)) (not panel)
                    (begin (ui-focus! ui '(p button))
                           (ui-key ui #\space '() (lambda args #f))
                           (ui-side-panel-open? ui 'p)))))
      (let-values ([(rest panel) (side-panel-layout ui 'right 150 300)])
        (check "with too little room for both the rest has it all, and the \
                button is off: a press leaves the panel as it was"
               (and (equal? rest '(0 0 150 280)) (not panel)
                    (begin (press-button!) (ui-side-panel-open? ui 'p)))))
      (let-values ([(shown shown-panel)
                    (side-panel-layout ui 'right 400 300 'floating #t)])
        (press-button!)
        (let-values ([(hidden hidden-panel)
                      (side-panel-layout ui 'right 400 300 'floating #t)])
          (press-button!)
          (check "over the rest, a side panel leaves it all its room, shown \
                  or hidden"
                 (and (equal? shown '(0 0 400 280))
                      (equal? shown-panel '(300 0 100 280))
                      (equal? hidden shown) (not hidden-panel)))))
      ;; what's under it, red, and a press on it
      (let* ([pressed 0]
             [pixel (lambda opts
                      (let* ([a (image 400 300 1
                                  (lambda ()
                                    (ui-begin! ui)
                                    (apply ui-side-panel ui 'p 0 0 400 280
                                           'right 100 80
                                           (lambda (x y w h)
                                             (fill-box x y w h #xff0000)
                                             (ui-area ui 'under x y w h
                                                      (lambda ()
                                                        (set! pressed
                                                          (+ pressed 1)))))
                                           (lambda r #f)
                                           opts)
                                    (ui-end! ui 400 300)))]
                             [p (pixel-at a 350 100)])
                        (picture-free! a)
                        p))]
             [beside (pixel)]
             [over (pixel 'floating #t)]
             [press! (lambda (x)
                       (ui-mouse-down ui x 100)
                       (ui-mouse-up ui))])
        (press! 350)
        (let ([on-panel pressed])
          (press! 50)
          (check "over the rest, a side panel shows it through and keeps \
                  presses from it"
                 (and (= beside (color->pixel 'bg-1))
                      (not (= over beside))
                      (not (= over (color->pixel #xff0000)))
                      (= on-panel 0) (= pressed 1)))))))
  (close-window! win))

(check "ui-flow places, wraps and centers"
       (and (equal? (call-with-values
                      (lambda () (ui-flow 0 0 100 5 '((10 . 10) (20 . 20)
                                                       (30 . 10))))
                      list)
                    '(((0 . 5) (15 . 0) (40 . 5)) 20))
            (equal? (call-with-values
                      (lambda () (ui-flow 0 0 40 5 '((10 . 10) (20 . 20)
                                                      (30 . 10))))
                      list)
                    '(((0 . 5) (15 . 0) (0 . 25)) 35))))

(check "ui-form puts a label beside its control, or over it where the \
        control would be narrower than its least; a hint goes under the \
        control, and a row without a label spans the form"
       (let* ([gap (ui-gap)] [lh (font-line-height 'ui)]
              [lw (+ (text-widest '("Name" "Kind") 'ui) gap gap)]
              [none (lambda (x y w) #f)]
              [rows (list (list "Name" 20 none)
                          (list "Kind" 30 none 'hint "Why")
                          (list #f (lambda (w) (quotient w 10)) none))]
              [walk (lambda (w)
                      (let* ([placed '()]
                             [bottom (ui-form-walk
                                      rows 0 0 w
                                      (lambda (row inline? lx ly lw lh cx cy
                                               cw ch hint hh)
                                        (set! placed
                                          (cons (list inline? cx cy cw ch)
                                                placed)))
                                      (lambda a #f))])
                        (cons bottom (reverse placed))))]
              [hh (let-values ([(w h) (ui-label-size '(hint wrap) "Why"
                                                     (- 400 lw))])
                    h)]
              [wide (walk 400)]
              [y2 (+ (max 20 lh) gap)]
              [y3 (+ (max (+ y2 30 4 hh) (+ y2 lh)) gap)]
              [narrow (walk (+ lw 100))])
         (and (equal? (cdr wide)
                      (list (list #t lw 0 (- 400 lw) 20)
                            (list #t lw y2 (- 400 lw) 30)
                            (list #f 0 y3 400 40)))
              (= (car wide) (+ y3 40) (ui-form-height rows 400))
              (equal? (cadr narrow) (list #f 0 (+ lh 4) (+ lw 100) 20)))))

(check "ui-suggestions ranks by segments, an exact name first, at most n; \
        none for nothing typed, nor the one that is what was typed"
       (and (equal? (ui-suggestions "abc" '("abcd" "abc" "xyz") 5)
                    '("abc" "abcd"))
            (member "draw-text-centered"
                    (ui-suggestions "dtc" '("draw-text-centered" "x") 5))
            (= (length (ui-suggestions "d" '("da" "db" "dc") 2)) 2)
            (null? (ui-suggestions "" '("a") 5))
            (null? (ui-suggestions "abc" '("abc") 5))))

(check "ui-table-fit gives the flexible column the rest, dropping \
        columns in order while it would be narrower than the least, the \
        others' flags kept"
       (let ([cols '((a "A" 50) (name "Name" #f) (b "B" 40 right)
                     (c "C" 30))])
         (and (equal? (ui-table-fit 300 cols '(c b a) 100)
                      '((a "A" 50) (name "Name" 180) (b "B" 40 right)
                        (c "C" 30)))
              (equal? (ui-table-fit 200 cols '(c b a) 100)
                      '((a "A" 50) (name "Name" 110) (b "B" 40 right)))
              (equal? (ui-table-fit 120 cols '(c b a) 100)
                      '((name "Name" 120))))))

(check "ui-table-step at both ends, by pages, from no row, with no rows"
       (equal? (map (lambda (a) (apply ui-table-step a))
                    '((0 5 2 up) (4 5 2 down) (#f 5 2 down) (#f 5 2 up)
                      (1 5 2 page-down) (4 5 2 page-down) (3 5 2 page-up)
                      (2 5 2 home) (2 5 2 end) (#f 0 2 down) (2 5 2 left)))
               '(0 4 0 4 3 4 1 0 4 #f #f)))

(check "dates: day numbers round-trip from 1970 to 2100; 2026-10-31 is a \
        Saturday; February's lengths; months added clamp the day"
       (and (let loop ([n 0])
              (or (> n (ui-date->day '(2100 12 31)))
                  (and (= n (ui-date->day (ui-day->date n))) (loop (+ n 1)))))
            (equal? (ui-day->date 0) '(1970 1 1))
            (= 5 (ui-week-day (ui-date->day '(2026 10 31))))
            (equal? (map (lambda (y) (ui-days-in-month y 2))
                         '(2024 2025 2100 2000))
                    '(29 28 28 29))
            (equal? (map (lambda (d k)
                           (ui-day->date (ui-add-months (ui-date->day d) k)))
                         '((2026 1 31) (2026 12 15) (2026 1 31)) '(1 1 -2))
                    '((2026 2 28) (2027 1 15) (2025 11 30)))))

(define tree-kids '((a b c) (b d) (c) (d)))
(define (tree-rows expanded?)
  (map (lambda (r) (list (ui-tree-row-node r) (ui-tree-row-depth r)
                         (ui-tree-row-parent r) (ui-tree-row-kids? r)
                         (ui-tree-row-expanded? r)))
       (vector->list (ui-tree-rows '(a) (lambda (n) (cdr (assq n tree-kids)))
                                   expanded?))))

(check "a tree's rows: the expanded nodes' children, depth first, and only \
        theirs asked for; a key's step: Up, Down, End and Page Down as a \
        table's, Right expands or goes to the first child, Left collapses or \
        goes to the parent, Space toggles, Return opens"
       (let* ([asked '()]
              [rows (ui-tree-rows '(a)
                                  (lambda (n)
                                    (set! asked (cons n asked))
                                    (cdr (assq n tree-kids)))
                                  (lambda (n) (not (eq? n 'b))))]
              [all (ui-tree-rows '(a) (lambda (n) (cdr (assq n tree-kids)))
                                 (lambda (n) #t))]
              [step (lambda (i key) (ui-tree-step all i 2 key))])
         (and (equal? (tree-rows (lambda (n) #t))
                      '((a 0 #f #t #t) (b 1 0 #t #t) (d 2 1 #f #f)
                        (c 1 0 #f #f)))
              (equal? (tree-rows (lambda (n) #f)) '((a 0 #f #t #f)))
              (= 3 (vector-length rows)) (not (memq 'd asked))
              (equal? (map (lambda (a) (apply step a))
                           '((0 down) (0 up) (#f down) (1 end) (0 page-down)
                             (0 right) (1 right) (2 right) (0 left) (2 left)
                             (3 left) (1 #\space) (2 #\space) (2 return)
                             (#f right) (#f left)))
                      '((select . 1) (select . 0) (select . 0) (select . 3)
                        (select . 2) (select . 1) (select . 2) #f
                        (collapse . 0) (select . 1) (select . 0)
                        (collapse . 1) #f (open . 2) #f #f))
              (equal? (ui-tree-step rows 1 2 'right) '(expand . 1))
              (equal? (ui-tree-step rows 1 2 #\space) '(expand . 1))
              (= 1 (ui-tree-index rows 'b)) (not (ui-tree-index rows 'd)))))

(check "a row under another at any depth, and not under its siblings"
       (let ([all (ui-tree-rows '(a) (lambda (n) (cdr (assq n tree-kids)))
                                (lambda (n) #t))])   ; a b d c
         (and (ui-tree-under? all 2 0) (ui-tree-under? all 2 1)
              (ui-tree-under? all 3 0) (not (ui-tree-under? all 3 1))
              (not (ui-tree-under? all 1 2)) (not (ui-tree-under? all 0 0))
              (not (ui-tree-under? all #f 0)))))

(check "a dimmed tree row shades its indentation and twisty as the cells \
        shade themselves, and nothing of its cell; selected, it is not \
        dimmed"
       (let* ([cx (cadr (assq 'cell (ui-tree-areas 0 0 200 30 1)))]
              [row (lambda (flags)
                     (image 300 30 1
                            (lambda ()
                              (fill-box 0 0 300 30 'bg-1)
                              (ui-draw-tree-row 0 0 300 30 flags 200 1))))]
              [cell (lambda (flags)
                      (image 300 30 1
                             (lambda ()
                               (fill-box 0 0 300 30 'bg-1)
                               (ui-draw-dim 0 0 cx 30 flags))))]
              [plain (row '(kids expanded))] [dim (row '(kids expanded dim))]
              [picked (row '(kids expanded selected))]
              [dim-picked (row '(kids expanded dim selected))]
              [shade (cell '(dim))])
         (and (> (max-diff plain dim (list cx 0 300 30)) 0)
              (= 0 (max-diff plain dim (list 0 0 cx 30)))
              (= 0 (max-diff picked dim-picked))
              (= (pixel-at dim 2 2) (pixel-at shade 2 2))
              (not (= (pixel-at dim 2 2) (pixel-at plain 2 2))))))

(check "a deep row's indentation stops at half its column, so its cell \
        keeps room"
       (let* ([at (lambda (depth k)
                    (cdr (assq k (ui-tree-areas 0 0 200 20 depth))))]
              [twisty (at 1 'twisty)] [cell (at 1 'cell)] [deep (at 500 'cell)])
         (and (< (car twisty) (car cell))
              (= (+ (car cell) (caddr cell)) 200)
              (>= (caddr deep) 80)
              (equal? deep (at 1000 'cell)))))

;;; The stepper: a field of digits between two arrows.

(let ([win (open-window "Stepper" 'size '(300 . 100))])
  (parameterize ([current-window win])
    (let* ([ui (make-ui)] [value 5] [changes 0]
           [draw! (lambda ()
                    (picture-free!
                     (image 300 100 1
                            (lambda ()
                              (ui-begin! ui)
                              (ui-stepper ui 's 10 10 value 1 60
                                          (lambda (n)
                                            (set! changes (+ changes 1))
                                            (set! value n)))
                              (ui-end! ui 300 100)))))]
           [press! (lambda (id)
                     (let ([r (ui-find ui id)])
                       (ui-mouse-down ui (+ (ui-region-x r) 2)
                                      (+ (ui-region-y r) 2))
                       (ui-mouse-up ui))
                     (draw!))]
           [type! (lambda (text) (ui-text ui text (lambda args #f)) (draw!))]
           [key! (lambda (key)
                   (ui-key ui key '() (lambda args #f))
                   (draw!))]
           [erase! (lambda ()
                     (key! 'end)
                     (key! 'backspace)
                     (key! 'backspace))])
      (draw!)
      (press! '(s up))
      (check "an arrow each side steps the number"
             (let ([up value])
               (press! '(s down))
               (and (= up 6) (= value 5))))
      (press! '(s field))
      (erase!)
      (check "a field emptied changes nothing yet"
             (= value 5))
      (type! "1")
      (type! "x")
      (type! "2")
      (check "the field takes only digits, and what's in range counts at once"
             (= value 12))
      (type! "7")
      (check "no more digits than the range's largest"
             (= value 12))
      (key! 'up)
      (check "Up and Down step it too"
             (let ([up value])
               (key! 'down)
               (and (= up 13) (= value 12))))
      (erase!)
      (let ([before value])
        (type! "99")
        (check "out of range waits"
               (= value before))
        (key! 'return)
        (check "and Return brings it in range"
               (= value 60)))
      (erase!)
      (let ([before value])
        (type! "0")
        (ui-focus! ui #f)
        (draw!)
        (check "the field losing the keyboard forgets what didn't count"
               (and (not (ui-memo ui '(s typed) #f)) (= value before))))
      (set! value 60)
      (draw!)
      (press! '(s up))
      (check "at its limit an arrow goes no further"
             (= value 60))
      ;; its digits at the right: a click goes by where they're drawn
      (set! value 5)
      (draw!)
      (ui-focus! ui #f)
      (draw!)
      (let ([r (ui-find ui '(s field))])
        (ui-mouse-down ui (- (+ (ui-region-x r) (ui-region-w r)) 3)
                       (+ (ui-region-y r) 2))
        (ui-mouse-up ui)
        (draw!)
        (type! "1")
        (check "a press to the digit's right puts the caret after it"
               (= value 51))
        (erase!)
        (type! "5")
        (ui-focus! ui #f)
        (draw!)
        (ui-mouse-down ui (+ (ui-region-x r) 3) (+ (ui-region-y r) 2))
        (ui-mouse-up ui)
        (draw!)
        (type! "1")
        (check "and one to its left before it"
               (= value 15)))))
  (close-window! win))

;; What's inked in a picture's device rect, by how far it is from its corner's
;; color: (left right top bottom).
(define (ui-test-ink img x0 y0 w h)
  (let* ([channel (lambda (p shift) (logand (ash p shift) 255))]
         [bg (pixel-at img x0 y0)]
         [inked? (lambda (x y)
                   (let ([p (pixel-at img x y)])
                     (> (apply + (map (lambda (shift)
                                        (abs (- (channel p shift)
                                                (channel bg shift))))
                                      '(0 -8 -16)))
                        90)))]
         [xs (filter (lambda (x)
                       (exists (lambda (y) (inked? x y))
                               (map (lambda (i) (+ y0 i)) (iota h))))
                     (map (lambda (i) (+ x0 i)) (iota w)))]
         [ys (filter (lambda (y)
                       (exists (lambda (x) (inked? x y))
                               (map (lambda (i) (+ x0 i)) (iota w))))
                     (map (lambda (i) (+ y0 i)) (iota h)))])
    (list (apply min xs) (apply max xs) (apply min ys) (apply max ys))))

;; A stepper at 5 with a label's 5 beside it, the two read from a picture at
;; scale s: (the digit's ink, the label's, where the field's text starts and
;; how wide it may be, the ink of a 5 drawn to end at the text's right edge,
;; device pixels).
(define (ui-test-stepper-ink style s)
  (with-style style
    (lambda ()
      (let* ([win (open-window "Ink" 'size '(300 . 100))]
             [result
              (parameterize ([current-window win])
                (let* ([ui (make-ui)] [ch (ui-control-height)]
                       [device (lambda (n) (exact (round (* s n))))]
                       [img (image (device 300) (device 60) s
                                   (lambda ()
                                     (fill-box 0 0 300 60 'bg-1)
                                     (ui-begin! ui)
                                     (let ([w (ui-stepper ui 's 10 10 5 1 60
                                                          (lambda (n) n))])
                                       (ui-draw-label (+ 10 w 10) 10 30 ch '()
                                                      "5"))
                                     (ui-end! ui 300 60)))]
                       [r (ui-find ui '(s field))]
                       ;; where its text goes: a style's marks are outside it
                       [a (car (with-place 'field
                                 (lambda ()
                                   (ui-text-box-areas (ui-region-x r)
                                                      (ui-region-y r)
                                                      (ui-region-w r)
                                                      (ui-region-h r)
                                                      '(field)))))]
                       [tx (device (list-ref a 1))]
                       [ty (device (list-ref a 2))]
                       [tw (device (list-ref a 3))]
                       [th (device (list-ref a 4))]
                       [digit (ui-test-ink img tx ty tw th)]
                       [up (ui-find ui '(s up))]
                       [label (ui-test-ink
                               img
                               (device (+ (ui-region-x up) (ui-region-w up) 4))
                               ty (device 40) th)]
                       [ref (image (device 300) (device 60) s
                                   (lambda ()
                                     (fill-box 0 0 300 60 'bg-1)
                                     (draw-text (- (+ (list-ref a 1)
                                                      (list-ref a 3))
                                                   (text-width "5" 'ui))
                                                (list-ref a 2) "5" 'text 'ui)))]
                       [at-right (ui-test-ink ref tx ty tw th)])
                  (picture-free! img)
                  (picture-free! ref)
                  (list digit label tx tw at-right)))])
        (close-window! win)
        result))))

(check "a stepper's digits stand on the line a label beside them does, at any \
        scale, in every kind of style"
       (for-all
        (lambda (style)
          (for-all
           (lambda (s)
             (let* ([ink (ui-test-stepper-ink style s)]
                    [digit (car ink)] [label (cadr ink)])
               (equal? (cddr digit) (cddr label))))
           '(1 7/4 2)))
        '(mac genera cons)))

(check "a stepper's field holds its widest number and no more, in every kind \
        of style: that one has as much room either side, and none is cut"
       (for-all
        (lambda (style)
          (with-style style
            (lambda ()
              (= (cadddr (ui-test-stepper-ink style 2))
                 (exact (round (* 2 (text-widest '("1" "60") 'ui))))))))
        '(mac genera cons)))

(check "an area's rows start at the top, however tall it is, a field's one \
        in the middle"
       (with-place 'field
         (lambda ()
           (let ([top (lambda (flags)
                        (list-ref (car (ui-text-box-areas 0 0 200 100 flags))
                                  2))]
                 [lh (font-line-height 'ui)])
             (and (< (top '(lines)) 10)
                  (< (top '(single)) 10)
                  (= (top '(field)) (/ (- 100 lh) 2)))))))

;; The digit's ink against a 5's that ends at the right edge, not against a
;; gap, which is the font's: Verdana's 5 keeps more room at its right than
;; DejaVu's.
(check "and they're at the field's right, as a table's numbers are"
       (for-all
        (lambda (style)
          (let* ([ink (ui-test-stepper-ink style 2)]
                 [digit (car ink)] [at-right (list-ref ink 4)])
            (printf "  ~a: ~s, a 5 at the right ~s\n" style digit at-right)
            (and (<= (abs (- (car digit) (car at-right))) 1)
                 (<= (abs (- (cadr digit) (cadr at-right))) 1))))
        '(mac genera cons)))

;; What a window looks like by itself later comes by a timer, set once for
;; the soonest; rows a scroll bar waits on come by frames it asks for.
(let* ([t 1000]
       [ui (make-ui)]
       [win (apply open-window "Later" 'size '(200 . 100) (ui-handlers ui))]
       [scan #f])
  (define (asked) (window-ref win 'wm-asked 0))
  (define (draw! due)
    (parameterize ([current-window win])
      (ui-begin! ui)
      (when due (ui-due! ui due))
      ;; as the kit's text views do while their bar shows an estimate
      (when (and scan (not (edit-layout-done? scan)))
        (ui-state-scans-set! ui (list scan)))
      (ui-end! ui 200 100)))
  (fluid-let ([now-ms (lambda () t)])
    (let ([timers (length *timers*)] [before (asked)])
      (draw! 1500)
      (draw! 1500)
      (check "a draw due again later sets one timer for it, not one a draw"
             (= (length *timers*) (+ timers 1)))
      (set! t 1499)
      (run-timers!)
      (check "the window isn't drawn again before it's due"
             (= (asked) before))
      (set! t 1500)
      (run-timers!)
      (check "and is when it is, by the timer, with no tick"
             (and (> (asked) before)
                  (not (hashtable-contains? (window-handlers win) 'tick))
                  (= (length *timers*) timers)))))
  (set! scan (edit-layout-of #f (apply string-append
                                       (make-list 2000 "words of a row "))
                             280 #f (lambda (s) (* 7 (string-length s))) #f))
  (draw! #f)
  (check "a draw whose bar waits on rows asks for a frame"
         (window-ref win 'wm-frame-soon #f))
  (let loop ([frames 0])
    (if (and (window-ref win 'wm-frame-soon #f) (< frames 10000))
        (begin (steps 1) (draw! #f) (loop (+ frames 1)))
        (check "its frames compute the rows to the end, then stop asking"
               (and (edit-layout-done? scan) (>= frames 1)
                    (not (window-ref win 'wm-frame-soon #f))))))
  (close-window! win))
