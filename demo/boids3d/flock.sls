;;; (demo boids3d flock) — a flock of Boids 3D: its two buffers, new birds
;;; scattered into them, and the flock in a window, stepped from one
;;; buffer into the other with the next frame. Also what the keys and the
;;; rules window do to the flock in a window: new rules, the defaults, a
;;; scatter, a new count, and how it rides. The flock lives in the
;;; window's properties, so whoever changes it, the other parts see it.

(library (demo boids3d flock)
  (export boids3d-buffers boids3d-current boids3d-step! boids3d-randomize!
          boids3d-defaults! boids3d-scatter! boids3d-resize!
          boids3d-set-ride!)
  (import (chezscheme)
          (schevana core)
          (demo boids3d rules)
          (demo boids3d shaders))

  ;; Returns a flock's two buffers, each with room for boids3d-most birds:
  ;; a step reads one and writes the other.
  (define (boids3d-buffers)
    (cons (make-gpu-buffer (* boids3d-words boids3d-most))
          (make-gpu-buffer (* boids3d-words boids3d-most))))

  ;; Returns a point picked evenly in the ball of radius r.
  (define (boids3d-random-in-ball r)
    (let loop ()
      (let ([x (- (random 2.0) 1.0)]
            [y (- (random 2.0) 1.0)]
            [z (- (random 2.0) 1.0)])
        (if (> (+ (* x x) (* y y) (* z z)) 1.0)
            (loop)
            (list (* r x) (* r y) (* r z))))))

  ;; Writes new birds, from index `from` up to `to`, into both buffers,
  ;; since a step waiting for the frame may read either: placed in the
  ;; ball, heading anywhere, their wings anywhere in a beat.
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

  ;; Returns the buffer the newest step wrote, which the next step reads.
  (define (boids3d-current win)
    (let ([b (window-ref win 'buffers)])
      (if (window-ref win 'flipped?) (cdr b) (car b))))

  ;; Steps the flock in win with the next frame, from the current buffer
  ;; into the other, which then becomes current. dt is how much of a step
  ;; to take (1.0 is a whole one), in steering and in flight alike, so that
  ;; the flock turns and flies as far as the time that passed, however
  ;; often it is stepped.
  (define (boids3d-step! win . dt)
    (let* ([b (window-ref win 'buffers)]
           [from (boids3d-current win)]
           [to (if (eq? from (car b)) (cdr b) (car b))]
           [n (window-ref win 'count)])
      (apply gpu-compute-soon! boids3d-steer n 1 from to n
             (append (boids3d-steering (window-ref win 'rules))
                     (list boids3d-space (if (pair? dt) (car dt) 1.0))))
      (window-set! win 'flipped? (not (window-ref win 'flipped?)))))

  ;; What the keys and the rules window's buttons do to the flock in win.
  (define (boids3d-randomize! win)
    (window-set! win 'rules (boids3d-random-rules)))
  (define (boids3d-defaults! win)
    (window-set! win 'rules boids3d-default-rules))
  (define (boids3d-scatter! win)
    (boids3d-scatter-into! (window-ref win 'buffers) 0 (window-ref win 'count)))

  ;; Sets the flock to n birds: the first n of it, or all of it plus
  ;; newcomers.
  (define (boids3d-resize! win n)
    (let ([was (window-ref win 'count)])
      (when (> n was)
        (boids3d-scatter-into! (window-ref win 'buffers) was n))
      (window-set! win 'count n)))

  ;; Sets whether the flock in win steps with its frames, pausing while it
  ;; is unseen (frames, the default), or on a timer, flying on while hidden
  ;; (timer).
  (define (boids3d-set-ride! win mode)
    (unless (memq mode '(frames timer))
      (errorf 'boids3d-set-ride! "frames or timer, not ~s" mode))
    (window-set! win 'ride mode)
    (window-frame-soon! win)))
