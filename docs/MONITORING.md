# Monitoring

Where the world's time and memory go is kept as data from boot on. Three
apps draw it, Monitor, the Pipeline and Allocations, and a REPL or a test
can read the same data. The apps explain themselves: hover over anything in them to
see what it means.

## Monitor

`(monitor)` shows the world live, in four tabs:

- **Overview**: the world's facts (uptime, the screen, the last tick and
  frame, memory, the style, the last error), the windows, and the
  processes, each with a Kill button.
- **Ticks**: a bar for each tick, its time stacked by phase, with late
  ticks flagged; who spent the time and who allocated, by window, surface
  and process; and the memory.
- **Flags**: every late tick the profiler kept, what made it late, and
  everything known about that moment.
- **Platform**: this machine's stack, and a button that copies the run as
  a row of [PLATFORMS.md](PLATFORMS.md).

## The Pipeline

`(pipeline)` shows the way from a window's draw procedure to the screen,
for the frame on the screen or for one it holds. It shows the frame's
records by who drew them and what each cost; a tick's stages in order; a
record decoded, with its list, its run and its shader's source; what the
GPU holds; the screen in small, colored by who drew each part, by kind, by
heat or by change, with a loupe; the Tape, the records in draw order, to
step or play through; and the River, a column for each refresh of the
screen, which shows each frame's way from its input to its showing. A
press on the River goes back to that frame, and Esc lets it go again
(after clearing the selection, if there is one).

## Allocations

`(allocations)` shows what the heap is doing:

- **The Column**, at the right: the generations as strata, the young one
  at the top and the oldest at the bottom, each as thick as the root of
  its bytes. The young generation is a tank that fills to the line at
  which the collector is asked; it says "held" while a frame turn holds
  its collection off.
- **The Flow**, along the bottom: a bar for each tick, as tall as what the
  tick allocated, banded by who (windows, processes, surfaces, and the
  loop and the rest). Over it, three strips: each collection, the stronger
  the longer its pause; each request that was held off; each tick that
  came late. A press holds the app at that tick.
- **Who**: the windows, surfaces and processes by what they allocated,
  a second and a tick, over the last two seconds. A row pressed shows as
  its share of each bar of the Flow.
- **Where**: which procedures allocate, from the tap's samples. At the
  top a flame: a span (a window and its part, a surface), and under it the
  procedures from the callers in, each box as wide as its bytes; a press
  on a box makes it the whole width, and a press on the top box goes back
  out. Under it the procedures by what their samples come down to (Own,
  Self, Total, as `(allocation-places)` has them). A row pressed shows
  its source, the procedure's first line marked.
- **Collections**: the log, the newest first: the pass, the pause, what
  was allocated since the collection before and what of it was kept, how
  long its request was held off, which thread performed it, and who asked.
  A row pressed shows what each generation held before and after.

While the window is open the tap records (the Record box), so that
`(allocation-report)` has something to say.

## The profiler

The profiler is on from boot and allocates nothing; with it on, a step of
30 Life windows costs about 1% more. Its unit is a tick: the steps of
core1's loop from one frame turn to the next, so that the steps that only
handle input between frames are summed into the tick they lead up to.

```scheme
(profile-on?)                              ; => #t
(life)
(sleep-ms 200)
(define tick (car (profile-ticks)))        ; the newest first
(profile-tick-ms tick)                     ; how long it took, ms
(profile-tick-phases tick)                 ; where it went: ((render . ns) ...)
(profile-tick-uses tick)                   ; who spent it
(profile-totals (profile-ticks) #t)        ; who spent the ticks kept, the most first
(map profile-use-bytes (profile-tick-uses tick))   ; what each allocated
(map profile-total-bytes (profile-totals (profile-ticks) #t))
```

A tick's phases are events, timers, processes, ticks, render, the
collector, other, and the two waits, for input and for the screen; a wait
delays the next tick as much as work does, so both count. A use is what
one key spent: a window's handler, a surface's draw, or a process's turn.
`(profile-seconds)` gives each second's sums, as `(profile-ticks)` gives
the ticks, and `profile-totals` sums either list. A use's bytes are its
own, as its time is: what was allocated while it ran, less what the uses
inside it allocated. They are exact while core1 is the only thread that
allocates; another thread's bytes come in 16 KB at a time.

```scheme
(pacer-period)                             ; a refresh, in ns
(profile-slow-ticks)                       ; the ticks that came late
(map profile-tick-phases (profile-slow-ticks))
(profile-totals (profile-slow-ticks) #t)   ; who spent them
(profile-tick-ref tick 'heap)              ; the heap at its end, bytes
```

A tick came late if it took more than one and a half periods, not
counting its wait for the screen. Each late tick is flagged, with what
made it late, what core0 said last before it, and the ticks around it:
`(profile-flag-report)` prints the last 1,024 flags, and
`(profile-flag-log! path)` appends each flag to a file as it comes, so
that the flags outlive the run.

```scheme
(profile-history! 60 30)                   ; a minute of ticks, 30 of seconds
(profile-on! #f)                           ; off: a step costs what it did
(profile-on! #t)
```

## Collections

Every collection is logged as it runs, into a ring of the last 4,096:
which of the collector's passes it was, how long it paused the world,
what each generation held before and after, and what survived.

```scheme
(allocation-clock)                         ; bytes allocated so far
(length (allocation-collections))          ; the collections kept, by seq
(allocation-collection)                    ; all that is known of the last
(cdr (assq 'pause (allocation-collection)))   ; its pause, ns
```

`pass` is `young` (generation 0 into 1, when 2 MB has been allocated),
`middle` (1 into 2) or `old` (3 into itself), both run while nobody is
typing, or `settle` (all into 4, at boot and after a reload). `allocated`
is what was allocated since the collection before, and `survived` what
this one kept of it: almost none of a frame's bytes should outlive the
frame. `held` counts the requests that were held off before it: a frame
turn holds collections till its frame is out, and Chez asks once in such
a turn, since a request held off moves the trip out of reach until the
collection that the turn owes. `span` is what was running when it was
asked for, `(gc . #f)` when the collector asked for it itself (after a
frame turn, or for an older pass). `thread` is the thread that performed
it, which Chez picks: core0, whenever core0 is running Scheme then.

`loose` says that another thread performed it while a span other than the
collector's was open. Each thread reads the allocation clock a little
apart (by what it holds in the segments it is filling), and a collection
keeps the clock level only for the thread that performs it. So the bytes
of that span are off by some KB, either way. A collection that the
collector asks for is never loose: the step goes to `gc`.

The log goes with the profiler: off, nothing is logged.

## Which procedure allocates

The profiler's bytes say who allocates: a window, a surface, a process.
The tap says where: it samples core1's stack every 64 KB allocated or
so, and adds each sample's bytes to the path of calls it found, under the
span that was open.

```scheme
(allocation-record! #t)                    ; a sample every 64 KB or so
(length (allocation-collections))          ; anything that allocates
(allocation-record! #f)
(allocation-recording?)                    ; #f again
(allocation-report)                        ; the 20 that allocate most
(allocation-sampled)                       ; samples, their bytes, unseen
(length (allocation-places))               ; every procedure sampled
(car (allocation-paths))                   ; the tree's root: #f
(allocation-clear!)                        ; forget the samples
```

`(allocation-record! #t (* 16 1024))` samples every 16 KB or so, which
is the least: Chez counts what was allocated only as a thread takes a
16 KB segment. Samples add up over recordings until
`(allocation-clear!)`.

A row of `(allocation-places)` is a procedure: its `name`, `file` and
`line`, and three counts of bytes. `self` is for the samples whose
innermost frame it is. `own` is for those where it is the innermost
frame that has a source: when the innermost frames are Chez's (a
`format`, a hash table), `own` names the place in a program's code that
the sample comes down to, and the report sorts by it. `total` is for
every sample that has it anywhere in its path.

`(allocation-paths)` gives the tree: a node is its name (a span, as
`(span key . part)`, or a procedure, as `(name file line)`), its own
bytes, its bytes with its children's, its samples, and its children, the
heaviest first.

What to know when reading it:

- A sample's bytes are measured, not assumed: what the allocation clock
  moved since the sample before. So the shares are right whatever the
  stride did, and the samples add up to what was allocated, less the
  bytes that no sample saw (`unseen`: those just before a collection that
  the collector asked for).
- The stack is read when the thread next looks for requests, shortly
  after the allocation that a stride ended in. The callers are right; the
  innermost frame can be a neighbor of the one that allocated. Under
  Chez 10.0.0 a thread looks only every 1,000 calls or loop turns, so
  samples are fewer and each stands for more.
- Chez has core0 take a request whenever core0 is running Scheme at that
  moment. core1's stack is out of sight then, and the sample's bytes stay
  with the span, with no path.
- Past 500 samples a second the stride doubles, and it comes back once
  they come slower.
- The tap rides the profiler's handler, so it records only while the
  profiler is on. A sample costs a few hundred bytes (the stack's
  continuation), which no sample's weight includes.

## Inside the frame

`schevana/kits/inspect.sls` reads what the core keeps about frames, the
GPU, the platform and what loads, and returns it as plain data, which the
Pipeline draws.

```scheme
(inspect-platform)                         ; the OS, CPU, Chez, the display
(inspect-pacer)                            ; when frames are due
(inspect-pacer2)                           ; the second pacer's state
(inspect-pacer-rows)                       ; the rows it reads
(inspect-core0)                            ; core0's side: sizes, jobs, events
(inspect-gpu-held)                         ; what the GPU holds
(inspect-list-tree)                        ; the lists the last frame shows
(inspect-recordings #f)                    ; what frames are drawn from
(inspect-reload)                           ; what the last reload evaluated
(inspect-auto-loads)                       ; what loads with the world
(inspect-world-later)                      ; what still waits to load
```

## From outside

`(debug-repl)` opens a window that lets something outside Schevana, such
as a debugger or an agent, evaluate Scheme in the running world, and
shows each request and answer as they come (select them with the mouse,
and Ctrl+C or a right click copies them). The window is the switch:
the socket exists only while the window is open, at
`$XDG_RUNTIME_DIR/schevana-debug.sock`, and only its owner can use it.

```scheme no-run
(debug-repl)
```

One connection carries one request: send the forms as text and stop
writing. The answer comes back as one datum, and the connection closes:

```bash
printf '(+ 1 2)' | nc -UN "$XDG_RUNTIME_DIR/schevana-debug.sock"
```

```
(ok "what it printed" ("a value, as text" ...) ms)
(error "what went wrong" "what it printed" ms)
(killed "what it printed" ms)
```

A request runs as a process, so a long one doesn't hold the world up, and
one that runs past 10 seconds is stopped. It has all the power of the
world's own REPL.
