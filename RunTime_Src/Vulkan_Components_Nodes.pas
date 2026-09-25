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
 *                                                                            *
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
unit Vulkan_Components_Nodes;

interface

{$INCLUDE VulkanPackage.inc}

uses
 // FastMM5,
  System.SysUtils,
  System.Generics.Collections,   //MUST STAY HERE
  System.Generics.Defaults,
  System.Classes,
  Vulkan,
  PasVulkan.Math,
  Vulkan_Components,
  Vulkan_Components_Lookups,
  Vulkan_Components_Descriptors;   //MUST STAY HERE

//Type
 (*
 TvgObject_Data<TInstance, TVertex> = Class(TvgObject)
  private

    function GetItem(Index: Integer): TVertex;
    procedure SetItem(Index: Integer; const Value: TVertex);

   Protected
    fInstanceData    : TInstance;
    fVertexDataArray : TvgGenericDataArray<TVertex>;   //generic vertex data

    fIndexType    : TvgIndexType;
    fCurrentIndex : Integer;
    fIndex16      : Array Of TvkUint16;
    fIndex32      : Array Of TvkUint32;
    //index data

   Public

    constructor Create; Override;
    destructor Destroy; override;

    procedure Add(const Item: TVertex);
    procedure Clear;

    Procedure AddIndex(const Index : TvkUint32);
    Procedure SetIndexLength(aLength:TvkUint32);
    Procedure ClearIndex;

    // methods for Vulkan API

    Function GetVertexDataPointer : Pointer ;  Override;  //Must point to Variables or Dynamic allocated mem
    Function GetVertexCount       : TvkUint32; Override;
    Function GetVertexDataSize    : TvkUint32; Override;
    Function GetVertexStride      : TvkUint32; Override;

    Function GetIndexDataPointer : Pointer ;  Override;  //Must point to Variables or Dynamic allocated mem
    Function GetIndexCount       : TVkUInt32; Override;
    Function GetIndexDataSize    : TVkUInt32; Override;
    Function GetIndexType        : TVkIndexType; Override;    //VK_INDEX_TYPE_UINT16

    Procedure VulkanDraw (aCommandBuffer: TvgCommandBuffer;
                          aPipe         : TvgGraphicPipeline;
                          aFrameIndex   : TvkUint32;
                       Var CommandCount : Integer); Override;

    property Items[Index: Integer]  : TVertex read GetItem  write SetItem; default;

 End;
 *)

implementation

(*

{ TvgRenderNode_Data<T> }

procedure TvgObject_Data<TInstance, TVertex>.Add(const Item: TVertex);
  Var L,I:Integer;
begin
  fDataChanged := True;
  fUploadNeeded:= True;

  fVertexDataArray.Add(Item);

  if (fIndexType = IT_16BIT) and (fVertexDataArray.Count>=65530) then
  Begin
  //switch to 32 bit index data
    fIndexType := IT_32BIT;
    L:= Length(fIndex16) ;
    if L>0 then
    Begin
      SetLength(fIndex32,L);
      for I := 0 to L-1 do
         fIndex32[I]:=fIndex16[I];
      SetLength(fIndex16,0);
    End;
  End;
end;

procedure TvgObject_Data<TInstance, TVertex>.AddIndex(const Index: TvkUint32);
  Var L:Integer;
begin
  fDataChanged := True;
  fUploadNeeded:= True;

  Inc(fCurrentIndex);

  case fIndexType of
    IT_16BIT: Begin
                L:=Length(findex16);
                if fCurrentIndex>=L then
                   SetLength(findex16, L+100);
                findex16[fCurrentIndex]:=Index;
    End;

    IT_32BIT: Begin
                L:=Length(findex32);
                if fCurrentIndex>=L then
                   SetLength(findex32, L+100);
                findex32[fCurrentIndex]:=Index;
    End;
  end;
end;

procedure TvgObject_Data<TInstance, TVertex>.Clear;
begin
  fVertexDataArray.Clear;
  fDataChanged := True;
end;

procedure TvgObject_Data<TInstance, TVertex>.ClearIndex;
begin

  case fIndexType of
    IT_16BIT: SetLength(fIndex16,0);
    IT_32BIT: SetLength(fIndex32,0);
  end;

  fIndexType    := IT_16BIT;
  fCurrentIndex := -1;
  fDataChanged := True;

end;

constructor TvgObject_Data<TInstance, TVertex>.Create;
begin
  inherited;

  fDataChanged := True;
  fUploadNeeded:= True;

  //nothing needed for generic array
  fCurrentIndex := -1;
  SetLength(fIndex16 ,100);

end;

destructor TvgObject_Data<TInstance, TVertex>.Destroy;
begin
  fVertexDataArray.Clear;

  SetLength(fIndex16 ,0);
  SetLength(fIndex32 ,0);

  inherited;
end;

function TvgObject_Data<TInstance, TVertex>.GetIndexCount: TVkUInt32;
begin
  Result := fCurrentIndex + 1;
end;

function TvgObject_Data<TInstance, TVertex>.GetIndexDataPointer: Pointer;
begin
  case fIndexType of
    IT_16BIT: Result := @fIndex16[0];
    IT_32BIT: Result := @fIndex32[0];
    else
      Result := @fIndex32[0];
  end;
end;

function TvgObject_Data<TInstance, TVertex>.GetIndexDataSize: TVkUInt32;
begin

  case fIndexType of
    IT_16BIT: Result := (fCurrentIndex + 1) * SizeOf(TvkUint16);
    IT_32BIT: Result := (fCurrentIndex + 1) * SizeOf(TvkUint32);
    else
      Result := (fCurrentIndex + 1) * SizeOf(TvkUint32);
  end;

end;

function TvgObject_Data<TInstance, TVertex>.GetIndexType: TVkIndexType;
begin

  case fIndexType of
    IT_16BIT: Result := VK_INDEX_TYPE_UINT16;
    IT_32BIT: Result := VK_INDEX_TYPE_UINT32;
    else
       Result := VK_INDEX_TYPE_UINT32;
  end;
end;

function TvgObject_Data<TInstance, TVertex>.GetItem(Index: Integer): TVertex;
begin

 Result := fVertexDataArray[Index];
end;

function TvgObject_Data<TInstance, TVertex>.GetVertexCount: TvkUint32;
begin
  Result := fVertexDataArray.Count;
end;

function TvgObject_Data<TInstance, TVertex>.GetVertexDataPointer: Pointer;
begin
  Result := fVertexDataArray.GetDataPointer;
end;

function TvgObject_Data<TInstance, TVertex>.GetVertexDataSize: TvkUint32;
begin
  Result := fVertexDataArray.GetDataSize;
end;

function TvgObject_Data<TInstance, TVertex>.GetVertexStride: TvkUint32;
begin
  Result :=  fVertexDataArray.GetDataStride ;
end;

procedure TvgObject_Data<TInstance, TVertex>.SetIndexLength(aLength: TvkUint32);
begin
  case fIndexType of
    IT_16BIT: SetLength(fIndex16,aLength);
    IT_32BIT: SetLength(fIndex32,aLength);
  end;
end;

procedure TvgObject_Data<TInstance, TVertex>.SetItem(Index: Integer; const Value: TVertex);
begin
  fVertexDataArray.Items[Index]:=Value  ;
end;

procedure TvgObject_Data<TInstance, TVertex>.VulkanDraw(aCommandBuffer: TvgCommandBuffer;
                                           aPipe         : TvgGraphicPipeline;
                                           aFrameIndex   : TvkUint32;
                                         var CommandCount: Integer);

  Var  VOffsets, InstOffset : TVkDeviceSize;
       IOffset,
       ICount  : TVkUInt32;
            I,PipeIndex  : integer;
            PC : TvgPushConstant;
        ConstOffset, ConstStride : TvkUint32;

        aBuffers: array[0..1] of TVkBuffer ;
        aOffsets: array[0..1] of TVkDeviceSize ;

begin
  If fVertexDataArray.Count=0 then exit;

  Assert(Assigned( aCommandBuffer),'Vulkan Buffer NOT assigned)');
  Assert(Assigned( aPipe),'Graphicpipeline NOT assigned)');
  Assert(Assigned( fInstanceBuffer),'INSTANCE Data Buffer NOT assigned)');
  Assert(Assigned( fVertexBuffer),'VERTEX Data Buffer NOT assigned)');

  VOffsets := 0;
  InstOffset  := 0;

  ICount  := GetIndexCount;
  IOffset := GetVertexDataSize + fVToIGap;

  aBuffers[0] := fVertexBuffer.Handle;
  aBuffers[1] := fInstanceBuffer.Handle;
  aOffsets[0]:=0;
  aOffsets[1]:=0;


 //INSTANCE Data  + //VERTEX Data
  aCommandBuffer.CmdBindVertexBuffers(0,            //firstBinding:TVkUInt32;;const const ); {$ifdef Windows}stdcall;{$else}{$ifdef Android}{$ifdef cpuarm}hardfloat;{$else}cdecl;{$endif}{$else}cdecl;{$endif}{$endif}
                                      2,            // bindingCount:TVkUInt32
                                      @aBuffers[0], //pBuffers:PVkBuffer;
                                      @aOffsets[0]); //pOffsets:PVkDeviceSize

  if (fCurrentIndex>=0) then
  Begin
      aCommandBuffer.CmdBindIndexBuffer( fVertexBuffer.Handle,  //   buffer:TVkBuffer;
                                         IOffset,             //offset:TVkDeviceSize;
                                         GetIndexType);       //indexType:TVkIndexType
  end;

  inc(CommandCount);

  ConstOffset := 0;


  PipeIndex := self.GetPipelineIndex(aPipe);
  If PipeIndex<>-1 then
  Begin
  End;


  if (fCurrentIndex>=0) then
  Begin
      aCommandBuffer.CmdDrawIndexed(ICount,    //   indexCount:TVkUInt32;
                                    1,         //   instanceCount:TVkUInt32;
                                    0,         //   firstIndex:TVkUInt32;
                                    0,         //   vertexOffset:TVkInt32;
                                    0);        //   firstInstance:TVkUInt32
  end else
  Begin
      aCommandBuffer.CmdDraw(fVertexDataArray.Count,
                             1,
                             0,
                             0);
  End;
end;
  *)
Initialization

 //  RegisterPushConstantType(TvgPushConstant_Data<T>);

Finalization


end.


