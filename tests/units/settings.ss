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

(check "Settings' Display tab offers how frames are presented where the \
        window has a choice: the choice holds in every style and saves, and \
        the default drops it"
       (let ()
         (define (press! ui win id)
           (let-values ([(cx cy cw ch) (content-rect win)])
             (let* ([r (ui-find ui id)]
                    [x (exact (round (+ cx (ui-region-x r)
                                        (/ (ui-region-w r) 2))))]
                    [y (exact (round (+ cy (ui-region-y r)
                                        (/ (ui-region-h r) 2))))])
               (inject! `(mouse-down ,x ,y left 1) `(mouse-up ,x ,y left))
               (steps 3))))
         (define (shown ui) (and (ui-find ui '(present-mode mailbox)) #t))
         (let* ([win (settings)] [ui (window-ref win 'ui)])
           (steps 3)
           (press! ui win '(tab display))
           (let ([no-window (shown ui)])
             (fluid-let ([*gpu-facts* (cons '(present-modes vsync mailbox)
                                            *gpu-facts*)]
                         [sdl-set-swapchain-parameters (lambda args #t)])
               (invalidate! win)
               (steps 3)
               (let ([offered (shown ui)])
                 (press! ui win '(present-mode mailbox))
                 (let ([chosen (theme 'present-mode)]
                       [elsewhere (begin (set-style! 'genera)
                                         (theme 'present-mode))])
                   (set-style! 'mac)
                   (theme-file-save!)
                   (override! 'present-mode)
                   (theme-file-load!)
                   (let ([loaded (theme 'present-mode)])
                     (steps 3)
                     (press! ui win '(present-mode vsync))
                     (let ([dropped (settings-pinned? 'present-mode)])
                       (close-window! win)
                       (steps 2)
                       (and (not no-window) offered
                            (eq? chosen 'mailbox) (eq? elsewhere 'mailbox)
                            (eq? loaded 'mailbox) (not dropped)
                            (eq? (theme 'present-mode) 'vsync)))))))))))

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

;; Settings' Paths tab: the library search by rank, each folder with a
;; switch for whether it auto-loads, and a row that adds one: a folder
;; picked in the file dialog joins the search, not auto-loading until its
;; switch is turned on.
(define (settings-test-rank dir)
  (let loop ([ds (library-directories)] [i 0])
    (cond [(null? ds) #f]
          [(equal? (path-full (if (pair? (car ds)) (caar ds) (car ds)))
                   (path-full dir))
           i]
          [else (loop (cdr ds) (+ i 1))])))

(let ([dir (string-append out-dir "/paths-tab")])
  (system (format "rm -rf '~a' && mkdir -p '~a'" dir dir))
  (for-each close-window! (windows))
  (app-launch! 'settings)
  (steps 2)
  (let ([win (find-window 'settings)])
    (settings-st-tab-set! (window-ref win 'state) 'paths)
    (invalidate! win)
    (steps 2)
    (test-click! win '(search add))
    (steps 2)
    ;; the dialog, over Settings: the folder named, then Add
    (let* ([fd (focused-window)] [d (window-ref fd 'state)])
      (file-dialog-name-set! d (path-full dir))
      (invalidate! fd)
      (steps 1)
      (test-click! fd '(file-dialog pick))
      (steps 2))
    (let* ([i (settings-test-rank dir)]
           [added (and i (not (member (path-full dir) (auto-loads))))])
      (invalidate! win)
      (steps 2)
      (when i (test-click! win `(search (search-auto ,i))))
      (steps 1)
      (check (format "the Paths tab adds a folder to the library search, \
                      not auto-loading, and its switch turns it on ~s"
                     (list i (auto-loads)))
             (and (not (window-error win))
                  added
                  (member (path-full dir) (auto-loads))
                  (member (path-full dir) *auto-loads*))))
    (let* ([full (map (lambda (d) (path-full (if (pair? d) (car d) d)))
                      (library-directories))]
           [libs (cadr (settings-path-facts (window-ref win 'ui)))]
           [ranks (map (lambda (l)
                         (if (caddr l) (settings-layer-rank (caddr l)) 1000))
                       libs)])
      (check (format "the library search holds each folder once, Chez's \
                      \".\" not again where it is the tree; the libraries \
                      loaded go by the rank of the layer each declares ~s"
                     (list full (list-head ranks (min 5 (length ranks)))))
             (and (let loop ([fs full])
                    (or (null? fs)
                        (and (not (member (car fs) (cdr fs)))
                             (loop (cdr fs)))))
                  (equal? (list-head (library-layer-names) 4)
                          '(foundation core0 recorder core))
                  (eq? (caddr (assoc '(schevana core) libs)) 'core)
                  (= (settings-layer-rank 'core) 4)
                  (let loop ([rs ranks])
                    (or (null? rs) (null? (cdr rs))
                        (and (<= (car rs) (cadr rs)) (loop (cdr rs))))))))
    (auto-load-forget! dir)
    (close-window! win)))
