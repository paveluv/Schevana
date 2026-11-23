;;; (schevana core0 for-recorder) — what core0 gives the recorder
;;; ((schevana recorder bytes)): the few names of core1's that it uses (a
;;; list's and an image's parts, whether core0 has a thread of its own),
;;; and what it gives the recorder alone: recordings, the lists, images and
;;; frames that hold them, how far frames have come back, and the calls
;;; that hand core0 writes outside a frame. Core1 never has these, so
;;; neither core1 nor the world can name a byte that core0 reads, or hand
;;; core0 a recording the recorder didn't freeze. A state that core0 sets
;;; is given as a view, which refuses a set!.

(library (schevana core0 for-recorder)
  (export
    ;; what core1 has too ((schevana core0))
    gpu-list-id gpu-list-labels gpu-list-recorded gpu-list-took gpu-image-id
    gpu-image-w gpu-image-h core0-forked?
    ;; the recorder's alone
    make-gpu-recording gpu-recording-recs gpu-recording-recs-set!
    gpu-recording-recs-n gpu-recording-recs-n-set! gpu-recording-extras
    gpu-recording-extras-set! gpu-recording-extras-n gpu-recording-extras-n-set!
    gpu-recording-runs gpu-recording-runs-set! gpu-recording-version
    gpu-recording-version-set! gpu-recording-until gpu-recording-until-set!
    gpu-recording-next gpu-recording-next-set! make-gpu-list gpu-list-recording
    gpu-list-recording-set! gpu-recording? gpu-image? gpu-image-loans
    gpu-image-loans-set! gpu-frame-root-set! gpu-frame-number-set!
    gpu-frame-earlier-set! gpu-frame-writes-set! *gpu-frame-back*
    gpu-drawing->bytes gpu-compute-now! gpu-submit-computes!
    gpu-buffer-download! core0-post-submit! gpu-reads-now! core0-post-reads!)
  (import (chezscheme)
          (only (schevana base) library-layer define-view)
          (only (schevana core0 mail) core0-forked?)
          (only (schevana core0 gpu) gpu-list-id gpu-list-labels
                gpu-list-recorded gpu-list-took gpu-image-id gpu-image-w
                gpu-image-h make-gpu-recording gpu-recording-recs
                gpu-recording-recs-set! gpu-recording-recs-n
                gpu-recording-recs-n-set! gpu-recording-extras
                gpu-recording-extras-set! gpu-recording-extras-n
                gpu-recording-extras-n-set! gpu-recording-runs
                gpu-recording-runs-set! gpu-recording-version
                gpu-recording-version-set! gpu-recording-until
                gpu-recording-until-set! gpu-recording-next
                gpu-recording-next-set! make-gpu-list gpu-list-recording
                gpu-list-recording-set! gpu-recording? gpu-image?
                gpu-image-loans gpu-image-loans-set! gpu-frame-root-set!
                gpu-frame-number-set! gpu-frame-earlier-set!
                gpu-frame-writes-set! gpu-drawing->bytes gpu-compute-now!
                gpu-submit-computes! gpu-buffer-download! gpu-reads-now!)
          (only (schevana core0 window) core0-post-submit! core0-post-reads!)
          (prefix (only (schevana core0 gpu) *gpu-frame-back*) core0:))

  (library-layer core0 facade)

  ;; What core0 sets and the recorder reads or calls, given as views.
  (define-view *gpu-frame-back* core0:*gpu-frame-back*))
