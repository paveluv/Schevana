;;; (schevana core windows) — the window manager.
;;;
;;; A window is a record with geometry, a table of handlers and a table of
;;; properties. Apps are procedures that call open-window:
;;;
;;;   (open-window "Hello"
;;;     'size '(300 . 120)                        ; content size
;;;     'draw (lambda (win w h) (draw-text 20 20 "Hi!" 'text 'big))
;;;     'key  (lambda (win key mods) ...))
;;;
;;; Options other than handlers (and size, min-size, pos, app) become
;;; window properties: (window-ref win 'bg), (window-ref win 'cursor).
;;; 'above owner makes a window its owner's: it stays above the owner, which
;;; still takes the keyboard when it is given it, and the two are raised,
;;; minimized, brought back, sent behind and closed together.
;;;
;;; Handlers: open draw frame key text mouse-down mouse-up mouse-move wheel
;;;           resize focus blur close.
;;;
;;; The frame around the content (title bar, borders, buttons) belongs to
;;; the style ((schevana core theme)). Geometry here is the outer frame's;
;;; 'size and the w h passed to handlers are always the content's size.
;;; Every handler runs under safe-call: errors and runaway loops crash only
;;; that window, which then shows the error and can be retried.

(library (schevana core windows)
  (export
    window window? window-id window-app window-title window-title-set! window-x
    window-x-set! window-y window-y-set! window-w window-w-set! window-h
    window-h-set! window-state window-state-set! window-restore-set!
    window-min-w window-min-h window-handlers window-props window-error
    *windows* *focus* *drag-outline* *hover* *mouse-x* *mouse-y* *mouse-button*
    *mouse-mods*
    drag current-window window-gone! invalidate! window-shadow window-extent
    screen-w screen-h screen-scale point-in? surface surface-doc surface-draw
    define-surface find-surface surface-call define-strip desktop-rect app
    app-name app-title
    app-launch app-icon *apps* define-app apps open-window detached-window
    new-window-position cascade-reset! place-window! windows focused-window
    visible? maximized? window-covered? find-window window-ref window-set!
    window-on! window-bg
    in-window-theme window-setting frame-insets frame-regions frame-radius
    frame-bleed content-rect window-content-size window-local window-call
    window-crash! window-modal-child focus-window! close-window!
    minimize-window! set-geometry! move-window! resize-window! restore-window!
    toggle-maximize! window-action! window-drag-move! shaded? unshade-window!
    toggle-shade! window-at screen-at resize-kinds window-region *global-keys*
    bind-key!
    window-frame-soon! window-hover draw-window* surfaces maximize-window!
    unbind-key!)
  (import (chezscheme)
          (only (schevana base) at-load clamp condition->string define-hook
                define-state library-layer plist-ref registry-add set-hook!
                string-contains-ci?)
          (only (schevana core0) core0-set-cursor!)
          (only (schevana core theme-table) *main-theme* *theme* theme
                theme-part world-value)
          (only (schevana core processes) *frame-generation* proc report-error!
                request-frame! request-redraw! safe-call safely
                with-profile-span)
          (only (schevana core gpu) gpu-list-new gpu-list-release!)
          (only (schevana core draw) *canvas-h* *canvas-w* *rec-den* *rec-num*
                *scale* draw-shadow draw-text fill-box record-list! show-list
                with-clip with-label with-translation)
          (only (schevana core pacer) frame-turn-soon! pacer-frame-ns
                record-safely record-world! wm-tick!)
          (only (schevana core screen) wm-screen-resized!)
          (only (schevana core loop) wm-event!)
          (only (schevana core theme) find-style style-theme theme-default!
                wm-chrome-changed!))

  (library-layer core)

  (define-record-type window
    (nongenerative schevana-window)
    (fields id app
            (mutable title) (mutable x) (mutable y) (mutable w) (mutable h)
            (mutable state)       ; normal | minimized | maximized
            (mutable restore)     ; (x y w h) before maximizing
            handlers              ; eq-hashtable: kind -> procedure
            props                 ; eq-hashtable: app-defined state
            (mutable error)       ; (handler-kind . condition) once crashed
            (mutable min-w) (mutable min-h)))

  (at-load
   (record-writer (record-type-descriptor window)
     (lambda (w p wr)
       (fprintf p "#<window ~a ~s ~ax~a+~a+~a~a>" (window-id w) (window-title w)
                (window-w w) (window-h w) (window-x w) (window-y w)
                (if (eq? (window-state w) 'normal)
                    ""
                    (format " ~a" (window-state w)))))))

  (define handler-kinds
    '(open draw frame key text mouse-down mouse-up mouse-move wheel resize focus
      blur close))

  (define-state *windows* '())        ; z-order, topmost first
  (define-state *focus* #f)
  (define-state *next-window-id* 1)
  ;; the current mouse interaction, a drag record, or #f
  (define-state *drag* #f)
  ;; (x y w h): where an outline drag would put it
  (define-state *drag-outline* #f)
  (define-state *hover* #f)
  (define-state *mouse-x* 0)
  (define-state *mouse-y* 0)
  (define-state *mouse-button* #f)    ; the button held down, or #f
  (define-state *mouse-mods* '())     ; the modifier keys held at its press
  (define-state *cascade* 0)

  (define-record-type drag
    (nongenerative schevana-drag)
    (fields kind win button mx my x y w h))

  ;;; ------------------------------------------------------------------
  ;;; invalidation
  ;;; A change records in *dirty* that the screen may now look different:
  ;;; the next frame records the screen's surfaces again and draws it all. A
  ;;; window keeps what it drew as a list, and draws again only when it
  ;;; opens or resizes, when what its frame is drawn with changes (its
  ;;; focus, the part under the mouse or held, its title, state or error),
  ;;; after it handles input, and when it is asked to:
  ;;;
  ;;;   (invalidate!)       anything may have changed: every window draws
  ;;;   (invalidate! win)   win may have (input to a window says so by itself)
  ;;;   (invalidate! win x y w h)   a part of it
  ;;;   (request-frame!), (request-frame! x y w h)   a frame of what is there
  ;;;
  ;;; A window that changes by itself over time (a clock, an animation) says
  ;;; so with invalidate!. A window that is moved or raised isn't drawn
  ;;; again: the screen shows its list somewhere else.

  ;; the window whose handler is running
  (define-state current-window (make-thread-parameter #f))
  ;; Told of each window that closes or crashes, to stop what works for it
  ;; (its background jobs; (schevana services vat) sets it); until then it
  ;; does nothing.
  (define-hook (window-gone! win) (void))

  ;; Draws a window's shadow, for its style: its size is the theme key
  ;; 'shadow, half that when unfocused; a maximized window has none.
  (define (window-shadow win x y w h r focused?)
    (unless (maximized? win)
      (draw-shadow x y w h r
                   (if focused? (theme 'shadow) (quotient (theme 'shadow) 2)))))

  ;; Returns how far past its frame a window's shadow may reach, in whole
  ;; logical pixels: the focused size, plus the third of it by which the
  ;; shadow lies lower.
  (define (window-shadow-reach win)
    (let ([size (theme 'shadow)])
      (if (maximized? win) 0 (+ size (quotient (+ size 2) 3)))))

  ;; Returns what win may cover on screen, as (values x y w h): its frame and
  ;; bleed, or the whole screen if the bleed raises (a mistake typed at the
  ;; REPL), so that frames and input go on and the mistake can be fixed.
  (define (window-extent win)
    ;; only the style's bleed is guarded: a guard around one value is
    ;; cheaper than around four
    (let ([b (guard (c [#t (report-error! 'bleed c) #f]) (window-bleed win))])
      (if b
          (values (- (window-x win) b) (- (window-y win) b)
                  (+ (window-w win) b b) (+ (window-h win) b b))
          (values 0 0 (screen-w) (screen-h)))))

  (define (screen-w) *canvas-w*)
  (define (screen-h) *canvas-h*)
  (define (screen-scale) *scale*)   ; the screen's pixels to a logical one

  (define (point-in? px py x y w h)
    (and (>= px x) (< px (+ x w)) (>= py y) (< py (+ y h))))

  ;;; ------------------------------------------------------------------
  ;;; surfaces
  ;;; Surfaces are what the window manager draws and routes input to besides
  ;;; windows: the desktop under them (depth below 0), and bars, menus and
  ;;; toasts over them, in depth order. They belong to the desktop layer
  ;;; (desktop/); the core names none of its procedures. Each field is a
  ;;; procedure, or the name of one that is looked up at each call, so the
  ;;; desktop layer's procedures stay redefinable.

  (define-record-type surface
    (nongenerative schevana-surface-3)
    (fields name depth
            draw    ; ()                           draws it
            box     ; () -> (values x y w h)       what it covers this frame
            at      ; (x y) -> what, or #f         what is there; #f lets
                    ;                              the point through
            mouse   ; (kind what x y button clicks)    kind: down up move
            key     ; (kind value mods) -> #t if taken; kind: key or text
            frame   ; (t)                          each frame, before it is
                    ;                              drawn: to see what changed
            doc))   ; (what) -> ((L . "Apps") ...)  its mouse documentation

  (define-state *surfaces* '())   ; by depth
  (at-load (set! *surfaces* (filter surface? *surfaces*)))

  (define (register-surface! name depth . opts)
    (set! *surfaces*
      (list-sort (lambda (a b) (< (surface-depth a) (surface-depth b)))
                 (registry-add *surfaces*
                   (make-surface name depth
                     (plist-ref opts 'draw void)
                     (plist-ref opts 'box (lambda () (values 0 0 0 0)))
                     (plist-ref opts 'at (lambda (x y) #f))
                     (plist-ref opts 'mouse void)
                     (plist-ref opts 'key (lambda args #f))
                     (plist-ref opts 'frame (lambda (t) (void)))
                     (plist-ref opts 'doc (lambda (what) '())))
                   surface-name)))
    (request-frame!)
    name)

  ;; (define-surface topbar 20 'draw 'draw-topbar 'box 'topbar-box ...)
  ;; adds a surface, or replaces the one of that name.
  (define-syntax define-surface
    (syntax-rules ()
      [(_ name depth opt ...) (register-surface! 'name depth opt ...)]))

  (define (find-surface name)
    (find (lambda (s) (eq? (surface-name s) name)) *surfaces*))

  (define (surfaces) (map surface-name *surfaces*))

  ;; Calls a surface's field: a procedure, or the name of one.
  (define (surface-call s field . args)
    (let ([v (field s)])
      (apply (if (symbol? v) (world-value v) v) args)))

  (define (over-windows? s) (>= (surface-depth s) 0))

  ;;; strips
  ;; (define-strip topbar 'top 'topbar-height): the area windows go in loses
  ;; (topbar-height) pixels at the top; strips on one edge add up.
  (define-state *strips* '())   ; ((name edge . size) ...)

  (define (register-strip! name edge size)
    (set! *strips* (registry-add *strips* (cons* name edge size) car))
    (wm-screen-resized!)
    name)

  (define-syntax define-strip
    (syntax-rules ()
      [(_ name edge size) (register-strip! 'name edge size)]))

  ;; Returns where windows go (maximized, tiled, kept on screen), as (values
  ;; x y w h): the screen less every strip.
  (define (desktop-rect)
    (define (edge e)
      (apply + (map (lambda (s)
                      (if (eq? (cadr s) e)
                          (let ([n (cddr s)])
                            ((if (symbol? n) (world-value n) n)))
                          0))
                    *strips*)))
    (let ([t (edge 'top)] [b (edge 'bottom)] [l (edge 'left)]
          [r (edge 'right)])
      (values l t (- (screen-w) l r) (- (screen-h) t b))))

  ;;; ---------------------------------------------------------------- apps

  ;; icon: a procedure (x y s flags) that draws the app's icon, or #f
  (define-record-type app
    (nongenerative schevana-app-2)
    (fields name title launch icon))

  (define-state *apps* '())
  (define-state current-app (make-thread-parameter #f))

  (define (register-app! name title launch icon)
    (set! *apps*
      (registry-add *apps* (make-app name title launch icon) app-name))
    (request-frame!))

  ;; (define-app (name) "Title" body ...) defines an ordinary procedure that
  ;; opens the app, and registers it with the launcher. With 'icon draw
  ;; after the title, the app has an icon: draw is a procedure (x y s flags)
  ;; that draws it in an s-square, faded when flags hold dim, and it is
  ;; called by name, so that a redefinition shows at the next draw.
  ;; 'icon is told by its datum: at the top level, where "/" binds every
  ;; name, a literal would never match.
  (define-syntax define-app
    (lambda (stx)
      (syntax-case stx ()
        [(_ (name . args) title key draw body ...)
         (equal? (syntax->datum #'key) ''icon)
         #'(begin
             (define (name . args)
               (parameterize ([current-app 'name]) body ...))
             (at-load (register-app! 'name title (lambda () (name))
                                     (lambda (x y s flags)
                                       (draw x y s flags)))))]
        [(_ (name . args) title body ...)
         #'(begin
             (define (name . args)
               (parameterize ([current-app 'name]) body ...))
             (at-load (register-app! 'name title (lambda () (name)) #f)))])))

  (define (apps) (map app-name *apps*))

  ;;; ---------------------------------------------------------------- windows

  (define (open-window title . opts)
    (let ([win (apply detached-window title opts)])
      (set! *next-window-id* (+ *next-window-id* 1))
      (place-window! win (plist-ref opts 'pos #f))
      (set! *windows* (cons win *windows*))
      (window-call win 'open)
      (focus-window! win)
      win))

  ;; Makes a window as open-window does, at 0, 0, but not on screen: a
  ;; style's miniature (in Settings' previews) draws one with draw-window*.
  (define (detached-window title . opts)
    (let* ([whole (lambda (p)
                    (cons (exact (round (car p))) (exact (round (cdr p)))))]
           [size (whole (plist-ref opts 'size '(480 . 320)))]
           [min-size (whole (plist-ref opts 'min-size '(160 . 80)))]
           [win (make-window *next-window-id*
                             (plist-ref opts 'app (current-app)) title
                             0 0 (car size) (cdr size) 'normal #f
                             (make-eq-hashtable) (make-eq-hashtable) #f
                             (car min-size) (cdr min-size))])
      ;; Handler options become handlers; any other option becomes a property.
      (let loop ([o opts])
        (when (and (pair? o) (pair? (cdr o)))
          (cond
            [(memq (car o) handler-kinds)
             (hashtable-set! (window-handlers win) (car o) (cadr o))]
            [(memq (car o) '(size min-size pos app)) (void)]
            [else (hashtable-set! (window-props win) (car o) (cadr o))])
          (loop (cddr o))))
      ;; The frame depends on the style, which may come from the options.
      (let-values ([(l t r b) (frame-insets win)])
        (window-w-set! win (+ l r (car size)))
        (window-h-set! win (+ t b (cdr size))))
      win))

  ;; Where a window opens when open-window gets no 'pos: #f to cascade, or a
  ;; point for its top-left corner, moved as little as needed to fit on the
  ;; desktop. (parameterize ([new-window-position '(400 . 300)]) (clock))
  (define-state new-window-position (make-thread-parameter #f))

  ;; The next window that cascades opens at the cascade's first place.
  (define (cascade-reset!) (set! *cascade* 0))

  (define (place-window! win pos)
    (let-values ([(dx dy dw dh) (desktop-rect)])
      (window-w-set! win (min (window-w win) dw))
      (window-h-set! win (min (window-h win) dh))
      (cond
        [pos (window-x-set! win (car pos)) (window-y-set! win (cdr pos))]
        [(new-window-position)
         => (lambda (at)
              (window-x-set! win (clamp (car at) dx
                                        (max dx (- (+ dx dw) (window-w win)))))
              (window-y-set! win
                             (clamp (cdr at) dy
                                    (max dy (- (+ dy dh) (window-h win))))))]
        [else
          (let ([k (mod *cascade* 8)])
            (set! *cascade* (+ *cascade* 1))
            (window-x-set! win (+ dx (min (+ 60 (* 34 k))
                                          (max 0 (- dw (window-w win))))))
            (window-y-set! win (min (+ dy 24 (* 30 k))
                                    (max dy (- (+ dy dh) (window-h win))))))])))

  (define (windows) *windows*)
  (define (focused-window) *focus*)
  (define (visible? win) (not (eq? (window-state win) 'minimized)))
  (define (maximized? win) (eq? (window-state win) 'maximized))

  ;; Returns the window that x names: an id, a part of the title (in any
  ;; case), an app's name, or the window itself. For an app's name, a window
  ;; of the app's own comes before one opened above another window.
  (define (find-window x)
    (let ([match? (lambda (w)
                    (cond [(number? x) (= (window-id w) x)]
                          [(string? x) (string-contains-ci? (window-title w) x)]
                          [(symbol? x) (eq? (window-app w) x)]
                          [else (eq? w x)]))])
      (or (and (symbol? x)
               (find (lambda (w) (and (match? w) (not (window-owner w))))
                     *windows*))
          (find match? *windows*))))

  (define (window-ref win key . default)
    (hashtable-ref (window-props win) key
                   (if (null? default) #f (car default))))

  ;; Sets a property of win, which is then drawn again as invalidate! asks
  ;; (in a frame, if it is seen).
  (define (window-set! win key val)
    (hashtable-set! (window-props win) key val)
    (invalidate! win))

  (define (window-on! win kind proc)
    (hashtable-set! (window-handlers win) kind proc)
    (window-error-set! win #f)
    (invalidate! win))

  (define (window-bg win) (window-ref win 'bg 'window-bg))

  ;; Returns the theme win is drawn and hit-tested in, content included: its
  ;; own style's (its 'window-style property, a style's name; the theme in
  ;; effect when it is that style, such as a preview's), or else the chosen
  ;; style's.
  (define (window-theme win)
    (let ([s (window-ref win 'window-style)])
      (cond [(and s (eq? s (theme 'window-style))) *theme*]
            [(and s (find-style s)) (style-theme s #f)]
            [else *main-theme*])))

  ;; Runs thunk in win's theme. A theme change it makes (set-theme! from a
  ;; handler) stays after it.
  (define (in-window-theme win thunk)
    (let ([t (window-theme win)] [main #f])
      (if (eq? t *theme*)
          (thunk)
          (dynamic-wind (lambda () (set! main *theme*) (set! *theme* t))
                        thunk
                        (lambda ()
                          (when (eq? *theme* t) (set! *theme* main)))))))

  ;; Calls win's frame part key ((schevana core theme)) in win's theme; when
  ;; that theme is the one on, it calls the part directly, with no closure.
  (define (frame-call win key . args)
    (if (eq? (window-theme win) *theme*)
        (apply (theme-part key) win args)
        (in-window-theme win (lambda () (apply (theme-part key) win args)))))

  ;; Returns a setting in win's theme: its own style's, or the chosen one's.
  (define (window-setting win key)
    (in-window-theme win (lambda () (theme key))))

  ;; A window opened 'frameless #t has no frame of the style's: its
  ;; content is all of it (a host app's one window, framed by the host's
  ;; desktop).
  (define (frameless? win) (window-ref win 'frameless))

  ;; Returns the frame's thickness around the content, as (values left top
  ;; right bottom).
  (define (frame-insets win)
    (if (frameless? win) (values 0 0 0 0) (frame-call win 'frame-insets)))
  (define (frame-regions win)
    (if (frameless? win) '() (frame-call win 'frame-regions)))
  (define (frame-radius win)
    (if (frameless? win) 0 (frame-call win 'frame-radius)))
  (define (frame-bleed win)
    (if (frameless? win) 0 (frame-call win 'frame-bleed)))

  ;; The hooks below are made as the library loads, after the definitions
  ;; they reach; made before them, they would have Chez check at each call
  ;; that those are defined.

  ;; (invalidate!) starts a new generation (request-redraw!), so every
  ;; window draws again; (invalidate! win) asks for win alone. A list a
  ;; window drew before the call is not reused after it. A call made while
  ;; the window is drawing takes effect on the next frame. A window that is
  ;; closed, shown only in a preview, or minimized asks for no frame: a
  ;; timer it left running draws nothing, and the window draws as usual
  ;; once it is shown again.
  (define invalidate!
    (case-lambda
      [() (request-redraw!)]
      [(win) (when win
               (hashtable-update! (window-props win) 'wm-asked
                                  (lambda (n) (+ n 1)) 0))
             (when (or (not win) (and (memq win *windows*) (visible? win)))
               (request-frame!))]
      [(win x y w h) (invalidate! win)]))

  ;; Returns how far past its frame a window may draw, never less than 0:
  ;; its shadow's reach, or its style's frame-bleed when that is more. A
  ;; style that strokes inside its frame needs no bleed: anti-aliasing stays
  ;; in the device pixels the frame touches.
  (define (window-bleed-here win)
    (max 0 (window-shadow-reach win) (frame-bleed win)))

  (define (window-bleed win)
    (if (eq? (window-theme win) *theme*)
        (window-bleed-here win)
        (in-window-theme win (lambda () (window-bleed-here win)))))

  ;; Returns the content area in screen coordinates, as (values x y w h).
  (define (content-rect win)
    (let-values ([(l t r b) (frame-insets win)])
      (values (+ (window-x win) l) (+ (window-y win) t)
              (- (window-w win) l r) (- (window-h win) t b))))

  (define (window-content-size win)
    (let-values ([(x y w h) (content-rect win)]) (values w h)))

  (define (window-local win x y)
    (let-values ([(l t r b) (frame-insets win)])
      (values (- x (window-x win) l) (- y (window-y win) t))))

  ;; Calls one of the window's handlers under the watchdog, in its theme,
  ;; with (current-window) set to win. Input invalidates the window by
  ;; itself, so a handler that only changes its state is still seen.
  (define (window-call win kind . args)
    (let ([h (hashtable-ref (window-handlers win) kind #f)])
      (if (and h (not (window-error win)))
          (begin
            (when (memq kind '(key text mouse-down mouse-up wheel))
              (invalidate! win))
            (with-profile-span (window-id win) kind
              (safe-call kind
                         (lambda ()
                           (parameterize ([current-window win])
                             (in-window-theme win
                                              (lambda () (apply h win args)))))
                         (lambda (c) (window-crash! win kind c) #f))))
          #f)))

  ;; Marks win as crashed and draws the whole screen again: a handler
  ;; stopped partway may have left shared state (focus, order, titles) half
  ;; changed.
  (define (window-crash! win kind c)
    (window-error-set! win (cons kind c))
    (window-gone! win)
    (invalidate!))

  ;; Returns the window that win waits on, its 'modal-child while that is
  ;; open (a dialog: ui-open-modal), or #f. Where win's style keeps the
  ;; child above (modal-above), the child takes win's keyboard: focusing win
  ;; focuses it, and raising win raises it above win.
  (define (window-modal-child win)
    (let ([c (window-ref win 'modal-child)]) (and c (memq c *windows*) c)))

  (define (window-modal-above win)
    (and (window-setting win 'modal-above) (window-modal-child win)))

  ;; window-owner returns the window that win was opened above ('above),
  ;; while that one is open, or #f; window-owned returns the windows opened
  ;; above win, the lowest first.
  (define (window-owner win)
    (let ([o (window-ref win 'above)]) (and o (memq o *windows*) o)))

  (define (window-owned win)
    (reverse (filter (lambda (w) (eq? (window-owner w) win)) *windows*)))

  ;; Returns the owner that win's owners lead up to, which stands for the
  ;; whole group (depth-window!).
  (define (window-root win)
    (let ([o (window-owner win)]) (if o (window-root o) win)))

  ;; Gives win the keyboard and brings it to the front (not when raise? is
  ;; #f); a window that waits on another one above it gives that one the
  ;; keyboard.
  (define (focus-window! win . raise?)
    (let ([c (and win (window-modal-above win))])
      (if c
          (begin (unless (and (pair? raise?) (not (car raise?)))
                   (raise-window! win))
                 (focus-window! c #f))
          (apply focus-window-itself! win raise?))))

  (define (focus-window-itself! win . raise?)
    (unless (eq? win *focus*)
      (let ([old *focus*])
        (set! *focus* win)
        (when (and old (memq old *windows*)) (window-call old 'blur))
        (when win (window-call win 'focus))))
    (when win
      (window-unminimize! win)
      (unless (and (pair? raise?) (not (car raise?))) (raise-window! win)))
    (request-frame!))

  ;; Brings win back from minimized, and the windows it owns with it.
  (define (window-unminimize! win)
    (when (eq? (window-state win) 'minimized)
      (window-state-set! win (if (window-restore win) 'maximized 'normal))
      (for-each window-unminimize! (window-owned win))))

  (define (raise-window! win)
    (set! *windows* (cons win (remq win *windows*)))
    (let ([c (window-modal-above win)]) (when c (raise-window! c)))
    (for-each raise-window! (window-owned win))
    (request-frame!))

  (define (focus-topmost!)
    (let ([w (find visible? *windows*)])
      (if w
          (focus-window! w)
          (begin
            (when (and *focus* (memq *focus* *windows*))
              (window-call *focus* 'blur))
            (set! *focus* #f)))))

  ;; Closes win; the windows it owns, and the one waiting on it, close with
  ;; it.
  (define (close-window! win)
    (when (memq win *windows*)
      (for-each close-window! (window-owned win))
      (let ([c (window-modal-child win)]) (when c (close-window! c)))
      (window-call win 'close)
      (set! *windows* (remq win *windows*))
      (window-lists-release! win)
      (window-gone! win)
      (when (and *drag* (eq? (drag-win *drag*) win))
        (set! *drag* #f)
        (set! *drag-outline* #f))
      (when (eq? *focus* win) (focus-topmost!))
      (request-frame!)))

  (define (minimize-window! win)
    (unshade-window! win)
    (window-state-set! win 'minimized)
    (for-each minimize-window! (window-owned win))
    (when (eq? win *focus*) (focus-topmost!))
    (request-frame!))

  ;; Sets the outer geometry, enforcing minimum sizes, and tells the app;
  ;; then asks for a frame over the old extent and the new one. Asked for
  ;; before the change, the old extent could go to a frame drawn while a
  ;; process is switched out, with the window still there, and the old
  ;; picture would stay on screen.
  (define (set-geometry! win x y w h)
    (let*-values ([(l t r b) (frame-insets win)]
                  [(w) (max (+ l r (window-min-w win)) (exact (round w)))]
                  [(h) (max (if (shaded? win) 0 (+ t b (window-min-h win)))
                            (exact (round h)))]
                  [(resized?)
                   (not (and (= w (window-w win)) (= h (window-h win))))]
                  [(ox oy ow oh) (window-extent win)])
      (window-x-set! win (exact (round x)))
      (window-y-set! win (exact (round y)))
      (window-w-set! win w)
      (window-h-set! win h)
      (when resized? (window-call win 'resize (- w l r) (- h t b)))
      (request-frame! ox oy ow oh)
      ;; a moved window isn't drawn again: the screen shows its list
      ;; elsewhere
      (if resized? (invalidate! win) (request-frame!))))

  (define (move-window! win x y)
    (set-geometry! win x y (window-w win) (window-h win)))

  ;; Resizes the content area to w x h.
  (define (resize-window! win w h)
    (let-values ([(l t r b) (frame-insets win)])
      (set-geometry! win (window-x win) (window-y win) (+ w l r) (+ h t b))))

  ;; Does what a 'depth button does (the Amiga's depth gadget): sends the
  ;; front window to the back, or brings a window that is behind others to
  ;; the front, treating an owner and the windows above it as one.
  (define (depth-window! win)
    (let* ([root (window-root win)]
           [group? (lambda (w) (eq? (window-root w) root))])
      (if (group? (find visible? *windows*))
          (begin
            (set! *windows* (append (remp group? *windows*)
                                    (filter group? *windows*)))
            (focus-topmost!))
          (focus-window! win)))
    (request-frame!))

  (define (maximize-window! win)
    (unshade-window! win)
    (unless (eq? (window-state win) 'maximized)
      (window-restore-set! win (list (window-x win) (window-y win)
                                     (window-w win) (window-h win)))
      (window-state-set! win 'maximized)
      (fit-maximized! win)
      (request-frame!)))

  (define (fit-maximized! win)
    (let-values ([(x y w h) (desktop-rect)])
      (set-geometry! win x y w h)))

  (define (restore-window! win)
    (let ([r (window-restore win)])
      (window-state-set! win 'normal)
      (window-restore-set! win #f)
      (when r (apply set-geometry! win r))
      (request-frame!)))

  (define (toggle-maximize! win)
    (if (eq? (window-state win) 'maximized)
        (restore-window! win)
        (maximize-window! win)))

  ;; Does to win the action that a style's setting names (for a double
  ;; click, or a button): maximize, shade, minimize, close or depth; any
  ;; other does nothing. A window's 'on-action, (lambda (win action) ...),
  ;; true when it acted, may do the action in its place (a host app's acts
  ;; on the OS window), and also the window menu ('menu) and a drag of the
  ;; title ('move).
  (define (window-action! win action)
    (unless (window-own-action? win action)
      (case action
        [(maximize) (toggle-maximize! win)]
        [(shade) (toggle-shade! win)]
        [(minimize) (minimize-window! win)]
        [(close) (close-window! win)]
        [(depth) (depth-window! win)])))

  ;; Opens the window's menu at (x, y): its 'on-action's, or else the
  ;; style's.
  (define (window-menu! win x y)
    (unless (window-own-action? win 'menu)
      ((theme-part 'open-window-menu) win x y)))

  ;; Whether win's 'on-action did action itself.
  (define (window-own-action? win action)
    (let ([own (window-ref win 'on-action #f)])
      (and own (own win action))))

  ;; A shaded window shows only its frame's top and bottom (the insets its
  ;; frame gives while shaded); its content is not drawn, and its app hears
  ;; no resize. Its full height waits in the property 'unshaded-h, while the
  ;; record holds the shaded one.
  (define (shaded? win) (and (window-ref win 'unshaded-h) #t))

  (define (shade-window! win)
    (when (and (not (shaded? win)) (eq? (window-state win) 'normal))
      (window-set! win 'unshaded-h (window-h win))
      (let-values ([(l t r b) (frame-insets win)])
        (if (> (+ t b) 0)                     ; a title along the top
            (window-h-set! win (+ t b))
            (window-set! win 'unshaded-h #f)))))

  (define (unshade-window! win)
    (when (shaded? win)
      (window-h-set! win (window-ref win 'unshaded-h))
      (window-set! win 'unshaded-h #f)))

  (define (toggle-shade! win)
    ((if (shaded? win) unshade-window! shade-window!) win))

  ;; Core0's window was resized, or the screen changed size (or scale):
  ;; refits maximized windows, and pulls the others back until their title
  ;; bars can be reached.
  (set-hook! (wm-screen-resized!)
    ;; (also called while loading, before there is a canvas to measure)
    (unless (null? *windows*)
      (let-values ([(dx dy dw dh) (desktop-rect)])
        (for-each (lambda (w)
                    (if (eq? (window-state w) 'maximized)
                        (fit-maximized! w)
                        (begin
                          (window-x-set! w (clamp (window-x w)
                                                  (- (+ dx 80) (window-w w))
                                                  (max dx (- (+ dx dw) 80))))
                          (window-y-set! w (clamp (window-y w) dy
                                                  (max dy (- (+ dy dh) 30)))))))
                  *windows*)))
    (invalidate!))

  ;; The style or the title height changed. Frames keep their outer size, so
  ;; every app hears its new content size; a shaded window's app hears what
  ;; it unshades to.
  (set-hook! (wm-chrome-changed!)
    (wm-screen-resized!)
    (for-each (lambda (w)
                (let ([shaded? (shaded? w)])
                  (unshade-window! w)   ; then shaded again in its new frame
                  (let-values ([(cw ch) (window-content-size w)])
                    (window-call w 'resize cw ch))
                  (when shaded? (shade-window! w))))
              *windows*))

  ;;; ------------------------------------------------------------------
  ;;; hit testing

  (define (window-at x y)
    (find (lambda (w)
            (and (visible? w)
                 (point-in? x y (window-x w) (window-y w)
                            (window-w w) (window-h w))))
          *windows*))

  ;; A resize region's kind names the sides a drag on it moves: l, r, t, b.
  (define resize-kinds
    '(resize-l resize-r resize-t resize-b resize-tl resize-tr resize-bl
      resize-br))

  ;; Returns which part of the window is at screen point (x, y): its style's
  ;; regions first, then the window manager's resize edges, 'frame-edge wide
  ;; (0 for none) with corners 'frame-corner long, then the title, then the
  ;; content.
  (define (window-region win x y)
    (let*-values ([(lx) (- x (window-x win))] [(ly) (- y (window-y win))]
                  [(w) (window-w win)] [(h) (window-h win)]
                  [(l t r b) (frame-insets win)]
                  [(edge) (window-setting win 'frame-edge)]
                  [(corner) (window-setting win 'frame-corner)]
                  [(free?) (and (eq? (window-state win) 'normal)
                                (not (shaded? win)))]   ; it may resize
                  ;; a frameless window's edges are its content's
                  [(resizable?) (and free? (> edge 0) (not (frameless? win)))])
      (cond
        [(find (lambda (r) (and (or free? (not (memq (car r) resize-kinds)))
                                (apply point-in? lx ly (list-head (cdr r) 4))))
               (frame-regions win))
         => car]
        [(and resizable? (>= ly (- h corner)) (>= lx (- w corner))) 'resize-br]
        [(and resizable? (>= ly (- h corner)) (< lx corner)) 'resize-bl]
        [(and resizable? (>= lx (- w edge)) (> ly edge)) 'resize-r]
        [(and resizable? (< lx edge) (> ly t)) 'resize-l]
        [(and resizable? (>= ly (- h edge))) 'resize-b]
        [(< ly t) 'title]
        [(and (>= lx l) (< lx (- w r)) (< ly (- h b))) 'content]
        [else 'frame])))

  (define (region-cursor win region)
    (case region
      [(resize-br resize-tl) 'resize-nwse]
      [(resize-bl resize-tr) 'resize-nesw]
      [(resize-r resize-l) 'resize-ew]
      [(resize-b resize-t) 'resize-ns]
      [(content) (if (window-error win) 'hand (window-ref win 'cursor 'arrow))]
      [else 'arrow]))

  ;;; ---------------------------------------------------------------- mouse

  ;; Returns what is at screen point (x, y): (surface name what) from the
  ;; topmost surface over the windows that answers, else (window win
  ;; region), else (surface name what) from a surface under them; #f where
  ;; nothing is.
  (define (screen-at x y)
    (define (answer ss)
      (exists (lambda (s)
                (let ([what (surface-call s surface-at x y)])
                  (and what (list 'surface (surface-name s) what))))
              ss))
    (let ([ss (reverse *surfaces*)])   ; topmost first
      (or (answer (filter over-windows? ss))
          (let ([w (window-at x y)])
            (and w (list 'window w (window-region w x y))))
          (answer (remp over-windows? ss)))))

  (define (update-hover! x y)
    (let ([h (screen-at x y)])
      (unless (equal? h *hover*)
        (request-hover-frame! *hover*)
        (set! *hover* h)
        (request-hover-frame! h))
      (core0-set-cursor!
       (if (and h (eq? (car h) 'window))
           (region-cursor (cadr h) (caddr h))
           'arrow))))

  ;; Asks to draw again what shows the hover h: its window, or its surface's
  ;; box; nothing for a surface under the windows (the desktop draws no
  ;; hover).
  (define (request-hover-frame! h)
    (case (and (pair? h) (car h))
      [(window) (invalidate! (cadr h))]
      [(surface)
       (let ([s (find-surface (cadr h))])
         (when (and s (over-windows? s))
           (call-with-values (lambda () (surface-call s surface-box))
             request-frame!)))]))

  ;; Has the surface of the hover h, (surface name what), act on the mouse.
  (define (surface-mouse! h kind x y button clicks)
    (let ([s (find-surface (cadr h))])
      (when s (surface-call s surface-mouse kind (caddr h) x y button clicks))))

  (define (wm-mouse-move x y)
    (set! *mouse-x* x)
    (set! *mouse-y* y)
    (let ([d *drag*])
      (cond
        [(not d)
         (update-hover! x y)
         (let ([h *hover*])
           (case (and h (car h))
             [(surface) (surface-mouse! h 'move x y #f 0)]
             [(window)   ; a frame's outside scroll bar is the app's too
              (when (memq (caddr h) '(content scrollbar))
                (let-values ([(lx ly) (window-local (cadr h) x y)])
                  (window-call (cadr h) 'mouse-move lx ly)))]))]
        [(eq? (drag-kind d) 'move) (drag-move! d x y)]
        [(eq? (drag-kind d) 'capture)
         (let ([win (drag-win d)] [h (screen-at x y)])
           (when (and h (eq? (car h) 'surface))   ; a menu it opened
             (surface-mouse! h 'move x y (drag-button d) 0))
           (let-values ([(lx ly) (window-local win x y)])
             (window-call win 'mouse-move lx ly)))]
        [(memq (drag-kind d) resize-kinds) (drag-resize! d x y)]
        [else (update-hover! x y)])))

  (define (drag-move! d x y)
    (let ([win (drag-win d)])
      (if (eq? (window-state win) 'maximized)
          ;; Tearing a maximized window off: restore it under the cursor.
          (when (> (+ (abs (- x (drag-mx d))) (abs (- y (drag-my d)))) 6)
            (let* ([frac (/ (- (drag-mx d) (window-x win))
                            (max 1 (window-w win)))])
              (restore-window! win)
              (let-values ([(l t r b) (frame-insets win)])
               (let ([nx (- x (* frac (window-w win)))] [ny (- y (/ t 2))])
                (move-window! win nx ny)
                (set! *drag* (make-drag 'move win 'left x y
                                        (window-x win) (window-y win) 0 0))))))
          (let-values ([(dx dy dw dh) (desktop-rect)])
            (drag-to! win
                      (clamp (+ (drag-x d) (- x (drag-mx d)))
                             (- (+ dx 80) (window-w win)) (- (+ dx dw) 80))
                      (clamp (+ (drag-y d) (- y (drag-my d)))
                             dy (- (+ dy dh) 20))
                      (window-w win) (window-h win))))))

  ;; Puts a dragged window where the drag takes it: there at once, or, with
  ;; drag-feedback outline, into the outline the desktop draws, until the
  ;; release puts the window there.
  (define (drag-to! win x y w h)
    (if (eq? (window-setting win 'drag-feedback) 'outline)
        (let ([old *drag-outline*])
          (set! *drag-outline* (list x y w h))
          (when old (apply request-frame! old))
          (request-frame! x y w h))
        (set-geometry! win x y w h)))

  ;; The sides that the drag's kind names follow the pointer, with the top
  ;; kept on the desktop as a move keeps it; the other sides stay.
  (define (drag-resize! d x y)
    (let*-values ([(win) (drag-win d)] [(left top dw dh) (desktop-rect)]
                  [(side?) (let ([k (string->list
                                     (symbol->string (drag-kind d)))])
                             (lambda (c) (memv c (list-tail k 7))))]
                  [(dx dy) (values (- x (drag-mx d)) (- y (drag-my d)))]
                  [(l t r b) (frame-insets win)]
                  [(nw) (max (+ l r (window-min-w win))
                             (cond [(side? #\r) (+ (drag-w d) dx)]
                                   [(side? #\l) (- (drag-w d) dx)]
                                   [else (drag-w d)]))]
                  [(nh) (max (+ t b (window-min-h win))
                             (cond [(side? #\b) (+ (drag-h d) dy)]
                                   [(side? #\t) (- (drag-h d)
                                                   (max dy (- top (drag-y d))))]
                                   [else (drag-h d)]))])
      (drag-to! win
                (if (side? #\l) (- (+ (drag-x d) (drag-w d)) nw) (drag-x d))
                (if (side? #\t) (- (+ (drag-y d) (drag-h d)) nh) (drag-y d))
                nw nh)))

  (define (wm-mouse-down x y button clicks . mods)
    (set! *mouse-x* x)
    (set! *mouse-y* y)
    (set! *mouse-button* button)
    (set! *mouse-mods* (if (pair? mods) (car mods) '()))
    (let ([h (screen-at x y)])
      (case (and h (car h))
        [(surface) (surface-mouse! h 'down x y button clicks)]
        [(window) (window-mouse-down (cadr h) x y button clicks)])))

  (define (window-mouse-down win x y button clicks)
    (let ([region (window-region win x y)])
      ;; The depth gadget decides about raising on release; a press in the
      ;; content raises where the style's raise-on-click says so.
      (unless (eq? region 'depth)
        (focus-window! win (or (not (eq? region 'content))
                               (window-setting win 'raise-on-click))))
      (case region
        ;; buttons act on release, and the window menu's on press; a
        ;; double click on a button may name an action of its own
        [(close minimize maximize depth shade menu)
         (cond
           [(and (>= clicks 2)
                 (assq region (window-setting win 'button-double-click)))
            => (lambda (a) (window-action! win (cdr a)))]
           [(eq? region 'menu) (window-menu! win x y)]
           [(eq? button 'left)
            (set! *drag* (make-drag region win button x y 0 0 0 0))
            (invalidate! win)])]   ; its style draws the button pressed
        [(frame) (void)]
        [(title)
         (cond
           [(eq? button 'right) (window-menu! win x y)]
           [(and (eq? button 'left) (>= clicks 2))
            (window-action! win (window-setting win 'title-double-click))]
           [(and (eq? button 'left) (not (window-own-action? win 'move)))
            (set! *drag* (make-drag 'move win button x y
                                    (window-x win) (window-y win) 0 0))
            (core0-set-cursor! 'move)])]
        [(content scrollbar)
         (cond
           [(window-error win)
            (when (eq? button 'left)
              (window-error-set! win #f)
              (invalidate! win))]
           [else
            ;; another button leaves a drag alone: the left one's release
            ;; ends it
            (unless (and *drag* (not (eq? button 'left)))
              (set! *drag* (make-drag 'capture win button x y 0 0 0 0)))
            (let-values ([(lx ly) (window-local win x y)])
              (window-call win 'mouse-down lx ly button clicks))])]
        [else
         (when (eq? button 'left)
           (set! *drag* (make-drag region win button x y
                                   (window-x win) (window-y win)
                                   (window-w win) (window-h win))))])))

  ;; Starts moving win with the pointer, as a left press on its title does:
  ;; a window with no frame (a desktop icon) moves by its content.
  (define (window-drag-move! win)
    (set! *drag* (make-drag 'move win 'left *mouse-x* *mouse-y*
                            (window-x win) (window-y win) 0 0))
    (core0-set-cursor! 'move))

  (define (wm-mouse-up x y button)
    (let ([d *drag*])
      (when d
        (let ([win (drag-win d)] [kind (drag-kind d)])
          (case kind
            [(close minimize maximize depth shade)
             (set! *drag* #f)
             (when (and (memq win *windows*)
                        (eq? (window-at x y) win)
                        (eq? (window-region win x y) kind))
               (window-action! win kind))]
            [(capture)
             (when (eq? button (drag-button d)) (set! *drag* #f))
             (let-values ([(lx ly) (window-local win x y)])
               (window-call win 'mouse-up lx ly button))]
            [else (set! *drag* #f)   ; a move or resize: its outline lands
                  (let ([o *drag-outline*])
                    (set! *drag-outline* #f)
                    (when o (apply set-geometry! win o)))])))
      (set! *mouse-button* #f)
      (let ([h (screen-at x y)])   ; a menu chooses on release, say
        (when (and h (eq? (car h) 'surface))
          (surface-mouse! h 'up x y button 1)))
      (update-hover! x y)
      (request-frame!)))

  ;; The wheel scrolls the window under the pointer, unless a surface over
  ;; it (a bar, an open menu) is there. On a title whose style's title-wheel
  ;; is shade, the wheel up shades the window and down unshades it.
  (define (wm-wheel dx dy)
    (let ([h (screen-at *mouse-x* *mouse-y*)])
      (when (and h (eq? (car h) 'window))
        (case (caddr h)
          [(content scrollbar) (window-call (cadr h) 'wheel dx dy)]
          [(title) (when (eq? (window-setting (cadr h) 'title-wheel) 'shade)
                     ((if (> dy 0) shade-window! unshade-window!)
                      (cadr h)))]))))

  ;;; ---------------------------------------------------------------- keyboard

  (define-state *global-keys* '())

  ;; (bind-key! '(ctrl shift #\w) close-focused-window!)
  (define (bind-key! spec proc)
    (set! *global-keys*
      (cons (cons spec proc)
            (remp (lambda (b) (equal? (car b) spec)) *global-keys*))))

  (define (unbind-key! spec)
    (set! *global-keys*
          (remp (lambda (b) (equal? (car b) spec)) *global-keys*)))

  (define (key-matches? spec key mods)
    (let ([rev (reverse spec)])
      (and (equal? (car rev) key)
           (let ([want (cdr rev)])
             (and (= (length want) (length mods))
                  (for-all (lambda (m) (memq m mods)) want))))))

  ;; Whether a surface takes the key or text (an open menu), topmost first.
  (define (surface-key! kind value mods)
    (exists (lambda (s) (surface-call s surface-key kind value mods))
            (reverse *surfaces*)))

  (define (wm-key-down key mods)
    (cond
      [(memq key '(ctrl shift alt super)) (void)]
      [(find (lambda (b) (key-matches? (car b) key mods)) *global-keys*)
       => (lambda (b)
            (safe-call 'key-binding (cdr b)
                       (lambda (c) (report-error! 'key-binding c))))]
      [(surface-key! 'key key mods)]
      [*focus* (window-call *focus* 'key key mods)]))

  (define (wm-text str)
    (cond
      [(surface-key! 'text str '())]
      [*focus* (window-call *focus* 'text str)]))

  ;;; ---------------------------------------------------------------- tick

  ;; Asks for win's 'frame handler, (lambda (win t) ...), to be called once,
  ;; before the next frame the window is seen in; t is when that frame shows
  ;; (pacer-frame-ns). A window that goes on animating asks again from its
  ;; 'frame. Asking draws nothing, so the flag isn't set with window-set!,
  ;; which would draw the window again.
  (define (window-frame-soon! win)
    (hashtable-set! (window-props win) 'wm-frame-soon #t)
    (frame-turn-soon!))

  ;; Calls the 'frame handlers that were asked for, each window's once. A
  ;; minimized window's waits until the window is seen again, and a crashed
  ;; one's until its error is cleared (its handlers don't run meanwhile), so
  ;; a window that rides frames pauses and then goes on. A tick in which no
  ;; window asked allocates nothing.
  (define (wm-frames! t)
    (let loop ([ws *windows*])
      (when (pair? ws)
        (let ([props (window-props (car ws))])
          (when (and (hashtable-ref props 'wm-frame-soon #f) (visible? (car ws))
                     (not (window-error (car ws))))
            (hashtable-set! props 'wm-frame-soon #f)
            (window-call (car ws) 'frame t)))
        (loop (cdr ws)))))

  ;; Runs the frames that windows asked for, then each surface's frame, in
  ;; depth order, before the frame is drawn, so that what a surface finds
  ;; changed (the mouse's documentation) shows in that frame.
  (set-hook! (wm-tick!)
    (let ([t (pacer-frame-ns)])
      (wm-frames! t)
      (for-each (lambda (s)
                  (safely (surface-name s)
                          (lambda () (surface-call s surface-frame t))))
                *surfaces*)))

  ;;; ---------------------------------------------------------------- drawing

  ;; window-hover returns the part of win under the mouse, and
  ;; window-pressed the kind of the drag that holds it, as the style sees
  ;; them (#f when none).
  (define (window-hover win)
    (and *hover* (eq? (car *hover*) 'window) (eq? (cadr *hover*) win)
         (caddr *hover*)))

  (define (window-pressed win)
    (and *drag* (eq? (drag-win *drag*) win) (drag-kind *drag*)))

  (define (draw-window* win focused?)
    (in-window-theme win
      (lambda ()
        (let ([x (window-x win)] [y (window-y win)]
              [w (window-w win)] [h (window-h win)]
              [hover (window-hover win)]
              [pressed (window-pressed win)])
          (unless (frameless? win)
            ((theme-part 'frame-under) win x y w h focused? hover pressed))
          (unless (shaded? win)
            (let-values ([(cx cy cw ch) (content-rect win)])
              (with-clip (x y w h (frame-radius win))
                (with-clip (cx cy cw ch)
                  (show-list (window-content-list win x y w h cx cy cw ch)
                             cx cy)))))
          (unless (frameless? win)
            ((theme-part 'frame-over) win x y w h focused? hover pressed))))))

  ;; Returns #t when the values e ... that one of win's lists is drawn with
  ;; changed since it was drawn, and keeps the new values. They are kept in
  ;; place, in a vector win keeps under name.
  (define-syntax window-key-changed!
    (syntax-rules ()
      [(_ win name e ...)
       (let ([k (window-own win name
                            (lambda () (make-vector (length '(e ...)) 'none)))])
         (window-key-check k 0 #f e ...))]))

  (define-syntax window-key-check
    (syntax-rules ()
      [(_ k i changed) changed]
      [(_ k i changed e rest ...)
       (let* ([v e]
              [c (if (equal? v (vector-ref k i))
                     changed
                     (begin (vector-set! k i v) #t))])
         (window-key-check k (+ i 1) c rest ...))]))

  ;; What a crashed window shows in place of its content until the desktop
  ;; gives its own panel ((schevana desktop crash)): the handler and the
  ;; condition, in a line of text, for a program with no desktop.
  (define (window-crash-line win w h)
    (let ([err (window-error win)])
      (draw-text 8 8 (format "The '~a handler raised: ~a" (car err)
                             (condition->string (cdr err)))
                 'red 'ui)))
  (at-load (theme-default! 'draw-crash-panel window-crash-line))

  ;; Returns win's content as a list drawn from the content's corner. It is
  ;; drawn again when win is asked to draw, or when its size, the scale or
  ;; its error changes, and it is clipped to the window's rounded box, which
  ;; a style may cut its corners with.
  (define (window-content-list win x y w h cx cy cw ch)
    (let ([l (window-own win 'wm-content-list gpu-list-new)])
      (when (window-key-changed! win 'wm-content-key
              *frame-generation* (hashtable-ref (window-props win) 'wm-asked 0)
              *rec-num* *rec-den* (- x cx) (- y cy) w h cw ch
              (window-error win))
        (record-list! l
          (lambda ()
            (with-clip ((- x cx) (- y cy) w h (frame-radius win))
              (with-clip (0 0 cw ch)
                (fill-box 0 0 cw ch (window-bg win))
                (if (window-error win)
                    ((theme-part 'draw-crash-panel) win cw ch)
                    (window-call win 'draw cw ch)))))))
      l))

  ;; Returns what win keeps under name, made by (make) the first time.
  (define (window-own win name make)
    (or (hashtable-ref (window-props win) name #f)
        (let ([v (make)])
          (hashtable-set! (window-props win) name v)
          v)))

  ;; The style draws the frame in two passes around the content, all in the
  ;; window's theme. draw-window is a hook made as the library loads, after
  ;; the definitions it reaches; made before them, it would have Chez check
  ;; at each call that those are defined.
  (define-hook (draw-window win) (draw-window* win (eq? win *focus*)))

  ;; Returns #t when a window above win, shown and with a frame, covers any
  ;; of it: a style may gray a window that is partly hidden (Genera's
  ;; deexposed ones), and win's frame is drawn again when that changes.
  (define (window-covered? win)
    (let loop ([ws *windows*])
      (and (pair? ws)
           (not (eq? (car ws) win))
           (or (let ([a (car ws)])
                 (and (visible? a) (not (frameless? a))
                      (< (window-x a) (+ (window-x win) (window-w win)))
                      (< (window-x win) (+ (window-x a) (window-w a)))
                      (< (window-y a) (+ (window-y win) (window-h win)))
                      (< (window-y win) (+ (window-y a) (window-h a)))))
               (loop (cdr ws))))))

  ;; Returns win as a list, drawn from its corner by draw-window. It is drawn
  ;; again when win is asked to draw, or when what its frame is drawn with
  ;; changes (whether it is covered too), but not when it moves.
  (define (window-whole-list win)
    (let ([l (window-own win 'wm-list gpu-list-new)])
      (when (window-key-changed! win 'wm-list-key
              *frame-generation* (hashtable-ref (window-props win) 'wm-asked 0)
              *rec-num* *rec-den* (eq? win *focus*) (window-hover win)
              (window-pressed win) (window-w win) (window-h win)
              (window-title win) (window-state win) (window-error win)
              (window-covered? win))
        (record-list! l
          (lambda ()
            (with-translation ((- (window-x win)) (- (window-y win)))
              (draw-window win)))))
      l))

  ;; Lets go of win's lists, on the GPU too.
  (define (window-lists-release! win)
    (for-each (lambda (name)
                (let ([l (window-ref win name)])
                  (when l
                    (gpu-list-release! l)
                    (hashtable-delete! (window-props win) name))))
              '(wm-list wm-content-list)))

  ;; Records the surfaces under the windows, or over them (over?).
  (define (record-surfaces! ss over?)
    (unless (null? ss)
      (let ([s (car ss)])
        (when (eq? (over-windows? s) over?)
          (with-label ((surface-name s))
            (record-safely (surface-name s)
                           (lambda () (surface-call s surface-draw))))))
      (record-surfaces! (cdr ss) over?)))

  ;; Records the windows from the bottom up: each one's list, shown at its
  ;; corner.
  (define (record-windows! ws)
    (unless (null? ws)
      (record-windows! (cdr ws))
      (let ([w (car ws)])
        (when (visible? w)
          (with-label ((window-title w))
            (record-safely
             'window
             (lambda ()
               (with-profile-span (window-id w) #f
                 (let-values ([(x y ew eh) (window-extent w)])
                   (let ([l (window-whole-list w)])
                     (with-clip (x y ew eh)
                       (show-list l (window-x w) (window-y w)))))))))))))

  ;; Records the whole screen as a list. A crashed draw leaves nothing to
  ;; unwind: the state it left goes when the next draw starts.
  (set-hook! (record-world!)
    (record-surfaces! *surfaces* #f)
    (record-windows! *windows*)
    (record-surfaces! *surfaces* #t))

  ;;; ------------------------------------------------------------------
  ;;; the screen's events

  ;; Passes an event of the screen's to the windows and the surfaces; the
  ;; loop hands each event here ((schevana core loop)).
  (set-hook! (wm-event! ev)
    (case (car ev)
      [(mouse-move) (apply wm-mouse-move (cdr ev))]
      [(mouse-down) (apply wm-mouse-down (cdr ev))]
      [(mouse-up) (apply wm-mouse-up (cdr ev))]
      [(wheel) (apply wm-wheel (cdr ev))]
      [(key-down) (apply wm-key-down (cdr ev))]
      [(text) (wm-text (cadr ev))]
      [(resize) (wm-screen-resized!)]
      [(expose) (request-frame!)]
      [(mouse-leave) (set! *hover* #f) (request-frame!)])))
