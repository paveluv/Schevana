;;; recorder/bytes.ss — "/recorder", sealed (.work/gpu-design.md 9.14): the
;;; bytes of what the world records and hands core0, and the only code that
;;; writes them. Core0 makes this environment and loads it; the world
;;; reaches it only through recorder-interface, each name a read-only
;;; forwarder (tests/sources.ss), so nothing it does, however written, can
;;; write a byte core0 reads. The world keeps the rest of the recorder
;;; (src/gfx.ss): colors, shapes, text, runs and labels.
;;;
;;; What's recorded goes into a recording (gpu-recording, src/host/gpu.ss):
;;; a list's, or the root's, the frame's. Recorded, it's frozen with its
;;; runs and version and swapped into its holder by one store, so core0
;;; reads a whole one, never written again while a frame may read it. Each
;;; holder keeps its older recordings chained after its newest, to write
;;; again once free: retired after frame N, the last published when it was
;;; replaced, it's free once core0 gave frame N back.

;; What the world may name of this environment's.
(define recorder-interface
  '(rec-write! rec-extra! rec-extra-u32! rec-extra-ref rec-extra-at
    rec-count rec-bytes-begin! rec-into-list! rec-freeze! rec-lend!
    rec-last-sizes rec-last-copy! rec-drawing->bytes rec-bytes-copies
    rec-list-new rec-list-copy gpu-list-recs-n gpu-list-extras-n
    gpu-list-runs gpu-list-version gpu-list-recs gpu-list-extras
    rec-recordings))

;; Written to between a publish and the next list: a write there raises.
(define rec-nothing
  (make-gpu-recording (make-bytevector 0) 0 (make-bytevector 0) 4 '() 0 #f #f))

(defvar *rec-now* rec-nothing)   ; the recording being written
(defvar *rec-root* #f)       ; the root's newest, the last frame's, or #f
(defvar *rec-root-next* #f)  ; the root's being written, or #f
(defvar *rec-published* 0)   ; frames lent so far, the last one's number
(defvar *rec-poison?* #f)    ; tests: a recording taken is garbage first

(define (rec-count) (fxquotient (gpu-recording-recs-n *rec-now*) 32))
(define (rec-extra-at) (fxsrl (gpu-recording-extras-n *rec-now*) 2))

;;; ------------------------------------------------------------------ writing

(define (rec-records-grow! r)
  (when (eq? r rec-nothing)
    (errorf 'rec-write! "nothing is being recorded: draw in a frame, a list \
                         or a drawing"))
  (let* ([old (gpu-recording-recs r)]
         [new (make-immobile-bytevector (* 2 (bytevector-length old)))])
    (bytevector-copy! old 0 new 0 (gpu-recording-recs-n r))
    (gpu-recording-recs-set! r new)))

;; A record's eight words.
(define (rec-write! w0 w1 x0 y0 x1 y1 a b)
  (let* ([r *rec-now*] [at (gpu-recording-recs-n r)])
    (when (fx= at (bytevector-length (gpu-recording-recs r)))
      (rec-records-grow! r))
    (let ([bv (gpu-recording-recs r)])
      (bytevector-u32-native-set! bv at w0)
      (bytevector-u32-native-set! bv (fx+ at 4) w1)
      (bytevector-s32-native-set! bv (fx+ at 8) x0)
      (bytevector-s32-native-set! bv (fx+ at 12) y0)
      (bytevector-s32-native-set! bv (fx+ at 16) x1)
      (bytevector-s32-native-set! bv (fx+ at 20) y1)
      (bytevector-s32-native-set! bv (fx+ at 24) a)
      (bytevector-s32-native-set! bv (fx+ at 28) b)
      (gpu-recording-recs-n-set! r (fx+ at 32)))))

;; Room for n more extra words in r: => where the next goes, in bytes.
(define (rec-extras-room! r n)
  (let ([at (gpu-recording-extras-n r)] [old (gpu-recording-extras r)])
    (when (> (+ at (* 4 n)) (bytevector-length old))
      (when (eq? r rec-nothing)
        (errorf 'rec-extra! "nothing is being recorded: draw in a frame, a \
                             list or a drawing"))
      (let ([new (make-immobile-bytevector
                  (* 2 (+ (bytevector-length old) (* 4 n))))])
        (bytevector-copy! old 0 new 0 at)
        (gpu-recording-extras-set! r new)))
    at))

(define (rec-extra! v)
  (let* ([r *rec-now*] [at (rec-extras-room! r 1)])
    (bytevector-s32-native-set! (gpu-recording-extras r) at v)
    (gpu-recording-extras-n-set! r (fx+ at 4))))

(define (rec-extra-u32! v)
  (let* ([r *rec-now*] [at (rec-extras-room! r 1)])
    (bytevector-u32-native-set! (gpu-recording-extras r) at v)
    (gpu-recording-extras-n-set! r (fx+ at 4))))

;; Word k of the row at row the recording being written wrote.
(define (rec-extra-ref row k)
  (bytevector-s32-native-ref (gpu-recording-extras *rec-now*)
                             (fx* 4 (fx+ row k))))

;;; ------------------------------------------------------------------ holding

;; A recording as big as like's, or a little one.
(define (rec-make like)
  (make-gpu-recording
   (make-immobile-bytevector
    (if like (bytevector-length (gpu-recording-recs like)) 1024) 0)
   0
   (make-immobile-bytevector
    (if like (bytevector-length (gpu-recording-extras like)) 256) 0)
   4 '() 0 #f #f))

(define (rec-free? r)
  (let ([until (gpu-recording-until r)])
    (and until (fx<= until *gpu-frame-back*))))

;; A recording to write for the holder whose newest is head (#f for none):
;; one of those chained after it that's free, taken off the chain, or a new
;; one; empty.
(define (rec-take! head)
  (let ([r (let loop ([prev head])
             (let ([r (and prev (gpu-recording-next prev))])
               (cond [(not r) (rec-make head)]
                     [(rec-free? r)
                      (gpu-recording-next-set! prev (gpu-recording-next r))
                      r]
                     [else (loop r)])))])
    (when *rec-poison?*
      (bytevector-fill! (gpu-recording-recs r) #xa5)
      (bytevector-fill! (gpu-recording-extras r) #xa5))
    (gpu-recording-recs-n-set! r 0)
    (gpu-recording-extras-n-set! r 4)
    (gpu-recording-runs-set! r '())
    (gpu-recording-until-set! r #f)
    (gpu-recording-next-set! r #f)
    r))

;; r, recorded, frozen with its runs, to be its holder's newest after head
;; (#f for none).
(define (rec-frozen! r runs head)
  (gpu-recording-runs-set! r runs)
  (gpu-recording-version-set! r (if head (fx+ 1 (gpu-recording-version head))
                                    1))
  (gpu-recording-next-set! r head))

;; head, replaced in its holder: the holder stores the newer first, then
;; this reads the frames published, so only frames up to that one may show
;; head.
(define (rec-retired! head)
  (when head (gpu-recording-until-set! head *rec-published*)))

;; The root's recording begins: written from the start.
(define (rec-bytes-begin!)
  (unless *rec-root-next* (set! *rec-root-next* (rec-take! *rec-root*)))
  (gpu-recording-recs-n-set! *rec-root-next* 0)
  (gpu-recording-extras-n-set! *rec-root-next* 4)
  (set! *rec-now* *rec-root-next*))

;; What thunk records goes into a recording of lst's own (a gpu-list's),
;; frozen after with the runs runs-of gives while it's still the one written
;; (the runs end there), and swapped into lst; the recording written before
;; goes on as it was.
(define (rec-into-list! lst thunk runs-of)
  (let ([outer *rec-now*] [r #f])
    (dynamic-wind
     (lambda ()
       (set! r (rec-take! (gpu-list-recording lst)))
       (set! *rec-now* r))
     thunk
     (lambda ()
       (let ([head (gpu-list-recording lst)])
         (rec-frozen! r (runs-of) head)
         (gpu-list-recording-set! lst r)
         (rec-retired! head))
       (set! *rec-now* outer)))))

;; The root's recording frozen with runs: the last frame, the next to lend,
;; and nothing written till the next begins.
(define (rec-freeze! runs)
  (let ([r (or *rec-root-next*
               (errorf 'rec-freeze! "no frame is being recorded"))])
    (let ([head *rec-root*])
      (rec-frozen! r runs head)
      (set! *rec-root* r)
      (rec-retired! head))
    (set! *rec-root-next* #f)
    (when (eq? *rec-now* r) (set! *rec-now* rec-nothing))))

;; Frame f is lent the root's newest recording, numbered the next.
(define (rec-lend! f)
  (set! *rec-published* (fx+ *rec-published* 1))
  (gpu-frame-number-set! f *rec-published*)
  (gpu-frame-root-set! f (or *rec-root*
                             (errorf 'rec-lend! "no frame was recorded"))))

;;; ------------------------------------------------------------------ lists

;; A list to record into, its handle's id given: empty.
(define (rec-list-new id)
  (make-gpu-list id (rec-make #f) '() 0 0))

;; Of the list's newest recording: its length in bytes, of records and of
;; extras; its runs; its version, how many times it was recorded.
(define (gpu-list-recs-n l) (gpu-recording-recs-n (gpu-list-recording l)))
(define (gpu-list-extras-n l) (gpu-recording-extras-n (gpu-list-recording l)))
(define (gpu-list-runs l) (gpu-recording-runs (gpu-list-recording l)))
(define (gpu-list-version l) (gpu-recording-version (gpu-list-recording l)))

;; r's records and extras, copied: (values recs recs-n extras extras-n).
(define (rec-copies r)
  (let ([copy (lambda (bv n)
                (let ([c (make-bytevector n)])
                  (bytevector-copy! bv 0 c 0 n)
                  c))])
    (values (copy (gpu-recording-recs r) (gpu-recording-recs-n r))
            (gpu-recording-recs-n r)
            (copy (gpu-recording-extras r) (gpu-recording-extras-n r))
            (gpu-recording-extras-n r))))

;; A copy of lst, never shown (its id #f), its own bytes, showing runs: what
;; the inspect kit keeps.
(define (rec-list-copy lst runs)
  (let-values ([(recs recs-n extras extras-n)
                (rec-copies (gpu-list-recording lst))])
    (make-gpu-list
     #f
     (make-gpu-recording recs recs-n extras extras-n runs
                         (gpu-list-version lst) #f #f)
     (gpu-list-labels lst) (gpu-list-recorded lst) (gpu-list-took lst))))

;; A copy's bytes: a list that may be shown keeps its own here.
(define (rec-copy-recording who l)
  (when (gpu-list-id l)
    (errorf who "a list shown keeps its bytes in /recorder: read a copy \
                 (rec-list-copy)"))
  (gpu-list-recording l))
(define (gpu-list-recs l)
  (gpu-recording-recs (rec-copy-recording 'gpu-list-recs l)))
(define (gpu-list-extras l)
  (gpu-recording-extras (rec-copy-recording 'gpu-list-extras l)))

;;; ------------------------------------------------------------------ reading

;; The recordings lst holds (a gpu-list, or #f for the root), newest first:
;; (version until free?) each, until #f for the newest.
(define (rec-recordings lst)
  (let loop ([r (if lst (gpu-list-recording lst) *rec-root*)])
    (if r
        (cons (list (gpu-recording-version r) (gpu-recording-until r)
                    (rec-free? r))
              (loop (gpu-recording-next r)))
        '())))

;; How many bytes of records and of extras the last frame has: (values
;; recs-n extras-n), 0 before the first.
(define (rec-last-sizes)
  (let ([r *rec-root*])
    (if r
        (values (gpu-recording-recs-n r) (gpu-recording-extras-n r))
        (values 0 0))))

;; The last frame's records and extras copied into recs and extras, each
;; big enough (rec-last-sizes): the world reads a frame only so.
(define (rec-last-copy! recs extras)
  (let ([r *rec-root*])
    (when r
      (bytevector-copy! (gpu-recording-recs r) 0 recs 0
                        (gpu-recording-recs-n r))
      (bytevector-copy! (gpu-recording-extras r) 0 extras 0
                        (gpu-recording-extras-n r)))))

;; The recording being written, drawn by core0 now on an image pw × ph, the
;; rest of the frame given: its pixels (gpu-drawing->bytes).
(define (rec-drawing->bytes jobs dirty computes table table-n pieces images
                            runs pw ph clear?)
  (let ([r *rec-now*])
    (gpu-drawing->bytes jobs dirty computes (gpu-recording-recs r)
                        (gpu-recording-recs-n r) (gpu-recording-extras r)
                        (gpu-recording-extras-n r) table table-n pieces images
                        runs pw ph clear?)))

;; The recording being written as copies of its own, for a job core0 runs
;; later: (values recs recs-n extras extras-n).
(define (rec-bytes-copies) (rec-copies *rec-now*))
