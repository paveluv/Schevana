# Rules for changes to Schevana

These are the rules every change, and so every pull request, must follow.
`README.md` explains the system; this file holds the rules. Where a test
checks a rule, the rule names the test.

## Before every commit

Run the suites from the repository's root under Chez Scheme 10.4.1, and
before every push under 10.0.0 too. In the library edition all four
suites must pass; in the hacker edition (`SCHEVANA_HACKER=1`), smoke and
the units' topics that tell the two editions apart, which the runner
picks by itself there:

```bash
mkdir -p out
scheme --script tests/smoke.ss out
scheme --script tests/units.ss out
scheme --script tests/frame.ss out
scheme --script tests/sources.ss
SCHEVANA_HACKER=1 scheme --script tests/smoke.ss out
SCHEVANA_HACKER=1 scheme --script tests/units.ss out
```

The suites size themselves to the machine: they run as many processes at
once as its CPUs and free memory allow (`tests/GUIDE.md`), and they pass
on a machine with 8 GB of memory.

- A test asks nothing of a library: no export, hook, state or name that
  exists only for the test. The test framework reaches what it needs by
  itself. It builds the libraries the suites boot in its own way
  (`tests/build.ss`): a library of Schevana's exports every name it
  defines, under the prefix `test:` (`tests/given.ss` gives each its own
  name again), and a definition a test stands in for becomes a hook. A
  demo's own names it reaches by stripping the library, as the hacker
  edition does (`test-library`, [tests/GUIDE.md](tests/GUIDE.md)).
- A change in behavior comes with a test of it, written by the rules in
  [tests/GUIDE.md](tests/GUIDE.md): where a check goes, what it may
  touch, and how it keeps passing under both Chez versions, with any font
  and on any platform (and how to run the suites under the other Chez).
- A new internal structure isn't finished until an `inspect-…` procedure
  in `schevana/kits/inspect.sls` reads it, so that the Pipeline can show
  it and a REPL and a test can read it.

## Simplicity first

Simplicity comes first, speed second.
- Of two designs, take the simpler one unless the speed gap is large and
  measured.
- No fast path that is right only while a built-in procedure stays as it
  is: anything can be redefined live, so code may not assume what
  `draw-window`, a style's part or a draw procedure does. Rules the
  system enforces (a clip, a budget, a check) are fine.
- Chez's own features (continuations, engines) are welcome where they
  make the code simpler.

## Layers

The world loads in this order, and each layer depends only on the ones
before it:

| Layer | What goes there |
|---|---|
| `desktop` and the demos' launchers | Short programs at the tree's root, which is where Schevana's libraries are found. Each loads `src/launch.ss` and starts its library's main procedure. |
| `src/` | The top level's own files. `launch.ss` loads the tree's libraries, compiled into `.cache/`, or spliced for `--hacker`. `hacker.ss` is the hacker edition: every library spliced into one environment, with all its names redefinable. `strip.ss` gives a library's own forms at the top level, for the hacker edition and the tests' `test-library`. `base.ss` is what every environment of the top level has, each its own copy: the basics, the forwarders by which an environment gives another its names, and the top level's own forms. These files are pure: no state, no C. |
| `schevana/core0/` | Core0, below the core, sealed in its libraries: the GPU's device side, the window and its events, the trace, and what differs by platform. A launcher boots core0, which runs core1 on the world's own thread (headless, one thread plays both). The core sees only core0's facade, `(schevana core0)`. The recorder, `schevana/recorder/` (the bytes of frames and their writers), sees `(schevana core0 for-recorder)`, and the core sees the recorder's facade, `(schevana recorder)`. |
| `schevana/core/` | The core, sealed in its libraries, `(schevana core <piece>)`: the world (windows, focus, the theme's layers, processes, timers, and its side of core0's window and events), core1's side of the GPU layer, drawing and fonts, the pacer, the loop, its registries, the hooks that later layers fill, and the caches its own procedures need. It also makes the world's environment, "/", where everything after it loads, and loads and reloads the world's files (`sources.sls`). The world sees only the core's facade, `(schevana core)`, which lists what the world is given. |
| `schevana/kits/` | Libraries that are pure or nearly so, `(schevana kits <name>)`. |
| `schevana/services/` | Long-lived state with an API and no surface: the crew of worker threads, the tree of environments and its sandboxes, vats and their jobs, the profiler, and the saved look. |
| `schevana/styles/`, `schevana/palettes/`, `schevana/wallpapers/` | The looks: one definition per library, registered as the library runs (the registries are the core's: `define-style`, `define-palette`, `define-wallpaper`). A look keeps its parts in the folder of its name, as libraries that it imports: what is too big for one file (Adwaita's and Cons's areas: `(schevana styles adwaita controls)`, `(schevana styles cons widgets)`, ...), or comes under a license of its own, which the part carries (`(schevana styles open-look fonts)`, OLGX's glyph fonts under Sun's notice; `(schevana styles genera font-5x5)`, the CADR's font under MIT's). The library itself keeps what registers as it loads: its settings' defaults and the style. |
| `schevana/desktop/` | The screen's own surfaces and the desktop's behavior: the wallpaper, the bars, the menu, toasts, keys and arranging windows; and its start (`main.sls`, from the command line, and `start.sls`, once the world has loaded). |
| `schevana/apps/` | The desktop's own apps (the REPL, Settings, Tasks, Monitor, Clock, ...), one per library, each defined with `define-app`. |
| `demo/` | The demos, one library each, `(demo <name>)`, built on the core's facade. A demo too big for one file keeps its parts in the folder of its name, as libraries of their own that it imports (Boids 3D: `(demo boids3d)`, and `(demo boids3d flock)` and the rest in `demo/boids3d/`). Each is an app the desktop adds when it is given the folder (`./desktop demo`: Boids, Life, Springies, ...), or what such a desktop starts with (the backlog, which enters Tasks' tasks as you would at a REPL); some are programs too, with a launcher at the root (`./rings-demo`). |
| `games/` | The games, one library each, `(games <name>)`, built on the core's facade, with their parts in the folder of their name as a demo has them (`(games prism-relay)`, and `(games prism-relay board)` and the rest in `games/prism-relay/`). A REPL loads one by its name (`(import (games fireflies))`, then `(fireflies)`), or the desktop loads them all when given the folder (`./desktop games`); each is a program too, with a launcher at the root (`./game-demo`). |

- **The boot is a chain.** A launcher boots core0, then core1, which
  boots the world (`(schevana desktop main)`). A sealed layer gives the
  next layer only what its facade exports (`(schevana core0)`,
  `(schevana recorder)`, `(schevana core)`); a state or a hook that the
  layer sets itself comes as a read-only view. The core's facade gives
  the hooks that later layers fill as settable, with a check
  (`define-settable`). Nothing else of a layer can be named, and nothing
  reaches back up. The world sees core0's and the recorder's names only
  where the core passes them on. A new name in a facade is a reviewed
  change, and `tests/sources.ss` checks that no layer names another
  layer's names beyond its facade.
- **A library of Schevana's declares its layer** first in its body,
  `(library-layer core0)`, or `(library-layer core0 facade)` for a sealed
  layer's front door. As it compiles, `(schevana base)` holds it to the
  layers' order: it imports no layer above its own, and of a sealed layer
  other than its own only the facade (`tests/units/boot.ss`;
  `tests/sources.ss` checks that every library under `schevana/`
  declares one). A demo or a game declares no layer, as a library from
  outside the tree needs none.
- **The core never depends on a later layer.** It reaches later layers
  only through the registries, parts and settings they fill and the hooks
  they set: what its facade gives as settable (`*profile-span*`,
  `theme-save!`, `window-gone!`, ...).
- **The looks sit below the desktop.** A look imports the core's facade,
  kits and services, never the desktop or an app, so that a program can
  take a look without the desktop's surfaces, keys and timers (a host
  app, `(schevana kits host)`). The desktop hands its parts what they
  draw, as arguments, the way the widget kit hands its own: a bar gets
  its height, its areas and the status; the menu gets itself (the menu
  kit's data), its areas and the chosen entry; the toasts get their
  boxes. A style reads none of the desktop's state.
- **Nothing below the apps names an app.** An app, a demo or a game may
  be anyone's: the core, the kits, the services, the looks and the
  desktop name nothing that one defines or registers, in code or by name
  (a setting a style gives, `world-value`'s name). What a style changes in
  an app's look is a kit's part that the app draws with (a board's
  columns and cards, a mark, a due date: `ui-draw-board-column`,
  `ui-draw-mark`, `ui-draw-due`), so that any app can use it. A piece may
  take its name from a signature app (`'repl-paren`, the transcript
  kit's), as long as it lives below the apps (`tests/sources.ss`).
- **Core0 sits below the core.** Core0's libraries name nothing of the
  core above them, and only core0 names SDL: the clock and the CPU count
  are core0's, and it gives them to core1. What still crosses the line is
  listed in `tests/sources.ss`, and those lists only shrink
  (`.work/gpu-design.md` 9.5, 9.12).
- **`src/base.ss` is pure.** It keeps no state and calls no C, so each
  environment's copy is as good as another's (`tests/sources.ss`).
  Whatever isn't pure belongs to core0 or the core, and a facade gives it.
- **What differs by platform lives in the platform files**:
  `schevana/core0/platform.sls` for core0's (a folder,
  `schevana/core0/platform/`, once it outgrows one file) and
  `schevana/core/platform.sls` for the core's. A stack differs by OS,
  windowing system, compositor, SDL, GPU API, driver and monitor. Code
  learns which platform it runs on only from their predicates and facts
  (`platform-mac?`, `platform-wayland?`, `platform-vulkan?`,
  `platform-windowing`; the OS's and CPU's in `schevana/base.sls`). What a
  platform can do is asked of the thing itself (a library that loads, a
  protocol the compositor lists), never assumed, and nothing crashes
  when it is missing. What the platform reports (its clock, its refresh)
  beats what was measured on one machine, and is checked where it can
  be. What still sits elsewhere is listed in `docs/PLATFORMS.md` and is
  to move into those files (`tests/sources.ss`). A change to such a
  feature updates `docs/PLATFORMS.md`: where it ran, where it should
  work, and what happens without it. Monitor's Platform tab shows all of
  it, and copies a run as a row of that table.
- **The core has a budget** of 41,585 tokens (atoms as read; comments,
  whitespace and the lengths of names are free, and a library's exports
  and imports, which only declare, are left out), set in
  `tests/sources.ss`. Don't join lines or shorten names to fit it: move
  code the core doesn't need out to the next layer, kits first. The
  budget is raised only on purpose.
- **Only the core calls C.** No library above the core (kits, services,
  looks, the desktop, apps, demos, games) binds SDL, FreeType or
  fontconfig or calls a `foreign-…` procedure, and no binding is
  exported to the world: when the world needs something of C, the core
  grows a primitive for it (`tests/sources.ss`). Core1 calls C through
  the bindings below the layers (`(schevana ffi)`, `(schevana freetype)`,
  `(schevana fontconfig)`), which any layer may import.
- **Only `(schevana ffi)` loads a shared library** (`ffi-load-library`,
  `load-first-library`). Chez's `load-shared-object` keeps each library's
  handle where its collector reads it as an object, and a Mac's handle
  need not look like one that the collector leaves alone: once the heap
  has grown over the address the handle names, a full collection ends the
  process. So no other file names `load-shared-object`, the tests'
  included, but for two tests that check for the name and call nothing,
  and no page of the docs shows it as code (`tests/sources.ss`, which
  lists the files that name it; `tests/units/platform.ss` checks the
  handles Chez keeps).
- **The GPU layer speaks the world's terms.** Above core0, in the core
  too, nothing names SDL's GPU API, Vulkan, SPIR-V, Metal or MSL, so that
  another back end, or raw Vulkan, stays core0's business alone
  (`tests/sources.ss`; the compiler, `schevana/shader.sls`, writes the
  back ends' code).
- **The shader language is the contract.** A feature that a back end
  can't provide doesn't get into the language: the twin
  (`schevana/kits/twin.sls`) has been a second back end from the start,
  and `tests/units/shader.ss` holds it and the device to the same
  results.
- **A library or file in the world's folders registers what it
  defines** (`tests/sources.ss`). "/" imports each of the world's
  libraries and runs it: the folders in their order, and each folder's
  libraries and files in file-name order (`world-entries`).

## State

- **S1. One owner.** Outside the core, only the file that defines a
  global sets it; other files call its procedures. The exception is the
  core's hooks, which its facade gives as settable; a `fluid-let` for a
  temporary view does not count as setting (`tests/sources.ss`). The
  world gets the rest of the core's globals read-only; a look that isn't
  the current one is read with `call-with-theme`.
- **S2. State by layer.** The world's state belongs to the core. A kit
  keeps no state except caches whose loss changes only speed, and state
  kept in an object its caller holds (a ui, an edit, an owner's
  completion list). A service keeps long-lived state behind its
  procedures. The desktop keeps its surfaces' state; an app keeps its own
  data, per window where it can.
- **S3. Lifetime.** State that must outlive `(reload!)` is a
  `define-state` in a library, or a `defvar` in a file (the user's); a
  cache may be a `define` that starts empty. What a world does once, when
  a library first loads (starting a timer, giving an app its first
  data), is an `at-load-once`, which a reload doesn't run again. A
  window's state lives in the window (`window-ref`, `window-set!`), not
  in a global table.
- **S4. Threads.** Global state belongs to core1, the world's thread, and
  only core1 writes it. The exceptions are a service's own structures
  that threads share, which change only by `box-cas!` (core1's mail, the
  crew's loops, a vat's mailbox). A worker runs only worklets
  (`define-worklet`): procedures compiled where SDL and the world's state
  are out of reach, which touch only what they are handed. In a vat, a
  worker runs code compiled in the vat's own sandbox, which only the
  vat's thread evaluates. The crew and the vats refuse any procedure that
  isn't a worklet, and a vat's results come back to core1 the same way.
  Don't hand a worker the world's code by other means (`fork-thread`).
- **S5. Names.** A global is earmuffed and carries its owner's prefix
  (`*status-segments*`, `*repl-inputs*`). A hook is not state: it is a
  procedure that may be replaced, defined with `define-hook` and named
  the way a procedure is, with a `!` when it changes state
  (`window-gone!`, `record-world!`). The file that provides what the hook
  does sets it (`set-hook!`).
- **S6. Environments.** Code that makes an environment shares a list of
  names with it (`env-share!`, `env-fork`'s `'share`), each read-only or
  through a setter that may refuse. Sharing every name of the world is a
  world namespace's alone, which a person asks for at a REPL or in the
  Environments app (`tests/sources.ss`). An environment forks only the
  kinds that its own kind allows (`env-forks`).
- **S7. Libraries.** What a library of the core's makes as it loads is
  kept in a state (`define-state`, when it is ever set) or a made value
  (`define-made`, when it never is: a buffer, a table, a foreign
  procedure, a fact found out). A plain definition there is a procedure
  or a literal, so no procedure it defines carries anything, and a
  closure that calls one costs what it did at the top level
  (`tests/units/allocation.ss`).

## Names

- The world's libraries give their names to "/", one shared namespace
  (and the hacker edition splices their internals there too). So no
  plain common word (`part`, `rule`, `item`) names a global, and no two
  libraries define the same name. Qualify a name by its owner or subject:
  `theme-`, `style-`, `window-`. A demo exports only its launcher; the
  names it keeps to itself may be its own words (`pt` in Springies),
  which the hacker edition holds too, as long as no other library defines
  them (`tests/sources.ss`). Its parts, in the folder of its name, export
  what it uses; the world loads them as its imports, not as its own, so
  their names come to "/" only in the hacker edition
  (`auto-load-entries`).
- In `schevana/kits/` and `schevana/services/`, every name starts with
  its library's name: `ui-…` in `(schevana kits ui)`, `profile-…` in
  `(schevana services profile)`; a record named after the library may
  give `make-x` and `x?` (`tests/sources.ss`). A record whose name is also
  a procedure's name takes a different name (`repl-record`, the REPL's).
- A library under `schevana/` imports each of the tree's libraries with
  `only`, naming what it uses, and names every name it imports. Its own
  parts, the libraries in the folder of its name, it imports whole, as a
  part does its siblings. A demo or a game imports every library whole,
  as a program from outside would (`tests/sources.ss`).
- A library exports only what something uses: a library that imports
  it, a program at the tree's root or in `src/`, or, for a library whose
  names "/" has (the world's and the core's facade), the docs or a lookup
  by name (`world-value`, a procedure a style or a surface names). A name
  nothing uses yet stays exported only if it makes a good example at a
  REPL, and then the docs show it (`tests/sources.ss`). The tests reach
  the rest by themselves.
- American spelling everywhere: code, comments, UI text and documents
  (color, gray, center, neighbor, labeled).

## Live redefinition

- The world is made of libraries, which change with their files at a
  reload. A `define` at "/" makes a name of the world's own, which the
  world reaches only where it looks a name up at "/" (`world-value`: a
  part's procedure, `draw-topbar`, a handler that calls a name); a
  library's calls to its own names and its imports don't see it. What may
  be replaced live is a hook that the facade gives as settable, or
  something called by name. The hacker edition (`--hacker`,
  `src/hacker.ss`) splices every library into "/", where any name may be
  redefined and every call reaches the new definition.
- A hook or a registry calls procedures by name, so that a redefinition
  takes effect at the next call: write
  `(lambda () (theme-file-save-soon!))`, not `theme-file-save-soon!`
  captured as a value.
- `(reload!)` of the tree into itself must keep working. It evaluates
  again each library whose file changed and every library that imports
  it (`schevana/reload.sls`), imports them again where they were imported
  ("/" among them), runs the world's libraries and loads its files (the
  user's). Core0's libraries, and everything they import, change only
  with a restart (`tests/units/reload.ss`).

## Drawing and the look

- Only drawing procedures draw or name a color: in kits, services, the
  desktop, Tasks, Settings and Environments, code that is not a draw
  procedure, a part or a theme default names no color and calls no
  drawing primitive (`tests/sources.ss`).
- A color is a theme key (`'accent`, `'text-dim`) or a mix of them. A
  look that differs by style is a part or a setting that a style gives,
  never a test of which style is on.
- Everything drawn is a record. A form like `with-clip` allocates no
  closure, and recording whole numbers allocates nothing
  (`tests/units/pipeline.ss`).
- **Mimicked styles** (Mac, Windows, Genera, the CADR, Interlisp, OPEN
  LOOK, Adwaita, GNOME, and in the future CDE and Platinum) use the
  original's widgets. Where the original has none, make what its
  designers would have made. **Our own styles** (Cons, Curses, Draft,
  Fold, Halo, Lambda, Reticle, Slab, Spine) are free, as long as each
  stays coherent.
- Sources for mimicked styles:
  - GPL desktops (NsCDE, ZacOS 9): facts only (sizes, colors, rules),
    with references; copy no code, pixmaps, icons, fonts or backdrops.
  - libadwaita (LGPL) and GNOME Shell (GPL): facts only (sizes, colors,
    radii, alphas, rules), with references as file:line at the tag; copy
    no SCSS, code, icons, images or fonts.
  - MIT's CADR sources (BSD) and Medley Interlisp (MIT): use them, and
    attribute them.
  - XView 3.2's OLGX and olwm (Sun's notice) and Sun's glyph fonts
    (X-style): use them, and attribute them with their notices
    (`CREDITS.md`).
  - Genera's sources: never. Use only its manuals and screenshots.

## Formatting

- Every line of every source file is at most 80 characters, counted as
  Unicode characters (`tests/sources.ss`). Wrap between subforms, in the
  file's own indentation; split a long string with R6RS's
  backslash-newline.
- In configurations (a settings or color plist, an option table, a
  `define-style` or `define-palette` body), put one item per line: a key
  and its value alone on the line.
- Comments and documents are in plain English: full sentences, with
  articles and the usual word order, and "Returns ..." for what a
  procedure returns. A comment says why, briefly, rather than retelling
  the code, and states what is true now, with no history of how it got
  there. Keep the project's terms (core0, core1, "/", a tick, a part, a
  hook, a worklet) and the names and idioms of the file you change.
