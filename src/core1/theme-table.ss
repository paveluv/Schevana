;;; theme-table.ss — the settings in effect: the one table (theme key)
;;; reads, where drawing finds a color or a font by its key. What fills
;;; it, the layers of a look (styles, palettes, the built-in defaults), is
;;; the theme's, above drawing (src/core1/theme.ss); with none, the table
;;; is empty, and a color is its number.

(defvar *theme* (make-eq-hashtable))   ; every setting in effect
;; the chosen style's: *theme* is another while a window of another style,
;; a preview or a place is drawn, or a window's handler runs
(defvar *main-theme* *theme*)

;; A setting computed from others when the theme is built.
(define-record-type (theme-rule-box make-theme-rule theme-rule?)
  (nongenerative schevana-rule-1)
  (fields thunk))
(define-syntax theme-rule
  (syntax-rules () [(_ e) (make-theme-rule (lambda () e))]))

(define theme-unset (list 'unset))
(define theme-busy (list 'busy))

;; thunk's values with t (a resolved theme) in effect meanwhile: a look
;; that isn't on, read as if it were (a preview, a comparison).
(define (call-with-theme t thunk)
  (fluid-let ([*theme* t]) (thunk)))

;; A rule still in the table is computed the first time it is read.
(define (theme key)
  (let ([v (hashtable-ref *theme* key theme-unset)])
    (cond [(eq? v theme-unset) (errorf 'theme "unknown theme key ~s" key)]
          [(theme-rule? v) (compute-rule! key v)]
          [(eq? v theme-busy) (errorf 'theme "~s is computed from itself" key)]
          [else v])))

(define (compute-rule! key r)
  (hashtable-set! *theme* key theme-busy)
  (let ([v (guard (c [#t (hashtable-set! *theme* key r) (raise c)])
             ((theme-rule-box-thunk r)))])
    (hashtable-set! *theme* key v)
    v))

(define (theme-keys)
  (vector->list
   (vector-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
                (hashtable-keys *theme*))))

;; The procedure the theme gives for key: a procedure, or the name of a
;; top-level one, looked up at each call, so a redefinition shows on the
;; next frame.
(define (theme-part key)
  (let ([v (theme key)])
    (if (symbol? v) (world-value v) v)))

;; The pacer's choices, settings a person may change live (src/core1/theme.ss),
;; unless a trial holds them: ((key . value) ...), the pacer lab's
;; (services/pacer-lab.ss), which is never saved with the look.
(defvar *pacer-trial* '())

(define (pacer-knob key)
  (let ([t (assq key *pacer-trial*)]) (if t (cdr t) (theme key))))
