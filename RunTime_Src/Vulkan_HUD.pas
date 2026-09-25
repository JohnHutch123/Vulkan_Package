(******************************************************************************
 *                                 vgVulkan                                  *
 ******************************************************************************
 * HUD overlay rasterizer.  CPU-side RGBA atlas: status panel + crosshair.   *
 * Blitted onto the swapchain after the scene (render or cached blit).       *
 ******************************************************************************)

unit Vulkan_HUD;

interface

{$INCLUDE VulkanPackage.inc}

uses
  System.SysUtils,
  System.Math,
  PasVulkan.Math.Double,
  Vulkan_WorldAxes,
  Vulkan_Components_Camera;

const
  HUD_ATLAS_WIDTH     = 480;
  HUD_ATLAS_HEIGHT    = 176;
  HUD_PANEL_WIDTH     = 480;
  HUD_PANEL_HEIGHT    = 160;
  HUD_CROSSHAIR_SIZE  = 11;
  //The crosshair arms are inset by one pixel inside their atlas cell so the
  //dark halo that keeps them visible on a light background has somewhere to
  //go without bleeding into the panel above.
  HUD_CROSSHAIR_CELL  = HUD_CROSSHAIR_SIZE + 2;
  HUD_PANEL_MARGIN    = 8;
  HUD_CHAR_W          = 8;
  HUD_CHAR_H          = 8;
  HUD_GIZMO_MARGIN    = 40;  // gizmo centre is this far in from the right edge
  HUD_GIZMO_CY        = 40;  // gizmo centre, from the panel top
  HUD_GIZMO_LEN       = 22;  // axis arm length

type
  TvgHUDInfo = record
    CursorX, CursorY : Integer;
    HasCamera        : Boolean;
    CameraPos        : TpvVector3D;
    CameraForward    : TpvVector3D;
    CameraUp         : TpvVector3D;
    CameraRight      : TpvVector3D;
    ExtraText        : string;
    SceneReused      : Boolean;
    PanelOpaque      : Boolean;
    CrossHairON      : Boolean;
  end;

procedure vgClearHUDInfo(out aInfo: TvgHUDInfo);
//aPanelHeight returns how tall the drawn content actually is, so the caller
//can blit just that much of the panel instead of the full HUD_PANEL_HEIGHT.
procedure vgRasterizeHUD(const aInfo: TvgHUDInfo; out aPixels: TBytes; out aPanelHeight: Integer);

implementation

type
  THudRGB = packed record
    R, G, B, A: Byte;
  end;
  PHudRGB = ^THudRGB;

const
  // 5x7 glyphs in the low 5 bits, chars 32..126.  Bit 4 = leftmost pixel.
  CFont8x8: array[0..94, 0..7] of Byte = (
    ($00,$00,$00,$00,$00,$00,$00,$00), // 32 space
    ($04,$04,$04,$04,$04,$00,$04,$00), // !
    ($0A,$0A,$00,$00,$00,$00,$00,$00), // "
    ($0A,$0A,$1F,$0A,$1F,$0A,$0A,$00), // #
    ($04,$0F,$14,$0E,$05,$1E,$04,$00), // $
    ($18,$19,$02,$04,$08,$13,$03,$00), // %
    ($08,$14,$14,$08,$15,$12,$0D,$00), // &
    ($04,$04,$00,$00,$00,$00,$00,$00), // '
    ($02,$04,$08,$08,$08,$04,$02,$00), // (
    ($08,$04,$02,$02,$02,$04,$08,$00), // )
    ($00,$04,$15,$0E,$15,$04,$00,$00), // *
    ($00,$04,$04,$1F,$04,$04,$00,$00), // +
    ($00,$00,$00,$00,$00,$04,$04,$08), // ,
    ($00,$00,$00,$1F,$00,$00,$00,$00), // -
    ($00,$00,$00,$00,$00,$00,$04,$00), // .
    ($01,$02,$02,$04,$08,$08,$10,$00), // /
    ($0E,$11,$13,$15,$19,$11,$0E,$00), // 0
    ($04,$0C,$04,$04,$04,$04,$0E,$00), // 1
    ($0E,$11,$01,$06,$08,$10,$1F,$00), // 2
    ($0E,$11,$01,$06,$01,$11,$0E,$00), // 3
    ($02,$06,$0A,$12,$1F,$02,$02,$00), // 4
    ($1F,$10,$1E,$01,$01,$11,$0E,$00), // 5
    ($06,$08,$10,$1E,$11,$11,$0E,$00), // 6
    ($1F,$01,$02,$04,$08,$08,$08,$00), // 7
    ($0E,$11,$11,$0E,$11,$11,$0E,$00), // 8
    ($0E,$11,$11,$0F,$01,$02,$0C,$00), // 9
    ($00,$00,$04,$00,$00,$04,$00,$00), // :
    ($00,$00,$04,$00,$00,$04,$04,$08), // ;
    ($02,$04,$08,$10,$08,$04,$02,$00), // <
    ($00,$00,$1F,$00,$1F,$00,$00,$00), // =
    ($08,$04,$02,$01,$02,$04,$08,$00), // >
    ($0E,$11,$01,$02,$04,$00,$04,$00), // ?
    ($0E,$11,$17,$15,$17,$10,$0E,$00), // @
    ($0E,$11,$11,$1F,$11,$11,$11,$00), // A
    ($1E,$11,$11,$1E,$11,$11,$1E,$00), // B
    ($0E,$11,$10,$10,$10,$11,$0E,$00), // C
    ($1E,$11,$11,$11,$11,$11,$1E,$00), // D
    ($1F,$10,$10,$1E,$10,$10,$1F,$00), // E
    ($1F,$10,$10,$1E,$10,$10,$10,$00), // F
    ($0E,$11,$10,$17,$11,$11,$0F,$00), // G
    ($11,$11,$11,$1F,$11,$11,$11,$00), // H
    ($0E,$04,$04,$04,$04,$04,$0E,$00), // I
    ($01,$01,$01,$01,$11,$11,$0E,$00), // J
    ($11,$12,$14,$18,$14,$12,$11,$00), // K
    ($10,$10,$10,$10,$10,$10,$1F,$00), // L
    ($11,$1B,$15,$15,$11,$11,$11,$00), // M
    ($11,$19,$15,$13,$11,$11,$11,$00), // N
    ($0E,$11,$11,$11,$11,$11,$0E,$00), // O
    ($1E,$11,$11,$1E,$10,$10,$10,$00), // P
    ($0E,$11,$11,$11,$15,$12,$0D,$00), // Q
    ($1E,$11,$11,$1E,$14,$12,$11,$00), // R
    ($0E,$11,$10,$0E,$01,$11,$0E,$00), // S
    ($1F,$04,$04,$04,$04,$04,$04,$00), // T
    ($11,$11,$11,$11,$11,$11,$0E,$00), // U
    ($11,$11,$11,$11,$11,$0A,$04,$00), // V
    ($11,$11,$11,$15,$15,$1B,$11,$00), // W
    ($11,$11,$0A,$04,$0A,$11,$11,$00), // X
    ($11,$11,$0A,$04,$04,$04,$04,$00), // Y
    ($1F,$01,$02,$04,$08,$10,$1F,$00), // Z
    ($0E,$08,$08,$08,$08,$08,$0E,$00), // [
    ($10,$08,$08,$04,$02,$02,$01,$00), // \
    ($0E,$02,$02,$02,$02,$02,$0E,$00), // ]
    ($04,$0A,$11,$00,$00,$00,$00,$00), // ^
    ($00,$00,$00,$00,$00,$00,$1F,$00), // _
    ($08,$04,$00,$00,$00,$00,$00,$00), // `
    ($00,$00,$0E,$01,$0F,$11,$0F,$00), // a
    ($10,$10,$1E,$11,$11,$11,$1E,$00), // b
    ($00,$00,$0E,$11,$10,$11,$0E,$00), // c
    ($01,$01,$0F,$11,$11,$11,$0F,$00), // d
    ($00,$00,$0E,$11,$1F,$10,$0E,$00), // e
    ($06,$08,$08,$1C,$08,$08,$08,$00), // f
    ($00,$00,$0F,$11,$11,$0F,$01,$0E), // g
    ($10,$10,$1E,$11,$11,$11,$11,$00), // h
    ($04,$00,$0C,$04,$04,$04,$0E,$00), // i
    ($02,$00,$06,$02,$02,$02,$12,$0C), // j
    ($10,$10,$12,$14,$18,$14,$12,$00), // k
    ($0C,$04,$04,$04,$04,$04,$0E,$00), // l
    ($00,$00,$1A,$15,$15,$15,$15,$00), // m
    ($00,$00,$1E,$11,$11,$11,$11,$00), // n
    ($00,$00,$0E,$11,$11,$11,$0E,$00), // o
    ($00,$00,$1E,$11,$11,$1E,$10,$10), // p
    ($00,$00,$0F,$11,$11,$0F,$01,$01), // q
    ($00,$00,$16,$19,$10,$10,$10,$00), // r
    ($00,$00,$0F,$10,$0E,$01,$1E,$00), // s
    ($08,$08,$1C,$08,$08,$08,$06,$00), // t
    ($00,$00,$11,$11,$11,$11,$0F,$00), // u
    ($00,$00,$11,$11,$11,$0A,$04,$00), // v
    ($00,$00,$11,$11,$15,$15,$0A,$00), // w
    ($00,$00,$11,$0A,$04,$0A,$11,$00), // x
    ($00,$00,$11,$11,$11,$0F,$01,$0E), // y
    ($00,$00,$1F,$02,$04,$08,$1F,$00), // z
    ($06,$08,$08,$10,$08,$08,$06,$00), // {
    ($04,$04,$04,$04,$04,$04,$04,$00), // |
    ($0C,$02,$02,$01,$02,$02,$0C,$00), // }
    ($00,$00,$08,$15,$02,$00,$00,$00)  // ~
  );

procedure vgClearHUDInfo(out aInfo: TvgHUDInfo);
begin
  FillChar(aInfo, SizeOf(aInfo), 0);
  aInfo.ExtraText := '';
end;

procedure vgRasterizeHUD(const aInfo: TvgHUDInfo; out aPixels: TBytes; out aPanelHeight: Integer);
var
  W, H : Integer;

  function Pix(aX, aY: Integer): PHudRGB;
  begin
    Result := PHudRGB(@aPixels[(aY * W + aX) * 4]);
  end;

  procedure Put(aX, aY: Integer; aR, aG, aB: Byte);
  begin
    if (aX < 0) or (aY < 0) or (aX >= W) or (aY >= H) then
      Exit;
    with Pix(aX, aY)^ do
    begin
      R := aR;
      G := aG;
      B := aB;
      A := 255;
    end;
  end;

  // Opaque fill so the caller can composite a rect with a single GPU blit.
  // vkCmdBlitImage is a raw copy with no alpha blending, so a HUD atlas that
  // is mostly transparent (as this one is, glyph pixels aside) can only be
  // composited pixel-run-by-pixel-run without punching black holes through
  // the scene - which is what previously turned every HUD redraw into
  // hundreds of tiny blits.  Giving the panel/crosshair backing a solid
  // colour removes the need for that.
  procedure FillRect(aX0, aY0, aX1, aY1: Integer; aR, aG, aB: Byte);
  var
    X, Y: Integer;
  begin
    for Y := aY0 to aY1 - 1 do
      for X := aX0 to aX1 - 1 do
        Put(X, Y, aR, aG, aB);
  end;

  procedure DrawChar(aX, aY: Integer; aCh: Char; aR, aG, aB: Byte);
  var
    Idx, Row, Col, OX, OY: Integer;
    Bits: Byte;
  begin
    Idx := Ord(aCh) - 32;
    if (Idx < 0) or (Idx > 94) then
      Idx := Ord('?') - 32;
    for Row := 0 to 7 do
    begin
      Bits := CFont8x8[Idx, Row];
      for Col := 0 to 4 do
        if (Bits and (1 shl (4 - Col))) <> 0 then
          for OY := -1 to 1 do
            for OX := -1 to 1 do
              Put(aX + Col + OX, aY + Row + OY, 0, 0, 0);
    end;
    for Row := 0 to 7 do
    begin
      Bits := CFont8x8[Idx, Row];
      for Col := 0 to 4 do
        if (Bits and (1 shl (4 - Col))) <> 0 then
          Put(aX + Col, aY + Row, aR, aG, aB);
    end;
  end;

  procedure DrawText(aX, aY: Integer; const aText: string; aR, aG, aB: Byte);
  var
    I, X: Integer;
  begin
    X := aX;
    for I := 1 to Length(aText) do
    begin
      if X + HUD_CHAR_W > HUD_PANEL_WIDTH - 4 then
        Break;
      DrawChar(X, aY, aText[I], aR, aG, aB);
      Inc(X, HUD_CHAR_W);
    end;
  end;

  procedure DrawLine(aX0, aY0, aX1, aY1: Integer; aR, aG, aB: Byte);
  var
    DX, DY, SX, SY, Err, E2: Integer;
  begin
    DX := Abs(aX1 - aX0);
    DY := Abs(aY1 - aY0);
    if aX0 < aX1 then SX := 1 else SX := -1;
    if aY0 < aY1 then SY := 1 else SY := -1;
    Err := DX - DY;
    while True do
    begin
      Put(aX0, aY0, aR, aG, aB);
      if (aX0 = aX1) and (aY0 = aY1) then
        Break;
      E2 := Err * 2;
      if E2 > -DY then
      begin
        Dec(Err, DY);
        Inc(aX0, SX);
      end;
      if E2 < DX then
      begin
        Inc(Err, DX);
        Inc(aY0, SY);
      end;
    end;
  end;

  function VecText(const aPrefix: string; const aV: TpvVector3D): string;
  begin
    Result := Format('%s %6.2f %6.2f %6.2f', [aPrefix, aV.X, aV.Y, aV.Z]);
  end;

  procedure DrawAxisGizmo;
  var
    CX, CY, Len: Integer;
    Right, Up: TpvVector3D;

    procedure Axis(const aWorld: TpvVector3D; aR, aG, aB: Byte; aLabel: Char);
    var
      SX, SY, EX, EY: Integer;
    begin
      SX := Round(aWorld.Dot(Right) * Len);
      SY := Round(-aWorld.Dot(Up) * Len);
      EX := CX + SX;
      EY := CY + SY;
      DrawLine(CX, CY, EX, EY, aR, aG, aB);
      DrawChar(EX + 1, EY - 3, aLabel, aR, aG, aB);
    end;

  begin
    CX  := HUD_PANEL_WIDTH - HUD_GIZMO_MARGIN;
    CY  := HUD_GIZMO_CY;
    Len := HUD_GIZMO_LEN;
    if aInfo.HasCamera then
    begin
      Right := aInfo.CameraRight;
      Up    := aInfo.CameraUp;
    end else
    begin
      Right := vgWorldRight;
      Up    := vgWorldUp;
    end;
    Axis(vgWorldRight,   220,  60,  60, 'X');
    Axis(vgWorldUp,       60, 200,  80, 'Y');
    Axis(vgWorldForward,  60, 120, 255, 'Z');
    Put(CX, CY, 240, 240, 240);
  end;

  procedure DrawCrosshair;
  var
    X0, Y0, C, I, OX, OY: Integer;
  begin
    X0 := 1;
    Y0 := HUD_PANEL_HEIGHT + 1;
    C  := HUD_CROSSHAIR_SIZE div 2;

    // Halo pass first, arms second - drawing them interleaved would let a
    // later arm pixel's halo paint over an earlier arm pixel.
    for I := 0 to HUD_CROSSHAIR_SIZE - 1 do
      for OY := -1 to 1 do
        for OX := -1 to 1 do
        begin
          Put(X0 + I + OX, Y0 + C + OY, 0, 0, 0);
          Put(X0 + C + OX, Y0 + I + OY, 0, 0, 0);
        end;

    for I := 0 to HUD_CROSSHAIR_SIZE - 1 do
    begin
      Put(X0 + I, Y0 + C, 255, 255, 255);
      Put(X0 + C, Y0 + I, 255, 255, 255);
    end;
    Put(X0 + C, Y0 + C, 255, 220, 80);
  end;

var
  AxisName, SceneLine: string;
  LineY: Integer;
begin
  W := HUD_ATLAS_WIDTH;
  H := HUD_ATLAS_HEIGHT;
  SetLength(aPixels, W * H * 4);
  FillChar(aPixels[0], Length(aPixels), 0);

  //The crosshair deliberately gets no backing in either mode - it is small
  //enough to composite as opaque spans, and a solid box following the mouse
  //around looks worse than the halo does.
  if aInfo.PanelOpaque then
    FillRect(0, 0, HUD_PANEL_WIDTH, HUD_PANEL_HEIGHT, 18, 22, 30);

  if vgAxisConvention = acZUp then
    AxisName := 'Z-up'
  else
    AxisName := 'Y-up';

  if aInfo.SceneReused then
    SceneLine := 'Scene: blit (unchanged)'
  else
    SceneLine := 'Scene: redraw';

  LineY := 6;
  DrawText(8, LineY, 'HUD  axis ' + AxisName, 200, 210, 230);
  Inc(LineY, 12);
  DrawText(8, LineY, Format('Cursor  %d, %d', [aInfo.CursorX, aInfo.CursorY]), 255, 220, 80);
  Inc(LineY, 12);
  DrawText(8, LineY, SceneLine, 180, 200, 160);
  Inc(LineY, 14);

  if aInfo.HasCamera then
  begin
    DrawText(8, LineY, VecText('Pos', aInfo.CameraPos), 210, 210, 210);
    Inc(LineY, 12);
    DrawText(8, LineY, VecText('Fwd', aInfo.CameraForward), 60, 120, 255);
    Inc(LineY, 12);
    DrawText(8, LineY, VecText('Up ', aInfo.CameraUp), 60, 200, 80);
    Inc(LineY, 12);
    DrawText(8, LineY, VecText('Rt ', aInfo.CameraRight), 220, 60, 60);
    Inc(LineY, 12);
  end else
  begin
    DrawText(8, LineY, 'Camera: (none)', 160, 160, 160);
    Inc(LineY, 12);
  end;

  if aInfo.ExtraText <> '' then
  begin
    DrawText(8, LineY, aInfo.ExtraText, 200, 200, 140);
    Inc(LineY, HUD_CHAR_H + 4);  // this row wasn't followed by an Inc above
  end;

  DrawAxisGizmo;

  If aInfo.CrossHairON then
    DrawCrosshair;

  // Report how tall the content actually is so the caller can blit just
  // that much instead of the full fixed-size panel.  The gizmo sits at a
  // fixed position regardless of text length, so don't let a short text
  // block (e.g. no camera, no extra text) clip it.
  aPanelHeight := LineY + 2;
  if aPanelHeight < (HUD_GIZMO_CY + HUD_GIZMO_LEN + HUD_CHAR_H + 4) then
    aPanelHeight := HUD_GIZMO_CY + HUD_GIZMO_LEN + HUD_CHAR_H + 4;
  if aPanelHeight > HUD_PANEL_HEIGHT then
    aPanelHeight := HUD_PANEL_HEIGHT;
end;

end.
