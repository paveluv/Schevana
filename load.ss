;;; load.ss — loads the whole Schevana world into the interaction environment.
;;; Everything is top-level on purpose: any definition can be redefined live
;;; from the REPL, and the running system picks it up immediately.

;; The script that loads this file sets *schevana-root* first.
(define *schevana-root*
  (if (top-level-bound? '*schevana-root*)
      (top-level-value '*schevana-root*)
      "."))

;; The core, in load order. Its last file loads the folders (kits, desktop,
;; styles, palettes, wallpapers, apps): see source-folders in src/system.ss.
(define *schevana-sources*
  '("src/ffi.ss" "src/base.ss" "src/shader.ss" "src/theme.ss" "src/gpu.ss"
    "src/font.ss" "src/gfx.ss"
    "src/proc.ss" "src/host.ss" "src/wm.ss" "src/system.ss"))

(for-each (lambda (f) (load (string-append *schevana-root* "/" f)))
          *schevana-sources*)
