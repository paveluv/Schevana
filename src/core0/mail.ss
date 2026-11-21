;;; mail.ss — what core0's thread and the world's hand each other, below
;;; all else of core0's: the clock both read, the boxes one puts into and
;;; the other takes from (jobs, frames, events, the input's times), the
;;; wakes that end a wait, and what SDL said of the window last. Lock-free
;;; but for the waits: neither side ever waits for the other's work.

;; The monotonic clock in ns, a fixnum: core0's, and what core1's is read
;; from (src/core1/platform.ss), from any thread. Core1 has a clock of its
;; own, so a test fakes the world's without moving the one core0 times the
;; screen by.
(define (core0-clock-ns) (sdl-get-ticks-ns))
(define (now-ns) (sdl-get-ticks-ns))

;; The jobs the world posted, newest first, each (name arg ...): core0's
;; procedure by name, so a redefinition in "/core0" takes.
(defvar *core0-jobs* (box '()))

;; x onto box b's list, what came before it handed over with it.
(define (core0-put! b x)
  (memory-order-release)
  (let loop ()
    (let ([l (unbox b)]) (unless (box-cas! b l (cons x l)) (loop)))))

;; Box b's list, taken, the oldest first.
(define (core0-take! b)
  (let loop ()
    (let ([l (unbox b)])
      (cond [(null? l) l]
            [(box-cas! b l '()) (memory-order-acquire) (reverse l)]
            [else (loop)]))))

(define (core0-post! job)
  (core0-put! *core0-jobs* job)
  (core0-wake!))

;; With a window core0 runs on the process's first thread and the world
;; on a thread of its own, core1; headless, one thread plays both
;; (src/core0/window.ss).
(defvar *core0-forked* #f)
(define (core0-forked?) *core0-forked*)

(defvar *core0-world-mutex* (make-mutex))
(defvar *core0-world-ready* (make-condition))
(defvar *core0-world-woken* #f)   ; under the mutex
(defvar *core0-ready* (make-condition))   ; core0's own
(defvar *core0-woken* #f)                 ; under the mutex

;; Ends core1's wait, or the next one: from any thread.
(define (core0-world-wake!)
  (when *core0-forked*
    (with-mutex *core0-world-mutex*
      (set! *core0-world-woken* #t)
      (condition-signal *core0-world-ready*))))

;; Core1 waits up to ms, or till it's woken.
(define (core0-world-wait! ms)
  (with-mutex *core0-world-mutex*
    (unless (or *core0-world-woken* (<= ms 0))
      (condition-wait *core0-world-ready* *core0-world-mutex* (core0-ms ms)))
    (set! *core0-world-woken* #f)))

(define (core0-ms ms)
  (make-time 'time-duration (* 1000000 (modulo ms 1000)) (quotient ms 1000)))

;; Ends core0's sleep, or the next one: a job posted, a frame published.
;; From any thread; on core1's own, core0 never sleeps.
(define (core0-wake!)
  (when *core0-forked*
    (with-mutex *core0-world-mutex*
      (set! *core0-woken* #t)
      (condition-signal *core0-ready*))))

;; What SDL says of the window, as core0 read it last: #(flags w h pw ph
;; scale frame-ns display error-text). Made again whole when it changes, so
;; another thread reads it whole.
(defvar *core0-facts* (vector 0 0 0 0 0 1 (quotient 1000000000 60) #f ""))

;; How long the screen shows a frame, ns, and its display, as core0 read
;; them last.
(define (core0-frame-ns) (vector-ref *core0-facts* 6))
(define (core0-display) (vector-ref *core0-facts* 7))

;; When the oldest input not yet taken came (now-ns; 0, none), three ways:
;; by SDL's stamp; when core0's pump first saw it; by the compositor's own
;; time where core0 reads it (src/core0/platform.ss). Core0's pump sets them,
;; the world takes them with the events, both by box-cas!.
(defvar *core0-input-ns* (box 0))
(defvar *core0-input-pumped* (box 0))
(defvar *core0-input-wl* (box 0))

;; Box b holds ns, unless it holds an older input's.
(define (core0-input-set! b ns)
  (let loop ()
    (let ([old (unbox b)])
      (unless (or (not (eqv? old 0)) (box-cas! b old ns))
        (loop)))))

(define (core0-input-take! b)
  (let loop ()
    (let ([old (unbox b)])
      (if (box-cas! b old 0) old (loop)))))
