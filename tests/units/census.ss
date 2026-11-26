;;; tests/units/census.ss — the census and the hours ((schevana services
;;; allocation)): the live heap counted by kind and by owner, a mark and
;;; what grew since it, and a row a minute of what the heap holds.

;; Returns the node at path in a census's tree of owners, or #f.
(define (census-test-node census . path)
  (let walk ([node (cdr (assq 'owners census))] [path path])
    (cond [(null? path) node]
          [(find (lambda (c) (equal? (car c) (car path))) (cddr node))
           => (lambda (c) (walk c (cdr path)))]
          [else #f])))

;; Returns the bytes a census counted of a kind.
(define (census-test-kind census name)
  (let ([k (assq name (cdr (assq 'kinds census)))])
    (if k (caddr k) 0)))

(define census-test-mb (* 1024 1024))

;; A window that holds 4 MB of its own.
(define census-test-win
  (open-window "Hoard" 'size '(80 . 60) 'draw (lambda (win w h) (void))))
(window-set! census-test-win 'hoard (make-bytevector (* 4 census-test-mb) 1))
(steps 1)
(define census-test-label (format "Hoard (~a)" (window-id census-test-win)))
(define census-test-first (allocation-census!))
(define census-test-seq (- (allocation-collection-count) 1))

(check (format "a census charges a window what it alone holds, and counts \
                it by kind: ~a KB for the window"
               (let ([w (census-test-node census-test-first "windows"
                                          census-test-label)])
                 (and w (quotient (cadr w) 1024))))
       (let ([w (census-test-node census-test-first "windows"
                                  census-test-label)])
         (and w
              (<= (* 4 census-test-mb) (cadr w) (* 5 census-test-mb))
              (>= (census-test-kind census-test-first 'bytevector)
                  (* 4 census-test-mb)))))

(check "a library's state is charged to its library, under its layer"
       (let ([n (census-test-node census-test-first "services"
                                  "services/allocation.sls"
                                  "*allocation-hours*")])
         (and n (>= (cadr n) (* 8 10 2880)))))

(check "the owners add up: each node is its children's sum, and the heap \
        is at least what the census found live"
       (let ([root (cdr (assq 'owners census-test-first))])
         (and (>= (cadr root) (cdr (assq 'bytes census-test-first)))
              (let sums ([node root])
                (or (null? (cddr node))
                    (and (= (cadr node) (apply + (map cadr (cddr node))))
                         (for-all sums (cddr node))))))))

(check "the symbols take the code and the names first, and the rest is \
        small"
       (let ([names (census-test-node census-test-first "code and names")]
             [rest (census-test-node census-test-first "the rest")]
             [all (cdr (assq 'bytes census-test-first))])
         (printf "  ~a KB live: ~a KB code and names, ~a KB the rest\n"
                 (quotient all 1024) (quotient (cadr names) 1024)
                 (quotient (cadr rest) 1024))
         (and (> (cadr names) 0) (< (cadr rest) (quotient all 4)))))

(check "a census is a full collection, which the log has as the census's"
       (let ([c (allocation-collection census-test-seq)])
         (printf "  ~s ~s, ~a ms\n" (cdr (assq 'pass c)) (cdr (assq 'span c))
                 (quotient (cdr (assq 'pause census-test-first)) 1000000))
         (and (eq? (cdr (assq 'pass c)) 'settle)
              (equal? (cdr (assq 'span c)) '(census . #f)))))

(allocation-census-mark!)
(window-set! census-test-win 'more (make-bytevector (* 2 census-test-mb) 2))
(allocation-census!)

(check "after a mark, a census tells what grew: the window by the bytes it \
        took, and the bytevectors"
       (let* ([grown (allocation-census-grown)]
              [owner (assoc (list "heap" "windows" census-test-label)
                            (cdr (assq 'owners grown)))]
              [kind (assq 'bytevector (cdr (assq 'kinds grown)))])
         (printf "  the window ~s, bytevectors ~s\n" owner kind)
         (and owner
              (<= (* 2 census-test-mb) (cdr owner)
                  (+ (* 2 census-test-mb) 4096))
              kind (>= (cdr kind) (* 2 census-test-mb)))))

(close-window! census-test-win)
(steps 1)
(check "a window closed is charged nothing at the next census"
       (not (census-test-node (allocation-census!) "windows"
                              census-test-label)))

(check "the hours have a row at each turn: each generation, what Chez \
        and the process hold, the GPU bytes, the collections and the \
        longest pause"
       (let ([n (allocation-hours-count)])
         (allocation-hours-row!)
         (let ([last (lambda (field) (car (reverse (allocation-hours field))))])
           (and (= (allocation-hours-count) (+ n 1))
                (= (length (allocation-hours 4)) (min (+ n 1) 2880))
                (> (last 4) 0)
                (> (last 'memory) (last 4))
                (>= (last 'process) 0)
                (<= (last 'collections) (collections))
                ;; the census's own collection came since the row before
                (> (last 'pause) 0)))))

(check "a generation's slope is in bytes a day, over all the rows kept or \
        the last ones asked for"
       (fluid-let ([*allocation-hours*
                    (make-fxvector (* allocation-hours-width 2880) 0)]
                   [*allocation-hours-count* 0])
         ;; a row a minute for an hour, generation 4 growing a KB a minute,
         ;; then ten minutes at twice that
         (do ([i 0 (+ i 1)]) ((= i 70))
           (let ([at (* allocation-hours-width i)])
             (fxvector-set! *allocation-hours* at (* i 60000000000))
             (fxvector-set! *allocation-hours* (+ at 5)
                            (+ 1000000 (* 1024 (min i 60))
                               (* 2048 (max 0 (- i 60)))))))
         (set! *allocation-hours-count* 70)
         (let ([recent (allocation-hours-slope 4 10)]
               [first (fluid-let ([*allocation-hours-count* 61])
                        (allocation-hours-slope 4))])
           (printf "  ~a and ~a bytes a day\n" first recent)
           (and (< (abs (- first (* 1024 1440))) 1)
                (< (abs (- recent (* 2048 1440))) 1)
                (not (fluid-let ([*allocation-hours-count* 1])
                       (allocation-hours-slope 4)))))))
