;;; apps/debug-repl.ss — what talks to the world from outside, in plain sight.
;;;
;;; While its window is open, a local socket takes Scheme to evaluate in the
;;; world, from a debugger or an agent, and the window shows every request and
;;; every answer as they come. Nobody types here: it's for watching, and it
;;; must be open for the socket to exist at all. Closing it closes the socket,
;;; and stops whatever was running.
;;;
;;; One connection, one request: send the forms as text and stop writing; the
;;; answer comes back as one datum, and the connection closes:
;;;
;;;   (ok "what it printed" ("a value, as text" ...) ms)
;;;   (error "what went wrong" "what it printed" ms)
;;;   (killed "what it printed" ms)      past debug-repl-limit-ms
;;;
;;;   printf '(+ 1 2)' | nc -UN $XDG_RUNTIME_DIR/schevana-debug.sock
;;;
;;; A request runs as a process, so a long one, or one that never ends, doesn't
;;; hold the world up. It runs in the world, with all the power that gives:
;;; only the user who owns the socket can reach it. main.ss sets where it
;;; listens (debug-repl-path!); with no path, as in the tests, there's no
;;; socket until one is set.

(define-record-type debug-repl
  (nongenerative schevana-debug-repl)
  (fields transcript
          (mutable listening)     ; its socket, or #f
          (mutable path)          ; where that is
          (mutable clients)))     ; the connections being served, oldest first

;; A connection: its socket, the request so far (a bytevector port and how to
;; get what it holds, how much), when it came, its process while that runs,
;; and its answer as bytes and how much of that has gone.
(define-record-type debug-repl-client
  (nongenerative schevana-debug-repl-client)
  (fields fd port get
          (mutable size)
          came
          (mutable proc)
          (mutable answer)
          (mutable sent)))

(defvar *debug-repl-path* #f)
(define (debug-repl-path! path) (set! *debug-repl-path* path))

;; Where a session listens: a folder only this user can read, if there is one.
(define (debug-repl-default-path)
  (format "~a/schevana-debug.sock"
          (or (getenv "XDG_RUNTIME_DIR") (getenv "TMPDIR") (getenv "HOME")
              ".")))

(define debug-repl-limit-ms 10000)   ; a request's time, running
(define debug-repl-read-ms 5000)     ; a request's time, arriving
(define debug-repl-most-bytes 1048576)   ; a request's size, and a text's
(define debug-repl-most-lines 200)   ; of a text, in the window
(define debug-repl-most-clients 8)
;; How often it looks for requests and answers them, ms: about a refresh.
(define debug-repl-serve-ms 16)
(define debug-repl-buffer-bytes 4096)
(defvar *debug-repl-buffer* (make-bytevector debug-repl-buffer-bytes))

;; text into the transcript, its long tail left out: the answer has it all.
(define (debug-repl-show! d style text)
  (let* ([lines (string-split text #\newline)] [n (length lines)]
         [t (debug-repl-transcript d)])
    (if (> n debug-repl-most-lines)
        (begin
          (transcript-add! t style
                           (string-join (list-head lines debug-repl-most-lines)
                                        "\n"))
          (transcript-add! t 'info (format "; ... and ~a more lines"
                                           (- n debug-repl-most-lines))))
        (transcript-add! t style text))))

;; The request's forms as the transcript shows them, each line after its
;; prompt.
(define (debug-repl-show-request! d text)
  (let ([lines (string-split text #\newline)])
    (for-each (lambda (line i)
                (debug-repl-show! d 'request
                                  (string-append (if (= i 0) repl-prompt
                                                     repl-cont)
                                                 line)))
              lines (iota (length lines)))))

(define (debug-repl-clip text)
  (if (> (string-length text) debug-repl-most-bytes)
      (string-append (substring text 0 debug-repl-most-bytes) "...")
      text))

;; The client's answer: what it says, shown and on its way.
(define (debug-repl-answer! d c datum)
  (debug-repl-client-answer-set!
   c (string->utf8 (with-output-to-string (lambda () (write datum)))))
  (debug-repl-client-proc-set! c #f))

;; The request has all come: it runs.
(define (debug-repl-start! d c)
  (let* ([text (utf8->string ((debug-repl-client-get c)))]
         [out (open-output-string)] [started (now-ms)] [vals '()])
    (debug-repl-show-request! d text)
    (debug-repl-client-proc-set!
     c
     (spawn "debug-repl"
            (lambda ()
              (parameterize ([current-output-port out]
                             [current-error-port out]
                             [current-input-port (open-input-string "")])
                (for-each
                 (lambda (form)
                   (call-with-values
                     (lambda () (env-eval (env-root) form))
                     (lambda results
                       (for-each (lambda (v)
                                   (unless (eq? v (void))
                                     (set! vals
                                       (cons (debug-repl-clip (value->string v))
                                             vals))))
                                 results))))
                 (read-input! text))))
            (lambda (status value)
              (let ([printed (debug-repl-clip (get-output-string out))]
                    [ms (- (now-ms) started)]
                    [results (reverse vals)])
                (unless (string=? printed "")
                  (debug-repl-show! d 'output printed))
                (case status
                  [(error)
                   (let ([why (condition->string value)])
                     (debug-repl-show! d 'error why)
                     (debug-repl-answer! d c (list 'error why printed ms)))]
                  [(killed)
                   (transcript-add! (debug-repl-transcript d) 'error
                                    (format "; stopped after ~a ms" ms))
                   (debug-repl-answer! d c (list 'killed printed ms))]
                  [else
                   (for-each (lambda (r) (debug-repl-show! d 'result r))
                             results)
                   (transcript-add! (debug-repl-transcript d) 'info
                                    (format "; ~a ms" ms))
                   (debug-repl-answer! d c
                                       (list 'ok printed results ms))])))))))

;; A step of a connection's: reading, running or answering. => is it still on?
(define (debug-repl-serve-client! d c)
  (let ([fd (debug-repl-client-fd c)])
    (cond
      [(debug-repl-client-answer c)
       (let ([at (socket-write fd (debug-repl-client-answer c)
                                    (debug-repl-client-sent c))])
         (cond
           [(and at (< at (bytevector-length (debug-repl-client-answer c))))
            (debug-repl-client-sent-set! c at)
            #t]
           [else #f]))]
      [(debug-repl-client-proc c)
       (when (> (- (now-ms) (debug-repl-client-came c))
                debug-repl-limit-ms)
         (kill! (debug-repl-client-proc c)))
       #t]
      [else
       (let ([n (socket-read fd *debug-repl-buffer*)])
         (cond
           [(not n)
            (if (> (- (now-ms) (debug-repl-client-came c)) debug-repl-read-ms)
                (begin
                  (transcript-add! (debug-repl-transcript d) 'error
                                   "; a request that never finished arriving")
                  #f)
                #t)]
           [(zero? n) (debug-repl-start! d c) #t]
           [(> (+ n (debug-repl-client-size c)) debug-repl-most-bytes)
            (transcript-add! (debug-repl-transcript d) 'error
                             "; a request too long to take")
            #f]
           [else
            (put-bytevector (debug-repl-client-port c) *debug-repl-buffer* 0 n)
            (debug-repl-client-size-set! c (+ n (debug-repl-client-size c)))
            #t]))])))

;; A tick's work: a new client, and a step of each.
;; Serves again after debug-repl-serve-ms, while it listens.
(define (debug-repl-serve-soon! d win)
  (after debug-repl-serve-ms
         (lambda ()
           (when (debug-repl-listening d)
             (debug-repl-serve! d win)
             (debug-repl-serve-soon! d win)))))

(define (debug-repl-serve! d win)
  (let ([fd (debug-repl-listening d)])
    (when fd
      (when (< (length (debug-repl-clients d)) debug-repl-most-clients)
        (let ([c (socket-accept fd)])
          (when c
            (let-values ([(port get) (open-bytevector-output-port)])
              (debug-repl-clients-set!
               d (append (debug-repl-clients d)
                         (list (make-debug-repl-client
                                c port get 0 (now-ms) #f #f 0))))))))
      (let ([count (transcript-count (debug-repl-transcript d))])
        (debug-repl-clients-set!
         d (filter (lambda (c)
                     (or (debug-repl-serve-client! d c)
                         (begin (socket-close (debug-repl-client-fd c))
                                #f)))
                   (debug-repl-clients d)))
        (unless (= count (transcript-count (debug-repl-transcript d)))
          (invalidate! win))))))

;; It listens at the path set, and says so.
(define (debug-repl-listen! d)
  (let ([t (debug-repl-transcript d)] [path *debug-repl-path*])
    (transcript-add! t 'banner "Debug REPL: what talks to the world from \
                                outside. Nobody types here.")
    (if path
        (guard (c [#t (transcript-add! t 'error (condition->string c))])
          (debug-repl-listening-set! d (socket-listen path))
          (debug-repl-path-set! d path)
          (transcript-add! t 'info (format "; listening at ~a" path)))
        (transcript-add! t 'info "; no socket: no path is set \
                                  (debug-repl-path!)"))))

;; Everything stops with the window.
(define (debug-repl-close! d)
  (for-each (lambda (c)
              (when (debug-repl-client-proc c)
                (kill! (debug-repl-client-proc c)))
              (socket-close (debug-repl-client-fd c)))
            (debug-repl-clients d))
  (debug-repl-clients-set! d '())
  (when (debug-repl-listening d)
    (socket-close (debug-repl-listening d))
    (debug-repl-listening-set! d #f)
    (when (file-exists? (debug-repl-path d))
      (delete-file (debug-repl-path d)))))

(define (debug-repl-open-window)
  (let ([d (make-debug-repl (transcript-new) #f #f '())])
    (debug-repl-listen! d)
    (open-window "Debug REPL"
      'size (repl-window-size)
      'min-size '(240 . 120)
      'bg 'bg-0
      'draw (lambda (win w h)
              (fill-box 0 0 w h 'bg-0)
              (transcript-draw-view (debug-repl-transcript d) w h))
      'wheel (lambda (win dx dy)
               (let ([t (debug-repl-transcript d)])
                 (transcript-scroll-set!
                  t (max 0 (+ (transcript-scroll t) (* 3 dy)))))
               (invalidate! win))
      ;; served seen or not, every few ms, until it's closed
      'open (lambda (win) (debug-repl-serve-soon! d win))
      'close (lambda (win) (debug-repl-close! d))
      'state d)))

(define-app (debug-repl) "Debug REPL"
  (let ([existing (find-window 'debug-repl)])
    (if existing
        (begin (focus-window! existing) existing)
        (debug-repl-open-window))))
