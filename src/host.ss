;;; host.ss — the host window that the whole world lives in.
;;;
;;; 'sdl      : a real resizable window, on the GPU
;;; 'headless : no window at all, on the CPU's Vulkan driver (for tests and
;;;             screenshots)
;;;
;;; Host events are translated into plain Scheme lists:
;;;   (mouse-move x y) (mouse-down x y button clicks) (mouse-up x y button)
;;;   (wheel dx dy) (key-down key mods) (text "a") (resize w h) (quit) ...
;;; key is a char for printable keys (#\a, #\space) or a symbol ('return,
;;; 'left, 'f1, ...); mods is a list drawn from (ctrl alt shift super).

(defvar *host* 'none)
(defvar *sdl-window* 0)
(defvar *sdl-event* (foreign-alloc 128))   ; an SDL_Event
;; what SDL says of the window's size: a place for it, a pointer made once
(define-ftype host-size (struct [w int] [h int]))
(defvar *host-scratch* (foreign-alloc (ftype-sizeof host-size)))
(define host-size* (make-ftype-pointer host-size *host-scratch*))
(defvar *host-clipboard* "")
;; told of every event the host sends, by its number, whether it means
;; anything to the world or not
(defvar *host-event-seen* void)
(defvar *cursors* (make-eq-hashtable))
(defvar *current-cursor* #f)
(defvar *host-fullscreen* #f)   ; what headless mode pretends
(defvar *host-scale* 1)         ; physical pixels per logical pixel, exact
;; physical pixels per SDL window unit (2 on a Retina Mac)
(defvar *pixel-ratio* 1)
;; the minimum size SDL last passed on to the window, or #f
(defvar *host-min-size* #f)
(defvar *headless-size* '(1280 . 800))

;; Who the host window is to the desktop: its app id under Wayland, its
;; class under X11. The desktop entry (desktop/icon.ss) names it too.
(define host-app-id "schevana")

;;; ------------------------------------------------------------------ scale
;;; The world is laid out in logical pixels and drawn *host-scale* times
;;; bigger. The scale follows the desktop unless the theme key 'scale (a
;;; percentage; 0 for automatic) overrides it.

(define (wanted-scale)
  (let ([p (theme 'scale)])
    (if (and (fixnum? p) (> p 0)) (/ (clamp p 50 400) 100) (system-scale))))

;; What the desktop asks for, to the percent: SDL's display scale for the
;; window, the pixel ratio (2 on macOS and Wayland at 200%) times the
;; desktop's own scale (under X11 Xft.dpi, 96 being 100%, which SDL reads
;; once, as it starts). 0 is SDL's failure.
(define (system-scale)
  (let ([s (if (eq? *host* 'sdl)
               (sdl-get-window-display-scale *sdl-window*)
               1)])
    (if (> s 0) (/ (exact (round (* 100 s))) 100) 1)))

(define (system-scale-percent) (exact (round (* 100 (system-scale)))))

;; SDL window units (mouse positions, fractional in SDL3) to logical
;; pixels.
(define (host->world v) (floor (/ (* (exact v) *pixel-ratio*) *host-scale*)))

;; After the 'scale setting changed: lay the world out again at the new scale.
(define (host-rescale!)
  (when (host-sync-size!)
    (wm-screen-resized!)))

;; The host window's size in window units for a w × h logical world drawn
;; at scale, with ratio physical pixels per window unit.
(define (host-window-size w h scale ratio)
  (values (exact (round (/ (* w scale) ratio)))
          (exact (round (/ (* h scale) ratio)))))

;; fullscreen?: start full screen instead of in a w × h window.
(define (host-init! mode w h . fullscreen?)
  (set! *host* mode)
  (set! *host-fullscreen* (and (pair? fullscreen?) (car fullscreen?)))
  (set! *host-min-size* #f)
  (case mode
    [(headless)
     (set! *headless-size* (cons w h))
     (set! *host-scale* (wanted-scale))
     ;; on a Mac, no Dock icon and no taking the focus from what you're doing
     (sdl-set-hint "SDL_MAC_BACKGROUND_APP" "1")
     (host-sdl-init! gpu-windowless-video)
     (unless *renderer* (gpu-open! gpu-windowless-kind))
     (canvas-create! w h *host-scale*)]
    [(sdl)
     (sdl-set-hint "SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR" "0")
     (sdl-set-hint "SDL_MOUSE_FOCUS_CLICKTHROUGH" "1")
     (sdl-set-hint "SDL_APP_ID" host-app-id)
     (host-sdl-init! #f)
     ;; w × h are logical pixels. How many physical pixels a window unit
     ;; holds, and the desktop's scale, are known once the window is there,
     ;; so it opens hidden, a unit per logical pixel, and is sized and
     ;; centered before it is shown.
     (set! *sdl-window*
       (sdl-create-window "Schevana" w h
                          (fxior SDL_WINDOW_RESIZABLE
                                 SDL_WINDOW_HIGH_PIXEL_DENSITY
                                 SDL_WINDOW_HIDDEN
                                 (if *host-fullscreen*
                                     SDL_WINDOW_FULLSCREEN
                                     0))))
     (when (= 0 *sdl-window*)
       (errorf 'host-init! "SDL_CreateWindow failed: ~a" (sdl-get-error)))
     (unless *renderer* (gpu-open! 'gpu))
     (gpu-claim-window! *sdl-window*)
     (let*-values ([(uw uh pw ph) (host-read-sizes)]
                   [(nw nh)
                    (host-window-size w h (wanted-scale) *pixel-ratio*)])
       (unless (or *host-fullscreen* (and (= nw uw) (= nh uh)))
         (sdl-set-window-size *sdl-window* nw nh)))
     (sdl-set-window-position *sdl-window* SDL_WINDOWPOS_CENTERED
                              SDL_WINDOWPOS_CENTERED)
     (sdl-show-window *sdl-window*)
     (sdl-start-text-input *sdl-window*)
     (host-sync-size!)]
    [else (errorf 'host-init! "unknown host mode ~s" mode)]))

;; Once for all: video, the driver named if one is.
(define (host-sdl-init! driver)
  (when driver (sdl-set-hint "SDL_VIDEO_DRIVER" driver))
  (unless (sdl-init SDL_INIT_VIDEO)
    (errorf 'host-init! "SDL_Init failed: ~a" (sdl-get-error))))

(define (host-shutdown!)
  (when (eq? *host* 'sdl)
    (sdl-wait-gpu-idle (renderer-device *renderer*))
    (sdl-release-window (renderer-device *renderer*) *sdl-window*)
    (sdl-destroy-window *sdl-window*)
    (sdl-quit)
    (set! *renderer* #f)
    (set! *host* 'none)))

;;; ------------------------------------------------------------------
;;; full screen

;; SDL3's flags include a change asked for and not made yet.
(define (fullscreen?)
  (if (eq? *host* 'sdl)
      (logtest (sdl-get-window-flags *sdl-window*) SDL_WINDOW_FULLSCREEN)
      *host-fullscreen*))

;; Full screen at the desktop's own resolution (SDL3's default full-screen
;; mode): the world just gets a bigger canvas (the host sends a resize
;; event).
(define (set-fullscreen! on?)
  (when (eq? *host* 'sdl)
    (sdl-set-window-fullscreen *sdl-window* on?))
  (set! *host-fullscreen* (and on? #t))
  (invalidate!))

(define (toggle-fullscreen!) (set-fullscreen! (not (fullscreen?))))

;;; ------------------------------------------------------------------ icon

;; The host window's icon, which the desktop's taskbar or dock shows (under
;; X11, and Wayland compositors with the xdg-toplevel-icon protocol; GNOME
;; takes icons from .desktop files instead, and SDL's call fails there).
;; draw is called on a clear size × size image.
(define (host-set-icon! size draw)
  (when (eq? *host* 'sdl)
    (let ([bytes (drawing->bytes size size 1 (lambda () (draw size)))])
      (unpremultiply! bytes)
      (let ([icon (sdl-create-surface-from size size SDL_PIXELFORMAT_ARGB8888
                                           (object->reference-address bytes)
                                           (* 4 size))])
        (unless (= icon 0)
          (sdl-set-window-icon *sdl-window* icon)   ; SDL copies the pixels
          (sdl-destroy-surface icon))))))

;; Pixels premultiplied, as images keep them, made straight.
(define (unpremultiply! bytes)
  (do ([i 0 (+ i 4)]) ((>= i (bytevector-length bytes)))
    (let ([a (bytevector-u8-ref bytes (+ i 3))])
      (when (fx< 0 a 255)
        (do ([k 0 (+ k 1)]) ((= k 3))
          (bytevector-u8-set!
           bytes (+ i k)
           (fxmin 255 (fxquotient (fx+ (fx* (bytevector-u8-ref bytes (+ i k))
                                            255)
                                       (fxquotient a 2))
                                  a))))))))

;; The window's size in window units and in physical pixels, (values w h pw
;; ph); sets *pixel-ratio* from them.
(define (host-read-sizes)
  (let*-values ([(w h) (host-size-from sdl-get-window-size)]
                [(pw ph) (host-size-from sdl-get-window-size-in-pixels)])
    (set! *pixel-ratio* (/ pw (max w 1)))
    (values w h pw ph)))

;; The size get, one of SDL's, says: (values w h).
(define (host-size-from get)
  (get *sdl-window*
       (ftype-pointer-address (ftype-&ref host-size (w) host-size*))
       (ftype-pointer-address (ftype-&ref host-size (h) host-size*)))
  (values (ftype-ref host-size (w) host-size*)
          (ftype-ref host-size (h) host-size*)))

;; Re-reads the window's pixel size and the scale; the canvas follows when
;; either changed. Returns #t if they did.
(define (host-sync-size!)
  (case *host*
    [(sdl)
     (let-values ([(w h pw ph) (host-read-sizes)])
       (let ([scale (wanted-scale)])
         (if (and (= pw (canvas-pixel-width)) (= ph (canvas-pixel-height))
                  (= scale *host-scale*))
             #f
             (begin
               (set! *host-scale* scale)
               (canvas-create-pixels! pw ph scale)
               ;; The host window may not shrink below 640 × 400 logical pixels.
               ;; SDL is told only when that changes: each call also sets the
               ;; window's size again (a request to the window manager,
               ;; mid-drag). In full screen SDL may not pass it on (under X11
               ;; it does not), so it is told again after.
               (let ([m (cons
                         (exact (ceiling (/ (* 640 scale) *pixel-ratio*)))
                         (exact (ceiling (/ (* 400 scale) *pixel-ratio*))))])
                 (unless (equal? m *host-min-size*)
                   (sdl-set-window-minimum-size *sdl-window* (car m) (cdr m))
                   (set! *host-min-size* (and (not (fullscreen?)) m))))
               #t))))]
    [(headless)
     (let ([scale (wanted-scale)])
       (and (not (= scale *host-scale*))
            (begin
              (set! *host-scale* scale)
              (canvas-create! (car *headless-size*) (cdr *headless-size*) scale)
              #t)))]
    [else #f]))

;; With vsync on, thunk may wait for the screen: a phase of the profiler's,
;; part saying in which call, and no work. => thunk's value.
(define (host-screen-wait part thunk)
  (let* ([t (now-ns)]
         [v (with-profile-span 'vsync-wait part (thunk))])
    (pacer-waited! t)
    (when (eq? part 'acquire) (pacer-image-waited! t))
    v))

;; How many threads this machine runs at once (logical cores).
(define (host-cpu-count) (sdl-get-num-logical-cpu-cores))

;; SDL_DisplayMode (SDL_video.h).
(define-ftype sdl-display-mode
  (struct [display unsigned-32] [format unsigned-32] [w int] [h int]
          [density float] [refresh float] [numerator int] [denominator int]))

;; The window's display's mode, or #f when SDL does not say (headless, say).
(define (host-display-mode)
  (let ([m (if (eq? *host* 'sdl)
               (sdl-get-current-display-mode
                (sdl-get-display-for-window *sdl-window*))
               0)])
    (and (not (= m 0)) (make-ftype-pointer sdl-display-mode m))))

;; How long the screen shows a frame, ns: by its display's refresh rate, or
;; 60 Hz when SDL does not say.
(define (host-frame-ns)
  (let* ([m (host-display-mode)]
         [hz (if m (ftype-ref sdl-display-mode (numerator) m) 0)]
         [per (if m (ftype-ref sdl-display-mode (denominator) m) 0)])
    (if (and (> hz 0) (> per 0))
        (quotient (* 1000000000 per) hz)
        (quotient 1000000000 60))))

;; The display as a person reads it: (w h refresh-numerator denominator
;; density), or #f.
(define (host-display)
  (let ([m (host-display-mode)])
    (and m
         (list (ftype-ref sdl-display-mode (w) m)
               (ftype-ref sdl-display-mode (h) m)
               (ftype-ref sdl-display-mode (numerator) m)
               (ftype-ref sdl-display-mode (denominator) m)
               (ftype-ref sdl-display-mode (density) m)))))

;; What SDL says of the host window and last went wrong with it. It's all
;; for whoever is looking into a late tick.
(define (host-flags)
  (if (eq? *host* 'sdl) (sdl-get-window-flags *sdl-window*) 0))

(define (host-flag-names flags)
  (map cdr
       (filter (lambda (bit) (logtest flags (car bit)))
               '((#x1 . fullscreen)
                 (#x4 . occluded)
                 (#x8 . hidden)
                 (#x40 . minimized)
                 (#x80 . maximized)
                 (#x200 . input-focus)
                 (#x400 . mouse-focus)))))

(define (host-error-text) (sdl-get-error))

;; An event's name, by its number (SDL_events.h); or the number.
(define (host-event-name type)
  (cond
    [(assv type
           '((#x100 . quit)
             (#x101 . terminating)
             (#x102 . low-memory)
             (#x103 . will-enter-background)
             (#x104 . did-enter-background)
             (#x105 . will-enter-foreground)
             (#x106 . did-enter-foreground)
             (#x107 . locale-changed)
             (#x108 . system-theme-changed)
             (#x151 . display-orientation)
             (#x152 . display-added)
             (#x153 . display-removed)
             (#x154 . display-moved)
             (#x155 . display-desktop-mode-changed)
             (#x156 . display-current-mode-changed)
             (#x157 . display-content-scale-changed)
             (#x202 . window-shown)
             (#x203 . window-hidden)
             (#x204 . window-exposed)
             (#x205 . window-moved)
             (#x206 . window-resized)
             (#x207 . window-pixel-size-changed)
             (#x209 . window-minimized)
             (#x20A . window-maximized)
             (#x20B . window-restored)
             (#x20C . mouse-enter)
             (#x20D . mouse-leave)
             (#x20E . focus-gained)
             (#x20F . focus-lost)
             (#x210 . close-requested)
             (#x212 . window-icc-profile-changed)
             (#x213 . window-display-changed)
             (#x214 . window-display-scale-changed)
             (#x215 . window-safe-area-changed)
             (#x216 . window-occluded)
             (#x217 . window-enter-fullscreen)
             (#x218 . window-leave-fullscreen)
             (#x219 . window-destroyed)
             (#x21A . window-hdr-state-changed)
             (#x300 . key-down)
             (#x301 . key-up)
             (#x302 . text-editing)
             (#x303 . text-input)
             (#x304 . keymap-changed)
             (#x400 . mouse-motion)
             (#x401 . mouse-down)
             (#x402 . mouse-up)
             (#x403 . mouse-wheel)
             (#x404 . mouse-added)
             (#x405 . mouse-removed)
             (#x900 . clipboard-update)))
     => cdr]
    [else type]))

;; Hidden, minimized or covered, the host window shows nothing: no frames,
;; which wait until it shows.
(define (host-hidden?)
  ;; SDL_WINDOW_OCCLUDED, _HIDDEN and _MINIMIZED
  (and (eq? *host* 'sdl) (logtest (sdl-get-window-flags *sdl-window*) #x4c)))

;;; ------------------------------------------------------------------ events

(define sdl-special-keys
  `((13 . return) (8 . backspace) (9 . tab) (27 . escape) (127 . delete)
    (#x4000004F . right) (#x40000050 . left)
    (#x40000051 . down) (#x40000052 . up)
    (#x4000004A . home) (#x4000004D . end)
    (#x4000004B . page-up) (#x4000004E . page-down)
    (#x40000049 . insert) (#x40000058 . return)
    (#x400000E0 . ctrl) (#x400000E1 . shift)
    (#x400000E2 . alt) (#x400000E3 . super)
    (#x400000E4 . ctrl) (#x400000E5 . shift)
    (#x400000E6 . alt) (#x400000E7 . super)
    ,@(let loop ([i 0] [acc '()])
        (if (= i 12)
            acc
            (loop (+ i 1)
                  (cons (cons (+ #x4000003A i)
                              (string->symbol (format "f~a" (+ i 1))))
                        acc))))))

(define (sdl-key->key code)
  (cond
    [(assv code sdl-special-keys) => cdr]
    [(and (>= code 32) (< code 127)) (integer->char code)]
    [else (string->symbol (format "key-~x" code))]))

(define (sdl-mods->list m)
  (append (if (fxzero? (fxand m #xC0)) '() '(ctrl))
          (if (fxzero? (fxand m #x300)) '() '(alt))
          (if (fxzero? (fxand m #x3)) '() '(shift))
          (if (fxzero? (fxand m #xC00)) '() '(super))))

(define (sdl-button->symbol b)
  (case b [(1) 'left] [(2) 'middle] [(3) 'right] [else b]))

;; SDL3's events (SDL_events.h), as far as the world reads them: a head, then
;; a kind's own. A mouse's motion and buttons lie alike from x on; motion's
;; state, unread, lies where a button's bytes do.
(define-ftype sdl-event-head
  (struct [type unsigned-32] [reserved unsigned-32] [timestamp unsigned-64]
          [window unsigned-32] [which unsigned-32]))
(define-ftype sdl-event
  (union
   [head sdl-event-head]
   [key (struct [head sdl-event-head] [scancode unsigned-32] [key unsigned-32]
                [mods unsigned-16])]
   [text (struct [head sdl-event-head] [text void*])]
   [mouse (struct [head sdl-event-head] [button unsigned-8] [down unsigned-8]
                  [clicks unsigned-8] [x float] [y float])]
   [wheel (struct [head sdl-event-head] [x float] [y float]
                  [direction unsigned-32])]))

(define (sdl-mouse-x e) (host->world (ftype-ref sdl-event (mouse x) e)))
(define (sdl-mouse-y e) (host->world (ftype-ref sdl-event (mouse y) e)))

;; An SDL_Event at address buf, as the world's.
(define (sdl-event->list buf)
  (let* ([e (make-ftype-pointer sdl-event buf)]
         [type (ftype-ref sdl-event (head type) e)])
    (*host-event-seen* type)
    (cond
      [(= type SDL_EVENT_QUIT) '(quit)]
      [(= type SDL_EVENT_KEY_DOWN)
       (list 'key-down (sdl-key->key (ftype-ref sdl-event (key key) e))
             (sdl-mods->list (ftype-ref sdl-event (key mods) e)))]
      [(= type SDL_EVENT_TEXT_INPUT)
       (list 'text (c-string->string (ftype-ref sdl-event (text text) e)))]
      [(= type SDL_EVENT_MOUSE_MOTION)
       (list 'mouse-move (sdl-mouse-x e) (sdl-mouse-y e))]
      [(= type SDL_EVENT_MOUSE_BUTTON_DOWN)
       (list 'mouse-down (sdl-mouse-x e) (sdl-mouse-y e)
             (sdl-button->symbol (ftype-ref sdl-event (mouse button) e))
             (ftype-ref sdl-event (mouse clicks) e))]
      [(= type SDL_EVENT_MOUSE_BUTTON_UP)
       (list 'mouse-up (sdl-mouse-x e) (sdl-mouse-y e)
             (sdl-button->symbol (ftype-ref sdl-event (mouse button) e)))]
      [(= type SDL_EVENT_MOUSE_WHEEL) (sdl-wheel->list e)]
      [(or (= type SDL_EVENT_WINDOW_RESIZED)
           (= type SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED)
           (= type SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED))
       (and (host-sync-size!) (list 'resize *canvas-w* *canvas-h*))]
      [(= type SDL_EVENT_WINDOW_EXPOSED) '(expose)]
      [(= type SDL_EVENT_WINDOW_MOUSE_LEAVE) '(mouse-leave)]
      [else #f])))

(defvar *wheel-rest* '(0 . 0))   ; wheel travel not passed on yet, x . y

;; SDL3 reports the wheel in fractions of a step (touchpads, fine wheels);
;; the world takes whole steps, as SDL2 gave them: (wheel dx dy), or #f
;; until a whole step has added up.
;; A leftover is dropped when the wheel turns the other way, as in SDL2.
(define (sdl-wheel-add rest d) (+ (if (negative? (* rest d)) 0 rest) d))

(define (sdl-wheel->list e)
  (let* ([flip (if (= 1 (ftype-ref sdl-event (wheel direction) e)) -1 1)]
         [x (sdl-wheel-add (car *wheel-rest*)
                           (* flip (exact (ftype-ref sdl-event (wheel x) e))))]
         [y (sdl-wheel-add (cdr *wheel-rest*)
                           (* flip (exact (ftype-ref sdl-event (wheel y) e))))]
         [dx (truncate x)]
         [dy (truncate y)])
    (set! *wheel-rest* (cons (- x dx) (- y dy)))
    (and (not (= 0 dx dy)) (list 'wheel dx dy))))

;; Waits up to wait-ms for the first event, then drains the queue.
(define (host-events wait-ms)
  (if (eq? *host* 'sdl)
      (let ([buf *sdl-event*])
        (let loop ([more? (if (> wait-ms 0)
                              (sdl-wait-event-timeout buf wait-ms)
                              (sdl-poll-event buf))]
                   [acc '()])
          (if more?
              (let ([e (sdl-event->list buf)])
                (loop (sdl-poll-event buf) (if e (cons e acc) acc)))
              (reverse acc))))
      '()))

;;; ------------------------------------------------------------------
;;; cursor & clipboard

(define cursor-ids
  '((arrow . 0) (ibeam . 1) (wait . 2) (crosshair . 3) (resize-nwse . 5)
    (resize-nesw . 6) (resize-ew . 7) (resize-ns . 8) (move . 9) (hand . 11)))

(define (host-set-cursor! kind)
  (when (and (eq? *host* 'sdl) (not (eq? kind *current-cursor*)))
    (set! *current-cursor* kind)
    (sdl-set-cursor
     (or (hashtable-ref *cursors* kind #f)
         (let ([c (sdl-create-system-cursor
                   (cdr (or (assq kind cursor-ids) '(arrow . 0))))])
           (hashtable-set! *cursors* kind c)
           c)))))

(define (clipboard-get)
  (if (eq? *host* 'sdl)
      (let* ([p (sdl-get-clipboard-text)] [s (c-string->string p)])
        (unless (= p 0) (sdl-free p))
        s)
      *host-clipboard*))

(define (clipboard-set! s)
  (if (eq? *host* 'sdl)
      (sdl-set-clipboard-text s)
      (set! *host-clipboard* s)))

;;; ------------------------------------------------------------------
;;; local sockets

;;; For what talks to the world from outside. Nothing here waits: a read or a
;;; write asks poll first and does no more than will go at once. A socket is
;;; its file descriptor.

;; sockaddr_un, as Linux and macOS share it: on macOS the first byte is the
;; length and the second the family, which family below folds into one.
(define-ftype host-sockaddr
  (struct [family unsigned-16] [path (array 104 unsigned-8)]))
(define-ftype host-pollfd (struct [fd int] [events short] [revents short]))
(defvar *host-socket-memory*
  (foreign-alloc (+ (ftype-sizeof host-sockaddr)
                    (ftype-sizeof host-pollfd))))
(define host-sockaddr* (make-ftype-pointer host-sockaddr *host-socket-memory*))
(define host-pollfd*
  (make-ftype-pointer host-pollfd
                      (+ *host-socket-memory*
                         (ftype-sizeof host-sockaddr))))
;; a write's most at once: poll's "writable" means this much goes unblocked
(define host-socket-chunk 2048)
(defvar *host-socket-chunk* (make-bytevector host-socket-chunk))

;; The address of path, in the memory above. => its length
(define (host-socket-address! path)
  (let* ([bytes (string->utf8 path)] [n (bytevector-length bytes)]
         [length (+ n 3)] [a host-sockaddr*])
    (unless (< n 104) (errorf 'host-socket "too long a path: ~a" path))
    (ftype-set! host-sockaddr (family) a
                (if (string-contains-ci? (symbol->string (machine-type)) "osx")
                    (+ 256 length)
                    1))
    (do ([i 0 (+ i 1)]) ((= i n))
      (ftype-set! host-sockaddr (path i) a (bytevector-u8-ref bytes i)))
    (ftype-set! host-sockaddr (path n) a 0)
    length))

;; A socket listening at path, which only this user can reach; what was there
;; before goes, unless it's a plain file. A client that goes away must fail a
;; write, not end the world: SIGPIPE is ignored from now on.
(define (host-socket-listen path)
  (c-signal 13 1)
  (when (file-exists? path)
    (when (file-regular? path)
      (errorf 'host-socket-listen "there's a file at ~a" path))
    (delete-file path))
  (let ([fd (c-socket 1 1 0)]   ; AF_UNIX, SOCK_STREAM
        [length (host-socket-address! path)])
    (when (< fd 0) (errorf 'host-socket-listen "no socket"))
    (unless (and (zero? (c-bind fd (ftype-pointer-address host-sockaddr*)
                                length))
                 (begin (chmod path #o600) (zero? (c-listen fd 8))))
      (c-close fd)
      (errorf 'host-socket-listen "can't listen at ~a" path))
    fd))

;; A socket connected to path, or #f.
(define (host-socket-connect path)
  (let* ([length (host-socket-address! path)] [fd (c-socket 1 1 0)])
    (if (and (>= fd 0)
             (zero? (c-connect fd (ftype-pointer-address host-sockaddr*)
                               length)))
        fd
        (begin (when (>= fd 0) (c-close fd)) #f))))

;; Would events (poll's: 1, in; 4, out) go at once, or has it ended?
(define (host-socket-ready? fd events)
  (let ([p host-pollfd*])
    (ftype-set! host-pollfd (fd) p fd)
    (ftype-set! host-pollfd (events) p events)
    (ftype-set! host-pollfd (revents) p 0)
    (and (> (c-poll (ftype-pointer-address p) 1 0) 0)
         (not (zero? (ftype-ref host-pollfd (revents) p))))))

;; A client waiting at listening socket fd, as a socket of its own, or #f.
(define (host-socket-accept fd)
  (and (host-socket-ready? fd 1)
       (let ([c (c-accept fd 0 0)]) (and (>= c 0) c))))

;; What's there into bytes: how many; 0, it has ended; #f, nothing yet.
(define (host-socket-read fd bytes)
  (and (host-socket-ready? fd 1)
       (max 0 (c-recv fd bytes (bytevector-length bytes) 0))))

;; bytes from at on, as much as goes now. => where that leaves it, or #f once
;; the other end has gone
(define (host-socket-write fd bytes at)
  (let loop ([at at] [left 32])
    (if (or (= at (bytevector-length bytes)) (= left 0)
            (not (host-socket-ready? fd 4)))
        at
        (let ([n (min host-socket-chunk (- (bytevector-length bytes) at))])
          (bytevector-copy! bytes at *host-socket-chunk* 0 n)
          (let ([sent (c-send fd *host-socket-chunk* n 0)])
            (and (> sent 0) (loop (+ at sent) (- left 1))))))))

;; No more will be written to fd: the other end reads to its end.
(define (host-socket-end-writing fd) (c-shutdown fd 1))

(define (host-socket-close fd) (c-close fd))
