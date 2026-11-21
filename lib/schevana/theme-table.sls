;;; (schevana theme-table) — the settings in effect: the table (theme key)
;;; reads (src/core1/theme-table.ss). It exports what the pieces above it and
;;; the world use of it.

(library (schevana theme-table)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana boot))

  (library-layer core)

  (include-sources "src/core1/theme-table.ss")

  (define-exports theme-table-exports
    (export (world)
      (settable *theme*) (settable *main-theme*) theme-rule? theme-rule
      theme-unset call-with-theme theme theme-keys theme-part plist-has?
      plist-remove *theme-table-defaults* theme-table-default!
      (settable *pacer-trial*) pacer-knob)))
