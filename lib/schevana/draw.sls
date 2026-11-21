;;; (schevana draw) — drawing: colors, shapes, text, paints, and the records
;;; they make (src/core1/gfx.ss). It exports what the pieces above it and the
;;; world use of it.

(library (schevana draw)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana shader)
          (schevana core0) (schevana recorder) (schevana platform)
          (schevana theme-table) (schevana processes) (schevana gpu)
          (schevana fonts))

  (include-sources "src/core1/gfx.ss")

  (define-exports draw-exports
    (export (world)
      pi *canvas-w* *canvas-h* *scale* *canvas-ratio* *canvas-pw* *canvas-ph*
      theme-changed! canvas-create-pixels! canvas-create! canvas-pixel-width
      canvas-pixel-height rgb alpha stipple stipple? linear-gradient
      radial-gradient color-rgba mix color-word rec-kind-polygon
      rec-kind-glyph rec-paint-gradient rec-paint-stipple rec-paint-image
      rec-gradient-radial rec-row-words rec-row-head rec-row-paint rec-row-x0
      rec-row-y0 rec-row-x1 rec-row-y1 rec-box-radius rec-box-line
      rec-segment-width rec-polygon-points rec-polygon-count rec-glyph-pen-x
      rec-glyph-pen-y rec-glyph-number rec-shadow-size gradient-row-kind
      gradient-row-x0 gradient-row-y0 gradient-row-x1 gradient-row-y1
      clip-row-words clip-row-x0 clip-row-y0 clip-row-x1 clip-row-y1
      clip-row-radius clip-row-parent clip-row-rx0 clip-row-ry0 clip-row-rx1
      clip-row-ry1 *rec-num* *rec-den* *rec-ox* *rec-oy* *rec-turn*
      *rec-labels* *rec-label-at* *rec-clip* *rec-cx0* *rec-cy0* *rec-cx1*
      *rec-cy1* rec-variant rec-begin! rec-runs rec-state-restore!
      record-list! show-list fill-box stroke-box fill-circle stroke-circle
      draw-line draw-polyline fill-polygon invert-box add-box draw-shadow
      draw-text draw-image define-paint fill-shader with-clip with-translation
      with-scale with-turn with-label draw-scale gfx-fragments rec-present!
      rec-preview! rec-past! drawing->bytes-then drawing->bytes)))
