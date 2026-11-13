;;; wm.ss — the window manager.
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
;;; still takes the keyboard when it's given it, and the two are raised,
;;; minimized, brought back, sent behind and closed together.
;;;
;;; Handlers: open draw tick key text mouse-down mouse-up mouse-move wheel
;;;           resize focus blur close.
;;;
;;; The frame around the content (title bar, borders, buttons) belongs to
;;; the style, see theme.ss. Geometry here is the outer frame;
;;; 'size and the w h passed to handlers are always the content size.
;;; Every handler runs under safe-call: errors and runaway loops crash only
;;; that window, which then shows the error and can be retried.

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

(record-writer (record-type-descriptor window)
  (lambda (w p wr)
    (fprintf p "#<window ~a ~s ~ax~a+~a+~a~a>" (window-id w) (window-title w)
             (window-w w) (window-h w) (window-x w) (window-y w)
             (if (eq? (window-state w) 'normal)
                 ""
                 (format " ~a" (window-state w))))))

(define handler-kinds
  '(open draw frame key text mouse-down mouse-up mouse-move wheel resize focus
    blur close))

(defvar *windows* '())        ; z-order, topmost first
(defvar *focus* #f)
(defvar *next-window-id* 1)
;; what the next frame draws: #f, #t (the whole screen) or (x0 y0 x1 y1)
(defvar *dirty* #t)
(defvar *drag* #f)            ; the current mouse interaction, see drag record
(defvar *drag-outline* #f)    ; (x y w h): where an outline drag would put it
(defvar *hover* #f)
(defvar *mouse-x* 0)
(defvar *mouse-y* 0)
(defvar *mouse-button* #f)    ; the button held down, or #f
(defvar *cascade* 0)

(define-record-type drag
  (nongenerative schevana-drag)
  (fields kind win button mx my x y w h))

;;; ------------------------------------------------------------------
;;; invalidation
;;; A change says that the screen may now look different, in *dirty*: the
;;; next frame records the screen's surfaces again and draws it all. A
;;; window keeps what it drew, as a list, and draws again only when it
;;; opens or resizes, when what its frame is drawn with changes (its
;;; focus, the part under the mouse or held, its title, state or error),
;;; after it handles input, and when it's asked to:
;;;
;;;   (invalidate!)       anything may have changed: every window draws
;;;   (invalidate! win)   win may have (input to a window says so by itself)
;;;   (invalidate! win x y w h)   a part of it
;;;   (request-frame!), (request-frame! x y w h)   only where things are
;;;
;;; A window that changes by itself over time (a clock, an animation) says
;;; so with invalidate!. A window moved or raised isn't drawn again: the
;;; screen shows its list somewhere else.

;; the window whose handler is running
(defvar current-window (make-thread-parameter #f))
;; Told of each window that closes or crashes, to stop what works for it:
;; a hook a later layer sets (its background jobs, services/vat.ss).
(defvar *window-gone* void)

(define request-frame!
  (case-lambda
    [() (set! *dirty* #t)]
    [(x y w h) (when (and (> w 0) (> h 0)) (set! *dirty* #t))]))

;; Each (invalidate!) is a new generation, and each (invalidate! win) a new
;; ask of win's: a list of win's drawn before either is drawn again. Asked
;; while it draws, it draws again the next frame. A window not open (closed,
;; or one a preview draws) or not seen (minimized) asks for no frame: a
;; timer it left behind, or one an app steps on unseen, draws nothing; one
;; brought back is drawn as it comes.
(defvar *wm-generation* 0)

(define invalidate!
  (case-lambda
    [() (set! *wm-generation* (+ *wm-generation* 1)) (request-frame!)]
    [(win) (when win
             (hashtable-update! (window-props win) 'wm-asked
                                (lambda (n) (+ n 1)) 0))
           (when (or (not win) (and (memq win *windows*) (visible? win)))
             (request-frame!))]
    [(win x y w h) (invalidate! win)]))

;; A window's shadow, for its style: the theme key 'shadow, half unfocused;
;; a maximized window has none.
(define (window-shadow win x y w h r focused?)
  (unless (maximized? win)
    (draw-shadow x y w h r
                 (if focused? (theme 'shadow) (quotient (theme 'shadow) 2)))))

;; How far past its frame a window's shadow may reach, in whole logical
;; pixels: the focused size, and the third of it the shadow lies lower.
(define (window-shadow-reach win)
  (let ([size (theme 'shadow)])
    (if (maximized? win) 0 (+ size (quotient (+ size 2) 3)))))

;; How far past its frame a window may draw, never less than 0: its
;; style's frame-bleed. A style that strokes inside its frame needs none:
;; anti-aliasing stays in the device pixels the frame touches.
(define (window-bleed win)
  (if (eq? (window-theme win) *theme*)
      (window-bleed-here win)
      (in-window-theme win (lambda () (window-bleed-here win)))))

(define (window-bleed-here win)
  (max 0 (window-shadow-reach win) (frame-bleed win)))

;; What win may cover on screen, (values x y w h): its frame and bleed;
;; the whole screen if the bleed raises (a mistake typed at the REPL), so
;; that frames and input go on and it can be fixed.
(define (window-extent win)
  ;; the style's bleed alone guarded: one value, which a guard keeps
  ;; cheaper than four
  (let ([b (guard (c [#t (report-error! 'bleed c) #f]) (window-bleed win))])
    (if b
        (values (- (window-x win) b) (- (window-y win) b)
                (+ (window-w win) b b) (+ (window-h win) b b))
        (values 0 0 (screen-w) (screen-h)))))

(define (screen-w) *canvas-w*)
(define (screen-h) *canvas-h*)
(define (screen-scale) *scale*)   ; the screen's pixels to a logical one
;; A title's or a bar's height, key: the setting, grown to the room its
;; text needs (the setting min, named key-min) unless the style fixes
;; it, meaning its pixels; 0 is none. At the default fonts the text fits
;; every setting the Settings app offers.
(define (chrome-height key min)
  (let ([v (theme key)])
    (if (or (eqv? v 0) (memq key (theme 'fixed))) v (max v (theme min)))))

(theme-default! 'title-height-min
                (theme-rule (exact (round (+ (font-line-height 'title) 7)))))
(define (title-height) (chrome-height 'title-height 'title-height-min))

(define (point-in? px py x y w h)
  (and (>= px x) (< px (+ x w)) (>= py y) (< py (+ y h))))

;;; ------------------------------------------------------------------
;;; surfaces
;;; What the window manager draws and routes besides windows: the desktop
;;; under them (depth below 0), bars, menus and toasts over them, in depth
;;; order. They are the desktop layer's (desktop/); the core names none of
;;; its procedures. Each field is a procedure, or the name of one looked
;;; up at each call, so the desktop layer's procedures stay redefinable.

(define-record-type surface
  (nongenerative schevana-surface-3)
  (fields name depth
          draw    ; ()                           draws it
          box     ; () -> (values x y w h)       what it covers this frame
          at      ; (x y) -> what, or #f         what is there; #f lets
                  ;                              the point through
          mouse   ; (kind what x y button clicks)    kind: down up move
          key     ; (kind value mods) -> #t if taken; kind: key or text
          frame   ; (t)                          each frame, before it's
                  ;                              drawn: what changed
          doc))   ; (what) -> ((L . "Apps") ...)  its mouse documentation

(defvar *surfaces* '())   ; by depth
(set! *surfaces* (filter surface? *surfaces*))

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
    (apply (if (symbol? v) (top-level-value v *world-env*) v) args)))

(define (over-windows? s) (>= (surface-depth s) 0))

;; What s covers this frame, in device pixels (x0 y0 x1 y1).
;;; strips
;; (define-strip topbar 'top 'topbar-height): the area windows go in loses
;; (topbar-height) pixels at the top; strips on one edge add up.
(defvar *strips* '())   ; ((name edge . size) ...)

(define (register-strip! name edge size)
  (set! *strips* (registry-add *strips* (cons* name edge size) car))
  (wm-screen-resized!)
  name)

(define-syntax define-strip
  (syntax-rules ()
    [(_ name edge size) (register-strip! 'name edge size)]))

;; Where windows go (maximized, tiled, kept on screen): the screen less
;; every strip.
(define (desktop-rect)
  (define (edge e)
    (apply + (map (lambda (s)
                    (if (eq? (cadr s) e)
                        (let ([n (cddr s)])
                          ((if (symbol? n) (top-level-value n *world-env*) n)))
                        0))
                  *strips*)))
  (let ([t (edge 'top)] [b (edge 'bottom)] [l (edge 'left)]
        [r (edge 'right)])
    (values l t (- (screen-w) l r) (- (screen-h) t b))))

;;; ------------------------------------------------------------------ apps

(define-record-type app
  (nongenerative schevana-app)
  (fields name title launch))

(defvar *apps* '())
(defvar current-app (make-thread-parameter #f))

(define (register-app! name title launch)
  (set! *apps* (registry-add *apps* (make-app name title launch) app-name))
  (request-frame!))

;; (define-app (name) "Title" body ...) defines an ordinary procedure that
;; opens the app, and registers it with the launcher.
(define-syntax define-app
  (syntax-rules ()
    [(_ (name . args) title body ...)
     (begin
       (define (name . args) (parameterize ([current-app 'name]) body ...))
       (register-app! 'name title (lambda () (name))))]))

(define (apps) (map app-name *apps*))

;;; ------------------------------------------------------------------ windows

(define (open-window title . opts)
  (let ([win (apply detached-window title opts)])
    (set! *next-window-id* (+ *next-window-id* 1))
    (place-window! win (plist-ref opts 'pos #f))
    (set! *windows* (cons win *windows*))
    (window-call win 'open)
    (focus-window! win)
    win))

;; A window as open-window makes it, at 0, 0, but not on screen: a
;; style's miniature (Settings' previews) draws one with draw-window*.
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
(defvar new-window-position (make-thread-parameter #f))

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
            (window-y-set! win (clamp (cdr at) dy
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

;; An app's window, by its name, is its own before one opened above another.
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
  (hashtable-ref (window-props win) key (if (null? default) #f (car default))))

;; The window is drawn again, as invalidate! asks: a frame if it's seen.
(define (window-set! win key val)
  (hashtable-set! (window-props win) key val)
  (invalidate! win))

(define (window-on! win kind proc)
  (hashtable-set! (window-handlers win) kind proc)
  (window-error-set! win #f)
  (invalidate! win))

(define (window-bg win) (window-ref win 'bg 'window-bg))

;; The theme win is drawn and hit-tested in, content included: its own
;; style's (its 'window-style property, a style's name; the one in effect
;; if it is that style, a preview's), else the chosen style's.
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
                      (lambda () (when (eq? *theme* t) (set! *theme* main)))))))

;; Calls win's frame part key (theme.ss) in win's theme: as it is, when
;; it's the one on, with no closure.
(define (frame-call win key . args)
  (if (eq? (window-theme win) *theme*)
      (apply (theme-part key) win args)
      (in-window-theme win (lambda () (apply (theme-part key) win args)))))

;; A setting in win's theme: its own style's, or the chosen one's.
(define (window-setting win key) (in-window-theme win (lambda () (theme key))))

;; Frame thickness around the content: (values left top right bottom).
(define (frame-insets win) (frame-call win 'frame-insets))
(define (frame-regions win) (frame-call win 'frame-regions))
(define (frame-radius win) (frame-call win 'frame-radius))
(define (frame-bleed win) (frame-call win 'frame-bleed))

;; Content area in screen coordinates.
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

;; The whole screen: a handler stopped partway may have left shared state
;; (focus, order, titles) half changed.
(define (window-crash! win kind c)
  (window-error-set! win (cons kind c))
  (*window-gone* win)
  (invalidate!))

;; The window win waits on, its 'modal-child while that is open (a
;; dialog: ui-open-modal), or #f. Where win's style keeps it above
;; (modal-above), it takes win's keyboard: focusing win focuses it, and
;; raising win raises it above.
(define (window-modal-child win)
  (let ([c (window-ref win 'modal-child)]) (and c (memq c *windows*) c)))

(define (window-modal-above win)
  (and (window-setting win 'modal-above) (window-modal-child win)))

;; The window win was opened above ('above), while it's open, or #f; the
;; windows opened above win, the lowest first.
(define (window-owner win)
  (let ([o (window-ref win 'above)]) (and o (memq o *windows*) o)))

(define (window-owned win)
  (reverse (filter (lambda (w) (eq? (window-owner w) win)) *windows*)))

;; The owner its owners lead up to: what moves win.
(define (window-root win)
  (let ([o (window-owner win)]) (if o (window-root o) win)))

;; Gives win the keyboard and brings it to the front (raise? #f: not); a
;; window that waits on another above it gives it the keyboard.
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

;; Back from minimized, and the windows it owns with it.
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

;; The windows it owns, and the one waiting on it, go with it.
(define (close-window! win)
  (when (memq win *windows*)
    (for-each close-window! (window-owned win))
    (let ([c (window-modal-child win)]) (when c (close-window! c)))
    (window-call win 'close)
    (set! *windows* (remq win *windows*))
    (window-lists-release! win)
    (*window-gone* win)
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
;; then asks for the old extent and the new one. Asked for before the
;; change, the old one could go to a frame drawn while a process is
;; switched out, the window still there, and stay on screen.
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
    ;; moved, it isn't drawn again: the screen shows its list elsewhere
    (if resized? (invalidate! win) (request-frame!))))

(define (move-window! win x y)
  (set-geometry! win x y (window-w win) (window-h win)))

;; Resizes the content area to w x h.
(define (resize-window! win w h)
  (let-values ([(l t r b) (frame-insets win)])
    (set-geometry! win (window-x win) (window-y win) (+ w l r) (+ h t b))))

;; What a 'depth button does (the Amiga's depth gadget): send the front
;; window to the back, or bring a window that is behind others to the front;
;; an owner and the windows above it as one.
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

;; What an action a style's setting names does to win (a double click's):
;; maximize, shade, minimize, close; any other nothing.
(define (window-action! win action)
  (case action
    [(maximize) (toggle-maximize! win)]
    [(shade) (toggle-shade! win)]
    [(minimize) (minimize-window! win)]
    [(close) (close-window! win)]))

;; A shaded window shows only its frame's top and bottom (the insets its
;; frame gives while shaded); its content is not drawn and its app hears
;; no resize. Its height waits in a property, as the record keeps.
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

;; The host window was resized.
;; The screen changed size (or scale): refit maximized windows, and pull
;; others back until their title bar can be reached.
(define (wm-screen-resized!)
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

;; The style or title height changed: frames keep their outer size, so
;; every app hears its new content size, a shaded one what it unshades to.
(define (wm-chrome-changed!)
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

;; Which part of the window is at screen point (x, y)? Its style's
;; regions, then the window manager's resize edges, 'frame-edge wide
;; (0: none) with corners 'frame-corner long, the title, the content.
(define (window-region win x y)
  (let*-values ([(lx) (- x (window-x win))] [(ly) (- y (window-y win))]
                [(w) (window-w win)] [(h) (window-h win)]
                [(l t r b) (frame-insets win)]
                [(edge) (window-setting win 'frame-edge)]
                [(corner) (window-setting win 'frame-corner)]
                [(free?) (and (eq? (window-state win) 'normal)
                              (not (shaded? win)))]   ; it may resize
                [(resizable?) (and free? (> edge 0))])
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

;;; ------------------------------------------------------------------ mouse

;; What is at screen point (x, y): (surface name what) from the topmost
;; surface over windows that answers, else (window win region), else
;; (surface name what) from one under them; #f where nothing is.
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
    (host-set-cursor!
     (if (and h (eq? (car h) 'window))
         (region-cursor (cadr h) (caddr h))
         'arrow))))

;; Asks for what shows the hover h: a window's extent, a surface's box;
;; nothing for a surface under the windows (the desktop draws no hover).
(define (request-hover-frame! h)
  (case (and (pair? h) (car h))
    [(window) (invalidate! (cadr h))]
    [(surface)
     (let ([s (find-surface (cadr h))])
       (when (and s (over-windows? s))
         (call-with-values (lambda () (surface-call s surface-box))
           request-frame!)))]))

;; The surface of the hover h (surface name what) acts on the mouse.
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

;; Where a drag puts its window: there at once, or (drag-feedback outline)
;; in the outline the desktop draws within it, until the release does.
(define (drag-to! win x y w h)
  (if (eq? (window-setting win 'drag-feedback) 'outline)
      (let ([old *drag-outline*])
        (set! *drag-outline* (list x y w h))
        (when old (apply request-frame! old))
        (request-frame! x y w h))
      (set-geometry! win x y w h)))

;; The sides the drag's kind names follow the pointer, the top kept on the
;; desktop as a move keeps it; the others stay.
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

(define (wm-mouse-down x y button clicks)
  (set! *mouse-x* x)
  (set! *mouse-y* y)
  (set! *mouse-button* button)
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
      ;; buttons act on release, the window menu's on press; a double
      ;; click on one may name an action of its own
      [(close minimize maximize depth shade menu)
       (cond
         [(and (>= clicks 2)
               (assq region (window-setting win 'button-double-click)))
          => (lambda (a) (window-action! win (cdr a)))]
         [(eq? region 'menu) ((theme-part 'open-window-menu) win x y)]
         [(eq? button 'left)
          (set! *drag* (make-drag region win button x y 0 0 0 0))
          (invalidate! win)])]   ; its style draws the button pressed
      [(frame) (void)]
      [(title)
       (cond
         [(eq? button 'right) ((theme-part 'open-window-menu) win x y)]
         [(and (eq? button 'left) (>= clicks 2))
          (window-action! win (window-setting win 'title-double-click))]
         [(eq? button 'left)
          (set! *drag* (make-drag 'move win button x y
                                  (window-x win) (window-y win) 0 0))
          (host-set-cursor! 'move)])]
      [(content scrollbar)
       (cond
         [(window-error win)
          (when (eq? button 'left)
            (window-error-set! win #f)
            (invalidate! win))]
         [else
          ;; another button leaves a drag alone: the left's release ends it
          (unless (and *drag* (not (eq? button 'left)))
            (set! *drag* (make-drag 'capture win button x y 0 0 0 0)))
          (let-values ([(lx ly) (window-local win x y)])
            (window-call win 'mouse-down lx ly button clicks))])]
      [else
       (when (eq? button 'left)
         (set! *drag* (make-drag region win button x y
                                 (window-x win) (window-y win)
                                 (window-w win) (window-h win))))])))

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
             (case kind
               [(close) (close-window! win)]
               [(minimize) (minimize-window! win)]
               [(maximize) (toggle-maximize! win)]
               [(depth) (depth-window! win)]
               [(shade) (toggle-shade! win)]))]
          [(capture)
           (when (eq? button (drag-button d)) (set! *drag* #f))
           (let-values ([(lx ly) (window-local win x y)])
             (window-call win 'mouse-up lx ly button))]
          [else (set! *drag* #f)   ; a move or resize: an outline lands
                (let ([o *drag-outline*])
                  (set! *drag-outline* #f)
                  (when o (apply set-geometry! win o)))])))
    (set! *mouse-button* #f)
    (let ([h (screen-at x y)])   ; a menu chooses on release, say
      (when (and h (eq? (car h) 'surface)) (surface-mouse! h 'up x y button 1)))
    (update-hover! x y)
    (request-frame!)))

;; The window under the pointer scrolls, unless a surface over it (a bar,
;; an open menu) is there; on a title whose style's title-wheel is shade,
;; the wheel up shades and down unshades.
(define (wm-wheel dx dy)
  (let ([h (screen-at *mouse-x* *mouse-y*)])
    (when (and h (eq? (car h) 'window))
      (case (caddr h)
        [(content scrollbar) (window-call (cadr h) 'wheel dx dy)]
        [(title) (when (eq? (window-setting (cadr h) 'title-wheel) 'shade)
                   ((if (> dy 0) shade-window! unshade-window!) (cadr h)))]))))

;;; ------------------------------------------------------------------ keyboard

(defvar *global-keys* '())

;; (bind-key! '(ctrl shift #\w) close-focused-window!)
(define (bind-key! spec proc)
  (set! *global-keys*
    (cons (cons spec proc)
          (remp (lambda (b) (equal? (car b) spec)) *global-keys*))))

(define (unbind-key! spec)
  (set! *global-keys* (remp (lambda (b) (equal? (car b) spec)) *global-keys*)))

(define (key-matches? spec key mods)
  (let ([rev (reverse spec)])
    (and (equal? (car rev) key)
         (let ([want (cdr rev)])
           (and (= (length want) (length mods))
                (for-all (lambda (m) (memq m mods)) want))))))

;; Does a surface take the key or text (an open menu), topmost first?
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

;;; ------------------------------------------------------------------ tick

;; Asks for win's 'frame, (lambda (win t) ...), once, before the next frame
;; it's seen in: t is when that frame shows (pacer-frame-ns). A window that
;; goes on animating asks again from its 'frame. Asking draws nothing, so
;; the flag isn't set by window-set!, which would draw the window again.
(define (window-frame-soon! win)
  (hashtable-set! (window-props win) 'wm-frame-soon #t)
  (frame-turn-soon!))

;; The frames asked for, each window's once; a minimized window's wait
;; until it's seen again, so one that rides frames pauses meanwhile. A
;; tick no window asked in allocates nothing.
(define (wm-frames! t)
  (let loop ([ws *windows*])
    (when (pair? ws)
      (let ([props (window-props (car ws))])
        (when (and (hashtable-ref props 'wm-frame-soon #f) (visible? (car ws)))
          (hashtable-set! props 'wm-frame-soon #f)
          (window-call (car ws) 'frame t)))
      (loop (cdr ws)))))

;; The frames windows asked for, then each surface's, in depth order,
;; before the frame is drawn: what it finds changed (the mouse's
;; documentation) shows in it.
(define (wm-tick!)
  (let ([t (pacer-frame-ns)])
    (wm-frames! t)
    (for-each (lambda (s)
                (safely (surface-name s)
                        (lambda () (surface-call s surface-frame t))))
              *surfaces*)))

;;; ------------------------------------------------------------------ drawing

;; The style draws the frame in two passes around the content, all in the
;; window's theme.
(define (draw-window win) (draw-window* win (eq? win *focus*)))

;; The part of win under the mouse, and the drag kind holding it, as the
;; style sees them (#f when none).
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
        ((theme-part 'frame-under) win x y w h focused? hover pressed)
        (unless (shaded? win)
          (let-values ([(cx cy cw ch) (content-rect win)])
            (with-clip (x y w h (frame-radius win))
              (with-clip (cx cy cw ch)
                (show-list (window-content-list win x y w h cx cy cw ch)
                           cx cy)))))
        ((theme-part 'frame-over) win x y w h focused? hover pressed)))))

;; Whether what a list of win's is drawn with, the values e ..., changed
;; since it was drawn, kept by name in place: => #t, and the new values
;; kept.
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

;; win's content, as a list from the content's corner, drawn again when win
;; is asked to draw, or when its size, the scale or its error changes; inside
;; the window's rounded box, which a style may cut its corners with.
(define (window-content-list win x y w h cx cy cw ch)
  (let ([l (window-own win 'wm-content-list gpu-list-new)])
    (when (window-key-changed! win 'wm-content-key
            *wm-generation* (hashtable-ref (window-props win) 'wm-asked 0)
            *rec-num* *rec-den* (- x cx) (- y cy) w h cw ch (window-error win))
      (record-list! l
        (lambda ()
          (with-clip ((- x cx) (- y cy) w h (frame-radius win))
            (with-clip (0 0 cw ch)
              (fill-box 0 0 cw ch (window-bg win))
              (if (window-error win)
                  ((theme-part 'draw-crash-panel) win cw ch)
                  (window-call win 'draw cw ch)))))))
    l))

;; What win keeps under name, made by (make) the first time.
(define (window-own win name make)
  (or (hashtable-ref (window-props win) name #f)
      (let ([v (make)])
        (hashtable-set! (window-props win) name v)
        v)))

;; win as a list from its corner: draw-window's, drawn again when win is
;; asked to draw or what its frame is drawn with changes; moved, it isn't.
(define (window-whole-list win)
  (let ([l (window-own win 'wm-list gpu-list-new)])
    (when (window-key-changed! win 'wm-list-key
            *wm-generation* (hashtable-ref (window-props win) 'wm-asked 0)
            *rec-num* *rec-den* (eq? win *focus*) (window-hover win)
            (window-pressed win) (window-w win) (window-h win)
            (window-title win) (window-state win) (window-error win))
      (record-list! l
        (lambda ()
          (with-translation ((- (window-x win)) (- (window-y win)))
            (draw-window win)))))
    l))

;; Its lists let go of, on the GPU too.
(define (window-lists-release! win)
  (for-each (lambda (name)
              (let ([l (window-ref win name)])
                (when l
                  (gpu-list-release! l)
                  (hashtable-delete! (window-props win) name))))
            '(wm-list wm-content-list)))

;; the last frame's time: its work, not its wait for the screen
(defvar *frame-ms* 0.0)
(defvar *frames-drawn* 0)
;; the newest frame core0 gave back: sent, or found no room
(defvar *frame-back* 0)

;; The whole screen, as a list. A crashed draw leaves nothing to unwind: the
;; state it left goes when the next one starts.
(define (record-world!)
  (record-surfaces! *surfaces* #f)
  (record-windows! *windows*)
  (record-surfaces! *surfaces* #t))

;; The surfaces under the windows, or over them.
(define (record-surfaces! ss over?)
  (unless (null? ss)
    (let ([s (car ss)])
      (when (eq? (over-windows? s) over?)
        (with-label ((surface-name s))
          (record-safely (surface-name s)
                         (lambda () (surface-call s surface-draw))))))
    (record-surfaces! (cdr ss) over?)))

;; The windows from the bottom up: each one's list, shown at its corner.
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

;; thunk's drawing, which may crash: what it left of the recorder's state
;; goes, the state as it was kept in variables.
(define (record-safely name thunk)
  (let ([num *rec-num*] [den *rec-den*] [ox *rec-ox*] [oy *rec-oy*]
        [turn *rec-turn*] [clip *rec-clip*] [cx0 *rec-cx0*] [cy0 *rec-cy0*]
        [cx1 *rec-cx1*] [cy1 *rec-cy1*])
    (safely name thunk)
    (rec-state-restore! num den ox oy turn clip cx0 cy0 cx1 cy1)))

;; One step's frame: recorded and sent to the screen. A screen with no room
;; for it yet asks again. A process may be switched out at any call while the
;; main loop draws on, so typed in a REPL (a process) or called by a handler,
;; (render-frame!) only asks for a frame.
(define render-frame!
  (case-lambda
    [() (render-frame! #t)]
    [(asked?)
     (cond
       [(or (not asked?) (eq? *host* 'none) (eqv? *canvas-pw* 0)) (void)]
       [(in-engine?) (request-frame!)]
       [(or (host-hidden?) (gpu-frame-waiting?)) (request-frame!)]
       [else
        (let ([t0 (now-ns)] [waits *pacer-waits*])
          (host-trace! 23 0)
          (set! *frame-draw-ns* t0)
          (rec-begin! *canvas-ratio*)
          (record-world!)
          (frame-number-set! (rec-present!))
          (pacer-drew!)
          (set! *frame-publish-ns* (now-ns))
          (host-trace! 24 *frame-number*)
          ;; its row first, for core0 may give it back at once
          (frame-ring-add!)
          (render-frames-back!)
          (set! *frame-ms* (fl/ (fixnum->flonum
                                 (- (now-ns) t0 (- *pacer-waits* waits)))
                                1e6))
          (frame-ring-set! *frame-number* 0
                           (flonum->fixnum
                            (flround (fl* 1000.0 *frame-ms*)))))])]))

;; The frames core0 gave back: each told to the pacer, and marked in its row
;; as having reached the screen or not; counted if it did, else one asked
;; again. Then what core0 read back, handed to its then.
(define (render-frames-back!)
  (for-each (lambda (f)
              (let ([shown? (gpu-frame-shown? f)])
                (set! *frame-back* (gpu-frame-number f))
                (pacer-frame-back! shown?)
                (pacer-latch! (gpu-frame-number f))
                (frame-ring-set! (gpu-frame-number f) 5 (if shown? 1 2))
                (if shown?
                    (set! *frames-drawn* (+ *frames-drawn* 1))
                    (request-frame!))
                (gpu-frame-free! f)))
            (gpu-frames-back!))
  (for-each (lambda (answer)
              (safely 'readback (lambda () ((car answer) (cdr answer)))))
            (gpu-take-answers!)))

;; The last frames, for kits/inspect.ss: what each took and held, and what
;; became of it (1 it reached the screen, 2 the window had no room, 0 not
;; given back yet); its number (its report's, host-frame-report), and when
;; the oldest input it shows came (now-ns; 0, none) by SDL's stamp; then
;; when its tick began, its draw began and it was published, and when that
;; input came by core0's pump and by the compositor's time; the latch its
;; tick aimed at (0, none), and when the pacer meant its tick to begin.
;; Always kept: a few numbers a frame, for as many frames as the reports
;; keep.
(define frame-ring-rows 2048)
(define frame-ring-words 15)
(defvar *frame-ring* (make-fxvector (* frame-ring-rows frame-ring-words) 0))
(defvar *frame-ring-n* 0)   ; frames so far
;; the frame being drawn's number, its times, and the oldest input not
;; drawn yet three ways (host-input-ns-take!)
(defvar *frame-number* 0)
(defvar *frame-tick-ns* 0)
(defvar *frame-draw-ns* 0)
(defvar *frame-publish-ns* 0)
(defvar *frame-input-ns* 0)
(defvar *frame-input-pumped* 0)
(defvar *frame-input-wl* 0)

(define (frame-number-set! n) (set! *frame-number* n))
;; The tick began at now (now-ns), or, unpaced, its ms: the pacer's read.
(define (frame-ticked! now)
  (set! *frame-tick-ns* (or now (* *pacer-tick-ms* 1000000))))

;; Input came (now-ns; 0, none), by SDL's stamp, core0's pump and the
;; compositor: the next frame shows it, if no older input waits.
(define (frame-input-came! ns pumped wl)
  (unless (or (eqv? ns 0) (not (eqv? *frame-input-ns* 0)))
    (set! *frame-input-ns* ns))
  (unless (or (eqv? pumped 0) (not (eqv? *frame-input-pumped* 0)))
    (set! *frame-input-pumped* pumped))
  (unless (or (eqv? wl 0) (not (eqv? *frame-input-wl* 0)))
    (set! *frame-input-wl* wl)))

;; Input that asked for no frame: no frame shows it.
(define (frame-input-drop!)
  (set! *frame-input-ns* 0)
  (set! *frame-input-pumped* 0)
  (set! *frame-input-wl* 0))

(define (frame-ring-add!)
  (let ([at (* frame-ring-words (modulo *frame-ring-n* frame-ring-rows))]
        [ring *frame-ring*])
    (fxvector-set! ring (+ at 6) *frame-number*)
    (fxvector-set! ring (+ at 7) *frame-input-ns*)
    (fxvector-set! ring (+ at 8) *frame-tick-ns*)
    (fxvector-set! ring (+ at 9) *frame-draw-ns*)
    (fxvector-set! ring (+ at 10) *frame-publish-ns*)
    (fxvector-set! ring (+ at 11) *frame-input-pumped*)
    (fxvector-set! ring (+ at 12) *frame-input-wl*)
    (fxvector-set! ring (+ at 13) *pacer-aimed*)
    (fxvector-set! ring (+ at 14) *pacer-planned*)
    (frame-input-drop!)
    (fxvector-set! ring at 0)
    ;; the frame's, published: the recorder writes nothing now
    (let-values ([(recs-n extras-n) (rec-last-sizes)])
      (fxvector-set! ring (+ at 1) (fxquotient recs-n 32))
      (fxvector-set! ring (+ at 2) (fxquotient extras-n 4)))
    (fxvector-set! ring (+ at 3) (length (rec-runs)))
    (fxvector-set! ring (+ at 4) *glyph-count*)
    (fxvector-set! ring (+ at 5) 0))
  (set! *frame-ring-n* (+ *frame-ring-n* 1)))

;; Where frame n's row starts, among the newest sixteen, which hold every
;; frame not given back or judged yet; else #f.
(define (frame-ring-at n)
  (let loop ([i (- *frame-ring-n* 1)] [j 0])
    (and (< j 16) (>= i 0)
         (let ([at (* frame-ring-words (modulo i frame-ring-rows))])
           (if (eqv? (fxvector-ref *frame-ring* (+ at 6)) n)
               at
               (loop (- i 1) (+ j 1)))))))

;; Word k of frame n's row set to v, while the ring has it.
(define (frame-ring-set! n k v)
  (let ([at (frame-ring-at n)])
    (when at (fxvector-set! *frame-ring* (+ at k) v))))

;; The screen as it would be drawn now: its pixels, row after row,
;; premultiplied BGRA. What tests and screenshots see; screen-bytes-then
;; hands them to then on main, nothing waiting.
(define (screen-bytes)
  (drawing->bytes *canvas-pw* *canvas-ph* *canvas-ratio* record-world! #f))

(define (screen-bytes-then then)
  (drawing->bytes-then *canvas-pw* *canvas-ph* *canvas-ratio* record-world! #f
                       then))
