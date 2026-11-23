# Internals

How Schevana is put together, for those who change its core. The rules
that every change follows are in [AGENTS.md](../AGENTS.md); this page
says how the pieces work.

## The tree

```
desktop        the desktop's launcher; the demos' launchers are beside it
src/launch.ss  what a launcher loads: it sets up the tree's libraries
               (compiled into .cache/, or spliced by src/hacker.ss), then
               calls its library's main
src/base.ss    what every environment of the top level has, each its own
               copy: pure, with no state and no C; forwarders, by which
               an environment gives another its names
src/hacker.ss  the hacker edition: every library spliced into the top
               level
src/strip.ss   a library's own forms in their top-level sense, for the
               hacker edition and the tests
src/build.ss   a library's main built as a program of its own, in out/lib
schevana/      the libraries below the world, each declaring its layer:
  base         the basics; the layers and their check; states, made
               values, hooks and views
  tree         where the tree is
  ffi  sdl  freetype  fontconfig  socket
               bindings to C
  shader       the shader language's compiler, to SPIR-V or to Metal's
               language
  reload       reloading a library in place
  core0/       core0, below the core: the window and its events, the
               GPU's device side, the trace; its facade is core0.sls
  recorder/    the bytes of frames and their writers; its facade is
               recorder.sls
  core/        the core, the world's runtime; its facade, core.sls, is
               what the world is given:
    platform     the core's part of what differs by platform; the clocks
    theme-table  the settings in effect, which drawing reads
    processes    processes and the watchdog (Chez engines); notify,
                 report-error!; the profiler's hook; worklets
    gpu          the GPU layer in the world's terms: images, buffers,
                 lists, compute runs
    fonts        fonts found by fontconfig, glyphs drawn by FreeType, the
                 atlas, measuring text
    draw         the drawing procedures, colors, stipples, gradients,
                 clips, images and paints, all written as records
    pacer        when frames are due, and what became of each
    screen       core0's window as the world sees it: scale, full screen,
                 icon, and its events as Scheme lists
    loop         core1's loop and step, the boot, the collector
    theme        settings in layers, rules, parts; the registries of the
                 looks: styles, palettes, wallpapers
    windows      windows, z-order, focus, hit testing, dragging,
                 dispatch; the registries of surfaces and strips
    sources      "/", the world's libraries and files, loading them, and
                 reload!
  kits/        libraries that are pure, or almost: ui, edit, text, color,
               px, menu, ...
  services/    long-lived state behind procedures: crew, env, pacer-lab,
               profile, theme-file, vat
  styles/  palettes/  wallpapers/    the looks, one definition per library;
               a look's parts, in the folder of its name (styles/adwaita/,
               styles/cons/, styles/genera/, styles/open-look/)
  desktop/     the screen's own surfaces: wallpaper, bars, menu, toasts;
               keys, arranging windows, the file dialog; the desktop's
               start (main, start)
  apps/        the desktop's own apps: the REPL, Settings, Tasks, Clock, ...
demo/          the demos, one library each: Boids, Life, Springies, Rings,
               ...; some have launchers at the root
games/         the games, one library each: Fireflies, Prism Relay (its
               parts in games/prism-relay/); a REPL loads one by its
               name, (import (games fireflies)), and each has a launcher
               at the root
```

## The boot chain

A launcher at the tree's root (`desktop`) loads `src/launch.ss`. That
file sets up the search for the tree's libraries (each is compiled once
into `.cache/`, which has a folder for each Chez version and machine)
and calls the main of the launcher's library, `(schevana desktop main)`.
Core0 boots first, then core1 starts on the world's thread
(`core1-run`), loads the world (`core1-boot!`) and starts it
(`desktop-start!`, in `schevana/desktop/start.sls`).

Core0, the recorder and the core are each sealed in their libraries, and
each layer has only what the facade of the layer below gives it: the core
imports `(schevana core0)` and `(schevana recorder)`, and the world
imports `(schevana core)`. A state or a hook that the layer below sets
comes as a read-only view, so that one thread never sets another's. No
layer reaches back up, and nothing else of a layer is there to name: each
library declares its layer (`library-layer`) and is held to the layers'
order as it compiles. Every name the core gives is read-only, except the
hooks that the later layers fill (`*profile-span*`, `theme-save!`,
`window-gone!`, `worklet-spread`, ...), so the core never names a later
layer.

Core0 is the bottom layer: SDL, the GPU's device side, the window and its
events, and the only code that names SDL. With a window, core0 opens the
window first and runs its loop on the process's first thread, and core1
boots on a thread of its own, the world's; the window shows with the
world's first frame. Headless, one thread plays both. Core1 makes "/",
which imports the core's facade (the facade passes on what the world uses
of core0 and the recorder). Then core1 loads a copy of `src/base.ss` into
"/" (in the hacker edition, "/" has it already) and the world's folders
in the layers' order, the looks before the desktop, each folder's files
in file-name order:

```scheme
(map env-path (env-children (env-root)))   ; "/worklets", ...
(length (source-files))                    ; the world's files, not libraries
```

The desktop's apps wait: they load after the screen shows, one at each
quiet step of the loop (a step that drew no frame and wants none), or one
a second while frames flow (`*world-later*`). The desktop loads the two
apps it opens first at once (`world-load-now!`). As it begins to compile
each library into its cache, a launcher prints its name, so a first boot
shows its progress.

Only the core calls C. No binding reaches "/", and `tests/sources.ss`
checks that no folder names one, nor anything of the core's that it isn't
given.

The hacker edition (`--hacker`) seals nothing. `src/hacker.ss` gives the
`library` form a top-level meaning, so that every library, Schevana's or
anyone's, is spliced from its source into one environment, "/", with its
internals. Every name is there to see and redefine, and the core's own
calls reach a redefinition at their next call. A state is a variable; a
view or a checked setter is the name itself; and a library imported
elsewhere has its names forwarded there. `(reload!)` splices again each
library whose file changed, and each library that imports it. The suites
run in both editions (`SCHEVANA_HACKER=1`, [TESTING.md](TESTING.md)); in
the hacker edition the units run only the topics that tell the editions
apart, and the demos'.

A program can stand on the core alone (`(demo rings)` and
`(games fireflies)`, each with a launcher at the root). It imports the
core's facade and runs with `schevana-main`, which boots the screen,
calls a thunk that opens what the program shows, and runs the world until
it quits. A program with no windows fills the hooks that the windows layer
would fill: what a frame draws (`record-world!`), where an event goes
(`wm-event!`) and what a tick does (`wm-tick!`), as `(demo rings)` does:

```scheme no-run
(import (chezscheme) (schevana core))
(schevana-main 'sdl 640 400 #f
  (lambda () (open-window "Hello" 'size '(300 . 200))))
```

## Reloading

`(reload!)` evaluates again each library whose file changed since it was
evaluated, and after it every library that imports it (Chez links a
library to the instance of each library it was evaluated against). It
imports them again wherever they were imported (in "/", that is the
core's facade), and then loads the world's files. A library's states stay
(`define-state`); its made values and hooks are made again, and whatever
sets a hook sets it again; a closure made before keeps the code it was
made with. Core0's libraries, and all that they import, stay as they were
booted: core0's thread runs them, and they change only with a restart.

A reload runs as a process. While it loads, nothing else runs half-loaded
code: no frames, timers, ticks or other processes, and input waits, to be
handled in order once the reload is done. Ctrl+C stops it, and if it is
stopped or fails, a toast names the file it was loading. State that must
survive a reload is a `define-state` in a library and a `defvar` in a
file, and record types are nongenerative.

The core's own code changes with its library's file: edit the file and
call `(reload!)`. A `define` in "/" of a name that the core gives makes a
name of the world's own, which the core never calls; what the core calls
through a hook is set from "/" (`set-hook!`).

## Surfaces and strips

The core names nothing of the desktop's. It keeps two registries: the
screen's surfaces, drawn and given input in depth order (the wallpaper
under the windows; the taskbar, top bar, menu and toasts over them), and
the strips that surfaces reserve at the screen's edges, which
`desktop-rect`, the area where windows go, leaves out:

```scheme
(define-surface dock 15                    ; over the taskbar
  'draw (lambda () (fill-box 0 0 64 (screen-h) 'panel))
  'box (lambda () (values 0 0 64 (screen-h)))   ; what a frame redraws
  'at (lambda (x y) (and (< x 64) 'dock))       ; takes the points there
  'mouse (lambda (kind what x y button clicks) (notify "dock")))
(define-strip dock 'left (lambda () 64))   ; maximized windows beside it
(memq 'dock (surfaces))
```

A field may name a procedure instead (`'draw 'taskbar-draw`), which is
looked up at each call, so a redefinition shows on the next frame. The
desktop's own surfaces draw through parts that a style gives
(`draw-taskbar`, `draw-menu`, ...), which are also called by name and are
handed what they draw: a look loads before the desktop and reads nothing
of it. The crash panel and the window menu are parts whose built-in
versions the desktop gives.

## Engines

Each window's handler runs in a Chez engine with a fuel budget
(`safe-call`): an error, or a loop that runs away, crashes only that
window, which shows the condition and can be retried, or fixed live with
`window-on!`. A process is an engine that gets slices of time between
frames. The system's own code runs under `safely`: its errors are caught
and reported, and it has no fuel limit.

## Frames

The screen is a tree of lists of records. A list is a flat run of 32-byte
records of whole numbers, written by the drawing procedures;
`with-clip`, `with-translation`, `with-scale`, `with-turn` and
`with-label` are forms, which allocate no closure for a call. One shader
on the GPU reads the records, in one instanced draw for each run of
records that are alike, and in variants: a run of boxes and text in solid
colors draws with none of the code for lines, shadows, gradients,
stipples or images. Glyphs come from an atlas on the GPU.

A list can show another, `(show-list lst x y)`, inside the clip around
it. What was recorded into the shown list keeps its own coordinates and
its own buffers on the GPU, so moving it changes one run and records
nothing again. A window is a list drawn from its corner, what
`draw-window` draws, and the window's content is a list of its own shown
in it. A frame (`record-world!` in `schevana/core/windows.sls`) records
the surfaces under the windows (the wallpaper), shows each window's list
from the bottom up, each clipped to its extent, then records the surfaces
over the windows (the bars, the menu, the toasts), and sends the result.
A list that changed goes up to the GPU; the others are there already.

A window draws again only when it opens or resizes, when something its
frame is drawn with changes (its focus, the part under the mouse, its
title, its state), after input to it, and when asked to,
`(invalidate! win)`; `(invalidate!)` asks every window. A window that is
moved or raised isn't drawn again, and a window whose app is slow keeps
showing what it drew last. A step in which nothing asked for a frame draws
nothing. Nothing is assumed about what a drawing procedure does, so
redefining `draw-window` or a style's part changes the next frame the
window is drawn in; a REPL's evaluation asks every window to draw again
when it ends.

Recording and the world's state stay on core1. A process may be switched
out at any call while frames go on, so `render-frame!`, called from a
process (a REPL's input, say), only asks for a frame.

## The pacer

A tick is one turn of frames: each window that asked for its `'frame`
gets it, then each surface gets its own, and then a frame is drawn if
something asked for one. Ticks run only while one is wanted, on a grid
one period apart; by default the period is one refresh of the screen.

```scheme
(pacer-period)                             ; ns
(pacer-ticks)                              ; how many so far
(pacer-busy-ms)                            ; the last tick's work, waits left out
(pacer-rate! 30)                           ; 30 ticks a second from now on
(pacer-rate! 'screen)                      ; the screen's rate again
(inspect-pacer)
```

When the work takes longer than a period, the world slows down: the next
tick comes right after, and none is skipped. Processes run in the time
left before the next tick, less what the last frame took to draw, and at
least 1 ms a step.

With a window, the screen sets the pace. Core0 presents frames on its own
thread and holds at most two: the one it presents and one more. No tick
runs while the last frame published waits for core0 to take it, which
core0 does as the screen frees an image. Between frames, core0 looks
every quarter ms while it awaits a frame's GPU work or the screen's
report on it; otherwise it waits in SDL's own wait for events, which
input ends at once, and which a frame or a job ends by an event that
core0 pushes (`core0-wake!`). After a tick whose frame the screen held,
the next tick may come as soon as half a period later, once core0 has
taken that frame. So each refresh gets a new frame, and never one drawn
on a clock that drifts against the screen's. A window's `'frame` handler
is told `t`, the time its frame should show: a refresh after the last
frame's, and a few refreshes after the tick, so that what moves by `t`
moves as evenly as the screen shows frames. While the window is hidden
or covered no frame is drawn; input, timers and processes go on.

Where the screen reports when the compositor latches a frame (on Wayland
and on the Mac), a tick instead begins just in time, aimed at a latch,
and at a later latch than the tick before it aimed at, so the screen's
queue never grows. The tick begins a lead before that latch. The lead is
what frames took lately from their tick to core0's sending them, leaving
out the screen's time (an acquire the screen held, or a submit that took
longer than a look, and the wait for core0 that the frame before held),
plus a margin. When a frame shows late
though it was sent about the margin before its latch, the margin grows by
a step. When a frame shows late though it was sent well before its latch,
the compositor missed the refresh, and the pacer learns nothing from it,
unless late frames keep coming in a chain. A margin that reaches a whole
refresh becomes the compositor's depth instead: one more refresh that the
compositor keeps frames (WindowServer keeps two). What the pacer learned
from frames whose GPU work was still going a refresh and an eighth after
they were sent is put down to the GPU: a GPU slow to wake as an app
opens (it finishes a frame every other refresh for a quarter of a second,
which taught three refreshes of depth), or an app too heavy for the GPU,
whose frames then queue so that the GPU is never idle. Once 240 frames
are judged with none that slow, the pacer forgets what it learned and
starts again. On a Mac the margin fades over a minute; elsewhere it stays.
These choices are settings, read live: `pacer-margin-start`,
`pacer-margin-step`, `pacer-miss-own`, `pacer-lead-fade`,
`pacer-margin-fade` and `frames-in-flight`. The Pacer Lab, `(pacer-lab)`,
tries values of them on Schevana itself while it is in use, ten minutes
each, and logs how many frames came late with each, in
`~/.schevana.d/pacer-lab.ss`.

How a frame reaches the screen is the `present-mode` setting, in
Settings' Display tab or `(override! 'present-mode 'mailbox)`, chosen
among the modes the window offers (`(inspect-device)`). With `vsync`, the
default, the screen holds core0 for each image, and that hold paces the
frames. With `mailbox`, core0 seldom waits, and a newer frame replaces
one that isn't shown yet.

### The second pacer

A second pacer, `(schevana core pacer2)`, can take the first one's place,
for comparing the two. The setting `pacer` says which one the loop asks:
1, the one above, by default, or 2. It is read live, and saved with the
look:

```scheme
(override! 'pacer 2)                       ; the second pacer from now on
(override! 'pacer)                         ; the first again
(inspect-pacer2)                           ; its state
(inspect-pacer-rows)                       ; the rows it reads
```

What a turn is, what asked for it, the rate, the turns so far, `t` and
the frame ring are the two pacers' alike. Each frame's row says which
pacer planned it, and neither learns from the other's rows: a switch
starts the second one over, as at a run's start. With the second pacer,
the world waits with no end while nothing is wanted, until input, mail
or a timer wakes it.

The second pacer reads only what every platform has. Each frame
published leaves a row: when its tick began and the begin it was
planned for, the refresh it aimed at, when it was published and when
core0 took it, how long the screen held core0 for it (an acquire it
held, or a submit that took longer than a look), when its GPU work was
first seen done, and what the screen reported. At each decision it
reads the last sixteen rows again. The grid is the newest refresh
reported, at the length that core0's clock gives it; with no report,
the pacer keeps a grid of its own, a 512th short of the display mode's
refresh, so that a screen a little faster than it says never holds it
back. The work is the largest of the last eight rows', from the tick's
begin to its GPU work seen done, less the screen's waits; the slack is
two of core0's looks plus the latest that any of those ticks began
after its plan. The margin is a 16th of the refresh: a compositor's
cutoff moves, and a frame done just over the hold still misses now and
then (on GNOME, one in a hundred at 60 Hz; with a ms more lead, misses
are as rare as the refreshes the compositor loses on its own).

No tick begins while the newest frame's GPU work isn't seen done, for
eight refreshes at most: core0 wakes the world when it sees the work
done, and not as it takes a frame (each frame says which wakes core1
asks for). Each frame on its way takes the first refresh a hold, less
the slack, after its GPU work is done, one after the frame before it;
the next tick aims at the refresh after that, and begins the hold, the
margin, the work and the slack before it. With VSync the screen takes
frames in order, so a frame on its way that it has said nothing of a
refresh and a half after its aim (no report, not even one that core0
holds back for saying a refresh was missed) showed at neither refresh,
and the frames behind it wait too. While a compositor takes nothing,
the next tick is put off a refresh at a time, eight past the frame's
aim at most, and its frame is drawn for the refresh it can make once
the compositor takes frames again, not for one long gone (GNOME stalls
40 to 60 ms now and then, and holds back its word on the refresh before:
of the frames queued then, only those already sent show late). A frame
that missed one refresh shows at the next, its report in by then, and
the frames behind it stay a refresh deep for a few ticks: a refresh to
spare while the compositor's cutoff moves. A window's `'frame` handler
is told `t`, the refresh the tick aims at, which is when its frame will
show. Past a refresh of work, the next tick begins as soon as the GPU
work is done, aimed at the refresh it can still make; none is skipped.
Processes run until the next tick's planned begin, and at least 1 ms a
step.

The hold, how long before a refresh a frame's GPU work must be seen
done, is the one thing the second pacer learns, from the screen's
reports. The first frame shown gives it; a frame shown in time with less
lead lowers it, never under the floor that a descent leaves. A frame
that missed its refresh although it began on plan, its GPU work was done
the hold before the refresh, and the frame before it was shown, is a
clean miss. One alone is the compositor's. Two within the sixteen rows
raise the hold a look over the lead that failed, never past the margin
over the hold the frame was planned with (more lead than that failed by
no cutoff: the compositor held a refresh, or the GPU was slow). Another
before any frame is in time raises it a refresh, which owes a descent.
Every three minutes, once eight frames in a row were in time and on
plan, a descent tries the hold lower: one probe frame at a time, a look
under what it has proven, with the frames around it at that. A probe in
time proves a look lower, and the next frame probes. A probe's first
clean miss counts as a miss alone, and the next frame probes the same
hold; the second ends the descent, with the hold two looks over the
larger lead of the two that failed, never over where the descent began,
and the floor a look over that lead. A refresh of another length starts
all of it over. Each verdict goes into the trace with its frame. With no
reports nothing is learned, and an acquire that the screen held leaves a
refresh out of the pacer's own grid where three frames are in flight.

## What the screen reports

On Wayland, core0 asks the compositor to report on each frame it presents
(`wp_presentation`): when the frame showed and how long a refresh is, or
that the frame was dropped. On a Mac, Metal calls a drawable's presented
handlers with the time it was shown. X11 and headless runs report nothing
yet; a headless frame's GPU work is taken as done as core0 gives the
frame back.

A compositor says which of the system's clocks its times are on, and it
may be wrong: GNOME over NVIDIA's driver says the monotonic clock but
stamps on the raw one, which runs behind the monotonic clock on one
machine and ahead of it on another. A frame shows after it is sent, and
its report comes after it showed, or at most a refresh before, where a
compositor predicts the time. When a time breaks that rule on the clock
the compositor named, core0 reads it, and the times after it, on the
first of the system's clocks on which the rule holds.

A report's time is a stamp, and core0 doesn't take a stamp at its word. A
screen that refreshes steadily is a clock, and a stamp is a late reading
of that clock: not late at all where the display stamps its own refresh,
and late by a kernel thread's turn where a driver stamps the flip's event
as it sends it, as NVIDIA's driver does with no vblank support. So core0
infers the clock from the stamps alone. A refresh comes one period after
the one before. An earlier stamp moves the clock at once; a later one
moves it only as far as the clock may have drifted, and eight later ones
in a row move it by the least of their delays, which is how the clock
learns a screen in a few frames at the start, or after the screen
changes. That holds while frames flow, each sent within a refresh and a
half of the one before. A display may stop its timing when nothing new
comes, and start it again with the next frame, off the old beat: a
laptop's panel does so some ten refreshes after the last frame. So after
a pause the clock is set to the stamp as it is. A stamp taken that way
may have run late; then the next frame's stamp reads as the same refresh,
which no stamp can be, since none comes before its refresh, and the clock
takes the newer stamp instead.

Each report then gives the number of the refresh its frame showed at, and
when that refresh came by the clock; the stamp is kept beside it. A stamp
can run a whole refresh late, which only the next frame's report can
tell, since a frame shows after the one before it. So a report that says
a refresh was missed in a flow of frames is held until the next report
agrees, or until three refreshes pass, and its stamp doesn't move the
clock at all: a stamp that ran more than three quarters of a refresh late
reads as a refresh later, and taken, it would leave the clock early for
the frames after it. Once shown, a held frame keeps the earlier of its
stamp and the clock's time for it. Where the screen says it keeps no
steady refresh (a variable refresh rate; a Mac, which reports none), each
stamp is taken as it is.

Core0 doesn't read the display's own count of its refreshes (the
protocol's sequence number). The protocol lets it be 0, and KWin's always
is; where the driver has no count to give, Mutter counts frames instead
of refreshes, and steps by one when a window moves to another screen.

The world reads the reports by frame number (`(inspect-frame-screen n)`
and `(inspect-frame-latency n)`) and joins them to the input that each
frame shows. So a refresh that froze where an update was due is counted
from the screen's own times, not guessed from waits, and Monitor and the
Pipeline show how long input takes to reach the screen, at the median and
at the 99th percentile. The input's time is the compositor's own where it
gives one, else SDL's stamp, else when core0 first saw the input. The
pacer reads the same reports, so a stamp that ran late doesn't make its
frame count as late.

The Pipeline's Latency view shows the clock's drift under the River, each
refresh under its column: how far the clock moved at that refresh
(`inspect-clock-moves`). Below 0, a stamp came earlier than the clock
expected; above 0, the clock gave way to late stamps.

The length of a refresh is the display mode's. The screen's own word on
it, where it gives one, is the same rate, and isn't read: not every
platform gives one (Metal doesn't), so the screen's word says only
whether its refresh is steady. The mode's rate can be a little off the
display's real rate. To try another length, give it at a REPL, in
nanoseconds:

```scheme
(core0-refresh-ns! 16667505)   ; => #t, taken from the next report on
(core0-refresh-ns! 0)          ; the display mode's length again
(cdr (assq 'refresh-said (inspect-core0)))   ; the length given now
```

A length from 1 to 100 ms (1,000,000 to 100,000,000 ns), or 0, is
accepted; anything else is refused with `#f` and changes nothing. The
length replaces the mode's; a screen that says it keeps no steady refresh
still has none. It isn't saved, and lasts until it is set to 0 or
Schevana quits. A length that suits the display shows as a
drift that stays at 0 between the clock's real moves.

Which OS, windowing system and GPU API this is comes from predicates
(`platform-mac?`, `platform-wayland?`, `platform-vulkan?`) and from facts
that core0 learns as SDL and the GPU start; what has run where is in
[PLATFORMS.md](PLATFORMS.md).

## Traces

In a checkout with a `.work` folder, and with a window, core0 and core1
record their steps around each frame (take, acquire, submit, tick, draw,
publish, collect) in rings of their own, with each event pump that held
core0 for more than 2 ms, each collection and each change of present
mode. The last two minutes or so of them, with the screen's reports, are
written to `.work/traces/trace-<date>-<time>.txt` when the window closes,
on Ctrl-C in the terminal, when core1 goes 5 s without a step (but not
while it waits), or on `(core0-trace-dump!)`. The file's head says why it
was written, how the window presents, how often core0 looks, and when
the first step came on the clock. With the second pacer, each tick's
planned begin, aim, `t` and hold, and each frame's verdict, are in it
too.

## The GPU

The GPU layer speaks the world's terms: above core0, nothing names SDL's
GPU, Vulkan, SPIR-V or Metal except the shader compiler, which writes the
back ends' code ([SHADERS.md](SHADERS.md)). A compute run asked for with
`gpu-compute-soon!` goes with the next frame, ahead of the frame's
drawing, so a paint shows what the run wrote; `(inspect-computes)` lists
the runs waiting. A shader touches only the buffers it is handed: on every
device, a read outside a buffer reads its last word, and a write outside
it is left out. Core0 checks every write from the world against the sizes
it made the buffer or image with.

Nothing on the GPU has to be freed. A buffer, an image or a list that
nothing holds is released once a collection finds it, by a guardian swept
at the end of each step, and whatever uses one keeps it alive. The
collector can't see GPU memory, so the bytes made count toward the growth
of its old generations. `gpu-buffer-release!` frees a buffer at once, and
is optional:

```scheme
(define b (make-gpu-buffer 1024))
(gpu-buffer-release! b)
(inspect-gpu-held)                         ; the bytes made, and how many let go
```

## The profiler's hook

`schevana/core/processes.sls` keeps one hook, `*profile-span*` (`#f`, or
a pair of procedures, begin and end), and the form `with-profile-span`,
in which six places run their work: the step, `safely` (each phase of
core1's loop, each surface's draw and tick), a window's handler, its
drawing, a process's turn, and core1's wait for the screen. While the
hook is off, each place costs a variable read and a branch. While it is
on, `schevana/services/profile.sls` times each span on the monotonic
clock in fixnum ns, on a stack of fixed depth, and gives each span its
self time, so that the parts add up to the tick; a span allocates
nothing. A span inside an engine runs untimed, since an engine can be
suspended halfway, and so does a span on another thread. While the
profiler is on, the collector's work is a span of its own, `gc`. The data
it keeps is described in [MONITORING.md](MONITORING.md).

## Measured

On 48 hardware threads, with the crew ([THREADS.md](THREADS.md)):

| | One thread | Crew of 8 | All 48 |
|---|---|---|---|
| Life, a generation, 1 px a cell, maximized on a 4K screen (7.4 M cells) | 69 ms | 9.6 ms | 4.2 ms |
| Boids, a step, 450 boids | 0.60 ms | 0.22 ms | |
| Boids, a step, 2,000 boids | 11.7 ms | 1.6 ms | |
| Boids, a step, 5,000 boids | 72 ms | 9.3 ms | |

The crew gains less per thread as it grows: a generation on 16 threads is
12 times as fast as on one, and on 48 threads 17 times. Boids 3D, all
shaders, at 2560 × 1600 with a step every frame: the GPU's time for a
frame grows from 0.82 ms to 2.01 ms with 1,000 birds, and to 5.18 ms with
4,096; core1 spends about 0.1 ms.
