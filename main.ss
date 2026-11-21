;;; main.ss — boots Schevana.
;;;
;;;   scheme --script main.ss [--size 1280x800] [--fullscreen] [--headless]
;;;                           [--fork] [--eval EXPR] ...
;;;   scheme --script main.ss --install-desktop     ; the app icon for GNOME
;;;                                                   and co.
;;;   scheme --script main.ss --uninstall-desktop
;;;
;;; --eval expressions run after boot, e.g.
;;;   --eval '(after 2000 (lambda () (png-write-screen-then "s.png" \
;;;                                    (lambda (p) (quit!)))))'
;;;
;;; The boot is a chain, each link making the next one's environment and
;;; loading it:
;;;
;;;   1. This file boots core0, the code below the core, sealed in its
;;;      libraries (lib/schevana/core0/), which this thread's environment
;;;      imports.
;;;   2. Core0 makes "/core1", loads the core there, which imports what
;;;      core0 and the recorder give it ((schevana core0), (schevana
;;;      recorder)), and boots core1 (src/core0/boot.ss).
;;;   3. Core1 makes the world's environment, "/", and loads the world into
;;;      it: the basics and the folders (src/core1/boot.ss).
;;;   4. world.ss, in "/", reads the user's settings, opens the first
;;;      windows and runs the world till it quits.
;;;
;;; With a window, core0 opens it first and keeps this thread for the
;;; screen, so the core loads, and steps 3 and 4 run, on the world's own
;;; thread, core1. Headless, this thread does them all, unless --fork asks
;;; for the two threads with no window (for the tests). The tests load this
;;; file too, for steps 1 to 3 alone, and go on in "/" (tests/reach.ss).
;;;
;;; Everything is top-level on purpose: any definition can be redefined live
;;; from the REPL, and the running system picks it up immediately.

;; Run as the script, this file boots Schevana; a test loads it for the
;; tree, having set *schevana-root* first.
(define main-script?
  (equal? (path-last (car (command-line))) "main.ss"))

;;; ------------------------------------------------------------------ the tree

;; Where the tree is: this file's folder, which a test found too.
(define *schevana-root*
  (if main-script?
      (let ([dir (path-parent (car (command-line)))])
        (if (string=? dir "") "." dir))
      (top-level-value '*schevana-root*)))

;; The pieces of the core that are R6RS libraries (lib/schevana/): the
;; basics, where the tree is, how C is bound, SDL's bindings (SDL itself,
;; the window's, the GPU's, and all three as one), the shader compiler,
;; sockets, FreeType's bindings and fontconfig's; core0's own, and its
;; facades, what it gives core1 and what it gives the recorder; the
;; recorder and its facade; and how a library is reloaded in place. Each
;; declares its layer (library-layer, in (schevana base)).
(define *schevana-libraries*
  '("lib/schevana/base.sls" "lib/schevana/tree.sls" "lib/schevana/ffi.sls"
    "lib/schevana/sdl/system.sls" "lib/schevana/sdl/window.sls"
    "lib/schevana/sdl/gpu.sls" "lib/schevana/sdl.sls" "lib/schevana/shader.sls"
    "lib/schevana/socket.sls" "lib/schevana/freetype.sls"
    "lib/schevana/fontconfig.sls" "lib/schevana/core0/mail.sls"
    "lib/schevana/core0/trace.sls" "lib/schevana/core0/renderer.sls"
    "lib/schevana/core0/present.sls" "lib/schevana/core0/platform.sls"
    "lib/schevana/core0/trace-file.sls" "lib/schevana/core0/gpu.sls"
    "lib/schevana/core0/window.sls" "lib/schevana/core0/for-recorder.sls"
    "lib/schevana/core0.sls" "lib/schevana/recorder/bytes.sls"
    "lib/schevana/recorder.sls" "lib/schevana/reload.sls"
    "lib/schevana/core/platform.sls" "lib/schevana/core/theme-table.sls"
    "lib/schevana/core/processes.sls" "lib/schevana/core/gpu.sls"
    "lib/schevana/core/fonts.sls" "lib/schevana/core/draw.sls"
    "lib/schevana/core/pacer.sls" "lib/schevana/core/screen.sls"
    "lib/schevana/core/loop.sls" "lib/schevana/core/theme.sls"
    "lib/schevana/core/windows.sls"))

;; Core0, below the core. Its code is libraries (lib/schevana/core0/):
;; what its threads hand each other, the trace and its file, the
;; renderer's record, the frames' reports, what differs by platform, the
;; GPU's device side, the window. Left in src/core0/ is the boot's making
;; of "/core1".
(define *schevana-core0-sources*
  '("src/base.ss" "src/core0/boot.ss"))

;; The core, in load order, in "/core1": the basics, a copy of its own,
;; then core1's code (src/core1/), its boot first and what it exports last.
;; The world it makes loads the folders (kits, services, desktop, styles,
;; palettes, wallpapers, apps): see source-folders in src/core1/sources.ss.
;; (reload!) loads these again, read from this file; core0's stay as they
;; are.
(define *schevana-core1-sources*
  '("src/base.ss" "src/core1/boot.ss" "src/core1/sources.ss"
    "src/core1/export.ss"))

;;; ---------------------------------------------------------- the command line

;; What a command line may ask, and what it gets when it doesn't.
(define main-defaults
  '((mode . sdl)
    (size 1280 . 800)
    (full-screen? . #f)
    (fork? . #f)
    (desktop . #f)
    (evals)))

;; "1280x800" => (1280 . 800); #f if it isn't a size.
(define (main-size s)
  (let loop ([i 0])
    (cond [(= i (string-length s)) #f]
          [(char=? (string-ref s i) #\x)
           (let ([w (string->number (substring s 0 i))]
                 [h (string->number (substring s (+ i 1) (string-length s)))])
             (and (fixnum? w) (fixnum? h) (> w 0) (> h 0) (cons w h)))]
          [else (loop (+ i 1))])))

(define (main-usage)
  (fprintf (current-error-port)
           "usage: schevana [--size WxH] [--fullscreen] [--headless] \
            [--fork] [--eval EXPR]...\n       \
            schevana --install-desktop | --uninstall-desktop\n")
  (exit 1))

;; What args ask, as main-defaults has it, read before anything loads: a
;; word it doesn't know prints the usage and stops. The world reads it too,
;; as *schevana-options* (world.ss).
(define (main-options args)
  (let loop ([args args] [opts main-defaults])
    (define (next n key value)
      (loop (list-tail args n) (cons (cons key value) opts)))
    (define (arg? word) (equal? (car args) word))
    (define (value? word) (and (arg? word) (pair? (cdr args))))
    (cond
      [(null? args) (map (lambda (d) (assq (car d) opts)) main-defaults)]
      [(arg? "--headless") (next 1 'mode 'headless)]
      [(arg? "--fullscreen") (next 1 'full-screen? #t)]
      [(arg? "--fork") (next 1 'fork? #t)]
      [(arg? "--install-desktop") (next 1 'desktop 'install)]
      [(arg? "--uninstall-desktop") (next 1 'desktop 'uninstall)]
      [(and (value? "--size") (main-size (cadr args)))
       => (lambda (size) (next 2 'size size))]
      [(value? "--eval")
       (next 2 'evals (append (cdr (assq 'evals opts)) (list (cadr args))))]
      [else (main-usage)])))

;; A test's tree is headless, on its own thread.
(define *schevana-options*
  (main-options (if main-script? (command-line-arguments) '("--headless"))))

;; A window wants the two threads, core0's for the screen and core1 for
;; the world; so does --fork, with none. Installing the desktop entry opens no
;; window.
(define (main-fork? opts)
  (and (not (cdr (assq 'desktop opts)))
       (or (eq? (cdr (assq 'mode opts)) 'sdl) (cdr (assq 'fork? opts)))))

;;; ------------------------------------------------------------------ the boot

;; 1. Core0. Its libraries first: (import (schevana ...)) finds them in
;; the tree's lib.
(library-directories
 (let ([lib (string-append *schevana-root* "/lib")])
   (cons (cons lib lib) (library-directories))))
(import (schevana ffi) (schevana sdl) (schevana shader)
        (schevana core0 mail) (schevana core0 trace) (schevana core0 renderer)
        (schevana core0 present) (schevana core0 platform)
        (schevana core0 trace-file) (schevana core0 gpu)
        (schevana core0 window) (schevana reload))
(for-each (lambda (f) (load (string-append *schevana-root* "/" f)))
          *schevana-core0-sources*)

;; 2 to 4. With two threads, core0 never comes back: its loop runs from
;; here. A test's boot stops at the world, loaded.
(cond
  [(not main-script?)
   (core0-boot! *schevana-root* *schevana-core1-sources* *schevana-options*
                #f)]
  [(main-fork? *schevana-options*)
   (core0-fork! *schevana-root* *schevana-core1-sources* *schevana-options*
                "world.ss")]
  [else
   (core0-boot! *schevana-root* *schevana-core1-sources* *schevana-options*
                "world.ss")])
