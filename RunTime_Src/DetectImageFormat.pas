unit DetectImageFormat;

interface

uses
  System.Classes, System.SysUtils, Vcl.Graphics, Vcl.Imaging.pngimage,
  Vcl.Imaging.jpeg, Vcl.Imaging.GIFImg, Vcl.Imaging.ico, Vcl.Imaging.WIC; // include units you need

type
  TImageFormatKind = (ifUnknown, ifBMP, ifPNG, ifJPEG, ifGIF, ifICO, ifWebP,
                      ifDDS, ifKTX1, ifKTX2, ifPVR, ifTGA);

function DetectImageFormat(AStream: TStream): TImageFormatKind;
function StreamHasGraphic(AStream: TStream): Boolean;

implementation

uses
  System.Math;

function CompareBytes(const A: array of Byte; const B: array of Byte; Count: Integer): Boolean;
begin
  Result := (Count >= 0) and (CompareMem(@A[0], @B[0], Count));
end;

// read up to N bytes into buffer, but preserve stream position
procedure ReadHeader(AStream: TStream; var Buffer; Count: Integer; out BytesRead: Integer);
var
  PosSaved: Int64;
begin
  BytesRead := 0;
  if AStream = nil then Exit;
  PosSaved := AStream.Position;
  try
    BytesRead := AStream.Read(Buffer, Count);
  finally
    AStream.Position := PosSaved;
  end;
end;

function DetectImageFormat(AStream: TStream): TImageFormatKind;
const
  PNGSig: array[0..7] of Byte = ($89, Ord('P'), Ord('N'), Ord('G'), $0D, $0A, $1A, $0A);
  JFIFSig: array[0..2] of Byte = ($FF, $D8, $FF);
  GIF87a: array[0..5] of Byte = (Ord('G'), Ord('I'), Ord('F'), Ord('8'), Ord('7'), Ord('a'));
  GIF89a: array[0..5] of Byte = (Ord('G'), Ord('I'), Ord('F'), Ord('8'), Ord('9'), Ord('a'));
  BMPSig: array[0..1] of Byte = (Ord('B'), Ord('M'));
  DDSsig: array[0..3] of Byte = (Ord('D'), Ord('D'), Ord('S'), $20);
  KTX1Sig: array[0..11] of Byte = ($AB, Ord('K'), Ord('T'), Ord('X'), $20, Ord('1'), Ord('1'), $BB, $0D, $0A, $1A, $0A);
  KTX2Sig: array[0..11] of Byte = ($AB, Ord('K'), Ord('T'), Ord('X'), $20, Ord('2'), Ord('0'), $BB, $0D, $0A, $1A, $0A);
  WebPSigRIFF: array[0..3] of Byte = (Ord('R'), Ord('I'), Ord('F'), Ord('F'));
  WebPSigWEBP: array[0..3] of Byte = (Ord('W'), Ord('E'), Ord('B'), Ord('P'));
  PVRSig_v3: array[0..3] of Byte = (Ord('P'), Ord('V'), Ord('R'), 3); // some PVR v3 files use 0x03525650 in LE; this is a heuristic
var
  Buf: array[0..31] of Byte;
  n: Integer;
begin
  Result := ifUnknown;
  if AStream = nil then Exit;
  ReadHeader(AStream, Buf, SizeOf(Buf), n);
  if n >= 2 then
  begin
    if CompareMem(@Buf[0], @BMPSig[0], 2) then
      Exit(ifBMP);
  end;
  if n >= 8 then
  begin
    if CompareMem(@Buf[0], @PNGSig[0], 8) then
      Exit(ifPNG);
  end;
  if n >= 3 then
  begin
    if CompareMem(@Buf[0], @JFIFSig[0], 3) then
      Exit(ifJPEG);
  end;
  if n >= 6 then
  begin
    if CompareMem(@Buf[0], @GIF87a[0], 6) or CompareMem(@Buf[0], @GIF89a[0], 6) then
      Exit(ifGIF);
  end;
  if n >= 4 then
  begin
    // ICO/PE icons often start with 00 00 01 00 or 00 00 02 00 (CUR)
    if (Buf[0] = 0) and (Buf[1] = 0) and ( (Buf[2] = 1) or (Buf[2] = 2) ) and (Buf[3] = 0) then
      Exit(ifICO);
    if CompareMem(@Buf[0], @DDSsig[0], 4) then
      Exit(ifDDS);
    if CompareMem(@Buf[0], @KTX1Sig[0], 12) then
      Exit(ifKTX1);
    if CompareMem(@Buf[0], @KTX2Sig[0], 12) then
      Exit(ifKTX2);
  end;
  // WebP check: RIFF....WEBP
  if n >= 12 then
  begin
    if CompareMem(@Buf[0], @WebPSigRIFF[0], 4) and CompareMem(@Buf[8], @WebPSigWEBP[0], 4) then
      Exit(ifWebP);
  end;
  // PVR heuristic: 'P','V','R' and a small version byte
  if n >= 4 then
  begin
    if (Buf[0] = Ord('P')) and (Buf[1] = Ord('V')) and (Buf[2] = Ord('R')) then
      Exit(ifPVR);
  end;
  // TGA is harder: no fixed magic at 0; many TGAs have zero id length in first byte plus certain image types:
  if n >= 3 then
  begin
    // Basic heuristic for TGA: idlength <= 255, color map type 0/1 and image type 1/2/3/9/10/11; this is not definitive
    if (Buf[1] in [0,1]) and (Buf[2] in [1,2,3,9,10,11]) then
      Exit(ifTGA);
  end;
  // Default: unknown
  Result := ifUnknown;
end;

function StreamHasGraphic(AStream: TStream): Boolean;
var
  PosSaved: Int64;
  Pic: TPicture;
  Wic: TWICImage;
begin
  Result := False;
  if AStream = nil then Exit;
  PosSaved := AStream.Position;
  try
    Pic := TPicture.Create;
    try
      try
        AStream.Position := 0;
        Pic.LoadFromStream(AStream);
        Result := Assigned(Pic.Graphic) and not Pic.Graphic.Empty;
        if Result then Exit;
      except
        // ignore, try TWICImage next
      end;
    finally
      Pic.Free;
    end;

    // Try WIC (supports more formats via installed codecs)
    try
      Wic := TWICImage.Create;
      try
        AStream.Position := 0;
        Wic.LoadFromStream(AStream);
        Result := Wic.Width > 0;
        Exit;
      finally
        Wic.Free;
      end;
    except
      // not supported or failed
    end;
  finally
    AStream.Position := PosSaved;
  end;
end;

end.