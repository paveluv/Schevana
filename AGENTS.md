# Rules for changes to Schevana

What every change, and so every pull request, must follow. `README.md`
explains the system; this file is the rules. Where a rule is checked by a
test, the test is named.

## Before every commit

All four suites pass under Chez Scheme 10.4.1, and before every push
under 10.0.0 too, run from the repository's root, in the library edition
and in the hacker edition (`SCHEVANA_HACKER=1` before each):

```bash
mkdir -p out
scheme --script tests/smoke.ss out
scheme --script tests/units.ss out
scheme --script tests/frame.ss out
scheme --script tests/sources.ss
```

- A test asks nothing of a library: no export, hook, state or name of
  its own for the test. The test framework reaches what it needs itself:
  the libraries the suites boot as the tests build them, a sealed
  layer's every name given and what a test stands in for a hook
  (`tests/build.ss`), and a demo's own names stripped as the hacker
  edition strips it (`test-library`, [tests/GUIDE.md](tests/GUIDE.md)).
- A change in behavior comes with a test of it, written by the rules in
  [tests/GUIDE.md](tests/GUIDE.md): where a check goes, what it may touch,
  and how it holds under both Chez versions, with any font and on any
  platform (and how to run the suites under the other Chez).
- A new internal structure isn't finished until an `inspect-…` procedure in
  `schevana/kits/inspect.sls` reads it: what the Pipeline shows, a REPL and a test can
  read.

## Simplicity first

Simplicity comes first, speed second.
- Of two designs, take the simpler one unless the speed gap is large and
  measured.
- No fast path that is right only while a built-in procedure stays
  unredefined: anything can be redefined live, so code may not assume what
  `draw-window`, a style's part or a draw procedure does. Rules the system
  enforces (a clip, a budget, a check) are fine.
- Chez's own features (continuations, engines) are welcome where they make
  the code simpler.

## Layers

The world loads in this order, and each layer depends only on the ones
before it:

| Layer | What goes there |
|---|---|
| `schevana-desktop` and the demos' launchers | Programs of a few lines at the tree's root, which is where Schevana's libraries are found: each loads `src/launch.ss` and starts its library's main. |
| `src/` | The top level's own files: `launch.ss` (the tree's libraries, compiled into `.cache/`, or spliced for `--hacker`), `hacker.ss` (the hacker edition: every library spliced into one environment, all its names redefinable), `strip.ss` (a library's own forms at the top level, for the hacker edition and the tests' `test-library`), and `base.ss`: what every environment of the top level has, a copy each, the basics, forwarders, by which an environment gives another its names, and the top level's own forms. Pure: no state, no C. |
| `schevana/core0/` | Core0, below the core, sealed in its libraries: the GPU's device side, the window and its events, the trace, what differs by platform. A launcher boots it, and core1 on the world's own thread (headless, one thread plays both). The core has of it only its facade, `(schevana core0)`; the recorder, `schevana/recorder/` (the bytes of frames and their writers), has `(schevana core0 for-recorder)`, and the core has of the recorder its facade, `(schevana recorder)`. |
| `schevana/core/` | The core, sealed in its libraries, `(schevana core <piece>)`: the world (windows, focus, the theme's layers, processes, timers, its side of core0's window and events), core1's side of the GPU layer, drawing and fonts, the pacer, the loop, its registries, the hooks later layers fill, and the caches its own procedures need; making the world's environment, "/", where everything below loads, loading the world's files and reloading (`sources.sls`). The world has of it only its facade, `(schevana core)`, which lists what the world is given. |
| `schevana/kits/` | Libraries, pure or almost, `(schevana kits <name>)`. |
| `schevana/services/` | Long-lived state with an API and no surface: the crew of worker threads, the tree of environments and its sandboxes, vats and their jobs, the profiler, the saved look. |
| `schevana/styles/`, `schevana/palettes/`, `schevana/wallpapers/` | The looks: one definition per library, registered by its definer as the library runs (the registries are the core's: `define-style`, `define-palette`, `define-wallpaper`). |
| `schevana/desktop/` | The screen's own surfaces and the desktop's behavior: wallpaper, bars, menu, toasts, keys, arranging windows; and its start (`main.sls`, from the command line; `start.sls`, once the world is loaded). |
| `schevana/apps/` | The desktop's own apps (the REPL, Settings, Tasks, Monitor, Clock, ...), one per library, defined with `define-app`. |
| `schevana-demo/` | The demos, one library each, `(schevana-demo <name>)`, on the core's facade: an app the desktop adds when its folder is given (`./schevana-desktop schevana-demo`: Boids, Life, Springies, ...), some a program too, with a launcher at the root (`./schevana-game-demo`). |

- **The boot is a chain**: a launcher boots core0, then core1, which
  boots the world (`(schevana desktop main)`). A sealed layer gives the next only what its facade
  exports (`(schevana core0)`, `(schevana recorder)`, `(schevana core)`),
  a state or a hook it sets as a read-only view; the core's facade gives
  the hooks later layers fill settable, checked (`define-settable`).
  Nothing else of a layer's is there to name, and nothing reaches back
  up. The world has of core0's and the recorder's only what the core
  gives it again. A new name in a facade is a reviewed change, and
  `tests/sources.ss` checks that no layer names another's beyond it.
- **A library declares its layer** first in its body, `(library-layer
  core0)`, or `(library-layer core0 facade)` for a sealed layer's front
  door, and is held to the layers' order as it compiles (`(schevana
  base)`): it imports no layer above its own, and of a sealed layer not
  its own only the facade (`tests/units/boot.ss`; that every library
  declares one, `tests/sources.ss`).
- **The core never depends on a later layer.** It reaches them only
  through registries, parts and settings they fill, and hooks they set:
  what its facade gives settable (`*profile-span*`, `theme-save!`,
  `window-gone!`, ...).
- **The looks sit below the desktop.** A look imports the core's facade,
  kits and services, never the desktop or an app, so that a program takes
  a look without the desktop's surfaces, keys and timers (a host app,
  `(schevana kits host)`). The desktop hands its parts what they draw, as
  arguments, as the widget kit hands its own: a bar its height, its areas
  and the status, the menu itself (the menu kit's data), its areas and
  the entry chosen, the toasts their boxes; a style reads none of the
  desktop's state.
- **Core0 sits below the core.** Core0's libraries name nothing of the
  core above it, and only core0 names SDL: the clock and
  the CPU count are core0's, which it gives core1. What still crosses is
  listed in `tests/sources.ss`, and the lists only shrink
  (`.work/gpu-design.md` 9.5, 9.12).
- **`src/base.ss` is pure**: it keeps no state and calls no C, so each
  environment's copy is as good as another (`tests/sources.ss`). What
  isn't pure is core0's or the core's, and given by a facade.
- **What differs by platform lives in the platform files**:
  `schevana/core0/platform.sls` for core0's (a folder,
  `schevana/core0/platform/`, once it outgrows a file),
  `schevana/core/platform.sls` for the core's. A stack
  differs by OS, windowing system, compositor, SDL, GPU API, driver and
  monitor. Which one this is comes from their predicates and facts alone
  (`platform-mac?`, `platform-wayland?`, `platform-vulkan?`,
  `platform-windowing`; the OS and CPU's in `src/base.ss`), which say
  which platform this is: what it can do is asked of the thing (a library
  that loads, a protocol the compositor lists), never assumed, and
  nothing crashes without it. What the platform says (its clock, its
  refresh) beats what was measured on one machine, and is checked where
  it can be. What sits elsewhere today is listed in `docs/PLATFORMS.md`
  and moves there (`tests/sources.ss`). A change to such a feature
  updates `docs/PLATFORMS.md`: where it ran, where it should work, what
  happens without it. Monitor's Platform tab shows it all, and copies a
  run as a row of it.
- **The core has a budget**, 39,763 tokens (atoms as read; comments,
  whitespace and names' lengths are free; a library's exports and
  imports, which declare, are left out), in `tests/sources.ss`. Don't join lines or
  shorten names to fit it. Code the core doesn't need moves out to the
  next layer, kits first; the budget is raised only on purpose.
- **Only the core calls C.** No SDL, FreeType or fontconfig binding, or
  `foreign-…` procedure, outside `src/`, and no binding is exported to the
  world: the core grows a primitive instead (`tests/sources.ss`). Core1
  binds its own C with `define-foreign`, which core0 gives it.
- **The GPU layer speaks the world's terms.** Above core0, in the core too,
  nothing names SDL's GPU, Vulkan, SPIR-V, Metal or MSL, so that another
  back end or raw Vulkan stays core0's business alone (`tests/sources.ss`;
  the compiler, `schevana/shader.sls`, writes the back ends' code).
- **The shader language is the contract.** What a back end can't do doesn't
  get in: the twin (`schevana/kits/twin.sls`) is a second back end from the start, and
  `tests/units/shader.ss` holds it and the device together.
- **A library or a file of the world's folders registers what it
  defines** (`tests/sources.ss`). "/" imports each of the world's
  libraries and runs it, the folders in their order, each folder's
  libraries and files in file-name order (`world-entries`).

## State

- **S1. One owner.** Outside the core, only the file that defines a global
  sets it; the others call its procedures. The core's hooks, which its
  facade gives settable, are the exception, and `fluid-let` for a temporary
  view is not a set (`tests/sources.ss`). The world is given the rest of
  the core's read-only: a look that isn't on is read with
  `call-with-theme`.
- **S2. State by layer.** The world is the core's. A kit keeps no state but
  caches whose loss changes only speed, and state kept per object its
  caller holds (a ui, an edit, an owner's completion list). A service keeps
  long-lived state behind its procedures. The desktop keeps its surfaces'
  state; an app its own data, per window where it can.
- **S3. Lifetime.** State that must outlive `(reload!)` is, in a
  library, a `define-state`, in a file (the user's) a
  `defvar`; a cache may be a `define` that starts empty. A window's state lives in the
  window (`window-ref`, `window-set!`), not in a global table.
- **S4. Threads.** Global state belongs to core1, the world's thread, and
  only it writes it. The exceptions are a service's own structures that
  threads share, changed only by `box-cas!` (core1's mail, the crew's
  loops, a vat's mailbox). A worker runs only worklets (`define-worklet`):
  procedures compiled where SDL and the world's state are out of
  reach, which touch only what they are handed; or, in a vat, code
  compiled in the vat's own sandbox, which its thread alone evaluates in.
  The crew and the vats refuse to hand them any procedure but worklets,
  and a vat's results come back to core1 the same way. Don't hand a worker
  world code by other means (`fork-thread`).
- **S5. Names.** A global is earmuffed and carries its owner's prefix
  (`*status-segments*`, `*repl-inputs*`). A hook is no state: it is a
  procedure that may be replaced, defined with `define-hook` and named
  as a procedure is, with a `!` when it changes state (`window-gone!`,
  `record-world!`). The file that has what it does sets it
  (`set-hook!`).
- **S6. Environments.** Code that makes an environment shares it a list
  of names (`env-share!`, `env-fork`'s `'share`), each read-only, or
  through a setter that may refuse. Every name of the world's is a world
  namespace's alone, which a person asks for at a REPL or in Environments
  (`tests/sources.ss`). An environment forks only the kinds its own
  allows (`env-forks`).
- **S7. Libraries.** What a library of the core's makes as it loads is
  kept in a state (`define-state`, when it is set) or a made value
  (`define-made`, when it never is: a buffer, a table, a foreign
  procedure, a fact found out). A plain definition there is a procedure
  or a literal, so no procedure it defines carries anything, and a
  closure that calls one costs what it did at the top level
  (`tests/units/allocation.ss`).

## Names

- The world's libraries give "/" their names, one shared namespace (and
  the hacker edition splices their internals there too), so no plain
  common word (`part`, `rule`, `item`) names a global, and no two
  libraries define one name. Qualify a name by its owner or subject:
  `theme-`, `style-`, `window-`. A demo exports its launcher alone; what
  it keeps to itself may keep its own words (`pt` in Springies), the
  hacker edition holding them too, while no other library defines them
  (`tests/sources.ss`).
- In `schevana/kits/` and `schevana/services/`, every name starts with its
  library's: `ui-…` in `(schevana kits ui)`, `profile-…` in `(schevana
  services profile)`; a record of the library's own name may give `make-x`
  and `x?` (`tests/sources.ss`). A record whose name is also a
  procedure's names itself apart (`repl-record`, the REPL's).
- American spelling everywhere: code, comments, UI text, documents (color,
  gray, center, neighbor, labeled).

## Live redefinition

- The world is libraries, which change with their files at a reload. A
  `define` at "/" makes a name of the world's own, which the world reaches
  where it calls by name (a hook, a part, a handler, `draw-window`): what
  may be replaced live is a hook or called by name. The hacker edition
  (`--hacker`, `src/hacker.ss`) splices every library into "/", where any
  name may be redefined and every call reaches it.
- A hook or a registry calls procedures by name, so a redefinition takes
  effect at the next call: `(lambda () (theme-file-save-soon!))`, not
  `theme-file-save-soon!` captured as a value.
- `(reload!)` of the tree into itself must keep working. It evaluates
  again each library whose file changed, and every library that imports
  it (`schevana/reload.sls`), imports them again where they were
  imported ("/" among them), runs the world's libraries and loads its
  files (the user's); core0's libraries, with all
  they import, change with a restart (`tests/units/reload.ss`).

## Drawing and the look

- Only drawing procedures draw or name a color: in kits, services, the
  desktop, Tasks, Settings and Environments, code that is not a draw
  procedure, a part or a theme default names no color and calls no
  drawing primitive (`tests/sources.ss`).
- A color is a theme key (`'accent`, `'text-dim`) or a mix of them; a look
  that differs by style is a part or a setting a style gives, never a test
  of which style is on.
- Everything drawn is a record; a form like `with-clip` allocates no closure,
  and recording whole numbers allocates nothing (`tests/units/pipeline.ss`).
- **Mimicked styles** (Mac, Windows, Genera, the CADR, Interlisp, OPEN
  LOOK, Adwaita, GNOME, and in future CDE and Platinum) use the original's
  widgets.
  Where the original has none, make what its designers would have made.
  **Our own styles** (Cons, Curses, Draft, Fold, Halo, Lambda, Reticle,
  Slab, Spine) are free, as long as they stay coherent.
- Sources for mimicked styles:
  - GPL desktops (NsCDE, ZacOS 9): facts only (sizes, colors, rules), with
    references; copy no code, pixmaps, icons, fonts or backdrops.
  - libadwaita (LGPL) and GNOME Shell (GPL): facts only (sizes, colors,
    radii, alphas, rules), with references as file:line at the tag; copy
    no SCSS, code, icons, images or fonts.
  - MIT's CADR sources (BSD) and Medley Interlisp (MIT): use, and attribute.
  - XView 3.2's OLGX and olwm (Sun's notice) and Sun's glyph fonts
    (X-style): use, and attribute with their notices (`CREDITS.md`).
  - Genera's sources: never. Its manuals and screenshots only.

## Formatting

- Every line of every source is at most 80 characters, counted as Unicode
  characters (`tests/sources.ss`). Wrap between subforms in the file's own
  indentation; split a long string with R6RS's backslash-newline.
- In configurations (a settings or color plist, an option table, a
  `define-style` or `define-palette` body), one item per line: a key and
  its value alone on the line.
- Comments say why, briefly, in the surrounding code's voice. Match the
  names, idioms and comment density of the file you change.
