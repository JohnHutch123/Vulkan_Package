 (******************************************************************************
 *                                 vgVulkan                                  *
 ******************************************************************************
 *                        Version 2021-05-01-01-01-0000                       *
 ******************************************************************************
 *                                zlib license                                *
 *============================================================================*
 *                                                                            *
 * Copyright (C) 2021 Datavis (www.datavis.com.au) johnh@datavis.com.au       *
 *                                                                            *
 * This software is provided 'as-is', without any express or implied          *
 * warranty. In no event will the authors be held liable for any damages      *
 * arising from the use of this software.                                     *
 *                                                                            *
 * Permission is granted to anyone to use this software for any purpose,      *
 * including commercial applications, and to alter it and redistribute it     *
 * freely, subject to the following restrictions:                             *
 *                                                                            *
 * 1. The origin of this software must not be misrepresented; you must not    *
 *    claim that you wrote the original software. If you use this software    *
 *    in a product, an acknowledgement in the product documentation would be  *
 *    appreciated but is not required.                                        *
 * 2. Altered source versions must be plainly marked as such, and must not be *
 *    misrepresented as being the original software.                          *
 * 3. This notice may not be removed or altered from any source distribution. *
 * 4. Some code has been generated using various LLM (GROK and Plerplexity)   *                                                                         *
 ******************************************************************************
 *                  General guidelines for code contributors                  *
 *============================================================================*
 *                                                                            *
 * 1. Make sure you are legally allowed to make a contribution under the zlib *
 *    license.                                                                *
 * 2. The zlib license header goes at the top of each source file, with       *
 *    appropriate copyright notice.                                           *
 * 3. This PasVulkan wrapper may be used only with the PasVulkan-own Vulkan   *
 *    Pascal header.                                                          *
 * 4. After a pull request, check the status of your pull request on          *
      http://github.com/BeRo1985/pasvulkan                                    *
 * 5. Write code which's compatible with Delphi >= 2009 and FreePascal >=     *
 *    3.1.1                                                                   *
 * 6. Don't use Delphi-only, FreePascal-only or Lazarus-only libraries/units, *
 *    but if needed, make it out-ifdef-able.                                  *
 * 7. No use of third-party libraries/units as possible, but if needed, make  *
 *    it out-ifdef-able.                                                      *
 * 8. Try to use const when possible.                                         *
 * 9. Make sure to comment out writeln, used while debugging.                 *
 * 10. Make sure the code compiles on 32-bit and 64-bit platforms (x86-32,    *
 *     x86-64, ARM, ARM64, etc.).                                             *
 * 11. Make sure the code runs on all platforms with Vulkan support           *
 *                                                                            *
 ******************************************************************************)
 unit Vulkan_Components_Particles;


(******************************************************************************
 *                                 vgVulkan                                   *
 ******************************************************************************
 *                              Particle System                               *
 *============================================================================*
 *                                                                            *
 *  GPU particle system for the Vulkan_Package component set.                 *
 *                                                                            *
 *  Particles are emitted with randomised life, velocity and mass, injected    *
 *  into a bounded space, and integrated every time step by a compute shader   *
 *  against a collection of force structures (uniform fields, point            *
 *  attractors/repulsors, drag and vortex).                                    *
 *                                                                            *
 *  Simulation state lives in a device-local SSBO that only the compute        *
 *  shader ever touches.  The same dispatch also writes the render-visible     *
 *  subset (position + colour) straight into the per-frame VERTEX buffer of a  *
 *  TvgObjectStore/TvgVulkanDataStore, so the existing DataStore draw path     *
 *  displays the result with no CPU readback and no extra copies.             *
 *                                                                            *
 *  Layout of the classes here:                                               *
 *                                                                            *
 *    TvgForceField        - one force structure (a TCollectionItem)           *
 *    TvgForceFields       - the collection of them                           *
 *    TvgParticleEmitter   - the randomisation ranges used when a particle is  *
 *                           first seeded and whenever it is respawned         *
 *    TvgParticleCompute   - the compute pipeline: shader module, descriptor   *
 *                           set layout/pool/sets, pipeline layout, pipeline   *
 *    TvgParticleStore     - TvgObjectStore descendant whose vertex buffers    *
 *                           carry STORAGE usage so compute can write them     *
 *    TvgParticleSystem    - owns all of the above and drives the time step    *
 *    TvgParticleThread    - optional worker that runs the step off the main   *
 *                           thread and flags a redraw when the fence signals  *
 *                                                                            *
 *  zlib license - see the other units in this package.                        *
 ******************************************************************************)

Interface

{$INCLUDE VulkanPackage.inc}

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.SyncObjs,
  System.Generics.Collections,
  Vulkan,
  PasVulkan.Types,
  PasVulkan.Framework,
  Vulkan_Assert,
  Vulkan_CriticalSection,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_Descriptors,
  Vulkan_Components_Compute,
  Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer,
  Vulkan_Components_ShaderCompiler;

const
  // Compute shader local workgroup size.  Must match the value written into
  // the GLSL source by TvgParticleCompute.BuildShaderSource.
  PARTICLE_LOCAL_SIZE   = 256;

  // Descriptor bindings inside the particle compute set (set = 0).
  PB_PARTICLES          = 0;   // read/write  - simulation state
  PB_FORCES             = 1;   // read only   - force structures
  PB_VERTICES           = 2;   // write only  - DataStore vertex buffer

  // Particle flag bits.
  PF_ALIVE              = 1;

  // Number of floats the compute shader writes per particle.  Position takes
  // three, colour four and texcoord two (x = point size, y = life ratio);
  // the DataStore rounds the 36-byte total up to a 48-byte stride, so the
  // last three floats are padding.  The real value is read back from
  // TvgVulkanDataStore.GetStride at Prepare time - this is only the default.
  PARTICLE_VERTEX_FLOATS = 12;

type

  EvgParticleException = class(Exception);

  {---------------------------------------------------------------------------
    GPU-side records.  These must match the GLSL declarations exactly, so they
    are packed and padded to std430 rules (vec4 on 16-byte boundaries).
  ---------------------------------------------------------------------------}

  // 64 bytes
  PvgParticle = ^TvgParticle;
  TvgParticle = packed record
    PosSize : TvgVector4S;   // xyz = position,  w = reserved (render size)
    VelMass : TvgVector4S;   // xyz = velocity,  w = mass
    Colour  : TvgVector4S;   // rgba, alpha is scaled by remaining life
    Life    : TvgScalarS;    // seconds of life remaining
    MaxLife : TvgScalarS;    // life it was born with, for the fade ratio
    Seed    : FixedUInt;     // per-particle xorshift RNG state
    Flags   : FixedUInt;     // bit 0 = alive
  end;
  TvgParticleArray = array of TvgParticle;

  // 48 bytes
  PvgForceRec = ^TvgForceRec;
  TvgForceRec = packed record
    Origin  : TvgVector4S;   // xyz = origin,          w = radius (0 = infinite)
    Vector  : TvgVector4S;   // xyz = direction/axis,  w = strength
    Kind    : FixedUInt;
    Falloff : FixedUInt;
    IsOn    : FixedUInt;
    Pad     : FixedUInt;
  end;
  TvgForceRecArray = array of TvgForceRec;

  // 128 bytes exactly - the guaranteed minimum maxPushConstantsSize.
  TvgParticlePush = packed record
    DeltaTime     : TvgScalarS;
    ElapsedTime   : TvgScalarS;
    ParticleCount : FixedUInt;
    ForceCount    : FixedUInt;

    EmitOrigin    : TvgVector4S;  // xyz = origin,      w = damping (per second)
    EmitExtent    : TvgVector4S;  // xyz = half extent, w = restitution
    VelMin        : TvgVector4S;  // xyz = min velocity
    VelMax        : TvgVector4S;  // xyz = max velocity
    BoundsMin     : TvgVector4S;  // xyz = simulation box minimum
    BoundsMax     : TvgVector4S;  // xyz = simulation box maximum
    LifeMass      : TvgVector4S;  // LifeMin, LifeMax, MassMin, MassMax
  end;

  {---------------------------------------------------------------------------
    Force structures
  ---------------------------------------------------------------------------}

  TvgForceKind = (
    fkUniform,   // constant acceleration - gravity, wind
    fkPoint,     // attract (+strength) or repel (-strength) about Origin
    fkDrag,      // velocity-proportional damping
    fkVortex     // tangential swirl about the axis Vector through Origin
  );

  TvgForceFalloff = (
    ffNone,           // strength is constant across the radius
    ffLinear,         // 1/r
    ffInverseSquare   // 1/r^2
  );

  TvgForceFields = class;

  TvgForceField = class(TCollectionItem)
  private
    fName     : String;
    fKind     : TvgForceKind;
    fFalloff  : TvgForceFalloff;
    fIsOn     : Boolean;

    fOriginX,
    fOriginY,
    fOriginZ,
    fRadius   : TvgScalarS;

    fVectorX,
    fVectorY,
    fVectorZ,
    fStrength : TvgScalarS;

    procedure SetSingleProp(var aField: TvgScalarS; const aValue: TvgScalarS);
    procedure SetKind(const Value: TvgForceKind);
    procedure SetFalloff(const Value: TvgForceFalloff);
    procedure SetIsOn(const Value: Boolean);

  protected
    function GetDisplayName: String; override;
    procedure MarkChanged;

  public
    constructor Create(Collection: TCollection); override;
    procedure Assign(Source: TPersistent); override;

    // Convenience setters so a force can be configured in one line.
    procedure SetOrigin(const X, Y, Z: TvgScalarS);
    procedure SetVector(const X, Y, Z: TvgScalarS);

    // Pack into the std430 record handed to the compute shader.
    function ToRecord: TvgForceRec;

  published
    property Name     : String          read fName     write fName;
    property Kind     : TvgForceKind    read fKind     write SetKind    default fkUniform;
    property Falloff  : TvgForceFalloff read fFalloff  write SetFalloff default ffNone;
    property IsOn     : Boolean         read fIsOn     write SetIsOn    default True;

    property OriginX  : TvgScalarS read fOriginX  write fOriginX;
    property OriginY  : TvgScalarS read fOriginY  write fOriginY;
    property OriginZ  : TvgScalarS read fOriginZ  write fOriginZ;
    property Radius   : TvgScalarS read fRadius   write fRadius;

    property VectorX  : TvgScalarS read fVectorX  write fVectorX;
    property VectorY  : TvgScalarS read fVectorY  write fVectorY;
    property VectorZ  : TvgScalarS read fVectorZ  write fVectorZ;
    property Strength : TvgScalarS read fStrength write fStrength;
  end;

  TvgForceFields = class(TCollection)
  private
    fOwner   : TPersistent;
    fChanged : Boolean;

    function GetItem(Index: Integer): TvgForceField;
    procedure SetItem(Index: Integer; const Value: TvgForceField);

  protected
    function GetOwner: TPersistent; override;
    procedure Update(Item: TCollectionItem); override;

  public
    constructor Create(aOwner: TPersistent);

    function Add: TvgForceField;

    // Helpers that build the common force types in one call.
    function AddGravity(const X, Y, Z, aStrength: TvgScalarS): TvgForceField;
    function AddAttractor(const X, Y, Z, aStrength, aRadius: TvgScalarS;
                          aFalloff: TvgForceFalloff = ffInverseSquare): TvgForceField;
    function AddDrag(const aStrength: TvgScalarS): TvgForceField;
    function AddVortex(const X, Y, Z, aAxisX, aAxisY, aAxisZ,
                             aStrength, aRadius: TvgScalarS): TvgForceField;

    // Flatten the active items into the array uploaded to the force SSBO.
    function BuildArray(var aArray: TvgForceRecArray): Integer;

    property Items[Index: Integer]: TvgForceField read GetItem write SetItem; default;
    property IsChanged: Boolean read fChanged write fChanged;
  end;

  {---------------------------------------------------------------------------
    Emitter - the randomisation ranges applied when a particle is seeded on the
    CPU and, from then on, whenever the compute shader respawns a dead one.
  ---------------------------------------------------------------------------}

  TvgParticleEmitter = class(TPersistent)
  private
    fOnChange : TNotifyEvent;

    fOriginX, fOriginY, fOriginZ : TvgScalarS;
    fExtentX, fExtentY, fExtentZ : TvgScalarS;

    fVelMinX, fVelMinY, fVelMinZ : TvgScalarS;
    fVelMaxX, fVelMaxY, fVelMaxZ : TvgScalarS;

    fLifeMin, fLifeMax : TvgScalarS;
    fMassMin, fMassMax : TvgScalarS;

    fColourR, fColourG, fColourB, fColourA : TvgScalarS;
    fColourJitter : TvgScalarS;
    fPointSize    : TvgScalarS;

    fDamping, fRestitution : TvgScalarS;

    fBoundsMinX, fBoundsMinY, fBoundsMinZ : TvgScalarS;
    fBoundsMaxX, fBoundsMaxY, fBoundsMaxZ : TvgScalarS;

    procedure Changed;

  public
    constructor Create;
    procedure Assign(Source: TPersistent); override;

    procedure SetOrigin(const X, Y, Z: TvgScalarS);
    procedure SetExtent(const X, Y, Z: TvgScalarS);
    procedure SetVelocityRange(const MinX, MinY, MinZ, MaxX, MaxY, MaxZ: TvgScalarS);
    procedure SetBounds(const MinX, MinY, MinZ, MaxX, MaxY, MaxZ: TvgScalarS);
    procedure SetColour(const R, G, B, A: TvgScalarS);

    property OnChange: TNotifyEvent read fOnChange write fOnChange;

  published
    property OriginX : TvgScalarS read fOriginX write fOriginX;
    property OriginY : TvgScalarS read fOriginY write fOriginY;
    property OriginZ : TvgScalarS read fOriginZ write fOriginZ;

    property ExtentX : TvgScalarS read fExtentX write fExtentX;
    property ExtentY : TvgScalarS read fExtentY write fExtentY;
    property ExtentZ : TvgScalarS read fExtentZ write fExtentZ;

    property VelMinX : TvgScalarS read fVelMinX write fVelMinX;
    property VelMinY : TvgScalarS read fVelMinY write fVelMinY;
    property VelMinZ : TvgScalarS read fVelMinZ write fVelMinZ;
    property VelMaxX : TvgScalarS read fVelMaxX write fVelMaxX;
    property VelMaxY : TvgScalarS read fVelMaxY write fVelMaxY;
    property VelMaxZ : TvgScalarS read fVelMaxZ write fVelMaxZ;

    property LifeMin : TvgScalarS read fLifeMin write fLifeMin;
    property LifeMax : TvgScalarS read fLifeMax write fLifeMax;
    property MassMin : TvgScalarS read fMassMin write fMassMin;
    property MassMax : TvgScalarS read fMassMax write fMassMax;

    property ColourR : TvgScalarS read fColourR write fColourR;
    property ColourG : TvgScalarS read fColourG write fColourG;
    property ColourB : TvgScalarS read fColourB write fColourB;
    property ColourA : TvgScalarS read fColourA write fColourA;
    property ColourJitter : TvgScalarS read fColourJitter write fColourJitter;

    // Base point-sprite size in pixels.  The compute shader scales it by mass
    // and by remaining life to get each particle's final gl_PointSize.
    property PointSize    : TvgScalarS read fPointSize write fPointSize;

    property Damping     : TvgScalarS read fDamping     write fDamping;
    property Restitution : TvgScalarS read fRestitution write fRestitution;

    property BoundsMinX : TvgScalarS read fBoundsMinX write fBoundsMinX;
    property BoundsMinY : TvgScalarS read fBoundsMinY write fBoundsMinY;
    property BoundsMinZ : TvgScalarS read fBoundsMinZ write fBoundsMinZ;
    property BoundsMaxX : TvgScalarS read fBoundsMaxX write fBoundsMaxX;
    property BoundsMaxY : TvgScalarS read fBoundsMaxY write fBoundsMaxY;
    property BoundsMaxZ : TvgScalarS read fBoundsMaxZ write fBoundsMaxZ;
  end;

  {---------------------------------------------------------------------------
    The particle compute pipeline.

    Everything generic about a compute dispatch - shader module, descriptor
    set layout, pool, one set per frame slot, pipeline layout with a push
    constant range, the pipeline, and the dispatch/barrier recording - lives
    in TvgComputeEngine (Vulkan_Components_Compute), which is the descendant
    that fills in the package's TvgBaseComputeEngine.

    What is left here is only what is particular to particles: the GLSL, and
    convenience wrappers that name the three buffers and the push block.
  ---------------------------------------------------------------------------}

  TvgParticleCompute = class(TvgComputeEngine)
  private
    fVertexStrideFloats : Integer;

  protected
    // Supplies the GLSL the base class compiles.
    function GetShaderSource: String; Override;
    function GetLocalSizeX: Integer; Override;

  public
    constructor Create(AOwner: TComponent); Override;

    // The GLSL handed to glslangValidator.  Public and class-level so an
    // application can log it, save it or diff it without a live device.
    class function BuildShaderSource(aVertexStrideFloats: Integer): String; virtual;

    // Build every Vulkan object.  Safe to call once the device exists.
    Procedure BuildPipeline(aFrameCount, aVertexStrideFloats: Integer); reintroduce;

    // Point one frame slot's descriptor set at the three buffers it reads and
    // writes.  Call again if any buffer is recreated.
    Procedure UpdateDescriptorSet(aFrameIndex     : Integer;
                                  aParticleBuffer : TpvVulkanBuffer;
                                  aForceBuffer    : TpvVulkanBuffer;
                                  aVertexBuffer   : TpvVulkanBuffer); reintroduce;

    // Record bind + push constants + dispatch into an already-recording buffer.
    Procedure RecordDispatch(aCommandBuffer : TvgCommandBuffer;
                             aFrameIndex    : Integer;
                             const aPush    : TvgParticlePush;
                             aParticleCount : Integer); reintroduce;

    // Barrier so the vertex stage sees what compute just wrote.
    class Procedure RecordComputeToVertexBarrier(aCommandBuffer : TvgCommandBuffer;
                                                 aVertexBuffer  : TpvVulkanBuffer);

    Property VertexStrideFloats : Integer read fVertexStrideFloats;
  end;

  {---------------------------------------------------------------------------
    The object store the particles are drawn from.

    A plain TvgObjectStore except that its vertex buffers also carry
    STORAGE_BUFFER usage, and once the simulation owns the data the CPU-side
    upload path is switched off so it cannot overwrite what compute wrote.
  ---------------------------------------------------------------------------}

  // How particles are composited.  Additive suits sparks, fire and energy and
  // needs no depth sorting because the result is order independent.  Alpha is
  // correct for smoke and dust but is order dependent, so overlapping
  // particles blend in draw order rather than depth order.
  TvgParticleBlendMode = (pbmAdditive, pbmAlpha);

  TvgParticleStore = class(TvgObjectStore)
  private
    fGPUOwned   : Boolean;
    fBlendMode  : TvgParticleBlendMode;
    fSoftEdge   : Single;
    fRenderIndex: Integer;

    function GetRenderIndex: Integer;
    procedure SetRenderIndex(const Value: Integer);

  protected
    // Enables blending, disables depth writes, and keeps depth testing on so
    // particles are still occluded by solid geometry.
    Procedure ConfigureGraphicPipeline(GP: TvgGraphicPipeline); Override;

    // Draws the slot the simulation last finished rather than the renderer's
    // own frame slot - see RenderIndex.
    Procedure VulkanDraw(aCommandBuffer: TvgCommandBuffer;
                         aPipe: TvgGraphicPipeline;
                         aFrameIndex: TvkUint32;
                         Var CommandCount: Integer); Override;

  public
    constructor Create(AOwner: TComponent); Override;

    // Point size comes from the texcoord attribute the compute shader writes,
    // so every particle is sized individually from its mass and remaining
    // life rather than sharing one constant.
    function GetShaderPointSizeExpression: String; Override;

    // Rounds the point sprite off with a radial falloff across gl_PointCoord,
    // so particles draw as soft discs instead of hard squares.
    function GetShaderFragmentColorExpression(const aSamplerName, aTexCoordName,
                                              aColorName: String): String; Override;

    // Vertex-buffer slot the next draw should read.  -1 (the default) means
    // "use the renderer's own frame index", which is correct for prmInline
    // because the dispatch and the draw share one command buffer.  In
    // prmThreaded the system publishes the slot whose fence has signalled, so
    // the renderer never reads a buffer the compute worker is still writing.
    Property RenderIndex : Integer read GetRenderIndex write SetRenderIndex;

    Function GetDataDirty(aFrameIndex: Integer): Boolean; Override;
    Procedure UploadAllDataUsingCommand(aCmd: TvgCommandBuffer;
                                        aFrameIndex: Integer;
                                        IncBarrier: Boolean = True); Override;

    // Once True the DataStore stops uploading vertex data from its CPU arrays,
    // because the compute shader is now the only writer.
    Property GPUOwned : Boolean read fGPUOwned write fGPUOwned;

    // Compositing mode.  Must be set before the graphic pipeline is built.
    Property BlendMode : TvgParticleBlendMode read fBlendMode write fBlendMode;

    // Fraction of the sprite radius that stays at full opacity before the
    // radial falloff starts.  0 gives a hard-edged disc, 0.5 a pure gradient.
    Property SoftEdge  : Single read fSoftEdge write fSoftEdge;
  end;

  {---------------------------------------------------------------------------
    The system itself
  ---------------------------------------------------------------------------}

  TvgParticleStepEvent = procedure(Sender: TObject; aDeltaTime: Single) of object;

  TvgParticleRunMode = (
    prmInline,    // dispatch is recorded into the frame's own command buffer
    prmThreaded   // a worker submits the dispatch and flags a redraw on the fence
  );

  TvgParticleThread = class;

  TvgParticleSystem = class(TvgBaseComponent)
  private
   //linked
    fStore        : TvgParticleStore;

   //owned
    fCompute      : TvgParticleCompute;
    fEmitter      : TvgParticleEmitter;
    fForces       : TvgForceFields;
    fThread       : TvgParticleThread;

    fParticleCount : Integer;
    fRunMode       : TvgParticleRunMode;
    fElapsedTime   : Single;
    fFixedStep     : Single;
    fStepInterval  : Cardinal;

    fVulkanDevice  : TpvVulkanDevice;
    fCommandPool   : TvgCommandBufferPool;
    fSubmitLock    : TvgCriticalSection;

    fParticleBuffer : TpvVulkanBuffer;
    fForceBuffer    : TpvVulkanBuffer;
    fForceRecs      : TvgForceRecArray;

    fObject        : TvgObject;
    fFrameCount    : Integer;

    // Slot the next dispatch writes.  Advances round robin; the slot whose
    // fence has just signalled is published to fStore.RenderIndex so the
    // renderer only ever draws finished data.
    fWriteIndex    : Integer;
    fSeeded        : Boolean;
    fDescriptorsValid : Boolean;

    fOnStep        : TvgParticleStepEvent;
    fOnRedrawNeeded: TNotifyEvent;

    procedure SetParticleCount(const Value: Integer);
    procedure SetStore(const Value: TvgParticleStore);
    procedure SetRunMode(const Value: TvgParticleRunMode);
    procedure EmitterChanged(Sender: TObject);

    function GetForceCount: Integer;

  protected
    Function SetDisabled : Boolean; Override;
    Function SetEnabled  : Boolean; Override;

    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

    procedure CreateBuffers;
    procedure DestroyBuffers;
    procedure SeedParticles;
    procedure UploadForces;
    procedure RefreshDescriptors;

    function BuildPushConstants(aDeltaTime: Single): TvgParticlePush;

  public
    constructor Create(AOwner: TComponent); Override;
    destructor Destroy; override;

    // Build the store's geometry (one point per particle), create the GPU
    // buffers and the compute pipeline.  Call with the scene already active so
    // a Vulkan device exists.
    Procedure Prepare;

    // prmInline: call from inside frame command-buffer recording, before the
    // render pass begins.
    Procedure RecordStep(aCommandBuffer : TvgCommandBuffer;
                         aFrameIndex    : Integer;
                         aDeltaTime     : Single);

    // prmThreaded: submit one dispatch on its own command buffer and block on
    // its fence, then publish the finished slot for the renderer.  The slot is
    // chosen internally - a caller cannot know which buffer is safe to write.
    // Called by TvgParticleThread, but usable directly.
    Function ExecuteStep(aDeltaTime: Single): Boolean;

    Procedure StartThread;
    Procedure StopThread;

    // Push the current force collection to the GPU.  Called automatically on
    // the next step whenever the collection changes.
    Procedure FlagForcesChanged;

    Property Store         : TvgParticleStore   read fStore   write SetStore;
    Property Compute       : TvgParticleCompute read fCompute;
    Property ParticleBuffer: TpvVulkanBuffer    read fParticleBuffer;
    Property ElapsedTime   : Single             read fElapsedTime;
    Property ForceCount    : Integer            read GetForceCount;
    Property SubmitLock    : TvgCriticalSection read fSubmitLock;

  published
    Property ParticleCount : Integer            read fParticleCount write SetParticleCount default 65536;
    Property RunMode       : TvgParticleRunMode read fRunMode       write SetRunMode       default prmThreaded;

    // Seconds per step when the thread drives the simulation.  0 uses the wall
    // clock delta between steps instead.
    Property FixedStep     : Single             read fFixedStep     write fFixedStep;

    // Milliseconds the worker sleeps between steps.
    Property StepInterval  : Cardinal           read fStepInterval  write fStepInterval default 16;

    Property Emitter       : TvgParticleEmitter read fEmitter;
    Property Forces        : TvgForceFields     read fForces;

    Property OnStep         : TvgParticleStepEvent read fOnStep         write fOnStep;
    Property OnRedrawNeeded : TNotifyEvent         read fOnRedrawNeeded write fOnRedrawNeeded;
  end;

  {---------------------------------------------------------------------------
    Worker thread.

    Submits a dispatch, waits on its fence, then raises OnRedrawNeeded through
    Synchronize so the application can repaint with data it knows is finished.

    NOTE: vkQueueSubmit needs external synchronisation per queue.  This thread
    takes TvgParticleSystem.SubmitLock around its submit; the application must
    take the same lock around its own frame submit/present call.
  ---------------------------------------------------------------------------}

  TvgParticleThread = class(TThread)
  private
    fSystem     : TvgParticleSystem;
    fFrameIndex : Integer;
    fLastTick   : Cardinal;
    fDelta      : Single;

    procedure DoRedraw;

  protected
    procedure Execute; override;

  public
    constructor Create(aSystem: TvgParticleSystem);

    Property FrameIndex : Integer read fFrameIndex write fFrameIndex;
  end;


Implementation

uses
  Winapi.Windows;

{------------------------------------------------------------------------------
  TvgForceField
------------------------------------------------------------------------------}

constructor TvgForceField.Create(Collection: TCollection);
begin
  inherited Create(Collection);

  fName     := Format('Force%d', [Index]);
  fKind     := fkUniform;
  fFalloff  := ffNone;
  fIsOn     := True;

  fOriginX  := 0;
  fOriginY  := 0;
  fOriginZ  := 0;
  fRadius   := 0;      // 0 = unlimited reach

  fVectorX  := 0;
  fVectorY  := -1;     // default is a downward field
  fVectorZ  := 0;
  fStrength := 9.81;
end;

procedure TvgForceField.Assign(Source: TPersistent);
var
  S : TvgForceField;
begin
  if Source is TvgForceField then
  begin
    S := TvgForceField(Source);

    fName     := S.fName;
    fKind     := S.fKind;
    fFalloff  := S.fFalloff;
    fIsOn     := S.fIsOn;
    fOriginX  := S.fOriginX;
    fOriginY  := S.fOriginY;
    fOriginZ  := S.fOriginZ;
    fRadius   := S.fRadius;
    fVectorX  := S.fVectorX;
    fVectorY  := S.fVectorY;
    fVectorZ  := S.fVectorZ;
    fStrength := S.fStrength;

    MarkChanged;
  end else
    inherited Assign(Source);
end;

procedure TvgForceField.MarkChanged;
begin
  if Collection is TvgForceFields then
    TvgForceFields(Collection).IsChanged := True;
end;

function TvgForceField.GetDisplayName: String;
begin
  if fName <> '' then
    Result := fName
  else
    Result := inherited GetDisplayName;
end;

procedure TvgForceField.SetSingleProp(var aField: TvgScalarS; const aValue: TvgScalarS);
begin
  if aField = aValue then Exit;
  aField := aValue;
  MarkChanged;
end;

procedure TvgForceField.SetKind(const Value: TvgForceKind);
begin
  if fKind = Value then Exit;
  fKind := Value;
  MarkChanged;
end;

procedure TvgForceField.SetFalloff(const Value: TvgForceFalloff);
begin
  if fFalloff = Value then Exit;
  fFalloff := Value;
  MarkChanged;
end;

procedure TvgForceField.SetIsOn(const Value: Boolean);
begin
  if fIsOn = Value then Exit;
  fIsOn := Value;
  MarkChanged;
end;

procedure TvgForceField.SetOrigin(const X, Y, Z: TvgScalarS);
begin
  SetSingleProp(fOriginX, X);
  SetSingleProp(fOriginY, Y);
  SetSingleProp(fOriginZ, Z);
end;

procedure TvgForceField.SetVector(const X, Y, Z: TvgScalarS);
begin
  SetSingleProp(fVectorX, X);
  SetSingleProp(fVectorY, Y);
  SetSingleProp(fVectorZ, Z);
end;

function TvgForceField.ToRecord: TvgForceRec;
begin
  FillChar(Result, SizeOf(Result), 0);

  Result.Origin.X := fOriginX;
  Result.Origin.Y := fOriginY;
  Result.Origin.Z := fOriginZ;
  Result.Origin.W := fRadius;

  Result.Vector.X := fVectorX;
  Result.Vector.Y := fVectorY;
  Result.Vector.Z := fVectorZ;
  Result.Vector.W := fStrength;

  Result.Kind    := FixedUInt(Ord(fKind));
  Result.Falloff := FixedUInt(Ord(fFalloff));
  if fIsOn then
    Result.IsOn := 1
  else
    Result.IsOn := 0;
  Result.Pad := 0;
end;

{------------------------------------------------------------------------------
  TvgForceFields
------------------------------------------------------------------------------}

constructor TvgForceFields.Create(aOwner: TPersistent);
begin
  inherited Create(TvgForceField);
  fOwner   := aOwner;
  fChanged := True;
end;

function TvgForceFields.GetOwner: TPersistent;
begin
  Result := fOwner;
end;

procedure TvgForceFields.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  fChanged := True;
end;

function TvgForceFields.GetItem(Index: Integer): TvgForceField;
begin
  Result := TvgForceField(inherited Items[Index]);
end;

procedure TvgForceFields.SetItem(Index: Integer; const Value: TvgForceField);
begin
  inherited SetItem(Index, Value);
end;

function TvgForceFields.Add: TvgForceField;
begin
  Result := TvgForceField(inherited Add);
  fChanged := True;
end;

function TvgForceFields.AddGravity(const X, Y, Z, aStrength: TvgScalarS): TvgForceField;
begin
  Result := Add;
  Result.Name    := 'Gravity';
  Result.Kind    := fkUniform;
  Result.Falloff := ffNone;
  Result.SetVector(X, Y, Z);
  Result.Strength := aStrength;
end;

function TvgForceFields.AddAttractor(const X, Y, Z, aStrength, aRadius: TvgScalarS;
                                     aFalloff: TvgForceFalloff): TvgForceField;
begin
  Result := Add;
  Result.Name    := 'Attractor';
  Result.Kind    := fkPoint;
  Result.Falloff := aFalloff;
  Result.SetOrigin(X, Y, Z);
  Result.Radius   := aRadius;
  Result.Strength := aStrength;
end;

function TvgForceFields.AddDrag(const aStrength: TvgScalarS): TvgForceField;
begin
  Result := Add;
  Result.Name     := 'Drag';
  Result.Kind     := fkDrag;
  Result.Falloff  := ffNone;
  Result.Strength := aStrength;
end;

function TvgForceFields.AddVortex(const X, Y, Z, aAxisX, aAxisY, aAxisZ,
                                        aStrength, aRadius: TvgScalarS): TvgForceField;
begin
  Result := Add;
  Result.Name    := 'Vortex';
  Result.Kind    := fkVortex;
  Result.Falloff := ffLinear;
  Result.SetOrigin(X, Y, Z);
  Result.SetVector(aAxisX, aAxisY, aAxisZ);
  Result.Radius   := aRadius;
  Result.Strength := aStrength;
end;

function TvgForceFields.BuildArray(var aArray: TvgForceRecArray): Integer;
var
  I, C : Integer;
begin
  C := 0;
  for I := 0 to Count - 1 do
    if Items[I].IsOn then
      Inc(C);

  // Always keep at least one slot so the SSBO is never zero sized.
  SetLength(aArray, Max(C, 1));
  FillChar(aArray[0], Length(aArray) * SizeOf(TvgForceRec), 0);

  C := 0;
  for I := 0 to Count - 1 do
    if Items[I].IsOn then
    begin
      aArray[C] := Items[I].ToRecord;
      Inc(C);
    end;

  Result   := C;
  fChanged := False;
end;

{------------------------------------------------------------------------------
  TvgParticleEmitter
------------------------------------------------------------------------------}

constructor TvgParticleEmitter.Create;
begin
  inherited Create;

  // A small box above the origin, particles drifting upward and outward.
  fOriginX := 0;    fOriginY := 0;    fOriginZ := 0;
  fExtentX := 0.25; fExtentY := 0.25; fExtentZ := 0.25;

  fVelMinX := -1.5; fVelMinY :=  2.0; fVelMinZ := -1.5;
  fVelMaxX :=  1.5; fVelMaxY :=  6.0; fVelMaxZ :=  1.5;

  fLifeMin := 2.0;  fLifeMax := 6.0;
  fMassMin := 0.5;  fMassMax := 2.5;

  fColourR := 0.65; fColourG := 0.80; fColourB := 1.00; fColourA := 1.00;
  fColourJitter := 0.25;
  fPointSize    := 6.0;

  fDamping     := 0.10;   // fraction of velocity shed per second
  fRestitution := 0.45;   // energy kept when bouncing off the bounds

  fBoundsMinX := -20; fBoundsMinY := -20; fBoundsMinZ := -20;
  fBoundsMaxX :=  20; fBoundsMaxY :=  20; fBoundsMaxZ :=  20;
end;

procedure TvgParticleEmitter.Assign(Source: TPersistent);
var
  S : TvgParticleEmitter;
begin
  if Source is TvgParticleEmitter then
  begin
    S := TvgParticleEmitter(Source);

    fOriginX := S.fOriginX; fOriginY := S.fOriginY; fOriginZ := S.fOriginZ;
    fExtentX := S.fExtentX; fExtentY := S.fExtentY; fExtentZ := S.fExtentZ;
    fVelMinX := S.fVelMinX; fVelMinY := S.fVelMinY; fVelMinZ := S.fVelMinZ;
    fVelMaxX := S.fVelMaxX; fVelMaxY := S.fVelMaxY; fVelMaxZ := S.fVelMaxZ;
    fLifeMin := S.fLifeMin; fLifeMax := S.fLifeMax;
    fMassMin := S.fMassMin; fMassMax := S.fMassMax;
    fColourR := S.fColourR; fColourG := S.fColourG;
    fColourB := S.fColourB; fColourA := S.fColourA;
    fColourJitter := S.fColourJitter;
    fPointSize    := S.fPointSize;
    fDamping := S.fDamping; fRestitution := S.fRestitution;
    fBoundsMinX := S.fBoundsMinX; fBoundsMinY := S.fBoundsMinY; fBoundsMinZ := S.fBoundsMinZ;
    fBoundsMaxX := S.fBoundsMaxX; fBoundsMaxY := S.fBoundsMaxY; fBoundsMaxZ := S.fBoundsMaxZ;

    Changed;
  end else
    inherited Assign(Source);
end;

procedure TvgParticleEmitter.Changed;
begin
  if Assigned(fOnChange) then
    fOnChange(Self);
end;

procedure TvgParticleEmitter.SetOrigin(const X, Y, Z: TvgScalarS);
begin
  fOriginX := X; fOriginY := Y; fOriginZ := Z;
  Changed;
end;

procedure TvgParticleEmitter.SetExtent(const X, Y, Z: TvgScalarS);
begin
  fExtentX := X; fExtentY := Y; fExtentZ := Z;
  Changed;
end;

procedure TvgParticleEmitter.SetVelocityRange(const MinX, MinY, MinZ, MaxX, MaxY, MaxZ: TvgScalarS);
begin
  fVelMinX := MinX; fVelMinY := MinY; fVelMinZ := MinZ;
  fVelMaxX := MaxX; fVelMaxY := MaxY; fVelMaxZ := MaxZ;
  Changed;
end;

procedure TvgParticleEmitter.SetBounds(const MinX, MinY, MinZ, MaxX, MaxY, MaxZ: TvgScalarS);
begin
  fBoundsMinX := MinX; fBoundsMinY := MinY; fBoundsMinZ := MinZ;
  fBoundsMaxX := MaxX; fBoundsMaxY := MaxY; fBoundsMaxZ := MaxZ;
  Changed;
end;

procedure TvgParticleEmitter.SetColour(const R, G, B, A: TvgScalarS);
begin
  fColourR := R; fColourG := G; fColourB := B; fColourA := A;
  Changed;
end;

{------------------------------------------------------------------------------
  TvgParticleCompute
------------------------------------------------------------------------------}
constructor TvgParticleCompute.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  fVertexStrideFloats := PARTICLE_VERTEX_FLOATS;
end;

function TvgParticleCompute.GetLocalSizeX: Integer;
begin
  Result := PARTICLE_LOCAL_SIZE;
end;

function TvgParticleCompute.GetShaderSource: String;
begin
  Result := BuildShaderSource(fVertexStrideFloats);
end;

class function TvgParticleCompute.BuildShaderSource(aVertexStrideFloats: Integer): String;
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('#version 450');
    SB.AppendLine('');
    SB.AppendLine('layout(local_size_x = ' + IntToStr(PARTICLE_LOCAL_SIZE) + ') in;');
    SB.AppendLine('');
    SB.AppendLine('const uint VERT_FLOATS = ' + IntToStr(aVertexStrideFloats) + 'u;');
    SB.AppendLine('');
    SB.AppendLine('struct Particle {');
    SB.AppendLine('  vec4  posSize;');
    SB.AppendLine('  vec4  velMass;');
    SB.AppendLine('  vec4  colour;');
    SB.AppendLine('  float life;');
    SB.AppendLine('  float maxLife;');
    SB.AppendLine('  uint  seed;');
    SB.AppendLine('  uint  flags;');
    SB.AppendLine('};');
    SB.AppendLine('');
    SB.AppendLine('struct Force {');
    SB.AppendLine('  vec4 origin;');   // xyz origin, w radius
    SB.AppendLine('  vec4 vector;');   // xyz dir/axis, w strength
    SB.AppendLine('  uint kind;');
    SB.AppendLine('  uint falloff;');
    SB.AppendLine('  uint isOn;');
    SB.AppendLine('  uint pad;');
    SB.AppendLine('};');
    SB.AppendLine('');
    SB.AppendLine('layout(std430, set = 0, binding = ' + IntToStr(PB_PARTICLES) + ') buffer ParticleBuf {');
    SB.AppendLine('  Particle particles[];');
    SB.AppendLine('};');
    SB.AppendLine('');
    SB.AppendLine('layout(std430, set = 0, binding = ' + IntToStr(PB_FORCES) + ') readonly buffer ForceBuf {');
    SB.AppendLine('  Force forces[];');
    SB.AppendLine('};');
    SB.AppendLine('');
    SB.AppendLine('layout(std430, set = 0, binding = ' + IntToStr(PB_VERTICES) + ') writeonly buffer VertexBuf {');
    SB.AppendLine('  float verts[];');
    SB.AppendLine('};');
    SB.AppendLine('');
    SB.AppendLine('layout(push_constant) uniform PushBlock {');
    SB.AppendLine('  float dt;');
    SB.AppendLine('  float elapsed;');
    SB.AppendLine('  uint  particleCount;');
    SB.AppendLine('  uint  forceCount;');
    SB.AppendLine('  vec4  emitOrigin;');   // w = damping
    SB.AppendLine('  vec4  emitExtent;');   // w = restitution
    SB.AppendLine('  vec4  velMin;');
    SB.AppendLine('  vec4  velMax;');
    SB.AppendLine('  vec4  boundsMin;');
    SB.AppendLine('  vec4  boundsMax;');
    SB.AppendLine('  vec4  lifeMass;');     // lifeMin, lifeMax, massMin, massMax
    SB.AppendLine('} pc;');
    SB.AppendLine('');
    SB.AppendLine('// xorshift32');
    SB.AppendLine('uint rndNext(inout uint s) {');
    SB.AppendLine('  if (s == 0u) s = 2463534242u;');
    SB.AppendLine('  s ^= s << 13; s ^= s >> 17; s ^= s << 5;');
    SB.AppendLine('  return s;');
    SB.AppendLine('}');
    SB.AppendLine('');
    SB.AppendLine('float rnd01(inout uint s) {');
    SB.AppendLine('  return float(rndNext(s) & 0x00FFFFFFu) / 16777216.0;');
    SB.AppendLine('}');
    SB.AppendLine('');
    SB.AppendLine('float rndRange(inout uint s, float a, float b) {');
    SB.AppendLine('  return a + (b - a) * rnd01(s);');
    SB.AppendLine('}');
    SB.AppendLine('');
    SB.AppendLine('// Give a dead particle a fresh position, velocity, mass and life.');
    SB.AppendLine('void respawn(inout Particle p, uint idx) {');
    SB.AppendLine('  uint s = p.seed ^ (idx * 747796405u) ^ floatBitsToUint(pc.elapsed + 1.0);');
    SB.AppendLine('  p.posSize.xyz = pc.emitOrigin.xyz + vec3(');
    SB.AppendLine('      rndRange(s, -pc.emitExtent.x, pc.emitExtent.x),');
    SB.AppendLine('      rndRange(s, -pc.emitExtent.y, pc.emitExtent.y),');
    SB.AppendLine('      rndRange(s, -pc.emitExtent.z, pc.emitExtent.z));');
    SB.AppendLine('  p.velMass.xyz = vec3(');
    SB.AppendLine('      rndRange(s, pc.velMin.x, pc.velMax.x),');
    SB.AppendLine('      rndRange(s, pc.velMin.y, pc.velMax.y),');
    SB.AppendLine('      rndRange(s, pc.velMin.z, pc.velMax.z));');
    SB.AppendLine('  p.velMass.w = rndRange(s, pc.lifeMass.z, pc.lifeMass.w);');
    SB.AppendLine('  p.maxLife   = rndRange(s, pc.lifeMass.x, pc.lifeMass.y);');
    SB.AppendLine('  p.life      = p.maxLife;');
    SB.AppendLine('  p.seed      = s;');
    SB.AppendLine('  p.flags     = 1u;');
    SB.AppendLine('}');
    SB.AppendLine('');
    SB.AppendLine('vec3 forceAccel(Force f, vec3 pos, vec3 vel, float mass) {');
    SB.AppendLine('  if (f.isOn == 0u) return vec3(0.0);');
    SB.AppendLine('');
    SB.AppendLine('  if (f.kind == 0u) {');
    SB.AppendLine('    // uniform field - already an acceleration, mass independent');
    SB.AppendLine('    return f.vector.xyz * f.vector.w;');
    SB.AppendLine('  }');
    SB.AppendLine('  else if (f.kind == 1u) {');
    SB.AppendLine('    vec3  d  = f.origin.xyz - pos;');
    SB.AppendLine('    float r2 = max(dot(d, d), 1e-6);');
    SB.AppendLine('    float r  = sqrt(r2);');
    SB.AppendLine('    if (f.origin.w > 0.0 && r > f.origin.w) return vec3(0.0);');
    SB.AppendLine('    float atten = 1.0;');
    SB.AppendLine('    if      (f.falloff == 1u) atten = 1.0 / r;');
    SB.AppendLine('    else if (f.falloff == 2u) atten = 1.0 / r2;');
    SB.AppendLine('    return (d / r) * f.vector.w * atten / mass;');
    SB.AppendLine('  }');
    SB.AppendLine('  else if (f.kind == 2u) {');
    SB.AppendLine('    return -vel * f.vector.w / mass;');
    SB.AppendLine('  }');
    SB.AppendLine('  else if (f.kind == 3u) {');
    SB.AppendLine('    vec3 axis = f.vector.xyz;');
    SB.AppendLine('    if (dot(axis, axis) < 1e-8) return vec3(0.0);');
    SB.AppendLine('    axis = normalize(axis);');
    SB.AppendLine('    vec3  d      = pos - f.origin.xyz;');
    SB.AppendLine('    vec3  radial = d - axis * dot(d, axis);');
    SB.AppendLine('    float r      = length(radial);');
    SB.AppendLine('    if (r < 1e-4) return vec3(0.0);');
    SB.AppendLine('    if (f.origin.w > 0.0 && r > f.origin.w) return vec3(0.0);');
    SB.AppendLine('    vec3  tang  = normalize(cross(axis, radial));');
    SB.AppendLine('    float atten = 1.0;');
    SB.AppendLine('    if      (f.falloff == 1u) atten = 1.0 / r;');
    SB.AppendLine('    else if (f.falloff == 2u) atten = 1.0 / (r * r);');
    SB.AppendLine('    return tang * f.vector.w * atten / mass;');
    SB.AppendLine('  }');
    SB.AppendLine('  return vec3(0.0);');
    SB.AppendLine('}');
    SB.AppendLine('');
    SB.AppendLine('void main() {');
    SB.AppendLine('  uint idx = gl_GlobalInvocationID.x;');
    SB.AppendLine('  if (idx >= pc.particleCount) return;');
    SB.AppendLine('');
    SB.AppendLine('  Particle p = particles[idx];');
    SB.AppendLine('');
    SB.AppendLine('  if (p.flags == 0u || p.life <= 0.0) {');
    SB.AppendLine('    respawn(p, idx);');
    SB.AppendLine('  } else {');
    SB.AppendLine('    float mass = max(p.velMass.w, 1e-4);');
    SB.AppendLine('    vec3  acc  = vec3(0.0);');
    SB.AppendLine('    for (uint i = 0u; i < pc.forceCount; ++i)');
    SB.AppendLine('      acc += forceAccel(forces[i], p.posSize.xyz, p.velMass.xyz, mass);');
    SB.AppendLine('');
    SB.AppendLine('    vec3 vel = p.velMass.xyz + acc * pc.dt;');
    SB.AppendLine('    vel *= max(0.0, 1.0 - clamp(pc.emitOrigin.w, 0.0, 1.0) * pc.dt);');
    SB.AppendLine('    vec3 pos = p.posSize.xyz + vel * pc.dt;');
    SB.AppendLine('');
    SB.AppendLine('    float rest = pc.emitExtent.w;');
    SB.AppendLine('    for (int c = 0; c < 3; ++c) {');
    SB.AppendLine('      if (pos[c] < pc.boundsMin[c]) { pos[c] = pc.boundsMin[c]; vel[c] = -vel[c] * rest; }');
    SB.AppendLine('      else if (pos[c] > pc.boundsMax[c]) { pos[c] = pc.boundsMax[c]; vel[c] = -vel[c] * rest; }');
    SB.AppendLine('    }');
    SB.AppendLine('');
    SB.AppendLine('    p.velMass.xyz = vel;');
    SB.AppendLine('    p.posSize.xyz = pos;');
    SB.AppendLine('    p.life        = p.life - pc.dt;');
    SB.AppendLine('  }');
    SB.AppendLine('');
    SB.AppendLine('  particles[idx] = p;');
    SB.AppendLine('');
    SB.AppendLine('  // Render-visible subset straight into the DataStore vertex buffer.');
    SB.AppendLine('  float t = (p.maxLife > 0.0) ? clamp(p.life / p.maxLife, 0.0, 1.0) : 0.0;');
    SB.AppendLine('');
    SB.AppendLine('  // Point size: heavier particles draw larger, and every');
    SB.AppendLine('  // particle shrinks as its life runs down.');
    SB.AppendLine('  float massT = (pc.lifeMass.w > pc.lifeMass.z)');
    SB.AppendLine('              ? clamp((p.velMass.w - pc.lifeMass.z) /');
    SB.AppendLine('                      (pc.lifeMass.w - pc.lifeMass.z), 0.0, 1.0)');
    SB.AppendLine('              : 0.5;');
    SB.AppendLine('  float psize = max(1.0, p.posSize.w * mix(0.6, 1.6, massT) * mix(0.35, 1.0, t));');
    SB.AppendLine('');
    SB.AppendLine('  uint  b = idx * VERT_FLOATS;');
    SB.AppendLine('  verts[b + 0u] = p.posSize.x;');
    SB.AppendLine('  verts[b + 1u] = p.posSize.y;');
    SB.AppendLine('  verts[b + 2u] = p.posSize.z;');
    SB.AppendLine('  verts[b + 3u] = p.colour.r;');
    SB.AppendLine('  verts[b + 4u] = p.colour.g;');
    SB.AppendLine('  verts[b + 5u] = p.colour.b;');
    SB.AppendLine('  verts[b + 6u] = p.colour.a * t;');
    SB.AppendLine('  verts[b + 7u] = psize;');
    SB.AppendLine('  verts[b + 8u] = t;');
    SB.AppendLine('}');

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

Procedure TvgParticleCompute.BuildPipeline(aFrameCount, aVertexStrideFloats: Integer);
begin
  fVertexStrideFloats := Max(aVertexStrideFloats, 4);

  // One descriptor set per frame slot; three storage buffers (particles,
  // forces, render vertices); one push block.
  inherited BuildPipeline(aFrameCount, 3, SizeOf(TvgParticlePush));
end;

Procedure TvgParticleCompute.UpdateDescriptorSet(aFrameIndex     : Integer;
                                                 aParticleBuffer : TpvVulkanBuffer;
                                                 aForceBuffer    : TpvVulkanBuffer;
                                                 aVertexBuffer   : TpvVulkanBuffer);
begin
  // Order must match the binding numbers the GLSL declares.
  inherited UpdateDescriptorSet(aFrameIndex,
                                [aParticleBuffer, aForceBuffer, aVertexBuffer]);
end;

Procedure TvgParticleCompute.RecordDispatch(aCommandBuffer : TvgCommandBuffer;
                                            aFrameIndex    : Integer;
                                            const aPush    : TvgParticlePush;
                                            aParticleCount : Integer);
begin
  if aParticleCount <= 0 then Exit;

  RecordDispatchFor(aCommandBuffer, aFrameIndex, @aPush, aParticleCount);
end;

class Procedure TvgParticleCompute.RecordComputeToVertexBarrier(aCommandBuffer : TvgCommandBuffer;
                                                                aVertexBuffer  : TpvVulkanBuffer);
begin
  RecordBufferBarrier(aCommandBuffer, aVertexBuffer, ccVertexInput);
end;


{------------------------------------------------------------------------------
  TvgParticleStore
------------------------------------------------------------------------------}

constructor TvgParticleStore.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  // The compute shader writes render data straight into these buffers.
  FExtraBufferUsage := TVkBufferUsageFlags(VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);

  // One point per particle.
  Topology := POINT_LIST;

  fGPUOwned    := False;
  fBlendMode   := pbmAdditive;   // order independent, so no depth sorting
  fSoftEdge    := 0.35;
  fRenderIndex := -1;            // follow the renderer's frame index
end;

function TvgParticleStore.GetRenderIndex: Integer;
begin
  // Written by the compute worker, read by the render thread.
  Result := TInterlocked.CompareExchange(fRenderIndex, 0, 0);
end;

procedure TvgParticleStore.SetRenderIndex(const Value: Integer);
begin
  TInterlocked.Exchange(fRenderIndex, Value);
end;

Procedure TvgParticleStore.ConfigureGraphicPipeline(GP: TvgGraphicPipeline);
var
  CB : TvgColorBlendAttachment;
begin
  inherited ConfigureGraphicPipeline(GP);

  if not Assigned(GP) then Exit;

  // -- Blending -------------------------------------------------------------
  // Without this the alpha the compute shader writes is ignored and every
  // particle draws as an opaque square.
  if Assigned(GP.ColorBlending) and (GP.ColorBlending.ColorAttachments.Count > 0) then
  begin
    CB := GP.ColorBlending.ColorAttachments[0];

    CB.BlendEnable := True;
    CB.ColorBlendOp := BO_ADD;
    CB.AlphaBlendOp := BO_ADD;

    case fBlendMode of
      pbmAdditive:
        begin
          // src*srcAlpha + dst.  Order independent, so overlapping particles
          // composite correctly whatever order they are drawn in.
          CB.SrcColorBlendFactor := BF_SRC_ALPHA;
          CB.DstColorBlendFactor := BF_ONE;
          CB.SrcAlphaBlendFactor := BF_ZERO;
          CB.DstAlphaBlendFactor := BF_ONE;
        end;
      pbmAlpha:
        begin
          CB.SrcColorBlendFactor := BF_SRC_ALPHA;
          CB.DstColorBlendFactor := BF_ONE_MINUS_SRC_ALPHA;
          CB.SrcAlphaBlendFactor := BF_ONE;
          CB.DstAlphaBlendFactor := BF_ONE_MINUS_SRC_ALPHA;
        end;
    end;
  end;

  // -- Depth ----------------------------------------------------------------
  // Test against the depth buffer so solid geometry still occludes particles,
  // but do not write depth: a particle must not hide the particles behind it.
  if Assigned(GP.DepthStencil) then
  begin
    GP.DepthStencil.DepthTestEnable  := True;
    GP.DepthStencil.DepthWriteEnable := False;
  end;
end;

Procedure TvgParticleStore.VulkanDraw(aCommandBuffer: TvgCommandBuffer;
                                      aPipe: TvgGraphicPipeline;
                                      aFrameIndex: TvkUint32;
                                      Var CommandCount: Integer);
var
  Slot : Integer;
begin
  Slot := GetRenderIndex;

  // aFrameIndex only selects which per-frame buffer set to bind, so
  // substituting the finished simulation slot is safe.
  if (Slot >= 0) and (Slot < NumFrames) then
    inherited VulkanDraw(aCommandBuffer, aPipe, TvkUint32(Slot), CommandCount)
  else
    inherited VulkanDraw(aCommandBuffer, aPipe, aFrameIndex, CommandCount);
end;

function TvgParticleStore.GetShaderFragmentColorExpression(
  const aSamplerName, aTexCoordName, aColorName: String): String;
var
  Base   : String;
  Inner  : String;
  FS     : TFormatSettings;
begin
  FS := TFormatSettings.Invariant;

  if aColorName <> '' then
    Base := aColorName
  else
    Base := 'vec4(1.0)';

  // Radial falloff over the point sprite: opaque out to SoftEdge, fading to
  // nothing at the sprite's rim.  gl_PointCoord runs 0..1 across the point.
  // Fixed decimals rather than FloatToStr, which would spell a Single out as
  // its full binary expansion (0.349999994039536).
  Inner := Format('%.4f', [Min(Max(fSoftEdge, 0.0), 0.49)], FS);

  Result := 'vec4(' + Base + '.rgb, ' + Base + '.a * (1.0 - smoothstep(' +
            Inner + ', 0.5, length(gl_PointCoord - vec2(0.5)))))';
end;

function TvgParticleStore.GetShaderPointSizeExpression: String;
begin
  // Written by the compute shader into texcoord.x - see BuildShaderSource.
  Result := 'inTexCoord.x';
end;

Function TvgParticleStore.GetDataDirty(aFrameIndex: Integer): Boolean;
begin
  if fGPUOwned then
    Result := False
  else
    Result := inherited GetDataDirty(aFrameIndex);
end;

Procedure TvgParticleStore.UploadAllDataUsingCommand(aCmd: TvgCommandBuffer;
                                                     aFrameIndex: Integer;
                                                     IncBarrier: Boolean);
begin
  // Once the simulation owns the buffers the CPU arrays are stale by design,
  // so uploading them would stamp on what the compute shader just produced.
  if fGPUOwned then Exit;

  inherited UploadAllDataUsingCommand(aCmd, aFrameIndex, IncBarrier);
end;

{------------------------------------------------------------------------------
  TvgParticleSystem
------------------------------------------------------------------------------}

constructor TvgParticleSystem.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  fParticleCount := 65536;
  fRunMode       := prmThreaded;
  fStepInterval  := 16;
  fFixedStep     := 0;
  fElapsedTime   := 0;
  fFrameCount    := 1;
  fSeeded        := False;
  fDescriptorsValid := False;

  fEmitter := TvgParticleEmitter.Create;
  fEmitter.OnChange := EmitterChanged;

  fForces  := TvgForceFields.Create(Self);

  fCompute := TvgParticleCompute.Create(Self);
  fCompute.SetSubComponent(True);
  fCompute.Name := 'ParticleCompute';

  fSubmitLock := TvgCriticalSection.Create;
end;

destructor TvgParticleSystem.Destroy;
begin
  StopThread;
  DestroyBuffers;

  if Assigned(fSubmitLock) then FreeAndNil(fSubmitLock);
  if Assigned(fForces)     then FreeAndNil(fForces);
  if Assigned(fEmitter)    then FreeAndNil(fEmitter);

  inherited;
end;

procedure TvgParticleSystem.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);

  if (Operation = opRemove) and (AComponent = fStore) then
  begin
    StopThread;
    fStore := nil;
    fDescriptorsValid := False;
  end;
end;

procedure TvgParticleSystem.SetStore(const Value: TvgParticleStore);
begin
  if fStore = Value then Exit;

  if Assigned(fStore) then
    fStore.RemoveFreeNotification(Self);

  fStore := Value;
  fDescriptorsValid := False;

  if Assigned(fStore) then
    fStore.FreeNotification(Self);
end;

procedure TvgParticleSystem.SetParticleCount(const Value: Integer);
var
  V : Integer;
begin
  V := Max(Value, PARTICLE_LOCAL_SIZE);
  if fParticleCount = V then Exit;

  fParticleCount := V;
  fSeeded := False;
  fDescriptorsValid := False;
end;

procedure TvgParticleSystem.SetRunMode(const Value: TvgParticleRunMode);
begin
  if fRunMode = Value then Exit;
  StopThread;
  fRunMode := Value;

  // Inline draws the frame it just simulated; threaded draws the last slot
  // the system published.
  if Assigned(fStore) and (fRunMode = prmInline) then
    fStore.RenderIndex := -1;
end;

procedure TvgParticleSystem.EmitterChanged(Sender: TObject);
begin
  // Emitter values are pushed every step, so nothing to invalidate.
end;

function TvgParticleSystem.GetForceCount: Integer;
begin
  if Assigned(fForces) then
    Result := fForces.Count
  else
    Result := 0;
end;

Procedure TvgParticleSystem.FlagForcesChanged;
begin
  if Assigned(fForces) then
    fForces.IsChanged := True;
end;

Function TvgParticleSystem.SetEnabled: Boolean;
begin
  Result := Assigned(fStore) and Assigned(fParticleBuffer);
end;

Function TvgParticleSystem.SetDisabled: Boolean;
begin
  StopThread;
  Result := True;
end;

procedure TvgParticleSystem.CreateBuffers;
var
  Size : TVkDeviceSize;
begin
  CustomAssert(Assigned(fVulkanDevice), 'Particle system: Vulkan device not available', Self);

  DestroyBuffers;

  // Simulation state - device local, only compute ever touches it.
  Size := TVkDeviceSize(fParticleCount) * SizeOf(TvgParticle);

  fParticleBuffer := TpvVulkanBuffer.Create(fVulkanDevice,
                       Size,
                       TVkBufferUsageFlags(VK_BUFFER_USAGE_STORAGE_BUFFER_BIT) or
                       TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_DST_BIT),
                       VK_SHARING_MODE_EXCLUSIVE,
                       [],
                       TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
                       0, 0, 0, 0, 0, 0, 0,
                       [TpvVulkanBufferFlag.OwnSingleMemoryChunk]);

  // Force structures - small, host visible so they can be refreshed cheaply
  // whenever the collection changes.
  fForces.BuildArray(fForceRecs);
  Size := TVkDeviceSize(Length(fForceRecs)) * SizeOf(TvgForceRec);

  fForceBuffer := TpvVulkanBuffer.Create(fVulkanDevice,
                     Size,
                     TVkBufferUsageFlags(VK_BUFFER_USAGE_STORAGE_BUFFER_BIT) or
                     TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_DST_BIT),
                     VK_SHARING_MODE_EXCLUSIVE,
                     [],
                     TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) or
                     TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
                     0, 0, 0, 0, 0, 0, 0,
                     [TpvVulkanBufferFlag.PersistentMapped]);
end;

procedure TvgParticleSystem.DestroyBuffers;
begin
  if Assigned(fParticleBuffer) then FreeAndNil(fParticleBuffer);
  if Assigned(fForceBuffer)    then FreeAndNil(fForceBuffer);
  fDescriptorsValid := False;
  fSeeded           := False;
end;

procedure TvgParticleSystem.SeedParticles;
var
  Data : TvgParticleArray;
  I    : Integer;
  E    : TvgParticleEmitter;
  J    : Single;
  Cmd  : TvgCommandBuffer;

  function Rnd(const A, B: Single): Single;
  begin
    Result := A + (B - A) * Random;
  end;

begin
  CustomAssert(Assigned(fParticleBuffer), 'Particle system: particle buffer not created', Self);

  E := fEmitter;
  SetLength(Data, fParticleCount);

  for I := 0 to fParticleCount - 1 do
  begin
    FillChar(Data[I], SizeOf(TvgParticle), 0);

    Data[I].PosSize.X := Rnd(E.OriginX - E.ExtentX, E.OriginX + E.ExtentX);
    Data[I].PosSize.Y := Rnd(E.OriginY - E.ExtentY, E.OriginY + E.ExtentY);
    Data[I].PosSize.Z := Rnd(E.OriginZ - E.ExtentZ, E.OriginZ + E.ExtentZ);
    Data[I].PosSize.W := E.PointSize;    // base size, scaled per step by mass and life

    Data[I].VelMass.X := Rnd(E.VelMinX, E.VelMaxX);
    Data[I].VelMass.Y := Rnd(E.VelMinY, E.VelMaxY);
    Data[I].VelMass.Z := Rnd(E.VelMinZ, E.VelMaxZ);
    Data[I].VelMass.W := Rnd(E.MassMin, E.MassMax);      // random mass

    J := E.ColourJitter;
    Data[I].Colour.X := Min(1.0, Max(0.0, E.ColourR + Rnd(-J, J)));
    Data[I].Colour.Y := Min(1.0, Max(0.0, E.ColourG + Rnd(-J, J)));
    Data[I].Colour.Z := Min(1.0, Max(0.0, E.ColourB + Rnd(-J, J)));
    Data[I].Colour.W := E.ColourA;

    Data[I].MaxLife := Rnd(E.LifeMin, E.LifeMax);        // random life

    // Stagger the initial lives so particles do not all die on the same step.
    Data[I].Life  := Data[I].MaxLife * Random;
    Data[I].Seed  := FixedUInt(Random(MaxInt)) or 1;
    Data[I].Flags := PF_ALIVE;
  end;

  Cmd := fCommandPool.AcquireUploadCommand(0);
  CustomAssert(Assigned(Cmd), 'Particle system: could not acquire an upload command', Self);

  fParticleBuffer.UploadData(fVulkanDevice.TransferQueue,
                             Cmd.VulkanCommandBuffer,
                             Cmd.BufferFence,
                             Data[0],
                             0,
                             TVkDeviceSize(fParticleCount) * SizeOf(TvgParticle));

  fSeeded := True;
end;

procedure TvgParticleSystem.UploadForces;
var
  Size : TVkDeviceSize;
begin
  if not Assigned(fForceBuffer) then Exit;

  fForces.BuildArray(fForceRecs);
  Size := TVkDeviceSize(Length(fForceRecs)) * SizeOf(TvgForceRec);

  // Host visible and persistently mapped, so a straight update is enough.
  if Size <= fForceBuffer.Size then
    fForceBuffer.UpdateData(fForceRecs[0], 0, Size);
end;

procedure TvgParticleSystem.RefreshDescriptors;
var
  I  : Integer;
  VB : TpvVulkanBuffer;
begin
  CustomAssert(Assigned(fStore), 'Particle system: store not assigned', Self);

  for I := 0 to fFrameCount - 1 do
  begin
    VB := fStore.GetVulkanVertexBuffer(I);
    CustomAssert(Assigned(VB), 'Particle system: DataStore vertex buffer not created', Self);

    fCompute.UpdateDescriptorSet(I, fParticleBuffer, fForceBuffer, VB);
  end;

  fDescriptorsValid := True;
end;

Procedure TvgParticleSystem.Prepare;
var
  I      : Integer;
  Obj    : TvgObject;
  Stride : Cardinal;
  Floats : Integer;
begin
  CustomAssert(Assigned(fStore), 'Particle system: Store must be assigned before Prepare', Self);

  fVulkanDevice := fStore.Scene.GetVulkanDevice;
  CustomAssert(Assigned(fVulkanDevice), 'Particle system: scene has no Vulkan device yet', Self);

  fFrameCount := fStore.NumFrames;
  if fFrameCount < 1 then fFrameCount := 1;

  // In prmThreaded the worker writes one slot while the renderer draws the
  // previously published one, and the renderer may still hold an earlier slot
  // in flight.  With fewer than three slots the write pointer can catch the
  // buffer the renderer is reading, which shows up as torn or stale
  // particles.  prmInline has no such constraint, because the dispatch and
  // the draw share a command buffer.
  if (fRunMode = prmThreaded) and (fFrameCount < 3) then
    raise EvgParticleException.CreateFmt(
      'Particle system: RunMode prmThreaded needs at least 3 frames in ' +
      'flight but the DataStore has %d.  Either raise the frame count, or ' +
      'set RunMode := prmInline and call RecordStep from the frame command ' +
      'buffer.', [fFrameCount]);

  // One vertex per particle: position for placement, colour for shading, and
  // texcoord carrying (point size, life ratio) so the point sprite can be
  // sized per particle rather than by a single constant.
  fStore.SetupVertexAttributes([vdtPosition, vdtColor, vdtTexCoord]);
  fStore.SetIndexType(itNONE);

  Obj := fStore.AddObject(False);
  Obj.AllocateVertices(fParticleCount, amClear);
  fObject := Obj;

  // Opt this object out of frustum culling.  Once GPUOwned is set the compute
  // shader is the only writer of the vertex positions, so the bounding box
  // the DataStore accumulates from CPU writes describes the seed positions at
  // best and nothing at all at worst - it would cull the simulation the
  // moment the particles moved out of where they started.
  //
  // Particles can be culled again by calling
  // TvgVulkanDataStore.SetObjectBounds with a box the emitter and forces
  // cannot carry a particle outside of; that switches the object to cmManual
  // and the bounds are then honoured as given.
  fStore.SetObjectCullMode(Obj.ObjIndex, cmNever);

  fStore.CreateVulkanDataBuffers;

  Stride := fStore.GetStride(BINDING_VERTEX);
  CustomAssert(Stride mod SizeOf(Single) = 0,
               'Particle system: vertex stride is not a whole number of floats', Self);
  Floats := Stride div SizeOf(Single);

  // Command pool used for the seeding upload and, in threaded mode, for the
  // dispatch submissions.
  if not Assigned(fCommandPool) then
  begin
    fCommandPool := TvgCommandBufferPool.Create(Self);
    fCommandPool.Device          := fStore.Scene.ScreenDevice;
    fCommandPool.QueueFamilyType := VGT_GRAPHIC;
    fCommandPool.QueueCreateFlags := [CP_RESET_COMMAND_BUFFER];
    fCommandPool.SetUpBufferArrays(fFrameCount);
    fCommandPool.Active := True;
  end;

  CreateBuffers;

  fCompute.SetDevice(fVulkanDevice);
  fCompute.BuildPipeline(fFrameCount, Floats);

  SeedParticles;
  UploadForces;
  RefreshDescriptors;

  // From here the GPU is the only writer of the vertex data.
  fStore.GPUOwned := True;

  // The vertex buffers are device local and have never been written, so prime
  // every frame slot with one tiny step.  Without this a frame presented
  // before the first real dispatch would draw uninitialised memory.
  fWriteIndex := 0;
  for I := 0 to fFrameCount - 1 do
    ExecuteStep(0.001);

  // prmInline records the dispatch into the frame's own command buffer, so
  // the draw must read that same frame's slot rather than a published one.
  if fRunMode = prmInline then
    fStore.RenderIndex := -1;
end;

function TvgParticleSystem.BuildPushConstants(aDeltaTime: Single): TvgParticlePush;
var
  E : TvgParticleEmitter;
begin
  E := fEmitter;

  FillChar(Result, SizeOf(Result), 0);

  Result.DeltaTime     := aDeltaTime;
  Result.ElapsedTime   := fElapsedTime;
  Result.ParticleCount := FixedUInt(fParticleCount);
  Result.ForceCount    := FixedUInt(Length(fForceRecs));

  Result.EmitOrigin.X := E.OriginX;
  Result.EmitOrigin.Y := E.OriginY;
  Result.EmitOrigin.Z := E.OriginZ;
  Result.EmitOrigin.W := E.Damping;

  Result.EmitExtent.X := E.ExtentX;
  Result.EmitExtent.Y := E.ExtentY;
  Result.EmitExtent.Z := E.ExtentZ;
  Result.EmitExtent.W := E.Restitution;

  Result.VelMin.X := E.VelMinX;
  Result.VelMin.Y := E.VelMinY;
  Result.VelMin.Z := E.VelMinZ;

  Result.VelMax.X := E.VelMaxX;
  Result.VelMax.Y := E.VelMaxY;
  Result.VelMax.Z := E.VelMaxZ;

  Result.BoundsMin.X := E.BoundsMinX;
  Result.BoundsMin.Y := E.BoundsMinY;
  Result.BoundsMin.Z := E.BoundsMinZ;

  Result.BoundsMax.X := E.BoundsMaxX;
  Result.BoundsMax.Y := E.BoundsMaxY;
  Result.BoundsMax.Z := E.BoundsMaxZ;

  Result.LifeMass.X := E.LifeMin;
  Result.LifeMass.Y := E.LifeMax;
  Result.LifeMass.Z := E.MassMin;
  Result.LifeMass.W := E.MassMax;
end;

Procedure TvgParticleSystem.RecordStep(aCommandBuffer : TvgCommandBuffer;
                                       aFrameIndex    : Integer;
                                       aDeltaTime     : Single);
var
  Push : TvgParticlePush;
  VB   : TpvVulkanBuffer;
begin
  if not Assigned(fStore) or not Assigned(fParticleBuffer) then Exit;
  if aDeltaTime <= 0 then Exit;

  if fForces.IsChanged then
  begin
    UploadForces;
    fDescriptorsValid := False;
  end;

  if not fDescriptorsValid then
    RefreshDescriptors;

  fElapsedTime := fElapsedTime + aDeltaTime;

  Push := BuildPushConstants(aDeltaTime);

  fCompute.RecordDispatch(aCommandBuffer, aFrameIndex, Push, fParticleCount);

  VB := fStore.GetVulkanVertexBuffer(aFrameIndex);
  TvgParticleCompute.RecordComputeToVertexBarrier(aCommandBuffer, VB);

  if Assigned(fOnStep) then
    fOnStep(Self, aDeltaTime);
end;

Function TvgParticleSystem.ExecuteStep(aDeltaTime: Single): Boolean;
var
  Cmd  : TvgCommandBuffer;
  Slot : Integer;
begin
  Result := False;

  if not Assigned(fStore) or not Assigned(fParticleBuffer) then Exit;
  if not Assigned(fCommandPool) then Exit;
  if aDeltaTime <= 0 then Exit;

  fSubmitLock.Enter;
  try
    Slot := fWriteIndex;

    // AcquireUploadCommand already prepares and activates the buffer.
    Cmd := fCommandPool.AcquireUploadCommand(TvkUint32(Slot));
    if not Assigned(Cmd) then Exit;

    Cmd.BeginRecording(TVkCommandBufferUsageFlags(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT));

    RecordStep(Cmd, Slot, aDeltaTime);

    Cmd.EndRecording;

    // Submit and block until the GPU has finished the step, so the slot we
    // publish below is known to hold complete vertex data.
    Cmd.ExecuteCommand(fVulkanDevice.GraphicsQueue,
                       TVkPipelineStageFlags(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT),
                       nil,
                       nil,
                       True,
                       True);

    // Hand this slot to the renderer and move on to the next one.  The
    // renderer keeps drawing the slot published here until the next step
    // finishes, so it never reads the buffer being written.
    fStore.RenderIndex := Slot;

    fWriteIndex := Slot + 1;
    if fWriteIndex >= fFrameCount then
      fWriteIndex := 0;

    Result := True;
  finally
    fSubmitLock.Leave;
  end;
end;

Procedure TvgParticleSystem.StartThread;
begin
  if fRunMode <> prmThreaded then Exit;
  if Assigned(fThread) then Exit;

  fThread := TvgParticleThread.Create(Self);
end;

Procedure TvgParticleSystem.StopThread;
begin
  if not Assigned(fThread) then Exit;

  fThread.Terminate;
  fThread.WaitFor;
  FreeAndNil(fThread);
end;

{------------------------------------------------------------------------------
  TvgParticleThread
------------------------------------------------------------------------------}

constructor TvgParticleThread.Create(aSystem: TvgParticleSystem);
begin
  fSystem     := aSystem;
  fFrameIndex := 0;
  fLastTick   := GetTickCount;

  FreeOnTerminate := False;

  inherited Create(False);
end;

procedure TvgParticleThread.DoRedraw;
begin
  if Assigned(fSystem) and Assigned(fSystem.OnRedrawNeeded) then
    fSystem.OnRedrawNeeded(fSystem);
end;

procedure TvgParticleThread.Execute;
var
  Now_    : Cardinal;
  Elapsed : Cardinal;
begin
  NameThreadForDebugging('vgParticleCompute');

  while not Terminated do
  begin
    Now_    := GetTickCount;
    Elapsed := Now_ - fLastTick;      // wraps correctly on Cardinal arithmetic
    fLastTick := Now_;

    if fSystem.FixedStep > 0 then
      fDelta := fSystem.FixedStep
    else
      fDelta := Elapsed / 1000.0;

    // Clamp so a stall does not fling every particle out of the bounds.
    if fDelta > 0.1 then fDelta := 0.1;

    if fDelta > 0 then
    begin
      try
        // The system picks the slot; a free-running counter here would have
        // no relationship to the buffer the renderer is about to read.
        if fSystem.ExecuteStep(fDelta) then
          // The fence has signalled and the finished slot has been published,
          // so the data is complete: ask for a repaint.
          Synchronize(DoRedraw);
      except
        // A failed step must not take the thread down; the next tick retries.
      end;
    end;

    if Terminated then Break;

    Sleep(fSystem.StepInterval);
  end;
end;

end.
