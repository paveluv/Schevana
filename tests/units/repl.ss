;;; tests/units/repl.ss — the REPL asks for frames only while it has
;;; something to show: an evaluation's output and busy mark; its caret
;;; blinks by a timer, and its title follows its environment. Tab always
;;; completes: it never inserts space, wherever the cursor is.

(for-each close-window! (windows))

(let* ([win (repl 'private)]
       [r (window-ref win 'state)]
       [asked? (lambda () (window-ref win 'wm-frame-soon #f))]
       [said? (lambda (s)
                (exists (lambda (l) (string-contains-ci? (cdr l) s))
                        (transcript-lines (repl-transcript r))))])
  (steps 3)
  (check "an idle REPL asks for no frame"
         (not (asked?)))
  (repl-run! r win "(begin (display \"hello-from-repl\") (+ 40 2))")
  (check "an evaluation asks for its frames"
         (asked?))
  (let loop ([n 0])
    (when (and (repl-proc r) (< n 500)) (steps 1) (loop (+ n 1))))
  (steps 2)
  (check "what it printed and returned is shown, and then the frames stop"
         (and (not (repl-proc r)) (said? "hello-from-repl") (said? "42")
              (not (asked?))))
  (focus-window! win)
  (check "with the keyboard its caret blinks by a timer, one at a time"
         (and (window-ref win 'repl-blinking #f)
              (let ([n (length *timers*)])
                (focus-window! win)
                (= n (length *timers*)))))
  (let ([was (repl-blink r)])
    (fluid-let ([now-ms (let ([t (+ (now-ms) 600)]) (lambda () t))])
      (run-timers!))
    (check "and it flips 530 ms after the last flip"
           (not (eq? was (repl-blink r)))))
  (env-drop! (repl-env r))
  (steps 2)
  (check "its environment dropped, its title says so"
         (string-contains-ci? (window-title win) "dropped"))
  (close-window! win))

;; Tab with nothing typed offers every name, as an empty name would, and
;; right after a paren only what can head a form; with a name it extends
;; it, takes a sole match, or says there is none.
(let* ([win (repl 'private)]
       [r (window-ref win 'state)]
       [tab! (lambda (text)
               (complete-close! r)
               (repl-input-set! r text)
               (repl-point-set! r (string-length text))
               (repl-complete! r))]
       [offered (lambda ()
                  (let ([c (complete-of r)])
                    (and c (not (complete-message c))
                         (map car (vector->list (complete-items c))))))]
       [said (lambda ()
               (let ([c (complete-of r)]) (and c (complete-message c))))])
  (repl-run! r win "(define zz-tab-alpha 1) (define zz-tab-alpha-two 2) \
                    (define (zz-tab-call) 3)")
  (let loop ([n 0])
    (when (and (repl-proc r) (< n 500)) (steps 1) (loop (+ n 1))))
  (repl-input-set! r "")
  (repl-point-set! r 0)
  (let ([all (let-values ([(kind start typed choices) (completion-context r)])
               (map car (vector->list (rank-choices typed choices))))])
    (tab! "")
    (check "tab on an empty prompt inserts nothing and offers every name"
           (and (string=? "" (repl-input r)) (pair? all)
                (equal? all (offered))))
    (tab! "(")
    (check "and right after a paren, procedures and syntax"
           (let ([c (complete-of r)])
             (and (string=? "(" (repl-input r)) (offered)
                  (for-all (lambda (item) (member (cadr item)
                                                  '("proc" "syntax")))
                           (vector->list (complete-items c)))
                  (not (equal? all (offered))))))
    (tab! "(list 1 ")
    (check "and after a space inside a form"
           (and (string=? "(list 1 " (repl-input r)) (equal? all (offered))))
    (repl-insert! r "zz-tab")
    (refresh-completion! r)
    (repl-delete! r (- (repl-point r) 6) (repl-point r))
    (refresh-completion! r)
    (check "a name typed there and taken back offers every name again"
           (equal? all (offered))))
  (tab! "( zz-tab")
  (check "a name there completes to what can be called, not a variable"
         (string=? "( zz-tab-call" (repl-input r)))
  (tab! "(let ([zz-tab")
  (check "a bracket's name is not a call: variables too"
         (member "zz-tab-alpha" (offered)))
  (tab! "(list zz-tab-al")
  (check "tab extends a name to what its matches share and lists them"
         (and (string=? "(list zz-tab-alpha" (repl-input r))
              (equal? (list-head (offered) 2)
                      '("zz-tab-alpha" "zz-tab-alpha-two"))))
  (repl-insert! r "-t")
  (refresh-completion! r)
  (let ([narrowed (offered)])
    (repl-key r win 'tab '())
    (check "tab on a list typing narrowed to one takes it"
           (and (equal? narrowed '("zz-tab-alpha-two"))
                (string=? "(list zz-tab-alpha-two" (repl-input r))
                (not (complete-of r)))))
  (tab! "(list zz-tab-alpha-t")
  (check "a sole match goes in"
         (and (string=? "(list zz-tab-alpha-two" (repl-input r))
              (not (complete-of r))))
  (repl-complete! r)
  (check "and tab on it again says it is the sole completion"
         (and (string=? "(list zz-tab-alpha-two" (repl-input r))
              (equal? (said) "Sole completion")))
  (tab! "(zzqxjw")
  (check "with nothing matching it says so and inserts nothing"
         (and (string=? "(zzqxjw" (repl-input r))
              (equal? (said) "No completions")))
  (complete-close! r)
  (close-window! win))

;; "/core0": core0 runs the forms, between frames, in its own environment
(let* ([win (repl "/core0")]
       [r (window-ref win 'state)]
       [said? (lambda (s)
                (exists (lambda (l) (string-contains-ci? (cdr l) s))
                        (transcript-lines (repl-transcript r))))])
  (steps 2)
  (repl-run! r win "(begin (display \"from-core0\") (core0-forked?))")
  (let loop ([n 0])
    (when (and (repl-proc r) (< n 200)) (steps 1) (loop (+ n 1))))
  (check "a REPL in /core0 sends its forms to core0, which prints and returns \
          from its own environment"
         (and (not (repl-proc r)) (said? "from-core0") (said? "#f")))
  (repl-run! r win "(car '())")
  (let loop ([n 0])
    (when (and (repl-proc r) (< n 200)) (steps 1) (loop (+ n 1))))
  (check "an error there comes back as one, and core0 goes on"
         (and (not (repl-proc r)) (said? "car")))
  (check "and its (exit) is still core0's: the REPL leaves it alone"
         (eq? (top-level-value 'exit (core0-environment))
              (top-level-value 'exit (scheme-environment))))
  (close-window! win))
