unit Vulkan_Components_Camera;

{
  Vulkan_Components_Camera.pas

  A generic, flexible 3D camera implementation compatible with:
  - glTF camera structures (perspective/orthographic)
  - Standard graphics APIs (OpenGL, Vulkan, DirectX conventions)
  - PasVulkan.Math.Double structures
  - Delphi/FreePascal serialization

  Precision:
  - Everything the camera owns - position, target, up, lens parameters and
    every cached matrix - is double precision (PasVulkan.Math.Double).  World
    coordinates here can be survey values with six digits before the decimal,
    where float32 steps are 62.5 mm; the view matrix's translation is exactly
    such a value.
  - TvgAABB stays single: it is built from vertex data, which the data stores
    keep in float32.
  - PasVulkan.Math.Double converts double types to single IMPLICITLY, so code
    that assigns a camera result to a TpvVector3/TpvMatrix4x4 still compiles
    and silently drops back to float32.  Keep camera results in the D types.

  Features:
  - Perspective and orthographic projection modes
  - View matrix (position, target, up vector)
  - Projection matrix with Vulkan clip space (-1 to +1, inverted Y)
  - Interactive controls: orbit, pan, zoom, dolly
  - Far/near plane management
  - Aspect ratio / FOV controls
  - Thread-safe matrix caching
}

interface

uses
  System.SysUtils,
  System.Math,
  System.SyncObjs,
  System.Generics.Collections,
  PasVulkan.Math,
  PasVulkan.Math.Double,
  PasVulkan.Types,
  Vulkan_WorldAxes;


const
  CAMERA_DEFAULT_FOV     = 45.0;
  CAMERA_DEFAULT_NEAR    = 0.01;
  CAMERA_DEFAULT_FAR     = 10000.0;
  CAMERA_DEFAULT_ASPECT  = 16.0 / 9.0;

  // Smallest near plane the fit methods will produce.  SetPerspective and
  // SetOrthographic already clamp to 0.0001; this is the same floor applied
  // before the far plane is derived from it, so a degenerate dataset cannot
  // ask for a near of zero and get a far of 0.1 back.
  CAMERA_MIN_NEAR        = 0.0001;

  // Default empty space left around the data by the ZoomAll family: 1.0
  // touches the data to the edge of the viewport, 1.05 leaves 5%.
  CAMERA_DEFAULT_ZOOM_MARGIN = 1.05;

  // Index of each plane within TvgFrustrumPlanes.Planes.
  //
  // These are the planes produced by the standard Gribb/Hartmann extraction,
  // named for the clip-space bound each one comes from.  Note that a
  // projection with a negated Y (which is how Vulkan clip space is normally
  // reached, and what GetViewProjectionMatrixForAspect builds) swaps which
  // of TOP/BOTTOM is geometrically above the other.  The six planes still
  // bound exactly the same volume, so culling is unaffected; only the labels
  // would read backwards if you inspected them individually.
  FRUSTUM_PLANE_LEFT   = 0;
  FRUSTUM_PLANE_RIGHT  = 1;
  FRUSTUM_PLANE_BOTTOM = 2;
  FRUSTUM_PLANE_TOP    = 3;
  FRUSTUM_PLANE_NEAR   = 4;
  FRUSTUM_PLANE_FAR    = 5;

type
  TvgCamera = class;

  TCameraProjectionType = (ptNone, ptPerspective, ptOrthographic);

  TCameraUpdateFlags = set of (
    cfViewDirty,
    cfProjectionDirty,
    cfFrustumDirty,
    // FViewProjectionMatrix is older than FViewMatrix or FProjectionMatrix.
    // Set by the Recalculate* that rebuild either one, cleared only when the
    // product is rebuilt.  Needed as a flag of its own: GetViewProjection-
    // MatrixForAspect rebuilds the view and clears cfViewDirty without
    // touching the cached product, so testing the other two flags cannot
    // tell whether the product is current.
    cfViewProjectionDirty
  );

  { Six world-space clipping planes of a view frustum.

    Each plane is stored as (A,B,C,D) where the normal (A,B,C) points INWARD,
    so a point P is on the inside of the plane when
    A*P.x + B*P.y + C*P.z + D >= 0.  (A,B,C) is unit length, which makes the
    value of that expression the true signed distance from P to the plane.
    Culling code depends on that: testing a bounding volume compares the
    distance against the volume's radius/extent, which is only meaningful if
    the plane really is normalised.

    Double precision: D is the plane's distance from the coordinate origin,
    so for a camera at survey coordinates it is a six or seven digit number
    that float32 would round to the nearest 1/16 or worse. }
  TvgFrustrumPlanes = Record
     Planes :  array [0..5] of TpvVector4D;
  end;

  { Axis-aligned bounding box, used to cull an object without touching its
    geometry.  Whatever space the box is built in is the space it must be
    tested in; for frustum culling that means world space.

    Valid is False until at least one point has been added, and Min/Max mean
    nothing while it is False - an EMPTY box is not the same as a box at the
    origin, and treating one as the other would cull objects sitting near
    (0,0,0).  A zero-filled record is already a correct empty box, so a
    FillChar'd owner needs no extra initialisation.

    Single precision on purpose: boxes are built from vertex positions, which
    the data stores hold in float32, so a double box would only carry digits
    its source never had. }
  TvgAABB = Record
  Public
    Min, Max : TpvVector3;
    Valid    : Boolean;

    procedure Reset;

    // Extend to include a point or another box.  Growing by an empty box is
    // a no-op; growing an empty box makes it exactly that point/box.
    procedure GrowPoint(const aPoint: TpvVector3);        Overload;
    procedure GrowPoint(aX, aY, aZ: Single);              Overload;
    procedure GrowAABB(const aBox: TvgAABB);

    // Adopt explicit bounds.  For geometry whose vertices the CPU never sees
    // - anything a compute shader writes - this is the only way to get a
    // usable box.  Components are ordered, so the caller may pass corners
    // either way round.
    procedure SetBounds(const aMin, aMax: TpvVector3);

    function  Centre  : TpvVector3;   // undefined unless Valid
    function  Extents : TpvVector3;   // HALF the size, undefined unless Valid
    function  Size    : TpvVector3;
    function  Radius  : Single;       // bounding sphere about Centre

    { Box enclosing this box transformed by aMatrix (Arvo's method: transform
      the centre, and scale the extents by the absolute value of the basis).
      The result is a bound on the transformed box, not a tight fit - for a
      rotation it can be up to sqrt(3) times the volume, which costs a little
      culling accuracy and never correctness.

      aMatrix is applied as aMatrix * point, and is assumed affine (the usual
      model/instance transform); a projective matrix would need a w divide
      that no bounding box can represent anyway. }
    function  Transform(const aMatrix: TpvMatrix4x4): TvgAABB;
  end;

  { TvgCamera: Main camera class }
  TvgCamera = class
  private
    FCriticalSection    : TCriticalSection;

    // --- Position & Orientation ---
    FPosition           : TpvVector3D;
    FTarget             : TpvVector3D;
    FUpVector           : TpvVector3D;

    // --- Projection Parameters ---
    FProjectionType     : TCameraProjectionType;
    FFieldOfView        : Double; // In degrees, for perspective
    FNearPlane          : Double;
    FFarPlane           : Double;
    FAspectRatio        : Double;

    // --- Orthographic Parameters ---
    FOrthLeft           : Double;
    FOrthRight          : Double;
    FOrthTop            : Double;
    FOrthBottom         : Double;

    // --- Cached Matrices ---
    FViewMatrix              : TpvMatrix4x4D;
    FProjectionMatrix        : TpvMatrix4x4D;
    FViewProjectionMatrix    : TpvMatrix4x4D;
    FInverseViewMatrix       : TpvMatrix4x4D;
    FInverseProjectionMatrix : TpvMatrix4x4D;

    // --- Update Tracking ---
    FUpdateFlags: TCameraUpdateFlags;
    FRevision: UInt64;
    FName: string;

    function GetRevision: UInt64;

    // --- Setters with dirty marking ---
    procedure SetPosition(const Value: TpvVector3D);
    procedure SetTarget(const Value: TpvVector3D);
    procedure SetUpVector(const Value: TpvVector3D);
    procedure SetFieldOfView(const Value: Double);
    procedure SetNearPlane(const Value: Double);
    procedure SetFarPlane(const Value: Double);
    procedure SetAspectRatio(const Value: Double);
    procedure SetProjectionType(const Value: TCameraProjectionType);
 //   procedure SetOrthBounds(aLeft, aRight, aTop, aBottom: Double);

    // --- Matrix Builders ---
    procedure RecalculateViewMatrix;
    procedure RecalculateProjectionMatrix;
    procedure RecalculateViewProjectionMatrix;
    procedure InvalidateMatrices(aFlags: TCameraUpdateFlags);

    { Brings every cached matrix up to date.
      CALLER MUST HOLD FCriticalSection. }
    procedure UpdateMatrices;

    { Builds a projection matrix for aAspect into a stack variable, leaving
      FProjectionMatrix, FAspectRatio and FUpdateFlags untouched.
      CALLER MUST HOLD FCriticalSection. }
    function  BuildProjectionForAspect(aAspect: Double): TpvMatrix4x4D;

    { The view matrix for geometry measured from aOrigin instead of from
      (0,0,0): the same rotation, translated by the eye's offset from aOrigin.
      CALLER MUST HOLD FCriticalSection, with the view matrix current. }
    function  BuildViewForOrigin(const aOrigin: TpvVector3D): TpvMatrix4x4D;

    { Places the eye so the box aMin..aMax fills a viewport of aAspect, looking
      along aDirection with aUp as the screen's up.  Shared by every ZoomAll
      entry point; they differ only in where the direction comes from.
      MUST NOT be called holding FCriticalSection - it ends in LookAt and
      SetPerspective/SetOrthographic, which take it themselves. }
    function  FitToBounds(const aMin, aMax, aDirection, aUp: TpvVector3D;
                          aAspect, aMargin: Double): Boolean;

    // --- Helpers ---
    function GetForwardVector: TpvVector3D;
    function GetRightVector: TpvVector3D;
    function GetViewUpVector: TpvVector3D;
    function GetCameraDistance: Double;

  public
    constructor Create;
    destructor Destroy; override;

    // --- Initialization ---
    procedure InitializeAsDefault;
    // glTF camera import lives in Vulkan_LoaderStorer_glTF.TvgSceneLoaderStorer_GLTF
    // (ImportNodeCamera), built against SetPerspective/SetOrthographic/LookAt
    // below rather than as a method here, so this core unit does not need to
    // depend on PasGLTF.
    procedure InitializeFromParameters(const aPosition,
                                             aTarget,
                                             aUpVector: TpvVector3D;
                                            aFOV: Double = CAMERA_DEFAULT_FOV;
                                            aNear: Double = CAMERA_DEFAULT_NEAR;
                                            aFar: Double = CAMERA_DEFAULT_FAR;
                                            aAspect: Double = CAMERA_DEFAULT_ASPECT);

    // --- View Matrix Access (thread-safe) ---
    function GetViewMatrix                  : TpvMatrix4x4D;
    function GetProjectionMatrix            : TpvMatrix4x4D;
    function GetViewProjectionMatrix        : TpvMatrix4x4D;
    function GetInverseViewMatrix           : TpvMatrix4x4D;
    function GetInverseProjectionMatrix     : TpvMatrix4x4D;

    // --- Interactive Controls ---
    { Orbit: Rotate camera around target }
    procedure Orbit(aYaw, aPitch: Double; aUseWorldUp: Boolean = True);

    { Pan: Move camera and target together in local plane }
    procedure Pan(aDeltaX, aDeltaY: Double);

    { Zoom: Move toward/away from target (dolly) }
    procedure Zoom(aDeltaZoom: Double);

    { Dolly: Move forward/backward in camera direction }
    procedure Dolly(aDistance: Double);

    { Look At: Set camera to look at target from position }
    procedure LookAt(const aPosition, aTarget, aUpVector: TpvVector3D);

    { Move: Directly set camera position }
    procedure Move(const aNewPosition: TpvVector3D);

    { Set Target: Directly set look-at target }
    procedure SetLookAtTarget(const aTarget: TpvVector3D);

    // --- Projection utilities ---
    procedure SetPerspective(aFOVDegrees, aAspect, aNear, aFar: Double);
    procedure SetOrthographic(aLeft, aRight, aTop, aBottom, aNear, aFar: Double);

    // --- Zoom to fit ---------------------------------------------------
    // The box these take is in WORLD coordinates and double precision - see
    // TvgScene.GetDataBounds, which produces exactly that.  Do not pass a
    // TvgAABB's corners from a scene with a WorldOrigin: those are local, and
    // adding the origin back in float32 is the rounding WorldOrigin exists
    // to avoid.
    //
    // aAspect is the viewport's width/height.  Pass the value the renderer
    // actually draws with - TvgBaseRenderEngine.GetViewportAspect - not the
    // camera's own stored AspectRatio, or the fit is correct for a window
    // shape nobody is looking at.  AspectRatio is never written by these.
    //
    // aMargin is the fraction of empty space left around the data.
    //
    // All three return False and change nothing when the box is empty
    // (aMax < aMin on any axis), which is what TvgScene.GetDataBounds
    // reports for a scene with no usable bounds.
    //
    // The fit is exact when the box is seen square on - the data touches the
    // margin on whichever screen axis binds.  Seen obliquely it is
    // conservative: the corner furthest out perpendicular to the view may be
    // at the BACK of the box, where perspective shrinks it, so everything is
    // on screen with some margin to spare.  Erring the other way would clip
    // the data, which is the one thing these must not do.

    { Frames all of aMin..aMax without turning the camera: keeps the current
      view direction and up vector, and only moves the eye - and, for an
      orthographic camera, widens the extent. }
    function ZoomAll(const aMin, aMax: TpvVector3D;
                     aAspect: Double;
                     aMargin: Double = CAMERA_DEFAULT_ZOOM_MARGIN): Boolean;

    { The same fit looking straight down the world up axis - a plan view.
      The screen's up becomes vgWorldForward: vgWorldUp is the view direction
      here, and an up vector parallel to the view direction collapses the
      cross products in RecalculateViewMatrix to zero. }
    function ZoomAllLookDown(const aMin, aMax: TpvVector3D;
                             aAspect: Double;
                             aMargin: Double = CAMERA_DEFAULT_ZOOM_MARGIN): Boolean;

    { Fit along a caller-supplied direction, for a named view - front, side,
      an isometric.  aDirection is the way the camera LOOKS, from the eye
      towards the data; it need not be normalised.  aUp is only a hint: the
      part of it along aDirection is removed, so a rough value works.  A caller
      passing an up vector parallel to aDirection gets False rather than a
      view matrix full of NaN. }
    function ZoomAllFromDirection(const aMin, aMax, aDirection, aUp: TpvVector3D;
                                  aAspect: Double;
                                  aMargin: Double = CAMERA_DEFAULT_ZOOM_MARGIN): Boolean;

    { World-space frustum planes of this camera's own projection, i.e. built
      with the stored FAspectRatio.  Indexed by FRUSTUM_PLANE_*.

      For CULLING, prefer GetFrustumPlanesForAspect: a renderer draws with
      GetViewProjectionMatrixForAspect(<its own viewport aspect>), and culling
      against a frustum built from a different aspect ratio will discard
      geometry that is actually on screen. }
    function GetFrustumPlanes : TvgFrustrumPlanes;

    { World-space frustum planes for the projection the caller actually
      renders with.  Pass the same aAspect handed to
      GetViewProjectionMatrixForAspect so the cull volume and the draw agree.
      Does not mutate any cached camera state, so it is safe to call
      concurrently from several renderer threads. }
    function GetFrustumPlanesForAspect(aAspect: Double) : TvgFrustrumPlanes; overload;

    { The same planes in coordinates relative to aOrigin, to cull geometry
      stored relative to it - see TvgScene.WorldOrigin. }
    function GetFrustumPlanesForAspect(aAspect: Double; const aOrigin: TpvVector3D) : TvgFrustrumPlanes; overload;

    { Screen-to-world ray through pixel (aScreenX, aScreenY) of a viewport
      aViewportWidth x aViewportHeight, y = 0 at the top.

      Built from the projection the renderer draws with - the viewport's own
      aspect, see GetViewProjectionMatrixForAspect - so the ray passes through
      whatever is on screen at that pixel even when the camera's stored
      AspectRatio differs from the window's.

      Returns the unit direction.  The overload with aOrigin also returns
      where the ray starts, on the near plane: for a perspective camera that
      is next to Position, but an orthographic camera's rays are parallel and
      start somewhere different for every pixel, so ray-casting code should
      use aOrigin rather than Position. }
    function ScreenToWorldRay(aScreenX, aScreenY: Double; aViewportWidth, aViewportHeight: Double): TpvVector3D; overload;
    function ScreenToWorldRay(aScreenX, aScreenY: Double; aViewportWidth, aViewportHeight: Double;
                              out aOrigin: TpvVector3D): TpvVector3D; overload;

    { World-to-screen projection: the inverse of ScreenToWorldRay.  Returns
      the pixel in x, y (y = 0 at the top) and the NDC depth in z. }
    function WorldToScreenPoint(const aWorldPoint: TpvVector3D; aViewportWidth, aViewportHeight: Double): TpvVector3D;

{ Returns VP matrix computed with aAspect substituted for FAspectRatio.
       Does NOT mutate FAspectRatio, FProjectionMatrix, or FUpdateFlags.
       Safe to call simultaneously from multiple renderer threads. }
    function GetViewProjectionMatrixForAspect(aAspect: Double): TpvMatrix4x4D; overload;

    { For geometry stored relative to aOrigin (see TvgScene.WorldOrigin): maps
      a LOCAL position to clip space.  Equivalent to
      Projection * View * Translate(aOrigin), but the eye's offset from the
      origin is taken before it enters the matrix, so a camera and data at
      survey coordinates produce only small translation terms - small enough
      that the result survives narrowing to a float32 mat4. }
    function GetViewProjectionMatrixForAspect(aAspect: Double; const aOrigin: TpvVector3D): TpvMatrix4x4D; overload;

    // --- Properties ---
    property Position: TpvVector3D read FPosition write SetPosition;
    property Target: TpvVector3D read FTarget write SetTarget;
    property UpVector: TpvVector3D read FUpVector write SetUpVector;

    property ProjectionType: TCameraProjectionType read FProjectionType write SetProjectionType;
    property FieldOfView: Double read FFieldOfView write SetFieldOfView;
    property NearPlane: Double read FNearPlane write SetNearPlane;
    property FarPlane: Double read FFarPlane write SetFarPlane;
    property AspectRatio: Double read FAspectRatio write SetAspectRatio;

    property OrthLeft: Double read FOrthLeft;
    property OrthRight: Double read FOrthRight;
    property OrthTop: Double read FOrthTop;
    property OrthBottom: Double read FOrthBottom;

    property ForwardVector: TpvVector3D read GetForwardVector;
    property RightVector: TpvVector3D read GetRightVector;
    { The screen's up direction in the world: at right angles to the view
      and to RightVector, so it tilts as the camera pitches.  UpVector is
      the reference the camera orbits about, and stays put. }
    property ViewUpVector: TpvVector3D read GetViewUpVector;
    property Distance: Double read GetCameraDistance;
    { Bumped whenever view or projection inputs change.  Used by the HUD
      frame path to treat camera motion as a scene rebuild. }
    property Revision: UInt64 read GetRevision;

    property Name: string read FName write FName;
  end;

  { Helper: Camera manager for a scene }
  TvgCameraManager = class
  private
    FCameras         : TObjectDictionary<string, TvgCamera>;
    FActiveCamera    : TvgCamera;
    FCriticalSection : TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    Procedure AddBaseCamera(aName:String);
    //Only adds a camera if none exist

    procedure AddCamera(const aName: string; aCamera: TvgCamera);
    function GetCamera(const aName: string): TvgCamera;
    procedure RemoveCamera(const aName: string);
    function GetCameraCount: Integer;

    procedure SetActiveCamera(const aName: string);
    function GetActiveCamera: TvgCamera;

    Procedure SetAspectRatio(aWidth, aHeight :Integer);

    procedure ClearAll;
  end;

{ Reports whether aProjection maps the near plane to z_ndc = 0 (the Vulkan
  convention) or to z_ndc = -1 (the OpenGL convention).  See the body for why
  this is probed rather than assumed. }
function vgProjectionIsZeroToOneDepth(const aProjection: TpvMatrix4x4D;
                                            aNearPlane : Double): Boolean;

{ Standard Gribb/Hartmann frustum plane extraction from a combined
  view-projection matrix, returning planes indexed by FRUSTUM_PLANE_*.
  Use vgProjectionIsZeroToOneDepth to decide aZeroToOneDepth. }
function vgExtractFrustumPlanes(const aVP: TpvMatrix4x4D;
                                      aZeroToOneDepth: Boolean): TvgFrustrumPlanes;

{ True if aBox might be visible inside aFrustum, False only when it is
  definitely outside and can be skipped.

  Conservative by design and in one direction only: it can return True for a
  box that turns out to be off screen (which merely wastes a draw), and must
  never return False for one that is on screen (which would make geometry
  disappear).  An empty box therefore tests as visible - a caller that has no
  bounds for an object has to draw it.

  aFrustum's planes must be normalised, which vgExtractFrustumPlanes
  guarantees; the test compares a plane distance against a box extent, so
  unnormalised planes would reject visible geometry. }
function vgFrustumTestAABB(const aFrustum: TvgFrustrumPlanes;
                           const aBox    : TvgAABB): Boolean;

implementation

{ Reports whether aProjection maps the near plane to z_ndc = 0 (the Vulkan
  convention) or to z_ndc = -1 (the OpenGL convention), by projecting a point
  that sits exactly on the near plane and looking at where it lands.

  This is probed rather than assumed because the projections built in this
  unit are NOT consistent: the perspective path produces -1..1 while the
  orthographic path produces 0..1.  Probing keeps frustum extraction correct
  either way, and keeps it correct if that inconsistency is resolved later. }
function vgProjectionIsZeroToOneDepth(const aProjection: TpvMatrix4x4D;
                                            aNearPlane : Double): Boolean;
var
  NearPoint : TpvVector4D;
begin
  // Eye space looks down -Z, so the near plane sits at z = -aNearPlane.
  NearPoint := aProjection * TpvVector4D.Create(0, 0, -aNearPlane, 1);

  if SameValue(NearPoint.w, 0.0) then
  begin
    // Degenerate projection; assume the Vulkan convention rather than divide.
    Result := True;
    Exit;
  end;

  // z_ndc is ~0 for a 0..1 clip volume and ~-1 for a -1..1 one, so the
  // midpoint -0.5 separates them with plenty of margin for FP error.
  Result := (NearPoint.z / NearPoint.w) > -0.5;
end;

{ Standard Gribb/Hartmann plane extraction from a combined view-projection
  matrix, returning planes indexed by FRUSTUM_PLANE_*.

  aZeroToOneDepth selects the near-plane clip bound: the Vulkan convention
  clips at z_clip >= 0, the OpenGL one at z_clip >= -w_clip.  Use
  vgProjectionIsZeroToOneDepth to decide.

  Rows, not columns: aVP is used with the column-vector convention
  (clip := aVP * world), so each clip-space bound comes from a ROW of aVP.
  TpvMatrix4x4D stores column-major - RawComponents[c,r] - so indexing it as
  [row,col] silently extracts the planes of the TRANSPOSED matrix.
  TpvMatrix4x4 has a Rows[] property that hides this; TpvMatrix4x4D does not,
  so MatrixRow below reads the row out explicitly. }
function vgExtractFrustumPlanes(const aVP: TpvMatrix4x4D;
                                      aZeroToOneDepth: Boolean): TvgFrustrumPlanes;

  function MatrixRow(aRow: Integer): TpvVector4D;
  begin
    Result := TpvVector4D.Create(aVP.RawComponents[0, aRow],
                                 aVP.RawComponents[1, aRow],
                                 aVP.RawComponents[2, aRow],
                                 aVP.RawComponents[3, aRow]);
  end;

var
  RowX, RowY, RowZ, RowW : TpvVector4D;
  I      : Integer;
  Len    : Double;

begin
  RowX := MatrixRow(0);
  RowY := MatrixRow(1);
  RowZ := MatrixRow(2);
  RowW := MatrixRow(3);

  // -w <= x <= w   ->  inside when (w + x) >= 0 and (w - x) >= 0
  Result.Planes[FRUSTUM_PLANE_LEFT]   := RowW + RowX;
  Result.Planes[FRUSTUM_PLANE_RIGHT]  := RowW - RowX;

  // -w <= y <= w
  Result.Planes[FRUSTUM_PLANE_BOTTOM] := RowW + RowY;
  Result.Planes[FRUSTUM_PLANE_TOP]    := RowW - RowY;

  // Near bound differs by depth convention; the far bound (z <= w) does not.
  if aZeroToOneDepth then
    Result.Planes[FRUSTUM_PLANE_NEAR] := RowZ            // 0 <= z
  else
    Result.Planes[FRUSTUM_PLANE_NEAR] := RowW + RowZ;    // -w <= z

  Result.Planes[FRUSTUM_PLANE_FAR]    := RowW - RowZ;

  // Normalise by the length of the NORMAL (xyz) only.
  //
  // TpvVector4D.Normalize divides by the length of all four components, which
  // leaves the plane geometrically correct - any uniform scale preserves the
  // sign of A*x+B*y+C*z+D - but destroys the magnitude.  Culling tests compare
  // that value against a bounding volume's radius, so it has to be a real
  // distance, which means scaling by 1/|(A,B,C)|.
  for I := 0 to 5 do
  begin
    Len := Sqrt(Sqr(Result.Planes[I].x) +
                Sqr(Result.Planes[I].y) +
                Sqr(Result.Planes[I].z));

    if Len > 1e-12 then
    begin
      Result.Planes[I].x := Result.Planes[I].x / Len;
      Result.Planes[I].y := Result.Planes[I].y / Len;
      Result.Planes[I].z := Result.Planes[I].z / Len;
      Result.Planes[I].w := Result.Planes[I].w / Len;
    end;
    // A zero-length normal means a degenerate projection (a zero FOV or an
    // empty ortho box).  Leaving the plane as-is keeps the result finite;
    // every point then tests as inside it, which fails safe by drawing.
  end;
end;

{ ============================================================================ }
{ TvgAABB                                                                      }
{ ============================================================================ }

procedure TvgAABB.Reset;
begin
  Min   := TpvVector3.Create(0, 0, 0);
  Max   := TpvVector3.Create(0, 0, 0);
  Valid := False;
end;

procedure TvgAABB.GrowPoint(const aPoint: TpvVector3);
begin
  if Valid then
  begin
    Min := Min.Min(aPoint);   // component-wise
    Max := Max.Max(aPoint);
  end
  else
  begin
    Min   := aPoint;
    Max   := aPoint;
    Valid := True;
  end;
end;

procedure TvgAABB.GrowPoint(aX, aY, aZ: Single);
begin
  GrowPoint(TpvVector3.Create(aX, aY, aZ));
end;

procedure TvgAABB.GrowAABB(const aBox: TvgAABB);
begin
  if not aBox.Valid then Exit;   // nothing to add

  if Valid then
  begin
    Min := Min.Min(aBox.Min);
    Max := Max.Max(aBox.Max);
  end
  else
  begin
    Self := aBox;
  end;
end;

procedure TvgAABB.SetBounds(const aMin, aMax: TpvVector3);
begin
  // Order the components rather than trusting the caller, so a box passed in
  // with its corners swapped does not come out inside-out and cull wrongly.
  Min   := aMin.Min(aMax);
  Max   := aMin.Max(aMax);
  Valid := True;
end;

function TvgAABB.Centre: TpvVector3;
begin
  Result := (Min + Max) * 0.5;
end;

function TvgAABB.Extents: TpvVector3;
begin
  Result := (Max - Min) * 0.5;
end;

function TvgAABB.Size: TpvVector3;
begin
  if Valid then
    Result := Max - Min
  else
    Result := TpvVector3.Create(0, 0, 0);
end;

function TvgAABB.Radius: Single;
begin
  if Valid then
    Result := Extents.Length
  else
    Result := 0.0;
end;

function TvgAABB.Transform(const aMatrix: TpvMatrix4x4): TvgAABB;
var
  C, E : TpvVector3;
  TC   : TpvVector4;
begin
  if not Valid then
  begin
    Result.Reset;
    Exit;
  end;

  C := Centre;
  E := Extents;

  // Centre goes through the full transform (rotation, scale AND translation).
  TC := aMatrix * TpvVector4.Create(C.x, C.y, C.z, 1.0);

  // Extents go through the absolute value of the 3x3 basis only: translation
  // must not move a half-size, and the absolute value is what makes the
  // result enclose the rotated box rather than slice through it.
  E := aMatrix.MulAbsBasis(E);

  Result.Min   := TpvVector3.Create(TC.x - E.x, TC.y - E.y, TC.z - E.z);
  Result.Max   := TpvVector3.Create(TC.x + E.x, TC.y + E.y, TC.z + E.z);
  Result.Valid := True;
end;

{ ============================================================================ }
{ Frustum / AABB intersection                                                  }
{ ============================================================================ }

function vgFrustumTestAABB(const aFrustum: TvgFrustrumPlanes;
                           const aBox    : TvgAABB): Boolean;
var
  C, E : TpvVector3D;
  I    : Integer;
  D, R : Double;
  N    : TpvVector4D;
begin
  // No bounds means no basis on which to reject it - draw it.
  if not aBox.Valid then
    Exit(True);

  C := aBox.Centre;
  E := aBox.Extents;

  for I := 0 to 5 do
  begin
    N := aFrustum.Planes[I];

    // Signed distance from the box centre to the plane.  Positive is inside,
    // because the plane normals point into the frustum.
    D := (N.x * C.x) + (N.y * C.y) + (N.z * C.z) + N.w;

    // How far the box can reach towards the plane from its centre: the
    // extent projected onto the plane normal.  Using abs(N) with the extents
    // picks whichever corner is furthest out without testing all eight.
    R := (System.Abs(N.x) * E.x) +
         (System.Abs(N.y) * E.y) +
         (System.Abs(N.z) * E.z);

    // Even the nearest corner is on the outside of this plane, so the whole
    // box is - one plane is enough to reject.
    if D < -R then
      Exit(False);
  end;

  // Inside, or straddling a plane.  Note this can also return True for a box
  // in one of the corner regions outside two planes but outside neither one
  // on its own; that is the known false positive of plane-by-plane testing
  // and costs a draw, never a missing object.
  Result := True;
end;

{ ============================================================================ }
{ TvgCamera Implementation                                                    }
{ ============================================================================ }

constructor TvgCamera.Create;
begin
  inherited Create;
  FCriticalSection := TCriticalSection.Create;

  // The defaults below depend on the world axis convention, so hold it fixed
  // for as long as this camera lives.
  vgRetainAxisConvention;

  // Back from the origin, looking at it horizontally.  Both position and up
  // follow the convention: moving only the up vector would leave a Z-up
  // camera looking straight along its own up axis.
  FPosition        := vgFromYUp(0, 0, 5);
  FTarget          := TpvVector3D.Create(0, 0, 0);
  FUpVector        := vgWorldUp;

  FProjectionType := ptPerspective;
  FFieldOfView    := CAMERA_DEFAULT_FOV;
  FNearPlane      := CAMERA_DEFAULT_NEAR;
  FFarPlane       := CAMERA_DEFAULT_FAR;
  FAspectRatio    := CAMERA_DEFAULT_ASPECT;

  FOrthLeft       := -1.0;
  FOrthRight      := 1.0;
  FOrthTop        := 1.0;
  FOrthBottom     := -1.0;

  FUpdateFlags    := [cfViewDirty, cfProjectionDirty, cfFrustumDirty];
  FRevision       := 1;

  FName           := 'Camera_' + IntToStr(Integer(Self));

  RecalculateViewMatrix;
  RecalculateProjectionMatrix;
  RecalculateViewProjectionMatrix;
end;

destructor TvgCamera.Destroy;
begin
  FCriticalSection.Free;
  vgReleaseAxisConvention;
  inherited Destroy;
end;

procedure TvgCamera.InitializeAsDefault;
begin
  LookAt(
    vgFromYUp(0, 2, 5),
    TpvVector3D.Create(0, 0, 0),
    vgWorldUp
  );
  SetPerspective(CAMERA_DEFAULT_FOV, CAMERA_DEFAULT_ASPECT, CAMERA_DEFAULT_NEAR, CAMERA_DEFAULT_FAR);
end;
procedure TvgCamera.InitializeFromParameters(const aPosition, aTarget, aUpVector: TpvVector3D;
  aFOV: Double; aNear: Double; aFar: Double; aAspect: Double);
begin
  LookAt(aPosition, aTarget, aUpVector);
  SetPerspective(aFOV, aAspect, aNear, aFar);
end;

Function Vec_Equals(Vec1, Vec2:TpvVector3D):Boolean;
Begin
  Result := False;
  If IsZero(Vec1.x-vec2.x) and
     IsZero(Vec1.y-vec2.y) and
     IsZero(Vec1.z-vec2.z) then result := True;
End;

procedure TvgCamera.SetPosition(const Value: TpvVector3D);
begin
  FCriticalSection.Enter;
  try
    if not Vec_Equals(fPosition, Value) then
    begin
      FPosition := Value;
      InvalidateMatrices([cfViewDirty, cfFrustumDirty]);
    end;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.SetTarget(const Value: TpvVector3D);
begin
  FCriticalSection.Enter;
  try
    if not Vec_Equals(FTarget, Value) then
    begin
      FTarget := Value;
      InvalidateMatrices([cfViewDirty, cfFrustumDirty]);
    end;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.SetUpVector(const Value: TpvVector3D);
begin
  FCriticalSection.Enter;
  try
    if not Vec_Equals(FUpVector, Value) then
    begin
      FUpVector := Value.Normalize;
      InvalidateMatrices([cfViewDirty, cfFrustumDirty]);
    end;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.SetFieldOfView(const Value: Double);
begin
  FCriticalSection.Enter;
  try
    if not SameValue(FFieldOfView, Value) then
    begin
      FFieldOfView := EnsureRange(Value, 1.0, 179.0);
      InvalidateMatrices([cfProjectionDirty, cfFrustumDirty]);
    end;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.SetNearPlane(const Value: Double);
begin
  FCriticalSection.Enter;
  try
    if not SameValue(FNearPlane, Value) then
    begin
      FNearPlane := Max(0.0001, Value);
      if FNearPlane >= FFarPlane then
        FFarPlane := FNearPlane * 2;
      InvalidateMatrices([cfProjectionDirty, cfFrustumDirty]);
    end;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.SetFarPlane(const Value: Double);
begin
  FCriticalSection.Enter;
  try
    if not SameValue(FFarPlane, Value) then
    begin
      FFarPlane := Max(FNearPlane + 0.1, Value);
      InvalidateMatrices([cfProjectionDirty, cfFrustumDirty]);
    end;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.SetAspectRatio(const Value: Double);
begin
  FCriticalSection.Enter;
  try
    if not SameValue(FAspectRatio, Value) then
    begin
      FAspectRatio := Max(0.1, Value);
      InvalidateMatrices([cfProjectionDirty, cfFrustumDirty]);
    end;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.SetProjectionType(const Value: TCameraProjectionType);
begin
  FCriticalSection.Enter;
  try
    if FProjectionType <> Value then
    begin
      FProjectionType := Value;
      InvalidateMatrices([cfProjectionDirty, cfFrustumDirty]);
    end;
  finally
    FCriticalSection.Leave;
  end;
end;
(*
procedure TvgCamera.SetOrthBounds(aLeft, aRight, aTop, aBottom: Double);
begin
  FCriticalSection.Enter;
  try
    FOrthLeft := aLeft;
    FOrthRight := aRight;
    FOrthTop := aTop;
    FOrthBottom := aBottom;
    InvalidateMatrices([cfProjectionDirty, cfFrustumDirty]);
  finally
    FCriticalSection.Leave;
  end;
end;
*)
procedure TvgCamera.InvalidateMatrices(aFlags: TCameraUpdateFlags);
begin
  FUpdateFlags := FUpdateFlags + aFlags;
  Inc(FRevision);
end;

function TvgCamera.GetRevision: UInt64;
begin
  FCriticalSection.Enter;
  try
    Result := FRevision;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.RecalculateViewMatrix;
var
  zaxis, xaxis, yaxis: TpvVector3D;
begin
  // Standard LookAt matrix (RH coordinate system, Vulkan-style)
  zaxis := (FPosition - FTarget).Normalize;
  xaxis := FUpVector.Cross(zaxis).Normalize;
  yaxis := zaxis.Cross(xaxis).Normalize;

  FViewMatrix.Columns[0] := TpvVector4D.Create(xaxis.X, yaxis.X, zaxis.X, 0);
  FViewMatrix.Columns[1] := TpvVector4D.Create(xaxis.Y, yaxis.Y, zaxis.Y, 0);
  FViewMatrix.Columns[2] := TpvVector4D.Create(xaxis.Z, yaxis.Z, zaxis.Z, 0);
  FViewMatrix.Columns[3] := TpvVector4D.Create(-xaxis.Dot(FPosition),
                                             -yaxis.Dot(FPosition),
                                             -zaxis.Dot(FPosition),  1 );

  // The inverse of a rigid transform, written down rather than computed:
  // the camera's axes are its columns and its position the translation.
  // A general Inverse would divide cofactors made of these million-unit
  // translations by the determinant, and throw away digits doing it.
  FInverseViewMatrix.Columns[0] := TpvVector4D.Create(xaxis.X, xaxis.Y, xaxis.Z, 0);
  FInverseViewMatrix.Columns[1] := TpvVector4D.Create(yaxis.X, yaxis.Y, yaxis.Z, 0);
  FInverseViewMatrix.Columns[2] := TpvVector4D.Create(zaxis.X, zaxis.Y, zaxis.Z, 0);
  FInverseViewMatrix.Columns[3] := TpvVector4D.Create(FPosition.X, FPosition.Y, FPosition.Z, 1);

  Exclude(FUpdateFlags, cfViewDirty);
  Include(FUpdateFlags, cfViewProjectionDirty);
end;

procedure TvgCamera.RecalculateProjectionMatrix;
var
  fovy, f, invDepth: Double;
begin
  case FProjectionType of
    ptPerspective:
    begin
      fovy := DegToRad(FFieldOfView) / 2;
      f := Cos(fovy) / Sin(fovy);
      invDepth := 1.0 / (FNearPlane - FFarPlane);

      FProjectionMatrix := TpvMatrix4x4D.Create(
        f / FAspectRatio, 0, 0, 0,
        0, f, 0, 0,
        0, 0, (FFarPlane + FNearPlane) * invDepth, -1,
        0, 0, 2 * FFarPlane * FNearPlane * invDepth, 0
      );
    end;

    ptOrthographic:
    begin
      invDepth := 1.0 / (FNearPlane - FFarPlane);

      FProjectionMatrix := TpvMatrix4x4D.Create(
        2 / (FOrthRight - FOrthLeft), 0, 0, 0,
        0, 2 / (FOrthTop - FOrthBottom), 0, 0,
        0, 0, invDepth, 0,
        -(FOrthRight + FOrthLeft) / (FOrthRight - FOrthLeft),
        -(FOrthTop + FOrthBottom) / (FOrthTop - FOrthBottom),
        FNearPlane * invDepth,
        1
      );
    end;
  end;

  FInverseProjectionMatrix := FProjectionMatrix.Inverse;
  Exclude(FUpdateFlags, cfProjectionDirty);
  Include(FUpdateFlags, cfViewProjectionDirty);
end;

procedure TvgCamera.RecalculateViewProjectionMatrix;
begin
  // Operand order looks backwards but is not: TpvMatrix4x4D's '*' multiplies
  // the RAW (column-major) arrays as if they were row-major, so 'A * B'
  // evaluates to B*A in normal matrix notation.  'View * Projection' is
  // therefore the one that yields Projection*View, i.e. the matrix a shader
  // applies as clip := VP * vec4(worldPos, 1).
  //
  // This matches PasVulkan's own convention - see TpvFrustum.Init in
  // PasVulkan.Frustum.pas, which builds aViewMatrix*aProjectionMatrix.
  FViewProjectionMatrix := FViewMatrix * FProjectionMatrix;
  Exclude(FUpdateFlags, cfViewProjectionDirty);
end;

procedure TvgCamera.UpdateMatrices;
begin
  // The getters used to rebuild the view or projection first - which clears
  // its dirty flag - and then test those same flags to decide whether the
  // product needed rebuilding.  It never did, so FViewProjectionMatrix stayed
  // whatever the constructor built.  cfViewProjectionDirty records it instead.
  if cfViewDirty in FUpdateFlags then
    RecalculateViewMatrix;
  if cfProjectionDirty in FUpdateFlags then
    RecalculateProjectionMatrix;
  if cfViewProjectionDirty in FUpdateFlags then
    RecalculateViewProjectionMatrix;
end;

function TvgCamera.GetViewMatrix: TpvMatrix4x4D;
begin
  FCriticalSection.Enter;
  try
    UpdateMatrices;
    Result := FViewMatrix;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetProjectionMatrix: TpvMatrix4x4D;
begin
  FCriticalSection.Enter;
  try
    UpdateMatrices;
    Result := FProjectionMatrix;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetViewProjectionMatrix: TpvMatrix4x4D;
begin
  FCriticalSection.Enter;
  try
    UpdateMatrices;
    Result := FViewProjectionMatrix;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.BuildProjectionForAspect(aAspect: Double): TpvMatrix4x4D;
var
  fovy, f    : Double;
  invDepth   : Double;
begin
  // This is identical to RecalculateProjectionMatrix but returns a stack
  // value, leaving FProjectionMatrix, FAspectRatio and FUpdateFlags alone.
  // Caller holds FCriticalSection.

  // Guard against a bad viewport.  Applied to BOTH projection types: the
  // orthographic path divides by halfH * aAspect, so a zero aspect is a hard
  // divide-by-zero there rather than merely a wrong-looking image.
  if aAspect <= 0 then aAspect := 1.0;

  case FProjectionType of

    ptPerspective:
    begin
      fovy     := DegToRad(FFieldOfView) / 2;
      f        := Cos(fovy) / Sin(fovy);
      invDepth := 1.0 / (FNearPlane - FFarPlane);

      Result := TpvMatrix4x4D.Create(
        f / aAspect,  0,  0,  0,
        0,            -f, 0,  0,    // negated Y for Vulkan clip space
        0,            0,  (FFarPlane + FNearPlane) * invDepth, -1,
        0,            0,  2 * FFarPlane * FNearPlane * invDepth, 0
      );
    end;

    ptOrthographic:
    begin
      // For ortho the caller's aspect scales the horizontal extent;
      // we derive new left/right bounds while preserving the stored height.
      var halfH : Double := (FOrthTop - FOrthBottom) * 0.5;

      // An empty ortho box would divide by zero below.  Fall back to a unit
      // box so the caller gets a usable matrix instead of an exception.
      if SameValue(halfH, 0.0) then halfH := 1.0;

      var halfW : Double := halfH * aAspect;
      invDepth := 1.0 / (FNearPlane - FFarPlane);

      // Y negated for Vulkan clip space, as in the perspective branch.  It
      // was not, so an orthographic camera drew upside down compared with a
      // perspective one looking the same way.
      Result := TpvMatrix4x4D.Create(
        1 / halfW,  0,          0,          0,
        0,          -1 / halfH, 0,          0,
        0,          0,          invDepth,   0,
        0,          0,          FNearPlane * invDepth, 1
      );
    end;

  else
    // TpvMatrix4x4D has no Identity constant.
    Result := TpvMatrix4x4D.Create(1, 0, 0, 0,
                                   0, 1, 0, 0,
                                   0, 0, 1, 0,
                                   0, 0, 0, 1);
  end;
end;

function TvgCamera.BuildViewForOrigin(const aOrigin: TpvVector3D): TpvMatrix4x4D;
var
  Eye : TpvVector3D;
  R   : Integer;
begin
  // Rows 0..2 of the rotation are the camera's axes, and the translation is
  // minus each axis dotted with the eye - the same arithmetic as
  // RecalculateViewMatrix, so an origin of (0,0,0) reproduces FViewMatrix
  // exactly.  Subtracting the origin FIRST is the point: the eye and the
  // origin are both survey-sized and nearly equal, and their difference is
  // exact in double, where the matrix product View * Translate(aOrigin)
  // would add and cancel million-unit terms.
  Result := FViewMatrix;
  Eye    := FPosition - aOrigin;
  for R := 0 to 2 do
    Result.RawComponents[3, R] := -((Result.RawComponents[0, R] * Eye.x) +
                                    (Result.RawComponents[1, R] * Eye.y) +
                                    (Result.RawComponents[2, R] * Eye.z));
end;

function TvgCamera.GetViewProjectionMatrixForAspect(aAspect: Double): TpvMatrix4x4D;
begin
  Result := GetViewProjectionMatrixForAspect(aAspect, TpvVector3D.Create(0, 0, 0));
end;

function TvgCamera.GetViewProjectionMatrixForAspect(aAspect: Double; const aOrigin: TpvVector3D): TpvMatrix4x4D;
var
  LocalProj  : TpvMatrix4x4D;
begin
  FCriticalSection.Enter;
  try
    // 1. Rebuild the view matrix if dirty (normal lazy path)
    if cfViewDirty in FUpdateFlags then
      RecalculateViewMatrix;

    // 2. Build a projection for the caller's aspect, touching no cached state
    LocalProj := BuildProjectionForAspect(aAspect);

    // 3. VP = Proj*View - see RecalculateViewProjectionMatrix for why that is
    //    spelled View * Proj with TpvMatrix4x4D's reversed '*'.
    Result := BuildViewForOrigin(aOrigin) * LocalProj;

  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetInverseViewMatrix: TpvMatrix4x4D;
begin
  FCriticalSection.Enter;
  try
    if cfViewDirty in FUpdateFlags then
      RecalculateViewMatrix;
    Result := FInverseViewMatrix;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetInverseProjectionMatrix: TpvMatrix4x4D;
begin
  FCriticalSection.Enter;
  try
    if cfProjectionDirty in FUpdateFlags then
      RecalculateProjectionMatrix;
    Result := FInverseProjectionMatrix;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetForwardVector: TpvVector3D;
begin
  FCriticalSection.Enter;
  try
    Result := (FTarget - FPosition).Normalize;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetRightVector: TpvVector3D;
begin
  FCriticalSection.Enter;
  try
    Result := ForwardVector.Cross(FUpVector).Normalize;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetViewUpVector: TpvVector3D;
begin
  FCriticalSection.Enter;
  try
    Result := RightVector.Cross(ForwardVector).Normalize;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetCameraDistance: Double;
begin
  FCriticalSection.Enter;
  try
    Result := (FTarget - FPosition).Length;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.LookAt(const aPosition, aTarget, aUpVector: TpvVector3D);
begin
  FCriticalSection.Enter;
  try
    FPosition := aPosition;
    FTarget := aTarget;
    FUpVector := aUpVector.Normalize;
    InvalidateMatrices([cfViewDirty, cfFrustumDirty]);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.Move(const aNewPosition: TpvVector3D);
begin
  Position := aNewPosition;
end;

procedure TvgCamera.SetLookAtTarget(const aTarget: TpvVector3D);
begin
  Target := aTarget;
end;

procedure TvgCamera.Orbit(aYaw, aPitch: Double; aUseWorldUp: Boolean = True);
const
  // Degrees above or below the target the eye may reach.  At 90 the view
  // direction lines up with FUpVector, the cross products that build the view
  // matrix collapse to zero, and the matrix fills with NaN.
  MAX_ELEVATION = 89.0;
var
  direction: TpvVector3D;
  distance: Double;
  elevation: Double;
  cosYaw, sinYaw, cosPitch, sinPitch: Double;
  newDir: TpvVector3D;
  right, up: TpvVector3D;
begin
  FCriticalSection.Enter;
  try
    distance := (FPosition - FTarget).Length;
    if distance < 0.01 then distance := 0.01;

    direction := (FPosition - FTarget).Normalize;

    if aUseWorldUp then
    begin
      right := FUpVector.Cross(direction).Normalize;
      up := direction.Cross(right).Normalize;

      // up leans towards FUpVector, so positive pitch raises the eye.  Trim
      // the pitch so the eye stops short of the pole instead of passing it.
      elevation := RadToDeg(ArcSin(EnsureRange(direction.Dot(FUpVector), -1.0, 1.0)));
      aPitch := EnsureRange(elevation + aPitch, -MAX_ELEVATION, MAX_ELEVATION) - elevation;
    end
    else
    begin
      right := RightVector;
      up := ForwardVector.Cross(right).Normalize;
    end;

    // Apply pitch (rotation around right axis)
    cosPitch := Cos(DegToRad(aPitch));
    sinPitch := Sin(DegToRad(aPitch));
    newDir := direction * cosPitch + up * sinPitch;

    // Apply yaw: rotate about world up (Rodrigues).  The last term keeps the
    // part of newDir along the up axis, so yawing never changes the eye's
    // height above the target.
    cosYaw := Cos(DegToRad(aYaw));
    sinYaw := Sin(DegToRad(aYaw));
    direction := newDir * cosYaw +
                 FUpVector.Cross(newDir) * sinYaw +
                 FUpVector * (FUpVector.Dot(newDir) * (1.0 - cosYaw));

    FPosition := FTarget + direction * distance;
    InvalidateMatrices([cfViewDirty, cfFrustumDirty]);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.Pan(aDeltaX, aDeltaY: Double);
var
  right, up: TpvVector3D;
  panAmount: Double;
begin
  FCriticalSection.Enter;
  try
    panAmount := Distance * 0.01; // Pan speed relative to distance
    right := RightVector;
    up := FUpVector;

    FPosition := FPosition + right * aDeltaX * panAmount - up * aDeltaY * panAmount;
    FTarget := FTarget + right * aDeltaX * panAmount - up * aDeltaY * panAmount;
    InvalidateMatrices([cfViewDirty, cfFrustumDirty]);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.Zoom(aDeltaZoom: Double);
var
  distance: Double;
  newDistance: Double;
begin
  FCriticalSection.Enter;
  try
    // Not 'distance := Distance': the local variable hides the property, so
    // that line read the uninitialised local back into itself.
    distance := (FPosition - FTarget).Length;
    newDistance := distance * (1.0 - aDeltaZoom * 0.1);
    newDistance := EnsureRange(newDistance, 0.1, 100000.0);

    FPosition := FTarget + (FPosition - FTarget).Normalize * newDistance;
    InvalidateMatrices([cfViewDirty, cfFrustumDirty]);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.Dolly(aDistance: Double);
begin
  FCriticalSection.Enter;
  try
    FPosition := FPosition + ForwardVector * aDistance;
    InvalidateMatrices([cfViewDirty, cfFrustumDirty]);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.SetPerspective(aFOVDegrees, aAspect, aNear, aFar: Double);
begin
  FCriticalSection.Enter;
  try
    FProjectionType := ptPerspective;
    FFieldOfView := EnsureRange(aFOVDegrees, 1.0, 179.0);
    FAspectRatio := Max(0.1, aAspect);
    FNearPlane := Max(0.0001, aNear);
    FFarPlane := Max(FNearPlane + 0.1, aFar);
    InvalidateMatrices([cfProjectionDirty, cfFrustumDirty]);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.SetOrthographic(aLeft, aRight, aTop, aBottom, aNear, aFar: Double);
begin
  FCriticalSection.Enter;
  try
    FProjectionType := ptOrthographic;
    FOrthLeft := aLeft;
    FOrthRight := aRight;
    FOrthTop := aTop;
    FOrthBottom := aBottom;
    FNearPlane := Max(0.0001, aNear);
    FFarPlane := Max(FNearPlane + 0.1, aFar);
    InvalidateMatrices([cfProjectionDirty, cfFrustumDirty]);
  finally
    FCriticalSection.Leave;
  end;
end;

{ ---------------------------------------------------------------------------
  Zoom to fit
  --------------------------------------------------------------------------- }

function TvgCamera.FitToBounds(const aMin, aMax, aDirection, aUp: TpvVector3D;
                               aAspect, aMargin: Double): Boolean;
const
  // Below this the basis vectors are not usable: an up vector parallel to the
  // view direction, or a box with no size at all.
  FIT_EPSILON = 1.0e-9;

  // How much of the way to the nearest data the near plane is placed.  The
  // near plane only has to clear the front of the box, so anything below 1
  // works; 0.05 leaves about 20x of room to dolly in afterwards before
  // geometry starts clipping, while keeping far/near near 10^2 for a survey-
  // sized dataset.  Leaving it at CAMERA_DEFAULT_NEAR (0.01) instead would
  // give such a scene a depth ratio around 10^8 and z-fighting throughout.
  NEAR_FRACTION = 0.05;
var
  ProjType     : TCameraProjectionType;
  FOV          : Double;
  C, F, R, U   : TpvVector3D;
  Corner, D    : TpvVector3D;
  halfW,
  halfH,
  halfD        : Double;
  Scale, MinExt: Double;
  T, Dist,
  Pad,
  NearP, FarP  : Double;
  Eye          : TpvVector3D;
  I            : Integer;
begin
  Result := False;

  // An empty box is the caller's "there is no data" answer - see
  // TvgScene.GetDataBounds - and must not move the camera.
  if (aMax.x < aMin.x) or (aMax.y < aMin.y) or (aMax.z < aMin.z) then
    Exit;

  // A viewport of zero or negative width/height is a window that has not been
  // sized yet; square is the same safe default GetViewportAspect uses.
  if aAspect <= 0 then
    aAspect := 1.0;

  // The whole promise of this call is that every point is on screen, so a
  // margin that would crop the data is refused rather than honoured.
  aMargin := Max(1.0, aMargin);

  // Orthonormal camera basis.  U is re-derived from R and F rather than used
  // as given, so a caller may pass a rough up vector - anything not parallel
  // to the direction - and still get a level horizon.
  F := aDirection;
  if F.Length < FIT_EPSILON then Exit;
  F := F.Normalize;

  R := F.Cross(aUp);
  if R.Length < FIT_EPSILON then Exit;   // up parallel to the view direction
  R := R.Normalize;

  U := R.Cross(F).Normalize;

  C := (aMin + aMax) * 0.5;

  // Half-size of the box measured along each camera axis.  Taken over all
  // eight corners rather than from the extents, so the same code would still
  // be right if the box ever stopped being axis aligned.
  halfW := 0;
  halfH := 0;
  halfD := 0;
  for I := 0 to 7 do
  begin
    if (I and 1) = 0 then Corner.x := aMin.x else Corner.x := aMax.x;
    if (I and 2) = 0 then Corner.y := aMin.y else Corner.y := aMax.y;
    if (I and 4) = 0 then Corner.z := aMin.z else Corner.z := aMax.z;

    D     := Corner - C;
    halfW := Max(halfW, Abs(D.Dot(R)));
    halfH := Max(halfH, Abs(D.Dot(U)));
    halfD := Max(halfD, Abs(D.Dot(F)));
  end;

  Scale := Max(Max(halfW, halfH), halfD);
  if Scale < FIT_EPSILON then
  begin
    // Every corner is the same point.  There is nothing to frame, so frame a
    // unit box about it: the caller gets a camera centred on the point and a
    // sane near/far, rather than one pressed up against it.
    halfW := 0.5;
    halfH := 0.5;
    halfD := 0.5;
    Scale := 0.5;
  end;

  // A flat dataset - a height field seen from above has halfD of exactly zero
  // - would otherwise divide by zero below.  Relative to the box, so the floor
  // means the same thing at survey scale as it does near the origin.
  MinExt := Scale * 1.0e-6;
  halfW  := Max(halfW, MinExt);
  halfH  := Max(halfH, MinExt);
  halfD  := Max(halfD, MinExt);

  // Margin applies to what is being framed - the screen-plane extent.  Depth
  // is only cleared, never framed, so halfD is left alone.
  halfW := halfW * aMargin;
  halfH := halfH * aMargin;

  FCriticalSection.Enter;
  try
    ProjType := FProjectionType;
    FOV      := FFieldOfView;
  finally
    FCriticalSection.Leave;
  end;

  if ProjType = ptOrthographic then
  begin
    // BuildProjectionForAspect keeps the stored HEIGHT and derives the width
    // as halfH * aAspect, discarding OrthLeft/OrthRight entirely.  Fitting
    // therefore means solving for the height: widening left/right to the data
    // and stopping there frames correctly at one aspect ratio and clips the
    // data at every other one.
    halfH := Max(halfH, halfW / aAspect);
    halfW := halfH * aAspect;

    // Clearance in front of and behind the data.  Proportional to the scene,
    // so it is neither swallowed by survey coordinates nor enormous next to a
    // small model.
    Pad := Max(halfD, halfH) * 0.1 + CAMERA_MIN_NEAR;

    Eye   := C - F * (halfD + Pad);
    NearP := Pad * 0.5;                  // half way to the near face
    FarP  := halfD * 2 + Pad * 2;        // past the far face

    LookAt(Eye, C, U);
    SetOrthographic(-halfW, halfW, halfH, -halfH, NearP, FarP);
  end
  else
  begin
    // FieldOfView is the full VERTICAL angle: RecalculateProjectionMatrix puts
    // f = cot(FOV/2) unscaled in the Y column and divides X by the aspect.
    // So the vertical half-extent visible at distance d is d * tan(FOV/2),
    // and the horizontal one that times the aspect.
    T := Tan(DegToRad(EnsureRange(FOV, 1.0, 179.0)) * 0.5);
    if T < FIT_EPSILON then T := FIT_EPSILON;

    // Whichever of the two constraints needs the greater distance wins; the
    // half-depth then pushes the eye back past the near face of the box, so a
    // fit computed at the centre does not clip the front half of the data.
    Dist := Max(halfH / T, halfW / (T * aAspect)) + halfD;

    Eye   := C - F * Dist;

    // Dist - halfD is the gap to the nearest data, and is strictly positive.
    NearP := Max(CAMERA_MIN_NEAR, (Dist - halfD) * NEAR_FRACTION);
    FarP  := (Dist + halfD) * 1.5;

    LookAt(Eye, C, U);

    // NOT SetPerspective: that writes FAspectRatio, and aAspect here is the
    // viewport's shape, not the camera's design aspect.  PrepareFrameGlobalData
    // relies on FAspectRatio staying the camera's own.  Near before far, so
    // SetNearPlane's "near must be below far" guard cannot push the far plane
    // somewhere we then have to undo.
    NearPlane := NearP;
    FarPlane  := FarP;
  end;

  Result := True;
end;

function TvgCamera.ZoomAll(const aMin, aMax: TpvVector3D;
                           aAspect: Double; aMargin: Double): Boolean;
var
  Dir, Up : TpvVector3D;
begin
  FCriticalSection.Enter;
  try
    Dir := FTarget - FPosition;
    Up  := FUpVector;
  finally
    FCriticalSection.Leave;
  end;

  // A camera sitting exactly on its own target has no direction to keep.
  // Fall back to the default view rather than refusing to zoom.
  if Dir.Length < 1.0e-9 then
    Dir := vgFromYUp(0, 0, -1);

  Result := FitToBounds(aMin, aMax, Dir, Up, aAspect, aMargin);
end;

function TvgCamera.ZoomAllLookDown(const aMin, aMax: TpvVector3D;
                                   aAspect: Double; aMargin: Double): Boolean;
begin
  // Looking along -vgWorldUp, so the up vector cannot be vgWorldUp: it is the
  // view direction, and FUpVector.Cross(zaxis) in RecalculateViewMatrix would
  // be zero.  vgWorldForward puts world forward at the top of the screen and
  // vgWorldRight to the right in either axis convention - north up, east
  // right, the usual plan view.
  Result := FitToBounds(aMin, aMax, -vgWorldUp, vgWorldForward, aAspect, aMargin);
end;

function TvgCamera.ZoomAllFromDirection(const aMin, aMax, aDirection, aUp: TpvVector3D;
                                        aAspect: Double; aMargin: Double): Boolean;
begin
  Result := FitToBounds(aMin, aMax, aDirection, aUp, aAspect, aMargin);
end;

function TvgCamera.GetFrustumPlanes: TvgFrustrumPlanes;
var
  VP       : TpvMatrix4x4D;
  Proj     : TpvMatrix4x4D;
  NearDist : Double;
begin
  FCriticalSection.Enter;
  try
    UpdateMatrices;

    VP       := FViewProjectionMatrix;
    Proj     := FProjectionMatrix;
    NearDist := FNearPlane;
  finally
    FCriticalSection.Leave;
  end;

  // Not cached, so cfFrustumDirty is deliberately left alone: nothing in this
  // unit ever tests it, and clearing it here would be an unsynchronised write
  // to FUpdateFlags from whichever thread happened to ask for the planes.
  Result := vgExtractFrustumPlanes(VP,
              vgProjectionIsZeroToOneDepth(Proj, NearDist));
end;

function TvgCamera.GetFrustumPlanesForAspect(aAspect: Double): TvgFrustrumPlanes;
begin
  Result := GetFrustumPlanesForAspect(aAspect, TpvVector3D.Create(0, 0, 0));
end;

function TvgCamera.GetFrustumPlanesForAspect(aAspect: Double; const aOrigin: TpvVector3D): TvgFrustrumPlanes;
var
  LocalProj : TpvMatrix4x4D;
  VP        : TpvMatrix4x4D;
  NearDist  : Double;
begin
  FCriticalSection.Enter;
  try
    if cfViewDirty in FUpdateFlags then
      RecalculateViewMatrix;

    // Same projection, and the same VP composition, that
    // GetViewProjectionMatrixForAspect hands the renderer - so the volume
    // culled against is exactly the volume drawn.
    LocalProj := BuildProjectionForAspect(aAspect);
    VP        := BuildViewForOrigin(aOrigin) * LocalProj;
    NearDist  := FNearPlane;
  finally
    FCriticalSection.Leave;
  end;

  // Deliberately outside the lock: operates only on the locals above, so
  // several renderer threads can extract their own planes concurrently.
  Result := vgExtractFrustumPlanes(VP,
              vgProjectionIsZeroToOneDepth(LocalProj, NearDist));
end;

function TvgCamera.ScreenToWorldRay(aScreenX, aScreenY: Double; aViewportWidth, aViewportHeight: Double): TpvVector3D;
var
  Origin : TpvVector3D;
begin
  Result := ScreenToWorldRay(aScreenX, aScreenY, aViewportWidth, aViewportHeight, Origin);
end;

function TvgCamera.ScreenToWorldRay(aScreenX, aScreenY: Double; aViewportWidth, aViewportHeight: Double;
                                    out aOrigin: TpvVector3D): TpvVector3D;

  // Clip-space point back to eye space, perspective divide included.
  function Unproject(const aInvProj: TpvMatrix4x4D; aX, aY, aZ: Double): TpvVector3D;
  var
    P : TpvVector4D;
  begin
    P      := aInvProj * TpvVector4D.Create(aX, aY, aZ, 1.0);
    Result := TpvVector3D.Create(P.x / P.w, P.y / P.w, P.z / P.w);
  end;

var
  Proj, InvView     : TpvMatrix4x4D;
  NearDist          : Double;
  NearZ, NX, NY     : Double;
  EyeNear, EyeFar   : TpvVector3D;
begin
  FCriticalSection.Enter;
  try
    if cfViewDirty in FUpdateFlags then
      RecalculateViewMatrix;

    if (aViewportWidth <= 0) or (aViewportHeight <= 0) then
    begin
      // No viewport, no pixel: the best available ray is the view direction.
      aOrigin := FPosition;
      Result  := (FTarget - FPosition).Normalize;
      Exit;
    end;

    Proj     := BuildProjectionForAspect(aViewportWidth / aViewportHeight);
    InvView  := FInverseViewMatrix;
    NearDist := FNearPlane;
  finally
    FCriticalSection.Leave;
  end;

  // This used to apply inverse(view) * inverse(projection) to one far-plane
  // point and normalise its xyz, with no perspective divide and without
  // subtracting the eye.  That is the direction from the WORLD ORIGIN to the
  // far point, which only resembles the view ray while the camera sits near
  // the origin - off by 6 degrees at (1000, 0, 1000) and pointing nearly
  // straight up at (0, 100000, 0).
  //
  // Instead: unproject a near-plane and a far-plane point into EYE space,
  // where the numbers are small, and only then take them to world space
  // with the rigid inverse view.

  // Vulkan's viewport maps y = 0 to NDC -1 (the top), and BuildProjection-
  // ForAspect already negates Y to match, so no flip here.
  NX := 2.0 * aScreenX / aViewportWidth  - 1.0;
  NY := 2.0 * aScreenY / aViewportHeight - 1.0;

  if vgProjectionIsZeroToOneDepth(Proj, NearDist) then
    NearZ := 0.0
  else
    NearZ := -1.0;

  EyeNear := Unproject(Proj.Inverse, NX, NY, NearZ);
  EyeFar  := Unproject(Proj.Inverse, NX, NY, 1.0);

  aOrigin := InvView.MulHomogen(EyeNear);
  Result  := InvView.MulBasis(EyeFar - EyeNear).Normalize;
end;

function TvgCamera.WorldToScreenPoint(const aWorldPoint: TpvVector3D; aViewportWidth, aViewportHeight: Double): TpvVector3D;
var
  View, Proj : TpvMatrix4x4D;
  Eye, Clip  : TpvVector4D;
begin
  // A degenerate viewport or a point in the eye plane lands on NDC (0,0,0).
  Result := TpvVector3D.Create(aViewportWidth * 0.5, aViewportHeight * 0.5, 0);
  if (aViewportWidth <= 0) or (aViewportHeight <= 0) then
    Exit;

  FCriticalSection.Enter;
  try
    if cfViewDirty in FUpdateFlags then
      RecalculateViewMatrix;
    View := FViewMatrix;
    Proj := BuildProjectionForAspect(aViewportWidth / aViewportHeight);
  finally
    FCriticalSection.Leave;
  end;

  // The same projection and pixel mapping as ScreenToWorldRay, so the two are
  // exact inverses and both agree with what the renderer draws.  View first:
  // it cancels the point's large world position against the camera's while
  // the values are still exact, and the projection then sees small numbers.
  Eye  := View * TpvVector4D.Create(aWorldPoint.X, aWorldPoint.Y, aWorldPoint.Z, 1.0);
  Clip := Proj * Eye;

  if Clip.W = 0 then
    Exit;

  Result.X := (Clip.X / Clip.W + 1.0) * 0.5 * aViewportWidth;
  Result.Y := (Clip.Y / Clip.W + 1.0) * 0.5 * aViewportHeight;
  Result.Z :=  Clip.Z / Clip.W;
end;

{ ============================================================================ }
{ TvgCameraManager Implementation                                            }
{ ============================================================================ }

constructor TvgCameraManager.Create;
begin
  inherited Create;
  FCriticalSection := TCriticalSection.Create;
  FCameras      := TObjectDictionary<string, TvgCamera>.Create([doOwnsValues]);
  FActiveCamera := nil;
end;

destructor TvgCameraManager.Destroy;
begin
  FCameras.Free;
  FCriticalSection.Free;
  inherited Destroy;
end;

procedure TvgCameraManager.AddBaseCamera(aName: String);
begin
  If FCameras.Count>0 then exit;

  AddCamera(aName,TvgCamera.Create);

end;

procedure TvgCameraManager.AddCamera(const aName: string; aCamera: TvgCamera);
begin
  if not Assigned(aCamera) then Exit;

  FCriticalSection.Enter;
  try
    FCameras.AddOrSetValue(aName, aCamera);
    if not Assigned(FActiveCamera) then
      FActiveCamera := aCamera;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCameraManager.GetCamera(const aName: string): TvgCamera;
begin
  FCriticalSection.Enter;
  try
    if not FCameras.TryGetValue(aName, Result) then
      Result := nil;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCameraManager.RemoveCamera(const aName: string);
begin
  FCriticalSection.Enter;
  try
    if FActiveCamera = FCameras[aName] then
      FActiveCamera := nil;
    FCameras.Remove(aName);
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCameraManager.GetCameraCount: Integer;
begin
  FCriticalSection.Enter;
  try
    Result := FCameras.Count;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCameraManager.SetActiveCamera(const aName: string);
var
  cam: TvgCamera;
begin
  FCriticalSection.Enter;
  try
    if FCameras.TryGetValue(aName, cam) then
      FActiveCamera := cam;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCameraManager.SetAspectRatio(aWidth, aHeight :Integer);
  Var C: TvgCamera;
      R: Double;
begin
  If  (aWidth=0) or (aHeight=0) then exit;
  If fCameras.Count=0 then exit;

  FCriticalSection.Enter;
  try
     R := aWidth/aHeight;  //check
     For C in fCameras.values do
        C.AspectRatio := R;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCameraManager.GetActiveCamera: TvgCamera;
begin
  FCriticalSection.Enter;
  try
    Result := FActiveCamera;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCameraManager.ClearAll;
begin
  FCriticalSection.Enter;
  try
    FCameras.Clear;
    FActiveCamera := nil;
  finally
    FCriticalSection.Leave;
  end;
end;

end.
