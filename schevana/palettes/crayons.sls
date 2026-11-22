;;; (schevana palettes crayons) — the Crayons palette: a kindergarten's box of
;;; crayons on cream paper. The hues are the crayons, the bars are a
;;; chalkboard, and the desktop is a sky over grass.

(library (schevana palettes crayons)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette crayons "Crayons"
     '(bg-0 #xfffdf5
       bg-1 #xfff8e7
       bg-2 #xffefc9
       bg-3 #xffe3a3
       text #x2b2118
       text-dim #x5a4634
       text-faint #x9c8569
       accent #x1e6fe8
       accent-2 #x9b4dca
       red #xe4322b
       orange #xc26b11
       yellow #xa27c00
       green #x24935e
       cyan #x0089b4
       teal #x009185
       magenta #xde4490
       desktop-top #x7ec8ff
       desktop-bottom #x9ae66e
       watermark #xffffff
       panel #x2f4f3a
       panel-text #xfff8e7
       panel-dim #xb9c9bd
       panel-hover #x3f6b4e))))
