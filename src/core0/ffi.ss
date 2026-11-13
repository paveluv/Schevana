;;; core0/ffi.ss — where Schevana talks to C: how a binding is made, and
;;; the few that core0 and core1 share.
;;;
;;; SDL3 gives us a window, input events, a clipboard and the GPU: only
;;; core0 names it (src/core0/sdl.ss). Core1 binds its own C (FreeType,
;;; fontconfig, sockets) in src/core1/ffi.ss, with define-foreign, which
;;; core0 gives it. Everything above is plain Scheme: the folders draw,
;;; measure and save through the core's procedures (tests/sources.ss).

(define (load-first-library names)
  (let loop ([ns names])
    (cond
      [(null? ns) (errorf 'load-first-library "could not load any of ~s" names)]
      [(guard (c [#t #f]) (load-shared-object (car ns)) #t) (car ns)]
      [else (loop (cdr ns))])))

(define libsdl
  (load-first-library
   '("libSDL3.so.0" "libSDL3.so" "libSDL3.0.dylib" "libSDL3.dylib"
     "SDL3.dll")))

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
           #`(define name
               (let ([f #,(if (is? #'how 'collect-safe)
                              #'(foreign-procedure __collect_safe cname
                                                   (ctype ...) cret)
                              #'(foreign-procedure cname (ctype ...) cret))])
                 (lambda (arg ...)
                   #,(if (is? #'ret 'bool)
                         #'(not (fx= 0 (f conv ...)))
                         #'(f conv ...)))))))])))

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
                 (if (= 0 (foreign-ref 'unsigned-8 ptr i)) i (loop (+ i 1))))])
        (let ([bv (make-bytevector n)])
          (do ([i 0 (+ i 1)]) ((= i n))
            (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 ptr i)))
          (utf8->string bv)))))

;;; ------------------------------------------------------------------ SDL
;;; SDL's two calls any thread may make: the clock, and how many threads
;;; the machine runs at once. The rest of SDL is core0's own
;;; (src/core0/sdl.ss).

(define-foreign sdl-get-ticks-ns "SDL_GetTicksNS" () unsigned-64)
(define-foreign sdl-get-num-logical-cpu-cores "SDL_GetNumLogicalCPUCores" ()
  int)
