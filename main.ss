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
;;; The boot, in three steps:
;;;
;;;   1. This thread loads core0, the host's own code (src/host/).
;;;   2. Core0 makes the world's environment, "/", and loads the tree into
;;;      it: the core, whose last file loads the folders (src/host/boot.ss,
;;;      src/system.ss).
;;;   3. world.ss, in "/", reads the user's settings, opens the first
;;;      windows and runs the world till it quits.
;;;
;;; With a window, core0 opens it first and keeps this thread for the
;;; screen, so steps 2 and 3 run on the world's own thread, core1. Headless,
;;; this thread does them all, unless --fork asks for the two threads with
;;; no window (for the tests). The tests load this file too, for steps 1
;;; and 2 alone, and go on in "/" (tests/core0.ss).
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

;; Core0, below the core: the C bindings and the basics, then the host's
;; own code (src/host/: SDL, what differs by platform, the GPU's device
;; side, the screen's reports, the trace, the window, the boot).
(define *schevana-core0-sources*
  '("src/ffi.ss" "src/base.ss" "src/host/sdl.ss" "src/host/platform.ss"
    "src/host/gpu.ss" "src/host/present.ss" "src/host/trace.ss"
    "src/host/window.ss" "src/host/boot.ss"))

;; "/recorder", sealed, made by core0 before "/": the basics, then the bytes
;; of frames and their writers (src/recorder/). Like core0's, these change
;; with a restart.
(define *schevana-recorder-sources*
  '("src/base.ss" "src/recorder/bytes.ss"))

;; The world's core, in load order, in "/": the C bindings and the basics,
;; a copy of its own, then the core above core0. Its last file loads the
;; folders (kits, services, desktop, styles, palettes, wallpapers, apps):
;; see source-folders in src/system.ss. (reload!) loads these again, read
;; from this file; core0's stay as they are.
(define *schevana-sources*
  '("src/ffi.ss" "src/base.ss" "src/platform.ss" "src/shader.ss"
    "src/theme.ss" "src/gpu.ss"
    "src/font.ss" "src/gfx.ss" "src/proc.ss" "src/host.ss" "src/wm.ss"
    "src/system.ss"))

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

;; 1. Core0.
(for-each (lambda (f) (load (string-append *schevana-root* "/" f)))
          *schevana-core0-sources*)

;; 2 and 3. With two threads, core0 never comes back: it's the host from
;; here. A test's boot stops at the tree.
(cond
  [(not main-script?)
   (host-boot! *schevana-root* *schevana-recorder-sources* *schevana-sources*
               *schevana-options* #f)]
  [(main-fork? *schevana-options*)
   (host-fork! *schevana-root* *schevana-recorder-sources* *schevana-sources*
               *schevana-options* "world.ss")]
  [else
   (host-boot! *schevana-root* *schevana-recorder-sources* *schevana-sources*
               *schevana-options* "world.ss")])
