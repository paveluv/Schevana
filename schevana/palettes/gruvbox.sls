;;; (schevana palettes gruvbox) — the Gruvbox palette.

(library (schevana palettes gruvbox)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette gruvbox "Gruvbox"
     '(bg-0 #x1d2021
       bg-1 #x282828
       bg-2 #x32302f
       bg-3 #x3c3836
       text #xebdbb2
       text-dim #xd5c4a1
       text-faint #x928374
       accent #x83a598
       accent-2 #xd3869b
       red #xfb4934
       orange #xfe8019
       yellow #xfabd2f
       green #xb8bb26
       cyan #x8ec07c
       teal #x8ec07c
       magenta #xd3869b
       desktop-top #x1d2021
       desktop-bottom #x473c2e
       watermark #xfbf1c7
       panel #x161819))))
