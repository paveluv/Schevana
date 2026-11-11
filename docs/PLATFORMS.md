# Platforms

Schevana runs on a stack of layers that differ from machine to machine: the
OS, the windowing protocol (Wayland, X11, the Mac's), the compositor, SDL's
version, the GPU API (Vulkan, Metal), the driver, the monitor. A feature that
works on one stack may do nothing, or something wrong, on another. This file
keeps what has run where, and where each platform-specific feature is
expected to work.

All code that differs by platform lives in the platform files:
`src/host/platform.ss` for core0's, `src/platform.ss` for the core's (the
rule is in `AGENTS.md`). Which platform this is comes only from their
predicates and facts (`host-mac?`, `host-wayland?`, `host-vulkan?`, ...),
which Monitor's Platform tab lists. A feature made on one platform is off on the others until
someone makes it there; off means "not there", never a crash.

## How to add to it

When you run Schevana on a platform, add a row to "Runs" with what you ran
and what happened, at the commit you ran. Monitor's Platform tab has a
button, "Copy as a row", that puts this run's row on the clipboard with
everything but what ran and its result. When you add or change a feature
that differs by platform, add or change its row in "Features": where it was
tested, where it should work too and why, and what happens without it.
Versions come from the machine (`scheme --version`, the package manager,
`vulkaninfo --summary`, the compositor's `--version`), not from memory; write
"not recorded" when you don't know.

## Runs

| Date | Commit | OS | Session | GPU and driver | Display | SDL | Chez | What ran | Result |
|---|---|---|---|---|---|---|---|---|---|
| 2026-11-10 | `290f48b` (gpu-first) | Debian 13.7, Linux 6.12 | GNOME Shell 48.7, Wayland | GeForce RTX 5090, NVIDIA 615.71.10 (open kernel module), `nvidia-drm vblank=1` | one, 3840×2160, 60 Hz, HDMI | 3.2.10 | 10.0.0 | the four suites (lavapipe, Mesa 25.0.7, headless); a real window | pass; works |
| 2026-11-07 | `9a652e7` (gpu-first) | macOS, version not recorded | the Mac's | Apple M3 Pro, Metal | built-in, ProMotion (120 Hz) | 3.4 (Homebrew) | Homebrew's, version not recorded | the four suites (Metal, headless); a real window | pass; works |

Never run: Windows; X11 sessions (Xorg) and XWayland; KDE's KWin and the
wlroots compositors (Sway, Hyprland); Mesa's GPU drivers (AMD, Intel, NVK)
in a real window; Intel Macs; variable refresh rate; several monitors.

## Features

| Feature | Where | Tested on | Expected to work on | Without it |
|---|---|---|---|---|
| Drawing on Vulkan, shaders as SPIR-V | `src/host/gpu.ss`, `src/shader.ss` | NVIDIA 615; lavapipe (Mesa 25.0.7) | any Vulkan driver SDL 3.2 or later opens | lavapipe, on the CPU |
| Drawing on Metal, shaders as MSL text | `src/host/gpu.ss`, `src/shader.ss` | M3 Pro, SDL 3.4 | Apple silicon Macs with SDL 3.2 or later; Intel Macs untried | none: Metal is a Mac's only renderer |
| Choosing the Vulkan driver by its file, lavapipe kept out unless asked | `src/host/gpu.ss` (`gpu-driver-files`) | Debian 13 | distributions with drivers in `/usr/share/vulkan/icd.d`, `/etc/vulkan/icd.d` or `/usr/local/share/vulkan/icd.d` | SDL chooses the driver |
| Running with no window | `src/host/gpu.ss` | Linux: SDL's offscreen driver and lavapipe; Mac: Metal | the same SDL and drivers | none: the suites need it |
| When each frame reached the screen (`wp_presentation`): the Pipeline's screen and latency lanes, Monitor's "Input to screen" | `src/host/platform.ss` | GNOME Shell 48.7 with NVIDIA 615: it says `CLOCK_MONOTONIC`, but its times are on `CLOCK_MONOTONIC_RAW`, 165 ms apart after 9 hours up; each report is checked against when its frame was sent, and read on the first clock it fits | Wayland compositors that offer `wp_presentation`: KWin, wlroots, Weston | no reports: those lanes and lines stay empty, everything else works (X11, XWayland, the Mac, Windows) |
| When each input came | `src/host/window.ss` (SDL's event times) | GNOME Shell 48.7, SDL 3.2.10 | any SDL 3 platform; SDL guesses the compositor's clock from the first event, so latency can read low | no latency figure |
| When the GPU finished each frame | `src/host/present.ss` (SDL's fences) | NVIDIA 615 | any SDL GPU back end | the GPU lane stays empty |
| A thread's CPU time | `src/base.ss` (`thread-cpu-clock`: 3 on Linux, 16 on a Mac) | Linux; the Mac | Linux, macOS | — |
| The Debug REPL's socket | `src/host.ss` (the address's layout differs on a Mac) | Linux; the Mac | Linux, macOS; not Windows | — |
| The generic font names asking for DejaVu first | `src/font.ss` (`font-generic-families`) | the Mac | macOS | the system's own fonts, taller lines |
| The window's app id (Wayland) and class (X11) | `src/host/window.ss` | GNOME Shell 48.7 | freedesktop desktops | a generic icon |
| The desktop entry (`--install-desktop`) | `desktop/icon.ss` | GNOME Shell 48.7 | freedesktop desktops | launched from a terminal only |
| The process's memory in the top bar (the number after "/") | `src/platform.ss` (`host-process-bytes`: `/proc/self/status`'s `VmRSS` on Linux, `proc_pid_rusage` on a Mac) | Linux | Linux; macOS, written and not run | the heap alone, with no "/" |
| The machine's load in the Pipeline's facts | `src/platform.ss` (`host-machine-load`: `getloadavg`) | Linux | Linux, macOS | the line is left out |
| Presenting modes offered in Settings (VSync, Mailbox) | `src/host/gpu.ss` (`gpu-present-modes`, asked of SDL per window) | NVIDIA 615 offers both; the Mac's Metal offers no Mailbox, so Settings shows no Presenting row there | whatever SDL says the window supports | VSync alone, the row hidden |
| What the host is: the predicates and facts, Monitor's Platform tab | `src/base.ss`, `src/platform.ss`, `src/host/platform.ss` | Linux, GNOME Shell 48.7, SDL 3.2.10 | anywhere; the GPU's name and driver need SDL 3.4 (written, not run), the system's name `/etc/os-release` or a Mac's `sysctl` | "not known here" for what a system doesn't say |
| The trace: each frame's steps on core0 and main, with the screen's reports, to `.work/traces/` | `src/host/trace.ss` | Linux, GNOME Shell 48.7 | anywhere with a window; written at quit or on `(host-trace-dump!)` | nothing written without a `.work` folder |
| Hardware vblank stamps with NVIDIA | [LINUX_NVIDIA_TUNING.md](LINUX_NVIDIA_TUNING.md) | NVIDIA 615.71.10 under GNOME Shell 48.7 | other NVIDIA versions under Mutter, unverified | now and then a refresh shows the previous frame again |

Where a row names a file other than the platform files, that is where it
sits today, and it is to move there.
