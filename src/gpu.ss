;;; gpu.ss — main's side of the GPU layer: what the world asks of the GPU,
;;; kept until it hands the host a frame. Images and buffers as handles,
;;; and the jobs that make them; buffers' copies here and what of them
;;; changed, the calls a paint or a compute run makes, the compute runs to
;;; go with the next frame, and the frame filled for the host. The device's
;;; side is core0's (src/host/gpu.ss), and no SDL is named here
;;; (tests/sources.ss).

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
       (make-gpu-image id w h levels #f #f))]))

;; An image that can also be drawn on. It has a chain of levels, each half the
;; last down to a pixel, so that it can be shown smaller: a third more memory.
(define (gpu-image-make-target w h)
  (gpu-image-make w h (fxior gpu-usage-sampler gpu-usage-target)
                  (fxlength (max w h))))

;; The pixels to go up with the next frame: 4·w·h bytes.
(define (gpu-image-write! image bytes)
  (gpu-image-pending-set! image bytes))

(define (gpu-image-release! image)
  (gpu-image-gone?-set! image #t)
  (gpu-ask! (list 'release (gpu-image-id image))))

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
(define (gpu-list-new)
  (make-gpu-list (gpu-new-id!) (make-immobile-bytevector 1024) 0
                 (make-immobile-bytevector 256) 4 '() '() 0 0 0))

;; Its GPU buffers let go of: shown again, it goes up again.
(define (gpu-list-release! l) (gpu-ask! (list 'release (gpu-list-id l))))

;;; ------------------------------------------------------------------ buffers

(defvar *gpu-dirty-buffers* '())

;; At least a word: a read outside it reads word 0 (shader.ss). Its words go
;; up with the next frame.
(define (make-gpu-buffer words)
  (let* ([n (* 4 (max 1 words))]
         [b (make-gpu-buffer* (gpu-new-id!) (make-immobile-bytevector n 0)
                              0 n #f)])
    (gpu-ask! (list 'buffer (gpu-buffer-id b) n))
    (set! *gpu-dirty-buffers* (cons b *gpu-dirty-buffers*))
    b))

(define (gpu-buffer-dirty! b from to)
  (if (fx= (gpu-buffer-from b) (gpu-buffer-to b))
      (begin
        (gpu-buffer-from-set! b from)
        (gpu-buffer-to-set! b to)
        (set! *gpu-dirty-buffers* (cons b *gpu-dirty-buffers*)))
      (begin
        (gpu-buffer-from-set! b (fxmin from (gpu-buffer-from b)))
        (gpu-buffer-to-set! b (fxmax to (gpu-buffer-to b))))))

;; A float, or a whole number that fits 32 bits, a color's word with its top
;; bit, too.
(define (gpu-word-set! bytes at v)
  (cond
    [(flonum? v) (bytevector-ieee-single-native-set! bytes at v)]
    [(fx< v 0) (bytevector-s32-native-set! bytes at v)]
    [else (bytevector-u32-native-set! bytes at v)]))

;; Word i.
(define (gpu-buffer-set! b i v)
  (let ([at (fx* 4 i)])
    (gpu-word-set! (gpu-buffer-bytes b) at v)
    (gpu-buffer-dirty! b at (fx+ at 4))))

(define (gpu-buffer-ref b i)
  (bytevector-s32-native-ref (gpu-buffer-bytes b) (fx* 4 i)))

(define (gpu-buffer-release! b)
  (set! *gpu-dirty-buffers* (remq b *gpu-dirty-buffers*))
  ;; a run waiting for the frame would name it
  (set! *gpu-computes*
    (filter (lambda (run)
              (not (memv (gpu-buffer-id b)
                         (append (cadddr run) (list-ref run 4)))))
            *gpu-computes*))
  (gpu-buffer-gone?-set! b #t)
  (gpu-ask! (list 'release (gpu-buffer-id b))))

;; What a shader left in the buffer: read back into the copy here. => its
;; bytes
(define (gpu-buffer-read! b) (gpu-buffer-download! (gpu-take-jobs!) b))

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
                                  (if a
                                      (fxquotient (bytevector-length
                                                   (gpu-buffer-bytes (cdr a)))
                                                  4)
                                      0)))
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
  (let ([dirty *gpu-dirty-buffers*])
    (set! *gpu-dirty-buffers* '())
    (gpu-compute-now! (gpu-compute-run shader w h args) (gpu-take-jobs!)
                      dirty)))

;; Compute runs to go with the next frame, the newest first.
(defvar *gpu-computes* '())

;; Runs a compute shader over w × h cells with the next frame, ahead of what it
;; draws, so that a paint shows what it wrote. Nothing waits for it.
(define (gpu-compute-soon! shader w h . args)
  (set! *gpu-computes*
    (cons (gpu-compute-run shader w h args) *gpu-computes*)))

;; What main asked of the GPU since it last handed it on, taken from it: the
;; jobs and the compute runs in order, and the dirty buffers.
(define (gpu-take-asks!)
  (let ([dirty *gpu-dirty-buffers*] [runs (reverse *gpu-computes*)])
    (set! *gpu-dirty-buffers* '())
    (set! *gpu-computes* '())
    (values (gpu-take-jobs!) dirty runs)))

;;; ------------------------------------------------------------------ frames

;; Main's side: the frame filled, what it asked of the GPU since handed on
;; with it. => the frame
(define (gpu-publish recs recs-n extras extras-n table table-n pieces images
                     runs mode earlier)
  (let ([f (gpu-frame-take!)])
    (let-values ([(jobs dirty computes) (gpu-take-asks!)])
      (gpu-frame-jobs-set! f jobs)
      (gpu-frame-dirty-set! f dirty)
      (gpu-frame-computes-set! f computes))
    (gpu-frame-recs-set! f recs)
    (gpu-frame-recs-n-set! f recs-n)
    (gpu-frame-extras-set! f extras)
    (gpu-frame-extras-n-set! f extras-n)
    (gpu-frame-table-set! f table)
    (gpu-frame-table-n-set! f table-n)
    (gpu-frame-pieces-set! f pieces)
    (gpu-frame-images-set! f images)
    (gpu-frame-runs-set! f runs)
    (gpu-frame-mode-set! f mode)
    (gpu-frame-earlier-set! f earlier)
    f))
