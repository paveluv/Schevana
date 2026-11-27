;;; tests/units/ui-scroll.ss — the kit's scroll view and scroll bar
;;; ((schevana kits ui)), tested by themselves, and a text area's own
;;; scrolling: the wheel, the bar pressed and dragged, Page Down, Ctrl+End
;;; and Ctrl+Home. Which side the bar is on, and when it shows, are tested
;;; in behaviors.ss.

(define ui-scroll-test-text
  (apply string-append (map (lambda (i) (format "line ~a\n" i)) (iota 59))))

;; A window with a view 200 high over 1,000 of content, and a text area of
;; 60 lines that is 8 lines high in the current font.
(define (ui-scroll-test-window)
  (test-kit-window "Scroll"
    (lambda (ui w h)
      (ui-scroll ui 'v 20 20 300 200
        (lambda (top)
          (do ([i 0 (+ i 1)]) ((= i 50))
            (fill-box 30 (+ top (* i 20)) 260 10 'accent))
          (+ top 1000)))
      (let-values ([(aw ah) (ui-text-area-size ui 'a '() 300 "" 8 8)])
        (ui-text-area ui 'a 20 240 300 ah ui-scroll-test-text void)))
    '(400 . 460)))

(define (ui-scroll-test-off win) (car (ui-memo (window-ref win 'ui) 'v '(0))))

(define (ui-scroll-test-wheel! win dy)
  (test-move! win 'v)
  (inject! `(wheel 0 ,dy))
  (steps 2))

(define (ui-scroll-test-press! key . mods)
  (inject! (list 'key-down key mods))
  (steps 2))

(check "the wheel scrolls the view by a scroll step a notch, down and back, \
        and no further than its ends"
       (let ([win (ui-scroll-test-window)])
         (steps 2)
         (let* ([at (lambda (dy) (ui-scroll-test-wheel! win dy)
                      (ui-scroll-test-off win))]
                [down (at -1)] [back (at 1)] [above (at 1)]
                [bottom (begin (do ([i 0 (+ i 1)]) ((= i 100))
                                 (inject! '(wheel 0 -1)))
                               (steps 2)
                               (ui-scroll-test-off win))])
           (close-window! win)
           (printf "  ~s\n" (list down back above bottom))
           (and (= down (ui-scroll-step)) (= back 0) (= above 0)
                (= bottom 800)))))

(check "a press on the bar below its thumb brings the thumb's middle there, \
        the view as far as it stands for; dragging the thumb to the top \
        scrolls back to the start"
       (let ([win (ui-scroll-test-window)])
         (steps 2)
         (test-move! win 'v)
         (let ([ui (window-ref win 'ui)])
           (let-values ([(x y) (test-point win '(v bar))]
                        [(cx cy cw ch) (content-rect win)])
             (let* ([r (test-region ui '(v bar))]
                    [y1 (- (+ cy (ui-region-y r) (ui-region-h r)) 2)])
               ;; a press near the bar's bottom: as far as the view goes
               (inject! `(mouse-move ,x ,y1) `(mouse-down ,x ,y1 left 1)
                        `(mouse-up ,x ,y1 left))
               (steps 2)
               (let ([pressed (ui-scroll-test-off win)])
                 ;; drag the thumb, now at the bottom, to the top
                 (inject! `(mouse-down ,x ,y1 left 1)
                          `(mouse-move ,x ,(- y1 400))
                          `(mouse-up ,x ,(- y1 400) left))
                 (steps 2)
                 (let ([dragged (ui-scroll-test-off win)])
                   (close-window! win)
                   (printf "  pressed to ~a, dragged to ~a\n" pressed dragged)
                   (and (= pressed 800) (= dragged 0)))))))))

(check "a text area's Page Down scrolls it a page with its caret; Ctrl+End \
        to its last row, Ctrl+Home back to its first"
       (let ([win (ui-scroll-test-window)])
         (steps 2)
         (let* ([ui (window-ref win 'ui)]
                [f (ui-region-frame (test-region ui 'a))]
                [areas (car (apply ui-text-box-areas
                                   (append f '((lines)))))]
                [th (list-ref areas 4)]
                [lh (font-line-height (list-ref areas 5))]
                [page (max 1 (exact (floor (/ th lh))))]
                [off (lambda () (ui-memo ui 'a 0))])
           (test-click! win 'a)
           (ui-scroll-test-press! 'home 'ctrl)
           (ui-scroll-test-press! 'page-down)
           (let ([paged (off)])
             (ui-scroll-test-press! 'end 'ctrl)
             (let ([ended (off)])
               (ui-scroll-test-press! 'home 'ctrl)
               (let ([homed (off)])
                 (close-window! win)
                 (printf "  ~s, a page ~a of ~a\n" (list paged ended homed)
                         (* page lh) th)
                 (and (<= (abs (- paged (* page lh))) 1)
                      (<= (abs (- ended (- (* 60 lh) th))) 1)
                      (= homed 0))))))))

(check "where the style's thumb travels along a track shorter than the bar \
        (Genera's, between its end boxes, its thumb dragged as Settings \
        offers), a press on the thumb leaves the view where it is, and a \
        drag moves it as far as the track says"
       (begin
         (set-style! 'genera)
         (set-theme! 'scrollbar-input 'drag)
         (let ([win (ui-scroll-test-window)])
           (steps 2)
           (ui-scroll-test-wheel! win -2)
           (let*-values ([(ui) (window-ref win 'ui)]
                         [(before) (ui-scroll-test-off win)]
                         [(cx cy cw ch) (content-rect win)]
                         [(f) (ui-region-frame (test-region ui '(v bar)))]
                         [(areas) (ui-scrollbar-areas (car f) (cadr f)
                                                      (caddr f) (cadddr f)
                                                      (/ before 1000) 1/5)]
                         [(thumb) (cdr (assq 'thumb areas))]
                         [(track) (cdr (assq 'track areas))]
                         [(x) (exact (round (+ cx (car f) (/ (caddr f) 2))))]
                         [(y) (exact (round (+ cy (cadr thumb)
                                               (/ (cadddr thumb) 2))))])
             (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                      `(mouse-up ,x ,y left))
             (steps 2)
             (let ([pressed (ui-scroll-test-off win)])
               (inject! `(mouse-down ,x ,y left 1) `(mouse-move ,x ,(+ y 20))
                        `(mouse-up ,x ,(+ y 20) left))
               (steps 2)
               (let ([dragged (ui-scroll-test-off win)]
                     [want (+ before (* 20 (/ 800 (- (cadddr track)
                                                     (cadddr thumb)))))])
                 (close-window! win)
                 (reset-style! 'scrollbar-input)
                 (set-style! 'mac)
                 (printf "  ~s\n" (list before pressed dragged want))
                 (and (> before 0) (= pressed before)
                      (<= (abs (- dragged want)) 1))))))))

;; A window with a wide view, 300 by 200 over content 800 by 1,000.
(define (ui-scroll-test-wide-window)
  (test-kit-window "Wide"
    (lambda (ui w h)
      (ui-scroll-wide ui 'v 20 20 300 200
        (lambda (left top)
          (do ([i 0 (+ i 1)]) ((= i 50))
            (fill-box (+ left 10) (+ top (* i 20)) 780 10 'accent))
          (values (+ left 800) (+ top 1000)))))
    '(400 . 300)))

(define (ui-scroll-test-offx win)
  (car (ui-memo (window-ref win 'ui) '(v across) '(0))))

(check "a wide view scrolls sideways by the wheel turned sideways, a step a \
        notch and no further than its ends, and down as a view does"
       (let ([win (ui-scroll-test-wide-window)])
         (steps 2)
         (test-move! win 'v)
         (let* ([at (lambda (dx dy) (inject! `(wheel ,dx ,dy)) (steps 2)
                      (list (ui-scroll-test-offx win)
                            (ui-scroll-test-off win)))]
                [right (at 1 0)] [back (at -1 0)] [down (at 0 -1)]
                [far (begin (do ([i 0 (+ i 1)]) ((= i 100))
                              (inject! '(wheel 1 0)))
                            (steps 2)
                            (ui-scroll-test-offx win))])
           (close-window! win)
           (printf "  ~s\n" (list right back down far))
           (and (equal? right (list (ui-scroll-step) 0))
                (equal? back '(0 0))
                (equal? down (list 0 (ui-scroll-step)))
                (= far 500)))))

(check "a wide view's bar across lies along its bottom, the bar at the side \
        stopping short of it; a press near its right end scrolls as far \
        right as the view goes"
       (let ([win (ui-scroll-test-wide-window)])
         (steps 2)
         (test-move! win 'v)
         (steps 1)
         (let*-values ([(ui) (window-ref win 'ui)]
                       [(across) (ui-region-frame
                                  (test-region ui '(v across bar)))]
                       [(side) (ui-region-frame (test-region ui '(v bar)))]
                       [(cx cy cw ch) (content-rect win)]
                       [(x) (exact (round (+ cx (car across) (caddr across)
                                             -2)))]
                       [(y) (exact (round (+ cy (cadr across)
                                             (/ (cadddr across) 2))))])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                    `(mouse-up ,x ,y left))
           (steps 2)
           (let ([far (ui-scroll-test-offx win)] [bw (ui-scrollbar-width)])
             (close-window! win)
             (printf "  ~s ~s ~a\n" across side far)
             (and (= (cadr across) (- 220 bw)) (= (cadddr across) bw)
                  (= (cadddr side) (- 200 bw))
                  (= (+ (car across) (caddr across)) (car side))
                  (= far 500))))))

(check "the bar across covers none of a wide view's content: scrolled to \
        its end, the last of it stands just above the bar, with the bar at \
        either side or in the margin; and none shows beside the bars where \
        the style's leave white (Genera's), wherever it is scrolled to"
       (let* ([shown #f]   ; what the body may draw on, and the view's bars
              [end (lambda (style)
                     (set-style! style)
                     (let* ([win (test-kit-window "Wide"
                                   (lambda (ui w h)
                                     (ui-scroll-wide ui 'v 20 20 300 200
                                       (lambda (left top)
                                         (set! shown
                                               (list (ui-state-clip-x ui)
                                                     (ui-state-clip-y ui)
                                                     (ui-state-clip-w ui)
                                                     (ui-state-clip-h ui)))
                                         (values (+ left 800) (+ top 1000)))))
                                   '(400 . 300))]
                            [ui (window-ref win 'ui)])
                       (steps 2)
                       (test-move! win 'v)
                       (do ([i 0 (+ i 1)]) ((= i 60)) (inject! '(wheel 0 -1)))
                       (inject! '(wheel 1 0))
                       (steps 2)
                       (let ([off (ui-scroll-test-off win)]
                             [f (lambda (id)
                                  (let ([r (ui-find ui id)])
                                    (and r (ui-region-frame r))))])
                         (let ([r (list (- (+ 20 1000) off) shown
                                        (f '(v across bar)) (f '(v bar)))])
                           (close-window! win)
                           r))))]
              [genera (end 'genera)] [mac (end 'mac)] [mit (end 'cadr)]
              [above? (lambda (r)
                        (let ([clip (cadr r)] [across (caddr r)])
                          (= (car r) (cadr across)
                             (+ (cadr clip) (cadddr clip)))))]
              [left (lambda (r) (car (cadr r)))])
         (set-style! 'mac)
         (for-each (lambda (r) (printf "  ~s\n" r)) (list genera mac mit))
         (and (for-all above? (list genera mac mit))
              (let ([bar (cadddr genera)])
                (= (left genera) (+ (car bar) (caddr bar))))
              (= (left mac) (left mit) 20))))

;; Presses button on the view's bar, d down it, with mods held, clicks
;; times; returns the view's offset after.
(define (ui-scroll-test-click! win d button clicks . mods)
  (let*-values ([(ui) (window-ref win 'ui)]
                [(f) (ui-region-frame (test-region ui '(v bar)))]
                [(cx cy cw ch) (content-rect win)])
    (let ([x (exact (round (+ cx (car f) (/ (caddr f) 2))))]
          [y (exact (round (+ cy (cadr f) d)))])
      (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y ,button ,clicks ,mods)
               `(mouse-up ,x ,y ,button))
      (steps 2)
      (ui-scroll-test-off win))))

(check "the Lisp machines' clicks on the bar (scrollbar-input lispm): the \
        left button brings the line pointed at to the top, the right the \
        top line to the pointer, the middle that part of the content; \
        Shift and the left button the pointed line to the bottom"
       (begin
         (set-theme! 'scrollbar-input 'lispm)
         (let* ([win (ui-scroll-test-window)]
                [lh (theme 'scrollbar-line-height)]
                [line (* lh (floor (/ 90 lh)))]
                [page (* lh (max 1 (floor (/ (- 200 (- lh 1)) lh))))])
           (steps 2)
           (test-move! win 'v)
           (steps 1)
           (let* ([left (ui-scroll-test-click! win 90 'left 1)]
                  [right (ui-scroll-test-click! win 90 'right 1)]
                  [middle (ui-scroll-test-click! win 100 'middle 1)]
                  [shifted (begin (ui-scroll-test-click! win 0 'middle 1)
                                  (ui-scroll-test-click! win 90 'left 1
                                                         'shift))])
             (close-window! win)
             (reset-style! 'scrollbar-input)
             (printf "  ~s\n" (list left right middle shifted))
             (and (= left line) (= right 0)
                  (= middle (* lh (round (/ 500 lh))))
                  (= shifted (max 0 (- line page))))))))

(check "Genera's end boxes: the left button scrolls a line from the top \
        box and a page from the bottom one, the middle goes to the start \
        or the end; the CADR's double click sends the pointed line to the \
        bottom, from where the view was before its first press"
       (begin
         (set-style! 'genera)
         (let* ([win (ui-scroll-test-window)]
                [lh (theme 'scrollbar-line-height)]
                [page (* lh (max 1 (floor (/ (- 200 (- lh 1)) lh))))])
           (steps 2)
           (test-move! win 'v)
           (steps 1)
           (let* ([up (ui-scroll-test-click! win 2 'left 1)]
                  [down (ui-scroll-test-click! win 198 'left 1)]
                  [end (ui-scroll-test-click! win 198 'middle 1)]
                  [start (ui-scroll-test-click! win 2 'middle 1)])
             (close-window! win)
             (set-style! 'cadr)
             (let ([win (ui-scroll-test-window)]
                   [lh (theme 'scrollbar-line-height)])
               (steps 2)
               (test-move! win 'v)
               (steps 1)
               (let* ([line (* lh (floor (/ 150 lh)))]
                      [page (* lh (max 1 (floor (/ (- 200 (- lh 1)) lh))))]
                      [single (ui-scroll-test-click! win 150 'left 1)]
                      [double (ui-scroll-test-click! win 150 'left 2)])
                 (close-window! win)
                 (set-style! 'mac)
                 (printf "  ~s\n" (list up down end start single double))
                 (and (= up lh) (= down (+ lh page)) (= end 800) (= start 0)
                      (= single line)
                      (= double (max 0 (- line page))))))))))

(check "the CADR's bar lies in the margin (scrollbar-show bar): its region \
        is there before the pointer is, so that the first press in the \
        margin scrolls, though the bar shows only under the pointer"
       (begin
         (set-style! 'cadr)
         (let ([win (ui-scroll-test-window)])
           (steps 2)
           (test-move! win 'v)
           (steps 1)
           (let* ([there (and (test-region (window-ref win 'ui) '(v bar)) #t)]
                  [scrolled (ui-scroll-test-click! win 150 'left 1)])
             (close-window! win)
             (set-style! 'mac)
             (printf "  ~s\n" (list there scrolled))
             (and there (> scrolled 0))))))

;; Returns what thunk returns in style, the window it was handed closed
;; after: one with three views 100 high, over no content, some and twice as
;; much as they show, and a wide view whose content fits.
(define (ui-scroll-test-full style proc)
  (set-style! style)
  (let ([win (test-kit-window "Full"
               (lambda (ui w h)
                 (for-each (lambda (id x n)
                             (ui-scroll ui id x 20 80 100
                               (lambda (top) (+ top n))))
                           '(none some twice) '(20 120 220) '(0 40 200))
                 (ui-scroll-wide ui 'wide 20 140 280 80
                   (lambda (left top) (values (+ left 100) (+ top 40)))))
               '(400 . 300))])
    (steps 2)
    (let ([r (proc win (window-ref win 'ui))])
      (close-window! win)
      (set-style! 'mac)
      r)))

(check "a bar is there though all of its content fits in a style whose bars \
        always are (Genera's), its thumb as long as its track, over no \
        content too, across as well; elsewhere only where a view scrolls"
       (let* ([bars (lambda (win ui)
                      (map (lambda (id) (and (ui-find ui id) #t))
                           '((none bar) (some bar) (twice bar) (wide bar)
                             (wide across bar))))]
              [genera (ui-scroll-test-full 'genera bars)]
              [mac (ui-scroll-test-full 'mac bars)]
              [cadr (ui-scroll-test-full 'cadr bars)]
              [full? (ui-scroll-test-full 'genera
                       (lambda (win ui)
                         (let* ([f (ui-region-frame
                                    (test-region ui '(some bar)))]
                                [a (apply ui-scrollbar-areas
                                          (append f '(0 1)))])
                           (equal? (cdr (assq 'thumb a))
                                   (cdr (assq 'track a))))))]
              [pressed (ui-scroll-test-full 'genera
                         (lambda (win ui)
                           (test-click! win '(some bar))
                           (and (not (window-error win))
                                (car (ui-memo ui 'some '(#f))))))])
         (printf "  ~s\n" (list genera mac cadr full? pressed))
         (and (equal? genera '(#t #t #t #t #t))
              (equal? mac '(#f #f #t #f #f))
              (equal? cadr '(#f #f #t #f #f))
              full? (eqv? pressed 0))))

;; Moves the pointer d down the view's bar (or along the one across, id),
;; and returns what the mouse documentation says there, and the pointer's
;; shape.
(define (ui-scroll-test-doc win id d)
  (let*-values ([(f) (ui-region-frame (test-region (window-ref win 'ui) id))]
                [(across?) (memq 'across id)]
                [(cx cy cw ch) (content-rect win)]
                [(x) (+ cx (car f) (if across? d (/ (caddr f) 2)))]
                [(y) (+ cy (cadr f) (if across? (/ (cadddr f) 2) d))])
    (inject! `(mouse-move ,(exact (round x)) ,(exact (round y))))
    (steps 1)
    (cons (window-ref win 'cursor 'arrow) (mouse-doc))))

(check "the mouse line says what a Lisp machine's buttons do where they are \
        on the bar: Genera's in its end boxes and along the shaft, with how \
        far down it is, the CADR's in its source's words; the pointer is a \
        double-headed arrow there, along the bar, and an arrow off it"
       (begin
         (set-style! 'genera)
         (let* ([win (ui-scroll-test-window)]
                [up (begin (steps 2) (ui-scroll-test-doc win '(v bar) 5))]
                [shaft (ui-scroll-test-doc win '(v bar) 100)]
                [lower (ui-scroll-test-doc win '(v bar) 145)]
                [down (ui-scroll-test-doc win '(v bar) 195)]
                [off (begin (test-move! win 'v) (window-ref win 'cursor))])
           (close-window! win)
           (let* ([win (ui-scroll-test-wide-window)]
                  [across (begin (steps 2)
                                 (ui-scroll-test-doc win '(v across bar) 5))])
             (close-window! win)
             (set-style! 'cadr)
             (let* ([win (ui-scroll-test-window)]
                    [mit (begin (steps 2) (ui-scroll-test-doc win '(v bar) 5))])
               (close-window! win)
               (set-style! 'mac)
               (for-each (lambda (d) (printf "  ~s\n" d))
                         (list up shaft lower down across mit off))
               (and (equal? up '(resize-ns (L . "Next line")
                                           (M . "First screen")
                                           (R . "Previous line")))
                    (equal? shaft '(resize-ns
                                    (L . "This line to top")
                                    (sh-L . "This line to bottom")
                                    (M . "Move to 50% of contents")
                                    (R . "Top line to here")))
                    (equal? (assq 'M (cdr lower))
                            '(M . "Move to 76% of contents"))
                    (equal? down '(resize-ns (L . "Next screen")
                                             (M . "Last screen")
                                             (R . "Previous screen")))
                    (equal? across '(resize-ew (L . "Next column")
                                               (M . "Leftmost column")
                                               (R . "Previous column")))
                    (equal? mit '(resize-ns (L . "This line to top")
                                            (L2 . "This line to bottom")
                                            (M . "Percentage-wise")
                                            (R . "Top line to here")))
                    (eq? off 'arrow)))))))

;; Presses button on the view's bar, d down it, and holds it.
(define (ui-scroll-test-hold! win d button)
  (let*-values ([(f) (ui-region-frame
                      (test-region (window-ref win 'ui) '(v bar)))]
                [(cx cy cw ch) (content-rect win)]
                [(x) (exact (round (+ cx (car f) (/ (caddr f) 2))))]
                [(y) (exact (round (+ cy (cadr f) d)))])
    (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y ,button 1))
    (steps 1)
    (lambda () (inject! `(mouse-up ,x ,y ,button)) (steps 2))))

;; Returns win's view's offset in lines after each of ms more, a step each
;; 5 ms.
(define (ui-scroll-test-lines win . ms)
  (let loop ([ms ms] [acc '()])
    (if (null? ms)
        (reverse acc)
        (begin
          (steps (quotient (car ms) 5) 5)
          (loop (cdr ms) (cons (/ (ui-scroll-test-off win)
                                  (theme 'scrollbar-line-height))
                               acc))))))

;; A window with a view vh high over 40,000 of content.
(define (ui-scroll-test-long-window vh)
  (test-kit-window "Long"
    (lambda (ui w h)
      (ui-scroll ui 'v 20 20 200 vh (lambda (top) (+ top 40000))))
    (cons 260 (+ vh 40))))

;; Returns how many lines the bar's top box scrolls in the fifth second that
;; the left button is held there, over a view vh high.
(define (ui-scroll-test-speed vh)
  (let* ([win (ui-scroll-test-long-window vh)]
         [release (begin (steps 2) (ui-scroll-test-hold! win 5 'left))]
         [r (ui-scroll-test-lines win 4000 1000)])
    (release)
    (close-window! win)
    (- (cadr r) (car r))))

(check "a button held over Genera's bar repeats what its press did, first \
        half a second after it and then half a second later, sooner each \
        time, up to 2 screens a second and no more than 50 lines; not once \
        it is released or off the bar, nor in the CADR"
       (begin
         (test-clock-hold!)
         (set-style! 'genera)
         (let* ([win (ui-scroll-test-long-window 200)]
                [release (begin (steps 2)
                                (ui-scroll-test-hold! win 5 'left))]
                [slow (ui-scroll-test-lines win 0 490 20 470 30 400)]
                [at (begin (release) (ui-scroll-test-lines win 0 1000))]
                [back (let ([release (ui-scroll-test-hold! win 5 'right)])
                        (let ([r (ui-scroll-test-lines win 0 520)])
                          (release)
                          r))]
                [moved (begin
                         (ui-scroll-test-hold! win 5 'left)
                         (test-move! win 'v)
                         (let ([r (ui-scroll-test-lines win 0 1500)])
                           (inject! '(mouse-up 0 0 left))
                           (steps 2)
                           r))]
                [pages (begin
                         (let ([release (ui-scroll-test-hold! win 195 'left)])
                           (let ([r (ui-scroll-test-lines win 0 520 500 500)])
                             (release)
                             r)))]
                [lh (theme 'scrollbar-line-height)]
                [page (max 1 (floor (/ (- 200 (- lh 1)) lh)))])
           (close-window! win)
           (let ([small (ui-scroll-test-speed 200)]
                 [large (ui-scroll-test-speed 600)])
             (set-style! 'cadr)
             (let* ([win (ui-scroll-test-window)]
                    [release (begin (steps 2)
                                    (ui-scroll-test-hold! win 50 'left))]
                    [mit (ui-scroll-test-lines win 0 2000)])
               (release)
               (close-window! win)
               (set-style! 'mac)
               (test-clock-release!)
               (for-each (lambda (r) (printf "  ~s\n" r))
                         (list slow at back moved pages page small large mit))
               (and (equal? slow '(1 1 2 2 3 4))
                    (= (car at) (cadr at))
                    (= (- (cadr back) (car back)) -1)
                    (= (car moved) (cadr moved))
                    ;; a page each half second
                    (equal? (map (lambda (n) (- n (car pages))) pages)
                            (list 0 page (* 2 page) (* 3 page)))
                    (let ([screens (* 2 (/ 200 lh))])
                      (and (< screens 50) (<= (* 3/4 screens) small screens)))
                    (<= 35 large 50)
                    (= (car mit) (cadr mit))))))))

(check "a text area's bar in Genera is a shaft alone until the pointer has \
        been to it, and again once its text has changed in size, as ZWEI's \
        was; other bars show their elevator from the first"
       (begin
         (set-style! 'genera)
         (let* ([text (make-string 1 #\a)] [flags #f] [view #f]
                [many (lambda (n)
                        (apply string-append
                               (map (lambda (i) (format "line ~a\n" i))
                                    (iota n))))]
                [shown (many 40)]
                [real ui-draw-scrollbar]
                [win (test-kit-window "Area"
                       (lambda (ui w h)
                         (ui-scroll ui 'v 20 130 200 60
                           (lambda (top) (+ top 400)))
                         (ui-text-area ui 'a 20 20 200 100 shown
                                       (lambda (s) (set! shown s))))
                       '(300 . 220))]
                [draw (lambda ()
                        (fluid-let ([ui-draw-scrollbar
                                     (lambda (x y w h fs start size)
                                       (if (= w 10)
                                           (set! flags fs)
                                           (set! view fs))
                                       (real x y w h fs start size))])
                          (invalidate! win)
                          (steps 2))
                        (and (memq 'unasked flags) #t))]
                [before (draw)]
                [over (begin (test-move! win '(a bar)) (draw))]
                [left (begin (test-move! win 'v) (draw))]
                [grown (begin (set! shown (many 41)) (draw))]
                [again (begin (test-move! win '(a bar)) (draw))]
                [plain (memq 'unasked view)])
           (close-window! win)
           (set-style! 'mac)
           (printf "  ~s\n" (list before over left grown again plain))
           (and before (not over) (not left) grown (not again)
                (not plain)))))

(check "Genera's elevator is drawn but where its flag says the pointer has \
        not asked for it: the shaft's dots run the whole way then"
       (let* ([picture (lambda (flags)
                         (with-style 'genera
                           (lambda ()
                             (pixel-rows
                              (image 18 64 1
                                     (lambda ()
                                       (fill-box 0 0 18 64 'window-bg)
                                       (ui-draw-scrollbar 0 0 18 64 flags 0
                                                          1/4)))
                              (list (cons (color->pixel 'window-bg) #\.))))))]
              [asked (picture '())] [unasked (picture '(unasked))])
         (and (not (equal? asked unasked))
              (for-all (lambda (i)
                         (string=? (list-ref unasked (+ 12 i))
                                   (if (odd? i)
                                       "....#........#...."
                                       (make-string 18 #\.))))
                       (iota 40)))))
