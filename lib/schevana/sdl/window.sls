;;; (schevana sdl window) — SDL3's bindings for the window, its events,
;;; the display and the clipboard, as SDL names them: what a test stands
;;; in for when it runs core0 with no window (tests/units/sdl.ss), so each
;;; call is a hook. Only core0 imports it, the one thread that may call
;;; them.

(library (schevana sdl window)
  (export
    ;; SDL's constants
    SDL_INIT_VIDEO SDL_WINDOW_FULLSCREEN SDL_WINDOW_HIDDEN SDL_WINDOW_RESIZABLE
    SDL_WINDOW_HIGH_PIXEL_DENSITY SDL_WINDOWPOS_CENTERED
    SDL_PIXELFORMAT_ARGB8888 SDL_EVENT_QUIT SDL_EVENT_WINDOW_EXPOSED
    SDL_EVENT_WINDOW_RESIZED SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED
    SDL_EVENT_WINDOW_MOUSE_LEAVE SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED
    SDL_EVENT_KEY_DOWN SDL_EVENT_TEXT_INPUT SDL_EVENT_MOUSE_MOTION
    SDL_EVENT_MOUSE_BUTTON_DOWN SDL_EVENT_MOUSE_BUTTON_UP SDL_EVENT_MOUSE_WHEEL
    ;; and its calls
    sdl-init sdl-quit sdl-get-error sdl-set-hint sdl-create-window
    sdl-destroy-window sdl-set-window-minimum-size sdl-set-window-size
    sdl-set-window-position sdl-show-window sdl-get-window-size
    sdl-get-window-display-scale sdl-get-window-size-in-pixels
    sdl-get-display-for-window sdl-get-current-display-mode sdl-poll-event
    sdl-start-text-input sdl-get-clipboard-text sdl-set-clipboard-text sdl-free
    sdl-create-system-cursor sdl-set-cursor sdl-set-window-fullscreen
    sdl-get-window-flags sdl-create-surface-from sdl-destroy-surface
    sdl-set-window-icon sdl-memset sdl-get-window-properties
    sdl-get-pointer-property sdl-get-number-property sdl-get-string-property
    sdl-get-version sdl-get-current-video-driver)
  (import (chezscheme)
          (schevana base)
          (schevana ffi)
          (schevana sdl system))

  ;; SDL3, loaded before a binding to it is made.
  (at-load sdl-library)

  ;; A call bound here is a hook holding the binding: the test sets its
  ;; stand-in there, and core0's libraries call whatever it holds.
  (define-syntax define-sdl-hook
    (syntax-rules ()
      [(_ name . spec)
       (begin (define-foreign bound . spec) (define-hook name bound))]))
  (define-syntax define-sdl-hook/collect-safe
    (syntax-rules ()
      [(_ name . spec)
       (begin (define-foreign/collect-safe bound . spec)
              (define-hook name bound))]))

  (define SDL_INIT_VIDEO #x20)
  (define SDL_WINDOW_FULLSCREEN #x1)
  (define SDL_WINDOW_HIDDEN #x8)
  (define SDL_WINDOW_RESIZABLE #x20)
  (define SDL_WINDOW_HIGH_PIXEL_DENSITY #x2000)
  (define SDL_WINDOWPOS_CENTERED #x2FFF0000)
  (define SDL_PIXELFORMAT_ARGB8888 #x16362004)

  (define SDL_EVENT_QUIT #x100)
  (define SDL_EVENT_WINDOW_EXPOSED #x204)
  (define SDL_EVENT_WINDOW_RESIZED #x206)
  (define SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED #x207)
  (define SDL_EVENT_WINDOW_MOUSE_LEAVE #x20D)
  (define SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED #x214)
  (define SDL_EVENT_KEY_DOWN #x300)
  (define SDL_EVENT_TEXT_INPUT #x303)
  (define SDL_EVENT_MOUSE_MOTION #x400)
  (define SDL_EVENT_MOUSE_BUTTON_DOWN #x401)
  (define SDL_EVENT_MOUSE_BUTTON_UP #x402)
  (define SDL_EVENT_MOUSE_WHEEL #x403)

  (define-sdl-hook sdl-init "SDL_Init" (unsigned-32) bool)
  (define-sdl-hook sdl-quit "SDL_Quit" () void)
  (define-sdl-hook sdl-get-error "SDL_GetError" () string)
  (define-sdl-hook sdl-set-hint "SDL_SetHint" (string string) bool)
  (define-sdl-hook sdl-create-window "SDL_CreateWindow"
    (string int int unsigned-64) uptr)
  ;; Collect-safe, as is what may size, show or let go of the window's Metal
  ;; layer once it has run: Core Animation may hold the layer's lock running
  ;; a presented handler of core0's, which may wait for a collection
  ;; ((schevana core0 platform)).
  (define-sdl-hook/collect-safe sdl-destroy-window "SDL_DestroyWindow" (uptr)
    void)
  (define-sdl-hook/collect-safe sdl-set-window-minimum-size
    "SDL_SetWindowMinimumSize" (uptr int int) bool)
  (define-sdl-hook/collect-safe sdl-set-window-size "SDL_SetWindowSize"
    (uptr int int) bool)
  (define-sdl-hook sdl-set-window-position "SDL_SetWindowPosition"
    (uptr int int) bool)
  (define-sdl-hook sdl-show-window "SDL_ShowWindow" (uptr) bool)
  (define-sdl-hook sdl-get-window-size "SDL_GetWindowSize"
    (uptr uptr uptr) bool)
  (define-sdl-hook sdl-get-window-display-scale "SDL_GetWindowDisplayScale"
    (uptr) float)
  (define-sdl-hook sdl-get-window-size-in-pixels "SDL_GetWindowSizeInPixels"
    (uptr uptr uptr) bool)
  (define-sdl-hook sdl-get-display-for-window "SDL_GetDisplayForWindow"
    (uptr) unsigned-32)
  (define-sdl-hook sdl-get-current-display-mode "SDL_GetCurrentDisplayMode"
    (unsigned-32) uptr)
  (define-sdl-hook/collect-safe sdl-poll-event "SDL_PollEvent" (uptr) bool)
  (define-sdl-hook sdl-start-text-input "SDL_StartTextInput" (uptr) bool)
  (define-sdl-hook sdl-get-clipboard-text "SDL_GetClipboardText" () uptr)
  (define-sdl-hook sdl-set-clipboard-text "SDL_SetClipboardText" (string) bool)
  (define-sdl-hook sdl-free "SDL_free" (uptr) void)
  (define-sdl-hook sdl-create-system-cursor "SDL_CreateSystemCursor" (int) uptr)
  (define-sdl-hook sdl-set-cursor "SDL_SetCursor" (uptr) bool)
  (define-sdl-hook/collect-safe sdl-set-window-fullscreen
    "SDL_SetWindowFullscreen" (uptr bool) bool)
  (define-sdl-hook sdl-get-window-flags "SDL_GetWindowFlags" (uptr) unsigned-64)
  (define-sdl-hook sdl-create-surface-from "SDL_CreateSurfaceFrom"
    (int int unsigned-32 uptr int) uptr)
  (define-sdl-hook sdl-destroy-surface "SDL_DestroySurface" (uptr) void)
  (define-sdl-hook sdl-set-window-icon "SDL_SetWindowIcon" (uptr uptr) bool)
  (define-sdl-hook sdl-memset "SDL_memset" (uptr int size_t) uptr)

  ;; What the window and the platform say of themselves.
  (define-sdl-hook sdl-get-window-properties "SDL_GetWindowProperties" (uptr)
    unsigned-32)
  (define-sdl-hook sdl-get-pointer-property "SDL_GetPointerProperty"
    (unsigned-32 string uptr) uptr)
  (define-sdl-hook sdl-get-number-property "SDL_GetNumberProperty"
    (unsigned-32 string integer-64) integer-64)
  (define-sdl-hook sdl-get-string-property "SDL_GetStringProperty"
    (unsigned-32 string string) string)
  (define-sdl-hook sdl-get-version "SDL_GetVersion" () int)
  (define-sdl-hook sdl-get-current-video-driver "SDL_GetCurrentVideoDriver" ()
    string))
