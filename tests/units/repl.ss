;;; tests/units/repl.ss — the REPL asks for frames only while it has
;;; something to show: an evaluation's output and busy mark; its caret
;;; blinks by a timer, and its title follows its environment.

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

;; "/host": core0 runs the forms, between frames, in its own environment
(let* ([win (repl "/host")]
       [r (window-ref win 'state)]
       [said? (lambda (s)
                (exists (lambda (l) (string-contains-ci? (cdr l) s))
                        (transcript-lines (repl-transcript r))))])
  (steps 2)
  (repl-run! r win "(begin (display \"from-core0\") (host-forked?))")
  (let loop ([n 0])
    (when (and (repl-proc r) (< n 200)) (steps 1) (loop (+ n 1))))
  (check "a REPL in /host sends its forms to core0, which prints and returns \
          from its own environment"
         (and (not (repl-proc r)) (said? "from-core0") (said? "#f")))
  (repl-run! r win "(car '())")
  (let loop ([n 0])
    (when (and (repl-proc r) (< n 200)) (steps 1) (loop (+ n 1))))
  (check "an error there comes back as one, and core0 goes on"
         (and (not (repl-proc r)) (said? "car")))
  (check "and its (exit) is still core0's: the REPL leaves it alone"
         (eq? (top-level-value 'exit (host-environment))
              (top-level-value 'exit (scheme-environment))))
  (close-window! win))
