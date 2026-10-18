unit Vulkan_Instancing;

{******************************************************************************
 *  Many copies of one model, one 4x4 matrix per copy.                         *
 *                                                                            *
 *  A model is whatever stores a loader made - an OBJ's one per material, a   *
 *  glTF's per mesh - and TvgInstanceSet gives every live instanced object    *
 *  in every one of them the SAME list of matrices, so the parts stay         *
 *  together.  The vertices are never copied: each store draws its mesh once  *
 *  per matrix from the one instance buffer, and culls against the union of   *
 *  the copies (TvgVulkanDataStore.RecomputeWorldBounds).                     *
 *                                                                            *
 *  vgMakeStoreInstanced adds idtMatrix to a store's instances, live or not:  *
 *  a store already on a renderer has its pipelines and buffers dropped and   *
 *  rebuilt round the new layout.  A store with PrebuiltShaderVariants then   *
 *  loads <BaseVertName>Inst, which has to exist (VulkanShaders\README.md).   *
 *                                                                            *
 *  vgScatterMatrices makes the matrices: random positions in a region, put   *
 *  on a surface by an IvgSurfaceSampler, a random turn about an axis and a   *
 *  random scale, optionally tilted toward the surface normal.  It is axis    *
 *  neutral - "up" and "horizontal" are vgWorldUp and the plane across it.    *
 *                                                                            *
 *  Coordinates are the stores' own: local to TvgScene.WorldOrigin.           *
 ******************************************************************************}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  PasVulkan.Math, PasVulkan.Math.Double,
  Vulkan_Components_Descriptors, Vulkan_Components_Camera,
  Vulkan_Components_DataStore, Vulkan_Components_Scene_Renderer,
  System.Math,
  Vulkan_Components,
  Vulkan_Components_Lookups,
  Vulkan_WorldAxes;

type
  EvgInstancingError = class(Exception);

  // Where a surface is.  aPoint's height (its vgWorldUp component) is
  // ignored; aSurface is aPoint moved along vgWorldUp onto the surface and
  // aNormal its unit normal there.  False where there is no surface under or
  // over aPoint - outside a triangulation's hull, say - and the scatter then
  // tries another point.
  IvgSurfaceSampler = interface
    ['{6E0C1E8B-3A0D-4B5C-9C61-2F7A9D4E8B10}']
    function Sample(const aPoint: TpvVector3D; out aSurface, aNormal: TpvVector3D): Boolean;
  end;

  // A level plane aHeight along vgWorldUp: a fixed "Z" for every copy.
  TvgFlatSurface = class(TInterfacedObject, IvgSurfaceSampler)
  private
    fHeight: Double;
  public
    constructor Create(aHeight: Double = 0);
    function Sample(const aPoint: TpvVector3D; out aSurface, aNormal: TpvVector3D): Boolean;
    property Height: Double read fHeight write fHeight;
  end;

  TvgScatterSettings = record
    Count        : Integer;       // copies wanted
    Seed         : Cardinal;      // same seed and settings, same matrices
    RegionMin,                    // the horizontal box points are drawn from;
    RegionMax    : TpvVector3D;   //   the up components are ignored
    HeightOffset : Double;        // added along vgWorldUp after sampling
    ModelUp      : TpvVector3D;   // the model's own up as authored (an OBJ is
                                  //   often +Y); zero = vgWorldUp
    SpinAxis     : TpvVector3D;   // turn axis once upright, world frame; zero = vgWorldUp
    SpinMin,
    SpinMax      : Double;        // degrees
    ScaleMin,
    ScaleMax     : Double;        // uniform scale
    AlignToSlope : Double;        // 0 upright .. 1 along the surface normal
    MinSpacing   : Double;        // horizontal distance between copies; 0 = any
    MaxAttempts  : Integer;       // per copy, before giving up; 0 = 30
    // One upright copy per point at scale 1, any turn, no spacing.
    class function Default(aCount: Integer; const aMin, aMax: TpvVector3D): TvgScatterSettings; static;
  end;

  TvgMatrixArray = TArray<TvgMatrix4x4S>;

  // The matrix that puts a model's aPivot at aPosition: scaled by aScale,
  // stood up (its aModelUp turned onto vgWorldUp), turned aSpinDegrees about
  // aSpinAxis, then tilted so its up is aUp.  A zero aModelUp or aSpinAxis
  // means vgWorldUp.  Columns as GLSL reads them: RawComponents[c, r].
  function vgPlacementMatrix(const aPivot, aPosition, aModelUp: TpvVector3D;
    const aSpinAxis: TpvVector3D; aSpinDegrees, aScale: Double;
    const aUp: TpvVector3D): TvgMatrix4x4S;

  // Fewer than Settings.Count when the sampler or MinSpacing rejected too
  // many points: Length(Result) is how many were placed.
  function vgScatterMatrices(const aSettings: TvgScatterSettings;
    const aSampler: IvgSurfaceSampler; const aPivot: TpvVector3D): TvgMatrixArray;

  // Adds idtMatrix to aStore's instance attributes (keeping the rest), so
  // every instance draws through its own matrix - identity until set.  A
  // store on a live scene is disconnected and connected again round the
  // change.  Raises, changing nothing, when the store loads prebuilt shaders
  // and no shader folder has <BaseVertName>Inst_vert.spv.
  procedure vgMakeStoreInstanced(aStore: TvgObjectStore);

type
  TvgInstanceSet = class(TComponent)
  private type
    TObjectKey = record
      Store : TvgObjectStore;
      Index : NativeInt;   // pointer sized, so the key has no padding for the comparer to read
    end;
    TObjectID = record
      ID1, ID2 : Cardinal;
    end;
  private
    fStores   : TList<TvgObjectStore>;
    fMatrices : TvgMatrixArray;
    // Each object's ID as first seen, so cutting the copies to none and
    // growing them again does not lose it with the last instance.
    fIDs      : TDictionary<TObjectKey, TObjectID>;
    procedure ForgetStore(aStore: TvgObjectStore);
    function GetStore(aIndex: Integer): TvgObjectStore;
    function GetStoreCount: Integer;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); overload; override;
    constructor Create(const aStores: array of TvgObjectStore); reintroduce; overload;
    destructor Destroy; override;

    procedure AddStore(aStore: TvgObjectStore);
    procedure Clear;

    // The model as loaded: the union of every live object's vertex bounds,
    // whatever its instances say.
    function ModelBounds: TvgAABB;
    // Where the model stands: the middle of ModelBounds across, its bottom
    // along vgWorldUp.  The pivot vgScatterMatrices sets on the surface.
    // aModelUp as in TvgScatterSettings: the bottom is along it.
    function BasePivot: TpvVector3D; overload;
    function BasePivot(const aModelUp: TpvVector3D): TpvVector3D; overload;

    // Every store is made instanced (vgMakeStoreInstanced), then every live
    // instanced object gets exactly these copies, each carrying the object
    // ID of its first instance.  An empty array leaves the objects drawing
    // nothing.
    procedure SetMatrices(const aMatrices: TvgMatrixArray);
    property Matrices: TvgMatrixArray read fMatrices;

    property StoreCount: Integer read GetStoreCount;
    property Stores[aIndex: Integer]: TvgObjectStore read GetStore;
  end;

implementation


type
  TMat3 = array[0..2, 0..2] of Double;   // [row, column]

function Rotation(const aAxis: TpvVector3D; aRadians: Double): TMat3;
var A: TpvVector3D; C, S, T: Double;
begin
  A := aAxis.Normalize;
  C := Cos(aRadians); S := Sin(aRadians); T := 1 - C;
  Result[0, 0] := C + A.x * A.x * T;       Result[0, 1] := A.x * A.y * T - A.z * S; Result[0, 2] := A.x * A.z * T + A.y * S;
  Result[1, 0] := A.y * A.x * T + A.z * S; Result[1, 1] := C + A.y * A.y * T;       Result[1, 2] := A.y * A.z * T - A.x * S;
  Result[2, 0] := A.z * A.x * T - A.y * S; Result[2, 1] := A.z * A.y * T + A.x * S; Result[2, 2] := C + A.z * A.z * T;
end;

function Identity3: TMat3;
var R, C: Integer;
begin
  for R := 0 to 2 do for C := 0 to 2 do Result[R, C] := Ord(R = C);
end;

function Mul(const A, B: TMat3): TMat3;
var R, C: Integer;
begin
  for R := 0 to 2 do
    for C := 0 to 2 do
      Result[R, C] := A[R, 0] * B[0, C] + A[R, 1] * B[1, C] + A[R, 2] * B[2, C];
end;

function Apply(const M: TMat3; const V: TpvVector3D): TpvVector3D;
begin
  Result.x := M[0, 0] * V.x + M[0, 1] * V.y + M[0, 2] * V.z;
  Result.y := M[1, 0] * V.x + M[1, 1] * V.y + M[1, 2] * V.z;
  Result.z := M[2, 0] * V.x + M[2, 1] * V.y + M[2, 2] * V.z;
end;

// The shortest turn taking unit aFrom onto unit aTo.
function FromTo(const aFrom, aTo: TpvVector3D): TMat3;
var Axis: TpvVector3D; Sin_, Cos_: Double;
begin
  Axis := aFrom.Cross(aTo);
  Sin_ := Axis.Length; Cos_ := aFrom.Dot(aTo);
  if Sin_ < 1E-9 then
  begin
    if Cos_ > 0 then Exit(Identity3);
    // Opposite: half a turn about anything perpendicular.
    Exit(Rotation(aFrom.Perpendicular, Pi));
  end;
  Result := Rotation(Axis, ArcTan2(Sin_, Cos_));
end;

function vgPlacementMatrix(const aPivot, aPosition, aModelUp: TpvVector3D;
  const aSpinAxis: TpvVector3D; aSpinDegrees, aScale: Double;
  const aUp: TpvVector3D): TvgMatrix4x4S;
var Up, Axis, T: TpvVector3D; L: TMat3; R, C: Integer;
begin
  Up := vgWorldUp;
  Axis := aSpinAxis;
  if Axis.Length < 1E-12 then Axis := Up;
  L := Rotation(Axis, DegToRad(aSpinDegrees));
  if aModelUp.Length > 1E-12 then
    L := Mul(L, FromTo(aModelUp.Normalize, Up));
  if aUp.Length > 1E-12 then
    L := Mul(FromTo(Up, aUp.Normalize), L);
  for R := 0 to 2 do for C := 0 to 2 do L[R, C] := L[R, C] * aScale;

  // x' = L (x - pivot) + position
  T := aPosition - Apply(L, aPivot);

  Result := TvgMatrix4x4S.Null;
  for C := 0 to 2 do
    for R := 0 to 2 do
      Result.RawComponents[C, R] := L[R, C];
  Result.RawComponents[3, 0] := T.x;
  Result.RawComponents[3, 1] := T.y;
  Result.RawComponents[3, 2] := T.z;
  Result.RawComponents[3, 3] := 1;
end;

{ TvgFlatSurface }

constructor TvgFlatSurface.Create(aHeight: Double);
begin
  inherited Create;
  fHeight := aHeight;
end;

function TvgFlatSurface.Sample(const aPoint: TpvVector3D; out aSurface, aNormal: TpvVector3D): Boolean;
begin
  aNormal  := vgWorldUp;
  aSurface := aPoint + aNormal * (fHeight - vgUpComponent(aPoint));
  Result   := True;
end;

{ TvgScatterSettings }

class function TvgScatterSettings.Default(aCount: Integer; const aMin, aMax: TpvVector3D): TvgScatterSettings;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Count     := aCount;
  Result.Seed      := 1;
  Result.RegionMin := aMin;
  Result.RegionMax := aMax;
  Result.SpinMax   := 360;
  Result.ScaleMin  := 1;
  Result.ScaleMax  := 1;
end;

{ Scatter }

type
  // xorshift32: the same sequence on every platform and Delphi version,
  // which System.Random does not promise.
  TRandom = record
    State: Cardinal;
    procedure Init(aSeed: Cardinal);
    function Next: Double;                       // [0, 1)
    function Range(aMin, aMax: Double): Double;
  end;

procedure TRandom.Init(aSeed: Cardinal);
begin
  State := aSeed;
  if State = 0 then State := $9E3779B9;
end;

function TRandom.Next: Double;
begin
  State := State xor (State shl 13);
  State := State xor (State shr 17);
  State := State xor (State shl 5);
  Result := State / 4294967296.0;
end;

function TRandom.Range(aMin, aMax: Double): Double;
begin
  Result := aMin + (aMax - aMin) * Next;
end;

function vgScatterMatrices(const aSettings: TvgScatterSettings;
  const aSampler: IvgSurfaceSampler; const aPivot: TpvVector3D): TvgMatrixArray;
var
  Rnd                    : TRandom;
  Up, Right, Fwd         : TpvVector3D;
  P, Surface, Normal, Tilt : TpvVector3D;
  Placed                 : TList<TvgMatrix4x4S>;
  Grid                   : TDictionary<Int64, TList<TPair<Double, Double>>>;
  Cells                  : TObjectList<TList<TPair<Double, Double>>>;
  Attempts, MaxTries     : Integer;
  U, V                   : Double;

  function Key(aCU, aCV: Integer): Int64;
  begin
    Result := (Int64(aCU) shl 32) or Int64(Cardinal(aCV));
  end;

  function Spaced(aU, aV: Double): Boolean;
  var CU, CV, DU, DV: Integer; L: TList<TPair<Double, Double>>; Q: TPair<Double, Double>;
  begin
    Result := True;
    if aSettings.MinSpacing <= 0 then Exit;
    CU := Floor(aU / aSettings.MinSpacing); CV := Floor(aV / aSettings.MinSpacing);
    for DU := -1 to 1 do
      for DV := -1 to 1 do
        if Grid.TryGetValue(Key(CU + DU, CV + DV), L) then
          for Q in L do
            if Sqr(Q.Key - aU) + Sqr(Q.Value - aV) < Sqr(aSettings.MinSpacing) then
              Exit(False);
  end;

  procedure Remember(aU, aV: Double);
  var K: Int64; L: TList<TPair<Double, Double>>;
  begin
    if aSettings.MinSpacing <= 0 then Exit;
    K := Key(Floor(aU / aSettings.MinSpacing), Floor(aV / aSettings.MinSpacing));
    if not Grid.TryGetValue(K, L) then
    begin
      L := TList<TPair<Double, Double>>.Create;
      Cells.Add(L); Grid.Add(K, L);
    end;
    L.Add(TPair<Double, Double>.Create(aU, aV));
  end;

begin
  Result := nil;
  if not Assigned(aSampler) then
    raise EvgInstancingError.Create('vgScatterMatrices needs a surface sampler');
  if aSettings.Count <= 0 then Exit;

  Up := vgWorldUp; Right := vgWorldRight; Fwd := vgWorldForward;
  MaxTries := aSettings.MaxAttempts;
  if MaxTries <= 0 then MaxTries := 30;

  Rnd.Init(aSettings.Seed);
  Placed := TList<TvgMatrix4x4S>.Create;
  Grid   := TDictionary<Int64, TList<TPair<Double, Double>>>.Create;
  Cells  := TObjectList<TList<TPair<Double, Double>>>.Create(True);
  try
    Attempts := 0;
    while (Placed.Count < aSettings.Count) and (Attempts < aSettings.Count * MaxTries) do
    begin
      Inc(Attempts);
      // Every component drawn, the up one included: the sampler ignores it,
      // and drawing it keeps the sequence the same under either convention.
      P.x := Rnd.Range(aSettings.RegionMin.x, aSettings.RegionMax.x);
      P.y := Rnd.Range(aSettings.RegionMin.y, aSettings.RegionMax.y);
      P.z := Rnd.Range(aSettings.RegionMin.z, aSettings.RegionMax.z);
      if not aSampler.Sample(P, Surface, Normal) then Continue;

      U := Surface.Dot(Right); V := Surface.Dot(Fwd);
      if not Spaced(U, V) then Continue;

      Tilt := Up;
      if aSettings.AlignToSlope > 0 then
        Tilt := Up.Lerp(Normal.Normalize, EnsureRange(aSettings.AlignToSlope, 0, 1));

      Placed.Add(vgPlacementMatrix(aPivot, Surface + Up * aSettings.HeightOffset,
        aSettings.ModelUp, aSettings.SpinAxis, Rnd.Range(aSettings.SpinMin, aSettings.SpinMax),
        Rnd.Range(aSettings.ScaleMin, aSettings.ScaleMax), Tilt));
      Remember(U, V);
    end;
    Result := Placed.ToArray;
  finally
    Cells.Free; Grid.Free; Placed.Free;
  end;
end;

{ vgMakeStoreInstanced }

procedure vgMakeStoreInstanced(aStore: TvgObjectStore);
var
  Types  : TInstanceDataTypes;
  IType  : TInstanceDataType;
  Scene  : TvgScene;
  Shader : String;
  I      : Integer;
  Live   : Boolean;
begin
  if not Assigned(aStore) then Exit;
  if aStore.IsInstanceTypeSet(idtMatrix) then Exit;

  if aStore.PrebuiltShaderVariants and (aStore.BaseVertName <> '') then
  begin
    Shader := aStore.BaseVertName + 'Inst_vert.spv';
    if vgFindShaderFile(Shader) = '' then
      raise EvgInstancingError.CreateFmt('%s cannot draw instanced copies: %s is in no shader folder',
        [aStore.BaseVertName, Shader]);
  end;

  Types := [];
  for IType := Low(TInstanceDataType) to High(TInstanceDataType) do
    if aStore.IsInstanceTypeSet(IType) then Include(Types, IType);
  Include(Types, idtMatrix);

  // The pipeline's vertex input and the GPU buffers are both built from the
  // layout, so a store already drawn loses both first - the same round trip
  // a live PointSize change takes.  The CPU data stays.
  Scene := aStore.Scene;
  Live  := Assigned(Scene) and Assigned(Scene.RendererList) and (Scene.SceneState = SS_READY);
  if Assigned(Scene) and Assigned(Scene.RendererList) then
    for I := 0 to Scene.RendererList.Count - 1 do
      if Assigned(Scene.RendererList.Items[I]) then
        aStore.DisConnectDataFromSceneandRenderer(Scene.RendererList.Items[I]);
  aStore.DeleteVulkanDataBuffers;

  aStore.ChangeInstanceAttributes(Types);

  if Live then
  begin
    Scene.ConnectStoreLive(aStore);
    Scene.NotifyDataChanged(aStore);
  end;
end;

{ TvgInstanceSet }

constructor TvgInstanceSet.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  fStores := TList<TvgObjectStore>.Create;
  fIDs    := TDictionary<TObjectKey, TObjectID>.Create;
end;

constructor TvgInstanceSet.Create(const aStores: array of TvgObjectStore);
var S: TvgObjectStore;
begin
  Create(nil);
  for S in aStores do AddStore(S);
end;

destructor TvgInstanceSet.Destroy;
begin
  Clear;
  fStores.Free;
  fIDs.Free;
  inherited;
end;

procedure TvgInstanceSet.ForgetStore(aStore: TvgObjectStore);
var Key: TObjectKey; Gone: TList<TObjectKey>;
begin
  Gone := TList<TObjectKey>.Create;
  try
    for Key in fIDs.Keys do
      if Key.Store = aStore then Gone.Add(Key);
    for Key in Gone do fIDs.Remove(Key);
  finally Gone.Free; end;
end;

procedure TvgInstanceSet.AddStore(aStore: TvgObjectStore);
begin
  if not Assigned(aStore) or fStores.Contains(aStore) then Exit;
  fStores.Add(aStore);
  aStore.FreeNotification(Self);
end;

procedure TvgInstanceSet.Clear;
var S: TvgObjectStore;
begin
  for S in fStores do S.RemoveFreeNotification(Self);
  fStores.Clear;
  fIDs.Clear;
end;

procedure TvgInstanceSet.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and Assigned(fStores) then
  begin
    fStores.Remove(TvgObjectStore(AComponent));
    ForgetStore(TvgObjectStore(AComponent));
  end;
end;

function TvgInstanceSet.GetStore(aIndex: Integer): TvgObjectStore;
begin
  Result := fStores[aIndex];
end;

function TvgInstanceSet.GetStoreCount: Integer;
begin
  Result := fStores.Count;
end;

// The store's data object indices, through its TvgObjects - a TvgObjectStore
// counts those (GetObjectCount), not the DataStore's records - leaving out
// any deleted.
function LiveObjects(aStore: TvgObjectStore): TArray<Integer>;
var I, D: Integer;
begin
  Result := nil;
  for I := 0 to aStore.GetObjectCount - 1 do
  begin
    D := aStore.GetObjectItem(I).ObjIndex;
    if (D >= 0) and not aStore.IsObjectDeleted(D) then Result := Result + [D];
  end;
end;

function TvgInstanceSet.ModelBounds: TvgAABB;
var S: TvgObjectStore; I: Integer; B: TvgAABB;
begin
  Result.Reset;
  for S in fStores do
    for I in LiveObjects(S) do
    begin
      B := S.GetObjectLocalBounds(I);
      if B.Valid then Result.GrowAABB(B);
    end;
end;

function TvgInstanceSet.BasePivot: TpvVector3D;
begin
  Result := BasePivot(TpvVector3D.Create(0, 0, 0));
end;

function TvgInstanceSet.BasePivot(const aModelUp: TpvVector3D): TpvVector3D;
var B: TvgAABB; Lo, Hi, Mid, Up: TpvVector3D; Bottom: Double;
begin
  B := ModelBounds;
  if not B.Valid then Exit(TpvVector3D.Create(0, 0, 0));
  Up := aModelUp;
  if Up.Length < 1E-12 then Up := vgWorldUp;
  Up := Up.Normalize;
  Lo := TpvVector3D(B.Min); Hi := TpvVector3D(B.Max);
  Mid := (Lo + Hi) * 0.5;
  // The box's lowest point along Up: each component from whichever side
  // Up points away from, so a negative or slanted axis works too.
  Bottom := Min(Lo.x * Up.x, Hi.x * Up.x) + Min(Lo.y * Up.y, Hi.y * Up.y) +
            Min(Lo.z * Up.z, Hi.z * Up.z);
  Result := Mid + Up * (Bottom - Mid.Dot(Up));
end;

procedure TvgInstanceSet.SetMatrices(const aMatrices: TvgMatrixArray);
var S: TvgObjectStore; I, J: Integer; Key: TObjectKey; ID: TObjectID; HasID: Boolean;
begin
  fMatrices := Copy(aMatrices);
  for S in fStores do
  begin
    vgMakeStoreInstanced(S);
    for I in LiveObjects(S) do
    begin
      if not S.ObjectHasInstances(I) then Continue;
      Key.Store := S; Key.Index := I;
      HasID := fIDs.TryGetValue(Key, ID);
      if not HasID and S.IsInstanceTypeSet(idtObjID) and (S.GetObjectInstanceCount(I) > 0) then
      begin
        S.GetObjectInstanceObjID(I, 0, ID.ID1, ID.ID2);
        fIDs.Add(Key, ID);
        HasID := True;
      end;

      S.SetObjectInstanceCount(I, Length(fMatrices));
      for J := 0 to High(fMatrices) do
      begin
        if HasID then S.SetObjectInstanceObjID(I, J, ID.ID1, ID.ID2);
        S.SetObjectInstanceMatrix(I, J, fMatrices[J]);
      end;
    end;
    if Assigned(S.Scene) then S.Scene.NotifyDataChanged(S);
  end;
end;

end.
