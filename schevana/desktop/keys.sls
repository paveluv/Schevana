;;; (schevana desktop keys) — the desktop's default key bindings, installed
;;; once a session when this file first loads: a reload does not undo your
;;; unbind-key!.

(library (schevana desktop keys)
  (export
    default-global-keys install-default-keys! *default-keys-installed?*)
  (import (chezscheme)
          (only (schevana base) at-load define-made define-state library-layer)
          (only (schevana core) *focus* *global-keys* bind-key!
                minimize-window! toggle-fullscreen! toggle-maximize!)
          (only (schevana kits app) app-launch!)
          (only (schevana desktop arrange) tile-windows! close-focused-window!
                cycle-windows!)
          (only (schevana desktop menu) toggle-launcher!)
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

  ;; A world that already has bindings (one reloaded from before this file,
  ;; which installed them at boot) has its keys.
  (define-state *default-keys-installed?* (pair? *global-keys*))
  (at-load
   (unless *default-keys-installed?*
     (install-default-keys!)
     (set! *default-keys-installed?* #t))))
