;;; (schevana core theme-table) — the settings in effect: the one table (theme
;;; key) reads, where drawing finds a color or a font by its key. What fills
;;; it, the layers of a look (styles, palettes, the built-in defaults), is the
;;; theme's, above drawing ((schevana core theme)); with none, the table is
;;; empty, and a color is its number.

(library (schevana core theme-table)
  (export
    *theme* *main-theme* theme-rule? theme-rule theme-unset call-with-theme
    theme theme-keys world-value theme-part plist-has? plist-remove
    *theme-table-defaults* theme-table-default! *pacer-trial* pacer-knob)
  (import (chezscheme)
          (schevana base))

  (library-layer core)

  (define-state *theme* (make-eq-hashtable))   ; every setting in effect
  ;; the chosen style's: *theme* is another while a window of another style,
  ;; a preview or a place is drawn, or a window's handler runs
  (define-state *main-theme* *theme*)

  ;; A setting computed from others when the theme is built.
  (define-record-type (theme-rule-box make-theme-rule theme-rule?)
    (nongenerative schevana-rule-1)
    (fields thunk))
  (define-syntax theme-rule
    (syntax-rules () [(_ e) (make-theme-rule (lambda () e))]))

  (define-made theme-unset (list 'unset))
  (define-state theme-busy (list 'busy))   ; *theme* holds it, a while

  ;; thunk's values with t (a resolved theme) in effect meanwhile: a look
  ;; that isn't on, read as if it were (a preview, a comparison).
  (define (call-with-theme t thunk)
    (fluid-let ([*theme* t]) (thunk)))

  ;; A rule still in the table is computed the first time it is read.
  (define (theme key)
    (let ([v (hashtable-ref *theme* key theme-unset)])
      (cond [(eq? v theme-unset) (errorf 'theme "unknown theme key ~s" key)]
            [(theme-rule? v) (compute-rule! key v)]
            [(eq? v theme-busy)
             (errorf 'theme "~s is computed from itself" key)]
            [else v])))

  (define (compute-rule! key r)
    (hashtable-set! *theme* key theme-busy)
    (let ([v (guard (c [#t (hashtable-set! *theme* key r) (raise c)])
               ((theme-rule-box-thunk r)))])
      (hashtable-set! *theme* key v)
      v))

  (define (theme-keys)
    (vector->list
     (vector-sort (lambda (a b)
                    (string<? (symbol->string a) (symbol->string b)))
                  (hashtable-keys *theme*))))

  ;; A procedure of the world's by its name, looked up at each call, so that
  ;; a redefinition takes at the next: the world's boot says how
  ;; ((schevana core sources)); a library is handed the procedure itself.
  (define-hook (world-value name)
    (errorf 'world-value "~s: a library is handed the procedure, not its name"
            name))

  ;; The procedure the theme gives for key: a procedure, or the name of a
  ;; top-level one, looked up at each call, so a redefinition shows on the
  ;; next frame.
  (define (theme-part key)
    (let ([v (theme key)])
      (if (symbol? v) (world-value v) v)))

  (define (plist-has? p key)
    (and (pair? p) (pair? (cdr p))
         (or (eq? (car p) key) (plist-has? (cddr p) key))))

  (define (plist-remove p key)
    (cond [(or (null? p) (null? (cdr p))) '()]
          [(eq? (car p) key) (plist-remove (cddr p) key)]
          [else (cons* (car p) (cadr p) (plist-remove (cddr p) key))]))

  ;; A setting that a piece below the look reads, and what it is till a look
  ;; says: given as the piece loads, so that the table has it with no look
  ;; at all. The look's built-in defaults start from these
  ;; ((schevana core theme)).
  (define-state *theme-table-defaults* '())   ; key value ...

  (define (theme-table-default! key value)
    (set! *theme-table-defaults*
      (cons* key value (plist-remove *theme-table-defaults* key)))
    (unless (hashtable-contains? *theme* key)
      (hashtable-set! *theme* key value)))

  ;; The pacer's choices, settings a person may change live ((schevana core
  ;; theme)), unless a trial holds them: ((key . value) ...), the pacer lab's
  ;; ((schevana services pacer-lab)), which is never saved with the look.
  (define-state *pacer-trial* '())

  (define (pacer-knob key)
    (let ([t (assq key *pacer-trial*)]) (if t (cdr t) (theme key)))))
