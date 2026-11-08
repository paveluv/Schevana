# Schevana

![Schevana: a REPL and a Clock in the Spine style](docs/screenshot.png)

A Lisp Machine-style desktop that lives inside one host window and is written
entirely in Chez Scheme. Every window, color, key binding, status-bar segment
and running process is a live Scheme value. You can inspect it, redefine it and
break it from a REPL that runs inside the world it changes.

The only C code involved is SDL3 (the host window, input and the GPU),
FreeType and fontconfig (fonts), all called through Chez's FFI. There is no
build step: the whole
world compiles from source in about 0.8 s at startup, and again at each
`(reload!)`.

**WARNING:** Schevana is a toy. It's meant to be a happy place for Lisp
enthusiasts, and it doesn't pretend to be a serious desktop replacement.
Simplicity is priority #1. The desktop is just a function of the
environment, drawn by the CPU on the main thread. The apps that tune the
world see all of it; the others run in sandboxes, with the permissions they
ask for, and loops and background jobs can go to worker threads. Future
versions of Schevana might draw on those threads too, and use the GPU for
window composition.

## Running

Requirements: Chez Scheme 10, SDL 3.2 or later, FreeType and fontconfig
(usually installed already on a Linux desktop), and a Vulkan driver. On
Debian 13, SDL3 is `sudo apt install libsdl3-0`, and `mesa-vulkan-drivers`
holds lavapipe, the Vulkan driver on the CPU that the tests use and that takes
over when no GPU can open. SDL chooses between Wayland and X11 by itself;
`SDL_VIDEO_DRIVER=x11 ./schevana` (or `wayland`) chooses for it.

On a Mac, install them from [Homebrew](https://brew.sh):

```bash
brew install chezscheme sdl3 freetype fontconfig
```

On a Mac the world draws on Metal, its shaders written out as Metal's language
and compiled by the system when a pipeline is made, so Xcode isn't needed.

For the fonts Linux has, install DejaVu too. Without it, `sans-serif` and
`monospace` are Lucida Grande and Menlo, not what fontconfig would choose.

```bash
brew install --cask font-dejavu
```

Homebrew's Chez Scheme is the command `chez`, not `scheme`: `./schevana`
runs whichever of the two it finds, and finds Homebrew's libraries in
`/opt/homebrew/lib` (Apple silicon) or `/usr/local/lib` (Intel). To run
the tests below on Apple silicon, type `chez` for `scheme` and put
`DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib` before it. A Mac has no
lavapipe, so they run on Metal, with no Dock icon and no window shown.

```bash
./schevana
```

```bash
./schevana --size 1600x1000 --eval '(life)'
```

```bash
./schevana --fullscreen
```

`~/.schevana.ss` is loaded at boot if it exists, like `.emacs`, and so are
your own apps, styles, palettes and wallpapers in `~/.schevana.d/` (see
"Your own apps, styles, palettes and wallpapers" below). The look you choose
in the Settings app is saved to `~/.schevana-theme.ss` (plain data, never
evaluated) and loaded at boot too, and so is what you allow the apps in
sandboxes, in `~/.schevana.d/permissions.ss`. The host window's taskbar
icon is the wallpaper's λ in your theme's colors, drawn by `draw-app-icon` (redefine
it, then call `(update-host-icon!)`). GNOME and similar desktops take app
icons from `.desktop` files instead, so install one once (it goes under
`~/.local/share`; `--uninstall-desktop` removes it):

```bash
./schevana --install-desktop
```

| Key | Action |
| --- | --- |
| F1 / click "λ Schevana" / right-click desktop | launcher (type to filter); apps picked after a right-click open where you clicked |
| Ctrl+Tab | cycle windows |
| Ctrl+Shift+W / M / N / T / R | close / maximize / minimize / tile / new REPL |
| Ctrl+Shift+P | new Private REPL |
| F11 | full screen on and off (also in the launcher) |
| F12 | screenshot to `~/schevana-N.png` |
| drag title, edges, corner; double-click title | move, resize, maximize |
| right-click title or taskbar button | window menu (incl. "Bind to `$w`") |

REPL: Enter evaluates when the form is complete (otherwise it inserts an
indented newline), Shift+Enter always adds a newline, Up/Down walk history,
Ctrl+C interrupts, Ctrl+L clears, Ctrl+V pastes. A form that runs a while
shows as the style has it: a spinner in place of its prompt (Genera's
turns `| / - \` and its who line says Run; the pointer over it says how
to stop it). Forms entered meanwhile wait under it (↳) and run in turn,
the spinner moving down to each; Backspace on an empty line takes the
last back, and Ctrl+C stops the running one and drops the rest.

Tab extends the name before the cursor to what the matches starting with
it share, and opens a list of the matches under the cursor that narrows
as you type: Up/Down choose, Tab and Shift+Tab go a page on or back,
Enter or a click takes one, Esc or a click elsewhere in the REPL closes
it, and so does a click on another window or the desktop, or anything
else that takes the keyboard from the REPL (a press on its title bar or
an empty part of a bar does not). With nothing to add, a popup says so:
the sole completion, with its description, or no completions; the next
key, text, click or wheel closes it. It offers what fits where the
cursor is: names bound in that REPL's environment; theme keys, apps,
palettes or styles after a quote in `(theme '…)`,
`(set-theme! '…)`, `(app-launch! '…)` and the like; file names inside a
string; library names inside `(import (…))`, a part at a time. Names
match as in the editor e: in segments, each starting where a part of the
name starts, in any order (`tdc` puts `text-draw-centered` first,
`winfind` `find-window`); fewer segments, in order, earlier, tighter and
shorter come first, ignoring case. The chosen one shows its argument
list and the `;;` comment above its definition (a library shows what it
exports), as the code that runs has them: the text each file had when it
was loaded, kept by the core, not the file as it is now; and for a
procedure, the definition its code was compiled from, so one redefined
at the REPL shows what was typed there (input is read with its places,
so errors in it say where too), and one `set!` to another procedure
what that one tells.

A REPL evaluates in one environment (`services/env.ss`), named in its
title (`REPL — /`, `REPL — /lab/sandbox`) with its kind's icon where the
style shows one. A kind opens a new environment of it, the window's own:

| | Opens with | What a `define` does |
| --- | --- | --- |
| REPL | `(repl)`, Ctrl+Shift+R | changes the running world |
| Private REPL | `(private-repl)`, Ctrl+Shift+P | stays in its environment and vanishes with it, like private browsing |
| World REPL | `(repl 'world)` | the same, with every name of the world's |
| Pure Scheme REPL | `(pure-repl)` | plain Chez Scheme, none of Schevana's names exist |
| Sandbox, thread | `(repl 'sandbox)`, `(repl 'thread)` | stays in a sandbox: Scheme's pure core, no files, C or threads |

A private REPL has all of Chez and, of the world, what reads it
(`env-private-names`: `(windows)`, `(theme 'accent)` and the like), live:
a `set!` of one is refused ("attempt to assign read-only variable"), and
redefining one makes the REPL's own. A world REPL has every name of the
world's, so `(set-theme! ...)` there still acts on the world. Neither is
a security sandbox: the FFI is reachable from any namespace, where
`(exit)` closes the window. A thread's REPL sends its forms to the vat,
whose thread runs and prints them; Ctrl+C stops them there.
`(repl "/lab")` opens one in an environment that exists (not
`/worklets`); once its environment is dropped, a REPL evaluates nowhere.

**Environments**, `(envs)`, shows the tree: each environment's icon,
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
every bundle. A world namespace gets the
names the world gains at its next evaluation; Sync shares them now
(`env-sync!`). An environment forks only the kinds its own allows,
through `(fork kind 'name n 'share names 'setters pairs)`: the world and
world namespaces every kind, a sandbox sandboxes and threads, the others
none; `(fork)` lists them.

R6RS libraries work as in Chez: `(import (acme math))` in a REPL, in the
file of an app that runs in the world, or inside a body (`(let () (import
(acme math)) …)`). A sandbox has no `import`: a library may name anything,
and a sandbox holds only what it is given. Besides
Chez's usual places, import looks in `~/.schevana.d/lib` (so
`~/.schevana.d/lib/acme/math.sls`) and in the tree's `lib/`, for libraries
shipped with Schevana (none yet), and `(add-library-directory! dir)` adds
more. A library is compiled in memory when imported: nothing is written
next to its source (Chez's `compile-imported-libraries` stays off). Two
things differ from Schevana's own code. A library is loaded once per
session: after editing one, `load` its file again and import it again;
`(reload!)` doesn't. And an import adds names to the environment it runs
in, the world's for its apps and a REPL at `/`, so a library exporting a name
Schevana also defines changes what that name means in code you type
afterwards; `(only …)` or `(prefix … acme:)` keep them apart.

## Things to try in the REPL

```scheme
(windows)                                  ; the window list, as data
(move-window! (find-window 'clock) 40 60)
(set-theme! 'accent #xff9e64)              ; recolor everything
(set-style! 'cons)                         ; or: mac genera fold ...
; or: tokyo-night catppuccin nord gruvbox interlisp genera
(set-theme! 'palette 'paper)               ; remembered for cons
(open-window "Odd one out" 'window-style 'windows)   ; one in its own style
(set-theme! 'ui-font-size 15)              ; fonts and sizes are theme keys too
(override! 'ui-font-size 15)               ; ... in every style
(theme-source 'accent)                     ; which layer gives it
(set-theme! 'title-double-click 'shade)    ; a double click rolls a window up
(override! 'mouse-doc #t)                  ; what the buttons do, in the top bar
(add-status-segment! 'hi (lambda () (format "~a windows" (length (windows)))))
(bind-key! '(ctrl shift #\l) life)
; watch it in (monitor); Ctrl+C or kill!
(spawn "busy" (lambda () (let loop () (loop))))
(monitor)                                  ; where the time and memory go
(profile-on! #f)                            ; the profiler off (on at boot)
(profile-history! 60 30)                   ; a minute of ticks, 30 of seconds
(profile-totals (profile-seconds))         ; what each window, ... spent
(profile-flag-report)                      ; every late tick, and why
(debug-repl)                               ; a socket for what's outside
(tasks)                                    ; a task manager; tasks are data
(add-task! "Fix the menu" 'priority 'high 'tags '("ui"))   ; shows at once
(set-task! "Fix the" 'status 'review)      ; by title, id (27) or "TASK-27"
(set-task! 22 'blocked-by '(14 "TASK-24")) ; 22 waits for them; no cycles
(tasks-tree)                               ; what waits for what, nested
; in a task's description, Ctrl+E opens it in a window of its own
(tasks-list 'status 'doing 'assignee "Pavel")
(life)                                     ; Maximize it, Cell size to 1 px,
                                           ; Speed to every tick: see below
(boids)                                    ; a flock, its rules beside it
(repl "/apps/boids")                       ; a REPL in its sandbox; there,
(define boids-step-ms 100)                 ; a slow flock; (reload!) undoes
(boids3d)                                  ; a murmuration, all on the GPU;
                                           ; drag round it, h for its rules
(define (draw-wallpaper w h) (fill-gradient 0 0 w h #x102030 #x301020))
; every window looks focused; (reload!) undoes it
(define (draw-window win) (draw-window* win #t))
```

Define a new app and it appears in the launcher immediately:

```scheme
(define-app (counter) "Counter"
  (let ([n 0])
    (open-window "Counter" 'size '(240 . 100)
      'draw (lambda (win w h)
              (text-draw-centered 0 0 w h (number->string n) 'accent 'big))
      'mouse-down (lambda (win x y button clicks) (set! n (+ n 1))))))
```

## Monitor

`(monitor)`, or Monitor in the launcher, shows the world live, in two
tabs. Its first, Overview, redrawn twice a second, has the World's
facts in a grid (uptime, the screen, the ticks, the last tick, the last
frame, the process's memory, the heap, the style, apps, timers waiting, whether profiling is on, the
last error), then the windows in a table (a click focuses one, the
focused one selected) and the processes in another, each with its
state and a Kill button. Its second, Ticks, shows where the world's time
and memory go, as the profiler (`services/profile.ss`) measures them.
Each part of a tab is under a group's heading (the kit's `group`
label, at the rows' size).
The profiler runs whether Monitor is open or not, from boot, until
Monitor's Profiling or `(profile-on! #f)` turns it off: a step of 30 Life
windows costs about 1% more with it (`tests/bench.ss`), and it
allocates nothing. Its unit is a tick of the pacer's: the steps of the
main loop (`schevana-step!`: the wait for host events, then events,
timers, a tick when due, processes, the frame and its upload) from the
one after a tick's to the next tick's, so that the steps that only
handle input between ticks sum into the tick they lead up to; a test's
steps, not paced, tick every one. It is level 1: Schevana's own
accounting, with nothing in an app's code instrumented.

The Ticks tab has three parts:

- **Ticks:** a bar a tick, all of its time since the last, stacked by
  phase: events, timers, processes, ticks, render, present, the
  collector, and the two waits, for input (the steps' wait for host
  events) and for the screen, in muted colors. A wait delays the next tick as much as work does, so
  both count. The work is at the bottom, the phase that spent the most
  over the graph lowest and first in the legend, and the waits above
  it, so that a bar past the top loses a wait, never work. A line marks
  the pacer's period (16.7 ms at 60 Hz, a refresh of the screen's by
  default) and the top is two. A tick that came late is flagged at the
  top: past one and a half periods after the last
  (`profile-tick-late?`). Not just past one, for a tick ends about at a
  refresh, a little before or after it, and one that missed a refresh
  waited for the next. All of it is whole ns and pixels, no float.
  Hover a bar for where its time went: its tick, how long it took and
  whether it came late and why, its phases and its three largest
  consumers; click it to pause there.
- **Consumers:** every window, surface (the desktop, the bars, the menu,
  the toasts) and process, and the collector, by milliseconds a second
  over the last 5 seconds, with the average and the longest a tick, the
  calls a second and a line of the last minute; hover a heading for
  what its column means. A window's row opens to
  its handlers (`draw`, `tick`, `key`, ...) and its frame, the style's
  drawing around the content; a surface's to its draw and its tick. A
  row selected shows its share of every bar; a second press lets it go. A
  window's name focuses it, and a process's Kill kills it. Two windows of one title are told
  apart by their ids (`Life (window 3)`); a window's row says once it
  is closed, a process's once it has ended.
- **Memory:** the heap, the bytes allocated a second and the collector's
  time a second, over the seconds kept.

Above them, Profiling turns the profiler on or off for the whole world
(`(profile-on! #f)`), Pause holds Monitor's view still (the profiler goes
on), Clear forgets the history, and two menus say how long the history
is: every tick of the last 30 seconds (at most 100 a second of them)
and each second's sums for the last 10 minutes, by default
(`(profile-history! 30 10)`). With profiling off, the tab says how to
turn it on.

The **Flags** tab keeps every late tick (the last 1,024 of them) long
after its bar has flowed past, the newest first: when it ended, what it
took, what made it late, what the host said last before it and the ticks
about it; `(profile-flag-report)` prints the same. What made it late is
the biggest single thing in the tick that could have
(`profile-tick-why`): a swapchain call the screen held main in, a wait
for events past its period (asleep, or running in SDL), the collector or
someone's work. When the screen held main for its next image, the last
frame's fence says where the GPU stood: finished already, finishing
during the wait, or not yet; so the GPU's work is told from the screen's
hold, on any back end.

A row's tooltip says all that's known of it: for each tick about it, how
long it slept and worked, what each swapchain call held main for, where
the GPU stood and when its frame went against the period; the host's
events for the 10 seconds before it; its frame, the host window's state,
the windows and processes, its memory, the machine's load and SDL's last
error. `(profile-flag-log! path)` adds each flag to the end of a file as
it comes, to outlive a run; a run from a checkout with a `.work` folder
logs to `.work/flags.log`.

The history is data, read in place: `(profile-ticks)` and
`(profile-seconds)` give the ticks kept and the seconds done as seqs,
the newest first; `(profile-tick-ms seq)`, `(profile-tick-phase-ms seq
'render)`, `(profile-tick-phases seq)` (where its time went, waits too,
the most first), `(profile-tick-ref seq 'heap)` and
`(profile-tick-uses seq)`
(what each key spent: a window's handler, a surface, a process) read a
tick, and `profile-second-phase-ms`, ... a second; `(profile-totals seconds)`
sums seconds by subject, the most first, each with its parts, and
`(profile-totals ticks #t)` ticks. The same as Monitor's Ticks, for a
reader without eyes (a headless agent, a test): `(profile-slow-ticks)`
gives the ticks that came late, by the pacer's period
(`(pacer-period)`), so `(map profile-tick-phases (profile-slow-ticks))`
says where each late tick's time went, and
`(profile-totals (profile-slow-ticks) #t)` who spent it. The ticks go
into a ring of 2 minutes, each second's sums into one of an hour and the last minute's
uses into one of their own, all made once; a window or a process is
kept by its id, with its title or name when first seen, so the history
keeps no closed window or ended process alive. Monitor
draws all of it with the widget kit: its charts (`ui-bar-chart`,
`ui-draw-line-chart`, `ui-draw-sparkline`, `ui-draw-legend`), its tree,
its tables and its labels. A chart's series are the kit's color
settings `chart-1` to `chart-8`, from the palette's hues,
`chart-muted-1` and `chart-muted-2` for what is not work, and
`chart-mark`, `chart-share`, `chart-rule` and `chart-flag` its mark,
its share, its reference lines and a flag over a bar: Genera and the CADR, which have no color, give them as
stipples of ink.


### The Debug REPL

`(debug-repl)` opens a window that lets something outside Schevana, a debugger
or an agent, evaluate Scheme in the running world, and shows every request and
answer as they come. Nobody types in it. The window is the switch: the socket
exists only while it's open, at `$XDG_RUNTIME_DIR/schevana-debug.sock`, for its
owner alone; closing it stops whatever was running.

One connection, one request: send the forms as text and stop writing. The
answer comes back as one datum, and the connection closes:

```
(ok "what it printed" ("a value, as text" ...) ms)
(error "what went wrong" "what it printed" ms)
(killed "what it printed" ms)
```

```bash
printf '(+ 1 2)' | nc -UN "$XDG_RUNTIME_DIR/schevana-debug.sock"
```

A request runs as a process, so a long one doesn't hold the world up, and one
past 10 seconds is stopped. It has all the power of the world's own REPL. It's
drawn by `kits/transcript.ss`, the REPL's transcript, which is there for other
apps to derive from.

## Your own apps, styles, palettes and wallpapers

Styles, palettes (named colors) and wallpapers (desktop fills) have definers
of the same shape as `define-app`: a name, a title, then the definition.
Evaluate one in a REPL and the next frame shows it; define a name again
and the new definition takes the old one's place.

```scheme
(define-palette dusk "Dusk"
  '(bg-0 #x15131c bg-1 #x1c1a26 bg-2 #x24212f bg-3 #x2e2a3b
    text #xe0dcef text-dim #xb8b2cc text-faint #x6e6884
    accent #xf0a35e accent-2 #xc792ea
    red #xf07178 orange #xf78c6c yellow #xffcb6b green #xc3e88d
    cyan #x89ddff teal #x80cbc4 magenta #xc792ea
    desktop-top #x1c1a26 desktop-bottom #x3a2a40 watermark #xffffff
    panel #x111017))
(set-theme! 'palette 'dusk)                ; or click it in Settings
(define-wallpaper stripes "Stripes"
  (lambda (x y w h top bottom)
    (fill-box x y w h top)
    (do ([i 0 (+ i 24)]) ((>= i h)) (fill-box x (+ y i) w 12 bottom))))
(set-theme! 'wallpaper 'stripes)
(define (bare-insets win) (values 0 8 0 0))
(define (bare-under win x y w h focused? hover pressed)
  (fill-box x y w 8 (if focused? 'accent 'bg-3)))
(define-style bare "Bare" 'frame-insets 'bare-insets 'frame-under 'bare-under)
(set-style! 'bare)
(define-style flat-mac "Flat Mac" 'parent 'mac 'corner-radius 0 'palette 'nord)
```

To keep one, drop it into a file of its own in `~/.schevana.d/`, under
`apps/`, `styles/`, `palettes/` or `wallpapers/`, with any code your styles
and bars share under `kits/` (or `services/`, if it keeps state) and your
own bars, menus or keys under `desktop/`. These folders load at boot after
Schevana's own (`kits` first, then `services`, `desktop`, `styles`,
`palettes`, `wallpapers` and `apps`, each in
file-name order) and again at every `(reload!)`. Settings lists your
styles and palettes with the others, and the saved look may name them.
An app of yours runs in a sandbox of its own, which holds only what it asks
for, so not your kits, which are the world's. Its file is named after it, and
its first form says what it needs, of the bundles `window`, `draw`, `ui`,
`timers`, `crew`, `gpu`, `toasts` and `launch`: the Counter above, in `counter.ss`, starts
with `(app-requests window draw)`. The launcher asks you before its first
run, and Settings, Permissions changes it later.
`(apps)`, `(styles)`, `(palettes)`, `(wallpapers)` and
`(surfaces)` list what is registered.

## Architecture

```
apps/        in the world: repl  debug-repl  envs  monitor  settings  tasks
             each in a sandbox of its own: boids  boids3d  clock  life
             sketch
wallpapers/  desktop fills: gradient  flat  shade
palettes/    named colors: catppuccin  crayons  forest  genera  gruvbox
             interlisp  neon  nord  paper  phosphor  sakura  sunset
             terracotta  tokyo-night
styles/      styles: cadr  cons  curses  draft  fold  genera  halo
             interlisp  lambda  mac  reticle  slab  spine  windows
desktop/     the screen's own surfaces: wallpaper  taskbar  topbar  menu
             toasts; status segments, the crash panel, the app icon, the
             default keys, the commands that arrange the windows, the
             file dialog (`open-file-dialog`), the window that asks what
             an app may do (`open-permissions-dialog`)
services/    long-lived state behind an API, no surface: crew, worker
             threads for data-parallel loops; env, the tree of
             environments; grant, the apps' sandboxes, their bundles and
             what is allowed; profile, the profiler; theme-file, the saved
             look, written soon after each change; vat, threads with a
             mailbox and a sandbox, and their background jobs
kits/        app: launching one by name, the color a name gets; color:
             hue, saturation and lightness, a color as one fixnum, the
             text color that reads on one; complete: a completion list
             beside a caret (matching, keys, clicks, placement); edit:
             text editing, pure, and a text's rows, computed only as far
             as they are shown; fill: gradient and glow fills; pixmap:
             pixel buffers drawn scaled up; px: pixel art on whole
             device pixels (rectangles, bevels, small pictures, text);
             text: the widest of some strings, a string centered, cut to
             fit or wrapped; theme: which layer gives a setting, what a
             palette would show; ui: immediate-mode widgets (buttons,
             text fields and areas, dropdowns, tabs, checkboxes, radios,
             steppers, a table, a tree, chips, a date picker, scroll
             views, a toolbar, a form, a movable split, breadcrumbs,
             tooltips, dialogs and sheets, windows that wait on one
             another, charts: stacked bars, lines, a sparkline, a
             legend), keyboard focus
src/system   main loop, timers, inject!, boot, reload!, loading the folders
             (an app's file through a hook, which grant sets)
src/wm       window records, z-order, focus, hit testing, drag/resize,
             dispatch; the registries of surfaces and strips
src/proc     processes + watchdog (Chez engines); notify, report-error!;
             the profiler's hook; worklets, what worker threads run
src/host     SDL3 window ⇄ Scheme event lists   |  headless mode
src/gfx      immediate-mode drawing API, colors, stipples and gradients,
             what's clipped and turned, images and paints: all written as
             records, the list a frame sends
src/gpu      the GPU layer: the device, frames, images, buffers, compute,
             in the world's terms, SDL's GPU names ending here
src/shader   the shader language's compiler: one small tree, and SPIR-V or,
             on a Mac, Metal's language
src/font     fonts by fontconfig, glyphs by FreeType, the atlas, and measuring
             from tables, with no device
src/theme    the whole look: settings in layers, rules, palettes, styles,
             parts, the frame's parts; a hook that keeps each change
src/ffi      the only file that knows about C (SDL3, FreeType, fontconfig);
             only the core uses it
```

`src/` is the core, the explicit, ordered list in `load.ss`. Its last
file loads the folders: `kits/`, `services/`, `desktop/`, `styles/`,
`palettes/`, `wallpapers/` and `apps/`, one definition per file (`kits/`,
`services/` and `desktop/` aside),
each folder in file-name order. A file dropped into a folder loads at the
next boot or `(reload!)`, with no list to edit, and `(source-files)`
lists them all. Only the core calls C: the folders draw, measure and
save through its procedures, never through `src/ffi.ss`'s bindings, and
`tests/sources.ss` checks that none of them names one.

The core names nothing of the desktop layer's: the crash panel and the
window menu are parts (`draw-crash-panel`, `open-window-menu`) whose
built-ins the desktop layer gives. It keeps two registries:
the screen's **surfaces**, drawn and given input in depth order (the
desktop under the windows; the taskbar, top bar, menu and toasts over
them), and the **strips** they reserve at the screen's edges, which
`desktop-rect` (where windows go) leaves out:

```scheme
(define-surface dock 15                      ; over the taskbar
  'draw (lambda () (fill-box 0 0 64 (screen-h) 'panel))
  'box (lambda () (values 0 0 64 (screen-h)))   ; what a frame redraws
  'at (lambda (x y) (and (< x 64) 'dock))       ; takes the points there
  'mouse (lambda (kind what x y button clicks) (notify "dock")))
(define-strip dock 'left (lambda () 64))     ; maximized windows beside it
```

A field may name a procedure instead (`'draw 'draw-taskbar`), looked up
at each call, so redefining it at the REPL shows on the next frame.

Decisions worth keeping in mind for the real design:

- **Everything is top-level.** No R6RS libraries on purpose. Every
  definition lives in the interaction environment (an app in a sandbox's, at
  the top level of its own), so redefining
  `draw-window` or `draw-wallpaper` at the REPL changes the running system
  on the next frame. State that must survive `(reload!)` is declared with
  `defvar`, and record types are `nongenerative`.
- **Folders, not lists.** Apart from the core, a definition is found by its
  folder. Each kind has a definer shaped like `define-app` that registers it by
  name, in a list kept in registration order, and a query that lists them. Kits
  are world code shared by apps: they load at boot, stay top-level and keep a
  name prefix (`ui-`, `edit-`, `complete-`), and they keep no state but
  caches. Services are the same with state behind their procedures
  (`profile-`, `theme-file-`). Code moves out of an app into a kit when a
  second app needs it, not before. The rules every change follows, layers
  and state among them, are in `AGENTS.md`. R6RS libraries are one-way black
  boxes, like C libraries: the world imports them, they never call into the
  world.
- **Worker threads run worklets.** A worklet (`define-worklet`, or
  `worklet` like `lambda`) is compiled in an environment of its own:
  Scheme's pure core, fixnums, flonums, bytevectors, fxvectors, flvectors,
  boxes, the clock and the other worklets, and nothing of the world. One that names a
  world procedure, SDL, `eval`, a `#%` primitive or a local of the
  code around it, or sets a top-level name, is refused when it is
  defined, so a worklet touches only what it is handed, by construction;
  worklets call each other by name and see each other redefined, through
  read-only forwarders to the world's bindings, which refuse a worklet's
  `set!` of another as it expands. Of what it is handed, a worklet opens
  only pairs, vectors and boxes, and the crew refuses any procedure there
  that is no worklet.
- **Environments are a tree.** The world is its root (`services/env.ss`).
  A child is of a kind, `(env-fork e 'sandbox 'name 'tally 'share
  '(add!))`, which says its base (all of Chez, what is always safe, or
  Scheme's pure core), what it is shared at once and what it may fork in
  turn (a registry, which vats and apps add to);
  `(env-child e name base)` makes a bare one. It is
  shared only the names its parent lists, as in
  `(env-share! e '(windows (clock . now-ms)))`. Each is a read-only
  forwarder, a macro that makes code in the child refer to the parent's
  binding itself: live, at no cost a call. A `set!` of it is refused as
  it expands, in the words Chez uses for an R6RS import's: "attempt to
  assign read-only variable farewell". A setter may take the `set!`
  instead (`env-share-setter!`), and the child's `define` makes its own.
  So a child changes its parent's state only through what it was shared.
  A sandbox's children are sandboxes on its base or a smaller one, shared
  what it holds: it narrows what it hands down, never widens it. Every name
  of the world's, followed, is a world namespace's alone, which a person asks
  for. A dropped one is marked so (`env-dropped?`): what holds it knows.
  A child on Chez's base still reaches the world through Chez, so it
  organizes state and confines nothing. The confined base is what is
  always safe, for apps: R6RS's libraries and Chez's pure extras, but no
  files, eval, C, threads, clock or inspector. Its record types are its
  own: a uid is taken under its path, so a type stays one across a reload
  and is never the world's. Its console writes to its log (`env-log`).
- **Apps run in sandboxes.** An app's file that starts with
  `(app-requests window draw timers)` loads into `/apps/<name>`
  (`services/grant.ss`), on the confined base, holding of the world's
  names only its bundles: titled lists ("Draw in its windows": `fill-box`
  and 49 more). The tree's Boids, Boids 3D, Clock and Life are approved by a
  table;
  Sketch, and every app of yours, asks the person, whose answers are kept in
  `~/.schevana.d/permissions.ss`. A bundle not allowed is there as stubs
  that raise, naming it ("Sketch needs Draw in its windows (fill-box):
  denied"); a name in no bundle it requests is unbound. Its `define-app`
  registers that app alone, and what it defines stays in its sandbox
  (Boids' `boids-step` is no name of the world's): only `(clock)` at the world's
  REPL reaches in, to open Clock. Settings, Monitor, Tasks, the REPL and
  Environments request nothing and run in the world, which they tune.
- **A crew of threads for loops.** `(crew-for start end worklet arg ...)`
  (`services/crew.ss`) calls `(worklet lo hi arg ...)` on disjoint slices
  of the range on worker threads, the caller among them, and returns when
  all have. A call writes only its own slice and allocates nothing (that
  stops every thread), and the crew adds nothing to it: a call is one
  `box-cas!`, a region a few hundred bytes, an idle worker nothing. It should
  take 20 to 200 µs: `(crew-for* chunk
  start end worklet arg ...)` gives each call at least chunk indices, and a
  range of one chunk runs on the caller alone, so a small grid never wakes
  the crew. An error in a call is
  raised in the caller; on main a runaway call is cancelled after 100 ms
  and the caller raises, as a runaway handler does; in a REPL evaluation
  the caller waits a millisecond at a time and the desktop runs on.
  `(crew-size)` workers, by default one less than the machine's threads,
  at most 8 (`SCHEVANA_WORKERS` sets it, 0 for none). Everything else stays
  on the main thread; `(post-main! thunk)` hands work back to it from any
  thread.
- **Apps use the crew through a bundle.** `crew`, "Compute on worker
  threads", gives an app `crew-for`, `crew-for*`, `crew-map`, `crew-size`,
  `crew-size-set!` (at most one thread short of the machine's), and
  `define-worklet` and `worklet` of its own: they compile in an environment
  its sandbox alone has, so an app's worklets reach nothing of the world's
  or another app's, and none lands in `/worklets`. Not approved, they are
  stubs like any other: the app loads, and the first use raises.
- **Apps use the GPU through a bundle.** `gpu`, "Compute and draw on the
  GPU", gives an app `define-compute-shader`, `define-paint`, `fill-shader`,
  `draw-scale` and its own buffers (`make-gpu-buffer`, `gpu-buffer-set!`,
  `gpu-buffer-release!`). A shader touches only the buffers it's handed: a
  read outside one reads its last word and a write outside is left out, on
  every device, each buffer's length a uniform of its own. A compute run asked
  for with `(gpu-compute-soon! shader w h arg ...)` goes with the next frame,
  ahead of its drawing, so a paint shows what it wrote, and nothing waits
  for it; `gpu-compute!`, which waits, and `gpu-buffer-read!` are the world's
  alone. `(inspect-computes)` lists the runs waiting for the frame.
- **Life and Boids run on the crew.** Life's grid is as many cells as its
  window has room for: a new size keeps what fits and seeds the new ground.
  Its panel sets the cell size (in the screen's own pixels: 1 px is one),
  the speed (up to a generation every tick, or flat out, as many as 10 ms of
  a tick hold) and the crew's threads, and shows what a generation and its
  drawing take, lying over the grid. Boids' rules window has the same threads
  slider. Boids' flock is an flvector of four numbers a boid, stepped
  by one worklet that allocates only its sums. Measured here, on 48 hardware
  threads:

  | | One thread | Crew of 8 | All 48 |
  |---|---|---|---|
  | Life, a generation, 1 px a cell, maximized on a 4K screen (7.4 M cells) | 69 ms | 9.6 ms | 4.2 ms |
  | Boids, a step, 450 boids (16 ms before the crew) | 0.60 ms | 0.22 ms | |
  | Boids, a step, 2,000 boids | 11.7 ms | 1.6 ms | |
  | Boids, a step, 5,000 boids | 72 ms | 9.3 ms | |

  The crew gains less per thread as it grows (a generation on 16 threads is
  12 times as fast as on one, on 48, 17 times), and a tick has room for what
  it has room for: at 4K a frame and its upload take 8 ms the crew does not
  help with, so a generation every tick at 60 Hz wants about 10 to 16
  threads, and more show only flat out. That upload is a stand-in's memcpy:
  a real screen has not been measured. What fills the frame after that is
  the drawing on the main thread, for both apps.
- **A side panel hides and shows.** `(ui-side-panel ui id x y w h side width
  least rest panel)` lays a panel along a side and the rest beside it;
  hidden, or where the rest would be narrower than least, the rest has all
  the room. `(ui-side-panel-button ui id x y w h side)` is its button, a
  widget of its own that the app lays where it has room, never over its
  work: Life's is at the end of its status line, which runs under both, so
  it stays put as the panel comes and goes, and a second press undoes the
  first. Its H key is `(ui-side-panel-toggle! ui id)`. By default the panel
  lies beside the rest, which gets its room when it hides. With `'floating #t`
  it lies over the rest, showing it through where the style lets it, so the
  rest never changes size: Life's grid, which a resize would have to rebuild.
- **Vats run jobs in the background.** A vat (`services/vat.ss`) is a
  thread, its mailbox and a sandbox only its thread evaluates in, so its
  state is its own: `(vat-eval! v '(define n 0) #f)` defines there, and
  `(vat-send! v 'add! '(5) show)` calls the vat's `add!` there.
  `(vat-send! (vat-pool) step! (list grid) show)` runs a worklet on the
  pool's threads, 4 until `(vat-pool-size-set! n)`. When a job returns, its `then` (`show`) runs on main at
  the next step as a handler of the window that sent the job: an error in
  the job or in `then` crashes that window. Closing or crashing the window
  kills its jobs, as `(vat-job-kill! j)` does: a job killed never starts,
  or escapes within microseconds, and its `then` never runs.
  `(vat-job-pending? j)` holds until `then` has run. Jobs carry and return
  no procedure but worklets. A job sent with a `fail` gives it the error
  instead of crashing the window; `(vat-repl! v forms width then fail)`
  prints what the forms return on the vat's thread, where the values
  live, as a REPL in a thread's environment does.
- **Apps are procedures.** `define-app` defines a normal procedure (in
  the app's sandbox, for one in a sandbox) that
  calls `open-window` with a property list of handlers (`'draw`, `'key`,
  `'text`, `'mouse-down`, `'tick`, ...). Every other option becomes a
  window property (`window-ref` / `window-set!`). `'above owner` makes a
  window its owner's: it stays above the owner, which still takes the
  keyboard when given it, and the two are raised, minimized, brought back,
  sent behind and closed together (`window-owner`, `window-owned`); looked
  up by its app, an app's own window comes first.
- **A tick's busy time is always kept.** What a tick took but its waits for
  input and for the screen, profiling on or off: past a period, the next
  tick is late. `(pacer-busy-ms)` is the last tick's, Monitor shows it, and
  the top bar's `ms/tick` is the most any tick took in the last second, so
  that one spike shows. The bar's memory is the heap, then the process's
  resident memory where the system says it (Linux): `43.0/175.3 MB`. That
  holds what SDL and the drivers keep outside the heap, which neither
  reports. Monitor shows both. The bar reads its numbers once a second,
  however many frames are drawn between.
- **A pacer gives the ticks.** Every window's, surface's and toast's
  `'tick` runs exactly once a period, whether it draws or not, while a
  tick's work and its frame fit in one: bookkeeping or a check on
  something can count on a steady beat. The period is a refresh of the
  screen's by default, so apps that move by time still read the clock
  (`(pacer-tick-ms)`, when this tick began); `(pacer-rate! 60)` makes it
  60 a second from then on, and `(pacer-rate! 'screen)` brings the
  screen's back. `(pacer-ticks)` counts them. Past a period of work the world slows down: the next tick comes
  right after, none skipped. Processes run in the time left before the
  next tick's frame, at least 1 ms a step. The screen's wait never holds
  the ticks back: while the host window is hidden, minimized or covered
  nothing is presented, and while it lacks the focus frames are presented
  without that wait. With the focus, the wait paces frames, and input is
  handled and drawn as it comes, between ticks; without it, the ticks
  pace both: the loop sleeps until the next, and takes input then.
  It also keeps frames off the screen's cutoff: a frame sent a little too
  close to a refresh shows a refresh late, and the screen shows the last
  one again. The pacer can't see that cutoff, but a wait for the screen's
  next image ends about there. So when three of the last eight frames have
  waited, it re-times itself to send each frame half a period after that moment,
  and leaves one out, so that what's queued drains while the world ticks
  on. A lone wait moves nothing: reacting to it is what makes the next
  frame wait. `(inspect-pacer)` says how often. Between waits it runs on
  its own clock, and can drift until the next one.
  Its period is a little shorter than the refresh the display reports
  (`'pacer-margin`, 300 ns, in Settings' Display tab), because a report can
  be a little too long: drifting early costs a frame nothing, where drifting
  late would show one a refresh late.
  How a frame reaches the screen is `'present-mode`, in the same tab, or
  `(override! 'present-mode 'mailbox)`; it changes live, at the next frame,
  among what the window offers (`(inspect-device)`). With `vsync`, the
  default, main can wait for the screen, and a frame that misses it shows as
  a flag. With `mailbox` main seldom waits and a newer frame replaces one not
  shown yet, which SDL doesn't report: no flag says so, and the pacer hardly
  re-times, having few waits to go by.
- **Kernel vs user space via engines.** Each app handler runs in a Chez
  engine with a fuel budget (`safe-call`). An error or an infinite loop
  "crashes" only that window, which then shows the condition and can be
  retried or fixed live with `window-on!`. REPL evaluations run as
  *processes*: engines that get time slices every frame, so `(let loop ()
  (loop))` never freezes the desktop. System code uses `safely` (errors are
  caught, but there is no fuel limit).
- **Reloading holds the world still.** `(reload!)` typed in a REPL, or the
  launcher's "Reload sources", is a process too, so a source file whose top
  level loops can't freeze the desktop. While it loads, nothing else runs
  half-loaded code: no frames (the screen stays as it was), timers, ticks or
  other processes, and input waits, to be handled in order when it is done.
  Ctrl+C stops it (and closing the window still quits); a toast names the
  file it was loading when it is stopped or fails.
- **Events are data.** The host turns SDL events into lists like
  `(mouse-down 120 40 left 1)` and `(key-down #\w (ctrl shift))`.
  `(inject! ...)` feeds the same lists in, which is how the tests drive the
  world.
- **Settings are theme keys, in layers.** Colors, sizes and fonts all
  live in one table, `(theme key)`, resolved from layers whenever one
  changes: your Overrides (`override!`, in every style), your changes to
  the chosen style (`set-theme!`: switch styles and back, and yours come
  back), the style and its parents, its palette (the setting `palette`),
  and the built-in defaults. A rule is a setting computed from others then,
  never per frame: the built-in `selection` is `(theme-rule (mix 'accent
  'bg-1 0.65))`, so a palette gives twenty colors and the rest follow it, and
  so does your accent. `(theme-source key)` (the theme kit's) says
  which layer gives one, `(theme-part key)` the procedure a part key
  gives.
  The Settings app is a front end to these, so anything it does can be
  scripted from the REPL: its Theme tab's style cards are the one
  switch (`set-style!`: frames, palette, wallpaper, fonts, behaviors and
  what you changed for that style at once); each row is one of the style's
  options (the common ones it honors, the behaviors, its own; those it
  does not honor show dimmed), and changing it is your change to this
  style (`set-theme!`; ↺ drops it, `reset-style!`); its pin makes it an
  Override (`override!`); Reset forgets your changes to the style; Save
  as new style writes them as a `define-style` with the style as its
  parent, `(save-style-as! 'my-mac "My Mac")`, into
  `~/.schevana.d/styles/` (`*settings-style-directory*`). The saved file is
  plain data: the
  style, the scale, the Overrides and your changes per style; an older,
  flat file loads as the saved style's changes.
- **Logical pixels.** All layout is in logical pixels, and a record holds
  device pixels: what's drawn is `*scale*` times bigger, so text and shapes
  are rendered from outlines at full resolution, and what a text measures
  doesn't change with the scale. The scale follows
  the desktop (SDL's display scale for the window: the pixel ratio on
  macOS and Wayland, `Xft.dpi` under X11, which is how GNOME publishes
  200% and SDL reads once, as it starts), and the display's `scale` (a
  percentage; 0 for automatic, in Settings → Display, saved apart from
  any style's settings) overrides it.
  Mouse positions are converted at the host boundary, so apps never see
  physical pixels.
- **Fonts are settings, and sizes follow them.** A font role (`'ui`,
  `'mono`, `'title`, ...) is a rule that makes the font from the four
  font settings, `(font family size . opts)`, one record per font, so
  every theme asking for it shares its face, its metrics and the text
  laid out in it; a style changes a role by setting it (Genera sets
  `'ui` to the code font). Besides the regular, bold, small and italic
  ones there are `'ui-bold-italic`, `'ui-small-bold` and `'mono-italic`.
  Faint text (`'text-faint`) takes the font a style's `faint-text-font`
  part makes of its own: Genera, with no gray, gives the kit's
  `ui-italic-of`. The kit's shared
  sizes (`control-height`, `gap`, `pad`, ...) are rules from the fonts
  too, and a style may give its own pixels. Title bars and the bars take
  the larger of their own setting and what their text needs
  (`chrome-height`: 0 is none, and a style that fixes one means its
  pixels), as do menus, the apps' bars and the Settings layout, so the
  interface stays usable from 9 to 36 px; the screen's
  scale changing builds the theme again, since fonts measure differently
  there. Where a window is too small, Settings scrolls and stacks its
  rows. A new REPL opens at 80 × 22 characters of the code font.
- **Styles are settings; parts are procedures by name.** A style is a
  name, a title and settings (`define-style`), one of which may be
  `'parent`: a derived style changes what it sets and inherits the rest.
  A part is a setting whose value is a procedure or its name, looked up
  at each call, so redefining that procedure at the REPL shows on the
  next frame. The frame is six parts (`src/theme.ss`): `frame-insets`,
  `frame-regions` (`close`, `minimize`, `maximize`, `depth` buttons and
  `title` areas), `frame-radius`, `frame-bleed`, and two drawing passes
  around the content, `frame-under` and `frame-over`. The window manager
  only does geometry and dispatch. Apps always get their content size,
  whatever the frame. A window is drawn clipped to its extent, so a style
  that draws past its frame (a glow, say) gives how far as its
  `frame-bleed`. A window naming a style (`'window-style`) is drawn and
  hit-tested in that style's theme, content included; `(with-style name
  thunk)` draws in one. `define-part` makes a procedure a part: its body
  becomes the built-in `name*`, and the name calls the style's. Every
  widget's drawing, size and areas in the kit is one, as are the bars'
  (`draw-topbar`, `topbar-areas`: what each bar draws where, and where it
  takes the clicks), the menus' (`menu-areas`, `draw-menu`, and the
  numbers as settings: `menu-item-height`, `menu-font`, ...), the toasts'
  and the popups' pieces (`ui-draw-panel`, `ui-draw-highlight`,
  `ui-draw-separator`, `ui-draw-card`), which menus, toasts, dialogs,
  tooltips, the calendar and the REPL's completion list share;
  `ui-draw-highlight-over` comes again after what a chosen row or entry
  shows, for a style that inverts it. A person is the kit's avatar
  (`ui-draw-avatar`, `ui-avatar-size`), and Tasks' own marks are its
  parts (`tasks-draw-mark`: priority, kind, blocked, status;
  `tasks-draw-due`, `tasks-draw-slot`). Settings say the rest: a text's
  caret (`text-caret`: `bar` or `block` in reverse video as wide as the
  character under it, the REPL's and a menu's filter's too) and
  selection (`text-selection`: `fill` or `underline`), a section label's
  font and case (`label-section-font`, `label-section-upcase`), where a
  menu's entries go (`menu-align`: `left` or `center`), and whether the
  calendar steps by glyphs or by the words Previous and Next
  (`calendar-step-words`), and how wide a well's ring is, which a view
  scrolling in it stops short of (`surface-well-ring`). A clip's edges,
  like a box's, lie on whole device pixels, so what it cuts ends crisp at any
  scale. A
  container draws its inside in its place (`with-place`: a text box's
  `field`, a table's `list`, `dialog`, `tooltip`, `menu`, the bars'
  `bar`, `toast`), so a style can color what sits there, an app's own
  cells too, by its `'places`.
  Styles share their drawing too. A stipple, `(stipple ink paper row
  ...)`, is a pattern used wherever a color is (a fill, a line, text, a
  theme key's value), tiled on the screen's device pixels where px's
  rule puts each logical pixel, so it lines up across windows at any
  scale. So is a gradient, `(linear-gradient x0 y0 x1 y1 color ...)`
  or `(radial-gradient cx cy r color ...)`, its colors spread evenly,
  which the fill kit's `fill-gradient` and `fill-glow` are made of.
  `text-ink` measures what a string inks where it is drawn (capitals
  centered on a line), and a font made with `'crisp` is not
  antialiased. What the styles ask beyond a
  box the core gives: `invert-box` (reverse video, the bell's flash; with a
  pattern, inverted where it shows), `add-box`, `with-turn` (Spine's title),
  `draw-scale` (how many device pixels a logical one is where we draw:
  Curses draws in whole ones, under `with-scale`), `draw-pixels` (raw pixels,
  which the pixmap kit's `pixmap-draw` draws; bigger than they are each is a
  sharp block, smaller they blend, an image that's drawn on from a chain of
  half-size copies of itself) and `png-write-drawing` (the app icon's file).
  `kits/px.ss` draws pictures of boxes: `px-bevel` (Motif's
  corners or the Mac's), `px-bits` for small pictures,
  `px-invert` (reverse video: ink and paper swap, in any palette),
  `px-bitmap-text` (a bitmap font's text, the CADR's 5X5 among them)
  and `px-lozenge`. The
  kit's `ui-draw-glyph` draws a window's buttons (`close`, `minimize`,
  `maximize`, `restore`, `shade`) and the triangles (`up`, `down`,
  `left`, `right`), which the styles share.
  The 1980s Lisp environments: Interlisp, from Medley's window system
  sources (MIT licensed): a border of 2 pixels of ink and 2 of paper, a
  black title strip with the title at x 4, the window's title shade
  after it (`interlisp-title-shade`), Medley's #x8822 desktop, and its
  scroll bars, 24 pixels at the left under the pointer or, with the
  scroll bar side `outside`, beside the window in its frame's margin.
  Genera (Symbolics Lisp Machines), built to the margins its 1986 manuals
  specify, with the window's label in the bottom-left corner, which is
  also where you drag it: a style can list any area as its `'title`. It
  takes the whole screen: no top bar, and at the bottom the who line,
  what the mouse buttons do in reverse video ("Mouse-L: Move; Mouse-R:
  Window menu.") over the selected window, a field listing the windows
  and the status, in character columns; a window not selected is
  grayed over. Every widget is Genera's own, or what its authors would
  have made of their parts: no color (every hue is the palette's ink),
  what an app shows in the code font and its command words in the sans;
  a word boxed under the mouse, inverse video for what is chosen, bold
  for a current value, italic for a hint, an underline for a field and
  the keyboard's place; tags as Zmail's `{keywords}`, people's initials
  in the CADR's lozenges (its 5X5 font, `px-lozenge`), a checkbox as a
  choice box after its name, a switch as "Yes No", a dialog's buttons
  as words in equal shares, menus' entries centered, a month as a text
  table. Its numbers are settings (`genera-border`,
  `genera-margin`, `genera-label-font`, `genera-command-font`, ...), so
  the MIT CADR, from MIT's System 99 sources (BSD), is Genera in a few
  settings: a 1-pixel border and margin, the label upright in the code
  font at the top of its strip under the content, no gray (the CADR
  grayed only covered windows), command words in the code font, menus
  a size up, the standout in italic, a heavier choice box, a dialog's
  buttons margin choices, and its 3-pixel scroll bar under the mouse.
  Each brings the palette of the same name and its wallpaper (the
  `wallpaper` theme key).
  Our own styles choose their feel where it suits them: Fold folds a
  window up to its title on a double click, Lambda rolls it into its tab
  on the wheel, Halo and Reticle show scroll bars under the pointer,
  Draft drags an outline that is a drawing with the live size, Reticle
  drags its brackets, Curses rings the bell on the whole screen and boxes
  menu entries, Interlisp drags Medley's dashed outline, chooses from
  menus on release and flashes the window.
- **How it feels is settings too.** Shared code does what a style
  chooses, each a setting whose default is today's feel: a double click
  on the title (`title-double-click`: `maximize`, `shade` or `none`) or
  on a frame button (`button-double-click`: `((menu . close))` is CDE's);
  a shaded window, only its frame's top and bottom (`shade-window!`,
  `unshade-window!`, `shaded?`), from a region of kind `shade`, the
  title's double click or its wheel (`title-wheel`); dragging live or as
  an outline (`drag-feedback`, drawn by the `draw-drag-outline` part);
  the window manager's resize edges (`frame-edge`, `frame-corner`; a
  style's regions may resize from the top too, `resize-t`, `resize-tl`,
  `resize-tr`); whether a click in a window raises it
  (`raise-on-click`); the bell, `(bell)` (`none`, or `screen` or
  `window` flashed inverted); menus (`menu-choose`: `click` or
  `release`, `menu-blink`, `menu-hover`: `fill` or `outline`); scroll
  bars (`scrollbar-side`: `right`, `left`, or `outside` in a region of
  kind `scrollbar` the frame leaves; `scrollbar-show`: `always` or
  `hover`); and the mouse documentation, `(mouse-doc)`, what each button
  does under the pointer as data (from the window's regions, a kit
  widget's `'doc`, an app's `'mouse-doc`, a surface's `'doc`), which the
  top bar shows where `mouse-doc` is on, and Genera's who line. A top
  bar 0 high is none; a style may make the taskbar another bar with its
  areas, drawing and tick (`taskbar-areas`, `draw-taskbar`,
  `taskbar-tick`).
- **The screen is a tree of lists of records.** A list is flat records
  of 32 bytes, whole numbers, that the drawing procedures write
  (`fill-box`, `draw-text`, ...); `with-clip`, `with-translation`,
  `with-scale`, `with-turn` and `with-label` are forms, with no closure a
  call. One shader on the GPU reads them, in one instanced draw for a run of
  them that's alike, in variants: a run of boxes and text in solid colors
  draws with none of the code for lines, shadows, gradients, stipples or
  images, which on Metal every pixel would pay for, and a record that needs
  one of them starts a run (`gfx-fragments`). Coverage is by distance, a
  paint times a geometry; glyphs come from an atlas on the GPU, and only
  they and what must be saved keep pixels in main memory. A list can show
  another, `(show-list lst x y)`, inside the clip around it: what
  `record-list!` recorded into it keeps its own coordinates and its own
  buffers on the GPU, and is drawn where it's shown, so moving it changes
  one run and nothing is recorded again. A window is a list from its corner,
  what `draw-window` draws, and its content a list of its own, shown in it.
  A change asks for a frame: input to a window, `(invalidate! win)`, the
  hover, the clock once a second, the world's changes. The next tick's frame
  records the wallpaper, the panels, the menu and the toasts, shows each
  window's list from the bottom up, each clipped to its extent
  (`record-world!` in `src/wm.ss`), and sends them; a list that changed goes
  up to the GPU, the others are there. A window draws again only when it
  opens or resizes, when what its frame is drawn with changes (its focus,
  the part under the mouse or held, its title, state or error), after input
  to it, and when asked, `(invalidate! win)`; `(invalidate!)` asks every
  window. Moved or raised, it isn't drawn again, and a window whose app is
  slow keeps showing what it drew. A step that nothing asked a frame of
  draws nothing. Nothing is assumed about what a drawing procedure does
  inside its window, so redefining `draw-window`, a style's part or
  `draw-taskbar` at the REPL changes the next frame each is drawn in: an
  evaluation asks every window when it ends, and so does `(reload!)`. A
  window that changes by itself over time says so with `(invalidate! win)`,
  as the Clock and Life do when they tick. The Pipeline reads the tree as
  one list (`inspect-list` in `kits/inspect.ss`): each list's records where
  its runs draw them, moved to where it's shown, which draws the same
  pixels.
- **A paint is a shader an app writes.** `define-paint` compiles when it's
  expanded: its body runs for each pixel of a box and gives a color, and
  `fill-shader` fills one, its arguments numbers, colors and GPU buffers
  (`make-gpu-buffer`, `gpu-buffer-set!`), so what changes is a few numbers and
  nothing is recorded again: Monitor's Ticks are one. `define-compute-shader` is the
  same language for compute: a small Scheme, branching with `if`, `cond`,
  `case`, `when` and `unless`. `define-shader-constant` names a number for
  shaders and Scheme alike, and `define-shader-helpers` a set of functions a
  shader takes with `use-shader-helpers`; a paint starts with `gfx-helpers`
  (`word`, `extra`, `pixels`, `clamp01`, `mixed`, `channel`, `box-distance`,
  `clip-coverage`). `define-shader-layout` names a table row's words: each
  field is its offset to Scheme and to shaders, and in a shader
  `(glyph-row-left row)` reads it. `kits/twin.ss` gives any shader as a Scheme
  procedure, to call for one pixel at a REPL; the conformance test holds the
  device and the twin together, whatever the driver. Life and Boids stay on
  the crew's worklets, by choice; Boids 3D is all shaders.
- **Boids 3D flies on the GPU.** `(boids3d)` is Boids in space, as Reynolds
  first made them: the same rules, a field of view that's a cone, Flake's
  blocker rules carried into 3D, and a pull home into a ball where Boids
  wraps at the screen's edges. Its defaults make a murmuration. A step, the
  flock laid out by the camera, the birds listed by 16-pixel tile, and the
  picture are four shaders (`boids3d-steer`, `-place`, `-bin` and the paint
  `boids3d-view`), and the flock never comes back to the CPU. Each bird is a
  body and two wings that beat, bend at the wrist and bank into turns, in a
  haze that grows with distance, so far off it looks like a real one. With a
  step every frame, at 2560 × 1600, the GPU's frame grows from 0.82 ms to
  2.01 ms with 1,000 birds and to 5.18 ms with 4,096, its most; main spends
  about 0.1 ms.
- **Drawing is single-threaded.** Recording and the world's state stay on
  the main thread; worker threads run only worklets and what a vat's sandbox
  holds. Monitor shows where each tick's time goes (above). A process may be
  switched out at any call while frames go on, so typed in a REPL (or
  called by a handler) `(render-frame!)` only asks for a frame. Next: lists
  showing lists (a window's own, moved without being drawn), then recording
  off main.
- **Pipeline shows all of this.** `(pipeline)` puts the way from a window's
  draw to the screen on one screen, reading through `kits/inspect.ss`, plain
  data that a REPL or a test can read too: the frame's list by who drew it,
  each record decoded in draw order and a run of glyphs as its text, and
  each drawer with a checkbox that leaves it out of the small screen and the
  Tape (the core's preview takes a cut of the frame's runs); Who, what each
  drawer cost, a row each in draw order: main's time drawing it a frame, its
  records, the pixels they may touch, the runs they start and how many
  changed since the frame before, each with a bar for its share; Course,
  a tick's stages in order, each as wide as its time, render split into
  each drawer's draw and the rest; Inside, the record selected decoded, its
  words and its run, and its shader's source with its helpers written out;
  Memory, what the GPU holds as bars, and the glyphs' atlas live; the
  screen small, drawn again every tick unless told otherwise and showing
  itself in its own box, a tick older each time round, with what's selected
  outlined, or showing who drew each record, in its drawer's color, the
  others dim while one's selected, or its records' kinds, or heat (a pixel
  as bright as how many records cover it), or what changed since the frame
  before, and a press there listing what may touch
  that pixel; the wheel
  zooms it at the pointer, a drag moves it, Fit and 100% set it, a loupe
  magnifies the pixels at the pointer and names the record on top there,
  and Pop out puts it in a window of its own kept above the Pipeline, back
  in its place when that window closes. Under them
  the Tape: a mark a record in draw order, as tall as what it may cover, and
  in lanes who drew it and its kind; a press or its stepper holds the frame
  and draws it as far as that record, Play draws it record by record over a
  few seconds, and what's selected in the list, or at a pixel, is marked on
  it and named on its heading, with Clear (or Esc). A record selected opens
  its drawer in the tree and stays with its drawer, at its place in it, as
  the frame changes, and a drawer keeps its color, whatever its place, while
  the Pipeline is open. Below, the River flows, a bar a tick: what main did,
  and in lanes over it whether the tick came late, the frame it sent, where
  the GPU stood, the collector, as bright as it took long, and input, green
  where all's well, a
  label's tooltip saying what its colors mean. A press holds it and goes back
  to that tick's frame, the whole app showing it, and a drag moves through
  them: the last 300 frames are kept while it's open, the images and paints
  they showed drawn again as they are now (the River's rows are kept by tick,
  so its bands come back as they were), and left out once they're let go
  of. While it flows it asks for a
  frame a tick, and says what that takes; closed, what's left of it is the
  core's few numbers a frame.
- **The profiler hooks into the core.** `src/proc.ss` keeps one hook,
  `*profile-span*` (`#f`, or a pair of procedures, begin and end), and
  `with-profile-span`, in which five places run their work: the step
  (`schevana-step!`), `safely` (each phase of the main loop, each
  surface's draw and tick), a window's handler (`window-call`, keyed
  by the window's id and the handler's kind), its drawing
  (`draw-window-clipped`, the id) and a process's turn (`run-procs!`,
  the process's id: in its turn a process runs slices for its share of
  the time left). Off, each costs a variable read and a branch, and
  the key is not even computed; nothing is allocated either way. On
  (at boot; `(profile-on! #f)` turns it off), `services/profile.ss`
  times each on `now-ns`, the monotonic clock in fixnum ns
  (`SDL_GetTicksNS`), on a stack of fixed depth, giving each its self
  time (its time less the spans inside it), so that the parts add up
  to the tick; a tick's last step's end adds them up into tables
  cleared, not made again, and rings made once. A span allocates nothing; a step's
  books allocate their one guard, under which an error turns the
  profiler off, reported once, and the world goes on. A raise out of a
  span leaves it open until the step's end closes it with the rest. A
  span inside an engine (a handler, a process) runs untimed, since an
  engine can be suspended halfway, and so does one outside a step, on
  another thread or past the stack's depth. While on, the collector's
  work is a span of its own, `gc` (its collect-request handler), and
  the memory numbers come from the collector's counters. The history is
  in defvars, so a reload keeps it. Off, a step costs what it did
  (`tests/bench.ss`); on, a step of 30 Life windows costs about 1%
  more, an idle step 10 µs more, and a busy process gets about 1% less
  done.

## Tests

```bash
mkdir -p out
scheme --script tests/smoke.ss out
```

This boots the world headlessly, types into the REPL (completing names: Tab's
pages, its popups, clicks, a small window), defines an app, crashes
windows, runs away in loops, drags and resizes windows, uses the launcher,
presses every button of each window style, clicks and drags through every
Settings tab (checking the theme file round-trips), uses Tasks by mouse and
keys (typing with selection, the clipboard and Tab, the focused field kept in
view, dropdowns, the calendar, tags, the checklist, dragging cards, sorting,
searching, filters, the context menu, the delete dialog, tooltips, the narrow
page, a description's 65,536 characters, its scroll bar, Ctrl+End and
Ctrl+Home, Page Down and Up scrolling as far as the caret moves, typing
that compares no texts, a key typed in another window that runs no scan,
and its editor's window: Save, Cancel and its question, its line and
column, Tasks waiting under a scrim, maximized, Save into a task deleted
meanwhile; what a task waits for and what waits for it in its details,
Add's menu of what makes no cycle, as much of it as fits on the screen
with many tasks (an id typed first), a choice the REPL made a cycle
meanwhile refused with a plain toast, a cycle the REPL refuses, a
blocked task moved to Done or added done; the Tree, its twisties and
keys, a shared blocker's later rows, a later row a change takes away, a
collapse that hides the selection, a search dimming rows or leaving
nothing to show, a keystroke that works out no tree again, a task
deleted there, the keys listed; a reload that changes the task record
and keeps every task) and from the REPL's procedures, uses Monitor (the
profiler collecting with it closed, its graphs, a window's name and a
process's Kill, Profiling off, the rows that focus and kill then, and on
again), uses Environments (a fork of each kind, sharing, loading through
the file dialog, syncing, dropping, an app's bundles), reloads the sources
(the profiler's history kept), runs the host's SDL code (uploads, presents, resize events, the window's size)
against a stand-in that replaces every SDL call, so no window opens, and
writes screenshots to the given folder. It asks Sketch's permissions
through the launcher and Settings, never touches your real
`~/.schevana-theme.ss` or apps' permissions, and no test reads
`~/.schevana.d`.

```bash
scheme --script tests/units.ss out
```

This runs every file of `tests/units/`, a topic each, in a process of its
own, so that none leans on what another left behind;
`scheme --script tests/units.ss out life boids` runs those alone. Together
they test the drawing layer piece by piece: measuring with no device,
text cut to fit measuring no more of a long text than its width could
show, cached shadows against the stacked ones, pixmaps, Life's
generations against a plain reference (a tick's allocates under 8 KB), on
the crew too, its grid against one rectangle per cell and, at one pixel a
cell, against the screen's own pixels at 100% and 200%, what a new size
keeps, its speeds, its threads and its painting, the side panel and its
button (where the app lays it, either side, by key, with no room), Boids in
its sandbox, its
flocking (the Niva version's tests, its steps to the last digit against
the rules written out plainly, on the crew and off it, the speed limits, a
flock carried over a reload) and its rules window (where it opens, its
sliders, buttons and keys), and the invalidation calls; and, with no
window, the edit kit (insertion, erasing, caret moves, words,
selection, pages, the most characters a text may hold, what an edit
changed, wrapping against a plain rule with even and uneven widths and
against breaking a character at a time, the rows a layout keeps and
takes back through thousands of random edits, a keystroke's measures in
each worst case bounded by the rows in view, an edit's rows past it
taken back, not measured, and a keystroke's work in an engine's ticks
bounded by the rows in view at any length), dates, flow and table keys,
and Tasks' sorting, filtering, moving, a search looked through once for
each change, the editor's line and column against a plain count, the
REPL's checks, the seed's long descriptions, what a task waits for (each
once, a cycle refused and named, whom it blocks worked out, a deleted
task forgotten), the tree of what waits for what with blockers shared,
the seed's links and what Add offers, what is kept until a link or a
status changes, Add's entries for what is typed, ids and later rows'
notes as wide as they fit, a task record from before a reload carried
over, the tree widget's rows (only expanded nodes' children asked for),
keys, indentation and dimmed rows, and the characters a keystroke in
Tasks measures, the same with a title of 100,000 characters as with one
of 10,000. The kit's charts: the bar chart's areas, the bar under the
pointer and a press on one reported by index, and each chart's look its
part's, under a style that replaces it. And the profiler: on at boot,
off (no tick kept, no clock read) and on again, nothing allocated by
20,000 spans, spans nesting and every tick's parts adding up to it, a
slow window first among the consumers, a busy process's share, a
collection in the memory numbers and as a span of its own, a span
inside an engine, on another thread or past the stack's depth untimed,
a raise out of a span, a collector made to fail turning itself off with
one error while the world draws on, a closed window and an ended
process not kept alive, two windows of one title told apart, the
history's lengths, and the charts' colors in every style. And what runs
apart: worklets and what they are refused, the crew, environments and what
a child may do with its shares, the confined base, vats and their jobs,
and apps in sandboxes (their bundles and stubs, a decision saved, read back
and denied, an app of yours that requests nothing, an app's own worklets
and what they are refused).

```bash
scheme --script tests/frame.ss out
```

This tests frames, on lavapipe (Metal on a Mac), with no window but one
offscreen (hidden on a Mac) for the swapchain's path: once the frames asked
for are drawn, the screen is the world drawn into an image, bit for bit, on
several desktops, every window
style, a menu and a toast, at 100, 125, 150, 200 and 300%; with nothing
asked for, no frame comes; every way the screen changes (the clock's second,
a window, a window under another, hover across windows and both bars, a window
dragged and resized, another moved, a process asking while the main loop
draws) shows on that frame at 100, 150 and 200%; every style, and one that glows past its frame with
and without its `'bleed`, moved, resized and hovered, shows the
reference, and drawn unclipped each registered style keeps to its
extent; with a stand-in window a boot, a resize or a rescale shows
its own frame at once, never an empty screen; a process, switched out
anywhere, may free surfaces, rescale and call `(render-frame!)` while
frames go on; drawing that raises crashes only its window, or shows no
frame, and a `window-bleed` that raises is reported while frames and
input go on; redefined `draw-window`, `draw-taskbar` and styles show at
once and cost the same, and a REPL evaluation asks for the whole screen
as it ends; a theme change (by `set-theme!` or behind its back) or a
redefined `draw-wallpaper` paints the wallpaper again for the next
frame; each generation of 30 Life windows shows on the next frame; and
Tasks shows the reference after typing, the caret's blink, hover and a
tooltip, a drag, the wheel, a field scrolled back into view, a menu, the
calendar, the dialog, a change from the REPL and the narrow page, at 100,
150 and 200%, and asks for no frame once its window loses the focus, or
while the dialog covers a field that had the keyboard, and so does its
Tree (hover, twisties, keys, the wheel, a later row, dimmed rows, links,
the Add menu); and a long description's scroll bar, drawn from an
estimate, settles when idle steps finish its rows, and when its editor's
caret row brings them to the end in the same draw.

```bash
scheme --script tests/sources.ss
```

This checks the sources themselves, and quickly: every line of every
source file is at most 80 characters, no top-level name is defined in
two files (an app in a sandbox's names are its own), `src/` stays within
its size budget, counted in tokens so that comments, names and line breaks
are free (raise it on purpose), outside `src/` no file sets a global another
defines, but the core's hooks, nothing reaches C, and only a world namespace
shares the whole world, every file in a folder registers what it defines,
under its own name (a kit's with its prefix, the desktop's plain), every
style sets only settings that exist, in the kits, the services, the desktop
layer, Tasks, Settings, Environments and Pipeline only the drawing procedures
(parts,
`draw-…`, `ui-draw-…`, `complete-draw-…`, `tasks-draw-…`, `settings-draw-…`,
`envs-draw-…`, `pipeline-draw-…`) draw or name a theme color, the edit kit never does, only
styles call a part's built-in body, what an app in a sandbox defines stays
there, a bundle names what the world has, each name in one bundle, and a
tree app requests what the table approves.

```bash
scheme --script tests/bench.ss out               # [frames]
```

Times frames on four scenes at 100% and 200%: 30 Life windows tiled,
a typical desktop of five overlapping windows, 30 Life windows cascaded,
and those under a maximized REPL, with every Life window stepping every
frame. For each it prints the main thread's time per frame (all the
work: everything runs on it), the wall time, the bytes uploaded and the
collections, then times a keystroke in the REPL, an idle step (it must
stay under 0.2 ms and upload nothing), a theme change, and the clock's
second with no window and a keystroke in a REPL alone (at 100% and
200%, and on a 1920 × 1080 screen at 200%, a 4K one), Tasks maximized
on that screen (an idle step, a keystroke in a title, two in one step, a
card dragged), a keystroke in a long description's worst cases there,
in the details and in its editor maximized, against the same in an
empty one (the least of three rounds each: it must stay within 1.25
times the empty one's in the details and 1.6 times in the editor, which
draws a screenful of text, and a jump within 2.5 times), the Tree there
with the seed and with 2,000 tasks more in chains (a key, Space and the
wheel, the least of three rounds: within 1.5 times the seed's), and
prints how much of the main thread a busy REPL evaluation gets while 30
Life windows animate at 200%, what profiling costs: a step with it on and
off (S30T at 100% and 200%, an idle step, a busy process), and the crew:
Life at one pixel a cell, maximized on that 4K screen, and Boids at 150, 450,
2,000 and 5,000, on one thread and more.

## Conventions

- Every line of every source file is at most 80 characters;
  `tests/sources.ss` checks it.
- American spelling: color, gray, center.

## Credits

Boids (`apps/boids.ss`) is ported from Eduardo Cavazos's
[Boids in Niva](https://github.com/dharmatech/boids-niva) (MIT). Its two
blocker rules, clear view and back off, follow Gary William Flake's *The
Computational Beauty of Nature* (MIT Press, 1998), written from his
description. Boids 3D (`apps/boids3d.ss`) takes the same rules into three
dimensions, as Craig Reynolds' "Flocks, Herds, and Schools: A Distributed
Behavioral Model" (SIGGRAPH 1987) first had them.

The CADR's 5X5 font in `kits/px.ss` (the glyphs of `px-5x5`) is MIT's,
decoded from System 99's `fonts/5x5.qfasl`:

Copyright (c) 1980, Massachusetts Institute of Technology. All rights
reserved. Redistribution and use in source and binary forms, with or
without modification, are permitted provided that the following
conditions are met: Redistributions of source code must retain the above
copyright notice, this list of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
Neither the names of the Massachusetts Institute of Technology nor the
names of its contributors may be used to endorse or promote products
derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## Known gaps and open questions

- Every start and `(reload!)` compiles the whole tree again, about 0.8 s,
  nearly all of it the compiler's: load time grows with the source, about
  0.63 ms a KB. Loading compiled files takes about 0.1 s, were there a cache
  of them.
- An app in a sandbox keeps no files and writes only to its log (`env-log`):
  the bundles for files and the console are still to come. Environments opens
  a REPL in its sandbox; its window's menu does not yet.
- A frame draws everything under its rectangle on the main thread. The
  rectangle is one bounding box (the top bar's clock and a window near
  the bottom make a frame of all between them) and grows to hold whole
  every window it touches, so overlapping windows are drawn again with
  one another, and while a toast or a menu shows every frame is the
  whole screen. Windows whose extent reaches into the top bar, as tiled
  ones do, are drawn again with the clock every second. With 30 animating
  Life windows, tiled, a frame takes about 3.8 ms at 100% and 8 ms at 200%;
  30 overlapping at 200%, each with its panel, take about 58 ms a frame,
  and a keystroke in a REPL among four other windows shows about 16 ms
  later at 200%. A REPL alone shows it 2.3 ms
  later (2.8 ms on a 4K screen), and the clock's second on an empty 4K
  screen takes 0.1 ms (`tests/bench.ss`). Meanwhile a busy REPL
  evaluation runs only between frames: with 30 Life windows animating
  at 200% it gets about half of what it gets with them paused. Next on
  the compositor plan: each window drawn into an image of its own, only
  when it changes, and the images composed on the CPU, then on the GPU.
- Every theme change paints the wallpaper again: a theme change takes
  about 27 ms at 100% and 88 ms at 200% until its frame is drawn, so
  dragging a color slider in Settings shows about 11 frames a second at
  200%.
- The built-in styles change mostly the windows (Genera and the CADR
  every widget too, Interlisp its scroll bars), though everything is a
  part a style may replace: each widget's drawing, size and areas, the
  bars, menus, toasts, the popups' panel, highlight, separator and card.
  Under Genera and the CADR a tooltip still floats in its box (the
  machines said it in the who line's documentation line, which shows
  only what the mouse buttons do), and a dropdown's menu still ticks
  the current choice.
  Settings draws with the kit's widgets and only its own pictures with
  its own code (the styles' miniatures, swatches, color tracks); its
  color list and its pane's scrolling are still its own. The
  "stable GUI API" question stays open: keep growing these immediate-mode
  procedures, or describe retained widget trees as data?
- Tasks redraws its whole window for a keystroke: about 11 ms on a 4K
  screen at 200%, maximized (half of it is any maximized window's frame:
  the wallpaper under it, its rows compared). In a description of 65,536
  characters a keystroke costs within a millisecond of that: a text's
  rows are computed only as far as they show, and kept; after an edit,
  those past it are taken back from before it, and the edit says where
  the text changed, so no keystroke looks at the whole text (the text
  and its rows' starts are still copied, by memcpy: about 0.02 ms at 64k
  characters). Only rows that do change are measured again, all those in
  view when an edit moves every row's break (a paragraph with no spaces,
  or rows exactly full). A jump far ahead (Ctrl+End, the scroll bar's
  thumb, a paste of the whole text) computes the rows to there once, 5
  to 8 ms; idle steps compute the rest for the scroll bar, a millisecond
  at a time. The description's editor, maximized, draws Tasks under it
  too, and a screenful of text: about 4 ms more a keystroke. With a
  search, Tasks looks through a task's texts only when they change:
  typing in a long description searches that one again at each keystroke
  (0.2 ms a word at 64k).
- Tasks keeps what it works out from which tasks there are, their
  order, statuses and links (the board order, whom each blocks, the
  Tree's shape and rows) until one of those changes, so typing costs
  nothing for them; it still passes over every task at each draw for
  its filters, the toolbar's names and tags, and the List's and Tree's
  assignee column, which measures every name, and the Board lays out
  every card of a column: with 2,000 tasks more in chains of 50, a
  keystroke in the List or the Tree costs within a millisecond of what
  it costs with the seed, in the Board about 6 ms more (with 8,000, 2
  and 18 ms more). Text cut to fit (a title, a tooltip, a menu entry)
  measures no more of it than its room could show. The details' Add
  shows the best matches that fit on the screen, then how many more:
  typing narrows them.
- The description's editor asks before Escape or Cancel drops changes,
  but its window's close button drops them without asking: the window
  manager closes a window at once and cannot ask it first.
- REPL lacks selection and copy, and there is no text editor app yet:
  the edit kit and Tasks' description editor are its start (undo, find
  and files come next).
- No persistence. Windows and state vanish on exit (`fasl-write` of app
  state is a natural first step).
- Portability: it runs on Linux and on a Mac. The library names for Windows
  are in `src/ffi.ss` but have not been tried.
