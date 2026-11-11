;;; kits/twin.ss — a shader as a Scheme procedure, its tree's second back end:
;;; slow and exact. Call a shader at the REPL for one pixel and see what it
;;; gives. Buffers are bytevectors, a texture a procedure of u, v, channel and
;;; level.

(define (twin-wrap v)
  (let ([x (logand v #xffffffff)])
    (if (>= x #x80000000) (- x #x100000000) x)))

(define (twin-fl->fx x)
  (if (and (fl< -2147483648.0 x) (fl< x 2147483648.0))
      (flonum->fixnum (fltruncate x))
      0))

(define (twin-fx-ref b i)
  (if (fx< -1 i (fxquotient (bytevector-length b) 4))
      (bytevector-s32-native-ref b (fx* 4 i))
      0))

(define (twin-fl-ref b i)
  (if (fx< -1 i (fxquotient (bytevector-length b) 4))
      (bytevector-ieee-single-native-ref b (fx* 4 i))
      0.0))

(define (twin-fx-set! b i v)
  (when (fx< -1 i (fxquotient (bytevector-length b) 4))
    (bytevector-s32-native-set! b (fx* 4 i) v)))

(define (twin-fl-set! b i v)
  (when (fx< -1 i (fxquotient (bytevector-length b) 4))
    (bytevector-ieee-single-native-set! b (fx* 4 i) v)))

(define (twin-var id)
  (if (symbol? id) id (string->symbol (format "v~a" id))))

(define (twin-op name args)
  (let ([a (and (pair? args) (car args))]
        [b (and (pair? args) (pair? (cdr args)) (cadr args))])
    (case name
      [(fx+) `(twin-wrap (+ ,a ,b))]
      [(fx-) `(twin-wrap (- ,a ,b))]
      [(fx*) `(twin-wrap (* ,a ,b))]
      [(fxneg) `(twin-wrap (- ,a))]
      [(fxnot) `(twin-wrap (lognot ,a))]
      [(fxand) `(logand ,a ,b)]
      [(fxior) `(logor ,a ,b)]
      [(fxxor) `(logxor ,a ,b)]
      [(fxsll) `(twin-wrap (ash ,a ,b))]
      [(fxsrl) `(twin-wrap (ash (logand ,a #xffffffff) (- ,b)))]
      [(fxsra) `(ash ,a (- ,b))]
      [(fxquotient) `(twin-wrap (quotient ,a ,b))]
      [(fxumin)
       `(twin-wrap (min (logand ,a #xffffffff) (logand ,b #xffffffff)))]
      [(fl+ fl- fl* fl/ flmin flmax)
       `(flsingle (,name ,a ,b))]
      [(flneg) `(fl- ,a)]
      [(flabs flfloor flceiling flround flsqrt)
       `(flsingle (,name ,a))]
      [(flsin) `(flsingle (flsin ,a))]
      [(flcos) `(flsingle (flcos ,a))]
      [(fixnum->flonum) `(flsingle (fixnum->flonum ,a))]
      [(flonum->fixnum) `(twin-fl->fx ,a)]
      [(not) `(not ,a)]
      [else (cons name args)])))

;; Forms worked out left to right, as the language has them, and then what k
;; makes of their values: Chez's order for a call's arguments is its own.
(define (twin-in-order forms k)
  (let ([names (map (lambda (f) (if (pair? f) (gensym) f)) forms)])
    `(let* ,(filter (lambda (b) (pair? (cadr b))) (map list names forms))
       ,(k names))))

(define (twin-form t)
  (case (car t)
    ;; a float as the device has it, 32 bits
    [(const) (let ([v (caddr t)]) (if (flonum? v) (flsingle v) v))]
    [(var) (twin-var (caddr t))]
    [(op)
     (twin-in-order (map twin-form (cdddr t))
                    (lambda (args) (twin-op (caddr t) args)))]
    [(let)
     `(let ([,(twin-var (cadr t)) ,(twin-form (caddr t))])
        ,(twin-form (cadddr t)))]
    [(seq) `(begin ,@(map twin-form (cdr t)))]
    [(if)
     `(if ,(twin-form (caddr t))
          ,(twin-form (cadddr t))
          ,(twin-form (car (cddddr t))))]
    [(loop)
     (let ([specs (cadddr t)])
       (twin-in-order
        (map (lambda (s) (twin-form (caddr s))) specs)
        (lambda (inits)
          `(let shader-loop
               ([shader-count 0]
                ,@(map (lambda (s i) (list (twin-var (car s)) i))
                       specs inits))
             (if (or ,(twin-form (car (cddddr t)))
                     (>= shader-count ,(caddr t)))
                 ,(twin-form (cadr (cddddr t)))
                 ,(twin-in-order
                   (map (lambda (s) (twin-form (cadddr s))) specs)
                   (lambda (steps)
                     `(shader-loop (+ shader-count 1) ,@steps))))))))]
    [(load)
     `(,(if (eq? (cadr t) 'flonum) 'twin-fl-ref 'twin-fx-ref)
       ,(caddr t) ,(twin-form (cadddr t)))]
    [(store)
     (let ([v (cadddr t)])
       (twin-in-order
        (list (twin-form (caddr t)) (twin-form v))
        (lambda (iv)
          `(,(if (eq? (shader-type v) 'flonum) 'twin-fl-set! 'twin-fx-set!)
            ,(cadr t) ,@iv))))]
    [(fetch)
     (twin-in-order
      (map twin-form (list (caddr t) (cadddr t) (list-ref t 5)))
      (lambda (uvl)
        `(,(cadr t) ,(car uvl) ,(cadr uvl) ,(car (cddddr t)) ,(caddr uvl))))]
    [(emit-position emit-color)
     (twin-in-order (map twin-form (cdr t))
                    (lambda (vs) `(set! shader-out (list ,@vs))))]
    [else '(void)]))

(define twin-procedures (make-weak-eq-hashtable))

;; The shader as a procedure of its coordinates and parameters, hidden
;; uniforms first in a compute shader's: => what it emitted, as a list. A
;; buffer's length is its bytevector's, as the device's is its buffer's.
(define (twin-procedure s)
  (or (hashtable-ref twin-procedures s #f)
      (let* ([stage (shader-stage s)]
             [hidden (if (eq? stage 'compute) '(shader-w shader-h) '())]
             [buffers (filter (lambda (p)
                                (memq (cadr p) '(fx-buffer fl-buffer)))
                              (shader-params s))]
             [f (eval
                 `(lambda (,@(shader-coords s) ,@hidden
                           ,@(map car (shader-params s)))
                    (let (,@(map (lambda (p)
                                   `[,(shader-words (car p))
                                     (fxquotient (bytevector-length ,(car p))
                                                 4)])
                                 buffers)
                          [shader-out #f])
                      ,(twin-form (shader-tree s))
                      shader-out)))])
        (hashtable-set! twin-procedures s f)
        f)))
