;;; main.ss — boot Schevana.
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

(define *schevana-root*
  (let ([dir (path-parent (car (command-line)))])
    (if (string=? dir "") "." dir)))

;; With a window, core0 runs the screen on this thread and forks the
;; world's, main, which loads the tree and world.ss into "/"
;; (src/host/boot.ss): load.ss never returns. Headless, or only installing
;; the desktop entry, this thread plays both, unless --fork asks for the
;; threads with no window (for the tests).
(define *schevana-fork*
  (let ([args (command-line-arguments)])
    (and (not (member "--install-desktop" args))
         (not (member "--uninstall-desktop" args))
         (or (not (member "--headless" args)) (member "--fork" args))
         #t)))

;; How core0 starts, (mode w h full-screen?): the size WxH.
(define *schevana-window*
  (let* ([args (command-line-arguments)]
         [size (let loop ([args args])
                 (cond [(or (null? args) (null? (cdr args))) "1280x800"]
                       [(string=? (car args) "--size") (cadr args)]
                       [else (loop (cdr args))]))]
         [x (let loop ([i 0])
              (if (char=? (string-ref size i) #\x) i (loop (+ i 1))))])
    (list (if (member "--headless" args) 'headless 'sdl)
          (string->number (substring size 0 x))
          (string->number (substring size (+ x 1) (string-length size)))
          (and (member "--fullscreen" args) #t))))

(load (string-append *schevana-root* "/load.ss"))
;; Core0 made "/" and loaded the world there: the rest is the world's.
(host-enter-world!)
(load (string-append *schevana-root* "/world.ss"))
