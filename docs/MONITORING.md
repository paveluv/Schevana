# Monitoring

Where the world's time and memory go is kept as data from boot on. Two
apps draw it, Monitor and the Pipeline, and a REPL or a test can read the
same data. The apps explain themselves: hover over anything in them to
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
frame. `held` counts the requests that were held off before it (a frame
turn holds collections till its frame is out), and `span` is what was
running when it was asked for. The log goes with the profiler: off,
nothing is logged.

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
