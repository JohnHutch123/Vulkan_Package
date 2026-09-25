unit Vulkan_WorldAxes;

{------------------------------------------------------------------------------
  World axis convention.

  The package can treat the world as either

    acYUp : XZ horizontal, +Y up   (the default, and what the package always used)
    acZUp : XY horizontal, +Z up

  Both are right-handed: Y-up becomes Z-up by a +90 degree rotation about X,
  (x, y, z) -> (x, -z, y).  Front-face winding, cull mode and the projection
  matrices are therefore identical in either convention; only which way is
  "up" changes.

  The convention decides the DEFAULTS objects are created with - a camera's
  position and up vector, a force field's direction, an emitter's launch
  velocity.  It never rotates anything that already exists, so set it once at
  start-up before any of those objects are created: first thing in the .dpr,
  or build the package with VG_WORLD_Z_UP defined in VulkanPackage.inc.

  Objects that bake the convention into their defaults call
  vgRetainAxisConvention when created and vgReleaseAxisConvention when
  destroyed.  vgSetAxisConvention refuses to change the value while any of
  them are alive, so a scene can never end up half in each convention.
------------------------------------------------------------------------------}

interface

{$INCLUDE VulkanPackage.inc}

uses
  PasVulkan.Math.Double;

type
  TvgAxisConvention = (acYUp, acZUp);

  // Planes named for what they are in the world rather than for the axes that
  // span them, so the same name means the same plane in either convention.
  TvgWorldPlane = (
    wpHorizontal,   // the ground plane;                    normal vgWorldUp
    wpFront,        // vertical, facing the default camera; normal -vgWorldForward
    wpSide          // vertical, facing +X;                 normal vgWorldRight
  );

function  vgAxisConvention: TvgAxisConvention;

// Returns False, and leaves the convention unchanged, when aValue differs from
// the current value while objects created under the current one are alive.
function  vgSetAxisConvention(aValue: TvgAxisConvention): Boolean;

procedure vgRetainAxisConvention;
procedure vgReleaseAxisConvention;
function  vgAxisConventionUsers: Integer;

function vgWorldUp      : TpvVector3D;   // acYUp (0,1,0)    acZUp (0,0,1)
function vgWorldForward : TpvVector3D;   // acYUp (0,0,-1)   acZUp (0,1,0)
function vgWorldRight   : TpvVector3D;   // (1,0,0) in both

function vgPlaneNormal(aPlane: TvgWorldPlane): TpvVector3D;

// The component of aV along vgWorldUp - its height.
function vgUpComponent(const aV: TpvVector3D): Double;

// Take a vector written in Y-up terms into the active convention, and back.
// Both are the identity under acYUp.  Double throughout: these carry world
// positions, and a Single parameter would round a survey coordinate such as
// 612345.678 to the nearest 1/16 before it was ever converted.
function vgFromYUp(const aX, aY, aZ: Double): TpvVector3D; overload;
function vgFromYUp(const aV: TpvVector3D): TpvVector3D; overload;
function vgToYUp(const aV: TpvVector3D): TpvVector3D;

// A Y-up min/max range taken into the active convention.  Converting the two
// corners on their own is not enough: acZUp negates a component, which would
// leave that axis with min > max.
procedure vgRangeFromYUp(const aMin, aMax: TpvVector3D; out aOutMin, aOutMax: TpvVector3D);

// For assets authored Y-up (glTF is Y-up by specification): apply
// vgYUpToWorldMatrix at the root when importing, vgWorldToYUpMatrix when
// exporting.  Both are the identity under acYUp.
function vgYUpToWorldMatrix: TpvMatrix4x4D;
function vgWorldToYUpMatrix: TpvMatrix4x4D;

implementation

uses
  System.SysUtils,
  System.Math,
  Vulkan_Assert;

var
  gAxisConvention : TvgAxisConvention = {$IFDEF VG_WORLD_Z_UP}acZUp{$ELSE}acYUp{$ENDIF};
  gAxisUsers      : Integer = 0;

function vgAxisConvention: TvgAxisConvention;
begin
  Result := gAxisConvention;
end;

function vgSetAxisConvention(aValue: TvgAxisConvention): Boolean;
begin
  if aValue = gAxisConvention then
    Exit(True);

  Result := gAxisUsers = 0;
  CustomAssert(Result,
    Format('vgSetAxisConvention: %d object(s) created under the current axis ' +
           'convention are still alive.  Set the convention at start-up, ' +
           'before creating cameras or particle systems.', [gAxisUsers]));
  if Result then
    gAxisConvention := aValue;
end;

procedure vgRetainAxisConvention;
begin
  AtomicIncrement(gAxisUsers);
end;

procedure vgReleaseAxisConvention;
begin
  AtomicDecrement(gAxisUsers);
end;

function vgAxisConventionUsers: Integer;
begin
  Result := gAxisUsers;
end;

function vgWorldUp: TpvVector3D;
begin
  if gAxisConvention = acZUp then
    Result := TpvVector3D.Create(0, 0, 1)
  else
    Result := TpvVector3D.Create(0, 1, 0);
end;

function vgWorldForward: TpvVector3D;
begin
  if gAxisConvention = acZUp then
    Result := TpvVector3D.Create(0, 1, 0)
  else
    Result := TpvVector3D.Create(0, 0, -1);
end;

function vgWorldRight: TpvVector3D;
begin
  Result := TpvVector3D.Create(1, 0, 0);
end;

function vgPlaneNormal(aPlane: TvgWorldPlane): TpvVector3D;
begin
  case aPlane of
    wpFront : Result := vgFromYUp(0, 0, 1);
    wpSide  : Result := vgWorldRight;
  else
    Result := vgWorldUp;
  end;
end;

function vgUpComponent(const aV: TpvVector3D): Double;
begin
  if gAxisConvention = acZUp then
    Result := aV.z
  else
    Result := aV.y;
end;

function vgFromYUp(const aX, aY, aZ: Double): TpvVector3D;
begin
  if gAxisConvention = acZUp then
    Result := TpvVector3D.Create(aX, -aZ, aY)
  else
    Result := TpvVector3D.Create(aX, aY, aZ);
end;

function vgFromYUp(const aV: TpvVector3D): TpvVector3D;
begin
  Result := vgFromYUp(aV.x, aV.y, aV.z);
end;

function vgToYUp(const aV: TpvVector3D): TpvVector3D;
begin
  if gAxisConvention = acZUp then
    Result := TpvVector3D.Create(aV.x, aV.z, -aV.y)
  else
    Result := aV;
end;

procedure vgRangeFromYUp(const aMin, aMax: TpvVector3D; out aOutMin, aOutMax: TpvVector3D);
var
  A, B : TpvVector3D;
begin
  A := vgFromYUp(aMin);
  B := vgFromYUp(aMax);
  aOutMin := TpvVector3D.Create(Min(A.x, B.x), Min(A.y, B.y), Min(A.z, B.z));
  aOutMax := TpvVector3D.Create(Max(A.x, B.x), Max(A.y, B.y), Max(A.z, B.z));
end;

// TpvMatrix4x4D.Create takes its arguments column by column: the first four are
// where the X basis vector lands, and so on.
//
// PasVulkan.Math.Double has no Identity constant (TpvMatrix4x4 does), so the
// Y-up branches spell it out.

function vgYUpToWorldMatrix: TpvMatrix4x4D;
begin
  if gAxisConvention = acZUp then
    Result := TpvMatrix4x4D.Create(1,  0, 0, 0,     // X -> +X
                                   0,  0, 1, 0,     // Y -> +Z
                                   0, -1, 0, 0,     // Z -> -Y
                                   0,  0, 0, 1)
  else
    Result := TpvMatrix4x4D.Create(1, 0, 0, 0,
                                   0, 1, 0, 0,
                                   0, 0, 1, 0,
                                   0, 0, 0, 1);
end;

function vgWorldToYUpMatrix: TpvMatrix4x4D;
begin
  if gAxisConvention = acZUp then
    Result := TpvMatrix4x4D.Create(1, 0,  0, 0,     // X -> +X
                                   0, 0, -1, 0,     // Y -> -Z
                                   0, 1,  0, 0,     // Z -> +Y
                                   0, 0,  0, 1)
  else
    Result := TpvMatrix4x4D.Create(1, 0, 0, 0,
                                   0, 1, 0, 0,
                                   0, 0, 1, 0,
                                   0, 0, 0, 1);
end;

end.
