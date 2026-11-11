;;; platform.ss — what differs by platform, of core0's: what the host is, as
;;; core0 learns it once SDL and the GPU start (*host-platform*), and the
;;; screen's reports where a platform gives them (Wayland's here). Each
;;; thing a platform may lack is found by asking (a library that loads, an
;;; entry SDL has, a global the compositor lists) and is off without it.
;;; docs/PLATFORMS.md says where each has run.

;; An entry of C's, or #f where this platform's libraries lack it.
(define-syntax define-optional-foreign
  (syntax-rules ()
    [(_ name form) (define name (guard (c [#t #f]) form))]))

;; s in C's memory, kept for good.
(define (platform-c-string s)
  (let* ([b (string->utf8 s)] [n (bytevector-length b)]
         [p (foreign-alloc (+ n 1))])
    (do ([i 0 (+ i 1)]) ((= i n))
      (foreign-set! 'unsigned-8 p i (bytevector-u8-ref b i)))
    (foreign-set! 'unsigned-8 p n 0)
    p))

;; The string C's memory holds at p, to its first nul.
(define (platform-c->string p)
  (let loop ([i 0] [acc '()])
    (let ([b (foreign-ref 'unsigned-8 p i)])
      (if (= b 0)
          (utf8->string (u8-list->bytevector (reverse acc)))
          (loop (+ i 1) (cons b acc))))))

;;; ------------------------------------------------------------------
;;; what the host is

;; The system's name and version, the kernel's, where the system says them.
(define-optional-foreign platform-uname
  (foreign-procedure "uname" (uptr) int))
(define-optional-foreign platform-sysctl
  (foreign-procedure "sysctlbyname" (string uptr uptr uptr size_t) int))
;; SDL 3.4's: the GPU's name and driver
(define-optional-foreign platform-gpu-properties
  (foreign-procedure "SDL_GetGPUDeviceProperties" (uptr) unsigned-32))

;; The kernel, as "Linux 6.12.1": uname's sysname and release (its first
;; and third fields), 65 bytes long on Linux and 256 on a Mac.
(define (platform-kernel)
  (and platform-uname
       (let* ([n (if (host-mac?) 256 65)] [p (foreign-alloc (* 6 n))])
         (let ([k (and (= 0 (platform-uname p))
                       (format "~a ~a" (platform-c->string p)
                               (platform-c->string (+ p (* 2 n)))))])
           (foreign-free p)
           k))))

;; The system, as its maker names it: os-release's on Linux, the product's
;; version on a Mac.
(define (platform-system)
  (cond
    [(file-exists? "/etc/os-release")
     (call-with-input-file "/etc/os-release"
       (lambda (in)
         (let loop ()
           (let ([l (get-line in)])
             (cond [(eof-object? l) #f]
                   [(string-prefix? "PRETTY_NAME=" l)
                    (let ([v (substring l 12 (string-length l))])
                      (if (and (> (string-length v) 1)
                               (char=? (string-ref v 0) #\"))
                          (substring v 1 (- (string-length v) 1))
                          v))]
                   [else (loop)])))))]
    [platform-sysctl
     (let ([p (foreign-alloc 64)] [n (foreign-alloc 8)])
       (foreign-set! 'size_t n 0 64)
       (let ([v (and (= 0 (platform-sysctl "kern.osproductversion" p n 0 0))
                     (format "macOS ~a" (platform-c->string p)))])
         (foreign-free p)
         (foreign-free n)
         v))]
    [else #f]))

;; SDL's version, as "3.2.10".
(define (platform-sdl-version)
  (let ([v (sdl-get-version)])
    (format "~a.~a.~a" (quotient v 1000000) (remainder (quotient v 1000) 1000)
            (remainder v 1000))))

;; The GPU device as SDL says it, (name driver version info), or #f before
;; SDL 3.4.
(define (platform-gpu-device)
  (and platform-gpu-properties *renderer*
       (let ([props (platform-gpu-properties (renderer-device *renderer*))]
             [get (lambda (props key)
                    (sdl-get-string-property
                     props (string-append "SDL.gpu.device." key) #f))])
         (and (not (eqv? props 0))
              (map (lambda (key) (get props key))
                   '("name" "driver_name" "driver_version" "driver_info"))))))

;; What core0 knows of the host, an alist it sets whole: the world reads it
;; (src/platform.ss), never asking SDL itself.
(defvar *host-platform* '())

(define (host-platform-read!)
  (let ([video (sdl-get-current-video-driver)])
    (set! *host-platform*
      `((windowing
         . ,(cond [(not video) 'none]
                  [(string=? video "windows") 'win32]
                  [else (string->symbol video)]))
        (gpu-api . ,(and *renderer* (string->symbol (gpu-driver-name))))
        (gpu-device . ,(platform-gpu-device))
        (sdl . ,(platform-sdl-version))
        (system . ,(platform-system))
        (kernel . ,(platform-kernel))
        ;; the session's word for its desktop: a hint, not the compositor's
        (desktop . ,(getenv "XDG_CURRENT_DESKTOP"))
        (reports . ,(platform-reports))))))

;;; ------------------------------------------------------------------
;;; the screen's reports
;;; When each frame reached the screen, in present.ss's ring
;;; (present-reported!). Wayland's wp_presentation is the one source so far.

;; Ask the screen to report on frame, sent next.
(define (platform-report-ask! frame)
  (unless (eqv? *wayland-presentation* 0)
    (with-interrupts-disabled
     (let ([proxy (wayland-marshal-2 *wayland-presentation* 1
                                     wayland-feedback-interface 1 0
                                     *wayland-surface* 0)])
       (wayland-add-listener proxy wayland-feedback-listener frame)))))

;; Reports from now on for the window, where its platform gives them.
(define (platform-reports-start! sdl-window)
  (wayland-start! sdl-window)
  (host-platform-read!))

;; The reports come since the last look, without waiting.
(define (platform-reports-pump!)
  (unless (eqv? *wayland-queue* 0)
    (with-interrupts-disabled
     (wayland-dispatch *wayland-display* *wayland-queue*))))

;; Where the reports come from, as a person reads it: (source clock clock
;; flags), the clock the compositor says and the one its times fit; or #f
;; with none.
(define (platform-reports)
  (and (not (eqv? *wayland-presentation* 0))
       (list 'wayland-presentation
             (platform-clock-name *wayland-clock*)
             (platform-clock-name *wayland-used*)
             (platform-report-flags *wayland-flags*))))

;; ns to add to a time on clock (a POSIX clock's number) for now-ns's, read
;; at each report: two clocks may drift apart by a few ms an hour.
(defvar *platform-timespec* (foreign-alloc 16))
(define (platform-clock-offset clock)
  (let ([ts *platform-timespec*])
    (c-clock-gettime clock ts)
    (- (now-ns)
       (+ (* 1000000000 (foreign-ref 'long ts 0)) (foreign-ref 'long ts 8)))))

;; Linux's clocks by number.
(define (platform-clock-name clock)
  (case clock
    [(0) 'realtime]
    [(1) 'monotonic]
    [(4) 'monotonic-raw]
    [(7) 'boottime]
    [(#f) #f]
    [else clock]))

;; wp_presentation_feedback's flags by name: tied to a refresh, the time
;; from the display's clock, its completion signaled, scanned out as is.
(define (platform-report-flags flags)
  (filter values
          (map (lambda (bit name) (and (logtest flags bit) name))
               '(1 2 4 8)
               '(vsync hw-clock hw-completion zero-copy))))

;;; ---- Wayland's
;;; wp_presentation through libwayland-client, on SDL's display and the
;;; window's surface, its events on a queue of core0's own, read after each
;;; pump without waiting. Its callbacks run with interrupts off, so that no
;;; engine's timer leaves through a C frame.

(define wayland-loaded?
  (guard (c [#t #f]) (load-shared-object "libwayland-client.so.0") #t))

(define-syntax define-wayland
  (syntax-rules ()
    [(_ name form) (define name (and wayland-loaded? form))]))

(define-wayland wayland-marshal-1
  (foreign-procedure (__varargs_after 5) "wl_proxy_marshal_flags"
    (uptr unsigned-32 uptr unsigned-32 unsigned-32 uptr) uptr))
(define-wayland wayland-marshal-2
  (foreign-procedure (__varargs_after 5) "wl_proxy_marshal_flags"
    (uptr unsigned-32 uptr unsigned-32 unsigned-32 uptr uptr) uptr))
(define-wayland wayland-marshal-bind
  (foreign-procedure (__varargs_after 5) "wl_proxy_marshal_flags"
    (uptr unsigned-32 uptr unsigned-32 unsigned-32 unsigned-32 uptr
     unsigned-32 uptr) uptr))
(define-wayland wayland-add-listener
  (foreign-procedure "wl_proxy_add_listener" (uptr uptr uptr) int))
(define-wayland wayland-destroy
  (foreign-procedure "wl_proxy_destroy" (uptr) void))
(define-wayland wayland-set-queue
  (foreign-procedure "wl_proxy_set_queue" (uptr uptr) void))
(define-wayland wayland-version
  (foreign-procedure "wl_proxy_get_version" (uptr) unsigned-32))
(define-wayland wayland-create-queue
  (foreign-procedure "wl_display_create_queue" (uptr) uptr))
(define-wayland wayland-roundtrip
  (foreign-procedure "wl_display_roundtrip_queue" (uptr uptr) int))
(define-wayland wayland-dispatch
  (foreign-procedure "wl_display_dispatch_queue_pending" (uptr uptr) int))

(define-ftype wayland-message
  (struct [name void*] [signature void*] [types void*]))
(define-ftype wayland-interface
  (struct [name void*] [version int] [method-count int] [methods void*]
          [event-count int] [events void*]))

;; Eight null types, for messages whose arguments name no interface.
(define wayland-nulls
  (and wayland-loaded?
       (let ([p (foreign-alloc 64)])
         (do ([i 0 (+ i 8)]) ((= i 64)) (foreign-set! 'uptr p i 0))
         p)))

;; An array of messages, each (name signature types).
(define (wayland-messages specs)
  (let* ([size (ftype-sizeof wayland-message)]
         [p (foreign-alloc (max 1 (* size (length specs))))])
    (for-each
     (lambda (spec i)
       (let ([m (make-ftype-pointer wayland-message (+ p (* i size)))])
         (ftype-set! wayland-message (name) m (platform-c-string (car spec)))
         (ftype-set! wayland-message (signature) m
                     (platform-c-string (cadr spec)))
         (ftype-set! wayland-message (types) m (caddr spec))))
     specs (iota (length specs)))
    p))

(define (wayland-interface-new name version methods events)
  (let* ([p (foreign-alloc (ftype-sizeof wayland-interface))]
         [i (make-ftype-pointer wayland-interface p)])
    (ftype-set! wayland-interface (name) i (platform-c-string name))
    (ftype-set! wayland-interface (version) i version)
    (ftype-set! wayland-interface (method-count) i (length methods))
    (ftype-set! wayland-interface (methods) i (wayland-messages methods))
    (ftype-set! wayland-interface (event-count) i (length events))
    (ftype-set! wayland-interface (events) i (wayland-messages events))
    p))

(define wayland-feedback-interface
  (and wayland-loaded?
       (wayland-interface-new "wp_presentation_feedback" 1 '()
         (list (list "sync_output" "o" wayland-nulls)
               (list "presented" "uuuuuuu" wayland-nulls)
               (list "discarded" "" wayland-nulls)))))

(define wayland-presentation-interface
  (and wayland-loaded?
       (let ([types (foreign-alloc 16)])
         (foreign-set! 'uptr types 0 (foreign-entry "wl_surface_interface"))
         (foreign-set! 'uptr types 8 wayland-feedback-interface)
         (wayland-interface-new "wp_presentation" 1
           (list (list "destroy" "" wayland-nulls)
                 (list "feedback" "on" types))
           (list (list "clock_id" "u" wayland-nulls))))))

;; The display, the surface, our queue and wp_presentation bound on it, or
;; 0; the clock the compositor reports by, as it says (#f till it has), and
;; the one its times fit; the last report's flags.
(defvar *wayland-display* 0)
(defvar *wayland-surface* 0)
(defvar *wayland-queue* 0)
(defvar *wayland-presentation* 0)
(defvar *wayland-clock* #f)
(defvar *wayland-used* #f)
(defvar *wayland-flags* 0)
(defvar *wayland-found* #f)   ; wp_presentation's (name . version)

(define-syntax define-wayland-callback
  (syntax-rules ()
    [(_ name handler (type ...))
     (define name
       (and wayland-loaded?
            (let ([code (foreign-callable handler (type ...) void)])
              (lock-object code)
              (foreign-callable-entry-point code))))]))

;; presented: tv_sec high and low, ns, refresh, sequence high and low, flags
(define-wayland-callback wayland-shown-code
  (lambda (frame proxy sec-hi sec-lo nsec refresh seq-hi seq-lo flags)
    (present-reported!
     frame 1
     (wayland-shown-ns frame
                       (+ (* 1000000000 (+ (* sec-hi 4294967296) sec-lo))
                          nsec))
     refresh
     (+ (* seq-hi 4294967296) seq-lo))
    (host-trace! 10 frame)
    (wayland-destroy proxy)
    (unless (eqv? flags *wayland-flags*)
      (set! *wayland-flags* flags)
      (host-platform-read!)))
  (uptr uptr unsigned-32 unsigned-32 unsigned-32 unsigned-32 unsigned-32
   unsigned-32 unsigned-32))
(define-wayland-callback wayland-dropped-code
  (lambda (frame proxy)
    (present-reported! frame 2 0 0 0)
    (host-trace! 11 frame)
    (wayland-destroy proxy))
  (uptr uptr))
(define-wayland-callback wayland-output-code
  (lambda (frame proxy output) (void))
  (uptr uptr uptr))
(define-wayland-callback wayland-clock-code
  (lambda (data proxy clock)
    (set! *wayland-clock* clock)
    (set! *wayland-used* clock))
  (uptr uptr unsigned-32))

;; A report's time t, on now-ns's clock. A frame shows after it's sent, and
;; within a second: a compositor whose times break that on the clock it
;; says (GNOME's with NVIDIA's vblank stamps, on CLOCK_MONOTONIC_RAW) is
;; read on the first of Linux's clocks that fits.
(define (wayland-shown-ns frame t)
  (let ([sent (fxvector-ref *present-ring* (fx+ (present-at frame) 2))]
        [on (lambda (clock) (+ t (platform-clock-offset clock)))])
    (define (fits? clock)
      (<= (- sent 1000000) (on clock) (+ sent 1000000000)))
    (unless (fits? *wayland-used*)
      (let ([clock (find fits? (list *wayland-clock* 4 1 7 0))])
        (when clock
          (set! *wayland-used* clock)
          (host-platform-read!))))
    (on *wayland-used*)))
(define-wayland-callback wayland-global-code
  (lambda (data registry name interface version)
    (when (string=? (platform-c->string interface) "wp_presentation")
      (set! *wayland-found* (cons name version))))
  (uptr uptr unsigned-32 uptr unsigned-32))
(define-wayland-callback wayland-global-gone-code
  (lambda (data registry name) (void))
  (uptr uptr unsigned-32))

;; A listener: its callbacks' entry points, in its events' order.
(define (wayland-listener . entries)
  (and wayland-loaded?
       (let ([p (foreign-alloc (* 8 (length entries)))])
         (for-each (lambda (e i) (foreign-set! 'uptr p (* 8 i) e))
                   entries (iota (length entries)))
         p)))

(define wayland-feedback-listener
  (wayland-listener wayland-output-code wayland-shown-code
                    wayland-dropped-code))
(define wayland-presentation-listener (wayland-listener wayland-clock-code))
(define wayland-registry-listener
  (wayland-listener wayland-global-code wayland-global-gone-code))

;; wp_presentation bound for the window, when it lives on Wayland and the
;; compositor has it; and the clock it reports by, which it says at once.
(define (wayland-start! sdl-window)
  (when wayland-loaded?
    (let* ([props (sdl-get-window-properties sdl-window)]
           [display (sdl-get-pointer-property
                     props "SDL.window.wayland.display" 0)]
           [wl-surface (sdl-get-pointer-property
                        props "SDL.window.wayland.surface" 0)])
      (unless (or (eqv? display 0) (eqv? wl-surface 0))
        (with-interrupts-disabled
         (set! *wayland-display* display)
         (set! *wayland-surface* wl-surface)
         (set! *wayland-queue* (wayland-create-queue display))
         (let ([registry (wayland-marshal-1
                          display 1 (foreign-entry "wl_registry_interface")
                          (wayland-version display) 0 0)])
           (wayland-set-queue registry *wayland-queue*)
           (wayland-add-listener registry wayland-registry-listener 0)
           (wayland-roundtrip display *wayland-queue*)
           (when *wayland-found*
             (let ([p (wayland-marshal-bind
                       registry 0 wayland-presentation-interface 1 0
                       (car *wayland-found*)
                       (platform-c-string "wp_presentation") 1 0)])
               (wayland-add-listener p wayland-presentation-listener 0)
               (wayland-roundtrip display *wayland-queue*)
               ;; no report till the clock is known
               (when *wayland-clock*
                 (set! *wayland-presentation* p))))))))))
