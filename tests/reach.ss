;;; tests/reach.ss — how a test reaches past the exports, loaded by
;;; tests/lib.ss once the world is loaded: the test goes on in "/", the
;;; world core1 made, where every name of the core's libraries, and of the
;;; tests' own environment (core0's libraries and the recorder's, imported
;;; there whole), is forwarded and may be set (set!, fluid-let), as the
;;; tests stand in for SDL and the screen and look into the core. The world
;;; itself has only what the core's facade gives it, (schevana core),
;;; read-only. What the test defined before it loaded the tree is forwarded
;;; too, and so are main-env and core-env, the tests' environment and one of
;;; the core's libraries whole, for what goes by name (top-level-value).
;;;
;;; In the hacker edition the tests' environment is the world, every name
;;; of every library there already, to set as any other: main-env, core-env
;;; and world-env are the one.

(define main-env (interaction-environment))

;; The core's libraries whole, their internals with them, which the tests
;; look into, the desktop's start, and the sockets' (a client's end); the
;; world has only what the core's facade gives. Imported again as a reload
;; evaluates one again (reload-import!).
(define core-env
  (if test-hacker? main-env (copy-environment (scheme-environment) #t)))
(unless test-hacker?
  (for-each (lambda (lib) (reload-import! core-env lib))
            '((schevana tree) (schevana socket) (schevana core platform)
              (schevana core theme-table)
              (schevana core processes) (schevana core gpu)
              (schevana core fonts) (schevana core draw) (schevana core pacer)
              (schevana core screen) (schevana core loop)
              (schevana core theme) (schevana core windows)
              (schevana core sources) (schevana desktop main))))
(define world-env (eval '*world-env* core-env))

;; The recorder's library whole, its internals with it, which the tests
;; look into; the core has only its facade's.
(unless test-hacker? (eval '(import (schevana recorder bytes)) main-env))

;; A forwarder to id's binding that a set! goes through, as fluid-let's do.
(define (reach-forwarder id)
  (make-variable-transformer
   (lambda (x)
     (syntax-case x (set!)
       [(set! _ v) #`(set! #,id v)]
       [_ (identifier? x) id]
       [(_ . rest) #`(#,id . rest)]))))

;;; ------------------------------------------------------------------
;;; a library's own names
;;; A test asks nothing of a library: no export, hook or name of its own
;;; for the test. It reaches what the library keeps to itself by stripping
;;; it, as the hacker edition strips every library: in the library
;;; edition, its body evaluated again at the top level of an environment
;;; of its own, after its imports and the top level's forms as the hacker
;;; edition has them (src/base.ss, src/strip.ss); in the hacker edition,
;;; as it is, its names in "/" already. Its names come to "/" under a
;;; prefix, so that none of them is one of the world's.
;;;
;;;   (test-library '(schevana-demo springies) 'sp:)
;;;   (sp:pt+ (sp:make-pt 1.0 2.0) sp:pt-zero)
;;;   (fluid-let ([sp:springies-controls-size (lambda () (values 100 100))])
;;;     ...)
;;;
;;; Each is settable, and a set (fluid-let's stand-in) is the library's
;;; own: its calls to its procedures go by the top level. Stripped again,
;;; it is another of the library: its state its own, its app the one the
;;; launcher opens.

;; The names a body form of a library defines: a record type's too, by
;; R6RS's rules for the names it makes.
(define (test-library-defined form)
  (define (name+ . parts)
    (string->symbol
     (apply string-append
            (map (lambda (x) (if (symbol? x) (symbol->string x) x)) parts))))
  (define (record-names spec clauses)
    (let ([name (if (pair? spec) (car spec) spec)]
          [fields (let ([f (assq 'fields clauses)]) (if f (cdr f) '()))])
      (append
       (list name)
       (if (pair? spec) (cdr spec) (list (name+ "make-" name) (name+ name "?")))
       (apply append
              (map (lambda (f)
                     (cond [(symbol? f) (list (name+ name "-" f))]
                           [(pair? (cddr f)) (cddr f)]
                           [(eq? (car f) 'mutable)
                            (list (name+ name "-" (cadr f))
                                  (name+ name "-" (cadr f) "-set!"))]
                           [else (list (name+ name "-" (cadr f)))]))
                   fields)))))
  (if (not (pair? form))
      '()
      (case (car form)
        [(begin) (apply append (map test-library-defined (cdr form)))]
        [(define-record-type) (record-names (cadr form) (cddr form))]
        [(define define-syntax define-state define-made define-hook
          define-worklet define-compute-shader define-paint define-app
          define-part)
         (let ([n (let first ([x (cadr form)])
                    (if (pair? x) (first (car x)) x))])
           (if (eq? (car form) 'define-part)
               (list n (name+ n "*"))
               (list n)))]
        [else '()])))

;; The source of library name: the first folder of the library search
;; that holds it.
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
                  world-env
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
                  world-env))
              (apply append (map test-library-defined body)))))

;; Each name of the two's, in "/", from the first of the core's and the
;; tests' that has it, a state or a hook (a macro) as a variable is, to be
;; set (by its names: top-level-syntax? says so of any name). What the
;; facade gives of core0's, a view, comes from the tests', which has the
;; state itself. A name "/" had already stays as it is but for what the
;; facade gives, which becomes settable.
(unless test-hacker?
  (let ([had (make-eq-hashtable)]
        [envs (list core-env main-env)])
    (for-each (lambda (n) (hashtable-set! had n #t))
              (environment-symbols world-env))
    (for-each (lambda (n) (hashtable-delete! had n))
              (library-exports '(schevana core)))
    (for-each
     (lambda (e)
       (let ([anchor (environment-anchor e)])
         (for-each
          (lambda (n)
            (unless (or (gensym? n) (hashtable-ref had n #f))
              (hashtable-set! had n #t)
              (define-top-level-syntax n
                (reach-forwarder (datum->syntax anchor n))
                world-env)))
          (environment-symbols e))))
     envs)))

(interaction-environment world-env)
