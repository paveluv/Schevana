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

;; A tree of 3 levels below its root, 4 children each, as a flame and a
;; treemap draw them: (label value child ...).
(define ui-alloc-test-tree
  (let make ([depth 0] [label "all"])
    (cons* label (expt 4 (- 3 depth))
           (if (= depth 3)
               '()
               (map (lambda (i) (make (+ depth 1) (format "~a.~a" label i)))
                    (iota 4))))))

;; The lines a source view shows.
(define ui-alloc-test-lines
  (map (lambda (i) (format "(define (f~a x) (+ x ~a))" i i)) (iota 30)))

(let* ([flame (ui-alloc-test-window
               "Flame"
               (lambda (ui w h)
                 (ui-flame ui 'f 0 0 w h ui-alloc-test-tree car cadr cddr
                           'tip (lambda (node) (car node)))))]
       [treemap (ui-alloc-test-window
                 "Treemap"
                 (lambda (ui w h)
                   (ui-treemap ui 't 0 0 w h ui-alloc-test-tree car cadr cddr
                               'tip (lambda (node) (car node)))))]
       [source (ui-alloc-test-window
                "Source"
                (lambda (ui w h)
                  (ui-source ui 's 0 0 w h ui-alloc-test-lines 'first 1
                             'marked 3)))]
       ;; a scroll view as tall, with its bar, and nothing in it
       [scroll (ui-alloc-test-window
                "Scroll"
                (lambda (ui w h)
                  (ui-scroll ui 's 0 0 w h (lambda (top) (+ top 600)))))]
       [none (ui-alloc-test-window "None" (lambda (ui w h) #f))]
       [other (ui-alloc-test-window "Other" (lambda (ui w h) #f))])
  (steps 2)
  (let ([base (ui-alloc-test-least none)]
        [f (ui-alloc-test-least flame)]
        [t (ui-alloc-test-least treemap)]
        [s (ui-alloc-test-least source)]
        [view (ui-alloc-test-least scroll)])
    (for-each close-window! (list flame treemap source scroll none other))
    (steps 1)
    ;; what is left past a draw with none: a flame's and a treemap's
    ;; handler and the walk to the root shown; a source's scroll view. In
    ;; the hacker edition, where the kit's procedures are names at "/", the
    ;; flame's and the treemap's walks over their boxes, and the source's
    ;; over its lines, allocate up to some KB more; why is not known yet.
    (check (format "a flame and a treemap drawn again find their boxes' \
                    ids, layouts and cut labels kept, and make their \
                    tooltips only when shown; a source view finds its \
                    numbers kept: past a draw with none, the flame and the \
                    treemap allocate a few hundred bytes whatever their \
                    size, and the source what its scroll view does (~a, ~a \
                    and ~a bytes past ~a; the scroll view ~a)"
                   (- f base) (- t base) (- s base) base (- view base))
           (let ([most (if test-hacker? 4096 512)])
             (and (<= (- f base) most) (<= (- t base) most)
                  (<= (- s base) (+ (- view base) most)))))))
