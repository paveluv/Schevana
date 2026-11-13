# Your own apps, and keeping what you make

What you define at a REPL lasts until you quit. To keep it, put it in a
file under `~/.schevana.d/`, which Schevana loads at boot and again at
each `(reload!)`.

## Your folders

| Folder | What goes there |
| --- | --- |
| `apps/` | one app a file, named after it, each in a sandbox of its own |
| `styles/`, `palettes/`, `wallpapers/` | one definition a file ([LOOKS.md](LOOKS.md)) |
| `kits/` | code your styles and bars share |
| `services/` | code that keeps state |
| `desktop/` | your own bars, menus and keys |
| `lib/` | R6RS libraries ([REPL.md](REPL.md)) |

They load after Schevana's own, in that order: `kits`, `services`,
`desktop`, `styles`, `palettes`, `wallpapers`, `apps`, each in file-name
order. Settings lists your styles and palettes with the others, and the
saved look may name them. `~/.schevana.ss` loads too, like `.emacs`.

```scheme
(apps)
(styles)
(palettes)
(wallpapers)
(surfaces)                                 ; the desktop's own: bars, menu, toasts
```

## Apps in sandboxes

An app of yours runs in a sandbox: an environment of its own, under
`/apps`, holding only what it asks for, not even your kits, which are the
world's. Its file's first form says what it needs, in bundles:

```scheme no-run
;;; ~/.schevana.d/apps/counter.ss
(app-requests window draw)

(define-app (counter) "Counter"
  (let ([n 0])
    (open-window "Counter" 'size '(240 . 100)
      'draw (lambda (win w h)
              (text-draw-centered 0 0 w h (number->string n) 'accent 'big))
      'mouse-down (lambda (win x y button clicks) (set! n (+ n 1))))))
```

The launcher asks you before its first run, and Settings' Permissions
page changes your answers later; they're kept in
`~/.schevana.d/permissions.ss`. A bundle not allowed is there as stubs
that raise, naming it, and a name in no bundle it requests isn't there at
all.

The bundles, and the tree's apps that run in sandboxes:

```scheme
(map car grant-bundles)          ; => (window draw ui timers crew gpu toasts launch)
(grant-bundle-title 'timers)               ; => "Run on a timer"
(grant-bundle-names 'timers)               ; => (after now-ms now-ns current-date)
(grant-apps)                               ; => (boids boids3d clock life sketch)
(grant-requested 'clock)                   ; => (window draw timers)
(grant-undecided 'sketch)                  ; => (window draw)
```

What an app defines stays in its sandbox. The world has only its
launcher, so `(clock)` at "/" opens Clock, but Clock's own names are
Clock's:

```scheme
(env-path (grant-env 'clock))              ; => "/apps/clock"
(procedure? (env-eval (grant-env 'clock) 'draw-clock-face))  ; => #t
(repl "/apps/clock")                       ; a REPL among them
```

Settings, Monitor, Tasks, the REPL and Environments request nothing: they
tune the world, and run in it.

## The sandboxes are a beta

Grants will be redesigned after v1, as a module system of Schevana's own,
built on environments: a module imports and exports names, and a grant is
a module's environment, imported. It won't be R6RS's, so that you can
still go into any module's environment and inspect or redefine everything
in it. Kits, and probably themes, will be modules too, installable from
third parties; an app will be able to span several files and use R6RS
libraries; modules will be compiled ahead, for a faster start; and an app
in a sandbox will be one you can define at the REPL, which today only a
file can make.
