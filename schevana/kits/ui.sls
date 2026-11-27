;;; (schevana kits ui) — immediate-mode widgets.
;;;
;;; Widgets draw themselves during 'draw and record hit regions (with an
;;; id) in a ui object; the window's handlers ask the ui object what was
;;; hit. There is no widget tree: the draw procedure is the layout.
;;;
;;;   (define ui (make-ui))
;;;   (apply open-window "Demo"
;;;     'draw (lambda (win w h)
;;;             (ui-begin! ui)
;;;             (ui-button ui 'hi 20 20 120 28 "Say hi"
;;;                        (lambda () (notify "hi")))
;;;             (ui-end! ui w h))
;;;     (ui-handlers ui))
;;;
;;; The seam: each kind of widget draws through one ui-draw-KIND procedure,
;;; which is given its rectangle, its state as a list of flags (hover,
;;; pressed, focused, selected, ...) and its data. Only these procedures
;;; decide colors, fonts, radii and paddings, and they read nothing else, so
;;; any state can be drawn from made-up flags. A widget's size comes from
;;; its ui-KIND-size procedure, which the layout asks, and the places of its
;;; pieces come from its ui-KIND-areas, which both its drawing and its
;;; clicks read. Behavior (events, focus, editing) never draws. Each
;;; ui-draw-KIND, ui-KIND-size and ui-KIND-areas procedure is a part
;;; (define-part, in (schevana core theme)): a style replaces it by its
;;; key, and the shared numbers are settings. A container draws its inside
;;; in its own place (with-place): a text box in 'field, a table or tree in
;;; 'list, a dialog or calendar in 'dialog, a tooltip in 'tooltip.
;;; tests/sources.ss checks the seam.
;;;
;;; Keyboard focus: one widget per ui has the focus. A click focuses a
;;; widget that takes typing; Tab and Shift+Tab go through the widgets in
;;; draw order; Escape takes the focus away. Text editing is pure ((schevana
;;; kits edit)): it needs no window.

(library (schevana kits ui)
  (export)
  (import (chezscheme) (only (schevana base) library-layer))

  (library-layer kits)

  ;; the parts' names that the world and the other layers use, as this
  ;; library's own
  (export
   (import
    (only (schevana kits ui base) ui-region-x ui-region-y ui-region-h
          ui-region-frame ui-state-mx ui-state-my ui-state-reveal
          ui-state-reveal-set! make-ui ui-memo ui-memo! ui-forget! ui-tip-ms
          ui-region! ui-area ui-region-in? ui-find ui-hover? ui-active?
          ui-flags ui-focus! ui-focused ui-edit ui-caret ui-due! ui-frame
          ui-stale! ui-pointer ui-mouse-down ui-mouse-move ui-mouse-up
          ui-wheel ui-handlers ui-pressable! ui-begin! ui-later! ui-disabled
          ui-end! ui-menu-open! ui-menu-open-tag ui-open-menu!
          ui-open-text-menu! ui-open-modal ui-control-height ui-glyph-size
          ui-small-glyph-size ui-gap ui-pad ui-popup-place ui-flow ui-toolbar
          ui-italic-of ui-draw-focus ui-draw-focus* ui-draw-field
          ui-draw-field* ui-fade ui-draw-glyph ui-draw-glyph* ui-frame-glyph
          ui-label-font ui-label-text ui-draw-label ui-draw-label*
          ui-label-size ui-label-size* ui-label-lines ui-wrap-lines
          ui-draw-surface ui-draw-surface* ui-surface-well-ring ui-text-y
          ui-text-y* ui-scroll ui-scroll-wide ui-scrollbar-shows? ui-scrollbar
          ui-scrollbar-across ui-reveal! ui-scrollbar-width ui-scrollbar-inset
          ui-frame-scrollbar ui-scrollbar-areas ui-scrollbar-areas*
          ui-draw-scrollbar ui-draw-scrollbar* ui-draw-panel ui-draw-panel*
          ui-draw-highlight ui-draw-highlight* ui-draw-highlight-over
          ui-draw-highlight-over* ui-draw-separator ui-draw-separator*
          ui-card-radius ui-card-radius* ui-draw-card ui-draw-card*
          ui-card-pad ui-card-pad* ui-panel-pad ui-panel-pad* ui-tooltip-lines
          ui-tooltip-size ui-tooltip-size* ui-draw-tooltip ui-draw-tooltip*
          ui-draw-scrim ui-draw-scrim*)
    (only (schevana kits ui controls) ui-button ui-joined-span
          ui-button-radius ui-linked ui-draw-button ui-draw-button*
          ui-button-size ui-button-size* ui-segmented ui-stepper-areas
          ui-stepper-areas* ui-breadcrumbs ui-nav ui-draw-nav-row
          ui-draw-nav-row* ui-slider ui-slider-height ui-draw-slider
          ui-draw-slider* ui-checkbox ui-toggle ui-checkbox-box
          ui-draw-checkbox ui-draw-checkbox* ui-checkbox-size
          ui-checkbox-size* ui-live-badge ui-live-badge-back
          ui-live-badge-mark ui-live-badge-size ui-live-badge-size*
          ui-draw-live-badge ui-draw-live-badge* ui-toggle-track
          ui-toggle-track* ui-draw-toggle ui-draw-toggle* ui-toggle-size
          ui-toggle-size* ui-radio ui-radio-text-x ui-radio-size
          ui-radio-size* ui-draw-radio ui-draw-radio* ui-tabs ui-draw-tab
          ui-draw-tab* ui-tabs-size ui-tabs-size* ui-title-icon ui-icon-grid
          ui-icon-ink ui-draw-app-icon ui-draw-window-icon ui-draw-app-tile
          ui-draw-app-tile*
          ui-draw-env-icon ui-draw-env-icon* ui-busy-frame-ms ui-busy-size
          ui-busy-size* ui-draw-busy ui-draw-busy* ui-initials ui-avatar-size
          ui-avatar-size* ui-draw-avatar ui-draw-avatar* ui-draw-progress
          ui-draw-progress* ui-progress-height ui-mark-size ui-draw-mark
          ui-draw-mark* ui-draw-due ui-draw-due*)
    (only (schevana kits ui text) ui-date->day ui-day->date ui-days-in-month
          ui-today ui-month-names ui-date-label ui-next-midnight ui-stepper
          ui-text-box-top ui-text-box-areas ui-text-box-areas*
          ui-text-box-inset ui-text-box-size ui-text-box-size*
          ui-text-area-size ui-text-area-size* ui-text-field ui-text-area
          ui-draw-text-box* ui-draw-suggestion ui-draw-suggestion* ui-rank
          ui-suggestions ui-draw-chip ui-draw-chip* ui-chip-size ui-chip-size*
          ui-chip-areas ui-chip-areas* ui-chip-input ui-chip-input-areas
          ui-chip-input-areas* ui-chip-input-size ui-chip-input-size* ui-chips
          ui-chips-height ui-dropdown ui-draw-dropdown ui-draw-dropdown*
          ui-dropdown-size ui-dropdown-size* ui-date-field ui-calendar-size
          ui-calendar-size* ui-calendar-areas ui-calendar-areas*
          ui-draw-calendar ui-draw-calendar* ui-draw-day ui-draw-day*)
    (only (schevana kits ui lists) ui-split ui-split-stacked ui-draw-split
          ui-draw-split* ui-menu-grid ui-draw-menu-grid-panel*
          ui-draw-menu-grid-heading* ui-draw-menu-grid-item* ui-choice-grid
          ui-draw-choice-grid-label* ui-draw-choice-grid-cell* ui-keycap
          ui-draw-keycap* ui-inline-choices ui-draw-inline-choice*
          ui-inline-choice-size* ui-side-panel-toggle! ui-side-panel
          ui-side-panel-button ui-table-room ui-table-fit ui-table
          ui-table-step ui-table-page ui-table-columns ui-table-header-height
          ui-table-row-height ui-table-cell-inset ui-table-cell-inset*
          ui-draw-cell ui-draw-cell* ui-draw-table-header
          ui-draw-table-header* ui-draw-table-divider ui-draw-table-divider*
          ui-draw-table-row ui-draw-table-row* ui-tree-states ui-tree-expand!
          ui-tree-key ui-tree ui-tree-areas ui-tree-areas* ui-draw-tree-row
          ui-draw-tree-row* ui-draw-dim ui-draw-dim* ui-rows ui-rows-height
          ui-switch-row ui-check-row ui-entry-row ui-rows-spacing
          ui-rows-spacing* ui-row-height ui-row-height* ui-row-areas
          ui-row-areas* ui-add-row-height ui-add-row-height* ui-draw-add-row
          ui-draw-add-row* ui-rows-radius ui-rows-radius* ui-draw-rows
          ui-draw-rows* ui-draw-row ui-draw-row*)
    (only (schevana kits ui charts) ui-bar-chart ui-bar-chart-areas*
          ui-bar-chart-bar ui-draw-bar-chart* ui-draw-flame-box* ui-flame
          ui-draw-treemap-box* ui-treemap ui-draw-source-surface*
          ui-draw-source-line* ui-source ui-stream-rows ui-stream-sent
          ui-stream-new ui-stream-restart! ui-stream-resend!
          ui-stream-release! ui-stream-send! ui-stream-lane* ui-stream-room
          ui-stream-areas* ui-stream-count ui-stream-layout ui-draw-stream*
          ui-stream ui-draw-sparkline ui-draw-sparkline* ui-draw-line-chart
          ui-draw-line-chart* ui-draw-legend ui-draw-legend* ui-legend-size
          ui-legend-size*)
    (only (schevana kits ui pages) ui-board-header-height
          ui-board-header-height* ui-board-column-insets
          ui-board-column-insets* ui-board-card-insets ui-board-card-insets*
          ui-draw-board-column ui-draw-board-column* ui-draw-board-slot
          ui-draw-board-slot* ui-draw-board-link ui-draw-board-link* ui-form
          ui-form-height ui-status-page ui-status-page-areas
          ui-status-page-areas* ui-draw-status-page ui-draw-status-page*
          ui-banner ui-banner-height ui-banner-height* ui-banner-areas
          ui-banner-areas* ui-draw-banner ui-draw-banner* ui-dialog ui-sheet
          ui-dialog-lines ui-dialog-size ui-dialog-size* ui-dialog-areas
          ui-dialog-areas* ui-draw-dialog ui-draw-dialog*))))
