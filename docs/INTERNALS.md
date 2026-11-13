# Internals

How Schevana is put together, for changing its core. The rules every
change follows are in [AGENTS.md](../AGENTS.md); this page says how the
pieces work.

## The tree

```
main.ss      boots core0
src/base.ss  what every environment has, a copy each: pure, no state, no C;
             define-exports, by which a layer gives the next its names
src/core0/   "/core0", below the core: SDL, the window and its events, the
             GPU's device side, the trace; how a C binding is made; makes
             "/recorder" and "/core1"
src/recorder/  "/recorder", sealed: the bytes of frames and their writers
src/core1/   "/core1", the core, the world's runtime:
  boot       core1's thread and environment; making "/"
  system     core1's loop, timers, inject!, reload!, loading the world
  wm         windows, z-order, focus, hit testing, dragging, dispatch;
             the registries of surfaces and strips
  proc       processes and the watchdog (Chez engines); notify,
             report-error!; the profiler's hook; worklets
  screen     core0's window as the world sees it: scale, full screen,
             icon, SDL's events as Scheme lists
  gfx        the drawing procedures, colors, stipples, gradients, clips,
             images and paints, all written as records
  gpu        the GPU layer in the world's terms: frames, images, buffers,
             compute
  shader     the shader language's compiler, to SPIR-V or Metal's language
  font       fonts by fontconfig, glyphs by FreeType, the atlas, measuring
  theme      settings in layers, rules, palettes, styles, parts
  platform   what differs by platform, of the core's; core1's clocks
  socket     local sockets, for what talks to the world from outside
  ffi        core1's own C: FreeType, fontconfig, sockets
  export     what the world is given of the core
kits/        libraries, pure or almost: ui, edit, text, color, px, ...
services/    long-lived state behind procedures: crew, env, grant,
             profile, theme-file, vat
desktop/     the screen's own surfaces: wallpaper, bars, menu, toasts;
             keys, arranging, the file dialog, the permissions dialog
styles/  palettes/  wallpapers/  apps/   one definition a file
```

## The boot chain

`main.ss` boots core0, core0 boots core1, and core1 boots the world. Each
link makes the next one's environment, gives it what its `export.ss`
lists, loads it, and calls its boot; nothing reaches back up, and nothing
else of a layer's is there to name. Each name goes down read-only unless
its entry says `settable`: those are the hooks the folders fill
(`*profile-span*`, `*theme-saver*`, `*window-gone*`, `*app-loader*`), so
the core never names a later layer.

Core0 is the bottom: SDL, the GPU's device side, the window and its
events, and the only code that names SDL. It makes "/recorder" and
"/core1", loads the core into "/core1", and boots core1 there, on a thread
of its own, the world's, while core0 runs its loop on the process's first
thread. Headless, one thread plays both. Core1 makes "/", gives it what
its `export.ss` lists, core0's and the recorder's that the world uses
among it, and loads a copy of `src/base.ss` and the folders, each in
file-name order:

```scheme
(map env-path (env-children (env-root)))   ; "/core0", "/recorder", "/core1", ...
(length (source-files))                    ; every file the world loaded
```

Only the core calls C. No binding reaches "/", and `tests/sources.ss`
checks that no folder names one, nor anything of the core's it isn't given.

## Reloading

`(reload!)` loads the core's files again into "/core1", gives "/" what the
core exports anew, and loads the world's. It runs as a process, and while
it loads nothing else runs half-loaded code: no frames, timers, ticks or
other processes, and input waits to be handled in order when it's done.
Ctrl+C stops it, and a toast names the file it was loading if it's
stopped or fails. State that must survive it is a `defvar`, and record
types are nongenerative.

The core's own names are redefined in a REPL in "/core1", where a
`define` takes at the core's next call. Core0's change with a restart, or
in a REPL in "/core0", whose forms core0 runs between frames on its own
thread:

```scheme
(repl "/core1")
```

## Surfaces and strips

The core names nothing of the desktop's. It keeps two registries: the
screen's surfaces, drawn and given input in depth order (the wallpaper
under the windows; the taskbar, top bar, menu and toasts over them), and
the strips they reserve at the screen's edges, which `desktop-rect`, where
windows go, leaves out:

```scheme
(define-surface dock 15                    ; over the taskbar
  'draw (lambda () (fill-box 0 0 64 (screen-h) 'panel))
  'box (lambda () (values 0 0 64 (screen-h)))   ; what a frame redraws
  'at (lambda (x y) (and (< x 64) 'dock))       ; takes the points there
  'mouse (lambda (kind what x y button clicks) (notify "dock")))
(define-strip dock 'left (lambda () 64))   ; maximized windows beside it
(memq 'dock (surfaces))
```

A field may name a procedure instead (`'draw 'draw-taskbar`), looked up at
each call, so redefining it shows on the next frame. The crash panel and
the window menu are parts whose built-ins the desktop gives.

## Engines

Each window's handler runs in a Chez engine with a fuel budget
(`safe-call`): an error or a loop that runs away crashes only that window,
which shows the condition and can be retried, or fixed live with
`window-on!`. A process is an engine that gets slices between frames. The
system's own code runs under `safely`: errors are caught and reported, with
no fuel limit.

## Frames

The screen is a tree of lists of records. A list is flat records of 32
bytes, whole numbers, that the drawing procedures write; `with-clip`,
`with-translation`, `with-scale`, `with-turn` and `with-label` are forms,
with no closure a call. One shader on the GPU reads them, in one instanced
draw for a run of records that are alike, in variants: a run of boxes and
text in solid colors draws with none of the code for lines, shadows,
gradients, stipples or images. Glyphs come from an atlas on the GPU.

A list can show another, `(show-list lst x y)`, inside the clip around
it: what was recorded into it keeps its own coordinates and its own
buffers on the GPU, so moving it changes one run and records nothing
again. A window is a list from its corner, what `draw-window` draws, and
its content a list of its own shown in it. A frame records the wallpaper,
the panels, the menu and the toasts, shows each window's list from the
bottom up, each clipped to its extent (`record-world!` in
`src/core1/wm.ss`), and sends them; a list that changed goes up to the
GPU, and the others are there.

A window draws again only when it opens or resizes, when what its frame is
drawn with changes (its focus, the part under the mouse, its title, its
state), after input to it, and when asked, `(invalidate! win)`;
`(invalidate!)` asks every window. Moved or raised, it isn't drawn again,
and a window whose app is slow keeps showing what it drew. A step nothing
asked a frame of draws nothing. Nothing is assumed about what a drawing
procedure does, so redefining `draw-window` or a style's part changes the
next frame it's drawn in: a REPL's evaluation asks every window when it
ends.

Recording and the world's state stay on core1. A process may be switched
out at any call while frames go on, so `(render-frame!)` from a REPL only
asks for a frame.

## The pacer

A tick is a frame turn: the windows that asked for their `'frame` get it,
then each surface its own, then a frame is drawn if something asked for
one. Ticks run only while one is wanted, on a grid a period apart: a
refresh of the screen's by default.

```scheme
(pacer-period)                             ; ns
(pacer-ticks)                              ; how many so far
(pacer-busy-ms)                            ; the last tick's work, waits left out
(pacer-rate! 30)                           ; 30 a second from now on
(pacer-rate! 'screen)                      ; the screen's again
(inspect-pacer)
```

Past a period of work the world slows down: the next tick comes right
after, none skipped. Processes run in the time left before the next
tick's frame, at least 1 ms a step.

With a window, the screen sets the pace. Core0 presents frames on its own
thread, holding at most the one it presents and one more, and no tick runs
while the last frame published waits for core0 to take it, which it does
as the screen frees an image. After a tick whose frame the screen holds,
the next may come as soon as half a period later, once core0 has taken
that frame, so each refresh gets a new frame, never one drawn on a clock
that drifts against the screen's. A window's `'frame` is told `t`, when
its frame should show: a refresh after the last one's, a few after the
tick, so what moves by `t` moves as evenly as the screen shows frames.
While the window is hidden or covered no frame is drawn; input, timers and
processes go on.

Where the screen reports when the compositor latches a frame (Wayland's,
the Mac's), a tick begins just in time instead, aimed at a latch, and at a
later one than the tick before it, so the screen's queue never grows. It
begins its lead before that latch: what frames took lately from their tick
to core0's sending them, and a margin. A frame that showed late though
sent about the margin before its latch grows the margin by a step; one
late though sent well before it was the compositor's, and teaches nothing,
unless lateness keeps coming in a chain. On a Mac the margin fades over a
minute. The choices are settings, read live: `pacer-margin-start`,
`pacer-margin-step`, `pacer-miss-own`, `pacer-lead-fade`,
`pacer-margin-fade` and `frames-in-flight`. The Pacer Lab,
`(pacer-lab)`, tries their values on Schevana itself while it's used,
ten minutes each, and keeps how many frames came late with each, in
`~/.schevana.d/pacer-lab.ss`.

How a frame reaches the screen is `present-mode`, in Settings' Display tab
or `(override! 'present-mode 'mailbox)`, among what the window offers
(`(inspect-device)`). With `vsync`, the default, the screen holds core0
for each image, and that hold paces the frames. With `mailbox` core0
seldom waits, and a newer frame replaces one not shown yet.

## What the screen reports

On Wayland core0 asks the compositor to report on each frame it presents
(`wp_presentation`): the vblank it showed at, the refresh and the
display's sequence, or that it was dropped. On a Mac, Metal tells a
drawable's presented handlers when it was shown, and core0 counts the
sequence from the times. X11 and headless runs report nothing yet. The
world reads the reports by frame number, `(inspect-frame-screen n)` and
`(inspect-frame-latency n)`, and joins them to the input each frame shows.
So a refresh frozen where an update was due is counted from the screen's
own sequence, not guessed from waits, and Monitor and the Pipeline say how
long input takes to reach the screen: at the median and the 99th, from the
compositor's own time where it gives one, else SDL's stamp, else when
core0 first saw it.

Which OS, windowing system and GPU API this is comes from predicates
(`platform-mac?`, `platform-wayland?`, `platform-vulkan?`) and facts core0
learns as SDL and the GPU start; what has run where is in
[PLATFORMS.md](PLATFORMS.md).

## Traces

In a checkout with a `.work` folder, core0 and core1 stamp their steps
around each frame (take, acquire, submit, tick, draw, publish, collect) on
rings of their own, with each event pump that held core0 past 2 ms and
each collection. Closing the window, Ctrl-C in the terminal, core1 going
5 s without a step, or `(core0-trace-dump!)` writes the last two minutes
or so, with the screen's reports, to `.work/traces/trace-<date>-<time>.txt`,
saying why it was written.

## The GPU

The GPU layer speaks the world's terms: nothing above core0 names SDL's
GPU, Vulkan, SPIR-V or Metal, but the shader compiler, which writes the
back ends' code ([SHADERS.md](SHADERS.md)). A compute run asked for with
`gpu-compute-soon!` goes with the next frame, ahead of its drawing, so a
paint shows what it wrote; `(inspect-computes)` lists the runs waiting. A
shader touches only the buffers it's handed: a read outside one reads its
last word and a write outside is left out, on every device. Core0 checks
every write against the sizes it made a buffer or image with.

Nothing on the GPU has to be let go of. A buffer, an image or a list that
nothing holds is released once a collection finds it, by a guardian swept
at each step's end, and what uses one keeps it. The collector can't see
GPU memory, so the bytes made count toward its old generations' growth.
`gpu-buffer-release!` frees at once, and stays optional:

```scheme
(define b (make-gpu-buffer 1024))
(gpu-buffer-release! b)
(inspect-gpu-held)                         ; the bytes made, and let go of
```

## The profiler's hook

`src/core1/proc.ss` keeps one hook, `*profile-span*` (`#f`, or a pair of
procedures, begin and end), and `with-profile-span`, in which five places
run their work: the step, `safely` (each phase of core1's loop, each
surface's draw and tick), a window's handler, its drawing, and a
process's turn. Off, each costs a variable read and a branch. On,
`services/profile.ss` times each on the monotonic clock in fixnum ns, on a
stack of fixed depth, giving each its self time, so the parts add up to
the tick; a span allocates nothing. A span inside an engine runs untimed,
since an engine can be suspended halfway, and so does one on another
thread. While it's on, the collector's work is a span of its own, `gc`.
The data it keeps is in [MONITORING.md](MONITORING.md).

## Measured

On 48 hardware threads, the crew ([THREADS.md](THREADS.md)):

| | One thread | Crew of 8 | All 48 |
|---|---|---|---|
| Life, a generation, 1 px a cell, maximized on a 4K screen (7.4 M cells) | 69 ms | 9.6 ms | 4.2 ms |
| Boids, a step, 450 boids | 0.60 ms | 0.22 ms | |
| Boids, a step, 2,000 boids | 11.7 ms | 1.6 ms | |
| Boids, a step, 5,000 boids | 72 ms | 9.3 ms | |

The crew gains less per thread as it grows: a generation on 16 threads is
12 times as fast as on one, on 48 17 times. Boids 3D, all shaders, at
2560 × 1600 with a step every frame: the GPU's frame grows from 0.82 ms to
2.01 ms with 1,000 birds and to 5.18 ms with 4,096; core1 spends about
0.1 ms.
