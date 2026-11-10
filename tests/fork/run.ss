;;; tests/fork/run.ss — what tests/units/fork.ss has a forked world do:
;;; loaded by main.ss's --eval on main, its own thread, core0 on the
;;; process's first. It writes what it saw, as a datum, to the file
;;; *fork-out* names, then quits.

(define (fork-raises? thunk) (guard (c [#t #t]) (thunk) #f))

(after 300
  (lambda ()
    (let ([seen
           (list (cons 'forked (host-forked?))
                 (cons 'main (main-thread?))
                 (cons 'readback
                       (fork-raises? (lambda ()
                                       (drawing->bytes 2 2 1 (lambda () #t)))))
                 (cons 'compute
                       (fork-raises? (lambda ()
                                       (gpu-buffer-read! (make-gpu-buffer 1))))))])
      (screen-bytes-then
       (lambda (bytes)
         (call-with-output-file *fork-out*
           (lambda (p)
             (write (append seen
                            (list (cons 'bytes (bytevector-length bytes))
                                  (cons 'frames (> *frames-drawn* 0))))
                    p))
           'replace)
         (quit!))))))
