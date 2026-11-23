# Windows, apps and events

A window is a record with a place on the screen, a table of handlers and
a table of properties. An app is a procedure that opens windows. This
page builds both at the REPL. How to draw in a window is in
[DRAWING.md](DRAWING.md), and the widgets are in [UI.md](UI.md).

## A window

```scheme
(define hello
  (open-window "Hello" 'size '(300 . 120)
    'draw (lambda (win w h)
            (text-draw-centered 0 0 w h "Hello" 'accent 'big))))
(window-title hello)                       ; => "Hello"
```

`'size` is the size of the content, inside the frame that the style
draws around it, and the `w` and `h` that a handler gets are always the
content's size too. The window opens at the next place in a cascade of
windows, or with its frame's top-left corner at `'pos '(x . y)`. Its draw
procedure runs whenever the window is drawn: it is the only place to put
what the window shows.

## Handlers and properties

An option that names a handler becomes one of the window's handlers. Any
other option, except `open-window`'s own (`'size`, `'min-size`, `'pos` and
`'app`), becomes a property, which `window-ref` reads and `window-set!`
changes; `window-set!` also draws the window again:

```scheme
(define counter
  (open-window "Counter" 'size '(240 . 100)
    'count 0
    'draw (lambda (win w h)
            (text-draw-centered 0 0 w h
                                (number->string (window-ref win 'count))
                                'accent 'big))
    'mouse-down (lambda (win x y button clicks)
                  (window-set! win 'count (+ 1 (window-ref win 'count))))
    'key (lambda (win key mods)
           (when (eqv? key #\0) (window-set! win 'count 0)))))
```

The handlers, and what each one is given besides the window:

| Handler | Called with | When |
| --- | --- | --- |
| `'open` | | it opens |
| `'draw` | `w h` | it is drawn |
| `'frame` | `t` | before a frame it asked for (below) |
| `'key` | `key mods` | a key is pressed while it has the keyboard |
| `'text` | `string` | text is typed into it |
| `'mouse-down` | `x y button clicks` | a button goes down in its content |
| `'mouse-up` | `x y button` | the button comes up |
| `'mouse-move` | `x y` | the pointer moves over it |
| `'wheel` | `dx dy` | the wheel turns over it |
| `'resize` | `w h` | its content changes size |
| `'focus`, `'blur` | | it gains or loses the keyboard |
| `'close` | | it closes |

A few properties mean something to the window manager: `'bg`, the color
under the content; `'cursor`, the pointer's shape over the content;
`'window-style`, a style for this window alone ([LOOKS.md](LOOKS.md));
`'title-icon`, the window's own icon, in place of its app's
([below](#apps)); `'frameless`, true for a window without the style's
frame, whose content
fills all of it (a host app's window, [APPS.md](APPS.md)); and
`'on-action`, a `(lambda (win action) ...)` that returns true when it has
done the action itself. The frame's buttons, a double click on the title
and the window menu (the action `menu`) ask `'on-action` first, and the
window manager acts only when it returns false (a host app's frame acts on
the OS window this way).

`x` and `y` are in the content's coordinates, in logical pixels. `key` is
a character (`#\a`) or a symbol (`return`, `escape`, `left`), and `mods`
is a list of any of `ctrl`, `shift`, `alt` and `super`. `window-on!` sets
a handler on a window that is already open, and clears its error. A
handler that raises an error crashes only its own window, which shows the
error and can be retried.

## Events are data

Core0 turns what the person does into lists, and the world reads those
lists as events. `inject!` hands the world the same lists, as if core0
had sent them. That is how the tests drive the world, and you can do it
too:

```scheme
(focus-window! counter)
(let-values ([(x y w h) (content-rect counter)])
  (inject! `(mouse-down ,(+ x 10) ,(+ y 10) left 1)
           `(mouse-up ,(+ x 10) ,(+ y 10) left)
           `(mouse-down ,(+ x 10) ,(+ y 10) left 1)
           `(mouse-up ,(+ x 10) ,(+ y 10) left)))
(sleep-ms 50)
(window-ref counter 'count)                ; => 2
(inject! '(key-down #\0 ()))
(sleep-ms 50)
(window-ref counter 'count)                ; => 0
```

The other events are `(mouse-move x y)`, `(wheel dx dy)` and `(text
"abc")`. An event's `x` and `y` are in the screen's coordinates.
`screen-at` returns what is at a point of the screen, as the mouse finds
it: `(window win region)`, a window and the part of it there; `(surface
name what)`, a surface (a bar, the desktop) and the part of it there; or
`#f`:

```scheme
(let-values ([(x y w h) (content-rect counter)])
  (cddr (screen-at (+ x 10) (+ y 10))))     ; => (content)
(screen-at 5 5)                            ; => (surface topbar launcher)
```

## Moving

Most windows need to be drawn again only when something changes. A
window that moves asks for its next frame with `window-frame-soon!`, and
its `'frame` handler runs just before that frame is drawn. The handler is
given `t`, the time in nanoseconds at which the frame will show; it moves
what the window shows to where it should be at `t`, and asks again:

```scheme
(define spinner
  (open-window "Spinner" 'size '(200 . 200)
    'angle 0.0
    'open (lambda (win) (window-frame-soon! win))
    'frame (lambda (win t)
             (window-set! win 'angle
                          (* 2 pi (/ (mod t 2000000000) 2e9)))
             (window-frame-soon! win))
    'draw (lambda (win w h)
            (let ([a (window-ref win 'angle)] [cx (/ w 2)] [cy (/ h 2)])
              (draw-line cx cy (+ cx (* 80 (cos a))) (+ cy (* 80 (sin a)))
                         'accent 3)))))
```

A window that stops asking stops moving. A minimized window's `'frame`
handler is not called until the window is shown again.

## Arranging

```scheme
(move-window! spinner 100 80)
(resize-window! spinner 300 300)
(maximize-window! hello)
(focus-window! counter)
(focused-window)
(close-window! hello)
```

The option `'above owner` makes a window belong to the window `owner`: it
stays above its owner, and the two are raised, minimized and closed
together.

## Apps

`define-app` defines a procedure that opens the app, and registers the
app with the launcher, which lists it at once, with its icon:

```scheme
(define (stopwatch-draw-icon x y s flags)
  (ui-icon-grid (x y s)
    (fill-box 10 1.5 4 3 (ui-icon-ink flags 'accent) 1)
    (stroke-circle 12 13.5 8.5 (ui-icon-ink flags 'accent) 2)
    (draw-line 12 13.5 15.5 9.5 (ui-icon-ink flags 'text) 2)))
(define-app (stopwatch) "Stopwatch" 'icon stopwatch-draw-icon
  (open-window "Stopwatch" 'size '(220 . 90)
    'start (now-ms)
    'open (lambda (win) (window-frame-soon! win))
    'frame (lambda (win t) (window-set! win 'now (now-ms))
             (window-frame-soon! win))
    'draw (lambda (win w h)
            (text-draw-centered
             0 0 w h
             (format "~,1f s" (/ (- (or (window-ref win 'now) (now-ms))
                                    (window-ref win 'start))
                                 1000.0))
             'text 'big))))
(stopwatch)
(memq 'stopwatch (apps))
(app-launch! 'stopwatch)
```

`(apps)` lists the registered apps, and `(app-launch! name)` opens one
as the launcher does. An app defined at the REPL lasts until you quit; to
keep it, see [APPS.md](APPS.md).

`'icon` after the title gives the app's icon: a procedure `(x y s flags)`
that draws it in the square of side `s` at `x`, `y`, at whatever size it
is asked for, in the theme's colors, so that it follows the look. The
launcher lists the app with it, the taskbar (or GNOME's dash) shows it on
each of the app's windows, and a style with an icon in its title bars
(Windows, Mac, Adwaita) shows it there, unless the window gives its own
as `'title-icon` (a REPL's window shows its environment's). Inside
`ui-icon-grid` the square is 24 units across at any size, and
`ui-icon-ink` fades a color when `flags` hold `dim` (an unfocused
window's title, a minimized window's button). The icon is called by
name, so redefining `stopwatch-draw-icon` shows at its next draw. An app
that gives no icon has a stand-in, a tile in its color with its title's
first letter. `ui-draw-app-icon` draws an app's icon by its name, and
`ui-draw-window-icon` a window's:

```scheme
(open-window "Icons" 'size '(200 . 80)
  'draw (lambda (win w h)
          (ui-draw-app-icon 16 16 48 '() 'stopwatch)
          (ui-draw-app-icon 76 16 48 '(dim) 'stopwatch)
          (ui-draw-app-icon 136 16 48 '() 'clock)))
```

## Keys, timers, processes, notices

```scheme
(bind-key! '(ctrl shift #\l) (lambda () (life)))  ; a key for the whole world
(unbind-key! '(ctrl shift #\l))
(after 1000 (lambda () (notify "a second later")))
(notify "Saved" 'green)                    ; a toast, in a theme color
(add-status-segment! 'windows
  (lambda () (format "~a windows" (length (windows)))))
(remove-status-segment! 'windows)
(define busy (spawn "busy" (lambda () (let loop () (loop)))))
(memq busy (procs))
(kill! busy)
```

A key binding, a timer and a status segment each call their procedure
anew every time, so when that procedure calls one of your own
definitions by name, redefining it at "/" takes effect at once. A process
(`spawn`) runs a piece at a time between frames, however long it loops,
and `(monitor)` shows what it costs. Inside a process, `(sleep-ms ms)`
waits without holding up the world.
