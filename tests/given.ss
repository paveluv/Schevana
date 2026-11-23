;;; tests/given.ss — how the tests take what a library keeps to itself:
;;; the tests' build gives each name a library defines as test:name
;;; (tests/build.ss), and reach-given! defines it under its plain name, as
;;; a forwarder that a set! and a fluid-let go through. tests/reach.ss
;;; loads it, and so does a topic of a library by itself (tests/units.ss).

;; Returns a forwarder to id's binding that a set! goes through, and so
;; does a fluid-let's.
(define (reach-forwarder id)
  (make-variable-transformer
   (lambda (x)
     (syntax-case x (set!)
       [(set! _ v) #`(set! #,id v)]
       [_ (identifier? x) id]
       [(_ . rest) #`(#,id . rest)]))))

;; Whether n is a name the tests' build gives (tests/build.ss): test:name.
(define (reach-given? n)
  (let ([s (symbol->string n)])
    (and (> (string-length s) 5) (string=? (substring s 0 5) "test:"))))

;; Defines in env, under its plain name, each name that the build gives
;; (test:name) of the libraries imported into env, unless env has that
;; name already: these are what a library keeps to itself.
(define (reach-given! env)
  (let ([anchor (environment-anchor env)] [had (make-eq-hashtable)]
        [names (environment-symbols env)])
    (for-each (lambda (n) (hashtable-set! had n #t)) names)
    (for-each
     (lambda (n)
       (when (reach-given? n)
         (let* ([s (symbol->string n)]
                [bare (string->symbol (substring s 5 (string-length s)))])
           (unless (hashtable-ref had bare #f)
             (hashtable-set! had bare #t)
             (define-top-level-syntax bare
               (reach-forwarder (datum->syntax anchor n))
               env)))))
     names)))
