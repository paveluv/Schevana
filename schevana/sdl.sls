;;; (schevana sdl) — all of SDL3's bindings, from the three libraries that
;;; make them: (schevana sdl system), for SDL itself and the calls any
;;; thread may make; (schevana sdl window), for the window and its events;
;;; and (schevana sdl gpu), for the GPU. Only core0 imports it.

(library (schevana sdl)
  (export)
  (import (chezscheme) (only (schevana base) library-layer))

  (library-layer foundation)

  ;; the three libraries' exports, as this library's own
  (export (import (schevana sdl system) (schevana sdl window)
                  (schevana sdl gpu))))
