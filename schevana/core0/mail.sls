;;; (schevana core0 mail) — what core0's thread and the world's thread
;;; hand each other, below everything else of core0's: the clock both
;;; read, the boxes one puts into and the other takes from (jobs, frames,
;;; events, the input's times), the wakes that end a wait, and what SDL
;;; last said about the window. It is lock-free except for the waits:
;;; neither side ever waits for the other's work.

(library (schevana core0 mail)
  (export
    core0-clock-ns *core0-jobs* core0-put! core0-take! core0-post!
    *core0-forked* core0-forked? *core0-world-mutex* *core0-ready*
    *core0-woken* *core0-waiting?* *core0-time* core0-world-wake!
    core0-world-wait-ns! core0-wake! core0-wake-event-make! *core0-wake-type*
    *core0-facts* core0-frame-ns core0-display *core0-input-ns*
    *core0-input-pumped* *core0-input-wl* core0-input-set! core0-input-take!)
  (import (chezscheme)
          (only (schevana base) define-made define-state library-layer)
          (only (schevana sdl) sdl-get-ticks-ns sdl-memset sdl-push-event
                sdl-register-events))

  (library-layer core0)

  ;; The monotonic clock in ns, as a fixnum, read from any thread: core0
  ;; times the screen by it, and core1's clock is read from it ((schevana
  ;; core platform)).
  (define (core0-clock-ns) (sdl-get-ticks-ns))

  ;; The jobs posted, newest first, each as (procedure arg ...): core0's
  ;; own code posts them, and core0's step applies each one.
  (define-state *core0-jobs* (box '()))

  ;; Pushes x onto box b's list, so that whatever was written before the
  ;; call is handed over with it.
  (define (core0-put! b x)
    (memory-order-release)
    (let loop ()
      (let ([l (unbox b)]) (unless (box-cas! b l (cons x l)) (loop)))))

  ;; Takes box b's list and returns it, oldest first.
  (define (core0-take! b)
    (let loop ()
      (let ([l (unbox b)])
        (cond [(null? l) l]
              [(box-cas! b l '()) (memory-order-acquire) (reverse l)]
              [else (loop)]))))

  (define (core0-post! job)
    (core0-put! *core0-jobs* job)
    (core0-wake!))

  ;; With a window, core0 runs on the process's first thread and the world
  ;; on a thread of its own, core1; headless, one thread plays both
  ;; ((schevana core0 window)).
  (define-state *core0-forked* #f)
  (define (core0-forked?) *core0-forked*)

  (define-state *core0-world-mutex* (make-mutex))
  (define-state *core0-world-ready* (make-condition))
  (define-state *core0-world-woken* #f)   ; under the mutex
  (define-state *core0-ready* (make-condition))   ; core0's own
  (define-state *core0-woken* #f)                 ; under the mutex
  ;; whether core0 is in SDL's wait for events, under the mutex
  (define-state *core0-waiting?* #f)

  ;; A time record for each thread's timed waits, set again for each wait,
  ;; so that a wait allocates nothing: core1's and core0's.
  (define-made *core0-world-time* (make-time 'time-duration 0 0))
  (define-made *core0-time* (make-time 'time-duration 0 0))

  ;; Ends core1's current wait, or its next one. Called from any thread, in
  ;; a handler's engine too (post-core1!): interrupts are off between the
  ;; lock's two ends, so no engine ends there with the lock held. Nothing is
  ;; allocated.
  (define (core0-world-wake!)
    (when *core0-forked*
      (disable-interrupts)
      (mutex-acquire *core0-world-mutex*)
      (set! *core0-world-woken* #t)
      (condition-signal *core0-world-ready*)
      (mutex-release *core0-world-mutex*)
      (enable-interrupts)))

  ;; Core1 waits up to ns, a fixnum, or with no end when ns is #f; or until
  ;; it is woken. Nothing is allocated.
  (define (core0-world-wait-ns! ns)
    (let ([t *core0-world-time*])
      (when (and ns (fx> ns 0))
        (set-time-second! t (fxquotient ns 1000000000))
        (set-time-nanosecond! t (fxremainder ns 1000000000)))
      (mutex-acquire *core0-world-mutex*)
      (cond
        [(or *core0-world-woken* (and ns (fx<= ns 0))) (void)]
        [ns (condition-wait *core0-world-ready* *core0-world-mutex* t)]
        [else (condition-wait *core0-world-ready* *core0-world-mutex*)])
      (set! *core0-world-woken* #f)
      (mutex-release *core0-world-mutex*)))

  ;; The event that core0-wake! pushes to end SDL's wait, kept, with its
  ;; type, which SDL gives as it starts (core0-wake-event-make!, from
  ;; core0-window-init!); core0's pump passes over it.
  (define-made *core0-wake-event* (foreign-alloc 128))   ; an SDL_Event
  (define-state *core0-wake-type* 0)

  (define (core0-wake-event-make!)
    (set! *core0-wake-type* (sdl-register-events 1))
    (sdl-memset *core0-wake-event* 0 128)
    (foreign-set! 'unsigned-32 *core0-wake-event* 0 *core0-wake-type*))

  ;; Ends core0's current sleep, or its next one, when a job is posted or a
  ;; frame published. Called from any thread, in a handler's engine too,
  ;; with interrupts off as in core0-world-wake!; on core1's thread (without
  ;; a thread of its own), core0 never sleeps. Only an event ends SDL's
  ;; wait, so there the wake's event is pushed.
  (define (core0-wake!)
    (when *core0-forked*
      (disable-interrupts)
      (mutex-acquire *core0-world-mutex*)
      (set! *core0-woken* #t)
      (if *core0-waiting?*
          (sdl-push-event *core0-wake-event*)
          (condition-signal *core0-ready*))
      (mutex-release *core0-world-mutex*)
      (enable-interrupts)))

  ;; What SDL says about the window, as core0 last read it: #(flags w h pw
  ;; ph scale frame-ns display error-text system-theme). It is made again
  ;; whole when it changes, so another thread reads it whole.
  (define-state *core0-facts*
    (vector 0 0 0 0 0 1 (quotient 1000000000 60) #f "" 0))

  ;; How long the screen shows a frame, in ns, and the window's display, as
  ;; core0 last read them.
  (define (core0-frame-ns) (vector-ref *core0-facts* 6))
  (define (core0-display) (vector-ref *core0-facts* 7))

  ;; When the oldest input not yet taken came (in core0-clock-ns, 0 for
  ;; none), in three ways: by SDL's stamp; when core0's pump first saw it;
  ;; and by the compositor's own time, where core0 reads it ((schevana core0
  ;; platform)). Core0's pump sets them and the world takes them with the
  ;; events, both by box-cas!.
  (define-state *core0-input-ns* (box 0))
  (define-state *core0-input-pumped* (box 0))
  (define-state *core0-input-wl* (box 0))

  ;; Puts ns in box b, unless b already holds an older input's time.
  (define (core0-input-set! b ns)
    (let loop ()
      (let ([old (unbox b)])
        (unless (or (not (eqv? old 0)) (box-cas! b old ns))
          (loop)))))

  (define (core0-input-take! b)
    (let loop ()
      (let ([old (unbox b)])
        (if (box-cas! b old 0) old (loop))))))
