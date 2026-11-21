;;; (schevana pacer) — when the world's ticks come, and what became of each
;;; frame (src/core1/pacer.ss). It exports what the pieces above it and the
;;; world use of it.

(library (schevana pacer)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana core0)
          (schevana recorder) (schevana platform) (schevana theme-table)
          (schevana processes) (schevana fonts) (schevana draw))

  (include-sources "src/core1/pacer.ss")

  (define-exports pacer-exports
    (export (world)
      *pacer-due* (settable *pacer-waits*) *pacer-frame-ns* *pacer-shown?*
      *pacer-latch* *pacer-lead* *pacer-counts* *pacer-aimed* *pacer-floor*
      *pacer-latch-phase* *pacer-depth* *pacer-made* *pacer-gpu-taught*
      *pacer-late-run* *pacer-late-chain* (settable *pacer-between?*)
      (settable *frame-ms*) (settable *frames-drawn*) (settable *frame-back*)
      frame-ring-rows frame-ring-words *frame-ring* *frame-ring-n*
      *frame-number* (settable *frame-draw-ns*) (settable *frame-publish-ns*)
      frame-number-set! frame-ticked! frame-input-came! frame-input-drop!
      frame-ring-add! frame-ring-set! pacer-waited! pacer-step-done!
      pacer-busy-ms pacer-peak-ms! pacer-rate pacer-ticks frame-turn-soon!
      pacer-wanted? pacer-frame-ns pacer-period pacer-start pacer-on-latch?
      pacer-latch! pacer-trial! pacer-margin pacer-drew!
      (settable *pacer-turn*) pacer-tick! pacer-frame-back! pacer-procs-ms
      pacer-wait-ms)))
