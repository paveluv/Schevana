;;; (schevana sources) — the world's files, loaded into "/" at boot and at a
;;; reload (src/core1/sources.ss). It exports what the pieces above it and the
;;; world use of it.

(library (schevana sources)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana reload)
          (schevana core loop) (schevana core processes) (schevana core0)
          (schevana boot))

  (library-layer core)

  (include-sources "src/core1/sources.ss")

  (define-exports sources-exports
    (export (world)
      load-user-init! source-path source-files *source-texts*
      keep-source-text! load-file! (settable app-load!) load-user-folders!
      reload!)))
