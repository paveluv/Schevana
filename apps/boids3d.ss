;;; apps/boids3d.ss — Boids in three dimensions, as Craig Reynolds first made
;;; them (1987), all on the GPU: compute shaders steer the flock and lay it out
;;; on the screen, and a paint draws it, birds far off against an evening
;;; sky over the sea, the sun setting, a wooded shore with a lighthouse.
;;; The flock never comes back to the CPU, which only sets the rules, moves
;;; the camera and asks for the shaders with each frame.
;;;
;;; The rules are apps/boids.ss's, in space: cohesion, alignment and
;;; separation, a field of view that is a cone, and the two blocker rules
;;; from Flake's "The Computational Beauty of Nature". Clear view steps along
;;; the part of the heading square to the line to a blocker, which is what
;;; the 2D rule works out, in any dimension; back off steps straight away.
;;; Where Boids wraps at the screen's edges, these turn back toward the
;;; middle of their space when they leave it (home).
;;;
;;; A bird is a body and two wings, beating, swept back and banked into its
;;; turns, seen by a camera that circles the flock: far away, its outline
;;; changes as a real one's does, a dash from the side, a V from below.
;;; R: random rules · D: the defaults · S: scatter · H: the rules window ·
;;; Space: pause · drag: move round the flock
;;;
;;; It runs in a sandbox (services/grant.ss), where its shaders touch only the
;;; buffers it hands them.

(app-requests window draw ui timers gpu)

;;; ------------------------------------------------------------------ rules

;; The flocking rules, as a plist: apps/boids.ss's, and home, how hard a bird
;; outside the space turns back. Speeds are in units a step; the space is a
;; ball boids3d-space units from its middle. Boids' own defaults, seeing only
;; ahead and hardly apart, string a flock out in lines; these make a
;; murmuration of it, a sheet that bends and thins as it turns: cohesion
;; weak and wide, alignment near, room between them, and seeing most of the
;; way round.
(define boids3d-default-rules
  '(cohesion 0.001
    cohesion-radius 120.0
    alignment 0.08
    alignment-radius 40.0
    separation 0.08
    separation-radius 18.0
    view-angle 300.0
    clear-view 0.0
    back-off 0.0
    blocker-radius 40.0
    blocker-cone 90.0
    home 0.003
    min-speed 1.5
    max-speed 3.0))

(define (boids3d-rule rules key)
  (let ([at (memq key rules)])
    (if at (cadr at) (errorf 'boids3d-rule "no rule ~s" key))))

;; Each rule's range, in the order the rules window shows them; a weight
;; starts at 0, and its useful values span orders of magnitude.
(define boids3d-ranges
  '((cohesion 0.0 0.2 weight)
    (cohesion-radius 0.0 200.0)
    (alignment 0.0 1.0 weight)
    (alignment-radius 0.0 200.0)
    (separation 0.0 1.0 weight)
    (separation-radius 0.0 50.0)
    (view-angle 0.0 360.0)
    (clear-view 0.0 1.0 weight)
    (back-off 0.0 1.0 weight)
    (blocker-radius 0.0 100.0)
    (blocker-cone 0.0 180.0)
    (home 0.0 0.1 weight)
    (min-speed 0.0 5.0)
    (max-speed 0.5 10.0)))

;; Rules picked at random within their ranges, a weight on a cube, max speed
;; from min speed up, as Boids picks them.
(define (boids3d-random-rules)
  (fold-left
   (lambda (rules range)
     (apply (lambda (key lo hi . weight)
              (let* ([lo (if (eq? key 'max-speed)
                             (max lo (boids3d-rule rules 'min-speed))
                             lo)]
                     [r (random 1.0)]
                     [t (if (null? weight) r (* r r r))])
                (append rules (list key (+ lo (* t (- hi lo)))))))
            range))
   '() boids3d-ranges))

;; Rules with key's value v; min and max speed push each other along.
(define (boids3d-set-rule rules key v)
  (define (with rules key v)
    (cond [(null? rules) (errorf 'boids3d-set-rule "no rule ~s" key)]
          [(eq? (car rules) key) (cons* key v (cddr rules))]
          [else (cons* (car rules) (cadr rules) (with (cddr rules) key v))]))
  (let ([rules (with rules key v)])
    (case key
      [(min-speed) (if (> v (boids3d-rule rules 'max-speed))
                       (with rules 'max-speed v)
                       rules)]
      [(max-speed) (if (< v (boids3d-rule rules 'min-speed))
                       (with rules 'min-speed v)
                       rules)]
      [else rules])))

;; What a step's shader is handed of the rules, in its parameters' order:
;; the weights; the cosines of half the field of view and of half the
;; blockers' cone, -2 for all around, which any heading beats; the reaches
;; squared, 0 for a rule without weight; home; the speed limits.
(define (boids3d-steering rules)
  (define (rule key) (inexact (boids3d-rule rules key)))
  (define (reach weight radius)
    (if (= (rule weight) 0.0) 0.0 (* (rule radius) (rule radius))))
  (define (half-cosine angle)
    (if (>= angle 360.0) -2.0 (cos (/ (* (/ angle 2.0) pi) 180.0))))
  (let ([reaches (list (reach 'cohesion 'cohesion-radius)
                       (reach 'alignment 'alignment-radius)
                       (reach 'separation 'separation-radius)
                       (reach 'clear-view 'blocker-radius)
                       (reach 'back-off 'blocker-radius))]
        [fov (rule 'view-angle)])
    (append (map rule '(cohesion alignment separation clear-view back-off))
            (list (half-cosine fov)
                  (half-cosine (min (rule 'blocker-cone) fov)))
            reaches
            (list (rule 'home) (rule 'min-speed) (rule 'max-speed)))))

;;; ------------------------------------------------------------------ the GPU

(define boids3d-most 4096)       ; birds at most: the shaders' loops' bound
(define boids3d-space 250.0)     ; the ball they keep to, its radius
(define boids3d-words 8)         ; a bird: x y z, its velocity, wing, bank
(define boids3d-shape-words 24)  ; one on the screen (boids3d-place)
(define boids3d-tile 16)         ; device pixels a tile's side
(define boids3d-tile-most 48)    ; birds a tile lists at most

;; A step: every bird steered by the flock as it is, into next. The pairs
;; the rules count are those apps/boids.ss's do; what one neighbor adds is
;; worked out again for each sum, which the GPU's compiler does once, and its
;; ifs are selects (1.0 or 0.0), so that the loop doesn't branch.
(define-compute-shader (boids3d-steer i row)
  ([flock fl-buffer]
   [next fl-buffer write]
   [n fixnum]
   [cohesion flonum]
   [alignment flonum]
   [separation flonum]
   [clear-view flonum]
   [back-off flonum]
   [fov flonum]               ; cosines of half the field of view
   [cone flonum]              ; and of half the blockers' cone
   [cohesion-reach flonum]    ; squared
   [alignment-reach flonum]
   [separation-reach flonum]
   [clear-reach flonum]
   [back-reach flonum]
   [home flonum]
   [min-speed flonum]
   [max-speed flonum]
   [space flonum])
  (define (at j k) (fl-ref flock (fx+ (fx* j 8) k)))
  (define (on c) (if c 1.0 0.0))
  (let* ([x (at i 0)]
         [y (at i 1)]
         [z (at i 2)]
         [vx (at i 3)]
         [vy (at i 4)]
         [vz (at i 5)]
         [h2 (fl+ (fl+ (fl* vx vx) (fl* vy vy)) (fl* vz vz))]
         [blockers? (fl> (fl+ clear-view back-off) 0.0)])
    (define (dx j) (fl- (at j 0) x))
    (define (dy j) (fl- (at j 1) y))
    (define (dz j) (fl- (at j 2) z))
    (define (dist2 j)
      (let ([a (dx j)] [b (dy j)] [c (dz j)])
        (fl+ (fl+ (fl* a a) (fl* b b)) (fl* c c))))
    (define (ahead j)
      (fl+ (fl+ (fl* vx (dx j)) (fl* vy (dy j))) (fl* vz (dz j))))
    ;; 1.0 if j is another bird within reach r2, inside the cone whose half's
    ;; cosine is c: ahead > c √(h2 d2), squared with its sign, no root. A bird
    ;; standing still sees everything.
    (define (in j r2 c)
      (let ([d2 (dist2 j)] [a (ahead j)])
        (fl* (fl* (on (fl> d2 0.0)) (on (fl< d2 r2)))
             (flmax (on (fl= h2 0.0))
                    (on (fl> (fl* a (flabs a))
                             (fl* (fl* c (flabs c)) (fl* h2 d2))))))))
    ;; part k of what j's nearness pushes: away from it, close; and, with the
    ;; blocker rules on, a unit step sideways out from behind it and one away
    (define (push j d k)
      (let* ([d2 (dist2 j)]
             [dist (flsqrt (flmax d2 0.000001))]
             [a (ahead j)]
             ;; the heading's part square to the line to j, its length
             [side (fl- (fl* (if (fx= k 0) vx (if (fx= k 1) vy vz)) d2)
                        (fl* a d))]
             [side2 (fl* d2 (fl- (fl* h2 d2) (fl* a a)))])
        (fl+ (fl* (fl* separation (in j separation-reach -2.0)) (fl- 0.0 d))
             (if blockers?
                 (fl+ (fl* (fl* clear-view (in j clear-reach cone))
                           (if (fl> side2 0.0)
                               (fl/ side (flsqrt side2))
                               0.0))
                      (fl* (fl* back-off (in j back-reach cone))
                           (fl/ (fl- 0.0 d) dist)))
                 0.0))))
    ;; toward the mean of a sum over count, from own, by weight
    (define (toward sum count own weight)
      (if (fl> count 0.0)
          (fl* (fl- (fl/ sum count) own) weight)
          0.0))
    (do-bounded 4096
        ([j 0 (fx+ j 1)]
         [cx 0.0 (fl+ cx (fl* (in j cohesion-reach fov) (at j 0)))]
         [cy 0.0 (fl+ cy (fl* (in j cohesion-reach fov) (at j 1)))]
         [cz 0.0 (fl+ cz (fl* (in j cohesion-reach fov) (at j 2)))]
         [cn 0.0 (fl+ cn (in j cohesion-reach fov))]
         [ax 0.0 (fl+ ax (fl* (in j alignment-reach fov) (at j 3)))]
         [ay 0.0 (fl+ ay (fl* (in j alignment-reach fov) (at j 4)))]
         [az 0.0 (fl+ az (fl* (in j alignment-reach fov) (at j 5)))]
         [an 0.0 (fl+ an (in j alignment-reach fov))]
         [px 0.0 (fl+ px (push j (dx j) 0))]
         [py 0.0 (fl+ py (push j (dy j) 1))]
         [pz 0.0 (fl+ pz (push j (dz j) 2))])
      ((fx>= j n)
       (let* ([nx (fl+ (fl+ (fl+ vx (toward cx cn x cohesion))
                            (toward ax an vx alignment))
                       px)]
              [ny (fl+ (fl+ (fl+ vy (toward cy cn y cohesion))
                            (toward ay an vy alignment))
                       py)]
              [nz (fl+ (fl+ (fl+ vz (toward cz cn z cohesion))
                            (toward az an vz alignment))
                       pz)]
              ;; out of the ball, back toward its middle, the harder the
              ;; farther out
              [r (flsqrt (fl+ (fl+ (fl* x x) (fl* y y)) (fl* z z)))]
              [pull (fl/ (fl* home (flmax (fl- r space) 0.0)) (flmax r 1.0))]
              [nx (fl- nx (fl* x pull))]
              [ny (fl- ny (fl* y pull))]
              [nz (fl- nz (fl* z pull))]
              ;; the speed limits; standing still, it stays put
              [s (flsqrt (fl+ (fl+ (fl* nx nx) (fl* ny ny)) (fl* nz nz)))]
              [k (if (fl> s max-speed)
                     (fl/ max-speed s)
                     (if (and (fl> s 0.0) (fl< s min-speed))
                         (fl/ min-speed s)
                         1.0))]
              [nx (fl* nx k)]
              [ny (fl* ny k)]
              [nz (fl* nz k)]
              [s (fl* s k)]
              ;; the wings beat faster climbing, slower diving; a turn
              ;; banks it, round the way it turns
              [climb (if (fl> s 0.0) (fl/ ny s) 0.0)]
              [beat (flmin (flmax (fl+ 0.45 (fl* 0.3 climb)) 0.2) 0.8)]
              [wing (fl+ (at i 6) beat)]
              [wing (fl- wing (fl* 6.2831853 (flfloor (fl* wing 0.15915494))))]
              [turn (if (fl> (fl* h2 (fl* s s)) 0.0)
                        (fl/ (fl- (fl* vz nx) (fl* vx nz))
                             (flsqrt (fl* h2 (fl* s s))))
                        0.0)]
              [bank (at i 7)]
              [bank (fl+ bank (fl* 0.1 (fl- (flmin (flmax (fl* turn 12.0)
                                                           -1.0)
                                                     1.0)
                                               bank)))]
              [o (fx* i 8)])
         (fl-set! next o (fl+ x nx))
         (fl-set! next (fx+ o 1) (fl+ y ny))
         (fl-set! next (fx+ o 2) (fl+ z nz))
         (fl-set! next (fx+ o 3) nx)
         (fl-set! next (fx+ o 4) ny)
         (fl-set! next (fx+ o 5) nz)
         (fl-set! next (fx+ o 6) wing)
         (fl-set! next (fx+ o 7) bank))))))

;; Each bird on the screen, by a camera at the eye, its axes right, up and
;; ahead, focal device pixels to the unit at a unit away, its middle at cx
;; cy: its box; its chest, head and tail; each wing's wrist and tip, left
;; then right; the chest's, the shoulder's, the wrist's and the tip's half
;; widths; and how much the haze leaves of it. A bird behind the eye has an
;; empty box, one that ends before it starts, left of the screen. A wing
;; bends at the wrist, the hand swept back and beating further than the arm,
;; so that far off its outline is a bird's: an M, a gull's curve, a dash edge
;; on.
(define-compute-shader (boids3d-place i row)
  ([flock fl-buffer]
   [shapes fl-buffer write]
   [ex flonum]
   [ey flonum]
   [ez flonum]
   [rx flonum]
   [ry flonum]
   [rz flonum]
   [ux flonum]
   [uy flonum]
   [uz flonum]
   [fx flonum]
   [fy flonum]
   [fz flonum]
   [focal flonum]
   [cx flonum]
   [cy flonum]
   [span flonum]              ; a bird's wings, tip to tip, in units
   [haze flonum])             ; how far, until half of it is gone
  (define (at k) (fl-ref flock (fx+ (fx* i 8) k)))
  (define (put k v) (fl-set! shapes (fx+ (fx* i 24) k) v))
  (let* ([x (at 0)]
         [y (at 1)]
         [z (at 2)]
         [vx (at 3)]
         [vy (at 4)]
         [vz (at 5)]
         [s (flsqrt (fl+ (fl+ (fl* vx vx) (fl* vy vy)) (fl* vz vz)))]
         ;; its own axes: ahead, right (level), up; then banked
         [ax (if (fl> s 0.0) (fl/ vx s) 1.0)]
         [ay (if (fl> s 0.0) (fl/ vy s) 0.0)]
         [az (if (fl> s 0.0) (fl/ vz s) 0.0)]
         [level (flsqrt (fl+ (fl* ax ax) (fl* az az)))]
         [bx (if (fl> level 0.001) (fl/ (fl- 0.0 az) level) 1.0)]
         [bz (if (fl> level 0.001) (fl/ ax level) 0.0)]
         [tx (fl- 0.0 (fl* bz ay))]
         [ty (fl- (fl* bz ax) (fl* bx az))]
         [tz (fl* bx ay)]
         [roll (at 7)]
         [c (flcos roll)]
         [sn (flsin roll)]
         [wx (fl+ (fl* bx c) (fl* tx sn))]
         [wy (fl* ty sn)]
         [wz (fl+ (fl* bz c) (fl* tz sn))]
         [qx (fl- (fl* tx c) (fl* bx sn))]
         [qy (fl* ty c)]
         [qz (fl- (fl* tz c) (fl* bz sn))]
         ;; the wings' angle: a beat, wide climbing and slow, small diving
         [climb (if (fl> s 0.0) (fl/ vy s) 0.0)]
         [wide (flmin (flmax (fl+ 0.5 (fl* 0.6 climb)) 0.15) 0.9)]
         [lift (fl* wide (flsin (at 6)))]
         [hand (fl* 1.6 lift)]
         [arm-out (fl* (fl* 0.22 span) (flcos lift))]
         [arm-up (fl* (fl* 0.22 span) (flsin lift))]
         [tip-out (fl+ arm-out (fl* (fl* 0.28 span) (flcos hand)))]
         [tip-up (fl+ arm-up (fl* (fl* 0.28 span) (flsin hand)))]
         ;; the camera's view of the middle: one depth for the whole bird
         [mx (fl- x ex)]
         [my (fl- y ey)]
         [mz (fl- z ez)]
         [depth (fl+ (fl+ (fl* mx fx) (fl* my fy)) (fl* mz fz))]
         [k (if (fl> depth 1.0) (fl/ focal depth) 0.0)])
    ;; a point da ahead, dr right and du up from the bird's middle, on the
    ;; screen
    (define (screen-x da dr du)
      (let ([px (fl+ (fl+ (fl+ mx (fl* ax da)) (fl* wx dr)) (fl* qx du))]
            [py (fl+ (fl+ (fl+ my (fl* ay da)) (fl* wy dr)) (fl* qy du))]
            [pz (fl+ (fl+ (fl+ mz (fl* az da)) (fl* wz dr)) (fl* qz du))])
        (fl+ cx (fl* k (fl+ (fl+ (fl* px rx) (fl* py ry)) (fl* pz rz))))))
    (define (screen-y da dr du)
      (let ([px (fl+ (fl+ (fl+ mx (fl* ax da)) (fl* wx dr)) (fl* qx du))]
            [py (fl+ (fl+ (fl+ my (fl* ay da)) (fl* wy dr)) (fl* qy du))]
            [pz (fl+ (fl+ (fl+ mz (fl* az da)) (fl* wz dr)) (fl* qz du))])
        (fl- cy (fl* k (fl+ (fl+ (fl* px ux) (fl* py uy)) (fl* pz uz))))))
    (let* ([chest (fl* 0.06 span)]
           [wrist (fl* 0.1 span)]
           [hand (fl* -0.16 span)]
           [chest-x (screen-x chest 0.0 0.0)]
           [chest-y (screen-y chest 0.0 0.0)]
           [head-x (screen-x (fl* 0.28 span) 0.0 0.0)]
           [head-y (screen-y (fl* 0.28 span) 0.0 0.0)]
           [tail-x (screen-x (fl* -0.3 span) 0.0 0.0)]
           [tail-y (screen-y (fl* -0.3 span) 0.0 0.0)]
           [left-wrist-x (screen-x wrist (fl- 0.0 arm-out) arm-up)]
           [left-wrist-y (screen-y wrist (fl- 0.0 arm-out) arm-up)]
           [left-tip-x (screen-x hand (fl- 0.0 tip-out) tip-up)]
           [left-tip-y (screen-y hand (fl- 0.0 tip-out) tip-up)]
           [right-wrist-x (screen-x wrist arm-out arm-up)]
           [right-wrist-y (screen-y wrist arm-out arm-up)]
           [right-tip-x (screen-x hand tip-out tip-up)]
           [right-tip-y (screen-y hand tip-out tip-up)]
           [body (fl* k (fl* 0.075 span))]
           [edge (fl+ (flmax body 0.5) 1.0)]
           [d (fl/ depth haze)])
      (put 0 (if (fl> k 0.0)
                 (fl- (flmin (flmin (flmin chest-x head-x)
                                    (flmin tail-x left-wrist-x))
                             (flmin (flmin left-tip-x right-wrist-x)
                                    right-tip-x))
                      edge)
                 1.0))
      (put 1 (fl- (flmin (flmin (flmin chest-y head-y)
                                (flmin tail-y left-wrist-y))
                         (flmin (flmin left-tip-y right-wrist-y)
                                right-tip-y))
                  edge))
      (put 2 (if (fl> k 0.0)
                 (fl+ (flmax (flmax (flmax chest-x head-x)
                                    (flmax tail-x left-wrist-x))
                             (flmax (flmax left-tip-x right-wrist-x)
                                    right-tip-x))
                      edge)
                 -1.0))
      (put 3 (fl+ (flmax (flmax (flmax chest-y head-y)
                                (flmax tail-y left-wrist-y))
                         (flmax (flmax left-tip-y right-wrist-y)
                                right-tip-y))
                  edge))
      (put 4 chest-x)
      (put 5 chest-y)
      (put 6 head-x)
      (put 7 head-y)
      (put 8 tail-x)
      (put 9 tail-y)
      (put 10 left-wrist-x)
      (put 11 left-wrist-y)
      (put 12 left-tip-x)
      (put 13 left-tip-y)
      (put 14 right-wrist-x)
      (put 15 right-wrist-y)
      (put 16 right-tip-x)
      (put 17 right-tip-y)
      (put 18 body)
      (put 19 (fl* k (fl* 0.07 span)))
      (put 20 (fl* k (fl* 0.045 span)))
      (put 21 (fl* k (fl* 0.012 span)))
      (put 22 (fl/ 1.0 (fl+ 1.0 (fl* d d)))))))

;; Each tile across × down of the screen lists the birds whose boxes touch
;; it, at most most of them: its count, then theirs, most + 1 words a tile.
;; A tile writes only its own, so that no two cells touch one word.
(define-compute-shader (boids3d-bin tx ty)
  ([shapes fl-buffer]
   [tiles fx-buffer write]
   [n fixnum]
   [across fixnum]
   [most fixnum]
   [tile flonum])
  (define (at j k) (fl-ref shapes (fx+ (fx* j 24) k)))
  (let* ([base (fx* (fx+ tx (fx* ty across)) (fx+ most 1))]
         [x0 (fl* (fixnum->flonum tx) tile)]
         [y0 (fl* (fixnum->flonum ty) tile)]
         [x1 (fl+ x0 tile)]
         [y1 (fl+ y0 tile)])
    (fx-set! tiles base
             (do-bounded 4096
                 ([j 0 (fx+ j 1)]
                  [c 0 (if (and (fx< c most)
                                (fl<= (at j 0) x1)
                                (fl>= (at j 2) x0)
                                (fl<= (at j 1) y1)
                                (fl>= (at j 3) y0))
                           (begin
                             (fx-set! tiles (fx+ base (fx+ c 1)) j)
                             (fx+ c 1))
                           c)])
               ((fx>= j n) c)))))

;; The scene round the flock, a pixel at a time: an evening sky from its top
;; to the horizon, clouds drifting in a band of it, the sun half set at
;; bearing 0, the sea below the horizon mirroring the sky, the sun's road on
;; it glittering, and a wooded headland at bearing 1.7 with a lighthouse at
;; its tip, a hazy ridge behind, both mirrored. It turns with the scene's own
;; bearing, not the camera's circling. Over it the birds the pixel's tile
;; lists: each dark strokes for its body and its wings, narrowing to the
;; tips, as much of it as the haze leaves. They're all one ink, so what's in
;; front doesn't matter: the scene shows through each by what it leaves.
(define-paint (boids3d-view x y)
  ([shapes fl-buffer]
   [tiles fx-buffer]
   [across fixnum]
   [most fixnum]
   [tile fixnum]
   [h fixnum]
   [top color]
   [middle color]
   [low color]
   [ink color]
   [left flonum]        ; the bearing at the field's left edge, radians
   [step flonum]        ; radians a device pixel
   [drift flonum]       ; how far the clouds have drifted, cells
   [time flonum]        ; seconds, for the waves and the lamp
   [horizon flonum])    ; the horizon's height, a share of the field's
  (define (at j k) (fl-ref shapes (fx+ (fx* j 24) k)))
  (define (part c shift) (fixnum->flonum (fxand (fxsrl c shift) 255)))
  (define (clamp01 v) (flmax 0.0 (flmin 1.0 v)))
  (define (mix a b t) (fl+ a (fl* t (fl- b a))))
  (define (fract v) (fl- v (flfloor v)))
  (define (smooth v) (fl* v (fl* v (fl- 3.0 (fl* 2.0 v)))))
  (define (hash i j)
    (let* ([a (fract (fl* i 0.1031))]
           [b (fract (fl* j 0.1031))]
           [d (fl+ (fl* a (fl+ b 33.33))
                   (fl+ (fl* b (fl+ a 33.33)) (fl* a (fl+ a 33.33))))])
      (fract (fl* (fl+ (fl+ a d) (fl+ b d)) (fl+ a d)))))
  (define (wrap k period) (fl- k (fl* period (flfloor (fl/ k period)))))
  (define (noise u v period)
    (let* ([i (flfloor u)] [j (flfloor v)]
           [su (smooth (fl- u i))] [sv (smooth (fl- v j))]
           [i0 (wrap i period)] [i1 (wrap (fl+ i 1.0) period)]
           [j1 (fl+ j 1.0)])
      (mix (mix (hash i0 j) (hash i1 j) su)
           (mix (hash i0 j1) (hash i1 j1) su)
           sv)))
  ;; an angle brought within half a turn either way
  (define (around a)
    (fl- a (fl* 6.2831853 (flfloor (fl/ (fl+ a 3.1415927) 6.2831853)))))
  (define (sun-col shift) (part #xfff1c8 shift))
  (define (glow-col shift) (part #xff9a5a shift))
  (define (land-col shift) (part #x1c1a28 shift))
  (define (deep-col shift) (part #x15233a shift))
  (define (sand-col shift) (part #x8a6a58 shift))
  (define (lamp-col shift) (part #xffe9a8 shift))
  (define (tower-col shift) (part #xd8cfc8 shift))
  (define (band-col shift) (part #x9a3b3b shift))
  (let* ([px (fl+ (fixnum->flonum x) 0.5)]
         [py (fl+ (fixnum->flonum y) 0.5)]
         [hf (fixnum->flonum (if (fx> h 1) h 1))]
         [hy (fl* hf horizon)]              ; the horizon
         [sea? (fl> py hy)]
         [base (fx* (fx+ (fxquotient x tile)
                         (fx* (fxquotient y tile) across))
                    (fx+ most 1))]
         [count (fx-ref tiles base)]
         [bearing (fl+ left (fl* px step))]
         [focal (fl/ 1.0 step)]
         ;; the sun: due bearing 0, half set
         [r (fl* hf 0.032)]
         [sdx (fl* (around bearing) focal)]
         [sy (fl- hy (fl* r 0.35))]
         [mirror (if sea? (fl- hy (fl- py hy)) py)]
         [sdy (fl- mirror sy)]
         [sd (flsqrt (fl+ (fl* sdx sdx) (fl* sdy sdy)))]
         [disk (if sea? 0.0 (clamp01 (fl+ (fl- r sd) 0.5)))]
         [halo (let ([g (clamp01 (fl- 1.0 (fl/ sd (fl* r 9.0))))])
                 (fl* g g))]
         [wide (let ([g (clamp01 (fl- 1.0 (fl/ (flabs sdx)
                                               (fl* hf 1.4))))])
                 (fl* g (fl* g (clamp01 (fl/ py hy)))))]
         ;; the far shore, a wooded headland at bearing 1.7
         [a (around (fl- bearing 1.7))]
         [hill (fl- 1.0 (smooth (clamp01 (fl/ (flabs a) 0.8))))]
         [k (fl/ (fl* bearing focal) (fl* hf 0.011))]
         [pine (fl* (fl* 0.022 (fl+ 0.55 (fl* 0.45 (hash (flfloor k) 3.0))))
                    (fl- 1.0 (fl* 2.0 (flabs (fl- (fract k) 0.5)))))]
         [k2 (fl+ (fl* k 0.62) 0.3)]
         [crown (let ([c (fl- (fl* 2.0 (fract k2)) 1.0)])
                  (fl* (fl* 0.016 (fl+ 0.5 (fl* 0.5
                                                 (hash (flfloor k2) 9.0))))
                       (flsqrt (flmax 0.0 (fl- 1.0 (fl* c c))))))]
         [mixed (if (fl> (hash (flfloor (fl* k 0.13)) 5.0) 0.45)
                    (flmax pine (fl* crown 0.9))
                    (flmax (fl* pine 0.8) crown))]
         [trees (fl* (smooth (clamp01 (fl* hill 4.0))) (fl* hf mixed))]
         [land-h (fl+ (fl* hf (fl* 0.045 (fl* hill
                                              (fl+ 0.7 (fl* 0.5
                                                (noise (fl* bearing 5.0)
                                                       1.0 31.0))))))
                      trees)]
         ;; a farther ridge, hazy, behind the headland
         [a2 (around (fl- bearing 1.25))]
         [ridge-h (fl* hf (fl* 0.03 (fl* (fl- 1.0 (smooth (clamp01
                                                      (fl/ (flabs a2) 1.3))))
                                         (fl+ 0.55 (fl* 0.7
                                           (noise (fl* bearing 9.0) 4.0
                                                  57.0))))))]
         [ridge (if sea? 0.0
                    (clamp01 (fl+ (fl- py (fl- hy ridge-h)) 0.5)))]
         [land (if sea?
                   0.0
                   (clamp01 (fl+ (fl- py (fl- hy land-h)) 0.5)))]
         ;; sand where the headland meets the sea
         [beach (if (and (not sea?) (fl> hill 0.05)
                         (fl> py (fl- hy (fl* hf (fl* 0.005 hill)))))
                    0.8
                    0.0)]
         ;; a lighthouse at the headland's tip, its lamp pulsing
         [lx (fl* (around (fl- bearing 2.27)) focal)]
         [lbase (fl- hy (fl* hf 0.006))]
         [ltop (fl- lbase (fl* hf 0.075))]
         [lup (clamp01 (fl/ (fl- lbase py) (fl- lbase ltop)))]
         [tower (if (and (not sea?) (fl< py lbase) (fl> py ltop)
                         (fl< (flabs lx) (fl* hf (fl- 0.0095
                                                     (fl* 0.0035 lup)))))
                    1.0
                    0.0)]
         [band (if (fl> (fract (fl* lup 4.0)) 0.5) 1.0 0.0)]
         [beat (fl+ 0.45 (fl* 0.55 (clamp01 (fl* 3.0 (flsin (fl* time 1.6))))))]
         [ly (fl- ltop (fl* hf 0.006))]
         [lmy (if sea? (fl- hy (fl- py hy)) py)]
         [ld (flsqrt (fl+ (fl* lx lx) (fl* (fl- lmy ly) (fl- lmy ly))))]
         [lamp (fl* beat
                    (if sea?
                        (fl* 0.5 (clamp01 (fl- 1.0 (fl/ (flabs lx)
                                                         (fl* hf 0.006)))))
                        (flmax (clamp01 (fl+ (fl- (fl* hf 0.006) ld) 0.5))
                               (let ([g (clamp01 (fl- 1.0
                                                      (fl/ ld
                                                           (fl* hf 0.05))))])
                                 (fl* 0.6 (fl* g g))))))]
         ;; the clouds, slower, in a band of the upper sky
         [cu (fl+ (fl* bearing (fl/ 20.0 6.2831853)) drift)]
         [cv (fl* py (fl* (fl/ (fl/ 20.0 6.2831853) focal) 2.6))]
         [cuc (fl* cu 1.0)]
         [d (fl+ (fl* 0.5 (noise cuc cv 20.0))
                 (fl+ (fl* 0.25 (noise (fl* cuc 2.0) (fl* cv 2.0) 40.0))
                      (fl+ (fl* 0.125 (noise (fl* cuc 4.0) (fl* cv 4.0)
                                             80.0))
                           (fl* 0.0625 (noise (fl* cuc 8.0) (fl* cv 8.0)
                                              160.0)))))]
         [ct (fl+ (fl/ py hf) (fl- 0.8 horizon))]
         [band (fl* (smooth (clamp01 (fl/ (fl- ct 0.04) 0.2)))
                    (fl- 1.0 (smooth (clamp01 (fl/ (fl- ct 0.36) 0.18)))))]
         [cover (if sea? 0.0
                    (fl* (smooth (clamp01 (fl* (fl- d 0.47) 3.2))) band))]
         [core (clamp01 (fl* (fl- d 0.62) 3.0))]
         ;; the sea: deeper toward the viewer, the shore's mirror under
         ;; it, rippled, and the sun's road, glittering
         [s (if sea? (clamp01 (fl/ (fl- py hy) (fl- hf hy))) 0.0)]
         [ripple (if sea?
                     (noise (fl* sdx (fl/ 0.07 (fl+ s 0.04)))
                            (fl+ (fl/ 4.5 (fl+ s 0.03)) (fl* time 0.9))
                            1000000.0)
                     0.0)]
         [shore (if (and sea? (fl< (fl- py hy)
                                   (fl* (flmax land-h ridge-h)
                                        (fl+ 0.75
                                                     (fl* 0.4 ripple)))))
                    0.85
                    0.0)]
         [road (if sea?
                   (let ([g (clamp01
                             (fl- 1.0 (fl/ (flabs sdx)
                                           (fl* r (fl+ 0.9 (fl* 3.5 s))))))])
                     (fl* (fl* g g)
                          (fl* (smooth (clamp01 (fl* (fl- ripple 0.38)
                                                     3.0)))
                               (fl- 1.0 (fl* 0.4 s)))))
                   0.0)])
    (define (gradient y shift)
      (let ([t (clamp01 (fl/ y hy))])
        (if (fl< t 0.65)
            (mix (part top shift) (part middle shift) (fl/ t 0.65))
            (let ([u (fl/ (fl- t 0.65) 0.35)])
              (mix (part middle shift) (part low shift) (fl* u u))))))
    (define (sky shift)
      (if sea?
          (let* ([mirrored (fl+ (fl* 0.72 (gradient mirror shift))
                                (fl* 0.5 (fl* (fl+ (fl* 0.5 halo) wide)
                                              (glow-col shift))))]
                 [water (mix mirrored (deep-col shift)
                             (fl* 0.75 (flsqrt s)))]
                 [mirrored-shore (mix water (fl* 0.8 (land-col shift))
                                      shore)])
            (mix (mix mirrored-shore (sun-col shift)
                      (clamp01 (fl* 1.3 road)))
                 (lamp-col shift)
                 (clamp01 (fl* lamp (fl+ 0.3 (fl* 0.7 ripple))))))
          (let* ([clear (gradient py shift)]
                 [lit (fl* (mix (mix (part middle shift) 255.0 0.45)
                                (part low shift)
                                (fl* 0.8 (clamp01 (fl/ ct 0.5))))
                           (fl- 1.0 (fl* 0.32 core)))]
                 [clouded (mix clear lit (fl* 0.92 cover))]
                 [glowing (mix clouded (glow-col shift)
                               (clamp01 (fl+ (fl* 0.55 halo)
                                             (fl* 0.35 wide))))]
                 [sunned (mix glowing (sun-col shift) disk)])
            (let* ([far (mix sunned (mix (land-col shift) clear 0.55)
                             ridge)]
                   [near (mix far (mix (land-col shift) clear 0.15) land)]
                   [sandy (mix near (sand-col shift) (fl* beach land))]
                   [towered (mix sandy
                                 (mix (fl* 0.7 (tower-col shift))
                                      (fl* 0.75 (band-col shift)) band)
                                 tower)])
              (mix towered (lamp-col shift) (clamp01 lamp))))))
    (define (stroke ax ay bx by r q)
      (let* ([pax (fl- px ax)]
             [pay (fl- py ay)]
             [bax (fl- bx ax)]
             [bay (fl- by ay)]
             [len2 (flmax (fl+ (fl* bax bax) (fl* bay bay)) 0.0001)]
             [s (clamp01 (fl/ (fl+ (fl* pax bax) (fl* pay bay)) len2))]
             [dx (fl- pax (fl* bax s))]
             [dy (fl- pay (fl* bay s))]
             [w (fl+ r (fl* (fl- q r) s))]
             [ww (flmax w 0.5)])
        (fl* (clamp01 (fl- 0.5 (fl- (flsqrt (fl+ (fl* dx dx) (fl* dy dy)))
                                    ww)))
             (fl/ w ww))))
    (define (bird-cover j)
      (if (and (fl>= px (at j 0)) (fl<= px (at j 2))
               (fl>= py (at j 1)) (fl<= py (at j 3)))
          (let ([x (at j 4)] [y (at j 5)] [body (at j 18)]
                [shoulder (at j 19)] [wrist (at j 20)] [tip (at j 21)])
            (fl* (at j 22)
                 (flmax
                  (flmax (stroke x y (at j 6) (at j 7) body
                                 (fl* 0.5 body))
                         (stroke x y (at j 8) (at j 9) body
                                 (fl* 0.3 body)))
                  (flmax
                   (flmax (stroke x y (at j 10) (at j 11) shoulder wrist)
                          (stroke (at j 10) (at j 11) (at j 12) (at j 13)
                                  wrist tip))
                   (flmax (stroke x y (at j 14) (at j 15) shoulder wrist)
                          (stroke (at j 14) (at j 15) (at j 16) (at j 17)
                                  wrist tip))))))
          0.0))
    (let ([sky-left
           (do-bounded 64
               ([k 0 (fx+ k 1)]
                [left 1.0 (fl* left
                               (fl- 1.0
                                    (bird-cover
                                     (fx-ref tiles
                                             (fx+ base (fx+ k 1))))))])
             ((fx>= k count) left))])
      (define (channel shift)
        (flonum->fixnum
         (flround (flmax 0.0 (flmin 255.0 (mix (part ink shift) (sky shift)
                                    sky-left))))))
      (fxior (fxsll 255 24)
             (fxior (fxsll (channel 16) 16)
                    (fxior (fxsll (channel 8) 8) (channel 0)))))))

;;; ------------------------------------------------------------------ flocks

;; A flock's two buffers, room for boids3d-most birds each: a step reads one
;; and writes the other.
(define (boids3d-buffers)
  (cons (make-gpu-buffer (* boids3d-words boids3d-most))
        (make-gpu-buffer (* boids3d-words boids3d-most))))

;; A point in the ball of radius r, picked evenly.
(define (boids3d-random-in-ball r)
  (let loop ()
    (let ([x (- (random 2.0) 1.0)]
          [y (- (random 2.0) 1.0)]
          [z (- (random 2.0) 1.0)])
      (if (> (+ (* x x) (* y y) (* z z)) 1.0)
          (loop)
          (list (* r x) (* r y) (* r z))))))

;; Birds from up to to, new in both buffers, since a step waiting for the
;; frame may read either: in the ball, heading anywhere, their wings anywhere
;; in a beat.
(define (boids3d-scatter-into! buffers from to)
  (do ([i from (+ i 1)]) ((>= i to))
    (let ([words (append (boids3d-random-in-ball (* 0.8 boids3d-space))
                         (boids3d-random-in-ball 2.0)
                         (list (random 6.2831853) 0.0))])
      (for-each (lambda (b)
                  (for-each (lambda (v k)
                              (gpu-buffer-set! b (+ (* i boids3d-words) k) v))
                            words (iota boids3d-words)))
                (list (car buffers) (cdr buffers))))))

;; The camera on a sphere round the flock's middle, looking at it: its eye,
;; then its axes right, up and ahead, as boids3d-place takes them.
(define (boids3d-camera yaw pitch distance)
  (let* ([ex (* distance (cos pitch) (sin yaw))]
         [ey (* distance (sin pitch))]
         [ez (* distance (cos pitch) (cos yaw))]
         [fx (/ (- ex) distance)]
         [fy (/ (- ey) distance)]
         [fz (/ (- ez) distance)]
         [l (sqrt (+ (* fx fx) (* fz fz)))]
         [rx (/ (- fz) l)]
         [rz (/ fx l)])
    (list ex ey ez
          rx 0.0 rz
          (- (* rz fy)) (- (* rz fx) (* rx fz)) (* rx fy)
          fx fy fz)))

;;; ------------------------------------------------------------------ the app

(define boids3d-step-ns 15000000) ; a step about 60 times a second, as Boids'
(define boids3d-step-ms (quotient boids3d-step-ns 1000000))
(define boids3d-count 1000)    ; how many a new window starts with
(define boids3d-span 9.0)      ; a bird's wings, tip to tip, in units
(define boids3d-haze 1400.0)   ; how far until half a bird is gone in it

;; The evening sky, from its top to the horizon, and the birds against it:
;; a scene's own colors, the theme's in no style.
(define boids3d-top #xff22385f)
(define boids3d-middle #xff6f88aa)
(define boids3d-low #xffe7bb93)
(define boids3d-ink #xff17161d)

(define (boids3d-bar-height)
  (max 26 (round (+ (font-line-height 'ui-small) 13))))

(define (boids3d-status-text n running?)
  (format "~a birds   ~ar random · d defaults · s scatter · h rules · drag to \
           turn · space pause"
          n (if running? "" "paused   ")))

;; The flock's field in win: its content above the status line.
(define (boids3d-field-size win)
  (let-values ([(w h) (window-content-size win)])
    (values w (max 1 (- h (boids3d-bar-height))))))

;; The buffer the newest step wrote, which the next reads.
(define (boids3d-current win)
  (let ([b (window-ref win 'buffers)])
    (if (window-ref win 'flipped?) (cdr b) (car b))))

;; A step of the flock in win, with the next frame: the current buffer into
;; the other, which is current then.
(define (boids3d-step! win)
  (let* ([b (window-ref win 'buffers)]
         [from (boids3d-current win)]
         [to (if (eq? from (car b)) (cdr b) (car b))]
         [n (window-ref win 'count)])
    (apply gpu-compute-soon! boids3d-steer n 1 from to n
           (append (boids3d-steering (window-ref win 'rules))
                   (list boids3d-space)))
    (window-set! win 'flipped? (not (window-ref win 'flipped?)))))

;; The tiles' buffer for at least words, made again when the field outgrows
;; it.
(define (boids3d-tiles! win words)
  (let ([t (window-ref win 'tiles)])
    (if (and t (>= (cdr t) words))
        (car t)
        (let ([new (make-gpu-buffer words)])
          (when t (gpu-buffer-release! (car t)))
          (window-set! win 'tiles (cons new words))
          new))))

;; The field, w × h: the flock laid out by the camera and listed by tile,
;; with the frame, then drawn by the paint over the scene, seen at the
;; window's scene bearing, the horizon raised as the camera looks down.
(define (boids3d-draw-field win w h)
  (let* ([s (draw-scale)]
         [pw (exact (ceiling (* w s)))]
         [ph (exact (ceiling (* h s)))]
         [tile boids3d-tile]
         [across (quotient (+ pw (- tile 1)) tile)]
         [down (quotient (+ ph (- tile 1)) tile)]
         [tiles (boids3d-tiles! win (* across down (+ boids3d-tile-most 1)))]
         [shapes (window-ref win 'shapes)]
         [n (window-ref win 'count)]
         [focal (* ph 1.07)]   ; 50° from the top of the field to its foot
         [turn 6.283185307179586]
         [left (- (window-ref win 'scene-bearing) (/ (/ pw 2.0) focal))]
         [ms (now-ms)]
         ;; a cloud cell drifts by in 150 s, 20 of them round the sky
         [drift (/ ms 150000.0)])
    (apply gpu-compute-soon! boids3d-place n 1 (boids3d-current win) shapes
           (append (boids3d-camera (window-ref win 'yaw) (window-ref win 'pitch)
                                   (window-ref win 'distance))
                   (list focal (/ pw 2.0) (/ ph 2.0) boids3d-span
                         boids3d-haze)))
    (gpu-compute-soon! boids3d-bin across down shapes tiles n across
                       boids3d-tile-most (inexact tile))
    (fill-shader 0 0 w h boids3d-view shapes tiles across boids3d-tile-most
                 tile ph boids3d-top boids3d-middle boids3d-low boids3d-ink
                 (- left (* turn (floor (/ left turn))))
                 (/ 1.0 focal)
                 (- drift (* 20.0 (floor (/ drift 20.0))))
                 (/ (mod ms 1000000) 1000.0)
                 (boids3d-horizon (window-ref win 'pitch)))))

;; The horizon's height, a share of the field's, for the camera's pitch: at
;; the pitch it starts at, about seven tenths down.
(define (boids3d-horizon pitch)
  (max 0.35 (min 0.95 (- 0.8 (* 1.07 (+ pitch 0.25))))))

;; What the keys and the rules window's buttons do to the flock in win.
(define (boids3d-randomize! win)
  (window-set! win 'rules (boids3d-random-rules)))
(define (boids3d-defaults! win) (window-set! win 'rules boids3d-default-rules))
(define (boids3d-scatter! win)
  (boids3d-scatter-into! (window-ref win 'buffers) 0 (window-ref win 'count)))

;; n birds: the first n of the flock, or all of it and newcomers.
(define (boids3d-resize! win n)
  (let ([was (window-ref win 'count)])
    (when (> n was)
      (boids3d-scatter-into! (window-ref win 'buffers) was n))
    (window-set! win 'count n)))

(define-app (boids3d) "Boids 3D"
  (let ([w 760] [h 520]
        [running? #t] [last-step (now-ns)]
        [drag #f]          ; (x y yaw pitch bearing) where a drag began
        [rules-win #f]
        [flying? #f]       ; its timer is set: it rides one ('ride timer)
        [closed? #f])
    (define (toggle-rules! win)
      (if rules-win
          (close-window! rules-win)
          (set! rules-win
                (boids3d-open-rules win (lambda () (set! rules-win #f))))))
    ;; While it rides a timer: a step every 15 ms, seen or not, until it
    ;; rides frames again or closes. A timer more than three steps late
    ;; starts again from now rather than catching up.
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
              ;; the steps due by t, three at most, so that a flock seen
              ;; again goes on rather than jumping ahead; riding a timer,
              ;; the timer steps it and its frames only turn the camera
              'frame (lambda (win t)
                       (window-frame-soon! win)
                       (when (and (eq? (window-ref win 'ride) 'timer)
                                  (not flying?))
                         (set! flying? #t)
                         (fly! win (now-ms)))
                       (if (not running?)
                           (set! last-step t)
                           (let ([n (min 3 (quotient (- t last-step)
                                                     boids3d-step-ns))])
                             (when (> n 0)
                               (set! last-step
                                 (if (= n 3)
                                     t
                                     (+ last-step (* n boids3d-step-ns))))
                               (when (eq? (window-ref win 'ride) 'frames)
                                 (do ([i 0 (+ i 1)]) ((= i n))
                                   (boids3d-step! win)))
                               ;; the camera goes slowly round, unless held:
                               ;; by the steps, so by time
                               (unless drag
                                 (window-set! win 'yaw
                                              (+ (window-ref win 'yaw)
                                                 (* n 0.0015))))
                               (invalidate! win)))))
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
                                (max -1.4 (min 1.4 (+ (cadddr drag)
                                                      (* 0.01 (- y (cadr
                                                                    drag)))))))
                              (invalidate! win)))
              'mouse-up (lambda (win x y button) (set! drag #f))
              'close (lambda (win)
                       (set! closed? #t)
                       (when (eq? *boids3d-flock* win)
                         (set! *boids3d-flock* #f))
                       (when rules-win (close-window! rules-win))
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
      win)))

;;; ------------------------------------------------------------------
;;; the rules window
;;; Boids' (apps/boids.ss), but for the threads: a slider for the count and
;;; each rule, and the keys' buttons. It reads and sets the flock window's
;;; properties, so it shows them as they are, whoever changed them.

(define (boids3d-setting-label key)
  (list->string (map (lambda (c) (if (char=? c #\-) #\space c))
                     (string->list (symbol->string key)))))

(define (boids3d-weight? range) (pair? (cdddr range)))

;; Where v sits on range's slider, from 0 to 1, and back; a weight's slider
;; is a cube, as Boids' is.
(define (boids3d-slider-t range v)
  (let ([t (/ (- v (cadr range)) (- (caddr range) (cadr range)))])
    (if (boids3d-weight? range) (expt (max t 0.0) 1/3) t)))

(define (boids3d-slider-value range t)
  (+ (cadr range)
     (* (- (caddr range) (cadr range))
        (if (boids3d-weight? range) (* t t t) t))))

(define (boids3d-readout range v)
  (case (car range)
    [(min-speed max-speed) (format "~,1f" v)]
    [(view-angle blocker-cone) (format "~a°" (exact (round v)))]
    [else (if (boids3d-weight? range)
              (format "~,4f" v)
              (format "~a" (exact (round v))))]))

(define (boids3d-label-width)
  (+ 12 (text-widest (cons "birds"
                           (map (lambda (r) (boids3d-setting-label (car r)))
                                boids3d-ranges))
                     'ui)))

(define (boids3d-readout-width) (+ 12 (text-widest '("0.0000" "4096") 'ui)))

(define boids3d-buttons
  '("Randomize (R)"
    "Defaults (D)"
    "Scatter (S)"))

(define boids3d-ride-label "Fly on while hidden: steps on a timer, not frames")

;; The newest flock's window, while it's open: what boids3d-ride! takes
;; with none given.
(defvar *boids3d-flock* #f)

;; Whether the flock in win steps with its frames, pausing while it's unseen
;; (frames, the default), or on a timer, flying on while hidden (timer):
;; (boids3d-ride! 'timer) at a REPL in Boids 3D's environment.
(define (boids3d-ride! mode . win)
  (let ([win (if (pair? win) (car win) *boids3d-flock*)])
    (unless (memq mode '(frames timer))
      (errorf 'boids3d-ride! "frames or timer, not ~s" mode))
    (unless win (errorf 'boids3d-ride! "no Boids 3D window is open"))
    (window-set! win 'ride mode)
    (window-frame-soon! win)))

(define (boids3d-button-width)
  (apply max (map (lambda (label)
                    (let-values ([(w h) (ui-button-size label #f)]) w))
                  boids3d-buttons)))

;; The rules window's content size: room for its rows, sliders 140 wide,
;; three buttons as wide as the widest label, and the timer's checkbox.
(define (boids3d-rules-size)
  (let ([pad (ui-pad)] [gap (ui-gap)] [sh (ui-slider-height)])
    (values (+ pad pad
               (max (+ (boids3d-label-width) 140 (boids3d-readout-width))
                    (+ (* 3 (boids3d-button-width)) (* 2 gap))
                    (let-values ([(cw ch) (ui-checkbox-size
                                           boids3d-ride-label)])
                      cw)))
            (+ pad (+ sh gap) (+ (ui-control-height) gap)
               (+ (ui-control-height) (* 3 gap))
               (* (length boids3d-ranges) (+ sh gap))
               gap (font-line-height 'ui-small) pad))))

;; The rows, top to bottom: the count, the buttons, whether it rides a timer,
;; a slider for each rule, and a hint.
(define (boids3d-draw-rules ui flock-win w)
  (let* ([pad (ui-pad)] [gap (ui-gap)] [sh (ui-slider-height)]
         [lw (boids3d-label-width)] [rw (boids3d-readout-width)]
         [rules (window-ref flock-win 'rules)]
         [n (window-ref flock-win 'count)])
    (define (row y id label t readout set)
      (ui-draw-label pad y lw sh '(dim) label)
      (ui-slider ui id (+ pad lw) y (- w pad lw rw pad) t 0.0 1.0 set)
      (ui-draw-label (- w pad rw) y rw sh '(right) readout)
      (+ y sh gap))
    (let* ([y (row pad 'count "birds"
                   (/ (- n 10) (- boids3d-most 10.0))
                   (number->string n)
                   (lambda (t)
                     (boids3d-resize! flock-win
                       (exact (round (+ 10 (* t (- boids3d-most 10))))))))]
           [y (let ([bw (/ (- w pad pad gap gap) 3)] [ch (ui-control-height)])
                (for-each (lambda (i label id act!)
                            (ui-button ui id (+ pad (* i (+ bw gap))) y bw ch
                                       label (lambda () (act! flock-win))))
                          '(0 1 2) boids3d-buttons '(randomize defaults scatter)
                          (list boids3d-randomize! boids3d-defaults!
                                boids3d-scatter!))
                (+ y ch gap))]
           [y (let ([ch (ui-control-height)])
                (ui-checkbox ui 'ride pad y (- w pad pad) ch boids3d-ride-label
                             (eq? (window-ref flock-win 'ride) 'timer)
                             (lambda (on?)
                               (boids3d-ride! (if on? 'timer 'frames)
                                              flock-win)))
                (+ y ch (* 3 gap)))]
           [y (fold-left
               (lambda (y range)
                 (let* ([key (car range)] [v (boids3d-rule rules key)])
                   (row y key (boids3d-setting-label key)
                        (boids3d-slider-t range v) (boids3d-readout range v)
                        (lambda (t)
                          (window-set! flock-win 'rules
                            (boids3d-set-rule (window-ref flock-win 'rules)
                                              key
                                              (boids3d-slider-value range
                                                                    t)))))))
               y boids3d-ranges)])
      (ui-draw-label pad (+ y gap) (- w pad pad) (font-line-height 'ui-small)
                     '(hint) "h hides this window · space pauses")
      (+ y gap (font-line-height 'ui-small) pad))))

;; Opens the rules window for the flock in flock-win, beside it; on-close is
;; called when it closes. Its keys are the flock's.
(define (boids3d-open-rules flock-win on-close)
  (let ([ui (make-ui)]
        [shown #f])   ; the rules and the count it last drew
    (define (now-shown)
      (list (window-ref flock-win 'rules) (window-ref flock-win 'count)
            (window-ref flock-win 'ride)))
    (let-values ([(w h) (boids3d-rules-size)])
      (let ([win
             (apply open-window "Boids 3D — Rules"
                    'size (cons w h)
                    'pos (cons (+ (window-x flock-win) (window-w flock-win) 12)
                               (window-y flock-win))
                    'app #f
                    'draw (lambda (win w h)
                            (set! shown (now-shown))
                            (ui-begin! ui)
                            (ui-draw-surface 0 0 w h '(page))
                            (boids3d-draw-rules ui flock-win w)
                            (ui-end! ui w h))
                    'close (lambda (win) (on-close))
                    (append
                     (ui-handlers ui 'key (lambda (win key mods)
                                            (window-call flock-win 'key key
                                                         mods)
                                            #t))
                     (list 'open (lambda (win) (window-frame-soon! win))
                           'frame (lambda (win t)
                                   (window-frame-soon! win)
                                   (ui-frame ui win)
                                   (let-values ([(w h) (boids3d-rules-size)])
                                     (boids3d-grow-to! win w h))
                                   (unless (equal? shown (now-shown))
                                     (invalidate! win))))))])
        (boids3d-keep-on-desktop! win)
        win))))

;; Grows win's content to at least w × h, kept on the desktop; never shrinks.
(define (boids3d-grow-to! win w h)
  (let-values ([(cw ch) (window-content-size win)])
    (when (and (or (> w cw) (> h ch)) (not (shaded? win)))
      (resize-window! win (max w cw) (max h ch))
      (boids3d-keep-on-desktop! win))))

;; Moves win left or up as far as it takes to stay on the desktop.
(define (boids3d-keep-on-desktop! win)
  (let-values ([(dx dy dw dh) (desktop-rect)])
    (move-window! win
      (max dx (min (window-x win) (- (+ dx dw) (window-w win))))
      (max dy (min (window-y win) (- (+ dy dh) (window-h win)))))))
