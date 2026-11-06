;;; host.ss — the host window that the whole world lives in.
;;;
;;; 'sdl      : a real resizable window (SDL3 renderer + streaming texture)
;;; 'headless : no window at all, just the canvas (for tests and screenshots)
;;;
;;; Host events are translated into plain Scheme lists:
;;;   (mouse-move x y) (mouse-down x y button clicks) (mouse-up x y button)
;;;   (wheel dx dy) (key-down key mods) (text "a") (resize w h) (quit) ...
;;; key is a char for printable keys (#\a, #\space) or a symbol ('return,
;;; 'left, 'f1, ...); mods is a list drawn from (ctrl alt shift super).

(defvar *host* 'none)
(defvar *sdl-window* 0)
(defvar *sdl-renderer* 0)
(defvar *sdl-texture* 0)
(defvar *sdl-event* (foreign-alloc 128))   ; an SDL_Event
(defvar *host-scratch* (foreign-alloc 16))
(defvar *host-clipboard* "")
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
     (canvas-create! w h *host-scale*)]
    [(sdl)
     (sdl-set-hint "SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR" "0")
     (sdl-set-hint "SDL_MOUSE_FOCUS_CLICKTHROUGH" "1")
     (sdl-set-hint "SDL_APP_ID" host-app-id)
     (sdl-set-hint "SDL_RENDER_VSYNC" "1")
     (unless (sdl-init SDL_INIT_VIDEO)
       (errorf 'host-init! "SDL_Init failed: ~a" (sdl-get-error)))
     ;; w × h are logical pixels. How many physical pixels a window unit
     ;; holds, and the desktop's scale, are known once the window has a
     ;; renderer, so it opens hidden, a unit per logical pixel, and is sized
     ;; and centered before it is shown.
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
     (set! *sdl-renderer* (sdl-create-renderer *sdl-window* #f))
     (set! *host-vsync?* #t)   ; by the hint, till host-present-damage!
     (when (= 0 *sdl-renderer*)
       (errorf 'host-init! "SDL_CreateRenderer failed: ~a" (sdl-get-error)))
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

(define (host-shutdown!)
  (when (eq? *host* 'sdl)
    (sdl-destroy-texture *sdl-texture*)
    (sdl-destroy-renderer *sdl-renderer*)
    (sdl-destroy-window *sdl-window*)
    (sdl-quit)
    (set! *sdl-texture* 0)
    (set! *host* 'none)))

(define (host-set-title! title)
  (when (eq? *host* 'sdl) (sdl-set-window-title *sdl-window* title)))

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
;; draw is called with *cr* on a size × size transparent image.
(define (host-set-icon! size draw)
  (when (eq? *host* 'sdl)
    (let* ([surface (cairo-image-surface-create CAIRO_FORMAT_ARGB32 size size)]
           [cr (cairo-create surface)])
      (fluid-let ([*cr* cr]) (draw size))
      (cairo-destroy cr)
      (cairo-surface-flush surface)
      (let ([data (cairo-image-surface-get-data surface)]
            [stride (cairo-image-surface-get-stride surface)])
        (unpremultiply! data stride size size)
        (let ([icon (sdl-create-surface-from size size
                                             SDL_PIXELFORMAT_ARGB8888
                                             data stride)])
          (unless (= icon 0)
            (sdl-set-window-icon *sdl-window* icon)   ; SDL copies the pixels
            (sdl-destroy-surface icon))))
      (cairo-surface-destroy surface))))

;; Cairo keeps color premultiplied by alpha; SDL wants it straight.
(define (unpremultiply! data stride w h)
  (do ([y 0 (+ y 1)]) ((= y h))
    (do ([x 0 (+ x 1)]) ((= x w))
      (let* ([i (+ (* y stride) (* 4 x))]
             [p (foreign-ref 'unsigned-32 data i)]
             [a (fxsrl p 24)])
        (when (fx< 0 a 255)
          (let ([un (lambda (c)
                      (fxmin 255 (fxquotient (fx+ (fx* c 255) (fxquotient a 2))
                                             a)))])
            (foreign-set! 'unsigned-32 data i
                          (fxior (fxsll a 24)
                                 (fxsll (un (fxand (fxsrl p 16) 255)) 16)
                                 (fxsll (un (fxand (fxsrl p 8) 255)) 8)
                                 (un (fxand p 255))))))))))

;; The window's size in window units and its renderer's in physical
;; pixels, (values w h pw ph); sets *pixel-ratio* from them.
(define (host-read-sizes)
  (sdl-get-window-size *sdl-window* *host-scratch* (+ *host-scratch* 4))
  (let ([w (foreign-ref 'integer-32 *host-scratch* 0)]
        [h (foreign-ref 'integer-32 *host-scratch* 4)])
    (sdl-get-current-render-output-size *sdl-renderer* *host-scratch*
                                        (+ *host-scratch* 4))
    (let ([pw (foreign-ref 'integer-32 *host-scratch* 0)]
          [ph (foreign-ref 'integer-32 *host-scratch* 4)])
      (set! *pixel-ratio* (/ pw (max w 1)))
      (values w h pw ph))))

;; Re-reads the window's pixel size and the scale; recreates canvas and
;; texture when either changed. Returns #t if they did.
(define (host-sync-size!)
  (case *host*
    [(sdl)
     (let-values ([(w h pw ph) (host-read-sizes)])
       (let ([scale (wanted-scale)])
         (if (and (= pw (canvas-pixel-width)) (= ph (canvas-pixel-height))
                  (= scale *host-scale*)
                  (not (= 0 *sdl-texture*)))
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
               (host-recreate-texture!)
               #t))))]
    [(headless)
     (let ([scale (wanted-scale)])
       (and (not (= scale *host-scale*))
            (begin
              (set! *host-scale* scale)
              (canvas-create! (car *headless-size*) (cdr *headless-size*) scale)
              #t)))]
    [else #f]))

;; A streaming texture the canvas's size; its pixels are undefined until
;; the next (full) upload. It is shown 1:1, so it is not filtered (SDL3's
;; default would).
(define (host-recreate-texture!)
  (when (eq? *host* 'sdl)
    (unless (= 0 *sdl-texture*) (sdl-destroy-texture *sdl-texture*))
    (set! *sdl-texture*
      (sdl-create-texture *sdl-renderer* SDL_PIXELFORMAT_ARGB8888
                          SDL_TEXTUREACCESS_STREAMING
                          (canvas-pixel-width) (canvas-pixel-height)))
    (sdl-set-texture-scale-mode *sdl-texture* SDL_SCALEMODE_NEAREST))
  (set! *full-upload?* #t))

;;; ------------------------------------------------------------------ upload
;;; A step that drew a frame uploads the rows it changed, each run of them
;;; as one full-width rectangle, and shows the texture. A step that changed
;;; no row neither uploads nor presents (nor waits for vsync).

;; rows the canvas changed since the last upload, ((y0 . y1) ...)
(defvar *upload-rows* '())
;; the texture must be refreshed whole (it was just made, say)
(defvar *full-upload?* #t)
;; show the texture again, unchanged (the host window was exposed)
(defvar *present-only?* #f)
(defvar *upload-bytes* 0)      ; bytes uploaded so far (counted headless too)
(defvar *host-rect* (foreign-alloc 16))   ; an SDL_Rect

;; The whole texture afresh, whatever the frame changed.
(define (invalidate-screen!)
  (set! *full-upload?* #t)
  (request-frame!))

;; Back buffers are undefined after a present: the whole texture each time.
(define (host-show-texture!)
  (sdl-render-texture *sdl-renderer* *sdl-texture* 0 0)
  ;; with vsync on, this waits for the screen: a phase of the profiler's
  (let ([t (now-ns)])
    (with-profile-span 'vsync-wait #f (sdl-render-present *sdl-renderer*))
    (pacer-waited! t)))

;; How many threads this machine runs at once (logical cores).
(define (host-cpu-count) (sdl-get-num-logical-cpu-cores))

;; How long the screen shows a frame, ns: by its display's refresh rate
;; (SDL_DisplayMode's numerator and denominator, at 24 and 28), or 60 Hz
;; when SDL does not say (headless, say).
(define (host-frame-ns)
  (let* ([m (if (eq? *host* 'sdl)
                (sdl-get-current-display-mode
                 (sdl-get-display-for-window *sdl-window*))
                0)]
         [hz (if (= m 0) 0 (foreign-ref 'int m 24))]
         [per (if (= m 0) 0 (foreign-ref 'int m 28))])
    (if (and (> hz 0) (> per 0))
        (quotient (* 1000000000 per) hz)
        (quotient 1000000000 60))))

;; Hidden, minimized or covered, the host window shows nothing: no upload
;; nor present (whose wait for the screen would hold the pacer's ticks
;; back), and the whole texture again once it shows. Without the focus it
;; does not wait for the screen either: the desktop may let a window it
;; hardly shows present seldom, whatever its flags say.
(defvar *host-vsync?* #t)
(define (host-present-damage!)
  (let* ([flags (if (eq? *host* 'sdl) (sdl-get-window-flags *sdl-window*) 0)]
         [focus? (logtest flags SDL_WINDOW_INPUT_FOCUS)])
    (unless (or (not (eq? *host* 'sdl)) (eq? focus? *host-vsync?*))
      (set! *host-vsync?* focus?)
      (sdl-set-render-vsync *sdl-renderer* (if focus? 1 0)))
    ;; SDL_WINDOW_OCCLUDED, _HIDDEN and _MINIMIZED
    (if (logtest flags #x4c)
        (begin
          (set! *upload-rows* '())
          (set! *full-upload?* #t)
          (set! *present-only?* #f))
        (host-upload-damage!))))

(define (host-upload-damage!)
  (let ([runs (cond [(eqv? *canvas* 0) '()]
                    [*full-upload?* (list (cons 0 *canvas-ph*))]
                    [else *upload-rows*])])
    (for-each (lambda (r)
                (set! *upload-bytes*
                      (+ *upload-bytes* (* 4 *canvas-pw* (- (cdr r) (car r))))))
              runs)
    (when (eq? *host* 'sdl)
      (cond
        [(pair? runs)
         (let ([data (cairo-image-surface-get-data *canvas*)]
               [stride (cairo-image-surface-get-stride *canvas*)])
           (cairo-surface-flush *canvas*)
           (for-each (lambda (r)
                       (foreign-set! 'integer-32 *host-rect* 0 0)
                       (foreign-set! 'integer-32 *host-rect* 4 (car r))
                       (foreign-set! 'integer-32 *host-rect* 8 *canvas-pw*)
                       (foreign-set! 'integer-32 *host-rect* 12
                                     (- (cdr r) (car r)))
                       (sdl-update-texture *sdl-texture* *host-rect*
                                           (+ data (* stride (car r))) stride))
                     runs))
         (host-show-texture!)]
        [*present-only?* (host-show-texture!)]))
    (set! *upload-rows* '())
    (set! *full-upload?* #f)
    (set! *present-only?* #f)))

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

;; The offsets are into SDL3's event structs (SDL_events.h).
(define (sdl-event->list buf)
  (let ([type (foreign-ref 'unsigned-32 buf 0)])
    (cond
      [(= type SDL_EVENT_QUIT) '(quit)]
      [(= type SDL_EVENT_KEY_DOWN)
       (list 'key-down (sdl-key->key (foreign-ref 'unsigned-32 buf 28))
             (sdl-mods->list (foreign-ref 'unsigned-16 buf 32)))]
      [(= type SDL_EVENT_TEXT_INPUT)
       (list 'text (c-string->string (foreign-ref 'uptr buf 24)))]
      [(= type SDL_EVENT_MOUSE_MOTION)
       (list 'mouse-move
             (host->world (foreign-ref 'float buf 28))
             (host->world (foreign-ref 'float buf 32)))]
      [(= type SDL_EVENT_MOUSE_BUTTON_DOWN)
       (list 'mouse-down
             (host->world (foreign-ref 'float buf 28))
             (host->world (foreign-ref 'float buf 32))
             (sdl-button->symbol (foreign-ref 'unsigned-8 buf 24))
             (foreign-ref 'unsigned-8 buf 26))]
      [(= type SDL_EVENT_MOUSE_BUTTON_UP)
       (list 'mouse-up
             (host->world (foreign-ref 'float buf 28))
             (host->world (foreign-ref 'float buf 32))
             (sdl-button->symbol (foreign-ref 'unsigned-8 buf 24)))]
      [(= type SDL_EVENT_MOUSE_WHEEL) (sdl-wheel->list buf)]
      [(or (= type SDL_EVENT_WINDOW_RESIZED)
           (= type SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED)
           (= type SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED))
       (and (host-sync-size!) (list 'resize *canvas-w* *canvas-h*))]
      [(= type SDL_EVENT_WINDOW_EXPOSED) '(expose)]
      [(= type SDL_EVENT_WINDOW_MOUSE_LEAVE) '(mouse-leave)]
      [(= type SDL_EVENT_RENDER_TARGETS_RESET) '(render-reset)]
      [(= type SDL_EVENT_RENDER_DEVICE_RESET) '(device-reset)]
      [else #f])))

(defvar *wheel-rest* '(0 . 0))   ; wheel travel not passed on yet, x . y

;; SDL3 reports the wheel in fractions of a step (touchpads, fine wheels);
;; the world takes whole steps, as SDL2 gave them: (wheel dx dy), or #f
;; until a whole step has added up.
;; A leftover is dropped when the wheel turns the other way, as in SDL2.
(define (sdl-wheel-add rest d) (+ (if (negative? (* rest d)) 0 rest) d))

(define (sdl-wheel->list buf)
  (let* ([flip (if (= 1 (foreign-ref 'unsigned-32 buf 32)) -1 1)]
         [x (sdl-wheel-add (car *wheel-rest*)
                           (* flip (exact (foreign-ref 'float buf 24))))]
         [y (sdl-wheel-add (cdr *wheel-rest*)
                           (* flip (exact (foreign-ref 'float buf 28))))]
         [dx (truncate x)]
         [dy (truncate y)])
    (set! *wheel-rest* (cons (- x dx) (- y dy)))
    (and (not (= 0 dx dy)) (list 'wheel dx dy))))

;; Waits up to wait-ms for the first event, then drains the queue.
;; Without the screen's wait, frames come only with ticks, and so does
;; input: it sleeps the whole wait, a step a tick and not one an event.
(define (host-events wait-ms)
  (if (eq? *host* 'sdl)
      (let ([buf *sdl-event*])
        (unless (or *host-vsync?* (<= wait-ms 0))
          (sleep (make-time 'time-duration
                            (* 1000000 (remainder wait-ms 1000))
                            (quotient wait-ms 1000))))
        (let loop ([more? (if (and *host-vsync?* (> wait-ms 0))
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
