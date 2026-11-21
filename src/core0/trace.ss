;;; trace.ss — what core0 and core1 did around each frame, for whoever looks
;;; into missed frames: each thread's steps (code, when, one number) in a
;;; ring of its own, the last few minutes of them, and written out with the
;;; screen's reports on the frames still kept, to a file of its own, when
;;; the window closes or on (core0-trace-dump!); and when core1 stops
;;; stepping, or Ctrl-C ends the run, so that a freeze says where core1
;;; stopped. On in a checkout with a .work folder and a window; elsewhere
;;; core0-trace! does nothing.

(define core0-trace-rows 262144)

;; Where the files go, or #f: off.
(defvar *core0-trace-dir* #f)

;; A ring a thread: rows of (index code ns a), the index written last, so a
;; reader on another thread takes a row only once it's whole; and the next
;; index. Core0's, and core1's (or both, with one thread).
(defvar *core0-trace-rings*
  (vector (make-fxvector (* 4 core0-trace-rows) -1) (box 0)
          (make-fxvector (* 4 core0-trace-rows) -1) (box 0)))
(defvar *core0-trace-thread* #f)   ; core0's thread id

;; Step code with a, now, on this thread's ring.
(define (core0-trace! code a)
  (when *core0-trace-dir*
    (let* ([k (if (eqv? (get-thread-id) *core0-trace-thread*) 0 2)]
           [v (vector-ref *core0-trace-rings* k)]
           [b (vector-ref *core0-trace-rings* (fx+ k 1))]
           [n (unbox b)]
           [at (fx* 4 (fxmodulo n core0-trace-rows))])
      (fxvector-set! v at -1)
      (fxvector-set! v (fx+ at 1) code)
      (fxvector-set! v (fx+ at 2) (now-ns))
      (fxvector-set! v (fx+ at 3) a)
      (memory-order-release)
      (fxvector-set! v at n)
      (set-box! b (fx+ n 1)))))
