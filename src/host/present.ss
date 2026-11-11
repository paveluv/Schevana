;;; present.ss — what became of each frame core0 presents, by the screen's
;;; own reports where the platform gives them (src/host/platform.ss). For
;;; each frame: when core0 sent it; when it reached the screen, the vblank
;;; it showed at, on now-ns's clock, with the refresh and the display's
;;; sequence, or that the compositor dropped it; and when core0 first saw
;;; its GPU work done. Where the screen says nothing (X11, headless, the Mac
;;; so far) only the GPU's times are kept.
;;;
;;; The reports are a ring by frame number that only core0 writes, and the
;;; world reads (host-frame-report): a row is its frame's once it bears its
;;; number, written last, and what a report brings is in view once the
;;; row's kind says so, written after it.

(define present-rows 2048)
(define present-words 8)
;; A row: the frame's number; its kind (0 sent, 1 shown, 2 dropped); when
;; it was sent (now-ns); when it showed (now-ns); the refresh (ns); the
;; display's sequence; when its GPU work was seen done (now-ns; 0, not
;; yet); when core0 took it from main (now-ns).
(defvar *present-ring* (make-fxvector (* present-rows present-words) 0))

;; When core0 took the frame it presents now from main.
(defvar *present-taken* 0)
(define (present-taken!) (set! *present-taken* (now-ns)))

(define (present-at frame) (fx* present-words (fxmodulo frame present-rows)))

;; Word k of frame's row, or #f once the row is another frame's.
(define (host-frame-report frame k)
  (let ([at (present-at frame)])
    (and (fx= (fxvector-ref *present-ring* at) frame)
         (begin (memory-order-acquire)
                (fxvector-ref *present-ring* (fx+ at k))))))

;; Frame's row begun, as core0 sends it: the screen asked to report on it.
(define (present-sent! frame)
  (let ([r *present-ring*] [at (present-at frame)])
    (fxvector-set! r (fx+ at 1) 0)
    (fxvector-set! r (fx+ at 2) (now-ns))
    (do ([k 3 (fx+ k 1)]) ((fx= k 7))
      (fxvector-set! r (fx+ at k) 0))
    (fxvector-set! r (fx+ at 7) *present-taken*)
    (memory-order-release)
    (fxvector-set! r at frame))
  (platform-report-ask! frame))

;; The screen's word on frame: kind, and with 1 when it showed, the refresh
;; and the sequence.
(define (present-reported! frame kind shown refresh seq)
  (let ([r *present-ring*] [at (present-at frame)])
    (when (fx= (fxvector-ref r at) frame)
      (fxvector-set! r (fx+ at 3) shown)
      (fxvector-set! r (fx+ at 4) refresh)
      (fxvector-set! r (fx+ at 5) seq)
      (memory-order-release)
      (fxvector-set! r (fx+ at 1) kind))))

;;; ---- the GPU's times
;;; Each frame's fence, kept till core0 sees it signaled at a step of its
;;; own: when, to the step, its GPU work was done.

(define present-fence-slots 4)
(defvar *present-fences* (make-vector present-fence-slots 0))
(defvar *present-fence-frames* (make-fxvector present-fence-slots 0))

;; Frame's fence, to look at: a free slot, else the oldest given up.
(define (present-fence! frame fence)
  (let ([dev (renderer-device *renderer*)] [fs *present-fences*])
    (let loop ([i 0] [oldest 0])
      (cond
        [(fx= i present-fence-slots)
         (sdl-release-gpu-fence dev (vector-ref fs oldest))
         (vector-set! fs oldest fence)
         (fxvector-set! *present-fence-frames* oldest frame)]
        [(eqv? (vector-ref fs i) 0)
         (vector-set! fs i fence)
         (fxvector-set! *present-fence-frames* i frame)]
        [else
         (loop (fx+ i 1)
               (if (fx< (fxvector-ref *present-fence-frames* i)
                        (fxvector-ref *present-fence-frames* oldest))
                   i
                   oldest))]))))

;; The fences signaled since the last look: their frames' GPU times.
(define (present-poll!)
  (when *renderer*
    (let ([dev (renderer-device *renderer*)] [fs *present-fences*])
      (do ([i 0 (fx+ i 1)]) ((fx= i present-fence-slots))
        (let ([fence (vector-ref fs i)])
          (unless (or (eqv? fence 0) (not (sdl-query-gpu-fence dev fence)))
            (let* ([frame (fxvector-ref *present-fence-frames* i)]
                   [at (present-at frame)])
              (when (fx= (fxvector-ref *present-ring* at) frame)
                (fxvector-set! *present-ring* (fx+ at 6) (now-ns)))
              (host-trace! 12 frame))
            (sdl-release-gpu-fence dev fence)
            (vector-set! fs i 0)))))))
