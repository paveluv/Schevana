# Widgets

`(schevana kits ui)` is the widget kit that every app here is built
with: buttons, text, choices, tables, trees, scroll views, menus, dialogs
and charts. It gives the names of its parts, in `schevana/kits/ui/`: the
base (the state, events, focus, scrolling, popups and the shared drawing),
the controls, text, lists, charts and pages, each built on those before
it. It is immediate-mode, so there is no tree of widget objects.
Each time a window draws, its draw procedure calls one procedure for each
widget, at the place where the widget goes. The widget draws itself and
records where it can be pressed, and the window's handlers ask the kit
what was hit. So the draw procedure is the layout, and the app keeps no
state but its own data.

## A button

```scheme
(define presses 0)
(define kit (make-ui))
(define hello
  (apply open-window "Hello, kit" 'size '(260 . 80)
    'draw (lambda (win w h)
            (ui-begin! kit)
            (ui-button kit 'hi 20 20 140 (ui-control-height) "Press me"
                       (lambda () (set! presses (+ presses 1))))
            (ui-end! kit w h))
    (ui-handlers kit)))
```

A `ui` holds what the kit remembers between draws: which widget the
pointer is over, which one has the keyboard, and each scroll view's
offset. `ui-begin!` and `ui-end!` go around a draw. `ui-handlers` gives
the window the kit's handlers for the mouse, the wheel, keys and typed
text, and keeps the `ui` in the window as its `'ui` property, where the
examples below find it (`(window-ref win 'ui)`). Each widget has an id
(`'hi` here) that is unique in its window.

Press the button as a person would:

```scheme
(focus-window! hello)
(let-values ([(x y w h) (content-rect hello)])
  (inject! `(mouse-move ,(+ x 40) ,(+ y 30))
           `(mouse-down ,(+ x 40) ,(+ y 30) left 1)
           `(mouse-up ,(+ x 40) ,(+ y 30) left)))
(sleep-ms 50)
presses                                    ; => 1
```

A widget takes options after its arguments, each a key and its value:
`'tip` gives the widget a tooltip, and `'disabled #t` grays it out. A
button also takes `'primary`, `'danger` or `'quiet` (flat until the
pointer is on it), and `'pill` or `'circular` for round ends. `ui-linked`
puts buttons side by side as one group, with their inner sides joined:

```scheme
(apply open-window "Linked" 'size '(320 . 70)
  'draw (lambda (win w h)
          (let ([ui (window-ref win 'ui)])
            (ui-begin! ui)
            (ui-linked ui 'align 20 20 (ui-control-height)
                       (list (list 'left "Left" (lambda () #f))
                             (list 'center "Center" (lambda () #f))
                             (list 'right "Right" (lambda () #f))))
            (ui-end! ui w h)))
  (ui-handlers (make-ui)))
```

## Values and changes

A widget shows the value it is given, and when the person changes it,
calls a procedure with the new value; the app keeps the value. Here the
window keeps each value, with `window-set!`, which also draws the window
again:

```scheme
(define (prefs-draw win w h)
  (let ([ui (window-ref win 'ui)] [ch (ui-control-height)]
        [set (lambda (key) (lambda (v) (window-set! win key v)))])
    (ui-begin! ui)
    (ui-form ui 'form 20 20 (- w 40)
      (list
       (list "Name" ch
             (lambda (x y w)
               (ui-text-field ui 'name x y w ch (window-ref win 'name)
                              (set 'name) 'placeholder "Your name")))
       (list "Copies" ch
             (lambda (x y w)
               (ui-stepper ui 'copies x y (window-ref win 'copies) 1 99
                           (set 'copies))))
       (list "Volume" (ui-slider-height)
             (lambda (x y w)
               (ui-slider ui 'volume x y w (window-ref win 'volume) 0 100
                          (set 'volume))))
       (list "Color" ch
             (lambda (x y w)
               (ui-dropdown ui 'color x y w ch
                            '(("Accent" . accent) ("Green" . green))
                            (window-ref win 'color) (set 'color))))
       (list "Due" ch
             (lambda (x y w)
               (ui-date-field ui 'due x y w ch (window-ref win 'due)
                              (set 'due))))
       (list #f ch
             (lambda (x y w)
               (ui-checkbox ui 'sound x y w ch "Sound"
                            (window-ref win 'sound) (set 'sound))))
       (list #f ch
             (lambda (x y w)
               (ui-toggle ui 'dark x y w ch "Dark"
                          (window-ref win 'dark) (set 'dark))))))
    (ui-end! ui w h)))
(define prefs
  (apply open-window "Preferences" 'size '(420 . 330)
    'name "" 'copies 1 'volume 50 'color 'accent 'due #f
    'sound #t 'dark #f
    'draw (lambda (win w h) (prefs-draw win w h))
    (ui-handlers (make-ui))))
```

`ui-form` lays out rows, each a label and a control, given as `(label
height place)`: `place` draws the control at the x, y and width that the
form gives it, and a row whose label is `#f` spans the whole width. The
window calls `prefs-draw` by name, so redefining `prefs-draw` at the REPL
changes the window at once.

Typing goes to the focused widget. A click focuses a widget that takes
typing, Tab and Shift+Tab move through the widgets in the order they are
drawn, and Escape takes the focus away:

```scheme
(focus-window! prefs)
(inject! '(key-down tab ()))
(inject! '(text "Ada"))
(sleep-ms 50)
(window-ref prefs 'name)                   ; => "Ada"
```

A part of a form that can't be used now is drawn inside `ui-disabled`:
every widget in it shows disabled, keeps its place and its tooltip, and
takes no input, Tab passes it by, and what it opens over the rest (a
dialog, a calendar) is disabled too:

```scheme no-run
(ui-disabled ui
  (lambda ()
    (ui-text-field ui 'proxy 20 140 200 30 proxy-host set-proxy-host!)))
```

The kit has more widgets of this kind: `ui-radio` (one choice of
several, each choice its own widget), `ui-segmented` and `ui-tabs`
(choices side by side), `ui-text-area` (text of many lines), `ui-chips`
and `ui-chip-input` (tags), `ui-breadcrumbs` (a path), `ui-nav` (a list to
choose a page from), and `ui-live-badge` (whether a view is live or holds
still).

The Lisp machines' choices are here too, drawn by every style in its own
way. `ui-menu-grid` is a menu of columns, each a heading over its choices,
where one choice in all, one in each column, or each on its own may be
chosen (`'policy`: `single`, `columns` or `multiple`); a choice that can't
be had now is drawn as such. `ui-choice-grid` is a matrix of boxes to
tick, rows by columns, a cell that can't be had left blank. `ui-keycap`
is a button labeled with a key, and `ui-inline-choices` shows a few values
at once in a row, the current one marked:

```scheme no-run
(ui-menu-grid ui 'look 20 20 360
              '(("Size" ("Small" . small) ("Large" . large))
                ("Face" ("Serif" . serif) ("Mono" . mono)))
              chosen set-chosen! 'policy 'columns)
(ui-inline-choices ui 'answer 20 140 (ui-control-height)
                   '(("Yes" . yes) ("No" . no) ("Ask" . ask))
                   answer set-answer!)
```

## Rows, empty views and banners

Settings are often shown as a boxed list: a group of rows in one box,
under the group's title. Each row has a title, maybe a subtitle, and a
control at its end (a switch, a button, a value) or before its title (a
check box):

```scheme
(define (net-draw win w h)
  (let ([ui (window-ref win 'ui)]
        [set (lambda (key) (lambda (v) (window-set! win key v)))])
    (ui-begin! ui)
    (ui-draw-surface 0 0 w h '(page))
    (ui-rows ui 'net 20 20 (- w 40)
      (list (ui-switch-row ui 'wifi "Wi-Fi" (window-ref win 'wifi) (set 'wifi)
                           'subtitle "Connected")
            (ui-check-row ui 'metered "Metered" (window-ref win 'metered)
                          (set 'metered))
            (ui-entry-row ui 'proxy "Proxy" (window-ref win 'proxy)
                          (set 'proxy))
            (list "Details" #f 0 #f 'on-press (lambda () (notify "Details"))))
      'title "Network" 'description "How this machine connects")
    (ui-end! ui w h)))
(define net
  (apply open-window "Network" 'size '(420 . 380)
    'wifi #t 'metered #f 'proxy ""
    'draw (lambda (win w h) (net-draw win w h))
    (ui-handlers (make-ui))))
```

A row is `(title subtitle suffix-width suffix opt ...)`. `suffix`, a
`(lambda (x y w h) ...)`, draws what ends the row in a place
`suffix-width` wide, and the option `'on-press` makes the whole row a
button. `ui-switch-row`, `ui-check-row` and `ui-entry-row` make the common
kinds of row. `(ui-rows-height w rows opt ...)` returns how tall the box
will be before it is drawn, as `ui-form-height` does for a form.

A view with nothing to show says so with `ui-status-page`: a large
glyph, a title and a line on what to do, centered, with an optional
button. `ui-banner` is a strip across the top of a view with an action at
its end, and returns its height:

```scheme
(apply open-window "Empty" 'size '(380 . 320)
  'draw (lambda (win w h)
          (let ([ui (window-ref win 'ui)])
            (ui-begin! ui)
            (let ([top (ui-banner ui 'offline 0 0 w "Offline" "Retry"
                                  (lambda () (notify "Retrying")))])
              (ui-status-page ui 'empty 0 top w (- h top) 'folder "No Tasks"
                              "Add a task to see it here"
                              'button (list "Add Task" (lambda () #f))))
            (ui-end! ui w h)))
  (ui-handlers (make-ui)))
```

## Laying out

The kit's sizes are settings computed from the fonts, and a style may
give its own: `(ui-control-height)` is the height of a control, `(ui-gap)`
the space between controls, and `(ui-pad)` the space inside a box. Lay
widgets out from these, never from fixed pixels, and the layout stays
right in every style and at every text size.

```scheme
(ui-control-height)
(ui-gap)
(let-values ([(places height) (ui-flow 0 0 200 (ui-gap)
                                       '((80 . 24) (80 . 24) (80 . 24)))])
  places)                                  ; where each goes, wrapping at 200
```

`ui-flow` places items from left to right, wrapping them into rows, and
returns their places and the height they take. `ui-toolbar` does the same
for a bar of items, one of which may stretch. `ui-split` divides a width
at a line that the person can drag, and `ui-split-stacked` a height.
`(ui-side-panel ui id x y w h side width least rest panel)` lays a panel
along one side and the rest of the view beside it; when the panel is hidden, or when the rest would be
narrower than `least`, the rest gets all the room. With `'floating #t` the
panel lies over the rest instead, so the rest never changes size (Life's
grid works this way). `ui-side-panel-button` draws the panel's button,
which the app places where it has room, and `(ui-side-panel-toggle! ui
id)` shows or hides the panel from a key.

## Lists, tables and trees

A table draws only the rows that are in view, and the app draws each
cell:

```scheme
(define planets '(("Mercury" 0.39) ("Venus" 0.72) ("Earth" 1.0)
                  ("Mars" 1.52) ("Jupiter" 5.2) ("Saturn" 9.54)))
(define (planets-cell row key x y w h flags)
  (let ([text (if (eq? key 'name) (car row) (number->string (cadr row)))]
        [color (if (memq 'selected flags) 'bg-0 'text)])
    (if (memq 'right flags)                ; the column's flag
        (draw-text (- (+ x w) 6 (text-width text 'ui)) (+ y 4) text color 'ui)
        (draw-text (+ x 6) (+ y 4) text color 'ui))))
(define planets-window
  (let ([ui (make-ui)])
    (apply open-window "Planets" 'size '(320 . 220) 'selected #f
      'draw (lambda (win w h)
              (ui-begin! ui)
              (ui-table ui 'planets 0 0 w h
                        '((name "Planet" 160) (au "AU" 100 right))
                        planets (window-ref win 'selected)
                        (lambda (row) (window-set! win 'selected row))
                        planets-cell)
              (ui-end! ui w h))
      (ui-handlers ui))))
```

A column is `(key title width flag ...)`: the width is a default that
the person may change by dragging, and the flag `right` aligns the
column's cells at the right, as for numbers. Options add sorting by a
press on a heading (`'sort`, `'on-sort`), an action on a double click
(`'on-open`) and on a right press (`'on-menu`), a tooltip for each row
(`'tip`), and a checkbox before each row (`'checked`, `'on-check`).
`ui-tree` is a table whose first column holds a tree: it takes the roots
and a procedure that returns a node's children, and it draws a node's
children only while the node is expanded.

## Scrolling

```scheme
(let ([ui (make-ui)])
  (apply open-window "Long" 'size '(240 . 160)
    'draw (lambda (win w h)
            (ui-begin! ui)
            (ui-scroll ui 'v 0 0 w h
              (lambda (top)
                (do ([i 0 (+ i 1)]) ((= i 40))
                  (draw-text (max 10 (ui-scrollbar-inset 'left))
                             (+ top (* i 20)) (format "Line ~a" i)
                             'text 'ui))
                (+ top 800)))                   ; where the content ends
            (ui-end! ui w h))
    (ui-handlers ui)))
```

A scroll view's body draws its content starting at `top`, and returns
the y where the content ends. The wheel and the scroll bar move the
content; the style decides where the bar is and when it shows. The bar
lies over the view's edge, and content keeps clear of it by
`(ui-scrollbar-inset 'left)` and `(ui-scrollbar-inset 'right)`: the room
the style's bar takes on that side, 0 where it shows only under the
pointer (Genera's is at the left, most styles' at the right). A style
whose bars are there whether they are needed or not (Genera's,
`scrollbar-full`) shows one over content that fits, too.

Content wider than its view scrolls sideways too in `ui-scroll-wide`,
whose body takes `left` and `top` and returns where the content ends, as
`(values right bottom)`. A bar across the view's bottom moves it
sideways, as does the wheel turned sideways. That bar is the style's own
bar at the side, transposed (`ui-scrollbar-across`), so every style has
one in its own look; a style that wants to draw it differently finds
`across` among the flags its `ui-draw-scrollbar` part is handed. Where it
is always there it covers no content: the last of it scrolls up to the
bar.

```scheme
(let ([ui (make-ui)])
  (apply open-window "Wide" 'size '(240 . 160)
    'draw (lambda (win w h)
            (ui-begin! ui)
            (ui-scroll-wide ui 'v 0 0 w h
              (lambda (left top)
                (do ([i 0 (+ i 1)]) ((= i 40))
                  (draw-text (+ left (ui-scrollbar-inset 'left))
                             (+ top (* i 20))
                             (format "Line ~a, which runs on and on" i)
                             'text 'ui))
                (values (+ left 400) (+ top 800))))
            (ui-end! ui w h))
    (ui-handlers ui)))
```

## Menus, dialogs and tooltips

```scheme
(define (ask-draw win w h)
  (let ([ui (window-ref win 'ui)] [ch (ui-control-height)])
    (ui-begin! ui)
    (ui-button ui 'menu 20 20 120 ch "Menu…"
               (lambda ()
                 (ui-open-menu! ui 20 (+ 20 ch)
                   (list (cons "Hello" (lambda () (notify "Hello")))
                         (cons "Ask" (lambda () (window-set! win 'asking #t)))))))
    (ui-button ui 'ask 160 20 120 ch "Ask" 
               (lambda () (window-set! win 'asking #t))
               'tip "Opens a dialog")
    (when (window-ref win 'asking)
      (ui-dialog ui 'dialog "Really?" "This asks a question."
                 (list (list "Cancel" (lambda () (window-set! win 'asking #f)))
                       (list "OK" (lambda () (window-set! win 'asking #f))
                             'primary))
                 (lambda () (window-set! win 'asking #f))))
    (ui-end! ui w h)))
(define asker
  (apply open-window "Ask" 'size '(320 . 200) 'asking #t
    'draw (lambda (win w h) (ask-draw win w h))
    (ui-handlers (make-ui))))
```

`ui-open-menu!` opens a menu at a point in the window, each entry a
`(label . thunk)`, or `(label thunk icon)` with an icon drawn as an app's
is ([WINDOWS.md](WINDOWS.md#apps)); an entry whose thunk is `#f` shows
faint and can't be chosen. `ui-open-text-menu!` opens the menu that a
right click opens on text: Copy, given the text selected (or `#f` where
nothing can be selected), and Paste, given a procedure that takes the
clipboard's text (or `#f` where nothing can be typed). A text field and a
text area open it themselves, and so do the REPL and the Debug REPL,
whose text is selected with the mouse. A dialog is drawn over the window at
`ui-end!`, so it is a widget too: the app draws it for as long as its own
state says the dialog is open. Return presses the dialog's last button, and Escape or a
press outside the dialog calls `on-dismiss`, its last argument.
`ui-sheet` is a dialog whose body the app draws (a form, say).
`ui-open-modal` opens a window that waits over another one, as the file
dialog does. A tooltip is a widget's `'tip` option; the kit shows it once
the pointer has rested on the widget.

## Charts

```scheme
(define (chart-draw win w h)
  (ui-draw-line-chart 10 10 (- w 20) 100 '()
    (list (cons 'chart-1 '(1 3 2 5 4 6))
          (cons 'chart-3 '(2 2 3 3 4 4))))
  (ui-draw-legend 10 116 (- w 20) 20 '()
    '((chart-1 . "Reads") (chart-3 . "Writes")))
  (ui-draw-sparkline 10 150 (- w 20) 30 '() '(5 3 6 2 7 4 8)))
(open-window "Charts" 'size '(300 . 190)
  'draw (lambda (win w h) (chart-draw win w h)))
```

A series is `(color value ...)`, with the oldest value first, and each
legend key is `(color . label)`. `ui-bar-chart` draws stacked bars, and
calls the app with a bar's index when it is pressed; `ui-stream` draws
bars that keep coming, their numbers kept on the GPU, as Monitor's ticks
are drawn. A series is drawn in the color the app gives it. The kit's
`chart-1` to `chart-8` are settings taken from the palette's hues, so a
style can give its own: Genera, which has no color, gives stipples, which
a stream's paint draws too (those of up to 16 rows of 32 cells; a larger
one comes out as a flat gray). `chart-level-1` to `chart-level-8` say how
much of something a mark stands for, from faint to strong: a hue that
fills in, and in Genera a stipple.

`ui-flame` draws where a total goes, level by level: a tree as boxes in
rows, the root across the top and each node's children under it, a box
as wide as its share. The app gives the tree and three procedures that
read a node (its label, its value, its children); a press on a box makes
it the whole width, and a press on the top box goes back out. A box is an
outline and a name, so it reads in one bit too. `ui-source` shows lines
of a program in the mono font, scrolling, with their numbers when the
first one's is given (`'first`), one line marked (`'marked`), and a note
for each line in a column of its own (`'notes`, a string or `#f` each:
how often the line ran, say). Allocations' Where uses both, and the
Pipeline shows a shader's source with the second.

`ui-treemap` draws the same kind of tree as areas: each box as big as its
share of its parent, laid out squarified (rows along the shorter side,
so that boxes come out near squares), and each box's children inside it,
under its name. The root shown is a strip across the top; a press on a
box makes it the root shown, and a press on the strip goes back out.
Allocations' Heap draws the census with it.

## Boards, cards and marks

A board is columns of cards side by side, as Tasks shows its tasks. The
app lays out the columns and the cards and handles them; the kit draws a
column's well and heading (`ui-draw-board-column`), and its parts give
the room around the cards, the link after each card (Cons draws a pointer
to the next) and the slot where a dragged card would land
(`ui-draw-board-slot`). A mark is a small sign on a card or a row, in the
square `ui-mark-size` gives: `(level n of)` for how important,
`circle`, `diamond` or `square` for a kind, `blocked`, or a state's
`dot`. Each is a part, so a style draws them its own way: Genera's level
is a choice box's bars, in ink.

```scheme
(define (board-draw win w h)
  (let-values ([(side first between edge) (ui-board-column-insets)]
               [(left right) (ui-board-card-insets)])
    (ui-draw-board-column 10 10 220 (- h 20) '() "Doing" 2 'accent "Empty")
    (let ([cw (- 220 left right)] [m (ui-mark-size)] [p (ui-card-pad)])
      (for-each
       (lambda (i title)
         (let ([x (+ 10 left)]
               [y (+ 10 (ui-board-header-height) first (* i (+ 64 between)))])
           (fill-box x y cw 64 'bg-2 (ui-card-radius))
           (ui-draw-card x y cw 64 '())
           (ui-draw-mark (+ x p) (+ y p) m (list 'level (- 3 i) 4) 'orange)
           (draw-text (+ x p m 6) (+ y p) title 'text 'ui)
           (ui-draw-due (+ x p) (+ y 40) (- cw p p) "Due today" 'today
                        'ui-small)
           (ui-draw-board-link x y cw 64 '() between (= i 1))))
       '(0 1) '("Write the docs" "Ship it")))))
(open-window "A board" 'size '(240 . 230)
  'draw (lambda (win w h) (board-draw win w h)))
```

## How a style changes them

Each kind of widget draws through one procedure, `ui-draw-KIND`, which
is given the widget's rectangle, its state as a list of flags (`hover`,
`pressed`, `focused`, `selected`, `checked`, `disabled`, ...) and its
data. The widget's size comes from `ui-KIND-size`, and the places of its
pieces from `ui-KIND-areas`. These procedures are parts
([LOOKS.md](LOOKS.md)), and only they decide colors, fonts and spacing, so
a style can replace any of them by its key. They read nothing but their
arguments, so every state can be drawn from made-up flags:

```scheme
(open-window "Every button" 'size '(420 . 60)
  'draw (lambda (win w h)
          (for-each (lambda (flags x)
                      (ui-draw-button x 14 90 (ui-control-height) flags
                                      (format "~a" (if (null? flags)
                                                       'plain
                                                       (car flags)))
                                      #f))
                    '(() (hover) (pressed) (primary))
                    '(10 110 210 310))))
```
