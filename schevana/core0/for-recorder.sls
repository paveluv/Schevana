;;; (schevana core0 for-recorder) — what core0 gives the recorder
;;; ((schevana recorder bytes)): what it gives core1 of its records,
;;; frames and itself, and what it gives the recorder alone: recordings,
;;; the lists, images and frame that hold them, how far frames have come
;;; back, and the calls that hand core0 writes with no frame. Core1 never
;;; has these, so neither it nor the world can name a byte core0 reads, or
;;; hand core0 a recording the recorder didn't freeze. A state or a hook
;;; core0 sets is given as a view, which a set! refuses.

(library (schevana core0 for-recorder)
  (export
    ;; what core1 has too ((schevana core0))
    core0-app-id gpu-atlas-side gpu-usage-sampler gpu-usage-target
    core0-flag-names core0-event-name gpu-show-run? gpu-run-gone?
    shader make-shader shader-name shader-stage shader-coords shader-params
    shader-source shader-code shader-price shader-target shader-entry
    shader-group-x shader-uniforms shader-words
    gpu-list-id gpu-list-labels gpu-list-labels-set! gpu-list-recorded
    gpu-list-recorded-set! gpu-list-took gpu-list-took-set!
    make-gpu-image gpu-image-id gpu-image-w gpu-image-h gpu-image-levels
    gpu-image-gone?-set! make-gpu-buffer* gpu-buffer-id gpu-buffer-size
    gpu-buffer-gone?-set! make-gpu-call gpu-call? gpu-call-shader
    gpu-frame-make gpu-frame-table-set! gpu-frame-table-n-set!
    gpu-frame-pieces-set! gpu-frame-jobs-set! gpu-frame-computes-set!
    gpu-frame-mode-set! gpu-frame-in-flight-set! gpu-frame-number
    gpu-frame-shown?
    *gpu-facts* *core0-mode* *core0-platform*
    core0-display core0-frame-ns core0-hidden? core0-flags core0-error-text
    core0-step-state core0-frame-report
    core0-window-sizes core0-window-scale core0-window-fullscreen?
    clipboard-get core0-window-events core0-input-ns-take!
    core0-window-minimum! core0-window-fullscreen! core0-window-icon!
    core0-set-cursor! clipboard-set! core0-trace-dump! core0-refresh-ns!
    core0-trace!
    core0-wake! gpu-publish! gpu-frame-waiting? gpu-frames-back!
    gpu-take-answers!
    core0-forked? core0-world-wait! core0-world-wake! core0-quit!
    core0-world-loaded!
    core0-step! core0-window-headless! core0-window-open! core0-window-show!
    core0-window-close! core0-window-resize!
    ;; the recorder's alone
    make-gpu-recording gpu-recording-recs gpu-recording-recs-set!
    gpu-recording-recs-n gpu-recording-recs-n-set! gpu-recording-extras
    gpu-recording-extras-set! gpu-recording-extras-n
    gpu-recording-extras-n-set! gpu-recording-runs gpu-recording-runs-set!
    gpu-recording-version gpu-recording-version-set! gpu-recording-until
    gpu-recording-until-set! gpu-recording-next gpu-recording-next-set!
    make-gpu-list gpu-list-recording gpu-list-recording-set!
    gpu-recording? gpu-image? gpu-image-loans gpu-image-loans-set!
    gpu-frame-root gpu-frame-root-set! gpu-frame-number-set!
    gpu-frame-earlier-set! gpu-frame-writes-set!
    *gpu-frame-back* gpu-drawing->bytes gpu-compute-now!
    gpu-submit-computes! gpu-buffer-download! core0-post-submit!
    gpu-reads-now! core0-post-reads!)
  (import (chezscheme)
          (only (schevana base) library-layer define-view)
          (only (schevana shader) shader make-shader shader-name shader-stage
                shader-coords shader-params shader-source shader-code
                shader-price shader-target shader-entry shader-group-x
                shader-uniforms shader-words)
          (only (schevana core0 mail) core0-display core0-frame-ns core0-wake!
                core0-forked? core0-world-wait!)
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
                core0-world-loaded! make-gpu-recording gpu-recording-recs
                gpu-recording-recs-set! gpu-recording-recs-n
                gpu-recording-recs-n-set! gpu-recording-extras
                gpu-recording-extras-set! gpu-recording-extras-n
                gpu-recording-extras-n-set! gpu-recording-runs
                gpu-recording-runs-set! gpu-recording-version
                gpu-recording-version-set! gpu-recording-until
                gpu-recording-until-set! gpu-recording-next
                gpu-recording-next-set! make-gpu-list gpu-list-recording
                gpu-list-recording-set! gpu-recording? gpu-image?
                gpu-image-loans gpu-image-loans-set! gpu-frame-root
                gpu-frame-root-set! gpu-frame-number-set! gpu-frame-earlier-set!
                gpu-frame-writes-set! gpu-drawing->bytes gpu-compute-now!
                gpu-submit-computes! gpu-buffer-download! gpu-reads-now!)
          (only (schevana core0 window) core0-app-id core0-flag-names
                core0-event-name core0-flags core0-error-text core0-step-state
                core0-window-sizes core0-window-scale core0-window-fullscreen?
                clipboard-get core0-window-events core0-input-ns-take!
                core0-window-minimum! core0-window-fullscreen!
                core0-window-icon! core0-set-cursor! clipboard-set! core0-quit!
                core0-step! core0-window-headless! core0-window-open!
                core0-window-show! core0-window-close! core0-window-resize!
                core0-post-submit! core0-post-reads!)
          (prefix (only (schevana core0 mail) core0-world-wake!) core0:)
          (prefix (only (schevana core0 trace) core0-trace!) core0:)
          (prefix (only (schevana core0 platform) *core0-platform*) core0:)
          (prefix (only (schevana core0 gpu) *gpu-facts* gpu-frame-waiting?
                        *gpu-frame-back*) core0:)
          (prefix (only (schevana core0 window) *core0-mode*
                        core0-hidden?) core0:))

  (library-layer core0 facade)

  ;; What core0 sets, and the recorder reads or calls: views.
  (define-view *gpu-facts* core0:*gpu-facts*)
  (define-view *core0-mode* core0:*core0-mode*)
  (define-view *core0-platform* core0:*core0-platform*)
  (define-view *gpu-frame-back* core0:*gpu-frame-back*)
  (define-view core0-hidden? core0:core0-hidden?)
  (define-view core0-trace! core0:core0-trace!)
  (define-view gpu-frame-waiting? core0:gpu-frame-waiting?)
  (define-view core0-world-wake! core0:core0-world-wake!))
