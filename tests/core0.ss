;;; tests/core0.ss — how a test reaches into core0, loaded right after
;;; main.ss: the test goes on in "/", the world core0 made, where every name
;;; of core0's own is forwarded and may be set (set!, fluid-let), as the
;;; tests stand in for SDL and the screen. The world itself sees only
;;; core0's interface (core0-interface, src/core0/boot.ss), read-only. What
;;; the test defined before it loaded the tree is forwarded too, and so is
;;; core0-env, core0's environment, for what goes by name (top-level-value).

(define core0-env (interaction-environment))

;; A forwarder to id's binding that a set! goes through, as fluid-let's do.
(define (core0-forwarder id)
  (make-variable-transformer
   (lambda (x)
     (syntax-case x (set!)
       [(set! _ v) #`(set! #,id v)]
       [_ (identifier? x) id]
       [(_ . rest) #`(#,id . rest)]))))

;; Core0's names, and the interface's in place of its read-only forwarders.
(let ([world (make-eq-hashtable)])
  (for-each (lambda (n) (hashtable-set! world n #t))
            (environment-symbols *core0-world*))
  (for-each (lambda (n)
              (when (or (memq n core0-interface)
                        (not (hashtable-ref world n #f)))
                (define-top-level-syntax n
                  (core0-forwarder (datum->syntax #'core0-env n))
                  *core0-world*)))
            (environment-symbols core0-env)))

;; Core0's own clock, which times the screen's waits: the world's now-ns is
;; another, from its own copy of src/base.ss.
(define-top-level-syntax 'core0-now-ns
  (core0-forwarder (datum->syntax #'core0-env 'now-ns))
  *core0-world*)

;; The recorder's names too, sealed from the world but not from the tests
;; (poisoning, its pools, the last frame): each forwarded, and settable.
(let ([recorder (core0-recorder-environment)]
      [world (make-eq-hashtable)])
  (for-each (lambda (n) (hashtable-set! world n #t))
            (environment-symbols *core0-world*))
  (let ([anchor (core0-anchor recorder)])
    (for-each (lambda (n)
                (unless (hashtable-ref world n #f)
                  (define-top-level-syntax n
                    (core0-forwarder (datum->syntax anchor n))
                    *core0-world*)))
              (environment-symbols recorder))))

(core0-enter-world!)
