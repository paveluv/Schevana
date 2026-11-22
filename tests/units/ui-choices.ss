;;; tests/units/ui-choices.ss — the kit's slider, segmented choice, checkbox
;;; and toggle ((schevana kits ui)), tested by themselves: what a press, a
;;; drag and Space set, and a slider released over another window.

;; A window with a slider from 0 to 100 at x 20, 200 wide, a segmented
;; choice of three, a checkbox, a disabled checkbox and a toggle. Returns
;; the window and a box for each of their values.
(define (ui-choices-test-window)
  (let ([level (box 50)] [size (box 'm)] [on (box #f)] [off (box #f)]
        [toggled (box #f)])
    (values
     (test-kit-window "Choices"
       (lambda (ui w h)
         (ui-slider ui 's 20 20 200 (unbox level) 0 100
                    (lambda (v) (set-box! level v)))
         (ui-segmented ui 'seg 20 60 240 (ui-control-height)
                       '(("S" . s) ("M" . m) ("L" . l)) (unbox size)
                       (lambda (v) (set-box! size v)))
         (ui-checkbox ui 'c 20 100 200 (ui-control-height) "Checked"
                      (unbox on) (lambda (v) (set-box! on v)))
         (ui-checkbox ui 'd 20 140 200 (ui-control-height) "Disabled"
                      (unbox off) (lambda (v) (set-box! off v))
                      'disabled #t)
         (ui-toggle ui 't 20 180 200 (ui-control-height) "Toggle"
                    (unbox toggled) (lambda (v) (set-box! toggled v))))
       '(400 . 260))
     level size on off toggled)))

;; Returns the screen point at fraction f of the slider's track. The
;; slider's area reaches 8 past either end of the track.
(define (ui-choices-test-slider-at win f)
  (test-point win 's 'at (exact (round (+ 8 (* f 200))))))

(check "a press on a slider sets the value under the pointer, a drag \
        follows it, and past its ends it stays at its least and its most"
       (let-values ([(win level size on off toggled)
                     (ui-choices-test-window)])
         (steps 2)
         (let-values ([(x y) (ui-choices-test-slider-at win 1/4)]
                      [(x1 y1) (ui-choices-test-slider-at win 3/4)])
           (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1))
           (steps 1)
           (let ([pressed (unbox level)])
             (inject! `(mouse-move ,x1 ,y))
             (steps 1)
             (let ([dragged (unbox level)])
               (inject! `(mouse-move ,(+ x1 400) ,y))
               (steps 1)
               (let ([most (unbox level)])
                 (inject! `(mouse-move ,(- x 400) ,y))
                 (steps 1)
                 (let ([least (unbox level)])
                   (inject! `(mouse-up ,(- x 400) ,y left))
                   (steps 1)
                   (close-window! win)
                   (printf "  ~s\n" (list pressed dragged most least))
                   (and (= pressed 25) (= dragged 75) (= most 100)
                        (= least 0)))))))))

(check "a slider let go over another window, after a right click there, \
        follows the pointer no more"
       (let-values ([(win level size on off toggled)
                     (ui-choices-test-window)])
         (let ([other (open-window "Other" 'size '(160 . 100)
                                   'pos '(800 . 500))])
           (steps 2)
           (focus-window! win)
           (steps 1)
           (let-values ([(x y) (ui-choices-test-slider-at win 1/2)]
                        [(x1 y1) (ui-choices-test-slider-at win 1/10)]
                        [(ox oy ow oh) (content-rect other)])
             (let ([ox (+ ox 20)] [oy (+ oy 20)])
               (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                        `(mouse-move ,ox ,oy) `(mouse-down ,ox ,oy right 1)
                        `(mouse-up ,ox ,oy right) `(mouse-up ,ox ,oy left))
               (steps 2)
               (let ([held (unbox level)])
                 (inject! `(mouse-move ,x1 ,y))
                 (steps 2)
                 (close-window! other)
                 (close-window! win)
                 (= held (unbox level))))))))

(check "a press on a segment chooses its value"
       (let-values ([(win level size on off toggled)
                     (ui-choices-test-window)])
         (steps 2)
         (test-click! win '(seg l))
         (let ([l (unbox size)])
           (test-click! win '(seg s))
           (close-window! win)
           (and (eq? l 'l) (eq? (unbox size) 's)))))

(check "a press on a checkbox or a toggle turns it over, and so does Space \
        with the keyboard; a disabled checkbox takes no press"
       (let-values ([(win level size on off toggled)
                     (ui-choices-test-window)])
         (steps 2)
         (test-click! win 'c)
         (let ([pressed (unbox on)])
           ;; a press doesn't give a Tab stop the keyboard (Tab does)
           (ui-focus! (window-ref win 'ui) 'c)
           (invalidate! win)
           (steps 1)
           (inject! '(key-down #\space ()))
           (steps 2)
           (let ([spaced (unbox on)])
             (test-click! win 't)
             (test-click! win 'd)
             (close-window! win)
             (and pressed (not spaced) (unbox toggled) (not (unbox off)))))))
