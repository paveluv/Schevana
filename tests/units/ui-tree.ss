;;; tests/units/ui-tree.ss — the kit's tree ((schevana kits ui)), by itself:
;;; rows selected by a click or by keys, a twisty, Right, Left and Space
;;; expanding and collapsing, Return and a double click opening, a right press's
;;; menu, a collapse that hides the selection, and a tree with no rows. The
;;; rows' order and steps are ui.ss's (ui-tree-rows, -step).

(define ui-tree-test-kids
  '((a a1 a2) (a1 a11) (c c1)))

;; A tree of a (a1 (a11) a2), b and c (c1), expanded, its selection, what
;; it opened and what its menu was for kept in boxes; nodes, if given,
;; are its roots instead.
(define (ui-tree-test-window . nodes)
  (let ([selected (box #f)] [opened (box #f)] [menu (box #f)]
        [roots (if (pair? nodes) (car nodes) '(a b c))])
    (define (select! n) (set-box! selected n))
    (values
     (test-kit-window "Tree"
       (lambda (ui w h)
         (ui-tree ui 't 20 20 360 (- h 40) '((name "Name" 300)) roots
                  (lambda (n) (cond [(assq n ui-tree-test-kids) => cdr]
                                    [else '()]))
                  (unbox selected) select!
                  (lambda (n key x y w h flags)
                    (draw-text (+ x 4) y (symbol->string n) 'text 'ui))
                  'expanded #t
                  'on-open (lambda (n) (set-box! opened n))
                  'on-menu (lambda (n x y) (set-box! menu n))))
       '(400 . 400)
       'key (lambda (win key mods)
              (ui-tree-key (window-ref win 'ui) 't key mods (unbox selected)
                           select! (lambda (n) (set-box! opened n)))))
     selected opened menu)))

(define (ui-tree-test-rows win)
  (ui-memo (window-ref win 'ui) '(t rows) '#()))

(define (ui-tree-test-nodes win)
  (map ui-tree-row-node (vector->list (ui-tree-test-rows win))))

;; Row node's region id, and the x of its twisty within the row.
(define (ui-tree-test-row win node)
  (list 't 'row (ui-tree-index (ui-tree-test-rows win) node)))

(define (ui-tree-test-twisty-x win node)
  (let* ([rows (ui-tree-test-rows win)] [i (ui-tree-index rows node)]
         [r (test-region (window-ref win 'ui) (list 't 'row i))]
         [t (cdr (assq 'twisty
                       (ui-tree-areas (ui-region-x r) (ui-region-y r)
                                      (ui-region-w r) (ui-region-h r)
                                      (ui-tree-row-depth
                                       (vector-ref rows i)))))])
    (exact (round (- (+ (car t) (/ (caddr t) 2)) (ui-region-x r))))))

(define (ui-tree-test-press! key . mods)
  (inject! (list 'key-down key mods))
  (steps 2))

(check "a click on a row selects its node; a press on its twisty collapses \
        it, and again expands it"
       (let-values ([(win selected opened menu) (ui-tree-test-window)])
         (steps 2)
         (test-click! win (ui-tree-test-row win 'a1))
         (steps 1)
         (let ([clicked (unbox selected)]
               [x (ui-tree-test-twisty-x win 'a)])
           (test-click! win (ui-tree-test-row win 'a) 'at x)
           (steps 1)
           (let ([collapsed (ui-tree-test-nodes win)])
             (test-click! win (ui-tree-test-row win 'a) 'at x)
             (steps 1)
             (let ([expanded (ui-tree-test-nodes win)])
               (close-window! win)
               (printf "  ~s ~s\n" collapsed expanded)
               (and (eq? clicked 'a1)
                    (equal? collapsed '(a b c c1))
                    (equal? expanded '(a a1 a11 a2 b c c1))))))))

(check "keys: Left collapses an expanded row, else goes to its parent; \
        Right expands a collapsed one, else goes to its first child; Space \
        expands; Down and Up go to the next row and back"
       (let-values ([(win selected opened menu) (ui-tree-test-window)])
         (steps 2)
         (test-click! win (ui-tree-test-row win 'a))
         (let* ([at (lambda () (unbox selected))]
                [step (lambda (key)
                        (ui-tree-test-press! key)
                        (list (at) (ui-tree-test-nodes win)))]
                [shut (step 'left)]       ; collapses a
                [open (step 'right)]      ; expands it
                [child (step 'right)]     ; to a1
                [shut1 (step 'left)]      ; collapses a1
                [parent (step 'left)]     ; to a
                [shut2 (step 'left)]      ; collapses a
                [space (step #\space)]    ; expands it
                [down (step 'down)]       ; to a1
                [up (step 'up)])          ; back to a
           (close-window! win)
           (and (equal? shut '(a (a b c c1)))
                (equal? open '(a (a a1 a11 a2 b c c1)))
                (eq? (car child) 'a1)
                (equal? shut1 '(a1 (a a1 a2 b c c1)))
                (eq? (car parent) 'a)
                (equal? shut2 '(a (a b c c1)))
                (equal? space '(a (a a1 a2 b c c1)))
                (eq? (car down) 'a1) (eq? (car up) 'a)))))

(check "Return opens the selected row, and a double click opens its row; a \
        right press asks for its row's menu"
       (let-values ([(win selected opened menu) (ui-tree-test-window)])
         (steps 2)
         (test-click! win (ui-tree-test-row win 'b))
         (ui-tree-test-press! 'return)
         (let ([returned (unbox opened)])
           (set-box! opened #f)
           (test-click! win (ui-tree-test-row win 'c1) 2)
           (let ([doubled (unbox opened)])
             (let-values ([(x y) (test-point win (ui-tree-test-row win 'c))])
               (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y right 1)
                        `(mouse-up ,x ,y right)))
             (steps 1)
             (close-window! win)
             (and (eq? returned 'b) (eq? doubled 'c1)
                  (eq? (unbox menu) 'c))))))

(check "a twisty that hides the selected row selects the row it collapsed"
       (let-values ([(win selected opened menu) (ui-tree-test-window)])
         (steps 2)
         (test-click! win (ui-tree-test-row win 'a11))
         (test-click! win (ui-tree-test-row win 'a) 'at
                      (ui-tree-test-twisty-x win 'a))
         (steps 1)
         (let ([s (unbox selected)])
           (close-window! win)
           (eq? s 'a))))

(check "a tree with no rows takes no keys"
       (let-values ([(win selected opened menu) (ui-tree-test-window '())])
         (steps 2)
         (let ([taken (ui-tree-key (window-ref win 'ui) 't 'down '() #f
                                   (lambda (n) #t) (lambda (n) #t))])
           (close-window! win)
           (not taken))))
