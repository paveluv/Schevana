;;; (demo boids3d rules) — Boids 3D's flocking rules, as data: their
;;; defaults and their ranges, rules picked at random, one rule changed,
;;; and what a step's shader is handed of them.

(library (demo boids3d rules)
  (export boids3d-default-rules boids3d-rule boids3d-ranges
          boids3d-random-rules boids3d-set-rule boids3d-steering)
  (import (chezscheme)
          (schevana core))

  ;; The flocking rules, as a plist: Boids' rules, plus home, how hard a
  ;; bird outside the space turns back. Speeds are in units per step; the
  ;; space is a ball of radius boids3d-space. Boids' own defaults, which see
  ;; only ahead and keep the birds hardly apart, string a flock out in
  ;; lines; these make a murmuration of it, a sheet that bends and thins as
  ;; it turns: cohesion is weak and wide, alignment near, there is room
  ;; between the birds, and they see most of the way around.
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

  ;; Returns rules picked at random within their ranges, as Boids picks
  ;; them: a weight as the cube of a uniform pick, and max speed from min
  ;; speed up.
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

  ;; Returns rules with key set to v; min and max speed push each other
  ;; along.
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

  ;; Returns what a step's shader is handed of the rules, in the order of
  ;; its parameters: the weights; the cosines of half the field of view and
  ;; of half the blockers' cone (-2 for all around, which any heading
  ;; beats); the squared reaches, 0 for a rule without weight; home; and
  ;; the speed limits.
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
              (list (rule 'home) (rule 'min-speed) (rule 'max-speed))))))
