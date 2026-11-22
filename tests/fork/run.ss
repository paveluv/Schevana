;;; tests/fork/run.ss — what tests/units/fork.ss has a forked world do.
;;; ./desktop's --eval loads it on core1, which runs on its own thread,
;;; with core0 on the process's first. It writes what it saw, as a datum,
;;; to the file that *fork-out* names, then quits.

(define (fork-raises? thunk) (guard (c [#t #t]) (thunk) #f))

;; A window that animates, keeping each frame's t and the time it came
;; (newest first) as it asks for the next. The run is timed after its
;; first 5 frames, which wait for the world's pipelines (and, on a first
;; run, for Mesa's shaders). It ends by a count of frames, 46 in all, not
;; by time, however long a busy machine takes for them.
(define fork-frames '())
(open-window "Animates" 'size '(120 . 80)
             'open window-frame-soon!
             'frame (lambda (win t)
                      (window-frame-soon! win)
                      (set! fork-frames (cons (cons t (now-ns)) fork-frames))
                      (when (= (length fork-frames) 46) (after 0 fork-done!))
                      (invalidate! win))
             'draw (lambda (win w h) (fill-box 0 0 w h 'accent)))

;; A compute run, and what it wrote read back through a callback
;; (gpu-buffer-read-then!), as a REPL's would be: core1 never waits for it.
(define-compute-shader (fork-squares x y) ([out fx-buffer write])
  (fx-set! out x (fx* x x)))
(define fork-read #f)
(let ([b (make-gpu-buffer 4)])
  (gpu-compute-soon! fork-squares 4 1 b)
  (gpu-buffer-read-then! b
    (lambda (bytes)
      (set! fork-read
        (map (lambda (i) (bytevector-s32-native-ref bytes (* 4 i)))
             (iota 4))))))

;; The same, as a REPL's input asks for it, in a process: gpu-compute!
;; and gpu-buffer-read! wait there while core1 goes on.
(define fork-waited #f)
(spawn "fork-wait"
       (lambda ()
         (let ([b (make-gpu-buffer 4)])
           (gpu-compute! fork-squares 4 1 b)
           (let ([bytes (gpu-buffer-read! b)])
             (set! fork-waited
               (map (lambda (i) (bytevector-s32-native-ref bytes (* 4 i)))
                    (iota 4)))))))

;; Returns how many of the ticks kept have phases that don't add up to
;; the tick's time, as Monitor's and the Pipeline's bars stack them.
(define (fork-unsummed)
  (length (remp (lambda (seq)
                  (= (profile-tick-ns seq 'ns)
                     (apply + (map cdr (profile-tick-phases seq)))))
                (profile-ticks))))

;; The timed frames, oldest first.
(define (fork-timed) (list-tail (reverse fork-frames) 5))

;; Returns how many gaps between the timed frames' t are not a whole
;; number of periods, to within 0.5 ms. A gap is one period where core1
;; kept up, and more where it was late for a refresh. A gap of more than
;; four periods doesn't count: core1 was away, and t starts anew.
(define (fork-uneven)
  (let ([p (core0-frame-ns)])
    (let count ([fs (fork-timed)] [k 0])
      (if (null? (cdr fs))
          k
          (count (cdr fs)
                 (let ([d (- (caadr fs) (caar fs))])
                   (if (or (and (< (abs (- d (* p (round (/ d p))))) 500000)
                                (> d (quotient p 2)))
                           (> d (* 4 p)))
                       k
                       (+ k 1))))))))

;; The number of refreshes between the first and the last timed frame, by
;; the clock.
(define (fork-refreshes)
  (let ([fs (fork-timed)])
    (exact (round (/ (- (cdar fork-frames) (cdar fs)) (core0-frame-ns))))))

(define (fork-done!)
  (let ([seen
         ;; core0-forked? is core0's, which the world isn't given: it is
         ;; read where the core has it, in core0's facade
         (list (cons 'forked
                     ((eval 'core0-forked? (environment '(schevana core0)))))
               (cons 'core1 (core1-thread?))
               (cons 'readback
                     (fork-raises? (lambda ()
                                     (drawing->bytes 2 2 1 (lambda () #t)))))
               (cons 'compute
                     (fork-raises?
                      (lambda () (gpu-buffer-read! (make-gpu-buffer 1)))))
               (cons 'read-then fork-read)
               (cons 'waited fork-waited))])
    (screen-bytes-then
     (lambda (bytes)
       (call-with-output-file *fork-out*
         (lambda (p)
           (write (append seen
                          (list (cons 'bytes (bytevector-length bytes))
                                (cons 'frames (> *frames-drawn* 0))
                                (cons 'animated (length (fork-timed)))
                                (cons 'refreshes (fork-refreshes))
                                (cons 'uneven (fork-uneven))
                                (cons 'ticks (length (profile-ticks)))
                                (cons 'unsummed (fork-unsummed))))
                  p))
         'replace)
       (quit!)))))
