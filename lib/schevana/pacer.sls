;;; (schevana pacer) — when the world's ticks come, and what became of each
;;; frame (src/core1/pacer.ss). It exports what the pieces above it and the
;;; world use of it.

(library (schevana pacer)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana core0)
          (schevana recorder) (schevana platform) (schevana theme-table)
          (schevana processes) (schevana gpu) (schevana fonts) (schevana draw))

  (library-layer core)

  (include-sources "src/core1/pacer.ss")

  (define-exports pacer-exports
    (export (world)
      *pacer-due* (settable *pacer-waits*) *pacer-frame-ns* *pacer-shown?*
      *pacer-latch* *pacer-lead* *pacer-counts* *pacer-aimed* *pacer-floor*
      *pacer-latch-phase* *pacer-depth* *pacer-made* *pacer-gpu-taught*
      *pacer-late-run* *pacer-late-chain* (settable *pacer-between?*)
      *frame-ms* *frames-drawn* *frame-back* frame-ring-rows frame-ring-words
      *frame-ring* *frame-ring-n* *frame-number* frame-ticked!
      frame-input-came! frame-input-drop! pacer-waited! pacer-step-done!
      pacer-busy-ms pacer-peak-ms! pacer-rate pacer-ticks frame-turn-soon!
      pacer-wanted? pacer-frame-ns pacer-period pacer-start pacer-on-latch?
      pacer-trial! pacer-margin wm-tick! pacer-tick! pacer-procs-ms
      pacer-wait-ms record-world! record-safely render-frame!
      render-frames-back! render-answers! screen-bytes screen-bytes-then)))
