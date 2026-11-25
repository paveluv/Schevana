;;; (demo widgets controls) — the Widgets demo's pages of controls and of
;;; text: every button, choice, value and key of the kit, and its text
;;; boxes, live and inside ui-disabled. The window keeps each value.

(library (demo widgets controls)
  (export widgets-controls-page widgets-text-page)
  (import (chezscheme)
          (schevana core)
          (schevana kits ui)
          (demo widgets layout))

  ;; Returns (values right bottom) of the page drawn from (x, y), w wide.
  (define (widgets-controls-page ui win x y w)
    (let* ([ch (ui-control-height)] [gap (ui-gap)]
           [get (lambda (key default) (window-ref win key default))]
           [say (lambda (text) (widgets-said win text))]
           [keep (lambda (key) (widgets-keep win key))]
           [y (widgets-heading x y w "Buttons")]
           [y (widgets-flow x y w
                (list (widgets-width "Plain") ch
                      (lambda (x y w h)
                        (ui-button ui 'plain x y w h "Plain"
                                   (say "Pressed Plain"))))
                (list (widgets-width "Primary") ch
                      (lambda (x y w h)
                        (ui-button ui 'primary x y w h "Primary"
                                   (say "Pressed Primary") 'primary #t)))
                (list (widgets-width "Danger") ch
                      (lambda (x y w h)
                        (ui-button ui 'danger x y w h "Danger"
                                   (say "Pressed Danger") 'danger #t)))
                (list (widgets-width "Quiet") ch
                      (lambda (x y w h)
                        (ui-button ui 'quiet x y w h "Quiet"
                                   (say "Pressed Quiet") 'quiet #t)))
                (list (widgets-width "Selected") ch
                      (lambda (x y w h)
                        (ui-button ui 'selected x y w h "Selected"
                                   (say "Pressed Selected") 'selected #t)))
                (list (widgets-width "Pill") ch
                      (lambda (x y w h)
                        (ui-button ui 'pill x y w h "Pill"
                                   (say "Pressed Pill") 'pill #t)))
                (list (widgets-width "Add" 'plus) ch
                      (lambda (x y w h)
                        (ui-button ui 'add x y w h "Add" (say "Pressed Add")
                                   'glyph 'plus)))
                (list (widgets-width #f 'gear) ch
                      (lambda (x y w h)
                        (ui-button ui 'gear x y w h #f (say "Pressed the gear")
                                   'glyph 'gear 'tip "A glyph alone")))
                (list (widgets-width #f 'cross) ch
                      (lambda (x y w h)
                        (ui-button ui 'round x y w h #f
                                   (say "Pressed the round button")
                                   'glyph 'cross 'circular #t
                                   'tip "A round button")))
                (list (widgets-width "Disabled") ch
                      (lambda (x y w h)
                        (ui-button ui 'disabled x y w h "Disabled"
                                   (say "A disabled button did something")
                                   'disabled #t
                                   'tip "Disabled: a tooltip still shows"))))]
           [y (begin
                (ui-linked ui 'align x y ch
                           (list (list 'left "Left" (say "Aligned left"))
                                 (list 'center "Center" (say "Centered")
                                       'selected #t)
                                 (list 'right "Right" (say "Aligned right"))))
                (+ y ch gap))]
           [y (widgets-heading x y w "Choices")]
           [y (widgets-flow x y w
                (let-values ([(bw bh) (ui-checkbox-size "Checked")])
                  (list bw bh
                        (lambda (x y w h)
                          (ui-checkbox ui 'check-a x y w h "Checked"
                                       (get 'check-a #t) (keep 'check-a)))))
                (let-values ([(bw bh) (ui-checkbox-size "Not checked")])
                  (list bw bh
                        (lambda (x y w h)
                          (ui-checkbox ui 'check-b x y w h "Not checked"
                                       (get 'check-b #f) (keep 'check-b)))))
                (let-values ([(bw bh) (ui-checkbox-size "Disabled")])
                  (list bw bh
                        (lambda (x y w h)
                          (ui-checkbox ui 'check-c x y w h "Disabled" #t
                                       (keep 'check-c) 'disabled #t
                                       'tip "A disabled checkbox"))))
                (list (ui-checkbox-box) ch
                      (lambda (x y w h)
                        (ui-checkbox ui 'check-d x y w h #f (get 'check-d #f)
                                     (keep 'check-d) 'tip "A box alone")))
                (let-values ([(bw bh) (ui-toggle-size "Toggle")])
                  (list bw bh
                        (lambda (x y w h)
                          (ui-toggle ui 'toggle-a x y w h "Toggle"
                                     (get 'toggle-a #f) (keep 'toggle-a)))))
                (let-values ([(bw bh) (ui-toggle-size "On")])
                  (list bw bh
                        (lambda (x y w h)
                          (ui-toggle ui 'toggle-b x y w h "On"
                                     (get 'toggle-b #t) (keep 'toggle-b))))))]
           [y (let* ([rw (min w 260)]
                     [size (get 'size 'medium)]
                     [radio (lambda (y id label hint . opts)
                              (let-values ([(bw bh) (ui-radio-size
                                                     label hint #f rw)])
                                (apply ui-radio ui id x y rw bh label
                                       (eq? size id)
                                       (lambda () ((keep 'size) id))
                                       'hint hint opts)
                                (+ y bh)))])
                (+ gap
                   (radio (radio (radio y 'small "Small" #f)
                                 'medium "Medium" "A hint under the label")
                          'large "Large" #f 'disabled #t
                          'tip "A disabled choice")))]
           [y (let* ([choices '(("Day" . day) ("Week" . week)
                                ("Month" . month))]
                     [sw (* 3 (+ (widgets-width "Month") gap))])
                (ui-segmented ui 'span x y sw ch choices (get 'span 'week)
                              (keep 'span) 'tip "A segmented choice")
                (+ y ch gap))]
           [y (let-values ([(tw th) (ui-tabs-size '("General" "Fonts"
                                                    "Advanced"))])
                (ui-tabs ui 'tab x y th
                         '(("General" . general) ("Fonts" . fonts)
                           ("Advanced" . advanced))
                         (get 'tab 'general) (keep 'tab))
                (+ y th gap))]
           [y (widgets-heading x y w "Values")]
           [y (let* ([sw (min 240 (- w 80))] [sh (ui-slider-height)]
                     [volume (get 'volume 40)])
                (ui-slider ui 'volume (+ x 8) y sw volume 0 100
                           (lambda (v) ((keep 'volume) (exact (round v))))
                           #f 'tip "A slider, its value beside it")
                (ui-draw-label (+ x sw 24) y 60 sh '()
                               (number->string volume))
                (ui-disabled ui
                  (lambda ()
                    (ui-slider ui 'volume-off (+ x sw 80) y (min sw 160)
                               volume 0 100 void #f
                               'tip "A slider under ui-disabled")))
                (+ y sh gap))]
           [y (let*-values ([(lw lh) (ui-label-size '(dim) "Copies" w)]
                            [(sx) (+ x lw gap)])
                (ui-draw-label x y lw ch '(dim) "Copies")
                (let ([sw (ui-stepper ui 'copies sx y (get 'copies 3) 1 99
                                      (keep 'copies) 'tip "From 1 to 99")])
                  (ui-draw-label (+ sx sw gap gap) y lw ch '(dim) "Low")
                  (ui-stepper ui 'low (+ sx sw gap gap lw gap) y
                              (get 'low -2) -5 5 (keep 'low)))
                (+ y ch gap))]
           [y (let*-values ([(dw dh) (ui-dropdown-size '("Red" "Green"
                                                         "Pick one…"))]
                            [(date-w date-h) (ui-dropdown-size
                                              '("Sep 30, 2026" "No date"))])
                (widgets-flow x y w
                  (list dw dh
                        (lambda (x y w h)
                          (ui-dropdown ui 'color x y w h
                                       '(("Red" . red) ("Green" . green)
                                         ("Blue" . blue))
                                       (get 'color 'green) (keep 'color)
                                       'tip "A dropdown")))
                  (list dw dh
                        (lambda (x y w h)
                          (ui-dropdown ui 'filter x y w h
                                       '(("Any" . any) ("Red" . red)
                                         ("Blue" . blue))
                                       (get 'filter 'red) (keep 'filter)
                                       'set (not (eq? (get 'filter 'red)
                                                      'any))
                                       'tip "A filter in use: 'set")))
                  (list dw dh
                        (lambda (x y w h)
                          (ui-dropdown ui 'labeled x y w h
                                       '(("Red" . red) ("Blue" . blue))
                                       #f (keep 'labeled)
                                       'label "Pick one…")))
                  (list date-w date-h
                        (lambda (x y w h)
                          (ui-date-field ui 'due x y w h (get 'due '(2026 9 30))
                                         (keep 'due) 'tip "A date field")))
                  (list date-w date-h
                        (lambda (x y w h)
                          (ui-date-field ui 'no-due x y w h (get 'no-due #f)
                                         (keep 'no-due)
                                         'placeholder "No date")))))]
           [y (let ([tags (get 'tags '("ui" "demo" "styles"))])
                (+ gap
                   (ui-chip-input ui 'tags x y (min w 420) tags (get 'draft "")
                                  (keep 'draft)
                                  (lambda (new)
                                    (window-set! win 'draft "")
                                    ((keep 'tags) (append tags new)))
                                  (lambda (i)
                                    ((keep 'tags)
                                     (append (list-head tags i)
                                             (list-tail tags (+ i 1)))))
                                  'placeholder "Add a tag")))]
           [y (let ([chips (get 'chips '("alpha" "beta" "gamma"))])
                (+ gap
                   (ui-chips ui 'chips x y (min w 420) chips
                             (lambda (i)
                               (widgets-say! win (format "Pressed the chip ~a"
                                                         (list-ref chips i))))
                             'on-remove
                             (lambda (i)
                               ((keep 'chips)
                                (append (list-head chips i)
                                        (list-tail chips (+ i 1)))))
                             'add (lambda ()
                                    ((keep 'chips)
                                     (append chips
                                             (list (format "chip-~a"
                                                           (length chips))))))
                             'tip (lambda (i) (list-ref chips i)))))]
           [y (+ gap (ui-chips ui 'no-chips x y (min w 420) '() #f
                               'empty "No chips: the words for none"))]
           [y (widgets-heading x y w "Keys")]
           [y (widgets-flow x y w
                (list (widgets-width "Help") ch
                      (lambda (x y w h)
                        (ui-keycap ui 'help x y w h "Help" (say "Help")
                                   '(#\space return))))
                (list (widgets-width "Abort") ch
                      (lambda (x y w h)
                        (ui-keycap ui 'abort x y w h "Abort" (say "Abort")
                                   '(#\space return))))
                (list (widgets-width "Resume") ch
                      (lambda (x y w h)
                        (ui-keycap ui 'resume x y w h "Resume" (say "Resume")
                                   '(#\space return)))))]
           [y (begin
                (ui-inline-choices ui 'answer x y ch
                                   '(("Yes" . yes) ("No" . no) ("Ask" . ask))
                                   (get 'answer 'yes) (keep 'answer))
                (+ y ch gap))]
           [y (widgets-heading x y w "Progress, live and busy")]
           [y (let ([pw (min 200 (quotient (- w (* 2 gap)) 3))]
                    [ph (ui-progress-height)])
                (for-each (lambda (frac i)
                            (let ([px (+ x (* i (+ pw gap)))])
                              (ui-draw-progress px y pw ph '() frac)
                              (ui-draw-label px (+ y ph 4) pw ch '(hint)
                                             (format "~a%" (* 100 frac)))))
                          '(0 3/5 1) '(0 1 2))
                (+ y ph 4 ch gap))]
           [y (let ([live? (get 'live #t)] [held "Held at 12:00"])
                (widgets-flow x y w
                  (let-values ([(bw bh) (ui-live-badge-size live? held)])
                    (list bw bh
                          (lambda (x y w h)
                            (ui-live-badge ui 'live x y w h live? held
                                           (keep 'live)))))
                  (let-values ([(bw bh) (ui-busy-size)])
                    (list bw bh
                          (lambda (x y w h)
                            (ui-draw-busy x y w h '() (now-ms))
                            (ui-due! ui (+ (now-ms) (ui-busy-frame-ms))))))
                  (list (widgets-width "Busy, in its style") ch
                        (lambda (x y w h)
                          (ui-draw-label x y w h '(hint)
                                         "Busy, in its style")))))]
           [y (let ([crumbs '("Home" "Projects" "Schevana" "demo" "widgets")]
                    [pick (lambda (i)
                            (widgets-say! win (format "Went to crumb ~a" i)))])
                (ui-breadcrumbs ui 'crumbs x y (min w 480) ch crumbs pick)
                (ui-breadcrumbs ui 'crumbs-short x (+ y ch gap) (min w 200) ch
                                crumbs pick)
                (+ y ch gap ch gap))])
      (values (+ x w) y)))

  ;; Draws the text boxes from (x, y), w wide, each named key-…, its id
  ;; and the window's key for its text, and returns the y under them.
  (define (widgets-text-boxes ui win key x y w)
    (let* ([ch (ui-control-height)] [gap (ui-gap)]
           [id (lambda (name) (string->symbol (format "~a-~a" key name)))]
           [get (lambda (name default) (window-ref win (id name) default))]
           [keep (lambda (name) (widgets-keep win (id name)))]
           [fw (min w 360)]
           [y (begin
                (ui-text-field ui (id 'name) x y fw ch
                               (get 'name "Ada Lovelace") (keep 'name)
                               'tip "A text field")
                (+ y ch gap))]
           [y (begin
                (ui-text-field ui (id 'email) x y fw ch (get 'email "")
                               (keep 'email) 'placeholder "name@example.org"
                               'tip "Its placeholder shows while it is empty")
                (+ y ch gap))]
           [y (begin
                (ui-text-field ui (id 'long) x y fw ch
                               (get 'long
                                    "A line far longer than its field, which \
                                     scrolls sideways under the caret as it \
                                     moves along")
                               (keep 'long))
                (+ y ch gap))]
           [y (begin
                (ui-text-field ui (id 'search) x y fw ch (get 'search "")
                               (keep 'search) 'search #t
                               'placeholder "Search the styles"
                               'suggest (lambda (text)
                                          (ui-suggestions
                                           text
                                           (map symbol->string (styles))
                                           8)))
                (+ y ch gap))]
           [y (let ([nw (min fw 160)])
                (ui-text-field ui (id 'number) x y nw ch (get 'number "1234.5")
                               (keep 'number) 'right #t
                               'tip "'right: at its right while it fits")
                (ui-text-field ui (id 'pin) (+ x nw gap) y (min nw 100) ch
                               (get 'pin "") (keep 'pin) 'max 4
                               'placeholder "PIN" 'tip "'max 4")
                (+ y ch gap))]
           [y (let-values ([(lw lh) (ui-text-box-size '(field large) fw 1)])
                (ui-text-field ui (id 'title) x y fw lh (get 'title "A title")
                               (keep 'title) 'large #t)
                (+ y lh gap))]
           [y (let* ([text (get 'notes
                                "A text area: its lines wrap at its width, \
                                 and past its most rows a scroll bar shows.\n\
                                 Second paragraph.\nThird.\nFourth.\n\
                                 Fifth.\nSixth.\nSeventh.\nEighth.")])
                (let-values ([(aw ah) (ui-text-area-size ui (id 'notes)
                                                         '(lines) fw text 3 5)])
                  (ui-text-area ui (id 'notes) x y fw ah text (keep 'notes)
                                'tip "A text area")
                  (+ y ah gap)))])
      y))

  ;; Returns (values right bottom) of the page drawn from (x, y), w wide.
  (define (widgets-text-page ui win x y w)
    (let* ([ch (ui-control-height)] [gap (ui-gap)]
           [off? (window-ref win 'text-off #t)]
           [y (widgets-heading x y w "Text boxes")]
           [y (widgets-text-boxes ui win 'live x y w)]
           [y (widgets-heading x y w "Inside ui-disabled")]
           [y (widgets-note x y w
                "Each shows disabled, keeps its place and its tooltip, and \
                 takes no input; Tab passes it by.")]
           [y (let-values ([(tw th) (ui-toggle-size "Disabled")])
                (ui-toggle ui 'text-off x y tw th "Disabled" off?
                           (widgets-keep win 'text-off))
                (+ y th gap))]
           [section
            (lambda ()
              (let* ([y (widgets-text-boxes ui win 'off x y w)]
                     [y (widgets-flow x y w
                          (list (widgets-width "Button") ch
                                (lambda (x y w h)
                                  (ui-button ui 'off-button x y w h "Button"
                                             (widgets-said win "Pressed")
                                             'tip "A button's tip")))
                          (let-values ([(bw bh) (ui-checkbox-size "Check")])
                            (list bw bh
                                  (lambda (x y w h)
                                    (ui-checkbox ui 'off-check x y w h "Check"
                                                 #t void))))
                          (let-values ([(dw dh) (ui-dropdown-size
                                                 '("Choice"))])
                            (list dw dh
                                  (lambda (x y w h)
                                    (ui-dropdown ui 'off-choice x y w h
                                                 '(("Choice" . a)) 'a void))))
                          (let-values ([(dw dh) (ui-dropdown-size
                                                 '("Sep 30, 2026"))])
                            (list dw dh
                                  (lambda (x y w h)
                                    (ui-date-field ui 'off-date x y w h
                                                   '(2026 9 30) void)))))])
                y))])
      (values (+ x w) (if off? (ui-disabled ui section) (section))))))
