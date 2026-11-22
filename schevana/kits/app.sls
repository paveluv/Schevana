;;; (schevana kits app) — the apps the core registers (define-app), as the
;;; desktop shows them: launching one by name, and the color a name gets (the
;;; taskbar's, a style's icon), from the theme's app-colors.

(library (schevana kits app)
  (export
    app-launch! app-color)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) *apps* app-launch app-name theme
                theme-default!))

  (library-layer kits)

  (define (app-launch! name)
    (let ([a (find (lambda (a) (eq? (app-name a) name)) *apps*)])
      (if a ((app-launch a)) (errorf 'app-launch! "no app named ~s" name))))

  ;; The colors app-color picks from, a style's to change.
  (at-load
   (theme-default! 'app-colors
                   '(accent accent-2 green orange cyan red yellow teal
                            magenta)))

  ;; mod n at every step: the same color as at the end, but a long name's
  ;; hash never grows.
  (define (app-color name)
    (let* ([s (symbol->string (or name 'unknown))] [cs (theme 'app-colors)]
           [n (length cs)])
      (list-ref cs
                (fold-left (lambda (h c) (mod (+ (* h 31) (char->integer c)) n))
                           (mod 7 n) (string->list s))))))
