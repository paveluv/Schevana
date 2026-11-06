;;; tests/frame.ss — the renderer: every frame drawn on the main thread
;;; into the second screen buffer, compared row by row with the screen;
;;; the rows that changed are copied onto it and uploaded.
;;;
;;;   scheme --script tests/frame.ss [output-dir]
;;;
;;; The reference for a frame is render-full-into! drawn directly into an
;;; image: the very procedure the renderer runs.
;;;   identity      once the frames asked for are drawn, the canvas is the
;;;                 reference, bit for bit: S30T, S30, S5, a translucent
;;;                 window, every style, a menu and a toast, at 100, 125,
;;;                 150, 200 and 300% (Monitor's content masked: it shows
;;;                 the heap)
;;;   damage        a texture fed only the uploaded rows is the canvas after
;;;                 every step of this file; a frame that changes nothing
;;;                 uploads and presents nothing; the screen stays one
;;;                 surface; every way an area is asked for (the clock's
;;;                 second, a window, part of it, a covered one, hover,
;;;                 dragging, resizing, moving, a process, one switched
;;;                 out after each area it asks for) leaves the reference
;;;                 at 100, 150 and 200%, the clock comparing only the top
;;;                 bar's rows, a lone window its extent's
;;;   bleed         every style, and one glowing past its frame with and
;;;                 without its 'bleed, moved, resized and hovered at 100
;;;                 and 150%, leaves the reference; drawn unclipped, each
;;;                 registered style keeps to its extent
;;;   the window    a fake window: boot, a resize, a drag, a rescale and a
;;;                 lost texture each show their own frame at once, never
;;;                 an empty new canvas
;;;   processes     a process, switched out anywhere, frees tile caches and
;;;                 owned surfaces, rescales and calls (render-frame!) while
;;;                 the main loop draws: frames stay whole
;;;   raising       a window's draw that raises crashes the window; a frame
;;;                 whose drawing raises shows nothing; a window-bleed that
;;;                 raises is reported, and frames and input go on
;;;   redefinition  draw-window, draw-taskbar and a style, redefined: the
;;;                 next frame shows them, is the reference, costs the same;
;;;                 a REPL evaluation asks for the whole screen as it ends
;;;   wallpaper     a theme change (raw or by set-theme!), a redefined
;;;                 draw-wallpaper or the wallpaper in use defined again
;;;                 paints it again for the next frame; a clock-reading
;;;                 draw-wallpaper is a still picture; the picture is
;;;                 draw-wallpaper's drawing
;;;   Life          each generation of 30 Life windows shows on the next frame
;;;   Tasks         typing, the caret's blink, hover, a tooltip, a drag, the
;;;                 wheel, a menu, the calendar, the dialog, a REPL change
;;;                 and the narrow page leave the reference at 100, 150 and
;;;                 200%; unfocused, or with the dialog over a field that
;;;                 had the keyboard, Tasks asks for no frame; the Tree's
;;;                 hover, twisties, keys, wheel, later rows, dimmed rows,
;;;                 links and Add menu too
;;;   a long text   a description's scroll bar shows an estimate until idle
;;;                 steps have computed its rows; the step that finishes
;;;                 draws it again, and the screen is the reference
;;;
;;; output-dir receives a scratch theme file and a screenshot of a failure.

(define *schevana-root*
  (let ([dir (path-parent (path-parent (car (command-line))))])
    (if (string=? dir "") "." dir)))

(load (string-append *schevana-root* "/load.ss"))

(define out-dir
  (if (pair? (command-line-arguments)) (car (command-line-arguments)) "."))
(set! *theme-file-path* (string-append out-dir "/theme.ss"))
(when (file-exists? *theme-file-path*) (delete-file *theme-file-path*))

(define failures 0)

(define-syntax check
  (syntax-rules ()
    [(_ name expr)
     (let ([ok (guard (c [#t (printf "  error: ~a\n" (condition->string c)) #f])
                 expr)])
       (unless ok (set! failures (+ failures 1)))
       (printf "~a ~a\n" (if ok "ok  " "FAIL") name))]))

;; A clock that moves only when told, so that Life steps when a check says.
;; Checks that need time to pass go back to the real one.
(define fake-ms 1000000)
(define real-now-ms now-ms)
(define (fake-clock!) (set! now-ms (lambda () fake-ms)))
(fake-clock!)
(random-seed 4242)
(schevana-boot! 'headless 1280 800)

(define (steps n . ms)
  (do ([i 0 (+ i 1)]) ((= i n))
    (set! fake-ms (+ fake-ms (if (pair? ms) (car ms) 0)))
    (schevana-step! 0)))

;; Steps while a frame is asked for (at most 20): then the canvas shows
;; the world as it is.
(define (settle)
  (let loop ([n 0])
    (when (and (< n 20) *dirty*)
      (schevana-step! 0)
      (loop (+ n 1)))))

;;; ------------------------------------------------------------------ images

(define (canvas-image)
  (cairo-image-surface-create CAIRO_FORMAT_ARGB32 *canvas-pw* *canvas-ph*))

;; The frame render-full-into! draws now, straight into an image.
(define (reference)
  (let ([ref (canvas-image)])
    (render-full-into! ref)
    ref))

;; A copy of the canvas.
(define (canvas-copy)
  (let ([c (canvas-image)])
    (cairo-surface-flush *canvas*)
    (sdl-memcpy (cairo-image-surface-get-data c)
                (cairo-image-surface-get-data *canvas*)
                (* (cairo-image-surface-get-stride c) *canvas-ph*))
    (cairo-surface-mark-dirty c)
    c))

;; Monitor's content in device pixels, (x0 y0 x1 y1), or #f.
(define (monitor-mask)
  (let ([m (find-window 'monitor)])
    (and m (visible? m)
         (let-values ([(cx cy cw ch) (content-rect m)])
           (map (lambda (v) (exact (round (* *scale* v))))
                (list cx cy (+ cx cw) (+ cy ch)))))))

;; How many pixels of a and b (the same size) differ outside the mask.
(define (differing a b mask)
  (cairo-surface-flush a)
  (cairo-surface-flush b)
  (let ([pa (cairo-image-surface-get-data a)]
        [pb (cairo-image-surface-get-data b)]
        [st (cairo-image-surface-get-stride a)]
        [w (cairo-image-surface-get-width a)]
        [h (cairo-image-surface-get-height a)])
    (let row ([y 0] [n 0])
      (cond
        [(= y h) n]
        [(zero? (sdl-memcmp (+ pa (* y st)) (+ pb (* y st)) (* 4 w)))
         (row (+ y 1) n)]
        [else
         (row (+ y 1)
              (let col ([x 0] [n n])
                (cond
                  [(= x w) n]
                  [(and mask (<= (car mask) x) (< x (caddr mask))
                        (<= (cadr mask) y) (< y (cadddr mask)))
                   (col (+ x 1) n)]
                  [(= (foreign-ref 'unsigned-32 pa (+ (* y st) (* 4 x)))
                      (foreign-ref 'unsigned-32 pb (+ (* y st) (* 4 x))))
                   (col (+ x 1) n)]
                  [else (col (+ x 1) (+ n 1))])))]))))

(define (same-image? a b)
  (and (= (cairo-image-surface-get-width a) (cairo-image-surface-get-width b))
       (= (cairo-image-surface-get-height a) (cairo-image-surface-get-height b))
       (zero? (differing a b #f))))

(define shots 0)

;; Does the canvas equal the reference? label is printed with a count
;; when it does not.
(define (shows-reference? label)
  (let* ([ref (reference)] [n (differing *canvas* ref (monitor-mask))])
    (unless (= n 0)
      (set! shots (+ shots 1))
      (printf "  ~a: ~a pixels differ from the reference\n" label n)
      (when (<= shots 3)
        (screenshot (format "~a/differs-~a.png" out-dir shots))))
    (cairo-surface-destroy ref)
    (= n 0)))

;; The same, once the frames asked for are drawn.
(define (matches-reference? label)
  (settle)
  (shows-reference? label))

(define (pixel-of surface x y)   ; logical point
  (cairo-surface-flush surface)
  (foreign-ref 'unsigned-32 (cairo-image-surface-get-data surface)
               (+ (* (exact (floor (* *scale* y)))
                     (cairo-image-surface-get-stride surface))
                  (* 4 (exact (floor (* *scale* x)))))))

;;; ------------------------------------------------------------------
;;; the texture
;;; The host's SDL upload, with *host* 'sdl only around the present and the
;;; texture an image that uploads copy rows into, as SDL_UpdateTexture does.
;;; After every step it must equal the canvas, and a step presents if and
;;; only if it uploaded or was exposed.

(define texture #f)
(define texture-steps 0)
(define texture-mismatches 0)
(define bad-presents 0)
(define presents 0)
(define plain-present #f)

(define (texture-upload! t rect pixels pitch)
  (unless (and texture (= (cairo-image-surface-get-width texture) *canvas-pw*)
               (= (cairo-image-surface-get-height texture) *canvas-ph*))
    (when texture (cairo-surface-destroy texture))
    ;; a new texture: its pixels are undefined (here clear)
    (set! texture (canvas-image)))
  (let ([td (cairo-image-surface-get-data texture)]
        [ts (cairo-image-surface-get-stride texture)])
    (let-values ([(x y w h)
                  (if (eqv? rect 0)
                      (values 0 0 *canvas-pw* *canvas-ph*)
                      (apply values
                             (map (lambda (i) (foreign-ref 'integer-32 rect i))
                                  '(0 4 8 12))))])
      (unless (and (= x 0) (= w *canvas-pw*) (<= 0 y) (< 0 h)
                   (<= (+ y h) *canvas-ph*) (= pitch ts))
        (errorf 'sdl-update-texture "not a run of whole rows: ~s"
                (list x y w h pitch)))
      (sdl-memcpy (+ td (* y ts)) pixels (* h ts))
      (cairo-surface-mark-dirty texture)
      #t)))

(set! sdl-update-texture texture-upload!)
(set! sdl-render-texture (lambda (r t src dst) #t))
(set! sdl-render-present (lambda (r) (set! presents (+ presents 1)) #t))
(set! plain-present host-present-damage!)
(set! host-present-damage!
  (lambda ()
    (let ([p0 presents] [u0 *upload-bytes*] [exposed? *present-only?*])
      (fluid-let ([*host* 'sdl]) (plain-present))
      (set! texture-steps (+ texture-steps 1))
      (unless (and texture (same-image? texture *canvas*))
        (set! texture-mismatches (+ texture-mismatches 1)))
      (unless (= (- presents p0) (if (or exposed? (> *upload-bytes* u0)) 1 0))
        (set! bad-presents (+ bad-presents 1))))))

(set! *full-upload?* #t)
(steps 2)

;;; ------------------------------------------------------------------ scenes

(define (fixed-status!)
  (set! *status-segments* '())
  (add-status-segment! 'a (lambda () "12.3 ms/tick"))
  (add-status-segment! 'b (lambda () "Thu 29 Oct   12:00:00")))

(define (clear-world!)
  (for-each close-window! (windows))
  (set! *toasts* '())
  (set! *cascade* 0)
  (set! *hover* #f)
  (set! *drag* #f)
  (when (menu-open?) (close-menu!)))

(define (texted-repl!)
  (let* ([r (repl)] [rs (window-ref r 'state)])
    (for-each (lambda (l) (repl-add! rs (car l) (cdr l)))
              '((input . "(define (fib n) (if (< n 2) n \
                          (+ (fib (- n 1)) (fib (- n 2)))))")
                (result . "fib")
                (input . "(map fib (iota 20))")
                (result . "(0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 \
                           1597 2584 4181)")
                (input . "(set-theme! 'accent #xff9e64)")))
    r))

;; S30T: 30 Life windows tiled; S30: cascaded; S5: a REPL, Settings, Clock,
;; Life and Monitor, overlapping, the REPL on top.
(define (scene! name)
  (clear-world!)
  (random-seed 4242)
  (case name
    [(S30T S30)
     (do ([i 0 (+ i 1)]) ((= i 30)) (life))
     (if (eq? name 'S30T) (tile-windows!) (cascade-windows!))]
    [(S5)
     (let* ([r (texted-repl!)] [s (settings)] [c (clock)] [l (life)]
            [m (monitor)])
       (move-window! r 30 45)
       (move-window! s 380 120)
       (move-window! c 1020 50)
       (move-window! l 520 290)
       (move-window! m 60 300)
       (for-each focus-window! (list s m l c r)))])
  (fixed-status!)
  (steps 3 81))

(define (pause-lifes!)
  (for-each (lambda (w)
              (when (eq? (window-app w) 'life)
                (window-call w 'key #\space '())))
            (windows)))

;;; ------------------------------------------------------------------ identity

(define four-styles '(mac windows interlisp genera))

(for-each
 (lambda (pct)
   (set-theme! 'scale pct)
   (steps 1)
   (let ([bad '()])
     (define (try! label)
       (unless (matches-reference? (list pct label))
         (set! bad (cons label bad))))
     (scene! 'S30T) (try! 'S30T)
     (steps 1 81) (try! 'S30T-stepped)
     (scene! 'S30) (try! 'S30)
     (scene! 'S5) (try! 'S5)
     (let ([g (open-window "Glass"
                'size '(320 . 200)
                'pos '(560 . 330)
                'bg (alpha 'bg-1 0.45)
                'draw (lambda (win w h)
                        (draw-text 14 14 "translucent" 'text 'big)))])
       (try! 'translucent)
       (for-each (lambda (style) (set-theme! 'window-style style) (try! style))
                 four-styles)
       (set-theme! 'window-style 'mac)
       (inject! `(mouse-down ,(+ (window-x g) 120) ,(+ (window-y g) 8) right 1)
                `(mouse-up ,(+ (window-x g) 120) ,(+ (window-y g) 8) right))
       (steps 1)
       (unless (menu-open?) (set! bad (cons 'no-window-menu bad)))
       (try! 'window-menu)
       (close-menu!)
       (notify "A toast")
       (try! 'toast)
       (close-window! g))
     (check (format "once the frames asked for are drawn, the canvas is \
                     render-full-into!'s frame, bit for bit, at ~a% (~a)" pct
                    (if (null? bad)
                        "S30T, S30, S5, translucent, every style, menu, toast"
                        (reverse bad)))
            (null? bad))))
 '(100 125 150 200 300))

;;; ------------------------------------------------------------------ damage

(set-theme! 'scale 100)
(scene! 'S5)
(pause-lifes!)
;; they change by themselves
(for-each (lambda (app) (close-window! (find-window app))) '(clock monitor))
(steps 2)
(invalidate!)
(steps 1)
(let ([u0 *upload-bytes*] [p0 presents] [n0 *frames-drawn*] [screen *canvas*])
  (invalidate!)
  (steps 1)
  (let ([none (list (- *frames-drawn* n0) (- *upload-bytes* u0)
                    (- presents p0))]
        [kept (list (eqv? screen *canvas*))])   ; after each frame
    (inject! '(text "x"))   ; into the REPL: a few rows change
    (steps 1)
    (let ([typed (list *frame-rows* (- *upload-bytes* u0) (- presents p0))]
          [kept (append kept (list (eqv? screen *canvas*)))])
      (check (format
              "a frame that changes nothing uploads and presents nothing ~s; \
               a keystroke uploads only its rows ~s; \
               the rows are copied onto the screen, which stays one surface ~s"
              none typed kept)
             (and (equal? none '(1 0 0))
                  (< 0 (car typed) (quotient *canvas-ph* 4))
                  (= (cadr typed) (* 4 *canvas-pw* (car typed)))
                  (= (caddr typed) 1)
                  (equal? kept '(#t #t)))))))

;;; ------------------------------------------------------------------
;;; damage paths
;;; Every way an area is asked for, at 100, 150 and 200%, odd logical
;;; coordinates giving fractional device ones: after each step the screen
;;; is the reference. The clock's second compares (and so uploads) only
;;; the top bar's rows; an invalidated window, alone, only its extent's.

;; The rows the last frame compared, (y0 . y1), and the runs it changed.
(define compared #f)
(define compared-runs '())
(let ([plain copy-changed-rows!])
  (set! copy-changed-rows!
    (lambda (y0 y1)
      (let ([runs (plain y0 y1)])
        (set! compared (cons y0 y1))
        (set! compared-runs runs)
        runs))))

;; Did the step after u0 bytes compare just rows, change some of them and
;; upload only those?
(define (compared-only? rows u0)
  (and (equal? compared rows) (pair? compared-runs)
       (for-all (lambda (r) (<= (car rows) (car r) (cdr r) (cdr rows)))
                compared-runs)
       (= (- *upload-bytes* u0)
          (* 4 *canvas-pw*
             (apply + (map (lambda (r) (- (cdr r) (car r))) compared-runs))))))

;; Styles that glow 5 pixels past their frame: glow-5 says so with 'bleed,
;; glow does not, as one typed at the REPL might not.
(define styles-before-glow *styles*)
(define (glow-under win x y w h focused? hover pressed)
  (fill-rect (- x 5) (- y 5) (+ w 10) (+ h 10) #xff00ff)
  (fill-rect x y w (title-height) 'accent))
(define-style glow-5 "Glow, 5" 'frame-bleed (lambda (win) 5)
  'frame-under glow-under)
(define-style glow "Glow" 'frame-under glow-under)

;; A window's extent, in device rows (y0 . y1).
(define (extent-rows win)
  (let-values ([(x y w h) (window-extent win)])
    (cons (max 0 (exact (floor (* y *scale*))))
          (min *canvas-ph* (exact (ceiling (* (+ y h) *scale*)))))))

;; Where a style's button of that kind is, on screen.
(define (button-point win kind)
  (let ([b (assq kind (frame-regions win))])
    (list (+ (window-x win) (cadr b) (quotient (cadddr b) 2))
          (+ (window-y win) (caddr b) (quotient (list-ref b 4) 2)))))

(define (taskbar-point win)
  (list (+ (cadr (assq win (taskbar-areas))) 20) (- (screen-h) 10)))

(define (damage-paths pct)
  (set-theme! 'scale pct)
  (clear-world!)
  (let* ([tick 0] [asked 0] [a-ink #x3060a0] [b-ink #x40a060]
         [c-ink #xa04060] [c-sub #xe0c040] [bad '()] [shown '()]
         ;; part of a's drawing lies under b
         [a (open-window "A" 'size '(301 . 201) 'pos '(201 . 151)
              'draw (lambda (win w h) (fill-rect 151 101 141 91 a-ink)))]
         [b (open-window "B" 'size '(301 . 201) 'pos '(401 . 251)
              'draw (lambda (win w h) (fill-rect 21 21 61 41 b-ink)))]
         ;; alone
         [c (open-window "C" 'size '(201 . 151) 'pos '(901 . 401)
              'draw (lambda (win w h)
                      (fill-rect 0 0 w h c-ink)
                      (fill-rect 11 13 47 29 c-sub)))])
    (define (try! label)
      (unless (matches-reference? (list pct label))
        (set! bad (cons label bad))))
    (define (step! label) (steps 1) (try! label))
    (define (move! label x y) (inject! `(mouse-move ,x ,y)) (step! label))
    (define (drag! label x y dx dy)   ; pressed at (x, y), moved 4 times
      (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1))
      (step! label)
      (do ([i 1 (+ i 1)]) ((> i 4))
        (move! (list label i) (+ x (* dx i)) (+ y (* dy i))))
      (inject! `(mouse-up ,(+ x (* 4 dx)) ,(+ y (* 4 dy)) left))
      (step! label))
    (set! *status-segments* '())
    (add-status-segment! 'tick (lambda () (format "tick ~a" tick)))
    ;; new whenever asked, as the heap's size and the frame time are
    (add-status-segment! 'asked (lambda () (set! asked (+ asked 1))
                                  (format "asked ~a" asked)))
    (steps 2)
    ;; the clock's second
    (set! tick 1)
    (set! *status-last-second* -1)
    (let ([u0 *upload-bytes*])
      (steps 1)
      (set! shown
        (list (compared-only?
               (cons 0 (exact (ceiling (* (topbar-height) *scale*)))) u0))))
    (try! 'tick)
    ;; (invalidate! win), in a step within one second of the real clock:
    ;; a second starting during it adds the top bar (wm-tick!), which is
    ;; right but not what this measures, so such a step is measured again
    (set! c-ink #x60a040)
    (let again ()
      (let ([s (time-second (current-time))] [u0 *upload-bytes*])
        (set! *status-last-second* s)
        (invalidate! c)
        (steps 1)
        (if (= s (time-second (current-time)))
            (set! shown
              (append shown (list (compared-only? (extent-rows c) u0))))
            (again))))
    (try! 'invalidate)
    (set! c-sub #x4040e0)
    (invalidate! c 11 13 47 29)
    (step! 'sub-rectangle)
    (set! a-ink #xc08030)
    (invalidate! a)
    (step! 'covered)
    ;; hover: buttons, content, title, the bars, the desktop
    (apply move! 'a-close (button-point a 'close))
    (move! 'b-content (+ (window-x b) 100) (+ (window-y b) 100))
    (move! 'b-title (+ (window-x b) 150) (+ (window-y b) 10))
    (move! 'launcher 20 10)
    (apply move! 'taskbar-a (taskbar-point a))
    (apply move! 'taskbar-c (taskbar-point c))
    (move! 'desktop 1200 650)
    (apply move! 'c-maximize (button-point c 'maximize))
    (move! 'desktop-again 1200 650)
    ;; a mac window, dragged by its title and resized
    (drag! 'drag (+ (window-x a) 150) (+ (window-y a) 10) 37 23)
    (drag! 'resize (+ (window-x a) (window-w a) -3)
           (+ (window-y a) (window-h a) -3) -29 17)
    ;; one that draws nothing past its frame, moved away from where it
    ;; leaves half pixels at 150%
    (set-theme! 'shadow 0)   ; shadow
    (steps 1)
    (move-window! c 1001 451)
    (step! 'moved)
    (set-theme! 'shadow (theme-default 'shadow))   ; shadow
    ;; A process asks for areas around e, far from b and c, while main
    ;; changes b and c by turns, compared at each step: none of main's
    ;; areas may be lost, though the process is switched out anywhere.
    (let* ([e (open-window "E" 'size '(81 . 61) 'pos '(41 . 601))]
           [p (spawn "asks"
                (lambda ()
                  (let loop ()
                    (invalidate! e)
                    (invalidate! e 3 5 21 13)
                    (request-frame! 141 621 11 11)
                    (loop))))])
      (fluid-let ([now-ms real-now-ms])
        (do ([i 0 (+ i 1)]) ((= i 60))
          (if (even? i)
              (begin (set! b-ink (if (even? (quotient i 2)) #x6040a0 #x40a060))
                     (invalidate! b))
              (begin (set! c-ink (if (even? (quotient i 2)) #x2080c0 #x60a040))
                     (invalidate! c)))
          (schevana-step! 0)
          (unless (shows-reference? (list pct 'process i))
            (set! bad (cons (list 'process i) bad)))))
      (kill! p)
      (close-window! e))
    (try! 'process-killed)
    ;; A process moves, resizes and restyles d (to a style that reaches
    ;; less far), switched out right after each area it asks for until
    ;; main has drawn a frame (a timer may do that), then stays alive: d
    ;; leaves nothing behind.
    (set-theme! 'shadow 0)   ; shadow
    (let ([d (open-window "D" 'size '(121 . 81) 'pos '(61 . 81)
                          'window-style 'glow-5)]
          [plain request-frame!] [done #f])
      (steps 1)
      (set! request-frame!
        (case-lambda
          [() (plain)]
          [(x y w h)
           (plain x y w h)
           (when (in-engine?)
             (let ([f *frames-drawn*])
               (let spin ()
                 (when (= f *frames-drawn*) (engine-block) (spin)))))]))
      (let ([p (spawn "switched out"
                 (lambda ()
                   (move-window! d 301 97)
                   (resize-window! d 61 41)
                   (window-set! d 'window-style 'mac)
                   (set! done #t)
                   (let park () (sleep-ms 100000000) (park))))])
        (fluid-let ([now-ms real-now-ms])
          (do ([i 0 (+ i 1)]) ((or done (= i 100))) (schevana-step! 0))
          (do ([i 0 (+ i 1)]) ((= i 2)) (schevana-step! 0)))
        (set! request-frame! plain)
        (unless (and done (shows-reference? (list pct 'switched-out)))
          (set! bad (cons 'switched-out bad)))
        (kill! p)
        (close-window! d)))
    (set-theme! 'shadow (theme-default 'shadow))   ; shadow
    (for-each close-window! (list a b c))
    (fixed-status!)
    (steps 1)
    (check (format "every way an area is asked for shows the reference at \
                    ~a%~a; the clock's second compares and uploads only \
                    the top bar's rows, an invalidated window only its \
                    extent's ~s"
                   pct (if (null? bad) "" (format " (not: ~s)" (reverse bad)))
                   shown)
           (and (null? bad) (equal? shown '(#t #t))))))

(for-each damage-paths '(100 150 200))

;;; ------------------------------------------------------------------ bleed
;;; A window is drawn clipped to its extent. Every style, glow-5 and glow
;;; (whose glow is clipped away) leave the reference when moved, resized
;;; and hovered, at 100 and 150%, and glow-5's glow shows. Drawn alone and
;;; unclipped, every registered style but glow keeps to its extent, focused
;;; or not, as set up here and with the theme's defaults.

;; How many pixels win, drawn alone and unclipped, puts outside its extent.
(define (bleeding win focused?)
  (let ([alone (canvas-image)] [blank (canvas-image)])
    (let ([cr (cairo-create alone)])
      (cairo-scale cr *scale* *scale*)
      (fluid-let ([*cr* cr]) (draw-window* win focused?))
      (cairo-destroy cr))
    (let ([n (differing alone blank (extent-box win))])
      (cairo-surface-destroy alone)
      (cairo-surface-destroy blank)
      n)))

;; The registered styles that draw outside their extent.
(define (styles-bleeding)
  (let ([w (open-window "Alone" 'size '(201 . 121) 'pos '(301 . 201))])
    (let ([out (filter (lambda (style)
                         (window-set! w 'window-style style)
                         (> (+ (bleeding w #t) (bleeding w #f)) 0))
                       (styles))])
      (close-window! w)
      out)))

(for-each
 (lambda (pct)
   (set-theme! 'scale pct)
   (clear-world!)
   (override! 'shadow 0)   ; shadow
   (steps 1)
   (let ([bad '()] [glows '()])
     (define (step! label)
       (steps 1)
       (unless (shows-reference? (list pct label))
         (set! bad (cons label bad))))
     (for-each
      (lambda (style)
        (let ([w (open-window "Styled" 'size '(201 . 121) 'pos '(301 . 201)
                              'window-style style)])
          (steps 1)
          (do ([i 1 (+ i 1)]) ((> i 3))
            (move-window! w (+ 301 (* i 37)) (+ 201 (* i 23)))
            (step! (list style 'moved i)))
          (do ([i 1 (+ i 1)]) ((> i 2))
            (resize-window! w (- 201 (* i 29)) (+ 121 (* i 17)))
            (step! (list style 'resized i)))
          (for-each (lambda (b)
                      (inject! `(mouse-move ,@(button-point w (car b))))
                      (step! (list style 'hover (car b))))
                    (frame-regions w))
          (inject! '(mouse-move 1200 650))
          (step! (list style 'left))
          (set! glows (cons (cons style (pixel-of *canvas* (- (window-x w) 3)
                                                  (+ (window-y w) 30)))
                            glows))
          (close-window! w)
          (step! (list style 'closed))))
      (styles))
     (let ([glow-5 (cdr (assq 'glow-5 glows))] [glow (cdr (assq 'glow glows))]
           [none (styles-bleeding)])
       (override! 'shadow)   ; shadow
       (let ([default (styles-bleeding)])
         (check (format "a window is drawn clipped to its extent: every \
                         style, one glowing past its frame with its 'bleed \
                         (#x~x) and one without (#x~x) leave the reference \
                         when moved, resized and hovered at ~a%~a; \
                         unclipped, the styles that draw outside their \
                         extent are ~s, ~s with the theme's defaults"
                        glow-5 glow pct
                        (if (null? bad) "" (format " (not: ~s)" (reverse bad)))
                        none default)
                (and (null? bad) (= glow-5 #xffff00ff) (not (= glow #xffff00ff))
                     (equal? none '(glow))
                     (null? (remq 'glow default))))))))
 '(100 150))
(set! *styles* styles-before-glow)
(set-theme! 'scale 100)
(steps 1)

;;; ------------------------------------------------------------------
;;; the window

;; Does the texture hold a frame? render-full-into! paints every pixel, so
;; none is clear (one pixel in 7 looked at).
(define (texture-holds-frame?)
  (and texture
       (let ([td (cairo-image-surface-get-data texture)]
             [ts (cairo-image-surface-get-stride texture)]
             [w (cairo-image-surface-get-width texture)]
             [h (cairo-image-surface-get-height texture)])
         (let row ([y 0])
           (or (= y h)
               (and (let col ([x 0])
                      (or (>= x w)
                          (and (not (fx= 0 (fxsrl (foreign-ref 'unsigned-32 td
                                                               (+ (* y ts)
                                                                  (* 4 x)))
                                                  24)))
                               (col (+ x 7)))))
                    (row (+ y 1))))))))

;; With a window, a step that uploads the whole canvas (at boot, after a
;; resize (full screen, a drag) or a rescale, or when the texture was lost)
;; shows its own frame: the canvas is new and holds no frame yet, and none
;; may be shown. A fake window answers the SDL calls; the host's own
;; events, resizing and upload run as with a real one.
(let ([size (cons *canvas-pw* *canvas-ph*)] [queue 0] [label #f] [blank '()]
      [log '()] [present sdl-render-present])
  (define (size! a b)
    (foreign-set! 'integer-32 a 0 (car size))
    (foreign-set! 'integer-32 b 0 (cdr size)))
  ;; A turn of the main loop with a window: its events, then the step.
  (define (turn! l)
    (set! label l)
    (let ([p0 presents])
      (apply inject! (fluid-let ([*host* 'sdl]) (host-events 0)))
      (schevana-step! 0)
      (set! log (cons (cons l (- presents p0)) log))))
  (define (resize! l w h)
    (set! size (cons w h))
    (set! queue 1)
    (turn! l))
  (fluid-let ([sdl-get-window-size (lambda (win a b) (size! a b) #t)]
              [sdl-get-current-render-output-size
               (lambda (r a b) (size! a b) #t)]
              [sdl-get-window-display-scale (lambda (win) 1.0)]
              [sdl-set-window-minimum-size (lambda (win w h) #t)]
              [sdl-get-window-flags (lambda (win) 0)]
              [sdl-poll-event   ; the queued pixel-size-changed events
               (lambda (buf)
                 (and (> queue 0)
                      (begin (foreign-set! 'unsigned-32 buf 0
                                           SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED)
                             (set! queue (- queue 1))
                             #t)))]
              [sdl-create-texture   ; a new texture: its pixels are undefined
               (lambda (r f a w h)
                 (when texture
                   (cairo-surface-destroy texture)
                   (set! texture #f))
                 1)]
              [sdl-set-texture-scale-mode (lambda (t mode) #t)]
              [sdl-destroy-texture (lambda (t) (void))]
              [sdl-render-present
               (lambda (r)
                 (unless (texture-holds-frame?) (set! blank (cons label blank)))
                 (present r))]
              [*sdl-texture* 0] [*pixel-ratio* *pixel-ratio*]
              [*host-min-size* #f])
    ;; as host-init! ends, then schevana-boot!
    (fluid-let ([*host* 'sdl]) (host-sync-size!))
    (invalidate!)
    (turn! 'boot)
    (resize! 'resize 1100 700)
    (resize! 'full-screen 1920 1080)
    (resize! 'back 1280 800)
    (do ([i 0 (+ i 1)]) ((= i 4))   ; a drag: a frame, then a resize
      (invalidate!)
      (turn! 'frame)
      (resize! 'drag (- 1240 (* 40 i)) (- 780 (* 20 i))))
    (resize! 'drag-end 1280 800)
    (fluid-let ([*host* 'sdl]) (set-theme! 'scale 150))
    (turn! 'rescale)
    (fluid-let ([*host* 'sdl]) (set-theme! 'scale 100))
    (turn! 'rescale-back)
    (inject! '(render-reset))
    (turn! 'render-reset)
    (fluid-let ([*host* 'sdl]) (handle-event! '(device-reset)))
    (turn! 'device-reset))
  (let ([log (reverse log)])
    (check (format
            "with a window, a step that uploads the whole canvas shows its \
             own frame, never an empty canvas: presents per step ~s; empty ~s"
            log (reverse blank))
           (and (null? blank)
                (for-all (lambda (e) (or (eq? (car e) 'frame) (= (cdr e) 1)))
                         log)
                (= (length (filter (lambda (e) (eq? (car e) 'drag)) log)) 4)
                (= *canvas-pw* 1280) (= *canvas-ph* 800) (= *scale* 1.0)
                (matches-reference? 'window-end)))))

;;; ------------------------------------------------------------------ processes

;; A process (a REPL evaluation is one) is an engine, switched out at any
;; call where interrupts are on, while the main loop draws on, here on the
;; real clock. At 200% it flushes the tile caches, frees owned surfaces,
;; rescales and calls (render-frame!), which in a process only asks for a
;; frame. Besides its time running out, it is switched out for a step now
;; and then where a timer could do it: before a surface is freed or
;; destroyed. No error may come, every frame is the main loop's (one a
;; step at most), and the frame is the reference.
(set-theme! 'scale 200)
(scene! 'S5)
(let* ([acts (make-vector 5 0)] [switches 0] [errors 0] [n0 *frames-drawn*]
       [destroy cairo-surface-destroy] [free free-owned-surface!]
       [report report-error!] [steps-run 300])
  (define (switch-point!)
    (when (and (current-proc) (= 0 (#%$tc-field 'disable-count (#%$tc)))
               (zero? (random 3)))
      (set! switches (+ switches 1))
      (sleep-ms 1)))
  (fluid-let ([now-ms real-now-ms]
              [report-error! (lambda (who c)
                               (set! errors (+ errors 1)) (report who c))]
              [cairo-surface-destroy (lambda (s) (switch-point!) (destroy s))]
              [free-owned-surface! (lambda (s) (switch-point!) (free s))])
    (let ([p (spawn "repl"
               (lambda ()
                 (let loop ()
                   (do ([k (random 2000)] [j 0 (fx+ j 1)]) ((fx= j k)))
                   (let ([a (random 5)])
                     (vector-set! acts a (+ 1 (vector-ref acts a)))
                     (case a
                       [(0) (flush-shadow-tiles!)]   ; shadow
                       [(1) (free-owned-surfaces!)]
                       [(2) (when (zero? (random 40))
                              (set-theme! 'scale (if (= *scale* 2.0) 150 200)))]
                       [(3) (render-frame!)]
                       [else (free-layer! (make-layer* 40 40))]))
                   (loop))))])
      (do ([n 0 (+ n 1)]) ((= n steps-run)) (schevana-step! 0))
      (kill! p)))
  (set-theme! 'scale 200)
  (let ([frames (- *frames-drawn* n0)])
    (check (format
            "a process, switched out anywhere, frees caches and surfaces, \
             rescales and calls (render-frame!) while the main loop draws \
             (~a calls by kind ~s, ~a switches): \
             ~a frames in ~a steps, ~a errors"
            (apply + (vector->list acts)) acts switches frames steps-run errors)
           (and (= errors 0) (> switches 50) (< 0 frames (+ steps-run 1))
                (> (vector-ref acts 3) 100)
                (matches-reference? 'process-calls)))))

;;; ------------------------------------------------------------------ raising

;; Draws that raise: a window's (it crashes) and the whole frame's (nothing
;; is drawn or uploaded, and the next frame is whole).
(let ([w (open-window "Crashy" 'size '(300 . 160) 'pos '(400 . 300)
                      'draw (lambda (win cw ch) (car '())))])
  (let ([crashed (matches-reference? 'crashed-window)])
    (close-window! w)
    (let ([plain frame-box] [frames *frames-drawn*] [u0 *upload-bytes*])
      (set! frame-box (lambda (damage) (error 'frame-box "on purpose")))
      (parameterize ([console-error-port (open-output-string)])
        (invalidate!)
        (steps 1))
      (let ([shown? (or (not (= frames *frames-drawn*))
                        (not (= u0 *upload-bytes*)))])
        (set! frame-box plain)
        (set! *toasts* '())
        (check (format
                "a draw that raises crashes its window, and the frame is the \
                 reference; a frame whose drawing raises shows nothing (~a)"
                shown?)
               (and crashed (window-error w) (not shown?)
                    (matches-reference? 'after-raise)))))))

;; A window-bleed with a mistake, as typed at the REPL: it is reported,
;; every window covers the whole screen meanwhile, and frames and input go
;; on, so that it can be fixed.
(let* ([keys 0] [plain window-bleed] [frames *frames-drawn*]
       [w (open-window "Keys" 'size '(200 . 100) 'pos '(300 . 200)
                       'key (lambda (win key mods) (set! keys (+ keys 1))))])
  (steps 1)
  (check "a window-bleed that raises is reported, and frames and input go on"
         (guard (c [#t (set! window-bleed plain) (raise c)])
           (set! window-bleed (lambda (win) (+ 1 'x)))
           (parameterize ([console-error-port (open-output-string)])
             (window-call w 'key #\a '())
             (steps 1)
             (move-window! w 320 210)
             (steps 1))
           (let ([drawn (- *frames-drawn* frames)]
                 [same (shows-reference? 'bad-bleed)]
                 [told (exists (lambda (t)
                                 (string-contains-ci? (vector-ref t 1) "bleed"))
                               *toasts*)])
             (set! window-bleed plain)
             (set! *toasts* '())
             (close-window! w)
             (and (= keys 1) (> drawn 1) same told
                  (matches-reference? 'bleed-fixed))))))

;;; ------------------------------------------------------------------ Tasks
;;; The widget kit changes the screen on input and by itself: typing into
;;; a title, a wrapping description and the search, the caret's blink,
;;; hover and a tooltip, a drag across columns, the wheel (rows scrolled
;;; under a still pointer), a field brought back into view, a dropdown's
;;; menu, the calendar, the dialog, a change from the REPL, the narrow
;;; page. After each step the screen is the reference, at 100, 150 and
;;; 200%; unfocused, or with the dialog over a field that had the keyboard
;;; (no caret blinks under it), Tasks asks for none.

(define (tasks-scene pct)
  (set-theme! 'scale pct)
  (clear-world!)
  (tasks-reset!)
  (let* ([w (tasks)] [ui (window-ref w 'ui)] [bad '()]
         [top-rows (exact (ceiling (* (topbar-height) *scale*)))])
    (define (try! label)
      (unless (matches-reference? (list pct label))
        (set! bad (cons label bad))))
    (define (point id)   ; region id's middle on screen
      (let ([r (ui-find ui id)])
        (let-values ([(cx cy cw ch) (content-rect w)])
          (values (exact (floor (+ cx (ui-region-x r) (/ (ui-region-w r) 2))))
                  (exact (floor (+ cy (ui-region-y r)
                                   (/ (ui-region-h r) 2))))))))
    (define (move! label id)
      (let-values ([(x y) (point id)]) (inject! `(mouse-move ,x ,y)))
      (steps 1)
      (try! label))
    (define (click! label id)
      (let-values ([(x y) (point id)])
        (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                 `(mouse-up ,x ,y left)))
      (steps 1)
      (try! label))
    (define (key! label key . mods)
      (inject! `(key-down ,key ,mods))
      (steps 1)
      (try! label))
    (define (type! label str)
      (for-each (lambda (c) (inject! `(text ,(string c)))) (string->list str))
      (steps 1)
      (try! label))
    (fixed-status!)
    (resize-window! w 1100 600)
    (move-window! w 20 70)
    (steps 1)
    (try! 'open)
    (click! 'select '(card 9))
    (key! 'title 'return)
    (type! 'title-typed " and more")
    (steps 1 530)
    (try! 'blink-off)
    (steps 1 530)
    (try! 'blink-on)
    (click! 'description 'description)
    (type! 'wrapped " Words that wrap across the rows of the description.")
    (key! 'search '#\/)
    (type! 'search-typed "kit")
    (key! 'search-left 'escape)
    ;; unfocused, the caret goes and no frame shows Tasks
    (click! 'title-again 'title)
    (inject! '(mouse-move 1240 400) '(mouse-down 1240 400 left 1)
             '(mouse-up 1240 400 left))
    (steps 1)
    (try! 'unfocused)
    (do ([i 0 (+ i 1)]) ((= i 4))
      (set! compared #f)
      (steps 1 500)
      (when (and compared (> (cdr compared) top-rows))
        (set! bad (cons (list 'unfocused-asked i) bad))))
    (focus-window! w)
    (steps 1)
    (try! 'refocused)
    (key! 'title-left 'escape)
    (move! 'hover-card '(card 10))
    (move! 'hover-new 'new)
    (steps 1 700)
    (try! 'tooltip)
    (inject! '(mouse-move 1240 400))
    (steps 1)
    (try! 'pointer-left)
    (let-values ([(x0 y0) (point '(card 16))]
                 [(x1 y1) (point '(column review))])
      (inject! `(mouse-move ,x0 ,y0) `(mouse-down ,x0 ,y0 left 1))
      (steps 1)
      (try! 'drag-pressed)
      (for-each (lambda (f)
                  (inject! `(mouse-move ,(round (+ x0 (* f (- x1 x0))))
                                        ,(round (+ y0 (* f (- y1 y0))))))
                  (steps 1)
                  (try! (list 'drag f)))
                '(1/4 1/2 3/4 1))
      (inject! `(mouse-up ,x1 ,y1 left))
      (steps 1)
      (try! 'dropped))
    (let-values ([(x y) (point '(column todo))])
      (inject! `(mouse-move ,x ,y) '(wheel 0 -2))
      (steps 1)
      (try! 'wheel-column))
    (let-values ([(x y) (point 'details)])
      (inject! `(mouse-move ,x ,y) '(wheel 0 -2))
      (steps 1)
      (try! 'wheel-details))
    ;; the title scrolled out of the details comes back when Return
    ;; focuses it
    (key! 'title-revealed 'return)
    (key! 'title-revealed-left 'escape)
    (click! 'menu 'status)
    (key! 'menu-closed 'escape)
    (click! 'calendar 'due)
    (key! 'calendar-key 'right)
    (key! 'calendar-picked 'return)
    (key! 'dialog 'delete)
    (key! 'dialog-canceled 'escape)
    ;; the dialog over a focused field: the field lets go of the keyboard,
    ;; so no caret blinks under the scrim and no frame shows Tasks
    (let-values ([(x y) (point 'details)])
      (inject! `(mouse-move ,x ,y) '(wheel 0 -20))
      (steps 1)
      (try! 'details-end))
    (click! 'item-field 'new-item)
    (click! 'dialog-over-field 'delete)
    (do ([i 0 (+ i 1)]) ((= i 4))
      (set! compared #f)
      (steps 1 530)
      (when (and compared (> (cdr compared) top-rows))
        (set! bad (cons (list 'dialog-asked i) bad))))
    (key! 'dialog-closed 'escape)
    (set-task! 9 'title "Changed from the REPL")
    (steps 1)
    (try! 'repl)
    (resize-window! w 760 600)
    (steps 1)
    (try! 'narrow)
    (click! 'page '(card 10))
    (key! 'page-closed 'escape)
    (close-window! w)
    (check (format "Tasks at ~a%: typing, the caret's blink, hover, a \
                    tooltip, a drag, the wheel, a field revealed, a menu, \
                    the calendar, the dialog, a REPL change and the narrow \
                    page show the \
                    reference, and unfocused or under the dialog it asks \
                    for no frame~a"
                   pct (if (null? bad) "" (format " (not: ~s)" (reverse bad))))
           (null? bad))))

(for-each tasks-scene '(100 150 200))
(set-theme! 'scale 100)
(tasks-reset!)

;;; The Tree: hover over its rows and twisties, a twisty that collapses
;;; and expands, keys that move the selection and expand, the wheel (rows
;;; moved under a still pointer), a later row picked and Return going to
;;; its task's own row, a search dimming rows, a chip in the details, the
;;; Add menu, the narrow page. After each step the screen is the
;;; reference, at 100, 150 and 200%.

(define (tree-scene pct)
  (set-theme! 'scale pct)
  (clear-world!)
  (tasks-reset!)
  (let* ([w (tasks)] [ui (window-ref w 'ui)] [bad '()])
    (define (try! label)
      (unless (matches-reference? (list pct label))
        (set! bad (cons label bad))))
    (define (rows) (ui-memo ui '(tree rows) '#()))
    (define (row-id node) (list 'tree 'row (ui-tree-index (rows) node)))
    (define (point id . twisty?)   ; region id's middle, or its twisty's
      (let ([r (ui-find ui id)])
        (unless r (errorf 'tree-scene "no ~s at ~a%" id pct))
        (let-values ([(cx cy cw ch) (content-rect w)])
          (values
           (exact (floor
                   (+ cx (if (pair? twisty?)
                             (let ([t (cdr (assq 'twisty
                                                 (ui-tree-areas
                                                  (ui-region-x r) 0 1000 0
                                                  (car twisty?))))])
                               (+ (car t) (/ (caddr t) 2)))
                             (+ (ui-region-x r) (/ (ui-region-w r) 2))))))
           (exact (floor (+ cy (ui-region-y r) (/ (ui-region-h r) 2))))))))
    (define (move! label id . twisty?)
      (let-values ([(x y) (apply point id twisty?)])
        (inject! `(mouse-move ,x ,y)))
      (steps 1)
      (try! label))
    (define (click! label id . twisty?)
      (let-values ([(x y) (apply point id twisty?)])
        (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                 `(mouse-up ,x ,y left)))
      (steps 1)
      (try! label))
    (define (key! label key . mods)
      (inject! `(key-down ,key ,mods))
      (steps 1)
      (try! label))
    (fixed-status!)
    (resize-window! w 1100 600)
    (move-window! w 20 70)
    (steps 1)
    (click! 'tree '(view tree))
    (move! 'hover-row (row-id 11))
    (move! 'hover-twisty (row-id 13) 0)
    (click! 'collapsed (row-id 13) 0)
    (click! 'expanded (row-id 13) 0)
    (click! 'select (row-id 22))
    (key! 'down 'down)
    (key! 'left 'left)
    (key! 'collapse 'left)
    (key! 'right 'right)
    (key! 'space #\space)
    (key! 'space-again #\space)
    (click! 'later (row-id '(17 . 31)))
    (key! 'later-down 'down)
    (key! 'later-up 'up)
    (key! 'own-row 'return)
    (let-values ([(x y) (point '(tree body))])
      (inject! `(mouse-move ,x ,y) '(wheel 0 -3))
      (steps 1)
      (try! 'wheel))
    (for-each (lambda (c) (inject! `(text ,(string c)))) (string->list "/gpu"))
    (steps 1)
    (try! 'dimmed)
    (key! 'search-left 'escape)
    (click! 'cleared 'clear)
    (click! 'chip '(blocks 13))
    (click! 'add '(blocked-by add))
    (key! 'add-closed 'escape)
    (set-task! 12 'blocked-by '(16))
    (steps 1)
    (try! 'repl)
    (resize-window! w 760 600)
    (steps 1)
    (try! 'narrow)
    (click! 'page (row-id 13))
    (key! 'page-closed 'escape)
    (close-window! w)
    (check (format "the Tree at ~a%: hover, a twisty, keys, the wheel, a \
                    later row and Return, a search dimming rows, a chip, the \
                    Add menu, a REPL change and the narrow page show the \
                    reference~a"
                   pct (if (null? bad) "" (format " (not: ~s)" (reverse bad))))
           (null? bad))))

(for-each tree-scene '(100 150 200))
(set-theme! 'scale 100)
(tasks-reset!)

;;; ------------------------------------------------------------------
;;; a long text
;;; A description whose first rows are long and the rest short: its first
;;; frame shows its scroll bar from the characters per row seen so far,
;;; far from the true count. Idle steps compute the rest of its rows, and
;;; the one that finishes draws the window again: the screen is then the
;;; reference, its bar where the whole count puts it. Were that frame not
;;; asked for, the estimate would stay on the screen.

(define (scan-scene pct)
  (set-theme! 'scale pct)
  (clear-world!)
  (tasks-reset!)
  (let* ([w (tasks)] [ui (window-ref w 'ui)] [v (window-ref w 'state)]
         [text (string-append
                (apply string-append (make-list 60 "rows that are long, "))
                (apply string-append (make-list 60 "x\n")))]
         [t (add-task! "Scanned" 'status 'review 'description text)])
    (fixed-status!)
    (resize-window! w 1100 600)
    (move-window! w 20 70)
    (steps 1)
    (tasks-select! v t)
    (invalidate! w)
    (steps 1)
    (let* ([lay (ui-memo ui '(description rows) #f)]
           [estimate (edit-layout-total lay)]
           [pending? (pair? (ui-state-scans ui))]
           [first? (shows-reference? (list pct 'estimate))])
      (let loop ([n 0])
        (when (and (< n 100) (pair? (ui-state-scans ui)))
          (steps 1)
          (loop (+ n 1))))
      (let ([settled? (shows-reference? (list pct 'settled))])
        (close-window! w)
        (check (format "a long text at ~a%: its bar shows an estimate (~a \
                        rows) until idle steps have its ~a rows, and \
                        then the screen is the reference"
                       pct estimate (edit-layout-count lay))
               (and pending? first? (edit-layout-done? lay)
                    (> (edit-layout-count lay) (* 2 estimate)) settled?))))))

(for-each scan-scene '(100 200))
(set-theme! 'scale 100)
(tasks-reset!)

;; The description's editor scrolled to its top, its caret at the end,
;; then maximized: its first draw at the new width takes the bar's total
;; from the rows in view, and only then does the caret's row bring the
;; rows to the end. The bar so drawn shows the estimate, so an idle step
;; must draw it again, though no rows are left to compute; were that
;; frame not asked for, the estimate would stay on the screen.

(define (caret-scene pct)
  (set-theme! 'scale pct)
  (clear-world!)
  (tasks-reset!)
  (let* ([w (tasks)] [v (window-ref w 'state)]
         [text (string-append
                (apply string-append (make-list 30 "x\n"))
                (apply string-append (make-list 200 "rows that are long, ")))]
         [t (add-task! "Caret at the end" 'status 'review 'description text)])
    (fixed-status!)
    (tasks-select! v t)
    (steps 2)
    (let* ([ed (tasks-open-editor! v t (string-length text))]
           [eui (window-ref ed 'ui)])
      (steps 2)
      (let ([r (ui-find eui 'text)])
        (let-values ([(cx cy cw ch) (content-rect ed)])
          (inject! `(mouse-move ,(exact (floor (+ cx (ui-region-x r) 20)))
                                ,(exact (floor (+ cy (ui-region-y r) 20)))))
          (do ([i 0 (+ i 1)]) ((= i 30)) (inject! '(wheel 0 10)))))
      (steps 2)
      (toggle-maximize! ed)
      (steps 6)
      (let ([settled? (shows-reference? (list pct 'maximized))])
        (close-window! ed)
        (close-window! w)
        (check (format "the description's editor at ~a%, scrolled to its \
                        top, its caret at the end, maximized: an idle step \
                        draws its bar again from the whole count"
                       pct)
               settled?)))))

(for-each caret-scene '(100 200))
(set-theme! 'scale 100)
(tasks-reset!)

;;; ------------------------------------------------------------------
;;; redefinition

(define (frame-ms n)   ; median time of n forced frames
  (let loop ([i 0] [ms '()])
    (if (= i n)
        (list-ref (sort < ms) (quotient n 2))
        (begin (invalidate!) (steps 1) (loop (+ i 1) (cons *frame-ms* ms))))))

(set-theme! 'scale 100)
(scene! 'S5)
(pause-lifes!)
(let* ([before (frame-ms 9)]
       [plain-draw-window draw-window] [plain-taskbar draw-taskbar]
       [plain-styles *styles*])
  (set! draw-window (lambda (win)
                      (draw-window* win #t)
                      (fill-rect (window-x win) (window-y win) 40 6 #xff0000)))
  (set! draw-taskbar (lambda ()
                       (plain-taskbar)
                       (fill-rect 0 (- (screen-h) 6) 60 6 #x0000ff)))
  (register-style! 'mac "Mac, striped"
    (cons* 'frame-over (lambda (win x y w h focused? hover pressed)
                         (mac-draw-over win x y w h focused? hover pressed)
                         (fill-rect x (+ y h -5) w 5 #x00ff00))
           (style-settings (find-style 'mac))))
  (let* ([after (frame-ms 9)]
         [same (matches-reference? 'redefined)]
         [r (find-window 'repl)]
         [shown (list (pixel-of *canvas* (+ (window-x r) 2) (+ (window-y r) 2))
                      (pixel-of *canvas* 2 (- (screen-h) 2))
                      (pixel-of *canvas* (+ (window-x r) 100)
                                (+ (window-y r) (window-h r) -2)))])
    (set! draw-window plain-draw-window)
    (set! draw-taskbar plain-taskbar)
    (set! *styles* plain-styles)
    (theme-changed!)
    (check (format
            "draw-window, draw-taskbar and a style, redefined: the next frame \
             shows them ~s, is the reference, and takes ~,2f ms (~,2f before)"
            (map (lambda (p) (format "#x~x" p)) shown) after before)
           (and same (equal? shown '(#xffff0000 #xff0000ff #xff00ff00))
                (< after (+ (* 2 before) 0.5))
                (matches-reference? 'restored)))))

;; A REPL evaluation asks for the whole screen when it ends: a drawing
;; procedure it redefines shows on that frame.
(let ([r (repl)] [plain draw-taskbar])
  (steps 2)
  (inject! '(text "(define (draw-taskbar) (fill-rect 0 30 50 50 #xff00ff))")
           '(key-down return ()))
  (steps 1)
  (let ([whole (equal? compared (cons 0 *canvas-ph*))]
        [shown (pixel-of *canvas* 10 40)]
        [same (shows-reference? 'repl-redefined)])
    (set! draw-taskbar plain)
    (close-window! r)
    (check (format "a REPL evaluation asks for the whole screen when it ends \
                    (~a): a drawing procedure it redefines shows on that \
                    frame (#x~x)" whole shown)
           (and whole (= shown #xffff00ff) same (not (repl-proc
                                                      (window-ref r 'state)))
                (matches-reference? 'repl-restored)))))

;;; ------------------------------------------------------------------ wallpaper

;; Is the wallpaper's picture draw-wallpaper's drawing as things are now,
;; drawn straight into a layer?
(define (wallpaper-is-drawn?)
  (let ([l (make-layer* *canvas-w* *canvas-h*)])
    (draw-into-layer! l (lambda () (draw-wallpaper *canvas-w* *canvas-h*)))
    (let ([ok (same-image? (layer-surface (car *wallpaper*))
                           (layer-surface l))])
      (free-layer! l)
      ok)))

;; no window there
(define (desktop-pixel) (pixel-of *canvas* 20 (quotient (screen-h) 2)))

;; A theme change, through set-theme! or behind its back, paints the
;; wallpaper again, whatever key changed, and the next frame shows it. A
;; frame with the theme as it was keeps the picture.
(set-theme! 'scale 200)
(clear-world!)
(steps 2)
(let ([p0 (car *wallpaper*)] [px0 (desktop-pixel)] [top (theme 'desktop-top)]
      [bottom (theme 'desktop-bottom)] [red (theme 'red)])
  (invalidate!)
  (steps 1)
  (let ([kept (eq? (car *wallpaper*) p0)])
    (hashtable-set! *theme* 'desktop-top #x204060)
    (request-frame!)
    (steps 1)
    (let* ([p1 (car *wallpaper*)] [px1 (desktop-pixel)]
           [raw (and (wallpaper-is-drawn?) (matches-reference? 'wallpaper-raw))]
           [t0 (current-time 'time-monotonic)])
      (set-theme! 'desktop-bottom #x603020)
      (steps 1)
      (let* ([ms (ms-since t0)] [p2 (car *wallpaper*)] [px2 (desktop-pixel)]
             [set (and (wallpaper-is-drawn?)
                       (matches-reference? 'wallpaper-set))])
        (set-theme! 'red #x00ff00)   ; a key the wallpaper does not use
        (steps 1)
        (let ([p3 (car *wallpaper*)])
          (hashtable-set! *theme* 'desktop-top top)
          (set-theme! 'desktop-bottom bottom)
          (set-theme! 'red red)
          (steps 1)
          (check (format
                  "a theme change, raw (#x~x -> #x~x) or by set-theme! \
                   (-> #x~x), paints the wallpaper again for the next frame, \
                   whatever key changed \
                   (the change and its frame take ~,1f ms at 200%)"
                  px0 px1 px2 ms)
                 (and kept raw set (not (= px0 px1)) (not (= px1 px2))
                      (not (memq p1 (list p0))) (not (memq p2 (list p0 p1)))
                      (not (memq p3 (list p0 p1 p2)))
                      (= (desktop-pixel) px0) (wallpaper-is-drawn?))))))))

;; A redefined draw-wallpaper shows on the next frame. One that reads the
;; clock shows a still picture (the wallpaper is a picture of its key).
(let ([plain draw-wallpaper])
  (set! draw-wallpaper (lambda (w h) (fill-rect 0 0 w h #x336699)))
  (invalidate!)
  (steps 1)
  (let ([shown (desktop-pixel)]
        [same (and (wallpaper-is-drawn?)
                   (matches-reference? 'wallpaper-redefined))])
    (set! draw-wallpaper (lambda (w h)
                           (fill-rect 0 0 w h
                                      (if (even? (quotient fake-ms 1000))
                                          #x112233
                                          #x445566))))
    (invalidate!)
    (steps 1)
    (let ([p (car *wallpaper*)] [px (desktop-pixel)])
      (steps 3 1000)
      (invalidate!)
      (steps 1)
      (let ([still (and (eq? (car *wallpaper*) p) (= px (desktop-pixel)))])
        (set! draw-wallpaper plain)
        (invalidate!)
        (steps 1)
        (check (format
                "a redefined draw-wallpaper shows on the next frame (#x~x); \
                 one that reads the clock shows a still picture (~a); \
                 the old one is back the frame after"
                shown still)
               (and (= shown #xff336699) same still (wallpaper-is-drawn?)
                    (matches-reference? 'wallpaper-back)))))))

;; The wallpaper in use, defined again, shows on the next frame.
(let ([pattern (theme 'wallpaper)] [plain *wallpapers*])
  (set-theme! 'wallpaper 'flat)
  (steps 1)
  (let ([px0 (desktop-pixel)])
    (define-wallpaper flat "Flat"
      (lambda (x y w h top bottom) (fill-rect x y w h #x336699)))
    (steps 1)
    (let ([shown (desktop-pixel)]
          [same (and (wallpaper-is-drawn?)
                     (matches-reference? 'wallpaper-defined-again))])
      (set! *wallpapers* plain)
      (set-theme! 'wallpaper pattern)
      (steps 1)
      (check (format "the wallpaper in use, defined again, shows on the next \
                      frame (#x~x -> #x~x)" px0 shown)
             (and (= shown #xff336699) (not (= px0 shown)) same
                  (wallpaper-is-drawn?)
                  (matches-reference? 'wallpaper-restored))))))

;;; ------------------------------------------------------------------ Life

;; Each Life window steps a generation (its pixmap's buffers swap), twice:
;; each next frame shows it.
(set-theme! 'scale 200)
(scene! 'S30T)
(pause-lifes!)
(steps 2)
(let ([lifes (filter (lambda (w) (eq? (window-app w) 'life)) (windows))])
  (define (generation!)
    (let ([before (canvas-copy)])
      (for-each (lambda (w) (window-call w 'key #\n '())) lifes)
      (steps 1)
      (let ([changed (> (differing *canvas* before #f) 0)])
        (cairo-surface-destroy before)
        (and changed (matches-reference? 'life)))))
  (let* ([first (generation!)] [second (generation!)])
    (check (format "30 Life windows step a generation, twice: each next \
                    frame shows it and is the reference (~a ~a)" first second)
           (and first second))))

(check (format "the texture, fed only the uploaded rows, was the canvas after \
                every step (~a of ~a); \
                presents only after an upload or an expose (~a bad)"
               (- texture-steps texture-mismatches) texture-steps bad-presents)
       (and (= texture-mismatches 0) (= bad-presents 0) (> texture-steps 400)))

(if (zero? failures)
    (printf "all checks passed\n")
    (printf "~a check(s) FAILED\n" failures))
(exit (if (zero? failures) 0 1))
