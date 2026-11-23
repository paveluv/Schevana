;;; (demo boids3d view) — what Boids 3D shows of a flock: the camera that
;;; circles it and the field drawn with each frame, where the shaders lay
;;; the flock out for the camera, list it by tile and paint it over the
;;; evening scene.

(library (demo boids3d view)
  (export boids3d-draw-field)
  (import (chezscheme)
          (schevana core)
          (demo boids3d shaders)
          (demo boids3d flock))

  (define boids3d-span 9.0)      ; a bird's wings, tip to tip, in units
  (define boids3d-haze 1400.0)   ; how far until the haze hides half a bird

  ;; The evening sky's colors, from its top to the horizon, and the birds'
  ;; ink: the scene's own colors, which no style's theme sets.
  (define boids3d-top #xff22385f)
  (define boids3d-middle #xff6f88aa)
  (define boids3d-low #xffe7bb93)
  (define boids3d-ink #xff17161d)

  ;; Returns the camera on a sphere around the flock's middle, looking at
  ;; it: its eye, then its axes right, up and ahead, as boids3d-place takes
  ;; them.
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

  ;; Returns the tiles' buffer, with room for at least words; it is made
  ;; again when the field outgrows it.
  (define (boids3d-tiles! win words)
    (let ([t (window-ref win 'tiles)])
      (if (and t (>= (cdr t) words))
          (car t)
          (let ([new (make-gpu-buffer words)])
            (when t (gpu-buffer-release! (car t)))
            (window-set! win 'tiles (cons new words))
            new))))

  ;; Draws the field, w × h: with the frame, the flock is laid out by the
  ;; camera and listed by tile, then the paint draws it over the scene,
  ;; seen at the window's scene bearing, with the horizon raised as the
  ;; camera looks down.
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
           [focal (* ph 1.07)]   ; 50° from the field's top to its bottom
           [turn 6.283185307179586]
           [left (- (window-ref win 'scene-bearing) (/ (/ pw 2.0) focal))]
           [ms (now-ms)]
           ;; a cloud cell drifts by in 150 s, with 20 cells around the sky
           [drift (/ ms 150000.0)])
      (apply gpu-compute-soon! boids3d-place n 1 (boids3d-current win) shapes
             (append (boids3d-camera (window-ref win 'yaw)
                                     (window-ref win 'pitch)
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

  ;; Returns the horizon's height, as a fraction of the field's, for the
  ;; camera's pitch: at the starting pitch, about seven tenths of the way
  ;; down.
  (define (boids3d-horizon pitch)
    (max 0.35 (min 0.95 (- 0.8 (* 1.07 (+ pitch 0.25)))))))
