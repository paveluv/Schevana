# Tests

This guide says what the suites are, how to run them and how to write a
check. What a change must pass before it's committed is in
[AGENTS.md](../AGENTS.md). A test that passes here and fails on another
machine, Chez or font is a broken test, even when this machine is the one
it was written on.

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
- **units** runs each file of `tests/units/`, one topic per file (an
  app's, a kit's, a service's or a part of the core's), each in a process
  of its own, so that no topic depends on what another left behind. It
  runs as many topics at once as the machine allows: at most its CPUs
  less two, and at most as many as fit in its free memory (within a
  container's limit too) less 1 GB, at what a topic takes at its peak
  (`test-jobs`, `tests/chez.ss`); or as many as `SCHEVANA_TEST_JOBS`
  says. Each docs page is a run of its own. Each run writes in a folder
  of its own, `out/topic`, and keeps its output there; the suite prints
  the outputs in the topics' order. `scheme --script tests/units.ss out
  life boids` runs those two topics alone.
- **frame** draws frames on lavapipe (or on Metal on a Mac), with no
  window but an offscreen one. It compares the screen bit for bit with the
  world drawn into an image, in every style and at several scales. It
  checks that every change shows on its frame, and that a window with
  nothing new to show asks for no frame. It runs in parts, as many at
  once as the machine allows, each part a world of its own. A part is some
  of the suite's sections and, for those drawn at several scales, some of
  the scales (`frame-parts`). A section begins with `(frame-section
  'name)`, and a loop over scales goes through `frame-scales`, which keeps
  the scales of the part that runs.
- **sources** checks the sources themselves: 80 columns, names, the
  layers and what crosses them, the core's budget, and who may name a
  color. It runs in seconds.

The suites run headless and never open a real window. They need
`spirv-val` (`sudo apt install spirv-tools`, `brew install spirv-tools`):
the shaders' topic writes every shader as SPIR-V, on a Mac too, and checks
it, since a module that lavapipe accepts may still be one that another
driver rejects. On Linux they need lavapipe (`mesa-vulkan-drivers`). On a
Mac, type `chez` for `scheme`; the tests run on Metal there, with no Dock
icon and no window shown. Homebrew's libraries are found where Homebrew
keeps them (`(schevana ffi)`), with no loader variable set.

## Running less while working

The whole suites take under a minute on a large machine, and a few
minutes on a small one; one check takes seconds. While a check is being
written or fixed, run what it needs; run the whole suites before the
commit, and under both Chez versions before the push (`AGENTS.md`).

- `tests/sources.ss` alone takes seconds, and a units topic can run alone:
  `scheme --script tests/units.ss out tasks`.
- `SCHEVANA_CHECK=text` stops any suite after the first check whose name
  contains the text (ignoring case). Everything before that check runs as
  in a whole run, so the check sees what it would see there. A run fails
  when no check's name contains the text; in units, name the topic too.

```bash
SCHEVANA_CHECK="a card's tags" scheme --script tests/units.ss out tasks
SCHEVANA_CHECK="Shift+Tab up onto a title" scheme --script tests/smoke.ss out
```

- `SCHEVANA_HACKER=1` runs any suite in the hacker edition (`--hacker`):
  every library spliced into the world, from its source. A check that
  holds in one edition only says so (`test-hacker?`). With no topic named,
  the units' runner runs only some topics there: those that tell the
  editions apart (the ones that name `test-hacker?`), and the demos'
  topic, whose launchers then run as the hacker edition's programs. A
  topic that is named runs there as asked.

```bash
SCHEVANA_HACKER=1 scheme --script tests/units.ss out
SCHEVANA_HACKER=1 scheme --script tests/units.ss out life
```

- A topic of one library by itself, which needs no world, says so in its
  first form: `(test-focus (schevana kits complete))`. In the library
  edition it then runs with only the libraries it names, from the tests'
  build, and the checks (`tests/check.ss`): the world is neither loaded
  nor booted. In the hacker edition it runs in the world, as any topic
  does.

## A check

A topic is a file in `tests/units/`, loaded into a world booted headless
(except a focused topic, above). From `tests/check.ss` it has `check`,
which runs an expression and reports whether it held, and `(raises?
thunk)`, which says whether a call raises. From `tests/lib.ss` it has
`(steps n)`, which runs `n` of the world's steps, each one a tick (see
"How a test steps time" below). And `tests/units.ss` gives it helpers that
more than one topic uses, among them `shown-picture`, `image` and
`max-diff`, which compare what was drawn.

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
  kit's, a service's or a part of the core's), which `tests/units.ss`
  runs in a process of its own: the check depends on no other topic, and
  what several topics use goes in `tests/units.ss`. `scheme --script
  tests/units.ss out life` runs one topic.
- A check's name is a sentence that says what is true when it passes.
- What can fail goes inside a check. A form outside a check that raises
  fails the suite at its line, and the suite goes on, but whatever the
  form left undone fails the checks after it.

## Levels

Tests form a hierarchy: the basics are checked at the bottom, and each
level above tests only what it adds, trusting the levels below.

1. The sources (`tests/sources.ss`): the rules the code itself follows.
2. The core and the kits (units: `ui`, `edit`, `text`, `drawing`, …):
   measuring, wrapping, and each widget by itself, in a synthetic window
   of its own: its layout in the size it's given, its keys, its mouse.
3. An app's API (units: `add-task!`, `tasks-match?`, `tasks-layout`): its
   rules, as procedures of what they're given. An app's tests don't test
   a widget: every widget is tested at level 2, so the only test an app
   needs of its screen is that it opens.
4. The world driven by events (smoke): what only the whole world does (a
   window's life, focus between windows, a reload, the desktop's menus and
   bars), each from a state the check sets up.
5. Frames (`tests/frame.ss`): that what changes shows, drawn as the world
   draws it.

- A check belongs to the lowest level that can see what it says. A check
  that repeats what a lower level checks is dropped, or moved down to that
  level.
- A sequence of checks starts from a state it sets itself (a window sized
  by the app's own measures, the selection it needs), not from what an
  earlier sequence left, so that one failure doesn't take the rest with
  it.

## What a test asks of a library

Nothing. A library is written for what it does, never for its tests: it
has no export, hook, state or name of its own for them. What a test needs
of a library, the test framework finds by itself:

- In the library edition, the suites boot the libraries as
  `tests/build.ss` builds them: the build changes each library as Chez
  expands it, both when it compiles into a cache of the build's own and
  when a reload evaluates it again. A library of a sealed layer (core0's,
  the recorder's, the core's, and the foundation below them), unless it
  is a facade, gives the tests every name it defines (but a plain
  `define` it also `set!`s, which Chez can't export), and the tests use
  each by its own name (`*pacer-margin*`, `gpu-frame!`). A definition
  listed in `test-stand-ins`, which the tests stand in for, becomes a
  hook, so that a `fluid-let` or a `set!` of it reaches every call
  (`now-ms`, `bell`, SDL's calls); the definition itself compiles as the
  library has it. A test that stands in for another definition adds it to
  the list. In the hacker edition every name is at the top level already,
  to be set like any other.
- A demo, which the suites' world doesn't load: `(test-demos! 'life)`
  loads it into the world, as the desktop does when it is given the demos'
  folder, for a test that opens the demo's window.
- A library that the world doesn't boot, such as a demo, and its own
  names: `(test-library '(demo boids) 'bo:)` (`tests/reach.ss`) strips the
  library, as the hacker edition strips every library, and evaluates its
  body again at the top level of an environment of its own. (In the
  hacker edition it uses the library as the world loads it.) It gives the
  test each name the library defines, under the prefix: `bo:boids-step`,
  `bo:boids-scatter`, `bo:boids`. The prefix keeps them apart from the
  world's names.
- A stand-in for one of the library's procedures is a `fluid-let` of the
  prefixed name. A stripped library calls its own procedures through the
  top level, so it calls the stand-in.
- Its app: the stripped library registers its app again, so both the
  launcher and the prefixed launcher (`bo:boids`) open the app the test
  reaches.

## What a test may touch

- Tests and scripts never touch the user's `~/.schevana-theme.ss`,
  `~/.schevana.ss` or `~/.schevana.d`. Point `*theme-file-path*` at a
  scratch file, as the suites do, or run with `HOME` set to a scratch
  folder.
- Nothing opens a real window: the suites run headless, on lavapipe (the
  Vulkan driver that runs on the CPU, `mesa-vulkan-drivers`), or on Metal
  on a Mac.
- A file a test writes goes in the suite's output folder (`out/`), named
  relative to it, never at an absolute path or in `/tmp`.
- A run whose heap passes its limit stops, as a failure, before the
  machine runs out of memory (`tests/check.ss`). The limit is 2 GB, where
  a topic or a suite takes from a few hundred MB to 1.5 GB;
  `SCHEVANA_TEST_HEAP_MB` sets another. The collector looks at the older
  generations at most every 500 ms of the clock, so under the held clock
  it would never look. The tests therefore let each look the world takes
  go through, and look after each check too, since a check that never
  steps the world never lets it look (`tests/lib.ss`). Otherwise the
  garbage in the older generations would pile up.

## How a test steps time

Core1's loop paces its steps, `(schevana-step! wait-ms)`: a step ticks
only when a tick is wanted and due (`pacer-start`), after waiting for it,
and its processes run until the next tick's frame must be drawn
(`pacer-procs-ms`). The core has no other kind of step. A test steps the
world itself, with `test-step!` (`tests/lib.ss`), which `steps` and
`test-wait` call:

- Each of a test's steps is a tick, with no wait, as if the screen were
  ready for every frame at once. The step asks for a tick, as input does
  (`frame-turn-soon!`), and stands in for the pacer's two decisions for
  that step only (`pacer-start` and `pacer-procs-ms`, listed in
  `test-stand-ins`): its tick is due now, and its processes run for 10
  ms, the most the pacer gives them, since the next tick comes when the
  test steps again. While a reload holds the world, no step ticks, whether
  it is core1's or a test's.
- A tick's `t` (what a window's `'frame` handler or a surface is given) is
  the pacer's: the time that tick's frame shows, a period after the last
  one's. Stepped back to back, the world moves on a period each step, and
  gets ahead of the machine's clock; once that clock has passed `t` by
  three periods (a pause), `t` is a period after the tick again. What
  moves with frames (Boids, Springies, Fireflies) moves by the steps, not
  by the time a run takes.
- The test's clock is `now-ms`, by which timers, tooltips and carets go:
  `test-clock-hold!` holds it, and `(steps n ms)` and
  `test-clock-advance!` move it. `now-ns` stays the machine's, since the
  pacer and the profiler go by it. So a held clock holds what goes by
  time, but not what goes by frames.
- A check of the pacer runs core1's own step, `schevana-step!`, on a fake
  clock of its own (`tests/units/pacer.ss`).

## Every run alike

- No flaky tests. A check that fails once and passes when run again is a
  bug: find what varies, and make the check measure only what it says. It
  is fixed at its cause or removed, never run again until it passes, and a
  limit that is raised says what it now means.
- What varies is fixed: a seed for what's random (`random-seed`), the fake
  clock for what's timed, and a size for each window a check measures.
- Topics run at once, so each must hold on a busy machine: no check
  depends on how fast a step is, or reads the real clock where it means a
  step. A check that fails only under load is flaky. Reproduce it beside
  spinning shells at the suites' own priority (nice 19), never above it,
  where the check would starve rather than share the CPU.
- What the world does by its clock happens between a check's steps when
  they are slow: the Pipeline reads the frame again a second after it last
  did, and Monitor's view moves on twice a second, its rows sorted again
  with new ones among them. A scene that such a read would change holds
  the clock (`test-clock-hold!`), holds the view as a person would
  (Monitor's Pause), or acts on what was last drawn, not on where it was a
  step ago.
- Taking the least of several samples leaves out only what some of the
  samples lack. A slow run puts into every step what a fast run puts into
  a few: a late tick's flag in the profiler, or what the world does once a
  second. Steps whose allocation is measured run on a clock of their own
  (`tests/units/allocation.ss`).
- `bytes-allocated` counts every thread's allocation, and counts another
  thread's by the 16 KB segment as that thread takes one. So a step
  measured on one thread counts another thread's segment whenever one
  falls within it. A thread of the suites' own allocates nothing as it
  waits (the heap's watch, `tests/check.ss`), and the world's threads are
  idle while a check measures.
- A held clock can't stay held while a process that never yields runs: a
  process's turn ends by that clock, so the turn would never end. When a
  tick reads the held clock 100,000 times, the run fails, and from then on
  the clock moves 1 ms at each read until it is held again
  (`tests/lib.ss`).
- A collection can come at any time. A check holds what it expects to
  find made until it has seen it; only then does it let go of it and
  collect.
- The crew's limit on core1, 100 ms of the machine's clock, is set to a
  minute in every suite (`tests/lib.ss`), since a busy machine keeps a
  worker waiting longer than 100 ms in an ordinary call. The crew's topic
  checks the limit at its real value.
- No check compares two of the machine's clocks: the monotonic clock and
  the raw one drift apart, in either direction, the longer a machine is
  up.

## Both Chez versions

- Every check holds under Chez Scheme 10.0.0 and 10.4.1, the two versions
  `AGENTS.md` asks for. They count differently: from 10.4.0 on, a copy
  counts against an engine's ticks by its size, up to a timer period.
- A bound on what a version counts (engine ticks, bytes allocated) leaves
  room for both, and its comment says what each counts. It doesn't test
  the version.
- A suite runs under the `scheme` first on `PATH`, and the runs it starts
  itself (the units' topics, the frame suite's parts) run under `chez` if
  `PATH` has one, else under `scheme` (`test-chez`). To run them under the
  other version, build it from its release tag and put its `bin` first on
  `PATH`.
- On a Mac, 10.0.0 needs one line changed before it's built. Today's SDK
  defines `TARGET_OS_IPHONE` on a Mac too, as 0, and 10.0.0's
  `c/version.h` asks only whether it's defined. That leaves Chez there
  with no `system` (it raises) and with an iPhone's code memory, which
  crashes with threads ("invalid memory reference"). Make the line
  `#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE`.
- A Mac's suites run by `chez`, and the build installs only `scheme`: in
  its `bin`, link `chez` to `scheme`, and beside `scheme.boot` link
  `chez.boot` to it, since Chez finds its boot file by the name it's run
  by. Use a link, not a script: a variable for the loader wouldn't get
  through `/bin/sh` (see "Any platform").

## Any font

The world sizes whatever holds text from the font's metrics, and the fonts
differ by system: Debian and Ubuntu put Noto Sans first for `sans-serif`
once it's installed, a Mac has Lucida Grande, and a person can pick
another in Settings. A check holds with any of them.

- No size measured from a font is written as a number. An expected size is
  the rule the code follows, in the font's terms: `(font-line-height
  'mono)`, `(text-width "+2" 'ui-small)`, a style's floor and its line.
- A scene makes room for what it shows: it sizes a window by the lines it
  holds, or brings a target into view before it clicks it, so that a
  taller font moves the target but doesn't decide whether it's there.
- Text that must wrap, or must not, is made so by the width it's given,
  as measured, not by a length that wraps in one font.
- Ink is compared with ink: where a check lines up glyphs, it measures the
  font's own ink (side bearings differ by family), not a margin in pixels.
- When in doubt, run the test under a few fonts, at least DejaVu and Noto
  (`sudo apt install fonts-dejavu-core fonts-noto-core`). A fontconfig
  file that puts a family first for the generic names chooses that family
  for one run, whatever the system prefers. This one is Noto's; DejaVu's
  is the same with `DejaVu Sans` and `DejaVu Sans Mono`:

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

- A check asks about the platform as the world does, by its predicates
  and facts (`platform-mac?`, `platform-vulkan?`, `platform-cpu-count`),
  never by `machine-type` or by a path that exists on one OS.
- A check of something only one platform has (Metal's exact floats,
  Wayland's clock) says in its output that it was skipped elsewhere. A
  tool the checks need is required, never skipped: a check doesn't pass by
  checking nothing.
- What can be checked for another platform is checked everywhere: a Mac
  writes and validates the SPIR-V that Linux runs.
- A check that runs Chez again does so with `test-chez` (`tests/chez.ss`),
  never with a command line of its own: macOS drops the loader's
  variables (`DYLD_FALLBACK_LIBRARY_PATH`) on the way into `/bin/sh`, and
  `test-chez` passes on any that a person set.
- What's drawn is compared with what the same machine draws, as the frame
  suite does, never with pixels stored from one rasterizer.
- A bound in time belongs in the bench (`tests/bench.ss`), not in a suite.
  A check's limit in milliseconds must hold on a slow machine under load,
  and its comment says how far it is from what it measures. It limits the
  work, by the thread's own time on the CPU (`(current-time
  'time-thread)`), never the wait: a busy machine keeps a thread waiting
  as long as it likes.
- Nothing depends on the monitor (its refresh, its scale, its size), the
  locale, the time zone, or an environment variable that the suites don't
  set themselves.

## The docs' examples

The `docs` topic runs every `scheme` block of README.md, CREDITS.md and
`docs/*.md`, in order, as if typed at a REPL at "/". Each form runs in a
process, as a REPL runs it, and each page runs in a world of its own: the
desktop's, given the demos' folder (`./desktop demo`). A comment
`; => value` after a form, on its line or the next, is checked against
what the form returns. An error fails its block, whether it comes from a
form, from what the form left to run later, or from a window's handler. A
block fenced `scheme no-run` is shown and not run: use it for a block
that never ends, waits for a person, or needs what only a test has.

## Timing

```bash
scheme --script tests/bench.ss out               # [frames]
```

The bench times frames in four scenes at 100% and 200%: 30 Life windows
tiled, a desktop of five overlapping windows, 30 Life windows cascaded,
and those under a maximized REPL. Then it times a keystroke in the REPL,
an idle step, a theme change, Tasks maximized on a 4K screen, what
profiling costs, and the crew with Life and Boids. It checks bounds on
some of these: an idle step stays under 0.2 ms and uploads nothing.
