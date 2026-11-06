;;; tests/units/settings.ss — Settings' Theme tab: a style's own options,
;;; saving a style.

;;; Settings' Theme tab (step 8)

;; A style with options of its own: a size, a choice.
(define-style test-own "Own options"
  'test-own-width 3  'test-own-ink 'dim
  'options '(palette (test-own-width "Width" 1 6)
             (test-own-ink "Ink" (("Dim" . dim) ("Bright" . bright)))))

(check "a style's own option's value saves and loads back, of the kind the \
        style gives it; one of another kind is dropped"
       (begin
         (set-style! 'test-own)
         (set-theme! 'test-own-width 5)
         (set-theme! 'test-own-ink 'bright)
         (theme-file-save!)
         (reset-theme!)
         (theme-file-load!)
         (let ([got (list (theme 'test-own-width) (theme 'test-own-ink))])
           (reset-theme!)
           (set-style! 'mac)
           (and (equal? got '(5 bright))
                (theme-file-valid-value? 'test-own-width 2)
                (not (theme-file-valid-value? 'test-own-width 'wide))
                (not (theme-file-valid-value? 'test-own-ink 4))))))

(check "Settings shows a style's own options, and the common ones it does \
        not honor as fixed"
       (begin
         (set-style! 'test-own)
         (let ([own (map car (settings-own-options))]
               [words (settings-value-words 'test-own-ink 'bright)]
               [fixed (theme 'fixed)])
           (set-style! 'mac)
           (and (equal? own '(test-own-width test-own-ink))
                (equal? words "Bright")
                (memq 'corner-radius fixed) (not (memq 'palette fixed))
                (null? (settings-own-options))
                (not (settings-option 'test-own-ink))))))

(check "a detached window is a window in its style that is not on screen"
       (let ([w (detached-window "Away" 'size '(200 . 100)
                                 'window-style 'genera)])
         (let-values ([(l t r b) (frame-insets w)])
           (and (not (memq w (windows)))
                (= (window-w w) (+ 200 l r)) (= (window-h w) (+ 100 t b))
                (eq? (window-ref w 'window-style) 'genera)))))

(check "save-style-as! writes a define-style of your changes over the \
        chosen style, loads it and chooses it; a name in use is refused"
       (let ([dir (string-append out-dir "/saved-styles")])
         (set! *settings-style-directory* dir)
         (when (file-exists? (string-append dir "/test-saved.ss"))
           (delete-file (string-append dir "/test-saved.ss")))
         (set-style! 'test-own)
         (set-theme! 'test-own-width 4)
         (set-theme! 'palette 'nord)
         (let* ([path (save-style-as! 'test-saved "Test saved")]
                [form (call-with-input-file path read)]
                [ok (list (current-style) (style-changes-of 'test-own)
                          (theme 'test-own-width) (theme 'palette)
                          (raises? (lambda () (save-style-as! 'mac "Mac"))))])
           (set-style! 'mac)
           (reset-theme!)
           (set! *styles* (remp (lambda (s) (memq (style-name s)
                                                  '(test-saved test-own)))
                                *styles*))
           (and (equal? form '(define-style test-saved "Test saved"
                                'parent 'test-own 'palette 'nord
                                'test-own-width 4))
                (equal? ok '(test-saved () 4 nord #t))))))

(check "a new style's name comes from its title"
       (and (eq? (settings-style-name "My Genera") 'my-genera)
            (eq? (settings-style-name "  CDE: Broica II ") 'cde-broica-ii)
            (not (settings-style-name " - "))))
