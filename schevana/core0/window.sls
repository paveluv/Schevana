;;; (schevana core0 window) — core0's window (.work/gpu-design.md 9.12): SDL's
;;; window, its events and what it says of itself, as plain data the world
;;; reads ((schevana core screen)), never SDL's pointers. Positions come in the
;;; window's units, as SDL gives them; the world lays them out.
;;;
;;; *core0-mode* says what core0 runs, 'none before it starts:
;;; 'sdl      : a real resizable window, on the GPU
;;; 'headless : no window at all, on the CPU's Vulkan driver (for tests and
;;;             screenshots)

(library (schevana core0 window)
  (export
    *core0-mode* *sdl-window* *sdl-event* *core0-clipboard* core0-app-id
    core0-app-id! core0-window-title! core0-system-theme core0-own-frame!
    core0-own-frame? core0-hit core0-window-hit-regions! core0-window-action!
    core0-window-maximized? core0-window-headless!
    core0-window-open! core0-window-show! core0-window-close!
    core0-window-sizes core0-window-resize! core0-resize-now!
    core0-window-minimum! core0-window-scale
    core0-window-fullscreen? core0-window-fullscreen! core0-window-icon!
    core0-flags core0-flag-names core0-error-text core0-event-name
    core0-hidden? sdl-event->list *wheel-rest* core0-window-pump
    core0-input-ns-take! core0-set-cursor! clipboard-get clipboard-set!
    *core0-inbox* *core0-job-failed* core0-post-submit! core0-post-reads!
    core0-quit! core0-loop! core0-window-start! core0-fork-loop! core0-run!
    *core0-sleeping* core0-sleep-release! core0-sleep! gpu-present-published!
    core0-step! core0-events-pumped! core0-window-events core0-facts-refresh!
    core0-step-state)
  (import (chezscheme)
          (schevana base)
          (schevana ffi)
          (schevana sdl)
          (schevana core0 mail)
          (schevana core0 trace)
          (schevana core0 renderer)
          (schevana core0 present)
          (schevana core0 platform)
          (schevana core0 trace-file)
          (schevana core0 gpu))

  (library-layer core0)

  (define-state *core0-mode* 'none)
  (define-state *sdl-window* 0)
  (define-state *sdl-event* (foreign-alloc 128))   ; an SDL_Event
  ;; what SDL says of the window's size: a place for it, a pointer made once
  (define-ftype core0-size (struct [w int] [h int]))
  (define-state *core0-scratch* (foreign-alloc (ftype-sizeof core0-size)))
  (define-made core0-size* (make-ftype-pointer core0-size *core0-scratch*))
  (define-state *core0-clipboard* "")   ; what headless mode keeps
  (define-state *cursors* (make-eq-hashtable))
  (define-state *current-cursor* #f)

  ;; Who the window is to the desktop: its app id under Wayland, its
  ;; class under X11, which the desktop matches to a desktop entry ((schevana
  ;; desktop icon) writes Schevana's). A program of its own may take another
  ;; before its window opens (core0-app-id!).
  (define-state core0-app-id "schevana")

  (define (core0-app-id! id)
    (unless (eq? *core0-mode* 'none)
      (errorf 'core0-app-id! "the window is open already"))
    (set! core0-app-id id))

  ;; Whether the program draws its window's frame itself where the desktop
  ;; draws none (a host app's header bar), asked before the window opens;
  ;; and whether it does, the window open: under Wayland, a compositor that
  ;; lists no xdg-decoration (GNOME's), where libdecor would draw it. Its
  ;; GTK plugin redraws its title bar at each step of a resize inside SDL's
  ;; pump, which held core0 3 to 240 ms a step (Debian 13, libdecor 0.2.2).
  (define-state *core0-own-frame-asked* #f)
  (define-state *core0-own-frame* #f)

  (define (core0-own-frame! on?)
    (unless (eq? *core0-mode* 'none)
      (errorf 'core0-own-frame! "the window is open already"))
    (set! *core0-own-frame-asked* on?))

  (define (core0-own-frame?) *core0-own-frame*)

  ;; The window's regions by which the desktop moves or resizes it, a frame
  ;; of the program's own: #(kind x y w h ...) in window units, kind SDL's
  ;; (0 the program's, 1 a drag that moves it, 2 to 9 a resize from the
  ;; top left round to the left); the first that holds the point wins.
  (define-state *core0-hit-regions* (vector))

  ;; What of the window is at (x, y), window units: SDL's kind.
  (define (core0-hit x y)
    (let ([v *core0-hit-regions*])
      (let loop ([i 0])
        (cond
          [(fx>= i (vector-length v)) 0]
          [(and (fx<= (vector-ref v (fx+ i 1)) x)
                (fx< x (fx+ (vector-ref v (fx+ i 1)) (vector-ref v (fx+ i 3))))
                (fx<= (vector-ref v (fx+ i 2)) y)
                (fx< y (fx+ (vector-ref v (fx+ i 2)) (vector-ref v (fx+ i 4)))))
           (vector-ref v i)]
          [else (loop (fx+ i 5))]))))

  ;; SDL's hit test: called on core0's thread, in SDL's pump, as the
  ;; pointer moves.
  (define-made core0-hit-test-code
    (let ([code (foreign-callable __collect_safe
                                  (lambda (sdl-win point data)
                                    (core0-hit (foreign-ref 'int point 0)
                                               (foreign-ref 'int point 4)))
                                  (uptr uptr uptr) int)])
      (lock-object code)
      (foreign-callable-entry-point code)))

  ;; The regions, from core1: a job.
  (define (core0-window-hit-regions! v)
    (core0-post! (list core0-hit-regions-now! v)))
  (define (core0-hit-regions-now! v) (set! *core0-hit-regions* v))

  ;; The window maximized, restored or minimized, or the desktop's menu for
  ;; it shown at (x, y), window units: a job.
  (define (core0-window-action! action . at)
    (when (eq? *core0-mode* 'sdl)
      (core0-post! (list core0-action-now! action at))))
  (define (core0-action-now! action at)
    (case action
      [(maximize) (sdl-maximize-window *sdl-window*)]
      [(restore) (sdl-restore-window *sdl-window*)]
      [(minimize) (sdl-minimize-window *sdl-window*)]
      [(menu) (sdl-show-window-system-menu *sdl-window* (car at) (cadr at))]))

  ;; SDL's flags include a change asked for and not made yet.
  (define (core0-window-maximized?) (logtest (core0-flags) #x80))

  ;;; ------------------------------------------------------------------ window

  ;; Once for all: video, the driver named if one is.
  (define (core0-window-init! driver)
    (when driver (sdl-set-hint "SDL_VIDEO_DRIVER" driver))
    (unless (sdl-init SDL_INIT_VIDEO)
      (errorf 'core0-window-init! "SDL_Init failed: ~a" (sdl-get-error))))

  ;; No window: the GPU draws to a target, on the windowless driver.
  (define (core0-window-headless!)
    (set! *core0-mode* 'headless)
    ;; on a Mac, no Dock icon and no taking the focus from what you're doing
    (sdl-set-hint "SDL_MAC_BACKGROUND_APP" "1")
    (core0-window-init! gpu-windowless-video)
    (unless *renderer* (gpu-open! gpu-windowless-kind))
    (core0-platform-read!))

  ;; The window, w × h window units, hidden till it's sized and shown, full
  ;; screen if asked; the GPU draws to it from then on.
  (define (core0-window-open! w h full?)
    (set! *core0-mode* 'sdl)
    (core0-trace-start!)
    (sdl-set-hint "SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR" "0")
    (sdl-set-hint "SDL_MOUSE_FOCUS_CLICKTHROUGH" "1")
    (sdl-set-hint "SDL_APP_ID" core0-app-id)
    (set! *core0-own-frame*
      (and *core0-own-frame-asked* (platform-desktop-frameless?)))
    (when *core0-own-frame*
      (sdl-set-hint "SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR" "0"))
    (core0-window-init! #f)
    ;; SDL may have taken another video driver
    (unless (platform-sdl-wayland?) (set! *core0-own-frame* #f))
    (set! *sdl-window*
      (sdl-create-window "Schevana" w h
                         (fxior SDL_WINDOW_RESIZABLE
                                SDL_WINDOW_HIGH_PIXEL_DENSITY
                                SDL_WINDOW_HIDDEN
                                (if full? SDL_WINDOW_FULLSCREEN 0))))
    (when (= 0 *sdl-window*)
      (errorf 'core0-window-open! "SDL_CreateWindow failed: ~a"
              (sdl-get-error)))
    (when *core0-own-frame*
      (sdl-set-window-hit-test *sdl-window* core0-hit-test-code 0))
    (unless *renderer* (gpu-open! 'gpu))
    (gpu-claim-window! *sdl-window*)
    (core0-platform-read!)
    (core0-facts-refresh! #t))

  ;; Centered on its display and shown, taking text from then on.
  (define (core0-window-show!)
    (sdl-set-window-position *sdl-window* SDL_WINDOWPOS_CENTERED
                             SDL_WINDOWPOS_CENTERED)
    (sdl-show-window *sdl-window*)
    (sdl-start-text-input *sdl-window*)
    (core0-clipboard-read!)
    (platform-reports-start! *sdl-window*)
    (core0-facts-refresh! #t))

  (define (core0-window-close!)
    (gpu-idle!)
    (sdl-release-window (renderer-device *renderer*) *sdl-window*)
    (sdl-destroy-window *sdl-window*)
    (sdl-quit)
    (set! *renderer* #f)
    (set! *core0-mode* 'none))

  ;; The window's size in window units and in physical pixels, as core0 last
  ;; read it: (values w h pw ph).
  (define (core0-window-sizes)
    (let ([f *core0-facts*])
      (values (vector-ref f 1) (vector-ref f 2) (vector-ref f 3)
              (vector-ref f 4))))

  ;; The size get, one of SDL's, says: (values w h).
  (define (core0-size-from get)
    (get *sdl-window*
         (ftype-pointer-address (ftype-&ref core0-size (w) core0-size*))
         (ftype-pointer-address (ftype-&ref core0-size (h) core0-size*)))
    (values (ftype-ref core0-size (w) core0-size*)
            (ftype-ref core0-size (h) core0-size*)))

  ;; To w × h window units: from core1, once core0 has a thread of its own, a
  ;; job of core0's.
  (define (core0-window-resize! w h)
    (if *core0-forked*
        (core0-post! (list core0-resize-now! w h))
        (core0-resize-now! w h)))
  (define (core0-resize-now! w h)
    (sdl-set-window-size *sdl-window* w h)
    (core0-facts-refresh! #t))

  ;; The least it may be dragged to, in window units: a job of core0's.
  (define (core0-window-minimum! w h)
    (core0-post! (list core0-minimum-now! w h)))
  (define (core0-minimum-now! w h)
    (sdl-set-window-minimum-size *sdl-window* w h))

  ;; SDL's display scale for the window as last read; 0 is SDL's failure, 1
  ;; with no window.
  (define (core0-window-scale)
    (if (eq? *core0-mode* 'sdl) (vector-ref *core0-facts* 5) 1))

  ;; SDL3's flags include a change asked for and not made yet.
  (define (core0-window-fullscreen?)
    (logtest (core0-flags) SDL_WINDOW_FULLSCREEN))

  (define (core0-window-fullscreen! on?)
    (core0-post! (list core0-fullscreen-now! on?)))
  (define (core0-fullscreen-now! on?)
    (sdl-set-window-fullscreen *sdl-window* on?))

  ;; The window's icon, from size × size straight ARGB pixels: a job, in which
  ;; SDL copies them.
  (define (core0-window-icon! size bytes)
    (core0-post! (list core0-icon-now! size bytes)))
  (define (core0-icon-now! size bytes)
    (let ([icon (sdl-create-surface-from size size SDL_PIXELFORMAT_ARGB8888
                                         (object->reference-address bytes)
                                         (* 4 size))])
      (unless (= icon 0)
        (sdl-set-window-icon *sdl-window* icon)
        (sdl-destroy-surface icon))))

  ;; The window's title, as the desktop shows it (its title bar, the
  ;; switcher): a job, in which SDL copies it.
  (define (core0-window-title! title)
    (when (eq? *core0-mode* 'sdl)
      (core0-post! (list core0-title-now! title))))
  (define (core0-title-now! title)
    (sdl-set-window-title *sdl-window* title))

  ;; The desktop's preference, light or dark, as SDL last read it: 'light,
  ;; 'dark, or #f where it says none (no window, or a desktop that doesn't
  ;; tell).
  (define (core0-system-theme)
    (case (vector-ref *core0-facts* 9) [(1) 'light] [(2) 'dark] [else #f]))

  ;;; ------------------------------------------------------------------ display

  ;; SDL_DisplayMode (SDL_video.h).
  (define-ftype sdl-display-mode
    (struct [display unsigned-32] [format unsigned-32] [w int] [h int]
            [density float] [refresh float] [numerator int] [denominator int]))

  ;; The window's display's mode, or #f when SDL does not say (headless, say).
  (define (core0-display-mode)
    (let ([m (if (eq? *core0-mode* 'sdl)
                 (sdl-get-current-display-mode
                  (sdl-get-display-for-window *sdl-window*))
                 0)])
      (and (not (= m 0)) (make-ftype-pointer sdl-display-mode m))))

  ;; How long the screen shows a frame, ns: by its display's refresh rate, or
  ;; 60 Hz when SDL does not say.
  (define (core0-read-frame-ns)
    (let* ([m (core0-display-mode)]
           [hz (if m (ftype-ref sdl-display-mode (numerator) m) 0)]
           [per (if m (ftype-ref sdl-display-mode (denominator) m) 0)])
      (if (and (> hz 0) (> per 0))
          (quotient (* 1000000000 per) hz)
          (quotient 1000000000 60))))

  ;; The display as a person reads it: (w h refresh-numerator denominator
  ;; density), or #f.
  (define (core0-read-display)
    (let ([m (core0-display-mode)])
      (and m
           (list (ftype-ref sdl-display-mode (w) m)
                 (ftype-ref sdl-display-mode (h) m)
                 (ftype-ref sdl-display-mode (numerator) m)
                 (ftype-ref sdl-display-mode (denominator) m)
                 (ftype-ref sdl-display-mode (density) m)))))

  ;; What SDL says of the window and last went wrong with it, as core0
  ;; last read them. It's all for whoever is looking into a late tick.
  (define (core0-flags) (vector-ref *core0-facts* 0))

  (define (core0-flag-names flags)
    (map cdr
         (filter (lambda (bit) (logtest flags (car bit)))
                 '((#x1 . fullscreen)
                   (#x4 . occluded)
                   (#x8 . hidden)
                   (#x40 . minimized)
                   (#x80 . maximized)
                   (#x200 . input-focus)
                   (#x400 . mouse-focus)))))

  (define (core0-error-text) (vector-ref *core0-facts* 8))

  ;; An event's name, by its number (SDL_events.h); or the number.
  (define (core0-event-name type)
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

  ;; Hidden, minimized or covered, the window shows nothing: no frames,
  ;; which wait until it shows.
  (define-hook (core0-hidden?)
    ;; SDL_WINDOW_OCCLUDED, _HIDDEN and _MINIMIZED
    (and (eq? *core0-mode* 'sdl) (logtest (core0-flags) #x4c)))

  ;;; ------------------------------------------------------------------ events

  (define sdl-special-keys
    '((13 . return) (8 . backspace) (9 . tab) (27 . escape) (127 . delete)
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
            [window-number unsigned-32] [which unsigned-32]))

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

  ;; An SDL_Event at address buf, as plain data, positions in window units: a
  ;; change of the window's size, scale or pixels as (window-resized); #f for
  ;; what means nothing to the world.
  (define (sdl-event->list buf)
    (let* ([e (make-ftype-pointer sdl-event buf)]
           [type (ftype-ref sdl-event (head type) e)]
           [x (lambda () (ftype-ref sdl-event (mouse x) e))]
           [y (lambda () (ftype-ref sdl-event (mouse y) e))])
      (cond
        [(= type SDL_EVENT_QUIT) '(quit)]
        [(= type SDL_EVENT_KEY_DOWN)
         (list 'key-down (sdl-key->key (ftype-ref sdl-event (key key) e))
               (sdl-mods->list (ftype-ref sdl-event (key mods) e)))]
        [(= type SDL_EVENT_TEXT_INPUT)
         (list 'text (c-string->string (ftype-ref sdl-event (text text) e)))]
        [(= type SDL_EVENT_MOUSE_MOTION) (list 'mouse-move (x) (y))]
        [(= type SDL_EVENT_MOUSE_BUTTON_DOWN)
         (list 'mouse-down (x) (y)
               (sdl-button->symbol (ftype-ref sdl-event (mouse button) e))
               (ftype-ref sdl-event (mouse clicks) e))]
        [(= type SDL_EVENT_MOUSE_BUTTON_UP)
         (list 'mouse-up (x) (y)
               (sdl-button->symbol (ftype-ref sdl-event (mouse button) e)))]
        [(= type SDL_EVENT_MOUSE_WHEEL) (sdl-wheel->list e)]
        [(or (= type SDL_EVENT_WINDOW_RESIZED)
             (= type SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED)
             (= type SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED))
         '(window-resized)]
        [(= type SDL_EVENT_WINDOW_EXPOSED) '(expose)]
        [(= type SDL_EVENT_SYSTEM_THEME_CHANGED) '(system-theme-changed)]
        [(= type SDL_EVENT_WINDOW_MOUSE_LEAVE) '(mouse-leave)]
        [else #f])))

  (define-state *wheel-rest* '(0 . 0))

  ;; SDL3 reports the wheel in fractions of a step (touchpads, fine wheels);
  ;; the world takes whole steps, as SDL2 gave them: (wheel dx dy), or #f
  ;; until a whole step has added up.
  ;; A leftover is dropped when the wheel turns the other way, as in SDL2.
  (define (sdl-wheel-add rest d) (+ (if (negative? (* rest d)) 0 rest) d))

  (define (sdl-wheel->list e)
    (let* ([flip (if (= 1 (ftype-ref sdl-event (wheel direction) e)) -1 1)]
           [x (sdl-wheel-add
               (car *wheel-rest*)
               (* flip (exact (ftype-ref sdl-event (wheel x) e))))]
           [y (sdl-wheel-add
               (cdr *wheel-rest*)
               (* flip (exact (ftype-ref sdl-event (wheel y) e))))]
           [dx (truncate x)]
           [dy (truncate y)])
      (set! *wheel-rest* (cons (- x dx) (- y dy)))
      (and (not (= 0 dx dy)) (list 'wheel dx dy))))

  ;; The queue drained, with no wait: (values events types first), the
  ;; events as sdl-event->list gives them, every event's number in order,
  ;; whether it means anything or not, and when SDL took the first that came
  ;; from the keyboard or the mouse (core0-now-ns; 0, none).
  (define-hook (core0-window-pump)
    (if (eq? *core0-mode* 'sdl)
        (let ([buf *sdl-event*])
          (let loop ([more? (sdl-poll-event buf)] [acc '()] [types '()]
                     [first 0])
            (if more?
                (let ([type (foreign-ref 'unsigned-32 buf 0)]
                      [e (sdl-event->list buf)])
                  (loop (sdl-poll-event buf) (if e (cons e acc) acc)
                        (cons type types)
                        (if (and (eqv? first 0)
                                 (memv type '(#x300 #x301 #x303 #x400 #x401
                                              #x402 #x403)))
                            (ftype-ref sdl-event-head (timestamp)
                                       (make-ftype-pointer sdl-event-head buf))
                            first)))
                (values (reverse acc) (reverse types) first))))
        (values '() '() 0)))

  ;; When the oldest input since the last take came, taken, by SDL, core0's
  ;; pump and the compositor: (values sdl pumped compositor), 0 for none.
  (define (core0-input-ns-take!)
    (values (core0-input-take! *core0-input-ns*)
            (core0-input-take! *core0-input-pumped*)
            (core0-input-take! *core0-input-wl*)))

  ;;; ------------------------------------------------------------------
  ;;; cursor & clipboard

  (define cursor-ids
    '((arrow . 0) (ibeam . 1) (wait . 2) (crosshair . 3) (resize-nwse . 5)
      (resize-nesw . 6) (resize-ew . 7) (resize-ns . 8) (move . 9) (hand . 11)))

  ;; The pointer's shape, with a window a job of core0's when it changes from
  ;; what was last asked (the asker's, so a move that keeps it posts nothing).
  (define-state *core0-cursor-asked* #f)
  (define (core0-set-cursor! kind)
    (when (and (eq? *core0-mode* 'sdl) (not (eq? kind *core0-cursor-asked*)))
      (set! *core0-cursor-asked* kind)
      (core0-post! (list core0-cursor-now! kind))))

  (define (core0-cursor-now! kind)
    (when (and (eq? *core0-mode* 'sdl) (not (eq? kind *current-cursor*)))
      (set! *current-cursor* kind)
      (sdl-set-cursor
       (or (hashtable-ref *cursors* kind #f)
           (let ([c (sdl-create-system-cursor
                     (cdr (or (assq kind cursor-ids) '(arrow . 0))))])
             (hashtable-set! *cursors* kind c)
             c)))))

  ;; The clipboard's text, as core0 read it last: when the window showed, and
  ;; whenever SDL said it changed; headless, it's kept here.
  (define (clipboard-get) *core0-clipboard*)

  (define (core0-clipboard-read!)
    (let* ([p (sdl-get-clipboard-text)] [s (c-string->string p)])
      (unless (= p 0) (sdl-free p))
      (set! *core0-clipboard* s)))

  ;; With a window, a job of core0's.
  (define (clipboard-set! s)
    (if (eq? *core0-mode* 'sdl)
        (core0-post! (list core0-clipboard-now! s))
        (set! *core0-clipboard* s)))

  (define (core0-clipboard-now! s)
    (sdl-set-clipboard-text s)
    (set! *core0-clipboard* s))

  ;;; ------------------------------------------------------------------ step
  ;;; Core0 runs the window in steps: the jobs the world posted, then the
  ;;; events, put in the world's inbox, then what it says of itself, read
  ;;; again. On one thread the world steps it where it waits for input; once
  ;;; core0 has a thread, its loop does (.work/gpu-design.md 9.4).

  ;; The events pumped and not yet taken, newest first, each (events .
  ;; types) of a step; the jobs posted are (schevana core0 mail)'s.
  (define-state *core0-inbox* (box '()))
  ;; (job . condition): the last job that raised
  (define-state *core0-job-failed* #f)

  ;;; ------------------------------------------------------------------ core1
  ;;; With a window core0 runs on the process's first thread and the world on
  ;;; a thread of its own, core1 (.work/gpu-design.md 9.4): core1 waits for
  ;;; core0's events, frames given back and mail here, woken by whoever
  ;;; brings them. Headless, one thread plays both, and core0's step is the
  ;;; wait.

  ;; Compute runs and writes no frame took, sent by a job, the recorder's.
  (define (core0-post-submit! runs jobs writes)
    (core0-post! (list gpu-submit-computes! runs jobs writes)))

  ;; The same, and buffers read back after them (gpu-reads-now!).
  (define (core0-post-reads! runs jobs writes reads)
    (core0-post! (list gpu-reads-now! runs jobs writes reads)))

  ;; Core1 is done: core0 closes the window and ends the process.
  (define (core0-quit!) (core0-post! (list core0-quit-now!)))
  (define-state *core0-quit* #f)
  (define (core0-quit-now!) (set! *core0-quit* #t))

  ;; How long core0 sleeps with nothing to do: input waits that long at most;
  ;; while frames flow (one taken in the last 100 ms), a ms, so that core1's
  ;; turn, which begins just in time for the screen, finds the newest.
  (define core0-idle-ms 4)
  (define (core0-idle-ms-now)
    (if (< (- (core0-now-ns) *present-taken*) 100000000) 1 core0-idle-ms))

  ;; Core0's loop, on its own thread: its steps till core1 quits.
  (define (core0-loop!)
    (let loop ()
      (core0-step!)
      ;; while it boots, the boot screen at each refresh
      (when *gpu-booting* (gpu-boot-screen!))
      (if *core0-quit*
          (begin
            (when (eq? *core0-mode* 'sdl)
              ;; a trace that fails to write never keeps the window open
              (guard (c [#t #f]) (core0-trace-write!))
              (core0-window-close!))
            (exit 0))
          (loop))))

  ;; Core0 on this thread, the process's first, and the world on one of its
  ;; own, in two steps. The first: with a window (mode sdl), core0 opens it,
  ;; w × h logical pixels at the desktop's scale, or full screen, and clears
  ;; it; with none (headless, for the tests), its GPU draws to a target.
  (define (core0-window-start! mode w h full?)
    (if (eq? mode 'headless)
        (core0-window-headless!)
        (begin
          (core0-window-open! w h full?)
          (unless full?
            (let-values ([(uw uh pw ph) (core0-window-sizes)])
              (let ([s (/ (if (> (core0-window-scale) 0) (core0-window-scale) 1)
                          (/ pw (max uw 1)))])
                (core0-resize-now! (exact (round (* w s)))
                                   (exact (round (* h s)))))))
          (core0-window-show!)
          (set! *gpu-booting* #t)
          (gpu-boot-screen!))))

  ;; The second: the world's thread forked, which runs world, a thunk, and
  ;; asks core0 to quit when it returns, or raises; and core0's loop, on
  ;; this thread, till then.
  (define (core0-fork-loop! world)
    (set! *core0-forked* #t)
    (fork-thread
     (lambda ()
       (platform-thread-interactive!)
       (guard (c [#t (display-condition c (console-error-port))
                     (newline (console-error-port))])
         (world))
       (core0-quit!)))
    (core0-loop!))

  ;; Both, for a program on the libraries.
  (define (core0-run! mode w h full? world)
    (core0-window-start! mode w h full?)
    (core0-fork-loop! world))

  ;; Core0 sleeps up to ms, or till it's woken. Its events aren't a wake:
  ;; it looks for them each time it wakes, so ms bounds how long input
  ;; waits while nothing else comes (core0-idle-ms).
  ;;
  ;; A second Ctrl-C before the first is answered makes Chez drop the first
  ;; thread's stack where it stands (its noncontinuable interrupt): in the
  ;; wait too, where the mutex is given up. What unwinds then releases the
  ;; mutex only if it is held, where with-mutex's release would raise, and
  ;; say so as the run ends.
  (define-state *core0-sleeping* #f)   ; in the wait
  (define (core0-sleep-release!)
    (if *core0-sleeping*
        (begin
          (set! *core0-sleeping* #f)
          (guard (c [#t (void)]) (mutex-release *core0-world-mutex*)))
        (mutex-release *core0-world-mutex*)))
  (define (core0-sleep! ms)
    (dynamic-wind
      (lambda () (mutex-acquire *core0-world-mutex*))
      (lambda ()
        (unless (or *core0-woken* (<= ms 0))
          (core0-trace! 7 ms)
          (set! *core0-sleeping* #t)
          (condition-wait *core0-ready* *core0-world-mutex* (core0-ms ms))
          (set! *core0-sleeping* #f)
          (core0-trace! 8 0))
        (set! *core0-woken* #f))
      core0-sleep-release!))

  ;; Core0's side, in its step: the frame published, if one is, presented
  ;; and given back.
  (define (gpu-present-published!)
    (let ([f (unbox *gpu-published*)])
      (when f
        (memory-order-acquire)
        (let loop () (unless (box-cas! *gpu-published* f #f) (loop)))
        (core0-trace! 2 (gpu-frame-number f))
        (present-taken!)
        (set! *gpu-booting* #f)
        ;; taken: core1 may make the next (.work/gpu-design.md 9.12), with the
        ;; input that came till now, not only till the last step's pump
        (core0-events-pumped!)
        (core0-world-wake!)
        (gpu-frame-shown?-set! f (gpu-present! f))
        ;; the input that came while the acquire held core0, read before core1
        ;; hears the frame is back and may begin its next turn
        (core0-events-pumped!)
        (core0-put! *gpu-given-back* f)
        (core0-trace! 6 (gpu-frame-number f))
        ;; given back, with what it read: core1 takes them at once, whether
        ;; or not a frame follows
        (core0-world-wake!))))

  (define (core0-run-job! job)
    (guard (c [#t (set! *core0-job-failed* (cons job c))])
      (apply (car job) (cdr job))))

  ;; One step of core0's: the jobs posted, in order; the frame published, if
  ;; one is; with none, on a thread of its own, a sleep of up to
  ;; core0-idle-ms, which a job or a frame ends; the frames' GPU fences looked
  ;; at and the screen's reports read; the events into the world's inbox,
  ;; what the window says of itself read again first; with none, read again
  ;; all the same; core1, on a thread of its own, watched for a stall
  ;; (core0-trace-watch!). The sleep comes before
  ;; the pump, so that input that came while it slept goes in before the
  ;; next present can wait for the screen.
  (define (core0-step!)
    (let ([jobs (core0-take! *core0-jobs*)])
      (core0-trace! 1 (length jobs))
      (for-each core0-run-job! jobs)
      (unless (eq? *core0-mode* 'none) (gpu-present-published!))
      (when (and *core0-forked* (not (unbox *gpu-published*)))
        (core0-sleep! (core0-idle-ms-now)))
      (present-poll!)
      (unless (core0-events-pumped!) (core0-facts-refresh! (pair? jobs)))
      (when *core0-forked* (core0-trace-watch!))))

  ;; The events come since the last pump into the world's inbox, core1 woken
  ;; for them, and when the oldest input came; what the window says of itself
  ;; read again before, so that core1, taking a resize, finds the new size. A
  ;; pump that held core0 past 2 ms is traced, µs, with its events' types.
  ;; => whether any came.
  (define (core0-events-pumped!)
    (let*-values ([(t0) (core0-now-ns)]
                  [(events types first) (core0-window-pump)]
                  [(took) (- (core0-now-ns) t0)])
      (when (> took 2000000)
        (core0-trace! 13 (quotient took 1000))
        (for-each (lambda (type) (core0-trace! 14 type)) types))
      ;; core0's queue, which SDL's pump read into: the screen's reports, and
      ;; the compositor's input times
      (platform-reports-pump!)
      (unless (eqv? first 0)
        (core0-input-set! *core0-input-ns* first)
        (core0-input-set! *core0-input-pumped* (core0-now-ns)))
      (unless (null? types)
        (core0-trace! 9 (length types))
        (core0-facts-refresh! #t)
        (when (memv #x900 types) (core0-clipboard-read!))   ; clipboard-update
        (core0-put! *core0-inbox* (cons events types))
        (core0-world-wake!))
      (pair? types)))

  ;; The events core0's steps have put in the inbox since it was last taken,
  ;; as core0-window-pump gives them: (values events types); when the oldest
  ;; input came, core0-input-ns-take!.
  (define (core0-window-events)
    (let ([steps (core0-take! *core0-inbox*)])
      (if (null? steps)
          (values '() '())
          (values (apply append (map car steps))
                  (apply append (map cdr steps))))))

  ;; The facts read again: the flags and sizes each step, and made again when
  ;; they changed; the scale, the display and the last error too after
  ;; events or jobs (all?), as they change only with those.
  (define-hook (core0-facts-refresh! all?)
    (when (eq? *core0-mode* 'sdl)
      (let*-values ([(f) (sdl-get-window-flags *sdl-window*)]
                    [(w h) (core0-size-from sdl-get-window-size)]
                    [(pw ph) (core0-size-from sdl-get-window-size-in-pixels)])
        (let ([old *core0-facts*])
          (when (or all?
                    (not (and (= f (vector-ref old 0)) (= w (vector-ref old 1))
                              (= h (vector-ref old 2)) (= pw (vector-ref old 3))
                              (= ph (vector-ref old 4)))))
            (set! *core0-facts*
              (vector f w h pw ph (sdl-get-window-display-scale *sdl-window*)
                      (core0-read-frame-ns) (core0-read-display)
                      (sdl-get-error) (sdl-get-system-theme))))))))

  ;; The step's state as plain data, for inspect-core0 ((schevana kits
  ;; inspect)): the jobs and events waiting, and the last job that raised.
  (define (core0-step-state)
    (list (cons 'jobs (length (unbox *core0-jobs*)))
          (cons 'events (length (unbox *core0-inbox*)))
          (cons 'failed (and *core0-job-failed* (car *core0-job-failed*)))
          (cons 'refresh-said *present-refresh-said*))))
