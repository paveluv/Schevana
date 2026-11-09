;;; tests/units/boids3d.ss — Boids 3D: in its sandbox with the GPU, its
;;; flocking against the rules written out plainly, its shaders on the device
;;; against the twin, its picture, its keys.

;; Boids 3D runs in its sandbox (services/grant.ss): its names, forwarded here.
(define boids3d-box (grant-env 'boids3d))

(check "Boids 3D runs in its sandbox with the GPU's bundle, allowed by the \
        table, and nothing there waits for the GPU; its names and shaders \
        stay there; its rules window is no app's"
       (let* ([held (environment-symbols (env-environment boids3d-box))]
              [world (environment-symbols *world-env*)]
              [win (boids3d)]
              [rw (find-window "Boids 3D — Rules")]
              [ok (and (equal? (env-path boids3d-box) "/apps/boids3d")
                       (equal? (grant-requested 'boids3d)
                               '(window draw ui timers gpu))
                       (null? (grant-undecided 'boids3d))
                       (memq 'define-compute-shader held)
                       (memq 'gpu-compute-soon! held)
                       (not (memq 'gpu-compute! held))
                       (not (memq 'gpu-buffer-read! held))
                       (not (memq 'crew-for* held))
                       (memq 'boids3d-steer held)
                       (not (memq 'boids3d-steer world))
                       (eq? (window-app win) 'boids3d)
                       (not (window-app rw)))])
         (close-window! win)
         ok))

(for-each (lambda (n)
            (define-top-level-syntax n
              (forwarder-to (datum->syntax (env-anchor boids3d-box) n))))
          '(boids3d-steer boids3d-place boids3d-bin boids3d-view
            boids3d-steering boids3d-default-rules boids3d-rule
            boids3d-random-rules boids3d-ranges boids3d-set-rule
            boids3d-space boids3d-words boids3d-shape-words boids3d-step!
            boids3d-resize! boids3d-current boids3d-camera boids3d-horizon))

;;; ------------------------------------------------------------------ steps

;; A flock as a list of birds, each (x y z vx vy vz wing bank), and a step
;; the obvious way on such lists, rule by rule: the reference, in doubles,
;; where the shader works in floats.
(define (b3-v+ a b) (map + a b))
(define (b3-v- a b) (map - a b))
(define (b3-v* a k) (map (lambda (x) (* x k)) a))
(define (b3-dot a b) (apply + (map * a b)))
(define (b3-sum vs) (fold-left b3-v+ '(0.0 0.0 0.0) vs))

(define (b3-ref-step flock rules)
  (define (rule k) (inexact (boids3d-rule rules k)))
  (define (reach w r) (if (= (rule w) 0.0) 0.0 (* (rule r) (rule r))))
  (define (half-cos angle)
    (if (>= angle 360.0) -2.0 (cos (* (/ angle 2.0) (/ pi 180.0)))))
  (let ([fov (half-cos (rule 'view-angle))]
        [cone (half-cos (min (rule 'blocker-cone) (rule 'view-angle)))])
    (map
     (lambda (b)
       (let* ([p (list-head b 3)]
              [v (list-head (list-tail b 3) 3)]
              [h2 (b3-dot v v)]
              ;; the others within reach r2, inside the cone of cosine c
              [in (lambda (r2 c)
                    (filter (lambda (o)
                              (let* ([d (b3-v- (list-head o 3) p)]
                                     [d2 (b3-dot d d)]
                                     [a (b3-dot v d)])
                                (and (> d2 0.0) (< d2 r2)
                                     (or (= h2 0.0)
                                         (> a (* c (sqrt (* h2 d2))))))))
                            flock))]
              [toward (lambda (vs own w)
                        (if (null? vs)
                            '(0.0 0.0 0.0)
                            (b3-v* (b3-v- (b3-v* (b3-sum vs)
                                                 (/ 1.0 (length vs)))
                                          own)
                                   w)))]
              [offset (lambda (o) (b3-v- (list-head o 3) p))]
              [coh (toward (map (lambda (o) (list-head o 3))
                                (in (reach 'cohesion 'cohesion-radius) fov))
                           p (rule 'cohesion))]
              [ali (toward (map (lambda (o) (list-head (list-tail o 3) 3))
                                (in (reach 'alignment 'alignment-radius) fov))
                           v (rule 'alignment))]
              [sep (b3-v* (b3-sum (map offset
                                       (in (reach 'separation
                                                  'separation-radius)
                                           -2.0)))
                          (- (rule 'separation)))]
              ;; the heading's part square to the line to a blocker, a unit
              ;; step of it; and a unit step away
              [side (b3-v* (b3-sum
                            (map (lambda (o)
                                   (let* ([d (offset o)]
                                          [s (b3-v- v
                                                    (b3-v* d
                                                           (/ (b3-dot v d)
                                                              (b3-dot d d))))]
                                          [n (sqrt (b3-dot s s))])
                                     (if (> n 0.0) (b3-v* s (/ 1.0 n))
                                         '(0.0 0.0 0.0))))
                                 (in (reach 'clear-view 'blocker-radius) cone)))
                           (rule 'clear-view))]
              [back (b3-v* (b3-sum
                            (map (lambda (o)
                                   (let ([d (offset o)])
                                     (b3-v* d (/ -1.0 (sqrt (b3-dot d d))))))
                                 (in (reach 'back-off 'blocker-radius) cone)))
                           (rule 'back-off))]
              [nv (fold-left b3-v+ v (list coh ali sep side back))]
              [r (sqrt (b3-dot p p))]
              [nv (b3-v- nv (b3-v* p (/ (* (rule 'home)
                                           (max (- r boids3d-space) 0.0))
                                        (max r 1.0))))]
              [s (sqrt (b3-dot nv nv))]
              [k (cond [(> s (rule 'max-speed)) (/ (rule 'max-speed) s)]
                       [(and (> s 0.0) (< s (rule 'min-speed)))
                        (/ (rule 'min-speed) s)]
                       [else 1.0])]
              [nv (b3-v* nv k)]
              [s (* s k)]
              [climb (if (> s 0.0) (/ (cadr nv) s) 0.0)]
              [wing (+ (list-ref b 6) (min (max (+ 0.45 (* 0.3 climb)) 0.2)
                                           0.8))]
              [wing (- wing (* 6.2831853 (floor (* wing 0.15915494))))]
              [turn (if (> (* h2 s s) 0.0)
                        (/ (- (* (caddr v) (car nv)) (* (car v) (caddr nv)))
                           (sqrt (* h2 s s)))
                        0.0)]
              [bank (list-ref b 7)])
         (append (b3-v+ p nv) nv
                 (list wing
                       (+ bank (* 0.1 (- (min (max (* turn 12.0) -1.0) 1.0)
                                         bank)))))))
     flock)))

;; A flock as the bytes a buffer holds, floats, and back.
(define (b3-bytes flock)
  (let ([bv (make-bytevector (* 4 boids3d-words (length flock)) 0)])
    (for-each (lambda (b i)
                (for-each (lambda (v k)
                            (bytevector-ieee-single-native-set!
                             bv (* 4 (+ (* i boids3d-words) k)) v))
                          b (iota boids3d-words)))
              flock (iota (length flock)))
    bv))

(define (b3-flock bv n)
  (map (lambda (i)
         (map (lambda (k)
                (bytevector-ieee-single-native-ref
                 bv (* 4 (+ (* i boids3d-words) k))))
              (iota boids3d-words)))
       (iota n)))

;; A step of flock on the twin: the shader as Scheme, in floats.
(define (b3-twin-step flock rules)
  (let* ([n (length flock)]
         [in (b3-bytes flock)]
         [out (make-bytevector (bytevector-length in) 0)]
         [args (append (boids3d-steering rules) (list boids3d-space))])
    (do ([i 0 (+ i 1)]) ((= i n))
      (apply (twin-procedure boids3d-steer) i 0 n 1 in out n args))
    (b3-flock out n)))

;; n birds in a ball of radius r, heading anywhere, from a seed.
(define (b3-random-flock n r seed)
  (random-seed seed)
  (map (lambda (i)
         (append (map (lambda (k) (- (random (* 2.0 r)) r)) '(0 1 2))
                 (map (lambda (k) (- (random 4.0) 2.0)) '(0 1 2))
                 (list (random 6.2831853) (- (random 1.0) 0.5))))
       (iota n)))

;; Two flocks the same, but for floats' rounding.
(define (b3-close? a b)
  (for-all (lambda (x y)
             (for-all (lambda (u v)
                        (< (abs (- u v)) (* 1e-3 (max 1.0 (abs u)))))
                      x y))
           a b))

(check "Boids 3D: a step on the twin is the rules' worked out plainly, every \
        rule on, out of the ball and in, at the speed limits"
       (for-all
        (lambda (seed)
          (let* ([flock (b3-random-flock 40 320.0 seed)]
                 [rules (boids3d-set-rule
                         (boids3d-set-rule
                          (boids3d-set-rule
                           (boids3d-set-rule boids3d-default-rules
                                             'clear-view 0.3)
                           'back-off 0.2)
                          'blocker-radius 80.0)
                         'view-angle 270.0)])
            (b3-close? (b3-twin-step flock rules) (b3-ref-step flock rules))))
        '(1 2 3)))

(check "Boids 3D: what the view lets a bird see, a cone round its heading"
       (let* ([rules (boids3d-set-rule
                      (boids3d-set-rule boids3d-default-rules 'alignment 0.0)
                      'separation 0.0)]
              [bird '(0.0 0.0 0.0 2.0 0.0 0.0 0.0 0.0)]
              [ahead '(30.0 5.0 0.0 0.0 0.0 0.0 0.0 0.0)]
              [behind '(-30.0 5.0 0.0 0.0 0.0 0.0 0.0 0.0)]
              [step (lambda (other) (car (b3-twin-step (list bird other)
                                                       rules)))])
         ;; cohesion pulls toward one ahead, up and forward: none behind
         (and (> (list-ref (step ahead) 4) 0.0)
              (= (list-ref (step behind) 4) 0.0))))

(check "Boids 3D: clear view steps square to the line to a blocker, on the \
        side the bird heads; back off steps straight away"
       (let* ([rules (fold-left (lambda (r kv) (boids3d-set-rule r (car kv)
                                                                 (cdr kv)))
                                boids3d-default-rules
                                '((cohesion . 0.0) (alignment . 0.0)
                                  (separation . 0.0) (home . 0.0)
                                  (min-speed . 0.0) (max-speed . 10.0)))]
              ;; heading along x and a little up; a blocker straight ahead
              [bird '(0.0 0.0 0.0 2.0 0.5 0.0 0.0 0.0)]
              [blocker '(20.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0)]
              [side (car (b3-twin-step (list bird blocker)
                                       (boids3d-set-rule rules 'clear-view
                                                         1.0)))]
              [back (car (b3-twin-step (list bird blocker)
                                       (boids3d-set-rule rules 'back-off
                                                         1.0)))])
         ;; aside: up by a unit, the way it heads, x as it was; back: x less
         (and (< (abs (- (list-ref side 3) 2.0)) 1e-5)
              (< (abs (- (list-ref side 4) 1.5)) 1e-5)
              (< (abs (- (list-ref back 3) 1.0)) 1e-5)
              (< (abs (- (list-ref back 4) 0.5)) 1e-5))))

(check "Boids 3D: a bird out of the ball turns back toward its middle, and \
        its speed keeps within the limits"
       (let* ([far (+ boids3d-space 100.0)]
              ;; one past the ball flying round it, one nearly still
              [flock (list (list far 0.0 0.0 0.0 0.0 2.0 0.0 0.0)
                           (list 0.0 0.0 0.0 0.01 0.0 0.0 0.0 0.0))]
              [next (b3-twin-step flock boids3d-default-rules)]
              [speed (lambda (b) (sqrt (b3-dot (list-head (list-tail b 3) 3)
                                               (list-head (list-tail b 3)
                                                          3))))])
         (and (< (list-ref (car next) 3) 0.0)
              (for-all (lambda (b)
                         (<= (- (boids3d-rule boids3d-default-rules
                                              'min-speed)
                                1e-5)
                             (speed b)
                             (+ (boids3d-rule boids3d-default-rules
                                              'max-speed)
                                1e-5)))
                       next))))

;;; ------------------------------------------------------------------ the GPU

;; A step on the device, by the frame, read back.
(define (b3-device-step flock rules)
  (let* ([n (length flock)]
         [in (make-gpu-buffer (* boids3d-words n))]
         [out (make-gpu-buffer (* boids3d-words n))])
    (bytevector-copy! (b3-bytes flock) 0 (gpu-buffer-bytes in) 0
                      (* 4 boids3d-words n))
    (gpu-buffer-dirty! in 0 (* 4 boids3d-words n))
    (apply gpu-compute! boids3d-steer n 1 in out n
           (append (boids3d-steering rules) (list boids3d-space)))
    (gpu-buffer-read! out)
    (let ([next (b3-flock (gpu-buffer-bytes out) n)])
      (gpu-buffer-release! in)
      (gpu-buffer-release! out)
      next)))

;; But for rounding: a root is a device's to round as it likes, Metal's too
;; (tests/units/shader.ss holds it to the twin's +, -, * and / alone).
(check "Boids 3D: a step on the device is the twin's"
       (let* ([flock (b3-random-flock 200 300.0 7)]
              [rules (boids3d-set-rule boids3d-default-rules 'back-off 0.1)])
         (b3-close? (b3-device-step flock rules) (b3-twin-step flock rules))))

(check "Boids 3D: each tile lists the birds whose boxes touch it, in order, \
        as many as it holds"
       (let* ([n 5]
              [most 3]
              [across 4]
              [down 2]
              [boxes '((1.0 1.0 3.0 3.0)        ; tile 0
                       (14.0 2.0 18.0 4.0)      ; tiles 0 and 1
                       (1.0 1.0 -1.0 -1.0)      ; behind the eye: none
                       (2.0 2.0 40.0 20.0)      ; the first three across
                       (0.0 0.0 5.0 5.0))]      ; tile 0, past its room
              [shapes (make-bytevector (* 4 boids3d-shape-words n) 0)]
              [tiles (make-bytevector (* 4 across down (+ most 1)) 0)])
         (for-each (lambda (box i)
                     (for-each (lambda (v k)
                                 (bytevector-ieee-single-native-set!
                                  shapes (* 4 (+ (* i boids3d-shape-words) k))
                                  v))
                               box (iota 4)))
                   boxes (iota n))
         (do ([t 0 (+ t 1)]) ((= t (* across down)))
           ((twin-procedure boids3d-bin) (modulo t across) (quotient t across)
            across down shapes tiles n across most 16.0))
         (let ([tile (lambda (t)
                       (let* ([at (* t (+ most 1))]
                              [c (bytevector-s32-native-ref tiles (* 4 at))])
                         (map (lambda (k)
                                (bytevector-s32-native-ref
                                 tiles (* 4 (+ at 1 k))))
                              (iota c))))])
           (and (equal? (tile 0) '(0 1 3))
                (equal? (tile 1) '(1 3))
                (equal? (tile 2) '(3))
                (equal? (tile 3) '())
                (equal? (tile 6) '(3))
                (equal? (tile 7) '())))))

;;; ------------------------------------------------------------------ the app

;; The flock window, paused, its rules window closed: one bird, at the middle
;; of the ball heading right across the camera's view, the camera level in
;; front of it.
(define (b3-one-bird-window)
  (let ([win (boids3d)])
    (close-window! (find-window "Boids 3D — Rules"))
    (window-call win 'key #\space '())
    (window-set! win 'count 1)
    (for-each (lambda (b)
                (for-each (lambda (v k) (gpu-buffer-set! b k v))
                          '(0.0 0.0 0.0 2.0 0.0 0.0 1.57 0.0) (iota 8)))
              (let ([bs (window-ref win 'buffers)]) (list (car bs) (cdr bs))))
    (window-set! win 'yaw 0.0)
    (window-set! win 'pitch 0.0)
    (window-set! win 'scene-bearing 3.14)   ; open sea, the sun behind
    (invalidate! win)
    (steps 2)
    win))

(check "Boids 3D draws an evening sky, dark at the top and warm at the \
        horizon, the sea under it darker, and a bird on it where the camera \
        sees it"
       (let* ([win (b3-one-bird-window)])
         (let-values ([(cx cy cw ch) (content-rect win)])
           (let* ([fh (- ch (max 26 (round (+ (font-line-height 'ui-small)
                                                13))))]
                  [mx (+ cx (quotient cw 2))]
                  [my (+ cy (quotient fh 2))]
                  [hy (+ cy (exact (floor (* fh (boids3d-horizon 0.0)))))]
                  [red (lambda (p) (fxand (fxsrl p 16) 255))]
                  [light (lambda (p) (+ (fxand (fxsrl p 16) 255)
                                        (fxand (fxsrl p 8) 255)
                                        (fxand p 255)))]
                  [top (canvas-pixel mx (+ cy 2))]
                  [low (canvas-pixel mx (- hy 3))]
                  [sea (canvas-pixel mx (+ hy 30))]
                  [sky (canvas-pixel mx (- my 40))]
                  [darkest (apply min (map (lambda (dx)
                                             (apply min
                                                    (map (lambda (dy)
                                                           (light
                                                            (canvas-pixel
                                                             (+ mx dx)
                                                             (+ my dy))))
                                                         '(-2 -1 0 1 2))))
                                           '(-3 -2 -1 0 1 2 3)))])
             (close-window! win)
             (printf "  top ~x low ~x sea ~x sky ~a darkest ~a\n" top low sea
                     (light sky) darkest)
             (and (< (red top) (red low))
                  (< (light top) (light low))
                  (< (light sea) (light low))
                  (< darkest (- (light sky) 60)))))))

(check "Boids 3D: facing the sun, it sits on the horizon and lays a road on \
        the sea, brighter than the water beside it"
       (let ([win (b3-one-bird-window)])
         (window-set! win 'scene-bearing 0.0)
         (invalidate! win)
         (steps 2)
         (let-values ([(cx cy cw ch) (content-rect win)])
           (let* ([fh (- ch (max 26 (round (+ (font-line-height 'ui-small)
                                                13))))]
                  [mx (+ cx (quotient cw 2))]
                  [hy (+ cy (exact (floor (* fh (boids3d-horizon 0.0)))))]
                  [light (lambda (p) (+ (fxand (fxsrl p 16) 255)
                                        (fxand (fxsrl p 8) 255)
                                        (fxand p 255)))]
                  [road (apply max (map (lambda (dy)
                                          (light (canvas-pixel mx (+ hy dy))))
                                        '(6 8 10 12 14)))]
                  [beside (light (canvas-pixel (+ mx 150) (+ hy 10)))]
                  [sun (light (canvas-pixel mx (- hy 2)))])
             (close-window! win)
             (printf "  sun ~a road ~a beside ~a\n" sun road beside)
             (and (> sun 600) (> road (+ beside 60)))))))

(check "Boids 3D: a drag turns the scene with the camera; the camera's own \
        circling leaves the scene where it is"
       (let* ([win (boids3d)]
              [bearing (lambda () (window-ref win 'scene-bearing))]
              [start (bearing)])
         (close-window! (find-window "Boids 3D — Rules"))
         (let ([t (+ (now-ms) 40)]) (let loop () (when (< (now-ms) t) (loop))))
         (window-call win 'frame (now-ns))
         (let ([circled (window-ref win 'yaw)])
           (window-call win 'mouse-down 100 100 'left 1)
           (window-call win 'mouse-move 150 100)
           (window-call win 'mouse-up 150 100 'left)
           (let ([dragged (bearing)] [yaw (window-ref win 'yaw)])
             (close-window! win)
             (and (= start 1.39)
                  (> circled 0.6)
                  (< (abs (- dragged (- start 0.5))) 1e-9)
                  (< (abs (- yaw (- circled 0.5))) 1e-9))))))

(check "Boids 3D: space pauses the flock, h shows and hides the rules; a \
        closed window leaves no step waiting for the frame"
       (let* ([win (boids3d)]
              [box (env-environment boids3d-box)]
              [tick (lambda ()
                      (let ([t (+ (now-ms) 20)])
                        (let loop () (when (< (now-ms) t) (loop))))
                      (window-call win 'frame (now-ns)))]
              [flipped (lambda () (window-ref win 'flipped?))])
         (tick)
         (let* ([moving (let ([was (flipped)])
                          (tick)
                          (not (eq? was (flipped))))]
                [_ (window-call win 'key #\space '())]
                [still (let ([was (flipped)]) (tick) (eq? was (flipped)))]
                [rules? (find-window "Boids 3D — Rules")]
                [_ (window-call win 'key #\h '())]
                [hidden (not (find-window "Boids 3D — Rules"))])
           (boids3d-step! win)
           (let ([waiting (map car (inspect-computes))])
             (close-window! win)
             (and moving still rules? hidden
                  (memq 'boids3d-steer waiting)
                  (not (memq 'boids3d-steer (map car (inspect-computes)))))))))

(check "Boids 3D: random rules are the rules, each within its range; what a \
        step is handed: a half view all round is -2, a rule without weight \
        reaches nothing"
       (let* ([rules (boids3d-random-rules)]
              [all-round (boids3d-set-rule
                          (boids3d-set-rule boids3d-default-rules 'view-angle
                                            360.0)
                          'cohesion 0.0)]
              [steering (boids3d-steering all-round)])
         (and (equal? (map car boids3d-ranges)
                      (let loop ([r rules])
                        (if (null? r) '() (cons (car r) (loop (cddr r))))))
              (for-all (lambda (range)
                         (<= (cadr range) (boids3d-rule rules (car range))
                             (caddr range)))
                       boids3d-ranges)
              (= (length steering) 15)
              (= (list-ref steering 5) -2.0)
              (= (list-ref steering 7) 0.0))))

(check "Boids 3D: its frames step the flock by time, 15 ms a step, three at \
        most however long since; the camera turns by the steps"
       (let* ([win (boids3d)]
              [yaw (lambda () (window-ref win 'yaw))]
              [t (+ (now-ns) 1000000000)])
         (close-window! (find-window "Boids 3D — Rules"))
         (let* ([y0 (yaw)]
                [late (begin (window-call win 'frame t) (- (yaw) y0))]
                [y1 (yaw)]
                [soon (begin (window-call win 'frame (+ t 5000000))
                             (- (yaw) y1))]
                [two (begin (window-call win 'frame (+ t 30000000))
                            (- (yaw) y1))])
           (close-window! win)
           (and (< (abs (- late (* 3 0.0015))) 1e-12)
                (= soon 0)
                (< (abs (- two (* 2 0.0015))) 1e-12)
                (not (hashtable-contains? (window-handlers win) 'tick))))))

;; Riding frames, the default, a minimized flock stays where it was; riding a
;; timer (boids3d-ride!, the rules window's checkbox), it flies on, asking
;; for no frame, its steps sent to the GPU at each turn's end; riding frames
;; again, its timer stops.
(check "Boids 3D rides frames by default: minimized, its flock waits"
       (let* ([win (boids3d)] [flipped (lambda () (window-ref win 'flipped?))])
         (close-window! (find-window "Boids 3D — Rules"))
         (steps 2)
         (minimize-window! win)
         (steps 1)
         (let ([was (flipped)])
           (steps 5)
           (let ([still (eq? was (flipped))])
             (close-window! win)
             (and still (eq? (window-ref win 'ride) 'frames))))))

(check "Boids 3D riding a timer flies on while minimized, asking for no \
        frame; riding frames again, its timer stops"
       (let* ([win (boids3d)]
              [box (env-environment boids3d-box)]
              [flips 0])
         (close-window! (find-window "Boids 3D — Rules"))
         (eval '(boids3d-ride! 'timer) box)
         (window-call win 'frame (now-ns))   ; its timer set
         (minimize-window! win)
         (steps 1)
         (let ([t (now-ms)] [timers (length *timers*)])
           (fluid-let ([now-ms (lambda () t)] [*dirty* #f])
             (do ([i 0 (+ i 1)]) ((= i 4))
               (let ([was (window-ref win 'flipped?)])
                 (set! t (+ t 15))
                 (run-timers!)
                 (unless (eq? was (window-ref win 'flipped?))
                   (set! flips (+ flips 1)))))
             (let ([quiet (not *dirty*)] [queued (pair? *gpu-computes*)])
               (eval '(boids3d-ride! 'frames) box)
               (set! t (+ t 15))
               (run-timers!)
               (let ([stopped (= (length *timers*) (- timers 1))])
                 (steps 1)   ; the steps queued go to the GPU
                 (let ([sent (null? *gpu-computes*)])
                   (close-window! win)
                   (and (= flips 4) quiet queued stopped sent))))))))
