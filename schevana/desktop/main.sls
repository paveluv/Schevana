;;; (schevana desktop main) — the desktop's start, which ./desktop launches.
;;; It reads the command line; then core1 (on a thread of its own when there
;;; is a window, since core0 keeps the process's first thread for the screen)
;;; loads the world and starts it (desktop-start!, (schevana desktop start)):
;;; the user's settings, the screen, the first windows, and the run until it
;;; quits.
;;;
;;;   ./desktop [--size WxH] [--fullscreen] [--headless] [--fork]
;;;                      [--hacker] [--eval EXPR]... [FOLDER]...
;;;   ./desktop --install-desktop | --uninstall-desktop
;;;
;;; Each FOLDER is added to the library search and loads with the world
;;; (./desktop demo loads the demos).

(library (schevana desktop main)
  (export desktop-defaults desktop-size desktop-usage desktop-options
          desktop-fork? desktop-later?
          desktop-main)
  (import (chezscheme)
          (only (schevana base) library-layer define-hook string-prefix?)
          (only (schevana core) auto-load! auto-load-layer core1-run
                core1-boot! world-app-file? world-value))

  (library-layer desktop)

  ;; What a command line may ask for, and what it gets when it doesn't ask.
  (define desktop-defaults
    '((mode . sdl)
      (size 1280 . 800)
      (full-screen? . #f)
      (fork? . #f)
      (desktop . #f)
      (hacker . #f)
      (evals)
      (auto-loads)))

  ;; Returns (1280 . 800) for "1280x800", or #f if s isn't a size.
  (define (desktop-size s)
    (let loop ([i 0])
      (cond [(= i (string-length s)) #f]
            [(char=? (string-ref s i) #\x)
             (let ([w (string->number (substring s 0 i))]
                   [h (string->number
                       (substring s (+ i 1) (string-length s)))])
               (and (fixnum? w) (fixnum? h) (> w 0) (> h 0) (cons w h)))]
            [else (loop (+ i 1))])))

  ;; Prints how to run the desktop on stderr, and exits.
  (define (desktop-usage)
    (fprintf (current-error-port)
             "usage: ./desktop [--size WxH] [--fullscreen] \
              [--headless] [--fork]\n                 \
              [--hacker] [--eval EXPR]... [FOLDER]...\n       \
              ./desktop --install-desktop | --uninstall-desktop\n")
    (exit 1))

  ;; Returns what args ask for, in the shape of desktop-defaults. A word
  ;; that isn't an option is a folder for the library search, which loads
  ;; with the world (auto-load!); an unknown option, or a file, prints the
  ;; usage and exits. Core1's boot is handed the result, which the world
  ;; reads as *schevana-options*. The hacker edition is asked for by
  ;; --hacker or SCHEVANA_HACKER, as src/launch.ss asks for it.
  (define (desktop-options args)
    (let loop ([args args]
               [opts (let ([v (getenv "SCHEVANA_HACKER")])
                       (if (and v (not (string=? v "")))
                           (cons '(hacker . #t) desktop-defaults)
                           desktop-defaults))])
      (define (next n key value)
        (loop (list-tail args n) (cons (cons key value) opts)))
      (define (arg? word) (equal? (car args) word))
      (define (value? word) (and (arg? word) (pair? (cdr args))))
      (cond
        [(null? args)
         (map (lambda (d) (assq (car d) opts)) desktop-defaults)]
        [(arg? "--headless") (next 1 'mode 'headless)]
        [(arg? "--fullscreen") (next 1 'full-screen? #t)]
        [(arg? "--fork") (next 1 'fork? #t)]
        [(arg? "--hacker") (next 1 'hacker #t)]
        [(arg? "--install-desktop") (next 1 'desktop 'install)]
        [(arg? "--uninstall-desktop") (next 1 'desktop 'uninstall)]
        [(and (value? "--size") (desktop-size (cadr args)))
         => (lambda (size) (next 2 'size size))]
        [(value? "--eval")
         (next 2 'evals
               (append (cdr (assq 'evals opts)) (list (cadr args))))]
        [(and (not (string-prefix? "-" (car args)))
              (not (and (file-exists? (car args))
                        (not (file-directory? (car args))))))
         (next 1 'auto-loads
               (append (cdr (assq 'auto-loads opts)) (list (car args))))]
        [else (desktop-usage)])))

  ;; A window needs two threads, core0's for the screen and core1 for the
  ;; world; --fork asks for both too, without a window. Installing the
  ;; desktop entry opens no window.
  (define (desktop-fork? opts)
    (and (not (cdr (assq 'desktop opts)))
         (or (eq? (cdr (assq 'mode opts)) 'sdl) (cdr (assq 'fork? opts)))))

  ;; Whether a world entry loads after the screen shows. The apps, the
  ;; heaviest part of the world, do: Schevana's and those of an added
  ;; folder, whether a library (by the layer it declares) or a file in an
  ;; apps folder. A kit or a look, from any folder, loads first. The desktop
  ;; opens its first apps itself (desktop-start!), and loads those first.
  (define (desktop-later? entry)
    (if (pair? entry)
        (eq? (auto-load-layer entry) 'apps)
        (world-app-file? entry)))

  ;; Starts the desktop from the command line's args. Installing its entry
  ;; opens no window.
  (define (desktop-main args)
    (let* ([options (desktop-options args)]
           [option (lambda (key) (cdr (assq key options)))]
           [size (option 'size)])
      (core1-run (if (option 'desktop) 'headless (option 'mode))
                 (car size) (cdr size) (option 'full-screen?)
                 (desktop-fork? options)
                 (lambda ()
                   (for-each auto-load! (option 'auto-loads))
                   (core1-boot! options desktop-later?)
                   ((world-value 'desktop-start!)))))))
