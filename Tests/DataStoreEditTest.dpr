program DataStoreEditTest;

{$APPTYPE CONSOLE}

{ Exercises editing a TvgVulkanDataStore after it has been built: growing an
  object that is not the last one, deleting objects, removing vertices,
  resizing, and compacting.  Nothing here touches Vulkan: every edit happens
  in the store's CPU arrays, so it can be driven without a device.

  The recurring check is that an edit to one object never changes another
  object's data - the store packs every object into shared arrays, so that is
  exactly what goes wrong when a range is grown, shrunk or moved carelessly. }

uses
  System.SysUtils,
  PasVulkan.Math,
  Vulkan_Components_Lookups,
  Vulkan_Components_Camera,
  Vulkan_Components_DataStore;

var
  Failures : Integer = 0;

procedure Check(const Name: string; Got, Expect: Boolean);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-44s %s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-44s got %s expected %s',
      [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

procedure CheckInt(const Name: string; Got, Expect: Int64);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-44s %d', [Name, Got]))
  else
  begin
    Writeln(Format('  FAIL %-44s got %d expected %d', [Name, Got, Expect]));
    Inc(Failures);
  end;
end;

procedure CheckVec(const Name: string; const Got, Expect: TpvVector3);
begin
  if (Got.x = Expect.x) and (Got.y = Expect.y) and (Got.z = Expect.z) then
    Writeln(Format('  ok   %-44s (%.1f %.1f %.1f)', [Name, Got.x, Got.y, Got.z]))
  else
  begin
    Writeln(Format('  FAIL %-44s got (%.1f %.1f %.1f) expected (%.1f %.1f %.1f)',
      [Name, Got.x, Got.y, Got.z, Expect.x, Expect.y, Expect.z]));
    Inc(Failures);
  end;
end;

function V(X, Y, Z: Single): TpvVector3;
begin
  Result := TpvVector3.Create(X, Y, Z);
end;

{ A store with position + object ID, indexed, automatic compaction off so
  the waste each edit leaves can be seen.  Tests that want compaction call
  Compact or turn it back on. }
function NewStore(aTopology: TvgPrimitiveTopology): TvgVulkanDataStore;
begin
  Result := TvgVulkanDataStore.Create(nil);
  Result.SetupVertexAttributes([vdtPosition, vdtColor]);
  Result.SetupInstanceAttributes([idtObjID]);
  Result.Topology         := aTopology;
  Result.AutoCompactRatio := 0;
end;

{ Adds an object whose vertex I sits at (Base + I, Base, Base), so every
  vertex of every object is distinguishable. }
function AddObj(DS: TvgVulkanDataStore; aVerts: Integer; aBase: Single;
                aWithInstance: Boolean = False): Integer;
var
  I, L : Integer;
begin
  Result := DS.AddDataObject(aWithInstance);
  for I := 0 to aVerts - 1 do
  begin
    L := DS.AddObjectVertex(Result);
    DS.SetObjectVertexPosition(Result, L, aBase + I, aBase, aBase);
  end;
end;

{ Every vertex of an object built by AddObj is still where AddObj put it. }
procedure CheckObjIntact(DS: TvgVulkanDataStore; const Name: string;
                         aObj, aVerts: Integer; aBase: Single);
var
  I  : Integer;
  OK : Boolean;
  P  : TpvVector3;
begin
  OK := DS.GetObjectVertexCount(aObj) = aVerts;
  if OK then
    for I := 0 to aVerts - 1 do
    begin
      P := DS.GetObjectVertexPosition(aObj, I);
      if (P.x <> aBase + I) or (P.y <> aBase) or (P.z <> aBase) then
        OK := False;
    end;
  Check(Name, OK, True);
end;

// ---------------------------------------------------------------------------
procedure TestGrowBuriedObject;
var
  DS   : TvgVulkanDataStore;
  A, B : Integer;
  L    : Integer;
begin
  Writeln('--- growing an object that is not the last one ---');
  DS := NewStore(POINT_LIST);
  try
    A := AddObj(DS, 3, 0);
    B := AddObj(DS, 2, 100);

    CheckInt('A starts at 0', DS.GetObjectVertexStart(A), 0);
    CheckInt('B starts at 3', DS.GetObjectVertexStart(B), 3);

    // The bug this fixes: A grew in place, over B's first vertex.
    L := DS.AddObjectVertex(A);
    DS.SetObjectVertexPosition(A, L, 3, 0, 0);

    CheckInt('new vertex is A''s local 3', L, 3);
    CheckObjIntact(DS, 'B untouched by A growing', B, 2, 100);
    CheckObjIntact(DS, 'A kept its vertices and grew', A, 4, 0);
    CheckInt('A moved past B', DS.GetObjectVertexStart(A), 5);
    CheckInt('B did not move', DS.GetObjectVertexStart(B), 3);
    CheckInt('A''s old range is waste', DS.VertexWaste, 3);
    CheckInt('array holds waste + live', DS.TotalVertexCount, 3 + 2 + 4);

    // Now A is at the end, so it grows in place: no more waste.
    DS.AddObjectVertex(A);
    CheckInt('tail object grows in place', DS.GetObjectVertexStart(A), 5);
    CheckInt('no new waste from tail growth', DS.VertexWaste, 3);

    // A's bounds survived the move: they are about positions, not places.
    Check('A bounds still valid', DS.GetObjectLocalBounds(A).Valid, True);
    CheckVec('A bounds min', DS.GetObjectLocalBounds(A).Min, V(0, 0, 0));
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestGrowBuriedIndicesAndInstances;
var
  DS       : TvgVulkanDataStore;
  A, B     : Integer;
  ID1, ID2 : Cardinal;
begin
  Writeln('--- growing buried index and instance ranges ---');
  DS := NewStore(LINE_LIST);
  try
    A := AddObj(DS, 3, 0, True);
    DS.AddObjectIndex(A, 0);
    DS.AddObjectIndex(A, 1);
    DS.AddObjectInstance(A);
    DS.SetObjectInstanceObjID(A, 0, 11, 12);

    B := AddObj(DS, 2, 100, True);
    DS.AddObjectIndex(B, 0);
    DS.AddObjectIndex(B, 1);
    DS.AddObjectInstance(B);
    DS.SetObjectInstanceObjID(B, 0, 21, 22);

    // Grow A's index and instance ranges, which B now follows.
    DS.AddObjectIndex(A, 1);
    DS.AddObjectIndex(A, 2);
    DS.AddObjectInstance(A);
    DS.SetObjectInstanceObjID(A, 1, 13, 14);

    CheckInt('B index 0 intact', DS.GetObjectIndex(B, 0), 0);
    CheckInt('B index 1 intact', DS.GetObjectIndex(B, 1), 1);
    DS.GetObjectInstanceObjID(B, 0, ID1, ID2);
    Check('B object ID intact', (ID1 = 21) and (ID2 = 22), True);

    CheckInt('A has 4 indices', DS.GetObjectIndexCount(A), 4);
    CheckInt('A index 0', DS.GetObjectIndex(A, 0), 0);
    CheckInt('A index 1', DS.GetObjectIndex(A, 1), 1);
    CheckInt('A index 2', DS.GetObjectIndex(A, 2), 1);
    CheckInt('A index 3', DS.GetObjectIndex(A, 3), 2);
    DS.GetObjectInstanceObjID(A, 0, ID1, ID2);
    Check('A first object ID moved with it', (ID1 = 11) and (ID2 = 12), True);
    DS.GetObjectInstanceObjID(A, 1, ID1, ID2);
    Check('A second object ID', (ID1 = 13) and (ID2 = 14), True);

    CheckInt('index waste', DS.IndexWaste, 2);
    CheckInt('instance waste', DS.InstanceWaste, 1);
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestResetBuriedObject;
var
  DS   : TvgVulkanDataStore;
  A, B : Integer;
begin
  Writeln('--- ResetObject on an object that is not the last one ---');
  DS := NewStore(POINT_LIST);
  try
    A := AddObj(DS, 3, 0);
    B := AddObj(DS, 2, 100);

    // This used to raise.
    try
      DS.ResetObject(A);
      Check('reset a buried object does not raise', False, False);
    except
      on EVulkanDataStoreException do Check('reset a buried object does not raise', True, False);
    end;
    CheckInt('A is empty', DS.GetObjectVertexCount(A), 0);
    Check('A has no bounds', DS.GetObjectLocalBounds(A).Valid, False);
    CheckObjIntact(DS, 'B untouched by the reset', B, 2, 100);
    CheckInt('A''s old vertices are waste', DS.VertexWaste, 3);

    // Refill it, as TvgDelaunayDisplay.UpdateIsolines does.
    DS.AddObjectVertex(A);
    DS.SetObjectVertexPosition(A, 0, 7, 7, 7);
    CheckVec('A refilled', DS.GetObjectVertexPosition(A, 0), V(7, 7, 7));
    CheckObjIntact(DS, 'B untouched by the refill', B, 2, 100);

    // The tail object still gives its space straight back.
    DS.ResetObject(A);
    CheckInt('tail reset leaves no new waste', DS.VertexWaste, 3);
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestDelete;
var
  DS      : TvgVulkanDataStore;
  A, B, C : Integer;
begin
  Writeln('--- DeleteDataObject ---');
  DS := NewStore(POINT_LIST);
  try
    A := AddObj(DS, 3, 0);
    B := AddObj(DS, 2, 100);
    C := AddObj(DS, 4, 200);

    DS.DeleteDataObject(B);

    Check('B reports deleted', DS.IsObjectDeleted(B), True);
    Check('A does not', DS.IsObjectDeleted(A), False);
    CheckInt('record count keeps the tombstone', DS.ObjectCount, 3);
    CheckInt('live object count', DS.GetLiveObjectCount, 2);
    CheckInt('B has no vertices', DS.GetObjectVertexCount(B), 0);
    CheckInt('B has no vertex range', DS.GetObjectVertexStart(B), -1);
    Check('B has no bounds', DS.GetObjectWorldBounds(B).Valid, False);

    // Indices are stable: A and C are still A and C.
    CheckObjIntact(DS, 'A intact', A, 3, 0);
    CheckObjIntact(DS, 'C intact', C, 4, 200);
    CheckInt('B''s vertices are waste', DS.VertexWaste, 2);

    // A deleted object takes no more edits, and is not deleted twice.
    try
      DS.SetObjectVertexPosition(B, 0, 1, 1, 1);
      Check('write to deleted raises', False, True);
    except
      on EVulkanDataStoreException do Check('write to deleted raises', True, True);
    end;
    try
      DS.AddObjectVertex(B);
      Check('add vertex to deleted raises', False, True);
    except
      on EVulkanDataStoreException do Check('add vertex to deleted raises', True, True);
    end;
    try
      DS.ResetObject(B);
      Check('reset deleted raises', False, True);
    except
      on EVulkanDataStoreException do Check('reset deleted raises', True, True);
    end;
    try
      DS.DeleteDataObject(B);
      Check('delete twice raises', False, True);
    except
      on EVulkanDataStoreException do Check('delete twice raises', True, True);
    end;
    try
      DS.DeleteDataObject(99);
      Check('bad index raises', False, True);
    except
      on EVulkanDataStoreException do Check('bad index raises', True, True);
    end;

    // Deleting the tail object hands its space back instead.
    DS.DeleteDataObject(C);
    CheckInt('tail delete leaves no new waste', DS.VertexWaste, 2);
    CheckInt('array shrank to A + B''s hole', DS.TotalVertexCount, 5);

    // A new object gets a new index; the tombstones are never reused.
    CheckInt('next object index', AddObj(DS, 1, 300), 3);
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestWritesStayInRange;
var
  DS   : TvgVulkanDataStore;
  A, B : Integer;
begin
  Writeln('--- writes cannot reach a neighbouring object ---');
  DS := NewStore(POINT_LIST);
  try
    A := AddObj(DS, 2, 0);
    B := AddObj(DS, 2, 100);

    // Local 2 of A is B's local 0 in the shared array.  These used to write
    // straight into B.
    try
      DS.SetObjectVertexColor(A, 2, 1, 0, 0, 1);
      Check('colour past the end raises', False, True);
    except
      on EVulkanDataStoreException do Check('colour past the end raises', True, True);
    end;
    try
      DS.SetObjectVertexNormal(A, -1, 0, 0, 1);
      Check('negative local index raises', False, True);
    except
      on EVulkanDataStoreException do Check('negative local index raises', True, True);
    end;
    try
      DS.SetObjectInstanceColor(A, 0, 1, 0, 0, 1);
      Check('instance write with no instances raises', False, True);
    except
      on EVulkanDataStoreException do Check('instance write with no instances raises', True, True);
    end;
    CheckObjIntact(DS, 'B intact', B, 2, 100);
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestRemoveVertexIndexed;
var
  DS   : TvgVulkanDataStore;
  A, B : Integer;
begin
  Writeln('--- RemoveObjectVertex, indexed ---');

  // A polyline 0-1-2 as a LINE_LIST: segments (0,1) and (1,2).
  DS := NewStore(LINE_LIST);
  try
    A := AddObj(DS, 3, 0);
    DS.AddObjectIndex(A, 0);  DS.AddObjectIndex(A, 1);
    DS.AddObjectIndex(A, 1);  DS.AddObjectIndex(A, 2);
    B := AddObj(DS, 2, 100);
    DS.AddObjectIndex(B, 0);  DS.AddObjectIndex(B, 1);

    CheckInt('removes one vertex', DS.RemoveObjectVertex(A, 0), 1);
    CheckInt('segment (0,1) dropped', DS.GetObjectIndexCount(A), 2);
    CheckInt('(1,2) renumbered to 0', DS.GetObjectIndex(A, 0), 0);
    CheckInt('(1,2) renumbered to 1', DS.GetObjectIndex(A, 1), 1);
    CheckInt('A has 2 vertices', DS.GetObjectVertexCount(A), 2);
    CheckVec('A vertex 0 was vertex 1', DS.GetObjectVertexPosition(A, 0), V(1, 0, 0));
    CheckVec('A vertex 1 was vertex 2', DS.GetObjectVertexPosition(A, 1), V(2, 0, 0));
    CheckObjIntact(DS, 'B intact', B, 2, 100);
    CheckInt('B index 0 intact', DS.GetObjectIndex(B, 0), 0);
    CheckInt('B index 1 intact', DS.GetObjectIndex(B, 1), 1);

    // The bounds are rescanned, so they shrink with the geometry.
    CheckVec('A bounds shrank', DS.GetObjectLocalBounds(A).Min, V(1, 0, 0));
  finally
    DS.Free;
  end;

  // Removing the shared middle vertex drops both segments.
  DS := NewStore(LINE_LIST);
  try
    A := AddObj(DS, 3, 0);
    DS.AddObjectIndex(A, 0);  DS.AddObjectIndex(A, 1);
    DS.AddObjectIndex(A, 1);  DS.AddObjectIndex(A, 2);
    DS.RemoveObjectVertex(A, 1);
    CheckInt('middle vertex: both segments gone', DS.GetObjectIndexCount(A), 0);
    CheckInt('middle vertex: 2 vertices left', DS.GetObjectVertexCount(A), 2);
  finally
    DS.Free;
  end;

  // A quad as two triangles (0,1,2) (0,2,3): removing 3 drops one.
  DS := NewStore(TRIANGLE_LIST);
  try
    A := AddObj(DS, 4, 0);
    DS.AddObjectTriangle(A, 0, 1, 2);
    DS.AddObjectTriangle(A, 0, 2, 3);
    DS.RemoveObjectVertex(A, 3);
    CheckInt('triangle list: one triangle left', DS.GetObjectIndexCount(A), 3);
    CheckInt('triangle kept 0', DS.GetObjectIndex(A, 0), 0);
    CheckInt('triangle kept 1', DS.GetObjectIndex(A, 1), 1);
    CheckInt('triangle kept 2', DS.GetObjectIndex(A, 2), 2);
  finally
    DS.Free;
  end;

  // A strip 0-1-2: removing 1 just closes the strip up to 0-1.
  DS := NewStore(LINE_STRIP);
  try
    A := AddObj(DS, 3, 0);
    DS.AddObjectIndex(A, 0);  DS.AddObjectIndex(A, 1);  DS.AddObjectIndex(A, 2);
    DS.RemoveObjectVertex(A, 1);
    CheckInt('strip: 2 indices left', DS.GetObjectIndexCount(A), 2);
    CheckInt('strip index 0', DS.GetObjectIndex(A, 0), 0);
    CheckInt('strip index 1 (was 2)', DS.GetObjectIndex(A, 1), 1);
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestRemoveVertexNonIndexed;
var
  DS   : TvgVulkanDataStore;
  A, B : Integer;
begin
  Writeln('--- RemoveObjectVertex, non-indexed ---');

  // Two segments (0,1) (2,3) as plain vertex pairs: removing vertex 3 takes
  // its whole segment, or the pairing of every later segment would shift.
  DS := NewStore(LINE_LIST);
  try
    A := AddObj(DS, 4, 0);
    B := AddObj(DS, 2, 100);
    CheckInt('line list removes the pair', DS.RemoveObjectVertex(A, 3), 2);
    CheckObjIntact(DS, 'A keeps the other segment', A, 2, 0);
    CheckObjIntact(DS, 'B intact', B, 2, 100);
    CheckInt('buried shrink is waste', DS.VertexWaste, 2);

    CheckInt('first segment too', DS.RemoveObjectVertex(A, 0), 2);
    CheckInt('A empty', DS.GetObjectVertexCount(A), 0);
  finally
    DS.Free;
  end;

  DS := NewStore(POINT_LIST);
  try
    A := AddObj(DS, 3, 0);
    CheckInt('point list removes one', DS.RemoveObjectVertex(A, 1), 1);
    CheckVec('point 0 kept', DS.GetObjectVertexPosition(A, 0), V(0, 0, 0));
    CheckVec('point 2 moved down', DS.GetObjectVertexPosition(A, 1), V(2, 0, 0));
    try
      DS.RemoveObjectVertex(A, 2);
      Check('out of range raises', False, True);
    except
      on EVulkanDataStoreException do Check('out of range raises', True, True);
    end;
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestSetCounts;
var
  DS   : TvgVulkanDataStore;
  A, B : Integer;
begin
  Writeln('--- SetObjectVertexCount / SetObjectIndexCount ---');
  DS := NewStore(LINE_LIST);
  try
    A := AddObj(DS, 4, 0);
    B := AddObj(DS, 2, 100);

    DS.SetObjectVertexCount(A, 2);
    CheckObjIntact(DS, 'A truncated to 2', A, 2, 0);
    CheckObjIntact(DS, 'B intact after shrink', B, 2, 100);
    CheckVec('A bounds rescanned', DS.GetObjectLocalBounds(A).Max, V(1, 0, 0));

    DS.SetObjectVertexCount(A, 5);
    CheckInt('A grown to 5', DS.GetObjectVertexCount(A), 5);
    CheckVec('kept vertex survives the move', DS.GetObjectVertexPosition(A, 1), V(1, 0, 0));
    CheckVec('new vertex is zeroed', DS.GetObjectVertexPosition(A, 4), V(0, 0, 0));
    CheckObjIntact(DS, 'B intact after grow', B, 2, 100);

    // An object with no range yet gets one.
    DS.SetObjectIndexCount(B, 2);
    CheckInt('B now has 2 indices', DS.GetObjectIndexCount(B), 2);
    DS.SetObjectIndex(B, 1, 1);
    CheckInt('B index written', DS.GetObjectIndex(B, 1), 1);

    try
      DS.SetObjectVertexCount(A, -1);
      Check('negative count raises', False, True);
    except
      on EVulkanDataStoreException do Check('negative count raises', True, True);
    end;
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestCompact;
var
  DS            : TvgVulkanDataStore;
  A, B, C, D, E : Integer;
  ID1, ID2      : Cardinal;
  L             : Integer;
begin
  Writeln('--- Compact ---');
  DS := NewStore(LINE_LIST);
  try
    A := AddObj(DS, 3, 0, True);
    DS.AddObjectIndex(A, 0);  DS.AddObjectIndex(A, 2);
    DS.AddObjectInstance(A);
    DS.SetObjectInstanceObjID(A, 0, 1, 2);

    B := AddObj(DS, 2, 100);
    C := AddObj(DS, 4, 200, True);
    DS.AddObjectIndex(C, 3);  DS.AddObjectIndex(C, 1);
    DS.AddObjectInstance(C);
    DS.SetObjectInstanceObjID(C, 0, 5, 6);
    D := AddObj(DS, 1, 300);

    // Make every kind of waste: a delete, a relocation, a buried shrink.
    DS.DeleteDataObject(B);
    L := DS.AddObjectVertex(A);
    DS.SetObjectVertexPosition(A, L, 3, 0, 0);
    DS.AddObjectIndex(A, 3);
    DS.AddObjectInstance(A);
    DS.SetObjectInstanceObjID(A, 1, 3, 4);
    DS.SetObjectVertexCount(C, 3);

    Check('there is waste to reclaim', DS.VertexWaste > 0, True);

    DS.Compact;

    CheckInt('no vertex waste', DS.VertexWaste, 0);
    CheckInt('no index waste', DS.IndexWaste, 0);
    CheckInt('no instance waste', DS.InstanceWaste, 0);
    CheckInt('vertices packed', DS.TotalVertexCount, 4 + 3 + 1);
    CheckInt('indices packed', DS.TotalIndexCount, 3 + 2);
    CheckInt('instances packed', DS.TotalInstanceCount, 2 + 1);

    // Same objects, same indices, same contents.
    CheckObjIntact(DS, 'A intact', A, 4, 0);
    CheckObjIntact(DS, 'C intact', C, 3, 200);
    CheckObjIntact(DS, 'D intact', D, 1, 300);
    Check('B still deleted', DS.IsObjectDeleted(B), True);
    CheckInt('A index 2', DS.GetObjectIndex(A, 2), 3);
    CheckInt('C index 0', DS.GetObjectIndex(C, 0), 3);
    DS.GetObjectInstanceObjID(A, 1, ID1, ID2);
    Check('A object ID 2', (ID1 = 3) and (ID2 = 4), True);
    DS.GetObjectInstanceObjID(C, 0, ID1, ID2);
    Check('C object ID', (ID1 = 5) and (ID2 = 6), True);

    // Ranges are contiguous in object order.
    CheckInt('A packed first', DS.GetObjectVertexStart(A), 0);
    CheckInt('C follows A', DS.GetObjectVertexStart(C), 4);
    CheckInt('D follows C', DS.GetObjectVertexStart(D), 7);

    // And the store keeps working afterwards.
    E := AddObj(DS, 2, 400);
    CheckObjIntact(DS, 'object added after compact', E, 2, 400);
    DS.AddObjectVertex(C);
    CheckObjIntact(DS, 'D intact when C grows again', D, 1, 300);
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestAutoCompact;
var
  DS   : TvgVulkanDataStore;
  A, B : Integer;
begin
  Writeln('--- automatic compaction ---');
  DS := NewStore(POINT_LIST);
  try
    DS.AutoCompactRatio    := 0.25;
    DS.AutoCompactMinWaste := 1;

    A := AddObj(DS, 3, 0);
    B := AddObj(DS, 3, 100);
    DS.DeleteDataObject(A);             // 3 of 6 wasted: over 25%

    CheckInt('compacted on delete', DS.VertexWaste, 0);
    CheckInt('only B remains', DS.TotalVertexCount, 3);
    CheckObjIntact(DS, 'B intact', B, 3, 100);
    CheckInt('B moved down', DS.GetObjectVertexStart(B), 0);

    // Growing a buried object leaves waste too, and compacts the same way.
    A := AddObj(DS, 3, 0);
    AddObj(DS, 1, 500);
    DS.AddObjectVertex(A);              // A relocates: 3 of 8 wasted
    CheckInt('compacted on relocation', DS.VertexWaste, 0);
    CheckObjIntact(DS, 'B intact after relocation', B, 3, 100);
    CheckInt('A grew', DS.GetObjectVertexCount(A), 4);

    // Below the minimum, nothing happens.
    DS.AutoCompactMinWaste := 1024;
    A := AddObj(DS, 3, 0);
    DS.DeleteDataObject(B);
    CheckInt('small waste left alone', DS.VertexWaste, 3);
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestClearAllThenReuse;
var
  DS : TvgVulkanDataStore;
  A  : Integer;
begin
  Writeln('--- ClearAll then reuse ---');
  DS := NewStore(POINT_LIST);
  try
    AddObj(DS, 20, 0);
    DS.ClearAll(False);
    CheckInt('empty after ClearAll', DS.TotalVertexCount, 0);

    // ClearAll emptied the arrays but kept their old capacity, so this used
    // to write past the end of an empty array.
    A := AddObj(DS, 3, 50);
    CheckObjIntact(DS, 'refilled after ClearAll', A, 3, 50);
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestGPUCapacityWithoutDevice;
var
  DS : TvgVulkanDataStore;
  A  : Integer;
begin
  Writeln('--- GPU capacity with no GPU buffers ---');
  // Growing the store checks its GPU buffers after every add.  With none
  // made yet there is nothing to outgrow: the first upload sizes them.  The
  // check must be a quiet no-op then - it is what every load goes through.
  DS := NewStore(POINT_LIST);
  try
    A := AddObj(DS, 40, 0);
    Check('no buffers: never too small', DS.GPUBuffersTooSmall, False);
    DS.EnsureGPUCapacity;
    Check('no buffers made by EnsureGPUCapacity', DS.BuffersCreated, False);
    CheckObjIntact(DS, 'data untouched', A, 40, 0);
  finally
    DS.Free;
  end;
end;

// ---------------------------------------------------------------------------
begin
  try
    TestGrowBuriedObject;
    TestGrowBuriedIndicesAndInstances;
    TestResetBuriedObject;
    TestDelete;
    TestWritesStayInRange;
    TestRemoveVertexIndexed;
    TestRemoveVertexNonIndexed;
    TestSetCounts;
    TestCompact;
    TestAutoCompact;
    TestClearAllThenReuse;
    TestGPUCapacityWithoutDevice;

    if Failures = 0 then
      Writeln('ALL CHECKS PASSED')
    else
    begin
      Writeln(Format('%d CHECK(S) FAILED', [Failures]));
      ExitCode := 1;
    end;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
