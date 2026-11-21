;;; (schevana core0 mail) — what core0's thread and the world's hand each
;;; other: the clock, the boxes, the wakes (src/core0/mail.ss). It exports what
;;; the pieces above it and the layers above core0 use of it.

(library (schevana core0 mail)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana sdl))

  (include-sources "src/core0/mail.ss")

  (define-exports mail-exports
    (export (world)
      core0-clock-ns now-ns *core0-jobs* core0-put! core0-take! core0-post!
      (settable *core0-forked*) core0-forked? *core0-world-mutex*
      *core0-ready* (settable *core0-woken*) core0-world-wake!
      core0-world-wait! core0-ms core0-wake! (settable *core0-facts*)
      core0-frame-ns core0-display *core0-input-ns* *core0-input-pumped*
      *core0-input-wl* core0-input-set! core0-input-take!)))
