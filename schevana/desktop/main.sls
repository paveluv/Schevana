;;; (schevana desktop main) — the desktop's start, which ./schevana-desktop
;;; launches: it reads the command line, then core1 (on a thread of its own with
;;; a window, core0 keeping the process's first for the screen) loads the world
;;; and starts it (desktop-start!, (schevana desktop start)): the user's
;;; settings, the screen, the first windows, the run till it quits.
;;;
;;;   ./schevana-desktop [--size WxH] [--fullscreen] [--headless] [--fork]
;;;                      [--hacker] [--demo] [--eval EXPR]...
;;;   ./schevana-desktop --install-desktop | --uninstall-desktop

(library (schevana desktop main)
  (export desktop-defaults desktop-size desktop-usage desktop-options
          desktop-fork? desktop-demos desktop-demos-load! desktop-main)
  (import (chezscheme)
          (only (schevana base) library-layer define-hook string-suffix?)
          (only (schevana core) core1-run core1-boot! world-value
                *schevana-root*))

  (library-layer desktop)

  ;; What a command line may ask, and what it gets when it doesn't.
  (define desktop-defaults
    '((mode . sdl)
      (size 1280 . 800)
      (full-screen? . #f)
      (fork? . #f)
      (desktop . #f)
      (hacker . #f)
      (demo . #f)
      (evals)))

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

  ;; A hook, so that a test hears the usage without the exit.
  (define-hook (desktop-usage)
    (fprintf (current-error-port)
             "usage: schevana-desktop [--size WxH] [--fullscreen] \
              [--headless] [--fork]\n                        \
              [--hacker] [--demo] [--eval EXPR]...\n       \
              schevana-desktop --install-desktop | --uninstall-desktop\n")
    (exit 1))

  ;; What args ask, as desktop-defaults has it: a word it doesn't know
  ;; prints the usage and stops. Core1's boot is handed it, which the world
  ;; reads as *schevana-options*. The hacker edition is asked by --hacker
  ;; or SCHEVANA_HACKER, as src/launch.ss asks it.
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
        [(arg? "--demo") (next 1 'demo #t)]
        [(arg? "--install-desktop") (next 1 'desktop 'install)]
        [(arg? "--uninstall-desktop") (next 1 'desktop 'uninstall)]
        [(and (value? "--size") (desktop-size (cadr args)))
         => (lambda (size) (next 2 'size size))]
        [(value? "--eval")
         (next 2 'evals
               (append (cdr (assq 'evals opts)) (list (cadr args))))]
        [else (desktop-usage)])))

  ;; A window wants the two threads, core0's for the screen and core1 for
  ;; the world; so does --fork, with none. Installing the desktop entry
  ;; opens no window.
  (define (desktop-fork? opts)
    (and (not (cdr (assq 'desktop opts)))
         (or (eq? (cdr (assq 'mode opts)) 'sdl) (cdr (assq 'fork? opts)))))

  ;; The demos' libraries, (schevana-demo name), by their files in
  ;; schevana-demo/, in file-name order.
  (define (desktop-demos)
    (let ([dir (string-append *schevana-root* "/schevana-demo")])
      (if (file-directory? dir)
          (map (lambda (f)
                 (list 'schevana-demo
                       (string->symbol (path-root f))))
               (sort string<?
                     (filter (lambda (f) (string-suffix? ".sls" f))
                             (directory-list dir))))
          '())))

  ;; Each demo's library, invoked: an app it defines registers itself
  ;; (define-app), and shows among the apps.
  (define (desktop-demos-load!)
    (for-each invoke-library (desktop-demos)))

  ;; The desktop, from the command line's args. Installing its entry
  ;; opens no window.
  (define (desktop-main args)
    (let* ([options (desktop-options args)]
           [option (lambda (key) (cdr (assq key options)))]
           [size (option 'size)])
      (core1-run (if (option 'desktop) 'headless (option 'mode))
                 (car size) (cdr size) (option 'full-screen?)
                 (desktop-fork? options)
                 (lambda ()
                   (core1-boot! options)
                   (when (option 'demo) (desktop-demos-load!))
                   ((world-value 'desktop-start!)))))))
