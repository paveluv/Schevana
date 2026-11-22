;;; tests/units/boids.ss — Boids: a demo, what of the world it uses: its
;;; steering a worklet on the crew, which steps the flock as the caller
;;; alone would, allocating only its sums; its keys and its rules window.

;; Boids' own names, bo:boids-step and the rest (tests/reach.ss).
(test-library '(demo boids) 'bo:)

;; Three boids close together: x, y, and the heading's dx, dy.
(define three-boids
  (flvector 0.0 0.0 1.0 0.0
            1.0 1.0 0.0 1.0
            2.0 0.0 1.0 1.0))

(check "Boids' steering is a worklet; its rules window is no app's, the \
        flock's own"
       (let* ([win (bo:boids)]
              [rw (find-window "Boids — Rules")]
              [ok (and (worklet? bo:boids-steer!)
                       (eq? (window-app win) 'boids)
                       (not (window-app rw))
                       (eq? (window-owner rw) win))])
         (close-window! win)
         ok))

;; The default rules with some set: (test-rules 'cohesion 1.0 ...).
(define (test-rules . sets)
  (let loop ([rules bo:boids-default-rules] [sets sets])
    (if (null? sets)
        rules
        (loop (bo:boids-set-rule rules (car sets) (cadr sets)) (cddr sets)))))

(check "Boids: a step leaves the flock it steps as it was"
       (let ([before (flvector->list three-boids)])
         (bo:boids-step three-boids bo:boids-default-rules)
         (equal? (flvector->list three-boids) before)))

;; The crew splits a step by boids, each worklet writing its own: the
;; flock it makes is the one the caller alone makes, to the last digit.
(random-seed 2024)
(check "Boids: a step on the crew is the one on the caller alone, under the \
        default rules and random ones"
       (let ([size (crew-size)])
         (define (step-on workers flock rules)
           (crew-size-set! workers)
           (flvector->list (bo:boids-step-on flock rules 400 300)))
         (let ([ok (for-all
                    (lambda (trial)
                      (let ([rules (if (= trial 0)
                                       bo:boids-default-rules
                                       (bo:boids-random-rules))]
                            [flock (bo:boids-scatter 300 400 300)])
                        (equal? (step-on 8 flock rules)
                                (step-on 0 flock rules))))
                    (iota 12))])
           (crew-size-set! size)
           ok)))

(check "Boids: a step's worklet allocates only its sums"
       (let* ([flock (bo:boids-scatter 300 200 200)]
              [next (make-flvector (flvector-length flock))]
              [rules (bo:boids-steering
                      (test-rules 'separation 0.5 'clear-view 0.5 'back-off 0.5
                                  'view-angle 300.0))])
         (bo:boids-steer! 0 300 flock next rules)
         (let ([b0 (bytes-total)])
           (do ([i 0 (fx+ i 1)]) ((fx= i 20))
             (bo:boids-steer! 0 300 flock next rules))
           (let ([b (- (bytes-total) b0)])
             (printf "  ~a bytes in 20 steps of 300 boids\n" b)
             (< b 4096)))))

(check "Boids: resizing a flock keeps the boids already there"
       (let ([fewer (bo:boids-resize three-boids 2 100 100)]
             [more (bo:boids-resize three-boids 5 100 100)]
             [first-numbers (lambda (f n) (list-head (flvector->list f) n))])
         (and (= (bo:boids-size fewer) 2) (= (bo:boids-size more) 5)
              (equal? (flvector->list fewer) (first-numbers three-boids 8))
              (equal? (first-numbers more 12) (flvector->list three-boids))
              (eq? (bo:boids-resize three-boids 3 100 100) three-boids))))

;; 50 frames of 150 boids.
(check "Boids: a frame keeps every boid on screen, within the speed limits"
       (let ([lo (bo:boids-rule bo:boids-default-rules 'min-speed)]
             [hi (bo:boids-rule bo:boids-default-rules 'max-speed)])
         (let loop ([flock (bo:boids-scatter 150 900 600)] [i 0])
           (or (= i 50)
               (let ([next (bo:boids-step-on flock bo:boids-default-rules
                                             900 600)])
                 (and (for-all
                       (lambda (k)
                         (let ([s (sqrt (+ (expt (bo:boid-vx next k) 2)
                                           (expt (bo:boid-vy next k) 2)))])
                           (and (<= 0.0 (bo:boid-x next k) 900.0)
                                (<= 0.0 (bo:boid-y next k) 600.0)
                                (<= (- lo 1e-9) s (+ hi 1e-9)))))
                       (iota 150))
                      (loop next (+ i 1))))))))

(check "Boids: random rules are the rules, each within its range"
       (let loop ([i 0])
         (or (= i 500)
             (let ([rules (bo:boids-random-rules)])
               (and (equal? (plist-keys rules)
                            (plist-keys bo:boids-default-rules))
                    (for-all (lambda (range)
                               (<= (cadr range)
                                   (bo:boids-rule rules (car range))
                                   (caddr range)))
                             bo:boids-ranges)
                    (<= (bo:boids-rule rules 'min-speed)
                        (bo:boids-rule rules 'max-speed))
                    (loop (+ i 1)))))))

;; The keys, through the window's own handler. A clock moved a second on
;; lets a tick step whether or not the last one was long ago.
(let ([win (bo:boids)])
  (define (key! k) (window-call win 'key k '()))
  (define (flock) (window-ref win 'flock))
  (define (tick-later!)
    (fluid-let ([now-ms (let ([t (now-ms)]) (lambda () (+ t 1000)))])
      (steps 1)))
  (check "Boids: R picks random rules, D the defaults again"
         (begin
           (key! #\r)
           (and (not (equal? (window-ref win 'rules) bo:boids-default-rules))
                (begin (key! #\d)
                       (eq? (window-ref win 'rules) bo:boids-default-rules)))))
  (check "Boids: S scatters as many boids anew"
         (let ([before (flock)])
           (key! #\s)
           (and (= (bo:boids-size (flock)) (bo:boids-size before))
                (not (equal? (flock) before)))))
  (check "Boids: Space holds the flock still, and again sets it going"
         (let ([before (begin (key! #\space) (flock))])
           (tick-later!)
           (let ([held? (eq? (flock) before)])
             (key! #\space)
             (tick-later!)
             (and held? (not (eq? (flock) before))))))
  (close-window! win))

(check "Boids: setting a rule keeps the others, and their order"
       (let ([rules (bo:boids-set-rule bo:boids-default-rules 'view-angle
                                       270.0)])
         (and (= (bo:boids-rule rules 'view-angle) 270.0)
              (equal? (plist-keys rules) (plist-keys bo:boids-default-rules))
              (= (bo:boids-rule rules 'cohesion)
                 (bo:boids-rule bo:boids-default-rules 'cohesion)))))

(check "Boids: min and max speed can't cross; the one set pushes the other"
       (let ([faster (bo:boids-set-rule bo:boids-default-rules 'min-speed 4.5)]
             [slower (bo:boids-set-rule bo:boids-default-rules 'max-speed 0.6)])
         (and (= (bo:boids-rule faster 'max-speed) 4.5)
              (= (bo:boids-rule slower 'min-speed) 0.6)
              (= (bo:boids-rule (bo:boids-set-rule bo:boids-default-rules
                                                   'min-speed 2.0)
                                'max-speed)
                 4.0))))

(check "Boids: a weight's slider is a cube, the others straight"
       (let ([cohesion (assq 'cohesion bo:boids-ranges)]
             [radius (assq 'cohesion-radius bo:boids-ranges)])
         (and (< (abs (- (bo:boids-slider-value cohesion 0.5) 0.025)) 1e-12)
              (< (abs (- (bo:boids-slider-t cohesion 0.025) 0.5)) 1e-12)
              (= (bo:boids-slider-value radius 0.5) 100.0)
              (= (bo:boids-slider-t radius 100.0) 0.5))))

;; The rules window, opened with the flock, where both fit.
(let* ([win (parameterize ([new-window-position '(40 . 60)]) (bo:boids))]
       [rules-win (lambda () (find-window "Boids — Rules"))]
       [press! (lambda (rw id)   ; the middle of the widget id
                 (let ([r (ui-find (window-ref rw 'ui) id)])
                   (let ([x (+ (ui-region-x r) (/ (ui-region-w r) 2))]
                         [y (+ (ui-region-y r) (/ (ui-region-h r) 2))])
                     (window-call rw 'mouse-down x y 'left 1)
                     (window-call rw 'mouse-up x y 'left))))])
  (render-frame!)
  (check "Boids: the rules window opens beside the flock, which has the keys"
         (let ([rw (rules-win)])
           (and rw (eq? (focused-window) win)
                (= (window-x rw) (+ (window-x win) (window-w win) 12))
                (= (window-y rw) (window-y win)))))
  (check "Boids: the rules window has room for all its rows"
         (let-values ([(w h) (window-content-size (rules-win))])
           (let* ([bottom #f]
                  [s (image (exact (ceiling w)) (exact (ceiling h)) 1
                            (lambda ()
                              (let ([ui (make-ui)])
                                (ui-begin! ui)
                                (set! bottom
                                      (bo:boids-draw-rules ui win w)))))])
             (picture-free! s)
             (<= bottom h))))
  (check "Boids: the rules window paints the style's page under its rows"
         (let*-values ([(rw) (rules-win)] [(w h) (window-content-size rw)])
           (let* ([surfaces '()]
                  [real ui-draw-surface]
                  [s (fluid-let ([ui-draw-surface
                                  (lambda (x y w h flags)
                                    (set! surfaces (cons flags surfaces))
                                    (real x y w h flags))])
                       (image (exact (ceiling w)) (exact (ceiling h)) 1
                              (lambda ()
                                (parameterize ([current-window rw])
                                  ((hashtable-ref (window-handlers rw) 'draw #f)
                                   rw w h)))))])
             (picture-free! s)
             (and (member '(page) surfaces) #t))))
  (check "Boids: its slider sets the flock's rule, on a weight's cube"
         (begin
           (press! (rules-win) 'cohesion)
           (< (abs (- (bo:boids-rule (window-ref win 'rules) 'cohesion) 0.025))
              1e-9)))
  (check "Boids: its buttons and keys act on the flock"
         (begin
           (press! (rules-win) 'randomize)
           (and (not (eq? (window-ref win 'rules) bo:boids-default-rules))
                (begin (window-call (rules-win) 'key #\d '())
                       (eq? (window-ref win 'rules) bo:boids-default-rules)))))
  (check "Boids: its count slider resizes the flock"
         (begin
           (press! (rules-win) 'count)
           (= (bo:boids-size (window-ref win 'flock))
              (round (+ 10 (/ (- bo:boids-max-count 10) 2))))))
  (check "Boids: its threads slider sets the crew's size, and shows it; a \
          small flock says it uses one"
         (let* ([size (crew-size)] [most (- (max 2 (platform-cpu-count)) 1)])
           (press! (rules-win) 'threads)
           (let ([set-to (crew-size)])
             (crew-size-set! 8)
             (let ([small (bo:boids-threads-readout 10)]
                   [big (bo:boids-threads-readout 2000)])
               (crew-size-set! 0)
               (let ([alone (bo:boids-threads-readout 2000)])
                 (crew-size-set! size)
                 (and (= set-to (exact (round (* 1/2 most))))
                      (equal? small "1 of 9")
                      (equal? big "9")
                      (equal? alone "1")))))))
  (check "Boids: H closes the rules window and opens it again"
         (begin
           (window-call win 'key #\h '())
           (and (not (rules-win))
                (begin (window-call win 'key #\h '())
                       (rules-win) #t))))
  ;; as when fonts grow in Settings: the rows ask for more room
  (check "Boids: the rules window grows when its rows need more, on screen"
         (let-values ([(w h) (window-content-size (rules-win))]
                      [(dx dy dw dh) (desktop-rect)])
           (define (grown-by! dw)
             (fluid-let ([bo:boids-rules-size (lambda () (values (+ w dw) h))])
               (steps 1))
             (let-values ([(w2 h2) (window-content-size (rules-win))])
               (and (= w2 (+ w dw)) (= h2 h))))
           (and (grown-by! 40)
                (= (window-x (rules-win))
                   (+ (window-x win) (window-w win) 12))   ; it fit there
                (grown-by! 400)
                (= (+ (window-x (rules-win)) (window-w (rules-win)))
                   (+ dx dw)))))                           ; it moved left
  (check "Boids: closing the flock closes its rules window"
         (begin (close-window! win) (not (rules-win)))))

;; Opened far to the right, the rules window is moved to fit, and the
;; flock moves left to clear it.
(let ([win (parameterize ([new-window-position '(400 . 60)]) (bo:boids))])
  (check "Boids: opened where the rules can't fit beside, the flock moves"
         (let ([rw (find-window "Boids — Rules")])
           (and (< (window-x win) 400)
                (= (+ (window-x win) (window-w win) 12) (window-x rw)))))
  (close-window! win))

(check "Boids' threads slider says they are the crew's, every app's"
       (let ([win (bo:boids)])
         (steps 2)
         (let* ([rw (find-window "Boids — Rules")]
                [r (ui-find (window-ref rw 'ui) 'threads)]
                [ok (string-contains-ci? (ui-region-tip r) "every app")])
           (close-window! win)
           ok)))
