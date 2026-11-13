# Windows, apps and events

A window is a record with a place on the screen, a table of handlers and
a table of properties. An app is a procedure that opens windows. This page
builds both at the REPL; how to draw in a window is in
[DRAWING.md](DRAWING.md), and its widgets are in [UI.md](UI.md).

## A window

```scheme
(define hello
  (open-window "Hello" 'size '(300 . 120)
    'draw (lambda (win w h)
            (text-draw-centered 0 0 w h "Hello" 'accent 'big))))
(window-title hello)                       ; => "Hello"
```

`'size` is the content's size, inside the frame the style draws around
it, and the `w` and `h` a handler gets are always the content's too. The
window opens where the next one cascades, or at `'pos '(x . y)`. Its draw
procedure runs whenever the window is drawn: there's no other place to put
what it shows.

## Handlers and properties

An option that names a handler becomes the window's handler; any other
but `open-window`'s own (`'size`, `'min-size`, `'pos` and `'app`) becomes
a property, read with `window-ref` and changed with `window-set!`, which
draws the window again:

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

The handlers, and what each is given besides the window:

| Handler | Called with | When |
| --- | --- | --- |
| `'open` | | it opens |
| `'draw` | `w h` | it is drawn |
| `'frame` | `t` | before a frame it asked for (below) |
| `'key` | `key mods` | a key is pressed while it has the keyboard |
| `'text` | `string` | text is typed into it |
| `'mouse-down` | `x y button clicks` | a button goes down in its content |
| `'mouse-up` | `x y button` | it comes up |
| `'mouse-move` | `x y` | the pointer moves over it |
| `'wheel` | `dx dy` | the wheel turns over it |
| `'resize` | `w h` | its content changes size |
| `'focus`, `'blur` | | it gains or loses the keyboard |
| `'close` | | it closes |

`x` and `y` are in the content's coordinates, in logical pixels. `key` is
a character (`#\a`) or a symbol (`return`, `escape`, `left`), and `mods`
a list of `ctrl`, `shift`, `alt` and `super`. `window-on!` sets a handler
on a window that's open. A handler that raises crashes only its window,
which shows the error and can be retried.

## Events are data

Core0 turns what the person does into lists, and the world reads them.
`inject!` hands it the same lists, which is how the tests drive it, and
how you can:

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

The others are `(mouse-move x y)`, `(wheel dx dy)` and `(text "abc")`, on
the screen's coordinates.

## Moving

A window drawn again only when something changed is all most windows
need. One that moves asks for its next frame, and its `'frame` handler
runs just before that frame is drawn, given `t`, the time in nanoseconds
when the frame will show. It moves what it shows by `t` and asks again:

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

A window that stops asking draws nothing more, and one that's minimized
isn't asked until it's seen again.

## Arranging

```scheme
(move-window! spinner 100 80)
(resize-window! spinner 300 300)
(maximize-window! hello)
(focus-window! counter)
(focused-window)
(close-window! hello)
```

`'above owner` makes a window its owner's: it stays above it, and the two
are raised, minimized and closed together.

## Apps

`define-app` defines a procedure that opens the app and registers it with
the launcher, which shows it at once:

```scheme
(define-app (stopwatch) "Stopwatch"
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

`(apps)` lists the apps registered, and `(app-launch! name)` opens one as
the launcher does. An app defined at the REPL runs in the world; to keep
it, and to give it a sandbox of its own, see [APPS.md](APPS.md).

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

A key binding, a timer or a status segment calls its procedure by name
each time, so redefining what it calls takes effect at once. A process
(`spawn`) runs a piece at a time between frames, however long it loops,
and `(monitor)` shows what it costs; `(sleep-ms ms)` inside one waits
without holding the world.
