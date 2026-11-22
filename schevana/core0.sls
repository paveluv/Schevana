;;; (schevana core0) — core0, below the core, as the core has it: what core0
;;; gives core1, and core0-run!, which starts the world's thread and runs
;;; core0's loop. A state or a hook core0 sets is given as a view, which a
;;; set! refuses: core1, on a thread of its own, reads it and never sets
;;; it. What core0 gives the recorder alone is (schevana core0
;;; for-recorder)'s.

(library (schevana core0)
  (export
    ;; Constants, and procedures of their arguments alone: safe anywhere.
    core0-app-id gpu-atlas-side gpu-usage-sampler gpu-usage-target
    core0-flag-names core0-event-name gpu-show-run? gpu-run-gone?
    ;; The records the two share. Their procedures touch nothing else, so
    ;; what's safe is who holds the record: a thread writes only those it
    ;; holds, and a frame is the world's from gpu-frame-make, or
    ;; gpu-frames-back!, until gpu-publish!.
    ;; compiled shaders
    shader make-shader shader-name shader-stage shader-coords shader-params
    shader-source shader-code shader-price shader-target shader-entry
    shader-group-x shader-uniforms shader-words
    ;; lists, and the runs that show them; their recordings are the
    ;; recorder's alone
    gpu-list-id gpu-list-labels gpu-list-labels-set! gpu-list-recorded
    gpu-list-recorded-set! gpu-list-took gpu-list-took-set!
    ;; images, buffers and the calls that name them
    make-gpu-image gpu-image-id gpu-image-w gpu-image-h gpu-image-levels
    gpu-image-gone?-set! make-gpu-buffer* gpu-buffer-id gpu-buffer-size
    gpu-buffer-gone?-set! make-gpu-call gpu-call? gpu-call-shader
    ;; frames; what they write is the recorder's
    gpu-frame-make gpu-frame-table-set! gpu-frame-table-n-set!
    gpu-frame-pieces-set! gpu-frame-jobs-set! gpu-frame-computes-set!
    gpu-frame-mode-set! gpu-frame-in-flight-set! gpu-frame-number
    gpu-frame-shown?
    ;; What core0 says of itself, in variables it sets whole: another thread
    ;; reads each whole (Chez lets no thread see an object half made), but
    ;; not in step with the others, as ARM keeps no order between stores.
    *gpu-facts* *core0-mode* *core0-platform*
    ;; The same, read through procedures: the window's facts as core0's
    ;; step last read them, made again whole when they change; what became
    ;; of each frame, by its report; and the events its steps put in the
    ;; world's inbox, taken.
    core0-display core0-frame-ns core0-hidden? core0-flags core0-error-text
    core0-step-state core0-frame-report
    core0-window-sizes core0-window-scale core0-window-fullscreen?
    clipboard-get core0-window-events core0-input-ns-take!
    ;; Jobs: posted to core0's mailbox, run at its next step; safe from any
    ;; thread.
    core0-window-minimum! core0-window-fullscreen! core0-window-icon!
    core0-set-cursor! clipboard-set! core0-trace-dump! core0-refresh-ns!
    ;; a step of the calling thread's, on its own ring
    core0-trace!
    ;; and its wake, ending core0's wait; frames published, whether the last
    ;; waits still, those given back, and what core0 read back: from any
    ;; thread
    core0-wake! gpu-publish! gpu-frame-waiting? gpu-frames-back!
    gpu-take-answers!
    ;; whether core0 has a thread of its own; core1's wait, and its wake from
    ;; any thread; and quitting, a job
    core0-forked? core0-world-wait! core0-world-wake! core0-quit!
    ;; and how far the world has loaded, for the boot screen
    core0-world-loaded!
    ;; Calls into SDL or core0's own state: safe only on core0's thread.
    ;; Until core0 has a thread of its own the world steps it (core0-step!),
    ;; and boots it (opening, sizing, showing the window).
    core0-step! core0-window-headless! core0-window-open! core0-window-show!
    core0-window-close! core0-window-resize!
    ;; The clock and the CPU count, from any thread, and the means to bind
    ;; C of one's own ((schevana ffi)).
    core0-clock-ns platform-cpu-count load-first-library define-foreign
    c-clock-gettime c-close c-string->string
    ;; Core0 on this thread, the world on its own.
    core0-run!)
  (import (chezscheme)
          (only (schevana base) library-layer define-view)
          (only (schevana ffi) load-first-library define-foreign c-clock-gettime
                c-close c-string->string)
          (only (schevana shader) shader make-shader shader-name shader-stage
                shader-coords shader-params shader-source shader-code
                shader-price shader-target shader-entry shader-group-x
                shader-uniforms shader-words)
          (only (schevana core0 mail) core0-display core0-frame-ns core0-wake!
                core0-forked? core0-world-wait! core0-clock-ns)
          (only (schevana core0 platform) platform-cpu-count)
          (only (schevana core0 present) core0-frame-report core0-refresh-ns!)
          (only (schevana core0 trace-file) core0-trace-dump!)
          (only (schevana core0 gpu) gpu-atlas-side gpu-usage-sampler
                gpu-usage-target gpu-show-run? gpu-run-gone? gpu-list-id
                gpu-list-labels gpu-list-labels-set! gpu-list-recorded
                gpu-list-recorded-set! gpu-list-took gpu-list-took-set!
                make-gpu-image gpu-image-id gpu-image-w gpu-image-h
                gpu-image-levels gpu-image-gone?-set! make-gpu-buffer*
                gpu-buffer-id gpu-buffer-size gpu-buffer-gone?-set!
                make-gpu-call gpu-call? gpu-call-shader gpu-frame-make
                gpu-frame-table-set! gpu-frame-table-n-set!
                gpu-frame-pieces-set! gpu-frame-jobs-set!
                gpu-frame-computes-set! gpu-frame-mode-set!
                gpu-frame-in-flight-set! gpu-frame-number gpu-frame-shown?
                gpu-publish! gpu-frames-back! gpu-take-answers!
                core0-world-loaded!)
          (only (schevana core0 window) core0-app-id core0-flag-names
                core0-event-name core0-flags core0-error-text core0-step-state
                core0-window-sizes core0-window-scale core0-window-fullscreen?
                clipboard-get core0-window-events core0-input-ns-take!
                core0-window-minimum! core0-window-fullscreen!
                core0-window-icon! core0-set-cursor! clipboard-set! core0-quit!
                core0-step! core0-window-headless! core0-window-open!
                core0-window-show! core0-window-close! core0-window-resize!
                core0-run!)
          (prefix (only (schevana core0 mail) core0-world-wake!) core0:)
          (prefix (only (schevana core0 trace) core0-trace!) core0:)
          (prefix (only (schevana core0 platform) *core0-platform*) core0:)
          (prefix (only (schevana core0 gpu) *gpu-facts*
                        gpu-frame-waiting?) core0:)
          (prefix (only (schevana core0 window) *core0-mode*
                        core0-hidden?) core0:))

  (library-layer core0 facade)

  ;; What core0 sets, and core1 reads or calls: views.
  (define-view *gpu-facts* core0:*gpu-facts*)
  (define-view *core0-mode* core0:*core0-mode*)
  (define-view *core0-platform* core0:*core0-platform*)
  (define-view core0-hidden? core0:core0-hidden?)
  (define-view core0-trace! core0:core0-trace!)
  (define-view gpu-frame-waiting? core0:gpu-frame-waiting?)
  (define-view core0-world-wake! core0:core0-world-wake!))
