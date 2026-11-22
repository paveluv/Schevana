;;; (schevana desktop screenshot) — the screen as a PNG in the home folder
;;; (F12, and the launcher's Screenshot).

(library (schevana desktop screenshot)
  (export
    save-screenshot! next-screenshot-path)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) notify)
          (only (schevana kits png) png-write-screen-then))

  (library-layer desktop)

  ;; The screen, as a PNG in the home folder, and a toast saying where.
  (define (save-screenshot!)
    (png-write-screen-then (next-screenshot-path)
                           (lambda (path) (notify (format "Saved ~a" path)))))

  (define (next-screenshot-path)
    (let loop ([i 1])
      (let ([p (format "~a/schevana-~a.png" (or (getenv "HOME") ".") i)])
        (if (file-exists? p) (loop (+ i 1)) p)))))
