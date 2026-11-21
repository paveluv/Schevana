;;; (schevana theme) — how everything looks: styles, palettes, parts, the
;;; layers that fill the table drawing reads (src/core1/theme.ss). It exports
;;; what the pieces above it and the world use of it.

(library (schevana theme)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana theme-table)
          (schevana processes) (schevana fonts) (schevana draw)
          (schevana screen))

  (library-layer core)

  (include-sources "src/core1/theme.ss")

  ;; plain defines that their file assigns
  (assigned-variables default-theme color-keys)

  (define-exports theme-exports
    (export (world)
      *theme-version* (settable theme-save!) *style-name* *style-changes*
      *theme-overrides* *scale-setting* default-theme color-keys
      common-options theme-default *palettes* define-palette palettes
      palette-title palette-colors style style-name style-title style-settings
      *styles* define-style find-style styles current-style define-part
      color-default! theme-default! style-theme with-style with-place
      style-changes-of style-chain chain-ref honored? resolve-theme
      wm-chrome-changed! theme-font-rule chrome-height title-height
      frame-over* change-layers! theme-layers-set! set-style! set-theme!
      reset-style! override! theme-overrides set-scale! set-palette!
      reset-theme!)))
