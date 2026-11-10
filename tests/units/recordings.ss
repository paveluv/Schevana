;;; tests/units/recordings.ss — what's recorded goes into recordings, never
;;; copied: frozen once recorded and swapped into their list or frame whole,
;;; retired after the last frame that may show them, and written again only
;;; once core0 gave that frame back.

(for-each close-window! (windows))
(request-frame!)
(steps 2)

(check "between frames the recorder writes to nothing: a stray write raises"
       (raises? (lambda () (fill-box 0 0 4 4 'accent))))

(let ([r (begin (request-frame!) (steps 1) *rec-root*)])
  (check "the frame just published is the root's newest, frozen, and lent \
          to the frame"
         (and (not (gpu-recording-until r))
              (eq? (gpu-frame-root *gpu-frame-free*) r)))
  (request-frame!)
  (steps 1)
  (check "replaced, it retires after the frame that showed it, and is free \
          once core0 gave that frame back"
         (and (not (eq? r *rec-root*))
              (eqv? (gpu-recording-until r)
                    (- (gpu-frame-number *gpu-frame-free*) 1))
              (rec-free? r))))

;; A list recorded again and again, a frame between: written in turn in its
;; own two recordings, each frozen whole, the newest one's version its
;; count.
(let* ([lst (gpu-list-new)]
       [record! (lambda (n)
                  (record-list! lst (lambda ()
                                      (do ([i 0 (+ i 1)]) ((= i n))
                                        (fill-box i 0 1 1 'accent)))))]
       [seen '()])
  (do ([i 1 (+ i 1)]) ((> i 6))
    (record! i)
    (unless (memq (gpu-list-recording lst) seen)
      (set! seen (cons (gpu-list-recording lst) seen)))
    (request-frame!)
    (steps 1))
  (check (format "a list reuses its own recordings once free (~a for 6), \
                  which the inspect kit reads ~s"
                 (length seen) (inspect-recordings lst))
         (and (<= (length seen) 2)
              (let ([rs (inspect-recordings lst)])
                (and (= (length rs) (length seen))
                     (equal? (car rs) '((version . 6) (until . #f)
                                        (free . #f)))
                     (for-all (lambda (r) (cdr (assq 'free r))) (cdr rs))))
              (pair? (inspect-recordings #f))
              (= (gpu-list-version lst) 6)
              (= (gpu-list-recs-n lst) (* 6 32))))
  (check "a list shown keeps its bytes in the recorder; a copy hands its own"
         (let ([copy (rec-list-copy lst (gpu-list-runs lst))])
           (and (raises? (lambda () (gpu-list-recs lst)))
                (= (bytevector-length (gpu-list-recs copy)) (* 6 32))
                (raises? (lambda () (gpu-list-state copy))))))
  ;; core0 reads each list's recording once a pass, whatever happens to the
  ;; list during it
  (let ([was (gpu-list-seen lst)])
    (record! 2)
    (let ([same (gpu-list-seen lst)])
      (set! *gpu-pass* (+ *gpu-pass* 1))
      (check "a pass reads a list's recording once: one recorded again in it \
              shows in the next"
             (and (eq? same was)
                  (eq? (gpu-list-seen lst) (gpu-list-recording lst))
                  (not (eq? was (gpu-list-recording lst))))))))

;; A list the world made of its own bytes, drawn ahead of a frame (the
;; Pipeline's flattened frames): copied as it's handed, so what the world
;; does to its bytes after can't reach what core0 reads.
(let ([target (gpu-image-make-target 8 8)]
      [recs (make-bytevector 64 7)] [extras (make-bytevector 8 9)])
  (rec-past! target recs 64 extras 8 '())
  (request-frame!)
  (steps 1)
  (let ([lent (gpu-frame-earlier *gpu-frame-free*)])
    (bytevector-fill! recs 0)
    (check (format "a list drawn ahead of a frame is the recorder's copy, \
                    read by that frame alone, free once it's back ~s"
                   (inspect-recordings 'earlier))
           (and (= (length lent) 1)
                (eq? (caar lent) target)
                (let ([r (cdar lent)])
                  (and (not (eq? (gpu-recording-recs r) recs))
                       (= (gpu-recording-recs-n r) 64)
                       (= (bytevector-u8-ref (gpu-recording-recs r) 63) 7)
                       (rec-free? r)))
                (for-all (lambda (r) (cdr (assq 'free r)))
                         (inspect-recordings 'earlier))))
    (request-frame!)
    (steps 1)
    (check "the next frame draws nothing ahead unless handed something"
           (null? (gpu-frame-earlier *gpu-frame-free*))))
  (gpu-image-release! target))

;; A frame drawn on a target, as the Pipeline's small screen draws it, from
;; the frozen frame: poisoned or not, the pixels are the same; poisoned, a
;; recording taken to write is garbage past what's written.
(define (recordings-frame-pixels poison?)
  (fluid-let ([*rec-poison?* poison?])
    (let ([target (gpu-image-make-target 32 32)] [plain record-world!])
      (set! record-world!
        (lambda ()
          (fill-box 0 0 32 32 #x204060)
          (fill-box 4 4 12 12 #xff8000)
          (draw-line 0 31 31 0 #xffffff 2)))
      (do ([i 0 (+ i 1)]) ((= i 4))
        (when (= i 2)
          (rec-preview! target
                        (lambda ()
                          (let-values ([(recs n extras extras-n) (rec-last)])
                            (list recs n extras extras-n (rec-runs))))))
        (request-frame!)
        (steps 1))
      (set! record-world! plain)
      (let* ([r *rec-root*] [n (gpu-recording-recs-n r)]
             [garbage (and (< n (bytevector-length (gpu-recording-recs r)))
                           (= (bytevector-u8-ref (gpu-recording-recs r) n)
                              #xa5))])
        (request-frame!)
        (steps 1)
        (let ([bytes (drawing->bytes 32 32 1
                       (lambda () (draw-image target 0 0 32 32)))])
          (gpu-image-release! target)
          (cons bytes garbage))))))

(let ([plain (recordings-frame-pixels #f)]
      [poisoned (recordings-frame-pixels #t)])
  (check "a frame poisoned as its recordings are taken draws the same \
          pixels, and a recording taken is garbage past what's written"
         (and (equal? (car plain) (car poisoned))
              (not (cdr plain)) (cdr poisoned))))

;;; ------------------------------------------------------------------ writes

;; The spans of the writes being written: (kind id x y n) each.
(define (recordings-spans)
  (let ([r *rec-writes*])
    (if r
        (let loop ([at 0])
          (if (= at (gpu-recording-recs-n r))
              '()
              (let ([word (lambda (k) (bytevector-s32-native-ref
                                       (gpu-recording-recs r) (+ at k)))])
                (cons (list (word 0) (word 4) (word 8) (word 12) (word 20))
                      (loop (+ at 32))))))
        '())))

(request-frame!)
(steps 1)

(let ([b (make-gpu-buffer 8)])
  (do ([i 2 (+ i 1)]) ((= i 6)) (gpu-buffer-set! b i (* 10 i)))
  (gpu-buffer-set! b 0 -1)
  (gpu-buffer-set! b 1 0.5)
  (let ([spans (recordings-spans)])
    (check (format "words set one after another go in one span, another \
                    word in the next ~s" spans)
           (equal? spans `((0 ,(gpu-buffer-id b) 2 0 4)
                           (0 ,(gpu-buffer-id b) 0 0 2)))))
  (check "a word that doesn't fit 32 bits raises, and nothing is written"
         (and (raises? (lambda () (gpu-buffer-set! b 7 (expt 2 32))))
              (raises? (lambda () (gpu-buffer-set! b 7 'red)))
              (raises? (lambda () (gpu-buffer-set! b 8 1)))
              (= (length (recordings-spans)) 2)))
  ;; past the buffer's size, by the recorder's own call: core0 skips it
  (rec-buffer-set! (gpu-buffer-id b) 8 99)
  (rec-buffer-set! (gpu-buffer-id b) -1 99)
  (let ([got (gpu-buffer-read! b)])
    (check "core0 writes what was set, words, negatives and floats, and \
            skips a word past the buffer's end, which it checks by its own \
            size"
           (and (= (bytevector-length got) 32)
                (= (bytevector-s32-native-ref got 0) -1)
                (= (bytevector-ieee-single-native-ref got 4) 0.5)
                (equal? (map (lambda (i)
                               (bytevector-s32-native-ref got (* 4 i)))
                             '(2 3 4 5 6 7))
                        '(20 30 40 50 0 0))
                (not (rec-writes-pending?)))))
  (gpu-buffer-release! b))

(check "writes no frame takes go at the turn's end"
       (let ([b (make-gpu-buffer 1)])
         (fluid-let ([*dirty* #f] [*timers* '()])
           (gpu-buffer-set! b 0 5)
           (schevana-step! 0))
         (let ([ok (and (not (rec-writes-pending?))
                        (pair? (inspect-recordings 'writes))
                        (= (bytevector-s32-native-ref (gpu-buffer-read! b) 0)
                           5))])
           (gpu-buffer-release! b)
           ok)))

;; Rows of a w-wide image's bytes: each pixel #xff and its row's number,
;; but the first pixel of a row in skip.
(define-worklet (recordings-rows! y0 y1 bytes w skip)
  (do ([y y0 (fx+ y 1)]) ((fx= y y1))
    (do ([x (if (fx= y skip) 1 0) (fx+ x 1)]) ((fx= x w))
      (bytevector-u32-native-set! bytes (fx* 4 (fx+ x (fx* y w)))
                                  (fxior #xff000000 y)))))

(define-worklet (recordings-fail! y0 y1 bytes)
  (raise 'recordings-fail))

(let ([pm (make-pixmap 16 8 #x000000)])
  (pixmap-rows! pm 2 6 recordings-rows! 16 -1)
  (pixmap-set-pixel! pm 5 3 #xff00ff00)
  (let ([spans (recordings-spans)])
    (guard (c [#t #f]) (pixmap-rows! pm 0 8 recordings-fail!))
    (check (format "rows painted are a span of their loan, a pixel set after \
                    one of its own, and a paint that raises leaves none ~s"
                   spans)
           (and (equal? (map car spans) '(2 2 1))
                (equal? (recordings-spans) spans))))
  (let ([p (pixmap-picture pm)])
    (check "the GPU holds the rows painted, then the pixel set over them"
           (and (= (pixel-at p 0 1) #xff000000)
                (= (pixel-at p 0 2) #xff000002)
                (= (pixel-at p 15 5) #xff000005)
                (= (pixel-at p 5 3) #xff00ff00)
                (= (pixel-at p 0 6) #xff000000))))
  ;; a paint each frame: its loans come back with their frames
  (do ([i 0 (+ i 1)]) ((= i 8))
    (pixmap-rows! pm 0 8 recordings-rows! 16 -1)
    (request-frame!)
    (steps 1))
  (let ([loans (inspect-recordings (pixmap-image pm))])
    (check (format "an image's loans are painted again once free (~a for 10 \
                    paints), which the inspect kit reads ~s"
                   (length loans) loans)
           (and (<= (length loans) 3)
                (for-all (lambda (l) (cdr (assq 'free l))) (cdr loans))))))

;; Rows y0 .. y1 of a w-wide image's bytes, all of pixel px.
(define-worklet (recordings-fill! y0 y1 bytes w px)
  (do ([i (fx* 4 (fx* y0 w)) (fx+ i 4)]) ((fx= i (fx* 4 (fx* y1 w))))
    (bytevector-u32-native-set! bytes i px)))

(let ([pm (make-pixmap 16 8 #x000000)])
  (request-frame!)
  (steps 1)
  (let ([before (length (inspect-recordings (pixmap-image pm)))])
    (do ([i 0 (+ i 1)]) ((= i 50))
      (pixmap-rows! pm 0 8 recordings-fill! 16 (+ #xff000000 i)))
    (pixmap-rows! pm 2 4 recordings-fill! 16 #xff00ff00)
    (let* ([spans (recordings-spans)]
           [loans (length (inspect-recordings (pixmap-image pm)))]
           [p (pixmap-picture pm)])
      (check (format "rows painted again over the last ones, nothing written \
                      between, take their place: 50 paints a span ~s, ~a \
                      loans more"
                     spans (- loans before))
             (and (equal? (map car spans) '(2 2))
                  (<= (- loans before) 2)
                  (= (pixel-at p 0 0) (+ #xff000000 49))
                  (= (pixel-at p 0 3) #xff00ff00))))))

(define (recordings-skipped-pixel poison?)
  (fluid-let ([*rec-poison?* poison?])
    (let ([pm (make-pixmap 4 4 #xffffff)])
      (pixmap-rows! pm 0 4 recordings-rows! 4 2)
      (pixel-at (pixmap-picture pm) 0 2))))

(check "poisoned, a loan is garbage till painted: a pixel a paint skips \
        shows it"
       (= (recordings-skipped-pixel #t) #xa5a5a5a5))

(let ([pm (make-pixmap 1 1 #x000000)] [got #f])
  (pixmap-set! pm 0 0 #x00ff00)
  (drawing->bytes-then 1 1 1 (lambda () (pixmap-draw pm 0 0)) #t
                       (lambda (bytes) (set! got bytes)))
  (steps 2)
  (check "a frame's writes go before the reads it carries: a drawing read \
          back shows the pixels set that turn"
         (and (bytevector? got)
              (= (bytevector-u32-native-ref got 0) #xff00ff00))))
