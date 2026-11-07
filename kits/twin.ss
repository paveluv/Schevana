;;; kits/twin.ss — a shader as a Scheme procedure, its tree's second back end:
;;; slow and exact. Call a shader at the REPL for one pixel and see what it
;;; gives. Buffers are bytevectors, a texture a procedure of u, v and channel.

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
      [(fxrem) `(remainder ,a ,b)]
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

(define (twin-form t)
  (case (car t)
    [(const) (caddr t)]
    [(var) (twin-var (caddr t))]
    [(op) (twin-op (caddr t) (map twin-form (cdddr t)))]
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
       `(let shader-loop
            ([shader-count 0]
             ,@(map (lambda (s)
                      (list (twin-var (car s))
                            (twin-form (caddr s))))
                    specs))
          (if (or ,(twin-form (car (cddddr t)))
                  (>= shader-count ,(caddr t)))
              ,(twin-form (cadr (cddddr t)))
              (shader-loop
               (+ shader-count 1)
               ,@(map (lambda (s) (twin-form (cadddr s))) specs)))))]
    [(load)
     `(,(if (eq? (cadr t) 'flonum) 'twin-fl-ref 'twin-fx-ref)
       ,(caddr t) ,(twin-form (cadddr t)))]
    [(store)
     (let ([v (cadddr t)])
       `(,(if (eq? (shader-type v) 'flonum) 'twin-fl-set! 'twin-fx-set!)
         ,(cadr t) ,(twin-form (caddr t)) ,(twin-form v)))]
    [(fetch)
     `(,(cadr t) ,(twin-form (caddr t)) ,(twin-form (cadddr t))
       ,(car (cddddr t)))]
    [(emit-position)
     `(set! shader-out (list ,@(map twin-form (cdr t))))]
    [(emit-color)
     `(set! shader-out (list ,@(map twin-form (cdr t))))]
    [else '(void)]))

(define twin-procedures (make-weak-eq-hashtable))

;; The shader as a procedure of its coordinates and parameters, hidden
;; uniforms first in a compute shader's: => what it emitted, as a list.
(define (twin-procedure s)
  (or (hashtable-ref twin-procedures s #f)
      (let* ([stage (shader-stage s)]
             [hidden (if (eq? stage 'compute) '(shader-w shader-h) '())]
             [f (eval
                 `(lambda (,@(shader-coords s) ,@hidden
                           ,@(map car (shader-params s)))
                    (let ([shader-out #f])
                      ,(twin-form (shader-tree s))
                      shader-out)))])
        (hashtable-set! twin-procedures s f)
        f)))
