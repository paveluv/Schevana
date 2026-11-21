;;; base.ss — what every environment of the top level has: the basics,
;;; which are a library's ((schevana base)), and the means by which a layer
;;; gives the next its names. Pure: it keeps no state and calls no C, so
;;; each environment loads a copy of its own, and any copy is as good as
;;; another (tests/sources.ss).

(import (schevana base))

;; State variables that must survive (reload!) are declared with defvar,
;; like in Emacs: the initial value is only used if the name is unbound.
(define-syntax defvar
  (syntax-rules ()
    [(_ name init)
     (define name (if (top-level-bound? 'name) (top-level-value 'name) init))]))

;; A procedure handed over by its name, so that a redefinition takes at
;; the next call (world-value). In a library, where nothing is redefined
;; and a name is no way to reach it, the procedure itself
;; (lib/schevana/layer.sls).
(define-syntax live-name
  (syntax-rules () [(_ name) 'name]))

;; A read-only forwarder to the identifier id's binding: a macro that,
;; installed in another environment, makes code there refer to that
;; binding itself (live, and at no cost a call). A set! of it is refused
;; as it expands, in the words Chez uses for an R6RS import's.
(define (forwarder-to id)
  (make-variable-transformer
   (lambda (x)
     (syntax-case x (set!)
       [(set! name . _)
        (syntax-error #'name "attempt to assign read-only variable")]
       [_ (identifier? x) id]
       [(_ . rest) #`(#,id . rest)]))))

;; The same, but a set!, and so a fluid-let, sets the binding, if (check
;; value); check #t lets any value by.
(define (forwarder-settable id check)
  (make-variable-transformer
   (lambda (x)
     (syntax-case x (set!)
       [(set! name v)
        (if (procedure? check)
            #`(set! #,id (let ([value v])
                           (if ((quote #,check) value)
                               value
                               (errorf 'set! "~s may not be ~s" 'name
                                       value))))
            #`(set! #,id v))]
       [_ (identifier? x) id]
       [(_ . rest) #`(#,id . rest)]))))

;; An identifier at environment's top level: a forwarder made from it names
;; that environment's binding. A macro there, under a name no code can type,
;; hands back the identifier it is used with, so it needs nothing of the
;; environment's own, not even syntax.
(define (environment-anchor environment)
  (let ([grab (gensym "anchor")] [got #f])
    (define-top-level-syntax grab
      (lambda (x)
        (syntax-case x () [(_ id) (begin (set! got #'id) #''anchor)]))
      environment)
    (eval (list grab 'anchor) environment)
    got))

;;; ---- exports
;;; Each layer below the world says in its export.ss what it gives the
;;; environments it makes, and nothing else gets there:
;;;
;;;   (define-exports name (export (destination ...) entry ...) ...)
;;;
;;; each entry a name, read-only there; or (settable name), whose set! and
;;; fluid-let reach the layer's own variable; or (settable name check), the
;;; same if (check value). The destinations are the chain's environments:
;;; the recorder's and core1's, which core0 makes, and the world's, "/",
;;; which core1 makes (main.ss).

(define-syntax define-exports
  (lambda (x)
    (define (destination? d) (memq (syntax->datum d) '(recorder core1 world)))
    (syntax-case x (export)
      [(_ name (export (destination ...) entry ...) ...)
       (for-all destination? #'(destination ... ...))
       #'(define name
           (list (cons '(destination ...) (list (export-entry entry) ...))
                 ...))])))

(define-syntax export-entry
  (lambda (x)
    (syntax-case x (settable)
      [(_ (settable name)) (identifier? #'name) #''(name . #t)]
      [(_ (settable name check)) (identifier? #'name) #'(cons 'name check)]
      [(_ name) (identifier? #'name) #''(name . #f)])))

;; Gives target what exports has for destination, each name a forwarder to
;; source's binding as its entry says. A name source doesn't have is
;; refused, so a slip in an export.ss stops the boot; a name target
;; defined itself stays its own.
(define (exports-install! exports source destination target)
  (let ([anchor (environment-anchor source)] [has (make-eq-hashtable)])
    ;; what source has, as syntax too: top-level-syntax? says so of any
    ;; name an environment doesn't have
    (for-each (lambda (s) (hashtable-set! has s #t))
              (environment-symbols source))
    (for-each
     (lambda (clause)
       (when (memq destination (car clause))
         (for-each
          (lambda (entry)
            (let ([name (car entry)] [check (cdr entry)])
              (unless (hashtable-ref has name #f)
                (errorf 'exports-install! "~s is not there to export" name))
              (unless (top-level-bound? name target)
                (define-top-level-syntax name
                  (let ([id (datum->syntax anchor name)])
                    (if check
                        (forwarder-settable id check)
                        (forwarder-to id)))
                  target))))
          (cdr clause))))
     exports)))

;; The names exports gives destination.
(define (exports-names exports destination)
  (apply append
         (map (lambda (clause)
                (if (memq destination (car clause))
                    (map car (cdr clause))
                    '()))
              exports)))
