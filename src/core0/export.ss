;;; core0/export.ss — what core0 gives the environments it makes
;;; (src/base.ss's define-exports): the recorder's, "/recorder", and core1's,
;;; "/core1". Nothing else of core0's is there to name. The world has of it
;;; only what core1 gives it again (src/core1/export.ss).

(define-exports core0-exports
  ;; Its interface, read-only, sorted by what a thread other than core0's
  ;; may do with it.
  (export (core1 recorder)
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
    ;; recorder's alone (below)
    gpu-list-id gpu-list-labels gpu-list-labels-set! gpu-list-recorded
    gpu-list-recorded-set! gpu-list-took gpu-list-took-set!
    ;; images, buffers and the calls that name them
    make-gpu-image gpu-image-id gpu-image-w gpu-image-h gpu-image-levels
    gpu-image-gone?-set! make-gpu-buffer* gpu-buffer-id gpu-buffer-size
    gpu-buffer-gone?-set! make-gpu-call gpu-call? gpu-call-shader
    ;; frames; what they write is the recorder's (below)
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
    core0-set-cursor! clipboard-set! core0-trace-dump! core0-eval!
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
    core0-step! core0-environment core0-recorder-environment
    core0-window-headless!
    core0-window-open! core0-window-show! core0-window-close!
    core0-window-resize!)
  ;; What core0 gives "/recorder" alone: recordings, the lists, images and
  ;; frame that hold them, how far frames have come back, and the calls
  ;; that hand core0 writes with no frame. Core1 never has them, so neither
  ;; it nor the world can name a byte core0 reads, or hand core0 a
  ;; recording the recorder didn't freeze.
  (export (recorder)
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
  ;; What core1 alone needs of core0's: the clock and the CPU count, from
  ;; any thread, and the means to bind C of its own (src/core1/ffi.ss).
  (export (core1)
    core0-clock-ns platform-cpu-count
    load-first-library define-foreign c-clock-gettime c-close
    c-string->string))
