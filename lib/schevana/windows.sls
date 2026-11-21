;;; (schevana windows) — windows, focus, surfaces and strips, and the frame
;;; they draw (src/core1/wm.ss). It exports what the pieces above it and the
;;; world use of it.

(library (schevana windows)
  (export)
  (import (chezscheme) (schevana layer) (schevana base) (schevana core0)
          (schevana boot) (schevana theme-table) (schevana processes)
          (schevana gpu) (schevana draw) (schevana pacer) (schevana screen)
          (schevana loop) (schevana theme))

  (library-layer core)

  (include-sources "src/core1/wm.ss")

  (define-exports windows-exports
    (export (world)
      window window? window-id window-app window-title window-title-set!
      window-x window-x-set! window-y window-y-set! window-w window-w-set!
      window-h window-h-set! window-state window-state-set!
      window-restore-set! window-handlers window-props window-error *windows*
      *focus* *drag-outline* *hover* *mouse-x* *mouse-y* *mouse-button* drag
      current-window (settable window-gone!) invalidate! window-shadow
      window-extent screen-w screen-h screen-scale point-in? surface
      surface-doc define-surface find-surface surface-call define-strip
      desktop-rect app app-name app-title app-launch *apps* register-app!
      define-app apps open-window detached-window new-window-position
      cascade-reset! place-window! windows focused-window visible? maximized?
      find-window window-ref window-set! window-bg in-window-theme
      window-setting frame-insets frame-regions frame-radius frame-bleed
      content-rect window-content-size window-local window-call window-crash!
      window-modal-child focus-window! close-window! minimize-window!
      set-geometry! move-window! resize-window! restore-window!
      toggle-maximize! window-action! shaded? unshade-window! toggle-shade!
      window-at resize-kinds window-region *global-keys* bind-key!
      window-frame-soon! window-hover draw-window*)))
