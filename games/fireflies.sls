;;; (games fireflies) — Fireflies, a game on the core alone. At dusk
;;; over a meadow, a glass jar that follows the mouse (or the arrow keys)
;;; catches the fireflies that are lit; a dark one slips through, and a
;;; moth cracks the jar: three cracks and it breaks. Every ten fireflies
;;; is a level, with one more moth and all of them faster. The same game
;;; is an app in a window on the desktop, (import (games fireflies)) and
;;; (fireflies) at a REPL, and a surface that fills a screen of its own:
;;;
;;;   ./game-demo [--size WxH] [--fullscreen]  a screen its own
;;;   ./game-demo --headless                   a second played, read back,
;;;                                            told

(library (games fireflies)
  (export fireflies-main fireflies)
  (import (chezscheme)
          (schevana core))

  ;; The jar's radius, and how near a bug's middle comes to touch it.
  (define fireflies-jar-r 24)
  (define fireflies-reach 30)

  ;; The cracks a lost life leaves in the jar, from its middle.
  (define fireflies-cracks
    '(((-5 . -21) (1 . -9) (-4 . 1) (4 . 12))
      ((20 . -9) (9 . -3) (13 . 6) (3 . 15))
      ((-21 . 5) (-10 . 3) (-13 . 12) (-5 . 20))))

  ;; A game, which its window or its surface keeps: the field's size, the
  ;; jar and where it heads, the bugs, how it goes, and the seed its
  ;; random numbers come from, so that a seed plays the same game again.
  (define-record-type fireflies-state
    (nongenerative games-fireflies-state)
    (fields (mutable w) (mutable h)
            (mutable seed)
            (mutable x) (mutable y)       ; the jar
            (mutable tx) (mutable ty)     ; where it heads
            (mutable bugs)
            (mutable score) (mutable lives) (mutable level)
            (mutable clock)               ; seconds played
            (mutable hurt)                ; seconds left of a crack's shake
            (mutable banner)              ; seconds left of the level's name
            (mutable sparks)              ; ((x y . when) ...): catches
            (mutable last)                ; the last frame's t, or #f
            (mutable stars)               ; ((u v . phase) ...), the sky's
            small big))                   ; its fonts

  ;; A firefly or a moth: where it is and heads, how fast it flies, and
  ;; its phase, where a firefly is in its blinking (lit for lit seconds,
  ;; then dark for dark), which also sets how either wanders.
  (define-record-type fireflies-bug
    (nongenerative games-fireflies-bug)
    (fields moth?
            (mutable x) (mutable y) (mutable heading)
            speed
            (mutable phase)
            lit dark))

  ;;; ---------------------------------------------------------------- rules

  ;; The next of g's random numbers, in [lo, hi): Park and Miller's
  ;; generator, whose state is the seed. Each draw is sequenced (let*),
  ;; never an argument beside another, so a seed plays the same game
  ;; compiled or spliced.
  (define (fireflies-random! g lo hi)
    (let ([s (mod (* (fireflies-state-seed g) 48271) 2147483647)])
      (fireflies-state-seed-set! g s)
      (+ lo (* (- hi lo) (/ s 2147483647.0)))))

  ;; A seed from the clock, for a game that isn't checking itself.
  (define (fireflies-seed) (+ 1 (mod (now-ms) 2147483646)))

  (define (fireflies-distance x0 y0 x1 y1)
    (let ([dx (- x1 x0)] [dy (- y1 y0)])
      (sqrt (+ (* dx dx) (* dy dy)))))

  ;; How far bug b is from the jar's middle.
  (define (fireflies-from-jar g b)
    (fireflies-distance (fireflies-bug-x b) (fireflies-bug-y b)
                        (fireflies-state-x g) (fireflies-state-y g)))

  ;; Heading a from (x, y), turned toward (x1, y1) by at most most radians.
  (define (fireflies-turn a x y x1 y1 most)
    (let* ([d (- (atan (- y1 y) (- x1 x)) a)]
           [d (atan (sin d) (cos d))])
      (+ a (max (- most) (min most d)))))

  ;; Where the grass begins, on a field h high: the bugs keep above it.
  (define (fireflies-ground h) (- h (max 36 (* 0.11 h))))

  (define (fireflies-over? g) (<= (fireflies-state-lives g) 0))

  ;; How lit firefly b is now, 0 to 1: lit seconds, then dark seconds, by
  ;; its own phase, fading in and out over a fifth of a second.
  (define (fireflies-glow g b)
    (let* ([lit (fireflies-bug-lit b)]
           [s (mod (+ (fireflies-state-clock g) (fireflies-bug-phase b))
                   (+ lit (fireflies-bug-dark b)))])
      (if (< s lit) (min 1.0 (/ s 0.2) (/ (- lit s) 0.2)) 0.0)))

  ;; b somewhere new: a moth past the left or right edge, heading in; a
  ;; firefly in the sky, away from the jar, just going dark, so that it
  ;; shows itself by lighting up.
  (define (fireflies-place! g b)
    (let ([w (fireflies-state-w g)]
          [top (fireflies-ground (fireflies-state-h g))])
      (if (fireflies-bug-moth? b)
          (let* ([left? (< (fireflies-random! g 0 1) 0.5)]
                 [y (fireflies-random! g 40 (- top 40))]
                 [a (fireflies-random! g -0.5 0.5)])
            (fireflies-bug-x-set! b (if left? -20.0 (+ w 20.0)))
            (fireflies-bug-y-set! b y)
            (fireflies-bug-heading-set! b (+ a (if left? 0.0 pi))))
          (let loop ([tries 0])
            (let* ([x (fireflies-random! g 30 (- w 30))]
                   [y (fireflies-random! g 30 (- top 30))])
              (if (and (< tries 8)
                       (< (fireflies-distance x y (fireflies-state-x g)
                                              (fireflies-state-y g))
                          150))
                  (loop (+ tries 1))
                  (begin
                    (fireflies-bug-x-set! b x)
                    (fireflies-bug-y-set! b y)
                    (fireflies-bug-heading-set!
                     b (fireflies-random! g 0 (* 2 pi)))
                    (fireflies-bug-phase-set!
                     b (- (fireflies-bug-lit b)
                          (fireflies-state-clock g))))))))))

  ;; A new firefly or moth, placed.
  (define (fireflies-bug-new g moth?)
    (let* ([speed (if moth?
                      (fireflies-random! g 80 100)
                      (fireflies-random! g 38 62))]
           [phase (fireflies-random! g 0 6)]
           [lit (fireflies-random! g 1.4 2.4)]
           [dark (fireflies-random! g 1.0 2.2)]
           [b (make-fireflies-bug moth? 0.0 0.0 0.0 speed phase lit dark)])
      (fireflies-place! g b)
      b))

  (define (fireflies-add! g b)
    (fireflies-state-bugs-set! g (cons b (fireflies-state-bugs g))))

  ;; A new game on g's field: three lives, seven fireflies (some lit
  ;; already), two moths on their way in.
  (define (fireflies-restart! g)
    (fireflies-state-score-set! g 0)
    (fireflies-state-lives-set! g 3)
    (fireflies-state-level-set! g 1)
    (fireflies-state-hurt-set! g 0.0)
    (fireflies-state-banner-set! g 2.5)
    (fireflies-state-sparks-set! g '())
    (fireflies-state-bugs-set! g '())
    (do ([i 0 (+ i 1)]) ((= i 7))
      (let ([b (fireflies-bug-new g #f)])
        (fireflies-bug-phase-set! b (fireflies-random! g 0 4))
        (fireflies-add! g b)))
    (fireflies-add! g (fireflies-bug-new g #t))
    (fireflies-add! g (fireflies-bug-new g #t)))

  ;; A game on a field w × h, its random numbers from seed (1 to 2^31 - 2).
  (define (fireflies-new w h seed)
    (let* ([y (* 0.6 (fireflies-ground h))]
           [g (make-fireflies-state w h seed (/ w 2.0) y (/ w 2.0) y
                                    '() 0 3 1 0.0 0.0 0.0 '() #f '()
                                    (font "sans-serif" 16 'bold)
                                    (font "sans-serif" 34 'bold))])
      (do ([i 0 (+ i 1)]) ((= i 60))
        (let* ([u (fireflies-random! g 0 1)]
               [v (fireflies-random! g 0 0.75)]
               [p (fireflies-random! g 0 1)])
          (fireflies-state-stars-set!
           g (cons (cons* u v p) (fireflies-state-stars g)))))
      (fireflies-restart! g)
      g))

  ;; b flies dt seconds on, wandering in lazy curves; it turns back in
  ;; near an edge, and a moth turns a little toward the jar, the more the
  ;; fuller the jar is: moths come to light.
  (define (fireflies-fly! g b dt)
    (let* ([moth? (fireflies-bug-moth? b)]
           [t (fireflies-state-clock g)] [p (fireflies-bug-phase b)]
           [x (fireflies-bug-x b)] [y (fireflies-bug-y b)]
           [w (fireflies-state-w g)]
           [top (fireflies-ground (fireflies-state-h g))]
           [wander (if moth?
                       (+ (* 2.6 (sin (+ (* 2.3 t) (* 5 p))))
                          (fireflies-random! g -4 4))
                       (+ (* 1.3 (sin (+ (* 0.9 t) (* 7 p))))
                          (fireflies-random! g -1.5 1.5)))]
           [a (+ (fireflies-bug-heading b) (* dt wander))]
           [a (if (or (< x 50) (> x (- w 50)) (< y 50) (> y (- top 30)))
                  (fireflies-turn a x y (/ w 2) (/ top 2) (* 3.0 dt))
                  a)]
           [pull (+ 0.2 (* 0.12 (mod (fireflies-state-score g) 10)))]
           [a (if (and moth? (not (fireflies-over? g)))
                  (fireflies-turn a x y
                                  (fireflies-state-x g) (fireflies-state-y g)
                                  (* dt pull))
                  a)]
           [v (if moth?
                  (* (fireflies-bug-speed b)
                     (+ 1 (* 0.12 (- (fireflies-state-level g) 1))))
                  (fireflies-bug-speed b))])
      (fireflies-bug-heading-set! b a)
      (fireflies-bug-x-set! b (+ x (* v dt (cos a))))
      (fireflies-bug-y-set! b (+ y (* v dt (sin a))))))

  ;; The jar glides toward where it heads, a tenth of a second behind it
  ;; and at most so fast: glass has some weight.
  (define (fireflies-jar-step! g dt)
    (let* ([x (fireflies-state-x g)] [y (fireflies-state-y g)]
           [dx (- (fireflies-state-tx g) x)] [dy (- (fireflies-state-ty g) y)]
           [d (fireflies-distance 0 0 dx dy)]
           [step (min (* d (min 1.0 (* 10.0 dt))) (* 600.0 dt))])
      (when (> d 0.0)
        (fireflies-state-x-set! g (+ x (* step (/ dx d))))
        (fireflies-state-y-set! g (+ y (* step (/ dy d)))))))

  ;; Firefly b caught: a spark where it was, and it goes elsewhere; every
  ;; tenth is a level, with one more moth, up to ten.
  (define (fireflies-catch! g b)
    (let ([score (+ 1 (fireflies-state-score g))])
      (fireflies-state-score-set! g score)
      (fireflies-state-sparks-set!
       g (cons (cons* (fireflies-bug-x b) (fireflies-bug-y b)
                      (fireflies-state-clock g))
               (fireflies-state-sparks g)))
      (fireflies-place! g b)
      (when (zero? (mod score 10))
        (fireflies-state-level-set! g (+ 1 (fireflies-state-level g)))
        (fireflies-state-banner-set! g 2.0)
        (when (< (length (filter fireflies-bug-moth?
                                 (fireflies-state-bugs g)))
                 10)
          (fireflies-add! g (fireflies-bug-new g #t))))))

  ;; What the jar touches: a lit firefly is caught, a dark one slips
  ;; through; a moth cracks the jar, unless it still shakes from the last,
  ;; and flies off past an edge.
  (define (fireflies-touch! g)
    (for-each
     (lambda (b)
       (when (< (fireflies-from-jar g b) fireflies-reach)
         (cond
           [(not (fireflies-bug-moth? b))
            (when (> (fireflies-glow g b) 0.5) (fireflies-catch! g b))]
           [(zero? (fireflies-state-hurt g))
            (fireflies-state-lives-set! g (- (fireflies-state-lives g) 1))
            (fireflies-state-hurt-set! g 1.2)
            (fireflies-place! g b)])))
     (fireflies-state-bugs g)))

  ;; g, dt seconds on. A broken jar lies still while the bugs fly on.
  (define (fireflies-step! g dt)
    (let ([clock (+ (fireflies-state-clock g) dt)])
      (fireflies-state-clock-set! g clock)
      (fireflies-state-hurt-set! g (max 0.0 (- (fireflies-state-hurt g) dt)))
      (fireflies-state-banner-set!
       g (max 0.0 (- (fireflies-state-banner g) dt)))
      (fireflies-state-sparks-set!
       g (filter (lambda (s) (< (- clock (cddr s)) 0.6))
                 (fireflies-state-sparks g)))
      (for-each (lambda (b) (fireflies-fly! g b dt)) (fireflies-state-bugs g))
      (unless (fireflies-over? g)
        (fireflies-jar-step! g dt)
        (fireflies-touch! g))))

  ;; A frame at t, in nanoseconds: the game goes on by the time since the
  ;; last, at most a twentieth of a second, so that a pause doesn't leap.
  (define (fireflies-frame! g t)
    (let ([last (fireflies-state-last g)])
      (fireflies-state-last-set! g t)
      (when last
        (fireflies-step! g (min 0.05 (max 0.0 (/ (- t last) 1e9)))))))

  ;; g's field resized to w × h, the jar's aim kept on it.
  (define (fireflies-resize! g w h)
    (unless (and (= w (fireflies-state-w g)) (= h (fireflies-state-h g)))
      (fireflies-state-w-set! g w)
      (fireflies-state-h-set! g h)
      (fireflies-head! g (fireflies-state-tx g) (fireflies-state-ty g))))

  ;;; ---------------------------------------------------------------- input

  ;; Where the jar heads, kept on the field, its cork too.
  (define (fireflies-head! g x y)
    (let ([r fireflies-jar-r])
      (fireflies-state-tx-set! g (max r (min (- (fireflies-state-w g) r) x)))
      (fireflies-state-ty-set!
       g (max (+ r 8) (min (- (fireflies-state-h g) r) y)))))

  ;; A click heads the jar there, or starts a new game once it's broken.
  (define (fireflies-click! g x y)
    (if (fireflies-over? g) (fireflies-restart! g) (fireflies-head! g x y)))

  ;; An arrow heads the jar a step its way, a step a key's repeat; space
  ;; or Return starts a new game once the jar is broken.
  (define (fireflies-key! g key)
    (let ([step (lambda (dx dy)
                  (fireflies-head! g (+ (fireflies-state-x g) (* 60 dx))
                                   (+ (fireflies-state-y g) (* 60 dy))))])
      (case key
        [(left) (step -1 0)]
        [(right) (step 1 0)]
        [(up) (step 0 -1)]
        [(down) (step 0 1)]
        [(#\space return) (when (fireflies-over? g) (fireflies-restart! g))])))

  ;;; ---------------------------------------------------------------- drawing

  ;; The dusk: the sky's gradient down to the grass, twinkling stars, a
  ;; crescent moon (a disc, cut by one of the sky's own), far hills.
  (define (fireflies-draw-sky g w h)
    (let* ([top (fireflies-ground h)] [t (fireflies-state-clock g)]
           [sky (linear-gradient 0 0 0 top
                                 #x050920 #x121845 #x352a5e #x7a4566)]
           [mx (* 0.8 w)] [my (* 0.14 h)])
      (fill-box 0 0 w h sky)
      (for-each (lambda (s)
                  (let ([twinkle (sin (+ (* 1.7 t) (* 20 (cddr s))))])
                    (fill-circle (* w (car s)) (* top (cadr s))
                                 (if (> (cddr s) 0.8) 1.5 1.0)
                                 (alpha #xfff4d8 (+ 0.45 (* 0.35 twinkle))))))
                (fireflies-state-stars g))
      (fill-circle mx my 20 #xf6eccc)
      (fill-circle (+ mx 8) (- my 5) 18 sky)
      (fill-circle mx my 80 (radial-gradient mx my 80 (alpha #xf6eccc 0.14)
                                             (alpha #xf6eccc 0)))
      (fill-polygon
       (let loop ([i 16] [points (list (cons 0 h) (cons w h))])
         (if (< i 0)
             points
             (let ([u (/ i 16.0)])
               (loop (- i 1)
                     (cons (cons (* u w)
                                 (- top 22 (* 14 (sin (+ (* 7 u) 1)))
                                    (* 9 (sin (* 17 u)))))
                           points)))))
       #x1a1636)))

  ;; The meadow: dark ground, and blades of grass that sway.
  (define (fireflies-draw-grass g w h)
    (let ([top (fireflies-ground h)] [t (fireflies-state-clock g)])
      (fill-box 0 top w (- h top) (linear-gradient 0 top 0 h #x0d2018 #x050d0a))
      (do ([i 0 (+ i 1)]) ((> (* i 9) (+ w 9)))
        (let ([x (* i 9)]
              [tall (+ 14 (mod (* i 37) 29))]
              [sway (* 5 (sin (+ (* 1.2 t) (* 0.45 i))))])
          (fill-polygon (list (cons (- x 4) h) (cons (+ x 4) h)
                              (cons (+ x sway) (- top tall)))
                        (if (even? i) #x0f2a1d #x143522))))))

  ;; A firefly: a dim speck dark, a soft green-gold glow lit.
  (define (fireflies-draw-firefly g b)
    (let ([x (fireflies-bug-x b)] [y (fireflies-bug-y b)]
          [k (fireflies-glow g b)])
      (when (> k 0)
        (fill-circle x y 22 (radial-gradient x y 22
                                             (alpha #xd8ff6a (* 0.55 k))
                                             (alpha #xb4f04c (* 0.18 k))
                                             (alpha #xb4f04c 0))))
      (fill-circle x y 2.5 (mix #x3c3a26 #xf8ffc8 k))))

  ;; A moth along its heading: hind and fore wings beating fast, a dark
  ;; body, two feelers; a little larger than its numbers, to be seen.
  (define (fireflies-draw-moth g b)
    (let* ([x (fireflies-bug-x b)] [y (fireflies-bug-y b)]
           [c (* 1.25 (cos (fireflies-bug-heading b)))]
           [s (* 1.25 (sin (fireflies-bug-heading b)))]
           [at (lambda (u v)
                 (cons (+ x (* u c) (- (* v s))) (+ y (* u s) (* v c))))]
           [span (+ 4 (* 8 (abs (sin (+ (* 22 (fireflies-state-clock g))
                                        (* 9 (fireflies-bug-phase b)))))))]
           [head (at 2 0)]
           [tail (at -5 0)])
      (for-each (lambda (v)
                  (fill-polygon (list (at -3 0) (at -6 (* v 0.75))
                                      (at -12 (* v 0.5)) (at -9 0))
                                #x7a7266)
                  (fill-polygon (list (at 3 0) (at -1 v) (at -7 (* v 0.8))
                                      (at -4 0))
                                #xaba393))
                (list span (- span)))
      (draw-polyline (list (at 9 -3) (at 3 0) (at 9 3)) #x8a8274 1)
      (fill-circle (car head) (cdr head) 2.6 #x4a4239)
      (fill-circle (car tail) (cdr tail) 2.2 #x4a4239)))

  ;; Each catch: a ring that spreads and fades.
  (define (fireflies-draw-sparks g)
    (for-each (lambda (s)
                (let ([age (- (fireflies-state-clock g) (cddr s))])
                  (stroke-circle (car s) (cadr s) (+ 6 (* 60 age))
                                 (alpha #xf0ffb0 (max 0 (- 1 (/ age 0.6))))
                                 2)))
              (fireflies-state-sparks g)))

  ;; The jar: glass with a cork, aglow, the more so with the fireflies
  ;; caught this level inside; a crack for each life lost; shaking red
  ;; when a moth hits.
  (define (fireflies-draw-jar g)
    (let* ([t (fireflies-state-clock g)] [hurt (fireflies-state-hurt g)]
           [x (+ (fireflies-state-x g) (* 4 hurt (sin (* 70 t))))]
           [y (fireflies-state-y g)] [r fireflies-jar-r]
           [n (mod (fireflies-state-score g) 10)])
      (fill-circle x y (+ r 30)
                   (radial-gradient x y (+ r 30)
                                    (alpha (if (> n 0) #xd8ff6a #xcfe4ff)
                                           (+ 0.06 (* 0.05 n)))
                                    (alpha #xd8ff6a 0)))
      (fill-circle x y r (radial-gradient (- x 8) (- y 8) (* 1.7 r)
                                          (alpha #xeef6ff 0.32)
                                          (alpha #xa8c8f0 0.10)
                                          (alpha #xa8c8f0 0.28)))
      (do ([i 0 (+ i 1)]) ((= i n))
        (let ([a (+ (* i 2.4) (* 0.7 t))] [d (+ 5 (* 4 (mod i 3)))])
          (fill-circle (+ x (* d (cos a))) (+ y 3 (* d (sin a))) 2 #xeaff9a)))
      (for-each (lambda (crack)
                  (draw-polyline (map (lambda (p)
                                        (cons (+ x (car p)) (+ y (cdr p))))
                                      crack)
                                 (alpha #xffffff 0.85) 1.5))
                (list-head fireflies-cracks
                           (- 3 (max 0 (fireflies-state-lives g)))))
      (stroke-circle x y r (alpha (mix #xd8ecff #xff5a48 (min 1 hurt)) 0.8) 2)
      (fill-circle (- x 9) (- y 10) 4 (alpha #xffffff 0.45))
      (fill-box (- x 12) (- y r 7) 24 9 #x8b6239 3)))

  ;; str centered on cx, its top at y.
  (define (fireflies-text-centered cx y str color f)
    (draw-text (- cx (/ (text-width str f) 2)) y str color f))

  ;; What's caught, the level and the lives left along the top; the
  ;; level's name as it starts; the score once the jar is broken.
  (define (fireflies-draw-words g w h)
    (let ([small (fireflies-state-small g)] [big (fireflies-state-big g)]
          [score (fireflies-state-score g)]
          [level (format "Level ~a" (fireflies-state-level g))]
          [banner (fireflies-state-banner g)])
      (draw-text 16 12 (format "~a caught" score) #xeaff9a small)
      (fireflies-text-centered (/ w 2) 12 level #xb8bcd8 small)
      (do ([i 0 (+ i 1)]) ((= i 3))
        (let ([x (- w 24 (* 22 i))])
          (when (< i (fireflies-state-lives g))
            (fill-circle x 22 7 (alpha #xd8ecff 0.3)))
          (stroke-circle x 22 7 (alpha #xd8ecff 0.8) 1.5)))
      (cond
        [(fireflies-over? g)
         (let ([pw (min 420 (- w 32))] [top (- (/ h 2) 80)])
           (fill-box (/ (- w pw) 2) top pw 160 (alpha #x04071a 0.75) 16)
           (stroke-box (/ (- w pw) 2) top pw 160 (alpha #xd8ecff 0.3) 1 16)
           (fireflies-text-centered (/ w 2) (+ top 20) "The jar broke"
                                    #xf4f0ff big)
           (fireflies-text-centered
            (/ w 2) (+ top 76)
            (format "~a ~a caught, ~a" score
                    (if (= score 1) "firefly" "fireflies")
                    (string-downcase level))
            #xeaff9a small)
           (fireflies-text-centered (/ w 2) (+ top 110)
                                    "Space, Return or a click to play again"
                                    #xa8aecc small))]
        [(> banner 0)
         (let ([a (min 1.0 banner)] [y (* 0.3 h)])
           (fireflies-text-centered (/ w 2) y level (alpha #xf4f0ff a) big)
           (when (= (fireflies-state-level g) 1)
             (fireflies-text-centered (/ w 2) (+ y 50)
                                      "Catch the lit ones; mind the moths"
                                      (alpha #xc8cce4 a) small)))])))

  ;; g drawn on a field w × h, from its top-left corner.
  (define (fireflies-draw-field g w h)
    (fireflies-draw-sky g w h)
    (fireflies-draw-grass g w h)
    (for-each (lambda (b)
                (if (fireflies-bug-moth? b)
                    (fireflies-draw-moth g b)
                    (fireflies-draw-firefly g b)))
              (fireflies-state-bugs g))
    (fireflies-draw-sparks g)
    (fireflies-draw-jar g)
    (fireflies-draw-words g w h))

  ;;; ---------------------------------------------------------------- two ways

  ;; The game in a window, on whatever screen there is: it rides frames,
  ;; and closing the window ends it.
  (define (fireflies-open)
    (open-window "Fireflies"
      'size '(640 . 480)
      'min-size '(320 . 240)
      'game (fireflies-new 640 480 (fireflies-seed))
      'open (lambda (win) (window-frame-soon! win))
      'frame (lambda (win t)
               (let ([g (window-ref win 'game)])
                 (call-with-values (lambda () (window-content-size win))
                   (lambda (w h) (fireflies-resize! g w h)))
                 (fireflies-frame! g t))
               (invalidate! win)
               (window-frame-soon! win))
      'draw (lambda (win w h)
              (fireflies-draw-field (window-ref win 'game) w h))
      'mouse-move (lambda (win x y)
                    (fireflies-head! (window-ref win 'game) x y))
      'mouse-down (lambda (win x y button clicks)
                    (fireflies-click! (window-ref win 'game) x y))
      'key (lambda (win key mods) (fireflies-key! (window-ref win 'game) key))))

  (define-app (fireflies) "Fireflies"
    (fireflies-open))

  ;; "960x640" => (960 . 640); #f if it isn't a size.
  (define (fireflies-size s)
    (let loop ([i 0])
      (cond [(= i (string-length s)) #f]
            [(char=? (string-ref s i) #\x)
             (let ([w (string->number (substring s 0 i))]
                   [h (string->number
                       (substring s (+ i 1) (string-length s)))])
               (and (fixnum? w) (fixnum? h) (> w 0) (> h 0) (cons w h)))]
            [else (loop (+ i 1))])))

  ;; The pixel of the screen's bytes at (u, v), fractions of its width
  ;; and height, as (r g b).
  (define (fireflies-screen-pixel bytes u v)
    (let* ([x (min (- *canvas-pw* 1) (exact (floor (* u *canvas-pw*))))]
           [y (min (- *canvas-ph* 1) (exact (floor (* v *canvas-ph*))))]
           [at (* 4 (+ x (* y *canvas-pw*)))])
      (list (bytevector-u8-ref bytes (+ at 2))
            (bytevector-u8-ref bytes (+ at 1))
            (bytevector-u8-ref bytes at))))

  ;; The lit firefly nearest the jar, or #f.
  (define (fireflies-nearest-lit g)
    (fold-left (lambda (best b)
                 (if (and (not (fireflies-bug-moth? b))
                          (> (fireflies-glow g b) 0.5)
                          (or (not best)
                              (< (fireflies-from-jar g b)
                                 (fireflies-from-jar g best))))
                     b
                     best))
               #f
               (fireflies-state-bugs g)))

  ;; The game checks itself, headless: a second played from seed 1, the
  ;; jar steered onto the nearest lit firefly, then the screen read back
  ;; and told: its size, the sky, the grass and the jar, and the score.
  (define (fireflies-check g)
    (do ([i 0 (+ i 1)]) ((= i 60))
      (let ([b (fireflies-nearest-lit g)])
        (when b (fireflies-head! g (fireflies-bug-x b) (fireflies-bug-y b))))
      (fireflies-step! g (/ 1.0 60)))
    (request-frame!)
    (after 100
      (lambda ()
        (screen-bytes-then
         (lambda (bytes)
           (printf "~a x ~a pixels; sky ~s, grass ~s, jar ~s; ~a caught, \
                    ~a lives, level ~a~n"
                   *canvas-pw* *canvas-ph*
                   (fireflies-screen-pixel bytes 1/2 1/200)
                   (fireflies-screen-pixel bytes 1/2 199/200)
                   (fireflies-screen-pixel
                    bytes
                    (/ (fireflies-state-x g) (fireflies-state-w g))
                    (/ (fireflies-state-y g) (fireflies-state-h g)))
                   (fireflies-state-score g) (fireflies-state-lives g)
                   (fireflies-state-level g))
           (quit!))))))

  ;; The game on a screen of its own, from the command line's args: a
  ;; surface over all of it takes the mouse and the keys, and Escape
  ;; quits. --headless plays a game and tells what it read back; --fork,
  ;; the screen's thread and the world's, as with a window.
  (define (fireflies-main args)
    (let* ([headless? (and (member "--headless" args) #t)]
           [size (member "--size" args)]
           [size (or (and size (pair? (cdr size)) (fireflies-size (cadr size)))
                     '(960 . 640))])
      (schevana-main (if headless? 'headless 'sdl) (car size) (cdr size)
                     (and (member "--fullscreen" args) #t)
        (lambda ()
          (let ([g (fireflies-new (screen-w) (screen-h)
                                  (if headless? 1 (fireflies-seed)))])
            (define-surface fireflies-field -10
              'draw (lambda () (fireflies-draw-field g (screen-w) (screen-h)))
              'box (lambda () (values 0 0 (screen-w) (screen-h)))
              'at (lambda (x y) 'field)
              'mouse (lambda (kind what x y button clicks)
                       (case kind
                         [(move) (fireflies-head! g x y)]
                         [(down) (fireflies-click! g x y)]))
              'key (lambda (kind key mods)
                     (when (eq? kind 'key)
                       (if (eq? key 'escape) (quit!) (fireflies-key! g key)))
                     #t)
              ;; headless, the check plays the game, by a clock of its own
              'frame (lambda (t)
                       (unless headless?
                         (fireflies-resize! g (screen-w) (screen-h))
                         (fireflies-frame! g t)
                         (request-frame!))))
            (when headless? (fireflies-check g))))
        (and (member "--fork" args) #t)))))
