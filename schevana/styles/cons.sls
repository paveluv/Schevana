;;; (schevana styles cons) — the Cons window style. The title bar is a
;;; box-and-pointer diagram, drawn the way SICP draws a list: the window is
;;; ("Title" - +). Its first pair holds the title in its car and points to
;;; two more pairs, whose cars minimize and maximize; the chain ends, as
;;; every list does, in the nil slash, and clicking that end of the list
;;; closes the window. It is drawn, not painted: outlined cells on the
;;; window's own background, in accent ink with a bolder stroke while the
;;; window has the focus, and in faint ink when it does not. Under the
;;; mouse a cell fills with ink; nil fills red, with its slash crossed out.
;;;
;;; The idea continues below the title bar: everything on the screen is
;;; Lisp data, drawn the same way (the widgets, popups, board and desktop
;;; parts). A button is a cell with its word in it, a checkbox is a cell
;;; holding #t or #f, a text box is a string in quotes, and a dropdown is a
;;; pair whose pointer leaves downward. Tabs, chips, a column's cards,
;;; menus, toasts, the taskbar and a dialog are chains ending in nil, and in
;;; a dialog, as in a window, nil is where you cancel.
;;;
;;; The style's parts are in schevana/styles/cons/, each a library this
;;; one imports: cells (the cons cell and the window as a chain of
;;; cells), widgets, popups, board (a board's columns and cards) and
;;; desktop (the menus, the bars, toasts and the wallpaper). This library
;;; keeps what registers as it loads: the style and its settings.

(library (schevana styles cons)
  (export
    cons-avatar cons-board-card-insets cons-board-column
    cons-board-column-insets cons-board-header-height cons-board-link
    cons-board-slot cons-button cons-button-size cons-card cons-card-pad
    cons-checkbox cons-checkbox-size cons-chip cons-chip-areas
    cons-chip-input-areas cons-chip-size cons-day cons-dialog cons-dialog-areas
    cons-dialog-size cons-draw-menu cons-draw-over cons-draw-taskbar
    cons-draw-toasts cons-draw-topbar cons-draw-under cons-draw-wallpaper
    cons-dropdown cons-dropdown-size cons-field cons-focus cons-highlight
    cons-menu-areas cons-mouse-doc-text cons-panel cons-panel-pad cons-progress
    cons-regions cons-scrim cons-scrollbar cons-scrollbar-areas cons-separator
    cons-slider cons-surface cons-tab cons-table-cell-inset cons-table-header
    cons-table-row cons-tabs-size cons-taskbar-areas cons-text-box-areas
    cons-toast-boxes cons-toggle cons-tooltip cons-tooltip-size cons-tree-row)
  (import (chezscheme)
          (only (schevana base) at-load library-layer)
          (only (schevana core) color-default! common-options define-style theme
                theme-rule)
          (only (schevana styles cons cells) cons-cell cons-draw-over
                cons-draw-under cons-regions)
          (only (schevana styles cons widgets) cons-arrow cons-button
                cons-button-size cons-card cons-checkbox cons-checkbox-size
                cons-chip cons-chip-areas cons-chip-input-areas cons-chip-size
                cons-dropdown cons-dropdown-size cons-field cons-focus
                cons-highlight cons-panel cons-progress cons-scrollbar
                cons-scrollbar-areas cons-separator cons-slider cons-space
                cons-surface cons-tab cons-table-header cons-table-row
                cons-tabs-size cons-text-box-areas cons-toggle cons-tree-row)
          (only (schevana styles cons popups) cons-avatar cons-day cons-dialog
                cons-dialog-areas cons-dialog-size cons-scrim cons-tooltip
                cons-tooltip-size)
          (only (schevana styles cons board) cons-board-card-insets
                cons-board-column cons-board-column-insets
                cons-board-header-height cons-board-link cons-board-slot
                cons-card-pad cons-panel-pad cons-table-cell-inset)
          (only (schevana styles cons desktop) cons-draw-menu cons-draw-taskbar
                cons-draw-toasts cons-draw-topbar cons-draw-wallpaper
                cons-menu-areas cons-mouse-doc-text cons-taskbar-areas
                cons-toast-boxes))

  (library-layer looks)

  ;;; ------------------------------------------------------------------
  ;;; the rest of the screen: Lisp data, drawn as the title is
  ;;; Cells are outlined boxes on the background, in the plain ink. What is
  ;;; focused, chosen or the default has the bold stroke in accent ink, as
  ;;; a focused window's chain does; what is disabled, a hint, or elsewhere
  ;;; is faint. A cell fills with its ink under the mouse, its word then in
  ;;; the paper's color, and at alpha 0.6 while pressed, as the title's
  ;;; cells do. Literals look like literals, in the code font: #t and #f,
  ;;; strings in quotes, the empty list as (). The chain is drawn where it
  ;;; reads best (tabs, chips, a column's cards, menus, toasts, the taskbar,
  ;;; a dialog); the rest are plain cells, so that the diagram is not all
  ;;; arrows.

  ;; The plain ink is a color of its own, dim text by default, which you
  ;; may change.
  (at-load
   (color-default! 'cons-ink (theme-rule (theme 'text-dim))))

  (at-load
   (define-style cons "Cons"
     ;; square, and so is everything drawn in it (rec-radius); it has
     ;; every common option except the radius
     'corner-radius 0
     'options (remq 'corner-radius (map car common-options))
     'frame-regions 'cons-regions
     'frame-under 'cons-draw-under
     'frame-over 'cons-draw-over
     ;; the desktop: a flat ground, the world drawn faint on it
     'wallpaper 'flat
     'draw-wallpaper 'cons-draw-wallpaper
     ;; drawn, not painted: cards and panels on the window's own background
     'bg-2 (theme-rule (theme 'bg-1))
     'surface-well-ring 1
     ;; the spacing (see above): g between neighbors, the pad as a window's
     ;; margin, a scroll bar a thumb g wide and g from its edge, g clear of
     ;; content
     'gap (theme-rule (cons-space))
     'pad (theme-rule (* 2 (cons-space)))
     'scrollbar-width (theme-rule (* 2 (cons-space)))
     'scrollbar-margin (theme-rule (cons-space))
     'text-selection 'underline
     ;; the bars: the mouse documentation as data in the top bar, the
     ;; windows as a list in the taskbar
     'mouse-doc #t
     'mouse-doc-text 'cons-mouse-doc-text
     'draw-topbar 'cons-draw-topbar
     'taskbar-areas 'cons-taskbar-areas
     'draw-taskbar 'cons-draw-taskbar
     'toast-boxes 'cons-toast-boxes
     'draw-toasts 'cons-draw-toasts
     ;; the menus: each entry a pair a cell high and a pointer to the
     ;; next, g inside the menu
     'menu-areas 'cons-menu-areas
     'draw-menu 'cons-draw-menu
     'menu-item-height (theme-rule (+ (cons-cell) (cons-arrow)))
     'menu-separator-height (theme-rule (cons-arrow))
     'menu-pad (theme-rule (cons-space))
     'menu-text-x (theme-rule (cons-space))
     'menu-min-width 150
     'menu-ink 'text
     ;; in a dialog every button is a cell of its chain
     'cons-chain #f
     'places '((dialog cons-chain #t))
     ;; the widgets
     'ui-draw-focus 'cons-focus
     'ui-draw-button 'cons-button
     'ui-button-size 'cons-button-size
     'ui-draw-checkbox 'cons-checkbox
     'ui-checkbox-size 'cons-checkbox-size
     'ui-draw-toggle 'cons-toggle
     'ui-toggle-size 'cons-checkbox-size
     'ui-draw-tab 'cons-tab
     'ui-tabs-size 'cons-tabs-size
     'ui-draw-field 'cons-field
     'ui-text-box-areas 'cons-text-box-areas
     'ui-draw-dropdown 'cons-dropdown
     'ui-dropdown-size 'cons-dropdown-size
     'ui-draw-chip 'cons-chip
     'ui-chip-size 'cons-chip-size
     'ui-chip-areas 'cons-chip-areas
     'ui-chip-input-areas 'cons-chip-input-areas
     'ui-draw-card 'cons-card
     'ui-draw-scrollbar 'cons-scrollbar
     'ui-scrollbar-areas 'cons-scrollbar-areas
     'ui-draw-slider 'cons-slider
     'ui-draw-progress 'cons-progress
     'ui-draw-table-header 'cons-table-header
     'ui-draw-table-row 'cons-table-row
     'ui-draw-tree-row 'cons-tree-row
     'ui-draw-surface 'cons-surface
     'ui-draw-panel 'cons-panel
     'ui-draw-highlight 'cons-highlight
     'ui-draw-separator 'cons-separator
     'ui-draw-tooltip 'cons-tooltip
     'ui-tooltip-size 'cons-tooltip-size
     'ui-draw-dialog 'cons-dialog
     'ui-dialog-size 'cons-dialog-size
     'ui-dialog-areas 'cons-dialog-areas
     'ui-draw-scrim 'cons-scrim
     'ui-draw-day 'cons-day
     'ui-draw-avatar 'cons-avatar
     ;; a board's cards and panels
     'ui-board-column-insets 'cons-board-column-insets
     'ui-board-header-height 'cons-board-header-height
     'ui-card-pad 'cons-card-pad
     'ui-table-cell-inset 'cons-table-cell-inset
     'ui-panel-pad 'cons-panel-pad
     'ui-board-card-insets 'cons-board-card-insets
     'ui-draw-board-link 'cons-board-link
     'ui-draw-board-column 'cons-board-column
     'ui-draw-board-slot 'cons-board-slot)))
