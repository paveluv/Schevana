;;; (schevana palettes sunset) — the Sunset palette: dusk, a purple sky over an
;;; orange horizon. The desktop is a sunset from top to bottom, and the text
;;; is a warm ink on the violet of the night.

(library (schevana palettes sunset)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette sunset "Sunset"
     '(bg-0 #x1d1026
       bg-1 #x26152f
       bg-2 #x35203f
       bg-3 #x4a2d52
       text #xffe9d6
       text-dim #xe2b8a3
       text-faint #xa07e85
       accent #xff8c42
       accent-2 #xff5e8a
       red #xff5c5c
       orange #xffa347
       yellow #xffd166
       green #x9ad67a
       cyan #x74d3f2
       teal #x5ec8b0
       magenta #xe07be0
       desktop-top #x2a1540
       desktop-bottom #xff7b3d
       watermark #xffd9b0
       panel #x150a1c))))
