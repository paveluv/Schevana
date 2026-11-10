;;; tests/fork/run.ss — what tests/units/fork.ss has a forked world do:
;;; loaded by main.ss's --eval on main, its own thread, core0 on the
;;; process's first. It writes what it saw, as a datum, to the file
;;; *fork-out* names, then quits.

(define (fork-raises? thunk) (guard (c [#t #t]) (thunk) #f))

;; A window that animates: each frame's t and when it came, newest first,
;; as it asks for the next. The run is timed after its first 5, which wait
;; for the world's pipelines, and on a first run for Mesa's shaders.
(define fork-frames '())
(open-window "Animates" 'size '(120 . 80)
             'open window-frame-soon!
             'frame (lambda (win t)
                      (window-frame-soon! win)
                      (set! fork-frames (cons (cons t (now-ns)) fork-frames))
                      (when (= (length fork-frames) 6) (after 1000 fork-done!))
                      (invalidate! win))
             'draw (lambda (win w h) (fill-box 0 0 w h 'accent)))

;; The ticks kept whose phases don't add up to their time, as Monitor's and
;; the Pipeline's bars stack them.
(define (fork-unsummed)
  (length (remp (lambda (seq)
                  (= (profile-tick-ns seq 'ns)
                     (apply + (map cdr (profile-tick-phases seq)))))
                (profile-ticks))))

;; The frames timed, oldest first.
(define (fork-timed) (list-tail (reverse fork-frames) 5))

;; Of the gaps between the timed frames' t, those that aren't a period, to
;; the 0.5 ms.
(define (fork-uneven)
  (let ([p (host-frame-ns)])
    (let count ([fs (fork-timed)] [k 0])
      (if (null? (cdr fs))
          k
          (count (cdr fs)
                 (if (< (abs (- (caadr fs) (caar fs) p)) 500000)
                     k
                     (+ k 1)))))))

;; The refreshes between the first and the last timed frame, by the clock.
(define (fork-refreshes)
  (let ([fs (fork-timed)])
    (exact (round (/ (- (cdar fork-frames) (cdar fs)) (host-frame-ns))))))

(define (fork-done!)
  (let ([seen
         (list (cons 'forked (host-forked?))
               (cons 'main (main-thread?))
               (cons 'readback
                     (fork-raises? (lambda ()
                                     (drawing->bytes 2 2 1 (lambda () #t)))))
               (cons 'compute
                     (fork-raises?
                      (lambda () (gpu-buffer-read! (make-gpu-buffer 1))))))])
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
