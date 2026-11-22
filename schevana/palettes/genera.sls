;;; (schevana palettes genera) — the Genera palette, after Symbolics Genera:
;;; black ink on white paper, with the panels in reverse video like Genera's
;;; mouse documentation line.

(library (schevana palettes genera)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette genera "Genera"
     '(bg-0 #xffffff
       bg-1 #xffffff
       bg-2 #xf0f0f0
       bg-3 #xd8d8d8
       text #x000000
       text-dim #x222222
       text-faint #x666666
       accent #x000000
       accent-2 #x444444
       red #x8b0000
       orange #x6b4400
       yellow #x5c5c00
       green #x1f5f1f
       cyan #x1f5566
       teal #x1f5f55
       magenta #x661f66
       desktop-top #xffffff
       desktop-bottom #xffffff
       watermark #x000000
       panel #x000000
       panel-text #xffffff
       panel-dim #xb4b4b4
       panel-hover #x383838))))
