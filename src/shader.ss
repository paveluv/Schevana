;;; shader.ss — shaders in a small Scheme, for any GPU.
;;;
;;; The language is a contract: a new back end must always be possible.
;;; It defines its own meaning (ints are 32 bits and wrap; fxmod floors;
;;; dividing an int by 0 gives 0; a shift's count is taken mod 32; a read
;;; outside a buffer reads its last word, and a write outside is left out),
;;; and asks only for what every GPU API has: three stages, scalars, buffers
;;; of 4-byte elements by index, a 2D texture by integer fetch at a level, a
;;; uniform block of scalars, if and bounded loops. No structs, pointers,
;;; recursion or shared memory; a buffer is read or written in a run, never
;;; both.
;;;
;;; The front end checks types, inlines local functions, prices the shader
;;; and gives a small typed tree with no target in it:
;;;   (const type value)  (var type id)  (op type name arg ...)
;;;   (let id init body)  (seq form ...)  (if type test yes no)
;;;   (loop type most ((id type init step) ...) test result)
;;;   (load type buffer index)  (store buffer index value)
;;;   (fetch texture u v channel level)  (emit-position x y id)
;;;   (emit-color r g b a)  (nothing)
;;; cond, case, when and unless are only ways to write if, a constant is its
;;; number, helpers are local functions and a layout's field an index: all gone
;;; by the tree, and no back end knows of them.
;;; A back end is a table from those to its target and a walk over the
;;; tree. SPIR-V's and MSL's are here; the twin (kits/twin.ss), the same tree
;;; as a Scheme procedure, is another, so that nothing one target alone can do
;;; gets into the language.

;;; ------------------------------------------------------------------ front

(define shader-fx-folds '(fx+ fx* fxand fxior fxxor))
(define shader-fl-folds '(fl+ fl* flmin flmax))
(define shader-fl-calls '(flabs flfloor flceiling flround flsqrt flsin flcos))
(define shader-fx-compares '(fx= fx< fx> fx<= fx>=))
(define shader-fl-compares '(fl= fl< fl> fl<= fl>=))

(define (shader-error . args) (apply errorf 'shader args))

;; What shaders share, by name. A constant is one definition for shaders and
;; Scheme alike, so that what writes a number and what reads it can't disagree.
(defvar *shader-constants* (make-eq-hashtable))
(define-syntax define-shader-constant
  (syntax-rules ()
    [(_ name value)
     (begin
       (define name value)
       (hashtable-set! *shader-constants* 'name name))]))

;; A set of local functions, which a shader takes with
;; (use-shader-helpers name) where a define could go. They see what's in scope
;; there, and what isn't called costs nothing.
(defvar *shader-helpers* (make-eq-hashtable))
(define-syntax define-shader-helpers
  (syntax-rules ()
    [(_ name form ...)
     (hashtable-set! *shader-helpers* 'name '(form ...))]))

;; Names for a row's words, so that what writes a table and what reads it can't
;; disagree. (define-shader-layout glyph-row glyphs (u v)) gives
;; glyph-row-words, and glyph-row-u and glyph-row-v, each its offset to Scheme
;; and to shaders.
;; In a shader, (glyph-row-v row) reads that word through the reader, a buffer
;; or a function in scope there; with no row, the reader takes the offset alone.
(defvar *shader-fields* (make-eq-hashtable))
(define-syntax define-shader-layout
  (lambda (x)
    (syntax-case x ()
      [(k name reader (field ...))
       (let ([named (lambda (s)
                      (datum->syntax
                       #'k (string->symbol (format "~a-~a" (datum name) s))))]
             [fields (datum (field ...))])
         (with-syntax ([words (named 'words)]
                       [n (length fields)]
                       [(full ...) (map named fields)]
                       [(at ...) (iota (length fields))])
           #'(begin
               (define-shader-constant words n)
               (begin
                 (define-shader-constant full at)
                 (hashtable-set! *shader-fields* 'full '(reader . at)))
               ...)))])))

;; cond as ifs. With no else, it has no value: what wants one refuses it.
(define (shader-cond-form clauses form)
  (cond
    [(null? clauses) '(begin)]
    [(not (and (pair? (car clauses)) (pair? (cdar clauses))))
     (shader-error "~s: a clause wants a test and a body" form)]
    [(eq? (caar clauses) 'else)
     (unless (null? (cdr clauses))
       (shader-error "~s: else comes last" form))
     (cons 'begin (cdar clauses))]
    [else
     `(if ,(caar clauses)
          (begin ,@(cdar clauses))
          ,(shader-cond-form (cdr clauses) form))]))

;; A fixnum, or a constant's name that's one.
(define (shader-case-datum? d)
  (or (fixnum? d) (fixnum? (hashtable-ref *shader-constants* d #f))))

;; case as a cond: its key read once, each clause's fixnums by fx=.
(define (shader-case-form key clauses form)
  (let ([k (gensym)])
    `(let ([,k ,key])
       (cond
         ,@(map (lambda (clause)
                  (unless (and (pair? clause)
                               (or (eq? (car clause) 'else)
                                   (and (pair? (car clause))
                                        (for-all shader-case-datum?
                                                 (car clause)))))
                    (shader-error "~s: a clause wants fixnums, or else" form))
                  (if (eq? (car clause) 'else)
                      clause
                      (cons (cons 'or (map (lambda (d) `(fx= ,k ,d))
                                           (car clause)))
                            (cdr clause))))
                clauses)))))

;; Is an if a select: a value whose arms have nothing to work out, so that a
;; back end needs no branch for it?
(define (shader-select? t)
  (and (not (eq? (cadr t) 'void))
       (memq (car (cadddr t)) '(const var))
       (memq (car (car (cddddr t))) '(const var))
       #t))

;; A node's type.
(define (shader-type t)
  (case (car t)
    [(const var op if loop load) (cadr t)]
    [(let) (shader-type (cadddr t))]
    [(seq) (shader-type (car (last-pair t)))]
    [(fetch) 'flonum]
    [else 'void]))

(define shader-nothing '(nothing))

;; Lowers forms for a stage: the tree, with coords and params in scope.
(define (shader-lower stage coords params forms)
  (define next-id 0)
  (define (new-id!) (set! next-id (+ next-id 1)) next-id)
  (define (want type t form)
    (unless (eq? (shader-type t) type)
      (shader-error "~s: wants ~a, has ~a" form type (shader-type t)))
    t)
  (define (lookup name env) (let ([b (assq name env)]) (and b (cdr b))))
  (define (bind-value name t env)
    (cons (cons name (cons 'value t)) env))
  ;; (let id t (k var)), or (k t) if t is a constant or a variable already
  (define (bound t k)
    (if (memq (car t) '(const var))
        (k t)
        (let ([id (new-id!)])
          (list 'let id t (k (list 'var (shader-type t) id))))))
  (define (lower form env)
    (cond
      [(fixnum? form) (list 'const 'fixnum form)]
      [(flonum? form) (list 'const 'flonum form)]
      [(boolean? form) (list 'const 'boolean form)]
      [(symbol? form)
       (let ([b (lookup form env)])
         (cond
           [(and b (eq? (car b) 'value)) (cdr b)]
           [(and (not b) (hashtable-ref *shader-constants* form #f))
            => (lambda (v) (lower v env))]
           [else
            (shader-error "~a: not a value this shader was handed" form)]))]
      [(pair? form) (lower-call (car form) (cdr form) env form)]
      [else (shader-error "~s: not an expression" form)]))
  (define (fold-op type name args env form)
    (let ([ts (map (lambda (a) (want type (lower a env) form)) args)])
      (when (null? ts) (shader-error "~s: wants an argument" form))
      (fold-left (lambda (acc t) (list 'op type name acc t))
                 (car ts) (cdr ts))))
  (define (unary type result name arg env form)
    (list 'op result name (want type (lower arg env) form)))
  (define (compare type name args env form)
    (list 'op 'boolean name
          (want type (lower (car args) env) form)
          (want type (lower (cadr args) env) form)))
  ;; Targets leave dividing by 0, and the smallest int by -1, undefined, and
  ;; Vulkan a remainder of a negative: here by 0 gives 0, by -1 negates, and a
  ;; remainder is a - d(a/d). A divisor that isn't a constant divides as 1
  ;; where it's 0 or -1, and the quotient is multiplied by it there.
  (define (divide name args env form)
    (let ([a (want 'fixnum (lower (car args) env) form)]
          [b (want 'fixnum (lower (cadr args) env) form)])
      (bound a
        (lambda (a)
          (bound b
            (lambda (b)
              (let ([n (and (eq? (car b) 'const) (caddr b))])
                (cond
                  [(not n) (divide-guarded name a b)]
                  [(and (eqv? n -1) (eq? name 'fxquotient))
                   (list 'op 'fixnum 'fxneg a)]
                  [(memv n '(0 -1)) '(const fixnum 0)]
                  [else (divided name a b #f)]))))))))
  (define (divide-guarded name a b)
    (define (is n) (list 'op 'boolean 'fx= b (list 'const 'fixnum n)))
    (bound (is 0)
      (lambda (zero)
        (bound (is -1)
          (lambda (minus)
            (bound (list 'if 'boolean zero '(const boolean #t) minus)
              (lambda (edge)
                (bound (list 'if 'fixnum edge '(const fixnum 1) b)
                  (lambda (d)
                    (divided name a d
                             (list 'if 'fixnum edge b
                                   '(const fixnum 1))))))))))))
  ;; by d, never 0 or -1; the quotient times k, if any
  (define (divided name a d k)
    (let ([q (list 'op 'fixnum 'fxquotient a d)])
      (cond
        [(eq? name 'fxmod)
         (bound q
           (lambda (q)
             (floored (list 'op 'fixnum 'fx- a (list 'op 'fixnum 'fx* d q))
                      d)))]
        [k (list 'op 'fixnum 'fx* q k)]
        [else q])))
  ;; fxmod floors: a remainder that truncates, given the divisor's sign
  (define (floored r b)
    (bound r
      (lambda (r)
        (list 'if 'fixnum
              (list 'if 'boolean
                    (list 'op 'boolean 'fx= r '(const fixnum 0))
                    '(const boolean #f)
                    (list 'op 'boolean 'fx<
                          (list 'op 'fixnum 'fxxor r b)
                          '(const fixnum 0)))
              (list 'op 'fixnum 'fx+ r b)
              r))))
  (define (shift name args env form)
    (let ([a (want 'fixnum (lower (car args) env) form)]
          [n (want 'fixnum (lower (cadr args) env) form)])
      (list 'op 'fixnum name a
            (if (and (eq? (car n) 'const) (<= 0 (caddr n) 31))
                n
                (list 'op 'fixnum 'fxand n '(const fixnum 31))))))
  ;; A buffer's word at index i, read, or written with v: the index is checked
  ;; against the buffer's length, so that a shader touches only what it was
  ;; handed. A read's index is at most the last word's, unsigned, so that a
  ;; negative one is past it too: one instruction, where a compare and a select
  ;; cost a frame a fifth more. A write outside is left out: 0 <= i < n as one
  ;; compare, unsigned by the sign bit flipped on both sides.
  (define (in-range i name)
    (list 'op 'boolean 'fx<
          (list 'op 'fixnum 'fxxor i '(const fixnum -2147483648))
          (list 'op 'fixnum 'fxxor (list 'var 'fixnum (shader-words name))
                '(const fixnum -2147483648))))
  (define (checked-load type name i)
    (list 'load type name
          (list 'op 'fixnum 'fxumin i
                (list 'op 'fixnum 'fx-
                      (list 'var 'fixnum (shader-words name))
                      '(const fixnum 1)))))
  (define (checked-store name i v)
    (bound i
      (lambda (i)
        (list 'if 'void (in-range i name) (list 'store name i v)
              shader-nothing))))
  (define (element-of name env form type writing?)
    (let ([b (lookup name env)])
      (unless (and b (eq? (car b) 'buffer))
        (shader-error "~a: not a buffer this shader was handed" name))
      (unless (eq? (cadr b) type)
        (shader-error "~a: holds ~a, in ~s" name (cadr b) form))
      (unless (eq? (and (caddr b) #t) writing?)
        (shader-error "~a: ~a, in ~s" name
                      (if writing? "read-only" "write-only") form))
      name))
  (define (lower-seq forms env)
    (let loop ([forms forms] [env env] [acc '()])
      (cond
        [(null? forms)
         (cond
           [(null? acc) shader-nothing]
           [(null? (cdr acc)) (car acc)]
           [else (cons 'seq (reverse acc))])]
        [(and (pair? (car forms)) (eq? (caar forms) 'use-shader-helpers))
         (let ([helpers (hashtable-ref *shader-helpers* (cadr (car forms)) #f)])
           (unless helpers (shader-error "~s: no such helpers" (car forms)))
           (loop (append helpers (cdr forms)) env acc))]
        [(and (pair? (car forms)) (eq? (caar forms) 'define))
         (let ([head (cadr (car forms))])
           ;; its env holds what came before it, not itself: no recursion
           (loop (cdr forms)
                 (cons (list (car head) 'fn (cdr head) (cddr (car forms)) env)
                       env)
                 acc))]
        [else (loop (cdr forms) env (cons (lower (car forms) env) acc))])))
  ;; (let id init (let id init ... body)); sequential? sees earlier ones
  (define (lower-lets bindings sequential? body env)
    (let loop ([bs bindings] [inner env])
      (if (null? bs)
          (lower-seq body inner)
          (let* ([t (lower (cadr (car bs)) (if sequential? inner env))]
                 [name (car (car bs))])
            (if (memq (car t) '(const var))
                (loop (cdr bs) (bind-value name t inner))
                (let ([id (new-id!)])
                  (list 'let id t
                        (loop (cdr bs)
                              (bind-value name
                                          (list 'var (shader-type t) id)
                                          inner)))))))))
  ;; A local function, inlined: its arguments evaluated once, as let's.
  (define (lower-inline b args env form)
    (let ([ps (car b)] [body (cadr b)] [fenv (caddr b)])
      (unless (= (length ps) (length args))
        (shader-error "~s: wants ~a arguments" form (length ps)))
      (let loop ([ps ps] [args args] [inner fenv])
        (if (null? ps)
            (lower-seq body inner)
            (let ([t (lower (car args) env)])
              (if (memq (car t) '(const var))
                  (loop (cdr ps) (cdr args) (bind-value (car ps) t inner))
                  (let ([id (new-id!)])
                    (list 'let id t
                          (loop (cdr ps) (cdr args)
                                (bind-value
                                 (car ps) (list 'var (shader-type t) id)
                                 inner))))))))))
  ;; A test known here leaves only its arm, so that a shader made twice, with
  ;; a part and without, has none of it the second time, whatever the target's
  ;; compiler would do. A name bound to a constant is the constant.
  (define (lower-if test yes no env form)
    (let ([c (want 'boolean (lower test env) form)]
          [a (lower yes env)]
          [b (lower no env)])
      (unless (eq? (shader-type a) (shader-type b))
        (shader-error "~s: arms of ~a and ~a" form
                      (shader-type a) (shader-type b)))
      (if (eq? (car c) 'const)
          (if (caddr c) a b)
          (list 'if (shader-type a) c a b))))
  ;; (do-bounded most ([v init step] ...) (test result)): at most most
  ;; rounds, so a shader's cost is known before it runs.
  (define (lower-do form env)
    (let* ([most (cadr form)]
           [specs (caddr form)]
           [end (cadddr form)])
      (unless (and (fixnum? most) (fx> most 0))
        (shader-error "~s: loops have a fixed bound" form))
      (let* ([inits (map (lambda (s) (lower (cadr s) env)) specs)]
             [ids (map (lambda (s) (new-id!)) specs)]
             [inner (fold-left
                     (lambda (e s id t)
                       (bind-value (car s)
                                   (list 'var (shader-type t) id) e))
                     env specs ids inits)]
             [steps (map (lambda (s) (lower (caddr s) inner)) specs)]
             [test (want 'boolean (lower (car end) inner) form)]
             [result (lower (cadr end) inner)])
        (for-each (lambda (i s)
                    (unless (eq? (shader-type i) (shader-type s))
                      (shader-error "~s: a variable changes type" form)))
                  inits steps)
        (list 'loop (shader-type result) most
              (map (lambda (id i s) (list id (shader-type i) i s))
                   ids inits steps)
              test result))))
  ;; A layout's field read: (reader offset), or at a row, (reader row + offset).
  (define (lower-field f args env form)
    (let* ([reader (car f)]
           [offset (cdr f)]
           [b (lookup reader env)]
           [index (cond [(null? args) offset]
                        [(pair? (cdr args))
                         (shader-error "~s: wants at most a row" form)]
                        [(eqv? offset 0) (car args)]
                        [else `(fx+ ,(car args) ,offset)])])
      (unless b (shader-error "~s: ~a isn't in scope" form reader))
      (lower (if (eq? (car b) 'fn)
                 `(,reader ,index)
                 `(fx-ref ,reader ,index))
             env)))
  (define (lower-call head args env form)
    (let ([b (lookup head env)])
      (cond
        [(and b (eq? (car b) 'fn)) (lower-inline (cdr b) args env form)]
        [(hashtable-ref *shader-fields* head #f)
         => (lambda (f) (lower-field f args env form))]
        [(memq head shader-fx-folds)
         (fold-op 'fixnum head args env form)]
        [(memq head shader-fl-folds)
         (fold-op 'flonum head args env form)]
        [(memq head shader-fl-calls)
         (unary 'flonum 'flonum head (car args) env form)]
        [(memq head shader-fx-compares) (compare 'fixnum head args env form)]
        [(memq head shader-fl-compares) (compare 'flonum head args env form)]
        [else
         (case head
           [(fx-)
            (if (null? (cdr args))
                (unary 'fixnum 'fixnum 'fxneg (car args) env form)
                (fold-op 'fixnum 'fx- args env form))]
           [(fl-)
            (if (null? (cdr args))
                (unary 'flonum 'flonum 'flneg (car args) env form)
                (fold-op 'flonum 'fl- args env form))]
           [(fl/) (fold-op 'flonum 'fl/ args env form)]
           [(fxnot) (unary 'fixnum 'fixnum 'fxnot (car args) env form)]
           [(not) (unary 'boolean 'boolean 'not (car args) env form)]
           [(fxquotient fxmod) (divide head args env form)]
           [(fxsll fxsrl fxsra) (shift head args env form)]
           [(fixnum->flonum)
            (unary 'fixnum 'flonum 'fixnum->flonum (car args) env form)]
           [(flonum->fixnum)
            (unary 'flonum 'fixnum 'flonum->fixnum (car args) env form)]
           [(let) (lower-lets (car args) #f (cdr args) env)]
           [(let*) (lower-lets (car args) #t (cdr args) env)]
           [(begin) (lower-seq args env)]
           [(if)
            (lower-if (car args) (cadr args)
                      (if (null? (cddr args)) '(begin) (caddr args))
                      env form)]
           [(cond) (lower (shader-cond-form args form) env)]
           [(case) (lower (shader-case-form (car args) (cdr args) form) env)]
           [(when)
            (lower-if (car args) (cons 'begin (cdr args)) '(begin) env form)]
           [(unless)
            (lower-if (car args) '(begin) (cons 'begin (cdr args)) env form)]
           [(and)
            (if (null? (cdr args))
                (lower (car args) env)
                (lower-if (car args) (cons 'and (cdr args)) #f env form))]
           [(or)
            (if (null? (cdr args))
                (lower (car args) env)
                (lower-if (car args) #t (cons 'or (cdr args)) env form))]
           [(do-bounded) (lower-do form env)]
           [(fx-ref)
            (checked-load 'fixnum (element-of (car args) env form 'fixnum #f)
                          (want 'fixnum (lower (cadr args) env) form))]
           [(fl-ref)
            (checked-load 'flonum (element-of (car args) env form 'flonum #f)
                          (want 'fixnum (lower (cadr args) env) form))]
           [(fx-set!)
            (checked-store (element-of (car args) env form 'fixnum #t)
                           (want 'fixnum (lower (cadr args) env) form)
                           (want 'fixnum (lower (caddr args) env) form))]
           [(fl-set!)
            (checked-store (element-of (car args) env form 'flonum #t)
                           (want 'fixnum (lower (cadr args) env) form)
                           (want 'flonum (lower (caddr args) env) form))]
           [(texture-ref)
            (let ([t (lookup (car args) env)])
              (unless (and t (eq? (car t) 'texture))
                (shader-error "~a: not a texture this shader was handed"
                              (car args)))
              (let ([c (lower (cadddr args) env)])
                (unless (and (eq? (car c) 'const) (fixnum? (caddr c))
                             (<= 0 (caddr c) 3))
                  (shader-error "~s: wants a channel, 0 to 3" form)))
              (list 'fetch (car args)
                    (want 'fixnum (lower (cadr args) env) form)
                    (want 'fixnum (lower (caddr args) env) form)
                    (caddr (lower (cadddr args) env))
                    (if (null? (cddddr args))
                        '(const fixnum 0)
                        (want 'fixnum (lower (car (cddddr args)) env) form))))]
           [(emit-position)
            (list 'emit-position
                  (want 'flonum (lower (car args) env) form)
                  (want 'flonum (lower (cadr args) env) form)
                  (want 'fixnum (lower (caddr args) env) form))]
           [(emit-color)
            (cons 'emit-color
                  (map (lambda (a) (want 'flonum (lower a env) form)) args))]
           [else (shader-error "~a: not available in a shader" head)])])))
  (let* ([env
          (fold-left
           (lambda (e p)
             (case (cadr p)
               [(fixnum flonum)
                (bind-value (car p) (list 'var (cadr p) (car p)) e)]
               [(fx-buffer fl-buffer)
                (cons (list (car p) 'buffer
                            (if (eq? (cadr p) 'fx-buffer) 'fixnum 'flonum)
                            (and (memq 'write (cddr p)) #t))
                      e)]
               [(texture) (cons (list (car p) 'texture) e)]
               [else (shader-error "~s: no such parameter" p)]))
           (shader-coord-env stage coords)
           params)]
         [body (lower-seq forms env)])
    ;; a dispatch counts in whole groups: only cells inside the area run
    (if (eq? stage 'compute)
        (list 'if 'void
              (list 'if 'boolean
                    (list 'op 'boolean 'fx<
                          (list 'var 'fixnum (car coords))
                          '(var fixnum shader-w))
                    (list 'op 'boolean 'fx<
                          (list 'var 'fixnum (cadr coords))
                          '(var fixnum shader-h))
                    '(const boolean #f))
              body shader-nothing)
        body)))

(define (shader-coord-env stage coords)
  (map (lambda (name type)
         (cons name (cons 'value (list 'var type name))))
       coords
       (case stage
         [(compute vertex) '(fixnum fixnum)]
         [else '(flonum flonum fixnum)])))

;; What a run of the tree costs at most: one unit an operation, a little
;; more for what touches memory or takes a root, times a loop's bound.
(define (shader-tree-price t)
  (define (sum ts)
    (fold-left (lambda (n t) (+ n (shader-tree-price t))) 0 ts))
  (case (car t)
    [(const var nothing) 0]
    [(op) (+ (if (memq (caddr t) '(flsqrt flsin flcos)) 4 1) (sum (cdddr t)))]
    [(let) (+ (shader-tree-price (caddr t)) (shader-tree-price (cadddr t)))]
    [(seq) (sum (cdr t))]
    [(if) (+ 1 (shader-tree-price (caddr t))
             (max (shader-tree-price (cadddr t))
                  (shader-tree-price (car (cddddr t)))))]
    [(loop)
     (let ([vars (cadddr t)])
       (+ (sum (map caddr vars))
          (* (caddr t)
             (+ 1 (sum (map cadddr vars))
                (shader-tree-price (car (cddddr t)))))
          (shader-tree-price (cadr (cddddr t)))))]
    [(load) (+ 2 (shader-tree-price (cadddr t)))]
    [(store) (+ 2 (shader-tree-price (caddr t)) (shader-tree-price (cadddr t)))]
    [(fetch) (+ 8 (shader-tree-price (caddr t)) (shader-tree-price (cadddr t))
                (shader-tree-price (list-ref t 5)))]
    [(emit-position emit-color) (+ 1 (sum (cdr t)))]
    [else 0]))

;;; ------------------------------------------------------------------ SPIR-V
;;; A module is a stream of 32-bit words; an instruction's first word holds
;;; its length and opcode, and every result has a number, assigned once.
;;; SDL's numbering: compute, read-only buffers in set 0, read-write in 1,
;;; uniforms in 2; vertex, textures then buffers in set 0, uniforms in 1;
;;; fragment, the same in sets 2 and 3.

(define spirv-binary-ops
  '((fx+ . 128) (fl+ . 129) (fx- . 130) (fl- . 131) (fx* . 132) (fl* . 133)
    (fxquotient . 135) (fl/ . 136)
    (fxand . 199) (fxior . 197) (fxxor . 198)
    (fxsll . 196) (fxsrl . 194) (fxsra . 195)
    (fx= . 170) (fx> . 173) (fx>= . 175) (fx< . 177) (fx<= . 179)
    (fl= . 180) (fl< . 184) (fl> . 186) (fl<= . 188) (fl>= . 190)))
(define spirv-unary-ops
  '((fxneg . 126) (flneg . 127) (fxnot . 200) (not . 168)
    (fixnum->flonum . 111) (flonum->fixnum . 110)))
;; GLSL.std.450's numbers; flround is RoundEven, for Round leaves which way a
;; half goes to the driver
(define spirv-math-ops
  '((flround . 2) (flabs . 4) (flfloor . 8) (flceiling . 9)
    (flsin . 13) (flcos . 14) (flsqrt . 31) (flmin . 37) (fxumin . 38)
    (flmax . 40)))

(define (spirv-string s)
  (let* ([b (string->utf8 s)]
         [n (bytevector-length b)]
         [out (make-bytevector (* 4 (+ 1 (quotient n 4))) 0)])
    (bytevector-copy! b 0 out 0 n)
    (let loop ([i 0] [acc '()])
      (if (= i (bytevector-length out))
          (reverse acc)
          (loop (+ i 4) (cons (bytevector-u32-native-ref out i) acc))))))

(define (shader-float-bits x)
  (let ([b (make-bytevector 4)])
    (bytevector-ieee-single-native-set! b 0 x)
    (bytevector-u32-native-ref b 0)))

(define (shader-spirv stage coords params tree)
  (define next 1)
  (define decos '())
  (define types '())
  (define body '())
  (define block 0)
  (define ints (make-eqv-hashtable))
  (define floats (make-eqv-hashtable))
  (define yes-id #f)
  (define no-id #f)
  (define vars (make-eqv-hashtable))
  (define buffers (make-eq-hashtable))    ; name -> variable
  (define textures (make-eq-hashtable))
  (define (id!) (let ([n next]) (set! next (+ n 1)) n))
  (define (inst op words) (cons (logor (ash (+ 1 (length words)) 16) op) words))
  (define (deco! op . w) (set! decos (cons (inst op w) decos)))
  (define (type! op . w) (set! types (cons (inst op w) types)))
  (define (body! op . w) (set! body (cons (inst op w) body)))
  (define (new-type! op . w) (let ([i (id!)]) (apply type! op i w) i))
  (define (op! op type . w) (let ([i (id!)]) (apply body! op type i w) i))
  (define (label! i) (body! 248 i) (set! block i))
  (define ext (id!))
  (define t-void (new-type! 19))
  (define t-bool (new-type! 20))
  (define t-int (new-type! 21 32 1))
  (define t-uint (new-type! 21 32 0))
  (define t-float (new-type! 22 32))
  (define t-vec4 (new-type! 23 t-float 4))
  (define t-ivec2 (new-type! 23 t-int 2))
  (define t-uvec3 (new-type! 23 t-uint 3))
  (define t-image (new-type! 25 t-float 1 0 0 0 1 0))
  (define t-sampled (new-type! 27 t-image))
  (define t-fn (new-type! 33 t-void))
  (define p-int (new-type! 32 2 t-int))
  (define p-float (new-type! 32 2 t-float))
  (define rt-int (new-type! 29 t-int))
  (define rt-float (new-type! 29 t-float))
  (define (type-id t)
    (case t
      [(fixnum) t-int]
      [(flonum) t-float]
      [(boolean) t-bool]
      [else (shader-error "no value of type ~a" t)]))
  (define (int-const n)
    (or (hashtable-ref ints n #f)
        (let ([i (id!)])
          (type! 43 t-int i (logand n #xffffffff))
          (hashtable-set! ints n i)
          i)))
  (define (float-const x)
    (let ([bits (shader-float-bits x)])
      (or (hashtable-ref floats bits #f)
          (let ([i (id!)])
            (type! 43 t-float i bits)
            (hashtable-set! floats bits i)
            i))))
  (define (bool-const b)
    (if b
        (or yes-id (begin (set! yes-id (id!)) (type! 41 t-bool yes-id) yes-id))
        (or no-id (begin (set! no-id (id!)) (type! 42 t-bool no-id) no-id))))
  (define (var! ptr storage)
    (let ([v (id!)]) (type! 59 ptr v storage) v))
  ;; an element's pointer
  (define (element buffer index)
    (let* ([b (hashtable-ref buffers buffer #f)])
      (op! 65 (if (eq? (car b) 'flonum) p-float p-int)
           (cdr b) (int-const 0) index)))
  (define out-position 0)
  (define out-id 0)
  (define out-color 0)
  (define (value t)
    (case (car t)
      [(const)
       (case (cadr t)
         [(fixnum) (int-const (caddr t))]
         [(flonum) (float-const (caddr t))]
         [else (bool-const (caddr t))])]
      [(var) (hashtable-ref vars (caddr t) #f)]
      [(op) (operation t)]
      [(let)
       (hashtable-set! vars (cadr t) (value (caddr t)))
       (value (cadddr t))]
      [(seq) (fold-left (lambda (last f) (value f)) 0 (cdr t))]
      [(if) (branch t)]
      [(loop) (bounded-loop t)]
      [(load)
       (op! 61 (type-id (cadr t)) (element (caddr t) (value (cadddr t))))]
      [(store)
       (let* ([p (element (cadr t) (value (caddr t)))]
              [v (value (cadddr t))])
         (body! 62 p v)
         0)]
      [(fetch)
       (let* ([u (value (caddr t))]
              [v (value (cadddr t))]
              [level (value (list-ref t 5))]
              [s (op! 61 t-sampled (hashtable-ref textures (cadr t) #f))]
              [i (op! 100 t-image s)]
              [c (op! 80 t-ivec2 u v)]
              ;; Lod, operand mask 2
              [p (op! 95 t-vec4 i c 2 level)])
         (op! 81 t-float p (car (cddddr t))))]
      [(emit-position)
       (let* ([x (value (cadr t))]
              [y (value (caddr t))]
              [i (value (cadddr t))]
              [p (op! 80 t-vec4 x y (float-const 0.0) (float-const 1.0))])
         (body! 62 out-position p)
         (body! 62 out-id i)
         0)]
      [(emit-color)
       (let* ([r (value (cadr t))]
              [g (value (caddr t))]
              [b (value (cadddr t))]
              [a (value (car (cddddr t)))])
         (body! 62 out-color (op! 80 t-vec4 r g b a))
         0)]
      [else 0]))
  (define (operation t)
    (let* ([type (type-id (cadr t))]
           [name (caddr t)]
           [args (map value (cdddr t))])
      (cond
        [(assq name spirv-binary-ops)
         => (lambda (o) (apply op! (cdr o) type args))]
        [(assq name spirv-unary-ops)
         => (lambda (o) (apply op! (cdr o) type args))]
        [(assq name spirv-math-ops)
         => (lambda (o) (apply op! 12 type ext (cdr o) args))]
        [else (shader-error "no SPIR-V for ~a" name)])))
  ;; Every if is a branch with a declared merge, as SPIR-V's structured
  ;; control flow demands, and its value a phi there.
  (define (branch t)
    (if (shader-select? t)
        (op! 169 (type-id (cadr t)) (value (caddr t)) (value (cadddr t))
             (value (car (cddddr t))))
        (branch-on t)))
  (define (branch-on t)
    (let* ([c (value (caddr t))]
           [then (id!)] [other (id!)] [merge (id!)])
      (body! 247 merge 0)
      (body! 250 c then other)
      (label! then)
      (let* ([a (value (cadddr t))] [a-end block])
        (body! 249 merge)
        (label! other)
        (let* ([b (value (car (cddddr t)))] [b-end block])
          (body! 249 merge)
          (label! merge)
          (if (eq? (cadr t) 'void)
              0
              (op! 245 (type-id (cadr t)) a a-end b b-end))))))
  ;; The test in a block of its own, as it may hold branches; at most most
  ;; rounds, by a counter the tree doesn't see. A phi names its later value
  ;; before that exists: its place is filled once it does.
  (define (bounded-loop t)
    (let* ([most (caddr t)]
           [specs (cadddr t)]
           [test (car (cddddr t))]
           [result (cadr (cddddr t))]
           [inits (map (lambda (s) (value (caddr s))) specs)]
           [before block]
           [header (id!)] [check (id!)] [work (id!)] [round-end (id!)]
           [merge (id!)]
           [count (id!)]
           [count-next (id!)]
           [phis (map (lambda (s init)
                        (let ([phi (id!)])
                          (hashtable-set! vars (car s) phi)
                          (inst 245 (list (type-id (cadr s)) phi
                                          init before 0 round-end))))
                      specs inits)])
      (body! 249 header)
      (label! header)
      (body! 245 t-int count (int-const 0) before count-next round-end)
      (set! body (append (reverse phis) body))
      (body! 246 merge round-end 0)
      (body! 249 check)
      (label! check)
      (let* ([done (value test)]
             [over (op! 175 t-bool count (int-const most))]
             [stop (op! 166 t-bool done over)])
        (body! 250 stop merge work)
        (label! work)
        (for-each (lambda (s phi)
                    (set-car! (list-tail phi 5) (value (cadddr s))))
                  specs phis)
        (body! 249 round-end)
        (label! round-end)
        (body! 128 t-int count-next count (int-const 1))
        (body! 249 header)
        (label! merge)
        (value result))))
  (let* ([uniforms (shader-uniforms stage params)]
         [members (length uniforms)]
         [set-read (if (eq? stage 'fragment) 2 0)]
         [set-uniform (case stage [(compute) 2] [(vertex) 1] [else 3])]
         [texture-count
          (length (filter (lambda (p) (eq? (cadr p) 'texture)) params))]
         [main (id!)]
         [entry (id!)]
         [ubo (and (> members 0)
                   (apply new-type! 30
                          (map (lambda (u) (type-id (cadr u))) uniforms)))]
         [u (and ubo (var! (new-type! 32 2 ubo) 2))]
         [p-sampled (new-type! 32 0 t-sampled)]
         [p-in-int (new-type! 32 1 t-int)]
         [p-out-int (new-type! 32 3 t-int)]
         [p-in-vec4 (new-type! 32 1 t-vec4)]
         [p-out-vec4 (new-type! 32 3 t-vec4)]
         [p-in-uvec3 (new-type! 32 1 t-uvec3)]
         [gid (and (eq? stage 'compute) (var! p-in-uvec3 1))]
         [vi (and (eq? stage 'vertex) (var! p-in-int 1))]
         [ii (and (eq? stage 'vertex) (var! p-in-int 1))]
         [frag (and (eq? stage 'fragment) (var! p-in-vec4 1))]
         [in-id (and (eq? stage 'fragment) (var! p-in-int 1))])
    (deco! 71 rt-int 6 4)
    (deco! 71 rt-float 6 4)
    (when ubo
      (deco! 71 ubo 2)
      (do ([k 0 (+ k 1)]) ((= k members)) (deco! 72 ubo k 35 (* 4 k)))
      (deco! 71 u 34 set-uniform)
      (deco! 71 u 33 0))
    (let ([interface
           (case stage
             [(compute) (deco! 71 gid 11 28) (list gid)]
             [(vertex)
              (set! out-position (var! p-out-vec4 3))
              (set! out-id (var! p-out-int 3))
              (deco! 71 vi 11 42)
              (deco! 71 ii 11 43)
              (deco! 71 out-position 11 0)
              (deco! 71 out-id 30 0)
              (list vi ii out-position out-id)]
             [else
              (set! out-color (var! p-out-vec4 3))
              (deco! 71 frag 11 15)
              (deco! 71 in-id 30 0)
              (deco! 71 in-id 14)
              (deco! 71 out-color 30 0)
              (list frag in-id out-color)])])
      (let ([read-n 0] [write-n 0] [tex-n 0])
        (for-each
         (lambda (p)
           (case (cadr p)
             [(fx-buffer fl-buffer)
              (let* ([float? (eq? (cadr p) 'fl-buffer)]
                     [write? (and (memq 'write (cddr p)) #t)]
                     [s (new-type! 30 (if float? rt-float rt-int))]
                     [v (var! (new-type! 32 2 s) 2)])
                (deco! 71 s 3)
                (deco! 72 s 0 35 0)
                (unless write? (deco! 72 s 0 24))
                (deco! 71 v 34 (if write? 1 set-read))
                (deco! 71 v 33 (if write?
                                   write-n
                                   (+ read-n (if (eq? stage 'compute)
                                                 0
                                                 texture-count))))
                (if write?
                    (set! write-n (+ write-n 1))
                    (set! read-n (+ read-n 1)))
                (hashtable-set! buffers (car p)
                                (cons (if float? 'flonum 'fixnum) v)))]
             [(texture)
              (let ([v (var! p-sampled 0)])
                (deco! 71 v 34 set-read)
                (deco! 71 v 33 tex-n)
                (set! tex-n (+ tex-n 1))
                (hashtable-set! textures (car p) v))]))
         params))
      (body! 54 t-void main 0 t-fn)
      (label! entry)
      (case stage
        [(compute)
         (let ([g (op! 61 t-uvec3 gid)])
           (hashtable-set! vars (car coords)
                           (op! 124 t-int (op! 81 t-uint g 0)))
           (hashtable-set! vars (cadr coords)
                           (op! 124 t-int (op! 81 t-uint g 1))))]
        [(vertex)
         (hashtable-set! vars (car coords) (op! 61 t-int vi))
         (hashtable-set! vars (cadr coords) (op! 61 t-int ii))]
        [else
         (let ([f (op! 61 t-vec4 frag)])
           (hashtable-set! vars (car coords) (op! 81 t-float f 0))
           (hashtable-set! vars (cadr coords) (op! 81 t-float f 1))
           (hashtable-set! vars (caddr coords) (op! 61 t-int in-id)))])
      (let loop ([us uniforms] [k 0])
        (unless (null? us)
          (let ([type (cadr (car us))])
            (hashtable-set!
             vars (car (car us))
             (op! 61 (type-id type)
                  (op! 65 (if (eq? type 'flonum) p-float p-int)
                       u (int-const k)))))
          (loop (cdr us) (+ k 1))))
      (value tree)
      (body! 253)
      (body! 56)
      (let* ([words
              (append
               (list #x07230203 #x00010000 0 next 0)
               (inst 17 '(1))
               (inst 11 (cons ext (spirv-string "GLSL.std.450")))
               (inst 14 '(0 1))
               (inst 15 (append
                         (list (case stage [(compute) 5] [(vertex) 0] [else 4])
                               main)
                         (spirv-string shader-entry)
                         interface))
               (case stage
                 [(compute) (inst 16 (list main 17 shader-group-x 1 1))]
                 [(fragment) (inst 16 (list main 7))]
                 [else '()])
               (apply append (reverse decos))
               (apply append (reverse types))
               (apply append (reverse body)))]
             [bytes (make-bytevector (* 4 (length words)))])
        (let loop ([i 0] [ws words])
          (unless (null? ws)
            (bytevector-u32-native-set! bytes i (car ws))
            (loop (+ i 4) (cdr ws))))
        bytes))))

;;; ------------------------------------------------------------------ MSL
;;; Metal's language, as text for its compiler. It has no statement
;;; expressions, so each node of the tree prints as one assignment and a
;;; walk gives back what names its value. Every name is a number of ours,
;;; whatever the source called it: a name printed from the source could say
;;; anything, and a shader sees only what it was handed. Signed overflow is
;;; undefined there, so what wraps goes through uint.
;;; SDL's numbering: buffers count uniforms, then read-only ones, then
;;; read-write ones; textures count from 0, in every stage.

(define msl-ops
  '((fx+ . "int(uint(~a) + uint(~a))") (fx- . "int(uint(~a) - uint(~a))")
    (fx* . "int(uint(~a) * uint(~a))") (fxneg . "int(0u - uint(~a))")
    (fxquotient . "~a / ~a")
    (fxnot . "~~~a") (fxand . "~a & ~a") (fxior . "~a | ~a")
    (fxxor . "~a ^ ~a")
    (fxsll . "int(uint(~a) << uint(~a))")
    (fxsrl . "int(uint(~a) >> uint(~a))") (fxsra . "~a >> ~a")
    (fx= . "~a == ~a") (fx< . "~a < ~a") (fx> . "~a > ~a")
    (fx<= . "~a <= ~a") (fx>= . "~a >= ~a")
    (fl= . "~a == ~a") (fl< . "~a < ~a") (fl> . "~a > ~a")
    (fl<= . "~a <= ~a") (fl>= . "~a >= ~a")
    (fl+ . "~a + ~a") (fl- . "~a - ~a") (fl* . "~a * ~a") (fl/ . "~a / ~a")
    (flneg . "-~a") (not . "!~a")
    (fixnum->flonum . "float(~a)") (flonum->fixnum . "int(~a)")
    (flabs . "fabs(~a)") (flfloor . "floor(~a)") (flceiling . "ceil(~a)")
    (flround . "rint(~a)") (flsqrt . "sqrt(~a)")
    (flsin . "sin(~a)") (flcos . "cos(~a)")
    (flmin . "min(~a, ~a)") (flmax . "max(~a, ~a)")
    (fxumin . "int(min(uint(~a), uint(~a)))")))

(define (msl-op name args)
  (let ([o (assq name msl-ops)])
    (unless o (shader-error "no MSL for ~a" name))
    (apply format (cdr o) args)))

(define (msl-type t)
  (case t
    [(fixnum) "int"]
    [(flonum) "float"]
    [(boolean) "bool"]
    [else (shader-error "no value of type ~a" t)]))

(define (msl-const type x)
  (case type
    [(fixnum) (format "int(~au)" (logand x #xffffffff))]
    [(flonum) (format "as_type<float>(~au)" (shader-float-bits x))]
    [else (if x "true" "false")]))

(define (shader-msl stage coords params tree)
  (define out (open-output-string))
  (define next 0)
  (define names (make-eqv-hashtable))     ; a tree's id or a parameter's name
  (define (line . parts)
    (for-each (lambda (s) (display s out)) parts)
    (newline out))
  (define (fresh!)
    (set! next (+ next 1))
    (format "v~a" next))
  (define (name! id)
    (let ([v (fresh!)]) (hashtable-set! names id v) v))
  (define (name-of id) (hashtable-ref names id #f))
  (define (assign! type text)
    (let ([v (fresh!)])
      (line (msl-type type) " " v " = " text ";")
      v))
  (define (value t)
    (case (car t)
      [(const) (msl-const (cadr t) (caddr t))]
      [(var) (name-of (caddr t))]
      [(op)
       (assign! (cadr t) (msl-op (caddr t) (map value (cdddr t))))]
      [(let)
       (hashtable-set! names (cadr t) (value (caddr t)))
       (value (cadddr t))]
      [(seq) (fold-left (lambda (last f) (value f)) "" (cdr t))]
      [(if) (branch t)]
      [(loop) (bounded-loop t)]
      [(load)
       (assign! (cadr t)
                (format "~a[~a]" (name-of (caddr t)) (value (cadddr t))))]
      [(store)
       (let* ([i (value (caddr t))] [v (value (cadddr t))])
         (line (name-of (cadr t)) "[" i "] = " v ";")
         "")]
      [(fetch)
       (let* ([u (value (caddr t))] [v (value (cadddr t))]
              [level (value (list-ref t 5))])
         (assign! 'flonum
                  (format "~a.read(uint2(uint(~a), uint(~a)), uint(~a))[~a]"
                          (name-of (cadr t)) u v level (car (cddddr t)))))]
      [(emit-position)
       (let* ([x (value (cadr t))] [y (value (caddr t))]
              [i (value (cadddr t))])
         (line "stage.position = float4(" x ", " y ", 0.0, 1.0);")
         (line "stage.id = " i ";")
         "")]
      [(emit-color)
       (let* ([r (value (cadr t))] [g (value (caddr t))]
              [b (value (cadddr t))] [a (value (car (cddddr t)))])
         (line "color = float4(" r ", " g ", " b ", " a ");")
         "")]
      [else ""]))
  (define (branch t)
    (if (shader-select? t)
        (assign! (cadr t) (format "~a ? ~a : ~a" (value (caddr t))
                                  (value (cadddr t)) (value (car (cddddr t)))))
        (branch-on t)))
  (define (branch-on t)
    (let* ([c (value (caddr t))]
           [v (and (not (eq? (cadr t) 'void)) (fresh!))])
      (define (arm form)
        (let ([a (value form)])
          (when v (line v " = " a ";"))))
      (when v (line (msl-type (cadr t)) " " v ";"))
      (line "if (" c ") {")
      (arm (cadddr t))
      (line "} else {")
      (arm (car (cddddr t)))
      (line "}")
      (or v "")))
  ;; A round's new values are all worked out before any is set: a step may
  ;; name another variable, and means the value it had.
  (define (bounded-loop t)
    (let ([specs (cadddr t)] [count (fresh!)])
      (for-each (lambda (s)
                  (hashtable-set! names (car s)
                                  (assign! (cadr s) (value (caddr s)))))
                specs)
      (line "int " count " = 0;")
      (line "while (true) {")
      (line "if (" (value (car (cddddr t))) " || " count " >= " (caddr t)
            ") break;")
      (let ([news (map (lambda (s) (assign! (cadr s) (value (cadddr s))))
                       specs)])
        (for-each (lambda (s v) (line (name-of (car s)) " = " v ";"))
                  specs news))
      (line count " += 1;")
      (line "}")
      (value (cadr (cddddr t)))))
  (let* ([uniforms (shader-uniforms stage params)]
         [slots (if (null? uniforms) 0 1)]
         [reads (filter (lambda (p)
                          (and (memq (cadr p) '(fx-buffer fl-buffer))
                               (null? (cddr p))))
                        params)]
         [args '()]
         [read-n 0]
         [write-n 0]
         [tex-n 0])
    (define (arg! . parts) (set! args (cons (apply string-append parts) args)))
    ;; Metal's default is fast math, which takes (a + b) - a for b
    (line "#pragma METAL fp math_mode(safe)")
    (line "#include <metal_stdlib>")
    (line "using namespace metal;")
    (unless (null? uniforms)
      (line "struct Uniforms {")
      (let loop ([us uniforms] [k 0])
        (unless (null? us)
          (line (msl-type (cadr (car us))) " m" k ";")
          (loop (cdr us) (+ k 1))))
      (line "};")
      (arg! "constant Uniforms& uniforms [[buffer(0)]]"))
    (line "struct Stage {")
    (line "float4 position [[position]];")
    (line "int id [[user(locn0)]] [[flat]];")
    (line "};")
    (for-each
     (lambda (p)
       (case (cadr p)
         [(fx-buffer fl-buffer)
          (let ([type (if (eq? (cadr p) 'fx-buffer) "int" "float")]
                [v (name! (car p))])
            (if (null? (cddr p))
                (begin
                  (arg! "device const " type "* " v " [[buffer("
                        (number->string (+ slots read-n)) ")]]")
                  (set! read-n (+ read-n 1)))
                (begin
                  (arg! "device " type "* " v " [[buffer("
                        (number->string (+ slots (length reads) write-n))
                        ")]]")
                  (set! write-n (+ write-n 1)))))]
         [(texture)
          (arg! "texture2d<float> " (name! (car p)) " [[texture("
                (number->string tex-n) ")]]")
          (set! tex-n (+ tex-n 1))]))
     params)
    (let ([given (string-join (reverse args) ", ")]
          [with (if (null? args) "" ", ")])
      (case stage
        [(compute)
         (line "kernel void " shader-entry "(uint3 cell \
                [[thread_position_in_grid]]" with given ") {")
         (hashtable-set! names (car coords) (assign! 'fixnum "int(cell.x)"))
         (hashtable-set! names (cadr coords) (assign! 'fixnum "int(cell.y)"))]
        [(vertex)
         (line "vertex Stage " shader-entry "(uint vertex_at [[vertex_id]], \
                uint instance_at [[instance_id]]" with given ") {")
         (line "Stage stage;")
         (hashtable-set! names (car coords)
                         (assign! 'fixnum "int(vertex_at)"))
         (hashtable-set! names (cadr coords)
                         (assign! 'fixnum "int(instance_at)"))]
        [else
         (line "fragment float4 " shader-entry "(Stage stage [[stage_in]]"
               with given ") {")
         (line "float4 color = float4(0.0);")
         (hashtable-set! names (car coords)
                         (assign! 'flonum "stage.position.x"))
         (hashtable-set! names (cadr coords)
                         (assign! 'flonum "stage.position.y"))
         (hashtable-set! names (caddr coords)
                         (assign! 'fixnum "stage.id"))]))
    (let loop ([us uniforms] [k 0])
      (unless (null? us)
        (hashtable-set! names (car (car us))
                        (assign! (cadr (car us))
                                 (format "uniforms.m~a" k)))
        (loop (cdr us) (+ k 1))))
    (value tree)
    (case stage
      [(vertex) (line "return stage;")]
      [(fragment) (line "return color;")]
      [else (void)])
    (line "}")
    (get-output-string out)))

;;; ------------------------------------------------------------------ shaders

;; (code . price) of a shader's source, for this machine's back end.
(define (shader-compile stage coords params forms)
  (let ([tree (shader-lower stage coords params forms)])
    (cons (if (eq? shader-target 'msl)
              (string->utf8 (shader-msl stage coords params tree))
              (shader-spirv stage coords params tree))
          (shader-tree-price tree))))

;; The shader's source as its tree, for anyone who wants to look.
(define (shader-tree s)
  (shader-lower (shader-stage s) (shader-coords s) (shader-params s)
                (shader-source s)))

(define-syntax shader-define
  (lambda (x)
    (syntax-case x ()
      [(_ stage (name . coords) params form ...)
       (let ([compiled (shader-compile (datum stage) (datum coords)
                                       (datum params) (datum (form ...)))])
         (with-syntax ([code (datum->syntax #'name (car compiled))]
                       [price (datum->syntax #'name (cdr compiled))])
           #'(define name
               (make-shader 'name 'stage 'coords 'params '(form ...)
                            'code price))))])))

(define-syntax define-compute-shader
  (syntax-rules ()
    [(_ head params form ...) (shader-define compute head params form ...)]))
(define-syntax define-vertex-shader
  (syntax-rules ()
    [(_ head params form ...) (shader-define vertex head params form ...)]))
(define-syntax define-fragment-shader
  (syntax-rules ()
    [(_ head params form ...) (shader-define fragment head params form ...)]))
