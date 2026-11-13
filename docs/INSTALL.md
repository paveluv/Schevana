# Installing and running

Schevana needs Chez Scheme 10, SDL 3.2 or later, FreeType and fontconfig
(usually installed already on a Linux desktop), and a GPU API: Vulkan on
Linux, Metal on a Mac. There is no build step: `./schevana` compiles the
world from source as it starts.

What has run where, and which features differ by platform, is in
[PLATFORMS.md](PLATFORMS.md).

## Linux

On Debian 13:

```bash
sudo apt install libsdl3-0 mesa-vulkan-drivers
```

`mesa-vulkan-drivers` holds lavapipe, the Vulkan driver on the CPU. The
tests run on it, and it takes over when no GPU can open. The tests want
`spirv-tools` too ([TESTING.md](TESTING.md)).

SDL chooses between Wayland and X11 by itself; `SDL_VIDEO_DRIVER=x11
./schevana` (or `wayland`) chooses for it. With NVIDIA's driver on
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

Homebrew's Chez Scheme is the command `chez`, not `scheme`. `./schevana`
runs whichever of the two it finds, and finds Homebrew's libraries in
`/opt/homebrew/lib` (Apple silicon) or `/usr/local/lib` (Intel).

## Running

```bash
./schevana
```

```bash
./schevana --size 1600x1000 --eval '(life)'
```

| Option | What it does |
| --- | --- |
| `--size WxH` | the window's size |
| `--fullscreen` | full screen from the start (F11 switches) |
| `--eval EXPR` | evaluates `EXPR` in the world once it's up; may repeat |
| `--headless` | no window: the world runs offscreen, as in the tests |
| `--fork` | core1 on a thread of its own even when headless |
| `--install-desktop` | installs a `.desktop` file, for the icon (below) |
| `--uninstall-desktop` | removes it |

## Your files

| File | What it holds |
| --- | --- |
| `~/.schevana.ss` | your code, loaded at boot, like `.emacs` |
| `~/.schevana.d/` | your apps, styles, palettes, wallpapers, kits, services and desktop code, in folders of those names, loaded at boot and at each `(reload!)` ([APPS.md](APPS.md)) |
| `~/.schevana.d/lib/` | your R6RS libraries ([REPL.md](REPL.md)) |
| `~/.schevana-theme.ss` | the look you chose in Settings; plain data, never evaluated |
| `~/.schevana.d/permissions.ss` | what you allowed the apps in sandboxes; plain data |

## The icon

The window's taskbar icon is the wallpaper's λ in your theme's colors,
drawn by `draw-app-icon`: redefine it, then call `(update-app-icon!)`.
GNOME and similar desktops take app icons from `.desktop` files instead,
so install one once; it goes under `~/.local/share`:

```bash
./schevana --install-desktop
```
