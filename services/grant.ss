;;; services/grant.ss — apps in sandboxes. An app outside the world runs in
;;; an environment of its own, /apps/<name>, on the confined base
;;; (services/env.ss), holding of the world's names only the bundles it
;;; requests and someone approved:
;;;
;;;   ;;; apps/weather.ss — today's weather in a window.
;;;   (app-requests window draw timers)       its first form
;;;   (define-app (weather) "Weather" ...)
;;;
;;; A bundle is a titled list of the world's names ("Draw in its windows":
;;; fill-box, draw-text ...). The tree's apps are approved by a table
;;; here (grant-tree-apps); the others by the person, whose decisions are
;;; kept in *grant-file-path* (main.ss reads it; tests point it at a
;;; scratch file). A bundle requested and not approved is there as stubs,
;;; which raise a &grant-needed naming it; a name in no requested bundle
;;; is unbound. A tree app that requests nothing (no app-requests form) is
;;; the world's own and loads there: Settings, Monitor, Tasks, the REPL,
;;; Environments.
;;;
;;; Every app holds define-app, which registers only the app named after
;;; its file, app-requests, which does nothing (the loader read it), and
;;; defvar, which asks its own sandbox; a window it opens is its own
;;; (window-app) or no app's, never another's. The world's (clock) still
;;; opens Clock: it forwards to the sandbox's launcher.

;;; ------------------------------------------------------------------ bundles

;; (bundle title name ...): what an app requests, as the person sees it
;; and as its sandbox holds it, the world's names.
(define grant-bundles
  '((window "Open windows"
     open-window
     close-window!
     invalidate!
     window-frame-soon!
     resize-window!
     move-window!
     focus-window!
     desktop-rect
     content-rect
     window-content-size
     window-x
     window-y
     window-w
     window-h
     shaded?
     window-ref
     window-set!
     window-call
     window-title
     window-title-set!)
    (draw "Draw in its windows"
     fill-box
     stroke-box
     draw-text
     draw-line
     draw-polyline
     fill-polygon
     fill-circle
     stroke-circle
     fill-glow
     fill-gradient
     with-clip
     with-translation
     with-scale
     with-turn
     with-label
     theme
     rgb
     alpha
     mix
     color->pixel
     screen-scale
     linear-gradient
     radial-gradient
     pi
     text-width
     text-widest
     text-within
     text-fit
     text-wrap
     text-draw-centered
     font-line-height
     font-char-width
     font-ascent
     font-descent
     make-pixmap
     make-pixmap-bytevector
     pixmap-from-bytevector
     pixmap?
     pixmap-w
     pixmap-h
     pixmap-bytes
     pixmap-ref
     pixmap-set!
     pixmap-set-pixel!
     pixmap-fill!
     pixmap-load!
     pixmap-swap-bytes!
     pixmap-draw)
    (ui "Use buttons, sliders and fields"
     make-ui
     ui-begin!
     ui-end!
     ui-handlers
     ui-frame
     ui-area
     ui-side-panel
     ui-side-panel-button
     ui-side-panel-open?
     ui-side-panel-toggle!
     ui-pad
     ui-gap
     ui-control-height
     ui-slider-height
     ui-draw-surface
     ui-draw-label
     ui-label-size
     ui-button
     ui-button-size
     ui-slider
     ui-checkbox
     ui-checkbox-size
     ui-toggle
     ui-text-field)
    (timers "Run on a timer"
     after
     now-ms
     now-ns
     current-date)
    (crew "Compute on worker threads"
     define-worklet
     worklet
     crew-for
     crew-for*
     crew-map
     crew-size
     crew-size-set!
     host-cpu-count)
    ;; a shader touches only the buffers it's handed (src/shader.ss), and
    ;; nothing here waits for the GPU
    (gpu "Compute and draw on the GPU"
     define-compute-shader
     define-paint
     fill-shader
     draw-scale
     make-gpu-buffer
     gpu-buffer-set!
     gpu-buffer-release!
     gpu-compute-soon!)
    (toasts "Show notifications"
     notify)
    (launch "Open other apps"
     apps
     app-launch!)))

(define (grant-bundle-title b)
  (let ([x (assq b grant-bundles)]) (if x (cadr x) (symbol->string b))))

(define (grant-bundle-names b)
  (let ([x (assq b grant-bundles)]) (if x (cddr x) '())))

;; The bundle holding the world's name n, or #f; a name is in one
;; (tests/sources.ss).
(define (grant-bundle-of n)
  (let ([x (find (lambda (x) (memq n (cddr x))) grant-bundles)])
    (and x (car x))))

;; What the tree's apps are approved: (app bundle ...). A test checks each
;; tree app's requests against it, so a new request is a reviewed change.
;; Sketch is not here: the person approves it, as an app of their own.
(define grant-tree-apps
  '((boids window draw ui timers crew)
    (boids3d window draw ui timers gpu)
    (clock window draw timers)
    (life window draw ui timers crew)))

;;; ------------------------------------------------------------------ decisions
;;; The person's, kept in a file of plain data, one app a form:
;;;   (app-permissions sketch
;;;     approved (window draw)
;;;     denied ())

(defvar *grant-file-path* (string-append user-directory "/permissions.ss"))

;; app: (approved . denied)
(defvar *grant-decisions* (make-eq-hashtable))

;; What app is approved and denied, as (values approved denied): the
;; table's for a tree app on it, else the person's.
(define (grant-of app)
  (let ([t (assq app grant-tree-apps)]
        [d (hashtable-ref *grant-decisions* app '(() . ()))])
    (if t (values (cdr t) '()) (values (car d) (cdr d)))))

;; Whether the person decides for app: not for one on the table.
(define (grant-asks? app) (not (assq app grant-tree-apps)))

;; How app's request b stands: allowed, denied or undecided.
(define (grant-state app b)
  (let-values ([(ok no) (grant-of app)])
    (cond [(memq b ok) 'allowed]
          [(memq b no) 'denied]
          [else 'undecided])))

;; What app requests that no one decided yet.
(define (grant-undecided app)
  (let-values ([(ok no) (grant-of app)])
    (remp (lambda (b) (or (memq b ok) (memq b no))) (grant-requested app))))

;; The person's decision on bundles of app's: approved, denied; the others
;; as they were. Saved, and app's sandbox made again with it.
(define (grant-decide! app approved denied)
  (let-values ([(ok no) (grant-of app)])
    (let ([keep (lambda (l) (remp (lambda (b) (or (memq b approved)
                                                  (memq b denied)))
                                  l))])
      (hashtable-set! *grant-decisions* app
                      (cons (append (keep ok) approved)
                            (append (keep no) denied)))))
  (grant-file-save!)
  (grant-reload-app! app))

(define (grant-file-save!)
  (let ([tmp (string-append *grant-file-path* ".tmp")])
    (when (file-exists? tmp) (delete-file tmp))
    (let ([dir (path-parent *grant-file-path*)])   ; ~/.schevana.d
      (unless (or (string=? dir "") (file-directory? dir)) (mkdir dir)))
    (call-with-output-file tmp
      (lambda (p)
        (fprintf p ";;; permissions.ss — what you allowed each app, and \
                    what you denied. Plain data; safe to edit.\n")
        (for-each (lambda (app)
                    (let ([d (hashtable-ref *grant-decisions* app #f)])
                      (fprintf p "\n(app-permissions ~s\n  approved ~s\n  \
                                  denied ~s)\n" app (car d) (cdr d))))
                  (sort (lambda (a b) (string<? (symbol->string a)
                                                (symbol->string b)))
                        (vector->list (hashtable-keys *grant-decisions*))))))
    (rename-file tmp *grant-file-path*)))

;; Reads the decisions (main.ss, at boot), and makes again the sandboxes
;; of the apps loaded meanwhile whose grants it changes. Read as data,
;; never evaluated.
(define (grant-file-load!)
  (when (file-exists? *grant-file-path*)
    (safely 'permissions
      (lambda ()
        (call-with-input-file *grant-file-path*
          (lambda (p)
            (let loop ()
              (let ([x (read p)])
                (unless (eof-object? x)
                  (when (and (list? x) (= (length x) 6)
                             (eq? (car x) 'app-permissions)
                             (symbol? (cadr x)))
                    (hashtable-set! *grant-decisions* (cadr x)
                                    (cons (plist-ref (cddr x) 'approved '())
                                          (plist-ref (cddr x) 'denied '()))))
                  (loop))))))
        (for-each (lambda (app)
                    (unless (grant-current? app) (grant-reload-app! app)))
                  (grant-apps))))))

;;; ------------------------------------------------------------------ apps

;; An app in a sandbox: its file, its sandbox, what it requests and what
;; its sandbox was made with.
(define-record-type grant-app
  (nongenerative schevana-grant-app-1)
  (fields name path env requests grants))

;; app: grant-app
(defvar *grant-apps* (make-eq-hashtable))

;; The apps in sandboxes, by name.
(define (grant-apps)
  (sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
        (vector->list (hashtable-keys *grant-apps*))))

(define (grant-app-of app) (hashtable-ref *grant-apps* app #f))

;; app's sandbox, or #f for an app of the world's.
(define (grant-env app)
  (let ([a (grant-app-of app)]) (and a (grant-app-env a))))

(define (grant-requested app)
  (let ([a (grant-app-of app)]) (if a (grant-app-requests a) '())))

;; The app whose sandbox e is, or #f.
(define (grant-app-in e)
  (find (lambda (app) (eq? (grant-env app) e)) (grant-apps)))

;; What app's requests are approved, in the order requested.
(define (grant-granted app requests)
  (let-values ([(ok no) (grant-of app)])
    (filter (lambda (b) (memq b ok)) requests)))

;; Whether app's sandbox has what it is granted now.
(define (grant-current? app)
  (let ([a (grant-app-of app)])
    (or (not a)
        (equal? (grant-app-grants a)
                (grant-granted app (grant-app-requests a))))))

;; The bundles path's first form requests, (app-requests b ...), read as
;; data before any of its code runs; #f when it has none.
(define (grant-requests path)
  (let ([x (guard (c [#t #f]) (call-with-input-file path read))])
    (and (list? x) (pair? x) (eq? (car x) 'app-requests) (cdr x))))

;; /apps: every name of a bundle's, shared from the world, but for what an
;; app is given of its own (grant-worklet-names). Each app's sandbox is its
;; child, shared from it those of its own bundles.
(defvar *grant-apps-env*
  (let ([e (env-child (env-root) 'apps 'confined)])
    (env-kind-set! e 'apps)
    e))

(define (grant-apps-env) *grant-apps-env*)

(define grant-worklet-names '(define-worklet worklet))

(env-share! *grant-apps-env*
            (remp (lambda (n) (memq n grant-worklet-names))
                  (apply append (map cddr grant-bundles))))

;; Loads path, a file of an apps folder, for src/system.ss: a tree app
;; that requests nothing into the world, any other into its sandbox,
;; made again when what it requests or is granted has changed.
(define (grant-load-app! path)
  (let ([requests (grant-requests path)])
    (if (and (not requests)
             (string-prefix? (source-path "apps/") path))
        (load-file! path)
        (env-load (grant-sandbox! (string->symbol (path-root (path-last path)))
                                  path (or requests '()))
                  path))))

(set! *app-loader* (lambda (path) (grant-load-app! path)))

(define (grant-sandbox! app path requests)
  (for-each (lambda (b)
              (unless (assq b grant-bundles)
                (errorf 'app-requests "~a requests ~s, no bundle (~a)" app b
                        (map car grant-bundles))))
            requests)
  (let ([a (grant-app-of app)] [grants (grant-granted app requests)])
    (if (and a (not (env-dropped? (grant-app-env a)))
             (equal? requests (grant-app-requests a))
             (equal? grants (grant-app-grants a)))
        (grant-app-env a)
        (begin
          (when (and a (not (env-dropped? (grant-app-env a))))
            (env-drop! (grant-app-env a)))
          (let ([e (grant-make-env app requests grants)])
            (hashtable-set! *grant-apps* app
                            (make-grant-app app path e requests grants))
            e)))))

;; app's sandbox: its bundles granted, the others it requests as stubs,
;; and what every app holds.
(define (grant-make-env app requests grants)
  (let-values ([(ok denied) (grant-of app)])
    (let ([e (env-child (grant-apps-env) app 'confined)]
          [worklets (worklet-base-environment)])
      (env-kind-set! e 'app)
      (for-each
       (lambda (b)
         (for-each
          (lambda (n)
            (cond [(and (memq n grant-worklet-names) (memq b grants))
                   (env-give-syntax! e n (grant-worklet-syntax n worklets)
                                     "compiled among this app's own worklets")]
                  [(memq n grant-worklet-names)
                   (env-give-syntax! e n
                                     (grant-worklet-stub
                                      n (grant-stub app b n (memq b denied)))
                                     (if (memq b denied)
                                         "a stub: denied"
                                         "a stub: not allowed yet"))]
                  [(not (memq b grants))
                   (env-give! e n (grant-stub app b n (memq b denied))
                              (if (memq b denied)
                                  "a stub: denied"
                                  "a stub: not allowed yet"))]
                  [(grant-narrow app n)
                   => (lambda (v) (env-give! e n v "for its own windows"))]
                  [else (env-share! e (list n))]))
          (grant-bundle-names b)))
       requests)
      (env-give-syntax! e 'define-app
                        (lambda (x) (grant-define-app x app))
                        "registers this app alone")
      (env-give-syntax! e 'app-requests
                        (lambda (x) #'(void))
                        "read by the loader")
      (let ([env (env-environment e)])
        (env-give-syntax! e 'defvar
                          (lambda (x) (grant-defvar x env))
                          "asks this sandbox"))
      e)))

;; The world's name n, made for app, or #f: a window it opens is its own,
;; or no app's where it says so (a secondary one), never another's; the
;; crew it sets is at most one thread short of the machine's.
(define (grant-narrow app n)
  (case n
    [(open-window)
     (lambda (title . opts)
       (if (plist-ref opts 'app app)
           (apply open-window title 'app app opts)
           (apply open-window title opts)))]
    [(crew-size-set!)
     (lambda (k)
       (crew-size-set! (max 0 (min k (- (host-cpu-count) 1)))))]
    [else #f]))

;; An app's define-worklet (n) and worklet: compiled in env, an environment
;; its sandbox alone has (the core base and its own worklets), so that they
;; reach nothing of the world's or another app's, and no app's name lands
;; in /worklets, where it would replace a worklet of the world's.
(define (grant-worklet-syntax n env)
  (case n
    [(worklet)
     (lambda (x)
       (syntax-case x ()
         [(_ formals body ...)
          #`((quote #,(lambda (form) (worklet-compile 'worklet form env)))
             '(lambda formals body ...))]))]
    [else
     (lambda (x)
       (syntax-case x ()
         [(_ (name . formals) body ...)
          #`(define name
              ((quote #,(lambda (form)
                          (let ([who (syntax->datum #'name)])
                            (define-top-level-syntax who (forwarder-to #'name)
                                                     env)
                            (worklet-compile who form env))))
               '(lambda formals body ...)))]))]))

;; While the crew bundle is not approved: the app still loads, and the
;; stub raises at the first use, as any stub does.
(define (grant-worklet-stub n stub)
  (lambda (x)
    (syntax-case x ()
      [(_ (name . formals) body ...)
       (eq? n 'define-worklet)
       #`(define name (quote #,stub))]
      [(_ formals body ...) #`(quote #,stub)])))

(define (grant-define-app x app)
  (syntax-case x ()
    [(_ (name . formals) title body ...)
     #`(begin
         (define (name . formals) body ...)
         ((quote #,(lambda (n t launch) (grant-register! app n t launch)))
          'name title (lambda () (name))))]))

(define (grant-register! app name title launch)
  (unless (eq? name app)
    (errorf 'define-app "~a.ss defines the app ~a, not ~s" app app name))
  (register-app! name title launch)
  (grant-forward-launcher! app))

;; The world's app names its launcher, where the world has no name app of
;; its own: (clock) at the world's REPL opens Clock.
(defvar *grant-forwarded* '())

(define (grant-forward-launcher! app)
  (when (or (memq app *grant-forwarded*)
            (not (memq app (environment-symbols *world-env*))))
    (define-top-level-syntax app
      (forwarder-to (datum->syntax (env-anchor (grant-env app)) app))
      *world-env*)
    (unless (memq app *grant-forwarded*)
      (set! *grant-forwarded* (cons app *grant-forwarded*)))))

(define (grant-defvar x env)
  (syntax-case x ()
    [(_ name init)
     #`(define name
         (if ((quote #,(lambda (s) (top-level-bound? s env))) 'name)
             ((quote #,(lambda (s) (top-level-value s env))) 'name)
             init))]))

;; Makes app's sandbox again with what it is granted now and loads its file
;; there; its windows close first, and as many open again where they were.
(define (grant-reload-app! app)
  (let ([a (grant-app-of app)])
    (when a
      (let ([wins (filter (lambda (w) (eq? (window-app w) app)) (windows))])
        (for-each close-window! wins)
        (grant-load-app! (grant-app-path a))
        (for-each (lambda (w)
                    (safely app
                      (lambda ()
                        (parameterize ([new-window-position
                                        (cons (window-x w) (window-y w))])
                          (app-launch! app)))))
                  wins)))))

;;; ------------------------------------------------------------------ stubs

(define-condition-type &grant-needed &error make-grant-needed grant-needed?
  (app grant-needed-app)
  (bundle grant-needed-bundle))

;; What app's name n raises in its sandbox while its bundle b is not
;; approved: "Sketch needs Draw in its windows (fill-box): not allowed
;; yet".
(define (grant-stub app b n denied?)
  (lambda args
    (raise (condition
            (make-grant-needed app b)
            (make-who-condition n)
            (make-message-condition
             (format "~a needs ~a (~a): ~a" (grant-app-title app)
                     (grant-bundle-title b) n
                     (if denied? "denied" "not allowed yet")))))))

(define (grant-app-title app)
  (let ([a (find (lambda (a) (eq? (app-name a) app)) *apps*)])
    (if a (app-title a) (symbol->string app))))

;;; ------------------------------------------------------------------ kinds

(env-register-kind! 'apps
  'title "Apps"
  'base 'confined
  'forks '()
  'fork #f
  'kept "the apps' sandboxes live there"
  'doc "Every name an app may be granted, shared from the world: each \
        app's sandbox is shared its own bundles from here")

(env-register-kind! 'app
  'title "App"
  'base 'confined
  'forks '()
  'fork #f
  'doc "An app's sandbox: what is always safe, and the bundles it \
        requests, granted or as stubs")
