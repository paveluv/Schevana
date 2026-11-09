;;; tests/units/debug-repl.ss — what talks to the world from outside: a local
;;; socket that exists while the window is open, in plain sight on it.

(define debug-repl-test-path (string-append out-dir "/debug.sock"))

;; text as a client sends it, steps until the answer has come. => the datum
(define (debug-repl-test-ask text)
  (let ([fd (host-socket-connect debug-repl-test-path)]
        [bytes (string->utf8 text)]
        [buffer (make-bytevector 4096)])
    (let-values ([(port get) (open-bytevector-output-port)])
      (let send ([at 0])
        (let ([next (host-socket-write fd bytes at)])
          (unless (= next (bytevector-length bytes)) (send next))))
      (host-socket-end-writing fd)
      ;; it serves by a timer, so the answer is waited for by the clock
      (let wait ([until (+ (now-ms) 5000)])
        (when (> (now-ms) until)
          (errorf 'debug-repl-test-ask "no answer to ~a" text))
        (steps 1)
        (let ([n (host-socket-read fd buffer)])
          (cond
            [(not n) (wait until)]
            [(zero? n) (void)]
            [else (put-bytevector port buffer 0 n) (wait until)])))
      (host-socket-close fd)
      (read (open-input-string (utf8->string (get)))))))

(define (debug-repl-test-styles win)
  (map car (reverse (transcript-lines
                     (debug-repl-transcript (window-ref win 'state))))))

(check "with no path set, a Debug REPL says so and there's no socket"
       (let* ([win (debug-repl)] [d (window-ref win 'state)])
         (let ([none (not (debug-repl-listening d))])
           (close-window! win)
           none)))

(debug-repl-path! debug-repl-test-path)

(let ([win (debug-repl)])
  (steps 2)
  (check "the socket is there while the window is open, for its owner alone; \
          a second call shows the same window; nothing there takes keys"
         (and (file-exists? debug-repl-test-path)
              (= (logand (get-mode debug-repl-test-path) #o077) 0)
              (eq? (debug-repl) win)
              (let ([hs (window-handlers win)])
                (not (or (hashtable-contains? hs 'key)
                         (hashtable-contains? hs 'text))))))
  (check "a request evaluates in the world, and its value comes back as text"
         (let ([a (debug-repl-test-ask "(define debug-repl-test-x 40) \
                                        (+ debug-repl-test-x 2)")])
           (and (eq? (car a) 'ok)
                (string=? (cadr a) "")
                (equal? (caddr a) '("42"))
                (= (top-level-value 'debug-repl-test-x) 40))))
  (check "what it prints comes back too"
         (let ([a (debug-repl-test-ask "(display \"hi\") (* 2 3)")])
           (and (eq? (car a) 'ok)
                (string=? (cadr a) "hi")
                (equal? (caddr a) '("6")))))
  (check "an error comes back as one, and so does a request that can't be read"
         (let ([bad (debug-repl-test-ask "(car 1)")]
               [unread (debug-repl-test-ask "(1 2")])
           (and (eq? (car bad) 'error)
                (eq? (car unread) 'error))))
  (check "one that never ends is stopped at the limit, and the world goes on"
         (let ([ticks (pacer-ticks)])
           (let ([a (fluid-let ([debug-repl-limit-ms 50])
                      (debug-repl-test-ask "(let loop () (loop))"))])
             (and (eq? (car a) 'killed)
                  (> (pacer-ticks) ticks)
                  (null? (filter (lambda (p)
                                   (string=? (proc-name p) "debug-repl"))
                                 (procs)))))))
  (check "the window shows requests and answers, each in its style, and draws"
         (let ([styles (debug-repl-test-styles win)])
           (invalidate! win)
           (steps 2)
           (and (memq 'request styles)
                (memq 'result styles)
                (memq 'output styles)
                (memq 'error styles)
                (memq 'info styles)
                (not (window-error win)))))
  (check "a client gone before its answer costs nothing but itself"
         (let ([fd (host-socket-connect debug-repl-test-path)]
               [bytes (string->utf8 "(+ 1 1)")])
           (host-socket-write fd bytes 0)
           (host-socket-end-writing fd)
           (host-socket-close fd)
           (steps 10)
           (and (null? (debug-repl-clients (window-ref win 'state)))
                (eq? (car (debug-repl-test-ask "1")) 'ok))))
  (check "closing the window closes the socket, and takes it away"
         (begin
           (close-window! win)
           (steps 1)
           (and (not (file-exists? debug-repl-test-path))
                (not (host-socket-connect debug-repl-test-path))))))

(debug-repl-path! #f)
