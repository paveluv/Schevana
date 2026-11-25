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
