;;; base.ss — what every environment of the top level has: the basics,
;;; which are a library's ((schevana base)), forwarders with them, by
;;; which an environment gives another its names, and the top level's own
;;; forms. Pure: it keeps no state and calls no C, so
;;; each environment loads a copy of its own, and any copy is as good as
;;; another (tests/sources.ss).

;; define-hook and define-state are the top level's own, below.
(import (except (schevana base) define-hook define-state))

;; State variables that must survive (reload!) are declared with defvar,
;; like in Emacs: the initial value is only used if the name is unbound.
(define-syntax defvar
  (syntax-rules ()
    [(_ name init)
     (define name (if (top-level-bound? 'name) (top-level-value 'name) init))]))

;; (define-hook (name . formals) body ...): a procedure that may be
;; replaced, which a library keeps in a box ((schevana base)). At the top
;; level every procedure may be, so here it is a definition like any
;; other, and set-hook! sets it.
(define-syntax define-hook
  (syntax-rules ()
    [(_ (name . formals) body ...) (define (name . formals) body ...)]
    [(_ name procedure) (define name procedure)]))

;; (define-state name init): a variable a library may export and another
;; set, kept there in a box too. Here it is a definition, made again at a
;; reload; what must outlive one is a defvar.
(define-syntax define-state
  (syntax-rules () [(_ name init) (define name init)]))

;; A procedure handed over by its name, so that a redefinition takes at
;; the next call (world-value). In a library, where nothing is redefined
;; and a name is no way to reach it, the procedure itself
;; (lib/schevana/layer.sls).
(define-syntax live-name
  (syntax-rules () [(_ name) 'name]))

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
