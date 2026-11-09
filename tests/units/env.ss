;;; tests/units/env.ss — environments (services/env.ss) and the confined base.

;;; Environments (services/env.ss): a child sees what its parent shares,
;;; live, and changes none of it.

(define units-env-value 1)
(define (units-env-get) units-env-value)
(define units-env-secret 'root)
(define units-env-size 1)
(define (units-env-size-set! v)
  (unless (fixnum? v) (errorf 'units-env-size-set! "no fixnum: ~s" v))
  (set! units-env-size v))

(define units-env (env-child (env-root) 'units 'chez))
(env-share! units-env '(units-env-get (value . units-env-value)))
(env-share-setter! units-env '(size . units-env-size) 'units-env-size-set!)

(check "a child's path is its name under its parent's, and finds it; a \
        sibling of the same name is numbered"
       (let* ([twin (env-child (env-root) 'units 'chez)]
              [inner (env-child units-env 'inner 'core)]
              [ok (and (equal? (env-path (env-root)) "/")
                       (equal? (env-path units-env) "/units")
                       (equal? (env-path twin) "/units-2")
                       (equal? (env-path inner) "/units/inner")
                       (eq? (env-find "/units/inner") inner)
                       (eq? (env-find "/") (env-root))
                       (eq? (env-find "/worklets/") (env-find "/worklets"))
                       (not (env-find "/units/none"))
                       (equal? (format "~s ~s" (env-root) inner)
                               "#<env /> #<env /units/inner core>"))])
         (env-drop! twin)
         (env-drop! inner)
         ok))

(check "what a child is shared is live: a set! and a redefinition in the \
        world reach it, a pair renames"
       (let ([before (env-eval units-env '(list (units-env-get) value))])
         (set! units-env-value 2)
         (set! units-env-get (lambda () (* 10 units-env-value)))
         (let ([after (env-eval units-env '(list (units-env-get) value))])
           (set! units-env-get (lambda () units-env-value))
           (and (equal? before '(1 1)) (equal? after '(20 2))))))

(check "a child's set! of a shared name is refused as an R6RS import's \
        is; a name not shared is unbound there, and the child's set! of it \
        makes its own"
       (and (guard (c [#t (and (syntax-violation? c)
                               (equal? (condition->string c)
                                       "Exception: attempt to assign \
                                        read-only variable value"))])
              (env-eval units-env '(set! value 5))
              #f)
            (guard (c [#t #t]) (env-eval units-env 'units-env-secret) #f)
            (begin (env-eval units-env '(set! units-env-secret 'child))
                   (eq? (env-eval units-env 'units-env-secret) 'child))
            (= units-env-value 2)
            (eq? units-env-secret 'root)))

(check "a child's define of a shared name makes its own; the world's is \
        unchanged"
       (let ([e (env-child (env-root) 'units-own 'chez)])
         (env-share! e '(units-env-get))
         (env-eval e '(define (units-env-get) 'mine))
         (let ([ok (and (eq? (env-eval e '(units-env-get)) 'mine)
                        (= (units-env-get) 2))])
           (env-drop! e)
           ok)))

(check "a setter: the child's set! calls the world's setter, which may \
        refuse"
       (begin
         (env-eval units-env '(set! size 4))
         (and (= units-env-size 4)
              (= (env-eval units-env 'size) 4)
              (guard (c [#t (= units-env-size 4)])
                (env-eval units-env '(set! size 'big))
                #f))))

(check "a grandchild shares its parent's own names, and its parent's \
        shares, still read-only and live"
       (let ([g (env-child units-env 'grand 'chez)])
         (env-eval units-env '(define units-env-mine 'child))
         (env-share! g '(units-env-mine value))
         (set! units-env-value 3)
         (let ([ok (and (equal? (env-eval g '(list units-env-mine value))
                                '(child 3))
                        (guard (c [#t (syntax-violation? c)])
                          (env-eval g '(set! value 0))
                          #f))])
           (env-drop! g)
           ok)))

(check "env-binding follows a share to the world's binding"
       (let-values ([(env name) (env-binding units-env 'value)]
                    [(own own-name) (env-binding units-env 'units-env-secret)])
         (and (eq? env *world-env*) (eq? name 'units-env-value)
              (eq? own (env-environment units-env))
              (eq? own-name 'units-env-secret))))

(check "env-load loads into the child: a shared defvar defines there, and \
        keeps its value at the next load"
       (let ([f (string-append out-dir "/units-env-file.ss")])
         (call-with-output-file f
           (lambda (p) (write '(defvar units-env-loaded value) p))
           'replace)
         (env-share! units-env '(defvar))
         (env-load units-env f)
         (set! units-env-value 9)
         (env-load units-env f)
         (set! units-env-value 3)
         (and (= (env-eval units-env 'units-env-loaded) 3)
              (not (top-level-bound? 'units-env-loaded)))))

(define units-env-world (env-child (env-root) 'units-world 'chez))
(env-share-world! units-env-world)
(env-eval units-env-world '(define units-env-later 'mine))
(define units-env-later 'world)
(define units-env-newer 'world)

(check "a world namespace has every name of the world's, and gains those \
        the world defines later, but for those it defined itself"
       (and (eqv? (env-eval units-env-world '(length (windows)))
                  (length (windows)))
            (eq? (env-eval units-env-world 'units-env-newer) 'world)
            (eq? (env-eval units-env-world 'units-env-later) 'mine)
            (guard (c [#t (syntax-violation? c)])
              (env-eval units-env-world '(set! units-env-newer 0))
              #f)))

(check "a private namespace sees its list of the world's, live, and only \
        it"
       (let ([e (env-fork (env-root) 'private)])
         (let ([ok (and (eq? (env-eval e '(windows)) (windows))
                        (guard (c [#t #t]) (env-eval e 'set-theme!) #f)
                        (guard (c [#t (syntax-violation? c)])
                          (env-eval e '(set! windows 0))
                          #f))])
           (env-drop! e)
           ok)))

(check "a sandbox's children are sandboxes on its base, shared what it \
        holds, its own names and its shares, read-only"
       (let ([box (env-child (env-root) 'units-box 'core)])
         (env-share! box '(units-env-get))
         (env-eval box '(define units-box-own 7))
         (let ([inner (env-child box 'inner 'core)])
           (env-share! inner '(units-box-own units-env-get))
           (let ([ok (and (raises? (lambda () (env-child box 'ns 'chez)))
                          (equal? (env-eval inner
                                            '(list units-box-own
                                                   (units-env-get)))
                                  (list 7 (units-env-get)))
                          (guard (c [#t (syntax-violation? c)])
                            (env-eval inner '(set! units-box-own 1))
                            #f))])
             (env-drop! box)
             ok))))

(check "an environment forks only the kinds its own allows, refuses \
        what is not its to share and options it does not take, and hands \
        forks down: a world namespace's makes all the world's, not an \
        app's sandbox, a sandbox's sandboxes and threads, a pure one holds \
        none"
       (let* ([w (env-fork (env-root) 'world)]
              [wf (env-eval w 'fork)]
              [s (env-find (wf 'sandbox))]
              [sf (env-eval s 'fork)]
              [p (env-find (wf 'pure))])
         (env-eval s '(define units-fork-own 3))
         (let* ([inner (env-find (sf 'sandbox 'share '(units-fork-own)))]
                [named (env-find (sf 'sandbox 'name 'units-named))]
                [t (env-find (sf 'thread))]
                [ok (and (equal? (wf) (env-forks (env-root)))
                         (not (memq 'app (wf)))
                         (raises? (lambda () (wf 'app)))
                         (equal? (sf) '(sandbox thread))
                         (raises? (lambda () (sf 'private)))
                         (raises? (lambda ()
                                    (sf 'sandbox 'share '(units-env-value))))
                         (raises? (lambda () (sf 'sandbox 'colour 1)))
                         (raises? (lambda () (sf 'sandbox 'name 'a/b)))
                         (raises? (lambda () (env-fork p 'pure)))
                         (= (env-eval inner 'units-fork-own) 3)
                         (eq? (env-parent inner) s)
                         (equal? (env-path named)
                                 (string-append (env-path s) "/units-named"))
                         (equal? ((env-eval inner 'fork)) '(sandbox thread))
                         (vat-of t)
                         (eq? (env-kind t) 'thread)
                         (null? (env-forks t))
                         (null? (env-forks p))
                         (not (top-level-bound? 'fork (env-environment p))))])
           (vat-drop-env! w)
           ok)))

(check "a fork shares what it is given, renamed and through setters, after \
        its kind's own; what a child holds is its shares and its own names"
       (let ([c (env-fork (env-root) 'pure 'name 'units-given
                          'share '(units-env-get (v . units-env-value))
                          'setters '(((sz . units-env-size)
                                      . units-env-size-set!)))])
         (env-eval c '(set! sz 6))
         (env-eval c '(define units-given-own 1))
         (let ([ok (and (equal? (env-path c) "/units-given")
                        (eq? (env-kind c) 'pure)
                        (= units-env-size 6)
                        (equal? (env-eval c '(list (units-env-get) v))
                                (list (units-env-get) units-env-value))
                        (equal? (env-shared-names c)
                                '((sz units-env-size units-env-size-set! #f)
                                  (units-env-get units-env-get #f #f)
                                  (v units-env-value #f #f)))
                        (equal? (env-own-names c) '(units-given-own))
                        (raises? (lambda ()
                                   (env-fork (env-root) 'pure
                                             'share '(units-not-a-name)))))])
           (env-drop! c)
           ok)))

(check "the file dialog's paths: crumbs from Home or the computer, names \
        resolved against the folder, whole and without . or .., sizes and \
        dates as people read them"
       (and (equal? (file-dialog-crumbs "/home/u/code/x" "/home/u")
                    '(("Home" . "/home/u") ("code" . "/home/u/code")
                      ("x" . "/home/u/code/x")))
            (equal? (file-dialog-crumbs "/etc" "/home/u")
                    '(("Computer" . "/") ("etc" . "/etc")))
            (equal? (file-dialog-crumbs "/" "/home/u") '(("Computer" . "/")))
            (equal? (file-dialog-resolve "/a/b" "c") "/a/b/c")
            (equal? (file-dialog-resolve "/a/b" "/x/") "/x")
            (equal? (file-dialog-resolve "/" "c") "/c")
            (equal? (file-dialog-resolve "/a/b" "../c/./d/") "/a/c/d")
            (equal? (file-dialog-resolve "/a" "..") "/")
            (equal? (file-dialog-resolve "." ".")
                    (file-dialog-clean (current-directory)))
            (equal? (file-dialog-crumbs (file-dialog-resolve "/" "/x/./y")
                                        "/home/u")
                    '(("Computer" . "/") ("x" . "/x") ("y" . "/x/y")))
            (equal? (file-dialog-above "/a/b") "/a")
            (equal? (file-dialog-above "/a") "/")
            (equal? (file-dialog-size-label 512) "512 bytes")
            (equal? (file-dialog-size-label 4200) "4.2 KB")
            (equal? (file-dialog-size-label 1300000) "1.3 MB")
            (let ([now (time-second (current-time))])
              (and (= 5 (string-length (file-dialog-date-label now now)))
                   (string-contains-ci? (file-dialog-date-label 86400 now)
                                        ", 1970")))))

(check "the world forks every kind, in the order registered; a bare child \
        forks nothing and is titled by its base"
       (let ([c (env-child (env-root) 'units-bare 'core)])
         (let ([ok (and (equal? (env-forks (env-root))
                                '(private world pure sandbox thread))
                        (null? (env-forks (env-worklets)))
                        (string=? (env-title (env-root)) "The world")
                        (string=? (env-title (env-worklets)) "Worklets")
                        (null? (env-forks c)) (not (env-kind c))
                        (string=? (env-title c) "Sandbox"))])
           (env-drop! c)
           ok)))

(check "a share as typed in Environments: a name, renamed with as, set \
        through a setter with via"
       (let ([read (lambda (s) (call-with-values
                                 (lambda () (envs-share-words s))
                                 list))])
         (and (equal? (read "now-ms") '(now-ms #f))
              (equal? (read "now-ms as clock") '((clock . now-ms) #f))
              (equal? (read "size via size-set!") '(size size-set!))
              (equal? (read " a  as b via c ") '((b . a) c))
              (equal? (read "a b") '(#f #f)))))

(check "a REPL's tinted background follows the style: one opened in Mac \
        and shown in Genera has Genera's, as one opened there"
       (let* ([rgb (lambda (w) (call-with-values
                                 (lambda () (color-rgba (window-bg w)))
                                 list))]
              [a (begin (set-style! 'mac) (repl 'private))]
              [in-mac (rgb a)]
              [b (begin (set-style! 'genera) (repl 'private))]
              [ok (and (not (equal? in-mac (rgb a)))
                       (equal? (rgb a) (rgb b)))])
         (close-window! a)
         (close-window! b)
         (set-style! 'mac)
         ok))

(check "a dialog stays above the window that waits on it and takes its \
        keyboard, where the style says so (modal-above); else the window \
        comes above it; closing the window closes the dialog at once"
       (let* ([p (open-window "Parent" 'size '(300 . 200))]
              [c (ui-open-modal p "Child" 200 100)])
         (focus-window! p)
         (let ([kept (and (eq? (focused-window) c) (eq? (car (windows)) c)
                          (eq? (cadr (windows)) p))])
           (override! 'modal-above #f)
           (focus-window! p)
           (let ([up (and (eq? (focused-window) p) (eq? (car (windows)) p))])
             (override! 'modal-above)
             (close-window! p)
             (and kept up (not (memq c (windows))))))))

(check "a window's title icon is drawn by the Mac and Windows styles' \
        frames, left of the title; Genera's busy mark is a terminal's \
        spinner in a character's cell, and its who line says Run"
       (let* ([at #f]
              [w (open-window "Iconic" 'size '(400 . 200)
                              'title-icon (lambda (x y s flags)
                                            (set! at (list x s flags))))]
              [drawn (lambda (style)
                       (set-style! style)
                       (set! at #f)
                       (invalidate!)
                       (steps 1)
                       at)])
         (let* ([mac (drawn 'mac)] [windows (drawn 'windows)])
           (set-style! 'genera)
           (focus-window! w)
           (window-set! w 'busy "Running")
           (let* ([state (genera-who-state)]
                  [idle (begin (window-set! w 'busy #f)
                               (genera-who-state))]
                  [size (call-with-values ui-busy-size list)]
                  [cell (list (font-char-width 'mono)
                              (font-line-height 'mono))])
             (set-style! 'mac)
             (close-window! w)
             (and mac (< (car mac) (+ (window-x w) (/ (window-w w) 2)))
                  (= (cadr mac) (ui-glyph-size)) (null? (caddr mac))
                  windows (< (car windows) (+ (window-x w) 40))
                  (equal? state "Run") (equal? idle "")
                  (assq 'windows (genera-who-line-areas))
                  (equal? size cell)
                  (equal? (call-with-values ui-busy-size list)
                          (list (ui-glyph-size) (ui-glyph-size))))))))

(check "a world namespace's next sync brings the names the world gained \
        since, but those it defined itself; env-sync! shares them now"
       (let ([w (env-fork (env-root) 'world 'name 'units-sync)])
         (eval '(define units-sync-later 1) *world-env*)
         (eval '(define units-sync-mine 2) *world-env*)
         ;; not by env-eval, which syncs first
         (eval '(define units-sync-mine 'its-own) (env-environment w))
         (let* ([before (env-unsynced w)]
                [ok (and (memq 'units-sync-later before)
                         (not (memq 'units-sync-mine before))
                         (begin (env-sync! w) (null? (env-unsynced w)))
                         (assq 'units-sync-later (env-shared-names w))
                         (eq? (env-eval w 'units-sync-mine) 'its-own)
                         (null? (env-unsynced units-env)))])
           (env-drop! w)
           ok)))

(check "the share dialog's names as fork and env-share! take them, and as \
        the Fork sheet's chips"
       (let-values ([(shares setters)
                     (envs-picked-shares '((a "" "") (b "bee" "")
                                           (c "" "c-set!")
                                           (d "dee" "d-set!")))])
         (and (equal? shares '(a (bee . b)))
              (equal? setters '((c . c-set!) ((dee . d) . d-set!)))
              (raises? (lambda () (envs-picked-shares '((a "a b" "")))))
              (equal? (envs-picked-chip '(d "dee" "d-set!"))
                      "d as dee via d-set!")
              (equal? (envs-chip-picked "d as dee via d-set!")
                      '(d "dee" "d-set!"))
              (equal? (envs-chip-picked "a") '(a "" "")))))

(check "dropping a child takes it, and its children, out of the tree and \
        marks them dropped; not the world, nor /worklets, nor /apps"
       (let ([g (env-child units-env-world 'grand 'chez)])
         (env-drop! units-env-world)
         (env-drop! units-env)
         (and (env-dropped? g)
              (env-dropped? units-env)
              (raises? (lambda () (env-child g 'more 'chez)))
              (raises? (lambda () (env-drop! (env-root))))
              (raises? (lambda () (env-drop! (env-worklets))))
              (raises? (lambda () (env-drop! (grant-apps-env))))
              (not (env-find "/units-world/grand"))
              (not (env-find "/units"))
              (not (memq units-env (env-children (env-root))))
              (equal? (map env-name (env-children (env-root)))
                      '(worklets apps)))))

;;; The confined base (services/env.ss): what is always safe, for apps.

(check "a confined sandbox has what is always safe, and nothing that \
        reaches past its arguments: no files, eval or environments, C, \
        threads or sleep, the clock, the inspector, the console's ports or \
        exit; its children are confined or core, never chez"
       (let* ([e (env-child (env-root) 'units-confined 'confined)]
              [held (environment-symbols (env-environment e))]
              [ok (and (for-all (lambda (n) (not (memq n held)))
                                '(eval expand load interaction-environment
                                  environment copy-environment top-level-value
                                  set-top-level-value! define-top-level-value
                                  foreign-procedure load-shared-object
                                  fork-thread make-mutex sleep open-input-file
                                  open-output-file open-file-input-port
                                  file-exists? delete-file directory-list
                                  system process getenv exit current-time
                                  real-time current-date record-rtd inspect
                                  inspect/object collect-request-handler
                                  print-radix syntax-case datum->syntax
                                  console-output-port current-input-port
                                  read))
                       (equal? (env-eval e '(let ([v (make-fxvector 2 1)])
                                              (fxvector-set! v 0 (fx+ 1 2 3))
                                              (list (fxvector->list v)
                                                    (sort < '(3 1 2))
                                                    (format "~a!" 'x))))
                               '((6 1) (1 2 3) "x!"))
                       (raises? (lambda () (env-child e 'units-wider 'chez)))
                       (eq? (env-base (env-child e 'units-narrower 'core))
                            'core)
                       (equal? (env-title e) "Sandbox"))])
         (env-drop! e)
         ok))

(check "a confined sandbox's record types are its own: one named by a uid \
        stays one type as it is defined again, and is never the world's"
       (let* ([e (env-child (env-root) 'units-records 'confined)]
              [named '(define-record-type env
                        (nongenerative schevana-env-3)
                        (fields a))])
         (env-eval e named)
         (let ([kept (env-eval e '(make-env 1))])
           (env-eval e named)
           (let ([ok (and (= 1 (env-eval e '(begin
                                              (define-record-type units-pt
                                                (fields x))
                                              (units-pt-x (make-units-pt 1)))))
                          ((env-eval e 'env?) kept)
                          (not ((env-eval e 'env?) (env-root)))
                          (eq? (record-type-uid
                                (env-eval e '(make-record-type-descriptor
                                              'q #f 'schevana-grant-app-1 #f
                                              #f '#())))
                               '/units-records:schevana-grant-app-1))])
             (env-drop! e)
             ok))))

(check "what a confined sandbox writes to the console goes to its log, and \
        to the caller's output too while root evaluates there (a REPL's)"
       (let* ([e (env-child (env-root) 'units-log 'confined)]
              [out (open-output-string)])
         (parameterize ([current-output-port out])
           (env-eval e '(begin (display "a") (newline) (printf "~a" 1)
                               (format #t "b") (write "c" (current-output-port))
                               (define (units-say) (display "!")))))
         ((env-eval e 'units-say))   ; no evaluation: the log alone
         (let ([ok (and (equal? (env-log e) "a\n1b\"c\"!")
                        (equal? (get-output-string out) "a\n1b\"c\""))])
           (env-drop! e)
           ok)))
