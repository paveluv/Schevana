# Your own apps, and keeping what you make

What you define at a REPL lasts until you quit. To keep it, put it in a
file under `~/.schevana.d/`, which Schevana loads at boot and again at
each `(reload!)`.

## Your folders

| Folder | What goes there |
| --- | --- |
| `apps/` | one app per file, named after the app ([below](#an-app-of-yours)) |
| `styles/`, `palettes/`, `wallpapers/` | one definition per file ([LOOKS.md](LOOKS.md)) |
| `kits/` | code your styles and bars share |
| `services/` | code that keeps state |
| `desktop/` | your own bars, menus and keys |
| `lib/` | R6RS libraries ([REPL.md](REPL.md)) |

They load after Schevana's own, in this order: `kits`, `services`,
`styles`, `palettes`, `wallpapers`, `desktop`, `apps`, each folder's
files in file-name order. The apps, yours and Schevana's, load once the
screen shows, one at a time in quiet moments, so that a heavy one never
holds up the desktop's start. A look loads before the desktop and uses
none of it: the desktop hands its bars, menus and toasts what they draw
([LOOKS.md](LOOKS.md)). Settings lists your styles and palettes with the
others, and the saved look may name them. `~/.schevana.ss` loads too,
like `.emacs`, once the world has loaded.

```scheme
(apps)
(styles)
(palettes)
(wallpapers)
(surfaces)                                 ; the desktop's own: bars, menu, toasts
```

Those folders are what loads with Schevana. A folder of the library
search (where libraries are found by name) can auto-load too, after
them, with the folders inside it (but for a folder that holds a
library's parts, [below](#an-app-in-several-files)). A library there loads by the name its
first form gives, whatever it holds (a kit, a style, a palette or an
app, such as `(third-party my-kit)`), and the folder it is found from by
that name joins the library search; a plain file (`.ss`) loads by its
path. The folder is read again at every `(reload!)`, so a file added
since then loads too. On the desktop the apps wait for the screen: a
library that declares the apps' layer (`(library-layer apps)`, as
Schevana's do), and a file in a folder named `apps`. Everything else
loads first, including a library that declares no layer. Paths are kept
in full (`path-full`).

A folder auto-loads when the command line names it (`./desktop
~/my-apps`), when it is switched on in Settings' Paths tab, or when a
REPL or `~/.schevana.ss` (which runs once the world has loaded) asks for
it. Paths shows the folders of the library search in the order they are
searched, each with a switch for whether it auto-loads, and a row that
adds a folder (which doesn't auto-load until its switch is turned on);
below them it lists every library loaded, by its layer's rank, with its
file. From a REPL:

```scheme no-run
(auto-load! "/home/me/my-apps")            ; searched, loads now and with the world
(auto-load-forget! "/home/me/my-apps")     ; searched still, no longer loads
(auto-loads)                               ; every folder that loads
```

## An app of yours

An app of yours is a file in `~/.schevana.d/apps/`, loaded into the
world as the rest is:

```scheme no-run
;;; ~/.schevana.d/apps/counter.ss
(define-app (counter) "Counter"
  (let ([n 0])
    (open-window "Counter" 'size '(240 . 100)
      'draw (lambda (win w h)
              (text-draw-centered 0 0 w h (number->string n) 'accent 'big))
      'mouse-down (lambda (win x y button clicks) (set! n (+ n 1))))))
```

What it defines belongs to the world, so give its names the app's prefix
(`counter-…`), as Schevana's apps do. An app can also be a library, in a
folder that auto-loads: the demos are libraries in `demo/`
(`(demo boids)` and the others), which `./desktop demo` loads. Code you
would rather keep apart goes in a sandbox you make
([ENVIRONMENTS.md](ENVIRONMENTS.md)).

## An app in several files

An app too big for one file is a library whose parts are libraries of
their own, in a folder of the app's name beside it. Each part's name is
the app's name and one more word, so it is found by its name from the
same folder of the library search as the app. Boids 3D is made this way:

| File | Library | What it holds |
| --- | --- | --- |
| `demo/boids3d.sls` | `(demo boids3d)` | the app: its window, keys, frames and timer |
| `demo/boids3d/rules.sls` | `(demo boids3d rules)` | the flocking rules, as data |
| `demo/boids3d/shaders.sls` | `(demo boids3d shaders)` | the code for the GPU: three compute shaders and a paint |
| `demo/boids3d/flock.sls` | `(demo boids3d flock)` | the flock in a window: its buffers, its steps, what the keys do to it |
| `demo/boids3d/view.sls` | `(demo boids3d view)` | the camera, and the field drawn with each frame |
| `demo/boids3d/rules-window.sls` | `(demo boids3d rules-window)` | the rules window |

The app imports its parts, and a part imports the parts it builds on (the
view imports the shaders and the flock), as any library imports another.
A part exports what the app and the other parts use, and keeps the rest
to itself. The app exports only its launcher, `boids3d`.

When the folder auto-loads, only the app is one of the world's entries
(`auto-load-entries`): a folder beside a library of its name holds that
library's parts, which load as its imports. So "/" gets the app's
launcher and none of its parts' names, which may then be the app's own
words. The hacker edition (`--hacker`) puts every library's names in "/",
the parts' too, so no two of them may define the same name; Boids 3D's
all start with `boids3d-`. A change to a part takes effect at the next
`(reload!)`, which evaluates again the part and every library that
imports it, the app among them.

Your own app is laid out the same way, in a folder that auto-loads:

```text
~/my-apps/
  counter.sls           (counter), the app, which imports (counter digits)
  counter/
    digits.sls          (counter digits), a part
```

## Host apps

An app can also be a program of its own, whose one window is an app on
the host's desktop, beside GNOME's or a Mac's own apps. The window fills
Schevana's whole screen (the OS window); its title is the one the
desktop's switcher and dock show; it has an app id of its own; and it
takes the host's look (Adwaita on Linux, Mac on a Mac, Windows on
Windows), light or dark as the desktop prefers. Its title bar is the
host's where the host draws one (KDE, X11, a Mac, Windows). Where the
host draws none (GNOME under Wayland), the title bar is the style's,
Adwaita's header bar, as GNOME's own apps draw theirs: the desktop moves
the window by it and resizes it by its edges, its close button quits,
and its other buttons and its menu (GNOME's window menu, opened by a
right click on it) act on the window. Closing the window, Ctrl+Q or
Ctrl+W quits the program. `(schevana kits host)` does all this:

```scheme no-run
(import (chezscheme) (schevana core) (schevana kits host))

(host-main "org.example.Notes" 360 480 (command-line-arguments)
  (lambda ()
    (open-window "Notes" 'min-size '(300 . 360)
      'draw (lambda (win w h) ...))))
```

`host-main` takes the app id (by custom a reverse-DNS name, which the
desktop matches to a desktop entry), the screen's size in logical pixels,
the command line (`--headless` draws with no window, `--fork` runs the
screen on a thread of its own) and a thunk that opens the window and
returns it. The window's `'min-size` is the smallest size the host lets a
person drag the window to. The same window opened on the Schevana desktop
is a window like any other there.

Only the look in use loads: `host-main` loads the host's style by its
name, and the palettes the style names, with the core's `look-load!`;
`--style NAME` loads any of Schevana's styles in its place:

```bash
./window-demo.sh --style genera
```

A host app needs no library of its own: `window-demo.ss`, a checklist, is
a plain script, run with the tree as Chez's library folder. To run it
from the libraries' sources (1.3 s a start here):

```bash
CHEZSCHEMELIBDIRS=. scheme-script window-demo.ss
```

Or, as `window-demo.sh` does, let Chez compile each library into a folder
of objects as it is imported, and load it from there while the object is
newer than its source (0.3 s a start once compiled):

```bash
scheme --libdirs .::.cache/mine --compile-imported-libraries \
  --program window-demo.ss
```

The `.sh` uses the launchers' own cache, the folder in `.cache/` named by
Chez's version and machine type, so what `./desktop` compiled is already
compiled for it too. `scheme-script` is `scheme --program` with no
options of its own, so it can load from a cache
(`CHEZSCHEMELIBDIRS=.::.cache/mine`) but not fill one.

What the host is told goes through the core: `screen-set-title!`,
`screen-set-app-id!` and `screen-own-frame!` (these two before the window
opens), `screen-set-least!`, `screen-hit-regions!` (the parts of the
window by which the desktop moves and resizes it: `((kind x y w h) ...)`,
where kind is `move`, a side or corner from `resize-tl` clockwise round
to `resize-l`, or `normal`, the app's own), `screen-window-action!`
(`maximize`, `restore`, `minimize`, `menu`), `screen-maximized?`, and
`screen-system-theme`. That last is the desktop's preference, `'light` or
`'dark` (or `#f`), and when it changes, the theme is built again: a style
that names a `'palette-dark` takes that palette on a dark desktop, unless
a palette was chosen.
