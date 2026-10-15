unit Vulkan_LOD;

{******************************************************************************
 *  Level of detail: one thing drawn as one of several versions, finer near   *
 *  the eye and coarser away from it - or as nothing beyond some distance.    *
 *                                                                            *
 *  A TvgLodGroup is the thing: a centre, a metric, and N levels, each a list *
 *  of objects from any number of stores (an OBJ's one per material, a glTF's *
 *  per mesh).  Apply writes each object's band (TvgLodBand, Vulkan_         *
 *  Components_DataStore): every level of the group shares the centre and    *
 *  the thresholds, so the parts of a level switch together, at exactly one  *
 *  distance.  The draw loop tests the bands per renderer, with the view the *
 *  scene publishes beside the cull volume, so two windows on one scene each *
 *  pick their own level; TvgBaseRenderEngine.LodBias scales the distances.  *
 *                                                                            *
 *  Two metrics:                                                               *
 *    lmDistance   - level i is drawn while Thresholds[i-1] <= distance <     *
 *                   Thresholds[i]: thresholds ascending, metres.             *
 *    lmScreenSize - level i is drawn while Thresholds[i] <= size <           *
 *                   Thresholds[i-1]: thresholds DESCENDING, pixels across    *
 *                   the group's sphere of Radius.  Works for orthographic    *
 *                   cameras, where distance means nothing.                   *
 *  N levels take N-1 thresholds.  A level may be empty: nothing is drawn     *
 *  there - "gone beyond 500 m".                                              *
 *                                                                            *
 *  Anchor: a group can follow an object.  Its centre, radius and distance   *
 *  thresholds are then in that object's own frame, and AnchorMoved - called *
 *  by whatever moves the object (PRO's Vulkan_SceneHierarchy bakes) - puts  *
 *  them in the world from the object's world transform, scale and all.      *
 *                                                                            *
 *  The groups of a scene are vgLodGroups(Scene): a TvgSceneExtension, owned *
 *  by the scene, cleared with it, moved with its stores by                  *
 *  vgAppendSceneFile, and told when an object goes, which then leaves its   *
 *  group.                                                                    *
 *                                                                            *
 *  Every object of a level other than 0 is a proxy (vgIsLodProxy): another  *
 *  version of something level 0 already has.  An exporter that cannot      *
 *  write levels skips proxies, so a file does not get every version.        *
 *                                                                            *
 *  An instanced object switches as a whole: all its copies by the group's   *
 *  one centre.  Choosing a level per copy needs a GPU pass (not here).      *
 *                                                                            *
 *  Main thread, like every scene edit.                                       *
 ******************************************************************************}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  PasVulkan.Math, PasVulkan.Math.Double,
  Vulkan_Components, Vulkan_Components_Camera,
  Vulkan_Components_DataStore, Vulkan_Components_Scene_Renderer;

type
  EvgLodError = class(Exception);

  TvgLodGroups = class;

  TvgLodGroup = class
  private
    fGroups     : TvgLodGroups;
    fName       : String;
    fMetric     : TvgLodMetric;
    fCentre     : TpvVector3D;        // world, or the anchor's frame
    fRadius     : Double;             // the same
    fThresholds : TArray<Double>;     // the same, for lmDistance
    fLevels     : TObjectList<TList<TvgObject>>;
    fAnchor     : TvgObject;
    fAnchorWorld: TpvMatrix4x4D;      // the anchor's frame -> world
    fApplying   : Boolean;
    function  GetLevelCount: Integer;
    function  GetLevel(aIndex: Integer): TArray<TvgObject>;
    function  GetThresholdCount: Integer;
    function  GetThreshold(aIndex: Integer): Double;
    function  Scale: Double;
    procedure CheckLevel(aLevel: Integer);
    procedure SetMetric(const Value: TvgLodMetric);
  public
    constructor Create;
    destructor  Destroy; override;

    { Adds an empty level after the last and returns its index. }
    function  AddLevel: Integer;
    { Puts aObject on aLevel (taking it off any other level of any group of
      the scene).  Its band is written by the next Apply. }
    procedure AddObject(aLevel: Integer; aObject: TvgObject);
    { Takes aObject off its level and clears its band.  Nothing for one
      not in this group. }
    procedure RemoveObject(aObject: TvgObject);
    { The level aObject is on, -1 for none. }
    function  LevelOf(aObject: TvgObject): Integer;

    { The N-1 thresholds of N levels - see the unit note for their order.
      Raises when they are out of order. }
    procedure SetThresholds(const aValues: array of Double);

    { Where the group is, in world coordinates (double) - or, anchored, in
      the anchor's frame. }
    procedure SetCentre(const aCentre: TpvVector3D; aRadius: Double = 0);

    { Follow aObject: from now Centre, Radius and the distance thresholds
      are in its frame, placed by aWorld (its frame -> world, row vectors
      as TvgObjectNode.World).  nil: back to world values, as they are
      placed now. }
    procedure SetAnchor(aObject: TvgObject; const aWorld: TpvMatrix4x4D);
    { The anchor has moved to aWorld: places the group there and Applies. }
    procedure AnchorMoved(const aWorld: TpvMatrix4x4D);

    { Writes every object's band from the levels, thresholds and centre.
      Objects of the scene's other groups are untouched. }
    procedure Apply;
    { Clears the band of every object of the group - all levels drawn. }
    procedure Unapply;

    { The centre in world coordinates, wherever the anchor is. }
    function  WorldCentre: TpvVector3D;
    { The threshold aIndex as the bands use it: scaled by the anchor for
      lmDistance. }
    function  WorldThreshold(aIndex: Integer): Double;

    { The level drawn seen from aView (a renderer's GetLodView), -1 when
      none is (an empty level, or nothing in range).  The draw loop's own
      test, on level 0's band - for UI and tools. }
    function  LevelFor(const aView: TvgLodView): Integer;
    function  LevelForRenderer(aRenderer: TvgBaseRenderEngine): Integer;

    property Groups     : TvgLodGroups read fGroups;
    property Name       : String read fName write fName;
    property Metric     : TvgLodMetric read fMetric write SetMetric;
    property Centre     : TpvVector3D read fCentre;
    property Radius     : Double read fRadius;
    property Anchor     : TvgObject read fAnchor;
    property LevelCount : Integer read GetLevelCount;
    property Levels[aIndex: Integer]: TArray<TvgObject> read GetLevel;
    property ThresholdCount : Integer read GetThresholdCount;
    property Thresholds[aIndex: Integer]: Double read GetThreshold;
  end;

  { A scene's groups - vgLodGroups(Scene). }
  TvgLodGroups = class(TvgSceneExtension)
  private
    fGroups  : TObjectList<TvgLodGroup>;
    fIndex   : TDictionary<TvgObject, TvgLodGroup>;
    function  GetCount: Integer;
    function  GetGroup(aIndex: Integer): TvgLodGroup;
  public
    constructor Create;
    destructor  Destroy; override;

    procedure ObjectGone(aObject: TvgObject); override;
    procedure SceneCleared; override;
    procedure MoveTo(aTarget: TvgScene); override;

    { A new empty group of the scene: add levels, objects, thresholds and a
      centre, then Apply. }
    function  Add(aMetric: TvgLodMetric = lmDistance; const aName: String = ''): TvgLodGroup;
    { Clears its objects' bands and frees it. }
    procedure Delete(aGroup: TvgLodGroup);
    procedure Clear;

    { The group aObject is in, nil for none. }
    function  GroupOf(aObject: TvgObject): TvgLodGroup;
    { Every group anchored to aObject. }
    function  AnchoredTo(aObject: TvgObject): TArray<TvgLodGroup>;

    property Count : Integer read GetCount;
    property Items[aIndex: Integer]: TvgLodGroup read GetGroup; default;
  end;

{ aScene's groups: made and added to it the first time when aCreate, nil
  then otherwise. }
function vgLodGroups(aScene: TvgScene; aCreate: Boolean = True): TvgLodGroups;

{ True if aObject is on a level other than 0 of a group: a coarser version
  of something level 0 has.  Exporters that cannot write levels skip it. }
function vgIsLodProxy(aObject: TvgObject): Boolean;

{ For whatever moves objects (PRO's hierarchy): aObject is now placed by
  aWorld - every group of its scene anchored to it follows. }
procedure vgLodAnchorMoved(aObject: TvgObject; const aWorld: TpvMatrix4x4D);

implementation

uses
  System.Math;

function SceneOf(aObject: TvgObject): TvgScene;
begin
  Result := nil;
  if Assigned(aObject) and Assigned(aObject.DataStore) then
    Result := aObject.DataStore.Scene;
end;

function IdentityD: TpvMatrix4x4D;
begin
  Result := TpvMatrix4x4D.CreateTranslation(TpvVector3D.Create(0, 0, 0));
end;

// aPoint through aM, as TvgObjectNode bakes a rest position.
function PlacePoint(const aPoint: TpvVector3D; const aM: TpvMatrix4x4D): TpvVector3D;
begin
  Result := aM.MulHomogen(aPoint);
end;

function Narrow(const V: TpvVector3D): TpvVector3;
begin
  Result := TpvVector3.Create(V.x, V.y, V.z);
end;

// The uniform scale of aM's 3x3 part: the cube root of its determinant.
function UniformScale(const aM: TpvMatrix4x4D): Double;
var
  D : Double;
begin
  D := aM.RawComponents[0, 0] * (aM.RawComponents[1, 1] * aM.RawComponents[2, 2] - aM.RawComponents[1, 2] * aM.RawComponents[2, 1])
     - aM.RawComponents[0, 1] * (aM.RawComponents[1, 0] * aM.RawComponents[2, 2] - aM.RawComponents[1, 2] * aM.RawComponents[2, 0])
     + aM.RawComponents[0, 2] * (aM.RawComponents[1, 0] * aM.RawComponents[2, 1] - aM.RawComponents[1, 1] * aM.RawComponents[2, 0]);
  Result := Power(Abs(D), 1 / 3);
  if (Result = 0) or IsNan(Result) then Result := 1;
end;

{ TvgLodGroup }

constructor TvgLodGroup.Create;
begin
  inherited;
  fLevels := TObjectList<TList<TvgObject>>.Create(True);
  fMetric := lmDistance;
  fAnchorWorld := IdentityD;
end;

destructor TvgLodGroup.Destroy;
begin
  fLevels.Free;
  inherited;
end;

function TvgLodGroup.GetLevelCount: Integer;
begin
  Result := fLevels.Count;
end;

function TvgLodGroup.GetLevel(aIndex: Integer): TArray<TvgObject>;
begin
  CheckLevel(aIndex);
  Result := fLevels[aIndex].ToArray;
end;

function TvgLodGroup.GetThresholdCount: Integer;
begin
  Result := Length(fThresholds);
end;

function TvgLodGroup.GetThreshold(aIndex: Integer): Double;
begin
  Result := fThresholds[aIndex];
end;

procedure TvgLodGroup.CheckLevel(aLevel: Integer);
begin
  if (aLevel < 0) or (aLevel >= fLevels.Count) then
    raise EvgLodError.CreateFmt('Level %d out of range (%d levels)', [aLevel, fLevels.Count]);
end;

procedure TvgLodGroup.SetMetric(const Value: TvgLodMetric);
begin
  if Value = lmNone then
    raise EvgLodError.Create('A level-of-detail group needs a metric');
  fMetric := Value;
end;

function TvgLodGroup.AddLevel: Integer;
begin
  Result := fLevels.Add(TList<TvgObject>.Create);
end;

procedure TvgLodGroup.AddObject(aLevel: Integer; aObject: TvgObject);
var
  Other : TvgLodGroup;
begin
  CheckLevel(aLevel);
  if not Assigned(aObject) then Exit;
  if Assigned(fGroups) then
  begin
    Other := fGroups.GroupOf(aObject);
    if Assigned(Other) then Other.RemoveObject(aObject);
    fGroups.fIndex.AddOrSetValue(aObject, Self);
  end
  else
    RemoveObject(aObject);
  fLevels[aLevel].Add(aObject);
end;

procedure TvgLodGroup.RemoveObject(aObject: TvgObject);
var
  L : TList<TvgObject>;
  Found : Boolean;
begin
  Found := False;
  for L in fLevels do
    if L.Remove(aObject) >= 0 then Found := True;
  if not Found then Exit;
  if Assigned(fGroups) then fGroups.fIndex.Remove(aObject);
  if aObject = fAnchor then fAnchor := nil;
  aObject.ClearLod;
end;

function TvgLodGroup.LevelOf(aObject: TvgObject): Integer;
var
  I : Integer;
begin
  for I := 0 to fLevels.Count - 1 do
    if fLevels[I].Contains(aObject) then Exit(I);
  Result := -1;
end;

procedure TvgLodGroup.SetThresholds(const aValues: array of Double);
var
  I : Integer;
begin
  for I := 1 to High(aValues) do
    if ((fMetric = lmDistance) and (aValues[I] < aValues[I - 1])) or
       ((fMetric = lmScreenSize) and (aValues[I] > aValues[I - 1])) then
      raise EvgLodError.Create('Level-of-detail thresholds out of order: ascending for distance, descending for screen size');
  SetLength(fThresholds, Length(aValues));
  for I := 0 to High(aValues) do
    fThresholds[I] := aValues[I];
end;

procedure TvgLodGroup.SetCentre(const aCentre: TpvVector3D; aRadius: Double);
begin
  fCentre := aCentre;
  fRadius := aRadius;
end;

function TvgLodGroup.Scale: Double;
begin
  if Assigned(fAnchor) then
    Result := UniformScale(fAnchorWorld)
  else
    Result := 1;
end;

function TvgLodGroup.WorldCentre: TpvVector3D;
begin
  if Assigned(fAnchor) then
    Result := PlacePoint(fCentre, fAnchorWorld)
  else
    Result := fCentre;
end;

function TvgLodGroup.WorldThreshold(aIndex: Integer): Double;
begin
  Result := fThresholds[aIndex];
  if fMetric = lmDistance then
    Result := Result * Scale;
end;

procedure TvgLodGroup.SetAnchor(aObject: TvgObject; const aWorld: TpvMatrix4x4D);
var
  S : Double;
  I : Integer;
begin
  if aObject = nil then
  begin
    // Back to world values, where the group is now.
    if Assigned(fAnchor) then
    begin
      S := Scale;
      fCentre := WorldCentre;
      fRadius := fRadius * S;
      if fMetric = lmDistance then
        for I := 0 to High(fThresholds) do
          fThresholds[I] := fThresholds[I] * S;
    end;
    fAnchor := nil;
    fAnchorWorld := IdentityD;
    Exit;
  end;
  fAnchor := aObject;
  fAnchorWorld := aWorld;
end;

procedure TvgLodGroup.AnchorMoved(const aWorld: TpvMatrix4x4D);
begin
  if not Assigned(fAnchor) then Exit;
  fAnchorWorld := aWorld;
  Apply;
end;

procedure TvgLodGroup.Apply;
var
  I, LevelIdx : Integer;
  Lo, Hi, S   : Double;
  C           : TpvVector3D;
  Scene       : TvgScene;
  Band        : TvgLodBand;
  Obj         : TvgObject;
begin
  if fApplying then Exit;
  if fLevels.Count = 0 then Exit;
  if Length(fThresholds) < fLevels.Count - 1 then
    raise EvgLodError.CreateFmt('%d levels need %d thresholds, the group has %d',
      [fLevels.Count, fLevels.Count - 1, Length(fThresholds)]);

  fApplying := True;
  try
    S := Scale;
    C := WorldCentre;
    for LevelIdx := 0 to fLevels.Count - 1 do
    begin
      if fMetric = lmDistance then
      begin
        if LevelIdx = 0 then Lo := 0 else Lo := fThresholds[LevelIdx - 1] * S;
        if LevelIdx = fLevels.Count - 1 then Hi := Infinity else Hi := fThresholds[LevelIdx] * S;
      end
      else
      begin
        // Pixels: finest first, largest on screen.
        if LevelIdx = fLevels.Count - 1 then Lo := 0 else Lo := fThresholds[LevelIdx];
        if LevelIdx = 0 then Hi := Infinity else Hi := fThresholds[LevelIdx - 1];
      end;

      for I := 0 to fLevels[LevelIdx].Count - 1 do
      begin
        Obj := fLevels[LevelIdx][I];
        Scene := SceneOf(Obj);
        // The band's centre is in the store's space, local to WorldOrigin.
        if Assigned(Scene) then
          Band.Centre := Narrow(Scene.WorldToLocal(C))
        else
          Band.Centre := Narrow(C);
        Band.Metric := fMetric;
        Band.Radius := fRadius * S;
        Band.Min    := Lo;
        Band.Max    := Hi;
        Obj.SetLod(Band);
      end;
    end;
  finally
    fApplying := False;
  end;
end;

procedure TvgLodGroup.Unapply;
var
  L   : TList<TvgObject>;
  Obj : TvgObject;
begin
  for L in fLevels do
    for Obj in L do
      Obj.ClearLod;
end;

function TvgLodGroup.LevelFor(const aView: TvgLodView): Integer;
var
  I    : Integer;
  Obj  : TvgObject;
  Band : TvgLodBand;
begin
  // The level whose band takes the view, read from its first object with
  // one.  An empty level has no object to ask: -1 when it is the one in
  // range, since nothing is drawn there.
  for I := 0 to fLevels.Count - 1 do
    for Obj in fLevels[I] do
    begin
      Band := Obj.GetLod;
      if Band.Metric = lmNone then Continue;
      if Band.Accepts(aView) then Exit(I);
      Break;
    end;
  Result := -1;
end;

function TvgLodGroup.LevelForRenderer(aRenderer: TvgBaseRenderEngine): Integer;
var
  View : TvgLodView;
begin
  if Assigned(aRenderer) and aRenderer.GetLodView(View) then
    Result := LevelFor(View)
  else
    Result := 0;
end;

{ TvgLodGroups }

constructor TvgLodGroups.Create;
begin
  inherited;
  fGroups := TObjectList<TvgLodGroup>.Create(True);
  fIndex  := TDictionary<TvgObject, TvgLodGroup>.Create;
end;

destructor TvgLodGroups.Destroy;
begin
  // The scene is going or the groups are: nothing to tell the objects,
  // whose stores go first or keep their bands harmlessly.
  fIndex.Free;
  fGroups.Free;
  inherited;
end;

function TvgLodGroups.GetCount: Integer;
begin
  Result := fGroups.Count;
end;

function TvgLodGroups.GetGroup(aIndex: Integer): TvgLodGroup;
begin
  Result := fGroups[aIndex];
end;

function TvgLodGroups.Add(aMetric: TvgLodMetric; const aName: String): TvgLodGroup;
begin
  Result := TvgLodGroup.Create;
  Result.fGroups := Self;
  Result.Metric  := aMetric;
  Result.fName   := aName;
  fGroups.Add(Result);
end;

procedure TvgLodGroups.Delete(aGroup: TvgLodGroup);
var
  L   : TList<TvgObject>;
  Obj : TvgObject;
begin
  if not Assigned(aGroup) or (fGroups.IndexOf(aGroup) < 0) then Exit;
  for L in aGroup.fLevels do
    for Obj in L do
    begin
      fIndex.Remove(Obj);
      Obj.ClearLod;
    end;
  fGroups.Remove(aGroup);
end;

procedure TvgLodGroups.Clear;
begin
  while fGroups.Count > 0 do
    Delete(fGroups.Last);
end;

function TvgLodGroups.GroupOf(aObject: TvgObject): TvgLodGroup;
begin
  if not fIndex.TryGetValue(aObject, Result) then
    Result := nil;
end;

function TvgLodGroups.AnchoredTo(aObject: TvgObject): TArray<TvgLodGroup>;
var
  G : TvgLodGroup;
begin
  Result := nil;
  if not Assigned(aObject) then Exit;
  for G in fGroups do
    if G.fAnchor = aObject then
      Result := Result + [G];
end;

procedure TvgLodGroups.ObjectGone(aObject: TvgObject);
var
  G : TvgLodGroup;
  L : TList<TvgObject>;
begin
  // Leaving the scene: off its level, no band to clear (its record may be
  // a tombstone already).  An anchor going leaves its groups where they are.
  for G in fGroups do
    if G.fAnchor = aObject then
      G.SetAnchor(nil, G.fAnchorWorld);
  if not fIndex.TryGetValue(aObject, G) then Exit;
  fIndex.Remove(aObject);
  for L in G.fLevels do
    L.Remove(aObject);
end;

procedure TvgLodGroups.SceneCleared;
begin
  // The objects are going with their stores: no bands to clear.
  fIndex.Clear;
  fGroups.Clear;
end;

procedure TvgLodGroups.MoveTo(aTarget: TvgScene);
var
  Target : TvgLodGroups;
  G      : TvgLodGroup;
  Pair   : TPair<TvgObject, TvgLodGroup>;
begin
  // The groups go with the stores.  The target's origin is this scene's
  // (vgAppendSceneFile sets it), so the bands already written stay right.
  if fGroups.Count = 0 then Exit;
  Target := vgLodGroups(aTarget, True);
  while fGroups.Count > 0 do
  begin
    G := fGroups.Extract(fGroups.First);
    G.fGroups := Target;
    Target.fGroups.Add(G);
  end;
  for Pair in fIndex do
    Target.fIndex.AddOrSetValue(Pair.Key, Pair.Value);
  fIndex.Clear;
end;

{ globals }

function vgLodGroups(aScene: TvgScene; aCreate: Boolean): TvgLodGroups;
begin
  Result := nil;
  if not Assigned(aScene) then Exit;
  Result := TvgLodGroups(aScene.FindExtension(TvgLodGroups));
  if (Result = nil) and aCreate then
  begin
    Result := TvgLodGroups.Create;
    aScene.AddExtension(Result);
  end;
end;

function vgIsLodProxy(aObject: TvgObject): Boolean;
var
  Groups : TvgLodGroups;
  G      : TvgLodGroup;
begin
  Result := False;
  Groups := vgLodGroups(SceneOf(aObject), False);
  if not Assigned(Groups) then Exit;
  G := Groups.GroupOf(aObject);
  Result := Assigned(G) and (G.LevelOf(aObject) > 0);
end;

procedure vgLodAnchorMoved(aObject: TvgObject; const aWorld: TpvMatrix4x4D);
var
  Groups : TvgLodGroups;
  G      : TvgLodGroup;
begin
  Groups := vgLodGroups(SceneOf(aObject), False);
  if not Assigned(Groups) then Exit;
  for G in Groups.AnchoredTo(aObject) do
    G.AnchorMoved(aWorld);
end;

end.
