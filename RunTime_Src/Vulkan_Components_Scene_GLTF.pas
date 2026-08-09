unit Vulkan_Components_Scene_GLTF;

interface

//{*R *.res}

{$INCLUDE VulkanPackage.inc}

uses

  {$IFDEF FASTMM5}
  FastMM5,
  {$ENDIF}
  System.SysUtils,
  System.Generics.Collections,   //MUST STAY HERE
  System.Generics.Defaults,
  System.Classes,                //MUST STAY HERE
  System.TypInfo,
//  System.Rtti,               //MUST STAY HERE
  System.Math,
  System.SyncObjs,
  {$IFDEF TIMINGON}
  System.Diagnostics,
  {$ENDIF}
  Vulkan,
  PasVulkan.Types,
  PasVulkan.Math,
  PasVulkan.Collections,
  PasVulkan.Framework,
//  PasVulkan.PasGLTF
  Vulkan_Assert,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_Descriptors,
  Vulkan_Components_DataStore,
  Vulkan_Components_Nodes;


implementation


(*
// In TvgVulkanDataStore interface
procedure ExportToGLTF(const AFileName: string; AGLB: Boolean = True);  // AGLB=True for binary .glb, False for .gltf JSON

// Implementation
procedure TvgVulkanDataStore.ExportToGLTF(const AFileName: string; AGLB: Boolean = True);
var
  GLTF: TGLTF2;
  MainScene: TGLTF2Scene;
  ObjNode: TGLTF2Node;
  InstNode: TGLTF2Node;
  Mesh: TGLTF2Mesh;
  Primitive: TGLTF2MeshPrimitive;
  BufferIndex: Integer;
  BufferViewIndex: Integer;
  AccessorIndex: Integer;
  BufferData: TGLTFByteDynArray;
  CurrentOffset: TGLTFSize;
  Binding: Cardinal;
  IndexBinding: Cardinal;
  ObjIndex, VertexSetIndex, InstanceIndex, IndexSetIndex: Integer;
  ObjRec: TvgVulkanObjectRecord;
  Attr: TAttributeRecord;
  VType: TvgVertexDataType;
  IType: TInstanceDataType;
  Data: TBytes;
  IndexData: TBytes;
  Stride: Cardinal;
  Count: Integer;
  IndexCount: Integer;
  OffsetDict: TOffsetDict;
  InstanceOffsetDict: TInstanceOffsetDict;
  GLTFComponentType: TGLTFComponentType;
  GLTFAccessorType: TGLTFAccessorType;
  Semantic: string;
  I, J, K, L: Integer;
begin
  FCriticalSection.Enter;
  try
    GLTF := TGLTF2.Create(nil);
    try
      GLTF.Asset.Generator := 'Vulkan Components Exporter using PasVulkan.Framework';
      GLTF.Asset.Version := '2.0';

      // Create main scene
      MainScene := GLTF.Scenes.Add;
      MainScene.Name := 'MainScene';
      GLTF.Scene := 0;  // Set as default scene

      BufferIndex := -1;  // We'll use one big buffer for all data (concatenated)

      BufferData := nil;  // TGLTFByteDynArray is dynamic array of Byte
      CurrentOffset := 0;

      // Iterate over objects to build concatenated buffer and structures
      for ObjIndex := 0 to FDataObjects.Count - 1 do
      begin
        ObjRec := FDataObjects[ObjIndex];

        // Create node for object
        ObjNode := GLTF.Nodes.Add;
        ObjNode.Name := Format('Object_%d', [ObjIndex]);
        MainScene.Nodes.Add(GLTF.Nodes.Count - 1);

        // Handle instances (each instance as child node with matrix)
        for InstanceIndex := 0 to ObjRec.InstanceCounts.Count - 1 do  // Assume one instance set
        begin
          if ObjRec.InstanceBindings.Count > 0 then  // If has instances
          begin
            InstNode := GLTF.Nodes.Add;
            InstNode.Name := Format('Instance_%d_%d', [ObjIndex, InstanceIndex]);
            ObjNode.Children.Add(GLTF.Nodes.Count - 1);

            // Set matrix from instance data (assume idtMatrix)
            // Get matrix data: Need to extract from FData[ObjRec.InstanceBinding]
            // For example:
            // InstBinding := ObjRec.InstanceBinding;
            // if FData.TryGetValue(InstBinding, Data) then
            //   Move(Data[InstanceIndex * Stride + GetInstanceOffset(InstBinding, idtMatrix)], InstNode.Matrix, SizeOf(TGLTFMatrix4x4));
          end
          else
            InstNode := ObjNode;  // No instances, use object node

          // Add mesh to instance/node
          for VertexSetIndex := 0 to ObjRec.VertexBindings.Count - 1 do
          begin
            Binding := ObjRec.VertexBindings[VertexSetIndex];

            if not FData.TryGetValue(Binding, Data) then Continue;

            Count := GetCount(Binding);
            Stride := GetStride(Binding);

            // Append vertex data to global buffer
            SetLength(BufferData, CurrentOffset + Length(Data));
            Move(Data[0], BufferData[CurrentOffset], Length(Data));
            VertexOffsetBase := CurrentOffset;
            CurrentOffset := CurrentOffset + Length(Data);

            // Create mesh
            Mesh := GLTF.Meshes.Add;
            Mesh.Name := Format('Mesh_%d_%d', [ObjIndex, VertexSetIndex]);
            InstNode.Mesh := GLTF.Meshes.Count - 1;

            Primitive := Mesh.Primitives.Add;
            Primitive.Mode := GLTF_PRIMITIVE_MODE_TRIANGLES;  // Assume triangles

            // Find attributes for this binding
            for Attr in FAttributes do
            begin
              if (Attr.Binding = Binding) and (Attr.DataType.Kind = akVertex) then
              begin
                if FOffsets.TryGetValue(Binding, OffsetDict) then
                begin
                  for VType in Attr.DataType.GetVertexTypes do
                  begin
                    if OffsetDict.TryGetValue(VType, AttrOffset) then
                    begin
                      // Create buffer view for attribute
                      BufferView := GLTF.BufferViews.Add;
                      BufferView.Buffer := 0;  // Single buffer
                      BufferView.ByteOffset := VertexOffsetBase + AttrOffset;
                      BufferView.ByteLength := Count * GetVertexSize(VType);
                      BufferView.ByteStride := Stride;
                      BufferView.Target := GLTF_BUFFER_VIEW_TARGET_ARRAY_BUFFER;

                      // Create accessor
                      Accessor := GLTF.Accessors.Add;
                      Accessor.BufferView := GLTF.BufferViews.Count - 1;
                      Accessor.ByteOffset := 0;
                      Accessor.Count := Count;

                      case VType of
                        vdtPosition: begin
                          Semantic := 'POSITION';
                          GLTFAccessorType := GLTF_ACCESSOR_TYPE_VEC3;
                          GLTFComponentType := GLTF_COMPONENT_TYPE_FLOAT;
                        end;
                        vdtNormal: begin
                          Semantic := 'NORMAL';
                          GLTFAccessorType := GLTF_ACCESSOR_TYPE_VEC3;
                          GLTFComponentType := GLTF_COMPONENT_TYPE_FLOAT;
                        end;
                        vdtTexCoord: begin
                          Semantic := 'TEXCOORD_0';  // Assume first
                          GLTFAccessorType := GLTF_ACCESSOR_TYPE_VEC2;
                          GLTFComponentType := GLTF_COMPONENT_TYPE_FLOAT;
                        end;
                        vdtTangent: begin
                          Semantic := 'TANGENT';
                          GLTFAccessorType := GLTF_ACCESSOR_TYPE_VEC4;  // xyz + sign
                          GLTFComponentType := GLTF_COMPONENT_TYPE_FLOAT;
                        end;
                        // Add others: color (COLOR_0, VEC4), etc.
                        else Continue;
                      end;

                      Accessor.ComponentType := GLTFComponentType;
                      Accessor.Type_ := GLTFAccessorType;

                      // Add to primitive
                      Primitive.Attributes.Add(Semantic, GLTF.Accessors.Count - 1);
                    end;
                  end;
                end;
              end;
            end;

            // Indices
            for IndexSetIndex := 0 to ObjRec.IndexBindings.Count - 1 do
            begin
              IndexBinding := ObjRec.IndexBindings[IndexSetIndex];

              if FIndexDatas.TryGetValue(IndexBinding, IndexData) then
              begin
                IndexCount := GetIndexCount(IndexBinding);

                // Append index data
                SetLength(BufferData, CurrentOffset + Length(IndexData));
                Move(IndexData[0], BufferData[CurrentOffset], Length(IndexData));
                IndexOffsetBase := CurrentOffset;
                CurrentOffset := CurrentOffset + Length(IndexData);

                // Buffer view for indices
                BufferView := GLTF.BufferViews.Add;
                BufferView.Buffer := 0;
                BufferView.ByteOffset := IndexOffsetBase;
                BufferView.ByteLength := Length(IndexData);
                BufferView.Target := GLTF_BUFFER_VIEW_TARGET_ELEMENT_ARRAY_BUFFER;

                // Accessor for indices
                Accessor := GLTF.Accessors.Add;
                Accessor.BufferView := GLTF.BufferViews.Count - 1;
                Accessor.ByteOffset := 0;
                Accessor.Count := IndexCount;

Accessor.ComponentType := IfThen(GetIndexType(IndexBinding) = itUInt16,
                                   GLTF_COMPONENT_TYPE_UNSIGNED_SHORT,
                                   GLTF_COMPONENT_TYPE_UNSIGNED_INT);
              //  Accessor.ComponentType := IfThen(FIndexType = itUInt16, GLTF_COMPONENT_TYPE_UNSIGNED_SHORT, GLTF_COMPONENT_TYPE_UNSIGNED_INT);
                Accessor.Type_ := GLTF_ACCESSOR_TYPE_SCALAR;

                Primitive.Indices := GLTF.Accessors.Count - 1;
              end;
            end;
          end;
        end;
      end;

      // Add the single buffer
      if Length(BufferData) > 0 then
      begin
        Buffer := GLTF.Buffers.Add;
        Buffer.ByteLength := Length(BufferData);
        Buffer.Data := BufferData;  // Assign dynamic array
        if AGLB then
          Buffer.URI := '';  // Embedded in GLB
        else
          Buffer.URI := ExtractFileName(ChangeFileExt(AFileName, '.bin'));  // Separate bin file
      end;

      // Save
      GLTF.SaveToFile(AFileName, AGLB);

    finally
      GLTF.Free;
    end;
  finally
    FCriticalSection.Leave;
  end;
end;
end.
*)


end.
