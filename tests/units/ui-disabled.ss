;;; tests/units/ui-disabled.ss — a disabled subtree of the kit's widgets
;;; ((schevana kits ui), ui-disabled), tested by itself: what it draws keeps
;;; its place and its tooltip but takes no input, Tab passes it by, a
;;; widget that had the keyboard lets go of it, an overlay opened inside is
;;; disabled too, and the state unwinds.

;; A window with a field, a button that counts its presses, a second
;; field, and an overlay the button's row opens, all under ui-disabled
;; while off? says so.
(define ui-disabled-test-presses 0)
(define ui-disabled-test-off? #f)
(define ui-disabled-test-later-flags #f)

(define (ui-disabled-test-window)
  (set! ui-disabled-test-presses 0)
  (set! ui-disabled-test-off? #f)
  (test-kit-window "Disabled"
    (lambda (ui w h)
      (ui-text-field ui 'a 20 10 200 30 "" void)
      (let ([row (lambda ()
                   (ui-button ui 'b 20 50 120 30 "Press"
                              (lambda ()
                                (set! ui-disabled-test-presses
                                  (+ ui-disabled-test-presses 1)))
                              'tip "Counts")
                   (ui-text-field ui 'c 20 90 200 30 "" void)
                   (ui-later! ui
                     (lambda (w h)
                       (ui-region! ui 'over 260 10 60 30 'on (lambda (ev) #t))
                       (set! ui-disabled-test-later-flags
                         (ui-flags ui 'over)))))])
        (if ui-disabled-test-off?
            (ui-disabled ui row)
            (row))))
    '(400 . 200)))

(check "a disabled widget keeps its place and its tooltip, shows disabled, \
        and a press does nothing; an overlay it opens is disabled too"
       (let ([win (ui-disabled-test-window)])
         (steps 2)
         (let ([ui (window-ref win 'ui)])
           (test-click! win 'b)
           (let ([live ui-disabled-test-presses]
                 [live-frame (ui-region-frame (test-region ui 'b))])
             (set! ui-disabled-test-off? #t)
             (invalidate! win)
             (steps 2)
             (test-click! win 'b)
             (let* ([r (test-region ui 'b)]
                    [r (list ui-disabled-test-presses (ui-region-frame r)
                             (ui-region-tip r) (ui-region-on r)
                             (ui-region-on (test-region ui 'over))
                             ui-disabled-test-later-flags)])
               (close-window! win)
               (printf "  ~s\n" r)
               (and (= live 1) (= (car r) 1)
                    (equal? (cadr r) live-frame)
                    (equal? (caddr r) "Counts")
                    (not (cadddr r)) (not (list-ref r 4))
                    (memq 'disabled (list-ref r 5)) #t))))))

(check "Tab passes a disabled widget by, and a field that had the keyboard \
        lets go of it when it is disabled"
       (let ([win (ui-disabled-test-window)])
         (steps 2)
         (let ([ui (window-ref win 'ui)])
           (test-click! win 'c)
           (let ([had (ui-focused ui)])
             (set! ui-disabled-test-off? #t)
             (invalidate! win)
             (steps 2)
             (let ([after (ui-focused ui)])
               (test-click! win 'a)
               (inject! '(key-down tab ()))
               (steps 2)
               (let ([tabbed (ui-focused ui)])
                 (close-window! win)
                 (printf "  ~s\n" (list had after tabbed))
                 (and (equal? had 'c) (not after)
                      (not (member tabbed '(b c))))))))))

(check "ui-disabled returns what its thunk returns, nests, and unwinds: \
        after it, or after an error inside it, widgets are live again"
       (let ([ui (make-ui)] [flags (lambda (ui) (ui-flags ui 'x))])
         (let* ([value (ui-disabled ui (lambda ()
                                         (ui-disabled ui (lambda () 7))))]
                [inside (ui-disabled ui (lambda () (flags ui)))]
                [after (flags ui)]
                [raised (guard (c [#t 'raised])
                          (ui-disabled ui (lambda () (error 'x "inside"))))]
                [after-error (flags ui)])
           (and (= value 7) (memq 'disabled inside) #t
                (not (memq 'disabled after))
                (eq? raised 'raised)
                (not (memq 'disabled after-error))))))
