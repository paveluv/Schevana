;;; (schevana palettes nord) — the Nord palette.

(library (schevana palettes nord)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette nord "Nord"
     '(bg-0 #x242933
       bg-1 #x2e3440
       bg-2 #x353c4a
       bg-3 #x3b4252
       text #xeceff4
       text-dim #xd8dee9
       text-faint #x6d7a96
       accent #x88c0d0
       accent-2 #xb48ead
       red #xbf616a
       orange #xd08770
       yellow #xebcb8b
       green #xa3be8c
       cyan #x8fbcbb
       teal #x8fbcbb
       magenta #xb48ead
       desktop-top #x252a34
       desktop-bottom #x3a4660
       watermark #xffffff
       panel #x1f232b))))
