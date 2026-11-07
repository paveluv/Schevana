;;; ffi.ss — the only place where Schevana talks to C.
;;;
;;; SDL3 gives us a host window, input events, a clipboard and the GPU.
;;; FreeType gives us glyphs, and fontconfig the files that hold them.
;;; Everything above this file is plain Scheme, and only the core (src/)
;;; uses these bindings: the folders draw, measure and save through the
;;; core's procedures (tests/sources.ss checks it).

(define (load-first-library names)
  (let loop ([ns names])
    (cond
      [(null? ns) (errorf 'load-first-library "could not load any of ~s" names)]
      [(guard (c [#t #f]) (load-shared-object (car ns)) #t) (car ns)]
      [else (loop (cdr ns))])))

(define sdl-library-names
  '("libSDL3.so.0" "libSDL3.so" "libSDL3.0.dylib" "libSDL3.dylib" "SDL3.dll"))

;; A process loads one SDL for good, so a session that started with another
;; (SDL2, before the switch) cannot reload into this one.
(when (and (top-level-bound? 'libsdl) (not (member libsdl sdl-library-names)))
  (errorf 'reload! "this session runs ~a; quit and start Schevana again"
          libsdl))

(define libsdl (load-first-library sdl-library-names))

(define libfreetype
  (load-first-library
   '("libfreetype.so.6" "libfreetype.so" "libfreetype.6.dylib"
     "libfreetype.dylib" "freetype.dll")))

(define libfontconfig
  (load-first-library
   '("libfontconfig.so.1" "libfontconfig.so" "libfontconfig.1.dylib"
     "libfontconfig.dylib" "fontconfig.dll")))

;; The C library's sockets come with what's loaded: only src/host.ss uses them,
;; and it declares them below, after the macro.

;; Like foreign-procedure, but `double` arguments accept any real number,
;; and `bool` is C's one-byte bool (SDL3's) as #t or #f: Chez's boolean is
;; an int, whose upper bytes a C bool leaves undefined. Only the main
;; thread calls them: workers run worklets, which cannot name them.
;; collect-safe: a call that blocks, given foreign memory only, during
;; which a collection another thread needs does not wait for it.
(define-syntax define-foreign-as
  (lambda (x)
    (define (is? t name) (eq? (syntax->datum t) name))
    (define (c-type t) (if (is? t 'bool) #'unsigned-8 t))
    (syntax-case x ()
      [(_ how name cname (type ...) ret)
       (with-syntax ([(arg ...) (generate-temporaries #'(type ...))])
         (with-syntax ([(conv ...)
                        (map (lambda (t a)
                               (cond [(is? t 'double) #`(inexact #,a)]
                                     [(is? t 'bool) #`(if #,a 1 0)]
                                     [else a]))
                             #'(type ...) #'(arg ...))]
                       [(ctype ...) (map c-type #'(type ...))]
                       [cret (c-type #'ret)])
           #`(define name
               (let ([f #,(if (is? #'how 'collect-safe)
                              #'(foreign-procedure __collect_safe cname
                                                   (ctype ...) cret)
                              #'(foreign-procedure cname (ctype ...) cret))])
                 (lambda (arg ...)
                   #,(if (is? #'ret 'bool)
                         #'(not (fx= 0 (f conv ...)))
                         #'(f conv ...)))))))])))

(define-syntax define-foreign
  (syntax-rules () [(_ . spec) (define-foreign-as plain . spec)]))
(define-syntax define-foreign/collect-safe
  (syntax-rules () [(_ . spec) (define-foreign-as collect-safe . spec)]))

(define-foreign c-socket "socket" (int int int) int)
(define-foreign c-bind "bind" (int uptr unsigned-32) int)
(define-foreign c-listen "listen" (int int) int)
(define-foreign c-accept "accept" (int uptr uptr) int)
(define-foreign c-connect "connect" (int uptr unsigned-32) int)
(define-foreign c-shutdown "shutdown" (int int) int)
(define-foreign c-recv "recv" (int u8* size_t int) ssize_t)
(define-foreign c-send "send" (int u8* size_t int) ssize_t)
(define-foreign c-close "close" (int) int)
(define-foreign c-poll "poll" (uptr unsigned-long int) int)
(define-foreign c-signal "signal" (int uptr) uptr)

(define (c-string->string ptr)
  (if (= ptr 0)
      ""
      (let ([n (let loop ([i 0])
                 (if (= 0 (foreign-ref 'unsigned-8 ptr i)) i (loop (+ i 1))))])
        (let ([bv (make-bytevector n)])
          (do ([i 0 (+ i 1)]) ((= i n))
            (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 ptr i)))
          (utf8->string bv)))))

;;; ------------------------------------------------------------------ SDL3

(define SDL_INIT_VIDEO #x20)
(define SDL_WINDOW_FULLSCREEN #x1)
(define SDL_WINDOW_HIDDEN #x8)
(define SDL_WINDOW_RESIZABLE #x20)
(define SDL_WINDOW_HIGH_PIXEL_DENSITY #x2000)
(define SDL_WINDOWPOS_CENTERED #x2FFF0000)
(define SDL_PIXELFORMAT_ARGB8888 #x16362004)

(define SDL_EVENT_QUIT #x100)
(define SDL_EVENT_WINDOW_EXPOSED #x204)
(define SDL_EVENT_WINDOW_RESIZED #x206)
(define SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED #x207)
(define SDL_EVENT_WINDOW_MOUSE_LEAVE #x20D)
(define SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED #x214)
(define SDL_EVENT_KEY_DOWN #x300)
(define SDL_EVENT_TEXT_INPUT #x303)
(define SDL_EVENT_MOUSE_MOTION #x400)
(define SDL_EVENT_MOUSE_BUTTON_DOWN #x401)
(define SDL_EVENT_MOUSE_BUTTON_UP #x402)
(define SDL_EVENT_MOUSE_WHEEL #x403)

(define-foreign sdl-init "SDL_Init" (unsigned-32) bool)
(define-foreign sdl-quit "SDL_Quit" () void)
(define-foreign sdl-get-error "SDL_GetError" () string)
(define-foreign sdl-get-ticks-ns "SDL_GetTicksNS" () unsigned-64)
(define-foreign sdl-get-num-logical-cpu-cores "SDL_GetNumLogicalCPUCores" ()
  int)
(define-foreign sdl-set-hint "SDL_SetHint" (string string) bool)
(define-foreign sdl-create-window "SDL_CreateWindow"
  (string int int unsigned-64) uptr)
(define-foreign sdl-destroy-window "SDL_DestroyWindow" (uptr) void)
(define-foreign sdl-set-window-minimum-size "SDL_SetWindowMinimumSize"
  (uptr int int) bool)
(define-foreign sdl-set-window-size "SDL_SetWindowSize" (uptr int int) bool)
(define-foreign sdl-set-window-position "SDL_SetWindowPosition"
  (uptr int int) bool)
(define-foreign sdl-show-window "SDL_ShowWindow" (uptr) bool)
(define-foreign sdl-get-window-size "SDL_GetWindowSize" (uptr uptr uptr) bool)
(define-foreign sdl-get-window-display-scale "SDL_GetWindowDisplayScale"
  (uptr) float)
(define-foreign sdl-get-window-size-in-pixels "SDL_GetWindowSizeInPixels"
  (uptr uptr uptr) bool)
(define-foreign sdl-get-display-for-window "SDL_GetDisplayForWindow"
  (uptr) unsigned-32)
(define-foreign sdl-get-current-display-mode "SDL_GetCurrentDisplayMode"
  (unsigned-32) uptr)
(define-foreign sdl-poll-event "SDL_PollEvent" (uptr) bool)
(define-foreign/collect-safe sdl-wait-event-timeout "SDL_WaitEventTimeout"
  (uptr int) bool)
(define-foreign sdl-start-text-input "SDL_StartTextInput" (uptr) bool)
(define-foreign sdl-get-clipboard-text "SDL_GetClipboardText" () uptr)
(define-foreign sdl-set-clipboard-text "SDL_SetClipboardText" (string) bool)
(define-foreign sdl-free "SDL_free" (uptr) void)
(define-foreign sdl-create-system-cursor "SDL_CreateSystemCursor" (int) uptr)
(define-foreign sdl-set-cursor "SDL_SetCursor" (uptr) bool)
(define-foreign sdl-set-window-fullscreen "SDL_SetWindowFullscreen"
  (uptr bool) bool)
(define-foreign sdl-get-window-flags "SDL_GetWindowFlags" (uptr) unsigned-64)
(define-foreign sdl-create-surface-from "SDL_CreateSurfaceFrom"
  (int int unsigned-32 uptr int) uptr)
(define-foreign sdl-destroy-surface "SDL_DestroySurface" (uptr) void)
(define-foreign sdl-set-window-icon "SDL_SetWindowIcon" (uptr uptr) bool)
(define-foreign sdl-memcpy "SDL_memcpy" (uptr uptr size_t) uptr)

;;; ------------------------------------------------------------------ SDL GPU
;;; Only src/gpu.ss uses these: above it no SDL name for the GPU appears.

(define-foreign sdl-create-gpu-device "SDL_CreateGPUDevice"
  (unsigned-32 bool uptr) uptr)
(define-foreign sdl-claim-window "SDL_ClaimWindowForGPUDevice"
  (uptr uptr) bool)
(define-foreign sdl-release-window "SDL_ReleaseWindowFromGPUDevice"
  (uptr uptr) void)
(define-foreign sdl-swapchain-format "SDL_GetGPUSwapchainTextureFormat"
  (uptr uptr) int)
(define-foreign sdl-create-gpu-shader "SDL_CreateGPUShader" (uptr uptr) uptr)
(define-foreign sdl-release-gpu-shader "SDL_ReleaseGPUShader"
  (uptr uptr) void)
(define-foreign sdl-create-gpu-pipeline "SDL_CreateGPUGraphicsPipeline"
  (uptr uptr) uptr)
(define-foreign sdl-release-gpu-pipeline "SDL_ReleaseGPUGraphicsPipeline"
  (uptr uptr) void)
(define-foreign sdl-create-gpu-compute "SDL_CreateGPUComputePipeline"
  (uptr uptr) uptr)
(define-foreign sdl-release-gpu-compute "SDL_ReleaseGPUComputePipeline"
  (uptr uptr) void)
(define-foreign sdl-create-gpu-buffer "SDL_CreateGPUBuffer" (uptr uptr) uptr)
(define-foreign sdl-release-gpu-buffer "SDL_ReleaseGPUBuffer"
  (uptr uptr) void)
(define-foreign sdl-create-gpu-texture "SDL_CreateGPUTexture" (uptr uptr) uptr)
(define-foreign sdl-release-gpu-texture "SDL_ReleaseGPUTexture"
  (uptr uptr) void)
(define-foreign sdl-create-gpu-sampler "SDL_CreateGPUSampler" (uptr uptr) uptr)
(define-foreign sdl-create-gpu-transfer "SDL_CreateGPUTransferBuffer"
  (uptr uptr) uptr)
(define-foreign sdl-release-gpu-transfer "SDL_ReleaseGPUTransferBuffer"
  (uptr uptr) void)
(define-foreign sdl-map-gpu-transfer "SDL_MapGPUTransferBuffer"
  (uptr uptr bool) uptr)
(define-foreign sdl-unmap-gpu-transfer "SDL_UnmapGPUTransferBuffer"
  (uptr uptr) void)
(define-foreign sdl-acquire-gpu-commands "SDL_AcquireGPUCommandBuffer"
  (uptr) uptr)
(define-foreign sdl-acquire-swapchain "SDL_AcquireGPUSwapchainTexture"
  (uptr uptr uptr uptr uptr) bool)
(define-foreign sdl-begin-copy-pass "SDL_BeginGPUCopyPass" (uptr) uptr)
(define-foreign sdl-end-copy-pass "SDL_EndGPUCopyPass" (uptr) void)
(define-foreign sdl-upload-to-buffer "SDL_UploadToGPUBuffer"
  (uptr uptr uptr bool) void)
(define-foreign sdl-upload-to-texture "SDL_UploadToGPUTexture"
  (uptr uptr uptr bool) void)
(define-foreign sdl-download-from-buffer "SDL_DownloadFromGPUBuffer"
  (uptr uptr uptr) void)
(define-foreign sdl-download-from-texture "SDL_DownloadFromGPUTexture"
  (uptr uptr uptr) void)
(define-foreign sdl-begin-render-pass "SDL_BeginGPURenderPass"
  (uptr uptr unsigned-32 uptr) uptr)
(define-foreign sdl-end-render-pass "SDL_EndGPURenderPass" (uptr) void)
(define-foreign sdl-bind-gpu-pipeline "SDL_BindGPUGraphicsPipeline"
  (uptr uptr) void)
(define-foreign sdl-bind-vertex-storage "SDL_BindGPUVertexStorageBuffers"
  (uptr unsigned-32 uptr unsigned-32) void)
(define-foreign sdl-bind-fragment-storage "SDL_BindGPUFragmentStorageBuffers"
  (uptr unsigned-32 uptr unsigned-32) void)
(define-foreign sdl-bind-fragment-samplers "SDL_BindGPUFragmentSamplers"
  (uptr unsigned-32 uptr unsigned-32) void)
(define-foreign sdl-push-vertex-uniform "SDL_PushGPUVertexUniformData"
  (uptr unsigned-32 uptr unsigned-32) void)
(define-foreign sdl-draw-primitives "SDL_DrawGPUPrimitives"
  (uptr unsigned-32 unsigned-32 unsigned-32 unsigned-32) void)
(define-foreign sdl-push-fragment-uniform "SDL_PushGPUFragmentUniformData"
  (uptr unsigned-32 u8* unsigned-32) void)
(define-foreign sdl-begin-compute-pass "SDL_BeginGPUComputePass"
  (uptr uptr unsigned-32 uptr unsigned-32) uptr)
(define-foreign sdl-end-compute-pass "SDL_EndGPUComputePass" (uptr) void)
(define-foreign sdl-bind-compute-pipeline "SDL_BindGPUComputePipeline"
  (uptr uptr) void)
(define-foreign sdl-bind-compute-storage "SDL_BindGPUComputeStorageBuffers"
  (uptr unsigned-32 uptr unsigned-32) void)
(define-foreign sdl-push-compute-uniform "SDL_PushGPUComputeUniformData"
  (uptr unsigned-32 u8* unsigned-32) void)
(define-foreign sdl-dispatch-compute "SDL_DispatchGPUCompute"
  (uptr unsigned-32 unsigned-32 unsigned-32) void)
(define-foreign sdl-submit-gpu-fence
  "SDL_SubmitGPUCommandBufferAndAcquireFence" (uptr) uptr)
(define-foreign/collect-safe sdl-wait-gpu-fences "SDL_WaitForGPUFences"
  (uptr bool uptr unsigned-32) bool)
(define-foreign sdl-query-gpu-fence "SDL_QueryGPUFence" (uptr uptr) bool)
(define-foreign sdl-release-gpu-fence "SDL_ReleaseGPUFence" (uptr uptr) void)
(define-foreign sdl-gpu-driver "SDL_GetGPUDeviceDriver" (uptr) string)
(define-foreign sdl-window-supports-present-mode
  "SDL_WindowSupportsGPUPresentMode" (uptr uptr int) bool)
(define-foreign/collect-safe sdl-wait-gpu-idle "SDL_WaitForGPUIdle" (uptr) bool)
(define gpu-copy-in (foreign-procedure "SDL_memcpy" (uptr u8* size_t) uptr))
(define gpu-copy-out (foreign-procedure "SDL_memcpy" (u8* uptr size_t) uptr))

;;; ------------------------------------------------------------------ FreeType

(define-foreign ft-init-freetype "FT_Init_FreeType" (uptr) int)
(define-foreign ft-new-face "FT_New_Face" (uptr string long uptr) int)
(define-foreign ft-set-char-size "FT_Set_Char_Size"
  (uptr long long unsigned unsigned) int)
(define-foreign ft-set-transform "FT_Set_Transform" (uptr uptr uptr) void)
(define-foreign ft-load-char "FT_Load_Char" (uptr unsigned-long int) int)
(define-foreign ft-get-first-char "FT_Get_First_Char"
  (uptr uptr) unsigned-long)
(define-foreign ft-get-next-char "FT_Get_Next_Char"
  (uptr unsigned-long uptr) unsigned-long)

;;; ----------------------------------------------------------------- fontconfig

(define-foreign fc-config-get-current "FcConfigGetCurrent" () uptr)
(define-foreign fc-name-parse "FcNameParse" (string) uptr)
(define-foreign fc-config-substitute "FcConfigSubstitute"
  (uptr uptr int) int)
(define-foreign fc-default-substitute "FcDefaultSubstitute" (uptr) void)
(define-foreign fc-font-match "FcFontMatch" (uptr uptr uptr) uptr)
(define-foreign fc-pattern-get-string "FcPatternGetString"
  (uptr string int uptr) int)
(define-foreign fc-pattern-get-integer "FcPatternGetInteger"
  (uptr string int uptr) int)
(define-foreign fc-pattern-destroy "FcPatternDestroy" (uptr) void)
