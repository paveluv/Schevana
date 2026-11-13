# The REPL

Everything in Schevana is a top-level definition in a running Chez Scheme,
and the REPL is how you reach it. A REPL is a window: Ctrl+Shift+R opens
one, and so does `(repl)`. This page is about what happens to what you
type; the REPL's own keys and completion are in its tooltips.

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

## Redefining the world

A `define` at "/" replaces the definition the world calls, from its next
call on:

```scheme
(define (draw-wallpaper w h)
  (fill-gradient 0 0 w h #x102030 #x301020))
(define (draw-window win) (draw-window* win #t))   ; every window focused
```

Every procedure is called by name, so nothing has to be restarted, and
nothing is out of reach: the bars, the menus, the styles, the window
manager. `(reload!)` loads the sources again and undoes what you redefined:

```scheme no-run
(reload!)
```

The core's own names (`open-window`, `fill-box`, the window manager) live
in "/core1", below the world, which calls its own definitions. A `define`
at "/" of one of those makes the world's own, which the core never calls;
the REPL says so when it happens.

## What you type runs as a process

A REPL runs each input as a process: the world keeps drawing while it
runs, and Ctrl+C stops it. A process may wait, which the world's own
handlers may not:

```scheme
(sleep-ms 200)                             ; the REPL waits, the world doesn't
(define p (spawn "count" (lambda () (let loop ([i 0]) (sleep-ms 10)
                                      (if (< i 10) (loop (+ i 1)) i)))))
(proc-name p)                              ; => "count"
```

The same holds for a shader run on the GPU and read back
([SHADERS.md](SHADERS.md)): `gpu-compute!` and `gpu-buffer-read!` wait
inside a process, and `proc-wait` turns any call that hands its result to
a procedure later into one that waits for it.

## REPLs of other kinds

A REPL evaluates in one environment, named in its title. `(repl kind)`
opens one in a new environment of that kind:

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

A private REPL has all of Chez and, of the world, what reads it
(`(windows)`, `(theme 'accent)` and the like), live: a `set!` of one is
refused, and redefining one makes the REPL's own. A world REPL has every
name of the world's, so `(set-theme! ...)` there still acts on the world.
Neither is a security sandbox. A thread's REPL sends its forms to a thread
of its own, which runs and prints them.

`(repl "/lab")` opens a REPL in an environment that exists, such as an
app's sandbox, `(repl "/apps/boids")`, where its own names are. How
environments are made and what they hold is in
[ENVIRONMENTS.md](ENVIRONMENTS.md).

## Libraries

R6RS libraries work as in Chez. A library typed at a REPL is there at
once:

```scheme
(library (acme math)
  (export twice)
  (import (chezscheme))
  (define (twice x) (* 2 x)))
(import (acme math))
(twice 21)                                 ; => 42
```

`import` also looks in `~/.schevana.d/lib` (so `(acme math)` is
`~/.schevana.d/lib/acme/math.sls`) and in the tree's `lib/`, and
`(add-library-directory! dir)` adds more. A library is compiled in memory
when imported; nothing is written next to its source.

Two things differ from Schevana's own code. A library is loaded once per
session: after editing one, `load` its file again and import it again;
`(reload!)` doesn't. And an import adds its names to the environment it
runs in, so a library exporting a name Schevana also defines changes what
that name means in what you type afterwards; `(only …)` or `(prefix …
acme:)` keep them apart. A sandbox has no `import`: a library may name
anything, and a sandbox holds only what it is given.
