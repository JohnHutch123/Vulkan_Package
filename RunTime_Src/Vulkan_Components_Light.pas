unit Vulkan_Components_Light;

interface

{$INCLUDE VulkanPackage.inc}

uses
  System.Math,
  PasVulkan.Math.Double;

type
  // KHR_lights_punctual's three punctual light types.  ltNone marks a light
  // whose "type" the source file left unrecognised - kept in case its
  // position/direction are still useful, but no type-specific lighting
  // applies to it.
  TvgLightType = (ltNone, ltDirectional, ltPoint, ltSpot);

  { TvgLight

    One glTF KHR_lights_punctual light, already resolved to world space at
    load time: Position/Direction come from the node that referenced it, via
    that node's world transform - a light is otherwise just data here, not
    tied to any node.  Field names, defaults and units follow the extension
    spec directly:

      Intensity            - lux for Directional, candela for Point/Spot
      Range                - metres; 0 means infinite (the spec's default
                              when the field is absent)
      InnerConeAngle,
      OuterConeAngle       - radians; Spot only

    Not covered: shadow casting, which the extension leaves to convention
    rather than specifying - this engine has no shadow maps yet either. }
  TvgLight = record
    Name           : String;
    LightType      : TvgLightType;
    Color          : TpvVector3D;   // linear RGB, default (1,1,1)
    Intensity      : Double;        // default 1
    Range          : Double;        // default 0 (infinite)
    InnerConeAngle : Double;        // default 0, Spot only
    OuterConeAngle : Double;        // default Pi/4, Spot only
    Position       : TpvVector3D;   // world space; Point/Spot
    Direction      : TpvVector3D;   // world space, normalised, the node's local -Z axis; Directional/Spot
  end;

  { TvgLightGPUData

    TvgLight narrowed and packed for the lights storage buffer: std430
    layout, vec4-aligned, single precision, four plain vec4s with no
    trailing padding needed since 4 singles already fill 16 bytes.  Position
    is relative to TvgScene.WorldOrigin, exactly like vertex data - see
    TvgLightToGPUData, which does that subtraction - not survey coordinates.

    Field packing (must stay in step with the GLSL struct
    TvgDescriptorArray_SB_Light.GetShaderDescriptorStringTemplate_Vertex
    declares ahead of the lights buffer block):
      PositionRange.xyz  = local-space position (Point/Spot)
      PositionRange.w    = range, 0 = infinite
      DirectionType.xyz  = local-space direction, normalised (Directional/Spot)
      DirectionType.w    = TvgLightType as a float (Ord: 0=None,1=Directional,2=Point,3=Spot)
      ColorIntensity.rgb = linear colour
      ColorIntensity.w   = intensity
      ConeAngles.x       = cos(InnerConeAngle)
      ConeAngles.y       = cos(OuterConeAngle)
      ConeAngles.zw      = unused }
  TvgLightGPUData = packed record
    PositionRange  : array[0..3] of Single;
    DirectionType  : array[0..3] of Single;
    ColorIntensity : array[0..3] of Single;
    ConeAngles     : array[0..3] of Single;
  end;

  // aWorldOrigin is TvgScene.WorldOrigin: narrowing aLight.Position to
  // Single without subtracting it first would round a real-world position
  // the same way an un-offset vertex would - see VG_LOCAL_COORD_LIMIT.
  function TvgLightToGPUData(const aLight: TvgLight; const aWorldOrigin: TpvVector3D): TvgLightGPUData;

implementation

function TvgLightToGPUData(const aLight: TvgLight; const aWorldOrigin: TpvVector3D): TvgLightGPUData;
var
  LocalPos : TpvVector3D;
begin
  LocalPos := aLight.Position - aWorldOrigin;

  Result.PositionRange[0] := LocalPos.x;
  Result.PositionRange[1] := LocalPos.y;
  Result.PositionRange[2] := LocalPos.z;
  Result.PositionRange[3] := aLight.Range;

  Result.DirectionType[0] := aLight.Direction.x;
  Result.DirectionType[1] := aLight.Direction.y;
  Result.DirectionType[2] := aLight.Direction.z;
  Result.DirectionType[3] := Ord(aLight.LightType);

  Result.ColorIntensity[0] := aLight.Color.x;
  Result.ColorIntensity[1] := aLight.Color.y;
  Result.ColorIntensity[2] := aLight.Color.z;
  Result.ColorIntensity[3] := aLight.Intensity;

  Result.ConeAngles[0] := Cos(aLight.InnerConeAngle);
  Result.ConeAngles[1] := Cos(aLight.OuterConeAngle);
  Result.ConeAngles[2] := 0.0;
  Result.ConeAngles[3] := 0.0;
end;

end.
