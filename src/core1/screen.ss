;;; screen.ss — the world's side of core0's window, the one it lives in:
;;; its scale and canvas, full screen, its icon, and core0's events as the
;;; world reads them. The window itself, SDL's, is core0's
;;; (src/core0/window.ss).
;;;
;;; Core0's events are translated into plain Scheme lists:
;;;   (mouse-move x y) (mouse-down x y button clicks) (mouse-up x y button)
;;;   (wheel dx dy) (key-down key mods) (text "a") (resize w h) (quit) ...
;;; key is a char for printable keys (#\a, #\space) or a symbol ('return,
;;; 'left, 'f1, ...); mods is a list drawn from (ctrl alt shift super).

;; told of every event core0 sends, by its number, whether it means
;; anything to the world or not
(defvar *screen-event-seen* void)
(defvar *screen-fullscreen* #f)   ; what headless mode pretends
;; the scale chosen (the setting's, or else the desktop's) that the canvas
;; was made at: physical pixels per logical pixel, exact
(defvar *screen-chosen-scale* 1)
;; physical pixels per SDL window unit (2 on a Retina Mac)
(defvar *pixel-ratio* 1)
;; the minimum size SDL last passed on to the window, or #f
(defvar *screen-min-size* #f)
(defvar *headless-size* '(1280 . 800))

;;; ------------------------------------------------------------------ scale
;;; The world is laid out in logical pixels and drawn *screen-chosen-scale*
;;; times bigger. The scale follows the desktop unless the theme key 'scale
;;; (a percentage; 0 for automatic) overrides it.

(define (wanted-scale)
  (let ([p (theme 'scale)])
    (if (and (fixnum? p) (> p 0)) (/ (clamp p 50 400) 100) (system-scale))))

;; What the desktop asks for, to the percent: SDL's display scale for the
;; window, the pixel ratio (2 on macOS and Wayland at 200%) times the
;; desktop's own scale (under X11 Xft.dpi, 96 being 100%, which SDL reads
;; once, as it starts). 0 is SDL's failure.
(define (system-scale)
  (let ([s (core0-window-scale)])
    (if (> s 0) (/ (exact (round (* 100 s))) 100) 1)))

(define (system-scale-percent) (exact (round (* 100 (system-scale)))))

;; SDL window units (mouse positions, fractional in SDL3) to logical
;; pixels.
(define (screen-units->world v)
  (floor (/ (* (exact v) *pixel-ratio*) *screen-chosen-scale*)))

;; After the 'scale setting changed: lay the world out again at the new scale.
(define (screen-rescale!)
  (when (screen-sync-size!)
    (wm-screen-resized!)))

;; Core0's window's size in window units for a w × h logical world drawn
;; at scale, with ratio physical pixels per window unit.
(define (screen-window-size w h scale ratio)
  (values (exact (round (/ (* w scale) ratio)))
          (exact (round (/ (* h scale) ratio)))))

;; fullscreen?: start full screen instead of in a w × h window.
(define (screen-init! mode w h . fullscreen?)
  (set! *screen-fullscreen* (and (pair? fullscreen?) (car fullscreen?)))
  (set! *screen-min-size* #f)
  (case mode
    [(headless)
     (set! *headless-size* (cons w h))
     (unless (core0-forked?) (core0-window-headless!))
     (set! *screen-chosen-scale* (wanted-scale))
     (canvas-create! w h *screen-chosen-scale*)]
    [(sdl)
     ;; w × h are logical pixels. How many physical pixels a window unit
     ;; holds, and the desktop's scale, are known once the window is there,
     ;; so it opens hidden, a unit per logical pixel, and is sized and
     ;; centered before it is shown. Core0 with a thread of its own opened
     ;; it already, at the desktop's scale.
     (unless (core0-forked?) (core0-window-open! w h *screen-fullscreen*))
     (let*-values ([(uw uh pw ph) (screen-read-sizes)]
                   [(nw nh)
                    (screen-window-size w h (wanted-scale) *pixel-ratio*)])
       (unless (or *screen-fullscreen* (and (= nw uw) (= nh uh)))
         (core0-window-resize! nw nh)))
     (unless (core0-forked?) (core0-window-show!))
     (screen-sync-size!)
     ;; what it posted (the least size) goes to the window
     (unless (core0-forked?) (core0-step!))]
    [else (errorf 'screen-init! "unknown mode ~s" mode)]))

(define (screen-shutdown!)
  (cond [(core0-forked?) (core0-quit!)]
        [(eq? *core0-mode* 'sdl) (core0-window-close!)]))

;;; ------------------------------------------------------------------
;;; full screen

(define (fullscreen?)
  (if (eq? *core0-mode* 'sdl) (core0-window-fullscreen?) *screen-fullscreen*))

;; Full screen at the desktop's own resolution (SDL3's default full-screen
;; mode): the world just gets a bigger canvas (core0 sends a resize
;; event).
(define (set-fullscreen! on?)
  (when (eq? *core0-mode* 'sdl) (core0-window-fullscreen! on?))
  (set! *screen-fullscreen* (and on? #t))
  (invalidate!))

(define (toggle-fullscreen!) (set-fullscreen! (not (fullscreen?))))

;;; ------------------------------------------------------------------ icon

;; Core0's window's icon, which the desktop's taskbar or dock shows (under
;; X11, and Wayland compositors with the xdg-toplevel-icon protocol; GNOME
;; takes icons from .desktop files instead, and SDL's call fails there).
;; draw is called on a clear size × size image.
(define (screen-set-icon! size draw)
  (when (eq? *core0-mode* 'sdl)
    (drawing->bytes-then size size 1 (lambda () (draw size)) #t
                         (lambda (bytes)
                           (unpremultiply! bytes)
                           (core0-window-icon! size bytes)))))

;; Pixels premultiplied, as images keep them, made straight.
(define (unpremultiply! bytes)
  (do ([i 0 (+ i 4)]) ((>= i (bytevector-length bytes)))
    (let ([a (bytevector-u8-ref bytes (+ i 3))])
      (when (fx< 0 a 255)
        (do ([k 0 (+ k 1)]) ((= k 3))
          (bytevector-u8-set!
           bytes (+ i k)
           (fxmin 255 (fxquotient (fx+ (fx* (bytevector-u8-ref bytes (+ i k))
                                            255)
                                       (fxquotient a 2))
                                  a))))))))

;; The window's size in window units and in physical pixels, (values w h pw
;; ph); sets *pixel-ratio* from them.
(define (screen-read-sizes)
  (let-values ([(w h pw ph) (core0-window-sizes)])
    (set! *pixel-ratio* (/ pw (max w 1)))
    (values w h pw ph)))

;; Re-reads the window's pixel size and the scale; the canvas follows when
;; either changed. Returns #t if they did.
(define (screen-sync-size!)
  (case *core0-mode*
    [(sdl)
     (let-values ([(w h pw ph) (screen-read-sizes)])
       (let ([scale (wanted-scale)])
         (if (and (= pw (canvas-pixel-width)) (= ph (canvas-pixel-height))
                  (= scale *screen-chosen-scale*))
             #f
             (begin
               (set! *screen-chosen-scale* scale)
               (canvas-create-pixels! pw ph scale)
               ;; Core0's window may not shrink below 640 × 400 logical pixels.
               ;; SDL is told only when that changes: each call also sets the
               ;; window's size again (a request to the window manager,
               ;; mid-drag). In full screen SDL may not pass it on (under X11
               ;; it does not), so it is told again after.
               (let ([m (cons
                         (exact (ceiling (/ (* 640 scale) *pixel-ratio*)))
                         (exact (ceiling (/ (* 400 scale) *pixel-ratio*))))])
                 (unless (equal? m *screen-min-size*)
                   (core0-window-minimum! (car m) (cdr m))
                   (set! *screen-min-size* (and (not (fullscreen?)) m))))
               #t))))]
    [(headless)
     (let ([scale (wanted-scale)])
       (and (not (= scale *screen-chosen-scale*))
            (begin
              (set! *screen-chosen-scale* scale)
              (canvas-create! (car *headless-size*) (cdr *headless-size*) scale)
              #t)))]
    [else #f]))

;;; ------------------------------------------------------------------ events

;; Steps core0, which drains its events into the world's inbox: on one
;; thread, headless, there is nothing to wait for. Or, core0 on a thread
;; of its own, waits up to wait-ms till it's woken: with a frame of core1's
;; waiting for core0, a wait for the screen, which holds core0 meanwhile;
;; or, ticks keeping to the compositor's latches, for the next latch.
;; Then the inbox: core0's events, each told to *screen-event-seen*, as
;; the world's.
(define (screen-events wait-ms)
  (core0-trace! 20 wait-ms)
  (cond [(not (core0-forked?)) (core0-step!)]
        [(gpu-frame-waiting?)
         (with-profile-span 'vsync-wait 'acquire (core0-world-wait! wait-ms))]
        ;; till the next latch: the screen's, though input wakes it
        [(and (pacer-wanted?) (pacer-on-latch?))
         (with-profile-span 'vsync-wait 'latch (core0-world-wait! wait-ms))]
        [else (core0-world-wait! wait-ms)])
  (core0-trace! 21 0)
  (let-values ([(events types) (core0-window-events)])
    (unless (null? types) (core0-trace! 27 (length types)))
    (call-with-values core0-input-ns-take! frame-input-came!)
    (for-each (lambda (type) (*screen-event-seen* type)) types)
    (filter values (map screen-event->world events))))

;; An event of core0's as the world's: positions in logical pixels; a
;; change of the window's size, the world laid out again, (resize w h), or
;; #f when nothing changed.
(define (screen-event->world e)
  (case (car e)
    [(mouse-move mouse-down mouse-up)
     (cons* (car e) (screen-units->world (cadr e))
            (screen-units->world (caddr e)) (cdddr e))]
    [(window-resized)
     (and (screen-sync-size!) (list 'resize *canvas-w* *canvas-h*))]
    [else e]))
