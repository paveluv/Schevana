# Schevana

![Schevana: a REPL and a Clock in the Spine style](docs/screenshot.png)

A Lisp Machine-style desktop that lives inside one window and is written
entirely in Chez Scheme. Every window, color, key binding, status-bar segment
and running process is a live Scheme value. You can inspect it, redefine it and
break it from a REPL that runs inside the world it changes.

The only C code involved is SDL3 (the window, input and the GPU),
FreeType and fontconfig (fonts), all called through Chez's FFI. There is no
build step: the whole
world compiles from source in about 0.8 s at startup, and again at each
`(reload!)`.

## Running

Schevana needs Chez Scheme 10, SDL 3.2 or later, FreeType, fontconfig, and
Vulkan on Linux or Metal on a Mac. On Debian 13:

```bash
sudo apt install libsdl3-0 mesa-vulkan-drivers
```

On a Mac:

```bash
brew install chezscheme sdl3 freetype fontconfig
```

Then, with no build step:

```bash
./schevana
```

The options, the files it reads and writes, and the details for each
platform are in [docs/INSTALL.md](docs/INSTALL.md).

| Key | Action |
| --- | --- |
| F1 / click "λ Schevana" / right-click desktop | launcher (type to filter); apps picked after a right-click open where you clicked |
| Ctrl+Tab | cycle windows |
| Ctrl+Shift+W / M / N / T / R | close / maximize / minimize / tile / new REPL |
| F11 | full screen on and off (also in the launcher) |
| F12 | screenshot to `~/schevana-N.png` |
| drag title, edges, corner; double-click title | move, resize, maximize |
| right-click title or taskbar button | window menu (incl. "Bind to `$w`") |

REPL: Enter evaluates when the form is complete (otherwise it inserts an
indented newline), Shift+Enter always adds a newline, Up/Down walk history,
Ctrl+C interrupts, Ctrl+L clears, Ctrl+V pastes. A form that runs a while
shows as the style has it: a spinner in place of its prompt (Genera's
turns `| / - \` and its who line says Run; the pointer over it says how
to stop it). Forms entered meanwhile wait under it (↳) and run in turn,
the spinner moving down to each; Backspace on an empty line takes the
last back, and Ctrl+C stops the running one and drops the rest.

Tab extends the name before the cursor to what the matches starting with
it share, and opens a list of the matches under the cursor that narrows
as you type: Up/Down choose, Tab and Shift+Tab go a page on or back,
Enter or a click takes one, Esc or a click elsewhere in the REPL closes
it, and so does a click on another window or the desktop, or anything
else that takes the keyboard from the REPL (a press on its title bar or
an empty part of a bar does not). With nothing to add, a popup says so:
the sole completion, with its description, or no completions; the next
key, text, click or wheel closes it. It offers what fits where the
cursor is: names bound in that REPL's environment; theme keys, apps,
palettes or styles after a quote in `(theme '…)`,
`(set-theme! '…)`, `(app-launch! '…)` and the like; file names inside a
string; library names inside `(import (…))`, a part at a time. Names
match as in the editor e: in segments, each starting where a part of the
name starts, in any order (`tdc` puts `text-draw-centered` first,
`winfind` `find-window`); fewer segments, in order, earlier, tighter and
shorter come first, ignoring case. The chosen one shows its argument
list and the `;;` comment above its definition (a library shows what it
exports), as the code that runs has them: the text each file had when it
was loaded, kept by the core, not the file as it is now; and for a
procedure, the definition its code was compiled from, so one redefined
at the REPL shows what was typed there (input is read with its places,
so errors in it say where too), and one `set!` to another procedure
what that one tells.

What each kind of REPL is, `(repl 'private)` and the others, and how
R6RS libraries are imported, is in [docs/REPL.md](docs/REPL.md).

**Environments**, `(envs)`, shows the tree: each environment's icon,
kind, how many names it was shared and holds, and its thread's jobs;
past a line you can drag, the one selected: kind, base, parent,
children, what it forks, its jobs (× stops one) and its names, shared
(the parent's name, read-only or through a setter, where bound) or its
own. Its toolbar and a row's right-press menu act on it:

- **Fork…**: a child of a kind it forks, named and shared names
  (suggested as you type; `now-ms as clock` renames, `size via
  size-set!` goes through a setter), optionally with a REPL in it.
- **REPL** (Return): a REPL in it.
- **Share…**: more of its parent's names, ticked in a dialog, each
  renamed or set through a setter (not into a thread's sandbox); the
  Fork sheet's Choose… picks there too.
- **Load…**: a file evaluated in it (`env-load`), picked in the
  desktop's file dialog, which stays above Environments while it waits
  (a style's `modal-above`).
- **Drop…**: it, what is under it and their threads.

On `/worklets` it sets the pool's threads. On an app's sandbox it lists
the bundles the app requests, as each stands (a press shows a bundle's
names), who decides them, and Permissions… to change them; `/apps` lists
every bundle. A world namespace gets the
names the world gains at its next evaluation; Sync shares them now
(`env-sync!`). An environment forks only the kinds its own allows,
through `(fork kind 'name n 'share names 'setters pairs)`: the world and
world namespaces every kind, a sandbox sandboxes and threads, the others
none; `(fork)` lists them.

## Things to try in the REPL

```scheme
(windows)                                  ; the window list, as data
(clock)                                    ; an app is a procedure
(move-window! (find-window 'clock) 40 60)
(set-theme! 'accent #xff9e64)              ; recolor everything
(set-style! 'cons)                         ; or: mac genera fold ...
; or: tokyo-night catppuccin nord gruvbox interlisp genera
(set-theme! 'palette 'paper)               ; remembered for cons
(open-window "Odd one out" 'window-style 'windows)   ; one in its own style
(set-theme! 'ui-font-size 15)              ; fonts and sizes are theme keys too
(override! 'ui-font-size 15)               ; ... in every style
(theme-source 'accent)                     ; which layer gives it
(set-theme! 'title-double-click 'shade)    ; a double click rolls a window up
(override! 'mouse-doc #t)                  ; what the buttons do, in the top bar
(add-status-segment! 'hi (lambda () (format "~a windows" (length (windows)))))
(bind-key! '(ctrl shift #\l) life)
; watch it in (monitor); Ctrl+C or kill!
(spawn "busy" (lambda () (let loop () (loop))))
(monitor)                                  ; where the time and memory go
(profile-on! #f)                            ; the profiler off (on at boot)
(profile-history! 60 30)                   ; a minute of ticks, 30 of seconds
(profile-totals (profile-seconds))         ; what each window, ... spent
(profile-flag-report)                      ; every late tick, and why
(debug-repl)                               ; a socket for what's outside
(tasks)                                    ; a task manager; tasks are data
(add-task! "Fix the menu" 'priority 'high 'tags '("ui"))   ; shows at once
(set-task! "Fix the" 'status 'review)      ; by title, id (27) or "TASK-27"
(set-task! 22 'blocked-by '(14 "TASK-24")) ; 22 waits for them; no cycles
(tasks-tree)                               ; what waits for what, nested
; in a task's description, Ctrl+E opens it in a window of its own
(tasks-list 'status 'doing 'assignee "Pavel")
(life)                                     ; Maximize it, Cell size to 1 px,
                                           ; Speed to every tick: see below
(boids)                                    ; a flock, its rules beside it
(repl "/apps/boids")                       ; a REPL in its sandbox; there,
(define boids-step-ms 100)                 ; a slow flock; (reload!) undoes
(boids3d)                                  ; a murmuration, all on the GPU;
                                           ; drag round it, h for its rules
(define (draw-wallpaper w h) (fill-gradient 0 0 w h #x102030 #x301020))
; every window looks focused; (reload!) undoes it
(define (draw-window win) (draw-window* win #t))
```

Define a new app and it appears in the launcher immediately:

```scheme
(define-app (counter) "Counter"
  (let ([n 0])
    (open-window "Counter" 'size '(240 . 100)
      'draw (lambda (win w h)
              (text-draw-centered 0 0 w h (number->string n) 'accent 'big))
      'mouse-down (lambda (win x y button clicks) (set! n (+ n 1))))))
```

## Monitor

`(monitor)`, or Monitor in the launcher, shows the world live, in two
tabs. Its first, Overview, redrawn twice a second, has the World's
facts in a grid (uptime, the screen, the ticks, the last tick, the last
frame, the process's memory, the heap, the style, apps, timers waiting, whether profiling is on, the
last error), then the windows in a table (a click focuses one, the
focused one selected) and the processes in another, each with its
state and a Kill button. Its second, Ticks, shows where the world's time
and memory go, as the profiler (`services/profile.ss`) measures them.
Each part of a tab is under a group's heading (the kit's `group`
label, at the rows' size).
The profiler runs whether Monitor is open or not, from boot, until
Monitor's Profiling or `(profile-on! #f)` turns it off: a step of 30 Life
windows costs about 1% more with it (`tests/bench.ss`), and it
allocates nothing. Its unit is a tick of the pacer's: the steps of
core1's loop (`schevana-step!`: the wait for core0's events, then events,
timers, a tick when due, processes, the frame and its upload) from the
one after a tick's to the next tick's, so that the steps that only
handle input between ticks sum into the tick they lead up to; a test's
steps, not paced, tick every one. It is level 1: Schevana's own
accounting, with nothing in an app's code instrumented.

The Ticks tab has three parts:

- **Ticks:** a bar a tick, all of its time since the last, stacked by
  phase: events, timers, processes, ticks, render, present, the
  collector, and the two waits, for input (the steps' wait for core0's
  events) and for the screen, in muted colors. A wait delays the next tick as much as work does, so
  both count. The work is at the bottom, the phase that spent the most
  over the graph lowest and first in the legend, and the waits above
  it, so that a bar past the top loses a wait, never work. A line marks
  the pacer's period (16.7 ms at 60 Hz, a refresh of the screen's by
  default) and the top is two. A tick that came late is flagged at the
  top: past one and a half periods, its wait for the screen left out
  (`profile-tick-late?`). That wait, with core0 on a thread of its own
  core1's wait for core0 to take its frame, is the screen's or core0's,
  which core1 can't shorten; past one and a half periods the tick was
  held instead, which the Pipeline shows in orange
  (`profile-tick-held?`). Not just past one, for a tick ends about at a
  refresh, a little before or after it, and one that missed a refresh
  waited for the next. All of it is whole ns and pixels, no float.
  Hover a bar for where its time went: its tick, how long it took and
  whether it came late and why, its phases and its three largest
  consumers; click it to pause there.
- **Consumers:** every window, surface (the desktop, the bars, the menu,
  the toasts) and process, and the collector, by milliseconds a second
  over the last 5 seconds, with the average and the longest a tick, the
  calls a second and a line of the last minute; hover a heading for
  what its column means. A window's row opens to
  its handlers (`draw`, `tick`, `key`, ...) and its frame, the style's
  drawing around the content; a surface's to its draw and its tick. A
  row selected shows its share of every bar; a second press lets it go. A
  window's name focuses it, and a process's Kill kills it. Two windows of one title are told
  apart by their ids (`Life (window 3)`); a window's row says once it
  is closed, a process's once it has ended.
- **Memory:** the heap, the bytes allocated a second and the collector's
  time a second, over the seconds kept.

Above them, Profiling turns the profiler on or off for the whole world
(`(profile-on! #f)`), Pause holds Monitor's view still (the profiler goes
on), Clear forgets the history, and two menus say how long the history
is: every tick of the last 30 seconds (at most 100 a second of them)
and each second's sums for the last 10 minutes, by default
(`(profile-history! 30 10)`). With profiling off, the tab says how to
turn it on.

The **Flags** tab keeps every late tick (the last 1,024 of them) long
after its bar has flowed past, the newest first: when it ended, what it
took, what made it late, what core0 said last before it and the ticks
about it; `(profile-flag-report)` prints the same. What made it late is
the biggest single thing in the tick that could have
(`profile-tick-why`) of what counts as late: a wait for events past its
period (asleep, or running in SDL), the collector or someone's work,
never what the screen held core0 for.

A row's tooltip says all that's known of it: for each tick about it, how
long it slept and worked and what the screen held core0 for; core0's
events for the 10 seconds before it; its
frame, core0's window's state, the windows and processes, its memory,
the machine's load and SDL's last error. `(profile-flag-log! path)`
adds each flag to the end of a file as it comes, to outlive a run; a run
from a checkout with a `.work` folder logs to `.work/flags.log`.

The profiler's history is data, read at a REPL as Monitor reads it:
[docs/MEASURING.md](docs/MEASURING.md). Monitor
draws all of it with the widget kit: its charts (`ui-bar-chart`,
`ui-draw-line-chart`, `ui-draw-sparkline`, `ui-draw-legend`), its tree,
its tables and its labels. A chart's series are the kit's color
settings `chart-1` to `chart-8`, from the palette's hues,
`chart-muted-1` and `chart-muted-2` for what is not work, and
`chart-mark`, `chart-share`, `chart-rule` and `chart-flag` its mark,
its share, its reference lines and a flag over a bar: Genera and the CADR, which have no color, give them as
stipples of ink.


## Your own apps, styles, palettes and wallpapers

Windows, apps, keys and timers are in [docs/WINDOWS.md](docs/WINDOWS.md);
themes, styles, palettes and wallpapers in [docs/LOOKS.md](docs/LOOKS.md);
keeping what you make in `~/.schevana.d/`, and apps in sandboxes, in
[docs/APPS.md](docs/APPS.md).

## Architecture

How the pieces work, from the boot chain to frames, the pacer and the
GPU, is in [docs/INTERNALS.md](docs/INTERNALS.md); drawing in
[docs/DRAWING.md](docs/DRAWING.md), and the widget kit in
[docs/UI.md](docs/UI.md). Still to move from here:

- **Pipeline shows all of this.** `(pipeline)` puts the way from a window's
  draw to the screen on one screen, reading through `kits/inspect.ss`, plain
  data that a REPL or a test can read too: the frame's list by who drew it,
  each record decoded in draw order and a run of glyphs as its text, and
  each drawer with a checkbox that leaves it out of the small screen and the
  Tape (the core's preview takes a cut of the frame's runs), and the lists
  it drew from, each with how many records it holds; Who, what each
  drawer cost, a row each in draw order or sorted by any column: core1's time
  drawing it a frame, its records, the pixels they may touch, the runs they
  start and how many changed since the frame before, each with a bar for its
  share, and in how many of the frames kept it was recorded again, and of
  those how many recorded the very same records, work for nothing, each
  with a mark a frame; Course,
  a tick's stages in order, each as wide as its time, render split into
  each drawer's draw and the rest; Inside, the record selected decoded, its
  words, the list it's in (whose, which version, its place there, when and
  in how long it was recorded) and its run, and its shader's source with its
  helpers written out;
  Memory, what the GPU holds as bars, and the glyphs' atlas live; the
  screen small, drawn again every tick unless told otherwise and showing
  itself in its own box, a tick older each time round, with what's selected
  outlined, or showing who drew each record, in its drawer's color, the
  others dim while one's selected, or its records' kinds, or heat (a pixel
  as bright as how many records cover it), or what changed since the frame
  before, and a press there listing what may touch
  that pixel; the wheel
  zooms it at the pointer, a drag moves it, Fit and 100% set it, a loupe
  magnifies the pixels at the pointer and names the record on top there,
  and Pop out puts it in a window of its own kept above the Pipeline, back
  in its place when that window closes. Under them
  the Tape: a mark a record in draw order, as tall as what it may cover, and
  in lanes who drew it and its kind; a press or its stepper holds the frame
  and draws it as far as that record, Play draws it record by record over a
  few seconds, and what's selected in the list, or at a pixel, is marked on
  it and named on its heading, with Clear (or Esc). A record selected opens
  its drawer in the tree and stays with its drawer, at its place in it, as
  the frame changes, and a drawer keeps its color, whatever its place, while
  the Pipeline is open. Below, the River flows, a column a refresh of the
  screen's (its own count where Wayland reports, else estimated on the
  clock), the newest at the right: the refresh before the one the frame
  being drawn will show at, should frames keep coming a refresh apart. So
  the River moves a column a frame however late the screen's word comes,
  and jumps only with a frame that came late. Its columns are whole
  pixels, all as wide. The newest frames are on their way, each under the
  refresh it's meant for, drawn as far as they've gone, ready up to the
  latch they should make and the compositor's from there. A column's
  bar is the frame on the
  screen at that refresh, a tail hanging from zero, its showing, down its
  way back: the compositor, ready to the latch, the GPU, core0, the box,
  core1, and under the tick its input's way, from the compositor's time to
  SDL's stamp, to core0's pump and to core1's tick; a rule a refresh. Shown
  again while the next frame was late, the time since is red, at the top;
  with nothing due, the column is empty. Over the bars the screen's word on
  each refresh, green where a new frame showed, red where one repeated
  while the next was late (or, by VSync, a frame was dropped), orange where
  one was dropped by a mode that drops, a pip where its count and its times
  disagree on how far a frame came after the one before (the columns go by
  the count, now by the times). Over that lane, rising to it, core1's
  ticks by Monitor's phases, in the same columns, by a choice in its
  heading: "Ticks when they ran", those whose work began in that refresh,
  or "Each over its frame", the one that drew the frame new there; over
  them, a tick that came late and a collection that ran. Its heading says
  whether it's live: "Live", or held, at which frame, with the way back
  (the kit's `ui-live-badge`); a press there holds it or lets it go, as
  Esc does. A press on a bar holds it and goes back to the frame on the
  screen at that refresh, the whole app showing it, and a drag moves
  through them: the last 300 frames are kept while it's open, each the
  screen's own records and copies of the lists it showed, a list the same
  as in the frame before the same copy, the images and paints they showed
  drawn again as they are now (the River's rows are kept by refresh, so
  its bands come back as they were), and left out once they're let go of.
  While it flows it asks for a frame a tick, and says what that takes;
  closed, what's left of it is the core's few numbers a frame.

## Tests

```bash
mkdir -p out
scheme --script tests/smoke.ss out
scheme --script tests/units.ss out
scheme --script tests/frame.ss out
scheme --script tests/sources.ss
```

What each suite covers, how to add a check, and the bench are in
[docs/TESTING.md](docs/TESTING.md).

## Conventions

- Every line of every source file is at most 80 characters;
  `tests/sources.ss` checks it.
- American spelling: color, gray, center.

## Credits

What Schevana takes from others, and under which terms, is in
[CREDITS.md](CREDITS.md).

## Known gaps and open questions

- Every start and `(reload!)` compiles the whole tree again, about 0.8 s,
  nearly all of it the compiler's: load time grows with the source, about
  0.63 ms a KB. Loading compiled files takes about 0.1 s, were there a cache
  of them.
- An app in a sandbox keeps no files and writes only to its log (`env-log`):
  the bundles for files and the console are still to come. Environments opens
  a REPL in its sandbox; its window's menu does not yet.
- A frame draws everything under its rectangle on core1. The
  rectangle is one bounding box (the top bar's clock and a window near
  the bottom make a frame of all between them) and grows to hold whole
  every window it touches, so overlapping windows are drawn again with
  one another, and while a toast or a menu shows every frame is the
  whole screen. Windows whose extent reaches into the top bar, as tiled
  ones do, are drawn again with the clock every second. With 30 animating
  Life windows, tiled, a frame takes about 3.8 ms at 100% and 8 ms at 200%;
  30 overlapping at 200%, each with its panel, take about 58 ms a frame,
  and a keystroke in a REPL among four other windows shows about 16 ms
  later at 200%. A REPL alone shows it 2.3 ms
  later (2.8 ms on a 4K screen), and the clock's second on an empty 4K
  screen takes 0.1 ms (`tests/bench.ss`). Meanwhile a busy REPL
  evaluation runs only between frames: with 30 Life windows animating
  at 200% it gets about half of what it gets with them paused. Next on
  the compositor plan: each window drawn into an image of its own, only
  when it changes, and the images composed on the CPU, then on the GPU.
- Every theme change paints the wallpaper again: a theme change takes
  about 27 ms at 100% and 88 ms at 200% until its frame is drawn, so
  dragging a color slider in Settings shows about 11 frames a second at
  200%.
- The built-in styles change mostly the windows (Genera and the CADR
  every widget too, Interlisp its scroll bars), though everything is a
  part a style may replace: each widget's drawing, size and areas, the
  bars, menus, toasts, the popups' panel, highlight, separator and card.
  Under Genera and the CADR a tooltip still floats in its box (the
  machines said it in the who line's documentation line, which shows
  only what the mouse buttons do), and a dropdown's menu still ticks
  the current choice.
  Settings draws with the kit's widgets and only its own pictures with
  its own code (the styles' miniatures, swatches, color tracks); its
  color list and its pane's scrolling are still its own. The
  "stable GUI API" question stays open: keep growing these immediate-mode
  procedures, or describe retained widget trees as data?
- Tasks redraws its whole window for a keystroke: about 11 ms on a 4K
  screen at 200%, maximized (half of it is any maximized window's frame:
  the wallpaper under it, its rows compared). In a description of 65,536
  characters a keystroke costs within a millisecond of that: a text's
  rows are computed only as far as they show, and kept; after an edit,
  those past it are taken back from before it, and the edit says where
  the text changed, so no keystroke looks at the whole text (the text
  and its rows' starts are still copied, by memcpy: about 0.02 ms at 64k
  characters). Only rows that do change are measured again, all those in
  view when an edit moves every row's break (a paragraph with no spaces,
  or rows exactly full). A jump far ahead (Ctrl+End, the scroll bar's
  thumb, a paste of the whole text) computes the rows to there once, 5
  to 8 ms; idle steps compute the rest for the scroll bar, a millisecond
  at a time. The description's editor, maximized, draws Tasks under it
  too, and a screenful of text: about 4 ms more a keystroke. With a
  search, Tasks looks through a task's texts only when they change:
  typing in a long description searches that one again at each keystroke
  (0.2 ms a word at 64k).
- Tasks keeps what it works out from which tasks there are, their
  order, statuses and links (the board order, whom each blocks, the
  Tree's shape and rows) until one of those changes, so typing costs
  nothing for them; it still passes over every task at each draw for
  its filters, the toolbar's names and tags, and the List's and Tree's
  assignee column, which measures every name, and the Board lays out
  every card of a column: with 2,000 tasks more in chains of 50, a
  keystroke in the List or the Tree costs within a millisecond of what
  it costs with the seed, in the Board about 6 ms more (with 8,000, 2
  and 18 ms more). Text cut to fit (a title, a tooltip, a menu entry)
  measures no more of it than its room could show. The details' Add
  shows the best matches that fit on the screen, then how many more:
  typing narrows them.
- The description's editor asks before Escape or Cancel drops changes,
  but its window's close button drops them without asking: the window
  manager closes a window at once and cannot ask it first.
- REPL lacks selection and copy, and there is no text editor app yet:
  the edit kit and Tasks' description editor are its start (undo, find
  and files come next).
- No persistence. Windows and state vanish on exit (`fasl-write` of app
  state is a natural first step).
- Portability: it runs on Linux and on a Mac. The library names for Windows
  are in `src/core0/ffi.ss` and `src/core1/ffi.ss` but have not been
  tried.
