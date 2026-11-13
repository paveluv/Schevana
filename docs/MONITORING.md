# Monitoring

Where the world's time and memory go is data, kept from boot. Two apps
draw it, Monitor and the Pipeline, and a REPL or a test reads the same.
The apps explain themselves: hover anything in them for what it means.

## Monitor

`(monitor)` shows the world live, in four tabs:

- **Overview**: the world's facts (uptime, the screen, the last tick and
  frame, memory, the style, the last error), the windows, and the
  processes, each with a Kill button.
- **Ticks**: a bar a tick, its time stacked by phase, a late one flagged;
  who spent it, by window, surface and process; and the memory.
- **Flags**: every tick that came late, what made it late, and all that's
  known of the moment.
- **Platform**: this machine's stack, and a button that copies the run as
  a row of [PLATFORMS.md](PLATFORMS.md).

## The Pipeline

`(pipeline)` shows the way from a window's draw procedure to the screen,
for the frame on the screen or one held: the frame's records by who drew
them and what each cost; a tick's stages in order; a record decoded, with
its list, its run and its shader's source; what the GPU holds; the screen
small, colored by who drew, kind, heat or change, with a loupe; the Tape,
the records in draw order, to step or play through; and the River, a
column a refresh of the screen's, each frame's way back from its showing
to its input. A press on the River goes back to that frame, and Esc lets
it go.

## The profiler

The profiler is on from boot and allocates nothing; a step of 30 Life
windows costs about 1% more with it. Its unit is a tick: the steps of
core1's loop from one frame turn to the next, so that the steps that only
handle input between frames add up into the tick they lead to.

```scheme
(profile-on?)                              ; => #t
(life)
(sleep-ms 200)
(define tick (car (profile-ticks)))        ; the newest first
(profile-tick-ms tick)                     ; how long it took, ms
(profile-tick-phases tick)                 ; where it went: ((render . ns) ...)
(profile-tick-uses tick)                   ; who spent it
(profile-totals (profile-ticks) #t)        ; who spent the ticks kept, the most first
```

A tick's phases are events, timers, processes, ticks, render, present, the
collector, and the two waits, for input and for the screen; a wait delays
the next tick as much as work does, so both count. A use is what one key
spent: a window's handler, a surface's draw, a process's turn.
`(profile-seconds)` gives each second's sums, as `(profile-ticks)` gives
the ticks, and `profile-totals` sums either.

```scheme
(pacer-period)                             ; a refresh, in ns
(profile-slow-ticks)                       ; the ticks that came late
(map profile-tick-phases (profile-slow-ticks))
(profile-totals (profile-slow-ticks) #t)   ; who spent them
(profile-tick-ref tick 'heap)              ; the heap at its end, bytes
```

A tick came late if it took over one and a half periods, its wait for the
screen left out. Each is flagged, with what made it late, what core0 said
last before it and the ticks around it: `(profile-flag-report)` prints the
last 1,024 of them, and `(profile-flag-log! path)` adds each to a file as
it comes, to outlive a run.

```scheme
(profile-history! 60 30)                   ; a minute of ticks, 30 of seconds
(profile-on! #f)                           ; off: a step costs what it did
(profile-on! #t)
```

## Inside the frame

`kits/inspect.ss` reads what the core keeps about frames, the GPU and the
platform, as plain data, which the Pipeline draws.

```scheme
(inspect-platform)                         ; the OS, CPU, Chez, the display
(inspect-pacer)                            ; when frames are due
(inspect-core0)                            ; core0's side: sizes, jobs, events
(inspect-gpu-held)                         ; what the GPU holds
```

## From outside

`(debug-repl)` opens a window that lets something outside Schevana, a
debugger or an agent, evaluate Scheme in the running world, and shows each
request and answer as they come. The window is the switch: the socket
exists only while it's open, at `$XDG_RUNTIME_DIR/schevana-debug.sock`,
for its owner alone.

```scheme no-run
(debug-repl)
```

One connection is one request: send the forms as text and stop writing.
The answer comes back as one datum, and the connection closes:

```bash
printf '(+ 1 2)' | nc -UN "$XDG_RUNTIME_DIR/schevana-debug.sock"
```

```
(ok "what it printed" ("a value, as text" ...) ms)
(error "what went wrong" "what it printed" ms)
(killed "what it printed" ms)
```

A request runs as a process, so a long one doesn't hold the world up, and
one past 10 seconds is stopped. It has all the power of the world's own
REPL.
