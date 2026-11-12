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
;;; (present-reported!): Wayland's wp_presentation, and Metal's presented
;;; handlers on the Mac.

;; Ask the screen to report on frame, sent next.
(define (platform-report-ask! frame)
  (cond
    [(not (eqv? *wayland-presentation* 0))
     (with-interrupts-disabled
      (let ([proxy (wayland-marshal-2 *wayland-presentation* 1
                                      wayland-feedback-interface 1 0
                                      *wayland-surface* 0)])
        (wayland-add-listener proxy wayland-feedback-listener frame)))]
    [(not (eqv? *mac-layer* 0)) (mac-ask! frame)]))

;; Reports from now on for the window, where its platform gives them.
(define (platform-reports-start! sdl-window)
  (wayland-start! sdl-window)
  (mac-start! sdl-window)
  (host-platform-read!))

;; The reports come since the last look, without waiting.
(define (platform-reports-pump!)
  (unless (eqv? *wayland-queue* 0)
    (with-interrupts-disabled
     (wayland-dispatch *wayland-display* *wayland-queue*)))
  (unless (eqv? *mac-layer* 0) (mac-pump!)))

;; Where the reports come from, as a person reads it: (source clock clock
;; flags), the clock the compositor says and the one its times fit; or #f
;; with none.
(define (platform-reports)
  (cond
    [(not (eqv? *wayland-presentation* 0))
     (list 'wayland-presentation
           (platform-clock-name *wayland-clock*)
           (platform-clock-name *wayland-used*)
           (platform-report-flags *wayland-flags*))]
    ;; Metal says its clock is the host's, mach_absolute_time's
    [(not (eqv? *mac-layer* 0))
     (list 'metal-presented-handler 'uptime-raw 'uptime-raw '())]
    [else #f]))

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
(defvar *wayland-seat-found* #f)   ; the seat's name
(defvar *wayland-pointer* 0)
(defvar *wayland-keyboard* 0)
(defvar *wayland-input-clock* #f)   ; the clock input's times fit

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
  (let ([sent (fxvector-ref *present-ring* (fx+ (present-at frame) 2))])
    (unless (platform-fits? t *wayland-used* (- sent 1000000)
                            (+ sent 1000000000))
      (let ([clock (platform-fitting t *wayland-clock* (- sent 1000000)
                                     (+ sent 1000000000))])
        (when clock
          (set! *wayland-used* clock)
          (host-platform-read!))))
    (+ t (platform-clock-offset *wayland-used*))))

;; Whether time t on clock falls from low to high on now-ns's; the first of
;; said and Linux's clocks on which it does, or #f. Numbers alone: no
;; allocation a report or an input.
(define (platform-fits? t clock low high)
  (and clock (<= low (+ t (platform-clock-offset clock)) high)))
(define (platform-fitting t said low high)
  (cond [(platform-fits? t said low high) said]
        [(platform-fits? t 4 low high) 4]
        [(platform-fits? t 1 low high) 1]
        [(platform-fits? t 7 low high) 7]
        [(platform-fits? t 0 low high) 0]
        [else #f]))

;; An input's time, its event's ms on the compositor's clock (which wraps
;; at 32 bits), as core0 reads the event at now-ns at: on the clock under
;; which it came within the last second, to the ms. Into the oldest not
;; yet taken (host-input-set!).
(define (wayland-input! ms)
  (let* ([at (now-ns)]
         [t (or (wayland-input-on *wayland-input-clock* ms at)
                (wayland-input-on 1 ms at)
                (wayland-input-on 4 ms at)
                (wayland-input-on 7 ms at))])
    (when t (host-input-set! *host-input-wl* t))))

;; ms, read on clock and kept as the clock it fits, on now-ns's; or #f.
(define (wayland-input-on clock ms at)
  (and clock
       (let* ([off (platform-clock-offset clock)]
              [now-ms (quotient (- at off) 1000000)]
              [t (+ off (* 1000000 (- now-ms (modulo (- now-ms ms)
                                                      4294967296))))])
         (and (<= (- at 1000000000) t (+ at 1000000))
              (begin (set! *wayland-input-clock* clock) t)))))
(define-wayland-callback wayland-global-code
  (lambda (data registry name interface version)
    (let ([named (platform-c->string interface)])
      (cond [(string=? named "wp_presentation")
             (set! *wayland-found* (cons name version))]
            [(and (string=? named "wl_seat") (not *wayland-seat-found*))
             (set! *wayland-seat-found* name)])))
  (uptr uptr unsigned-32 uptr unsigned-32))

;; The seat's pointer and keyboard of core0's own, version 1, for their
;; events' times alone: the same events SDL reads, on core0's queue.
(define-wayland-callback wayland-seat-code
  (lambda (data seat caps)
    (when (and (logtest caps 1) (eqv? *wayland-pointer* 0))
      (set! *wayland-pointer*
        (wayland-marshal-1 seat 0 (foreign-entry "wl_pointer_interface") 1 0
                           0))
      (wayland-add-listener *wayland-pointer* wayland-pointer-listener 0))
    (when (and (logtest caps 2) (eqv? *wayland-keyboard* 0))
      (set! *wayland-keyboard*
        (wayland-marshal-1 seat 1 (foreign-entry "wl_keyboard_interface") 1 0
                           0))
      (wayland-add-listener *wayland-keyboard* wayland-keyboard-listener 0)))
  (uptr uptr unsigned-32))
;; pointer: enter, leave, motion, button, axis
(define-wayland-callback wayland-enter-code
  (lambda (data p serial wl-surface x y) (void))
  (uptr uptr unsigned-32 uptr int int))
(define-wayland-callback wayland-leave-code
  (lambda (data p serial wl-surface) (void))
  (uptr uptr unsigned-32 uptr))
(define-wayland-callback wayland-motion-code
  (lambda (data p ms x y) (wayland-input! ms))
  (uptr uptr unsigned-32 int int))
(define-wayland-callback wayland-button-code
  (lambda (data p serial ms button state) (wayland-input! ms))
  (uptr uptr unsigned-32 unsigned-32 unsigned-32 unsigned-32))
(define-wayland-callback wayland-axis-code
  (lambda (data p ms axis value) (wayland-input! ms))
  (uptr uptr unsigned-32 unsigned-32 int))
;; keyboard: keymap (its file closed: SDL has its own), enter, leave, key,
;; modifiers
(define-wayland-callback wayland-keymap-code
  (lambda (data k format fd size) (c-close fd))
  (uptr uptr unsigned-32 int unsigned-32))
(define-wayland-callback wayland-keys-code
  (lambda (data k serial wl-surface keys) (void))
  (uptr uptr unsigned-32 uptr uptr))
(define-wayland-callback wayland-key-code
  (lambda (data k serial ms key state) (wayland-input! ms))
  (uptr uptr unsigned-32 unsigned-32 unsigned-32 unsigned-32))
(define-wayland-callback wayland-modifiers-code
  (lambda (data k serial depressed latched locked group) (void))
  (uptr uptr unsigned-32 unsigned-32 unsigned-32 unsigned-32 unsigned-32))
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
(define wayland-seat-listener (wayland-listener wayland-seat-code))
(define wayland-pointer-listener
  (wayland-listener wayland-enter-code wayland-leave-code wayland-motion-code
                    wayland-button-code wayland-axis-code))
(define wayland-keyboard-listener
  (wayland-listener wayland-keymap-code wayland-keys-code wayland-leave-code
                    wayland-key-code wayland-modifiers-code))

;; wp_presentation bound for the window, when it lives on Wayland and the
;; compositor has it, and the clock it reports by, which it says at once;
;; and the seat, for the input's own times.
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
           (when *wayland-seat-found*
             (wayland-add-listener
              (wayland-marshal-bind
               registry 0 (foreign-entry "wl_seat_interface") 1 0
               *wayland-seat-found* (platform-c-string "wl_seat") 1 0)
              wayland-seat-listener 0))
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

;;; ---- the frame's threads
;;; On a Mac the OS's main thread, core0's, runs at the user-interactive
;;; class; a thread forked starts at the default one, which Apple silicon
;;; may run on an efficiency core and wake late, and main's ticks that
;;; woke late sent frames past their latch. So main asks for core0's
;;; class. Elsewhere, nothing yet.

(define mac-system-loaded?
  (and (host-mac?)
       (guard (c [#t #f])
         (load-shared-object "/usr/lib/libSystem.B.dylib")
         #t)))

;; QOS_CLASS_USER_INTERACTIVE
(define mac-class-interactive #x21)

;; The calling thread at the class core0's runs at, where the OS has one.
(define (platform-thread-interactive!)
  (when mac-system-loaded?
    ((foreign-procedure "pthread_set_qos_class_self_np" (unsigned-int int)
                        int)
     mac-class-interactive 0)))

;; The calling thread's class, as the OS says (a Mac's QOS_CLASS_…); or
;; #f where there's none.
(define (platform-thread-class)
  (and mac-system-loaded?
       ((foreign-procedure "qos_class_self" () unsigned-int))))

;;; ---- the Mac's
;;; Metal calls a drawable's presented handlers when it was shown, or
;;; never will be: its presentedTime, seconds on the host's clock
;;; (mach_absolute_time's, CLOCK_UPTIME_RAW), 0 for never. SDL takes each
;;; drawable from its layer in its acquire and presents it at the submit,
;;; and hands us none; so the one layer it draws to becomes a class of
;;; core0's own, made once, whose nextDrawable is CAMetalLayer's and gives
;;; what it returns our handler, there on core0's thread, inside SDL's
;;; acquire. The handler runs on a thread of Apple's: it writes only a ring
;;; of its own, by the drawable's number, which core0 reads at each pump
;;; for the frames it sent. Keeping the drawables to read them later would
;;; keep them from the layer's pool, which holds three.

(define mac-objc-loaded?
  (and (host-mac?)
       (guard (c [#t #f])
         (load-shared-object "/usr/lib/libobjc.A.dylib")
         #t)))

(define-syntax define-objc
  (syntax-rules ()
    [(_ name form) (define name (and mac-objc-loaded? form))]))

(define-objc objc-class (foreign-procedure "objc_getClass" (string) uptr))
(define-objc objc-selector
  (foreign-procedure "sel_registerName" (string) uptr))
(define-objc objc-class-of (foreign-procedure "object_getClass" (uptr) uptr))
(define-objc objc-class-set!
  (foreign-procedure "object_setClass" (uptr uptr) uptr))
(define-objc objc-subclass
  (foreign-procedure "objc_allocateClassPair" (uptr uptr size_t) uptr))
(define-objc objc-subclass-done!
  (foreign-procedure "objc_registerClassPair" (uptr) void))
(define-objc objc-method-add!
  (foreign-procedure "class_addMethod" (uptr uptr uptr uptr) unsigned-8))
(define-objc objc-method
  (foreign-procedure "class_getMethodImplementation" (uptr uptr) uptr))
;; objc_msgSend, as each message's types call it
(define-objc objc-send (foreign-procedure "objc_msgSend" (uptr uptr) uptr))
(define-objc objc-send-long
  (foreign-procedure "objc_msgSend" (uptr uptr long) uptr))
(define-objc objc-send-double
  (foreign-procedure "objc_msgSend" (uptr uptr) double))
;; Collect-safe, for core0 inside nextDrawable: Core Animation's lock that
;; a drawable's messages take is held by its thread while it runs our
;; handler, which may wait for a collection, which can't wait for core0
;; blocked on that lock.
(define-objc objc-send-safe
  (foreign-procedure __collect_safe "objc_msgSend" (uptr uptr) uptr))
(define-objc objc-send-pointer-safe
  (foreign-procedure __collect_safe "objc_msgSend" (uptr uptr uptr) void))

(define-objc mac-next-selector (objc-selector "nextDrawable"))
(define-objc mac-id-selector (objc-selector "drawableID"))
(define-objc mac-time-selector (objc-selector "presentedTime"))
(define-objc mac-handler-selector (objc-selector "addPresentedHandler:"))

;; The handlers' ring: a row a drawable, by its number (drawableID, which
;; counts up from 0 on each layer): that number plus one (0, none yet), and
;; when it was shown (ns on the host's clock; 0, never). Only the handlers
;; write it, the number last.
(define mac-rows 64)
(defvar *mac-shown* (make-fxvector (* 2 mac-rows) 0))

;; On Apple's thread: the drawable's word, into its row.
(define (mac-presented! drawable)
  (let* ([id (objc-send drawable mac-id-selector)]
         [t (objc-send-double drawable mac-time-selector)]
         [at (fx* 2 (fxmodulo id mac-rows))])
    (fxvector-set! *mac-shown* (fx+ at 1)
                   (if (fl> t 0.0) (flonum->fixnum (flround (fl* t 1e9))) 0))
    (memory-order-release)
    (fxvector-set! *mac-shown* at (fx+ id 1))))

;; Collect-safe: Chez makes the thread of Apple's that calls it one of its
;; own for the call.
(define mac-handler-code
  (and mac-objc-loaded?
       (let ([code (foreign-callable __collect_safe
                     (lambda (block drawable) (mac-presented! drawable))
                     (uptr uptr) void)])
         (lock-object code)
         (foreign-callable-entry-point code))))

;; The handler as a block: a global one (flag 1 << 28), which copying and
;; releasing leave as it is, with its signature (1 << 30). Never freed.
(define mac-handler-block
  (and mac-objc-loaded?
       (let ([b (foreign-alloc 32)] [d (foreign-alloc 24)])
         (foreign-set! 'unsigned-64 d 0 0)
         (foreign-set! 'unsigned-64 d 8 32)
         (foreign-set! 'uptr d 16 (platform-c-string "v16@?0@8"))
         (foreign-set! 'uptr b 0 (foreign-entry "_NSConcreteGlobalBlock"))
         (foreign-set! 'integer-32 b 8 (+ (expt 2 28) (expt 2 30)))
         (foreign-set! 'integer-32 b 12 0)
         (foreign-set! 'uptr b 16 mac-handler-code)
         (foreign-set! 'uptr b 24 d)
         b)))

;; SDL's layer, of core0's class now (0, none); CAMetalLayer's own
;; nextDrawable, collect-safe, as the pool may hold it a refresh; and the
;; number of the drawable the acquire running now was given (-1, none).
(defvar *mac-layer* 0)
(defvar *mac-next-drawable* #f)
(defvar *mac-drawable* -1)

;; nextDrawable, as core0's class has it: the layer's own, and the drawable
;; it returns given our handler.
(define mac-next-code
  (and mac-objc-loaded?
       (let ([code (foreign-callable __collect_safe
                     (lambda (layer cmd)
                       (let ([d (*mac-next-drawable* layer cmd)])
                         (if (eqv? d 0)
                             (set! *mac-drawable* -1)
                             (begin
                               (objc-send-pointer-safe d mac-handler-selector
                                                       mac-handler-block)
                               (set! *mac-drawable*
                                 (objc-send-safe d mac-id-selector))))
                         d))
                     (uptr uptr) uptr)])
         (lock-object code)
         (foreign-callable-entry-point code))))

;; Core0's subclass of CAMetalLayer, made once a process.
(define (mac-layer-class metal)
  (let ([own (objc-class "SchevanaMetalLayer")])
    (if (eqv? own 0)
        (let ([c (objc-subclass metal (platform-c-string "SchevanaMetalLayer")
                                0)])
          (objc-method-add! c mac-next-selector mac-next-code
                            (platform-c-string "@16@0:8"))
          (objc-subclass-done! c)
          c)
        own)))

;; The layer SDL draws to, found by its view's tag in the window, of core0's
;; class from now on: only one of CAMetalLayer's own class, not one another
;; has given its own (KVO does).
(define (mac-start! sdl-window)
  (when (and mac-objc-loaded? (eqv? *mac-layer* 0))
    (let* ([props (sdl-get-window-properties sdl-window)]
           [nswindow (sdl-get-pointer-property
                      props "SDL.window.cocoa.window" 0)]
           [tag (sdl-get-number-property
                 props "SDL.window.cocoa.metal_view_tag" 0)]
           [metal (objc-class "CAMetalLayer")]
           [content (if (eqv? nswindow 0)
                        0
                        (objc-send nswindow (objc-selector "contentView")))]
           [view (if (or (eqv? content 0) (eqv? tag 0))
                     0
                     (objc-send-long content (objc-selector "viewWithTag:")
                                     tag))]
           [layer (if (eqv? view 0)
                      0
                      (objc-send view (objc-selector "layer")))])
      (when (and (not (eqv? layer 0)) (not (eqv? metal 0))
                 (eqv? (objc-class-of layer) metal))
        (set! *mac-next-drawable*
          (foreign-procedure __collect_safe
            (objc-method metal mac-next-selector) (uptr uptr) uptr))
        (objc-class-set! layer (mac-layer-class metal))
        (set! *mac-layer* layer)))))

;; The frames sent and not reported on yet, each with its drawable's
;; number, a row a frame by its number (-1, none): core0's alone.
(define mac-waiting-rows 8)
(defvar *mac-waiting* (make-fxvector (* 2 mac-waiting-rows) -1))

;; Frame, sent next, waits for its drawable's report.
(define (mac-ask! frame)
  (unless (fx= *mac-drawable* -1)
    (let ([at (fx* 2 (fxmodulo frame mac-waiting-rows))])
      (fxvector-set! *mac-waiting* at frame)
      (fxvector-set! *mac-waiting* (fx+ at 1) *mac-drawable*))
    (set! *mac-drawable* -1)))

;; The reports the handlers wrote since the last look.
(define (mac-pump!)
  (let ([w *mac-waiting*] [s *mac-shown*])
    (do ([i 0 (fx+ i 2)]) ((fx= i (fx* 2 mac-waiting-rows)))
      (let ([frame (fxvector-ref w i)] [id (fxvector-ref w (fx+ i 1))])
        (unless (fx< frame 0)
          (let ([at (fx* 2 (fxmodulo id mac-rows))])
            (when (fx= (fxvector-ref s at) (fx+ id 1))
              (memory-order-acquire)
              (mac-reported! frame (fxvector-ref s (fx+ at 1)))
              (fxvector-set! w i -1))))))))

;; The display's refreshes as Metal's times count them, from the first
;; shown, and when the last shown came (now-ns).
(defvar *mac-refresh* 0)
(defvar *mac-refresh-at* 0)

;; Frame's word from Metal: t, when it was shown on the host's clock, or 0
;; for never. A time is taken on now-ns's clock when its frame shows after
;; it was sent, and within a second; else the report says nothing. The
;; display's sequence is the refreshes since the last shown, at the
;; window's rate, as Metal gives none.
(define (mac-reported! frame t)
  (if (fx= t 0)
      (begin (present-reported! frame 2 0 0 0)
             (host-trace! 11 frame))
      (let ([shown (+ t (platform-clock-offset 8))]
            [sent (fxvector-ref *present-ring* (fx+ (present-at frame) 2))]
            [r (host-frame-ns)])
        (when (and (<= (- sent 1000000) shown (+ sent 1000000000)) (> r 0))
          (let ([seq (if (= *mac-refresh-at* 0)
                         1
                         (+ *mac-refresh*
                            (div (+ (- shown *mac-refresh-at*)
                                    (quotient r 2))
                                 r)))])
            (when (> shown *mac-refresh-at*)
              (set! *mac-refresh* seq)
              (set! *mac-refresh-at* shown))
            (present-reported! frame 1 shown r seq)
            (host-trace! 10 frame))))))
