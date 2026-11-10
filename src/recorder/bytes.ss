;;; recorder/bytes.ss — "/recorder", sealed (.work/gpu-design.md 9.14): the
;;; bytes of what the world records and hands core0 with a frame, and the
;;; only code that writes them. Core0 makes this environment and loads it;
;;; the world reaches it only through recorder-interface, each name a
;;; read-only forwarder (tests/sources.ss), so nothing it does, however
;;; written, can write a byte core0 reads. The world keeps the rest of the
;;; recorder (src/gfx.ss): colors, shapes, text, runs and labels.
;;;
;;; The root's records and extras are a pair of blocks (gpu-block,
;;; src/host/gpu.ss): written while the world owns them; frozen as the frame
;;; is published, the last frame to read, and lent with it; free once core0
;;; gave the frame back and a newer one is the last. Between a publish and
;;; the next list the recorder writes to nothing, so a stray write raises.

;; What the world may name of this environment's.
(define recorder-interface
  '(rec-write! rec-extra! rec-extra-u32! rec-extra-ref rec-extra-at
    rec-count rec-bytes-begin! rec-into-list! rec-freeze! rec-lend!
    rec-last-sizes rec-last-copy! rec-drawing->bytes rec-bytes-copies))

;; What's written to: the root's pair, or a list's bytes; between a publish
;; and the next list, nothing.
(define rec-nothing (make-bytevector 0))
(defvar *rec-bytes* rec-nothing)
(defvar *rec-at* 0)               ; bytes written
(defvar *rec-extras* rec-nothing)
(defvar *rec-extra-at* 1)         ; words written

(defvar *rec-pairs* '())   ; every pair the root has had, (recs . extras)
(defvar *rec-pair* #f)     ; the pair being written, or #f
(defvar *rec-last* #f)     ; the last frame's pair, and its bytes' lengths
(defvar *rec-last-n* 0)
(defvar *rec-last-extras-n* 0)
(defvar *rec-poison?* #f)  ; tests: a pair freed is filled with garbage

(define (rec-count) (fxquotient *rec-at* 32))
(define (rec-extra-at) *rec-extra-at*)

;;; ------------------------------------------------------------------ writing

(define (rec-records-grow!)
  (let ([new (make-immobile-bytevector (* 2 (bytevector-length *rec-bytes*)))])
    (bytevector-copy! *rec-bytes* 0 new 0 *rec-at*)
    (set! *rec-bytes* new)))

;; A record's eight words.
(define (rec-write! w0 w1 x0 y0 x1 y1 a b)
  (let ([at *rec-at*])
    (when (fx= at (bytevector-length *rec-bytes*)) (rec-records-grow!))
    (let ([bv *rec-bytes*])
      (bytevector-u32-native-set! bv at w0)
      (bytevector-u32-native-set! bv (fx+ at 4) w1)
      (bytevector-s32-native-set! bv (fx+ at 8) x0)
      (bytevector-s32-native-set! bv (fx+ at 12) y0)
      (bytevector-s32-native-set! bv (fx+ at 16) x1)
      (bytevector-s32-native-set! bv (fx+ at 20) y1)
      (bytevector-s32-native-set! bv (fx+ at 24) a)
      (bytevector-s32-native-set! bv (fx+ at 28) b)
      (set! *rec-at* (fx+ at 32)))))

(define (rec-extras-room! n)
  (when (> (* 4 (+ *rec-extra-at* n)) (bytevector-length *rec-extras*))
    (let ([new (make-immobile-bytevector
                (* 2 (+ (bytevector-length *rec-extras*) (* 4 n))))])
      (bytevector-copy! *rec-extras* 0 new 0 (* 4 *rec-extra-at*))
      (set! *rec-extras* new))))

(define (rec-extra! v)
  (rec-extras-room! 1)
  (bytevector-s32-native-set! *rec-extras* (fx* 4 *rec-extra-at*) v)
  (set! *rec-extra-at* (fx+ *rec-extra-at* 1)))

(define (rec-extra-u32! v)
  (rec-extras-room! 1)
  (bytevector-u32-native-set! *rec-extras* (fx* 4 *rec-extra-at*) v)
  (set! *rec-extra-at* (fx+ *rec-extra-at* 1)))

;; Word k of the row at row the list being recorded wrote.
(define (rec-extra-ref row k)
  (bytevector-s32-native-ref *rec-extras* (fx* 4 (fx+ row k))))

;;; ------------------------------------------------------------------ owning

;; b's bytes, to write; raises while a frame holds it.
(define (rec-block-writable b)
  (unless (eq? (gpu-block-owner b) 'world)
    (errorf 'rec-block-writable "a frame holds these bytes: lent, frozen"))
  (gpu-block-bytes b))

(define (rec-pair-free? p)
  (and (not (eq? p *rec-pair*)) (not (eq? p *rec-last*))
       (eq? (gpu-block-owner (car p)) 'world)))

;; A free pair is filled with garbage, when tests ask: a reader that kept
;; it draws garbage.
(define (rec-pair-freed! p)
  (when (and *rec-poison?* (rec-pair-free? p))
    (bytevector-fill! (gpu-block-bytes (car p)) #xa5)
    (bytevector-fill! (gpu-block-bytes (cdr p)) #xa5)))

;; A free pair, or a new one.
(define (rec-pair-take!)
  (or (find rec-pair-free? *rec-pairs*)
      (let ([p (cons (make-gpu-block (make-immobile-bytevector (* 32 16384) 0)
                                     'world)
                     (make-gpu-block (make-immobile-bytevector (* 4 65536) 0)
                                     'world))])
        (set! *rec-pairs* (cons p *rec-pairs*))
        p)))

;; The root's list begins: written in a pair the world owns, from the start.
(define (rec-bytes-begin!)
  (unless *rec-pair* (set! *rec-pair* (rec-pair-take!)))
  (set! *rec-bytes* (rec-block-writable (car *rec-pair*)))
  (set! *rec-extras* (rec-block-writable (cdr *rec-pair*)))
  (set! *rec-at* 0)
  (set! *rec-extra-at* 1))

;; What thunk records goes into lst's bytes (a gpu-list's), from their start,
;; their lengths set after, done called while they're still the ones
;; written (the runs end there); the list recorded before goes on as it was.
(define (rec-into-list! lst thunk done)
  (let ([bytes *rec-bytes*] [at *rec-at*]
        [extras *rec-extras*] [extra-at *rec-extra-at*])
    (dynamic-wind
     (lambda ()
       (set! *rec-bytes* (gpu-list-recs lst))
       (set! *rec-at* 0)
       (set! *rec-extras* (gpu-list-extras lst))
       (set! *rec-extra-at* 1))
     thunk
     (lambda ()
       (done)
       (gpu-list-recs-set! lst *rec-bytes*)
       (gpu-list-recs-n-set! lst *rec-at*)
       (gpu-list-extras-set! lst *rec-extras*)
       (gpu-list-extras-n-set! lst (* 4 *rec-extra-at*))
       (set! *rec-bytes* bytes)
       (set! *rec-at* at)
       (set! *rec-extras* extras)
       (set! *rec-extra-at* extra-at)))))

;; The root's pair frozen, grown as it may have: the last frame to read,
;; the recorder writing to nothing till the next list.
(define (rec-freeze!)
  (let ([p *rec-pair*] [old *rec-last*])
    (gpu-block-bytes-set! (car p) *rec-bytes*)
    (gpu-block-bytes-set! (cdr p) *rec-extras*)
    (gpu-block-owner-set! (car p) 'lent)
    (gpu-block-owner-set! (cdr p) 'lent)
    (set! *rec-last* p)
    (set! *rec-last-n* *rec-at*)
    (set! *rec-last-extras-n* (* 4 *rec-extra-at*))
    (set! *rec-pair* #f)
    (set! *rec-bytes* rec-nothing)
    (set! *rec-extras* rec-nothing)
    (when old (rec-pair-freed! old))))

;; Frame f, given back by core0 and filled again, is lent the frozen pair:
;; what it was lent before is the world's again.
(define (rec-lend! f)
  (let ([back (gpu-frame-blocks f)] [p *rec-last*])
    (when (pair? back)
      (gpu-block-owner-set! (car back) 'world)
      (gpu-block-owner-set! (cdr back) 'world)
      (rec-pair-freed! back))
    (gpu-frame-recs-set! f (gpu-block-bytes (car p)))
    (gpu-frame-recs-n-set! f *rec-last-n*)
    (gpu-frame-extras-set! f (gpu-block-bytes (cdr p)))
    (gpu-frame-extras-n-set! f *rec-last-extras-n*)
    (gpu-frame-blocks-set! f p)))

;;; ------------------------------------------------------------------ reading

;; The last frame published: (values recs recs-n extras extras-n), its
;; bytes, here only; empty before the first.
(define (rec-last)
  (let ([p *rec-last*])
    (if p
        (values (gpu-block-bytes (car p)) *rec-last-n*
                (gpu-block-bytes (cdr p)) *rec-last-extras-n*)
        (values rec-nothing 0 rec-nothing 0))))

;; How many bytes of records and of extras the last frame has: (values
;; recs-n extras-n).
(define (rec-last-sizes) (values *rec-last-n* *rec-last-extras-n*))

;; The last frame's records and extras copied into recs and extras, each
;; big enough (rec-last-sizes): the world reads a frame only so.
(define (rec-last-copy! recs extras)
  (let-values ([(r rn e en) (rec-last)])
    (bytevector-copy! r 0 recs 0 rn)
    (bytevector-copy! e 0 extras 0 en)))

;; The list being recorded, drawn by core0 now on an image pw × ph, the rest
;; of the frame given: its pixels (gpu-drawing->bytes).
(define (rec-drawing->bytes jobs dirty computes table table-n pieces images
                            runs pw ph clear?)
  (gpu-drawing->bytes jobs dirty computes *rec-bytes* *rec-at* *rec-extras*
                      (* 4 *rec-extra-at*) table table-n pieces images runs
                      pw ph clear?))

;; The list being recorded as copies of its own, for a job core0 runs later:
;; (values recs recs-n extras extras-n).
(define (rec-bytes-copies)
  (let ([copy (lambda (bv n)
                (let ([c (make-bytevector n)])
                  (bytevector-copy! bv 0 c 0 n)
                  c))])
    (values (copy *rec-bytes* *rec-at*) *rec-at*
            (copy *rec-extras* (* 4 *rec-extra-at*)) (* 4 *rec-extra-at*))))
