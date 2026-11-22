;;; (schevana palettes phosphor) — the Phosphor palette. A green monitor: one
;;; phosphor, so every hue is a brightness of green, except alarms, which glow
;;; amber as the other phosphor did.

(library (schevana palettes phosphor)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette phosphor "Phosphor"
     '(bg-0 #x000000
       bg-1 #x041006
       bg-2 #x0a1c0c
       bg-3 #x112914
       text #x3dff6e
       text-dim #x2bb84f
       text-faint #x1a7a36
       accent #x7dffa0
       accent-2 #xffb000
       red #xff8f3f
       orange #xffb347
       yellow #xd4ff5c
       green #x3dff6e
       cyan #x8cffe0
       teal #x5fe3b3
       magenta #xb6ff9e
       desktop-top #x000000
       desktop-bottom #x06260f
       watermark #x3dff6e
       panel #x000000
       panel-text #x3dff6e
       panel-dim #x1f9a44
       panel-hover #x0e3a18))))
