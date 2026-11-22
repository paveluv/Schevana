;;; (schevana sdl system) — SDL3 itself, loaded, and its two calls any
;;; thread may make: the clock, and how many threads the machine runs at
;;; once. The window's bindings and the GPU's are libraries of their own,
;;; which load after this one.

(library (schevana sdl system)
  (export
    sdl-library sdl-get-ticks-ns sdl-get-num-logical-cpu-cores)
  (import (chezscheme) (only (schevana base) library-layer)
          (schevana ffi))

  (library-layer foundation)

  ;; SDL3 gives a window, input events, a clipboard and the GPU.
  (define sdl-library
    (load-first-library
     '("libSDL3.so.0" "libSDL3.so" "libSDL3.0.dylib" "libSDL3.dylib"
       "SDL3.dll")))

  ;; SDL's two calls any thread may make: the clock, and how many threads
  ;; the machine runs at once.
  (define-foreign sdl-get-ticks-ns "SDL_GetTicksNS" () unsigned-64)
  (define-foreign sdl-get-num-logical-cpu-cores "SDL_GetNumLogicalCPUCores" ()
    int))
