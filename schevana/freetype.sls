;;; (schevana freetype) — FreeType's bindings, named as FreeType names
;;; them: a face from a file, its glyphs and their bitmaps. The structs
;;; FreeType fills are read by (schevana core fonts).

(library (schevana freetype)
  (export
    ft-init-freetype ft-library-version ft-new-face ft-set-char-size
    ft-set-transform ft-load-char ft-get-first-char ft-get-next-char)
  (import (chezscheme) (only (schevana base) library-layer)
          (only (schevana ffi) define-foreign load-first-library))

  (library-layer foundation)

  (define libfreetype
    (load-first-library
     '("libfreetype.so.6" "libfreetype.so" "libfreetype.6.dylib"
       "libfreetype.dylib" "freetype.dll")))

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
    (uptr unsigned-long uptr) unsigned-long))
