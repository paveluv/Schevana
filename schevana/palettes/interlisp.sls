;;; (schevana palettes interlisp) — the Interlisp palette, after Interlisp-D:
;;; black ink on white paper, as bits rather than as a console's tube shows
;;; them ((schevana palettes p4)). Its accent is the ink, so a default button
;;; under the pointer lightens to a gray of its own rather than darkening.

(library (schevana palettes interlisp)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette interlisp "Interlisp"
     '(bg-0 #xffffff
       bg-1 #xffffff
       bg-2 #xf0f0f0
       bg-3 #xd8d8d8
       text #x000000
       text-dim #x2a2a2a
       text-faint #x6a6a6a
       accent #x000000
       accent-2 #x555555
       primary-hover #x333333
       red #x8b0000
       orange #x6b4400
       yellow #x5c5c00
       green #x1f5f1f
       cyan #x1f5566
       teal #x1f5f55
       magenta #x661f66
       desktop-top #xffffff
       desktop-bottom #x000000
       watermark #x000000
       panel #xffffff))))
