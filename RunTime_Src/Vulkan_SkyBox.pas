unit Vulkan_SkyBox;

{------------------------------------------------------------------------------
  A sky behind a scene.

    vgSkyBox(Scene).Visible := True;

  draws a day or night sky behind everything in the scene, with the sun and
  the moon where they are for the time and place.

  It is always fitted to the scene.  The sky is not a box of some size placed
  around the data: it is one triangle covering the screen at the far plane,
  and its shader turns each pixel into the world direction the camera is
  looking along (VulkanShaders\SkyBox.vert / .frag).  So it is at infinity -
  it encloses a scene of any extent, follows every change of the scene's size
  with nothing to resize, never clips against the far plane, and cannot be
  flown out of.  It works in either axis convention (Vulkan_WorldAxes),
  whatever the WorldOrigin.  An orthographic camera looks the same way at
  every pixel, so there the sky is the one colour it has in that direction.

  Mode
    skmAuto   day, twilight and night follow the sun
    skmDay    always day:   the sun where the time puts it, or at a fixed
                            mid-morning position while the real one is down
    skmNight  always night: the moon likewise

  UpAxis - which way is up in the sky
    skuWorld  the package's axis convention (Vulkan_WorldAxes); the default
    skuYUp    +Y up: XZ is the ground, north along -Z
    skuZUp    +Z up: XY is the ground, north along +Y
  East is +X in all three.  The convention is one setting for the whole
  program (VG_WORLD_Z_UP in VulkanPackage.inc, or vgSetAxisConvention) and
  decides which way up a new camera is.  A model drawn with other axes - a
  Y-up OBJ in a Z-up program, or the reverse - has its ground plane
  somewhere else, and UpAxis turns the sky to match the model.  It turns the
  sky only.  A camera keeps the up it was made with, so on its own a turned
  sky is seen side-on or from underneath: follow a change of UpAxis with
  AlignCamera, which turns the camera the same way about its target - its
  up becomes the sky's, and it orbits about that from then on.

  The sun and moon come from the clock (UseSystemTime, the default) or from
  DateTime / UTCOffset, at Latitude / Longitude.  Longitude defaults to the
  middle of the machine's time zone, Latitude to 40 north: set them for a
  real place.  SetSunPosition places the sun by hand instead.

  The sky is drawn when the scene is.  Nothing redraws it as time passes:
  call Refresh from a timer (once a minute is plenty) for a sky that keeps
  up with the clock.

  Two panoramas are blended by the sun's height - a day sky with clouds, a
  night sky with stars and the Milky Way.  Both are generated here
  (vgSkyGenerateDay / vgSkyGenerateNight) the first time they are needed,
  on every core, and kept for the next load;
  DayTextureFile / NightTextureFile replace either with an equirectangular
  image of your own (north in the middle, the zenith along the top edge).

  The sky is a store of the scene like any other, so ClearScene and
  Load_Begin free it; it puts itself back when the scene is ready again
  (TvgSceneExtension.SceneReady).  It is kept out of GetDataBounds, ZoomAll
  and picking.  It needs a render pass with a depth buffer: it is drawn at
  the far plane with the depth test on, so whatever is drawn before or after
  it stays in front.  A renderer without one draws no sky.

  Main thread, like every edit of a scene.
------------------------------------------------------------------------------}

interface

{$INCLUDE VulkanPackage.inc}

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.DateUtils,
  System.TimeSpan,
  System.Threading,
  Vulkan,
  PasVulkan.Math,
  PasVulkan.Math.Double,
  PasVulkan.Framework,
  Vulkan_Assert,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_Descriptors,
  Vulkan_Components_DataStore,
  Vulkan_Components_Scene_Renderer,
  Vulkan_Components_Camera,
  Vulkan_WorldAxes;

const
  VG_SKY_SHADER          = 'SkyBox';      // SkyBox_vert.spv, SkyBoxDouble_vert.spv, SkyBox_frag.spv
  VG_SKY_TEXTURE_WIDTH   = 4096;          // default TextureWidth
  VG_SKY_MIN_WIDTH       = 256;
  VG_SKY_MAX_WIDTH       = 8192;

type
  TvgSkyMode = (skmAuto, skmDay, skmNight);

  // Which world axis is up in the sky - see the note at the top.
  TvgSkyUpAxis = (skuWorld, skuYUp, skuZUp);

  TvgSkyBox = class;

  { The sky's store.  Made and owned by TvgSkyBox - through its scene, like
    any store. }
  TvgSkyStore = class(TvgObjectStore)
  private
    fSky : TvgSkyBox;
  protected
    Procedure ConfigureGraphicPipeline(GP: TvgGraphicPipeline); Override;
  public
    destructor Destroy; override;
    Procedure UpdateGraphicPipeline(aPipe: TvgGraphicPipeline); Override;
  end;

  { A scene's sky - vgSkyBox(Scene). }
  TvgSkyBox = class(TvgSceneExtension)
  private
    fStore            : TvgSkyStore;
    fObj              : TvgObject;

    fVisible          : Boolean;
    fMode             : TvgSkyMode;
    fUpAxis           : TvgSkyUpAxis;
    fUseSystemTime    : Boolean;
    fDateTime         : TDateTime;
    fUTCOffset        : Double;
    fLatitude         : Double;
    fLongitude        : Double;
    fSunTracksTime    : Boolean;
    fManualAzimuth    : Double;
    fManualElevation  : Double;
    fBrightness       : Single;
    fSunSize          : Single;
    fMoonSize         : Single;
    fTextureWidth     : Integer;
    fDayTextureFile   : String;
    fNightTextureFile : String;

    // The generated panoramas, as BMP files in memory: a load frees the
    // store and its textures, and making them again takes a moment.
    fDayImage         : TMemoryStream;
    fNightImage       : TMemoryStream;

    // What is drawn - see UpdateState.
    fSunDir           : TpvVector3D;     // (east, up, north)
    fMoonDir          : TpvVector3D;
    fDayFactor        : Double;
    fSunVisible       : Boolean;
    fMoonVisible      : Boolean;

    procedure SetVisible(const Value: Boolean);
    procedure SetMode(const Value: TvgSkyMode);
    procedure SetUpAxis(const Value: TvgSkyUpAxis);
    procedure SetUseSystemTime(const Value: Boolean);
    procedure SetDateTime(const Value: TDateTime);
    procedure SetUTCOffset(const Value: Double);
    procedure SetLatitude(const Value: Double);
    procedure SetLongitude(const Value: Double);
    procedure SetSunTracksTime(const Value: Boolean);
    procedure SetBrightness(const Value: Single);
    procedure SetSunSize(const Value: Single);
    procedure SetMoonSize(const Value: Single);
    procedure SetTextureWidth(const Value: Integer);
    procedure SetDayTextureFile(const Value: String);
    procedure SetNightTextureFile(const Value: String);
    function  GetSunAzimuth: Double;
    function  GetSunElevation: Double;
    function  GetMoonAzimuth: Double;
    function  GetMoonElevation: Double;

    // Sun, moon and day factor for the mode, time and place.
    procedure UpdateState;
    // The state into the store's three vertices.
    procedure WriteParams(aNotify: Boolean);
    // Makes the store and adds it to the scene, if it is wanted and the
    // scene can take it now.
    procedure EnsureStore;
    procedure RemoveStore;
    // For a change of textures: the store is made again.
    procedure RebuildStore;
    function  AddTexture(const aName: String; aBinding: Integer; const aFileName: String;
                         aNight: Boolean): Boolean;
    procedure StoreGone;
  public
    constructor Create;
    destructor  Destroy; override;

    procedure SceneCleared; override;
    procedure SceneReady; override;

    { Reads the clock again and redraws.  The property setters do this
      themselves; call it as time passes. }
    procedure Refresh;

    { The sun by hand: degrees, azimuth clockwise from north, elevation above
      the horizon (negative below).  Turns SunTracksTime off. }
    procedure SetSunPosition(aAzimuth, aElevation: Double);

    { The moment the sky shows, in UTC. }
    function  CurrentUTC: TDateTime;

    { The directions drawn, as world vectors - in the axes UpAxis gives. }
    function  SunDirection: TpvVector3D;
    function  MoonDirection: TpvVector3D;

    { True when the sky's up is +Z: UpAxis, or the package's convention for
      skuWorld. }
    function  IsZUp: Boolean;

    { The sky's up as a world vector: +Z or +Y. }
    function  UpVector: TpvVector3D;

    { Turns aCamera - the scene's active camera for nil - about its target
      so that its up is the sky's: the horizon is level again, the eye is as
      far from the target and as high above it as it was, and Orbit goes
      round the sky's up.  For after a change of UpAxis.  False, changing
      nothing, when there is no camera or its up is the sky's already. }
    function  AlignCamera(aCamera: TvgCamera = nil): Boolean;

    { On switches the sky on; it appears as soon as the scene is ready. }
    property Visible : Boolean read fVisible write SetVisible;
    property Mode    : TvgSkyMode read fMode write SetMode;

    { Which world axis is up in the sky.  skuWorld, the package's axis
      convention, unless a model with other axes needs the sky to match it. }
    property UpAxis  : TvgSkyUpAxis read fUpAxis write SetUpAxis;

    { True (the default): the machine's clock.  False: DateTime, a local time
      UTCOffset hours ahead of UTC. }
    property UseSystemTime : Boolean read fUseSystemTime write SetUseSystemTime;
    property DateTime      : TDateTime read fDateTime write SetDateTime;
    property UTCOffset     : Double read fUTCOffset write SetUTCOffset;

    { Degrees; north and east positive. }
    property Latitude  : Double read fLatitude write SetLatitude;
    property Longitude : Double read fLongitude write SetLongitude;

    { True (the default): the sun is where the time and place put it.
      False: where SetSunPosition put it. }
    property SunTracksTime : Boolean read fSunTracksTime write SetSunTracksTime;

    { Where the sun and moon are drawn, in degrees. }
    property SunAzimuth    : Double read GetSunAzimuth;
    property SunElevation  : Double read GetSunElevation;
    property MoonAzimuth   : Double read GetMoonAzimuth;
    property MoonElevation : Double read GetMoonElevation;

    { 0 night .. 1 day, as drawn. }
    property DayFactor : Double read fDayFactor;

    { Multiplies the whole sky.  1. }
    property Brightness : Single read fBrightness write SetBrightness;

    { Diameters in degrees.  Both are about half a degree in the real sky,
      which is smaller than it looks: the defaults are 2.4 and 3. }
    property SunSize  : Single read fSunSize write SetSunSize;
    property MoonSize : Single read fMoonSize write SetMoonSize;

    { Width of the generated night panorama, rounded down to a power of two;
      its height is half that, and the day panorama half each way again.
      VG_SKY_TEXTURE_WIDTH.  The stars are a fixed number of pixels across,
      so a wider picture has sharper ones. }
    property TextureWidth : Integer read fTextureWidth write SetTextureWidth;

    { An equirectangular image to use in place of the generated one; ''
      (the default), or a file that cannot be loaded, for the generated. }
    property DayTextureFile   : String read fDayTextureFile write SetDayTextureFile;
    property NightTextureFile : String read fNightTextureFile write SetNightTextureFile;

    { nil while the sky is not in the scene. }
    property Store : TvgSkyStore read fStore;
  end;

{ aScene's sky: made and added to it the first time when aCreate, nil then
  otherwise.  It is not shown until its Visible is set. }
function vgSkyBox(aScene: TvgScene; aCreate: Boolean = True): TvgSkyBox;

{ Directions to the sun and the moon at aUTC from a place on the ground, as
  (east, up, north) unit vectors: x east, y up, z north.  The sun is good to
  a few hundredths of a degree, the moon to about a degree (no parallax).
  Degrees, north and east positive. }
function vgSunDirection(const aUTC: TDateTime; aLatitude, aLongitude: Double): TpvVector3D;
function vgMoonDirection(const aUTC: TDateTime; aLatitude, aLongitude: Double): TpvVector3D;

{ An (east, up, north) direction from degrees, and back.  Azimuth is
  clockwise from north, 0 .. 360. }
function vgSkyDirection(aAzimuth, aElevation: Double): TpvVector3D;
procedure vgSkyAngles(const aDirection: TpvVector3D; out aAzimuth, aElevation: Double);

{ An (east, up, north) direction in the world's axes: north is
  vgWorldForward, east vgWorldRight, up vgWorldUp.  The second form names
  the axes itself: +Z up with north along +Y, or +Y up with north along -Z. }
function vgSkyToWorld(const aDirection: TpvVector3D): TpvVector3D; overload;
function vgSkyToWorld(const aDirection: TpvVector3D; aZUp: Boolean): TpvVector3D; overload;

{ The generated panoramas, written to aStream as a 24-bit BMP file, aWidth by
  aWidth / 2: equirectangular, north in the middle, the zenith along the top
  edge.  The same picture every time. }
procedure vgSkyGenerateDay(aWidth: Integer; aStream: TStream);
procedure vgSkyGenerateNight(aWidth: Integer; aStream: TStream);

implementation

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

const
  // Fixed places for a sky that is not following the time.
  DAY_SUN_AZIMUTH      = 140.0;
  DAY_SUN_ELEVATION    = 48.0;
  NIGHT_MOON_AZIMUTH   = 215.0;
  NIGHT_MOON_ELEVATION = 42.0;

  // Sines of the sun's height between which night turns to day: from 9
  // degrees below the horizon, when the brighter stars are out, to 2 above.
  NIGHT_SIN            = -0.1564;
  DAY_SIN              =  0.0349;

{ --- small maths ------------------------------------------------------------ }

function Lerp(A, B, T: Single): Single; inline;
begin
  Result := A + (B - A) * T;
end;

function Clamp01(V: Single): Single; inline;
begin
  if V < 0 then Result := 0
  else if V > 1 then Result := 1
  else Result := V;
end;

function SmoothStep(E0, E1, X: Single): Single; inline;
begin
  if E0 = E1 then
  begin
    if X < E0 then Result := 0 else Result := 1;
    Exit;
  end;
  Result := Clamp01((X - E0) / (E1 - E0));
  Result := Result * Result * (3 - 2 * Result);
end;

function Mod360(A: Double): Double;
begin
  Result := A - 360 * Floor(A / 360);
end;

function SinD(A: Double): Double; inline;
begin
  Result := Sin(DegToRad(A));
end;

function CosD(A: Double): Double; inline;
begin
  Result := Cos(DegToRad(A));
end;

function Normalized(const aV: TpvVector3D): TpvVector3D;
var
  L : Double;
begin
  L := Sqrt(aV.x * aV.x + aV.y * aV.y + aV.z * aV.z);
  if L > 0 then
    Result := TpvVector3D.Create(aV.x / L, aV.y / L, aV.z / L)
  else
    Result := TpvVector3D.Create(0, 1, 0);
end;

{ --- astronomy --------------------------------------------------------------- }

// Days since J2000.0.
function DaysSinceJ2000(const aUTC: TDateTime): Double;
begin
  Result := DateTimeToJulianDate(aUTC) - 2451545.0;
end;

// Right ascension and declination (degrees) to (east, up, north).
function EquatorialToSky(aRA, aDec: Double; const aDays, aLatitude, aLongitude: Double): TpvVector3D;
var
  GMST, HA : Double;
begin
  // Greenwich mean sidereal time, in degrees.
  GMST := Mod360(280.46061837 + 360.98564736629 * aDays);
  HA   := GMST + aLongitude - aRA;      // hour angle, positive to the west

  Result := TpvVector3D.Create(
    -CosD(aDec) * SinD(HA),
     SinD(aLatitude) * SinD(aDec) + CosD(aLatitude) * CosD(aDec) * CosD(HA),
     CosD(aLatitude) * SinD(aDec) - SinD(aLatitude) * CosD(aDec) * CosD(HA));
end;

// Ecliptic longitude and latitude (degrees) to right ascension and
// declination (degrees).
procedure EclipticToEquatorial(aLambda, aBeta, aDays: Double; out aRA, aDec: Double);
var
  Eps, X, Y, Z : Double;
begin
  Eps := 23.439 - 0.0000004 * aDays;
  X := CosD(aBeta) * CosD(aLambda);
  Y := CosD(Eps) * CosD(aBeta) * SinD(aLambda) - SinD(Eps) * SinD(aBeta);
  Z := SinD(Eps) * CosD(aBeta) * SinD(aLambda) + CosD(Eps) * SinD(aBeta);
  aRA  := RadToDeg(ArcTan2(Y, X));
  aDec := RadToDeg(ArcSin(EnsureRange(Z, -1, 1)));
end;

function vgSunDirection(const aUTC: TDateTime; aLatitude, aLongitude: Double): TpvVector3D;
var
  N, L, G, Lambda, RA, Dec : Double;
begin
  // The Astronomical Almanac's low-precision sun.
  N      := DaysSinceJ2000(aUTC);
  L      := Mod360(280.460 + 0.9856474 * N);
  G      := Mod360(357.528 + 0.9856003 * N);
  Lambda := L + 1.915 * SinD(G) + 0.020 * SinD(2 * G);
  EclipticToEquatorial(Lambda, 0, N, RA, Dec);
  Result := EquatorialToSky(RA, Dec, N, aLatitude, aLongitude);
end;

function vgMoonDirection(const aUTC: TDateTime; aLatitude, aLongitude: Double): TpvVector3D;
var
  N, T, Lambda, Beta, RA, Dec : Double;
begin
  // The Astronomical Almanac's low-precision moon, seen from the Earth's
  // centre.
  N := DaysSinceJ2000(aUTC);
  T := N / 36525;
  Lambda := 218.32 + 481267.881 * T
          + 6.29 * SinD(135.0 + 477198.87 * T)
          - 1.27 * SinD(259.3 - 413335.36 * T)
          + 0.66 * SinD(235.7 + 890534.22 * T)
          + 0.21 * SinD(269.9 + 954397.74 * T)
          - 0.19 * SinD(357.5 +  35999.05 * T)
          - 0.11 * SinD(186.5 + 966404.03 * T);
  Beta   := 5.13 * SinD( 93.3 + 483202.02 * T)
          + 0.28 * SinD(228.2 + 960400.89 * T)
          - 0.28 * SinD(318.3 +   6003.15 * T)
          - 0.17 * SinD(217.6 - 407332.21 * T);
  EclipticToEquatorial(Lambda, Beta, N, RA, Dec);
  Result := EquatorialToSky(RA, Dec, N, aLatitude, aLongitude);
end;

function vgSkyDirection(aAzimuth, aElevation: Double): TpvVector3D;
begin
  Result := TpvVector3D.Create(CosD(aElevation) * SinD(aAzimuth),
                               SinD(aElevation),
                               CosD(aElevation) * CosD(aAzimuth));
end;

procedure vgSkyAngles(const aDirection: TpvVector3D; out aAzimuth, aElevation: Double);
var
  D : TpvVector3D;
begin
  D := Normalized(aDirection);
  aElevation := RadToDeg(ArcSin(EnsureRange(D.y, -1, 1)));
  if (Abs(D.x) < 1e-12) and (Abs(D.z) < 1e-12) then
    aAzimuth := 0
  else
    aAzimuth := Mod360(RadToDeg(ArcTan2(D.x, D.z)));
end;

function vgSkyToWorld(const aDirection: TpvVector3D): TpvVector3D;
begin
  Result := vgSkyToWorld(aDirection, vgAxisConvention = acZUp);
end;

// The same two mappings SkyBox.frag undoes, and the ones Vulkan_WorldAxes
// gives for each convention.
function vgSkyToWorld(const aDirection: TpvVector3D; aZUp: Boolean): TpvVector3D;
begin
  if aZUp then
    Result := TpvVector3D.Create(aDirection.x, aDirection.z, aDirection.y)
  else
    Result := TpvVector3D.Create(aDirection.x, aDirection.y, -aDirection.z);
end;

{ --- noise ------------------------------------------------------------------- }

function Hash2(X, Y: Integer): Single; inline;
var
  H : Cardinal;
begin
  H := Cardinal(X) * Cardinal(374761393) + Cardinal(Y) * Cardinal(668265263);
  H := (H xor (H shr 15)) * Cardinal($2C1B3C6D);
  H := (H xor (H shr 12)) * Cardinal($297A2D39);
  H := H xor (H shr 15);
  Result := (H and $FFFFFF) * (1 / 16777216);
end;

function Hash3(X, Y, Z: Integer): Single; inline;
var
  H : Cardinal;
begin
  H := Cardinal(X) * Cardinal(374761393) + Cardinal(Y) * Cardinal(668265263) + Cardinal(Z) * Cardinal(2147483647);
  H := (H xor (H shr 15)) * Cardinal($2C1B3C6D);
  H := (H xor (H shr 12)) * Cardinal($297A2D39);
  H := H xor (H shr 15);
  Result := (H and $FFFFFF) * (1 / 16777216);
end;

function Noise2(X, Y: Single): Single;
var
  IX, IY : Integer;
  FX, FY : Single;
begin
  IX := Floor(X);  FX := X - IX;
  IY := Floor(Y);  FY := Y - IY;
  FX := FX * FX * (3 - 2 * FX);
  FY := FY * FY * (3 - 2 * FY);
  Result := Lerp(Lerp(Hash2(IX, IY),     Hash2(IX + 1, IY),     FX),
                 Lerp(Hash2(IX, IY + 1), Hash2(IX + 1, IY + 1), FX), FY);
end;

function Noise3(X, Y, Z: Single): Single;
var
  IX, IY, IZ : Integer;
  FX, FY, FZ : Single;
begin
  IX := Floor(X);  FX := X - IX;
  IY := Floor(Y);  FY := Y - IY;
  IZ := Floor(Z);  FZ := Z - IZ;
  FX := FX * FX * (3 - 2 * FX);
  FY := FY * FY * (3 - 2 * FY);
  FZ := FZ * FZ * (3 - 2 * FZ);
  Result := Lerp(
    Lerp(Lerp(Hash3(IX, IY,     IZ),     Hash3(IX + 1, IY,     IZ),     FX),
         Lerp(Hash3(IX, IY + 1, IZ),     Hash3(IX + 1, IY + 1, IZ),     FX), FY),
    Lerp(Lerp(Hash3(IX, IY,     IZ + 1), Hash3(IX + 1, IY,     IZ + 1), FX),
         Lerp(Hash3(IX, IY + 1, IZ + 1), Hash3(IX + 1, IY + 1, IZ + 1), FX), FY), FZ);
end;

// Fractal sums, 0 .. 1.
function Fbm2(X, Y: Single; aOctaves: Integer): Single;
var
  I        : Integer;
  Amp, Sum : Single;
begin
  Result := 0;  Amp := 0.5;  Sum := 0;
  for I := 1 to aOctaves do
  begin
    Result := Result + Amp * Noise2(X, Y);
    Sum    := Sum + Amp;
    // Turned as well as scaled, so the lattice does not line up.
    X := X * 2.03 + 17.1;
    Y := Y * 2.03 - 9.4;
    Amp := Amp * 0.5;
  end;
  Result := Result / Sum;
end;

function Fbm3(X, Y, Z: Single; aOctaves: Integer): Single;
var
  I        : Integer;
  Amp, Sum : Single;
begin
  Result := 0;  Amp := 0.5;  Sum := 0;
  for I := 1 to aOctaves do
  begin
    Result := Result + Amp * Noise3(X, Y, Z);
    Sum    := Sum + Amp;
    X := X * 2.03 + 17.1;
    Y := Y * 2.03 - 9.4;
    Z := Z * 2.03 + 3.7;
    Amp := Amp * 0.5;
  end;
  Result := Result / Sum;
end;

{ --- panoramas --------------------------------------------------------------- }

type
  TSkyRGB = record
    R, G, B : Single;
  end;
  TSkyPixels = TArray<TSkyRGB>;

function RGB(R, G, B: Single): TSkyRGB; inline;
begin
  Result.R := R;  Result.G := G;  Result.B := B;
end;

function Mix(const A, B: TSkyRGB; T: Single): TSkyRGB; inline;
begin
  Result.R := A.R + (B.R - A.R) * T;
  Result.G := A.G + (B.G - A.G) * T;
  Result.B := A.B + (B.B - A.B) * T;
end;

function SkyWidth(aWidth: Integer): Integer;
begin
  aWidth := EnsureRange(aWidth, VG_SKY_MIN_WIDTH, VG_SKY_MAX_WIDTH);
  Result := VG_SKY_MIN_WIDTH;
  while Result * 2 <= aWidth do
    Result := Result * 2;
end;

// 24-bit, bottom-up: what every reader of the format takes.
procedure WriteBMP(const aPixels: TSkyPixels; aWidth, aHeight: Integer; aStream: TStream);
type
  TFileHeader = packed record
    bfType      : Word;
    bfSize      : Cardinal;
    bfReserved  : Cardinal;
    bfOffBits   : Cardinal;
  end;
  TInfoHeader = packed record
    biSize, biWidth, biHeight : Integer;
    biPlanes, biBitCount      : Word;
    biCompression, biSizeImage,
    biXPelsPerMeter, biYPelsPerMeter,
    biClrUsed, biClrImportant : Integer;
  end;
var
  FH     : TFileHeader;
  IH     : TInfoHeader;
  Stride : Integer;
  Row    : TBytes;
  X, Y   : Integer;
  P      : PByte;

  function ToByte(V: Single): Byte; inline;
  begin
    if V <= 0 then Result := 0
    else if V >= 1 then Result := 255
    else Result := Round(V * 255);
  end;

begin
  Stride := ((aWidth * 3 + 3) div 4) * 4;

  FH := Default(TFileHeader);
  FH.bfType    := $4D42;     // 'BM'
  FH.bfOffBits := SizeOf(FH) + SizeOf(IH);
  FH.bfSize    := FH.bfOffBits + Cardinal(Stride) * Cardinal(aHeight);

  IH := Default(TInfoHeader);
  IH.biSize      := SizeOf(IH);
  IH.biWidth     := aWidth;
  IH.biHeight    := aHeight;
  IH.biPlanes    := 1;
  IH.biBitCount  := 24;
  IH.biSizeImage := Stride * aHeight;
  IH.biXPelsPerMeter := 2835;
  IH.biYPelsPerMeter := 2835;

  aStream.WriteBuffer(FH, SizeOf(FH));
  aStream.WriteBuffer(IH, SizeOf(IH));

  SetLength(Row, Stride);
  for Y := aHeight - 1 downto 0 do
  begin
    P := @Row[0];
    for X := 0 to aWidth - 1 do
      with aPixels[Y * aWidth + X] do
      begin
        P^ := ToByte(B);  Inc(P);
        P^ := ToByte(G);  Inc(P);
        P^ := ToByte(R);  Inc(P);
      end;
    aStream.WriteBuffer(Row[0], Stride);
  end;
end;

// Sines and cosines of each column's azimuth: north in the middle of the
// picture.
procedure ColumnAzimuths(aWidth: Integer; out aSin, aCos: TArray<Single>);
var
  X : Integer;
  A : Double;
begin
  SetLength(aSin, aWidth);
  SetLength(aCos, aWidth);
  for X := 0 to aWidth - 1 do
  begin
    A := ((X + 0.5) / aWidth - 0.5) * 2 * Pi;
    aSin[X] := Sin(A);
    aCos[X] := Cos(A);
  end;
end;

// One row of the day sky.  Rows are made on several threads at once
// (TParallel.For): each writes its own pixels and reads nothing another
// writes.
procedure DayRow(Y, W, H: Integer; const aPixels: TSkyPixels; const aSin, aCos: TArray<Single>);
const
  CLOUD_SCALE = 1.25;
  ZENITH : TSkyRGB = (R: 0.14; G: 0.34; B: 0.72);
  MIDDLE : TSkyRGB = (R: 0.28; G: 0.53; B: 0.89);
  HAZE   : TSkyRGB = (R: 0.74; G: 0.85; B: 0.95);
  GROUND : TSkyRGB = (R: 0.27; G: 0.30; B: 0.34);
var
  X                     : Integer;
  El, Up, CosEl, T, K   : Single;
  PX, PY, N, Big, Cover : Single;
  Dens, Cirrus          : Single;
  Col, Cloud, Clear     : TSkyRGB;
begin
  El    := (0.5 - (Y + 0.5) / H) * Pi;
  Up    := Sin(El);
  CosEl := Cos(El);

  if Up < 0 then
  begin
    // Below the horizon: haze, darkening into the ground.
    Col := Mix(Mix(HAZE, RGB(0.60, 0.68, 0.76), SmoothStep(0.0, 0.04, -Up)),
               GROUND, SmoothStep(0.0, 0.30, -Up));
    for X := 0 to W - 1 do
      aPixels[Y * W + X] := Col;
    Exit;
  end;

  // Deep blue overhead, paling towards a hazy horizon.
  T     := 1 - Up;
  Clear := Mix(ZENITH, MIDDLE, T * T);
  Clear := Mix(Clear, HAZE, Power(T, 7.0));
  K     := CLOUD_SCALE / (Up + 0.11);

  for X := 0 to W - 1 do
  begin
    Col := Clear;

    // A flat layer of cloud seen from below: the further towards the
    // horizon, the more of it is crossed.  A function of the direction
    // alone, so the picture joins up at its edges.
    PX := CosEl * aSin[X] * K;
    PY := CosEl * aCos[X] * K;

    N     := Fbm2(PX + 11.3, PY - 4.7, 6);
    Big   := Fbm2(PX * 0.31 + 53.0, PY * 0.31 + 21.0, 3);
    Dens  := N * 0.72 + Big * 0.45;
    Cover := SmoothStep(0.56, 0.72, Dens) * SmoothStep(0.0, 0.11, Up);

    if Cover > 0 then
    begin
      // White where thin, grey underneath where thick; hazed far away.
      Cloud := Mix(RGB(1.0, 1.0, 1.0), RGB(0.70, 0.74, 0.82), SmoothStep(0.66, 0.92, Dens));
      Cloud := Mix(HAZE, Cloud, SmoothStep(0.0, 0.28, Up));
      Col   := Mix(Col, Cloud, Cover * 0.96);
    end;

    // High, thin, streaked cloud.
    Cirrus := Fbm2(PX * 0.42 + 101.0, PY * 1.9 + 33.0, 4);
    Cirrus := SmoothStep(0.56, 0.80, Cirrus) * SmoothStep(0.06, 0.35, Up) * 0.22;
    Col    := Mix(Col, RGB(1.0, 1.0, 1.0), Cirrus);

    aPixels[Y * W + X] := Col;
  end;
end;

procedure vgSkyGenerateDay(aWidth: Integer; aStream: TStream);
var
  W, H         : Integer;
  Pixels       : TSkyPixels;
  SinAz, CosAz : TArray<Single>;
begin
  W := SkyWidth(aWidth);
  H := W div 2;
  SetLength(Pixels, W * H);
  ColumnAzimuths(W, SinAz, CosAz);

  TParallel.For(0, H - 1,
    procedure(Y: Integer)
    begin
      DayRow(Y, W, H, Pixels, SinAz, CosAz);
    end);

  WriteBMP(Pixels, W, H, aStream);
end;

const
  // Half-width of the Milky Way's band, in radians of galactic latitude.
  BAND_WIDTH = 0.21;
  GROUND_NIGHT : TSkyRGB = (R: 0.010; G: 0.012; B: 0.018);

// How much of the Milky Way a direction is in, 0 .. 1.  aSinLat is the sine
// of its galactic latitude: its dot product with the pole.
function BandOf(aSinLat: Single; out aLat: Single): Single; inline;
begin
  aLat := 0;
  // Past 2.4 widths it is under 0.004: not worth an ArcSin.
  if Abs(aSinLat) > 0.485 then Exit(0);
  aLat   := ArcSin(aSinLat);
  Result := Exp(-Sqr(aLat / BAND_WIDTH));
end;

// One row of the night sky, without its stars - see DayRow.
procedure NightRow(Y, W, H: Integer; const aPixels: TSkyPixels; const aSin, aCos: TArray<Single>;
                   const aPole, aCentre: TpvVector3D);
var
  X                       : Integer;
  El, Up, CosEl, T        : Single;
  DX, DY, DZ              : Single;
  B, Band, N1, N2, N3     : Single;
  Core, Lane, Inten, Mag  : Single;
  Col, Tint, Base         : TSkyRGB;
begin
  El    := (0.5 - (Y + 0.5) / H) * Pi;
  Up    := Sin(El);
  CosEl := Cos(El);

  // Nothing shines through the ground (the stars stop there too).
  if Up < -0.04 then
  begin
    for X := 0 to W - 1 do
      aPixels[Y * W + X] := GROUND_NIGHT;
    Exit;
  end;

  // Nearly black overhead, a little lighter and bluer low down.
  T    := 1 - Max(Up, 0);
  Base := Mix(RGB(0.004, 0.007, 0.020), RGB(0.020, 0.032, 0.062), T * T * T);
  DY   := Up;

  for X := 0 to W - 1 do
  begin
    DX  := CosEl * aSin[X];
    DZ  := CosEl * aCos[X];
    Col := Base;

    Band := BandOf(DX * aPole.x + DY * aPole.y + DZ * aPole.z, B);
    if Band > 0.004 then
    begin
      N1   := Fbm3(DX * 3.4 + 5.0, DY * 3.4 + 1.0, DZ * 3.4 + 9.0, 5);
      Core := Exp(-(1 - (DX * aCentre.x + DY * aCentre.y + DZ * aCentre.z)) / 0.11);

      Inten := Band * (0.16 + 0.95 * SmoothStep(0.30, 0.74, N1)) * (1 + 1.7 * Core);
      // Dust: dark lanes along the middle of the band.
      if Abs(B) < 0.16 then
      begin
        N2    := Fbm3(DX * 8.5 + 31.0, DY * 8.5 + 17.0, DZ * 8.5 + 2.0, 4);
        Lane  := Exp(-Sqr(B / 0.06)) * SmoothStep(0.44, 0.60, N2);
        Inten := Inten * (1 - 0.78 * Lane);
      end;

      Tint  := Mix(RGB(0.40, 0.48, 0.78), RGB(0.96, 0.78, 0.56), Clamp01(Core * 1.3));
      Col.R := Col.R + Tint.R * Inten * 0.38;
      Col.G := Col.G + Tint.G * Inten * 0.38;
      Col.B := Col.B + Tint.B * Inten * 0.38;

      // A few faint glowing clouds.
      if Band > 0.05 then
      begin
        N3    := Fbm3(DX * 2.3 + 40.0, DY * 2.3 + 7.0, DZ * 2.3 + 23.0, 3);
        N3    := SmoothStep(0.60, 0.78, N3) * Band * 0.20;
        Col.R := Col.R + 0.42 * N3;
        Col.G := Col.G + 0.10 * N3;
        Col.B := Col.B + 0.26 * N3;
      end;
    end;

    // Star dust: single pixels, thick in the band and thin outside it.
    // Fewer per pixel towards the zenith, where a pixel covers less sky.
    if Hash2(X, Y) > 1 - (0.0030 + 0.026 * Band) * CosEl then
    begin
      Mag   := 0.10 + 0.35 * Hash2(X + 977, Y + 131);
      Col.R := Col.R + Mag;
      Col.G := Col.G + Mag;
      Col.B := Col.B + Mag * 1.08;
    end;

    aPixels[Y * W + X] := Col;
  end;
end;

// Adds one star, a small round blur, at (aU, aV) of the picture.
procedure SplatStar(const aPixels: TSkyPixels; W, H: Integer; aU, aV, aSigma, aBright: Single;
                    const aColor: TSkyRGB; aCosEl: Single);
var
  CX, CY, SX, Reach, WY, Wgt : Single;
  X0, X1, Y0, Y1, XX, YY, XW : Integer;
  P                          : ^TSkyRGB;
begin
  CX := aU * W - 0.5;
  CY := aV * H - 0.5;
  // Wider towards the poles, where the picture is stretched, so the star is
  // round in the sky.
  SX    := 1 / Max(aCosEl, 0.03);
  Reach := aSigma * 3;
  Y0 := Max(0, Floor(CY - Reach));
  Y1 := Min(H - 1, Ceil(CY + Reach));
  X0 := Floor(CX - Reach * SX);
  X1 := Ceil(CX + Reach * SX);
  for YY := Y0 to Y1 do
  begin
    WY := Sqr(YY - CY);
    for XX := X0 to X1 do
    begin
      Wgt := Exp(-(Sqr((XX - CX) / SX) + WY) / (2 * aSigma * aSigma)) * aBright;
      if Wgt < 0.004 then Continue;
      XW := ((XX mod W) + W) mod W;       // round the seam
      P  := @aPixels[YY * W + XW];
      P^.R := P^.R + aColor.R * Wgt;
      P^.G := P^.G + aColor.G * Wgt;
      P^.B := P^.B + aColor.B * Wgt;
    end;
  end;
end;

procedure vgSkyGenerateNight(aWidth: Integer; aStream: TStream);
var
  W, H, I, Count, X, Y    : Integer;
  Pixels                  : TSkyPixels;
  SinAz, CosAz            : TArray<Single>;
  Pole, Centre, H1, H2    : TpvVector3D;
  Tint                    : TSkyRGB;
  Seed                    : Cardinal;
  Z, Phi, SinE, Mag       : Single;
  Sigma, Kind, Keep       : Single;
  Bright, Lat, Up, Fade   : Single;

  function Rnd: Single;
  begin
    Seed := Seed * 1664525 + 1013904223;
    Result := (Seed shr 8) * (1 / 16777216);
  end;

begin
  W := SkyWidth(aWidth);
  H := W div 2;
  SetLength(Pixels, W * H);
  ColumnAzimuths(W, SinAz, CosAz);

  // The Milky Way lies along the great circle about Pole, brightest at
  // Centre - placed for the picture, not from a star chart.
  Pole   := Normalized(TpvVector3D.Create(0.42, 0.52, 0.74));
  H1     := Normalized(TpvVector3D.Create(Pole.z, 0, -Pole.x));     // in the band, on the horizon
  H2     := TpvVector3D.Create(Pole.y * H1.z - Pole.z * H1.y,       // in the band, highest
                               Pole.z * H1.x - Pole.x * H1.z,
                               Pole.x * H1.y - Pole.y * H1.x);
  if H2.y < 0 then
    H2 := TpvVector3D.Create(-H2.x, -H2.y, -H2.z);
  Centre := Normalized(TpvVector3D.Create(H1.x * 0.70 + H2.x * 0.71,
                                          H1.y * 0.70 + H2.y * 0.71,
                                          H1.z * 0.70 + H2.z * 0.71));

  TParallel.For(0, H - 1,
    procedure(Row: Integer)
    begin
      NightRow(Row, W, H, Pixels, SinAz, CosAz, Pole, Centre);
    end);

  // Stars, spread evenly over the sky and thicker along the band.  Their
  // blur is a fixed number of pixels, so a wider picture has sharper stars.
  Seed  := 20240229;
  Count := Round(2048 * 5.0);
  I := 0;
  while I < Count do
  begin
    Z    := Rnd;                         // above the horizon only
    Phi  := Rnd * 2 * Pi;
    SinE := Sqrt(Max(0, 1 - Z * Z));
    Mag  := Rnd;
    Kind := Rnd;
    Keep := Rnd;
    if Keep > 0.40 + 0.60 * BandOf(SinE * Sin(Phi) * Pole.x + Z * Pole.y + SinE * Cos(Phi) * Pole.z, Lat) then
      Continue;
    Inc(I);

    // Nearly all faint, a few bright.
    Bright := 0.10 + 0.22 * Mag;
    Mag    := Power(Mag, 24.0);
    Bright := Bright + 1.75 * Mag;
    Sigma  := 0.50 + 0.60 * Mag;

    if      Kind < 0.18 then Tint := RGB(0.70, 0.80, 1.00)     // blue-white
    else if Kind < 0.72 then Tint := RGB(1.00, 1.00, 0.96)
    else if Kind < 0.92 then Tint := RGB(1.00, 0.91, 0.70)
    else                     Tint := RGB(1.00, 0.72, 0.52);    // orange

    SplatStar(Pixels, W, H, Phi / (2 * Pi), 0.5 - ArcSin(Z) / Pi, Sigma, Bright, Tint, SinE);
  end;

  // The stars fade out into the ground with everything else.
  for Y := 0 to H - 1 do
  begin
    Up   := Sin((0.5 - (Y + 0.5) / H) * Pi);
    Fade := SmoothStep(-0.035, 0.02, Up);
    if Fade >= 1 then Continue;
    for X := 0 to W - 1 do
      Pixels[Y * W + X] := Mix(GROUND_NIGHT, Pixels[Y * W + X], Fade);
  end;

  WriteBMP(Pixels, W, H, aStream);
end;

{ TvgSkyStore }

destructor TvgSkyStore.Destroy;
begin
  // Freed by its scene (ClearScene, RemoveDataStore) or anyone else: the sky
  // must not keep the pointer.
  if Assigned(fSky) then
    fSky.StoreGone;
  inherited;
end;

procedure TvgSkyStore.ConfigureGraphicPipeline(GP: TvgGraphicPipeline);
begin
  // The sky's own variants: a double view-projection or not.  It is never
  // picked, so there is one fragment shader whatever the renderer's
  // SelectMode.
  if Assigned(GP) and Assigned(GP.Renderer) and GP.Renderer.UsesDoubleViewProjection then
    fShaderBaseVertName := VG_SKY_SHADER + 'Double'
  else
    fShaderBaseVertName := VG_SKY_SHADER;
  fShaderBaseFragName := VG_SKY_SHADER;

  inherited;
end;

procedure TvgSkyStore.UpdateGraphicPipeline(aPipe: TvgGraphicPipeline);
begin
  inherited UpdateGraphicPipeline(aPipe);
  if not Assigned(aPipe) then Exit;

  // No depth buffer on this renderer, so nothing can be drawn behind
  // anything - and stores are not drawn in any set order, so the sky would
  // cover whatever came before it.  Both faces culled: it draws nothing.
  if not aPipe.DepthStencil.DepthTestEnable then
  begin
    aPipe.Rasterizer.CullMode := CULL_FRONT_AND_BACK;
    Exit;
  end;

  // Drawn at the far plane, which is what the depth buffer is cleared to:
  // tested so that it stays behind everything, equal allowed so that it
  // shows at all, and never written.
  aPipe.DepthStencil.DepthWriteEnable := False;
  if aPipe.DepthStencil.DepthCompareOp = CO_LESS then
    aPipe.DepthStencil.DepthCompareOp := CO_LESS_OR_EQUAL;
end;

{ TvgSkyBox }

constructor TvgSkyBox.Create;
var
  Offset : TTimeSpan;
  NowLoc : TDateTime;
begin
  inherited Create;
  fMode          := skmAuto;
  fUseSystemTime := True;
  fSunTracksTime := True;
  fBrightness    := 1.0;
  fSunSize       := 2.4;
  fMoonSize      := 3.0;
  fTextureWidth  := VG_SKY_TEXTURE_WIDTH;

  fManualAzimuth   := DAY_SUN_AZIMUTH;
  fManualElevation := DAY_SUN_ELEVATION;

  // The place, as near as the time zone says: the middle of the zone's
  // standard time.  The latitude is a guess.
  NowLoc     := Now;
  Offset     := TTimeZone.Local.GetUtcOffset(NowLoc);
  fDateTime  := NowLoc;
  fUTCOffset := Offset.TotalHours;
  fLongitude := fUTCOffset * 15;
  if TTimeZone.Local.IsDaylightTime(NowLoc) then
    fLongitude := fLongitude - 15;
  fLongitude := EnsureRange(fLongitude, -180, 180);
  fLatitude  := 40;

  UpdateState;
end;

destructor TvgSkyBox.Destroy;
begin
  // The scene frees its extensions first and its stores after: the store
  // only has to forget the sky.
  if Assigned(fStore) then
    fStore.fSky := nil;
  fStore := nil;
  fObj   := nil;
  FreeAndNil(fDayImage);
  FreeAndNil(fNightImage);
  inherited;
end;

procedure TvgSkyBox.StoreGone;
begin
  fStore := nil;
  fObj   := nil;
end;

procedure TvgSkyBox.SceneCleared;
begin
  // ClearScene frees the store next; its destructor says so (StoreGone).
end;

procedure TvgSkyBox.SceneReady;
begin
  EnsureStore;
end;

function TvgSkyBox.CurrentUTC: TDateTime;
begin
  if fUseSystemTime then
    Result := TTimeZone.Local.ToUniversalTime(Now)
  else
    Result := fDateTime - fUTCOffset / 24;
end;

procedure TvgSkyBox.UpdateState;
var
  UTC        : TDateTime;
  Sun, Moon  : TpvVector3D;
  Side       : TpvVector3D;
begin
  UTC  := CurrentUTC;
  Moon := vgMoonDirection(UTC, fLatitude, fLongitude);
  if fSunTracksTime then
    Sun := vgSunDirection(UTC, fLatitude, fLongitude)
  else
    Sun := vgSkyDirection(fManualAzimuth, fManualElevation);

  fSunVisible  := True;
  fMoonVisible := True;

  case fMode of
    skmDay:
      begin
        // A sun still below, or only just above, the horizon would light a
        // day sky from underneath.
        if Sun.y < SinD(8) then
          Sun := vgSkyDirection(DAY_SUN_AZIMUTH, DAY_SUN_ELEVATION);
        fDayFactor := 1;
      end;

    skmNight:
      begin
        if Moon.y < SinD(10) then
          Moon := vgSkyDirection(NIGHT_MOON_AZIMUTH, NIGHT_MOON_ELEVATION);
        // The sun only lights the moon here.  A real one that is up would
        // light it from the wrong side of the night: put it below, off to
        // one side, for a moon a little past half.
        if Sun.y > NIGHT_SIN then
        begin
          Side := Normalized(TpvVector3D.Create(Moon.z, 0, -Moon.x));
          Sun  := Normalized(TpvVector3D.Create(Side.x * 0.8 - Moon.x * 0.35,
                                                -0.45,
                                                Side.z * 0.8 - Moon.z * 0.35));
        end;
        fSunVisible := False;
        fDayFactor  := 0;
      end;
  else
    fDayFactor := SmoothStep(NIGHT_SIN, DAY_SIN, Sun.y);
  end;

  fSunDir  := Sun;
  fMoonDir := Moon;
end;

procedure TvgSkyBox.WriteParams(aNotify: Boolean);
const
  // One triangle covering the screen, at the far plane.
  PX : array[0..2] of Single = (-1,  3, -1);
  PY : array[0..2] of Single = (-1, -1,  3);
var
  I    : Integer;
  ZUp  : Single;
begin
  if not (Assigned(fStore) and Assigned(fObj)) then Exit;

  if IsZUp then ZUp := 1 else ZUp := 0;

  if fObj.VertexCount > 0 then
    fObj.Reset;

  for I := 0 to 2 do
  begin
    fObj.AddVertex;
    fObj.SetVertexPosition(PX[I], PY[I], 1.0);
    fObj.SetVertexColor(fDayFactor, ZUp, Ord(fSunVisible), Ord(fMoonVisible));
    fObj.SetVertexNormal(fSunDir.x, fSunDir.y, fSunDir.z);
    fObj.SetVertexTangent(fMoonDir.x, fMoonDir.y, fMoonDir.z);
    fObj.SetVertexBiTangent(fBrightness, fSunSize, fMoonSize);
  end;

  // Its positions are clip coordinates, not a place in the world: never
  // culled, and no bounds for anything to zoom to.
  fStore.SetObjectCullMode(fObj.ObjIndex, cmNever);

  if aNotify and Assigned(Scene) then
    Scene.NotifyDataChanged(fStore);
end;

function TvgSkyBox.AddTexture(const aName: String; aBinding: Integer; const aFileName: String;
                              aNight: Boolean): Boolean;
var
  Use   : TvgResourceUse;
  DI    : TvgDescriptorItem;
  Tex   : TvgDescriptorArray_Texture;
  Image : TMemoryStream;
  Index : Integer;
begin
  Result := False;
  if not Assigned(fStore.ObjectStoreRes) then Exit;

  // As TvgSceneLoaderStorer.PrepareTextureDescriptor does for a loader.
  if not (RU_OBJECTSTORE in fStore.ResourceUse) then
  begin
    Use := fStore.ResourceUse;
    Include(Use, RU_OBJECTSTORE);
    fStore.ResourceUse := Use;
  end;

  DI := fStore.ObjectStoreRes.Descriptors.Add;
  if not Assigned(DI) then Exit;
  DI.DescriptorName := TvgDescriptorArray_Texture.GetPropertyName;
  if not (Assigned(DI.Descriptor) and (DI.Descriptor is TvgDescriptorArray_Texture)) then Exit;
  DI.Name := aName;

  Tex              := TvgDescriptorArray_Texture(DI.Descriptor);
  Tex.Name         := aName;
  Tex.ResourceType := RT_GROUPTEX;
  Tex.FrameCount   := 1;
  Tex.BindingCount := 1;
  Tex.Binding      := aBinding;

  Index := -1;
  if (aFileName <> '') and FileExists(aFileName) then
    Index := Tex.AddSharedTexture(aName, aFileName);

  if Index < 0 then
  begin
    if aNight then
    begin
      if not Assigned(fNightImage) then
      begin
        fNightImage := TMemoryStream.Create;
        vgSkyGenerateNight(fTextureWidth, fNightImage);        // stars want every pixel
      end;
      Image := fNightImage;
    end
    else
    begin
      if not Assigned(fDayImage) then
      begin
        fDayImage := TMemoryStream.Create;
        vgSkyGenerateDay(fTextureWidth div 2, fDayImage);      // clouds are soft: half is plenty
      end;
      Image := fDayImage;
    end;
    Image.Position := 0;
    Index := Tex.AddSharedTexture(aName, Image);
  end;
  if Index < 0 then Exit;

  // Round the seam at the back of the panorama, and no wrapping over the
  // poles.
  if Assigned(Tex.TextureData[0]) then
  begin
    Tex.TextureData[0].WrapModeU := TpvVulkanTextureWrapMode.WrappedRepeat;
    Tex.TextureData[0].WrapModeV := TpvVulkanTextureWrapMode.ClampToEdge;
  end;

  Result := True;
end;

procedure TvgSkyBox.EnsureStore;
var
  S : TvgSkyStore;
begin
  if Assigned(fStore) or not fVisible then Exit;
  if not Assigned(Scene) then Exit;
  if csDestroying in Scene.ComponentState then Exit;
  // While loading, Load_End comes back here (SceneReady).
  if Scene.SceneState <> SS_READY then Exit;

  UpdateState;

  S := TvgSkyStore.Create(nil);          // the scene owns it once added
  fStore := S;
  S.fSky := Self;
  try
    S.SetupVertexAttributes([vdtPosition, vdtColor, vdtNormal, vdtTangent, vdtBiTangent]);
    S.SetIndexType(itNONE);
    S.Topology        := TRIANGLE_LIST;
    S.BaseVertName    := VG_SKY_SHADER;
    S.BaseFragName    := VG_SKY_SHADER;
    S.InDataBounds    := False;
    S.ColorOverrideON := False;

    if not (AddTexture('DaySky',   0, fDayTextureFile,   False) and
            AddTexture('NightSky', 1, fNightTextureFile, True)) then
      raise EvgSceneEditException.Create('TvgSkyBox: the sky textures could not be made');

    fObj := S.AddObject(False);
    fObj.Selectable := False;
    WriteParams(False);

    if not Scene.AddDataStoreLive(S) then
      raise EvgSceneEditException.Create('TvgSkyBox: the scene did not take the sky');
  except
    on E: Exception do
    begin
      // Not in the scene: nothing else will free it.  Its destructor clears
      // fStore and fObj (StoreGone).
      if Assigned(fStore) then
        S.Free;
      CustomAssert(False, E.Message);
    end;
  end;
end;

procedure TvgSkyBox.RemoveStore;
var
  S : TvgSkyStore;
begin
  S := fStore;
  if not Assigned(S) then Exit;

  if Assigned(Scene) and not (csDestroying in Scene.ComponentState) and
     (Scene.SceneData.IndexOf(S) >= 0) then
    Scene.RemoveDataStore(S)     // waits for frames drawing it, then frees it
  else
    S.Free;
  // Either way its destructor has cleared fStore and fObj.
end;

procedure TvgSkyBox.RebuildStore;
begin
  if not Assigned(fStore) then Exit;
  RemoveStore;
  EnsureStore;
end;

procedure TvgSkyBox.Refresh;
begin
  UpdateState;
  if Assigned(fStore) then
    WriteParams(True)
  else
    EnsureStore;
end;

procedure TvgSkyBox.SetSunPosition(aAzimuth, aElevation: Double);
begin
  fManualAzimuth   := Mod360(aAzimuth);
  fManualElevation := EnsureRange(aElevation, -90, 90);
  fSunTracksTime   := False;
  Refresh;
end;

function TvgSkyBox.SunDirection: TpvVector3D;
begin
  Result := vgSkyToWorld(fSunDir, IsZUp);
end;

function TvgSkyBox.MoonDirection: TpvVector3D;
begin
  Result := vgSkyToWorld(fMoonDir, IsZUp);
end;

function TvgSkyBox.IsZUp: Boolean;
begin
  case fUpAxis of
    skuYUp : Result := False;
    skuZUp : Result := True;
  else
    Result := vgAxisConvention = acZUp;
  end;
end;

function TvgSkyBox.GetSunAzimuth: Double;
var
  El : Double;
begin
  vgSkyAngles(fSunDir, Result, El);
end;

function TvgSkyBox.GetSunElevation: Double;
var
  Az : Double;
begin
  vgSkyAngles(fSunDir, Az, Result);
end;

function TvgSkyBox.GetMoonAzimuth: Double;
var
  El : Double;
begin
  vgSkyAngles(fMoonDir, Result, El);
end;

function TvgSkyBox.GetMoonElevation: Double;
var
  Az : Double;
begin
  vgSkyAngles(fMoonDir, Az, Result);
end;

procedure TvgSkyBox.SetVisible(const Value: Boolean);
begin
  if fVisible = Value then Exit;
  fVisible := Value;
  if fVisible then
    EnsureStore
  else
    RemoveStore;
end;

function TvgSkyBox.UpVector: TpvVector3D;
begin
  Result := vgSkyToWorld(TpvVector3D.Create(0, 1, 0), IsZUp);
end;

function TvgSkyBox.AlignCamera(aCamera: TvgCamera): Boolean;
var
  OldUp, NewUp, Axis, V, KxV : TpvVector3D;
  C, S, L, KdV               : Double;
begin
  Result := False;
  if not Assigned(aCamera) and Assigned(Scene) and Assigned(Scene.Cameras) then
    aCamera := Scene.Cameras.GetActiveCamera;
  if not Assigned(aCamera) then Exit;

  OldUp := Normalized(aCamera.UpVector);
  NewUp := UpVector;
  C := OldUp.x * NewUp.x + OldUp.y * NewUp.y + OldUp.z * NewUp.z;
  if C > 1 - 1e-9 then Exit;

  // The rotation that takes the old up to the new one, about the axis at
  // right angles to both.
  Axis := TpvVector3D.Create(OldUp.y * NewUp.z - OldUp.z * NewUp.y,
                             OldUp.z * NewUp.x - OldUp.x * NewUp.z,
                             OldUp.x * NewUp.y - OldUp.y * NewUp.x);
  S := Sqrt(Axis.x * Axis.x + Axis.y * Axis.y + Axis.z * Axis.z);
  if S < 1e-9 then
  begin
    // Upside down: half a turn about any axis across the old up.
    if Abs(OldUp.x) < 0.9 then
      Axis := TpvVector3D.Create(0, OldUp.z, -OldUp.y)        // (1,0,0) x OldUp
    else
      Axis := TpvVector3D.Create(-OldUp.z, 0, OldUp.x);       // (0,1,0) x OldUp
    S := 0;
    C := -1;
  end;
  Axis := Normalized(Axis);

  // The eye, turned about the target (Rodrigues).
  V   := TpvVector3D.Create(aCamera.Position.x - aCamera.Target.x,
                            aCamera.Position.y - aCamera.Target.y,
                            aCamera.Position.z - aCamera.Target.z);
  KxV := TpvVector3D.Create(Axis.y * V.z - Axis.z * V.y,
                            Axis.z * V.x - Axis.x * V.z,
                            Axis.x * V.y - Axis.y * V.x);
  KdV := Axis.x * V.x + Axis.y * V.y + Axis.z * V.z;
  L   := KdV * (1 - C);
  V   := TpvVector3D.Create(V.x * C + KxV.x * S + Axis.x * L,
                            V.y * C + KxV.y * S + Axis.y * L,
                            V.z * C + KxV.z * S + Axis.z * L);

  aCamera.Position := TpvVector3D.Create(aCamera.Target.x + V.x,
                                         aCamera.Target.y + V.y,
                                         aCamera.Target.z + V.z);
  aCamera.UpVector := NewUp;
  Result := True;

  // The view has changed: drawn again.
  if Assigned(fStore) and Assigned(Scene) then
    Scene.NotifyDataChanged(fStore);
end;

procedure TvgSkyBox.SetUpAxis(const Value: TvgSkyUpAxis);
begin
  if fUpAxis = Value then Exit;
  fUpAxis := Value;
  Refresh;
end;

procedure TvgSkyBox.SetMode(const Value: TvgSkyMode);
begin
  if fMode = Value then Exit;
  fMode := Value;
  Refresh;
end;

procedure TvgSkyBox.SetUseSystemTime(const Value: Boolean);
begin
  if fUseSystemTime = Value then Exit;
  fUseSystemTime := Value;
  Refresh;
end;

procedure TvgSkyBox.SetDateTime(const Value: TDateTime);
begin
  fDateTime := Value;
  Refresh;
end;

procedure TvgSkyBox.SetUTCOffset(const Value: Double);
begin
  fUTCOffset := EnsureRange(Value, -14, 14);
  Refresh;
end;

procedure TvgSkyBox.SetLatitude(const Value: Double);
begin
  fLatitude := EnsureRange(Value, -90, 90);
  Refresh;
end;

procedure TvgSkyBox.SetLongitude(const Value: Double);
begin
  fLongitude := EnsureRange(Value, -180, 180);
  Refresh;
end;

procedure TvgSkyBox.SetSunTracksTime(const Value: Boolean);
begin
  if fSunTracksTime = Value then Exit;
  fSunTracksTime := Value;
  Refresh;
end;

procedure TvgSkyBox.SetBrightness(const Value: Single);
begin
  fBrightness := Max(0, Value);
  Refresh;
end;

procedure TvgSkyBox.SetSunSize(const Value: Single);
begin
  fSunSize := EnsureRange(Value, 0.1, 45);
  Refresh;
end;

procedure TvgSkyBox.SetMoonSize(const Value: Single);
begin
  fMoonSize := EnsureRange(Value, 0.1, 45);
  Refresh;
end;

procedure TvgSkyBox.SetTextureWidth(const Value: Integer);
var
  W : Integer;
begin
  W := SkyWidth(Value);
  if W = fTextureWidth then Exit;
  fTextureWidth := W;
  FreeAndNil(fDayImage);
  FreeAndNil(fNightImage);
  RebuildStore;
end;

procedure TvgSkyBox.SetDayTextureFile(const Value: String);
begin
  if fDayTextureFile = Value then Exit;
  fDayTextureFile := Value;
  RebuildStore;
end;

procedure TvgSkyBox.SetNightTextureFile(const Value: String);
begin
  if fNightTextureFile = Value then Exit;
  fNightTextureFile := Value;
  RebuildStore;
end;

{ globals }

function vgSkyBox(aScene: TvgScene; aCreate: Boolean): TvgSkyBox;
begin
  Result := nil;
  if not Assigned(aScene) then Exit;
  Result := TvgSkyBox(aScene.FindExtension(TvgSkyBox));
  if (Result = nil) and aCreate then
  begin
    Result := TvgSkyBox.Create;
    aScene.AddExtension(Result);
  end;
end;

end.
