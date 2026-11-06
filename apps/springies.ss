;;; apps/springies.ss — Springies: masses joined by springs, falling,
;;; bouncing and wobbling. Ported from Springies in Agave
;;; (github.com/dharmatech/agave, demos/springies.sls), which followed
;;; Douglas DeCarlo's XSpringies (1991). The physics is written from
;;; XSpringies' behavior, not copied from its (GPL) source, and the models
;;; are made here, in code, not read from its example files.
;;;
;;; The simulation is pure: the particles are a vector, and a step makes a
;;; new one. The world is y-up, as XSpringies' is; only drawing flips it.
;;; The window keeps the model, its particles, springs and settings, as
;;; plain data:
;;; (particle-position (vector-ref (window-ref win 'particles) 0)) => a pt
;;; (springies-set! win 'time-step 0.002)
;;; 1 2 3: ball, tire, snake · R: start over · K: kick · G: gravity
;;; Space: pause · drag: pull a mass
;;; H: the controls window, beside the box (it closes with the box)
;;;
;;; It runs in a sandbox (services/grant.ss), where the names above are: a
;;; REPL in /apps/springies has them.

(app-requests window draw ui timers)

;;; ------------------------------------------------------------------ points

;; A 2D vector of flonums: a position, a velocity, an acceleration or a
;; force. The names are Agave's.
(define-record-type pt
  (nongenerative schevana-springies-pt)
  (fields x y))

(define pt-zero (make-pt 0.0 0.0))

(define (pt+ a b) (make-pt (+ (pt-x a) (pt-x b)) (+ (pt-y a) (pt-y b))))
(define (pt- a b) (make-pt (- (pt-x a) (pt-x b)) (- (pt-y a) (pt-y b))))
(define (pt* p k) (make-pt (* (pt-x p) k) (* (pt-y p) k)))

(define (pt-dot a b) (+ (* (pt-x a) (pt-x b)) (* (pt-y a) (pt-y b))))
(define (pt-norm p) (sqrt (pt-dot p p)))

;;; ------------------------------------------------------------------ particles

;; A point mass: where it is, how it moves, its mass, and how much of its
;; speed it keeps when it bounces off a wall (1.0 all of it, 0.0 none).
(define-record-type particle
  (nongenerative schevana-springies-particle)
  (fields position velocity mass elasticity))

;; Its size on the screen and against the walls: the heavier, the bigger.
(define (particle-radius p) (* 3.0 (sqrt (particle-mass p))))

;; Past a wall of the w × h box, a particle is put back on it, and if it
;; was moving out it turns back. Either way it keeps its elasticity of
;; its speed, across the wall and along it (the loss along is friction).
(define (particle-bounce p w h)
  (let* ([r (particle-radius p)] [e (particle-elasticity p)]
         [x (pt-x (particle-position p))] [y (pt-y (particle-position p))]
         [vx (pt-x (particle-velocity p))] [vy (pt-y (particle-velocity p))]
         [side? (or (< x r) (> x (- w r)))]
         [floor? (or (< y r) (> y (- h r)))])
    ;; a coordinate c moving at v, put back between lo and hi, and v
    ;; turned back if it was taking c farther out
    (define (inside c lo hi) (max lo (min hi c)))
    (define (back c v lo hi)
      (if (or (and (< c lo) (< v 0.0)) (and (> c hi) (> v 0.0)))
          (- (* v e))
          (* v e)))
    (if (not (or side? floor?))
        p
        (make-particle
         (make-pt (inside x r (- w r)) (inside y r (- h r)))
         (make-pt (if side? (back x vx r (- w r)) (* vx e))
                  (if floor? (back y vy r (- h r)) (* vy e)))
         (particle-mass p) e))))

;;; ------------------------------------------------------------------ springs

;; A spring between two particles, by their place in the vector: how stiff
;; it is (Hooke's k), how much it damps, and its length at rest.
(define-record-type spring
  (nongenerative schevana-springies-spring)
  (fields a b stiffness damping rest-length))

;; The force spring s pulls its particle a with (b feels the opposite):
;; Hooke's, along the spring, and damping, against how fast its ends move
;; apart along it. A spring of no length has no direction: no force.
(define (spring-force s particles)
  (let* ([a (vector-ref particles (spring-a s))]
         [b (vector-ref particles (spring-b s))]
         [d (pt- (particle-position a) (particle-position b))]   ; b to a
         [len (pt-norm d)])
    (if (= len 0.0)
        pt-zero
        (let ([stretch (- len (spring-rest-length s))]
              [apart (/ (pt-dot (pt- (particle-velocity a)
                                     (particle-velocity b))
                                d)
                        len)])
          (pt* d (/ (- (+ (* (spring-stiffness s) stretch)
                          (* (spring-damping s) apart)))
                    len))))))

;; A spring from a point that holds still to a particle, by its place in
;; the vector, of no length at rest: how the pointer holds a particle. It
;; goes among the springs.
(define-record-type tether
  (nongenerative schevana-springies-tether)
  (fields particle point stiffness damping))

;; The force tether t pulls its particle with: toward its point, damped
;; against the particle's velocity.
(define (tether-force t particles)
  (let ([p (vector-ref particles (tether-particle t))])
    (pt- (pt* (pt- (tether-point t) (particle-position p))
              (tether-stiffness t))
         (pt* (particle-velocity p) (tether-damping t)))))

;;; ------------------------------------------------------------------ motion
;;; A state is the particles, a vector of them. Runge-Kutta needs states
;;; to add and scale, as vectors do, and a state's rate of change to be a
;;; state too: so it is, each particle's position changing at its
;;; velocity, its velocity at its acceleration.

;; The springs' forces on each particle, summed: a vector like particles.
;; A tether among the springs pulls its one particle.
(define (springies-forces particles springs)
  (let ([forces (make-vector (vector-length particles) pt-zero)])
    (define (push! i f) (vector-set! forces i (pt+ (vector-ref forces i) f)))
    (for-each (lambda (s)
                (if (tether? s)
                    (push! (tether-particle s) (tether-force s particles))
                    (let ([f (spring-force s particles)])
                      (push! (spring-a s) f)
                      (push! (spring-b s) (pt* f -1.0)))))
              springs)
    forces))

;; How the particles change. Gravity is an acceleration, so it pulls
;; light and heavy alike; a spring's force moves a light particle more.
(define (springies-rate particles springs gravity)
  (vector-map (lambda (p f)
                (make-particle (particle-velocity p)
                               (pt+ gravity (pt* f (/ 1.0 (particle-mass p))))
                               (particle-mass p) (particle-elasticity p)))
              particles (springies-forces particles springs)))

;; States add and scale through their positions and velocities; mass and
;; elasticity ride along.
(define (particle+ p q)
  (make-particle (pt+ (particle-position p) (particle-position q))
                 (pt+ (particle-velocity p) (particle-velocity q))
                 (particle-mass p) (particle-elasticity p)))

(define (particle* p k)
  (make-particle (pt* (particle-position p) k) (pt* (particle-velocity p) k)
                 (particle-mass p) (particle-elasticity p)))

(define (state+ s . more)
  (fold-left (lambda (a b) (vector-map particle+ a b)) s more))

(define (state* s k) (vector-map (lambda (p) (particle* p k)) s))

;; The state h seconds on from s, by the classic fourth-order Runge-Kutta:
;; rate gives a state's rate of change.
(define (springies-rk4 rate s h)
  (let* ([k1 (rate s)]
         [k2 (rate (state+ s (state* k1 (/ h 2.0))))]
         [k3 (rate (state+ s (state* k2 (/ h 2.0))))]
         [k4 (rate (state+ s (state* k3 h)))])
    (state+ s (state* (state+ k1 (state* k2 2.0) (state* k3 2.0) k4)
                      (/ h 6.0)))))

;; The particles dt seconds on, in a w × h box: Runge-Kutta, then the walls.
(define (springies-step particles springs gravity dt w h)
  (vector-map (lambda (p) (particle-bounce p w h))
              (springies-rk4 (lambda (s) (springies-rate s springs gravity))
                             particles dt)))

;;; ------------------------------------------------------------------ settings

;; How a model runs, as a plist: gravity's pull, down, in pixels a second
;; squared (980: a pixel a centimeter), whether it is on, the time a step
;; takes, in seconds, and how many steps a frame makes. A frame comes
;; about 60 times a second, so 4 steps of 1/240 s keep the time real:
;; (gravity 980.0 gravity? #t time-step 0.004 steps 4)

(define (springies-setting settings key)
  (let ([at (memq key settings)])
    (if at (cadr at) (errorf 'springies-setting "no setting ~s" key))))

;; Settings with key's value v, the others as they were, in their order.
(define (springies-set-setting settings key v)
  (cond [(null? settings) (errorf 'springies-set-setting "no setting ~s" key)]
        [(eq? (car settings) key) (cons* key v (cddr settings))]
        [else (cons* (car settings) (cadr settings)
                     (springies-set-setting (cddr settings) key v))]))

(define (springies-gravity settings)
  (if (springies-setting settings 'gravity?)
      (make-pt 0.0 (- (springies-setting settings 'gravity)))
      pt-zero))

;; One frame in a w × h box: the settings' steps.
(define (springies-frame particles springs settings w h)
  (let ([g (springies-gravity settings)]
        [dt (springies-setting settings 'time-step)])
    (let loop ([ps particles] [n (springies-setting settings 'steps)])
      (if (= n 0)
          ps
          (loop (springies-step ps springs g dt w h) (- n 1))))))

;;; ------------------------------------------------------------------ models
;;; Each made in code to fit a w × h box: particles placed by geometry, and
;;; springs between them, each at rest at the length it starts at.

;; A model as it starts: its particles, its springs, and the settings it
;; runs best with.
(define-record-type springies-model
  (nongenerative schevana-springies-model)
  (fields particles springs settings))

;; n points evenly around a circle of radius r about c.
(define (springies-ring c r n)
  (map (lambda (i)
         (let ([a (/ (* 2.0 pi i) n)])
           (pt+ c (make-pt (* r (cos a)) (* r (sin a))))))
       (iota n)))

;; Particles of mass m and elasticity e at points, moving as one body
;; would: at velocity v, and turning about c at spin radians a second,
;; counterclockwise.
(define (springies-body points c v spin m e)
  (map (lambda (q)
         (let ([r (pt- q c)])
           (make-particle q
                          (pt+ v (make-pt (* (- spin) (pt-y r))
                                          (* spin (pt-x r))))
                          m e)))
       points))

;; Springs of stiffness k and damping d between particles, one for each
;; pair of indexes (a b), at rest at the length they start at.
(define (springies-springs particles pairs k d)
  (map (lambda (pair)
         (let ([a (car pair)] [b (cadr pair)])
           (make-spring a b k d
                        (pt-norm (pt- (particle-position
                                       (vector-ref particles a))
                                      (particle-position
                                       (vector-ref particles b)))))))
       pairs))

;; The pairs that brace a ladder of k rungs, its rails the particles from
;; index a and from index b: each joined to the next along its rail and
;; to the one across its rung, and two braces crossing each square
;; between rungs, so it holds its shape. Closed, the last rung's square
;; reaches back to the first: two rings make a band.
(define (springies-ladder a b k closed?)
  (define (next i) (mod (+ i 1) k))
  (apply append
         (map (lambda (i)
                (cons (list (+ a i) (+ b i))   ; the rung
                      (if (or closed? (< (+ i 1) k))
                          (list (list (+ a i) (+ a (next i)))
                                (list (+ b i) (+ b (next i)))
                                (list (+ a i) (+ b (next i)))
                                (list (+ a (next i)) (+ b i)))
                          '())))
              (iota k))))

;; A velocity of up to speed along each axis, either way.
(define (springies-random-velocity speed)
  (make-pt (- (random (* 2.0 speed)) speed) (- (random (* 2.0 speed)) speed)))

;; The particles kicked: all pushed one random way, and each a little its
;; own way too, so the body flies off wobbling.
(define (springies-kick particles)
  (let ([push (springies-random-velocity 400.0)])
    (vector-map (lambda (p)
                  (make-particle (particle-position p)
                                 (pt+ (particle-velocity p)
                                      (pt+ push
                                           (springies-random-velocity 100.0)))
                                 (particle-mass p) (particle-elasticity p)))
                particles)))

;; A ball: a band between two rings of 12, the inner half the outer's
;; size. Stiff and bouncy, thrown up and to the right, spinning.
(define (springies-ball w h)
  (let* ([n 12] [r (/ (min w h) 7.0)] [c (make-pt (* w 0.3) (* h 0.5))]
         [particles
          (list->vector
           (springies-body (append (springies-ring c r n)
                                   (springies-ring c (/ r 2.0) n))
                           c (make-pt 150.0 250.0) 2.0 1.0 0.9))])
    (make-springies-model
     particles
     (springies-springs particles (springies-ladder 0 n n #t) 10000.0 12.0)
     '(gravity 980.0
       gravity? #t
       time-step 0.004
       steps 4))))

;; A tire: its tread a band between two rings of 16, and a heavy hub at
;; the center on a spoke to each particle of the inner ring. The tread is
;; softer than the spokes and grips (a bounce keeps half the speed); it is
;; thick, the inner ring 0.6 the outer's size: at 0.75 the hub's landing
;; folds it. Dropped rolling to the right: spinning as fast as it moves.
(define (springies-tire w h)
  (let* ([n 16] [r (/ (min w h) 6.0)] [c (make-pt (* w 0.2) (* h 0.6))]
         [v (make-pt 200.0 0.0)] [spin (/ -200.0 r)]
         [particles
          (list->vector
           (append (springies-body (append (springies-ring c r n)
                                           (springies-ring c (* r 0.6) n))
                                   c v spin 1.0 0.5)
                   (springies-body (list c) c v spin 8.0 0.5)))])
    (make-springies-model
     particles
     (append (springies-springs particles (springies-ladder 0 n n #t)
                                8000.0 10.0)
             (springies-springs particles
                                (map (lambda (i) (list (* 2 n) (+ n i)))
                                     (iota n))
                                20000.0 15.0))
     '(gravity 980.0
       gravity? #t
       time-step 0.003
       steps 5))))

;; A snake: a ladder of 12 rungs, each half again as long as the gap
;; between them. No gravity, and a kick to set it going, so it floats and
;; writhes; a bounce keeps all its speed.
;;
;; A body of springs can fold: a square's rails cross, and it stays
;; inside out. Whipped against a wall, a soft snake (600) folded in half
;; the runs; this one, stiffer, wider and shorter, in none left alone,
;; though a hard yank by the pointer can still fold it (R starts over).
(define (springies-snake w h)
  (let* ([k 12] [gap (/ (min w h) 20.0)] [half-rung (* gap 0.75)]
         [x0 (- (/ w 2.0) (* gap (- k 1) 0.5))] [y (/ h 2.0)]
         [rail (lambda (y)
                 (map (lambda (i) (make-pt (+ x0 (* gap i)) y)) (iota k)))]
         [particles
          (springies-kick
           (list->vector
            (springies-body (append (rail (+ y half-rung))
                                    (rail (- y half-rung)))
                            pt-zero pt-zero 0.0 1.0 1.0)))])
    (make-springies-model
     particles
     (springies-springs particles (springies-ladder 0 k k #f) 3000.0 5.0)
     '(gravity 980.0
       gravity? #f
       time-step 0.005
       steps 4))))

;; The models by name, in the order of their keys: 1, 2 and 3.
(define springies-models
  '(ball
    tire
    snake))

;; The model named name, made to fit a w × h box.
(define (springies-build name w h)
  (case name
    [(ball) (springies-ball w h)]
    [(tire) (springies-tire w h)]
    [(snake) (springies-snake w h)]
    [else (errorf 'springies-build "no model ~s" name)]))

;;; ------------------------------------------------------------------ the app

;; How often a frame steps, in ms: about 60 times a second, however often
;; the window ticks.
(define springies-step-ms 15)

;; The springs as lines, then the particles over them as dots, and the
;; pointer's tether, if it holds one. The box is h high: the world is
;; y-up, the screen y-down.
(define (draw-springies particles springs tether h)
  (define (at q) (values (pt-x q) (- h (pt-y q))))
  (define (particle-at i) (at (particle-position (vector-ref particles i))))
  (for-each (lambda (s)
              (let-values ([(x1 y1) (particle-at (spring-a s))]
                           [(x2 y2) (particle-at (spring-b s))])
                (draw-line x1 y1 x2 y2 'teal 1.5)))
            springs)
  (vector-for-each (lambda (p)
                     (let-values ([(x y) (at (particle-position p))])
                       (fill-circle x y (particle-radius p) 'yellow)))
                   particles)
  (when tether
    (let-values ([(x1 y1) (particle-at (tether-particle tether))]
                 [(x2 y2) (at (tether-point tether))])
      (draw-line x1 y1 x2 y2 'accent 1.5)
      (fill-circle x2 y2 3 'accent))))

;; The particle in particles nearest q, by its place, if one is within
;; reach of it.
(define (springies-nearest particles q reach)
  (let loop ([i 0] [best #f] [best-d reach])
    (if (= i (vector-length particles))
        best
        (let ([d (pt-norm (pt- (particle-position (vector-ref particles i))
                               q))])
          (if (<= d best-d)
              (loop (+ i 1) i d)
              (loop (+ i 1) best best-d))))))

;; How the pointer holds particle i at q: stiff enough to lift the ball a
;; hand's breadth under it (its weight stretches the tether 94 pixels),
;; and damped well past swinging. Stiffer, or less damped, a quick drag
;; sends the model flying into the walls, where the snake folds: at 2000
;; and 20 it folded in 8 drags of 9, at 500 and 100 in 2.
(define (springies-pointer-tether i q) (make-tether i q 500.0 100.0))

(define (springies-bar-height)
  (max 26 (round (+ (font-line-height 'ui-small) 13))))

;; The status line under the box.
(define (springies-status-text model particles springs gravity? frame-ms
                               running?)
  (format "~a: ~a masses, ~a springs~a   ~a   1 2 3 model · r reset · \
           k kick · g gravity · h controls · space pause"
          (string-titlecase (symbol->string model))
          (vector-length particles) (length springs)
          (if gravity? "" ", no gravity")
          (if running? (format "~,1f ms a frame" frame-ms) "paused")))

;; The box in win: its content above the status line.
(define (springies-box-size win)
  (let-values ([(w h) (window-content-size win)])
    (values w (max 1 (- h (springies-bar-height))))))

;; The point in the world at x, y in win's content: y flipped.
(define (springies-world-point win x y)
  (let-values ([(w h) (springies-box-size win)])
    (make-pt (inexact x) (inexact (- h y)))))

;; What the keys do to the model in win. Choosing a model brings its
;; settings; Reset starts the model over and keeps them. Either lets go
;; of what the pointer held.
(define (springies-choose! win name)
  (let-values ([(w h) (springies-box-size win)])
    (let ([model (springies-build name w h)])
      (window-set! win 'model name)
      (window-set! win 'particles (springies-model-particles model))
      (window-set! win 'springs (springies-model-springs model))
      (window-set! win 'settings (springies-model-settings model))
      (window-set! win 'tether #f))))

(define (springies-reset! win)
  (let-values ([(w h) (springies-box-size win)])
    (let ([model (springies-build (window-ref win 'model) w h)])
      (window-set! win 'particles (springies-model-particles model))
      (window-set! win 'springs (springies-model-springs model))
      (window-set! win 'tether #f))))

;; What the mouse does: a press within 50 pixels of a particle holds the
;; nearest on the pointer's tether, which follows the pointer until the
;; button comes up.
(define (springies-grab! win x y)
  (let* ([q (springies-world-point win x y)]
         [i (springies-nearest (window-ref win 'particles) q 50.0)])
    (when i (window-set! win 'tether (springies-pointer-tether i q)))))

(define (springies-pull! win x y)
  (let ([t (window-ref win 'tether)])
    (when t
      (window-set! win 'tether
        (springies-pointer-tether (tether-particle t)
                                  (springies-world-point win x y))))))

(define (springies-let-go! win) (window-set! win 'tether #f))

(define (springies-kick! win)
  (window-set! win 'particles (springies-kick (window-ref win 'particles))))

(define (springies-set! win key v)
  (window-set! win 'settings
    (springies-set-setting (window-ref win 'settings) key v)))

(define (springies-toggle-gravity! win)
  (springies-set! win 'gravity?
    (not (springies-setting (window-ref win 'settings) 'gravity?))))

(define (springies-toggle-running! win)
  (window-set! win 'running? (not (window-ref win 'running?))))

(define-app (springies) "Springies"
  (let ([w 760] [h 520] [last-step 0]
        [frame-ms 0.0]        ; a frame's time, smoothed
        [controls-win #f])    ; the controls window, while it is open
    (define (toggle-controls! win)
      (if controls-win
          (close-window! controls-win)
          (set! controls-win
                (springies-open-controls win
                  (lambda () (set! controls-win #f))))))
    (define (frame! win)
      (let-values ([(w h) (springies-box-size win)])
        (let ([t0 (now-ns)]
              [springs (window-ref win 'springs)]
              [tether (window-ref win 'tether)])
          (window-set! win 'particles
            (springies-frame (window-ref win 'particles)
                             (if tether (cons tether springs) springs)
                             (window-ref win 'settings) w h))
          (set! frame-ms (+ (* frame-ms 0.95)
                            (* (/ (- (now-ns) t0) 1e6) 0.05))))))
    (let ([win
           (open-window "Springies"
             'size (cons w (+ h (springies-bar-height)))
             'mouse-doc '((L . "Pull a mass"))
             'running? #t
             'tether #f
             'tick (lambda (win)
                     (when (and (window-ref win 'running?)
                                (>= (- (now-ms) last-step) springies-step-ms))
                       (set! last-step (now-ms))
                       (frame! win)))
             'draw (lambda (win w h)
                     (let ([bar (springies-bar-height)]
                           [particles (window-ref win 'particles)]
                           [springs (window-ref win 'springs)])
                       (fill-rect 0 0 w (- h bar) 'bg-0)
                       (draw-springies particles springs
                                       (window-ref win 'tether) (- h bar))
                       (fill-rect 0 (- h bar) w bar 'bg-1)
                       (draw-text 10 (+ (- h bar) 5)
                                  (springies-status-text
                                   (window-ref win 'model) particles springs
                                   (springies-setting
                                    (window-ref win 'settings) 'gravity?)
                                   frame-ms (window-ref win 'running?))
                                  'text-faint 'ui-small)))
             'key (lambda (win key mods)
                    (case key
                      [(#\1 #\2 #\3)
                       (springies-choose! win
                         (list-ref springies-models
                                   (- (char->integer key)
                                      (char->integer #\1))))]
                      [(#\r) (springies-reset! win)]
                      [(#\k) (springies-kick! win)]
                      [(#\g) (springies-toggle-gravity! win)]
                      [(#\space) (springies-toggle-running! win)]
                      [(#\h) (toggle-controls! win)])
                    (invalidate! win))
             'mouse-down (lambda (win x y button clicks)
                           (when (eq? button 'left) (springies-grab! win x y)))
             'mouse-move (lambda (win x y) (springies-pull! win x y))
             'mouse-up (lambda (win x y button)
                         (when (eq? button 'left) (springies-let-go! win)))
             'close (lambda (win)
                      (when controls-win (close-window! controls-win))))])
      (springies-choose! win 'ball)
      ;; the controls show at first. Moved to fit on the desktop, they'd
      ;; cover the box: it moves left to clear them.
      (toggle-controls! win)
      (let-values ([(dx dy dw dh) (desktop-rect)])
        (let ([short (- (+ (window-x win) (window-w win) 12)
                        (window-x controls-win))])
          (when (> short 0)
            (move-window! win (max dx (- (window-x win) short))
                          (window-y win)))))
      (focus-window! win)   ; the box has the keyboard
      win)))

;;; ------------------------------------------------------------------
;;; the controls window
;;; Beside the box, as Boids' rules are beside the flock: a model to
;;; choose, the keys' buttons and switches, and sliders for the time. It
;;; reads and sets the box window's properties, so it shows them as they
;;; are, whoever changed them: a key, a button or the REPL.

;; The sliders' settings, their ranges and the labels of their rows. The
;; time step stops at 10 ms: at 15 the ball and the tire blow up.
(define springies-ranges
  '((time-step 0.0005 0.01 "time step")
    (steps 1 16 "steps a frame")))

(define (springies-readout key v)
  (case key
    [(time-step) (format "~,1f ms" (* v 1000.0))]
    [else (format "~a" v)]))

;; A slider's value v as its setting key holds it: steps are whole.
(define (springies-slider-value key v)
  (if (eq? key 'steps) (exact (round v)) v))

(define springies-model-labels
  '("Ball (1)"
    "Tire (2)"
    "Snake (3)"))

(define springies-buttons
  '("Start over (R)"
    "Kick (K)"))

(define springies-switches
  '("Gravity (G)"
    "Pause (Space)"))

(define (springies-label-width)
  (+ 12 (text-widest (map cadddr springies-ranges) 'ui)))

(define (springies-readout-width) (+ 12 (text-width "00.0 ms" 'ui)))

;; The controls window's content size: room for its rows, as
;; springies-draw-controls lays them out, with sliders 140 wide, and its
;; buttons and switches as wide as the widest of their row, in the
;; style's own sizes.
(define (springies-controls-size)
  (let ([pad (ui-pad)] [gap (ui-gap)] [sh (ui-slider-height)]
        [ch (ui-control-height)])
    (define (button-w label) (let-values ([(w h) (ui-button-size label #f)]) w))
    (define (switch-w label) (let-values ([(w h) (ui-checkbox-size label)]) w))
    (define (in-a-row widths)
      (+ (* (length widths) (apply max widths))
         (* (- (length widths) 1) gap)))
    (values (+ pad pad
               (max (+ (springies-label-width) 140 (springies-readout-width))
                    (in-a-row (map button-w springies-model-labels))
                    (in-a-row (map button-w springies-buttons))
                    (in-a-row (map switch-w springies-switches))))
            (+ pad (* 3 (+ ch gap)) (* 2 gap)
               (* (length springies-ranges) (+ sh gap))
               gap (font-line-height 'ui-small) pad))))

;; The rows, top to bottom: the models, the buttons, the switches, a
;; slider for each range, and a hint. Returns the y below them.
(define (springies-draw-controls ui box-win w)
  (let* ([pad (ui-pad)] [gap (ui-gap)] [sh (ui-slider-height)]
         [ch (ui-control-height)]
         [lw (springies-label-width)] [rw (springies-readout-width)]
         [settings (window-ref box-win 'settings)])
    ;; widgets side by side across the row at y, as wide as each other:
    ;; (draw x y w) each
    (define (in-a-row y draws)
      (let* ([n (length draws)]
             [cw (/ (- w pad pad (* gap (- n 1))) n)])
        (for-each (lambda (draw i) (draw (+ pad (* i (+ cw gap))) y cw))
                  draws (iota n))))
    (define (row y range)
      (let* ([key (car range)] [v (springies-setting settings key)])
        (ui-draw-label pad y lw sh '(dim) (cadddr range))
        (ui-slider ui key (+ pad lw) y (- w pad lw rw pad) v
                   (cadr range) (caddr range)
                   (lambda (v)
                     (springies-set! box-win key
                                     (springies-slider-value key v))))
        (ui-draw-label (- w pad rw) y rw sh '(right) (springies-readout key v))
        (+ y sh gap)))
    (in-a-row pad
      (map (lambda (name label)
             (lambda (x y cw)
               (ui-button ui name x y cw ch label
                          (lambda () (springies-choose! box-win name))
                          'selected (eq? name (window-ref box-win 'model)))))
           springies-models springies-model-labels))
    (in-a-row (+ pad ch gap gap)
      (map (lambda (id label act!)
             (lambda (x y cw)
               (ui-button ui id x y cw ch label (lambda () (act! box-win)))))
           '(reset kick) springies-buttons
           (list springies-reset! springies-kick!)))
    (in-a-row (+ pad (* 2 (+ ch gap)) gap)
      (list (lambda (x y cw)
              (ui-checkbox ui 'gravity x y cw ch (car springies-switches)
                           (springies-setting settings 'gravity?)
                           (lambda (on?)
                             (springies-set! box-win 'gravity? on?))))
            (lambda (x y cw)
              (ui-checkbox ui 'pause x y cw ch (cadr springies-switches)
                           (not (window-ref box-win 'running?))
                           (lambda (on?)
                             (window-set! box-win 'running? (not on?)))))))
    (let ([y (fold-left row (+ pad (* 3 (+ ch gap)) (* 2 gap))
                        springies-ranges)])
      (ui-draw-label pad (+ y gap) (- w pad pad) (font-line-height 'ui-small)
                     '(hint) "h hides this window · drag a mass to pull it")
      (+ y gap (font-line-height 'ui-small) pad))))

;; Opens the controls window for the model in box-win, beside it, and
;; returns it; on-close is called when it closes. Its keys are the box's.
(define (springies-open-controls box-win on-close)
  (let ([ui (make-ui)]
        [shown #f])   ; what it last drew
    (define (now-shown)
      (list (window-ref box-win 'model) (window-ref box-win 'settings)
            (window-ref box-win 'running?)))
    (let-values ([(w h) (springies-controls-size)])
      (let ([win
             (apply open-window "Springies — Controls"
                    'size (cons w h)
                    'pos (cons (+ (window-x box-win) (window-w box-win) 12)
                               (window-y box-win))
                    'app #f
                    'draw (lambda (win w h)
                            (set! shown (now-shown))
                            (ui-begin! ui)
                            (ui-draw-surface 0 0 w h '(page))
                            (springies-draw-controls ui box-win w)
                            (ui-end! ui w h))
                    'close (lambda (win) (on-close))
                    (append
                     (ui-handlers ui 'key (lambda (win key mods)
                                            (window-call box-win 'key key
                                                         mods)
                                            #t))
                     ;; the kit's tick, then: a change from elsewhere shows,
                     ;; and fonts grown in Settings get room for the rows
                     (list 'tick (lambda (win)
                                   (ui-tick ui win)
                                   (let-values ([(w h)
                                                 (springies-controls-size)])
                                     (springies-grow-to! win w h))
                                   (unless (equal? shown (now-shown))
                                     (invalidate! win))))))])
        (springies-keep-on-desktop! win)
        win))))

;; Grows win's content to at least w × h, moved left or up as far as it
;; takes to stay on the desktop. It never shrinks: a size set by hand
;; holds. Boids' rules window grows the same way (boids-grow-to!).
(define (springies-grow-to! win w h)
  (let-values ([(cw ch) (window-content-size win)])
    (when (and (or (> w cw) (> h ch)) (not (shaded? win)))
      (resize-window! win (max w cw) (max h ch))
      (springies-keep-on-desktop! win))))

;; Moves win left or up as far as it takes to stay on the desktop.
(define (springies-keep-on-desktop! win)
  (let-values ([(dx dy dw dh) (desktop-rect)])
    (move-window! win
      (max dx (min (window-x win) (- (+ dx dw) (window-w win))))
      (max dy (min (window-y win) (- (+ dy dh) (window-h win)))))))
