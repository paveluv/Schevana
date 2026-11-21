;;; (schevana fontconfig) — fontconfig's bindings: the file that holds a
;;; family's font, as fontconfig names its calls.

(library (schevana fontconfig)
  (export
    fc-config-get-current fc-get-version fc-name-parse fc-config-substitute
    fc-default-substitute fc-font-match fc-pattern-get-string
    fc-pattern-get-integer fc-pattern-destroy)
  (import (chezscheme)
          (schevana ffi))

  (define libfontconfig
    (load-first-library
     '("libfontconfig.so.1" "libfontconfig.so" "libfontconfig.1.dylib"
       "libfontconfig.dylib" "fontconfig.dll")))

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
  (define-foreign fc-pattern-destroy "FcPatternDestroy" (uptr) void))
