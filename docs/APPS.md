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
`styles`, `palettes`, `wallpapers`, `desktop`, `apps`, each in file-name
order; the apps, yours and Schevana's, once the screen shows, one at a
time while it is quiet, so that a heavy one never holds the desktop's
start. A look comes before the desktop and uses none of it: the desktop
hands its bars, menus and toasts what they draw ([LOOKS.md](LOOKS.md)).
Settings lists your styles and palettes with the others, and the saved
look may name them. `~/.schevana.ss` loads too, like `.emacs`.

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
(grant-apps)                     ; => (boids boids3d clock life sketch springies)
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

## Host apps

An app can also be a program of its own whose one window is an app of
the host's desktop, beside GNOME's or a Mac's own: the window is the
screen's whole; its title is the one the desktop's switcher and dock
show; it has an app id of its own; and it takes the host's look, Adwaita
on Linux, Mac on a Mac, Windows on Windows, light or dark as the desktop
prefers. Its title bar is the host's where the host draws one (KDE, X11,
a Mac, Windows); where it draws none (GNOME under Wayland) it is the
style's, Adwaita's header bar, as GNOME's own apps draw theirs: the
desktop moves the window by it and resizes it by its edges, its close
button quits, its other buttons and its menu (a right click on it,
GNOME's window menu) act on the window. Closing it, Ctrl+Q or Ctrl+W
quits. `(schevana kits host)` does it:

```scheme no-run
(import (chezscheme) (schevana core) (schevana kits host))

(host-main "org.example.Notes" 360 480 (command-line-arguments)
  (lambda ()
    (open-window "Notes" 'min-size '(300 . 360)
      'draw (lambda (win w h) ...))))
```

`host-main` takes the app id (reverse-DNS by custom, for the desktop to
match to a desktop entry), the screen's size in logical pixels, the
command line (`--headless` draws with no window, `--fork` runs the screen
on a thread of its own) and a thunk that opens the window. The window's
`'min-size` is the least the host lets the window be dragged to. The
same window opened on the Schevana desktop is a window like any other
there.

Only the look in use loads: `host-main` loads the host's style by its
name, and the palettes it names, with `look-load!` (the core's), and
`--style NAME` takes any of Schevana's styles in its place:

```bash
./schevana-window-demo.sh --style genera
```

A host app needs no library of its own: `schevana-window-demo.ss`, a
checklist, is a plain script, run with the tree as Chez's library folder.
From the libraries' sources (1.3 s a start here):

```bash
CHEZSCHEMELIBDIRS=. scheme-script schevana-window-demo.ss
```

Or, as `schevana-window-demo.sh` does, with Chez compiling each library
into a folder of objects as it's imported, and loading it from there
while it's newer than its source (0.3 s a start once compiled):

```bash
scheme --libdirs .::.cache/mine --compile-imported-libraries \
  --program schevana-window-demo.ss
```

The `.sh` takes the launchers' own cache, `.cache/` and Chez's version and
machine type, so what `schevana-desktop` compiled is compiled for it too.
`scheme-script` is `scheme --program` with no options of its own, so it
can load a cache (`CHEZSCHEMELIBDIRS=.::.cache/mine`) but not fill one.

What the host is told goes through the core: `screen-set-title!`,
`screen-set-app-id!` and `screen-own-frame!` (before the window opens),
`screen-set-least!`, `screen-hit-regions!` (what of the window the
desktop moves and resizes it by: `((kind x y w h) ...)`, kind `move`,
`resize-tl` and the rest round to `resize-l`, or `normal`, the app's),
`screen-window-action!` (`maximize`, `restore`, `minimize`, `menu`),
`screen-maximized?`, and `screen-system-theme`, the desktop's `'light` or
`'dark` (or `#f`), whose change builds the theme again: a style naming a
`'palette-dark` takes it on a dark desktop, unless a palette was chosen.
