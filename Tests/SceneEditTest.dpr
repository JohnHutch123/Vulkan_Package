program SceneEditTest;

{$APPTYPE CONSOLE}

{ Editing a TvgScene after it has been loaded, with no Vulkan device: adding
  and removing whole stores without Load_Begin (which clears everything),
  deleting single objects, the scene's list of live objects that picking
  checks, and the change notification an edit ends with. }

uses
  System.SysUtils,
  Vulkan,
  PasVulkan.Math,
  PasVulkan.Math.Double,
  Vulkan_Components_Lookups,
  Vulkan_Components_Camera,
  Vulkan_Components,
  Vulkan_Components_Descriptors,
  Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer;

var
  Failures : Integer = 0;

procedure Check(const Name: string; Got, Expect: Boolean);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-48s %s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-48s got %s expected %s',
      [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

procedure CheckInt(const Name: string; Got, Expect: Int64);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-48s %d', [Name, Got]))
  else
  begin
    Writeln(Format('  FAIL %-48s got %d expected %d', [Name, Got, Expect]));
    Inc(Failures);
  end;
end;

procedure CheckNum(const Name: string; Got, Expect: Double);
begin
  if Abs(Got - Expect) < 1e-6 then
    Writeln(Format('  ok   %-48s %.3f', [Name, Got]))
  else
  begin
    Writeln(Format('  FAIL %-48s got %.3f expected %.3f', [Name, Got, Expect]));
    Inc(Failures);
  end;
end;

type
  // Counts OnDataChanged and remembers what it said.
  TChangeLog = class
    Count     : Integer;
    LastStore : TvgObjectStore;
    procedure Changed(Sender: TvgScene; aDataStore: TvgObjectStore);
  end;

procedure TChangeLog.Changed(Sender: TvgScene; aDataStore: TvgObjectStore);
begin
  Inc(Count);
  LastStore := aDataStore;
end;

function NewLineStore: TvgObjectStore;
begin
  Result := TvgObjectStore.Create(nil);
  Result.SetupVertexAttributes([vdtPosition, vdtColor]);
  Result.Topology := LINE_LIST;
end;

{ One segment from (X,0,0) to (X+1,0,0). }
function AddSegment(aStore: TvgObjectStore; X: Single): TvgObject;
begin
  Result := aStore.AddObject(False);
  Result.AddVertex;
  Result.SetVertexPosition(X, 0, 0);
  Result.AddVertex;
  Result.SetVertexPosition(X + 1, 0, 0);
end;

// ---------------------------------------------------------------------------
procedure TestLiveObjects;
var
  Scene   : TvgScene;
  Store   : TvgObjectStore;
  Early   : TvgObjectStore;
  A, B, E : TvgObject;
  Dummy   : TObject;
begin
  Writeln('--- the scene''s live objects ---');
  Scene := TvgScene.Create(nil);
  Dummy := TObject.Create;
  try
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');

    Store := NewLineStore;
    Scene.AddDataStore(Store);
    A := AddSegment(Store, 0);
    B := AddSegment(Store, 10);

    // A store filled before it joins brings its objects with it.
    Early := NewLineStore;
    E := AddSegment(Early, 20);
    Check('not live before its store joins', Scene.IsLiveObject(E), False);
    Scene.AddDataStore(Early);

    Scene.Load_End;

    Check('object added while loading is live', Scene.IsLiveObject(A), True);
    Check('second object is live', Scene.IsLiveObject(B), True);
    Check('store filled early: object live', Scene.IsLiveObject(E), True);
    Check('nil is not', Scene.IsLiveObject(nil), False);
    Check('some other object is not', Scene.IsLiveObject(Dummy), False);
  finally
    Scene.Free;
    Dummy.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestRemoveObject;
var
  Scene     : TvgScene;
  Store     : TvgObjectStore;
  Other     : TvgObjectStore;
  A, B, C   : TvgObject;
  X         : TvgObject;
  AIdx      : Integer;
  AAddr     : Pointer;
  Log       : TChangeLog;
  BMin,BMax : TpvVector3D;
begin
  Writeln('--- TvgObjectStore.RemoveObject ---');
  Scene := TvgScene.Create(nil);
  Log   := TChangeLog.Create;
  try
    Scene.OnDataChanged := Log.Changed;
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    Store := NewLineStore;
    Scene.AddDataStore(Store);
    A := AddSegment(Store, 100);   // the far one: removing it shrinks the bounds
    B := AddSegment(Store, 0);
    C := AddSegment(Store, 2);
    Other := NewLineStore;
    Scene.AddDataStore(Other);
    X := AddSegment(Other, 5);
    Scene.Load_End;

    Check('bounds reach the far segment',
      Scene.GetDataBounds(BMin, BMax) and (BMax.x > 100), True);

    AIdx  := A.ObjIndex;
    AAddr := A;
    Log.Count := 0;

    Store.RemoveObject(A);

    Check('removed object is no longer live', Scene.IsLiveObject(AAddr), False);
    Check('its data is deleted', Store.IsObjectDeleted(AIdx), True);
    CheckInt('store holds two objects', Store.ObjectCount, 2);
    Check('neighbour still live', Scene.IsLiveObject(B), True);
    CheckInt('neighbour kept its index', B.ObjIndex, 1);
    CheckNum('neighbour vertex 0 intact', Store.GetObjectVertexPosition(B.ObjIndex, 0).x, 0);
    CheckNum('last object vertex 1 intact', Store.GetObjectVertexPosition(C.ObjIndex, 1).x, 3);
    CheckInt('OnDataChanged fired once', Log.Count, 1);
    Check('...for this store', Log.LastStore = Store, True);

    Check('bounds no longer reach it',
      Scene.GetDataBounds(BMin, BMax) and (BMax.x < 100), True);
    CheckNum('bounds now end at the other store', BMax.x, 6);

    // Another store's object is not this store's to remove.
    Log.Count := 0;
    Store.RemoveObject(X);
    Check('foreign object left alone', Scene.IsLiveObject(X), True);
    CheckInt('foreign object still in its store', Other.ObjectCount, 1);
    CheckInt('no notification for a no-op', Log.Count, 0);
    Store.RemoveObject(nil);

    // Still usable: new objects go on after the tombstone.
    A := AddSegment(Store, 50);
    Check('object added after a removal is live', Scene.IsLiveObject(A), True);
    CheckInt('it gets a new index', A.ObjIndex, 3);
  finally
    Scene.Free;
    Log.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestAddStoreLive;
var
  Scene     : TvgScene;
  First     : TvgObjectStore;
  Live      : TvgObjectStore;
  Obj       : TvgObject;
  Log       : TChangeLog;
  BMin,BMax : TpvVector3D;
begin
  Writeln('--- AddDataStoreLive ---');
  Scene := TvgScene.Create(nil);
  Log   := TChangeLog.Create;
  try
    Scene.OnDataChanged := Log.Changed;
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    First := NewLineStore;
    Scene.AddDataStore(First);
    AddSegment(First, 0);
    Scene.Load_End;

    // The old way refuses a loaded scene...
    Live := NewLineStore;
    Check('AddDataStore refuses a loaded scene', Scene.AddDataStore(Live), False);

    // ...and Load_Begin would clear what is there.  AddDataStoreLive adds.
    Obj := AddSegment(Live, 40);
    Log.Count := 0;
    Check('AddDataStoreLive accepts it', Scene.AddDataStoreLive(Live), True);
    CheckInt('scene holds both stores', Scene.GetObjectStoreCount, 2);
    Check('earlier store untouched', Scene.SceneData.IndexOf(First) = 0, True);
    Check('scene still READY', Scene.SceneState = SS_READY, True);
    Check('its object is live', Scene.IsLiveObject(Obj), True);
    Check('bounds include it', Scene.GetDataBounds(BMin, BMax) and (BMax.x = 41), True);
    CheckInt('OnDataChanged fired', Log.Count, 1);
    Check('...for the new store', Log.LastStore = Live, True);

    // Objects added to it afterwards register as usual.
    Obj := AddSegment(Live, 60);
    Check('object added to it later is live', Scene.IsLiveObject(Obj), True);

    // Adding it twice changes nothing.
    Check('adding it again', Scene.AddDataStoreLive(Live), True);
    CheckInt('still two stores', Scene.GetObjectStoreCount, 2);

    Check('nil refused', Scene.AddDataStoreLive(nil), False);

    // While loading it is plain AddDataStore; Load_End does the rest.
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    Live := NewLineStore;
    Check('while loading: accepted', Scene.AddDataStoreLive(Live), True);
    Scene.Load_End;
    CheckInt('while loading: added', Scene.GetObjectStoreCount, 1);

    // Any other state is refused.
    Scene.SceneState := SS_STORING;
    Live := NewLineStore;
    Check('while storing: refused', Scene.AddDataStoreLive(Live), False);
    Live.Free;
    Scene.SceneState := SS_READY;
  finally
    Scene.Free;
    Log.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestRemoveStore;
var
  Scene      : TvgScene;
  Keep, Drop : TvgObjectStore;
  K, D1, D2  : TvgObject;
  P1, P2     : Pointer;
  Log        : TChangeLog;
  BMin,BMax  : TpvVector3D;
begin
  Writeln('--- RemoveDataStore ---');
  Scene := TvgScene.Create(nil);
  Log   := TChangeLog.Create;
  try
    Scene.OnDataChanged := Log.Changed;
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    Keep := NewLineStore;
    Scene.AddDataStore(Keep);
    K := AddSegment(Keep, 0);
    Drop := NewLineStore;
    Scene.AddDataStore(Drop);
    D1 := AddSegment(Drop, 100);
    D2 := AddSegment(Drop, 200);
    Scene.Load_End;

    P1 := D1;
    P2 := D2;
    Log.Count := 0;

    Scene.RemoveDataStore(Drop);   // frees Drop, D1 and D2

    CheckInt('one store left', Scene.GetObjectStoreCount, 1);
    Check('it is the one kept', Scene.SceneData.Items[0] = Keep, True);
    Check('first removed object not live', Scene.IsLiveObject(P1), False);
    Check('second removed object not live', Scene.IsLiveObject(P2), False);
    Check('kept object still live', Scene.IsLiveObject(K), True);
    Check('bounds are the kept store''s',
      Scene.GetDataBounds(BMin, BMax) and (BMax.x = 1), True);
    CheckInt('OnDataChanged fired', Log.Count, 1);
    Check('...for the scene as a whole', Log.LastStore = nil, True);

    // A store the scene does not hold is ignored.
    Drop := NewLineStore;
    Log.Count := 0;
    Scene.RemoveDataStore(Drop);
    CheckInt('unknown store: nothing removed', Scene.GetObjectStoreCount, 1);
    CheckInt('unknown store: no notification', Log.Count, 0);
    Drop.Free;
    Scene.RemoveDataStore(nil);
  finally
    Scene.Free;
    Log.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestNotify;
var
  Scene : TvgScene;
  Store : TvgObjectStore;
  Log   : TChangeLog;
begin
  Writeln('--- NotifyDataChanged ---');
  Scene := TvgScene.Create(nil);
  Log   := TChangeLog.Create;
  try
    Scene.OnDataChanged := Log.Changed;
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    Store := NewLineStore;
    Scene.AddDataStore(Store);
    Scene.Load_End;

    Scene.NotifyDataChanged(Store);
    CheckInt('fires with no renderer attached', Log.Count, 1);
    Check('passes the store on', Log.LastStore = Store, True);
    Scene.NotifyDataChanged;
    Check('nil for the whole scene', Log.LastStore = nil, True);

    // With no renderer there is nothing to build; it must just do nothing.
    Scene.ConnectStoreLive(Store);
    Scene.ConnectStoreLive(nil);
    Check('ConnectStoreLive with no renderer is harmless', True, True);
  finally
    Scene.Free;
    Log.Free;
  end;
end;

// ---------------------------------------------------------------------------
function Near(const A, B: TpvVector3D; aTol: Double): Boolean;
begin
  Result := (Abs(A.x - B.x) <= aTol) and (Abs(A.y - B.y) <= aTol) and (Abs(A.z - B.z) <= aTol);
end;

function V3(X, Y, Z: Double): TpvVector3D;
begin
  Result := TpvVector3D.Create(X, Y, Z);
end;

procedure TestEditLayers;
var
  Scene      : TvgScene;
  L, L2, P, T : TvgObjectStore;
begin
  Writeln('--- edit layers ---');
  Scene := TvgScene.Create(nil);
  try
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    Scene.Load_End;

    Scene.EditLineWidth := 3;
    L := Scene.GetEditStore(elkLines);
    Check('lines layer made', Assigned(L), True);
    Check('same layer the second time', Scene.GetEditStore(elkLines) = L, True);
    Check('it is in the scene', Scene.SceneData.IndexOf(L) >= 0, True);
    Check('LINE_LIST', L.Topology = LINE_LIST, True);
    Check('indexed', L.GetIndexType = itUInt32, True);
    Check('coloured per vertex', L.IsVertexTypeSet(vdtColor), True);
    Check('pickable', L.IsInstanceTypeSet(idtObjID), True);
    Check('shader named EditLines', L.BaseVertName = 'EditLines', True);
    CheckNum('takes EditLineWidth', L.LineWidth, 3);
    Check('takes EditColor', (L.DefaultColor.x = Scene.EditColor.x) and
                             (L.DefaultColor.z = Scene.EditColor.z), True);

    P := Scene.GetEditStore(elkPoints);
    Check('points layer is POINT_LIST', P.Topology = POINT_LIST, True);
    Check('points layer not indexed', P.GetIndexType = itNONE, True);
    T := Scene.GetEditStore(elkTriangles);
    Check('triangles layer is TRIANGLE_LIST', T.Topology = TRIANGLE_LIST, True);
    CheckInt('three layers, three stores', Scene.GetObjectStoreCount, 3);

    // Removing a layer, or reloading, makes the next call build a new one.
    Scene.RemoveDataStore(L);
    L2 := Scene.GetEditStore(elkLines);
    Check('after RemoveDataStore: a layer again', Assigned(L2) and (Scene.SceneData.IndexOf(L2) >= 0), True);
    CheckInt('after RemoveDataStore: three stores', Scene.GetObjectStoreCount, 3);

    Scene.EditShaderPrefix := 'Mine';
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    Scene.Load_End;
    CheckInt('reload cleared them', Scene.GetObjectStoreCount, 0);
    L := Scene.GetEditStore(elkLines);
    Check('after reload: a layer again', Assigned(L) and (Scene.GetObjectStoreCount = 1), True);
    Check('new layer takes the new prefix', L.BaseVertName = 'MineLines', True);

    Scene.SceneState := SS_STORING;
    Check('no layer while storing', Scene.GetEditStore(elkPoints) = nil, True);
    Scene.SceneState := SS_READY;
  finally
    Scene.Free;
  end;
end;

procedure TestShapes;
const
  ORIGIN_X = 500000.0;  ORIGIN_Y = 6000000.0;  ORIGIN_Z = 100.0;
var
  Scene     : TvgScene;
  Lines     : TvgObjectStore;
  Points    : TvgObjectStore;
  Plain     : TvgObjectStore;
  Strip     : TvgObjectStore;
  Obj       : TvgObject;
  ID1, ID2  : Cardinal;
  Log       : TChangeLog;
  A, B      : TpvVector3D;
  BMin,BMax : TpvVector3D;
  Before    : Integer;
  Raised    : Boolean;
begin
  Writeln('--- AddLine / AddPolyline / AddPoint ---');
  Scene := TvgScene.Create(nil);
  Log   := TChangeLog.Create;
  try
    Scene.OnDataChanged := Log.Changed;
    // Survey coordinates: the shapes go through WorldOrigin like any data.
    Scene.WorldOrigin := V3(ORIGIN_X, ORIGIN_Y, ORIGIN_Z);
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    Plain := NewLineStore;
    Plain.SetIndexType(itNONE);            // stores default to itUInt32
    Scene.AddDataStore(Plain);
    Strip := NewLineStore;
    Strip.Topology := LINE_STRIP;
    Scene.AddDataStore(Strip);
    Scene.Load_End;

    Lines  := Scene.GetEditStore(elkLines);
    Points := Scene.GetEditStore(elkPoints);

    A := V3(ORIGIN_X + 1.234, ORIGIN_Y + 2.5,   ORIGIN_Z + 0.001);
    B := V3(ORIGIN_X + 7.891, ORIGIN_Y - 3.125, ORIGIN_Z + 2.0);
    Log.Count := 0;
    Obj := Lines.AddLine(A, B);

    CheckInt('line: two vertices', Obj.VertexCount, 2);
    CheckInt('line: one segment', Lines.GetObjectIndexCount(Obj.ObjIndex), 2);
    Check('line: start to the millimetre', Near(Obj.GetVertexWorldPosition(0), A, 0.0005), True);
    Check('line: end to the millimetre', Near(Obj.GetVertexWorldPosition(1), B, 0.0005), True);
    Check('line: live, so pickable', Scene.IsLiveObject(Obj), True);
    Lines.GetObjectInstanceObjID(Obj.ObjIndex, 0, ID1, ID2);
    Check('line: its object ID is its address',
      ((UInt64(ID1) shl 32) or UInt64(ID2)) = UInt64(NativeUInt(Obj)), True);
    Check('line: notified', Log.Count >= 1, True);
    Check('bounds include it',
      Scene.GetDataBounds(BMin, BMax) and (Abs(BMax.x - B.x) < 0.001), True);

    Obj := Lines.AddPolyline([V3(ORIGIN_X, ORIGIN_Y, ORIGIN_Z), V3(ORIGIN_X + 1, ORIGIN_Y, ORIGIN_Z),
                              V3(ORIGIN_X + 1, ORIGIN_Y + 1, ORIGIN_Z), V3(ORIGIN_X, ORIGIN_Y + 1, ORIGIN_Z)], False);
    CheckInt('open polyline: 4 shared vertices', Obj.VertexCount, 4);
    CheckInt('open polyline: 3 segments', Lines.GetObjectIndexCount(Obj.ObjIndex), 6);
    CheckInt('open polyline: 2nd segment starts at 1', Lines.GetObjectIndex(Obj.ObjIndex, 2), 1);
    Obj := Lines.AddPolyline([V3(ORIGIN_X, ORIGIN_Y, ORIGIN_Z), V3(ORIGIN_X + 1, ORIGIN_Y, ORIGIN_Z),
                              V3(ORIGIN_X + 1, ORIGIN_Y + 1, ORIGIN_Z)], True);
    CheckInt('closed triangle: 3 segments', Lines.GetObjectIndexCount(Obj.ObjIndex), 6);
    CheckInt('closing segment ends at 0', Lines.GetObjectIndex(Obj.ObjIndex, 5), 0);

    Obj := Plain.AddPolyline([V3(ORIGIN_X, ORIGIN_Y, ORIGIN_Z), V3(ORIGIN_X + 1, ORIGIN_Y, ORIGIN_Z),
                              V3(ORIGIN_X + 2, ORIGIN_Y, ORIGIN_Z)], False);
    CheckInt('unindexed LINE_LIST repeats the inner vertex', Obj.VertexCount, 4);
    Check('...so vertex 2 is vertex 1 again',
      Near(Obj.GetVertexWorldPosition(2), Obj.GetVertexWorldPosition(1), 0), True);

    Obj := Strip.AddPolyline([V3(ORIGIN_X, ORIGIN_Y, ORIGIN_Z), V3(ORIGIN_X + 1, ORIGIN_Y, ORIGIN_Z),
                              V3(ORIGIN_X + 1, ORIGIN_Y + 1, ORIGIN_Z)], True);
    CheckInt('closed LINE_STRIP returns to the start', Obj.VertexCount, 4);
    Check('...last vertex is the first',
      Near(Obj.GetVertexWorldPosition(3), Obj.GetVertexWorldPosition(0), 0), True);

    Obj := Points.AddPoint(A);
    CheckInt('point: one vertex', Obj.VertexCount, 1);
    CheckInt('point: no indices', Points.GetObjectIndexCount(Obj.ObjIndex), 0);

    // The wrong shape for a store raises, and leaves nothing behind.
    Before := Points.ObjectCount;
    Raised := False;
    try Points.AddLine(A, B); except on EvgSceneEditException do Raised := True; end;
    Check('line into a points layer raises', Raised, True);
    CheckInt('...and adds nothing', Points.ObjectCount, Before);

    Before := Lines.ObjectCount;
    Raised := False;
    try Lines.AddPoint(A); except on EvgSceneEditException do Raised := True; end;
    Check('point into a lines layer raises', Raised, True);
    Raised := False;
    try Lines.AddPolyline([A], False); except on EvgSceneEditException do Raised := True; end;
    Check('one-point polyline raises', Raised, True);
    Raised := False;
    try Lines.AddPolyline([A, B], True); except on EvgSceneEditException do Raised := True; end;
    Check('closed two-point polyline raises', Raised, True);
    CheckInt('...none of them added anything', Lines.ObjectCount, Before);

    Raised := False;
    try Scene.GetEditStore(elkTriangles).AddLine(A, B); except on EvgSceneEditException do Raised := True; end;
    Check('line into a triangles layer raises', Raised, True);
  finally
    Scene.Free;
    Log.Free;
  end;
end;

procedure TestObjectEdits;
var
  Scene     : TvgScene;
  Lines     : TvgObjectStore;
  Obj       : TvgObject;
  Poly      : TvgObject;
  Addr      : Pointer;
  Log       : TChangeLog;
  D         : Double;
  Box       : TvgAABB;
begin
  Writeln('--- TvgObject edits ---');
  Scene := TvgScene.Create(nil);
  Log   := TChangeLog.Create;
  try
    Scene.OnDataChanged := Log.Changed;
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    Scene.Load_End;
    Lines := Scene.GetEditStore(elkLines);
    Obj   := Lines.AddLine(V3(0, 0, 0), V3(10, 0, 0));

    Log.Count := 0;
    Check('MoveVertex', Obj.MoveVertex(1, V3(10, 5, 0)), True);
    Check('moved', Near(Obj.GetVertexWorldPosition(1), V3(10, 5, 0), 1e-6), True);
    Check('bounds grew to it', Lines.GetObjectLocalBounds(Obj.ObjIndex).Max.y = 5, True);
    Obj.MoveVertex(1, V3(10, 0, 0));
    // Rescanned, not accumulated: moving back shrinks the box again.
    Check('bounds shrank back', Lines.GetObjectLocalBounds(Obj.ObjIndex).Max.y = 0, True);
    CheckInt('each edit notified', Log.Count, 2);

    Check('Translate', Obj.Translate(V3(1, 2, 3)), True);
    Check('vertex 0 translated', Near(Obj.GetVertexWorldPosition(0), V3(1, 2, 3), 1e-6), True);
    Check('vertex 1 translated', Near(Obj.GetVertexWorldPosition(1), V3(11, 2, 3), 1e-6), True);
    Box := Lines.GetObjectLocalBounds(Obj.ObjIndex);
    Check('bounds moved with it', (Box.Min.x = 1) and (Box.Max.x = 11) and (Box.Min.z = 3), True);
    Check('Centroid', Near(Obj.Centroid, V3(6, 2, 3), 1e-6), True);
    CheckInt('NearestVertex', Obj.NearestVertex(V3(10, 2, 3), D), 1);
    CheckNum('...at distance 1', D, 1);

    Check('out-of-range vertex refused', Obj.MoveVertex(5, V3(0, 0, 0)), False);

    // Locked and frozen objects take no edits.
    Obj.LockON := True;
    Check('locked: MoveVertex refused', Obj.MoveVertex(0, V3(99, 0, 0)), False);
    Check('locked: unchanged', Near(Obj.GetVertexWorldPosition(0), V3(1, 2, 3), 1e-6), True);
    Obj.LockON := False;
    Obj.FrozenON := True;
    Check('frozen: Translate refused', Obj.Translate(V3(1, 0, 0)), False);
    Check('frozen: CanEdit false', Obj.CanEdit, False);
    Obj.FrozenON := False;
    Check('editable again', Obj.CanEdit, True);

    // Deleting the end vertex of a 3-point polyline leaves its first segment.
    Poly := Lines.AddPolyline([V3(0, 0, 0), V3(1, 0, 0), V3(2, 0, 0)], False);
    Check('DeleteVertex', Poly.DeleteVertex(2), True);
    CheckInt('two vertices left', Poly.VertexCount, 2);
    CheckInt('one segment left', Lines.GetObjectIndexCount(Poly.ObjIndex), 2);

    // Delete frees the object.
    Addr := Obj;
    Obj.Delete;
    Check('deleted object not live', Scene.IsLiveObject(Addr), False);
    Check('the other is', Scene.IsLiveObject(Poly), True);
  finally
    Scene.Free;
    Log.Free;
  end;
end;

// ---------------------------------------------------------------------------
procedure TestTeardown;
var
  Scene : TvgScene;
  Store : TvgObjectStore;
  First : TvgObject;
  I     : Integer;
begin
  Writeln('--- freeing a scene full of objects ---');
  // Every object leaves the live list as it is freed, so the list must
  // outlive the stores.
  Scene := TvgScene.Create(nil);
  if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
  Store := NewLineStore;
  Scene.AddDataStore(Store);
  First := AddSegment(Store, 0);
  for I := 1 to 9 do AddSegment(Store, I * 2);
  Scene.Load_End;
  Store.RemoveObject(First);   // a tombstone in the store being freed
  Scene.Free;
  Check('scene freed', True, True);

  // Freed while still loading: the stores are freed by the scene's own
  // destructor rather than ClearScene.
  Scene := TvgScene.Create(nil);
  if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
  Store := NewLineStore;
  Scene.AddDataStore(Store);
  AddSegment(Store, 0);
  Scene.Free;
  Check('scene freed mid-load', True, True);
end;

// ---------------------------------------------------------------------------
{ TvgObject.VisibleON reaches the store: False hides the object from the
  draw (TvgVulkanDataStore.SetObjectHidden) as well as from picking and the
  data bounds, keeps its data, and notifies once per change so the frames
  are recorded again. }
procedure TestVisibleON;
var
  Scene     : TvgScene;
  Store     : TvgObjectStore;
  A, B      : TvgObject;
  Log       : TChangeLog;
  BMin,BMax : TpvVector3D;
begin
  Writeln('--- TvgObject.VisibleON ---');
  Scene := TvgScene.Create(nil);
  Log   := TChangeLog.Create;
  try
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    Store := NewLineStore;
    Scene.AddDataStore(Store);
    A := AddSegment(Store, 0);
    B := AddSegment(Store, 10);
    Scene.Load_End;
    Scene.OnDataChanged := Log.Changed;

    Check('new object is visible', A.VisibleON, True);
    Check('new object is drawn', Store.ShouldSkipObject(A.ObjIndex), False);

    A.VisibleON := False;
    Check('flag cleared', A.VisibleON, False);
    Check('store hides it', Store.IsObjectHidden(A.ObjIndex), True);
    Check('draw skips it', Store.ShouldSkipObject(A.ObjIndex), True);
    CheckInt('its data is kept', A.VertexCount, 2);
    CheckInt('one notification', Log.Count, 1);
    Check('naming its store', Log.LastStore = Store, True);
    Check('B still drawn', Store.ShouldSkipObject(B.ObjIndex), False);
    Scene.GetDataBounds(BMin, BMax);
    CheckNum('bounds leave it out', BMin.x, 10);

    A.VisibleON := False;
    CheckInt('same value: no notification', Log.Count, 1);

    // Edits still work on a hidden object, and leave it hidden.
    Check('translate while hidden', A.Translate(TpvVector3D.Create(0, 5, 0)), True);
    CheckNum('moved', A.GetVertexWorldPosition(0).y, 5);
    Check('still hidden after the edit', Store.IsObjectHidden(A.ObjIndex), True);

    A.VisibleON := True;
    Check('shown again', Store.IsObjectHidden(A.ObjIndex), False);
    Check('drawn again', Store.ShouldSkipObject(A.ObjIndex), False);
    Scene.GetDataBounds(BMin, BMax);
    CheckNum('bounds take it back', BMin.x, 0);

    // One repaint for a group of changes.
    Log.Count := 0;
    Scene.BeginUpdate;
    A.VisibleON := False;
    B.VisibleON := False;
    CheckInt('nothing until EndUpdate', Log.Count, 0);
    Scene.EndUpdate;
    CheckInt('one notification for both', Log.Count, 1);

    // A hidden object is removed like any other.
    Store.RemoveObject(A);
    Check('hidden object removed', Scene.IsLiveObject(A), False);
    Check('B still hidden', Store.IsObjectHidden(B.ObjIndex), True);
  finally
    Scene.Free;
    Log.Free;
  end;
end;

// ---------------------------------------------------------------------------
{ TvgObject.SetColorOverride reaches the store and notifies once per change;
  TvgObjectStore gives its pipelines the push constant VulkanDraw pushes it
  through - vertex stage, after the renderer's, with that offset in its
  GLSL.  The pipelines are built by hand: no device. }
procedure TestColorOverride;
var
  Scene  : TvgScene;
  Store  : TvgObjectStore;
  A      : TvgObject;
  Log    : TChangeLog;
  C      : TpvVector4;
  GP     : TvgGraphicPipeline;
  PCI    : TvgPushConstantItem;
  Off    : TVkUInt32;
  Stages : TVkShaderStageFlags;
  I, N   : Integer;
begin
  Writeln('--- TvgObject.SetColorOverride ---');
  Scene := TvgScene.Create(nil);
  Log   := TChangeLog.Create;
  try
    if not Scene.Load_Begin then raise Exception.Create('Load_Begin refused');
    Store := NewLineStore;
    Scene.AddDataStore(Store);
    A := AddSegment(Store, 0);
    Scene.Load_End;
    Scene.OnDataChanged := Log.Changed;

    Check('no override to start', A.GetColorOverride(C), False);
    A.SetColorOverride(TpvVector4.Create(0, 0, 1, 1));
    Check('override set', A.GetColorOverride(C), True);
    Check('...blue', (C.z = 1) and (C.x = 0) and (C.w = 1), True);
    CheckInt('in the store', Store.GetObjectColorOverridePacked(A.ObjIndex), $FFFF0000);
    CheckInt('one notification', Log.Count, 1);
    A.SetColorOverride(TpvVector4.Create(0, 0, 1, 1));
    CheckInt('same colour: no notification', Log.Count, 1);

    A.LockON := True;
    A.SetColorOverride(TpvVector4.Create(1, 1, 0, 1));
    CheckInt('not an edit: works on a locked object', Store.GetObjectColorOverridePacked(A.ObjIndex), $FF00FFFF);
    A.LockON := False;

    A.ClearColorOverride;
    Check('cleared', A.GetColorOverride(C), False);
    CheckInt('two more notifications', Log.Count, 3);
  finally
    Scene.Free;
    Log.Free;
  end;

  // The pipeline side.
  Store := NewLineStore;
  GP    := TvgGraphicPipeline.Create(nil);
  try
    Check('ColorOverrideON by default', Store.ColorOverrideON, True);
    Check('a bare pipeline has none',
      TvgVulkanDataStore.FindObjectColorPushConstant(GP, Off, Stages), False);

    // As the renderer's storage-buffer picking adds its screen size first.
    PCI := GP.PushConstantCol.Add;
    PCI.Name             := 'inScreenSize';
    PCI.PushConstantName := TvgPushConstant_2UI.GetPropertyName;
    PCI.PushConstant.ShaderFlags := [SS_FRAGMENT_BIT];

    Store.UpdateGraphicPipeline(GP);
    Check('UpdateGraphicPipeline adds it',
      TvgVulkanDataStore.FindObjectColorPushConstant(GP, Off, Stages), True);
    CheckInt('after the screen size: offset 8', Off, 8);
    Check('vertex stage only', Stages = TVkShaderStageFlags(VK_SHADER_STAGE_VERTEX_BIT), True);
    PCI := GP.PushConstantCol[GP.PushConstantCol.Count - 1];
    Check('it comes last', PCI.PushConstant is TvgPushConstant_ObjectColor, True);
    Check('its GLSL declares that offset',
      Pos('layout(offset = 8) uint value', PCI.PushConstant.GetGLSLDeclaration('pc')) > 0, True);
    CheckInt('4 bytes', PCI.PushConstant.DataStride, 4);

    Store.UpdateGraphicPipeline(GP);
    N := 0;
    for I := 0 to GP.PushConstantCol.Count - 1 do
      if GP.PushConstantCol[I].PushConstant is TvgPushConstant_ObjectColor then Inc(N);
    CheckInt('updated again: still one', N, 1);
  finally
    GP.Free;
    Store.Free;
  end;

  Store := NewLineStore;
  GP    := TvgGraphicPipeline.Create(nil);
  try
    Store.UpdateGraphicPipeline(GP);
    TvgVulkanDataStore.FindObjectColorPushConstant(GP, Off, Stages);
    CheckInt('alone: offset 0', Off, 0);
  finally
    GP.Free;
    Store.Free;
  end;

  Store := NewLineStore;
  GP    := TvgGraphicPipeline.Create(nil);
  try
    Store.ColorOverrideON := False;
    Store.UpdateGraphicPipeline(GP);
    Check('ColorOverrideON False: none',
      TvgVulkanDataStore.FindObjectColorPushConstant(GP, Off, Stages), False);
  finally
    GP.Free;
    Store.Free;
  end;
end;

begin
  try
    TestLiveObjects;
    TestRemoveObject;
    TestAddStoreLive;
    TestRemoveStore;
    TestNotify;
    TestEditLayers;
    TestShapes;
    TestObjectEdits;
    TestVisibleON;
    TestColorOverride;
    TestTeardown;

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
