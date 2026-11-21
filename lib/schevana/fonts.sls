;;; (schevana fonts) — fonts and their glyphs (src/core1/font.ss). It exports
;;; what the pieces above it and the world use of it.

(library (schevana fonts)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana ffi)
          (schevana shader) (schevana freetype) (schevana fontconfig)
          (schevana core0) (schevana theme-table))

  (library-layer core)

  (include-sources "src/core1/font.ss")

  (define-exports fonts-exports
    (export (world)
      font-file-upem font-file-pages font-library-versions font-family
      font-weight font-size font-crisp? font-sized make-font* *font-specs*
      font get-font font-advance font-ascent font-descent font-line-height
      font-char-width font-ready text-width glyph-row-words glyph-row-u
      glyph-row-v glyph-row-w glyph-row-h glyph-row-left glyph-row-top
      glyph-row-character *glyph-table* *glyph-count*
      (settable *glyph-table-dirty?*) *atlas-y* *atlas-row*
      (settable *atlas-pieces*) atlas-place! *stipple-tiles* glyph-row-ref
      font-glyph-pages font-glyph)))
