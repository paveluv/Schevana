;;; host/gpu.ss — the GPU layer's device side, in core0 below the core
;;; (.work/gpu-design.md 9.5): the device, pipelines, images, buffers and
;;; lists on the GPU, uploads, the pass, the swapchain, presenting a frame
;;; main publishes. Only core0 names SDL; this file alone knows one driver
;;; from another, so that another back end stays a swap. It names nothing
;;; of the core above it but what tests/sources.ss lists, on its way out.
;;;
;;; Everything that touches a device hangs off one record, a renderer, so
;;; that one can be rebuilt on another device. SDL handles what the GPU still
;;; holds: buffers uploaded and transfer buffers mapped with cycling on are
;;; ring buffers, and no fence bookkeeping is needed for them.

;;; ------------------------------------------------------------------ shaders
;;; What a compiled shader is, the compiler's (src/shader.ss) and the
;;; device's contract, and which back end this machine speaks.

;; This machine's back end: a Mac has Metal, everything else Vulkan.
(define shader-target (if host-mac? 'msl 'spirv))

;; What a shader's entry is called: main is no function's name in MSL.
(define shader-entry (if (eq? shader-target 'msl) "main0" "main"))

;; A compute shader's group, across: a dispatch counts in these.
(define shader-group-x 64)

(define-record-type shader
  (nongenerative schevana-shader-1)
  (fields name stage coords params source code price))

;; The uniforms a stage's block holds, hidden ones first: ((name type) ...).
;; After the parameters, each buffer's length in words, in their order: no
;; GPU API but Vulkan tells a shader how long its buffers are.
(define (shader-uniforms stage params)
  (append (if (eq? stage 'compute)
              '((shader-w fixnum) (shader-h fixnum))
              '())
          (filter (lambda (p) (memq (cadr p) '(fixnum flonum))) params)
          (map (lambda (p) (list (shader-words (car p)) 'fixnum))
               (filter (lambda (p) (memq (cadr p) '(fx-buffer fl-buffer)))
                       params))))

;; The uniform holding buffer name's length: a name no parameter can have.
(define (shader-words name) (string->symbol (format "~a words" name)))

(define-record-type renderer
  (nongenerative schevana-renderer-1)
  (fields kind device sampler atlas blank
          (mutable pipelines)      ; (format . vector of pipelines by mode)
          (mutable paints)         ; shader: ((format . pipeline) ...)
          (mutable records)        ; each (buffer . capacity)
          (mutable extras)
          (mutable glyphs)
          (mutable transfer)       ; (transfer buffer . capacity)
          (mutable sdl-window)     ; the host window it draws to, or 0
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
;; The vertex shader's uniforms; the fragment shader's are the last five,
;; where the list is on the target and its buffers' lengths in words, which
;; go as bytes (gpu-list-words).
(gpu-struct gpu-frame-uniforms gpu-frame-uniforms* 1040
  (struct [w float] [h float] [first int] [ox int] [oy int]
          [records int] [extras int] [glyphs int]))
(define gpu-list-words (make-bytevector 20 0))
(gpu-struct gpu-scissor gpu-scissor* 1072
  (struct [x int] [y int] [w int] [h int]))
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

(define gpu-make-texture
  (case-lambda
    [(device format usage w h) (gpu-make-texture device format usage w h 1)]
    [(device format usage w h levels)
     (let ([p gpu-texture-info*])
       (gpu-zero! p (ftype-sizeof gpu-texture-info))
       (ftype-set! gpu-texture-info (format) p format)
       (ftype-set! gpu-texture-info (usage) p usage)
       (ftype-set! gpu-texture-info (width) p w)
       (ftype-set! gpu-texture-info (height) p h)
       (ftype-set! gpu-texture-info (layers) p 1)
       (ftype-set! gpu-texture-info (levels) p levels)
       (gpu-must 'gpu-make-texture
                 (sdl-create-gpu-texture device (gpu-at p))))]))

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
      (gpu-facts-refresh!)
      r)))

;; The host window this renderer draws to from now on.
(define (gpu-claim-window! sdl-window)
  (unless (sdl-claim-window (renderer-device *renderer*) sdl-window)
    (errorf 'gpu-claim-window! "~a" (sdl-get-error)))
  (set! *gpu-present-mode* 'vsync)   ; as a claim leaves it
  (set! *gpu-present-asked* 'vsync)
  (renderer-sdl-window-set! *renderer* sdl-window)
  (gpu-facts-refresh!))

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
  (let loop ([ps (shader-params shader)] [n 0])
    (if (null? ps)
        n
        (loop (cdr ps) (if (memq (cadar ps) kinds) (+ n 1) n)))))

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

;; The core's shaders, which records are drawn with, as main hands them
;; over (src/gfx.ss): (vertex . fragments), a vector of the fragment
;; shader's variants.
(defvar *gpu-shaders* #f)

;; The pipelines drawing records to this format, made once: four by mode for
;; each variant of the fragment shader, in their order. All of them, so that
;; a run that's the first to need one doesn't wait for it.
(define (gpu-pipelines-for format)
  (let ([r *renderer*])
    (cond
      [(assv format (renderer-pipelines r)) => cdr]
      [else
       (let* ([d (renderer-device r)]
              [vs (gpu-make-shader d (car *gpu-shaders*))]
              [all (apply vector
                          (apply append
                                 (map (lambda (fragment)
                                        (gpu-pipelines-of d vs fragment format))
                                      (vector->list (cdr *gpu-shaders*)))))])
         (sdl-release-gpu-shader d vs)
         (renderer-pipelines-set!
          r (cons (cons format all) (renderer-pipelines r)))
         all)])))

;; The four pipelines of a fragment shader, by mode.
(define (gpu-pipelines-of d vs fragment format)
  (let* ([fs (gpu-make-shader d fragment)]
         [ps (map (lambda (mode) (gpu-make-pipeline d vs fs format mode))
                  '(0 1 2 3))])
    (sdl-release-gpu-shader d fs)
    ps))

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
                   ((if (eq? (car p) 'compute)
                        sdl-release-gpu-compute
                        sdl-release-gpu-pipeline)
                    (renderer-device *renderer*) (cdr p)))
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
              [vs (gpu-make-shader d (car *gpu-shaders*))]
              [fs (gpu-make-shader d shader)]
              [p (gpu-make-pipeline d vs fs format 0)])
         (sdl-release-gpu-shader d vs)
         (sdl-release-gpu-shader d fs)
         (hashtable-set! (renderer-paints r) shader
                         (cons (cons format p) ps))
         p)])))

;;; ------------------------------------------------------------------ objects
;;; The SDL objects behind main's handles, by id, (kind . object): made and
;;; let go of by the jobs main asks, which core0 runs before anything that
;;; needs them (.work/gpu-design.md 9.12).

(defvar *gpu-objects* (make-eqv-hashtable))

;; The SDL object behind handle id.
(define (gpu-object id)
  (let ([o (hashtable-ref *gpu-objects* id #f)])
    (unless o (errorf 'gpu-object "~a has no object: its job hasn't run" id))
    (cdr o)))

;; Main's jobs, in order: (texture id w h usage levels), (buffer id bytes),
;; (atlas id), the glyphs' atlas under id, (shaders vertex fragments), the
;; core's, (target w h), the size frames draw to with no window, (release
;; id), and (read then recs recs-n extras extras-n table table-n pieces
;; images runs w h clear?), a drawing read back, its pixels left with then
;; in *gpu-answers*.
(defvar *gpu-answers* '())

;; What core0 read back for main since main last took it, (then . bytes)
;; each, in order: main hands each to its then.
(define (gpu-take-answers!)
  (let ([answers (reverse *gpu-answers*)])
    (set! *gpu-answers* '())
    answers))

(define (gpu-run-jobs! jobs)
  (for-each
   (lambda (job)
     (let ([d (renderer-device *renderer*)])
       (case (car job)
         [(texture)
          (let-values ([(id w h usage levels) (apply values (cdr job))])
            (hashtable-set! *gpu-objects* id
                            (cons 'texture
                                  (gpu-make-texture d gpu-format-bgra8 usage
                                                    w h levels))))]
         [(buffer)
          (let ([p gpu-buffer-info*])
            (gpu-zero! p (ftype-sizeof gpu-buffer-info))
            (ftype-set! gpu-buffer-info (usage) p
                        (fxior gpu-usage-graphics-read gpu-usage-compute-read
                               gpu-usage-compute-write))
            (ftype-set! gpu-buffer-info (size) p (caddr job))
            (hashtable-set! *gpu-objects* (cadr job)
                            (cons 'buffer
                                  (gpu-must 'gpu-run-jobs!
                                            (sdl-create-gpu-buffer
                                             d (gpu-at p))))))]
         [(atlas)
          (hashtable-set! *gpu-objects* (cadr job)
                          (cons 'atlas (renderer-atlas *renderer*)))]
         [(shaders)
          (set! *gpu-shaders* (cons (cadr job) (caddr job)))
          (gpu-forget-pipelines!)]
         [(target) (gpu-set-target! (cadr job) (caddr job))]
         [(read)
          (set! *gpu-answers*
            (cons (cons (cadr job)
                        (apply gpu-drawing->bytes '() '() '() (cddr job)))
                  *gpu-answers*))]
         [(release)
          (gpu-list-free! (cadr job))
          (let ([o (hashtable-ref *gpu-objects* (cadr job) #f)])
            (hashtable-delete! *gpu-objects* (cadr job))
            (when o
              (case (car o)
                [(texture) (sdl-release-gpu-texture d (cdr o))]
                [(buffer) (sdl-release-gpu-buffer d (cdr o))])))])))
   jobs))

;;; ------------------------------------------------------------------ images
;;; An image is a texture of premultiplied BGRA, its pixels on the GPU alone.

;; Main's handle on one: its id in *gpu-objects*, its size and levels, the
;; pixels to go up next, and gone?, let go of, so that a list kept from
;; before that names it draws without it.
(define-record-type gpu-image
  (nongenerative schevana-gpu-image-2)
  (fields id w h levels (mutable pending) (mutable gone?)))

(define (gpu-image-texture image) (gpu-object (gpu-image-id image)))

;; What's just been drawn on image goes down its chain.
(define (gpu-image-fill-levels! cb image)
  (when (> (gpu-image-levels image) 1)
    (sdl-generate-gpu-mipmaps cb (gpu-image-texture image))))

;;; ------------------------------------------------------------------ buffers
;;; A buffer a shader reads or writes: whole numbers or floats, 32 bits each.
;;; What's set here goes up with the next frame, or the next compute run; it
;;; costs a word's write, and the copy here only what's in the buffer.

;; Main's handle on one: its id in *gpu-objects*, and its words here.
(define-record-type (gpu-buffer make-gpu-buffer* gpu-buffer?)
  (nongenerative schevana-gpu-buffer-2)
  (fields id bytes
          (mutable from)     ; the bytes to go up: from .. to
          (mutable to)
          (mutable gone?)))  ; let go of, as an image can be

;; What a paint or a compute run is called with: its shader, its uniforms as
;; bytes, its buffers.
(define-record-type gpu-call
  (nongenerative schevana-gpu-call-1)
  (fields shader uniforms buffers))

;; What a recording left, "/recorder"'s (src/recorder/bytes.ss), the only
;; code that writes one: its records and extras, as bytes, and how many of
;; them; its runs; its version, its list's count of recordings. Frozen once
;; recorded, it's what core0 reads, whole: a list or a frame swaps to a
;; newer one by one store. until and next are the recorder's own: when it
;; may be written again, and its list's other recordings.
(define-record-type gpu-recording
  (nongenerative schevana-gpu-recording-1)
  (fields (mutable recs) (mutable recs-n) (mutable extras) (mutable extras-n)
          (mutable runs) (mutable version) (mutable until) (mutable next)))

;; A list kept to be shown by another: its recording, and the labels the
;; recorder gave it; when it was last recorded (now-ns) and in how many ns,
;; for kits/inspect.ss. Its id, a handle's, names its GPU buffers in
;; *gpu-lists*; #f for a copy that's never shown (kits/inspect.ss).
(define-record-type gpu-list
  (nongenerative schevana-gpu-list-3)
  (fields id (mutable recording) (mutable labels) (mutable recorded)
          (mutable took)))

;; What core0 keeps of each list shown, by id: #(records extras version
;; recs-at extras-at seen seen-in), its GPU buffers (buffer . size) each,
;; the version that went up, where its records and extras wait in the
;; transfer while they go, or #f, and the recording this pass reads.
;; A list goes up when it has a newer version.
(defvar *gpu-lists* (make-eqv-hashtable))

(define (gpu-list-state l)
  (let ([id (or (gpu-list-id l)
                (errorf 'gpu-list-state "a copy of a list is never shown"))])
    (or (hashtable-ref *gpu-lists* id #f)
        (let ([state (vector (cons 0 0) (cons 0 0) 0 #f #f #f -1)])
          (hashtable-set! *gpu-lists* id state)
          state))))

;; Each upload and the drawing after it is a pass, which reads each list's
;; recording once, the first time it meets it: a list recorded again while
;; core0 reads it shows the same recording in every step of the pass.
(defvar *gpu-pass* 0)

(define (gpu-list-seen l)
  (let ([state (gpu-list-state l)])
    (unless (fx= (vector-ref state 6) *gpu-pass*)
      (vector-set! state 5 (gpu-list-recording l))
      (vector-set! state 6 *gpu-pass*))
    (vector-ref state 5)))

(define (gpu-list-fresh? l)
  (not (fx= (vector-ref (gpu-list-state l) 2)
            (gpu-recording-version (gpu-list-seen l)))))

;; Its GPU buffers let go of, by main's release job: shown again, it goes
;; up again.
(define (gpu-list-free! id)
  (let ([state (hashtable-ref *gpu-lists* id #f)])
    (when state
      (hashtable-delete! *gpu-lists* id)
      (for-each (lambda (pair)
                  (unless (eqv? 0 (car pair))
                    (sdl-release-gpu-buffer (renderer-device *renderer*)
                                            (car pair))))
                (list (vector-ref state 0) (vector-ref state 1))))))

;; A run that shows a list: (show list ox oy x0 y0 x1 y1 labels), at (ox,
;; oy) in device pixels from its own list's origin, inside the clip x0 y0
;; x1 y1 there, x0 #f for none; labels, the recorder's, before it.
(define (gpu-show-run? run) (eq? (car run) 'show))

;; What the lists runs show, and those they show, that changed since they
;; went up take in the transfer, after n: a list shown twice counts twice.
(define (gpu-fresh-bytes runs n)
  (cond
    [(null? runs) n]
    [(gpu-show-run? (car runs))
     (let ([rec (gpu-list-seen (cadar runs))])
       (gpu-fresh-bytes (cdr runs)
                        (gpu-fresh-bytes (gpu-recording-runs rec)
                                         (if (gpu-list-fresh? (cadar runs))
                                             (+ n 8 (gpu-recording-recs-n rec)
                                                (gpu-recording-extras-n rec))
                                             n))))]
    [else (gpu-fresh-bytes (cdr runs) n)]))

;; Does a run, (mode image first count variant), show an image or a paint's
;; buffer let go of since it was drawn? A list kept draws without it.
(define (gpu-run-gone? run)
  (let ([x (cadr run)])
    (cond [(gpu-image? x) (gpu-image-gone? x)]
          [(gpu-call? x) (exists gpu-buffer-gone? (gpu-call-buffers x))]
          [else #f])))

;; The dirty buffers' bytes, by a copy pass on cb.
(define (gpu-upload-buffers! r cb dirty)
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
             (ftype-set! gpu-buffer-region (buffer) to
                          (gpu-object (gpu-buffer-id b)))
             (ftype-set! gpu-buffer-region (offset) to (gpu-buffer-from b))
             (ftype-set! gpu-buffer-region (size) to n)
             (sdl-upload-to-buffer pass (gpu-at from) (gpu-at to) #f)
             (gpu-buffer-from-set! b 0)
             (gpu-buffer-to-set! b 0)
             (+ off n)))
         0 dirty)
        (sdl-end-copy-pass pass)))))

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

;; The pipeline that runs a compute shader, built when first asked for and
;; kept with the paints'.
(define (gpu-compute-pipeline shader)
  (let* ([r *renderer*]
         [ps (hashtable-ref (renderer-paints r) shader '())])
    (cond
      [(assq 'compute ps) => cdr]
      [else
       (let ([p (gpu-make-compute (renderer-device r) shader)])
         (hashtable-set! (renderer-paints r) shader (cons (cons 'compute p) ps))
         p)])))

;; A compute run on cb, in a pass of its own.
(define (gpu-dispatch! cb run)
  (apply
   (lambda (call w h writes reads)
     (let ([bindings gpu-buffer-bindings*] [ids gpu-storage-buffers*])
       (gpu-zero! bindings (ftype-sizeof gpu-buffer-bindings))
       (for-each (lambda (id i)
                   (ftype-set! gpu-buffer-bindings (i buffer) bindings
                               (gpu-object id)))
                 writes (iota (length writes)))
       (let ([pass (sdl-begin-compute-pass cb 0 0 (gpu-at bindings)
                                           (length writes))])
         (sdl-bind-compute-pipeline
          pass (gpu-compute-pipeline (gpu-call-shader call)))
         (for-each (lambda (id i)
                     (ftype-set! gpu-storage-buffers (i) ids (gpu-object id)))
                   reads (iota (length reads)))
         (unless (null? reads)
           (sdl-bind-compute-storage pass 0 (gpu-at ids) (length reads)))
         (sdl-push-compute-uniform cb 0 (gpu-call-uniforms call)
                                   (bytevector-length (gpu-call-uniforms call)))
         (sdl-dispatch-compute pass (quotient (+ w (- shader-group-x 1))
                                              shader-group-x)
                               h 1)
         (sdl-end-compute-pass pass))))
   run))

;; run, now, main's jobs run and the dirty buffers going up first, and a
;; wait for it.
(define (gpu-compute-now! run jobs dirty)
  (gpu-run-jobs! jobs)
  (let* ([r *renderer*]
         [cb (gpu-must 'gpu-compute-now!
                       (sdl-acquire-gpu-commands (renderer-device r)))])
    (gpu-upload-buffers! r cb dirty)
    (gpu-dispatch! cb run)
    (gpu-wait! (gpu-must 'gpu-compute-now! (sdl-submit-gpu-fence cb)))))

;; runs, in order, on cb: after its uploads, before its draws.
(define (gpu-run-computes! cb runs)
  (for-each (lambda (run) (gpu-dispatch! cb run)) runs))

;; runs that no frame took, main's jobs run and the dirty buffers going up
;; first, sent with no frame and waited for by nobody. The queue keeps the
;; order: what a frame sent after them reads finds them done.
(define (gpu-submit-computes! runs jobs dirty)
  (gpu-run-jobs! jobs)
  (let* ([r *renderer*]
         [cb (gpu-must 'gpu-submit-computes!
                       (sdl-acquire-gpu-commands (renderer-device r)))])
    (gpu-upload-buffers! r cb dirty)
    (gpu-run-computes! cb runs)
    (sdl-submit-gpu cb)))

;; What a shader left in the buffer: read back into the copy here, main's
;; jobs run first. => its bytes
(define (gpu-buffer-download! jobs b)
  (gpu-run-jobs! jobs)
  (let* ([r *renderer*]
         [d (renderer-device r)]
         [n (bytevector-length (gpu-buffer-bytes b))]
         [transfer (gpu-make-transfer d 1 n)]
         [cb (gpu-must 'gpu-buffer-download! (sdl-acquire-gpu-commands d))]
         [pass (sdl-begin-copy-pass cb)]
         [from gpu-buffer-region*]
         [to gpu-transfer-location*])
    (ftype-set! gpu-buffer-region (buffer) from
                (gpu-object (gpu-buffer-id b)))
    (ftype-set! gpu-buffer-region (offset) from 0)
    (ftype-set! gpu-buffer-region (size) from n)
    (ftype-set! gpu-transfer-location (transfer) to transfer)
    (ftype-set! gpu-transfer-location (offset) to 0)
    (sdl-download-from-buffer pass (gpu-at from) (gpu-at to))
    (sdl-end-copy-pass pass)
    (gpu-wait! (gpu-must 'gpu-buffer-download! (sdl-submit-gpu-fence cb)))
    (gpu-copy-out (gpu-buffer-bytes b)
                  (gpu-must 'gpu-buffer-download!
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
;; images' new pixels, and the lists the runs show that changed. All through
;; one transfer buffer, mapped once. A frame with none of those allocates
;; nothing.
(define (gpu-upload! r cb dirty recs recs-n extras extras-n table table-n
                     atlas-pieces images runs)
  (gpu-upload-buffers! r cb dirty)
  (set! *gpu-pass* (fx+ *gpu-pass* 1))
  (let* ([total (+ recs-n extras-n (if table table-n 0) 8
                   (gpu-fresh-bytes runs 0)
                   (gpu-each-bytes atlas-pieces gpu-piece-bytes 0)
                   (gpu-each-bytes images gpu-image-pending 0))]
         [transfer (car (gpu-sized-transfer r (max total 16)))]
         [mapped (gpu-must 'gpu-upload!
                           (sdl-map-gpu-transfer (renderer-device r) transfer
                                                 #t))])
    (set! gpu-put-at 0)
    (let* ([recs-at (gpu-put! mapped recs recs-n)]
           [extras-at (gpu-put! mapped extras extras-n)]
           [table-at (and table (gpu-put! mapped table table-n))]
           [piece-ats (gpu-put-each! mapped atlas-pieces gpu-piece-bytes)]
           [image-ats (gpu-put-each! mapped images gpu-image-pending)])
      (gpu-put-lists! mapped runs)
      (sdl-unmap-gpu-transfer (renderer-device r) transfer)
      (let ([pass (sdl-begin-copy-pass cb)]
            [recs-b (gpu-sized-buffer r (renderer-records r) (max recs-n 32))]
            [extras-b (gpu-sized-buffer r (renderer-extras r)
                                        (max extras-n 32))]
            [table-b (gpu-sized-buffer r (renderer-glyphs r)
                                       (max table-n 32))])
        (renderer-records-set! r recs-b)
        (renderer-extras-set! r extras-b)
        (renderer-glyphs-set! r table-b)
        (gpu-to-buffer! pass transfer recs-b recs-at recs-n)
        (gpu-to-buffer! pass transfer extras-b extras-at extras-n)
        (when table-at (gpu-to-buffer! pass transfer table-b table-at table-n))
        (gpu-send-lists! r pass transfer runs)
        (gpu-send-pieces! r pass transfer atlas-pieces piece-ats)
        (gpu-send-images! pass transfer images image-ats)
        (sdl-end-copy-pass pass)))))

;; Where the next bytes go in the transfer being filled.
(define gpu-put-at 0)

;; n of bv's bytes into the mapped transfer, each on a word: an image's
;; pixels are words, whatever a piece of the atlas before them left, and
;; Metal shifts them otherwise. => where they went
(define (gpu-put! mapped bv n)
  (let ([off (logand (+ gpu-put-at 3) -4)])
    (gpu-copy-in (+ mapped off) bv n)
    (set! gpu-put-at (+ off n))
    off))

(define (gpu-piece-bytes p) (car (cddddr p)))

;; The bytes of each of xs, bytes-of's of it, after n, each a word at most
;; more for where it starts.
(define (gpu-each-bytes xs bytes-of n)
  (if (null? xs)
      n
      (gpu-each-bytes (cdr xs) bytes-of
                      (+ n 3 (bytevector-length (bytes-of (car xs)))))))

;; Each of xs's bytes into the transfer: => where each went.
(define (gpu-put-each! mapped xs bytes-of)
  (if (null? xs)
      '()
      (let ([bv (bytes-of (car xs))])
        (let ([off (gpu-put! mapped bv (bytevector-length bv))])
          (cons off (gpu-put-each! mapped (cdr xs) bytes-of))))))

;; The lists runs show that changed into the transfer, each once.
(define (gpu-put-lists! mapped runs)
  (unless (null? runs)
    (when (gpu-show-run? (car runs))
      (let* ([l (cadar runs)] [state (gpu-list-state l)]
             [rec (gpu-list-seen l)])
        (when (and (gpu-list-fresh? l) (not (vector-ref state 3)))
          (vector-set! state 3
                       (gpu-put! mapped (gpu-recording-recs rec)
                                 (gpu-recording-recs-n rec)))
          (vector-set! state 4
                       (gpu-put! mapped (gpu-recording-extras rec)
                                 (gpu-recording-extras-n rec))))
        (gpu-put-lists! mapped (gpu-recording-runs rec))))
    (gpu-put-lists! mapped (cdr runs))))

;; Those lists from the transfer into their own buffers, in pass.
(define (gpu-send-lists! r pass transfer runs)
  (unless (null? runs)
    (when (gpu-show-run? (car runs))
      (let* ([l (cadar runs)] [state (gpu-list-state l)]
             [rec (gpu-list-seen l)] [rn (gpu-recording-recs-n rec)]
             [en (gpu-recording-extras-n rec)])
        (when (vector-ref state 3)
          (let ([recs-b (gpu-sized-buffer r (vector-ref state 0) (max rn 32))]
                [extras-b (gpu-sized-buffer r (vector-ref state 1)
                                            (max en 32))])
            (vector-set! state 0 recs-b)
            (vector-set! state 1 extras-b)
            (gpu-to-buffer! pass transfer recs-b (vector-ref state 3) rn)
            (gpu-to-buffer! pass transfer extras-b (vector-ref state 4) en)
            (vector-set! state 2 (gpu-recording-version rec))
            (vector-set! state 3 #f)
            (vector-set! state 4 #f)))
        (gpu-send-lists! r pass transfer (gpu-recording-runs rec))))
    (gpu-send-lists! r pass transfer (cdr runs))))

(define (gpu-send-pieces! r pass transfer pieces offs)
  (unless (null? pieces)
    (let ([p (car pieces)])
      (gpu-to-texture! pass transfer (renderer-atlas r) (car offs)
                       (car p) (cadr p) (caddr p) (cadddr p)))
    (gpu-send-pieces! r pass transfer (cdr pieces) (cdr offs))))

(define (gpu-send-images! pass transfer images offs)
  (unless (null? images)
    (let ([i (car images)])
      (gpu-to-texture! pass transfer (gpu-image-texture i) (car offs) 0 0
                       (gpu-image-w i) (gpu-image-h i))
      (gpu-image-pending-set! i #f))
    (gpu-send-images! pass transfer (cdr images) (cdr offs))))

;; n bytes from off in the transfer to the start of a buffer, (id . size).
(define (gpu-to-buffer! pass transfer pair off n)
  (when (> n 0)
    (let ([from gpu-transfer-location*] [to gpu-buffer-region*])
      (ftype-set! gpu-transfer-location (transfer) from transfer)
      (ftype-set! gpu-transfer-location (offset) from off)
      (ftype-set! gpu-buffer-region (buffer) to (car pair))
      (ftype-set! gpu-buffer-region (offset) to 0)
      (ftype-set! gpu-buffer-region (size) to n)
      (sdl-upload-to-buffer pass (gpu-at from) (gpu-at to) #t))))

;; w × h pixels from off in the transfer to texture at (u, v).
(define (gpu-to-texture! pass transfer texture off u v w h)
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

;; Draws the runs, ((mode image first count variant) ...), to target, w × h,
;; cleared to black, or to nothing if clear?. A run that shows a list draws
;; its runs, from its buffers, where it puts it and inside its clip.
(define (gpu-draw-runs! r cb target format w h runs clear?)
  (let ([c gpu-color-target*]
        [samplers gpu-sampler-bindings*]
        [uniforms gpu-frame-uniforms*])
    (gpu-zero! c (ftype-sizeof gpu-color-target))
    (ftype-set! gpu-color-target (texture) c target)
    (ftype-set! gpu-color-target (a) c (if clear? 0.0 1.0))
    (ftype-set! gpu-color-target (load-op) c gpu-load-clear)
    (let ([pass (gpu-must 'gpu-draw-runs!
                          (sdl-begin-render-pass cb (gpu-at c) 1 0))])
      ;; as floats only when they change: a float is made each time
      (unless (and (eqv? w gpu-drawn-w) (eqv? h gpu-drawn-h))
        (set! gpu-drawn-w w)
        (set! gpu-drawn-h h)
        (ftype-set! gpu-frame-uniforms (w) uniforms (fixnum->flonum w))
        (ftype-set! gpu-frame-uniforms (h) uniforms (fixnum->flonum h)))
      (ftype-set! gpu-sampler-bindings (0 texture) samplers (renderer-atlas r))
      (ftype-set! gpu-sampler-bindings (0 sampler) samplers
                  (renderer-sampler r))
      (ftype-set! gpu-sampler-bindings (1 sampler) samplers
                  (renderer-sampler r))
      (gpu-draw-list! r cb pass (gpu-pipelines-for format) format runs
                      (renderer-records r) (renderer-extras r) 0 0 0 0 w h)
      (sdl-end-render-pass pass))))

;; The size of the target the uniforms hold.
(define gpu-drawn-w #f)
(define gpu-drawn-h #f)

;; A list's: its buffers, where it is, its lengths, for the runs next.
(define (gpu-bind-list! r recs extras ox oy)
  (let* ([buffers gpu-storage-buffers*] [uniforms gpu-frame-uniforms*]
         [words gpu-list-words] [glyphs (renderer-glyphs r)]
         [rn (fxquotient (cdr recs) 4)] [en (fxquotient (cdr extras) 4)]
         [gn (fxquotient (cdr glyphs) 4)])
    (ftype-set! gpu-storage-buffers (0) buffers (car recs))
    (ftype-set! gpu-storage-buffers (1) buffers (car extras))
    (ftype-set! gpu-storage-buffers (2) buffers (car glyphs))
    (ftype-set! gpu-frame-uniforms (ox) uniforms ox)
    (ftype-set! gpu-frame-uniforms (oy) uniforms oy)
    (ftype-set! gpu-frame-uniforms (records) uniforms rn)
    (ftype-set! gpu-frame-uniforms (extras) uniforms en)
    (ftype-set! gpu-frame-uniforms (glyphs) uniforms gn)
    (bytevector-s32-native-set! words 0 ox)
    (bytevector-s32-native-set! words 4 oy)
    (bytevector-s32-native-set! words 8 rn)
    (bytevector-s32-native-set! words 12 en)
    (bytevector-s32-native-set! words 16 gn)))

;; What's drawn next is cut to x0 y0 x1 y1, in the target's pixels.
(define (gpu-scissor! pass x0 y0 x1 y1)
  (let ([box gpu-scissor*])
    (ftype-set! gpu-scissor (x) box x0)
    (ftype-set! gpu-scissor (y) box y0)
    (ftype-set! gpu-scissor (w) box (max 0 (- x1 x0)))
    (ftype-set! gpu-scissor (h) box (max 0 (- y1 y0)))
    (sdl-set-gpu-scissor pass (gpu-at box))))

;; A list's runs, from its buffers, at (ox, oy) on the target, inside x0
;; y0 x1 y1; a list it shows inside that and its own clip, and after it
;; this one's state back.
(define (gpu-draw-list! r cb pass pipelines format runs recs extras ox oy
                        x0 y0 x1 y1)
  (let ([buffers gpu-storage-buffers*]
        [samplers gpu-sampler-bindings*]
        [uniforms gpu-frame-uniforms*])
    (gpu-bind-list! r recs extras ox oy)
    (let loop ([runs runs] [bound #f])   ; the pipeline bound, or #f
      (unless (null? runs)
        (let ([run (car runs)])
          (if (gpu-show-run? run)
              (let* ([l (cadr run)] [cx (list-ref run 4)]
                     [state (gpu-list-state l)]
                     [lruns (gpu-recording-runs (gpu-list-seen l))])
                (unless (or (null? lruns)
                            (eqv? 0 (car (vector-ref state 0))))
                  (let ([ix0 (if cx (max x0 (+ ox cx)) x0)]
                        [iy0 (if cx (max y0 (+ oy (list-ref run 5))) y0)]
                        [ix1 (if cx (min x1 (+ ox (list-ref run 6))) x1)]
                        [iy1 (if cx (min y1 (+ oy (list-ref run 7))) y1)])
                    (gpu-scissor! pass ix0 iy0 ix1 iy1)
                    (gpu-draw-list! r cb pass pipelines format lruns
                                    (vector-ref state 0) (vector-ref state 1)
                                    (+ ox (caddr run)) (+ oy (cadddr run))
                                    ix0 iy0 ix1 iy1)
                    (gpu-scissor! pass x0 y0 x1 y1)
                    (gpu-bind-list! r recs extras ox oy)))
                (loop (cdr runs) #f))
              (let* ([image (cadr run)]
                     [count (cadddr run)]
                     [call (and (gpu-call? image) image)]
                     [pipeline (+ (car run) (* 4 (list-ref run 4)))])
                (when (> count 0)
                  (ftype-set! gpu-frame-uniforms (first) uniforms (caddr run))
                  (cond
                    [call (gpu-draw-call! r cb pass call format)]
                    [else
                     (unless (eqv? pipeline bound)
                       (sdl-bind-gpu-pipeline
                        pass (vector-ref pipelines pipeline))
                       (sdl-bind-vertex-storage pass 0 (gpu-at buffers) 3)
                       (sdl-bind-fragment-storage pass 0 (gpu-at buffers) 3))
                     (ftype-set! gpu-sampler-bindings (1 texture) samplers
                                 (if image
                                     (gpu-image-texture image)
                                     (renderer-blank r)))
                     (sdl-bind-fragment-samplers pass 0 (gpu-at samplers) 2)
                     (sdl-push-fragment-uniform cb 0 gpu-list-words 20)])
                  (sdl-push-vertex-uniform cb 0 (gpu-at uniforms)
                                           (ftype-sizeof gpu-frame-uniforms))
                  (sdl-draw-primitives pass 6 count 0 0))
                (loop (cdr runs)
                      (cond [call #f]
                            [(> count 0) pipeline]
                            [else bound])))))))))

;; A paint's run: its pipeline, the list's buffers then its own, and its
;; uniforms, where the list is first and the list's lengths first of its
;; buffers'.
(define (gpu-draw-call! r cb pass call format)
  (let ([buffers gpu-storage-buffers*]
        [u (gpu-call-uniforms call)])
    (sdl-bind-gpu-pipeline pass (gpu-paint-pipeline (gpu-call-shader call)
                                                    format))
    (sdl-bind-vertex-storage pass 0 (gpu-at buffers) 3)
    (let loop ([bs (gpu-call-buffers call)] [i 2])
      (if (null? bs)
          (sdl-bind-fragment-storage pass 0 (gpu-at buffers) i)
          (begin
            (ftype-set! gpu-storage-buffers (i) buffers
                        (gpu-object (gpu-buffer-id (car bs))))
            (loop (cdr bs) (+ i 1)))))
    (ftype-set! gpu-storage-buffers (2) buffers (car (renderer-glyphs r)))
    (bytevector-copy! gpu-list-words 0 u 0 8)
    (bytevector-copy! gpu-list-words 8 u
                      (- (bytevector-length u)
                         (* 4 (gpu-count-params (gpu-call-shader call)
                                                '(fx-buffer fl-buffer))))
                      8)
    (sdl-push-fragment-uniform cb 0 u (bytevector-length u))))

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
    (if (eqv? 0 (renderer-sdl-window r))
        '()
        (map car
             (filter (lambda (m)
                       (sdl-window-supports-present-mode
                        (renderer-device r) (renderer-sdl-window r) (cdr m)))
                     gpu-present-codes)))))

;; How this window presents, and what it was last asked to.
(defvar *gpu-present-mode* 'vsync)
(defvar *gpu-present-asked* 'vsync)

;;; ------------------------------------------------------------------ facts
;;; What core0 says of itself, for the world to read (.work/gpu-design.md
;;; 9.12): an alist the world never changes, made again at the end
;;; of a frame only when what it's made of changed, so that a frame like the
;;; last allocates nothing. A frame's own state, *gpu-frame-state*, and its
;;; waits, *gpu-waits*, are told on their own.

(defvar *gpu-facts* '())

;; What they were made of: records', extras', glyphs' and the transfer's
;; capacity, the target's size, whether there's a window; and the mode.
(defvar *gpu-facts-of* (make-fxvector 7 -1))
(defvar *gpu-facts-mode* #f)

(define (gpu-facts-refresh!)
  (let ([r *renderer*] [of *gpu-facts-of*])
    (unless (and (fx= (fxvector-ref of 0) (cdr (renderer-records r)))
                 (fx= (fxvector-ref of 1) (cdr (renderer-extras r)))
                 (fx= (fxvector-ref of 2) (cdr (renderer-glyphs r)))
                 (fx= (fxvector-ref of 3) (cdr (renderer-transfer r)))
                 (fx= (fxvector-ref of 4) (renderer-target-w r))
                 (fx= (fxvector-ref of 5) (renderer-target-h r))
                 (fx= (fxvector-ref of 6) (if (eqv? 0 (renderer-sdl-window r))
                                              0
                                              1))
                 (eq? *gpu-facts-mode* *gpu-present-mode*))
      (fxvector-set! of 0 (cdr (renderer-records r)))
      (fxvector-set! of 1 (cdr (renderer-extras r)))
      (fxvector-set! of 2 (cdr (renderer-glyphs r)))
      (fxvector-set! of 3 (cdr (renderer-transfer r)))
      (fxvector-set! of 4 (renderer-target-w r))
      (fxvector-set! of 5 (renderer-target-h r))
      (fxvector-set! of 6 (if (eqv? 0 (renderer-sdl-window r)) 0 1))
      (set! *gpu-facts-mode* *gpu-present-mode*)
      (set! *gpu-facts*
        `((renderer . ,(renderer-kind r))
          (windowed? . ,(not (eqv? 0 (renderer-sdl-window r))))
          (driver . ,(gpu-driver-name))
          (present-mode . ,*gpu-present-mode*)
          (present-modes . ,(gpu-present-modes))
          (objects
           (records buffer . ,(cdr (renderer-records r)))
           (extras buffer . ,(cdr (renderer-extras r)))
           (glyphs buffer . ,(cdr (renderer-glyphs r)))
           (atlas texture . ,(* gpu-atlas-side gpu-atlas-side))
           (transfer buffer . ,(cdr (renderer-transfer r)))
           (target texture
                   . ,(* 4 (renderer-target-w r) (renderer-target-h r)))))))))

;; Between frames, the window presents by mode from now on. A mode it doesn't
;; offer leaves it as it is, and is asked once a change: a choice saved on
;; another machine costs this one's frames nothing.
(define (gpu-present-mode! mode)
  (unless (eq? mode *gpu-present-asked*)
    (set! *gpu-present-asked* mode)
    (let ([r *renderer*])
      (when (and (memq mode (gpu-present-modes))
                 (sdl-set-swapchain-parameters
                  (renderer-device r) (renderer-sdl-window r)
                  gpu-composition-sdr (cdr (assq mode gpu-present-codes))))
        (set! *gpu-present-mode* mode)))))

;;; ------------------------------------------------------------------ frames
;;; A frame as main hands it to the host, which reads nothing else of main's
;;; (.work/gpu-design.md 9.5): the root's recording and the frame's number,
;;; "/recorder"'s to set (src/recorder/bytes.ss), the glyph table if it
;;; changed, the atlas's new pieces, images with pixels to go up, the jobs,
;;; the buffers made dirty and the compute runs asked for since, the
;;; present mode, and lists kept from earlier to draw on images first,
;;; (image . recording) each, the recorder's copies. One record goes back and
;;; forth, filled again for each frame: a frame allocates none.

(define-record-type gpu-frame
  (nongenerative schevana-gpu-frame-3)
  (fields (mutable root) (mutable number) (mutable table) (mutable table-n)
          (mutable pieces) (mutable images) (mutable jobs) (mutable dirty)
          (mutable computes) (mutable mode) (mutable earlier)))

;; The frame the host gave back, to fill; #f while it has it.
(defvar *gpu-frame-free* #f)

;; The number of the last frame the host gave back: what it read of the
;; recorder's is free to write again once a later frame doesn't show it.
(defvar *gpu-frame-back* 0)

;; The frame the host gave back, taken to be filled, or a new one.
(define (gpu-frame-take!)
  (let ([f (or *gpu-frame-free*
               (make-gpu-frame #f 0 #f 0 '() '() '() '() '() #f '()))])
    (set! *gpu-frame-free* #f)
    f))



;; The host's side: main's jobs, the lists kept from earlier on their
;; images, then the frame, the dirty buffers going up with the first of
;; them; f given back.
;; => #t if the frame reached the screen; #f if the window had no room for
;; it yet, and it should be tried again.
(define (gpu-present! f)
  (gpu-run-jobs! (gpu-frame-jobs f))
  (gpu-present-mode! (gpu-frame-mode f))
  (let loop ([earlier (gpu-frame-earlier f)] [dirty (gpu-frame-dirty f)])
    (if (pair? earlier)
        (begin
          (gpu-list-on-image! dirty (caar earlier) (cdar earlier))
          (loop (cdr earlier) '()))
        (let ([shown? (gpu-frame! f dirty)])
          ;; read and gone up: the frame goes back, and what it read
          (set! *gpu-frame-back* (gpu-frame-number f))
          (set! *gpu-frame-free* f)
          (gpu-facts-refresh!)
          shown?))))

;; The last frame's waits for the screen, on now-ns's clock: when the
;; acquire began and ended, and the submit; all -1 with no window. Core0
;; times them itself, and the world reads them after (src/host.ss).
(defvar *gpu-waits* (make-fxvector 4 -1))

;; One frame: uploads, then the runs, to the window or the target. => #t if
;; it reached the screen; #f if the window had no room for it yet (a frame
;; still in flight, or it is hidden).
(define (gpu-frame! f dirty)
  (fxvector-fill! *gpu-waits* -1)
  (let* ([r *renderer*]
         [root (gpu-frame-root f)]
         [runs (gpu-recording-runs root)]
         [cb (gpu-must 'gpu-frame!
                       (sdl-acquire-gpu-commands (renderer-device r)))])
    (gpu-upload! r cb dirty (gpu-recording-recs root)
                 (gpu-recording-recs-n root) (gpu-recording-extras root)
                 (gpu-recording-extras-n root) (gpu-frame-table f)
                 (gpu-frame-table-n f) (gpu-frame-pieces f)
                 (gpu-frame-images f) runs)
    (gpu-run-computes! cb (gpu-frame-computes f))
    (if (eqv? 0 (renderer-sdl-window r))
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
               [waits *gpu-waits*]
               [shown?
                (begin
                  (fxvector-set! waits 0 (now-ns))
                  (let ([ok (sdl-acquire-swapchain
                             cb (renderer-sdl-window r)
                             (ftype-pointer-address
                              (ftype-&ref gpu-swapchain-out (texture) out))
                             (ftype-pointer-address
                              (ftype-&ref gpu-swapchain-out (w) out))
                             (ftype-pointer-address
                              (ftype-&ref gpu-swapchain-out (h) out)))])
                    (fxvector-set! waits 1 (now-ns))
                    (and ok
                         (not (eqv? 0 (ftype-ref gpu-swapchain-out (texture)
                                                 out))))))])
          (set! *gpu-frame-state*
            (cond [done? 0] [(gpu-last-frame-done? r) 1] [else 2]))
          (when shown?
            (gpu-draw-runs! r cb (ftype-ref gpu-swapchain-out (texture) out)
                            (sdl-swapchain-format (renderer-device r)
                                                  (renderer-sdl-window r))
                            (ftype-ref gpu-swapchain-out (w) out)
                            (ftype-ref gpu-swapchain-out (h) out)
                            runs #f))
          (fxvector-set! waits 2 (now-ns))
          (let ([fence (gpu-must 'gpu-frame! (sdl-submit-gpu-fence cb))])
            (fxvector-set! waits 3 (now-ns))
            (when (renderer-fence r)
              (sdl-release-gpu-fence (renderer-device r) (renderer-fence r)))
            (renderer-fence-set! r fence))
          shown?))))

;; A list kept from earlier drawn on image, ahead of the next frame, which sends
;; its own: its glyphs are all up already. Its images and paints show what
;; they hold now, but those let go of since; dirty, the buffers going up.
(define (gpu-list-on-image! dirty image rec)
  (let* ([r *renderer*]
         [d (renderer-device r)]
         [runs (gpu-recording-runs rec)]
         [cb (gpu-must 'gpu-list-on-image! (sdl-acquire-gpu-commands d))])
    (gpu-upload! r cb dirty (gpu-recording-recs rec) (gpu-recording-recs-n rec)
                 (gpu-recording-extras rec) (gpu-recording-extras-n rec) #f 0
                 '() '() runs)
    (gpu-draw-runs! r cb (gpu-image-texture image) gpu-format-bgra8
                    (gpu-image-w image) (gpu-image-h image)
                    (remp gpu-run-gone? runs) #f)
    (gpu-image-fill-levels! cb image)
    (sdl-submit-gpu cb)))

;; The same, drawn to a new texture w × h and read back: its pixels, row
;; after row, premultiplied BGRA. What tests, screenshots and icons see;
;; jobs, dirty and computes, what main asked of the GPU since, go first.
(define (gpu-drawing->bytes jobs dirty computes recs recs-n extras extras-n
                           table table-n atlas-pieces images runs w h clear?)
  (gpu-run-jobs! jobs)
  (let* ([r *renderer*]
         [d (renderer-device r)]
         [texture (gpu-make-texture d gpu-format-bgra8 gpu-usage-target w h)]
         [cb (gpu-must 'gpu-drawing->bytes (sdl-acquire-gpu-commands d))])
    (gpu-upload! r cb dirty recs recs-n extras extras-n table table-n
                 atlas-pieces images runs)
    (gpu-run-computes! cb computes)
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
