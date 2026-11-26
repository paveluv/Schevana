;;; (schevana core theme-table) — the settings in effect: the one table that
;;; (theme key) reads, where drawing finds a color or a font by its key. The
;;; theme ((schevana core theme)), which sits above drawing, fills it from
;;; the layers of a look (styles, palettes, the built-in defaults). Without
;;; a look, the table holds only the defaults that pieces below the look
;;; give (theme-table-default!), and a color is given as its number.

(library (schevana core theme-table)
  (export
    *theme* *main-theme* theme-rule? theme-rule theme-unset call-with-theme
    theme theme-keys world-value theme-part plist-has? plist-remove
    *theme-table-defaults* theme-table-default!)
  (import (chezscheme)
          (only (schevana base) define-hook define-made define-state
                library-layer))

  (library-layer core)

  (define-state *theme* (make-eq-hashtable))   ; every setting in effect
  ;; The chosen style's table. *theme* is a different one while a window of
  ;; another style is drawn or its handler runs, and while a preview or a
  ;; place is drawn.
  (define-state *main-theme* *theme*)

  ;; A setting computed from others when the theme is built.
  (define-record-type (theme-rule-box make-theme-rule theme-rule?)
    (nongenerative schevana-rule-1)
    (fields thunk))
  (define-syntax theme-rule
    (syntax-rules () [(_ e) (make-theme-rule (lambda () e))]))

  (define-made theme-unset (list 'unset))

  ;; The rules that this computation is in the middle of, innermost first,
  ;; each (table . key). A fluid-let binds it, so a process switched out
  ;; inside a rule takes its own list along, and whoever reads the rule
  ;; meanwhile has a list of its own, without that rule.
  (define-state *theme-computing* '())

  ;; Returns thunk's values with t (a resolved theme) in effect while it
  ;; runs, so that a look that isn't on is read as if it were (for a preview
  ;; or a comparison).
  (define (call-with-theme t thunk)
    (fluid-let ([*theme* t]) (thunk)))

  ;; A rule still in the table is computed the first time it is read.
  (define (theme key)
    (let ([v (hashtable-ref *theme* key theme-unset)])
      (cond [(eq? v theme-unset) (errorf 'theme "unknown theme key ~s" key)]
            [(theme-rule? v) (compute-rule! *theme* key v)]
            [else v])))

  ;; The rule stays in table t until its value replaces it. So a reader
  ;; while a process is switched out inside the rule computes it too, and
  ;; one left unfinished (its process killed, its handler out of time) is
  ;; computed by the next reader. Only a rule that reads itself, in the
  ;; same computation, finds itself in the list.
  (define (compute-rule! t key r)
    (let ([this (cons t key)])
      (when (member this *theme-computing*)
        (errorf 'theme "~s is computed from itself" key))
      (let ([v (fluid-let ([*theme-computing* (cons this *theme-computing*)])
                 ((theme-rule-box-thunk r)))])
        (hashtable-set! t key v)
        v)))

  (define (theme-keys)
    (vector->list
     (vector-sort (lambda (a b)
                    (string<? (symbol->string a) (symbol->string b)))
                  (hashtable-keys *theme*))))

  ;; Returns the world's procedure of that name, looked up at each call, so
  ;; that a redefinition takes effect at the next call. (schevana core
  ;; sources) sets the hook that looks in the world; this default only
  ;; errors, since a library is handed the procedure itself.
  (define-hook (world-value name)
    (errorf 'world-value "~s: a library is handed the procedure, not its name"
            name))

  ;; Returns the procedure the theme gives for key. The setting is a
  ;; procedure, or the name of a top-level one, which is looked up at each
  ;; call so that a redefinition shows on the next frame.
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

  ;; A setting that a piece below the look reads, with its value until a
  ;; look gives one. The piece gives it as it loads, so that the table has
  ;; it even with no look at all. The look's built-in defaults start from
  ;; these ((schevana core theme)).
  (define-state *theme-table-defaults* '())   ; key value ...

  (define (theme-table-default! key value)
    (set! *theme-table-defaults*
      (cons* key value (plist-remove *theme-table-defaults* key)))
    (unless (hashtable-contains? *theme* key)
      (hashtable-set! *theme* key value))))
