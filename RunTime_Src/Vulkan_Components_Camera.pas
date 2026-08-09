unit Vulkan_Components_Camera;

{
  Vulkan_Components_Camera.pas

  A generic, flexible 3D camera implementation compatible with:
  - glTF camera structures (perspective/orthographic)
  - Standard graphics APIs (OpenGL, Vulkan, DirectX conventions)
  - PasVulkan.Math structures
  - Delphi/FreePascal serialization

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
  PasVulkan.Types;//,


const
  CAMERA_DEFAULT_FOV     = 45.0;
  CAMERA_DEFAULT_NEAR    = 0.01;
  CAMERA_DEFAULT_FAR     = 10000.0;
  CAMERA_DEFAULT_ASPECT  = 16.0 / 9.0;

type
  TvgCamera = class;

  TCameraProjectionType = (ptNone, ptPerspective, ptOrthographic);

  TCameraUpdateFlags = set of (
    cfViewDirty,
    cfProjectionDirty,
    cfFrustumDirty
  );

  TvgFrustrumPlanes = Record
     Planes :  array [0..5] of TpvVector4;
  end;

  { TvgCamera: Main camera class }
  TvgCamera = class
  private
    FCriticalSection    : TCriticalSection;

    // --- Position & Orientation ---
    FPosition           : TpvVector3;
    FTarget             : TpvVector3;
    FUpVector           : TpvVector3;

    // --- Projection Parameters ---
    FProjectionType     : TCameraProjectionType;
    FFieldOfView        : Single; // In degrees, for perspective
    FNearPlane          : Single;
    FFarPlane           : Single;
    FAspectRatio        : Single;

    // --- Orthographic Parameters ---
    FOrthLeft           : Single;
    FOrthRight          : Single;
    FOrthTop            : Single;
    FOrthBottom         : Single;

    // --- Cached Matrices ---
    FViewMatrix              : TpvMatrix4x4;
    FProjectionMatrix        : TpvMatrix4x4;
    FViewProjectionMatrix    : TpvMatrix4x4;
    FInverseViewMatrix       : TpvMatrix4x4;
    FInverseProjectionMatrix : TpvMatrix4x4;

    // --- Update Tracking ---
    FUpdateFlags: TCameraUpdateFlags;
    FName: string;

    // --- Setters with dirty marking ---
    procedure SetPosition(const Value: TpvVector3);
    procedure SetTarget(const Value: TpvVector3);
    procedure SetUpVector(const Value: TpvVector3);
    procedure SetFieldOfView(const Value: Single);
    procedure SetNearPlane(const Value: Single);
    procedure SetFarPlane(const Value: Single);
    procedure SetAspectRatio(const Value: Single);
    procedure SetProjectionType(const Value: TCameraProjectionType);
 //   procedure SetOrthBounds(aLeft, aRight, aTop, aBottom: Single);

    // --- Matrix Builders ---
    procedure RecalculateViewMatrix;
    procedure RecalculateProjectionMatrix;
    procedure RecalculateViewProjectionMatrix;
    procedure InvalidateMatrices(aFlags: TCameraUpdateFlags);

    // --- Helpers ---
    function GetForwardVector: TpvVector3;
    function GetRightVector: TpvVector3;
    function GetCameraDistance: Single;

  public
    constructor Create;
    destructor Destroy; override;

    // --- Initialization ---
    procedure InitializeAsDefault;
 //   procedure InitializeFromGltfCamera(const aCamera: TpgCamera; aAspectRatio: Single = CAMERA_DEFAULT_ASPECT);
    procedure InitializeFromParameters(const aPosition,
                                             aTarget,
                                             aUpVector: TpvVector3;
                                            aFOV: Single = CAMERA_DEFAULT_FOV;
                                            aNear: Single = CAMERA_DEFAULT_NEAR;
                                            aFar: Single = CAMERA_DEFAULT_FAR;
                                            aAspect: Single = CAMERA_DEFAULT_ASPECT);

    // --- View Matrix Access (thread-safe) ---
    function GetViewMatrix                  : TpvMatrix4x4;
    function GetProjectionMatrix            : TpvMatrix4x4;
    function GetViewProjectionMatrix        : TpvMatrix4x4;
    function GetInverseViewMatrix           : TpvMatrix4x4;
    function GetInverseProjectionMatrix     : TpvMatrix4x4;

    // --- Interactive Controls ---
    { Orbit: Rotate camera around target }
    procedure Orbit(aYaw, aPitch: Single; aUseWorldUp: Boolean = True);

    { Pan: Move camera and target together in local plane }
    procedure Pan(aDeltaX, aDeltaY: Single);

    { Zoom: Move toward/away from target (dolly) }
    procedure Zoom(aDeltaZoom: Single);

    { Dolly: Move forward/backward in camera direction }
    procedure Dolly(aDistance: Single);

    { Look At: Set camera to look at target from position }
    procedure LookAt(const aPosition, aTarget, aUpVector: TpvVector3);

    { Move: Directly set camera position }
    procedure Move(const aNewPosition: TpvVector3);

    { Set Target: Directly set look-at target }
    procedure SetLookAtTarget(const aTarget: TpvVector3);

    // --- Projection utilities ---
    procedure SetPerspective(aFOVDegrees, aAspect, aNear, aFar: Single);
    procedure SetOrthographic(aLeft, aRight, aTop, aBottom, aNear, aFar: Single);

    { World-space frustum planes (useful for culling) }
    function GetFrustumPlanes : TvgFrustrumPlanes; // 6 planes: near, far, left, right, top, bottom

    { Screen-to-world ray casting }
    function ScreenToWorldRay(aScreenX, aScreenY: Single; aViewportWidth, aViewportHeight: Single): TpvVector3;

    { World-to-screen projection }
    function WorldToScreenPoint(const aWorldPoint: TpvVector3; aViewportWidth, aViewportHeight: Single): TpvVector3;

{ Returns VP matrix computed with aAspect substituted for FAspectRatio.
       Does NOT mutate FAspectRatio, FProjectionMatrix, or FUpdateFlags.
       Safe to call simultaneously from multiple renderer threads. }
    function GetViewProjectionMatrixForAspect(aAspect: Single): TpvMatrix4x4;

    // --- Properties ---
    property Position: TpvVector3 read FPosition write SetPosition;
    property Target: TpvVector3 read FTarget write SetTarget;
    property UpVector: TpvVector3 read FUpVector write SetUpVector;

    property ProjectionType: TCameraProjectionType read FProjectionType write SetProjectionType;
    property FieldOfView: Single read FFieldOfView write SetFieldOfView;
    property NearPlane: Single read FNearPlane write SetNearPlane;
    property FarPlane: Single read FFarPlane write SetFarPlane;
    property AspectRatio: Single read FAspectRatio write SetAspectRatio;

    property OrthLeft: Single read FOrthLeft;
    property OrthRight: Single read FOrthRight;
    property OrthTop: Single read FOrthTop;
    property OrthBottom: Single read FOrthBottom;

    property ForwardVector: TpvVector3 read GetForwardVector;
    property RightVector: TpvVector3 read GetRightVector;
    property Distance: Single read GetCameraDistance;

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

    procedure AddCamera(const aName: string; aCamera: TvgCamera);
    function GetCamera(const aName: string): TvgCamera;
    procedure RemoveCamera(const aName: string);
    function GetCameraCount: Integer;

    procedure SetActiveCamera(const aName: string);
    function GetActiveCamera: TvgCamera;

    Procedure SetAspectRatio(aWidth, aHeight :Integer);

    procedure ClearAll;
  end;

implementation

{ ============================================================================ }
{ TvgCamera Implementation                                                    }
{ ============================================================================ }

constructor TvgCamera.Create;
begin
  inherited Create;
  FCriticalSection := TCriticalSection.Create;

  FPosition        := TpvVector3.Create(0, 0, 5);
  FTarget          := TpvVector3.Create(0, 0, 0);
  FUpVector        := TpvVector3.Create(0, 1, 0);

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

  FName           := 'Camera_' + IntToStr(Integer(Self));

  RecalculateViewMatrix;
  RecalculateProjectionMatrix;
  RecalculateViewProjectionMatrix;
end;

destructor TvgCamera.Destroy;
begin
  FCriticalSection.Free;
  inherited Destroy;
end;

procedure TvgCamera.InitializeAsDefault;
begin
  LookAt(
    TpvVector3.Create(0, 2, 5),
    TpvVector3.Create(0, 0, 0),
    TpvVector3.Create(0, 1, 0)
  );
  SetPerspective(CAMERA_DEFAULT_FOV, CAMERA_DEFAULT_ASPECT, CAMERA_DEFAULT_NEAR, CAMERA_DEFAULT_FAR);
end;
(*
procedure TvgCamera.InitializeFromGltfCamera(const aCamera: TpgCamera; aAspectRatio: Single = CAMERA_DEFAULT_ASPECT);
var
  camType: string;
begin
  if not Assigned(aCamera) then
  begin
    InitializeAsDefault;
    Exit;
  end;

  camType := aCamera.Type_;

  if camType = 'perspective' then
  begin
    if Assigned(aCamera.Perspective) then
    begin
      SetPerspective(
        RadToDeg(aCamera.Perspective.YFov),
        aCamera.Perspective.AspectRatio,
        aCamera.Perspective.ZNear,
        aCamera.Perspective.ZFar
      );
    end
    else
      SetPerspective(CAMERA_DEFAULT_FOV, aAspectRatio, CAMERA_DEFAULT_NEAR, CAMERA_DEFAULT_FAR);
  end
  else if camType = 'orthographic' then
  begin
    if Assigned(aCamera.Orthographic) then
    begin
      SetOrthographic(
        -aCamera.Orthographic.XMag / 2,
        aCamera.Orthographic.XMag / 2,
        aCamera.Orthographic.YMag / 2,
        -aCamera.Orthographic.YMag / 2,
        aCamera.Orthographic.ZNear,
        aCamera.Orthographic.ZFar
      );
    end
    else
      SetOrthographic(-1, 1, 1, -1, CAMERA_DEFAULT_NEAR, CAMERA_DEFAULT_FAR);
  end
  else
    InitializeAsDefault;

  FName := aCamera.Name;
end;
*)
procedure TvgCamera.InitializeFromParameters(const aPosition, aTarget, aUpVector: TpvVector3;
  aFOV: Single; aNear: Single; aFar: Single; aAspect: Single);
begin
  LookAt(aPosition, aTarget, aUpVector);
  SetPerspective(aFOV, aAspect, aNear, aFar);
end;

Function Vec_Equals(Vec1, Vec2:TpvVector3):Boolean;
Begin
  Result := False;
  If IsZero(Vec1.x-vec2.x) and
     IsZero(Vec1.y-vec2.y) and
     IsZero(Vec1.z-vec2.z) then result := True;
End;

procedure TvgCamera.SetPosition(const Value: TpvVector3);
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

procedure TvgCamera.SetTarget(const Value: TpvVector3);
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

procedure TvgCamera.SetUpVector(const Value: TpvVector3);
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

procedure TvgCamera.SetFieldOfView(const Value: Single);
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

procedure TvgCamera.SetNearPlane(const Value: Single);
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

procedure TvgCamera.SetFarPlane(const Value: Single);
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

procedure TvgCamera.SetAspectRatio(const Value: Single);
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
procedure TvgCamera.SetOrthBounds(aLeft, aRight, aTop, aBottom: Single);
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
end;

procedure TvgCamera.RecalculateViewMatrix;
var
  zaxis, xaxis, yaxis: TpvVector3;
begin
  // Standard LookAt matrix (RH coordinate system, Vulkan-style)
  zaxis := (FPosition - FTarget).Normalize;
  xaxis := FUpVector.Cross(zaxis).Normalize;
  yaxis := zaxis.Cross(xaxis).Normalize;

  FViewMatrix.Columns[0] := TpvVector4.Create(xaxis.X, yaxis.X, zaxis.X, 0);
  FViewMatrix.Columns[1] := TpvVector4.Create(xaxis.Y, yaxis.Y, zaxis.Y, 0);
  FViewMatrix.Columns[2] := TpvVector4.Create(xaxis.Z, yaxis.Z, zaxis.Z, 0);
  FViewMatrix.Columns[3] := TpvVector4.Create(-xaxis.Dot(FPosition),
                                             -yaxis.Dot(FPosition),
                                             -zaxis.Dot(FPosition),  1 );

  FInverseViewMatrix := FViewMatrix.Inverse;
  Exclude(FUpdateFlags, cfViewDirty);
end;

procedure TvgCamera.RecalculateProjectionMatrix;
var
  fovy, f, invDepth: Single;
begin
  case FProjectionType of
    ptPerspective:
    begin
      fovy := DegToRad(FFieldOfView) / 2;
      f := Cos(fovy) / Sin(fovy);
      invDepth := 1.0 / (FNearPlane - FFarPlane);

      FProjectionMatrix := TpvMatrix4x4.Create(
        f / FAspectRatio, 0, 0, 0,
        0, f, 0, 0,
        0, 0, (FFarPlane + FNearPlane) * invDepth, -1,
        0, 0, 2 * FFarPlane * FNearPlane * invDepth, 0
      );
    end;

    ptOrthographic:
    begin
      invDepth := 1.0 / (FNearPlane - FFarPlane);

      FProjectionMatrix := TpvMatrix4x4.Create(
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
end;

procedure TvgCamera.RecalculateViewProjectionMatrix;
begin
  FViewProjectionMatrix := FProjectionMatrix * FViewMatrix;
end;

function TvgCamera.GetViewMatrix: TpvMatrix4x4;
begin
  FCriticalSection.Enter;
  try
    if cfViewDirty in FUpdateFlags then
      RecalculateViewMatrix;
    if (cfViewDirty in FUpdateFlags) or (cfProjectionDirty in FUpdateFlags) then
      RecalculateViewProjectionMatrix;
    Result := FViewMatrix;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetProjectionMatrix: TpvMatrix4x4;
begin
  FCriticalSection.Enter;
  try
    if cfProjectionDirty in FUpdateFlags then
      RecalculateProjectionMatrix;

    if (cfViewDirty in FUpdateFlags) or (cfProjectionDirty in FUpdateFlags) then
      RecalculateViewProjectionMatrix;
    Result := FProjectionMatrix;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetViewProjectionMatrix: TpvMatrix4x4;
begin
  FCriticalSection.Enter;
  try
    if cfViewDirty in FUpdateFlags then
      RecalculateViewMatrix;
    if cfProjectionDirty in FUpdateFlags then
      RecalculateProjectionMatrix;
    if (cfViewDirty in FUpdateFlags) or (cfProjectionDirty in FUpdateFlags) then
      RecalculateViewProjectionMatrix;
    Result := FViewProjectionMatrix;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetViewProjectionMatrixForAspect(  aAspect: Single): TpvMatrix4x4;
var
  LocalProj  : TpvMatrix4x4;
  fovy, f    : Single;
  invDepth   : Single;
begin
  FCriticalSection.Enter;
  try
    // ?? 1. Rebuild the view matrix if dirty (normal lazy path) ???????????
    if cfViewDirty in FUpdateFlags then
      RecalculateViewMatrix;

    // ?? 2. Build a local projection matrix using the caller's aspect ??????
    //    This is identical to RecalculateProjectionMatrix but writes into
    //    a stack variable, leaving FProjectionMatrix and FAspectRatio alone.
    case FProjectionType of

      ptPerspective:
      begin
        if aAspect <= 0 then aAspect := 1.0;  // guard against bad viewport
        fovy     := DegToRad(FFieldOfView) / 2;
        f        := Cos(fovy) / Sin(fovy);
        invDepth := 1.0 / (FNearPlane - FFarPlane);

        LocalProj := TpvMatrix4x4.Create(
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
        var halfH : Single := (FOrthTop - FOrthBottom) * 0.5;
        var halfW : Single := halfH * aAspect;
        invDepth := 1.0 / (FNearPlane - FFarPlane);

        LocalProj := TpvMatrix4x4.Create(
          1 / halfW,  0,          0,          0,
          0,          1 / halfH,  0,          0,
          0,          0,          invDepth,   0,
          0,          0,          FNearPlane * invDepth, 1
        );
      end;

    else
      LocalProj := TpvMatrix4x4.Identity;
    end;

    // ?? 3. VP = Proj * View (column-major, matches RecalculateViewProjection)
    Result := LocalProj * FViewMatrix;

  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetInverseViewMatrix: TpvMatrix4x4;
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

function TvgCamera.GetInverseProjectionMatrix: TpvMatrix4x4;
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

function TvgCamera.GetForwardVector: TpvVector3;
begin
  FCriticalSection.Enter;
  try
    Result := (FTarget - FPosition).Normalize;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetRightVector: TpvVector3;
begin
  FCriticalSection.Enter;
  try
    Result := ForwardVector.Cross(FUpVector).Normalize;
  finally
    FCriticalSection.Leave;
  end;
end;

function TvgCamera.GetCameraDistance: Single;
begin
  FCriticalSection.Enter;
  try
    Result := (FTarget - FPosition).Length;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.LookAt(const aPosition, aTarget, aUpVector: TpvVector3);
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

procedure TvgCamera.Move(const aNewPosition: TpvVector3);
begin
  Position := aNewPosition;
end;

procedure TvgCamera.SetLookAtTarget(const aTarget: TpvVector3);
begin
  Target := aTarget;
end;

procedure TvgCamera.Orbit(aYaw, aPitch: Single; aUseWorldUp: Boolean = True);
var
  direction: TpvVector3;
  distance: Single;
  cosYaw, sinYaw, cosPitch, sinPitch: Single;
  newDir: TpvVector3;
  right, up: TpvVector3;
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

    // Apply yaw (rotation around world up)
    cosYaw := Cos(DegToRad(aYaw));
    sinYaw := Sin(DegToRad(aYaw));
    direction := newDir * cosYaw + FUpVector.Cross(newDir).Normalize * sinYaw;

    FPosition := FTarget + direction * distance;
    InvalidateMatrices([cfViewDirty, cfFrustumDirty]);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.Pan(aDeltaX, aDeltaY: Single);
var
  right, up: TpvVector3;
  panAmount: Single;
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

procedure TvgCamera.Zoom(aDeltaZoom: Single);
var
  distance: Single;
  newDistance: Single;
begin
  FCriticalSection.Enter;
  try
    distance := Distance;          //fix
    newDistance := distance * (1.0 - aDeltaZoom * 0.1);
    newDistance := EnsureRange(newDistance, 0.1, 100000.0);

    FPosition := FTarget + (FPosition - FTarget).Normalize * newDistance;
    InvalidateMatrices([cfViewDirty, cfFrustumDirty]);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.Dolly(aDistance: Single);
begin
  FCriticalSection.Enter;
  try
    FPosition := FPosition + ForwardVector * aDistance;
    InvalidateMatrices([cfViewDirty, cfFrustumDirty]);
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TvgCamera.SetPerspective(aFOVDegrees, aAspect, aNear, aFar: Single);
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

procedure TvgCamera.SetOrthographic(aLeft, aRight, aTop, aBottom, aNear, aFar: Single);
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

function TvgCamera.GetFrustumPlanes: TvgFrustrumPlanes;
var
  vp: TpvMatrix4x4;
begin
  // Extract frustum planes from view-projection matrix
  // Left, Right, Bottom, Top, Near, Far
  vp := GetViewProjectionMatrix;

  // Left plane
  Result.Planes[0] := TpvVector4.Create(
    vp.RawComponents[3, 0] + vp.RawComponents[0, 0],
    vp.RawComponents[3, 1] + vp.RawComponents[0, 1],
    vp.RawComponents[3, 2] + vp.RawComponents[0, 2],
    vp.RawComponents[3, 3] + vp.RawComponents[0, 3]
  ).Normalize;

  // Right plane
  Result.Planes[1] := TpvVector4.Create(
    vp.RawComponents[3, 0] - vp.RawComponents[0, 0],
    vp.RawComponents[3, 1] - vp.RawComponents[0, 1],
    vp.RawComponents[3, 2] - vp.RawComponents[0, 2],
    vp.RawComponents[3, 3] - vp.RawComponents[0, 3]
  ).Normalize;

  // Bottom plane
  Result.Planes[2] := TpvVector4.Create(
    vp.RawComponents[3, 0] + vp.RawComponents[1, 0],
    vp.RawComponents[3, 1] + vp.RawComponents[1, 1],
    vp.RawComponents[3, 2] + vp.RawComponents[1, 2],
    vp.RawComponents[3, 3] + vp.RawComponents[1, 3]
  ).Normalize;

  // Top plane
  Result.Planes[3] := TpvVector4.Create(
    vp.RawComponents[3, 0] - vp.RawComponents[1, 0],
    vp.RawComponents[3, 1] - vp.RawComponents[1, 1],
    vp.RawComponents[3, 2] - vp.RawComponents[1, 2],
    vp.RawComponents[3, 3] - vp.RawComponents[1, 3]
  ).Normalize;

  // Near plane
  Result.Planes[4] := TpvVector4.Create(
    vp.RawComponents[3, 0] + vp.RawComponents[2, 0],
    vp.RawComponents[3, 1] + vp.RawComponents[2, 1],
    vp.RawComponents[3, 2] + vp.RawComponents[2, 2],
    vp.RawComponents[3, 3] + vp.RawComponents[2, 3]
  ).Normalize;

  // Far plane
  Result.Planes[5] := TpvVector4.Create(
    vp.RawComponents[3, 0] - vp.RawComponents[2, 0],
    vp.RawComponents[3, 1] - vp.RawComponents[2, 1],
    vp.RawComponents[3, 2] - vp.RawComponents[2, 2],
    vp.RawComponents[3, 3] - vp.RawComponents[2, 3]
  ).Normalize;
end;

function TvgCamera.ScreenToWorldRay(aScreenX, aScreenY: Single; aViewportWidth, aViewportHeight: Single): TpvVector3;
var
  ndc: TpvVector3;
  invView: TpvMatrix4x4;
  ray: TpvVector3;
begin
  // Normalize screen coordinates to NDC (-1 to 1)
  ndc.X := (2.0 * aScreenX) / aViewportWidth - 1.0;
  ndc.Y := 1.0 - (2.0 * aScreenY) / aViewportHeight;
  ndc.Z := 1.0;

  invView := GetInverseViewMatrix * GetInverseProjectionMatrix;
  ray := (invView * TpvVector4.Create(ndc.X, ndc.Y, ndc.Z, 1.0)).XYZ.Normalize;

  Result := ray;
end;

function TvgCamera.WorldToScreenPoint(const aWorldPoint: TpvVector3; aViewportWidth, aViewportHeight: Single): TpvVector3;
var
  viewProj: TpvVector4;
  screenPos: TpvVector3;
begin
  viewProj := GetViewProjectionMatrix * TpvVector4.Create(aWorldPoint.X, aWorldPoint.Y, aWorldPoint.Z, 1.0);

  // Perspective divide
  if viewProj.W <> 0 then
  begin
    screenPos.X := viewProj.X / viewProj.W;
    screenPos.Y := viewProj.Y / viewProj.W;
    screenPos.Z := viewProj.Z / viewProj.W;
  end
  else
  begin
    screenPos := TpvVector3.Create(0, 0, 0);
  end;

  // Convert from NDC to screen space
  screenPos.X := (screenPos.X + 1.0) * 0.5 * aViewportWidth;
  screenPos.Y := (1.0 - screenPos.Y) * 0.5 * aViewportHeight;

  Result := screenPos;
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
      R: Single;
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
