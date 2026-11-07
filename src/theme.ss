;;; theme.ss — how everything looks, as live data: each setting from the
;;; first layer that has it (your Overrides, your changes to the chosen
;;; style, the style, its palette, the built-in defaults), resolved into
;;; one table that (theme key) reads.
;;;
;;; (theme 'accent)                 => #x7aa2f7
;;; (set-style! 'genera)            the one switch: frames, palette, ...
;;; (set-theme! 'accent #xff9e64)   your change, remembered for this style
;;; (override! 'ui-font-size 15)    on top of every style that honors it
;;;
;;; A rule is a setting computed from others when the table is built:
;;; 'selection (theme-rule (mix 'accent 'bg-1 0.65)). A part is a setting
;;; whose value is a procedure or its name: 'frame-under 'mac-draw-under.
;;; Anywhere a color is expected you may pass a theme key symbol instead.

(defvar *theme* (make-eq-hashtable))   ; every setting in effect
;; the chosen style's: *theme* is another while a window of another style,
;; a preview or a place is drawn, or a window's handler runs
(defvar *main-theme* *theme*)
(defvar *theme-version* 0)
;; Keeps a change to the layers: void, or what services/theme-file.ss sets
;; (the file saved soon after).
(defvar *theme-saver* void)

(defvar *style-name* 'mac)   ; the chosen style's name
;; ((style key value ...) ...): yours, per style
(defvar *style-changes* '())
(defvar *theme-overrides* '())   ; (key value ...): on top of every style
(defvar *scale-setting* 0)   ; the display's, in percent; 0 follows it

;; A setting computed from others when the theme is built.
(define-record-type (theme-rule-box make-theme-rule theme-rule?)
  (nongenerative schevana-rule-1)
  (fields thunk))
(define-syntax theme-rule
  (syntax-rules () [(_ e) (make-theme-rule (lambda () e))]))

(define theme-unset (list 'unset))
(define theme-busy (list 'busy))

;; The built-in defaults, the bottom layer: Tokyo Night's colors, the
;; rest derived from them as every palette's are, and the metrics.
(define base-colors
  '(bg-0 #x13141c
    bg-1 #x1a1b26
    bg-2 #x1f2335
    bg-3 #x292e42
    text #xc0caf5
    text-dim #x9aa5ce
    text-faint #x565f89
    accent #x7aa2f7
    accent-2 #xbb9af7
    red #xf7768e
    orange #xff9e64
    yellow #xe0af68
    green #x9ece6a
    cyan #x7dcfff
    teal #x73daca
    magenta #xc678dd
    desktop-top #x1b1d2e
    desktop-bottom #x2b2140
    watermark #xffffff
    panel #x111219))

;; (a palette may give any of these itself)
(define derived-colors
  (let ([same (lambda (k) (theme-rule (theme k)))])
    (list 'selection (theme-rule (mix 'accent 'bg-1 0.65))
          'panel-text (same 'text)
          'panel-dim (same 'text-faint)
          'panel-hover (same 'bg-3)
          'window-bg (same 'bg-1)
          'window-border (theme-rule (mix 'bg-3 'text 0.08))
          'window-border-focus (theme-rule (mix 'bg-3 'accent 0.45))
          'title-bg (same 'bg-2)
          'title-bg-focus (same 'bg-3)
          'title-text (same 'text)
          'title-text-dim (same 'text-faint)
          'button-close (same 'red)
          'button-min (same 'yellow)
          'button-max (same 'green)
          'button-idle (theme-rule (mix 'bg-3 'text 0.15)))))

;; What the rest of the world adds as it loads (theme-default!): the
;; fonts, the frame's parts, the kits' and the desktop layer's; kept
;; across a reload until they add it again.
(defvar *added-defaults* '())

(define default-theme
  (append base-colors derived-colors
          '(title-height 30
            corner-radius 9
            topbar-height 28
            taskbar-height 38
            shadow 14
            pacer-margin 300
            present-mode vsync
            ui-font "sans-serif"
            ui-font-size 13
            mono-font "monospace"
            mono-font-size 14
            palette tokyo-night
            ;; a wallpaper's name: gradient, flat or shade
            wallpaper gradient
            ;; the behaviors a style chooses: today's feel
            frame-edge 5
            frame-corner 14
            title-double-click maximize
            button-double-click ()
            title-wheel none
            drag-feedback live
            raise-on-click #t
            ;; a dialog stays above the window that waits on it
            modal-above #t)
          *added-defaults*))

(define color-keys
  (append (plist-keys base-colors) (plist-keys derived-colors)))

;; The look's knobs, (key "Label" . kind): a style honors those its
;; 'options list (none: all); one it does not list holds its own value
;; whatever you change. Pixels: lo hi, and the key of the text's least.
(define common-options
  '((palette "Palette" palette)
    (accent "Accent" color)
    (wallpaper "Wallpaper" wallpaper)
    (ui-font "Typeface" typeface)
    (ui-font-size "Text size" 9 36)
    (mono-font "Code typeface" typeface)
    (mono-font-size "Code size" 9 36)
    (corner-radius "Corner radius" 0 20)
    (title-height "Title bar" 22 44 title-height-min)
    (shadow "Window shadow" 0 32)
    (topbar-height "Top bar" 22 40 topbar-height-min)
    (taskbar-height "Taskbar" 28 56 taskbar-height-min)))

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

;; The built-in value of key (a rule as it is).
(define (theme-default key) (plist-ref default-theme key #f))

(define (theme-keys)
  (vector->list
   (vector-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
                (hashtable-keys *theme*))))

;;; ------------------------------------------------------------------
;;; palettes
;;; A palette is named colors, a layer under the styles. Each is a file in
;;; palettes/; the setting 'palette names the one in use:
;;;
;;;   (define-palette nord "Nord" '(bg-0 #x242933 ... panel #x1f232b))

;; ((name title plist) ...) in registration order
(defvar *palettes* '())

(define (register-palette! name title plist)
  (set! *palettes* (registry-add *palettes* (list name title plist) car))
  (theme-changed!))

;; (define-palette name "Title" plist) adds a palette, or replaces the one
;; of that name. Its plist gives colors (and may give derived ones).
(define-syntax define-palette
  (syntax-rules ()
    [(_ name title) (register-palette! 'name title '())]
    [(_ name title plist) (register-palette! 'name title plist)]))

(define (palettes) (map car *palettes*))

(define (palette-title name)
  (let ([p (assq name *palettes*)]) (if p (cadr p) (symbol->string name))))

;; (a world from before keeps #f for a palette of no colors until its
;; files register again)
(define (palette-colors name)
  (let ([p (assq name *palettes*)]) (or (and p (caddr p)) '())))

;;; ------------------------------------------------------------------
;;; styles
;;; A style is a name, a title and settings: theme keys, and 'parent (a
;;; style's name: it inherits that style's settings), 'options (the
;;; common options it honors and its own) and 'places. Each is a file in
;;; styles/:
;;;
;;;   (define-style flat-mac "Flat Mac" 'parent 'mac 'corner-radius 0)

(define-record-type style
  (nongenerative schevana-style-1)
  (fields name title settings))

(defvar *styles* '())   ; in registration order

(define (register-style! name title settings)
  (set! *styles* (registry-add *styles* (make-style name title settings)
                               style-name))
  (theme-changed!)
  name)

;; (define-style name "Title" key value ...) adds a style, or replaces the
;; one of that name; the next frame shows it, in every style under it.
(define-syntax define-style
  (syntax-rules ()
    [(_ name title setting ...)
     (register-style! 'name title (list setting ...))]))

(define (find-style name)
  (find (lambda (s) (eq? (style-name s) name)) *styles*))

(define (styles) (map style-name *styles*))

(define (current-style) *style-name*)

;;; ------------------------------------------------------------------
;;; parts

;; The procedure the theme gives for key: a procedure, or the name of a
;; top-level one, looked up at each call, so a redefinition shows on the
;; next frame.
(define (theme-part key)
  (let ([v (theme key)])
    (if (symbol? v) (top-level-value v *world-env*) v)))

;; (define-part (name formal ...) body ...) defines name* as the body (the
;; built-in) and name as a call to the theme's part for the key name,
;; whose built-in setting is name*; a style replaces it by setting the key.
(define-syntax define-part
  (lambda (x)
    (define (star k name)
      (datum->syntax k (string->symbol (format "~a*" (syntax->datum name)))))
    (syntax-case x ()
      [(k (name formal ...) body ...)
       (with-syntax ([built-in (star #'k #'name)])
         #'(begin
             (define (built-in formal ...) body ...)
             (define (name formal ...) ((theme-part 'name) formal ...))
             (theme-default! 'name 'built-in)))]
      [(k (name formal ... . rest) body ...)
       (with-syntax ([built-in (star #'k #'name)])
         #'(begin
             (define (built-in formal ... . rest) body ...)
             (define (name formal ... . rest)
               (apply (theme-part 'name) formal ... rest))
             (theme-default! 'name 'built-in)))])))

;; A built-in color setting: a change of colors alone changes no chrome.
(define (color-default! key value)
  (unless (memq key color-keys) (set! color-keys (cons key color-keys)))
  (theme-default! key value))

;; A built-in setting, under every layer: kits and the desktop layer give
;; their parts and sizes so as they load.
(define (theme-default! key value)
  (set! *added-defaults* (cons* key value (plist-remove *added-defaults* key)))
  (set! default-theme (cons* key value (plist-remove default-theme key)))
  (unless (hashtable-contains? *theme* key) (hashtable-set! *theme* key value))
  (hashtable-clear! *style-themes*))

;;; ------------------------------------------------------------------
;;; another style's theme

;; Themes of other styles, of styles with a preview's settings, and inside
;; containers, built once per change.
(define *style-themes* (make-hashtable equal-hash equal?))

;; The theme of style name with your changes to it and the Overrides,
;; extra (key value ...) over all, inside the container place (#f: none).
(define (style-theme name place . extra)
  (let ([k (list* name place extra)])
    (or (hashtable-ref *style-themes* k #f)
        (let ([t (resolve-theme name *theme-overrides* (style-changes-of name)
                                place extra)])
          (hashtable-set! *style-themes* k t)
          t))))

;; (with-style 'genera thunk) draws in another style; (with-style
;; (current-style) thunk 'palette 'nord), in this one with a palette.
(define (with-style name thunk . extra)
  (fluid-let ([*theme* (apply style-theme name #f extra)]) (thunk)))

;; Draws thunk inside a container: a dialog, a field, a list, a tooltip,
;; a menu, a bar or a toast. A style colors what sits there by
;; its settings for that place: 'places ((dialog key value ...) ...).
(define (with-place place thunk)
  (if (assq place (theme 'places))
      (fluid-let ([*theme* (apply style-theme (theme 'window-style) place
                                  (theme 'theme-extra))])
        (thunk))
      (thunk)))

;;; ------------------------------------------------------------------
;;; the layers

(define (style-changes-of name)
  (let ([p (assq name *style-changes*)]) (if p (cdr p) '())))

(define (plist-has? p key)
  (and (pair? p) (pair? (cdr p))
       (or (eq? (car p) key) (plist-has? (cddr p) key))))

(define (plist-remove p key)
  (cond [(or (null? p) (null? (cdr p))) '()]
        [(eq? (car p) key) (plist-remove (cddr p) key)]
        [else (cons* (car p) (cadr p) (plist-remove (cddr p) key))]))

;; The style and its parents, nearest first; a loop or a missing parent
;; ends the chain (the built-in defaults are under every chain).
(define (style-chain name)
  (let loop ([n name] [seen '()])
    (let ([s (and (not (memq n seen)) (find-style n))])
      (if s
          (cons s (loop (plist-ref (style-settings s) 'parent #f)
                        (cons n seen)))
          '()))))

;; The nearest style setting of key in the chain.
(define (chain-ref chain key default)
  (let ([s (find (lambda (s) (plist-has? (style-settings s) key)) chain)])
    (if s (plist-ref (style-settings s) key default) default)))

(define meta-keys '(parent options places))

(define (honored? chain key)
  (or (not (assq key common-options))
      (let ([os (chain-ref chain 'options #f)])
        (or (not os)
            (exists (lambda (o) (eq? key (if (pair? o) (car o) o))) os)))))

;; Sets each key of p that ok? takes and t does not have yet.
(define (plist-into! t p ok?)
  (let loop ([p p])
    (when (and (pair? p) (pair? (cdr p)))
      (unless (or (hashtable-contains? t (car p)) (not (ok? (car p))))
        (hashtable-set! t (car p) (cadr p)))
      (loop (cddr p)))))

;; The theme of style name with these Overrides and changes: each setting
;; from the first layer that has it, the palette's colors under the
;; styles; at: inside a container place, and a preview's extra settings
;; over all. Its rules are computed when read (theme-changed! reads them
;; all, so that a broken one fails at the change that broke it).
(define (resolve-theme name overrides changes . at)   ; at: [place [extra]]
  (let* ([chain (style-chain name)] [t (make-eq-hashtable)]
         [places (chain-ref chain 'places '())]
         [place (and (pair? at) (car at))]
         [extra (if (and (pair? at) (pair? (cdr at))) (cadr at) '())])
    (define (all k) #t)
    (hashtable-set! t 'window-style name)
    (hashtable-set! t 'scale *scale-setting*)
    ;; the common options it does not honor
    (hashtable-set! t 'fixed (remp (lambda (k) (honored? chain k))
                                   (map car common-options)))
    (hashtable-set! t 'places places)
    (hashtable-set! t 'theme-extra extra)
    (plist-into! t extra all)
    (plist-into! t overrides (lambda (k) (honored? chain k)))
    (plist-into! t changes (lambda (k) (honored? chain k)))
    ;; inside a container, the style's settings for it (with-place)
    (let ([p (assq place places)])
      (when p (plist-into! t (cdr p) all)))
    (for-each (lambda (s) (plist-into! t (style-settings s)
                                       (lambda (k) (not (memq k meta-keys)))))
              chain)
    (plist-into! t (list 'palette (theme-default 'palette)) all)
    (plist-into! t (palette-colors (hashtable-ref t 'palette #f)) all)
    (plist-into! t default-theme all)
    t))

(define (compute-rules! t)
  (fluid-let ([*theme* t]) (vector-for-each theme (hashtable-keys t))))

;; Whatever changed: build the theme again, then tell who cares: a change
;; not only of colors changes the chrome.
(define (theme-changed!)
  (let* ([old *main-theme*]
         [new (resolve-theme *style-name* *theme-overrides*
                             (style-changes-of *style-name*))]
         [changed? (lambda (k)
                     (not (equal? (hashtable-ref old k theme-unset)
                                  (hashtable-ref new k theme-unset))))])
    (compute-rules! new)
    (set! *main-theme* new)
    (set! *theme* new)
    (hashtable-clear! *style-themes*)
    (set! *theme-version* (+ *theme-version* 1))
    (when (changed? 'scale) (host-rescale!))
    (unless (for-all (lambda (k) (or (memq k color-keys) (not (changed? k))))
                     (append (vector->list (hashtable-keys old))
                             (vector->list (hashtable-keys new))))
      (wm-chrome-changed!))
    (invalidate!)))

;;; ------------------------------------------------------------------
;;; the frame
;;; The frame around each window's content: parts of the style that the
;;; window manager calls with the window, in its theme.
;;;
;;;   frame-insets   (win) -> (values left top right bottom), its thickness
;;;   frame-regions  (win) -> ((kind x y w h) ...) in window coordinates:
;;;                  close, minimize, maximize and depth (send to back /
;;;                  bring to front) act on release, menu (the window
;;;                  menu) on press; title is a drag handle (Genera's
;;;                  label sits at the bottom); resize-l, -r, -t, -b and
;;;                  the corners -tl, -tr, -bl, -br start a resize; the
;;;                  pointer in a scrollbar region is the app's, as in
;;;                  the content (an outside scroll bar, ui-frame-scrollbar)
;;;   frame-radius   (win) -> its corners' radius
;;;   frame-bleed    (win) -> how far, in logical pixels, it draws past
;;;                  its frame (a glow, say): a window is drawn clipped to
;;;                  its extent (window-extent in wm.ss), its frame and at
;;;                  least that bleed, and only that much is drawn again
;;;                  when it changes
;;;   frame-under, frame-over   (win x y w h focused? hover pressed) draw
;;;                  it before the content and after; hover is the region
;;;                  under the mouse, pressed the drag in progress
;;;
;;; A style gives the procedures by name. Each style is a file in styles/;
;;; add your own there, in ~/.schevana.d/styles/, or from the REPL:
;;;
;;;   (define (bare-under win x y w h focused? hover pressed)
;;;     (fill-box x y w (title-height) (if focused? 'accent 'bg-3)))
;;;   (define-style bare "Bare" 'frame-under 'bare-under)
;;;   (set-style! 'bare)
;;;   (open-window "Odd one out" 'window-style 'windows)   ; one window's

;; The plain frame, what a style leaves out: a title bar's height on top,
;; and nothing drawn.
(define (frame-insets* win) (values 0 (title-height) 0 0))
(define (frame-regions* win) '())
(define (frame-radius* win) 0)
(define (frame-bleed* win) 0)
(define (frame-under* win x y w h focused? hover pressed) (void))
(define (frame-over* win x y w h focused? hover pressed) (void))

(for-each theme-default!
          '(frame-insets frame-regions frame-radius frame-bleed frame-under
            frame-over)
          '(frame-insets* frame-regions* frame-radius* frame-bleed*
            frame-under* frame-over*))

;;; ------------------------------------------------------------------
;;; changing settings

;; Changes the layers by thunk and builds the theme again; if that fails
;; (a broken rule, a bad value), the layers are as they were, and so is
;; the theme (a failure after the new table took over, in fonts, say).
(define (change-layers! thunk)
  (let ([s *style-name*] [c *style-changes*] [o *theme-overrides*]
        [sc *scale-setting*])
    (guard (e [#t (set! *style-name* s) (set! *style-changes* c)
                  (set! *theme-overrides* o) (set! *scale-setting* sc)
                  (guard (again [#t #f]) (theme-changed!))
                  (raise e)])
      (thunk)
      (theme-changed!))))

;; The layers at once, as a saved look gives them (services/theme-file.ss).
(define (theme-layers-set! style overrides changes scale)
  (set! *style-name* style)
  (set! *theme-overrides* overrides)
  (set! *style-changes* changes)
  (set! *scale-setting* scale))

(define (set-changes! name plist)
  (set! *style-changes* (let ([rest (remp (lambda (c) (eq? (car c) name))
                                    *style-changes*)])
                    (if (null? plist) rest (cons (cons name plist) rest)))))

;; The one switch: frames, palette, everything you changed for it.
(define (set-style! name)
  (unless (find-style name) (errorf 'set-style! "no style ~s" name))
  (change-layers! (lambda () (set! *style-name* name)))
  (*theme-saver*))

;; Your change to the chosen style, remembered for it. window-style
;; chooses a style, scale the display's scale.
(define (set-theme! key value)
  (case key
    [(window-style) (set-style! value)]
    [(scale) (set-scale! value)]
    [else
     (change-layers!
      (lambda ()
        (set-changes! *style-name*
                      (cons* key value (plist-remove
                                        (style-changes-of *style-name*) key)))))
     (*theme-saver*)]))

;; Forgets your changes to the chosen style: those keys, or all.
(define (reset-style! . keys)
  (change-layers!
   (lambda ()
     (set-changes! *style-name*
                   (if (null? keys)
                       '()
                       (fold-left plist-remove (style-changes-of *style-name*)
                                  keys)))))
  (*theme-saver*))

;; (override! key value) holds in every style that honors key;
;; (override! key) clears it. The style and the scale are not a style's.
(define (override! key . value)
  (when (memq key '(window-style scale))
    (errorf 'override! "~s is not a style's setting" key))
  (change-layers!
   (lambda ()
     (set! *theme-overrides*
       (let ([rest (plist-remove *theme-overrides* key)])
         (if (pair? value) (cons* key (car value) rest) rest)))))
  (*theme-saver*))

(define (theme-overrides) *theme-overrides*)

;; The display's scale in percent, 0 to follow the desktop: not a style's.
(define (set-scale! pct)
  (change-layers! (lambda () (set! *scale-setting* pct)))
  (*theme-saver*))

;; Old names, kept.
(define (set-theme-plist! plist)
  (for-each (lambda (k) (set-theme! k (plist-ref plist k #f)))
            (plist-keys plist)))

(define (set-palette! name)
  (unless (assq name *palettes*)
    (errorf 'set-palette! "no theme ~s" name))
  (set-theme! 'palette name))

(define (set-accent! color) (set-theme! 'accent color))

;; Every style's changes and the Overrides go.
(define (reset-theme!)
  (change-layers!
   (lambda () (set! *style-changes* '()) (set! *theme-overrides* '())))
  (*theme-saver*))

;; The theme until its first change, its rules computed when read (no
;; color can be mixed before gfx.ss loads).
(set! *theme* (resolve-theme *style-name* *theme-overrides*
                             (style-changes-of *style-name*)))
(set! *main-theme* *theme*)
