;;; (schevana base) — the basics, which every piece of Schevana has:
;;; numbers, strings, lists and property lists, and which platform this
;;; is. Pure: it keeps no state and calls no C.

(library (schevana base)
  (export
    at-load define-state define-view define-made define-hook set-hook!
    clamp string-split string-join string-prefix? string-suffix? filter-map
    string-contains-ci? plist-ref plist-keys condition->string list-index
    registry-add
    ;; which OS and CPU this is
    platform-os platform-linux? platform-mac? platform-windows? platform-cpu
    platform-x86-64? platform-arm64?)
  (import (chezscheme))

  ;; Expressions among definitions, as a definition of a name nobody can
  ;; type: a library's body takes no definition after an expression.
  (define-syntax at-load
    (syntax-rules ()
      [(_ form ...) (define at-load-done (begin form ...))]))

  ;; (define-global name g init kept?): a global of Chez's own under the
  ;; symbol g, and name a macro that reads it, or sets it under set! (and
  ;; so under fluid-let). A global, not a box: Chez reads it from the
  ;; symbol itself, one load, where a box would be a variable of the
  ;; library that every closure reading it must hold, so that a thunk which
  ;; only calls such a procedure is allocated each time it is made.
  ;; $top-level-value and $set-top-level-value! are Chez's internals, the
  ;; two its expander writes for every variable of the top level. kept?: a
  ;; value already there stays as the library is evaluated again (a
  ;; reload). Each use names global-made too, a variable of the library's,
  ;; where it is never reached: Chez runs a library only for code that
  ;; names a variable of it, and code that used only its globals would
  ;; find them unbound. The optimizer drops the branch.
  (define-syntax define-global
    (lambda (x)
      (syntax-case x ()
        [(_ name g init kept?)
         (with-syntax ([get #'($primitive $top-level-value)]
                       [put #'($primitive $set-top-level-value!)]
                       [bound? #'($primitive $top-level-bound?)])
           #'(begin
               (define global-made
                 (unless (and kept? (bound? 'g)) (put 'g init)))
               (define-syntax name
                 (make-variable-transformer
                  (lambda (x)
                    (syntax-case x (set!)
                      [(set! _ v) #'(if #f global-made (put 'g v))]
                      [id (identifier? #'id) #'(if #f global-made (get 'g))]
                      [(_ . rest)
                       #'(if #f global-made ((get 'g) . rest))]))))))])))

  ;; The symbol a state is kept under: fixed by the file it is defined in
  ;; and its name, so that the library evaluated again finds it; a fresh
  ;; one where the expander knows no file. Its pretty name says nothing of
  ;; what it holds.
  (meta define (state-symbol id)
    (let* ([a (syntax->annotation id)]
           [s (and a (annotation-source a))])
      (if s
          (gensym "state"
                  (format "schevana-state ~a ~a"
                          (source-file-descriptor-path (source-object-sfd s))
                          (syntax->datum id)))
          (gensym "state"))))

  ;; (define-state name init): a variable a library may export, to be read
  ;; and set by those that import it, kept as the library is evaluated
  ;; again (reload-libraries!) as a defvar is. Chez exports no variable
  ;; that is assigned, so the value is a global (define-global). name is
  ;; the definer's own, never one a macro makes up: two states a macro
  ;; made in one file would share the symbol.
  (define-syntax define-state
    (lambda (x)
      (syntax-case x ()
        [(_ name init)
         (with-syntax ([g (datum->syntax #'name (state-symbol #'name))])
           #'(define-global name g init #t))])))

  ;; (define-view name state): state under another name, to read and never
  ;; to set: what a library gives on of a state it imports. A set! of it
  ;; is refused as it expands, in the words Chez uses for an import's.
  (define-syntax define-view
    (syntax-rules ()
      [(_ name state)
       (define-syntax name
         (make-variable-transformer
          (lambda (x)
            (syntax-case x (set!)
              [(set! n . _)
               (syntax-error #'n "attempt to assign read-only variable")]
              [id (identifier? #'id) #'state]
              [(_ . rest) #'(state . rest)]))))]))

  ;; (define-made name init): a value made as the library loads, read and
  ;; never set: a buffer, a table, a foreign procedure, a fact found out. A
  ;; global under a view, not a definition: a library's own variable is
  ;; held by every procedure that reads it, and by every procedure that
  ;; calls one of those, so that a closure made at run time which only
  ;; calls one carries it, and is allocated where the top level's was not.
  ;; With none, a library's procedures carry nothing
  ;; (tests/units/allocation.ss). Made again as the library is evaluated
  ;; again; a value a state may hold is a state itself, so the two stay
  ;; one.
  (define-syntax define-made
    (lambda (x)
      (syntax-case x ()
        [(_ name init)
         (with-syntax ([g (datum->syntax #'name (gensym "made"))])
           #'(begin (define-global made g init #f)
                    (define-view name made)))])))

  ;; (define-hook (name . formals) body ...), or (define-hook name
  ;; procedure): a procedure that may be replaced, under its own name. The
  ;; piece that has what it does sets it (set-hook!), where the one that
  ;; calls it sits below; a test puts its own there for a while. Called by
  ;; its name, set by set!, as a state is; made again as the library is
  ;; evaluated again, and set again by the piece that sets it, which
  ;; imports it and so is evaluated again after it.
  (define-syntax define-hook
    (lambda (x)
      (syntax-case x ()
        [(k (name . formals) body ...)
         #'(k name (lambda formals body ...))]
        [(_ name procedure)
         (with-syntax ([g (datum->syntax #'name (gensym "hook"))])
           #'(define-global name g procedure #f))])))

  ;; (set-hook! (name . formals) body ...): what the hook name does, from
  ;; here on. A definition, so it stands among a library's.
  (define-syntax set-hook!
    (syntax-rules ()
      [(_ (name . formals) body ...)
       (at-load (set! name (lambda formals body ...)))]))

  (define (clamp x lo hi) (max lo (min hi x)))

  (define (string-split str ch)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length str)) (reverse (cons (substring str start i) acc))]
        [(char=? (string-ref str i) ch)
         (loop (+ i 1) (+ i 1) (cons (substring str start i) acc))]
        [else (loop (+ i 1) start acc)])))

  (define (string-join strs sep)
    (if (null? strs)
        ""
        (apply string-append (car strs)
               (map (lambda (s) (string-append sep s)) (cdr strs)))))

  (define (string-prefix? prefix str)
    (and (<= (string-length prefix) (string-length str))
         (string=? prefix (substring str 0 (string-length prefix)))))

  (define (string-suffix? suffix str)
    (let ([n (string-length str)] [m (string-length suffix)])
      (and (<= m n) (string=? suffix (substring str (- n m) n)))))

  ;; map, keeping only the true results.
  (define (filter-map f l)
    (fold-right (lambda (x acc) (let ([y (f x)]) (if y (cons y acc) acc)))
                '()
                l))

  ;; Compared in place, a character at a time: a long str costs no copies.
  (define (string-contains-ci? str sub)
    (let ([n (string-length str)] [m (string-length sub)])
      (define (at? i j)   ; sub from j on is in str at i + j
        (or (= j m)
            (and (char-ci=? (string-ref str (+ i j)) (string-ref sub j))
                 (at? i (+ j 1)))))
      (let loop ([i 0]) (and (<= (+ i m) n) (or (at? i 0) (loop (+ i 1)))))))

  ;; Property lists: '(key val key val ...)
  (define (plist-ref plist key default)
    (cond
      [(or (null? plist) (null? (cdr plist))) default]
      [(eq? (car plist) key) (cadr plist)]
      [else (plist-ref (cddr plist) key default)]))

  (define (plist-keys plist)
    (if (or (null? plist) (null? (cdr plist)))
        '()
        (cons (car plist) (plist-keys (cddr plist)))))

  (define (condition->string c)
    (call-with-string-output-port
     (lambda (p)
       (if (condition? c)
           (display-condition c p)
           (fprintf p "non-condition raised: ~s" c)))))

  (define (list-index pred lst)
    (let loop ([l lst] [i 0])
      (cond [(null? l) #f] [(pred (car l)) i] [else (loop (cdr l) (+ i 1))])))

  ;; A registry (apps, styles, palettes, wallpapers) is a list in
  ;; first-registration order. An entry whose name is already there replaces
  ;; that entry in place. name-of gives an entry's name.
  (define (registry-add entries entry name-of)
    (let ([name (name-of entry)])
      (if (exists (lambda (e) (eq? (name-of e) name)) entries)
          (map (lambda (e) (if (eq? (name-of e) name) entry e)) entries)
          (append entries (list entry)))))

  ;;; ---- what the platform is
  ;;; Which OS and CPU this is, as Chez was built for them: known before
  ;;; anything loads, so here, where every environment has them. What is
  ;;; known only once SDL and the GPU start (the windowing system, the GPU's
  ;;; API) core0 says in *core0-platform* ((schevana core0 platform)), and the
  ;;; world asks src/core1/platform.ss. These say what the platform is;
  ;;; whether it can do a thing is asked of the thing.

  ;; 'linux, 'macos, 'windows, or 'other.
  (define (platform-os)
    (let ([m (symbol->string (machine-type))])
      (cond [(string-contains-ci? m "osx") 'macos]
            [(string-contains-ci? m "le") 'linux]
            [(string-contains-ci? m "nt") 'windows]
            [else 'other])))
  (define (platform-linux?) (eq? (platform-os) 'linux))
  (define (platform-mac?) (eq? (platform-os) 'macos))
  (define (platform-windows?) (eq? (platform-os) 'windows))

  ;; 'x86-64, 'arm64, or 'other.
  (define (platform-cpu)
    (let ([m (symbol->string (machine-type))])
      (cond [(string-contains-ci? m "a6") 'x86-64]
            [(string-contains-ci? m "arm64") 'arm64]
            [else 'other])))
  (define (platform-x86-64?) (eq? (platform-cpu) 'x86-64))
  (define (platform-arm64?) (eq? (platform-cpu) 'arm64)))
