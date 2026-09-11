unit Vulkan_Components_DataStore;

{------------------------------------------------------------------------------
  Vulkan_Components_DataStore.pas - REFACTORED VERSION
  A simplified data store and Vulkan buffer manager for vertex and instance data.
  
  KEY SIMPLIFICATIONS:
  - Fixed binding scheme: Binding 0 = Vertices, Binding 1 = Instances
  - Single interleaved buffer per binding type
  - Objects track simple start/count ranges
  - Direct array access instead of dictionary lookups
  - Removed multi-vertex-set and multi-index-set complexity
------------------------------------------------------------------------------}

Interface
uses
  SysUtils,
  System.classes,
  System.Math,
  System.SyncObjs,
  Generics.Collections,
  Vulkan,
  PasVulkan.Framework,
  PasVulkan.Types,
  PasVulkan.Math,
  Vulkan_Assert,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_Camera,      // TvgAABB - per-object bounds for culling
  Vulkan_Components_Descriptors;

const
  // Data size constants
  SIZE_VEC1       = 4;
  SIZE_VEC2       = 8;
  SIZE_VEC3       = 12;
  SIZE_VEC4       = 16;
  SIZE_MAT4       = 64;
  SIZE_VECINT1    = 4;
  SIZE_VECINT2    = 8;
  SIZE_VECUINT1   = 4;
  SIZE_VECUINT2   = 8;
  SIZE_UINT16     = 2;
  SIZE_UINT32     = 4;

  // Fixed binding assignments
  BINDING_VERTEX   = 0;
  BINDING_INSTANCE = 1;
  
  INVALIDBINDING   = High(Cardinal);
  NO_INDEX_SET     = -1;

type

  TGLSLAttributeInfo = record
    GLSLType: string;
    GLSLName: string;
  end;


  TvgVertexDataType = (vdtPosition,
                       vdtColor,
                       vdtNormal,
                       vdtTexCoord,
                       vdtTangent,
                       vdtBiTangent,
                       vdtIndex);
  TVertexDataTypes = set of TvgVertexDataType;

  TInstanceDataType = (idtObjID,
                       idtColor,
                       idtNormal,
                       idtTangent,
                       idtVector,
                       idtMatrix,
                       idtIndex);
  TInstanceDataTypes = set of TInstanceDataType;

  TIndexType = (itUInt16, itUInt32, itNONE);

  TAllocationMode = (amClear, amPreserve, amUninitialized);

  { How an object's bounding box is obtained, and therefore whether the
    object can be frustum culled at all.

    cmAuto MUST be the first value: TvgVulkanObjectRecord is created with
    FillChar, so the zero value is what a new object gets. }
  TvgObjectCullMode = (
    cmAuto,     // bounds accumulated from the vertex positions the CPU writes
    cmNever,    // always drawn - for geometry whose bounds the CPU cannot know
    cmManual    // bounds supplied by the application via SetObjectBounds
  );

  // Simplified object record - just tracks ranges
  TvgVulkanObjectRecord = record
    VertexStart,
    VertexCount    : Integer;

    InstanceStart,
    InstanceCount  : Integer;

    IndexStart,
    IndexCount     : Integer;

    IndexType      : TIndexType;
    HasInstances   : Boolean;

    // --- Frustum culling -----------------------------------------------
    // LocalBounds encloses the vertex positions as written, in whatever
    // space they were authored in.  This draw path has no per-object model
    // matrix, so for a non-instanced object that space IS world space and
    // WorldBounds is simply a copy.
    //
    // WorldBounds is what culling actually tests.  For an instanced object
    // carrying idtMatrix it is the union of LocalBounds transformed by every
    // instance matrix; for cmManual it is whatever the application supplied.
    //
    // BoundsDirty means WorldBounds needs rebuilding from LocalBounds and the
    // instance matrices.  Recomputation is deferred rather than done on every
    // vertex write, so building a mesh stays O(1) per vertex.
    LocalBounds    : TvgAABB;
    WorldBounds    : TvgAABB;
    CullMode       : TvgObjectCullMode;
    BoundsDirty    : Boolean;
  end;

  TVulkanBufferInfo = record
    Buffer          : TpvVulkanBuffer;
    Memory          : TpvVulkanDeviceMemoryBlock;
    Size            : TVkDeviceSize;
    Mapped          : Boolean;
  end;

  TTransferState = (tsIdle, tsTransferring, tsCompleted);

  TvgVulkanDataStore = class(TvgBaseObjectStore)
  private
    FCriticalSection    : TCriticalSection;
    FDataObjects        : TList<TvgVulkanObjectRecord>;

    // Vertex attribute configuration (set once during setup)
    FVertexTypes        : TVertexDataTypes;
    FVertexOffsets      : array[TvgVertexDataType] of Cardinal;
    FVertexLocations    : array[TvgVertexDataType] of Cardinal;
    FVertexStride       : Cardinal;

    // Instance attribute configuration (set once during setup)
    FInstanceTypes      : TInstanceDataTypes;
    FInstanceOffsets    : array[TInstanceDataType] of Cardinal;
    FInstanceLocations  : array[TInstanceDataType] of Cardinal;
    FInstanceStride     : Cardinal;

    // Single buffers for all data
    FVertexData         : TBytes;
    FVertexCount        : Integer;
    FVertexCapacity     : Integer;
    
    FInstanceData       : TBytes;
    FInstanceCount      : Integer;
    FInstanceCapacity   : Integer;
    
    FIndexData          : TBytes;
    FIndexCount         : Integer;
    FIndexCapacity      : Integer;
    FIndexType          : TIndexType;

    FNumFrames         : Integer;
    FDataDirty         : TArray<Boolean>;
    FBuffersCreated    : Boolean;
    FTransferState     : TTransferState;
    FValidateWrites    : Boolean;

    StageBufferList    : TList<TpvVulkanBuffer>;


    // Helper methods
    procedure EnsureVertexCapacity(ARequiredCount: Integer);
    procedure EnsureInstanceCapacity(ARequiredCount: Integer);
    procedure EnsureIndexCapacity(ARequiredCount: Integer);

    procedure CreateVulkanBuffer(aDevice: TpvVulkanDevice;
                                 ASize: TVkDeviceSize;
                                 AUsage: TVkBufferUsageFlags;
                                 AMemoryProperties: TVkMemoryPropertyFlags;
                                 out ABufferInfo: TVulkanBufferInfo);

    procedure DestroyVulkanBuffer(var ABufferInfo: TVulkanBufferInfo);

    procedure SetFrameCount(const Value: Integer);

    // Generic data setters (work on global indices)
    procedure SetVertexAttributeData(AIndex: Integer; ADataType: TvgVertexDataType; const AData);
    procedure SetInstanceAttributeData(AIndex: Integer; ADataType: TInstanceDataType; const AData);


    procedure ComputeLayout;
    function GetIndexElementSize(AType: TIndexType): Cardinal;

    { Reads one instance's idtMatrix attribute straight out of FInstanceData.
      TvgMatrix4x4S and TpvMatrix4x4 share a layout - both are 16 singles
      indexed RawComponents[column, row] - so this is a plain copy.
      CALLER MUST HOLD FCriticalSection. }
    function  GetInstanceMatrix(AGlobalInstanceIndex: Integer): TpvMatrix4x4;

    { Rebuilds WorldBounds from LocalBounds and the object's instance
      matrices, and clears BoundsDirty.  Does nothing for cmManual, whose
      WorldBounds belongs to the application.
      CALLER MUST HOLD FCriticalSection. }
    procedure RecomputeWorldBounds(ObjectIndex: Integer);

  protected

    // Vulkan resources
    FVulkanDevice      : TpvVulkanDevice;

    // Extra VkBufferUsageFlags OR'd into the vertex/instance buffers created by
    // CreateVulkanDataBuffers.  Descendants that let a compute shader write
    // straight into the render buffers set this to
    // VK_BUFFER_USAGE_STORAGE_BUFFER_BIT before the buffers are created.
    // See TvgParticleStore in Vulkan_Components_Particles.
    FExtraBufferUsage  : TVkBufferUsageFlags;

    FVertexBuffers     : TArray<TVulkanBufferInfo>;    // Per frame
    FInstanceBuffers   : TArray<TVulkanBufferInfo>;    // Per frame
    FIndexBuffers      : TArray<TVulkanBufferInfo>;    // Per frame

    Procedure SetEnabled; Override;
    Procedure SetDisabled; Override;

    function GetObjectCount: Integer; Override;

    Procedure UpdateGraphicPipeBindingAndAttributeDescriptions(aPipe:TvgGraphicPipeline);


    Procedure VulkanDraw(aCommandBuffer: TvgCommandBuffer;
                         aPipe: TvgGraphicPipeline;
                         aFrameIndex: TvkUint32;
                         Var CommandCount: Integer); Override;

  public
    constructor Create(AOwner: TComponent);  Override;
    destructor Destroy; override;

    // Configuration (call before adding data)
    function SetupVertexAttributes(ATypes: TVertexDataTypes)    : TvgVulkanDataStore;
    function SetupInstanceAttributes(ATypes: TInstanceDataTypes): TvgVulkanDataStore;
    procedure SetIndexType(AType: TIndexType);

    // Object management
    function AddDataObject(IncludeInstance: Boolean): Integer;
    procedure ClearAll(AClearVulkanBuffers: Boolean = True);
    procedure SetDataDirty;

    // Allocation for objects
    procedure AllocateVertices(ObjectIndex, ACount: Integer; AMode:  TAllocationMode = amClear);
    procedure AllocateInstances(ObjectIndex, ACount: Integer; AMode: TAllocationMode = amClear);
    procedure AllocateIndices(ObjectIndex, ACount: Integer; AMode:   TAllocationMode = amClear);

    // Adding elements (returns global index)
    function AddObjectVertex(ObjectIndex: Integer): Integer;
    function AddObjectInstance(ObjectIndex: Integer): Integer;
    function AddObjectIndex(ObjectIndex: Integer; IndexValue: Cardinal): Integer;
    procedure AddObjectTriangle(ObjectIndex: Integer; I1, I2, I3: Cardinal);

    // Setters using object + local index
    procedure SetObjectVertexPosition(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
    procedure SetObjectVertexColor(ObjectIndex, LocalIndex: Integer; R, G, B, A: Single);
    procedure SetObjectVertexNormal(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
    procedure SetObjectVertexTexCoord(ObjectIndex, LocalIndex: Integer; U, V: Single);
    procedure SetObjectVertexTangent(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
    procedure SetObjectVertexBiTangent(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
    procedure SetObjectVertexIndex(ObjectIndex, LocalIndex: Integer; I: Cardinal);

    procedure SetObjectInstanceObjID(ObjectIndex, LocalIndex: Integer; ID1, ID2: Cardinal);
    procedure SetObjectInstanceColor(ObjectIndex, LocalIndex: Integer; R, G, B, A: Single);
    procedure SetObjectInstanceNormal(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
    procedure SetObjectInstanceTangent(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
    procedure SetObjectInstanceVector(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
    procedure SetObjectInstanceMatrix(ObjectIndex, LocalIndex: Integer; M: TvgMatrix4x4S);
    procedure SetObjectInstanceIndex(ObjectIndex, LocalIndex: Integer; I: Cardinal);

    procedure SetObjectIndex(ObjectIndex, LocalIndex: Integer; AValue: Cardinal);
    procedure SetObjectTriangle(ObjectIndex, TriangleIndex: Integer; I1, I2, I3: Cardinal);

    // --- Frustum culling -------------------------------------------------

    { Selects how this object's bounds are obtained; see TvgObjectCullMode.
      Set cmNever for geometry a compute shader writes, where the CPU's
      idea of the vertex positions is stale or absent - particles being the
      case in this package. }
    procedure SetObjectCullMode(ObjectIndex: Integer; AMode: TvgObjectCullMode);
    function  GetObjectCullMode(ObjectIndex: Integer): TvgObjectCullMode;

    { Supplies world-space bounds directly and switches the object to
      cmManual, so they are used as given and never recomputed from vertex
      data.  The way to cull geometry the CPU does not author. }
    procedure SetObjectBounds(ObjectIndex: Integer; const AMin, AMax: TpvVector3);

    { World-space bounds used for culling, rebuilt first if stale.  Returns
      an invalid (empty) box when the object has no usable bounds, which
      vgFrustumTestAABB treats as visible - never culled by accident. }
    function  GetObjectWorldBounds(ObjectIndex: Integer): TvgAABB;

    { Bounds of the vertex positions as written, before instancing. }
    function  GetObjectLocalBounds(ObjectIndex: Integer): TvgAABB;

    // Getters
    function GetObjectVertexStart(ObjectIndex: Integer): Integer;
    function GetObjectVertexCount(ObjectIndex: Integer): Integer;
    function GetObjectInstanceStart(ObjectIndex: Integer): Integer;
    function GetObjectInstanceCount(ObjectIndex: Integer): Integer;
    function GetObjectIndexStart(ObjectIndex: Integer): Integer;
    function GetObjectIndexCount(ObjectIndex: Integer): Integer;

    function GetBindingDescriptions: TArray<TVkVertexInputBindingDescription>;
    function GetAttributeDescriptions: TArray<TVkVertexInputAttributeDescription>;
    function GetStride(Binding: Cardinal): Cardinal;

    Function IsInstanceTypeSet(aInstanceType:TInstanceDataType):Boolean;

    // Vulkan buffer management
    Procedure CreateVulkanDataBuffers; Override;
    Procedure DeleteVulkanDataBuffers; Override;

    Procedure UploadAllData(aPool: TvgCommandBufferPool; aFrameIndex: Integer); Override;
    Procedure UploadAllDataUsingCommand(aCmd: TvgCommandBuffer; aFrameIndex: Integer; IncBarrier: Boolean = True); Override;

    Procedure UploadResourceDataToVulkan(aPool: TvgCommandBufferPool; aFrameIndex, aSubPassIndex: Integer); Override;
    Procedure BindObjectResources(aCommandBuf: TvgCommandBuffer; aWorkerIndex, aSubPassIndex, aSetValue: TvkUint32); Override;
    Function GetDataDirty(aFrameIndex: Integer): Boolean; Override;

    function GetVulkanVertexBuffer(AFrameIndex: Integer): TpvVulkanBuffer;
    function GetVulkanInstanceBuffer(AFrameIndex: Integer): TpvVulkanBuffer;
    function GetVulkanIndexBuffer(AFrameIndex: Integer): TpvVulkanBuffer;

    // GLSL generation
    function WriteGLSLHeader: string; Override;
    function GetShaderVertexPositionExpression( const aPositionName: String): String; Override;

    // Pipeline updates

    Procedure UpdateGraphicPipeline(aPipe: TvgGraphicPipeline); Override;
    Procedure SetBaseScene(aBaseScene: TvgBaseScene); Override;

    property ValidateWrites: Boolean read FValidateWrites write FValidateWrites;
    property BuffersCreated: Boolean read fBuffersCreated;
    property NumFrames: Integer read FNumFrames write SetFrameCount;

  end;

  EVulkanDataStoreException = class(Exception);

// Helper functions
function GetVertexFormat(ADataType: TvgVertexDataType): TVkFormat;
function GetInstanceFormat(ADataType: TInstanceDataType): TVkFormat;
function GetVertexSize(ADataType: TvgVertexDataType): Cardinal;
function GetInstanceSize(ADataType: TInstanceDataType): Cardinal;
function GetGLSLVertexType(ADataType: TvgVertexDataType): TGLSLAttributeInfo;
function GetGLSLInstanceType(ADataType: TInstanceDataType): TGLSLAttributeInfo;

implementation

{ Helper Functions }

function GetVertexFormat(ADataType: TvgVertexDataType): TVkFormat;
begin
  case ADataType of
    vdtPosition: Result  := VK_FORMAT_R32G32B32_SFLOAT;
    vdtColor: Result     := VK_FORMAT_R32G32B32A32_SFLOAT;
    vdtNormal: Result    := VK_FORMAT_R32G32B32_SFLOAT;
    vdtTexCoord: Result  := VK_FORMAT_R32G32_SFLOAT;
    vdtTangent: Result   := VK_FORMAT_R32G32B32_SFLOAT;
    vdtBiTangent: Result := VK_FORMAT_R32G32B32_SFLOAT;
    vdtIndex: Result     := VK_FORMAT_R32_UINT;
  else
    raise EVulkanDataStoreException.CreateFmt('Unknown vertex data type: %d', [Ord(ADataType)]);
  end;
end;

function GetInstanceFormat(ADataType: TInstanceDataType): TVkFormat;
begin
  case ADataType of
    idtObjID: Result   := VK_FORMAT_R32G32_UINT;
    idtColor: Result   := VK_FORMAT_R32G32B32A32_SFLOAT;
    idtNormal: Result  := VK_FORMAT_R32G32B32_SFLOAT;
    idtTangent: Result := VK_FORMAT_R32G32B32_SFLOAT;
    idtVector: Result  := VK_FORMAT_R32G32B32_SFLOAT;
    idtIndex: Result   := VK_FORMAT_R32_UINT;
    idtMatrix: Result  := VK_FORMAT_R32G32B32A32_SFLOAT; // Per column
  else
    raise EVulkanDataStoreException.CreateFmt('Unknown instance data type: %d', [Ord(ADataType)]);
  end;
end;

function GetVertexSize(ADataType: TvgVertexDataType): Cardinal;
begin
  case ADataType of
    vdtPosition:   Result := SIZE_VEC3;
    vdtColor:      Result := SIZE_VEC4;
    vdtNormal:     Result := SIZE_VEC3;
    vdtTexCoord:   Result := SIZE_VEC2;
    vdtTangent:    Result := SIZE_VEC3;
    vdtBiTangent:  Result := SIZE_VEC3;
    vdtIndex:      Result := SIZE_VECUINT1;
  else
    raise EVulkanDataStoreException.CreateFmt('Unknown vertex data type: %d', [Ord(ADataType)]);
  end;
end;

function GetInstanceSize(ADataType: TInstanceDataType): Cardinal;
begin
  case ADataType of
    idtObjID:    Result := SIZE_VECUINT2;
    idtColor:    Result := SIZE_VEC4;
    idtNormal:   Result := SIZE_VEC3;
    idtTangent:  Result := SIZE_VEC3;
    idtVector:   Result := SIZE_VEC3;
    idtIndex:    Result := SIZE_UINT32;
    idtMatrix:   Result := SIZE_MAT4; // 64 bytes for mat4
  else
    raise EVulkanDataStoreException.CreateFmt('Unknown instance data type: %d', [Ord(ADataType)]);
  end;
end;

function GetGLSLVertexType(ADataType: TvgVertexDataType): TGLSLAttributeInfo;
begin
  case ADataType of
    vdtPosition: begin Result.GLSLType := 'vec3'; Result.GLSLName := 'inPosition'; end;
    vdtColor: begin Result.GLSLType := 'vec4'; Result.GLSLName := 'inColor'; end;
    vdtNormal: begin Result.GLSLType := 'vec3'; Result.GLSLName := 'inNormal'; end;
    vdtTexCoord: begin Result.GLSLType := 'vec2'; Result.GLSLName := 'inTexCoord'; end;
    vdtTangent: begin Result.GLSLType := 'vec3'; Result.GLSLName := 'inTangent'; end;
    vdtBiTangent: begin Result.GLSLType := 'vec3'; Result.GLSLName := 'inBiTangent'; end;
    vdtIndex: begin Result.GLSLType := 'uint'; Result.GLSLName := 'inIndex'; end;
  else
    raise Exception.Create('Unknown vertex attribute for GLSL');
  end;
end;

function GetGLSLInstanceType(ADataType: TInstanceDataType): TGLSLAttributeInfo;
begin
  case ADataType of
    idtObjID: begin Result.GLSLType := 'uvec2'; Result.GLSLName := 'inObjID'; end;
    idtColor: begin Result.GLSLType := 'vec4'; Result.GLSLName := 'inInstanceColor'; end;
    idtNormal: begin Result.GLSLType := 'vec3'; Result.GLSLName := 'inInstanceNormal'; end;
    idtTangent: begin Result.GLSLType := 'vec3'; Result.GLSLName := 'inInstanceTangent'; end;
    idtVector: begin Result.GLSLType := 'vec3'; Result.GLSLName := 'inInstanceVector'; end;
    idtIndex: begin Result.GLSLType := 'uint'; Result.GLSLName := 'inInstanceIndex'; end;
    idtMatrix: begin Result.GLSLType := 'mat4'; Result.GLSLName := 'inInstanceMatrix'; end;
  else
    raise Exception.Create('Unknown instance attribute for GLSL');
  end;
end;

function GetVertexAttributeType(ADataType: TvgVertexDataType): TvgAttributeType;
begin
  case ADataType of
    vdtPosition:  Result := AT_POSITION;
    vdtColor:     Result := AT_COLOR;
    vdtNormal:    Result := AT_NORMAL;
    vdtTexCoord:  Result := AT_TEXTURE;
    vdtTangent:   Result := AT_TANGENT;
    vdtBiTangent: Result := AT_BITANGENT;
    vdtIndex:     Result := AT_INDEX;
  else
    raise EVulkanDataStoreException.CreateFmt(
      'Unknown vertex attribute semantic: %d', [Ord(ADataType)]);
  end;
end;

function GetInstanceAttributeType(ADataType: TInstanceDataType): TvgAttributeType;
begin
  case ADataType of
    idtObjID:   Result := AT_OBJID;
    idtColor:   Result := AT_COLOR;
    idtNormal:  Result := AT_NORMAL;
    idtTangent: Result := AT_TANGENT;
    idtVector:  Result := AT_VECTOR;
    idtMatrix:  Result := AT_MATRIX;
    idtIndex:   Result := AT_INDEX;
  else
    raise EVulkanDataStoreException.CreateFmt(
      'Unknown instance attribute semantic: %d', [Ord(ADataType)]);
  end;
end;

function GetDataTypeForFormat(AFormat: TVkFormat): TvgDataType;
begin
  case AFormat of
    VK_FORMAT_R32_SINT:             Result := DT_IVEC1;
    VK_FORMAT_R32G32_SINT:          Result := DT_IVEC2;
    VK_FORMAT_R32G32B32_SINT:       Result := DT_IVEC3;
    VK_FORMAT_R32_UINT:             Result := DT_UVEC1;
    VK_FORMAT_R32G32_UINT:          Result := DT_UVEC2;
    VK_FORMAT_R32G32B32_UINT:       Result := DT_UVEC3;
    VK_FORMAT_R32_SFLOAT:           Result := DT_VEC1;
    VK_FORMAT_R32G32_SFLOAT:        Result := DT_VEC2;
    VK_FORMAT_R32G32B32_SFLOAT:     Result := DT_VEC3;
    VK_FORMAT_R32G32B32A32_SFLOAT:  Result := DT_VEC4;
  else
    raise EVulkanDataStoreException.CreateFmt(
      'Unsupported shader attribute format: %d', [Ord(AFormat)]);
  end;
end;

{ TvgVulkanDataStore }

constructor TvgVulkanDataStore.Create(AOwner: TComponent);
begin
  inherited Create(aOwner);
  
  FCriticalSection := TCriticalSection.Create;
  FDataObjects     := TList<TvgVulkanObjectRecord>.Create;
  StageBufferList  := TList<TpvVulkanBuffer>.Create;
  
  FVertexTypes    := [];
  FInstanceTypes  := [];
  FVertexStride   := 0;
  FInstanceStride := 0;
  
  FVertexCount      := 0;
  FVertexCapacity   := 0;
  FInstanceCount    := 0;
  FInstanceCapacity := 0;
  FIndexCount       := 0;
  FIndexCapacity    := 0;
  FIndexType        := itUInt32;
  
  FVulkanDevice     := nil;
  FBuffersCreated   := False;
  FTransferState    := tsIdle;
  FValidateWrites   := True;
  
  //MUST track the frames-in-flight count used by TvgLinker/TvgFrame.
  //If this is smaller, the highest frame index has no vertex/instance/index
  //buffer, its upload raises (and is swallowed by the worker) and its draw is
  //recorded with nothing bound - which presents as a blank frame.
  FNumFrames := Integer(MaxFramesInFlight);
  SetLength(FDataDirty, FNumFrames);
end;

destructor TvgVulkanDataStore.Destroy;
var
  I: Integer;
  SB: TpvVulkanBuffer;
begin
  DeleteVulkanDataBuffers;
  
  if Assigned(StageBufferList) then
  begin
    for I := 0 to StageBufferList.Count - 1 do
    begin
      SB := StageBufferList[I];
      if Assigned(SB) then
        SB.Free;
    end;
    StageBufferList.Free;
  end;
  
  FDataObjects.Free;
  FCriticalSection.Free;
  
  inherited;
end;

procedure TvgVulkanDataStore.SetFrameCount(const Value: Integer);
begin

  if Value <> FNumFrames then
  begin
    FNumFrames := Value;
    SetLength(FDataDirty, FNumFrames);
    if FBuffersCreated then
    begin
      DeleteVulkanDataBuffers;
    //  CreateVulkanDataBuffers;
    end;
  end;

end;


procedure TvgVulkanDataStore.SetEnabled;
//var
 // I : Integer;
 // R : TvgBaseRenderEngine;
 // D : TpvVulkanDevice;
begin
  inherited;
  fActive := True;

  // Only update FVulkanDevice if we don't already have a live one.
  // This preserves the existing device when a second renderer connects
  // to the same device (no-op), and picks up the new device when the
  // store is reconnected after the previous device was freed.
  if Assigned(FVulkanDevice) then exit;  // still valid from a prior renderer

  if not Assigned(fBaseScene) then exit;
  if not Assigned(fBaseScene.RendererList) then exit;

end;

procedure TvgVulkanDataStore.SetDisabled;
var
  I: Integer;
  SB: TpvVulkanBuffer;
begin
  // Always delete device-local buffers if they were created.
  // DeleteVulkanDataBuffers itself guards on FBuffersCreated and clears it.
  if FBuffersCreated then
    DeleteVulkanDataBuffers;

  // Free all staging buffers owned by this store.
  if Assigned(StageBufferList) and (StageBufferList.Count > 0) then
  begin
    for I := 0 to StageBufferList.Count - 1 do
    begin
      SB := StageBufferList[I];
      if Assigned(SB) then
        SB.Free;
    end;
    StageBufferList.Clear;
  end;

  // Drop the device reference; CPU-side arrays are kept so a reconnect
  // can re-upload them.
  FVulkanDevice := nil;

  inherited;
end;

function TvgVulkanDataStore.GetObjectCount: Integer;
begin
  FCriticalSection.Enter;
  try
    Result := FDataObjects.Count;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.SetupVertexAttributes(ATypes: TVertexDataTypes): TvgVulkanDataStore;
begin
  FCriticalSection.Enter;
  try
    if FVertexCount > 0 then
      raise EVulkanDataStoreException.Create('Cannot change vertex attributes after data has been added');
      
    FVertexTypes := ATypes;
    ComputeLayout;
    Result := Self;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.SetupInstanceAttributes(ATypes: TInstanceDataTypes): TvgVulkanDataStore;
begin
  FCriticalSection.Enter;
  try
    if FInstanceCount > 0 then
      raise EVulkanDataStoreException.Create('Cannot change instance attributes after data has been added');
      
    FInstanceTypes := ATypes;
    ComputeLayout;
    Result := Self;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetIndexType(AType: TIndexType);
begin
  FCriticalSection.Enter;
  try
    if FIndexCount > 0 then
      raise EVulkanDataStoreException.Create('Cannot change index type after indices have been added');
      
    FIndexType := AType;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.ComputeLayout;
const
  Alignment = 16; // Standard alignment for vertex data
var
  VType: TvgVertexDataType;
  IType: TInstanceDataType;
  CurrentOffset: Cardinal;
  Location: Cardinal;
begin
  // Compute vertex layout
  CurrentOffset := 0;
  Location := 0;
  
  for VType := Low(TvgVertexDataType) to High(TvgVertexDataType) do
  begin
    if VType in FVertexTypes then
    begin
      FVertexOffsets[VType] := CurrentOffset;
      FVertexLocations[VType] := Location;
      Inc(CurrentOffset, GetVertexSize(VType));
      Inc(Location);
    end
    else
    begin
      FVertexOffsets[VType]   := INVALIDBINDING;
      FVertexLocations[VType] := INVALIDBINDING;
    end;
  end;
  
  FVertexStride := CurrentOffset;
  if (FVertexStride > 0) and (FVertexStride mod Alignment <> 0) then
    FVertexStride := ((FVertexStride div Alignment) + 1) * Alignment;

  // Compute instance layout
  CurrentOffset := 0;
  
  for IType := Low(TInstanceDataType) to High(TInstanceDataType) do
  begin
    if IType in FInstanceTypes then
    begin
      FInstanceOffsets[IType] := CurrentOffset;
      FInstanceLocations[IType] := Location;
      Inc(CurrentOffset, GetInstanceSize(IType));
      
      // Matrix takes 4 consecutive locations
      if IType = idtMatrix then
        Inc(Location, 4)
      else
        Inc(Location);
    end
    else
    begin
      FInstanceOffsets[IType]   := INVALIDBINDING;
      FInstanceLocations[IType] := INVALIDBINDING;
    end;
  end;
  
  FInstanceStride := CurrentOffset;
  if (FInstanceStride > 0) and (FInstanceStride mod Alignment <> 0) then
    FInstanceStride := ((FInstanceStride div Alignment) + 1) * Alignment;
end;

function TvgVulkanDataStore.AddDataObject(IncludeInstance: Boolean): Integer;
var
  Obj: TvgVulkanObjectRecord;
begin
  FCriticalSection.Enter;
  try
    // The FillChar already leaves the culling fields correct: both boxes read
    // as empty (TvgAABB.Valid False), CullMode is cmAuto, and BoundsDirty is
    // False because there is nothing yet to rebuild from.  An empty box is
    // treated as visible, so an object is drawn until it has real bounds.
    FillChar(Obj, SizeOf(Obj), 0);
    Obj.VertexStart   := -1;
    Obj.InstanceStart := -1;
    Obj.IndexStart    := -1;
    Obj.HasInstances  := IncludeInstance;
    Obj.IndexType     := FIndexType;

    Result := FDataObjects.Add(Obj);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.ClearAll(AClearVulkanBuffers: Boolean);
begin
  FCriticalSection.Enter;
  try
    if AClearVulkanBuffers then
      DeleteVulkanDataBuffers;

    FDataObjects.Clear;
    FVertexCount := 0;
    FInstanceCount := 0;
    FIndexCount := 0;
    SetLength(FVertexData, 0);
    SetLength(FInstanceData, 0);
    SetLength(FIndexData, 0);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.EnsureVertexCapacity(ARequiredCount: Integer);
var
  NewCapacity: Integer;
begin
  if ARequiredCount <= FVertexCapacity then
    Exit;

  NewCapacity := FVertexCapacity;
  if NewCapacity < 16 then
    NewCapacity := 16;
    
  while NewCapacity < ARequiredCount do
    NewCapacity := NewCapacity * 2;
    
  FVertexCapacity := NewCapacity;
  SetLength(FVertexData, FVertexCapacity * Integer(FVertexStride));
end;

procedure TvgVulkanDataStore.EnsureInstanceCapacity(ARequiredCount: Integer);
var
  NewCapacity: Integer;
begin
  if ARequiredCount <= FInstanceCapacity then
    Exit;
    
  NewCapacity := FInstanceCapacity;
  if NewCapacity < 16 then
    NewCapacity := 16;
    
  while NewCapacity < ARequiredCount do
    NewCapacity := NewCapacity * 2;
    
  FInstanceCapacity := NewCapacity;
  SetLength(FInstanceData, FInstanceCapacity * Integer(FInstanceStride));
end;

procedure TvgVulkanDataStore.EnsureIndexCapacity(ARequiredCount: Integer);
var
  NewCapacity: Integer;
  ElementSize: Integer;
begin
  if ARequiredCount <= FIndexCapacity then
    Exit;
    
  NewCapacity := FIndexCapacity;
  if NewCapacity < 16 then
    NewCapacity := 16;
    
  while NewCapacity < ARequiredCount do
    NewCapacity := NewCapacity * 2;
    
  FIndexCapacity := NewCapacity;
  ElementSize := GetIndexElementSize(FIndexType);
  SetLength(FIndexData, FIndexCapacity * ElementSize);
end;

function TvgVulkanDataStore.GetIndexElementSize(AType: TIndexType): Cardinal;
begin
  case AType of
    itUInt16: Result := SIZE_UINT16;
    itUInt32: Result := SIZE_UINT32;
    itNONE: Result := 0;
  else
    Result := SIZE_UINT32;
  end;
end;

procedure TvgVulkanDataStore.AllocateVertices(ObjectIndex, ACount: Integer; AMode: TAllocationMode);
var
  Obj: TvgVulkanObjectRecord;
  NewStart: Integer;
  I, GlobalIndex: Integer;
begin
  FCriticalSection.Enter;
  try
    if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then
      raise EVulkanDataStoreException.CreateFmt('Invalid object index: %d', [ObjectIndex]);
      
    Obj := FDataObjects[ObjectIndex];
    
    if Obj.VertexStart >= 0 then
      raise EVulkanDataStoreException.Create('Object already has vertices allocated');
      
    NewStart := FVertexCount;
    EnsureVertexCapacity(FVertexCount + ACount);
    
    Obj.VertexStart := NewStart;
    Obj.VertexCount := ACount;

    // Fresh storage holds no authored geometry yet, whatever AMode put in it,
    // so any bound carried over from before would be describing vertices that
    // no longer exist.  Start empty and let the position writes rebuild it.
    Obj.LocalBounds.Reset;
    Obj.BoundsDirty := True;

    FDataObjects[ObjectIndex] := Obj;

    Inc(FVertexCount, ACount);

    // Clear data if requested
    if AMode = amClear then
    begin
      for I := 0 to ACount - 1 do
      begin
        GlobalIndex := NewStart + I;
        FillChar(FVertexData[GlobalIndex * Integer(FVertexStride)], FVertexStride, 0);
      end;
    end;
    
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.AllocateInstances(ObjectIndex, ACount: Integer; AMode: TAllocationMode);
var
  Obj: TvgVulkanObjectRecord;
  NewStart: Integer;
  I, GlobalIndex: Integer;
begin
  FCriticalSection.Enter;
  try
    if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then
      raise EVulkanDataStoreException.CreateFmt('Invalid object index: %d', [ObjectIndex]);
      
    Obj := FDataObjects[ObjectIndex];
    
    if not Obj.HasInstances then
      raise EVulkanDataStoreException.Create('Object was not created with instance support');
      
    if Obj.InstanceStart >= 0 then
      raise EVulkanDataStoreException.Create('Object already has instances allocated');
      
    NewStart := FInstanceCount;
    EnsureInstanceCapacity(FInstanceCount + ACount);
    
    Obj.InstanceStart := NewStart;
    Obj.InstanceCount := ACount;

    // Instance count feeds the world bound, so it has to be rebuilt.
    Obj.BoundsDirty := True;

    FDataObjects[ObjectIndex] := Obj;

    Inc(FInstanceCount, ACount);
    
    if AMode = amClear then
    begin
      for I := 0 to ACount - 1 do
      begin
        GlobalIndex := NewStart + I;
        FillChar(FInstanceData[GlobalIndex * Integer(FInstanceStride)], FInstanceStride, 0);
      end;
    end;
    
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.AllocateIndices(ObjectIndex, ACount: Integer; AMode: TAllocationMode);
var
  Obj: TvgVulkanObjectRecord;
  NewStart: Integer;
  I, GlobalIndex: Integer;
  ElementSize: Integer;
begin
  FCriticalSection.Enter;
  try
    if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then
      raise EVulkanDataStoreException.CreateFmt('Invalid object index: %d', [ObjectIndex]);
      
    Obj := FDataObjects[ObjectIndex];
    
    if Obj.IndexStart >= 0 then
      raise EVulkanDataStoreException.Create('Object already has indices allocated');
      
    NewStart := FIndexCount;
    EnsureIndexCapacity(FIndexCount + ACount);
    
    Obj.IndexStart := NewStart;
    Obj.IndexCount := ACount;
    FDataObjects[ObjectIndex] := Obj;
    
    Inc(FIndexCount, ACount);
    
    if AMode = amClear then
    begin
      ElementSize := GetIndexElementSize(FIndexType);
      for I := 0 to ACount - 1 do
      begin
        GlobalIndex := NewStart + I;
        FillChar(FIndexData[GlobalIndex * ElementSize], ElementSize, 0);
      end;
    end;
    
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.AddObjectVertex(ObjectIndex: Integer): Integer;
var
  Obj: TvgVulkanObjectRecord;
begin
  FCriticalSection.Enter;
  try
    if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then
      raise EVulkanDataStoreException.CreateFmt('Invalid object index: %d', [ObjectIndex]);
      
    Obj := FDataObjects[ObjectIndex];
    
    if Obj.VertexStart < 0 then
    begin
      // Auto-allocate first vertex
      AllocateVertices(ObjectIndex, 1, amClear);
      Obj := FDataObjects[ObjectIndex];
      Result := 0; // Local index
    end
    else
    begin
      // Grow allocation
      Inc(Obj.VertexCount);
      EnsureVertexCapacity(FVertexCount + 1);
      Inc(FVertexCount);
      FDataObjects[ObjectIndex] := Obj;
      Result := Obj.VertexCount - 1; // Local index
    end;
    
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.AddObjectInstance(ObjectIndex: Integer): Integer;
var
  Obj: TvgVulkanObjectRecord;
begin
  FCriticalSection.Enter;
  try
    if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then
      raise EVulkanDataStoreException.CreateFmt('Invalid object index: %d', [ObjectIndex]);

    Obj := FDataObjects[ObjectIndex];

    if not Obj.HasInstances then
      raise EVulkanDataStoreException.Create('Object was not created with instance support');


    if Obj.InstanceStart < 0 then
    begin
      AllocateInstances(ObjectIndex, 1, amClear);
      Obj    := FDataObjects[ObjectIndex];
      Result := 0;
    end
    else
    begin
      Inc(Obj.InstanceCount);
      EnsureInstanceCapacity(FInstanceCount + 1);
      Inc(FInstanceCount);
      FDataObjects[ObjectIndex] := Obj;
      Result := Obj.InstanceCount - 1;
    end;
    
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.AddObjectIndex(ObjectIndex: Integer; IndexValue: Cardinal): Integer;
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  ElementSize: Integer;
  Offset: Integer;
begin
  FCriticalSection.Enter;
  try
    if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then
      raise EVulkanDataStoreException.CreateFmt('Invalid object index: %d', [ObjectIndex]);
      
    Obj := FDataObjects[ObjectIndex];
    
    if Obj.IndexStart < 0 then
    begin
      AllocateIndices(ObjectIndex, 1, amClear);
      Obj := FDataObjects[ObjectIndex];
      Result := 0;
    end
    else
    begin
      Inc(Obj.IndexCount);
      EnsureIndexCapacity(FIndexCount + 1);
      Inc(FIndexCount);
      FDataObjects[ObjectIndex] := Obj;
      Result := Obj.IndexCount - 1;
    end;
    
    // Write the index value
    GlobalIndex := Obj.IndexStart + Result;
    ElementSize := GetIndexElementSize(FIndexType);
    Offset := GlobalIndex * ElementSize;
    
    case FIndexType of
      itUInt16: PWord(@FIndexData[Offset])^     := Word(IndexValue);
      itUInt32: PCardinal(@FIndexData[Offset])^ := IndexValue;
    end;
    
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.AddObjectTriangle(ObjectIndex: Integer; I1, I2, I3: Cardinal);
begin
  AddObjectIndex(ObjectIndex, I1);
  AddObjectIndex(ObjectIndex, I2);
  AddObjectIndex(ObjectIndex, I3);
end;

procedure TvgVulkanDataStore.SetVertexAttributeData(AIndex: Integer; ADataType: TvgVertexDataType; const AData);
var
  Offset: Integer;
  Size: Cardinal;
begin
  if not (ADataType in FVertexTypes) then
    raise EVulkanDataStoreException.Create('Vertex attribute type not configured');
    
  if (AIndex < 0) or (AIndex >= FVertexCount) then
    raise EVulkanDataStoreException.CreateFmt('Invalid vertex index: %d', [AIndex]);
    
  Offset := AIndex * Integer(FVertexStride) + Integer(FVertexOffsets[ADataType]);
  Size   := GetVertexSize(ADataType);
  
  Move(AData, FVertexData[Offset], Size);
end;

procedure TvgVulkanDataStore.SetInstanceAttributeData(AIndex: Integer; ADataType: TInstanceDataType; const AData);
var
  Offset: Integer;
  Size: Cardinal;
begin
  if not (ADataType in FInstanceTypes) then
    raise EVulkanDataStoreException.Create('Instance attribute type not configured');
    
  if (AIndex < 0) or (AIndex >= FInstanceCount) then
    raise EVulkanDataStoreException.CreateFmt('Invalid instance index: %d', [AIndex]);
    
  Offset := AIndex * Integer(FInstanceStride) + Integer(FInstanceOffsets[ADataType]);
  Size := GetInstanceSize(ADataType);
  
  Move(AData, FInstanceData[Offset], Size);
end;

{ Object-based setters }

procedure TvgVulkanDataStore.SetObjectVertexPosition(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  Data: array[0..2] of Single;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    if (LocalIndex < 0) or (LocalIndex >= Obj.VertexCount) then
      raise EVulkanDataStoreException.CreateFmt('Invalid local vertex index: %d', [LocalIndex]);
      
    GlobalIndex := Obj.VertexStart + LocalIndex;
    Data[0] := X; Data[1] := Y; Data[2] := Z;
    SetVertexAttributeData(GlobalIndex, vdtPosition, Data);

    // This is the ONLY path that writes a vertex position, so accumulating
    // the bound here keeps it correct for free and costs O(1) per vertex -
    // no rescanning FVertexData later.
    //
    // Note this tracks positions that are actually WRITTEN.  Vertices left
    // at their allocation value (amClear zeroes them) are not included, so a
    // partially written allocation is bounded by its real geometry rather
    // than being dragged out to the origin.  The unwritten remainder is
    // degenerate and draws nothing visible.
    Obj.LocalBounds.GrowPoint(X, Y, Z);
    Obj.BoundsDirty := True;
    FDataObjects[ObjectIndex] := Obj;

    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectVertexColor(ObjectIndex, LocalIndex: Integer; R, G, B, A: Single);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  Data: array[0..3] of Single;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.VertexStart + LocalIndex;
    Data[0] := R; Data[1] := G; Data[2] := B; Data[3] := A;
    SetVertexAttributeData(GlobalIndex, vdtColor, Data);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectVertexNormal(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  Data: array[0..2] of Single;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.VertexStart + LocalIndex;
    Data[0] := X; Data[1] := Y; Data[2] := Z;
    SetVertexAttributeData(GlobalIndex, vdtNormal, Data);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectVertexTexCoord(ObjectIndex, LocalIndex: Integer; U, V: Single);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  Data: array[0..1] of Single;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.VertexStart + LocalIndex;
    Data[0] := U; Data[1] := V;
    SetVertexAttributeData(GlobalIndex, vdtTexCoord, Data);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectVertexTangent(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  Data: array[0..2] of Single;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.VertexStart + LocalIndex;
    Data[0] := X; Data[1] := Y; Data[2] := Z;
    SetVertexAttributeData(GlobalIndex, vdtTangent, Data);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectVertexBiTangent(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  Data: array[0..2] of Single;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.VertexStart + LocalIndex;
    Data[0] := X; Data[1] := Y; Data[2] := Z;
    SetVertexAttributeData(GlobalIndex, vdtBiTangent, Data);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectVertexIndex(ObjectIndex, LocalIndex: Integer; I: Cardinal);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.VertexStart + LocalIndex;
    SetVertexAttributeData(GlobalIndex, vdtIndex, I);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectInstanceObjID(ObjectIndex, LocalIndex: Integer; ID1, ID2: Cardinal);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  Data: array[0..1] of Cardinal;
begin
  FCriticalSection.Enter;
  try
    Obj         := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.InstanceStart + LocalIndex;
    Data[0]     := ID1;
    Data[1]     := ID2;
    SetInstanceAttributeData(GlobalIndex, idtObjID, Data);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectInstanceColor(ObjectIndex, LocalIndex: Integer; R, G, B, A: Single);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  Data: array[0..3] of Single;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.InstanceStart + LocalIndex;
    Data[0] := R; Data[1] := G; Data[2] := B; Data[3] := A;
    SetInstanceAttributeData(GlobalIndex, idtColor, Data);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectInstanceNormal(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  Data: array[0..2] of Single;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.InstanceStart + LocalIndex;
    Data[0] := X; Data[1] := Y; Data[2] := Z;
    SetInstanceAttributeData(GlobalIndex, idtNormal, Data);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectInstanceTangent(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  Data: array[0..2] of Single;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.InstanceStart + LocalIndex;
    Data[0] := X; Data[1] := Y; Data[2] := Z;
    SetInstanceAttributeData(GlobalIndex, idtTangent, Data);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectInstanceVector(ObjectIndex, LocalIndex: Integer; X, Y, Z: Single);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  Data: array[0..2] of Single;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.InstanceStart + LocalIndex;
    Data[0] := X; Data[1] := Y; Data[2] := Z;
    SetInstanceAttributeData(GlobalIndex, idtVector, Data);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectInstanceMatrix(ObjectIndex, LocalIndex: Integer; M: TvgMatrix4x4S);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.InstanceStart + LocalIndex;
    SetInstanceAttributeData(GlobalIndex, idtMatrix, M);

    // Where an instance sits is part of where the object sits, so the world
    // bound no longer holds.  Flagged rather than recomputed: a caller
    // setting a thousand instance matrices should pay for one rebuild, not
    // a thousand.
    Obj.BoundsDirty := True;
    FDataObjects[ObjectIndex] := Obj;

    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectInstanceIndex(ObjectIndex, LocalIndex: Integer; I: Cardinal);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    GlobalIndex := Obj.InstanceStart + LocalIndex;
    SetInstanceAttributeData(GlobalIndex, idtIndex, I);
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectIndex(ObjectIndex, LocalIndex: Integer; AValue: Cardinal);
var
  Obj: TvgVulkanObjectRecord;
  GlobalIndex: Integer;
  ElementSize: Integer;
  Offset: Integer;
begin
  FCriticalSection.Enter;
  try
    Obj := FDataObjects[ObjectIndex];
    if (LocalIndex < 0) or (LocalIndex >= Obj.IndexCount) then
      raise EVulkanDataStoreException.CreateFmt('Invalid local index: %d', [LocalIndex]);
      
    GlobalIndex := Obj.IndexStart + LocalIndex;
    ElementSize := GetIndexElementSize(FIndexType);
    Offset := GlobalIndex * ElementSize;
    
    case FIndexType of
      itUInt16: PWord(@FIndexData[Offset])^ := Word(AValue);
      itUInt32: PCardinal(@FIndexData[Offset])^ := AValue;
    end;
    
    SetDataDirty;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectTriangle(ObjectIndex, TriangleIndex: Integer; I1, I2, I3: Cardinal);
var
  BaseIndex: Integer;
begin
  BaseIndex := TriangleIndex * 3;
  SetObjectIndex(ObjectIndex, BaseIndex, I1);
  SetObjectIndex(ObjectIndex, BaseIndex + 1, I2);
  SetObjectIndex(ObjectIndex, BaseIndex + 2, I3);
end;

{ Frustum culling bounds }

function TvgVulkanDataStore.GetInstanceMatrix(AGlobalInstanceIndex: Integer): TpvMatrix4x4;
var
  Offset: Integer;
begin
  Result := TpvMatrix4x4.Identity;

  if not (idtMatrix in FInstanceTypes) then Exit;

  if (AGlobalInstanceIndex < 0) or (AGlobalInstanceIndex >= FInstanceCount) then Exit;

  Offset := AGlobalInstanceIndex * Integer(FInstanceStride) +
            Integer(FInstanceOffsets[idtMatrix]);

  if (Offset < 0) or (Offset + SizeOf(TpvMatrix4x4) > Length(FInstanceData)) then Exit;

  // Same 16-single, RawComponents[column, row] layout in both records - see
  // TvgMatrix4x4D.Create in Vulkan_Components_Descriptors, which copies
  // element for element between exactly these two shapes.
  Move(FInstanceData[Offset], Result, SizeOf(TpvMatrix4x4));
end;

procedure TvgVulkanDataStore.RecomputeWorldBounds(ObjectIndex: Integer);
var
  Obj  : TvgVulkanObjectRecord;
  I    : Integer;
  M    : TpvMatrix4x4;
begin
  if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then Exit;

  Obj := FDataObjects[ObjectIndex];

  // cmManual bounds belong to the application; rebuilding them from vertex
  // data would throw away the very thing it asked us to use.
  if Obj.CullMode = cmManual then
  begin
    Obj.BoundsDirty := False;
    FDataObjects[ObjectIndex] := Obj;
    Exit;
  end;

  if (not Obj.HasInstances) or
     (Obj.InstanceCount <= 0) or
     (Obj.InstanceStart < 0) or
     (not (idtMatrix in FInstanceTypes)) then
  begin
    // No per-instance transform, so there is nothing to move the geometry:
    // this draw path has no per-object model matrix and the vertices are
    // already in world space.
    Obj.WorldBounds := Obj.LocalBounds;
  end
  else
  begin
    // Union of the local box placed by each instance.  Each transformed box
    // is itself a bound rather than a tight fit, so the union is generous in
    // the safe direction.
    Obj.WorldBounds.Reset;
    for I := 0 to Obj.InstanceCount - 1 do
    begin
      M := GetInstanceMatrix(Obj.InstanceStart + I);
      Obj.WorldBounds.GrowAABB(Obj.LocalBounds.Transform(M));
    end;
  end;

  Obj.BoundsDirty := False;
  FDataObjects[ObjectIndex] := Obj;
end;

procedure TvgVulkanDataStore.SetObjectCullMode(ObjectIndex: Integer; AMode: TvgObjectCullMode);
var
  Obj: TvgVulkanObjectRecord;
begin
  FCriticalSection.Enter;
  try
    if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then
      raise EVulkanDataStoreException.CreateFmt('Invalid object index: %d', [ObjectIndex]);

    Obj := FDataObjects[ObjectIndex];
    if Obj.CullMode = AMode then Exit;

    Obj.CullMode    := AMode;
    // Leaving cmManual hands the bounds back to the vertex data, so whatever
    // the application supplied must be rebuilt from it.
    Obj.BoundsDirty := True;
    FDataObjects[ObjectIndex] := Obj;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.GetObjectCullMode(ObjectIndex: Integer): TvgObjectCullMode;
begin
  FCriticalSection.Enter;
  try
    if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then
      Exit(cmAuto);
    Result := FDataObjects[ObjectIndex].CullMode;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgVulkanDataStore.SetObjectBounds(ObjectIndex: Integer; const AMin, AMax: TpvVector3);
var
  Obj: TvgVulkanObjectRecord;
begin
  FCriticalSection.Enter;
  try
    if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then
      raise EVulkanDataStoreException.CreateFmt('Invalid object index: %d', [ObjectIndex]);

    Obj := FDataObjects[ObjectIndex];
    Obj.WorldBounds.SetBounds(AMin, AMax);

    // Supplying bounds only makes sense if they are then used, so this also
    // selects cmManual rather than silently having no effect on an object
    // still deriving its bounds from vertex data.
    Obj.CullMode    := cmManual;
    Obj.BoundsDirty := False;

    FDataObjects[ObjectIndex] := Obj;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.GetObjectWorldBounds(ObjectIndex: Integer): TvgAABB;
begin
  Result.Reset;

  FCriticalSection.Enter;
  try
    if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then Exit;

    if FDataObjects[ObjectIndex].BoundsDirty then
      RecomputeWorldBounds(ObjectIndex);

    Result := FDataObjects[ObjectIndex].WorldBounds;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.GetObjectLocalBounds(ObjectIndex: Integer): TvgAABB;
begin
  Result.Reset;

  FCriticalSection.Enter;
  try
    if (ObjectIndex < 0) or (ObjectIndex >= FDataObjects.Count) then Exit;
    Result := FDataObjects[ObjectIndex].LocalBounds;
  finally
    FCriticalSection.Leave;
  end;
end;

{ Getters }

function TvgVulkanDataStore.GetObjectVertexStart(ObjectIndex: Integer): Integer;
begin
  FCriticalSection.Enter;
  try
    Result := FDataObjects[ObjectIndex].VertexStart;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.GetObjectVertexCount(ObjectIndex: Integer): Integer;
begin
  FCriticalSection.Enter;
  try
    Result := FDataObjects[ObjectIndex].VertexCount;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.GetObjectInstanceStart(ObjectIndex: Integer): Integer;
begin
  FCriticalSection.Enter;
  try
    Result := FDataObjects[ObjectIndex].InstanceStart;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.GetObjectInstanceCount(ObjectIndex: Integer): Integer;
begin
  FCriticalSection.Enter;
  try
    Result := FDataObjects[ObjectIndex].InstanceCount;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.GetObjectIndexStart(ObjectIndex: Integer): Integer;
begin
  FCriticalSection.Enter;
  try
    Result := FDataObjects[ObjectIndex].IndexStart;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.GetObjectIndexCount(ObjectIndex: Integer): Integer;
begin
  FCriticalSection.Enter;
  try
    Result := FDataObjects[ObjectIndex].IndexCount;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgVulkanDataStore.GetStride(Binding: Cardinal): Cardinal;
begin
  case Binding of
    BINDING_VERTEX: Result := FVertexStride;
    BINDING_INSTANCE: Result := FInstanceStride;
  else
    Result := 0;
  end;
end;

function TvgVulkanDataStore.GetBindingDescriptions: TArray<TVkVertexInputBindingDescription>;
var
  Count: Integer;

begin
  Count := 0;

  if FVertexStride > 0 then
    Inc(Count);
  if FInstanceStride > 0 then
    Inc(Count);

  SetLength(Result, Count);
  Count := 0;

  if FVertexStride > 0 then
  begin
    Result[Count].binding   := BINDING_VERTEX;
    Result[Count].stride    := FVertexStride;
    Result[Count].inputRate := VK_VERTEX_INPUT_RATE_VERTEX;
    Inc(Count);
  end;

  if FInstanceStride > 0 then
  begin
    Result[Count].binding   := BINDING_INSTANCE;
    Result[Count].stride    := FInstanceStride;
    Result[Count].inputRate := VK_VERTEX_INPUT_RATE_INSTANCE;
  end;
end;

function TvgVulkanDataStore.GetAttributeDescriptions: TArray<TVkVertexInputAttributeDescription>;
var
  Count, Idx: Integer;
  VType: TvgVertexDataType;
  IType: TInstanceDataType;
  MatrixCol: Integer;
begin
  Count := 0;

  // Count attributes
  for VType in FVertexTypes do
    Inc(Count);

  for IType in FInstanceTypes do
  begin
    if IType = idtMatrix then
      Inc(Count, 4) // Matrix uses 4 locations
    else
      Inc(Count);
  end;

  SetLength(Result, Count);
  Idx := 0;
  
  // Vertex attributes
  for VType := Low(TvgVertexDataType) to High(TvgVertexDataType) do
  begin
    if VType in FVertexTypes then
    begin
      Result[Idx].location := FVertexLocations[VType];
      Result[Idx].binding  := BINDING_VERTEX;
      Result[Idx].format   := GetVertexFormat(VType);
      Result[Idx].offset   := FVertexOffsets[VType];
      Inc(Idx);
    end;
  end;

  // Instance attributes
  for IType := Low(TInstanceDataType) to High(TInstanceDataType) do
  begin
    if IType in FInstanceTypes then
    begin
      if IType = idtMatrix then
      begin
        // Matrix splits into 4 vec4 columns
        for MatrixCol := 0 to 3 do
        begin
          Result[Idx].location := Integer(FInstanceLocations[IType]) + MatrixCol;
          Result[Idx].binding  := BINDING_INSTANCE;
          Result[Idx].format   := VK_FORMAT_R32G32B32A32_SFLOAT;
          Result[Idx].offset   := Integer(FInstanceOffsets[IType]) + (MatrixCol * SIZE_VEC4);
          Inc(Idx);
        end;
      end
      else
      begin
        Result[Idx].location := FInstanceLocations[IType];
        Result[Idx].binding  := BINDING_INSTANCE;
        Result[Idx].format   := GetInstanceFormat(IType);
        Result[Idx].offset   := FInstanceOffsets[IType];
        Inc(Idx);
      end;
    end;
  end;
end;

procedure TvgVulkanDataStore.SetDataDirty;
var
  I: Integer;
begin
  for I := 0 to High(FDataDirty) do
    FDataDirty[I] := True;
end;

function TvgVulkanDataStore.GetDataDirty(aFrameIndex: Integer): Boolean;
begin
  if (aFrameIndex >= 0) and (aFrameIndex < Length(FDataDirty)) then
    Result := FDataDirty[aFrameIndex]
  else
    Result := False;
end;

{ Vulkan Buffer Management }

procedure TvgVulkanDataStore.CreateVulkanBuffer(aDevice: TpvVulkanDevice;
                                                ASize: TVkDeviceSize; AUsage: TVkBufferUsageFlags;
                                                AMemoryProperties: TVkMemoryPropertyFlags; out ABufferInfo: TVulkanBufferInfo);
begin
  ABufferInfo.Size   := ASize;
  ABufferInfo.Mapped := False;

  ABufferInfo.Buffer := TpvVulkanBuffer.Create(aDevice,//  aRenderer.Linker.ScreenDevice.VulkanDevice,                  //TpvVulkanDevice;
                                          ASize ,                     //TVkDeviceSize;
                                          AUsage,                     //TVkBufferUsageFlags;
                                          VK_SHARING_MODE_EXCLUSIVE,       // important;
                                          [],
                                          AMemoryProperties,
                                          0,  // MemoryPreferredPropertyFlags:TVkMemoryPropertyFlags;
                                          0,                                                  // MemoryAvoidPropertyFlags:TVkMemoryPropertyFlags;
                                          0,  //TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT),   // MemoryPreferredNotPropertyFlags:TVkMemoryPropertyFlags;
                                          0,                                                  // MemoryRequiredHeapFlags:TVkMemoryHeapFlags;
                                          0,                                                  // MemoryAvoidHeapFlags:TVkMemoryHeapFlags;
                                          0,                                                  // MemoryPreferredNotHeapFlags:TVkMemoryHeapFlags;
                                          0,                                                  // MemoryPreferredNotHeapFlags:TVkMemoryHeapFlags;
                                          [TpvVulkanBufferFlag.OwnSingleMemoryChunk]);  //[TpvVulkanBufferFlag.PersistentMapped]) ;          // TpvVulkanBufferFlags

  ABufferInfo.Memory := ABufferInfo.Buffer.Memory;
end;

procedure TvgVulkanDataStore.DestroyVulkanBuffer(var ABufferInfo: TVulkanBufferInfo);
begin
  if Assigned(ABufferInfo.Buffer) then
  begin
    ABufferInfo.Buffer.Free;
    ABufferInfo.Buffer := nil;
  end;
  ABufferInfo.Memory := nil;
  ABufferInfo.Size := 0;
  ABufferInfo.Mapped := False;
end;

procedure TvgVulkanDataStore.CreateVulkanDataBuffers;
var
  Frame: Integer;
  Usage: TVkBufferUsageFlags;
  MemProps: TVkMemoryPropertyFlags;
  Size: TVkDeviceSize;
begin
  if fBuffersCreated then  Exit;

  If not assigned(FVulkanDevice) then
    FVulkanDevice := fBaseScene.GetVulkanDevice;

  CustomAssert(assigned(FVulkanDevice),'Vulkan Device not assigned');

  Usage := TVkBufferUsageFlags(VK_BUFFER_USAGE_VERTEX_BUFFER_BIT) or
           TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_DST_BIT) or
           FExtraBufferUsage;
  MemProps := TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
  
  // Create vertex buffers
  if FVertexStride > 0 then
  begin
    Size := {TVkDeviceSize(FVertexCapacity)} TVkDeviceSize(FVertexCount)  * FVertexStride;
    if Size > 0 then
    begin
      SetLength(FVertexBuffers, FNumFrames);
      for Frame := 0 to FNumFrames - 1 do
        CreateVulkanBuffer(FVulkanDevice, Size, Usage, MemProps, FVertexBuffers[Frame]);
    end;
  end;
  
  // Create instance buffers
  if FInstanceStride > 0 then
  begin
    Size := {TVkDeviceSize(FInstanceCapacity)} TVkDeviceSize(FInstanceCount)  * FInstanceStride;
    if Size > 0 then
    begin
      SetLength(FInstanceBuffers, FNumFrames);
      for Frame := 0 to FNumFrames - 1 do
        CreateVulkanBuffer(FVulkanDevice, Size, Usage, MemProps, FInstanceBuffers[Frame]);
    end;
  end;
  
  // Create index buffers
  if FIndexType <> itNONE then
  begin
    Size := {TVkDeviceSize(FIndexCapacity)} TVkDeviceSize(FIndexCount) * GetIndexElementSize(FIndexType);
    if Size > 0 then
    begin
      SetLength(FIndexBuffers, FNumFrames);
      for Frame := 0 to FNumFrames - 1 do
      begin
        CreateVulkanBuffer(FVulkanDevice,
          Size,
          TVkBufferUsageFlags(VK_BUFFER_USAGE_INDEX_BUFFER_BIT) or
          TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_DST_BIT),
          MemProps,
          FIndexBuffers[Frame]);
      end;
    end;
  end;
  
  fBuffersCreated := True;
end;

procedure TvgVulkanDataStore.DeleteVulkanDataBuffers;
var
  Frame: Integer;
begin
  if not fBuffersCreated then   Exit;
    
  // Free vertex buffers
  for Frame := 0 to High(FVertexBuffers) do
    DestroyVulkanBuffer(FVertexBuffers[Frame]);
  SetLength(FVertexBuffers, 0);
  
  // Free instance buffers
  for Frame := 0 to High(FInstanceBuffers) do
    DestroyVulkanBuffer(FInstanceBuffers[Frame]);
  SetLength(FInstanceBuffers, 0);
  
  // Free index buffers
  for Frame := 0 to High(FIndexBuffers) do
    DestroyVulkanBuffer(FIndexBuffers[Frame]);
  SetLength(FIndexBuffers, 0);
  
  fBuffersCreated := False;
end;
(*
procedure TvgVulkanDataStore.CopyBufferToDevice(aTransferPool: TvgCommandBufferPool;
                                                const ASrcData: TBytes; ASize, AOffset: TVkDeviceSize; aFrameIndex: Integer;
                                                ABuffer: TpvVulkanBuffer);
var
  StagingBuffer: TpvVulkanBuffer;
  TransferCmd: TvgCommandBuffer;
  CopyRegion: TVkBufferCopy;
  pData: Pointer;
  RequiredSize: NativeUInt;
begin
  if ASize = 0 then
    Exit;

  CustomAssert(Assigned(FVulkanDevice), 'Vulkan device not assigned');
  CustomAssert(Assigned(aTransferPool), 'Transfer command pool not assigned');
  CustomAssert(Assigned(ABuffer), 'Destination buffer not assigned');

  RequiredSize := NativeUInt(ASize);
  CustomAssert(Length(ASrcData) >= Integer(RequiredSize),  Format('CopyBufferToDevice source array too small. Need %d bytes, have %d', [RequiredSize, Length(ASrcData)]));

        StagingBuffer := TpvVulkanBuffer.Create(FVulkanDevice,
                                                ASize,
                                                TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_SRC_BIT),
                                                TVkSharingMode(VK_SHARING_MODE_EXCLUSIVE),
                                                [],
                                                TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) or
                                                TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
                                                0, 0, 0,
                                                0,//TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT),
                                                0, 0, 0,
                                                [TpvVulkanBufferFlag.OwnSingleMemoryChunk]);

  TransferCmd := nil;
  try
    StageBufferList.Add(StagingBuffer);

    pData := StagingBuffer.Memory.MapMemory(0, ASize);
    try
      CustomAssert(Assigned(pData), 'Failed to map staging buffer memory');
      Move(ASrcData[0], pData^, RequiredSize);
    //  if (StagingBuffer.MemoryPropertyFlags and TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) = 0 then
        StagingBuffer.Memory.FlushMappedMemoryRange(nil, ASize);
    finally
      StagingBuffer.Memory.UnmapMemory;
    end;

    TransferCmd := aTransferPool.AcquireUploadCommand(aFrameIndex);
    CustomAssert(Assigned(TransferCmd), 'Failed to acquire upload command buffer');

    if not TransferCmd.Active then
      TransferCmd.Active := True;

    if TransferCmd.BufferState <> cbsRecording then
    begin
      if TransferCmd.BufferState = cbsPending then
        TransferCmd.WaitOnFence;

      if TransferCmd.BufferState <> cbsInitial then
        TransferCmd.Reset;

      TransferCmd.BeginRecordingPrimary;
    end;

    FillChar(CopyRegion, SizeOf(CopyRegion), 0);
    CopyRegion.srcOffset := 0;
    CopyRegion.dstOffset := AOffset;
    CopyRegion.size := ASize;

    TransferCmd.CmdCopyBuffer(StagingBuffer.Handle, ABuffer.Handle, 1, @CopyRegion);
    TransferCmd.EndRecording;

    TransferCmd.ExecuteCommand( FVulkanDevice.TransferQueue,
                                TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
                                nil,
                                nil,
                                True,
                                True
                              );

  finally
    if Assigned(TransferCmd) then
      aTransferPool.ReleaseCommand(TransferCmd);
  end;
end;
*)

(*

procedure TvgVulkanDataStore.CopyBufferToDevice(aTransferPool: TvgCommandBufferPool;
                                               const ASrcData: TBytes;
                                               ASize, AOffset: TVkDeviceSize;
                                               aFrameIndex: Integer;
                                               ABuffer: TpvVulkanBuffer);
var
  StagingBuffer: TpvVulkanBuffer;
  TransferCmd  : TvgCommandBuffer;
  CopyRegion   : TVkBufferCopy;
    pData: Pointer;
begin
  if ASize = 0 then
    Exit;

  CustomAssert(Assigned(FVulkanDevice), 'Vulkan device not assigned');
  CustomAssert(Assigned(aTransferPool), 'Transfer pool not assigned');
  CustomAssert(Assigned(ABuffer), 'Destination buffer not assigned');
  CustomAssert(AOffset + ASize <= ABuffer.Size, 'Copy exceeds destination buffer size');
  CustomAssert(Length(ASrcData) > 0, 'Source byte array is empty');
  CustomAssert(TVkDeviceSize(Length(ASrcData)) >= ASize, 'CopyBufferToDevice: source byte array smaller than requested copy size');

  StagingBuffer := nil;
  TransferCmd := nil;

  Try
  // Create staging buffer

        StagingBuffer := TpvVulkanBuffer.Create(FVulkanDevice,
                                                ASize,
                                                TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_SRC_BIT),
                                                TVkSharingMode(VK_SHARING_MODE_EXCLUSIVE),
                                                [],
                                                TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) or
                                                TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
                                                0, 0, 0,
                                                TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT),
                                                0, 0, 0,
                                                [TpvVulkanBufferFlag.OwnSingleMemoryChunk]);


         pData := StagingBuffer.Memory.MapMemory(0, ASize);
         CustomAssert(Assigned(pData), 'Failed to map staging buffer');
        try
          Move(ASrcData[0], pData^, ASize);
          StagingBuffer.Memory.FlushMappedMemory;
        finally
          StagingBuffer.Memory.UnmapMemory;
        end;


        TransferCmd := aTransferPool.AcquireUploadCommand(aFrameIndex);// RequestCommand(aFrameIndex, CB_PRIMARY,  [{BU_ONE_TIME_SUBMIT_BIT}]);
        CustomAssert(Assigned(TransferCmd), 'Failed to acquire transfer command buffer');
       Try
        If not TransferCmd.Active then
           TransferCmd.Active:=True;

        TransferCmd.PrepareForRecording;
        TransferCmd.BeginRecording;

        CopyRegion := Default(TVkBufferCopy);
        CopyRegion.srcOffset := 0;
        CopyRegion.dstOffset := AOffset;
        CopyRegion.size      := ASize;

        TransferCmd.CmdCopyBuffer(StagingBuffer.Handle, ABuffer.Handle, 1, @CopyRegion);

        TransferCmd.EndRecording;

        TransferCmd.ExecuteCommand(fVulkanDevice.TransferQueue,
                               TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
                               nil,     //wait for
                               nil,     //signal when finished
                               true,          //MUST be TRUE
                               true) ;        //MUST be TRUE

       Finally
          if Assigned(TransferCmd) then
            aTransferPool.ReleaseCommand(TransferCmd);
          FreeAndNil(StagingBuffer);
       End;

  Finally

  End;
end;
*)
(*
procedure TvgVulkanDataStore.UploadAllData(aTransferPool: TvgCommandBufferPool; aFrameIndex: Integer);
var
  Size: TVkDeviceSize;
begin
//  if not fBuffersCreated then
//    CreateVulkanDataBuffers(FVulkanDevice);

  CustomAssert(assigned(FVulkanDevice),'Vulkan Device NOT assigned');

  FCriticalSection.Enter;
  try
    // Upload vertex data
    if (Length(FVertexBuffers) > aFrameIndex) and (FVertexCount > 0) then
    begin
      Size := TVkDeviceSize(FVertexCount) * FVertexStride;
      CopyBufferToDevice(aTransferPool, FVertexData, Size, 0, aFrameIndex, FVertexBuffers[aFrameIndex].Buffer);
    end;
    
    // Upload instance data
    if (Length(FInstanceBuffers) > aFrameIndex) and (FInstanceCount > 0) then
    begin
      Size := TVkDeviceSize(FInstanceCount) * FInstanceStride;
      CopyBufferToDevice(aTransferPool, FInstanceData, Size, 0, aFrameIndex, FInstanceBuffers[aFrameIndex].Buffer);
    end;
    
    // Upload index data
    if (Length(FIndexBuffers) > aFrameIndex) and (FIndexCount > 0) then
    begin
      Size := TVkDeviceSize(FIndexCount) * GetIndexElementSize(FIndexType);
      CopyBufferToDevice(aTransferPool, FIndexData, Size, 0, aFrameIndex, FIndexBuffers[aFrameIndex].Buffer);
    end;
    
    FDataDirty[aFrameIndex] := False;
  finally
    FCriticalSection.Leave;
  end;
end;
*)
procedure TvgVulkanDataStore.UploadAllDataUsingCommand(aCmd: TvgCommandBuffer; aFrameIndex: Integer; IncBarrier: Boolean = True);
var
  pData: TpvPointer;
  CopyRegion: TVkBufferCopy;
  Size: TVkDeviceSize;
  BarrierCount: Integer;
  Barriers: array[0..2] of TVkBufferMemoryBarrier;
  LocalStageBuffers: TList<TpvVulkanBuffer>;

  procedure AddStageBuffer(const ABuffer: TpvVulkanBuffer);
  begin
    if Assigned(ABuffer) then
      LocalStageBuffers.Add(ABuffer);
  end;

  procedure DoBufferCopy(const AData: TBytes; const ASize: TVkDeviceSize;
    const ADstBuffer: TpvVulkanBuffer);
  var
    StagingBuffer: TpvVulkanBuffer;
  begin
    if (not Assigned(ADstBuffer)) or (ASize = 0) then
      Exit;

    CustomAssert(TVkDeviceSize(Length(AData)) >= ASize,
      'UploadAllDataUsingCommand: source byte array smaller than requested copy size');
    CustomAssert(ASize <= ADstBuffer.Size,
      'UploadAllDataUsingCommand: destination buffer too small');

    if (ADstBuffer.MemoryPropertyFlags and TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) <> 0 then
    begin
      pData := ADstBuffer.Memory.MapMemory(0, ASize);
      try
        if Assigned(pData) then
        begin
          Move(AData[0], pData^, ASize);
        //  if (ADstBuffer.MemoryPropertyFlags and TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) = 0 then
            ADstBuffer.Memory.FlushMappedMemory;
        end
        else
          raise EVulkanDataStoreException.Create('Vulkan buffer memory map failed');
      finally
        ADstBuffer.Memory.UnMapMemory;
      end;
    end
    else
    begin

         StagingBuffer := TpvVulkanBuffer.Create(FVulkanDevice,
                                          ASize,
                                          TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_SRC_BIT),
                                          TVkSharingMode(VK_SHARING_MODE_EXCLUSIVE),
                                          [],
                                          TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) or
                                          TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
                                          0, 0, 0,
                                          0,//TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT),
                                          0, 0, 0,
                                          [TpvVulkanBufferFlag.OwnSingleMemoryChunk]);

      AddStageBuffer(StagingBuffer);

      pData := StagingBuffer.Memory.MapMemory(0, ASize);
      try
        if Assigned(pData) then
        begin
          Move(AData[0], pData^, ASize);
        //  if (StagingBuffer.MemoryPropertyFlags and TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) = 0 then
            StagingBuffer.Memory.FlushMappedMemory;
        end
        else
          raise EVulkanDataStoreException.Create('Vulkan staging buffer memory map failed');
      finally
        StagingBuffer.Memory.UnMapMemory;
      end;

      FillChar(CopyRegion, SizeOf(CopyRegion), 0);
      CopyRegion.srcOffset := 0;
      CopyRegion.dstOffset := 0;
      CopyRegion.size := ASize;

      aCmd.CmdCopyBuffer(StagingBuffer.Handle, ADstBuffer.Handle, 1, @CopyRegion);
    end;
  end;

begin
  if not Assigned(aCmd) then
    Exit;

  CustomAssert(Assigned(FVulkanDevice), 'Vulkan device not assigned');
  CustomAssert(aCmd.Active, 'UploadAllDataUsingCommand: command buffer not active');

  if not FBuffersCreated then
    raise EVulkanDataStoreException.Create('Buffers must be created before uploading data');

  if (aFrameIndex < 0) or (aFrameIndex >= FNumFrames) then
    raise EVulkanDataStoreException.CreateFmt('Invalid frame index %d, must be 0..%d',
      [aFrameIndex, FNumFrames - 1]);

  if not FDataDirty[aFrameIndex] then
    Exit;

  LocalStageBuffers := TList<TpvVulkanBuffer>.Create;
  try
    FCriticalSection.Enter;
    try
      if (aFrameIndex < Length(FVertexBuffers)) and Assigned(FVertexBuffers[aFrameIndex].Buffer) and (FVertexCount > 0) then
      begin
        Size := TVkDeviceSize(FVertexCount) * TVkDeviceSize(FVertexStride);
        DoBufferCopy(FVertexData, Size, FVertexBuffers[aFrameIndex].Buffer);
      end;

      if (aFrameIndex < Length(FInstanceBuffers)) and Assigned(FInstanceBuffers[aFrameIndex].Buffer) and (FInstanceCount > 0) then
      begin
        Size := TVkDeviceSize(FInstanceCount) * TVkDeviceSize(FInstanceStride);
        DoBufferCopy(FInstanceData, Size, FInstanceBuffers[aFrameIndex].Buffer);
      end;

      if (aFrameIndex < Length(FIndexBuffers)) and Assigned(FIndexBuffers[aFrameIndex].Buffer) and (FIndexCount > 0) then
      begin
        Size := TVkDeviceSize(FIndexCount) * TVkDeviceSize(GetIndexElementSize(FIndexType));
        DoBufferCopy(FIndexData, Size, FIndexBuffers[aFrameIndex].Buffer);
      end;

      if IncBarrier then
      begin
        FillChar(Barriers[0], SizeOf(Barriers), 0);
        BarrierCount := 0;

        if (aFrameIndex < Length(FVertexBuffers)) and Assigned(FVertexBuffers[aFrameIndex].Buffer) and (FVertexCount > 0) then
        begin
          Barriers[BarrierCount].sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
          Barriers[BarrierCount].srcAccessMask := TVkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT);
          Barriers[BarrierCount].dstAccessMask := TVkAccessFlags(VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT);
          Barriers[BarrierCount].srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
          Barriers[BarrierCount].dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
          Barriers[BarrierCount].buffer := FVertexBuffers[aFrameIndex].Buffer.Handle;
          Barriers[BarrierCount].offset := 0;
          Barriers[BarrierCount].size := TVkDeviceSize(FVertexCount) * TVkDeviceSize(FVertexStride);
          Inc(BarrierCount);
        end;

        if (aFrameIndex < Length(FInstanceBuffers)) and Assigned(FInstanceBuffers[aFrameIndex].Buffer) and (FInstanceCount > 0) then
        begin
          Barriers[BarrierCount].sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
          Barriers[BarrierCount].srcAccessMask := TVkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT);
          Barriers[BarrierCount].dstAccessMask := TVkAccessFlags(VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT);
          Barriers[BarrierCount].srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
          Barriers[BarrierCount].dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
          Barriers[BarrierCount].buffer := FInstanceBuffers[aFrameIndex].Buffer.Handle;
          Barriers[BarrierCount].offset := 0;
          Barriers[BarrierCount].size := TVkDeviceSize(FInstanceCount) * TVkDeviceSize(FInstanceStride);
          Inc(BarrierCount);
        end;

        if (aFrameIndex < Length(FIndexBuffers)) and Assigned(FIndexBuffers[aFrameIndex].Buffer) and (FIndexCount > 0) then
        begin
          Barriers[BarrierCount].sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
          Barriers[BarrierCount].srcAccessMask := TVkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT);
          Barriers[BarrierCount].dstAccessMask := TVkAccessFlags(VK_ACCESS_INDEX_READ_BIT);
          Barriers[BarrierCount].srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
          Barriers[BarrierCount].dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
          Barriers[BarrierCount].buffer := FIndexBuffers[aFrameIndex].Buffer.Handle;
          Barriers[BarrierCount].offset := 0;
          Barriers[BarrierCount].size := TVkDeviceSize(FIndexCount) * TVkDeviceSize(GetIndexElementSize(FIndexType));
          Inc(BarrierCount);
        end;

        if BarrierCount > 0 then
        begin
          aCmd.CmdPipelineBarrier(
            TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
            TVkPipelineStageFlags(VK_PIPELINE_STAGE_VERTEX_INPUT_BIT),
            0,
            0, nil,
            BarrierCount, @Barriers[0],
            0, nil);
        end;
      end;

      FDataDirty[aFrameIndex] := False;
    finally
      FCriticalSection.Leave;
    end;

    { IMPORTANT:
      Staging buffers must stay alive until AFTER the recorded command buffer has
      actually finished executing on the GPU.

      Safe options:
      1. If caller submits and waits immediately, free them right after submit.
      2. Otherwise move these buffers to an owner list associated with the frame
         and free them only when that frame fence signals.

      For now, keep compatibility with your existing lifetime model by transferring
      ownership to StageBufferList after recording. }
    while LocalStageBuffers.Count > 0 do
    begin
      StageBufferList.Add(LocalStageBuffers[0]);
      LocalStageBuffers.Delete(0);
    end;

  finally
    for var I := 0 to LocalStageBuffers.Count - 1 do
      LocalStageBuffers[I].Free;
    LocalStageBuffers.Free;
  end;
end;


 (*

procedure TvgVulkanDataStore.UploadAllDataUsingCommand(aCmd: TvgCommandBuffer;  aFrameIndex: Integer; IncBarrier: Boolean);
var
  pData: TpvPointer;
  CopyRegion: TVkBufferCopy;
  StagingBuffer: TpvVulkanBuffer;
  Size: TVkDeviceSize;
  Barriers: array[0..2] of TVkBufferMemoryBarrier;
  BarrierCount: Integer;

  procedure DoBufferCopy(const AData: TBytes; ASize: TVkDeviceSize; ADstBuffer: TpvVulkanBuffer);
  begin
    if (not Assigned(ADstBuffer)) or (ASize = 0) then
      Exit;

    // Check if destination is host-visible (can write directly)
    if (ADstBuffer.MemoryPropertyFlags and TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) <> 0) then
    begin
      // Direct mapping (rare for vertex buffers but possible)
      pData := ADstBuffer.Memory.MapMemory(0, ASize);
      try
        if Assigned(pData) then
        begin
          Move(AData[0], pData^, ASize);
          ADstBuffer.Memory.FlushMappedMemory;
        end
        else
          raise EpvVulkanException.Create('Vulkan buffer memory block map failed');
      finally
        ADstBuffer.Memory.UnMapMemory;
      end;
    end
    else
    begin

     StagingBuffer := TpvVulkanBuffer.Create(FVulkanDevice,
                                          ASize,
                                          TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_SRC_BIT),
                                          TVkSharingMode(VK_SHARING_MODE_EXCLUSIVE),
                                          [],
                                          TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) or
                                          TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
                                          0, 0, 0, 0, 0, 0, 0,
                                          [TpvVulkanBufferFlag.OwnSingleMemoryChunk]);

      StageBufferList.Add(StagingBuffer);

      // Map and copy to staging buffer
      pData := StagingBuffer.Memory.MapMemory(0, ASize);
      try
        if Assigned(pData) then
        begin
          Move(AData[0], pData^, ASize);
          StagingBuffer.Memory.FlushMappedMemory;
        end
        else
          raise EpvVulkanException.Create('Vulkan staging buffer memory map failed');
      finally
        StagingBuffer.Memory.UnMapMemory;
      end;

      // Record copy command
      CopyRegion.srcOffset := 0;
      CopyRegion.dstOffset := 0;
      CopyRegion.size := ASize;

      aCmd.CmdCopyBuffer(StagingBuffer.Handle, ADstBuffer.Handle, 1, @CopyRegion);
    end;
  end;

begin
  if not Assigned(aCmd) then
    Exit;
  if not aCmd.Active then
    Exit;

  if not fBuffersCreated then
    raise EVulkanDataStoreException.Create('Buffers must be created before uploading data');

  if (aFrameIndex < 0) or (aFrameIndex >= FNumFrames) then
    raise EVulkanDataStoreException.CreateFmt('Invalid frame index: %d (must be 0..%d)',
      [aFrameIndex, FNumFrames - 1]);

  if not FDataDirty[aFrameIndex] then
    Exit; // Don't upload if not dirty

  FCriticalSection.Enter;
  try
    // Upload vertex data
    if (Length(FVertexBuffers) > aFrameIndex) and (FVertexCount > 0) then
    begin
      Size := TVkDeviceSize(FVertexCount) * FVertexStride;
      DoBufferCopy(FVertexData, Size, FVertexBuffers[aFrameIndex].Buffer);
    end;

    // Upload instance data
    if (Length(FInstanceBuffers) > aFrameIndex) and (FInstanceCount > 0) then
    begin
      Size := TVkDeviceSize(FInstanceCount) * FInstanceStride;
      DoBufferCopy(FInstanceData, Size, FInstanceBuffers[aFrameIndex].Buffer);
    end;

    // Upload index data
    if (Length(FIndexBuffers) > aFrameIndex) and (FIndexCount > 0) then
    begin
      Size := TVkDeviceSize(FIndexCount) * GetIndexElementSize(FIndexType);
      DoBufferCopy(FIndexData, Size, FIndexBuffers[aFrameIndex].Buffer);
    end;

    // Memory barriers (if requested)
    if IncBarrier then
    begin
      FillChar(Barriers[0], SizeOf(Barriers), 0);
      BarrierCount := 0;

      // Vertex buffer barrier
      if (Length(FVertexBuffers) > aFrameIndex) and Assigned(FVertexBuffers[aFrameIndex].Buffer) then
      begin
        Barriers[BarrierCount].sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        Barriers[BarrierCount].srcAccessMask := TVkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT);
        Barriers[BarrierCount].dstAccessMask := TVkAccessFlags(VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT);
        Barriers[BarrierCount].srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
        Barriers[BarrierCount].dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
        Barriers[BarrierCount].buffer := FVertexBuffers[aFrameIndex].Buffer.Handle;
        Barriers[BarrierCount].offset := 0;
        Barriers[BarrierCount].size := FVertexBuffers[aFrameIndex].Buffer.Size;
        Inc(BarrierCount);
      end;

      // Instance buffer barrier
      if (Length(FInstanceBuffers) > aFrameIndex) and Assigned(FInstanceBuffers[aFrameIndex].Buffer) then
      begin
        Barriers[BarrierCount].sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        Barriers[BarrierCount].srcAccessMask := TVkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT);
        Barriers[BarrierCount].dstAccessMask := TVkAccessFlags(VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT);
        Barriers[BarrierCount].srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
        Barriers[BarrierCount].dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
        Barriers[BarrierCount].buffer := FInstanceBuffers[aFrameIndex].Buffer.Handle;
        Barriers[BarrierCount].offset := 0;
        Barriers[BarrierCount].size := FInstanceBuffers[aFrameIndex].Buffer.Size;
        Inc(BarrierCount);
      end;

      // Index buffer barrier
      if (Length(FIndexBuffers) > aFrameIndex) and Assigned(FIndexBuffers[aFrameIndex].Buffer) then
      begin
        Barriers[BarrierCount].sType := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        Barriers[BarrierCount].srcAccessMask := TVkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT);
        Barriers[BarrierCount].dstAccessMask := TVkAccessFlags(VK_ACCESS_INDEX_READ_BIT);
        Barriers[BarrierCount].srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
        Barriers[BarrierCount].dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
        Barriers[BarrierCount].buffer := FIndexBuffers[aFrameIndex].Buffer.Handle;
        Barriers[BarrierCount].offset := 0;
        Barriers[BarrierCount].size := FIndexBuffers[aFrameIndex].Buffer.Size;
        Inc(BarrierCount);
      end;

      // Issue pipeline barrier if we have any buffers to synchronize
      if BarrierCount > 0 then
      begin
        aCmd.CmdPipelineBarrier(
          TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
          TVkPipelineStageFlags(VK_PIPELINE_STAGE_VERTEX_INPUT_BIT),
          0,
          0, nil,
          BarrierCount, @Barriers[0],
          0, nil);
      end;
    end;

    // Clear dirty flag for this frame
    FDataDirty[aFrameIndex] := False;
  finally
    FCriticalSection.Leave;
  end;

end;
*)

Procedure TvgVulkanDataStore.UploadAllData(aPool: TvgCommandBufferPool; aFrameIndex: Integer);
var
  Cmd: TvgCommandBuffer;
begin
  CustomAssert(Assigned(aPool), 'Transfer command pool not assigned');
  CustomAssert(Assigned(FVulkanDevice) or Assigned(fBaseScene), 'Vulkan device/base scene not assigned');

  if not Assigned(FVulkanDevice) then
    FVulkanDevice := fBaseScene.GetVulkanDevice;

  CustomAssert(Assigned(FVulkanDevice), 'Vulkan device NOT assigned');

  if not fBuffersCreated then
    CreateVulkanDataBuffers;

  if (aFrameIndex < 0) or (aFrameIndex >= FNumFrames) then
    raise EVulkanDataStoreException.CreateFmt('Invalid frame index %d, must be 0..%d',
      [aFrameIndex, FNumFrames - 1]);

  if not FDataDirty[aFrameIndex] then
    Exit;

  FCriticalSection.Enter;
  try
    Cmd := aPool.AcquireUploadCommand(aFrameIndex);
    CustomAssert(Assigned(Cmd), 'Failed to acquire upload command buffer');

    try
      if not Cmd.Active then
        Cmd.Active := True;

      if Cmd.BufferState <> cbsRecording then
      begin
        if Cmd.BufferState = cbsPending then
          Cmd.WaitOnFence;
        if Cmd.BufferState <> cbsInitial then
          Cmd.Reset;
        Cmd.BeginRecordingPrimary;
      end;

      UploadAllDataUsingCommand(Cmd, aFrameIndex, True);

      if Cmd.BufferState = cbsRecording then
        Cmd.EndRecording;

      if Cmd.CommandCount > 0 then
      begin
        Cmd.ExecuteCommand( FVulkanDevice.TransferQueue,
                            TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
                            nil,
                            nil,
                            True,
                            True
                          );
      end
      else
      begin
        FDataDirty[aFrameIndex] := False;
      end;
    finally
      aPool.ReleaseCommand(Cmd);

      while StageBufferList.Count > 0 do
      begin
        StageBufferList.Items[0].free;
        StageBufferList.Delete(0);
      end;

    end;
  finally
    FCriticalSection.Leave;
  end;
end;


procedure TvgVulkanDataStore.UploadResourceDataToVulkan(aPool: TvgCommandBufferPool; aFrameIndex, aSubPassIndex: Integer);
begin
  if GetDataDirty(aFrameIndex) then
    UploadAllData(aPool, aFrameIndex);
end;

procedure TvgVulkanDataStore.BindObjectResources(aCommandBuf: TvgCommandBuffer; aWorkerIndex, aSubPassIndex, aSetValue: TvkUint32);
begin
  // Override in subclass if needed for descriptor sets
end;

function TvgVulkanDataStore.GetVulkanVertexBuffer(AFrameIndex: Integer): TpvVulkanBuffer;
begin
  if (AFrameIndex >= 0) and (AFrameIndex < Length(FVertexBuffers)) then
    Result := FVertexBuffers[AFrameIndex].Buffer
  else
    Result := nil;
end;

function TvgVulkanDataStore.IsInstanceTypeSet(  aInstanceType: TInstanceDataType): Boolean;
begin
  Result := aInstanceType in FInstanceTypes;
end;

function TvgVulkanDataStore.GetVulkanInstanceBuffer(AFrameIndex: Integer): TpvVulkanBuffer;
begin
  if (AFrameIndex >= 0) and (AFrameIndex < Length(FInstanceBuffers)) then
    Result := FInstanceBuffers[AFrameIndex].Buffer
  else
    Result := nil;
end;

function TvgVulkanDataStore.GetVulkanIndexBuffer(AFrameIndex: Integer): TpvVulkanBuffer;
begin
  if (AFrameIndex >= 0) and (AFrameIndex < Length(FIndexBuffers)) then
    Result := FIndexBuffers[AFrameIndex].Buffer
  else
    Result := nil;
end;

{ Draw Implementation }

procedure TvgVulkanDataStore.VulkanDraw(aCommandBuffer: TvgCommandBuffer;
  aPipe: TvgGraphicPipeline; aFrameIndex: TvkUint32; var CommandCount: Integer);
var
  I: Integer;
  FI: Integer;
  Obj: TvgVulkanObjectRecord;
  VertexBuffer, InstanceBuffer, IndexBuffer: TpvVulkanBuffer;
  VertexOffset : TVkDeviceSize;
  IndexTypeVk: TVkIndexType;
  Buffers: array[0..1] of TVkBuffer;
  Offsets: array[0..1] of TVkDeviceSize;
  BufferCount: Integer;
begin
  if not Assigned(aCommandBuffer) then
    Exit;

  //Nothing has been uploaded to the device yet.  That is a sequencing state,
  //not a fault, so record nothing and stay quiet.
  if not FBuffersCreated then
    Exit;

  //A frame index this store was never sized for means the per-frame buffer
  //arrays are out of step with the renderer's frames-in-flight.  Recording a
  //draw against the missing slot binds nothing and presents as a blank frame,
  //so refuse the draw and leave a trace instead of failing silently.
  FI := Integer(aFrameIndex);
  if (FI < 0) or (FI >= FNumFrames) then
  begin
    CustomAssert(False,
      System.SysUtils.Format('VulkanDraw: frame index %d out of range, store holds %d frame slots',
                             [FI, FNumFrames]), Self);
    Exit;
  end;

  VertexBuffer   := GetVulkanVertexBuffer(aFrameIndex);
  InstanceBuffer := GetVulkanInstanceBuffer(aFrameIndex);
  IndexBuffer    := GetVulkanIndexBuffer(aFrameIndex);
  
  // Determine index type
  case FIndexType of
    itUInt16: IndexTypeVk := VK_INDEX_TYPE_UINT16;
    itUInt32: IndexTypeVk := VK_INDEX_TYPE_UINT32;
  else
    IndexTypeVk := VK_INDEX_TYPE_UINT32;
  end;
  
  FCriticalSection.Enter;
  try
    for I := 0 to FDataObjects.Count - 1 do
    begin
      Obj := FDataObjects[I];
      
      if (Obj.VertexCount <= 0) then
        Continue;

      //Every draw below sources the vertex binding, so a missing vertex buffer
      //or an unallocated vertex range can never produce a correct draw.  Skip
      //the object rather than record a draw with nothing bound.
      if (not Assigned(VertexBuffer)) or (Obj.VertexStart < 0) then
      begin
        CustomAssert(False,
          System.SysUtils.Format('VulkanDraw: object %d has no vertex buffer for frame %d - draw skipped',
                                 [I, FI]), Self);
        Continue;
      end;

      //An object carrying indices MUST be drawn indexed.  Falling through to a
      //non-indexed draw of VertexCount vertices renders the wrong geometry.
      if (Obj.IndexCount > 0) and
         ((not Assigned(IndexBuffer)) or (Obj.IndexStart < 0)) then
      begin
        CustomAssert(False,
          System.SysUtils.Format('VulkanDraw: object %d has %d indices but no index buffer for frame %d - draw skipped',
                                 [I, Obj.IndexCount, FI]), Self);
        Continue;
      end;

      //Instanced geometry needs its instance binding for the same reason - the
      //instance attributes would otherwise be read from an unbound binding.
      if Obj.HasInstances and
         ((not Assigned(InstanceBuffer)) or (Obj.InstanceStart < 0)) then
      begin
        CustomAssert(False,
          System.SysUtils.Format('VulkanDraw: object %d is instanced but has no instance buffer for frame %d - draw skipped',
                                 [I, FI]), Self);
        Continue;
      end;

      // Bind vertex and instance buffers
      BufferCount := 0;

      Buffers[BufferCount] := VertexBuffer.Handle;
      Offsets[BufferCount] := TVkDeviceSize(Obj.VertexStart) * FVertexStride;
      Inc(BufferCount);

      if Obj.HasInstances then
      begin
        Buffers[BufferCount] := InstanceBuffer.Handle;
        Offsets[BufferCount] := TVkDeviceSize(Obj.InstanceStart) * FInstanceStride;
        Inc(BufferCount);
      end;

      aCommandBuffer.CmdBindVertexBuffers(0, BufferCount, @Buffers[0], @Offsets[0]);

      // Bind index buffer if present
      if (Obj.IndexCount > 0) then
      begin
        VertexOffset := TVkDeviceSize(Obj.IndexStart) * GetIndexElementSize(FIndexType);
        aCommandBuffer.CmdBindIndexBuffer(IndexBuffer.Handle, VertexOffset, IndexTypeVk);

        // Indexed draw
        aCommandBuffer.CmdDrawIndexed(Obj.IndexCount,
                                      Max(1, Obj.InstanceCount),
                                      0, 0, 0);
      end
      else
      begin
        // Non-indexed draw
        aCommandBuffer.CmdDraw( Obj.VertexCount,
                                Max(1, Obj.InstanceCount),
                                0, 0);
      end;

      Inc(CommandCount);
    end;
  finally
    FCriticalSection.Leave;
  end;
end;

{ GLSL Header Generation }

function TvgVulkanDataStore.WriteGLSLHeader: string;
var
  Lines: TStringList;
  VType: TvgVertexDataType;
  IType: TInstanceDataType;
  Info: TGLSLAttributeInfo;
  Location: Cardinal;
 // MatrixCol: Integer;
begin
  Lines := TStringList.Create;
  try
    // Vertex attributes
    for VType := Low(TvgVertexDataType) to High(TvgVertexDataType) do
    begin
      if VType in FVertexTypes then
      begin
        Location := FVertexLocations[VType];
        Info := GetGLSLVertexType(VType);
        Lines.Add(Format('layout(location = %d) in %s %s;  // per-vertex',
          [Location, Info.GLSLType, Info.GLSLName]));
      end;

    end;
    
    // Instance attributes
    for IType := Low(TInstanceDataType) to High(TInstanceDataType) do
    begin
      if IType in FInstanceTypes then
      begin
        Location := FInstanceLocations[IType];
        Info := GetGLSLInstanceType(IType);
        
        if IType = idtMatrix then
        begin
          Lines.Add(Format('layout(location = %d) in mat4 %s; // per-instance (columns %d..%d)',
            [Location, Info.GLSLName, Location, Location + 3]));
        end
        else
        begin
          Lines.Add(Format('layout(location = %d) in %s %s; // per-instance',
            [Location, Info.GLSLType, Info.GLSLName]));
        end;
      end;
    end;
    
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

function TvgVulkanDataStore.GetShaderVertexPositionExpression(
  const aPositionName: String): String;
begin
  if idtMatrix in FInstanceTypes then
    Result := 'inInstanceMatrix * vec4(' + aPositionName + ', 1.0)'
  else
    Result := inherited GetShaderVertexPositionExpression(aPositionName);
end;

{ Pipeline Updates }

procedure TvgVulkanDataStore.UpdateGraphicPipeBindingAndAttributeDescriptions( aPipe: TvgGraphicPipeline);
  Var
     VType: TvgVertexDataType;
     IType: TInstanceDataType;

      VA : TvgVertexAttributeDesc;
      VB : TvgVertexBindingDesc;
      MatrixCol: Integer;
      AttributeInfo: TGLSLAttributeInfo;


begin
  If not assigned(aPipe) then exit;

 // If not aPipe.Active then exit;

  aPipe.VertexInput.Bindings.clear;
  aPipe.VertexInput.Attributes.clear;

  if (FVertexStride = 0) and (FInstanceStride = 0) then  exit;

  if FVertexStride > 0 then
  begin
    VB  := aPipe.VertexInput.Bindings.add;
    VB.binding   := BINDING_VERTEX;
    VB.stride    := FVertexStride;
    VB.inputRate := IR_VERTEX;
  end;

  if FInstanceStride > 0 then
  begin
    VB  := aPipe.VertexInput.Bindings.add;
    VB.binding   := BINDING_INSTANCE;
    VB.stride    := FInstanceStride;
    VB.inputRate := IR_INSTANCE;
  end;

  // Vertex attributes
  for VType := Low(TvgVertexDataType) to High(TvgVertexDataType) do
  begin
    if VType in FVertexTypes then
    begin
      AttributeInfo := GetGLSLVertexType(VType);
      VA          := aPipe.VertexInput.Attributes.Add;
      VA.location := FVertexLocations[VType];
      VA.binding  := BINDING_VERTEX;
      VA.AttFormat:= GetVGFormat(GetVertexFormat(VType));
      VA.offset   := FVertexOffsets[VType];
      VA.Name     := AttributeInfo.GLSLName;
      VA.DataType := GetDataTypeForFormat(GetVertexFormat(VType));
      VA.AttType  := GetVertexAttributeType(VType);
    end;
  end;

  // Instance attributes
  for IType := Low(TInstanceDataType) to High(TInstanceDataType) do
  begin
    if IType in FInstanceTypes then
    begin
      AttributeInfo := GetGLSLInstanceType(IType);
      if IType = idtMatrix then
      begin
        // Matrix splits into 4 vec4 columns
        for MatrixCol := 0 to 3 do
        begin
          VA := aPipe.VertexInput.Attributes.Add;
          VA.location := Integer(FInstanceLocations[IType]) + MatrixCol;
          VA.binding  := BINDING_INSTANCE;
          VA.AttFormat:= GetVGFormat(VK_FORMAT_R32G32B32A32_SFLOAT);
          VA.offset   := Integer(FInstanceOffsets[IType]) + (MatrixCol * SIZE_VEC4);
          if MatrixCol = 0 then
            VA.Name := AttributeInfo.GLSLName
          else
            VA.Name := AttributeInfo.GLSLName +
              'Column' + IntToStr(MatrixCol);
          VA.DataType := DT_VEC4;
          VA.AttType  := AT_MATRIX;
        end;
      end
      else
      begin
        VA := aPipe.VertexInput.Attributes.Add;
        VA.location := FInstanceLocations[IType];
        VA.binding  := BINDING_INSTANCE;
        VA.AttFormat:= GetVGFormat(GetInstanceFormat(IType));
        VA.offset   := FInstanceOffsets[IType];
        VA.Name     := AttributeInfo.GLSLName;
        VA.DataType := GetDataTypeForFormat(GetInstanceFormat(IType));
        VA.AttType  := GetInstanceAttributeType(IType);
      end;
    end;
  end;

end;

procedure TvgVulkanDataStore.UpdateGraphicPipeline(aPipe: TvgGraphicPipeline);

begin
  if not Assigned(aPipe) then  Exit;

  UpdateGraphicPipeBindingAndAttributeDescriptions(aPipe);

end;

procedure TvgVulkanDataStore.SetBaseScene(aBaseScene: TvgBaseScene);
begin
  inherited;

  // finish
  // Scene reference stored for pipeline updates
end;

end.
