;;; tests/reach.ss — how a test reaches past the exports. tests/boot.ss
;;; loads it once the world is loaded. The test goes on in "/", the world
;;; that core1 made, where every name of the core's libraries, of the
;;; world's libraries (what each keeps to itself too) and of the tests' own
;;; environment (core0's libraries and the recorder's, imported there
;;; whole) is forwarded and may be set (set!, fluid-let), so that the tests
;;; can stand in for SDL and the screen and look into the core and the
;;; apps. The world itself has only what the core's facade, (schevana
;;; core), gives it, read-only, and what the world's libraries export.
;;; What the test defined before it loaded the tree is forwarded too, and
;;; so are main-env and core-env (the tests' environment, and an
;;; environment with the core's libraries whole), for what goes by name
;;; (top-level-value).
;;;
;;; In the hacker edition the tests' environment is the world, which
;;; already has every name of every library, to set as any other: main-env,
;;; core-env and world-env are the same environment.

(define main-env (interaction-environment))

;; An environment with the core's libraries whole, internals included, for
;; the tests to look into, along with the desktop's start; the world has
;; only what the core's facade gives. A library is imported here again when
;; a reload evaluates it again (reload-import!).
(define core-env
  (if test-hacker? main-env (copy-environment (scheme-environment) #t)))
(unless test-hacker?
  (for-each (lambda (lib) (reload-import! core-env lib lib))
            '((schevana tree) (schevana core platform)
              (schevana core theme-table)
              (schevana core processes) (schevana core gpu)
              (schevana core fonts) (schevana core draw) (schevana core pacer)
              (schevana core pacer2) (schevana core screen) (schevana core loop)
              (schevana core theme) (schevana core windows)
              (schevana core sources) (schevana desktop main))))
(define world-env (eval '*world-env* core-env))

;; Where the tests go on, with their reach: "/" itself. The exception is a
;; docs page's run (tests/units/docs.ss), whose examples run at "/" as
;; typed at a REPL there, with only what the world gives it. There the
;; tests go on in a copy of "/" made once the world has loaded, and their
;; names and reach are in the copy alone.
(define test-env
  (if (and (not test-hacker?) (getenv "SCHEVANA_DOCS_PAGE"))
      (copy-environment world-env #t)
      world-env))

;; The recorder's library whole, internals included, for the tests to look
;; into; the core has only what the recorder's facade gives.
(unless test-hacker? (eval '(import (schevana recorder bytes)) main-env))

;; The forwarders, and the names the tests' build gives.
(load (string-append *schevana-root* "/tests/given.ss"))

;; A library's parts, in the folder of its name ((schevana styles open-look
;; fonts)), which "/" has only through the library that imports them:
;; imported here as well, so that their names reach the tests too.
(unless test-hacker?
  (let ([loaded (library-list)])
    (for-each (lambda (name)
                (when (and (eq? (car name) 'schevana) (> (length name) 3)
                           (member (list-head name (- (length name) 1))
                                   loaded))
                  (reload-import! core-env name name)))
              loaded)))

(unless test-hacker?
  (reach-given! main-env)
  (reach-given! core-env)
  ;; the world's libraries, which "/" imports
  (reach-given! test-env))

;;; ------------------------------------------------------------------
;;; a library's own names
;;; A test asks nothing of a library: no export, hook or name of its own
;;; for the test. It reaches what the library keeps to itself by stripping
;;; it, as the hacker edition strips every library. In the library
;;; edition, the library's body is evaluated again at the top level of an
;;; environment of its own, after its imports and the top level's forms as
;;; the hacker edition has them (src/base.ss, src/strip.ss). In the hacker
;;; edition, it is the library as the world loads it (loading it first, if
;;; the world hasn't), with its names in "/". Its names come to "/" under a
;;; prefix, so that none of them clashes with one of the world's.
;;;
;;;   (test-library '(demo boids) 'bo:)
;;;   (bo:boids-step (bo:boids-scatter 3 100 100) bo:boids-default-rules)
;;;   (fluid-let ([bo:boids-scatter (lambda (n w h) (make-flvector 0))])
;;;     ...)
;;;
;;; Each name is settable, and a set (a fluid-let's stand-in) reaches the
;;; library itself, since its calls to its own procedures go through the
;;; top level. Stripped again, it is another instance of the library, with
;;; state of its own, and its app is the one that the launcher opens.

;; Returns the source file of library name, from the first folder of the
;; library search path that holds it.
(define (test-library-file name)
  (let ([rel (string-append
              (apply string-append
                     (map (lambda (part)
                            (string-append "/" (symbol->string part)))
                          name))
              ".sls")])
    (or (exists (lambda (d)
                  (let ([f (string-append (if (pair? d) (car d) d) rel)])
                    (and (file-exists? f) f)))
                (library-directories))
        (errorf 'test-library "no source for ~s" name))))

(define (test-library name prefix)
  (let* ([form (call-with-input-file (test-library-file name) read)]
         [body (cddddr form)]          ; past its name, exports and imports
         [env (if test-hacker?
                  ;; in the world, which loads it if it hasn't
                  (begin (load-sources! (list name)) world-env)
                  (let* ([e (copy-environment (scheme-environment) #t)]
                         [in-e (lambda (x) (eval x e))])
                    (eval `(import ,@(cdr (cadddr form))) e)
                    (for-each (lambda (f)
                                (load (string-append *schevana-root* f) in-e))
                              '("/src/base.ss" "/src/strip.ss"))
                    (for-each in-e body)
                    e))]
         [anchor (environment-anchor env)])
    (for-each (lambda (n)
                (define-top-level-syntax
                  (string->symbol (string-append (symbol->string prefix)
                                                 (symbol->string n)))
                  (reach-forwarder (datum->syntax anchor n))
                  test-env))
              (apply append (map test-defined-names body)))))

;; Forwards each name of the two environments (core-env and main-env) into
;; "/" (test-env), from the first of them that has it, a state or a hook
;; (a macro) the same way as a variable, so that each can be set
;; (top-level-syntax? is true of every one of them). What the facade gives
;; of core0's, a view, is forwarded from the tests' environment, which has
;; the state itself. A name that "/" already had stays as it is, except
;; what the facade gives, which becomes settable.
(unless test-hacker?
  (let ([had (make-eq-hashtable)]
        [envs (list core-env main-env)])
    (for-each (lambda (n) (hashtable-set! had n #t))
              (environment-symbols test-env))
    (for-each (lambda (n) (hashtable-delete! had n))
              (library-exports '(schevana core)))
    (for-each
     (lambda (e)
       (let ([anchor (environment-anchor e)])
         (for-each
          (lambda (n)
            (unless (or (gensym? n) (reach-given? n)
                        (hashtable-ref had n #f))
              (hashtable-set! had n #t)
              (define-top-level-syntax n
                (reach-forwarder (datum->syntax anchor n))
                test-env)))
          (environment-symbols e))))
     envs)))

(interaction-environment test-env)
