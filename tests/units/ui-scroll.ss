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
        (Genera's, between its end boxes), a press on the thumb leaves the \
        view where it is, and a drag moves it as far as the track says"
       (begin
         (set-style! 'genera)
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
