;;; tests/units/collector.ss — the world waits in the oldest generation,
;;; and a pause costs what has survived since the last one, not what the
;;; heap holds.

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
       ;; before is read first: allocating this much may bring a request
       ;; by itself
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

(check "the loader lets the collector look after each source it loads, as \
        a step of the loop does: the look finds what the load left in the \
        young generations, and collects it"
       (let ([file (path-full (string-append out-dir "/collector-load.ss"))]
             [left (* 2 collector-young-quiet)]
             [look collector-tick!]
             [found #f])
         ;; a source that leaves 16 MB behind: a request finds the bytes
         ;; alive and moves them on a generation, and then nothing holds
         ;; them
         (call-with-output-file file
           (lambda (p)
             (write `(let ([kept (make-bytevector ,left 1)])
                       (collect-rendezvous)
                       (bytevector-u8-ref kept 0))
                    p))
           'replace)
         (set! *collector-check-ms* 0)
         (set! *collector-input-ms* (- (now-ms) 2000))
         (set! *input-step?* #f)
         (fluid-let ([collector-tick! (lambda ()
                                        (set! found (bytes-allocated 1))
                                        (look))])
           (load-sources! (list file)))
         (and found
              (>= found left)
              (< (bytes-allocated 1) collector-young-quiet))))

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
                         ;; some 17 MB, many times past the collect trip
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

;; core0 on a thread of its own gives a frame back once it has sent it:
;; until then, the collection that the frame's turn held off waits, since
;; it would stop core0
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
         (fluid-let ([core0-trace! (lambda (code a)
                                    (set! traced (cons (cons code a) traced)))]
                     [*collector-holding?* #f]
                     [*collector-pass* #f])
           (collector-collect!))
         (equal? (reverse traced) '((28 . 0) (29 . 0)))))

;;; The log of collections ((schevana services allocation)), which the
;;; profiler's handler writes as each one runs.

;; Returns the newest collection's seq, or -1 for none.
(define (collector-newest)
  (let ([seqs (allocation-collections)]) (if (pair? seqs) (car seqs) -1)))

;; Returns a field of each collection logged after seq, the oldest first.
(define (collector-logged-since seq field)
  (map (lambda (s) (cdr (assq field (allocation-collection s))))
       (reverse (filter (lambda (s) (> s seq)) (allocation-collections)))))

(check "a collection is logged: its pass, its pause, what each generation \
        held, and what survived it"
       ;; the newest is read first: allocating this much may bring a
       ;; collection by itself, which then moves it
       (let* ([before (collector-newest)]
              [kept (make-bytevector (* 4 1024 1024) 1)])
         (collect-rendezvous)
         (let ([c (allocation-collection (+ before 1))])
           (and c
                (for-all (lambda (pass) (eq? pass 'young))
                         (collector-logged-since before 'pass))
                (for-all (lambda (ns) (> ns 0))
                         (collector-logged-since before 'pause))
                (>= (apply + (collector-logged-since before 'survived))
                    (* 4 1024 1024))
                (= (length (cdr (assq 'before c))) 5)
                (< (car (cdr (assq 'after c))) (car (cdr (assq 'before c))))
                (= (cdr (assq 'held c)) 0)
                (not (allocation-collection (+ (collector-newest) 1)))
                (= 1 (bytevector-u8-ref kept 0))))))

(check "the log tells the collector's passes apart, by what the \
        generations held before and after"
       (let ([kept (make-bytevector (* 4 1024 1024) 1)]
             [pass-of (lambda (thunk)
                        (let ([before (collector-newest)])
                          (thunk)
                          (cdr (assq 'pass
                                     (allocation-collection (+ before 1))))))])
         ;; into generation 1, then on by each pass: 1 into 2, 2 into 3,
         ;; and all into 4
         (collect-rendezvous)
         (let* ([middle (pass-of (lambda () (collector-pass! 1 2)))]
                [old (pass-of (lambda () (collector-pass! 3 3)))]
                [settle (pass-of collector-settle!)])
           (printf "  passes read: ~a ~a ~a\n" middle old settle)
           (and (eq? middle 'middle) (eq? old 'old) (eq? settle 'settle)
                (= 1 (bytevector-u8-ref kept 0))))))

;; a draw that allocates some 17 MB in one frame turn, many times past the
;; collect trip: the turn holds every request off till its frame is out
(let ([win (open-window "Hog" 'size '(80 . 60)
                        'draw (lambda (win w h)
                                (let loop ([i 0] [keep '()])
                                  (when (< i 200000)
                                    (loop (+ i 1)
                                          (cons (make-vector 8)
                                                (if (> (length keep) 10)
                                                    '()
                                                    keep)))))))])
  (steps 1)
  (let ([before (collector-newest)])
    (invalidate! win)
    (steps 1)
    (let ([held (collector-logged-since before 'held)]
          [held-ns (collector-logged-since before 'held-ns)])
      (close-window! win)
      (printf "  requests held off before each collection: ~a\n" held)
      (check "a frame turn that allocates many times the trip holds one \
              request off, not one at each segment after: the collection \
              that follows says so, and for how long"
             (and (pair? held)
                  (= (apply + held) 1)
                  (exists positive? held-ns))))))

(check "a request held off moves the trip out of Chez's reach, and the \
        collection that the turn owes sets it back"
       (fluid-let ([*collector-holding?* #t]
                   [*collector-held?* #f]
                   [*collector-pass* #f])
         (collector-collect!)
         (let ([held? *collector-held?*] [moved (collect-trip-bytes)])
           (set! *collector-holding?* #f)
           (collector-collect!)
           (and held?
                (> moved (* 1024 collector-trip))
                (= (collect-trip-bytes) collector-trip)))))

;; Chez reads a generation low on a thread that did not do all of the last
;; collection's work, and under 0 as a number near 2^64. A second thread
;; running Scheme brings that about for this one: it waits at the
;; rendezvous, and the collector works in its name too. The second thread
;; stops when told, or by itself after some seconds' turns.
(check "a generation that Chez reads under 0 is 0 to the collector"
       (let* ([started (box #f)] [stop (box #f)]
              [t (fork-thread
                  (lambda ()
                    (set-box! started #t)
                    (let loop ([i 0])
                      (unless (or (unbox stop) (fx= i 2000000000))
                        (loop (fx+ i 1))))))])
         (let wait ([i 0])
           (unless (or (unbox started) (fx= i 2000000000)) (wait (fx+ i 1))))
         (fluid-let ([*collector-holding?* #f]) (collect-rendezvous))
         (let ([chez (bytes-allocated 0)]
               [here (collector-generation-bytes 0)])
           (set-box! stop #t)
           (thread-join t)
           (printf "  generation 0 after a collection beside a second \
                    thread: Chez reads ~a, the collector ~a\n" chez here)
           (and (unbox started) (fixnum? here) (<= 0 here (* 1024 1024))))))
