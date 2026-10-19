# Dynamic Rendering

Branch: `DynamicRender`

Goal: record frames with Vulkan 1.3 dynamic rendering (`vkCmdBeginRendering`)
instead of a `VkRenderPass` and `VkFramebuffer`s, keep the classic path
working beside it, and let the application choose between the two before the
renderer is enabled.

## 1. Choosing the path

```pascal
Renderer.RenderingMode := rmStandard;   // or rmDynamic (the default)
...
Instance.Active := True;
if Renderer.ActiveRenderingMode = rmDynamic then ...
```

| | |
|---|---|
| `TvgBaseRenderEngine.RenderingMode` | **What you ask for.** `rmDynamic` (default) or `rmStandard`. Published, so it streams with the form. Set it before enabling; changing it on an active renderer disables it, as `ShaderUseDouble` and `SelectMode` do. |
| `TvgBaseRenderEngine.ActiveRenderingMode` | **What is in use**, or what enabling would pick. Read-only. |
| `TvgBaseRenderEngine.UseDynamicRendering` | The same as a Boolean. Called by the render pass, pipelines, workers and frame recording. |
| `TvgLogicalDevice.DynamicRenderingON` | Whether the device *requests* the `dynamicRendering` feature (default True). Off forces Standard. |
| `TvgLogicalDevice.IsDynamicRenderingActive` | Requested, and, once the Vulkan device exists, actually **granted**. |

`rmDynamic` means "dynamic when possible". It quietly becomes Standard when:

- the device did not get the feature. A 1.2 driver, a GPU without it, or an
  instance API below 1.3 all leave it off. `IsDynamicRenderingActive` only
  counts the feature once the device has actually granted it: the 1.3 feature
  struct was chained, the feature came back `VK_TRUE`, and
  `vkCmdBeginRendering` was loaded;
- `DynamicRenderingON` is off;
- the render pass has more than one subpass. Dynamic rendering has no
  `vkCmdNextSubpass`.

Previously the device reported only the request. On a GPU without the
feature, the engine would still have built pipelines with `renderPass = NULL`
and called a nil `vkCmdBeginRendering`.

### The decision is latched

The render pass decides in `SetEnabled`, after `BuildStructure`, when the
subpass count is known. It records the answer in `fBuiltForDynamicRendering`,
and the engine latches that for the renderer's whole active life. Pipelines
(render pass handle or `VkPipelineRenderingCreateInfo`), worker secondaries
(render-pass inheritance or `VkCommandBufferInheritanceRenderingInfo`) and
frame recording all follow the latch, so they cannot disagree, even if a
device flag changes mid-life. `SetDisabled` clears the latch. A swapchain
rebuild re-enables the renderer and decides again, the same way.

Formats come from one place, `TvgRenderPass.GetDynamicRenderingFormats`. The
pipeline, the secondaries' inheritance and `vkCmdBeginRendering` must name
exactly the same attachments.

## 2. What a dynamic frame records

`CmdBeginDynamicRendering` → secondaries (`vkCmdExecuteCommands`) →
`CmdEndDynamicRendering`.

| Attachment | Image | Load / store |
|---|---|---|
| colour, no MSAA | swapchain image (screen) or the frame's offscreen image | clear / store |
| colour, MSAA | the MSAA attachment image, **resolved** (`AVERAGE`) into the target above | clear / don't care |
| depth (+ stencil) | the depth attachment image for this swapchain image or frame slot | clear / don't care |

The images are the ones the classic path's framebuffers use, indexed the same
way (per swapchain image on screen, per frame slot offscreen).

### Barriers

**Begin**, one `vkCmdPipelineBarrier`. Every attachment goes
`UNDEFINED → *_ATTACHMENT_OPTIMAL`: all are cleared, so their old contents
are discarded. That also means no queue-family ownership transfer is needed.

- Source and destination stages are
  `COLOR_ATTACHMENT_OUTPUT | EARLY_FRAGMENT_TESTS | LATE_FRAGMENT_TESTS`.
  `COLOR_ATTACHMENT_OUTPUT` is the stage the frame's submit waits on the
  acquire semaphore at. A barrier is only ordered after that wait if its
  source scope includes that stage, and only then does the swapchain image's
  layout transition wait for the presentation engine to release the image.
  The first version used `TOP_OF_PIPE`, and synchronization validation
  reported it as a write-after-read hazard against `vkAcquireNextImageKHR`.
- Depth has `srcAccess = DEPTH_STENCIL_ATTACHMENT_WRITE`, which orders this
  frame's clear after the previous frame's writes to the same image.
- A combined depth/stencil format is transitioned with both aspects, even
  when `StencilBufOn` is off and only depth is rendered.

**End**, depending on the target:

| Target | HUD | Barrier | Swapchain image left in |
|---|---|---|---|
| screen | off | `COLOR_ATTACHMENT → PRESENT_SRC` (plus a graphics→present release if the families differ) | `PRESENT_SRC` |
| screen | on | `COLOR_ATTACHMENT → TRANSFER_DST` | `TRANSFER_DST`, handed straight to the HUD blits |
| offscreen | either | none: the frame image stays `COLOR_ATTACHMENT_OPTIMAL` for `RecordPresentBlit` | set by `RecordPresentBlit` |

The HUD hand-off is where dynamic rendering beats a render pass by more than
object count. A render pass must end in its `finalLayout`, `PRESENT_SRC`, so
the HUD then had to go `PRESENT_SRC → TRANSFER_DST` with a `BOTTOM_OF_PIPE`
source, which drains the whole pipeline every frame. `CmdEndDynamicRendering`
takes an `aHUDFollows` flag. Only pass True when `TvgFrame.RecordPresentAndHUD`
really runs next. `StartRenderEnginePrepare` passes `Linker.HUDEnabled` and
then calls it. A threaded renderer passes `TvgFrame.HUDEnabledForFrame`, the
value `CaptureHUD` took on the main thread, and then calls it.
`RecordPresentAndHUD` is public so that renderers which
end their frames outside `StartRenderEnginePrepare` can do so.

`TvgFrame.fSwapImageLayout` tracks the swapchain image's layout through the
frame. `RecordHUDOverlay` transitions only when it has to, and
`RecordPresentAndHUD` finishes by making the image presentable, even if the
HUD bailed out early.

## 3. Also fixed along the way

These came to light once validation really ran (see section 4). They affect
**both** paths.

| Problem | Effect | Fix |
|---|---|---|
| `Validation := True` silently ran with no validation layer in a 32-bit process: the SDK only installs 64-bit layers unless its 32-bit component is added | nothing was ever validated in the sample | `TvgInstance.ValidationLayerActive` reports the truth; the sample logs it; the GPU test fails on it |
| `OnInstanceDebugReportCallback` published but never installed | no way to receive messages | installed when enabled with Validation on; new `OnInstanceDebugUtilsMessengerCallback` and `SyncValidation` |
| HUD `FlushMappedMemoryRange(nil, ...)`: PasVulkan takes the offset as base minus mapping | **access violation inside the NVIDIA driver** with the HUD on | pass the mapped pointer (same bug fixed in the data store's staging upload) |
| image view created for the transfer-only HUD atlas | validation error; the NVIDIA driver faults on such views | `TvgResourceImageBuffer` only creates a view for a viewable usage; view destroyed before image |
| uploads recorded in a graphics-family pool, submitted on `TransferQueue` | invalid on GPUs with a separate transfer family (the RTX 3080 here) | submit on the pool's own queue (`Pool.Queue[-1]`) |
| `vkAcquireNextImageKHR` into a semaphore whose wait was still pending | invalid; the frame's fence was waited on after the acquire | wait for the slot's fence first, then acquire |
| offscreen blit and HUD blit into the same pixels with no barrier; also panel then crosshair | write-after-write hazards | transfer→transfer barriers between them |
| classic non-MSAA subpass colour reference left `UNDEFINED` | `vkCreateRenderPass` invalid (Standard path only) | `COLOR_ATTACHMENT_OPTIMAL` |
| `VkPhysicalDeviceVulkan13Features` chained on the GPU's version alone | invalid under a 1.2 instance | chained on min(instance, device) version: `TvgFeatures.EffectiveAPIVersion` |
| `TvgElementSampler` (picking with `smStorageBuffer`) recorded fragment/compute-stage barriers in a transfer-family pool and copied on `TransferQueue` | `VUID-vkCmdPipelineBarrier-srcStageMask-06461` / `dstStageMask-06462`; the copy was not ordered after the frame that wrote the IDs, so a pick during a frame in flight sometimes found nothing | graphics-family pool, submitted on the queue that rendered the frame slot (`Pool.Queue[frame]`); transfer→host barrier before the CPU reads the staging buffer |
| `TvgPixelSampler` (picking with `smImageBuffer`) copied on `GraphicsQueue`, whichever queue rendered the frame slot | not ordered after a frame still running on another graphics queue (no symptom seen on the RTX 3080, but the spec does not guarantee the order) | new `FrameIndex`, set by `GetPixelData`; submitted on `Pool.Queue[FrameIndex]`; the same transfer→host barrier |
| `TvgCommandBufferPool.Queue[N]` never returned a family's last queue | `Queue[N]` could differ from the `GraphicsQueues[N]` the frame loop submits slot N to | index check made inclusive |

## 4. Tests

| | |
|---|---|
| `Tests/DynamicRenderingTest.dpr` | CPU only, in `RunTests.bat`. Defaults, switching Dynamic ↔ Standard before enabling, every fallback to Standard, the device's request semantics. |
| `DynamicRenderingGPUTest` | Real frames on a real GPU. |

The GPU test builds the same component chain as the sample, on a small
window. It runs the matrix [Standard, Dynamic] × [screen, offscreen] ×
[MSAA 1×, 4×] × [depth on, off], plus the HUD both ways. Each case:

- renders frames with **validation and synchronization validation** on, and
  fails on any error or warning. Two canaries (a deliberate invalid call and
  a deliberate write-after-write hazard) prove the layer is live and its
  messages arrive. A run that asks for validation without getting it fails;
- checks the path taken, and that a `VkRenderPass` exists on the Standard
  path only;
- resizes the window (swapchain rebuild, renderer re-enabled) and renders
  again;
- offscreen: reads the image back. The background must be the clear colour,
  and the centre pixel must show depth testing worked: two overlapping
  triangles in one draw, the far one recorded second. Then the Standard and
  Dynamic images must match;
- checks every frame slot recorded the HUD overlay when the HUD is on (its
  atlas left `TRANSFER_SRC`), none did when it is off, and every slot left
  its swapchain image `PRESENT_SRC`.

The scene has a second object store, a blue square in a corner, so there
are two pipelines and two draws, and every offscreen case checks the square
was drawn too.

That matrix runs on `TvgRenderEngine_Single`, which records through
`StartRenderEnginePrepare`. A renderer that records on its own threads should
run the same matrix in each of its thread modes, and its offscreen images must
match the single-thread renderer's. A missing present blit shows up as
`VUID-VkPresentInfoKHR-pImageIndices-01430`: the swapchain image is presented
still `UNDEFINED`.

Each mode also runs one case under `Linker.UseThread`, where a frame's
completion starts the next frame before it returns.

A
`WM_PAINT` and `TvgScene.ClearScene` each start a frame too, so the test
waits for any frame in flight before a resize or a read-back. Teardown
deliberately does not wait. It starts a frame of the scene, runs `ClearScene`
while that frame is recording, then disables the instance straight away, as
the sample's `Button2Click` does. It checks that a frame really is in flight
at each step.

Object picking has its own cases: [storage buffer, storage image] ×
[Standard, Dynamic] × [screen, offscreen] (`DynamicRenderingGPUTest.exe [gpu]
pick` runs just these). The triangles carry their object's ID, and
`TvgRenderEngine.GetObjectAtLocation` reads it back through `TvgElementSampler`
(buffer) or `TvgPixelSampler` (image). Each pick follows a paint straight
away, with no wait for idle, on the slot the tool manager picks from
(`Linker.PresentFrameIndex`). That slot was just submitted and may still be
running. Two points on the triangles must give their object and two off them
must give nothing. Every slot is then picked with the GPU idle, and all of it
again after a resize. Validation must stay clean throughout.

Synchronization validation does not report the cross-queue race these picks
can hit. Without the `TvgElementSampler` fix, on the RTX 3080, 1 to 3 of every
12 picks made during a frame in flight came back empty. The old
`TvgPixelSampler` queue never produced a wrong pick at all. So after every
pick the test also checks the queue directly. The sampler's `SubmitQueue`
must be the queue the frame loop last submitted that slot on. Against the
old pixel sampler this fails for every pick of slots 1 and 2 (graphics
queue 0 against 1 or 2). On a GPU with a single graphics queue it holds
trivially.

Results, 2026-09-22:

| GPU | Build | Validation | Result | Standard vs Dynamic images |
|---|---|---|---|---|
| NVIDIA RTX 3080 Laptop (driver 581.95) | Win64 | on + sync | all pass, 0 messages | byte-identical |
| Intel UHD (CometLake, 101.2137) | Win64 | on + sync | all pass, 0 messages | byte-identical |
| both | Win32 | off | all pass | byte-identical |

Timing, validation off, 400 frames, screen, MSAA 4×, depth, mean wall time of
recording plus submit plus present:

| GPU | Standard | Dynamic |
|---|---|---|
| RTX 3080 | 0.35-0.52 ms | 0.23-0.27 ms (30-50% less) |
| Intel UHD | 2.75 ms | 2.75 ms (GPU-bound: the same work either way) |

With a GPU that is not the bottleneck, dynamic rendering is cheaper per frame.
There is no `VkRenderPass` or `VkFramebuffer` to begin, and fewer layout
transitions. On a GPU-bound frame the two paths do identical GPU work.

## 5. Editing while a frame is in flight

A renderer may record on threads of its own, so the scene cannot assume a
frame is finished when the main thread is idle. `TvgScene.ClearScene`,
`Load_Begin` and disabling call `FinishFramesInFlight` before they free or
deactivate anything. That calls the virtual
`TvgBaseRenderEngine.FinishFrameInFlight` on each connected renderer: a no-op
for a renderer that records synchronously, such as `TvgRenderEngine_Single`,
and a drain of its threads for one that does not. It then waits for the
device, because finished recording is not finished executing
(`VUID-vkDestroyBuffer-buffer-00922` without it).

Editing a store in place, with no `Load_Begin`/`Load_End`, is safe while a
frame that draws it is recording or executing:

- **CPU-side data** (vertices, colours, objects, bounds). Every edit already
  held the store's lock. `TvgVulkanDataStore.VulkanDraw` now holds it for
  everything it reads, the buffer handles, frame count and strides as well as
  the objects. So a draw sees the store before an edit or after it.
- **Freeing what a frame uses**: deactivating a store (`ShowPoints := False`),
  a live pipeline rebuild,
  `DeleteVulkanDataBuffers`, `ClearAll`, `SetFrameCount`. These first call the
  new `TvgBaseObjectStore.FinishFramesInFlight`, which is the scene's: the
  frame in flight is finished and the device waited on. The wait happens
  outside the store's lock, which a draw may be waiting for. Before this, the
  pipeline rebuild invalidated the command buffer being recorded, and the
  device was lost (`VK_ERROR_DEVICE_LOST`). The device wait also covers the
  single-thread renderer, whose recent frames can still be executing.
- `DeleteVulkanDataBuffers` now marks the data dirty. The CPU copy is kept, so
  a store switched off and on again re-uploads it. Before, it drew whatever
  its new buffers held.
- **Growing a store past its GPU buffers** (adding vertices, instances or
  indices once it has been drawn). Buffers were made at exactly the size
  loaded and never grown, so the next upload failed its destination-too-small
  assert. The call that grew the store now calls
  `TvgVulkanDataStore.EnsureGPUCapacity` on its way out: the short buffers are
  freed through `DeleteVulkanDataBuffers`, with the wait above, and the next
  upload makes them again at the CPU arrays' capacity, which doubles. So an
  edit costs one wait per doubling, and a store that is only ever loaded keeps
  exact-size buffers. Until the buffers are replaced, an upload copies what
  fits and stays dirty, and `VulkanDraw` skips objects that do not fit. Edits
  that add data must therefore run on the main thread, not inside the lock.
  The GPU test's in-place edits grow the blue square's object mid-frame and
  check the new geometry is drawn.

An edit spanning several stores is still not atomic: a frame can record one
store before the edit and another after it. Call
`Scene.FinishFramesInFlight` first if that matters.

## 6. Not changed

- Pipelines are created once per worker per frame in flight, all identical.
- MSAA enables `sampleShadingEnable` (per-sample shading, N× fragment cost at
  N× MSAA). That is a quality versus speed choice, not a bug.
- `TvgFeatures` enables every feature the GPU supports, `robustBufferAccess`
  included.
- `TvgShaderModule.SetFileName` keeps a name only if the file already exists,
  so a pipeline cannot be built before its `.spv` is on disk.
- `TvgWindowVCL.vgWindowBackgroundColor` passes 0-255 channel values as
  floats, so any non-black clear colour saturates.
