;;; core1/export.ss — what core1 gives the world, "/" (src/base.ss's
;;; define-exports): each name read-only, but for the hooks a later layer
;;; fills. Nothing else of the core's is there to name, and none of its C.
;;; A new name here is a reviewed change; tests/sources.ss names those no
;;; file of the world's uses.

(define-exports core1-exports
  (export (world)
    ;; src/core1/boot.ss: core1's thread, and the world's environment
    core1-thread? *core1-env* *world-env* world-value core1-exported
    *schevana-root* *schevana-options*
    ;; src/core1/platform.ss: which platform this is, the clocks, the
    ;; system's figures
    platform-fact platform-windowing platform-gpu-api platform-predicates
    platform-process-bytes platform-machine-load now-ns now-ms thread-cpu-ns
    ;; src/core1/shader.ss: the shader language
    *shader-constants* *shader-helpers* *shader-fields* define-shader-layout
    shader-type shader-tree define-compute-shader
    ;; src/core1/theme.ss: the theme, styles, palettes and parts
    *theme-version* *style-name* *style-changes* *theme-overrides*
    *scale-setting* theme-rule? theme-rule default-theme color-keys
    common-options call-with-theme theme theme-default theme-keys *palettes*
    define-palette palettes palette-title palette-colors style style-name
    style-title style-settings *styles* define-style find-style styles
    current-style theme-part define-part color-default! theme-default!
    with-style with-place style-changes-of plist-has? plist-remove style-chain
    chain-ref honored? resolve-theme frame-over* change-layers!
    theme-layers-set! set-style! set-theme! reset-style! override!
    theme-overrides set-scale! set-palette! reset-theme!
    ;; src/core1/gpu.ss: the GPU's world side: images, buffers, lists, computes
    *gpu-bytes-made* *gpu-held-gone* gpu-image-make gpu-image-make-target
    gpu-image-release! gpu-atlas-image gpu-list-new make-gpu-buffer
    gpu-buffer-set! gpu-buffer-release! gpu-buffer-read! *gpu-computes*
    gpu-compute-soon! gpu-buffer-read-then! gpu-compute!
    ;; src/core1/font.ss: fonts and text
    font-file-upem font-file-pages font-library-versions make-font* *font-specs*
    font get-font font-advance font-ascent font-descent font-line-height
    font-char-width font-ready text-width *glyph-count* *atlas-y* *atlas-row*
    glyph-row-ref
    font-family font-size font-sized font-weight glyph-row-character
    glyph-row-h glyph-row-left glyph-row-top glyph-row-w
    ;; src/core1/gfx.ss: drawing: colors, shapes, text, runs and labels
    pi *canvas-w* *canvas-h* *scale* *canvas-ratio* *canvas-pw* *canvas-ph*
    canvas-pixel-width canvas-pixel-height rgb alpha stipple stipple?
    linear-gradient radial-gradient color-rgba mix color-word theme-font-rule
    *rec-labels* *rec-label-at* rec-variant record-list! fill-box stroke-box
    fill-circle stroke-circle draw-line draw-polyline fill-polygon invert-box
    add-box draw-shadow draw-text draw-image define-paint fill-shader with-clip
    with-translation with-scale with-turn with-label draw-scale gfx-fragments
    rec-preview! rec-past! drawing->bytes
    ;; the records' layouts and kinds, which the Pipeline and inspect read
    rec-row-head rec-row-paint rec-row-words rec-row-x0 rec-row-x1 rec-row-y0
    rec-row-y1 rec-box-line rec-box-radius rec-glyph-number rec-glyph-pen-x
    rec-glyph-pen-y rec-polygon-count rec-polygon-points rec-segment-width
    rec-shadow-size rec-kind-glyph rec-kind-polygon rec-paint-gradient
    rec-paint-image rec-paint-stipple rec-gradient-radial gradient-row-kind
    gradient-row-x0 gradient-row-x1 gradient-row-y0 gradient-row-y1
    clip-row-parent clip-row-radius clip-row-rx0 clip-row-rx1 clip-row-ry0
    clip-row-ry1 clip-row-words clip-row-x0 clip-row-x1 clip-row-y0
    clip-row-y1
    ;; src/core1/proc.ss: processes, errors, toasts, worklets
    proc-wait
    in-engine? current-proc make-timeout-condition safe-call safely *toasts*
    notify *last-error* report-error! proc proc? proc-id proc-name proc-state
    proc-ticks proc-started proc-wake *procs* spawn procs find-proc kill!
    sleep-ms worklet-base-environment *worklet-environment* worklet?
    worklet-compile worklet worklet-spread define-worklet
    ;; src/core1/screen.ss: the screen core0 shows
    system-scale-percent fullscreen? set-fullscreen! toggle-fullscreen!
    screen-set-icon!
    ;; src/core1/socket.ss: sockets
    socket-listen socket-accept socket-read socket-write socket-close
    ;; src/core1/wm.ss: windows, focus, surfaces and strips
    window window? window-id window-app window-title window-title-set! window-x
    window-x-set! window-y window-y-set! window-w window-w-set! window-h
    window-h-set! window-state window-state-set! window-restore-set!
    window-handlers window-props window-error *windows* *focus* *drag-outline*
    *hover* *mouse-x* *mouse-y* *mouse-button* drag current-window
    request-frame! invalidate! window-shadow window-extent screen-w screen-h
    screen-scale chrome-height title-height point-in? surface surface-doc
    define-surface find-surface surface-call define-strip desktop-rect app
    app-name app-title app-launch *apps* register-app! define-app apps
    open-window detached-window new-window-position cascade-reset! place-window!
    windows focused-window visible? maximized? find-window window-ref
    window-set! window-bg in-window-theme window-setting frame-insets
    frame-regions frame-radius frame-bleed content-rect window-content-size
    window-local window-call window-crash! window-modal-child focus-window!
    close-window! minimize-window! set-geometry! move-window! resize-window!
    restore-window! toggle-maximize! window-action! shaded? unshade-window!
    toggle-shade! window-at resize-kinds window-region *global-keys* bind-key!
    window-frame-soon! window-hover draw-window* *frame-ms* *frames-drawn*
    frame-ring-rows frame-ring-words *frame-ring* *frame-ring-n* screen-bytes
    screen-bytes-then
    ;; src/core1/system.ss: the step, the pacer, timers, sources and reload
    *timers* *input-step?* *pacer-due* *pacer-frame-ns* *pacer-shown?*
    *pacer-latch* *pacer-lead* *pacer-counts* *pacer-aimed* *pacer-floor*
    *pacer-latch-phase* *pacer-depth* *pacer-made* *pacer-late-run*
    *pacer-late-chain* *pacer-between?* after post-core1! pacer-busy-ms
    pacer-peak-ms! pacer-rate pacer-ticks pacer-period pacer-start *pacer-trial*
    pacer-trial! pacer-margin schevana-run! quit! schevana-end! uptime-ms
    load-user-init! user-directory schevana-boot! collector-declining?
    source-path source-files *source-texts* keep-source-text! load-file!
    load-user-folders! reload!
    ;; Given again: core0's (src/core0/export.ss), which Monitor, the
    ;; Pipeline and inspect read
    core0-app-id gpu-atlas-side core0-flag-names core0-event-name gpu-show-run?
    gpu-run-gone? shader shader-name shader-stage shader-coords shader-params
    shader-source shader-words gpu-list-id gpu-list-labels gpu-list-recorded
    gpu-list-took gpu-image-id gpu-image-w gpu-image-h gpu-image-levels
    gpu-call? gpu-call-shader *gpu-facts* core0-display core0-frame-ns
    core0-hidden? core0-flags core0-error-text core0-step-state
    core0-frame-report core0-window-sizes core0-window-scale clipboard-get
    core0-set-cursor! clipboard-set! core0-eval! core0-environment
    core0-recorder-environment platform-cpu-count
    ;; Given again: the recorder's (src/recorder/export.ss), which the
    ;; Pipeline reads of a list
    rec-count rec-last-sizes rec-last-copy! rec-last-runs rec-list-copy
    gpu-list-recs-n gpu-list-extras-n gpu-list-runs gpu-list-version
    gpu-list-recs gpu-list-extras rec-recordings rec-pixel-set! rec-image-rows!
    ;; The hooks later layers fill (AGENTS.md, S1): each set by the one
    ;; file that fills it, with what the core calls.
    (settable *profile-span* (lambda (v) (or (not v) (pair? v))))
    (settable *theme-saver* procedure?)
    (settable *window-gone* procedure?)
    (settable *app-loader* procedure?)
    (settable *screen-event-seen* procedure?)
    (settable *worklet-spread* (lambda (v) (or (not v) (procedure? v))))))
