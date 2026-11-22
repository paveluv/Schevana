;;; (schevana ffi) — how Schevana binds C: define-foreign, the shared
;;; library a binding comes from, and the few calls of the C library's
;;; that more than one piece makes. Each piece that talks to C binds its
;;; own with these: (schevana sdl) SDL3's, (schevana socket) the
;;; sockets'.

(library (schevana ffi)
  (export
    load-first-library define-foreign define-foreign/collect-safe
    c-clock-gettime c-close c-string->string)
  (import (chezscheme) (schevana base))

  (library-layer foundation)

  (define (load-first-library names)
    (let loop ([ns names])
      (cond
        [(null? ns)
         (errorf 'load-first-library "could not load any of ~s" names)]
        [(guard (c [#t #f]) (load-shared-object (car ns)) #t) (car ns)]
        [else (loop (cdr ns))])))

  ;; The C library's calls are the process's own: found once the process
  ;; is loaded as a shared object, which every binding made here waits
  ;; for.
  (define ffi-process (load-shared-object #f))

  ;; Like foreign-procedure, but `double` arguments accept any real number,
  ;; and `bool` is C's one-byte bool (SDL3's) as #t or #f: Chez's boolean is
  ;; an int, whose upper bytes a C bool leaves undefined. Only core0 and
  ;; core1 call them: workers run worklets, which cannot name them.
  ;; collect-safe: a call that blocks, given foreign memory only, during
  ;; which a collection another thread needs does not wait for it.
  (define-syntax define-foreign-as
    (lambda (x)
      (define (is? t name) (eq? (syntax->datum t) name))
      (define (c-type t) (if (is? t 'bool) #'unsigned-8 t))
      (syntax-case x ()
        [(_ how name cname (type ...) ret)
         (with-syntax ([(arg ...) (generate-temporaries #'(type ...))])
           (with-syntax ([(conv ...)
                          (map (lambda (t a)
                                 (cond [(is? t 'double) #`(inexact #,a)]
                                       [(is? t 'bool) #`(if #,a 1 0)]
                                       [else a]))
                               #'(type ...) #'(arg ...))]
                         [(ctype ...) (map c-type #'(type ...))]
                         [cret (c-type #'ret)])
             ;; the foreign procedure is made as the library loads, and
             ;; so held as a made value: name carries nothing
             #`(begin
                 (define-made f
                   (begin
                     ffi-process   ; before any binding is made
                     #,(if (is? #'how 'collect-safe)
                           #'(foreign-procedure __collect_safe cname
                                                (ctype ...) cret)
                           #'(foreign-procedure cname (ctype ...) cret))))
                 (define (name arg ...)
                   #,(if (is? #'ret 'bool)
                         #'(not (fx= 0 (f conv ...)))
                         #'(f conv ...))))))])))

  (define-syntax define-foreign
    (syntax-rules () [(_ . spec) (define-foreign-as plain . spec)]))
  (define-syntax define-foreign/collect-safe
    (syntax-rules () [(_ . spec) (define-foreign-as collect-safe . spec)]))

  (define-foreign c-clock-gettime "clock_gettime" (int uptr) int)
  (define-foreign c-close "close" (int) int)

  (define (c-string->string ptr)
    (if (= ptr 0)
        ""
        (let ([n (let loop ([i 0])
                   (if (= 0 (foreign-ref 'unsigned-8 ptr i))
                       i
                       (loop (+ i 1))))])
          (let ([bv (make-bytevector n)])
            (do ([i 0 (+ i 1)]) ((= i n))
              (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 ptr i)))
            (utf8->string bv))))))
