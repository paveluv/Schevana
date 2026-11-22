;;; tests/units/springies.ss — Springies: the springs' laws as XSpringies
;;; has them, Runge-Kutta against motion known exactly, the walls, the
;;; models, and the window, its pointer and its controls.

;; Springies' own names, sp:pt+, sp:springies-step and the rest
;; (tests/reach.ss).
(test-library '(schevana-demo springies) 'sp:)

(check "Springies' controls window is no app's, the box's own"
       (let* ([win (sp:springies)]
              [cw (find-window "Springies — Controls")]
              [ok (and (eq? (window-app win) 'springies)
                       (not (window-app cw))
                       (eq? (window-owner cw) win))])
         (close-window! win)
         ok))

(define (test-particle x y vx vy m e)
  (sp:make-particle (sp:make-pt x y) (sp:make-pt vx vy) m e))

(define (test-close? a b tolerance) (<= (abs (- a b)) tolerance))

(define (test-pt-close? p x y tolerance)
  (and (test-close? (sp:pt-x p) x tolerance)
       (test-close? (sp:pt-y p) y tolerance)))

;; Two particles 10 apart on x, the first moving at (vx, vy), and a spring
;; between them of stiffness 100, damping 2 and the rest length given:
;; the force it pulls the first with.
(define (test-spring-pull rest vx vy)
  (sp:spring-force (sp:make-spring 0 1 100.0 2.0 rest)
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
         (and (eq? (sp:spring-force (sp:make-spring 0 1 100.0 2.0 10.0) ps)
                   sp:pt-zero)
              (eq? (sp:spring-force (sp:make-spring 0 1 100.0 2.0 0.0) ps)
                   sp:pt-zero))))

(check "Springies: gravity pulls light and heavy alike"
       (let ([rate (sp:springies-rate
                    (vector (test-particle 0.0 0.0 0.0 0.0 1.0 1.0)
                            (test-particle 9.0 0.0 0.0 0.0 10.0 1.0))
                    '() (sp:make-pt 0.0 -980.0))])
         (for-all (lambda (p) (test-pt-close? (sp:particle-velocity p)
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
                                       (sp:make-spring a b (random 500.0)
                                                       (random 5.0)
                                                       (random 50.0)))
                                     (iota a)))
                              (iota 6)))]
              [rate (sp:springies-rate ps ss sp:pt-zero)]
              [sum (fold-left sp:pt+ sp:pt-zero
                              (map (lambda (p r)
                                     (sp:pt* (sp:particle-velocity r)
                                             (sp:particle-mass p)))
                                   (vector->list ps) (vector->list rate)))])
         (test-pt-close? sum 0.0 0.0 1e-9)))

;; With gravity alone the acceleration is constant, which Runge-Kutta
;; follows exactly: x0 + v0 t + g t²/2.
(check "Springies: a fall under gravity is the parabola, to rounding"
       (let loop ([ps (vector (test-particle 100.0 100.0 3.0 40.0 1.0 1.0))]
                  [i 0])
         (if (< i 10)
             (loop (sp:springies-rk4 (lambda (s)
                                       (sp:springies-rate
                                        s '() (sp:make-pt 0.0 -980.0)))
                                     ps 0.05)
                   (+ i 1))
             (let ([p (vector-ref ps 0)])   ; half a second on
               (and (test-pt-close? (sp:particle-position p)
                                    101.5 (+ 100.0 20.0 -122.5) 1e-9)
                    (test-pt-close? (sp:particle-velocity p)
                                    3.0 (- 40.0 490.0) 1e-9))))))

;; Two particles of mass 1 on a spring of stiffness 100, stretched by 1
;; and let go: they swing at ω = √(k/μ), μ = 1/2 the reduced mass. Half a
;; period on, the spring is squeezed by 1.
(check "Springies: two particles on a spring swing at its period"
       (let* ([ss (list (sp:make-spring 0 1 100.0 0.0 10.0))]
              [half-period (/ pi (sqrt 200.0))]
              [n 1000])
         (let loop ([ps (vector (test-particle 500.0 500.0 0.0 0.0 1.0 1.0)
                                (test-particle 511.0 500.0 0.0 0.0 1.0 1.0))]
                    [i 0])
           (if (< i n)
               (loop (sp:springies-step ps ss sp:pt-zero
                                        (/ half-period n) 1e6 1e6)
                     (+ i 1))
               (let ([a (sp:particle-position (vector-ref ps 0))]
                     [b (sp:particle-position (vector-ref ps 1))])
                 (test-close? (sp:pt-norm (sp:pt- b a)) 9.0 1e-6))))))

;; Radius 3, elasticity 1/2, in a 100 × 100 box.
(check "Springies: a particle past a wall is put back on it, and turns \
        back if it was moving out, keeping its elasticity of its speed"
       (let ([down (sp:particle-bounce
                    (test-particle 10.0 -2.0 4.0 -10.0 1.0 0.5) 100.0 100.0)]
             [in (sp:particle-bounce
                  (test-particle 99.0 50.0 -6.0 2.0 1.0 0.5) 100.0 100.0)]
             [free (test-particle 50.0 50.0 -6.0 2.0 1.0 0.5)])
         (and (test-pt-close? (sp:particle-position down) 10.0 3.0 0.0)
              (test-pt-close? (sp:particle-velocity down) 2.0 5.0 0.0)
              (test-pt-close? (sp:particle-position in) 97.0 50.0 0.0)
              (test-pt-close? (sp:particle-velocity in) -3.0 1.0 0.0)
              (eq? (sp:particle-bounce free 100.0 100.0) free))))

(define (test-models) (map (lambda (name) (sp:springies-build name 760.0 520.0))
                           sp:springies-models))

;; Each pair once: two springs between the same particles would be one
;; spring twice as stiff.
(check "Springies: each model's springs join particles it has, each pair \
        once, each at rest"
       (for-all
        (lambda (m)
          (let ([ps (sp:springies-model-particles m)]
                [ss (sp:springies-model-springs m)])
            (define (ends s) (list (min (sp:spring-a s) (sp:spring-b s))
                                   (max (sp:spring-a s) (sp:spring-b s))))
            (and (for-all
                  (lambda (s)
                    (and (< -1 (sp:spring-a s) (vector-length ps))
                         (< -1 (sp:spring-b s) (vector-length ps))
                         (not (= (sp:spring-a s) (sp:spring-b s)))
                         (= (sp:spring-rest-length s)
                            (sp:pt-norm
                             (sp:pt- (sp:particle-position
                                      (vector-ref ps (sp:spring-a s)))
                                     (sp:particle-position
                                      (vector-ref ps (sp:spring-b s))))))))
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
          (let ([ss (sp:springies-model-springs m)])
            (let loop ([ps (sp:springies-model-particles m)] [i 0])
              (if (< i 300)
                  (loop (sp:springies-frame
                         (if (= i 150) (sp:springies-kick ps) ps)
                         ss (sp:springies-model-settings m) 760.0 520.0)
                        (+ i 1))
                  (and (not (for-all eq? (vector->list ps)
                                     (vector->list
                                      (sp:springies-model-particles m))))
                       (for-all (lambda (p)
                                  (let ([q (sp:particle-position p)]
                                        [r (sp:particle-radius p)])
                                    (and (<= r (sp:pt-x q) (- 760.0 r))
                                         (<= r (sp:pt-y q) (- 520.0 r)))))
                                (vector->list ps))
                       (for-all
                        (lambda (s)
                          (< 0.5
                             (/ (sp:pt-norm
                                 (sp:pt- (sp:particle-position
                                          (vector-ref ps (sp:spring-a s)))
                                         (sp:particle-position
                                          (vector-ref ps (sp:spring-b s)))))
                                (sp:spring-rest-length s))
                             1.5))
                        ss))))))
        (test-models)))

(check "Springies: only the snake starts without gravity"
       (equal? (map (lambda (m)
                      (sp:springies-setting (sp:springies-model-settings m)
                                            'gravity?))
                    (test-models))
               '(#t #t #f)))

(check "Springies: a kick moves every particle, from where it was"
       (let* ([ps (sp:springies-model-particles
                   (sp:springies-ball 760.0 520.0))]
              [kicked (sp:springies-kick ps)])
         (for-all (lambda (p q)
                    (and (eq? (sp:particle-position p) (sp:particle-position q))
                         (not (equal? (sp:pt-x (sp:particle-velocity p))
                                      (sp:pt-x (sp:particle-velocity q))))))
                  (vector->list ps) (vector->list kicked))))

(check "Springies: setting a setting keeps the others, and their order"
       (let* ([settings '(gravity 980.0 gravity? #t time-step 0.004 steps 4)]
              [set (sp:springies-set-setting settings 'time-step 0.002)])
         (and (= (sp:springies-setting set 'time-step) 0.002)
              (equal? (plist-keys set) (plist-keys settings))
              (= (sp:springies-setting set 'steps) 4)
              (raises? (lambda ()
                       (sp:springies-set-setting settings 'drag 1.0)))
              (raises? (lambda () (sp:springies-setting settings 'drag))))))

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
(let ([win (sp:springies)])
  (define (key! k) (window-call win 'key k '()))
  (define (particles) (window-ref win 'particles))
  (define (setting key) (sp:springies-setting (window-ref win 'settings) key))
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
              [t (sp:make-tether 1 (sp:make-pt 60.0 40.0) 100.0 5.0)]
              [forces (sp:springies-forces ps (list t))])
         (and (test-pt-close? (sp:tether-force t ps) 990.0 -995.0 0.0)
              (eq? (vector-ref forces 0) sp:pt-zero)
              (test-pt-close? (vector-ref forces 1) 990.0 -995.0 0.0))))

(check "Springies: the particle nearest a point, within reach"
       (let ([ps (vector (test-particle 0.0 0.0 0.0 0.0 1.0 1.0)
                         (test-particle 30.0 0.0 0.0 0.0 1.0 1.0)
                         (test-particle 60.0 0.0 0.0 0.0 1.0 1.0))])
         (and (= (sp:springies-nearest ps (sp:make-pt 40.0 5.0) 50.0) 1)
              (= (sp:springies-nearest ps (sp:make-pt 100.0 0.0) 50.0) 2)
              (not (sp:springies-nearest ps (sp:make-pt 200.0 0.0) 50.0)))))

;; The mouse, through the window's handlers, at a particle's place on the
;; screen: y flipped.
(let ([win (sp:springies)])
  (define (particle i) (vector-ref (window-ref win 'particles) i))
  (define (screen-of i)
    (let-values ([(w h) (sp:springies-box-size win)])
      (let ([q (sp:particle-position (particle i))])
        (values (sp:pt-x q) (- h (sp:pt-y q))))))
  (check "Springies: a press near a particle holds it on the pointer's \
          tether, one far from all holds none"
         (let-values ([(x y) (screen-of 5)])
           (window-call win 'mouse-down (+ x 4) (- y 3) 'left 1)
           (let ([t (window-ref win 'tether)])
             (window-call win 'mouse-up (+ x 4) (- y 3) 'left)
             (and t (= (sp:tether-particle t) 5)
                  (let ([q (sp:particle-position (particle 5))])
                    (test-pt-close? (sp:tether-point t)
                                    (+ (sp:pt-x q) 4) (+ (sp:pt-y q) 3) 1e-9))
                  (not (window-ref win 'tether))
                  (begin (window-call win 'mouse-down 1 1 'left 1)
                         (not (window-ref win 'tether)))))))
  ;; held 100 pixels up, against two frames let be
  (check "Springies: the held particle follows the pointer, until let go"
         (let*-values ([(x y) (screen-of 5)]
                       [(w h) (sp:springies-box-size win)])
           (window-call win 'mouse-down x y 'left 1)
           (window-call win 'mouse-move x (- y 100))
           (let* ([frame (lambda (ps)
                           (sp:springies-frame ps (window-ref win 'springs)
                                               (window-ref win 'settings) w h))]
                  [let-be (vector-ref (frame (frame (window-ref win
                                                                'particles)))
                                      5)])
             (test-frame! win)
             (test-frame! win)
             (let ([pulled (> (sp:pt-y (sp:particle-position (particle 5)))
                              (+ (sp:pt-y (sp:particle-position let-be)) 1.0))])
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
(let* ([win (parameterize ([new-window-position '(40 . 60)]) (sp:springies))]
       [controls (lambda () (find-window "Springies — Controls"))]
       [setting (lambda (key)
                  (sp:springies-setting (window-ref win 'settings) key))]
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
                                (set! bottom (sp:springies-draw-controls
                                              ui win w)))))])
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
             (fluid-let ([sp:springies-controls-size
                          (lambda () (values (+ w dw) h))])
               (steps 1))
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
(let ([win (parameterize ([new-window-position '(400 . 60)]) (sp:springies))])
  (check "Springies: opened where the controls can't fit beside, the box \
          moves"
         (let ([cw (find-window "Springies — Controls")])
           (and (< (window-x win) 400)
                (= (+ (window-x win) (window-w win) 12) (window-x cw)))))
  (close-window! win))

(check "Springies: a frame leaves the particles it steps as they were"
       (let* ([m (sp:springies-ball 760.0 520.0)]
              [ps (sp:springies-model-particles m)]
              [before (vector->list ps)])
         (sp:springies-frame ps (sp:springies-model-springs m)
                             (sp:springies-model-settings m) 760.0 520.0)
         (for-all eq? (vector->list ps) before)))

