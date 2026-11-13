# Threads: worklets, the crew and vats

The world lives on one thread, core1, and only it writes the world's
state: windows, the theme, every global. Nothing locks, because nothing
else may write. Work goes to other threads in two forms that can't break
that rule: worklets, which touch only what they are handed, and vats,
threads with a sandbox of their own.

On core1 itself, long work is a process ([WINDOWS.md](WINDOWS.md)): it
runs a slice at a time between frames, so a loop never freezes the
desktop. A window's handler runs with a budget, and one that runs away or
raises crashes only its window.

## Worklets

A worklet is a procedure compiled where the world can't be reached:
Scheme's pure core, fixnums, flonums, bytevectors and the vectors of
numbers, boxes, the clock, and the other worklets. One that names
anything else is refused as it is defined.

```scheme
(define-worklet (square x) (fx* x x))
(square 7)                                 ; => 49
(guard (c [#t #f]) (worklet (x) (open-window x)))   ; => #f
```

`worklet` is to `define-worklet` what `lambda` is to `define`. Worklets
call each other by name and see each other redefined. Of what it is
handed, a worklet opens only pairs, vectors and boxes, and the threads
refuse to hand it any procedure that isn't a worklet.

## The crew

The crew is worker threads for loops: `crew-for` calls a worklet on
disjoint slices of a range, the caller among them, and returns when all
have.

```scheme
(crew-map square '(1 2 3))                 ; => (1 4 9)
(define bytes (make-bytevector 8 0))
(define-worklet (fill-slice lo hi bv)
  (do ([i lo (fx+ i 1)]) ((fx= i hi)) (bytevector-u8-set! bv i i)))
(crew-for 0 8 fill-slice bytes)
bytes                                      ; => #vu8(0 1 2 3 4 5 6 7)
```

A call writes only its own slice and allocates nothing, since allocating
stops every thread. It should take 20 to 200 µs: `(crew-for* chunk start
end worklet arg ...)` gives each call at least `chunk` indices, and a
range of one chunk runs on the caller alone. An error in a call is raised
in the caller; on core1, a call still running after 100 ms is cancelled
and the caller raises.

`(crew-size)` is how many workers there are: by default one less than the
machine's threads, at most 8. `SCHEVANA_WORKERS` sets it at start, 0 for
none. Life and Boids step on the crew.

## Vats

A vat is a thread, its mailbox, and a sandbox only its thread evaluates
in, so its state is its own. A `thread` environment is a sandbox with a
vat started on it:

```scheme
(define tally (vat-of (env-fork (env-root) 'thread 'name 'tally)))
(vat-eval! tally '(define n 0) #f)
(vat-eval! tally '(define (add! k) (set! n (+ n k)) n) #f)
(proc-wait 'tally (lambda (done) (vat-send! tally 'add! '(5) done)))  ; => 5
(proc-wait 'tally (lambda (done) (vat-send! tally 'add! '(2) done)))  ; => 7
```

Nothing reaches a vat's state but through its mailbox: each call above
puts a message there, and the vat's thread takes them out. A message is a
job: a form for `vat-eval!`, or a procedure in the vat's sandbox and its
arguments for `vat-send!`. A vat runs its jobs one at a time, in the order
sent. When one returns, its last argument, the `then`,
is called with its results on core1, at the world's next step, as a
handler of the window that sent it: an error there crashes that window,
and closing the window kills its jobs. At a REPL, `proc-wait` turns that
`then` into the value, as above. Jobs carry no procedure but worklets, and
return none.

The pool is a vat of several threads that runs worklets:

```scheme
(vat-pool)                                 ; the pool, at "/worklets"
(proc-wait 'pool (lambda (done) (vat-send! (vat-pool) square '(6) done)))  ; => 36
(vat-pool-size)                            ; => 4
```

A REPL goes into a vat's environment as into any other, by its path:

```scheme
(repl "/tally")
(window-title (focused-window))            ; => "REPL — /tally"
```

There, `n` is 7 and `(add! 1)` gives 8. The REPL doesn't evaluate in the
sandbox itself, which is the vat's alone: it puts each form you type in
the vat's mailbox with `vat-repl!`, and the vat's thread evaluates it and
prints the values there, where they live; the REPL shows the text it gets
back. Ctrl+C kills the job. What that REPL does, by hand:

```scheme
(proc-wait 'tally
  (lambda (done) (vat-repl! tally '(n (add! 1)) 72 done done)))  ; => ("7" "8")
```

`(repl 'thread)` does the same in a new thread environment of its own.
`(vat-job-kill! j)` kills a job, `(vat-drop! v)` a vat, and
`(vat-jobs-of v)` lists what it holds; Environments shows each vat's
jobs.

## Back to core1

`(post-core1! thunk)` hands a procedure from any thread to core1, which
runs it at its next step. It's what a vat's `then` rides on, and the only
way for a thread to have the world changed.
