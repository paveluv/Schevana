;;; (schevana apps settings) — the look of the world: pick a style, then change
;;; what it lets you.
;;;
;;; A style is the one switch: frames, bars, widgets, palette, wallpaper,
;;; fonts and what you changed for it. Every row is a theme setting (see
;;; (schevana core theme)), so the REPL does the same: (set-style! 'genera),
;;; (set-theme! 'accent #xff9e64) for the chosen style, (override!
;;; 'ui-font-size 15) for every style that honors it, (reset-style!),
;;; (save-style-as! 'my-genera "My Genera"). Changes apply live and are
;;; saved to *theme-file-path* (~/.schevana-theme.ss). Settings draws with the
;;; widget kit, so it is drawn in the chosen style too; its own pictures
;;; (the styles' miniatures, swatches, color tracks) are its
;;; settings-draw-… procedures.

(library (schevana apps settings)
  (export
    settings-tabs settings-present-choices settings-scale-choices
    settings-text-keys settings-group-of settings-options-in settings-behaviors
    settings-typefaces settings-st make-settings-st settings-st?
    settings-st-tab settings-st-tab-set! settings-st-key settings-st-key-set!
    settings-st-scroll settings-st-scroll-set! settings-st-hex
    settings-st-hex-set! settings-st-hsl settings-st-hsl-set!
    settings-st-pane-scroll settings-st-pane-scroll-set! settings-own-options
    settings-option settings-owner-option settings-key-label settings-applies?
    settings-style-title settings-pinned? settings-changed? settings-set!
    settings-pin! settings-source-words settings-choice-label
    settings-choice-value settings-hex-digits settings-wallpaper-title
    settings-value-words *settings-style-directory* settings-style-name
    settings-make-directory! settings-datum save-style-as!
    settings-sidebar-width settings-color-row-height settings-color-list-width
    settings-hsl-label-width settings-hsl-readout-width settings-hex-width
    settings-marks-width settings-color-editor-width settings-natural-width
    settings-natural-height settings-label-width settings-readout-width
    settings-card-label-height settings-card-width settings-card-height
    settings-pane-height settings-shown? settings-card-grid settings-heading
    settings-section settings-row settings-revert settings-marks
    settings-control-height settings-choice settings-control settings-row-label
    settings-option-row settings-unused-row settings-group settings-draw-card
    draw-style-preview settings-draw-preview-content settings-press-focus!
    settings-style-card settings-palettes settings-draw-swatch settings-accent
    settings-style-bar settings-save-row settings-theme-tab
    settings-override-words settings-overrides settings-color-rows
    settings-draw-steps settings-draw-color-row settings-draw-big-swatch
    settings-colors settings-parse-hex settings-color-editor
    settings-draw-font-sample settings-fonts settings-display
    settings-paths settings-layer-rank
    settings-path-facts
    settings-library-file settings-search-row settings-path-choose
    settings-path-added! settings-sidebar
    settings-pane-scrollbar
    settings-reveal! settings-draw settings-key settings-wheel settings)
  (import (chezscheme)
          (only (schevana base) at-load clamp define-made define-state
                filter-map library-layer library-layer-names list-index
                plist-keys plist-ref
                string-join string-prefix? string-split)
          (only (schevana core) *gpu-facts* *styles* *wallpapers*
                *world-env* *auto-loads* *schevana-root* add-library-directory!
                auto-load! auto-load-entries auto-load-forget! auto-loads
                library-file-layer path-full alpha app chain-ref close-window!
                color-default! color-keys color-rgba common-options
                current-style current-window define-app detached-window
                draw-text draw-window* fill-box fill-circle fill-wallpaper
                find-style find-window focus-window! font-char-width
                font-line-height fullscreen? invalidate! load-file! open-window
                override! palette-title palettes plist-has? reset-style!
                reset-theme! rgb set-fullscreen! set-scale! set-style!
                set-theme! stroke-box stroke-circle style style-chain
                style-changes-of style-name style-settings style-title styles
                system-scale-percent text-width theme theme-default
                theme-default! theme-overrides theme-rule user-directory
                window-h-set! window-hover window-ref window-w-set!
                window-x-set! window-y-set! with-clip with-scale with-style
                with-translation)
          (only (schevana kits color) color-from-hsl color->hsl color->fixnum)
          (only (schevana kits text) text-fit text-widest)
          (only (schevana kits theme) theme-palette-preview theme-source)
          (only (schevana kits transcript) transcript-draw-line
                transcript-fill-colors! transcript-draw-scheme
                transcript-line-height)
          (only (schevana kits ui) ui-handlers make-ui ui-state-my ui-state-mx
                ui-region-in? ui-wheel ui-end! ui-scrollbar-inset ui-begin!
                ui-region-frame ui-state-reveal-set! ui-find ui-state-reveal
                ui-scrollbar ui-scrollbar-width ui-nav ui-checkbox ui-gap
                ui-focused ui-hover? ui-area ui-draw-surface
                ui-draw-highlight-over ui-draw-highlight ui-text-field
                ui-dialog ui-memo! ui-memo ui-button-size ui-flags
                ui-pressable! ui-focus! ui-active? ui-draw-field
                ui-draw-checkbox ui-draw-button ui-draw-focus ui-draw-card
                ui-card-radius
                ui-label-size ui-toggle ui-slider ui-dropdown ui-segmented
                ui-slider-height ui-button ui-region! ui-draw-label
                ui-control-height ui-rows ui-switch-row)
          (only (schevana desktop file-dialog) open-file-dialog)
          (only (schevana services theme-file) theme-file-plain?
                theme-file-hex))

  (library-layer apps)

  (define settings-tabs
    '((theme . "Theme") (colors . "Colors") (fonts . "Fonts")
      (display . "Display") (paths . "Paths")))

  ;; How frames reach the screen, those the window offers shown.
  (define settings-present-choices '(("VSync" . vsync) ("Mailbox" . mailbox)))

  ;; Percentages for the display's scale; 0 follows the desktop.
  (define settings-scale-choices
    '(("Auto" . 0) ("100%" . 100) ("125%" . 125) ("150%" . 150) ("175%" . 175)
      ("200%" . 200) ("250%" . 250) ("300%" . 300)))

  ;; The colors the Colors tab lists, by group, and those the accent's
  ;; swatches offer: settings, so a style may group its own (CDE its slots).
  (at-load
   (theme-default! 'color-groups
     '(("BASE" bg-0 bg-1 bg-2 bg-3 text text-dim text-faint)
       ("ACCENTS" accent accent-2 red orange yellow green cyan teal magenta
                  selection)
       ("DESKTOP" desktop-top desktop-bottom watermark)
       ("PANELS" panel panel-text panel-dim panel-hover)
       ("WINDOWS" window-bg window-border window-border-focus title-bg
                  title-bg-focus title-text title-text-dim button-close
                  button-min
                  button-max button-idle))))
  (at-load
   (theme-default! 'accent-choices
     '(accent cyan teal green yellow orange red magenta accent-2)))

  ;; The common options ((schevana core theme)) by group: Colors (a palette or a
  ;; color), Desktop (a wallpaper), Text (on the Fonts tab) and Shape, the
  ;; rest: the sizes.
  (define settings-text-keys '(ui-font ui-font-size mono-font mono-font-size))

  (define (settings-group-of o)
    (cond [(memq (caddr o) '(palette color)) "Colors"]
          [(eq? (caddr o) 'wallpaper) "Desktop"]
          [(memq (car o) settings-text-keys) "Text"]
          [else "Shape"]))

  (define (settings-options-in group)
    (filter (lambda (o) (string=? (settings-group-of o) group)) common-options))

  ;; The behaviors, (key "Label" . kind) as common-options: shared code does
  ;; each whatever a style draws, so every style honors them; a style gives
  ;; its own defaults, and a pin holds yours in every style.
  (define settings-behaviors
    '((title-double-click "Double-click on a title"
       (("Maximize" . maximize) ("Shade" . shade) ("Nothing" . none)))
      (title-wheel "Wheel on a title" (("Nothing" . none) ("Shade" . shade)))
      (drag-feedback "Moving and resizing"
       (("Live" . live) ("Outline" . outline)))
      (raise-on-click "Raise a window when clicked" bool)
      (bell "The bell"
       (("Silent" . none) ("Screen" . screen) ("Window" . window)))
      (menu-choose "Choose from a menu"
       (("Click" . click) ("Release" . release)))
      (menu-blink "Blink a chosen entry"
       (("No" . 0) ("Once" . 1) ("Twice" . 2) ("3 times" . 3)))
      (menu-hover "Entry under the pointer"
       (("Fill" . fill) ("Outline" . outline)))
      (mouse-doc "Show what the mouse buttons do" bool)
      (scrollbar-show "Scroll bars" (("Always" . always) ("On hover" . hover)))
      (scrollbar-side "Scroll bar side"
       (("Right" . right) ("Left" . left) ("Outside" . outside)))))

  (define settings-typefaces
    '(("Sans" . "sans-serif") ("Serif" . "serif") ("Mono" . "monospace")))

  (define-record-type settings-st
    (nongenerative schevana-settings-2)
    (fields (mutable tab)
            (mutable key)       ; color being edited
            (mutable scroll)    ; color list scroll offset
            (mutable hex)       ; hex digits being typed, or #f
            ;; #(key rgb h s l): keeps hue stable at zero saturation
            (mutable hsl)
            (mutable pane-scroll)))

  ;;; ------------------------------------------------------------------
  ;;; options and how they are changed

  ;; The chosen style's own options, (key "Label" . kind), from its chain.
  (define (settings-own-options)
    (filter pair? (or (chain-ref (style-chain (current-style)) 'options #f)
                      '())))

  ;; key's descriptor: a common option, a behavior, or one of the chosen
  ;; style's own; #f for another setting (a color).
  (define (settings-option key)
    (or (assq key common-options) (assq key settings-behaviors)
        (assq key (settings-own-options))))

  ;; The style that declares key as an option of its own: (name . o).
  (define (settings-owner-option key)
    (exists (lambda (s)
              (let ([o (assq key (filter pair? (plist-ref (style-settings s)
                                                          'options '())))])
                (and o (cons (style-name s) o))))
            *styles*))

  ;; key's label; another style's own option says whose it is.
  (define (settings-key-label key)
    (let ([o (settings-option key)] [owner (settings-owner-option key)])
      (cond [o (cadr o)]
            [owner (format "~a (~a)" (cadr (cdr owner))
                           (settings-style-title (car owner)))]
            [else (symbol->string key)])))

  ;; Does key's setting apply in the chosen style: not a common option it
  ;; fixes, nor another style's own option?
  (define (settings-applies? key)
    (not (or (memq key (theme 'fixed))
             (and (not (settings-option key)) (settings-owner-option key)))))

  (define (settings-style-title name) (style-title (find-style name)))

  (define (settings-pinned? key) (plist-has? (theme-overrides) key))

  (define (settings-changed? key)
    (plist-has? (style-changes-of (current-style)) key))

  ;; Your change: to the Override while key is pinned, else to this style.
  (define (settings-set! key value)
    (if (settings-pinned? key) (override! key value) (set-theme! key value)))

  ;; Pinned, key's value holds in every style that honors it (an Override);
  ;; unpinned, it is your change to this style.
  (define (settings-pin! key on?)
    (let ([v (theme key)])
      (if on?
          (begin (reset-style! key) (override! key v))
          (begin (override! key)
                 (unless (equal? (theme key) v) (set-theme! key v))))))

  ;; Which layer gives key, in words: a label's tooltip.
  (define (settings-source-words key)
    (let ([s (theme-source key)])
      (case (and s (car s))
        [(overrides) "Your Override: it holds in every style that uses it."]
        [(changes)
         (format "Your change to ~a." (settings-style-title (cadr s)))]
        [(style) (format "~a gives this." (settings-style-title (cadr s)))]
        [(palette)
         (format "The ~a palette gives this." (palette-title (cadr s)))]
        [else "Built in."])))

  (define (settings-choice-label c) (if (pair? c) (car c) (format "~a" c)))
  (define (settings-choice-value c) (if (pair? c) (cdr c) c))

  ;; A color's six hex digits.
  (define (settings-hex-digits c)
    (substring (theme-file-hex (color->fixnum c)) 2 8))

  (define (settings-wallpaper-title name)
    (let ([wp (assq name *wallpapers*)]) (if wp (cadr wp) (format "~a" name))))

  ;; v, a value of key, in words.
  (define (settings-value-words key v)
    (let ([kind (let ([o (or (settings-option key)
                             (let ([own (settings-owner-option key)])
                               (and own (cdr own))))])
                  (and o (cddr o)))])
      (cond
        [(not kind) (if (fixnum? v) (string-append "#" (settings-hex-digits v))
                        (format "~s" v))]
        [(real? (car kind)) (format "~a px" v)]
        [(list? (car kind))
         (let ([c (find (lambda (c) (equal? (settings-choice-value c) v))
                        (car kind))])
           (if c (settings-choice-label c) (format "~a" v)))]
        [else (case (car kind)
                [(bool) (if v "On" "Off")]
                [(palette) (palette-title v)]
                [(wallpaper) (settings-wallpaper-title v)]
                [(color) (string-append "#" (settings-hex-digits v))]
                [else (let ([c (find (lambda (c) (equal? (cdr c) v))
                                     settings-typefaces)])
                        (if c (car c) (format "~a" v)))])])))

  ;;; ------------------------------------------------------------------
  ;;; saving a style

  ;; Where Save as new style writes: the user's styles folder, which loads
  ;; at every boot. The tests point it at their output folder.
  (define-state *settings-style-directory*
    (string-append user-directory "/styles"))

  ;; A new style's name from its title: "My Genera" -> my-genera, "1984"
  ;; -> style-1984 (a name must not read as a number); #f for none.
  (define (settings-style-name title)
    (let ([words (filter (lambda (s) (not (string=? s "")))
                         (string-split
                          (list->string
                           (map (lambda (c)
                                  (if (or (char-alphabetic? c)
                                          (char-numeric? c))
                                      (char-downcase c)
                                      #\-))
                                (string->list title)))
                          #\-))])
      (and (pair? words)
           (let ([s (string-join words "-")])
             (string->symbol (if (string->number s)
                                 (string-append "style-" s)
                                 s))))))

  (define (settings-make-directory! dir)
    (unless (or (string=? dir "") (file-directory? dir))
      (settings-make-directory! (path-parent dir))
      (mkdir dir)))

  ;; A setting's value as save-style-as! writes it: colors in hex, names and
  ;; lists quoted.
  (define (settings-datum key v)
    (cond [(and (memq key color-keys) (fixnum? v)) (theme-file-hex v)]
          [(or (symbol? v) (pair? v) (null? v)) (format "'~s" v)]
          [else (format "~s" v)]))

  ;; Your changes to the chosen style as a new style, a file that defines
  ;; it in *style-save-directory*: the chosen style its parent, your changes
  ;; that are data its settings (a procedure typed at the REPL is not
  ;; saved). It loads and is chosen, and the changes it took go from the
  ;; parent; the Overrides stay. => the file's path.
  (define (save-style-as! name title)
    (when (find-style name)
      (errorf 'save-style-as! "a style named ~s exists already" name))
    (let* ([parent (current-style)]
           [changes (style-changes-of parent)]
           [keys (filter (lambda (k)
                           (theme-file-plain? (plist-ref changes k #f)))
                         (plist-keys changes))]
           [path (format "~a/~a.ss" *settings-style-directory* name)])
      (settings-make-directory! *settings-style-directory*)
      (when (file-exists? path) (delete-file path))
      (call-with-output-file path
        (lambda (p)
          (fprintf p ";;; ~a.ss — saved by Settings: ~a with your changes.\n\
                      ;;; Plain define-style: edit it freely.\n\n\
                      (define-style ~s ~s\n  'parent '~s"
                   name (settings-style-title parent) name title parent)
          (for-each (lambda (k)
                      (fprintf p "\n  '~s ~a" k
                               (settings-datum k (plist-ref changes k #f))))
                    keys)
          (fprintf p ")\n")))
      (parameterize ([interaction-environment *world-env*]) (load-file! path))
      (unless (null? keys) (apply reset-style! keys))
      (set-style! name)
      path))

  ;;; ------------------------------------------------------------------
  ;;; sizes
  ;;; Sizes are worked out from the current fonts, so the layout still holds
  ;;; after the Fonts tab makes text bigger. Each is a max with the number it
  ;;; comes to at the default fonts. When the window is too small for what it
  ;;; shows, the right-hand pane scrolls and label columns stack.

  (define (settings-sidebar-width)
    (max 168
         (+ 40 (text-width "Settings" 'heading))
         (+ 48 (text-widest (map cdr settings-tabs) 'ui))
         (+ 56 (text-width "Reset to defaults" 'ui))))

  (define (settings-color-row-height)
    (max 26 (round (+ (font-line-height 'ui) 11))))

  (define (settings-color-list-width)
    (max 220 (+ 54 (text-widest (map symbol->string
                                     (filter symbol? (settings-color-rows)))
                                'ui))))

  ;; Color editor: label column, hex field and its marks.
  (define (settings-hsl-label-width)
    (max 96 (+ 24 (text-widest '("Hue" "Saturation" "Lightness") 'ui))))
  (define (settings-hsl-readout-width) (max 64 (+ 28 (text-width "100%" 'ui))))
  (define (settings-hex-width) (max 116 (+ 60 (text-width "000000" 'ui))))
  (define (settings-marks-width) (+ 12 (* 2 (ui-control-height))))
  (define (settings-color-editor-width)
    (+ (settings-hsl-label-width) (settings-hex-width) (settings-marks-width)))

  ;; The size a new Settings window opens at: wide enough for the Colors
  ;; tab beside its list, and tall enough for most tabs without scrolling.
  (define (settings-natural-width)
    (max 840 (+ (settings-sidebar-width) 28 (settings-color-list-width) 28
                (settings-color-editor-width) 28)))
  (define (settings-natural-height)
    (max 600 (* 30 (round (font-line-height 'ui)))))

  ;; Label column and readout of a slider row.
  (define (settings-label-width labels)
    (max 180 (+ 24 (text-widest labels 'ui))))
  (define (settings-readout-width) (max 60 (+ 24 (text-width "00 px" 'ui))))

  ;; Cards (styles, palettes) are wide enough for their labels, in whole
  ;; pixels (text measures in fractions).
  (define (settings-card-label-height)
    (max 28 (round (+ (font-line-height 'ui) 10))))
  (define (settings-card-width labels)
    (max 180 (+ 36 (exact (ceiling (text-widest labels 'ui))))))
  (define (settings-card-height) (+ 88 (settings-card-label-height)))

  ;; The pane's height while it is drawn: what lies outside it (cards,
  ;; mostly) is not drawn.
  (define-made settings-pane-height (make-parameter +inf.0))
  (define (settings-shown? y h)
    (and (< y (settings-pane-height)) (> (+ y h) 0)))

  ;; Lay cards out in a grid; place-card gets (item x y). Returns the y
  ;; below.
  (define (settings-card-grid items x y w cw ch place-card)
    (let* ([gap 12] [cols (max 1 (exact (floor (/ (+ w gap) (+ cw gap)))))])
      (let loop ([is items] [i 0])
        (unless (null? is)
          (place-card (car is) (+ x (* (mod i cols) (+ cw gap)))
                     (+ y (* (quotient i cols) (+ ch gap))))
          (loop (cdr is) (+ i 1))))
      (+ y (* (quotient (+ (length items) cols -1) cols) (+ ch gap)))))

  ;;; ------------------------------------------------------------------
  ;;; rows

  ;; Title and subtitle of a tab; returns the y where its content starts.
  (define (settings-heading x y w title subtitle)
    (let ([y (ui-draw-label x y w (font-line-height 'heading) '(heading)
                            title)])
      (+ 22 (ui-draw-label x (+ y 6) w 0 '(hint wrap) subtitle))))

  ;; A group's title, small capitals above its rows; => the y below.
  (define (settings-section x y w title)
    (+ 10 (ui-draw-label x (+ y 18) w (font-line-height 'ui-small) '(section)
                         title)))

  ;; A labeled row: the label in a column label-w wide, or on a line of its
  ;; own above the control when fewer than min-w pixels would be left for
  ;; it. tip, (id text), gives the label a tooltip. place-control gets (x y
  ;; w) for a control control-h tall, trailing-w pixels kept free after it.
  ;; Returns the y below the row.
  (define (settings-row ui x y w label-w label flags control-h min-w trailing-w
                        place-control . tip)
    (let* ([lh (round (font-line-height 'ui))]
           [inline? (>= (- w label-w trailing-w) min-w)]
           [row-h (if inline? (max control-h lh) lh)]
           [cy (if inline? (+ y (floor (/ (- row-h control-h) 2))) (+ y lh 6))])
      (ui-draw-label x y (if inline? (- label-w 12) w) row-h flags label)
      (when (pair? tip)
        (ui-region! ui (car tip) x y (if inline? (- label-w 12) w) row-h
                    'tip (cadr tip)))
      (place-control (if inline? (+ x label-w) x) cy
                    (- w (if inline? label-w 0) trailing-w))
      (if inline? (+ y row-h) (+ cy control-h))))

  ;; ↺ at x y while you changed key for this style: it drops the change.
  (define (settings-revert ui x y key)
    (when (settings-changed? key)
      (let ([h (ui-control-height)])
        (ui-button ui (list 'revert key) x y h h #f
                   (lambda () (reset-style! key))
                   'glyph 'undo 'quiet #t
                   'tip (format "Drop your change to ~a"
                                (settings-style-title (current-style)))))))

  ;; The marks after key's row at x y: ↺ while you changed it for this
  ;; style, and its pin, on while it is an Override.
  (define (settings-marks ui x y key)
    (let ([h (ui-control-height)] [pinned? (settings-pinned? key)])
      (settings-revert ui x y key)
      (ui-button ui (list 'pin key) (+ x h 4) y h h #f
                 (lambda () (settings-pin! key (not pinned?)))
                 'glyph 'pin 'quiet (not pinned?) 'selected pinned?
                 'tip (if pinned?
                          "Pinned: it holds in every style that uses it. \
                           Unpin to keep it for this style only."
                          "Pin it: hold it in every style that uses it"))))

  (define (settings-control-height kind)
    (if (real? (car kind)) (ui-slider-height) (ui-control-height)))

  ;; A choice of buttons, or a dropdown when they do not fit.
  (define (settings-choice ui id x y w choices current on-select)
    (let* ([cs (map (lambda (c)
                      (cons (settings-choice-label c)
                            (settings-choice-value c)))
                    choices)]
           [h (ui-control-height)]
           [sw (* (length cs) (+ 34 (text-widest (map car cs) 'ui)))])
      (if (<= sw w)
          (ui-segmented ui id x y sw h cs current on-select)
          (ui-dropdown ui id x y (min w (+ 60 (text-widest (map car cs) 'ui)))
                       h cs current on-select))))

  ;; Option o's control at x y, w wide: a slider (from the least the text
  ;; needs, where the option names it), a choice, a toggle, the wallpapers,
  ;; the typefaces.
  (define (settings-control ui x y w o)
    (let* ([key (car o)] [kind (cddr o)] [v (theme key)]
           [id (list 'option key)] [h (ui-control-height)]
           [set (lambda (nv) (unless (equal? nv (theme key))
                               (settings-set! key nv)))])
      (cond
        [(real? (car kind))
         (let* ([lo (if (pair? (cddr kind))
                        (max (car kind) (theme (caddr kind)))
                        (car kind))]
                [hi (if (pair? (cddr kind)) (max (cadr kind) (+ lo 10))
                        (cadr kind))]
                [shown (max v lo)] [rw (settings-readout-width)])
           (ui-slider ui id x y (- w rw) shown lo hi
                      (lambda (nv) (set (exact (round nv)))))
           (ui-draw-label (+ x (- w rw) 18) y (- rw 18) (ui-slider-height)
                          '(dim) (format "~a px" shown)))]
        [(list? (car kind)) (settings-choice ui id x y w (car kind) v set)]
        [else
         (case (car kind)
           [(bool) (ui-toggle ui id x y (min w 60) h #f v set)]
           [(wallpaper)
            (ui-dropdown ui id x y (min w 220) h
                         (map (lambda (wp) (cons (cadr wp) (car wp)))
                              *wallpapers*)
                         v set)]
           [(typeface) (settings-choice ui id x y w settings-typefaces v set)]
           [else (ui-draw-label x y w h '(dim)
                                (settings-value-words key v))])])))

  ;; Option o's label; a pinned row reads Override.
  (define (settings-row-label o)
    (if (settings-pinned? (car o)) (format "~a · Override" (cadr o)) (cadr o)))

  ;; A row for option o, (key "Label" . kind): its control, then its marks.
  ;; The label's tooltip says which layer gives the value. A palette's row
  ;; holds its cards, the accent's its swatches, under the label. => the y
  ;; below.
  (define (settings-option-row ui x y w label-w o)
    (let* ([key (car o)] [kind (cddr o)] [h (ui-control-height)]
           [mw (settings-marks-width)] [tip (settings-source-words key)])
      (if (memq (car kind) '(palette color))
          (begin
            (ui-draw-label x y (- w mw) h '(dim) (settings-row-label o))
            (ui-region! ui (list 'label key) x y (- w mw) h 'tip tip)
            (settings-marks ui (+ x w (- mw) 12) y key)
            ((if (eq? (car kind) 'palette) settings-palettes settings-accent)
             ui x (+ y h 8) w key))
          (let ([ch (settings-control-height kind)])
            (settings-row ui x y w label-w (settings-row-label o) '(dim) ch 120
                          mw
                          (lambda (cx cy cw)
                            (settings-control ui cx cy cw o)
                            (settings-marks ui (+ cx cw 12)
                                            (+ cy (/ (- ch h) 2)) key))
                          (list 'label key) tip)))))

  ;; A row for a common option the chosen style does not honor: dimmed,
  ;; what it holds, and, wrapped, whether your change to it (with its ↺) or
  ;; your Override is passed by here.
  (define (settings-unused-row ui x y w label-w key)
    (let* ([passed (lambda (whose v)
                     (format "; ~a (~a) does not apply" whose
                             (settings-value-words key v)))]
           [changed? (settings-changed? key)]
           [words (string-append
                   (format "~a sets this: ~a"
                           (settings-style-title (current-style))
                           (settings-value-words key (theme key)))
                   (if changed?
                       (passed "your change"
                               (plist-ref (style-changes-of (current-style)) key
                                          #f))
                       "")
                   (if (settings-pinned? key)
                       (passed "your Override"
                               (plist-ref (theme-overrides) key #f))
                       ""))]
           [trailing (if changed? (settings-marks-width) 0)]
           ;; the words' width as settings-row gives it, beside the label or
           ;; under it
           [ww (let ([beside (- w label-w trailing)])
                 (if (>= beside 120) beside w))]
           [rh (let-values ([(tw th) (ui-label-size '(hint wrap) words ww)])
                 (max th (if changed? (ui-control-height) 0)))])
      (settings-row ui x y w label-w (settings-key-label key) '(hint) rh 120
                    trailing
                    (lambda (cx cy cw)
                      (ui-draw-label cx cy cw 0 '(hint wrap) words)
                      (settings-revert ui (+ cx cw 12) cy key)))))

  ;; A group of option rows under its title; nothing when it has none.
  (define (settings-group ui x y w label-w title options)
    (if (null? options)
        y
        (fold-left (lambda (y o)
                     (+ 12 (settings-option-row ui x y w label-w o)))
                   (settings-section x y w title)
                   options)))

  ;;; ------------------------------------------------------------------
  ;;; the Theme tab

  ;; A card's picture: style's miniature (with extra settings) over all but
  ;; the label strip, which holds title, and a dot when changed?; the kit's
  ;; card outline.
  (define (settings-draw-card x y w h flags title changed? style . extra)
    (let ([lh (settings-card-label-height)])
      (with-clip (x y w h (ui-card-radius))
        (apply draw-style-preview style x y w (- h lh) extra)
        (fill-box x (- (+ y h) lh) w lh 'panel)
        (draw-text (+ x 12) (+ (- (+ y h) lh)
                               (/ (- lh (font-line-height 'ui)) 2))
                   (text-fit title (- w 34) 'ui) 'panel-text 'ui)
        (when changed?
          (fill-circle (- (+ x w) 15) (- (+ y h) (/ lh 2)) 3.5
                       'panel-accent)))
      (ui-draw-card x y w h flags)
      (when (memq 'focused flags)
        (ui-draw-focus x y w h flags (ui-card-radius)))))

  ;; A miniature of style name (extra: settings over it, a palette say) in
  ;; x y w h: its wallpaper and a focused window in its frame holding a
  ;; button, a checkbox and a field, all drawn by its parts at half size.
  (define (draw-style-preview name x y w h . extra)
    (apply with-style name
           (lambda ()
             (let ([win (detached-window "Preview" 'window-style name
                                         'draw settings-draw-preview-content)])
               (window-x-set! win 16)
               (window-y-set! win 14)
               (window-w-set! win (- (* 2 w) 32))
               (window-h-set! win (- (* 2 h) 28))
               (fill-wallpaper x y w h (theme 'wallpaper) 'desktop-top
                               'desktop-bottom)
               (with-clip (x y w h)
                 (with-translation (x y)
                   (with-scale (1/2) (draw-window* win #t))))))
           extra))

  (define (settings-draw-preview-content win cw ch)
    (let ([h (ui-control-height)] [w (- cw 28)])
      (ui-draw-button 14 12 (min w 120) h '() "Button" #f)
      (ui-draw-checkbox 14 (+ 20 h) w h '(checked) "Checkbox")
      (ui-draw-field 14 (+ 28 h h) w h '())))

  ;; A mouse press on a card, a swatch or a tab takes the keyboard from
  ;; where it was (a field would go on taking keys); a key's press keeps it
  ;; on what was pressed.
  (define (settings-press-focus! ui id)
    (when (ui-active? ui id) (ui-focus! ui #f)))

  ;; A style's card: its miniature, its title, a dot if you changed it; a
  ;; press chooses it.
  (define (settings-style-card ui name x y w h)
    (let ([id (list 'style name)])
      (ui-pressable! ui id x y w h
                     (lambda () (settings-press-focus! ui id) (set-style! name))
                     '(#\space return) '(doc ((L . "Choose this style"))))
      (when (settings-shown? y h)
        (settings-draw-card x y w h
                            (apply ui-flags ui id (if (eq? name (current-style))
                                                      '(selected)
                                                      '()))
                            (settings-style-title name)
                            (pair? (style-changes-of name)) name))))

  ;; The palettes' cards for key (the palette): the chosen style in each.
  (define (settings-palettes ui x y w key)
    (let ([cw (settings-card-width (map palette-title (palettes)))]
          [ch (settings-card-height)])
      (settings-card-grid (palettes) x y w cw ch
        (lambda (name cx cy)
          (let ([id (list key name)])

            (ui-pressable! ui id cx cy cw ch
                           (lambda ()
                             (settings-press-focus! ui id)
                             (settings-set! key name))
                           '(#\space return)
                           '(doc ((L . "Choose this palette"))))
            (when (settings-shown? cy ch)
              (settings-draw-card cx cy cw ch
                                  (apply ui-flags ui id
                                         (if (eq? name (theme key))
                                                            '(selected)
                                                            '()))
                                  (palette-title name) #f (current-style)
                                  'palette name)))))))

  ;; flags: selected, focused.
  (define (settings-draw-swatch x y d color flags)
    (fill-circle (+ x (/ d 2)) (+ y (/ d 2)) (- (/ d 2) 3) color)
    (when (memq 'selected flags)
      (stroke-circle (+ x (/ d 2)) (+ y (/ d 2)) (+ (/ d 2) 1) 'text 2))
    (when (memq 'focused flags) (ui-draw-focus x y d d flags (/ d 2))))

  ;; A color, key (the accent): the palette's colors as swatches. => the y
  ;; below.
  (define (settings-accent ui x y w key)
    (let ([colors (theme-palette-preview (theme 'palette))]
          [per-row (max 1 (exact (floor (/ (+ w 8) 36))))])
      (let loop ([ks (theme 'accent-choices)] [i 0])
        (if (null? ks)
            (+ y (* 36 (quotient (+ i per-row -1) per-row)))
            (let ([c (plist-ref colors (car ks) #x808080)]
                  [sx (+ x (* 36 (mod i per-row)))]
                  [sy (+ y (* 36 (quotient i per-row)))])
              (ui-pressable! ui (list 'swatch (car ks)) sx sy 28 28
                             (lambda ()
                               (settings-press-focus! ui
                                                      (list 'swatch (car ks)))
                               (settings-set! key c))
                             '(#\space return)
                             (list 'tip (symbol->string (car ks))))
              (settings-draw-swatch sx sy 28 c
                                    (apply ui-flags ui (list 'swatch (car ks))
                                           (if (eqv? c (theme key))
                                               '(selected)
                                               '())))
              (loop (cdr ks) (+ i 1)))))))

  ;; The chosen style, yours or as it comes; Reset (a dialog lists your
  ;; changes first) and Save as new style (a title typed in a field; the
  ;; name follows it). => the y below.
  (define (settings-style-bar ui x y w)
    (let* ([name (current-style)] [title (settings-style-title name)]
           [keys (plist-keys (style-changes-of name))] [h (ui-control-height)]
           [reset (format "Reset ~a" title)] [save "Save as new style…"]
           [bw (lambda (l) (let-values ([(bw bh) (ui-button-size l #f)]) bw))]
           [buttons-w (+ (bw reset) 8 (bw save))]
           [text (if (null? keys) title (format "~a, your version" title))]
           [beside? (<= (+ (text-width text 'ui) 24 buttons-w) w)]
           [by (if beside? y (+ y h 8))]
           [bx (if beside? (- (+ x w) buttons-w) x)]
           [saving (ui-memo ui '(settings save-title) #f)])
      (ui-draw-label x y (if beside? (- w buttons-w 24) w) h '() text)
      (ui-button ui 'reset-style bx by (bw reset) h reset
                 (lambda () (ui-memo! ui '(settings confirm-reset) #t))
                 'disabled (null? keys))
      (ui-button ui 'save-style (+ bx (bw reset) 8) by (bw save) h save
                 (lambda ()
                   (ui-memo! ui '(settings save-title) (format "My ~a" title))
                   (ui-focus! ui 'save-title #t)))
      (when (ui-memo ui '(settings confirm-reset) #f)
        (let ([done (lambda () (ui-memo! ui '(settings confirm-reset) #f))])
          (ui-dialog ui 'reset-dialog (format "Reset ~a?" title)
                     (format "Your changes to ~a go: ~a." title
                             (string-join (map settings-key-label keys) ", "))
                     (list (list "Cancel" done)
                           (list reset (lambda () (done) (reset-style!))
                                 'primary))
                     done)))
      (if saving
          (settings-save-row ui x (+ by h 12) w saving)
          (+ by h))))

  ;; The title of the style being saved, Save and Cancel, and why Save is
  ;; off when it is. => the y below.
  (define (settings-save-row ui x y w text)
    (let* ([h (ui-control-height)] [name (settings-style-name text)]
           [taken? (and name (find-style name) #t)]
           [close (lambda () (ui-memo! ui '(settings save-title) #f))]
           [save! (lambda ()
                    (when (and name (not taken?))
                      (save-style-as! name text)
                      (close)))]
           [fw (max 120 (- (min w 420) 200))])
      (ui-text-field ui 'save-title x y fw h text
                     (lambda (s) (ui-memo! ui '(settings save-title) s))
                     'placeholder "The new style's title" 'max 40
                     'on-enter save!)
      (ui-button ui 'save-style-ok (+ x fw 8) y 90 h "Save" save!
                 'primary #t 'disabled (or (not name) taken?))
      (ui-button ui 'save-style-cancel (+ x fw 106) y 90 h "Cancel" close)
      (ui-draw-label x (+ y h 6) w 0 '(hint wrap)
                     (cond [taken? (format "There is a style named ~a \
                                            already." name)]
                           [name (format "Saved as styles/~a.ss, with ~a as \
                                          its parent." name
                                          (settings-style-title
                                           (current-style)))]
                           [else "Type a title."]))))

  ;; The Theme tab: the styles' cards, the chosen style's bar, then its
  ;; options by group (Colors, Desktop, Shape, its own, Behavior), the
  ;; common ones it does not use, dimmed, and your Overrides. => the y
  ;; below.
  (define (settings-theme-tab ui x y w)
    (let* ([y (settings-heading x y w "Theme"
                "Pick a style: it brings its colors, fonts, sizes and \
                 behaviors. What you change is kept for that style.")]
           [cw (settings-card-width (map settings-style-title (styles)))]
           [ch (settings-card-height)]
           [y (+ 4 (settings-card-grid (styles) x y w cw ch
                     (lambda (name cx cy)
                       (settings-style-card ui name cx cy cw ch))))]
           [y (settings-style-bar ui x y w)]
           [fixed (theme 'fixed)]
           [groups (append
                    (map (lambda (g)
                           (cons g (remp (lambda (o) (memq (car o) fixed))
                                         (settings-options-in g))))
                         '("Colors" "Desktop" "Shape"))
                    (list (cons (format "~a's own"
                                        (settings-style-title (current-style)))
                                (settings-own-options))
                          (cons "Behavior" settings-behaviors)))]
           [unused (filter (lambda (k)
                             (and (memq k fixed)
                                  (not (memq k settings-text-keys))))
                           (map car common-options))]
           [label-w (settings-label-width
                     (append (map settings-row-label
                                  (apply append (map cdr groups)))
                             (map settings-key-label unused)))]
           [y (fold-left (lambda (y g)
                           (settings-group ui x y w label-w (car g) (cdr g)))
                         y groups)]
           [y (if (null? unused)
                  y
                  (fold-left (lambda (y k)
                               (+ 10 (settings-unused-row ui x y w label-w k)))
                             (settings-section
                              x y w (format "Not used by ~a"
                                            (settings-style-title
                                             (current-style))))
                             unused))])
      (settings-overrides ui x y w label-w)))

  ;; An Override's value in words, and whether the chosen style passes it
  ;; by (a common option it fixes, another style's own option).
  (define (settings-override-words key)
    (let ([v (settings-value-words key (plist-ref (theme-overrides) key #f))])
      (if (settings-applies? key) v (string-append v "; does not apply here"))))

  ;; Your Overrides, each with its value and a button that drops it, then
  ;; one that drops them all. => the y below.
  (define (settings-overrides ui x y w label-w)
    (let ([keys (plist-keys (theme-overrides))] [h (ui-control-height)])
      (if (null? keys)
          y
          (let ([y (fold-left
                    (lambda (y k)
                      (+ 8 (settings-row
                            ui x y w label-w (settings-key-label k) '(dim) h 120
                            0
                            (lambda (cx cy cw)
                              (ui-draw-label cx cy (- cw h 8) h '()
                                             (settings-override-words k))
                              (ui-button ui (list 'unpin k) (+ cx cw (- h)) cy h
                                         h #f (lambda () (override! k))
                                         'glyph 'cross 'quiet #t
                                         'tip "Drop this Override")))))
                    (settings-section x y w "Overrides")
                    keys)]
                [label "Clear all Overrides"])
            (let-values ([(bw bh) (ui-button-size label #f)])
              (ui-button ui 'clear-overrides x (+ y 4) bw h label
                         (lambda () (for-each override! keys))))
            (+ y 4 h)))))

  ;;; ------------------------------------------------------------------
  ;;; the Colors tab

  (define (settings-color-rows)
    (apply append (theme 'color-groups)))

  ;; Fills a track with n small steps of (color-at t), t in [0, 1].
  (define (settings-draw-steps x y w h color-at)
    (let ([n 48])
      (do ([i 0 (+ i 1)]) ((= i n))
        (fill-box (+ x (* i (/ w n))) y (+ 1 (/ w n)) h
                  (color-at (/ (+ i 0.5) n))))))

  ;; A row of the color list: its swatch and its name; flags: selected,
  ;; hover.
  ;; The swatch comes last, after a style that inverts the chosen row has:
  ;; its own color, whatever the row's.
  (define (settings-draw-color-row x y w h key flags)
    (cond [(memq 'selected flags) (ui-draw-highlight (+ x 4) y (- w 8) h '())]
          [(memq 'hover flags)
           (ui-draw-highlight (+ x 4) y (- w 8) h '(hover))])
    (ui-draw-label (+ x 38) y (- w 46) h
                   (if (memq 'selected flags) '() '(dim)) (symbol->string key))
    (when (memq 'selected flags)
      (ui-draw-highlight-over (+ x 4) y (- w 8) h '()))
    (fill-box (+ x 12) (+ y (/ (- h 16) 2)) 16 16 key 4)
    (stroke-box (+ x 12) (+ y (/ (- h 16) 2)) 16 16 'settings-swatch-ring 1 4))

  ;; A swatch's ring, which reads on its row, chosen or not: a stipple of ink
  ;; and paper where a style inverts the chosen row (Genera).
  (at-load
   (color-default! 'settings-swatch-ring (theme-rule (alpha 'text 0.25))))

  (define (settings-draw-big-swatch x y d color)
    (fill-box x y d d color 12)
    (stroke-box x y d d (alpha 'text 0.25) 1 12))

  ;; avail: the visible height of the pane, which the list fills.
  (define (settings-colors ui st x y w avail)
    (let* ([ly (settings-heading x y w "Colors"
                 "Pick a color to edit it. Every window updates as you drag.")]
           [lw (settings-color-list-width)]
           [row-h (settings-color-row-height)]
           [rows (settings-color-rows)]
           [total (+ 12 (* row-h (length rows)))]
           ;; the editor sits beside the list, or below it when there's no room
           [beside? (>= (- w lw 28) (settings-color-editor-width))]
           [lh (if beside?
                   (max (* 6 row-h) (- (+ y avail) ly))
                   (min total (* 8 row-h)))]
           [scroll (clamp (settings-st-scroll st) 0 (max 0 (- total lh)))])
      (settings-st-scroll-set! st scroll)
      (ui-draw-surface x ly lw lh '(well))
      ;; for the wheel; the rows sit on top
      (ui-area ui 'color-list x ly lw lh #f)
      (with-clip (x (+ ly 4) lw (- lh 8))
        (let loop ([rs rows] [ry (- (+ ly 6) scroll)])
          (unless (or (null? rs) (> ry (+ ly lh)))
            (let ([r (car rs)] [top (max ry ly)]
                  [bottom (min (+ ry row-h) (+ ly lh))])
              (when (> (+ ry row-h) ly)
                (if (string? r)
                    (ui-draw-label (+ x 12) ry (- lw 24) row-h '(section) r)
                    (begin
                      (when (> bottom top)
                        (ui-area ui (list 'color r) x top lw (- bottom top)
                                 (lambda ()
                                   (settings-st-key-set! st r)
                                   (settings-st-hex-set! st #f))))
                      (settings-draw-color-row
                       x ry lw row-h r
                       (cond [(eq? r (settings-st-key st)) '(selected)]
                             [(and (> bottom top)
                                   (ui-hover? ui x top lw (- bottom top)))
                              '(hover)]
                             [else '()])))))
              (loop (cdr rs) (+ ry row-h))))))
      (if beside?
          (max (+ ly lh)
               (settings-color-editor ui st (+ x lw 28) ly (- w lw 28)))
          (settings-color-editor ui st x (+ ly lh 28) w))))

  (define (settings-parse-hex s)
    (case (string-length s)
      [(6) (string->number s 16)]
      [(3) (string->number
            (list->string
             (apply append (map (lambda (c) (list c c)) (string->list s))))
            16)]
      [else #f]))

  ;; The swatch, the key's name, its hex digits (a field: type six, then
  ;; Return) and marks, its hue, saturation and lightness, and how to read
  ;; it at the REPL. Returns the y below the editor.
  (define (settings-color-editor ui st x y w)
    (let* ([key (settings-st-key st)]
           [value (theme key)]
           [rgbv (color->fixnum value)]
           [hsl (let ([c (settings-st-hsl st)])
                  (if (and c (eq? (vector-ref c 0) key)
                           (eqv? (vector-ref c 1) rgbv))
                      c
                      (let-values ([(hh ss ll) (color->hsl value)])
                        (let ([v (vector key rgbv hh ss ll)])
                          (settings-st-hsl-set! st v)
                          v))))]
           [label-w (settings-hsl-label-width)]
           [readout-w (settings-hsl-readout-width)]
           [sx (+ x label-w)]
           [h (ui-control-height)]
           [by (+ y (max 44 (round (+ 2 (font-line-height 'heading) 21))))]
           [bw (settings-hex-width)]
           [row0 (+ (max (+ y 78) (+ by h)) 26)]
           [focused? (equal? (ui-focused ui) 'hex)])
      (define (update! i v)
        (vector-set! hsl i v)
        (let ([c (color-from-hsl (vector-ref hsl 2) (vector-ref hsl 3)
                                 (vector-ref hsl 4))])
          (vector-set! hsl 1 c)
          (settings-set! key c)))
      (define (slider-row ry label id v lo hi readout paint on-change)
        (+ 18 (settings-row ui x ry w label-w label '(dim) 24 60 readout-w
                (lambda (cx cy cw)
                  (ui-slider ui id cx cy cw v lo hi on-change paint)
                  (ui-draw-label (+ cx cw 16) cy (- readout-w 16) 24 '(dim)
                                 readout)))))
      (define (track color-at)
        (lambda (tx ty tw th) (settings-draw-steps tx ty tw th color-at)))
      (unless focused? (settings-st-hex-set! st #f))
      (settings-draw-big-swatch x y 78 value)
      (ui-draw-label sx y (- w label-w) (font-line-height 'heading) '(heading)
                     (symbol->string key))
      (ui-text-field ui 'hex sx by bw h
                     (if focused?
                         (or (settings-st-hex st) "")
                         (settings-hex-digits rgbv))
                     (lambda (s)
                       (settings-st-hex-set!
                        st (list->string
                            (filter (lambda (c) (or (char<=? #\0 c #\9)
                                                    (char<=? #\a c #\f)))
                                    (string->list (string-downcase s))))))
                     'max 6 'placeholder (settings-hex-digits rgbv)
                     'tip "Type six hex digits, then Return"
                     'on-enter (lambda ()
                                 (let ([v (settings-parse-hex
                                           (or (settings-st-hex st) ""))])
                                   (when v (settings-set! key v)))
                                 (settings-st-hex-set! st #f)
                                 (ui-focus! ui #f)))
      (settings-marks ui (+ sx bw 8) by key)
      (let* ([hh (vector-ref hsl 2)]
             [ss (vector-ref hsl 3)]
             [ll (vector-ref hsl 4)]
             [y1 (slider-row row0 "Hue" 'hue hh 0 360
                             (format "~a°" (exact (round hh)))
                             (track (lambda (t)
                                      (color-from-hsl (* 360 t) (max ss 0.4)
                                                      (clamp ll 0.35 0.65))))
                             (lambda (v) (update! 2 v)))]
             [y2 (slider-row y1 "Saturation" 'saturation ss 0 1
                             (format "~a%" (exact (round (* 100 ss))))
                             (track (lambda (t) (color-from-hsl hh t ll)))
                             (lambda (v) (update! 3 v)))]
             [y3 (slider-row y2 "Lightness" 'lightness ll 0 1
                             (format "~a%" (exact (round (* 100 ll))))
                             (track (lambda (t) (color-from-hsl hh ss t)))
                             (lambda (v) (update! 4 v)))])
        ;; rgb and the expression that reads this key, on two lines if need be
        (let*-values ([(r g b a) (color-rgba rgbv)]
                      [(rgb) (format "rgb(~a, ~a, ~a)" (exact (round (* r 255)))
                                     (exact (round (* g 255)))
                                     (exact (round (* b 255))))]
                      [(expr) (format "(theme '~a)" key)]
                      [(one-line) (string-append rgb "   " expr)]
                      [(ty) (+ y3 8)]
                      [(lh) (font-line-height 'mono-small)])
          (if (<= (text-width one-line 'mono-small) w)
              (ui-draw-label x ty w lh '(mono) one-line)
              (ui-draw-label x (ui-draw-label x ty w lh '(mono) rgb) w lh
                             '(mono) expr))))))

  ;;; ------------------------------------------------------------------
  ;;; the Fonts and Display tabs

  ;; Text in the interface fonts and code in the REPL's colors.
  (define (settings-draw-font-sample x y w)
    (let* ([cw (font-char-width 'mono)] [lh (transcript-line-height)]
           [code-y (round (+ 14 (* 2 (font-line-height 'ui)) 8 22))]
           [ph (max 190 (+ code-y (* 3 lh) 14))])
      (define (code-line i text)
        (let ([colors (transcript-draw-scheme text 3)])
          (transcript-fill-colors! colors 0 3 'accent)
          (transcript-draw-line (+ x 18) (+ y code-y (* i lh))
                                text colors 999 0 1 cw lh)))
      (if (<= (theme 'corner-radius) 0)   ; square: on whole device pixels
          (begin (fill-box x y w ph 'bg-0) (stroke-box x y w ph 'window-border))
          (begin (fill-box x y w ph 'bg-0 8)
                 (stroke-box x y w ph 'window-border 1 8)))
      (with-clip (x y w ph)
        (draw-text (+ x 18) (+ y 14)
                   "The quick brown fox jumps over the lazy dog." 'text 'ui)
        (draw-text (+ x 18) (+ y 14 (font-line-height 'ui) 8)
                   "Window titles and menus use the bold weight."
                   'text-dim 'ui-bold)
        (code-line 0 "λ> (define (square x) (* x x))  ; code")
        (code-line 1 "λ> (map square '(1 2 3))")
        (draw-text (+ x 18) (+ y code-y (* 2 lh)) "(1 4 9)" 'teal 'mono))
      (+ y ph)))

  ;; The four text options (dimmed where the style sets them), and a
  ;; sample.
  (define (settings-fonts ui x y w)
    (let* ([y (+ 6 (settings-heading x y w "Fonts" "Interface text and code."))]
           [os (map settings-option settings-text-keys)]
           [label-w (settings-label-width (map settings-row-label os))]
           [y (fold-left (lambda (y o)
                           (+ 18 (if (memq (car o) (theme 'fixed))
                                     (settings-unused-row ui x y w label-w
                                                          (car o))
                                     (settings-option-row ui x y w label-w o))))
                         y os)])
      (settings-draw-font-sample x (+ y 10) w)))

  (define (settings-display ui x y w)
    (let* ([y (+ 6 (settings-heading x y w "Display"
                     "How big everything is drawn, full screen, and how \
                      frames are shown."))]
           [label-w (settings-label-width '("Scale" "Full screen"
                                            "Presenting"))]
           [h (ui-control-height)]
           [segmented-w (lambda (choices)
                          (* (length choices)
                             (+ 34 (text-widest (map car choices) 'ui))))]
           [scale-w (segmented-w settings-scale-choices)]
           [stack? (< (- w label-w) scale-w)]   ; both rows stack, or neither
           [y (settings-row ui x y w label-w "Scale" '(dim) h scale-w 0
                            (lambda (sx sy sw)
                              (ui-segmented ui 'scale sx sy (min scale-w sw) h
                                            settings-scale-choices
                                            (theme 'scale)
                                            (lambda (v) (set-scale! v)))))]
           [y (+ 22 (ui-draw-label x (+ y 10) w 0 '(hint wrap)
                                   (format "Auto follows your desktop, which \
                                            asks for ~a%. Everything is drawn \
                                            from outlines, so text stays sharp \
                                            at any scale; 1-pixel lines are \
                                            crispest at whole multiples like \
                                            200%."
                                           (system-scale-percent))))]
           [fs-choices '(("Off" . #f) ("On" . #t))]
           [y (settings-row ui x y w label-w "Full screen" '(dim) h
                            (if stack? (+ w 1) (segmented-w fs-choices)) 0
                            (lambda (sx sy sw)
                              (ui-segmented
                               ui 'fullscreen sx sy
                               (min (max 160 (segmented-w fs-choices)) sw)
                               h fs-choices (fullscreen?)
                               (lambda (v) (set-fullscreen! v)))))]
           [present-choices
            (let ([offered (cdr (assq 'present-modes *gpu-facts*))])
              (filter (lambda (c) (memq (cdr c) offered))
                      settings-present-choices))])
      (if (< (length present-choices) 2)
          y
          (let ([y (settings-row
                    ui x (+ y 18) w label-w "Presenting" '(dim) h
                    (if stack? (+ w 1) (segmented-w present-choices)) 0
                    (lambda (sx sy sw)
                      (ui-segmented
                       ui 'present-mode sx sy
                       (min (max 160 (segmented-w present-choices)) sw)
                       h present-choices (theme 'present-mode)
                       ;; the window's, whatever the style
                       (lambda (v)
                         (if (eq? v (theme-default 'present-mode))
                             (override! 'present-mode)
                             (override! 'present-mode v))))))])
            (+ 22 (ui-draw-label x (+ y 10) w 0 '(hint wrap)
                                 "VSync: core1 waits its turn for the screen, \
                                  and a frame that misses it shows as a flag \
                                  in Monitor. Mailbox: core1 seldom waits, and \
                                  a newer frame replaces one not shown yet. \
                                  That leaves no trace here, so fewer flags \
                                  needn't mean fewer missed frames."))))))

  ;;; ------------------------------------------------------------------
  ;;; paths

  ;; Where libraries are found, and what loads with the world: the library
  ;; search, its folders in order (the first that holds a library is the
  ;; one it loads from), each with a switch for whether it auto-loads, and
  ;; a row that adds one; the libraries loaded from a file, by the rank of
  ;; the layer each declares, and whether it auto-loads. => the y below
  (define (settings-paths ui x y w)
    (let* ([facts (settings-path-facts ui)]
           [dirs (car facts)] [libs (cadr facts)]
           [y (+ 12 (ui-draw-label x y w 0 '(hint wrap)
                                   "Libraries are found in these folders, \
                                    in this order: a library loads from \
                                    the first that holds it. One that \
                                    auto-loads loads what it holds with \
                                    the world, at boot and at each reload, \
                                    read again each time. Schevana's own \
                                    always loads: the tree's kits, \
                                    services, looks, desktop and apps, and \
                                    folders of those names in \
                                    ~/.schevana.d."))]
           [y (ui-rows ui 'search x y w
                       (map (lambda (d i) (settings-search-row ui d i))
                            dirs (iota (length dirs)))
                       'title "Library paths"
                       'add (list "Add Library Path" settings-path-choose))])
      (ui-rows ui 'libs x (+ y 18) w
               (map (lambda (l)
                      (let ([layer (caddr l)])
                        (list (format "~s" (car l))
                              (format "~a~a · ~a"
                                      (if layer
                                          (format "Rank ~a, ~a"
                                                  (settings-layer-rank layer)
                                                  layer)
                                          "No layer")
                                      (if (cadddr l) ", auto-loads" "")
                                      (cadr l))
                              0 #f
                              'key (car l))))
                    libs)
               'title "Loaded libraries"
               'description (format "By the rank of the layer each declares \
                                     (library-layer); ~a more of Chez's \
                                     own, with no file"
                                    (- (length (library-list))
                                       (length libs))))))

  ;; A layer's rank, the lowest 1; past them all for one that isn't.
  (define (settings-layer-rank layer)
    (let ([names (library-layer-names)])
      (+ 1 (or (list-index (lambda (l) (eq? l layer)) names)
               (length names)))))

  ;; What the tab shows, worked out once while the library search, the
  ;; libraries loaded and what auto-loads stay the same: (search-folders
  ;; ((name file layer auto?) ...)), the libraries by their layers' rank,
  ;; then by name.
  (define (settings-path-facts ui)
    (let ([key (list (library-directories) (length (library-list))
                     (auto-loads))]
          [kept (ui-memo ui 'path-facts #f)])
      (if (and kept (equal? (car kept) key))
          (cdr kept)
          (let* ([dirs (library-directories)]
                 [entries (apply append (map auto-load-entries (auto-loads)))]
                 [libs (filter-map
                        (lambda (name)
                          (let ([f (exists (lambda (d)
                                             (settings-library-file
                                              (if (pair? d) (car d) d) name))
                                           dirs)])
                            (and f
                                 (list name f (library-file-layer f)
                                       (and (member name entries) #t)))))
                        (library-list))]
                 [rank (lambda (l)
                         (if (caddr l) (settings-layer-rank (caddr l)) 1000))]
                 [facts (list dirs
                              (list-sort
                               (lambda (a b)
                                 (or (< (rank a) (rank b))
                                     (and (= (rank a) (rank b))
                                          (string<? (format "~s" (car a))
                                                    (format "~s" (car b))))))
                               libs))])
            (ui-memo! ui 'path-facts (cons key facts))
            facts))))

  ;; The file of library name in folder dir, a source's, or #f.
  (define (settings-library-file dir name)
    (let ([base (string-append (path-full dir) "/"
                               (string-join (map symbol->string name) "/"))])
      (find file-exists?
            (map (lambda (ext) (string-append base ext)) '(".sls" ".ss")))))

  ;; A folder of the library search, d (source . objects), the i-th: how
  ;; it is written where that isn't in full (Chez's ".", the current
  ;; folder), where its libraries compile to, and whether it auto-loads.
  ;; The tree's own world loads from the tree; a folder that holds the tree
  ;; never auto-loads (its tests and its own sources would load), nor can
  ;; one of Schevana's own folders be turned off.
  (define (settings-search-row ui d i)
    (let* ([source (if (pair? d) (car d) d)]
           [objects (if (pair? d) (cdr d) d)]
           [path (path-full source)]
           [root (path-full *schevana-root*)]
           [tree? (string-prefix? (string-append path "/")
                                  (string-append root "/"))]
           [own? (and (member path (auto-loads))
                      (not (member path *auto-loads*)))])
      (ui-switch-row ui (list 'search-auto i) path
                     (or (equal? path root) (and (member path (auto-loads)) #t))
                     (lambda (on)
                       (if on (auto-load! path) (auto-load-forget! path)))
                     'subtitle
                     (string-append
                      (if (equal? (path-full objects) path)
                          "From its sources"
                          (format "Compiled into ~a" (path-full objects)))
                      (if (equal? source path) "" (format ", as ~s" source))
                      (cond [(equal? path root) ", Schevana's own"]
                            [tree? ", holds the tree"]
                            [own? ", Schevana's own"]
                            [else ""]))
                     'disabled (or tree? own?))))

  ;; A folder to add to the library search, picked in the file dialog; it
  ;; auto-loads once its switch is turned on.
  (define (settings-path-choose)
    (open-file-dialog (current-window) "Add a Library Path" "Add"
                      settings-path-added!
                      'picks 'folders
                      'folder "~"))

  (define (settings-path-added! folder)
    (add-library-directory! (path-full folder)))

  ;;; ------------------------------------------------------------------
  ;;; the app

  (define (settings-sidebar ui st sw h)
    (ui-draw-surface 0 0 sw h '(nav))
    (ui-draw-label 20 18 (- sw 40) (font-line-height 'heading) '(heading)
                   "Settings")
    (let* ([tabs-bottom
            (- (ui-nav ui 'tab 10 (round (+ 18 (font-line-height 'heading) 27))
                       (- sw 20)
                       (map (lambda (t) (list (car t) (cdr t) #f))
                            settings-tabs)
                       (settings-st-tab st)
                       (lambda (t)
                         (settings-press-focus! ui (list 'tab t))
                         (settings-st-tab-set! st t)
                         (settings-st-hex-set! st #f)
                         (settings-st-pane-scroll-set! st 0)))
               6)]
           ;; The hint at the bottom, wrapped to the sidebar, and the button
           ;; above it; both move down rather than cover the tabs.
           [hint "Changes apply live and are saved automatically."]
           [hint-h (let-values ([(hw hh) (ui-label-size '(hint wrap) hint
                                                        (- sw 32))])
                     hh)]
           [bh (max 30 (round (+ (font-line-height 'ui) 15)))]
           [by (max (- h 20 hint-h 12 bh) (+ tabs-bottom 16))])
      (ui-button ui 'reset-all 14 by (- sw 28) bh "Reset to defaults"
                 (lambda () (reset-theme!)))
      (ui-draw-label 18 (+ by bh 12) (- sw 32) 0 '(hint wrap) hint)))

  ;; The pane's scroll bar, when what the tab shows is taller than h: on
  ;; the style's side of the pane from x0 to x1 (left, or right), shown as
  ;; it says (always, or while the pointer is over the pane).
  (define (settings-pane-scrollbar ui st x0 x1 h content-h max-scroll)
    (let ([bw (ui-scrollbar-width)])
      (when (or (eq? (theme 'scrollbar-show) 'always)
                (ui-active? ui 'pane-scrollbar)
                (and (memq (window-hover (current-window)) '(content scrollbar))
                     (ui-hover? ui x0 0 (- x1 x0) h)))
        (ui-scrollbar ui 'pane-scrollbar
                      (if (eq? (theme 'scrollbar-side) 'left) x0 (- x1 bw)) 0
                      bw h (settings-st-pane-scroll st) content-h h
                      (lambda (off)
                        (settings-st-pane-scroll-set!
                         st (clamp (exact (round off)) 0 max-scroll)))))))

  ;; The pane scrolls to a widget focused out of view (by Tab, or a field
  ;; just opened). => #t when it moved.
  (define (settings-reveal! ui st h)
    (let* ([rv (ui-state-reveal ui)] [r (and rv (ui-find ui (car rv)))])
      (ui-state-reveal-set! ui #f)
      (and r
           (let* ([top (cadr (ui-region-frame r))]
                  [bottom (+ top (cadddr (ui-region-frame r)))]
                  [scroll (settings-st-pane-scroll st)]
                  [new (max 0 (cond [(< top 10) (+ scroll top -10)]
                                    [(> bottom (- h 10))
                                     (+ scroll bottom 10 (- h))]
                                    [else scroll]))])
             (settings-st-pane-scroll-set! st new)
             (not (= new scroll))))))

  (define (settings-draw ui st w h)
    (ui-begin! ui)
    (ui-draw-surface 0 0 w h '(page))
    (settings-sidebar ui st (settings-sidebar-width) h)
    ;; the pane's margins, or the room its scroll bar keeps if more
    (let* ([sw (settings-sidebar-width)]
           [x (+ sw (max 28 (ui-scrollbar-inset 'left)))]
           [cw (- w x (max 28 (ui-scrollbar-inset 'right)))]
           [scroll (settings-st-pane-scroll st)]
           [y (- 20 scroll)]
           [bottom (with-clip ((+ sw 1) 0 (- w sw 1) h)
                     (ui-region! ui 'pane (+ sw 1) 0 (- w sw 1) h)
                     (parameterize ([settings-pane-height h])
                       (case (settings-st-tab st)
                         [(colors) (settings-colors ui st x y cw (- h 38))]
                         [(fonts) (settings-fonts ui x y cw)]
                         [(display) (settings-display ui x y cw)]
                         [(paths) (settings-paths ui x y cw)]
                         [else (settings-theme-tab ui x y cw)])))]
           [content-h (+ (- bottom y) 20 18)]
           [max-scroll (max 0 (- content-h h))])
      (when (> max-scroll 0)
        (settings-pane-scrollbar ui st (+ sw 1) w h content-h max-scroll))
      ;; the wheel went past the end, which only drawing finds, or the pane
      ;; scrolls to a widget: drawn again where it stops, not shown for a
      ;; frame before
      (if (or (and (> scroll max-scroll)
                   (begin (settings-st-pane-scroll-set! st max-scroll) #t))
              (settings-reveal! ui st h))
          (settings-draw ui st w h)
          (ui-end! ui w h))))

  ;; Up and Down move through the color list.
  (define (settings-key st win key mods)
    (and (eq? (settings-st-tab st) 'colors) (memq key '(up down)) (null? mods)
         (let* ([keys (filter symbol? (settings-color-rows))]
                [i (or (list-index (lambda (k) (eq? k (settings-st-key st)))
                                   keys)
                       0)])
           (settings-st-key-set!
            st (list-ref keys (clamp (+ i (if (eq? key 'up) -1 1))
                                     0 (- (length keys) 1))))
           (invalidate! win)
           #t)))

  ;; The wheel goes to the kit's (a dialog, a scroll bar), else scrolls the
  ;; color list under the pointer, else the pane.
  (define (settings-wheel ui st dy)
    (let ([r (and (eq? (settings-st-tab st) 'colors) (ui-find ui 'color-list))])
      (cond
        [(ui-wheel ui dy)]
        [(and r (ui-region-in? r (ui-state-mx ui) (ui-state-my ui)))
         (settings-st-scroll-set!
          st (max 0 (- (settings-st-scroll st)
                       (* (settings-color-row-height) dy))))]
        [else
         (settings-st-pane-scroll-set!
          st (max 0 (- (settings-st-pane-scroll st)
                       (* 3 (round (font-line-height 'ui)) dy))))])))

  (define-app (settings) "Settings"
    (let ([existing (find-window 'settings)])
      (if (and existing (settings-st? (window-ref existing 'state #f)))
          (begin (focus-window! existing) existing)
          (let ([ui (make-ui)]
                [st (make-settings-st 'theme (car (theme 'accent-choices))
                                      0 #f #f 0)])
            ;; a window opened by code from before a (reload!) that changed
            ;; settings-st can't draw any more: replace it
            (when existing (close-window! existing))
            (apply open-window "Settings"
                   'size (cons (settings-natural-width)
                               (settings-natural-height))
                   'min-size '(640 . 420)
                   'state st
                   'draw (lambda (win w h) (settings-draw ui st w h))
                   (append
                    (ui-handlers ui 'key (lambda (win key mods)
                                           (settings-key st win key mods)))
                    (list 'wheel (lambda (win dx dy)
                                   (settings-wheel ui st dy)
                                   (invalidate! win))))))))))
