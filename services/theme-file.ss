;;; services/theme-file.ss — the saved look (src/core1/theme.ss's layers):
;;; the file holds the chosen style, the scale, the Overrides and your
;;; changes per style. It is plain data: loading it never evaluates code. A
;;; rule or a procedure typed at the REPL lasts the session. Every change
;;; to the layers saves it soon after, through the core's *theme-saver*;
;;; world.ss loads it before boot (theme-file-load!).

(defvar *theme-file-path*
  (format "~a/.schevana-theme.ss" (or (getenv "HOME") ".")))

(define (theme-file-hex v)
  (let ([s (string-downcase (number->string v 16))])
    (string-append "#x" (make-string (max 0 (- 6 (string-length s))) #\0) s)))

(define (theme-file-plain? v)
  (or (number? v) (string? v) (symbol? v) (boolean? v) (null? v)
      (and (pair? v) (theme-file-plain? (car v)) (theme-file-plain? (cdr v)))))

(define (theme-file-save!)
  (let ([tmp (string-append *theme-file-path* ".tmp")])
    (define (pairs p plist)   ; (key . value) a line, colors in hex
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

(defvar *theme-file-save-pending* #f)

;; Saves 600 ms after a change, with the changes made meanwhile.
(define (theme-file-save-soon!)
  (unless *theme-file-save-pending*
    (set! *theme-file-save-pending* #t)
    (after 600 (lambda ()
                 (set! *theme-file-save-pending* #f)
                 (theme-file-save!)))))

;; A palette or style that is gone falls back, a wallpaper that is gone
;; draws as the default; a value of no kind its defaults have is dropped
;; (the built-in one, or a style's for its own options).
(define (theme-file-valid-value? key v)
  (let ([ds (map (lambda (p) (plist-ref p key #f))
                 (filter (lambda (p) (plist-has? p key))
                         (cons default-theme (map style-settings *styles*))))])
    (cond
      [(memq key color-keys)
       (or (fixnum? v) (stipple? v)
           (and (pair? v) (or (fixnum? (car v)) (symbol? (car v)))
                (real? (cdr v))))]
      [(eq? key 'palette) (and (assq v *palettes*) #t)]
      [else (exists (lambda (kind?) (and (kind? v) (exists kind? ds)))
                    (list fixnum? string? symbol? boolean? list?))])))

(define (theme-file-style s) (if (find-style s) s 'mac))

;; The settings of ((key . value) ...) that fit their keys, as a plist.
(define (theme-file-valid-plist alist)
  (if (list? alist)
      (apply append
             (filter-map (lambda (kv)
                           (and (pair? kv)
                                (theme-file-valid-value? (car kv) (cdr kv))
                                (list (car kv) (cdr kv))))
                         alist))
      '()))

;; An old file, one flat table: its style chosen (mac for one that is
;; gone), its preset that style's palette, and its keys that differ from
;; what the layers under them give, your changes to it; a color a rule
;; derives is one only where it differs from what the rule gives from
;; them. Its wallpaper counts even when left out (it saved no default),
;; or a palette's own would replace it. => (style key value ...)
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
         ;; the keys of kvs that keep? takes and that differ from the
         ;; theme these changes give
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

;; data: the file's, a list of pairs. Nothing changes until all of it is
;; read.
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
           ;; a style that is gone keeps your changes for when it returns
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

(set! *theme-saver* (lambda () (theme-file-save-soon!)))
