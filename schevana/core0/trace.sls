;;; (schevana core0 trace) — what core0 and core1 did around each frame,
;;; for anyone looking into missed frames. Each thread records its steps (a
;;; code, a time and one number) in a ring of its own, which holds the last
;;; few minutes of them. The rings, with the screen's reports on the frames
;;; still kept, are written to a file of their own when the window closes
;;; or on (core0-trace-dump!), and also when core1 stops stepping or Ctrl-C
;;; ends the run, so that a freeze shows where core1 stopped. The trace is
;;; on in a checkout with a .work folder and a window; elsewhere
;;; core0-trace! does nothing.

(library (schevana core0 trace)
  (export
    core0-trace-rows *core0-trace-dir* *core0-trace-rings* *core0-trace-thread*
    core0-trace!)
  (import (chezscheme)
          (only (schevana base) define-state library-layer)
          (only (schevana core0 mail) core0-clock-ns))

  (library-layer core0)

  (define core0-trace-rows 262144)

  ;; The folder the trace files go to, or #f when the trace is off.
  (define-state *core0-trace-dir* #f)

  ;; One ring for each thread, each followed by its next index. A ring's
  ;; rows are (index code ns a), with the index written last, so that a
  ;; reader on another thread takes a row only once it is whole. The first
  ;; ring is core0's and the second core1's (with one thread, the first
  ;; holds both).
  (define-state *core0-trace-rings*
    (vector (make-fxvector (* 4 core0-trace-rows) -1) (box 0)
            (make-fxvector (* 4 core0-trace-rows) -1) (box 0)))
  (define-state *core0-trace-thread* #f)   ; core0's thread id

  ;; Records step code with the number a, at the current time, on this
  ;; thread's ring.
  (define (core0-trace! code a)
    (when *core0-trace-dir*
      (let* ([k (if (eqv? (get-thread-id) *core0-trace-thread*) 0 2)]
             [v (vector-ref *core0-trace-rings* k)]
             [b (vector-ref *core0-trace-rings* (fx+ k 1))]
             [n (unbox b)]
             [at (fx* 4 (fxmodulo n core0-trace-rows))])
        (fxvector-set! v at -1)
        (fxvector-set! v (fx+ at 1) code)
        (fxvector-set! v (fx+ at 2) (core0-clock-ns))
        (fxvector-set! v (fx+ at 3) a)
        (memory-order-release)
        (fxvector-set! v at n)
        (set-box! b (fx+ n 1))))))
