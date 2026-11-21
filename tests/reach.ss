;;; tests/reach.ss — how a test reaches past the exports, loaded right after
;;; main.ss: the test goes on in "/", the world core1 made, where every name
;;; of the core's libraries, and of main.ss's environment (core0's libraries
;;; and the recorder's, imported there whole), is forwarded and may be set
;;; (set!, fluid-let), as the tests stand in for SDL and the screen and look
;;; into the core. The world itself has only what the core's facade gives
;;; it, (schevana core), read-only. What the test defined before it loaded
;;; the tree is forwarded too, and so are main-env and core-env, main.ss's
;;; environment and one of the core's libraries whole, for what goes by
;;; name (top-level-value).

(define main-env (interaction-environment))

;; The core's libraries whole, their internals with them, which the tests
;; look into, and the sockets' (a client's end); the world has only what
;; the core's facade gives. Imported again as a reload evaluates one again
;; (reload-import!).
(define core-env (copy-environment (scheme-environment) #t))
(for-each (lambda (lib) (reload-import! core-env lib))
          '((schevana tree) (schevana socket) (schevana core platform)
            (schevana core theme-table)
            (schevana core processes) (schevana core gpu)
            (schevana core fonts) (schevana core draw) (schevana core pacer)
            (schevana core screen) (schevana core loop)
            (schevana core theme) (schevana core windows)
            (schevana core sources)))
(define world-env (eval '*world-env* core-env))

;; The recorder's library whole, its internals with it, which the tests
;; look into; the core has only its facade's.
(eval '(import (schevana recorder bytes)) main-env)

;; A forwarder to id's binding that a set! goes through, as fluid-let's do.
(define (reach-forwarder id)
  (make-variable-transformer
   (lambda (x)
     (syntax-case x (set!)
       [(set! _ v) #`(set! #,id v)]
       [_ (identifier? x) id]
       [(_ . rest) #`(#,id . rest)]))))

;; Each name of the two's, in "/", from the first of the core's and
;; main.ss's that has it, a state or a hook (a macro) as a variable is,
;; to be set (by its names: top-level-syntax? says so of any name). What
;; the facade gives of core0's, a view, comes from main.ss's, which has
;; the state itself. A name "/" had already stays as it is but for what
;; the facade gives, which becomes settable.
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
   envs))

;; Core0's own clock, which times the screen's waits: the world's now-ns is
;; another, the core's.
(define-top-level-syntax 'core0-now-ns
  (reach-forwarder (datum->syntax #'main-env 'now-ns))
  world-env)

(interaction-environment world-env)
