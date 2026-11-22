;;; (schevana palettes tokyo-night) — the Tokyo Night palette: the built-in
;;; one, base-colors in (schevana core theme), so that the world has its colors
;;; even with no theme files. Its other colors derive as every palette's do.

(library (schevana palettes tokyo-night)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) define-palette))

  (library-layer looks)

  (at-load
   (define-palette tokyo-night "Tokyo Night")))
