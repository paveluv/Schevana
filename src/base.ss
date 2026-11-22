;;; base.ss — what every environment of the top level has: the basics
;;; (the library (schevana base)), the forwarders by which one environment
;;; gives another its names, and the top level's own forms. It is pure: it
;;; keeps no state and calls no C, so each environment loads its own copy,
;;; and any copy is as good as another (tests/sources.ss).

;; The top level has its own define-hook and define-state, defined below.
(import (except (schevana base) define-hook define-state))

;; State variables that must survive (reload!) are declared with defvar,
;; like in Emacs: the initial value is only used if the name is unbound.
(define-syntax defvar
  (syntax-rules ()
    [(_ name init)
     (define name (if (top-level-bound? 'name) (top-level-value 'name) init))]))

;; (define-hook (name . formals) body ...) defines a procedure that may be
;; replaced, which a library keeps in a global of Chez's ((schevana
;; base)). At the top level every procedure may be replaced, so here a
;; hook is a definition like any other, and set-hook! sets it.
(define-syntax define-hook
  (syntax-rules ()
    [(_ (name . formals) body ...) (define (name . formals) body ...)]
    [(_ name procedure) (define name procedure)]))

;; (define-state name init) defines a variable that a library may export
;; and another library set, which a library also keeps in a global. Here
;; it is a plain definition, made again at each reload; what must outlive
;; a reload is a defvar.
(define-syntax define-state
  (syntax-rules () [(_ name init) (define name init)]))

;; Returns an identifier at environment's top level: a forwarder made from
;; it names that environment's binding. It is found by a macro defined there
;; under a name no code can type, which hands back the identifier it is used
;; with, so it needs nothing from the environment, not even syntax.
(define (environment-anchor environment)
  (let ([grab (gensym "anchor")] [got #f])
    (define-top-level-syntax grab
      (lambda (x)
        (syntax-case x () [(_ id) (begin (set! got #'id) #''anchor)]))
      environment)
    (eval (list grab 'anchor) environment)
    got))
