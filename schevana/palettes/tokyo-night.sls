;;; (schevana palettes tokyo-night) — the Tokyo Night palette, the built-in
;;; one. Its colors are base-colors in (schevana core theme), so the world has
;;; colors even with no theme files, and this palette gives none of its own.
;;; Its other colors are derived from those, as they are for every palette.

(library (schevana palettes tokyo-night)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette tokyo-night "Tokyo Night")))
