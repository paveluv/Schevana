# Drawing

A window shows what its draw procedure draws each time the window is
drawn ([WINDOWS.md](WINDOWS.md)). The procedures on this page write
records, which the GPU then draws ([INTERNALS.md](INTERNALS.md)); outside
a draw procedure they draw nothing. Each example opens a window to draw
in.

## Coordinates and colors

A draw procedure is given the content's width and height, and its
coordinates start at the content's top-left corner. They are in logical
pixels: what is drawn is that size times the screen's scale,
`(draw-scale)`, and text and shapes are drawn from outlines at full
resolution.

A color is either a theme key (`'accent`, `'text`, `'bg-2`), which
follows the look, or a fixnum `#xRRGGBB`. `(mix a b t)` mixes two colors,
`(alpha c a)` makes a color translucent, and `(rgb r g b)` makes one from
its red, green and blue channels.

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

The window keeps the procedure it was given, so redefining `draw-shapes`
at the REPL doesn't change it. To make a redefinition show, give the
window `(lambda (win w h) (draw-shapes win w h))`, which calls
`draw-shapes` by name each time the window draws; `(invalidate! shapes)`
then draws the window again at once. `invert-box` turns what is under a
box into reverse video, in any palette, and `add-box` adds a color to
it.

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

A font is named by its role: `'ui`, `'mono`, `'title`, `'big`, and
variants such as `'ui-bold`, `'ui-small` and `'ui-italic`, which the
theme makes from its font settings ([LOOKS.md](LOOKS.md)). Text is
measured from the fonts' tables, with no device, so `text-width` is the
same at any scale. `text-ink` returns the box that a string's ink covers,
measured from the pen on the baseline, and `text-widest` the width of the
widest of some strings.

A font may be a bitmap font, its pixels drawn by hand at one size, as the
mimicked styles' originals had (the Interlisp style draws all of its text
in Medley's own). `define-bitmap-font` registers one by name: its pixel
size, ascent and descent, then its glyphs, each a character, its advance,
where its bits begin (right of the pen and above the baseline), its
width, and its rows from the top, the leftmost pixel in a row's highest
bit; `#f` is what a character it lacks draws. A font of that family draws
it, a font pixel to a logical pixel at the pixel size, each pixel a square
at any whole scale; it is measured and drawn as any font is:

```scheme
(define-bitmap-font "Chevrons"
  '(5 5 0
    (#f 6 1 5 4 #b1111 #b1111 #b1111 #b1111 #b1111)
    (32 6)
    (60 6 0 5 5 #b00011 #b01100 #b10000 #b01100 #b00011)
    (62 6 0 5 5 #b11000 #b00110 #b00001 #b00110 #b11000)))
(define chevrons (font "Chevrons" 15 'crisp))      ; three times its size
(define (draw-chevrons win w h)
  (fill-box 0 0 w h 'bg-1)
  (draw-text 20 20 "<> <>?" 'accent chevrons))     ; ? is the slug
(open-window "Chevrons" 'size '(240 . 70) 'draw draw-chevrons)
(text-width "<>" chevrons)                         ; => 36.0
(inspect-bitmap-fonts)
```

A bitmap font is always drawn at whole pixels, so it is given `'crisp`.

## Clips, moves and turns

These are forms written around the drawing they change, not procedures
that take a thunk, so they allocate nothing.

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

A clip's edges, like a box's, lie on whole device pixels, so the edge it
cuts is crisp at any scale. A turn is in radians, clockwise on the
screen: lines and polygons turn by any angle, boxes become polygons, and
text turns only by a quarter turn counterclockwise.

## Gradients and patterns

A gradient or a stipple can go wherever a color can: in a fill, a line or
text, or as a theme key's value.

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
`#f`) from the screen's origin, so the tiles line up across windows at
any scale: this is how Genera and the CADR draw gray.

## Pixels and images

A pixmap is an image that an app fills pixel by pixel (one pixel per Life
cell, say) and draws scaled up in one call, each pixel as a sharp block:

```scheme
(define dots (make-pixmap 8 8 'bg-1))
(do ([i 0 (+ i 1)]) ((= i 8))
  (pixmap-set! dots i i 'accent)
  (pixmap-set! dots (- 7 i) i 'green))
(open-window "Dots" 'size '(160 . 160)
  'draw (lambda (win w h) (pixmap-draw dots 0 0 w h)))
```

Its pixels are on the GPU, and a pixel that is set goes up with the next
frame. `(pixmap-rows! pm from to worklet arg ...)` has the crew paint
rows of it, each thread a share of them ([THREADS.md](THREADS.md)), and
`draw-image` draws any image, a pixmap's among them: at its own size or
bigger each pixel is a sharp block, and smaller the pixels blend.

`schevana/kits/px.sls` draws pixel art on whole device pixels:
`px-bevel` (with Motif's corners or the Mac's), `px-bits` for small
pictures from rows of characters, `px-invert`, and `px-bitmap-text` for
text in a bitmap font (the Genera style has one, the CADR's 5X5,
`genera-5x5`).

```scheme
(open-window "Pixel art" 'size '(300 . 140)
  'draw (lambda (win w h)
          (fill-box 0 0 w h 'bg-2)
          (with-scale (4)                          ; a logical pixel, 4 wide
            (px-bevel 2 2 20 10 'text-dim 'bg-0 1)
            (px-bits 28 3 '("..##.." ".#..#." "#....#" ".#..#." "..##..")
                     '((#\# . accent)))
            (px-bitmap-text 2 18 "HELLO" genera-5x5 'text))))
```

## Paints

A paint is a shader you write in Scheme: its body runs for each pixel of
a box and returns a color, and `fill-shader` fills a box with it.
Everything about shaders is in [SHADERS.md](SHADERS.md).

```scheme
(define-paint (checks x y)
  ([ink color] [size fixnum])
  (if (fx= 0 (fxand (fx+ (fxquotient x size) (fxquotient y size)) 1)) ink 0))
(open-window "Checks" 'size '(200 . 200)
  'draw (lambda (win w h) (fill-shader 0 0 w h checks 'accent 16)))
```
