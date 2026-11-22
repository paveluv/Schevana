;;; (schevana kits theme) — answers to questions about the theme ((schevana
;;; core theme)), for Settings and the REPL: which layer gives a setting, and
;;; what a palette would show.
;;;
;;;   (theme-source 'accent)            which layer gives it

(library (schevana kits theme)
  (export
    theme-source theme-palette-preview)
  (import (chezscheme)
          (only (schevana base) library-layer)
          (only (schevana core) *style-name* *theme-overrides* call-with-theme
                color-keys default-theme honored? palette-colors plist-has?
                resolve-theme style style-chain style-changes-of style-name
                style-settings theme))

  (library-layer kits)

  ;; Returns the layer that gives key, with its value: (overrides v),
  ;; (changes mac v), (style genera v), (palette nord v) or (built-in v);
  ;; #f if no layer gives it.
  (define (theme-source key)
    (let* ([name *style-name*] [chain (style-chain name)]
           [yours? (lambda (p) (and (honored? chain key) (plist-has? p key)))]
           [style (find (lambda (s) (plist-has? (style-settings s) key))
                        chain)]
           [palette (theme 'palette)])
      (cond [(yours? *theme-overrides*) (list 'overrides (theme key))]
            [(yours? (style-changes-of name)) (list 'changes name (theme key))]
            [style (list 'style (style-name style) (theme key))]
            [(plist-has? (palette-colors palette) key)
             (list 'palette palette (theme key))]
            [(plist-has? default-theme key) (list 'built-in (theme key))]
            [else #f])))

  ;; Returns the colors and the wallpaper that the chosen style would show
  ;; with the palette named name, as a plist.
  (define (theme-palette-preview name)
    (let ([t (resolve-theme *style-name* '() (list 'palette name))])
      (call-with-theme t
        (lambda ()
          (apply append (map (lambda (k) (list k (theme k)))
                             (append color-keys '(wallpaper)))))))))
