# Installing and running

Schevana needs Chez Scheme 10, SDL 3.2 or later, FreeType and fontconfig
(usually installed already on a Linux desktop), and a GPU API: Vulkan on
Linux, Metal on a Mac. There is no build step: `./desktop`
compiles Schevana's libraries the first time it starts, into the tree's
`.cache/`, and loads them from there after, until one's file changes; the
world's own files load from source.

What has run where, and which features differ by platform, is in
[PLATFORMS.md](PLATFORMS.md).

## Linux

On Debian 13 (Ubuntu 26.04 or later has these packages too, though it
hasn't been tried there):

```bash
sudo apt install chezscheme libsdl3-0 mesa-vulkan-drivers
```

`mesa-vulkan-drivers` holds lavapipe, the Vulkan driver on the CPU. The
tests run on it, and it takes over when no GPU can open. The tests need
`spirv-tools` too ([TESTING.md](TESTING.md)).

SDL chooses between Wayland and X11 by itself; `SDL_VIDEO_DRIVER=x11
./desktop` (or `wayland`) chooses for it. With NVIDIA's driver on
Wayland, set the one module option in
[LINUX_NVIDIA_TUNING.md](LINUX_NVIDIA_TUNING.md), or the compositor now
and then shows a frame again although the next was ready.

## A Mac

From [Homebrew](https://brew.sh):

```bash
brew install chezscheme sdl3 freetype fontconfig
```

The world draws on Metal, its shaders written out as Metal's language and
compiled by the system, so Xcode isn't needed. For the fonts Linux has,
install DejaVu too; without it, `sans-serif` and `monospace` are Lucida
Grande and Menlo, not what fontconfig would choose:

```bash
brew install --cask font-dejavu
```

Homebrew's Chez Scheme is the command `chez`, not `scheme`; the launchers
run under `scheme-script`, which it installs too. Schevana finds
Homebrew's libraries in `/opt/homebrew/lib` (Apple silicon) or
`/usr/local/lib` (Intel) by itself (`(schevana ffi)`), with no loader
variable set.

The tests need `spirv-tools` too ([TESTING.md](TESTING.md)): they write
the shaders as Linux's SPIR-V and check it, so a change made on a Mac is
checked for Vulkan as well.

```bash
brew install spirv-tools
```

## Running

```bash
./desktop
```

```bash
./desktop --size 1600x1000 --eval '(life)'
```

| Option | What it does |
| --- | --- |
| `--size WxH` | the window's size |
| `--fullscreen` | full screen from the start (F11 switches) |
| `--eval EXPR` | evaluates `EXPR` in the world once it's up; may repeat |
| `--headless` | no window: the world runs offscreen, as in the tests |
| `--fork` | core1 on a thread of its own even when headless |
| `--hacker` | the hacker edition: every library's names, internals too, in the world, to see and redefine live ([INTERNALS.md](INTERNALS.md)) |
| `PATH`... | files and folders to load with the world, folders recursively, at boot and at each `(reload!)`, after the screen shows (`./desktop demo` adds the demos' apps) |
| `--install-desktop` | installs a `.desktop` file, for the icon (below) |
| `--uninstall-desktop` | removes it |

The demos are programs on the core, with no desktop, each with a
launcher beside `./desktop`; `--headless` draws a frame and tells what it
read back. On the desktop, `./desktop demo` adds the rings as an app, and
a REPL loads the game by its name: `(import (games fireflies))`, then
`(fireflies)`. The checklist is a plain script, no library of its own:
`window-demo.ss` imports what it needs and opens its window, and
`window-demo.sh` runs it with the tree as Chez's library folder,
Chez compiling each library into the launchers' cache as it's imported.

| Launcher | What it runs |
| --- | --- |
| `./game-demo` | Fireflies, a game, the screen its own |
| `./window-demo.sh` | a checklist made of the widget kit, an app of the host's desktop: its look the host's (Adwaita on GNOME), or any of Schevana's with `--style NAME` |
| `./rings-demo` | drawing alone, below the windows: a shader and a box that follows the mouse |

A demo builds into one file that runs with no tree:

```bash
scheme --script src/build.ss games fireflies fireflies-main
scheme --program out/lib/fireflies.so
```

## Your files

| File | What it holds |
| --- | --- |
| `~/.schevana.ss` | your code, loaded at boot, like `.emacs` |
| `~/.schevana.d/` | your apps, styles, palettes, wallpapers, kits, services and desktop code, in folders of those names, loaded at boot and at each `(reload!)` ([APPS.md](APPS.md)) |
| `~/.schevana.d/lib/` | your R6RS libraries ([REPL.md](REPL.md)) |
| `~/.schevana-theme.ss` | the look you chose in Settings; plain data, never evaluated |

## The icon

The window's taskbar icon is the wallpaper's λ in your theme's colors,
drawn by `draw-app-icon`: redefine it, then call `(update-app-icon!)`.
GNOME and similar desktops take app icons from `.desktop` files instead,
so install one once; it goes under `~/.local/share`:

```bash
./desktop --install-desktop
```
