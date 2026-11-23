# The REPL

Everything in Schevana is a live value in a running Chez Scheme, and the
REPL is how you reach it. A REPL is a window: Ctrl+Shift+R opens one, and
so does `(repl)`. This page is about what happens to what you type; the
REPL's own keys and completion are explained in its tooltips.

## The world is data

A REPL opened with `(repl)` evaluates at "/", the world itself, so what
it returns is the live thing, not a copy:

```scheme
(clock)                                    ; an app is a procedure
(windows)                                  ; every window, topmost first
(define w (find-window 'clock))            ; by app, title or id
(window-title w)                           ; => "Clock"
(move-window! w 40 60)
(window-x w)                               ; => 40
```

Every app opens the same way, by its name: `(repl)`, `(settings)`,
`(tasks)`, `(monitor)`, `(pipeline)`, and, on a desktop started with the
demos, `(boids)`, `(boids3d)`, `(life)`, `(sketch)`, `(springies)` and
`(rings)`. What an app holds is live too. Tasks keeps its tasks as
records, which its procedures find, read and change, and its window shows
each change at once. With the demos it holds Schevana's backlog, which
`demo/backlog.sls` enters with these same procedures:

```scheme
(tasks)
(define t (find-task 12))
(task-status t)                            ; => todo
(set-task! 12 'status 'doing 'assignee "Claude")
(task-assignee t)                          ; => "Claude"
(map task-title (tasks-list 'status 'review))
(task-blockers 13)                         ; what TASK-13 waits for
(task-blocks 10)                           ; what waits for TASK-10
(tasks-tree)                               ; all of it, as nested ids
(move-task! 12 'done)
(delete-task! 12)                          ; => #t
```

## Redefining the world

A `define` at "/" replaces what the world calls by name, from its next
call on: the desktop's drawing (`draw-wallpaper`, `draw-topbar`,
`draw-menu`, `draw-toasts`), the procedure a part names (the built-in
wallpaper is `draw-wallpaper*`, the Mac style's frame `mac-draw-under`),
a surface's procedures (`draw-desktop`), and the procedures of your own
that your handlers call by name:

```scheme
(define (draw-wallpaper w h)
  (fill-gradient 0 0 w h #x102030 #x301020))
```

A library calls its own procedures directly, its hooks too (the core's
`draw-window`): a `define` at "/" of one of them makes a name of the
world's own, which the library doesn't call, and the library's code
changes with its file, at `(reload!)`.
Started with `--hacker`, the hacker edition, every library's names are
"/"'s, internals too, and a `define` replaces any of them at every call:
the bars, the menus, the styles, the window manager. There, `(define
(draw-window win) (draw-window* win #t))` draws every window as focused.
`(reload!)` reads the sources again: it evaluates again each library
whose file changed, with the libraries that import it, and loads the
world's files again:

```scheme no-run
(reload!)
```

The core's own names (`open-window`, `fill-box`, the window manager)
belong to its libraries, below the world, and those libraries call their
own definitions: the world imports the names. A `define` at "/" of one of
them makes a name of the world's own, which the core never calls; the
REPL says so when it happens. The core's code changes with its library's
file, at `(reload!)`.

## What you type runs as a process

A REPL runs each input as a process: the world keeps drawing while the
input runs, and Ctrl+C stops it. A process may wait, which the world's
own handlers may not:

```scheme
(sleep-ms 200)                             ; the REPL waits, the world doesn't
(define p (spawn "count" (lambda () (let loop ([i 0]) (sleep-ms 10)
                                      (if (< i 10) (loop (+ i 1)) i)))))
(proc-name p)                              ; => "count"
```

The same holds for a shader run on the GPU and read back
([SHADERS.md](SHADERS.md)): `gpu-compute!` and `gpu-buffer-read!` wait
inside a process. `proc-wait` turns any call that later hands its result
to a procedure into one that waits for the result.

## REPLs of other kinds

A REPL evaluates in one environment, which its title names. `(repl
kind)` opens a REPL in a new environment of that kind:

| | Opens with | What a `define` does |
| --- | --- | --- |
| REPL | `(repl)`, Ctrl+Shift+R | changes the running world |
| Private REPL | `(repl 'private)` | stays in its environment and vanishes with it, like private browsing |
| World REPL | `(repl 'world)` | the same, with every name of the world's |
| Pure Scheme REPL | `(repl 'pure)` | plain Chez Scheme: none of Schevana's names exist |
| Sandbox, thread | `(repl 'sandbox)`, `(repl 'thread)` | stays in a sandbox: Scheme's pure core, no files, C or threads |

```scheme
(repl 'private)
(repl 'pure)
```

A private REPL has all of Chez and, of the world's names, those that
read the world (`(windows)`, `(theme 'accent)` and the like), live: a
`set!` of one of them is refused, and redefining one makes a name of the
REPL's own. A world REPL has every name of the world's, so `(set-theme!
...)` there still acts on the world. Neither is a security sandbox. A
thread's REPL sends its forms to a thread of its own, which evaluates
them and prints the values.

`(repl "/lab")` opens a REPL in an environment that already exists, such
as a sandbox you made, with that environment's own names. How
environments are made and what they hold is in
[ENVIRONMENTS.md](ENVIRONMENTS.md).

## Libraries

R6RS libraries work as they do in Chez. A library typed at a REPL can be
imported at once:

```scheme
(library (acme math)
  (export twice)
  (import (chezscheme))
  (define (twice x) (* 2 x)))
(import (acme math))
(twice 21)                                 ; => 42
```

`import` also looks in `~/.schevana.d/lib` (so `(acme math)` is
`~/.schevana.d/lib/acme/math.sls`) and at the tree's root (where
`(schevana kits ui)` is `schevana/kits/ui.sls`), and
`(add-library-directory! dir)` adds more folders. The library edition
compiles a library when it is first imported, into a file beside its
source (`math.so` beside `math.sls`), which it loads again until the
source changes; the hacker edition compiles it in memory.

Two things differ from Schevana's own code. A library is loaded once per
session: after editing one, `load` its file again and import it again,
since `(reload!)` doesn't. And an import adds the library's names to the
environment it runs in, so a library that exports a name Schevana also
defines changes what that name means in what you type afterwards; `(only
…)` or `(prefix … acme:)` keep the two apart. A sandbox has no `import`,
since a library may name anything, and a sandbox holds only what it is
given.
