;;; (schevana core) — the core, as the world and a program have it: what
;;; it gives them, each name read-only but the hooks a later layer fills,
;;; and schevana-main, which runs a program on it:
;;;
;;;   (import (chezscheme) (schevana core))
;;;   (schevana-main 'sdl 640 400 #f
;;;     (lambda () (open-window ...)))
;;;
;;; Nothing else of the core's is there to name, and none of its C. A new
;;; name here is a reviewed change; tests/sources.ss names those no file
;;; of the world's uses.

(library (schevana core)
  (export
    ;; core1's thread, the world's environment, the tree, and how a
    ;; program runs
    core1-thread? *world-env* world-value core1-exported
    *schevana-root* *schevana-options* schevana-main
    ;; (schevana core platform): which platform this is, the clocks, the
    ;; system's figures
    platform-fact platform-windowing platform-gpu-api platform-predicates
    platform-process-bytes platform-machine-load now-ns now-ms thread-cpu-ns
    ;; (schevana core theme-table): the settings in effect, which drawing reads
    theme-rule? theme-rule call-with-theme theme theme-keys theme-part
    *pacer-trial* plist-has? plist-remove
    ;; (schevana core processes): processes, errors, toasts, worklets, and
    ;; what is asked of the loop
    proc-wait in-engine? current-proc make-timeout-condition safe-call safely
    *toasts* notify *last-error* report-error! proc proc? proc-id proc-name
    proc-state proc-ticks proc-started proc-wake *procs* spawn procs find-proc
    kill! sleep-ms worklet-base-environment *worklet-environment* worklet?
    worklet define-worklet request-frame! *timers* after
    ;; (schevana core gpu): the GPU's world side: images, buffers, lists,
    ;; computes
    *gpu-bytes-made* *gpu-held-gone* gpu-image-make gpu-image-make-target
    gpu-image-release! gpu-atlas-image gpu-list-new make-gpu-buffer
    gpu-buffer-set! gpu-buffer-release! gpu-buffer-read! *gpu-computes*
    gpu-compute-soon! gpu-buffer-read-then! gpu-compute!
    ;; (schevana core fonts): fonts and text
    font-file-upem font-file-ascender font-file-descender font-file-pages
    font-library-versions make-font*
    *font-specs* font get-font font-advance font-ascent
    font-line-height font-char-width font-ready text-width *glyph-count*
    *atlas-y* *atlas-row* glyph-row-ref font-family font-size font-sized
    font-weight glyph-row-character glyph-row-h glyph-row-left glyph-row-top
    glyph-row-w
    ;; (schevana core draw): drawing: colors, shapes, text, runs and labels
    pi *canvas-w* *canvas-h* *scale* *canvas-ratio* *canvas-pw* *canvas-ph*
    canvas-pixel-width canvas-pixel-height rgb alpha stipple stipple?
    linear-gradient radial-gradient color-rgba mix color-word *rec-labels*
    *rec-label-at* rec-variant record-list! fill-box stroke-box fill-circle
    stroke-circle draw-line draw-polyline fill-polygon invert-box add-box
    draw-shadow draw-text draw-image define-paint fill-shader with-clip
    with-translation with-scale with-turn with-label draw-scale gfx-fragments
    rec-preview! rec-past! drawing->bytes rec-row-head rec-row-paint
    rec-row-words rec-row-x0 rec-row-x1 rec-row-y0 rec-row-y1 rec-box-line
    rec-box-radius rec-glyph-number rec-glyph-pen-x rec-glyph-pen-y
    rec-polygon-count rec-polygon-points rec-segment-width rec-shadow-size
    rec-kind-glyph rec-kind-polygon rec-paint-gradient rec-paint-image
    rec-paint-stipple rec-gradient-radial gradient-row-kind gradient-row-x0
    gradient-row-x1 gradient-row-y0 gradient-row-y1 clip-row-parent
    clip-row-radius clip-row-rx0 clip-row-rx1 clip-row-ry0 clip-row-ry1
    clip-row-words clip-row-x0 clip-row-x1 clip-row-y0 clip-row-y1
    ;; (schevana core pacer): the pacer, the last frames' numbers, and a frame's
    ;; way to the screen
    *frame-ms* *frames-drawn* frame-ring-rows frame-ring-words *frame-ring*
    *frame-ring-n* *pacer-due* *pacer-frame-ns* *pacer-shown?* *pacer-latch*
    *pacer-lead* *pacer-counts* *pacer-aimed* *pacer-floor* *pacer-latch-phase*
    *pacer-depth* *pacer-made* *pacer-late-run* *pacer-late-chain*
    *pacer-gpu-taught* *pacer-between?* pacer-busy-ms pacer-peak-ms! pacer-rate
    pacer-ticks pacer-period pacer-start pacer-trial! pacer-margin screen-bytes
    screen-bytes-then
    ;; (schevana core screen): the screen core0 shows, and what the host's
    ;; desktop knows it by
    system-scale-percent fullscreen? set-fullscreen! toggle-fullscreen!
    screen-set-icon! screen-set-title! screen-set-app-id! screen-set-least!
    *screen-least* screen-system-theme screen-own-frame! screen-own-frame?
    screen-hit-regions! screen-window-action! screen-maximized?
    ;; (schevana core loop) and (schevana core sources): the step, boot,
    ;; sources and reload
    *input-step?* post-core1! schevana-run! quit! schevana-end! uptime-ms
    load-user-init! user-directory schevana-boot! collector-declining?
    source-files *source-texts* keep-source-text! load-file!
    load-user-folders! reload! core1-run core1-boot! look-load!
    world-load-now! *world-later* auto-load! auto-load-forget! auto-loads
    *auto-loads* auto-load-layer world-app-file? world-after-load!
    auto-load-entries library-file-layer path-full add-library-directory!
    ;; (schevana core theme): the theme, styles, palettes, wallpapers and
    ;; parts
    *theme-version* *style-name* *style-changes* *theme-overrides*
    *scale-setting* default-theme color-keys common-options theme-default
    *palettes* define-palette palettes palette-title palette-colors
    *wallpapers* define-wallpaper wallpapers wallpaper-shown fill-wallpaper
    style style-name style-title style-settings *styles* define-style find-style
    styles current-style define-part color-default! theme-default! with-style
    with-place style-changes-of style-chain chain-ref honored? resolve-theme
    frame-over* change-layers! theme-layers-set! set-style! set-theme!
    reset-style! override! theme-overrides set-scale! set-palette! set-accent!
    reset-theme!
    theme-font-rule chrome-height title-height
    ;; (schevana core windows): windows, focus, surfaces and strips
    window window? window-id window-app window-title window-title-set! window-x
    window-x-set! window-y window-y-set! window-w window-w-set! window-h
    window-h-set! window-state window-state-set! window-restore-set!
    window-min-w window-min-h window-handlers window-props window-error
    *windows* *focus* *drag-outline*
    *hover* *mouse-x* *mouse-y* *mouse-button* drag current-window invalidate!
    window-shadow window-extent screen-w screen-h screen-scale point-in?
    surface surface-doc define-surface find-surface surface-call define-strip
    desktop-rect app app-name app-title app-launch *apps*
    define-app apps open-window detached-window new-window-position
    cascade-reset! place-window! windows focused-window visible? maximized?
    find-window window-ref window-set! window-bg in-window-theme window-setting
    frame-insets frame-regions frame-radius frame-bleed content-rect
    window-content-size window-local window-call window-crash!
    window-modal-child focus-window! close-window! minimize-window!
    set-geometry! move-window! resize-window! restore-window! toggle-maximize!
    window-action! shaded? unshade-window! toggle-shade! window-at screen-at
    resize-kinds
    window-region *global-keys* bind-key! window-frame-soon! window-hover
    draw-window*
    ;; (schevana shader): the shader language
    *shader-constants* *shader-helpers* *shader-fields* define-shader-layout
    define-shader-constant define-shader-helpers shader-type shader-tree
    define-compute-shader
    ;; (schevana socket): sockets
    socket-listen socket-accept socket-read socket-write socket-close
    ;; (schevana reload): what a reload of the libraries keeps
    reload-facts
    ;; Given again: core0's ((schevana core0)), which Monitor, the
    ;; Pipeline and inspect read
    core0-app-id gpu-atlas-side core0-flag-names core0-event-name gpu-show-run?
    gpu-run-gone? shader shader-name shader-stage shader-coords shader-params
    shader-source shader-words gpu-list-id gpu-list-labels gpu-list-recorded
    gpu-list-took gpu-image-id gpu-image-w gpu-image-h gpu-image-levels
    gpu-call? gpu-call-shader *gpu-facts* core0-display core0-frame-ns
    core0-hidden? core0-flags core0-error-text core0-step-state
    core0-frame-report core0-window-sizes core0-window-scale clipboard-get
    core0-set-cursor! clipboard-set! core0-refresh-ns! platform-cpu-count
    ;; Given again: the recorder's ((schevana recorder)), which the
    ;; Pipeline reads of a list
    rec-count rec-last-sizes rec-last-copy! rec-last-runs rec-list-copy
    gpu-list-recs-n gpu-list-extras-n gpu-list-runs gpu-list-version
    gpu-list-recs gpu-list-extras rec-recordings rec-pixel-set! rec-image-rows!
    ;; The hooks later layers fill (AGENTS.md, S1): each set by the one
    ;; file that fills it, with what the core calls.
    *profile-span*
    theme-save!
    window-gone!
    screen-event-seen!
    worklet-spread
    ;; And those the windows layer fills, which a program without it fills
    ;; itself (demo rings): what a frame draws, where an event
    ;; goes, what a tick does.
    record-world!
    wm-event!
    wm-tick!)
  (import (chezscheme)
          (only (schevana base) library-layer define-view define-settable)
          (only (schevana shader) *shader-constants* *shader-helpers*
                *shader-fields* define-shader-layout define-shader-constant
                define-shader-helpers shader-type shader-tree
                define-compute-shader shader shader-name shader-stage
                shader-coords shader-params shader-source shader-words)
          (only (schevana socket) socket-listen socket-accept socket-read
                socket-write socket-close)
          (only (schevana reload) reload-facts)
          (only (schevana core0) core0-app-id gpu-atlas-side core0-flag-names
                core0-event-name gpu-show-run? gpu-run-gone? gpu-list-id
                gpu-list-labels gpu-list-recorded gpu-list-took gpu-image-id
                gpu-image-w gpu-image-h gpu-image-levels gpu-call?
                gpu-call-shader *gpu-facts* core0-display core0-frame-ns
                core0-hidden? core0-flags core0-error-text core0-step-state
                core0-frame-report core0-window-sizes core0-window-scale
                clipboard-get core0-set-cursor! clipboard-set! core0-refresh-ns!
                platform-cpu-count)
          (only (schevana recorder) rec-count rec-last-sizes rec-last-copy!
                rec-last-runs rec-list-copy gpu-list-recs-n gpu-list-extras-n
                gpu-list-runs gpu-list-version gpu-list-recs gpu-list-extras
                rec-recordings rec-pixel-set! rec-image-rows!)
          (only (schevana core platform) platform-fact platform-windowing
                platform-gpu-api platform-predicates platform-machine-load
                thread-cpu-ns)
          (only (schevana core theme-table) theme-rule? theme-rule
                call-with-theme theme theme-keys theme-part plist-has?
                plist-remove)
          (only (schevana core processes) core1-thread? proc-wait
                make-timeout-condition safe-call safely proc proc? proc-id
                proc-name proc-state proc-ticks proc-started proc-wake spawn
                procs find-proc kill! sleep-ms worklet-base-environment worklet?
                worklet define-worklet after)
          (only (schevana core gpu) gpu-image-make gpu-image-make-target
                gpu-image-release! gpu-atlas-image gpu-list-new make-gpu-buffer
                gpu-buffer-set! gpu-buffer-release! gpu-buffer-read!
                gpu-compute-soon! gpu-buffer-read-then! gpu-compute!)
          (only (schevana core fonts) font-file-upem font-file-ascender
                font-file-descender font-file-pages
                font-library-versions make-font* font get-font font-advance
                font-ascent font-line-height font-char-width
                font-ready glyph-row-ref font-family font-size font-sized
                font-weight glyph-row-character glyph-row-h glyph-row-left
                glyph-row-top glyph-row-w)
          (only (schevana core draw) pi canvas-pixel-width canvas-pixel-height
                rgb alpha stipple stipple? linear-gradient radial-gradient
                color-rgba mix color-word rec-variant record-list! fill-box
                stroke-box fill-circle stroke-circle draw-line draw-polyline
                fill-polygon invert-box add-box draw-shadow draw-image
                define-paint fill-shader with-clip with-translation with-scale
                with-turn with-label draw-scale gfx-fragments rec-preview!
                rec-past! drawing->bytes rec-row-head rec-row-paint
                rec-row-words rec-row-x0 rec-row-x1 rec-row-y0 rec-row-y1
                rec-box-line rec-box-radius rec-glyph-number rec-glyph-pen-x
                rec-glyph-pen-y rec-polygon-count rec-polygon-points
                rec-segment-width rec-shadow-size rec-kind-glyph
                rec-kind-polygon rec-paint-gradient rec-paint-image
                rec-paint-stipple rec-gradient-radial gradient-row-kind
                gradient-row-x0 gradient-row-x1 gradient-row-y0 gradient-row-y1
                clip-row-parent clip-row-radius clip-row-rx0 clip-row-rx1
                clip-row-ry0 clip-row-ry1 clip-row-words clip-row-x0 clip-row-x1
                clip-row-y0 clip-row-y1)
          (only (schevana core pacer) frame-ring-rows frame-ring-words
                pacer-busy-ms pacer-peak-ms! pacer-rate pacer-ticks pacer-start
                pacer-trial! pacer-margin screen-bytes screen-bytes-then)
          (only (schevana core screen) system-scale-percent fullscreen?
                set-fullscreen! toggle-fullscreen! screen-set-icon!
                screen-set-title! screen-set-app-id! screen-set-least!
                screen-system-theme screen-own-frame! screen-own-frame?
                screen-hit-regions! screen-window-action! screen-maximized?)
          (prefix (only (schevana core screen) *screen-least*) core:)
          (only (schevana core loop) post-core1! schevana-run! quit!
                schevana-end! uptime-ms user-directory schevana-boot!
                collector-declining? core1-run loop-main path-full
                add-library-directory!)
          (only (schevana core theme) common-options theme-default
                define-palette palettes palette-title palette-colors
                define-wallpaper wallpapers wallpaper-shown fill-wallpaper style
                style-name style-title style-settings define-style find-style
                styles current-style define-part color-default! theme-default!
                with-style with-place style-changes-of style-chain chain-ref
                honored? resolve-theme frame-over* change-layers!
                theme-layers-set! set-style! set-theme! reset-style! override!
                theme-overrides set-scale! set-palette! set-accent! reset-theme!
                theme-font-rule chrome-height title-height)
          (only (schevana core windows) window window? window-id window-app
                window-title window-title-set! window-x window-x-set! window-y
                window-y-set! window-w window-w-set! window-h window-h-set!
                window-state window-state-set! window-restore-set!
                window-min-w window-min-h window-handlers window-props
                window-error drag window-shadow
                window-extent screen-w screen-h screen-scale point-in? surface
                surface-doc define-surface find-surface surface-call
                define-strip desktop-rect app app-name app-title app-launch
                define-app apps open-window detached-window
                cascade-reset! place-window! windows focused-window visible?
                maximized? find-window window-ref window-set! window-bg
                in-window-theme window-setting frame-insets frame-regions
                frame-radius frame-bleed content-rect window-content-size
                window-local window-call window-crash! window-modal-child
                focus-window! close-window! minimize-window! set-geometry!
                move-window! resize-window! restore-window! toggle-maximize!
                window-action! shaded? unshade-window! toggle-shade! window-at
                screen-at resize-kinds window-region bind-key!
                window-frame-soon! window-hover draw-window*)
          (only (schevana core sources) core1-exported load-user-init!
                source-files keep-source-text! load-file!
                load-user-folders! reload! core1-boot! program-world!
                look-load! world-load-now! auto-load! auto-load-forget!
                auto-loads auto-load-entries auto-load-layer world-app-file?
                world-after-load! library-file-layer)
          (prefix (only (schevana tree) *schevana-root*) core:)
          (prefix (only (schevana core platform) platform-process-bytes now-ns
                        now-ms) core:)
          (prefix (only (schevana core theme-table) world-value
                        *pacer-trial*) core:)
          (prefix (only (schevana core processes) in-engine? current-proc
                        *toasts* notify *last-error* report-error! *procs*
                        *worklet-environment* request-frame! *timers*
                        *profile-span* worklet-spread) core:)
          (prefix (only (schevana core gpu) *gpu-bytes-made* *gpu-held-gone*
                        *gpu-computes*) core:)
          (prefix (only (schevana core fonts) *font-specs* text-width
                        *glyph-count* *atlas-y* *atlas-row*) core:)
          (prefix (only (schevana core draw) *canvas-w* *canvas-h* *scale*
                        *canvas-ratio* *canvas-pw* *canvas-ph* *rec-labels*
                        *rec-label-at* draw-text) core:)
          (prefix (only (schevana core pacer) *frame-ms* *frames-drawn*
                        *frame-ring* *frame-ring-n* *pacer-due* *pacer-frame-ns*
                        *pacer-shown?* *pacer-latch* *pacer-lead* *pacer-counts*
                        *pacer-aimed* *pacer-floor* *pacer-latch-phase*
                        *pacer-depth* *pacer-made* *pacer-late-run*
                        *pacer-late-chain* *pacer-gpu-taught* *pacer-between?*
                        pacer-period wm-tick! record-world!) core:)
          (prefix (only (schevana core screen) screen-event-seen!) core:)
          (prefix (only (schevana core loop) *input-step?* wm-event!) core:)
          (prefix (only (schevana core theme) *theme-version* *style-name*
                        *style-changes* *theme-overrides* *scale-setting*
                        default-theme color-keys *palettes* *wallpapers*
                        *styles* theme-save!) core:)
          (prefix (only (schevana core windows) *windows* *focus* *drag-outline*
                        *hover* *mouse-x* *mouse-y* *mouse-button*
                        current-window invalidate! *apps* new-window-position
                        *global-keys* window-gone!) core:)
          (prefix (only (schevana core sources) *world-env* *schevana-options*
                        *world-later* *auto-loads* *source-texts*)
                  core:))

  (library-layer core facade)

  ;; A program on the whole core: the loop's main (loop-main), defined
  ;; here so that a program compiled as one carries this library.
  ;; Its "/" is made first (program-world!), from the libraries it loaded.
  (define (schevana-main mode w h full? world . fork?)
    (program-world!)
    (apply loop-main mode w h full? world fork?))

  ;; What the core sets, and the world reads or calls: views.
  (define-view *schevana-root* core:*schevana-root*)
  (define-view *screen-least* core:*screen-least*)
  (define-view *world-later* core:*world-later*)
  (define-view *auto-loads* core:*auto-loads*)
  (define-view platform-process-bytes core:platform-process-bytes)
  (define-view now-ns core:now-ns)
  (define-view now-ms core:now-ms)
  (define-view world-value core:world-value)
  (define-view *pacer-trial* core:*pacer-trial*)
  (define-view in-engine? core:in-engine?)
  (define-view current-proc core:current-proc)
  (define-view *toasts* core:*toasts*)
  (define-view notify core:notify)
  (define-view *last-error* core:*last-error*)
  (define-view report-error! core:report-error!)
  (define-view *procs* core:*procs*)
  (define-view *worklet-environment* core:*worklet-environment*)
  (define-view request-frame! core:request-frame!)
  (define-view *timers* core:*timers*)
  (define-view *gpu-bytes-made* core:*gpu-bytes-made*)
  (define-view *gpu-held-gone* core:*gpu-held-gone*)
  (define-view *gpu-computes* core:*gpu-computes*)
  (define-view *font-specs* core:*font-specs*)
  (define-view text-width core:text-width)
  (define-view *glyph-count* core:*glyph-count*)
  (define-view *atlas-y* core:*atlas-y*)
  (define-view *atlas-row* core:*atlas-row*)
  (define-view *canvas-w* core:*canvas-w*)
  (define-view *canvas-h* core:*canvas-h*)
  (define-view *scale* core:*scale*)
  (define-view *canvas-ratio* core:*canvas-ratio*)
  (define-view *canvas-pw* core:*canvas-pw*)
  (define-view *canvas-ph* core:*canvas-ph*)
  (define-view *rec-labels* core:*rec-labels*)
  (define-view *rec-label-at* core:*rec-label-at*)
  (define-view draw-text core:draw-text)
  (define-view *frame-ms* core:*frame-ms*)
  (define-view *frames-drawn* core:*frames-drawn*)
  (define-view *frame-ring* core:*frame-ring*)
  (define-view *frame-ring-n* core:*frame-ring-n*)
  (define-view *pacer-due* core:*pacer-due*)
  (define-view *pacer-frame-ns* core:*pacer-frame-ns*)
  (define-view *pacer-shown?* core:*pacer-shown?*)
  (define-view *pacer-latch* core:*pacer-latch*)
  (define-view *pacer-lead* core:*pacer-lead*)
  (define-view *pacer-counts* core:*pacer-counts*)
  (define-view *pacer-aimed* core:*pacer-aimed*)
  (define-view *pacer-floor* core:*pacer-floor*)
  (define-view *pacer-latch-phase* core:*pacer-latch-phase*)
  (define-view *pacer-depth* core:*pacer-depth*)
  (define-view *pacer-made* core:*pacer-made*)
  (define-view *pacer-late-run* core:*pacer-late-run*)
  (define-view *pacer-late-chain* core:*pacer-late-chain*)
  (define-view *pacer-gpu-taught* core:*pacer-gpu-taught*)
  (define-view *pacer-between?* core:*pacer-between?*)
  (define-view pacer-period core:pacer-period)
  (define-view *input-step?* core:*input-step?*)
  (define-view *theme-version* core:*theme-version*)
  (define-view *style-name* core:*style-name*)
  (define-view *style-changes* core:*style-changes*)
  (define-view *theme-overrides* core:*theme-overrides*)
  (define-view *scale-setting* core:*scale-setting*)
  (define-view default-theme core:default-theme)
  (define-view color-keys core:color-keys)
  (define-view *palettes* core:*palettes*)
  (define-view *wallpapers* core:*wallpapers*)
  (define-view *styles* core:*styles*)
  (define-view *windows* core:*windows*)
  (define-view *focus* core:*focus*)
  (define-view *drag-outline* core:*drag-outline*)
  (define-view *hover* core:*hover*)
  (define-view *mouse-x* core:*mouse-x*)
  (define-view *mouse-y* core:*mouse-y*)
  (define-view *mouse-button* core:*mouse-button*)
  (define-view current-window core:current-window)
  (define-view invalidate! core:invalidate!)
  (define-view *apps* core:*apps*)
  (define-view new-window-position core:new-window-position)
  (define-view *global-keys* core:*global-keys*)
  (define-view *world-env* core:*world-env*)
  (define-view *schevana-options* core:*schevana-options*)
  (define-view *source-texts* core:*source-texts*)

  ;; The hooks later layers fill (AGENTS.md, S1): each set by the one file
  ;; that fills it, with what the core calls, and checked as it is set.
  (define-settable *profile-span* core:*profile-span*
    (lambda (v) (or (not v) (pair? v))))
  (define-settable worklet-spread core:worklet-spread
    procedure?)
  (define-settable screen-event-seen! core:screen-event-seen!
    procedure?)
  (define-settable theme-save! core:theme-save!
    procedure?)
  (define-settable window-gone! core:window-gone!
    procedure?)

  ;; And those the windows layer fills, for a program that has none.
  (define-settable record-world! core:record-world!
    procedure?)
  (define-settable wm-event! core:wm-event!
    procedure?)
  (define-settable wm-tick! core:wm-tick!
    procedure?))
