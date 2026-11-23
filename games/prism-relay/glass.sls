;;; (games prism-relay glass) — the paint that draws the bench from its ray
;;; map ((games prism-relay board)): etched glass, silver mirrors on round
;;; mounts, violet half-silvered ones, amber crystals, the source, the ring,
;;; and the light, with pulses running along it from the source.

(library (games prism-relay glass)
  (export prism-glass prism-swing-ease)
  (import (chezscheme)
          (schevana core))

  (define-shader-constant prism-slash (char->integer #\/))
  (define-shader-constant prism-backslash (char->integer #\\))
  (define-shader-constant prism-half-slash (char->integer #\Z))
  (define-shader-constant prism-half-backslash (char->integer #\N))
  (define-shader-constant prism-crystal (char->integer #\*))
  (define-shader-constant prism-ring (char->integer #\O))
  (define-shader-constant prism-wall (char->integer #\#))
  (define-shader-constant prism-east (char->integer #\>))
  (define-shader-constant prism-south (char->integer #\v))
  (define-shader-constant prism-west (char->integer #\<))
  (define-shader-constant prism-north (char->integer #\^))

  ;; Returns how far a mirror's swing has gone at p, from 0 to 1 of its
  ;; quarter turn: fast at first, settling at the end.
  (define (prism-swing-ease p)
    (let ([q (- 1.0 (max 0.0 (min 1.0 p)))]) (- 1.0 (* q q q))))

  ;; Each pixel is shaded in cell coordinates, cells being pitch device
  ;; pixels wide. The mirror at swing-cell is drawn turned by swing (from 0
  ;; to 1 of its quarter turn) from the leaning the map gives it. surge is
  ;; where the light's flourish runs, in cells from the source, or less than
  ;; 0 for none; solved is 1 once the chamber is solved.
  (define-paint (prism-glass x y)
    ([cells fx-buffer] [cols fixnum] [rows fixnum] [pitch flonum]
     [selected fixnum] [hover fixnum] [phase flonum] [swing-cell fixnum]
     [swing flonum] [surge flonum] [solved fixnum])
    (define (band d w) (clamp01 (fl+ 0.5 (fl* pitch (fl- w d)))))
    ;; A glow fades out before the cell's edge, d cells from its middle,
    ;; since the next cell doesn't draw it.
    (define (fade d) (clamp01 (fl* 5.0 (fl- 0.5 d))))
    (define (frac a) (fl- a (flfloor a)))
    ;; Dither of interleaved gradient noise, from 0 to 1, so that the
    ;; glass's soft shading shows no steps.
    (define (grain)
      (frac (fl* 52.9829189
                 (frac (fl+ (fl* 0.06711056 (fixnum->flonum x))
                            (fl* 0.00583715 (fixnum->flonum y)))))))
    (define (byte v n) (flonum->fixnum (fl+ (fl* 255.0 (clamp01 v)) n)))
    (define (ink r g b)
      (let ([n (grain)])
        (fxior -16777216 (fxsll (byte r n) 16) (fxsll (byte g n) 8)
               (byte b n))))
    (let* ([gx (fl/ (fl+ (fixnum->flonum x) 0.5) pitch)]
           [gy (fl/ (fl+ (fixnum->flonum y) 0.5) pitch)]
           [col (flfloor gx)] [row (flfloor gy)]
           [i (fx+ (flonum->fixnum col) (fx* cols (flonum->fixnum row)))]
           [u (fl- gx col 0.5)] [v (fl- gy row 0.5)]
           [au (flabs u)] [av (flabs v)]
           [r (flsqrt (fl+ (fl* u u) (fl* v v)))]
           [edge (flmax au av)] [word (fx-ref cells i)]
           [tile (fxand word 255)] [sides (fxand (fxsrl word 8) 65535)]
           [far (fixnum->flonum (fxand (fxsrl word 24) 255))]
           [lit? (not (fx= sides 0))])
      ;; The light of one side's leg at a point along cells out from the
      ;; middle and across cells off its line. The pulses keep their
      ;; phase from cell to cell, and the flourish brightens the light
      ;; near its front.
      (define (leg-light leg along across)
        (if (fx= leg 0)
            0.0
            (let* ([at (fl+ (fixnum->flonum (fxand leg 3))
                            (if (fx= 0 (fxand leg 4)) (fl- along) along))]
                   [wave (flcos (fl- (fl* 1.5707963 at) phase))]
                   [pulse (clamp01 (fl- (fl* 4.0 wave) 3.0))]
                   [whole (fl+ at (fl* 4.0 (flround (fl* 0.25 (fl- far at)))))]
                   [ahead (flabs (fl- whole surge))]
                   [rush (if (fl< surge 0.0)
                             0.0
                             (clamp01 (fl- 1.0 (fl* 0.6 ahead))))])
              (fl* (fl+ 0.72 (fl* 0.68 pulse) (fl* 1.6 rush))
                   (fl+ (band across 0.021)
                        (fl/ (fl* 0.62 (fade across))
                             (fl+ 1.0 (fl* 245.0 across across))))))))
      ;; A side's leg runs from the middle to that side; behind the
      ;; middle, its light is measured from the middle, so that joints and
      ;; ends are round.
      (define (side-light side ahead off)
        (let ([leg (fxand 15 (fxsrl sides (fx* 4 side)))])
          (if (fl< ahead 0.0)
              (leg-light leg 0.0 r)
              (leg-light leg ahead off))))
      (let* ([beam (flmax (side-light 0 u av) (side-light 1 v au)
                          (side-light 2 (fl- u) av) (side-light 3 (fl- v) au))]
             [half? (or (fx= tile prism-half-slash)
                        (fx= tile prism-half-backslash))]
             [mirror? (or half? (fx= tile prism-slash)
                          (fx= tile prism-backslash))]
             [lean (if (or (fx= tile prism-slash) (fx= tile prism-half-slash))
                       -0.7853982
                       0.7853982)]
             [angle (if (fx= i swing-cell)
                        (fl+ lean (fl* 1.5707963 swing))
                        lean)]
             [ca (flcos angle)] [sa (flsin angle)]
             [bar-off (flabs (fl- (fl* ca v) (fl* sa u)))]
             [bar-along (flabs (fl+ (fl* ca u) (fl* sa v)))]
             [mount (fl* (if (fx= i hover) 0.6 0.23)
                         (band (flabs (fl- r 0.34)) 0.014))]
             [steel
              (cond
                [(and mirror? (not half?))
                 (fl+ mount
                      (fl* (band bar-along 0.375)
                           (fl+ (fl* 0.28 (band bar-off 0.06))
                                (fl* 0.68 (band bar-off 0.0226)))))]
                [(or (fx= tile prism-east) (fx= tile prism-south)
                     (fx= tile prism-west) (fx= tile prism-north))
                 (fl+ (fl* 0.65 (band (flabs (fl- r 0.23)) 0.029))
                      (fl* 0.9 (band r 0.115)))]
                [(fx= tile prism-wall)
                 (fl* (band edge 0.40)
                      (fl+ 0.09 (fl* 0.08 (flcos (fl* 35.0 (fl+ u v))))))]
                [else 0.0])]
             [violet
              (if half?
                  ;; a pane of glass with a dashed silvering
                  (let* ([wave (flcos (fl* 56.0 bar-along))]
                         [dash (fl+ 0.55 (fl* 0.45 (clamp01
                                                    (fl+ 0.5
                                                         (fl* 2.0 wave)))))])
                    (fl+ (fl* 0.7 mount)
                         (fl* (band bar-along 0.375)
                              (fl+ (fl* 0.22 (band bar-off 0.05))
                                   (fl* 0.7 dash (band bar-off 0.016))))))
                  0.0)]
             [flare (if (fl< surge 0.0)
                        0.0
                        (clamp01 (fl- 1.0 (fl* 0.7 (flabs (fl- far surge))))))]
             [bloom (if (fx= solved 0)
                        0.0
                        (clamp01 (fl* 0.8 (fl- surge far))))]
             [gold
              (cond
                [(fx= tile prism-crystal)
                 (let ([facet (fl+ (fl* 1.24 au) av)])
                   (fl+ (fl* (if lit? 1.0 0.65)
                             (fl+ (fl* 0.65 (band (flabs (fl- facet 0.32))
                                                  0.024))
                                  (fl* (band facet 0.30)
                                       (fl+ 0.25 (if (fl< u 0.0) 0.25 0.0)
                                            (if (fl< v 0.0) 0.25 0.0)))))
                        (if lit?
                            (fl/ (fl* (fl+ 0.12 (fl* 0.5 flare)) (fade edge))
                                 (fl+ 1.0 (fl* 30.0 r r)))
                            0.0)))]
                [(fx= tile prism-ring)
                 (fl+ (fl* (fl+ 0.8 (fl* 0.2 bloom))
                           (band (flabs (fl- r 0.31)) 0.025))
                      (fl* 0.5 (band (flabs (fl- r 0.21)) 0.014))
                      (cond
                        [(not lit?) 0.0]
                        [(fx= solved 0)
                         ;; reached while crystals are still dark: a
                         ;; weak, wavering light
                         (fl* (band r 0.13)
                              (fl+ 0.3 (fl* 0.12 (flsin (fl* 3.0 phase)))))]
                        [else
                         (fl+ (fl* (band r 0.13) (fl+ 0.55 (fl* 0.45 bloom)))
                              (fl/ (fl* 0.45 bloom (fade edge))
                                   (fl+ 1.0 (fl* 25.0 r r))))]))]
                [else 0.0])]
             [cursor (if (and (fx= selected i) (fl> (flmin au av) 0.31))
                         (band (flabs (fl- edge 0.43)) 0.012)
                         0.0)]
             [plate (fl+ 0.045
                         (fl* 0.022 (fl- 1.0 (fl/ gy (fixnum->flonum rows))))
                         (fl* 0.045 (band (flabs (fl- edge 0.48)) 0.006))
                         (fl* 0.02 (clamp01 (fl- 1.0 (fl* 1.6 r r)))))])
        (ink (fl+ 0.036 plate (fl* 0.58 steel) gold (fl* 0.36 beam) cursor
                  (fl* 0.8 violet))
             (fl+ 0.079 plate (fl* 0.87 steel) (fl* 0.62 gold) beam
                  (fl* 0.79 cursor) (fl* 0.62 violet))
             (fl+ 0.108 plate steel (fl* 0.19 gold) (fl* 0.91 beam)
                  (fl* 0.45 cursor) violet))))))
