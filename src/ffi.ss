;;; ffi.ss — the only place where Schevana talks to C.
;;;
;;; SDL3 gives us a host window, input events, a clipboard and the GPU.
;;; FreeType gives us glyphs, and fontconfig the files that hold them.
;;; Everything above this file is plain Scheme, and only the core (src/)
;;; uses these bindings: the folders draw, measure and save through the
;;; core's procedures (tests/sources.ss checks it).

(define (load-first-library names)
  (let loop ([ns names])
    (cond
      [(null? ns) (errorf 'load-first-library "could not load any of ~s" names)]
      [(guard (c [#t #f]) (load-shared-object (car ns)) #t) (car ns)]
      [else (loop (cdr ns))])))

(define sdl-library-names
  '("libSDL3.so.0" "libSDL3.so" "libSDL3.0.dylib" "libSDL3.dylib" "SDL3.dll"))

;; A process loads one SDL for good, so a session that started with another
;; (SDL2, before the switch) cannot reload into this one.
(when (and (top-level-bound? 'libsdl) (not (member libsdl sdl-library-names)))
  (errorf 'reload! "this session runs ~a; quit and start Schevana again"
          libsdl))

(define libsdl (load-first-library sdl-library-names))

(define libfreetype
  (load-first-library
   '("libfreetype.so.6" "libfreetype.so" "libfreetype.6.dylib"
     "libfreetype.dylib" "freetype.dll")))

(define libfontconfig
  (load-first-library
   '("libfontconfig.so.1" "libfontconfig.so" "libfontconfig.1.dylib"
     "libfontconfig.dylib" "fontconfig.dll")))

;; The C library's sockets come with what's loaded: only src/host.ss uses them,
;; and it declares them below, after the macro.

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
(define-foreign c-socket "socket" (int int int) int)
(define-foreign c-bind "bind" (int uptr unsigned-32) int)
(define-foreign c-listen "listen" (int int) int)
(define-foreign c-accept "accept" (int uptr uptr) int)
(define-foreign c-connect "connect" (int uptr unsigned-32) int)
(define-foreign c-shutdown "shutdown" (int int) int)
(define-foreign c-recv "recv" (int u8* size_t int) ssize_t)
(define-foreign c-send "send" (int u8* size_t int) ssize_t)
(define-foreign c-close "close" (int) int)
(define-foreign c-poll "poll" (uptr unsigned-long int) int)
(define-foreign c-signal "signal" (int uptr) uptr)

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
;;; SDL's two calls any thread may make, so core1's: the clock, and how many
;;; threads the machine runs at once. The rest of SDL is core0's
;;; (src/host/sdl.ss).

(define-foreign sdl-get-ticks-ns "SDL_GetTicksNS" () unsigned-64)
(define-foreign sdl-get-num-logical-cpu-cores "SDL_GetNumLogicalCPUCores" ()
  int)

;;; ------------------------------------------------------------------ FreeType

(define-foreign ft-init-freetype "FT_Init_FreeType" (uptr) int)
(define-foreign ft-library-version "FT_Library_Version"
  (uptr uptr uptr uptr) void)
(define-foreign ft-new-face "FT_New_Face" (uptr string long uptr) int)
(define-foreign ft-set-char-size "FT_Set_Char_Size"
  (uptr long long unsigned unsigned) int)
(define-foreign ft-set-transform "FT_Set_Transform" (uptr uptr uptr) void)
(define-foreign ft-load-char "FT_Load_Char" (uptr unsigned-long int) int)
(define-foreign ft-get-first-char "FT_Get_First_Char"
  (uptr uptr) unsigned-long)
(define-foreign ft-get-next-char "FT_Get_Next_Char"
  (uptr unsigned-long uptr) unsigned-long)

;;; ----------------------------------------------------------------- fontconfig

(define-foreign fc-config-get-current "FcConfigGetCurrent" () uptr)
(define-foreign fc-get-version "FcGetVersion" () int)
(define-foreign fc-name-parse "FcNameParse" (string) uptr)
(define-foreign fc-config-substitute "FcConfigSubstitute"
  (uptr uptr int) int)
(define-foreign fc-default-substitute "FcDefaultSubstitute" (uptr) void)
(define-foreign fc-font-match "FcFontMatch" (uptr uptr uptr) uptr)
(define-foreign fc-pattern-get-string "FcPatternGetString"
  (uptr string int uptr) int)
(define-foreign fc-pattern-get-integer "FcPatternGetInteger"
  (uptr string int uptr) int)
(define-foreign fc-pattern-destroy "FcPatternDestroy" (uptr) void)
