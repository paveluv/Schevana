# Platforms

Schevana runs on a stack of layers that differ from machine to machine: the
OS, the windowing protocol (Wayland, X11, the Mac's), the compositor, SDL's
version, the GPU API (Vulkan, Metal), the driver, the monitor. A feature that
works on one stack may do nothing, or something wrong, on another. This file
keeps what has run where, and where each platform-specific feature is
expected to work.

All code that differs by platform lives in the platform files:
`src/core0/platform.ss` for core0's, `src/core1/platform.ss` for the core's
(the rule is in `AGENTS.md`). Which platform this is comes only from their
predicates and facts (`platform-mac?`, `platform-wayland?`, `platform-vulkan?`, ...),
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
| 2026-11-14 | `cd55a1c` (v1) | Ubuntu 26.04.1, Linux 7.0 | GNOME Shell 50.1, Wayland | GeForce GTX 1650 Ti with Max-Q Design, a laptop's, beside its Intel UHD Graphics (Comet Lake-H); NVIDIA 595.99.02 (open kernel module), whose `nvidia-drm` has no `vblank` option | one, 3840×2160, 29.98 Hz, HDMI, scale 2 (the built-in panel off) | 3.4.2 | 10.4.1 | the four suites (lavapipe, Mesa 26.0.8, headless); a real window | the suites' style, looks, Pipeline, Tasks and frame checks fail alike (sans-serif is Noto Sans here), and so do edit's keystroke check, under Chez 10.4, and now and then the Pipeline's River check; works. Boids 3D: 24 refreshes repeated in 69 s, one each, while its frames came a refresh apart; the screen's sequence doesn't show them, since it steps once a frame shown, not once a refresh. A light window dragged: 122 ms from input to screen (the median; 262 at the 90th percentile), 68 of them from the GPU's done to shown. A drag ends where the pointer leaves the window: SDL says the button went up there |
| 2026-11-11 | `b32e4fb` (gpu-first) with the Mac's reports, the pacer's depth and the collections after the send, the commits after it | macOS 15.7.9, Darwin 24.6.0 | the Mac's | Apple M3 Pro, Metal 3 | built-in Liquid Retina XDR, 3024×1964, ProMotion (120 Hz) | 3.4.18 | 10.4.1 | the four suites (Metal, headless); a real window | pass; works, every frame reported |
| 2026-11-11 | `85bf525` (gpu-first) and the pacer's newest reports | Debian 13.7, Linux 6.12 | GNOME Shell 48.7, Wayland | Intel Arrow Lake-U (Core Ultra 7 255U), Mesa 25.0.7 (ANV), i915 | built-in OLED, 2880×1800, 120 Hz, scale 2, HDR (BT.2100) | 3.2.10 | 10.0.0 | the four suites (lavapipe, headless); a real window | the suites' style, looks, Pipeline, Tasks and frame checks fail alike at `85bf525` (sans-serif is Noto Sans here); works |
| 2026-11-10 | `290f48b` (gpu-first) | Debian 13.7, Linux 6.12 | GNOME Shell 48.7, Wayland | GeForce RTX 5090, NVIDIA 615.71.10 (open kernel module), `nvidia-drm vblank=1` | one, 3840×2160, 60 Hz, HDMI | 3.2.10 | 10.0.0 | the four suites (lavapipe, Mesa 25.0.7, headless); a real window | pass; works |
| 2026-11-07 | `9a652e7` (gpu-first) | macOS, version not recorded | the Mac's | Apple M3 Pro, Metal | built-in, ProMotion (120 Hz) | 3.4 (Homebrew) | Homebrew's, version not recorded | the four suites (Metal, headless); a real window | pass; works |

Never run: Windows; X11 sessions (Xorg) and XWayland; KDE's KWin and the
wlroots compositors (Sway, Hyprland); Mesa's GPU drivers (AMD, Intel, NVK)
in a real window; Intel Macs; variable refresh rate; several monitors.

## Features

| Feature | Where | Tested on | Expected to work on | Without it |
|---|---|---|---|---|
| Drawing on Vulkan, shaders as SPIR-V | `src/core0/gpu.ss`, `src/core1/shader.ss` | NVIDIA 615; lavapipe (Mesa 25.0.7) | any Vulkan driver SDL 3.2 or later opens | lavapipe, on the CPU |
| Drawing on Metal, shaders as MSL text | `src/core0/gpu.ss`, `src/core1/shader.ss` | M3 Pro, SDL 3.4 | Apple silicon Macs with SDL 3.2 or later; Intel Macs untried | none: Metal is a Mac's only renderer |
| Choosing the Vulkan driver by its file, lavapipe kept out unless asked | `src/core0/gpu.ss` (`gpu-driver-files`) | Debian 13 | distributions with drivers in `/usr/share/vulkan/icd.d`, `/etc/vulkan/icd.d` or `/usr/local/share/vulkan/icd.d` | SDL chooses the driver |
| Running with no window | `src/core0/gpu.ss` | Linux: SDL's offscreen driver and lavapipe; Mac: Metal | the same SDL and drivers | none: the suites need it |
| When each frame reached the screen (`wp_presentation`): the Pipeline's screen and latency lanes, Monitor's "Input to screen" | `src/core0/platform.ss` | GNOME Shell 48.7 with NVIDIA 615: it says `CLOCK_MONOTONIC`, but its times are on `CLOCK_MONOTONIC_RAW`, 165 ms apart after 9 hours up; each report is checked against when its frame was sent, and read on the first clock it fits | Wayland compositors that offer `wp_presentation`: KWin, wlroots, Weston | no reports: those lanes and lines stay empty, everything else works (X11, XWayland, Windows) |
| When each frame reached the screen, on the Mac (Metal's presented handlers, `presentedTime`): the same lanes and lines | `src/core0/platform.ss` (SDL's `CAMetalLayer` given a subclass whose `nextDrawable` adds the handler; the handler, a block whose code is Scheme's, runs on Apple's threads and writes a ring core0 reads) | macOS 15.7.9, M3 Pro, built-in display at 120 Hz, SDL 3.4.18, Chez 10.4.1: every frame reported, the times on `CLOCK_UPTIME_RAW` as Apple says; no display sequence, so it's counted from the times at the window's rate | Macs with SDL 3.2 or later, which tags its Metal view (`SDL.window.cocoa.metal_view_tag`); Intel Macs untried | the layer not found, or already given a class of another's (KVO's): no reports, as on X11 |
| When each input came, by SDL's stamp | `src/core0/window.ss` (SDL's event times) | GNOME Shell 48.7, SDL 3.2.10: SDL anchors the compositor's ms times to its clock at the first event it sees, and only moves them earlier after, so its stamps run late by the shortest delivery it has seen | any SDL 3 platform | no latency figure |
| When each input came, by the compositor's own time | `src/core0/platform.ss` (core0's own `wl_pointer` and `wl_keyboard`, version 1, on its queue) | GNOME Shell 48.7: ms only (it has no `zwp_input_timestamps_v1`), read on the first clock under which the input came before core0 read it | Wayland compositors | the Pipeline's Latency shows SDL's stamp alone (X11, the Mac, Windows) |
| When the GPU finished each frame | `src/core0/present.ss` (SDL's fences) | NVIDIA 615 | any SDL GPU back end | the GPU lane stays empty |
| A thread's CPU time | `src/core1/platform.ss` (`thread-cpu-clock`: 3 on Linux, 16 on a Mac) | Linux; the Mac | Linux, macOS | — |
| The Debug REPL's socket | `src/core1/socket.ss` (the address's layout differs on a Mac) | Linux; the Mac | Linux, macOS; not Windows | — |
| The generic font names asking for DejaVu first | `src/core1/font.ss` (`font-generic-families`) | the Mac | macOS | the system's own fonts, taller lines |
| The window's app id (Wayland) and class (X11) | `src/core0/window.ss` | GNOME Shell 48.7 | freedesktop desktops | a generic icon |
| The desktop entry (`--install-desktop`) | `desktop/icon.ss` | GNOME Shell 48.7 | freedesktop desktops | launched from a terminal only |
| Core1 at the class core0's runs at, the user-interactive one | `src/core0/platform.ss` (`platform-thread-interactive!`, `pthread_set_qos_class_self_np`), called as `src/core0/boot.ss` forks core1 | macOS 15.7.9, M3 Pro: the process's first thread runs at `QOS_CLASS_USER_INTERACTIVE`, a thread forked at `QOS_CLASS_DEFAULT` till it asks | Macs | the OS's default for core1 (Linux, Windows) |
| The process's memory in the top bar (the number after "/") | `src/core1/platform.ss` (`platform-process-bytes`: `/proc/self/status`'s `VmRSS` on Linux, `proc_pid_rusage` on a Mac) | Linux | Linux; macOS, written and not run | the heap alone, with no "/" |
| The machine's load in the Pipeline's facts | `src/core1/platform.ss` (`platform-machine-load`: `getloadavg`) | Linux | Linux, macOS | the line is left out |
| Ticks just in time for the compositor's latch, and its queue drained when deep | `src/core1/system.ss` (`pacer-just-in-time`, `pacer-latch!`, `pacer-behind!`) | GNOME Shell 48.7 with NVIDIA 615: a frame's publish to the screen 58 → 24 ms under the Pipeline and Boids 3D, 7.4 ms for a light window, no refresh missed in 2 × 21 s each. GNOME Shell 48.7 with Intel's Mesa 25.0.7 at 120 Hz: the reports come four frames behind, so they are read by the newest in; a redraw every refresh 43 → 10.6 ms, 8 refreshes repeated in 20 s; Boids 3D 24 → 11.5 ms, 58 repeated → 5 to 30. macOS 15.7.9, M3 Pro, built-in display at 120 Hz: WindowServer frees an image a tenth of a refresh after a vsync and shows a frame two refreshes past the first after that, the compositor's depth, learned within half a second; a light window's publish to the screen 33.6 → 24.7–25.4 ms (the grid's pacing before), 3 to 5 refreshes repeated in 14 s, most of them WindowServer missing one itself; the Pipeline on its Latency view 25.1–26.2 ms, 4 to 8 repeated (15 in a run whose start was slow). Fullscreen, when macOS shows the frame without compositing it (2 runs of 4), 10.6–11.7 ms, a depth of 0 learned; else as a window. A layer of 2 drawables instead of 3: 25–40 ms, 8 to 84 repeated (`.work/macjit`, `variants.sh`) | Wayland compositors that offer `wp_presentation`; Macs; how far each keeps frames under load will differ | the grid's pacing, as before (X11, XWayland, Windows) |
| The pacer's margin fades over a minute, or stays | `src/core1/platform.ss` (`platform-pacer-margin-fade`) | GNOME Shell 48.7 under Wayland, staying: a margin that faded sent a frame late a minute or two with the pointer still; kept, 2 misses in 2691 frames after boot, both the margin learning. macOS 15.7.9, M3 Pro: fading, as the Mac's numbers above were measured | everywhere: the margin stays, but on a Mac | the margin stays |
| Presenting modes offered in Settings (VSync, Mailbox) | `src/core0/gpu.ss` (`gpu-present-modes`, asked of SDL per window) | NVIDIA 615 offers both; the Mac's Metal offers no Mailbox, so Settings shows no Presenting row there | whatever SDL says the window supports | VSync alone, the row hidden |
| Which platform this is: the predicates and facts, Monitor's Platform tab | `src/base.ss`, `src/core1/platform.ss`, `src/core0/platform.ss` | Linux, GNOME Shell 48.7, SDL 3.2.10; Ubuntu 26.04, GNOME Shell 50.1, SDL 3.4.2, the GPU's name and driver too | anywhere; the GPU's name and driver need SDL 3.4, the system's name `/etc/os-release` or a Mac's `sysctl` | "not known here" for what a system doesn't say |
| The trace: each frame's steps on core0 and core1, with the screen's reports, to `.work/traces/` | `src/core0/trace.ss` | Linux, GNOME Shell 48.7 | anywhere with a window; written at quit, on `(core0-trace-dump!)`, on Ctrl-C (Chez's keyboard interrupt, on the process's first thread) and when core1 stops stepping | nothing written without a `.work` folder |
| Hardware vblank stamps with NVIDIA | [LINUX_NVIDIA_TUNING.md](LINUX_NVIDIA_TUNING.md) | NVIDIA 615.71.10 under GNOME Shell 48.7 | other NVIDIA versions under Mutter, unverified | now and then a refresh shows the previous frame again |

Where a row names a file other than the platform files, that is where it
sits today, and it is to move there.
