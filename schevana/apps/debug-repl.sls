;;; (schevana apps debug-repl) — a way to talk to the world from outside, in
;;; plain sight.
;;;
;;; While its window is open, a local socket takes Scheme to evaluate in the
;;; world, from a debugger or an agent, and the window shows every request and
;;; every answer as they come. Nobody types here: the window is for watching,
;;; and it must be open for the socket to exist at all. Closing it closes the
;;; socket and stops whatever was running.
;;;
;;; Each connection carries one request: send the forms as text and stop
;;; writing; the answer comes back as one datum, and the connection closes:
;;;
;;;   (ok "what it printed" ("a value, as text" ...) ms)
;;;   (error "what went wrong" "what it printed" ms)
;;;   (killed "what it printed" ms)      past debug-repl-limit-ms
;;;
;;;   printf '(+ 1 2)' | nc -UN $XDG_RUNTIME_DIR/schevana-debug.sock
;;;
;;; A request runs as a process, so a long one, or one that never ends, doesn't
;;; hold up the world. It runs in the world, with all the power that gives, so
;;; only the user who owns the socket can reach it. The desktop's start sets
;;; where it listens (debug-repl-path!); with no path, there is no socket
;;; until one is set.

(library (schevana apps debug-repl)
  (export
    debug-repl)
  (import (chezscheme)
          (only (schevana base) at-load condition->string define-state
                library-layer string-join string-split)
          (only (schevana core) after alpha clipboard-set! define-app
                draw-line draw-polyline fill-box fill-circle find-window
                focus-window! invalidate! kill! now-ms open-window
                socket-accept socket-close socket-listen socket-read
                socket-write spawn stroke-box style)
          (only (schevana desktop start) desktop-at-start!)
          (only (schevana kits transcript) transcript-scroll
                transcript-scroll-set! transcript-draw-view transcript-new
                transcript-count transcript-add! transcript-press!
                transcript-drag! transcript-release! transcript-selection)
          (only (schevana services env) env-root env-eval)
          (only (schevana kits repl) repl-cont repl-prompt repl-read-input!
                repl-value->string repl-window-size)
          (only (schevana kits ui) ui-icon-grid ui-icon-ink))

  (library-layer apps)

  ;; The record has a name of its own, since debug-repl is the app's name.
  (define-record-type (debug-repl-record make-debug-repl debug-repl?)
    (nongenerative schevana-debug-repl)
    (fields
     (immutable transcript debug-repl-transcript)
     ;; the socket it listens on, or #f
     (mutable listening debug-repl-listening debug-repl-listening-set!)
     ;; that socket's path
     (mutable path debug-repl-path debug-repl-path-set!)
     ;; the connections being served, oldest first
     (mutable clients debug-repl-clients debug-repl-clients-set!)))

  ;; A connection: its socket; the request so far (a bytevector port, the
  ;; procedure that gets what it holds, and how many bytes it holds); when it
  ;; came; its process while that runs; and its answer as bytes, with how
  ;; many of them have been sent.
  (define-record-type debug-repl-client
    (nongenerative schevana-debug-repl-client)
    (fields fd port get
            (mutable size)
            came
            (mutable proc)
            (mutable answer)
            (mutable sent)))

  (define-state *debug-repl-path* #f)
  (define (debug-repl-path! path) (set! *debug-repl-path* path))

  ;; Reads a request's text with the kit's reader, which names it by
  ;; *debug-repl-requests*, the count of the requests.
  (define-state *debug-repl-requests* 0)

  (define (debug-repl-read! text)
    (set! *debug-repl-requests* (+ *debug-repl-requests* 1))
    (repl-read-input! text
                      (format "Debug REPL request ~a" *debug-repl-requests*)))

  ;; Returns where a session listens: in a folder only this user can read
  ;; ($XDG_RUNTIME_DIR), if there is one.
  (define (debug-repl-default-path)
    (format "~a/schevana-debug.sock"
            (or (getenv "XDG_RUNTIME_DIR") (getenv "TMPDIR") (getenv "HOME")
                ".")))

  ;; A desktop session listens at the default path; a world whose desktop
  ;; never starts listens nowhere.
  (at-load
   (desktop-at-start! (lambda () (debug-repl-path! (debug-repl-default-path)))))

  (define-state debug-repl-limit-ms 10000)   ; how long a request may run
  (define debug-repl-read-ms 5000)     ; how long a request may take to arrive
  (define debug-repl-most-bytes 1048576)   ; most bytes of a request or a text
  (define debug-repl-most-lines 200)   ; the most lines of a text shown
  (define debug-repl-most-clients 8)
  ;; How often, in ms, it looks for requests and answers them: about once a
  ;; refresh.
  (define debug-repl-serve-ms 16)
  (define debug-repl-buffer-bytes 4096)
  (define-state *debug-repl-buffer* (make-bytevector debug-repl-buffer-bytes))

  ;; Adds text to the transcript, leaving out a long tail: the answer has all
  ;; of it.
  (define (debug-repl-show! d style text)
    (let* ([lines (string-split text #\newline)] [n (length lines)]
           [t (debug-repl-transcript d)])
      (if (> n debug-repl-most-lines)
          (begin
            (transcript-add! t style
                             (string-join (list-head lines
                                                     debug-repl-most-lines)
                                          "\n"))
            (transcript-add! t 'info (format "; ... and ~a more lines"
                                             (- n debug-repl-most-lines))))
          (transcript-add! t style text))))

  ;; Shows the request's forms in the transcript, each line after its
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

  ;; Sets the client's answer, datum written as bytes, ready to be sent; the
  ;; client no longer has a process.
  (define (debug-repl-answer! d c datum)
    (debug-repl-client-answer-set!
     c (string->utf8 (with-output-to-string (lambda () (write datum)))))
    (debug-repl-client-proc-set! c #f))

  ;; Runs the request, once all of it has arrived.
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
                                         (cons (debug-repl-clip
                                                (repl-value->string v))
                                               vals))))
                                   results))))
                   (debug-repl-read! text))))
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

  ;; Takes one step of a connection: reading, running or answering. Returns
  ;; whether the connection stays open.
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
              (put-bytevector (debug-repl-client-port c) *debug-repl-buffer* 0
                              n)
              (debug-repl-client-size-set! c (+ n (debug-repl-client-size c)))
              #t]))])))

  ;; Serves again after debug-repl-serve-ms, while it listens.
  (define (debug-repl-serve-soon! d win)
    (after debug-repl-serve-ms
           (lambda ()
             (when (debug-repl-listening d)
               (debug-repl-serve! d win)
               (debug-repl-serve-soon! d win)))))

  ;; One round of work: a new client, if one is waiting, and a step of each
  ;; client.
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

  ;; Listens at the path that is set, and says so in the transcript.
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

  ;; Everything stops with the window: the requests that run, the
  ;; connections and the socket.
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
        ;; its text can be selected and copied, as a REPL's; nothing is
        ;; typed here, so the text menu has no Paste
        'cursor 'ibeam
        'mouse-down (lambda (win x y button clicks)
                      (when (transcript-press! (debug-repl-transcript d) x y
                                               button clicks #f)
                        (invalidate! win)))
        'mouse-move (lambda (win x y)
                      (when (transcript-drag! (debug-repl-transcript d) x y)
                        (invalidate! win)))
        'mouse-up (lambda (win x y button)
                    (transcript-release! (debug-repl-transcript d) x y
                                         button))
        'key (lambda (win key mods)
               (when (and (memq 'ctrl mods) (eqv? key #\c))
                 (let ([s (transcript-selection (debug-repl-transcript d))])
                   (unless (string=? s "") (clipboard-set! s)))))
        ;; served every few ms, seen or not, until the window closes
        'open (lambda (win) (debug-repl-serve-soon! d win))
        'close (lambda (win) (debug-repl-close! d))
        'state d)))

  ;; The app's icon: a prompt in a window, with a bug on its corner.
  (define (debug-repl-draw-icon x y s flags)
    (define (ink c) (ui-icon-ink flags c))
    (ui-icon-grid (x y s)
      (fill-box 2 3 18 14 (ink (alpha 'orange 0.18)) 3)
      (stroke-box 2 3 18 14 (ink 'orange) 1.75 3)
      (draw-polyline '((6 . 7) (9 . 10) (6 . 13)) (ink 'orange) 1.75)
      ;; the bug: three legs on each side, its body, its head
      (for-each (lambda (x0 y0 x1 y1)
                  (draw-line x0 y0 x1 y1 (ink 'red) 1.25)
                  (draw-line (- 35 x0) y0 (- 35 x1) y1 (ink 'red) 1.25))
                '(14 13.5 14) '(15.5 17.5 19.5) '(12 11.5 12) '(13.5 17.5 21.5))
      (fill-circle 17.5 17.5 4 (ink 'red))
      (fill-circle 17.5 12.6 2 (ink 'red))
      (draw-line 17.5 14.5 17.5 21 (ink (alpha 'bg-0 0.6)) 1)))

  (define-app (debug-repl) "Debug REPL" 'icon debug-repl-draw-icon
    (let ([existing (find-window 'debug-repl)])
      (if existing
          (begin (focus-window! existing) existing)
          (debug-repl-open-window)))))
