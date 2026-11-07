;;; gpu.ss — the GPU layer. It speaks Schevana's terms (lists of records,
;;; runs, images, buffers, frames), and only this file names SDL's GPU calls
;;; or knows a driver from another, so that another back end stays a swap.
;;;
;;; Everything that touches a device hangs off one record, a renderer, so
;;; that one can be rebuilt on another device. SDL handles what the GPU still
;;; holds: buffers uploaded and transfer buffers mapped with cycling on are
;;; ring buffers, and no fence bookkeeping is needed for them.

(define-record-type renderer
  (nongenerative schevana-renderer-1)
  (fields kind device sampler atlas blank
          (mutable pipelines)      ; (format . vector of pipelines by mode)
          (mutable paints)         ; shader: ((format . pipeline) ...)
          (mutable records)        ; each (buffer . capacity)
          (mutable extras)
          (mutable glyphs)
          (mutable transfer)       ; (transfer buffer . capacity)
          (mutable window)         ; the host window it draws to, or 0
          (mutable target)         ; an offscreen texture, or 0
          (mutable target-w)
          (mutable target-h)
          (mutable fence)))        ; the last frame's, or #f

(defvar *renderer* #f)
(defvar *gpu-scratch* (foreign-alloc 2048))   ; structs, on their way to SDL

(define gpu-atlas-side 4096)
(define gpu-format-r8 2)
(define gpu-format-bgra8 12)
(define gpu-usage-sampler 1)
(define gpu-usage-target 2)
(define gpu-usage-graphics-read 8)
(define gpu-usage-compute-read 16)
(define gpu-usage-compute-write 32)
;; What shaders are, to SDL: SPIR-V, or MSL.
(define gpu-shader-format (if (eq? shader-target 'msl) 16 2))
(define gpu-blend-zero 1)
(define gpu-blend-one 2)
(define gpu-blend-one-minus-source 4)
(define gpu-blend-one-minus-target 6)
(define gpu-blend-one-minus-source-alpha 8)
(define gpu-op-add 1)
(define gpu-op-subtract 2)
(define gpu-load-clear 1)
(define gpu-address-clamp 2)

;;; ---- SDL's structs. Chez lays them out by the platform's C rules, so no
;;; offset here is counted by hand. Each has a place of its own in the
;;; scratch memory, and a pointer made once: a frame allocates none.

(define-syntax gpu-struct
  (syntax-rules ()
    [(_ name pointer offset type)
     (begin
       (define-ftype name type)
       (define pointer (make-ftype-pointer name (+ *gpu-scratch* offset))))]))

(define (gpu-zero! pointer size)
  (let ([at (ftype-pointer-address pointer)])
    (do ([i 0 (fx+ i 1)]) ((fx= i size))
      (foreign-set! 'unsigned-8 at i 0))))

(gpu-struct gpu-texture-info gpu-texture-info* 0
  (struct [type int] [format int] [usage unsigned-32]
          [width unsigned-32] [height unsigned-32] [layers unsigned-32]
          [levels unsigned-32] [samples int] [props unsigned-32]))
(gpu-struct gpu-sampler-info gpu-sampler-info* 64
  (struct [min-filter int] [mag-filter int] [mipmap-mode int]
          [address-u int] [address-v int] [address-w int]
          [lod-bias float] [anisotropy float] [compare int]
          [min-lod float] [max-lod float]
          [enable-anisotropy unsigned-8] [enable-compare unsigned-8]
          [pad1 unsigned-8] [pad2 unsigned-8] [props unsigned-32]))
(gpu-struct gpu-shader-info gpu-shader-info* 128
  (struct [code-size size_t] [code void*] [entry void*] [format unsigned-32]
          [stage int] [samplers unsigned-32] [storage-textures unsigned-32]
          [storage-buffers unsigned-32] [uniform-buffers unsigned-32]
          [props unsigned-32]))
(gpu-struct gpu-buffer-info gpu-buffer-info* 192
  (struct [usage unsigned-32] [size unsigned-32] [props unsigned-32]))
(gpu-struct gpu-transfer-info gpu-transfer-info* 208
  (struct [usage int] [size unsigned-32] [props unsigned-32]))
(gpu-struct gpu-transfer-location gpu-transfer-location* 224
  (struct [transfer void*] [offset unsigned-32]))
(gpu-struct gpu-buffer-region gpu-buffer-region* 240
  (struct [buffer void*] [offset unsigned-32] [size unsigned-32]))
(gpu-struct gpu-texture-transfer gpu-texture-transfer* 256
  (struct [transfer void*] [offset unsigned-32] [pixels-per-row unsigned-32]
          [rows-per-layer unsigned-32]))
(gpu-struct gpu-texture-region gpu-texture-region* 288
  (struct [texture void*] [mip unsigned-32] [layer unsigned-32]
          [x unsigned-32] [y unsigned-32] [z unsigned-32]
          [w unsigned-32] [h unsigned-32] [d unsigned-32]))
(gpu-struct gpu-color-target gpu-color-target* 336
  (struct [texture void*] [mip unsigned-32] [layer unsigned-32]
          [r float] [g float] [b float] [a float]
          [load-op int] [store-op int]
          [resolve void*] [resolve-mip unsigned-32] [resolve-layer unsigned-32]
          [cycle unsigned-8] [cycle-resolve unsigned-8]
          [pad1 unsigned-8] [pad2 unsigned-8]))
(gpu-struct gpu-target-description gpu-target-description* 408
  (struct [format int]
          [source-color int] [target-color int] [color-op int]
          [source-alpha int] [target-alpha int] [alpha-op int]
          [write-mask unsigned-8] [enable-blend unsigned-8]
          [enable-write-mask unsigned-8] [pad unsigned-8]))
(gpu-struct gpu-pipeline-info gpu-pipeline-info* 448
  (struct [vertex-shader void*] [fragment-shader void*]
          [vertex-input (struct [buffers void*] [buffer-count unsigned-32]
                                [attributes void*]
                                [attribute-count unsigned-32])]
          [primitive int]
          [rasterizer (struct [fill-mode int] [cull-mode int] [front-face int]
                              [bias-constant float] [bias-clamp float]
                              [bias-slope float] [enable-bias unsigned-8]
                              [enable-depth-clip unsigned-8]
                              [pad1 unsigned-8] [pad2 unsigned-8])]
          [multisample (struct [count int] [mask unsigned-32]
                               [enable-mask unsigned-8] [pad1 unsigned-8]
                               [pad2 unsigned-8] [pad3 unsigned-8])]
          [depth-stencil (struct [compare int]
                                 [back (array 4 int)] [front (array 4 int)]
                                 [compare-mask unsigned-8]
                                 [write-mask unsigned-8]
                                 [enable-depth unsigned-8]
                                 [enable-depth-write unsigned-8]
                                 [enable-stencil unsigned-8] [pad1 unsigned-8]
                                 [pad2 unsigned-8] [pad3 unsigned-8])]
          [target-info (struct [targets void*] [count unsigned-32]
                               [depth-format int] [has-depth unsigned-8]
                               [pad1 unsigned-8] [pad2 unsigned-8]
                               [pad3 unsigned-8])]
          [props unsigned-32]))
(gpu-struct gpu-storage-buffers gpu-storage-buffers* 760
  (array 8 void*))
(gpu-struct gpu-compute-info gpu-compute-info* 824
  (struct [code-size size_t] [code void*] [entry void*] [format unsigned-32]
          [samplers unsigned-32] [read-textures unsigned-32]
          [read-buffers unsigned-32] [write-textures unsigned-32]
          [write-buffers unsigned-32] [uniform-buffers unsigned-32]
          [group-x unsigned-32] [group-y unsigned-32] [group-z unsigned-32]
          [props unsigned-32]))
(gpu-struct gpu-buffer-bindings gpu-buffer-bindings* 904
  (array 8 (struct [buffer void*] [cycle unsigned-8] [pad1 unsigned-8]
                   [pad2 unsigned-8] [pad3 unsigned-8])))
(gpu-struct gpu-sampler-bindings gpu-sampler-bindings* 672
  (array 2 (struct [texture void*] [sampler void*])))
(gpu-struct gpu-frame-uniforms gpu-frame-uniforms* 704
  (struct [w float] [h float] [first int]))
(gpu-struct gpu-swapchain-out gpu-swapchain-out* 720
  (struct [texture void*] [w unsigned-32] [h unsigned-32]))
(gpu-struct gpu-fence-list gpu-fence-list* 736
  (array 1 void*))

;; Where a struct is, for the C call that takes it.
(define (gpu-at pointer) (ftype-pointer-address pointer))

(define (gpu-must who p)
  (when (eqv? p 0) (errorf who "~a" (sdl-get-error)))
  p)

;;; ------------------------------------------------------------------ devices

;; On Linux, which Vulkan drivers may load, by a file for each: lavapipe
;; alone for the CPU, the others for the GPU, so that lavapipe and LLVM
;; never load then. Elsewhere the driver is SDL's choice.
(define (gpu-driver-files kind)
  (let ([files
         (apply append
                (map (lambda (dir)
                       (if (file-directory? dir)
                           (map (lambda (f) (string-append dir "/" f))
                                (filter (lambda (f) (string-suffix? ".json" f))
                                        (directory-list dir)))
                           '()))
                     '("/usr/share/vulkan/icd.d" "/etc/vulkan/icd.d"
                       "/usr/local/share/vulkan/icd.d")))])
    (define (lavapipe? f) (string-contains-ci? f "lvp_icd"))
    (if (eq? kind 'cpu) (filter lavapipe? files) (remp lavapipe? files))))

;; With no window: what renders, and SDL's video driver, none named meaning
;; its choice. Metal is a Mac's one renderer and needs its real video driver,
;; which opens no window until asked; Vulkan has lavapipe for this.
(define gpu-windowless-kind (if (eq? shader-target 'msl) 'gpu 'cpu))
(define gpu-windowless-video (if (eq? shader-target 'msl) #f "offscreen"))

;; A device of this kind, 'gpu or 'cpu; or #f.
(define (gpu-open-device kind)
  (let ([files (gpu-driver-files kind)])
    (unless (null? files)
      (putenv "VK_DRIVER_FILES" (string-join files ":")))
    (let ([d (sdl-create-gpu-device gpu-shader-format #f 0)])
      (and (not (eqv? d 0)) d))))

(define (gpu-make-texture device format usage w h)
  (let ([p gpu-texture-info*])
    (gpu-zero! p (ftype-sizeof gpu-texture-info))
    (ftype-set! gpu-texture-info (format) p format)
    (ftype-set! gpu-texture-info (usage) p usage)
    (ftype-set! gpu-texture-info (width) p w)
    (ftype-set! gpu-texture-info (height) p h)
    (ftype-set! gpu-texture-info (layers) p 1)
    (ftype-set! gpu-texture-info (levels) p 1)
    (gpu-must 'gpu-make-texture (sdl-create-gpu-texture device (gpu-at p)))))

(define (gpu-make-sampler device)
  (let ([p gpu-sampler-info*])
    (gpu-zero! p (ftype-sizeof gpu-sampler-info))
    (ftype-set! gpu-sampler-info (address-u) p gpu-address-clamp)
    (ftype-set! gpu-sampler-info (address-v) p gpu-address-clamp)
    (ftype-set! gpu-sampler-info (address-w) p gpu-address-clamp)
    (gpu-must 'gpu-make-sampler (sdl-create-gpu-sampler device (gpu-at p)))))

;; The renderer of this kind, ready to draw; the GPU falls back to the CPU.
(define (gpu-open! kind)
  (let* ([device (or (gpu-open-device kind)
                     (and (eq? kind 'gpu) (gpu-open-device 'cpu))
                     (errorf 'gpu-open!
                             "no GPU device, and no renderer on the CPU to \
                              fall back on: ~a" (sdl-get-error)))])
    (let ([r (make-renderer
              kind device
              (gpu-make-sampler device)
              (gpu-make-texture device gpu-format-r8 gpu-usage-sampler
                                gpu-atlas-side gpu-atlas-side)
              (gpu-make-texture device gpu-format-bgra8 gpu-usage-sampler 1 1)
              '() (make-weak-eq-hashtable)
              (cons 0 0) (cons 0 0) (cons 0 0) (cons 0 0) 0 0 0 0 #f)])
      (set! *renderer* r)
      r)))

;; The host window this renderer draws to from now on.
(define (gpu-claim-window! window)
  (unless (sdl-claim-window (renderer-device *renderer*) window)
    (errorf 'gpu-claim-window! "~a" (sdl-get-error)))
  (set! *gpu-present-mode* 'vsync)   ; as a claim leaves it
  (set! *gpu-present-asked* 'vsync)
  (renderer-window-set! *renderer* window))

;; What frames draw to with no window: a texture w × h.
(define (gpu-set-target! w h)
  (let ([r *renderer*])
    (unless (and (= w (renderer-target-w r)) (= h (renderer-target-h r))
                 (not (eqv? 0 (renderer-target r))))
      (unless (eqv? 0 (renderer-target r))
        (sdl-release-gpu-texture (renderer-device r) (renderer-target r)))
      (renderer-target-set!
       r (gpu-make-texture (renderer-device r) gpu-format-bgra8
                           gpu-usage-target w h))
      (renderer-target-w-set! r w)
      (renderer-target-h-set! r h))))

;;; ------------------------------------------------------------------ shaders

(define (gpu-count-params shader kinds)
  (length (filter (lambda (p) (memq (cadr p) kinds)) (shader-params shader))))

(define gpu-entry-name
  (let* ([bytes (string->utf8 shader-entry)]
         [n (bytevector-length bytes)]
         [p (foreign-alloc (+ n 1))])
    (do ([i 0 (+ i 1)]) ((= i n))
      (foreign-set! 'unsigned-8 p i (bytevector-u8-ref bytes i)))
    (foreign-set! 'unsigned-8 p n 0)
    p))

(define (gpu-make-shader device shader)
  (let* ([bytes (shader-code shader)]
         [n (bytevector-length bytes)]
         [code (foreign-alloc n)]
         [p gpu-shader-info*])
    (gpu-copy-in code bytes n)
    (gpu-zero! p (ftype-sizeof gpu-shader-info))
    (ftype-set! gpu-shader-info (code-size) p n)
    (ftype-set! gpu-shader-info (code) p code)
    (ftype-set! gpu-shader-info (entry) p gpu-entry-name)
    (ftype-set! gpu-shader-info (format) p gpu-shader-format)
    (ftype-set! gpu-shader-info (stage) p
                (if (eq? (shader-stage shader) 'vertex) 0 1))
    (ftype-set! gpu-shader-info (samplers) p
                (gpu-count-params shader '(texture)))
    (ftype-set! gpu-shader-info (storage-buffers) p
                (gpu-count-params shader '(fx-buffer fl-buffer)))
    (ftype-set! gpu-shader-info (uniform-buffers) p
                (if (null? (shader-uniforms (shader-stage shader)
                                            (shader-params shader)))
                    0
                    1))
    (let ([s (gpu-must 'gpu-make-shader
                       (sdl-create-gpu-shader device (gpu-at p)))])
      (foreign-free code)
      s)))

;; Mode 0 covers what's there, premultiplied; mode 1 leaves source - what's
;; there; mode 2 turns what's there to its inverse by the source's amount,
;; so that a pattern's clear pixels leave it alone; mode 3 adds. Those three
;; leave alpha.
(define (gpu-make-pipeline device vs fs format mode)
  (let ([t gpu-target-description*] [p gpu-pipeline-info*])
    (define (blend! source target op source-a target-a)
      (ftype-set! gpu-target-description (source-color) t source)
      (ftype-set! gpu-target-description (target-color) t target)
      (ftype-set! gpu-target-description (color-op) t op)
      (ftype-set! gpu-target-description (source-alpha) t source-a)
      (ftype-set! gpu-target-description (target-alpha) t target-a)
      (ftype-set! gpu-target-description (alpha-op) t gpu-op-add))
    (gpu-zero! t (ftype-sizeof gpu-target-description))
    (gpu-zero! p (ftype-sizeof gpu-pipeline-info))
    (ftype-set! gpu-target-description (format) t format)
    (ftype-set! gpu-target-description (enable-blend) t 1)
    (case mode
      [(0) (blend! gpu-blend-one gpu-blend-one-minus-source-alpha gpu-op-add
                   gpu-blend-one gpu-blend-one-minus-source-alpha)]
      [(1) (blend! gpu-blend-one gpu-blend-one gpu-op-subtract
                   gpu-blend-zero gpu-blend-one)]
      [(2) (blend! gpu-blend-one-minus-target gpu-blend-one-minus-source
                   gpu-op-add gpu-blend-zero gpu-blend-one)]
      [else (blend! gpu-blend-one gpu-blend-one gpu-op-add
                    gpu-blend-zero gpu-blend-one)])
    (ftype-set! gpu-pipeline-info (vertex-shader) p vs)
    (ftype-set! gpu-pipeline-info (fragment-shader) p fs)
    (ftype-set! gpu-pipeline-info (rasterizer enable-depth-clip) p 1)
    (ftype-set! gpu-pipeline-info (target-info targets) p (gpu-at t))
    (ftype-set! gpu-pipeline-info (target-info count) p 1)
    (gpu-must 'gpu-make-pipeline
              (sdl-create-gpu-pipeline device (gpu-at p)))))

;; The pipelines drawing records to this format, made once.
(define (gpu-pipelines-for format)
  (let ([r *renderer*])
    (cond
      [(assv format (renderer-pipelines r)) => cdr]
      [else
       (let* ([d (renderer-device r)]
              [vs (gpu-make-shader d (top-level-value 'gfx-vertex))]
              [fs (gpu-make-shader d (top-level-value 'gfx-fragment))]
              [modes (vector (gpu-make-pipeline d vs fs format 0)
                             (gpu-make-pipeline d vs fs format 1)
                             (gpu-make-pipeline d vs fs format 2)
                             (gpu-make-pipeline d vs fs format 3))])
         (sdl-release-gpu-shader d vs)
         (sdl-release-gpu-shader d fs)
         (renderer-pipelines-set!
          r (cons (cons format modes) (renderer-pipelines r)))
         modes)])))

;; After a reload the shaders may be new.
(define (gpu-forget-pipelines!)
  (when *renderer*
    (for-each (lambda (p)
                (vector-for-each
                 (lambda (q)
                   (sdl-release-gpu-pipeline (renderer-device *renderer*) q))
                 (cdr p)))
              (renderer-pipelines *renderer*))
    (renderer-pipelines-set! *renderer* '())
    (vector-for-each
     (lambda (ps)
       (for-each (lambda (p)
                   (sdl-release-gpu-pipeline (renderer-device *renderer*)
                                             (cdr p)))
                 ps))
     (hashtable-values (renderer-paints *renderer*)))
    (hashtable-clear! (renderer-paints *renderer*))))

;; The pipeline that draws boxes with a paint's fragment shader, built when
;; first asked for.
(define (gpu-paint-pipeline shader format)
  (let* ([r *renderer*]
         [ps (hashtable-ref (renderer-paints r) shader '())])
    (cond
      [(assv format ps) => cdr]
      [else
       (let* ([d (renderer-device r)]
              [vs (gpu-make-shader d (top-level-value 'gfx-vertex))]
              [fs (gpu-make-shader d shader)]
              [p (gpu-make-pipeline d vs fs format 0)])
         (sdl-release-gpu-shader d vs)
         (sdl-release-gpu-shader d fs)
         (hashtable-set! (renderer-paints r) shader
                         (cons (cons format p) ps))
         p)])))

;;; ------------------------------------------------------------------ images
;;; An image is a texture of premultiplied BGRA, its pixels on the GPU alone.

(define-record-type gpu-image
  (nongenerative schevana-gpu-image-1)
  (fields texture w h (mutable pending)))

(define gpu-image-make
  (case-lambda
    [(w h) (gpu-image-make w h gpu-usage-sampler)]
    [(w h usage)
     (make-gpu-image
      (gpu-make-texture (renderer-device *renderer*) gpu-format-bgra8 usage w h)
      w h #f)]))

;; An image that can also be drawn on.
(define (gpu-image-make-target w h)
  (gpu-image-make w h (fxior gpu-usage-sampler gpu-usage-target)))

;; The pixels to go up with the next frame: 4·w·h bytes.
(define (gpu-image-write! image bytes)
  (gpu-image-pending-set! image bytes))

(define (gpu-image-release! image)
  (sdl-release-gpu-texture (renderer-device *renderer*)
                           (gpu-image-texture image)))

;;; ------------------------------------------------------------------ buffers
;;; A buffer a shader reads or writes: whole numbers or floats, 32 bits each.
;;; What's set here goes up with the next frame, or the next compute run; it
;;; costs a word's write, and the copy here only what's in the buffer.

(define-record-type (gpu-buffer make-gpu-buffer* gpu-buffer?)
  (nongenerative schevana-gpu-buffer-1)
  (fields id bytes
          (mutable from)     ; the bytes to go up: from .. to
          (mutable to)))

(defvar *gpu-dirty-buffers* '())

(define (make-gpu-buffer words)
  (let ([p gpu-buffer-info*] [n (* 4 words)])
    (gpu-zero! p (ftype-sizeof gpu-buffer-info))
    (ftype-set! gpu-buffer-info (usage) p
                (fxior gpu-usage-graphics-read gpu-usage-compute-read
                       gpu-usage-compute-write))
    (ftype-set! gpu-buffer-info (size) p n)
    (let ([b (make-gpu-buffer*
              (gpu-must 'make-gpu-buffer
                        (sdl-create-gpu-buffer (renderer-device *renderer*)
                                               (gpu-at p)))
              (make-immobile-bytevector n 0) 0 n)])
      (set! *gpu-dirty-buffers* (cons b *gpu-dirty-buffers*))
      b)))

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
  (sdl-release-gpu-buffer (renderer-device *renderer*) (gpu-buffer-id b)))

;; What a paint or a compute run is called with: its shader, its uniforms as
;; bytes, its buffers' ids.
(define-record-type gpu-call
  (nongenerative schevana-gpu-call-1)
  (fields shader uniforms buffers))

;; The arguments of the parameters that keep? takes.
(define (gpu-args-of keep? params args)
  (cond [(null? params) '()]
        [(keep? (car params))
         (cons (car args) (gpu-args-of keep? (cdr params) (cdr args)))]
        [else (gpu-args-of keep? (cdr params) (cdr args))]))

(define (gpu-buffer-param? p) (memq (cadr p) '(fx-buffer fl-buffer)))

;; A shader's arguments in its parameters' order, by their kinds, its
;; hidden uniforms first => a gpu-call
(define (gpu-make-call shader hidden params args)
  (let* ([values (append hidden
                         (gpu-args-of (lambda (p)
                                        (memq (cadr p) '(fixnum flonum)))
                                      params args))]
         [bytes (make-bytevector (max 4 (* 4 (length values))) 0)])
    (for-each (lambda (v i) (gpu-word-set! bytes (* 4 i) v))
              values (iota (length values)))
    (make-gpu-call shader bytes
                   (map gpu-buffer-id
                        (gpu-args-of gpu-buffer-param? params args)))))

;; The buffers' dirty bytes, by a copy pass on cb.
(define (gpu-upload-buffers! r cb)
  (let ([dirty *gpu-dirty-buffers*])
    (unless (null? dirty)
      (let* ([total (fold-left (lambda (n b)
                                 (+ n (- (gpu-buffer-to b)
                                         (gpu-buffer-from b))))
                               0 dirty)]
             [transfer (car (gpu-sized-transfer r total))]
             [mapped (gpu-must 'gpu-upload-buffers!
                               (sdl-map-gpu-transfer (renderer-device r)
                                                     transfer #t))]
             [at 0])
        (for-each (lambda (b)
                    (let ([n (- (gpu-buffer-to b) (gpu-buffer-from b))])
                      (sdl-memcpy (+ mapped at)
                                  (+ (object->reference-address
                                      (gpu-buffer-bytes b))
                                     (gpu-buffer-from b))
                                  n)
                      (set! at (+ at n))))
                  dirty)
        (sdl-unmap-gpu-transfer (renderer-device r) transfer)
        (let ([pass (sdl-begin-copy-pass cb)]
              [from gpu-transfer-location*]
              [to gpu-buffer-region*])
          (fold-left
           (lambda (off b)
             (let ([n (- (gpu-buffer-to b) (gpu-buffer-from b))])
               (ftype-set! gpu-transfer-location (transfer) from transfer)
               (ftype-set! gpu-transfer-location (offset) from off)
               (ftype-set! gpu-buffer-region (buffer) to (gpu-buffer-id b))
               (ftype-set! gpu-buffer-region (offset) to (gpu-buffer-from b))
               (ftype-set! gpu-buffer-region (size) to n)
               (sdl-upload-to-buffer pass (gpu-at from) (gpu-at to) #f)
               (gpu-buffer-from-set! b 0)
               (gpu-buffer-to-set! b 0)
               (+ off n)))
           0 dirty)
          (sdl-end-copy-pass pass)))
      (set! *gpu-dirty-buffers* '()))))

;;; ------------------------------------------------------------------ compute

(define (gpu-make-compute device shader)
  (let* ([bytes (shader-code shader)]
         [n (bytevector-length bytes)]
         [code (foreign-alloc n)]
         [p gpu-compute-info*]
         [buffers (filter (lambda (q) (memq (cadr q) '(fx-buffer fl-buffer)))
                          (shader-params shader))]
         [writes (length (filter (lambda (q) (pair? (cddr q))) buffers))])
    (gpu-copy-in code bytes n)
    (gpu-zero! p (ftype-sizeof gpu-compute-info))
    (ftype-set! gpu-compute-info (code-size) p n)
    (ftype-set! gpu-compute-info (code) p code)
    (ftype-set! gpu-compute-info (entry) p gpu-entry-name)
    (ftype-set! gpu-compute-info (format) p gpu-shader-format)
    (ftype-set! gpu-compute-info (read-buffers) p (- (length buffers) writes))
    (ftype-set! gpu-compute-info (write-buffers) p writes)
    (ftype-set! gpu-compute-info (uniform-buffers) p 1)
    (ftype-set! gpu-compute-info (group-x) p shader-group-x)
    (ftype-set! gpu-compute-info (group-y) p 1)
    (ftype-set! gpu-compute-info (group-z) p 1)
    (let ([c (gpu-must 'gpu-make-compute
                       (sdl-create-gpu-compute device (gpu-at p)))])
      (foreign-free code)
      c)))

;; Runs a compute shader over w × h cells, now, and waits for it: its buffers
;; are then ready to read with gpu-buffer-read!.
(define (gpu-compute! shader w h . args)
  (let* ([r *renderer*]
         [d (renderer-device r)]
         [params (shader-params shader)]
         [call (gpu-make-call shader (list w h) params args)]
         [writes (map gpu-buffer-id
                      (gpu-args-of (lambda (p)
                                     (and (gpu-buffer-param? p)
                                          (pair? (cddr p))))
                                   params args))]
         [reads (map gpu-buffer-id
                     (gpu-args-of (lambda (p)
                                    (and (gpu-buffer-param? p)
                                         (null? (cddr p))))
                                  params args))]
         [pipeline (gpu-make-compute d shader)]
         [cb (gpu-must 'gpu-compute! (sdl-acquire-gpu-commands d))]
         [bindings gpu-buffer-bindings*]
         [ids gpu-storage-buffers*])
    (gpu-upload-buffers! r cb)
    (gpu-zero! bindings (ftype-sizeof gpu-buffer-bindings))
    (for-each (lambda (id i)
                (ftype-set! gpu-buffer-bindings (i buffer) bindings id))
              writes (iota (length writes)))
    (let ([pass (sdl-begin-compute-pass cb 0 0 (gpu-at bindings)
                                        (length writes))])
      (sdl-bind-compute-pipeline pass pipeline)
      (for-each (lambda (id i) (ftype-set! gpu-storage-buffers (i) ids id))
                reads (iota (length reads)))
      (unless (null? reads)
        (sdl-bind-compute-storage pass 0 (gpu-at ids) (length reads)))
      (sdl-push-compute-uniform cb 0 (gpu-call-uniforms call)
                                (bytevector-length (gpu-call-uniforms call)))
      (sdl-dispatch-compute pass (quotient (+ w (- shader-group-x 1))
                                           shader-group-x)
                            h 1)
      (sdl-end-compute-pass pass))
    (gpu-wait! (gpu-must 'gpu-compute! (sdl-submit-gpu-fence cb)))
    (sdl-release-gpu-compute d pipeline)))

;; What a shader left in the buffer: read back into the copy here. => its
;; bytes
(define (gpu-buffer-read! b)
  (let* ([r *renderer*]
         [d (renderer-device r)]
         [n (bytevector-length (gpu-buffer-bytes b))]
         [transfer (gpu-make-transfer d 1 n)]
         [cb (gpu-must 'gpu-buffer-read! (sdl-acquire-gpu-commands d))]
         [pass (sdl-begin-copy-pass cb)]
         [from gpu-buffer-region*]
         [to gpu-transfer-location*])
    (ftype-set! gpu-buffer-region (buffer) from (gpu-buffer-id b))
    (ftype-set! gpu-buffer-region (offset) from 0)
    (ftype-set! gpu-buffer-region (size) from n)
    (ftype-set! gpu-transfer-location (transfer) to transfer)
    (ftype-set! gpu-transfer-location (offset) to 0)
    (sdl-download-from-buffer pass (gpu-at from) (gpu-at to))
    (sdl-end-copy-pass pass)
    (gpu-wait! (gpu-must 'gpu-buffer-read! (sdl-submit-gpu-fence cb)))
    (gpu-copy-out (gpu-buffer-bytes b)
                  (gpu-must 'gpu-buffer-read!
                            (sdl-map-gpu-transfer d transfer #f))
                  n)
    (sdl-unmap-gpu-transfer d transfer)
    (sdl-release-gpu-transfer d transfer)
    (gpu-buffer-bytes b)))

;;; ------------------------------------------------------------------ frames

;; A buffer at least n bytes big: a pair (buffer . capacity), the same one
;; while it fits.
(define (gpu-sized-buffer r pair n)
  (if (>= (cdr pair) n)
      pair
      (let ([cap (max 4096 (* 2 n))] [p gpu-buffer-info*])
        (unless (eqv? 0 (car pair))
          (sdl-release-gpu-buffer (renderer-device r) (car pair)))
        (gpu-zero! p (ftype-sizeof gpu-buffer-info))
        (ftype-set! gpu-buffer-info (usage) p gpu-usage-graphics-read)
        (ftype-set! gpu-buffer-info (size) p cap)
        (cons (gpu-must 'gpu-sized-buffer
                        (sdl-create-gpu-buffer (renderer-device r) (gpu-at p)))
              cap))))

(define (gpu-make-transfer device usage size)
  (let ([p gpu-transfer-info*])
    (gpu-zero! p (ftype-sizeof gpu-transfer-info))
    (ftype-set! gpu-transfer-info (usage) p usage)
    (ftype-set! gpu-transfer-info (size) p size)
    (gpu-must 'gpu-make-transfer (sdl-create-gpu-transfer device (gpu-at p)))))

(define (gpu-sized-transfer r n)
  (let ([pair (renderer-transfer r)])
    (if (>= (cdr pair) n)
        pair
        (let ([cap (max 65536 (* 2 n))])
          (unless (eqv? 0 (car pair))
            (sdl-release-gpu-transfer (renderer-device r) (car pair)))
          (let ([new (cons (gpu-make-transfer (renderer-device r) 0 cap) cap)])
            (renderer-transfer-set! r new)
            new)))))

;; Uploads what a frame needs, in a copy pass of cb: the records and extras,
;; the glyph table if it changed, new atlas pieces ((u v w h bytes) ...),
;; and images' new pixels. All through one transfer buffer, mapped once.
(define (gpu-upload! r cb recs recs-n extras extras-n table table-n
                     atlas-pieces images)
  (gpu-upload-buffers! r cb)
  (let* ([piece-n (lambda (p) (bytevector-length (car (cddddr p))))]
         [image-n (lambda (i) (bytevector-length (gpu-image-pending i)))]
         [total (+ recs-n extras-n (if table table-n 0)
                   (fold-left (lambda (n p) (+ n 3 (piece-n p))) 0 atlas-pieces)
                   (fold-left (lambda (n i) (+ n 3 (image-n i))) 0 images))]
         [transfer (car (gpu-sized-transfer r (max total 16)))]
         [mapped (gpu-must 'gpu-upload!
                           (sdl-map-gpu-transfer (renderer-device r) transfer
                                                 #t))]
         [at 0])
    ;; Each starts on a word: an image's pixels are words, whatever a piece
    ;; of the atlas before them left, and Metal shifts them otherwise.
    (define (put! bv n)
      (let ([off (logand (+ at 3) -4)])
        (gpu-copy-in (+ mapped off) bv n)
        (set! at (+ off n))
        off))
    (let* ([recs-at (put! recs recs-n)]
           [extras-at (put! extras extras-n)]
           [table-at (and table (put! table table-n))]
           [piece-ats (map (lambda (p) (put! (car (cddddr p)) (piece-n p)))
                           atlas-pieces)]
           [image-ats (map (lambda (i) (put! (gpu-image-pending i) (image-n i)))
                           images)])
      (sdl-unmap-gpu-transfer (renderer-device r) transfer)
      (let ([pass (sdl-begin-copy-pass cb)])
        (define (to-buffer! pair off n)
          (when (> n 0)
            (let ([from gpu-transfer-location*] [to gpu-buffer-region*])
              (ftype-set! gpu-transfer-location (transfer) from transfer)
              (ftype-set! gpu-transfer-location (offset) from off)
              (ftype-set! gpu-buffer-region (buffer) to (car pair))
              (ftype-set! gpu-buffer-region (offset) to 0)
              (ftype-set! gpu-buffer-region (size) to n)
              (sdl-upload-to-buffer pass (gpu-at from) (gpu-at to) #t))))
        (define (to-texture! texture off u v w h)
          (let ([from gpu-texture-transfer*] [to gpu-texture-region*])
            (gpu-zero! from (ftype-sizeof gpu-texture-transfer))
            (gpu-zero! to (ftype-sizeof gpu-texture-region))
            (ftype-set! gpu-texture-transfer (transfer) from transfer)
            (ftype-set! gpu-texture-transfer (offset) from off)
            (ftype-set! gpu-texture-transfer (pixels-per-row) from w)
            (ftype-set! gpu-texture-transfer (rows-per-layer) from h)
            (ftype-set! gpu-texture-region (texture) to texture)
            (ftype-set! gpu-texture-region (x) to u)
            (ftype-set! gpu-texture-region (y) to v)
            (ftype-set! gpu-texture-region (w) to w)
            (ftype-set! gpu-texture-region (h) to h)
            (ftype-set! gpu-texture-region (d) to 1)
            (sdl-upload-to-texture pass (gpu-at from) (gpu-at to) #f)))
        (let ([recs-b (gpu-sized-buffer r (renderer-records r) (max recs-n 32))]
              [extras-b (gpu-sized-buffer r (renderer-extras r)
                                          (max extras-n 32))]
              [table-b (gpu-sized-buffer r (renderer-glyphs r)
                                         (max table-n 32))])
          (renderer-records-set! r recs-b)
          (renderer-extras-set! r extras-b)
          (renderer-glyphs-set! r table-b)
          (to-buffer! recs-b recs-at recs-n)
          (to-buffer! extras-b extras-at extras-n)
          (when table-at (to-buffer! table-b table-at table-n)))
        (for-each
         (lambda (p off)
           (to-texture! (renderer-atlas r) off (car p) (cadr p) (caddr p)
                        (cadddr p)))
         atlas-pieces piece-ats)
        (for-each
         (lambda (i off)
           (to-texture! (gpu-image-texture i) off 0 0 (gpu-image-w i)
                        (gpu-image-h i))
           (gpu-image-pending-set! i #f))
         images image-ats)
        (sdl-end-copy-pass pass)))))

;; Draws the runs, ((mode image first count) ...), to target, w × h, cleared
;; to black, or to nothing if clear?.
(define (gpu-draw-runs! r cb target format w h runs clear?)
  (let ([pipelines (gpu-pipelines-for format)]
        [c gpu-color-target*]
        [buffers gpu-storage-buffers*]
        [samplers gpu-sampler-bindings*]
        [uniforms gpu-frame-uniforms*])
    (gpu-zero! c (ftype-sizeof gpu-color-target))
    (ftype-set! gpu-color-target (texture) c target)
    (ftype-set! gpu-color-target (a) c (if clear? 0.0 1.0))
    (ftype-set! gpu-color-target (load-op) c gpu-load-clear)
    (let ([pass (gpu-must 'gpu-draw-runs!
                          (sdl-begin-render-pass cb (gpu-at c) 1 0))])
      (ftype-set! gpu-storage-buffers (0) buffers (car (renderer-records r)))
      (ftype-set! gpu-storage-buffers (1) buffers (car (renderer-extras r)))
      (ftype-set! gpu-storage-buffers (2) buffers (car (renderer-glyphs r)))
      (ftype-set! gpu-frame-uniforms (w) uniforms (inexact w))
      (ftype-set! gpu-frame-uniforms (h) uniforms (inexact h))
      (ftype-set! gpu-sampler-bindings (0 texture) samplers (renderer-atlas r))
      (ftype-set! gpu-sampler-bindings (0 sampler) samplers
                  (renderer-sampler r))
      (ftype-set! gpu-sampler-bindings (1 sampler) samplers
                  (renderer-sampler r))
      (let loop ([runs runs] [mode #f])
        (unless (null? runs)
          (let* ([run (car runs)]
                 [run-mode (car run)]
                 [image (cadr run)]
                 [first (caddr run)]
                 [count (cadddr run)]
                 [call (and (gpu-call? image) image)])
            (when (> count 0)
              (ftype-set! gpu-frame-uniforms (first) uniforms first)
              (cond
                [call
                 (sdl-bind-gpu-pipeline
                  pass (gpu-paint-pipeline (gpu-call-shader call) format))
                 (sdl-bind-vertex-storage pass 0 (gpu-at buffers) 3)
                 ;; a paint's: the list's, then its own
                 (let ([own (gpu-call-buffers call)])
                   (for-each (lambda (id i)
                               (ftype-set! gpu-storage-buffers (i) buffers id))
                             own (map (lambda (i) (+ i 2))
                                      (iota (length own))))
                   (sdl-bind-fragment-storage pass 0 (gpu-at buffers)
                                              (+ 2 (length own))))
                 (ftype-set! gpu-storage-buffers (2) buffers
                             (car (renderer-glyphs r)))
                 (sdl-push-fragment-uniform
                  cb 0 (gpu-call-uniforms call)
                  (bytevector-length (gpu-call-uniforms call)))]
                [else
                 (unless (eqv? run-mode mode)
                   (sdl-bind-gpu-pipeline pass (vector-ref pipelines run-mode))
                   (sdl-bind-vertex-storage pass 0 (gpu-at buffers) 3)
                   (sdl-bind-fragment-storage pass 0 (gpu-at buffers) 3))
                 (ftype-set! gpu-sampler-bindings (1 texture) samplers
                             (if image
                                 (gpu-image-texture image)
                                 (renderer-blank r)))
                 (sdl-bind-fragment-samplers pass 0 (gpu-at samplers) 2)])
              (sdl-push-vertex-uniform cb 0 (gpu-at uniforms)
                                       (ftype-sizeof gpu-frame-uniforms))
              (sdl-draw-primitives pass 6 count 0 0))
            (loop (cdr runs)
                  (cond [call #f]
                        [(> count 0) run-mode]
                        [else mode])))))
      (sdl-end-render-pass pass))))

;; Where the GPU stood with the last frame, as main asked the window for its
;; next image: what tells the GPU's work from the screen's hold. 0, it had
;; finished already; 1, it finished during the wait; 2, it hadn't yet.
(defvar *gpu-frame-state* 0)

(define (gpu-last-frame-done? r)
  (let ([fence (renderer-fence r)])
    (or (not fence) (sdl-query-gpu-fence (renderer-device r) fence))))

;; The driver's name, and how this window may present.
(define (gpu-driver-name) (sdl-gpu-driver (renderer-device *renderer*)))

(define gpu-present-codes '((vsync . 0) (immediate . 1) (mailbox . 2)))
(define gpu-composition-sdr 0)   ; the one a claim gives: colors stay the same

(define (gpu-present-modes)
  (let ([r *renderer*])
    (if (eqv? 0 (renderer-window r))
        '()
        (map car
             (filter (lambda (m)
                       (sdl-window-supports-present-mode
                        (renderer-device r) (renderer-window r) (cdr m)))
                     gpu-present-codes)))))

;; How this window presents, and what it was last asked to.
(defvar *gpu-present-mode* 'vsync)
(defvar *gpu-present-asked* 'vsync)

;; Between frames, the window presents by mode from now on. A mode it doesn't
;; offer leaves it as it is, and is asked once a change: a choice saved on
;; another machine costs this one's frames nothing.
(define (gpu-present-mode! mode)
  (unless (eq? mode *gpu-present-asked*)
    (set! *gpu-present-asked* mode)
    (let ([r *renderer*])
      (when (and (memq mode (gpu-present-modes))
                 (sdl-set-swapchain-parameters
                  (renderer-device r) (renderer-window r) gpu-composition-sdr
                  (cdr (assq mode gpu-present-codes))))
        (set! *gpu-present-mode* mode)))))

;; One frame: uploads, then the runs, to the window or the target. => #t if
;; it reached the screen; #f if the window had no room for it yet (a frame
;; still in flight, or it is hidden), and it should be tried again. preview,
;; if not #f, (image . runs): those runs are drawn on image first.
(define (gpu-frame! recs recs-n extras extras-n table table-n atlas-pieces
                    images runs preview)
  (let* ([r *renderer*]
         [cb (gpu-must 'gpu-frame!
                       (sdl-acquire-gpu-commands (renderer-device r)))])
    (gpu-upload! r cb recs recs-n extras extras-n table table-n atlas-pieces
                 images)
    (when preview
      (gpu-draw-runs! r cb (gpu-image-texture (car preview)) gpu-format-bgra8
                      (gpu-image-w (car preview)) (gpu-image-h (car preview))
                      (cdr preview) #f))
    (if (eqv? 0 (renderer-window r))
        (begin
          (gpu-draw-runs! r cb (renderer-target r) gpu-format-bgra8
                          (renderer-target-w r) (renderer-target-h r) runs #f)
          ;; no screen paces these, and frames sent faster than they're drawn
          ;; would pile up without end: one waits behind the one being drawn
          (let ([fence (gpu-must 'gpu-frame! (sdl-submit-gpu-fence cb))])
            (when (renderer-fence r) (gpu-wait! (renderer-fence r)))
            (renderer-fence-set! r fence))
          #t)
        ;; the driver may hold either end of this till the screen is ready
        (let* ([out gpu-swapchain-out*]
               [done? (gpu-last-frame-done? r)]
               [shown?
                (and (host-screen-wait
                      'acquire
                      (lambda ()
                        (sdl-acquire-swapchain
                         cb (renderer-window r)
                         (ftype-pointer-address
                          (ftype-&ref gpu-swapchain-out (texture) out))
                         (ftype-pointer-address
                          (ftype-&ref gpu-swapchain-out (w) out))
                         (ftype-pointer-address
                          (ftype-&ref gpu-swapchain-out (h) out)))))
                     (not (eqv? 0 (ftype-ref gpu-swapchain-out (texture)
                                             out))))])
          (set! *gpu-frame-state*
            (cond [done? 0] [(gpu-last-frame-done? r) 1] [else 2]))
          (when shown?
            (gpu-draw-runs! r cb (ftype-ref gpu-swapchain-out (texture) out)
                            (sdl-swapchain-format (renderer-device r)
                                                  (renderer-window r))
                            (ftype-ref gpu-swapchain-out (w) out)
                            (ftype-ref gpu-swapchain-out (h) out)
                            runs #f))
          (let ([fence (gpu-must
                        'gpu-frame!
                        (host-screen-wait
                         'submit (lambda () (sdl-submit-gpu-fence cb))))])
            (when (renderer-fence r)
              (sdl-release-gpu-fence (renderer-device r) (renderer-fence r)))
            (renderer-fence-set! r fence))
          shown?))))

;; The same, drawn to a new texture w × h and read back: its pixels, row
;; after row, premultiplied BGRA. What tests, screenshots and icons see.
(define (gpu-drawing->bytes recs recs-n extras extras-n table table-n
                           atlas-pieces images runs w h clear?)
  (let* ([r *renderer*]
         [d (renderer-device r)]
         [texture (gpu-make-texture d gpu-format-bgra8 gpu-usage-target w h)]
         [cb (gpu-must 'gpu-drawing->bytes (sdl-acquire-gpu-commands d))])
    (gpu-upload! r cb recs recs-n extras extras-n table table-n atlas-pieces
                 images)
    (gpu-draw-runs! r cb texture gpu-format-bgra8 w h runs clear?)
    (let ([bytes (gpu-read-texture! r cb texture w h)])
      (sdl-release-gpu-texture d texture)
      bytes)))

;; Submits cb with texture's pixels on their way down, and waits for them.
(define (gpu-read-texture! r cb texture w h)
  (let* ([d (renderer-device r)]
         [n (* 4 w h)]
         [transfer (gpu-make-transfer d 1 n)]
         [pass (sdl-begin-copy-pass cb)]
         [bytes (make-immobile-bytevector n)]
         [from gpu-texture-region*]
         [to gpu-texture-transfer*])
    (gpu-zero! from (ftype-sizeof gpu-texture-region))
    (gpu-zero! to (ftype-sizeof gpu-texture-transfer))
    (ftype-set! gpu-texture-region (texture) from texture)
    (ftype-set! gpu-texture-region (w) from w)
    (ftype-set! gpu-texture-region (h) from h)
    (ftype-set! gpu-texture-region (d) from 1)
    (ftype-set! gpu-texture-transfer (transfer) to transfer)
    (ftype-set! gpu-texture-transfer (pixels-per-row) to w)
    (ftype-set! gpu-texture-transfer (rows-per-layer) to h)
    (sdl-download-from-texture pass (gpu-at from) (gpu-at to))
    (sdl-end-copy-pass pass)
    (gpu-wait! (gpu-must 'gpu-read-texture! (sdl-submit-gpu-fence cb)))
    (gpu-copy-out bytes (gpu-must 'gpu-read-texture!
                                  (sdl-map-gpu-transfer d transfer #f))
                  n)
    (sdl-unmap-gpu-transfer d transfer)
    (sdl-release-gpu-transfer d transfer)
    bytes))

(define (gpu-wait! fence)
  (let ([d (renderer-device *renderer*)] [list gpu-fence-list*])
    (ftype-set! gpu-fence-list (0) list fence)
    (sdl-wait-gpu-fences d #t (gpu-at list) 1)
    (sdl-release-gpu-fence d fence)))
