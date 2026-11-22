;;; (schevana palettes sakura) — the Sakura palette. Cherry blossom: pale pink
;;; paper, plum ink, a deep pink accent and wisteria beside it; the desktop
;;; blossoms over a spring sky.

(library (schevana palettes sakura)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette sakura "Sakura"
     '(bg-0 #xfff7fa
       bg-1 #xfdeef3
       bg-2 #xf9dde6
       bg-3 #xf2c9d6
       text #x4a2b36
       text-dim #x7a5362
       text-faint #xa17e8a
       accent #xd03169
       accent-2 #x7c5cbf
       red #xd62839
       orange #xbb6c2e
       yellow #xa07900
       green #x468d51
       cyan #x2886a9
       teal #x268b7f
       magenta #xc13f9e
       desktop-top #xf7c7d6
       desktop-bottom #xdceefb
       watermark #x8c1d3f
       panel #xfbe4ec))))
