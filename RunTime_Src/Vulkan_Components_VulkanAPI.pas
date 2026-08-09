unit Vulkan_Components_VulkanAPI;


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


Interface

uses
  SysUtils,
  Classes,
  Generics.Collections,
  vulkan;

type

{==============================================================================}
{ Descriptor Binding Flags                                                     }
{==============================================================================}

  TvgDescriptorBindingFlag = (
                                dbfPartiallyBound,
                                dbfUpdateAfterBind,
                                dbfUpdateUnusedWhilePending,
                                dbfVariableDescriptorCount
                              );

  TvgDescriptorBindingFlags = set of TvgDescriptorBindingFlag;

{==============================================================================}
{ Descriptor Binding Description                                               }
{==============================================================================}


  TvgDescriptorBinding = record
    Binding            : UInt32;
    DescriptorType     : TVkDescriptorType;
    DescriptorCount    : UInt32;
    StageFlags         : TVkShaderStageFlags;
    BindingFlags       : TvgDescriptorBindingFlags;
    ImmutableSamplers  : PVkSampler;
  end;

{==============================================================================}
{ TvgDescriptorSetNative                                                       }
{==============================================================================}

  TvgDescriptorSet_VulkanAPI = class
  private
    fDevice                  : TVkDevice;

    fBindings                : TList<TvgDescriptorBinding>;

    fDescriptorPool          : TVkDescriptorPool;
    fDescriptorSetLayout     : TVkDescriptorSetLayout;
    fDescriptorSet           : TVkDescriptorSet;

    fVariableDescriptorCount : UInt32;

    fPoolFlags               : TVkDescriptorPoolCreateFlags;
    fLayoutFlags             : TVkDescriptorSetLayoutCreateFlags;

    procedure CreateLayout;
    procedure CreatePool;
    procedure AllocateSet;

    function ConvertBindingFlags( const Flags : TvgDescriptorBindingFlags ) : TVkDescriptorBindingFlags;

  public
    constructor Create( const ADevice : TVkDevice );

    destructor Destroy; override;

    procedure AddBinding( const ABinding        : UInt32;
                          const ADescriptorType : TVkDescriptorType;
                          const ADescriptorCount: UInt32;
                          const AStageFlags     : TVkShaderStageFlags;
                          const ABindingFlags   : TvgDescriptorBindingFlags = [];
                          const AImmutableSamplers : PVkSampler = nil
                        );

    procedure Build(  const AVariableDescriptorCount : UInt32 = 0 );

    procedure DestroyResources;

{------------------------------------------------------------------------------}
{ Descriptor Updates                                                           }
{------------------------------------------------------------------------------}

    procedure UpdateImage(  const Binding       : UInt32;
                            const ArrayElement  : UInt32;
                            const DescriptorType: TVkDescriptorType;
                            const ImageView     : TVkImageView;
                            const Sampler       : TVkSampler;
                            const ImageLayout   : TVkImageLayout
                          );

    procedure UpdateBuffer( const Binding       : UInt32;
                            const ArrayElement  : UInt32;
                            const DescriptorType: TVkDescriptorType;
                            const Buffer        : TVkBuffer;
                            const Offset        : TVkDeviceSize;
                            const Range         : TVkDeviceSize
                          );

{------------------------------------------------------------------------------}
{ Accessors                                                                    }
{------------------------------------------------------------------------------}

    property Handle : TVkDescriptorSet read fDescriptorSet;

    property Layout : TVkDescriptorSetLayout read fDescriptorSetLayout;

    property Pool : TVkDescriptorPool read fDescriptorPool;
  end;



implementation

{==============================================================================}
{ TvgDescriptorSetNative                                                       }
{==============================================================================}

constructor TvgDescriptorSet_VulkanAPI.Create(
  const ADevice : TVkDevice
);
begin
  inherited Create;

  fDevice := ADevice;

  fBindings := TList<TvgDescriptorBinding>.Create;
end;

destructor TvgDescriptorSet_VulkanAPI.Destroy;
begin
  DestroyResources;

  FreeAndNil(fBindings);

  inherited;
end;

procedure TvgDescriptorSet_VulkanAPI.DestroyResources;
begin

  if fDescriptorPool <> VK_NULL_HANDLE then
  begin
    vkDestroyDescriptorPool(
      fDevice,
      fDescriptorPool,
      nil
    );

    fDescriptorPool := VK_NULL_HANDLE;
  end;

  if fDescriptorSetLayout <> VK_NULL_HANDLE then
  begin
    vkDestroyDescriptorSetLayout(
      fDevice,
      fDescriptorSetLayout,
      nil
    );

    fDescriptorSetLayout := VK_NULL_HANDLE;
  end;

end;

function TvgDescriptorSet_VulkanAPI.ConvertBindingFlags( const Flags : TvgDescriptorBindingFlags) : TVkDescriptorBindingFlags;
begin
  Result := 0;

  if dbfPartiallyBound in Flags then
    Result := Result or TVkDescriptorBindingFlags(VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT);

  if dbfUpdateAfterBind in Flags then
    Result := Result or TVkDescriptorBindingFlags(VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT);

  if dbfUpdateUnusedWhilePending in Flags then
    Result := Result or TVkDescriptorBindingFlags(VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT);

  if dbfVariableDescriptorCount in Flags then
    Result := Result or TVkDescriptorBindingFlags(VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT);
end;

procedure TvgDescriptorSet_VulkanAPI.AddBinding(
                                const ABinding         : UInt32;
                                const ADescriptorType  : TVkDescriptorType;
                                const ADescriptorCount : UInt32;
                                const AStageFlags      : TVkShaderStageFlags;
                                const ABindingFlags    : TvgDescriptorBindingFlags;
                                const AImmutableSamplers : PVkSampler
                              );
var
  B : TvgDescriptorBinding;
begin

  FillChar(B, SizeOf(B), 0);

  B.Binding           := ABinding;
  B.DescriptorType    := ADescriptorType;
  B.DescriptorCount   := ADescriptorCount;
  B.StageFlags        := AStageFlags;
  B.BindingFlags      := ABindingFlags;
  B.ImmutableSamplers := AImmutableSamplers;

  fBindings.Add(B);

  if dbfUpdateAfterBind in ABindingFlags then
  begin
    fPoolFlags :=
      fPoolFlags or TVkDescriptorPoolCreateFlags( VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT);

    fLayoutFlags :=
      fLayoutFlags or TVkDescriptorPoolCreateFlags(VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT);
  end;

end;

procedure TvgDescriptorSet_VulkanAPI.Build(
  const AVariableDescriptorCount : UInt32
);
begin

  fVariableDescriptorCount := AVariableDescriptorCount;

  CreateLayout;
  CreatePool;
  AllocateSet;

end;

procedure TvgDescriptorSet_VulkanAPI.CreateLayout;
var
  Bindings          : array of TVkDescriptorSetLayoutBinding;
  BindingFlags      : array of TVkDescriptorBindingFlags;

  LayoutInfo        : TVkDescriptorSetLayoutCreateInfo;

  FlagsInfo         : TVkDescriptorSetLayoutBindingFlagsCreateInfo;

  I                 : Integer;

begin

  SetLength(Bindings, fBindings.Count);
  SetLength(BindingFlags, fBindings.Count);

  for I := 0 to fBindings.Count - 1 do
  begin

    Bindings[I].binding := fBindings[I].Binding;

    Bindings[I].descriptorType :=  fBindings[I].DescriptorType;

    Bindings[I].descriptorCount := fBindings[I].DescriptorCount;

    Bindings[I].stageFlags :=      fBindings[I].StageFlags;

    Bindings[I].pImmutableSamplers := fBindings[I].ImmutableSamplers;

    BindingFlags[I] :=    ConvertBindingFlags(fBindings[I].BindingFlags );

  end;

  FillChar(FlagsInfo, SizeOf(FlagsInfo), 0);

  FlagsInfo.sType :=
    VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO;

  FlagsInfo.bindingCount := Length(BindingFlags);

  FlagsInfo.pBindingFlags :=@BindingFlags[0];

  FillChar(LayoutInfo, SizeOf(LayoutInfo), 0);

  LayoutInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;

  LayoutInfo.pNext := @FlagsInfo;

  LayoutInfo.flags := fLayoutFlags;

  LayoutInfo.bindingCount := Length(Bindings);

  LayoutInfo.pBindings :=  @Bindings[0];

  if vkCreateDescriptorSetLayout(  fDevice,
                                   @LayoutInfo,
                                   nil,
                                   @fDescriptorSetLayout
                                 ) <> VK_SUCCESS then
  begin
    raise Exception.Create(
      'Failed to create descriptor set layout'
    );
  end;

end;

procedure TvgDescriptorSet_VulkanAPI.CreatePool;
var
  PoolSizes : array of TVkDescriptorPoolSize;

  PoolInfo  : TVkDescriptorPoolCreateInfo;

  I         : Integer;

begin

  SetLength(PoolSizes, fBindings.Count);

  for I := 0 to fBindings.Count - 1 do
  begin

    PoolSizes[I].Type_ :=
      fBindings[I].DescriptorType;

    PoolSizes[I].descriptorCount := fBindings[I].DescriptorCount;

    if ( dbfVariableDescriptorCount in  fBindings[I].BindingFlags )  and
       (fVariableDescriptorCount > 0) then
    begin
      PoolSizes[I].descriptorCount :=
        fVariableDescriptorCount;
    end;

  end;

  FillChar(PoolInfo, SizeOf(PoolInfo), 0);

  PoolInfo.sType := VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;

  PoolInfo.flags :=  fPoolFlags;

  PoolInfo.maxSets := 1;

  PoolInfo.poolSizeCount := Length(PoolSizes);

  PoolInfo.pPoolSizes := @PoolSizes[0];

  if vkCreateDescriptorPool( fDevice,
                             @PoolInfo,
                             nil,
                             @fDescriptorPool
                           ) <> VK_SUCCESS then
  begin
    raise Exception.Create(
      'Failed to create descriptor pool'
    );
  end;

end;

procedure TvgDescriptorSet_VulkanAPI.AllocateSet;
var
  AllocInfo     : TVkDescriptorSetAllocateInfo;

  VarCountInfo  : TVkDescriptorSetVariableDescriptorCountAllocateInfo;

begin

  FillChar(AllocInfo, SizeOf(AllocInfo), 0);

  AllocInfo.sType :=
    VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;

  AllocInfo.descriptorPool := fDescriptorPool;

  AllocInfo.descriptorSetCount := 1;

  AllocInfo.pSetLayouts :=   @fDescriptorSetLayout;

  if fVariableDescriptorCount > 0 then
  begin

    FillChar(VarCountInfo, SizeOf(VarCountInfo), 0);

    VarCountInfo.sType :=
      VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO;

    VarCountInfo.descriptorSetCount := 1;

    VarCountInfo.pDescriptorCounts :=  @fVariableDescriptorCount;

    AllocInfo.pNext :=  @VarCountInfo;

  end;

  if vkAllocateDescriptorSets( fDevice,
                               @AllocInfo,
                               @fDescriptorSet
                             ) <> VK_SUCCESS then
  begin
    raise Exception.Create(
      'Failed to allocate descriptor set'
    );
  end;

end;

procedure TvgDescriptorSet_VulkanAPI.UpdateImage(
  const Binding       : UInt32;
  const ArrayElement  : UInt32;
  const DescriptorType: TVkDescriptorType;
  const ImageView     : TVkImageView;
  const Sampler       : TVkSampler;
  const ImageLayout   : TVkImageLayout
);
var
  ImageInfo : TVkDescriptorImageInfo;
  WriteInfo : TVkWriteDescriptorSet;
begin

  FillChar(ImageInfo, SizeOf(ImageInfo), 0);

  ImageInfo.imageView := ImageView;
  ImageInfo.sampler   := Sampler;
  ImageInfo.imageLayout := ImageLayout;

  FillChar(WriteInfo, SizeOf(WriteInfo), 0);

  WriteInfo.sType :=
    VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;

  WriteInfo.dstSet := fDescriptorSet;
  WriteInfo.dstBinding := Binding;
  WriteInfo.dstArrayElement := ArrayElement;
  WriteInfo.descriptorCount := 1;
  WriteInfo.descriptorType := DescriptorType;
  WriteInfo.pImageInfo := @ImageInfo;

  vkUpdateDescriptorSets(
                          fDevice,
                          1,
                          @WriteInfo,
                          0,
                          nil
                        );

end;

procedure TvgDescriptorSet_VulkanAPI.UpdateBuffer(
  const Binding       : UInt32;
  const ArrayElement  : UInt32;
  const DescriptorType: TVkDescriptorType;
  const Buffer        : TVkBuffer;
  const Offset        : TVkDeviceSize;
  const Range         : TVkDeviceSize
);
var
  BufferInfo : TVkDescriptorBufferInfo;
  WriteInfo  : TVkWriteDescriptorSet;
begin

  FillChar(BufferInfo, SizeOf(BufferInfo), 0);

  BufferInfo.buffer := Buffer;
  BufferInfo.offset := Offset;
  BufferInfo.range := Range;

  FillChar(WriteInfo, SizeOf(WriteInfo), 0);

  WriteInfo.sType :=
    VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;

  WriteInfo.dstSet := fDescriptorSet;
  WriteInfo.dstBinding := Binding;
  WriteInfo.dstArrayElement := ArrayElement;
  WriteInfo.descriptorCount := 1;
  WriteInfo.descriptorType := DescriptorType;
  WriteInfo.pBufferInfo := @BufferInfo;

  vkUpdateDescriptorSets(
                          fDevice,
                          1,
                          @WriteInfo,
                          0,
                          nil
                        );

end;



end.
