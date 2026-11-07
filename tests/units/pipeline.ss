;;; tests/units/pipeline.ss — kits/inspect.ss reads what the recorder wrote,
;;; and the Pipeline shows it.

;; thunk drawn as a frame, and the list that frame leaves; the world's own
;; recording comes back.
(define (pipeline-test-list thunk)
  (let ([plain record-world!])
    (set! record-world! thunk)
    (request-frame!)
    (steps 1)
    (set! record-world! plain)
    (let ([l (inspect-list)])
      (request-frame!)
      (steps 1)
      l)))

(define (pipeline-test-field record key) (cdr (assq key record)))

(check "the reader's names for kinds and paints are the recorder's numbers"
       (and (eq? (vector-ref inspect-kinds rec-kind-box) 'box)
            (eq? (vector-ref inspect-kinds rec-kind-segment) 'segment)
            (eq? (vector-ref inspect-kinds rec-kind-polygon) 'polygon)
            (eq? (vector-ref inspect-kinds rec-kind-glyph) 'glyph)
            (eq? (vector-ref inspect-kinds rec-kind-shadow) 'shadow)
            (eq? (vector-ref inspect-paints rec-paint-solid) 'solid)
            (eq? (vector-ref inspect-paints rec-paint-gradient) 'gradient)
            (eq? (vector-ref inspect-paints rec-paint-stipple) 'stipple)
            (eq? (vector-ref inspect-paints rec-paint-image) 'image)
            (eq? (vector-ref inspect-paints rec-paint-shader) 'shader)))

(let* ([l (pipeline-test-list
           (lambda ()
             (with-label ("boxes")
               (fill-box 10 20 30 40 #x112233)
               (with-clip (15 25 5 5)
                 (stroke-box 10 20 30 40 #x445566 2 6))
               (fill-box 0 0 8 8 (linear-gradient 0 0 8 0 #x000000 #xffffff))
               (fill-box 0 0 8 8 (stipple #x000000 #f "#.")))
             (with-label ("lines")
               (draw-line 0 0 10 0 #x778899 2)
               (fill-polygon '((0 . 0) (10 . 0) (0 . 10)) #x778899))
             (with-label ("words")
               (draw-text 100 100 "Hi" #xaabbcc 'ui)
               (draw-text 100 200 "Lo" #xaabbcc 'ui))))]
       [record (lambda (i) (inspect-record l i))])
  (check (format "a box reads back: ~s" (record 0))
         (let ([r (record 0)])
           (and (eq? (pipeline-test-field r 'kind) 'box)
                (eq? (pipeline-test-field r 'paint) 'solid)
                (= (pipeline-test-field r 'color) #xff112233)
                (equal? (pipeline-test-field r 'reach)
                        (map (lambda (v) (* v 1.0))
                             (map (lambda (v) (* v *scale*))
                                  '(10 20 40 60))))
                (not (pipeline-test-field r 'clip)))))
  (check (format "a line and a radius read back, and a clip: ~s" (record 1))
         (let ([r (record 1)])
           (and (> (pipeline-test-field r 'line) 0)
                (> (pipeline-test-field r 'radius) 0)
                (equal? (list-head (pipeline-test-field r 'clip) 4)
                        (map (lambda (v) (* v *scale* 1.0))
                             '(15 25 20 30))))))
  (check "a square clip reads back the rounded box it lies in"
       (let ([clip (pipeline-test-field
                    (inspect-record
                     (pipeline-test-list
                      (lambda ()
                        (with-clip (10 10 40 40 5)
                          (with-clip (20 20 10 10)
                            (fill-box 20 20 5 5 #x112233)))))
                     0)
                    'clip)])
         (equal? clip
                 (map (lambda (v) (* v *scale* 1.0))
                      '(20 20 30 30 5 10 10 50 50)))))

(check "paints read back by name; a segment and a polygon by kind"
         (and (eq? (pipeline-test-field (record 2) 'paint) 'gradient)
              (eq? (pipeline-test-field (record 3) 'paint) 'stipple)
              (eq? (pipeline-test-field (record 4) 'kind) 'segment)
              (eq? (pipeline-test-field (record 5) 'kind) 'polygon)))
  (check (format "labels span what's drawn inside them: ~s"
                 (inspect-list-labels l))
         (equal? (inspect-list-labels l)
                 '(("boxes" 0 4) ("lines" 4 2) ("words" 6 4))))
  (check "a run of glyphs reads as its text; another baseline is another row"
         (equal? (map (lambda (row) (vector-ref row 3))
                      (inspect-rows l 6 4))
                 '("Hi" "Lo")))
  (check "the records at a pixel come with the one on top first"
         (equal? (inspect-records-at l (exact (round (* 16 *scale*)))
                                     (exact (round (* 26 *scale*))))
                 '(1 0)))
  (check "a pixel its clip cuts away isn't one a record touches"
         (equal? (inspect-records-at l (exact (round (* 35 *scale*)))
                                     (exact (round (* 55 *scale*))))
                 '(0))))

(check "the frames kept say what each held, and every one was shown"
       (begin
         (request-frame!)
         (steps 1)
         (let ([f (car (inspect-frames 1))])
           (and (= (cadr f) (rec-count))
                (= (caddr f) *rec-extra-at*)
                (> (list-ref f 4) 0)
                (list-ref f 5)
                (<= (length (inspect-frames 100000)) frame-ring-rows)))))

(check "what the device and the GPU hold reads back"
       (and (eq? (cdr (assq 'renderer (inspect-device))) gpu-windowless-kind)
            (> (cdr (assq 'glyphs (inspect-glyphs))) 0)
            (for-all (lambda (o) (>= (cddr o) 0)) (inspect-gpu-objects))))

;; The preview's pixel at device x, y.
(define (pipeline-test-preview-pixel image x y)
  (let* ([r *renderer*]
         [w (inspect-preview-w image)]
         [cb (sdl-acquire-gpu-commands (renderer-device r))]
         [bytes (gpu-read-texture! r cb (gpu-image-texture image)
                                   w (inspect-preview-h image))])
    (bytevector-u32-native-ref bytes (* 4 (+ x (* y w))))))

(check "the preview draws the list as far as a record: the same draw, cut"
       (let* ([image (inspect-preview-image *canvas-pw* *canvas-ph*)]
              [plain record-world!]
              [at (lambda (count)
                    (inspect-preview! image count)
                    (request-frame!)
                    (steps 1)
                    (pipeline-test-preview-pixel image 5 5))])
         (set! record-world! (lambda ()
                               (fill-box 0 0 10 10 #xff0000)
                               (fill-box 0 0 10 10 #x0000ff)))
         (let ([none (at 0)] [one (at 1)] [two (at 2)])
           (set! record-world! plain)
           (request-frame!)
           (steps 1)
           (inspect-preview-free! image)
           (and (= none #xff000000) (= one #xffff0000) (= two #xff0000ff)))))

;;; The app.

(let* ([w (pipeline)] [v (window-ref w 'state)] [ui (window-ref w 'ui)]
       [press! (lambda (id)
                 (let ([r (ui-find ui id)])
                   (let-values ([(cx cy cw ch) (content-rect w)])
                     (let ([x (exact (round (+ cx (ui-region-x r)
                                               (/ (ui-region-w r) 2))))]
                           [y (exact (round (+ cy (ui-region-y r)
                                               (/ (ui-region-h r) 2))))])
                       (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                                `(mouse-up ,x ,y left))
                       (steps 2)))))])
  (steps 3)
  (pipeline-look! v)
  (check "the Pipeline opens on the list, by who drew it, itself among them"
         (and (not (window-error w))
              (eq? (pipeline-view-stage v) 'lists)
              (assoc "Pipeline" (pipeline-view-groups v))))
  (check "it opens the one window it has, again"
         (eq? (pipeline) w))
  (check "a label's children are its records"
         (let* ([group (assoc "Pipeline" (pipeline-view-groups v))]
                [rows (pipeline-children v group)])
           (and (pair? rows)
                (= (apply + (map pipeline-node-count rows)) (caddr group)))))
  (press! '(pipeline screen))
  (check "a press on the small screen lists the records at that pixel, the \
          top one selected"
         (let ([t (pipeline-view-traced v)])
           (and t (pair? (caddr t))
                (equal? (pipeline-view-selected v) (car (caddr t))))))
  (steps 1)
  (check "and they're drawn with no crash" (not (window-error w)))
  (press! '(pipeline untrace))
  (check "All goes back to the tree" (not (pipeline-view-traced v)))
  (press! '(pipeline screen))
  (press! '(pipeline untrace))
  (press! '(pipeline hold))
  (check "Hold keeps the list on view"
         (let ([held (pipeline-view-shown v)])
           (pipeline-look! v)
           (and (pipeline-view-held? v) (eq? held (pipeline-view-shown v)))))
  (press! '(pipeline hold))
  (pipeline-view-stage-set! v 'screen)
  (invalidate! w)
  (steps 2)
  (check "the Screen stage draws its facts" (not (window-error w)))
  (pipeline-view-stage-set! v 'lists)
  (close-window! w)
  (steps 1)
  (check "closed, it lets its image go" (not (pipeline-view-image v))))

;;; Recording itself.

;; The bytes thunk allocates, the least of a few calls: one may share its
;; time with a stray collection's bookkeeping.
(define (pipeline-test-bytes thunk)
  (thunk)
  (let loop ([i 0] [least #f])
    (if (= i 5)
        least
        (let ([b0 (bytes-total)])
          (thunk)
          (let ([b (- (bytes-total) b0)])
            (loop (+ i 1) (if least (min least b) b)))))))

(check "recording whole numbers allocates nothing: boxes, a solid paint from \
        a key, text, clips, translations"
       (begin
         (rec-begin! 1)
         (let ([n (pipeline-test-bytes
                   (lambda ()
                     (rec-begin! 1)
                     (do ([i 0 (fx+ i 1)]) ((fx= i 200))
                       (fill-box i 2 30 40 #x112233)
                       (stroke-box i 2 30 40 #x112233)
                       (with-clip (i 2 30 40)
                         (with-translation (1 2)
                           (fill-box 0 0 3 4 'accent))))
                     (draw-text 10 10 "Recording allocates nothing" 'text 'ui)
                     (rec-begin! 1)))])
           (printf "  ~a bytes a pass\n" n)
           (< n 512))))

;;; Monitor's Ticks, by a paint: a tick is a row of numbers.

(check "a new tick costs Monitor's Ticks a row on the GPU and one record"
       (let* ([ring (make-gpu-buffer (* monitor-ring-rows monitor-ring-words))]
              [was (profile-on?)])
         (profile-on! #t)
         (steps 3)
         (let* ([newest (profile-newest-tick)]
                [sent (monitor-ring-send! ring -1 newest (pacer-period))]
                [at (* monitor-ring-words (modulo newest monitor-ring-rows))]
                [row (map (lambda (j) (gpu-buffer-ref ring (+ at j)))
                          (iota (- monitor-ring-words 1)))]
                [want (map (lambda (j)
                             (quotient (monitor-tick-phase-ns newest j) 1000))
                           (iota (- monitor-ring-words 1)))])
           (profile-on! was)
           (gpu-buffer-release! ring)
           (and (= sent newest) (equal? row want)))))
