;;; tests/units/repl.ss — the REPL asks for frames only while it has
;;; something to show (an evaluation's output and its busy mark); its caret
;;; blinks by a timer, and its title follows its environment. Tab always
;;; completes: it never inserts a space, wherever the cursor is. Its text is
;;; selected with the mouse, copied and pasted.

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
;; right after a paren only what can head a form. After a name, it extends
;; the name, takes the only match, or says there is none.
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

;; At "/", a define of a name the core gives the world gets a note, once,
;; as it is evaluated, that the name becomes the world's own (except in the
;; hacker edition); a define of one of the world's own names gets none.
(let* ([win (repl "/")]
       [r (window-ref win 'state)]
       [notes (lambda ()
                (length (filter (lambda (l)
                                  (string-contains-ci?
                                   (cdr l) "edit the core's library"))
                                (transcript-lines (repl-transcript r)))))])
  (repl-note-core! r '(define (platform-machine-load) "mine"))
  (let ([after-core (notes)])
    (repl-note-core! r '(define (units-repl-own) 1))
    (repl-note-core! r '(+ 1 2))
    (check "a define in \"/\" of a core name says it's the world's own, \
            and to edit the core's library, but in the hacker edition, where \
            it is the core's; one of the world's says nothing"
           (let ([n (if test-hacker? 0 1)])
             (and (= after-core n) (= (notes) n)))))
  (close-window! win))

(check "every kind of REPL says its keys as it opens, and a running form's \
        tooltip says what Ctrl+C and Backspace do to the forms waiting \
        under it"
       (let* ([said? (lambda (win s)
                       (exists (lambda (l) (string-contains-ci? (cdr l) s))
                               (transcript-lines
                                (repl-transcript (window-ref win 'state)))))]
              [wins (map repl '(root private pure sandbox))]
              [keys? (for-all (lambda (w)
                                (and (said? w "↑↓ history")
                                     (said? w "Tab completes by parts")))
                              wins)]
              [root-new? (said? (car wins) "Ctrl+Shift+R")]
              [r (window-ref (car wins) 'state)]
              [alone (repl-busy-tip-words r)])
         (repl-queue-set! r '("(+ 1 2)" "(+ 3 4)"))
         (let ([waiting (repl-busy-tip-words r)])
           (repl-queue-set! r '())
           (for-each close-window! wins)
           (and keys? root-new? (not (string-contains-ci? alone "waiting"))
                (string-contains-ci? waiting "drops the 2 waiting")
                (string-contains-ci? waiting "Backspace")))))

;; The root REPL's greeting shows how to load an app by its name, and the
;; line it shows works: it opens the window of the game under games/.
(let* ([win (repl 'root)] [r (window-ref win 'state)]
       [line "(import (games fireflies)) (fireflies)"])
  (repl-run! r win line)
  (let loop ([n 0])
    (when (and (repl-proc r) (< n 500)) (steps 1) (loop (+ n 1))))
  (steps 2)
  (let ([game (find-window 'fireflies)])
    (check "the root REPL's greeting shows a line that loads an app by its \
            name, and it does: (import (games fireflies)) (fireflies) opens \
            the game"
           (and (exists (lambda (l) (string-contains-ci? (cdr l) line))
                        (transcript-lines (repl-transcript r)))
                game
                #t))
    (when game (close-window! game)))
  (close-window! win))

;; The point on screen of position p, (line . index), of the lines t last
;; placed in win: in the character's left quarter, which reads as before
;; it whatever the font.
(define (repl-test-point win t p)
  (let* ([g (transcript-grid t)] [x0 (vector-ref g 0)] [cw (vector-ref g 1)]
         [lh (vector-ref g 2)] [cols (vector-ref g 3)]
         [placed (find (lambda (pl) (= (car pl) (car p)))
                       (transcript-placed t))])
    (let-values ([(cx cy w h) (content-rect win)])
      (values (exact (floor (+ cx x0 (* cw (remainder (cdr p) cols))
                               (/ cw 4))))
              (exact (floor (+ cy (cadr placed)
                               (* lh (quotient (cdr p) cols)) (/ lh 2))))))))

(let* ([win (repl 'private)] [r (window-ref win 'state)]
       [t (repl-transcript r)])
  (repl-add! r 'output "alpha beta")
  (repl-add! r 'output "gamma delta")
  (focus-window! win)
  (steps 2)
  (let* ([n (- (transcript-end t) 1)] [m (- n 1)])
    (define (mouse! kind p . more)
      (let-values ([(x y) (repl-test-point win t p)])
        (inject! `(mouse-move ,x ,y)
                 (case kind
                   [(down) `(mouse-down ,x ,y ,@more)]
                   [(up) `(mouse-up ,x ,y left)]
                   [else `(mouse-move ,x ,y)]))
        (steps 1)))
    ;; from "beta" of one line to after "gamma" of the next
    (mouse! 'down (cons m 6) 'left 1)
    (mouse! 'move (cons n 5))
    (mouse! 'up (cons n 5))
    (let ([dragged (transcript-selection t)])
      (inject! '(key-down #\c (ctrl shift)))
      (steps 1)
      (let ([copied (clipboard-get)])
        (mouse! 'down (cons n 8) 'left 2)
        (mouse! 'up (cons n 8))
        (let ([word (transcript-selection t)])
          (mouse! 'down (cons n 0) 'right 1)
          (let ([menu (and *menu*
                           (map (lambda (e)
                                  (cons (car e) (menu-entry-ready? e)))
                                (menu-entries *menu*)))])
            (menu-activate! 1)
            (steps 2)
            (let ([pasted (repl-input r)] [end (transcript-end t)])
              ;; the input's first line, after its prompt
              (mouse! 'down (cons end 5) 'left 1)
              (mouse! 'up (cons end 5))
              (let ([point (repl-point r)])
                (close-window! win)
                (check (format "a press and a drag select a REPL's text \
                                across lines, which Ctrl+Shift+C copies; two \
                                clicks select a word; a right press opens \
                                the text menu, whose Paste types at the \
                                cursor; a click on the input moves the \
                                cursor there ~s"
                               (list dragged copied word menu pasted point))
                       (and (equal? dragged "beta\ngamma")
                            (equal? copied "beta\ngamma")
                            (equal? word "delta")
                            (equal? menu '(("Copy\tCtrl+Shift+C" . #t)
                                           ("Paste\tCtrl+V" . #t)))
                            (equal? pasted "beta\ngamma")
                            (= point 2)))))))))))

;; A REPL's scroll bar is the kit's own: returns what proc does with a REPL
;; of 80 more lines in style, its transcript and the bar's frame on the
;; screen, as a procedure (#f for none).
(define (repl-test-bar style proc)
  (set-style! style)
  (let* ([win (repl 'private)] [r (window-ref win 'state)]
         [t (repl-transcript r)])
    (focus-window! win)
    (do ([i 0 (+ i 1)]) ((= i 80)) (repl-add! r 'output (format "line ~a" i)))
    (invalidate! win)
    (steps 2)
    (let ([v (proc win r t
                   (lambda ()
                     (let ([g (ui-find (transcript-ui t) 'bar)])
                       (and g
                            (let-values ([(cx cy cw ch) (content-rect win)])
                              (let ([f (ui-region-frame g)])
                                (list (+ cx (car f)) (+ cy (cadr f))
                                      (caddr f) (cadddr f))))))))])
      (close-window! win)
      (set-style! 'mac)
      (steps 1)
      v)))

(define (repl-test-press! x y button)
  (let ([x (exact (round x))] [y (exact (round y))])
    (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y ,button 1)
             `(mouse-up ,x ,y ,button))
    (steps 2)))

(check "in Genera a REPL's scroll bar is always there, clear of its text, as \
        the Listener's is: its boxes and its shaft scroll it, the mouse line \
        calls what it holds its history, and neither the selection nor the \
        input's cursor moves; the pointer is an I-beam again off it"
       (repl-test-bar 'genera
         (lambda (win r t bar)
           (repl-insert! r "abc")
           (repl-point-set! r 1)
           (invalidate! win)
           (steps 2)
           (let*-values
               ([(f) (bar)]
                [(x) (+ (car f) (/ (caddr f) 2))]
                [(y) (cadr f)] [(h) (cadddr f)]
                [(cx cy cw ch) (content-rect win)]
                [(scroll) (lambda (d button)
                            (repl-test-press! x (+ y d) button)
                            (transcript-scroll t))]
                [(up) (scroll 5 'right)]
                [(page) (scroll (- h 5) 'right)]
                [(top) (scroll 5 'middle)]
                [(end) (scroll (- h 5) 'middle)]
                [(middle) (scroll (/ h 2) 'middle)]
                [(over) (list (window-ref win 'cursor)
                              (cdr (assq 'M (mouse-doc))))]
                [(off) (begin
                         (inject! `(mouse-move ,(+ cx 200) ,(+ cy 60)))
                         (steps 1)
                         (list (window-ref win 'cursor) (mouse-doc)))]
                [(x0) (vector-ref (transcript-grid t) 0)])
             (printf "  ~s\n" (list up page top end middle over off x0 f))
             (and (= up 1) (> page 10) (> top 60) (= end 0)
                  (< 20 middle 60)
                  (equal? over '(resize-ns "Move to 50% of history"))
                  (equal? off '(ibeam ()))
                  (>= (+ cx x0) (+ (car f) (caddr f)))
                  (= (repl-point r) 1)
                  (string=? (transcript-selection t) ""))))))

(check "elsewhere a REPL's scroll bar is there while it is scrolled back, and \
        its thumb drags"
       (repl-test-bar 'mac
         (lambda (win r t bar)
           (let ([before (bar)])
             (repl-scroll-set! r 30)
             (invalidate! win)
             (steps 2)
             (let* ([f (bar)]
                    ;; inside of where the window's edge resizes it
                    [x (exact (round (+ (car f) 2)))]
                    [y (exact (round (+ (cadr f) (/ (cadddr f) 2))))]
                    [bottom (exact (round (+ (cadr f) (cadddr f) -2)))])
               (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                        `(mouse-move ,x ,bottom))
               (steps 2)
               (let ([dragged (transcript-scroll t)] [held (and (bar) #t)])
                 (inject! `(mouse-up ,x ,bottom left))
                 (steps 2)
                 (printf "  ~s\n" (list before f dragged held (bar)))
                 (and (not before) f (= dragged 0) held (not (bar))
                      (string=? (transcript-selection t) ""))))))))
