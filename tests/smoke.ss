;;; tests/smoke.ss — drive the whole world headlessly with synthetic events.
;;;
;;;   scheme --script tests/smoke.ss [output-dir]
;;;
;;; Writes screenshots into output-dir (default: current directory).

(define *schevana-root*
  (let ([dir (path-parent (path-parent (car (command-line))))])
    (if (string=? dir "") "." dir)))

(load (string-append *schevana-root* "/tests/lib.ss"))

;; Returns the screen as it would be drawn now. The bytes are kept until a
;; frame is asked for or drawn, so that reading pixel after pixel costs
;; only one drawing.
(define screen-picture-kept #f)
(define screen-picture-frames -1)
(define (screen-picture)
  (when (or *dirty* (not screen-picture-kept)
            (not (= screen-picture-frames *frames-drawn*)))
    (set! screen-picture-kept (screen-bytes))
    (set! screen-picture-frames *frames-drawn*))
  screen-picture-kept)

;; The screen's pixel at device x, y.
(define (screen-pixel x y)
  (bytevector-u32-native-ref (screen-picture) (* 4 (+ x (* y *canvas-pw*)))))

;; Typing and key presses, under the names the suite has always used
;; (tests/lib.ss).
(define type! test-type!)
(define press! test-press!)

(define (repl-of win) (window-ref win 'state))

(define (transcript win)
  (map cdr (reverse (repl-lines (repl-of win)))))

;; Whether pred comes true while the world goes on, for work done
;; elsewhere (a process, a thread). It waits at most 10 s of the machine's
;; clock, as long as a slow machine may take, and returns as soon as pred
;; is true.
(define (wait-for pred) (and (test-wait 10000 pred) #t))


;; Click (or drag across) a ui widget by its id, with real mouse events.
(define (ui-point win id frac)
  (let ([r (ui-find (window-ref win 'ui) id)])
    (unless r (errorf 'ui-point "no widget ~s" id))
    (let-values ([(cx cy cw ch) (content-rect win)])
      (values (exact (round (+ cx (ui-region-x r) 8
                               (* frac (- (ui-region-w r) 16)))))
              (exact (round (+ cy (ui-region-y r) (/ (ui-region-h r) 2))))))))

;; Turns the wheel over a scrolling pane (Settings') until the area id is
;; in view: inside the window's content and on the desktop, clear of the
;; desktop's bars, which grow with the fonts. The suite needs at most 41
;; turns (the Theme tab's length at the biggest fonts), and it never turns
;; more than 200 times, for an area that no wheel brings into view.
(define (scroll-to-ui! win id)
  (let loop ([n 0])
    (let*-values ([(x y) (ui-point win id 0.5)]
                  [(cx cy cw ch) (content-rect win)]
                  [(dx dy dw dh) (desktop-rect)]
                  [(top) (max cy dy)]
                  [(bottom) (min (+ cy ch) (+ dy dh))])
      (let ([dy (cond [(> y (- bottom 10)) -1] [(< y (+ top 10)) 1] [else 0])])
        (unless (or (zero? dy) (= n 200))
          (inject! `(mouse-move ,(+ cx cw -20) ,(+ cy 100)) `(wheel 0 ,dy))
          (steps 2)
          (loop (+ n 1)))))))

(define (click-ui! win id)
  (scroll-to-ui! win id)
  (let-values ([(x y) (ui-point win id 0.5)])
    (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
             `(mouse-up ,x ,y left))
    (steps 2)))

(define (drag-ui! win id frac)
  (let-values ([(x0 y) (ui-point win id 0.5)] [(x1 y1) (ui-point win id frac)])
    (inject! `(mouse-down ,x0 ,y left 1) `(mouse-move ,x1 ,y)
             `(mouse-up ,x1 ,y left))
    (steps 2)))

;; The demos the suite drives.
(test-demos! 'life 'sketch)
(schevana-boot! 'headless 1280 800)
;; From here on, a form that raises fails and the next form goes on.
(current-eval test-form-eval)

(check "a form outside a check that raises is a failure, said with its \
        place, and the suite goes on; an eval inside a form raises as it \
        would"
       (let* ([before failures]
              ;; as the loader evaluates a form (this check is one)
              [said (with-output-to-string
                      (lambda ()
                        (fluid-let ([test-form-running #f])
                          (test-form-eval '(car #f)))))]
              [counted (= failures (+ before 1))])
         (set! failures before)
         (and counted (string-prefix? "FAIL a form at " said)
              (guard (c [#t #t])
                (fluid-let ([test-form-running #t])
                  (test-form-eval '(car #f)))
                #f))))
(clock)
(move-window! (find-window 'clock) 1000 60)
(define r (repl))
(steps 2)

(check "boot opened two windows" (= 2 (length (windows))))
(check "repl is focused" (eq? r (focused-window)))

;; Evaluate an expression by typing it.
(type! "(map (lambda (x) (* x x)) '(1 2 3 4))")
(press! 'return)
(check "repl evaluates"
       (wait-for (lambda () (member "(1 4 9 16)" (transcript r)))))

;; Multi-line input: an incomplete form gets a newline, not evaluation.
(type! "(define (fact n)")
(press! 'return)
(type! "(if (= n 0) 1 (* n (fact (- n 1)))))")
(press! 'return)
(type! "(fact 20)")
(press! 'return)
(check "multi-line define"
       (wait-for (lambda () (member "2432902008176640000" (transcript r)))))

;; Output from display goes into the transcript.
(type! "(begin (display \"hello\") (newline) 42)")
(press! 'return)
(check "display output"
       (wait-for (lambda () (and (member "hello" (transcript r))
                                 (member "42" (transcript r))))))

;; Errors are shown, not fatal.
(type! "(car 5)")
(press! 'return)
(check "errors are reported"
       (wait-for (lambda () (exists (lambda (l) (string-contains-ci? l "car"))
                                    (transcript r)))))

;; An infinite loop runs as a process; Ctrl+C kills it, the world stays alive.
(type! "(let loop () (loop))")
(press! 'return)
(steps 5)
(check "infinite loop becomes a process" (= 1 (length (procs))))
(press! #\c 'ctrl)
(steps 3)
(check "ctrl+c kills it" (null? (procs)))

;; Define a brand-new app from the REPL and launch it.
(type! "(define-app (hello) \"Hello\" (open-window \"Hello\" 'size '(260 . 90) \
        'draw (lambda (win w h) (draw-text 20 30 \"Hello from the REPL!\" \
        'accent 'ui-bold))))")
(press! 'return)
(type! "(hello)")
(press! 'return)
(check "app defined at the REPL opens"
       (wait-for (lambda () (find-window "Hello"))))
(check "and is in the launcher" (memq 'hello (apps)))

;; Private and pure REPLs: experiment without touching the world.
(define world-draw-window draw-window)
(define p (repl 'private))
(steps 2)
(check "private repl opens focused" (eq? p (focused-window)))
(type! "(define (draw-window win) (error 'oops \"broken\"))")
(press! 'return)
;; typed ahead: these wait in turn while the first runs
(type! "(define private-secret 42)")
(press! 'return)
(type! "(set! *windows* '())")
(press! 'return)
(type! "(list private-secret (length (windows)))")
(press! 'return)
(check "private definitions work inside, world procedures see the world"
       (wait-for (lambda () (member (format "(42 ~a)" (length (windows)))
                                    (transcript p)))))
(check "but nothing leaks into the world"
       (and (eq? draw-window world-draw-window)
            (not (top-level-bound? 'private-secret))
            (memq p (windows))))
(type! "private-sec")
(press! 'tab)
(steps 1)
(check "tab completes from the private environment"
       (string=? "private-secret" (repl-input (repl-of p))))

;; The completion list: narrowing, choosing, contexts.
(let* ([w (repl)] [r (repl-of w)])
  (define (fresh! text)
    (repl-input-set! r "")
    (repl-point-set! r 0)
    (complete-close! r)
    (type! text)
    (steps 1))
  (define (offered)
    (let ([c (complete-of r)])
      (and c (map car (vector->list (complete-items c))))))
  (define (click! x y)
    (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
             `(mouse-up ,x ,y left))
    (steps 1))
  (fresh! "(set-th")
  (press! 'tab)
  (steps 1)
  (check "tab extends to the shared prefix and lists the choices"
         (and (string=? "(set-theme" (repl-input r))
              (equal? (list-head (offered) 2)
                      '("set-theme!" "set-theme-plist!"))))
  (png-write-screen (string-append out-dir "/completion.png"))
  (press! 'down)
  (press! 'return)
  (steps 1)
  (fresh! "(stp")
  (press! 'tab)
  (steps 1)
  (type! "l")
  (steps 1)
  (check "typing narrows the list"
         (for-all (lambda (n) (string-contains-ci? n "l")) (offered)))
  ;; whichever is offered first: the test's world has core0's names too
  (let ([lines (length (repl-lines r))] [choice (car (offered))])
    (press! 'return)
    (steps 1)
    (check "enter takes the choice instead of evaluating"
           (and (string=? (string-append "(" choice) (repl-input r))
                (= lines (length (repl-lines r))))))
  (fresh! "(theme 'acc")
  (press! 'tab)
  (steps 1)
  (check "after (theme ' it offers theme keys only"
         (equal? (offered)
                 '("accent" "accent-2" "accent-choices" "panel-accent")))
  (press! 'escape)
  (steps 1)
  (call-with-output-file (string-append out-dir "/zz-complete-me.txt")
    (lambda (p) (display "x" p))
    'replace)
  (fresh! (string-append "(load \"" out-dir "/zz-comp"))
  (press! 'tab)
  (steps 1)
  (check "inside a string it completes file names"
         (string-suffix? "/zz-complete-me.txt" (repl-input r)))
  (let-values ([(sig doc) (name-description "after" (env-root))])
    (check "a name shows its argument list and the comment above its definition"
           (and (string=? sig "(after ms thunk)")
                (string-contains-ci? doc "a second later"))))
  (check "other procedures show their arity"
         (string=? "Takes 1 argument."
                   (arity-description (procedure-arity-mask car))))
  ;; Descriptions describe the code that runs: the text a file had when it
  ;; was loaded, a REPL's own definition, or what a value itself tells.
  (let ([f (let ([p (string-append out-dir "/zz-docs.ss")])
             (if (path-absolute? p)
                 p
                 (string-append (current-directory) "/" p)))]
        [env (repl-env r)])
    (define (write-source! text)
      (call-with-output-file f (lambda (p) (display text p)) 'replace))
    (define (doc name)
      (let-values ([(sig doc) (name-description name env)]) (list sig doc)))
    (write-source! ";; Doubles x.\n(define (zz-twice x) (* 2 x))\n")
    (load-sources! (list f))
    (check "a loaded file's definition is described"
           (equal? (doc "zz-twice") '("(zz-twice x)" "Doubles x.")))
    (write-source! ";; Triples x.\n(define (zz-twice x y) (* 3 x))\n")
    (check "a file edited since it loaded still tells of what loaded"
           (equal? (doc "zz-twice") '("(zz-twice x)" "Doubles x.")))
    (load-sources! (list f))
    (check "and of the new text once that is loaded"
           (equal? (doc "zz-twice") '("(zz-twice x y)" "Triples x.")))
    (let ([text ";; Adds them.\n(define (zz-twice a b) (+ a b))"])
      (repl-input-set! r text)
      (repl-point-set! r (string-length text)))
    (press! 'return)
    (check "a procedure redefined at the REPL is described as typed there"
           (wait-for (lambda ()
                       (equal? (doc "zz-twice")
                               '("(zz-twice a b)" "Adds them.")))))
    (env-eval env '(set! zz-twice car))
    (check "set! to another procedure: what that procedure tells"
           (equal? (doc "zz-twice") '("(zz-twice …)" "Takes 1 argument.")))
    (check "an app's launcher, made by define-app, keeps its description"
           (equal? (car (doc "clock")) "(clock)"))
    (fresh! "(let ((x)) x)")
    (press! 'return)
    (check "an error in REPL input says where in it"
           (wait-for (lambda ()
                       (exists (lambda (l) (string-contains-ci? l "REPL input"))
                               (transcript w))))))
  ;; Libraries: a folder of our own, searched by import and offered by Tab.
  (let ([lib (string-append out-dir "/lib")])
    (for-each (lambda (d) (unless (file-exists? d) (mkdir d)))
              (list lib (string-append lib "/acme")))
    (call-with-output-file (string-append lib "/acme/math.sls")
      (lambda (p)
        (write '(library (acme math) (export square (rename (twice double)))
                  (import (rnrs))
                  (define (square x) (* x x)) (define (twice x) (+ x x)))
               p))
      'replace)
    (add-library-directory! lib)
    (check "the tree is searched by import, the user's lib folder not"
           (let ([on-path? (lambda (dir)
                             (exists (lambda (e)
                                       (equal? (path-full (if (pair? e)
                                                              (car e)
                                                              e))
                                               (path-full dir)))
                                     (library-directories)))])
             (and (on-path? *schevana-root*)
                  (not (on-path? user-library-directory)))))
    (check "import loads a library from an added folder"
           (equal? '(25 6)
                   (eval '(let () (import (acme math))
                            (list (square 5) (double 3))))))
    (fresh! "(import (ac")
    (press! 'tab)
    (steps 1)
    (check "tab in an import completes the first part and offers the next"
           (and (string=? "(import (acme " (repl-input r))
                (equal? (offered) '("math"))))
    (press! 'return)
    (steps 1)
    (check "and return takes the library"
           (and (string=? "(import (acme math" (repl-input r)) (not (offered))))
    (fresh! "(import (only (acme m")
    (press! 'tab)
    (steps 1)
    (check "library names complete inside only"
           (string=? "(import (only (acme math" (repl-input r)))
    (fresh! "(import (")
    (press! 'tab)
    (steps 1)
    (check "an empty import set offers libraries and import forms"
           (for-all (lambda (n) (member n (offered)))
                    '("acme" "rnrs" "chezscheme" "only")))
    (fresh! "(list (acm")
    (press! 'tab)
    (steps 1)
    (check "outside an import there are no library names"
           (not (member "acme" (or (offered) '()))))
    (fresh! "(library (acm")
    (press! 'tab)
    (steps 1)
    (check "a library's own name is not completed"
           (not (member "acme" (or (offered) '()))))
    (let-values ([(sig doc) (library-description '(acme) "math" "library")])
      (check "a library shows what it exports and where it is"
             (and (string=? sig "(acme math)")
                  (string-contains-ci? doc "double square")
                  (string-contains-ci? doc "acme/math.sls")))))
  ;; Tab pages through the list; Return or a click on a row accepts. A row
  ;; under the pointer shows that it takes a click: a box, a hand and the
  ;; mouse documentation's words. Off the list the cursor is the REPL's
  ;; own again, and so it is once the list closes under a still pointer.
  (fresh! "(set-th")
  (press! 'tab)
  (steps 1)
  (let-values ([(cx cy cw ch) (content-rect w)])
    (let* ([box (complete-box (complete-of r))]
           [move! (lambda (x y) (inject! `(mouse-move ,x ,y)) (steps 1))]
           [state (lambda ()
                    (let ([c (complete-of r)])
                      (list (and c (complete-hover c)) (window-ref w 'cursor)
                            (mouse-doc))))]
           [row-x (+ cx (car box) 20)]
           [row-y (+ cy (list-ref box 5) (* 3/2 (complete-row-height)))])
      (move! row-x row-y)
      (let ([over (state)])
        (png-write-screen (string-append out-dir "/completion-hover.png"))
        (move! (+ cx cw -10) (+ cy 10))
        (let ([off (state)])
          (move! row-x row-y)
          (press! 'escape)
          (steps 1)
          (check "a row under the pointer shows it, with a hand and what a \
                  click does; off the list, and once it closes, the REPL's \
                  own again"
                 (and (equal? over '(1 hand ((L . "Complete") (W . "Scroll"))))
                      (equal? off '(#f ibeam ((L . "Close the list"))))
                      (equal? (state) '(#f ibeam ()))))))))
  (fresh! "(set-th")
  (press! 'tab)
  (inject! '(wheel 0 -1))
  (steps 1)
  (let-values ([(cx cy cw ch) (content-rect w)])
    (click! (+ cx cw -10) (+ cy 10))
    (check "a click elsewhere in the REPL closes the list"
           (and (not (offered)) (string=? "(set-theme" (repl-input r)))))
  ;; Losing the keyboard closes it: a click on another window, or on the
  ;; desktop.
  (let ([open-list! (lambda ()
                      (focus-window! w)
                      (fresh! "(set-th")
                      (press! 'tab)
                      (steps 1)
                      (and (offered) #t))]
        [clock (find-window 'clock)])
    (let-values ([(cx cy cw ch) (content-rect clock)])
      (let* ([on-clock? (open-list!)]
             [_ (click! (+ cx (quotient cw 2)) (+ cy (quotient ch 2)))]
             [after-clock (offered)]
             [on-desktop? (open-list!)]
             [_ (click! 1200 700)]
             [after-desktop (offered)])
        ;; back as before the clicks: w over the private REPL, the pointer
        ;; on w
        (focus-window! p)
        (focus-window! w)
        (let-values ([(x y ww wh) (content-rect w)])
          (inject! `(mouse-move ,(+ x 20) ,(+ y 20))))
        (steps 1)
        (check "a click on another window or on the desktop closes the list"
               (and on-clock? (not after-clock) (not (window-at 1200 700))
                    on-desktop? (not after-desktop))))))
  ;; With nothing to add, a popup says so, with the sole completion's
  ;; description; the popup goes at the next key, which then acts as usual
  ;; (the list itself is tested in tests/units/complete.ss).
  (fresh! "(set-theme-plist!")
  (press! 'tab)
  (steps 1)
  (let ([c (complete-of r)])
    (check "tab on a sole completion says so, with its description"
           (and c (equal? (complete-message c) "Sole completion")
                (equal? (offered) '("set-theme-plist!"))
                (string=? "(set-theme-plist!" (repl-input r))
                (>= (cadddr (complete-box c))
                    (+ 8 (complete-row-height) (complete-detail-height 0))))))
  (png-write-screen (string-append out-dir "/completion-sole.png"))
  (press! 'backspace)
  (steps 1)
  (check "the next key closes it and acts as usual"
         (and (not (complete-of r))
              (string=? "(set-theme-plist" (repl-input r))))
  (fresh! "(zzqx")
  (press! 'tab)
  (steps 1)
  (png-write-screen (string-append out-dir "/completion-none.png"))
  (type! "y")
  (steps 1)
  ;; A small window: the rows shrink so the list leaves the line in view.
  (resize-window! w 420 140)
  (fresh! "(set-")
  (press! 'tab)
  (steps 1)
  (let-values ([(cw ch) (window-content-size w)])
    (let ([box (let ([c (complete-of r)]) (and c (complete-box c)))]
          [line (- ch repl-pad (repl-line-height))])
      (check "in a small window the list's rows shrink to leave the line \
              in view"
             (and box (< 0 (list-ref box 4) complete-rows)
                  (<= (+ (cadr box) (cadddr box)) line)))))
  (png-write-screen (string-append out-dir "/completion-small.png"))
  (let* ([c (complete-of r)]
         [shown (and c (complete-box c) (list-ref (complete-box c) 4))])
    (press! 'tab)
    (steps 1)
    (check "there Tab pages by the rows shown"
           (and shown (< shown complete-rows)
                (eqv? shown (complete-sel (complete-of r)))))
    (press! 'tab 'shift)
    (press! 'up)
    (steps 1)
    (resize-window! w 660 440)
    (steps 1)
    (let ([c (complete-of r)])
      (check "the last row selected there, the window made bigger shows \
              more rows, the last one last"
             (and (not (window-error w)) c (complete-box c)
                  (= (complete-sel c) (- (vector-length (complete-items c)) 1))
                  (= (+ (complete-top c) (list-ref (complete-box c) 4))
                     (vector-length (complete-items c)))
                  (> (list-ref (complete-box c) 4) shown)))))
  ;; Above the line the description goes over the rows, so that they stay
  ;; put as Tab pages through descriptions of other lengths.
  (do ([i 0 (+ i 1)]) ((= i 40)) (repl-add! r 'info ""))
  (fresh! "(set-")
  (press! 'tab)
  (steps 1)
  (let ([pages
         (map (lambda (k)
                (let* ([c (complete-of r)] [box (and c (complete-box c))]
                       [rows-end (and box (+ (list-ref box 5)
                                             (* (list-ref box 4)
                                                (complete-row-height))))])
                  (when (= k 1)
                    (png-write-screen (string-append out-dir
                                               "/completion-above.png")))
                  (press! 'tab)
                  (steps 1)
                  (and box (list (cadr box) (list-ref box 5) rows-end
                                 (+ (cadr box) (cadddr box))))))
              (iota 4))])
    (check "above the line the description is over the rows, which stay \
            put from page to page"
           (and (for-all (lambda (p) p) pages)
                (for-all (lambda (p) (= (+ (caddr p) 4) (cadddr p))) pages)
                (for-all (lambda (p) (= (cadr p) (cadar pages))) pages)
                (exists (lambda (p) (not (= (car p) (caar pages)))) pages))))
  ;; A REPL's own handler survives when the REPL's library is evaluated
  ;; again and run.
  (let ([mine (lambda (win x y button clicks) #f)])
    (hashtable-set! (window-handlers w) 'mouse-down mine)
    (test-reload-library! '(schevana apps repl))
    (check "the REPL's library evaluated again keeps a REPL's own mouse \
            handler"
           (eq? mine (hashtable-ref (window-handlers w) 'mouse-down #f))))
  (close-window! w))

(press! #\u 'ctrl)
(type! "(exit)")
(press! 'return)
(check "(exit) closes only the private repl"
       (wait-for (lambda () (not (memq p (windows))))))
(define q (repl 'pure))
(steps 2)
(type! "(windows)")
(press! 'return)
(check "pure repl has none of Schevana's names"
       (wait-for (lambda ()
                   (exists (lambda (l) (string-contains-ci? l "not bound"))
                           (transcript q)))))
(type! "(define x (* 6 7))")
(press! 'return)
(type! "x")
(press! 'return)
(check "but is a working Scheme"
       (wait-for (lambda () (member "42" (transcript q)))))
(check "whose definitions stay put" (not (top-level-bound? 'x)))
(repl 'private)
(steps 2)
(check "another private repl opens, titled by its environment"
       (string-prefix? "REPL — /private" (window-title (focused-window))))
(type! "(define note \"only here\")")
(press! 'return)
(steps 20)
(tile-windows!)
(steps 2)
(png-write-screen (string-append out-dir "/repl-modes.png"))
(close-window! q)
(close-window! (focused-window))
(focus-window! r)

;; A REPL in an existing environment, here a thread's, whose forms run in
;; its vat. Its title names the environment, and once the environment is
;; dropped, the REPL evaluates nowhere.
(let* ([t (env-fork (env-root) 'thread 'name 'smoke-vat)]
       [w (repl t)] [rr (repl-of w)])
  (define (enter! src) (type! src) (press! 'return) (steps 2))
  (define (idle?) (not (repl-proc rr)))
  (define (said? text)
    (wait-for (lambda () (and (idle?) (member text (transcript w)) #t))))
  (steps 2)
  (check "a REPL is titled by its environment's path, the world's too, and \
          gives its frame its kind's icon"
         (and (string=? (window-title w) "REPL — /smoke-vat")
              (string=? (window-title r) "REPL — /")
              (procedure? (window-ref w 'title-icon))))
  (enter! "(define smoke-vat-n 41)")
  (enter! "(+ smoke-vat-n 1) (lambda (x) x)")
  (check "a thread's REPL sends its forms to the vat, which prints what they \
          return"
         (and (said? "42")
              (exists (lambda (l) (string-prefix? "#<procedure" l))
                      (transcript w))
              (not (top-level-bound? 'smoke-vat-n))))
  (enter! "(car 1)")
  (check "an error in the vat is the REPL's to show, not a crash"
         (and (wait-for idle?)
              (exists (lambda (l) (string-contains-ci? l "car"))
                      (transcript w))
              (not (window-error w))))
  (enter! "(let loop () (loop))")
  (wait-for (lambda () (window-ref w 'busy)))
  (steps 2)
  (let ([b (repl-busy rr)])
    (check "a long evaluation leaves the titles be; after a moment the \
            window is busy, its mark in place of the running input's prompt"
           (and (string=? (window-title w) "REPL — /smoke-vat")
                (equal? (window-ref w 'busy)
                        "Running on its thread: Ctrl+C stops it")
                (equal? (cdr (repl-running rr)) "λ> (let loop () (loop))")
                b))
    (when b
      (let-values ([(cx cy cw ch) (content-rect w)])
        (inject! `(mouse-move ,(+ cx (car b) 2) ,(+ cy (cadr b) 2)))
        (steps 1)
        (check "over the mark the pointer is an arrow"
               (eq? (window-ref w 'cursor) 'arrow)))))
  (press! 'return)
  (steps 1)
  (check "Enter with nothing typed while a form runs queues nothing"
         (null? (repl-queue rr)))
  (type! "1")
  (press! 'return)
  (type! "(+ 1 1)")
  (press! 'return)
  (steps 1)
  (check "while a form runs, each input entered waits in turn under it, \
          the input line free for the next"
         (and (equal? (repl-queue rr) '("1" "(+ 1 1)"))
              (equal? (repl-input rr) "")))
  (press! 'backspace)
  (steps 1)
  (check "Backspace on an empty line takes the last one back"
         (and (equal? (repl-queue rr) '("1"))
              (equal? (repl-input rr) "(+ 1 1)")))
  (press! 'return)
  (steps 1)
  (press! #\c 'ctrl)
  (steps 2)
  (check "stopped, the window is no longer busy, its mark is gone, and \
          what waited was dropped (it is history)"
         (and (not (window-ref w 'busy)) (not (repl-busy rr))
              (null? (repl-queue rr)) (not (repl-running rr))
              (member "(+ 1 1)" (repl-history rr))))
  (enter! "smoke-vat-n")
  (check "ctrl+c stops a form on the vat's thread; the vat goes on"
         (and (member "; interrupted" (transcript w)) (said? "41")))
  (enter! "(fork 'sandbox)")
  (check "a thread holds no fork"
         (wait-for (lambda ()
                     (and (idle?)
                          (exists (lambda (l) (string-contains-ci? l "fork"))
                                  (transcript w))))))
  (check "no REPL opens in /worklets, where the pool's threads run"
         (guard (c [#t #t]) (repl "/worklets") #f))
  (vat-drop-env! t)
  (steps 2)
  (enter! "smoke-vat-n")
  (check "once its environment is dropped, a REPL says so, and evaluates \
          nowhere"
         (and (wait-for (lambda ()
                          (exists (lambda (l) (string-contains-ci? l "dropped"))
                                  (transcript w))))
              (string=? (window-title w) "REPL — /smoke-vat (dropped)")))
  (close-window! w)
  (focus-window! r))

;; Environments: the tree, what the one selected is, and what can be done
;; with it, by clicks and keys.
(let* ([w (envs)] [v (window-ref w 'state)] [ui (envs-view-ui v)])
  (define (live? id) (let ([b (ui-find ui id)]) (and b (ui-region-on b) #t)))
  (define (sheet-button! i) (click-ui! w (list 'envs-sheet i)))
  (steps 2)
  (check "Environments shows the tree, the world first and selected, \
          /worklets too; the world forks and takes a REPL, not Share or \
          Drop"
         (and (eq? (envs-view-selected v) (env-root))
              (ui-find ui '(tree row 0)) (ui-find ui '(tree row 1))
              (live? '(envs fork)) (live? '(envs repl))
              (not (live? '(envs share))) (not (live? '(envs drop)))))
  (click-ui! w '(envs fork))
  (check "Fork… opens a sheet of the kinds, its name focused"
         (and (eq? (envs-view-sheet v) 'fork)
              (equal? (ui-focused ui) '(envs-sheet name))
              (live? '(envs-sheet kind private))))
  (click-ui! w '(envs-sheet kind sandbox))
  (click-ui! w '(envs-sheet name))
  (type! "smoke-box")
  (click-ui! w (list '(envs-sheet shares) 'field))
  (type! "now-m")
  (steps 2)
  (check "Share suggests the names the environment holds"
         (ui-find ui (list (list '(envs-sheet shares) 'field) 'suggestion 0)))
  (press! 'down)
  (press! 'return)
  (steps 2)
  (type! "now-ms as clock")
  (press! 'return)
  (steps 2)
  (check "a pick, and a share typed, become chips"
         (equal? (envs-view-shares v) '("now-ms" "now-ms as clock")))
  (check "Open a REPL in it starts off" (not (envs-view-repl? v)))
  (sheet-button! 1)
  (let ([c (env-find "/smoke-box")])
    (check "Fork makes a child of the kind, named, shared what it was \
            given, and selects it; no REPL opens unasked"
           (and c (eq? (env-kind c) 'sandbox) (not (envs-view-sheet v))
                (eq? (focused-window) w)
                (eq? (envs-view-selected v) c)
                (equal? (map car (env-shared-names c)) '(clock fork now-ms))
                (env-eval c '(eq? clock now-ms))))
    (type! "f")
    (steps 2)
    (check "F forks too; a sandbox's sheet offers sandboxes and threads \
            only"
           (and (eq? (envs-view-sheet v) 'fork)
                (live? '(envs-sheet kind thread))
                (not (live? '(envs-sheet kind private)))))
    (type! "a/b")
    (press! 'return)
    (steps 2)
    (check "a refused fork says why, and the sheet stays"
           (and (eq? (envs-view-sheet v) 'fork)
                (string-contains-ci? (envs-view-error v) "slash")))
    (press! 'escape)
    (steps 2)
    (click-ui! w '(envs repl))
    (check "REPL opens a REPL in the one selected"
           (let ([f (focused-window)])
             (and (repl? (window-ref f 'state #f))
                  (eq? (repl-env (repl-of f)) c))))
    (close-window! (focused-window))
    (focus-window! w)
    (steps 2)
    (type! "f")
    (steps 2)
    (click-ui! w '(envs-sheet repl))
    (sheet-button! 1)
    (let ([child (envs-view-selected v)])
      (check "ticked, Open a REPL in it opens one in the child"
             (let ([f (focused-window)])
               (and (eq? (env-parent child) c)
                    (repl? (window-ref f 'state #f))
                    (eq? (repl-env (repl-of f)) child)))))
    (close-window! (focused-window))
    (focus-window! w)
    (steps 2)
    (type! "f")
    (steps 2)
    (check "and it is off again when the sheet opens next"
           (not (envs-view-repl? v)))
    (press! 'escape)
    (steps 2)
    (click-ui! w '((envs parent) 0))
    (check "the Parent chip goes to the parent" (eq? (envs-view-selected v) c))
    (click-ui! w '(envs drop))
    (sheet-button! 1)
    (check "Drop… asks first, then drops it; the world is selected again"
           (and (env-dropped? c) (eq? (envs-view-selected v) (env-root)))))
  (let ([lab (env-fork (env-root) 'world 'name 'smoke-lab)])
    (eval '(define smoke-sync-new 1) *world-env*)
    (envs-select! v lab)
    (invalidate! w)   ; selected from here, not by input
    (steps 2)
    (check "a world namespace shows the names the world gained since it last \
            synced, and Sync shares them"
           (and (memq 'smoke-sync-new (env-unsynced lab))
                (live? '(envs sync))
                (begin (click-ui! w '(envs sync))
                       (and (null? (env-unsynced lab))
                            (assq 'smoke-sync-new (env-shared-names lab))
                            (not (live? '(envs sync)))))))
    (envs-select! v (env-root))
    (vat-drop-env! lab)
    (steps 2))
  ;; Share…: the share dialog, with Environments waiting on it
  (eval '(define smoke-share-a 1) *world-env*)
  (eval '(define smoke-share-n 1) *world-env*)
  (eval '(define (smoke-share-n-set! v) (set! smoke-share-n v)) *world-env*)
  (let ([box (env-fork (env-root) 'pure 'name 'smoke-share)]
        [check-of (lambda (i) (list '(envs-picker names) 'check i))])
    (define (picker) (window-ref (focused-window) 'state))
    (envs-select! v box)
    (invalidate! w)
    (steps 2)
    (click-ui! w '(envs share))
    (let* ([pw (focused-window)] [p (picker)])
      (type! "smoke-share")
      (press! 'escape)   ; the filter lets go of the keyboard
      (steps 2)
      (check "Share… opens the share dialog over Environments, which waits \
              on it: the parent's names, filtered as typed"
             (and (envs-picker? p) (eq? (window-modal-child w) pw)
                  (equal? (envs-picker-shown p)
                          '(smoke-share-a smoke-share-n smoke-share-n-set!))))
      (click-ui! pw (check-of 0))
      (click-ui! pw (check-of 1))
      (click-ui! pw '(envs-picker via))
      (type! "smoke-share-n-set!")
      (steps 2)
      (check "checked, a name is to be shared, the last checked chosen, its \
              options under the list"
             (equal? (envs-picker-picked p)
                     '((smoke-share-a "" "")
                       (smoke-share-n "" "smoke-share-n-set!"))))
      (click-ui! pw '(envs-picker done))
      (env-eval box '(set! smoke-share-n 5))
      (check "Share shares them, the setter's through it, and closes"
             (and (not (memq pw (windows)))
                  (equal? (map car (env-shared-names box))
                          '(smoke-share-a smoke-share-n))
                  (= (eval 'smoke-share-n *world-env*) 5))))
    (click-ui! w '(envs share))
    (let ([pw (focused-window)])
      (type! "smoke-share-a")
      (press! 'escape)
      (steps 2)
      (check "a name shared already is checked, and takes no press"
             (and (equal? (envs-picker-shown (picker)) '(smoke-share-a))
                  (not (ui-find (window-ref pw 'ui) (check-of 0)))))
      (press! 'escape)
      (steps 2))
    (envs-select! v (env-root))   ; a pure namespace forks nothing
    (invalidate! w)
    (steps 2)
    (type! "f")
    (steps 2)
    (click-ui! w '(envs-sheet choose))
    (let ([pw (focused-window)])
      (type! "smoke-share-n-")
      (press! 'escape)
      (steps 2)
      (click-ui! pw (check-of 0))
      (click-ui! pw '(envs-picker done))
      (check "the Fork sheet's Choose… picks its shares in the same dialog"
             (and (not (memq pw (windows)))
                  (equal? (envs-view-shares v) '("smoke-share-n-set!")))))
    (press! 'escape)
    (steps 2)
    (envs-select! v (env-root))
    (vat-drop-env! box)
    (invalidate! w)
    (steps 2))
  ;; Load…: the desktop's file dialog, with Environments waiting on it
  (let* ([dir (string-append out-dir "/smoke-load")]
         [sub (string-append dir "/sub")]
         [file (string-append dir "/smoke-load.ss")]
         [lab (env-fork (env-root) 'pure 'name 'smoke-load)])
    (unless (file-exists? dir) (mkdir dir))
    (unless (file-exists? sub) (mkdir sub))
    (call-with-output-file file
      (lambda (p) (write '(define smoke-loaded 7) p)) 'replace)
    (call-with-output-file (string-append dir "/notes.txt")
      (lambda (p) (display "notes" p)) 'replace)
    (envs-select! v lab)
    (envs-view-folder-set! v dir)   ; where Load… last picked from
    (invalidate! w)
    (steps 2)
    (click-ui! w '(envs load))
    (let* ([fd (focused-window)] [d (window-ref fd 'state)]
           [names (lambda () (map file-dialog-entry-name
                                  (or (file-dialog-shown d) '())))]
           [row (lambda (i) (list '(file-dialog list) 'row i))]
           ;; the dialog keeps its folders' whole paths
           [dir (file-dialog-resolve (current-directory) dir)]
           [sub (file-dialog-resolve (current-directory) sub)])
      (check "Load… opens the file dialog over Environments, which waits on \
              it, where the last file was picked: folders, then Scheme files"
             (and (file-dialog? d)
                  (equal? (window-title fd) "Load into /smoke-load")
                  (eq? (window-modal-child w) fd)
                  (ui-find ui '(ui modal-child))
                  (equal? (names) '("sub" "smoke-load.ss"))))
      (focus-window! w)
      (let ([kept (and (eq? (focused-window) fd) (eq? (car (windows)) fd))])
        (let-values ([(x y) (ui-point w '(envs fork) 0.5)])
          (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                   `(mouse-up ,x ,y left))
          (steps 2))
        (let ([pressed (and (eq? (focused-window) fd) (eq? (car (windows)) fd)
                            (not (envs-view-sheet v)))]
              [tx (+ (window-x w) (quotient (window-w w) 2))]
              [ty (+ (window-y w) 6)])
          ;; a press on its title bar, as if to move it
          (inject! `(mouse-move ,tx ,ty) `(mouse-down ,tx ,ty left 1)
                   `(mouse-up ,tx ,ty left))
          (steps 2)
          (check "the dialog stays above Environments, with its keyboard: \
                  focused from code, pressed in its content, which does \
                  nothing there, and on its title bar"
                 (and kept pressed (eq? (window-region w tx ty) 'title)
                      (eq? (focused-window) fd)
                      (eq? (car (windows)) fd)
                      (eq? (cadr (windows)) w)))))
      ;; its rows, keys and paths are tested in tests/units/file-dialog.ss
      (click-ui! fd (row 1))
      (click-ui! fd '(file-dialog pick))
      (check "Load picks it: the dialog closes, Environments goes on, and \
              the file is loaded into the environment"
             (and (not (memq fd (windows))) (not (window-modal-child w))
                  (wait-for (lambda ()
                              (guard (c [#t #f])
                                (eqv? 7 (env-eval lab 'smoke-loaded))))))))
    (focus-window! w)
    (click-ui! w '(envs load))
    (let ([fd (focused-window)])
      (press! 'escape)
      (steps 2)
      (check "Escape closes it, loading nothing"
             (and (not (memq fd (windows))) (not (window-modal-child w)))))
    (envs-select! v (env-root))
    (vat-drop-env! lab)
    (invalidate! w)
    (steps 2))
  ;; the line between the tree and the inspector is a split
  ;; (tests/units/ui-split.ss)
  (click-ui! w '(tree row 1))
  (let ([n (vat-pool-size)])
    (click-ui! w '((envs pool) up))
    (check "/worklets' Pool sets how many threads the pool has"
           (= (vat-pool-size) (+ n 1)))
    (click-ui! w '((envs pool) down)))
  (close-window! w)
  (focus-window! r))

;; A crashing app only crashes its own window.
(define bad (open-window "Broken" 'size '(300 . 120) 'pos '(80 . 480)
                         'draw (lambda (win w h) (vector-ref (vector) 3))))
(steps 2)
(check "crashing draw marks the window" (window-error bad))

;; A runaway handler is stopped by the watchdog.
(define stuck (open-window "Stuck" 'size '(300 . 80) 'pos '(420 . 560)
                           'key (lambda (win k m) (let loop () (loop)))))
(press! #\x)
(steps 2)
(check "watchdog stops runaway handler" (window-error stuck))
(close-window! stuck)

;; Window management through synthetic mouse events.
(define c (find-window 'clock))
(let ([x0 (window-x c)])
  (inject! `(mouse-down ,(+ (window-x c) 120) ,(+ (window-y c) 10) left 1)
           `(mouse-move ,(+ (window-x c) 20) ,(+ (window-y c) 30))
           `(mouse-up ,(+ (window-x c) 20) ,(+ (window-y c) 30) left))
  (steps 2)
  (check "dragging the title bar moves a window" (= (window-x c) (- x0 100))))

(let ([w0 (window-w c)])
  (inject! `(mouse-down ,(+ (window-x c) (window-w c) -2)
                        ,(+ (window-y c) (window-h c) -2) left 1)
           `(mouse-move ,(+ (window-x c) (window-w c) 38)
                        ,(+ (window-y c) (window-h c) 18))
           `(mouse-up ,(+ (window-x c) (window-w c) 38)
                      ,(+ (window-y c) (window-h c) 18) left))
  (steps 2)
  (check "dragging the corner resizes" (= (window-w c) (+ w0 40))))

(png-write-screen (string-append out-dir "/desktop.png"))

;; The launcher by F1, the desktop's menu, F11 and the icon are tested in
;; tests/units/desktop.ss.
(close-window! c)

;; Theme changes are live.
(set-theme! 'accent #xff9e64)
(sketch)
(monitor)
(tile-windows!)
(steps 3)
(png-write-screen (string-append out-dir "/tiled.png"))
(reset-theme!)

;; Window styles: the frame, its buttons and their actions come from the style.
;; The insets that Genera's rule gives with today's fonts: its 2-pixel
;; border and 4-pixel margin on each side, and at the bottom its label
;; strip, the label font's line height plus 2, at least 14 ((schevana
;; styles genera)).
(define (test-genera-insets)
  (with-style 'genera
    (lambda ()
      (let ([label (font-line-height (theme 'genera-label-font))])
        (list 6 6 6 (+ 6 (max 14 (exact (round (+ label 2))))))))))

;; Medley's insets: a border of 4, and at the top the title strip plus the
;; border's 2 pixels of ink. The strip is the largest of Medley's 15
;; pixels, the title font's line under the ink, and the title bar's
;; setting less 15 ((schevana styles interlisp)).
(define (test-interlisp-insets)
  (with-style 'interlisp
    (lambda ()
      (let ([line (exact (round (font-line-height 'ui-small)))])
        (list 4 (+ 2 (max 15 (- (title-height) 15) (+ 2 line))) 4 4)))))

(define (click-button! win kind)
  (let ([b (assq kind (frame-regions win))])
    (unless b (errorf 'click-button! "~s has no ~s button" win kind))
    (let ([x (+ (window-x win) (list-ref b 1) (quotient (list-ref b 3) 2))]
          [y (+ (window-y win) (list-ref b 2) (quotient (list-ref b 4) 2))])
      (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
               `(mouse-up ,x ,y left))
      (steps 2))))

(define (style-scene! style)
  (for-each close-window! (windows))
  (set-theme! 'window-style style)
  (repl)
  (clock)
  (move-window! (find-window 'clock) 900 60)
  (life)
  (move-window! (find-window 'life) 560 330)
  (focus-window! (find-window 'repl))
  (steps 2)
  (png-write-screen
   (string-append out-dir "/style-" (symbol->string style) ".png"))
  (for-all (lambda (w) (not (window-error w))) (windows)))

(check "mac style draws" (style-scene! 'mac))
(check "windows style draws" (style-scene! 'windows))
(let ([w (open-window "Alpha" 'size '(400 . 200) 'pos '(100 . 100))])
  (let-values ([(cx cy cw ch) (content-rect w)])
    (check "windows frame is just a title bar"
           (and (= cx 100) (= cw 400) (= (window-w w) 400))))
  (click-button! w 'maximize)
  (check "windows maximize button" (maximized? w))
  (click-button! w 'minimize)
  (check "windows minimize button" (not (visible? w)))
  (focus-window! w)
  (click-button! w 'close)
  (check "windows close button" (not (memq w (windows)))))

(check "interlisp style draws" (style-scene! 'interlisp))
(let ([w (open-window "Gamma" 'size '(300 . 150) 'pos '(200 . 140))])
  (let-values ([(l t r b) (frame-insets w)])
    (check "interlisp has Medley's border of 4 (2 of ink, 2 of paper), a \
            title strip of Medley's 15 pixels or the title font's line, and \
            no buttons"
           (and (equal? (list l t r b) (test-interlisp-insets))
                (null? (frame-regions w)))))
  (inject! '(mouse-move 300 147) '(mouse-down 300 147 right 1)
           '(mouse-up 300 147 right))
  (steps 2)
  (check "so the right-button menu on its title closes it"
         (and (menu-open?)
              (find (lambda (e)
                      (and (pair? e)
                           (string=? (menu-label-text (car e)) "Close")))
                    (menu-entries *menu*))))
  (close-menu!))

(check "genera style draws" (style-scene! 'genera))
(let ([w (open-window "Delta" 'size '(300 . 150) 'pos '(200 . 140))])
  (let-values ([(l t r b) (frame-insets w)])
    (check "genera has a 2-pixel border, a 4-pixel margin and the label at \
            the bottom"
           (equal? (list l t r b) (test-genera-insets))))
  (let ([x 260] [y (+ 140 (window-h w) -10)])
    (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
             `(mouse-move ,(+ x 40) ,(- y 30))
             `(mouse-up ,(+ x 40) ,(- y 30) left))
    (steps 2))
  (check "dragging the label at the bottom moves the window"
         (and (= (window-x w) 240) (= (window-y w) 110)))
  (let* ([w0 (window-w w)]
         [x (+ (window-x w) w0 -3)]
         [y (+ (window-y w) (window-h w) -3)])
    (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
             `(mouse-move ,(+ x 20) ,y) `(mouse-up ,(+ x 20) ,y left))
    (steps 2)
    (check "and its corner still resizes it" (= (window-w w) (+ w0 20)))))
(set-palette! 'genera)
(style-scene! 'genera)
(png-write-screen (string-append out-dir "/style-genera-palette.png"))
(check "genera's palette keeps its own panel text"
       (= (theme 'panel-text) #xffffff))
(reset-theme!)

(check "cadr style draws" (style-scene! 'cadr))
(let ([w (open-window "Epsilon" 'size '(300 . 150) 'pos '(200 . 140))])
  (let-values ([(l t r b) (frame-insets w)])
    (check "the CADR is Genera's frame with a 1-pixel border and margin, \
            its who line at the bottom and no top bar"
           (and (= l 2) (= t 2) (= r 2) (> b 16) (= (topbar-height) 0)
                (> (taskbar-height) 0))))
  (close-window! w))
(reset-theme!)

(check "open-look style draws" (style-scene! 'open-look))
(let ([w (open-window "Zeta" 'size '(300 . 150) 'pos '(200 . 140))])
  (let-values ([(l t r b) (frame-insets w)])
    (check "open-look is olwm's frame at 12 point: arms of 5, the header \
            and an arm above and below it, 25"
           (and (= l 5) (= r 5) (= b 5) (= t 25))))
  (let* ([w0 (window-w w)]
         [drag (lambda (x y)
                 (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                          `(mouse-move ,(+ x 20) ,y)
                          `(mouse-up ,(+ x 20) ,y left))
                 (steps 2))])
    (drag (+ (window-x w) w0 -3) (+ (window-y w) 70))
    (let ([side (window-w w)])
      (drag (+ (window-x w) w0 -3) (+ (window-y w) (window-h w) -3))
      (check "open-look's sides do not resize it, its corners do"
             (and (= side w0) (= (window-w w) (+ w0 20))))))
  (let ([p (open-window "Eta" 'size '(200 . 80) 'pos '(300 . 200)
                        'above w)])
    (click-button! p 'close)
    (check "a pop-up's pushpin pulled out dismisses it, not its owner"
           (and (not (memq p (windows))) (memq w (windows)) #t)))
  (click-button! w 'minimize)
  (check "and the window button closes it to the taskbar" (not (visible? w)))
  (close-window! w))
(reset-theme!)

;; Depth and size gadgets, which no built-in style uses now, still work in
;; a style defined at run time.
(define-style gadgets "Gadgets"
  'frame-insets (lambda (win) (values 4 20 4 12))
  'frame-regions (lambda (win)
             (let ([w (window-w win)] [h (window-h win)])
               (list (list 'maximize (- w 48) 0 24 20)
                     (list 'depth (- w 24) 0 24 20)
                     (list 'resize-br (- w 16) (- h 12) 16 12)))))
(for-each close-window! (windows))
(set-theme! 'window-style 'gadgets)
(let* ([a (open-window "One" 'size '(300 . 150) 'pos '(80 . 80))]
       [b (open-window "Two" 'size '(300 . 150) 'pos '(200 . 140))])
  (click-button! b 'depth)
  (check "depth gadget sends the front window back"
         (and (eq? (car (windows)) a) (eq? (car (last-pair (windows))) b)))
  (click-button! b 'depth)
  (check "and brings it to the front again" (eq? (car (windows)) b))
  (let ([w0 (window-w b)])
    (let ([g (assq 'resize-br (frame-regions b))])
      (let ([x (+ (window-x b) (list-ref g 1) 5)]
            [y (+ (window-y b) (list-ref g 2) 5)])
        (inject! `(mouse-down ,x ,y left 1) `(mouse-move ,(+ x 30) ,(+ y 10))
                 `(mouse-up ,(+ x 30) ,(+ y 10) left))
        (steps 2)))
    (check "size gadget resizes" (= (window-w b) (+ w0 30))))
  (click-button! b 'maximize)
  (check "zoom gadget maximizes" (maximized? b))
  (let ([m (open-window "Mac island" 'size '(200 . 100) 'window-style 'mac)])
    (check "a window can override the style"
           (and (= (window-w m) 200) (assq 'minimize (frame-regions m))))))
(set! *styles*
  (remp (lambda (s) (eq? (style-name s) 'gadgets)) *styles*))
(set-theme! 'window-style 'mac)

;; A style, palette, wallpaper or app defined again keeps its place and
;; takes the new definition.
(let ([styles0 *styles*] [palettes0 *palettes*] [papers *wallpapers*]
      [apps0 *apps*])
  (define-style genera "Genera, again")
  (define-palette nord "Nord, again")
  (define-wallpaper flat "Flat, again" (lambda (x y w h top bottom) (void)))
  (register-app! 'clock "Clock, again" (lambda () #f))
  (let ([named (lambda (registry name-of title-of)
                 (map (lambda (e) (cons (name-of e) (title-of e))) registry))])
    (check "a style, palette, wallpaper or app defined again keeps its place"
           (and (equal? (styles) (map style-name styles0))
                (equal? (palettes) (map car palettes0))
                (equal? (wallpapers) (map car papers))
                (equal? (apps) (map app-name apps0))
                (member '(genera . "Genera, again")
                        (named *styles* style-name
                               style-title))
                (equal? (theme-palette-preview 'nord)
                        (theme-palette-preview 'tokyo-night))
                (equal? (palette-title 'nord) "Nord, again")
                (member '(flat . "Flat, again") (named *wallpapers* car cadr))
                (member '(clock . "Clock, again")
                        (named *apps* app-name app-title)))))
  (set! *styles* styles0)
  (set! *palettes* palettes0)
  (set! *wallpapers* papers)
  (set! *apps* apps0)
  (wm-chrome-changed!))

;; a palette is a change to the chosen style; the wallpaper is the style's
;; own
(set-theme! 'window-style 'interlisp)
(set-palette! 'interlisp)
(style-scene! 'interlisp)
(png-write-screen (string-append out-dir "/style-interlisp-palette.png"))
(check "the interlisp style shades the desktop"
       (eq? (theme 'wallpaper) 'shade))
(set-palette! 'nord)
(check "in other palettes too, and Mac in its palette keeps the gradient"
       (and (eq? (theme 'wallpaper) 'shade)
            (begin (set-theme! 'window-style 'mac)
                   (set-palette! 'interlisp)
                   (eq? (theme 'wallpaper) 'gradient))))
;; A saved theme that names a style and a palette no longer defined
;; (Amiga, Workbench) still loads.
(reset-theme!)
(call-with-output-file *theme-file-path*
  (lambda (p)
    (write '((window-style . amiga) (preset . workbench) (corner-radius . 4))
           p))
  'replace)
(theme-file-load!)
(check
 "a saved theme naming a removed style or palette falls back to the defaults"
 (and (eq? (theme 'window-style) 'mac) (eq? (theme 'palette) 'tokyo-night)
      (= 4 (theme 'corner-radius))))
(delete-file *theme-file-path*)
(reset-theme!)
(for-each close-window! (windows))

;; Settings: every control is a theme key; changes apply live and persist.
;; Save as new style writes into the output folder, never ~/.schevana.d.
(for-each close-window! (windows))
(set! *settings-style-directory* (string-append out-dir "/styles"))
(let ([f (string-append *settings-style-directory* "/my-windows.ss")])
  (when (file-exists? f) (delete-file f)))
;; A style with its own palette and fonts, and few options, of which the
;; text size is not one.
(define-style test-serif "Test serif"
  'palette 'gruvbox 'ui-font "serif" 'wallpaper 'flat
  'options '(palette accent wallpaper corner-radius))
(define s (settings))
(define (settings-ui) (window-ref s 'ui))
(steps 2)
;; The pane's last rows sit below the style cards, out of view: scroll the
;; pane to its end.
(define (scroll-settings-down!)
  (let-values ([(cx cy cw ch) (content-rect s)])
    (apply inject! `(mouse-move ,(+ cx cw -20) ,(+ cy 100))
           (make-list 60 '(wheel 0 -1)))
    (steps 2)))
(check "settings opens" (and s (not (window-error s))))
(check "settings is single-instance" (eq? s (settings)))
;; An old, flat theme file shows as its style, with its choices as your
;; changes.
(call-with-output-file *theme-file-path*
  (lambda (p) (write '((window-style . genera) (accent . #x3366cc)) p))
  'replace)
(theme-file-load!)
(steps 2)
(check "an old theme file shows in Settings as its style and your changes"
       (and (eq? (current-style) 'genera) (= (theme 'accent) #x3366cc)
            (ui-find (settings-ui) '(revert accent))
            (not (ui-find (settings-ui) '(revert corner-radius)))))
(delete-file *theme-file-path*)
(reset-theme!)
(set-style! 'mac)
(steps 2)
(png-write-screen (string-append out-dir "/settings-theme.png"))
(click-ui! s '(style test-serif))
(check "a style card switches the style, its palette, wallpaper and fonts \
        at once"
       (and (eq? (current-style) 'test-serif) (eq? (theme 'palette) 'gruvbox)
            (eq? (theme 'wallpaper) 'flat)
            (equal? (font-family (get-font 'ui)) "serif")))
;; A style's own slider keeps to its range: Genera's border is 1 to 4.
(click-ui! s '(style genera))
(scroll-to-ui! s '(option genera-border))
(drag-ui! s '(option genera-border) 1)
(check "a style's own slider stops at its most"
       (= (theme 'genera-border) 4))
(reset-style!)
;; The keyboard reaches the cards, the swatches and the sidebar's tabs.
(define (tab-to! id)
  (let loop ([n 0])
    (cond [(equal? (ui-focused (settings-ui)) id) #t]
          [(= n 400) #f]
          [else (press! 'tab) (steps 1) (loop (+ n 1))])))
(click-ui! s '(style mac))
(let* ([reached (map tab-to! '((palette nord) (swatch orange) (tab fonts)
                               (style windows)))]
       [chosen (begin (press! #\space) (steps 2) (current-style))]
       [tabbed (begin (tab-to! '(tab fonts)) (press! 'return) (steps 2)
                      (settings-st-tab (window-ref s 'state)))])
  (check "Tab reaches the palette cards, the swatches, the sidebar's tabs \
          and the style cards; space chooses a card, Return a tab"
         (and (for-all values reached) (eq? chosen 'windows)
              (eq? tabbed 'fonts))))
(click-ui! s '(tab theme))
(click-ui! s '(style mac))
(click-ui! s '(palette nord))
(check "clicking a palette applies it, to this style"
       (and (= (theme 'accent) #x88c0d0) (eq? (theme 'palette) 'nord)
            (equal? (style-changes-of 'mac) '(palette nord))))
(click-ui! s '(swatch orange))
(check "accent swatch sets the accent" (= (theme 'accent) #xd08770))
(scroll-to-ui! s '(option corner-radius))
(drag-ui! s '(option corner-radius) 0)
(check "a slider sets a size" (= 0 (theme 'corner-radius)))
(click-ui! s '(style windows))
(let ([away (list (theme 'corner-radius) (theme 'palette))])
  (click-ui! s '(style mac))
  (check "a change is remembered for its style across switches"
         (and (equal? away (list (theme-default 'corner-radius)
                                 (theme-default 'palette)))
              (= 0 (theme 'corner-radius)) (eq? (theme 'palette) 'nord)
              (ui-find (settings-ui) '(revert corner-radius)))))
(click-ui! s '(revert corner-radius))
(check "↺ drops one change" (= (theme 'corner-radius) 9))
(scroll-to-ui! s '(option corner-radius))
(drag-ui! s '(option corner-radius) 0)
(png-write-screen (string-append out-dir "/settings-changed.png"))
;; The text size is on the Fonts tab. Pinned, it holds in every style that
;; honors it, and test-serif doesn't.
(click-ui! s '(tab fonts))
(scroll-to-ui! s '(option ui-font-size))
(drag-ui! s '(option ui-font-size) 0.2)
(let ([size (theme 'ui-font-size)])
  (click-ui! s '(pin ui-font-size))
  (check "a pin makes the change an Override"
         (and (= (theme 'ui-font-size) size)
              (equal? (theme-overrides) (list 'ui-font-size size))
              (not (plist-has? (style-changes-of 'mac) 'ui-font-size))))
  (set-style! 'windows)
  (steps 2)
  (let ([windows (theme 'ui-font-size)])
    (set-style! 'test-serif)
    (steps 2)
    (check "a pin holds in every style that honors it, and is passed by \
            where the style sets it"
           (and (= windows size) (= (theme 'ui-font-size) 13)
                (eq? (car (theme-source 'ui-font-size)) 'built-in)
                (not (ui-find (settings-ui) '(option ui-font-size)))
                (not (ui-find (settings-ui) '(pin ui-font-size)))))
    (png-write-screen (string-append out-dir "/settings-fonts-unused.png"))
    (set-style! 'mac)
    (steps 2)
    (click-ui! s '(pin ui-font-size))
    (check "unpinned, the Override is this style's change again"
           (and (null? (theme-overrides))
                (= size (plist-ref (style-changes-of 'mac) 'ui-font-size #f))))
    (set-theme! 'ui-font-size 13)))
(click-ui! s '(tab colors))
(click-ui! s '(color accent))
(click-ui! s 'hex)
(type! "e06c75")
(press! 'return)
(steps 2)
(check "typing a hex color sets it" (= (theme 'accent) #xe06c75))
(check "accent edits update derived keys"
       (= (theme 'window-border-focus) (mix (theme 'bg-3) #xe06c75 0.45)))
(drag-ui! s 'lightness 0.25)
(check "lightness slider darkens it"
       (let-values ([(h sat l) (color->hsl (theme 'accent))])
         (< (abs (- l 0.25)) 0.02)))
(png-write-screen (string-append out-dir "/settings-colors.png"))
;; Reset, after a dialog listing the changes; Save as new style.
(click-ui! s '(tab theme))
(click-ui! s '(style windows))
(set-theme! 'corner-radius 3)
(set-theme! 'bell 'screen)
(steps 2)
(click-ui! s 'reset-style)
(png-write-screen (string-append out-dir "/settings-reset.png"))
(let ([shown (and (ui-find (settings-ui) '(reset-dialog 1)) #t)])
  (click-ui! s '(reset-dialog 1))
  (check "Reset asks first, then forgets the style's changes"
         (and shown (null? (style-changes-of 'windows))
              (= (theme 'corner-radius) 9) (eq? (theme 'bell) 'none))))
(set-theme! 'corner-radius 3)
(set-theme! 'accent #x112233)
(steps 2)
(click-ui! s 'save-style)
(press! 'backspace)   ; the title is selected: typing replaces it
(type! "My Windows")
(png-write-screen (string-append out-dir "/settings-save.png"))
(press! 'return)
(steps 2)
(let ([file (string-append out-dir "/styles/my-windows.ss")])
  (check "Save as new style writes a style file that loads, its parent the \
          style and its settings your changes, and chooses it"
         (and (file-exists? file)
              (equal? (call-with-input-file file read)
                      '(define-style my-windows "My Windows"
                         'parent 'windows 'accent #x112233
                         'corner-radius 3))
              (eq? (current-style) 'my-windows)
              (null? (style-changes-of 'windows))
              (= (theme 'accent) #x112233)
              (equal? (theme-source 'corner-radius) '(style my-windows 3))
              (ui-find (settings-ui) '(style my-windows)))))
(set-style! 'mac)
(set! *styles* (remp (lambda (s) (memq (style-name s) '(my-windows test-serif)))
                     *styles*))
(steps 2)
(click-ui! s '(tab theme))
(scroll-settings-down!)
;; a column of pixels down the middle of the pane
(define (settings-column)
  (let-values ([(cx cy cw ch) (content-rect s)])
    (let ([px (exact (floor (* *scale* (+ cx (quotient cw 2)))))])
      (map (lambda (y) (screen-pixel px (exact (floor (* *scale* (+ cy y))))))
           (iota ch)))))
(let ([at-end (settings-column)])
  (inject! '(wheel 0 -1))
  (steps 1)
  (check "the wheel past the pane's end shows no frame past it"
         (equal? at-end (settings-column))))
(scroll-to-ui! s '(option title-height))
(drag-ui! s '(option title-height) 1)
(check "title bar height follows" (= 44 (theme 'title-height)))
(png-write-screen (string-append out-dir "/settings-behavior.png"))
(click-ui! s '(tab fonts))
(click-ui! s '((option ui-font) "serif"))
(scroll-to-ui! s '(option mono-font-size))
(drag-ui! s '(option mono-font-size) 1)
(check "font settings rebuild fonts"
       (and (equal? (font-family (get-font 'ui)) "serif")
            (= 36 (font-size (get-font 'mono)))))
(scroll-to-ui! s '(option ui-font-size))
(drag-ui! s '(option ui-font-size) 1)
(check "at the biggest fonts the sidebar button fits its label"
       (let ([r (ui-find (window-ref s 'ui) 'reset-all)])
         (and (= 36 (theme 'ui-font-size))
              (<= (+ 12 (text-width "Reset to defaults" 'ui))
                  (ui-region-w r)))))
(check "title bar, top bar and taskbar grow to fit the biggest fonts"
       (and (> (title-height) (theme 'title-height))
            (> (topbar-height) (theme 'topbar-height))
            (> (taskbar-height) (theme 'taskbar-height))
            (>= (title-height) (font-line-height 'title))))
(let-values ([(cx cy cw ch) (content-rect s)])
  (inject! `(mouse-move ,(+ cx cw -20) ,(+ cy 100)) '(wheel 0 -1) '(wheel 0 -1))
  (steps 2)
  (check "the settings pane scrolls when its content doesn't fit"
         (and (> (settings-st-pane-scroll (window-ref s 'state)) 0)
              (ui-find (window-ref s 'ui) 'pane-scrollbar))))
(png-write-screen (string-append out-dir "/settings-fonts.png"))
(click-ui! s '(tab theme))
(scroll-to-ui! s '(option title-height))
(drag-ui! s '(option title-height) 0.5)
(check "chrome height sliders start at what the font needs"
       (and (> (theme 'title-height) (theme 'title-height-min))
            (= (theme 'title-height) (title-height))))
(click-ui! s '(tab fonts))
;; 80 columns of 36 px would not fit this screen
(set-theme! 'mono-font-size 22)
(let ([r (repl)])
  (steps 1)
  (check "a new REPL opens 80 columns wide at any code size"
         (= 80 (repl-cols (window-ref r 'state))))
  (close-window! r))
(check "settings never crashed" (not (window-error s)))
(check "changes are saved shortly after"
       (wait-for (lambda () (and (not *theme-file-save-pending*)
                                 (file-exists? *theme-file-path*)))))
(let ([saved-accent (theme 'accent)])
  (reset-theme!)
  (check "reset restores defaults"
         (= (theme 'corner-radius) (theme-default 'corner-radius)))
  (theme-file-load!)
  (check "saved theme loads back"
         (and (= (theme 'accent) saved-accent) (= 0 (theme 'corner-radius))
              (eq? (theme 'palette) 'nord)
              (equal? (theme 'ui-font) "serif"))))
(set-palette! 'paper)
(set-theme! 'title-height 30)
(set-theme! 'mono-font-size 14)
(set-theme! 'ui-font-size 13)
(set-theme! 'ui-font "sans-serif")
(repl)
(clock)
(move-window! (find-window 'clock) 900 300)
(click-ui! s '(tab theme))
(steps 2)
(png-write-screen (string-append out-dir "/paper.png"))
(focus-window! s)   ; the REPL above opened on top of it
(click-ui! s '(tab display))
(click-ui! s '(scale 200))
(check "the scale setting draws the same world twice as big"
       (and (= 200 (theme 'scale)) (= *scale* 2.0)
            (= (screen-w) 1280) (= (canvas-pixel-width) 2560)))
(steps 1)
(png-write-screen (string-append out-dir "/scale-200.png"))
(click-ui! s '(scale 0))
(check "and Auto follows the desktop again"
       (and (= 0 (theme 'scale)) (= *scale* 1.0) (= (canvas-pixel-width) 1280)))
(reset-theme!)
(reset-theme!)
(close-window! s)

;; Tasks: a task manager on the widget kit, driven by real events.
(tasks-reset!)
(define tw (tasks))
(steps 2)
(define tv (window-ref tw 'state))
(define tui (window-ref tw 'ui))
(define (focus-id) (ui-focused tui))
(define (selected) (tasks-view-selected tv))
(define (edit) (ui-state-edit tui))
(define (card-of t) (ui-find tui (list 'card (task-id (find-task t)))))
(define (column-of status)
  (filter (lambda (t) (eq? (task-status t) status)) *tasks*))
(define (next-to t) (cadr (memq (find-task t) *tasks*)))
(define (shot name) (png-write-screen (format "~a/tasks-~a.png" out-dir name)))

;; Size Tasks by its own measures, not by a number that one font's widths
;; decide. Wide (at the screen's left) is the width at which its details
;; sit beside its view (tasks-wide-width); narrow is its least width, at
;; which they never fit.
(define (tasks-wide!)
  (let-values ([(mw mh) (tasks-min-size)])
    (move-window! tw 0 (window-y tw))
    (resize-window! tw (max mw (tasks-wide-width tv)) (max 660 mh))
    (steps 2)))
(define (tasks-narrow!)
  (let-values ([(mw mh) (tasks-min-size)])
    (resize-window! tw mw (max 600 mh))
    (steps 2)))

;; Presses and releases at a point of the window's content.
(define (tasks-click! x y . more)   ; more: button, clicks
  (let-values ([(cx cy cw ch) (content-rect tw)])
    (let ([x (+ cx (round x))] [y (+ cy (round y))]
          [b (if (pair? more) (car more) 'left)]
          [n (if (and (pair? more) (pair? (cdr more))) (cadr more) 1)])
      (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y ,b ,n)
               `(mouse-up ,x ,y ,b))
      (steps 2))))

(define (region-center id)
  (let ([r (test-region tui id)])
    (values (+ (ui-region-x r) (/ (ui-region-w r) 2))
            (+ (ui-region-y r) (/ (ui-region-h r) 2)))))

(check "Tasks opens on the Board with the seed tasks"
       (and (not (window-error tw)) (= (length tasks-seed) (length *tasks*))
            (eq? (tasks-view-mode tv) 'board) (card-of 16)))
(check "Tasks is single-instance" (eq? tw (tasks)))
(shot "board")
(check "a column draws and registers only the cards in view"
       (let ([todo (column-of 'todo)])
         (< 0 (length (filter card-of todo)) (length todo))))

;; n, then typing at once: nothing is lost, and the n itself is not typed.
(type! "n")
(type! "Fix the toolbar")
(steps 2)
(define nt (selected))
(check "n makes a task, selected with its title focused; typed at once, the \
        title is whole"
       (and (= (+ 1 (length tasks-seed)) (length *tasks*)) nt
            (eq? (focus-id) 'title)
            (equal? (task-title nt) "Fix the toolbar")))
(check "and its card, last in a long column, scrolled into view"
       (let ([r (card-of nt)])
         (and r (= (ui-region-h r) (cadddr (ui-region-frame r))))))
(shot "title")

;; Tab to Status, then its menu by keys, and Priority's by mouse: the
;; dropdowns reach the task (the dropdown itself is tested in
;; tests/units/ui-dropdown.ss).
(press! 'tab)
(steps 1)
(check "Tab goes from the title to Status" (equal? (focus-id) 'status))
(press! 'return)
(steps 1)
(shot "dropdown")
(press! 'down)
(press! 'return)
(steps 2)
(click-ui! tw 'priority)
(test-menu-click! "Urgent")
(check "Status by keys and Priority by a click set the task: In progress, \
        at the end of its column, and Urgent"
       (and (eq? (task-status nt) 'doing)
            (eq? nt (car (last-pair (column-of 'doing))))
            (eq? (task-priority nt) 'urgent)))

(click-ui! tw 'assignee)
(type! "Ada")
(press! 'return)
(steps 2)
(check "the assignee is typed, and Return leaves the field"
       (and (equal? (task-assignee nt) "Ada") (not (focus-id))))

;; The due date: a day picked in its calendar becomes the task's (the date
;; field itself is tested in tests/units/ui-date-field.ss).
(click-ui! tw 'due)
(shot "calendar")
(define day20 (let ([d (ui-today)]) (ui-date->day (list (car d) (cadr d) 20))))
(click-ui! tw (list 'due 'day day20))
(check "a day picked in the due date's calendar is the task's due date"
       (equal? (task-due nt) (ui-day->date day20)))
(click-ui! tw 'assignee)
(press! 'tab)
(steps 1)
(check "Tab goes from the assignee to the date" (equal? (focus-id) 'due))
(press! 'escape)

;; Tags: the chip input reaches the task (the chip input itself is tested
;; in tests/units/ui-chip-input.ss).
(click-ui! tw '(tags field))
(type! "perf")
(press! 'return)
(steps 2)
(let ([added (task-tags nt)])
  (click-ui! tw '(tags remove 0))
  (check "a tag typed and Return is the task's, and its chip's × removes it"
         (and (equal? added '("perf")) (null? (task-tags nt)))))
(set-task! nt 'tags '("render"))
(steps 2)   ; the chip moves the field
(click-ui! tw '(tags field))
(type! "re")
(steps 2)
(let ([shown (filter-map (lambda (r)
                           (let ([id (ui-region-id r)])
                             (and (pair? id) (pair? (cdr id))
                                  (eq? (cadr id) 'suggestion) id)))
                         (ui-state-regions tui))])
  (press! 'down)
  (press! 'return)
  (steps 2)
  (check "the tag field suggests the tags the other tasks have, not its \
          own; Down and Return add one"
         (and (pair? shown)
              (= (length (task-tags nt)) 2)
              (equal? (car (task-tags nt)) "render")
              (member (cadr (task-tags nt)) (tasks-tags *tasks*))
              (string=? (tasks-view-tag-draft tv) ""))))
(press! 'escape)
(set-task! nt 'tags '())

(click-ui! tw 'description)
(type! "line one")
(press! 'return)
(type! "line two")
(steps 2)
(check "the description takes a newline"
       (equal? (task-description nt) "line one\nline two"))
(press! 'up)
(steps 1)
(check "Up moves the caret to the first row" (< (edit-caret (edit)) 9))

(click-ui! tw 'new-item)
(type! "one")
(press! 'return)
(type! "two")
(press! 'return)
(steps 2)
(click-ui! tw '(item 0))
(check "checklist items are added, and checked"
       (equal? (task-checklist nt) '(("one" . #t) ("two" . #f))))
(click-ui! tw '(drop 1))
(check "and removed" (equal? (task-checklist nt) '(("one" . #t))))
(shot "details")

;; Drag and drop. The new task scrolled To do to its end, so scroll it back
;; to the top.
(define (column-home! status)
  (let-values ([(x y) (region-center (list 'column status))]
               [(cx cy cw ch) (content-rect tw)])
    (apply inject! `(mouse-move ,(+ cx (round x)) ,(+ cy (round y)))
           (make-list 40 '(wheel 0 1)))
    (steps 2)))
(column-home! 'todo)
(define (column-top status) (ui-region-y (ui-find tui (list 'column status))))
(define (column-x status)
  (let ([r (ui-find tui (list 'column status))])
    (+ (ui-region-x r) (/ (ui-region-w r) 2))))
;; Drags t's card to (x, y) of the content, with a step after each of
;; three moves, and presses Escape before the release when asked.
(define (drag-card! t x y . escape?)
  (let*-values ([(r) (card-of t)]
                [(x0 y0) (values (+ (ui-region-x r) 20) (+ (ui-region-y r) 10))]
                [(cx cy cw ch) (content-rect tw)])
    (inject! `(mouse-move ,(+ cx x0) ,(+ cy y0))
             `(mouse-down ,(+ cx x0) ,(+ cy y0) left 1))
    (steps 1)
    (for-each (lambda (f)
                (inject! `(mouse-move ,(+ cx (round (+ x0 (* f (- x x0)))))
                                      ,(+ cy (round (+ y0 (* f (- y y0)))))))
                (steps 1))
              '(1/3 2/3 1))
    (when (pair? escape?) (press! 'escape) (steps 1))
    (inject! `(mouse-up ,(+ cx (round x)) ,(+ cy (round y)) left))
    (steps 2)))
(let ([y (+ (column-top 'review) 8 (ui-region-h (card-of 7)) 4)])
  (drag-card! 16 (column-x 'review) y)
  (check "a card dragged into Review between two cards lands there"
         (and (eq? (task-status (find-task 16)) 'review)
              (eq? (next-to 7) (find-task 16))
              (eq? (next-to 16) (find-task 8)))))
(let ([y (+ (column-top 'todo) 8 (ui-region-h (card-of 12)) 4)])
  (drag-card! 11 (column-x 'todo) y)
  (check "and within a column it reorders"
         (and (eq? (next-to 12) (find-task 11))
              (eq? (next-to 11) (find-task 13)))))
(let ([order *tasks*] [r (ui-find tui 'details)])
  (drag-card! 12 (+ (ui-region-x r) 40) 300)
  (drag-card! 12 (column-x 'review) (+ (column-top 'review) 20) #t)
  (check "released outside the board, or after Escape, a card stays"
         (equal? order *tasks*)))
(let-values ([(cx cy cw ch) (content-rect tw)])
  (let* ([r (card-of 12)] [x0 (+ cx (ui-region-x r) 20)]
         [y0 (+ cy (ui-region-y r) 10)]
         [x1 (+ cx (column-x 'doing))] [y1 (+ cy (column-top 'doing) 4)])
    (inject! `(mouse-move ,x0 ,y0) `(mouse-down ,x0 ,y0 left 1))
    (steps 1)
    (inject! `(mouse-move ,x1 ,y1))
    (steps 1)
    (shot "drag")
    (inject! `(mouse-move ,(+ x1 1) ,y1) `(mouse-up ,(+ x1 1) ,y1 left))
    (steps 2)
    (check "a move and the release in one step drop it where the pointer is"
           (and (eq? (task-status (find-task 12)) 'doing)
                (eq? (find-task 12) (car (column-of 'doing)))))))

;; Another button during a drag: a right press, here in the gap between
;; two columns, ends the drag, leaving the card where it was and opening
;; no menu, and once both buttons are up nothing is held. With the right
;; button pressed first, the left one's release still ends a drag.
(let-values ([(cx cy cw ch) (content-rect tw)])
  (let* ([r (card-of 13)] [order *tasks*] [doing (ui-find tui '(column doing))]
         [x0 (+ cx (ui-region-x r) 20)] [y0 (+ cy (ui-region-y r) 10)]
         [x1 (+ cx (column-x 'doing))] [y1 (+ cy (column-top 'doing) 40)]
         [xg (round (+ cx (ui-region-x doing) (ui-region-w doing) 4))])
    (define (held?) (or (tasks-view-drag tv) (ui-state-active tui) *drag*))
    (inject! `(mouse-move ,x0 ,y0) `(mouse-down ,x0 ,y0 left 1))
    (steps 1)
    (inject! `(mouse-move ,x1 ,y1))
    (steps 1)
    (inject! `(mouse-move ,xg ,y1) `(mouse-down ,xg ,y1 right 1))
    (steps 1)
    (let ([ended? (and (not (ui-region-at tui (- xg cx) (- y1 cy)))
                       (not (or (tasks-view-drag tv) (menu-open?))))])
      (inject! `(mouse-up ,xg ,y1 right) `(mouse-up ,xg ,y1 left))
      (steps 2)
      (check "a right press during a drag ends it, the card where it was; \
              with both buttons up, nothing is held"
             (and ended? (equal? order *tasks*) (not (held?)))))
    (inject! `(mouse-move ,(+ cx 300) ,(+ cy 2))
             `(mouse-down ,(+ cx 300) ,(+ cy 2) right 1))
    (steps 1)
    (inject! `(mouse-move ,x0 ,y0) `(mouse-down ,x0 ,y0 left 1))
    (steps 1)
    (inject! `(mouse-move ,x1 ,y1))
    (steps 1)
    (inject! `(mouse-up ,x1 ,y1 right) `(mouse-up ,x1 ,y1 left))
    (steps 2)
    (check "pressed after the right button, the left one's release still \
            drops the card"
           (and (eq? (task-status (find-task 13)) 'doing) (not (held?))))
    (move-task! 13 'todo 14)
    (steps 2)))

;; Board keys: a key reaches the board (its keys are tested in
;; tests/units/tasks.ss).
(let-values ([(x y) (region-center (list 'card 13))])
  (tasks-click! x y))
(check "a click on a card selects it" (eq? (selected) (find-task 13)))
(press! 'down)
(steps 1)
(check "Down selects the next card" (eq? (selected) (find-task 14)))
(press! 'escape)
(steps 1)

;; The List.
(type! "v")
(steps 2)
(check "v switches to the List" (eq? (tasks-view-mode tv) 'list))
(define (rows) (tasks-rows tv (tasks-visible tv)))
(click-ui! tw '(table header priority))
(check "a press on a heading sorts the List by it"
       (equal? (tasks-view-sort tv) '(priority . up)))
(shot "list")
(tasks-sort-by! tv 'priority)
(tasks-sort-by! tv 'priority)   ; board order again
(press! 'down) (press! 'down)
(press! 'return)
(steps 2)
(check "Down twice selects the List's second row, and Return edits its title"
       (and (eq? (selected) (cadr (rows))) (eq? (focus-id) 'title)))
(press! 'escape)
(let-values ([(x y) (region-center '(table body))]
             [(cx cy cw ch) (content-rect tw)])
  (define (last-shown?)   ; drawn whole, not cut by the table's view
    (let ([r (ui-find tui (list 'table 'row (- (length (rows)) 1)))])
      (and r (> (ui-region-h r) 0)
           (= (ui-region-h r) (cadddr (ui-region-frame r))))))
  (press! 'end)
  (steps 2)
  (inject! `(mouse-move ,(+ cx (round x)) ,(+ cy (round y))) '(wheel 0 20))
  (steps 2)
  (let ([away (not (last-shown?))])
    (type! "v")
    (type! "v")
    (type! "v")
    (steps 2)
    (check "the Tree, the Board and back: the List shows its selected row \
            again"
           (and away (last-shown?)))))

(type! "/")
(type! "sdl")
(steps 2)
(check "/ focuses the search, which filters as you type"
       (and (eq? (focus-id) 'search)
            (equal? (tasks-visible tv) (tasks-list 'search "sdl"))
            (< 0 (length (tasks-visible tv)) 5)))
(press! 'return)
(steps 2)
(check "Return leaves the search and selects the first match"
       (and (not (focus-id)) (eq? (selected) (car (rows)))))
(click-ui! tw 'clear)
(click-ui! tw '(filter kind))
(test-menu-click! "Bug")
(check "Kind: Bug shows only bugs"
       (and (pair? (tasks-visible tv))
            (for-all (lambda (t) (eq? (task-kind t) 'bug)) (tasks-visible tv))))
(click-ui! tw 'clear)
(let ([a (task-assignee (find-task 9))])
  (set-task! 9 'assignee (apply string-append (make-list 20 "Grace Hopper ")))
  (steps 1)
  (click-ui! tw '(filter assignee))
  (let-values ([(mx my mw mh) (menu-geometry *menu*)]
               [(cx cy cw ch) (content-rect tw)]
               [(bx) (ui-region-x (ui-find tui '(filter assignee)))])
    (check "a long name keeps the Assignee filter's menu under its box, on \
            the screen"
           (and (< (abs (- mx cx bx)) 1) (<= (+ mx mw) (screen-w)))))
  (press! 'escape)
  (steps 2)
  (set-task! 9 'assignee a))
(type! "v")
(type! "v")   ; the Board again
(steps 2)

;; The context menu, Duplicate and Move to; Delete and its dialog.
(column-home! 'todo)
(let-values ([(x y) (region-center (list 'card 13))])
  (tasks-click! x y 'right 1))
(check "a right click on a card opens its menu" (menu-open?))
(test-menu-click! "Duplicate")
(define copy (selected))
(check "Duplicate: a copy right after it, selected"
       (and (= (+ 2 (length tasks-seed)) (length *tasks*))
            (eq? (next-to 13) copy)
            (equal? (task-title copy)
                    (string-append (task-title (find-task 13)) " (copy)"))))
;; Tasks' delete dialog (the dialog itself is tested in
;; tests/units/ui-dialog.ss)
(press! 'delete)
(steps 2)
(check "Delete asks first" (ui-find tui '(confirm 1)))
(shot "dialog")
(press! 'return)
(steps 2)
(check "Delete and Return: gone, and the task next to it selected"
       (and (not (memq copy *tasks*)) (selected)))

;; A long title in the details, scrolled to the caret, shows its start
;; again once left.
(let ([long (add-task! (string-append "A " (make-string 80 #\W))
                       'status 'review)])
  (steps 2)
  (let-values ([(x y) (region-center (list 'card (task-id long)))])
    (tasks-click! x y))
  (press! 'return)
  (press! 'end 'ctrl)
  (steps 2)
  (let ([scrolled (ui-memo tui 'title 0)])
    (press! 'escape)
    (steps 2)
    (check "a long title scrolled to the caret shows its start once left"
           (and (> scrolled 0) (not (focus-id)) (= 0 (ui-memo tui 'title 0)))))
  (delete-task! long)
  (steps 1))

;; Whatever has the keyboard is in view. Enter, a double click and the
;; menu's Open focus the title of a task whose details are scrolled away;
;; Return in Add an item keeps the keyboard in the field; a new card stays
;; in view as its title grows.
(define (shown? id)   ; drawn whole, not cut by a scroll view
  (let ([r (ui-find tui id)])
    (and r (> (ui-region-h r) 0)
         (= (ui-region-h r) (cadddr (ui-region-frame r))))))
(define (details-down!)
  (let-values ([(x y) (region-center 'status)]
               [(cx cy cw ch) (content-rect tw)])
    (inject! `(mouse-move ,(+ cx (round x)) ,(+ cy (round y)))
             '(wheel 0 -10))
    (steps 2)))
(let-values ([(x y) (region-center (list 'card 7))])
  (tasks-click! x y)
  (details-down!)
  (let ([away (not (shown? 'title))])
    (press! 'return)
    (steps 2)
    (let ([enter (and (eq? (focus-id) 'title) (shown? 'title))])
      (press! 'escape)
      (details-down!)
      (tasks-click! x y 'left 1)
      (tasks-click! x y 'left 2)
      (let ([double (and (eq? (focus-id) 'title) (shown? 'title))])
        (press! 'escape)
        (details-down!)
        (tasks-click! x y 'right 1)
        (test-menu-click! "Open")
        (check "Enter, a double click and Open show the title they focus, \
                scrolled out of the details"
               (and away enter double (eq? (focus-id) 'title)
                    (shown? 'title)))))))
(press! 'escape)
(click-ui! tw 'new-item)
(for-each (lambda (s) (type! s) (press! 'return))
          '("Item 1" "Item 2" "Item 3" "Item 4" "Item 5"))
(steps 2)
;; that the field stays in view as the items push it down is the kit's to
;; test (tests/units/ui-focus.ss)
(check "Return in Add an item keeps the keyboard there for the next item"
       (eq? (focus-id) 'new-item))
(set-task! 7 'checklist (list-head (task-checklist (find-task 7)) 5))
(press! 'escape)
(type! "n")
(type! (make-string 150 #\W))
(steps 2)
(check "a new card follows its title as it grows past the column's end"
       (shown? (list 'card (task-id (selected)))))
(press! 'escape)
(delete-task! (selected))
(steps 2)

;; Looks: the tag field draws no box inside the chip input's; a disabled
;; button does not light up under the pointer; a title cut short says so,
;; and so does a checklist item cut short, with a tooltip.
(define (content-pixel x y)
  (let-values ([(cx cy cw ch) (content-rect tw)])
    (screen-pixel (exact (floor (* *scale* (+ cx x))))
                  (exact (floor (* *scale* (+ cy y)))))))
(define (pixels-of x y w h)
  (let ([w (exact (round w))] [h (exact (round h))])
    (map (lambda (i) (content-pixel (+ x (mod i w)) (+ y (quotient i w))))
         (iota (* w h)))))
(define (pixels-in id)
  (let ([r (ui-find tui id)])
    (pixels-of (ui-region-x r) (ui-region-y r) (ui-region-w r)
               (ui-region-h r))))
(let-values ([(x y) (region-center (list 'card 9))])
  (tasks-click! x y))
(click-ui! tw '(tags field))
(let* ([r (ui-find tui '(tags field))]
       [right (+ (ui-region-x r) (ui-region-w r))]
       [y (+ (ui-region-y r) (quotient (ui-region-h r) 2))])
  (check "the tag field draws no box of its own inside the chip input's"
         (= (content-pixel (- right 1) y) (content-pixel (- right 12) y))))
(press! 'escape)
(let-values ([(cx cy cw ch) (content-rect tw)] [(x y) (region-center 'clear)])
  (inject! `(mouse-move ,(+ cx 4) ,(+ cy 4)))
  (steps 2)
  (let ([before (pixels-in 'clear)])
    (inject! `(mouse-move ,(+ cx (round x)) ,(+ cy (round y))))
    (steps 2)
    (check "a disabled button does not light up under the pointer"
           (and (not (tasks-filtered? tv)) (equal? before (pixels-in 'clear))))
    (inject! `(mouse-move ,(+ cx 4) ,(+ cy 4)))
    (steps 2)))
(let ([long (add-task! (make-string 300 #\W) 'status 'review
                       'checklist (list (make-string 60 #\x)))])
  (steps 2)
  (let-values ([(x y) (region-center (list 'card (task-id long)))])
    (tasks-click! x y))
  (let* ([r (ui-find tui 'title)]
         [a (car (apply ui-text-box-areas
                        (append (ui-region-frame r) '((large bare single)))))]
         [hh (font-line-height 'heading)]
         [row (lambda (i) (pixels-of (list-ref a 1) (round (+ (list-ref a 2)
                                                               (* i hh)))
                                     (list-ref a 3) (round hh)))])
    (check "an unfocused title cut after four rows ends its last with …"
           (and (not (focus-id)) (equal? (row 1) (row 2))
                (not (equal? (row 2) (row 3))))))
  (check "a checklist item cut short has its text as a tooltip"
         (equal? (ui-region-tip (ui-find tui '(item 0)))
                 (caar (task-checklist long))))
  (delete-task! long)
  (steps 2))

;; The REPL's procedures show in the window at once.
(define rt (add-task! "From the REPL" 'status 'review))
(steps 1)
(check "add-task!: its card shows" (card-of rt))
(let-values ([(x y) (region-center (list 'card (task-id rt)))])
  (tasks-click! x y))
(press! 'return)
(steps 1)
(set-task! rt 'title "Renamed")
(steps 2)
(check "set-task! on a focused title: the field shows it"
       (and (eq? (focus-id) 'title) (equal? (edit-text (edit)) "Renamed")))
(delete-task! rt)
(steps 1)
(check "delete-task!: the selection goes" (and (not (selected))
                                              (not (memq rt *tasks*))))

;; Empty states.
(type! "/")
(type! "nothing-like-this")
(press! 'escape)
(steps 2)
(check "nothing matches: an empty state with a way back"
       (ui-find tui 'empty-clear))
(shot "nothing")
(click-ui! tw 'empty-clear)
(tasks-reset!)

;; Dependencies. The details show what a task waits for, as chips that a
;; × removes, with Add's menu of the tasks that make no cycle, and what
;; waits for it; a click on a chip selects that task.
(tasks-wide!)
(tasks-select! tv (find-task 14))
(invalidate! tw)   ; a selection from here asks for no frame
(steps 2)
(check "the details show what a task waits for and what waits for it"
       (and (ui-find tui '(blocked-by 33)) (ui-find tui '(blocks 22))
            (ui-find tui '(blocked-by add))))
(shot "links")
(let ([tip (tasks-tip (find-task 13) #f)] [card (card-of 13)])
  (check "a blocked task's card has a tooltip naming what it waits for"
         (and (string-prefix? "Blocked by TASK-31 Each window" tip)
              (string-contains-ci? tip ", TASK-10 Threads spec")
              (not (tasks-tip (find-task 12) #f))
              ;; on the card it comes after the title, which the card cuts
              (or (not card) (string-suffix? tip (ui-region-tip card))))))
(click-ui! tw '(blocked-by add))   ; its choices: tasks-blocker-choices
(type! "fractal")
(press! 'return)
(steps 2)
(check "typed, the menu narrows, and Return adds that one"
       (and (not (menu-open?))
            (equal? (task-blocked-by (find-task 14)) '(33 19))
            (ui-find tui '(blocked-by 19))))
(click-ui! tw '(blocked-by remove 19))
(check "a chip's × removes it" (equal? (task-blocked-by (find-task 14)) '(33)))
(click-ui! tw '(blocks 22))
(check "a click on a chip selects that task" (eq? (selected) (find-task 22)))

;; With many tasks, Add's menu shows what fits on the screen, then how many
;; more there are, which typing narrows; the task whose id is typed comes
;; first. A choice that the REPL made into a cycle while the menu was open
;; is refused, and a plain toast says so.
(let* ([more (sort (lambda (a b) (< (task-id a) (task-id b)))   ; board order
                   (map (lambda (i) (add-task! (format "Filler ~a" i)))
                        (iota 60)))]
       [last (car (last-pair more))]
       [labels (lambda () (map car (filter pair? (menu-entries *menu*))))]
       [red? (lambda ()
               (exists (lambda (x) (eq? (vector-ref x 2) 'red)) *toasts*))])
  (set-task! (car more) 'title (format "About ~a" (task-label last)))
  (test-finally
   (lambda ()
     (tasks-select! tv (find-task 14))
     (invalidate! tw)
     (steps 2)
     (click-ui! tw '(blocked-by add))
     (let ([n (length (tasks-blocker-choices (find-task 14)))] [l (labels)])
       (let-values ([(x y w h) (menu-geometry *menu*)])
         (check "with many tasks, Add's menu fits on the screen, its last \
                 entry saying how many more"
                (and (<= (+ y h) (screen-h)) (< 10 (length l) n)
                     (equal? (car (last-pair l))
                             (format "… ~a more: type to narrow"
                                     (- n (length l) -1)))))))
     (press! 'escape)
     (steps 1)
     (let ([a (car more)] [b (cadr more)])
       (tasks-select! tv a)
       (invalidate! tw)
       (steps 2)
       (click-ui! tw '(blocked-by add))
       (type! (task-label b))
       (steps 1)
       (set-task! b 'blocked-by (list a))   ; the REPL, while the menu is open
       (set! *toasts* '())
       (press! 'return)
       (steps 2)
       (check "a choice the REPL made into a cycle while Add's menu was open: \
               refused, and a plain toast names the cycle"
              (and (null? (task-blocked-by a)) (not (red?))
                   (equal? (map (lambda (x) (vector-ref x 1)) *toasts*)
                           (list (format "~a would wait for itself: ~a → ~a \
                                          → ~a (each waits for the next)"
                                         (task-label a) (task-label a)
                                         (task-label b) (task-label a))))))))
   (lambda ()
     (when (menu-open?) (close-menu!))
     (for-each delete-task! more)
     (set! *toasts* '())
     (tasks-select! tv #f)
     (steps 2))))

;; The Tree: under each task, what it waits for. A click selects; a later
;; row of a shared blocker is a place of its own, and Return goes to the
;; task's own row (the tree itself is tested in tests/units/ui-tree.ss).
(define (tree-rows) (ui-memo tui '(tree rows) '#()))
(define (tree-nodes) (map ui-tree-row-node (vector->list (tree-rows))))
(define (tree-shown! node)   ; the wheel brings node's row into view
  (let loop ([n 0])
    (let* ([i (ui-tree-index (tree-rows) node)]
           [r (ui-find tui (list 'tree 'row i))]
           [shown (filter-map (lambda (r)
                                (let ([id (ui-region-id r)])
                                  (and (list? id) (= 3 (length id))
                                       (equal? (list-head id 2) '(tree row))
                                       (caddr id))))
                              (ui-state-regions tui))])
      (unless (or (= n 40)
                  (and r (= (ui-region-h r) (cadddr (ui-region-frame r)))))
        (let-values ([(x y) (region-center '(tree body))]
                     [(cx cy cw ch) (content-rect tw)])
          (inject! `(mouse-move ,(+ cx (round x)) ,(+ cy (round y)))
                   ;; up for a row at the top (cut there) or above it
                   `(wheel 0 ,(if (<= i (apply min shown)) 1 -1)))
          (steps 1)
          (loop (+ n 1)))))))
(define (tree-click! node . twisty?)   ; on its row, or on its twisty
  (tree-shown! node)
  (let* ([i (ui-tree-index (tree-rows) node)]
         [r (ui-find tui (list 'tree 'row i))]
         [t (cdr (assq 'twisty
                       (ui-tree-areas (ui-region-x r) (ui-region-y r) 1000
                                      (ui-region-h r)
                                      (ui-tree-row-depth
                                       (vector-ref (tree-rows) i)))))])
    (tasks-click! (if (pair? twisty?)
                      (+ (car t) (/ (caddr t) 2))
                      (+ (ui-region-x r) (/ (ui-region-w r) 2)))
                  (+ (ui-region-y r) (/ (ui-region-h r) 2)))))
(define (tree-at) (tasks-tree-node tv))
(tasks-select! tv #f)
(click-ui! tw '(view tree))
(shot "tree")
(tree-click! 13)
(check "a click on a row selects its task, and the details show it"
       (and (eq? (selected) (find-task 13)) (equal? (tree-at) 13)
            (ui-find tui '(blocked-by 31))))
(tree-click! '(17 . 31))
(press! 'down)
(steps 1)
(check "a click on a later row, and Down goes on from there"
       (equal? (tree-at) 18))
(press! 'up)
(press! 'return)   ; to the task's own row
(steps 2)
(press! 'return)
(steps 1)
(check "Return on a task's own row edits its title" (eq? (focus-id) 'title))
(press! 'escape)
(tree-click! 13 'twisty)
(tasks-select! tv (find-task 10))
(invalidate! tw)
(steps 2)
(check "selecting a task under a collapsed row expands it again"
       (and (memv 10 (tree-nodes)) (equal? (tree-at) 10)))
(tree-click! 16)
(tree-shown! 16)
(let-values ([(x y) (region-center (list 'tree 'row
                                         (ui-tree-index (tree-rows) 16)))])
  (tasks-click! x y 'right 1))
(check "a right click on a row opens the task's menu"
       (and (menu-open?) (eq? (selected) (find-task 16))))
(press! 'escape)
(steps 1)
(let ([dim '()] [orig tasks-draw-node])
  (set! tasks-draw-node
        (lambda (x y w h flags t where)
          (when (memq 'dim flags) (set! dim (cons (task-id t) dim)))
          (orig x y w h flags t where)))
  (type! "/")
  (type! "fractal")
  (press! 'escape)
  (steps 2)
  (set! tasks-draw-node orig)
  (check "a search dims what it leaves out, keeping the tree"
         (and (memv 11 dim) (not (memv 19 dim)) (memv 11 (tree-nodes))
              (memv 16 (tree-nodes)))))
(shot "tree-search")
(click-ui! tw 'clear)

;; A row whose twisty hid the selection is selected, and typing in that
;; task's details keeps it collapsed (the selection's own rules are tested
;; in tests/units/tasks.ss).
(tasks-select! tv (find-task 9))
(invalidate! tw)
(steps 2)
(tree-click! 11 'twisty)   ; it hides the selection, 9, so 11 is selected
(let ([was (task-description (find-task 11))])
  (click-ui! tw 'description)
  (type! "x")
  (steps 2)
  (check "a task whose row's twisty hid the selection: typing in its \
          details keeps it collapsed"
         (and (not (memv 9 (tree-nodes))) (equal? (tree-at) 11)))
  (press! 'escape)
  (set-task! 11 'description was))
(tree-click! 11 'twisty)
(let ([forests 0] [made 0] [plain-forest tasks-forest] [plain ui-tree-rows]
      [after (next-to 13)] [was (task-description (find-task 13))])
  (set! tasks-forest (lambda (ts) (set! forests (+ forests 1))
                       (plain-forest ts)))
  (set! ui-tree-rows (lambda a (set! made (+ made 1)) (apply plain a)))
  (tasks-select! tv (find-task 13))
  (invalidate! tw)
  (steps 2)
  (click-ui! tw 'description)
  (set! forests 0)
  (set! made 0)
  (type! "y")
  (steps 2)
  (let ([typed (list forests made)])
    (press! 'escape)
    (move-task! 13 'review)
    (steps 2)
    (set! tasks-forest plain-forest)
    (set! ui-tree-rows plain)
    (check "a keystroke in the Tree's details works out neither the forest \
            nor its rows again; a status changed does"
           (and (equal? typed '(0 0)) (> forests 0) (> made 0))))
  (move-task! 13 'todo after)
  (set-task! 13 'description was)
  (steps 2))
(let ([drawn '()] [plain draw-text])
  (set! draw-text (lambda (x y s . more)
                    (set! drawn (cons s drawn))
                    (apply plain x y s more)))
  (tasks-select! tv #f)
  (invalidate! tw)
  (steps 1)
  (set! draw-text plain)
  (check "with nothing selected, the keys list the Tree's Left, Right and \
          Space" (member "← → Space" drawn)))
(set-task! 12 'blocked-by '(16))
(steps 2)
(check "set-task! from the REPL shows in the Tree at once"
       (and (equal? (assv 12 (tasks-tree)) '(12 (16)))
            (let ([i (ui-tree-index (tree-rows) 16)])
              (and i (= 1 (ui-tree-row-depth (vector-ref (tree-rows) i)))))))
(set-task! 12 'blocked-by '())
(tasks-select! tv #f)

;; A reload that changed task's fields (here, as if coming back from its
;; first record type) carries the tasks over, each with an empty
;; blocked-by, and Tasks opens again in its place.
(let* ([rtd (make-record-type-descriptor
             'task #f 'schevana-task-1 #f #f
             '#((immutable id) (mutable title) (mutable description)
                (mutable status) (mutable kind) (mutable priority)
                (mutable assignee) (mutable tags) (mutable due)
                (mutable checklist) (immutable created) (mutable updated)))]
       [old (record-constructor (make-record-constructor-descriptor rtd #f
                                                                    #f))]
       [before (map (lambda (t)
                      (list (task-id t) (task-title t) (task-status t)
                            (task-checklist t)))
                    *tasks*)]
       [x (window-x tw)] [y (window-y tw)])
  (set! *tasks*
    (map (lambda (t)
           (old (task-id t) (task-title t) (task-description t)
                (task-status t) (task-kind t) (task-priority t)
                (task-assignee t) (task-tags t) (task-due t) (task-checklist t)
                (task-created t) (task-updated t)))
         *tasks*))
  (test-reload-library! '(schevana apps tasks))
  (steps 3)
  (let ([new (find-window 'tasks)])
    (check "a reload that changed task's fields keeps every task, each \
            carried over with an empty blocked-by, and Tasks opens again in \
            its place"
           (and (for-all task? *tasks*)
                (equal? before (map (lambda (t)
                                      (list (task-id t) (task-title t)
                                            (task-status t) (task-checklist t)))
                                    *tasks*))
                (for-all (lambda (t) (null? (task-blocked-by t))) *tasks*)
                new (not (eq? new tw)) (not (memq tw (windows)))
                (= x (window-x new)) (= y (window-y new))
                (not (window-error new))))
    (set! tw new)
    (set! tv (window-ref tw 'state))
    (set! tui (window-ref tw 'ui))))
(tasks-reset!)
(steps 2)

;; A narrow window: the details are a page.
(tasks-narrow!)
(steps 2)
(let-values ([(x y) (region-center (list 'card 9))])
  (tasks-click! x y))
(check "narrow, a click on a card opens its page"
       (and (ui-find tui 'back) (not (ui-find tui (list 'card 9)))))
(shot "narrow")
(press! 'escape)
(steps 2)
(check "and Escape goes back" (and (not (ui-find tui 'back)) (card-of 9)
                                   (eq? (selected) (find-task 9))))
(tasks-wide!)
(steps 2)
(click-ui! tw 'assignee)
(tasks-narrow!)
(steps 2)
(type! "n")
(steps 2)
(check "a window made narrow while a field has the keyboard shows the \
        details' page, and typing goes on in the field"
       (and (eq? (focus-id) 'assignee) (ui-find tui 'back)
            (equal? (task-assignee (find-task 9)) "Clauden")))
(press! 'escape)
(press! 'escape)
(steps 2)
(set-task! 9 'assignee "Claude")
(steps 1)

;; A row that the toolbar's items fill exactly stays one row: that is the
;; toolbar's to test (tests/units/ui-toolbar.ss).
(tasks-wide!)
(steps 2)

;; 100,000 characters: words, then one word as long as all of them.
(define long-text
  (string-append (apply string-append (make-list 5555 "abcdefgh "))
                 (make-string 50005 #\x)))

;; The CPU time this thread has had, in ms: by this measure a step's work
;; is the step's own, however long a busy machine kept the thread waiting.
(define (thread-cpu-ms)
  (let ([t (current-time 'time-thread)])
    (+ (* 1000 (time-second t)) (quotient (time-nanosecond t) 1000000))))

;; Takes n steps and returns the slowest one's work, in ms.
(define (slowest-of-steps n)
  (let loop ([i 0] [worst 0])
    (if (= i n)
        worst
        (let ([t0 (thread-cpu-ms)])
          (steps 1)
          (loop (+ i 1) (max worst (- (thread-cpu-ms) t0)))))))

;; That text pasted into a title, an assignee, a tag and the search: the
;; Board, the details, the menus, the dialog, the List and the Tree keep
;; answering, every step under 300 ms of work (55 at most measured alone,
;; 95 on a busy machine; a cut that reads the text again for each piece
;; takes seconds), and Tasks never crashes.
(let ([t (add-task! "Long" 'status 'review)] [slow '()])
  (define (timed label n)
    (let ([ms (slowest-of-steps n)])
      (when (or (> ms 300) (window-error tw))
        (set! slow (cons (cons label ms) slow)))))
  (define (at! id . button)   ; a click, not stepped
    (if (ui-find tui id)
        (let-values ([(x y) (region-center id)]
                     [(cx cy cw ch) (content-rect tw)])
          (let ([x (+ cx (round x))] [y (+ cy (round y))]
                [b (if (pair? button) (car button) 'left)])
            (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y ,b 1)
                     `(mouse-up ,x ,y ,b))))
        (set! slow (cons (cons id 'gone) slow))))
  (define (paste!) (set! *core0-clipboard* long-text) (press! #\v 'ctrl))
  (define card (list 'card (task-id t)))
  (steps 1)
  (at! card) (timed "its details" 2)
  (press! 'return) (press! #\a 'ctrl) (paste!) (timed "the title" 2)
  (type! "y") (timed "typed" 1)
  (press! 'escape) (timed "left" 1)
  (at! 'assignee) (timed "the assignee" 2)
  (paste!) (timed "pasted" 1)
  (press! 'escape) (timed "left" 1)
  (at! '(tags field)) (timed "the tag field" 2)
  (paste!) (timed "pasted" 1)
  (press! 'return) (timed "added" 1)
  (press! 'escape) (timed "left" 1)
  (at! card 'right) (timed "the card's menu" 2)
  (let ([menu? (menu-open?)])
    (press! 'escape) (timed "closed" 1)
    (press! 'delete) (timed "the dialog" 1)
    (let ([dialog? (ui-find tui '(confirm 1))])
      (press! 'escape) (timed "canceled" 1)
      (at! '(filter assignee)) (timed "the Assignee menu" 2)
      (let ([menu-w (and (menu-open?)
                         (call-with-values (lambda () (menu-geometry *menu*))
                           (lambda (x y w h) w)))])
        (press! 'escape) (timed "closed" 1)
        (type! "v") (timed "the List" 1)
        (press! 'down) (timed "down" 1)
        (press! 'up) (timed "up" 1)
        (type! "v") (timed "the Tree" 1)
        (press! 'down) (timed "down" 1)
        (press! 'left) (timed "left" 1)
        (type! "v") (timed "the Board" 1)
        (type! "/") (paste!) (timed "the search" 1)
        (at! 'search) (timed "a click in it" 2)
        (press! 'escape) (timed "left" 1)
        (unless (null? slow) (printf "  slow or crashed: ~s\n" slow))
        (check "100,000 characters in a title, an assignee, a tag and the \
                search: every step of the Board, the details, the menus, \
                the dialog, the List and the Tree under 300 ms of work, \
                and Tasks never crashed"
               ;; the menu's width: a name of at most 20 line heights, and
               ;; the menu's own room
               (and (null? slow) menu? dialog? menu-w
                    (< menu-w (* 24 (font-line-height 'ui)))
                    (= (string-length (task-title t)) 100001)
                    ;; a name is cut to 64 characters
                    (equal? (task-assignee t) (substring long-text 0 64))
                    (member "abcdefgh-abcdefgh-abcdef" (task-tags t))
                    (not (window-error tw)))))))
  (when (ui-find tui 'clear) (click-ui! tw 'clear))
  (delete-task! t)
  (steps 2))

;; A description holds at most 65,536 characters, whether typed, pasted or
;; set from the REPL. A long one has a scroll bar, which settles once idle
;; steps have computed its rows.
(define (words n)
  (let ([o (open-output-string)])
    (let loop ([i 0])
      (when (< i n)
        (put-string o (vector-ref '#("scroll " "the " "long " "text " "row ")
                                  (mod i 5)))
        (loop (+ i 1))))
    (substring (get-output-string o) 0 n)))
(define long-task (add-task! "A long description" 'status 'review))
(steps 2)
(let-values ([(x y) (region-center (list 'card (task-id long-task)))])
  (tasks-click! x y))
;; its limit of 65,536 is Tasks' to test (tests/units/tasks.ss), and its
;; box's 'max the kit's (tests/units/ui-text-box.ss)
(set-task! long-task 'description (make-string 70000 #\a))
(steps 1)
(set-task! long-task 'description (words 65000))
(steps 1)
(let ([bar (ui-find tui '(description bar))]
      [lay (ui-memo tui '(description rows) #f)])
  (check "a long description has a scroll bar; idle steps compute its rows \
          to the end, then draw it again, its bar settled"
         (and bar (pair? (ui-state-scans tui))
              (not (edit-layout-done? lay))
              (wait-for (lambda () (null? (ui-state-scans tui))))
              (edit-layout-done? lay)
              (eq? lay (ui-memo tui '(description rows) #f)))))

;; Its wheel, bar, Page Down, Ctrl+Home and Ctrl+End are a text area's,
;; and are tested with it (tests/units/ui-scroll.ss).

;; A keystroke's edit says where it changed the text, so its rows follow
;; without comparing texts; a change from the REPL compares them.
(click-ui! tw 'description)   ; the keys below go to the description
(define compared 0)
(define plain-difference edit-difference)
(set! edit-difference
      (lambda (a b) (set! compared (+ compared 1)) (plain-difference a b)))
(type! "abc")
(press! 'backspace)
(press! 'delete)
(press! 'return)
(steps 2)
(let ([typed compared])
  (set-task! long-task 'description
             (string-append "From the REPL. " (task-description long-task)))
  (steps 2)
  (check "typing in a long description compares no texts; a change from \
          the REPL does"
         (and (= typed 0) (> compared 0))))

;; A step that brings input to any window runs no scan for a scroll bar in
;; any window: the input's frame comes first.
(let ([slices 0] [plain edit-layout-scan!] [w (repl)])
  (set! edit-layout-scan!
        (lambda args (set! slices (+ slices 1)) (apply plain args)))
  (set-task! long-task 'description (words 65000))
  (steps 1)
  (let ([pending? (pair? (ui-state-scans tui))])
    (set! slices 0)
    (type! "x")
    (steps 1)
    (let ([on-input slices])
      (steps 1)
      (set! edit-layout-scan! plain)
      (close-window! w)
      (steps 2)
      (check "a key typed in a REPL runs no scan of Tasks' long description \
              in that step; the next, idle, does"
             (and pending? (= on-input 0) (> slices 0))))))
(focus-window! tw)
(click-ui! tw 'description)

;; The description's editor is tested in tests/units/tasks-editor.ss.
(set! edit-difference plain-difference)
(press! 'escape)
(tasks-select! tv #f)
(invalidate! tw)
(steps 2)
(delete-task! long-task)
(steps 2)

;; A window titled with 10,000 characters, then (only if that was quick,
;; so that a slow cut fails within seconds) with 100,000: every window
;; style draws it in under 300 ms of work per frame.
(let ([style (theme 'window-style)])
  (define (slow-styles title)
    (let* ([w (open-window title 'size '(300 . 200)
                           'draw (lambda (win cw ch) (void)))]
           [slow (filter (lambda (s)
                           (set-theme! 'window-style s)
                           (invalidate!)
                           (> (slowest-of-steps 2) 300))
                         (styles))])
      (close-window! w)
      slow))
  (let* ([slow (slow-styles (substring long-text 0 10000))]
         [slow (if (null? slow) (slow-styles long-text) slow)])
    (set-theme! 'window-style style)
    (steps 1)
    (check (format "a window's title of 10,000, then 100,000 characters: \
                    every window style draws it in under 300 ms of work \
                    (slow: ~a)"
                   slow)
           (null? slow))))

(let ([n (length *tasks*)] [first (car *tasks*)])
  (reload!)
  (steps 2)
  (check "(reload!) keeps the tasks, and the window draws"
         (and (= n (length *tasks*)) (eq? first (car *tasks*))
              (not (window-error tw)) (eq? tv (window-ref tw 'state)))))
(check "Tasks never crashed" (not (window-error tw)))
(let ([status (task-status (find-task 9))])
  (let-values ([(x y) (region-center (list 'card 9))])
    (tasks-click! x y 'right 1))
  (close-window! tw)
  (test-menu-click! "Move to Done")
  (check "a menu its window left open changes nothing once it is closed"
         (eq? status (task-status (find-task 9)))))
(set! *toasts* '())


;; The profiler and Monitor are tested in tests/units/monitor.ss.
(let ([m (find-window 'monitor)]) (when m (close-window! m)))
(steps 2)

;; Reloading the sources keeps the world's state, and the profiler's
;; history.
(let ([n (length (windows))] [s (car (profile-ticks))])
  (reload!)
  (check "reload asks for the whole screen" (eq? *dirty* #t))
  (steps 2)
  (check "reload keeps windows" (= n (length (windows))))
  (check "windows still draw after reload"
         (not (window-error (find-window 'clock))))
  (check "reload keeps the profiler's history, and it goes on"
         (and (profile-on?) (pair? *profile-span*)
              (memv s (profile-ticks))
              (not (eqv? s (car (profile-ticks)))))))
(let ([s (settings)])
  (steps 2)
  (click-ui! s '(tab theme))
  (click-ui! s '(style interlisp))
  (check "settings still work after reload"
         (and (eq? (theme 'window-style) 'interlisp) (not (window-error s))))
  (set-theme! 'window-style 'mac)
  (close-window! s))

;;; Frames asked for and not are tested in tests/units/windows.ss. What
;;; the checks below still share:
(for-each close-window! (windows))
(set! *toasts* '())
(steps 2)

;; A counter of the window's draws.
(define (count-draws! win)
  (let ([n 0]
        [draw (hashtable-ref (window-handlers win) 'draw
                             (lambda args (void)))])
    (window-on! win 'draw (lambda (w cw ch) (set! n (+ n 1)) (draw w cw ch)))
    (lambda () n)))

;; (open-window takes the first 'size)
(define (plain-window title x y . opts)
  (apply open-window title 'size (plist-ref opts 'size '(260 . 120))
         'pos (cons x y)
         'draw (lambda (win w h) (draw-text 14 14 title 'text 'ui))
         opts))

;; The device pixels the logical rect (x y w h) covers completely:
;; (x0 y0 x1 y1).
(define (device-box x y w h)
  (let ([s *scale*])
    (list (exact (ceiling (* s x))) (exact (ceiling (* s y)))
          (exact (floor (* s (+ x w)))) (exact (floor (* s (+ y h)))))))

;; How many pixels of the canvas inside the device box b are px.
(define (canvas-pixels b px)
  (do ([y (cadr b) (+ y 1)]
       [n 0 (do ([x (car b) (+ x 1)]
                 [n n (if (= px (screen-pixel x y)) (+ n 1) n)])
                ((= x (caddr b)) n))])
      ((= y (cadddr b)) n)))

;; Settings: input and the full-screen switch reach it.
(let* ([s (settings)] [st (window-ref s 'state)])
  (steps 2)
  (click-ui! s '(tab colors))
  (click-ui! s 'hex)
  (let ([n (count-draws! s)])
    (steps 2)
    (type! "12")
    (steps 2)
    (let ([n0 (n)]
          [editing? (and (equal? (ui-focused (window-ref s 'ui)) 'hex)
                         (equal? (settings-st-hex st) "12"))])
      (let-values ([(x y) (ui-point s '(color bg-1) 0.5)])
        (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                 `(mouse-up ,x ,y left)))
      (steps 2)
      (check
       "a press elsewhere while typing a hex color leaves its field, the \
        typing dropped"
       (and editing? (not (settings-st-hex st)) (> (n) n0)
            (eq? (settings-st-key st) 'bg-1))))
    (click-ui! s '(tab display))
    (let ([n0 (n)])
      (press! 'f11)
      (steps 2)
      (check "F11 updates Settings' Full screen control"
             (and (fullscreen?) (> (n) n0)))
      (press! 'f11)
      (steps 2)))
  (close-window! s))

;; A drawing procedure redefined at the REPL draws the next frame its
;; window is drawn in (the REPL invalidates everything when it is done),
;; and so does the original once it is put back.
(let ([w (plain-window "Plain" 300 200)] [orig draw-window] [calls 0])
  (steps 2)
  (set! draw-window (lambda (win) (set! calls (+ calls 1)) (orig win)))
  (invalidate!)
  (steps 1)
  (let ([n calls])
    (set! draw-window orig)
    (invalidate!)
    (steps 1)
    (check (format "a redefined draw-window draws the next frame \
                    (~a windows), the one put back the frame after" n)
           (and (= n 1) (= calls 1))))
  (let ([orig draw-taskbar] [calls 0])
    (set! draw-taskbar (lambda args
                         (apply orig args)
                         (set! calls (+ calls 1))
                         (draw-text 700 (- (screen-h) 28) (number->string calls)
                                    'panel-text 'ui)))
    (do ([i 0 (+ i 1)]) ((= i 3)) (request-frame!) (steps 1))
    (let ([n calls])
      (set! draw-taskbar orig)
      (steps 1)
      (check (format
              "a redefined draw-taskbar draws every forced frame (~a of 3)" n)
             (= n 3))))
  (close-window! w))

;; Hover and press-and-hold on the buttons of the styles that draw them.
(for-each
 (lambda (style)
   (let ([w (plain-window "Buttons" 200 200 'window-style style)])
     (steps 2)
     (for-each (lambda (kind)
                 (let* ([b (assq kind (frame-regions w))]
                        [x (+ (window-x w) (list-ref b 1)
                              (quotient (list-ref b 3) 2))]
                        [y (+ (window-y w) (list-ref b 2)
                              (quotient (list-ref b 4) 2))])
                   (inject! `(mouse-move ,x ,y))
                   (steps 1)
                   (inject! `(mouse-down ,x ,y left 1))
                   (steps 1)
                   ;; held, then released elsewhere
                   (inject! `(mouse-move ,(+ x 300) ,(+ y 200)))
                   (steps 1)
                   (inject! `(mouse-up ,(+ x 300) ,(+ y 200) left))
                   (steps 1)))
               '(close minimize maximize))
     (check (format "~a buttons hover and press without acting" style)
            (and (memq w (windows)) (visible? w) (not (maximized? w))))
     (close-window! w)))
 '(mac windows))

(let* ([broken #t]
       [w (plain-window "Fragile" 300 200
                        'draw (lambda (win cw ch)
                                (when broken (error 'draw "broken on purpose"))
                                (draw-text 14 14 "fixed" 'text 'ui)))])
  (parameterize ([console-error-port (open-output-string)]) (steps 2))
  (let ([crashed? (and (window-error w) #t)])
    (set! broken #f)
    (let-values ([(cx cy cw ch) (content-rect w)])
      (inject! `(mouse-move ,(+ cx 50) ,(+ cy 50))
               `(mouse-down ,(+ cx 50) ,(+ cy 50) left 1)
               `(mouse-up ,(+ cx 50) ,(+ cy 50) left)))
    (steps 2)
    (check "a click on a crashed window retries it"
           (and crashed? (not (window-error w)))))
  (close-window! w)
  (set! *toasts* '())
  (steps 1))


;; A style whose drawing fails: nothing of what was under the window
;; stays on screen.
(define-style broken "Broken"
  'frame-radius (lambda (w) 8)
  'frame-under (lambda (win x y w h focused? hover pressed)
                (error 'broken "broken on purpose")))
(test-with-quiet-status
 (lambda ()
   (let ([x (open-window "Red" 'size '(300 . 200) 'pos '(300 . 200)
                         'draw (lambda (win cw ch)
                                 (fill-box 0 0 cw ch #xff0000)))])
     (steps 2)
     (minimize-window! x)
     (let ([y (open-window "Broken" 'size '(300 . 200) 'pos '(300 . 200)
                           'window-style 'broken)])
       (set-geometry! y (window-x x) (window-y x) (window-w x) (window-h x))
       (parameterize ([console-error-port (open-output-string)]) (steps 3))
       (check "a window whose style fails to draw hides what was under it"
              (= 0 (canvas-pixels (device-box (window-x y) (window-y y)
                                              (window-w y) (window-h y))
                                  #xffff0000)))
       (for-each close-window! (list x y))
       (set! *toasts* '())
       (steps 1)))))
(set! *styles*
  (remp (lambda (s) (eq? (style-name s) 'broken)) *styles*))

;; Life's cells take up a theme change made behind set-theme!'s back, once
;; asked to draw (set-theme! asks every window). The height of Life's bar
;; is Life's own, reached through test-library (tests/reach.ss).
(test-library '(demo life) 'lf:)
(let ([l (lf:life)] [green (theme 'green)] [cyan (theme 'cyan)])
  (window-call l 'key #\space '())   ; paused
  (move-window! l 100 60)
  (steps 2)
  (let*-values ([(cx cy cw ch) (content-rect l)]
                [(grid) (device-box cx cy cw (- ch (lf:life-bar-height)))]
                [(old) (canvas-pixels grid (color->pixel green))])
    (hashtable-set! *theme* 'green #xff00ff)
    (hashtable-set! *theme* 'cyan #xff00ff)
    (invalidate!)
    (steps 2)
    (let ([stale (canvas-pixels grid (color->pixel green))]
          [new (canvas-pixels grid (color->pixel #xff00ff))])
      (hashtable-set! *theme* 'green green)
      (hashtable-set! *theme* 'cyan cyan)
      (steps 1)
      (check (format "a raw change to the theme recolors Life's cells on the \
                      next frame (~a, ~a stale)" new stale)
             (and (> old 0) (= stale 0) (> new 0)))))
  (close-window! l)
  (steps 1))

;;; Live changes: redefining while the world runs (reloading as a process
;;; is tested in tests/units/reload.ss).

;; A draw-wallpaper that raises, tried again with every frame, is reported
;; once, and the windows are drawn as ever.
(let ([orig draw-wallpaper] [calls 0] [told 0] [plain notify] [drawn 0]
      [w (plain-window "Over" 100 100)])
  (let ([n (count-draws! w)])
    ;; it passes fill-gradient an argument too few
    (set! draw-wallpaper (lambda (w h)
                           (set! calls (+ calls 1))
                           (fill-gradient 0 0 w h #x102030)))
    (set! notify (lambda args (set! told (+ told 1)) (apply plain args)))
    (parameterize ([console-error-port (open-output-string)])
      (let ([d0 (n)])
        (invalidate!)
        (steps 1)
        (invalidate!)
        (steps 1)
        (set! drawn (- (n) d0))))
    (set! draw-wallpaper orig)
    (set! notify plain)
    (invalidate!)
    (steps 1)
    (check (format "a draw-wallpaper that raises is reported once though \
                    tried ~a times, and windows are drawn (~a)" calls drawn)
           (and (= told 1) (>= calls 2) (>= drawn 2))))
  (close-window! w)
  (set! *toasts* '())
  (steps 1))

;; A window opened under an older kit holds a ui that this kit cannot
;; read: when the kit's library is evaluated again and run (as a reload
;; does), the window's app opens again in its place.
(for-each (lambda (w) (when (eq? (window-app w) 'clock) (close-window! w)))
          (windows))
(let ([old (clock)])
  (resize-window! old 300 240)
  (hashtable-set! (window-props old) 'ui 'an-older-kits-ui)
  (let ([x (window-x old)] [y (window-y old)]
        [w (window-w old)] [h (window-h old)])
    (test-reload-library! '(schevana kits ui))
    (steps 2)
    (let ([new (find-window 'clock)])
      (check "reloading the kit reopens a window of an older kit's ui in its \
              place"
             (and new (not (eq? new old)) (not (memq old (windows)))
                  (= (window-x new) x) (= (window-y new) y)
                  (= (window-w new) w) (= (window-h new) h)
                  (not (window-error new))))
      (when new (close-window! new)))))

;; The REPL rings the bell: for a #\alarm it writes, and for a Tab with
;; nothing to complete.
(let ([w (repl)] [rings 0] [real bell])
  (set! bell (lambda () (set! rings (+ rings 1))))
  (steps 2)
  (type! "(display (integer->char 7))")
  (press! 'return)
  (let ([alarm (wait-for (lambda () (= rings 1)))])
    (type! "(zqxjvwq")
    (press! 'tab)
    (steps 2)
    (set! bell real)
    (close-window! w)
    (check "the REPL rings the bell for #\\alarm and a Tab with nothing to \
            complete"
           (and alarm (= rings 2)))))

(check "frame time is sane" (< *frame-ms* 200))
(printf "frame: ~,1f ms, heap: ~,1f MB\n" *frame-ms*
        (/ (bytes-allocated) 1048576.0))
(test-verdict!)
