;;; kits/theme.ss — questions about the theme (src/core1/theme.ss): which
;;; layer gives a setting, and what a palette would show (Settings, the
;;; REPL).
;;;
;;;   (theme-source 'accent)            which layer gives it

;; Which layer gives key: (overrides v), (changes mac v), (style genera
;; v), (palette nord v) or (built-in v); #f if none.
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

;; The colors and wallpaper the chosen style shows in palette name.
(define (theme-palette-preview name)
  (let ([t (resolve-theme *style-name* '() (list 'palette name))])
    (call-with-theme t
      (lambda ()
        (apply append (map (lambda (k) (list k (theme k)))
                           (append color-keys '(wallpaper))))))))
