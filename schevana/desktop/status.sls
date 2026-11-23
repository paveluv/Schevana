;;; (schevana desktop status) — the status segments on the right side of the
;;; top bar, a list of (name . thunk); each thunk returns a string, or #f to
;;; hide its segment. Add your own with
;;; (add-status-segment! 'hello (lambda () "hi!")).

(library (schevana desktop status)
  (export
    add-status-segment! remove-status-segment! *status-shown*)
  (import (chezscheme)
          (only (schevana base) at-load-once define-state library-layer)
          (only (schevana core) *procs* after pacer-peak-ms!
                platform-process-bytes request-frame! safe-call)
          (only (schevana kits ui) ui-month-names))

  (library-layer desktop)

  ;; the defaults, until you change them (a reload keeps your changes)
  (define-state *status-segments*
    (list (cons 'procs (lambda () (status-procs)))
          (cons 'busy (lambda () (status-busy)))
          (cons 'memory (lambda () (status-memory)))
          (cons 'clock (lambda () (status-clock)))))

  (define (add-status-segment! name thunk)
    (set! *status-segments*
      (append (remp (lambda (s) (eq? (car s) name)) *status-segments*)
              (list (cons name thunk))))
    (refresh-status!)
    (request-frame!))

  (define (remove-status-segment! name)
    (set! *status-segments*
      (remp (lambda (s) (eq? (car s) name)) *status-segments*))
    (refresh-status!)
    (request-frame!))

  ;; What the top bar shows, ((name . string-or-#f) ...), read once a second;
  ;; each segment's thunk runs under the watchdog (safe-call).
  (define-state *status-shown* '())

  (define (refresh-status!)
    (set! *status-shown*
      (map (lambda (s)
             (cons (car s)
                   (safe-call 'status (cdr s)
                              (lambda (c) (format "⚠ ~a" (car s))))))
           *status-segments*)))

  (define-state *status-second* #f)   ; the wall clock's second last shown

  ;; Reads the status again and asks for a frame that shows it.
  (define (status-show!)
    (refresh-status!)
    (request-frame!))

  ;; At the start of each second of the wall clock, the status is read and
  ;; shown again. The frames in between, however many something else asks
  ;; for, show the same values: numbers that change every tick (the heap and
  ;; the busiest tick) are read once a second, and the busiest tick is that
  ;; second's. Timers run on the monotonic clock, so this may fire a little
  ;; before the wall clock's second turns; it then only waits for the turn,
  ;; and nothing is shown twice.
  (define (status-second!)
    (let ([t (current-time)])
      (unless (eqv? (time-second t) *status-second*)
        (set! *status-second* (time-second t))
        (status-show!))
      (after (- 1000 (quotient (time-nanosecond t) 1000000))
             (lambda () (status-second!)))))

  ;; one timer, which a reload doesn't add to
  (at-load-once
   (status-second!))

  (define (status-procs)
    (let ([n (length *procs*)])
      (and (> n 0) (format "⚙ ~a running" n))))

  ;; The heap, and the process's resident memory where the system reports
  ;; it.
  (define (status-memory)
    (let ([heap (/ (bytes-allocated) 1048576.0)]
          [process (platform-process-bytes)])
      (if process
          (format "heap ~,1f · process ~,1f MB" heap (/ process 1048576.0))
          (format "heap ~,1f MB" heap))))

  ;; The longest any tick took, not counting its waits, since the bar last
  ;; read it a second ago; a tick longer than a period was late.
  (define (status-busy) (format "busiest tick ~,1f ms" (pacer-peak-ms!)))

  (define day-names '#("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))

  (define (status-clock)
    (let ([d (current-date)])
      (format "~a ~a ~a   ~2,'0d:~2,'0d:~2,'0d"
              (vector-ref day-names (date-week-day d)) (date-day d)
              (vector-ref ui-month-names (- (date-month d) 1))
              (date-hour d) (date-minute d) (date-second d)))))
