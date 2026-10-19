program TextureScaleTest;

{ vgFitTextureSize and vgDecodeTextureScaled (Vulkan_Components_TextureInspector):
  textures larger than the size limit are decoded straight to a smaller
  RGBA image with WIC. No device needed. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Math,
  Vulkan_Components_TextureInspector;

var
  Failures: Integer = 0;

procedure Check(const Name: string; OK: Boolean);
begin
  if OK then Writeln('  ok   ', Name)
  else begin Writeln('  FAIL ', Name); Inc(Failures); end;
end;

{ A 24-bit BMP, left half red, right half blue. }
function MakeBMP(aWidth, aHeight: Integer): TMemoryStream;
var
  RowSize, ImageSize, X, Y: Integer;
  Row: TBytes;
  Ms: TMemoryStream;
  procedure W16(V: Word);     begin Ms.WriteBuffer(V, 2); end;
  procedure W32(V: Cardinal); begin Ms.WriteBuffer(V, 4); end;
begin
  Ms := TMemoryStream.Create;
  Result := Ms;
  RowSize   := ((aWidth * 3 + 3) div 4) * 4;
  ImageSize := RowSize * aHeight;
  W16($4D42); W32(54 + ImageSize); W32(0); W32(54);       // file header
  W32(40); W32(Cardinal(aWidth)); W32(Cardinal(aHeight)); // info header
  W16(1); W16(24); W32(0); W32(Cardinal(ImageSize));
  W32(2835); W32(2835); W32(0); W32(0);
  SetLength(Row, RowSize);
  for X := 0 to aWidth - 1 do
    if X < aWidth div 2 then
    begin Row[X*3] := 0;   Row[X*3+1] := 0; Row[X*3+2] := 255; end  // BGR red
    else
    begin Row[X*3] := 255; Row[X*3+1] := 0; Row[X*3+2] := 0;   end; // BGR blue
  for Y := 0 to aHeight - 1 do Result.WriteBuffer(Row[0], RowSize);
  Result.Position := 0;
end;

function PixelIs(const P: TBytes; aWidth, X, Y: Integer; R, G, B: Byte): Boolean;
var I: Integer;
begin
  I := (Y * aWidth + X) * 4;
  Result := (P[I] = R) and (P[I+1] = G) and (P[I+2] = B) and (P[I+3] = 255);
end;

procedure TestFit;
var W, H: Integer;
begin
  Writeln('vgFitTextureSize');
  W := 8192; H := 8192;
  Check('8192 square to 4096', vgFitTextureSize(W, H, 4096) and (W = 4096) and (H = 4096));
  W := 8192; H := 2048;
  Check('wide keeps aspect', vgFitTextureSize(W, H, 4096) and (W = 4096) and (H = 1024));
  W := 1000; H := 3000;
  Check('tall keeps aspect', vgFitTextureSize(W, H, 1500) and (W = 500) and (H = 1500));
  W := 4096; H := 100;
  Check('already fits is unchanged', not vgFitTextureSize(W, H, 4096) and (W = 4096) and (H = 100));
  W := 9000; H := 9000;
  Check('limit 0 means no limit', not vgFitTextureSize(W, H, 0) and (W = 9000));
end;

procedure TestDecode;
var
  S: TMemoryStream;
  W, H: Integer;
  P: TBytes;
begin
  Writeln('vgDecodeTextureScaled');
  S := MakeBMP(3000, 1000);
  try
    Check('3000x1000 BMP shrinks to fit 1000',
          vgDecodeTextureScaled(S, 1000, W, H, P) and (W = 1000) and (H = 333));
    Check('buffer is RGBA', Length(P) = W * H * 4);
    Check('left is red (RGBA order)',  (Length(P) > 0) and PixelIs(P, W, 100, H div 2, 255, 0, 0));
    Check('right is blue (RGBA order)', (Length(P) > 0) and PixelIs(P, W, 900, H div 2, 0, 0, 255));
    Check('fits already: not decoded',
          not vgDecodeTextureScaled(S, 4096, W, H, P) and (P = nil));
  finally
    S.Free;
  end;

  S := TMemoryStream.Create;
  try
    S.WriteBuffer(PAnsiChar('not an image at all')^, 19);
    Check('not an image: False', not vgDecodeTextureScaled(S, 16, W, H, P));
  finally
    S.Free;
  end;
end;

begin
  Writeln('vgMaxTextureSize default: ', vgMaxTextureSize);
  {$IF SizeOf(Pointer) = 4}
  Check('32-bit default is 4096', vgMaxTextureSize = 4096);
  {$IFEND}
  TestFit;
  TestDecode;
  if Failures > 0 then
  begin
    Writeln(Failures, ' FAILED');
    Halt(1);
  end;
  Writeln('all passed');
end.
