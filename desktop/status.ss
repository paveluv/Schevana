;;; status.ss — status segments: the right side of the top bar is a list of
;;; (name . thunk); each thunk returns a string (or #f to hide). Add your
;;; own:
;;;   (add-status-segment! 'hello (lambda () "hi!"))

;; the defaults, until you change them (a reload keeps yours)
(defvar *status-segments*
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

;; What the top bar shows: ((name . string-or-#f) ...), taken once a second,
;; each segment under the watchdog.
(defvar *status-shown* '())

(define (refresh-status!)
  (set! *status-shown*
    (map (lambda (s)
           (cons (car s)
                 (safe-call 'status (cdr s)
                            (lambda (c) (format "⚠ ~a" (car s))))))
         *status-segments*)))

(define (shown-status-strings) (filter string? (map cdr *status-shown*)))

(defvar *status-timer?* #f)   ; its timer is set: reloads set no other
(defvar *status-second* #f)   ; the wall clock's second last shown

;; The status taken again, and a frame asked for that shows it.
(define (status-show!)
  (refresh-status!)
  (request-frame!))

;; At the start of each second the status is shown again, the clock's.
;; Frames between, however many something else asks for, show the same:
;; numbers that change every tick, the heap's and the busiest tick's, are
;; read once a second, the busiest that second's. Timers run by the
;; monotonic clock, which may fire this a little before the wall clock's
;; second turns: then it only waits for the turn, showing nothing twice.
(define (status-second!)
  (let ([t (current-time)])
    (unless (eqv? (time-second t) *status-second*)
      (set! *status-second* (time-second t))
      (status-show!))
    (after (- 1000 (quotient (time-nanosecond t) 1000000))
           (lambda () (status-second!)))))

(unless *status-timer?*
  (set! *status-timer?* #t)
  (status-second!))

(define (status-procs)
  (let ([n (length *procs*)])
    (and (> n 0) (format "⚙ ~a running" n))))

;; The heap, and the process's resident memory where the system says it.
(define (status-memory)
  (let ([heap (/ (bytes-allocated) 1048576.0)]
        [process (host-process-bytes)])
    (if process
        (format "~,1f/~,1f MB" heap (/ process 1048576.0))
        (format "~,1f MB" heap))))

;; The most a tick took since the bar last looked, a second ago, but its
;; waits: past a period, a tick was late.
(define (status-busy) (format "~,1f ms/tick" (pacer-peak-ms!)))

(define day-names '#("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))
(define month-names
  '#("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

(define (status-clock)
  (let ([d (current-date)])
    (format "~a ~a ~a   ~2,'0d:~2,'0d:~2,'0d"
            (vector-ref day-names (date-week-day d)) (date-day d)
            (vector-ref month-names (- (date-month d) 1))
            (date-hour d) (date-minute d) (date-second d))))
