;;; (schevana palettes forest) — the Forest palette. Under the canopy: moss and
;;; bark, a stream, berries and foxglove, and sunlight through the leaves as
;;; the second accent.

(library (schevana palettes forest)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette forest "Forest"
     '(bg-0 #x0f1a14
       bg-1 #x15241b
       bg-2 #x1c3024
       bg-3 #x26402f
       text #xe3ecdf
       text-dim #xb5c7ad
       text-faint #x6f8a6c
       accent #xa3d977
       accent-2 #xe0a645
       red #xe06c5c
       orange #xe59a3e
       yellow #xe6c75a
       green #x6fcf6a
       cyan #x6bc8c3
       teal #x4fb39d
       magenta #xc58ad6
       desktop-top #x0b1410
       desktop-bottom #x1f3b2a
       watermark #xc8e6c0
       panel #x0b1410))))
