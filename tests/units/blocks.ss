;;; tests/units/blocks.ss — a frame's bytes change owner, never copied: the
;;; root's records and extras are blocks the world writes while it owns
;;; them, frozen and lent with the frame as it's published, and free again
;;; once core0 gave the frame back and a newer one is the last.

(for-each close-window! (windows))
(request-frame!)
(steps 2)

(check "between frames the recorder writes to nothing: a stray write raises"
       (raises? (lambda () (fill-box 0 0 4 4 'accent))))

(let ([last (lambda () *rec-last*)])
  (request-frame!)
  (steps 1)
  (let ([p (last)])
    (check "the frame just published is frozen, lent: its bytes can't be had \
            to write"
           (and (eq? (gpu-block-owner (car p)) 'lent)
                (raises? (lambda () (gpu-block-writable (car p))))))
    (request-frame!)
    (steps 1)
    (check "once core0 gave its frame back and a newer one is the last, it's \
            the world's again, and free"
           (and (not (eq? p (last)))
                (eq? (gpu-block-owner (car p)) 'world)
                (eq? (gpu-block-owner (cdr p)) 'world)
                (rec-pair-free? p)))))

;; A frame drawn on a target, as the Pipeline's small screen draws it, from
;; the frozen frame: poisoned or not, the pixels are the same; poisoned, a
;; pair freed is garbage.
(define (blocks-frame-pixels poison?)
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
      (request-frame!)
      (steps 1)
      (let ([bytes (drawing->bytes 32 32 1
                     (lambda () (draw-image target 0 0 32 32)))]
            [garbage (exists (lambda (p)
                               (and (rec-pair-free? p)
                                    (= (bytevector-u8-ref
                                        (gpu-block-bytes (car p)) 0)
                                       #xa5)))
                             *rec-pairs*)])
        (gpu-image-release! target)
        (cons bytes garbage)))))

(let ([plain (blocks-frame-pixels #f)] [poisoned (blocks-frame-pixels #t)])
  (check "a frame poisoned as its pairs are freed draws the same pixels, and \
          a pair freed is garbage"
         (and (equal? (car plain) (car poisoned))
              (not (cdr plain)) (cdr poisoned))))
