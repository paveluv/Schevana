;;; tests/units/ui-alloc.ss — what the ui kit allocates as a window draws
;;; ((schevana kits ui)): a draw fills the regions of its ui's pool again
;;; and finds the ids of its widgets' pieces made, so that what a draw
;;; makes is the app's own, not the kit's. Each draw is measured as the
;;; Probe measures it (allocation-probe-draw): the least of several.

(for-each close-window! (windows))
(steps 2)

;; Opens a window whose draw begins its ui, calls (body ui w h) and ends it.
(define (ui-alloc-test-window title body)
  (let ([ui (make-ui)])
    (apply open-window title 'size '(300 . 200)
           'draw (lambda (win w h)
                   (ui-begin! ui)
                   (body ui w h)
                   (ui-end! ui w h))
           (ui-handlers ui))))

(define (ui-alloc-test-least win)
  (cdr (assq 'least (allocation-probe-draw win 10))))

(let* ([none (ui-alloc-test-window "None" (lambda (ui w h) #f))]
       [many (ui-alloc-test-window
              "Many"
              (lambda (ui w h)
                (do ([i 0 (+ i 1)]) ((= i 100))
                  (let ([id (ui-id ui 'piece 'row i)])
                    (ui-region!* ui id 0 i 10 1 #f #f #f #f #f '() #f)
                    (ui-flags* ui id '())))))]
       ;; a third window, opened last, has the focus, so that the two above
       ;; draw alike
       [other (ui-alloc-test-window "Other" (lambda (ui w h) #f))])
  (steps 2)
  (let ([a (ui-alloc-test-least none)] [b (ui-alloc-test-least many)])
    (for-each close-window! (list none many other))
    (steps 1)
    (check (format "a draw's regions are its ui's, filled again, and the ids \
                    of its pieces and their flags are found, not made: 100 \
                    regions allocate nothing past a draw with none (~a \
                    bytes, ~a)" b a)
           (<= b a))))
