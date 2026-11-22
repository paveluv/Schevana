# Tests

What the suites are, how to run them and how to write a check. What a
change must pass before it's committed is in [AGENTS.md](../AGENTS.md).
A test that passes here and fails on another machine, Chez or font is a
broken test, even when this machine is the one it was written on.

## The suites

From the tree's root:

```bash
mkdir -p out
scheme --script tests/smoke.ss out
scheme --script tests/units.ss out
scheme --script tests/frame.ss out
scheme --script tests/sources.ss
```

- **smoke** boots the world headless and uses it as a person would: it
  types into the REPL, drives every app by mouse and keys, presses every
  button of each style, crashes windows and reloads the sources. It
  writes screenshots to `out/`.
- **units** runs every file of `tests/units/`, a topic each (an app's, a
  kit's, a service's, a part of the core's), in a process of its own, so
  that none leans on what another left behind, many at once: as many as
  the machine allows, its CPUs less two and its free memory (within a
  container's limit too) less 1 GB, at what a topic takes at its peak
  (`test-jobs`, `tests/chez.ss`), or as many as `SCHEVANA_TEST_JOBS`
  says. Each docs page is a run of its own. Each writes in a folder of
  its own, `out/topic`, and says what it says there; the suite prints it
  in the topics' order. `scheme --script tests/units.ss out life boids`
  runs those two alone.
- **frame** draws frames on lavapipe, or on Metal on a Mac, with no window
  but one offscreen. It compares the screen bit for bit with the world
  drawn into an image, in every style and at several scales, and checks
  that every change shows on its frame and that nothing asked for draws
  no frame. It runs in parts at once, each a world of its own, as many as
  the machine allows: a part is some of its sections and, of those drawn
  at several scales, some scales (`frame-parts`); a section begins with
  `(frame-section 'name)`, and a loop over scales takes `frame-scales`.
- **sources** checks the sources themselves: 80 columns, names, the
  layers and what crosses them, the core's budget, who may name a color.
  It runs in seconds.

They run headless and never open a real window. They need `spirv-val`
(`sudo apt install spirv-tools`, `brew install spirv-tools`): the
shaders' topic writes every shader as SPIR-V, on a Mac too, and checks it,
since a module lavapipe takes may still be one another driver rejects. On
Linux they need lavapipe (`mesa-vulkan-drivers`). On a Mac type `chez` for
`scheme`; the tests run on Metal there, with no Dock icon and no window
shown. Homebrew's libraries are found where it keeps them (`(schevana
ffi)`), with no loader variable set.

## Running less while working

The whole suites take under a minute on a large machine, a few on a small
one; one check takes seconds. While a check is being written or fixed,
run what it needs, and the whole suites before the commit, under both
Chez versions before the push (`AGENTS.md`).

- `tests/sources.ss` alone takes seconds, and a units topic runs alone:
  `scheme --script tests/units.ss out tasks`.
- `SCHEVANA_CHECK=text` stops any suite after the first check whose name has the
  text in it (case aside). Everything before it runs as in a whole run, so
  the check sees what it would there. A run fails when no check's name has
  the text; in units, name the topic too.

```bash
SCHEVANA_CHECK="a card's tags" scheme --script tests/units.ss out tasks
SCHEVANA_CHECK="Shift+Tab up onto a title" scheme --script tests/smoke.ss out
```

- `SCHEVANA_HACKER=1` runs any suite in the hacker edition (`--hacker`):
  every library spliced into the world, from its source. A check that
  holds of one edition alone says so (`test-hacker?`). With no topic
  named, the units' runner runs there the topics that tell the editions
  apart (those that name `test-hacker?`) and the demos', whose launchers
  then run as the hacker edition's programs; a topic named runs there as
  asked.

```bash
SCHEVANA_HACKER=1 scheme --script tests/units.ss out
SCHEVANA_HACKER=1 scheme --script tests/units.ss out life
```

- A topic of one library by itself, which needs no world, says so first,
  `(test-focus (schevana kits complete))`: in the library edition it runs
  with that library alone from the cache and the checks
  (`tests/check.ss`), the world neither loaded nor booted.

## A check

A topic is a file in `tests/units/`, loaded into a world booted headless.
`tests/units.ss` gives it `check`, which runs an expression and reports
it, and helpers more than one topic uses: `(steps n)` runs `n` of the
world's steps, each a tick (see "How a test steps time" below),
`(raises? thunk)` says whether a call raises, and
`shown-picture`, `image` and `max-diff` compare what was drawn.

```scheme
(check "a window opens where it's asked"
       (let ([w (open-window "Here" 'pos '(40 . 60))])
         (steps 1)
         (let ([ok (and (= (window-x w) 40) (= (window-y w) 60))])
           (close-window! w)
           ok)))
```


- A change in behavior comes with a test of it.
- A unit check goes in its topic's file in `tests/units/` (an app's, a
  kit's, a service's, a part of the core's), which `tests/units.ss` runs in
  a process of its own: it leans on no other topic, and what several use is
  in `tests/units.ss`. `scheme --script tests/units.ss out life` runs one.
- A check's name says what is true when it passes, as a sentence.
- What can fail goes inside a check. A form outside one that raises fails
  the suite at its line, and the suite goes on, but what the form left
  undone fails the checks after it.

## Levels

Tests form a hierarchy: the basics are checked at the bottom, and each
level above tests only what it adds, trusting the levels below.

1. The sources (`tests/sources.ss`): the rules the code itself follows.
2. The core and the kits (units: `ui`, `edit`, `text`, `drawing`, …):
   measuring, wrapping, and each widget by itself, in a synthetic window
   of its own: its layout in the size it's given, its keys, its mouse.
3. An app's API (units: `add-task!`, `tasks-match?`, `tasks-layout`): its
   rules as procedures of what they're given. An app's tests don't test a
   widget: every widget is tested at level 2, so an app needs no test of
   its screen beyond that it opens.
4. The world driven by events (smoke): what only the whole world does, a
   window's life, focus between windows, a reload, the menus and bars of
   the desktop, each from a state the check sets up.
5. Frames (`tests/frame.ss`): that what changes shows, drawn as the world
   draws it.

- A check belongs to the lowest level that can see what it says. One that
  says again what a lower level says is dropped, or moved down to it.
- A sequence of checks starts from a state it sets itself (a window sized
  by the app's own measures, the selection it needs), not from what an
  earlier sequence left, so one failure doesn't take the rest with it.

## What a test asks of a library

Nothing. A library is written for what it does, never for its tests: no
export, hook, state or name of its own for them. What a test needs of
it, the test framework finds itself:

- The libraries the suites boot, in the library edition, as
  `tests/build.ss` builds them: each expanded as it compiles, into a
  cache of the build's own, and as a reload evaluates it again. A
  library of a sealed layer (core0's, the recorder's, the core's, and
  the foundation below them), but a facade, gives the tests every name
  it defines, which they have by the name itself (`*pacer-margin*`,
  `gpu-frame!`). A definition the tests stand in for, listed in
  `test-stand-ins`, is a hook there, so that a `fluid-let` or a `set!`
  of it reaches every call (`now-ms`, `bell`, SDL's calls); the
  definition itself is compiled as the library has it. A test that
  stands in for another adds it to the list. In the hacker edition
  every name is at the top level already, to set as any other.
- A demo, which the suites' world doesn't load: `(test-demos! 'life)`
  loads it into the world, as the desktop given the demos' folder does,
  for a test that opens its window.
- A library the world doesn't boot, a demo's own names: `(test-library
  '(schevana-demo boids) 'bo:)` (`tests/reach.ss`) strips the
  library, as the hacker edition
  strips every library, its body evaluated again at the top level of an
  environment of its own (in the hacker edition, as it is), and gives
  the test each name it defines under the prefix: `bo:boids-step`,
  `bo:boids-scatter`, `bo:boids`. The prefix keeps them apart from the
  world's.
- A stand-in for one of its procedures: a `fluid-let` of the prefixed
  name. Stripped, the library calls its own procedures through the top
  level, so it calls the stand-in.
- Its app: the stripped library registers it again, so the launcher, and
  the prefixed launcher (`bo:boids`), open the one the test reaches.

## What a test may touch

- Tests and scripts never touch the user's `~/.schevana-theme.ss`,
  `~/.schevana.ss` or `~/.schevana.d`. Point `*theme-file-path*` at a
  scratch file, as the suites do, or run with `HOME` set to a scratch
  folder.
- Nothing opens a real window: the suites run headless, on lavapipe, the
  Vulkan driver on the CPU (`mesa-vulkan-drivers`), or on Metal on a Mac.
- A file a test writes goes in the suite's output folder (`out/`), named
  relative to it, never at an absolute path or in `/tmp`.
- A run whose heap passes its limit stops, as a failure, before the
  machine runs out of memory (`tests/lib.ss`): 2 GB, where a topic or a
  suite takes a few hundred MB to 1.5 GB; `SCHEVANA_TEST_HEAP_MB` sets
  another. The collector looks at the older generations at most every
  500 ms of the clock: under the held clock the tests let each look the
  world takes go through, and look after each check too, since a check
  that never steps the world never lets it (`tests/lib.ss`); else their
  garbage would pile up.

## How a test steps time

Core1's loop paces its steps, `(schevana-step! wait-ms)`: a step ticks
only when a tick is wanted and due (`pacer-start`), after waiting for
it, and its processes run till the next tick's frame must be drawn
(`pacer-procs-ms`). The library has no other step. A test steps the world
itself, with `test-step!` (`tests/lib.ss`), which `steps` and `test-wait`
run:

- Each test's step is a tick, with no wait, as a screen ready for every
  frame at once would have it. It asks for a tick, as input does
  (`frame-turn-soon!`), and stands in for the pacer's two decisions for
  the step alone (`pacer-start`, `pacer-procs-ms`, in `test-stand-ins`):
  its tick is due now, and its processes run 10 ms, the most the pacer
  gives them, for the next tick comes when the test steps again. While a
  reload holds the world no step ticks, core1's or a test's.
- A tick's `t` (a window's `'frame`, a surface's) is the pacer's: when
  that tick's frame shows, a period after the last one's. Stepped back
  to back, the world moves a period a step, ahead of the machine's
  clock; once that clock has passed `t` by three periods (a pause), `t`
  is a period after the tick again. What rides frames (Boids, Springies,
  Fireflies) moves by its steps, not by the time a run takes.
- The test's clock is `now-ms`, by which timers, tooltips and carets
  go: `test-clock-hold!` holds it, `(steps n ms)` and
  `test-clock-advance!` move it. `now-ns` stays the machine's: the pacer
  and the profiler go by it. So a held clock holds what goes by time,
  not frames.
- A check of the pacer runs core1's own step, `schevana-step!`, on a
  fake clock of its own (`tests/units/pacer.ss`).

## Every run alike

- No flaky tests. A check that fails once and passes when run again is a
  bug: find what varies, and make the check measure only what it says. It
  is fixed at its cause or removed, never run again until it passes, and a
  limit raised says what it now means.
- What varies is fixed: a seed for what's random (`random-seed`), the fake
  clock for what's timed, a size given for each window a check measures.
- Topics run at once, so each holds on a busy machine: no check leans on
  how fast a step is, or reads the real clock where it means a step. A
  check that fails only under load is flaky; reproduce it beside spinning
  shells at the suites' own priority (nice 19), never above it, where the
  check would starve rather than share.
- What the world does by its clock happens between a check's steps when
  they're slow: the Pipeline reads the frame again a second after it last
  did, Monitor's view moves on twice a second, its rows sorted again and
  others among them. A scene such a read would change holds the clock
  (`test-clock-hold!`), holds the view as a person would (Monitor's
  Pause), or acts on what was last drawn, not on where it was a step ago.
- The least of several samples leaves out only what some of them lack. A
  slow run puts in every step what a fast one puts in few: a late tick's
  flag in the profiler, what the world does once a second. Steps whose
  allocation is measured run on a clock of their own
  (`tests/units/allocation.ss`).
- `bytes-allocated` counts every thread's allocation, another thread's by
  the 16 KB segment as it takes one, so a step measured on one thread
  counts another's segment whenever it falls in. A thread of the suites'
  own allocates nothing as it waits (the heap's watch, `tests/lib.ss`),
  and the world's are idle while a check measures.
- The held clock isn't held while a process runs that never yields: a
  process's turn ends by that clock, so it would never end. The clock
  fails the run when a tick reads it 100,000 times (`tests/lib.ss`).
- A collection comes when it likes. What a check expects to find made, it
  holds till it has seen it; only then does it let go and collect.
- The crew's limit on core1, 100 ms of the machine's clock, is long in
  every suite (`tests/lib.ss`): a busy machine keeps a worker waiting
  longer in an ordinary call. The crew's topic checks it at what it is.
- No check compares two of the machine's clocks: the monotonic clock and
  raw drift apart with the time a machine is up, either way.

## Both Chez versions

- Every check holds under Chez Scheme 10.0.0 and 10.4.1, the two
  `AGENTS.md` asks for. They count differently: from 10.4.0 a copy counts
  against an engine's ticks by its size, up to a timer period.
- A bound on what a version counts (engine ticks, bytes allocated) has room
  for both, and its comment says what each counts. It doesn't test the
  version.
- A suite runs under the `scheme` first on `PATH`, and `tests/units.ss`
  runs its topics by `chez` if `PATH` has one, else by `scheme`. To run
  them under the other version, build it from its release tag and put its
  `bin` first on `PATH`.
- On a Mac, 10.0.0 needs one line changed before it's built. Today's SDK
  defines `TARGET_OS_IPHONE` on a Mac too, as 0, and 10.0.0's
  `c/version.h` asks only whether it's defined, which leaves Chez there
  with no `system` (it raises) and an iPhone's code memory, which crashes
  with threads ("invalid memory reference"). Make the line
  `#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE`.
- A Mac's suites run by `chez`, and the build installs `scheme` alone: in
  its `bin` link `chez` to `scheme`, and beside `scheme.boot` link
  `chez.boot` to it, since Chez finds its boot file by the name it's run
  by. A link, not a script: a variable for the loader wouldn't get through
  `/bin/sh` (see "Any platform").

## Any font

The world sizes what holds text from the font's metrics, and the fonts
differ by system: Debian and Ubuntu put Noto Sans first for `sans-serif`
once it's installed, a Mac has Lucida Grande, and a person picks another
in Settings. A check holds with any of them.

- No size measured from a font is written as a number. An expected size is
  the rule the code follows, in the font's terms: `(font-line-height
  'mono)`, `(text-width "+2" 'ui-small)`, a style's floor and its line.
- A scene makes room for what it shows: it sizes a window by the lines it
  holds, or brings a target into view before it clicks it, so a taller
  font moves the target, not whether it's there.
- Text that must wrap, or must not, is made so by the width it's given,
  measured, not by a length that wraps in one font.
- Ink is compared with ink: where a check lines up glyphs, it measures the
  font's own (its side bearings differ by family), not a margin in pixels.
- When in doubt, run the test under a few fonts, DejaVu and Noto at least
  (`sudo apt install fonts-dejavu-core fonts-noto-core`). A fontconfig
  file that puts a family first for the generic names chooses it for one
  run, whatever the system prefers; this one is Noto's, and DejaVu's is
  the same with `DejaVu Sans` and `DejaVu Sans Mono`:

```bash
FONTCONFIG_FILE=$PWD/out/noto.conf scheme --script tests/units.ss out tasks
```

```xml
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <include ignore_missing="no">/etc/fonts/fonts.conf</include>
  <match target="pattern">
    <test name="family"><string>sans-serif</string></test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>Noto Sans</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="family"><string>monospace</string></test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>Noto Sans Mono</string>
    </edit>
  </match>
</fontconfig>
```

## Any platform

A stack differs by OS, windowing system, compositor, SDL, GPU API, driver,
monitor, CPU and Chez (`AGENTS.md`, "Layers"). A check holds on each.

- A check asks the platform as the world does, by its predicates and facts
  (`platform-mac?`, `platform-vulkan?`, `platform-cpu-count`), never by
  `machine-type` or a path that exists on one OS.
- A check of what one platform has (Metal's exact floats, Wayland's
  clock) says it was skipped elsewhere, in its output. A tool the checks
  need is required, never skipped: a check doesn't pass by checking
  nothing.
- What can be checked for another platform is checked everywhere: a Mac
  writes and validates the SPIR-V Linux runs.
- A check that runs Chez again runs it by `test-chez` (`tests/chez.ss`),
  never by a command line of its own: macOS drops the loader's variables
  (`DYLD_FALLBACK_LIBRARY_PATH`) on the way into `/bin/sh`, and `test-chez`
  hands on any a person set.
- What's drawn is compared with what the same machine draws, as the frame
  suite does, never with pixels stored from one rasterizer.
- A bound in time is for the bench (`tests/bench.ss`), not a suite: a
  check's limit in milliseconds holds on a slow machine under load, and
  says how far it is from what it measures. It limits the work, by the
  thread's own time in the CPU (`(current-time 'time-thread)`), never the
  wait: a busy machine keeps a thread waiting as long as it likes.
- Nothing depends on the monitor (its refresh, its scale, its size), the
  locale, the time zone, or a variable of the environment the suites don't
  set themselves.

## The docs' examples

The `docs` topic runs every `scheme` block of README.md, CREDITS.md and
`docs/*.md`, in order, as typed at a REPL at "/", each form in a process
as a REPL runs it, and each page in a world of its own. A comment `; =>
value` after a form, on its line or the next, is checked as what the form
returns, and an error, in a form, in what it left to run later or in a
window's handler, fails its block. A block fenced `scheme no-run` is shown
and not run: one that never ends, waits for a person, or needs what only a
test has.

## Timing

```bash
scheme --script tests/bench.ss out               # [frames]
```

The bench times frames on four scenes at 100% and 200%: 30 Life windows
tiled, a desktop of five overlapping windows, 30 Life windows cascaded,
and those under a maximized REPL. Then it times a keystroke in the REPL,
an idle step, a theme change, Tasks maximized on a 4K screen, what
profiling costs, and the crew with Life and Boids. Some of these have
bounds it checks: an idle step stays under 0.2 ms and uploads nothing.
