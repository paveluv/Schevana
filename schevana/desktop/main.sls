;;; (schevana desktop main) — the desktop's start, which ./schevana-desktop
;;; launches: it reads the command line, then core1 (on a thread of its own with
;;; a window, core0 keeping the process's first for the screen) loads the world
;;; and starts it (desktop-start!, (schevana desktop start)): the user's
;;; settings, the screen, the first windows, the run till it quits.
;;;
;;;   ./schevana-desktop [--size WxH] [--fullscreen] [--headless] [--fork]
;;;                      [--hacker] [--eval EXPR]... [FOLDER]...
;;;   ./schevana-desktop --install-desktop | --uninstall-desktop
;;;
;;; Each FOLDER joins the library search and loads with the world
;;; (./schevana-desktop schevana-demo: the demos).

(library (schevana desktop main)
  (export desktop-defaults desktop-size desktop-usage desktop-options
          desktop-fork? desktop-later?
          desktop-main)
  (import (chezscheme)
          (only (schevana base) library-layer define-hook string-prefix?)
          (only (schevana core) auto-load! auto-load-layer core1-run
                core1-boot! world-app-file? world-value))

  (library-layer desktop)

  ;; What a command line may ask, and what it gets when it doesn't.
  (define desktop-defaults
    '((mode . sdl)
      (size 1280 . 800)
      (full-screen? . #f)
      (fork? . #f)
      (desktop . #f)
      (hacker . #f)
      (evals)
      (auto-loads)))

  ;; "1280x800" => (1280 . 800); #f if it isn't a size.
  (define (desktop-size s)
    (let loop ([i 0])
      (cond [(= i (string-length s)) #f]
            [(char=? (string-ref s i) #\x)
             (let ([w (string->number (substring s 0 i))]
                   [h (string->number
                       (substring s (+ i 1) (string-length s)))])
               (and (fixnum? w) (fixnum? h) (> w 0) (> h 0) (cons w h)))]
            [else (loop (+ i 1))])))

  ;; How to run it, on stderr; and the run stops.
  (define (desktop-usage)
    (fprintf (current-error-port)
             "usage: schevana-desktop [--size WxH] [--fullscreen] \
              [--headless] [--fork]\n                        \
              [--hacker] [--eval EXPR]... [FOLDER]...\n       \
              schevana-desktop --install-desktop | --uninstall-desktop\n")
    (exit 1))

  ;; What args ask, as desktop-defaults has it: a word that isn't an
  ;; option is a folder for the library search that loads with the world
  ;; (auto-load!); an option it doesn't know, or a file, prints the usage
  ;; and stops. Core1's boot is
  ;; handed it, which the world reads as *schevana-options*. The hacker
  ;; edition is asked by --hacker or SCHEVANA_HACKER, as src/launch.ss asks
  ;; it.
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

  ;; A window wants the two threads, core0's for the screen and core1 for
  ;; the world; so does --fork, with none. Installing the desktop entry
  ;; opens no window.
  (define (desktop-fork? opts)
    (and (not (cdr (assq 'desktop opts)))
         (or (eq? (cdr (assq 'mode opts)) 'sdl) (cdr (assq 'fork? opts)))))

  ;; The desktop, from the command line's args. Installing its entry
  ;; opens no window.
  ;; What of the world loads after the screen shows: the apps, the heaviest
  ;; of it, Schevana's and those of a folder added, a library by the layer
  ;; it declares, a file in an apps folder; a kit or a look, of any
  ;; folder, loads first. The desktop opens its first apps itself
  ;; (desktop-start!), loading them first.
  (define (desktop-later? entry)
    (if (pair? entry)
        (eq? (auto-load-layer entry) 'apps)
        (world-app-file? entry)))

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
