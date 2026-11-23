;;; (schevana base) — the basics that every piece of Schevana has:
;;; numbers, strings, lists and property lists, which platform this is,
;;; and the forms that declare a library's layer, its states, views, made
;;; values and hooks. It is pure: it keeps no state and calls no C.

(library (schevana base)
  (export
    library-layer library-layer-names at-load at-load-once define-state
    define-view
    define-settable define-made
    define-hook
    set-hook!
    clamp string-split string-join string-prefix? string-suffix? filter-map
    string-contains-ci? plist-ref plist-keys condition->string list-index
    registry-add forwarder-to
    ;; which OS and CPU this is
    platform-os platform-linux? platform-mac? platform-windows? platform-cpu
    platform-x86-64? platform-arm64?)
  (import (chezscheme))

  ;; (at-load form ...) runs expressions among a library's definitions, as
  ;; the definition of a name nobody can type, since a library's body takes
  ;; no definition after an expression.
  (define-syntax at-load
    (syntax-rules ()
      [(_ form ...) (define at-load-done (begin form ...))]))

  ;;; ------------------------------------------------------------------ layers
  ;;; (library-layer layer), or (library-layer layer facade), comes first
  ;;; in a library's body and names the layer the library belongs to. As
  ;;; the library compiles, its imports are held to the layers' order: it
  ;;; may import nothing from a layer above its own, and from a sealed
  ;;; layer other than its own only the facade, the front door that layer
  ;;; declares. A library outside Schevana's (Chez's own, a demo) declares
  ;;; no layer and counts as below them all; each of Schevana's declares
  ;;; one. Programs and tests may import anything.

  ;; The layers, lowest first. A sealed layer is reached from outside only
  ;; through its facade. The looks are below the desktop, so that a program
  ;; may take a look without the desktop's surfaces and keys.
  (meta define library-layers
    '((foundation) (core0 sealed) (recorder sealed) (core sealed) (kits)
      (services) (looks) (desktop) (apps)))

  (meta define (library-layer-rank layer)
    (let loop ([ls library-layers] [i 0])
      (cond [(null? ls) #f]
            [(eq? (caar ls) layer) i]
            [else (loop (cdr ls) (+ i 1))])))

  ;; (library-layer-names) returns the layers' names, lowest first, for
  ;; code that shows a library's layer (and its rank, counted from 1).
  (define-syntax library-layer-names
    (lambda (x)
      (syntax-case x ()
        [(k) #`'#,(datum->syntax #'k (map car library-layers))])))

  (meta define (library-layer-sealed? layer)
    (let ([l (assq layer library-layers)]) (and l (memq 'sealed l) #t)))

  ;; Returns the file a library is compiled from, as Chez's library
  ;; manager finds it (library-directories, library-extensions), or #f.
  (meta define (library-layer-source name)
    (let ([path (apply string-append
                       (map (lambda (part)
                              (string-append "/" (symbol->string part)))
                            name))])
      (let loop ([dirs (library-directories)])
        (and (pair? dirs)
             (or (exists (lambda (ext)
                           (let ([f (string-append (caar dirs) path
                                                   (car ext))])
                             (and (file-regular? f) f)))
                         (library-extensions))
                 (loop (cdr dirs)))))))

  ;; Returns the library form that file holds, or #f.
  (meta define (library-layer-form file)
    (let ([form (guard (c [#t #f]) (call-with-input-file file read))])
      (and (list? form) (>= (length form) 4) (eq? (car form) 'library)
           form)))

  ;; What each library declares, by its name: (layer . facade?), or 'none.
  (meta define library-layer-known (make-hashtable equal-hash equal?))

  (meta define (library-layer-declared form)
    (let ([d (find (lambda (x) (and (pair? x) (eq? (car x) 'library-layer)
                                    (pair? (cdr x))))
                   (cddddr form))])
      (if d
          (cons (cadr d) (and (pair? (cddr d)) (eq? (caddr d) 'facade)))
          'none)))

  (meta define (library-layer-of name)
    (or (hashtable-ref library-layer-known name #f)
        (let* ([file (library-layer-source name)]
               [form (and file (library-layer-form file))]
               [layer (if form (library-layer-declared form) 'none)])
          (hashtable-set! library-layer-known name layer)
          layer)))

  ;; Returns the library an import spec names, without its version.
  (meta define (library-layer-imported spec)
    (cond
      [(and (pair? spec) (memq (car spec) '(only except prefix rename for))
            (pair? (cdr spec)) (pair? (cadr spec)))
       (library-layer-imported (cadr spec))]
      [(and (pair? spec) (eq? (car spec) 'library) (pair? (cdr spec)))
       (library-layer-imported (cadr spec))]
      [else (filter symbol? spec)]))

  ;; Returns a message for each of form's imports that breaks the layers'
  ;; order, for a library of layer.
  (meta define (library-layer-faults form layer)
    (let ([rank (library-layer-rank layer)] [name (cadr form)])
      ;; filter-map is this library's own, out of reach at expansion
      (filter
       string?
       (map
       (lambda (spec)
         (let* ([m (library-layer-imported spec)]
                [theirs (library-layer-of m)])
           (cond
             [(eq? theirs 'none)
              (and (pair? m) (eq? (car m) 'schevana)
                   (format "~s imports ~s, which declares no layer" name m))]
             [(not (library-layer-rank (car theirs)))
              (format "~s imports ~s, of no such layer ~s" name m
                      (car theirs))]
             [(> (library-layer-rank (car theirs)) rank)
              (format "~s, of layer ~s, imports ~s, of ~s, above it" name
                      layer m (car theirs))]
             [(and (not (eq? (car theirs) layer))
                   (library-layer-sealed? (car theirs))
                   (not (cdr theirs)))
              (format "~s imports ~s, a piece of the sealed layer ~s, \
                       not its facade" name m (car theirs))]
             [else #f])))
       (let ([clause (cadddr form)])
         (if (and (pair? clause) (eq? (car clause) 'import))
             (cdr clause)
             '()))))))

  (define-syntax library-layer
    (lambda (x)
      (syntax-case x ()
        [(_ layer opt ...)
         (let* ([me (syntax->datum #'layer)]
                [a (syntax->annotation x)]
                [s (and a (annotation-source a))]
                [form (and s (library-layer-form
                              (source-file-descriptor-path
                               (source-object-sfd s))))])
           (unless (library-layer-rank me)
             (syntax-error #'layer "no such layer:"))
           (when form
             (hashtable-set! library-layer-known (cadr form)
                             (cons me (memq 'facade
                                            (syntax->datum #'(opt ...)))))
             (let ([faults (library-layer-faults form me)])
               (unless (null? faults)
                 (syntax-error x (apply string-append
                                        (map (lambda (f)
                                               (string-append "\n  " f))
                                             faults))))))
           #'(define library-layer-declared 'layer))])))

  ;; This library's own layer, declared once the form is defined.
  (library-layer foundation)

  ;; (define-global name g init kept?) keeps a value in a global of Chez's
  ;; own, under the symbol g, and makes name a macro that reads it, or sets
  ;; it under set! (and so under fluid-let). It is a global rather than a
  ;; box because Chez reads a global from the symbol itself, in one load,
  ;; while a box would be a variable of the library that every closure
  ;; reading it must hold, so that a thunk which only calls such a
  ;; procedure would be allocated each time it is made. $top-level-value
  ;; and $set-top-level-value! are Chez's internals, the two its expander
  ;; emits for every variable of the top level. With kept?, a value already
  ;; there stays when the library is evaluated again (at a reload). Each
  ;; use also names global-made, a variable of the library's, in a branch
  ;; that is never taken: Chez runs a library only for code that names one
  ;; of its variables, so code that used only its globals would find them
  ;; unbound. The optimizer drops the branch.
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

  ;; Returns the symbol a state is kept under. The symbol is fixed by the
  ;; file the state is defined in and the state's name, so that the library,
  ;; evaluated again, finds it; where the expander knows no file, it is a
  ;; fresh one. Its pretty name says nothing about what it holds.
  (meta define (state-symbol id)
    (let* ([a (syntax->annotation id)]
           [s (and a (annotation-source a))])
      (if s
          (gensym "state"
                  (format "schevana-state ~a ~a"
                          (source-file-descriptor-path (source-object-sfd s))
                          (syntax->datum id)))
          (gensym "state"))))

  ;; (define-state name init) defines a variable that a library may export,
  ;; for the libraries that import it to read and set, and that keeps its
  ;; value when the library is evaluated again (reload-libraries!), as a
  ;; defvar does. Chez exports no variable that is assigned, so the value
  ;; is a global (define-global). name must be written by the definer,
  ;; never made up by a macro: two states that a macro made in one file
  ;; would share the symbol.
  (define-syntax define-state
    (lambda (x)
      (syntax-case x ()
        [(_ name init)
         (with-syntax ([g (datum->syntax #'name (state-symbol #'name))])
           #'(define-global name g init #t))])))

  ;; Returns the symbol that an at-load-once form x keeps its flag under,
  ;; fixed by the file x is in and its forms, so that the library, evaluated
  ;; again, finds it.
  (meta define (once-symbol x)
    (let* ([a (syntax->annotation x)]
           [s (and a (annotation-source a))])
      (gensym "once"
              (format "schevana-once ~a ~x"
                      (if s
                          (source-file-descriptor-path (source-object-sfd s))
                          "")
                      (equal-hash (syntax->datum x))))))

  ;; (at-load-once form ...) runs expressions among a library's definitions,
  ;; as at-load does, but only when the library first loads in the world,
  ;; not when a reload evaluates it again: what a world does once, such as
  ;; starting a timer or giving an app its first data. Forms that change
  ;; are new ones, and run at the next reload.
  (define-syntax at-load-once
    (lambda (x)
      (syntax-case x ()
        [(k form ...)
         (with-syntax ([g (datum->syntax #'k (once-symbol x))])
           #'(begin
               (define-global done g #f #t)
               (define at-load-done
                 (unless done (set! done #t) form ... (void)))))])))

  ;; (define-view name state) gives state under another name, to read and
  ;; never to set: how a library passes on a state it imports. A set! of
  ;; the view is refused at expansion, with the message Chez gives for an
  ;; import.
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

  ;; (define-settable name state check) also gives state under another
  ;; name, as a facade gives a hook that a later layer fills; its set!
  ;; (set-hook!, fluid-let) accepts only a value that check passes.
  (define-syntax define-settable
    (syntax-rules ()
      [(_ name state check)
       (define-syntax name
         (make-variable-transformer
          (lambda (x)
            (syntax-case x (set!)
              [(set! n e)
               #'(let ([v e])
                   (unless (check v)
                     (errorf 'set! "~s can't be ~s" 'n v))
                   (set! state v))]
              [id (identifier? #'id) #'state]
              [(_ . rest) #'(state . rest)]))))]))

  ;; (define-made name init) defines a value made as the library loads,
  ;; read and never set: a buffer, a table, a foreign procedure, a fact
  ;; found out. It is a global under a view rather than a definition: a
  ;; library's own variable is held by every procedure that reads it and by
  ;; every procedure that calls one of those, so a closure made at run time
  ;; that only calls one of them carries it, and is allocated where the
  ;; same closure at the top level was not. Without such variables, a
  ;; library's procedures carry nothing (tests/units/allocation.ss). The
  ;; value is made again when the library is evaluated again, so a value
  ;; that a state may hold is made a state itself, and the two stay the
  ;; same object.
  (define-syntax define-made
    (lambda (x)
      (syntax-case x ()
        [(_ name init)
         (with-syntax ([g (datum->syntax #'name (gensym "made"))])
           #'(begin (define-global made g init #f)
                    (define-view name made)))])))

  ;; (define-hook (name . formals) body ...), or (define-hook name
  ;; procedure), defines a procedure that may be replaced, under its own
  ;; name. The library that calls it sits below the one that knows what it
  ;; does, which sets it (set-hook!). It is called by its name and set by
  ;; set!, as a state is. It is made again when the library is evaluated
  ;; again, and set again by the library that sets it, which imports it and
  ;; so is evaluated again after it.
  (define-syntax define-hook
    (lambda (x)
      (syntax-case x ()
        [(k (name . formals) body ...)
         #'(k name (lambda formals body ...))]
        [(_ name procedure)
         (with-syntax ([g (datum->syntax #'name (gensym "hook"))])
           #'(define-global name g procedure #f))])))

  ;; (set-hook! (name . formals) body ...) sets what the hook name does
  ;; from here on. It expands to a definition, so it can stand among a
  ;; library's definitions.
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

  ;; Whether str contains sub, ignoring case. It compares in place, a
  ;; character at a time, so a long str costs no copies.
  (define (string-contains-ci? str sub)
    (let ([n (string-length str)] [m (string-length sub)])
      (define (at? i j)   ; sub from j on matches str from i + j
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

  ;; Returns a read-only forwarder to the binding of the identifier id: a
  ;; macro that, installed in another environment, makes code there refer
  ;; to that binding itself (live, and without the cost of a call). A set!
  ;; of it is refused at expansion, with the message Chez gives for an
  ;; R6RS import.
  (define (forwarder-to id)
    (make-variable-transformer
     (lambda (x)
       (syntax-case x (set!)
         [(set! name . _)
          (syntax-error #'name "attempt to assign read-only variable")]
         [_ (identifier? x) id]
         [(_ . rest) #`(#,id . rest)]))))

  ;; A registry (apps, styles, palettes, wallpapers) is a list in
  ;; first-registration order. An entry whose name is already there replaces
  ;; that entry in place. name-of gives an entry's name.
  (define (registry-add entries entry name-of)
    (let ([name (name-of entry)])
      (if (exists (lambda (e) (eq? (name-of e) name)) entries)
          (map (lambda (e) (if (eq? (name-of e) name) entry e)) entries)
          (append entries (list entry)))))

  ;;; ---- what the platform is
  ;;; Which OS and CPU this is, as Chez was built for them. These are
  ;;; known before anything loads, so they are here, where every
  ;;; environment has them. What is known only once SDL and the GPU start
  ;;; (the windowing system, the GPU's API) core0 reports in
  ;;; *core0-platform* ((schevana core0 platform)), and the world asks
  ;;; (schevana core platform) for it. These say what the platform is;
  ;;; whether it can do a thing is asked of the thing itself.

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
