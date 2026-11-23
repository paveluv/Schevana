;;; (schevana kits app) — the apps the core registers (define-app), as the
;;; desktop uses them: it finds one by name and launches it, and gives each
;;; app's name a color from the theme's app-colors (for the stand-in icon
;;; of an app that gives none, (schevana kits ui)).

(library (schevana kits app)
  (export
    app-find app-launch! app-color)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) *apps* app-launch app-name theme
                theme-default!))

  (library-layer kits)

  ;; Returns the registered app named name, or #f.
  (define (app-find name)
    (let loop ([as *apps*])
      (cond [(null? as) #f]
            [(eq? (app-name (car as)) name) (car as)]
            [else (loop (cdr as))])))

  (define (app-launch! name)
    (let ([a (app-find name)])
      (if a ((app-launch a)) (errorf 'app-launch! "no app named ~s" name))))

  ;; The colors app-color picks from; a style may change them.
  (at-load
   (theme-default! 'app-colors
                   '(accent accent-2 green orange cyan red yellow teal
                            magenta)))

  ;; Taking mod n at every step gives the same color as taking it once at
  ;; the end, but the hash of a long name never grows.
  (define (app-color name)
    (let* ([s (symbol->string (or name 'unknown))] [cs (theme 'app-colors)]
           [n (length cs)])
      (list-ref cs
                (fold-left (lambda (h c) (mod (+ (* h 31) (char->integer c)) n))
                           (mod 7 n) (string->list s))))))
