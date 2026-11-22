;;; (schevana core screen) — the world's side of core0's window, the one the
;;; world lives in: its scale and canvas, full screen, its icon, and core0's
;;; events as the world reads them. The window itself, SDL's, belongs to
;;; core0 ((schevana core0 window)).
;;;
;;; Core0's events are translated into plain Scheme lists:
;;;   (mouse-move x y) (mouse-down x y button clicks) (mouse-up x y button)
;;;   (wheel dx dy) (key-down key mods) (text "a") (resize w h) (quit) ...
;;; key is a char for printable keys (#\a, #\space) or a symbol ('return,
;;; 'left, 'f1, ...); mods is a list drawn from (ctrl alt shift super).

(library (schevana core screen)
  (export
    screen-event-seen! system-scale-percent wm-screen-resized! screen-rescale!
    screen-init! screen-shutdown! fullscreen? set-fullscreen! toggle-fullscreen!
    screen-set-icon! screen-set-title! screen-set-app-id! *screen-least*
    screen-set-least! screen-system-theme screen-own-frame! screen-own-frame?
    screen-hit-regions! screen-window-action! screen-maximized? screen-events)
  (import (chezscheme)
          (schevana base)
          (schevana core0)
          (schevana core theme-table)
          (schevana core processes)
          (schevana core draw)
          (schevana core pacer))

  (library-layer core)

  ;; Told of every event core0 sends, by its number, whether it means
  ;; anything to the world or not. (schevana services profile) sets it;
  ;; until then it does nothing.
  (define-hook (screen-event-seen! type) (void))
  (define-state *screen-fullscreen* #f)   ; full screen, as headless pretends
  ;; the scale chosen (the setting's, or else the desktop's) that the canvas
  ;; was made at: physical pixels per logical pixel, as an exact number
  (define-state *screen-chosen-scale* 1)
  ;; physical pixels per SDL window unit (2 on a Retina Mac)
  (define-state *pixel-ratio* 1)
  ;; the minimum size SDL last passed on to the window, or #f
  (define-state *screen-min-size* #f)
  ;; the smallest size the window may be dragged to, (w . h) in logical
  ;; pixels
  (define-state *screen-least* '(640 . 400))
  (define-state *headless-size* '(1280 . 800))

  ;;; ---------------------------------------------------------------- scale
  ;;; The world is laid out in logical pixels and drawn *screen-chosen-scale*
  ;;; times bigger. The scale follows the desktop unless the theme key 'scale
  ;;; (a percentage; 0 for automatic) overrides it.

  (at-load (theme-table-default! 'scale 0))

  (define (wanted-scale)
    (let ([p (theme 'scale)])
      (if (and (fixnum? p) (> p 0)) (/ (clamp p 50 400) 100) (system-scale))))

  ;; The scale the desktop asks for, rounded to the percent: SDL's display
  ;; scale for the window, which is the pixel ratio (2 on macOS and on
  ;; Wayland at 200%) times the desktop's own scale (under X11, Xft.dpi, with
  ;; 96 as 100%, which SDL reads once, as it starts). SDL gives 0 when it
  ;; fails, and the scale is then 1.
  (define (system-scale)
    (let ([s (core0-window-scale)])
      (if (> s 0) (/ (exact (round (* 100 s))) 100) 1)))

  (define (system-scale-percent) (exact (round (* 100 (system-scale)))))

  ;; Converts SDL window units (mouse positions, fractional in SDL3) to
  ;; logical pixels.
  (define (screen-units->world v)
    (floor (/ (* (exact v) *pixel-ratio*) *screen-chosen-scale*)))

  ;; Called when the screen has a new size or scale, to lay out again what
  ;; is on it. (schevana core windows) sets it; until then it does nothing.
  (define-hook (wm-screen-resized!) (void))

  ;; After the 'scale setting changes, lays the world out again at the new
  ;; scale.
  (define (screen-rescale!)
    (when (screen-sync-size!)
      (wm-screen-resized!)))

  ;; Returns the size of core0's window, in window units, for a w × h
  ;; logical world drawn at scale, with ratio physical pixels per window
  ;; unit.
  (define (screen-window-size w h scale ratio)
    (values (exact (round (/ (* w scale) ratio)))
            (exact (round (/ (* h scale) ratio)))))

  ;; Opens the screen in mode 'headless or 'sdl. With fullscreen? true it
  ;; starts full screen instead of in a w × h window.
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
       ;; holds, and the desktop's scale, are known only once the window
       ;; exists, so it opens hidden at one unit per logical pixel, and is
       ;; sized and centered before it is shown. Core0 with a thread of its
       ;; own has opened it already, at the desktop's scale.
       (unless (core0-forked?) (core0-window-open! w h *screen-fullscreen*))
       (let*-values ([(uw uh pw ph) (screen-read-sizes)]
                     [(nw nh)
                      (screen-window-size w h (wanted-scale) *pixel-ratio*)])
         (unless (or *screen-fullscreen* (and (= nw uw) (= nh uh)))
           (core0-window-resize! nw nh)))
       (unless (core0-forked?) (core0-window-show!))
       (screen-sync-size!)
       ;; what it posted (the minimum size) goes to the window
       (unless (core0-forked?) (core0-step!))]
      [else (errorf 'screen-init! "unknown mode ~s" mode)]))

  (define (screen-shutdown!)
    (cond [(core0-forked?) (core0-quit!)]
          [(eq? *core0-mode* 'sdl) (core0-window-close!)]))

  ;;; ------------------------------------------------------------------
  ;;; full screen

  (define (fullscreen?)
    (if (eq? *core0-mode* 'sdl) (core0-window-fullscreen?) *screen-fullscreen*))

  ;; Full screen is at the desktop's own resolution (SDL3's default
  ;; full-screen mode): the world just gets a bigger canvas (core0 sends a
  ;; resize event).
  (define (set-fullscreen! on?)
    (when (eq? *core0-mode* 'sdl) (core0-window-fullscreen! on?))
    (set! *screen-fullscreen* (and on? #t))
    (request-redraw!))

  (define (toggle-fullscreen!) (set-fullscreen! (not (fullscreen?))))

  ;;; ---------------------------------------------------------------- icon

  ;; Sets the icon of core0's window, which the desktop's taskbar or dock
  ;; shows (under X11, and under Wayland compositors with the
  ;; xdg-toplevel-icon protocol; GNOME takes icons from .desktop files
  ;; instead, and SDL's call fails there). draw is called on a clear
  ;; size × size image.
  (define (screen-set-icon! size draw)
    (when (eq? *core0-mode* 'sdl)
      (drawing->bytes-then size size 1 (lambda () (draw size)) #t
                           (lambda (bytes)
                             (unpremultiply! bytes)
                             (core0-window-icon! size bytes)))))

  ;; Turns premultiplied pixels, as images keep them, into straight ones, in
  ;; place.
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

  ;; Returns the window's size in window units and in physical pixels, as
  ;; (values w h pw ph), and sets *pixel-ratio* from them.
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
                 (screen-least-tell!)
                 #t))))]
      [(headless)
       (let ([scale (wanted-scale)])
         (and (not (= scale *screen-chosen-scale*))
              (begin
                (set! *screen-chosen-scale* scale)
                (canvas-create! (car *headless-size*) (cdr *headless-size*)
                                scale)
                #t)))]
      [else #f]))

  ;; Core0's window may not shrink below *screen-least*, in logical pixels.
  ;; SDL is told only when that changes, because each call also sets the
  ;; window's size again (a request to the window manager, in the middle of
  ;; a drag). In full screen SDL may not pass it on (under X11 it does not),
  ;; so it is told again afterwards.
  (define (screen-least-tell!)
    (let* ([unit (lambda (n)
                   (exact (ceiling (/ (* n *screen-chosen-scale*)
                                      *pixel-ratio*))))]
           [m (cons (unit (car *screen-least*)) (unit (cdr *screen-least*)))])
      (unless (equal? m *screen-min-size*)
        (core0-window-minimum! (car m) (cdr m))
        (set! *screen-min-size* (and (not (fullscreen?)) m)))))

  ;; Sets the smallest size the window may be dragged to, w × h logical
  ;; pixels. A program sets its own (a host app, for its one window).
  (define (screen-set-least! w h)
    (set! *screen-least* (cons w h))
    (when (eq? *core0-mode* 'sdl) (screen-least-tell!)))

  ;;; ---------------------------------------------------------------- the host

  ;; Sets the window's title, which the desktop shows (in its title bar, the
  ;; switcher, the dock).
  (define (screen-set-title! title) (core0-window-title! title))

  ;; Sets who the window is to the desktop, which matches the window to a
  ;; desktop entry by this id (core0-app-id). A program sets its own before
  ;; its window opens.
  (define (screen-set-app-id! id) (core0-app-id! id))

  ;; The desktop's preference: 'light, 'dark, or #f where it gives none
  ;; (headless, or a desktop that doesn't tell). A change rebuilds the theme
  ;; (screen-event->world), whose palette may follow it ((schevana core
  ;; theme), 'palette-dark).
  (define (screen-system-theme) (core0-system-theme))

  ;; A frame of the program's own where the desktop draws none (a host
  ;; app's header bar, under GNOME). It is asked for before the window opens
  ;; (screen-own-frame!); screen-own-frame? says whether it is so once the
  ;; window has opened.
  (define (screen-own-frame! on?) (core0-own-frame! on?))
  (define (screen-own-frame?) (core0-own-frame?))

  ;; The parts of the window by which the desktop moves or resizes it, when
  ;; the program draws its own frame: ((kind x y w h) ...) in logical
  ;; pixels, where the first region that holds a point wins. kind is one of
  ;; screen-hit-kinds (normal means the point is the program's own). Core0
  ;; is told when the regions change.
  (define screen-hit-kinds
    '(normal move resize-tl resize-t resize-tr resize-r resize-br resize-b
      resize-bl resize-l))
  (define-state *screen-hit-regions* '())

  (define (screen-hit-regions! regions)
    (unless (equal? regions *screen-hit-regions*)
      (set! *screen-hit-regions* regions)
      (core0-window-hit-regions!
       (list->vector
        (apply append
               (map (lambda (r)
                      (cons (list-index (lambda (k) (eq? k (car r)))
                                        screen-hit-kinds)
                            (map screen-units (cdr r))))
                    regions))))))

  ;; Converts logical pixels to the window's units.
  (define (screen-units v)
    (exact (round (/ (* v *screen-chosen-scale*) *pixel-ratio*))))

  ;; Maximizes, restores or minimizes the window, or shows the desktop's
  ;; menu for it at (x, y) in logical pixels.
  (define (screen-window-action! action . at)
    (apply core0-window-action! action (map screen-units at)))

  (define (screen-maximized?) (core0-window-maximized?))

  ;;; ---------------------------------------------------------------- events

  ;; Returns an event of core0's as the world's, with positions in logical
  ;; pixels. A change of the window's size becomes (resize w h), for which
  ;; the world is laid out again, or #f when nothing changed; a change of
  ;; the desktop's light or dark preference rebuilds the theme and becomes
  ;; #f.
  (define (screen-event->world e)
    (case (car e)
      [(mouse-move mouse-down mouse-up)
       (cons* (car e) (screen-units->world (cadr e))
              (screen-units->world (caddr e)) (cdddr e))]
      [(window-resized)
       (and (screen-sync-size!) (list 'resize *canvas-w* *canvas-h*))]
      [(system-theme-changed) (theme-changed!) #f]
      [else e]))

  ;; Returns core0's events as the world's, after telling
  ;; screen-event-seen! of each one. With one thread for both, it first
  ;; steps core0, which drains its events into the world's inbox, and there
  ;; is nothing to wait for. With core0 on a thread of its own, it first
  ;; waits up to wait-ms until it is woken: while a frame of core1's waits
  ;; for core0, this is a wait for the screen, which holds core0 meanwhile;
  ;; while ticks keep to the compositor's latches, it waits for the next
  ;; latch.
  (define (screen-events wait-ms)
    (core0-trace! 20 wait-ms)
    (cond [(not (core0-forked?)) (core0-step!)]
          [(gpu-frame-waiting?)
           (with-profile-span 'vsync-wait 'acquire (core0-world-wait! wait-ms))]
          ;; until the next latch, the screen's, though input wakes it
          [(and (pacer-wanted?) (pacer-on-latch?))
           (with-profile-span 'vsync-wait 'latch (core0-world-wait! wait-ms))]
          [else (core0-world-wait! wait-ms)])
    (core0-trace! 21 0)
    (let-values ([(events types) (core0-window-events)])
      (unless (null? types) (core0-trace! 27 (length types)))
      (call-with-values core0-input-ns-take! frame-input-came!)
      (for-each (lambda (type) (screen-event-seen! type)) types)
      (filter values (map screen-event->world events)))))
