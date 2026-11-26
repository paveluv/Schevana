# Chez

Schevana is written for Chez Scheme, and most of what it uses is in Chez's
guide (the CSUG) and stays put from version to version. This file keeps the
rest: the places where the tree leans on something Chez doesn't promise,
and which another version may change. Each says what is leaned on, where,
what goes wrong if it changes, and which check would show it.

The suites run under two versions, 10.0.0 and 10.4.1 (`AGENTS.md`), so an
entry here is known to hold in both.

## How to add to it

Add an entry when code or a test leans on any of these:

- a procedure Chez keeps for itself: one named with a `$`, reached by
  `#%$name` or, in a library, by `($primitive $name)`;
- the shape of what Chez gives back as data: `expand`'s output, the
  printer's text for an object;
- the text of one of Chez's own messages or names (an error's words, the
  version string, a procedure's name in a stack);
- something a version counts or does in its own way (an engine's ticks,
  bytes allocated, when a thread sees a request);
- a flaw of Chez's that the tree works around.

Write what the tree expects, where, and what happens if Chez changes it.
Then name the check that fails when it does, and add one if there is none:
a dependency no check holds is found by a person, later. Try it under both
versions before writing "holds".

What Chez documents needs no entry, however unusual: continuations,
engines, `collect-request-handler`, `collect-trip-bytes`, weak tables
keeping their values. A comment where it is used says so.

## What the tree leans on

### A continuation's stack, read in place

- **Expected:** the frames of a continuation can be read without being
  split off: `$continuation?`, `$null-continuation`,
  `$continuation-return-code` and `$continuation-return-frame-words` for
  the frame at the top, `$continuation-stack-clength`,
  `$continuation-stack-return-code` and
  `$continuation-stack-return-frame-words` for those under it by their
  offset, and `$continuation-link` for the next stack segment. Each
  frame's return code is the code object of the procedure that the frame
  returns into.
- **Where:** `allocation-walk!` in `schevana/services/allocation.sls`,
  the allocation tap's walk of core1's stack at a sample.
- **Why:** a sample is taken a few hundred times a second, inside the
  collect-request handler. The inspector's walk of the same stack
  allocates 64 bytes a frame (305 KB with sources, measured); this one
  allocates nothing and takes about half a microsecond for 45 frames.
- **If it changes:** a sample's path is wrong or empty, or the walk
  raises inside the handler.
- **Held by:** `tests/units/tap.ss`, "a sample's path is the callers from
  the outermost in ...", and "two procedures that allocate three to one
  ...", whose shares come from the innermost frames.

### The frames on the way into a collect-request handler

- **Expected:** between the handler's own frames and the code that a
  request interrupted lie only frames of Chez's whose code is named
  `dynamic-wind` or `enable-interrupts` (`$code-name`).
- **Where:** `allocation-way-in` in `schevana/services/allocation.sls`:
  the walk leaves out the frames of these names at the stack's top, with
  the handler's own.
- **If it changes:** every sample's innermost frame is one of Chez's, so
  `self` names it and not the code that allocated.
- **Held by:** `tests/units/tap.ss`, "a sample's path ...", which asks
  that no sample ends at a frame of the way in, and "two procedures that
  allocate three to one ...", whose procedures must be innermost.

### A code object's name and source

- **Expected:** `$code-name` gives a procedure's name as a string, or
  `#f`; and the inspector's object for a code object answers
  `source-path` with a path, a line and a character, with a path and a
  position when the file has changed, or with nothing when the code has
  no source.
- **Where:** `allocation-place` in `schevana/services/allocation.sls`,
  asked once for each code object and kept.
- **If it changes:** the tap's rows have no name, file or line.
- **Held by:** `tests/units/tap.ss`, "a procedure of the tree's is named
  with its file and line ...".

### When Chez asks for a collection

- **Expected:** Chez calls the collect-request handler when the young
  generation has grown by `collect-trip-bytes` since the last collection.
  It counts that growth only as a thread takes a 16 KB segment, and asks
  again at each segment taken while the growth stays past the trip. The
  trip can be set at any time, to any fixnum, from any thread.
- **Where:** `collector-collect!` in `schevana/core/loop.sls`: a request
  held off moves the trip out of reach, so that a frame turn is asked
  once and not at each segment after. And the tap's alarm,
  `allocation-request!` in `schevana/services/allocation.sls`: the trip
  set a stride ahead of the growth makes Chez ask at the bytes chosen.
- **If it changes:** a turn that holds collections off is asked many
  times again (a thousand for 16 MB), or the tap's samples come at other
  distances than asked. The bytes of the samples stay right: they are
  measured.
- **Held by:** `tests/units/collector.ss`, "a frame turn that allocates
  many times the trip holds one request off ..."; `tests/units/tap.ss`,
  "two procedures that allocate three to one ..." (the number of samples)
  and "with the tap on, collections come when they would ...".

### When a thread sees a request

- **Expected:** a request is seen at the thread's next look for one: at
  once under 10.4.1, and when its count of calls and loop turns runs out
  under 10.0.0, up to 1,000 of them later (megabytes later, when each
  turn allocates much through Chez's C code).
- **Where:** the tap counts the young generation's growth by the
  allocation clock, not by the strides it asked for, so that the
  collector is asked when it would be, however late a request is seen.
- **If it changes:** nothing breaks; under a Chez that sees requests
  late, samples are fewer and each stands for more bytes.
- **Held by:** `tests/units/tap.ss`, "with the tap on, collections come
  when they would, also where a request is seen late ...".

### Which thread runs the collect-request handler

- **Expected:** with several threads, the process's first thread runs
  the handler whenever it is running Scheme then; otherwise the thread
  that asked. Every other thread running Scheme waits while it runs.
- **Where:** the profiler's handler, `profile-collect` in
  `schevana/services/profile.sls`, and what it calls, and the census's,
  `allocation-census-collect!` in `schevana/services/allocation.sls`:
  they write the profiler's and the allocation service's state from
  whichever thread that is, and the tap walks the stack only on core1.
  The census counts the heap there because Chez counts only while one
  thread is active.
- **If it changes:** if threads did not wait, that state would be written
  by two threads at once.
- **Held by:** no check of its own. `tests/units/profile.ss`, "when
  another thread performs a collection ...", holds what the handler does
  when it is not on core1, with that thread stood in for.

### A generation's bytes, and the clock, on another thread

- **Expected (a flaw):** `(bytes-allocated g)` leaves out what other
  threads hold in the segments they are still filling. So on a thread
  that did not do all of the last collection's work, a generation can
  read under 0, which comes back as a number near 2^64; and
  `(+ (bytes-allocated) (bytes-deallocated))` steps across a collection
  that another thread performs, by some KB either way. A fix is prepared
  for upstream; with it the step is smaller and steady, not gone.
- **Where:** `collector-generation-bytes` in `schevana/core/loop.sls`
  takes a reading that is no fixnum as 0, for the collector's policy and
  the log of collections. `collector-rendezvous!` there opens a span of
  the collector's own around each collection the collector asks for,
  which takes the clock's step; the log marks any other collection that
  another thread performed as `loose`.
- **If it changes:** with the flaw gone the guard never fires; nothing
  else changes.
- **Held by:** `tests/units/collector.ss`, "a generation that Chez reads
  under 0 is 0 to the collector", which runs a second thread and prints
  what Chez read; `tests/units/profile.ss`, "when another thread
  performs a collection that the collector asked for ...".

### A state's value, by its symbol

- **Expected:** `$top-level-value`, `$set-top-level-value!` and
  `$top-level-bound?` read, set and ask for the value that a symbol holds
  as a global of Chez's own, outside any environment. A symbol made by
  `gensym` with a name of its own is in `(oblist)` once a fasl file or
  `gensym->unique-string` has named it.
- **Where:** `define-global` in `schevana/base.sls`, which keeps every
  state and made value of a library under such a symbol, its states
  under the name "schevana-state", their file and their own name; and
  `allocation-census-states` in `schevana/services/allocation.sls`, which
  finds a census's states by those names in `(oblist)` and reads their
  values.
- **If it changes:** a library's states don't keep their values across a
  reload, or the census finds no state, and the code and names take them.
- **Held by:** `tests/units/reload.ss`, "a library whose file changed is
  evaluated again ...", which asks for the state as it was;
  `tests/units/census.ss`, "a library's state is charged to its library,
  under its layer".

### In the tests only

- `tests/frame.ss` reads a thread's count of disabled interrupts,
  `(#%$tc-field 'disable-count (#%$tc))`, to switch threads only where an
  interrupt could come. If the field goes, the suite's form raises.
- `tests/units/threads.ss` names `#%$top-level-value` as one of the
  things a worklet is refused. If the name goes, that worklet is refused
  for another reason, and the check still passes.
