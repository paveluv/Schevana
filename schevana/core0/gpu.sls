;;; (schevana core0 gpu) — the device side of the GPU layer, in core0 below
;;; the core (.work/gpu-design.md 9.5): the device; pipelines, images,
;;; buffers and lists on the GPU; uploads; the pass; the swapchain; and
;;; presenting a frame that core1 publishes. Only core0 names SDL, and this
;;; file alone tells one driver from another, so that another back end stays
;;; a swap. It names nothing of the core above it except what
;;; tests/sources.ss lists as on its way out.
;;;
;;; Everything that touches a device hangs off one record, a renderer, so
;;; that it can be rebuilt on another device. SDL handles what the GPU still
;;; holds: buffers uploaded and transfer buffers mapped with cycling on are
;;; ring buffers, so they need no fence bookkeeping.

(library (schevana core0 gpu)
  (export
    gpu-atlas-side gpu-usage-sampler gpu-usage-target gpu-windowless-kind
    gpu-windowless-video gpu-open! gpu-idle! gpu-claim-window! gpu-take-answers!
    make-gpu-image gpu-image? gpu-image-id gpu-image-w gpu-image-h
    gpu-image-levels gpu-image-loans gpu-image-loans-set! gpu-image-gone?-set!
    make-gpu-buffer* gpu-buffer-id gpu-buffer-size gpu-buffer-gone?-set!
    make-gpu-call gpu-call? gpu-call-shader make-gpu-recording gpu-recording?
    gpu-recording-recs gpu-recording-recs-set! gpu-recording-recs-n
    gpu-recording-recs-n-set! gpu-recording-extras gpu-recording-extras-set!
    gpu-recording-extras-n gpu-recording-extras-n-set! gpu-recording-runs
    gpu-recording-runs-set! gpu-recording-version gpu-recording-version-set!
    gpu-recording-until gpu-recording-until-set! gpu-recording-next
    gpu-recording-next-set! make-gpu-list gpu-list-id gpu-list-recording
    gpu-list-recording-set! gpu-list-labels gpu-list-labels-set!
    gpu-list-recorded gpu-list-recorded-set! gpu-list-took gpu-list-took-set!
    gpu-show-run? gpu-run-gone? gpu-compute-now! gpu-submit-computes!
    gpu-reads-now! gpu-buffer-download! *gpu-facts* gpu-frame-root-set!
    gpu-frame-number gpu-frame-number-set! gpu-frame-table-set!
    gpu-frame-table-n-set! gpu-frame-pieces-set! gpu-frame-jobs-set!
    gpu-frame-writes-set! gpu-frame-computes-set! gpu-frame-mode-set!
    gpu-frame-in-flight-set! gpu-frame-earlier-set! gpu-frame-shown?
    gpu-frame-shown?-set! gpu-frame-next gpu-frame-next-set! gpu-frame-wakes
    gpu-frame-wakes-set! gpu-frame-make
    *gpu-frame-back* *gpu-published* gpu-publish! gpu-frame-waiting?
    gpu-give-back! gpu-frames-back! gpu-present! gpu-drawing->bytes
    *gpu-present-mode* *gpu-frames-in-flight*)
  (import (chezscheme)
          (only (schevana base) at-load define-made define-state library-layer
                string-contains-ci? string-join string-suffix?)
          (only (schevana shader) shader shader-code shader-entry shader-group-x
                shader-params shader-stage shader-target shader-uniforms)
          (only (schevana sdl) gpu-copy-in gpu-copy-out sdl-acquire-gpu-commands
                sdl-acquire-swapchain sdl-begin-compute-pass sdl-begin-copy-pass
                sdl-begin-render-pass sdl-bind-compute-pipeline
                sdl-bind-compute-storage sdl-bind-fragment-samplers
                sdl-bind-fragment-storage sdl-bind-gpu-pipeline
                sdl-bind-vertex-storage sdl-claim-window sdl-create-gpu-buffer
                sdl-create-gpu-compute sdl-create-gpu-device
                sdl-create-gpu-pipeline sdl-create-gpu-sampler
                sdl-create-gpu-shader sdl-create-gpu-texture
                sdl-create-gpu-transfer sdl-dispatch-compute
                sdl-download-from-buffer sdl-download-from-texture
                sdl-draw-primitives sdl-end-compute-pass sdl-end-copy-pass
                sdl-end-render-pass sdl-generate-gpu-mipmaps sdl-get-error
                sdl-map-gpu-transfer sdl-memcpy sdl-memset
                sdl-push-compute-uniform sdl-push-fragment-uniform
                sdl-push-vertex-uniform sdl-release-gpu-buffer
                sdl-release-gpu-compute sdl-release-gpu-fence
                sdl-release-gpu-pipeline sdl-release-gpu-shader
                sdl-release-gpu-texture sdl-release-gpu-transfer
                sdl-set-frames-in-flight sdl-set-gpu-scissor
                sdl-set-swapchain-parameters sdl-submit-gpu sdl-submit-gpu-fence
                sdl-swapchain-format sdl-unmap-gpu-transfer sdl-upload-to-buffer
                sdl-upload-to-texture sdl-wait-gpu-fences sdl-wait-gpu-idle
                sdl-window-supports-present-mode)
          (only (schevana core0 mail) *core0-forked* *core0-time*
                core0-clock-ns core0-frame-ns core0-put! core0-take!
                core0-wake! core0-world-wake!)
          (only (schevana core0 trace) core0-trace!)
          (only (schevana core0 renderer) *renderer* gpu-driver-name
                make-renderer renderer-atlas renderer-blank renderer-device
                renderer-extras renderer-extras-set! renderer-fence
                renderer-fence-set! renderer-glyphs renderer-glyphs-set!
                renderer-kind renderer-paints renderer-pipelines
                renderer-pipelines-set! renderer-records renderer-records-set!
                renderer-sampler renderer-sdl-window renderer-sdl-window-set!
                renderer-target renderer-target-h renderer-target-h-set!
                renderer-target-set! renderer-target-w renderer-target-w-set!
                renderer-transfer renderer-transfer-set!)
          (only (schevana core0 present) present-acquired! present-acquiring!
                present-done! present-fence! present-sent! present-submitted!
                present-submitting!)
          (only (schevana core0 platform) core0-look-ns platform-report-ask!))

  (library-layer core0)

  ;; scratch memory for structs on their way to SDL
  (define-state *gpu-scratch* (foreign-alloc 2048))

  (define gpu-atlas-side 4096)
  (define gpu-format-r8 2)
  (define gpu-format-bgra8 12)
  (define gpu-usage-sampler 1)
  (define gpu-usage-target 2)
  (define gpu-usage-graphics-read 8)
  (define gpu-usage-compute-read 16)
  (define gpu-usage-compute-write 32)
  ;; The shaders' format, as SDL numbers it: SPIR-V or MSL.
  (define-made gpu-shader-format (if (eq? shader-target 'msl) 16 2))
  (define gpu-blend-zero 1)
  (define gpu-blend-one 2)
  (define gpu-blend-one-minus-source 4)
  (define gpu-blend-one-minus-target 6)
  (define gpu-blend-one-minus-source-alpha 8)
  (define gpu-op-add 1)
  (define gpu-op-subtract 2)
  (define gpu-load-clear 1)
  (define gpu-address-clamp 2)

  ;;; ---- SDL's structs. Chez lays out their fields by the platform's C
  ;;; rules, so no field's offset is counted by hand. Each struct has a place
  ;;; of its own in the scratch memory, and a pointer made once, so a frame
  ;;; allocates none.

  (define-syntax gpu-struct
    (syntax-rules ()
      [(_ name pointer offset type)
       (begin
         (define-ftype name type)
         (define-made pointer
           (make-ftype-pointer name (+ *gpu-scratch* offset))))]))

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
            [resolve void*] [resolve-mip unsigned-32]
            [resolve-layer unsigned-32]
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
  ;; The vertex shader's uniforms. The fragment shader's are the last five
  ;; (where the list sits on the target, and its buffers' lengths in words),
  ;; which go as bytes (gpu-list-words).
  (gpu-struct gpu-frame-uniforms gpu-frame-uniforms* 1040
    (struct [w float] [h float] [first int] [ox int] [oy int]
            [records int] [extras int] [glyphs int]))
  (define-made gpu-list-words (make-bytevector 20 0))
  (gpu-struct gpu-scissor gpu-scissor* 1072
    (struct [x int] [y int] [w int] [h int]))
  (gpu-struct gpu-swapchain-out gpu-swapchain-out* 720
    (struct [texture void*] [w unsigned-32] [h unsigned-32]))
  (gpu-struct gpu-fence-list gpu-fence-list* 736
    (array 1 void*))

  ;; The address of a struct, for the C call that takes it.
  (define (gpu-at pointer) (ftype-pointer-address pointer))

  (define (gpu-must who p)
    (when (eqv? p 0) (errorf who "~a" (sdl-get-error)))
    p)

  ;;; ------------------------------------------------------------------ devices

  ;; On Linux, the Vulkan drivers that may load, by a file for each:
  ;; lavapipe alone for the CPU, and the others for the GPU, so that lavapipe
  ;; and LLVM never load for the GPU. Elsewhere the driver is SDL's choice.
  (define (gpu-driver-files kind)
    (let ([files
           (apply append
                  (map (lambda (dir)
                         (if (file-directory? dir)
                             (map (lambda (f) (string-append dir "/" f))
                                  (filter (lambda (f)
                                            (string-suffix? ".json" f))
                                          (directory-list dir)))
                             '()))
                       '("/usr/share/vulkan/icd.d" "/etc/vulkan/icd.d"
                         "/usr/local/share/vulkan/icd.d")))])
      (define (lavapipe? f) (string-contains-ci? f "lvp_icd"))
      (if (eq? kind 'cpu) (filter lavapipe? files) (remp lavapipe? files))))

  ;; With no window: what renders, and SDL's video driver (#f leaves the
  ;; choice to SDL). Metal is a Mac's only renderer and needs its real video
  ;; driver, which opens no window until asked; Vulkan has lavapipe for this.
  (define-made gpu-windowless-kind (if (eq? shader-target 'msl) 'gpu 'cpu))
  (define-made gpu-windowless-video
    (if (eq? shader-target 'msl) #f "offscreen"))

  ;; Opens a device of this kind, 'gpu or 'cpu, and returns it, or #f.
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

  ;; Opens the renderer of this kind, ready to draw; the GPU falls back to
  ;; the CPU.
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

  ;; Waits until the device has done all it was sent, if one is open:
  ;; before the window goes, and before the process ends.
  (define (gpu-idle!)
    (when *renderer* (sdl-wait-gpu-idle (renderer-device *renderer*))))

  ;; Every exit waits for the GPU first, whoever calls it: the world's quit,
  ;; a suite's verdict, a script. A driver's own threads may still be at
  ;; work (lavapipe compiling a frame's new shaders with LLVM), and exit()
  ;; would tear down LLVM's globals under them. The handler is set on the
  ;; thread that loads core0, the process's first, whose exit alone ends the
  ;; process (on a thread that Chez forked, exit ends only that thread).
  (at-load
   (exit-handler
    (let ([chez (exit-handler)])
      (lambda args
        ;; a wait that fails never keeps the process from ending
        (guard (c [#t #f]) (gpu-idle!))
        (apply chez args)))))

  ;; Frames in flight, and so images in the swapchain: by default three,
  ;; the most SDL allows (the world's 'frames-in-flight, sent with each
  ;; frame). With two, GPU work that took most of a refresh missed
  ;; refreshes; three cover a stall of core0's of up to about two refreshes,
  ;; at the cost of a refresh more of latency when the queue fills.
  (define-state *gpu-frames-in-flight* 3)

  ;; Sets what frames draw to with no window: a texture w × h.
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

  (define-made gpu-entry-name
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

  ;; Mode 0 covers what's there, premultiplied; mode 1 leaves the source
  ;; minus what's there; mode 2 turns what's there to its inverse by the
  ;; source's amount, so that a pattern's clear pixels leave it alone; mode 3
  ;; adds. The last three leave alpha as it is.
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

  ;; The core's shaders, with which records are drawn, as core1 hands them
  ;; over ((schevana core draw)): (vertex . fragments), where fragments is a
  ;; vector of the fragment shader's variants.
  (define-state *gpu-shaders* #f)

  ;; Returns the pipelines that draw records to this format, made once: four,
  ;; by mode, for each variant of the fragment shader, in their order. All
  ;; are made at once, so that the first run to need one doesn't wait for it.
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
                                          (gpu-pipelines-of
                                           d vs fragment format))
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

  ;; Releases every pipeline: after a reload the shaders may be new.
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
  ;;; The SDL objects behind core1's handles, by id, each as (kind object .
  ;;; sizes): (texture object w h), (buffer object bytes), (atlas object).
  ;;; They are made and released by the jobs core1 asks for, which core0 runs
  ;;; before anything that needs them (.work/gpu-design.md 9.12); the sizes
  ;;; are core0's own, and every write core1 hands it must fit them.

  (define-state *gpu-objects* (make-eqv-hashtable))

  ;; Whether core0 has made the object behind handle id.
  (define (gpu-object-made? id) (and (hashtable-ref *gpu-objects* id #f) #t))

  ;; The SDL object behind handle id.
  (define (gpu-object id)
    (let ([o (hashtable-ref *gpu-objects* id #f)])
      (unless o (errorf 'gpu-object "~a has no object: its job hasn't run" id))
      (cadr o)))

  ;; Core1's jobs, run in order: (texture id w h usage levels); (buffer id
  ;; bytes), zeroed; (atlas id), the glyphs' atlas under id; (shaders vertex
  ;; fragments), the core's; (target w h), the size frames draw to with no
  ;; window; (release id); and (read then recs recs-n extras extras-n table
  ;; table-n pieces runs w h clear?), a drawing read back, whose pixels are
  ;; left with then in *gpu-answers*, newest first.
  (define-state *gpu-answers* (box '()))

  ;; Takes what core0 read back for core1 since core1 last took it, each as
  ;; (then . bytes), in order: core1 hands each to its then. Safe from any
  ;; thread.
  (define (gpu-take-answers!) (core0-take! *gpu-answers*))

  ;; Runs the jobs and core1's writes since it last handed them on (writes:
  ;; a recording of the recorder's, or #f): first the jobs that make
  ;; objects, then the writes into them, then the reads that see them and
  ;; the releases.
  (define (gpu-run-jobs! jobs writes)
    (for-each (lambda (job)
                (unless (memq (car job) '(read release)) (gpu-run-job! job)))
              jobs)
    (gpu-send-writes! writes)
    (for-each (lambda (job)
                (when (memq (car job) '(read release)) (gpu-run-job! job)))
              jobs))

  (define (gpu-run-job! job)
    (let ([d (renderer-device *renderer*)])
      (case (car job)
        [(texture)
         (let-values ([(id w h usage levels) (apply values (cdr job))])
           (hashtable-set! *gpu-objects* id
                           (list 'texture
                                 (gpu-make-texture d gpu-format-bgra8 usage w h
                                                   levels)
                                 w h)))]
        [(buffer)
         (let ([p gpu-buffer-info*] [n (caddr job)])
           (gpu-zero! p (ftype-sizeof gpu-buffer-info))
           (ftype-set! gpu-buffer-info (usage) p
                       (fxior gpu-usage-graphics-read gpu-usage-compute-read
                              gpu-usage-compute-write))
           (ftype-set! gpu-buffer-info (size) p n)
           (let ([b (gpu-must 'gpu-run-jobs!
                              (sdl-create-gpu-buffer d (gpu-at p)))])
             (gpu-buffer-zero! d b n)
             (hashtable-set! *gpu-objects* (cadr job) (list 'buffer b n))))]
        [(atlas)
         (hashtable-set! *gpu-objects* (cadr job)
                         (list 'atlas (renderer-atlas *renderer*)))]
        [(shaders)
         (set! *gpu-shaders* (cons (cadr job) (caddr job)))
         (gpu-forget-pipelines!)]
        [(target) (gpu-set-target! (cadr job) (caddr job))]
        [(read)
         (core0-put! *gpu-answers*
                    (cons (cadr job)
                          (apply gpu-drawing->bytes '() #f '() (cddr job))))]
        [(release)
         (gpu-list-free! (cadr job))
         (let ([o (hashtable-ref *gpu-objects* (cadr job) #f)])
           (hashtable-delete! *gpu-objects* (cadr job))
           (when o
             (case (car o)
               [(texture) (sdl-release-gpu-texture d (cadr o))]
               [(buffer) (sdl-release-gpu-buffer d (cadr o))])))])))

  ;; Zeroes a new buffer's n bytes, by a copy of its own sent now, so that
  ;; what is written into it later comes after.
  (define (gpu-buffer-zero! d buffer n)
    (let* ([transfer (gpu-make-transfer d 0 n)]
           [mapped (gpu-must 'gpu-buffer-zero!
                             (sdl-map-gpu-transfer d transfer #f))])
      (sdl-memset mapped 0 n)
      (sdl-unmap-gpu-transfer d transfer)
      (let* ([cb (gpu-must 'gpu-buffer-zero! (sdl-acquire-gpu-commands d))]
             [pass (sdl-begin-copy-pass cb)])
        (gpu-to-region! pass transfer 0 buffer 0 n)
        (sdl-end-copy-pass pass)
        (sdl-submit-gpu cb))
      (sdl-release-gpu-transfer d transfer)))

  ;; Copies n bytes from off in the transfer to buffer at at, keeping what
  ;; is around them.
  (define (gpu-to-region! pass transfer off buffer at n)
    (let ([from gpu-transfer-location*] [to gpu-buffer-region*])
      (ftype-set! gpu-transfer-location (transfer) from transfer)
      (ftype-set! gpu-transfer-location (offset) from off)
      (ftype-set! gpu-buffer-region (buffer) to buffer)
      (ftype-set! gpu-buffer-region (offset) to at)
      (ftype-set! gpu-buffer-region (size) to n)
      (sdl-upload-to-buffer pass (gpu-at from) (gpu-at to) #f)))

  ;;; ------------------------------------------------------------------ writes
  ;;; What core1 writes into buffers and images goes in a recording of the
  ;;; recorder's, the frame's writes. Its records are spans of 32 bytes,
  ;;; (kind id x y src n 0 0), and its extras the words they name. Kind 0
  ;;; writes n words into buffer id from word x, from src in the extras;
  ;;; kind 1, n pixels into image id at (x, y), from src; kind 2, rows y to
  ;;; y + n of image id from the next of the recording's loans, each a
  ;;; recording whose records are the image's pixels, chained through their
  ;;; runs from the recording's. Core0 checks each span against the sizes
  ;;; it made the object with, and skips one that doesn't fit.

  ;; Returns what a span (kind id x y n, with loan its loan's bytes, or #f)
  ;; writes into, as (kind object . sizes), or #f if the span doesn't fit.
  (define (gpu-write-fits kind id x y n loan)
    (let ([o (hashtable-ref *gpu-objects* id #f)])
      (and o
           (fx> n 0)
           (case kind
             [(0) (and (eq? (car o) 'buffer) (fx>= x 0)
                       (<= (* 4 (+ x n)) (caddr o)))]
             [(1) (and (eq? (car o) 'texture) (fx>= x 0) (fx>= y 0)
                       (fx< y (cadddr o)) (<= (+ x n) (caddr o)))]
             [(2) (and (eq? (car o) 'texture) loan (fx>= y 0)
                       (<= (+ y n) (cadddr o))
                       (= (bytevector-length loan)
                          (* 4 (caddr o) (cadddr o))))]
             [else #f])
           o)))

  ;; Walks each span of writes that fits, in order, each of kind 2 taking
  ;; the next loan. With mapped, it copies the loan's rows into the transfer
  ;; mapped there; with pass, it copies the span into its object from the
  ;; transfer, by pass. The rows go after the extras, which go first, whole.
  ;; Returns where they end.
  (define (gpu-writes-walk! writes mapped pass transfer)
    (let ([recs (gpu-recording-recs writes)] [n (gpu-recording-recs-n writes)])
      (let loop ([at 0] [loans (gpu-recording-runs writes)]
                 [off (gpu-recording-extras-n writes)])
        (if (fx>= at n)
            off
            (let* ([word (lambda (k)
                           (bytevector-s32-native-ref recs (fx+ at k)))]
                   [kind (word 0)] [x (word 8)] [y (word 12)] [src (word 16)]
                   [count (word 20)]
                   [loan (and (fx= kind 2) (gpu-recording? loans) loans)]
                   [o (gpu-write-fits kind (word 4) x y count
                                      (and loan (gpu-recording-recs loan)))]
                   [row (if o (* 4 (caddr o)) 0)]
                   [size (if (fx= kind 2) (* row count) 0)])
              (when (and o mapped (fx= kind 2))
                (sdl-memcpy (+ mapped off)
                            (+ (object->reference-address
                                (gpu-recording-recs loan))
                               (* row y))
                            size))
              (when (and o pass)
                (case kind
                  [(0) (gpu-to-region! pass transfer src (cadr o) (* 4 x)
                                       (* 4 count))]
                  [(1) (gpu-to-texture! pass transfer (cadr o) src x y count 1)]
                  [else (gpu-to-texture! pass transfer (cadr o) off 0 y
                                         (caddr o) count)]))
              (loop (fx+ at 32)
                    (cond [loan (gpu-recording-runs loan)]
                          [(fx= kind 2) '()]
                          [else loans])
                    (+ off size)))))))

  ;; Sends core1's writes (writes, or #f for none) into their objects, by a
  ;; copy pass of their own sent now, ahead of anything that reads them,
  ;; through one transfer. Then, with core0 done reading them, they are free
  ;; for the recorder to write again, loans and all.
  (define (gpu-send-writes! writes)
    (when writes
      (gpu-writes-copy! writes)
      (memory-order-release)
      (gpu-recording-until-set! writes 0)
      (let loop ([loan (gpu-recording-runs writes)])
        (when (gpu-recording? loan)
          (gpu-recording-until-set! loan 0)
          (loop (gpu-recording-runs loan))))))

  (define (gpu-writes-copy! writes)
    (when (fx> (gpu-recording-recs-n writes) 0)
      (let* ([r *renderer*]
             [d (renderer-device r)]
             [transfer (car (gpu-sized-transfer
                             r (max 16 (gpu-writes-walk! writes #f #f #f))))]
             [mapped (gpu-must 'gpu-send-writes!
                               (sdl-map-gpu-transfer d transfer #t))])
        (gpu-copy-in mapped (gpu-recording-extras writes)
                     (gpu-recording-extras-n writes))
        (gpu-writes-walk! writes mapped #f transfer)
        (sdl-unmap-gpu-transfer d transfer)
        (let* ([cb (gpu-must 'gpu-send-writes! (sdl-acquire-gpu-commands d))]
               [pass (sdl-begin-copy-pass cb)])
          (gpu-writes-walk! writes #f pass transfer)
          (sdl-end-copy-pass pass)
          (sdl-submit-gpu cb)))))

  ;;; ------------------------------------------------------------------ images
  ;;; An image is a texture of premultiplied BGRA, with its pixels on the
  ;;; GPU alone.

  ;; Core1's handle on an image: its id in *gpu-objects*, its size and
  ;; levels, the recording its loans are chained after (the recorder's; #f
  ;; until it lends one), and gone?, whether it was released, so that a list
  ;; kept from before that names it draws without it.
  (define-record-type gpu-image
    (nongenerative schevana-gpu-image-3)
    (fields id w h levels (mutable loans) (mutable gone?)))

  (define (gpu-image-texture image) (gpu-object (gpu-image-id image)))

  ;; Carries what was just drawn on image down its chain of mip levels.
  (define (gpu-image-fill-levels! cb image)
    (when (> (gpu-image-levels image) 1)
      (sdl-generate-gpu-mipmaps cb (gpu-image-texture image))))

  ;;; ------------------------------------------------------------------ buffers
  ;;; A buffer a shader reads or writes: whole numbers or floats, 32 bits
  ;;; each, on the GPU alone. What is set goes up with the next frame, or
  ;;; the next compute run, among core1's writes.

  ;; Core1's handle on a buffer: its id in *gpu-objects*, its size in
  ;; bytes, and gone?, whether it was released, as for an image.
  (define-record-type (gpu-buffer make-gpu-buffer* gpu-buffer?)
    (nongenerative schevana-gpu-buffer-3)
    (fields id size (mutable gone?)))

  ;; What a paint or a compute run is called with: its shader, its
  ;; uniforms as bytes, and its buffers.
  (define-record-type gpu-call
    (nongenerative schevana-gpu-call-1)
    (fields shader uniforms buffers))

  ;; What a recording left. The recorder ((schevana recorder bytes)) is the
  ;; only code that writes one: its records and extras, as bytes, and how
  ;; many of each; its runs; and its version, its list's count of
  ;; recordings. Frozen once recorded, it is what core0 reads, whole: a list
  ;; or a frame swaps to a newer one by one store. until and next are the
  ;; recorder's own: when it may be written again, and its list's other
  ;; recordings.
  (define-record-type gpu-recording
    (nongenerative schevana-gpu-recording-1)
    (fields (mutable recs) (mutable recs-n) (mutable extras) (mutable extras-n)
            (mutable runs) (mutable version) (mutable until) (mutable next)))

  ;; A list kept to be shown by another: its recording, and the labels the
  ;; recorder gave it; when it was last recorded (core0-clock-ns) and in how
  ;; many ns, for (schevana kits inspect). Its id, a handle's, names its GPU
  ;; buffers in *gpu-lists*; it is #f for a copy that is never shown
  ;; ((schevana kits inspect)).
  (define-record-type gpu-list
    (nongenerative schevana-gpu-list-3)
    (fields id (mutable recording) (mutable labels) (mutable recorded)
            (mutable took)))

  ;; What core0 keeps of each list shown, by id: #(records extras version
  ;; recs-at extras-at seen seen-in), with its GPU buffers, each (buffer .
  ;; size); the version that went up; where its records and extras wait in
  ;; the transfer while they go up, or #f; and the recording this pass reads,
  ;; with the pass it was read in. A list goes up when it has a newer
  ;; version.
  (define-state *gpu-lists* (make-eqv-hashtable))

  (define (gpu-list-state l)
    (let ([id (or (gpu-list-id l)
                  (errorf 'gpu-list-state "a copy of a list is never shown"))])
      (or (hashtable-ref *gpu-lists* id #f)
          (let ([state (vector (cons 0 0) (cons 0 0) 0 #f #f #f -1)])
            (hashtable-set! *gpu-lists* id state)
            state))))

  ;; Each upload and the drawing after it is a pass, which reads each list's
  ;; recording once, the first time it meets the list, so that a list
  ;; recorded again while core0 reads it shows the same recording in every
  ;; step of the pass.
  (define-state *gpu-pass* 0)

  (define (gpu-list-seen l)
    (let ([state (gpu-list-state l)])
      (unless (fx= (vector-ref state 6) *gpu-pass*)
        (vector-set! state 5 (gpu-list-recording l))
        (vector-set! state 6 *gpu-pass*))
      (vector-ref state 5)))

  (define (gpu-list-fresh? l)
    (not (fx= (vector-ref (gpu-list-state l) 2)
              (gpu-recording-version (gpu-list-seen l)))))

  ;; Releases a list's GPU buffers, for core1's release job: shown again,
  ;; the list goes up again.
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
  ;; x1 y1 there (x0 is #f for none), with labels, the recorder's, before
  ;; it.
  (define (gpu-show-run? run) (eq? (car run) 'show))

  ;; Returns n plus the bytes that the lists runs show (and the lists those
  ;; show) take in the transfer, for those that changed since they went up:
  ;; a list shown twice counts twice.
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

  ;; Whether a run, (mode image first count variant), shows an image or a
  ;; paint's buffer released since it was drawn. A list kept draws without
  ;; it.
  (define (gpu-run-gone? run)
    (let ([x (cadr run)])
      (cond [(gpu-image? x) (gpu-image-gone? x)]
            [(gpu-call? x) (exists gpu-buffer-gone? (gpu-call-buffers x))]
            [else #f])))

  ;; Whether core0 can draw a run now: it is not gone, and every object it
  ;; names is made. A list recorded again for the next frame, which core0
  ;; may read before it takes that frame, can name what that frame's jobs
  ;; make; the run then waits a frame for them.
  (define (gpu-run-drawable? run)
    (and (not (gpu-run-gone? run))
         (let ([x (cadr run)])
           (cond [(gpu-image? x) (gpu-object-made? (gpu-image-id x))]
                 [(gpu-call? x)
                  (for-all (lambda (b) (gpu-object-made? (gpu-buffer-id b)))
                           (gpu-call-buffers x))]
                 [else #t]))))

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

  ;; The pipeline that runs a compute shader, built when first asked for,
  ;; and kept with the paints'.
  (define (gpu-compute-pipeline shader)
    (let* ([r *renderer*]
           [ps (hashtable-ref (renderer-paints r) shader '())])
      (cond
        [(assq 'compute ps) => cdr]
        [else
         (let ([p (gpu-make-compute (renderer-device r) shader)])
           (hashtable-set! (renderer-paints r) shader
                           (cons (cons 'compute p) ps))
           p)])))

  ;; Records a compute run on cb, in a pass of its own.
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
           (sdl-push-compute-uniform
            cb 0 (gpu-call-uniforms call)
            (bytevector-length (gpu-call-uniforms call)))
           (sdl-dispatch-compute pass (quotient (+ w (- shader-group-x 1))
                                                shader-group-x)
                                 h 1)
           (sdl-end-compute-pass pass))))
     run))

  ;; Runs run now, after core1's jobs and writes, and waits for it.
  (define (gpu-compute-now! run jobs writes)
    (gpu-run-jobs! jobs writes)
    (let* ([r *renderer*]
           [cb (gpu-must 'gpu-compute-now!
                         (sdl-acquire-gpu-commands (renderer-device r)))])
      (gpu-dispatch! cb run)
      (gpu-wait! (gpu-must 'gpu-compute-now! (sdl-submit-gpu-fence cb)))))

  ;; Records runs, in order, on cb: after its uploads, before its draws.
  (define (gpu-run-computes! cb runs)
    (for-each (lambda (run) (gpu-dispatch! cb run)) runs))

  ;; Sends runs that no frame took, after core1's jobs and writes, with no
  ;; frame, and nobody waits for them. The queue keeps the order: what a
  ;; frame sent after them reads finds them done.
  (define (gpu-submit-computes! runs jobs writes)
    (gpu-run-jobs! jobs writes)
    (let* ([r *renderer*]
           [cb (gpu-must 'gpu-submit-computes!
                         (sdl-acquire-gpu-commands (renderer-device r)))])
      (gpu-run-computes! cb runs)
      (sdl-submit-gpu cb)))

  ;; Sends runs, after core1's jobs and writes, then reads back the buffers
  ;; that reads names, each as (id . then): each buffer's bytes, a copy of
  ;; its own, or #f if id names none, are left with its then in
  ;; *gpu-answers*, and core1 is woken for them. The queue keeps the order:
  ;; a read finds the runs done. Core0 waits for its copies, between frames;
  ;; core1 never does.
  (define (gpu-reads-now! runs jobs writes reads)
    (gpu-submit-computes! runs jobs writes)
    (for-each (lambda (read)
                (core0-put! *gpu-answers*
                            (cons (cdr read)
                                  (gpu-buffer-download! '() #f (car read)))))
              reads)
    (core0-world-wake!))

  ;; Returns what is in buffer id now, after core1's jobs and writes: its
  ;; bytes, a copy of its own, or #f if id names no buffer.
  (define (gpu-buffer-download! jobs writes id)
    (gpu-run-jobs! jobs writes)
    (let ([o (hashtable-ref *gpu-objects* id #f)])
      (and o (eq? (car o) 'buffer) (gpu-buffer-copy-down (cadr o) (caddr o)))))

  (define (gpu-buffer-copy-down buffer n)
    (let* ([r *renderer*]
           [d (renderer-device r)]
           [transfer (gpu-make-transfer d 1 n)]
           [cb (gpu-must 'gpu-buffer-download! (sdl-acquire-gpu-commands d))]
           [pass (sdl-begin-copy-pass cb)]
           [from gpu-buffer-region*]
           [to gpu-transfer-location*])
      (ftype-set! gpu-buffer-region (buffer) from buffer)
      (ftype-set! gpu-buffer-region (offset) from 0)
      (ftype-set! gpu-buffer-region (size) from n)
      (ftype-set! gpu-transfer-location (transfer) to transfer)
      (ftype-set! gpu-transfer-location (offset) to 0)
      (sdl-download-from-buffer pass (gpu-at from) (gpu-at to))
      (sdl-end-copy-pass pass)
      (gpu-wait! (gpu-must 'gpu-buffer-download! (sdl-submit-gpu-fence cb)))
      (let ([bytes (make-bytevector n)])
        (gpu-copy-out bytes
                      (gpu-must 'gpu-buffer-download!
                                (sdl-map-gpu-transfer d transfer #f))
                      n)
        (sdl-unmap-gpu-transfer d transfer)
        (sdl-release-gpu-transfer d transfer)
        bytes)))

  ;;; ------------------------------------------------------------------ frames

  ;; Returns a buffer at least n bytes big, as a pair (buffer . capacity):
  ;; the same one while it fits.
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
                          (sdl-create-gpu-buffer (renderer-device r)
                                                 (gpu-at p)))
                cap))))

  (define (gpu-make-transfer device usage size)
    (let ([p gpu-transfer-info*])
      (gpu-zero! p (ftype-sizeof gpu-transfer-info))
      (ftype-set! gpu-transfer-info (usage) p usage)
      (ftype-set! gpu-transfer-info (size) p size)
      (gpu-must 'gpu-make-transfer
                (sdl-create-gpu-transfer device (gpu-at p)))))

  (define (gpu-sized-transfer r n)
    (let ([pair (renderer-transfer r)])
      (if (>= (cdr pair) n)
          pair
          (let ([cap (max 65536 (* 2 n))])
            (unless (eqv? 0 (car pair))
              (sdl-release-gpu-transfer (renderer-device r) (car pair)))
            (let ([new (cons (gpu-make-transfer (renderer-device r) 0 cap)
                             cap)])
              (renderer-transfer-set! r new)
              new)))))

  ;; Uploads what a frame needs, in a copy pass of cb: the records and extras,
  ;; the glyph table if it changed, new atlas pieces ((u v w h bytes) ...),
  ;; and the lists the runs show that changed, all through one transfer
  ;; buffer, mapped once. A frame with none of those allocates nothing.
  (define (gpu-upload! r cb recs recs-n extras extras-n table table-n
                       atlas-pieces runs)
    (set! *gpu-pass* (fx+ *gpu-pass* 1))
    (let* ([total (+ recs-n extras-n (if table table-n 0) 8
                     (gpu-fresh-bytes runs 0)
                     (gpu-each-bytes atlas-pieces gpu-piece-bytes 0))]
           [transfer (car (gpu-sized-transfer r (max total 16)))]
           [mapped (gpu-must 'gpu-upload!
                             (sdl-map-gpu-transfer (renderer-device r) transfer
                                                   #t))])
      (set! gpu-put-at 0)
      (let* ([recs-at (gpu-put! mapped recs recs-n)]
             [extras-at (gpu-put! mapped extras extras-n)]
             [table-at (and table (gpu-put! mapped table table-n))]
             [piece-ats (gpu-put-each! mapped atlas-pieces gpu-piece-bytes)])
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
          (when table-at
            (gpu-to-buffer! pass transfer table-b table-at table-n))
          (gpu-send-lists! r pass transfer runs)
          (gpu-send-pieces! r pass transfer atlas-pieces piece-ats)
          (sdl-end-copy-pass pass)))))

  ;; Where the next bytes go in the transfer being filled.
  (define-state gpu-put-at 0)

  ;; Copies n of bv's bytes into the mapped transfer, starting on a word: a
  ;; piece of the atlas may leave any length, and what follows starts on a
  ;; word. Returns where they went.
  (define (gpu-put! mapped bv n)
    (let ([off (logand (+ gpu-put-at 3) -4)])
      (gpu-copy-in (+ mapped off) bv n)
      (set! gpu-put-at (+ off n))
      off))

  (define (gpu-piece-bytes p) (car (cddddr p)))

  ;; Returns n plus the bytes of each of xs (by bytes-of), with up to 3
  ;; more for each, for where it starts.
  (define (gpu-each-bytes xs bytes-of n)
    (if (null? xs)
        n
        (gpu-each-bytes (cdr xs) bytes-of
                        (+ n 3 (bytevector-length (bytes-of (car xs)))))))

  ;; Copies each of xs's bytes into the transfer. Returns where each went.
  (define (gpu-put-each! mapped xs bytes-of)
    (if (null? xs)
        '()
        (let ([bv (bytes-of (car xs))])
          (let ([off (gpu-put! mapped bv (bytevector-length bv))])
            (cons off (gpu-put-each! mapped (cdr xs) bytes-of))))))

  ;; Copies the lists that runs show and that changed into the transfer,
  ;; each once.
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

  ;; Copies those lists from the transfer into their own buffers, in pass.
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

  ;; Copies n bytes from off in the transfer to the start of a buffer,
  ;; given as (buffer . capacity).
  (define (gpu-to-buffer! pass transfer pair off n)
    (when (> n 0)
      (let ([from gpu-transfer-location*] [to gpu-buffer-region*])
        (ftype-set! gpu-transfer-location (transfer) from transfer)
        (ftype-set! gpu-transfer-location (offset) from off)
        (ftype-set! gpu-buffer-region (buffer) to (car pair))
        (ftype-set! gpu-buffer-region (offset) to 0)
        (ftype-set! gpu-buffer-region (size) to n)
        (sdl-upload-to-buffer pass (gpu-at from) (gpu-at to) #t))))

  ;; Copies w × h pixels from off in the transfer to texture at (u, v).
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

  ;; Draws the runs, ((mode image first count variant) ...), to target, w ×
  ;; h, cleared to opaque black, or to transparent if clear?. A run that
  ;; shows a list draws the list's runs, from its buffers, where the run
  ;; puts it and inside its clip.
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
        ;; set as floats only when they change: each set makes a float
        (unless (and (eqv? w gpu-drawn-w) (eqv? h gpu-drawn-h))
          (set! gpu-drawn-w w)
          (set! gpu-drawn-h h)
          (ftype-set! gpu-frame-uniforms (w) uniforms (fixnum->flonum w))
          (ftype-set! gpu-frame-uniforms (h) uniforms (fixnum->flonum h)))
        (ftype-set! gpu-sampler-bindings (0 texture) samplers
                    (renderer-atlas r))
        (ftype-set! gpu-sampler-bindings (0 sampler) samplers
                    (renderer-sampler r))
        (ftype-set! gpu-sampler-bindings (1 sampler) samplers
                    (renderer-sampler r))
        (gpu-draw-list! r cb pass (gpu-pipelines-for format) format runs
                        (renderer-records r) (renderer-extras r) 0 0 0 0 w h)
        (sdl-end-render-pass pass))))

  ;; The size of the target the uniforms hold.
  (define-state gpu-drawn-w #f)
  (define-state gpu-drawn-h #f)

  ;; Binds a list's buffers, where it is and its lengths, for the runs that
  ;; come next.
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

  ;; Cuts what is drawn next to x0 y0 x1 y1, in the target's pixels.
  (define (gpu-scissor! pass x0 y0 x1 y1)
    (let ([box gpu-scissor*])
      (ftype-set! gpu-scissor (x) box x0)
      (ftype-set! gpu-scissor (y) box y0)
      (ftype-set! gpu-scissor (w) box (max 0 (- x1 x0)))
      (ftype-set! gpu-scissor (h) box (max 0 (- y1 y0)))
      (sdl-set-gpu-scissor pass (gpu-at box))))

  ;; Draws a list's runs, from its buffers, at (ox, oy) on the target,
  ;; inside x0 y0 x1 y1. A list it shows is drawn inside that and its own
  ;; clip, and after it this list's state is bound again.
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
                  (when (and (> count 0) (gpu-run-drawable? run))
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

  ;; Draws a paint's run: binds its pipeline, the list's buffers and then
  ;; its own, and pushes its uniforms, with where the list is written first
  ;; and the list's lengths first among its buffers' lengths.
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

  ;; The ways a window may present, by SDL's numbers.
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

  ;; How this window presents, and how it was last asked to.
  (define-state *gpu-present-mode* 'vsync)
  (define-state *gpu-present-asked* 'vsync)

  ;;; ------------------------------------------------------------------ facts
  ;;; What core0 reports about itself, for the world to read
  ;;; (.work/gpu-design.md 9.12): an alist the world never changes, made
  ;;; again at the end of a frame only when what it is made from has
  ;;; changed, so that a frame like the last one allocates nothing. What
  ;;; became of each frame is in its report ((schevana core0 present)).

  (define-state *gpu-facts* '())

  ;; What the facts were made from: the capacities of the records',
  ;; extras', glyphs' and transfer buffers, the target's size, and whether
  ;; there is a window; and the present mode.
  (define-state *gpu-facts-of* (make-fxvector 7 -1))
  (define-state *gpu-facts-mode* #f)

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
            (frames-in-flight . ,*gpu-frames-in-flight*)
            (objects
             (records buffer . ,(cdr (renderer-records r)))
             (extras buffer . ,(cdr (renderer-extras r)))
             (glyphs buffer . ,(cdr (renderer-glyphs r)))
             (atlas texture . ,(* gpu-atlas-side gpu-atlas-side))
             (transfer buffer . ,(cdr (renderer-transfer r)))
             (target texture
                     . ,(* 4 (renderer-target-w r) (renderer-target-h r)))))))))

  ;; Makes sdl-window the window this renderer draws to from now on. The
  ;; count of frames in flight is set first, since setting it on a claimed
  ;; window builds the swapchain again.
  (define (gpu-claim-window! sdl-window)
    (sdl-set-frames-in-flight (renderer-device *renderer*)
                              *gpu-frames-in-flight*)
    (unless (sdl-claim-window (renderer-device *renderer*) sdl-window)
      (errorf 'gpu-claim-window! "~a" (sdl-get-error)))
    (set! *gpu-present-mode* 'vsync)   ; as a claim leaves it
    (set! *gpu-present-asked* 'vsync)
    (renderer-sdl-window-set! *renderer* sdl-window)
    (gpu-facts-refresh!))

  ;; Between frames: the window presents by mode from now on. A mode the
  ;; window doesn't offer leaves it as it is, and is asked about only once
  ;; per change, so a choice saved on another machine costs this one's
  ;; frames nothing.
  (define (gpu-present-mode! mode)
    (unless (eq? mode *gpu-present-asked*)
      (set! *gpu-present-asked* mode)
      (let ([r *renderer*])
        (when (and (memq mode (gpu-present-modes))
                   (sdl-set-swapchain-parameters
                    (renderer-device r) (renderer-sdl-window r)
                    gpu-composition-sdr (cdr (assq mode gpu-present-codes))))
          (set! *gpu-present-mode* mode)
          (core0-trace! 30 (cdr (assq mode gpu-present-codes)))))))

  ;; Between frames: n frames in flight from now on, 1 to 3, as SDL
  ;; allows, and the swapchain is built again. Any other count is ignored.
  (define (gpu-frames-in-flight! n)
    (when (and (fixnum? n) (fx<= 1 n 3) (not (fx= n *gpu-frames-in-flight*))
               (sdl-set-frames-in-flight (renderer-device *renderer*) n))
      (set! *gpu-frames-in-flight* n)
      (set! *gpu-facts-mode* #f)))       ; the facts say so at the next look

  ;;; ------------------------------------------------------------------ frames
  ;;; A frame as core1 hands it to core0, which reads nothing else of
  ;;; core1's (.work/gpu-design.md 9.5): the root's recording and the
  ;;; frame's number, which the recorder sets ((schevana recorder bytes));
  ;;; the glyph table if it changed; the atlas's new pieces; the jobs, the
  ;;; writes and the compute runs asked for since the last frame; the
  ;;; present mode; the frames in flight; and lists kept from earlier to
  ;;; draw on images first, each (image . recording), the recorder's copies;
  ;;; and which of core0's wakes core1 asks for with it, a list of taken
  ;;; (as core0 takes it), done (as its GPU work is seen done) and back (as
  ;;; core0 gives it back, where it reached the screen; one that didn't
  ;;; always wakes core1). It comes back with whether it reached the
  ;;; screen. The same few records
  ;;; go back and forth, filled again for each frame, so a frame allocates
  ;;; none. Each one goes back, and waits to be filled again, on a chain by
  ;;; its own link (next), which whoever holds it sets.

  (define-record-type gpu-frame
    (nongenerative schevana-gpu-frame-9)
    (fields (mutable root) (mutable number) (mutable table) (mutable table-n)
            (mutable pieces) (mutable jobs) (mutable writes) (mutable computes)
            (mutable mode) (mutable in-flight) (mutable earlier)
            (mutable shown?) (mutable next) (mutable wakes)))

  ;; A frame to fill: core1 keeps those given back to fill again.
  (define (gpu-frame-make)
    (make-gpu-frame #f 0 #f 0 '() '() #f '() #f 3 '() #f #f '(taken back)))

  ;; The number of the last frame core0 gave back: what core0 read of the
  ;; recorder's for it is free to write again once a later frame doesn't
  ;; show it.
  (define-state *gpu-frame-back* 0)

  ;; The frame core1 published, until core0 takes it, or else #f; and the
  ;; newest of the frames core0 gave back since core1 last took them,
  ;; linked to the older ones, or else #f.
  (define-state *gpu-published* (box #f))
  (define-state *gpu-given-back* (box #f))

  ;; Core1's side: publishes f for the screen and wakes core0. One frame
  ;; waits at a time: core1 publishes again once core0 has taken it
  ;; (gpu-frame-waiting?).
  (define (gpu-publish! f)
    (memory-order-release)
    (let loop ()
      (cond [(unbox *gpu-published*)
             (errorf 'gpu-publish! "the frame published last waits for core0 \
                                    still")]
            [(not (box-cas! *gpu-published* #f f)) (loop)]))
    (core0-wake!))

  (define (gpu-frame-waiting?) (and (unbox *gpu-published*) #t))

  ;; Core0's side: gives f back, by its own link.
  (define (gpu-give-back! f)
    (memory-order-release)
    (let loop ()
      (let ([newest (unbox *gpu-given-back*)])
        (gpu-frame-next-set! f newest)
        (unless (box-cas! *gpu-given-back* newest f) (loop)))))

  ;; Core1's side: takes the frames core0 gave back since core1 last took
  ;; them. Returns the newest, linked to the older ones (gpu-frame-next), or
  ;; #f.
  (define (gpu-frames-back!)
    (let loop ()
      (let ([newest (unbox *gpu-given-back*)])
        (cond [(not newest) #f]
              [(box-cas! *gpu-given-back* newest #f)
               (memory-order-acquire)
               newest]
              [else (loop)]))))

  ;; Runs core1's jobs and writes, draws the lists kept from earlier on
  ;; their images, then the frame. Returns #t if the frame reached the
  ;; screen, or #f if the window had no room for it yet and it should be
  ;; tried again.
  (define (gpu-present! f)
    (gpu-run-jobs! (gpu-frame-jobs f) (gpu-frame-writes f))
    (gpu-present-mode! (gpu-frame-mode f))
    (gpu-frames-in-flight! (gpu-frame-in-flight f))
    (let loop ([earlier (gpu-frame-earlier f)])
      (if (pair? earlier)
          (begin
            ;; core1 may ask for a list on an image and release the image
            ;; before the frame goes (a Pipeline closed): the release ran
            ;; with the jobs above, so the list is skipped
            (when (gpu-object-made? (gpu-image-id (caar earlier)))
              (gpu-list-on-image! (caar earlier) (cdar earlier)))
            (loop (cdr earlier)))
          (let ([shown? (gpu-frame! f)])
            ;; read and gone up: what it read is given back
            (memory-order-release)
            (set! *gpu-frame-back* (gpu-frame-number f))
            (gpu-facts-refresh!)
            shown?))))

  ;; With no window, core0 on a thread of its own holds each frame until
  ;; the next refresh of a screen of its own, at the window's rate, as a
  ;; screen holds the acquire. Its refreshes fall on whole periods of
  ;; core0-clock-ns's clock. It sleeps on core0's own time record, set
  ;; again, so nothing is allocated.
  (define (gpu-headless-hold!)
    (let ([p (core0-frame-ns)] [t *core0-time*])
      (set-time-second! t 0)
      (set-time-nanosecond! t (fx- p (fxmodulo (core0-clock-ns) p)))
      (sleep t)))

  ;; Where the acquire writes the image it gives and its size, kept.
  (define-made gpu-swapchain-texture
    (ftype-pointer-address
     (ftype-&ref gpu-swapchain-out (texture) gpu-swapchain-out*)))
  (define-made gpu-swapchain-w
    (ftype-pointer-address
     (ftype-&ref gpu-swapchain-out (w) gpu-swapchain-out*)))
  (define-made gpu-swapchain-h
    (ftype-pointer-address
     (ftype-&ref gpu-swapchain-out (h) gpu-swapchain-out*)))

  ;; Draws one frame: the uploads, then the runs, to the window or the
  ;; target. Returns #t if it reached the screen, or #f if the window had no
  ;; room for it yet (a frame still in flight, or the window is hidden).
  (define (gpu-frame! f)
    (let* ([r *renderer*]
           [root (gpu-frame-root f)]
           [runs (gpu-recording-runs root)]
           [cb (gpu-must 'gpu-frame!
                         (sdl-acquire-gpu-commands (renderer-device r)))])
      (gpu-upload! r cb (gpu-recording-recs root) (gpu-recording-recs-n root)
                   (gpu-recording-extras root) (gpu-recording-extras-n root)
                   (gpu-frame-table f) (gpu-frame-table-n f)
                   (gpu-frame-pieces f) runs)
      (gpu-run-computes! cb (gpu-frame-computes f))
      (if (eqv? 0 (renderer-sdl-window r))
          (begin
            (when *core0-forked* (gpu-headless-hold!))
            (gpu-draw-runs! r cb (renderer-target r) gpu-format-bgra8
                            (renderer-target-w r) (renderer-target-h r) runs #f)
            ;; a row as a screen's frame has, its GPU work taken as done as
            ;; it goes back: no report ever comes for it
            (present-sent! (gpu-frame-number f))
            ;; no screen paces these, and frames sent faster than they're drawn
            ;; would pile up without end: one waits behind the one being drawn
            (let ([fence (gpu-must 'gpu-frame! (sdl-submit-gpu-fence cb))])
              (when (renderer-fence r) (gpu-wait! (renderer-fence r)))
              (renderer-fence-set! r fence))
            (present-done! (gpu-frame-number f))
            #t)
          ;; the driver may hold either end of this until the screen is ready
          (let* ([out gpu-swapchain-out*]
                 [shown?
                  (let ([ok (begin
                              (core0-trace! 3 (gpu-frame-number f))
                              (present-acquiring!)
                              (sdl-acquire-swapchain
                               cb (renderer-sdl-window r) gpu-swapchain-texture
                               gpu-swapchain-w gpu-swapchain-h))])
                    (present-acquired!)
                    (core0-trace! 4 (if ok 1 0))
                    (and ok
                         (not (eqv? 0 (ftype-ref gpu-swapchain-out (texture)
                                                 out)))))])
            (when shown?
              (gpu-draw-runs! r cb (ftype-ref gpu-swapchain-out (texture) out)
                              (sdl-swapchain-format (renderer-device r)
                                                    (renderer-sdl-window r))
                              (ftype-ref gpu-swapchain-out (w) out)
                              (ftype-ref gpu-swapchain-out (h) out)
                              runs #f))
            ;; the screen is asked to report on it before the submit presents it
            (when shown?
              (present-sent! (gpu-frame-number f))
              (platform-report-ask! (gpu-frame-number f)))
            (present-submitting!)
            (present-fence! (gpu-frame-number f)
                            (gpu-must 'gpu-frame! (sdl-submit-gpu-fence cb)))
            (when shown?
              (present-submitted! (gpu-frame-number f) core0-look-ns))
            (core0-trace! 5 (gpu-frame-number f))
            shown?))))

  ;; Draws a list kept from earlier on image, ahead of the next frame, which
  ;; sends its own glyph table and atlas pieces: the list's glyphs are all
  ;; up already. Its images and paints show what they hold now, except those
  ;; released since.
  (define (gpu-list-on-image! image rec)
    (let* ([r *renderer*]
           [d (renderer-device r)]
           [runs (gpu-recording-runs rec)]
           [cb (gpu-must 'gpu-list-on-image! (sdl-acquire-gpu-commands d))])
      (gpu-upload! r cb (gpu-recording-recs rec) (gpu-recording-recs-n rec)
                   (gpu-recording-extras rec) (gpu-recording-extras-n rec) #f 0
                   '() runs)
      (gpu-draw-runs! r cb (gpu-image-texture image) gpu-format-bgra8
                      (gpu-image-w image) (gpu-image-h image)
                      (filter gpu-run-drawable? runs) #f)
      (gpu-image-fill-levels! cb image)
      (sdl-submit-gpu cb)))

  ;; The same, drawn to a new texture w × h and read back. Returns its
  ;; pixels, row after row, in premultiplied BGRA: what screenshots and icons
  ;; see. jobs, writes and computes, which core1 asked of the GPU since, go
  ;; first.
  (define (gpu-drawing->bytes jobs writes computes recs recs-n extras extras-n
                             table table-n atlas-pieces runs w h clear?)
    (gpu-run-jobs! jobs writes)
    (let* ([r *renderer*]
           [d (renderer-device r)]
           [texture (gpu-make-texture d gpu-format-bgra8 gpu-usage-target w h)]
           [cb (gpu-must 'gpu-drawing->bytes (sdl-acquire-gpu-commands d))])
      (gpu-upload! r cb recs recs-n extras extras-n table table-n atlas-pieces
                   runs)
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
      (sdl-release-gpu-fence d fence))))
