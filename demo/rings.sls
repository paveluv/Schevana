;;; (demo rings) — a program that uses only drawing: no theme, no
;;; windows, no desktop. It fills the hooks the windows layer would fill,
;;; telling the loop what a frame draws and where an event goes, and runs
;;; six paints of the shader language at once, each in a tile of the
;;; screen: the ripples of two waves, plasma, a Julia set, metaballs,
;;; cells and fire. The mouse moves the ripples' second source and a ball.
;;; Keys 1 to 6 show one paint alone, 0 (or Escape) shows all of them
;;; again, and Escape while all of them show quits. On the desktop
;;; (./desktop demo) the same paints run in a window.
;;;
;;;   ./rings-demo             a window
;;;   ./rings-demo --headless  draws a frame, reads it back and reports
;;;                            whether each paint drew

(library (demo rings)
  (export rings-main rings)
  (import (chezscheme)
          (schevana core))

  ;;; ------------------------------------------------------------------ paints
  ;;; Each paint gets its tile's size, w × h device pixels, and t, the
  ;;; seconds since the program began; x and y are the pixel it paints,
  ;;; counted from the tile's corner.

  ;; Helpers the paints share: byte turns a fraction into a byte, rgb
  ;; makes a color of three fractions, wave is a channel of a cosine
  ;; palette (0.5 + 0.5 cos 2π(v + d)), and dist is the distance between
  ;; two points.
  (define-shader-helpers rings-helpers
    (define (byte v) (flonum->fixnum (fl* 255.0 (clamp01 v))))
    (define (rgb r g b)
      (fxior -16777216 (fxsll (byte r) 16) (fxsll (byte g) 8) (byte b)))
    (define (wave v d)
      (fl+ 0.5 (fl* 0.5 (flcos (fl* 6.2831853 (fl+ v d))))))
    (define (dist ax ay bx by)
      (let ([dx (fl- ax bx)] [dy (fl- ay by)])
        (flsqrt (fl+ (fl* dx dx) (fl* dy dy))))))

  ;; Value noise: each point of a whole-number lattice gets a value from
  ;; 0 to 1 by hashing its coordinates (in 32-bit words that wrap), and a
  ;; point between them gets a smooth mix of the four around it.
  (define-shader-helpers rings-noise
    (define (lattice ix iy)
      (let* ([a (fx+ (fx* ix 374761393) (fx* iy 668265263))]
             [b (fx* (fxxor a (fxsrl a 13)) 1274126177)]
             [c (fxxor b (fxsrl b 16))])
        (fl* 0.0000152590219 (fixnum->flonum (fxand c 65535)))))
    (define (noise px py)
      (let* ([x0 (flfloor px)] [y0 (flfloor py)]
             [ix (flonum->fixnum x0)] [iy (flonum->fixnum y0)]
             [u (fl- px x0)] [v (fl- py y0)]
             [su (fl* u u (fl- 3.0 (fl* 2.0 u)))]
             [sv (fl* v v (fl- 3.0 (fl* 2.0 v)))]
             [a (lattice ix iy)] [b (lattice (fx+ ix 1) iy)]
             [c (lattice ix (fx+ iy 1))] [d (lattice (fx+ ix 1) (fx+ iy 1))])
        (fl+ a (fl* su (fl- b a)) (fl* sv (fl- c a))
             (fl* su sv (fl- (fl- a b) (fl- c d)))))))

  ;; Waves from two sources, one at the middle and one at (mx, my): it is
  ;; light where two crests meet and dark where a crest meets a trough.
  (define-paint (rings-ripples x y)
    ([w fixnum] [h fixnum] [t flonum] [mx flonum] [my flonum])
    (use-shader-helpers rings-helpers)
    (let* ([fw (fixnum->flonum w)] [fh (fixnum->flonum h)]
           [px (fixnum->flonum x)] [py (fixnum->flonum y)]
           [k (fl/ 60.0 (flmin fw fh))]
           [a (dist px py (fl* 0.5 fw) (fl* 0.5 fh))]
           [b (dist px py mx my)]
           [v (fl* 0.25 (fl+ 2.0
                             (flsin (fl- (fl* k a) (fl* 4.0 t)))
                             (flsin (fl- (fl* k b) (fl* 4.0 t)))))])
      (rgb (fl* 0.6 v v) (fl+ 0.1 (fl* 0.7 v)) (fl+ 0.25 (fl* 0.75 v)))))

  ;; Plasma: four sines (along x, along y, diagonally, and around a point
  ;; that wanders), added and colored through the palette.
  (define-paint (rings-plasma x y)
    ([w fixnum] [h fixnum] [t flonum])
    (use-shader-helpers rings-helpers)
    (let* ([k (fl/ 10.0 (flmin (fixnum->flonum w) (fixnum->flonum h)))]
           [px (fl* k (fixnum->flonum x))]
           [py (fl* k (fixnum->flonum y))]
           [cx (fl- px (fl* 5.0 (fl+ 1.0 (flsin (fl* 0.3 t)))))]
           [cy (fl- py (fl* 3.0 (fl+ 1.0 (flcos (fl* 0.4 t)))))]
           [v (fl* 0.125
                   (fl+ 4.0
                        (flsin (fl+ px t))
                        (flsin (fl* 0.5 (fl+ py t)))
                        (flsin (fl* 0.5 (fl+ px py t)))
                        (flsin (fl+ t (flsqrt (fl+ (fl* cx cx) (fl* cy cy)
                                                   1.0))))))])
      (rgb (wave v 0.0) (wave v 0.33) (wave v 0.67))))

  ;; The Julia set of c, where c moves around a circle of radius 0.7885,
  ;; starting at 2.4 radians, where the sets curl. Each pixel iterates
  ;; z² + c from its own z at most 96 times; a pixel whose z stays near
  ;; the origin is in the set.
  (define-paint (rings-julia x y)
    ([w fixnum] [h fixnum] [t flonum])
    (use-shader-helpers rings-helpers)
    (let* ([fw (fixnum->flonum w)] [fh (fixnum->flonum h)]
           [k (fl/ 3.2 (flmin fw fh))]
           [ar (fl* k (fl- (fixnum->flonum x) (fl* 0.5 fw)))]
           [ai (fl* k (fl- (fixnum->flonum y) (fl* 0.5 fh)))]
           [a (fl+ 2.4 (fl* 0.2 t))]
           [cr (fl* 0.7885 (flcos a))]
           [ci (fl* 0.7885 (flsin a))]
           [count
            (do-bounded 96 ([zr ar (fl+ (fl- (fl* zr zr) (fl* zi zi)) cr)]
                            [zi ai (fl+ (fl* 2.0 zr zi) ci)]
                            [n 0 (fx+ n 1)])
              ((fl> (fl+ (fl* zr zr) (fl* zi zi)) 4.0) n))])
      (if (fx>= count 96)
          (rgb 0.02 0.0 0.05)
          (let ([v (fl* 1.6 (flsqrt (fl/ (fixnum->flonum count) 96.0)))])
            (rgb (wave v 0.5) (wave v 0.6) (wave v 0.7))))))

  ;; Metaballs: the fields of four balls added up, three moving in loops
  ;; and one at (mx, my). Where the field passes 1 the balls merge into
  ;; one hot surface, and around it they glow.
  (define-paint (rings-metaballs x y)
    ([w fixnum] [h fixnum] [t flonum] [mx flonum] [my flonum])
    (use-shader-helpers rings-helpers)
    ;; ball is a ball's field at (px, py); by-sin and by-cos give a ball's
    ;; place along a side s long, swinging at most a of s from the middle
    ;; at b radians a second
    (define (ball px py bx by r2)
      (let ([dx (fl- px bx)] [dy (fl- py by)])
        (fl/ r2 (fl+ (fl* dx dx) (fl* dy dy) 1.0))))
    (define (by-sin s a b) (fl* s (fl+ 0.5 (fl* a (flsin (fl* b t))))))
    (define (by-cos s a b) (fl* s (fl+ 0.5 (fl* a (flcos (fl* b t))))))
    (let* ([fw (fixnum->flonum w)] [fh (fixnum->flonum h)]
           [px (fixnum->flonum x)] [py (fixnum->flonum y)]
           [r2 (fl* 0.02 fw fh)]
           [f (fl+ (ball px py (by-sin fw 0.25 0.9) (by-cos fh 0.25 1.3) r2)
                   (ball px py (by-cos fw 0.3 0.7) (by-sin fh 0.2 1.1) r2)
                   (ball px py (by-sin fw 0.2 1.7) (by-sin fh 0.3 0.6) r2)
                   (ball px py mx my r2))]
           [glow (clamp01 (fl* 0.6 f f))]
           [hot (clamp01 (fl* 0.5 (fl- f 1.0)))])
      (if (fl> f 1.0)
          (rgb 1.0 (fl+ 0.45 (fl* 0.5 hot)) (fl+ 0.1 (fl* 0.8 hot)))
          (rgb (fl+ 0.06 (fl* 0.9 glow)) (fl+ 0.02 (fl* 0.3 glow glow))
               (fl+ 0.12 (fl* 0.25 glow))))))

  ;; Cells: twelve seeds move in loops, and each pixel takes the color of
  ;; the nearest one, darker farther from it, and dark where the second
  ;; nearest is nearly as near (the cells' walls).
  (define-paint (rings-cells x y)
    ([w fixnum] [h fixnum] [t flonum])
    (use-shader-helpers rings-helpers)
    (let* ([fw (fixnum->flonum w)] [fh (fixnum->flonum h)]
           [px (fixnum->flonum x)] [py (fixnum->flonum y)])
      ;; the distance to seed i, whose two angles each turn at a pace of
      ;; their own
      (define (seed i)
        (let* ([fi (fixnum->flonum i)]
               [a (fl+ (fl* 1.7 fi) (fl* t (fl+ 0.21 (fl* 0.037 fi))))]
               [b (fl+ (fl* 2.3 fi) (fl* t (fl+ 0.17 (fl* 0.041 fi))))])
          (dist px py
                (fl* fw (fl+ 0.5 (fl* 0.45 (flsin a))))
                (fl* fh (fl+ 0.5 (fl* 0.45 (flcos b)))))))
      (do-bounded 12 ([i 0 (fx+ i 1)]
                      [d1 1e9 (flmin d1 (seed i))]
                      [d2 1e9 (if (fl< (seed i) d1) d1 (flmin d2 (seed i)))]
                      [id 0 (if (fl< (seed i) d1) i id)])
        ((fx>= i 12)
         (let* ([wall (clamp01 (fl* 0.08 (fl- d2 d1)))]
                [far (clamp01 (fl/ d1 (fl* 0.6 (flmin fw fh))))]
                [shade (fl* wall (fl- 1.0 far))]
                [v (fl* 0.083 (fixnum->flonum id))])
           (rgb (fl* shade (wave v 0.0)) (fl* shade (wave v 0.33))
                (fl* shade (wave v 0.67))))))))

  ;; Fire: five octaves of rising noise, hotter lower down, colored from
  ;; black through red and orange to yellow and white.
  (define-paint (rings-fire x y)
    ([w fixnum] [h fixnum] [t flonum])
    (use-shader-helpers rings-helpers)
    (use-shader-helpers rings-noise)
    (let* ([fh (fixnum->flonum h)]
           [k (fl/ 6.0 (flmin (fixnum->flonum w) fh))]
           [px (fl* k (fixnum->flonum x))]
           [py (fl+ (fl* k (fixnum->flonum y)) (fl* 2.0 t))])
      ;; the noise, f times finer
      (define (octave f) (noise (fl* px f) (fl* py f)))
      (let* ([n (do-bounded 5 ([o 0 (fx+ o 1)]
                               [amp 0.5 (fl* amp 0.5)]
                               [freq 1.0 (fl* freq 2.0)]
                               [sum 0.0 (fl+ sum (fl* amp (octave freq)))])
                  ((fx>= o 5) sum))]
             [low (fl/ (fixnum->flonum y) fh)]
             [heat (clamp01 (fl- (fl* 1.9 n low) 0.35))])
        (rgb (fl* 2.6 heat) (fl- (fl* 2.0 heat) 0.6)
             (fl- (fl* 3.0 heat) 2.2)))))

  ;;; ------------------------------------------------------------------ tiles

  (define rings-names
    '#("Ripples" "Plasma" "Julia" "Metaballs" "Cells" "Fire"))

  ;; Draws paint i over the box at (x, y), w × h, at s device pixels per
  ;; unit, t seconds in; mouse is the pointer as (x . y) in the same units
  ;; as the box, or #f.
  (define (rings-tile i x y w h s t mouse)
    (let* ([pw (exact (round (* w s)))]
           [ph (exact (round (* h s)))]
           ;; the pointer in the tile's device pixels or, when it isn't
           ;; over the tile, a point moving in a loop
           [over? (and mouse (<= x (car mouse) (+ x w))
                       (<= y (cdr mouse) (+ y h)))]
           [mx (if over?
                   (inexact (* s (- (car mouse) x)))
                   (* pw (+ 0.5 (* 0.3 (cos (* 0.7 t))))))]
           [my (if over?
                   (inexact (* s (- (cdr mouse) y)))
                   (* ph (+ 0.5 (* 0.3 (sin (* 0.9 t))))))])
      (case i
        [(0) (fill-shader x y w h rings-ripples pw ph t mx my)]
        [(1) (fill-shader x y w h rings-plasma pw ph t)]
        [(2) (fill-shader x y w h rings-julia pw ph t)]
        [(3) (fill-shader x y w h rings-metaballs pw ph t mx my)]
        [(4) (fill-shader x y w h rings-cells pw ph t)]
        [else (fill-shader x y w h rings-fire pw ph t)])))

  ;; Returns where tile i sits in w × h (leaving out a line at the
  ;; bottom) as (x y w h): all six tiles sit in three columns and two
  ;; rows, and the one shown alone takes the whole space.
  (define (rings-place i alone w h)
    (let ([h (- h 24)])
      (if alone
          (list 0 0 w h)
          (let ([tw (quotient (- w 8) 3)] [th (quotient (- h 4) 2)])
            (list (* (mod i 3) (+ tw 4)) (* (quotient i 3) (+ th 4)) tw th)))))

  ;; Draws the paints over w × h logical pixels, at s device pixels to
  ;; one, t seconds in: all six, or the one alone (#f for all six), each
  ;; with its name, and a line saying what the keys do (in the program,
  ;; program?, Escape also quits).
  (define (rings-draw w h s t mouse alone font program?)
    (fill-box 0 0 w h #x101018)
    (for-each
     (lambda (i)
       (let ([p (rings-place i alone w h)])
         (apply (lambda (x y tw th)
                  (rings-tile i x y tw th s t mouse)
                  (draw-text (+ x 11) (+ y 9) (vector-ref rings-names i)
                             #x000000 font)
                  (draw-text (+ x 10) (+ y 8) (vector-ref rings-names i)
                             #xffffff font))
                p)))
     (if alone (list alone) (iota 6)))
    (draw-text 10 (- h 20)
               (cond
                 [alone "0 or Escape: all six"]
                 [program? "Six paints in the shader language.   1-6: one \
                            alone.   Escape quits."]
                 [else "Six paints in the shader language.   1-6: one \
                        alone."])
               #xb8b8c8 font))

  ;; Returns what key makes of alone: the paint to show alone now (#f for
  ;; all six), or quit for Escape while all six show.
  (define (rings-key alone key)
    (cond [(and (char? key) (char<=? #\1 key #\6))
           (- (char->integer key) (char->integer #\1))]
          [(or (eqv? key #\0) (and (eq? key 'escape) alone)) #f]
          [(eq? key 'escape) 'quit]
          [else alone]))

  ;; On the desktop: the same paints in a window, which asks for a frame
  ;; after every frame.
  (define-app (rings) "Rings"
    (let ([began (now-ms)] [font (font "sans-serif" 14 'bold)])
      (open-window "Rings"
        'size '(720 . 480)
        'open (lambda (win) (window-frame-soon! win))
        'frame (lambda (win t) (invalidate! win) (window-frame-soon! win))
        'mouse-move (lambda (win x y) (window-set! win 'mouse (cons x y)))
        'key (lambda (win key mods)
               (let ([alone (rings-key (window-ref win 'alone) key)])
                 (window-set! win 'alone (and (fixnum? alone) alone))))
        'draw (lambda (win w h)
                (rings-draw w h (draw-scale) (/ (- (now-ms) began) 1000.0)
                            (window-ref win 'mouse) (window-ref win 'alone)
                            font #f)))))

  ;; Returns the pixel at (x, y) of bytes (the screen's pixels) as
  ;; (r g b).
  (define (rings-pixel bytes x y)
    (let ([at (* 4 (+ x (* y *canvas-pw*)))])
      (list (bytevector-u8-ref bytes (+ at 2))
            (bytevector-u8-ref bytes (+ at 1))
            (bytevector-u8-ref bytes at))))

  ;; Whether tile i drew anything in bytes: whether nine pixels across it
  ;; are not all the same.
  (define (rings-drew? bytes i)
    (let* ([s (/ *canvas-pw* *canvas-w*)]
           [p (rings-place i #f *canvas-w* *canvas-h*)]
           [at (lambda (f g)
                 (rings-pixel bytes
                              (exact (floor (* s (+ (car p) (* f (caddr p))))))
                              (exact (floor (* s (+ (cadr p)
                                                    (* g (cadddr p))))))))]
           [seen (apply append
                        (map (lambda (f)
                               (map (lambda (g) (at f g)) '(0.3 0.5 0.7)))
                             '(0.3 0.5 0.7)))])
      (not (for-all (lambda (c) (equal? c (car seen))) seen))))

  ;; The program, from the command line's args. It fills the loop's hooks
  ;; itself, so nothing of the windows layer runs. --headless draws a
  ;; frame, reports what it read back, and exits with 1 if a paint drew
  ;; nothing.
  (define (rings-main args)
    (let ([headless? (member "--headless" args)]
          [began (now-ms)]
          [font (font "sans-serif" 14 'bold)]
          [mouse #f]
          [alone #f])
      (set! record-world!
        (lambda ()
          (rings-draw *canvas-w* *canvas-h* (/ *canvas-pw* *canvas-w*)
                      (/ (- (now-ms) began) 1000.0) mouse alone font #t)))
      (set! wm-event!
        (lambda (ev)
          (case (car ev)
            [(mouse-move)
             (set! mouse (cons (cadr ev) (caddr ev)))
             (request-frame!)]
            [(key-down)
             (let ([now (rings-key alone (cadr ev))])
               (if (eq? now 'quit)
                   (quit!)
                   (begin (set! alone now) (request-frame!))))]
            [else (void)])))
      (set! wm-tick! (lambda () (unless headless? (request-frame!))))
      (schevana-main (if headless? 'headless 'sdl) 960 600 #f
        (lambda ()
          (when headless?
            (after 100
              (lambda ()
                (screen-bytes-then
                 (lambda (bytes)
                   (let ([drew (map (lambda (i) (rings-drew? bytes i))
                                    (iota 6))])
                     (printf "~a x ~a pixels; ~{~a~^, ~}~n"
                             *canvas-pw* *canvas-ph*
                             (map (lambda (i d)
                                    (format "~a ~a" (vector-ref rings-names i)
                                            (if d "drew" "drew nothing")))
                                  (iota 6) drew))
                     (if (for-all values drew) (quit!) (exit 1)))))))))))))
