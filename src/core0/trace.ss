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

;; The steps' names, by code.
(define core0-trace-names
  '#(#f step take acquire acquired submit back sleep woke pump shown
     dropped gpu-done slow-pump event #f #f #f #f #f
     wait waited tick draw publish collect collected events gc gced))

;; From now on, if the checkout has a .work folder: on core0's thread, as
;; the window opens.
(define (core0-trace-start!)
  (let ([dir (string-append *schevana-root* "/.work")])
    (set! *core0-trace-thread* (get-thread-id))
    (when (file-directory? dir)
      (set! *core0-trace-dir* (string-append dir "/traces"))
      (core0-trace-on-interrupt!))))

;; The handler Ctrl-C had before the trace's, once it's set.
(defvar *core0-trace-interrupt* #f)

;; Ctrl-C ends the run as it did, the trace written first. Chez hands the
;; signal to the process's first thread, core0's with a window, which goes
;; on while core1 is stuck.
(define (core0-trace-on-interrupt!)
  (unless *core0-trace-interrupt*
    (set! *core0-trace-interrupt* (keyboard-interrupt-handler))
    (keyboard-interrupt-handler
     (lambda ()
       (guard (c [#t #f]) (core0-trace-write! "Ctrl-C ended the run"))
       (*core0-trace-interrupt*)))))

;; How long core1 may go without a step before core0 writes the trace: far
;; longer than any wait of core1's, which is a refresh or a timer's at most.
(define core0-trace-stall-ns 5000000000)

;; Core1's count of steps when a stall's trace was written: one a stall.
(defvar *core0-trace-stalled* -1)

;; On core0's step, core1 on a thread of its own: core1's newest step older
;; than core0-trace-stall-ns, the trace written, saying which it was.
(define (core0-trace-watch!)
  (when *core0-trace-dir*
    (let ([v (vector-ref *core0-trace-rings* 2)]
          [n (unbox (vector-ref *core0-trace-rings* 3))])
      (unless (or (fx= n 0) (fx= n *core0-trace-stalled*))
        (let ([at (fx* 4 (fxmodulo (fx- n 1) core0-trace-rows))])
          (memory-order-acquire)
          (when (eqv? (fxvector-ref v at) (fx- n 1))
            (let ([since (- (now-ns) (fxvector-ref v (fx+ at 2)))])
              (when (> since core0-trace-stall-ns)
                (set! *core0-trace-stalled* n)
                (core0-trace-write!
                 (format "core1 hasn't stepped for ~,1f s, since its ~a"
                         (/ since 1e9)
                         (vector-ref core0-trace-names
                                     (fxvector-ref v (fx+ at 1)))))))))))))

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

;; The file written, from any thread: a job of core0's.
(define (core0-trace-dump!) (core0-post! '(core0-trace-write!)))

;; The steps of both rings by time, then the frames' reports, to
;; .work/traces/trace-<date>-<time>.txt (-2 on, another in the same
;; second), after why it was written, if that's said. => its path, or #f
;; when off.
(define core0-trace-write!
  (case-lambda
    [() (core0-trace-write! #f)]
    [(why) (core0-trace-write-why! why)]))

(define (core0-trace-write-why! why)
  (and *core0-trace-dir*
       (let* ([d (current-date)]
              [stem (format "~a/trace-~4,'0d~2,'0d~2,'0d-~2,'0d~2,'0d~2,'0d"
                            *core0-trace-dir* (date-year d) (date-month d)
                            (date-day d) (date-hour d) (date-minute d)
                            (date-second d))]
              ;; a second's second trace (a stall's, then Ctrl-C's) beside
              ;; the first
              [path (let next ([k 1])
                      (let ([path (if (= k 1)
                                      (string-append stem ".txt")
                                      (format "~a-~a.txt" stem k))])
                        (if (file-exists? path) (next (+ k 1)) path)))]
              [rows (sort (lambda (a b) (< (cadr a) (cadr b)))
                          (append (core0-trace-rows-of 0 'core0)
                                  (core0-trace-rows-of 2 'core1)))]
              [t0 (if (pair? rows) (cadr (car rows)) (now-ns))])
         (unless (file-directory? *core0-trace-dir*)
           (mkdir *core0-trace-dir*))
         (call-with-output-file path
           (lambda (p)
             (fprintf p "# Schevana's trace, ~a~%# ~s~%" (date-and-time d)
                      *core0-platform*)
             (when why (fprintf p "# written as ~a~%" why))
             (fprintf p "# steps: ms since the first, thread, step, number~%")
             (for-each
              (lambda (r)
                (fprintf p "~,3f ~a ~a ~a~%" (/ (- (cadr r) t0) 1e6)
                         (car r) (caddr r) (cadddr r)))
              rows)
             (fprintf p "# frames: number, then ms since the first step: \
                         sent, shown (#f, not; dropped), refresh ms, \
                         sequence, GPU done~%")
             (core0-trace-frames p t0)))
         path)))

;; Ring k's whole rows, oldest first: (thread ns name a).
(define (core0-trace-rows-of k who)
  (let* ([v (vector-ref *core0-trace-rings* k)]
         [n (unbox (vector-ref *core0-trace-rings* (fx+ k 1)))])
    (let loop ([i (max 0 (- n core0-trace-rows))] [acc '()])
      (if (>= i n)
          (reverse acc)
          (let ([at (fx* 4 (fxmodulo i core0-trace-rows))])
            (memory-order-acquire)
            (loop (+ i 1)
                  (if (eqv? (fxvector-ref v at) i)
                      (cons (list who (fxvector-ref v (fx+ at 2))
                                  (or (vector-ref core0-trace-names
                                                  (fxvector-ref v (fx+ at 1)))
                                      (fxvector-ref v (fx+ at 1)))
                                  (fxvector-ref v (fx+ at 3)))
                            acc)
                      acc)))))))

;; The frames the screen's ring still holds, oldest first.
(define (core0-trace-frames p t0)
  (let ([newest (fold-left max -1
                           (map (lambda (i)
                                  (fxvector-ref *present-ring*
                                                (fx* present-words i)))
                                (iota present-rows)))]
        [ms (lambda (ns) (and ns (> ns 0) (/ (- ns t0) 1e6)))])
    (do ([frame (max 0 (- newest present-rows -1)) (+ frame 1)])
        ((> frame newest))
      (when (let ([sent (core0-frame-report frame 2)]) (and sent (> sent 0)))
        (fprintf p "~a ~,3f ~a ~,3f ~a ~a~%" frame
                 (ms (core0-frame-report frame 2))
                 (case (core0-frame-report frame 1)
                   [(1) (format "~,3f" (ms (core0-frame-report frame 3)))]
                   [(2) "dropped"]
                   [else "#f"])
                 (/ (core0-frame-report frame 4) 1e6)
                 (core0-frame-report frame 5)
                 (let ([g (ms (core0-frame-report frame 6))])
                   (if g (format "~,3f" g) "#f")))))))
