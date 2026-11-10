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

(check "a deep pass never touches the world"
       (let ([world (bytes-allocated 4)])
         (collector-pass! 3 3)
         (= (bytes-allocated 4) world)))

(check "a reload frees the world it replaces"
       (let ([world (begin (collector-settle!) (bytes-allocated 4))])
         (reload!)
         (< (bytes-allocated 4) (+ world (quotient world 4)))))
