;;; (schevana desktop keys) — the desktop's default key bindings. They are
;;; installed once per session, when this file first loads, so a reload does
;;; not undo an unbind-key! you made.

(library (schevana desktop keys)
  (export)
  (import (chezscheme)
          (only (schevana base) at-load-once define-made library-layer)
          (only (schevana core) *focus* *global-keys* bind-key!
                minimize-window! toggle-fullscreen! toggle-maximize!)
          (only (schevana kits app) app-launch!)
          (only (schevana desktop arrange) tile-windows! close-focused-window!
                cycle-windows!)
          (only (schevana desktop launcher) toggle-launcher!)
          (only (schevana desktop screenshot) save-screenshot!))

  (library-layer desktop)

  (define-made default-global-keys
    `(((f1) . ,(lambda () (toggle-launcher!)))
      ((ctrl tab) . ,(lambda () (cycle-windows!)))
      ((ctrl shift #\w) . ,(lambda () (close-focused-window!)))
      ((ctrl shift #\m) .
                        ,(lambda () (when *focus* (toggle-maximize! *focus*))))
      ((ctrl shift #\n) .
                        ,(lambda () (when *focus* (minimize-window! *focus*))))
      ((ctrl shift #\t) . ,(lambda () (tile-windows!)))
      ((ctrl shift #\r) . ,(lambda () (app-launch! 'repl)))
      ((f11) . ,(lambda () (toggle-fullscreen!)))
      ((f12) . ,(lambda () (save-screenshot!)))))

  (define (install-default-keys!)
    (for-each (lambda (b)
                (unless (assoc (car b) *global-keys*)
                  (bind-key! (car b) (cdr b))))
              default-global-keys))

  ;; A world that already has bindings when this library first loads keeps
  ;; its keys.
  (at-load-once
   (unless (pair? *global-keys*)
     (install-default-keys!))))
