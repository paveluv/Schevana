# Environments

An environment is where a name means something. Schevana keeps its
environments in a tree. The root is the world, "/"; under it are the
worklets' environment, "/worklets", and whatever environments you make.
A REPL evaluates in one environment ([REPL.md](REPL.md)), and `(envs)`
shows the tree.

## The tree

```scheme
(env-root)                                 ; the world, "/"
(map env-path (env-children (env-root)))
(env-find "/worklets")
(env-kinds)       ; => (private world pure sandbox thread)
(env-forks (env-root))                     ; => (private world pure sandbox thread)
```

A kind says three things about an environment: what it is built on (its
base), what it is shared at once, and which kinds it may fork in turn.
The world and a world namespace fork every kind a person may ask for, a
sandbox forks sandboxes and threads, and the others fork none.

| Kind | Base | What it holds |
| --- | --- | --- |
| `private` | all of Chez | what reads the world, read-only and live |
| `world` | all of Chez | every name of the world's |
| `pure` | all of Chez | none of Schevana's names |
| `sandbox` | Scheme's pure core | what it is shared, and nothing else |
| `thread` | Scheme's pure core | a sandbox, with a thread of its own ([THREADS.md](THREADS.md)) |

## Making one

`env-fork` makes a child of a given kind, with a name, and shares some
of its parent's names with it:

```scheme
(define lab (env-fork (env-root) 'sandbox 'name 'lab 'share '(now-ms)))
(env-path lab)                             ; => "/lab"
(env-eval lab '(define x 41))
(env-eval lab '(+ x 1))                    ; => 42
(number? (env-eval lab '(now-ms)))         ; => #t
```

`env-eval` does what a REPL does with each form you type. To type the
forms yourself, open a REPL in the environment, given by its path or by
the environment itself; the REPL's title names the environment, `REPL —
/lab`:

```scheme
(repl "/lab")
(repl lab)
(window-title (focused-window))            ; => "REPL — /lab"
```

In that REPL, `x` is 41 and `(now-ms)` is the world's clock, and nothing
else of the world's is there. `(repl)` alone opens a REPL at "/", and
`(repl 'sandbox)` makes a new sandbox for the REPL it opens.

A shared name is a read-only forwarder to the parent's binding. It is
live, so a redefinition in the parent shows in the child at once, and it
costs nothing extra to call. The child can't assign it, and the child's
own `define` of the name makes a name of its own:

```scheme
(guard (c [#t (condition-message c)])
  (env-eval lab '(set! now-ms 0)))   ; => "attempt to assign read-only variable"
(env-eval lab '(define (now-ms) 0))
(env-eval lab '(now-ms))                   ; => 0
(number? (now-ms))                         ; => #t
```

A sandbox's base is Scheme's pure core, which has no files, no `eval`,
no C, no threads and no clock, so a sandbox can touch only what it was
shared:

```scheme
(guard (c [#t #f]) (env-eval lab '(open-input-file "/etc/passwd")))  ; => #f
(guard (c [#t #f]) (env-eval lab '(open-window "x")))               ; => #f
```

More names can be shared later, and a name can be renamed as it is
shared. A setter can take the child's `set!` of a name, so the parent
decides what the change does (the setter may refuse it):

```scheme
(env-share! lab '((clock . now-ms)))
(number? (env-eval lab '(clock)))          ; => #t
(define lab-count 0)
(define (lab-count-set! v) (when (fixnum? v) (set! lab-count v)))
(define tally (env-fork (env-root) 'sandbox 'name 'tally
                        'share '(lab-count)
                        'setters '((lab-count . lab-count-set!))))
(env-eval tally '(set! lab-count 5))
lab-count                                  ; => 5
```

So a child changes its parent's state only through what it was shared. A
sandbox's own children are sandboxes on its base or a smaller one, and
can be shared only what the sandbox holds: a sandbox can narrow what it
hands down, never widen it. An environment that may fork holds its own
`fork` procedure, which does what `env-fork` does for it: `(fork)` lists
the kinds it forks, and `(fork 'sandbox 'name 'inner)` makes a child and
returns the child's path.

A private, world or pure namespace is built on all of Chez, so it can
still reach the world through Chez (`eval`, the inspector, C): it
organizes what you define, and confines nothing.

## Files and dropping

```scheme
(env-drop! lab)
(env-dropped? lab)                         ; => #t
```

`(env-load e path)` evaluates a file in `e`. A sandbox on the confined
base, which holds only what is always safe (`(env-child e 'name
'confined)`), has a console that writes to its log, `(env-log e)`; a
sandbox on Scheme's pure core has none. `env-drop!` drops an environment
and everything under it, and `vat-drop-env!` also stops their threads
(as the app's Drop does); code that still holds a dropped environment can
ask `env-dropped?`.

Core0, the recorder and the core are sealed in their libraries, and have
no environment: the world imports what the core gives it
([INTERNALS.md](INTERNALS.md)).

## The Environments app

`(envs)` opens Environments, which shows the tree: each environment's
icon, its kind, how many names it was shared and how many it holds of its
own, and its thread's jobs. Past a line you can drag, it shows the
environment selected: its kind, base, parent, children, what it forks,
its jobs (× stops one), and its names, each either shared (with the
parent's name it forwards to, whether it is read-only or set through a
setter, and where it is bound) or its own. The toolbar, and the menu of a
right press on a row, act on the environment selected:

- **Fork…**: makes a child of a kind it forks, with a name and shared
  names (suggested as you type; `now-ms as clock` renames, and `size via
  size-set!` goes through a setter), and optionally a REPL in it.
- **REPL** (Return): opens a REPL in it.
- **Share…**: shares more of its parent's names, ticked in a dialog, each
  renamed or set through a setter (not into a thread's sandbox); the Fork
  sheet's Choose… picks names there too.
- **Load…**: evaluates a file in it (`env-load`), picked in the desktop's
  file dialog, which stays above Environments while it waits (a style's
  `modal-above`).
- **Drop…**: drops it, what is under it, and their threads.

On `/worklets`, the app sets the number of the pool's threads. A world
namespace is shared the names the world gains at its next evaluation;
Sync shares them at once (`env-sync!`).
