;;; host/sdl.ss — SDL's bindings, core0's alone (.work/gpu-design.md 9.5):
;;; the window, its events, and the GPU. Main names none of them
;;; (tests/sources.ss) but the two any thread may call, in src/ffi.ss.

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
(define-foreign sdl-set-hint "SDL_SetHint" (string string) bool)
(define-foreign sdl-create-window "SDL_CreateWindow"
  (string int int unsigned-64) uptr)
;; Collect-safe, as is what may size, show or let go of the window's Metal
;; layer once it has run: Core Animation may hold the layer's lock running
;; a presented handler of core0's, which may wait for a collection
;; (src/host/platform.ss).
(define-foreign/collect-safe sdl-destroy-window "SDL_DestroyWindow" (uptr)
  void)
(define-foreign/collect-safe sdl-set-window-minimum-size
  "SDL_SetWindowMinimumSize" (uptr int int) bool)
(define-foreign/collect-safe sdl-set-window-size "SDL_SetWindowSize"
  (uptr int int) bool)
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
(define-foreign/collect-safe sdl-poll-event "SDL_PollEvent" (uptr) bool)
(define-foreign sdl-start-text-input "SDL_StartTextInput" (uptr) bool)
(define-foreign sdl-get-clipboard-text "SDL_GetClipboardText" () uptr)
(define-foreign sdl-set-clipboard-text "SDL_SetClipboardText" (string) bool)
(define-foreign sdl-free "SDL_free" (uptr) void)
(define-foreign sdl-create-system-cursor "SDL_CreateSystemCursor" (int) uptr)
(define-foreign sdl-set-cursor "SDL_SetCursor" (uptr) bool)
(define-foreign/collect-safe sdl-set-window-fullscreen
  "SDL_SetWindowFullscreen" (uptr bool) bool)
(define-foreign sdl-get-window-flags "SDL_GetWindowFlags" (uptr) unsigned-64)
(define-foreign sdl-create-surface-from "SDL_CreateSurfaceFrom"
  (int int unsigned-32 uptr int) uptr)
(define-foreign sdl-destroy-surface "SDL_DestroySurface" (uptr) void)
(define-foreign sdl-set-window-icon "SDL_SetWindowIcon" (uptr uptr) bool)
(define-foreign sdl-memcpy "SDL_memcpy" (uptr uptr size_t) uptr)
(define-foreign sdl-memset "SDL_memset" (uptr int size_t) uptr)

;;; ------------------------------------------------------------------ SDL GPU
;;; Only src/gpu.ss uses these: above it no SDL name for the GPU appears.

(define-foreign sdl-create-gpu-device "SDL_CreateGPUDevice"
  (unsigned-32 bool uptr) uptr)
(define-foreign sdl-claim-window "SDL_ClaimWindowForGPUDevice"
  (uptr uptr) bool)
(define-foreign/collect-safe sdl-release-window
  "SDL_ReleaseWindowFromGPUDevice" (uptr uptr) void)
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
;; The screen holds it as long as it likes: collect-safe, as every call
;; that may block is (tests/sources.ss).
(define-foreign/collect-safe sdl-acquire-swapchain
  "SDL_AcquireGPUSwapchainTexture" (uptr uptr uptr uptr uptr) bool)
(define-foreign sdl-begin-copy-pass "SDL_BeginGPUCopyPass" (uptr) uptr)
(define-foreign sdl-blit-gpu-texture "SDL_BlitGPUTexture" (uptr uptr) void)
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
(define-foreign sdl-set-gpu-scissor "SDL_SetGPUScissor" (uptr uptr) void)
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
(define-foreign sdl-generate-gpu-mipmaps "SDL_GenerateMipmapsForGPUTexture"
  (uptr uptr) void)
(define-foreign/collect-safe sdl-submit-gpu "SDL_SubmitGPUCommandBuffer"
  (uptr) bool)
(define-foreign/collect-safe sdl-submit-gpu-fence
  "SDL_SubmitGPUCommandBufferAndAcquireFence" (uptr) uptr)
(define-foreign/collect-safe sdl-wait-gpu-fences "SDL_WaitForGPUFences"
  (uptr bool uptr unsigned-32) bool)
(define-foreign sdl-query-gpu-fence "SDL_QueryGPUFence" (uptr uptr) bool)
(define-foreign sdl-release-gpu-fence "SDL_ReleaseGPUFence" (uptr uptr) void)
;; a window's properties: its Wayland display and surface, or its Cocoa
;; window and the tag of the view SDL draws to, for their reports
(define-foreign sdl-get-window-properties "SDL_GetWindowProperties" (uptr)
  unsigned-32)
(define-foreign sdl-get-pointer-property "SDL_GetPointerProperty"
  (unsigned-32 string uptr) uptr)
(define-foreign sdl-get-number-property "SDL_GetNumberProperty"
  (unsigned-32 string integer-64) integer-64)
(define-foreign sdl-gpu-driver "SDL_GetGPUDeviceDriver" (uptr) string)
;; what the host is: SDL's version, its video driver (#f before its start)
(define-foreign sdl-get-version "SDL_GetVersion" () int)
(define-foreign sdl-get-current-video-driver "SDL_GetCurrentVideoDriver" ()
  string)
(define-foreign sdl-get-string-property "SDL_GetStringProperty"
  (unsigned-32 string string) string)
(define-foreign sdl-window-supports-present-mode
  "SDL_WindowSupportsGPUPresentMode" (uptr uptr int) bool)
(define-foreign/collect-safe sdl-set-frames-in-flight
  "SDL_SetGPUAllowedFramesInFlight" (uptr unsigned-32) bool)
(define-foreign/collect-safe sdl-set-swapchain-parameters
  "SDL_SetGPUSwapchainParameters" (uptr uptr int int) bool)
(define-foreign/collect-safe sdl-wait-gpu-idle "SDL_WaitForGPUIdle" (uptr) bool)
(define gpu-copy-in (foreign-procedure "SDL_memcpy" (uptr u8* size_t) uptr))
(define gpu-copy-out (foreign-procedure "SDL_memcpy" (u8* uptr size_t) uptr))
