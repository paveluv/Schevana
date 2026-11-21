;;; (schevana sdl) — all of SDL3's bindings, from the three libraries that
;;; make them: (schevana sdl system), SDL itself and what any thread may
;;; call; (schevana sdl window), the window and its events; (schevana sdl
;;; gpu), the GPU. Only core0 imports it.

(library (schevana sdl)
  (export)
  (import (chezscheme))

  ;; each of the three's exports, as this library's own
  (export (import (schevana sdl system) (schevana sdl window)
                  (schevana sdl gpu))))
