;;; tests/units/boids.ss — Boids: its flocking against the rules written out
;;; plainly, its keys and its rules window.

;;; The Niva version's tests (tests/flockTest.niva in boids-niva), and the
;;; screen's rules.

;; Boids' own names, bo:boids-step and the rest (tests/reach.ss).
(test-library '(schevana-demo boids) 'bo:)

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

;; A flock as a list of (x y vx vy), and the flocking the obvious way on
;; such lists, rule by rule, the flonum operations in the Niva version's
;; order: the reference, to the last digit. Its rules are plain procedures
;; to read; the app's are one loop over flat numbers, for the crew.
(define (ref-flock flock)
  (let loop ([l (flvector->list flock)] [acc '()])
    (if (null? l)
        (reverse acc)
        (loop (list-tail l 4) (cons (list-head l 4) acc)))))
(define (ref-pos b) (cons (car b) (cadr b)))
(define (ref-vel b) (cons (caddr b) (cadddr b)))
(define ref-zero '(0.0 . 0.0))
(define (ref+ a b) (cons (+ (car a) (car b)) (+ (cdr a) (cdr b))))
(define (ref- a b) (cons (- (car a) (car b)) (- (cdr a) (cdr b))))
(define (ref* v k) (cons (* (car v) k) (* (cdr v) k)))
(define (ref/ v k) (cons (/ (car v) k) (/ (cdr v) k)))
(define (ref-dot a b) (+ (* (car a) (car b)) (* (cdr a) (cdr b))))
(define (ref-dist2 a b)
  (let ([dx (- (car a) (car b))] [dy (- (cdr a) (cdr b))])
    (+ (* dx dx) (* dy dy))))
(define (ref-mean vs) (ref/ (fold-left ref+ ref-zero vs) (inexact (length vs))))
(define (ref-sees? b other fov)
  (let* ([v (ref-vel b)] [h2 (ref-dot v v)])
    (or (= h2 0.0) (>= fov 360.0)
        (let* ([to (ref- (ref-pos other) (ref-pos b))]
               [lengths (sqrt (* h2 (ref-dot to to)))]
               [half (/ (* (/ fov 2.0) pi) 180.0)])
          (> (ref-dot v to) (* (cos half) lengths))))))
(define (ref-neighbors b flock r fov)
  (let ([r2 (* r r)])
    (filter (lambda (o)
              (let ([d2 (ref-dist2 (ref-pos b) (ref-pos o))])
                (and (> d2 0.0) (< d2 r2) (ref-sees? b o fov))))
            flock)))
(define (ref-steer b flock rules)
  (define (rule key) (bo:boids-rule rules key))
  (define (seen radius fov) (ref-neighbors b flock (rule radius) fov))
  (define (push weight thunk)
    (let ([w (rule weight)]) (if (= w 0.0) ref-zero (ref* (thunk) w))))
  (define (mean-from vs own)
    (if (null? vs) ref-zero (ref- (ref-mean vs) own)))
  (let* ([p (ref-pos b)] [v (ref-vel b)] [fov (rule 'view-angle)]
         [cone (min (rule 'blocker-cone) fov)]
         [next
          (fold-left
           ref+ v
           (list
            (push 'cohesion
                  (lambda ()
                    (mean-from (map ref-pos (seen 'cohesion-radius fov)) p)))
            (push 'alignment
                  (lambda ()
                    (mean-from (map ref-vel (seen 'alignment-radius fov)) v)))
            (push 'separation
                  (lambda ()
                    (let ([r2 (* (rule 'separation-radius)
                                 (rule 'separation-radius))])
                      (fold-left
                       (lambda (sum o)
                         (let ([d2 (ref-dist2 p (ref-pos o))])
                           (if (and (> d2 0.0) (< d2 r2))
                               (ref+ sum (ref- p (ref-pos o)))
                               sum)))
                       ref-zero flock))))
            (push 'clear-view
                  (lambda ()
                    (fold-left
                     (lambda (sum o)
                       (let* ([away (ref- p (ref-pos o))]
                              [d (sqrt (ref-dot away away))]
                              [turn (cons (- 0.0 (cdr away)) (car away))]
                              [side (if (< (ref-dot v turn) 0.0)
                                        (ref* turn -1.0)
                                        turn)])
                         (ref+ sum (ref/ side d))))
                     ref-zero (seen 'blocker-radius cone))))
            (push 'back-off
                  (lambda ()
                    (fold-left
                     (lambda (sum o)
                       (let* ([away (ref- p (ref-pos o))]
                              [d (sqrt (ref-dot away away))])
                         (ref+ sum (ref/ away d))))
                     ref-zero (seen 'blocker-radius cone))))))]
         [moved (ref+ p next)])
    (list (car moved) (cdr moved) (car next) (cdr next))))
(define (ref-step flock rules)
  (map (lambda (b) (ref-steer b flock rules)) flock))
;; A frame on a w × h screen: the speed limits, then the wrap.
(define (ref-step-on flock rules w h)
  (let ([lo (bo:boids-rule rules 'min-speed)]
        [hi (bo:boids-rule rules 'max-speed)])
    (map (lambda (b)
           (let* ([v (ref-vel b)] [s2 (ref-dot v v)]
                  [v (if (and (> s2 0.0) (< s2 (* lo lo)))
                         (ref* v (/ lo (sqrt s2)))
                         v)]
                  [s2 (ref-dot v v)]
                  [v (if (> s2 (* hi hi)) (ref* v (/ hi (sqrt s2))) v)])
             (list (mod (car b) w) (mod (cadr b) h) (car v) (cdr v))))
         (ref-step flock rules))))

(define test-flock-of list->flvector)

;; The default rules with some set: (test-rules 'cohesion 1.0 ...).
(define (test-rules . sets)
  (let loop ([rules bo:boids-default-rules] [sets sets])
    (if (null? sets)
        rules
        (loop (bo:boids-set-rule rules (car sets) (cadr sets)) (cddr sets)))))

;; To the last digit, so any change to the rules shows. They are the Niva
;; version's numbers: the same flonum operations, in the same order.
(check "Boids: three boids' first step is the Niva version's"
       (equal? (flvector->list
                (bo:boids-step three-boids bo:boids-default-rules))
               '(0.9869999999999999 0.054 0.9869999999999999 0.054
                 1.0 2.002 0.0 1.002
                 3.003 0.999 1.003 0.999)))

(check "Boids: a step leaves the flock it steps as it was"
       (let ([before (flvector->list three-boids)])
         (bo:boids-step three-boids bo:boids-default-rules)
         (equal? (flvector->list three-boids) before)))

(check "Boids: a boid is not its own neighbor"
       (equal? (flvector->list
                (bo:boids-step (flvector 0.0 0.0 1.0 0.0)
                               (test-rules 'cohesion 1.0 'alignment 1.0
                                           'separation 1.0 'view-angle 360.0
                                           'clear-view 1.0 'back-off 1.0)))
               '(1.0 0.0 1.0 0.0)))

;; Heading right, with one boid ahead, one to the side and one behind:
;; whether a boid at (x, y) pulls it, with only cohesion on.
(check "Boids: what the view angle lets a boid see"
       (let ([sees? (lambda (x y fov)
                      (let ([next (bo:boids-step
                                   (flvector 0.0 0.0 1.0 0.0 x y 1.0 0.0)
                                   (test-rules 'alignment 0.0 'separation 0.0
                                               'cohesion 1.0 'view-angle fov))])
                        (not (and (= (bo:boid-vx next 0) 1.0)
                                  (= (bo:boid-vy next 0) 0.0)))))])
         (and (sees? 3.0 0.0 180.0)
              (not (sees? 0.0 3.0 180.0))
              (not (sees? -3.0 0.0 180.0))
              (sees? 0.0 3.0 270.0)
              (not (sees? -3.0 0.0 270.0))
              (sees? -3.0 0.0 360.0)
              (sees? 3.0 0.0 10.0))))

;; Heading right: of these, only the boid close and straight ahead. Back
;; off, on alone, takes a unit of velocity straight back.
(check "Boids: blockers are close and ahead"
       (let ([next (bo:boids-step
                    (flvector 0.0 0.0 1.0 0.0
                              10.0 0.0 1.0 0.0      ; ahead
                              0.0 10.0 1.0 0.0      ; to the side
                              -10.0 0.0 1.0 0.0     ; behind
                              50.0 0.0 1.0 0.0)     ; too far
                    (test-rules 'cohesion 0.0 'alignment 0.0 'separation 0.0
                                'back-off 1.0 'view-angle 360.0))])
         (and (= (bo:boid-vx next 0) 0.0) (= (bo:boid-vy next 0) 0.0))))

;; One unit sideways, and one unit back. Heading a little upward, the
;; sideways step goes up too.
(check "Boids: clear view steps aside, back off steps back"
       (let ([quiet (lambda (key)
                      (test-rules 'cohesion 0.0 'alignment 0.0 'separation 0.0
                                  key 1.0))])
         (let ([aside (bo:boids-step (flvector 0.0 0.0 1.0 0.0 10.0 0.0 1.0 0.0)
                                     (quiet 'clear-view))]
               [back (bo:boids-step (flvector 0.0 0.0 1.0 0.0 10.0 0.0 1.0 0.0)
                                    (quiet 'back-off))]
               [climbing (bo:boids-step
                          (flvector 0.0 0.0 1.0 0.2 10.0 0.0 1.0 0.0)
                          (quiet 'clear-view))])
           (and (= (bo:boid-vx aside 0) 1.0) (= (bo:boid-vy aside 0) -1.0)
                (= (bo:boid-vx back 0) 0.0) (= (bo:boid-vy back 0) 0.0)
                (> (bo:boid-vy climbing 0) 0.2)))))

(random-seed 2024)
(check "Boids' steps are the reference's to the last digit, under the \
        default rules and random ones, on the crew and on the caller alone"
       (let ([size (crew-size)])
         (define (agree? workers)
           (crew-size-set! workers)
           (for-all
            (lambda (trial)
              (let ([rules (if (= trial 0)
                               bo:boids-default-rules
                               (bo:boids-random-rules))]
                    [flock (bo:boids-scatter 300 400 300)])
                (equal? (ref-flock (bo:boids-step-on flock rules 400 300))
                        (ref-step-on (ref-flock flock) rules 400.0 300.0))))
            (iota 12)))
         (let ([ok (and (agree? 8) (agree? 0))])
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
