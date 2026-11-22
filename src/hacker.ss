;;; hacker.ss — the hacker edition. Every library loaded from a file,
;;; Schevana's or anyone's, is spliced into this one top-level environment
;;; with its internals, so that each of its names can be seen and
;;; redefined there, as in a world of top-level files. A redefinition takes
;;; effect at the next call, in the core's own calls too. src/launch.ss
;;; loads this file for --hacker, after src/base.ss and src/strip.ss and
;;; before any of the tree's libraries. Everything loads from source:
;;; nothing is compiled to a file.
;;;
;;; The libraries' own forms have their top-level meaning here, as
;;; src/strip.ss, loaded before this file, defines them.

;; Chez's library and import forms, renamed so this file can redefine
;; library and import.
(import (prefix (only (chezscheme) library import) chez:))

;; The libraries loaded before any is spliced: Chez's, and (schevana
;; base), which src/base.ss imported. These are never spliced.
(define hacker-real-libraries (library-list))

;; This environment, and an identifier in it, from which the spliced
;; libraries' exports are forwarded to any other environment that imports
;; one of them.
(define hacker-environment (interaction-environment))
(define hacker-anchor (environment-anchor hacker-environment))

;; Returns the library's name in an import spec.
(meta define (hacker-spec-library s)
  (if (and (pair? s) (memq (car s) '(only except prefix rename for)))
      (hacker-spec-library (cadr s))
      s))

;; Here (import spec ...) loads each library that isn't one of
;; hacker-real-libraries, which splices it as it loads, and binds no name:
;; the library's names are here already, under the names it defines.
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

;; A library's body may hold (export (import lib ...)), which exports the
;; names of other libraries as its own. Here those libraries are spliced
;; too, so the form just loads them.
(define-syntax export
  (syntax-rules ()
    [(_ (import lib ...)) (import lib ...)]
    [(_ . x) (begin)]))

;; The libraries spliced so far, in the order they were first spliced,
;; each as (name file text imports): its file, the text that was spliced
;; (so that a reload can tell a change), and the libraries it imports that
;; were spliced too.
(define hacker-spliced '())

(define (hacker-splice-noted! name file imports)
  (when file
    (let ([entry (list name file (call-with-input-file file get-string-all)
                       imports)]
          [had (assoc name hacker-spliced)])
      (if had
          (set-cdr! had (cdr entry))
          (set! hacker-spliced (append hacker-spliced (list entry)))))))

;; Here (library name (export ...) (import spec ...) body ...) splices
;; the body into this environment, after each library it imports that
;; isn't one of hacker-real-libraries. Each of those is spliced when it is
;; first named (import's search loads its file here, through this form
;; again). A name the library exports under another name (rename) is
;; defined here under that name too. Then a real library of the same name
;; is defined, whose exports forward, read-only, to the names here, so
;; that import finds it loaded and another environment that imports it
;; gets its names.
(define-syntax library
  (lambda (x)
    (define (file-of x)
      (let ([a (syntax->annotation x)])
        (and a (source-file-descriptor-path
                (source-object-sfd (annotation-source a))))))
    ;; The (external . internal) pairs of identifiers that the export
    ;; clause's specs name.
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

;; Splices again each spliced library whose file has changed since it was
;; spliced (and each library in forced, as if its file had changed), and
;; each library that imports one of them, in the order they were first
;; spliced. Their names are redefined here, which every caller reaches at
;; its next call, and the code that sets a hook sets it again; code that
;; used a macro keeps what the macro expanded to. held names libraries
;; that stay as they are, with everything they import, as in the library
;; edition (reload-libraries!). Returns the names of the libraries spliced
;; again, and keeps them in *reload-last* as the library edition's reload
;; does.
(define (hacker-reload-libraries! held . forced)
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
                                 (or (member (car e) forced)
                                     (and (file-exists? (cadr e))
                                          (not (string=? (caddr e)
                                                         (call-with-input-file
                                                           (cadr e)
                                                           get-string-all))))))
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
