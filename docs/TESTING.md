# Testing

What a change must pass, and the rules tests follow, are in
[AGENTS.md](../AGENTS.md). This page says what each suite is, and how to
add a check.

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
  button of each style, asks an app's permissions, crashes windows and
  reloads the sources. It writes screenshots to `out/`.
- **units** runs every file of `tests/units/`, a topic each (an app's, a
  kit's, a service's, a part of the core's), in a process of its own, so
  that none leans on what another left behind. `scheme --script
  tests/units.ss out life boids` runs those two alone.
- **frame** draws frames on lavapipe, or on Metal on a Mac, with no window
  but one offscreen. It compares the screen bit for bit with the world
  drawn into an image, in every style and at several scales, and checks
  that every change shows on its frame and that nothing asked for draws
  no frame.
- **sources** checks the sources themselves: 80 columns, names, the
  layers and what crosses them, the core's budget, who may name a color.
  It runs in seconds.

They run headless and never open a real window. On Linux they need
lavapipe (`mesa-vulkan-drivers`), and the shaders' topic checks each
compiled shader with `spirv-val` (`sudo apt install spirv-tools`); without
it, or on a Mac, that check says it was skipped. On a Mac type `chez` for
`scheme`, and on Apple silicon put
`DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib` before it; the tests run on
Metal there, with no Dock icon and no window shown.

The suites never touch your `~/.schevana-theme.ss`, `~/.schevana.ss` or
`~/.schevana.d`: they point `*theme-file-path*` and `*grant-file-path*` at
files in `out/`. Run anything else of yours with `HOME` set to a scratch
folder.

## A check

A topic is a file in `tests/units/`, loaded into a world booted headless.
`tests/units.ss` gives it `check`, which runs an expression and reports
it, and helpers more than one topic uses: `(steps n)` runs the world's
loop `n` times, `(raises? thunk)` says whether a call raises, and
`shown-picture`, `image` and `max-diff` compare what was drawn.

```scheme no-run
(check "a window opens where it's asked"
       (let ([w (open-window "Here" 'pos '(40 . 60))])
         (steps 1)
         (let ([ok (and (= (window-x w) 40) (= (window-y w) 60))])
           (close-window! w)
           ok)))
```

A check's name says what is true when it passes, as a sentence.

## The docs' examples

The `docs` topic runs every `scheme` block of README.md, CREDITS.md and
`docs/*.md`, in order, as typed at a REPL at "/", each form in a process
as a REPL runs it, and each page in a world of its own. A comment `; =>
value` after a form, on its line or the next, is checked as what the form
returns, and an error, in a form, in what it left to run later or in a
window's handler, fails its block. A block fenced `scheme no-run`, like
the one above, is shown and not run: one that never ends, waits for a
person, or needs what only a test has.

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
