;;; tests/core0.ss — how a test reaches into core0, loaded right after
;;; load.ss: the test goes on in "/", the world core0 made, where every name
;;; of core0's own is forwarded and may be set (set!, fluid-let), as the
;;; tests stand in for SDL and the screen. The world itself sees only
;;; core0's interface (host-interface, src/host/boot.ss), read-only. What
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
            (environment-symbols *host-world*))
  (for-each (lambda (n)
              (when (or (memq n host-interface)
                        (not (hashtable-ref world n #f)))
                (define-top-level-syntax n
                  (core0-forwarder (datum->syntax #'core0-env n))
                  *host-world*)))
            (environment-symbols core0-env)))

;; Core0's own clock, which times the screen's waits: the world's now-ns is
;; another, from its own copy of src/base.ss.
(define-top-level-syntax 'core0-now-ns
  (core0-forwarder (datum->syntax #'core0-env 'now-ns))
  *host-world*)

(host-enter-world!)
