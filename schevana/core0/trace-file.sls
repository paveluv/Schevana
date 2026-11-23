;;; (schevana core0 trace-file) — writes the trace ((schevana core0
;;; trace)), with the screen's reports on the frames still kept, to a file
;;; of its own: when the window closes, on (core0-trace-dump!), when core1
;;; stops stepping, and when Ctrl-C ends the run.

(library (schevana core0 trace-file)
  (export
    core0-trace-start! core0-trace-watch! core0-trace-dump! core0-trace-write!)
  (import (chezscheme)
          (only (schevana base) define-state library-layer)
          (only (schevana tree) *schevana-root*)
          (only (schevana core0 mail) *core0-world-waiting?* core0-clock-ns
                core0-post!)
          (only (schevana core0 trace) *core0-trace-dir* *core0-trace-rings*
                *core0-trace-thread* core0-trace-rows)
          (only (schevana core0 present) *present-ring* core0-frame-report
                present-rows present-words)
          (only (schevana core0 platform) *core0-platform* core0-look-ns)
          (only (schevana core0 gpu) *gpu-present-mode*))

  (library-layer core0)

  ;; The steps' names, by code.
  (define core0-trace-names
    '#(#f step take acquire acquired submit back sleep woke pump shown
       dropped gpu-done slow-pump event #f #f #f #f #f
       wait waited tick draw publish collect collected events gc gced
       mode))

  ;; Turns the trace on from now on, if the checkout has a .work folder. It
  ;; is called on core0's thread, as the window opens.
  (define (core0-trace-start!)
    (let ([dir (string-append *schevana-root* "/.work")])
      (set! *core0-trace-thread* (get-thread-id))
      (when (file-directory? dir)
        (set! *core0-trace-dir* (string-append dir "/traces"))
        (core0-trace-on-interrupt!))))

  ;; The handler Ctrl-C had before the trace set its own, once it has.
  (define-state *core0-trace-interrupt* #f)

  ;; Makes Ctrl-C write the trace first, then end the run as before. Chez
  ;; hands the signal to the process's first thread, which with a window is
  ;; core0's, and that thread keeps running while core1 is stuck.
  (define (core0-trace-on-interrupt!)
    (unless *core0-trace-interrupt*
      (set! *core0-trace-interrupt* (keyboard-interrupt-handler))
      (keyboard-interrupt-handler
       (lambda ()
         (guard (c [#t #f]) (core0-trace-write! "Ctrl-C ended the run"))
         (*core0-trace-interrupt*)))))

  ;; How long core1 may go without a step before core0 writes the trace: far
  ;; longer than any wait of core1's, which lasts a refresh or a timer's
  ;; delay at most.
  (define-state core0-trace-stall-ns 5000000000)

  ;; Core1's count of steps when a stall's trace was last written, so that
  ;; each stall writes one trace.
  (define-state *core0-trace-stalled* -1)

  ;; Called on each of core0's steps when core1 runs on a thread of its own.
  ;; If core1's newest step is older than core0-trace-stall-ns, it writes the
  ;; trace, saying which step that was. A core1 in its wait, which may last
  ;; as long as it likes, is not stalled.
  (define (core0-trace-watch!)
    (when *core0-trace-dir*
      (let ([v (vector-ref *core0-trace-rings* 2)]
            [n (unbox (vector-ref *core0-trace-rings* 3))])
        (unless (or (fx= n 0) (fx= n *core0-trace-stalled*)
                    *core0-world-waiting?*)
          (let ([at (fx* 4 (fxmodulo (fx- n 1) core0-trace-rows))])
            (memory-order-acquire)
            (when (eqv? (fxvector-ref v at) (fx- n 1))
              (let ([since (- (core0-clock-ns) (fxvector-ref v (fx+ at 2)))])
                (when (> since core0-trace-stall-ns)
                  (set! *core0-trace-stalled* n)
                  (core0-trace-write!
                   (format "core1 hasn't stepped for ~,1f s, since its ~a"
                           (/ since 1e9)
                           (vector-ref core0-trace-names
                                       (fxvector-ref v (fx+ at 1)))))))))))))

  ;; Writes the trace file from any thread, as a job posted to core0.
  (define (core0-trace-dump!) (core0-post! (list core0-trace-write!)))

  (define (core0-trace-write-why! why)
    (and *core0-trace-dir*
         (let* ([d (current-date)]
                [stem (format "~a/trace-~4,'0d~2,'0d~2,'0d-~2,'0d~2,'0d~2,'0d"
                              *core0-trace-dir* (date-year d) (date-month d)
                              (date-day d) (date-hour d) (date-minute d)
                              (date-second d))]
                ;; a second trace in the same second (a stall's, then
                ;; Ctrl-C's) goes beside the first
                [path (let next ([k 1])
                        (let ([path (if (= k 1)
                                        (string-append stem ".txt")
                                        (format "~a-~a.txt" stem k))])
                          (if (file-exists? path) (next (+ k 1)) path)))]
                [rows (sort (lambda (a b) (< (cadr a) (cadr b)))
                            (append (core0-trace-rows-of 0 'core0)
                                    (core0-trace-rows-of 2 'core1)))]
                [t0 (if (pair? rows) (cadr (car rows)) (core0-clock-ns))])
           (unless (file-directory? *core0-trace-dir*)
             (mkdir *core0-trace-dir*))
           (call-with-output-file path
             (lambda (p)
               (fprintf p "# Schevana's trace, ~a~%# ~s~%" (date-and-time d)
                        *core0-platform*)
               (when why (fprintf p "# written as ~a~%" why))
               ;; so that a step's number that is a time can be placed
               (fprintf p "# presents by ~a, looks every ~,3f ms; the first \
                           step at ~a ns on the clock~%"
                        *gpu-present-mode* (/ core0-look-ns 1e6) t0)
               (fprintf p "# steps: ms since the first, thread, step, number~%")
               (for-each
                (lambda (r)
                  (fprintf p "~,3f ~a ~a ~a~%" (/ (- (cadr r) t0) 1e6)
                           (car r) (caddr r) (cadddr r)))
                rows)
               (fprintf p "# frames: number, then ms since the first step: \
                           sent, shown by the screen's clock (#f, not; \
                           dropped), refresh ms, the refresh's number, GPU \
                           done, the screen's stamp, the last look that \
                           found its GPU work going~%")
               (core0-trace-frames p t0)))
           path)))

  ;; Writes the steps of both rings, sorted by time, then the frames'
  ;; reports, to .work/traces/trace-<date>-<time>.txt (with -2, -3, ... for
  ;; another trace in the same second), after the reason it was written, if
  ;; one is given. Returns the file's path, or #f when the trace is off.
  (define core0-trace-write!
    (case-lambda
      [() (core0-trace-write! #f)]
      [(why) (core0-trace-write-why! why)]))

  ;; Returns ring k's whole rows, oldest first, each as (thread ns name a).
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

  ;; Writes to p the frames the screen's ring still holds, oldest first.
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
          (fprintf p "~a ~,3f ~a ~,3f ~a ~a ~a ~a~%" frame
                   (ms (core0-frame-report frame 2))
                   (case (core0-frame-report frame 1)
                     [(1) (format "~,3f" (ms (core0-frame-report frame 3)))]
                     [(2) "dropped"]
                     [else "#f"])
                   (/ (core0-frame-report frame 4) 1e6)
                   (core0-frame-report frame 5)
                   (let ([g (ms (core0-frame-report frame 6))])
                     (if g (format "~,3f" g) "#f"))
                   (let ([s (ms (core0-frame-report frame 10))])
                     (if s (format "~,3f" s) "#f"))
                   (let ([g (ms (core0-frame-report frame 11))])
                     (if g (format "~,3f" g) "#f"))))))))
