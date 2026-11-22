;;; (schevana services theme-file) — the saved look, the layers of (schevana
;;; core theme): the file holds the chosen style, the scale, the Overrides
;;; and your changes to each style. It is plain data, so loading it never
;;; evaluates code; a rule or a procedure typed at the REPL lasts only for
;;; the session. Every change to the layers saves the file soon after,
;;; through the core's hook theme-save!; (schevana desktop start) loads it
;;; before the boot (theme-file-load!).

(library (schevana services theme-file)
  (export
    *theme-file-path* theme-file-hex theme-file-plain? theme-file-save!
    *theme-file-save-pending* theme-file-save-soon! theme-file-valid-value?
    theme-file-style theme-file-valid-plist theme-file-old->changes
    theme-file-load-data! theme-file-load!)
  (import (chezscheme)
          (only (schevana base) define-state filter-map library-layer
                plist-keys plist-ref set-hook!)
          (only (schevana core) *palettes* *scale-setting* *style-changes*
                *style-name* *styles* *theme-overrides* after call-with-theme
                change-layers! color-keys default-theme find-style plist-has?
                resolve-theme safely stipple? style style-settings theme
                theme-default theme-layers-set! theme-rule? theme-save!))

  (library-layer services)

  (define-state *theme-file-path*
    (format "~a/.schevana-theme.ss" (or (getenv "HOME") ".")))

  (define (theme-file-hex v)
    (let ([s (string-downcase (number->string v 16))])
      (string-append "#x" (make-string (max 0 (- 6 (string-length s))) #\0) s)))

  (define (theme-file-plain? v)
    (or (number? v) (string? v) (symbol? v) (boolean? v) (null? v)
        (and (pair? v) (theme-file-plain? (car v))
             (theme-file-plain? (cdr v)))))

  (define (theme-file-save!)
    (let ([tmp (string-append *theme-file-path* ".tmp")])
      (define (pairs p plist)   ; one (key . value) per line, colors in hex
        (for-each (lambda (k)
                    (let ([v (plist-ref plist k #f)])
                      (when (theme-file-plain? v)
                        (if (and (memq k color-keys) (fixnum? v))
                            (fprintf p "\n   (~s . ~a)" k (theme-file-hex v))
                            (fprintf p "\n   (~s . ~s)" k v)))))
                  (plist-keys plist)))
      (when (file-exists? tmp) (delete-file tmp))
      (call-with-output-file tmp
        (lambda (p)
          (fprintf p ";; Schevana appearance, written by Settings. Plain data; \
                      safe to edit.\n((version . 2)\n (style . ~s)\n \
                      (scale . ~s)\n (overrides" *style-name* *scale-setting*)
          (pairs p *theme-overrides*)
          (fprintf p ")\n (changes")
          (for-each (lambda (c)
                      (fprintf p "\n  (~s" (car c))
                      (pairs p (cdr c))
                      (fprintf p ")"))
                    *style-changes*)
          (fprintf p "))\n")))
      (rename-file tmp *theme-file-path*)
      *theme-file-path*))

  (define-state *theme-file-save-pending* #f)

  ;; Saves the file 600 ms after the first unsaved change, with every
  ;; change made in the meantime. Returns void, which set-theme! and the
  ;; other setters return too, so a REPL prints nothing for them.
  (define (theme-file-save-soon!)
    (unless *theme-file-save-pending*
      (set! *theme-file-save-pending* #t)
      (after 600 (lambda ()
                   (set! *theme-file-save-pending* #f)
                   (theme-file-save!))))
    (void))

  ;; Whether v is a value the file may keep for key. A palette that is gone
  ;; is dropped, so the style's own applies; a style that is gone falls back
  ;; to mac (theme-file-style), and a wallpaper that is gone draws as the
  ;; default. A value of a kind that none of key's defaults has is dropped
  ;; (the built-in default, or a style's for its own options).
  (define (theme-file-valid-value? key v)
    (let ([ds (map (lambda (p) (plist-ref p key #f))
                   (filter (lambda (p) (plist-has? p key))
                           (cons default-theme
                                 (map style-settings *styles*))))])
      (cond
        [(memq key color-keys)
         (or (fixnum? v) (stipple? v)
             (and (pair? v) (or (fixnum? (car v)) (symbol? (car v)))
                  (real? (cdr v))))]
        [(eq? key 'palette) (and (assq v *palettes*) #t)]
        [else (exists (lambda (kind?) (and (kind? v) (exists kind? ds)))
                      (list fixnum? string? symbol? boolean? list?))])))

  (define (theme-file-style s) (if (find-style s) s 'mac))

  ;; Returns the pairs of alist, ((key . value) ...), whose values are valid
  ;; for their keys, as a plist.
  (define (theme-file-valid-plist alist)
    (if (list? alist)
        (apply append
               (filter-map (lambda (kv)
                             (and (pair? kv)
                                  (theme-file-valid-value? (car kv) (cdr kv))
                                  (list (car kv) (cdr kv))))
                           alist))
        '()))

  ;; Reads an old file, one flat table, as your changes to one style. Its
  ;; window-style is the style (mac if that style is gone), and its preset
  ;; is that style's palette (tokyo-night if the preset is gone). Its other
  ;; keys are changes where they differ from what the style and the palette
  ;; give; a key whose default is a rule (a derived color) is a change only
  ;; where it differs from what the rule gives from those changes. The
  ;; wallpaper counts even when the file leaves it out (old files did not
  ;; save the default), or the palette's own would replace it.
  ;; Returns (style key value ...).
  (define (theme-file-old->changes alist)
    (let* ([ref (lambda (k d) (let ([p (assq k alist)]) (if p (cdr p) d)))]
           [style (theme-file-style (ref 'window-style 'mac))]
           [palette (if (assq (ref 'preset #f) *palettes*)
                        (ref 'preset #f)
                        'tokyo-night)]
           [kvs (theme-file-valid-plist
                 (cons (cons 'wallpaper (ref 'desktop-pattern 'gradient))
                       (remp (lambda (kv) (eq? (car kv) 'desktop-pattern))
                             alist)))]
           [derived? (lambda (k) (theme-rule? (theme-default k)))]
           ;; the keys of kvs that keep? accepts and whose values differ
           ;; from the theme that changes gives
           [differing
            (lambda (changes keep?)
              (call-with-theme (resolve-theme style '() changes)
                (lambda ()
                  (let loop ([p kvs])
                    (cond [(null? p) '()]
                          [(and (keep? (car p))
                                (not (equal? (cadr p) (theme (car p)))))
                           (cons* (car p) (cadr p) (loop (cddr p)))]
                          [else (loop (cddr p))])))))]
           [chosen (cons* 'palette palette
                          (differing (list 'palette palette)
                                     (lambda (k) (not (derived? k)))))])
      (cons style (append chosen (differing chosen derived?)))))

  ;; Sets the layers from data, the file's list of pairs (an old file's
  ;; too). Nothing changes until all of it has been read.
  (define (theme-file-load-data! data)
    (let* ([ref (lambda (k d) (let ([p (assq k data)]) (if p (cdr p) d)))]
           [scale (let ([s (ref 'scale 0)]) (if (fixnum? s) s 0))])
      (define (set-layers! style overrides changes)
        (theme-layers-set! style overrides changes scale))
      (if (eqv? (ref 'version 1) 2)
          (let ([cs (ref 'changes '())])
            (set-layers!
             (theme-file-style (ref 'style 'mac))
             (theme-file-valid-plist (ref 'overrides '()))
             ;; the changes to a style that is gone are kept for when it
             ;; returns
             (if (list? cs)
                 (filter-map (lambda (c)
                               (and (pair? c) (symbol? (car c))
                                    (cons (car c)
                                          (theme-file-valid-plist (cdr c)))))
                             cs)
                 '())))
          (let ([c (theme-file-old->changes data)])
            (set-layers! (car c) '() (list c))))))

  (define (theme-file-load!)
    (when (file-exists? *theme-file-path*)
      (safely 'theme
        (lambda ()
          (let ([data (call-with-input-file *theme-file-path* read)])
            (when (list? data)
              (change-layers!
               (lambda () (theme-file-load-data! (filter pair? data))))))))))

  (set-hook! (theme-save!) (theme-file-save-soon!)))
