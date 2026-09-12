unit ParticleDemo;

{------------------------------------------------------------------------------
  Worked example for Vulkan_Components_Particles.

  Assumes you already have a working TvgScene / TvgLinker / TvgRenderEngine set
  up the way the rest of the package expects - an active TvgInstance, a screen
  device, a surface, a swapchain and a render engine attached to the scene.
  This unit only adds the particle system on top of that.

  Two things the host application must do, and neither can be done from inside
  the component:

  1) Threaded mode submits to the graphics queue from a worker thread.
     vkQueueSubmit needs external synchronisation per queue, so the application
     must take TvgParticleSystem.SubmitLock around its own frame submit /
     present call.  See PresentGuarded below for the shape of it.

  2) OnRedrawNeeded fires on the main thread once the compute fence has
     signalled.  Hook it to whatever triggers a repaint in your application.

  If you would rather not deal with either, set RunMode := prmInline and call
  RecordStep from inside your frame command-buffer recording, before the render
  pass begins - see the note on RecordInlineStep at the bottom.
------------------------------------------------------------------------------}

interface

uses
  System.SysUtils,
  System.Classes,
  Vulkan,
  PasVulkan.Framework,
  Vulkan_Components,
  Vulkan_Components_Lookups,
  Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer,
  Vulkan_Components_Particles;

type
  TvgParticleDemo = class(TComponent)
  private
    fScene   : TvgScene;
    fLinker  : TvgLinker;
    fStore   : TvgParticleStore;
    fSystem  : TvgParticleSystem;

    procedure HandleRedrawNeeded(Sender: TObject);

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Build the store, the forces and the compute pipeline against a scene
    // that already has an active Vulkan device.
    procedure Build(aScene: TvgScene; aLinker: TvgLinker; aParticleCount: Integer = 65536);

    // Start / stop the simulation worker.
    procedure Start;
    procedure Stop;

    // Render one frame, holding the lock the compute worker also takes, so the
    // two never submit to the graphics queue at the same time.
    //
    // The frame loop this drives, for reference - every step matters, which is
    // why TriggerWindowRepaint has to be the entry point:
    //
    //   TvgLinker.TriggerWindowRepaint            (RT_SCREEN)
    //     -> TvgLinker.LinkerStartPrepare         sets fLinkRenderLock
    //         -> TvgFrame.StartFramePrepare       acquires the swapchain image
    //             -> TvgBaseRenderEngine.StartRenderEnginePrepare
    //                 -> FinishRenderEnginePrepare      (when not UseThread)
    //                     -> TvgFrame.FinishFramePrepare
    //                         -> TvgLinker.LinkerFinishPrepare
    //                             -> AdvanceToNextFrames   <- frame advance
    //                             -> VulkanPaint_Present   <- present
    //
    procedure RenderFrameGuarded;

    // Superseded by RenderFrameGuarded, which it now calls.  aFrame is ignored.
    procedure PresentGuarded(aFrame: TvgFrame);

    // prmInline alternative: call this while the frame command buffer is
    // recording and before the render pass begins.
    procedure RecordInlineStep(aCommandBuffer: TvgCommandBuffer;
                               aFrameIndex: Integer;
                               aDeltaTime: Single);

    property Store  : TvgParticleStore   read fStore;
    property System_ : TvgParticleSystem read fSystem;
  end;

implementation

constructor TvgParticleDemo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  fSystem := TvgParticleSystem.Create(Self);
  fSystem.OnRedrawNeeded := HandleRedrawNeeded;
end;

destructor TvgParticleDemo.Destroy;
begin
  Stop;
  inherited;
end;

procedure TvgParticleDemo.Build(aScene: TvgScene; aLinker: TvgLinker; aParticleCount: Integer);
var
  E : TvgParticleEmitter;
begin
  fScene  := aScene;
  fLinker := aLinker;

  //--------------------------------------------------------------------------
  // 1.  The store.  A TvgParticleStore is a normal TvgObjectStore except that
  //     its vertex buffers also carry STORAGE usage, and it is already set to
  //     POINT_LIST so the package's shader builder emits gl_PointSize.
  //--------------------------------------------------------------------------
  fStore := TvgParticleStore.Create(Self);

  // Additive is the default and needs no depth sorting, because the result is
  // the same whatever order overlapping particles are drawn in.  Switch to
  // pbmAlpha for smoke or dust, where particles should occlude rather than
  // accumulate - but be aware that is order dependent.
  fStore.BlendMode := pbmAdditive;

  // 0 gives a hard-edged disc, 0.5 a pure gradient.
  fStore.SoftEdge  := 0.35;

  if not fScene.Load_Begin then
    raise Exception.Create('Scene would not enter loading state');
  try
    fScene.AddDataStore(fStore);
  finally
    fScene.Load_End;
  end;

  //--------------------------------------------------------------------------
  // 2.  Emission ranges.  Life, velocity and mass are all randomised per
  //     particle - on the CPU for the initial seed, and thereafter by the
  //     compute shader every time a particle dies and respawns.
  //--------------------------------------------------------------------------
  E := fSystem.Emitter;

  E.SetOrigin(0, -4, 0);          // inject from a small box low in the space
  E.SetExtent(0.6, 0.2, 0.6);

  E.SetVelocityRange(-2.0, 3.0, -2.0,      // min x,y,z
                      2.0, 7.0,  2.0);     // max x,y,z

  E.LifeMin := 2.0;   E.LifeMax := 7.0;    // random life, seconds
  E.MassMin := 0.5;   E.MassMax := 3.0;    // random mass

  E.SetColour(0.55, 0.75, 1.0, 1.0);
  E.ColourJitter := 0.30;

  // Base point-sprite size in pixels.  The compute shader scales it per
  // particle: heavier particles draw larger, and every particle shrinks as
  // its life runs down, so gl_PointSize is no longer one shared constant.
  E.PointSize := 7.0;

  E.Damping     := 0.08;   // fraction of velocity shed per second
  E.Restitution := 0.40;   // energy kept on a bounce off the bounds

  E.SetBounds(-15, -15, -15,  15, 15, 15);

  //--------------------------------------------------------------------------
  // 3.  The force structures the particles are pushed around by.
  //--------------------------------------------------------------------------
  fSystem.Forces.AddGravity(0, -1, 0, 9.81);              // downward field

  fSystem.Forces.AddAttractor(0, 2, 0,                    // origin
                              45.0,                       // strength, + attracts
                              12.0,                       // radius of influence
                              ffInverseSquare);

  fSystem.Forces.AddVortex(0, 0, 0,                       // origin
                           0, 1, 0,                       // axis
                           14.0,                          // strength
                           10.0);                         // radius

  fSystem.Forces.AddDrag(0.35);

  //--------------------------------------------------------------------------
  // 4.  Configure the system.  Nothing Vulkan-side is built until Start sets
  //     Active := True, so this part does not need a live device.
  //--------------------------------------------------------------------------
  fSystem.ParticleCount := aParticleCount;
  fSystem.Store         := fStore;
  fSystem.StepInterval  := 16;      // ~60 steps a second
  fSystem.FixedStep     := 0;       // 0 = use the wall clock delta

  // prmThreaded needs at least 3 frames in flight so the worker never writes
  // the slot the renderer is reading; activating raises if there are fewer.
  // prmInline has no such requirement and is the simpler thing to bring up
  // first - it records the dispatch into the frame's own command buffer, so
  // no locking, no fence stall and no slot handshake.
  fSystem.RunMode := prmThreaded;
end;

procedure TvgParticleDemo.Start;
begin
  // Builds the buffers and compute pipeline, seeds the particles, primes every
  // frame slot, and starts the worker if RunMode is prmThreaded.
  fSystem.Active := True;
end;

procedure TvgParticleDemo.Stop;
begin
  // Stops the worker, waits for the device to go idle and frees the GPU side.
  // The store keeps drawing the last simulated frame.
  if Assigned(fSystem) then
    fSystem.Active := False;
end;

procedure TvgParticleDemo.HandleRedrawNeeded(Sender: TObject);
begin
  // Runs on the main thread (the worker reaches here through Synchronize),
  // after the compute fence has signalled, so the vertex data for this step is
  // complete.  Go through the guarded path: the render submit inside
  // TriggerWindowRepaint shares the graphics queue with the compute worker.
  RenderFrameGuarded;
end;

procedure TvgParticleDemo.RenderFrameGuarded;
begin
  if not Assigned(fLinker) then Exit;

  // TriggerWindowRepaint drives the WHOLE cycle, and it must be the entry
  // point.  Calling TvgFrame.StartFramePrepare directly (as an earlier version
  // of this sample did) skips TvgLinker.LinkerStartPrepare, so fLinkRenderLock
  // is never set - and LinkerFinishPrepare opens with
  //
  //     if not fLinkRenderLock then exit;
  //
  // so AdvanceToNextFrames and VulkanPaint_Present never run.  The frame is
  // recorded and submitted but the swapchain image never advances and the same
  // picture stays on screen.
  //
  // The lock is the one the compute worker takes around its own submit: the
  // render submit happens inside this call (FinishFramePrepare ->
  // ExecuteCommand), so it has to be covered too.
  fSystem.SubmitLock.Enter;
  try
    // The compute shader has just rewritten the particle vertex buffers, so
    // the scene content is stale.  Saying so is all that is needed: the linker
    // decides what to do about it, and an offscreen target uses it to choose
    // between re-rendering and simply re-blitting the last image.
    //
    // (Before the frame-loop rework this call was load-bearing for a different
    //  reason - RT_FRAME would otherwise re-present the same image forever.
    //  That is fixed in TvgLinker.TriggerWindowRepaint; this is now just an
    //  honest "the scene changed".)
    fLinker.FlagALLFrameRebuild;

    fLinker.TriggerWindowRepaint;
  finally
    fSystem.SubmitLock.Leave;
  end;
end;

procedure TvgParticleDemo.PresentGuarded(aFrame: TvgFrame);
begin
  // Retained so existing callers keep compiling.  aFrame is ignored: the
  // linker owns which frame is prepared and which is presented.
  RenderFrameGuarded;
end;

procedure TvgParticleDemo.RecordInlineStep(aCommandBuffer: TvgCommandBuffer;
                                           aFrameIndex: Integer;
                                           aDeltaTime: Single);
begin
  // prmInline path: no thread, no fence wait, no locking.  The dispatch and
  // the barrier go into the frame's own command buffer, so the draw that
  // follows in the same submit is correctly ordered after the simulation.
  fSystem.RecordStep(aCommandBuffer, aFrameIndex, aDeltaTime);
end;

end.
