;;; core1/ffi.ss — core1's own C: FreeType's glyphs, fontconfig's files
;;; that hold them, and the C library's sockets. Bound with define-foreign,
;;; which core0 gives core1 (src/core0/ffi.ss); none of it reaches the world.

(define libfreetype
  (load-first-library
   '("libfreetype.so.6" "libfreetype.so" "libfreetype.6.dylib"
     "libfreetype.dylib" "freetype.dll")))

(define libfontconfig
  (load-first-library
   '("libfontconfig.so.1" "libfontconfig.so" "libfontconfig.1.dylib"
     "libfontconfig.dylib" "fontconfig.dll")))

;; The C library's sockets come with what's loaded: only src/core1/socket.ss
;; uses them.

(define-foreign c-socket "socket" (int int int) int)
(define-foreign c-bind "bind" (int uptr unsigned-32) int)
(define-foreign c-listen "listen" (int int) int)
(define-foreign c-accept "accept" (int uptr uptr) int)
(define-foreign c-connect "connect" (int uptr unsigned-32) int)
(define-foreign c-shutdown "shutdown" (int int) int)
(define-foreign c-recv "recv" (int u8* size_t int) ssize_t)
(define-foreign c-send "send" (int u8* size_t int) ssize_t)
(define-foreign c-poll "poll" (uptr unsigned-long int) int)
(define-foreign c-signal "signal" (int uptr) uptr)

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
