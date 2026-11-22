# Threads: worklets, the crew and vats

The world lives on one thread, core1, and only core1 writes the world's
state: the windows, the theme, every global. Nothing needs a lock,
because no other thread may write that state. Work goes to other threads
in two forms that can't break this rule: worklets, which touch only what
they are handed, and vats, which are threads with a sandbox of their own.

On core1 itself, long work runs as a process ([WINDOWS.md](WINDOWS.md)):
a process runs a slice at a time between frames, so even an endless loop
never freezes the desktop. A window's handler runs with a time budget,
and a handler that runs past it or raises an error crashes only its own
window.

## Worklets

A worklet is a procedure compiled in an environment where the world
can't be reached. All it can name is Scheme's pure core, fixnums,
flonums, bytevectors, vectors of numbers (fxvectors and flvectors),
boxes, the clock (`now-ns`), and the other worklets. A worklet that names
anything else is refused when it is defined.

```scheme
(define-worklet (square x) (fx* x x))
(square 7)                                 ; => 49
(guard (c [#t #f]) (worklet (x) (open-window x)))   ; => #f
```

`worklet` is to `define-worklet` what `lambda` is to `define`. Worklets
call each other by name, so each one sees the others' redefinitions. Of
what it is handed, a worklet can look inside only plain data (pairs,
vectors and boxes), never a record, and the threads refuse to hand it any
procedure that isn't a worklet.

## The crew

The crew is a set of worker threads for loops. `crew-for` calls a
worklet on disjoint slices of a range, with the caller doing a share of
the work too, and returns when every call has returned.

```scheme
(crew-map square '(1 2 3))                 ; => (1 4 9)
(define bytes (make-bytevector 8 0))
(define-worklet (fill-slice lo hi bv)
  (do ([i lo (fx+ i 1)]) ((fx= i hi)) (bytevector-u8-set! bv i i)))
(crew-for 0 8 fill-slice bytes)
bytes                                      ; => #vu8(0 1 2 3 4 5 6 7)
```

A call should write only its own slice and allocate nothing, since
allocation stops every thread. Each call should take 20 to 200 µs:
`(crew-for* chunk start end worklet arg ...)` gives each call at least
`chunk` indices, and a range of only one chunk runs on the caller alone.
An error in a call is raised in the caller. On core1, the caller waits at
most 100 ms: then it cancels the calls still running and raises an error.

`(crew-size)` is the number of workers: by default one less than the
machine's threads, at least 1 and at most 8. The environment variable
`SCHEVANA_WORKERS` sets it at start (0 for none). Life and Boids compute
their steps on the crew.

## Vats

A vat is a thread with a mailbox and a sandbox that only its thread
evaluates in, so the vat's state is its own. A `thread` environment is a
sandbox with a vat started on it:

```scheme
(define tally (vat-of (env-fork (env-root) 'thread 'name 'tally)))
(vat-eval! tally '(define n 0) #f)
(vat-eval! tally '(define (add! k) (set! n (+ n k)) n) #f)
(proc-wait 'tally (lambda (done) (vat-send! tally 'add! '(5) done)))  ; => 5
(proc-wait 'tally (lambda (done) (vat-send! tally 'add! '(2) done)))  ; => 7
```

Nothing reaches a vat's state except through its mailbox: each call
above puts a message there, and the vat's thread takes the messages out.
A message is a job: a form, for `vat-eval!`, or the name of a procedure
in the vat's sandbox (or a worklet) and its arguments, for `vat-send!`. A
vat with one thread runs its jobs one at a time, in the order they were
sent. When a job returns, its `then` (the argument after the job's own)
is called with its results on core1, at the world's next step, as a
handler of the window that sent the job: an error in `then` crashes that
window, and closing the window kills its jobs. At a REPL, `proc-wait`
turns that `then` into a returned value, as above. A job's arguments and
its results may hold no procedure but worklets.

The pool is a vat of several threads (4 unless `vat-pool-size-set!` says
otherwise) that runs only worklets, in no particular order:

```scheme
(vat-pool)                                 ; the pool, at "/worklets"
(proc-wait 'pool (lambda (done) (vat-send! (vat-pool) square '(6) done)))  ; => 36
(vat-pool-size)                            ; => 4
```

A REPL opens in a vat's environment as in any other, by its path:

```scheme
(repl "/tally")
(window-title (focused-window))            ; => "REPL — /tally"
```

In that REPL, `n` is 7 and `(add! 1)` gives 8. The REPL doesn't
evaluate in the sandbox itself, which belongs to the vat alone: it puts
each form you type in the vat's mailbox with `vat-repl!`, and the vat's
thread evaluates the form and prints the values on that thread, where
they live; the REPL shows the text it gets back. Ctrl+C kills the job.
This is what that REPL does, by hand:

```scheme
(proc-wait 'tally
  (lambda (done) (vat-repl! tally '(n (add! 1)) 72 done done)))  ; => ("7" "8")
```

`(repl 'thread)` does the same in a new thread environment of its own.
`(vat-job-kill! j)` kills a job, `(vat-drop! v)` drops a vat, and
`(vat-jobs-of v)` lists a vat's jobs; Environments shows each vat's jobs
too.

## Back to core1

`(post-core1! thunk)` hands a procedure from any thread to core1, which
runs it at its next step. A vat's `then` reaches core1 this way, and it
is the only way for another thread to have the world changed.
