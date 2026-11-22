;;; tests/units/ui-tooltip.ss — the kit's tooltip ((schevana kits ui)),
;;; tested by itself: when one shows, and what uses it up until the pointer
;;; moves. The test's clock is held, so a wait lasts ui-tip-ms on any
;;; machine.

(define ui-tooltip-test-rows 30)

;; A window with a button, a text field and a scroll of rows, each with a
;; tooltip.
(define (ui-tooltip-test-window)
  (test-kit-window "Tooltips"
    (lambda (ui w h)
      (ui-button ui 'b 20 20 120 30 "Rest" void 'tip "A button's tooltip")
      (ui-text-field ui 'f 20 70 200 30 "" void 'tip "A field's tooltip")
      (ui-scroll ui 'rows 20 120 300 140
        (lambda (top)
          (do ([i 0 (+ i 1)]) ((= i ui-tooltip-test-rows))
            (ui-region! ui (list 'row i) 30 (+ top (* i 20)) 260 18
                        'tip (format "Row ~a" i))
            (fill-box 30 (+ top (* i 20)) 260 18 'accent))
          (+ top (* ui-tooltip-test-rows 20)))))
    '(400 . 300)))

;; Returns how many tooltips are drawn in the next ms milliseconds of the
;; held clock.
(define (ui-tooltip-test-drawn ms)
  (let ([n 0] [plain ui-draw-tooltip])
    (fluid-let ([ui-draw-tooltip
                 (lambda args (set! n (+ n 1)) (apply plain args))])
      (steps (quotient ms 5) 5))
    n))

(test-clock-hold!)

(check "a region's tooltip shows once the pointer has rested on it \
        ui-tip-ms, and not before"
       (let ([win (ui-tooltip-test-window)])
         (steps 2)
         (test-move! win 'b)
         (let* ([early (ui-tooltip-test-drawn (- ui-tip-ms 50))]
                [late (ui-tooltip-test-drawn 100)])
           (close-window! win)
           (printf "  ~a drawn early, ~a after\n" early late)
           (and (= early 0) (> late 0)))))

(check "a text field's tooltip shows, but not while the field has the \
        keyboard, where typing pauses"
       (let ([win (ui-tooltip-test-window)])
         (steps 2)
         (test-move! win 'f)
         (let ([idle (ui-tooltip-test-drawn (* 2 ui-tip-ms))])
           (test-click! win 'f)
           (test-move! win 'b)
           (test-move! win 'f 2)
           (let ([focused (ui-tooltip-test-drawn (* 2 ui-tip-ms))]
                 [has (equal? (ui-focused (window-ref win 'ui)) 'f)])
             (close-window! win)
             (and (> idle 0) has (= focused 0))))))

(check "a press, a key and typing each use the tooltip up: resting after \
        them shows none until the pointer moves and rests again"
       (let ([win (ui-tooltip-test-window)])
         (define (used-then-moved use!)
           (test-move! win 'b)
           (use!)
           (steps 1)
           (let ([after (ui-tooltip-test-drawn (* 2 ui-tip-ms))])
             (test-move! win 'b 2)
             (let ([moved (ui-tooltip-test-drawn (* 2 ui-tip-ms))])
               (test-move! win 'f)   ; move off, for the next use
               (list after moved))))
         (steps 2)
         (let ([pressed (used-then-moved
                         (lambda () (test-click! win 'b)))]
               [keyed (used-then-moved
                       (lambda () (inject! '(key-down down ()))))]
               [typed (used-then-moved
                       (lambda () (inject! '(text "x"))))])
           (close-window! win)
           (printf "  ~s\n" (list pressed keyed typed))
           (for-all (lambda (r) (and (= (car r) 0) (> (cadr r) 0)))
                    (list pressed keyed typed)))))

(check "rows the wheel moves under a still pointer show no tooltip: the \
        wheel used it up"
       (let ([win (ui-tooltip-test-window)])
         (steps 2)
         (test-move! win '(row 3))
         (let ([rested (ui-tooltip-test-drawn (* 2 ui-tip-ms))])
           (let-values ([(x y) (test-point win '(row 3))])
             (inject! `(wheel 0 -1)))
           (steps 1)
           (let ([scrolled (ui-tooltip-test-drawn (* 2 ui-tip-ms))]
                 [moved (car (ui-memo (window-ref win 'ui) 'rows '(0)))])
             (close-window! win)
             (printf "  ~a, then ~a; scrolled to ~a\n" rested scrolled moved)
             (and (> rested 0) (= scrolled 0))))))

(test-clock-release!)
