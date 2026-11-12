;;; trace.ss — what core0 and main did around each frame, for whoever looks
;;; into missed frames: each thread's steps (code, when, one number) in a
;;; ring of its own, the last few minutes of them, and written out with the
;;; screen's reports on the frames still kept, to a file of its own, when
;;; the window closes or on (host-trace-dump!). On in a checkout with a
;;; .work folder and a window; elsewhere host-trace! does nothing.

(define host-trace-rows 131072)

;; Where the files go, or #f: off.
(defvar *host-trace-dir* #f)

;; A ring a thread: rows of (index code ns a), the index written last, so a
;; reader on another thread takes a row only once it's whole; and the next
;; index. Core0's, and main's (or both, with one thread).
(defvar *host-trace-rings*
  (vector (make-fxvector (* 4 host-trace-rows) -1) (box 0)
          (make-fxvector (* 4 host-trace-rows) -1) (box 0)))
(defvar *host-trace-core0* #f)   ; core0's thread id

;; The steps' names, by code.
(define host-trace-names
  '#(#f step take acquire acquired submit back sleep woke pump shown
     dropped gpu-done slow-pump event #f #f #f #f #f
     wait waited tick draw publish collect collected events))

;; From now on, if the checkout has a .work folder: on core0's thread, as
;; the window opens.
(define (host-trace-start!)
  (let ([dir (string-append *schevana-root* "/.work")])
    (set! *host-trace-core0* (get-thread-id))
    (when (file-directory? dir)
      (set! *host-trace-dir* (string-append dir "/traces")))))

;; Step code with a, now, on this thread's ring.
(define (host-trace! code a)
  (when *host-trace-dir*
    (let* ([k (if (eqv? (get-thread-id) *host-trace-core0*) 0 2)]
           [v (vector-ref *host-trace-rings* k)]
           [b (vector-ref *host-trace-rings* (fx+ k 1))]
           [n (unbox b)]
           [at (fx* 4 (fxmodulo n host-trace-rows))])
      (fxvector-set! v at -1)
      (fxvector-set! v (fx+ at 1) code)
      (fxvector-set! v (fx+ at 2) (now-ns))
      (fxvector-set! v (fx+ at 3) a)
      (memory-order-release)
      (fxvector-set! v at n)
      (set-box! b (fx+ n 1)))))

;; The file written, from any thread: a job of core0's.
(define (host-trace-dump!) (host-post! '(host-trace-write!)))

;; The steps of both rings by time, then the frames' reports, to
;; .work/traces/trace-<date>-<time>.txt. => its path, or #f when off.
(define (host-trace-write!)
  (and *host-trace-dir*
       (let* ([d (current-date)]
              [path (format "~a/trace-~4,'0d~2,'0d~2,'0d-~2,'0d~2,'0d~2,'0d.txt"
                            *host-trace-dir* (date-year d) (date-month d)
                            (date-day d) (date-hour d) (date-minute d)
                            (date-second d))]
              [rows (sort (lambda (a b) (< (cadr a) (cadr b)))
                          (append (host-trace-rows-of 0 'core0)
                                  (host-trace-rows-of 2 'main)))]
              [t0 (if (pair? rows) (cadr (car rows)) (now-ns))])
         (unless (file-directory? *host-trace-dir*)
           (mkdir *host-trace-dir*))
         (call-with-output-file path
           (lambda (p)
             (fprintf p "# Schevana's trace, ~a~%# ~s~%" (date-and-time d)
                      *host-platform*)
             (fprintf p "# steps: ms since the first, thread, step, number~%")
             (for-each
              (lambda (r)
                (fprintf p "~,3f ~a ~a ~a~%" (/ (- (cadr r) t0) 1e6)
                         (car r) (caddr r) (cadddr r)))
              rows)
             (fprintf p "# frames: number, then ms since the first step: \
                         sent, shown (#f, not; dropped), refresh ms, \
                         sequence, GPU done~%")
             (host-trace-frames p t0)))
         path)))

;; Ring k's whole rows, oldest first: (thread ns name a).
(define (host-trace-rows-of k who)
  (let* ([v (vector-ref *host-trace-rings* k)]
         [n (unbox (vector-ref *host-trace-rings* (fx+ k 1)))])
    (let loop ([i (max 0 (- n host-trace-rows))] [acc '()])
      (if (>= i n)
          (reverse acc)
          (let ([at (fx* 4 (fxmodulo i host-trace-rows))])
            (memory-order-acquire)
            (loop (+ i 1)
                  (if (eqv? (fxvector-ref v at) i)
                      (cons (list who (fxvector-ref v (fx+ at 2))
                                  (or (vector-ref host-trace-names
                                                  (fxvector-ref v (fx+ at 1)))
                                      (fxvector-ref v (fx+ at 1)))
                                  (fxvector-ref v (fx+ at 3)))
                            acc)
                      acc)))))))

;; The frames the screen's ring still holds, oldest first.
(define (host-trace-frames p t0)
  (let ([newest (fold-left max -1
                           (map (lambda (i)
                                  (fxvector-ref *present-ring*
                                                (fx* present-words i)))
                                (iota present-rows)))]
        [ms (lambda (ns) (and ns (> ns 0) (/ (- ns t0) 1e6)))])
    (do ([frame (max 0 (- newest present-rows -1)) (+ frame 1)])
        ((> frame newest))
      (when (let ([sent (host-frame-report frame 2)]) (and sent (> sent 0)))
        (fprintf p "~a ~,3f ~a ~,3f ~a ~a~%" frame
                 (ms (host-frame-report frame 2))
                 (case (host-frame-report frame 1)
                   [(1) (format "~,3f" (ms (host-frame-report frame 3)))]
                   [(2) "dropped"]
                   [else "#f"])
                 (/ (host-frame-report frame 4) 1e6)
                 (host-frame-report frame 5)
                 (let ([g (ms (host-frame-report frame 6))])
                   (if g (format "~,3f" g) "#f")))))))
