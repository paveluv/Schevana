;;; platform.ss — what differs by platform, of the core's: what the host is,
;;; as predicates and facts (the OS and CPU are src/base.ss's, the rest
;;; core0's word in *host-platform*), and what main reads of the system
;;; that each system says its own way. Each is #f where the system doesn't
;;; say. docs/PLATFORMS.md says where each has run.

;; One of core0's facts of the host (src/host/platform.ss), or #f: windowing,
;; gpu-api, gpu-device, sdl, system, kernel, desktop, reports.
(define (host-platform-fact key)
  (let ([f (assq key *host-platform*)]) (and f (cdr f))))

;; The windowing system: 'wayland, 'x11, 'cocoa, 'win32, 'offscreen, or 'none
;; before SDL's start.
(define (host-windowing) (host-platform-fact 'windowing))
(define (host-wayland?) (eq? (host-windowing) 'wayland))
(define (host-x11?) (eq? (host-windowing) 'x11))
(define (host-cocoa?) (eq? (host-windowing) 'cocoa))
(define (host-win32?) (eq? (host-windowing) 'win32))
(define (host-offscreen?) (eq? (host-windowing) 'offscreen))

;; The GPU's API, as SDL drives it: 'vulkan, 'metal, 'direct3d12.
(define (host-gpu-api) (host-platform-fact 'gpu-api))
(define (host-vulkan?) (eq? (host-gpu-api) 'vulkan))
(define (host-metal?) (eq? (host-gpu-api) 'metal))
(define (host-direct3d12?) (eq? (host-gpu-api) 'direct3d12))

;; The predicates by name, each with what it says now: for whoever lists
;; what the host is.
(define (host-predicates)
  `((host-linux? . ,(host-linux?))
    (host-mac? . ,(host-mac?))
    (host-windows? . ,(host-windows?))
    (host-x86-64? . ,(host-x86-64?))
    (host-arm64? . ,(host-arm64?))
    (host-wayland? . ,(host-wayland?))
    (host-x11? . ,(host-x11?))
    (host-cocoa? . ,(host-cocoa?))
    (host-win32? . ,(host-win32?))
    (host-offscreen? . ,(host-offscreen?))
    (host-vulkan? . ,(host-vulkan?))
    (host-metal? . ,(host-metal?))
    (host-direct3d12? . ,(host-direct3d12?))))

;;; ------------------------------------------------------------------
;;; what main reads of the system

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
(define (host-process-bytes)
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
(define (host-machine-load)
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

;;; ------------------------------------------------------------------
;;; the pacer here

;; How fast the pacer's margin fades, ns, or #f: never. A Mac's fades in a
;; minute, as its pacer was measured with (WindowServer). Elsewhere it
;; stays: under Mutter a margin that fades sends a frame late now and then,
;; finding out whether the compositor would take frames later again.
(define platform-pacer-margin-fade (and (host-mac?) 60000000000))
