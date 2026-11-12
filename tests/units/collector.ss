;;; tests/units/collector.ss — the world waits in the oldest generation, and
;;; a pause is what survived since the last one.

(define (collector-young)
  (+ (bytes-allocated 0) (bytes-allocated 1)))

(check "after boot the world is in the oldest generation"
       (begin
         (collector-settle!)
         (and (> (bytes-allocated 4) (* 8 1024 1024))
              (< (+ (collector-young) (collector-old))
                 (quotient (bytes-allocated 4) 4)))))

(check "a request collects only the young"
       (let ([world (bytes-allocated 4)])
         (do ([i 0 (+ i 1)]) ((= i 1000000)) (cons i i))
         (collect-rendezvous)
         (and (= (bytes-allocated 4) world)
              (< (bytes-allocated 0) (* 1024 1024)))))

(check "what survives a request moves to the next generation, no further"
       ;; before first: so much allocated may bring a request by itself
       (let* ([before (bytes-allocated 1)]
              [kept (make-bytevector (* 4 1024 1024) 1)])
         (collect-rendezvous)
         (let ([grown (- (bytes-allocated 1) before)])
           (and (>= grown (* 4 1024 1024))
                (< (bytes-allocated 2) (* 1024 1024))
                (= 1 (bytevector-u8-ref kept 0))))))

(check "while nobody is typing, a grown young generation is collected"
       (let ([kept (make-bytevector (* 2 collector-young-quiet) 1)])
         (collect-rendezvous)
         (set! *collector-check-ms* 0)
         (set! *collector-input-ms* (- (now-ms) 2000))
         (set! *input-step?* #f)
         (let ([before (bytes-allocated 1)])
           (collector-tick!)
           (and (>= before collector-young-quiet)
                (< (bytes-allocated 1) collector-young-quiet)
                (= 1 (bytevector-u8-ref kept 0))))))

(check "while someone is typing, it waits for its limit"
       (let ([kept (make-bytevector (* 2 collector-young-quiet) 1)])
         (collect-rendezvous)
         (set! *collector-check-ms* 0)
         (set! *input-step?* #t)
         (let ([before (bytes-allocated 1)])
           (collector-tick!)
           (set! *input-step?* #f)
           (and (= (bytes-allocated 1) before)
                (= 1 (bytevector-u8-ref kept 0))))))

(check "GPU bytes made count as old growth: past the limit an old pass \
        comes, and finds a buffer dropped after it grew old"
       (let* ([held (box (make-gpu-buffer 4))]
              [release (list 'release (gpu-buffer-id (unbox held)))]
              [let-go? (lambda ()
                         (gpu-held-sweep!)
                         (and (member release *gpu-jobs*) #t))])
         (collector-pass! 1 2)
         (set-box! held #f)
         (collect-rendezvous)
         (let ([young (let-go?)])
           (set! *collector-check-ms* 0)
           (set! *collector-input-ms* (- (now-ms) 2000))
           (set! *input-step?* #f)
           (set! *gpu-bytes-made* (+ *gpu-bytes-made* collector-old-quiet))
           (collector-tick!)
           (and (not young)
                (let-go?)
                (= *collector-old-kept* (collector-grown))))))

(let* ([counts '()]
       [note! (lambda () (set! counts (cons (collections) counts)))]
       [win (open-window "Hog" 'size '(80 . 60)
                         ;; some 17 MB, past the trip many times over
                         'draw (lambda (win w h)
                                 (note!)
                                 (let loop ([i 0] [keep '()])
                                   (when (< i 200000)
                                     (loop (+ i 1)
                                           (cons (make-vector 8)
                                                 (if (> (length keep) 10)
                                                     '()
                                                     keep)))))
                                 (note!)))])
  (steps 1)
  (set! counts '())
  (let ([present rec-present!])
    (fluid-let ([rec-present! (lambda () (note!) (present))])
      (invalidate! win)
      (steps 1)))
  (let ([after (collections)] [seen (reverse counts)])
    (close-window! win)
    (check (format "a collection asked for in a frame turn waits till its \
                    frame is out (collections at the draw's start and \
                    end, at the publish, after: ~a ~a)" seen after)
           (and (= (length seen) 3)
                (apply = seen)
                (> after (car seen))))))

;; core0 on a thread of its own gives a frame back once it's sent: till
;; then, the collection its turn held off waits, as it would stop core0
(let ([win (open-window "Hog" 'size '(80 . 60)
                        'draw (lambda (win w h)
                                (let loop ([i 0] [keep '()])
                                  (when (< i 200000)
                                    (loop (+ i 1)
                                          (cons (make-vector 8)
                                                (if (> (length keep) 10)
                                                    '()
                                                    keep)))))))]
      [back render-frames-back!])
  (steps 1)
  (let* ([before (collections)]
         [waiting (fluid-let ([render-frames-back! (lambda () #f)])
                    (invalidate! win)
                    (steps 1)
                    (collections))])
    (back)
    (collector-after-sent!)
    (let ([after (collections)])
      (close-window! win)
      (check (format "a collection a frame turn held off waits till core0 \
                      has sent its frame, then runs (collections before, \
                      while it's out, once it's back: ~a ~a ~a)"
                     before waiting after)
             (and (= waiting before) (> after waiting))))))

(check "a deep pass never touches the world"
       (let ([world (bytes-allocated 4)])
         (collector-pass! 3 3)
         (= (bytes-allocated 4) world)))

(check "a reload frees the world it replaces"
       (let ([world (begin (collector-settle!) (bytes-allocated 4))])
         (reload!)
         (< (bytes-allocated 4) (+ world (quotient world 4)))))

(check "a collection, which every thread waits for, is traced: its start \
        by the generation collected, and its end"
       (let ([traced '()])
         (fluid-let ([host-trace! (lambda (code a)
                                    (set! traced (cons (cons code a) traced)))]
                     [*collector-holding?* #f]
                     [*collector-pass* #f])
           (collector-collect!))
         (equal? (reverse traced) '((28 . 0) (29 . 0)))))
