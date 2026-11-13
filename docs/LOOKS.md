# The look: themes, styles, palettes, wallpapers

How everything looks is one table of settings, `(theme key)`: colors,
sizes, fonts, the frames' drawing, and how the desktop feels. The Settings
app is a front end to it, so anything it does is a call at the REPL. The
values shown are a fresh world's, in the Mac style it starts in.

## Settings

```scheme
(theme 'accent)                            ; => 8037111
(set-theme! 'accent #xff9e64)              ; everything that uses it, at once
(theme-source 'accent)                     ; => (changes mac 16752228)
(reset-style! 'accent)                     ; your change forgotten
(theme-source 'accent)                     ; => (built-in 8037111)
```

A color is a fixnum, `#xRRGGBB`, and wherever a color is taken a theme
key is too: `(fill-box 0 0 10 10 'accent)`. `(mix 'accent 'bg-1 0.5)`
mixes two.

A setting comes from the first layer that has it:

1. your Overrides, `(override! key value)`, which hold in every style;
2. your changes to the chosen style, `(set-theme! key value)`, kept for
   that style: switch styles and back, and they come back;
3. the style, and the styles it derives from;
4. its palette, the setting `palette`;
5. the built-in defaults.

```scheme
(override! 'ui-font-size 15)               ; in every style that honors it
(theme-source 'ui-font-size)               ; => (overrides 15)
(override! 'ui-font-size)                  ; and gone
(theme-overrides)                          ; => ()
```

A rule is a setting computed from others whenever the table is built,
never a frame at a time: the built-in `selection` is `(theme-rule (mix
'accent 'bg-1 0.65))`, so a palette gives twenty colors and the rest
follow it, as they follow your accent.

The look is saved to `~/.schevana-theme.ss` soon after each change, as
plain data.

## Styles

A style is a name, a title and settings. `set-style!` is the one switch:
frames, palette, wallpaper, fonts, behaviors, and your changes for that
style.

```scheme
(styles)
(set-style! 'genera)
(theme 'palette)                           ; => genera
(set-style! 'mac)
(theme 'palette)                           ; => tokyo-night
(open-window "Odd one out" 'window-style 'windows)  ; this one alone
```

A style may name a `'parent` and change only what it sets:

```scheme
(define-style flat-mac "Flat Mac"
  'parent 'mac
  'corner-radius 0
  'palette 'nord)
(set-style! 'flat-mac)
(set-style! 'mac)
```

Settings' Save as new style writes your changes the same way, as a
`define-style` with the style as its parent, into
`~/.schevana.d/styles/`:

```scheme no-run
(save-style-as! 'my-mac "My Mac")
```

## Parts

A part is a setting whose value is a procedure or its name, looked up at
each call, so redefining that procedure shows on the next frame. A
window's frame is six of them: `frame-insets`, `frame-regions` (its
buttons and title), `frame-radius`, `frame-bleed`, and two drawing passes
around the content, `frame-under` and `frame-over`.

```scheme
(theme 'frame-under)                       ; => mac-draw-under
(define (bare-insets win) (values 0 8 0 0))
(define (bare-under win x y w h focused? hover pressed)
  (fill-box x y w 8 (if focused? 'accent 'bg-3)))
(define-style bare "Bare"
  'frame-insets 'bare-insets
  'frame-under 'bare-under)
(set-style! 'bare)
(set-style! 'mac)
```

`define-part` makes a procedure a part: its body becomes the built-in
`name*`, and `name` calls the style's. Every widget's drawing, size and
areas in the kit is one ([UI.md](UI.md)), and so are the bars'
(`draw-topbar`, `topbar-areas`), the menus' (`draw-menu`, `menu-areas`),
the toasts' and the popups' pieces (`ui-draw-panel`, `ui-draw-highlight`,
`ui-draw-separator`, `ui-draw-card`), which menus, dialogs, tooltips and
the REPL's completion list share. So a style can replace any of them, and
a window naming a style, `'window-style`, is drawn in that style's theme,
content included; `(with-style name thunk)` draws in one.

A container draws its inside in its place (`with-place`: a text box's
`field`, a table's `list`, `dialog`, `tooltip`, `menu`, the bars' `bar`,
`toast`), so a style can color what sits there by its `'places`, an app's
own cells too. Settings say the rest: a text's caret (`text-caret`: `bar`
or `block`) and selection (`text-selection`: `fill` or `underline`), a
section label's font and case, where a menu's entries go (`menu-align`),
and the like.

## The built-in styles

The mimicked styles use the original's widgets, and where the original
has none, what its designers would have made:

- **Interlisp**, from Medley's window system sources (MIT licensed): a
  border of 2 pixels of ink and 2 of paper, a black title strip, Medley's
  #x8822 desktop, its scroll bars at the left under the pointer, its
  dashed outline when dragging, menus chosen on release.
- **Genera**, built to the margins its 1986 manuals specify: the window's
  label in its bottom-left corner, where you drag it; the whole screen, no
  top bar, and at the bottom the who line, what the mouse buttons do over
  the selected window; no color, gray as stipples; words boxed under the
  mouse, inverse video for what is chosen. Its numbers are settings
  (`genera-border`, `genera-margin`, ...).
- **The CADR**, from MIT's System 99 sources (BSD), is Genera in a few
  settings: a 1-pixel border and margin, the label upright in the code
  font, its 5X5 font in people's lozenges, its 3-pixel scroll bar.
- **Mac** and **Windows**, as their names say.

Each brings the palette of the same name and its wallpaper. Our own
styles, Cons, Curses, Draft, Fold, Halo, Lambda, Reticle, Slab and Spine,
choose their feel where it suits them: Fold folds a window up to its title
on a double click, Lambda rolls it into its tab on the wheel, Halo and
Reticle show scroll bars under the pointer, Draft drags an outline that
is a drawing with the live size, Reticle drags its brackets, and Curses
rings the bell on the whole screen and boxes menu entries.

## Palettes and wallpapers

A palette is named colors; a wallpaper is a desktop fill. Their definers
have the shape of `define-app`'s:

```scheme
(define-palette dusk "Dusk"
  '(bg-0 #x15131c bg-1 #x1c1a26 bg-2 #x24212f bg-3 #x2e2a3b
    text #xe0dcef text-dim #xb8b2cc text-faint #x6e6884
    accent #xf0a35e accent-2 #xc792ea
    red #xf07178 orange #xf78c6c yellow #xffcb6b green #xc3e88d
    cyan #x89ddff teal #x80cbc4 magenta #xc792ea
    desktop-top #x1c1a26 desktop-bottom #x3a2a40 watermark #xffffff
    panel #x111017))
(set-theme! 'palette 'dusk)
(define-wallpaper stripes "Stripes"
  (lambda (x y w h top bottom)
    (fill-box x y w h top)
    (do ([i 0 (+ i 24)]) ((>= i h)) (fill-box x (+ y i) w 12 bottom))))
(set-theme! 'wallpaper 'stripes)
(palettes)
(wallpapers)
```

Define one again and the new definition takes the old one's place. To keep
one, put it in a file of its own under `~/.schevana.d/palettes/` or
`~/.schevana.d/wallpapers/` ([APPS.md](APPS.md)).

## Fonts and sizes

```scheme
(theme 'ui)                                ; the font a role makes
(font-line-height 'mono)
(text-width "hello" 'ui)
(set-theme! 'mono-font "monospace")
(set-theme! 'mono-font-size 15)
(reset-style! 'mono-font 'mono-font-size)
```

A font role (`'ui`, `'mono`, `'title`, `'big` and their bold, small and
italic ones) is a rule that makes its font from four settings, `ui-font`,
`ui-font-size`, `mono-font` and `mono-font-size`; a style changes a role
by setting it. The kit's shared sizes (`control-height`, `gap`, `pad`,
...) are rules from the fonts too, and title bars and bars take the
larger of their own setting and what their text needs, so the desktop
stays usable from 9 to 36 px.

Layout is in logical pixels, and what's drawn is that times the screen's
scale: text and shapes are drawn from outlines at full resolution, and a
text measures the same at any scale. The scale follows the desktop's;
`(set-theme! 'scale 200)` sets it in percent, and 0 follows again.

## How it feels

What differs between desktops beyond drawing is settings too:

```scheme
(set-theme! 'title-double-click 'shade)    ; a double click rolls it up
(set-theme! 'drag-feedback 'outline)       ; drag an outline, not the window
(set-theme! 'raise-on-click #f)
(override! 'mouse-doc #t)                  ; what the buttons do, in the top bar
(reset-style! 'title-double-click 'drag-feedback 'raise-on-click)
(override! 'mouse-doc)
```

Among them: `title-double-click` (`maximize`, `shade`, `none`),
`title-wheel`, `drag-feedback` (`live`, `outline`), `frame-edge` and
`frame-corner` (the resize edges), `raise-on-click`, `menu-choose`
(`click`, `release`), `scrollbar-side` and `scrollbar-show`, and the
bell, `(bell)`. A style chooses each; the built-in styles show what they
can do.
