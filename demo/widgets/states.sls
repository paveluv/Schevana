;;; (demo widgets states) — the Widgets demo's sheet of the kit's parts:
;;; each ui-draw-… part drawn in every state from made-up flags, as a style
;;; draws it; then the parts that differ by kind rather than by state, the
;;; popups at their own sizes, the sizes the style gives, and where its
;;; areas put a widget's pieces. Nothing on it takes input.

(library (demo widgets states)
  (export widgets-states-page)
  (import (chezscheme)
          (schevana core)
          (schevana kits ui)
          (demo widgets layout))

  ;; The sheet's columns: each state's name and the flags made up for it.
  (define widgets-states
    '(("Normal")
      ("Hover" hover)
      ("Pressed" hover pressed)
      ("Disabled" disabled)
      ("Focused" focused)
      ("Selected" selected)
      ("Checked" checked)))

  ;; Returns a number as the sheet shows it: whole, or to a tenth.
  (define (widgets-shown v)
    (cond [(and (number? v) (integer? v)) (exact v)]
          [(number? v) (/ (round (* 10 v)) 10.0)]
          [(pair? v) (cons (widgets-shown (car v)) (widgets-shown (cdr v)))]
          [else v]))

  ;; Draws areas, ((name x y w h ...) ...) as an areas part returns them,
  ;; each a box with its name; entries that are no box are left out.
  (define (widgets-outline areas)
    (for-each (lambda (a)
                (when (and (pair? a) (list? a) (>= (length a) 5)
                           (for-all number? (list-head (cdr a) 4)))
                  (let-values ([(ax ay aw ah) (apply values
                                                     (list-head (cdr a) 4))])
                    (stroke-box ax ay (max 1 aw) (max 1 ah) 'accent 1)
                    (draw-text (+ ax 2) (+ ay 1) (format "~a" (car a))
                               'text-faint 'ui-small))))
              areas))

  ;; Returns (values right bottom) of the sheet drawn from (x, y), w wide.
  (define (widgets-states-page ui win x y w)
    (let* ([gap (ui-gap)] [ch (ui-control-height)] [g (ui-glyph-size)]
           [sh (font-line-height 'ui-small)]
           [lw 220] [cw 124] [n (length widgets-states)]
           [right (+ x lw (* n cw))] [rh (+ ch 12)]
           ;; Draws in each state's cell, x y w h inside it, with that
           ;; state's flags, in place, as the kit draws there; the part's
           ;; name goes before. Returns the y under the row.
           [row (lambda (y name h draw . place)
                  (ui-draw-label x y lw h '(mono) name)
                  (for-each
                   (lambda (state i)
                     (let ([cx (+ x lw (* i cw))])
                       (with-clip (cx y cw h)
                         (if (pair? place)
                             (with-place (car place)
                               (lambda ()
                                 (draw (+ cx 6) (+ y 4) (- cw 12) (- h 8)
                                       (cdr state))))
                             (draw (+ cx 6) (+ y 4) (- cw 12) (- h 8)
                                   (cdr state))))))
                   widgets-states (iota n))
                  (ui-draw-separator x (+ y h -1) (- right x) 1 '())
                  (+ y h))]
           ;; Draws a row of kinds: each named over its cell, which draw
           ;; draws, given the kind's index.
           [kinds (lambda (y name h names draw)
                    (ui-draw-label x y lw h '(mono) name)
                    (for-each
                     (lambda (kind i)
                       (let ([cx (+ x lw (* i cw))])
                         (ui-draw-label (+ cx 6) y (- cw 12) sh '(hint) kind)
                         (with-clip (cx (+ y sh) cw (- h sh))
                           (draw (+ cx 6) (+ y sh 4) (- cw 12) (- h sh 8) i))))
                     names (iota (length names)))
                    (ui-draw-separator x (+ y h -1) (- right x) 1 '())
                    (+ y h))]
           ;; A size's or an areas' name takes the width of three cells.
           [nw (+ lw cw cw)]
           ;; Writes what a size part returns, its values in a list.
           [size (lambda (y name thunk)
                   (ui-draw-label x y nw sh '(mono) name)
                   (ui-draw-label (+ x nw) y (- right x nw) sh '()
                                  (format "~s" (widgets-shown
                                                (call-with-values thunk
                                                  list))))
                   (+ y sh 4))]
           ;; Draws the areas a part puts in a box w × h, over the box.
           [areas (lambda (y name w h thunk)
                    (ui-draw-label x y nw sh '(mono) name)
                    (widgets-frame (+ x nw) y w h)
                    (widgets-outline (thunk (+ x nw) y))
                    (+ y (max h sh) gap))]
           [y (widgets-heading x y w "Every part in every state")]
           [y (begin
                (for-each (lambda (state i)
                            (ui-draw-label (+ x lw (* i cw) 6) y (- cw 12) ch
                                           '(dim) (car state)))
                          widgets-states (iota n))
                (+ y ch))]
           [y (row y "ui-draw-button" rh
                   (lambda (x y w h f) (ui-draw-button x y w h f "Button" #f)))]
           [y (row y "ui-draw-button primary" rh
                   (lambda (x y w h f)
                     (ui-draw-button x y w h (cons 'primary f) "Primary" #f)))]
           [y (row y "ui-draw-button danger" rh
                   (lambda (x y w h f)
                     (ui-draw-button x y w h (cons 'danger f) "Danger" #f)))]
           [y (row y "ui-draw-button quiet" rh
                   (lambda (x y w h f)
                     (ui-draw-button x y w h (cons 'quiet f) "Quiet" #f)))]
           [y (row y "ui-draw-button pill, glyph" rh
                   (lambda (x y w h f)
                     (ui-draw-button x y w h (cons 'pill f) "Add" 'plus)))]
           [y (row y "ui-draw-button circular" rh
                   (lambda (x y w h f)
                     (ui-draw-button x y h h (cons 'circular f) #f 'gear)))]
           [y (row y "ui-draw-button segment" rh
                   (lambda (x y w h f)
                     (ui-draw-button x y w h
                                     (append '(segment join-left join-right) f)
                                     "Segment" #f)))]
           [y (row y "ui-draw-checkbox" rh
                   (lambda (x y w h f) (ui-draw-checkbox x y w h f "Check")))]
           [y (row y "ui-draw-toggle" rh
                   (lambda (x y w h f) (ui-draw-toggle x y w h f "Toggle")))]
           [y (row y "ui-draw-radio" rh
                   (lambda (x y w h f)
                     (ui-draw-radio x y w h f "Radio" #f #f)))]
           [y (row y "ui-draw-radio hint, icon" (+ rh sh sh)
                   (lambda (x y w h f)
                     (ui-draw-radio x y w h f "Radio" "A hint under it"
                                    (lambda (x y s flags)
                                      (ui-draw-glyph x y s s flags 'globe)))))]
           [y (row y "ui-draw-tab" rh
                   (lambda (x y w h f)
                     (ui-draw-tab x y w h (append '(first last) f) "Tab")))]
           [y (row y "ui-draw-nav-row" rh
                   (lambda (x y w h f)
                     (ui-draw-nav-row x y w h f "Place"
                                      (lambda (x y s flags)
                                        (ui-draw-glyph x y s s flags
                                                       'home)))))]
           [y (row y "ui-draw-slider" rh
                   (lambda (x y w h f)
                     (ui-draw-slider (+ x 8) y (- w 16) (ui-slider-height) f
                                     3/5 #f)))]
           [y (row y "ui-draw-live-badge" rh
                   (lambda (x y w h f)
                     (let* ([live? (memq 'checked f)]
                            [label (if live? "Live" "Held")])
                       (let-values ([(bw bh) (ui-live-badge-size live? label)])
                         (ui-draw-live-badge x y (min w bw) bh f label)))))]
           [y (row y "ui-draw-dropdown" rh
                   (lambda (x y w h f) (ui-draw-dropdown x y w h f "Choice")))]
           [y (row y "ui-draw-dropdown open" rh
                   (lambda (x y w h f)
                     (ui-draw-dropdown x y w h (cons 'open f) "Open")))]
           [y (row y "ui-draw-dropdown set" rh
                   (lambda (x y w h f)
                     (ui-draw-dropdown x y w h (cons 'set f) "A filter")))]
           [y (row y "ui-draw-dropdown placeholder" rh
                   (lambda (x y w h f)
                     (ui-draw-dropdown x y w h (cons 'placeholder f)
                                       "No date")))]
           [y (row y "ui-draw-field" rh
                   (lambda (x y w h f) (ui-draw-field x y w h f))
                   'field)]
           [y (row y "ui-draw-suggestion" rh
                   (lambda (x y w h f)
                     (ui-draw-suggestion x y w h f "suggestion")))]
           [y (row y "ui-draw-chip" rh
                   (lambda (x y w h f)
                     (let-values ([(bw bh) (ui-chip-size "tag" #f)])
                       (ui-draw-chip x y (min w bw) bh f "tag"))))]
           [y (row y "ui-draw-chip removable" rh
                   (lambda (x y w h f)
                     (let-values ([(bw bh) (ui-chip-size "tag" #t)])
                       (ui-draw-chip x y (min w bw) bh (cons 'removable f)
                                     "tag"))))]
           [y (row y "ui-draw-table-header" rh
                   (lambda (x y w h f)
                     (ui-draw-table-header x y w (ui-table-header-height) f
                                           "Name" 'up))
                   'list)]
           [y (row y "ui-draw-table-divider" rh
                   (lambda (x y w h f)
                     (ui-draw-table-divider (+ x (quotient w 2)) y
                                            (ui-table-header-height) f))
                   'list)]
           [y (row y "ui-draw-table-row, cell" rh
                   (lambda (x y w h f)
                     (ui-draw-table-row x y w (ui-table-row-height) f)
                     (ui-draw-cell x y w (ui-table-row-height) f "Cell"))
                   'list)]
           [y (row y "ui-draw-tree-row" rh
                   (lambda (x y w h f)
                     (let ([th (ui-table-row-height)])
                       (ui-draw-tree-row x y w th (append '(kids expanded) f)
                                         w 1)
                       (let ([c (cdr (assq 'cell (ui-tree-areas x y w th 1)))])
                         (ui-draw-cell (car c) y (caddr c) th f "Node"))))
                   'list)]
           [y (row y "ui-draw-dim" rh
                   (lambda (x y w h f)
                     (ui-draw-label x y w h '() "Dimmed")
                     (ui-draw-dim x y w h (cons 'dim f)))
                   'list)]
           [y (row y "ui-draw-row" (+ rh sh)
                   (lambda (x y w h f)
                     (ui-draw-rows x y w h '())
                     (ui-draw-row x y w h (append '(first last activatable) f)
                                  "Title" "Subtitle" (+ x 8) (- w 16))
                     (ui-draw-rows x y w h '(over))))]
           [y (row y "ui-draw-add-row" (+ rh sh)
                   (lambda (x y w h f)
                     (ui-draw-rows x y w h '())
                     (ui-draw-add-row x y w h
                                      (append '(first last activatable) f)
                                      "Add one")
                     (ui-draw-rows x y w h '(over))))]
           [y (row y "ui-draw-day" rh
                   (lambda (x y w h f) (ui-draw-day x y h h f "14"))
                   'dialog)]
           [y (row y "ui-draw-day today, outside" rh
                   (lambda (x y w h f)
                     (ui-draw-day x y h h (cons 'today f) "15")
                     (ui-draw-day (+ x h 4) y h h (cons 'outside f) "31"))
                   'dialog)]
           [y (row y "ui-draw-day cursor" rh
                   (lambda (x y w h f)
                     (ui-draw-day x y h h (cons 'cursor f) "16"))
                   'dialog)]
           [y (row y "ui-draw-highlight" rh
                   (lambda (x y w h f)
                     (ui-draw-highlight x y w h f)
                     (ui-draw-label (+ x 6) y (- w 12) h '() "Entry")
                     (ui-draw-highlight-over x y w h f)))]
           [y (row y "ui-draw-highlight outline" rh
                   (lambda (x y w h f)
                     (ui-draw-highlight x y w h (cons 'outline f))
                     (ui-draw-label (+ x 6) y (- w 12) h '() "Entry")
                     (ui-draw-highlight-over x y w h (cons 'outline f))))]
           [y (row y "ui-draw-highlight popup" rh
                   (lambda (x y w h f)
                     (ui-draw-panel x y w h '(menu))
                     (ui-draw-highlight (+ x 4) (+ y 4) (- w 8) (- h 8)
                                        (cons 'popup f))
                     (ui-draw-label (+ x 10) y (- w 20) h '() "Entry")))]
           [y (row y "ui-draw-card" (* 2 rh)
                   (lambda (x y w h f)
                     (fill-box x y w h 'bg-2 (ui-card-radius))
                     (ui-draw-card x y w h f)))]
           [y (row y "ui-draw-scrollbar" (* 2 rh)
                   (lambda (x y w h f)
                     (ui-draw-scrollbar x y (ui-scrollbar-width) h f 1/5 2/5)))]
           [y (row y "ui-draw-scrollbar across" rh
                   (lambda (x y w h f)
                     (let ([bw (ui-scrollbar-width)])
                       (with-transpose
                         (ui-draw-scrollbar y x bw w (cons 'across f)
                                            1/5 2/5)))))]
           [y (row y "ui-draw-split" rh
                   (lambda (x y w h f)
                     (ui-draw-split (+ x (quotient w 2)) y h f)))]
           [y (row y "ui-draw-split stacked" rh
                   (lambda (x y w h f)
                     (with-transpose
                       (ui-draw-split (+ y (quotient h 2)) x w f))))]
           [y (row y "ui-draw-focus" rh
                   (lambda (x y w h f) (ui-draw-focus (+ x 4) (+ y 4) (- w 8)
                                                      (- h 8) f 6)))]
           [y (row y "ui-draw-glyph" rh
                   (lambda (x y w h f) (ui-draw-glyph x y g h f 'gear)))]
           [y (row y "ui-draw-busy" rh
                   (lambda (x y w h f)
                     (let-values ([(bw bh) (ui-busy-size)])
                       (ui-draw-busy x y bw bh f (now-ms)))))]
           [y (row y "ui-draw-app-icon" rh
                   (lambda (x y w h f) (ui-draw-app-icon x y h f 'widgets)))]
           [y (row y "ui-draw-window-icon" rh
                   (lambda (x y w h f) (ui-draw-window-icon win x y h f)))]
           [y (row y "ui-draw-env-icon" rh
                   (lambda (x y w h f) (ui-draw-env-icon x y h f 'sandbox)))]
           [y (row y "ui-draw-avatar" rh
                   (lambda (x y w h f)
                     (let-values ([(aw ah) (ui-avatar-size f "Ada Lovelace")])
                       (ui-draw-avatar x y aw ah f "Ada Lovelace"))))]
           [y (row y "ui-draw-progress" rh
                   (lambda (x y w h f)
                     (ui-draw-progress x y w (ui-progress-height) f 3/5)))]
           [y (row y "ui-draw-sparkline" rh
                   (lambda (x y w h f)
                     (ui-draw-sparkline x y w h f '(3 5 2 8 4 6 9 5))))]
           [y (row y "ui-draw-label" rh
                   (lambda (x y w h f) (ui-draw-label x y w h f "Label")))]
           [y (widgets-heading x y w "Parts by kind")]
           [y (kinds y "ui-draw-label" (+ rh sh)
                     '("heading" "body" "dim" "hint" "section" "group"
                       "error")
                     (lambda (x y w h i)
                       (ui-draw-label x y w h
                                      (list (list-ref '(heading body dim hint
                                                        section group error)
                                                      i))
                                      "Label")))]
           [y (kinds y "ui-draw-label" (+ rh sh)
                     '("mono" "wrap" "center" "right")
                     (lambda (x y w h i)
                       (ui-draw-label x y w h
                                      (list (list-ref '(mono wrap center
                                                        right)
                                                      i))
                                      "Label, wrapped when it is long")))]
           [y (kinds y "ui-draw-surface" (+ rh sh)
                     '("page" "toolbar" "footer" "side" "nav" "well"
                       "floating")
                     (lambda (x y w h i)
                       (ui-draw-surface x y w h
                                        (list (list-ref '(page toolbar footer
                                                          side nav well
                                                          floating)
                                                        i)))))]
           [y (kinds y "ui-draw-panel" (+ rh sh)
                     '("flat" "menu" "toast" "dialog" "tooltip")
                     (lambda (x y w h i)
                       (ui-draw-panel x y w h
                                      (list-ref '(() (menu) (toast) (dialog)
                                                  (tooltip))
                                                i))))]
           [y (kinds y "ui-draw-mark" (+ rh sh)
                     '("level 1 of 4" "level 3 of 4" "circle" "diamond"
                       "square" "blocked" "dot")
                     (lambda (x y w h i)
                       (ui-draw-mark x y (ui-mark-size)
                                     (list-ref '((level 1 4) (level 3 4)
                                                 circle diamond square
                                                 blocked dot)
                                               i)
                                     'orange)))]
           [y (kinds y "ui-draw-due" (+ rh sh)
                     '("past" "today" "none")
                     (lambda (x y w h i)
                       (ui-draw-due x y w "Due Friday"
                                    (list-ref '(past today #f) i) 'ui)))]
           [y (kinds y "ui-draw-env-icon" (+ rh sh)
                     '("root" "worklets" "thread" "sandbox" "world" "private"
                       "pure")
                     (lambda (x y w h i)
                       (ui-draw-env-icon x y h '()
                                         (list-ref '(root worklets thread
                                                     sandbox world private
                                                     pure)
                                                   i))))]
           [y (kinds y "ui-draw-busy" (+ rh sh)
                     '("plain" "hover" "bar")
                     (lambda (x y w h i)
                       (let-values ([(bw bh) (ui-busy-size)])
                         (ui-draw-busy x y bw bh
                                       (list-ref '(() (hover) (bar)) i)
                                       (now-ms)))))]
           [y (fold-left
               (lambda (y names)
                 (kinds y "ui-draw-glyph" (+ rh sh)
                        (map symbol->string names)
                        (lambda (x y w h i)
                          (ui-draw-glyph x y g g '() (list-ref names i)))))
               y
               '((check cross plus minus edit prompt search)
                 (chevron-down chevron-up chevron-left chevron-right up down
                  left)
                 (right home file drive folder box chip)
                 (gear globe expand pin undo panel-right panel-left)
                 (panel-right-shown panel-left-shown close minimize maximize
                  restore shade)))]
           [y (kinds y "ui-draw-separator, scrim" (+ rh sh)
                     '("separator" "scrim")
                     (lambda (x y w h i)
                       (case i
                         [(0) (ui-draw-separator x y w h '())]
                         [else (ui-draw-label x y w h '() "Under it")
                               (ui-draw-scrim x y w h '())])))]
           [y (kinds y "ui-draw-board-…" (+ (* 2 rh) sh)
                     '("slot" "link" "last link")
                     (lambda (x y w h i)
                       (case i
                         [(0) (ui-draw-board-slot x y w h)]
                         [else (let ([half (quotient h 2)])
                                 (fill-box x y w half 'bg-2 (ui-card-radius))
                                 (ui-draw-card x y w half '())
                                 (ui-draw-board-link x y w half '()
                                                     (- h half) (= i 2)))])))]
           [y (widgets-heading x y w "Popups and pieces at their sizes")]
           [y (let*-values ([(cw ch) (with-place 'dialog ui-calendar-size)]
                            [(tw th) (with-place 'tooltip
                                       (lambda ()
                                         (ui-tooltip-size
                                          "A tooltip, which wraps when its \
                                           words are many")))]
                            [(bx) (+ x cw gap)])
                (with-place 'dialog
                  (lambda ()
                    (ui-draw-calendar x y cw ch '() "September 2026")
                    (let* ([a (cdr (assq 'grid (ui-calendar-areas x y cw ch)))]
                           [cell (caddr a)])
                      (do ([i 0 (+ i 1)]) ((= i 42))
                        (let ([day (+ i -1)])
                          (ui-draw-day (+ (car a) (* cell (mod i 7)))
                                       (+ (cadr a) (* cell (div i 7)))
                                       cell cell
                                       (append
                                        (if (or (< day 1) (> day 30))
                                            '(outside)
                                            '())
                                        (case day
                                          [(14) '(today)]
                                          [(16) '(selected)]
                                          [(18) '(cursor)]
                                          [(20) '(hover)]
                                          [else '()]))
                                       (number->string
                                        (cond [(< day 1) (+ day 31)]
                                              [(> day 30) (- day 30)]
                                              [else day]))))))))
                (with-place 'tooltip
                  (lambda ()
                    (ui-draw-tooltip bx y tw th '()
                                     "A tooltip, which wraps when its \
                                      words are many")))
                (let ([by (+ y th gap)] [bw (max 200 (- right bx))])
                  (ui-draw-banner bx by bw (ui-banner-height) '()
                                  "A banner's strip" "Act")
                  (ui-draw-board-column bx (+ by (ui-banner-height) gap)
                                        (min bw 220) 160 '(empty) "Column" 0
                                        'accent "No cards"))
                (+ y ch gap))]
           [y (with-place 'dialog
                (lambda ()
                  (let*-values ([(labels) '("Cancel" "OK")]
                                [(dw dh) (ui-dialog-size "A dialog"
                                                         "Its message" labels)]
                                [(sw) (+ dw 40)] [(sh) (+ dh 40)])
                    (ui-draw-label x y 160 sh '(dim) "Under the scrim")
                    (ui-draw-scrim x y sw sh '())
                    (ui-draw-dialog (+ x 20) (+ y 20) dw dh
                                    (list (cons 'labels labels))
                                    "A dialog" "Its message")
                    (for-each (lambda (a l)
                                (apply ui-draw-button
                                       (append (cdr a)
                                               (list '() l #f))))
                              (filter (lambda (a) (eq? (car a) 'button))
                                      (ui-dialog-areas (+ x 20) (+ y 20) dw dh
                                                       labels))
                              labels)
                    (+ y sh gap))))]
           [y (let ([pw (min 320 (- right x))] [ph 220])
                (widgets-frame x y pw ph)
                (ui-draw-status-page x y pw ph '() 'folder "Nothing here"
                                     "What to do about it" #f)
                (ui-draw-line-chart (+ x pw gap) y (min 320 pw) 100 '()
                                    '((chart-1 1 4 2 6 3 7)
                                      (chart-3 2 2 3 3 5 4)))
                (ui-draw-legend (+ x pw gap) (+ y 100 4) (min 320 pw) sh '()
                                '((chart-1 . "One") (chart-3 . "Two")))
                (+ y ph gap))]
           [y (widgets-heading x y w "Sizes")]
           [y (size y "ui-control-height, glyph, small, gap, pad"
                    (lambda ()
                      (values (ui-control-height) (ui-glyph-size)
                              (ui-small-glyph-size) (ui-gap) (ui-pad))))]
           [y (size y "ui-slider-height, progress, scrollbar"
                    (lambda ()
                      (values (ui-slider-height) (ui-progress-height)
                              (ui-scrollbar-width))))]
           [y (size y "ui-table-header-, row-height, inset"
                    (lambda ()
                      (values (ui-table-header-height) (ui-table-row-height)
                              (ui-table-cell-inset))))]
           [y (size y "ui-button-size \"Button\" #f"
                    (lambda () (ui-button-size "Button" #f)))]
           [y (size y "ui-button-size #f 'gear"
                    (lambda () (ui-button-size #f 'gear)))]
           [y (size y "ui-checkbox-size \"Check\""
                    (lambda () (ui-checkbox-size "Check")))]
           [y (size y "ui-toggle-size \"Toggle\", track"
                    (lambda ()
                      (let-values ([(w h) (ui-toggle-size "Toggle")]
                                   [(tw th) (ui-toggle-track)])
                        (values w h tw th))))]
           [y (size y "ui-radio-size \"Radio\" hint #f 200"
                    (lambda () (ui-radio-size "Radio" "A hint" #f 200)))]
           [y (size y "ui-tabs-size '(\"One\" \"Two\")"
                    (lambda () (ui-tabs-size '("One" "Two"))))]
           [y (size y "ui-label-size '(section) …"
                    (lambda () (ui-label-size '(section) "Section" 200)))]
           [y (size y "ui-text-box-size '(field) 200 1"
                    (lambda ()
                      (with-place 'field
                        (lambda () (ui-text-box-size '(field) 200 1)))))]
           [y (size y "ui-text-area-size … 200 \"\" 3 5"
                    (lambda ()
                      (ui-text-area-size ui 'states-area '(lines) 200 "" 3
                                         5)))]
           [y (size y "ui-text-y 0 'ui" (lambda () (ui-text-y 0 'ui)))]
           [y (size y "ui-live-badge-size #t, #f \"Held\""
                    (lambda ()
                      (let-values ([(a b) (ui-live-badge-size #t "Live")]
                                   [(c d) (ui-live-badge-size #f "Held")])
                        (values a b c d))))]
           [y (size y "ui-busy-size" ui-busy-size)]
           [y (size y "ui-chip-size \"tag\" #t"
                    (lambda () (ui-chip-size "tag" #t)))]
           [y (size y "ui-chip-input-size 200 '(\"a\" \"b\")"
                    (lambda ()
                      (with-place 'field
                        (lambda () (ui-chip-input-size 200 '("a" "b"))))))]
           [y (size y "ui-avatar-size '(), '(named)"
                    (lambda ()
                      (let-values ([(a b) (ui-avatar-size '() "Ada")]
                                   [(c d) (ui-avatar-size '(named) "Ada")])
                        (values a b c d))))]
           [y (size y "ui-legend-size"
                    (lambda () (ui-legend-size '((chart-1 . "One")))))]
           [y (size y "ui-dropdown-size '(\"Choice\")"
                    (lambda () (ui-dropdown-size '("Choice"))))]
           [y (size y "ui-calendar-size"
                    (lambda () (with-place 'dialog ui-calendar-size)))]
           [y (size y "ui-dialog-size \"Title\" \"Message\" '(\"OK\")"
                    (lambda ()
                      (with-place 'dialog
                        (lambda () (ui-dialog-size "Title" "Message"
                                                   '("OK"))))))]
           [y (size y "ui-tooltip-size \"Tip\""
                    (lambda ()
                      (with-place 'tooltip
                        (lambda () (ui-tooltip-size "Tip")))))]
           [y (size y "ui-row-height \"T\" \"S\", ui-add-row-height"
                    (lambda ()
                      (values (ui-row-height "Title" "Subtitle")
                              (ui-add-row-height))))]
           [y (size y "ui-rows-spacing, ui-rows-radius"
                    (lambda ()
                      (let-values ([(a b) (ui-rows-spacing)])
                        (values a b (ui-rows-radius)))))]
           [y (size y "ui-banner-height, ui-mark-size"
                    (lambda () (values (ui-banner-height) (ui-mark-size))))]
           [y (size y "ui-card-radius, card-pad, panel-pad"
                    (lambda ()
                      (values (ui-card-radius) (ui-card-pad) (ui-panel-pad))))]
           [y (size y "ui-board-header-height, …-column-insets"
                    (lambda ()
                      (let-values ([(a b c d) (ui-board-column-insets)])
                        (values (ui-board-header-height) a b c d))))]
           [y (size y "ui-board-card-insets" ui-board-card-insets)]
           [y (widgets-heading x y w "Areas")]
           [y (areas y "ui-text-box-areas '(field)" 240 ch
                     (lambda (ax ay)
                       (with-place 'field
                         (lambda ()
                           (ui-text-box-areas ax ay 240 ch '(field))))))]
           [y (areas y "ui-stepper-areas" 160 ch
                     (lambda (ax ay) (ui-stepper-areas ax ay 160 ch)))]
           [y (areas y "ui-row-areas, prefix and suffix" 320 (+ ch 12)
                     (lambda (ax ay)
                       (ui-row-areas ax ay 320 (+ ch 12) 24 60)))]
           [y (areas y "ui-tree-areas, depth 2" 240 (ui-table-row-height)
                     (lambda (ax ay)
                       (ui-tree-areas ax ay 240 (ui-table-row-height) 2)))]
           [y (areas y "ui-chip-areas" 80 ch
                     (lambda (ax ay) (ui-chip-areas ax ay 80 ch)))]
           [y (areas y "ui-chip-input-areas" 320 (* 2 ch)
                     (lambda (ax ay)
                       (with-place 'field
                         (lambda ()
                           (ui-chip-input-areas ax ay 320
                                                '("one" "two" "three"))))))]
           [y (areas y "ui-scrollbar-areas" (ui-scrollbar-width) 160
                     (lambda (ax ay)
                       (ui-scrollbar-areas ax ay (ui-scrollbar-width) 160
                                           1/5 2/5)))]
           [y (areas y "ui-banner-areas" 320 (ui-banner-height)
                     (lambda (ax ay)
                       (ui-banner-areas ax ay 320 (ui-banner-height) "Title"
                                        "Act")))]
           [y (let-values ([(cw ch) (with-place 'dialog ui-calendar-size)])
                (areas y "ui-calendar-areas" cw ch
                       (lambda (ax ay)
                         (with-place 'dialog
                           (lambda () (ui-calendar-areas ax ay cw ch))))))]
           [y (let-values ([(dw dh) (with-place 'dialog
                                      (lambda ()
                                        (ui-dialog-size "Title" "Message"
                                                        '("Cancel" "OK"))))])
                (areas y "ui-dialog-areas" dw dh
                       (lambda (ax ay)
                         (with-place 'dialog
                           (lambda ()
                             (ui-dialog-areas ax ay dw dh
                                              '("Cancel" "OK")))))))]
           [y (areas y "ui-status-page-areas" 320 240
                     (lambda (ax ay)
                       (ui-status-page-areas ax ay 320 240 '() "Title"
                                             "Description" "Button")))])
      (values right y))))
