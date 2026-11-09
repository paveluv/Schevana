;;; tests/smoke.ss — drive the whole world headlessly with synthetic events.
;;;
;;;   scheme --script tests/smoke.ss [output-dir]
;;;
;;; Writes screenshots into output-dir (default: current directory).

(define *schevana-root*
  (let ([dir (path-parent (path-parent (car (command-line))))])
    (if (string=? dir "") "." dir)))

(load (string-append *schevana-root* "/load.ss"))

(define out-dir
  (if (pair? (command-line-arguments)) (car (command-line-arguments)) "."))

;; Never touch the user's real theme file, nor their apps' permissions.
(set! *theme-file-path* (string-append out-dir "/theme.ss"))
(when (file-exists? *theme-file-path*) (delete-file *theme-file-path*))
(set! *grant-file-path* (string-append out-dir "/permissions.ss"))
(when (file-exists? *grant-file-path*) (delete-file *grant-file-path*))

(define failures 0)

(define-syntax check
  (syntax-rules ()
    [(_ name expr)
     (let ([ok (guard (c [#t (printf "  error: ~a\n" (condition->string c)) #f])
                 expr)])
       (unless ok (set! failures (+ failures 1)))
       (printf "~a ~a\n" (if ok "ok  " "FAIL") name))]))

(define (steps n) (do ([i 0 (+ i 1)]) ((= i n)) (schevana-step! 0)))

;; The screen as it would be drawn now: the same bytes until a frame is asked
;; for or drawn, so that reading pixel after pixel costs one drawing.
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

(define (type! str)
  (for-each (lambda (c) (inject! (list 'text (string c)))) (string->list str)))

(define (press! key . mods) (inject! (list 'key-down key mods)))

(define (repl-of win) (window-ref win 'state))

(define (transcript win)
  (map cdr (reverse (repl-lines (repl-of win)))))

(define (wait-for pred)
  (let ([deadline (+ (now-ms) 3000)])
    (let loop ()
      (cond [(pred) #t]
            [(> (now-ms) deadline) #f]
            [else (schevana-step! 5) (loop)]))))

;; Click (or drag across) a ui widget by its id, with real mouse events.
(define (ui-point win id frac)
  (let ([r (ui-find (window-ref win 'ui) id)])
    (unless r (errorf 'ui-point "no widget ~s" id))
    (let-values ([(cx cy cw ch) (content-rect win)])
      (values (exact (round (+ cx (ui-region-x r) 8
                               (* frac (- (ui-region-w r) 16)))))
              (exact (round (+ cy (ui-region-y r) (/ (ui-region-h r) 2))))))))

;; Wheels a scrolling pane (Settings') until the area id is in view.
(define (scroll-to-ui! win id)
  (let loop ([n 0])
    (let-values ([(x y) (ui-point win id 0.5)]
                 [(cx cy cw ch) (content-rect win)])
      (let ([dy (cond [(> y (+ cy ch -10)) -1] [(< y (+ cy 10)) 1] [else 0])])
        (unless (or (zero? dy) (= n 40))
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

(schevana-boot! 'headless 1280 800)
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
(define p (private-repl))
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
  (check "down and return take the second one"
         (and (string=? "(set-theme-plist!" (repl-input r)) (not (offered))))
  (fresh! "(stp")
  (press! 'tab)
  (steps 1)
  (check "initials find set-theme-plist!"
         (member "set-theme-plist!" (offered)))
  (type! "l")
  (steps 1)
  (check "typing narrows the list"
         (for-all (lambda (n) (string-contains-ci? n "l")) (offered)))
  (let ([lines (length (repl-lines r))])
    (press! 'return)
    (steps 1)
    (check "enter takes the choice instead of evaluating"
           (and (string=? "(set-theme-plist!" (repl-input r))
                (= lines (length (repl-lines r))))))
  (fresh! "(theme 'acc")
  (press! 'tab)
  (steps 1)
  (check "after (theme ' it offers theme keys only"
         (equal? (offered)
                 '("accent" "accent-2" "accent-choices" "panel-accent")))
  (press! 'escape)
  (steps 1)
  (check "escape closes the list" (not (offered)))
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
  ;; Descriptions tell of the code that runs: the text a file had when it
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
    (check "the tree's lib folder is searched by import, the user's not"
           (let ([on-path? (lambda (dir)
                             (exists (lambda (e)
                                       (equal? (if (pair? e) (car e) e) dir))
                                     (library-directories)))])
             (and (on-path? (string-append *schevana-root* "/lib"))
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
  ;; Tab pages through the list; Return or a click on a row accepts.
  (fresh! "(set-")
  (press! 'tab)
  (steps 1)
  (let* ([input (repl-input r)]
         [n (length (or (offered) '()))]
         [last-page (* complete-rows (quotient (- n 1) complete-rows))]
         [sel (lambda () (let ([c (complete-of r)]) (and c (complete-sel c))))])
    (press! 'tab)
    (steps 1)
    (let ([next (sel)])
      (press! 'tab 'shift)
      (press! 'tab 'shift)
      (steps 1)
      (let ([back (sel)])
        (press! 'tab)
        (steps 1)
        (check "tab selects the next page's first row and shift+tab the \
                previous one's, both wrapping, and neither takes one"
               (and (> n (* 2 complete-rows)) (eqv? next complete-rows)
                    (eqv? back last-page) (eqv? (sel) 0)
                    (string=? input (repl-input r)))))))
  ;; Under the pointer a row shows it takes a click: a box, a hand and
  ;; the mouse documentation's words; off the list the REPL's own again,
  ;; and so once the list closes under a still pointer.
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
  (steps 1)
  (let-values ([(cx cy cw ch) (content-rect w)])
    (let* ([c (complete-of r)] [box (complete-box c)]
           [second (car (vector-ref (complete-items c) 1))])
      (click! (+ cx (car box) 20)
              (+ cy (list-ref box 5) (* 3/2 (complete-row-height))))
      (check "a click on a row takes it"
             (and (string=? (string-append "(" second) (repl-input r))
                  (not (offered))))))
  (fresh! "(set-th")
  (press! 'tab)
  (inject! '(wheel 0 -1))
  (steps 1)
  (check "the wheel moves the selection"
         (= 1 (complete-sel (complete-of r))))
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
        ;; as before the clicks: w over the private REPL, the pointer on w
        (focus-window! p)
        (focus-window! w)
        (let-values ([(x y ww wh) (content-rect w)])
          (inject! `(mouse-move ,(+ x 20) ,(+ y 20))))
        (steps 1)
        (check "a click on another window or on the desktop closes the list"
               (and on-clock? (not after-clock) (not (window-at 1200 700))
                    on-desktop? (not after-desktop))))))
  ;; With nothing to add, a popup says so; it goes at the next key, text,
  ;; click or wheel, which then acts as usual.
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
  (check "tab with nothing matching says so"
         (let ([c (complete-of r)])
           (and c (equal? (complete-message c) "No completions")
                (equal? (offered) '()))))
  (png-write-screen (string-append out-dir "/completion-none.png"))
  (type! "y")
  (steps 1)
  (check "typed text closes it and is typed"
         (and (not (complete-of r)) (string=? "(zzqxy" (repl-input r))))
  (press! 'tab)
  (inject! '(wheel 0 1))
  (steps 1)
  (check "so does the wheel" (not (complete-of r)))
  (press! 'tab)
  (steps 1)
  (let ([c (complete-of r)])
    (let-values ([(cx cy cw ch) (content-rect w)])
      (when c (click! (+ cx (car (complete-box c)) 20)
                      (+ cy (cadr (complete-box c)) 10)))
      (check "and a click, even on the popup"
             (and c (not (complete-of r))))))
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
  (let ([owner (list 'field)])
    (complete-open! owner 'symbols 0 (vector))
    (check "a list opened with no items is closed"
           (not (complete-of owner))))
  ;; A REPL's own handler outlives loading the REPL's file again.
  (let ([mine (lambda (win x y button clicks) #f)])
    (hashtable-set! (window-handlers w) 'mouse-down mine)
    (load (source-path "apps/repl.ss"))
    (check "loading the REPL again keeps a REPL's own mouse handler"
           (eq? mine (hashtable-ref (window-handlers w) 'mouse-down #f))))
  (close-window! w))

;; Names match as in the editor e: in segments, each starting where a part
;; of the name starts, in any order.
(let ([world (map (lambda (s) (cons (symbol->string s) #f))
                  (environment-symbols (interaction-environment)))]
      [names (lambda (v) (map car (vector->list v)))])
  (check "stp still finds set-theme-plist!"
         (member "set-theme-plist!" (names (rank-choices "stp" world))))
  (check "a segment starts where a part does: letters in order inside a \
          part do not match"
         (null? (names (rank-choices "sem" '(("set-theme!" . #f))))))
  (check "segments out of order match, after those in order"
         (equal? (names (rank-choices "thse" '(("set-theme" . #f)
                                               ("theme-set" . #f))))
                 '("theme-set" "set-theme")))
  (check "an exact name comes first"
         (equal? "string" (car (names (rank-choices "string" world))))))
(press! #\u 'ctrl)
(type! "(exit)")
(press! 'return)
(check "(exit) closes only the private repl"
       (wait-for (lambda () (not (memq p (windows))))))
(define q (pure-repl))
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
(press! #\p 'ctrl 'shift)
(steps 2)
(check "ctrl+shift+p opens a private repl, titled by its environment"
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

;; A REPL in an environment that is there: a thread's, whose forms run
;; in its vat; its title names it; once dropped, it evaluates nowhere.
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
  ;; Share…: the share dialog, Environments waiting on it
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
      (press! 'escape)   ; the filter lets go
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
  ;; Load…: the desktop's file dialog, Environments waiting on it
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
          ;; on its title bar, as to move it
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
      (let-values ([(x y) (ui-point fd (row 0) 0.5)])
        (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                 `(mouse-up ,x ,y left) `(mouse-down ,x ,y left 2)
                 `(mouse-up ,x ,y left))
        (steps 2))
      (check "a double click goes into a folder"
             (equal? (file-dialog-folder d) sub))
      (press! 'backspace)
      (steps 2)
      (let ([up (file-dialog-folder d)])
        (press! 'left 'alt)
        (steps 2)
        (let ([back (file-dialog-folder d)])
          (press! 'right 'alt)
          (steps 2)
          (check "Backspace goes up, Alt+Left back, Alt+Right forward"
                 (and (equal? up dir) (equal? back sub)
                      (equal? (file-dialog-folder d) dir)))))
      (click-ui! fd (row 1))
      (check "a click selects a file and names it"
             (equal? (file-dialog-name d) "smoke-load.ss"))
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
  (let* ([line (lambda () (+ 3 (ui-region-x (ui-find ui 'split))))]
         [before (line)])
    (define (drag! x0 x1 y clicks)
      (inject! `(mouse-move ,x0 ,y) `(mouse-down ,x0 ,y left ,clicks)
               `(mouse-move ,x1 ,y) `(mouse-up ,x1 ,y left))
      (steps 2))
    (let-values ([(x y) (ui-point w 'split 0.5)])
      (inject! `(mouse-move ,x ,y))
      (steps 1)
      (let ([cursor (window-ref w 'cursor)])
        (drag! x (- x 100) y 1)
        (let ([dragged (line)])
          (drag! (- x 100) -5000 y 1)
          (let ([narrowest (line)])
            (inject! `(mouse-move ,(- (+ x narrowest) before) ,y)
                     `(mouse-down ,(- (+ x narrowest) before) ,y left 1)
                     `(mouse-up ,(- (+ x narrowest) before) ,y left)
                     `(mouse-down ,(- (+ x narrowest) before) ,y left 2)
                     `(mouse-up ,(- (+ x narrowest) before) ,y left))
            (steps 2)
            (check "the line between the tree and the inspector drags, no \
                    further than the panes' least widths; a double click \
                    puts it back"
                   (and (eq? cursor 'resize-ew)
                        (= dragged (- before 100))
                        (= narrowest 280)
                        (= (line) before))))))))
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

;; The launcher menu.
(press! 'f1)
(steps 1)
(check "F1 opens the launcher" (launcher-open?))
(type! "lif")
(steps 1)
(png-write-screen (string-append out-dir "/launcher.png"))
(press! 'return)
(steps 2)
(check "launcher starts Life" (find-window 'life))

;; Apps picked from the desktop's right-click menu open where you clicked.
(define (launch-from-desktop! x y title)
  (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y right 1)
           `(mouse-up ,x ,y right))
  (steps 2)
  (when (launcher-open?)
    (menu-activate!
     (list-index (lambda (e) (and (pair? e) (string=? (car e) title)))
                 (menu-entries *menu*)))
    (steps 2)))
(close-window! (find-window 'life))
(launch-from-desktop! 700 400 "Clock")
(check "an app picked from the desktop menu opens where you clicked"
       (let ([c (find-window 'clock)])
         (and c (= (window-x c) 700) (= (window-y c) 400))))
(close-window! (find-window 'clock))
(launch-from-desktop! 1250 740 "Clock")
(check "and stays on screen near the edge"
       (let ([c (find-window 'clock)])
         (and c (= (+ (window-x c) (window-w c)) (screen-w))
              (= (+ (window-y c) (window-h c))
                 (- (screen-h) (taskbar-height))))))
(close-window! (find-window 'clock))

;; Full screen, and the host window's icon.
(press! 'f11)
(steps 1)
(check "F11 switches to full screen" (fullscreen?))
(press! 'f11)
(steps 1)
(check "and back" (not (fullscreen?)))
(check "the app icon draws"
       (bytevector? (drawing->bytes 64 64 1 (lambda () (draw-app-icon 64)))))

;; An app in a sandbox that asks (services/grant.ss): the launcher shows
;; what it requests first (desktop/permissions.ss), and Settings changes
;; the answer later.
(let ([launch! (lambda ()
                 (launch-app-asking!
                  (find (lambda (a) (eq? (app-name a) 'sketch)) *apps*))
                 (steps 2))])
  (launch!)
  (let ([d (focused-window)])
    (check "the launcher asks before Sketch opens: what it requests, each \
            ticked"
           (and (eq? (window-ref d 'permissions #f) 'sketch)
                (not (find-window 'sketch))
                (equal? (window-ref d 'ticked #f) '(window draw))))
    (click-ui! d '(permissions draw))   ; unticked
    (click-ui! d '(permissions allow))
    (steps 2)
    (let ([s (find-window 'sketch)])
      (check "Allow decides as ticked and saves it, and Sketch opens; what \
              it may not do crashes its window, which says where to allow it"
             (and s (not (memq d (windows)))
                  (let-values ([(ok no) (grant-of 'sketch)])
                    (and (equal? ok '(window)) (equal? no '(draw))))
                  (file-exists? *grant-file-path*)
                  (window-error s)
                  (grant-needed? (cdr (window-error s)))))
      (let ([st (settings)])
        (settings-st-tab-set! (window-ref st 'state) 'permissions)
        (invalidate! st)
        (steps 2)
        (click-ui! st '(grant sketch draw))
        (steps 2)
        (let ([s2 (find-window 'sketch)])
          (check "Settings' Permissions allows it: Sketch opens again where \
                  it was, and draws"
                 (and s2 (not (eq? s2 s)) (not (memq s (windows)))
                      (not (window-error s2))
                      (= (window-x s2) (window-x s))
                      (= (window-y s2) (window-y s))
                      (let-values ([(ok no) (grant-of 'sketch)])
                        (and (equal? ok '(window draw)) (null? no))))))
        (close-window! st)
        (close-window! (find-window 'sketch)))
      (launch!)
      (check "decided, the launcher opens it without asking"
             (let ([s3 (find-window 'sketch)])
               (and s3 (eq? (focused-window) s3)
                    (not (exists (lambda (w) (window-ref w 'permissions #f))
                                 (windows))))))
      (close-window! (find-window 'sketch))))
  ;; Environments shows the bundles, and Permissions… changes them.
  (let* ([e (envs)] [v (window-ref e 'state)] [ui (window-ref e 'ui)]
         [show! (lambda (env)
                  (envs-select! v env)
                  (invalidate! e)
                  (steps 2))])
    (show! (grant-apps-env))
    (check "Environments on /apps lists every bundle, and has no Permissions…"
           (and (for-all (lambda (b) (ui-find ui (list '(envs bundles) b)))
                         (map car grant-bundles))
                (not (ui-find ui '(envs permissions)))))
    (show! (grant-env 'clock))
    (click-ui! e '(envs permissions))
    (check "on Clock, what it requests; Permissions… does nothing: the \
            table allows it"
           (and (ui-find ui '((envs bundles) timers))
                (not (ui-find ui '((envs bundles) toasts)))
                (not (window-modal-child e))))
    (let ([old (grant-env 'sketch)])
      (show! old)
      (click-ui! e '(envs permissions))
      (let ([d (window-modal-child e)])
        (check "on Sketch, Permissions… asks over Environments, which waits"
               (and d (eq? (focused-window) d)
                    (eq? (window-ref d 'permissions #f) 'sketch)))
        (click-ui! d '(permissions draw))   ; unticked
        (click-ui! d '(permissions allow))
        (steps 2)
        (check "Allow decides, and Environments stays on Sketch, whose \
                sandbox was made again"
               (and (not (memq d (windows))) (not (window-modal-child e))
                    (env-dropped? old)
                    (eq? (envs-view-selected v) (grant-env 'sketch))
                    (eq? (grant-state 'sketch 'draw) 'denied)))))
    (click-ui! e '((envs bundles) draw))
    (check "a press on a bundle shows only its names"
           (and (equal? (envs-view-names-query v) "Draw in its windows")
                (eq? (envs-view-names v) 'shared)))
    (click-ui! e '((envs bundles) draw))
    (check "and again, all"
           (equal? (envs-view-names-query v) ""))
    (grant-decide! 'sketch '(window draw) '())
    (close-window! e)))

;; Theme changes are live.
(set-theme! 'accent #xff9e64)
(sketch)
(monitor)
(tile-windows!)
(steps 3)
(png-write-screen (string-append out-dir "/tiled.png"))
(reset-theme!)

;; Window styles: the frame, its buttons and their actions come from the style.
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
            15-pixel title strip and no buttons"
           (and (= l 4) (= r 4) (= b 4) (= t 17) (null? (frame-regions w)))))
  (inject! '(mouse-move 300 147) '(mouse-down 300 147 right 1)
           '(mouse-up 300 147 right))
  (steps 2)
  (check "so the right-button menu on its title closes it"
         (and (menu-open?)
              (find (lambda (e) (and (pair? e) (string=? (car e) "Close")))
                    (menu-entries *menu*))))
  (close-menu!))

(check "genera style draws" (style-scene! 'genera))
(let ([w (open-window "Delta" 'size '(300 . 150) 'pos '(200 . 140))])
  (let-values ([(l t r b) (frame-insets w)])
    (check "genera has a 2-pixel border, a 4-pixel margin and the label at \
            the bottom"
           (and (= l 6) (= t 6) (= r 6) (= b 23))))
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

;; A style, theme, wallpaper or app defined again keeps its place and takes
;; the new definition.
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

;; a palette is a change to the style chosen; the wallpaper is the style's
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
;; A theme saved before Amiga and Workbench were removed still loads.
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
;; A style with its own palette and fonts, and few options: the text size
;; is not one.
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
;; An old, flat theme file shows as its style, its choices your changes.
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
;; The text size is on the Fonts tab: pinned, it holds in every style
;; that honors it, and test-serif does not.
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
;; A slider held, a right click on another window and both buttons let go
;; there: back over Settings, the pointer drags nothing.
(click-ui! s '(tab colors))
(click-ui! s '(color accent))
(move-window! s 40 (window-y s))   ; the other window beside it, not over
(steps 1)
(let ([other (open-window "Other" 'size '(160 . 100)
                          'pos (cons (min 1100 (+ (window-x s) (window-w s) 10))
                                     600))])
  (steps 1)
  (let-values ([(x0 y) (ui-point s 'lightness 0.5)]
               [(x1 y1) (ui-point s 'lightness 0.1)]
               [(ox oy ow oh) (content-rect other)])
    (let ([ox (+ ox 20)] [oy (+ oy 20)])
      (inject! `(mouse-move ,x0 ,y) `(mouse-down ,x0 ,y left 1)
               `(mouse-move ,ox ,oy) `(mouse-down ,ox ,oy right 1)
               `(mouse-up ,ox ,oy right) `(mouse-up ,ox ,oy left))
      (steps 2)
      (let ([accent (theme 'accent)])
        (inject! `(mouse-move ,x1 ,y))
        (steps 2)
        (check "a slider let go over another window, after a right click \
                there, follows the pointer no more"
               (and (eq? (window-at ox oy) other)
                    (= accent (theme 'accent)))))))
  (close-window! other))
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
  (let ([r (ui-find tui id)])
    (values (+ (ui-region-x r) (/ (ui-region-w r) 2))
            (+ (ui-region-y r) (/ (ui-region-h r) 2)))))

;; Clicks the open menu's entry that starts with label, where menu-areas
;; puts it.
(define (menu-click! label)
  (let* ([es (menu-entries *menu*)]
         [i (list-index (lambda (e)
                          (and (pair? e) (string-prefix? label (car e))))
                        es)]
         [a (and i (assv i (placed-menu-areas *menu*)))])
    (unless a (errorf 'menu-click! "no entry ~s" label))
    (let ([x (+ (cadr a) 30)] [my (round (+ (caddr a) (/ (list-ref a 4) 2)))])
      (inject! `(mouse-move ,x ,my) `(mouse-down ,x ,my left 1)
               `(mouse-up ,x ,my left))
      (steps 2))))

(check "Tasks opens on the Board with the seed tasks"
       (and (not (window-error tw)) (= (length tasks-seed) (length *tasks*))
            (eq? (tasks-view-mode tv) 'board) (card-of 16)))
(check "Tasks is single-instance" (eq? tw (tasks)))
(shot "board")
(check "a column draws and registers only the cards in view"
       (let ([todo (column-of 'todo)])
         (< 0 (length (filter card-of todo)) (length todo))))
(let ([at (lambda ()
            (map (lambda (id)
                   (let ([r (ui-find tui id)]) (list (ui-region-x r)
                                                     (ui-region-y r))))
                 '(new (filter tag) done clear (column todo))))])
  (let ([before (at)])
    (set-task! 13 'tags '("render" "a-much-longer-tag-name"))
    (steps 2)
    (let ([long (at)])
      (set-task! 13 'tags '("render" "gpu"))
      (steps 2)
      (check "a long tag moves nothing in the toolbar, nor the board below"
             (equal? before long)))))

;; n, then typing at once: nothing is lost and the n is not typed.
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
(press! 'left 'shift) (press! 'left 'shift) (press! 'left 'shift)
(press! #\c 'ctrl)
(steps 1)
(check "Shift+Left selects and Ctrl+C copies" (equal? (clipboard-get) "bar"))
(press! 'end)
(press! #\v 'ctrl)
(steps 1)
(check "End and Ctrl+V paste" (equal? (task-title nt) "Fix the toolbarbar"))
(press! 'backspace) (press! 'backspace) (press! 'backspace)
(press! #\a 'ctrl)
(type! "Fix the menu")
(steps 2)
(check "Backspace, Ctrl+A and typing over everything: the title and the card"
       (and (equal? (task-title nt) "Fix the menu") (card-of nt)))
(let* ([r (ui-find tui 'title)]
       [a (car (ui-text-box-areas (ui-region-x r) (ui-region-y r)
                                  (ui-region-w r) (ui-region-h r) '(large)))]
       [x (+ (list-ref a 1) (text-width "Fix the me" 'heading))]
       [y (+ (list-ref a 2) 8)])
  (tasks-click! x y 'left 1)
  (tasks-click! x y 'left 2)
  (check "a double click selects a word"
         (equal? (edit-selection (edit)) "menu")))
(shot "title")

;; Tab to Status; its menu by keys. Priority by mouse.
(press! 'tab)
(steps 1)
(check "Tab goes from the title to Status" (equal? (focus-id) 'status))
(press! 'return)
(steps 1)
(check "Return opens Status's menu on the current entry"
       (and (menu-open?) (= 0 (menu-sel *menu*))))
(shot "dropdown")
(press! 'down)
(press! 'return)
(steps 2)
(check "Down and Return: In progress, at the end of its column"
       (and (eq? (task-status nt) 'doing)
            (eq? nt (car (last-pair (column-of 'doing))))))
(click-ui! tw 'priority)
(check "a click opens Priority's menu" (menu-open?))
(menu-click! "Urgent")
(check "and picks Urgent" (eq? (task-priority nt) 'urgent))

(click-ui! tw 'assignee)
(type! "Ada")
(press! 'return)
(steps 2)
(check "the assignee is typed, and Return leaves the field"
       (and (equal? (task-assignee nt) "Ada") (not (focus-id))))

;; The due date: the calendar by mouse and by keys.
(define (calendar-open?)
  (exists (lambda (r) (let ([id (ui-region-id r)])
                        (and (pair? id) (eq? (car id) 'due) (pair? (cdr id))
                             (eq? (cadr id) 'day))))
          (ui-state-regions tui)))
(click-ui! tw 'due)
(check "a click on the date opens the calendar" (calendar-open?))
(shot "calendar")
(define day20 (let ([d (ui-today)]) (ui-date->day (list (car d) (cadr d) 20))))
(click-ui! tw (list 'due 'day day20))
(check "a day picked is the due date, and the calendar closes"
       (and (equal? (task-due nt) (ui-day->date day20)) (not (calendar-open?))))
(click-ui! tw 'due)
(press! 'right) (press! 'right) (press! 'return)
(steps 2)
(check "reopened, Right Right Return: two days later"
       (equal? (task-due nt) (ui-day->date (+ day20 2))))
(click-ui! tw 'due)
(press! 'page-down) (press! 'escape)
(steps 2)
(check "reopened, Escape: unchanged and closed"
       (and (equal? (task-due nt) (ui-day->date (+ day20 2)))
            (not (calendar-open?))))
(click-ui! tw 'assignee)
(press! 'tab)
(steps 1)
(check "Tab goes from the assignee to the date" (equal? (focus-id) 'due))
(press! 'delete)
(steps 1)
(check "and Delete clears it" (not (task-due nt)))
(press! 'escape)

;; Tags: Return and a comma add, Backspace and × remove.
(click-ui! tw '(tags field))
(type! "perf")
(press! 'return)
(type! "ui,")
(steps 2)
(check "tags: Return and a comma add them"
       (equal? (task-tags nt) '("perf" "ui")))
(press! 'backspace)
(steps 2)
(check "Backspace in the empty field removes the last tag"
       (equal? (task-tags nt) '("perf")))
(click-ui! tw '(tags remove 0))
(check "and a chip's × the others" (null? (task-tags nt)))
(clipboard-set! "alpha, beta,gamma")
(press! #\v 'ctrl)
(steps 2)
(check "a paste with commas adds a tag for each, and keeps the rest typed"
       (and (equal? (task-tags nt) '("alpha" "beta"))
            (equal? (tasks-view-tag-draft tv) "gamma")))
(set-task! nt 'tags '())
(tasks-view-tag-draft-set! tv "")
(clipboard-set! (apply string-append
                       (map (lambda (i) (format "at f~a (x.ss:~a), " i (* 7 i)))
                            (iota 4000))))
(press! #\v 'ctrl)
(steps 2)
(check "a pasted log of 4,000 comma-separated frames: its first 64 become \
        tags, and Tasks still draws"
       (and (not (window-error tw)) (= (length (task-tags nt)) 64)
            (equal? (car (task-tags nt)) "at-f0-(x.ss:0)")))
(set-task! nt 'tags '())
(tasks-view-tag-draft-set! tv "")
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

;; Drag and drop. The new task scrolled To do to its end: back to the top.
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
;; Drags t's card to (x, y) of the content, a step after each of three
;; moves; Escape before the release when asked.
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
;; two columns, ends it, the card where it was and no menu, and once both
;; buttons are up nothing is held. With the right button pressed first,
;; the left one's release still ends a drag.
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

;; Board keys.
(let-values ([(x y) (region-center (list 'card 13))])
  (tasks-click! x y))
(check "a click on a card selects it" (eq? (selected) (find-task 13)))
(press! 'down)
(steps 1)
(check "Down selects the next card" (eq? (selected) (find-task 14)))
(press! 'right 'shift)
(steps 1)
(check "Shift+Right moves it to the next status"
       (eq? (task-status (find-task 14)) 'doing))
(let ([before (list-index (lambda (t) (eq? t (find-task 14)))
                          (column-of 'doing))])
  (press! 'up 'shift)
  (steps 1)
  (check "Shift+Up moves it up its column"
         (= (list-index (lambda (t) (eq? t (find-task 14))) (column-of 'doing))
            (- before 1))))
(press! 'escape)
(steps 1)
(check "Escape lets go of the selection" (not (selected)))

;; The List.
(type! "v")
(steps 2)
(check "v switches to the List" (eq? (tasks-view-mode tv) 'list))
(define (rows) (tasks-rows tv (tasks-visible tv)))
(click-ui! tw '(table header priority))
(check "a header sorts by it: urgent first"
       (eq? (task-priority (car (rows))) 'urgent))
(shot "list")
(click-ui! tw '(table header priority))
(check "again: low first" (eq? (task-priority (car (rows))) 'low))
(click-ui! tw '(table header priority))
(check "again: board order" (not (tasks-view-sort tv)))
;; A real drag on the line between Status and Priority widens Status; the
;; cells follow; a double click there sets back its width.
(let ([draw-cell tasks-draw-cell] [drawn '()])
  (define (status-w)
    (let ([r (ui-find tui '(table header status))]) (ui-region-w r)))
  (define (cells-x)   ; the first row's cells, by key, as drawn
    (set! drawn '())
    (invalidate! tw)
    (steps 1)
    (reverse drawn))
  (set! tasks-draw-cell
        (lambda (x y w h flags t key today)
          (when (eq? t (car (rows))) (set! drawn (cons (cons key x) drawn)))
          (draw-cell x y w h flags t key today)))
  (let*-values ([(before) (cells-x)] [(w0) (status-w)]
                [(x y) (region-center '(table handle status))]
                [(cx cy cw ch) (content-rect tw)]
                [(x y) (values (+ cx (round x)) (+ cy (round y)))])
    (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
             `(mouse-move ,(+ x 40) ,y) `(mouse-up ,(+ x 40) ,y left))
    (steps 2)
    (let* ([after (cells-x)] [w1 (status-w)]
           [moved (lambda (key) (- (cdr (assq key after))
                                   (cdr (assq key before))))])
      (inject! `(mouse-move ,(+ x 40) ,y) `(mouse-down ,(+ x 40) ,y left 1)
               `(mouse-up ,(+ x 40) ,y left)
               `(mouse-down ,(+ x 40) ,y left 2) `(mouse-up ,(+ x 40) ,y left))
      (steps 2)
      (set! tasks-draw-cell draw-cell)
      (check "a drag on the line after Status widens it by as much; the \
              cells after it follow, those before it stay; a double click \
              there sets back its width"
             (and (= w1 (+ w0 40))
                  (equal? (map car before) (map car after))
                  (let loop ([ks (map car before)] [by 0])
                    (or (null? ks)
                        (and (= by (moved (car ks)))
                             (loop (cdr ks)
                                   (if (eq? (car ks) 'status) 40 by)))))
                  (> (length (memq 'status (map car before))) 1)
                  (= w0 (status-w))
                  (not (tasks-view-sort tv)))))))
(press! 'down) (press! 'down)
(steps 1)
(check "Down twice selects the second row" (eq? (selected) (cadr (rows))))
(press! 'return)
(steps 1)
(check "Return edits its title" (eq? (focus-id) 'title))
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
(check "Clear shows every task again"
       (and (equal? "" (tasks-view-query tv))
            (= (length *tasks*) (length (tasks-visible tv)))))
(click-ui! tw '(filter kind))
(menu-click! "Bug")
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
(click-ui! tw 'done)
(type! "v")
(type! "v")
(steps 2)
(check "Show done off: no Done column"
       (and (not (tasks-view-done? tv)) (ui-find tui '(column todo))
            (not (ui-find tui '(column done)))))
(let-values ([(x y) (region-center (list 'card 7))])
  (tasks-click! x y))
(press! 'right 'shift)
(steps 2)
(check "Shift+Right into the hidden Done selects the task next to it"
       (and (eq? (task-status (find-task 7)) 'done)
            (eq? (selected) (find-task 16))))
(move-task! 7 'review 16)
(press! 'escape)
(steps 1)
(click-ui! tw 'done)

;; The context menu, Duplicate and Move to; Delete and its dialog.
(column-home! 'todo)
(let-values ([(x y) (region-center (list 'card 13))])
  (tasks-click! x y 'right 1))
(check "a right click on a card opens its menu" (menu-open?))
(menu-click! "Duplicate")
(define copy (selected))
(check "Duplicate: a copy right after it, selected"
       (and (= (+ 2 (length tasks-seed)) (length *tasks*))
            (eq? (next-to 13) copy)
            (equal? (task-title copy)
                    (string-append (task-title (find-task 13)) " (copy)"))))
(let-values ([(x y) (region-center (list 'card (task-id copy)))])
  (tasks-click! x y 'right 1))
(menu-click! "Move to Done")
(check "Move to Done" (eq? (car (last-pair (column-of 'done))) copy))
(click-ui! tw 'description)
(click-ui! tw 'delete)
(check "the dialog takes the keyboard from the field under it"
       (and (ui-find tui '(confirm 1)) (not (focus-id))))
(press! 'escape)
(steps 2)
(press! 'delete)
(steps 2)
(check "Delete asks first" (ui-find tui '(confirm 1)))
(shot "dialog")
(press! 'escape)
(steps 2)
(check "Escape cancels" (and (memq copy *tasks*) (not (ui-find tui 'confirm))))
(press! 'delete)
(steps 1)
(press! 'return)
(steps 2)
(check "Delete and Return: gone, and the task next to it selected"
       (and (not (memq copy *tasks*)) (selected)))
(let ([t (add-task! (apply string-append (make-list 200 "very long title "))
                    'status 'review)]
      [orig ui-draw-dialog] [said #f])
  (set! ui-draw-dialog   ; the lines the dialog's message shows
        (lambda (x y w h flags title message)
          (set! said (ui-dialog-lines
                      message
                      (caddr (cdr (assq 'message
                                        (ui-dialog-areas x y w h '()))))))
          (orig x y w h flags title message)))
  (steps 1)
  (let-values ([(x y) (region-center (list 'card (task-id t)))])
    (tasks-click! x y))
  (press! 'delete)
  (steps 2)
  (set! ui-draw-dialog orig)
  (let ([b (ui-find tui '(confirm 1))])
    (let-values ([(w h) (window-content-size tw)])
      (check "a very long title makes the dialog no taller than a few lines: \
              its buttons stay well inside the window, and it still says \
              that this cannot be undone"
             (and (< (+ (ui-region-y b) (ui-region-h b)) (* 3/4 h))
                  (string-suffix? "undone." (car (last-pair said)))))))
  (press! 'escape)
  (delete-task! t)
  (steps 2))

;; A tooltip shows after the pointer rests.
(let*-values ([(x y) (region-center 'new)]
              [(cx cy cw ch) (content-rect tw)]
              [(px py) (values (+ cx x 12 6) (+ cy y 20 6))])
  (define (pixel)
    (screen-pixel (exact (floor (* *scale* px)))
                  (exact (floor (* *scale* py)))))
  (let ([before (pixel)])
    (inject! `(mouse-move ,(+ cx x) ,(+ cy y)))
    (steps 2)
    (check "a tooltip shows when the pointer rests on New task"
           (and (= before (pixel))
                (wait-for (lambda () (not (= before (pixel)))))))
    (shot "tooltip")))
(let*-values ([(x y) (region-center 'search)]
              [(cx cy cw ch) (content-rect tw)]
              [(px py) (values (+ cx x 12 6) (+ cy y 20 6))])
  (define (pixel)
    (screen-pixel (exact (floor (* *scale* px)))
                  (exact (floor (* *scale* py)))))
  (tasks-click! x y)
  (type! "x")
  (steps 2)
  (let ([before (pixel)])
    (check "but none over the field being typed in"
           (and (eq? (focus-id) 'search)
                (not (wait-for (lambda () (not (= before (pixel))))))))
    (press! 'escape)
    (click-ui! tw 'clear)))

;; A press, key or text uses the tooltip up until the pointer moves: a new
;; task's title typed with the pointer left on New task shows no tooltip
;; while the typing pauses; once the pointer moves and rests, it shows.
(let-values ([(x y) (region-center 'new)] [(cx cy cw ch) (content-rect tw)])
  (let ([tips 0] [orig ui-draw-tooltip])
    (set! ui-draw-tooltip
          (lambda args (set! tips (+ tips 1)) (apply orig args)))
    (tasks-click! x y)
    (type! "Typed under a resting pointer")
    (steps 2)
    (let ([t (selected)])
      (check "after a click and typing, no tooltip while the pointer rests"
             (and (eq? (focus-id) 'title)
                  (not (wait-for (lambda () (> tips 0))))))
      (inject! `(mouse-move ,(+ cx (round x) 2) ,(+ cy (round y))))
      (check "and one once the pointer moves and rests"
             (wait-for (lambda () (> tips 0))))
      (set! ui-draw-tooltip orig)
      (press! 'escape)
      (delete-task! t)
      (steps 2))))

;; Keys that scroll the List bring other rows under the resting pointer,
;; and still no tooltip: the pointer has not moved since the keys.
(let ([extra (map (lambda (i)
                    (add-task! (format "Row ~a, a title the List cuts: ~a" i
                                       (make-string 80 #\W))))
                  (iota 30))]
      [tips 0] [orig ui-draw-tooltip])
  (type! "v")
  (steps 2)
  (let-values ([(x y) (region-center '(table row 3))]
               [(cx cy cw ch) (content-rect tw)])
    (inject! `(mouse-move ,(+ cx (round x)) ,(+ cy (round y))))
    (steps 2)
    (set! ui-draw-tooltip
          (lambda args (set! tips (+ tips 1)) (apply orig args)))
    (do ([i 0 (+ i 1)]) ((= i 40)) (press! 'down) (steps 1))
    (check "keys that scroll the List under a resting pointer show no row's \
            tooltip"
           (and (> (car (ui-memo tui '(table body) '(0 . 0))) 0)
                (not (wait-for (lambda () (> tips 0))))))
    (set! ui-draw-tooltip orig))
  (for-each delete-task! extra)
  (type! "v")
  (type! "v")
  (steps 2))

;; A title cut inside a long word: the card's tooltip tells it, and the
;; details' title, scrolled to the caret, shows its start again once left.
(let ([long (add-task! (string-append "A " (make-string 80 #\W))
                       'status 'review)])
  (steps 2)
  (check "a card whose title is cut, even inside a long word, has it as a \
          tooltip"
         (equal? (ui-region-tip (card-of long)) (task-title long)))
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

;; What has the keyboard is in view. Enter, a double click and the menu's
;; Open focus the title of a task whose details are scrolled away; Return
;; in Add an item, and typing at the end of a long description, follow
;; the field and its caret; a new card follows its growing title.
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
        (menu-click! "Open")
        (check "Enter, a double click and Open show the title they focus, \
                scrolled out of the details"
               (and away enter double (eq? (focus-id) 'title)
                    (shown? 'title)))))))
(press! 'escape)
(click-ui! tw 'new-item)
(for-each (lambda (s) (type! s) (press! 'return))
          '("Item 1" "Item 2" "Item 3" "Item 4" "Item 5"))
(steps 2)
(check "Return in Add an item keeps it in view as the items push it down"
       (and (eq? (focus-id) 'new-item) (shown? 'new-item)))
(set-task! 7 'checklist (list-head (task-checklist (find-task 7)) 5))
(press! 'escape)
(let-values ([(w h) (window-content-size tw)]
             [(t) (car (column-of 'review))])
  (define text (task-description t))
  (resize-window! tw 1100 440)
  (steps 2)
  (let-values ([(x y) (region-center (list 'card (task-id t)))])
    (tasks-click! x y))
  (click-ui! tw 'description)
  (press! 'end 'ctrl)
  (do ([i 0 (+ i 1)]) ((= i 12)) (press! 'return) (type! "more text"))
  (steps 2)
  (let* ([r (ui-find tui 'description)]
         [a (car (apply ui-text-box-areas
                        (append (ui-region-frame r) '(()))))]
         [lh (font-line-height 'ui)] [text (task-description (selected))]
         [lay (edit-layout-of #f text (list-ref a 3) #f
                              (lambda (s) (text-width s 'ui)) #f)]
         [top (- (+ (list-ref a 2)
                    (* lh (edit-row-at lay (edit-caret (edit)))))
                 (ui-memo tui 'description 0))])
    (check "typing at the end of a long description keeps its caret in view"
           (<= (ui-region-y r) top (+ top lh)
               (+ (ui-region-y r) (ui-region-h r)))))
  (press! 'escape)
  (press! 'escape)
  (steps 1)
  (set-task! t 'description text)
  (resize-window! tw w h)
  (steps 2))
(type! "n")
(type! (make-string 150 #\W))
(steps 2)
(check "a new card follows its title as it grows past the column's end"
       (shown? (list 'card (task-id (selected)))))
(press! 'escape)
(delete-task! (selected))
(steps 2)

;; Each task's details start at their top: a description wheeled down is
;; not wheeled in the next task. Tab leaves a gap at the details' edges,
;; so a focus ring shows whole.
(let* ([lines (lambda (what)
                (apply string-append
                       (map (lambda (i) (format "~a ~a.\n" what i))
                            (iota 40))))]
       [a (add-task! "Wheeled" 'status 'review 'description (lines "Para"))]
       [b (add-task! "Next" 'status 'review 'description (lines "Other"))])
  (steps 2)
  (let-values ([(x y) (region-center (list 'card (task-id a)))])
    (tasks-click! x y))
  (let-values ([(x y) (region-center 'description)]
               [(cx cy cw ch) (content-rect tw)])
    (inject! `(mouse-move ,(+ cx (round x)) ,(+ cy (round y))) '(wheel 0 -4))
    (steps 2))
  (let ([wheeled (ui-memo tui 'description 0)])
    (let-values ([(x y) (region-center (list 'card (task-id b)))])
      (tasks-click! x y))
    (check "a description wheeled down in one task starts at its top in the \
            next"
           (and (> wheeled 0) (eq? (selected) b)
                (= 0 (ui-memo tui 'description 0)))))
  (delete-task! a)
  (delete-task! b)
  (steps 2))
(tasks-select! tv (find-task 11))   ; its card is scrolled out of view
(invalidate! tw)
(steps 2)
(click-ui! tw 'title)
(define (ring-inside? id)   ; the focus ring reaches 4 px out
  (let ([r (ui-find tui id)] [d (ui-find tui 'details)])
    (and (>= (- (ui-region-y r) 4) (ui-region-y d))
         (<= (+ (ui-region-y r) (ui-region-h r) 4)
             (+ (ui-region-y d) (ui-region-h d))))))
(define (tab-to! id . mods)
  (let loop ([n 0])
    (unless (or (= n 40) (eq? (focus-id) id))
      (apply press! 'tab mods)
      (steps 2)
      (loop (+ n 1)))))
(tab-to! 'delete)
(let ([last (ring-inside? 'delete)])
  (tab-to! 'status 'shift)
  (check "Tab and Shift+Tab bring a field into view with its focus ring"
         (and last (eq? (focus-id) 'status) (ring-inside? 'status))))
(tab-to! 'title 'shift)
(check "Shift+Tab up onto a title of three rows shows all of it"
       (and (eq? (focus-id) 'title)
            (>= (cadddr (ui-region-frame (ui-find tui 'title)))
                (* 3 (font-line-height 'heading)))
            (ring-inside? 'title)))
(press! 'escape)
(steps 1)

;; Looks: the tag field draws no box inside the chip input's; a filter
;; whose tag no task has any more still shows it; a disabled button does
;; not light up under the pointer; a cut title says so, and so does a cut
;; checklist item or List row with a tooltip.
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
(click-ui! tw '(filter tag))
(menu-click! "genera")
(set-task! 8 'tags '("style"))
(steps 2)
(let ([r (ui-find tui '(filter tag))])
  (check "a Tag filter whose tag no task has any more still shows it"
         (let loop ([ps (pixels-of (+ (ui-region-x r) 10) (+ (ui-region-y r) 6)
                                   (- (ui-region-w r) 40)
                                   (- (ui-region-h r) 12))]
                    [seen '()])
           (cond [(> (length seen) 2) #t]
                 [(null? ps) #f]
                 [else (loop (cdr ps) (if (memv (car ps) seen)
                                          seen
                                          (cons (car ps) seen)))]))))
(set-task! 8 'tags '("style" "genera"))
(click-ui! tw 'clear)
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
  (type! "v")
  (steps 2)
  (check "and so does a List row whose title is cut"
         (let ([i (list-index (lambda (t) (eq? t long)) (rows))])
           (equal? (ui-region-tip (ui-find tui (list 'table 'row i)))
                   (task-title long))))
  (type! "v")
  (type! "v")
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
(move-task! rt 'done)
(steps 1)
(check "move-task!" (eq? (car (last-pair (column-of 'done))) rt))
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
;; A long word in the search: the empty state's message draws nothing past
;; its width.
(let ([drawn '()] [label ui-draw-label] [text draw-text] [in #f])
  (set! ui-draw-label   ; a wrapped label's box, while it draws
        (lambda (x y w h flags str)
          (fluid-let ([in (and (memq 'wrap flags) (list x w))])
            (label x y w h flags str))))
  (set! draw-text
        (lambda (x y str . more)
          (when in
            (set! drawn (cons (list x (text-width str (cadr more)) in)
                              drawn)))
          (apply text x y str more)))
  (type! "/")
  (type! (make-string 150 #\q))
  (press! 'escape)
  (steps 2)
  (set! ui-draw-label label)
  (set! draw-text text)
  (check "a long word in the search: the empty state's message stays \
          within its width"
         (and (pair? drawn)
              (for-all (lambda (d)
                         (let ([x (car d)] [lx (car (caddr d))])
                           (and (>= x (- lx 0.5))
                                (<= (+ x (cadr d))
                                    (+ lx (cadr (caddr d)) 0.5)))))
                       drawn)))
  (click-ui! tw 'empty-clear))
(for-each delete-task! (map task-id *tasks*))
(steps 2)
(check "no tasks at all: an empty state that makes one"
       (and (null? *tasks*) (ui-find tui 'empty-new)))
(shot "empty")
(tasks-reset!)

;; Dependencies. The details: what a task waits for, chips a × removes,
;; Add's menu of what makes no cycle; what waits for it; a chip selects.
(resize-window! tw 1205 660)
(tasks-select! tv (find-task 14))
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
              (or (not card) (equal? (ui-region-tip card) tip)))))
(click-ui! tw '(blocked-by add))
(let ([labels (if (menu-open?)
                  (map car (filter pair? (menu-entries *menu*)))
                  '())]
      [offered? (lambda (labels id)
                  (exists (lambda (l) (string-prefix? (format "TASK-~a " id) l))
                          labels))])
  (check "Add opens a menu of the tasks it may wait for: none that waits for \
          it, nor itself, nor what it waits for already, nor a done one"
         (and (offered? labels 9) (offered? labels 19)
              (not (exists (lambda (id) (offered? labels id))
                           '(22 14 33 1))))))
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
(check "the REPL refuses a cycle, and the error names it"
       (and (equal? (guard (c [#t (condition->string c)])
                      (set-task! 9 'blocked-by '(16 22)))
                    "Exception in set-task!: TASK-9 would wait for itself: \
                     TASK-9 → TASK-22 → TASK-14 → TASK-33 → TASK-9 (each \
                     waits for the next)")
            (null? (task-blocked-by (find-task 9)))))
(set! *toasts* '())
(move-task! 22 'done)
(steps 1)
(check "a blocked task moved to Done: it is, and a toast says what it waits \
        for"
       (and (eq? 'done (task-status (find-task 22)))
            (exists (lambda (t)
                      (equal? (vector-ref t 1)
                              "TASK-22 is done, though it waits for TASK-14"))
                    *toasts*)))
(move-task! 22 'todo 15)
(set! *toasts* '())
(let ([t (add-task! "Born done" 'status 'done 'blocked-by '(10))])
  (check "a task added done while it waits: the same toast"
         (exists (lambda (x)
                   (equal? (vector-ref x 1)
                           (format "~a is done, though it waits for TASK-10"
                                   (task-label t))))
                 *toasts*))
  (delete-task! t)
  (set! *toasts* '()))

;; With many tasks, Add's menu shows what fits on the screen, then how many
;; more, which typing narrows; the task an id typed names comes first. A
;; choice the REPL made into a cycle while the menu was open is refused,
;; and a plain toast says so.
(let* ([more (sort (lambda (a b) (< (task-id a) (task-id b)))   ; board order
                   (map (lambda (i) (add-task! (format "Filler ~a" i)))
                        (iota 60)))]
       [last (car (last-pair more))]
       [labels (lambda () (map car (filter pair? (menu-entries *menu*))))]
       [red? (lambda ()
               (exists (lambda (x) (eq? (vector-ref x 2) 'red)) *toasts*))])
  (set-task! (car more) 'title (format "About ~a" (task-label last)))
  (tasks-select! tv (find-task 14))
  (invalidate! tw)
  (steps 2)
  (click-ui! tw '(blocked-by add))
  (let ([n (length (tasks-blocker-choices (find-task 14)))] [l (labels)])
    (let-values ([(x y w h) (menu-geometry *menu*)])
      (check "with many tasks, Add's menu fits on the screen, its last entry \
              saying how many more"
             (and (<= (+ y h) (screen-h)) (< 10 (length l) n)
                  (equal? (car (last-pair l))
                          (format "… ~a more: type to narrow"
                                  (- n (length l) -1)))))))
  (type! (task-label last))
  (steps 1)
  (check "an id typed: the task it names first, then what mentions it"
         (equal? (labels)
                 (list (format "~a  ~a" (task-label last) (task-title last))
                       (format "~a  About ~a" (task-label (car more))
                               (task-label last)))))
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
                        (list (format "~a would wait for itself: ~a → ~a → ~a \
                                       (each waits for the next)"
                                      (task-label a) (task-label a)
                                      (task-label b) (task-label a)))))))
  (for-each delete-task! more)
  (set! *toasts* '())
  (tasks-select! tv #f)
  (steps 2))

;; The Tree: under each task what it waits for; a twisty, Right, Left and
;; Space expand and collapse; a click or a key selects; a later row of a
;; shared blocker is a place of its own, and Return goes to its own row.
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
                   `(wheel 0 ,(if (< i (apply min shown)) 1 -1)))
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
(let ([nodes (tree-nodes)])
  (check "the Tree tab: the roots, under each what it waits for, a shared \
          blocker's own row under its first waiter and later rows under the \
          others"
         (and (eq? (tasks-view-mode tv) 'tree)
              (equal? (list-head nodes 4) '(16 11 9 12))
              (member '(17 . 31) nodes) (memv 31 nodes)
              (member '(33 . 9) nodes)
              (= (length (filter (lambda (n) (eqv? n 10)) nodes)) 1))))
(shot "tree")
(tree-click! 13)
(check "a click on a row selects its task, and the details show it"
       (and (eq? (selected) (find-task 13)) (equal? (tree-at) 13)
            (ui-find tui '(blocked-by 31))))
(tree-click! 13 'twisty)
(check "its twisty collapses it" (not (memv 31 (tree-nodes))))
(press! 'right)
(steps 1)
(check "Right expands it" (memv 31 (tree-nodes)))
(press! 'right)
(steps 1)
(check "and again goes to its first child" (equal? (tree-at) 31))
(press! 'left)
(steps 1)
(check "Left goes to the parent" (equal? (tree-at) 13))
(press! 'left)
(steps 1)
(let ([collapsed? (not (memv 31 (tree-nodes)))])
  (press! #\space)
  (steps 1)
  (check "Left collapses, Space expands"
         (and collapsed? (memv 31 (tree-nodes)))))
(press! 'down)
(steps 1)
(check "Down goes to the next row" (equal? (tree-at) 31))
(tree-click! '(17 . 31))
(check "a click on a later row selects its task there"
       (and (eq? (selected) (find-task 31)) (equal? (tree-at) '(17 . 31))))
(press! 'down)
(steps 1)
(check "and Down goes on from there" (equal? (tree-at) 18))
(press! 'up)
(press! 'return)
(steps 2)
(check "Return on a later row goes to the task's own row"
       (and (equal? (tree-at) 31) (eq? (selected) (find-task 31))))
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

;; The selection stays on a row the Tree shows: a later row a change
;; takes away falls back to the task's own row; a twisty that hides it
;; selects the row it collapsed, as Left would, and typing in that task's
;; details keeps it collapsed. A Tree that shows nothing (a search that
;; matches none) takes no keys.
(tree-click! '(17 . 31))
(let ([after (next-to 13)])
  (move-task! 13 'doing)   ; 17 first in board order: 31's own row under it
  (steps 2)
  (let ([i (ui-tree-index (tree-rows) 31)] [was (tree-at)])
    (press! 'down)
    (steps 1)
    (check "a later row a change takes away: the selection falls back to \
            the task's own row, and Down goes on from there"
           (and i (equal? was 31)
                (equal? (tree-at) (list-ref (tree-nodes) (+ i 1))))))
  (move-task! 13 'todo after)
  (steps 2))
(tasks-select! tv (find-task 9))
(invalidate! tw)
(steps 2)
(tree-click! 11 'twisty)
(check "a twisty that hides the selection selects the row it collapsed"
       (and (equal? (tree-at) 11) (not (memv 9 (tree-nodes)))))
(let ([was (task-description (find-task 11))])
  (click-ui! tw 'description)
  (type! "x")
  (steps 2)
  (check "and typing in that task's details keeps it collapsed"
         (and (not (memv 9 (tree-nodes))) (equal? (tree-at) 11)))
  (press! 'escape)
  (set-task! 11 'description was))
(tree-click! 11 'twisty)
(tasks-select! tv #f)
(type! "/")
(type! "zzzzqq")
(press! 'escape)
(steps 2)
(press! 'down)
(press! 'end)
(steps 2)
(check "a search that leaves the Tree nothing to show: Down and End select \
        nothing"
       (and (ui-find tui 'empty-clear) (not (selected))))
(click-ui! tw 'clear)
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
(let* ([shared (add-task! "Shared" 'status 'todo)]
       [a (add-task! "Waits A" 'blocked-by (list shared))]
       [b (add-task! "Waits B" 'blocked-by (list shared))])
  (steps 2)
  (tree-click! (task-id shared))
  (press! 'delete)
  (press! 'return)
  (steps 2)
  (check "deleting a task in the Tree: what waited for it no more, and the \
          next row selected"
         (and (not (memq shared *tasks*)) (null? (task-blocked-by a))
              (null? (task-blocked-by b)) (eq? (selected) b)))
  (delete-task! a)
  (delete-task! b))
(set-task! 12 'blocked-by '())
(tasks-select! tv #f)

;; A reload that changed task's fields (here, as if back from its first
;; record type) carries the tasks over, an empty blocked-by each, and
;; Tasks opens again in its place.
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
  (load-sources! '("apps/tasks.ss"))
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
(resize-window! tw 760 600)
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
(resize-window! tw 1205 660)
(steps 2)
(click-ui! tw 'assignee)
(resize-window! tw 760 600)
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

;; At 150%, Clear keeps to the toolbar's first row until the search is at
;; its narrowest, even at widths that fill the row exactly.
(let ([y (lambda (id) (ui-region-y (ui-find tui id)))] [bad '()]
      [scale (theme 'scale)])
  (set-theme! 'scale 150)
  (steps 2)
  (for-each (lambda (w)
              (resize-window! tw w 700)
              (steps 1)
              (when (and (> (y 'clear) (y 'new))
                         (> (ui-region-w (ui-find tui 'search)) 151))
                (set! bad (cons w bad))))
            (map (lambda (i) (+ 1260 i)) (iota 31)))
  (set-theme! 'scale scale)
  (resize-window! tw 1205 660)
  (steps 2)
  (check "at 150%, Clear stays on the toolbar's first row while the search \
          is wider than its narrowest"
         (null? bad)))

;; 100,000 characters: words, then one word as long.
(define long-text
  (string-append (apply string-append (make-list 5555 "abcdefgh "))
                 (make-string 50005 #\x)))

;; Takes n steps; => the slowest one's ms.
(define (slowest-of-steps n)
  (let loop ([i 0] [worst 0])
    (if (= i n)
        worst
        (let ([t0 (now-ms)])
          (steps 1)
          (loop (+ i 1) (max worst (- (now-ms) t0)))))))

;; That pasted into a title, an assignee, a tag and the search: the Board,
;; the details, the menus, the dialog and the List keep answering, every
;; step under 300 ms (about 60 at most measured alone), and Tasks never
;; crashes.
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
  (define (paste!) (set! *host-clipboard* long-text) (press! #\v 'ctrl))
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
                the dialog, the List and the Tree under 300 ms, and Tasks \
                never crashed"
               (and (null? slow) menu? dialog? menu-w (< menu-w 400)
                    (= (string-length (task-title t)) 100001)
                    ;; a name is cut to 64 characters
                    (equal? (task-assignee t) (substring long-text 0 64))
                    (member "abcdefgh-abcdefgh-abcdef" (task-tags t))
                    (not (window-error tw)))))))
  (when (ui-find tui 'clear) (click-ui! tw 'clear))
  (delete-task! t)
  (steps 2))

;; A description: at most 65,536 characters, typed, pasted or set from the
;; REPL; a long one scrolls by the wheel and its bar, which settles once
;; idle steps have its rows, and Ctrl+End and Ctrl+Home show its ends.
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
(set-task! long-task 'description (make-string 70000 #\a))
(steps 1)
(check "a description given by the REPL is cut to 65,536 characters"
       (= 65536 (string-length (task-description long-task))))
(click-ui! tw 'description)
(press! 'end 'ctrl)
(type! "b")
(press! 'return)
(steps 2)
(check "at 65,536 characters a key types nothing, nor does Return"
       (equal? (task-description long-task) (make-string 65536 #\a)))
(do ([i 0 (+ i 1)]) ((= i 10)) (press! 'backspace))
(clipboard-set! (make-string 100 #\c))
(press! #\v 'ctrl)
(steps 2)
(check "a paste is cut to fit"
       (let ([d (task-description long-task)])
         (and (= 65536 (string-length d))
              (string=? (substring d 65526 65536) (make-string 10 #\c)))))
(press! 'escape)
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
(define (description-top) (ui-memo tui 'description 0))
(define (caret-shown?)   ; the caret's row is in the description's view
  (let* ([r (ui-find tui 'description)]
         [a (car (apply ui-text-box-areas
                        (append (ui-region-frame r) '(()))))]
         [lh (font-line-height 'ui)]
         [row (edit-row-at (ui-memo tui '(description rows) #f)
                           (ui-caret tui))]
         [top (- (* lh row) (description-top))])
    (and (>= top 0) (<= (+ top lh) (list-ref a 4)))))
(let-values ([(x y) (region-center 'description)]
             [(cx cy cw ch) (content-rect tw)])
  (inject! `(mouse-move ,(+ cx (round x)) ,(+ cy (round y))) '(wheel 0 -3))
  (steps 2)
  (check "the wheel scrolls a long description" (> (description-top) 0)))
(let-values ([(x0 y0) (ui-point tw '(description bar) 0.5)]
             [(cx cy cw ch) (content-rect tw)])
  (let* ([r (ui-find tui '(description bar))]
         [top (+ cy (round (ui-region-y r)) 2)]
         [bottom (+ cy (round (+ (ui-region-y r) (ui-region-h r))))])
    (inject! `(mouse-move ,x0 ,top) `(mouse-down ,x0 ,top left 1)
             `(mouse-move ,x0 ,bottom) `(mouse-up ,x0 ,bottom left))
    (steps 2)
    (let* ([lay (ui-memo tui '(description rows) #f)]
           [d (ui-find tui 'description)]
           [th (list-ref (car (apply ui-text-box-areas
                                     (append (ui-region-frame d) '(()))))
                         4)])
      (check "its thumb dragged to the bottom shows the last row"
             (>= (+ (description-top) th)
                 (- (* (font-line-height 'ui) (edit-layout-count lay)) 1))))))
(click-ui! tw 'description)
(press! 'home 'ctrl)
(steps 2)
(check "Ctrl+Home: the caret at the start, in view"
       (and (= 0 (ui-caret tui)) (= 0 (description-top)) (caret-shown?)))
(press! 'end 'ctrl)
(steps 2)
(check "Ctrl+End: the caret at the end, in view"
       (and (= 65000 (ui-caret tui)) (> (description-top) 0)
            (caret-shown?)))
(shot "long-description")
(define (description-page)   ; the rows a page moves
  (let* ([r (ui-find tui 'description)]
         [a (car (apply ui-text-box-areas
                        (append (ui-region-frame r) '(()))))])
    (max 1 (exact (floor (/ (list-ref a 4) (font-line-height 'ui)))))))
(define (caret-row)
  (edit-row-at (ui-memo tui '(description rows) #f) (ui-caret tui)))
(press! 'home 'ctrl)
(press! 'down)
(press! 'down)
(steps 2)
(let ([row (caret-row)] [top (description-top)]
      [page (description-page)] [lh (font-line-height 'ui)])
  (press! 'page-down)
  (steps 2)
  (let ([row-down (caret-row)] [top-down (description-top)])
    (press! 'page-up)
    (steps 2)
    (check "Page Down scrolls a long description a page and moves the \
            caret as many rows, so it keeps its place; Page Up goes back"
           (and (= 2 row) (= row-down (+ row page))
                (< (abs (- top-down (+ top (* page lh)))) 0.01)
                (= (caret-row) row)
                (< (abs (- (description-top) top)) 0.01)))))

;; A keystroke's edit says where it changed the text, so its rows follow
;; without comparing texts; a change from the REPL compares them.
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

;; A step that brings any window input runs no scan for a scroll bar, in
;; no window: the input's frame comes first.
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

;; The description's editor: a window of its own, opened by the button by
;; the Description label or by Ctrl+E in it, modal to Tasks; Save
;; (Ctrl+S) and Cancel (Escape, asking first when there are changes);
;; closed in any way, Tasks goes on.
(define (editor) (tasks-view-editor tv))
(define (editor-text) (tasks-editor-text (window-ref (editor) 'state)))
(define (waiting?) (and (ui-find tui '(ui modal-child)) #t))
(press! 'escape)
(steps 1)
(click-ui! tw 'edit-description)
(steps 1)
(check "the button by the label opens the editor, focused, on top, its \
        text focused at the start, and Tasks waits under a scrim"
       (and (window? (editor)) (eq? (editor) (focused-window))
            (eq? (editor) (car (windows)))
            (equal? (window-title (editor))
                    (format "~a — Description" (task-label long-task)))
            (eq? 'text (ui-focused (window-ref (editor) 'ui)))
            (= 0 (ui-caret (window-ref (editor) 'ui)))
            (waiting?)))
(png-write-screen (format "~a/tasks-editor.png" out-dir))
(let-values ([(cx cy cw ch) (content-rect tw)])
  (let ([x (+ cx 30)] [y (+ cy 80)] [n (length *tasks*)])
    (focus-window! tw)
    (steps 1)
    (check "focusing Tasks gives the editor the keyboard, above Tasks"
           (and (eq? (editor) (focused-window))
                (eq? (editor) (car (windows))) (eq? tw (cadr (windows)))))
    ;; handed to it, as a style that keeps no dialog above would
    (window-call tw 'text "n")
    (window-call tw 'key 'delete '())
    (steps 2)
    (check "Tasks takes no key while it waits"
           (and (= n (length *tasks*)) (not (tasks-view-confirm tv))))
    (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
             `(mouse-up ,x ,y left))
    (steps 2)
    (check "a click in Tasks brings the editor to the front"
           (and (eq? (editor) (focused-window))
                (eq? (editor) (car (windows)))))))
(define (editor-status)
  (let ([ed (editor)])
    (tasks-editor-status (window-ref ed 'state) (ui-edit (window-ref ed 'ui)))))
(set! compared 0)
(type! "Begun. ")
(steps 2)
(check "typed into the editor, the draft changes, not the task, and no \
        texts are compared"
       (and (string-prefix? "Begun. scroll" (editor-text))
            (string-prefix? "scroll" (task-description long-task))
            (= compared 0)))
(let ([status (editor-status)])
  (press! 'return)
  (type! "ab")
  (steps 2)
  (let ([two (editor-status)])
    (press! 'backspace)
    (press! 'backspace)
    (press! 'backspace)
    (steps 2)
    (check "the status line counts the caret's line and column as typing \
            makes and joins lines"
           (and (string-prefix? "Line 1, column 8  ·  65,007 of" status)
                (string-prefix? "Line 2, column 3" two)
                (string-prefix? "Line 1, column 8" (editor-status))))))
(set! edit-difference plain-difference)
(press! #\s 'ctrl)
(steps 2)
(check "Ctrl+S saves and closes it, and Tasks waits no more"
       (and (not (editor)) (not (waiting?))
            (string-prefix? "Begun. scroll" (task-description long-task))))
(click-ui! tw 'description)
(press! 'home 'ctrl)
(press! 'right) (press! 'right)
(press! #\e 'ctrl)
(steps 2)
(check "Ctrl+E in the description opens it, the caret where it was"
       (and (editor) (= 2 (ui-caret (window-ref (editor) 'ui)))))
(press! 'escape)
(steps 2)
(check "Escape with no changes closes it" (and (not (editor)) (not (waiting?))))
(click-ui! tw 'edit-description)
(type! "XY")
(press! 'escape)
(steps 2)
(let ([eui (window-ref (editor) 'ui)])
  (check "Escape with changes asks first"
         (and (editor) (ui-find eui '(discard 1))))
  (png-write-screen (format "~a/tasks-editor-discard.png" out-dir))
  (click-ui! (editor) '(discard 0))
  (check "Keep editing: back to the text, the caret where it was"
         (and (editor) (not (ui-find eui 'discard))
              (eq? 'text (ui-focused eui)) (= 2 (ui-caret eui))))
  (click-ui! (editor) 'cancel)
  (press! 'return)
  (steps 2)
  (check "Cancel, then Discard: the description as it was, the editor gone"
       (and (not (editor)) (not (waiting?))
            (string-prefix? "Begun. scroll" (task-description long-task)))))
(click-ui! tw 'edit-description)
(toggle-maximize! (editor))
(steps 2)
(press! 'end 'ctrl)
(type! "!")
(steps 2)
(let ([ed (editor)])
  (check "maximized, it types at the end of the text"
         (and (maximized? ed) (not (window-error ed))
              (string-suffix? "!" (editor-text))))
  (png-write-screen (format "~a/tasks-editor-maximized.png" out-dir))
  (close-window! ed)
  (steps 2)
  (check "closed by its window, the editor lets Tasks go, the draft lost"
         (and (not (editor)) (not (waiting?)) (focused-window)
              (not (string-suffix? "!" (task-description long-task))))))
;; Its task deleted from the REPL meanwhile, Save keeps the draft in a new
;; task of its title, and a toast says so.
(let ([gone (add-task! "Gone soon" 'status 'review 'description "Old.")])
  (steps 2)
  (tasks-select! tv gone)
  (steps 1)
  (let ([ed (tasks-open-editor! tv gone 0)])
    (steps 2)
    (delete-task! gone)
    (steps 1)
    (type! "Kept. ")
    (press! #\s 'ctrl)
    (steps 2)
    (let ([new (find (lambda (t) (equal? (task-description t) "Kept. Old."))
                     *tasks*)])
      (check "Save into a task deleted meanwhile keeps the draft in a new \
              task of its title, selected, and a toast names it"
             (and new (not (memq ed (windows))) (not (waiting?))
                  (equal? (task-title new) "Gone soon")
                  (eq? new (tasks-view-selected tv))
                  (exists (lambda (t)
                            (string-contains-ci? (vector-ref t 1)
                                                 (task-label new)))
                          *toasts*)))
      (when new (delete-task! new))
      (tasks-select! tv long-task)
      (steps 2))))
(click-ui! tw 'edit-description)
(let ([ed (editor)])
  (close-window! tw)
  (check "closing Tasks closes its editor" (not (memq ed (windows))))
  (set! tw (tasks))
  (set! tv (window-ref tw 'state))
  (set! tui (window-ref tw 'ui))
  (resize-window! tw 1205 660)
  (steps 2))
(delete-task! long-task)
(steps 2)

;; A window titled with 10,000 characters, then (when that was quick, so
;; that a slow cut fails in seconds) with 100,000: every window style
;; draws it in under 300 ms a frame.
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
                    every window style draws it in under 300 ms (slow: ~a)"
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
  (menu-click! "Move to Done")
  (check "a menu its window left open changes nothing once it is closed"
         (eq? status (task-status (find-task 9)))))
(set! *toasts* '())

;; The desktop entry that gives GNOME and co. the app icon (into a scratch
;; folder).
(putenv "XDG_DATA_HOME" (string-append out-dir "/xdg"))
(let ([files (install-desktop-entry!)])
  (check "the desktop entry names the window's app id and the icon"
         (let ([text (call-with-input-file (car files) get-string-all)])
           (and (member (string-append "StartupWMClass=" host-app-id)
                        (string-split text #\newline))
                (string-suffix? (string-append "/" host-app-id ".desktop")
                                (car files))
                (string-contains-ci? text "Icon=schevana")
                (file-exists? (cadr files)))))
  (uninstall-desktop-entry!)
  (check "and uninstalling removes it" (not (exists file-exists? files))))

;; The profiler: on at boot, it collects with Monitor closed. Monitor
;; draws its graphs; a window's name focuses it and a process's Kill
;; kills it; the Profiling checkbox turns it off, and Monitor lists the
;; windows and processes in tables, whose rows focus and kill as they
;; always did; and on again.
(let ([m (find-window 'monitor)]) (when m (close-window! m)))
(steps 2)
(check "profiling is on at boot, and collects with Monitor closed"
       (let ([s (car (profile-ticks))])
         (steps 1)
         (and (profile-on?) (not (find-window 'monitor))
              (not (eqv? s (car (profile-ticks)))))))
(let* ([target (open-window "Target"   ; drawn at every step, slowly: a top row
                 'size '(200 . 100) 'pos '(1000 . 420)
                 'tick (lambda (win) (invalidate! win))
                 'draw (lambda (win w h)
                         (let ([t (+ (real-time) 2)])
                           (let loop () (when (< (real-time) t) (loop))))))]
       [busy (lambda () (spawn "monitored" (lambda () (let loop () (loop)))))]
       [p (busy)]
       [m (monitor)]
       [ui (window-ref m 'ui)]
       [bars (lambda ()
               (filter (lambda (r)
                         (let ([id (ui-region-id r)])
                           (and (pair? id) (eq? (car id) 'monitor-ticks))))
                       (ui-state-regions ui)))]
       [row (lambda (table x xs)   ; x's row in the table of xs, by id
              (list table 'row (list-index (lambda (y) (eq? y x)) xs)))]
       [window-row (lambda ()
                     (row 'monitor-windows target
                          (sort (lambda (a b) (< (window-id a) (window-id b)))
                                (windows))))])
  (move-window! m 20 40)
  (focus-window! m)
  (steps 2)
  (check "Monitor opens on its Overview: the windows and processes in \
          tables, no bars"
         (and (null? (bars)) (ui-find ui (window-row))
              (ui-find ui (row 'monitor-procs p (procs)))))
  (click-ui! m '(tab ticks))
  ;; the Consumers sum seconds done: one with Target in it done, and
  ;; Monitor's view moved on (twice a second) since
  (let ([until (+ (real-time) 1700)])
    (let loop () (when (< (real-time) until) (schevana-step! 5) (loop))))
  (steps 1)
  (png-write-screen (string-append out-dir "/monitor.png"))
  (check "Monitor draws its graphs: a bar a tick, a row a consumer"
         (and (not (window-error m)) (pair? (bars))
              (ui-find ui (list 'monitor-kill (proc-id p)))
              (ui-find ui (list 'monitor-focus (window-id target)))))
  ;; the Consumers sorted by a heading: by name, again the other way, and
  ;; back to ms/s, the most first
  (let ([order (lambda (nodes)   ; the same nodes, in a fixed order
                 (list-sort string<? (map (lambda (n) (format "~s" n))
                                          nodes)))]
        [roots (lambda ()
                 (map ui-tree-row-node
                      (filter (lambda (r) (= 0 (ui-tree-row-depth r)))
                              (vector->list
                               (ui-memo ui '(consumers rows) '#())))))])
    (let ([by-rate (roots)])
      (click-ui! m '(consumers header name))
      (let ([by-name (roots)])
        (click-ui! m '(consumers header name))
        (let ([by-name-down (roots)])
          (click-ui! m '(consumers header rate))
          (check "a Consumers heading sorts its rows by it, again the other \
                  way; the same rows each time"
                 (and (> (length by-rate) 2)
                      (not (equal? by-name by-name-down))
                      (equal? (reverse by-name) by-name-down)
                      (equal? (order by-rate) (order by-name))
                      (equal? (order by-rate) (order (roots)))))))))
  ;; The rows drawn selected, at a draw of Monitor's.
  (let ([selected-rows
         (lambda ()
           (let ([n 0] [real ui-draw-highlight-over])
             (fluid-let ([ui-draw-highlight-over
                          (lambda args (set! n (+ n 1)) (apply real args))])
               (invalidate! m)
               (steps 1))
             n))])
    (click-ui! m '(consumers row 0))
    (let ([chosen (selected-rows)])
      (click-ui! m '(consumers row 0))
      (let ([let-go (selected-rows)])
        (check (format "a press selects a Consumers row, and a second lets it \
                        go (~a, then ~a drawn selected)" chosen let-go)
               (and (= chosen 1) (= let-go 0))))))
  (check "a Consumers heading says what its column means"
         (let ([r (ui-find ui '(consumers header avg))])
           (and r (string? (ui-region-tip r))
                (string-contains-ci? (ui-region-tip r) "average"))))
  ;; the pointer resting on the newest bar: its tooltip, what it spent
  (let ([r (car (bars))])
    (let-values ([(cx cy cw ch) (content-rect m)])
      (inject! `(mouse-move ,(+ cx (ui-region-x r) (ui-region-w r) -2)
                            ,(+ cy (ui-region-y r)
                                (quotient (ui-region-h r) 2)))))
    (let ([until (+ (real-time) 800)])
      (let loop () (when (< (real-time) until) (schevana-step! 5) (loop))))
    (png-write-screen (string-append out-dir "/monitor-tip.png"))
    (let ([tip (let ([rs (bars)]) (and (pair? rs) (ui-region-tip (car rs))))])
      (printf "  ~s\n" tip)
      (check "hovering a bar of Monitor's Ticks shows its tooltip: its \
              tick, whether it came late, and its phases"
             (and (string? tip)
                  (string-contains-ci? tip "tick ")
                  (string-contains-ci? tip "(a tick is ")
                  (< (+ (car (ui-state-rest ui)) ui-tip-ms) (now-ms))))))
  (click-ui! m (list 'monitor-focus (window-id target)))
  (check "a window's name in Monitor focuses it" (eq? (focused-window) target))
  (focus-window! m)
  (steps 2)
  (click-ui! m (list 'monitor-kill (proc-id p)))
  (check "a process's Kill in Monitor kills it" (not (memq p (procs))))
  (click-ui! m 'profiling)
  (let ([p (busy)])
    (steps 2)
    (check "Monitor's Profiling turns it off: no bars"
           (and (not (profile-on?)) (not *profile-span*) (null? (bars))))
    (click-ui! m '(tab overview))
    (check "its Overview lists the windows and processes in tables still \
            (a new one by its next view: twice a second)"
           (and (ui-find ui (window-row))
                (wait-for (lambda ()
                            (ui-find ui (row 'monitor-procs p (procs)))))))
    (click-ui! m (window-row))
    (check "where a window's row focuses it" (eq? (focused-window) target))
    (focus-window! m)
    (steps 2)
    (click-ui! m (row 'monitor-procs p (procs)))
    (check "a process's row only selects it" (memq p (procs)))
    (click-ui! m (list 'monitor-proc-kill (proc-id p)))
    (check "and its Kill kills it" (not (memq p (procs)))))
  (click-ui! m '(tab ticks))
  (click-ui! m 'profiling)
  (let ([until (+ (real-time) 700)])
    (let loop () (when (< (real-time) until) (schevana-step! 5) (loop))))
  (check "and on again: the bars come back"
         (and (profile-on?) (pair? *profile-span*)
              (pair? (bars)) (not (window-error m))))
  (close-window! m)
  (close-window! target)
  (steps 2))

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

;;; Frames: whenever something asks for one, everything is drawn again.
(for-each close-window! (windows))
(set! *toasts* '())
(steps 2)

;; Whether one step drew a frame.
(define (step-drew?)
  (let ([n *frames-drawn*])
    (schevana-step! 0)
    (> *frames-drawn* n)))

;; Steps until the frame the clock forces once a second has just been
;; drawn, so that the next steps (well under a second of them) get none.
(define (after-clock-frame!)
  (let ([s (time-second (current-time))])
    (let loop ()
      (when (= s (time-second (current-time))) (schevana-step! 0) (loop)))
    (steps 1)))

;; thunk with status segments that never change, so the top bar stays put.
(define (with-quiet-status thunk)
  (let ([segs *status-segments*])
    (set! *status-segments* (list (cons 'quiet (lambda () "quiet"))))
    (steps 2)
    (let ([v (thunk)])
      (set! *status-segments* segs)
      (steps 1)
      v)))

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

;; Input asks for a frame by itself, so a handler that only changes its
;; state is seen.
(let* ([seen #f] [state 0]
       [bump (lambda (win . args) (set! state (+ state 1)))]
       [w (plain-window "Quiet" 100 100
                        'draw (lambda (win cw ch)
                                (set! seen state)
                                (draw-text 14 14 (number->string state)
                                           'text 'big))
                        'key bump 'text bump 'wheel bump 'mouse-up bump)])
  (steps 2)
  (let-values ([(cx cy cw ch) (content-rect w)])
    (define (shown-after kind . evs)
      (apply inject! evs)
      (steps 2)
      (cons kind (eqv? seen state)))
    (let* ([x (+ cx 50)] [y (+ cy 50)]
           [key (shown-after 'key '(key-down #\a ()))]
           [text (shown-after 'text '(text "x"))]
           [wheel (shown-after 'wheel `(mouse-move ,x ,y) '(wheel 0 1))]
           ;; (no 'mouse-down handler)
           [up (shown-after 'mouse-up `(mouse-down ,x ,y left 1)
                            `(mouse-up ,x ,y left))]
           [shown (list key text wheel up)])
      (check (format "input reaches windows that never invalidate ~s" shown)
             (and (= state 4) (for-all cdr shown)))))
  (close-window! w))

;; A window that changes by itself says so, and the next frame shows it
;; (the frame the clock asks for once a second is the top bar's).
(let* ([count 0]
       [w (open-window "Ticker" 'size '(260 . 120) 'pos '(400 . 100)
                       'tick (lambda (win)
                               (set! count (+ count 1))
                               (invalidate! win))
                       'draw (lambda (win cw ch)
                               (fill-box 0 0 cw ch (if (even? count)
                                                       #xff0000
                                                       #x0000ff))))])
  (let-values ([(x y cw ch) (content-rect w)])
    (define (red?) (> (canvas-pixels (device-box x y cw ch) #xffff0000) 0))
    (steps 2)
    (let* ([a (red?)] [b (begin (steps 1) (red?))]
           [c (begin (steps 1) (red?))])
      (check (format "a window that invalidates itself as it ticks shows \
                      each tick on the next frame ~s" (list a b c))
             (and (not (eq? a b)) (not (eq? b c))))))
  (close-window! w))

;; Steps that nothing asked a frame of draw nothing. The frame the clock
;; asks for once a second draws no window, which keeps what it drew;
;; (invalidate!) draws every window once.
(let* ([a (plain-window "One" 100 100)] [b (plain-window "Two" 420 160)]
       [na (count-draws! a)] [nb (count-draws! b)])
  (steps 2)
  (let ([a0 (na)] [b0 (nb)] [t0 (now-ms)])
    (let loop ([n 0] [forced 0])
      (if (< (- (now-ms) t0) 1100)
          (loop (+ n 1) (if (step-drew?) (+ forced 1) forced))
          (check (format "idle steps draw nothing; a frame the clock asks \
                          for draws no window (~a steps, ~a forced)" n forced)
                 (and (> n 3) (<= 1 forced 2) (= (na) a0) (= (nb) b0))))))
  (with-quiet-status
   (lambda ()
     (invalidate!)
     (steps 1)   ; the quiet top bar drawn
     (let ([a0 (na)] [b0 (nb)])
       (invalidate!)
       (steps 1)
       (check "(invalidate!) draws every window again"
              (and (= (na) (+ a0 1)) (= (nb) (+ b0 1)))))))
  (close-window! a)
  (close-window! b))

;; An expose shows a frame again: what the window showed may be gone.
(with-quiet-status
 (lambda ()
   (let ([w (plain-window "Plain" 300 200)])
     (after-clock-frame!)
     (let ([frames *frames-drawn*])
       (inject! '(expose))
       (steps 1)
       (check "an expose draws a frame" (= *frames-drawn* (+ frames 1))))
     (close-window! w)
     (steps 1))))

;;; SDL3's event layout, from a hand-filled SDL_Event: the offsets are
;;; SDL_events.h's (3.2). Core0 decodes it; the world lays it out.
(define (decode-event type . fields)   ; fields: (type offset value) ...
  (do ([i 0 (+ i 1)]) ((= i 128)) (foreign-set! 'unsigned-8 *sdl-event* i 0))
  (foreign-set! 'unsigned-32 *sdl-event* 0 type)
  (for-each (lambda (f) (foreign-set! (car f) *sdl-event* (cadr f) (caddr f)))
            fields)
  (let ([e (sdl-event->list *sdl-event*)])
    (and e (host-event->world e))))

(set! *wheel-rest* '(0 . 0))
;; the decoded wheel events, in order (map's order is unspecified)
(let ([wheel (lambda ds
               (let loop ([ds ds] [acc '()])
                 (if (null? ds)
                     (reverse acc)
                     (loop (cdr ds)
                           (cons (decode-event SDL_EVENT_MOUSE_WHEEL
                                               `(float 28 ,(car ds)))
                                 acc)))))])
  (check "SDL3 events decode: a key with its modifiers, float mouse \
          positions, and wheel fractions summed into whole steps, the \
          leftover dropped when the wheel turns back"
         (and (equal? (decode-event SDL_EVENT_KEY_DOWN '(unsigned-32 28 #x61)
                                    '(unsigned-16 32 #x41))
                      '(key-down #\a (ctrl shift)))
              (equal? (decode-event SDL_EVENT_MOUSE_MOTION '(float 28 10.75)
                                    '(float 32 20.25))
                      (list 'mouse-move (host->world 10.75)
                            (host->world 20.25)))
              (equal? (wheel 0.4 0.4 -0.4 -0.4 -0.4)
                      '(#f #f #f #f (wheel 0 -1))))))

;;; The host's SDL code, run against a stand-in for SDL: every SDL call
;;; src/ffi.ss and src/host/sdl.ss bind is replaced (one with no stand-in
;;; raises), so nothing here reaches the real SDL or opens a window. The
;;; fake window is fake-units window units big with fake-ratio physical
;;; pixels per unit, on a desktop that asks for fake-desktop (Xft.dpi / 96
;;; under X11), so its display scale is their product, as SDL3's is; its
;;; texture is an image that uploads copy rows into, as SDL_UpdateTexture
;;; does. *host* is 'sdl only around single host calls, so steps stay
;;; headless.

(define fake-sdl-names
  (apply append
         (map (lambda (f)
                (call-with-input-file (string-append *schevana-root* f)
                  (lambda (p)
                    (let loop ([acc '()])
                      (let ([x (read p)])
                        (cond
                          [(eof-object? x) acc]
                          [(and (pair? x)
                                (memq (car x) '(define-foreign
                                                define-foreign/collect-safe))
                                (string-prefix? "SDL_" (caddr x))
                                ;; plain memory and the GPU's: kept
                                (not (member (caddr x)
                                             '("SDL_memcmp" "SDL_memcpy")))
                                (not (string-contains-ci? (caddr x) "GPU")))
                           (loop (cons (cadr x) acc))]
                          [else (loop acc)]))))))
              '("/src/ffi.ss" "/src/host/sdl.ss"))))

(define fake-units '(1280 . 800))
(define fake-ratio 1)
(define fake-desktop 1)
(define fake-flags 0)
(define fake-hints '())        ; the hints set, newest first
(define fake-queue '())        ; the event types SDL_PollEvent hands out next
(define fake-log '())          ; what was asked of the window, newest first
(define fake-unfaked '())      ; SDL calls made that have no stand-in

(define (fake-log! . entry) (set! fake-log (cons entry fake-log)))

(define (fake-sdl name)
  (define (pair! a b x y)
    (foreign-set! 'integer-32 a 0 x)
    (foreign-set! 'integer-32 b 0 y)
    #t)
  (define (poll buf)
    (and (pair? fake-queue)
         (begin
           (foreign-set! 'unsigned-32 buf 0 (car fake-queue))
           (set! fake-queue (cdr fake-queue))
           #t)))
  (case name
    [(sdl-init) (lambda (flags) #t)]
    [(sdl-set-hint)
     (lambda (k v) (set! fake-hints (cons (cons k v) fake-hints)) #t)]
    [(sdl-start-text-input) (lambda (win) #t)]
    [(sdl-get-window-display-scale)
     (lambda (win) (inexact (* fake-ratio fake-desktop)))]
    [(sdl-create-window)
     (lambda (title w h flags)
       (set! fake-units (cons w h))
       (set! fake-flags flags)
       (fake-log! 'create w h
                  (if (logtest flags SDL_WINDOW_HIDDEN) 'hidden 'shown))
       1)]
    [(sdl-set-window-size)
     (lambda (win w h) (set! fake-units (cons w h)) (fake-log! 'size w h) #t)]
    [(sdl-set-window-position)
     (lambda (win x y)
       (fake-log! 'position
                  (if (= x y SDL_WINDOWPOS_CENTERED) 'centered (list x y)))
       #t)]
    [(sdl-show-window) (lambda (win) (fake-log! 'show) #t)]
    [(sdl-set-window-minimum-size)
     (lambda (win w h) (fake-log! 'minimum w h) #t)]
    [(sdl-get-window-flags) (lambda (win) fake-flags)]
    [(sdl-get-window-size)
     (lambda (win w h) (pair! w h (car fake-units) (cdr fake-units)))]
    [(sdl-get-window-size-in-pixels)
     (lambda (win w h)
       (pair! w h (* fake-ratio (car fake-units))
              (* fake-ratio (cdr fake-units))))]
    [(sdl-poll-event) poll]
    [(sdl-wait-event-timeout) (lambda (buf ms) (poll buf))]
    [(sdl-get-ticks-ns) (top-level-value name)]   ; the clock: SDL's own
    [(sdl-get-num-logical-cpu-cores) (top-level-value name)]
    [else (lambda args
            (set! fake-unfaked (cons name fake-unfaked))
            (errorf name "the fake SDL has no stand-in for this"))]))

;; Runs thunk with the fake SDL in place of the real one, the GPU's frames
;; going on to its target.
(define (with-fake-sdl thunk)
  (let ([saved (map top-level-value fake-sdl-names)]
        [claim gpu-claim-window!])
    (dynamic-wind
      (lambda ()
        (for-each (lambda (n) (set-top-level-value! n (fake-sdl n)))
                  fake-sdl-names)
        (set! gpu-claim-window! (lambda (window) (void))))
      thunk
      (lambda ()
        (for-each set-top-level-value! fake-sdl-names saved)
        (set! gpu-claim-window! claim)))))

;; SDL reports window events (through the host's real event loop); the
;; world handles what the host makes of them.
(define (fake-event! . types)
  (set! fake-queue types)
  (apply inject! (fluid-let ([*host* 'sdl]) (host-events 0)))
  (steps 2))

;; As SDL3 reports a change of size or of pixel ratio: each of the three
;; events may come alone, and the first makes the change.
(define (fake-resize! units ratio)
  (set! fake-units units)
  (set! fake-ratio ratio)
  (fake-event! SDL_EVENT_WINDOW_RESIZED SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED
               SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED))

(with-quiet-status
 (lambda ()
   (fluid-let ([*host-min-size* #f] [*pixel-ratio* 1]
               [*host-scale* *host-scale*])
     (with-fake-sdl
      (lambda ()
        (set! fake-log '())
        (fake-resize! '(1280 . 800) 1)
        (check "the fake SDL had a stand-in for every call"
               (null? fake-unfaked))
        ;; measuring is by the fonts' tables: a scale changes nothing of it
        (let ([before (font-metrics 'mono)])
          ;; a window moved to a 2x display (macOS, Wayland)
          (fake-resize! '(1280 . 800) 2)
          (check (format "a scale change by a resize event leaves the world \
                          its logical size, and the fonts' measures (mono ~s)"
                         before)
                 (and (= *scale* 2.0) (= *canvas-w* 1280) (= *canvas-h* 800)
                      (equal? before (font-metrics 'mono)))))
        (fake-resize! '(1280 . 800) 1)
        ;; the minimum size: plain resizes do not repeat it; in full screen SDL
        ;; only stores it, so it is passed on again after
        (do ([i 1 (+ i 1)]) ((> i 8))
          (fake-resize! (cons (+ 1280 (* 20 i)) (+ 800 (* 12 i))) 1))
        (set! fake-desktop 3/2)
        (set! fake-flags SDL_WINDOW_FULLSCREEN)
        (fake-resize! '(1920 . 1200) 1)
        (set! fake-flags 0)
        (fake-resize! '(1300 . 820) 1)
        (fake-resize! '(1320 . 830) 1)
        (set! fake-desktop 1)
        (fake-resize! '(1280 . 800) 1)
        (let ([minimums
               (reverse
                (filter-map (lambda (e) (and (eq? (car e) 'minimum) (cdr e)))
                            fake-log))])
          (check (format "the minimum size goes to SDL only when it changes, \
                          and again after full screen ~s" minimums)
                 (and (equal? minimums
                              '((640 400) (960 600) (960 600) (640 400)))
                      (= *scale* 1.0) (= *canvas-w* 1280)
                      (= *canvas-h* 800)))))))))

;; The host window opens hidden, is sized in window units once the pixel
;; ratio and the desktop's scale are known, centered, and only then shown.
;; SDL is told the app id that the desktop entry names.
(with-quiet-status
 (lambda ()
   (fluid-let ([*host* 'headless] [*sdl-window* 0]
               [*host-fullscreen* #f] [*host-min-size* #f]
               [*pixel-ratio* 1] [*host-scale* *host-scale*])
     (with-fake-sdl
      (lambda ()
        ;; the scale saved (a rescale builds the theme again from it)
        (define (open scale ratio desktop . fullscreen?)
          (set! *scale-setting* scale)
          (hashtable-set! *theme* 'scale scale)
          (set! fake-ratio ratio)
          (set! fake-desktop desktop)
          (set! fake-log '())
          (set! *canvas-pw* 0)   ; as in a new session
          (apply host-init! 'sdl 1280 800 fullscreen?)
          (set! *host* 'headless)   ; steps stay headless
          (list (reverse fake-log) *canvas-w* *canvas-h*
                (= fake-flags
                   (fxior SDL_WINDOW_RESIZABLE SDL_WINDOW_HIGH_PIXEL_DENSITY
                          SDL_WINDOW_HIDDEN
                          (if (pair? fullscreen?) SDL_WINDOW_FULLSCREEN 0)))))
        (let* ([explicit (open 200 2 1)]   ; a 2x display (macOS, Wayland)
               [x11 (open 0 1 2)]          ; X11 at Xft.dpi 192
               [wayland (open 0 2 1)]
               [x150 (open 150 1 1)]
               [full (open 200 1 1 #t)])   ; never resized
          (set! *scale-setting* 0)
          (hashtable-set! *theme* 'scale 0)
          (set! fake-flags 0)
          (set! fake-desktop 1)
          (set! *host-fullscreen* #f)
          (fake-resize! '(1280 . 800) 1)   ; the world as it was
          (check (format "the host window opens hidden, sized for the pixel \
                          ratio and the desktop's scale, then centered and \
                          shown ~s" (list explicit x11 wayland x150 full))
                 (and (equal? explicit '(((create 1280 800 hidden)
                                          (position centered) (show)
                                          (minimum 640 400))
                                         1280 800 #t))
                      (equal? x11 '(((create 1280 800 hidden) (size 2560 1600)
                                     (position centered) (show)
                                     (minimum 1280 800))
                                    1280 800 #t))
                      (equal? wayland explicit)
                      (equal? x150 '(((create 1280 800 hidden) (size 1920 1200)
                                      (position centered) (show)
                                      (minimum 960 600))
                                     1280 800 #t))
                      (equal? full '(((create 1280 800 hidden)
                                      (position centered) (show)
                                      (minimum 1280 800))
                                     640 400 #t))
                      (= *scale* 1.0) (= *canvas-w* 1280) (= *canvas-h* 800)
                      (null? fake-unfaked))))
        (check (format "SDL gets the app id the desktop entry names, ~s"
                       host-app-id)
               (equal? (assoc "SDL_APP_ID" fake-hints)
                       (cons "SDL_APP_ID" host-app-id))))))))


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
;; window is drawn in (the REPL invalidates all when it's done); so does the
;; original, put back.
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
    (set! draw-taskbar (lambda ()
                         (orig)
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

;; Minimized from its taskbar button's window menu while another window
;; keeps the focus.
(let* ([a (plain-window "Aaa" 100 100)] [b (plain-window "Bbb" 500 100)])
  (steps 2)
  (let* ([it (cdr (assq a (taskbar-areas)))]
         [x (exact (round (+ (car it) (/ (caddr it) 2))))]
         [y (- (screen-h) (quotient (taskbar-height) 2))])
    (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y right 1)
             `(mouse-up ,x ,y right))
    (steps 2)
    (press! 'down)   ; Bind, Maximize, Minimize
    (press! 'down)
    (steps 1)
    (press! 'return)
    (steps 2)
    (check
     "a window minimized from its taskbar menu leaves the focus where it was"
     (and (not (visible? a)) (eq? *focus* b))))
  (for-each close-window! (list a b))
  (steps 1))

;; A status segment's change shows when the bar next looks, at the clock's
;; next second.
(let ([v "probe-a"])
  (add-status-segment! 'probe (lambda () v))
  (steps 2)
  (set! v "probe-b")
  (set! *status-last-second* -1)
  (steps 1)
  (check (format "a status segment's change shows at the bar's next second ~s"
                 (shown-status-strings))
         (and (member "probe-b" (shown-status-strings)) #t))
  (remove-status-segment! 'probe)
  (steps 1))

;; A style whose drawing fails: nothing of what was under the window
;; stays on screen.
(define-style broken "Broken"
  'frame-radius (lambda (w) 8)
  'frame-under (lambda (win x y w h focused? hover pressed)
                (error 'broken "broken on purpose")))
(with-quiet-status
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

;; Life's cells take a theme change made behind set-theme!'s back, once
;; asked to draw (set-theme! asks every window).
(let ([l (life)] [green (theme 'green)] [cyan (theme 'cyan)])
  (window-call l 'key #\space '())   ; paused
  (move-window! l 100 60)
  (steps 2)
  (let*-values ([(cx cy cw ch) (content-rect l)]
                [(grid) (device-box cx cy cw
                                    (- ch ((top-level-value
                                            'life-bar-height
                                            (env-environment
                                             (grant-env 'life))))))]
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

;;; Live changes: reloading and redefining while the world runs.

;; Reloading as a process (the launcher's "Reload sources", a REPL) holds
;; the world still until it ends, but stays a process. These reload a copy
;; of the tree whose apps/tasks.ss ends in form.
(define (tree-copy-with name form)
  (let ([dir (string-append out-dir "/" name)])
    (system (format "rm -rf '~a' && mkdir -p '~a' && cp -r~{ '~a'~} '~a'"
                    dir dir
                    (map (lambda (f) (string-append *schevana-root* "/" f))
                         (cons* "load.ss" "src" source-folders))
                    dir))
    ;; the last file to load into the world: an app in a sandbox would run
    ;; the form there
    (let ([p (open-output-file (string-append dir "/apps/tasks.ss") 'append)])
      (write form p)
      (newline p)
      (close-port p))
    dir))

;; A long load: until it ends no frame, timer, tick, handler or other
;; process runs, and events that come meanwhile are handled after it, in
;; order. The slow form notes what had run before and after its 0.6 s;
;; a process that comes after the reload in each round counts its slices
;; during it.
(define probe-counts (lambda () '()))
(define probe-seen '())
(let* ([root *schevana-root*] [ticks 0] [draws 0] [timers 0] [slices 0]
       [keys '()] [sent '()] [n 0] [done? #f] [late-held 0]
       [probe (open-window "Probe" 'size '(200 . 100)
                           'tick (lambda (win) (set! ticks (+ ticks 1)))
                           'draw (lambda (win w h) (set! draws (+ draws 1)))
                           'key (lambda (win key mods)
                                  (set! keys (cons key keys))))]
       [bystander (spawn "bystander"
                         (lambda ()
                           (let loop ()
                             (set! slices (+ slices 1))
                             (yield)
                             (loop))))])
  (set! probe-counts (lambda () (list ticks draws timers slices (length keys))))
  (let again ()
    (after 5 (lambda () (set! timers (+ timers 1)) (unless done? (again)))))
  (steps 2)
  (set! *schevana-root*
    (tree-copy-with "slow-tree"
      '(begin (set! probe-seen (list (probe-counts)))
              (let ([t (+ (real-time) 600)])
                (let loop () (when (< (real-time) t) (loop))))
              (set! probe-seen (cons (probe-counts) probe-seen)))))
  (let* ([p (spawn "reload" reload!)]
         [late (spawn "late"
                      (lambda ()
                        (let loop ()
                          (when *reloading* (set! late-held (+ late-held 1)))
                          (yield)
                          (loop))))])
    (let loop ()
      (when (and (memq p (procs)) (< n 5000))
        (let ([k (integer->char (+ 97 (mod n 26)))])
          (inject! (list 'key-down k '()))
          (set! sent (cons k sent)))
        (set! n (+ n 1))
        (schevana-step! 0)
        (loop)))
    (kill! late))
  (set! *schevana-root* root)
  (steps 3)
  (check (format "a long reload run as a process holds the world still (~a \
                  steps; ticks, draws, timers, other process, keys before and \
                  after: ~s; slices of a later process during it: ~a)"
                 n (reverse probe-seen) late-held)
         (and (> n 10) (= (length probe-seen) 2)
              (equal? (car probe-seen) (cadr probe-seen)) (= late-held 0)
              (> (length keys) 0) (equal? keys sent)
              (> ticks (car (car probe-seen)))))
  (set! done? #t)
  (kill! bystander)
  (close-window! probe)
  (set! *toasts* '())
  (steps 1))

;; A source whose top level loops: the world does not freeze, Ctrl+C kills
;; the reload, a toast names the file, and the world goes on.
(define reload-reached #f)
(let ([root *schevana-root*] [worst 0] [n 0] [ticks 0])
  (set! *schevana-root*
    (tree-copy-with "loop-tree"
      '(begin (set! reload-reached #t) (let loop () (loop)))))
  (let ([p (spawn "reload" reload!)]
        [w (open-window "Ticks" 'tick (lambda (win) (set! ticks (+ ticks 1))))])
    (define (step!)
      (let ([t0 (real-time)])
        (schevana-step! 0)
        (set! n (+ n 1))
        (set! worst (max worst (- (real-time) t0)))))
    (let loop () (unless (or reload-reached (> n 3000)) (step!) (loop)))
    (do ([i 0 (+ i 1)]) ((= i 20)) (step!))
    (let ([alive? (and (memq p (procs)) #t)] [t0 ticks])
      (press! #\c 'ctrl)
      (steps 3)
      (set! *schevana-root* root)
      (check (format "a reload whose source loops does not freeze the world \
                      (~a steps, the longest ~a ms), Ctrl+C kills it and a \
                      toast names the file"
                     n worst)
             (and reload-reached alive? (< worst 500) (not (memq p (procs)))
                  (not *reloading*) (> ticks t0)
                  (exists (lambda (t)
                            (string-contains-ci? (vector-ref t 1)
                                                 "apps/tasks.ss"))
                          *toasts*))))
    (close-window! w)
    (set! *toasts* '())
    (steps 1)))

;; A source that raises: the reload ends there and a toast names the file,
;; also when the process catches the error and carries on.
(let ([root *schevana-root*] [caught? #f])
  (set! *schevana-root*
    (tree-copy-with "error-tree" '(error 'smoke "on purpose")))
  (let ([p (spawn "reload"
                  (lambda ()
                    (guard (c [#t (set! caught? #t)]) (reload!))
                    (let loop () (yield) (loop))))])
    (let loop ([n 0])
      (unless (or caught? (> n 3000)) (schevana-step! 0) (loop (+ n 1))))
    (steps 2)
    (set! *schevana-root* root)
    (check "a reload whose source raises ends there, and a toast names the file"
           (and caught? (memq p (procs)) (not (reload-holding?))
                (exists (lambda (t)
                          (string-contains-ci? (vector-ref t 1)
                                               "failed in apps/tasks.ss"))
                        *toasts*)))
    (kill! p)
    (set! *toasts* '())
    (steps 1)))

;; The hold ends when the loading does, not when the process does: a
;; process that goes on after (reload!) lets the world run.
(let ([state 'unset] [ticks 0])
  (let ([p (spawn "reload+work"
                  (lambda ()
                    (reload!)
                    (set! state *reloading*)
                    (let loop () (yield) (loop))))]
        [w (open-window "Ticks" 'tick (lambda (win) (set! ticks (+ ticks 1))))])
    (let loop ([n 0])
      (when (and (eq? state 'unset) (< n 3000))
        (schevana-step! 0)
        (loop (+ n 1))))
    (let ([t0 ticks])
      (steps 3)
      (let ([alive? (and (memq p (procs)) #t)] [ran (- ticks t0)])
        (kill! p)
        (steps 2)
        (check (format "a process that goes on after (reload!) does not hold \
                        the world (*reloading* ~s, ~a ticks, toasts ~s)"
                       state ran (map (lambda (t) (vector-ref t 1)) *toasts*))
               (and (not state) alive? (> ran 0) (not *reloading*)
                    (exists (lambda (t)
                              (equal? (vector-ref t 1) "Sources reloaded"))
                            *toasts*)
                    (not (exists (lambda (t)
                                   (string-contains-ci? (vector-ref t 1)
                                                        "stopped"))
                                 *toasts*))))))
    (close-window! w)
    (set! *toasts* '())
    (steps 1)))

;; (reload!) in a world REPL reloads the world, not the REPL.
(let ([p (repl 'world)] [old render-frame!])
  (steps 2)
  (type! "(reload!)")
  (press! 'return)
  (let ([reloaded? (wait-for (lambda () (not (eq? render-frame! old))))])
    (wait-for (lambda () (not (repl-proc (repl-of p)))))
    ;; the REPL's own: the world's styles must not see it
    (type! "(define (title-height) 99)")
    (press! 'return)
    (wait-for (lambda () (not (repl-proc (repl-of p)))))
    (let ([w (plain-window "Plain" 300 200)])
      (let-values ([(l t r b) (frame-insets w)])
        (check "(reload!) in a world REPL reloads the world, whose \
                styles keep the world's names"
               (and reloaded? (= t (title-height)) (not (= t 99)))))
      (close-window! w)))
  (close-window! p)
  (set! *toasts* '())
  (steps 1))

;; A draw-wallpaper that raises, tried again with every frame, is reported
;; once, and the windows are drawn as ever.
(let ([orig draw-wallpaper] [calls 0] [told 0] [plain notify] [drawn 0]
      [w (plain-window "Over" 100 100)])
  (let ([n (count-draws! w)])
    ;; an argument short
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

;; A window opened under an older kit holds a ui this kit cannot read:
;; loading the kit again (as a reload does) opens its app in its place.
(for-each (lambda (w) (when (eq? (window-app w) 'clock) (close-window! w)))
          (windows))
(let ([old (clock)])
  (resize-window! old 300 240)
  (hashtable-set! (window-props old) 'ui 'an-older-kits-ui)
  (let ([x (window-x old)] [y (window-y old)]
        [w (window-w old)] [h (window-h old)])
    (load-sources! '("kits/ui.ss"))
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
(printf "~a\n" (if (zero? failures)
                   "all checks passed"
                   (format "~a check(s) FAILED" failures)))
(exit (if (zero? failures) 0 1))
