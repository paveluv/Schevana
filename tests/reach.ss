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
