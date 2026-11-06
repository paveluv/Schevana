;;; apps/boids.ss — Boids, Craig Reynolds' flocking simulation (1987).
;;; Ported from Boids in Niva (github.com/dharmatech/boids-niva), which was
;;; in turn inspired by Boids in Aloe, a Lisp whose kernel is sending a
;;; message (github.com/dharmatech/2026-09-02-aloe-racket).
;;;
;;; Besides Reynolds' three rules (cohesion, alignment, separation), two
;;; react to blockers, boids close and straight ahead: clear view steps
;;; aside, back off steps away. They come from Gary William Flake's "The
;;; Computational Beauty of Nature" (MIT Press, 1998), written from his
;;; description, not copied from his (GPL) source.
;;;
;;; The simulation is pure: a flock is an flvector, four numbers a boid
;;; (where it is, where it's heading), and a step makes a new one, on the
;;; crew when the flock is big enough. The window keeps the flock and its
;;; rules, as plain data:
;;; (boid-x (window-ref win 'flock) 0)
;;; (window-set! win 'rules (boids-random-rules))
;;; R: random rules · D: the defaults · S: scatter · Space: pause
;;; H: the rules window, beside the flock (it closes with the flock)
;;;
;;; It runs in a sandbox (services/grant.ss), where the names above are: a
;;; REPL in /apps/boids has them.

(app-requests window draw ui timers crew)

;;; ------------------------------------------------------------------ boids

(define (boids-size flock) (quotient (flvector-length flock) 4))

(define (boid-x flock i) (flvector-ref flock (* 4 i)))
(define (boid-y flock i) (flvector-ref flock (+ 1 (* 4 i))))
(define (boid-vx flock i) (flvector-ref flock (+ 2 (* 4 i))))
(define (boid-vy flock i) (flvector-ref flock (+ 3 (* 4 i))))

;;; ------------------------------------------------------------------ rules

;; The flocking rules, as a plist. Each rule has a weight (how hard it
;; steers) and a radius (how far a boid looks for it). view-angle is the
;; field of view in degrees, centered on the heading: 180 sees only
;; ahead, 360 all around. Blockers are boids closer than blocker-radius
;; inside a cone straight ahead, blocker-cone degrees wide.
;;
;; The speed limits belong to the screen, not the sim (boids-step leaves
;; them out). With view-angle 180, cohesion pulls stragglers forward and
;; nothing pulls the leaders back, so speed grows without bound: classic
;; boids cap it. Back off, unchecked, brakes boids almost to a standstill:
;; Flake's boids keep a minimum speed.
;;
;; These are the original settings: see only ahead, barely any
;; separation, and the blocker rules off (their radius and cone are
;; Flake's).
(define boids-default-rules
  '(cohesion 0.01
    cohesion-radius 50.0
    alignment 0.05
    alignment-radius 50.0
    separation 0.001
    separation-radius 5.0
    view-angle 180.0
    clear-view 0.0
    back-off 0.0
    blocker-radius 40.0
    blocker-cone 90.0
    min-speed 1.0
    max-speed 4.0))

(define (boids-rule rules key)
  (let ([at (memq key rules)])
    (if at (cadr at) (errorf 'boids-rule "no rule ~s" key))))

;; Each rule's range, in the order the rules window shows them. A weight
;; starts at 0, and its useful values span orders of magnitude.
(define boids-ranges
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
    (min-speed 0.0 5.0)
    (max-speed 0.5 10.0)))

;; Rules picked at random within their ranges. A weight is picked on a
;; cube, so that small ones come up about as often as they would on a
;; log scale. Max speed comes after min speed and is picked from it up,
;; so the two never cross.
(define (boids-random-rules)
  (fold-left
   (lambda (rules range)
     (apply (lambda (key lo hi . weight)
              (let* ([lo (if (eq? key 'max-speed)
                             (max lo (boids-rule rules 'min-speed))
                             lo)]
                     [r (random 1.0)]
                     [t (if (null? weight) r (* r r r))])
                (append rules (list key (+ lo (* t (- hi lo)))))))
            range))
   '() boids-ranges))

;; Rules with key's value v, the others as they were. Min and max speed
;; can't cross: setting one past the other pushes the other along.
(define (boids-set-rule rules key v)
  (define (with rules key v)
    (cond [(null? rules) (errorf 'boids-set-rule "no rule ~s" key)]
          [(eq? (car rules) key) (cons* key v (cddr rules))]
          [else (cons* (car rules) (cadr rules) (with (cddr rules) key v))]))
  (let ([rules (with rules key v)])
    (case key
      [(min-speed) (if (> v (boids-rule rules 'max-speed))
                       (with rules 'max-speed v)
                       rules)]
      [(max-speed) (if (< v (boids-rule rules 'min-speed))
                       (with rules 'min-speed v)
                       rules)]
      [else rules])))

;;; ------------------------------------------------------------------ flocks

;; The rules as a step reads them, worked out once: each rule's weight and
;; reach, the squared radius, 0 for a rule without weight, so that nothing
;; is in reach; the cosines of half a field of view and of half the
;; blockers' cone, which is in view too: a boid can't react to what it
;; can't see (all around, -inf: any heading beats it); and the longest
;; reach.
(define (boids-steering rules)
  (define (rule key) (inexact (boids-rule rules key)))
  (define (reach weight radius)
    (if (= (rule weight) 0.0) 0.0 (* (rule radius) (rule radius))))
  (define (half-cosine angle)
    (if (>= angle 360.0) -inf.0 (cos (/ (* (/ angle 2.0) pi) 180.0))))
  (let ([reaches (list (reach 'cohesion 'cohesion-radius)
                       (reach 'alignment 'alignment-radius)
                       (reach 'separation 'separation-radius)
                       (reach 'clear-view 'blocker-radius)
                       (reach 'back-off 'blocker-radius))]
        [fov (rule 'view-angle)])
    (apply flvector
           (rule 'cohesion)
           (rule 'alignment)
           (rule 'separation)
           (rule 'clear-view)
           (rule 'back-off)
           (half-cosine fov)
           (half-cosine (min (rule 'blocker-cone) fov))
           (apply max reaches)
           reaches)))

;; Boids [lo, hi) of flock steered into next, each by everyone's current
;; state: its velocity plus each rule's push times its weight, and its
;; position moved by that. Every pair of boids is looked at, so the loop
;; over them keeps its flonums unboxed: nothing crosses a call or sits in
;; a variable a loop closes over, and what adds up lives in sums, the one
;; thing a call allocates.
(define-worklet (boids-steer! lo hi flock next rules)
  (define n (fxquotient (flvector-length flock) 4))
  (define sums (make-flvector 12 0.0))
  (define-syntax add!
    (syntax-rules ()
      [(_ k v) (flvector-set! sums k (fl+ (flvector-ref sums k) v))]))
  (define-syntax sum (syntax-rules () [(_ k) (flvector-ref sums k)]))
  (define-syntax rule (syntax-rules () [(_ k) (flvector-ref rules k)]))
  ;; toward the mean of what is summed at k and k+1, over the count at c
  (define-syntax toward
    (syntax-rules ()
      [(_ k c own weight)
       (if (fl> (sum c) 0.0)
           (fl* (fl- (fl/ (sum k) (sum c)) own) (rule weight))
           0.0)]))
  (do ([i lo (fx+ i 1)]) ((fx= i hi))
    (flvector-fill! sums 0.0)
    (let ([at (fx* 4 i)])
      (do ([j 0 (fx+ j 1)]) ((fx= j n))
        (let* ([o (fx* 4 j)]
               [dx (fl- (flvector-ref flock o) (flvector-ref flock at))]
               [dy (fl- (flvector-ref flock (fx+ o 1))
                        (flvector-ref flock (fx+ at 1)))]
               [d2 (fl+ (fl* dx dx) (fl* dy dy))])
          ;; not itself, and in somebody's reach: most pairs stop here
          (when (and (fl> d2 0.0) (fl< d2 (rule 7)))
            (let* ([vx (flvector-ref flock (fx+ at 2))]
                   [vy (flvector-ref flock (fx+ at 3))]
                   [h2 (fl+ (fl* vx vx) (fl* vy vy))]
                   [ahead (fl+ (fl* vx dx) (fl* vy dy))]
                   [lengths (flsqrt (fl* h2 d2))]
                   [away-x (fl- 0.0 dx)]
                   [away-y (fl- 0.0 dy)])
              ;; in the field of view whose half-cosine is rule k: a boid
              ;; standing still sees everything
              (let-syntax ([sees? (syntax-rules ()
                                    [(_ k)
                                     (or (fl= h2 0.0)
                                         (fl> ahead (fl* (rule k) lengths)))])])
                ;; toward the center of the neighbors
                (when (and (fl< d2 (rule 8)) (sees? 5))
                  (add! 0 (flvector-ref flock o))
                  (add! 1 (flvector-ref flock (fx+ o 1)))
                  (add! 2 1.0))
                ;; toward their average velocity
                (when (and (fl< d2 (rule 9)) (sees? 5))
                  (add! 3 (flvector-ref flock (fx+ o 2)))
                  (add! 4 (flvector-ref flock (fx+ o 3)))
                  (add! 5 1.0))
                ;; away from every boid this close, seen or not: you feel
                ;; a bump from behind
                (when (fl< d2 (rule 10))
                  (add! 6 away-x)
                  (add! 7 away-y))
                ;; a unit step sideways out from behind each blocker:
                ;; square to the line between them, on the side it heads
                (when (and (fl< d2 (rule 11)) (sees? 6))
                  (let* ([turn-x (fl- 0.0 away-y)]
                         [side (if (fl< (fl+ (fl* vx turn-x) (fl* vy away-x))
                                        0.0)
                                   -1.0
                                   1.0)]
                         [d (flsqrt d2)])
                    (add! 8 (fl/ (fl* turn-x side) d))
                    (add! 9 (fl/ (fl* away-x side) d))))
                ;; a unit step straight away from each blocker
                (when (and (fl< d2 (rule 12)) (sees? 6))
                  (let ([d (flsqrt d2)])
                    (add! 10 (fl/ away-x d))
                    (add! 11 (fl/ away-y d)))))))))
      (let* ([x (flvector-ref flock at)]
             [y (flvector-ref flock (fx+ at 1))]
             [vx (flvector-ref flock (fx+ at 2))]
             [vy (flvector-ref flock (fx+ at 3))]
             [nvx (fl+ (fl+ (fl+ (fl+ (fl+ vx (toward 0 2 x 0))
                                      (toward 3 5 vx 1))
                                 (fl* (sum 6) (rule 2)))
                            (fl* (sum 8) (rule 3)))
                       (fl* (sum 10) (rule 4)))]
             [nvy (fl+ (fl+ (fl+ (fl+ (fl+ vy (toward 1 2 y 0))
                                      (toward 4 5 vy 1))
                                 (fl* (sum 7) (rule 2)))
                            (fl* (sum 9) (rule 3)))
                       (fl* (sum 11) (rule 4)))])
        (flvector-set! next at (fl+ x nvx))
        (flvector-set! next (fx+ at 1) (fl+ y nvy))
        (flvector-set! next (fx+ at 2) nvx)
        (flvector-set! next (fx+ at 3) nvy)))))

;; Boids a call of the crew: at least this many pairs, about 80 µs. So a
;; small flock runs on the caller alone, where waking the crew would cost
;; more than it gives.
(define boids-chunk-pairs 24000)

(define (boids-chunk n) (max 1 (quotient boids-chunk-pairs (max n 1))))

;; The next flock: every boid steered by the same current state.
(define (boids-step flock rules)
  (let ([next (make-flvector (flvector-length flock))]
        [n (boids-size flock)])
    (crew-for* (boids-chunk n) 0 n boids-steer! flock next
               (boids-steering rules))
    next))

;; Three boids close together, for the tests and the REPL:
;; (boids-step boids-demo boids-default-rules)
(define boids-demo
  (flvector 0.0 0.0 1.0 0.0
            1.0 1.0 0.0 1.0
            2.0 0.0 1.0 1.0))

;;; ------------------------------------------------------------------ screen

;; Leaving one edge of a w × h screen brings a boid back on the opposite
;; edge, and its speed stays within the limits; standing still, it has no
;; heading, so it stays put.
(define (boids-keep-on-screen! flock lo hi w h)
  (do ([at 0 (fx+ at 4)]) ((fx= at (flvector-length flock)))
    (flvector-set! flock at (flmod (flvector-ref flock at) w))
    (flvector-set! flock (fx+ at 1) (flmod (flvector-ref flock (fx+ at 1)) h))
    (let* ([vx (flvector-ref flock (fx+ at 2))]
           [vy (flvector-ref flock (fx+ at 3))]
           [s2 (fl+ (fl* vx vx) (fl* vy vy))])
      (when (and (fl> s2 0.0) (fl< s2 (fl* lo lo)))
        (let ([k (fl/ lo (flsqrt s2))])
          (flvector-set! flock (fx+ at 2) (fl* vx k))
          (flvector-set! flock (fx+ at 3) (fl* vy k)))))
    (let* ([vx (flvector-ref flock (fx+ at 2))]
           [vy (flvector-ref flock (fx+ at 3))]
           [s2 (fl+ (fl* vx vx) (fl* vy vy))])
      (when (fl> s2 (fl* hi hi))
        (let ([k (fl/ hi (flsqrt s2))])
          (flvector-set! flock (fx+ at 2) (fl* vx k))
          (flvector-set! flock (fx+ at 3) (fl* vy k)))))))

;; One frame on a w × h screen: a sim step, then the speed limits and
;; the wrap.
(define (boids-step-on flock rules w h)
  (let ([next (boids-step flock rules)])
    (boids-keep-on-screen! next
                           (inexact (boids-rule rules 'min-speed))
                           (inexact (boids-rule rules 'max-speed))
                           (inexact w)
                           (inexact h))
    next))

;; n boids scattered over a w × h screen, moving in random directions.
(define (boids-scatter n w h)
  (let ([flock (make-flvector (* 4 n))] [w (inexact w)] [h (inexact h)])
    (do ([at 0 (+ at 4)]) ((= at (* 4 n)) flock)
      (flvector-set! flock at (random w))
      (flvector-set! flock (+ at 1) (random h))
      (flvector-set! flock (+ at 2) (- (random 4.0) 2.0))
      (flvector-set! flock (+ at 3) (- (random 4.0) 2.0)))))

;; n boids: the first n of flock, or all of it and random newcomers.
(define (boids-resize flock n w h)
  (if (= n (boids-size flock))
      flock
      (let ([next (boids-scatter n w h)])
        (do ([i 0 (+ i 1)])
            ((= i (* 4 (min n (boids-size flock)))) next)
          (flvector-set! next i (flvector-ref flock i))))))

;;; ------------------------------------------------------------------ the app

;; How often the flock steps, in ms: about 60 times a second, however
;; often the window ticks.
(define boids-step-ms 15)

(define boids-count 150)   ; how many a new window starts with

(define (boids-bar-height) (max 26 (round (+ (font-line-height 'ui-small) 13))))

;; The status line under the flock.
(define (boids-status-text n step-ms running?)
  (format "~a boids   ~a   r random · d defaults · s scatter · h rules · \
           space pause"
          n (if running? (format "~,1f ms a step" step-ms) "paused")))

;; The flock's field in win: its content above the status line.
(define (boids-field-size win)
  (let-values ([(w h) (window-content-size win)])
    (values w (max 1 (- h (boids-bar-height))))))

;; What the keys and the rules window's buttons do to the flock in win.
(define (boids-randomize! win) (window-set! win 'rules (boids-random-rules)))
(define (boids-defaults! win) (window-set! win 'rules boids-default-rules))

(define (boids-scatter! win)
  (let-values ([(w h) (boids-field-size win)])
    (window-set! win 'flock
      (boids-scatter (boids-size (window-ref win 'flock)) w h))))

(define (boids-resize! win n)
  (let-values ([(w h) (boids-field-size win)])
    (window-set! win 'flock (boids-resize (window-ref win 'flock) n w h))))

;; A dot, with a line toward where it's heading.
(define (draw-boid flock i)
  (let ([x (boid-x flock i)] [y (boid-y flock i)])
    (draw-line x y
               (+ x (* (boid-vx flock i) 4.0))
               (+ y (* (boid-vy flock i) 4.0))
               'red 2)
    (fill-circle x y 3 'yellow)))

(define-app (boids) "Boids"
  (let ([w 760] [h 520]
        [running? #t] [last-step 0]
        [step-ms 0.0]      ; a step's time, smoothed
        [rules-win #f])    ; the rules window, while it is open
    (define (step! win)
      (let-values ([(w h) (boids-field-size win)])
        (let ([t0 (now-ns)])
          (window-set! win 'flock
            (boids-step-on (window-ref win 'flock) (window-ref win 'rules)
                           w h))
          ;; one step's time jumps around (collections): over about 20
          (set! step-ms (+ (* step-ms 0.95)
                           (* (/ (- (now-ns) t0) 1e6) 0.05))))))
    (define (toggle-rules! win)
      (if rules-win
          (close-window! rules-win)
          (set! rules-win
                (boids-open-rules win (lambda () (set! rules-win #f))))))
    (let ([win
           (open-window "Boids"
             'size (cons w (+ h (boids-bar-height)))
             'flock (boids-scatter boids-count w h)
             'rules boids-default-rules
             'tick (lambda (win)
                     (when (and running?
                                (>= (- (now-ms) last-step) boids-step-ms))
                       (set! last-step (now-ms))
                       (step! win)))
             'draw (lambda (win w h)
                     (let ([bar (boids-bar-height)]
                           [flock (window-ref win 'flock)])
                       (fill-rect 0 0 w (- h bar) 'bg-0)
                       (do ([i 0 (+ i 1)]) ((= i (boids-size flock)))
                         (draw-boid flock i))
                       (fill-rect 0 (- h bar) w bar 'bg-1)
                       (draw-text 10 (+ (- h bar) 5)
                                  (boids-status-text (boids-size flock) step-ms
                                                     running?)
                                  'text-faint 'ui-small)))
             'key (lambda (win key mods)
                    (case key
                      [(#\r) (boids-randomize! win)]
                      [(#\d) (boids-defaults! win)]
                      [(#\s) (boids-scatter! win)]
                      [(#\h) (toggle-rules! win)]
                      [(#\space) (set! running? (not running?))])
                    (invalidate! win))
             'close (lambda (win) (when rules-win (close-window! rules-win))))])
      ;; the rules show at first, as Niva's panel does. Moved to fit on
      ;; the desktop, they'd cover the flock: it moves left to clear them.
      (toggle-rules! win)
      (let-values ([(dx dy dw dh) (desktop-rect)])
        (let ([short (- (+ (window-x win) (window-w win) 12)
                        (window-x rules-win))])
          (when (> short 0)
            (move-window! win (max dx (- (window-x win) short))
                          (window-y win)))))
      (focus-window! win)   ; the flock has the keyboard
      win)))

;;; ------------------------------------------------------------------
;;; the rules window
;;; A slider for the count and for each rule, and the keys' buttons. It
;;; reads and sets the flock window's properties, so it shows them as they
;;; are, whoever changed them: a key, a button or the REPL.

;; A step's cost grows as the count squared, a frame's as the count. At
;; 2,000, measured here, a step takes 1.6 ms on the crew of 8 with the
;; default rules and 2.7 with the heaviest (both blocker rules, 360°, radii
;; of 200), a frame 9: well inside a 60 Hz frame. On a thread alone the
;; heaviest takes 23 ms, about two frames. Past this the drawing, one line
;; and one circle a boid on the main thread, is what fills the frame.
(define boids-max-count 2000)

;; A rule's name as its row shows it: cohesion-radius as cohesion radius.
(define (boids-setting-label key)
  (list->string (map (lambda (c) (if (char=? c #\-) #\space c))
                     (string->list (symbol->string key)))))

(define (boids-weight? range) (pair? (cdddr range)))

;; Where v sits on range's slider, from 0 to 1, and back. A weight's
;; slider is a cube: its middle is an eighth of its top, so the small
;; weights that matter get most of it, as on Niva's log slider.
(define (boids-slider-t range v)
  (let ([t (/ (- v (cadr range)) (- (caddr range) (cadr range)))])
    (if (boids-weight? range) (expt (max t 0.0) 1/3) t)))

(define (boids-slider-value range t)
  (+ (cadr range)
     (* (- (caddr range) (cadr range))
        (if (boids-weight? range) (* t t t) t))))

;; A rule's value as its row shows it.
(define (boids-readout range v)
  (case (car range)
    [(min-speed max-speed) (format "~,1f" v)]
    [(view-angle blocker-cone) (format "~a°" (exact (round v)))]
    [else (if (boids-weight? range)
              (format "~,4f" v)
              (format "~a" (exact (round v))))]))

(define (boids-label-width)
  (+ 12 (text-widest (cons "boids"
                           (map (lambda (r) (boids-setting-label (car r)))
                                boids-ranges))
                     'ui)))

(define (boids-readout-width) (+ 12 (text-width "0.0000" 'ui)))

(define boids-buttons
  '("Randomize (R)"
    "Defaults (D)"
    "Scatter (S)"))

;; As wide as the widest label's button, in the style's own.
(define (boids-button-width)
  (apply max (map (lambda (label)
                    (let-values ([(w h) (ui-button-size label #f)]) w))
                  boids-buttons)))

;; The rules window's content size: room for its rows (as
;; boids-draw-rules lays them out), with sliders 140 wide, and for three
;; buttons as wide as the widest label.
(define (boids-rules-size)
  (let ([pad (ui-pad)] [gap (ui-gap)] [sh (ui-slider-height)])
    (values (+ pad pad
               (max (+ (boids-label-width) 140 (boids-readout-width))
                    (+ (* 3 (boids-button-width)) (* 2 gap))))
            (+ pad (+ sh gap) (+ (ui-control-height) (* 3 gap))
               (* (length boids-ranges) (+ sh gap))
               gap (font-line-height 'ui-small) pad))))

;; The rows, top to bottom: the count, the buttons, a slider for each
;; rule, and a hint. Returns the y below them.
(define (boids-draw-rules ui flock-win w)
  (let* ([pad (ui-pad)] [gap (ui-gap)] [sh (ui-slider-height)]
         [lw (boids-label-width)] [rw (boids-readout-width)]
         [rules (window-ref flock-win 'rules)]
         [n (boids-size (window-ref flock-win 'flock))])
    (define (row y id label t readout set)
      (ui-draw-label pad y lw sh '(dim) label)
      (ui-slider ui id (+ pad lw) y (- w pad lw rw pad) t 0.0 1.0 set)
      (ui-draw-label (- w pad rw) y rw sh '(right) readout)
      (+ y sh gap))
    (let* ([y (row pad 'count "boids"
                   (/ (- n 10) (- boids-max-count 10.0))
                   (number->string n)
                   (lambda (t)
                     (boids-resize! flock-win
                       (exact (round (+ 10 (* t (- boids-max-count 10))))))))]
           [y (let ([bw (/ (- w pad pad gap gap) 3)] [ch (ui-control-height)])
                (for-each (lambda (i label id act!)
                            (ui-button ui id (+ pad (* i (+ bw gap))) y bw ch
                                       label (lambda () (act! flock-win))))
                          '(0 1 2) boids-buttons '(randomize defaults scatter)
                          (list boids-randomize! boids-defaults!
                                boids-scatter!))
                (+ y ch (* 3 gap)))]
           [y (fold-left
               (lambda (y range)
                 (let* ([key (car range)] [v (boids-rule rules key)])
                   (row y key (boids-setting-label key)
                        (boids-slider-t range v) (boids-readout range v)
                        ;; the rules as they are then, not as drawn
                        (lambda (t)
                          (window-set! flock-win 'rules
                            (boids-set-rule (window-ref flock-win 'rules) key
                                            (boids-slider-value range t)))))))
               y boids-ranges)])
      (ui-draw-label pad (+ y gap) (- w pad pad) (font-line-height 'ui-small)
                     '(hint) "h hides this window · space pauses")
      (+ y gap (font-line-height 'ui-small) pad))))

;; Opens the rules window for the flock in flock-win, beside it, and
;; returns it; on-close is called when it closes. Its keys are the
;; flock's.
(define (boids-open-rules flock-win on-close)
  (let ([ui (make-ui)]
        [shown #f])   ; the rules and the count it last drew
    (define (now-shown)
      (cons (window-ref flock-win 'rules)
            (boids-size (window-ref flock-win 'flock))))
    (let-values ([(w h) (boids-rules-size)])
      (let ([win
             (apply open-window "Boids — Rules"
                    'size (cons w h)
                    'pos (cons (+ (window-x flock-win) (window-w flock-win) 12)
                               (window-y flock-win))
                    'app #f
                    'draw (lambda (win w h)
                            (set! shown (now-shown))
                            (ui-begin! ui)
                            (ui-draw-surface 0 0 w h '(page))
                            (boids-draw-rules ui flock-win w)
                            (ui-end! ui w h))
                    'close (lambda (win) (on-close))
                    (append
                     (ui-handlers ui 'key (lambda (win key mods)
                                            (window-call flock-win 'key key
                                                         mods)
                                            #t))
                     ;; the kit's tick, then: a change from elsewhere shows,
                     ;; and fonts grown in Settings get room for the rows
                     (list 'tick (lambda (win)
                                   (ui-tick ui win)
                                   (let-values ([(w h) (boids-rules-size)])
                                     (boids-grow-to! win w h))
                                   (unless (equal? shown (now-shown))
                                     (invalidate! win))))))])
        (boids-keep-on-desktop! win)
        win))))

;; Grows win's content to at least w × h, moved left or up as far as it
;; takes to stay on the desktop. It never shrinks: a size set by hand
;; holds.
(define (boids-grow-to! win w h)
  (let-values ([(cw ch) (window-content-size win)])
    (when (and (or (> w cw) (> h ch)) (not (shaded? win)))
      (resize-window! win (max w cw) (max h ch))
      (boids-keep-on-desktop! win))))

;; Moves win left or up as far as it takes to stay on the desktop.
(define (boids-keep-on-desktop! win)
  (let-values ([(dx dy dw dh) (desktop-rect)])
    (move-window! win
      (max dx (min (window-x win) (- (+ dx dw) (window-w win))))
      (max dy (min (window-y win) (- (+ dy dh) (window-h win)))))))
