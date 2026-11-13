;;; core1/platform.ss — what differs by platform, of the core's: which
;;; platform this is, as predicates and facts (the OS and CPU are
;;; src/base.ss's, the rest core0's word in *core0-platform*), and what core1
;;; reads of the system that each system says its own way. Each is #f where
;;; the system doesn't say. docs/PLATFORMS.md says where each has run.

;; One of core0's facts of the platform (src/core0/platform.ss), or #f:
;; windowing, gpu-api, gpu-device, sdl, system, kernel, desktop, reports.
(define (platform-fact key)
  (let ([f (assq key *core0-platform*)]) (and f (cdr f))))

;; The windowing system: 'wayland, 'x11, 'cocoa, 'win32, 'offscreen, or 'none
;; before SDL's start.
(define (platform-windowing) (platform-fact 'windowing))
(define (platform-wayland?) (eq? (platform-windowing) 'wayland))
(define (platform-x11?) (eq? (platform-windowing) 'x11))
(define (platform-cocoa?) (eq? (platform-windowing) 'cocoa))
(define (platform-win32?) (eq? (platform-windowing) 'win32))
(define (platform-offscreen?) (eq? (platform-windowing) 'offscreen))

;; The GPU's API, as SDL drives it: 'vulkan, 'metal, 'direct3d12.
(define (platform-gpu-api) (platform-fact 'gpu-api))
(define (platform-vulkan?) (eq? (platform-gpu-api) 'vulkan))
(define (platform-metal?) (eq? (platform-gpu-api) 'metal))
(define (platform-direct3d12?) (eq? (platform-gpu-api) 'direct3d12))

;; The predicates by name, each with what it says now: for whoever lists
;; which platform this is.
(define (platform-predicates)
  `((platform-linux? . ,(platform-linux?))
    (platform-mac? . ,(platform-mac?))
    (platform-windows? . ,(platform-windows?))
    (platform-x86-64? . ,(platform-x86-64?))
    (platform-arm64? . ,(platform-arm64?))
    (platform-wayland? . ,(platform-wayland?))
    (platform-x11? . ,(platform-x11?))
    (platform-cocoa? . ,(platform-cocoa?))
    (platform-win32? . ,(platform-win32?))
    (platform-offscreen? . ,(platform-offscreen?))
    (platform-vulkan? . ,(platform-vulkan?))
    (platform-metal? . ,(platform-metal?))
    (platform-direct3d12? . ,(platform-direct3d12?))))

;;; ------------------------------------------------------------------
;;; what core1 reads of the system

;; A Mac's: the resident size of a process, from proc_pid_rusage's
;; rusage_info_v0, which holds it after a 16-byte id and six counts.
(define platform-pid-rusage
  (guard (c [#t #f])
    (foreign-procedure "proc_pid_rusage" (int int uptr) int)))
(define platform-getpid
  (guard (c [#t #f]) (foreign-procedure "getpid" () int)))
(define platform-getloadavg
  (guard (c [#t #f]) (foreign-procedure "getloadavg" (uptr int) int)))

;; The process's memory in RAM, bytes: the heap, and what SDL and the
;; drivers hold outside it, which neither reports; #f where the system
;; doesn't say.
(define (platform-process-bytes)
  (cond
    [(file-exists? "/proc/self/status")
     (guard (c [#t #f])
       (call-with-input-file "/proc/self/status"
         (lambda (p)
           (let loop ()
             (let ([l (get-line p)])
               (cond
                 [(eof-object? l) #f]
                 [(string-prefix? "VmRSS:" l)
                  (* 1024 (string->number
                           (list->string (filter char-numeric?
                                                 (string->list l)))))]
                 [else (loop)]))))))]
    [(and platform-pid-rusage platform-getpid)
     (let ([info (foreign-alloc 256)])
       (let ([b (and (= 0 (platform-pid-rusage (platform-getpid) 0 info))
                     (foreign-ref 'unsigned-64 info 64))])
         (foreign-free info)
         b))]
    [else #f]))

;; The machine's load over the last 1, 5 and 15 minutes, as "0.52 0.48
;; 0.40"; #f where the system doesn't say.
(define (platform-machine-load)
  (and platform-getloadavg
       (let ([p (foreign-alloc 24)])
         (let ([n (platform-getloadavg p 3)])
           (let ([load (and (= n 3)
                            (format "~,2f ~,2f ~,2f"
                                    (foreign-ref 'double p 0)
                                    (foreign-ref 'double p 8)
                                    (foreign-ref 'double p 16)))])
             (foreign-free p)
             load)))))

;; The monotonic clock in ns, a fixnum: what the profiler times with.
;; Core1's own, read from core0's (src/core0/ffi.ss), so a test fakes it
;; without moving core0's.
(define (now-ns) (core0-clock-ns))

;; The same clock in ms: what apps and timers go by. It reads the clock
;; itself, so a test can fake either without moving the other.
(define (now-ms) (quotient (core0-clock-ns) 1000000))

;; The CPU time this thread has had, in ns: a number, read into memory
;; kept for it, so that reading it allocates nothing. The clock's number is
;; the system's.
(define thread-cpu-clock
  (if (platform-mac?) 16 3))
(define thread-cpu-time (foreign-alloc 16))   ; a timespec
(define (thread-cpu-ns)
  (c-clock-gettime thread-cpu-clock thread-cpu-time)
  (+ (* 1000000000 (foreign-ref 'long thread-cpu-time 0))
     (foreign-ref 'long thread-cpu-time 8)))

;;; ------------------------------------------------------------------
;;; the pacer here

;; How fast the pacer's margin fades, seconds, or 0: never; the default
;; of its pacer-margin-fade setting. A Mac's fades in a minute, as its
;; pacer was measured with (WindowServer). Elsewhere it stays: under Mutter
;; a margin that fades sends a frame late now and then, finding out
;; whether the compositor would take frames later again.
(define platform-pacer-margin-fade (if (platform-mac?) 60 0))
