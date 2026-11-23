# The look: themes, styles, palettes, wallpapers

How everything looks is one table of settings, read with `(theme key)`:
colors, sizes, fonts, how the frames are drawn, and how the desktop
behaves. The Settings app is a front end to this table, so anything
Settings does can also be done with a call at the REPL. The values shown
below are those of a fresh world, which starts in the Mac style.

## Settings

```scheme
(theme 'accent)                            ; => 8037111
(set-theme! 'accent #xff9e64)              ; everything that uses it, at once
(theme-source 'accent)                     ; => (changes mac 16752228)
(reset-style! 'accent)                     ; your change forgotten
(theme-source 'accent)                     ; => (built-in 8037111)
(set-accent! #x9ece6a)                     ; the accent's own word for it
(theme 'accent)                            ; => 10407530
(reset-style! 'accent)
```

A color is a fixnum, `#xRRGGBB`. Wherever a procedure takes a color, it
also takes a theme key: `(fill-box 0 0 10 10 'accent)`. `(mix 'accent
'bg-1 0.5)` mixes two colors.

A setting comes from the first of these layers that has it:

1. your Overrides, `(override! key value)`, which hold in every style;
2. your changes to the chosen style, `(set-theme! key value)`, kept for
   that style: switch to another style and back, and they come back;
3. the style, and the styles it derives from;
4. the style's palette, which the setting `palette` names;
5. the built-in defaults.

```scheme
(override! 'ui-font-size 15)               ; in every style that honors it
(theme-source 'ui-font-size)               ; => (overrides 15)
(override! 'ui-font-size)                  ; and gone
(theme-overrides)                          ; => ()
```

A rule is a setting computed from other settings each time the table is
built, never once a frame. The built-in `selection`, for example, is
`(theme-rule (mix 'accent 'bg-1 0.65))`. So a palette gives twenty
colors, the rest are computed from them, and they change when you change
the accent.

The look is saved to `~/.schevana-theme.ss` soon after each change, as
plain data.

## Styles

A style is a name, a title and settings. `set-style!` is the one switch
that changes everything at once: the frames, palette, wallpaper, fonts
and behaviors, with your changes for that style.

```scheme
(styles)
(set-style! 'genera)
(theme 'palette)                           ; => genera
(set-style! 'mac)
(theme 'palette)                           ; => tokyo-night
(open-window "Odd one out" 'window-style 'windows)  ; this one alone
```

A style may name a `'parent`. It then has all of the parent's settings
but those it sets itself:

```scheme
(define-style flat-mac "Flat Mac"
  'parent 'mac
  'corner-radius 0
  'palette 'nord)
(set-style! 'flat-mac)
(set-style! 'mac)
```

Settings' Save as new style writes your changes to the chosen style the
same way: as a `define-style` whose parent is that style, in a file in
`~/.schevana.d/styles/`. It then loads the new style and chooses it:

```scheme no-run
(save-style-as! 'my-mac "My Mac")
```

## Parts

A part is a setting whose value is a procedure, or the name of one. The
name is looked up at each call, so a redefinition of the procedure shows
on the next frame. A window's frame is made of six parts:
`frame-insets`, `frame-regions` (its buttons and title), `frame-radius`,
`frame-bleed`, and two drawing passes around the content, `frame-under`
and `frame-over`.

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
procedure `name*`, and `name` calls the procedure that the style gives.
In the kit, each widget's drawing, size and areas are parts
([UI.md](UI.md)). So are the bars' (`draw-topbar`, `topbar-areas`), the
menus' (`draw-menu`, `menu-areas`) and the toasts', and the pieces of a
popup (`ui-draw-panel`, `ui-draw-highlight`, `ui-draw-separator`,
`ui-draw-card`), which menus, dialogs, tooltips and the REPL's completion
list share. So a style can replace any of them. A window that names a
style with `'window-style` is drawn in that style's theme, its content
included, and `(with-style name thunk)` runs `thunk` so that it draws in
the theme of the style `name`.

The looks load before the desktop and use nothing of it, so a program can
take a look without the desktop (a host app, [APPS.md](APPS.md)). The
desktop hands its parts what they draw as arguments, and calls them in
the place they draw in (`bar`, `menu`, `toast`), as the kit does with a
widget's parts:

- `(topbar-areas h)` and `(draw-topbar h areas open? doc status)`: the
  bar's height `h`, its areas, the launcher's form while it is open
  (`menu` or `grid`, else `#f`), the line of
  mouse documentation (worded by `mouse-doc-text`) or `#f`, which takes the
  status's place where the style shows it (`'mouse-doc`), and the status
  segments, `((name . string) ...)`;
- `(taskbar-areas h hint)` and `(draw-taskbar h areas open? doc status
  hint)`: the same, and the hint's text; here `doc` is the mouse
  documentation only where there is no top bar (Genera's who line);
- `(menu-areas m)` and `(draw-menu m areas on flags)`: the menu, as the
  menu kit's data (`(schevana kits menu)`: `menu-entries`,
  `menu-label-text`, `menu-entry-icon`, `menu-icon-size`, `menu-filter`,
  ...), its areas, the entry shown chosen or `#f`, and that entry's
  highlight's flags (`outline`, `pressed`). An entry may have an icon
  (the launcher's apps have theirs), which the built-in menu draws before
  its text unless the style's `menu-icons` is `#f` (the Lisp machines',
  OPEN LOOK's and Curses' menus are words alone);
- `(app-grid-areas n page)` and `(draw-app-grid entries areas filter page
  sel)`: the app grid, the launcher of a style whose `launcher-form` is
  `grid` (GNOME's), which shows the apps over the windows and under the
  bars, in pages under a search field. Its areas, for `n` entries with
  `page` shown, are the search field's, a dot for each page when there
  is more than one, `((page . k) x y w h)`, and the page's entries, `(i x
  y w h)`. It is handed its entries for what is typed, each `(label app .
  thunk)`, where `app` is an app's name or `#f` for one of the desktop's
  actions, their areas, what is typed, the page and the entry the keys
  chose, or `#f`;
- `(toast-boxes)`, which returns where each toast goes, and `(draw-toasts
  boxes)`; and `(draw-wallpaper w h)`, which fills the desktop with
  `fill-wallpaper`.

A container draws what is inside it within its place (`with-place`): a
text box's `field`, a table's `list`, a `dialog`, a `tooltip`, a `menu`,
the bars' `bar`, and a `toast`. A style can give each place settings of
its own, under `'places`, to color what sits there, an app's own cells
included. Plain settings cover the rest: a text's caret (`text-caret`:
`bar` or `block`) and its selection (`text-selection`: `fill` or
`underline`), a section label's font and case, how a menu's entries are
aligned (`menu-align`), and the like.

Every place that shows an app draws its icon ([WINDOWS.md](WINDOWS.md#apps)):
the launcher, the taskbar or the dash, the app grid, and the title bar
where a style has one there (`ui-title-icon`). An app's icon is drawn in
the theme's colors, so it follows the palette; an app that gives none
gets a stand-in from the part `ui-draw-app-tile`, a tile in the app's
color (`app-colors`) with its title's first letter.

## The built-in styles

The mimicked styles use the original's widgets, and where the original
has none, the widget its designers would have made:

- **Interlisp**, from Medley's window system sources (MIT licensed): a
  border of 2 pixels of ink and 2 of paper, a black title strip, Medley's
  #x8822 desktop, scroll bars at the left that show while the pointer is
  over the view, a dashed outline while a window is dragged, and menus
  that choose on release.
- **Genera**, built to the margins its 1986 manuals specify: the window's
  label sits in its bottom-left corner, and you drag the window by it. The
  style covers the whole screen: there is no top bar, and at the bottom
  the who line shows what the mouse buttons do over the selected window.
  There is no color, and gray is drawn as stipples; words are boxed under
  the mouse, and what is chosen is in inverse video. Its numbers are
  settings (`genera-border`, `genera-margin`, ...).
- **The CADR**, from MIT's System 99 sources (BSD), is Genera with a few
  settings changed: a 1-pixel border and margin, the label upright in the
  code font, and a 3-pixel scroll bar. (The 5X5 font in which both styles
  draw people's initials in lozenges is the CADR's.)
- **OPEN LOOK** (Sun, 1988) as OpenWindows drew it: olwm's frames drawn
  through OLGX, from XView 3.2's sources on the X11R6 contrib tape, with
  Sun's Functional Specification of 1989 where the code is silent. A
  window is its window color in a 2-pixel outline, 3 pixels while it has
  the focus. Its header holds the window button, which closes the window
  to the taskbar, and the title, in bold, centered to the right of the
  button. An L-shaped resize corner at each corner is the only place the
  window resizes from. The focus is shown as a band across the header, of
  ink in 2D and recessed in 3D (`open-look-depth`), or as olwm's two lines
  (`open-look-focus`). A window opened `'above` another is a pop-up: it has
  a pushpin instead of the button, pinned in, which dismisses the window
  when pulled out, and it has no corners, as XView's pop-ups keep their
  size. A window's `'footer`, a string or `(left . right)`, shows under
  the pane. Everything comes in OPEN LOOK's four sizes, 10, 12, 14 and 19
  point, whichever is nearest the text size: OLGX's glyph fonts drawn
  pixel for pixel, olwm's numbers, and the 3D shades that OLGX takes from
  the window color (`open-look-window`): BG2 is 90 % of its value, BG3
  50 %, and the highlight 120 %. Drawn where olwm's own screenshots have
  their frames, at every size in 2D and 3D, its frames match olwm's to the
  pixel but for three pixels at 14 and 19 point, where olwm's corner shows
  the desktop through. Its buttons are OLGX's as XView drew them, on panes
  of the window color in 3D and white in 2D: oblong, the default one
  ringed a pixel inside, a glyph alone in an abbreviated button, a pressed
  one recessed in 3D and filled with ink in 2D, and an inactive one grayed
  over every other pixel. Drawn alone, each state is OLGX's to the pixel.
  It asks for Lucida Sans, OpenWindows' face, and uses the sans font where
  that isn't installed.
- **Adwaita**, the look of GNOME 48's apps, from libadwaita 1.7.6's
  stylesheet (facts only, `CREDITS.md`): controls are flat tints of the
  text color with no border, 34 pixels high with corners of radius 9;
  cards and boxed lists have a radius of 12, and popovers, dialogs and
  windows 15. A window's title bar is a header bar, flat as in
  libadwaita's toolbar view or raised (`adwaita-header`), with its title
  in bold in the middle. As GNOME lays out the buttons, there is only a
  close button: a double click on the title maximizes the window, the
  window's menu minimizes it, and `adwaita-window-buttons` shows all three
  buttons. Segmented choices and tabs are toggle groups, a stepper is a
  spin button, and scroll bars are overlay scroll bars that show under the
  pointer. Its palette is `adwaita`, or `adwaita-dark` where the desktop
  prefers dark (`palette-dark`, which Settings shows as Dark palette); its
  text is Cantarell, GNOME's 11 pt as 15 pixels. It is the look of a host
  app on GNOME ([APPS.md](APPS.md)), where it draws only the app's
  windows.
- **GNOME**: Adwaita's windows on GNOME Shell 48.7's desktop (from its
  stylesheet, facts only), dark, as the Shell stays unless one prefers
  light. It has a black top bar with the Activities dots and the clock,
  the Shell's menus for the desktop's own menus and popovers for a
  window's, and notices as the Shell's banners at the top. GNOME has no
  taskbar, so the windows are shown in a dash at the bottom, as the
  overview shows them.
- **Mac** and **Windows**, as their names say.

Interlisp, Genera, OPEN LOOK and Adwaita each bring the palette of the
same name and choose a wallpaper; the CADR and GNOME take their parents',
and Mac and Windows keep the built-in Tokyo Night palette and gradient
wallpaper. Our own styles (Cons, Curses, Draft, Fold, Halo, Lambda,
Reticle, Slab and Spine) choose their feel where it suits them: Fold
folds a window up to its title on a double click, Lambda rolls a window
up into its tab when the wheel turns over the title, Halo and Reticle
show scroll bars only under the pointer, Draft drags an outline drawn as
a technical drawing with the live size on it, Reticle drags only its
brackets, and Curses flashes the whole screen for the bell and boxes menu
entries.

## Palettes and wallpapers

A palette is a set of named colors; a wallpaper is a fill for the
desktop. Both are defined as an app is with `define-app`: a name, a
title, then what defines it:

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

Define one again and the new definition takes the old one's place. To
keep one, put it in a file of its own under `~/.schevana.d/palettes/` or
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

A font role (`'ui`, `'mono`, `'title`, `'heading`, `'big`, and variants
such as `'ui-bold`, `'ui-small`, `'ui-italic` and `'mono-bold`) is a rule
that makes its font from four settings: `ui-font`, `ui-font-size`,
`mono-font` and `mono-font-size`. A style changes a role by setting it.
The kit's shared sizes (`control-height`, `gap`, `pad`, ...) are rules
computed from the fonts too, and title bars and the desktop's bars take
the larger of their own setting and the height their text needs, so the
desktop stays usable at text sizes from 9 to 36 px.

Layout is in logical pixels, and what is drawn is that size times the
screen's scale. Text and shapes are drawn from outlines at full
resolution, and a text measures the same at any scale. The scale follows
the desktop's; `(set-theme! 'scale 200)` sets it in percent, and 0 makes
it follow the desktop again.

## How it feels

How a desktop behaves, beyond how it draws, is settings too:

```scheme
(set-theme! 'title-double-click 'shade)    ; a double click rolls it up
(set-theme! 'drag-feedback 'outline)       ; drag an outline, not the window
(set-theme! 'raise-on-click #f)
(override! 'mouse-doc #t)                  ; what the buttons do, in the top bar
(reset-style! 'title-double-click 'drag-feedback 'raise-on-click)
(override! 'mouse-doc)
```

Among them are `title-double-click` (`maximize`, `shade`, `none`),
`title-wheel`, `drag-feedback` (`live`, `outline`), `frame-edge` and
`frame-corner` (the resize edges), `raise-on-click`, `menu-choose`
(`click`, `release`), `launcher-form` (`menu`, `grid`), `scrollbar-side`
and `scrollbar-show`, and the bell
(`bell`: `none`, `screen` or `window`), which `(bell)` rings. A style
chooses each of them; the built-in styles show what they can do.
