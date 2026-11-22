;;; tests/units/springies.ss — Springies: in its sandbox, the springs' laws
;;; as XSpringies has them, Runge-Kutta against motion known exactly, the
;;; walls, the models, and the window, its pointer and its controls.

;; Springies runs in its sandbox ((schevana services grant)): its names,
;; forwarded here.
(define springies-box (grant-env 'springies))

(check "Springies runs in its sandbox, holding its bundles, allowed by the \
        table, and its names stay there: pt is none of the world's; its \
        controls window is no app's, the box's own"
       (let* ([held (environment-symbols (env-environment springies-box))]
              [world (environment-symbols *world-env*)]
              [win (springies)]
              [cw (find-window "Springies — Controls")]
              [ok (and (equal? (env-path springies-box) "/apps/springies")
                       (equal? (grant-requested 'springies)
                               '(window draw ui timers))
                       (null? (grant-undecided 'springies))
                       (memq 'ui-checkbox held) (not (memq 'notify held))
                       (memq 'pt held) (memq 'springies-step held)
                       (not (memq 'pt world)) (not (memq 'pt+ world))
                       (not (memq 'springies-step world))
                       (eq? (window-app win) 'springies)
                       (not (window-app cw))
                       (eq? (window-owner cw) win))])
         (close-window! win)
         ok))

;; For the checks below, here and not in the world they test: this suite's
;; own view of the sandbox.
(for-each (lambda (n)
            (define-top-level-syntax n
              (forwarder-to (datum->syntax (env-anchor springies-box) n))))
          '(make-pt pt-x pt-y pt-zero pt+ pt- pt* pt-norm make-particle
            particle? particle-position particle-velocity particle-mass
            particle-radius particle-bounce make-spring spring-a spring-b
            spring-rest-length spring-force make-tether tether-particle
            tether-point tether-force springies-forces springies-rate
            springies-rk4 springies-step springies-setting
            springies-set-setting springies-frame springies-model-particles
            springies-model-springs springies-model-settings springies-kick
            springies-ball springies-models springies-build springies-nearest
            springies-box-size springies-draw-controls))

(define (test-particle x y vx vy m e)
  (make-particle (make-pt x y) (make-pt vx vy) m e))

(define (test-close? a b tolerance) (<= (abs (- a b)) tolerance))

(define (test-pt-close? p x y tolerance)
  (and (test-close? (pt-x p) x tolerance) (test-close? (pt-y p) y tolerance)))

;; Two particles 10 apart on x, the first moving at (vx, vy), and a spring
;; between them of stiffness 100, damping 2 and the rest length given:
;; the force it pulls the first with.
(define (test-spring-pull rest vx vy)
  (spring-force (make-spring 0 1 100.0 2.0 rest)
                (vector (test-particle 0.0 0.0 vx vy 1.0 1.0)
                        (test-particle 10.0 0.0 0.0 0.0 1.0 1.0))))

(check "Springies: a spring at rest pulls nothing; stretched it pulls its \
        ends together, squeezed it pushes them apart"
       (and (test-pt-close? (test-spring-pull 10.0 0.0 0.0) 0.0 0.0 1e-12)
            (test-pt-close? (test-spring-pull 8.0 0.0 0.0) 200.0 0.0 1e-12)
            (test-pt-close? (test-spring-pull 12.0 0.0 0.0) -200.0 0.0 1e-12)))

(check "Springies: damping resists ends moving apart, not moving sideways"
       (and (test-pt-close? (test-spring-pull 10.0 -3.0 0.0) 6.0 0.0 1e-12)
            (test-pt-close? (test-spring-pull 10.0 0.0 5.0) 0.0 0.0 1e-12)))

(check "Springies: a spring of no length pulls nothing"
       (let ([ps (vector (test-particle 5.0 5.0 1.0 0.0 1.0 1.0)
                         (test-particle 5.0 5.0 0.0 0.0 1.0 1.0))])
         (and (eq? (spring-force (make-spring 0 1 100.0 2.0 10.0) ps) pt-zero)
              (eq? (spring-force (make-spring 0 1 100.0 2.0 0.0) ps)
                   pt-zero))))

(check "Springies: gravity pulls light and heavy alike"
       (let ([rate (springies-rate
                    (vector (test-particle 0.0 0.0 0.0 0.0 1.0 1.0)
                            (test-particle 9.0 0.0 0.0 0.0 10.0 1.0))
                    '() (make-pt 0.0 -980.0))])
         (for-all (lambda (p) (test-pt-close? (particle-velocity p)
                                              0.0 -980.0 0.0))
                  (vector->list rate))))

;; Six particles of random masses and springs between them all, moving at
;; random: m a summed over them is the springs' forces, which cancel.
(check "Springies: springs pull equal and opposite: momentum holds"
       (let* ([ps (list->vector
                   (map (lambda (i)
                          (test-particle (random 100.0) (random 100.0)
                                         (- (random 20.0) 10.0)
                                         (- (random 20.0) 10.0)
                                         (+ 0.5 (random 5.0)) 1.0))
                        (iota 6)))]
              [ss (apply append
                         (map (lambda (a)
                                (map (lambda (b)
                                       (make-spring a b (random 500.0)
                                                    (random 5.0)
                                                    (random 50.0)))
                                     (iota a)))
                              (iota 6)))]
              [rate (springies-rate ps ss pt-zero)]
              [sum (fold-left pt+ pt-zero
                              (map (lambda (p r)
                                     (pt* (particle-velocity r)
                                          (particle-mass p)))
                                   (vector->list ps) (vector->list rate)))])
         (test-pt-close? sum 0.0 0.0 1e-9)))

;; With gravity alone the acceleration is constant, which Runge-Kutta
;; follows exactly: x0 + v0 t + g t²/2.
(check "Springies: a fall under gravity is the parabola, to rounding"
       (let loop ([ps (vector (test-particle 100.0 100.0 3.0 40.0 1.0 1.0))]
                  [i 0])
         (if (< i 10)
             (loop (springies-rk4 (lambda (s)
                                    (springies-rate s '()
                                                    (make-pt 0.0 -980.0)))
                                  ps 0.05)
                   (+ i 1))
             (let ([p (vector-ref ps 0)])   ; half a second on
               (and (test-pt-close? (particle-position p)
                                    101.5 (+ 100.0 20.0 -122.5) 1e-9)
                    (test-pt-close? (particle-velocity p)
                                    3.0 (- 40.0 490.0) 1e-9))))))

;; Two particles of mass 1 on a spring of stiffness 100, stretched by 1
;; and let go: they swing at ω = √(k/μ), μ = 1/2 the reduced mass. Half a
;; period on, the spring is squeezed by 1.
(check "Springies: two particles on a spring swing at its period"
       (let* ([ss (list (make-spring 0 1 100.0 0.0 10.0))]
              [half-period (/ pi (sqrt 200.0))]
              [n 1000])
         (let loop ([ps (vector (test-particle 500.0 500.0 0.0 0.0 1.0 1.0)
                                (test-particle 511.0 500.0 0.0 0.0 1.0 1.0))]
                    [i 0])
           (if (< i n)
               (loop (springies-step ps ss pt-zero (/ half-period n) 1e6 1e6)
                     (+ i 1))
               (let ([a (particle-position (vector-ref ps 0))]
                     [b (particle-position (vector-ref ps 1))])
                 (test-close? (pt-norm (pt- b a)) 9.0 1e-6))))))

;; Radius 3, elasticity 1/2, in a 100 × 100 box.
(check "Springies: a particle past a wall is put back on it, and turns \
        back if it was moving out, keeping its elasticity of its speed"
       (let ([down (particle-bounce (test-particle 10.0 -2.0 4.0 -10.0 1.0 0.5)
                                    100.0 100.0)]
             [in (particle-bounce (test-particle 99.0 50.0 -6.0 2.0 1.0 0.5)
                                  100.0 100.0)]
             [free (test-particle 50.0 50.0 -6.0 2.0 1.0 0.5)])
         (and (test-pt-close? (particle-position down) 10.0 3.0 0.0)
              (test-pt-close? (particle-velocity down) 2.0 5.0 0.0)
              (test-pt-close? (particle-position in) 97.0 50.0 0.0)
              (test-pt-close? (particle-velocity in) -3.0 1.0 0.0)
              (eq? (particle-bounce free 100.0 100.0) free))))

(define (test-models) (map (lambda (name) (springies-build name 760.0 520.0))
                           springies-models))

;; Each pair once: two springs between the same particles would be one
;; spring twice as stiff.
(check "Springies: each model's springs join particles it has, each pair \
        once, each at rest"
       (for-all
        (lambda (m)
          (let ([ps (springies-model-particles m)]
                [ss (springies-model-springs m)])
            (define (ends s) (list (min (spring-a s) (spring-b s))
                                   (max (spring-a s) (spring-b s))))
            (and (for-all
                  (lambda (s)
                    (and (< -1 (spring-a s) (vector-length ps))
                         (< -1 (spring-b s) (vector-length ps))
                         (not (= (spring-a s) (spring-b s)))
                         (= (spring-rest-length s)
                            (pt-norm (pt- (particle-position
                                           (vector-ref ps (spring-a s)))
                                          (particle-position
                                           (vector-ref ps (spring-b s))))))))
                  ss)
                 (= (length ss)
                    (length (fold-left (lambda (seen s)
                                         (if (member (ends s) seen)
                                             seen
                                             (cons (ends s) seen)))
                                       '() ss))))))
        (test-models)))

;; 5 seconds at 60 frames a second; the snake kicked again halfway. Whole:
;; no spring stretched or squeezed by half.
(check "Springies: each model moves about and stays in its box, whole"
       (for-all
        (lambda (m)
          (let ([ss (springies-model-springs m)])
            (let loop ([ps (springies-model-particles m)] [i 0])
              (if (< i 300)
                  (loop (springies-frame (if (= i 150) (springies-kick ps) ps)
                                         ss (springies-model-settings m)
                                         760.0 520.0)
                        (+ i 1))
                  (and (not (for-all eq? (vector->list ps)
                                     (vector->list
                                      (springies-model-particles m))))
                       (for-all (lambda (p)
                                  (let ([q (particle-position p)]
                                        [r (particle-radius p)])
                                    (and (<= r (pt-x q) (- 760.0 r))
                                         (<= r (pt-y q) (- 520.0 r)))))
                                (vector->list ps))
                       (for-all
                        (lambda (s)
                          (< 0.5
                             (/ (pt-norm
                                 (pt- (particle-position
                                       (vector-ref ps (spring-a s)))
                                      (particle-position
                                       (vector-ref ps (spring-b s)))))
                                (spring-rest-length s))
                             1.5))
                        ss))))))
        (test-models)))

(check "Springies: only the snake starts without gravity"
       (equal? (map (lambda (m)
                      (springies-setting (springies-model-settings m)
                                         'gravity?))
                    (test-models))
               '(#t #t #f)))

(check "Springies: a kick moves every particle, from where it was"
       (let* ([ps (springies-model-particles (springies-ball 760.0 520.0))]
              [kicked (springies-kick ps)])
         (for-all (lambda (p q)
                    (and (eq? (particle-position p) (particle-position q))
                         (not (equal? (pt-x (particle-velocity p))
                                      (pt-x (particle-velocity q))))))
                  (vector->list ps) (vector->list kicked))))

(check "Springies: setting a setting keeps the others, and their order"
       (let* ([settings '(gravity 980.0 gravity? #t time-step 0.004 steps 4)]
              [set (springies-set-setting settings 'time-step 0.002)])
         (and (= (springies-setting set 'time-step) 0.002)
              (equal? (plist-keys set) (plist-keys settings))
              (= (springies-setting set 'steps) 4)
              (raises? (lambda () (springies-set-setting settings 'drag 1.0)))
              (raises? (lambda () (springies-setting settings 'drag))))))

;; A frame of win's, a thousand seconds after the last one made here. The
;; window steps by its frames' times, which go by the machine's clock: a
;; check that needs a step makes the frame itself, so it steps however
;; fast the checks run, and the world's own frames come too soon after it
;; to step.
(define test-frame-ns (now-ns))
(define (test-frame! win)
  (set! test-frame-ns (+ test-frame-ns (* 1000 1000000000)))
  (window-call win 'frame test-frame-ns))

;; The keys, through the window's own handler.
(let ([win (springies)])
  (define (key! k) (window-call win 'key k '()))
  (define (particles) (window-ref win 'particles))
  (define (setting key) (springies-setting (window-ref win 'settings) key))
  (check "Springies: it opens on the ball, running"
         (and (eq? (window-ref win 'model) 'ball)
              (window-ref win 'running?)))
  (check "Springies: 1, 2 and 3 choose the ball, the tire and the snake, \
          each with its settings"
         (begin
           (key! #\3)
           (and (eq? (window-ref win 'model) 'snake)
                (not (setting 'gravity?))
                (begin (key! #\2) (eq? (window-ref win 'model) 'tire))
                (= (setting 'time-step) 0.003)
                (begin (key! #\1) (eq? (window-ref win 'model) 'ball)))))
  (check "Springies: G turns gravity off and on; R starts over, keeping it"
         (begin
           (key! #\g)
           (test-frame! win)
           (let ([moved (particles)])
             (key! #\r)
             (and (not (setting 'gravity?))
                  (not (eq? (particles) moved))
                  (eq? (window-ref win 'model) 'ball)
                  (begin (key! #\g) (setting 'gravity?))))))
  (check "Springies: K kicks"
         (let ([before (particles)])
           (key! #\k)
           (not (eq? (particles) before))))
  (check "Springies: Space holds the particles still, and again sets them \
          going"
         (let ([before (begin (key! #\space) (particles))])
           (test-frame! win)
           (let ([held? (eq? (particles) before)])
             (key! #\space)
             (test-frame! win)
             (and held? (window-ref win 'running?)
                  (not (eq? (particles) before))))))
  (close-window! win))

(check "Springies: a tether pulls its particle to its point, damped against \
        the particle's speed; among springs, it pulls that one alone"
       (let* ([ps (vector (test-particle 10.0 20.0 0.0 0.0 1.0 1.0)
                          (test-particle 50.0 50.0 2.0 -1.0 1.0 1.0))]
              [t (make-tether 1 (make-pt 60.0 40.0) 100.0 5.0)]
              [forces (springies-forces ps (list t))])
         (and (test-pt-close? (tether-force t ps) 990.0 -995.0 0.0)
              (eq? (vector-ref forces 0) pt-zero)
              (test-pt-close? (vector-ref forces 1) 990.0 -995.0 0.0))))

(check "Springies: the particle nearest a point, within reach"
       (let ([ps (vector (test-particle 0.0 0.0 0.0 0.0 1.0 1.0)
                         (test-particle 30.0 0.0 0.0 0.0 1.0 1.0)
                         (test-particle 60.0 0.0 0.0 0.0 1.0 1.0))])
         (and (= (springies-nearest ps (make-pt 40.0 5.0) 50.0) 1)
              (= (springies-nearest ps (make-pt 100.0 0.0) 50.0) 2)
              (not (springies-nearest ps (make-pt 200.0 0.0) 50.0)))))

;; The mouse, through the window's handlers, at a particle's place on the
;; screen: y flipped.
(let ([win (springies)])
  (define (particle i) (vector-ref (window-ref win 'particles) i))
  (define (screen-of i)
    (let-values ([(w h) (springies-box-size win)])
      (let ([q (particle-position (particle i))])
        (values (pt-x q) (- h (pt-y q))))))
  (check "Springies: a press near a particle holds it on the pointer's \
          tether, one far from all holds none"
         (let-values ([(x y) (screen-of 5)])
           (window-call win 'mouse-down (+ x 4) (- y 3) 'left 1)
           (let ([t (window-ref win 'tether)])
             (window-call win 'mouse-up (+ x 4) (- y 3) 'left)
             (and t (= (tether-particle t) 5)
                  (test-pt-close? (tether-point t)
                                  (+ (pt-x (particle-position (particle 5))) 4)
                                  (+ (pt-y (particle-position (particle 5))) 3)
                                  1e-9)
                  (not (window-ref win 'tether))
                  (begin (window-call win 'mouse-down 1 1 'left 1)
                         (not (window-ref win 'tether)))))))
  ;; held 100 pixels up, against two frames let be
  (check "Springies: the held particle follows the pointer, until let go"
         (let*-values ([(x y) (screen-of 5)] [(w h) (springies-box-size win)])
           (window-call win 'mouse-down x y 'left 1)
           (window-call win 'mouse-move x (- y 100))
           (let* ([frame (lambda (ps)
                           (springies-frame ps (window-ref win 'springs)
                                            (window-ref win 'settings) w h))]
                  [let-be (vector-ref (frame (frame (window-ref win
                                                                'particles)))
                                      5)])
             (test-frame! win)
             (test-frame! win)
             (let ([pulled (> (pt-y (particle-position (particle 5)))
                              (+ (pt-y (particle-position let-be)) 1.0))])
               (window-call win 'mouse-up x (- y 100) 'left)
               (and pulled (not (window-ref win 'tether)))))))
  (check "Springies: choosing a model, or starting over, lets go"
         (let-values ([(x y) (screen-of 5)])
           (window-call win 'mouse-down x y 'left 1)
           (window-call win 'key #\2 '())
           (and (not (window-ref win 'tether))
                (let-values ([(x y) (screen-of 5)])
                  (window-call win 'mouse-down x y 'left 1)
                  (window-call win 'key #\r '())
                  (not (window-ref win 'tether))))))
  (close-window! win))

;; The controls window, opened with the box, where both fit.
(let* ([win (parameterize ([new-window-position '(40 . 60)]) (springies))]
       [controls (lambda () (find-window "Springies — Controls"))]
       [setting (lambda (key)
                  (springies-setting (window-ref win 'settings) key))]
       [press! (lambda (cw id)   ; the middle of the widget id
                 (let ([r (ui-find (window-ref cw 'ui) id)])
                   (let ([x (+ (ui-region-x r) (/ (ui-region-w r) 2))]
                         [y (+ (ui-region-y r) (/ (ui-region-h r) 2))])
                     (window-call cw 'mouse-down x y 'left 1)
                     (window-call cw 'mouse-up x y 'left))))])
  (render-frame!)
  (check "Springies: the controls open beside the box, which has the keys"
         (let ([cw (controls)])
           (and cw (eq? (focused-window) win)
                (= (window-x cw) (+ (window-x win) (window-w win) 12))
                (= (window-y cw) (window-y win)))))
  (check "Springies: the controls window has room for all its rows"
         (let-values ([(w h) (window-content-size (controls))])
           (let* ([bottom #f]
                  [s (image (exact (ceiling w)) (exact (ceiling h)) 1
                            (lambda ()
                              (let ([ui (make-ui)])
                                (ui-begin! ui)
                                (set! bottom
                                      (springies-draw-controls ui win w)))))])
             (picture-free! s)
             (<= bottom h))))
  (check "Springies: the controls window paints the style's page under its \
          rows"
         (let*-values ([(cw) (controls)] [(w h) (window-content-size cw)])
           (let* ([surfaces '()]
                  [real ui-draw-surface]
                  [s (fluid-let ([ui-draw-surface
                                  (lambda (x y w h flags)
                                    (set! surfaces (cons flags surfaces))
                                    (real x y w h flags))])
                       (image (exact (ceiling w)) (exact (ceiling h)) 1
                              (lambda ()
                                (parameterize ([current-window cw])
                                  ((hashtable-ref (window-handlers cw) 'draw #f)
                                   cw w h)))))])
             (picture-free! s)
             (and (member '(page) surfaces) #t))))
  (check "Springies: its model buttons choose the model"
         (begin
           (press! (controls) 'snake)
           (and (eq? (window-ref win 'model) 'snake)
                (not (setting 'gravity?))
                (begin (press! (controls) 'ball)
                       (eq? (window-ref win 'model) 'ball)))))
  (check "Springies: its buttons and keys act on the box"
         (let ([before (window-ref win 'particles)])
           (press! (controls) 'kick)
           (let ([kicked (window-ref win 'particles)])
             (press! (controls) 'reset)
             (window-call (controls) 'key #\g '())
             (and (not (eq? kicked before))
                  (not (eq? (window-ref win 'particles) kicked))
                  (not (setting 'gravity?))))))
  (check "Springies: its switches turn gravity and the pause on and off"
         (begin
           (press! (controls) 'gravity)
           (press! (controls) 'pause)
           (and (setting 'gravity?)
                (not (window-ref win 'running?))
                (begin (press! (controls) 'pause)
                       (window-ref win 'running?)))))
  (check "Springies: its sliders set the time step, and whole steps a frame"
         (begin
           (press! (controls) 'time-step)
           (press! (controls) 'steps)
           (and (< (abs (- (setting 'time-step) 0.00525)) 1e-9)
                (eqv? (setting 'steps) 8))))
  (check "Springies: H closes the controls and opens them again"
         (begin
           (window-call win 'key #\h '())
           (and (not (controls))
                (begin (window-call win 'key #\h '())
                       (controls) #t))))
  (check "Springies: the controls grow when their rows need more, on screen"
         (let-values ([(w h) (window-content-size (controls))]
                      [(dx dy dw dh) (desktop-rect)])
           (define (grown-by! dw)
             (let* ([env (env-environment springies-box)]
                    [real (top-level-value 'springies-controls-size env)])
               (set-top-level-value! 'springies-controls-size
                                     (lambda () (values (+ w dw) h)) env)
               (steps 1)
               (set-top-level-value! 'springies-controls-size real env))
             (let-values ([(w2 h2) (window-content-size (controls))])
               (and (= w2 (+ w dw)) (= h2 h))))
           (and (grown-by! 40)
                (grown-by! 900)
                (= (+ (window-x (controls)) (window-w (controls)))
                   (+ dx dw)))))
  (check "Springies: closing the box closes its controls"
         (begin (close-window! win) (not (controls)))))

;; Opened far to the right, the controls are moved to fit, and the box
;; moves left to clear them.
(let ([win (parameterize ([new-window-position '(400 . 60)]) (springies))])
  (check "Springies: opened where the controls can't fit beside, the box \
          moves"
         (let ([cw (find-window "Springies — Controls")])
           (and (< (window-x win) 400)
                (= (+ (window-x win) (window-w win) 12) (window-x cw)))))
  (close-window! win))

(check "Springies: a frame leaves the particles it steps as they were"
       (let* ([m (springies-ball 760.0 520.0)]
              [ps (springies-model-particles m)]
              [before (vector->list ps)])
         (springies-frame ps (springies-model-springs m)
                          (springies-model-settings m) 760.0 520.0)
         (for-all eq? (vector->list ps) before)))

;; The record types are nongenerative, as Boids' are.
(check "Springies: particles made before the file loads again still work"
       (let ([m (springies-ball 760.0 520.0)])
         (load-source "apps/springies.ss")
         (and (particle? (vector-ref (springies-model-particles m) 0))
              (vector? (springies-frame (springies-model-particles m)
                                        (springies-model-springs m)
                                        (springies-model-settings m)
                                        760.0 520.0)))))
