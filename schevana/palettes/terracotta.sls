;;; (schevana palettes terracotta) — the Terracotta palette: desert clay. Sand
;;; for the paper, fired clay for the accent, an oasis for the second accent,
;;; cactus green, and dark clay for the bars.

(library (schevana palettes terracotta)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette terracotta "Terracotta"
     '(bg-0 #xf6ead9
       bg-1 #xf0dfc8
       bg-2 #xe5cba8
       bg-3 #xd6b48a
       text #x3b2416
       text-dim #x6b4a33
       text-faint #x997458
       accent #xab4b26
       accent-2 #x2f6f73
       red #xb8322a
       orange #xaf6124
       yellow #x906e10
       green #x537f32
       cyan #x257b8c
       teal #x2b7f6c
       magenta #xa64b86
       desktop-top #xe9c79a
       desktop-bottom #xb2632f
       watermark #x5a2e14
       panel #x3b2416
       panel-text #xf6ead9
       panel-dim #xcdb59c
       panel-hover #x553625))))
