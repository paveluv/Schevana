# Environments

An environment is where a name means something. Schevana keeps them in a
tree whose root is the world, "/": the core below it in "/core1", the
apps' sandboxes under "/apps", and whatever you make. A REPL evaluates in
one ([REPL.md](REPL.md)), and `(envs)` shows the tree.

## The tree

```scheme
(env-root)                                 ; the world, "/"
(map env-path (env-children (env-root)))
(env-find "/apps/clock")
(env-kinds)       ; => (private world pure core0 core1 recorder sandbox apps app thread)
(env-forks (env-root))                     ; => (private world pure sandbox thread)
```

A kind says what an environment is built on, its base, what it is given
at once, and what kinds it may make in turn: the world makes every kind a
person may ask for, a sandbox makes sandboxes and threads, and the others
make none.

| Kind | Base | What it holds |
| --- | --- | --- |
| `private` | all of Chez | what reads the world, read-only and live |
| `world` | all of Chez | every name of the world's |
| `pure` | all of Chez | none of Schevana's names |
| `sandbox` | Scheme's pure core | what it is shared, and nothing else |
| `thread` | Scheme's pure core | a sandbox, with a thread of its own ([THREADS.md](THREADS.md)) |

## Making one

`env-fork` makes a child of a kind, named, and shares it names of its
parent's:

```scheme
(define lab (env-fork (env-root) 'sandbox 'name 'lab 'share '(now-ms)))
(env-path lab)                             ; => "/lab"
(env-eval lab '(define x 41))
(env-eval lab '(+ x 1))                    ; => 42
(number? (env-eval lab '(now-ms)))         ; => #t
```

`env-eval` is what a REPL does for each form you type. To type them
yourself, open a REPL in the environment, by its path or the environment
itself; its title names it, `REPL — /lab`:

```scheme
(repl "/lab")
(repl lab)
(window-title (focused-window))            ; => "REPL — /lab"
```

There, `x` is 41, `(now-ms)` the world's clock, and nothing else of the
world's is there. `(repl)` alone opens one at "/", and `(repl 'sandbox)`
makes a new sandbox for the REPL it opens.

A shared name is a read-only forwarder to the parent's binding: live, so
a redefinition there shows at once, and free to call. A child can't
assign it, and its own `define` of the name makes its own:

```scheme
(guard (c [#t (condition-message c)])
  (env-eval lab '(set! now-ms 0)))   ; => "attempt to assign read-only variable"
(env-eval lab '(define (now-ms) 0))
(env-eval lab '(now-ms))                   ; => 0
(number? (now-ms))                         ; => #t
```

A sandbox's base is Scheme's pure core: no files, no `eval`, no C, no
threads, no clock, so what it can touch is what it was shared:

```scheme
(guard (c [#t #f]) (env-eval lab '(open-input-file "/etc/passwd")))  ; => #f
(guard (c [#t #f]) (env-eval lab '(open-window "x")))               ; => #f
```

More names can be shared later, renamed as they go, and a setter can take
a child's `set!` of one, so the parent decides what a change does:

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
sandbox's own children are sandboxes on its base or a smaller one, shared
what it holds: it narrows what it hands down, never widens it. Inside an
environment that may fork, `fork` does what `env-fork` does for it:
`(fork)` lists the kinds, and `(fork 'sandbox 'name 'inner)` makes one.

A private or world namespace is on all of Chez, so it can still reach the
world through Chez: it organizes what you define, and confines nothing.

## Files and dropping

```scheme
(env-drop! lab)
(env-dropped? lab)                         ; => #t
```

`(env-load e path)` evaluates a file in `e`. An app's sandbox, on the
confined base, has a console, which writes to its log, `(env-log e)`; a
sandbox on Scheme's pure core has none. Dropping an environment drops what is under it and
stops their threads; what still holds it can ask `env-dropped?`.

The tree's apps live in sandboxes made this way, under "/apps"
([APPS.md](APPS.md)), and the core in environments of its own: "/core0",
"/recorder" and "/core1" ([INTERNALS.md](INTERNALS.md)).

## The Environments app

`(envs)` opens Environments, which shows the tree: each environment's icon,
kind, how many names it was shared and holds, and its thread's jobs;
past a line you can drag, the one selected: kind, base, parent,
children, what it forks, its jobs (× stops one) and its names, shared
(the parent's name, read-only or through a setter, where bound) or its
own. Its toolbar and a row's right-press menu act on it:

- **Fork…**: a child of a kind it forks, named and shared names
  (suggested as you type; `now-ms as clock` renames, `size via
  size-set!` goes through a setter), optionally with a REPL in it.
- **REPL** (Return): a REPL in it.
- **Share…**: more of its parent's names, ticked in a dialog, each
  renamed or set through a setter (not into a thread's sandbox); the
  Fork sheet's Choose… picks there too.
- **Load…**: a file evaluated in it (`env-load`), picked in the
  desktop's file dialog, which stays above Environments while it waits
  (a style's `modal-above`).
- **Drop…**: it, what is under it and their threads.

On `/worklets` it sets the pool's threads. On an app's sandbox it lists
the bundles the app requests, as each stands (a press shows a bundle's
names), who decides them, and Permissions… to change them; `/apps` lists
every bundle. A world namespace gets the names the world gains at its next
evaluation; Sync shares them now (`env-sync!`).
