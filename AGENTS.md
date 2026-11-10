# Rules for changes to Schevana

What every change, and so every pull request, must follow. `README.md`
explains the system; this file is the rules. Where a rule is checked by a
test, the test is named.

## Before you open a pull request

All four suites pass, run from the repository's root:

```bash
mkdir -p out
scheme --script tests/smoke.ss out
scheme --script tests/units.ss out
scheme --script tests/frame.ss out
scheme --script tests/sources.ss
```

- A change in behavior comes with a test of it.
- A unit check goes in its topic's file in `tests/units/` (an app's, a
  kit's, a service's, a part of the core's), which `tests/units.ss` runs in a
  process of its own: it leans on no other topic, and what several use is
  in `tests/units.ss`. `scheme --script tests/units.ss out life` runs one.
- Tests and scripts never touch the user's `~/.schevana-theme.ss`,
  `~/.schevana.ss` or `~/.schevana.d`. Point `*theme-file-path*` and
  `*grant-file-path*` at scratch files, as the suites do, or run with
  `HOME` set to a scratch folder.
- Nothing opens a real window: the suites run headless, on lavapipe, the
  Vulkan driver on the CPU (`mesa-vulkan-drivers`).
- A new internal structure isn't finished until an `inspect-…` procedure in
  `kits/inspect.ss` reads it: what the Pipeline shows, a REPL and a test can
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
| `src/host/` | Core0, below the core: the host's own code, SDL's bindings, the GPU's device side, and the window and its events. It loads right after `src/ffi.ss` and `src/base.ss`, then makes the world's environment, "/", where everything below loads. |
| `src/` | The core: the world (windows, focus, the theme's layers, processes, timers, the host's interface), the shader compiler, main's side of the GPU layer, the recorder and fonts, its registries, the hooks later layers fill, and the caches its own procedures need. |
| `kits/` | Libraries, pure or almost. |
| `services/` | Long-lived state with an API and no surface: the crew of worker threads, the tree of environments, the apps' sandboxes and what they are allowed, vats and their jobs, the profiler, the saved look. |
| `desktop/` | The screen's own surfaces and the desktop's behavior: wallpaper, bars, menu, toasts, keys, arranging windows. |
| `styles/`, `palettes/`, `wallpapers/` | One definition per file, registered by its definer. |
| `apps/` | One app per file, defined with `define-app`; one whose first form is `app-requests` runs in a sandbox of its own (`services/grant.ss`). |

- **The core never depends on a later layer.** It reaches them only
  through registries, parts and settings they fill, and hooks they set
  (`*profile-span*`, `*theme-saver*`, `*window-gone*`, `*app-loader*`).
- **Core0 sits below the core.** `src/host/` names nothing of the core
  above it, and only it names SDL, but for the clock and the CPU count,
  which any thread may call (`src/ffi.ss`). What still crosses is listed
  in `tests/sources.ss`, and the lists only shrink
  (`.work/gpu-design.md` 9.5, 9.12). The world names of core0's only its
  interface (`host-interface` in `src/host/boot.ss`), which "/" has
  read-only: a new name there is a reviewed change (`tests/sources.ss`).
- **The core has a budget**, 31,650 tokens (atoms as read; comments,
  whitespace and names' lengths are free), in `tests/sources.ss`. Don't
  join lines or shorten names to fit it. Code the core doesn't need moves
  out to the next layer, kits first; the budget is raised only on purpose.
- **Only the core calls C.** No SDL, FreeType or fontconfig binding, or
  `foreign-…` procedure, outside `src/`: the core grows a primitive instead
  (`tests/sources.ss`).
- **The GPU layer speaks the world's terms.** Above core0, in the core too,
  nothing names SDL's GPU, Vulkan, SPIR-V, Metal or MSL, so that another
  back end or raw Vulkan stays core0's business alone (`tests/sources.ss`;
  the compiler, `src/shader.ss`, writes the back ends' code).
- **The shader language is the contract.** What a back end can't do doesn't
  get in: the twin (`kits/twin.ss`) is a second back end from the start, and
  `tests/units/shader.ss` holds it and the device together.
- **A file in a folder registers what it defines** (`tests/sources.ss`).
- **An app in a sandbox requests what the table approves**
  (`grant-tree-apps` in `services/grant.ss`, `tests/sources.ss`): a new
  request is a reviewed change, and a bundle names only what the world
  has. An app that tunes the world (Settings, Tasks) requests nothing and
  runs there.

## State

- **S1. One owner.** Outside the core, only the file that defines a global
  sets it; the others call its procedures. The core's hooks are the
  exception, and `fluid-let` for a temporary view is not a set
  (`tests/sources.ss`).
- **S2. State by layer.** The world is the core's. A kit keeps no state but
  caches whose loss changes only speed, and state kept per object its
  caller holds (a ui, an edit, an owner's completion list). A service keeps
  long-lived state behind its procedures. The desktop keeps its surfaces'
  state; an app its own data, per window where it can.
- **S3. Lifetime.** State that must outlive `(reload!)` is a `defvar`; a
  cache may be a `define` that starts empty. A window's state lives in the
  window (`window-ref`, `window-set!`), not in a global table.
- **S4. Threads.** Global state belongs to the main thread, and only it
  writes it. The exceptions are a service's own structures that threads
  share, changed only by `box-cas!` (the main thread's mail, the crew's
  loops, a vat's mailbox). A worker runs only worklets (`define-worklet`):
  procedures compiled where SDL and the world's state are out of
  reach, which touch only what they are handed; or, in a vat, code
  compiled in the vat's own sandbox, which its thread alone evaluates in.
  The crew and the vats refuse to hand them any procedure but worklets,
  and a vat's results come back to main the same way. Don't hand a worker
  world code by other means (`fork-thread`).
- **S5. Names.** A global is earmuffed and carries its owner's prefix
  (`*status-segments*`, `*repl-inputs*`).
- **S6. Environments.** Code that makes an environment shares it a list
  of names (`env-share!`, `env-fork`'s `'share`), each read-only, or
  through a setter that may refuse. Every name of the world's is a world
  namespace's alone, which a person asks for at a REPL or in Environments
  (`tests/sources.ss`). An environment forks only the kinds its own
  allows (`env-forks`).

## Names

- Everything is top-level, in one shared namespace, so no plain common word
  (`part`, `rule`, `item`) names a global. Qualify a top-level name by its
  owner or subject: `theme-`, `style-`, `window-`. An app in a sandbox has a
  namespace of its own, which stays there (`boids-step` in `apps/boids.ss`):
  the world holds only its launcher (`tests/sources.ss`).
- In `kits/` and `services/`, every name starts with its file's: `ui-…` in
  `kits/ui.ss`, `profile-…` in `services/profile.ss`; a record of the
  file's own name may give `make-x` and `x?` (`tests/sources.ss`).
- American spelling everywhere: code, comments, UI text, documents (color,
  gray, center, neighbor, labeled).

## Live redefinition

- Definitions are top-level, never in R6RS libraries, so the REPL can
  redefine any of them in the running world.
- A hook or a registry calls procedures by name, so a redefinition takes
  effect at the next call: `(lambda () (theme-file-save-soon!))`, not
  `theme-file-save-soon!` captured as a value.
- `(reload!)` of the tree into itself must keep working. It loads the
  world's files again; core0's change with a restart.

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
- **Mimicked styles** (Mac, Windows, Genera, the CADR, Interlisp, and in
  future CDE and Platinum) use the original's widgets. Where the original
  has none, make what its designers would have made. **Our own styles**
  (Cons, Curses, Draft, Fold, Halo, Lambda, Reticle, Slab, Spine) are free,
  as long as they stay coherent.
- Sources for mimicked styles:
  - GPL desktops (NsCDE, ZacOS 9): facts only (sizes, colors, rules), with
    references; copy no code, pixmaps, icons, fonts or backdrops.
  - MIT's CADR sources (BSD) and Medley Interlisp (MIT): use, and attribute.
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
