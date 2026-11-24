;;; (schevana services env) — environments: the world, and a tree of children,
;;; each given what its parent shares with it.
;;;
;;;   (env-fork (env-root) 'sandbox)          a child of a kind (below)
;;;   (env-fork e 'thread 'name 'tally 'share '(add! (clock . now-ns)))
;;;   (env-child (env-root) 'scratch 'chez)   a bare child: all of Chez, and
;;;                                           none of the world's names
;;;   (env-child (env-root) 'box 'confined)   what is always safe (below)
;;;   (env-share! e '(windows (clock . now-ms)))   names of the parent's; a
;;;                                           pair renames, so e's clock is
;;;                                           the parent's now-ms
;;;   (env-share-setter! e '*crew-size* 'crew-size-set!)
;;;   (env-share-world! e)                    every name of the world's,
;;;                                           and those the world gains
;;;                                           later, at e's next evaluation
;;;                                           or (env-sync! e)
;;;   (env-eval e '(windows))   (env-load e path)
;;;   (env-path e) => "/scratch"   (env-find "/scratch")   (env-drop! e)
;;;
;;; Root is the world (*world-env*), the superuser. A child has a base:
;;; chez (all of Chez), confined (what is always safe, for sandboxes) or
;;; core (Scheme's pure core, the worklets' base). Of its parent's names it
;;; has only those the parent shares, as read-only forwarders (forwarder-to,
;;; in (schevana base)): they are live, cost nothing per call, and refuse a
;;; set! as it expands ("attempt to assign read-only variable"), as R6RS
;;; refuses a set! of an import. The child's define of a name makes a name
;;; of its own. A name that is not shared is unbound in the child, and the
;;; child's set! of it makes a variable of the child's. So a child changes
;;; its parent's state only through what the parent shares with it.
;;;
;;; A child on the chez base is a namespace: it can still reach the world
;;; through Chez (eval, the inspector, C), so it organizes state but
;;; confines nothing. Code that makes an environment shares it a list of
;;; names; only a world namespace is shared every name of the world's as the
;;; world gains them, and only a person asks for one (tests/sources.ss).
;;;
;;; The tree belongs to core1: only core1 forks and drops environments.

(library (schevana services env)
  (export
    env env? env-name env-parent env-base env-environment env-children
    env-world? env-kind env-dropped? env-log env-root env-worklets
    env-generation env-path env-find env-child env-child-name env-share!
    env-share-setter! env-unsynced env-sync! env-holder env-binding env-eval
    env-load env-drop! env-shared-names env-own-names env-register-kind!
    env-kinds env-kind-ref env-forks env-kind-title env-title env-fork
    env-shares-check)
  (import (chezscheme)
          (only (schevana base) at-load define-made define-state filter-map
                forwarder-to library-layer plist-ref registry-add string-split)
          (only (schevana core) *worklet-environment* *world-env*
                core1-exported core1-thread? invalidate! load-file!
                worklet-base-environment)
          (only (schevana reload) reload-import!))

  (library-layer services)

  ;; An environment: its name and its parent (root has none); its base (#f
  ;; for root); its Chez environment, and an identifier made there, from
  ;; which identifiers of its names are made; its shares, a table from each
  ;; name to the parent's name it forwards to (or #f for a name a world
  ;; namespace kept as its own); its setters, a table from each name shared
  ;; through a setter to the setter's name; its children, oldest first;
  ;; whether it shares every name of the world's; its kind (#f for a bare
  ;; child) and the kinds it may fork (a list, or all); whether it was
  ;; dropped; what its parent gave it, a table from each name to a note
  ;; (env-give!); and, for a confined one, its log: the text it wrote to the
  ;; console.
  (define-record-type env
    (nongenerative schevana-env-3)
    (fields name parent base environment anchor shares setters
            (mutable children) (mutable world?) (mutable kind)
            (mutable may-fork) (mutable dropped?) given (mutable log)))

  ;; An env prints as #<env /private chez>: its path and its base, not the
  ;; tree it holds.
  (at-load
   (record-writer (record-type-descriptor env)
     (lambda (e p wr)
       (if (env-base e)
           (fprintf p "#<env ~a ~a>" (env-path e) (env-base e))
           (fprintf p "#<env ~a>" (env-path e))))))

  ;; Returns an identifier at environment's top level. A macro defined there
  ;; under a name no code can type (a gensym) hands back the identifier it is
  ;; used with, so this needs nothing of the environment's own, not even
  ;; syntax.
  (define (env-anchor-in environment)
    (let ([grab (gensym "env-anchor")] [got #f])
      (define-top-level-syntax grab
        (lambda (x)
          (syntax-case x () [(_ id) (begin (set! got #'id) #''anchor)]))
        environment)
      (eval (list grab 'env-anchor) environment)
      got))

  (define (env-new name parent base environment kind may-fork)
    (make-env name parent base environment (env-anchor-in environment)
              (make-eq-hashtable) (make-eq-hashtable) '() #f kind may-fork
              #f (make-eq-hashtable) ""))

  ;; Root, with the worklets' environment as its child. Core0, the recorder
  ;; and the core are sealed in their libraries and have no environment.
  (define-state *env-root*
    (let ([root (env-new 'root #f #f *world-env* 'root 'all)])
      (env-children-set! root
        (list (env-new 'worklets root 'core *worklet-environment*
                       'worklets '())))
      root))

  (define (env-root) *env-root*)

  ;; The world's shares are what the core gives it. They are set at each
  ;; load, since a reload may bring new ones.
  (at-load
   (for-each (lambda (n) (hashtable-set! (env-shares *env-root*) n n))
             (core1-exported)))

  ;; /worklets: the worklets live there, and the threads of the pool
  ;; (vat-pool) run them.
  (define (env-worklets)
    (find (lambda (c) (eq? (env-kind c) 'worklets)) (env-children *env-root*)))

  ;; Counts the forks and drops, so that a view of the tree keeps its rows
  ;; until the tree changes.
  (define-state *env-generation* 0)
  (define (env-generation) *env-generation*)

  ;; Chez's own names; the world's names are all the others.
  (define-made *env-chez-names*
    (let ([t (make-eq-hashtable)])
      (for-each (lambda (s) (hashtable-set! t s #t))
                (environment-symbols (scheme-environment)))
      t))

  (define (env-path e)
    (let ([p (env-parent e)])
      (cond [(not p) "/"]
            [(env-parent p) (format "~a/~a" (env-path p) (env-name e))]
            [else (format "/~a" (env-name e))])))

  ;; Returns the environment at path ("/", "/private"), or #f.
  (define (env-find path)
    (let loop ([e *env-root*]
               [names (remp (lambda (s) (string=? s ""))
                            (string-split path #\/))])
      (cond
        [(null? names) e]
        [(find (lambda (c) (string=? (symbol->string (env-name c)) (car names)))
               (env-children e))
         => (lambda (c) (loop c (cdr names)))]
        [else #f])))

  (define (env-on-core1 who)
    (unless (core1-thread?)
      (errorf who "the tree of environments is core1's")))

  ;; The bases, largest first.
  (define env-bases '(chez confined core))

  ;; Makes a bare child of parent on base, named name (or name-2, name-3 ...
  ;; when a sibling has that name), shared nothing and forking nothing. A
  ;; sandbox's child is a sandbox on the same base or a smaller one: a
  ;; sandbox may narrow what it hands down, never widen it.
  (define (env-child parent name base)
    (env-on-core1 'env-child)
    (when (and (memq (env-base parent) '(confined core))
               (not (memq base (memq (env-base parent) env-bases))))
      (errorf 'env-child "~a is a sandbox: its children are sandboxes on its \
                          base or a smaller one, not ~s"
              (env-path parent) base))
    (when (env-dropped? parent)
      (errorf 'env-child "~a was dropped" (env-path parent)))
    (let ([e (env-new (env-child-name parent name) parent base
                      (case base
                        [(chez) (copy-environment (scheme-environment) #t)]
                        [(confined) (env-confined-environment)]
                        [(core) (worklet-base-environment)]
                        [else (errorf 'env-child "no base ~s (expected ~a)"
                                      base env-bases)])
                      #f '())])
      (when (eq? base 'confined)
        (env-give-records! e)
        (env-give-console! e))
      (env-children-set! parent (append (env-children parent) (list e)))
      (set! *env-generation* (+ *env-generation* 1))
      e))

  ;; Returns the name that a child called name gets under parent: name, or
  ;; else the first of name-2, name-3 ... that no sibling has.
  (define (env-child-name parent name)
    (let ([taken (map env-name (env-children parent))])
      (let loop ([n 1])
        (let ([s (if (= n 1) name (string->symbol (format "~a-~a" name n)))])
          (if (memq s taken) (loop (+ n 1)) s)))))

  (define (env-parent-anchor who e)
    (let ([p (env-parent e)])
      (unless p (errorf who "the world has no parent to share with it"))
      (env-anchor p)))

  ;; Forwards e's names to those of anchor's environment. Each of names is
  ;; a name, or (e's name . the other environment's name).
  (define (env-forward! e anchor names)
    (for-each (lambda (n)
                (let ([name (if (pair? n) (car n) n)]
                      [target (if (pair? n) (cdr n) n)])
                  (define-top-level-syntax name
                    (forwarder-to (datum->syntax anchor target))
                    (env-environment e))
                  (hashtable-set! (env-shares e) name target)
                  (hashtable-delete! (env-setters e) name)))
              names))

  (define (env-share! e names)
    (env-forward! e (env-parent-anchor 'env-share! e) names))

  ;; Forwards e's name (or (name . parent's name)) as env-share! does, but
  ;; e's set! of it calls the parent's setter with the value, and the setter
  ;; may refuse.
  (define (env-share-setter! e n setter)
    (let* ([anchor (env-parent-anchor 'env-share-setter! e)]
           [name (if (pair? n) (car n) n)]
           [target (if (pair? n) (cdr n) n)]
           [id (datum->syntax anchor target)]
           [set (datum->syntax anchor setter)])
      (define-top-level-syntax name
        (make-variable-transformer
         (lambda (x)
           (syntax-case x (set!)
             [(set! _ v) #`(#,set v)]
             [_ (identifier? x) id]
             [(_ . rest) #`(#,id . rest)])))
        (env-environment e))
      (hashtable-set! (env-shares e) name target)
      (hashtable-set! (env-setters e) name setter)))

  (define (env-share-world! e)
    (env-world?-set! e #t)
    (env-sync! e))

  ;; Returns the world's names that the world namespace e has not been
  ;; shared yet, as (values new own): own holds those that e defined itself
  ;; meanwhile, and new the rest.
  (define (env-world-new e)
    (let ([new (filter (lambda (s)
                         (not (or (hashtable-contains? *env-chez-names* s)
                                  (hashtable-contains? (env-shares e) s))))
                       (environment-symbols *world-env*))])
      (if (null? new)
          (values '() '())
          (let ([mine (make-eq-hashtable)])
            (for-each (lambda (s) (hashtable-set! mine s #t))
                      (environment-symbols (env-environment e)))
            (partition (lambda (s) (not (hashtable-contains? mine s))) new)))))

  ;; Returns what a world namespace's next sync brings: the names the world
  ;; gained since the last sync, except those e defined itself. For any other
  ;; environment, returns none.
  (define (env-unsynced e)
    (if (env-world? e)
        (let-values ([(new own) (env-world-new e)]) new)
        '()))

  ;; Shares with a world namespace the world's names it has not been
  ;; shared yet, except those it defined itself meanwhile, which stay its
  ;; own. It runs before each evaluation and load in e; as a diff, it takes
  ;; under a millisecond.
  (define (env-sync! e)
    (when (env-world? e)
      (let-values ([(new own) (env-world-new e)])
        (env-forward! e (env-anchor *env-root*) new)
        (for-each (lambda (s) (hashtable-set! (env-shares e) s #f)) own))))

  ;; Returns where e's name is bound, as (values env name). It follows the
  ;; shares up to the environment that holds the binding, so that what
  ;; describes a name (the REPL's help) describes what the name forwards to.
  ;; A shared name that e defined itself is e's. An env's shares come from
  ;; its parent; the world, which has no parent, holds in its shares what
  ;; the core gives it.
  (define (env-holder e name)
    (let* ([from (env-parent e)]
           [target (and from (hashtable-ref (env-shares e) name #f))])
      (if (and target (not (top-level-bound? name (env-environment e))))
          (env-holder from target)
          (values e name))))

  ;; The same as env-holder, but returns e's Chez environment: (values
  ;; environment name).
  (define (env-binding e name)
    (let-values ([(h n) (env-holder e name)])
      (values (env-environment h) n)))

  ;; Evaluates form, or loads path, in e, with interaction-environment bound
  ;; to e's environment, so that defvar, eval and load inside mean e. What a
  ;; confined e writes to its console meanwhile also goes to the caller's
  ;; output (a REPL's). An import in the world or a namespace is kept
  ;; (reload-import!), so that (reload!) evaluates its libraries again when
  ;; their files change, and imports them again in e.
  (define (env-eval e form)
    (env-sync! e)
    (parameterize ([interaction-environment (env-environment e)]
                   [env-listener (cons e (current-output-port))])
      (if (and (pair? form) (eq? (car form) 'import)
               (memq (env-base e) '(#f chez)))
          (for-each (lambda (set)
                      (reload-import! (env-environment e)
                                      (env-import-library set) set))
                    (cdr form))
          (eval form (env-environment e)))))

  ;; Returns the library that an import set names: the set itself when it
  ;; is a library's name (without its version), else the one inside only,
  ;; except, prefix, rename or for; library wraps a name that starts with
  ;; one of those words.
  (define (env-import-library set)
    (case (car set)
      [(only except prefix rename for) (env-import-library (cadr set))]
      [(library) (filter symbol? (cadr set))]
      [else (filter symbol? set)]))

  (define (env-load e path)
    (env-sync! e)
    (parameterize ([interaction-environment (env-environment e)]
                   [env-listener (cons e (current-output-port))])
      (load-file! path)))

  ;; Drops e and its children from the tree. They are marked dropped, so
  ;; that whatever holds one (a REPL) knows. The world, /worklets (where the
  ;; worklets live) and an environment of a kind registered as 'kept are
  ;; never dropped.
  (define (env-drop! e)
    (env-on-core1 'env-drop!)
    (let ([p (env-parent e)])
      (cond [(not p) (errorf 'env-drop! "the world is not dropped")]
            [(eq? (env-kind e) 'worklets)
             (errorf 'env-drop! "/worklets is not dropped: the worklets live \
                                 there")]
            [(env-kind-ref (env-kind e) 'kept #f)
             => (lambda (why)
                  (errorf 'env-drop! "~a is not dropped: ~a" (env-path e)
                          why))])
      (env-children-set! p (remq e (env-children p)))
      (let mark ([e e])
        (env-dropped?-set! e #t)
        (for-each mark (env-children e)))
      (set! *env-generation* (+ *env-generation* 1))
      ;; Every window draws again, so one that holds e (a REPL) shows it
      ;; dropped.
      (invalidate!)))

  ;;; ---------------------------------------------------------------- names
  ;;; What an environment holds: the names it was shared and still forwards,
  ;;; and the names that are its own, apart from its base's names.

  ;; The names of the confined and core bases, each found once.
  (define-made *env-base-names* (make-eq-hashtable))
  (define (env-base-names base)
    (define (names-of environment)
      (let ([t (make-eq-hashtable)])
        (for-each (lambda (s) (hashtable-set! t s #t))
                  (environment-symbols environment))
        t))
    (case base
      [(confined core)
       (or (hashtable-ref *env-base-names* base #f)
           (let ([t (names-of (if (eq? base 'core)
                                  (worklet-base-environment)
                                  (env-confined-environment)))])
             (for-each (lambda (s) (hashtable-set! t s #t))
                       (if (eq? base 'confined) env-console-names '()))
             (hashtable-set! *env-base-names* base t)
             t))]
      [else *env-chez-names*]))   ; chez, and root: the world's are root's own

  ;; Returns the names e forwards and those its parent gave it, sorted by
  ;; name, as ((name parent's-name setter note) ...): setter is #f for a
  ;; read-only name, and note is #f except for a given one. With look? #f, e
  ;; is not asked which shared names it defined over (a vat's sandbox, which
  ;; only its thread may read).
  (define (env-shared-names e . look?)
    (let ([env (env-environment e)] [look? (or (null? look?) (car look?))])
      (sort (lambda (a b) (string<? (symbol->string (car a))
                                    (symbol->string (car b))))
            (append
             (filter-map (lambda (n)
                           (let ([t (hashtable-ref (env-shares e) n #f)])
                             (and t (not (and look? (top-level-bound? n env)))
                                  (list n t (hashtable-ref (env-setters e) n
                                                           #f)
                                        #f))))
                         (vector->list (hashtable-keys (env-shares e))))
             (map (lambda (n) (list n n #f (hashtable-ref (env-given e) n #f)))
                  (vector->list (hashtable-keys (env-given e))))))))

  ;; Returns the names e defined itself, sorted: not its base's, not
  ;; forwarded, not given.
  (define (env-own-names e)
    (let ([env (env-environment e)] [base (env-base-names (env-base e))])
      (sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
            (filter (lambda (s)
                      (not (or (gensym? s)
                               (hashtable-contains? base s)
                               (hashtable-contains? (env-given e) s)
                               (and (hashtable-ref (env-shares e) s #f)
                                    (not (top-level-bound? s env))))))
                    (environment-symbols env)))))

  ;; Binds e's name to value, which e's parent made for it (its fork, an
  ;; app's narrowed procedure, a stub), and lists it with e's shared names
  ;; with note, which says what it is ("its own fork").
  (define (env-give! e name value note)
    (define-top-level-value name value (env-environment e))
    (env-given! e name note))

  (define (env-given! e name note)
    (hashtable-delete! (env-shares e) name)
    (hashtable-delete! (env-setters e) name)
    (hashtable-set! (env-given e) name note))

  ;;; ---------------------------------------------------------------- confined
  ;;; The confined base, for sandboxes: only what is always safe, which
  ;;; touches only its arguments and what it makes itself. It has R6RS's
  ;;; libraries except those for I/O, files, programs, evaluation and record
  ;;; inspection; Chez's pure extras; string ports; and, narrowed, records
  ;;; and the console. Left out on purpose: syntax-case (datum->syntax on an
  ;;; identifier that a world macro hands in could name any of the world's
  ;;; bindings), record-writer (it would change how the world prints the
  ;;; types of conditions), the clock (the world's to share), eval and
  ;;; environments, C, threads and sleep, the inspector, Chez's own
  ;;; parameters, files, the console's ports, and exit. One name per line:
  ;;; adding one is a reviewed change, and a test (tests/units/env.ss)
  ;;; refuses the dangerous ones.

  (define env-confined-libraries
    '((rnrs base)
      (rnrs unicode)
      (rnrs bytevectors)
      (rnrs lists)
      (rnrs sorting)
      (rnrs control)
      (rnrs exceptions)
      (rnrs conditions)
      (rnrs records syntactic)
      (rnrs records procedural)
      (rnrs arithmetic fixnums)
      (rnrs arithmetic flonums)
      (rnrs arithmetic bitwise)
      (rnrs hashtables)
      (rnrs enums)
      (rnrs mutable-pairs)
      (rnrs mutable-strings)))

  (define env-confined-extras
    '(fx=
      fx<
      fx>
      fx<=
      fx>=
      fx+
      fx-
      fx*
      fx1+
      fx1-
      fxquotient
      fxremainder
      fxmodulo
      fxabs
      fxlogand
      fxlogor
      fxlogxor
      fxlognot
      fxsll
      fxsrl
      fxsra
      fl=
      fl<
      fl>
      fl<=
      fl>=
      fl+
      fl-
      fl*
      fl/
      flonum->fixnum
      add1
      sub1
      quotient
      remainder
      modulo
      exact->inexact
      inexact->exact
      logand
      logor
      logxor
      lognot
      ash
      random
      iota
      enumerate
      void
      box
      box?
      unbox
      set-box!
      box-cas!
      make-fxvector
      fxvector
      fxvector?
      fxvector-length
      fxvector-ref
      fxvector-set!
      fxvector-fill!
      fxvector-copy
      fxvector->list
      list->fxvector
      make-flvector
      flvector
      flvector?
      flvector-length
      flvector-ref
      flvector-set!
      flvector-fill!
      flvector-copy
      bytevector
      vector-copy
      string-copy!
      list-head
      last-pair
      list-copy
      make-list
      sort
      sort!
      merge
      andmap
      ormap
      gensym
      gensym?
      make-parameter
      parameterize
      fluid-let
      rec
      errorf
      call/1cc
      make-weak-eq-hashtable
      make-weak-eqv-hashtable
      hashtable-values
      hashtable-cells
      date?
      make-date
      date-nanosecond
      date-second
      date-minute
      date-hour
      date-day
      date-month
      date-year
      date-week-day
      date-year-day
      date-zone-offset
      open-output-string
      get-output-string
      open-input-string
      open-string-input-port
      get-char
      lookahead-char
      get-line
      get-string-all
      get-string-n
      get-datum
      put-char
      put-string
      put-datum
      fprintf
      eof-object
      eof-object?))

  ;; Returns a fresh confined Chez environment; env-child gives it its
  ;; records and its console.
  (define (env-confined-environment)
    (let ([e (copy-environment
              (apply environment   ; Chez's last, as its fx+ takes any count
                     (append env-confined-libraries
                             (list `(only (chezscheme)
                                          ,@env-confined-extras))))
              #t)])
      e))

  ;; e's records: a type named by a uid (nongenerative uid) stays one type
  ;; when a file loads again, so that what is kept across a reload still
  ;; opens. The uid is put under e's path, so that it cannot be another
  ;; environment's uid (the world's included) and open that one's records.
  (define (env-give-records! e)
    (define-top-level-syntax 'define-record-type
      (lambda (x) (env-confined-record-type e x))
      (env-environment e))
    (define-top-level-value 'make-record-type-descriptor
      (lambda (name parent uid . rest)
        (apply make-record-type-descriptor name parent
               (and uid (env-own-uid e uid)) rest))
      (env-environment e)))

  (define (env-own-uid e uid)
    (string->symbol (format "~a:~a" (env-path e) uid)))

  (define (env-confined-record-type e x)
    (syntax-case x ()
      [(_ name clause ...)
       (let loop ([cs #'(clause ...)] [done '()])
         (syntax-case cs ()
           [() #`(define-record-type name #,@(reverse done))]
           [((k uid) . rest) (and (identifier? #'k)
                                  (eq? (syntax->datum #'k) 'nongenerative)
                                  (identifier? #'uid))
            (loop #'rest
                  (cons #`(k #,(datum->syntax
                                #'uid (env-own-uid e (syntax->datum #'uid))))
                        done))]
           [(c . rest) (loop #'rest (cons #'c done))]))]))

  ;;; The console comes wrapped: what a confined environment writes to it
  ;;; goes to its log (env-log), which keeps the last env-log-max
  ;;; characters, and, while env-eval or env-load runs in it (a REPL's
  ;;; input), to the caller's output too. A port passed explicitly is
  ;;; written to directly.

  (define env-log-max 16384)

  ;; (env . port) while env-eval or env-load runs in env.
  (define-made env-listener (make-thread-parameter #f))

  (define env-console-names
    '(display write write-char pretty-print newline printf format
      current-output-port))

  (define (env-give-console! e)
    (let* ([log (make-custom-textual-output-port
                 (format "~a's log" (env-path e))
                 (lambda (s start n)
                   (env-log-add! e (substring s start (+ start n)))
                   n)
                 #f #f #f)]
           [flush (lambda (p) (when (eq? p log) (flush-output-port log)))]
           [to (lambda (put)   ; to the log, or to the port given
                 (case-lambda
                   [(x) (put x log) (flush log)]
                   [(x p) (put x p) (flush p)]))])
      (for-each
       (lambda (n v) (define-top-level-value n v (env-environment e)))
       env-console-names
       (list (to (lambda (x p) (display x p)))
             (to (lambda (x p) (write x p)))
             (to (lambda (x p) (write-char x p)))
             (to (lambda (x p) (pretty-print x p)))
             (case-lambda
               [() (newline log) (flush log)]
               [(p) (newline p) (flush p)])
             (lambda (f . args) (apply fprintf log f args) (flush log))
             (lambda (dest . args)   ; #t: the console
               (let ([p (if (eq? dest #t) log dest)])
                 (if (eq? p log)
                     (begin (apply fprintf log args) (flush log))
                     (apply format p args))))
             (lambda () log)))))

  (define (env-log-add! e s)
    (let* ([all (string-append (env-log e) s)] [n (string-length all)])
      (env-log-set! e (if (> n env-log-max)
                          (substring all (- n env-log-max) n)
                          all))
      (let ([l (env-listener)])
        (when (and l (eq? (car l) e))
          (put-string (cdr l) s)))))

  ;;; ---------------------------------------------------------------- kinds
  ;;; Each child is of a kind, which says its base, what it is shared at once
  ;;; and what it may fork in turn. The kinds are a registry
  ;;; (env-register-kind!), and the vats add thread. An environment forks
  ;;; only the kinds its own kind allows (env-forks): the world forks every
  ;;; kind, and so does a world namespace (it holds the world's names); a
  ;;; sandbox forks sandboxes and threads; the others fork none. An
  ;;; environment that forks holds fork, a procedure of its own:
  ;;;   (fork)                                  => the kinds it forks
  ;;;   (fork 'sandbox 'share '(add!))          => the child's path
  ;;;   private  a namespace shared what reads the world (env-private-names)
  ;;;   world    a namespace shared every name of the world's, as it gains
  ;;;            them
  ;;;   pure     a namespace shared nothing
  ;;;   sandbox  Scheme's pure core, and what is shared with it
  ;;;   thread   a sandbox in a vat of its own ((schevana services vat))

  ;; ((kind . plist) ...), in the order registered. The plist's keys are
  ;; 'title; 'base; 'forks (the kinds a child of this kind forks: a list, or
  ;; all); 'doc; 'share (a procedure of the child that makes the kind's own
  ;; shares, called first); 'start (a procedure of the child, called last);
  ;; 'fork (#f for a kind that only code makes, never a fork by hand); and
  ;; 'kept (the reason a child of the kind is never dropped).
  (define-state *env-kinds* '())

  (define (env-register-kind! kind . plist)
    (set! *env-kinds* (registry-add *env-kinds* (cons kind plist) car)))

  (define (env-kinds) (map car *env-kinds*))

  (define (env-kind-ref kind key default)
    (let ([k (assq kind *env-kinds*)])
      (if k (plist-ref (cdr k) key default) default)))

  ;; Returns the kinds e may fork, as a list. Kinds registered with 'fork #f
  ;; are left out: only code makes them.
  (define (env-forks e)
    (let ([f (env-may-fork e)])
      (filter (lambda (k) (env-kind-ref k 'fork #t))
              (if (eq? f 'all)
                  (env-kinds)
                  (filter (lambda (k) (assq k *env-kinds*)) f)))))

  ;; Returns a kind's title, the world's and the worklets' included.
  ;; env-title names a bare child by its base.
  (define (env-kind-title kind)
    (case kind
      [(root) "The world"]
      [(worklets) "Worklets"]
      [else (env-kind-ref kind 'title (format "~a" kind))]))

  (define (env-title e)
    (if (env-kind e)
        (env-kind-title (env-kind e))
        (if (eq? (env-base e) 'chez) "Namespace" "Sandbox")))

  ;; The world's names that a private namespace is shared, read-only and
  ;; live: those that read the world. Acting on the world is left to the
  ;; world.
  (define env-private-names
    '(windows
      focused-window
      find-window
      window-title
      window-ref
      apps
      procs
      styles
      current-style
      palettes
      wallpapers
      theme
      theme-keys
      now-ms
      uptime-ms
      source-files))

  ;; Makes a child of e of the given kind, which must be one that e forks
  ;; (env-forks), as e's fork procedure does. opts: 'name, the child's name
  ;; (the kind's by default, numbered when a sibling has it); 'share, names
  ;; e holds, in the form env-share! takes; 'setters, ((name . setter) ...),
  ;; names e holds, shared through e's setters, in the form
  ;; env-share-setter! takes. The kind's own shares come first, then these;
  ;; a thread's vat starts last. Anything wrong is refused before the child
  ;; is made. Returns the child.
  (define (env-fork e kind . opts)
    (let ([name (plist-ref opts 'name kind)]
          [shares (plist-ref opts 'share '())]
          [setters (plist-ref opts 'setters '())])
      (env-fork-check e kind opts name shares setters)
      (let ([c (env-child e name (env-kind-ref kind 'base #f))])
        (env-kind-set! c kind)
        (env-may-fork-set! c (env-kind-ref kind 'forks '()))
        ((env-kind-ref kind 'share (lambda (c) #f)) c)
        (env-share! c shares)
        (for-each (lambda (s) (env-share-setter! c (car s) (cdr s))) setters)
        (unless (null? (env-forks c)) (env-give-fork! c))
        ((env-kind-ref kind 'start (lambda (c) #f)) c)
        c)))

  (define (env-fork-check e kind opts name shares setters)
    (let ([kinds (env-forks e)])
      (cond
        [(env-dropped? e) (errorf 'fork "~a was dropped" (env-path e))]
        [(not (assq kind *env-kinds*))
         (errorf 'fork "no kind ~s (expected one of ~a)" kind (env-kinds))]
        [(null? kinds) (errorf 'fork "~a forks nothing, not ~s" (env-path e)
                               kind)]
        [(not (memq kind kinds))
         (errorf 'fork "~a forks ~a, not ~s" (env-path e) kinds kind)]))
    (let loop ([o opts])
      (when (pair? o)
        (unless (and (memq (car o) '(name share setters)) (pair? (cdr o)))
          (errorf 'fork "fork takes name, share and setters, not ~s" (car o)))
        (loop (cddr o))))
    (unless (and (symbol? name) (not (gensym? name))
                 (let ([s (symbol->string name)])
                   (and (> (string-length s) 0)
                        (not (memv #\/ (string->list s))))))
      (errorf 'fork "a name is a symbol without a slash, not ~s" name))
    (env-shares-check 'fork e shares setters))

  ;; Refuses shares and setters (in the forms env-share! and
  ;; env-share-setter! take from e) unless they have that shape and name
  ;; what e holds.
  (define (env-shares-check who e shares setters)
    (let ([held (make-eq-hashtable)])
      (for-each (lambda (s) (hashtable-set! held s #t))
                (environment-symbols (env-environment e)))
      (let ([check (lambda (n)
                     (unless (and (symbol? n) (hashtable-contains? held n))
                       (errorf who "~s is not ~a's to share" n (env-path e))))]
            [shape (lambda (n)
                     (unless (or (symbol? n)
                                 (and (pair? n) (symbol? (car n))
                                      (symbol? (cdr n))))
                       (errorf who "a share is a name or (name . ~a's), \
                                    not ~s" (env-path e) n))
                     (if (pair? n) (cdr n) n))])
        (unless (list? shares)
          (errorf who "share takes a list of names, not ~s" shares))
        (unless (and (list? setters) (for-all pair? setters))
          (errorf who "setters takes ((name . setter) ...), not ~s" setters))
        (for-each (lambda (n) (check (shape n))) shares)
        (for-each (lambda (s) (check (shape (car s))) (check (cdr s)))
                  setters))))

  ;; Gives e its own fork procedure: (fork) returns the kinds e forks, and
  ;; (fork kind opt ...) returns the new child's path.
  (define (env-give-fork! e)
    (env-give! e 'fork
               (case-lambda
                 [() (env-forks e)]
                 [(kind . opts) (env-path (apply env-fork e kind opts))])
               "its own fork"))

  (at-load
   (env-register-kind! 'private
     'title "Private namespace"
     'base 'chez
     'forks '()
     'doc "All of Chez, and what reads the world, read-only and live"
     'share (lambda (e) (env-share! e env-private-names))))

  (at-load
   (env-register-kind! 'world
     'title "World namespace"
     'base 'chez
     'forks 'all
     'doc "All of Chez, and every name of the world's, those it gains later \
           too"
     'share (lambda (e) (env-share-world! e))))

  (at-load
   (env-register-kind! 'pure
     'title "Pure namespace"
     'base 'chez
     'forks '()
     'doc "All of Chez, and nothing of the world's"))

  (at-load
   (env-register-kind! 'sandbox
     'title "Sandbox"
     'base 'core
     'forks '(sandbox thread)
     'doc "Scheme's pure core, and only what is shared with it")))
