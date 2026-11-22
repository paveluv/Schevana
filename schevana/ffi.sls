;;; (schevana ffi) — how Schevana binds C: define-foreign, loading the
;;; shared library a binding comes from, and the few C library calls that
;;; more than one piece makes. Each piece that talks to C binds its own
;;; calls with these: (schevana sdl) binds SDL3's, (schevana socket) the
;;; sockets'.

(library (schevana ffi)
  (export
    load-first-library define-foreign define-foreign/collect-safe
    c-clock-gettime c-close c-string->string)
  (import (chezscheme) (schevana base))

  (library-layer foundation)

  ;; The folders where, on a Mac, a library given by its bare name is also
  ;; looked for: those DYLD_FALLBACK_LIBRARY_PATH lists, then the package
  ;; managers' folders (Homebrew's on Apple silicon and on Intel, then
  ;; MacPorts'). The loader itself looks only in /usr/local/lib and
  ;; /usr/lib, and the variable, set outside, doesn't reach a process
  ;; started through /usr/bin/env or /bin/sh, because macOS drops it on the
  ;; way.
  (define (ffi-mac-folders)
    (append (let ([v (getenv "DYLD_FALLBACK_LIBRARY_PATH")])
              (if v (remp (lambda (d) (string=? d "")) (string-split v #\:))
                  '()))
            '("/opt/homebrew/lib" "/usr/local/lib" "/opt/local/lib")))

  ;; Loads the first of names (a library's file names on the various
  ;; platforms) that loads, and returns it. It tries each name as given,
  ;; then, on a Mac, each bare name in each of those folders.
  (define (load-first-library names)
    (let loop ([ns (if (platform-mac?)
                       (append names
                               (apply append
                                      (map (lambda (d)
                                             (map (lambda (n)
                                                    (string-append d "/" n))
                                                  (remp (lambda (n)
                                                          (string-contains-ci?
                                                           n "/"))
                                                        names)))
                                           (ffi-mac-folders))))
                       names)])
      (cond
        [(null? ns)
         (errorf 'load-first-library "could not load any of ~s" names)]
        [(guard (c [#t #f]) (load-shared-object (car ns)) #t) (car ns)]
        [else (loop (cdr ns))])))

  ;; The C library's procedures are the process's own: they are found once
  ;; the process is loaded as a shared object, which every binding made
  ;; here waits for.
  (define ffi-process (load-shared-object #f))

  ;; Like foreign-procedure, except that `double` arguments accept any real
  ;; number, and `bool` is C's one-byte bool (SDL3's), passed and returned
  ;; as #t or #f: Chez's boolean is an int, whose upper bytes a C bool
  ;; leaves undefined. Only core0 and core1 call these bindings: workers run
  ;; worklets, which cannot name them. collect-safe is for a call that
  ;; blocks and is given only foreign memory: while it runs, a collection
  ;; that another thread needs does not wait for it.
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
             ;; the foreign procedure is made as the library loads, so
             ;; it is held as a made value, and name carries nothing
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
