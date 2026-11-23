;;; tests/units/boids3d.ss — Boids 3D, a demo, and what of the world it
;;; uses: its shaders on the device, checked against the twin, its picture,
;;; its keys, its frames and its timer.

;; Boids 3D's own names, b3:boids3d-steer and the rest (tests/reach.ss):
;; the app's, in (demo boids3d), and its parts', in demo/boids3d/.
(for-each (lambda (lib) (test-library lib 'b3:))
          '((demo boids3d rules) (demo boids3d shaders) (demo boids3d flock)
            (demo boids3d view) (demo boids3d)))

;; Boids 3D's files: the app's and its parts'.
(define b3-files
  (let ([dir (string-append *schevana-root* "/demo/boids3d")])
    (cons (string-append dir ".sls")
          (map (lambda (f) (string-append dir "/" f))
               (filter (lambda (f) (equal? (path-extension f) "sls"))
                       (sort string<? (directory-list dir)))))))

(check "Nothing in Boids 3D waits for the GPU or works on the crew: none \
        of its files names gpu-compute! nor gpu-buffer-read! nor \
        crew-for*; its rules window is no app's, the flock's own"
       (let* ([names (let walk ([x (map (lambda (f)
                                          (call-with-input-file f read))
                                        b3-files)]
                                [acc '()])
                       (cond [(symbol? x) (cons x acc)]
                             [(pair? x) (walk (cdr x) (walk (car x) acc))]
                             [(vector? x) (walk (vector->list x) acc)]
                             [else acc]))]
              [win (b3:boids3d)]
              [rw (find-window "Boids 3D — Rules")]
              [ok (and (memq 'gpu-compute-soon! names)
                       (not (memq 'gpu-compute! names))
                       (not (memq 'gpu-buffer-read! names))
                       (not (memq 'crew-for* names))
                       (eq? (window-app win) 'boids3d)
                       (not (window-app rw))
                       (eq? (window-owner rw) win))])
         (close-window! win)
         ok))

;;; ------------------------------------------------------------------ steps

;; A flock as the bytes a buffer holds (floats), and back.
(define (b3-bytes flock)
  (let ([bv (make-bytevector (* 4 b3:boids3d-words (length flock)) 0)])
    (for-each (lambda (b i)
                (for-each (lambda (v k)
                            (bytevector-ieee-single-native-set!
                             bv (* 4 (+ (* i b3:boids3d-words) k)) v))
                          b (iota b3:boids3d-words)))
              flock (iota (length flock)))
    bv))

(define (b3-flock bv n)
  (map (lambda (i)
         (map (lambda (k)
                (bytevector-ieee-single-native-ref
                 bv (* 4 (+ (* i b3:boids3d-words) k))))
              (iota b3:boids3d-words)))
       (iota n)))

;; A step of flock on the twin: the shader as Scheme, in floats.
(define (b3-twin-step flock rules)
  (let* ([n (length flock)]
         [in (b3-bytes flock)]
         [out (make-bytevector (bytevector-length in) 0)]
         [args (append (b3:boids3d-steering rules)
                       (list b3:boids3d-space 1.0))])
    (do ([i 0 (+ i 1)]) ((= i n))
      (apply (twin-procedure b3:boids3d-steer) i 0 n 1 in out n args))
    (b3-flock out n)))

;; n birds in a ball of radius r, heading anywhere, from a seed.
(define (b3-random-flock n r seed)
  (random-seed seed)
  (map (lambda (i)
         (append (map (lambda (k) (- (random (* 2.0 r)) r)) '(0 1 2))
                 (map (lambda (k) (- (random 4.0) 2.0)) '(0 1 2))
                 (list (random 6.2831853) (- (random 1.0) 0.5))))
       (iota n)))

;; Whether two flocks are the same, apart from floats' rounding.
(define (b3-close? a b)
  (for-all (lambda (x y)
             (for-all (lambda (u v)
                        (< (abs (- u v)) (* 1e-3 (max 1.0 (abs u)))))
                      x y))
           a b))

;; A step on the device (gpu-compute!), read back.
(define (b3-device-step flock rules)
  (let* ([n (length flock)]
         [in (make-gpu-buffer (* b3:boids3d-words n))]
         [out (make-gpu-buffer (* b3:boids3d-words n))])
    (let ([bytes (b3-bytes flock)])
      (do ([i 0 (+ i 1)]) ((= i (* b3:boids3d-words n)))
        (gpu-buffer-set! in i (bytevector-s32-native-ref bytes (* 4 i)))))
    (apply gpu-compute! b3:boids3d-steer n 1 in out n
           (append (b3:boids3d-steering rules) (list b3:boids3d-space 1.0)))
    (let ([next (b3-flock (gpu-buffer-read! out) n)])
      (gpu-buffer-release! in)
      (gpu-buffer-release! out)
      next)))

;; The same apart from rounding: a device may round a square root as it
;; likes, Metal included (tests/units/shader.ss holds the device to the
;; twin's +, -, * and / alone).
(check "Boids 3D: a step on the device is the twin's"
       (let* ([flock (b3-random-flock 200 300.0 7)]
              [rules (b3:boids3d-set-rule b3:boids3d-default-rules 'back-off
                                          0.1)])
         (b3-close? (b3-device-step flock rules) (b3-twin-step flock rules))))

(check "Boids 3D: each tile lists the birds whose boxes touch it, in order, \
        as many as it holds"
       (let* ([n 5]
              [most 3]
              [across 4]
              [down 2]
              [boxes '((1.0 1.0 3.0 3.0)        ; tile 0
                       (14.0 2.0 18.0 4.0)      ; tiles 0 and 1
                       (1.0 1.0 -1.0 -1.0)      ; behind the eye: none
                       (2.0 2.0 40.0 20.0)      ; the first three across
                       (0.0 0.0 5.0 5.0))]      ; tile 0, past its room
              [shapes (make-bytevector (* 4 b3:boids3d-shape-words n) 0)]
              [tiles (make-bytevector (* 4 across down (+ most 1)) 0)])
         (for-each (lambda (box i)
                     (for-each (lambda (v k)
                                 (bytevector-ieee-single-native-set!
                                  shapes
                                  (* 4 (+ (* i b3:boids3d-shape-words) k))
                                  v))
                               box (iota 4)))
                   boxes (iota n))
         (do ([t 0 (+ t 1)]) ((= t (* across down)))
           ((twin-procedure b3:boids3d-bin)
            (modulo t across) (quotient t across)
            across down shapes tiles n across most 16.0))
         (let ([tile (lambda (t)
                       (let* ([at (* t (+ most 1))]
                              [c (bytevector-s32-native-ref tiles (* 4 at))])
                         (map (lambda (k)
                                (bytevector-s32-native-ref
                                 tiles (* 4 (+ at 1 k))))
                              (iota c))))])
           (and (equal? (tile 0) '(0 1 3))
                (equal? (tile 1) '(1 3))
                (equal? (tile 2) '(3))
                (equal? (tile 3) '())
                (equal? (tile 6) '(3))
                (equal? (tile 7) '())))))

;;; ------------------------------------------------------------------ the app

;; Opens the flock window, paused, with its rules window closed and one
;; bird, at the middle of the ball, heading right across the camera's view,
;; with the camera level in front of it.
(define (b3-one-bird-window)
  (let ([win (b3:boids3d)])
    (close-window! (find-window "Boids 3D — Rules"))
    (window-call win 'key #\space '())
    (window-set! win 'count 1)
    (for-each (lambda (b)
                (for-each (lambda (v k) (gpu-buffer-set! b k v))
                          '(0.0 0.0 0.0 2.0 0.0 0.0 1.57 0.0) (iota 8)))
              (let ([bs (window-ref win 'buffers)]) (list (car bs) (cdr bs))))
    (window-set! win 'yaw 0.0)
    (window-set! win 'pitch 0.0)
    (window-set! win 'scene-bearing 3.14)   ; open sea, the sun behind
    (invalidate! win)
    (steps 2)
    win))

(check "Boids 3D draws an evening sky, dark at the top and warm at the \
        horizon, the sea under it darker, and a bird on it where the camera \
        sees it"
       (let* ([win (b3-one-bird-window)])
         (let-values ([(cx cy cw ch) (content-rect win)])
           (let* ([fh (- ch (max 26 (round (+ (font-line-height 'ui-small)
                                                13))))]
                  [mx (+ cx (quotient cw 2))]
                  [my (+ cy (quotient fh 2))]
                  [hy (+ cy (exact (floor (* fh (b3:boids3d-horizon 0.0)))))]
                  [red (lambda (p) (fxand (fxsrl p 16) 255))]
                  [light (lambda (p) (+ (fxand (fxsrl p 16) 255)
                                        (fxand (fxsrl p 8) 255)
                                        (fxand p 255)))]
                  [top (canvas-pixel mx (+ cy 2))]
                  [low (canvas-pixel mx (- hy 3))]
                  [sea (canvas-pixel mx (+ hy 30))]
                  [sky (canvas-pixel mx (- my 40))]
                  [darkest (apply min (map (lambda (dx)
                                             (apply min
                                                    (map (lambda (dy)
                                                           (light
                                                            (canvas-pixel
                                                             (+ mx dx)
                                                             (+ my dy))))
                                                         '(-2 -1 0 1 2))))
                                           '(-3 -2 -1 0 1 2 3)))])
             (close-window! win)
             (printf "  top ~x low ~x sea ~x sky ~a darkest ~a\n" top low sea
                     (light sky) darkest)
             (and (< (red top) (red low))
                  (< (light top) (light low))
                  (< (light sea) (light low))
                  (< darkest (- (light sky) 60)))))))

(check "Boids 3D: facing the sun, it sits on the horizon and lays a road on \
        the sea, brighter than the water beside it"
       (let ([win (b3-one-bird-window)])
         (window-set! win 'scene-bearing 0.0)
         (invalidate! win)
         (steps 2)
         (let-values ([(cx cy cw ch) (content-rect win)])
           (let* ([fh (- ch (max 26 (round (+ (font-line-height 'ui-small)
                                                13))))]
                  [mx (+ cx (quotient cw 2))]
                  [hy (+ cy (exact (floor (* fh (b3:boids3d-horizon 0.0)))))]
                  [light (lambda (p) (+ (fxand (fxsrl p 16) 255)
                                        (fxand (fxsrl p 8) 255)
                                        (fxand p 255)))]
                  [road (apply max (map (lambda (dy)
                                          (light (canvas-pixel mx (+ hy dy))))
                                        '(6 8 10 12 14)))]
                  [beside (light (canvas-pixel (+ mx 150) (+ hy 10)))]
                  [sun (light (canvas-pixel mx (- hy 2)))])
             (close-window! win)
             (printf "  sun ~a road ~a beside ~a\n" sun road beside)
             (and (> sun 600) (> road (+ beside 60)))))))

(check "Boids 3D: a drag turns the scene with the camera; the camera's own \
        circling leaves the scene where it is"
       (let* ([win (b3:boids3d)]
              [bearing (lambda () (window-ref win 'scene-bearing))]
              [start (bearing)])
         (close-window! (find-window "Boids 3D — Rules"))
         (let ([t (+ (now-ms) 40)]) (let loop () (when (< (now-ms) t) (loop))))
         (window-call win 'frame (now-ns))
         (let ([circled (window-ref win 'yaw)])
           (window-call win 'mouse-down 100 100 'left 1)
           (window-call win 'mouse-move 150 100)
           (window-call win 'mouse-up 150 100 'left)
           (let ([dragged (bearing)] [yaw (window-ref win 'yaw)])
             (close-window! win)
             (and (= start 1.39)
                  (> circled 0.6)
                  (< (abs (- dragged (- start 0.5))) 1e-9)
                  (< (abs (- yaw (- circled 0.5))) 1e-9))))))

(check "Boids 3D: space pauses the flock, h shows and hides the rules; a \
        closed window leaves no step waiting for the frame"
       (let* ([win (b3:boids3d)]
              [tick (lambda ()
                      (let ([t (+ (now-ms) 20)])
                        (let loop () (when (< (now-ms) t) (loop))))
                      (window-call win 'frame (now-ns)))]
              [flipped (lambda () (window-ref win 'flipped?))])
         (tick)
         (let* ([moving (let ([was (flipped)])
                          (tick)
                          (not (eq? was (flipped))))]
                [_ (window-call win 'key #\space '())]
                [still (let ([was (flipped)]) (tick) (eq? was (flipped)))]
                [rules? (find-window "Boids 3D — Rules")]
                [_ (window-call win 'key #\h '())]
                [hidden (not (find-window "Boids 3D — Rules"))])
           (b3:boids3d-step! win)
           (let ([waiting (map car (inspect-computes))])
             (close-window! win)
             (and moving still rules? hidden
                  (memq 'boids3d-steer waiting)
                  (not (memq 'boids3d-steer (map car (inspect-computes)))))))))

(check "Boids 3D: random rules are the rules, each within its range; what a \
        step is handed: a half view all round is -2, a rule without weight \
        reaches nothing"
       (let* ([rules (b3:boids3d-random-rules)]
              [all-round (b3:boids3d-set-rule
                          (b3:boids3d-set-rule b3:boids3d-default-rules
                                               'view-angle 360.0)
                          'cohesion 0.0)]
              [steering (b3:boids3d-steering all-round)])
         (and (equal? (map car b3:boids3d-ranges)
                      (let loop ([r rules])
                        (if (null? r) '() (cons (car r) (loop (cddr r))))))
              (for-all (lambda (range)
                         (<= (cadr range) (b3:boids3d-rule rules (car range))
                             (caddr range)))
                       b3:boids3d-ranges)
              (= (length steering) 15)
              (= (list-ref steering 5) -2.0)
              (= (list-ref steering 7) 0.0))))

(check "Boids 3D: its frames step the flock by time, a step a frame as far \
        as the time since the last, three steps' worth at most however \
        long; the camera turns by the same time"
       (let* ([win (b3:boids3d)]
              [yaw (lambda () (window-ref win 'yaw))]
              [t (+ (now-ns) 1000000000)])
         (close-window! (find-window "Boids 3D — Rules"))
         (let* ([y0 (yaw)]
                [late (begin (window-call win 'frame t) (- (yaw) y0))]
                [y1 (yaw)]
                [soon (begin (window-call win 'frame (+ t 5000000))
                             (- (yaw) y1))]
                [two (begin (window-call win 'frame (+ t 30000000))
                            (- (yaw) y1))])
           (close-window! win)
           (and (< (abs (- late (* 3 0.0015))) 1e-12)
                (< (abs (- soon (/ 0.0015 3))) 1e-12)
                (< (abs (- two (* 2 0.0015))) 1e-12)
                (not (hashtable-contains? (window-handlers win) 'tick))))))

;; Riding frames (the default), a minimized flock stays where it was.
;; Riding a timer (boids3d-ride!, the rules window's checkbox), it flies on,
;; asking for no frame, and its steps are sent to the GPU at the end of each
;; turn. Riding frames again, its timer stops.
(check "Boids 3D rides frames by default: minimized, its flock waits"
       (let* ([win (b3:boids3d)]
              [flipped (lambda () (window-ref win 'flipped?))])
         (close-window! (find-window "Boids 3D — Rules"))
         (steps 2)
         (minimize-window! win)
         (steps 1)
         (let ([was (flipped)])
           (steps 5)
           (let ([still (eq? was (flipped))])
             (close-window! win)
             (and still (eq? (window-ref win 'ride) 'frames))))))

(check "Boids 3D riding a timer flies on while minimized, asking for no \
        frame; riding frames again, its timer stops"
       (let* ([win (b3:boids3d)]
              [flips 0])
         (close-window! (find-window "Boids 3D — Rules"))
         (minimize-window! win)
         (steps 1)
         ;; only its own timers: the top bar's, once a second, asks for a
         ;; frame of its own
         ;; a copy, since after links a timer in place, behind any already
         ;; due, and so into these very cells on a machine running late
         (let ([before (list-copy *timers*)])
           (b3:boids3d-ride! 'timer)
           (window-call win 'frame (now-ns))   ; this sets its timer
           (let* ([own (remp (lambda (x) (memq x before)) *timers*)]
                  ;; the first of its 15 ms steps finds it due
                  [t (if (pair? own)
                         (- (vector-ref (car own) 0) 15)
                         (now-ms))])
             (fluid-let ([*timers* own] [now-ms (lambda () t)] [*dirty* #f])
               (do ([i 0 (+ i 1)]) ((= i 4))
                 (let ([was (window-ref win 'flipped?)])
                   (set! t (+ t 15))
                   (run-timers!)
                   (unless (eq? was (window-ref win 'flipped?))
                     (set! flips (+ flips 1)))))
               (let ([quiet (not *dirty*)] [queued (pair? *gpu-computes*)])
                 (b3:boids3d-ride! 'frames)
                 (set! t (+ t 15))
                 (run-timers!)
                 (let ([stopped (null? *timers*)] [had (pair? own)])
                   (steps 1)   ; the steps queued go to the GPU
                   (let ([sent (null? *gpu-computes*)]
                         [crashed (window-error win)])
                     (close-window! win)
                     (printf "  ~s\n" (list 'had had 'flips flips 'quiet quiet
                                           'queued queued 'stopped stopped
                                           'sent sent 'crashed crashed))
                     (and had (= flips 4) quiet queued stopped
                          sent)))))))))

(check "Boids 3D's home rule says what it does, and its Defaults button that \
        they make a murmuration"
       (let ([win (b3:boids3d)])
         (steps 2)
         (let* ([ui (window-ref (find-window "Boids 3D — Rules") 'ui)]
                [tip (lambda (id) (ui-region-tip (ui-find ui id)))]
                [ok (and (string-contains-ci? (tip 'home) "back to the middle")
                         (string-contains-ci? (tip 'defaults) "murmuration")
                         (not (tip 'scatter)))])
           (close-window! win)
           ok)))
