;;; strip.ss — a library's own forms, with the meaning they have at the
;;; top level, for a library's body stripped to the top level. The hacker
;;; edition uses them when it splices every library into one environment
;;; (src/hacker.ss), and a test when it strips a library into an
;;; environment of its own (test-library, tests/reach.ss). This file is
;;; loaded after src/base.ss: base.ss's define-hook stays, and the
;;; define-state here replaces base.ss's.
;;;
;;; A state is a variable that keeps its value when its file loads again
;;; (as a defvar does); a made value and a hook are plain definitions; a
;;; view and a checked setter expand to nothing (the name is already the
;;; thing); at-load runs its forms, and at-load-once runs them the first
;;; time only; and a layer's declaration checks nothing, since holding a
;;; library to its layer is the library edition's job. Each form is a
;;; definition where the library's form is one, so that a name the library
;;; uses before it defines it is one name at the top level too.

(define-syntax define-state
  (syntax-rules ()
    [(_ name init)
     (define name (if (top-level-bound? 'name) (top-level-value 'name) init))]))
(define-syntax define-made
  (syntax-rules () [(_ name init) (define name init)]))
(define-syntax define-view (syntax-rules () [(_ . x) (begin)]))
(define-syntax define-settable (syntax-rules () [(_ . x) (begin)]))
(define-syntax library-layer (syntax-rules () [(_ . x) (begin)]))
(define-syntax at-load (syntax-rules () [(_ form ...) (begin form ...)]))
;; Once in the world: its flag is a global of Chez's own, under a symbol
;; fixed by the forms, which a file loaded again finds set.
(define-syntax at-load-once
  (lambda (x)
    (syntax-case x ()
      [(k form ...)
       (with-syntax ([g (datum->syntax
                         #'k
                         (gensym "once"
                                 (format "schevana-once ~x"
                                         (equal-hash (syntax->datum x)))))])
         #'(unless (($primitive $top-level-bound?) 'g)
             (($primitive $set-top-level-value!) 'g #t)
             form ...))])))
(define-syntax set-hook!
  (syntax-rules ()
    [(_ (name . formals) body ...) (set! name (lambda formals body ...))]))
