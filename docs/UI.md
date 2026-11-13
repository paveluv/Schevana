# Widgets

`kits/ui.ss` is the widget kit every app here is built with: buttons,
text, choices, tables, trees, scroll views, menus, dialogs and charts. It
is immediate-mode: there is no tree of widget objects. A window's draw
procedure calls a procedure for each widget, where it should be, every
time the window draws; the widget draws itself and records where it can
be pressed, and the window's handlers ask the kit what was hit. So the
draw procedure is the layout, and the app's own data is the only state.

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
pointer is over, which one has the keyboard, a scroll view's offset.
`ui-begin!` and `ui-end!` bracket a draw, and `ui-handlers` gives the
window the kit's mouse, wheel and key handlers. Each widget has an id,
`'hi` here, unique in its window.

Press it as a person would:

```scheme
(focus-window! hello)
(let-values ([(x y w h) (content-rect hello)])
  (inject! `(mouse-move ,(+ x 40) ,(+ y 30))
           `(mouse-down ,(+ x 40) ,(+ y 30) left 1)
           `(mouse-up ,(+ x 40) ,(+ y 30) left)))
(sleep-ms 50)
presses                                    ; => 1
```

A widget takes options after its arguments: `'tip` gives a tooltip,
`'disabled #t` greys it out, and a button takes `'primary`, `'danger` or
`'quiet`.

## Values and changes

A widget shows a value it's given and calls a procedure with a new one;
the app keeps the value. Kept in the window, with `window-set!`, which
draws the window again:

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

`ui-form` lays out rows of a label and a control, each `(label height
place)`: `place` draws the control at the x, y and width the form gives
it, and a row with no label spans the width. The window calls `prefs-draw`
by name, so redefining it changes the window at once.

Typing goes to the focused widget. A click focuses what takes typing, Tab
and Shift+Tab go through the widgets in draw order, and Escape leaves:

```scheme
(focus-window! prefs)
(inject! '(key-down tab ()))
(inject! '(text "Ada"))
(sleep-ms 50)
(window-ref prefs 'name)                   ; => "Ada"
```

The other choices: `ui-radio` (one of several, each its own widget),
`ui-segmented` and `ui-tabs` (choices side by side), `ui-text-area` (many
lines), `ui-chips` and `ui-chip-input` (tags), `ui-breadcrumbs`, `ui-nav`
(a list to choose a page from), and `ui-live-badge`.

## Laying out

The kit's sizes are settings that follow the fonts: `(ui-control-height)`
is a control's height, and `(ui-gap)` and `(ui-pad)` the space between
controls and inside a box. Lay widgets out from those, never from pixels,
and they stay right in every style and at every text size.

```scheme
(ui-control-height)
(ui-gap)
(let-values ([(places height) (ui-flow 0 0 200 (ui-gap)
                                       '((80 . 24) (80 . 24) (80 . 24)))])
  places)                                  ; where each goes, wrapping at 200
```

`ui-flow` places items left to right, wrapping; `ui-toolbar` does that
for a bar of items with one that stretches; `ui-split` divides a width at
a line the person can drag. `(ui-side-panel ui id x y w h side width
least rest panel)` lays a panel along a side and the rest beside it;
hidden, or where the rest would be narrower than `least`, the rest has all
the room. With `'floating #t` the panel lies over the rest instead, so the
rest never changes size, as Life's grid doesn't. `ui-side-panel-button`
is its button, which the app lays where it has room, and
`(ui-side-panel-toggle! ui id)` turns it from a key.

## Lists, tables and trees

A table draws only the rows it shows, and the app draws each cell:

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

A column is `(key title width flag ...)`: the width is a default the
person may drag, and `right` aligns numbers. Options add sorting by a
heading (`'sort`, `'on-sort`), a double click (`'on-open`), a right press
(`'on-menu`), a tooltip a row, and checkboxes. `ui-tree` is a table whose
first column holds a tree: it takes the roots and a procedure giving a
node's children, and draws only the nodes expanded.

## Scrolling

```scheme
(let ([ui (make-ui)])
  (apply open-window "Long" 'size '(240 . 160)
    'draw (lambda (win w h)
            (ui-begin! ui)
            (ui-scroll ui 'v 0 0 w h
              (lambda (top)
                (do ([i 0 (+ i 1)]) ((= i 40))
                  (draw-text 10 (+ top (* i 20)) (format "Line ~a" i)
                             'text 'ui))
                (+ top 800)))                   ; where the content ends
            (ui-end! ui w h))
    (ui-handlers ui)))
```

A scroll view's body draws its content from `top` and says where it ends;
the wheel and the scroll bar move it, and the bar is where and when the
style puts it.

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

A dialog is drawn over the window at `ui-end!`, so it's a widget too: the
app shows it while its state says so. Return presses its last button,
and Escape or a press outside calls `on-dismiss`. `ui-sheet` is a dialog
whose body the app draws, a form, say. `ui-open-modal` opens a window that
waits over another, as the file dialog does. A tooltip is a widget's
`'tip`; the kit shows it once the pointer rests.

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

A series is `(color value ...)`, the oldest first, and the legend's keys
`(color . label)`. `ui-bar-chart` draws stacked bars, a press on one
reporting it, as Monitor's ticks are. A series is drawn
in the color the app gives it, and the kit's `chart-1` to `chart-8` are
settings from the palette's hues, so a style can give its own: Genera,
which has no color, gives stipples.

## How a style changes them

Each kind of widget draws through one procedure, `ui-draw-KIND`, given its
rectangle, its state as a list of flags (`hover`, `pressed`, `focused`,
`selected`, `checked`, `disabled`, ...) and its data; its size comes from
`ui-KIND-size` and its pieces' places from `ui-KIND-areas`. Those are
parts ([LOOKS.md](LOOKS.md)), and only they decide colors, fonts and
spacing, so a style replaces any of them by its key, and every state can
be drawn from made-up flags:

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
