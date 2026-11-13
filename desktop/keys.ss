;;; keys.ss — the desktop's default key bindings, installed once a session
;;; when this file first loads: a reload does not undo your unbind-key!.

(define default-global-keys
  `(((f1) . ,(lambda () (toggle-launcher!)))
    ((ctrl tab) . ,(lambda () (cycle-windows!)))
    ((ctrl shift #\w) . ,(lambda () (close-focused-window!)))
    ((ctrl shift #\m) . ,(lambda () (when *focus* (toggle-maximize! *focus*))))
    ((ctrl shift #\n) . ,(lambda () (when *focus* (minimize-window! *focus*))))
    ((ctrl shift #\t) . ,(lambda () (tile-windows!)))
    ((ctrl shift #\r) . ,(lambda () (app-launch! 'repl)))
    ((f11) . ,(lambda () (toggle-fullscreen!)))
    ((f12) . ,(lambda ()
                (png-write-screen-then
                 (next-screenshot-path)
                 (lambda (path) (notify (format "Saved ~a" path))))))))

(define (install-default-keys!)
  (for-each (lambda (b)
              (unless (assoc (car b) *global-keys*)
                (bind-key! (car b) (cdr b))))
            default-global-keys))

(define (next-screenshot-path)
  (let loop ([i 1])
    (let ([p (format "~a/schevana-~a.png" (or (getenv "HOME") ".") i)])
      (if (file-exists? p) (loop (+ i 1)) p))))

;; A world that already has bindings (one reloaded from before this file,
;; which installed them at boot) has its keys.
(defvar *default-keys-installed?* (pair? *global-keys*))
(unless *default-keys-installed?*
  (install-default-keys!)
  (set! *default-keys-installed?* #t))
