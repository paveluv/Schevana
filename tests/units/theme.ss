;;; tests/units/theme.ss — settings in layers, the theme file, fonts and sizes
;;; as settings.

;;; settings in layers

;; Runs thunk with the mac style given these settings too (its own options,
;; say), with your changes and the Overrides cleared before and after.
(define (with-mac-settings settings thunk)
  (let ([plain *styles*])
    (dynamic-wind
      (lambda ()
        (register-style! 'mac "Mac"
                         (append settings (style-settings (find-style 'mac))))
        (set-style! 'mac)
        (reset-theme!))
      thunk
      (lambda ()
        (set! *styles* plain)
        (reset-theme!)))))

;; The accent and where it comes from, after each layer gives one.
(check "a setting comes from the first layer that has it: the Overrides, \
        your changes to the style, the style, its palette, the built-ins"
       (let ([at (lambda () (list (theme 'accent) (theme-source 'accent)))])
         (equal?
          (list (with-mac-settings '() at)
                (with-mac-settings '()
                  (lambda () (set-theme! 'palette 'nord) (at)))
                (with-mac-settings '(accent #x112233)
                  (lambda () (set-theme! 'palette 'nord) (at)))
                (with-mac-settings '(accent #x112233)
                  (lambda () (set-theme! 'accent #x445566) (at)))
                (with-mac-settings '(accent #x112233)
                  (lambda ()
                    (set-theme! 'accent #x445566)
                    (override! 'accent #x778899)
                    (let ([over (at)])
                      (override! 'accent)
                      (let ([cleared (at)])
                        (reset-style! 'accent)
                        (list over cleared (at)))))))
          '((#x7aa2f7 (built-in #x7aa2f7))
            (#x88c0d0 (palette nord #x88c0d0))
            (#x112233 (style mac #x112233))
            (#x445566 (changes mac #x445566))
            ((#x778899 (overrides #x778899))
             (#x445566 (changes mac #x445566))
             (#x112233 (style mac #x112233)))))))

;; A style that lists its options honors only those common options: for
;; the others, the style's value holds under your changes and the
;; Overrides. Keys that are not common options are always yours.
(check "a style honors the common options it lists, and every other key"
       (equal?
        (with-mac-settings '(options (accent) corner-radius 3)
          (lambda ()
            (override! 'corner-radius 12)
            (set-theme! 'ui-font-size 20)
            (override! 'accent #x778899)
            (set-theme! 'red #x010203)
            (map theme '(corner-radius ui-font-size accent red))))
        '(3 13 #x778899 #x010203)))

(check "a rule computed from itself is named, and the theme stays"
       (with-mac-settings '()
         (lambda ()
           (set-changes! 'mac (list 'loop-a (theme-rule (theme 'loop-b))
                                    'loop-b (theme-rule (theme 'loop-a))))
           (let* ([before *theme*]
                  [msg (guard (c [#t (condition->string c)])
                         (theme-changed!)
                         #f)])
             (set-changes! 'mac '())
             (and msg (string-contains-ci? msg "computed from itself")
                  (or (string-contains-ci? msg "loop-a")
                      (string-contains-ci? msg "loop-b"))
                  (eq? *theme* before))))))

;; Returns a theme of one key, units-slow, whose rule gives 42, and a box.
;; In a process the rule first waits (proc-wait) until the procedure that
;; the box then holds is called: the process is switched out inside the
;; rule, as a preemption leaves it, for as long as a check likes. With
;; self? the rule then reads itself.
(define (waiting-rule-theme self?)
  (let ([go (box #f)] [t (make-eq-hashtable)])
    (hashtable-set! t 'units-slow
                    (theme-rule
                     (begin
                       (when (current-proc)
                         (proc-wait 'units (lambda (k) (set-box! go k))))
                       (if self? (theme 'units-slow) 42))))
    (values t go)))

;; Returns units-slow of theme t, read where this runs, or the message of
;; what the read raised.
(define (read-units-slow t)
  (guard (c [#t (condition->string c)])
    (call-with-theme t (lambda () (theme 'units-slow)))))

(check "a rule that a process is switched out of is computed again where \
        it is read meanwhile, not taken for one computed from itself, and \
        the process then gives the same value"
       (let-values ([(t go) (waiting-rule-theme #f)])
         (let* ([done #f]
                [p (spawn "units" (lambda () (read-units-slow t))
                          (lambda (status value) (set! done value)))]
                [waiting (test-wait 1000 (lambda () (unbox go)))]
                [here (read-units-slow t)])
           (when waiting (waiting))
           (test-wait 1000 (lambda () done))
           (kill! p)
           (and waiting (eqv? here 42) (equal? done '(42))))))

(check "a rule that a killed process was computing is computed by the \
        next reader"
       (let-values ([(t go) (waiting-rule-theme #f)])
         (let* ([p (spawn "units" (lambda () (read-units-slow t)))]
                [waiting (test-wait 1000 (lambda () (unbox go)))])
           (kill! p)
           (and waiting (eqv? (read-units-slow t) 42)))))

(check "a rule that reads itself is named as computed from itself, though \
        its process was switched out inside it"
       (let-values ([(t go) (waiting-rule-theme #t)])
         (let* ([done #f]
                [p (spawn "units" (lambda () (read-units-slow t))
                          (lambda (status value) (set! done value)))]
                [waiting (test-wait 1000 (lambda () (unbox go)))])
           (when waiting (waiting))
           (test-wait 1000 (lambda () done))
           (kill! p)
           (and waiting (pair? done) (string? (car done))
                (string-contains-ci? (car done) "computed from itself")))))

(check "a base color changed re-derives what its rules derive from it"
       (with-mac-settings '()
         (lambda ()
           (set-theme! 'accent #xff9e64)
           (set-theme! 'bg-3 #x404040)
           (and (= (theme 'selection) (mix #xff9e64 'bg-1 0.65))
                (= (theme 'window-border-focus) (mix #x404040 #xff9e64 0.45))
                (= (theme 'panel-hover) #x404040)
                (= (theme 'button-idle) (mix #x404040 'text 0.15))))))

;; Theme files an older tree wrote (the tests' fixtures, from .work): Tokyo
;; Night with an accent and a radius, Nord with a radius, Genera with its
;; palette and an accent of its own, and one that names a style and a
;; palette since removed. Each loads to what that tree resolved from it:
;; its own values, and the built-in ones for the rest; its style and
;; palette are chosen (mac and Tokyo Night where they are gone), and only
;; your choices are kept as changes.
(define old-theme-files
  '((default (accent . #xff9e64) (selection . #x6a493c)
             (window-border-focus . #x896051) (corner-radius . 4))
    (nord (bg-0 . #x242933) (bg-1 . #x2e3440) (bg-2 . #x353c4a)
          (bg-3 . #x3b4252) (text . #xeceff4) (text-dim . #xd8dee9)
          (text-faint . #x6d7a96) (accent . #x88c0d0) (accent-2 . #xb48ead)
          (red . #xbf616a) (orange . #xd08770) (yellow . #xebcb8b)
          (green . #xa3be8c) (cyan . #x8fbcbb) (teal . #x8fbcbb)
          (magenta . #xb48ead) (selection . #x4e6572)
          (desktop-top . #x252a34) (desktop-bottom . #x3a4660)
          (panel . #x1f232b) (panel-text . #xeceff4) (panel-dim . #x6d7a96)
          (panel-hover . #x3b4252) (window-bg . #x2e3440)
          (window-border . #x49505f) (window-border-focus . #x5e7b8b)
          (title-bg . #x353c4a) (title-bg-focus . #x3b4252)
          (title-text . #xeceff4) (title-text-dim . #x6d7a96)
          (button-close . #xbf616a) (button-min . #xebcb8b)
          (button-max . #xa3be8c) (button-idle . #x565c6a)
          (corner-radius . 4) (preset . nord))
    (genera (bg-0 . #xffffff) (bg-1 . #xffffff) (bg-2 . #xf0f0f0)
            (bg-3 . #xd8d8d8) (text . #x000000) (text-dim . #x222222)
            (text-faint . #x666666) (accent . #x3366cc) (accent-2 . #x444444)
            (red . #x8b0000) (orange . #x6b4400) (yellow . #x5c5c00)
            (green . #x1f5f1f) (cyan . #x1f5566) (teal . #x1f5f55)
            (magenta . #x661f66) (selection . #xb8c9ed)
            (desktop-top . #xffffff) (desktop-bottom . #xffffff)
            (watermark . #x000000) (panel . #x000000) (panel-text . #xffffff)
            (panel-dim . #xb4b4b4) (panel-hover . #x383838)
            (window-bg . #xffffff) (window-border . #xc7c7c7)
            (window-border-focus . #x8ea5d3) (title-bg . #xf0f0f0)
            (title-bg-focus . #xd8d8d8) (title-text . #x000000)
            (title-text-dim . #x666666) (button-close . #x8b0000)
            (button-min . #x5c5c00) (button-max . #x1f5f1f)
            (button-idle . #xb8b8b8) (window-style . genera)
            (preset . genera) (desktop-pattern . flat))
    (deleted (window-style . amiga) (preset . workbench) (corner-radius . 4))))

(define (write-theme-file! data)
  (call-with-output-file *theme-file-path* (lambda (p) (write data p))
    'replace))

;; The colors a palette gives or derives (not those kits and styles add).
(define palette-keys
  (append (plist-keys base-colors) (plist-keys derived-colors)))

(let* ([fresh (let ([t (resolve-theme 'mac '() '())])
                (compute-rules! t)
                t)]
       [loaded
        (map (lambda (f)
               (let ([file (cdr f)])
                 (write-theme-file! file)
                 (theme-file-load!)
                 (list (car f)
                       (for-all (lambda (k)
                                  (equal? (theme k)
                                          (let ([p (assq k file)])
                                            (if p
                                                (cdr p)
                                                (hashtable-ref fresh k #f)))))
                                palette-keys)
                       (theme 'window-style) (theme 'palette)
                       (theme 'corner-radius) (theme 'wallpaper)
                       *style-changes*)))
             old-theme-files)])
  (set-style! 'mac)
  (reset-theme!)
  (check (format "old theme files load to the colors today's tree resolved \
                  from them, and your choices as the style's changes: ~s"
                 loaded)
         (equal? loaded
                 '((default #t mac tokyo-night 4 gradient
                            ((mac palette tokyo-night accent #xff9e64
                                  corner-radius 4)))
                   (nord #t mac nord 4 gradient
                         ((mac palette nord corner-radius 4)))
                   ;; a v1 file holds every color, and those the Genera
                   ;; style inks become its changes
                   (genera #t genera genera 0 flat
                           ((genera palette genera bg-2 #xf0f0f0
                                    bg-3 #xd8d8d8 text-dim #x222222
                                    text-faint #x666666 accent #x3366cc
                                    accent-2 #x444444 red #x8b0000
                                    orange #x6b4400 yellow #x5c5c00
                                    green #x1f5f1f cyan #x1f5566
                                    teal #x1f5f55 magenta #x661f66
                                    window-border #xc7c7c7
                                    window-border-focus #x8ea5d3)))
                   (deleted #t mac tokyo-night 4 gradient
                            ((mac palette tokyo-night corner-radius 4)))))))

;; Saved, cleared and loaded again, the chosen style, the scale, the
;; Overrides and every style's changes come back; the file is plain data,
;; with its colors in hex.
(check "the theme file round-trips: style, scale, Overrides, changes"
       (let ([text (lambda ()
                     (call-with-input-file *theme-file-path* get-string-all))])
         (set-style! 'genera)
         (set-theme! 'palette 'nord)
         (set-theme! 'corner-radius 4)
         (set-style! 'mac)
         (set-theme! 'accent #xff9e64)
         (override! 'ui-font-size 15)
         (let ([state (list *style-name* *scale-setting* *theme-overrides*
                            *style-changes*)]
               [file (begin (theme-file-save!) (text))])
           (set-style! 'windows)
           (reset-theme!)
           (theme-file-load!)
           (let ([back (list *style-name* *scale-setting* *theme-overrides*
                             *style-changes*)])
             (reset-theme!)
             (set-style! 'mac)
             (and (equal? back state)
                  (string-contains-ci? file "(accent . #xff9e64)")
                  (string-contains-ci? file "(version . 2)")
                  (equal? (theme 'ui-font-size) 13))))))

;; Every palette, Tokyo Night too, derives the colors it does not give as
;; derived-as-today does: a copy of the tree's former derive-colors.
(define (derived-as-today palette)
  (define (ref k) (plist-ref palette k #f))
  (define (unless-given p)
    (cond [(null? p) '()]
          [(ref (car p)) (unless-given (cddr p))]
          [else (cons* (car p) (cadr p) (unless-given (cddr p)))]))
  (append palette
          (unless-given
           (list 'selection (mix (ref 'accent) (ref 'bg-1) 0.65)
                 'panel-text (ref 'text) 'panel-dim (ref 'text-faint)
                 'panel-hover (ref 'bg-3) 'window-bg (ref 'bg-1)
                 'window-border (mix (ref 'bg-3) (ref 'text) 0.08)
                 'window-border-focus (mix (ref 'bg-3) (ref 'accent) 0.45)
                 'title-bg (ref 'bg-2) 'title-bg-focus (ref 'bg-3)
                 'title-text (ref 'text) 'title-text-dim (ref 'text-faint)
                 'button-close (ref 'red) 'button-min (ref 'yellow)
                 'button-max (ref 'green)
                 'button-idle (mix (ref 'bg-3) (ref 'text) 0.15)))))

(check (format "every palette resolves to its colors derived as today's \
                tree derived them (~a)" (palettes))
       (for-all (lambda (name)
                  (let* ([given (let ([p (palette-colors name)])
                                  (if (null? p) base-colors p))]
                         [today (derived-as-today given)]
                         [now (theme-palette-preview name)])
                    (for-all (lambda (k)
                               (equal? (plist-ref now k #f)
                                       (plist-ref today k #f)))
                             palette-keys)))
                (palettes)))

;;; fonts and sizes as settings

(check "a font is a setting: two themes asking for one font share its \
        record, and a font changed and back is the very one"
       (let ([ui (theme 'ui)]
             [other (with-style 'windows (lambda () (theme 'ui)))])
         (set-theme! 'ui-font-size 15)
         (let ([bigger (theme 'ui)])
           (reset-style! 'ui-font-size)
           (and (eq? ui other) (eq? ui (theme 'ui))
                (= 15 (font-size bigger)) (eq? (theme 'title) (theme 'ui-bold))
                (eq? (get-font 'ui) ui)))))

(check "a text's layout stays across a color change, and goes with a font \
        change"
       (let* ([ui (make-ui)]
              [lay (lambda ()
                     (ui-text-layout ui 'probe "some words to wrap here" 120
                                     'ui #t))]
              [a (lay)])
         (set-theme! 'accent #x123456)
         (let ([b (lay)])
           (set-theme! 'ui-font-size 15)
           (let ([c (lay)])
             (reset-style! 'accent 'ui-font-size)
             (and (eq? a b) (not (eq? b c)))))))

(check "a title's or bar's height: the setting grown to its text's need, 0 \
        none, and a style's own pixels where it fixes it"
       (with-test-styles
        (lambda ()
          (set-theme! 'title-height 10)
          (set-theme! 'taskbar-height 0)
          (let ([mac (list (title-height) (taskbar-height)
                           (theme 'title-height-min))])
            (reset-style! 'title-height 'taskbar-height)
            (define-style test-fixed "Test" 'options '(palette)
              'title-height 12)
            (set-style! 'test-fixed)
            (override! 'title-height 40)
            (let ([fixed (list (title-height) (theme 'fixed))])
              (override! 'title-height)
              (and (equal? (cdr mac) (list 0 (car mac))) (> (car mac) 10)
                   (= (car fixed) 12) (memq 'title-height (cadr fixed))
                   #t))))))

(check "at a REPL, a theme change prints nothing, and a font prints what \
        makes it, not its caches"
       (let ([font-text (format "~s" (theme 'mono))])
         (and (eq? (set-theme! 'accent (theme 'accent)) (void))
              (eq? (override! 'ui-font-size) (void))
              (string-prefix? "#<font \"" font-text)
              (< (string-length font-text) 60)
              (string-prefix? "#<font-file \""
                              (format "~s" (font-ready (theme 'mono)))))))
