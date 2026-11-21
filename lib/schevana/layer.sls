;;; (schevana layer) — the forms a layer's library is written with. A layer
;;; is the files of src/ it always was, included in a library's body, and
;;; these stand where the top level's stood (src/base.ss): defvar, whose
;;; state another library reads and never sets; define-exports, which makes
;;; a layer's export.ss the library's exports; and live-name.

(library (schevana layer)
  (export defvar define-exports assigned-variables live-name
          include-sources tree-root
          state-settable state-read-only state-checked state-through
          state-cell state-reader
          ;; the top level's own (src/base.ss), which a file still names
          forwarder-to forwarder-settable exports-install! exports-names)
  (import (chezscheme) (only (schevana base) library-layer))

  (library-layer foundation)

  ;; Where the tree is, from where a form of it was read: its file is
  ;; under <root>/lib.
  (meta define (form-root x)
    (let* ([a (syntax->annotation x)]
           [path (and a (source-file-descriptor-path
                         (source-object-sfd (annotation-source a))))]
           [up (lambda (p)
                 (let ([d (path-parent p)]) (if (string=? d "") "." d)))]
           [root (if path
                     (let loop ([p (up path)])
                       (cond [(string=? (path-last p) "lib") (up p)]
                             [(member p '("." "/")) "."]
                             [else (loop (up p))]))
                     ".")])
      (if (path-absolute? root)
          root
          (string-append (current-directory) "/" root))))

  ;; (include-sources "src/base.ss" ...): the tree's files, by their names
  ;; from its root, where the form is.
  (define-syntax include-sources
    (lambda (x)
      (syntax-case x ()
        [(k file ...)
         (let ([root (form-root x)])
           (with-syntax ([include (datum->syntax #'k 'include)]
                         [(path ...)
                          (map (lambda (f)
                                 (string-append root "/" (syntax->datum f)))
                               #'(file ...))])
             #'(begin (include path) ...)))])))

  ;; The tree's root, as a string.
  (define-syntax tree-root
    (lambda (x)
      (syntax-case x ()
        [(k) (datum->syntax #'k (form-root x))])))

  ;; A library exports no variable it assigns, not even through a macro.
  ;; So a defvar's value is a global of Chez's, under a symbol nobody can
  ;; type, as (schevana base)'s define-state has it, and its name a macro
  ;; that reads the global, or sets it. state-cell is the property by
  ;; which define-exports knows such a name: the symbol.
  (define state-cell)

  (define (state-settable cell)
    (make-variable-transformer
     (lambda (x)
       (syntax-case x (set!)
         [(set! _ v) #`(($primitive $set-top-level-value!) '#,cell v)]
         [id (identifier? #'id) #`(($primitive $top-level-value) '#,cell)]
         [(_ . rest) #`((($primitive $top-level-value) '#,cell) . rest)]))))

  ;; What another library has of it: a set! is refused as it expands, in
  ;; the words Chez uses for an import's.
  (define (state-read-only cell)
    (make-variable-transformer
     (lambda (x)
       (syntax-case x (set!)
         [(set! name . _)
          (syntax-error #'name "attempt to assign read-only variable")]
         [id (identifier? #'id) #`(($primitive $top-level-value) '#,cell)]
         [(_ . rest) #`((($primitive $top-level-value) '#,cell) . rest)]))))

  ;; A hook: another library sets it, if (check value).
  (define (state-checked cell check)
    (make-variable-transformer
     (lambda (x)
       (syntax-case x (set!)
         [(set! name v)
          #`(($primitive $set-top-level-value!)
             '#,cell
             (let ([value v])
               (if (#,check value)
                   value
                   (errorf 'set! "~s may not be ~s" 'name value))))]
         [id (identifier? #'id) #`(($primitive $top-level-value) '#,cell)]
         [(_ . rest) #`((($primitive $top-level-value) '#,cell) . rest)]))))

  ;; A variable of the layer's that is a plain define, and assigned: read
  ;; by another library through a procedure, reader.
  (define state-reader)

  (define (state-through reader)
    (make-variable-transformer
     (lambda (x)
       (syntax-case x (set!)
         [(set! name . _)
          (syntax-error #'name "attempt to assign read-only variable")]
         [id (identifier? #'id) #`(#,reader)]
         [(_ . rest) #`((#,reader) . rest)]))))

  ;; (assigned-variables name ...), before the layer's export.ss: these of
  ;; its plain defines are assigned, and exported all the same.
  (define-syntax assigned-variables
    (lambda (x)
      (syntax-case x ()
        [(_ name ...)
         (with-syntax ([(reader ...) (generate-temporaries #'(name ...))])
           #'(begin
               (begin
                 (define (reader) name)
                 (define-property name state-reader #'reader))
               ...))])))

  (define-syntax defvar
    (lambda (x)
      (syntax-case x ()
        [(_ name init)
         (with-syntax ([g (datum->syntax #'name (gensym "state"))])
           #'(begin
               (define state-made
                 (($primitive $set-top-level-value!) 'g init))
               (define-syntax name (state-settable #'g))
               (define-property name state-cell #'g)))])))

  ;; (define-exports name (export (destination ...) entry ...) ...), as
  ;; src/base.ss has it: the library exports every entry, to whoever
  ;; imports it. A state's name is exported read-only; (settable name
  ;; check), a hook, set if (check value). name is the list the top
  ;; level's would be, a settable entry's check #t.
  (define-syntax define-exports
    (lambda (x)
      (lambda (lookup)
        (define (entry-name entry)
          (syntax-case entry (settable)
            [(settable name . _) #'name]
            [name #'name]))
        (define (entry-settable? entry)
          (syntax-case entry (settable)
            [(settable . _) #t]
            [_ #f]))
        (define (face entry)
          (with-syntax ([(face) (generate-temporaries '(face))])
            (syntax-case entry (settable)
              ;; a face another library may set keeps the property, so
              ;; that a library above gives it on read-only, or checked
              [(settable name)
               (let ([cell (lookup #'name #'state-cell)])
                 (if cell
                     (with-syntax ([cell cell])
                       #'((define-syntax face (state-settable #'cell))
                          (define-property face state-cell #'cell)
                          (export (rename (face name)))))
                     ;; no defvar's: a hook's (define-hook), set as it is
                     #'((export name))))]
              [(settable name check)
               (let ([cell (lookup #'name #'state-cell)])
                 (if cell
                     (with-syntax ([cell cell])
                       #'((define-syntax face (state-checked #'cell #'check))
                          (export (rename (face name)))))
                     #'((export name))))]
              [name
               (let ([cell (lookup #'name #'state-cell)]
                     [reader (lookup #'name #'state-reader)])
                 (cond
                   [cell
                    (with-syntax ([cell cell])
                      #'((define-syntax face (state-read-only #'cell))
                         (export (rename (face name)))))]
                   [reader
                    (with-syntax ([reader reader])
                      #'((define-syntax face (state-through #'reader))
                         (export (rename (face name)))))]
                   [else #'((export name))]))])))
        (syntax-case x (export)
          [(_ list-name (export (destination ...) entry ...) ...)
           (with-syntax ([((form ...) ...) (map face #'(entry ... ...))]
                         [((pair ...) ...)
                          (map (lambda (entries)
                                 (map (lambda (e)
                                        (cons (entry-name e)
                                              (entry-settable? e)))
                                      entries))
                               #'((entry ...) ...))])
             #'(begin
                 (define list-name '(((destination ...) pair ...) ...))
                 form ... ...))]))))

  ;; In a library a procedure is handed over itself: nothing redefines
  ;; it, and no name reaches it.
  (define-syntax live-name
    (syntax-rules () [(_ name) name]))

  ;; What src/base.ss has that works in a library as it is. The rest of
  ;; it (its defvar, its define-exports, its live-name) stays inside.
  (module (forwarder-to forwarder-settable exports-install! exports-names)
    (include-sources "src/base.ss")))
