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
one. Ticks run only while one is wanted; with none wanted the world waits
with no end, till input, mail or a timer wakes it.

```scheme
(pacer-period)                             ; ns
(pacer-ticks)                              ; how many so far
(pacer-busy-ms)                            ; the last tick's work, waits left out
(pacer-rate! 30)                           ; 30 a second from now on
(pacer-rate! 'screen)                      ; the screen's again
(inspect-pacer)
(inspect-pacer-rows)
```

The pacer (`src/core1/pacer.ss`) reads what every platform has. Each frame
published leaves a row: when its tick began and the begin it was planned
for, the refresh it aimed at, when it was published and core0 took it, how
long the screen held core0 for it (an acquire it held, or a submit that
took over a look), when its GPU work was first seen done, and what the
screen reported (`inspect-pacer-rows` shows the rows as the pacer reads
them). At each decision it reads the last sixteen again. The grid is the
newest refresh reported, at the length core0's clock gives it; with no
report, its own grid, a 512th short of the display mode's refresh, so it
is never held back by a screen a little faster than it says. The work is
the largest of the last eight rows', begin to GPU-done less the screen's
waits; the slack two of core0's looks and the latest any of those ticks
began after its plan. The margin is a 16th of the refresh: a compositor's
cutoff moves, and a frame done just over the hold still misses now and
then (on GNOME, one in a hundred at 60 Hz; a ms more lead and they are as
rare as the refreshes it loses on its own).

No tick begins while the newest frame's GPU work isn't seen done, eight
refreshes at most: core0 wakes the world when it sees it done. Each frame
on its way takes the first refresh a hold less the slack after its GPU
work, one after the frame before it; the next tick aims at the refresh
after that, and begins the hold, the margin, the work and the slack before
it. A window's `'frame` is told `t`, the refresh it aims at: when its frame
will show. Past a refresh of work the next tick begins as soon as the GPU
work is done, aimed at the refresh it can still make; none is skipped.
Processes run till the next tick's planned begin, at least 1 ms a step.

The hold, how long before a refresh a frame's GPU work must be seen done,
is the one thing learned, from the screen's reports. The first frame shown
gives it; one shown in time with less lead lowers it, never under the floor
a descent leaves. A frame that missed its refresh though begun on plan, its
GPU work done the hold before it, and its predecessor shown, is a clean
miss: one alone is the compositor's, and two within the sixteen rows raise
the hold a look over the lead that failed, never past the margin over the
hold the frame was planned with (more lead than that failed by no cutoff:
the compositor held a refresh, or the GPU was slow); another before any
frame is in time, a refresh over, which owes a descent. Every three minutes, once eight
frames in a row were in time and on plan, a descent tries the hold lower,
one probe frame at a time a look under what it has proven, the frames
around it at that. A probe in time proves a look lower, and the next frame
probes. A probe's first clean miss is a miss alone, and the next frame
probes the same hold; the second ends the descent, the hold two looks over
the larger lead of the two that failed, never over where the descent
began, and the floor a look over that lead. A refresh of another length
starts all of it over. Each verdict is in the trace with its frame. With no
reports, nothing is learned, and an acquire the screen held leaves a
refresh out of its own grid, where three frames are in flight.

How a frame reaches the screen is `present-mode`, in Settings' Display tab
or `(override! 'present-mode 'mailbox)`, among what the window offers
(`(inspect-device)`). With `vsync`, the default, the screen holds core0
for each image, and that hold paces the frames. With `mailbox` core0
seldom waits, and a newer frame replaces one not shown yet.

## What the screen reports

On Wayland core0 asks the compositor to report on each frame it presents
(`wp_presentation`): when it showed and how long a refresh is, or that it
was dropped. On a Mac, Metal tells a drawable's presented handlers when it
was shown. X11 and headless runs report nothing yet; a headless frame's
GPU work is taken as done as core0 gives it back.

A compositor says which of the system's clocks its times are on, and may
be wrong: GNOME's over NVIDIA's driver says the monotonic clock and stamps
on the raw one, which runs behind it on one machine and ahead on another.
A frame shows after it's sent, and its report comes after it showed, or
at most a refresh before, where a compositor foretells the time. A time
that breaks that on the clock said is read on the first of the system's
clocks under which it holds, and so are the times after it.

A report's time is a stamp, and core0 doesn't take one at its word. A
screen that refreshes steadily is a clock, and a stamp is that clock read
late: by nothing where the display stamps its own refresh, by a kernel
thread's turn where a driver stamps the flip's event as it sends it, as
NVIDIA's does with no vblank support. So core0 infers the clock from the
stamps alone. A refresh comes its period after the one before; an earlier
stamp moves the clock at once, a later one only as far as the clock may
have drifted, and eight later in a row by the least of them, which is the
few frames it takes to learn a screen at the start, or a change of it.
That holds while frames flow, each sent within a refresh and a half of
the one before. A display may stop its timing when nothing new comes and
start it anew with the next frame, off the old beat: a laptop's panel
does, some ten refreshes after the last frame. So after a pause the
clock is the stamp, as it is. A stamp taken so may have run late; the
next frame's then reads as the same refresh's, which no stamp can be,
since none comes before its refresh, and the clock takes that one.
Each report then says the refresh its frame showed at, by number, and when
that refresh came by the clock; the stamp is kept beside it. A stamp can
run a whole refresh late, which only the next frame's report can tell,
since a frame shows after the one before it: so a report that says a
refresh was missed in a flow of frames is held till the next agrees, or
three refreshes pass, and its stamp moves the clock not at all: one that
ran more than three quarters of a refresh late reads as a refresh on, and
taken, would leave the clock early for the frames after it. Shown, a held
frame keeps the earlier of its stamp and the clock's time for it. Where
the screen says it keeps no steady refresh (a variable one; a Mac's,
which says none), each stamp is taken as it is.

The display's own count of its refreshes, the protocol's sequence, isn't
read. The protocol lets it be 0, and KWin's always is; Mutter's counts
frames, not refreshes, where the driver has no count to give, and steps by
one when a window changes screens.

The world reads the reports by frame number, `(inspect-frame-screen n)` and
`(inspect-frame-latency n)`, and joins them to the input each frame shows.
So a refresh frozen where an update was due is counted from the screen's
own times, not guessed from waits, and Monitor and the Pipeline say how
long input takes to reach the screen: at the median and the 99th, from the
compositor's own time where it gives one, else SDL's stamp, else when
core0 first saw it. The pacer reads the same reports, so a stamp that ran
late doesn't make its frame late.

The Pipeline's Latency shows the clock's drift under the River, a
refresh under its column: how far the clock moved at each one
(`inspect-clock-moves`). Under 0, a stamp came earlier than the clock had
it; over 0, the clock gave way to late stamps.

The refresh's length is the display mode's. The screen's own word on it,
where it gives one, is the same rate, and isn't read: not every platform
gives one, so the screen's word says only whether the refresh is steady.
The mode's rate can be a little off the display's real one. To try
another, say it at a REPL, in nanoseconds:

```scheme
(core0-refresh-ns! 16667505)   ; => #t, taken from the next report on
(core0-refresh-ns! 0)          ; the display mode's again
(cdr (assq 'refresh-said (inspect-core0)))   ; what is said now
```

A length is taken from 1 to 100 ms (1,000,000 to 100,000,000), or 0;
anything else is refused with `#f` and changes nothing. It stands in for
the mode's; a screen that says it keeps no steady refresh still keeps
none. It isn't saved: it lasts till it's set to 0 or
Schevana quits. A length that suits the display shows as a drift that
keeps to 0 between the clock's real moves.

Which OS, windowing system and GPU API this is comes from predicates
(`platform-mac?`, `platform-wayland?`, `platform-vulkan?`) and facts core0
learns as SDL and the GPU start; what has run where is in
[PLATFORMS.md](PLATFORMS.md).

## Traces

In a checkout with a `.work` folder, core0 and core1 stamp their steps
around each frame (take, acquire, submit, tick, draw, publish, collect) on
rings of their own, with each event pump that held core0 past 2 ms, each
collection and each change of present mode. A tick says the begin it was
planned for, its aim, its `t` and the pacer's hold; each frame the pacer
judges, its verdict (in time, late, a clean miss alone, a pair, a probe's
miss); a wait, how long, in µs. Closing the window, Ctrl-C in
the terminal, core1 going 5 s without a step but in its wait, or
`(core0-trace-dump!)` writes the last two minutes or so, with the screen's
reports, to `.work/traces/trace-<date>-<time>.txt`, saying why it was
written, how the window presents, how often core0 looks, and when the
first step came on the clock.

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
