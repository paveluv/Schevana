;;; (demo boids3d) — Boids in three dimensions, as Craig Reynolds
;;; first made them (1987), all on the GPU: compute shaders steer the flock
;;; and lay it out on the screen, and a paint draws it: birds far off
;;; against an evening sky over the sea, with the sun setting and a wooded
;;; shore with a lighthouse.
;;; The flock never comes back to the CPU, which only sets the rules, moves
;;; the camera and asks for the shaders with each frame.
;;;
;;; The rules are Boids' rules in space: cohesion, alignment and
;;; separation, a field of view that is a cone, and the two blocker rules
;;; from Flake's "The Computational Beauty of Nature". Clear view steps
;;; along the part of the heading at a right angle to the line to a
;;; blocker, which is what the 2D rule works out, in any number of
;;; dimensions; back off steps straight away. Where Boids wraps around at
;;; the screen's edges, these birds turn back toward the middle of their
;;; space when they leave it (home).
;;;
;;; A bird is a body and two beating wings, swept back and banked into its
;;; turns, seen by a camera that circles the flock: far away, its outline
;;; changes as a real bird's does, a dash from the side and a V from below.
;;; R: random rules · D: the defaults · S: scatter · H: the rules window ·
;;; Space: pause · drag: move around the flock
;;;
;;; This library is the app. Its parts are libraries of their own, in
;;; demo/boids3d/, which it imports: the rules (rules), the code for the
;;; GPU (shaders), the flock in a window (flock), what the window shows of
;;; it (view) and the rules window (rules-window).

(library (demo boids3d)
  (export boids3d)
  (import (chezscheme)
          (only (schevana base) define-state)
          (schevana core)
          (demo boids3d rules)
          (demo boids3d shaders)
          (demo boids3d flock)
          (demo boids3d view)
          (demo boids3d rules-window))

  (define boids3d-step-ns 15000000) ; a step about 60 times a second, as Boids
  (define boids3d-step-ms (quotient boids3d-step-ns 1000000))
  (define boids3d-count 1000)    ; how many a new window starts with

  (define (boids3d-bar-height)
    (max 26 (round (+ (font-line-height 'ui-small) 13))))

  (define (boids3d-status-text n running?)
    (format "~a birds   ~ar random · d defaults · s scatter · h rules · drag \
             to turn · space pause"
            n (if running? "" "paused   ")))

  ;; Returns the size of the flock's field in win: the content above the
  ;; status line.
  (define (boids3d-field-size win)
    (let-values ([(w h) (window-content-size win)])
      (values w (max 1 (- h (boids3d-bar-height))))))

  ;; The newest flock's window while it is open: the one boids3d-ride!
  ;; acts on.
  (define-state *boids3d-flock* #f)

  ;; Sets whether the newest flock steps with its frames or on a timer
  ;; (boids3d-set-ride!): (boids3d-ride! 'timer) at a REPL of the hacker
  ;; edition (--hacker), which has the libraries' own names.
  (define (boids3d-ride! mode)
    (unless *boids3d-flock*
      (errorf 'boids3d-ride! "no Boids 3D window is open"))
    (boids3d-set-ride! *boids3d-flock* mode))

  (define-app (boids3d) "Boids 3D"
    (let ([w 760] [h 520]
          [running? #t] [last-step (now-ns)]
          [drag #f]          ; (x y yaw pitch bearing) where a drag began
          [rules-win #f]
          [flying? #f]       ; whether its timer is set ('ride timer)
          [closed? #f])
      (define (toggle-rules! win)
        (if rules-win
            (close-window! rules-win)
            (set! rules-win
                  (boids3d-open-rules win (lambda () (set! rules-win #f))))))
      ;; While the window rides a timer, the flock steps every 15 ms, seen
      ;; or not, until the window rides frames again or closes. A timer
      ;; more than three steps late starts again from now rather than
      ;; catching up.
      (define (fly! win due)
        (after (max 0 (- due (now-ms)))
               (lambda ()
                 (if (or closed? (not (eq? (window-ref win 'ride) 'timer)))
                     (set! flying? #f)
                     (let ([next (+ due boids3d-step-ms)])
                       (when running? (boids3d-step! win))
                       (fly! win (if (< next (- (now-ms) (* 3 boids3d-step-ms)))
                                     (now-ms)
                                     next)))))))
      (let* ([buffers (boids3d-buffers)]
             [win
              (open-window "Boids 3D"
                'size (cons w (+ h (boids3d-bar-height)))
                'buffers buffers
                'flipped? #f
                'count boids3d-count
                'shapes (make-gpu-buffer (* boids3d-shape-words boids3d-most))
                'tiles #f
                'rules boids3d-default-rules
                'yaw 0.6
                'pitch -0.17         ; from below, the sky behind the flock
                'scene-bearing 1.39  ; the shore ahead, the sun to the left
                'distance 760.0
                'ride 'frames        ; or timer: boids3d-ride!
                'open (lambda (win) (window-frame-soon! win))
                ;; one step per frame, as far as the time since the last
                ;; frame's t, so that the flock moves as evenly as the screen
                ;; shows it; at most three steps' worth, so that a flock seen
                ;; again goes on rather than jumping ahead. While the window
                ;; rides a timer, the timer steps the flock and the frames
                ;; only turn the camera
                'frame (lambda (win t)
                         (window-frame-soon! win)
                         (when (and (eq? (window-ref win 'ride) 'timer)
                                    (not flying?))
                           (set! flying? #t)
                           (fly! win (now-ms)))
                         (let ([k (min 3.0 (/ (- t last-step)
                                              (inexact boids3d-step-ns)))])
                           (set! last-step t)
                           (when (and running? (> k 0.0))
                             (when (eq? (window-ref win 'ride) 'frames)
                               (boids3d-step! win k))
                             ;; the camera circles slowly, by time, unless
                             ;; a drag holds it
                             (unless drag
                               (window-set! win 'yaw
                                            (+ (window-ref win 'yaw)
                                               (* k 0.0015))))
                             (invalidate! win))))
                'draw (lambda (win w h)
                        (let ([bar (boids3d-bar-height)])
                          (boids3d-draw-field win w (- h bar))
                          (fill-box 0 (- h bar) w bar 'bg-1)
                          (draw-text 10 (+ (- h bar) 5)
                                     (boids3d-status-text
                                      (window-ref win 'count) running?)
                                     'text-faint 'ui-small)))
                'key (lambda (win key mods)
                       (case key
                         [(#\r) (boids3d-randomize! win)]
                         [(#\d) (boids3d-defaults! win)]
                         [(#\s) (boids3d-scatter! win)]
                         [(#\h) (toggle-rules! win)]
                         [(#\space) (set! running? (not running?))])
                       (invalidate! win))
                'mouse-doc '((L . "Turn"))
                'mouse-down (lambda (win x y button clicks)
                              (set! drag (list x y (window-ref win 'yaw)
                                               (window-ref win 'pitch)
                                               (window-ref win
                                                           'scene-bearing))))
                'mouse-move (lambda (win x y)
                              (when drag
                                ;; the camera and the scene turn together;
                                ;; only the camera goes on circling
                                (window-set! win 'yaw
                                  (- (caddr drag) (* 0.01 (- x (car drag)))))
                                (window-set! win 'scene-bearing
                                  (- (list-ref drag 4)
                                     (* 0.01 (- x (car drag)))))
                                (window-set! win 'pitch
                                  (max -1.4
                                       (min 1.4
                                            (+ (cadddr drag)
                                               (* 0.01 (- y (cadr drag)))))))
                                (invalidate! win)))
                'mouse-up (lambda (win x y button) (set! drag #f))
                'close (lambda (win)
                         (set! closed? #t)
                         (when (eq? *boids3d-flock* win)
                           (set! *boids3d-flock* #f))
                         (gpu-buffer-release! (car buffers))
                         (gpu-buffer-release! (cdr buffers))
                         (gpu-buffer-release! (window-ref win 'shapes))
                         (let ([t (window-ref win 'tiles)])
                           (when t (gpu-buffer-release! (car t))))))])
        (set! *boids3d-flock* win)
        (boids3d-scatter! win)
        (toggle-rules! win)
        (let-values ([(dx dy dw dh) (desktop-rect)])
          (let ([short (- (+ (window-x win) (window-w win) 12)
                          (window-x rules-win))])
            (when (> short 0)
              (move-window! win (max dx (- (window-x win) short))
                            (window-y win)))))
        (focus-window! win)
        win))))
