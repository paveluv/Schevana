# Schevana

![Schevana: a REPL and a Clock in the Spine style](docs/screenshot.png)

A Lisp Machine-style desktop that lives inside one window and is written
entirely in Chez Scheme. Every window, color, key binding, status-bar segment,
running process and GPU shader is a live Scheme value (shaders are written in
Scheme too, and compiled for the GPU as they're defined). You can inspect it,
redefine it and break it from a REPL that runs inside the world it changes.

The only C code involved is SDL3 (the window, input and the GPU),
FreeType and fontconfig (fonts), all called through Chez's FFI. There is no
build step: the whole world compiles from source in about 0.8 s at
startup, and again at each `(reload!)`.

## Running

Schevana needs Chez Scheme 10, SDL 3.2 or later, FreeType, fontconfig, and
Vulkan on Linux or Metal on a Mac.

On Debian 13 (it should work on Ubuntu 26.04 or later too, although I
haven't tried):

```bash
sudo apt install chezscheme libsdl3-0 mesa-vulkan-drivers
```

With NVIDIA's driver on Wayland, turn on its hardware vblank stamps (one
module option and a reboot,
[docs/LINUX_NVIDIA_TUNING.md](docs/LINUX_NVIDIA_TUNING.md)). It's not
required, but can improve VSYNC experience with animated apps such as
Boids 3D.

On a Mac:

```bash
brew install chezscheme sdl3 freetype fontconfig
```

Then, with no build step:

```bash
./schevana
```

The options, the files it reads and writes, and the details for each
platform are in [docs/INSTALL.md](docs/INSTALL.md).

| Key | Action |
| --- | --- |
| F1 / click "λ Schevana" / right-click desktop | launcher (type to filter); apps picked after a right-click open where you clicked |
| Ctrl+Tab | cycle windows |
| Ctrl+Shift+W / M / N / T / R | close / maximize / minimize / tile / new REPL |
| F11 | full screen on and off (also in the launcher) |
| F12 | screenshot to `~/schevana-N.png` |
| drag title, edges, corner; double-click title | move, resize, maximize |
| right-click title or taskbar button | window menu (incl. "Bind to `$w`") |

## The REPL

Ctrl+Shift+R or `(repl)` opens one. Enter evaluates a complete form, and
Shift+Enter adds a line; Up and Down walk the history, Tab completes, and
Ctrl+C stops what's running. What you type runs as a Schevana process
(backed by a Chez engine), so the desktop goes on meanwhile.

Every example in [docs/](docs/) works as it is: copy it from your browser
or editor and paste it into a REPL with Ctrl+V, which reads the system
clipboard, taking a page's examples in order. (I'll add copying from a
REPL to the system clipboard soon.) A test runs them all
(`tests/units/docs.ss`). The kinds of REPL, and what a `define` does in
each, are in [docs/REPL.md](docs/REPL.md).

## The guide

A programmer's guide, taught at the REPL, in reading order:

- [Installing and running](docs/INSTALL.md): what it needs, its options,
  the files it keeps
- [The REPL](docs/REPL.md): the world as data, redefining it, the kinds
  of REPL, libraries
- [Windows, apps and events](docs/WINDOWS.md): handlers, properties,
  frames, keys, timers, processes
- [Drawing](docs/DRAWING.md): shapes, text, clips, gradients, pixels
- [Widgets](docs/UI.md): the kit every app here is built with
- [The look](docs/LOOKS.md): settings, styles, parts, palettes,
  wallpapers
- [Your own apps](docs/APPS.md): keeping what you make, sandboxes
- [Shaders](docs/SHADERS.md): Scheme on the GPU
- [Environments](docs/ENVIRONMENTS.md): the tree of namespaces, sandboxes
- [Threads](docs/THREADS.md): worklets, the crew, vats
- [Monitoring](docs/MONITORING.md): Monitor, the Pipeline, the profiler,
  the Debug REPL
- [Internals](docs/INTERNALS.md): the boot chain, frames, the pacer
- [Testing](docs/TESTING.md): the suites, and adding a check
- [Platforms](docs/PLATFORMS.md): what has run where;
  [NVIDIA on Linux](docs/LINUX_NVIDIA_TUNING.md)

## Tests

```bash
mkdir -p out
scheme --script tests/smoke.ss out
scheme --script tests/units.ss out
scheme --script tests/frame.ss out
scheme --script tests/sources.ss
```

What each suite covers, how to add a check, and the bench are in
[docs/TESTING.md](docs/TESTING.md).

## Conventions

- Every line of every source file is at most 80 characters;
  `tests/sources.ss` checks it.
- American spelling: color, gray, center.

## Credits

What Schevana takes from others, and under which terms, is in
[CREDITS.md](CREDITS.md).

## Known gaps, and after v1

- Every start and `(reload!)` compiles the whole tree again, about 0.8 s.
- An app in a sandbox keeps no files and writes only to its log.
- The REPL has no selection or copy, though Ctrl+V pastes from outside,
  and there's no text editor app yet.
- Windows and their state vanish on exit: only the look and what you
  allowed the apps are kept.
- It runs on Linux and on a Mac; I haven't tried Windows yet.

After v1, I plan to turn the apps' sandboxes and grants into a module
system of Schevana's own, built on environments: a module imports and
exports names, and a grant is a module's environment, imported. Kits and
probably themes will become modules too, installable from third parties;
an app will be able to span several files; and modules will be compiled
ahead, for a faster start. And I'll make the profiler, which now sees
only how long the collector ran, profile it properly: what allocates, by
window, process and procedure, and what each collection costs.
