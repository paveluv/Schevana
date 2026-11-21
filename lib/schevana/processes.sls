;;; (schevana processes) — processes, errors, toasts, worklets, and what is
;;; asked of the loop: a frame, a call after a while (src/core1/proc.ss). It
;;; exports what the pieces above it and the world use of it.

(library (schevana processes)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana platform))

  (include-sources "src/core1/proc.ss")

  (define-exports processes-exports
    (export (world)
      in-engine? current-proc (settable *profile-span*) with-profile-span
      make-timeout-condition safe-call safely (settable *dirty*)
      request-frame! *frame-generation* request-redraw! *timers* after
      run-timers! *toasts* notify *last-error* report-error! proc proc?
      proc-id proc-name proc-state proc-ticks proc-started proc-wake *procs*
      (settable *reloading*) spawn procs find-proc kill! procs-ready?
      run-procs! sleep-ms proc-wait worklet-base-environment
      *worklet-environment* worklet? worklet-compile worklet
      (settable worklet-spread) define-worklet)))
