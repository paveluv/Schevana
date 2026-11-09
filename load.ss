;;; load.ss — loads core0 into the loading script's environment; core0 then
;;; makes the world's, "/", and loads the world there (src/host/boot.ss).
;;; Everything is top-level on purpose: any definition can be redefined live
;;; from the REPL, and the running system picks it up immediately.

;; The script that loads this file sets *schevana-root* first.
(define *schevana-root*
  (if (top-level-bound? '*schevana-root*)
      (top-level-value '*schevana-root*)
      "."))

;; Core0, below the core: the C bindings and the basics, then the host's
;; own code (src/host/: SDL, the GPU's device side, the window, the boot).
(define *schevana-core0-sources*
  '("src/ffi.ss" "src/base.ss" "src/host/sdl.ss" "src/host/gpu.ss"
    "src/host/window.ss" "src/host/boot.ss"))

;; The world's core, in load order, in "/": the C bindings and the basics,
;; a copy of its own, then the core above core0. Its last file loads the
;; folders (kits, desktop, styles, palettes, wallpapers, apps): see
;; source-folders in src/system.ss. (reload!) loads these again, read from
;; this file; core0's stay as they are.
(define *schevana-sources*
  '("src/ffi.ss" "src/base.ss" "src/shader.ss" "src/theme.ss" "src/gpu.ss"
    "src/font.ss" "src/gfx.ss" "src/proc.ss" "src/host.ss" "src/wm.ss"
    "src/system.ss"))

(for-each (lambda (f) (load (string-append *schevana-root* "/" f)))
          *schevana-core0-sources*)
(host-boot! *schevana-root* *schevana-sources*)
