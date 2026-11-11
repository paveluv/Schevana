;;; host.ss — the world's side of the host window that it lives in: its
;;; scale and canvas, and the host's events as the world reads them. The
;;; window itself, SDL's, is core0's (src/host/window.ss).
;;;
;;; Host events are translated into plain Scheme lists:
;;;   (mouse-move x y) (mouse-down x y button clicks) (mouse-up x y button)
;;;   (wheel dx dy) (key-down key mods) (text "a") (resize w h) (quit) ...
;;; key is a char for printable keys (#\a, #\space) or a symbol ('return,
;;; 'left, 'f1, ...); mods is a list drawn from (ctrl alt shift super).

;; told of every event the host sends, by its number, whether it means
;; anything to the world or not
(defvar *host-event-seen* void)
(defvar *host-fullscreen* #f)   ; what headless mode pretends
(defvar *host-scale* 1)         ; physical pixels per logical pixel, exact
;; physical pixels per SDL window unit (2 on a Retina Mac)
(defvar *pixel-ratio* 1)
;; the minimum size SDL last passed on to the window, or #f
(defvar *host-min-size* #f)
(defvar *headless-size* '(1280 . 800))

;;; ------------------------------------------------------------------ scale
;;; The world is laid out in logical pixels and drawn *host-scale* times
;;; bigger. The scale follows the desktop unless the theme key 'scale (a
;;; percentage; 0 for automatic) overrides it.

(define (wanted-scale)
  (let ([p (theme 'scale)])
    (if (and (fixnum? p) (> p 0)) (/ (clamp p 50 400) 100) (system-scale))))

;; What the desktop asks for, to the percent: SDL's display scale for the
;; window, the pixel ratio (2 on macOS and Wayland at 200%) times the
;; desktop's own scale (under X11 Xft.dpi, 96 being 100%, which SDL reads
;; once, as it starts). 0 is SDL's failure.
(define (system-scale)
  (let ([s (host-window-scale)])
    (if (> s 0) (/ (exact (round (* 100 s))) 100) 1)))

(define (system-scale-percent) (exact (round (* 100 (system-scale)))))

;; SDL window units (mouse positions, fractional in SDL3) to logical
;; pixels.
(define (host->world v) (floor (/ (* (exact v) *pixel-ratio*) *host-scale*)))

;; After the 'scale setting changed: lay the world out again at the new scale.
(define (host-rescale!)
  (when (host-sync-size!)
    (wm-screen-resized!)))

;; The host window's size in window units for a w × h logical world drawn
;; at scale, with ratio physical pixels per window unit.
(define (host-window-size w h scale ratio)
  (values (exact (round (/ (* w scale) ratio)))
          (exact (round (/ (* h scale) ratio)))))

;; fullscreen?: start full screen instead of in a w × h window.
(define (host-init! mode w h . fullscreen?)
  (set! *host-fullscreen* (and (pair? fullscreen?) (car fullscreen?)))
  (set! *host-min-size* #f)
  (case mode
    [(headless)
     (set! *headless-size* (cons w h))
     (unless (host-forked?) (host-window-headless!))
     (set! *host-scale* (wanted-scale))
     (canvas-create! w h *host-scale*)]
    [(sdl)
     ;; w × h are logical pixels. How many physical pixels a window unit
     ;; holds, and the desktop's scale, are known once the window is there,
     ;; so it opens hidden, a unit per logical pixel, and is sized and
     ;; centered before it is shown. Core0 with a thread of its own opened
     ;; it already, at the desktop's scale.
     (unless (host-forked?) (host-window-open! w h *host-fullscreen*))
     (let*-values ([(uw uh pw ph) (host-read-sizes)]
                   [(nw nh)
                    (host-window-size w h (wanted-scale) *pixel-ratio*)])
       (unless (or *host-fullscreen* (and (= nw uw) (= nh uh)))
         (host-window-resize! nw nh)))
     (unless (host-forked?) (host-window-show!))
     (host-sync-size!)
     ;; what it posted (the least size) goes to the window
     (unless (host-forked?) (host-step!))]
    [else (errorf 'host-init! "unknown host mode ~s" mode)]))

(define (host-shutdown!)
  (cond [(host-forked?) (host-quit!)]
        [(eq? *host* 'sdl) (host-window-close!)]))

;;; ------------------------------------------------------------------
;;; full screen

(define (fullscreen?)
  (if (eq? *host* 'sdl) (host-window-fullscreen?) *host-fullscreen*))

;; Full screen at the desktop's own resolution (SDL3's default full-screen
;; mode): the world just gets a bigger canvas (the host sends a resize
;; event).
(define (set-fullscreen! on?)
  (when (eq? *host* 'sdl) (host-window-fullscreen! on?))
  (set! *host-fullscreen* (and on? #t))
  (invalidate!))

(define (toggle-fullscreen!) (set-fullscreen! (not (fullscreen?))))

;;; ------------------------------------------------------------------ icon

;; The host window's icon, which the desktop's taskbar or dock shows (under
;; X11, and Wayland compositors with the xdg-toplevel-icon protocol; GNOME
;; takes icons from .desktop files instead, and SDL's call fails there).
;; draw is called on a clear size × size image.
(define (host-set-icon! size draw)
  (when (eq? *host* 'sdl)
    (drawing->bytes-then size size 1 (lambda () (draw size)) #t
                         (lambda (bytes)
                           (unpremultiply! bytes)
                           (host-window-icon! size bytes)))))

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
(define (host-read-sizes)
  (let-values ([(w h pw ph) (host-window-sizes)])
    (set! *pixel-ratio* (/ pw (max w 1)))
    (values w h pw ph)))

;; Re-reads the window's pixel size and the scale; the canvas follows when
;; either changed. Returns #t if they did.
(define (host-sync-size!)
  (case *host*
    [(sdl)
     (let-values ([(w h pw ph) (host-read-sizes)])
       (let ([scale (wanted-scale)])
         (if (and (= pw (canvas-pixel-width)) (= ph (canvas-pixel-height))
                  (= scale *host-scale*))
             #f
             (begin
               (set! *host-scale* scale)
               (canvas-create-pixels! pw ph scale)
               ;; The host window may not shrink below 640 × 400 logical pixels.
               ;; SDL is told only when that changes: each call also sets the
               ;; window's size again (a request to the window manager,
               ;; mid-drag). In full screen SDL may not pass it on (under X11
               ;; it does not), so it is told again after.
               (let ([m (cons
                         (exact (ceiling (/ (* 640 scale) *pixel-ratio*)))
                         (exact (ceiling (/ (* 400 scale) *pixel-ratio*))))])
                 (unless (equal? m *host-min-size*)
                   (host-window-minimum! (car m) (cdr m))
                   (set! *host-min-size* (and (not (fullscreen?)) m))))
               #t))))]
    [(headless)
     (let ([scale (wanted-scale)])
       (and (not (= scale *host-scale*))
            (begin
              (set! *host-scale* scale)
              (canvas-create! (car *headless-size*) (cdr *headless-size*) scale)
              #t)))]
    [else #f]))

;; How many threads this machine runs at once (logical cores).
(define (host-cpu-count) (sdl-get-num-logical-cpu-cores))

;;; ------------------------------------------------------------------ events

;; Steps core0, which drains its events into the world's inbox: on one
;; thread, headless, there is nothing to wait for. Or, core0 on a thread
;; of its own, waits up to wait-ms till it's woken: with a frame of main's
;; waiting for core0, a wait for the screen, which holds core0 meanwhile;
;; or, ticks keeping to the compositor's latches, for the next latch.
;; Then the inbox: the host's events, each told to *host-event-seen*, as
;; the world's.
(define (host-events wait-ms)
  (host-trace! 20 wait-ms)
  (cond [(not (host-forked?)) (host-step!)]
        [(gpu-frame-waiting?)
         (with-profile-span 'vsync-wait 'acquire (host-world-wait! wait-ms))]
        ;; till the next latch: the screen's, though input wakes it
        [(and (pacer-wanted?) (pacer-on-latch?))
         (with-profile-span 'vsync-wait 'latch (host-world-wait! wait-ms))]
        [else (host-world-wait! wait-ms)])
  (host-trace! 21 0)
  (let-values ([(events types) (host-window-events)])
    (unless (null? types) (host-trace! 27 (length types)))
    (call-with-values host-input-ns-take! frame-input-came!)
    (for-each (lambda (type) (*host-event-seen* type)) types)
    (filter values (map host-event->world events))))

;; A host event as the world's: positions in logical pixels; a change of the
;; window's size, the world laid out again, (resize w h), or #f when nothing
;; changed.
(define (host-event->world e)
  (case (car e)
    [(mouse-move mouse-down mouse-up)
     (cons* (car e) (host->world (cadr e)) (host->world (caddr e)) (cdddr e))]
    [(window-resized)
     (and (host-sync-size!) (list 'resize *canvas-w* *canvas-h*))]
    [else e]))

;;; ------------------------------------------------------------------
;;; local sockets

;;; For what talks to the world from outside. Nothing here waits: a read or a
;;; write asks poll first and does no more than will go at once. A socket is
;;; its file descriptor.

;; sockaddr_un, as Linux and macOS share it: on macOS the first byte is the
;; length and the second the family, which family below folds into one.
(define-ftype host-sockaddr
  (struct [family unsigned-16] [path (array 104 unsigned-8)]))
(define-ftype host-pollfd (struct [fd int] [events short] [revents short]))
(defvar *host-socket-memory*
  (foreign-alloc (+ (ftype-sizeof host-sockaddr)
                    (ftype-sizeof host-pollfd))))
(define host-sockaddr* (make-ftype-pointer host-sockaddr *host-socket-memory*))
(define host-pollfd*
  (make-ftype-pointer host-pollfd
                      (+ *host-socket-memory*
                         (ftype-sizeof host-sockaddr))))
;; a write's most at once: poll's "writable" means this much goes unblocked
(define host-socket-chunk 2048)
(defvar *host-socket-chunk* (make-bytevector host-socket-chunk))

;; The address of path, in the memory above. => its length
(define (host-socket-address! path)
  (let* ([bytes (string->utf8 path)] [n (bytevector-length bytes)]
         [length (+ n 3)] [a host-sockaddr*])
    (unless (< n 104) (errorf 'host-socket "too long a path: ~a" path))
    (ftype-set! host-sockaddr (family) a
                (if (host-mac?)
                    (+ 256 length)
                    1))
    (do ([i 0 (+ i 1)]) ((= i n))
      (ftype-set! host-sockaddr (path i) a (bytevector-u8-ref bytes i)))
    (ftype-set! host-sockaddr (path n) a 0)
    length))

;; A socket listening at path, which only this user can reach; what was there
;; before goes, unless it's a plain file. A client that goes away must fail a
;; write, not end the world: SIGPIPE is ignored from now on.
(define (host-socket-listen path)
  (c-signal 13 1)
  (when (file-exists? path)
    (when (file-regular? path)
      (errorf 'host-socket-listen "there's a file at ~a" path))
    (delete-file path))
  (let ([fd (c-socket 1 1 0)]   ; AF_UNIX, SOCK_STREAM
        [length (host-socket-address! path)])
    (when (< fd 0) (errorf 'host-socket-listen "no socket"))
    (unless (and (zero? (c-bind fd (ftype-pointer-address host-sockaddr*)
                                length))
                 (begin (chmod path #o600) (zero? (c-listen fd 8))))
      (c-close fd)
      (errorf 'host-socket-listen "can't listen at ~a" path))
    fd))

;; A socket connected to path, or #f.
(define (host-socket-connect path)
  (let* ([length (host-socket-address! path)] [fd (c-socket 1 1 0)])
    (if (and (>= fd 0)
             (zero? (c-connect fd (ftype-pointer-address host-sockaddr*)
                               length)))
        fd
        (begin (when (>= fd 0) (c-close fd)) #f))))

;; Would events (poll's: 1, in; 4, out) go at once, or has it ended?
(define (host-socket-ready? fd events)
  (let ([p host-pollfd*])
    (ftype-set! host-pollfd (fd) p fd)
    (ftype-set! host-pollfd (events) p events)
    (ftype-set! host-pollfd (revents) p 0)
    (and (> (c-poll (ftype-pointer-address p) 1 0) 0)
         (not (zero? (ftype-ref host-pollfd (revents) p))))))

;; A client waiting at listening socket fd, as a socket of its own, or #f.
(define (host-socket-accept fd)
  (and (host-socket-ready? fd 1)
       (let ([c (c-accept fd 0 0)]) (and (>= c 0) c))))

;; What's there into bytes: how many; 0, it has ended; #f, nothing yet.
(define (host-socket-read fd bytes)
  (and (host-socket-ready? fd 1)
       (max 0 (c-recv fd bytes (bytevector-length bytes) 0))))

;; bytes from at on, as much as goes now. => where that leaves it, or #f once
;; the other end has gone
(define (host-socket-write fd bytes at)
  (let loop ([at at] [left 32])
    (if (or (= at (bytevector-length bytes)) (= left 0)
            (not (host-socket-ready? fd 4)))
        at
        (let ([n (min host-socket-chunk (- (bytevector-length bytes) at))])
          (bytevector-copy! bytes at *host-socket-chunk* 0 n)
          (let ([sent (c-send fd *host-socket-chunk* n 0)])
            (and (> sent 0) (loop (+ at sent) (- left 1))))))))

;; No more will be written to fd: the other end reads to its end.
(define (host-socket-end-writing fd) (c-shutdown fd 1))

(define (host-socket-close fd) (c-close fd))
