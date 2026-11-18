;;; tests/units/sdl.ss — core0's SDL side with no SDL: its events decoded
;;; from a hand-filled SDL_Event, and its window code run against a
;;; stand-in for every SDL call it binds.

;;; SDL3's event layout, from a hand-filled SDL_Event: the offsets are
;;; SDL_events.h's (3.2). Core0 decodes it; the world lays it out.
(define (decode-event type . fields)   ; fields: (type offset value) ...
  (do ([i 0 (+ i 1)]) ((= i 128)) (foreign-set! 'unsigned-8 *sdl-event* i 0))
  (foreign-set! 'unsigned-32 *sdl-event* 0 type)
  (for-each (lambda (f) (foreign-set! (car f) *sdl-event* (cadr f) (caddr f)))
            fields)
  (let ([e (sdl-event->list *sdl-event*)])
    (and e (screen-event->world e))))

(set! *wheel-rest* '(0 . 0))
;; the decoded wheel events, in order (map's order is unspecified)
(let ([wheel (lambda ds
               (let loop ([ds ds] [acc '()])
                 (if (null? ds)
                     (reverse acc)
                     (loop (cdr ds)
                           (cons (decode-event SDL_EVENT_MOUSE_WHEEL
                                               `(float 28 ,(car ds)))
                                 acc)))))])
  (check "SDL3 events decode: a key with its modifiers, float mouse \
          positions, and wheel fractions summed into whole steps, the \
          leftover dropped when the wheel turns back"
         (and (equal? (decode-event SDL_EVENT_KEY_DOWN '(unsigned-32 28 #x61)
                                    '(unsigned-16 32 #x41))
                      '(key-down #\a (ctrl shift)))
              (equal? (decode-event SDL_EVENT_MOUSE_MOTION '(float 28 10.75)
                                    '(float 32 20.25))
                      (list 'mouse-move (screen-units->world 10.75)
                            (screen-units->world 20.25)))
              (equal? (wheel 0.4 0.4 -0.4 -0.4 -0.4)
                      '(#f #f #f #f (wheel 0 -1))))))

;;; Core0's SDL code, run against a stand-in for SDL: every SDL call
;;; src/core0/ffi.ss and src/core0/sdl.ss bind is replaced in core0's
;;; environment (one with no stand-in raises), so nothing here reaches the
;;; real SDL or opens a window. The fake window is fake-units window units
;;; big with fake-ratio physical pixels per unit, on a desktop that asks
;;; for fake-desktop (Xft.dpi / 96 under X11), so its display scale is
;;; their product, as SDL3's is; its texture is an image that uploads copy
;;; rows into, as SDL_UpdateTexture does. *core0-mode* is 'sdl only around
;;; single core0 calls, so steps stay headless.

(define fake-sdl-names
  (apply append
         (map (lambda (f)
                (call-with-input-file (string-append *schevana-root* f)
                  (lambda (p)
                    (let loop ([acc '()])
                      (let ([x (read p)])
                        (cond
                          [(eof-object? x) acc]
                          [(and (pair? x)
                                (memq (car x) '(define-foreign
                                                define-foreign/collect-safe))
                                (string-prefix? "SDL_" (caddr x))
                                ;; plain memory and the GPU's: kept
                                (not (member (caddr x)
                                             '("SDL_memcpy" "SDL_memset")))
                                (not (string-contains-ci? (caddr x) "GPU")))
                           (loop (cons (cadr x) acc))]
                          [else (loop acc)]))))))
              '("/src/core0/ffi.ss" "/src/core0/sdl.ss"))))

(define fake-units '(1280 . 800))
(define fake-ratio 1)
(define fake-desktop 1)
(define fake-flags 0)
(define fake-hints '())        ; the hints set, newest first
(define fake-queue '())        ; the event types SDL_PollEvent hands out next
(define fake-log '())          ; what was asked of the window, newest first
(define fake-unfaked '())      ; SDL calls made that have no stand-in

(define (fake-log! . entry) (set! fake-log (cons entry fake-log)))

(define (fake-sdl name)
  (define (pair! a b x y)
    (foreign-set! 'integer-32 a 0 x)
    (foreign-set! 'integer-32 b 0 y)
    #t)
  (define (poll buf)
    (and (pair? fake-queue)
         (begin
           (foreign-set! 'unsigned-32 buf 0 (car fake-queue))
           (set! fake-queue (cdr fake-queue))
           #t)))
  (case name
    [(sdl-init) (lambda (flags) #t)]
    ;; the type of core0's wake event: SDL's first of its users'
    [(sdl-register-events) (lambda (n) #x8000)]
    [(sdl-set-hint)
     (lambda (k v) (set! fake-hints (cons (cons k v) fake-hints)) #t)]
    [(sdl-start-text-input) (lambda (win) #t)]
    [(sdl-get-window-display-scale)
     (lambda (win) (inexact (* fake-ratio fake-desktop)))]
    [(sdl-create-window)
     (lambda (title w h flags)
       (set! fake-units (cons w h))
       (set! fake-flags flags)
       (fake-log! 'create w h
                  (if (logtest flags SDL_WINDOW_HIDDEN) 'hidden 'shown))
       1)]
    [(sdl-set-window-size)
     (lambda (win w h) (set! fake-units (cons w h)) (fake-log! 'size w h) #t)]
    [(sdl-set-window-position)
     (lambda (win x y)
       (fake-log! 'position
                  (if (= x y SDL_WINDOWPOS_CENTERED) 'centered (list x y)))
       #t)]
    [(sdl-show-window) (lambda (win) (fake-log! 'show) #t)]
    [(sdl-set-window-minimum-size)
     (lambda (win w h) (fake-log! 'minimum w h) #t)]
    [(sdl-get-window-flags) (lambda (win) fake-flags)]
    [(sdl-get-window-properties) (lambda (win) 0)]
    [(sdl-get-pointer-property) (lambda (props name default) default)]
    [(sdl-get-number-property) (lambda (props name default) default)]
    [(sdl-get-current-video-driver) (lambda () "dummy")]
    [(sdl-get-version) (lambda () 3002010)]
    [(sdl-get-string-property) (lambda (props name default) default)]
    [(sdl-get-window-size)
     (lambda (win w h) (pair! w h (car fake-units) (cdr fake-units)))]
    [(sdl-get-window-size-in-pixels)
     (lambda (win w h)
       (pair! w h (* fake-ratio (car fake-units))
              (* fake-ratio (cdr fake-units))))]
    [(sdl-get-display-for-window) (lambda (win) 0)]
    [(sdl-get-current-display-mode) (lambda (display) 0)]   ; none: 60 Hz
    [(sdl-get-error) (lambda () "")]
    [(sdl-get-clipboard-text) (lambda () 0)]
    [(sdl-poll-event) poll]
    [(sdl-get-ticks-ns) (top-level-value name core0-env)]   ; SDL's own
    [(sdl-get-num-logical-cpu-cores) (top-level-value name core0-env)]
    [else (lambda args
            (set! fake-unfaked (cons name fake-unfaked))
            (errorf name "the fake SDL has no stand-in for this"))]))

;; Runs thunk with the fake SDL in place of the real one, the GPU's frames
;; going on to its target.
(define (with-fake-sdl thunk)
  (let ([saved (map (lambda (n) (top-level-value n core0-env))
                    fake-sdl-names)]
        [claim gpu-claim-window!])
    (dynamic-wind
      (lambda ()
        (for-each (lambda (n) (set-top-level-value! n (fake-sdl n) core0-env))
                  fake-sdl-names)
        (set! gpu-claim-window! (lambda (window) (void))))
      thunk
      (lambda ()
        (for-each (lambda (n v) (set-top-level-value! n v core0-env))
                  fake-sdl-names saved)
        (set! gpu-claim-window! claim)))))

;; SDL reports window events (through core0's real event loop); the
;; world handles what core0 makes of them.
(define (fake-event! . types)
  (set! fake-queue types)
  (apply inject! (fluid-let ([*core0-mode* 'sdl]) (screen-events 0)))
  (steps 2))

;; As SDL3 reports a change of size or of pixel ratio: each of the three
;; events may come alone, and the first makes the change.
(define (fake-resize! units ratio)
  (set! fake-units units)
  (set! fake-ratio ratio)
  (fake-event! SDL_EVENT_WINDOW_RESIZED SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED
               SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED))

(test-with-quiet-status
 (lambda ()
   (fluid-let ([*screen-min-size* #f] [*pixel-ratio* 1]
               [*screen-chosen-scale* *screen-chosen-scale*])
     (with-fake-sdl
      (lambda ()
        (set! fake-log '())
        (fake-resize! '(1280 . 800) 1)
        (check "the fake SDL had a stand-in for every call"
               (null? fake-unfaked))
        ;; measuring is by the fonts' tables: a scale changes nothing of it
        (let ([before (font-metrics 'mono)])
          ;; a window moved to a 2x display (macOS, Wayland)
          (fake-resize! '(1280 . 800) 2)
          (check (format "a scale change by a resize event leaves the world \
                          its logical size, and the fonts' measures (mono ~s)"
                         before)
                 (and (= *scale* 2.0) (= *canvas-w* 1280) (= *canvas-h* 800)
                      (equal? before (font-metrics 'mono)))))
        (fake-resize! '(1280 . 800) 1)
        ;; the minimum size: plain resizes do not repeat it; in full screen SDL
        ;; only stores it, so it is passed on again after
        (do ([i 1 (+ i 1)]) ((> i 8))
          (fake-resize! (cons (+ 1280 (* 20 i)) (+ 800 (* 12 i))) 1))
        (set! fake-desktop 3/2)
        (set! fake-flags SDL_WINDOW_FULLSCREEN)
        (fake-resize! '(1920 . 1200) 1)
        (set! fake-flags 0)
        (fake-resize! '(1300 . 820) 1)
        (fake-resize! '(1320 . 830) 1)
        (set! fake-desktop 1)
        (fake-resize! '(1280 . 800) 1)
        (let ([minimums
               (reverse
                (filter-map (lambda (e) (and (eq? (car e) 'minimum) (cdr e)))
                            fake-log))])
          (check (format "the minimum size goes to SDL only when it changes, \
                          and again after full screen ~s" minimums)
                 (and (equal? minimums
                              '((640 400) (960 600) (960 600) (640 400)))
                      (= *scale* 1.0) (= *canvas-w* 1280)
                      (= *canvas-h* 800)))))))))

;; Core0's window opens hidden, is sized in window units once the pixel
;; ratio and the desktop's scale are known, centered, and only then shown.
;; SDL is told the app id that the desktop entry names.
(test-with-quiet-status
 (lambda ()
   (fluid-let ([*core0-mode* 'headless] [*sdl-window* 0]
               [*screen-fullscreen* #f] [*screen-min-size* #f]
               [*pixel-ratio* 1] [*screen-chosen-scale* *screen-chosen-scale*])
     (with-fake-sdl
      (lambda ()
        ;; the scale saved (a rescale builds the theme again from it)
        (define (open scale ratio desktop . fullscreen?)
          (set! *scale-setting* scale)
          (hashtable-set! *theme* 'scale scale)
          (set! fake-ratio ratio)
          (set! fake-desktop desktop)
          (set! fake-log '())
          (set! *canvas-pw* 0)   ; as in a new session
          (apply screen-init! 'sdl 1280 800 fullscreen?)
          (set! *core0-mode* 'headless)   ; steps stay headless
          (list (reverse fake-log) *canvas-w* *canvas-h*
                (= fake-flags
                   (fxior SDL_WINDOW_RESIZABLE SDL_WINDOW_HIGH_PIXEL_DENSITY
                          SDL_WINDOW_HIDDEN
                          (if (pair? fullscreen?) SDL_WINDOW_FULLSCREEN 0)))))
        (let* ([explicit (open 200 2 1)]   ; a 2x display (macOS, Wayland)
               [x11 (open 0 1 2)]          ; X11 at Xft.dpi 192
               [wayland (open 0 2 1)]
               [x150 (open 150 1 1)]
               [full (open 200 1 1 #t)])   ; never resized
          (set! *scale-setting* 0)
          (hashtable-set! *theme* 'scale 0)
          (set! fake-flags 0)
          (set! fake-desktop 1)
          (set! *screen-fullscreen* #f)
          (fake-resize! '(1280 . 800) 1)   ; the world as it was
          (check (format "core0's window opens hidden, sized for the pixel \
                          ratio and the desktop's scale, then centered and \
                          shown ~s" (list explicit x11 wayland x150 full))
                 (and (equal? explicit '(((create 1280 800 hidden)
                                          (position centered) (show)
                                          (minimum 640 400))
                                         1280 800 #t))
                      (equal? x11 '(((create 1280 800 hidden) (size 2560 1600)
                                     (position centered) (show)
                                     (minimum 1280 800))
                                    1280 800 #t))
                      (equal? wayland explicit)
                      (equal? x150 '(((create 1280 800 hidden) (size 1920 1200)
                                      (position centered) (show)
                                      (minimum 960 600))
                                     1280 800 #t))
                      (equal? full '(((create 1280 800 hidden)
                                      (position centered) (show)
                                      (minimum 1280 800))
                                     640 400 #t))
                      (= *scale* 1.0) (= *canvas-w* 1280) (= *canvas-h* 800)
                      (null? fake-unfaked))))
        (check (format "SDL gets the app id the desktop entry names, ~s"
                       core0-app-id)
               (equal? (assoc "SDL_APP_ID" fake-hints)
                       (cons "SDL_APP_ID" core0-app-id))))))))
