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
  (export
    ui-region-x ui-region-y ui-region-h ui-region-frame ui-state-mx ui-state-my
    ui-state-reveal ui-state-reveal-set! make-ui ui-memo ui-memo! ui-forget!
    ui-tip-ms ui-region! ui-area ui-region-in? ui-find ui-hover? ui-active?
    ui-flags ui-focus! ui-focused ui-edit ui-caret ui-due! ui-frame ui-stale!
    ui-wheel ui-handlers ui-pressable! ui-begin! ui-later! ui-end! ui-menu-open!
    ui-menu-open-tag ui-open-menu! ui-open-modal ui-control-height ui-glyph-size
    ui-small-glyph-size ui-gap ui-pad ui-popup-place ui-flow ui-toolbar
    ui-date->day ui-day->date ui-days-in-month ui-today ui-month-names
    ui-date-label ui-next-midnight ui-italic-of ui-draw-focus ui-draw-focus*
    ui-draw-field ui-draw-field* ui-draw-glyph ui-draw-glyph* ui-frame-glyph
    ui-button ui-draw-button ui-draw-button* ui-button-size ui-button-size*
    ui-segmented ui-stepper ui-breadcrumbs ui-nav ui-draw-nav-row
    ui-draw-nav-row* ui-slider ui-slider-height ui-draw-slider ui-draw-slider*
    ui-checkbox ui-toggle ui-checkbox-box ui-draw-checkbox ui-draw-checkbox*
    ui-checkbox-size ui-checkbox-size* ui-live-badge ui-live-badge-back
    ui-live-badge-mark ui-live-badge-size ui-live-badge-size* ui-draw-live-badge
    ui-draw-live-badge* ui-toggle-track ui-draw-toggle ui-draw-toggle*
    ui-toggle-size ui-toggle-size* ui-radio ui-radio-size ui-radio-size*
    ui-draw-radio ui-draw-radio* ui-tabs ui-draw-tab ui-draw-tab* ui-tabs-size
    ui-tabs-size* ui-label-font ui-label-text ui-draw-label ui-draw-label*
    ui-label-size ui-label-size* ui-label-lines ui-wrap-lines ui-draw-surface
    ui-draw-surface* ui-surface-well-ring ui-text-y ui-text-y* ui-text-box-top
    ui-text-box-areas ui-text-box-areas* ui-text-box-inset ui-text-box-size
    ui-text-box-size* ui-text-area-size ui-text-area-size* ui-text-field
    ui-text-area ui-draw-text-box* ui-draw-suggestion ui-draw-suggestion*
    ui-rank ui-suggestions ui-scroll ui-scrollbar ui-reveal! ui-scrollbar-width
    ui-scrollbar-inset ui-frame-scrollbar ui-scrollbar-areas ui-scrollbar-areas*
    ui-draw-scrollbar ui-draw-scrollbar* ui-title-icon ui-draw-env-icon
    ui-draw-env-icon* ui-busy-frame-ms ui-busy-size ui-busy-size* ui-draw-busy
    ui-draw-busy* ui-split ui-draw-split ui-draw-split* ui-side-panel-toggle!
    ui-side-panel ui-side-panel-button ui-table-room ui-table-fit ui-table
    ui-table-step ui-table-page ui-table-columns ui-table-header-height
    ui-table-row-height ui-table-cell-inset ui-table-cell-inset* ui-draw-cell
    ui-draw-cell* ui-draw-table-header ui-draw-table-header*
    ui-draw-table-divider ui-draw-table-divider* ui-draw-table-row
    ui-draw-table-row* ui-tree-states ui-tree-expand! ui-tree-key ui-tree
    ui-tree-areas ui-tree-areas* ui-draw-tree-row ui-draw-tree-row* ui-draw-dim
    ui-draw-dim* ui-draw-chip ui-draw-chip* ui-chip-size ui-chip-size*
    ui-chip-areas ui-chip-areas* ui-chip-input ui-chip-input-areas
    ui-chip-input-areas* ui-chip-input-size ui-chip-input-size* ui-chips
    ui-chips-height ui-initials ui-avatar-size ui-avatar-size* ui-draw-avatar
    ui-draw-avatar* ui-draw-progress ui-draw-progress* ui-progress-height
    ui-bar-chart ui-bar-chart-areas* ui-bar-chart-bar ui-draw-bar-chart*
    ui-stream-rows ui-stream-sent ui-stream-new ui-stream-restart!
    ui-stream-resend! ui-stream-release! ui-stream-send! ui-stream-lane*
    ui-stream-room ui-stream-areas* ui-stream-count ui-stream-layout
    ui-draw-stream* ui-stream ui-draw-sparkline ui-draw-sparkline*
    ui-draw-line-chart ui-draw-line-chart* ui-draw-legend ui-draw-legend*
    ui-legend-size ui-legend-size* ui-draw-panel ui-draw-panel*
    ui-draw-highlight ui-draw-highlight* ui-draw-highlight-over
    ui-draw-highlight-over* ui-draw-separator ui-draw-separator* ui-draw-card
    ui-draw-card* ui-tooltip-lines ui-tooltip-size ui-tooltip-size*
    ui-draw-tooltip ui-draw-tooltip* ui-dropdown ui-draw-dropdown
    ui-draw-dropdown* ui-dropdown-size ui-dropdown-size* ui-date-field
    ui-calendar-size ui-calendar-size* ui-calendar-areas ui-calendar-areas*
    ui-draw-calendar ui-draw-calendar* ui-draw-day ui-draw-day* ui-form
    ui-form-height ui-dialog ui-sheet ui-dialog-lines ui-dialog-size
    ui-dialog-size* ui-dialog-areas ui-dialog-areas* ui-draw-scrim
    ui-draw-scrim* ui-draw-dialog ui-draw-dialog* ui-joined-span
    ui-button-radius ui-linked ui-stepper-areas ui-stepper-areas*
    ui-toggle-track* ui-rows ui-rows-height ui-switch-row ui-check-row
    ui-entry-row ui-rows-spacing ui-rows-spacing* ui-row-height ui-row-height*
    ui-row-areas ui-row-areas* ui-rows-radius ui-rows-radius* ui-draw-rows
    ui-draw-rows* ui-draw-row ui-draw-row* ui-add-row-height ui-add-row-height*
    ui-draw-add-row ui-draw-add-row* ui-status-page ui-status-page-areas
    ui-status-page-areas* ui-draw-status-page ui-draw-status-page* ui-banner
    ui-banner-height ui-banner-height* ui-banner-areas ui-banner-areas*
    ui-draw-banner ui-draw-banner* ui-card-radius ui-card-radius*)
  (import (chezscheme)
          (only (schevana base) at-load clamp define-hook filter-map
                library-layer list-index plist-ref string-prefix? string-split)
          (only (schevana core) *input-step?* *scale* after alpha app
                clipboard-get clipboard-set! close-window! color-default!
                color-word content-rect core0-set-cursor! current-window
                define-paint define-part define-shader-layout draw-line
                draw-polyline draw-scale draw-shadow draw-text fill-box
                fill-circle fill-polygon fill-shader focus-window!
                focused-window font font-char-width font-family font-line-height
                font-size font-weight frame-insets frame-regions get-font
                gpu-buffer-release! gpu-buffer-set! gpu-list-new invalidate!
                make-gpu-buffer maximized? mix new-window-position now-ms
                open-window pi plist-remove point-in? proc record-list!
                resize-window! stipple stroke-box stroke-circle text-width theme
                theme-default! theme-font-rule theme-rule window-app
                window-content-size window-frame-soon! window-handlers
                window-hover window-modal-child window-props window-ref
                window-set! window-x window-y window? windows with-clip
                with-place)
          (only (schevana kits app) app-launch! app-color)
          (only (schevana kits color) color-readable-on)
          (only (schevana kits edit) edit-layout-text edit-range edit-move
                edit-line-bounds edit-select edit-word-bounds edit-key
                edit-clean edit-insert edit-erase edit-selection edit-index-at
                edit-layout-done? edit-layout-total edit-row-at edit-caret-x
                edit-at edit-all edit-anchor make-edit edit-change edit-text
                edit-row-last edit-row edit-layout-count edit-layout-extend!
                edit-layout-of edit-wrap edit-layout-scan! edit-caret edit?)
          (only (schevana kits px) px-invert)
          (only (schevana kits text) text-draw-centered text-widest text-fit))

  (library-layer kits)

  ;;; ---------------------------------------------------------------- state

  (define-record-type ui-region
    (nongenerative schevana-ui-region-4)
    (fields id x y w h   ; the area that can be hit, cut to the clip (may be
                         ; 0 × 0)
            frame        ; (x y w h) before the cut, for scrolling into view
            on           ; #f, or (lambda (event) ...): true when it handled
                         ; the event
            focus        ; click, tab, keep or #f: see ui-mouse-down
            tip          ; tooltip text, or #f
            cursor       ; the pointer's shape over it ('ibeam), or #f
            modal?       ; covers the window, so what lies under it is not live
            doc          ; what the mouse buttons do on it: ((L . "Set") ...)
            follow))     ; #f, or (lambda (x y) ...): what it shows for the
                         ; pointer there; a move that changes that redraws

  (define-record-type ui-state
    (nongenerative schevana-ui-state-4)
    (fields (mutable regions)  ; this draw's regions, newest (topmost) first
            (mutable active)   ; the region the left button holds, or #f
            (mutable hover-id) ; the topmost live region under the pointer
            (mutable mx) (mutable my)
            (mutable clicks)   ; the click count of the press in progress
            (mutable rest)     ; (ms x y): when and where the pointer settled;
                               ; ms is +inf.0 once a press, key, text or
                               ; wheel has used the tooltip up
            (mutable clip)     ; the (x y w h) new regions are cut to, or #f
            (mutable focus)    ; the focused widget's id, or #f
            (mutable edit)     ; the focused text's edit, or #f; for a new
                               ; focus, all or a caret index
            (mutable blink-at) ; ms of the last caret change, the blink's
                               ; phase 0
            (mutable reveal)   ; (id . span) to scroll into view at the next
                               ; draw, or #f; span is (top . bottom) within
                               ; it (a caret's row), for a view too short
                               ; to show all of it, or #f
            (mutable popup)    ; (id . cursor-day) of an open calendar, or #f
            (mutable later)    ; overlays for ui-end!, newest first
            (mutable due)      ; ms when the window next looks different
            (mutable woken)    ; the ms a timer is set for, to draw the
                               ; window then, or #f
            (mutable fresh?)   ; whether nothing was handled since the last
                               ; layout
            (mutable scans)    ; text layouts a scroll bar waits on: the
                               ; window's frames compute their rows to the
                               ; end
            memo))             ; per-id kit memory (scroll offsets, ...)

  (define (make-ui)
    (make-ui-state '() #f #f -1 -1 1 (list 0 -1 -1) #f #f #f 0 #f #f '() #f #f
                   #t '() (make-hashtable equal-hash equal?)))

  (define (ui-memo ui key default)
    (hashtable-ref (ui-state-memo ui) key default))
  (define (ui-memo! ui key value) (hashtable-set! (ui-state-memo ui) key value))

  ;; Forgets what the kit keeps for widget id (a scroll offset and a caret),
  ;; so that, given other data to show, the widget starts at its top again.
  (define (ui-forget! ui id)
    (hashtable-delete! (ui-state-memo ui) id)
    (hashtable-delete! (ui-state-memo ui) (list id 'caret)))

  ;; How long (ms) the pointer rests before a tooltip shows, and how long a
  ;; caret phase lasts.
  (define ui-tip-ms 600)
  (define ui-blink-ms 530)

  ;; Returns a rect cut to clip (x y w h), as (values x y w h): 0 wide or
  ;; high, at the clip's edge, when the rect lies outside the clip.
  (define (ui-cut x y w h clip)
    (if clip
        (let ([cx (car clip)] [cy (cadr clip)]
              [cx1 (+ (car clip) (caddr clip))]
              [cy1 (+ (cadr clip) (cadddr clip))])
          (let ([x0 (clamp x cx cx1)] [y0 (clamp y cy cy1)])
            (values x0 y0
                    (max 0 (- (clamp (+ x w) cx cx1) x0))
                    (max 0 (- (clamp (+ y h) cy cy1) y0)))))
        (values x y w h)))

  ;; The only way anything enters the hit list; returns the region. opts:
  ;; 'on 'focus 'tip 'cursor 'modal 'doc 'follow. Inside a scroll view the
  ;; rect is cut to the viewport; a region cut away entirely is still
  ;; recorded, 0 × 0 at the edge, so that it stays a Tab stop (and can be
  ;; revealed) but cannot be hit.
  (define (ui-region! ui id x y w h . opts)
    (let-values ([(cx cy cw ch) (ui-cut x y w h (ui-state-clip ui))])
      (let ([r (make-ui-region id cx cy cw ch (list x y w h)
                               (plist-ref opts 'on #f)
                               (plist-ref opts 'focus #f)
                               (plist-ref opts 'tip #f)
                               (plist-ref opts 'cursor #f)
                               (plist-ref opts 'modal #f)
                               (plist-ref opts 'doc '())
                               (plist-ref opts 'follow #f))])
        (ui-state-regions-set! ui (cons r (ui-state-regions ui)))
        r)))

  ;; A clickable area, as Settings uses it: on-press is a thunk or #f;
  ;; on-drag, if given, receives the pointer's position on the press and on
  ;; every move until the release; opts are ui-region!'s ('doc, say).
  (define ui-area
    (case-lambda
      [(ui id x y w h on-press) (ui-area ui id x y w h on-press #f)]
      [(ui id x y w h on-press on-drag . opts)
       (apply ui-region! ui id x y w h 'on
         (and (or on-press on-drag)
              (lambda (ev)
                (case (car ev)
                  [(press)
                   (and (eq? (list-ref ev 3) 'left)
                        (begin (when on-press (on-press))
                               (when on-drag (on-drag (cadr ev) (caddr ev)))
                               #t))]
                  [(drag)
                   (and on-drag (begin (on-drag (cadr ev) (caddr ev)) #t))]
                  [else #f])))
         opts)
       (void)]))

  ;; Returns the live regions, newest first: those drawn above the newest
  ;; modal region, which is the last of them.
  (define (ui-live ui)
    (let loop ([rs (ui-state-regions ui)] [acc '()])
      (cond [(null? rs) (reverse acc)]
            [(ui-region-modal? (car rs)) (reverse (cons (car rs) acc))]
            [else (loop (cdr rs) (cons (car rs) acc))])))

  (define (ui-region-in? r x y)
    (point-in? x y (ui-region-x r) (ui-region-y r) (ui-region-w r)
               (ui-region-h r)))

  (define (ui-region-at ui x y)
    (find (lambda (r) (ui-region-in? r x y)) (ui-live ui)))

  (define (ui-find ui id)
    (find (lambda (r) (equal? (ui-region-id r) id)) (ui-state-regions ui)))

  (define (ui-live-region ui id)
    (and id (find (lambda (r) (equal? (ui-region-id r) id)) (ui-live ui))))

  (define (ui-hover? ui x y w h)
    (point-in? (ui-state-mx ui) (ui-state-my ui) x y w h))

  (define (ui-active? ui id)
    (let ([a (ui-state-active ui)]) (and a (equal? (ui-region-id a) id))))

  ;; Returns the symbols among keys whose option value in opts is true, so
  ;; that intents such as 'primary #t become flags.
  (define (ui-opt-flags opts keys)
    (filter (lambda (k) (plist-ref opts k #f)) keys))

  ;; Returns the state flags the kit computes for id, followed by own.
  ;; hover: the pointer is on it and no other region is held; pressed: the
  ;; left button holds it; focused: it has the keyboard, in the focused
  ;; window.
  (define (ui-flags ui id . own)
    (let* ([win (current-window)]
           [r (ui-find ui id)]
           [pressed? (ui-active? ui id)]
           [hover? (and win (equal? (ui-state-hover-id ui) id)
                        (or pressed? (not (ui-state-active ui)))
                        (memq (window-hover win) '(content scrollbar))
                        (or (not r)
                            (ui-region-in? r (ui-state-mx ui)
                                           (ui-state-my ui))))]
           [focused? (and win (equal? (ui-state-focus ui) id)
                          (eq? win (focused-window)))])
      (append (if hover? '(hover) '()) (if pressed? '(pressed) '())
              (if focused? '(focused) '()) own)))

  ;;; ---------------------------------------------------------------- focus

  ;; Focuses id (#f for nothing) and scrolls it into view at the next draw.
  ;; A new focus starts with its caret at the end; at, when given, is #t to
  ;; select everything, or the caret's index.
  (define (ui-focus! ui id . at)
    (unless (equal? id (ui-state-focus ui))
      (ui-state-focus-set! ui id)
      (ui-state-edit-set! ui (and (pair? at) (if (eq? (car at) #t) 'all
                                                 (car at))))
      (ui-state-blink-at-set! ui (now-ms)))
    (when id (ui-state-reveal-set! ui (cons id #f))))

  (define (ui-focused ui) (ui-state-focus ui))

  ;; Returns the edit of the text that has the keyboard, as its last draw
  ;; left it, or #f. ui-caret returns that edit's caret.
  (define (ui-edit ui)
    (let ([e (ui-state-edit ui)]) (and (edit? e) e)))

  (define (ui-caret ui)
    (let ([e (ui-edit ui)]) (and e (edit-caret e))))

  ;; Moves the focus to the next (dir 1) or previous (-1) live Tab stop in
  ;; draw order, wrapping around. Returns #f when there is none.
  (define (ui-tab! ui dir)
    (let ([ids (map ui-region-id
                    (filter (lambda (r) (memq (ui-region-focus r) '(click tab)))
                            (reverse (ui-live ui))))])
      (and (pair? ids)
           (let* ([n (length ids)]
                  [i (list-index (lambda (id) (equal? id (ui-state-focus ui)))
                                 ids)]
                  [j (cond [i (mod (+ i dir) n)] [(> dir 0) 0] [else (- n 1)])])
             (ui-focus! ui (list-ref ids j) #t)
             #t))))

  ;;; ---------------------------------------------------------------- time

  ;; The draw says when the window next looks different by itself (a caret
  ;; flip, a tooltip, midnight), and a timer draws it again then.
  (define (ui-due! ui ms)
    (let ([d (ui-state-due ui)])
      (when (or (not d) (< ms d)) (ui-state-due-set! ui ms))))

  ;; A scroll bar over a text whose rows are not all computed shows an
  ;; estimate. Each frame computes some more of the rows, a millisecond's
  ;; worth, but not in a step that brought window input (so never on a
  ;; keystroke's frame); once the rows reach the end, the window draws again
  ;; and the bar settles.

  ;; After a draw of the current window, sets a timer for when the window
  ;; is due, unless one is set already for then or sooner, and asks for a
  ;; frame while rows wait.
  (define (ui-wake! ui)
    (let ([win (current-window)] [d (ui-state-due ui)] [w (ui-state-woken ui)])
      (when win
        (when (and d (not (and w (<= w d))))
          (ui-state-woken-set! ui d)
          (after (max 0 (- d (now-ms))) (lambda () (ui-woken! ui win d))))
        (when (pair? (ui-state-scans ui)) (window-frame-soon! win)))))

  ;; A timer set for ms went off: the window draws again if it is due. A
  ;; draw since then may have made it due later, and then the timer is set
  ;; again.
  (define (ui-woken! ui win ms)
    (when (eqv? (ui-state-woken ui) ms) (ui-state-woken-set! ui #f))
    (let ([d (ui-state-due ui)])
      (when d
        (if (>= (now-ms) d)
            (begin (ui-state-due-set! ui #f) (invalidate! win))
            (parameterize ([current-window win]) (ui-wake! ui))))))

  ;; On a frame asked for while rows wait, computes some more of the rows.
  (define (ui-frame ui win)
    (let ([scans (ui-state-scans ui)])
      (when (pair? scans)
        (cond
          [*input-step?* (window-frame-soon! win)]
          [(edit-layout-scan! (car scans) 1)
           (ui-state-scans-set! ui (cdr scans))
           (invalidate! win)]
          [else (window-frame-soon! win)]))))

  ;; Whether a focused caret shows now. Asks for a draw at its next flip.
  (define (ui-caret-on? ui)
    (let* ([t0 (ui-state-blink-at ui)]
           [k (quotient (max 0 (- (now-ms) t0)) ui-blink-ms)])
      (ui-due! ui (+ t0 (* (+ k 1) ui-blink-ms)))
      (even? k)))

  ;; Starts the tooltip's wait at ms (+inf.0: not until the pointer moves),
  ;; for a pointer at (x, y), by default where it was.
  (define (ui-rest! ui ms . at)
    (ui-state-rest-set! ui (cons ms
                                 (if (pair? at) at (cdr (ui-state-rest ui))))))

  ;;; ---------------------------------------------------------------- events
  ;;; A region's on receives (press x y button clicks), (drag x y clicks),
  ;;; (release x y), (key key mods), (text str) and (wheel dy), and returns
  ;;; true when it handled the event.

  (define (ui-stale! ui) (ui-state-fresh?-set! ui #f))

  ;; Runs before an event that needs the regions: when an event handled
  ;; since the last draw may have changed them, it lays the window out
  ;; again. That draw only records (what is recorded between frames goes
  ;; nowhere).
  (define (ui-fresh! ui)
    (let ([win (current-window)])
      (unless (or (ui-state-fresh? ui) (not win))
        (let-values ([(w h) (window-content-size win)])
          ;; A layout pass, recorded into a list of the ui's own that nothing
          ;; shows, never into a frame's bytes.
          (record-list! (ui-layout-list ui)
                        (lambda ()
                          ((hashtable-ref (window-handlers win) 'draw
                                          (lambda a #f))
                           win w h)))
          (ui-state-fresh?-set! ui #t)))))

  ;; Returns the list that ui-fresh! records into: the ui's own, made once.
  (define (ui-layout-list ui)
    (or (ui-memo ui 'ui-layout-list #f)
        (let ([l (gpu-list-new)])
          (ui-memo! ui 'ui-layout-list l)
          l)))

  ;; Returns the held region as the latest layout drew it, or as it was when
  ;; pressed if it is gone or no longer takes events (a button that disabled
  ;; itself).
  (define (ui-held ui)
    (let* ([a (ui-state-active ui)] [r (and a (ui-find ui (ui-region-id a)))])
      (if (and r (ui-region-on r)) r a)))

  ;; Moves the hover to the topmost live region at (x, y). A change starts
  ;; the tooltip's wait at ms, sets the pointer's shape, redraws, and returns
  ;; #t.
  (define (ui-hover! ui win x y ms)
    (let* ([r (ui-region-at ui x y)] [id (and r (ui-region-id r))]
           [c (or (and r (ui-region-cursor r)) 'arrow)])
      (and (not (equal? id (ui-state-hover-id ui)))
           (begin
             (ui-state-hover-id-set! ui id)
             ;; The mouse documentation reads this; it needs no redraw.
             (hashtable-set! (window-props win) 'mouse-doc
                             (if r (ui-region-doc r) '()))
             (ui-rest! ui ms x y)
             (unless (eq? c (window-ref win 'cursor 'arrow))
               (window-set! win 'cursor c)
               (core0-set-cursor! c))
             (invalidate! win)
             #t))))

  ;; A press. A left press focuses a region that takes typing (focus
  ;; click), leaves the focus as it is on Tab stops and keep regions, and
  ;; clears it elsewhere; then the region gets the press. While the left
  ;; button holds a region, another button's press goes to that region (a
  ;; card ends its drag). button and clicks are optional (the tests leave
  ;; them out). Returns whether a region was hit.
  (define (ui-mouse-down ui x y . more)
    (let ([button (if (pair? more) (car more) 'left)]
          [clicks (if (and (pair? more) (pair? (cdr more))) (cadr more) 1)])
      (ui-state-mx-set! ui x)
      (ui-state-my-set! ui y)
      (let ([r (or (and (not (eq? button 'left)) (ui-held ui))
                   (ui-region-at ui x y))])
        (when (eq? button 'left)
          (case (and r (ui-region-focus r))
            [(click) (ui-focus! ui (ui-region-id r))]
            [(tab keep) (void)]
            [else (ui-focus! ui #f)])
          (ui-state-clicks-set! ui clicks)
          (ui-state-active-set! ui (and r (ui-region-on r) r)))
        (ui-state-hover-id-set! ui (and r (ui-region-id r)))
        (ui-rest! ui +inf.0 x y)
        (when (and r (ui-region-on r))
          ((ui-region-on r) (list 'press x y button clicks)))
        (ui-stale! ui)
        (invalidate! (current-window))
        (and r #t))))

  (define (ui-mouse-move ui x y)
    (ui-state-mx-set! ui x)
    (ui-state-my-set! ui y)
    (let ([a (ui-held ui)] [win (current-window)])
      (if a
          (when ((ui-region-on a) (list 'drag x y (ui-state-clicks ui)))
            (ui-stale! ui)
            (invalidate! win))
          (begin
            (ui-follow! ui win x y)
            (unless (ui-hover! ui win x y (now-ms))
              ;; A tooltip not shown yet waits for the pointer to rest, so a
              ;; move starts its wait again. One that a press, key or typing
              ;; used up waits from now, and a draw sets its timer, as a
              ;; hover's draw does.
              (when (< (now-ms) (+ (car (ui-state-rest ui)) ui-tip-ms))
                (let ([used? (= (car (ui-state-rest ui)) +inf.0)])
                  (ui-rest! ui (now-ms) x y)
                  (when used? (invalidate! win)))))))))

  ;; A region that follows the pointer within it (a chart's column under
  ;; the pointer) draws again when what it shows for the pointer changes;
  ;; within one region, the hover alone would wait for the window's next
  ;; draw.
  (define (ui-follow! ui win x y)
    (let* ([r (ui-region-at ui x y)]
           [follow (and r (ui-region-follow r))]
           [shown (and follow (cons (ui-region-id r) (follow x y)))])
      (unless (equal? shown (ui-memo ui 'ui-follow #f))
        (ui-memo! ui 'ui-follow shown)
        (invalidate! win))))

  ;; x, y and button are optional (the tests leave them out): by default, a
  ;; left release at the pointer.
  (define (ui-mouse-up ui . more)
    (let ([x (if (pair? more) (car more) (ui-state-mx ui))]
          [y (if (pair? more) (cadr more) (ui-state-my ui))]
          [button (if (pair? more) (caddr more) 'left)])
      (when (eq? button 'left)
        (let ([a (ui-held ui)])
          (ui-state-active-set! ui #f)
          (when (and a ((ui-region-on a) (list 'release x y)))
            (ui-stale! ui))))
      (invalidate! (current-window))))

  ;; The wheel is offered to each live region under the pointer, topmost
  ;; first.
  (define (ui-wheel ui dy)
    (ui-rest! ui +inf.0)
    (let ([x (ui-state-mx ui)] [y (ui-state-my ui)])
      (and (exists (lambda (r)
                     (and (ui-region-on r) (ui-region-in? r x y)
                          ((ui-region-on r) (list 'wheel dy))))
                   (ui-live ui))
           (begin (ui-stale! ui) #t))))

  ;; A key goes along a chain: the focused widget, Tab, a modal (which takes
  ;; every key), Escape (which clears the focus), then the app's own key
  ;; handler.
  (define (ui-key ui key mods app-key)
    (ui-rest! ui +inf.0)
    (let* ([f (ui-live-region ui (ui-state-focus ui))]
           [modal (find ui-region-modal? (ui-live ui))]
           [done?
            (cond
              [(and f (ui-region-on f) ((ui-region-on f) (list 'key key mods)))]
              [(and (eq? key 'tab) (member mods '(() (shift)))
                    (ui-tab! ui (if (null? mods) 1 -1)))]
              [modal ((ui-region-on modal) (list 'key key mods)) #t]
              [(and (eq? key 'escape) (ui-state-focus ui)) (ui-focus! ui #f) #t]
              [app-key (app-key (current-window) key mods)]
              [else #f])])
      (when done? (ui-stale! ui))
      done?))

  ;; Typed text goes to the focused widget, else to a modal, else to the
  ;; app's handler.
  (define (ui-text ui str app-text)
    (ui-rest! ui +inf.0)
    (let* ([f (ui-live-region ui (ui-state-focus ui))]
           [modal (find ui-region-modal? (ui-live ui))]
           [done?
            (cond
              [(and f (ui-region-on f) ((ui-region-on f) (list 'text str)))]
              [modal #t]
              [app-text (app-text (current-window) str)]
              [else #f])])
      (when done? (ui-stale! ui))
      done?))

  ;; Returns open-window options: the kit's mouse, wheel, key, text and
  ;; frame handlers, and 'ui ui. app may give 'key (win key mods) and 'text
  ;; (win str), the app's own handlers, called for what the kit did not
  ;; take; they return true when they acted.
  (define (ui-handlers ui . app)
    (let ([key (plist-ref app 'key #f)] [text (plist-ref app 'text #f)])
      (list 'mouse-down (lambda (win x y button clicks)
                          (ui-fresh! ui)
                          (ui-mouse-down ui x y button clicks))
            'mouse-move (lambda (win x y) (ui-mouse-move ui x y))
            'mouse-up (lambda (win x y button)
                        (ui-fresh! ui)
                        (ui-mouse-up ui x y button))
            'wheel (lambda (win dx dy) (ui-fresh! ui) (ui-wheel ui dy))
            'key (lambda (win k mods) (ui-fresh! ui) (ui-key ui k mods key))
            'text (lambda (win str) (ui-fresh! ui) (ui-text ui str text))
            'frame (lambda (win t) (ui-frame ui win))
            'ui ui)))

  ;; The handler of the region under an overlay: a press calls on-dismiss;
  ;; every key is taken, going to on-key first (Escape, when on-key does not
  ;; take it, calls on-dismiss); the wheel is taken too.
  (define (ui-modal-on on-dismiss on-key)
    (lambda (ev)
      (case (car ev)
        [(press) (on-dismiss) #t]
        [(key) (unless (on-key (cadr ev) (caddr ev))
                 (when (eq? (cadr ev) 'escape) (on-dismiss)))
               #t]
        [(wheel) #t]
        [else #f])))

  ;; A region pressed like a button: a left press, or one of keys (with no
  ;; modifiers) while it is focused, calls thunk. opts may give 'disabled
  ;; (no behavior), 'focus (tab by default), 'tip and 'doc (by default doc,
  ;; when it is given).
  (define (ui-pressable! ui id x y w h thunk keys opts . doc)
    (let ([disabled? (plist-ref opts 'disabled #f)])
      (ui-region! ui id x y w h
        'focus (if disabled? 'keep (plist-ref opts 'focus 'tab))
        'tip (plist-ref opts 'tip #f)
        'doc (plist-ref opts 'doc (if (pair? doc) (car doc) '()))
        'on (and (not disabled?)
                 (lambda (ev)
                   (case (car ev)
                     [(press)
                      (and (eq? (list-ref ev 3) 'left) (begin (thunk) #t))]
                     [(key)
                      (and (null? (caddr ev)) (memv (cadr ev) keys)
                           (begin (thunk) #t))]
                     [else #f]))))))

  ;;; ---------------------------------------------------------------- a draw

  (define (ui-begin! ui)
    (let ([win (current-window)])   ; an outside bar shows only if drawn again
      (when win (hashtable-delete! (window-props win) 'scrollbar)))
    (ui-state-regions-set! ui '())
    (ui-state-clip-set! ui #f)
    (ui-state-later-set! ui '())
    (ui-state-due-set! ui #f)
    (ui-state-scans-set! ui '())
    (ui-state-fresh?-set! ui #t))

  ;; Adds an overlay: proc, (lambda (w h) ...), which ui-end! draws above
  ;; everything.
  (define (ui-later! ui proc)
    (ui-state-later-set! ui (cons proc (ui-state-later ui))))

  ;; Ends a draw of a window w × h. It draws the overlays; then a widget that
  ;; vanished loses the focus, a reveal that no scroll view took is dropped,
  ;; the hover follows rows that moved under a still pointer, and the
  ;; tooltip is drawn.
  (define (ui-end! ui w h)
    (let loop ()
      (let ([later (reverse (ui-state-later ui))])
        (unless (null? later)
          (ui-state-later-set! ui '())
          (for-each (lambda (p) (p w h)) later)
          (loop))))
    (ui-wait-on-modal! ui w h)
    (ui-state-reveal-set! ui #f)
    (let ([f (ui-state-focus ui)])
      (when (and f (not (ui-find ui f)))
        (ui-state-focus-set! ui #f)
        (ui-state-edit-set! ui #f)))
    (let ([p (ui-state-popup ui)])
      (when (and p (not (ui-find ui (car p)))) (ui-state-popup-set! ui #f)))
    (let ([win (current-window)])
      (when (and win (memq (window-hover win) '(content scrollbar))
                 (not (ui-state-active ui)))
        ;; Rows may have moved under a still pointer: the tooltip's wait
        ;; starts now, unless a press, key or wheel used it up (+inf.0).
        (ui-hover! ui win (ui-state-mx ui) (ui-state-my ui)
                   (max (now-ms) (car (ui-state-rest ui))))
        ;; No tooltip over the widget that has the keyboard, where typing
        ;; pauses.
        (let* ([r (ui-live-region ui (ui-state-hover-id ui))]
               [tip (and r (not (equal? (ui-region-id r) (ui-state-focus ui)))
                         (ui-region-tip r))]
               [rest (ui-state-rest ui)]
               [at (+ (car rest) ui-tip-ms)])
          (cond
            [(not tip) (void)]
            [(< (now-ms) at) (ui-due! ui at)]
            [else
             (with-place 'tooltip
               (lambda ()
                 (let*-values ([(px py) (values (cadr rest) (caddr rest))]
                               [(tw th) (ui-tooltip-size tip)]
                               [(tx ty) (ui-popup-place (+ px 12) (+ py 20)
                                                        (- py 8) tw th w h)])
                   (ui-draw-tooltip tx ty tw th '() tip))))]))))
    (ui-wake! ui))

  ;;; ---------------------------------------------------------------- menus

  ;; Opens a menu of entries at (x, y) of the screen, with opts as open-menu!
  ;; takes them. The desktop's menu ((schevana desktop menu)) sets this hook;
  ;; until it does, no menu opens.
  (define-hook (ui-menu-open! x y entries . opts) (void))

  ;; Returns the tag of the menu that is open ('tag, as open-menu! takes
  ;; it), or #f. The desktop's menu sets this hook too.
  (define-hook (ui-menu-open-tag) #f)

  ;; Calls ui-menu-open! at a point of the current window's content. Each
  ;; entry's thunk runs with current-window set to this window, then marks
  ;; the ui stale; once the window is closed, an entry does nothing. With
  ;; 'filter, entries may be (lambda (filter) entries), the menu's own
  ;; filtering.
  (define (ui-open-menu! ui x y entries . opts)
    (let ([win (current-window)])
      (define (wrap es)
        (map (lambda (e)
               (if (pair? e)
                   (cons (car e)
                         (lambda ()
                           (when (memq win (windows))
                             (parameterize ([current-window win]) ((cdr e)))
                             (ui-stale! ui)
                             (invalidate! win))))
                   e))
             es))
      (let-values ([(cx cy cw ch) (content-rect win)])
        (apply ui-menu-open! (+ cx x) (+ cy y)
               (if (procedure? entries)
                   (lambda (f) (wrap (entries f)))
                   (wrap entries))
               opts))))

  ;;; ------------------------------------------------------------------
  ;;; modal windows
  ;;; A window can wait on another, its modal child (a file dialog, an
  ;;; editor). While the child is open, the parent takes no input and lies
  ;;; under a scrim, and the child stays above it and takes its keyboard
  ;;; (window-modal-child, in the window manager); closing the parent closes
  ;;; the child. The parent's ui does its part as it ends its draw, so an app
  ;;; needs nothing of its own for this.

  ;; Opens a window w × h as the modal child of parent, centered over it;
  ;; opts are open-window's. Returns the child.
  (define (ui-open-modal parent title w h . opts)
    (let* ([close (plist-ref opts 'close #f)]
           [at (let-values ([(x y pw ph) (content-rect parent)])
                 (cons (exact (round (+ x (/ (- pw w) 2))))
                       (exact (round (+ y (/ (- ph h) 2))))))]
           [child
            (parameterize ([new-window-position at])
              (apply open-window title
                     'size (cons w h)
                     'close (lambda (win)
                              (when close (close win))
                              (when (memq parent (windows))
                                (invalidate! parent)))
                     (plist-remove opts 'close)))])
      (window-set! parent 'modal-child child)
      child))

  ;; While the window waits on its modal child, nothing in it keeps the
  ;; keyboard; a scrim covers it, and a region over all of it takes every
  ;; press (bringing the child to the front), key, text and turn of the
  ;; wheel.
  (define (ui-wait-on-modal! ui w h)
    (let ([child (and (current-window) (window-modal-child (current-window)))])
      (when child
        (when (ui-focused ui) (ui-focus! ui #f))
        (ui-draw-scrim 0 0 w h '())
        (ui-region! ui '(ui modal-child) 0 0 w h 'modal #t 'focus 'keep
          'on (lambda (ev)
                (case (car ev)
                  [(press) (focus-window! child) #t]
                  [(key text wheel) #t]
                  [else #f]))))))

  ;;; ------------------------------------------------------------------
  ;;; sizes and layout

  ;; The shared sizes are settings, rules computed from the fonts, so a
  ;; style may give its own pixels. glyph-size is a glyph's side beside 'ui
  ;; text (a button's plus, a dropdown's chevron), and small-glyph-size its
  ;; side beside 'ui-small text (a chip's ×, a sort arrow).
  (at-load
   (for-each theme-default!
     '(control-height glyph-size small-glyph-size gap pad)
     (list (theme-rule (max 28 (round (+ (font-line-height 'ui) 13))))
           (theme-rule (round (* 4/5 (font-line-height 'ui))))
           (theme-rule (round (* 4/5 (font-line-height 'ui-small))))
           (theme-rule (max 8 (round (/ (font-line-height 'ui) 2))))
           (theme-rule (max 12 (round (* (font-line-height 'ui) 4/5)))))))
  (define (ui-control-height) (theme 'control-height))
  (define (ui-glyph-size) (theme 'glyph-size))
  (define (ui-small-glyph-size) (theme 'small-glyph-size))
  (define (ui-gap) (theme 'gap))
  (define (ui-pad) (theme 'pad))

  ;; Returns where a popup w × h goes in a window ww × wh, as (values x y):
  ;; at x, with its top at below, or its bottom at above when there is no
  ;; room below, and kept inside the window.
  (define (ui-popup-place x below above w h ww wh)
    (values (clamp x 0 (max 0 (- ww w)))
            (clamp (if (<= (+ below h) wh) below (- above h))
                   0 (max 0 (- wh h)))))

  ;; Places sizes ((w . h) ...) left to right from (x, y), gap apart both
  ;; ways, wrapping before an item that would pass x + w; the items in a row
  ;; are centered on its tallest. Pure. Returns (values ((x . y) ...)
  ;; height).
  (define (ui-flow x y w gap sizes)
    (let ([rows (let loop ([ss sizes] [cx x] [row '()] [rows '()])
                  (cond
                    [(null? ss)
                     (reverse (if (null? row) rows (cons (reverse row) rows)))]
                    [(or (null? row) (<= (+ cx (caar ss)) (+ x w)))
                     (loop (cdr ss) (+ cx (caar ss) gap)
                           (cons (cons cx (car ss)) row) rows)]
                    [else (loop ss x '() (cons (reverse row) rows))]))])
      (let loop ([rows rows] [ry y] [acc '()])
        (if (null? rows)
            (values (reverse acc) (max 0 (- ry y gap)))
            (let ([rh (apply max (map cddr (car rows)))])
              (loop (cdr rows) (+ ry rh gap)
                    (append (reverse
                             (map (lambda (it)
                                    (cons (car it)
                                          (+ ry
                                             (floor (/ (- rh (cddr it)) 2)))))
                                  (car rows)))
                            acc)))))))

  ;; Draws a toolbar across w from (x, y). Its items, ((w h draw) ...) with
  ;; each draw a (lambda (x y w h) ...), go left to right a gap apart,
  ;; wrapping. One item's w may be #f: that item takes what the others leave
  ;; of the first row, within 'flex (least . most). 'end, an item, goes at
  ;; the right of the first row (a count, say), and the others leave room for
  ;; it. The toolbar's strip is drawn under the items. Returns the toolbar's
  ;; height.
  (define (ui-toolbar x y w items . opts)
    (let*-values
        ([(pad gap) (values (ui-pad) (ui-gap))]
         [(end) (plist-ref opts 'end #f)]
         [(flex) (plist-ref opts 'flex '(150 . 300))]
         [(room) (- w pad pad (if end (+ (car end) gap) 0))]
         ;; Whole pixels, so that a row the item fills exactly still fits.
         [(fw) (floor (clamp (- room (apply + (filter-map car items))
                                (* gap (max 0 (- (length items) 1))))
                             (car flex) (cdr flex)))]
         [(sizes) (map (lambda (i) (cons (or (car i) fw) (cadr i))) items)]
         [(at height) (ui-flow (+ x pad) (+ y gap) room gap sizes)])
      (ui-draw-surface x y w (+ height gap gap) '(toolbar))
      (for-each (lambda (i s p) ((caddr i) (car p) (cdr p) (car s) (cdr s)))
                items sizes at)
      (when end   ; on the first row, level with its first item
        ((caddr end) (- (+ x w) pad (car end))
                     (if (pair? at) (cdar at) (+ y gap))
                     (car end) (if (pair? sizes) (cdar sizes) (cadr end))))
      (+ height gap gap)))

  ;;; ------------------------------------------------------------------
  ;;; dates, pure: a date is (year month day), and a day number counts the
  ;;; days since 1970-01-01

  (define (ui-date->day d)
    (let* ([m (cadr d)] [y (if (<= m 2) (- (car d) 1) (car d))]
           [era (div y 400)] [yoe (- y (* era 400))]
           [doy (+ (quotient (+ (* 153 (mod (+ m 9) 12)) 2) 5) (- (caddr d) 1))]
           [doe (+ (* yoe 365) (quotient yoe 4) (- (quotient yoe 100)) doy)])
      (+ (* era 146097) doe -719468)))

  (define (ui-day->date n)
    (let* ([z (+ n 719468)] [era (div z 146097)] [doe (- z (* era 146097))]
           [yoe (quotient (- doe (quotient doe 1460) (- (quotient doe 36524))
                             (quotient doe 146096))
                          365)]
           [doy (- doe (+ (* 365 yoe) (quotient yoe 4) (- (quotient yoe 100))))]
           [mp (quotient (+ (* 5 doy) 2) 153)]
           [d (+ (- doy (quotient (+ (* 153 mp) 2) 5)) 1)]
           [m (if (< mp 10) (+ mp 3) (- mp 9))])
      (list (+ yoe (* era 400) (if (<= m 2) 1 0)) m d)))

  ;; 0 is Monday.
  (define (ui-week-day n) (mod (+ n 3) 7))

  (define (ui-days-in-month y m)
    (- (ui-date->day (if (= m 12) (list (+ y 1) 1 1) (list y (+ m 1) 1)))
       (ui-date->day (list y m 1))))

  ;; Returns day n moved by k months, its day of the month clamped to the
  ;; new month.
  (define (ui-add-months n k)
    (let* ([d (ui-day->date n)] [m0 (+ (cadr d) k -1)]
           [y (+ (car d) (div m0 12))] [m (+ 1 (mod m0 12))])
      (ui-date->day (list y m (min (caddr d) (ui-days-in-month y m))))))

  (define (ui-today)
    (let ([d (current-date)]) (list (date-year d) (date-month d) (date-day d))))

  ;; The months' short names.
  (define ui-month-names
    '#("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

  ;; A date's label: "Nov 14, 2026".
  (define (ui-date-label d)
    (format "~a ~a, ~a" (vector-ref ui-month-names (- (cadr d) 1)) (caddr d)
            (car d)))

  (define ui-month-titles
    '#("January" "February" "March" "April" "May" "June" "July" "August"
       "September" "October" "November" "December"))

  ;; The time, in ms, of the next local midnight.
  (define (ui-next-midnight)
    (let ([d (current-date)])
      (+ (now-ms)
         (* 1000 (- 86400 (* 3600 (date-hour d)) (* 60 (date-minute d))
                    (date-second d))))))

  ;;; ------------------------------------------------------------------
  ;;; shared drawing

  ;; More font roles, made from the font settings as the core's are:
  ;; Genera's pane headings and fixed italic, and the CADR's current choice.
  (at-load
   (theme-default! 'ui-bold-italic (theme-font-rule 'ui 0 'bold 'italic)))
  (at-load
   (theme-default! 'mono-italic (theme-font-rule 'mono 0 'italic)))
  (at-load
   (theme-default! 'ui-small-bold (theme-font-rule 'ui -2 'bold)))

  ;; Returns f's italic, keeping its bold: a style's 'faint-text-font where
  ;; the style has no gray (Genera's hints and type descriptions).
  (define (ui-italic-of f)
    (apply font (font-family f) (font-size f) 'italic
           (if (eq? (font-weight f) 'bold) '(bold) '())))

  ;; The ring around a widget that got the keyboard from Tab.
  (define-part (ui-draw-focus x y w h flags r)
    (stroke-box (- x 3) (- y 3) (+ w 6) (+ h 6) (alpha 'accent 0.7) 2 (+ r 3)))

  ;; The box of a widget that takes typing (a text box, a chip input), with
  ;; an accent border while it has the keyboard.
  (define-part (ui-draw-field x y w h flags)
    (fill-box x y w h 'bg-0 6)
    (if (memq 'focused flags)
        (stroke-box x y w h 'accent 1.5 6)
        (stroke-box x y w h (if (memq 'hover flags) 'text-faint 'window-border)
                    1
                    6)))

  ;; Vector glyphs, drawn with no font and centered in the box: check,
  ;; cross, plus, chevron-down, chevron-left, chevron-right, search and
  ;; expand; the triangles up, down, left and right (sort marks, scroll
  ;; arrows, submenus; sort-up and sort-down are other names for up and
  ;; down); pin and undo (Settings' rows); edit, a pencil (an entry row's);
  ;; minus (a stepper's); globe, folder, box and gear, in outline, and
  ;; prompt, a REPL's (the environments); chip, a processor; home, file,
  ;; drive and chevron-up (the file dialog); panel-right and panel-left, a
  ;; window with a pane along that side, filled in as panel-right-shown and
  ;; panel-left-shown (a side panel's button); and a window's buttons,
  ;; close, minimize, maximize, restore and shade, which fill a square box
  ;; in lines of 1 pixel. flags may hold (ink . color) and (width . w), the
  ;; width of those lines.
  (define-part (ui-draw-glyph x y w h flags name)
    (let* ([s (min w h)] [ox (+ x (/ (- w s) 2))] [oy (+ y (/ (- h s) 2))]
           [p (lambda (fx fy) (cons (+ ox (* fx s)) (+ oy (* fy s))))]
           [given (lambda (key)
                    (let ([f (find (lambda (f)
                                     (and (pair? f) (eq? (car f) key)))
                                   flags)])
                      (and f (cdr f))))]
           [ink (cond [(given 'ink)]
                      [(memq 'primary flags) (color-readable-on 'accent)]
                      [(and (memq 'danger flags) (memq 'hover flags)) 'red]
                      [(memq 'hover flags) 'text]
                      [(memq 'quiet flags) 'text-faint]
                      [else 'text-dim])]
           [ink (if (memq 'disabled flags) (alpha ink 0.5) ink)]
           [lw (max 1.5 (* s 0.13))]
           [t (or (given 'width) 1)])
      (define (line . ps) (draw-polyline ps ink lw))
      (define (triangle . ps) (fill-polygon (map (lambda (q) (apply p q)) ps)
                                            ink))
      (case name
        [(check) (line (p 0.2 0.52) (p 0.42 0.74) (p 0.8 0.3))]
        [(cross) (line (p 0.28 0.28) (p 0.72 0.72))
                 (line (p 0.72 0.28) (p 0.28 0.72))]
        [(plus) (line (p 0.5 0.2) (p 0.5 0.8)) (line (p 0.2 0.5) (p 0.8 0.5))]
        [(minus) (line (p 0.2 0.5) (p 0.8 0.5))]
        [(edit)   ; a pencil, its point at the bottom left
         (line (p 0.16 0.84) (p 0.22 0.62) (p 0.66 0.18) (p 0.82 0.34)
               (p 0.38 0.78) (p 0.16 0.84))
         (line (p 0.58 0.26) (p 0.74 0.42))]
        [(prompt)   ; >_
         (line (p 0.18 0.28) (p 0.44 0.5) (p 0.18 0.72))
         (line (p 0.52 0.74) (p 0.86 0.74))]
        [(chevron-down) (line (p 0.25 0.38) (p 0.5 0.63) (p 0.75 0.38))]
        [(chevron-up) (line (p 0.25 0.62) (p 0.5 0.37) (p 0.75 0.62))]
        [(home)   ; a roof over a house with a door
         (line (p 0.1 0.5) (p 0.5 0.14) (p 0.9 0.5))
         (line (p 0.22 0.4) (p 0.22 0.86) (p 0.78 0.86) (p 0.78 0.4))
         (line (p 0.42 0.86) (p 0.42 0.62) (p 0.58 0.62) (p 0.58 0.86))]
        [(file)   ; a page, its corner folded
         (line (p 0.22 0.1) (p 0.6 0.1) (p 0.8 0.3) (p 0.8 0.9) (p 0.22 0.9)
               (p 0.22 0.1))
         (line (p 0.6 0.1) (p 0.6 0.3) (p 0.8 0.3))]
        [(drive)   ; a disk's box and its light
         (line (p 0.1 0.32) (p 0.9 0.32) (p 0.9 0.72) (p 0.1 0.72) (p 0.1 0.32))
         (line (p 0.66 0.52) (p 0.76 0.52))]
        [(panel-right panel-right-shown panel-left panel-left-shown)
         (let ([edge (if (memq name '(panel-right panel-right-shown)) 0.6 0.4)])
           (line (p 0.08 0.2) (p 0.92 0.2) (p 0.92 0.8) (p 0.08 0.8)
                 (p 0.08 0.2))
           (line (p edge 0.2) (p edge 0.8))
           (when (memq name '(panel-right-shown panel-left-shown))
             (let ([far (if (> edge 0.5) 0.92 0.08)])
               (fill-polygon (list (p edge 0.2) (p far 0.2) (p far 0.8)
                                   (p edge 0.8))
                             ink))))]
        [(chevron-left) (line (p 0.62 0.25) (p 0.37 0.5) (p 0.62 0.75))]
        [(chevron-right) (line (p 0.38 0.25) (p 0.63 0.5) (p 0.38 0.75))]
        [(up sort-up) (triangle '(0.5 0.3) '(0.8 0.7) '(0.2 0.7))]
        [(down sort-down) (triangle '(0.5 0.7) '(0.8 0.3) '(0.2 0.3))]
        [(left) (triangle '(0.3 0.5) '(0.7 0.2) '(0.7 0.8))]
        [(right) (triangle '(0.7 0.5) '(0.3 0.2) '(0.3 0.8))]
        [(close) (draw-line ox oy (+ ox s) (+ oy s) ink t)
                 (draw-line (+ ox s) oy ox (+ oy s) ink t)]
        [(minimize) (fill-box ox (+ oy (ceiling (/ (- s t) 2))) s t ink)]
        [(maximize) (stroke-box ox oy s s ink t)]
        [(restore)   ; a sheet in front of another
         (stroke-box ox (+ oy 2) (- s 2) (- s 2) ink)
         (fill-box (+ ox 2) oy (- s 2) 1 ink)
         (fill-box (+ ox s -1) oy 1 (- s 2) ink)]
        [(shade) (stroke-box ox oy s (ceiling (/ s 3)) ink t)]   ; a title bar
        [(pin)   ; a pushpin from the side: its head, its collar, its point
         (fill-circle (+ ox (* 0.5 s)) (+ oy (* 0.3 s)) (* 0.25 s) ink)
         (line (p 0.22 0.56) (p 0.78 0.56))
         (line (p 0.5 0.56) (p 0.5 1))]
        [(undo)   ; ↺: three quarters of a circle, an arrowhead at its top
         (apply line (map (lambda (i)
                            (let ([a (* pi (/ (- i 6) 12))])
                              (p (+ 0.5 (* 0.38 (cos a)))
                                 (+ 0.56 (* 0.38 (sin a))))))
                          (iota 19)))
         (triangle '(0.26 0.18) '(0.56 0) '(0.56 0.36))]
        [(search)
         (stroke-circle (+ ox (* 0.43 s)) (+ oy (* 0.43 s)) (* 0.25 s) ink lw)
         (line (p 0.62 0.62) (p 0.82 0.82))]
        [(expand)   ; two arrows out to opposite corners
         (line (p 0.56 0.2) (p 0.8 0.2) (p 0.8 0.44))
         (line (p 0.8 0.2) (p 0.55 0.45))
         (line (p 0.44 0.8) (p 0.2 0.8) (p 0.2 0.56))
         (line (p 0.2 0.8) (p 0.45 0.55))]
        [(globe)   ; a circle, a meridian and the equator
         (stroke-circle (+ ox (* 0.5 s)) (+ oy (* 0.5 s)) (* 0.4 s) ink lw)
         (apply line (map (lambda (i)
                            (let ([a (* pi (/ i 8))])
                              (p (+ 0.5 (* 0.17 (cos a)))
                                 (+ 0.5 (* 0.4 (sin a))))))
                          (iota 17)))
         (line (p 0.1 0.5) (p 0.9 0.5))]
        [(folder)   ; a tab, then the folder
         (line (p 0.1 0.22) (p 0.4 0.22) (p 0.5 0.34) (p 0.9 0.34) (p 0.9 0.8)
               (p 0.1 0.8) (p 0.1 0.22))]
        [(box)   ; a cube from above: its outline, and its near edges
         (line (p 0.5 0.1) (p 0.86 0.3) (p 0.86 0.7) (p 0.5 0.9) (p 0.14 0.7)
               (p 0.14 0.3) (p 0.5 0.1))
         (line (p 0.14 0.3) (p 0.5 0.5) (p 0.86 0.3))
         (line (p 0.5 0.5) (p 0.5 0.9))]
        [(chip)   ; a chip from above: its body, and two pins on each side
         (line (p 0.28 0.28) (p 0.72 0.28) (p 0.72 0.72) (p 0.28 0.72)
               (p 0.28 0.28))
         (for-each (lambda (f)
                     (line (p f 0.1) (p f 0.28))
                     (line (p f 0.72) (p f 0.9))
                     (line (p 0.1 f) (p 0.28 f))
                     (line (p 0.72 f) (p 0.9 f)))
                   '(0.38 0.62))]
        [(gear)   ; six teeth around a hub
         (let ([at (lambda (r a)
                     (p (+ 0.5 (* r (cos a))) (+ 0.5 (* r (sin a)))))])
           (apply line
                  (append
                   (apply append
                          (map (lambda (k)
                                 (let ([a (* pi (/ k 3))])
                                   (list (at 0.32 (- a 0.42))
                                         (at 0.47 (- a 0.2))
                                         (at 0.47 (+ a 0.2))
                                         (at 0.32 (+ a 0.42)))))
                               (iota 6)))
                   (list (at 0.32 -0.42)))))
         (stroke-circle (+ ox (* 0.5 s)) (+ oy (* 0.5 s)) (* 0.13 s) ink lw)])))

  ;; Returns the glyph for win's frame button of kind: a maximized window's
  ;; maximize button shows restore.
  (define (ui-frame-glyph win kind)
    (if (and (eq? kind 'maximize) (maximized? win)) 'restore kind))

  ;;; ---------------------------------------------------------------- button

  ;; opts: 'glyph, 'tip, 'disabled, and the flags 'primary (the suggested
  ;; action), 'danger, 'quiet (flat: no box until the pointer is on it),
  ;; 'selected (pressed in), 'pill and 'circular (round ends; a round
  ;; button), 'join-left and 'join-right (square on that side, where a
  ;; linked neighbor touches it), and 'segment (a piece of a segmented
  ;; choice).
  (define (ui-button ui id x y w h label on-press . opts)
    (ui-pressable! ui id x y w h on-press '(#\space return) opts
                   (list (cons 'L (or label (plist-ref opts 'tip #f) "Press"))))
    (ui-draw-button x y w h
                    (apply ui-flags ui id
                           (ui-opt-flags opts '(selected primary danger quiet
                                                disabled pill circular
                                                join-left join-right
                                                segment)))
                    label (plist-ref opts 'glyph #f)))

  ;; A box x..x+w with corners of radius r, except on its joined sides
  ;; (flags join-left, join-right), is drawn as a rounded box that much
  ;; wider on those sides, cut to x..x+w (with-clip). Returns (values x w)
  ;; of that wider box.
  (define (ui-joined-span x w r flags)
    (let ([l (if (memq 'join-left flags) r 0)]
          [rt (if (memq 'join-right flags) r 0)])
      (values (- x l) (+ w l rt))))

  ;; Returns a button's corner radius: half its height when it is a pill or
  ;; round, else r.
  (define (ui-button-radius h flags r)
    (if (or (memq 'pill flags) (memq 'circular flags)) (/ h 2) r))

  ;; Buttons side by side, joined into one (a linked group). items are ((key
  ;; label thunk opt ...) ...), with opts as ui-button's; each button is as
  ;; wide as ui-button-size says unless it gives 'width, and neighbors share
  ;; their edge's pixel. Returns the x after the last button.
  (define (ui-linked ui id x y h items)
    (let loop ([is items] [bx x] [first? #t])
      (if (null? is)
          (+ bx 1)
          (let* ([it (car is)] [opts (cdddr it)]
                 [bw (or (plist-ref opts 'width #f)
                         (let-values ([(w bh) (ui-button-size
                                               (cadr it)
                                               (plist-ref opts 'glyph #f))])
                           w))])
            (apply ui-button ui (list id (car it)) bx y bw h (cadr it)
                   (caddr it) 'join-left (not first?)
                   'join-right (pair? (cdr is)) opts)
            (loop (cdr is) (+ bx bw -1) #f)))))

  ;; A primary button's fill while pressed, and under the pointer.
  (at-load
   (color-default! 'primary-pressed (theme-rule (mix 'accent 'bg-0 0.15))))
  (at-load
   (color-default! 'primary-hover (theme-rule (mix 'accent 'text 0.15))))

  ;; The built-in button's box: its fill and its outline, either of which
  ;; may be #f.
  (define (ui-draw-button-box x y w h fill stroke r)
    (when fill (fill-box x y w h fill r))
    (when stroke (stroke-box x y w h stroke 1 r)))

  ;; With only the flags hover and selected, this is the look Settings was
  ;; designed with.
  (define-part (ui-draw-button x y w h flags label glyph)
    (let* ([flags (if (memq 'disabled flags)   ; the pointer does nothing
                      (remp (lambda (f) (memq f '(hover pressed))) flags)
                      flags)]
           [on? (lambda (f) (memq f flags))]
           [ink (lambda (c) (if (on? 'disabled) (alpha c 0.5) c))]
           [hot? (or (on? 'hover) (on? 'pressed))]
           [fill (cond [(on? 'primary)
                        (cond [(on? 'pressed) 'primary-pressed]
                              [(on? 'hover) 'primary-hover]
                              [else 'accent])]
                       [(on? 'selected) (alpha 'accent 0.25)]
                       [(on? 'pressed) (mix 'bg-3 'text 0.08)]
                       [(and (on? 'danger) (on? 'hover)) (alpha 'red 0.15)]
                       [(on? 'hover) 'bg-3]
                       [(on? 'quiet) #f]
                       [else 'bg-2])]
           [stroke (cond [(or (on? 'primary) (and (on? 'quiet) (not hot?))) #f]
                         [(on? 'selected) 'accent]
                         [(on? 'danger) 'red]
                         [else 'window-border])]
           [color (cond [(on? 'primary) (color-readable-on 'accent)]
                        [(on? 'danger) 'red]
                        [(or (on? 'hover) (on? 'selected)) 'text]
                        [else 'text-dim])]
           [lh (font-line-height 'ui)] [g (ui-glyph-size)]
           [gw (if glyph (* 3/2 g) 0)]   ; the glyph and its gap
           [label (and label (text-fit label (- w 12 gw) 'ui))]
           [cw (if label (+ gw (text-width label 'ui)) g)]
           [x0 (+ x (/ (- w cw) 2))]
           [r (ui-button-radius h flags 6)])
      (if (or (on? 'join-left) (on? 'join-right))
          (let-values ([(bx bw) (ui-joined-span x w r flags)])
            (with-clip (x y w h)
              (ui-draw-button-box bx y bw h (and fill (ink fill))
                                  (and stroke (ink stroke)) r)))
          (ui-draw-button-box x y w h (and fill (ink fill))
                              (and stroke (ink stroke)) r))
      (when glyph (ui-draw-glyph x0 (+ y (/ (- h g) 2)) g g flags glyph))
      (when label
        (draw-text (+ x0 gw) (+ y (/ (- h lh) 2)) label (ink color) 'ui))
      (when (on? 'focused) (ui-draw-focus x y w h flags r))))

  ;; A glyph alone makes a square button.
  (define-part (ui-button-size label glyph)
    (let ([h (ui-control-height)])
      (values (if label
                  (+ 24 (text-width label 'ui)
                     (if glyph (* 3/2 (ui-glyph-size)) 0))
                  h)
              h)))

  ;; A segmented control. choices: ((label . value) ...); the one equal? to
  ;; current is selected. opts: 'tip, shared by every choice. Each choice is
  ;; a button flagged segment, the style's segmented-gap apart; with no gap,
  ;; they form one group with its inner edges joined (join-left,
  ;; join-right).
  (define (ui-segmented ui id x y w h choices current on-select . opts)
    (let* ([n (length choices)] [gap (theme 'segmented-gap)]
           [bw (/ w n)] [joined? (zero? gap)])
      (for-each (lambda (c i)
                  (ui-button ui (list id (cdr c)) (+ x (* i bw)) y (- bw gap) h
                             (car c) (lambda () (on-select (cdr c)))
                             'selected (equal? current (cdr c))
                             'segment #t
                             'join-left (and joined? (> i 0))
                             'join-right (and joined? (< i (- n 1)))
                             'tip (plist-ref opts 'tip #f)))
                choices (iota n))))

  ;; The space between two choices of a segmented control.
  (at-load
   (theme-default! 'segmented-gap 6))

  ;; A whole number from lo to hi: a field that takes only digits, aligned
  ;; at its right as a table's numbers are, with a button on either side, or
  ;; both after it (ui-stepper-areas), each a step of 1, as Up and Down are.
  ;; What is typed counts at once if it is in range; if not, Return brings it
  ;; into range, and the field forgets it when it loses the keyboard. opts:
  ;; 'tip. Returns the stepper's width.
  (define (ui-stepper ui id x y value lo hi on-change . opts)
    (let-values ([(w h) (ui-stepper-size lo hi)])
      (let* ([tip (plist-ref opts 'tip #f)]
             [areas (ui-stepper-areas x y w h)]
             [area (lambda (k) (list-head (cdr (assq k areas)) 4))]
             [joins (lambda (k)
                      (apply append
                             (map (lambda (f) (list f #t))
                                  (list-tail (cdr (assq k areas)) 4))))]
             [glyphs (theme 'stepper-glyphs)]
             [field (list id 'field)] [typed (list id 'typed)]
             [step! (lambda (n)
                      (ui-memo! ui typed #f)
                      (on-change (clamp n lo hi)))])
        (unless (equal? (ui-focused ui) field) (ui-memo! ui typed #f))
        (apply ui-button ui (list id 'down)
               (append (area 'down)
                       (list #f (lambda () (step! (- value 1)))
                             'glyph (car glyphs) 'disabled (<= value lo)
                             'tip tip)
                       (joins 'down)))
        (apply ui-text-field ui field
               (append
                (area 'field)
                (list (or (ui-memo ui typed #f) (number->string value))
                      (lambda (text)
                        (when (ui-stepper-text? text lo)
                          (ui-memo! ui typed text)
                          (let ([n (string->number text)])
                            (when (and n (<= lo n hi)) (on-change n)))))
                      'tip tip
                      'right #t
                      'max (apply max
                                  (map (lambda (n)
                                         (string-length (number->string n)))
                                       (list lo hi)))
                      'on-enter (lambda ()
                                  (let ([n (string->number
                                            (or (ui-memo ui typed #f) ""))])
                                    (if n
                                        (step! n)
                                        (ui-memo! ui typed #f))))
                      'on-key (lambda (key mods text)
                                (and (null? mods) (memq key '(up down))
                                     (begin
                                       (step! (+ value
                                                 (if (eq? key 'up) 1 -1)))
                                       #t))))
                (joins 'field)))
        (apply ui-button ui (list id 'up)
               (append (area 'up)
                       (list #f (lambda () (step! (+ value 1)))
                             'glyph (cdr glyphs) 'disabled (>= value hi)
                             'tip tip)
                       (joins 'up)))
        w)))

  ;; Where a stepper w × h puts its buttons and its field: ((down x y w h
  ;; flag ...) (field ...) (up ...)), each flag (join-left, join-right) a
  ;; side the piece shares with a neighbor. This one puts a button on either
  ;; side, each a square of the control height, and the field between them.
  (define-part (ui-stepper-areas x y w h)
    (let ([b (ui-control-height)])
      (list (list 'down x y b b)
            (list 'field (+ x b) y (- w b b) h)
            (list 'up (- (+ x w) b) y b b))))

  ;; The stepper's glyphs, (down . up).
  (at-load
   (theme-default! 'stepper-glyphs '(chevron-left . chevron-right)))

  ;; Whether text, as it is typed, can become a number here: digits, after a
  ;; minus sign when the range goes below 0.
  (define (ui-stepper-text? text lo)
    (let ([chars (string->list text)])
      (for-all char-numeric?
               (if (and (< lo 0) (pair? chars) (char=? (car chars) #\-))
                   (cdr chars)
                   chars))))

  ;; A stepper's size: its two buttons, and a field whose text holds the
  ;; widest number and no more, inside the style's own insets, so that the
  ;; widest number fills it with the same room on either side, and a
  ;; narrower one sits at its right.
  (define (ui-stepper-size lo hi)
    (let ([b (ui-control-height)])
      (values (+ b b (ui-text-box-insets '(field))
                 (text-widest (map number->string (list lo hi)) 'ui))
              b)))

  ;; A path shown as crumbs: labels, oldest first, each a button that calls
  ;; (on-select i), with a chevron between them; all but the last are quiet,
  ;; and the last is the one you are in. What does not fit in w is hidden,
  ;; from the oldest on, behind a … that selects the newest of those it
  ;; hides.
  (define (ui-breadcrumbs ui id x y w h labels on-select)
    (let* ([g (ui-small-glyph-size)] [sep (+ g 6)]
           [widths (map (lambda (l)
                          (let-values ([(bw bh) (ui-button-size l #f)])
                                      (- bw 8)))
                        labels)]
           [n (length labels)]
           [dots (let-values ([(bw bh) (ui-button-size "…" #f)]) (- bw 8))]
           ;; how many of the oldest go into the …
           [hidden (let loop ([k 0])
                     (let ([need (+ (apply + (list-tail widths k))
                                    (* sep (- n k 1))
                                    (if (> k 0) (+ dots sep) 0))])
                       (if (or (<= need w) (>= k (- n 1))) k (loop (+ k 1)))))])
      (let loop ([i hidden] [cx (if (> hidden 0)
                                    (begin
                                      (ui-button ui (list id 'more) x y dots h
                                                 "…"
                                                 (lambda () (on-select
                                                             (- hidden 1)))
                                                 'quiet #t 'focus 'keep
                                                 'tip (list-ref labels
                                                                (- hidden 1)))
                                      (ui-draw-glyph (+ x dots 3)
                                                     (+ y (/ (- h g) 2)) g g
                                                     '(quiet) 'chevron-right)
                                      (+ x dots sep))
                                    x)])
        (when (< i n)
          (let ([bw (min (list-ref widths i) (max 0 (- (+ x w) cx)))])
            (ui-button ui (list id i) cx y bw h (list-ref labels i)
                       (lambda () (on-select i))
                       'quiet (< i (- n 1)) 'focus 'keep)
            (when (< i (- n 1))
              (ui-draw-glyph (+ cx bw 3) (+ y (/ (- h g) 2)) g g '(quiet)
                             'chevron-right))
            (loop (+ i 1) (+ cx bw sep)))))))

  ;;; ---------------------------------------------------------------- nav
  ;;; A column of places to go, one of which is where you are: Settings'
  ;;; tabs, a file dialog's places.

  ;; items: ((value label icon) ...), icon being #f or a (lambda (x y s
  ;; flags) ...) that draws one s square. The item equal? to current is
  ;; selected; a press, or Space or Return on a focused item, calls
  ;; (on-select value). The rows are ui-nav-row-height high and 6 apart,
  ;; from y. Returns the y below the last row and its gap.
  (define (ui-nav ui id x y w items current on-select)
    (let ([rh (ui-nav-row-height)])
      (fold-left
       (lambda (ry item)
         (let ([rid (list id (car item))])
           (ui-pressable! ui rid x ry w rh (lambda () (on-select (car item)))
                          '(#\space return) '() (list (cons 'L (cadr item))))
           (ui-draw-nav-row x ry w rh
                            (apply ui-flags ui rid
                                   (if (equal? (car item) current)
                                       '(selected)
                                       '()))
                            (cadr item) (caddr item))
           (+ ry rh 6)))
       y items)))

  (define (ui-nav-row-height) (max 32 (round (+ (font-line-height 'ui) 12))))

  ;; flags: selected, hover, focused. The selected row is highlighted, with
  ;; a mark at its left; the label comes after the icon, if any.
  (define-part (ui-draw-nav-row x y w h flags label icon)
    (let* ([selected? (memq 'selected flags)] [g (ui-glyph-size)]
           [lx (if icon (+ x 14 g 8) (+ x 14))])
      (cond [selected? (ui-draw-highlight x y w h '())]
            [(memq 'hover flags) (ui-draw-highlight x y w h '(hover))])
      (when icon (icon (+ x 14) (+ y (/ (- h g) 2)) g flags))
      (ui-draw-label lx y (- (+ x w) lx 6) h (if selected? '() '(dim)) label)
      (when selected?
        (ui-draw-highlight-over x y w h '())
        ;; The mark comes after that, so that a style that inverts the row
        ;; keeps the mark whole (in ink on ink).
        (fill-box x (+ y (/ h 2) -8) 3 16 'accent 1.5))
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 5))))

  ;;; ---------------------------------------------------------------- slider

  ;; A horizontal slider. on-change receives the new value in [lo, hi].
  ;; paint-track, if given, draws the track: (lambda (x y w h) ...). opts:
  ;; 'tip.
  (define ui-slider
    (case-lambda
      [(ui id x y w value lo hi on-change)
       (ui-slider ui id x y w value lo hi on-change #f)]
      [(ui id x y w value lo hi on-change paint-track . opts)
       (let ([h (ui-slider-height)])
         (ui-area ui id (- x 8) y (+ w 16) h #f
                  (lambda (mx my)
                    (on-change
                     (+ lo (* (- hi lo) (clamp (/ (- mx x) w) 0 1)))))
                  'doc '((L . "Set")) 'tip (plist-ref opts 'tip #f))
         (ui-draw-slider x y w h (ui-flags ui id)
                         (clamp (/ (- value lo) (- hi lo)) 0 1) paint-track))]))

  (at-load
   (theme-default! 'slider-height 24))
  (define (ui-slider-height) (theme 'slider-height))

  (define-part (ui-draw-slider x y w h flags frac paint)
    (let* ([cy (+ y (/ h 2))] [kx (+ x (* frac w))]
           [r (if (or (memq 'hover flags) (memq 'pressed flags)) 8 7)])
      (if paint
          (with-clip (x (- cy 4) w 8 4) (paint x (- cy 4) w 8))
          (begin
            (fill-box x (- cy 3) w 6 'bg-3 3)
            (fill-box x (- cy 3) (max 6 (- kx x)) 6 'accent 3)))
      (fill-circle kx cy r #xf2f2f5)
      (stroke-circle kx cy r (alpha #x000000 0.35) 1)))

  ;;; ------------------------------------------------------------------
  ;;; checkbox and toggle: one behavior, two looks

  (define (ui-checkbox ui id x y w h label checked? on-change . opts)
    ;; A cut label gets a tooltip; a box alone (no label) has none.
    (let-values ([(kw kh) (if label (ui-checkbox-size label) (values 0 0))])
      (ui-pressable! ui id x y w h (lambda () (on-change (not checked?)))
                     '(#\space)
                     (cons* 'tip (or (plist-ref opts 'tip #f)
                                     (and (> kw w) label))
                            opts)
                     '((L . "Toggle"))))
    (ui-draw-checkbox x y w h
                      (apply ui-flags ui id
                             (append (if checked? '(checked) '())
                                     (if (plist-ref opts 'disabled #f)
                                         '(disabled)
                                         '())))
                      label))

  (define (ui-toggle ui id x y w h label on? on-change . opts)
    (ui-pressable! ui id x y w h (lambda () (on-change (not on?)))
                   '(#\space) opts '((L . "Toggle")))
    (ui-draw-toggle x y w h (apply ui-flags ui id (if on? '(checked) '()))
                    label))

  (define (ui-checkbox-box) (round (+ (font-line-height 'ui) 1)))

  ;; flags: checked, hover, focused, disabled (faded, and the pointer does
  ;; nothing).
  (define-part (ui-draw-checkbox x y w h flags label)
    (let* ([b (ui-checkbox-box)] [by (+ y (floor (/ (- h b) 2)))]
           [lh (font-line-height 'ui)] [checked? (memq 'checked flags)]
           [off? (memq 'disabled flags)]
           [flags (if off? (remq 'hover flags) flags)])
      (if checked?
          (begin (fill-box x by b b
                           (if off? (alpha 'accent 0.45) 'accent)
                           4)
                 (ui-draw-glyph x by b b '(primary) 'check))
          (begin (fill-box x by b b 'bg-0 4)
                 (stroke-box x by b b
                             (if (memq 'hover flags)
                                 'accent
                                 'text-faint)
                             1 4)))
      (when label
        (draw-text (+ x b 8) (+ y (/ (- h lh) 2))
                   (text-fit label (- w b 8) 'ui)
                   (if checked? 'text-dim 'text) 'ui))
      (when (memq 'focused flags) (ui-draw-focus x by b b flags 4))))

  (define-part (ui-checkbox-size label)
    (values (+ (ui-checkbox-box) 8 (text-width label 'ui)) (ui-control-height)))

  ;;; ------------------------------------------------------------------
  ;;; live: whether a view follows what happens, or holds still

  ;; A badge that says whether a view is live: "Live", with a dot; or, when
  ;; held, what it holds (held-label) and the way back. A press or Space
  ;; switches it, calling (on-change live?) with the other state.
  (define (ui-live-badge ui id x y w h live? held-label on-change . opts)
    (ui-pressable! ui id x y w h (lambda () (on-change (not live?)))
                   '(#\space) opts
                   (list (cons 'L (if live? "Hold still" "Back to live"))))
    (ui-draw-live-badge x y w h
                        (apply ui-flags ui id (if live? '(checked) '()))
                        (if live? "Live" held-label)))

  (define ui-live-badge-back " · back to live")

  ;; The dot's or the pause mark's width.
  (define (ui-live-badge-mark) (quotient (font-line-height 'ui-small) 2))

  (define-part (ui-live-badge-size live? held-label)
    (values (+ 8 (ui-live-badge-mark) 6
               (text-width (if live? "Live" held-label) 'ui-small)
               (if live? 0 (text-width ui-live-badge-back 'ui-small))
               10)
            (+ (font-line-height 'ui-small) 6)))

  ;; flags: checked (live), hover, pressed, focused. A pill: when live, it
  ;; is tinted with the accent and has a dot; when held, it is plain, with a
  ;; pause mark and the way back in the accent.
  (define-part (ui-draw-live-badge x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))]
           [live? (on? 'checked)] [hot? (or (on? 'hover) (on? 'pressed))]
           [lh (font-line-height 'ui-small)] [m (ui-live-badge-mark)]
           [ty (+ y (/ (- h lh) 2))] [my (+ y (/ (- h m) 2))]
           [r (exact (floor (/ h 2)))]
           [tx (+ x 8 m 6)]
           [back (if live? 0 (text-width ui-live-badge-back 'ui-small))]
           [label (text-fit label (max 0 (- (+ x w) tx back 10)) 'ui-small)])
      (fill-box x y w h
                (cond [live? (alpha 'accent (if hot? 0.3 0.18))]
                      [hot? 'bg-3]
                      [else 'bg-2])
                r)
      (stroke-box x y w h
                  (cond [hot? 'accent]
                        [live? (alpha 'accent 0.6)]
                        [else 'window-border])
                  1 r)
      (if live?
          (fill-circle (+ x 8 (/ m 2)) (+ y (/ h 2)) (/ m 2) 'accent)
          (let ([bw (max 1 (quotient m 3))])
            (fill-box (+ x 8) my bw m 'text-dim)
            (fill-box (+ x 8 (- m bw)) my bw m 'text-dim)))
      (draw-text tx ty label (if live? 'text 'text-dim) 'ui-small)
      (unless live?
        (draw-text (+ tx (text-width label 'ui-small)) ty ui-live-badge-back
                   'accent 'ui-small))
      (when (on? 'focused) (ui-draw-focus x y w h flags r))))

  ;; Returns the size of a toggle's track, the pill its knob slides in, as
  ;; (values w h).
  (define-part (ui-toggle-track)
    (let ([th (+ (ui-glyph-size) 6)]) (values (- (* 2 th) 4) th)))

  (define-part (ui-draw-toggle x y w h flags label)
    (let*-values ([(tw th) (ui-toggle-track)]
                  [(ty) (+ y (floor (/ (- h th) 2)))]
                  [(on? r) (values (memq 'checked flags) (- (/ th 2) 2))]
                  [(kx) (if on? (+ x tw (- (/ th 2))) (+ x (/ th 2)))]
                  [(lh) (font-line-height 'ui)])
      (fill-box x ty tw th
                (cond [on? 'accent] [(memq 'hover flags) 'text-faint]
                      [else 'bg-3])
                (/ th 2))
      (fill-circle kx (+ ty (/ th 2)) r #xf2f2f5)
      (stroke-circle kx (+ ty (/ th 2)) r (alpha #x000000 0.35) 1)
      (when label
        (draw-text (+ x tw 8) (+ y (/ (- h lh) 2))
                   (text-fit label (- w tw 8) 'ui)
                   (if (memq 'hover flags) 'text 'text-dim) 'ui))
      (when (memq 'focused flags) (ui-draw-focus x ty tw th flags (/ th 2)))))

  (define-part (ui-toggle-size label)
    (let-values ([(tw th) (ui-toggle-track)])
      (values (+ tw 8 (text-width label 'ui)) (ui-control-height))))

  ;;; ---------------------------------------------------------------- radio
  ;;; One choice among several: the app draws one radio per choice, and the
  ;;; chosen one is checked.

  ;; opts: 'hint, text under the label that says what the choice means;
  ;; 'icon, a (lambda (x y s flags) ...) that draws an icon s square before
  ;; the label (the app's drawing procedure); 'disabled; 'tip.
  (define (ui-radio ui id x y w h label chosen? on-choose . opts)
    (ui-pressable! ui id x y w h on-choose '(#\space return) opts
                   '((L . "Choose")))
    (ui-draw-radio x y w h
                   (apply ui-flags ui id
                          (append (if chosen? '(checked) '())
                                  (ui-opt-flags opts '(disabled))))
                   label (plist-ref opts 'hint #f) (plist-ref opts 'icon #f)))

  ;; The mark's side, the same as a checkbox's.
  (define (ui-radio-mark) (ui-checkbox-box))

  ;; Returns where the text starts, after the mark and any icon, as an
  ;; offset from the radio's x.
  (define (ui-radio-text-x icon?)
    (+ (ui-radio-mark) 8 (if icon? (+ (ui-glyph-size) 6) 0)))

  ;; Returns (values w h) of a radio w wide: h is a control's height, or the
  ;; height of its label with its hint wrapped under it, if that is taller.
  (define-part (ui-radio-size label hint icon? w)
    (let* ([tw (max 0 (- w (ui-radio-text-x icon?)))]
           [lh (font-line-height 'ui)]
           [hh (if hint (let-values ([(hw hh) (ui-label-size '(hint wrap) hint
                                                             tw)])
                          hh)
                   0)])
      (values w (max (ui-control-height) (+ 8 lh (if hint (+ 2 hh) 0))))))

  ;; flags: checked, disabled, hover, focused. The mark and the label go on
  ;; the first line, and the hint under the label.
  (define-part (ui-draw-radio x y w h flags label hint icon)
    (let* ([b (ui-radio-mark)] [lh (font-line-height 'ui)]
           [one? (not hint)]
           [ly (if one? (+ y (/ (- h lh) 2)) (+ y 4))]   ; the label's top
           [by (+ ly (floor (/ (- lh b) 2)))]
           [cx (+ x (/ b 2))] [cy (+ by (/ b 2))]
           [off? (memq 'disabled flags)]
           [ink (lambda (c) (if off? (alpha c 0.5) c))]
           [tx (+ x (ui-radio-text-x icon))])
      (if (memq 'checked flags)
          (begin (fill-circle cx cy (/ b 2) (ink 'accent))
                 (fill-circle cx cy (/ b 5) (color-readable-on 'accent)))
          (begin (fill-circle cx cy (/ b 2) 'bg-0)
                 (stroke-circle cx cy (- (/ b 2) 0.5)
                                (ink (if (and (memq 'hover flags) (not off?))
                                         'accent
                                         'text-faint))
                                1)))
      (when icon
        (let ([g (ui-glyph-size)])
          (icon (+ x b 8) (+ ly (/ (- lh g) 2)) g flags)))
      (draw-text tx ly (text-fit label (- (+ x w) tx) 'ui)
                 (ink (if (memq 'hover flags) 'text 'text-dim)) 'ui)
      (when hint
        (fold-left (lambda (hy line)
                     (draw-text tx hy line (ink 'text-faint) 'ui-small)
                     (+ hy (font-line-height 'ui-small)))
                   (+ ly lh 2)
                   (ui-label-lines hint (- (+ x w) tx) 'ui-small)))
      (when (memq 'focused flags) (ui-draw-focus x by b b flags (/ b 2)))))

  ;;; ---------------------------------------------------------------- tabs

  ;; choices: ((label . value) ...). Returns the x after the last tab. The
  ;; first and last tabs carry the flags first and last: a style that
  ;; chains its tabs ends the chain there, and one that groups them rounds
  ;; the group's ends.
  (define (ui-tabs ui id x y h choices current on-select)
    (let loop ([cs choices] [tx x])
      (if (null? cs)
          tx
          (let ([label (caar cs)] [value (cdar cs)] [tid (list id (cdar cs))])
            (let-values ([(tw th) (ui-tabs-size (list label))])
              (ui-pressable! ui tid tx y tw h (lambda () (on-select value))
                             '(#\space return) '() (list (cons 'L label)))
              (ui-draw-tab tx y tw h
                           (apply ui-flags ui tid
                                  (append
                                   (if (equal? value current) '(selected) '())
                                   (if (eq? cs choices) '(first) '())
                                   (if (null? (cdr cs)) '(last) '())))
                           label)
              (loop (cdr cs) (+ tx tw)))))))

  (define-part (ui-draw-tab x y w h flags label)
    (let ([selected? (memq 'selected flags)] [lh (font-line-height 'ui-bold)])
      (text-draw-centered x y w h label
                          (if (or selected? (memq 'hover flags)) 'text
                              'text-dim)
                          'ui-bold)
      (when selected?
        (fill-box (+ x 10) (+ y (/ (+ h lh) 2) 3) (- w 20) 2 'accent 1))
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 6))))

  ;; Each tab is as wide as its label in 'ui-bold, plus 24.
  (define-part (ui-tabs-size labels)
    (values (fold-left (lambda (acc l) (+ acc 24 (text-width l 'ui-bold))) 0
                       labels)
            (round (+ (font-line-height 'ui) 15))))

  ;;; ------------------------------------------------------------------
  ;;; labels and surfaces: an app's text and strips, so it never names a
  ;;; font, a color or a fill

  ;; A section label's font, and whether it is in capitals (Genera heads a
  ;; pane in bold italic instead). A group's heading, over a block of rows
  ;; (a table, a grid), is at the rows' size, so that it stands over them
  ;; rather than under them.
  (at-load
   (theme-default! 'label-section-font 'ui-small))
  (at-load
   (theme-default! 'label-section-upcase #t))
  (at-load
   (theme-default! 'label-group-font 'ui-bold))

  (define (ui-label-font flags)
    (cond [(memq 'heading flags) 'heading]
          [(memq 'section flags) (theme 'label-section-font)]
          [(memq 'group flags) (theme 'label-group-font)]
          [(memq 'hint flags) 'ui-small]
          [(memq 'mono flags) 'mono-small]
          [else 'ui]))

  (define (ui-label-text flags text)
    (if (and (memq 'section flags) (theme 'label-section-upcase))
        (string-upcase text)
        text))

  ;; flags: a role (heading body dim hint section group mono error), and
  ;; wrap, center or right. Without wrap, the text is cut to w and centered
  ;; in h; with wrap, it is a paragraph from y. Returns the y below the
  ;; text.
  (define-part (ui-draw-label x y w h flags text)
    (let* ([font (ui-label-font flags)]
           [color (cond [(memq 'error flags) 'red]
                        [(memq 'dim flags) 'text-dim]
                        [(or (memq 'hint flags) (memq 'section flags)
                             (memq 'mono flags))
                         'text-faint]
                        [else 'text])]
           [text (ui-label-text flags text)]
           [lh (font-line-height font)]
           [at (lambda (s)
                 (cond [(memq 'right flags) (- (+ x w) (text-width s font))]
                       [(memq 'center flags)
                        (+ x (/ (- w (text-width s font)) 2))]
                       [else x]))])
      (if (memq 'wrap flags)
          (fold-left (lambda (y line) (draw-text (at line) y line color font)
                       (+ y lh))
                     y (ui-label-lines text w font))
          (let ([s (text-fit text w font)])
            (draw-text (at s) (+ y (max 0 (/ (- h lh) 2))) s color font)
            (+ y (max h lh))))))

  ;; Returns (values w h); w matters only with wrap.
  (define-part (ui-label-size flags text w)
    (let* ([font (ui-label-font flags)] [lh (font-line-height font)]
           [text (ui-label-text flags text)])
      (if (memq 'wrap flags)
          (values w (* lh (length (ui-label-lines text w font))))
          (values (text-width text font) lh))))

  ;; Returns a wrapped label's lines at w, broken as text boxes break them
  ;; (a word wider than w too), each without the space it ends in at a soft
  ;; break.
  (define (ui-label-lines text w font)
    (let ([n (string-length text)])
      (map (lambda (row)
             (let ([s (car row)] [e (cdr row)])
               (substring text s
                          (if (and (< s e n)
                                   (char=? (string-ref text (- e 1)) #\space)
                                   (not (char=? (string-ref text e) #\newline)))
                              (- e 1)
                              e))))
           (vector->list (edit-wrap text w (lambda (s) (text-width s font)))))))

  ;; Returns text wrapped at w in font as text boxes wrap it (a long word
  ;; breaks), as (values lines cut?): at most n lines, the last ending in
  ;; "…" when more follow. Only the rows shown are computed.
  (define (ui-wrap-lines text w font n)
    (let ([lay (edit-layout-of #f text w #f (lambda (s) (text-width s font))
                               #f)])
      (edit-layout-extend! lay n)
      (let* ([cut? (> (edit-layout-count lay) n)]
             [k (min n (edit-layout-count lay))])
        (values (map (lambda (r)
                       (let-values ([(s e) (edit-row lay r)])
                         (if (and cut? (= r (- k 1)))
                             (text-fit (string-append
                                        (substring text s (edit-row-last lay r))
                                        "…")
                                       w font)
                             (substring text s e))))
                     (iota k))
                cut?))))

  ;; flags: page, toolbar (a line below), footer (a line above: a dialog's
  ;; buttons), side (a line at the left), nav (a deeper column with a line
  ;; at the right: Settings' tabs), well; and floating, for a surface that
  ;; lies over something, which shows through it.
  (define-part (ui-draw-surface x y w h flags)
    (define (paper c)   ; over something, it shows through
      (if (memq 'floating flags) (alpha c (theme 'floating-opacity)) c))
    (cond
      [(memq 'well flags) (fill-box x y w h 'bg-0 8)]
      [(memq 'nav flags)
       (fill-box x y w h (paper 'bg-0))
       (fill-box (+ x w -1) y 1 h 'window-border)]
      [else
       (fill-box x y w h (paper 'bg-1))
       (cond [(memq 'toolbar flags)
              (fill-box x (- (+ y h) 1) w 1 'window-border)]
             [(memq 'footer flags) (fill-box x y w 1 'window-border)]
             [(memq 'side flags) (fill-box x y 1 h 'window-border)])]))

  ;; How wide a well's ring is, if its style draws one (Genera's 1-pixel
  ;; box): a view that scrolls in the well stops short of it, so that what
  ;; the view cuts off never covers the ring.
  (at-load
   (theme-default! 'surface-well-ring 0))
  (define (ui-surface-well-ring) (theme 'surface-well-ring))

  ;; Returns draw-text's y for a line of text in font whose box's top is
  ;; top. The core puts the baseline the font's whole ascent down; a style
  ;; may put it where its original does (Adwaita: where GTK does, with the
  ;; ascent unrounded).
  (define-part (ui-text-y top font) top)

  ;;; ------------------------------------------------------------------
  ;;; text field and text area: one box, with one row or wrapped rows

  ;; Returns how far down a box h high its text starts: a field's one row
  ;; is centered, where a label beside it has its own; an area's rows,
  ;; however many, start margin down.
  (define (ui-text-box-top h flags font margin)
    (if (memq 'field flags)
        (max 0 (/ (- h (font-line-height font)) 2))
        margin))

  ;; Returns the box's inner rect and font, and where an area's scroll bar
  ;; goes (over its right padding, its thumb a pixel clear of a full row's
  ;; end), as ((edit tx ty tw th font) (bar x y w h)).
  (define-part (ui-text-box-areas x y w h flags)
    (let* ([left (if (memq 'search flags) (+ (ui-glyph-size) 14) 8)]
           [bw (ui-scrollbar-width)]
           [font (if (memq 'large flags) 'heading 'ui)]
           [top (ui-text-box-top h flags font 6)])
      (list (list 'edit (+ x left) (+ y top) (max 0 (- w left 8))
                  (max 0 (- h top top)) font)
            (list 'bar (+ x w 1 (- bw)) (+ y 3) bw (max 0 (- h 6))))))

  ;; Returns how far in from the box's left edge its text starts: a bare box
  ;; moved that much to the left lines its text up with what is above and
  ;; below it. A box's sizes, areas and drawing all belong to its place,
  ;; field.
  (define (ui-text-box-inset flags)
    (with-place 'field
      (lambda () (cadr (car (ui-text-box-areas 0 0 0 0 flags))))))

  ;; Returns how much of a box's width its text does not get: what the style
  ;; keeps on either side for its marks and margins.
  (define (ui-text-box-insets flags)
    (with-place 'field
      (lambda ()
        (- 100 (list-ref (car (ui-text-box-areas 0 0 100 0 flags)) 3)))))

  ;; Returns (values w h) for a box with rows of text.
  (define-part (ui-text-box-size flags w rows)
    (with-place 'field
      (lambda ()
        (let ([large? (memq 'large flags)])
          (values w
                  (if (and (= rows 1) (not large?))
                      (ui-control-height)
                      (round (+ 12 (* rows (font-line-height
                                            (if large? 'heading 'ui)))))))))))

  ;; Returns the rows of box id's text, tw wide in font (unwrapped for a
  ;; field). The kit keeps them, so that the layout pass and the frame share
  ;; them, and a draw computes only the rows it shows. When the text came
  ;; from the focused box's edit, the edit says where it changed, so that
  ;; the rows need not compare the texts. The rows measure in the font they
  ;; were laid out in (a click comes outside the box's place).
  (define (ui-text-layout ui id text tw font area?)
    (let* ([e (ui-edit ui)] [f (get-font font)]
           [lay (edit-layout-of (ui-memo ui (list id 'rows) #f) text
                                (and area? tw) (cons f *scale*)
                                (lambda (s) (text-width s f))
                                (and e (equal? (ui-state-focus ui) id)
                                     (eq? (edit-text e) text)
                                     (edit-change e)))])
      (ui-memo! ui (list id 'rows) lay)
      lay))

  ;; Returns the size of text area id: as tall as text wrapped at w needs,
  ;; within the row counts. Only the rows up to max-rows are computed, and
  ;; the box draws those.
  (define-part (ui-text-area-size ui id flags w text min-rows max-rows)
    (with-place 'field
      (lambda ()
        (let* ([a (car (ui-text-box-areas 0 0 w 0 flags))]
               [lay (ui-text-layout ui id text (list-ref a 3) (list-ref a 5)
                                    #t)])
          (edit-layout-extend! lay (- max-rows 1))
          (ui-text-box-size flags w
                            (clamp (edit-layout-count lay) min-rows
                                   max-rows))))))

  (define (ui-text-field ui id x y w h text on-change . opts)
    (with-place 'field
      (lambda () (ui-text-box ui id x y w h text on-change #f opts))))

  (define (ui-text-area ui id x y w h text on-change . opts)
    (with-place 'field
      (lambda () (ui-text-box ui id x y w h text on-change #t opts))))

  ;; Returns the focused text's edit of text: the kept edit, or one clamped
  ;; to text when the text changed elsewhere. A new focus puts the caret at
  ;; the end, or where ui-focus! said.
  (define (ui-text-edit ui text)
    (let* ([e (ui-state-edit ui)] [n (string-length text)]
           [e (cond [(edit? e)
                     (if (eq? (edit-text e) text)
                         e
                         (make-edit text (min (edit-caret e) n)
                                    (min (edit-anchor e) n) #f #f))]
                    [(eq? e 'all) (edit-all text)]
                    [(fixnum? e) (edit-at text e)]
                    [else (edit-at text n)])])
      (ui-state-edit-set! ui e)
      e))

  ;; opts: 'placeholder, 'tip, 'max (the most characters the text may
  ;; hold), 'on-enter (a thunk for Return), 'on-key ((lambda (key mods text)
  ;; ...), true when it acted), 'suggest and 'on-pick (below), and the flags
  ;; 'large, 'bare, 'search, 'single (an area whose Return is not a
  ;; newline), 'inner (inside another widget's box: never a box of its
  ;; own), 'right (a field's text at its right, while it fits), and
  ;; 'join-left and 'join-right (the box square on that side, where a
  ;; neighbor shares its edge, as in a stepper). An area of lines taller
  ;; than its box has a scroll bar.
  ;;
  ;; Suggestions: (suggest text) returns what the text may become, best
  ;; first (ui-suggestions ranks them); while the box has the keyboard, up
  ;; to 8 of them show in a list under it. Down and Up choose one, Return or
  ;; a click picks it, and Escape closes the list until the text changes. A
  ;; pick calls (on-pick s), which by default makes s the text.
  (define (ui-text-box ui id x y w h text on-change area? opts)
    (let* ([own (append (ui-opt-flags opts
                                      '(large bare search single inner right
                                        join-left join-right))
                        (if area? '() '(field))
                        ;; an area of lines: a box of its own, not a field
                        (if (and area? (not (plist-ref opts 'single #f)))
                            '(lines)
                            '()))]
           [areas (ui-text-box-areas x y w h own)]
           [a (car areas)] [tx (list-ref a 1)] [ty (list-ref a 2)]
           [tw (list-ref a 3)] [th (list-ref a 4)] [font (list-ref a 5)]
           [lh (font-line-height font)]
           [lines? (and area? (not (memq 'single own)))]
           [most (plist-ref opts 'max #f)]
           [on-key (plist-ref opts 'on-key #f)]
           [on-enter (plist-ref opts 'on-enter #f)]
           [lay (ui-text-layout ui id text tw font area?)]
           [e (and (equal? (ui-state-focus ui) id) (ui-text-edit ui text))]
           [suggest (plist-ref opts 'suggest #f)]
           [sid (list id 'suggest)]   ; (chosen . the text it closed at)
           [shown (and suggest e (current-window)
                       (eq? (current-window) (focused-window))
                       (not (equal? (cdr (ui-memo ui sid '(#f . #f))) text))
                       (let ([l (suggest text)])
                         (list-head l (min 8 (length l)))))]
           [chosen (let ([c (car (ui-memo ui sid '(#f . #f)))])
                     (and shown c (< c (length shown)) c))]
           [page (max 1 (exact (floor (/ th lh))))]
           ;; a text at the right is a text scrolled back past its start
           [room (if (and (memq 'right own) (not area?))
                     (- tw (edit-caret-x lay (string-length text)))
                     0)]
           [dx (cond [(> room 0) (- room)]
                     [(and e (not area?))
                      (max 0 (- (edit-caret-x lay (edit-caret e)) tw))]
                     [else 0])]
           [dy (if area?
                   (let* ([off (ui-memo ui id 0)]
                          [c (and e (edit-caret e))]
                          [moved? (and c
                                       (not (eqv? c (ui-memo ui (list id 'caret)
                                                               #f))))]
                          [off (cond
                                 [moved?
                                  (let ([top (* lh (edit-row-at lay c))])
                                    (min top (max off (- (+ top lh) th))))]
                                 ;; The focus left: back to the start.
                                 [(and (not c) (ui-memo ui (list id 'caret) #f))
                                  0]
                                 [else off])])
                     ;; the rows in view, and one more
                     (edit-layout-extend! lay
                                          (+ (exact (floor (/ (+ off th) lh)))
                                                 1))
                     (let ([off (clamp off 0 (max 0 (- (* lh (edit-layout-total
                                                              lay))
                                                       th)))])
                       (ui-memo! ui id off)
                       (ui-memo! ui (list id 'caret) c)
                       off))
                   (begin (edit-layout-extend! lay 0) 0))]
           [content (* lh (edit-layout-total lay))]
           ;; The bar shows an estimate: a scan is asked for even if the
           ;; caret's row, worked out below, brings the rows to the end, so
           ;; that the frame that finds them done draws the bar again.
           [estimate? (not (edit-layout-done? lay))]
           [max-dy (if area? (max 0 (- content th)) 0)]
           [bar? (and lines? (> max-dy 0))])
      (define (current) (ui-text-edit ui text))
      (define (index-at px py)
        (let ([r (max 0 (exact (floor (/ (- (+ py dy) ty) lh))))])
          (edit-layout-extend! lay r)
          (edit-index-at lay (min r (- (edit-layout-count lay) 1))
                         (- (+ px dx) tx))))
      ;; Whatever moves the caret, changes the text or acts on a key shows
      ;; the box: it asks to be scrolled into view at the next draw.
      (define (show!) (ui-state-reveal-set! ui (cons id #f)) #t)
      (define (apply! e2)
        (ui-state-edit-set! ui e2)
        (ui-state-blink-at-set! ui (now-ms))
        (unless (eq? (edit-text e2) text)
          (ui-memo! ui sid '(#f . #f))   ; the list starts over
          (on-change (edit-text e2)))
        (show!))
      (define (pick! s)
        (ui-memo! ui sid (cons #f s))
        ((plist-ref opts 'on-pick
                    (lambda (s) (apply! (edit-at s (string-length s)))))
         s)
        (show!))
      (define (key! key mods)
        (let ([e (current)])
          (cond
            [(and shown (pair? shown) (null? mods) (memq key '(up down)))
             (let ([n (length shown)] [down? (eq? key 'down)])
               (ui-memo! ui sid
                         (cons (cond [chosen (mod (+ chosen (if down? 1 -1)) n)]
                                     [down? 0]
                                     [else (- n 1)])
                               #f))
               (show!))]
            [(and chosen (null? mods) (eq? key 'return))
             (pick! (list-ref shown chosen))]
            [(and shown (pair? shown) (null? mods) (eq? key 'escape))
             (ui-memo! ui sid (cons #f text))
             #t]
            [(and on-key (on-key key mods (edit-text e))) (show!)]
            [(and (equal? mods '(ctrl)) (memv key '(#\c #\x #\v)))
             (let ([s (edit-selection e)])
               (case key
                 [(#\c) (unless (string=? s "") (clipboard-set! s)) #t]
                 [(#\x) (unless (string=? s "")
                          (clipboard-set! s)
                          (apply! (edit-erase e 0)))
                        #t]
                 [else (apply! (edit-insert
                                e (edit-clean (clipboard-get) lines?) most))]))]
            [(eq? key 'return)
             (cond [lines? (apply! (edit-insert e "\n" most))]
                   [on-enter (on-enter) (show!)]
                   [else #f])]
            [(edit-key e key mods lay page)
             => (lambda (e2)
                  ;; Page Up and Page Down scroll the view as many rows as
                  ;; they move the caret, so the caret keeps its place in it.
                  (when (and area? (memq key '(page-up page-down)))
                    (ui-memo! ui id (max 0 (+ (ui-memo ui id 0)
                                              (* lh (if (eq? key 'page-up)
                                                        (- page)
                                                        page))))))
                  (apply! e2))]
            [else #f])))
      ;; When asked to be shown, a focused box names its caret's row, where
      ;; the typing goes, for a scroll view too short to show all of it; on
      ;; its first and last rows, the box's edges come along.
      (let ([rv (ui-state-reveal ui)])
        (when (and e rv (equal? (car rv) id))
          (let* ([r (edit-row-at lay (edit-caret e))]
                 [top (- (+ (- ty y) (* r lh)) dy)]
                 [last? (begin (edit-layout-extend! lay (+ r 1))
                               (>= (+ r 1) (edit-layout-count lay)))])
            (ui-state-reveal-set!
             ui (cons id (cons (if (= r 0) 0 top) (if last? h (+ top lh))))))))
      (ui-region! ui id x y w h 'focus 'click 'cursor 'ibeam
        'tip (plist-ref opts 'tip #f)
        'doc (plist-ref opts 'doc '((L . "Place the caret")
                                     (L2 . "Select a word")))
        'on (lambda (ev)
              (case (car ev)
                [(press)
                 (and (eq? (list-ref ev 3) 'left)
                      (let ([i (index-at (cadr ev) (caddr ev))])
                        (apply!
                         (case (list-ref ev 4)
                           [(1) (edit-at text i)]
                           [(2) (let-values ([(lo hi) (edit-word-bounds text
                                                                        i)])
                                  (edit-select (current) lo hi))]
                           [else (let-values ([(lo hi) (edit-line-bounds text
                                                                         i)])
                                   (edit-select (current) lo hi))]))))]
                [(drag)
                 (and (eqv? (cadddr ev) 1)
                      (apply! (edit-move (current)
                                         (index-at (cadr ev) (caddr ev)) #t)))]
                [(key) (key! (cadr ev) (caddr ev))]
                [(text) (apply! (edit-insert
                                 (current) (edit-clean (cadr ev) lines?) most))]
                [(wheel)
                 (and (> max-dy 0)
                      (let* ([old (ui-memo ui id 0)]
                             [new (clamp (- old (* (cadr ev) (ui-scroll-step)))
                                         0 max-dy)])
                        (and (not (= new old))
                             (begin (ui-memo! ui id new) #t))))]
                [else #f])))
      (let* ([base (apply ui-flags ui id own)]
             [flags (append base
                            (if (and (memq 'focused base) (ui-caret-on? ui))
                                '(caret)
                                '())
                            (if (string=? text "") '(placeholder) '()))])
        (let-values ([(lo hi) (if (and e (memq 'focused base))
                                  (edit-range e)
                                  (values 0 0))])
          (ui-draw-text-box x y w h flags lay lo hi (if e (edit-caret e) 0) dx
                            dy
                            (plist-ref opts 'placeholder #f))))
      (when (and shown (pair? shown))
        (ui-later! ui
          (lambda (ww wh)
            (with-place 'field
              (lambda ()
                (ui-suggestion-list ui id x y w h shown chosen pick! ww wh))))))
      ;; The bar's total is an estimate until the window's frames finish the
      ;; rows.
      (when bar?
        (when estimate?
          (ui-state-scans-set! ui (cons lay (ui-state-scans ui))))
        (apply ui-scrollbar ui (list id 'bar)
               (append (cdr (cadr areas))
                       (list dy content th
                             (lambda (off) (ui-memo! ui id off))))))))

  ;; lay is the text's rows (an edit-layout), with those in view computed;
  ;; [lo, hi) is the selection; dx and dy are how far the text is scrolled.
  (define-part (ui-draw-text-box x y w h flags lay lo hi caret dx dy
                                 placeholder)
    (let* ([a (car (ui-text-box-areas x y w h flags))]
           [tx (list-ref a 1)] [ty (list-ref a 2)] [tw (list-ref a 3)]
           [th (list-ref a 4)] [font (list-ref a 5)]
           [lh (font-line-height font)] [text (edit-layout-text lay)]
           [measure (lambda (s) (text-width s font))]
           [focused? (memq 'focused flags)] [hover? (memq 'hover flags)])
      (unless (or (memq 'inner flags)
                  (and (memq 'bare flags) (not hover?) (not focused?)))
        (ui-draw-field x y w h flags))
      (when (memq 'search flags)
        (let ([s (+ (ui-glyph-size) 2)])
          (ui-draw-glyph (+ x 7) (+ y (/ (- h s) 2)) s s '(quiet) 'search)))
      ;; The clip is the edit rect and 2 px on either side for the caret, so
      ;; a scrolled row never shows in the padding. Scrolled sideways, the
      ;; caret is at the right, so the left margin is dropped.
      (with-clip ((if (> dx 0) tx (- tx 2)) ty (+ tw (if (> dx 0) 2 4)) th)
        (if (memq 'placeholder flags)
            (when placeholder
              (draw-text tx (ui-text-y ty font) (text-fit placeholder tw font)
                         (theme 'text-placeholder-color) font))
            ;; only the rows in view
            (let loop ([r (max 0 (- (exact (floor (/ dy lh))) 1))])
              (let ([ry (- (+ ty (* r lh)) dy)] [rx (- tx dx)])
                (when (and (< r (edit-layout-count lay)) (< (+ ry 1) (+ ty th)))
                  ;; A row at most a pixel into view would show only the
                  ;; tips of its descenders, so it is skipped.
                  (when (> (+ ry lh) (+ ty 1))
                    (let-values ([(s e) (edit-row lay r)])
                      (when (and (< lo hi) (< lo (max e (+ s 1))) (> hi s))
                        (let* ([x0 (measure (substring text s (max s lo)))]
                               [x1 (if (> hi e)
                                       (+ (measure (substring text s e)) 4)
                                       (measure (substring text s hi)))])
                          (if (eq? (theme 'text-selection) 'underline)
                              (fill-box (+ rx x0) (+ ry lh -1) (- x1 x0) 1
                                        'text)
                              (fill-box (+ rx x0) ry (- x1 x0) lh
                                        'selection))))
                      ;; Unfocused and scrolled to its start, the box's last
                      ;; row in view says that more follows.
                      (draw-text rx (ui-text-y ry font)
                                 (if (and (not focused?) (= dy 0)
                                          (or (< (+ r 1)
                                                 (edit-layout-count lay))
                                              (not (edit-layout-done? lay)))
                                          (> (+ ry lh lh) (+ ty th 1)))
                                     (text-fit
                                      (string-append
                                       (substring text s (edit-row-last lay r))
                                       "…")
                                      tw font)
                                     (substring text s e))
                                 'text font)))
                  (loop (+ r 1))))))
        (when (memq 'caret flags)
          (let ([cx (+ (- tx dx) (edit-caret-x lay caret))]
                [cy (- (+ ty (* lh (edit-row-at lay caret))) dy)])
            (if (eq? (theme 'text-caret) 'block)
                (px-invert cx cy (ui-caret-block-width text caret font) lh)
                (let ([cw (theme 'text-caret-width)])
                  (fill-box (- cx (/ cw 2)) cy cw lh
                            (theme 'text-caret-color)))))))))

  ;; How the text's caret and selection show: a bar and a fill (bar, fill),
  ;; or, as the Lisp machines showed them, a block in reverse video over the
  ;; character and an underline (block, underline).
  (at-load
   (theme-default! 'text-caret 'bar))
  (at-load
   (theme-default! 'text-selection 'fill))
  ;; A bar caret's width and color, and a placeholder's color.
  (at-load
   (theme-default! 'text-caret-width 2))
  (at-load
   (theme-default! 'text-caret-color 'accent))
  (at-load
   (theme-default! 'text-placeholder-color 'text-faint))

  ;; A block caret is as wide as the character under it; at the end of the
  ;; text or of a line, it is the font's own character width.
  (define (ui-caret-block-width text i font)
    (if (and (< i (string-length text))
             (not (char=? (string-ref text i) #\newline)))
        (text-width (string (string-ref text i)) font)
        (font-char-width font)))

  ;; Draws the suggestions under box id at x y w h (above it when there is
  ;; no room below), in a window ww × wh: each is a row that a press picks.
  (define (ui-suggestion-list ui id x y w h shown chosen pick! ww wh)
    (let*-values ([(rh) (ui-suggestion-row-height)] [(pad) 4]
                  [(lh) (+ pad pad (* rh (length shown)))]
                  [(lx ly) (ui-popup-place x (+ y h 2) (- y 2) w lh ww wh)])
      (ui-draw-panel lx ly w lh '(menu))
      (for-each
       (lambda (s i)
         (let ([rid (list id 'suggestion i)] [ry (+ ly pad (* i rh))])
           (ui-pressable! ui rid lx ry w rh (lambda () (pick! s)) '()
                          '(focus keep) '((L . "Pick")))
           (ui-draw-suggestion (+ lx pad) ry (- w pad pad) rh
                               (apply ui-flags ui rid
                                      (if (eqv? i chosen) '(selected) '()))
                               s)))
       shown (iota (length shown)))))

  (define (ui-suggestion-row-height) (round (+ (font-line-height 'ui) 8)))

  ;; A suggestion's row. flags: selected (chosen by the keyboard), hover.
  (define-part (ui-draw-suggestion x y w h flags label)
    (let ([on? (or (memq 'selected flags) (memq 'hover flags))])
      (when on? (ui-draw-highlight x y w h (if (memq 'selected flags)
                                               '()
                                               '(hover))))
      (draw-text (+ x 8) (+ y (/ (- h (font-line-height 'ui)) 2))
                 (text-fit label (- w 16) 'ui) (if on? 'text 'text-dim) 'ui)
      (when (memq 'selected flags) (ui-draw-highlight-over x y w h '()))))

  ;; Returns the choices ((name . detail) ...) that typed matches, best
  ;; first, as a vector of (name detail positions); first? says whether a
  ;; name goes first among equals. The completion kit ((schevana kits
  ;; complete)) sets this hook to its ranking by segments; until it does,
  ;; the names that begin with typed match.
  (define-hook (ui-rank typed choices first?)
    (list->vector
     (map (lambda (c) (list (car c) (cdr c) '()))
          (filter (lambda (c) (string-prefix? typed (car c))) choices))))

  ;; Returns the choices (strings) that typed matches, best first, at most
  ;; n, in the ranking's order (ui-rank), by segments ("dtc" finds
  ;; draw-text-centered). Returns none when nothing is typed, or when typed
  ;; itself is the only match.
  (define (ui-suggestions typed choices n)
    (if (string=? typed "")
        '()
        (let* ([ranked (ui-rank typed (map (lambda (c) (cons c #f)) choices)
                                (lambda (c) #f))]
               [names (map car (vector->list ranked))])
          (if (equal? names (list typed))
              '()
              (list-head names (min n (length names)))))))

  ;;; ---------------------------------------------------------------- scroll

  ;; A scroll view. body is (lambda (top) ... bottom): it draws its content
  ;; from top and returns where the content ends. The content is clipped to
  ;; the view, and the wheel and a scroll bar over the view's edge move it.
  ;; The style places the bar (scrollbar-side right, left, or outside: over
  ;; the whole of the frame's region of kind scrollbar, for a view against
  ;; the window's left edge, or on the right where there is no such region)
  ;; and shows it always or while the pointer is over the view
  ;; (scrollbar-show hover; outside, while the pointer is over the margin).
  ;; The bar lies over the content, which never reflows for it; content
  ;; that keeps clear of it asks how far (ui-scrollbar-inset).
  (define (ui-scroll ui id x y w h body)
    (let ([off (car (ui-memo ui id '(0 . 0)))]
          [clip (ui-state-clip ui)])
      (ui-region! ui id x y w h 'on
        (lambda (ev)
          (and (eq? (car ev) 'wheel)
               (let* ([m (ui-memo ui id '(0 . 0))]
                      [new (clamp (- (car m) (* (cadr ev) (ui-scroll-step)))
                                  0 (cdr m))])
                 (and (not (= new (car m)))
                      (begin (ui-memo! ui id (cons new (cdr m))) #t))))))
      (let ([before (ui-state-regions ui)])
        (ui-state-clip-set! ui (call-with-values
                                 (lambda () (ui-cut x y w h clip))
                                 list))
        (let* ([bottom (with-clip (x y w h) (body (- y off)))]
               [content (- bottom (- y off))]
               [most (max 0 (- content h))]
               [now (car (ui-memo ui id '(0 . 0)))]
               [new (clamp now 0 most)])
          (ui-state-clip-set! ui clip)
          (ui-memo! ui id (cons new most))
          (unless (= new off) (invalidate! (current-window)))
          ;; A region drawn in the view that asks to be revealed is shown a
          ;; gap clear of the edges, where a focus ring around it shows
          ;; whole.
          (let ([rv (ui-state-reveal ui)])
            (when rv
              (let loop ([rs (ui-state-regions ui)])
                (unless (eq? rs before)
                  (if (equal? (ui-region-id (car rs)) (car rv))
                      ;; All of it when it fits, else the span it asks for
                      ;; (a text box's caret row).
                      (let* ([f (ui-region-frame (car rs))]
                             [top (- (cadr f) (- y off))]
                             [span (if (and (cdr rv)
                                            (> (+ (cadddr f) (* 2 (ui-gap))) h))
                                       (cdr rv)
                                       (cons 0 (cadddr f)))])
                        (ui-state-reveal-set! ui #f)
                        (ui-reveal! ui id (- (+ top (car span)) (ui-gap))
                                    (+ top (cdr span) (ui-gap)) h))
                      (loop (cdr rs)))))))
          (let* ([win (current-window)] [bid (list id 'bar)]
                 [side (theme 'scrollbar-side)]
                 [r (and win (eq? side 'outside) (zero? x)
                         (assq 'scrollbar (frame-regions win)))]
                 [out? (and r #t)]   ; the whole region its frame leaves
                 [bw (if out? (list-ref r 3) (ui-scrollbar-width))]
                 [hover (and win (window-hover win))])
            (when (and (> content h)
                       (or (eq? (theme 'scrollbar-show) 'always)
                           (ui-active? ui bid)
                           (if out?
                               (eq? hover 'scrollbar)
                               (and (eq? hover 'content)
                                    (ui-hover? ui x y w h)))))
              ;; Outside, the bar takes the whole region (in the content's
              ;; coordinates).
              (let-values ([(bx by bh)
                            (if out?
                                (let-values ([(l t . rb) (frame-insets win)])
                                  (values (- (cadr r) l) (- (caddr r) t)
                                          (list-ref r 4)))
                                (values (if (eq? side 'left) x (- (+ x w) bw))
                                        y h))])
                (ui-scrollbar ui bid bx by bw bh new content h
                              (lambda (off) (ui-memo! ui id (cons off most))))
                (when out?   ; for the frame's over pass: ui-frame-scrollbar
                  (hashtable-set! (window-props win) 'scrollbar
                                  (list bx by bw bh (ui-flags ui bid)
                                        (/ new content) (/ h content)))))))))))

  ;; A scroll bar at x y w h for a view, view high, that shows content from
  ;; off on: a press on the thumb or beside it, and a drag, set the offset
  ;; by calling (set-off! off).
  (define (ui-scrollbar ui id x y w h off content view set-off!)
    (let* ([most (max 0 (- content view))]
           [start (/ off content)] [size (/ view content)]
           [thumb (cdr (assq 'thumb (ui-scrollbar-areas x y w h start size)))])
      (define (thumb-to! ty)
        (set-off! (clamp (* most (/ (- ty y) (max 1 (- h (cadddr thumb)))))
                         0 most))
        #t)
      (ui-region! ui id x y w h 'focus 'keep 'doc '((L . "Scroll")) 'on
        (lambda (ev)
          (case (car ev)
            [(press)
             (and (eq? (list-ref ev 3) 'left)
                  (let* ([py (caddr ev)] [ty (cadr thumb)]
                         [grab (if (<= ty py (+ ty (cadddr thumb)))
                                   (- py ty)
                                   (/ (cadddr thumb) 2))])
                    (ui-memo! ui (list id 'grab) grab)
                    (thumb-to! (- py grab))))]
            [(drag) (thumb-to! (- (caddr ev) (ui-memo ui (list id 'grab) 0)))]
            ;; The wheel scrolls as over the view, since an outside bar lies
            ;; over no view.
            [(wheel) (let ([new (clamp (- off (* (cadr ev) (ui-scroll-step)))
                                       0 most)])
                       (and (not (= new off)) (begin (set-off! new) #t)))]
            [else #f])))
      (ui-draw-scrollbar x y w h (ui-flags ui id) start size)))

  ;; Scrolls view id so that [top, bottom) of its content is in view (its
  ;; top first), and invalidates the window when the offset moved. The
  ;; offset is not clamped to the last draw's content, which may not hold
  ;; [top, bottom) yet (a card just added); the scroll view clamps it as it
  ;; draws.
  (define (ui-reveal! ui id top bottom view-h)
    (let* ([m (ui-memo ui id '(0 . 0))]
           [new (max 0 (min top (max (car m) (- bottom view-h))))])
      (unless (= new (car m))
        (ui-memo! ui id (cons new (cdr m)))
        (invalidate! (current-window)))))

  (at-load
   (theme-default! 'scrollbar-width 10))
  (at-load
   (theme-default! 'scrollbar-side 'right))
  (at-load
   (theme-default! 'scrollbar-show 'always))
  ;; The room content keeps clear for a bar always shown at its left or
  ;; right: a margin beyond the bar's width, so that the bar never covers
  ;; what it scrolls; #f for none (the bar lies over the content). A bar
  ;; shown only under the pointer (scrollbar-show hover) lies over the
  ;; content anyway.
  (at-load
   (theme-default! 'scrollbar-margin 4))
  (define (ui-scrollbar-width) (theme 'scrollbar-width))

  ;; Returns how much a scroll view's content keeps clear for its bar on
  ;; side (left or right): the kit's tables and trees keep it, and an app's
  ;; own content may (Tasks' cards).
  (define (ui-scrollbar-inset side)
    (let ([m (theme 'scrollbar-margin)])
      (if (and m
               (eq? side (theme 'scrollbar-side))
               (eq? (theme 'scrollbar-show) 'always))
          (+ (ui-scrollbar-width) m)
          0)))

  ;; Draws the window's outside scroll bar, which its main scroll view
  ;; leaves in the window's 'scrollbar while the bar shows. A style that
  ;; leaves a margin for it (scrollbar-side outside, with a region of kind
  ;; scrollbar there) draws it this way in its frame's over pass, after the
  ;; content.
  (define (ui-frame-scrollbar win)
    (let ([b (window-ref win 'scrollbar)])
      (when b
        (let-values ([(cx cy cw ch) (content-rect win)])
          (apply (lambda (x y w h flags start size)
                   (ui-draw-scrollbar (+ cx x) (+ cy y) w h flags start size))
                 b)))))

  ;; How far one wheel step scrolls: three lines.
  (define (ui-scroll-step) (* 3 (font-line-height 'ui)))

  ;; start and size are the view's top and height as fractions of the
  ;; content.
  (define-part (ui-scrollbar-areas x y w h start size)
    (let ([th (min h (max (* 2 (font-line-height 'ui)) (* size h)))])
      (list (list 'thumb x
                  (+ y (if (< size 1) (* (- h th) (/ start (- 1 size))) 0))
                  w th))))

  (define-part (ui-draw-scrollbar x y w h flags start size)
    (let ([t (cdr (assq 'thumb (ui-scrollbar-areas x y w h start size)))])
      (fill-box (+ x 2) (+ (cadr t) 2) (- w 5) (- (cadddr t) 4)
                (alpha 'text (if (or (memq 'hover flags) (memq 'pressed flags))
                                 0.4
                                 0.2))
                2.5)))

  ;;; ------------------------------------------------------------------
  ;;; what a window's app says about the window, which each style shows in
  ;;; its own way

  ;; Returns a window's title icon: its 'title-icon, a (lambda (x y s flags)
  ;; ...) that draws it s square (with the flag dim for an unfocused
  ;; window), or #f. A style draws it by the title, elsewhere, or not at
  ;; all.
  (define (ui-title-icon win) (window-ref win 'title-icon #f))

  ;; An environment's icon by its kind ((schevana services env)): the
  ;; world's globe, a namespace's folder, a sandbox's box, and a thread's or
  ;; the worklets' gear, each in its kind's color, and faded when dim or
  ;; disabled.
  (define-part (ui-draw-env-icon x y s flags kind)
    (let-values ([(glyph ink)
                  (case kind
                    [(root) (values 'globe 'accent)]
                    [(worklets) (values 'gear 'yellow)]
                    [(thread) (values 'gear 'orange)]
                    [(sandbox) (values 'box 'teal)]
                    [(world) (values 'folder 'accent)]
                    [(private) (values 'folder 'accent-2)]
                    [(pure) (values 'folder 'green)]
                    [else (values 'folder 'text-dim)])])
      (ui-draw-glyph x y s s
                     (list (cons 'ink (if (or (memq 'dim flags)
                                              (memq 'disabled flags))
                                          (alpha ink 0.55)
                                          ink)))
                     glyph)))

  ;; An app says that its window is at work by the window's 'busy (the words
  ;; for it, or #f), and the window shows this as its style chooses. By
  ;; default the app draws a busy mark where the work shows (a REPL's
  ;; prompt), with its words in a tooltip over it; a style may give the
  ;; mark no size and show it in its frame or a bar instead, or animate it
  ;; its own way. The mark is drawn again every busy-frame-ms while it
  ;; shows.
  (at-load
   (theme-default! 'busy-frame-ms 100))
  (define (ui-busy-frame-ms) (theme 'busy-frame-ms))

  ;; Returns (values w h), the room the mark takes, or (values 0 0) for
  ;; none, when the style shows it elsewhere.
  (define-part (ui-busy-size)
    (let ([s (ui-glyph-size)]) (values s s)))

  ;; Draws the mark at ms (now): a spinner of eight spokes in a circle, with
  ;; the brightest moving on by one spoke every busy-frame-ms. flags: hover.
  (define-part (ui-draw-busy x y w h flags ms)
    (let* ([r (/ (min w h) 2)] [cx (+ x (/ w 2))] [cy (+ y (/ h 2))]
           [lead (mod (quotient ms (max 1 (ui-busy-frame-ms))) 8)]
           [ink (if (memq 'hover flags) 'text 'text-dim)]
           [lw (max 1.5 (* r 0.22))])
      (do ([i 0 (+ i 1)]) ((= i 8))
        (let ([a (* pi (/ i 4))]
              [fade (/ (mod (- lead i) 8) 8)])
          (draw-line (+ cx (* 0.45 r (cos a))) (+ cy (* 0.45 r (sin a)))
                     (+ cx (* 0.95 r (cos a))) (+ cy (* 0.95 r (sin a)))
                     (alpha ink (- 1 (* 0.85 fade))) lw)))))

  ;;; ---------------------------------------------------------------- split
  ;;; Two panes side by side, with the line between them dragged to share
  ;;; the room. An app asks for a split where the person should share the
  ;;; room; a pane of a fixed width (Tasks' details) needs none.

  ;; Returns the left pane's width in x..x+w: at, the app's choice, until
  ;; the line is dragged, and then where the line was left, kept so that the
  ;; left pane is at least lo wide and the right one at least hi. A double
  ;; click on the line goes back to at. The line's handle, from y and h
  ;; high, goes over the panes: it is laid out at ui-end!, after them.
  (define (ui-split ui id x y w h at lo hi)
    (let* ([most (max lo (- w hi))]
           [left (clamp (ui-memo ui (list id 'at) at) lo most)]
           [line (+ x left)])
      (ui-later! ui
        (lambda (ww wh)
          (ui-region! ui id (- line 3) y 6 h 'focus 'keep 'cursor 'resize-ew
            'doc '((L . "Resize the panes") (L2 . "Back to their widths"))
            'on
            (lambda (ev)
              (case (car ev)
                [(press)
                 (and (eq? (list-ref ev 3) 'left)
                      (begin
                        (if (>= (list-ref ev 4) 2)
                            (hashtable-delete! (ui-state-memo ui) (list id 'at))
                            (ui-memo! ui (list id 'grab) (- (cadr ev) line)))
                        #t))]
                [(drag)
                 (let ([new (clamp (exact (round (- (cadr ev) x
                                                    (ui-memo ui (list id 'grab)
                                                             0))))
                                   lo most)])
                   (and (< (cadddr ev) 2) (not (= new left))
                        (begin (ui-memo! ui (list id 'at) new) #t)))]
                [else #f])))
          (ui-draw-split line y h (ui-flags ui id))))
      left))

  ;; The line between two panes at x, which a drag moves: it shows under the
  ;; pointer and while dragged (flags hover, pressed); at rest, the panes'
  ;; own edges show it.
  (define-part (ui-draw-split x y h flags)
    (when (or (memq 'hover flags) (memq 'pressed flags))
      (fill-box (- x 1) y 2 h 'accent)))

  ;;; --------------------------------------------------------------- side panel
  ;;; What an app shows beside its work, for those who want it: controls,
  ;;; numbers, details. Its button hides it and shows it again; while
  ;;; hidden, it takes none of the room. The button is a widget of its own,
  ;;; placed where the app has room for it (a toolbar, a status line), never
  ;;; over the work, and best where it stays put as the panel comes and goes,
  ;;; so that a second press undoes the first.
  ;;;
  ;;;   (ui-side-panel ui 'controls 0 0 w h 'right 240 200
  ;;;     (lambda (x y w h) ...the rest...)
  ;;;     (lambda (x y w h) ...the panel, its surface already there...))
  ;;;   (ui-side-panel-button ui 'controls x y 24 20 'right)
  ;;;   (ui-side-panel-toggle! ui 'controls)    for a key
  ;;;
  ;;; An app whose work should not change size as the panel comes and goes
  ;;; gives 'floating #t: the rest keeps all the room, and the panel lies
  ;;; over it.

  (at-load
   (theme-default! 'floating-opacity 0.8))   ; of a surface over what's under it

  (define (ui-side-panel-open? ui id)
    (not (ui-memo ui (list id 'hidden) #f)))

  ;; Does what the button does, for a key; the caller invalidates.
  (define (ui-side-panel-toggle! ui id)
    (ui-memo! ui (list id 'hidden) (ui-side-panel-open? ui id)))

  ;; Lays out x y w h: calls rest, then panel (width wide, at side, left or
  ;; right), each with its rectangle. Where the rest would be narrower than
  ;; least, there is no panel and rest has all the room. opts: 'floating,
  ;; for a panel over the rest, which keeps all the room; a press on the
  ;; panel does not reach the rest.
  (define (ui-side-panel ui id x y w h side width least rest panel . opts)
    (let* ([fits? (>= w (+ width least))]
           [floating? (plist-ref opts 'floating #f)]
           [room (if (and fits? (ui-side-panel-open? ui id)) width 0)]
           [beside (if floating? 0 room)]
           [right? (eq? side 'right)])
      (ui-memo! ui (list id 'fits) fits?)
      (rest (if right? x (+ x beside)) y (- w beside) h)
      (when (> room 0)
        (let ([px (if right? (- (+ x w) room) x)])
          (when floating? (ui-region! ui (list id 'floating) px y room h))
          (ui-draw-surface px y room h
                           (append (if right? '(side) '(nav))
                                   (if floating? '(floating) '())))
          (panel px y room h)))))

  ;; The button for panel id at side, in the rectangle given. Its glyph is a
  ;; window with a pane on that side, filled in while the panel shows. The
  ;; button is disabled where the panel has no room.
  (define (ui-side-panel-button ui id x y w h side)
    (let ([open? (ui-side-panel-open? ui id)]
          [fits? (ui-memo ui (list id 'fits) #t)])
      (ui-button ui (list id 'button) x y w h #f
                 (lambda () (ui-side-panel-toggle! ui id))
                 'glyph (if (eq? side 'right)
                            (if open? 'panel-right-shown 'panel-right)
                            (if open? 'panel-left-shown 'panel-left))
                 'quiet #t
                 'disabled (not fits?)
                 'tip (cond [(not fits?) "No room for the panel here"]
                            [open? "Hide this panel"]
                            [else "Show the panel"]))))

  ;;; ---------------------------------------------------------------- table

  ;; Returns the width a table or tree w wide gives its columns: w less the
  ;; room its scroll bar keeps (ui-scrollbar-inset), so that columns fitted
  ;; to it stay clear of the bar.
  (define (ui-table-room w)
    (- w (ui-scrollbar-inset 'left) (ui-scrollbar-inset 'right)))

  ;; Returns columns that fit in w, in the form a table or tree takes them.
  ;; One column has width #f and takes what the others leave; the columns
  ;; that drops names are left out, in that order, while that column would
  ;; be narrower than least.
  (define (ui-table-fit w columns drops least)
    (let loop ([cols columns] [drops drops])
      (let ([fixed (apply + (filter-map caddr cols))])
        (if (or (null? drops) (<= (+ fixed least) w))
            (map (lambda (c)
                   (if (caddr c)
                       c
                       (cons* (car c) (cadr c) (- w fixed) (cdddr c))))
                 cols)
            (loop (remp (lambda (c) (eq? (car c) (car drops))) cols)
                  (cdr drops))))))

  ;; columns: ((key title width flag ...) ...). Each width is a default the
  ;; user may change by dragging (ui-table-columns); the flags are the
  ;; heading's and the cells' (right: aligned at the right, as numbers are),
  ;; and a string among them is the heading's tooltip, saying what the
  ;; column means. rows are the app's values, and selected is the one eq?
  ;; to it; a left press calls on-select. cell draws a cell: (lambda (row key
  ;; x y w h flags) ...), with flags its row's and its column's. opts: 'sort
  ;; ((key . up|down) or #f); 'on-sort (key), called on a press on a
  ;; heading; 'on-open (row), on a double click; 'on-menu (row x y), on a
  ;; right press; 'tip (row), a row's tooltip or #f; 'reveal, which when
  ;; true scrolls the selected row into view; 'checked (row), for a checkbox
  ;; before each row's first cell, checked when it returns true, and checked
  ;; and disabled when it returns fixed, with 'on-check (row) called on a
  ;; press on it; and 'resize, how a drag resizes the columns, pair or
  ;; shift, by default the style's (table-resize).
  (define (ui-table ui id x y w h columns rows selected on-select cell . opts)
    (with-place 'list
      (lambda ()
        (let* (;; the scroll view's rect, its bar in a margin the content keeps
               [sx x] [sw w]
               [x (+ sx (ui-scrollbar-inset 'left))]
               [w (ui-table-room sw)]
               [columns (ui-table-filled (ui-table-columns ui id columns) w)]
               [hh (ui-table-header-height)] [rh (ui-table-row-height)]
               [sort (plist-ref opts 'sort #f)]
               [tip (plist-ref opts 'tip (lambda (r) #f))]
               [on-sort (plist-ref opts 'on-sort (lambda (k) #f))]
               [on-open (plist-ref opts 'on-open (lambda (r) #f))]
               [on-menu (plist-ref opts 'on-menu (lambda (r x y) #f))]
               [checked (plist-ref opts 'checked #f)]
               [on-check (plist-ref opts 'on-check (lambda (r) #f))]
               ;; the checkboxes' lane, before the first cell
               [box (ui-checkbox-box)]
               [lane (if checked (+ (ui-table-cell-inset) box) 0)]
               [body (list id 'body)] [view-h (max 0 (- h hh))]
               [i (and (plist-ref opts 'reveal #f)
                       (list-index (lambda (r) (eq? r selected)) rows))]
               [rows (list->vector rows)] [n (vector-length rows)])
          (ui-table-headings! ui id sx sw x y hh columns sort on-sort
                              (+ x lane) (plist-ref opts 'resize #f))
          (when i (ui-reveal! ui body (* i rh) (* (+ i 1) rh) view-h))
          (ui-memo! ui (list id 'page) (max 1 (exact (floor (/ view-h rh)))))
          (ui-scroll ui body sx (+ y hh) sw view-h
            (lambda (top)
              (let ([vy (+ y hh)])
                (do ([i (max 0 (exact (floor (/ (- vy top) rh)))) (+ i 1)])
                    ((or (>= i n) (>= (+ top (* i rh)) (+ vy view-h))))
                  (let* ([row (vector-ref rows i)] [ry (+ top (* i rh))]
                         [rid (list id 'row i)])
                    (ui-region! ui rid x ry w rh 'tip (tip row)
                      'doc (if (plist-ref opts 'on-menu #f)
                               '((L . "Select") (R . "Menu"))
                               '((L . "Select")))
                      'on
                      (lambda (ev)
                        (and (eq? (car ev) 'press)
                             (case (list-ref ev 3)
                               [(left) (on-select row)
                                       (when (>= (list-ref ev 4) 2)
                                         (on-open row))
                                       #t]
                               [(right) (on-menu row (cadr ev) (caddr ev)) #t]
                               [else #f]))))
                    (let ([flags (apply ui-flags ui rid
                                        (if (eq? row selected) '(selected)
                                            '()))])
                      (ui-draw-table-row x ry w rh flags)
                      (when checked
                        (let ([state (checked row)] [cid (list id 'check i)]
                              [bx (+ x (ui-table-cell-inset))])
                          (unless (eq? state 'fixed)
                            (ui-pressable! ui cid (- bx 4) ry (+ box 8) rh
                                           (lambda () (on-check row)) '()
                                           '(focus keep) '((L . "Check"))))
                          (ui-draw-checkbox bx ry box rh
                                            (apply ui-flags ui cid
                                                   (append
                                                    (if state '(checked) '())
                                                    (if (eq? state 'fixed)
                                                        '(disabled)
                                                        '())))
                                            #f)))
                      (let cells ([cs columns] [cx x] [first? #t])
                        (unless (null? cs)
                          (let ([in (if first? lane 0)])
                            (cell row (caar cs) (+ cx in) ry
                                  (- (caddr (car cs)) in) rh
                                  (append flags (ui-column-flags (car cs)))))
                          (cells (cdr cs) (+ cx (caddr (car cs))) #f)))
                      (when (eq? row selected)
                        (ui-draw-highlight-over x ry w rh '()))))))
              (+ top (* n rh))))))))

  ;; Returns the new row index for a key, or #f for any other key: Up and
  ;; Down move by 1, Page Up and Page Down by page, Home goes to 0 and End to
  ;; n−1. From i #f, Down, Page Down and Home give 0, and the others n−1.
  ;; Returns #f when n is 0.
  (define (ui-table-step i n page key)
    (and (> n 0)
         (case key
           [(up) (if i (max 0 (- i 1)) (- n 1))]
           [(down) (if i (min (- n 1) (+ i 1)) 0)]
           [(page-up) (if i (max 0 (- i page)) (- n 1))]
           [(page-down) (if i (min (- n 1) (+ i page)) 0)]
           [(home) 0]
           [(end) (- n 1)]
           [else #f])))

  ;; Returns the rows per page of table id at its last draw.
  (define (ui-table-page ui id) (ui-memo ui (list id 'page) 1))

  ;; Returns the columns of table or tree id as it shows them: the app's
  ;; columns, with the width the user dragged in place of a column's
  ;; default. The kit keeps those widths while the window is open.
  (define (ui-table-columns ui id columns)
    (map (lambda (c)
           (let ([w (ui-memo ui (list id 'width (car c)) #f)])
             (if w (cons* (car c) (cadr c) w (cdddr c)) c)))
         columns))

  ;; Returns columns as drawn in w: when the widths the user dragged leave
  ;; room at the right, the last column takes it, so that the headings reach
  ;; the table's edge as its rows do.
  (define (ui-table-filled columns w)
    (let ([left (- w (apply + (map caddr columns)))])
      (if (or (null? columns) (<= left 0))
          columns
          (let ([c (car (last-pair columns))])
            (append (list-head columns (- (length columns) 1))
                    (list (cons* (car c) (cadr c) (+ (caddr c) left)
                                 (cdddr c))))))))

  ;; The narrowest the user can drag a column: two line heights.
  (define (ui-table-column-min) (exact (round (* 2 (font-line-height 'ui)))))

  ;; The handles of table or tree id: a few pixels on each line between two
  ;; of its headings, the first heading at x, h high. Dragging a handle sets
  ;; the width of the column to its left, in whole pixels, at least
  ;; ui-table-column-min. With resize pair, the width comes from the column
  ;; to its right, which keeps at least that width too; with shift, the
  ;; columns to its right move along. A double click sets their defaults
  ;; back.
  ;; How a style's tables resize (table-resize): pair, between two columns,
  ;; keeping the table's width; or shift, the Finder's and Explorer's way.
  (at-load
   (theme-default! 'table-resize 'pair))

  ;; When a table's column dividers show (table-dividers): always, faintly;
  ;; hover, while the pointer is over the headings; or handle, only the one
  ;; under the pointer. A divider under the pointer or being dragged always
  ;; shows, strongly.
  (at-load
   (theme-default! 'table-dividers 'hover))

  (define (ui-table-divider-shown? row-hover? hot?)
    (or hot?
        (case (theme 'table-dividers)
          [(always) #t]
          [(hover) row-hover?]
          [else #f])))

  (define (ui-table-handles! ui id x y h columns sx sw resize)
    (define row-hover?
      (let ([win (current-window)])
        (and win
             (memq (window-hover win) '(content scrollbar))
             (ui-hover? ui sx y sw h))))
    (let loop ([cs columns] [cx x])
      (unless (or (null? cs) (null? (cdr cs)))
        (let* ([key (caar cs)] [cw (caddr (car cs))] [line (+ cx cw)]
               [width (list id 'width key)] [grab (list id 'width-grab)]
               [pair? (eq? resize 'pair)]
               [next (list id 'width (caadr cs))]
               [both (+ cw (caddr (cadr cs)))])
          (ui-region! ui (list id 'handle key) (- line 3) y 6 h
            'focus 'keep 'cursor 'resize-ew
            'doc '((L . "Resize column") (L2 . "Default width"))
            'on
            (lambda (ev)
              (case (car ev)
                [(press)
                 (and (eq? (list-ref ev 3) 'left)
                      (begin
                        (if (>= (list-ref ev 4) 2)
                            (begin
                              (hashtable-delete! (ui-state-memo ui) width)
                              (when pair?
                                (hashtable-delete! (ui-state-memo ui) next)))
                            (ui-memo! ui grab (- (cadr ev) line)))
                        #t))]
                [(drag)
                 (let* ([least (ui-table-column-min)]
                        [new (max least
                                  (exact (round (- (cadr ev) (ui-memo ui grab 0)
                                                   cx))))]
                        [new (if pair? (min new (- both least)) new)])
                   (and (< (cadddr ev) 2) (not (= new cw))
                        (begin
                          (ui-memo! ui width new)
                          (when pair? (ui-memo! ui next (- both new)))
                          #t)))]
                [else #f])))
          (let* ([flags (ui-flags ui (list id 'handle key))]
                 [hot? (or (memq 'hover flags) (memq 'pressed flags))])
            (when (ui-table-divider-shown? row-hover? hot?)
              (ui-draw-table-divider line y h flags)))
          (loop (cdr cs) line)))))

  ;; A column's flags, apart from its tooltip; and its tooltip (the string
  ;; among them), or #f.
  (define (ui-column-flags c) (filter symbol? (cdddr c)))
  (define (ui-column-tip c) (find string? (cdddr c)))

  ;; Draws the headings of table or tree id over columns from x, h high, cut
  ;; to its view sx sw, and their handles; a column's flags and its tooltip
  ;; are its heading's. With on-sort, a left press on a heading calls
  ;; (on-sort key), and the heading that sort names ((key . up|down), or #f)
  ;; shows its direction. The first title starts at title-x: a tree's starts
  ;; over its roots' cells.
  (define (ui-table-headings! ui id sx sw x y h columns sort on-sort title-x
                              resize)
    (ui-table-call-with-clip ui sx y sw h
      (lambda ()
        (let loop ([cs columns] [cx x])
          (unless (null? cs)
            (let* ([key (caar cs)] [cw (caddr (car cs))]
                   [hid (list id 'header key)]
                   [tx (if (eq? cs columns) title-x cx)]
                   [flags (ui-column-flags (car cs))]
                   [tip (ui-column-tip (car cs))])
              (cond
                [on-sort
                 (ui-pressable! ui hid cx y cw h (lambda () (on-sort key))
                                '() (list 'focus 'keep 'tip tip)
                                '((L . "Sort")))]
                [tip (ui-region! ui hid cx y cw h 'tip tip)])
              (unless (= tx cx)
                (ui-draw-table-header cx y (- tx cx) h '() "" #f))
              (ui-draw-table-header tx y (- (+ cx cw) tx) h
                                    (if on-sort
                                        (apply ui-flags ui hid flags)
                                        flags)
                                    (cadar cs)
                                    (and sort (eq? (car sort) key) (cdr sort)))
              (loop (cdr cs) (+ cx cw)))))
        (ui-table-handles! ui id x y h columns sx sw
                           (or resize (theme 'table-resize))))))

  ;; Calls thunk with its drawing and its regions cut to x y w h: for a
  ;; table's headings, which a column the user widened carries past the
  ;; table's edge, as it does the rows.
  (define (ui-table-call-with-clip ui x y w h thunk)
    (let ([clip (ui-state-clip ui)])
      (ui-state-clip-set! ui (call-with-values
                               (lambda () (ui-cut x y w h clip))
                               list))
      (with-clip (x y w h) (thunk))
      (ui-state-clip-set! ui clip)))

  (at-load
   (theme-default! 'table-header-height
                   (theme-rule (round (+ (font-line-height 'ui-small) 13)))))
  (at-load
   (theme-default! 'table-row-height
                   (theme-rule (round (+ (font-line-height 'ui) 13)))))
  (define (ui-table-header-height) (theme 'table-header-height))
  (define (ui-table-row-height) (theme 'table-row-height))

  ;; Where a table's text starts in a cell, and in its heading: what a cell
  ;; draws itself starts there, so that it lines up under the heading.
  (define-part (ui-table-cell-inset) 10)

  ;; A cell's text, from the inset, cut to the cell (with right, a number at
  ;; the right, the inset short of the edge); its flags, its row's and its
  ;; column's, are a label's (dim, mono).
  (define-part (ui-draw-cell x y w h flags text)
    (let ([in (ui-table-cell-inset)])
      (ui-draw-label (+ x in) y (max 0 (- w in in)) h flags text)))

  ;; dir: up, down or #f (not sorted by this column). A heading lines up
  ;; with its column's cells: from the inset at the left, or up to it at the
  ;; right (flags right: numbers), with its sort arrow on its other side.
  (define-part (ui-draw-table-header x y w h flags label dir)
    (let* ([in (ui-table-cell-inset)]
           [sh (font-line-height 'ui-small)] [g (ui-small-glyph-size)]
           [s (text-fit label (max 0 (- w 16 g)) 'ui-small)]
           [color (if (or dir (memq 'hover flags)) 'text 'text-faint)]
           [right? (memq 'right flags)]
           [tx (if right? (- (+ x w) in (text-width s 'ui-small)) (+ x in))]
           [end (draw-text tx (+ y (/ (- h sh) 2)) s color 'ui-small)])
      (fill-box x (- (+ y h) 1) w 1 'window-border)
      (when dir
        (ui-draw-glyph (if right? (- tx 4 g) (+ end 4)) (+ y (/ (- h g) 2)) g g
                       '(hover) dir))))

  ;; The line between two headings at x, where a drag resizes the column on
  ;; its left: faint where the style shows it at rest (table-dividers), and
  ;; stronger under the pointer or while dragged (flags hover, pressed).
  (define-part (ui-draw-table-divider x y h flags)
    (if (or (memq 'hover flags) (memq 'pressed flags))
        (fill-box (- x 1) y 2 h 'accent)
        (fill-box x (+ y 5) 1 (- h 10) 'window-border)))

  (define-part (ui-draw-table-row x y w h flags)
    (cond [(memq 'selected flags) (fill-box x y w h 'selection)]
          [(memq 'hover flags) (fill-box x y w h 'bg-2)])
    (fill-box x (- (+ y h) 1) w 1 (alpha 'window-border 0.6)))

  ;;; ---------------------------------------------------------------- tree
  ;;; A tree of the app's values (nodes), given by its roots and a children
  ;;; procedure, shown as rows with columns, as a table is. The first
  ;;; column is indented by depth, with a twisty that expands and collapses
  ;;; a node that has children. The kit keeps which nodes are expanded, and
  ;;; the app which is selected. Children are asked for only of the nodes
  ;;; shown, and only the rows in view are drawn. Like the table, the tree
  ;;; takes no keyboard focus: the app passes it keys (ui-tree-key).

  ;; A row as shown: its node, its depth (0 for a root), its parent's row
  ;; index (#f for a root), whether the node has children, and whether they
  ;; show.
  (define-record-type ui-tree-row
    (nongenerative schevana-ui-tree-row-1)
    (fields node depth parent kids? expanded?))

  ;; Returns the rows shown, as a vector of ui-tree-row: each root and,
  ;; under each expanded node, its children, depth first. children: (lambda
  ;; (node) ...), returning a list, empty for a leaf; expanded?: (lambda
  ;; (node) ...). Pure.
  (define (ui-tree-rows roots children expanded?)
    (let ([acc '()] [n 0])
      (let walk ([nodes roots] [depth 0] [parent #f])
        (for-each (lambda (node)
                    (let* ([kids (children node)]
                           [open? (and (pair? kids) (expanded? node) #t)]
                           [i n])
                      (set! acc (cons (make-ui-tree-row node depth parent
                                                        (pair? kids) open?)
                                      acc))
                      (set! n (+ n 1))
                      (when open? (walk kids (+ depth 1) i))))
                  nodes))
      (list->vector (reverse acc))))

  ;; Returns the index of the row in rows whose node is equal? to node, or
  ;; #f.
  (define (ui-tree-index rows node)
    (let loop ([i 0])
      (cond [(= i (vector-length rows)) #f]
            [(equal? (ui-tree-row-node (vector-ref rows i)) node) i]
            [else (loop (+ i 1))])))

  ;; Whether row j of rows (#f: none) is under row i, at any depth. (A row's
  ;; parent comes before it.)
  (define (ui-tree-under? rows j i)
    (let up ([p (and j (ui-tree-row-parent (vector-ref rows j)))])
      (and p (>= p i)
           (or (= p i) (up (ui-tree-row-parent (vector-ref rows p)))))))

  ;; Returns what key does to rows (as ui-tree-rows makes them), with row i
  ;; selected (#f: none) and page rows to a page: (select . j),
  ;; (expand . i), (collapse . i), (open . i), or #f. Up, Down, Page Up,
  ;; Page Down, Home and End move as in a table; Right expands a node, or
  ;; goes to its first child; Left collapses it, or goes to its parent;
  ;; Space expands or collapses; Return opens. Pure.
  (define (ui-tree-step rows i page key)
    (let ([r (and i (vector-ref rows i))])
      (case key
        [(right) (and r (ui-tree-row-kids? r)
                      (if (ui-tree-row-expanded? r)
                          (cons 'select (+ i 1))
                          (cons 'expand i)))]
        [(left) (and r (if (ui-tree-row-expanded? r)
                           (cons 'collapse i)
                           (let ([p (ui-tree-row-parent r)])
                             (and p (cons 'select p)))))]
        [(#\space) (and r (ui-tree-row-kids? r)
                        (cons (if (ui-tree-row-expanded? r) 'collapse 'expand)
                              i))]
        [(return) (and r (cons 'open i))]
        [else (let ([j (ui-table-step i (vector-length rows) page key)])
                (and j (cons 'select j)))])))

  ;; Returns which nodes of tree id are expanded or collapsed, where that
  ;; differs from how they start: a hashtable the kit keeps.
  (define (ui-tree-states ui id)
    (or (ui-memo ui (list id 'expanded) #f)
        (let ([states (make-hashtable equal-hash equal?)])
          (ui-memo! ui (list id 'expanded) states)
          states)))

  ;; Expands node in tree id (on? #t) or collapses it, from its next draw.
  (define (ui-tree-expand! ui id node on?)
    (let ([states (ui-tree-states ui id)])
      (unless (eq? on? (hashtable-ref states node 'unset))
        (hashtable-set! states node on?)
        (ui-memo! ui (list id 'generation) #f)   ; its rows change
        (invalidate! (current-window)))))

  ;; Handles a key that the app's key handler passes to tree id, as the
  ;; tree's last draw showed it (see ui-tree-step): the selection moves by
  ;; (on-select node), and Return calls (on-open node). Returns true when it
  ;; acted. A tree that the last draw did not show (the app showed something
  ;; else instead) takes no key.
  (define (ui-tree-key ui id key mods selected on-select on-open)
    (let* ([rows (if (ui-find ui (list id 'body))
                     (ui-memo ui (list id 'rows) '#())
                     '#())]
           [act (and (null? mods)
                     (ui-tree-step rows (ui-tree-index rows selected)
                                   (ui-memo ui (list id 'page) 1) key))])
      (and act
           (let ([node (ui-tree-row-node (vector-ref rows (cdr act)))])
             (case (car act)
               [(select) (on-select node)]
               [(open) (on-open node)]
               [else (ui-tree-expand! ui id node (eq? (car act) 'expand))])
             #t))))

  ;; roots: the top nodes; children: (lambda (node) ...), returning a list.
  ;; columns: ((key title width flag ...) ...), as a table's, under a
  ;; header; the first column holds the tree. selected: the node equal? to
  ;; it is selected. A left press calls on-select, or, on a twisty, expands
  ;; or collapses the node. cell draws a cell: (lambda (node key x y w h
  ;; flags) ...), as a table's; the first column's cell comes after the
  ;; indentation and the twisty. opts: 'expanded (true when nodes start
  ;; expanded; else they start collapsed); 'on-open (node), called on a
  ;; double click; 'on-menu (node x y), on a right press; 'on-hide (node),
  ;; called when a collapse hides the selected row, with node, the collapsed
  ;; one, to be selected, as Left would (by default on-select); 'tip (node
  ;; w), its tooltip or #f, w being its first cell's width; 'reveal, which
  ;; when true scrolls the selected row into view; 'dim (node), true to dim
  ;; its row (the flag dim); 'sort, 'on-sort and 'resize, as a table's
  ;; (without 'on-sort the headings take no presses, and the app gives roots
  ;; and children in the order sort names); and 'generation, a value that
  ;; changes (eqv?) whenever roots or children would give other nodes, so
  ;; that the rows are kept until it changes or a node is expanded or
  ;; collapsed (without it, they are made at every draw).
  (define (ui-tree ui id x y w h columns roots children selected on-select cell
                   . opts)
    (with-place 'list
      (lambda ()
        (let* (;; the scroll view's rect, its bar in a margin the content keeps
               [sx x] [sw w]
               [x (+ sx (ui-scrollbar-inset 'left))]
               [w (ui-table-room sw)]
               [columns (ui-table-filled (ui-table-columns ui id columns) w)]
               [hh (ui-table-header-height)] [rh (ui-tree-row-height)]
               [tip (plist-ref opts 'tip (lambda (node w) #f))]
               [on-open (plist-ref opts 'on-open (lambda (node) #f))]
               [on-menu (plist-ref opts 'on-menu (lambda (node x y) #f))]
               [on-hide (plist-ref opts 'on-hide on-select)]
               [sort (plist-ref opts 'sort #f)]
               [on-sort (plist-ref opts 'on-sort #f)]
               [dim? (plist-ref opts 'dim (lambda (node) #f))]
               [start (plist-ref opts 'expanded #f)]
               [generation (plist-ref opts 'generation #f)]
               [states (ui-tree-states ui id)]
               [rows (if (and generation
                              (eqv? generation
                                    (ui-memo ui (list id 'generation) #f)))
                         (ui-memo ui (list id 'rows) #f)
                         (ui-tree-rows roots children
                                       (lambda (node)
                                         (hashtable-ref states node start))))]
               [n (vector-length rows)] [body (list id 'body)]
               [view-h (max 0 (- h hh))] [w0 (caddr (car columns))]
               [c0 (cdr (assq 'cell (ui-tree-areas x y w0 rh 0)))])
          (ui-memo! ui (list id 'rows) rows)
          (ui-memo! ui (list id 'generation) generation)
          ;; The first title starts over a root's cell.
          (ui-table-headings! ui id sx sw x y hh columns sort on-sort (car c0)
                              (plist-ref opts 'resize #f))
          (when (plist-ref opts 'reveal #f)
            (let ([i (ui-tree-index rows selected)])
              (when i (ui-reveal! ui body (* i rh) (* (+ i 1) rh) view-h))))
          (ui-memo! ui (list id 'page) (max 1 (exact (floor (/ view-h rh)))))
          (ui-scroll ui body sx (+ y hh) sw view-h
            (lambda (top)
              (let ([vy (+ y hh)])
                (do ([i (max 0 (exact (floor (/ (- vy top) rh)))) (+ i 1)])
                    ((or (>= i n) (>= (+ top (* i rh)) (+ vy view-h))))
                  (let* ([r (vector-ref rows i)] [node (ui-tree-row-node r)]
                         [ry (+ top (* i rh))] [rid (list id 'row i)]
                         [areas (ui-tree-areas x ry w0 rh
                                               (ui-tree-row-depth r))]
                         [twisty (cdr (assq 'twisty areas))]
                         [c (cdr (assq 'cell areas))])
                    (ui-region! ui rid x ry w rh 'tip (tip node (caddr c))
                      'doc (if (plist-ref opts 'on-menu #f)
                               '((L . "Select or open") (R . "Menu"))
                               '((L . "Select or open")))
                      'on
                      (lambda (ev)
                        (and (eq? (car ev) 'press)
                             (case (list-ref ev 3)
                               [(left)
                                (if (and (ui-tree-row-kids? r)
                                         (apply point-in? (cadr ev) (caddr ev)
                                                twisty))
                                    (let ([open? (ui-tree-row-expanded? r)])
                                      (ui-tree-expand! ui id node (not open?))
                                      (when (and open?
                                                 (ui-tree-under?
                                                  rows
                                                  (ui-tree-index rows selected)
                                                  i))
                                        (on-hide node)))
                                    (begin
                                      (on-select node)
                                      (when (>= (list-ref ev 4) 2)
                                        (on-open node))))
                                #t]
                               [(right) (on-menu node (cadr ev) (caddr ev)) #t]
                               [else #f]))))
                    (let ([flags (apply ui-flags ui rid
                                        (append
                                         (if (equal? node selected)
                                             '(selected)
                                             '())
                                         (if (dim? node) '(dim) '())
                                         (if (ui-tree-row-kids? r) '(kids) '())
                                         (if (ui-tree-row-expanded? r)
                                             '(expanded)
                                             '())))])
                      (ui-draw-tree-row x ry w rh flags w0
                                        (ui-tree-row-depth r))
                      (cell node (caar columns) (car c) ry (caddr c) rh
                            (append flags (ui-column-flags (car columns))))
                      (let cells ([cs (cdr columns)] [cx (+ x w0)])
                        (unless (null? cs)
                          (cell node (caar cs) cx ry (caddr (car cs)) rh
                                (append flags (ui-column-flags (car cs))))
                          (cells (cdr cs) (+ cx (caddr (car cs))))))
                      (when (memq 'selected flags)
                        (ui-draw-highlight-over x ry w rh '())))))
                (+ top (* n rh)))))))))

  ;; A tree's rows are as high as a table's.
  (define (ui-tree-row-height) (ui-table-row-height))

  ;; Where a row at depth puts its twisty and its first cell, in its first
  ;; column x y w h, as ((twisty x y w h) (cell x y w h)): indented by a
  ;; twisty's width per level, but by at most half the column, so that a
  ;; deep row keeps room for its cell.
  (define-part (ui-tree-areas x y w h depth)
    (let* ([s (+ (ui-glyph-size) 8)]
           [in (min (* depth s) (max 0 (floor (/ (- w s) 2))))])
      (list (list 'twisty (+ x 4 in) y s h)
            (list 'cell (+ x 4 in s) y (max 0 (- w 4 in s)) h))))

  ;; A row's look: a table row's, with the twisty of a node with children
  ;; (flags kids, expanded) at its depth in its first column, w0 wide. With
  ;; dim, everything left of its first cell is dimmed, as the cells dim
  ;; themselves.
  (define-part (ui-draw-tree-row x y w h flags w0 depth)
    (let ([areas (ui-tree-areas x y w0 h depth)] [g (ui-glyph-size)])
      (ui-draw-table-row x y w h flags)
      (when (memq 'kids flags)
        (let ([t (cdr (assq 'twisty areas))])
          (ui-draw-glyph (+ (car t) (/ (- (caddr t) g) 2)) (+ y (/ (- h g) 2))
                         g g (if (memq 'hover flags) '(hover) '(quiet))
                         (if (memq 'expanded flags)
                             'chevron-down
                             'chevron-right))))
      (ui-draw-dim x y (- (cadr (assq 'cell areas)) x) h flags)))

  ;; A row that a view shows but leaves out (flags: dim; outside the app's
  ;; search, say), or a part of it, x y w h: shaded, unless it is selected.
  (define-part (ui-draw-dim x y w h flags)
    (when (and (memq 'dim flags) (not (memq 'selected flags)))
      (fill-box x y w h (alpha 'bg-0 0.6))))

  ;;; ---------------------------------------------------------------- chips

  ;; A tag: a pill whose hue comes from its label, so that a tag keeps its
  ;; color everywhere. The flag removable adds a ×, which turns red under the
  ;; pointer.
  (define-part (ui-draw-chip x y w h flags label)
    (let* ([sh (font-line-height 'ui-small)] [r (/ h 2)]
           [g (ui-small-glyph-size)] [removable? (memq 'removable flags)]
           [hue (app-color (string->symbol label))])
      (fill-box x y w h (alpha hue 0.18) r)
      (draw-text (+ x 8) (+ y (/ (- h sh) 2))
                 (text-fit label (- w 16 (if removable? (+ g 4) 0)) 'ui-small)
                 'text 'ui-small)
      (when removable?
        (let ([a (cdr (assq 'remove (ui-chip-areas x y w h)))])
          (ui-draw-glyph (+ (car a) (/ (- (caddr a) g) 2))
                         (+ (cadr a) (/ (- (cadddr a) g) 2)) g g
                         (if (memq 'hover flags) '(danger hover) '())
                         'cross)))))

  ;; A chip's size: its text 8 in from either end, and, when removable, a ×
  ;; after it.
  (define-part (ui-chip-size label removable?)
    (values (+ 16 (text-width label 'ui-small)
               (if removable? (+ (ui-small-glyph-size) 4) 0))
            (round (+ (font-line-height 'ui-small) 8))))

  (define-part (ui-chip-areas x y w h)
    (let ([g (ui-small-glyph-size)])
      (list (list 'remove (- (+ x w) g 10) y (+ g 6) h))))

  ;; Chips (removable) and a field to type more, wrapped in one box. The
  ;; draft is the field's text; a comma or Return adds it (Return with
  ;; nothing but spaces typed is left to others), and Backspace in an empty
  ;; field removes the last chip. on-add gets a list: the draft, or a
  ;; paste's comma-separated parts all at once. opts: 'placeholder, and
  ;; 'suggest, as a text field's; a pick adds the suggestion. Returns the
  ;; box's bottom. The box's flags say that it holds chips, the last chip's
  ;; that it is last, and every other chip's where the next one starts,
  ;; (next x y), so that a style that draws the chips as a list knows where
  ;; the list ends and where it wraps.
  (define (ui-chip-input ui id x y w chips draft on-draft on-add on-remove
                         . opts)
    (with-place 'field
      (lambda ()
        (let* ([areas (ui-chip-input-areas x y w chips)]
               [field (cdr (assq 'field areas))]
               [bottom (+ (cadr field) (cadddr field))]
               [fid (list id 'field)] [n (length chips)]
               [chip-areas (map cdr (filter (lambda (a) (eq? (car a) 'chip))
                                            areas))])
          (ui-draw-field x y w (- bottom y) (ui-flags ui fid 'chips))
          (for-each
           (lambda (chip a i)
             (let ([rid (list id 'remove i)]
                   [r (cdr (assq 'remove (apply ui-chip-areas a)))])
               (ui-pressable! ui rid (car r) (cadr r) (caddr r) (cadddr r)
                              (lambda () (on-remove i)) '()
                              '(focus keep tip "Remove") '((L . "Remove")))
               (apply ui-draw-chip
                      (append a (list (apply ui-flags ui rid 'removable
                                             (ui-chain-flags chip-areas i))
                                      chip)))))
           chips chip-areas
           (iota (length chips)))
          (apply ui-text-field ui fid
                 (append field
                         (list draft
                               (lambda (s)
                                 (let ([parts (string-split s #\,)])
                                   (when (pair? (cdr parts))
                                     (on-add (list-head parts
                                                        (- (length parts) 1))))
                                   (on-draft (car (last-pair parts)))))
                               'inner #t
                               'placeholder (plist-ref opts 'placeholder #f)
                               'suggest (plist-ref opts 'suggest #f)
                               'on-pick (lambda (s) (on-add (list s))
                                          (on-draft ""))
                               'on-key
                               (lambda (key mods text)
                                 (cond
                                   [(and (eq? key 'return) (null? mods)
                                         (exists (lambda (c)
                                                   (not (char-whitespace? c)))
                                                 (string->list text)))
                                    (on-add (list text)) (on-draft "") #t]
                                   [(and (eq? key 'backspace) (string=? text "")
                                         (pair? chips))
                                    (on-remove (- (length chips) 1)) #t]
                                   [else #f])))))
          bottom))))

  ;; Returns a chain's flags for the i-th element of areas ((x y w h) ...):
  ;; last, or where the next one starts, (next x y).
  (define (ui-chain-flags areas i)
    (if (= i (- (length areas) 1))
        '(last)
        (let ([b (list-ref areas (+ i 1))])
          (list (list 'next (car b) (cadr b))))))

  ;; Where a chip input at (x, y), w wide, puts its chips and its field:
  ;; ((chip x y w h) ... (field x y w h)), flowed in rows of a control's
  ;; height, 4 apart and 4 in from the sides. The field takes the rest of
  ;; the last row, or a row of its own when less than 8 line heights of
  ;; width is left.
  (define-part (ui-chip-input-areas x y w chips)
    (let*-values ([(pad ch) (values 4 (ui-control-height))]
                  [(sizes) (map (lambda (c)
                                  (call-with-values
                                    (lambda () (ui-chip-size c #t))
                                    cons))
                                chips)]
                  [(at height)
                   (ui-flow (+ x pad) y (- w pad pad) pad
                            (append (map (lambda (s) (cons (car s) ch)) sizes)
                                    (list (cons (min (- w pad pad)
                                                     (* 8
                                                        (font-line-height 'ui)))
                                                ch))))])
      (let ([f (list-ref at (length chips))])
        (append (map (lambda (s p)
                       (list 'chip (car p)
                             (+ (cdr p) (floor (/ (- ch (cdr s)) 2)))
                             (car s) (cdr s)))
                     sizes (list-head at (length chips)))
                (list (list 'field (car f) (cdr f) (- (+ x w) pad (car f))
                            ch))))))

  ;; Returns the box's height for chips at width w.
  (define-part (ui-chip-input-size w chips)
    (let ([f (cdr (assq 'field (ui-chip-input-areas 0 0 w chips)))])
      (+ (cadr f) (cadddr f))))

  ;; Chips in rows from (x, y), w wide, each row a control's height: a
  ;; left press on chip i calls (on-press i) (with on-press #f, they take no
  ;; press). opts: 'on-remove (i), for a × on each; 'add, a thunk, and
  ;; 'add-label ("Add" by default), for a button after them; 'empty, the
  ;; words shown when there are none and no add ("None" by default); 'tip
  ;; (i), a chip's tooltip; 'keys, what names each chip's widgets, (id key)
  ;; and (id remove key) (by default its index). Returns the y below them.
  (define (ui-chips ui id x y w labels on-press . opts)
    (let* ([on-remove (plist-ref opts 'on-remove #f)]
           [keys (plist-ref opts 'keys (iota (length labels)))]
           [add (plist-ref opts 'add #f)]
           [add-label (plist-ref opts 'add-label "Add")]
           [tip (plist-ref opts 'tip (lambda (i) #f))]
           [areas (ui-chips-areas x y w labels (and on-remove #t)
                                  (and add add-label))]
           [chips (map cdr (filter (lambda (a) (eq? (car a) 'chip)) areas))]
           [ch (ui-control-height)])
      (for-each
       (lambda (l a i key)
         (let ([cid (list id key)] [rid (list id 'remove key)])
           (when on-press
             (apply ui-region! ui cid
                    (append a (list 'cursor 'hand 'focus 'keep 'tip (tip i)
                                    'doc '((L . "Open"))
                                    'on (lambda (ev)
                                          (and (eq? (car ev) 'press)
                                               (eq? (list-ref ev 3) 'left)
                                               (begin (on-press i) #t)))))))
           (when on-remove
             (let ([r (cdr (assq 'remove (apply ui-chip-areas a)))])
               (ui-pressable! ui rid (car r) (cadr r) (caddr r) (cadddr r)
                              (lambda () (on-remove i)) '()
                              '(focus keep tip "Remove") '((L . "Remove")))))
           (apply ui-draw-chip
                  (append a
                          (list (append (cond [on-remove
                                               (ui-flags ui rid 'removable)]
                                              [on-press (ui-flags ui cid)]
                                              [else '()])
                                        (ui-chain-flags chips i))
                                l)))))
       labels chips (iota (length labels)) keys)
      (let ([b (assq 'add areas)])
        (cond
          [b (apply ui-button ui (list id 'add)
                    (append (cdr b) (list add-label add 'glyph 'plus 'quiet #t
                                          'focus 'keep)))]
          [(null? labels)
           (ui-draw-label x y w ch '(hint) (plist-ref opts 'empty "None"))]))
      (cdr (assq 'bottom areas))))

  ;; Where chips go in rows from (x, y), w wide, each row a control's height
  ;; and 4 apart, with each chip centered in its row and cut to w, and the
  ;; add button (with add-label) after them: ((chip x y w h) ... (add x y w
  ;; h) (bottom . y)).
  (define (ui-chips-areas x y w labels removable? add-label)
    (let*-values ([(ch) (ui-control-height)]
                  [(sizes) (map (lambda (l)
                                  (let-values ([(cw h) (ui-chip-size
                                                        l removable?)])
                                    (cons (min cw w) h)))
                                labels)]
                  [(bw bh) (if add-label
                               (ui-button-size add-label 'plus)
                               (values 0 0))]
                  [(at height)
                   (ui-flow x y w 4
                            (append (map (lambda (s) (cons (car s) ch)) sizes)
                                    (if add-label (list (cons bw bh)) '())))])
      (append (map (lambda (s p)
                     (list 'chip (car p)
                           (+ (cdr p) (floor (/ (- ch (cdr s)) 2)))
                           (car s) (cdr s)))
                   sizes (list-head at (length labels)))
              (if add-label
                  (let ([p (list-ref at (length labels))])
                    (list (list 'add (car p) (cdr p) bw bh)))
                  '())
              (list (cons 'bottom (+ y (max ch height)))))))

  ;; Returns the chips' height.
  (define (ui-chips-height w labels removable? add-label)
    (cdr (assq 'bottom (ui-chips-areas 0 0 w labels removable? add-label))))

  ;;; ------------------------------------------------------------------
  ;;; avatar

  ;; "Pavel Uvarov" → "PU", "Claude" → "C".
  (define (ui-initials name)
    (let ([words (remp (lambda (w) (string=? w ""))
                       (string-split name #\space))])
      (if (null? words)
          "?"
          (list->string
           (map (lambda (w) (char-upcase (string-ref w 0)))
                (if (null? (cdr words))
                    words
                    (list (car words) (car (last-pair words)))))))))

  ;; Returns the size of a person's avatar, by name, as (values w h). flags
  ;; may hold named (the name is written beside it, so a style may leave the
  ;; avatar out: (values 0 0)).
  (define-part (ui-avatar-size flags name)
    (let ([s (round (+ (font-line-height 'ui-small) 7))]) (values s s)))

  ;; A circle in one color per person, however the name was typed (spaces
  ;; around it, capitals), with the initials.
  (define-part (ui-draw-avatar x y w h flags name)
    (let ([color (let trim ([i 0] [j (string-length name)])
                   (cond [(and (< i j) (char-whitespace? (string-ref name i)))
                          (trim (+ i 1) j)]
                         [(and (< i j)
                               (char-whitespace? (string-ref name (- j 1))))
                          (trim i (- j 1))]
                         [else (app-color (string->symbol
                                           (string-downcase
                                            (substring name i j))))]))])
      (fill-circle (+ x (/ w 2)) (+ y (/ w 2)) (/ w 2) color)
      (text-draw-centered x y w w (ui-initials name) (color-readable-on color)
                          'ui-small)))

  ;;; ------------------------------------------------------------------
  ;;; progress, tooltip

  (define-part (ui-draw-progress x y w h flags frac)
    (fill-box x y w h 'bg-3 (/ h 2))
    (when (> frac 0)
      (fill-box x y (max h (* w (min 1 frac))) h (if (>= frac 1) 'green 'accent)
                (/ h 2))))

  (at-load
   (theme-default! 'progress-height
                   (theme-rule (max 4 (round (* (font-line-height 'ui) 0.4))))))
  (define (ui-progress-height) (theme 'progress-height))

  ;;; ------------------------------------------------------------------
  ;;; charts: stacked bars, lines, a sparkline, a legend
  ;;; A series is drawn in the color the app gives it. The kit's chart-1 to
  ;;; chart-8 are settings made from the palette's hues, so that a style can
  ;;; give its own (Genera, which has no color, stipples), and chart-muted-1
  ;;; and chart-muted-2 are two quiet ones for what is not work (time
  ;;; waited, say): a flat gray and a lined one, told apart by their texture
  ;;; in any palette. A mark behind a bar, a share of the bars, the
  ;;; reference lines and a flag over a bar are chart-mark, chart-share,
  ;;; chart-rule and chart-flag; a mark that says all is well is chart-ok, a
  ;;; quiet color, so that a flag stands out from it.

  (at-load
   (color-default! 'chart-1 'yellow))
  (at-load
   (color-default! 'chart-2 'orange))
  (at-load
   (color-default! 'chart-3 'magenta))
  (at-load
   (color-default! 'chart-4 'green))
  (at-load
   (color-default! 'chart-5 'cyan))
  (at-load
   (color-default! 'chart-6 'teal))
  (at-load
   (color-default! 'chart-7 'red))
  (at-load
   (color-default! 'chart-8 'accent-2))
  (at-load
   (color-default! 'chart-muted-1 (alpha 'text 0.2)))
  (at-load
   (color-default! 'chart-muted-2
                   (stipple (alpha 'text 0.5) (alpha 'text 0.12) "#" "." ".")))
  (at-load
   (color-default! 'chart-mark (alpha 'text 0.12)))
  (at-load
   (color-default! 'chart-share 'accent))
  (at-load
   (color-default! 'chart-rule 'text-faint))
  (at-load
   (color-default! 'chart-flag 'red))
  (at-load
   (color-default! 'chart-ok (alpha 'green 0.55)))

  ;; A stacked bar chart, one bar per value (a step, say), the newest at the
  ;; right. bars, oldest first, are (segments . share): segments are ((color
  ;; . value) ...) from the bottom up, and share is how much of the bar to
  ;; show in chart-share (#f for none). Values are exact integers (ns, say),
  ;; so the bars' pixels are worked out in integers. top is the value at the
  ;; chart's top; rules are ((value . label) ...), reference lines labeled
  ;; in a scale at the left. The bar marked (its index, or #f) and the one
  ;; under the pointer show a mark; a left press on a bar calls (on-press
  ;; index). opts: 'tip, a procedure of a bar's index that returns its
  ;; tooltip (asked only for the bar under the pointer), or #f; 'flagged, a
  ;; procedure of a bar's index, true for a bar to flag at the chart's top
  ;; (a late step, say). Returns the index of the bar under the pointer, or
  ;; #f.
  ;; ui-bar-chart-under returns the bar of n that the pointer is over, by
  ;; where the bars are, or #f.
  (define (ui-bar-chart-under ui areas n)
    (let ([plot (cdr (assq 'plot areas))] [win (current-window)]
          [mx (ui-state-mx ui)] [my (ui-state-my ui)])
      (and win (eq? (window-hover win) 'content)
           (point-in? mx my (car plot) (cadr plot) (caddr plot) (cadddr plot))
           (let ([i (- n 1 (exact (floor (/ (- (+ (car plot) (caddr plot)) mx)
                                            (cadr (assq 'bar areas))))))])
             (and (<= 0 i) i)))))

  (define (ui-bar-chart ui id x y w h bars top rules marked on-press . opts)
    (let* ([n (length bars)] [areas (ui-bar-chart-areas x y w h n rules)]
           [plot (cdr (assq 'plot areas))] [win (current-window)]
           [tip-of (plist-ref opts 'tip #f)]
           [flagged? (plist-ref opts 'flagged (lambda (i) #f))]
           [under (and tip-of (ui-bar-chart-under ui areas n))])
      (for-each (lambda (i)
                  (let-values ([(bx bw) (ui-bar-chart-bar areas n i)])
                    (when (>= bx (car plot))
                      (ui-region! ui (list id i) bx (cadr plot) bw (cadddr plot)
                        'doc '((L . "Select"))
                        'tip (and (eqv? i under) (tip-of i))
                        'on (lambda (ev)
                              (and (eq? (car ev) 'press)
                                   (eq? (list-ref ev 3) 'left)
                                   (begin (on-press i) #t)))))))
                (iota n))
      (let* ([r (ui-region-at ui (ui-state-mx ui) (ui-state-my ui))]
             [rid (and r (ui-region-id r))]
             [hover (and win (eq? (window-hover win) 'content) (pair? rid)
                         (equal? (car rid) id) (pair? (cdr rid)) (cadr rid))])
        (ui-draw-bar-chart x y w h '()
                           (map (lambda (b i)
                                  (list (car b) (cdr b)
                                        (cond [(eqv? i hover) 'hover]
                                              [(eqv? i marked) 'marked]
                                              [else #f])
                                        (and (flagged? i) #t)))
                                bars (iota n))
                           top rules)
        hover)))

  ;; A bar chart's pieces, as ((plot x y w h) (bar w)): the plot, right of
  ;; the scale's labels and 4 clear of the top and right edges, on whole
  ;; pixels, and the bars' width for n bars, in whole pixels, at least 1 and
  ;; at most 6.
  (define-part (ui-bar-chart-areas x y w h n rules)
    (let* ([px (exact (ceiling (+ x 12 (text-widest (map cdr rules)
                                                     'ui-small))))]
           [py (exact (ceiling (+ y 4)))]
           [pw (max 0 (exact (floor (- (+ x w) 4 px))))]
           [ph (max 0 (exact (floor (- (+ y h) py))))])
      (list (list 'plot px py pw ph)
            (list 'bar (max 1 (min 6 (quotient pw (max n 1))))))))

  ;; Returns bar i of n by the areas, as (values x w): the newest is at the
  ;; plot's right, and a bar left of the plot does not fit.
  (define (ui-bar-chart-bar areas n i)
    (let ([plot (cdr (assq 'plot areas))] [bw (cadr (assq 'bar areas))])
      (values (+ (car plot) (- (caddr plot) (* bw (- n i)))) bw)))

  ;; bars: each is (segments share mark flag), with mark hover, marked or
  ;; #f, and flag true for a strip at the plot's top over the bar. The
  ;; segments of one color are filled together. A segment's top is where
  ;; the sum up to it rounds down to, in whole pixels, so that a bar's
  ;; segments meet.
  (define-part (ui-draw-bar-chart x y w h flags bars top rules)
    (let* ([n (length bars)] [areas (ui-bar-chart-areas x y w h n rules)]
           [plot (cdr (assq 'plot areas))] [px (car plot)] [py (cadr plot)]
           [pw (caddr plot)] [ph (cadddr plot)] [bottom (+ py ph)]
           [high (lambda (v) (if (> top 0) (div (* ph (min v top)) top) 0))]
           [rects (make-eq-hashtable)]   ; color -> ((x y w h) ...)
           [colors '()])                 ; the series' colors, in order
      (define (rect! color r)
        (unless (or (hashtable-contains? rects color)
                    (memq color '(chart-mark chart-share chart-flag)))
          (set! colors (cons color colors)))
        (hashtable-update! rects color (lambda (rs) (cons r rs)) '()))
      (ui-draw-surface x y w h '(well))
      (for-each
       (lambda (bar i)
         (let-values ([(bx bw) (ui-bar-chart-bar areas n i)])
           (when (>= bx px)
             (let ([gap (if (>= bw 3) 1 0)])
               (when (caddr bar) (rect! 'chart-mark (list bx py bw ph)))
               (fold-left (lambda (sum s)
                            (let* ([below (high sum)]
                                   [above (high (+ sum (cdr s)))])
                              (when (> above below)
                                (rect! (car s)
                                       (list bx (- bottom above) (- bw gap)
                                             (- above below))))
                              (+ sum (cdr s))))
                          0 (car bar))
               (when (cadr bar)
                 (let ([sh (high (cadr bar))])
                   (rect! 'chart-share
                          (list bx (- bottom sh) (- bw gap) sh))))
               (when (cadddr bar)
                 (rect! 'chart-flag (list bx py (- bw gap) 3)))))))
       bars (iota n))
      ;; The marks go under the series, and the share and the flags over
      ;; them.
      (for-each (lambda (c)
                  (let ([rs (hashtable-ref rects c '())])
                    (for-each (lambda (r)
                                (fill-box (car r) (cadr r) (caddr r) (cadddr r)
                                          c))
                              rs)))
                (append '(chart-mark) (reverse colors)
                        '(chart-share chart-flag)))
      (ui-draw-bar-chart-rules x areas top rules)))

  ;; Draws a chart's reference lines over its bars, and their labels in its
  ;; scale. A rule at #f only widens the labels' room, so that charts
  ;; stacked one over another can line their bars up.
  (define (ui-draw-bar-chart-rules x areas top rules)
    (let* ([plot (cdr (assq 'plot areas))] [px (car plot)] [pw (caddr plot)]
           [ph (cadddr plot)] [bottom (+ (cadr plot) ph)])
      (for-each (lambda (r)
                  (let ([ly (+ (- bottom (if (> top 0)
                                             (div (* ph (min (car r) top)) top)
                                             0))
                               0.5)])
                    (draw-line px ly (+ px pw) ly 'chart-rule)
                    (draw-text (+ x 6)
                               (ui-text-y (- ly (/ (font-line-height 'ui-small)
                                                   2))
                                          'ui-small)
                               (cdr r) 'text-faint 'ui-small)))
                (filter car rules))))

  ;;; ------------------------------------------------------------------
  ;;; streams: a chart of what keeps coming, one bar per moment, the newest
  ;;; at the right. Its rows are on the GPU and a paint draws them, so a new
  ;;; moment costs a row of numbers, and the chart costs one record, however
  ;;; many bars flow past. A moment is named by its seq, which only grows.
  ;;;
  ;;;   (define s (ui-stream-new 2048 columns '(("late" chart-flag))))
  ;;;   (ui-stream-send! s oldest newest (lambda (seq j) ...))
  ;;;   (ui-stream ui 'id s x y w h newest oldest top rules stack bar ...)
  ;;;   (ui-stream-release! s)    when its window closes, to free at once
  ;;;
  ;;; A row is its columns' numbers, then one word per strip. A strip is a
  ;;; thin lane over the bars, (label color ...), with the label #f for none;
  ;;; its word says which of its colors a moment has, counting from 1, or 0
  ;;; for none.

  ;; The record has a name of its own, since ui-stream names the widget.
  (define-record-type (ui-stream-record make-ui-stream ui-stream?)
    (nongenerative schevana-ui-stream)
    (fields (immutable rows ui-stream-rows)
            (immutable columns ui-stream-columns)
            (immutable strips ui-stream-strips)
            ;; the rows, made when first sent
            (mutable buffer ui-stream-buffer ui-stream-buffer-set!)
            ;; what the paint colors them with
            (mutable palette ui-stream-palette ui-stream-palette-set!)
            ;; the newest moment the rows have
            (mutable sent ui-stream-sent ui-stream-sent-set!)))

  (define (ui-stream-new rows columns strips)
    (make-ui-stream rows columns strips #f #f -1))

  ;; The largest a column's number can be, since the paint adds up a row in
  ;; 32 bits.
  (define ui-stream-most 100000000)

  (define (ui-stream-words s)
    (+ (ui-stream-columns s) (length (ui-stream-strips s))))

  (define (ui-stream-colors s)
    (fold-left (lambda (n strip) (+ n (length (cdr strip)))) 0
               (ui-stream-strips s)))

  ;; The moments begin again: the next send sends all it is given, whatever
  ;; was sent before.
  (define (ui-stream-restart! s) (ui-stream-sent-set! s -1))

  ;; The moments from seq on are sent again at the next send, with their
  ;; words read again: for moments still changing.
  (define (ui-stream-resend! s seq)
    (when (>= (ui-stream-sent s) seq) (ui-stream-sent-set! s (- seq 1))))

  (define (ui-stream-release! s)
    (when (ui-stream-buffer s)
      (gpu-buffer-release! (ui-stream-buffer s))
      (gpu-buffer-release! (ui-stream-palette s))
      (ui-stream-buffer-set! s #f)
      (ui-stream-palette-set! s #f)
      (ui-stream-sent-set! s -1)))

  ;; Sends the rows of the moments after those already sent, up to newest:
  ;; as many as the stream holds, and none before oldest. (word-of seq j)
  ;; gives word j of a moment's row. A newest behind what was sent means the
  ;; history began again.
  (define (ui-stream-send! s oldest newest word-of)
    (unless (ui-stream-buffer s)
      (ui-stream-buffer-set! s (make-gpu-buffer (* (ui-stream-rows s)
                                                   (ui-stream-words s))))
      (ui-stream-palette-set! s (make-gpu-buffer
                                 (+ 1 (* ui-stream-stack-words
                                         (ui-stream-columns s))
                                    (ui-stream-colors s)))))
    (when (< newest (ui-stream-sent s)) (ui-stream-sent-set! s -1))
    (let ([rows (ui-stream-rows s)] [words (ui-stream-words s)]
          [columns (ui-stream-columns s)] [buffer (ui-stream-buffer s)]
          ;; What each strip's words start from, among the strips' colors.
          [bases (let loop ([ss (ui-stream-strips s)] [at 0])
                   (if (null? ss)
                       '()
                       (cons at (loop (cdr ss) (+ at (length (cdar ss)))))))])
      (do ([seq (max (+ (ui-stream-sent s) 1) (- newest rows -1) oldest)
                (+ seq 1)])
          ((> seq newest) (ui-stream-sent-set! s newest))
        (let ([at (* words (modulo seq rows))])
          (do ([j 0 (+ j 1)]) ((= j words))
            (let ([v (word-of seq j)])
              (gpu-buffer-set!
               buffer (+ at j)
               (cond [(< j columns) (max 0 (min ui-stream-most v))]
                     [(eqv? v 0) 0]
                     [else (+ v (list-ref bases (- j columns)))]))))))))

  ;; From the right, one bar per moment; up each bar, its columns as the
  ;; palette stacks them; over the bars, the strips.
  ;; The palette's first rows are the stack, from the bottom up: which
  ;; column, and its color.
  (define-shader-layout ui-stream-stack palette (column color))

  (define-paint (ui-stream-bars x y)
    ([moments fx-buffer]
     [palette fx-buffer]   ; ui-stream-stack's rows, with room for every column;
                           ; after them, the strips' colors
     [stacked fixnum]      ; how many entries the stack holds
     [columns fixnum]      ; the numbers a row starts with
     [rows fixnum]         ; the ring's rows
     [row-words fixnum]
     [newest fixnum]       ; the moment of the bar at the right
     [shown fixnum]        ; how many moments there are to show
     [w fixnum]
     [h fixnum]
     [top fixnum]          ; the number the bars' top stands for
     [bar flonum]          ; a bar's width, in device pixels
     [gap flonum]          ; the space clear at its right
     [strips fixnum]
     [strip-h fixnum]      ; a strip's height, its gap included
     [strip-gap fixnum]
     [bars-at fixnum])     ; where the bars' room starts, under the strips
    (let* ([d (fl- (fl- (fixnum->flonum w) 0.5) (fixnum->flonum x))]
           [col (flonum->fixnum (flfloor (fl/ d bar)))]
           [within (fl- d (fl* (fixnum->flonum col) bar))]
           [row (fx* (fxmod (fx- newest col) rows) row-words)]
           [lanes (fx* strips strip-h)])
      (define (spent k)
        (fx-ref moments
                (fx+ row
                     (ui-stream-stack-column (fx* k ui-stream-stack-words)))))
      (cond
        [(or (fx>= col shown) (fl< within gap)) 0]
        [(fx< y bars-at)
         (if (fx< y lanes)
             (let ([mark (fx-ref moments
                                 (fx+ row
                                      (fx+ columns (fxquotient y strip-h))))])
               (if (or (fx= mark 0)
                       (fx>= (fxmod y strip-h) (fx- strip-h strip-gap)))
                   0
                   (fx-ref palette
                           (fx+ (fx* columns ui-stream-stack-words)
                                (fx- mark 1)))))
             0)]
        [else
         (let ([at (fl* (fl/ (fl- (fixnum->flonum (fx- h y)) 0.5)
                             (fixnum->flonum (fx- h bars-at)))
                        (fixnum->flonum top))])
           (do-bounded 12
               ([k 0 (fx+ k 1)]
                [sum (spent 0) (fx+ sum (spent (fx+ k 1)))])
             ((or (fx>= k stacked) (fl> (fixnum->flonum sum) at))
              (if (fx>= k stacked)
                  0
                  (ui-stream-stack-color (fx* k ui-stream-stack-words))))))])))

  ;; Returns a strip's height and the space clear under it: a labeled strip
  ;; takes a line.
  (define-part (ui-stream-lane strips)
    (if (exists car strips)
        (values (font-line-height 'ui-small) 3)
        (values 3 0)))

  ;; Returns how far down the bars' room starts: labeled strips leave half a
  ;; line more, for the label of a rule at the bars' top.
  (define (ui-stream-room strips)
    (let-values ([(lane-h lane-gap) (ui-stream-lane strips)])
      (+ (* lane-h (length strips))
         (if (exists car strips)
             (quotient (font-line-height 'ui-small) 2)
             0))))

  ;; A stream's pieces, as ((plot x y w h) (bar w) (bars x y w h) (lane h
  ;; gap)): a bar chart's, with room left for the strips' labels too, and the
  ;; bars' part of the plot, under the strips.
  (define-part (ui-stream-areas s x y w h n rules)
    (let*-values
        ([(strips) (ui-stream-strips s)]
         [(lane-h lane-gap) (ui-stream-lane strips)]
         [(areas) (ui-bar-chart-areas
                   x y w h n
                   (append rules
                           (map (lambda (strip) (cons 0 (car strip)))
                                (filter car strips))))]
         [(plot) (cdr (assq 'plot areas))]
         [(room) (ui-stream-room strips)])
      (append areas
              (list (list 'bars (car plot) (+ (cadr plot) room) (caddr plot)
                          (max 0 (- (cadddr plot) room)))
                    (list 'lane lane-h lane-gap)))))

  ;; Returns how many moments there are to show: as many bars bar wide as
  ;; fit, or, with no bar, as many as the rows hold.
  (define (ui-stream-count s x y w h newest oldest rules bar)
    (if newest
        (max 0 (min (if bar
                        (quotient (cadddr (assq 'plot
                                                (ui-stream-areas s x y w h 1
                                                                       rules)))
                                  bar)
                        (ui-stream-rows s))
                    (+ 1 (- newest oldest))))
        0))

  ;; Returns (values count areas). With fit? true, every moment goes across
  ;; the width, with bars as narrow as that takes; with fit? 'whole, the bars
  ;; are whole device pixels, so that all are as wide, and the oldest
  ;; moments that do not fit are left out.
  (define (ui-stream-layout s x y w h newest oldest rules bar fit?)
    (let* ([count (ui-stream-count s x y w h newest oldest rules
                                   (and (not fit?) bar))]
           [areas (ui-stream-areas s x y w h count rules)]
           [room (cadddr (assq 'plot areas))])
      (cond
        [(eq? fit? 'whole)
         (let* ([scale (draw-scale)]
                [pixels (exact (floor (* scale room)))]
                [px (max 1 (exact (ceiling (/ pixels (max count 1)))))])
           (values (min count (quotient pixels px))
                   (cons (list 'bar (/ px scale)) areas)))]
        [fit? (values count (cons (list 'bar (/ room (max count 1))) areas))]
        [else (values count areas)])))

  ;; Returns the moment at x, or the nearest of those shown when x is off
  ;; either end.
  (define (ui-stream-seq-at areas x newest count)
    (let ([plot (cdr (assq 'plot areas))] [bw (cadr (assq 'bar areas))])
      (- newest
         (max 0 (min (- count 1)
                     (exact (floor (/ (- (+ (car plot) (caddr plot)) x)
                                      bw))))))))

  ;; rules and top are in the columns' numbers; marked lists the moments
  ;; marked; over, a procedure (over areas count) or #f, draws over the bars
  ;; and under the rules.
  (define-part (ui-draw-stream x y w h flags s areas count newest top rules
                               stack
                               marked over)
    (let*-values
        ([(plot) (cdr (assq 'plot areas))]
         [(px py pw ph) (apply values plot)]
         [(bw) (cadr (assq 'bar areas))]
         [(lane-h lane-gap) (apply values (cdr (assq 'lane areas)))]
         [(strips) (ui-stream-strips s)]
         [(columns) (ui-stream-columns s)])
      (ui-draw-surface x y w h '(well))
      (when newest
        (for-each (lambda (seq)
                    (let-values ([(bx bx-w)
                                  (ui-bar-chart-bar areas count
                                                    (- count 1
                                                       (- newest seq)))])
                      (when (>= bx px)
                        (fill-box bx py bx-w ph 'chart-mark))))
                  marked))
      (when (and newest (ui-stream-buffer s))
        (let ([palette (ui-stream-palette s)] [scale (draw-scale)])
          (for-each (lambda (entry k)
                      (let ([row (* k ui-stream-stack-words)])
                        (gpu-buffer-set! palette (+ row ui-stream-stack-column)
                                         (car entry))
                        (gpu-buffer-set! palette (+ row ui-stream-stack-color)
                                         (if (cdr entry)
                                             (color-word (cdr entry))
                                             0))))
                    stack (iota (length stack)))
          (fold-left (lambda (at strip)
                       (for-each (lambda (color i)
                                   (gpu-buffer-set!
                                    palette
                                    (+ (* ui-stream-stack-words columns) at i)
                                    (color-word color)))
                                 (cdr strip) (iota (length (cdr strip))))
                       (+ at (length (cdr strip))))
                     0 strips)
          (fill-shader px py pw ph ui-stream-bars
                       (ui-stream-buffer s) palette (length stack) columns
                       (ui-stream-rows s) (ui-stream-words s)
                       (modulo newest (ui-stream-rows s)) count
                       (exact (round (* scale pw))) (exact (round (* scale ph)))
                       top
                       (inexact (* scale bw)) (if (>= bw 3) (inexact scale) 0.0)
                       (length strips)
                       (exact (round (* scale lane-h)))
                       (exact (round (* scale lane-gap)))
                       (exact (round (* scale (ui-stream-room strips)))))))
      (when over (over areas count))
      (ui-draw-bar-chart-rules x (list (cons 'plot (cdr (assq 'bars areas))))
                               top rules)
      (fold-left (lambda (ly strip)
                   (when (car strip)
                     (draw-text (+ x 6) (ui-text-y ly 'ui-small) (car strip)
                                'text-faint 'ui-small))
                   (+ ly lane-h))
                 py strips)))

  ;; stack: from the bottom up, (column . color), with the color #f for a
  ;; clear entry that lifts the rest; bar: a bar's least width. opts: 'tip
  ;; (seq), a moment's tooltip or #f; 'on-pick (seq), called on a left press
  ;; and as the press is dragged; 'marked, the moments marked; 'over, as the
  ;; part takes it; 'doc; 'strip-tips, a tooltip for each strip's label;
  ;; 'fit, true to show every moment from oldest to newest across the
  ;; width, ignoring bar, or 'whole to show as many as fit as bars of whole
  ;; pixels (ui-stream-layout). A bar under the pointer is marked too.
  ;; Returns the moment under the pointer, or #f.
  (define (ui-stream ui id s x y w h newest oldest top rules stack bar . opts)
    (let-values ([(count areas)
                  (ui-stream-layout s x y w h newest oldest rules bar
                                    (plist-ref opts 'fit #f))])
      (let* ([plot (cdr (assq 'plot areas))]
             [under (ui-bar-chart-under ui areas count)]
             [hover (and newest under (< under count)
                         (+ newest (- under count -1)))]
             [tip-of (plist-ref opts 'tip #f)]
             [on-pick (plist-ref opts 'on-pick #f)]
             [pick! (lambda (at)
                      (and on-pick newest (> count 0)
                           (begin
                             (on-pick (ui-stream-seq-at areas at newest count))
                             #t)))])
        (ui-region! ui (list id) (car plot) (cadr plot) (caddr plot)
                    (cadddr plot)
          'doc (plist-ref opts 'doc '((L . "Select")))
          'follow (and newest (> count 0)
                       (lambda (mx my)
                         (ui-stream-seq-at areas mx newest count)))
          'tip (and hover tip-of (tip-of hover))
          'on (lambda (ev)
                (case (car ev)
                  [(press) (and (eq? (list-ref ev 3) 'left) (pick! (cadr ev)))]
                  [(drag) (pick! (cadr ev))]
                  [else #f])))
        (let-values ([(lane-h lane-gap) (ui-stream-lane (ui-stream-strips s))])
          (for-each (lambda (tip i)
                      (ui-region! ui (list id 'strip i)
                                  x (+ (cadr plot) (* i lane-h))
                                  (- (car plot) x) lane-h 'tip tip))
                    (plist-ref opts 'strip-tips '())
                    (iota (length (plist-ref opts 'strip-tips '())))))
        (ui-draw-stream x y w h '() s areas count newest top rules stack
                        (append (if hover (list hover) '())
                                (plist-ref opts 'marked '()))
                        (plist-ref opts 'over #f))
        hover)))

  ;; Returns values, oldest first, as points ((x . y) ...) across x y w h,
  ;; scaled so that top reaches the box's top (1 pixel clear of the top and
  ;; of the bottom).
  (define (ui-chart-points x y w h values top)
    (let ([n (length values)])
      (map (lambda (v i)
             (cons (+ x (* w (/ i (max 1 (- n 1)))))
                   (- (+ y h) 1 (* (- h 2) (if (> top 0) (/ (min v top) top)
                                               0)))))
           values (iota n))))

  ;; values, oldest first, as a line scaled to their largest; with the flag
  ;; selected (its row is selected), in chart-share.
  (define-part (ui-draw-sparkline x y w h flags values)
    (when (> (length values) 1)
      (draw-polyline (ui-chart-points x y w h values (apply max 0 values))
                     (if (memq 'selected flags) 'chart-share 'text-dim) 1)))

  ;; series: ((color value ...) ...), each oldest first over one span and
  ;; scaled to its own largest value, drawn in a well.
  (define-part (ui-draw-line-chart x y w h flags series)
    (ui-draw-surface x y w h '(well))
    (for-each (lambda (s)
                (when (> (length (cdr s)) 1)
                  (draw-polyline (ui-chart-points (+ x 4) (+ y 4) (- w 8)
                                                  (- h 8)
                                                  (cdr s)
                                                  (apply max 0 (cdr s)))
                                 (car s) 1)))
              series))

  ;; A legend in a row: keys are ((color . label) ...), each drawn as a
  ;; swatch and its label, as many as fit in w.
  (define-part (ui-draw-legend x y w h flags keys)
    (let ([lh (font-line-height 'ui-small)] [end (+ x w)])
      (fold-left (lambda (lx k)
                   (let ([kw (ui-legend-key-width (cdr k))])
                     (if (> (+ lx kw) end)
                         lx
                         (begin
                           (fill-box lx (+ y (/ (- h lh) 2) 2) (- lh 4) (- lh 4)
                                     (car k))
                           (draw-text (+ lx lh)
                                      (ui-text-y (+ y (/ (- h lh) 2)) 'ui-small)
                                      (cdr k) 'text-dim 'ui-small)
                           (+ lx kw 12)))))
                 x keys)))

  (define (ui-legend-key-width label)
    (+ (font-line-height 'ui-small) 4 (text-width label 'ui-small)))

  ;; Returns (values w h) for all of its keys in a row.
  (define-part (ui-legend-size keys)
    (values (+ (apply + (map (lambda (k) (ui-legend-key-width (cdr k))) keys))
               (* 12 (max 0 (- (length keys) 1))))
            (font-line-height 'ui-small)))

  ;;; ------------------------------------------------------------------
  ;;; popups: what menus, toasts, dialogs, calendars, tooltips and the
  ;;; completion list share, so that a style restyles them all at once

  ;; A popup's box. Flags: menu (the desktop's menus and the completion
  ;; list: a soft edge), toast (a plain border and a smaller soft edge),
  ;; dialog (rounder), tooltip (the panels' color, no border); with none, it
  ;; is flat, as the calendar is.
  (define-part (ui-draw-panel x y w h flags)
    (let* ([on? (lambda (f) (memq f flags))]
           [r (cond [(on? 'dialog) 10] [(on? 'tooltip) 5] [else 8])]
           [edge (cond [(on? 'menu) 12] [(on? 'toast) 10] [else 0])])
      (draw-shadow x y w h r edge)
      (fill-box x y w h (if (on? 'tooltip) (alpha 'panel 0.96) 'bg-2) r)
      (unless (on? 'tooltip)
        (stroke-box x y w h
                    (if (on? 'toast)
                        'window-border
                        'window-border-focus)
                    1 r))))

  ;; The entry chosen in a menu or a list. With outline (a menu's
  ;; menu-hover), it is a 1-pixel box, and with pressed too, filled:
  ;; inverted. With hover, it marks an entry under the pointer that is not
  ;; chosen: filled (Settings' list), or, with popup (on a popup's panel), a
  ;; 1-pixel box, as a card or a field under the pointer has (the completion
  ;; list).
  (define-part (ui-draw-highlight x y w h flags)
    (cond [(memq 'hover flags)
           (if (memq 'popup flags)
               (stroke-box x y w h 'text-faint 1 5)
               (fill-box x y w h 'bg-2 5))]
          [(not (memq 'outline flags))
           (fill-box x y w h (alpha 'accent 0.22) 5)]
          [(memq 'pressed flags) (fill-box x y w h 'text)]
          [else (stroke-box x y w h 'text)]))

  ;; Draws the chosen entry or row again, after what is drawn on it:
  ;; nothing here, but a style that inverts what is chosen does it now
  ;; (Genera's inverse video: the text on it must turn too).
  (define-part (ui-draw-highlight-over x y w h flags) (void))

  ;; A line across the middle of the box, between a menu's groups.
  (define-part (ui-draw-separator x y w h flags)
    (let ([my (+ y (/ h 2))]) (draw-line x my (+ x w) my 'window-border)))

  ;; A card's corner radius, which an app fills or clips a card to.
  (define-part (ui-card-radius) 8)

  ;; A card's outline (a task, a style), drawn over what the app drew in
  ;; it. flags: selected (or floating, while dragged), hover.
  (define-part (ui-draw-card x y w h flags)
    (let ([selected? (memq 'selected flags)])
      (stroke-box x y w h
                  (cond [(or selected? (memq 'floating flags)) 'accent]
                        [(memq 'hover flags) 'text-faint]
                        [else 'window-border])
                  (if selected? 2 1) (ui-card-radius))))

  ;; A tooltip's lines: its text wrapped at 280, each of the text's own
  ;; lines (a newline ends one) starting a new one; at most 6, or as many as
  ;; the text has lines, if that is more.
  (define (ui-tooltip-lines text)
    (let ([n (fold-left (lambda (n c) (if (char=? c #\newline) (+ n 1) n))
                        1 (string->list text))])
      (let-values ([(lines cut?) (ui-wrap-lines text 280 'ui-small (max 6 n))])
        lines)))

  (define-part (ui-tooltip-size text)
    (let ([lines (ui-tooltip-lines text)])
      (values (+ 16 (min 280 (text-widest lines 'ui-small)))
              (+ 10 (* (length lines) (font-line-height 'ui-small))))))

  (define-part (ui-draw-tooltip x y w h flags text)
    (ui-draw-panel x y w h '(tooltip))
    (fold-left (lambda (ty line)
                 (draw-text (+ x 8) ty line 'panel-text 'ui-small)
                 (+ ty (font-line-height 'ui-small)))
               (+ y 5) (ui-tooltip-lines text)))

  ;;; ------------------------------------------------------------------
  ;;; dropdown, date field and calendar

  ;; choices: ((label . value) ...). A press opens the desktop's menu under
  ;; the dropdown, with the current choice selected. opts: 'label (shown
  ;; instead of the current choice's label), 'set (the choice matters: a
  ;; filter in use), 'tip.
  (define (ui-dropdown ui id x y w h choices current on-select . opts)
    (let ([i (list-index (lambda (c) (equal? (cdr c) current)) choices)]
          [open? (equal? (ui-menu-open-tag) (cons ui id))])
      (ui-pressable! ui id x y w h
        (lambda ()
          (ui-open-menu! ui x (+ y h)
            (map (lambda (c)
                   (cons (if (equal? (cdr c) current)
                             (string-append (car c) "  ✓")
                             (car c))
                         (lambda () (on-select (cdr c)))))
                 choices)
            'selected i 'tag (cons ui id) 'filter (> (length choices) 8)))
        '(#\space return down) opts '((L . "Choose")))
      (ui-draw-dropdown x y w h
                        (apply ui-flags ui id
                               (append (if open? '(open) '())
                                       (ui-opt-flags opts '(set label))))
                        (or (plist-ref opts 'label #f)
                            (if i (car (list-ref choices i)) "")))))

  ;; flags: open, set (an accent border and text), placeholder, label (it
  ;; shows its 'label, not a choice).
  (define-part (ui-draw-dropdown x y w h flags label)
    (let ([lh (font-line-height 'ui)] [hot? (memq 'hover flags)]
          [set? (memq 'set flags)] [s (+ (ui-glyph-size) 2)])
      (fill-box x y w h (if hot? 'bg-3 'bg-2) 6)
      (stroke-box x y w h
                  (if (or set? (memq 'open flags)) 'accent 'window-border) 1 6)
      (draw-text (+ x 10) (+ y (/ (- h lh) 2)) (text-fit label (- w 22 s) 'ui)
                 (cond [set? 'accent] [(memq 'placeholder flags) 'text-faint]
                       [hot? 'text] [else 'text-dim])
                 'ui)
      ;; The chevron, 6 from the text's room and 6 from the edge.
      (ui-draw-glyph (- (+ x w) 6 s) (+ y (/ (- h s) 2)) s s flags
                     'chevron-down)
      (when (memq 'focused flags) (ui-draw-focus x y w h flags 6))))

  ;; The text 10 in, then 6, the chevron and 6; at most 10 line heights
  ;; wide.
  (define-part (ui-dropdown-size labels)
    (values (min (* 10 (font-line-height 'ui))
                 (+ 24 (ui-glyph-size) (text-widest labels 'ui)))
            (ui-control-height)))

  ;; A date field: date is (year month day) or #f. A press, Space, Return or
  ;; Down opens a calendar under it; Delete and Backspace clear it. opts:
  ;; 'label (a procedure from the date to what is shown; ui-date-label by
  ;; default), 'placeholder, 'tip.
  (define (ui-date-field ui id x y w h date on-select . opts)
    (let* ([p (ui-state-popup ui)] [open? (and p (equal? (car p) id))]
           [open! (lambda ()
                    (ui-state-popup-set! ui (cons id (ui-date->day
                                                      (or date (ui-today))))))])
      (ui-region! ui id x y w h 'focus 'tab 'tip (plist-ref opts 'tip #f)
        'doc (plist-ref opts 'doc '((L . "Choose"))) 'on (lambda (ev)
              (case (car ev)
                [(press) (and (eq? (list-ref ev 3) 'left) (begin (open!) #t))]
                [(key)
                 (and (null? (caddr ev))
                      (cond [(memv (cadr ev) '(#\space return down)) (open!) #t]
                            [(memq (cadr ev) '(delete backspace))
                             (on-select #f) #t]
                            [else #f]))]
                [else #f])))
      (ui-draw-dropdown x y w h
                        (apply ui-flags ui id
                               (append (if open? '(open) '())
                                       (if date '() '(placeholder))))
                        (if date
                            ((plist-ref opts 'label ui-date-label) date)
                            (plist-ref opts 'placeholder "No date")))
      (when open?
        (ui-later! ui (lambda (ww wh)
                        (ui-calendar ui id x y h date on-select ww wh))))))

  ;; The calendar of the field id at (fx, fy), fh high, in a window ww × wh:
  ;; under the field, or above it when there is no room below, over a modal
  ;; region that closes it on a press outside.
  (define (ui-calendar ui id fx fy fh date on-select ww wh)
    (with-place 'dialog
      (lambda ()
        (let*-values ([(cw ch) (ui-calendar-size)]
                      [(x y) (ui-popup-place fx (+ fy fh 4) (- fy 4) cw ch ww
                                             wh)])
          (let* ([cursor (cdr (ui-state-popup ui))]
                 [close (lambda () (ui-state-popup-set! ui #f))]
                 [pick (lambda (n) (close) (on-select (ui-day->date n)))]
                 [move (lambda (n) (ui-state-popup-set! ui (cons id n)) #t)]
                 [today (ui-date->day (ui-today))]
                 [cd (ui-day->date cursor)]
                 [first (ui-date->day (list (car cd) (cadr cd) 1))]
                 [start (- first (ui-week-day first))]
                 [chosen (and date (ui-date->day date))]
                 [areas (ui-calendar-areas x y cw ch)]
                 [area (lambda (k) (cdr (assq k areas)))]
                 [button (lambda (k label thunk . opts)
                           (apply ui-button ui (list id k)
                                  (append (area k) (list label thunk 'quiet #t
                                                         'focus 'keep)
                                          opts)))])
            (ui-region! ui (list id 'calendar) 0 0 ww wh 'modal #t 'focus 'keep
              'on (ui-modal-on close
                    (lambda (key mods)
                      (case key
                        [(left) (move (- cursor 1))]
                        [(right) (move (+ cursor 1))]
                        [(up) (move (- cursor 7))]
                        [(down) (move (+ cursor 7))]
                        [(page-up) (move (ui-add-months cursor -1))]
                        [(page-down) (move (ui-add-months cursor 1))]
                        [(home) (move today)]
                        [(return) (pick cursor) #t]
                        [else #f]))))
            (ui-draw-calendar x y cw ch '()
                              (format "~a ~a" (vector-ref ui-month-titles
                                                          (- (cadr cd) 1))
                                      (car cd)))
            (button 'prev (and (theme 'calendar-step-words) "Previous")
                    (lambda () (move (ui-add-months cursor -1)))
                    'glyph 'chevron-left)
            (button 'next (and (theme 'calendar-step-words) "Next")
                    (lambda () (move (ui-add-months cursor 1)))
                    'glyph 'chevron-right)
            (let* ([g (area 'grid)] [gx (car g)] [gy (cadr g)] [cell (caddr g)])
              (do ([i 0 (+ i 1)]) ((= i 42))
                (let* ([n (+ start i)] [did (list id 'day n)]
                       [dx (+ gx (* cell (mod i 7)))]
                       [dy (+ gy (* cell (div i 7)))])
                  (ui-pressable! ui did dx dy cell cell (lambda () (pick n)) '()
                                 '(focus keep) '((L . "Choose")))
                  (ui-draw-day dx dy cell cell
                               (apply ui-flags ui did
                                      (append (if (= n today) '(today) '())
                                              (if (eqv? n chosen) '(selected)
                                                  '())
                                              (if (= n cursor) '(cursor) '())
                                              (if (= (cadr (ui-day->date n))
                                                     (cadr cd))
                                                  '()
                                                  '(outside))))
                               (number->string (caddr (ui-day->date n)))))))
            (button 'today "Today" (lambda () (pick today)))
            (button 'clear "Clear" (lambda () (close) (on-select #f))))))))

  (define (ui-calendar-cell) (max 28 (round (* (font-line-height 'ui) 1.9))))

  ;; Whether the month's steps show as the words Previous and Next, or as
  ;; glyphs (#f).
  (at-load
   (theme-default! 'calendar-step-words #f))

  (define-part (ui-calendar-size)
    (let* ([w (+ 20 (* 7 (ui-calendar-cell)))]
           [t (cdr (assq 'today (ui-calendar-areas 0 0 w 0)))])
      (values w (round (+ (cadr t) (cadddr t) 8)))))

  ;; ((prev x y w h) (next ..) (title ..) (week x y w h) (grid gx gy cell)
  ;; (today ..) (clear ..)); day i of the grid lies at gx + (i mod 7)·cell,
  ;; gy + (i div 7)·cell.
  (define-part (ui-calendar-areas x y w h)
    (let* ([cell (ui-calendar-cell)] [sh (font-line-height 'ui-small)]
           [b (ui-control-height)] [gy (+ y 4 b sh 6)]
           [fy (+ gy (* 6 cell) 8)])
      `((prev ,(+ x 8) ,(+ y 4) ,b ,b)
        (next ,(- (+ x w) 8 b) ,(+ y 4) ,b ,b)
        (title ,(+ x 8 b) ,(+ y 4) ,(- w 16 b b) ,b)
        (week ,(+ x 10) ,(+ y 4 b) ,(* 7 cell) ,(+ sh 6))
        (grid ,(+ x 10) ,gy ,cell)
        (today ,(+ x 8) ,fy ,(/ (- w 24) 2) ,b)
        (clear ,(+ x 16 (/ (- w 24) 2)) ,fy ,(/ (- w 24) 2) ,b))))

  ;; Draws the panel, its title and the weekday initials.
  (define-part (ui-draw-calendar x y w h flags title)
    (let* ([areas (ui-calendar-areas x y w h)]
           [t (cdr (assq 'title areas))] [wk (cdr (assq 'week areas))]
           [cell (/ (caddr wk) 7)])
      (ui-draw-panel x y w h '())
      (apply text-draw-centered (append t (list title 'text 'ui-bold)))
      (do ([i 0 (+ i 1)]) ((= i 7))
        (text-draw-centered (+ (car wk) (* i cell)) (cadr wk) cell (cadddr wk)
                            (string (string-ref "MTWTFSS" i)) 'text-faint
                            'ui-small))))

  ;; flags: hover, today (a ring), selected (filled), cursor (the keyboard's
  ;; day), outside (another month).
  (define-part (ui-draw-day x y w h flags label)
    (let* ([on? (lambda (f) (memq f flags))] [s (- (min w h) 4)]
           [cx (+ x (/ (- w s) 2))] [cy (+ y (/ (- h s) 2))])
      (cond [(on? 'selected) (fill-box cx cy s s 'accent 6)]
            [(on? 'hover) (fill-box cx cy s s 'bg-3 6)])
      (when (on? 'today)
        (stroke-box cx cy s s (if (on? 'selected) 'text 'accent) 1.5 6))
      (when (on? 'cursor)
        (stroke-box (- cx 1) (- cy 1) (+ s 2) (+ s 2) 'text 1 7))
      (text-draw-centered x y w h label
                          (cond [(on? 'selected) (color-readable-on 'accent)]
                                [(on? 'outside) 'text-faint]
                                [else 'text])
                          'ui)))

  ;;; ---------------------------------------------------------------- form
  ;;; Rows of labeled controls: each label goes in a column as wide as the
  ;;; longest label needs, with its control beside it, or on a line of its
  ;;; own above the control when less than the control's least width would
  ;;; be left beside it. A row may say under its control what it means (a
  ;;; hint), or span the whole width (with no label: a list of choices, a
  ;;; table). The app draws the controls; the form places them and their
  ;;; labels, and knows its height before it is drawn (ui-form-height), as a
  ;;; sheet must.

  ;; rows: each is (label h place opt ...): label a string, or #f to span
  ;; the width; h the control's height, or a (lambda (w) ...) that returns
  ;; it at width w; place a (lambda (x y w) ...) that draws the control
  ;; there. opts: 'hint, words under the control; 'tip, the label's tooltip;
  ;; 'min, the least width the control takes beside its label (120 by
  ;; default). A row may instead be (section title): a group's heading over
  ;; the rows after it. Returns the y below the form.
  (define (ui-form ui id x y w rows)
    (ui-form-walk rows x y w
      (lambda (row inline? lx ly lw lh cx cy cw ch hint hh)
        (let ([label (car row)] [opts (cdddr row)])
          (when label
            (ui-draw-label lx ly lw lh '(dim) label)
            (let ([tip (plist-ref opts 'tip #f)])
              (when tip (ui-region! ui (list id 'label label) lx ly lw lh
                                    'tip tip))))
          ((caddr row) cx cy cw)
          (when hint (ui-draw-label cx (+ cy ch 4) cw hh '(hint wrap) hint))))
      (lambda (title sx sy sw sh)
        (ui-draw-label sx sy sw sh '(section) title))))

  (define (ui-form-height rows w)
    (ui-form-walk rows 0 0 w (lambda a #f) (lambda a #f)))

  ;; Lays rows out from (x, y), w wide, calling (row! row inline? label-x y
  ;; w h control-x y w h hint hint-h) and (section! title x y w h). Returns
  ;; the y below them.
  (define (ui-form-walk rows x y w row! section!)
    (let* ([gap (ui-gap)] [lh (font-line-height 'ui)]
           [labels (filter string? (map car rows))]
           [lw (if (null? labels) 0 (+ (text-widest labels 'ui) gap gap))])
      (let loop ([rs rows] [y y] [first? #t])
        (cond
          [(null? rs) (if first? y (- y gap))]
          [(eq? (caar rs) 'section)
           (let*-values ([(top) (if first? y (+ y gap))]
                         [(sw sh) (ui-label-size '(section) (cadar rs) w)])
             (section! (cadar rs) x top w sh)
             (loop (cdr rs) (+ top sh 6) #f))]
          [else
           (let* ([row (car rs)] [label (car row)] [opts (cdddr row)]
                  [inline? (and label
                                (>= (- w lw) (plist-ref opts 'min 120)))]
                  [cx (if inline? (+ x lw) x)]
                  [cw (if inline? (- w lw) w)]
                  [ch (let ([h (cadr row)]) (if (procedure? h) (h cw) h))]
                  [cy (if (and label (not inline?)) (+ y lh 4) y)]
                  [hint (plist-ref opts 'hint #f)]
                  [hh (if hint
                          (let-values ([(hw hh) (ui-label-size '(hint wrap) hint
                                                               cw)])
                            hh)
                          0)])
             ;; the label beside the control's first line, or above it
             (row! row inline? x y (if inline? (- lw gap) w)
                   (if inline? (min ch (ui-control-height)) lh)
                   cx cy cw ch hint hh)
             (loop (cdr rs)
                   (+ (max (+ cy ch (if hint (+ 4 hh) 0)) (+ y lh)) gap)
                   #f))]))))

  ;;; ---------------------------------------------------------------- rows
  ;;; A boxed list: rows in one box, with a line between two rows. Each row
  ;;; has a title, maybe a subtitle under it, and what the app draws at its
  ;;; end (a switch, a button, a value) or before its title (a check box);
  ;;; over the box go a group's title and what the group is for. GNOME's
  ;;; preferences are made of these. The rows are the app's data, as a
  ;;; form's are, and the box knows its height before it is drawn
  ;;; (ui-rows-height).
  ;;;
  ;;;   (ui-rows ui 'net x y w
  ;;;     (list (ui-switch-row ui 'wifi "Wi-Fi" on? set-on! 'subtitle "On")
  ;;;           (list "Proxy" "Manual" 0 #f 'on-press open-proxy!))
  ;;;     'title "Network"
  ;;;     'add (list "Add Network" add-network!))

  ;; rows: each is (title subtitle suffix-w suffix opt ...): title a string,
  ;; subtitle a string or #f, and suffix #f or a (lambda (x y w h) ...) that
  ;; draws what ends the row, in a place suffix-w wide. opts: 'on-press, a
  ;; thunk that a press, Space or Return on the row calls (the row then
  ;; shows the pointer on it); 'prefix-width and 'prefix, a place before the
  ;; title and what draws in it; 'body, a (lambda (x y w h) ...) that draws
  ;; the title's place itself (an entry row's field); 'key, what names the
  ;; row and its widgets, (id key) (by default its index); 'height; 'tip;
  ;; 'disabled; 'selected. ui-rows' own opts: 'title and 'description, a
  ;; heading over the box; 'add, (label thunk), a last row that adds one, as
  ;; the style makes it (ui-draw-add-row): a press, Space or Return on it
  ;; calls thunk, and its id is (id add). Returns the y below the box.
  (define (ui-rows ui id x y w rows . opts)
    (let* ([top (ui-rows-heading x y w (plist-ref opts 'title #f)
                                 (plist-ref opts 'description #f) #t)]
           [add (plist-ref opts 'add #f)]
           [hs (map ui-row-spec-height rows)]
           [rh (apply + hs)]
           [h (+ rh (if add (ui-add-row-height) 0))])
      (unless (and (null? rows) (not add))
        (ui-draw-rows x top w h '())
        ;; The rows are cut to the box's corners, then its edge is drawn
        ;; over them.
        (with-clip (x top w h (ui-rows-radius))
          (let loop ([rs rows] [hs hs] [ry top] [i 0])
            (unless (null? rs)
              (ui-row ui (list id (plist-ref (cddddr (car rs)) 'key i))
                      x ry w (car hs) (car rs) (= i 0)
                      (and (null? (cdr rs)) (not add)))
              (loop (cdr rs) (cdr hs) (+ ry (car hs)) (+ i 1))))
          (when add
            (ui-add-row ui (list id 'add) x (+ top rh) w (- h rh) (car add)
                        (cadr add) (null? rows))))
        (ui-draw-rows x top w h '(over)))
      (+ top h)))

  ;; Returns the height ui-rows takes at width w, with opts as ui-rows takes
  ;; them.
  (define (ui-rows-height w rows . opts)
    (+ (ui-rows-heading 0 0 w (plist-ref opts 'title #f)
                        (plist-ref opts 'description #f) #f)
       (apply + (map ui-row-spec-height rows))
       (if (plist-ref opts 'add #f) (ui-add-row-height) 0)))

  ;; The row that ends a box of rows and adds one, with rid its id: label,
  ;; and thunk, which a press, Space or Return on it calls.
  (define (ui-add-row ui rid x y w h label thunk first?)
    (ui-pressable! ui rid x y w h thunk '(#\space return) '() '((L . "Add")))
    (ui-draw-add-row x y w h
                     (apply ui-flags ui rid
                            (append (if first? '(first) '())
                                    '(last activatable)))
                     label))

  ;; Returns a row's height: its own 'height, or as tall as its title and
  ;; subtitle need.
  (define (ui-row-spec-height row)
    (or (plist-ref (cddddr row) 'height #f)
        (ui-row-height (car row) (cadr row))))

  ;; The heading over a box of rows, from y and w wide, drawn when draw?:
  ;; its title and its description, each if given. Returns the y the box
  ;; starts at.
  (define (ui-rows-heading x y w title description draw?)
    (if (not (or title description))
        y
        (let*-values ([(gap below) (ui-rows-spacing)]
                      [(tw th) (if title
                                   (ui-label-size '(group) title w)
                                   (values 0 0))]
                      [(dy) (if (and title description)
                                (+ y th gap)
                                (+ y th))]
                      [(dw dh) (if description
                                   (ui-label-size '(dim wrap) description w)
                                   (values 0 0))])
          (when draw?
            (when title (ui-draw-label x y w th '(group) title))
            (when description
              (ui-draw-label x dy w dh '(dim wrap) description)))
          (+ dy dh below))))

  ;; A row of ui-rows at x y w h, with rid its id: its region, its look,
  ;; then what it holds.
  (define (ui-row ui rid x y w h row first? last?)
    (let* ([title (car row)] [subtitle (cadr row)]
           [suffix (cadddr row)] [sw (if suffix (or (caddr row) 0) 0)]
           [opts (cddddr row)]
           [on-press (plist-ref opts 'on-press #f)]
           [prefix (plist-ref opts 'prefix #f)]
           [body (plist-ref opts 'body #f)]
           [areas (ui-row-areas x y w h
                                (if prefix (plist-ref opts 'prefix-width 0) 0)
                                sw)]
           [t (cdr (assq 'title areas))])
      (if on-press
          (ui-pressable! ui rid x y w h on-press '(#\space return) opts
                         '((L . "Choose")))
          (ui-region! ui rid x y w h 'tip (plist-ref opts 'tip #f)))
      (ui-draw-row x y w h
                   (apply ui-flags ui rid
                          (append (if first? '(first) '())
                                  (if last? '(last) '())
                                  (if on-press '(activatable) '())
                                  (ui-opt-flags opts '(disabled selected))))
                   (and (not body) title) (and (not body) subtitle)
                   (car t) (caddr t))
      (when prefix (apply prefix (cdr (assq 'prefix areas))))
      (when body (apply body t))
      (when suffix (apply suffix (cdr (assq 'suffix areas))))))

  ;; A row whose switch says whether something is on (a switch row): a
  ;; press anywhere on the row switches it. opts: 'subtitle, and a row's.
  ;; Returns a row for ui-rows.
  (define (ui-switch-row ui id title on? on-change . opts)
    (let-values ([(tw th) (ui-toggle-track)])
      (cons* title (plist-ref opts 'subtitle #f) tw
             (lambda (x y w h)
               (ui-toggle ui (list id 'switch) x y w h #f on? on-change
                          'focus 'keep))
             'on-press (lambda () (on-change (not on?)))
             'key id
             opts)))

  ;; A row with a check box before its title (a check row): a press
  ;; anywhere on the row checks it or clears it. opts: 'subtitle, and a
  ;; row's. Returns a row for ui-rows.
  (define (ui-check-row ui id title checked? on-change . opts)
    (cons* title (plist-ref opts 'subtitle #f) 0 #f
           'prefix-width (ui-checkbox-box)
           'prefix (lambda (x y w h)
                     (ui-checkbox ui (list id 'check) x y w h #f checked?
                                  on-change 'focus 'keep))
           'on-press (lambda () (on-change (not checked?)))
           'key id
           opts))

  ;; A row that is a text field (an entry row): its title sits in the text's
  ;; place while the field is empty and does not have the keyboard, and
  ;; small over the text otherwise; a pencil at its end, while it does not
  ;; have the keyboard, says that it can be changed. id is the field's.
  ;; opts: the field's (except 'placeholder), and a row's. Returns a row for
  ;; ui-rows.
  (define (ui-entry-row ui id title text on-change . opts)
    (cons* title #f 0 #f
           'key id
           'body
           (lambda (x y w h)
             (let* ([lh (font-line-height 'ui)]
                    [sh (font-line-height 'ui-small)]
                    [g (ui-glyph-size)]
                    [focused? (equal? (ui-focused ui) id)]
                    [up? (or focused? (not (string=? text "")))]
                    [ty (+ y (/ (- h sh 2 lh) 2))]
                    [in (ui-text-box-inset '(field inner))]
                    [fw (if focused? w (- w g (ui-gap)))])
               ;; a press on the title gives the field the keyboard
               (ui-pressable! ui (list id 'title) x y w h
                              (lambda () (ui-focus! ui id)) '() '(focus keep))
               (if up?
                   (ui-draw-label x ty fw sh '(hint) title)
                   (ui-draw-label x y fw h '(dim) title))
               (unless focused?
                 (ui-draw-glyph (- (+ x w) g) (+ y (/ (- h g) 2)) g g
                                '(hover) 'edit))
               (apply ui-text-field ui id (- x in)
                      (if up? (- (+ ty sh 2) 4) y) (+ fw in)
                      (if up? (+ lh 8) h) text on-change 'inner #t
                      (plist-remove opts 'placeholder))))
           opts))

  ;; How far a heading's description is under its title, and how far the
  ;; box is under the heading.
  (define-part (ui-rows-spacing) (values 4 (ui-gap)))

  ;; A row's height for its title and subtitle (#f: none).
  (define-part (ui-row-height title subtitle)
    (max (+ (ui-control-height) 8)
         (round (+ 12 (font-line-height 'ui)
                   (if subtitle (+ 2 (font-line-height 'ui-small)) 0)))))

  ;; Where a row x y w h puts what it holds: ((prefix x y w h) (title ..)
  ;; (suffix ..)), with the prefix pw wide and the suffix sw wide (0: none),
  ;; the pad in from the box's sides, and a gap between them.
  (define-part (ui-row-areas x y w h pw sw)
    (let* ([m (ui-pad)] [g (ui-gap)]
           [tx (if (> pw 0) (+ x m pw g) (+ x m))]
           [sx (- (+ x w) m sw)]
           [te (if (> sw 0) (- sx g) (- (+ x w) m))])
      (list (list 'prefix (+ x m) y pw h)
            (list 'title tx y (max 0 (- te tx)) h)
            (list 'suffix sx y sw h))))

  ;; The height of the row that adds one.
  (define-part (ui-add-row-height) (ui-row-height "" #f))

  ;; The row that adds one: its flags are a row's, and a plus and its label
  ;; go where a row's title goes, in the accent.
  (define-part (ui-draw-add-row x y w h flags label)
    (let* ([t (cdr (assq 'title (ui-row-areas x y w h 0 0)))]
           [g (ui-glyph-size)] [lh (font-line-height 'ui)]
           [tx (car t)] [lx (+ tx g (ui-gap))])
      (ui-draw-row x y w h flags #f #f tx (caddr t))
      (ui-draw-glyph tx (+ y (/ (- h g) 2)) g g '((ink . accent)) 'plus)
      (draw-text lx (ui-text-y (+ y (/ (- h lh) 2)) 'ui)
                 (text-fit label (max 0 (- (+ tx (caddr t)) lx)) 'ui)
                 (if (memq 'disabled flags) (alpha 'accent 0.5) 'accent)
                 'ui)))

  ;; The corner radius of the box of rows.
  (define-part (ui-rows-radius) 8)

  ;; The box of rows: its fill under them (flags ()), and its edge over them
  ;; (over).
  (define-part (ui-draw-rows x y w h flags)
    (if (memq 'over flags)
        (stroke-box x y w h 'window-border 1 (ui-rows-radius))
        (fill-box x y w h 'bg-0 (ui-rows-radius))))

  ;; A row. flags: first, last (no line under it), activatable (a press
  ;; acts, so it shows the pointer), hover, pressed, focused, selected,
  ;; disabled. Its title and subtitle (each #f for none) go in tx..tx+tw.
  (define-part (ui-draw-row x y w h flags title subtitle tx tw)
    (let* ([on? (lambda (f) (memq f flags))]
           [lh (font-line-height 'ui)] [sh (font-line-height 'ui-small)]
           [th (if subtitle (+ lh 2 sh) lh)] [ty (+ y (/ (- h th) 2))]
           [ink (lambda (c) (if (on? 'disabled) (alpha c 0.5) c))])
      (cond [(on? 'selected) (fill-box x y w h 'selection)]
            [(and (on? 'activatable) (on? 'pressed)) (fill-box x y w h 'bg-3)]
            [(and (on? 'activatable) (on? 'hover)) (fill-box x y w h 'bg-2)])
      (unless (on? 'last)
        (fill-box x (+ y h -1) w 1 'window-border))
      (when title
        (draw-text tx ty (text-fit title tw 'ui) (ink 'text) 'ui))
      (when subtitle
        (draw-text tx (+ ty lh 2) (text-fit subtitle tw 'ui-small)
                   (ink 'text-dim) 'ui-small))
      (when (on? 'focused)
        (ui-draw-focus (+ x 3) (+ y 3) (- w 6) (- h 6) flags 4))))

  ;;; ---------------------------------------------------------- status page

  ;; What a view shows when it has nothing to show (an empty list, no
  ;; results), centered in x y w h: a large glyph, a title, what to do, and
  ;; maybe a button that does it. glyph: a name ui-draw-glyph knows, or a
  ;; (lambda (x y s flags) ...) that draws one s square; description: words
  ;; or #f. opts: 'compact (smaller, for a narrow pane), 'button (label
  ;; thunk), a pill under the words.
  (define (ui-status-page ui id x y w h glyph title description . opts)
    (let ([b (plist-ref opts 'button #f)]
          [flags (ui-opt-flags opts '(compact))])
      (ui-region! ui id x y w h)
      (ui-draw-status-page x y w h flags glyph title description
                           (and b (car b)))
      (when b
        (apply ui-button ui (list id 'button)
               (append (cdr (assq 'button
                                  (ui-status-page-areas x y w h flags title
                                                        description (car b))))
                       (list (car b) (cadr b) 'pill #t 'primary #t))))))

  ;; The font of a status page's title.
  (at-load
   (theme-default! 'status-title-font 'heading))

  ;; A status page's pieces in x y w h, as ((glyph x y s s) (title x y w h)
  ;; (description ..) (button ..)), with the block centered: the glyph over
  ;; the title, the description wrapped under it, and the button (when there
  ;; is a label) under that.
  (define-part (ui-status-page-areas x y w h flags title description label)
    (let*-values ([(s) (if (memq 'compact flags) 48 64)]
                  [(g) (ui-gap)]
                  [(tw) (max 0 (- w (* 2 (ui-pad))))]
                  [(tf) (theme 'status-title-font)]
                  [(th) (* (font-line-height tf)
                           (length (ui-label-lines title tw tf)))]
                  [(dh) (if description
                            (* (font-line-height 'ui)
                               (length (ui-label-lines description tw 'ui)))
                            0)]
                  [(bw bh) (if label (ui-button-size label #f) (values 0 0))]
                  [(bw) (if label (+ bw (* 2 (ui-pad))) 0)]
                  [(top) (+ y (max 0 (/ (- h (+ s g g th
                                                (if description (+ g dh) 0)
                                                (if label (+ g g bh) 0)))
                                        2)))]
                  [(ty) (+ top s g g)]
                  [(dy) (+ ty th g)]
                  [(by) (+ (if description (+ dy dh) (+ ty th)) g g)]
                  [(tx) (+ x (/ (- w tw) 2))])
      (list (list 'glyph (+ x (/ (- w s) 2)) top s s)
            (list 'title tx ty tw th)
            (list 'description tx dy tw dh)
            (list 'button (+ x (/ (- w bw) 2)) by bw bh))))

  ;; Draws text wrapped at w, each line centered in x..x+w, from y down.
  (define (ui-draw-centered-lines x y w text color font)
    (fold-left (lambda (ly line)
                 (draw-text (+ x (/ (- w (text-width line font)) 2))
                            (ui-text-y ly font) line color font)
                 (+ ly (font-line-height font)))
               y (ui-label-lines text w font)))

  ;; The glyph, faint, and the words, centered. label is the button's, whose
  ;; place the areas keep (the button draws itself).
  (define-part (ui-draw-status-page x y w h flags glyph title description
                                    label)
    (let* ([areas (ui-status-page-areas x y w h flags title description
                                        label)]
           [g (cdr (assq 'glyph areas))] [t (cdr (assq 'title areas))]
           [d (cdr (assq 'description areas))]
           [s (caddr g)] [tf (theme 'status-title-font)])
      (if (procedure? glyph)
          (glyph (car g) (cadr g) s '(dim))
          (ui-draw-glyph (car g) (cadr g) s s '((ink . text-faint)) glyph))
      (ui-draw-centered-lines (car t) (cadr t) (caddr t) title 'text tf)
      (when description
        (ui-draw-centered-lines (car d) (cadr d) (caddr d) description
                                'text-dim 'ui))))

  ;;; ---------------------------------------------------------------- banner

  ;; A strip across the top of a view that says something about it, with an
  ;; action at its end (a banner): title, and label and on-press for the
  ;; button (label #f for none). Returns its height.
  (define (ui-banner ui id x y w title label on-press)
    (let* ([h (ui-banner-height)]
           [b (assq 'button (ui-banner-areas x y w h title label))])
      (ui-region! ui id x y w h)
      (ui-draw-banner x y w h '() title label)
      (when label
        (apply ui-button ui (list id 'button)
               (append (cdr b) (list label on-press))))
      h))

  (define-part (ui-banner-height) (+ (ui-control-height) 12))

  ;; ((title x y w h) (button x y w h)): the button at the end (none without
  ;; a label), and the title centered in the strip where it fits, else at
  ;; the left of the room the button leaves.
  (define-part (ui-banner-areas x y w h title label)
    (let*-values ([(m) 6]
                  [(bw bh) (if label (ui-button-size label #f) (values 0 0))]
                  [(room) (- w m m (if label (+ bw m) 0))]
                  [(tw) (max 0 (min room (text-width title 'ui-bold)))]
                  [(tx) (max (+ x m) (+ x (/ (- w tw) 2)))]
                  [(tx) (if (> (+ tx tw) (+ x m room)) (+ x m) tx)])
      (list (list 'title tx y tw h)
            (list 'button (- (+ x w) m bw) (+ y (/ (- h bh) 2)) bw bh))))

  ;; The strip, with its title in its place; label is the button's.
  (define-part (ui-draw-banner x y w h flags title label)
    (let ([t (cdr (assq 'title (ui-banner-areas x y w h title label)))])
      (fill-box x y w h (alpha 'accent 0.15))
      (draw-text (car t) (+ y (/ (- h (font-line-height 'ui-bold)) 2))
                 (text-fit title (caddr t) 'ui-bold) 'text 'ui-bold)))

  ;;; ---------------------------------------------------------------- dialog

  ;; A modal dialog over the window, drawn at ui-end!. buttons: ((label
  ;; thunk flag ...) ...), right-aligned; the last is the default (Return),
  ;; unless it is disabled. Escape and a press outside call on-dismiss, and
  ;; so does a press on a dismiss area, where a style's areas have one
  ;; (Cons's nil). The dialog's flags carry its buttons' labels, (labels .
  ;; list), and the dismiss area's state, for a style whose dialog draws
  ;; around them.
  (define (ui-dialog ui id title message buttons on-dismiss)
    (ui-dialog-box ui id title message buttons on-dismiss #f))

  ;; Whether widget id f is under id: (id ...), or under one of those.
  (define (ui-under? f id)
    (and (pair? f) (or (equal? (car f) id) (ui-under? (car f) id))))

  ;; A sheet: a dialog whose body the app draws where a dialog's message
  ;; goes, between its title and its buttons: (body x y w), bw wide (or
  ;; wider, for the title and buttons) and bh high (a form's, say:
  ;; ui-form-height). The body's widgets take ids under id, (id ...) or
  ;; under those, and a widget elsewhere that has the keyboard loses it.
  (define (ui-sheet ui id title bw bh body buttons on-dismiss)
    (ui-dialog-box ui id title "" buttons on-dismiss (list bw bh body)))

  (define (ui-dialog-box ui id title message buttons on-dismiss sheet)
    (ui-later! ui
      (lambda (w h)
        (with-place 'dialog
          (lambda ()
            (let*-values ([(labels) (map car buttons)]
                          [(dw dh) (ui-dialog-size title message labels)]
                          ;; A sheet puts its body in the message's place,
                          ;; with the dialog's other parts around it as they
                          ;; are.
                          [(dw dh)
                           (if sheet
                               (let ([m (cdr (assq 'message
                                                   (ui-dialog-areas 0 0 dw dh
                                                                    labels)))])
                                 (values (max dw (+ (car sheet)
                                                    (- dw (caddr m))))
                                         (+ (cadr sheet) (- dh (cadddr m)))))
                               (values dw dh))]
                          [(dx dy) (values (max 0 (round (/ (- w dw) 2)))
                                           (max 0 (round (/ (- h dh) 2))))]
                          [(f) (ui-state-focus ui)]
                          [(areas) (ui-dialog-areas dx dy dw dh labels)]
                          [(dismiss) (assq 'dismiss areas)]
                          [(default) (car (last-pair buttons))])
              (unless (or (not f) (ui-under? f id))
                (ui-focus! ui #f)
                (invalidate! (current-window)))
              (ui-draw-scrim 0 0 w h '())
              (ui-region! ui id 0 0 w h 'modal #t 'focus 'keep
                'on (ui-modal-on on-dismiss
                      (lambda (key mods)
                        (and (eq? key 'return) (null? mods)
                             (not (memq 'disabled (cddr default)))
                             (begin ((cadr default)) #t)))))
              ;; The dialog's own panel takes a press that misses its
              ;; widgets, so that only a press outside it dismisses it.
              (ui-region! ui (list id 'inside) dx dy dw dh 'focus 'keep
                'on (lambda (ev) #t))
              (when dismiss
                (apply ui-pressable! ui (list id 'dismiss)
                       (append (cdr dismiss)
                               (list on-dismiss '() '(focus keep)
                                     '((L . "Cancel"))))))
              (ui-draw-dialog dx dy dw dh
                              (cons (cons 'labels labels)
                                    (ui-flags ui (list id 'dismiss)))
                              title message)
              (when sheet
                (let ([m (cdr (assq 'message areas))])
                  ((caddr sheet) (car m) (cadr m) (caddr m))))
              (for-each (lambda (b a i)
                          (apply ui-button ui (list id i)
                                 (append a (list (car b) (cadr b))
                                         (apply append
                                                (map (lambda (f) (list f #t))
                                                     (cddr b))))))
                        buttons
                        (map cdr (filter (lambda (a) (eq? (car a) 'button))
                                         areas))
                        (iota (length buttons)))))))))

  ;; Each button is at least 88 wide.
  (define (ui-dialog-button-widths labels)
    (map (lambda (l) (let-values ([(bw bh) (ui-button-size l #f)]) (max bw 88)))
         labels))

  ;; A dialog's message lines at width w: at most 6, so that a long message
  ;; keeps the dialog and its buttons small.
  (define (ui-dialog-lines message w)
    (let-values ([(lines cut?) (ui-wrap-lines message w 'ui 6)]) lines))

  ;; labels are the buttons' labels.
  (define-part (ui-dialog-size title message labels)
    (let* ([lh (font-line-height 'ui)]
           [bw (+ (apply + (ui-dialog-button-widths labels))
                  (* (ui-gap) (max 0 (- (length labels) 1))))]
           [w (clamp (+ 48 (max (text-width title 'heading)
                                (text-width message 'ui) bw))
                     360 (* 32 lh))])
      (values w
              (round (+ 24 (font-line-height 'heading) 8
                        (* lh (length (ui-dialog-lines message (- w 48))))
                        24 (ui-control-height) 20)))))

  ;; ((title x y w h) (message ..) (button x y w h) ...): one button per
  ;; label, right-aligned in the bottom row, a gap apart.
  (define-part (ui-dialog-areas x y w h labels)
    (let* ([hh (font-line-height 'heading)] [b (ui-control-height)]
           [gap (ui-gap)] [widths (ui-dialog-button-widths labels)]
           [by (- (+ y h) 20 b)])
      `((title ,(+ x 24) ,(+ y 24) ,(- w 48) ,hh)
        (message ,(+ x 24) ,(+ y 24 hh 8) ,(- w 48) ,(- h 24 hh 8 24 b 20))
        ,@(let loop ([ws widths]
                     [bx (- (+ x w -24) (apply + widths)
                            (* gap (max 0 (- (length widths) 1))))])
            (if (null? ws)
                '()
                (cons (list 'button bx by (car ws) b)
                      (loop (cdr ws) (+ bx (car ws) gap))))))))

  (define-part (ui-draw-scrim x y w h flags)
    (fill-box x y w h (alpha 'bg-0 0.55)))

  (define-part (ui-draw-dialog x y w h flags title message)
    (let* ([areas (ui-dialog-areas x y w h '())] [t (cdr (assq 'title areas))]
           [m (cdr (assq 'message areas))])
      (ui-draw-panel x y w h '(dialog))
      (draw-text (car t) (cadr t) (text-fit title (caddr t) 'heading) 'text
                 'heading)
      (fold-left (lambda (ly line) (draw-text (car m) ly line 'text-dim 'ui)
                   (+ ly (font-line-height 'ui)))
                 (cadr m) (ui-dialog-lines message (caddr m)))))

  ;;; ---------------------------------------------------------------- reload

  ;; At a reload, every window's regions come from its next draw (an older
  ;; kit's regions are records of another type).
  (at-load
   (for-each (lambda (win)
               (let ([ui (window-ref win 'ui #f)])
                 (when (ui-state? ui)
                   (ui-state-regions-set! ui '())
                   (ui-state-active-set! ui #f)
                   (ui-stale! ui))))
             (windows)))

  ;; A window opened under an older kit holds that kit's ui, a record this
  ;; code cannot read: its app opens again in its place, once the reload
  ;; has loaded the apps too. A window that no app opened (Tasks' editor)
  ;; closes.
  (at-load
   (for-each
    (lambda (win)
      (let ([ui (window-ref win 'ui #f)] [app (window-app win)])
        (when (and ui (not (ui-state? ui)) (not app))
          (close-window! win))
        (when (and ui (not (ui-state? ui)) app)
          (let-values ([(cx cy cw ch) (content-rect win)])
            (let ([x (window-x win)] [y (window-y win)])
              (close-window! win)
              (after 0
                (lambda ()
                  (let ([new (parameterize ([new-window-position (cons x y)])
                               (app-launch! app))])
                    (when (window? new) (resize-window! new cw ch))))))))))
    (windows))))
