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
