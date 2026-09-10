unit Vulkan_Components_Compute;

(******************************************************************************
 *                                 vgVulkan                                   *
 ******************************************************************************
 *                          Generic compute engine                            *
 *============================================================================*
 *                                                                            *
 *  Fills in TvgBaseComputeEngine, which the package declared but left empty. *
 *                                                                            *
 *  TvgComputeEngine owns everything a compute dispatch needs and nothing      *
 *  specific to what is being computed:                                       *
 *                                                                            *
 *    - a compute shader module, compiled from GLSL at run time               *
 *    - a descriptor set layout of N storage-buffer bindings                  *
 *    - a descriptor pool and one descriptor set per frame slot               *
 *    - a pipeline layout carrying a single push-constant range               *
 *    - the compute pipeline itself                                           *
 *    - bind / push / dispatch recording, and the usual buffer barriers       *
 *                                                                            *
 *  A descendant supplies the GLSL by overriding GetShaderSource, then calls   *
 *  BuildPipeline once the device exists.  See TvgParticleCompute in          *
 *  Vulkan_Components_Particles for a worked descendant.                      *
 *                                                                            *
 *  zlib license - see the other units in this package.                       *
 ******************************************************************************)

Interface

{$INCLUDE VulkanPackage.inc}

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  Vulkan,
  PasVulkan.Types,
  PasVulkan.Framework,
  Vulkan_Assert,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_ShaderCompiler;

type

  EvgComputeException = class(Exception);

  // Where a compute write is going to be read next.  Picks the destination
  // stage and access mask for RecordBufferBarrier.
  TvgComputeConsumer = (
    ccVertexInput,    // the buffer is bound as a vertex/instance buffer
    ccIndexInput,     // bound as an index buffer
    ccIndirect,       // consumed by an indirect draw or dispatch
    ccCompute,        // read by a following compute dispatch
    ccHost            // read back by the CPU
  );

  TvgComputeEngine = class(TvgBaseComputeEngine)
  private
    fVulkanDevice   : TpvVulkanDevice;

    fShaderModule   : TVkShaderModule;
    fSetLayout      : TVkDescriptorSetLayout;
    fDescPool       : TVkDescriptorPool;
    fPipelineLayout : TVkPipelineLayout;
    fPipeline       : TVkPipeline;

    fDescSets       : array of TVkDescriptorSet;

    fSetCount       : Integer;   // descriptor sets, normally frames in flight
    fBindingCount   : Integer;   // storage buffers in the set
    fPushSize       : Integer;   // bytes of push constants
    fLastError      : String;

    procedure CreateSetLayout;
    procedure CreateDescriptorPool;
    procedure AllocateDescriptorSets;
    procedure CreatePipelineLayout;
    procedure CreateComputePipeline;

  protected
    Function SetDisabled : Boolean; Override;
    Function SetEnabled  : Boolean; Override;

    procedure DestroyPipelineObjects; virtual;

    // The GLSL compiled into the compute shader module.  Descendants must
    // override this; it is called once per BuildPipeline.
    function GetShaderSource: String; virtual; abstract;

    // Workgroup size the shader declares.  Used to turn a work item count
    // into a group count in DispatchGroupsFor.
    function GetLocalSizeX: Integer; virtual;

  public
    constructor Create(AOwner: TComponent); Override;
    destructor Destroy; override;

    Procedure SetDevice(aDevice: TpvVulkanDevice);

    // Build every Vulkan object.  aSetCount is usually the frame-in-flight
    // count; aBindingCount is how many storage buffers the shader declares at
    // set 0, bindings 0..N-1; aPushConstantSize may be 0 for none.
    Procedure BuildPipeline(aSetCount, aBindingCount, aPushConstantSize: Integer); virtual;

    // Point one set at its buffers.  Length(aBuffers) must equal the binding
    // count the pipeline was built with.  Call again if a buffer is recreated.
    Procedure UpdateDescriptorSet(aSetIndex: Integer;
                                  const aBuffers: array of TpvVulkanBuffer);

    // Record bind + optional push constants + dispatch into a command buffer
    // that is already recording.
    Procedure RecordDispatch(aCommandBuffer : TvgCommandBuffer;
                             aSetIndex      : Integer;
                             aPushData      : Pointer;
                             aGroupsX       : TvkUint32;
                             aGroupsY       : TvkUint32 = 1;
                             aGroupsZ       : TvkUint32 = 1);

    // Convenience: dispatch enough groups to cover aWorkItems, using the
    // shader's declared local size.
    Procedure RecordDispatchFor(aCommandBuffer : TvgCommandBuffer;
                                aSetIndex      : Integer;
                                aPushData      : Pointer;
                                aWorkItems     : Integer);

    // Make a compute write visible to whatever reads the buffer next.
    class Procedure RecordBufferBarrier(aCommandBuffer : TvgCommandBuffer;
                                        aBuffer        : TpvVulkanBuffer;
                                        aConsumer      : TvgComputeConsumer);

    Function Built : Boolean;

    Function DispatchGroupsFor(aWorkItems: Integer): TvkUint32;

    Property VulkanDevice   : TpvVulkanDevice read fVulkanDevice;
    Property PipelineHandle : TVkPipeline read fPipeline;
    Property LayoutHandle   : TVkPipelineLayout read fPipelineLayout;
    Property SetCount       : Integer read fSetCount;
    Property BindingCount   : Integer read fBindingCount;
    Property PushSize       : Integer read fPushSize;
    Property LastError      : String read fLastError;
  end;


Implementation

{------------------------------------------------------------------------------
  TvgComputeEngine
------------------------------------------------------------------------------}

constructor TvgComputeEngine.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  fVulkanDevice   := nil;
  fShaderModule   := VK_NULL_HANDLE;
  fSetLayout      := VK_NULL_HANDLE;
  fDescPool       := VK_NULL_HANDLE;
  fPipelineLayout := VK_NULL_HANDLE;
  fPipeline       := VK_NULL_HANDLE;

  fSetCount       := 0;
  fBindingCount   := 0;
  fPushSize       := 0;
end;

destructor TvgComputeEngine.Destroy;
begin
  DestroyPipelineObjects;
  inherited;
end;

function TvgComputeEngine.GetLocalSizeX: Integer;
begin
  Result := 256;
end;

Function TvgComputeEngine.Built: Boolean;
begin
  Result := Assigned(fVulkanDevice) and (fPipeline <> VK_NULL_HANDLE);
end;

Function TvgComputeEngine.SetEnabled: Boolean;
begin
  Result := Built;
end;

Function TvgComputeEngine.SetDisabled: Boolean;
begin
  DestroyPipelineObjects;
  Result := True;
end;

Procedure TvgComputeEngine.SetDevice(aDevice: TpvVulkanDevice);
begin
  if fVulkanDevice = aDevice then Exit;
  DestroyPipelineObjects;
  fVulkanDevice := aDevice;
end;

procedure TvgComputeEngine.DestroyPipelineObjects;
begin
  if not Assigned(fVulkanDevice) then
  begin
    fShaderModule   := VK_NULL_HANDLE;
    fSetLayout      := VK_NULL_HANDLE;
    fDescPool       := VK_NULL_HANDLE;
    fPipelineLayout := VK_NULL_HANDLE;
    fPipeline       := VK_NULL_HANDLE;
    SetLength(fDescSets, 0);
    Exit;
  end;

  if fPipeline <> VK_NULL_HANDLE then
  begin
    vkDestroyPipeline(fVulkanDevice.Handle, fPipeline, nil);
    fPipeline := VK_NULL_HANDLE;
  end;

  if fPipelineLayout <> VK_NULL_HANDLE then
  begin
    vkDestroyPipelineLayout(fVulkanDevice.Handle, fPipelineLayout, nil);
    fPipelineLayout := VK_NULL_HANDLE;
  end;

  // Descriptor sets are released with the pool.
  if fDescPool <> VK_NULL_HANDLE then
  begin
    vkDestroyDescriptorPool(fVulkanDevice.Handle, fDescPool, nil);
    fDescPool := VK_NULL_HANDLE;
  end;
  SetLength(fDescSets, 0);

  if fSetLayout <> VK_NULL_HANDLE then
  begin
    vkDestroyDescriptorSetLayout(fVulkanDevice.Handle, fSetLayout, nil);
    fSetLayout := VK_NULL_HANDLE;
  end;

  if fShaderModule <> VK_NULL_HANDLE then
  begin
    vkDestroyShaderModule(fVulkanDevice.Handle, fShaderModule, nil);
    fShaderModule := VK_NULL_HANDLE;
  end;
end;

procedure TvgComputeEngine.CreateSetLayout;
var
  Bindings   : array of TVkDescriptorSetLayoutBinding;
  LayoutInfo : TVkDescriptorSetLayoutCreateInfo;
  I          : Integer;
begin
  SetLength(Bindings, fBindingCount);
  FillChar(Bindings[0], fBindingCount * SizeOf(TVkDescriptorSetLayoutBinding), 0);

  for I := 0 to fBindingCount - 1 do
  begin
    Bindings[I].binding            := TvkUint32(I);
    Bindings[I].descriptorType     := VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    Bindings[I].descriptorCount    := 1;
    Bindings[I].stageFlags         := TVkShaderStageFlags(VK_SHADER_STAGE_COMPUTE_BIT);
    Bindings[I].pImmutableSamplers := nil;
  end;

  FillChar(LayoutInfo, SizeOf(LayoutInfo), 0);
  LayoutInfo.sType        := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
  LayoutInfo.pNext        := nil;
  LayoutInfo.flags        := 0;
  LayoutInfo.bindingCount := fBindingCount;
  LayoutInfo.pBindings    := @Bindings[0];

  if vkCreateDescriptorSetLayout(fVulkanDevice.Handle, @LayoutInfo, nil, @fSetLayout) <> VK_SUCCESS then
    raise EvgComputeException.Create('Compute engine: failed to create descriptor set layout');
end;

procedure TvgComputeEngine.CreateDescriptorPool;
var
  PoolSize : TVkDescriptorPoolSize;
  PoolInfo : TVkDescriptorPoolCreateInfo;
begin
  FillChar(PoolSize, SizeOf(PoolSize), 0);
  PoolSize.type_           := VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
  PoolSize.descriptorCount := TvkUint32(fBindingCount * fSetCount);

  FillChar(PoolInfo, SizeOf(PoolInfo), 0);
  PoolInfo.sType         := VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
  PoolInfo.pNext         := nil;
  PoolInfo.flags         := 0;
  PoolInfo.maxSets       := TvkUint32(fSetCount);
  PoolInfo.poolSizeCount := 1;
  PoolInfo.pPoolSizes    := @PoolSize;

  if vkCreateDescriptorPool(fVulkanDevice.Handle, @PoolInfo, nil, @fDescPool) <> VK_SUCCESS then
    raise EvgComputeException.Create('Compute engine: failed to create descriptor pool');
end;

procedure TvgComputeEngine.AllocateDescriptorSets;
var
  Layouts   : array of TVkDescriptorSetLayout;
  AllocInfo : TVkDescriptorSetAllocateInfo;
  I         : Integer;
begin
  SetLength(Layouts, fSetCount);
  for I := 0 to fSetCount - 1 do
    Layouts[I] := fSetLayout;

  SetLength(fDescSets, fSetCount);

  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType              := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
  AllocInfo.pNext              := nil;
  AllocInfo.descriptorPool     := fDescPool;
  AllocInfo.descriptorSetCount := TvkUint32(fSetCount);
  AllocInfo.pSetLayouts        := @Layouts[0];

  if vkAllocateDescriptorSets(fVulkanDevice.Handle, @AllocInfo, @fDescSets[0]) <> VK_SUCCESS then
    raise EvgComputeException.Create('Compute engine: failed to allocate descriptor sets');
end;

procedure TvgComputeEngine.CreatePipelineLayout;
var
  PushRange  : TVkPushConstantRange;
  LayoutInfo : TVkPipelineLayoutCreateInfo;
begin
  FillChar(LayoutInfo, SizeOf(LayoutInfo), 0);
  LayoutInfo.sType          := VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
  LayoutInfo.pNext          := nil;
  LayoutInfo.flags          := 0;
  LayoutInfo.setLayoutCount := 1;
  LayoutInfo.pSetLayouts    := @fSetLayout;

  if fPushSize > 0 then
  begin
    FillChar(PushRange, SizeOf(PushRange), 0);
    PushRange.stageFlags := TVkShaderStageFlags(VK_SHADER_STAGE_COMPUTE_BIT);
    PushRange.offset     := 0;
    PushRange.size       := TvkUint32(fPushSize);

    LayoutInfo.pushConstantRangeCount := 1;
    LayoutInfo.pPushConstantRanges    := @PushRange;
  end
  else
  begin
    LayoutInfo.pushConstantRangeCount := 0;
    LayoutInfo.pPushConstantRanges    := nil;
  end;

  if vkCreatePipelineLayout(fVulkanDevice.Handle, @LayoutInfo, nil, @fPipelineLayout) <> VK_SUCCESS then
    raise EvgComputeException.Create('Compute engine: failed to create pipeline layout');
end;

procedure TvgComputeEngine.CreateComputePipeline;
var
  Source   : String;
  Stage    : TVkPipelineShaderStageCreateInfo;
  PipeInfo : TVkComputePipelineCreateInfo;
  EntryPt  : TvkCharString;
begin
  Source := GetShaderSource;

  if Trim(Source) = '' then
    raise EvgComputeException.Create('Compute engine: GetShaderSource returned nothing');

  // Compiles the GLSL with glslangValidator from the installed Vulkan SDK.
  CompileAndCreateShaderModule(fVulkanDevice.Handle,
                               fShaderModule,
                               Source,
                               shaderc_compute_shader);

  if fShaderModule = VK_NULL_HANDLE then
    raise EvgComputeException.Create('Compute engine: shader module was not created');

  EntryPt := 'main';

  FillChar(Stage, SizeOf(Stage), 0);
  Stage.sType               := VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
  Stage.pNext               := nil;
  Stage.flags               := 0;
  Stage.stage               := VK_SHADER_STAGE_COMPUTE_BIT;
  Stage.module              := fShaderModule;
  Stage.pName               := PVkChar(EntryPt);
  Stage.pSpecializationInfo := nil;

  FillChar(PipeInfo, SizeOf(PipeInfo), 0);
  PipeInfo.sType              := VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
  PipeInfo.pNext              := nil;
  PipeInfo.flags              := 0;
  PipeInfo.stage              := Stage;
  PipeInfo.layout             := fPipelineLayout;
  PipeInfo.basePipelineHandle := VK_NULL_HANDLE;
  PipeInfo.basePipelineIndex  := -1;

  if vkCreateComputePipelines(fVulkanDevice.Handle,
                              VK_NULL_HANDLE,
                              1,
                              @PipeInfo,
                              nil,
                              @fPipeline) <> VK_SUCCESS then
    raise EvgComputeException.Create('Compute engine: failed to create compute pipeline');
end;

Procedure TvgComputeEngine.BuildPipeline(aSetCount, aBindingCount, aPushConstantSize: Integer);
begin
  CustomAssert(Assigned(fVulkanDevice), 'Compute engine: Vulkan device not assigned', Self);
  CustomAssert(aSetCount > 0,     'Compute engine: set count must be positive', Self);
  CustomAssert(aBindingCount > 0, 'Compute engine: binding count must be positive', Self);

  DestroyPipelineObjects;

  fSetCount     := aSetCount;
  fBindingCount := aBindingCount;
  fPushSize     := Max(aPushConstantSize, 0);
  fLastError    := '';

  try
    CreateSetLayout;
    CreateDescriptorPool;
    AllocateDescriptorSets;
    CreatePipelineLayout;
    CreateComputePipeline;
  except
    on E: Exception do
    begin
      fLastError := E.Message;
      DestroyPipelineObjects;
      raise;
    end;
  end;
end;

Procedure TvgComputeEngine.UpdateDescriptorSet(aSetIndex: Integer;
                                               const aBuffers: array of TpvVulkanBuffer);
var
  BufInfos : array of TVkDescriptorBufferInfo;
  Writes   : array of TVkWriteDescriptorSet;
  I        : Integer;
begin
  CustomAssert(Assigned(fVulkanDevice), 'Compute engine: Vulkan device not assigned', Self);
  CustomAssert((aSetIndex >= 0) and (aSetIndex < Length(fDescSets)),
               'Compute engine: descriptor set index out of range', Self);
  CustomAssert(Length(aBuffers) = fBindingCount,
               'Compute engine: buffer count does not match the binding count', Self);

  SetLength(BufInfos, fBindingCount);
  SetLength(Writes,   fBindingCount);

  FillChar(BufInfos[0], fBindingCount * SizeOf(TVkDescriptorBufferInfo), 0);
  FillChar(Writes[0],   fBindingCount * SizeOf(TVkWriteDescriptorSet), 0);

  for I := 0 to fBindingCount - 1 do
  begin
    CustomAssert(Assigned(aBuffers[I]),
                 Format('Compute engine: buffer for binding %d not assigned', [I]), Self);

    BufInfos[I].buffer := aBuffers[I].Handle;
    BufInfos[I].offset := 0;
    BufInfos[I].range  := VK_WHOLE_SIZE;

    Writes[I].sType           := VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    Writes[I].pNext           := nil;
    Writes[I].dstSet          := fDescSets[aSetIndex];
    Writes[I].dstBinding      := TvkUint32(I);
    Writes[I].dstArrayElement := 0;
    Writes[I].descriptorCount := 1;
    Writes[I].descriptorType  := VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    Writes[I].pBufferInfo     := @BufInfos[I];
  end;

  vkUpdateDescriptorSets(fVulkanDevice.Handle, TvkUint32(fBindingCount), @Writes[0], 0, nil);
end;

Function TvgComputeEngine.DispatchGroupsFor(aWorkItems: Integer): TvkUint32;
var
  Local : Integer;
begin
  Local := Max(GetLocalSizeX, 1);

  if aWorkItems <= 0 then
    Result := 0
  else
    Result := TvkUint32((aWorkItems + Local - 1) div Local);
end;

Procedure TvgComputeEngine.RecordDispatch(aCommandBuffer : TvgCommandBuffer;
                                          aSetIndex      : Integer;
                                          aPushData      : Pointer;
                                          aGroupsX       : TvkUint32;
                                          aGroupsY       : TvkUint32;
                                          aGroupsZ       : TvkUint32);
var
  DSet : TVkDescriptorSet;
begin
  CustomAssert(Assigned(aCommandBuffer), 'Compute engine: command buffer not assigned', Self);
  CustomAssert(fPipeline <> VK_NULL_HANDLE, 'Compute engine: pipeline not built', Self);
  CustomAssert((aSetIndex >= 0) and (aSetIndex < Length(fDescSets)),
               'Compute engine: descriptor set index out of range', Self);

  if (aGroupsX = 0) or (aGroupsY = 0) or (aGroupsZ = 0) then Exit;

  DSet := fDescSets[aSetIndex];

  aCommandBuffer.CmdBindPipeline(VK_PIPELINE_BIND_POINT_COMPUTE, fPipeline);

  aCommandBuffer.CmdBindDescriptorSets(VK_PIPELINE_BIND_POINT_COMPUTE,
                                       fPipelineLayout,
                                       0, 1, @DSet, 0, nil);

  if (fPushSize > 0) and Assigned(aPushData) then
    aCommandBuffer.CmdPushConstants(fPipelineLayout,
                                    TVkShaderStageFlags(VK_SHADER_STAGE_COMPUTE_BIT),
                                    0,
                                    TvkUint32(fPushSize),
                                    aPushData);

  aCommandBuffer.CmdDispatch(aGroupsX, aGroupsY, aGroupsZ);
end;

Procedure TvgComputeEngine.RecordDispatchFor(aCommandBuffer : TvgCommandBuffer;
                                             aSetIndex      : Integer;
                                             aPushData      : Pointer;
                                             aWorkItems     : Integer);
begin
  RecordDispatch(aCommandBuffer, aSetIndex, aPushData, DispatchGroupsFor(aWorkItems), 1, 1);
end;

class Procedure TvgComputeEngine.RecordBufferBarrier(aCommandBuffer : TvgCommandBuffer;
                                                     aBuffer        : TpvVulkanBuffer;
                                                     aConsumer      : TvgComputeConsumer);
var
  Barrier  : TVkBufferMemoryBarrier;
  DstStage : TVkPipelineStageFlags;
  DstAcc   : TVkAccessFlags;
begin
  if not Assigned(aCommandBuffer) or not Assigned(aBuffer) then Exit;

  case aConsumer of
    ccVertexInput:
      begin
        DstStage := TVkPipelineStageFlags(VK_PIPELINE_STAGE_VERTEX_INPUT_BIT);
        DstAcc   := TVkAccessFlags(VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT);
      end;
    ccIndexInput:
      begin
        DstStage := TVkPipelineStageFlags(VK_PIPELINE_STAGE_VERTEX_INPUT_BIT);
        DstAcc   := TVkAccessFlags(VK_ACCESS_INDEX_READ_BIT);
      end;
    ccIndirect:
      begin
        DstStage := TVkPipelineStageFlags(VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT);
        DstAcc   := TVkAccessFlags(VK_ACCESS_INDIRECT_COMMAND_READ_BIT);
      end;
    ccHost:
      begin
        DstStage := TVkPipelineStageFlags(VK_PIPELINE_STAGE_HOST_BIT);
        DstAcc   := TVkAccessFlags(VK_ACCESS_HOST_READ_BIT);
      end;
  else
    // ccCompute
    DstStage := TVkPipelineStageFlags(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT);
    DstAcc   := TVkAccessFlags(VK_ACCESS_SHADER_READ_BIT);
  end;

  FillChar(Barrier, SizeOf(Barrier), 0);
  Barrier.sType               := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
  Barrier.pNext               := nil;
  Barrier.srcAccessMask       := TVkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT);
  Barrier.dstAccessMask       := DstAcc;
  Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  Barrier.buffer              := aBuffer.Handle;
  Barrier.offset              := 0;
  Barrier.size                := VK_WHOLE_SIZE;

  aCommandBuffer.CmdPipelineBarrier(
    TVkPipelineStageFlags(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT),
    DstStage,
    0,
    0, nil,
    1, @Barrier,
    0, nil);
end;

end.
