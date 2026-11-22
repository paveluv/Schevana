;;; hacker.ss — the hacker edition: every library loaded from a file,
;;; Schevana's and anyone's, spliced into this one top-level environment,
;;; its internals with it, each name there to see and to redefine, as in a
;;; world of top-level files; a redefinition takes at the next call, the
;;; core's own calls too. src/launch.ss loads it for --hacker, after
;;; src/base.ss and before any of the tree's libraries. From source only:
;;; nothing is compiled to a file.
;;;
;;; The libraries' own forms take their top-level sense here: a state is a
;;; variable kept as its file loads again (a defvar), a made value and a hook
;;; are definitions, a view and a checked setter are nothing (the name is
;;; already the thing), and a layer's declaration checks nothing: what holds
;;; a library to its layer is the library edition's.

;; Chez's library and import forms, under names of their own.
(import (prefix (only (chezscheme) library import) chez:))

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

;; The libraries here before any is spliced: Chez's, and (schevana base),
;; which src/base.ss imported. Not spliced again.
(define hacker-real-libraries (library-list))

;; This environment, and an identifier in it, from which the spliced
;; libraries' exports are forwarded to whoever imports one elsewhere.
(define hacker-environment (interaction-environment))
(define hacker-anchor (environment-anchor hacker-environment))

;; A library's name in an import spec.
(meta define (hacker-spec-library s)
  (if (and (pair? s) (memq (car s) '(only except prefix rename for)))
      (hacker-spec-library (cadr s))
      s))

;; (import spec ...) here: each library that is not Chez's loaded,
;; spliced as it loads, and no name bound, as its names are here already
;; under the names it defines them by.
(define-syntax import
  (lambda (x)
    (syntax-case x ()
      [(k spec ...)
       (with-syntax ([(lib ...)
                      (map (lambda (l) (datum->syntax #'k l))
                           (remp (lambda (l) (member l hacker-real-libraries))
                                 (map hacker-spec-library
                                      (syntax->datum #'(spec ...)))))])
         #'(begin (chez:import (only lib)) ...))])))

;; A library's body-level (export (import lib ...)), another's names
;; given as its own: here those are spliced, so it loads them.
(define-syntax export
  (syntax-rules ()
    [(_ (import lib ...)) (import lib ...)]
    [(_ . x) (begin)]))

;; Each library spliced, the first first: (name file text imports), its
;; file, the text that was spliced, for a reload to tell a change, and the
;; libraries it imports that were spliced too.
(define hacker-spliced '())

(define (hacker-splice-noted! name file imports)
  (when file
    (let ([entry (list name file (call-with-input-file file get-string-all)
                       imports)]
          [had (assoc name hacker-spliced)])
      (if had
          (set-cdr! had (cdr entry))
          (set! hacker-spliced (append hacker-spliced (list entry)))))))

;; (library name (export ...) (import spec ...) body ...): the body
;; spliced here, after each library it imports that is not Chez's,
;; spliced as it is first named (import's search loads its file here,
;; through this form again); a name it exports renamed, here under that
;; name too. Then a real library of the name, whose exports forward to
;; the names here, read-only, so that import finds it loaded, and another
;; environment that imports it has its names.
(define-syntax library
  (lambda (x)
    (define (file-of x)
      (let ([a (syntax->annotation x)])
        (and a (source-file-descriptor-path
                (source-object-sfd (annotation-source a))))))
    ;; (external . internal) syntax pairs, of the export clause's specs
    (define (export-pairs specs)
      (apply append
             (map (lambda (s)
                    (syntax-case s (rename)
                      [(rename (in out) ...)
                       (map cons #'(out ...) #'(in ...))]
                      [id (identifier? #'id) (list (cons #'id #'id))]))
                  specs)))
    (syntax-case x ()
      [(k name (ex spec ...) (im ispec ...) body ...)
       (let ([pairs (export-pairs #'(spec ...))])
         (with-syntax
           ([(lib ...)
             (map (lambda (l) (datum->syntax #'k l))
                  (remp (lambda (l) (member l hacker-real-libraries))
                        (map hacker-spec-library
                             (syntax->datum #'(ispec ...)))))]
            [((out . in) ...)
             (filter (lambda (p) (not (bound-identifier=? (car p) (cdr p))))
                     pairs)]
            [(external ...) (map car pairs)]
            [(forward ...)
             (map (lambda (p)
                    (forwarder-to (datum->syntax hacker-anchor
                                                 (syntax->datum (cdr p)))))
                  pairs)]
            [file (file-of x)])
           #'(begin
               (chez:import (only lib)) ...
               body ...
               (define-syntax out (identifier-syntax in)) ...
               (hacker-splice-noted! 'name file '(lib ...))
               (chez:library name (ex external ...) (im (chezscheme))
                 (define-syntax external (quote forward)) ...))))])))

;; Each spliced library whose file changed since, and each that imports
;; one of them, spliced again, in the order they were first: their names
;; redefined here, which every caller reaches at its next call, and what
;; sets a hook set again; a macro's users keep what they expanded to. held:
;; libraries that stay as they are, with all they import, as in the
;; library edition (reload-libraries!). => the names of those spliced
;; again, kept as the library edition's reload keeps them.
(define (hacker-reload-libraries! held)
  (let* ([imports (lambda (name)
                    (let ([e (assoc name hacker-spliced)])
                      (if e (cadddr e) '())))]
         [held (let loop ([todo held] [seen '()])
                 (cond [(null? todo) seen]
                       [(member (car todo) seen) (loop (cdr todo) seen)]
                       [else (loop (append (imports (car todo)) (cdr todo))
                                   (cons (car todo) seen))]))]
         [candidates (remp (lambda (e) (member (car e) held)) hacker-spliced)]
         [changed (map car
                       (filter (lambda (e)
                                 (and (file-exists? (cadr e))
                                      (not (string=? (caddr e)
                                                     (call-with-input-file
                                                       (cadr e)
                                                       get-string-all)))))
                               candidates))]
         [set (let grow ([set changed])
                (let ([more (filter (lambda (e)
                                      (and (not (member (car e) set))
                                           (exists (lambda (i) (member i set))
                                                   (cadddr e))))
                                    candidates)])
                  (if (null? more) set (grow (append set (map car more))))))]
         [order (map car (filter (lambda (e) (member (car e) set))
                                 candidates))])
    (parameterize ([interaction-environment hacker-environment])
      (for-each (lambda (name) (load (cadr (assoc name hacker-spliced))))
                order))
    (when (top-level-bound? '*reload-last* hacker-environment)
      (set-top-level-value! '*reload-last* order hacker-environment))
    order))
