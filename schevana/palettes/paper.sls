;;; (schevana palettes paper) — the Paper palette.

(library (schevana palettes paper)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette paper "Paper"
     '(bg-0 #xfbfaf7
       bg-1 #xf4f2ee
       bg-2 #xe9e6df
       bg-3 #xdcd7ce
       text #x2b2a33
       text-dim #x4f4d5a
       text-faint #x8b8794
       accent #x3b6fd8
       accent-2 #x8a4fd0
       red #xd43f4d
       orange #xc96a12
       yellow #xa87b00
       green #x3d8a3a
       cyan #x1f88a8
       teal #x238a7a
       magenta #xb0399a
       desktop-top #xe9e5dd
       desktop-bottom #xc9d3e6
       watermark #x000000
       panel #xece9e3))))
