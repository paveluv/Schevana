;;; tests/units/grant.ss — apps in sandboxes (services/grant.ss): bundles,
;;; grants, stubs, decisions, an app's own worklets.

;;; Apps in sandboxes (services/grant.ss): bundles, grants, stubs and the
;;; person's decisions.

(check "a tree app that requests bundles runs in its sandbox under /apps, \
        holding them, live, and nothing it did not request; the world's \
        apps run in the world, and (clock) there opens Clock"
       (let* ([c (grant-env 'clock)] [held (environment-symbols
                                            (env-environment c))]
              [w (clock)]
              [ok (and (equal? (env-path c) "/apps/clock")
                       (eq? (env-kind c) 'app) (eq? (env-base c) 'confined)
                       (eq? (env-eval c 'now-ms) now-ms)
                       (eq? (env-eval c 'fill-rect) fill-rect)
                       (not (memq 'notify held)) (not (memq 'windows held))
                       (not (memq 'draw-clock-face
                                  (environment-symbols *world-env*)))
                       (not (grant-env 'settings)) (not (grant-env 'repl))
                       (eq? (window-app w) 'clock)
                       (equal? (grant-requested 'clock)
                               '(window draw timers))
                       (null? (grant-undecided 'clock)))])
         (close-window! w)
         ok))

(check "an app's define-app registers its own app alone, a window it opens \
        is its own or no app's, never another's, and its defvar keeps a value \
        as it loads again, in its sandbox"
       (let* ([c (grant-env 'clock)]
              [w (env-eval c '(open-window "Units" 'app 'settings))]
              [none (env-eval c '(open-window "Units" 'app #f))]
              [ok (and (raises? (lambda ()
                                  (env-eval c '(define-app (units-not-clock)
                                                 "No" #f))))
                       (not (memq 'units-not-clock (apps)))
                       (eq? (window-app w) 'clock)
                       (not (window-app none))
                       (begin (env-eval c '(defvar units-kept 1))
                              (env-eval c '(set! units-kept 2))
                              (env-eval c '(defvar units-kept 1))
                              (= 2 (env-eval c 'units-kept)))
                       (not (memq 'units-kept
                                  (environment-symbols *world-env*))))])
         (close-window! w)
         (close-window! none)
         ok))

(check "an app the person approves: what it requests and no one decided \
        raises, naming it; a decision is saved, makes its sandbox again, \
        and is read back from the file; a denied bundle raises as denied"
       (let* ([before (grant-env 'sketch)]
              [asked (grant-undecided 'sketch)]
              [needed (guard (c [(grant-needed? c) c])
                        (env-eval before '(open-window "x")) #f)])
         (grant-decide! 'sketch '(window) '(draw))
         (let* ([after (grant-env 'sketch)]
                [saved (call-with-input-file *grant-file-path* get-string-all)]
                [denied (guard (c [(grant-needed? c) (condition-message c)])
                          (env-eval after '(fill-rect 0 0 1 1 'red)) #f)])
           (hashtable-clear! *grant-decisions*)
           (grant-file-load!)
           (let ([ok (and (equal? asked '(window draw))
                          needed (eq? (grant-needed-app needed) 'sketch)
                          (eq? (grant-needed-bundle needed) 'window)
                          (string-contains-ci? (condition-message needed)
                                               "Sketch needs Open windows")
                          (env-dropped? before) (not (env-dropped? after))
                          (equal? (env-path after) "/apps/sketch")
                          (string-contains-ci? saved "approved (window)")
                          denied (string-contains-ci? denied "denied")
                          (let-values ([(ok no) (grant-of 'sketch)])
                            (and (equal? ok '(window)) (equal? no '(draw))))
                          (eq? (grant-env 'sketch) after)
                          (null? (grant-undecided 'sketch)))])
             (grant-decide! 'sketch '(window draw) '())
             ok))))

(check "Environments says how an app's requests stand and which bundle \
        each name came in, and what it is there: the world's, or a stub; \
        other environments keep the parent's name, set! and where bound"
       (begin
         (grant-decide! 'sketch '(window) '(draw))
         (let* ([e (grant-env 'sketch)] [rows (env-shared-names e)]
                [text (lambda (n key)
                        (envs-names-text e 'shared (assq n rows) key))]
                [ok (and (eq? (grant-state 'sketch 'draw) 'denied)
                         (eq? (grant-state 'clock 'timers) 'allowed)
                         (eq? (grant-bundle-of 'fill-rect) 'draw)
                         (not (grant-bundle-of 'define-app))
                         (eq? (grant-app-in e) 'sketch)
                         (not (grant-app-in (grant-apps-env)))
                         (equal? (envs-bundle-label 'sketch 'window)
                                 "Open windows")
                         (equal? (envs-bundle-label 'sketch 'draw)
                                 "Draw in its windows · denied")
                         (equal? (envs-bundle-label #f 'toasts)
                                 "Show notifications · 1")
                         (equal? (text 'close-window! 'bundle) "Open windows")
                         (equal? (text 'close-window! 'held) "the world's")
                         (equal? (text 'fill-rect 'bundle)
                                 "Draw in its windows")
                         (equal? (text 'fill-rect 'held) "a stub: denied")
                         (equal? (text 'define-app 'bundle) "Every app's")
                         (equal? (map car (envs-names-columns e 'shared 300))
                                 '(name bundle held))
                         (equal? (map car (envs-names-columns (env-root)
                                                              'shared 300))
                                 '(name from set holder))
                         (begin
                           (hashtable-delete! *grant-decisions* 'sketch)
                           (equal? (envs-bundle-label 'sketch 'draw)
                                   "Draw in its windows · not decided")))])
           (grant-decide! 'sketch '(window draw) '())
           ok)))

(check "an app of the person's runs in a sandbox though it requests \
        nothing, and holds nothing of the world's then"
       (let ([dir (string-append out-dir "/apps")])
         (unless (file-directory? dir) (mkdir dir))
         (call-with-output-file (string-append dir "/units-mine.ss")
           (lambda (p)
             (write '(define-app (units-mine) "Mine" (open-window "Mine")) p))
           'replace)
         (grant-load-app! (string-append dir "/units-mine.ss"))
         (let ([e (grant-env 'units-mine)])
           (and e (equal? (env-path e) "/apps/units-mine")
                (memq 'units-mine (apps))
                (raises? (lambda () (app-launch! 'units-mine)))
                (not (memq 'open-window
                           (environment-symbols (env-environment e))))))))

;;; An app's worklets (services/grant.ss).

(define-worklet (grant-test-square x) (* x x))

(define (units-crew-env) (grant-env 'units-crew))

(let ([dir (string-append out-dir "/apps")])
  (call-with-output-file (string-append dir "/units-crew.ss")
    (lambda (p)
      (for-each
       (lambda (form) (write form p) (newline p))
       '((app-requests crew)
         ;; a name of the world's worklets, and of nothing of this app's
         (define-worklet (crew-map-chunk x) (fx* x 100))
         (define-worklet (units-app-twice x) (fx* x 2))
         (define-worklet (units-app-quad x)
           (units-app-twice (units-app-twice x)))
         (define-worklet (units-app-fact n)
           (if (fx= n 0) 1 (fx* n (units-app-fact (fx- n 1)))))
         (define (units-app-plain x) x)
         (define-app (units-crew) "Crew" (void)))))
    'replace)
  (grant-load-app! (string-append dir "/units-crew.ss")))

(check "an app not yet allowed the crew still loads, and its worklets and \
        the crew raise at the first use, naming the bundle"
       (let ([e (units-crew-env)]
             [needs? (lambda (form)
                       (guard (c [(grant-needed? c)
                                  (eq? (grant-needed-bundle c) 'crew)])
                         (env-eval (units-crew-env) form)
                         #f))])
         (and e (needs? '(units-app-quad 3)) (needs? '(crew-size))
              (needs? '((worklet (x) x) 1)))))

(grant-decide! 'units-crew '(crew) '())

(check "an app's worklets are its own: compiled in its sandbox's environment, \
        out of /worklets, shadowing none of the world's; each sees the \
        others, itself and their redefinitions; the crew runs them"
       (let ([e (units-crew-env)])
         (let ([before (env-eval e '(units-app-quad 3))])
           (env-eval e '(define-worklet (units-app-twice x) (fx* x 3)))
           (and (= before 12)
                (= (env-eval e '(units-app-quad 1)) 9)
                (= (env-eval e '(units-app-fact 5)) 120)
                (= (env-eval e '((worklet (x) (fx+ x 1)) 1)) 2)
                (worklet? (env-eval e 'units-app-twice))
                (equal? (env-eval e '(crew-map units-app-twice '(1 2 3)))
                        '(3 6 9))
                (not (memq 'units-app-quad
                           (environment-symbols *worklet-environment*)))
                (not (memq 'units-app-quad (environment-symbols *world-env*)))
                (equal? (crew-map grant-test-square '(1 2 3)) '(1 4 9))))))

(check "an app's worklet reaches only what any worklet does and its own: not \
        the world's, not its sandbox's other names, not another app's; the \
        crew refuses a plain procedure of it"
       (let ([e (units-crew-env)])
         (define (refused? form)
           (raises? (lambda () (env-eval e form))))
         (and (refused? '(worklet (x) (open-window x)))
              (refused? '(worklet (x) (units-app-plain x)))
              (refused? '(worklet (x) (life-step-rows! x)))
              (refused? '(worklet (x) (set! units-app-twice x)))
              (refused? '(define-worklet (units-app-bad)
                           (set! units-app-gone 1)))
              (refused? '(crew-for 0 10 (lambda (lo hi) #f)))
              (refused? '(crew-map units-app-plain '(1))))))

(check "an app sets the crew no bigger than one thread short of the machine"
       (let ([size (crew-size)])
         (env-eval (units-crew-env) '(crew-size-set! 100000))
         (let ([most (crew-size)])
           (crew-size-set! size)
           (= most (- (host-cpu-count) 1)))))
