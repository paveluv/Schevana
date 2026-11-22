# Installing and running

Schevana needs Chez Scheme 10, SDL 3.2 or later, FreeType and fontconfig
(usually installed already on a Linux desktop), and a GPU API: Vulkan on
Linux, Metal on a Mac. There is no build step: the first time `./desktop`
starts, it compiles Schevana's libraries into the tree's `.cache/`, and
later starts load them from there, compiling again only a library whose
file changed. The world's plain files (`.ss`, such as `~/.schevana.ss`)
load from source.

What has run where, and which features differ by platform, is in
[PLATFORMS.md](PLATFORMS.md).

## Linux

On Debian 13 (Ubuntu 26.04 or later has these packages too, though it
hasn't been tried there):

```bash
sudo apt install chezscheme libsdl3-0 mesa-vulkan-drivers
```

`mesa-vulkan-drivers` holds lavapipe, the Vulkan driver that runs on the
CPU. The tests run on it, and Schevana falls back on it when no GPU
device opens. The tests need `spirv-tools` too
([TESTING.md](TESTING.md)).

SDL chooses between Wayland and X11 by itself; `SDL_VIDEO_DRIVER=x11
./desktop` (or `wayland`) makes the choice for it. With NVIDIA's driver
on Wayland, set the module option in
[LINUX_NVIDIA_TUNING.md](LINUX_NVIDIA_TUNING.md); without it, the
compositor now and then shows a frame again although the next one was
ready.

## A Mac

From [Homebrew](https://brew.sh):

```bash
brew install chezscheme sdl3 freetype fontconfig
```

The world draws on Metal: Schevana writes its shaders in Metal's shading
language and the system compiles them, so Xcode isn't needed. For the
fonts Linux has, install DejaVu too. Without it, `sans-serif` and
`monospace` are Lucida Grande and Menlo, which Schevana asks for in place
of what fontconfig would choose:

```bash
brew install --cask font-dejavu
```

Homebrew installs Chez Scheme as the command `chez`, not `scheme`; the
launchers run under `scheme-script`, which it installs too. Schevana
finds Homebrew's libraries in `/opt/homebrew/lib` (Apple silicon) or
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
./desktop --size 1600x1000 --eval '(life)' demo
```

| Option | What it does |
| --- | --- |
| `--size WxH` | the window's size |
| `--fullscreen` | full screen from the start (F11 turns it off and on) |
| `--eval EXPR` | evaluates `EXPR` in the world once all of it has loaded; may be given more than once |
| `--headless` | no window: the world runs offscreen, as in the tests |
| `--fork` | runs core1 on a thread of its own, even when headless |
| `--hacker` | the hacker edition: every library's names, its internal ones too, are in the world, to see and redefine live ([INTERNALS.md](INTERNALS.md)) |
| `FOLDER`... | folders that join the library search and load with the world, with the folders inside them, at boot and at each `(reload!)` ([APPS.md](APPS.md)); `./desktop demo` adds the demos' apps |
| `--install-desktop` | installs a `.desktop` file, for the icon (below) |
| `--uninstall-desktop` | removes it |

Three demos are programs of their own on the core, with no desktop, each
with a launcher beside `./desktop` (below); with `--headless`, each draws
with no window and reports what it read back. On the desktop,
`./desktop demo` adds Rings as an app, and a REPL loads the game by its
name: `(import (games fireflies))`, then `(fireflies)`. The checklist is a
plain script with no library of its own: `window-demo.ss` imports what it
needs and opens its window, and `window-demo.sh` runs it with the tree as
Chez's library folder, while Chez compiles each library into the
launchers' cache as it is imported.

| Launcher | What it runs |
| --- | --- |
| `./game-demo` | Fireflies, a game that has the whole screen to itself |
| `./window-demo.sh` | a checklist made with the widget kit, an app on the host's desktop: it takes the host's look (Adwaita on GNOME), or any of Schevana's styles with `--style NAME` |
| `./rings-demo` | drawing alone, with no windows: six paints of the shader language at once (ripples, plasma, a Julia set, metaballs, cells and fire) |

A demo program builds into one file that runs without the tree:

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
so install one once; it goes under `~/.local/share` (or
`$XDG_DATA_HOME`):

```bash
./desktop --install-desktop
```
