;;; (schevana core0 platform) — core0's part of what differs by platform:
;;; which platform this is, as core0 learns it once SDL and the GPU start
;;; (*core0-platform*), and the screen's reports where a platform gives them
;;; (Wayland's and Metal's). Each thing a platform may lack is found by
;;; asking (a library that loads, an entry SDL has, a global the compositor
;;; lists), and is off without it. docs/PLATFORMS.md says where each has
;;; run.

(library (schevana core0 platform)
  (export
    platform-cpu-count *core0-platform* core0-platform-read!
    platform-report-ask! platform-reports-start! platform-reports-pump!
    platform-desktop-frameless? platform-sdl-wayland?
    platform-thread-interactive!)
  (import (chezscheme)
          (only (schevana base) define-made define-state library-layer
                platform-mac? string-prefix?)
          (only (schevana ffi) c-clock-gettime c-close)
          (only (schevana sdl) sdl-get-current-video-driver
                sdl-get-num-logical-cpu-cores sdl-get-number-property
                sdl-get-pointer-property sdl-get-string-property sdl-get-version
                sdl-get-window-properties)
          (only (schevana core0 mail) *core0-input-wl* core0-clock-ns
                core0-input-set!)
          (only (schevana core0 trace) core0-trace!)
          (only (schevana core0 renderer) *renderer* gpu-driver-name
                renderer-device)
          (only (schevana core0 present) *present-ring* present-at
                present-reported!))

  (library-layer core0)

  ;; A C entry, or #f where this platform's libraries lack it.
  (define-syntax define-optional-foreign
    (syntax-rules ()
      [(_ name form) (define-made name (guard (c [#t #f]) form))]))

  ;; Copies s into C's memory, kept for good, and returns its address.
  (define (platform-c-string s)
    (let* ([b (string->utf8 s)] [n (bytevector-length b)]
           [p (foreign-alloc (+ n 1))])
      (do ([i 0 (+ i 1)]) ((= i n))
        (foreign-set! 'unsigned-8 p i (bytevector-u8-ref b i)))
      (foreign-set! 'unsigned-8 p n 0)
      p))

  ;; Returns the string C's memory holds at p, up to its first nul.
  (define (platform-c->string p)
    (let loop ([i 0] [acc '()])
      (let ([b (foreign-ref 'unsigned-8 p i)])
        (if (= b 0)
            (utf8->string (u8-list->bytevector (reverse acc)))
            (loop (+ i 1) (cons b acc))))))

  ;;; ------------------------------------------------------------------
  ;;; what the platform is

  ;; How many threads this machine runs at once (logical cores): from any
  ;; thread.
  (define (platform-cpu-count) (sdl-get-num-logical-cpu-cores))

  ;; The system's and the kernel's names and versions, where the system
  ;; gives them.
  (define-optional-foreign platform-uname
    (foreign-procedure "uname" (uptr) int))
  (define-optional-foreign platform-sysctl
    (foreign-procedure "sysctlbyname" (string uptr uptr uptr size_t) int))
  ;; SDL 3.4's: the GPU's name and driver
  (define-optional-foreign platform-gpu-properties
    (foreign-procedure "SDL_GetGPUDeviceProperties" (uptr) unsigned-32))

  ;; The kernel, as "Linux 6.12.1": uname's sysname and release (its first
  ;; and third fields, each 65 bytes long on Linux and 256 on a Mac).
  (define (platform-kernel)
    (and platform-uname
         (let* ([n (if (platform-mac?) 256 65)] [p (foreign-alloc (* 6 n))])
           (let ([k (and (= 0 (platform-uname p))
                         (format "~a ~a" (platform-c->string p)
                                 (platform-c->string (+ p (* 2 n)))))])
             (foreign-free p)
             k))))

  ;; The system, as its maker names it: os-release's PRETTY_NAME on Linux,
  ;; the product version on a Mac.
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

  ;; The GPU device as SDL describes it, (name driver version info), or #f
  ;; before SDL 3.4.
  (define (platform-gpu-device)
    (and platform-gpu-properties *renderer*
         (let ([props (platform-gpu-properties (renderer-device *renderer*))]
               [get (lambda (props key)
                      (sdl-get-string-property
                       props (string-append "SDL.gpu.device." key) #f))])
           (and (not (eqv? props 0))
                (map (lambda (key) (get props key))
                     '("name" "driver_name" "driver_version" "driver_info"))))))

  ;; What core0 knows about the platform, an alist it sets whole: the world
  ;; reads it ((schevana core platform)) and never asks SDL itself.
  (define-state *core0-platform* '())

  ;;; ------------------------------------------------------------------
  ;;; the screen's reports
  ;;; When each frame reached the screen, written into (schevana core0
  ;;; present)'s ring (present-reported!): from Wayland's wp_presentation,
  ;;; and from Metal's presented handlers on a Mac.

  ;; Asks the screen to report on frame, which is sent next.
  (define (platform-report-ask! frame)
    (cond
      [(not (eqv? *wayland-presentation* 0))
       (with-interrupts-disabled
        (let ([proxy (wayland-marshal-2 *wayland-presentation* 1
                                        wayland-feedback-interface 1 0
                                        *wayland-surface* 0)])
          (wayland-add-listener proxy wayland-feedback-listener frame)))]
      [(not (eqv? *mac-layer* 0)) (mac-ask! frame)]))

  ;; Starts the reports for the window from now on, where its platform
  ;; gives them.
  (define (platform-reports-start! sdl-window)
    (wayland-start! sdl-window)
    (mac-start! sdl-window)
    (core0-platform-read!))

  ;; Where the reports come from, for a person to read: (source clock
  ;; clock flags), with the clock the compositor names and the one its times
  ;; fit; or #f with no reports.
  (define (platform-reports)
    (cond
      [(not (eqv? *wayland-presentation* 0))
       (list 'wayland-presentation
             (platform-clock-name *wayland-clock*)
             (platform-clock-name *wayland-used*)
             (platform-report-flags *wayland-flags*))]
      ;; Metal says its clock is Apple's host time, mach_absolute_time's
      [(not (eqv? *mac-layer* 0))
       (list 'metal-presented-handler 'uptime-raw 'uptime-raw '())]
      [else #f]))

  (define (core0-platform-read!)
    (let ([video (sdl-get-current-video-driver)])
      (set! *core0-platform*
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

  ;; Returns the ns to add to a time on clock (a POSIX clock's number) to
  ;; put it on core0-clock-ns's clock. It is read at each report, since two
  ;; clocks may drift apart by a few ms an hour.
  (define-state *platform-timespec* (foreign-alloc 16))
  (define (platform-clock-offset clock)
    (let ([ts *platform-timespec*])
      (c-clock-gettime clock ts)
      (- (core0-clock-ns)
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
  ;;; window's surface, with its events on a queue of core0's own, read
  ;;; after each pump without waiting. Its callbacks run with interrupts
  ;;; off, so that no engine's timer leaves through a C frame.

  (define-made wayland-loaded?
    (guard (c [#t #f]) (load-shared-object "libwayland-client.so.0") #t))

  (define-syntax define-wayland
    (syntax-rules ()
      [(_ name form) (define-made name (and wayland-loaded? form))]))

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
  (define-wayland wayland-connect
    (foreign-procedure "wl_display_connect" (uptr) uptr))
  (define-wayland wayland-disconnect
    (foreign-procedure "wl_display_disconnect" (uptr) void))
  (define-wayland wayland-queue-destroy
    (foreign-procedure "wl_event_queue_destroy" (uptr) void))

  (define-ftype wayland-message
    (struct [name void*] [signature void*] [types void*]))
  (define-ftype wayland-interface
    (struct [name void*] [version int] [method-count int] [methods void*]
            [event-count int] [events void*]))

  ;; Eight null types, for messages whose arguments name no interface.
  (define-made wayland-nulls
    (and wayland-loaded?
         (let ([p (foreign-alloc 64)])
           (do ([i 0 (+ i 8)]) ((= i 64)) (foreign-set! 'uptr p i 0))
           p)))

  ;; Makes an array of messages from specs, each (name signature types).
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

  (define-made wayland-feedback-interface
    (and wayland-loaded?
         (wayland-interface-new "wp_presentation_feedback" 1 '()
           (list (list "sync_output" "o" wayland-nulls)
                 (list "presented" "uuuuuuu" wayland-nulls)
                 (list "discarded" "" wayland-nulls)))))

  (define-made wayland-presentation-interface
    (and wayland-loaded?
         (let ([types (foreign-alloc 16)])
           (foreign-set! 'uptr types 0 (foreign-entry "wl_surface_interface"))
           (foreign-set! 'uptr types 8 wayland-feedback-interface)
           (wayland-interface-new "wp_presentation" 1
             (list (list "destroy" "" wayland-nulls)
                   (list "feedback" "on" types))
             (list (list "clock_id" "u" wayland-nulls))))))

  ;; The display, the surface, our queue and wp_presentation bound on it, or
  ;; 0; the clock the compositor reports by, as it says (#f until it has),
  ;; and the one its times fit; and the last report's flags.
  (define-state *wayland-display* 0)
  (define-state *wayland-surface* 0)
  (define-state *wayland-queue* 0)
  (define-state *wayland-presentation* 0)
  (define-state *wayland-clock* #f)
  (define-state *wayland-used* #f)
  (define-state *wayland-flags* 0)
  (define-state *wayland-found* #f)   ; wp_presentation's (name . version)
  (define-state *wayland-seat-found* #f)   ; the seat's name
  (define-state *wayland-pointer* 0)
  (define-state *wayland-keyboard* 0)
  (define-state *wayland-input-clock* #f)   ; the clock that input's times fit

  (define-syntax define-wayland-callback
    (syntax-rules ()
      [(_ name handler (type ...))
       (define-made name
         (and wayland-loaded?
              (let ([code (foreign-callable handler (type ...) void)])
                (lock-object code)
                (foreign-callable-entry-point code))))]))

  ;; presented: tv_sec high and low, ns, refresh, sequence high and low, flags.
  ;; The sequence, the display's count of its refreshes, is left unread: the
  ;; protocol lets it be 0, as KWin's is, and Mutter's counts frames where
  ;; the driver counts nothing. The refreshes are counted from the times
  ;; (present-shown!).
  (define-wayland-callback wayland-shown-code
    (lambda (frame proxy sec-hi sec-lo nsec refresh seq-hi seq-lo flags)
      (present-reported!
       frame 1
       (wayland-shown-ns frame
                         (+ (* 1000000000 (+ (* sec-hi 4294967296) sec-lo))
                            nsec)
                         refresh)
       refresh)
      (core0-trace! 10 frame)
      (wayland-destroy proxy)
      (unless (eqv? flags *wayland-flags*)
        (set! *wayland-flags* flags)
        (core0-platform-read!)))
    (uptr uptr unsigned-32 unsigned-32 unsigned-32 unsigned-32 unsigned-32
     unsigned-32 unsigned-32))
  (define-wayland-callback wayland-dropped-code
    (lambda (frame proxy)
      (present-reported! frame 2 0 0)
      (core0-trace! 11 frame)
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

  ;; Whether time t on clock falls, on core0-clock-ns's clock, between low
  ;; and ahead ns after now; and the first of said and Linux's clocks on
  ;; which it does, or #f. Now is read after the clock's offset, so a time
  ;; gone by never reads as one to come, however long core0 waited between
  ;; the offset's two reads. They use numbers alone: no allocation for a
  ;; report or an input.
  (define (platform-fits? t clock low ahead)
    (and clock
         (let ([at (+ t (platform-clock-offset clock))])
           (<= low at (+ (core0-clock-ns) ahead)))))
  (define (platform-fitting t said low ahead)
    (cond [(platform-fits? t said low ahead) said]
          [(platform-fits? t 4 low ahead) 4]
          [(platform-fits? t 1 low ahead) 1]
          [(platform-fits? t 7 low ahead) 7]
          [(platform-fits? t 0 low ahead) 0]
          [else #f]))

  ;; Returns a report's time t on core0-clock-ns's clock, given its refresh
  ;; as the screen says it (ns; 0 for none). A frame shows after it is sent,
  ;; and its report comes after it showed, or up to a refresh before where a
  ;; compositor predicts the time. A compositor whose times break that rule
  ;; on the clock it names (GNOME's with NVIDIA's vblank stamps, on
  ;; CLOCK_MONOTONIC_RAW, which runs behind the monotonic clock on one
  ;; machine and ahead of it on another) is read on the first of Linux's
  ;; clocks that fits.
  (define (wayland-shown-ns frame t refresh)
    (let ([low (- (fxvector-ref *present-ring* (fx+ (present-at frame) 2))
                  1000000)])
      (unless (platform-fits? t *wayland-used* low refresh)
        (let ([clock (platform-fitting t *wayland-clock* low refresh)])
          (when clock
            (set! *wayland-used* clock)
            (core0-platform-read!))))
      (+ t (platform-clock-offset *wayland-used*))))

  ;; Notes an input's time from its event's ms on the compositor's clock
  ;; (which wraps at 32 bits), as core0 reads the event: on the clock by
  ;; which it came within the last second, to the ms. It goes in as the
  ;; oldest input not yet taken (core0-input-set!).
  (define (wayland-input! ms)
    (let* ([at (core0-clock-ns)]
           [t (or (wayland-input-on *wayland-input-clock* ms at)
                  (wayland-input-on 1 ms at)
                  (wayland-input-on 4 ms at)
                  (wayland-input-on 7 ms at))])
      (when t (core0-input-set! *core0-input-wl* t))))

  ;; Returns ms, read on clock, as a time on core0-clock-ns's clock, and
  ;; keeps clock as the one input fits; or #f when it doesn't fit.
  (define (wayland-input-on clock ms at)
    (and clock
         (let* ([off (platform-clock-offset clock)]
                [at-ms (quotient (- at off) 1000000)]
                [t (+ off (* 1000000 (- at-ms (modulo (- at-ms ms)
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

  ;; A pointer and a keyboard of core0's own on the seat, at version 1, for
  ;; their events' times alone: the same events SDL reads, on core0's queue.
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

  ;; Makes a listener: its callbacks' entry points, in its events' order.
  (define (wayland-listener . entries)
    (and wayland-loaded?
         (let ([p (foreign-alloc (* 8 (length entries)))])
           (for-each (lambda (e i) (foreign-set! 'uptr p (* 8 i) e))
                     entries (iota (length entries)))
           p)))

  (define-made wayland-feedback-listener
    (wayland-listener wayland-output-code wayland-shown-code
                      wayland-dropped-code))
  (define-made wayland-presentation-listener
    (wayland-listener wayland-clock-code))
  (define-made wayland-registry-listener
    (wayland-listener wayland-global-code wayland-global-gone-code))

  ;; The interfaces the compositor lists, by name, as
  ;; platform-wayland-globals reads them.
  (define-state *wayland-listed* '())
  (define-wayland-callback wayland-listed-code
    (lambda (data registry name interface version)
      (set! *wayland-listed*
        (cons (platform-c->string interface) *wayland-listed*)))
    (uptr uptr unsigned-32 uptr unsigned-32))
  (define-made wayland-listing-listener
    (wayland-listener wayland-listed-code wayland-global-gone-code))

  ;; What the compositor can do, asked before SDL starts: returns the
  ;; interfaces it lists, by name, on a connection of core0's own (to
  ;; WAYLAND_DISPLAY's), opened and closed again; '() with no compositor.
  (define (platform-wayland-globals)
    (let ([display (if wayland-loaded? (wayland-connect 0) 0)])
      (if (eqv? display 0)
          '()
          (with-interrupts-disabled
           (set! *wayland-listed* '())
           (let ([queue (wayland-create-queue display)]
                 [registry (wayland-marshal-1
                            display 1 (foreign-entry "wl_registry_interface")
                            (wayland-version display) 0 0)])
             (wayland-set-queue registry queue)
             (wayland-add-listener registry wayland-listing-listener 0)
             (wayland-roundtrip display queue)
             (wayland-destroy registry)
             (wayland-queue-destroy queue)
             (wayland-disconnect display)
             *wayland-listed*)))))

  ;; Whether the desktop draws no window frames, asked before SDL starts:
  ;; SDL is to use Wayland (as it does unless told otherwise), and the
  ;; compositor lists no xdg-decoration (GNOME's).
  (define (platform-desktop-frameless?)
    (let ([driver (getenv "SDL_VIDEO_DRIVER")])
      (and (or (not driver) (string=? driver "wayland"))
           (let ([globals (platform-wayland-globals)])
             (and (pair? globals)
                  (not (member "zxdg_decoration_manager_v1" globals)))))))

  ;; Whether SDL, once started, runs on Wayland.
  (define (platform-sdl-wayland?)
    (equal? (sdl-get-current-video-driver) "wayland"))
  (define-made wayland-seat-listener (wayland-listener wayland-seat-code))
  (define-made wayland-pointer-listener
    (wayland-listener wayland-enter-code wayland-leave-code wayland-motion-code
                      wayland-button-code wayland-axis-code))
  (define-made wayland-keyboard-listener
    (wayland-listener wayland-keymap-code wayland-keys-code wayland-leave-code
                      wayland-key-code wayland-modifiers-code))

  ;; Binds wp_presentation for the window, when the window lives on
  ;; Wayland and the compositor has it, and learns the clock it reports by,
  ;; which it names at once; and binds the seat, for the input's own times.
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
                 ;; no report until the clock is known
                 (when *wayland-clock*
                   (set! *wayland-presentation* p))))))))))

  ;;; ---- the frame's threads
  ;;; On a Mac the process's first thread, core0's, runs at the
  ;;; user-interactive class, while a forked thread starts at the default
  ;;; class, which Apple silicon may run on an efficiency core and wake
  ;;; late: core1's turns that woke late sent frames past their latch. So
  ;;; core1 asks for core0's class. Elsewhere this does nothing.

  (define-made mac-system-loaded?
    (and (platform-mac?)
         (guard (c [#t #f])
           (load-shared-object "/usr/lib/libSystem.B.dylib")
           #t)))

  ;; QOS_CLASS_USER_INTERACTIVE
  (define mac-class-interactive #x21)

  ;; Puts the calling thread at the class core0's thread runs at, where the
  ;; OS has classes.
  (define (platform-thread-interactive!)
    (when mac-system-loaded?
      ((foreign-procedure "pthread_set_qos_class_self_np" (unsigned-int int)
                          int)
       mac-class-interactive 0)))

  ;;; ---- the Mac's
  ;;; Metal calls a drawable's presented handlers when it was shown, or
  ;;; when it never will be: its presentedTime gives seconds in Apple's host
  ;;; time (mach_absolute_time's, CLOCK_UPTIME_RAW), or 0 for never. SDL
  ;;; takes each drawable from its layer in its acquire and presents it at
  ;;; the submit, and hands none to us; so the one layer it draws to is
  ;;; given a class of core0's own, made once, whose nextDrawable calls
  ;;; CAMetalLayer's and gives our handler to the drawable it returns, there
  ;;; on core0's thread, inside SDL's acquire. The handler runs on a thread
  ;;; of Apple's: it writes only a ring of its own, indexed by the
  ;;; drawable's number, which core0 reads at each pump for the frames it
  ;;; sent. Keeping the drawables to read them later would keep them from
  ;;; the layer's pool, which holds three.

  (define-made mac-objc-loaded?
    (and (platform-mac?)
         (guard (c [#t #f])
           (load-shared-object "/usr/lib/libobjc.A.dylib")
           #t)))

  (define-syntax define-objc
    (syntax-rules ()
      [(_ name form) (define-made name (and mac-objc-loaded? form))]))

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
  ;; objc_msgSend, once for each message's types
  (define-objc objc-send (foreign-procedure "objc_msgSend" (uptr uptr) uptr))
  (define-objc objc-send-long
    (foreign-procedure "objc_msgSend" (uptr uptr long) uptr))
  (define-objc objc-send-double
    (foreign-procedure "objc_msgSend" (uptr uptr) double))
  ;; Collect-safe, for core0 inside nextDrawable: Core Animation's thread
  ;; holds the lock that a drawable's messages take while it runs our
  ;; handler, which may wait for a collection, and the collection can't wait
  ;; for core0 blocked on that lock.
  (define-objc objc-send-safe
    (foreign-procedure __collect_safe "objc_msgSend" (uptr uptr) uptr))
  (define-objc objc-send-pointer-safe
    (foreign-procedure __collect_safe "objc_msgSend" (uptr uptr uptr) void))

  (define-objc mac-next-selector (objc-selector "nextDrawable"))
  (define-objc mac-id-selector (objc-selector "drawableID"))
  (define-objc mac-time-selector (objc-selector "presentedTime"))
  (define-objc mac-handler-selector (objc-selector "addPresentedHandler:"))

  ;; The handlers' ring: one row for each drawable, by its number
  ;; (drawableID, which counts up from 0 on each layer), holding that number
  ;; plus one (0 for none yet) and when the drawable was shown (ns in Apple's
  ;; host time; 0 for never). Only the handlers write it, the number last.
  (define mac-rows 64)
  (define-state *mac-shown* (make-fxvector (* 2 mac-rows) 0))

  ;; On Apple's thread: writes the drawable's report into its row.
  (define (mac-presented! drawable)
    (let* ([id (objc-send drawable mac-id-selector)]
           [t (objc-send-double drawable mac-time-selector)]
           [at (fx* 2 (fxmodulo id mac-rows))])
      (fxvector-set! *mac-shown* (fx+ at 1)
                     (if (fl> t 0.0) (flonum->fixnum (flround (fl* t 1e9))) 0))
      (memory-order-release)
      (fxvector-set! *mac-shown* at (fx+ id 1))))

  ;; Collect-safe: for the call, Chez makes the thread of Apple's that
  ;; calls it one of its own.
  (define-made mac-handler-code
    (and mac-objc-loaded?
         (let ([code (foreign-callable __collect_safe
                       (lambda (block drawable) (mac-presented! drawable))
                       (uptr uptr) void)])
           (lock-object code)
           (foreign-callable-entry-point code))))

  ;; The handler as a block: a global one (flag 1 << 28), which copying and
  ;; releasing leave as it is, with a signature (1 << 30). It is never
  ;; freed.
  (define-made mac-handler-block
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

  ;; SDL's layer, now of core0's class (0 for none); CAMetalLayer's own
  ;; nextDrawable, collect-safe, since the pool may hold it for a refresh;
  ;; and the number of the drawable given to the acquire running now (-1
  ;; for none).
  (define-state *mac-layer* 0)
  (define-state *mac-next-drawable* #f)
  (define-state *mac-drawable* -1)

  ;; nextDrawable, as core0's class has it: calls the layer's own, and
  ;; gives our handler to the drawable it returns.
  (define-made mac-next-code
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

  ;; Core0's subclass of CAMetalLayer, made once per process.
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

  ;; Finds the layer SDL draws to, by its view's tag in the window, and
  ;; makes it of core0's class from now on: only a layer of CAMetalLayer's
  ;; own class, not one that something else has given a class of its own
  ;; (as KVO does).
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

  ;; The frames sent and not yet reported on, each with its drawable's
  ;; number, one row per frame by its number (-1 for none): core0's alone.
  (define mac-waiting-rows 8)
  (define-state *mac-waiting* (make-fxvector (* 2 mac-waiting-rows) -1))

  ;; Makes frame, which is sent next, wait for its drawable's report.
  (define (mac-ask! frame)
    (unless (fx= *mac-drawable* -1)
      (let ([at (fx* 2 (fxmodulo frame mac-waiting-rows))])
        (fxvector-set! *mac-waiting* at frame)
        (fxvector-set! *mac-waiting* (fx+ at 1) *mac-drawable*))
      (set! *mac-drawable* -1)))

  ;; Takes Metal's report on frame: t, when it was shown in Apple's host
  ;; time, or 0 for never. A time, moved to core0-clock-ns's clock, is taken
  ;; when its frame shows after it was sent and within a second of it;
  ;; otherwise the report says nothing. Metal gives no refresh length, and
  ;; the display may vary its own, so the refreshes are counted at the
  ;; window's rate, each time taken as it is (present-shown!).
  (define (mac-reported! frame t)
    (if (fx= t 0)
        (begin (present-reported! frame 2 0 0)
               (core0-trace! 11 frame))
        (let ([shown (+ t (platform-clock-offset 8))]
              [sent (fxvector-ref *present-ring* (fx+ (present-at frame) 2))])
          (when (<= (- sent 1000000) shown (+ sent 1000000000))
            (present-reported! frame 1 shown 0)
            (core0-trace! 10 frame)))))

  ;; Takes the reports the handlers wrote since the last look.
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

  ;; Takes the reports that came since the last look, without waiting.
  (define (platform-reports-pump!)
    (unless (eqv? *wayland-queue* 0)
      (with-interrupts-disabled
       (wayland-dispatch *wayland-display* *wayland-queue*)))
    (unless (eqv? *mac-layer* 0) (mac-pump!))))
