;;; tests/reach.ss — how a test reaches past the exports, loaded right after
;;; main.ss: the test goes on in "/", the world core1 made, where every name
;;; of core1's, the recorder's and core0's own is forwarded and may be set
;;; (set!, fluid-let), as the tests stand in for SDL and the screen and look
;;; into the core. The world itself has only what core1 exports
;;; (src/core1/export.ss), read-only. What the test defined before it loaded
;;; the tree is forwarded too, and so are core0-env and core1-env, core0's
;;; environment and core1's, for what goes by name (top-level-value).

(define core0-env (interaction-environment))
(define core1-env *core0-core1*)
(define world-env (top-level-value '*world-env* core1-env))

;; A forwarder to id's binding that a set! goes through, as fluid-let's do.
(define (reach-forwarder id)
  (make-variable-transformer
   (lambda (x)
     (syntax-case x (set!)
       [(set! _ v) #`(set! #,id v)]
       [_ (identifier? x) id]
       [(_ . rest) #`(#,id . rest)]))))

;; Each name of the three's, in "/": a variable's, settable, from the first
;; of core1, the recorder and core0 that has it as a variable; a macro's,
;; from the first that has it (by its names: top-level-syntax? says so of
;; any name). A name "/" had already stays as it is but for core1's
;; exports, which become settable.
(let ([had (make-eq-hashtable)]
      [exported (exports-names (top-level-value 'core1-exports core1-env)
                               'world)]
      [envs (list core1-env (core0-recorder-environment) core0-env)])
  (for-each (lambda (n) (hashtable-set! had n #t))
            (environment-symbols world-env))
  (for-each (lambda (n) (hashtable-delete! had n)) exported)
  (let ([anchors (map environment-anchor envs)])
    (define (reach! n bound?)
      (unless (or (gensym? n) (hashtable-ref had n #f))
        (let loop ([es envs] [as anchors])
          (cond
            [(null? es) #f]
            [(bound? n (car es))
             (hashtable-set! had n #t)
             (define-top-level-syntax n
               (reach-forwarder (datum->syntax (car as) n))
               world-env)]
            [else (loop (cdr es) (cdr as))]))))
    (for-each (lambda (e)
                (for-each (lambda (n) (reach! n top-level-bound?))
                          (environment-symbols e)))
              envs)
    (let ([has (map (lambda (e)
                      (let ([t (make-eq-hashtable)])
                        (for-each (lambda (n) (hashtable-set! t n #t))
                                  (environment-symbols e))
                        (cons e t)))
                    envs)])
      (for-each (lambda (e)
                  (for-each (lambda (n)
                              (reach! n (lambda (n e)
                                          (hashtable-ref (cdr (assq e has))
                                                         n #f))))
                            (environment-symbols e)))
                envs))))

;; Core0's own clock, which times the screen's waits: the world's now-ns is
;; another, core1's.
(define-top-level-syntax 'core0-now-ns
  (reach-forwarder (datum->syntax #'core0-env 'now-ns))
  world-env)

(interaction-environment world-env)
