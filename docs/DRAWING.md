# Drawing

A window shows what its draw procedure draws, each time it's drawn
([WINDOWS.md](WINDOWS.md)). The procedures here write records, which the
GPU draws ([INTERNALS.md](INTERNALS.md)); they draw nothing outside a draw
procedure. Each example opens a window to draw in.

## Coordinates and colors

A draw procedure gets the content's width and height, and draws from its
top-left corner, in logical pixels: what's drawn is that times the
screen's scale, `(draw-scale)`, and text and shapes are drawn from
outlines at full resolution.

A color is a theme key (`'accent`, `'text`, `'bg-2`), so it follows the
look, or a fixnum `#xRRGGBB`. `(mix a b t)` mixes two, `(alpha c a)` makes
one translucent, and `(rgb r g b)` makes one from its channels.

## Shapes

```scheme
(define (draw-shapes win w h)
  (fill-box 0 0 w h 'bg-1)
  (fill-box 20 20 120 60 'accent)                  ; a box
  (fill-box 160 20 120 60 'green 12)               ; rounded
  (stroke-box 300 20 120 60 'text 2 6)             ; an outline, 2 wide
  (fill-circle 80 150 40 (alpha 'red 0.5))
  (stroke-circle 220 150 40 'yellow 3)
  (draw-line 300 110 420 190 'cyan 4)
  (draw-polyline '((20 . 260) (80 . 220) (140 . 260) (200 . 220)) 'text 2)
  (fill-polygon '((260 . 260) (320 . 210) (380 . 260)) 'magenta)
  (draw-shadow 440 30 80 60 8 14)
  (fill-box 440 30 80 60 'bg-3 8))
(define shapes (open-window "Shapes" 'size '(540 . 280) 'draw draw-shapes))
```

`draw-shapes` is called by name each time the window draws, so it can be
redefined at the REPL and the window shows the new one; `(invalidate!
shapes)` asks for that at once. `invert-box` turns what's under a box into
reverse video, in any palette, and `add-box` adds a color to it.

## Text

```scheme
(define (draw-words win w h)
  (fill-box 0 0 w h 'bg-1)
  (let ([x (draw-text 20 20 "Draw " 'text 'ui)])   ; where it ends
    (draw-text x 20 "this" 'accent 'ui-bold))
  (draw-text 20 50 "(define (f x) x)" 'text 'mono)
  (text-draw-centered 0 80 w 60 "Centered" 'accent 'big)
  (draw-text 20 150 (text-fit "Cut to fit, whatever its length" 160 'ui)
             'text-dim 'ui))
(open-window "Text" 'size '(320 . 180) 'draw draw-words)
(font-line-height 'ui)
(text-width "Draw " 'ui)
(text-wrap "Broken into lines no wider than asked" 120 'ui)
```

A font is a role: `'ui`, `'mono`, `'title`, `'big`, and their bold,
small and italic ones, which the theme makes from its font settings
([LOOKS.md](LOOKS.md)). Text is measured from the fonts' tables, with no
device, so `text-width` is the same at any scale. `text-ink` gives what a
string inks, from the pen on the baseline, and `text-widest` the widest of
some strings.

## Clips, moves and turns

These are forms around the drawing they change, not procedures: they
allocate nothing.

```scheme
(define (draw-framed win w h)
  (fill-box 0 0 w h 'bg-1)
  (with-clip (20 20 100 100 12)                    ; rounded, 12
    (fill-box 0 0 w h 'accent)
    (draw-text 30 30 "clipped to the box" 'bg-0 'ui))
  (with-translation (160 20)
    (fill-box 0 0 40 40 'green))                   ; at (160, 20)
  (with-scale (2)
    (draw-text 110 10 "twice" 'text 'ui))
  (with-translation (240 100)
    (with-turn (0.5)
      (fill-box -30 -10 60 20 'orange)))           ; turned about (240, 100)
  (with-label ("legend")                           ; named in the Pipeline
    (draw-text 20 130 "a label names what's drawn" 'text-dim 'ui)))
(open-window "Framed" 'size '(320 . 160) 'draw draw-framed)
```

A clip's edges, like a box's, lie on whole device pixels, so what it cuts
ends crisp at any scale. A turn is in radians, clockwise on the screen:
lines and polygons turn any way, boxes become polygons, and text turns
only by a quarter.

## Gradients and patterns

A gradient or a stipple goes wherever a color does: a fill, a line, text,
a theme key's value.

```scheme
(define (draw-fills win w h)
  (fill-box 0 0 w 60 (linear-gradient 0 0 w 0 'accent 'magenta))
  (fill-gradient 0 60 w 60 'bg-0 'bg-3)            ; vertical, by default
  (fill-glow 80 170 50 'yellow)
  (fill-box 160 130 140 80 (stipple 'text 'bg-1 "#." ".#")))
(open-window "Fills" 'size '(320 . 220) 'draw draw-fills)
```

A gradient spreads its colors evenly from one point to another,
`(linear-gradient x0 y0 x1 y1 color ...)`, or out from a center,
`(radial-gradient cx cy r color ...)`. A stipple, `(stipple ink paper row
...)`, tiles rows of `#` (ink) and `.` (paper, or nothing where paper is
`#f`) over the screen's pixels, so it lines up across windows at any
scale: it's how Genera and the CADR draw gray.

## Pixels and images

A pixmap is an image an app fills pixel by pixel, one pixel a Life cell,
say, and draws scaled up in one call, each pixel a sharp block:

```scheme
(define dots (make-pixmap 8 8 'bg-1))
(do ([i 0 (+ i 1)]) ((= i 8))
  (pixmap-set! dots i i 'accent)
  (pixmap-set! dots (- 7 i) i 'green))
(open-window "Dots" 'size '(160 . 160)
  'draw (lambda (win w h) (pixmap-draw dots 0 0 w h)))
```

Its pixels are on the GPU, and what's set goes up with the next frame.
`(pixmap-rows! pm from to worklet arg ...)` has the crew paint rows of it
at once ([THREADS.md](THREADS.md)), and `draw-image` draws any image, a
pixmap's among them: at its size or bigger each pixel is a sharp block,
smaller they blend.

`kits/px.ss` draws pixel art on whole device pixels: `px-bevel` (Motif's
corners or the Mac's), `px-bits` for small pictures from rows of
characters, `px-invert`, `px-bitmap-text` (a bitmap font's text, the
CADR's 5X5 among them) and `px-lozenge`.

```scheme
(open-window "Pixel art" 'size '(300 . 140)
  'draw (lambda (win w h)
          (fill-box 0 0 w h 'bg-2)
          (with-scale (4)                          ; a logical pixel, 4 wide
            (px-bevel 2 2 20 10 'text-dim 'bg-0 1)
            (px-bits 28 3 '("..##.." ".#..#." "#....#" ".#..#." "..##..")
                     '((#\# . accent)))
            (px-bitmap-text 2 18 "HELLO" px-5x5 'text))))
```

## Paints

A paint is a shader you write in Scheme: its body runs for each pixel of a
box and gives a color, and `fill-shader` fills a box with it. Everything
about shaders is in [SHADERS.md](SHADERS.md).

```scheme
(define-paint (checks x y)
  ([ink color] [size fixnum])
  (if (fx= 0 (fxand (fx+ (fxquotient x size) (fxquotient y size)) 1)) ink 0))
(open-window "Checks" 'size '(200 . 200)
  'draw (lambda (win w h) (fill-shader 0 0 w h checks 'accent 16)))
```
