;;; (schevana styles adwaita) — the look of GNOME's apps: libadwaita
;;; 1.7.6's widgets and windows, as GNOME 48 draws them with the blue
;;; accent, in its light style (the palette adwaita) or its dark one
;;; (adwaita-dark, which a desktop that prefers dark gets). GNOME Shell's
;;; desktop around them belongs to a separate style, GNOME ((schevana styles
;;; gnome)): a program that takes this look (a host app) has GNOME's own
;;; Shell around its window. Facts only, from libadwaita's stylesheet
;;; (LGPL-2.1+) and GNOME Shell's (GPL-2.0+): sizes, radii, colors and
;;; alphas, each cited as file:line at those tags, libadwaita's under
;;; src/stylesheet/ (adw-…c files under src/), and the Shell's under
;;; data/theme/gnome-shell-sass/, marked shell. No SCSS, icon or image is
;;; copied: the glyphs are drawn here from their geometry.
;;;
;;; Controls are flat tints of the text color, 10 % at rest, 15 % under the
;;; pointer and 30 % pressed, with no border or bevel; they are 34 high and
;;; 9 round, cards and boxed lists are 12 round, and popovers, dialogs and
;;; windows 15. A window is a libadwaita window: its title bar is a header
;;; bar 46 high, with the title bold in the middle and, as GNOME lays out
;;; its buttons ("appmenu:close"), only a close button, a 24-pixel circle.
;;; A double click on the title maximizes the window, its menu (a right
;;; click on the title) minimizes it, and adwaita-window-buttons all shows
;;; minimize and maximize too, as GNOME Tweaks does.
;;;
;;; The style's parts are in schevana/styles/adwaita/, each a library
;;; this one imports: colors (GNOME's em, a color's luma, the standalone
;;; colors), text (as GTK sets a label), window (the header bar and its
;;; buttons), controls, fields, popups and pages. This library keeps what
;;; registers as it loads: the colors' settings and the style.

(library (schevana styles adwaita)
  (export
    adwaita-add-row adwaita-add-row-height adwaita-avatar adwaita-banner
    adwaita-banner-height adwaita-busy adwaita-button adwaita-button-size
    adwaita-calendar adwaita-card adwaita-card-radius adwaita-checkbox
    adwaita-checkbox-size adwaita-chip adwaita-chip-size adwaita-day
    adwaita-dialog adwaita-dialog-areas adwaita-dialog-size adwaita-draw-over
    adwaita-draw-under adwaita-dropdown adwaita-dropdown-size adwaita-em
    adwaita-field adwaita-focus adwaita-highlight adwaita-insets adwaita-label
    adwaita-live-badge adwaita-nav-row adwaita-panel adwaita-progress
    adwaita-radio adwaita-radio-size adwaita-radius adwaita-regions
    adwaita-ring adwaita-row adwaita-row-areas adwaita-row-height adwaita-rows
    adwaita-rows-radius adwaita-rows-spacing adwaita-scrim adwaita-scrollbar
    adwaita-scrollbar-areas adwaita-separator adwaita-slider adwaita-split
    adwaita-status-page adwaita-status-page-areas adwaita-stepper-areas
    adwaita-suggestion adwaita-surface adwaita-tab adwaita-table-cell-inset
    adwaita-table-divider adwaita-table-header adwaita-table-row
    adwaita-tabs-size adwaita-text-box-areas adwaita-text-y adwaita-toggle
    adwaita-toggle-size adwaita-toggle-track adwaita-tooltip
    adwaita-tooltip-size)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) alpha color-default! define-style
                font-line-height mix theme theme-default! theme-font-rule
                theme-rule)
          (schevana styles adwaita colors)
          (schevana styles adwaita text)
          (schevana styles adwaita window)
          (schevana styles adwaita controls)
          (schevana styles adwaita fields)
          (schevana styles adwaita popups)
          (schevana styles adwaita pages))

  (library-layer looks)

  ;; The theme keys of Adwaita's own, with their defaults.
  (at-load
   ;; The dark style is a palette whose window is dark.
   (theme-default! 'adwaita-dark (theme-rule (< (adwaita-luma 'bg-1) 0.5)))

   ;; The surfaces, which the Adwaita palettes give exactly
   ;; (_defaults.scss:39-88); under another palette, its window's color is
   ;; lightened as GNOME's dark style lightens it: a header bar by 5 % of
   ;; white, a card by 8 %, a popover by 10 %, and a sidebar by a step
   ;; toward the text.
   (color-default! 'adwaita-headerbar (theme-rule (mix 'bg-1 #xffffff 0.05)))
   (color-default! 'adwaita-card (theme-rule (mix 'bg-1 #xffffff 0.08)))
   (color-default! 'adwaita-popover (theme-rule (mix 'bg-1 #xffffff 0.1)))
   (color-default! 'adwaita-dialog
                   (theme-rule (adwaita-by-style (theme 'bg-1)
                                                 (theme 'adwaita-popover))))
   (color-default! 'adwaita-sidebar (theme-rule (mix 'bg-1 'text 0.06)))
   ;; A knob: white mixed 80 % into the view (_colors.scss:98).
   (color-default! 'adwaita-slider (theme-rule (mix #xffffff 'bg-0 0.2)))
   (color-default! 'adwaita-destructive (theme-rule (theme 'red)))
   ;; The accent and the destructive red as text (_defaults.scss:25-36):
   ;; the accent's is GNOME's link color (_colors.scss:79), and its focus
   ;; ring's color.
   (color-default! 'adwaita-link
                   (theme-rule (adwaita-standalone 'accent (adwaita-dark?))))
   (color-default! 'adwaita-destructive-ink
                   (theme-rule (adwaita-standalone 'adwaita-destructive
                                                   (adwaita-dark?))))
   ;; A toggle group's chosen toggle (_defaults.scss:113-119).
   (color-default! 'adwaita-toggle
                   (theme-rule (adwaita-by-style #xffffff
                                                 (alpha #xffffff 0.2))))
   ;; The shades: a header bar's line (_defaults.scss:52), a boxed list's
   ;; line between rows (71), a sidebar's border (60), and what dims the
   ;; window under a dialog, which is the shade at twice its alpha (87,
   ;; widgets/_dialogs.scss:72-74).
   (color-default! 'adwaita-headerbar-shade
                   (theme-rule (alpha #x000006 (adwaita-by-style 0.12 0.36))))
   (color-default! 'adwaita-card-shade
                   (theme-rule (alpha #x000006 (adwaita-by-style 0.07 0.36))))
   (color-default! 'adwaita-sidebar-border
                   (theme-rule (alpha #x000006 (adwaita-by-style 0.07 0.36))))
   (color-default! 'adwaita-dim
                   (theme-rule (alpha #x000006 (adwaita-by-style 0.14 0.5))))
   ;; An overlay scroll bar's outline (_defaults.scss:88).
   (color-default! 'adwaita-scrollbar-outline
                   (theme-rule (adwaita-by-style #xffffff
                                                 (alpha #x00000c 0.95))))
   ;; A tooltip's (widgets/_tooltip.scss:5), the same in both styles.
   (color-default! 'adwaita-tooltip (alpha #x000006 0.8))
   ;; A toast's, the same in both styles (_colors.scss:106).
   (color-default! 'adwaita-toast #x505053)
   ;; GNOME Shell's dark style: its menus' color, text, dimmed text (the fg
   ;; mixed half into the bg) and border (shell _colors.scss:12-13, 39,
   ;; 52); a menu item under the pointer and pressed (widgets/
   ;; _popovers.scss:5, _drawing.scss:381-390); a notification's card
   ;; (_message-list.scss:94); and the dash and its tiles, lighter under the
   ;; pointer and while chosen (_colors.scss:49, widgets/_dash.scss:57-68).
   (color-default! 'adwaita-shell-bg #x36363a)
   (color-default! 'adwaita-shell-text #xffffff)
   (color-default! 'adwaita-shell-dim #x9b9b9d)
   (color-default! 'adwaita-shell-border #x424247)
   (color-default! 'adwaita-shell-hover #x53535a)
   (color-default! 'adwaita-shell-pressed #x58585f)
   (color-default! 'adwaita-shell-card #x54545a)
   (color-default! 'adwaita-dash #x38383b)
   (color-default! 'adwaita-dash-hover #x49494d)
   (color-default! 'adwaita-dash-checked #x4c4c4f)
   (color-default! 'adwaita-dash-text #xfafafb)
   ;; The overview behind the Shell's app grid, the system's base color
   ;; (shell _colors.scss:20, widgets/_overview.scss:7-9); a tile on it under
   ;; the pointer, a flat button lightened 7 % (widgets/_app-grid.scss:21-25,
   ;; _drawing.scss:160-196, 342-371); and the search entry, the system's
   ;; text mixed 9 % into its bg (_common.scss:337-345, _drawing.scss:85-129,
   ;; _default-colors.scss:33, _colors.scss:46).
   (color-default! 'adwaita-overview #x222226)
   (color-default! 'adwaita-overview-hover #x333339)
   (color-default! 'adwaita-overview-entry #x404045)

   ;; The style's own settings: a title-1 text, 181 % bold (widgets/
   ;; _labels.scss:35-38), for a status page; the radius of a button (9:
   ;; _common.scss:8), 12 in an alert, which a dialog's place gives; the
   ;; header bar, flat as a toolbar view has it, or raised (widgets/
   ;; _toolbars.scss:259-314); and which window buttons are shown.
   (theme-default! 'adwaita-title-1 (theme-font-rule 'ui 12 'bold))
   (theme-default! 'adwaita-button-radius 9)
   (theme-default! 'adwaita-header 'flat)
   (theme-default! 'adwaita-window-buttons 'close))

  ;;; ------------------------------------------------------------------

  (at-load
   (define-style adwaita "Adwaita"
     'options '(palette
                (palette-dark "Dark palette" palette)
                accent
                wallpaper
                ui-font
                ui-font-size
                mono-font
                mono-font-size
                shadow
                (adwaita-header "Header bar" (("Flat" . flat)
                                              ("Raised" . raised)))
                (adwaita-window-buttons "Window buttons"
                                        (("Close" . close)
                                         ("All three" . all))))
     'palette 'adwaita
     'palette-dark 'adwaita-dark
     'wallpaper 'gradient
     ;; GNOME's text, as on this machine: Cantarell 11, 15 here
     ;; (adwaita-em); a caption 82 % (widgets/_labels.scss:63-71)
     'ui-font "Cantarell"
     'ui-font-size 15
     'mono-font "monospace"
     'mono-font-size 15
     'ui-small (theme-font-rule 'ui -3)
     'ui-small-bold (theme-font-rule 'ui -3 'bold)
     'corner-radius 15
     'shadow 24
     ;; a control's text and 5 above and below it, at least 34 (widgets/
     ;; _buttons.scss:20-22)
     'control-height (theme-rule (+ 10 (max 24 (round (font-line-height
                                                        'ui)))))
     'title-height (theme-rule (adwaita-header-height))
     'glyph-size 16
     'small-glyph-size 12
     ;; GNOME spaces by 6 between neighbors, 12 in from a box's edge
     'gap 6
     'pad 12
     'slider-height (theme-rule (theme 'control-height))
     'progress-height 8
     'segmented-gap 0
     'stepper-glyphs '(minus . plus)
     'scrollbar-width 16
     'scrollbar-show 'hover
     'surface-well-ring 1
     ;; a column view's heading: a button, at least 24 high
     ;; (widgets/_buttons.scss:20), with its caption set solid and 3 above
     ;; and below; a cell: its text and 8 above and below
     ;; (widgets/_column-view.scss:12-20, 72-79)
     'table-header-height
     (theme-rule (+ 6 (max 24 (round (font-line-height 'ui-small-bold)))))
     'table-row-height (theme-rule (round (+ 16 (font-line-height 'ui))))
     'table-dividers 'handle
     'label-section-font 'ui-bold
     'label-section-upcase #f
     'label-group-font 'ui-bold
     'text-caret-width 1
     'text-caret-color 'text
     'text-placeholder-color 'text-dim
     'status-title-font 'adwaita-title-1
     'busy-frame-ms 50
     'title-double-click 'maximize
     'places '((dialog adwaita-button-radius 12))
     ;; the window
     'frame-insets 'adwaita-insets
     'frame-regions 'adwaita-regions
     'frame-radius 'adwaita-radius
     'frame-under 'adwaita-draw-under
     'frame-over 'adwaita-draw-over
     ;; the widgets
     'ui-draw-focus 'adwaita-focus
     'ui-draw-field 'adwaita-field
     'ui-draw-button 'adwaita-button
     'ui-button-size 'adwaita-button-size
     'ui-draw-nav-row 'adwaita-nav-row
     'ui-draw-slider 'adwaita-slider
     'ui-draw-checkbox 'adwaita-checkbox
     'ui-checkbox-size 'adwaita-checkbox-size
     'ui-draw-live-badge 'adwaita-live-badge
     'ui-toggle-track 'adwaita-toggle-track
     'ui-draw-toggle 'adwaita-toggle
     'ui-toggle-size 'adwaita-toggle-size
     'ui-radio-size 'adwaita-radio-size
     'ui-draw-radio 'adwaita-radio
     'ui-draw-tab 'adwaita-tab
     'ui-tabs-size 'adwaita-tabs-size
     'ui-draw-label 'adwaita-label
     'ui-text-y 'adwaita-text-y
     'ui-draw-surface 'adwaita-surface
     'ui-text-box-areas 'adwaita-text-box-areas
     'ui-draw-suggestion 'adwaita-suggestion
     'ui-scrollbar-areas 'adwaita-scrollbar-areas
     'ui-draw-scrollbar 'adwaita-scrollbar
     'ui-draw-busy 'adwaita-busy
     'ui-draw-split 'adwaita-split
     'ui-table-cell-inset 'adwaita-table-cell-inset
     'ui-draw-table-header 'adwaita-table-header
     'ui-draw-table-divider 'adwaita-table-divider
     'ui-draw-table-row 'adwaita-table-row
     'ui-draw-chip 'adwaita-chip
     'ui-chip-size 'adwaita-chip-size
     'ui-draw-avatar 'adwaita-avatar
     'ui-draw-progress 'adwaita-progress
     'ui-draw-panel 'adwaita-panel
     'ui-draw-highlight 'adwaita-highlight
     'ui-draw-separator 'adwaita-separator
     'ui-draw-card 'adwaita-card
     'ui-card-radius 'adwaita-card-radius
     'ui-tooltip-size 'adwaita-tooltip-size
     'ui-draw-tooltip 'adwaita-tooltip
     'ui-draw-dropdown 'adwaita-dropdown
     'ui-dropdown-size 'adwaita-dropdown-size
     'ui-draw-calendar 'adwaita-calendar
     'ui-draw-day 'adwaita-day
     'ui-dialog-size 'adwaita-dialog-size
     'ui-dialog-areas 'adwaita-dialog-areas
     'ui-draw-scrim 'adwaita-scrim
     'ui-draw-dialog 'adwaita-dialog
     'ui-stepper-areas 'adwaita-stepper-areas
     'ui-rows-spacing 'adwaita-rows-spacing
     'ui-row-height 'adwaita-row-height
     'ui-row-areas 'adwaita-row-areas
     'ui-rows-radius 'adwaita-rows-radius
     'ui-draw-rows 'adwaita-rows
     'ui-draw-row 'adwaita-row
     'ui-add-row-height 'adwaita-add-row-height
     'ui-draw-add-row 'adwaita-add-row
     'ui-status-page-areas 'adwaita-status-page-areas
     'ui-draw-status-page 'adwaita-status-page
     'ui-banner-height 'adwaita-banner-height
     'ui-draw-banner 'adwaita-banner)))
