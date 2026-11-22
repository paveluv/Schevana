;;; (schevana palettes catppuccin) — the Catppuccin palette.

(library (schevana palettes catppuccin)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette catppuccin "Catppuccin"
     '(bg-0 #x181825
       bg-1 #x1e1e2e
       bg-2 #x252537
       bg-3 #x313244
       text #xcdd6f4
       text-dim #xbac2de
       text-faint #x6c7086
       accent #x89b4fa
       accent-2 #xcba6f7
       red #xf38ba8
       orange #xfab387
       yellow #xf9e2af
       green #xa6e3a1
       cyan #x89dceb
       teal #x94e2d5
       magenta #xf5c2e7
       desktop-top #x1e1e2e
       desktop-bottom #x302845
       watermark #xffffff
       panel #x11111b))))
