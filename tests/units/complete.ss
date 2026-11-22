;;; tests/units/complete.ss — the completion list ((schevana kits
;;; complete)) by itself, with the test as its owner: Tab's list, prefix and
;;; popups, the list narrowed, keys, the wheel and presses, and the
;;; matching. What the REPL completes, describes and draws is smoke's.

(test-focus (schevana kits complete))

(define complete-test-names
  '("set-theme!" "set-theme-plist!" "set-style!" "setting-of" "sum"
    "head:split-window" "head:window-split" "*scratch*"))

;; Returns the names that typed matches, best first, as items.
(define (complete-test-rank typed)
  (complete-rank typed (map (lambda (n) (cons n "procedure"))
                            complete-test-names)
                 (lambda (n) #f)))

;; Presses Tab on typed for a new owner. Returns (values owner replaced
;; accepted): the owner, and what its Tab put in.
(define (complete-test-tab typed)
  (let ([owner (list 'owner)] [replaced (box #f)] [accepted (box #f)])
    (complete-tab! owner 'names 0 typed (complete-test-rank typed)
                   (lambda (s) (set-box! replaced s))
                   (lambda (item) (set-box! accepted (car item))))
    (values owner (unbox replaced) (unbox accepted))))

(define (complete-test-names-of owner)
  (map car (vector->list (complete-items (complete-of owner)))))

(check "Tab: a list of the matches, the word grown to what those starting \
        with it share; one other match put in; with nothing to add, a \
        popup that says so"
       (let-values ([(owner replaced accepted) (complete-test-tab "set-t")]
                    [(one r1 a1) (complete-test-tab "su")]
                    [(none r2 a2) (complete-test-tab "zzz")]
                    [(sole r3 a3) (complete-test-tab "*scratch*")])
         (and (equal? (complete-test-names-of owner)
                      '("set-theme!" "set-theme-plist!"))
              (equal? replaced "set-theme") (not accepted)
              (equal? a1 "sum") (not (complete-of one))
              (equal? (complete-message (complete-of none)) "No completions")
              (equal? (complete-message (complete-of sole))
                      "Sole completion"))))

(check "the match: segments where a name's parts start, in any order, case \
        aside: \"stp\" finds set-theme-plist!, \":sp\" head:split-window \
        but not head:window-split, \"*\" *scratch*"
       (let ([names (lambda (q) (map car (vector->list
                                          (complete-test-rank q))))])
         (and (member "set-theme-plist!" (names "stp"))
              (member "set-theme-plist!" (names "STP"))
              (member "head:split-window" (names ":sp"))
              (not (member "head:window-split" (names ":sp")))
              (equal? (names "*") '("*scratch*")))))

(check "the word changed while the list is open narrows it, and only the \
        word itself left closes it; a list of no items is none"
       (let-values ([(owner replaced accepted) (complete-test-tab "set")])
         (complete-narrow! owner 'names 0 "set-th"
                           (complete-test-rank "set-th"))
         (let ([narrowed (complete-test-names-of owner)])
           (complete-narrow! owner 'names 0 "sum" (complete-test-rank "sum"))
           (let ([closed (not (complete-of owner))])
             (complete-open! owner 'names 0 '#())
             (and (equal? narrowed '("set-theme!" "set-theme-plist!"))
                  closed (not (complete-of owner)))))))

(check "keys: Down and Up move, wrapping; Tab goes to the next page's \
        first row and Shift+Tab back; Return puts the selected one in; \
        Escape closes"
       (let ([owner (list 'owner)] [accepted (box #f)]
             [items (list->vector
                     (map (lambda (i) (list (format "n~a" i) #f '()))
                          (iota 20)))])
         (define (key! k . mods)
           (complete-key! owner k mods (lambda (it) (set-box! accepted
                                                              (car it)))))
         (complete-open! owner 'names 0 items)
         (let* ([sel (lambda () (complete-sel (complete-of owner)))]
                [up (begin (key! 'up) (sel))]          ; wraps to the last
                [down (begin (key! 'down) (sel))]      ; back to the first
                [paged (begin (key! 'tab) (sel))]
                [back (begin (key! 'tab 'shift) (sel))])
           (key! 'down)
           (key! 'return)
           (let ([taken (unbox accepted)])
             (key! 'escape)
             (and (= up 19) (= down 0) (= paged complete-rows) (= back 0)
                  (equal? taken "n1") (not (complete-of owner)))))))

(check "the wheel moves the selection; a press on a row puts it in, one \
        outside the list closes it"
       (let ([owner (list 'owner)] [accepted (box #f)]
             [items (list->vector
                     (map (lambda (i) (list (format "n~a" i) #f '()))
                          (iota 20)))]
             [rh (complete-row-height)])
         (define (press! x y)
           (complete-mouse-down! owner x y 'left
                                 (lambda (it) (set-box! accepted (car it)))))
         (complete-open! owner 'names 0 items)
         (complete-wheel! owner -2)
         (let ([wheeled (complete-sel (complete-of owner))])
           ;; as a draw left it: at (100, 50), 8 rows from y 54
           (complete-box-set! (complete-of owner)
                              (list 100 50 200 (+ 8 (* 8 rh)) 8 54))
           (press! 120 (+ 54 (* 3 rh) (quotient rh 2)))
           (let ([clicked (unbox accepted)])
             (press! 10 10)
             (and (= wheeled 2) (equal? clicked "n3")
                  (not (complete-of owner)))))))

(check "a popup goes at the next key, typing, the wheel or a press, which \
        then act as usual"
       (for-all
        (lambda (go!)
          (let-values ([(owner replaced accepted) (complete-test-tab "zzz")])
            (and (complete-of owner)
                 (not (go! owner))
                 (not (complete-of owner)))))
        (list (lambda (o) (complete-key! o 'down '() void))
              complete-text!
              (lambda (o) (complete-wheel! o 1))
              (lambda (o) (complete-mouse-down! o 5 5 'left void)))))

(check "a segment starts where a part of the name does: letters in order \
        inside a part match nothing; segments out of order match, after \
        those in order; an exact name comes first"
       (let ([names (lambda (q choices)
                      (map car (vector->list
                                (complete-rank q (map (lambda (n) (cons n #f))
                                                      choices)
                                               (lambda (n) #f)))))])
         (and (null? (names "sem" '("set-theme!")))
              (equal? (names "thse" '("set-theme" "theme-set"))
                      '("theme-set" "set-theme"))
              (equal? (car (names "string" '("string-append" "substring"
                                             "string" "string?")))
                      "string"))))
