;;; tests/units/ui-flame.ss — the kit's flame and its source view
;;; ((schevana kits ui)), tested by themselves.

;; A tree of (label value child ...): a root of 100, a at 60 with two
;; children, one of them with a child of its own, b at 30, and 10 that no
;; child has.
(define ui-flame-test-tree
  '("root" 100
    ("a" 60 ("a1" 40 ("a1x" 40)) ("a2" 20))
    ("b" 30)))

(define ui-flame-test-picked #f)
(define ui-flame-test-win
  (test-kit-window "Flame"
    (lambda (ui w h)
      ;; room for three rows
      (ui-flame ui 'f 0 0 400 (* 3 (ui-flame-row-height))
                ui-flame-test-tree car cadr cddr
                'tip (lambda (node) (format "~a: ~a" (car node) (cadr node)))
                'on-pick (lambda (node)
                           (set! ui-flame-test-picked (car node))))
      (ui-source ui 'src 0 100 400 90 '("(define (f x)" "  (+ x 1))" "")
                 'first 7 'marked 1))
    '(400 . 200)))
(steps 2)

(define (ui-flame-test-box . path)
  (ui-find (window-ref ui-flame-test-win 'ui) (list 'f 'box path)))

(check "a flame lays a tree out in rows, each box as wide as its share of \
        its parent, with its tooltip; rows past the height are left out"
       (let ([root (ui-flame-test-box)] [a (ui-flame-test-box "a")]
             [b (ui-flame-test-box "b")] [a1 (ui-flame-test-box "a" "a1")])
         (and root a b a1
              (= (ui-region-w root) 400)
              (= (ui-region-w a) 240)
              (= (ui-region-w b) 120)
              (= (ui-region-x b) 240)
              (> (ui-region-y a) (ui-region-y root))
              (= (ui-region-w a1) 160)
              (equal? (ui-region-tip a) "a: 60")
              (not (ui-flame-test-box "a" "a1" "a1x")))))

(check "a press on a box makes it the root shown and tells the app; a \
        press on the root shown goes back out"
       (begin
         (test-click! ui-flame-test-win '(f box ("a")))
         (steps 1)
         (let ([in (ui-flame-test-box "a")]
               [child (ui-flame-test-box "a" "a1")]
               [gone (ui-flame-test-box "b")])
           (test-click! ui-flame-test-win '(f box ("a")))
           (steps 1)
           (and (equal? ui-flame-test-picked "a")
                in (= (ui-region-w in) 400)
                child (> (ui-region-w child) 260)
                (not gone)
                (ui-flame-test-box "b")
                (= (ui-region-w (ui-flame-test-box)) 400)))))

(check "the source view lays its lines out to scroll"
       (and (ui-find (window-ref ui-flame-test-win 'ui) 'src) #t))

(check "the source view keeps its lines clear of a scroll bar at its left \
        (Genera's)"
       (let ([style (current-style)] [real draw-text] [xs '()])
         (set-style! 'genera)
         (let ([win (test-kit-window "Source"
                      (lambda (ui w h)
                        (ui-source
                         ui 'lines 20 10 300 100
                         (map (lambda (i) (format "line ~a" i)) (iota 40)))))])
           (steps 2)
           (fluid-let ([draw-text
                        (lambda (x y s . rest)
                          (when (and (> (string-length s) 5)
                                     (string=? (substring s 0 5) "line "))
                            (set! xs (cons x xs)))
                          (apply real x y s rest))])
             (invalidate! win)
             (steps 2))
           (let ([f (ui-region-frame
                     (test-region (window-ref win 'ui)
                                  '(lines bar)))])
             (close-window! win)
             (set-style! style)
             (steps 1)
             (printf "  ~s ~s\n" f (and (pair? xs) (car xs)))
             (and (pair? xs)
                  (for-all (lambda (x) (>= x (+ (car f) (caddr f)))) xs))))))
