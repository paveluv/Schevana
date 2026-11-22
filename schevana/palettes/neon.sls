;;; (schevana palettes neon) — the Neon palette: downtown at night, with wet
;;; asphalt, a dark sky and the signs. Hot pink is the accent and electric
;;; cyan the second accent, with acid yellow and violet. The desktop glows
;;; purple from the streets below, and its λ is a pink sign.

(library (schevana palettes neon)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette neon "Neon"
     '(bg-0 #x07070f
       bg-1 #x0d0d1a
       bg-2 #x15152a
       bg-3 #x1f1f3a
       text #xe8e8ff
       text-dim #xb4b4d8
       text-faint #x6a6a92
       accent #xff2bd6
       accent-2 #x19e6ff
       red #xff3c5a
       orange #xff8a1f
       yellow #xf5ff3c
       green #x39ff8a
       cyan #x19e6ff
       teal #x2ad6c0
       magenta #xc04bff
       desktop-top #x05050c
       desktop-bottom #x2b0d45
       watermark #xff2bd6
       panel #x05050c
       panel-text #xe8e8ff
       panel-dim #x7a7aa8
       panel-hover #x1a1a33))))
