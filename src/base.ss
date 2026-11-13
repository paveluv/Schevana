;;; base.ss — what every environment has: the basics, and the means by
;;; which a layer gives the next its names. Pure: it keeps no state and
;;; calls no C, so each environment loads a copy of its own, and any copy
;;; is as good as another (tests/sources.ss).

;; State variables that must survive (reload!) are declared with defvar,
;; like in Emacs: the initial value is only used if the name is unbound.
(define-syntax defvar
  (syntax-rules ()
    [(_ name init)
     (define name (if (top-level-bound? 'name) (top-level-value 'name) init))]))

;; A read-only forwarder to the identifier id's binding: a macro that,
;; installed in another environment, makes code there refer to that
;; binding itself (live, and at no cost a call). A set! of it is refused
;; as it expands, in the words Chez uses for an R6RS import's.
(define (forwarder-to id)
  (make-variable-transformer
   (lambda (x)
     (syntax-case x (set!)
       [(set! name . _)
        (syntax-error #'name "attempt to assign read-only variable")]
       [_ (identifier? x) id]
       [(_ . rest) #`(#,id . rest)]))))

;; The same, but a set!, and so a fluid-let, sets the binding, if (check
;; value); check #t lets any value by.
(define (forwarder-settable id check)
  (make-variable-transformer
   (lambda (x)
     (syntax-case x (set!)
       [(set! name v)
        (if (procedure? check)
            #`(set! #,id (let ([value v])
                           (if ((quote #,check) value)
                               value
                               (errorf 'set! "~s may not be ~s" 'name
                                       value))))
            #`(set! #,id v))]
       [_ (identifier? x) id]
       [(_ . rest) #`(#,id . rest)]))))

;; An identifier at environment's top level: a forwarder made from it names
;; that environment's binding. A macro there, under a name no code can type,
;; hands back the identifier it is used with, so it needs nothing of the
;; environment's own, not even syntax.
(define (environment-anchor environment)
  (let ([grab (gensym "anchor")] [got #f])
    (define-top-level-syntax grab
      (lambda (x)
        (syntax-case x () [(_ id) (begin (set! got #'id) #''anchor)]))
      environment)
    (eval (list grab 'anchor) environment)
    got))

;;; ---- exports
;;; Each layer below the world says in its export.ss what it gives the
;;; environments it makes, and nothing else gets there:
;;;
;;;   (define-exports name (export (destination ...) entry ...) ...)
;;;
;;; each entry a name, read-only there; or (settable name), whose set! and
;;; fluid-let reach the layer's own variable; or (settable name check), the
;;; same if (check value). The destinations are the chain's environments:
;;; the recorder's and core1's, which core0 makes, and the world's, "/",
;;; which core1 makes (main.ss).

(define-syntax define-exports
  (lambda (x)
    (define (destination? d) (memq (syntax->datum d) '(recorder core1 world)))
    (syntax-case x (export)
      [(_ name (export (destination ...) entry ...) ...)
       (for-all destination? #'(destination ... ...))
       #'(define name
           (list (cons '(destination ...) (list (export-entry entry) ...))
                 ...))])))

(define-syntax export-entry
  (lambda (x)
    (syntax-case x (settable)
      [(_ (settable name)) (identifier? #'name) #''(name . #t)]
      [(_ (settable name check)) (identifier? #'name) #'(cons 'name check)]
      [(_ name) (identifier? #'name) #''(name . #f)])))

;; Gives target what exports has for destination, each name a forwarder to
;; source's binding as its entry says. A name source doesn't have is
;; refused, so a slip in an export.ss stops the boot; a name target
;; defined itself stays its own.
(define (exports-install! exports source destination target)
  (let ([anchor (environment-anchor source)] [has (make-eq-hashtable)])
    ;; what source has, as syntax too: top-level-syntax? says so of any
    ;; name an environment doesn't have
    (for-each (lambda (s) (hashtable-set! has s #t))
              (environment-symbols source))
    (for-each
     (lambda (clause)
       (when (memq destination (car clause))
         (for-each
          (lambda (entry)
            (let ([name (car entry)] [check (cdr entry)])
              (unless (hashtable-ref has name #f)
                (errorf 'exports-install! "~s is not there to export" name))
              (unless (top-level-bound? name target)
                (define-top-level-syntax name
                  (let ([id (datum->syntax anchor name)])
                    (if check
                        (forwarder-settable id check)
                        (forwarder-to id)))
                  target))))
          (cdr clause))))
     exports)))

;; The names exports gives destination.
(define (exports-names exports destination)
  (apply append
         (map (lambda (clause)
                (if (memq destination (car clause))
                    (map car (cdr clause))
                    '()))
              exports)))

;;; ---- the basics

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
  (fold-right (lambda (x acc) (let ([y (f x)]) (if y (cons y acc) acc))) '() l))

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
;;; API) core0 says in *core0-platform* (src/core0/platform.ss), and the
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
(define (platform-arm64?) (eq? (platform-cpu) 'arm64))
