;;; gpu.ss — main's side of the GPU layer: what the world asks of the GPU,
;;; kept until it hands the host a frame. Images and buffers as handles,
;;; and the jobs that make them; the calls a paint or a compute run makes,
;;; the compute runs to go with the next frame, and the frame filled for
;;; the host. What's written into buffers and images "/recorder" keeps
;;; (src/recorder/bytes.ss). The device's side is core0's (src/host/gpu.ss),
;;; and no SDL is named here (tests/sources.ss).

;;; ------------------------------------------------------------------ handles
;;; An image or a buffer main holds is a handle, with an integer id; the SDL
;;; object behind it is core0's. Main makes the handle at once and asks for
;;; the object by a job, which core0 runs before anything that needs it.

(defvar *gpu-next-id* 1)

;; The jobs asked of core0 since it last took them, the newest first.
(defvar *gpu-jobs* '())

(define (gpu-new-id!)
  (let ([id *gpu-next-id*])
    (set! *gpu-next-id* (+ id 1))
    id))

(define (gpu-ask! job) (set! *gpu-jobs* (cons job *gpu-jobs*)))

;; The jobs asked since, in order, taken from main.
(define (gpu-take-jobs!)
  (let ([jobs (reverse *gpu-jobs*)])
    (set! *gpu-jobs* '())
    jobs))

;;; ------------------------------------------------------------------ images

;; An image of w × h, premultiplied BGRA, its pixels on the GPU alone; usage
;; and levels as the GPU layer names them.
(define gpu-image-make
  (case-lambda
    [(w h) (gpu-image-make w h gpu-usage-sampler 1)]
    [(w h usage levels)
     (let ([id (gpu-new-id!)])
       (gpu-ask! (list 'texture id w h usage levels))
       (gpu-images-sweep!)
       (make-gpu-image id w h levels #f #f))]))

;; An image that can also be drawn on. It has a chain of levels, each half the
;; last down to a pixel, so that it can be shown smaller: a third more memory.
(define (gpu-image-make-target w h)
  (gpu-image-make w h (fxior gpu-usage-sampler gpu-usage-target)
                  (fxlength (max w h))))

(define (gpu-image-release! image)
  (gpu-image-gone?-set! image #t)
  (gpu-ask! (list 'release (gpu-image-id image))))

;; Images whose holders are gone, let go of: (gpu-image-held! holder image)
;; lets image go once nothing holds holder, if it wasn't already; a second
;; release finds nothing. Swept as images are made.
(defvar *gpu-images-held* (make-guardian))

(define (gpu-image-held! holder image) (*gpu-images-held* holder image))

(define (gpu-images-sweep!)
  (let loop ()
    (let ([image (*gpu-images-held*)])
      (when image
        (gpu-image-release! image)
        (loop)))))

;; The glyphs' atlas as an image, to draw: one channel, coverage, as the
;; glyph records read it. Core0's own, never let go of.
(defvar *gpu-atlas-image* #f)

(define (gpu-atlas-image)
  (or *gpu-atlas-image*
      (let ([id (gpu-new-id!)])
        (gpu-ask! (list 'atlas id))
        (set! *gpu-atlas-image*
          (make-gpu-image id gpu-atlas-side gpu-atlas-side 1 #f #f))
        *gpu-atlas-image*)))

;;; ------------------------------------------------------------------ lists

;; A list to record into (record-list!), a handle like an image's: its GPU
;; buffers are core0's.
(define (gpu-list-new) (rec-list-new (gpu-new-id!)))

;; Its GPU buffers let go of: shown again, it goes up again.
(define (gpu-list-release! l) (gpu-ask! (list 'release (gpu-list-id l))))

;;; ------------------------------------------------------------------ buffers

;; At least a word: a read outside it reads word 0 (shader.ss). Zeroed.
(define (make-gpu-buffer words)
  (let* ([n (* 4 (max 1 words))]
         [b (make-gpu-buffer* (gpu-new-id!) n #f)])
    (gpu-ask! (list 'buffer (gpu-buffer-id b) n))
    b))

(define (gpu-buffer-words b) (fxquotient (gpu-buffer-size b) 4))

;; A float, or a whole number that fits 32 bits, a color's word with its top
;; bit, too.
(define (gpu-word-set! bytes at v)
  (cond
    [(flonum? v) (bytevector-ieee-single-native-set! bytes at v)]
    [(fx< v 0) (bytevector-s32-native-set! bytes at v)]
    [else (bytevector-u32-native-set! bytes at v)]))

;; Word i: it goes up with the next frame, or the next compute run.
(define (gpu-buffer-set! b i v)
  (unless (fx< -1 i (gpu-buffer-words b))
    (errorf 'gpu-buffer-set! "~s isn't a word of a buffer of ~a" i
            (gpu-buffer-words b)))
  (rec-buffer-set! (gpu-buffer-id b) i v))

(define (gpu-buffer-release! b)
  ;; a run waiting for the frame would name it
  (set! *gpu-computes*
    (filter (lambda (run)
              (not (memv (gpu-buffer-id b)
                         (append (cadddr run) (list-ref run 4)))))
            *gpu-computes*))
  (gpu-buffer-gone?-set! b #t)
  (gpu-ask! (list 'release (gpu-buffer-id b))))

;; What the buffer holds, what was set and what shaders wrote, read back
;; now: => its bytes, a copy of the world's own, or #f once it's let go of.
(define (gpu-buffer-read! b)
  (rec-buffer-read! (gpu-take-jobs!) (gpu-buffer-id b)))

;;; ------------------------------------------------------------------ calls

;; The arguments of the parameters that keep? takes.
(define (gpu-args-of keep? params args)
  (cond [(null? params) '()]
        [(keep? (car params))
         (cons (car args) (gpu-args-of keep? (cdr params) (cdr args)))]
        [else (gpu-args-of keep? (cdr params) (cdr args))]))

(define (gpu-buffer-param? p) (memq (cadr p) '(fx-buffer fl-buffer)))

;; A shader's arguments in its parameters' order, by their kinds, its
;; hidden uniforms first, then its buffers' lengths: one it isn't handed
;; here, a paint's list's, the frame fills in => a gpu-call
(define (gpu-make-call shader hidden params args)
  (let* ([given (map cons (map car params) args)]
         [values (append hidden
                         (gpu-args-of (lambda (p)
                                        (memq (cadr p) '(fixnum flonum)))
                                      params args)
                         (map (lambda (p)
                                (let ([a (assq (car p) given)])
                                  (if a (gpu-buffer-words (cdr a)) 0)))
                              (filter gpu-buffer-param?
                                      (shader-params shader))))]
         [bytes (make-bytevector (max 4 (* 4 (length values))) 0)])
    (for-each (lambda (v i) (gpu-word-set! bytes (* 4 i) v))
              values (iota (length values)))
    (make-gpu-call shader bytes
                   (gpu-args-of gpu-buffer-param? params args))))

;; A compute run: (call w h written read), the buffers by id.
(define (gpu-compute-run shader w h args)
  (let* ([params (shader-params shader)]
         [ids (lambda (write?)
                (map gpu-buffer-id
                     (gpu-args-of (lambda (p)
                                    (and (gpu-buffer-param? p)
                                         (eq? write? (pair? (cddr p)))))
                                  params args)))])
    (list (gpu-make-call shader (list w h) params args) w h (ids #t) (ids #f))))

;;; ------------------------------------------------------------------ compute

;; Runs a compute shader over w × h cells, now, and waits for it: its buffers
;; are then ready to read with gpu-buffer-read!.
(define (gpu-compute! shader w h . args)
  (rec-compute-now! (gpu-compute-run shader w h args) (gpu-take-jobs!)))

;; Compute runs to go with the next frame, the newest first.
(defvar *gpu-computes* '())

;; Runs a compute shader over w × h cells soon: with the frame this turn
;; makes, ahead of what it draws, so that a paint shows what it wrote, or at
;; the turn's end with none (gpu-computes-send!). Nothing waits for it.
(define (gpu-compute-soon! shader w h . args)
  (set! *gpu-computes*
    (cons (gpu-compute-run shader w h args) *gpu-computes*)))

;; What main asked of the GPU since it last handed it on, taken from it: the
;; jobs and the compute runs, in order.
(define (gpu-take-asks!)
  (let ([runs (reverse *gpu-computes*)])
    (set! *gpu-computes* '())
    (values (gpu-take-jobs!) runs)))

;; Is there what a turn's end sends, with no frame: compute runs or writes?
(define (gpu-asks-pending?)
  (or (pair? *gpu-computes*) (rec-writes-pending?)))

;; At a turn's end: compute runs and writes no frame took go now, on their
;; own, so that one an app steps on a timer, its window unseen, isn't kept
;; waiting, and what's written is held no longer than a turn.
(define (gpu-computes-send!)
  (unless (eq? *host* 'none)
    (let-values ([(jobs runs) (gpu-take-asks!)])
      (rec-submit-computes! runs jobs))))

;;; ------------------------------------------------------------------ frames

;; The frames core0 gave back, to fill again, and the last of them.
(defvar *gpu-frames-free* '())
(defvar *gpu-frame-last* #f)

(define (gpu-frame-free! f)
  (set! *gpu-frames-free* (cons f *gpu-frames-free*))
  (set! *gpu-frame-last* f))

;; Main's side: the frame filled, what it asked of the GPU since handed on
;; with it; its writes "/recorder"'s to hand (rec-lend!). => the frame
(define (gpu-publish table table-n pieces mode in-flight)
  (let ([f (if (pair? *gpu-frames-free*)
               (let ([f (car *gpu-frames-free*)])
                 (set! *gpu-frames-free* (cdr *gpu-frames-free*))
                 f)
               (gpu-frame-make))])
    (let-values ([(jobs computes) (gpu-take-asks!)])
      (gpu-frame-jobs-set! f jobs)
      (gpu-frame-computes-set! f computes))
    (gpu-frame-table-set! f table)
    (gpu-frame-table-n-set! f table-n)
    (gpu-frame-pieces-set! f pieces)
    (gpu-frame-mode-set! f mode)
    (gpu-frame-in-flight-set! f in-flight)
    f))
