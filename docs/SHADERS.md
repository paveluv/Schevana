# Shaders

A shader is a small program the GPU runs many times at once: once for each
pixel of a box, or once for each cell of a grid. In Schevana you write one
in a small Scheme, at a REPL or in an app's file, and it is compiled the
moment it is defined, for whatever GPU this machine has. The same language
draws everything on the screen: the core's own drawing is shaders written
in it.

This guide covers what shaders do in Schevana, the language, how a shader
gets from its definition to the GPU, and two examples to type at a REPL.

## Their role in Schevana

- **The core draws everything with them.** A window's drawing is a list of
  records (boxes, glyphs, lines, shadows, gradients, stipples, images). One
  vertex shader, `gfx-vertex`, and a fragment shader in seven variants,
  `gfx-fragments`, draw those records, all in `src/core1/gfx.ss` and all in this
  language. Each variant holds only the code its records need, so a pixel
  pays only for what it draws.
- **Apps add their own, of two kinds.** A *paint* (`define-paint`) gives a
  color for each pixel of a box, and is drawn with `fill-shader` among the
  window's other drawing, clipped like it. A *compute shader*
  (`define-compute-shader`) runs over a grid of cells and writes into GPU
  buffers, which paints then read. Boids 3D is all shaders: three compute
  shaders steer the flock, lay it out by the camera and sort it into
  tiles, and a paint draws the sky, the sea and the birds. The flock never
  comes back to the CPU.
- **Apps in sandboxes get them through a bundle.** `gpu`, "Compute and draw
  on the GPU", gives an app `define-compute-shader`, `define-paint`,
  `fill-shader`, `draw-scale`, `make-gpu-buffer`, `gpu-buffer-set!`,
  `gpu-buffer-release!` and `gpu-compute-soon!`. A shader touches only the
  buffers it is handed, so a sandboxed app's shaders reach nothing else.
- **The language is a contract.** It asks only for what every GPU API has,
  and defines its own meaning where targets differ (dividing by zero, say),
  so that a shader gives the same results everywhere. What one back end
  can't do doesn't get in. There are three back ends: SPIR-V for Vulkan
  (Linux), MSL for Metal (the Mac), and the *twin*, which turns a shader
  into a Scheme procedure; `tests/units/shader.ss` holds the device and the
  twin to the same answers.
- **The GPU layer speaks in the world's terms.** Above core0 nothing names
  Vulkan, SPIR-V, Metal or MSL but the compiler, which writes the back
  ends' code. Core0 (`src/core0/gpu.ss`) makes the pipelines and runs them.

## A first shader

```scheme
(define-compute-shader (squares x y)
  ([out fx-buffer write])
  (fx-set! out x (fx* x x)))
```

`squares` runs once for each cell of the grid it is run over, `x` and `y`
being the cell. Its one parameter, `out`, is a buffer of whole numbers it
may write. Run over a grid 10 cells wide and 1 high, it fills the first ten
words of `out` with 0, 1, 4, 9 and so on.

Everything about it is checked when it is defined: the types of every
expression, that `out` may be written, that every name is something the
shader was handed. A mistake is an error at once, at the REPL or as the
app loads, never a wrong picture later:

```
(fl+ 1 2.0): wants flonum, has fixnum
in: read-only, in (fx-set! in x 1)
(do-bounded n ...): loops have a fixed bound
vector-ref: not available in a shader
```

## The language

### Values

There are three types: `fixnum`, a 32-bit whole number; `flonum`, a 32-bit
float; and `boolean`. There are no strings, pairs, vectors or procedures as
values, no recursion and no memory but the buffers a shader is handed.
Literals are written as in Scheme: `3`, `-1`, `0.5`, `#t`. A whole number is
a 32-bit word, so a color with its top bit set can be written as a negative
number: `-16777216` is `#xff000000`.

### Parameters

A shader's head names it and its coordinates; then comes a list of
parameters, each a name and a kind:

| Kind | What the shader gets |
|---|---|
| `fixnum`, `flonum` | a number, the same for every cell or pixel |
| `color` | (paints only) a color word, from a color or a theme key |
| `fx-buffer`, `fl-buffer` | a GPU buffer of whole numbers or floats, to read |
| `fx-buffer write`, `fl-buffer write` | the same, to write |

A buffer is read or written in a run, never both. Each buffer's length is
handed to the shader too, unseen, which is how reads and writes are kept
inside it.

### Forms

- `let`, `let*`, `begin`, `if`, `cond`, `case` (its data are whole
  numbers or constants' names), `when`, `unless`, `and`, `or`. An `if`
  without an else, a `when` and the like have no value: what wants one
  refuses them.
- `(define (name arg ...) body ...)` makes a local function where a
  `define` can go. It is inlined where it is called, sees what came before
  it, and can't call itself.
- `(do-bounded most ([var init step] ...) (test result))` is `do` with a
  bound: at most `most` rounds, `most` a number written in the shader. It
  gives `result` once `test` is true, or after the last round.

### Operations

| | |
|---|---|
| whole numbers | `fx+` `fx-` `fx*` `fxquotient` `fxmod` `fxand` `fxior` `fxxor` `fxnot` `fxsll` `fxsrl` `fxsra` |
| compared | `fx=` `fx<` `fx>` `fx<=` `fx>=` |
| floats | `fl+` `fl-` `fl*` `fl/` `flmin` `flmax` `flabs` `flfloor` `flceiling` `flround` `flsqrt` `flsin` `flcos` |
| compared | `fl=` `fl<` `fl>` `fl<=` `fl>=` |
| between them | `fixnum->flonum` `flonum->fixnum` |
| booleans | `not`, and `and` and `or` as forms |
| buffers | `(fx-ref b i)` `(fl-ref b i)` `(fx-set! b i v)` `(fl-set! b i v)` |

`fx+`, `fx*`, `fxand`, `fxior`, `fxxor`, `fl+`, `fl*`, `fl/`, `flmin` and
`flmax` take any number of arguments; `fx-` and `fl-` of one negate it.

### What it means

The language defines its own meaning where GPUs differ or leave it
undefined, and every back end keeps to it:

- Whole numbers are 32 bits and wrap.
- Dividing by 0 gives 0; dividing the smallest number by -1 wraps.
  `fxmod` floors, as Scheme's does.
- A shift's count is taken mod 32.
- `flround` takes a half to the even neighbor.
- Operands are worked out left to right.
- A read outside a buffer reads its last word (a negative index too); a
  write outside is left out.

## How a shader gets to the GPU

1. **Defining it compiles it.** `define-compute-shader` (and
   `define-paint`) is a macro: as it expands, the front end in
   `src/core1/shader.ss` checks the forms and lowers them to a small typed tree,
   with every local function inlined, every `cond`, `case` and `when` turned
   into `if`, and every constant replaced by its number. A test it can work
   out leaves only its arm. The back end for this machine then writes the
   tree as SPIR-V words or MSL text. The result is a `shader` record: its
   name, stage, coordinates, parameters, source, code and *price*, what one
   run costs at most, counted from the tree (a loop's bound times its body).
2. **Running it is a call.** `fill-shader` and `gpu-compute-soon!` pack
   numbers into a uniform block: the hidden ones first (a compute run's
   grid size), then the numbers they're given, then each buffer's length.
   The buffers they keep by handle.
3. **The frame takes it to core0.** A paint's call is recorded among the
   window's drawing; a compute run waits in a list, `(inspect-computes)`,
   for the next frame. Core0 makes a pipeline for a shader the first time
   it sees it, runs the frame's compute runs ahead of its drawing, so that a
   paint shows what they wrote, and then draws. A compute run asked for
   when no frame is coming goes at the step's end on its own.
4. **A compute shader runs in groups** of 64 cells along x; a cell outside
   the grid it was asked for does nothing.

## Sharing names with Scheme

What writes a buffer in Scheme and what reads it in a shader must agree on
numbers and offsets. Three forms keep one definition for both:

```scheme
(define-shader-constant cell-words 4)      ; a number, in Scheme and shaders

(define-shader-layout cell cells (count color))
;; cell-words is 2, cell-count 0 and cell-color 1: offsets, in Scheme and
;; shaders; in a shader, (cell-color row) reads (fx-ref cells (fx+ row 1)),
;; cells being an fx-buffer (or a local function) in scope there

(define-shader-helpers vectors             ; local functions to share
  (define (dot ax ay bx by) (fl+ (fl* ax bx) (fl* ay by))))
;; in a shader, (use-shader-helpers vectors) where a define could go
```

`(inspect-shader-constants)`, `(inspect-shader-helpers)` and
`(inspect-shader-fields)` list what's defined.

## Paints

```scheme
(define-paint (stripes x y)
  ([ink color] [width fixnum])
  (if (fx= 0 (fxand (fxquotient x width) 1)) ink 0))

;; in a window's draw procedure
(fill-shader 0 0 w h stripes 'accent 8)
```

A paint's body gives a color word, `#xAARRGGBB`, alpha not multiplied in;
0 is transparent. `x` and `y` are the pixel, in device pixels from the
box's corner: on a display at 2× a box 100 wide is 200 pixels, and
`(draw-scale)` gives the factor. `fill-shader` takes the box, in the
window's units, the paint, and the paint's arguments in order. A `color`
parameter takes a color or a theme key.

A paint is drawn like any other drawing: in order, clipped to its window
and to rounded corners, in a list that is drawn again only when the window
asks. It starts with the core's helpers in scope, among them `(channel c
shift)`, a color word's channel from 0 to 1 (`shift` 16 for red),
`(mixed a b t)` and `(clamp01 v)`.

## Compute shaders and buffers

```scheme
(define b (make-gpu-buffer 1000))    ; 1000 words, zeroed
(gpu-buffer-set! b 0 42)             ; a whole number, or a float
(gpu-compute-soon! squares 1000 1 b) ; the grid, then the arguments
```

`gpu-buffer-set!` writes a word; it goes up with the next frame or compute
run. `gpu-compute-soon!` runs the shader with the next frame, ahead of its
drawing, and nothing waits for it.

A buffer, an image or a list nothing holds any more is let go of once a
collection finds it, so an app never has to free one.
`gpu-buffer-release!` frees at once, and is optional.

A shader's results show on the screen through a paint, or come back to
Scheme.

### At a REPL, on the GPU and back

`squares` from above, run on the GPU over ten cells, and what it wrote read
back:

```scheme
(define-compute-shader (squares x y)
  ([out fx-buffer write])
  (fx-set! out x (fx* x x)))

(define b (make-gpu-buffer 10))
(gpu-compute! squares 10 1 b)
(define bytes (gpu-buffer-read! b))   ; 4 bytes a word, as the GPU wrote them

(map (lambda (i) (bytevector-s32-native-ref bytes (* 4 i))) (iota 10))
; => (0 1 4 9 16 25 36 49 64 81)
```

`gpu-compute!` runs the shader and `gpu-buffer-read!` reads the buffer
back, each waiting till it's done, while the world goes on: a REPL's input
runs as a process, and a process can wait without holding core1, the
world's thread. Core0 reads the buffer between frames and hands the bytes
back. Ctrl+C stops the wait like any other. A float buffer (`fl-buffer`)
reads the same way, each word with `bytevector-ieee-single-native-ref`.

Code that isn't in a process (a window's handler, a timer, an app) can't
wait, and the two raise there. It asks for the bytes with a procedure to
hand them to, `gpu-buffer-read-then!`, which nothing waits for:

```scheme
(gpu-compute-soon! squares 10 1 b)
(gpu-buffer-read-then! b (lambda (bytes) (set! squared bytes)))
```

The run goes with the next frame; the read goes after it, and the
procedure runs on core1 a step or two later. A buffer let go of meanwhile
reads `#f`. The waiting calls are this, inside a process: `(proc-wait who
start)` waits for what `start` hands its `done`, and wraps any call that
hands its result to a procedure later.

With one thread playing both core0 and core1, as in the tests, the two
read at once, waiting for the GPU itself. The twin, below, runs a shader
on the CPU, where waiting is always fine.

## The twin

`(twin-procedure shader)` is the shader as a Scheme procedure: slow, exact,
and the language's meaning to the letter. A compute shader's twin takes the
cell, the grid's size, then the shader's arguments, with bytevectors for
buffers, and runs one cell:

```scheme
(define out (make-bytevector 40 0))
(let ([run (twin-procedure squares)])
  (do ([x 0 (+ x 1)]) ((= x 10)) (run x 0 10 1 out)))
(bytevector-s32-native-ref out 12)   ; => 9
```

It's how to try a shader at a REPL, how the tests check the device, and a
back end of its own: what it can't do, the language doesn't have.

## Looking at shaders

- `(shader-tree s)` gives the typed tree the back ends get.
- `(shader-code s)` is what went to the driver; `(shader-price s)` its price.
- `(inspect-shader-lines s)` is its source, pretty-printed, with the
  helpers it uses written out.
- Pipeline shows the source of the shader behind a paint run, and what
  the GPU holds.

## Costs

The price counts operations; the GPU's cost is not only that. On Metal,
safe math makes division and `flsqrt` dear, so the core multiplies by
`0.00392156862745098` where it means "divided by 255". Code that never runs
still costs registers, which is why the core's fragment shader comes in
seven variants instead of one with branches. A test the compiler can work
out costs nothing: an option handed as a constant leaves only its arm.

## Two examples at the REPL

Both use the same compute shader: the Mandelbrot set's escape count for
each cell, `cx` and `cy` the top-left corner in the plane and `step` a
cell's width there.

```scheme
(define-compute-shader (mandel x y)
  ([out fx-buffer write] [w fixnum] [cx flonum] [cy flonum] [step flonum])
  (let ([cr (fl+ cx (fl* step (fixnum->flonum x)))]
        [ci (fl+ cy (fl* step (fixnum->flonum y)))])
    (fx-set! out (fx+ x (fx* y w))
             (do-bounded 300 ([zr 0.0 (fl+ (fl- (fl* zr zr) (fl* zi zi)) cr)]
                              [zi 0.0 (fl+ (fl* 2.0 zr zi) ci)]
                              [n 0 (fx+ n 1)])
               ((fl> (fl+ (fl* zr zr) (fl* zi zi)) 4.0) n)))))
```

### As text, through the twin

The twin runs `mandel` on the CPU, cell by cell, and the REPL prints the
counts as characters. It works in any REPL, and shows exactly what the GPU
would compute.

```scheme
(define (mandel-text w h)
  ;; a character is about twice as tall as it is wide: twice the rows are
  ;; computed, and every other one printed
  (let* ([rows (* 2 h)]
         [out (make-bytevector (* 4 w rows) 0)]
         [run (twin-procedure mandel)]
         [step (/ 3.0 w)])
    (do ([y 0 (+ y 1)]) ((= y rows))
      (do ([x 0 (+ x 1)]) ((= x w))
        ;; the cell, the grid's size, then the shader's parameters
        (run x y w rows out w -2.2 (* step h -1.0) step)))
    (do ([y 0 (+ y 2)]) ((>= y rows))
      (do ([x 0 (+ x 1)]) ((= x w))
        (let ([n (bytevector-s32-native-ref out (* 4 (+ x (* y w))))])
          (display (string-ref " .:-=+*#%@" (min 9 (quotient n 4))))))
      (newline))))

(mandel-text 72 24)
```

### In a window, on the GPU

Here the GPU does the work: `mandel` fills a buffer with a count for each
of the window's pixels, and a paint colors them, every frame, zooming in
twice as close a second for 14 seconds, then again from the start. Nothing
comes back to the CPU.

```scheme
;; Each pixel's count, as a color: black inside, dark blue to gold outside.
(define-paint (mandel-view x y)
  ([counts fx-buffer] [w fixnum])
  (let ([n (fx-ref counts (fx+ x (fx* y w)))])
    (define (byte v) (flonum->fixnum (fl* 255.0 (flmin 1.0 v))))
    (if (fx>= n 300)
        -16777216                                  ; #xff000000, opaque black
        (let* ([t (flsqrt (fl/ (fixnum->flonum n) 300.0))]
               [u (fl- 1.0 t)])
          (fxior -16777216
                 (fxsll (byte (fl* 9.0 u t t t)) 16)
                 (fxsll (byte (fl* 15.0 u u t t)) 8)
                 (byte (fl* 8.5 u u u t)))))))

;; A compute run and a paint a frame; the counts' buffer is the window's,
;; made again when the window grows.
(define (mandel-window)
  (open-window "Mandelbrot"
    'size '(640 . 400)
    'open (lambda (win)
            (window-set! win 'start (now-ms))
            (window-frame-soon! win))
    'frame (lambda (win t) (window-frame-soon! win) (invalidate! win))
    'draw (lambda (win w h)
            (let* ([s (draw-scale)]
                   [pw (exact (ceiling (* w s)))]
                   [ph (exact (ceiling (* h s)))]
                   [b (window-ref win 'counts #f)]
                   [counts (if (and b (>= (cdr b) (* pw ph)))
                               (car b)
                               (let ([new (make-gpu-buffer (* pw ph))])
                                 (window-set! win 'counts (cons new (* pw ph)))
                                 new))]
                   [secs (/ (- (now-ms) (window-ref win 'start)) 1000.0)]
                   [zoom (- secs (* 14 (floor (/ secs 14))))]
                   [step (/ (* 3.0 (expt 0.5 zoom)) pw)])
              (gpu-compute-soon! mandel pw ph counts pw
                                 (- -0.743643887 (* step pw 0.5))
                                 (- 0.131825904 (* step ph 0.5))
                                 step)
              (fill-shader 0 0 w h mandel-view counts pw)))))

(mandel-window)
```

- **A frame** asks for the next one (`'frame`) and draws again. The draw
  procedure queues the compute run, which goes ahead of that frame's
  drawing, then paints from the same buffer.
- **The buffer** has a word for each device pixel. When the window grows
  a bigger one replaces it, and the old one, held by nothing, goes by
  itself; so does the last one when the window closes.
- **Precision**: shaders compute in 32-bit floats, so by the end of each
  zoom the edges turn grainy. That's why it starts over there.

## Where the code is

| File | What it holds |
|---|---|
| `src/core1/shader.ss` | the language: the front end, the SPIR-V and MSL back ends, `define-compute-shader`, constants, helpers and layouts |
| `src/core1/gfx.ss` | `define-paint`, `fill-shader`, the core's own shaders and their helpers |
| `src/core1/gpu.ss` | buffers and images as handles, calls, compute runs |
| `src/core0/gpu.ss` | core0: pipelines, dispatch, drawing |
| `kits/twin.ss` | the twin |
| `kits/inspect.ss` | `inspect-shader-…`, `inspect-computes` |
| `apps/boids3d.ss` | an app that is all shaders |
| `tests/units/shader.ss` | the device and the twin held together |
