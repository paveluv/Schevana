;;; (schevana core platform) — the core's part of what differs by platform:
;;; which platform this is, as predicates and facts (the OS and CPU come from
;;; (schevana base), the rest from core0's *core0-platform*), and what core1
;;; reads of the system where each system answers in its own way. Each
;;; reading is #f where the system doesn't say. docs/PLATFORMS.md says where
;;; each has run.

(library (schevana core platform)
  (export
    platform-fact platform-windowing platform-gpu-api platform-predicates
    platform-process-bytes platform-machine-load now-ns now-ms thread-cpu-ns
    platform-pacer-margin-fade)
  (import (chezscheme)
          (only (schevana base) define-made library-layer platform-arm64?
                platform-linux? platform-mac? platform-windows? platform-x86-64?
                string-prefix?)
          (only (schevana ffi) c-clock-gettime)
          (only (schevana core0) *core0-platform* core0-clock-ns))

  (library-layer core)

  ;; Returns one of core0's facts about the platform ((schevana core0
  ;; platform)), or #f. The keys are windowing, gpu-api, gpu-device, sdl,
  ;; system, kernel, desktop and reports.
  (define (platform-fact key)
    (let ([f (assq key *core0-platform*)]) (and f (cdr f))))

  ;; The windowing system: 'wayland, 'x11, 'cocoa, 'win32 or 'offscreen, or
  ;; 'none before SDL starts.
  (define (platform-windowing) (platform-fact 'windowing))
  (define (platform-wayland?) (eq? (platform-windowing) 'wayland))
  (define (platform-x11?) (eq? (platform-windowing) 'x11))
  (define (platform-cocoa?) (eq? (platform-windowing) 'cocoa))
  (define (platform-win32?) (eq? (platform-windowing) 'win32))
  (define (platform-offscreen?) (eq? (platform-windowing) 'offscreen))

  ;; The GPU API that SDL drives: 'vulkan, 'metal or 'direct3d12, or #f with
  ;; no renderer.
  (define (platform-gpu-api) (platform-fact 'gpu-api))
  (define (platform-vulkan?) (eq? (platform-gpu-api) 'vulkan))
  (define (platform-metal?) (eq? (platform-gpu-api) 'metal))
  (define (platform-direct3d12?) (eq? (platform-gpu-api) 'direct3d12))

  ;; Returns each predicate's name with its value now, for whoever lists
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

  ;; On a Mac, proc_pid_rusage gives the resident size of a process: its
  ;; rusage_info_v0 holds it after a 16-byte id and six counts.
  (define-made platform-pid-rusage
    (guard (c [#t #f])
      (foreign-procedure "proc_pid_rusage" (int int uptr) int)))
  (define-made platform-getpid
    (guard (c [#t #f]) (foreign-procedure "getpid" () int)))
  (define-made platform-getloadavg
    (guard (c [#t #f]) (foreign-procedure "getloadavg" (uptr int) int)))

  ;; Returns the process's memory in RAM, in bytes: the heap and also what
  ;; SDL and the drivers hold outside it (neither of them reports it).
  ;; Returns #f where the system doesn't say.
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

  ;; Returns the machine's load over the last 1, 5 and 15 minutes as a
  ;; string like "0.52 0.48 0.40", or #f where the system doesn't say.
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

  ;; The monotonic clock in ns, as a fixnum, read from core0's clock
  ;; ((schevana core0 mail)). The profiler times with it.
  (define (now-ns) (core0-clock-ns))

  ;; The same clock in ms, which apps and timers go by.
  (define (now-ms) (quotient (core0-clock-ns) 1000000))

  ;; The CPU time this thread has used, in ns. The clock is read into memory
  ;; kept for it, so that a reading allocates nothing. The clock's number
  ;; (CLOCK_THREAD_CPUTIME_ID) differs by system.
  (define-made thread-cpu-clock
    (if (platform-mac?) 16 3))
  (define-made thread-cpu-time (foreign-alloc 16))   ; a timespec
  (define (thread-cpu-ns)
    (c-clock-gettime thread-cpu-clock thread-cpu-time)
    (+ (* 1000000000 (foreign-ref 'long thread-cpu-time 0))
       (foreign-ref 'long thread-cpu-time 8)))

  ;;; ------------------------------------------------------------------
  ;;; the pacer on this platform

  ;; How fast the pacer's margin fades, in seconds, or 0 for never: the
  ;; default of the pacer-margin-fade setting. On a Mac it fades in a
  ;; minute, as the pacer was measured there (under WindowServer). Elsewhere
  ;; it stays: under Mutter a fading margin sends a frame late now and then,
  ;; each time it finds out whether the compositor would take frames later
  ;; again.
  (define-made platform-pacer-margin-fade (if (platform-mac?) 60 0)))
