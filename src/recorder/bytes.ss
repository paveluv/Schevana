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
;;;
;;; What the world writes into buffers and images goes the same way, in
;;; the frame's writes (src/host/gpu.ss's gpu-send-writes!), and so do the
;;; rows an app paints, in loans of the image's own.

;; What the world may name of this environment's.
(define recorder-interface
  '(rec-write! rec-extra! rec-extra-u32! rec-extra-ref rec-extra-at
    rec-count rec-bytes-begin! rec-into-list! rec-freeze! rec-lend!
    rec-last-sizes rec-last-copy! rec-drawing->bytes rec-bytes-copies
    rec-list-new rec-list-copy gpu-list-recs-n gpu-list-extras-n
    gpu-list-runs gpu-list-version gpu-list-recs gpu-list-extras
    rec-earlier-add! rec-recordings rec-buffer-set! rec-pixel-set!
    rec-image-rows! rec-writes-pending? rec-compute-now!
    rec-submit-computes! rec-buffer-read!))

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

;; A record's eight words into recording rec, counted once all are in.
(define-syntax rec-words-put!
  (syntax-rules ()
    [(_ rec w0 w1 x0 y0 x1 y1 a b)
     (let* ([r rec] [at (gpu-recording-recs-n r)])
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
         (gpu-recording-recs-n-set! r (fx+ at 32))))]))

(define (rec-write! w0 w1 x0 y0 x1 y1 a b)
  (rec-words-put! *rec-now* w0 w1 x0 y0 x1 y1 a b))

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

;; Free once core0 says it's done reading it, by a frame back or by
;; setting its until itself: what it read before, read before this.
(define (rec-free? r)
  (let ([until (gpu-recording-until r)])
    (memory-order-acquire)
    (and until (fx<= until *gpu-frame-back*))))

;; Of the recordings chained after head (#f for none), one that's free,
;; taken off the chain, or #f.
(define (rec-take-free! head)
  (let loop ([prev head])
    (let ([r (and prev (gpu-recording-next prev))])
      (cond [(not r) #f]
            [(rec-free? r)
             (gpu-recording-next-set! prev (gpu-recording-next r))
             r]
            [else (loop r)]))))

;; A recording to write for the holder whose newest is head (#f for none):
;; one of those chained after it that's free, or a new one; empty.
(define (rec-take! head)
  (let ([r (or (rec-take-free! head) (rec-make head))])
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

;; The copies drawn ahead of frames, each read by one: chained after a head
;; that's never written; and those the next frame is lent, (image .
;; recording), newest first.
(defvar *rec-earlier* (rec-make #f))
(defvar *rec-earlier-next* '())

;; A list the world made of its own bytes (the Pipeline's flattened frames),
;; drawn on image ahead of the next frame: copied as it's handed, into a
;; recording only that frame reads, free once core0 gave it back. The copy
;; is the Pipeline's cost alone; if another app needs a list drawn on an
;; image, make it zero copy: hand core0 a recorded list (a gpu-list), whose
;; frozen recording it draws as it draws any list, and no bytes.
(define (rec-earlier-add! image recs recs-n extras extras-n runs)
  (let ([r (rec-take! *rec-earlier*)]
        [fit (lambda (bv n)
               (if (< (bytevector-length bv) n)
                   (make-immobile-bytevector (* 2 n))
                   bv))])
    (gpu-recording-recs-set! r (fit (gpu-recording-recs r) recs-n))
    (gpu-recording-extras-set! r (fit (gpu-recording-extras r) extras-n))
    (bytevector-copy! recs 0 (gpu-recording-recs r) 0 recs-n)
    (bytevector-copy! extras 0 (gpu-recording-extras r) 0 extras-n)
    (gpu-recording-recs-n-set! r recs-n)
    (gpu-recording-extras-n-set! r extras-n)
    (gpu-recording-runs-set! r runs)
    (gpu-recording-until-set! r (fx+ *rec-published* 1))
    (gpu-recording-next-set! r (gpu-recording-next *rec-earlier*))
    (gpu-recording-next-set! *rec-earlier* r)
    (set! *rec-earlier-next* (cons (cons image r) *rec-earlier-next*))))

;; Frame f is lent the root's newest recording, numbered the next, the
;; writes, and the copies to draw ahead of it.
(define (rec-lend! f)
  (set! *rec-published* (fx+ *rec-published* 1))
  (gpu-frame-number-set! f *rec-published*)
  (gpu-frame-writes-set! f (rec-writes-take!))
  (gpu-frame-earlier-set! f (reverse *rec-earlier-next*))
  (set! *rec-earlier-next* '())
  (gpu-frame-root-set! f (or *rec-root*
                             (errorf 'rec-lend! "no frame was recorded"))))

;;; ------------------------------------------------------------------ writes
;;; What the world writes into buffers and images: spans in a recording of
;;; their own, the writes, handed to core0 whole with the next frame, or
;;; with a call that sends them sooner, and free again once that frame is
;;; back. A word or a pixel is copied in; rows an app paints are painted in
;;; a loan, a recording whose records are the image's pixels, never written
;;; while core0 may read it. So core0 reads what was painted, and only an
;;; app that keeps a loan's bytes past its paint, against the rule, can
;;; tear what it painted: its own image's pixels, never another's.

(defvar *rec-writes-head* (rec-make #f))  ; never written: those handed
(defvar *rec-writes* #f)       ; the writes being written, or #f
(defvar *rec-writes-last* #f)  ; their last loan, or #f
(defvar *rec-loan-stamp* 0)    ; loans lent so far: the last one's stamp

;; The writes being written, taken when the first goes in.
(define (rec-writes-now)
  (or *rec-writes*
      (begin
        (set! *rec-writes* (rec-take! *rec-writes-head*))
        (set! *rec-writes-last* #f)
        *rec-writes*)))

(define (rec-writes-pending?) (and *rec-writes* #t))

;; A word into the writes, v a float or a whole number of 32 bits: kind 0,
;; word x of buffer id, or kind 1, pixel (x, y) of image id. Next to the
;; last span's word, it lengthens that span, whose words end the extras.
(define (rec-word-write! kind id x y v)
  (let* ([r (rec-writes-now)]
         [at (rec-extras-room! r 1)]
         [extras (gpu-recording-extras r)]
         [recs (gpu-recording-recs r)]
         [last (fx- (gpu-recording-recs-n r) 32)])
    ;; a word that can't go raises before anything counts it
    (cond [(flonum? v) (bytevector-ieee-single-native-set! extras at v)]
          [(fx< v 0) (bytevector-s32-native-set! extras at v)]
          [else (bytevector-u32-native-set! extras at v)])
    (if (and (fx>= last 0)
             (fx= (bytevector-u32-native-ref recs last) kind)
             (eqv? (bytevector-u32-native-ref recs (fx+ last 4)) id)
             (eqv? (bytevector-s32-native-ref recs (fx+ last 12)) y)
             (eqv? (fx+ (bytevector-s32-native-ref recs (fx+ last 8))
                        (bytevector-s32-native-ref recs (fx+ last 20)))
                   x))
        (bytevector-s32-native-set!
         recs (fx+ last 20)
         (fx+ 1 (bytevector-s32-native-ref recs (fx+ last 20))))
        (rec-words-put! r kind id x y at 1 0 0))
    (gpu-recording-extras-n-set! r (fx+ at 4))))

(define (rec-buffer-set! id i v) (rec-word-write! 0 id i 0 v))
(define (rec-pixel-set! id x y pixel) (rec-word-write! 1 id x y pixel))

;; A recording of bytes alone: a loan, or the head its image chains them
;; after.
(define (rec-loan-make bytes)
  (make-gpu-recording bytes 0 (make-bytevector 0) 0 '() 0 #f #f))

;; A loan of image's to paint: one of those chained after its loans' head
;; that's free, or a new one; stamped the next, and not free till handed.
(define (rec-loan-take! image)
  (let* ([head (or (gpu-image-loans image)
                   (let ([h (rec-loan-make (make-bytevector 0))])
                     (gpu-image-loans-set! image h)
                     h))]
         [loan (or (rec-take-free! head)
                   (rec-loan-make (make-immobile-bytevector
                                   (* 4 (gpu-image-w image)
                                      (gpu-image-h image)))))])
    (when *rec-poison?* (bytevector-fill! (gpu-recording-recs loan) #xa5))
    (set! *rec-loan-stamp* (fx+ *rec-loan-stamp* 1))
    (gpu-recording-version-set! loan *rec-loan-stamp*)
    (gpu-recording-until-set! loan #f)
    loan))

;; Rows y0 .. y1 of image painted by (paint bytes): bytes, a loan's, are
;; the image's pixels, row after row, and paint writes every pixel of those
;; rows, whatever they held. They go into the writes once paint returns; a
;; paint that doesn't writes nothing, and one that returns again raises.
(define (rec-image-rows! image y0 y1 paint)
  (unless (fx<= 0 y0 y1 (gpu-image-h image))
    (errorf 'rec-image-rows! "rows ~s .. ~s aren't the image's" y0 y1))
  (unless (fx= y0 y1)
    (let* ([loan (rec-loan-take! image)]
           [stamp (gpu-recording-version loan)])
      (paint (gpu-recording-recs loan))
      (unless (eqv? (gpu-recording-version loan) stamp)
        (errorf 'rec-image-rows! "a paint returned twice"))
      (gpu-recording-version-set! loan 0)
      (gpu-recording-runs-set! loan '())
      (let* ([r (rec-writes-now)]
             [last *rec-writes-last*]
             [at (fx- (gpu-recording-recs-n r) 32)]
             [word (lambda (k)
                     (bytevector-s32-native-ref (gpu-recording-recs r)
                                                (fx+ at k)))])
        (if (and last
                 (fx= (word 0) 2)
                 (eqv? (word 4) (gpu-image-id image))
                 (fx<= y0 (word 12))
                 (fx<= (fx+ (word 12) (word 20)) y1))
            ;; the last write, rows of the image's this paint covers: its
            ;; loan takes these bytes, and this loan, its old ones, is free
            ;; again, so paints faster than frames take two loans, not one
            ;; each
            (let ([bytes (gpu-recording-recs loan)])
              (gpu-recording-recs-set! loan (gpu-recording-recs last))
              (gpu-recording-recs-set! last bytes)
              (gpu-recording-until-set! loan 0)
              (bytevector-s32-native-set! (gpu-recording-recs r) (fx+ at 12)
                                          y0)
              (bytevector-s32-native-set! (gpu-recording-recs r) (fx+ at 20)
                                          (fx- y1 y0)))
            (begin
              (rec-words-put! r 2 (gpu-image-id image) 0 y0 0 (fx- y1 y0) 0 0)
              (gpu-recording-runs-set! (or last r) loan)
              (set! *rec-writes-last* loan))))
      (let ([head (gpu-image-loans image)])
        (gpu-recording-next-set! loan (gpu-recording-next head))
        (gpu-recording-next-set! head loan)))))

;; The writes, to hand core0: free again, with their loans, once core0 has
;; sent them, which it says itself. => them, or #f for none.
(define (rec-writes-take!)
  (let ([r *rec-writes*])
    (when r
      (gpu-recording-until-set! r (greatest-fixnum))
      (let loop ([loan (gpu-recording-runs r)])
        (when (gpu-recording? loan)
          (gpu-recording-until-set! loan (greatest-fixnum))
          (loop (gpu-recording-runs loan))))
      (gpu-recording-next-set! r (gpu-recording-next *rec-writes-head*))
      (gpu-recording-next-set! *rec-writes-head* r)
      (set! *rec-writes* #f)
      (set! *rec-writes-last* #f))
    r))

;; Calls that hand core0 the writes with no frame, run now while one thread
;; plays both: a compute run; and buffer id's bytes, read back (#f if id
;; names none). On a world of its own thread they'd hold main till core0
;; answered: they raise.
(define (rec-one-thread who)
  (when (host-forked?)
    (errorf who "readbacks never hold main: on a world of its own thread, \
                 use what hands the bytes to a then")))

(define (rec-compute-now! run jobs)
  (rec-one-thread 'gpu-compute!)
  (gpu-compute-now! run jobs (rec-writes-take!)))
(define (rec-buffer-read! jobs id)
  (rec-one-thread 'gpu-buffer-read!)
  (gpu-buffer-download! jobs (rec-writes-take!) id))

;; The compute runs no frame took, and the writes, sent with no frame: by a
;; job of core0's, or at once while one thread plays both.
(define (rec-submit-computes! runs jobs)
  (let ([writes (rec-writes-take!)])
    (if (host-forked?)
        (host-post-submit! runs jobs writes)
        (gpu-submit-computes! runs jobs writes))))

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

;; The recordings x holds, newest first: x a gpu-list, #f for the root,
;; 'earlier for the copies drawn ahead of frames, 'writes for the writes
;; handed, or a gpu-image for its loans. (version until free?) each, until
;; #f for the newest of a list or the root.
(define (rec-recordings x)
  (let loop ([r (cond [(eq? x 'earlier) (gpu-recording-next *rec-earlier*)]
                      [(eq? x 'writes) (gpu-recording-next *rec-writes-head*)]
                      [(gpu-image? x)
                       (let ([head (gpu-image-loans x)])
                         (and head (gpu-recording-next head)))]
                      [x (gpu-list-recording x)]
                      [else *rec-root*])])
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
;; rest of the frame given, the writes with it: its pixels
;; (gpu-drawing->bytes).
(define (rec-drawing->bytes jobs computes table table-n pieces runs pw ph
                            clear?)
  (rec-one-thread 'drawing->bytes)
  (let ([r *rec-now*])
    (gpu-drawing->bytes jobs (rec-writes-take!) computes
                        (gpu-recording-recs r) (gpu-recording-recs-n r)
                        (gpu-recording-extras r) (gpu-recording-extras-n r)
                        table table-n pieces runs pw ph clear?)))

;; The recording being written as copies of its own, for a job core0 runs
;; later: (values recs recs-n extras extras-n).
(define (rec-bytes-copies) (rec-copies *rec-now*))
