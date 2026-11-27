;;; (schevana kits ui base) — a part of the ui kit ((schevana kits ui)),
;;; which gives its names: the kit's own workings: the state and regions,
;;; focus, time, events and a draw, menus and modal windows, sizes and
;;; layout, the shared drawing, labels and surfaces, scrolling, popups and
;;; tooltips.

(library (schevana kits ui base)
  (export
    ui-region-id ui-region-x ui-region-y ui-region-h ui-region-frame
    ui-state-mx ui-state-my ui-state-clip ui-state-clip-set! ui-state-focus
    ui-state-edit ui-state-edit-set! ui-state-blink-at-set! ui-state-reveal
    ui-state-reveal-set! ui-state-popup ui-state-popup-set! ui-state-scans
    ui-state-scans-set! ui-state-memo make-ui ui-memo ui-memo! ui-forget!
    ui-tip-ms ui-cut ui-region! ui-area ui-region-in? ui-region-at ui-find
    ui-hover? ui-active? ui-opt-flags ui-flags ui-focus! ui-focused ui-edit
    ui-caret ui-due! ui-frame ui-caret-on? ui-stale! ui-pointer ui-mouse-down
    ui-mouse-move ui-mouse-up ui-wheel ui-handlers ui-modal-on ui-pressable!
    ui-begin! ui-later! ui-disabled ui-end! ui-menu-open! ui-menu-open-tag
    ui-open-menu! ui-open-text-menu! ui-open-modal ui-control-height
    ui-glyph-size ui-small-glyph-size ui-gap ui-pad ui-popup-place ui-flow
    ui-toolbar ui-italic-of ui-draw-focus ui-draw-focus* ui-draw-field
    ui-draw-field* ui-fade ui-draw-glyph ui-draw-glyph* ui-frame-glyph
    ui-label-font ui-label-text ui-draw-label ui-draw-label* ui-label-size
    ui-label-size* ui-label-lines ui-wrap-lines ui-draw-surface
    ui-draw-surface* ui-surface-well-ring ui-text-y ui-text-y* ui-scroll
    ui-scroll-wide ui-scrollbar-shows? ui-scrollbar ui-scrollbar-across
    ui-reveal! ui-scrollbar-width ui-scrollbar-inset ui-frame-scrollbar
    ui-scroll-step ui-scrollbar-areas ui-scrollbar-areas* ui-draw-scrollbar
    ui-draw-scrollbar* ui-draw-panel ui-draw-panel* ui-draw-highlight
    ui-draw-highlight* ui-draw-highlight-over ui-draw-highlight-over*
    ui-draw-separator ui-draw-separator* ui-card-radius ui-card-radius*
    ui-draw-card ui-draw-card* ui-card-pad ui-card-pad* ui-panel-pad
    ui-panel-pad* ui-tooltip-lines ui-tooltip-size ui-tooltip-size*
    ui-draw-tooltip ui-draw-tooltip* ui-draw-scrim ui-draw-scrim*)
  (import (chezscheme)
          (only (schevana base) at-load clamp define-hook filter-map
                library-layer list-index plist-ref)
          (only (schevana core) *input-step?* *mouse-button* *mouse-mods*
                after alpha app clipboard-get clipboard-set! close-window!
                color-default! content-rect core0-set-cursor! current-window
                define-part draw-line draw-polyline draw-shadow draw-text
                fill-box fill-circle fill-polygon focus-window! focused-window
                font font-family font-line-height font-size font-weight
                frame-insets frame-regions gpu-list-new invalidate! maximized?
                new-window-position now-ms open-window pi plist-remove
                point-in? proc record-list! resize-window! stipple stroke-box
                stroke-circle text-width theme theme-default! theme-font-rule
                theme-rule window-app window-content-size window-frame-soon!
                window-handlers window-hover window-modal-child window-props
                window-ref window-set! window-x window-y window? windows
                with-clip with-place with-transpose)
          (only (schevana kits app) app-launch!)
          (only (schevana kits edit) edit-row-last edit-row edit-layout-count
                edit-layout-extend! edit-layout-of edit-wrap edit-layout-scan!
                edit-caret edit?)
          (only (schevana kits menu) menu-entry-action menu-entry-icon
                menu-entry-ready?)
          (only (schevana kits text) text-widest text-fit))

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
            doc          ; what the mouse buttons do on it: ((L . "Set") ...),
                         ; or (lambda (x y) ...), for where the pointer is
            follow))     ; #f, or (lambda (x y) ...): what it shows for the
                         ; pointer there; a move that changes that redraws

  (define-record-type ui-state
    (nongenerative schevana-ui-state-5)
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
            (mutable disabled) ; whether what is drawn now is disabled
                               ; (ui-disabled)
            memo))             ; per-id kit memory (scroll offsets, ...)

  (define (make-ui)
    (make-ui-state '() #f #f -1 -1 1 (list 0 -1 -1) #f #f #f 0 #f #f '() #f #f
                   #t '() #f (make-hashtable equal-hash equal?)))

  (define (ui-memo ui key default)
    (hashtable-ref (ui-state-memo ui) key default))
  (define (ui-memo! ui key value) (hashtable-set! (ui-state-memo ui) key value))

  ;; Forgets what the kit keeps for widget id (a scroll offset and a caret),
  ;; so that, given other data to show, the widget starts at its top again.
  (define (ui-forget! ui id)
    (hashtable-delete! (ui-state-memo ui) id)
    (hashtable-delete! (ui-state-memo ui) (list id 'caret)))

  ;; How long (ms) the pointer rests before a tooltip shows, and how long a
  ;; caret phase lasts (a style's setting: the CADR's blinkers flipped
  ;; faster).
  (define ui-tip-ms 600)
  (at-load
   (theme-default! 'text-blink-ms 530))
  (define (ui-blink-ms) (theme 'text-blink-ms))

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
  ;; Under ui-disabled a region takes no input and no keyboard: it keeps
  ;; its place and its tooltip, and a widget that had the keyboard or the
  ;; mouse lets go of it.
  (define (ui-region! ui id x y w h . opts)
    (let-values ([(cx cy cw ch) (ui-cut x y w h (ui-state-clip ui))])
      (let* ([off? (ui-state-disabled ui)]
             [r (make-ui-region id cx cy cw ch (list x y w h)
                                (and (not off?) (plist-ref opts 'on #f))
                                (if off? 'keep (plist-ref opts 'focus #f))
                                (plist-ref opts 'tip #f)
                                (plist-ref opts 'cursor #f)
                                (plist-ref opts 'modal #f)
                                (if off? '() (plist-ref opts 'doc '()))
                                (and (not off?) (plist-ref opts 'follow #f)))])
        (when off?
          (when (equal? (ui-state-focus ui) id)
            (ui-state-focus-set! ui #f)
            (ui-state-edit-set! ui #f))
          (when (ui-active? ui id) (ui-state-active-set! ui #f)))
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
    (if (ui-state-disabled ui)
        (cons 'disabled own)
        (apply ui-live-flags ui id own)))

  (define (ui-live-flags ui id . own)
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
           [ms (ui-blink-ms)]
           [k (quotient (max 0 (- (now-ms) t0)) ms)])
      (ui-due! ui (+ t0 (* (+ k 1) ms)))
      (even? k)))

  ;; Starts the tooltip's wait at ms (+inf.0: not until the pointer moves),
  ;; for a pointer at (x, y), by default where it was.
  (define (ui-rest! ui ms . at)
    (ui-state-rest-set! ui (cons ms
                                 (if (pair? at) at (cdr (ui-state-rest ui))))))

  ;;; ---------------------------------------------------------------- events
  ;;; A region's on receives (press x y button clicks), (drag x y clicks),
  ;;; (release x y), (key key mods), (text str) and (wheel dy dx), and returns
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
           ;; where there is no region, the ui's own, if it has one
           [c (or (and r (ui-region-cursor r)) (ui-memo ui 'ui-cursor 'arrow))])
      (and (not (equal? id (ui-state-hover-id ui)))
           (begin
             (ui-state-hover-id-set! ui id)
             (ui-doc! win r x y)
             (ui-rest! ui ms x y)
             (unless (eq? c (window-ref win 'cursor 'arrow))
               (window-set! win 'cursor c)
               (core0-set-cursor! c))
             (invalidate! win)
             #t))))

  ;; Returns the pointer's shape at (x, y) and what the mouse buttons do
  ;; there, as (cursor . doc), or #f where there is no region: for a window
  ;; whose own handlers set the pointer's shape (a REPL's, whose scroll bar
  ;; alone is the kit's).
  (define (ui-pointer ui x y)
    (let ([r (ui-region-at ui x y)])
      (and r (cons (or (ui-region-cursor r) 'arrow)
                   (ui-region-doc-at r x y)))))

  ;; Returns what the mouse buttons do at (x, y) of region r.
  (define (ui-region-doc-at r x y)
    (let ([d (ui-region-doc r)]) (if (procedure? d) (d x y) d)))

  ;; The mouse documentation of win, for the pointer at (x, y) over region
  ;; r, or over none (#f). The bar that shows it reads this; it needs no
  ;; redraw.
  (define (ui-doc! win r x y)
    (hashtable-set! (window-props win) 'mouse-doc
                    (if r (ui-region-doc-at r x y) '())))

  ;; A press. A left press focuses a region that takes typing (focus
  ;; click), leaves the focus as it is on Tab stops and keep regions, and
  ;; clears it elsewhere; a right press focuses only a region that takes
  ;; typing; then the region gets the press. While the left
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
        ;; a right press gives the keyboard only to what a click would (a
        ;; text box, whose text menu it opens), and leaves it elsewhere
        (when (and (eq? button 'right) r (eq? (ui-region-focus r) 'click))
          (ui-focus! ui (ui-region-id r)))
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
              ;; within one region, its documentation may differ by place
              (let ([r (ui-region-at ui x y)])
                (when (and r (procedure? (ui-region-doc r)))
                  (ui-doc! win r x y)))
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
  ;; first, as (wheel dy dx): dx where it turns sideways.
  (define (ui-wheel ui dy dx)
    (ui-rest! ui +inf.0)
    (let ([x (ui-state-mx ui)] [y (ui-state-my ui)])
      (and (exists (lambda (r)
                     (and (ui-region-on r) (ui-region-in? r x y)
                          ((ui-region-on r) (list 'wheel dy dx))))
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
              ;; a disabled one has no handler, and lets keys by
              [(and modal (ui-region-on modal))
               ((ui-region-on modal) (list 'key key mods))
               #t]
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
            'wheel (lambda (win dx dy) (ui-fresh! ui) (ui-wheel ui dy dx))
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
    (ui-state-disabled-set! ui #f)
    (ui-state-fresh?-set! ui #t))

  ;; Adds an overlay: proc, (lambda (w h) ...), which ui-end! draws above
  ;; everything.
  (define (ui-later! ui proc)
    (ui-state-later-set! ui (cons (if (ui-state-disabled ui)
                                      (lambda (w h)
                                        (ui-disabled ui (lambda () (proc w h))))
                                      proc)
                                  (ui-state-later ui))))

  ;; Draws what thunk draws disabled: every control in it shows so and
  ;; takes no input (Tab passes it by, a focused field lets go of the
  ;; keyboard, a held slider of the mouse), and what it opens over the rest
  ;; (a dialog, a calendar) is disabled too. Returns what thunk returns.
  (define (ui-disabled ui thunk)
    (let ([was (ui-state-disabled ui)])
      (dynamic-wind
        (lambda () (ui-state-disabled-set! ui #t))
        thunk
        (lambda () (ui-state-disabled-set! ui was)))))

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
  ;; the ui stale (ui may be #f, for an app that draws without the kit);
  ;; once the window is closed, an entry does nothing. An entry that can't
  ;; be chosen now (its thunk #f) stays so. With 'filter, entries may be
  ;; (lambda (filter) entries), the menu's own filtering.
  (define (ui-open-menu! ui x y entries . opts)
    (let ([win (current-window)])
      (define (wrap es)
        (map (lambda (e)
               (if (menu-entry-ready? e)
                   (let ([run (lambda ()
                                (when (memq win (windows))
                                  (parameterize ([current-window win])
                                    ((menu-entry-action e)))
                                  (when ui (ui-stale! ui))
                                  (invalidate! win)))]
                         [icon (menu-entry-icon e)])
                     (if icon (list (car e) run icon) (cons (car e) run)))
                   e))
             es))
      (let-values ([(cx cy cw ch) (content-rect win)])
        (apply ui-menu-open! (+ cx x) (+ cy y)
               (if (procedure? entries)
                   (lambda (f) (wrap (entries f)))
                   (wrap entries))
               opts))))

  ;; Opens the menu that a right press opens on text, at (x, y) of the
  ;; current window's content: Copy where the text can be selected, and
  ;; Paste where it can be typed in. copy is the text selected ("" for none,
  ;; when Copy shows but can't be chosen), or #f where nothing can be
  ;; selected; paste is a procedure that takes the clipboard's text, or #f
  ;; where nothing can be typed (with the clipboard empty, Paste can't be
  ;; chosen). opts: 'copy-key and 'paste-key, the keys shown beside them
  ;; (Ctrl+C and Ctrl+V; a REPL's Ctrl+C stops what runs).
  (define (ui-open-text-menu! ui x y copy paste . opts)
    (let ([clip (if paste (clipboard-get) "")])
      (ui-open-menu!
       ui x y
       (append
        (if copy
            (list (cons (string-append "Copy\t"
                                       (plist-ref opts 'copy-key "Ctrl+C"))
                        (and (not (string=? copy ""))
                             (lambda () (clipboard-set! copy)))))
            '())
        (if paste
            (list (cons (string-append "Paste\t"
                                       (plist-ref opts 'paste-key "Ctrl+V"))
                        (and (not (string=? clip ""))
                             (lambda () (paste (clipboard-get))))))
            '()))
       'tag 'text)))

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
  ;; an accent border while it has the keyboard, and the window's own shade
  ;; when disabled.
  (define-part (ui-draw-field x y w h flags)
    (fill-box x y w h (if (memq 'disabled flags) 'bg-1 'bg-0) 6)
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
  ;; How a disabled mark (a glyph, a radio's ring) fades: a number, the
  ;; share of its ink it keeps, or, on a screen one bit deep, the rows of
  ;; a stipple it is drawn through (Genera's and the CADR's 50 % gray), so
  ;; that no pixel is gray.
  (at-load
   (theme-default! 'disabled-fade 0.5))

  ;; Text that can't be used now: faint, unless a style says otherwise (the
  ;; CADR's gray, where its faint text is as black as the rest).
  (at-load
   (color-default! 'text-disabled 'text-faint))

  ;; Returns color as a disabled mark draws it (disabled-fade).
  (define (ui-fade color)
    (let ([f (theme 'disabled-fade)])
      (if (number? f) (alpha color f) (apply stipple color #f f))))

  (define-part (ui-draw-glyph x y w h flags name)
    (let* ([s (min w h)] [ox (+ x (/ (- w s) 2))] [oy (+ y (/ (- h s) 2))]
           [p (lambda (fx fy) (cons (+ ox (* fx s)) (+ oy (* fy s))))]
           [given (lambda (key)
                    (let ([f (find (lambda (f)
                                     (and (pair? f) (eq? (car f) key)))
                                   flags)])
                      (and f (cdr f))))]
           [ink (cond [(given 'ink)]
                      [(memq 'primary flags) 'accent-ink]
                      [(and (memq 'danger flags) (memq 'hover flags)) 'red]
                      [(memq 'hover flags) 'text]
                      [(memq 'quiet flags) 'text-faint]
                      [else 'text-dim])]
           [ink (if (memq 'disabled flags) (ui-fade ink) ink)]
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

  ;;; ------------------------------------------------------------------
  ;;; labels and surfaces: an app's text and strips, so it never names a
  ;;; font, a color or a fill

  ;; A section label's font, and whether it is in capitals (Genera heads a
  ;; pane in bold italic instead). A group's heading, over a block of rows
  ;; (a table, a grid), is at the rows' size, so that it stands over them
  ;; rather than under them.
  (at-load
   (theme-default! 'label-section-font 'ui-small))
  ;; how much a surface takes on a hue it stands for (a REPL's, by its
  ;; kind): none on a screen one bit deep
  (at-load
   (theme-default! 'surface-tint 0.06))
  ;; the font of a label's hint (the CADR's small italic, TR10I)
  (at-load
   (theme-default! 'label-hint-font 'ui-small))
  (at-load
   (theme-default! 'label-section-upcase #t))
  (at-load
   (theme-default! 'label-group-font 'ui-bold))

  (define (ui-label-font flags)
    (cond [(memq 'heading flags) 'heading]
          [(memq 'section flags) (theme 'label-section-font)]
          [(memq 'group flags) (theme 'label-group-font)]
          [(memq 'hint flags) (theme 'label-hint-font)]
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
           [color (cond [(memq 'disabled flags) 'text-disabled]
                        [(memq 'error flags) 'red]
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
    (ui-scroll-view ui id x y w h body #f))

  ;; A scroll view whose content may be wider than it, too: body is (lambda
  ;; (left top) ...), and returns where the content ends as (values right
  ;; bottom). A bar across the view's bottom scrolls it sideways (the
  ;; style's own bar, transposed), as does the wheel turned sideways; where
  ;; both bars show, the one at the side stops short of the one across.
  (define (ui-scroll-wide ui id x y w h body)
    (ui-scroll-view ui id x y w h body #t))

  (define (ui-scroll-view ui id x y w h body wide?)
    (let* ([xid (and wide? (list id 'across))]
           [off (car (ui-memo ui id '(0 . 0)))]
           [offx (if wide? (car (ui-memo ui xid '(0 . 0))) 0)]
           [clip (ui-state-clip ui)]
           ;; in the margin (the CADR's), the bar is there to press
           ;; whenever its view scrolls, and shows under the pointer
           [always? (memq (theme 'scrollbar-show) '(always bar))]
           ;; How much of a wide view its bars take that are always there,
           ;; one at the left that content keeps clear of, and the one
           ;; across: no content shows under them, however far it is
           ;; scrolled. A draw goes by the last one's bars, and another
           ;; follows when they change.
           [left-of (lambda (most)
                      (if (and wide? (ui-scrollbar-shows? most)
                               (> (ui-scrollbar-inset 'left) 0))
                          (min w (ui-scrollbar-width))
                          0))]
           [below-of (lambda (mostx)
                       (if (and wide? always? (ui-scrollbar-shows? mostx))
                           (min h (ui-scrollbar-width))
                           0))]
           [left (left-of (cdr (ui-memo ui id '(0 . 0))))]
           [below (below-of (if wide? (cdr (ui-memo ui xid '(0 . 0))) 0))])
      (ui-region! ui id x y w h 'on
        (lambda (ev)
          (and (eq? (car ev) 'wheel)
               (let* ([m (ui-memo ui id '(0 . 0))]
                      [new (clamp (- (car m) (* (cadr ev) (ui-scroll-step)))
                                  0 (cdr m))])
                 (cond
                   [(not (= new (car m)))
                    (ui-memo! ui id (cons new (cdr m)))
                    #t]
                   [(and wide? (pair? (cddr ev)))
                    (let* ([m (ui-memo ui xid '(0 . 0))]
                           [new (clamp (+ (car m)
                                          (* (caddr ev) (ui-scroll-step)))
                                       0 (cdr m))])
                      (and (not (= new (car m)))
                           (begin (ui-memo! ui xid (cons new (cdr m))) #t)))]
                   [else #f])))))
      (let ([before (ui-state-regions ui)])
        (ui-state-clip-set! ui (call-with-values
                                 (lambda ()
                                   (ui-cut (+ x left) y (- w left) (- h below)
                                           clip))
                                 list))
        (let* ([ends (with-clip ((+ x left) y (- w left) (- h below))
                       (if wide?
                           (call-with-values
                             (lambda () (body (- x offx) (- y off)))
                             cons)
                           (body (- y off))))]
               [bottom (if wide? (cdr ends) ends)]
               [wide (if wide? (- (car ends) (- x offx)) w)]
               [mostx (max 0 (- wide w))]
               [newx (if wide? (clamp (car (ui-memo ui xid '(0 . 0))) 0 mostx)
                         0)]
               ;; the last of the content scrolls up to the bar across
               [vh (- h (below-of mostx))]
               [content (- bottom (- y off))]
               [most (max 0 (- content vh))]
               [now (car (ui-memo ui id '(0 . 0)))]
               [new (clamp now 0 most)])
          (ui-state-clip-set! ui clip)
          (ui-memo! ui id (cons new most))
          (when wide? (ui-memo! ui xid (cons newx mostx)))
          (unless (and (= new off) (= newx offx)
                       (= left (left-of most)) (= (- h below) vh))
            (invalidate! (current-window)))
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
                                            (> (+ (cadddr f) (* 2 (ui-gap)))
                                               vh))
                                       (cdr rv)
                                       (cons 0 (cadddr f)))])
                        (ui-state-reveal-set! ui #f)
                        (ui-reveal! ui id (- (+ top (car span)) (ui-gap))
                                    (+ top (cdr span) (ui-gap)) vh))
                      (loop (cdr rs)))))))
          (let* ([win (current-window)] [bid (list id 'bar)]
                 [side (theme 'scrollbar-side)]
                 [r (and win (eq? side 'outside) (zero? x)
                         (assq 'scrollbar (frame-regions win)))]
                 [out? (and r #t)]   ; the whole region its frame leaves
                 [bw (if out? (list-ref r 3) (ui-scrollbar-width))]
                 [hover (and win (window-hover win))]
                 [over? (and (eq? hover 'content) (ui-hover? ui x y w h))]
                 [xbid (and wide? (list id 'across 'bar))]
                 [across? (and wide? (ui-scrollbar-shows? mostx)
                               (or always? over? (ui-active? ui xbid)))]
                 [aw (if across? (ui-scrollbar-width) 0)])
            (when (and (ui-scrollbar-shows? most)
                       (or always?
                           (ui-active? ui bid)
                           (if out? (eq? hover 'scrollbar) over?)))
              ;; Outside, the bar takes the whole region (in the content's
              ;; coordinates).
              (let-values ([(bx by bh)
                            (if out?
                                (let-values ([(l t . rb) (frame-insets win)])
                                  (values (- (cadr r) l) (- (caddr r) t)
                                          (list-ref r 4)))
                                (values (if (eq? side 'left) x (- (+ x w) bw))
                                        y (- h aw)))])
                (ui-scrollbar ui bid bx by bw bh new content vh
                              (lambda (off) (ui-memo! ui id (cons off most))))
                (when out?   ; for the frame's over pass: ui-frame-scrollbar
                  (hashtable-set! (window-props win) 'scrollbar
                                  (let ([content (max content vh 1)])
                                    (list bx by bw bh (ui-flags ui bid)
                                          (/ new content) (/ vh content)))))))
            (when across?
              ;; it stops short of a bar at the side, inside the view
              (let ([side? (and (not out?) (ui-scrollbar-shows? most)
                                (or always? over? (ui-active? ui bid)))])
                (ui-scrollbar-across
                 ui xbid (if (and side? (eq? side 'left)) (+ x bw) x)
                 (- (+ y h) aw) (if side? (- w bw) w) aw newx wide w
                 (lambda (off) (ui-memo! ui xid (cons off mostx)))))))))))

  ;; Whether a bar shows over a view whose content goes on for most beyond
  ;; it: where it does, and, in a style whose bars are there whether they
  ;; are needed or not (scrollbar-full), where all of it fits.
  (define (ui-scrollbar-shows? most) (or (> most 0) (theme 'scrollbar-full)))

  ;; A scroll bar at x y w h for a view, view high, that shows content from
  ;; off on: a press on the thumb or beside it, and a drag, set the offset
  ;; by calling (set-off! off). The thumb travels along the style's track,
  ;; the whole bar unless its areas give one (Genera's, between its end
  ;; boxes). opts: 'flags, flags of its own that its drawing is handed;
  ;; 'noun, what the mouse documentation calls the content; and 'line, how
  ;; high a line of it is, by which the Lisp machines' buttons scroll.
  (define (ui-scrollbar ui id x y w h off content view set-off! . opts)
    (ui-scrollbar-of ui id x y w h off content view set-off! #f opts))

  ;; A scroll bar across, at x y w h, for a view view wide over content
  ;; that wide: the style's bar at the side, transposed, its areas and its
  ;; drawing with x and y traded (the flags then hold across).
  (define (ui-scrollbar-across ui id x y w h off content view set-off! . opts)
    (ui-scrollbar-of ui id x y w h off content view set-off! #t opts))

  ;; Returns the areas of a bar across at x y w h: the style's areas for a
  ;; bar at the side, transposed.
  (define (ui-scrollbar-areas-across x y w h start size)
    (map (lambda (a)
           (list (car a) (caddr a) (cadr a) (list-ref a 4) (cadddr a)))
         (ui-scrollbar-areas y x h w start size)))

  (define (ui-scrollbar-of ui id x y w h off content view set-off! across?
                           opts)
    (let* ([lispm? (eq? (theme 'scrollbar-input) 'lispm)]
           [lh (plist-ref opts 'line (theme 'scrollbar-line-height))]
           [content (max content view 1)]
           [most (- content view)]
           [start (/ off content)] [size (/ view content)]
           [areas (if across?
                      (ui-scrollbar-areas-across x y w h start size)
                      (ui-scrollbar-areas x y w h start size))]
           [thumb (cdr (assq 'thumb areas))]
           [track (assq 'track areas)]
           ;; along the bar: where the thumb starts and how long it is, and
           ;; the same of the track it travels
           [t0 (if across? (car thumb) (cadr thumb))]
           [tl (if across? (caddr thumb) (cadddr thumb))]
           [k0 (cond [(not track) (if across? x y)]
                     [across? (cadr track)]
                     [else (caddr track)])]
           [kl (cond [(not track) (if across? w h)]
                     [across? (cadddr track)]
                     [else (list-ref track 4)])]
           [at (lambda (px py) (if across? px py))]
           ;; where a Lisp machine's button scrolls to from base
           [to (lambda (p base button twice?)
                 (ui-lispm-scroll-offset areas across? (if across? x y)
                                         (if across? w h) k0 kl p base content
                                         view lh button twice?))]
           [shift? (lambda (button)
                     (and (eq? button 'left) (memq 'shift *mouse-mods*) #t))])
      (define (thumb-to! p)
        (set-off! (clamp (* most (/ (- p k0) (max 1 (- kl tl)))) 0 most))
        #t)
      (ui-region! ui id x y w h 'focus 'keep
        ;; the Lisp machines' pointer turns into a double-headed arrow over
        ;; the bar (UG p.2742; mouse.lisp:1032-1037)
        'cursor (and lispm? (if across? 'resize-ew 'resize-ns))
        'doc (if lispm?
                 (lambda (px py)
                   (ui-lispm-scroll-doc areas across? k0 kl (at px py)
                                        (plist-ref opts 'noun "contents")))
                 '((L . "Scroll")))
        'on
        (lambda (ev)
          (case (car ev)
            [(press)
             (if lispm?
                 (let* ([button (list-ref ev 3)] [clicks (list-ref ev 4)]
                        [key (list id 'click)] [last (ui-memo ui key #f)]
                        [delay (theme 'scrollbar-repeat-delay)]
                        [double? (and (theme 'scrollbar-double-click)
                                      (> clicks 1))]
                        ;; SDL sends a double click's single press first;
                        ;; the double starts again from before it
                        [base (if (and double? last (eq? button (car last)))
                                  (cdr last)
                                  off)])
                   (when (= clicks 1) (ui-memo! ui key (cons button off)))
                   (set-off! (to (at (cadr ev) (caddr ev)) base button
                                 (or double? (shift? button))))
                   (ui-memo! ui (list id 'hold)
                             (and delay (memq button '(left right))
                                  (list button (+ (now-ms) delay) 0)))
                   #t)
                 (and (eq? (list-ref ev 3) 'left)
                      (let* ([p (at (cadr ev) (caddr ev))]
                             [grab (if (<= t0 p (+ t0 tl)) (- p t0) (/ tl 2))])
                        (ui-memo! ui (list id 'grab) grab)
                        (thumb-to! (- p grab)))))]
            [(drag) (and (not lispm?)
                         (thumb-to! (- (at (cadr ev) (caddr ev))
                                       (ui-memo ui (list id 'grab) 0))))]
            ;; The wheel scrolls as over the view, since an outside bar lies
            ;; over no view; over a bar across, turned either way.
            [(wheel)
             (let* ([d (if (and across? (pair? (cddr ev)))
                           (- (cadr ev) (caddr ev))
                           (cadr ev))]
                    [new (clamp (- off (* d (ui-scroll-step))) 0 most)])
               (and (not (= new off)) (begin (set-off! new) #t)))]
            [else #f])))
      (when lispm?
        (ui-scrollbar-repeat! ui id (ui-hover? ui x y w h) off view lh
          (lambda (button)
            (to (at (ui-state-mx ui) (ui-state-my ui)) off button
                (shift? button)))
          set-off!))
      ;; in the margin, drawn only while the pointer is over it or it is
      ;; held, its region kept so that the first press there takes
      (when (or (not (eq? (theme 'scrollbar-show) 'bar))
                (ui-active? ui id) (memq 'hover (ui-flags ui id)))
        (let ([flags (append (plist-ref opts 'flags '()) (ui-flags ui id))])
          (if across?
              (with-transpose
                (ui-draw-scrollbar y x h w (cons 'across flags) start size))
              (ui-draw-scrollbar x y w h flags start size))))))

  ;; A button held over a Lisp machine's bar repeats what its press did
  ;; (Genera's bars do, by default; UG p.2804), from scrollbar-repeat-delay
  ;; ms after the press (#f for never) until it is released, leaves the bar
  ;; (over? tells) or can scroll no further. The first repeats come as often
  ;; as lines would at scrollbar-repeat-slowest a second, and each a fifth
  ;; sooner than the one before, which is this kit's choice, up to
  ;; scrollbar-repeat-fastest lines or scrollbar-repeat-screens screens a
  ;; second. to returns where a button scrolls to from off.
  (define (ui-scrollbar-repeat! ui id over? off view lh to set-off!)
    (let* ([key (list id 'hold)] [hold (ui-memo ui key #f)])
      (when hold
        (let ([button (car hold)] [due (cadr hold)] [k (caddr hold)])
          (cond
            [(not (and over? (eq? *mouse-button* button)))
             (ui-memo! ui key #f)]
            [(< (now-ms) due) (ui-due! ui due)]
            [else
             (let* ([new (to button)] [n (/ (abs (- new off)) lh)])
               (if (= n 0)
                   (ui-memo! ui key #f)
                   (let ([s (max (/ n (min (theme 'scrollbar-repeat-fastest)
                                           (* (theme 'scrollbar-repeat-screens)
                                              (/ view lh))))
                                 (/ (expt 0.8 k)
                                    (theme 'scrollbar-repeat-slowest)))])
                     (set-off! new)
                     (ui-memo! ui key
                               (list button
                                     (+ (now-ms) (exact (round (* 1000 s))))
                                     (+ k 1)))
                     (invalidate! (current-window)))))])))))

  ;; Returns the end box that p along a bar lies in, as its areas' (up x y w
  ;; h) or (down x y w h), or #f.
  (define (ui-scrollbar-end areas across? p)
    (find (lambda (a)
            (and (memq (car a) '(up down))
                 (let ([a0 (if across? (cadr a) (caddr a))]
                       [al (if across? (cadddr a) (list-ref a 4))])
                   (and (<= a0 p) (< p (+ a0 al))))))
          areas))

  ;; Returns how far along the track from k0, kl long, p lies: 0 to 1.
  (define (ui-scrollbar-part k0 kl p) (/ (clamp (- p k0) 0 kl) (max 1 kl)))

  ;; The Lisp machines' scrolling by the bar (TV's three buttons; Genera's
  ;; end boxes): returns the offset after a press of button at p along a
  ;; bar from b, l long, its track from k0, kl long, over a view showing
  ;; content from off, its lines lh high. The left button brings the line
  ;; pointed at to the top, the right the top line to the pointer, and the
  ;; middle that part of the content into view; twice (the CADR's double
  ;; click, or Shift and the left button) the pointed line goes to the other
  ;; end. In an end box (Genera's up and down) the left and right buttons
  ;; scroll a line (up) or a page (down), and the middle goes to the start
  ;; or the end.
  (define (ui-lispm-scroll-offset areas across? b l k0 kl p off content view
                                  lh button twice?)
    (let* ([line (* lh (floor (/ (clamp (- p b) 0 l) lh)))]
           [page (* lh (max 1 (floor (/ (- view (- lh 1)) lh))))]
           [most (max 0 (- content view))]
           [end (ui-scrollbar-end areas across? p)])
      (clamp (if end
                 (case button
                   [(middle) (if (eq? (car end) 'up) 0 most)]
                   [(left) (+ off (if (eq? (car end) 'up) lh page))]
                   [(right) (- off (if (eq? (car end) 'up) lh page))]
                   [else off])
                 (case button
                   [(middle)
                    (* lh (round (/ (* content (ui-scrollbar-part k0 kl p))
                                    lh)))]
                   [(left) (+ off line (if twice? (- page) 0))]
                   [(right) (+ off (- line) (if twice? page 0))]
                   [else off]))
             0 most)))

  ;; Returns what those buttons do at p along a bar, as the mouse
  ;; documentation says it: Genera's, in the end box there (HB
  ;; p.2563-2564) or along the shaft (UID p.1297), noun being what it calls
  ;; the content; or the CADR's, whose double click goes to the other end
  ;; (mouse.lisp:944-946).
  (define (ui-lispm-scroll-doc areas across? k0 kl p noun)
    (let ([end (ui-scrollbar-end areas across? p)]
          [cadr? (theme 'scrollbar-double-click)])
      (map cons
           (cond [end '(L M R)] [cadr? '(L L2 M R)] [else '(L sh-L M R)])
           (if end
               (if (eq? (car end) 'up)
                   (if across?
                       '("Next column" "Leftmost column" "Previous column")
                       '("Next line" "First screen" "Previous line"))
                   (if across?
                       '("Screen to the right" "Rightmost screen"
                         "Screen to the left")
                       '("Next screen" "Last screen" "Previous screen")))
               (let ([part (if cadr?
                               "Percentage-wise"
                               (format "Move to ~a% of ~a"
                                       (exact (round (* 100 (ui-scrollbar-part
                                                             k0 kl p))))
                                       noun))])
                 (if across?
                     (list "This column to left edge"
                           "This column to right edge" part "Left edge to here")
                     (list "This line to top" "This line to bottom" part
                           "Top line to here")))))))

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
  ;; whether a bar is there though all of its view's content fits, its thumb
  ;; as long as its track (Genera's :normal, UID p.1297)
  (at-load
   (theme-default! 'scrollbar-full #f))
  ;; how the bar is worked: drag its thumb, or the Lisp machines' three
  ;; buttons (lispm: ui-lispm-scroll-offset), a double click going to the
  ;; other end (the CADR's), a line being so many pixels
  (at-load
   (theme-default! 'scrollbar-input 'drag))
  (at-load
   (theme-default! 'scrollbar-double-click #f))
  ;; a held button's repeats (ui-scrollbar-repeat!): how many ms after the
  ;; press they begin, or #f for none, and their speeds, in lines a second
  ;; and, at most, screens a second
  (at-load
   (theme-default! 'scrollbar-repeat-delay #f))
  (at-load
   (theme-default! 'scrollbar-repeat-slowest 2))
  (at-load
   (theme-default! 'scrollbar-repeat-fastest 50))
  (at-load
   (theme-default! 'scrollbar-repeat-screens 2))
  (at-load
   (theme-default! 'scrollbar-line-height
                   (theme-rule (font-line-height 'ui))))
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

  ;; Returns the bar's areas, each (name x y w h): its thumb, and the track
  ;; the thumb travels along if that is not the whole bar. start and size
  ;; are the view's top and height as fractions of the content.
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

  ;; How far a card's content (its marks, title, tags and dates) is from
  ;; its edges.
  (define-part (ui-card-pad) 10)

  ;; How far a panel beside a list or a board (its details, or keys when
  ;; nothing is chosen) keeps what it shows from its edges, and clear of a
  ;; scroll bar a style keeps room for.
  (define-part (ui-panel-pad) 16)

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

  (define-part (ui-draw-scrim x y w h flags)
    (fill-box x y w h (alpha 'bg-0 0.55)))

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
