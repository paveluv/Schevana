;;; strip.ss — a library's own forms in their top-level sense, for a
;;; library's body stripped to the top level: the hacker edition's, every
;;; library spliced into one environment (src/hacker.ss), and a test's, a
;;; library stripped into one of its own (test-library, tests/reach.ss).
;;; Loaded after src/base.ss, whose define-hook and define-state are the
;;; top level's too.
;;;
;;; A state is a variable kept as its file loads again (a defvar), a made
;;; value and a hook are definitions, a view and a checked setter are
;;; nothing (the name is already the thing), and a layer's declaration
;;; checks nothing: what holds a library to its layer is the library
;;; edition's. Each is a definition where the library has one, so that a
;;; name a library uses before it defines it is one name at the top level
;;; too.

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
(define-syntax set-hook!
  (syntax-rules ()
    [(_ (name . formals) body ...) (set! name (lambda formals body ...))]))
