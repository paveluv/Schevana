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
;;;      libraries (schevana/core0/), which this thread's environment
;;;      imports.
;;;   2. Core0 boots core1 (core1-boot!, (schevana core sources)): the core
;;;      is sealed in its libraries too (schevana/core/), and has of
;;;      core0's and the recorder's only their facades, (schevana core0)
;;;      and (schevana recorder).
;;;   3. Core1 makes the world's environment, "/", which imports what the
;;;      core gives it, (schevana core), and loads the world into it: the
;;;      basics and the folders.
;;;   4. world.ss, in "/", reads the user's settings, opens the first
;;;      windows and runs the world till it quits.
;;;
;;; With a window, core0 opens it first and keeps this thread for the
;;; screen, so the core loads, and steps 2 to 4 run, on the world's own
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

;; Schevana's R6RS libraries below the world (schevana/): the
;; basics, where the tree is, how C is bound, SDL's bindings (SDL itself,
;; the window's, the GPU's, and all three as one), the shader compiler,
;; sockets, FreeType's bindings and fontconfig's; core0's own, and its
;; facades, what it gives core1 and what it gives the recorder; the
;; recorder and its facade; how a library is reloaded in place; the
;; core's own, and its facade, what it gives the world. Each declares its
;; layer (library-layer, in (schevana base)).
(define *schevana-libraries*
  '("schevana/base.sls" "schevana/tree.sls" "schevana/ffi.sls"
    "schevana/sdl/system.sls" "schevana/sdl/window.sls"
    "schevana/sdl/gpu.sls" "schevana/sdl.sls" "schevana/shader.sls"
    "schevana/socket.sls" "schevana/freetype.sls"
    "schevana/fontconfig.sls" "schevana/core0/mail.sls"
    "schevana/core0/trace.sls" "schevana/core0/renderer.sls"
    "schevana/core0/present.sls" "schevana/core0/platform.sls"
    "schevana/core0/trace-file.sls" "schevana/core0/gpu.sls"
    "schevana/core0/window.sls" "schevana/core0/for-recorder.sls"
    "schevana/core0.sls" "schevana/recorder/bytes.sls"
    "schevana/recorder.sls" "schevana/reload.sls"
    "schevana/core/platform.sls" "schevana/core/theme-table.sls"
    "schevana/core/processes.sls" "schevana/core/gpu.sls"
    "schevana/core/fonts.sls" "schevana/core/draw.sls"
    "schevana/core/pacer.sls" "schevana/core/screen.sls"
    "schevana/core/loop.sls" "schevana/core/theme.sls"
    "schevana/core/windows.sls" "schevana/core/sources.sls"
    "schevana/core.sls"))

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
;; word it doesn't know prints the usage and stops. Core1's boot is handed
;; it, which the world reads as *schevana-options* (world.ss).
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
(define *main-options*
  (main-options (if main-script? (command-line-arguments) '("--headless"))))

;; A window wants the two threads, core0's for the screen and core1 for
;; the world; so does --fork, with none. Installing the desktop entry opens no
;; window.
(define (main-fork? opts)
  (and (not (cdr (assq 'desktop opts)))
       (or (eq? (cdr (assq 'mode opts)) 'sdl) (cdr (assq 'fork? opts)))))

;;; ------------------------------------------------------------------ the boot

;; 1. Core0. Its libraries first: (import (schevana ...)) finds them in
;; the tree's lib. This thread's environment has the basics too, a copy
;; of its own.
(library-directories
 (cons (cons *schevana-root* *schevana-root*) (library-directories)))
(import (schevana ffi) (schevana sdl) (schevana shader)
        (schevana core0 mail) (schevana core0 trace) (schevana core0 renderer)
        (schevana core0 present) (schevana core0 platform)
        (schevana core0 trace-file) (schevana core0 gpu)
        (schevana core0 window) (schevana reload))
(load (string-append *schevana-root* "/src/base.ss"))

;; 2 and 3. Core1's boot, named rather than imported: the core loads as
;; it is first named, so with two threads it loads on core1's while the
;; boot screen shows.
(define (main-core1-boot! script)
  ((eval 'core1-boot! (environment '(schevana core sources)))
   *main-options* script))

;; With two threads, core0 never comes back: its loop runs from here. A
;; test's boot stops at the world, loaded.
(cond
  [(not main-script?) (main-core1-boot! #f)]
  [(main-fork? *main-options*)
   (let ([option (lambda (key) (cdr (assq key *main-options*)))])
     (core0-run! (option 'mode) (car (option 'size)) (cdr (option 'size))
                 (option 'full-screen?)
                 (lambda () (main-core1-boot! "world.ss"))))]
  [else (main-core1-boot! "world.ss")])
