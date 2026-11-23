;;; (schevana sdl gpu) — SDL3's bindings for the GPU, and for the plain
;;; memory handed to it. Only core0 uses these, (schevana core0 gpu) almost
;;; alone: above core0, no SDL name for the GPU appears.

(library (schevana sdl gpu)
  (export
    sdl-memcpy sdl-create-gpu-device sdl-claim-window sdl-release-window
    sdl-swapchain-format sdl-create-gpu-shader sdl-release-gpu-shader
    sdl-create-gpu-pipeline sdl-release-gpu-pipeline sdl-create-gpu-compute
    sdl-release-gpu-compute sdl-create-gpu-buffer sdl-release-gpu-buffer
    sdl-create-gpu-texture sdl-release-gpu-texture sdl-create-gpu-sampler
    sdl-create-gpu-transfer sdl-release-gpu-transfer sdl-map-gpu-transfer
    sdl-unmap-gpu-transfer sdl-acquire-gpu-commands sdl-acquire-swapchain
    sdl-begin-copy-pass sdl-end-copy-pass
    sdl-upload-to-buffer sdl-upload-to-texture sdl-download-from-buffer
    sdl-download-from-texture sdl-begin-render-pass sdl-end-render-pass
    sdl-bind-gpu-pipeline sdl-bind-vertex-storage sdl-bind-fragment-storage
    sdl-bind-fragment-samplers sdl-push-vertex-uniform sdl-set-gpu-scissor
    sdl-draw-primitives sdl-push-fragment-uniform sdl-begin-compute-pass
    sdl-end-compute-pass sdl-bind-compute-pipeline sdl-bind-compute-storage
    sdl-push-compute-uniform sdl-dispatch-compute sdl-generate-gpu-mipmaps
    sdl-submit-gpu sdl-submit-gpu-fence sdl-wait-gpu-fences sdl-query-gpu-fence
    sdl-release-gpu-fence sdl-gpu-driver sdl-window-supports-present-mode
    sdl-set-frames-in-flight sdl-set-swapchain-parameters sdl-wait-gpu-idle
    gpu-copy-in gpu-copy-out)
  (import (chezscheme)
          (only (schevana base) at-load define-made library-layer)
          (only (schevana ffi) define-foreign define-foreign/collect-safe)
          (only (schevana sdl system) sdl-library))

  (library-layer foundation)

  ;; SDL3, loaded before a binding to it is made.
  (at-load sdl-library)

  ;; Copies plain memory, from Scheme's to SDL's and back.
  (define-foreign sdl-memcpy "SDL_memcpy" (uptr uptr size_t) uptr)

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
  (define-foreign sdl-create-gpu-texture "SDL_CreateGPUTexture"
    (uptr uptr) uptr)
  (define-foreign sdl-release-gpu-texture "SDL_ReleaseGPUTexture"
    (uptr uptr) void)
  (define-foreign sdl-create-gpu-sampler "SDL_CreateGPUSampler"
    (uptr uptr) uptr)
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
  ;; The screen may hold this call as long as it likes, so it is
  ;; collect-safe, as every call that may block is (tests/sources.ss).
  (define-foreign/collect-safe sdl-acquire-swapchain
    "SDL_AcquireGPUSwapchainTexture" (uptr uptr uptr uptr uptr) bool)
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
  ;; the name of the device's driver
  (define-foreign sdl-gpu-driver "SDL_GetGPUDeviceDriver" (uptr) string)
  ;; how a window's frames are presented, and waiting for the device
  (define-foreign sdl-window-supports-present-mode
    "SDL_WindowSupportsGPUPresentMode" (uptr uptr int) bool)
  (define-foreign/collect-safe sdl-set-frames-in-flight
    "SDL_SetGPUAllowedFramesInFlight" (uptr unsigned-32) bool)
  (define-foreign/collect-safe sdl-set-swapchain-parameters
    "SDL_SetGPUSwapchainParameters" (uptr uptr int int) bool)
  (define-foreign/collect-safe sdl-wait-gpu-idle "SDL_WaitForGPUIdle"
    (uptr) bool)
  (define-made gpu-copy-in
    (foreign-procedure "SDL_memcpy" (uptr u8* size_t) uptr))
  (define-made gpu-copy-out
    (foreign-procedure "SDL_memcpy" (u8* uptr size_t) uptr)))
