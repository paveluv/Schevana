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
  (check (format "a record that needs another variant of the fragment shader \
                  starts a run, which draws with that one: ~s"
                 (inspect-list-runs l))
         (equal? (map (lambda (run)
                        (list (caddr run) (cadddr run)
                              (inspect-run-shader run)))
                      (inspect-list-runs l))
                 '((0 2 gfx-fragment)
                   (2 1 gfx-gradient-fragment)
                   (3 1 gfx-stipple-fragment)
                   (4 2 gfx-line-fragment)
                   (6 4 gfx-fragment))))
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

(check "the variant a record needs: the plain one for a box or glyph in a \
        solid color; one for a line, a shadow or a paint; the full one for a \
        line or shadow in a gradient or stipple"
       (let ([shader (lambda (kind paint)
                       (vector-ref gfx-fragments
                                   (rec-variant
                                    (fxior kind (fxsll paint 4)))))])
         (equal? (list (shader rec-kind-box rec-paint-solid)
                       (shader rec-kind-glyph rec-paint-solid)
                       (shader rec-kind-segment rec-paint-solid)
                       (shader rec-kind-polygon rec-paint-solid)
                       (shader rec-kind-shadow rec-paint-solid)
                       (shader rec-kind-glyph rec-paint-gradient)
                       (shader rec-kind-box rec-paint-stipple)
                       (shader rec-kind-box rec-paint-image)
                       (shader rec-kind-box rec-paint-shader)
                       (shader rec-kind-segment rec-paint-gradient)
                       (shader rec-kind-shadow rec-paint-stipple))
                 '(gfx-fragment
                   gfx-fragment
                   gfx-line-fragment
                   gfx-line-fragment
                   gfx-shadow-fragment
                   gfx-gradient-fragment
                   gfx-stipple-fragment
                   gfx-image-fragment
                   gfx-fragment
                   gfx-full-fragment
                   gfx-full-fragment))))

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

(check "the preview says what it holds on the GPU, its levels with it"
       (let* ([image (inspect-preview-image 4 4)]
              [bytes (inspect-preview-bytes image)])
         (inspect-preview-free! image)
         (= bytes (+ 64 16 4))))

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

(check "a run with records left out is cut around them"
       (equal? (inspect-runs-without '((m #f 0 10 0) (m #f 10 5 1))
                                     '((2 . 3) (9 . 2) (14 . 1)))
               '((m #f 0 2 0) (m #f 5 4 0) (m #f 11 3 1))))

(check "the preview leaves out the spans it's told to, by the frame's labels: \
        live, and of a frame kept"
       (let* ([image (inspect-preview-image *canvas-pw* *canvas-ph*)]
              [plain record-world!]
              [but (lambda (label)
                     (lambda (spans)
                       (map (lambda (s) (cons (cadr s) (caddr s)))
                            (filter (lambda (s) (equal? (car s) label))
                                    spans))))])
         (set! record-world! (lambda ()
                               (with-label ("one")
                                 (fill-box 0 0 10 10 #xff0000))
                               (with-label ("two")
                                 (fill-box 0 0 10 10 #x0000ff))))
         (inspect-preview! image (most-positive-fixnum) (but "two"))
         (request-frame!)
         (steps 1)
         (let ([live (pipeline-test-preview-pixel image 5 5)]
               [l (inspect-list)])
           (inspect-preview-list! image l (inspect-list-count l) (but "one"))
           (request-frame!)
           (steps 1)
           (let ([kept (pipeline-test-preview-pixel image 5 5)])
             (set! record-world! plain)
             (request-frame!)
             (steps 1)
             (inspect-preview-free! image)
             (and (= live #xffff0000) (= kept #xff0000ff))))))

(check "a list repainted: each record solid in its span's color over what it \
        covers, its runs those plain records need"
       (let* ([image (inspect-preview-image *canvas-pw* *canvas-ph*)]
              [plain record-world!]
              [green (color-word #x00ff00)] [white (color-word #xffffff)]
              [at (lambda (x) (exact (floor (* x *scale*))))])
         (set! record-world! (lambda ()
                               (with-label ("one")
                                 (fill-box 0 0 10 10 #xff0000))
                               (with-label ("two") (invert-box 0 0 5 10))))
         (request-frame!)
         (steps 1)
         (let* ([l (inspect-list)]
                [p (inspect-list-paint! (inspect-list-empty) l
                                        (lambda (i) (if (= i 0) green white))
                                        0)])
           (inspect-preview-list! image p (inspect-list-count p))
           (request-frame!)
           (steps 1)
           (let ([left (pipeline-test-preview-pixel image (at 2) (at 5))]
                 [right (pipeline-test-preview-pixel image (at 7) (at 5))])
             (set! record-world! plain)
             (request-frame!)
             (steps 1)
             (inspect-preview-free! image)
             (and (= (inspect-list-count p) 2)
                  (> (length (inspect-list-runs l)) 1)
                  (for-all (lambda (i) (eq? (inspect-paint p i) 'solid))
                           '(0 1))
                  (equal? (map (lambda (run) (list (car run) (cadr run)))
                               (inspect-list-runs p))
                          '((0 #f)))
                  (= left #xffffffff)
                  (= right #xff00ff00))))))

(check "a span's cost: the device pixels its records may touch within their \
        clips, the runs that start among them, and how many changed since a \
        frame before"
       (let* ([plain record-world!]
              [frame (lambda (color)
                       (set! record-world!
                         (lambda ()
                           (with-label ("one")
                             (fill-box 0 0 10 10 #xff0000)
                             (with-clip (0 0 5 10)
                               (fill-box 0 0 10 10 color)))
                           (with-label ("two") (invert-box 0 0 5 10))))
                       (request-frame!)
                       (steps 1)
                       (inspect-list))]
              [a (frame #x00ff00)] [b (frame #x00ff00)] [c (frame #x0000ff)]
              [device (* 150 *scale* *scale*)])
         (set! record-world! plain)
         (request-frame!)
         (steps 1)
         (let-values ([(one runs-one) (inspect-span-cost a 0 2)]
                      [(two runs-two) (inspect-span-cost a 2 1)])
           (and (<= device one (* 1.1 device))
                (= runs-one 1)
                (= runs-two 1)
                (= (inspect-span-changed b 0 2 a 0 2) 0)
                (= (inspect-span-changed c 0 2 b 0 2) 1)
                (= (inspect-span-changed c 0 2 b 0 1) 1)))))

;;; The frames kept.

;; A box in the color its buffer holds.
(define-paint (pipeline-test-paint x y)
  ([colors fx-buffer])
  (fx-ref colors 0))

(let* ([plain record-world!]
       [draw! (lambda (thunk)
                (set! record-world! thunk)
                (request-frame!)
                (steps 1))]
       [box-of (lambda (color)
                 (lambda ()
                   (with-label ("one") (fill-box 0 0 10 10 color))))]
       [red #xffff0000] [blue #xff0000ff]
       [h (inspect-history-new 8)])
  (draw! (box-of #xff0000))
  (inspect-history-add! h)
  (let* ([a (inspect-history-newest h)] [la (inspect-history-ref h a)]
         [a-bytes (vector-ref la 0)]
         [a-color (cdr (assq 'color (inspect-record la 0)))])
    (inspect-history-add! h)
    (check "a frame is kept once, with its records and who drew them"
           (and la (= (inspect-history-newest h) a)
                (= (inspect-list-frame la) a)
                (= (inspect-list-count la) 1)
                (equal? (inspect-list-labels la) '(("one" 0 1)))
                (= a-color red)
                (= (inspect-history-count h) 1)))
    (draw! (box-of #x0000ff))
    (inspect-history-add! h)
    (check "the frames before it stay as they were"
           (let ([lb (inspect-history-ref h (+ a 1))])
             (and (= (cdr (assq 'color (inspect-record lb 0))) blue)
                  (= (cdr (assq 'color (inspect-record la 0))) red))))
    (let ([image (inspect-preview-image *canvas-pw* *canvas-ph*)])
      (define (shown l count)
        (inspect-preview-list! image l count)
        (request-frame!)
        (steps 1)
        (pipeline-test-preview-pixel image 5 5))
      (check "a frame kept draws again, as far as a record, the screen having \
              moved on"
             (let ([one (shown la 1)] [none (shown la 0)])
               (and (= one red) (= none #xff000000))))
      ;; an image gone by now, in a frame kept
      (let ([gone (inspect-preview-image 4 4)])
        (draw! (lambda ()
                 (with-label ("one")
                   (fill-box 0 0 10 10 #xff0000)
                   (draw-image gone 0 0 10 10))))
        (inspect-history-add! h)
        (let ([l (inspect-history-ref h (inspect-history-newest h))])
          (draw! (box-of #x0000ff))
          (inspect-preview-free! gone)
          (check "an image let go of since a frame was kept is left out when \
                  it's drawn again, and says so, and can't hurt"
                 (and (= (inspect-list-left-out l) 1)
                      (= (inspect-list-left-out la) 0)
                      (= (shown l (inspect-list-count l)) red)))))
      ;; a paint, as the River's and the Tape's bands are
      (let ([colors (make-gpu-buffer 1)] [green #xff00ff00])
        (gpu-buffer-set! colors 0 green)
        (draw! (lambda ()
                 (with-label ("one")
                   (fill-box 0 0 10 10 #xff0000)
                   (fill-shader 0 0 10 10 pipeline-test-paint colors))))
        (inspect-history-add! h)
        (let ([l (inspect-history-ref h (inspect-history-newest h))])
          (draw! (box-of #x0000ff))
          (check "a paint kept with a frame draws again, from what its buffer \
                  holds"
                 (and (= (inspect-list-left-out l) 0)
                      (= (shown l (inspect-list-count l)) green)))
          (gpu-buffer-release! colors)
          (check "and once its buffer's let go of, it's left out, and says so"
                 (and (= (inspect-list-left-out l) 1)
                      (= (shown l (inspect-list-count l)) red)))))
      (inspect-preview-free! image))
    (do ([i 0 (+ i 1)]) ((= i 8))
      (draw! (box-of #x0000ff))
      (inspect-history-add! h))
    (check "the ring goes round: the oldest goes, and its buffers are used \
            again"
           (and (not (inspect-history-ref h a))
                (= (inspect-history-count h) 8)
                (> (inspect-history-bytes h) 0)
                (eq? (vector-ref (vector-ref (inspect-history-slots h)
                                             (modulo a 8))
                                 0)
                     a-bytes))))
  (set! record-world! plain)
  (request-frame!)
  (steps 1))

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
                [rows (pipeline-children v '("Pipeline" 0))])
           (and (pair? rows)
                (= (apply + (map (lambda (row) (pipeline-node-count v row))
                                 rows))
                   (caddr group)))))
  ;; A window below draws one box, then two, as a caret blinks: what the
  ;; Pipeline draws moves along by a record and back each time.
  (let* ([boxes 1]
         [below (open-window "Pipeline test boxes" 'size '(120 . 80)
                             'pos '(10 . 10) 'app 'pipeline-test
                             'draw (lambda (win w h)
                                     (do ([i 0 (+ i 1)]) ((= i boxes))
                                       (fill-box (* i 10) 0 8 8 'accent))))]
         [tree '(pipeline tree)]
         [row-of (lambda (name)
                   (let ([rows (ui-memo ui (list tree 'rows) '#())])
                     (find (lambda (r)
                             (equal? (pipeline-node-name (ui-tree-row-node r))
                                     name))
                           (vector->list rows))))]
         [look! (lambda ()
                  (invalidate! below)
                  (steps 1)
                  (pipeline-look! v)
                  (steps 1))])
    (focus-window! w)
    (look!)
    (let* ([rows (ui-memo ui (list tree 'rows) '#())]
           [i (let loop ([i 0])
                (if (equal? (pipeline-node-name
                             (ui-tree-row-node (vector-ref rows i)))
                            "Pipeline")
                    i
                    (loop (+ i 1))))]
           [r (ui-find ui (list tree 'row i))]
           [twisty (cdr (assq 'twisty
                              (ui-tree-areas (ui-region-x r) (ui-region-y r)
                                             (ui-region-w r) (ui-region-h r)
                                             0)))])
      (let-values ([(cx cy cw ch) (content-rect w)])
        (let ([x (exact (round (+ cx (car twisty) (/ (caddr twisty) 2))))]
              [y (exact (round (+ cy (cadr twisty) (/ (cadddr twisty) 2))))])
          (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                   `(mouse-up ,x ,y left))
          (steps 2))))
    (check "a press on a span's twisty opens it"
           (ui-tree-row-expanded? (row-of "Pipeline")))
    (check "and it stays open while records before it and in it come and go"
           (for-all (lambda (n)
                      (set! boxes n)
                      (look!)
                      (ui-tree-row-expanded? (row-of "Pipeline")))
                    '(2 1 2 1)))
    (pipeline-view-selected-set! v (ui-tree-row-node (row-of "Pipeline")))
    (check "a span selected stays so, its records marked where they are now"
           (for-all (lambda (n)
                      (set! boxes n)
                      (look!)
                      (and (equal? (ui-tree-row-node (row-of "Pipeline"))
                                   (pipeline-view-selected v))
                           (= (car (pipeline-tape-marked v))
                              (cadr (assoc "Pipeline"
                                           (pipeline-view-groups v))))))
                    '(2 1)))
    (pipeline-view-selected-set! v #f)
    (let* ([node '("Pipeline test boxes" 0)]
           [span (lambda () (assoc "Pipeline test boxes"
                                   (pipeline-view-groups v)))]
           [out? (lambda ()
                   (let ([kept (pipeline-kept v)] [span (span)])
                     (and (not (pipeline-kept-at kept (cadr span)))
                          (= (vector-length kept)
                             (- (inspect-list-count (pipeline-view-shown v))
                                (caddr span))))))])
      (press! (list 'pipeline 'shows node))
      (check "a span's checkbox off leaves its records out of the small screen \
              and the Tape, and its color out of the Tape's legend"
             (and (equal? (pipeline-view-off v) (list node))
                  (let ([given '()] [plain inspect-preview!])
                    (fluid-let ([inspect-preview!
                                 (lambda (image count . left-out)
                                   (set! given left-out)
                                   (apply plain image count left-out))])
                      (steps 2))
                    (and (pair? given) (car given)
                         (equal? ((car given) (pipeline-view-groups v))
                                 (list (cons (cadr (span)) (caddr (span)))))))
                  (out?)
                  (not (member "Pipeline test boxes"
                               (map cdr (pipeline-tape-keys v))))))
      (check "it stays out while records come and go"
             (for-all (lambda (n) (set! boxes n) (look!) (out?)) '(2 1)))
      (let* ([first (cadr (span))] [end (+ first (caddr (span)))])
        (pipeline-tape-go! v (pipeline-kept-upto
                              v (+ 1 (pipeline-kept-below (pipeline-kept v)
                                                          first))))
        (invalidate! w)
        (steps 1)
        (check "a press on the Tape goes to a record kept"
               (= (pipeline-view-upto v) (+ end 1)))
        (press! '((pipeline drawn) down))
        (check "and its stepper steps over the records left out"
               (= (pipeline-view-upto v) first)))
      (press! '(pipeline hold))
      (press! (list 'pipeline 'shows node))
      (check "on again, they're back"
             (and (null? (pipeline-view-off v))
                  (= (vector-length (pipeline-kept v))
                     (inspect-list-count (pipeline-view-shown v))))))
    ;; what's selected: kept with its drawer, named, cleared, shown
    (let ([before (map (lambda (n) (cons n (pipeline-color-index v n)))
                       (pipeline-span-nodes (pipeline-view-groups v)))])
      (focus-window! below)
      (look!)
      (check "a drawer keeps its color when it's raised: who it is, not its \
              place"
             (and (not (equal? (map car before)
                               (pipeline-span-nodes
                                (pipeline-view-groups v))))
                  (for-all (lambda (p)
                             (= (pipeline-color-index v (car p)) (cdr p)))
                           before)))
      (focus-window! w)
      (look!))
    (let ([pipe (lambda () (assoc "Pipeline" (pipeline-view-groups v)))])
      (pipeline-select! v (car (inspect-rows (pipeline-view-shown v)
                                             (+ (cadr (pipe)) 5) 1)))
      (set! boxes 3)
      (look!)
      (check "a record selected stays with its drawer, at its place in it, \
              as records before it come and go"
             (let ([selected (pipeline-view-selected v)])
               (and (vector? selected)
                    (= (vector-ref selected 0) (+ (cadr (pipe)) 5))
                    (equal? (pipeline-selected-span v) '("Pipeline" 0)))))
      (check "the Tape's heading names it, by its drawer, with a button that \
              clears it"
             (let* ([text (pipeline-selected-text v)] [n (string-length text)])
               (and (string=? (substring text (- n 12) n) " by Pipeline")
                    (ui-find ui '(pipeline unselect)))))
      (press! '(pipeline unselect))
      (check "Clear selects nothing, and the heading says what the Tape is"
             (and (not (pipeline-view-selected v))
                  (not (ui-find ui '(pipeline unselect)))))
      (pipeline-select! v '("Pipeline" 0))
      (inject! '(key-down escape ()))
      (steps 2)
      (check "and so does Esc" (not (pipeline-view-selected v))))
    (let ([first-of (lambda (name)
                      (car (inspect-rows
                            (pipeline-view-shown v)
                            (cadr (assoc name (pipeline-view-groups v))) 1)))])
      (pipeline-select! v (first-of "Pipeline test boxes"))
      (steps 1)
      (check "a record selected opens its drawer in the tree, its row shown \
              selected"
             (and (ui-tree-row-expanded? (row-of "Pipeline test boxes"))
                  (find (lambda (r)
                          (equal? (ui-tree-row-node r)
                                  (pipeline-tree-selected v)))
                        (vector->list
                         (ui-memo ui (list tree 'rows) '#())))))
      (pipeline-select! v (first-of 'topbar))
      (steps 1)
      (check "and closes it when another drawer's record is selected, as it \
              opens that one"
             (and (not (ui-tree-row-expanded? (row-of "Pipeline test boxes")))
                  (ui-tree-row-expanded? (row-of "topbar"))
                  (ui-tree-row-expanded? (row-of "Pipeline")))))
    ;; the tree as it was: at its top, the topbar closed
    (parameterize ([current-window w])
      (ui-tree-expand! ui tree '(topbar 0) #f))
    (pipeline-select! v '(desktop 0))
    (steps 1)
    (pipeline-select! v #f)
    (close-window! below)
    (steps 1))
  (let ([drawn '()] [plain ui-draw-cell])
    (fluid-let ([ui-draw-cell (lambda (x y w h flags text)
                                (set! drawn (cons text drawn))
                                (plain x y w h flags text))])
      (steps 2))
    (check "its cells are the kit's, so that they line up under their headings \
            and clear of each other"
           (member "Pipeline" drawn)))
  (press! '(pipeline viewer))
  (check "a press on the small screen lists the records at that pixel, the \
          top one selected"
         (let ([t (pipeline-view-traced v)])
           (and t (pair? (caddr t))
                (equal? (pipeline-view-selected v) (car (caddr t))))))
  (steps 1)
  (check "and they're drawn with no crash" (not (window-error w)))
  (press! '(pipeline untrace))
  (check "All goes back to the tree" (not (pipeline-view-traced v)))
  (press! '(pipeline viewer))
  (press! '(pipeline untrace))
  (press! '(pipeline hold))
  (check "Hold keeps the list on view"
         (let ([held (pipeline-view-shown v)])
           (pipeline-look! v)
           (and (pipeline-view-held? v) (eq? held (pipeline-view-shown v)))))
  (press! '(pipeline hold))
  ;; the River: a few ticks to go back through
  (steps 6)
  (let* ([history (pipeline-view-history v)]
         [river (pipeline-view-river v)])
    (check "the River flows while it's open: the frames are kept, the ticks \
            sent, each with its lanes"
           (let* ([seq (profile-newest-tick)]
                  [row (and (ui-stream-buffer river)
                            (ui-stream-row river (ui-stream-sent river)))])
             (and row (> (inspect-history-count history) 3)
                  (= (length row) (+ (length monitor-phases)
                                      (length pipeline-draw-lanes)))
                  (= ((pipeline-river-word (pacer-period)) seq
                      (length monitor-phases))
                     (if (profile-tick-late? seq (pacer-period)) 1 0)))))
    (check "the River's lanes say all's well in the chart-ok color, and each \
            label says what its colors mean, a bar's tooltip what they read"
           (let ([seq (profile-newest-tick)])
             (and (eq? (cadr (assoc "frame" pipeline-draw-lanes)) 'chart-ok)
                  (eq? (cadr (assoc "GPU" pipeline-draw-lanes)) 'chart-ok)
                  (= (length pipeline-lane-tips) (length pipeline-draw-lanes))
                  (for-all (lambda (i)
                             (ui-find ui (list 'pipeline-river 'strip i)))
                           (iota (length pipeline-draw-lanes)))
                  (string? (pipeline-tick-lanes seq)))))
    (check "the River's collector lane is as bright as the tick's collecting \
            took: faint however short, full from its most, in every style"
           (let* ([full pipeline-collector-full-ns]
                  [most pipeline-collector-levels]
                  [colors (cdr (assoc "collector" pipeline-draw-lanes))]
                  [opacity (lambda (c)
                             (let-values ([(r g b a) (color-rgba c)]) a))]
                  [j (+ (length monitor-phases) 3)]
                  [seq (profile-newest-tick)]
                  [word ((pipeline-river-word (pacer-period)) seq j)])
             (and (= (pipeline-collector-level 0) 1)
                  (= (pipeline-collector-level 1000) 1)
                  (= (pipeline-collector-level (quotient full 2)) 4)
                  (= (pipeline-collector-level full) most)
                  (= (pipeline-collector-level (* 100 full)) most)
                  (= (length colors) most)
                  (= word (if (> (profile-tick-ns seq 'gcs) 0)
                              (pipeline-collector-level
                               (profile-tick-ns seq 'gc-ns))
                              0))
                  (for-all
                   (lambda (s)
                     (with-style (style-name s)
                       (lambda ()
                         (and (< (opacity (car colors))
                                 (opacity (car (last-pair colors))))
                              (for-all fixnum? (map color-word colors))))))
                   *styles*))))
    ;; a press on the bar before the newest
    (let* ([r (ui-find ui '(pipeline-river))]
           [right (+ (ui-region-x r) (ui-region-w r) -1)])
      ((ui-region-on r) (list 'press (- right pipeline-bar-px) (ui-region-y r)
                              'left 1))
      (invalidate! w)
      (steps 2))
    (let* ([tick (pipeline-view-tick v)] [reach (pipeline-view-reach v)]
           [frames (inspect-history-newest history)])
      (check "a press on the River holds it and goes back to that tick's \
              frame: the whole app shows it"
             (and (pipeline-view-held? v) tick
                  (= (inspect-list-frame (pipeline-view-shown v))
                     (pipeline-tick-frame tick))
                  (not (window-error w))))
      (steps 3)
      (check "held, nothing moves on: its bars or the frames kept"
             (and (equal? reach (pipeline-view-reach v))
                  (= frames (inspect-history-newest history))
                  (not (window-error w))))
      ;; a drag to its newest bar
      (let* ([r (ui-find ui '(pipeline-river))]
             [right (+ (ui-region-x r) (ui-region-w r) -1)])
        ((ui-region-on r) (list 'drag right (ui-region-y r) 1))
        (steps 2)
        (check "a drag moves through them"
               (and (= (pipeline-view-tick v) (car reach))
                    (= (inspect-list-frame (pipeline-view-shown v))
                       (pipeline-tick-frame (car reach)))
                    (not (window-error w)))))
      (press! '(pipeline hold))
      (steps 3)
      (check "letting go of Hold, it flows on from now"
             (and (not (pipeline-view-held? v))
                  (not (pipeline-view-tick v))
                  (> (inspect-history-newest history) frames)
                  (> (ui-stream-sent river) (car reach))
                  (not (window-error w))))))
  ;; how often the small screen draws
  (let ([drawn (lambda (n)
                 (let ([calls 0] [plain inspect-preview!])
                   (fluid-let ([inspect-preview!
                                (lambda (image count . left-out)
                                  (set! calls (+ calls 1))
                                  (apply plain image count left-out))])
                     (steps n))
                   calls))])
    (check "the small screen draws every frame by default"
           (and (= (pipeline-view-every v) 1) (= (drawn 8) 8)))
    (press! '((pipeline every) up))
    (press! '((pipeline every) up))
    (press! '((pipeline every) up))
    (check "its control makes that as seldom as it's told"
           (and (= (pipeline-view-every v) 4)
                (<= 1 (drawn 8) 3)))
    (pipeline-view-every-set! v 1)
    (steps 1))
  ;; the Tape
  (pipeline-look! v)
  (steps 2)
  (let* ([l (pipeline-view-shown v)] [n (inspect-list-count l)]
         [tape (pipeline-view-tape v)]
         [who-base 0]
         [kind-base (length pipeline-draw-tape-who)])
    (check "the Tape holds a mark a record of the frame on view: how much it \
            may cover, who drew it, its kind"
           (and (> n 0)
                (eq? (pipeline-view-kept-of v) l)
                (eq? (pipeline-view-tape-of v) (pipeline-view-kept v))
                (= (ui-stream-sent tape) (- n 1))
                (let ([row (ui-stream-row tape 0)])
                  ;; record 0, the desktop's: as big as the screen
                  (and (> (car row) 1500)
                       (> (cadr row) who-base)
                       (= (caddr row)
                          (+ kind-base 1
                             (- (length pipeline-tape-kinds)
                                (length (memq (inspect-kind l 0)
                                              pipeline-tape-kinds)))))))))
    (press! '(pipeline-tape))
    (check "a press on the Tape holds the frame and draws it as far as that \
            record, which is selected"
           (let ([upto (pipeline-view-upto v)])
             (and (pipeline-view-held? v)
                  upto (< 0 upto n)
                  (= (pipeline-node-first v (pipeline-view-selected v))
                     (- upto 1))
                  (memv (- upto 1) (pipeline-tape-marked v)))))
    (let ([before (pipeline-view-upto v)])
      (press! '((pipeline drawn) down))
      (check "its stepper takes it a record at a time"
             (= (pipeline-view-upto v) (- before 1))))
    (pipeline-view-play-secs-set! v 1)
    (pipeline-tape-go! v 0)
    (press! '(pipeline play))
    (check "Play draws the frame record by record, from the start"
           (and (pipeline-view-playing v)
                (< 0 (pipeline-view-upto v) n)))
    (steps 90)
    (check "and stops at its end, all of it drawn"
           (and (not (pipeline-view-playing v))
                (not (pipeline-view-upto v))))
    (let ([span (car (pipeline-view-groups v))])
      (pipeline-view-selected-set!
       v (car (pipeline-span-nodes (pipeline-view-groups v))))
      (check "what's selected is marked, a span of records whole"
             (equal? (list-head (pipeline-tape-marked v) (caddr span))
                     (map (lambda (k) (+ (cadr span) k))
                          (iota (caddr span))))))
    (pipeline-view-selected-set! v #f)
    (pipeline-trace! v 5 5)
    (check "and so are the records at a pixel traced"
           (let ([traced (map (lambda (node) (pipeline-node-first v node))
                              (caddr (pipeline-view-traced v)))])
             (and (pair? traced)
                  (for-all (lambda (i) (memv i (pipeline-tape-marked v)))
                           traced))))
    (pipeline-view-traced-set! v #f)
    (press! '(pipeline hold))
    (steps 2)
    (check "and with Hold let go, it flows on, a mark a record of what's new"
           (and (not (pipeline-view-held? v))
                (eq? (pipeline-view-kept-of v) (pipeline-view-shown v))
                (eq? (pipeline-view-tape-of v) (pipeline-view-kept v)))))
  ;; Who, and the small screen showing who drew
  (press! '(pipeline who))
  (let* ([rows (pipeline-who-rows v)]
         [mine (find (lambda (r) (equal? (vector-ref r 0) '("Pipeline" 0)))
                     rows)])
    (check "Who has a row a drawer, in draw order, of what each cost: main's \
            time drawing it, its records, the pixels they may touch, the runs \
            they start"
           (and (eq? (pipeline-view-stage v) 'who)
                (not (window-error w))
                (equal? (map (lambda (r) (vector-ref r 0)) rows)
                        (pipeline-span-nodes (pipeline-view-groups v)))
                mine
                (> (vector-ref mine 2) 0)
                (= (vector-ref mine 3)
                   (caddr (assoc "Pipeline" (pipeline-view-groups v))))
                (> (vector-ref mine 4) 0)
                (>= (vector-ref mine 5) 1)))
    (press! (list '(pipeline who) 'row
                  (let loop ([rs rows] [i 0])
                    (if (eq? (car rs) mine) i (loop (cdr rs) (+ i 1))))))
    (check "a row pressed selects its drawer, everywhere"
           (equal? (pipeline-view-selected v) '("Pipeline" 0)))
    (pipeline-view-selected-set!
     v (car (inspect-rows (pipeline-view-shown v)
                          (cadr (assoc "Pipeline" (pipeline-view-groups v)))
                          1)))
    (check "and a record selected shows as its drawer's"
           (equal? (pipeline-selected-span v) '("Pipeline" 0))))
  (pipeline-view-selected-set! v #f)
  (check "Show offers the small screen's views"
         (equal? (map cdr pipeline-looks) '(picture who kind heat changed)))
  (pipeline-view-look-set! v 'who)
  (press! '(pipeline hold))
  (let* ([image (pipeline-view-image v)]
         [x (quotient *canvas-pw* 2)] [y (quotient *canvas-ph* 2)]
         [top (car (pipeline-records-at v x y))]
         [i (pipeline-color-index v (pipeline-span-node-at v top))]
         [color (color-word (pipeline-draw-who-color i))]
         [shown (lambda ()
                  (pipeline-preview! v)
                  (request-frame!)
                  (steps 1)
                  (pipeline-test-preview-pixel image x y))])
    (check "showing who drew, the small screen paints each record its \
            drawer's color"
           (and (eq? (pipeline-view-look v) 'who) (= (shown) color)))
    (pipeline-view-selected-set! v '(topbar 0))
    (check "the others dim while a drawer is selected"
           (= (shown) (color-word (mix (pipeline-draw-who-color i) 'bg-0
                                       0.75)))))
  (pipeline-view-selected-set! v #f)
  (let* ([l (pipeline-view-shown v)] [n (inspect-list-count l)]
         [paint (lambda (look)
                  (pipeline-view-look-set! v look)
                  (pipeline-painted v l))]
         [image (pipeline-view-image v)]
         [x (quotient *canvas-pw* 2)] [y (quotient *canvas-ph* 2)])
    (let ([p (paint 'kind)] [words (pipeline-draw-kind-words)])
      (check "Kind paints each record its kind's color, as the Tape's kind \
              lane"
             (for-all (lambda (i)
                        (= (fxand (inspect-word p i rec-row-paint) #xffffffff)
                           (fxand (cdr (assq (inspect-kind l i) words))
                                  #xffffffff)))
                      (iota n))))
    (let ([p (paint 'heat)])
      (pipeline-preview! v)
      (request-frame!)
      (steps 1)
      (check "Heat adds the records up, a pixel as bright as how many cover \
              it"
             (let ([red (fxand (fxsrl (pipeline-test-preview-pixel image x y)
                                      16)
                               255)])
               (and (for-all (lambda (run) (= (car run) 3))
                             (inspect-list-runs p))
                    (>= red 16)))))
    (let ([marks (pipeline-changed-marks v l)]
          [before (inspect-history-ref (pipeline-view-history v)
                                       (- (inspect-list-frame l) 1))])
      (check "Changed marks the records that differ from the frame before, \
              as many in each drawer as Who counts"
             (or (not before)
                 (for-all
                  (lambda (span node)
                    (let ([row (find (lambda (r) (equal? (vector-ref r 0) node))
                                     (pipeline-who-rows v))]
                          [marked (length
                                   (filter (lambda (k)
                                             (vector-ref marks
                                                         (+ (cadr span) k)))
                                           (iota (caddr span))))])
                      (or (not (vector-ref row 6))
                          (= marked (vector-ref row 6)))))
                  (inspect-list-labels l)
                  (pipeline-span-nodes (inspect-list-labels l)))))))
  (pipeline-view-look-set! v 'picture)
  (press! '(pipeline hold))
  (press! '(pipeline lists))
  ;; the viewer: zoomed, moved, magnified, popped out
  (let* ([r (ui-find ui '(pipeline viewer))]
         [vx (ui-region-x r)] [vy (ui-region-y r)]
         [vw (ui-region-w r)] [vh (ui-region-h r)]
         [mid (lambda (dx dy)
                (let-values ([(cx cy cw ch) (content-rect w)])
                  (list (exact (round (+ cx vx (/ vw 2) dx)))
                        (exact (round (+ cy vy (/ vh 2) dy))))))]
         [pixel-at (lambda (mx my)
                     (pipeline-viewer-pixel v vx vy vw vh mx my))])
    (check "the viewer starts showing all of the screen, filling its box one \
            way"
           (let ([a (pixel-at vx vy)] [b (pixel-at (+ vx vw) (+ vy vh))])
             ;; the box's size rounded: within a pixel or so
             (and (not (pipeline-view-zoom v))
                  (< (car a) 2) (< (cdr a) 2)
                  (> (car b) (- *canvas-pw* 2)) (> (cdr b) (- *canvas-ph* 2))
                  (or (and (< (abs (car a)) 2)
                           (< (abs (- (car b) *canvas-pw*)) 2))
                      (and (< (abs (cdr a)) 2)
                           (< (abs (- (cdr b) *canvas-ph*)) 2))))))
    (let* ([mx (+ vx (/ vw 4))] [my (+ vy (/ vh 3))]
           [before (pixel-at mx my)])
      (pipeline-zoom-at! v vx vy vw vh mx my 3)
      (check "zoomed at a point, the screen's pixel there stays put"
             (let ([after (pixel-at mx my)])
               (and (pipeline-view-zoom v)
                    (< (abs (- (car after) (car before))) 1/1000)
                    (< (abs (- (cdr after) (cdr before))) 1/1000)))))
    (pipeline-zoom-at! v vx vy vw vh vx vy -40)
    (check "zoomed out past all of it, it shows all of it"
           (not (pipeline-view-zoom v)))
    (apply (lambda (x y) (inject! `(mouse-move ,x ,y) '(wheel 0 2)))
           (mid 0 0))
    (steps 2)
    (check "the wheel zooms it"
           (pipeline-view-zoom v))
    (let ([center (pipeline-viewer-center v)] [traced (pipeline-view-traced v)])
      (apply (lambda (x y)
               (inject! `(mouse-move ,x ,y) `(mouse-down ,x ,y left 1)
                        `(mouse-move ,(+ x 30) ,(+ y 20))
                        `(mouse-up ,(+ x 30) ,(+ y 20) left)))
             (mid 0 0))
      (steps 2)
      (check "a drag moves it, and lists nothing"
             (and (< (car (pipeline-viewer-center v)) (car center))
                  (< (cdr (pipeline-viewer-center v)) (cdr center))
                  (eq? (pipeline-view-traced v) traced))))
    (press! '(pipeline actual))
    (check "100% is a pixel of the screen for a device pixel"
           (= (pipeline-view-zoom v) 1))
    (press! '(pipeline fit))
    (check "and Fit all of it again"
           (not (pipeline-view-zoom v)))
    (press! '(pipeline loupe))
    (apply (lambda (x y) (inject! `(mouse-move ,x ,y))) (mid 10 10))
    (steps 2)
    (check "with the loupe on, the pixels at the pointer are magnified, and it \
            says what's there"
           (and (pipeline-view-loupe? v)
                (not (window-error w))
                (string-prefix? "5, 7" (pipeline-loupe-caption v 5 7))))
    (press! '(pipeline loupe))
    (press! '(pipeline pop))
    (let ([pop (pipeline-view-popped v)])
      (check "popped out, it's in a window of its own above the Pipeline's, \
              the Pipeline keeping its place"
             (and pop
                  (eq? (window-owner pop) w)
                  (ui-find (window-ref pop 'ui) '(pipeline viewer))
                  (ui-find ui '(pipeline unpop))
                  (not (ui-find ui '(pipeline viewer)))
                  (eq? (find-window 'pipeline) w)))
      (focus-window! w)
      (steps 2)
      (check "focused, the Pipeline takes the keyboard, and stays below it"
             (and (eq? (focused-window) w)
                  (memq w (cdr (memq pop (windows))))
                  (not (window-error pop))))
      (close-window! pop)
      (steps 2)
      (check "closed, it's back in its place"
             (and (not (pipeline-view-popped v))
                  (ui-find ui '(pipeline viewer))
                  (not (ui-find ui '(pipeline unpop))))))
    (press! '(pipeline pop))
    ;; out of the way of the button under it
    (set-geometry! (pipeline-view-popped v) 0 0 200 150)
    (steps 2)
    (press! '(pipeline unpop))
    (check "and Bring it back closes it too"
           (and (not (pipeline-view-popped v))
                (ui-find ui '(pipeline viewer)))))
  ;; the small screen in the small screen: a flat box if it's left out, in a
  ;; list read since the selection's outline went
  (pipeline-view-selected-set! v #f)
  (steps 4)
  (pipeline-look! v)
  (let ([colors
         (lambda ()
           (let* ([image (pipeline-view-image v)]
                  [pw (inspect-preview-w image)]
                  [r *renderer*]
                  [cb (sdl-acquire-gpu-commands (renderer-device r))]
                  [bytes (gpu-read-texture! r cb (gpu-image-texture image)
                                            pw (inspect-preview-h image))]
                  [box (ui-find ui '(pipeline viewer))])
             (let-values ([(cx cy cw ch) (content-rect w)])
               (let ([x0 (exact (ceiling (* *canvas-ratio*
                                            (+ cx (ui-region-x box) 2))))]
                     [y0 (exact (ceiling (* *canvas-ratio*
                                            (+ cy (ui-region-y box) 2))))]
                     [n (exact (floor (* *canvas-ratio*
                                         (- (ui-region-w box) 4))))]
                     [m (exact (floor (* *canvas-ratio*
                                         (- (ui-region-h box) 4))))]
                     [seen (make-eqv-hashtable)])
                 (do ([y y0 (+ y 1)]) ((= y (+ y0 m)))
                   (do ([x x0 (+ x 1)]) ((= x (+ x0 n)))
                     (hashtable-set!
                      seen
                      (bytevector-u32-native-ref bytes (* 4 (+ x (* y pw))))
                      #t)))
                 (hashtable-size seen)))))])
    (check "the small screen shows itself, in the box it's drawn in"
           (> (colors) 8))
    (press! '(pipeline hold))
    (steps 2)
    (check "a frame kept can't, as it can't show any image"
           (= (colors) 1))
    (press! '(pipeline hold))
    (steps 3)
    (check "and letting go of Hold it does again"
           (> (colors) 8)))
  ;; the screen's size changes while a tick's draw waits
  (let ([front (pipeline-view-image v)]
        [waiting (begin (steps 1) (pipeline-tick! v w) *rec-preview*)])
    (fluid-let ([*canvas-pw* (+ *canvas-pw* 2)])
      (pipeline-image! v))
    (check "a new size draws on what's new, not on what's let go of"
           (and waiting
                (not (eq? (pipeline-view-image v) front))
                (eq? (car *rec-preview*) (pipeline-view-image v))
                (= (inspect-preview-w (pipeline-view-image v))
                   (+ *canvas-pw* 2))))
    (steps 2)
    (check "and comes back to the screen's own"
           (and (= (inspect-preview-w (pipeline-view-image v)) *canvas-pw*)
                (not (window-error w)))))
  (pipeline-view-stage-set! v 'screen)
  (invalidate! w)
  (steps 2)
  (check "the Screen stage draws its facts" (not (window-error w)))
  (pipeline-view-stage-set! v 'lists)
  (close-window! w)
  (steps 1)
  (check "closed, it lets its images and its River go"
         (and (not (pipeline-view-image v))
              (not (pipeline-view-back v))
              (not (ui-stream-buffer (pipeline-view-river v))))))

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
       (let* ([ring (monitor-ticks-stream)]
              [was (profile-on?)])
         (profile-on! #t)
         (steps 3)
         (let* ([newest (profile-newest-tick)]
                [sent (begin
                        (ui-stream-send! ring newest newest
                                         (monitor-tick-word (pacer-period)))
                        (ui-stream-sent ring))]
                [row (list-head (ui-stream-row ring newest)
                                (length monitor-phases))]
                [want (map (lambda (j)
                             (quotient (monitor-tick-phase-ns newest j) 1000))
                           (iota (length monitor-phases)))])
           (profile-on! was)
           (ui-stream-release! ring)
           (and (= sent newest) (equal? row want)))))
