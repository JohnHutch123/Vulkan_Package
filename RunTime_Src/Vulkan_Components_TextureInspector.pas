unit Vulkan_Components_TextureInspector;

interface

uses
  System.Classes, System.SysUtils, System.Math;

type
  TTextureFormatKind = (tfUnknown, tfBMP, tfPNG, tfJPEG, tfGIF, tfICO,
                        tfWebP, tfDDS, tfKTX1, tfKTX2, tfPVRv3, tfTGA,
                        tfQOI, tfRadianceHDR, tfEXR);

  TTextureInfo = record
    FormatKind   : TTextureFormatKind;
    Width        : Integer;        // -1 if unknown
    Height       : Integer;       // -1 if unknown
    MipMapCount  : Integer;  // -1 if unknown
    HasMipMaps   : Boolean;   // MipMapCount > 1
    IsSRGB       : Boolean;       // true if file explicitly marks sRGB
    AllocationGroupID: string; // best-effort metadata lookup (empty if none)
  end;

function InspectTexture(AStream: TStream; out Info: TTextureInfo): Boolean;

implementation

const
  // DDS magic
  DDS_MAGIC: array[0..3] of Byte = (Ord('D'), Ord('D'), Ord('S'), $20);
  // KTX1 ident
  KTX1_IDENT: array[0..11] of Byte = ($AB, Ord('K'), Ord('T'), Ord('X'), $20, Ord('1'), Ord('1'), $BB, $0D, $0A, $1A, $0A);
  // KTX2 ident: AB KTX 20 BB 0D 0A 1A 0A (we accept '2'/'0')
  KTX2_IDENT: array[0..11] of Byte = ($AB, Ord('K'), Ord('T'), Ord('X'), $20, Ord('2'), Ord('0'), $BB, $0D, $0A, $1A, $0A);
  // PVRv3 magic
  PVRv3_MAGIC = $03525650; // 'P''V''R' 0x03
  // QOI magic 'qoif'
  QOI_MAGIC: array[0..3] of Byte = (Ord('q'), Ord('o'), Ord('i'), Ord('f'));
  // PNG signature
  PNG_SIG: array[0..7] of Byte = ($89, Ord('P'), Ord('N'), Ord('G'), $0D, $0A, $1A, $0A);
  // Radiance header start '#?'
  RADIANCE_SIG: array[0..1] of Byte = (Ord('#'), Ord('?'));

type
  // DDS header pieces (packed)
  TDDS_PIXELFORMAT = packed record
    dwSize: Cardinal;
    dwFlags: Cardinal;
    dwFourCC: Cardinal;
    dwRGBBitCount: Cardinal;
    dwRBitMask: Cardinal;
    dwGBitMask: Cardinal;
    dwBBitMask: Cardinal;
    dwABitMask: Cardinal;
  end;

  TDDS_HEADER = packed record
    dwSize: Cardinal;
    dwFlags: Cardinal;
    dwHeight: Cardinal;
    dwWidth: Cardinal;
    dwPitchOrLinearSize: Cardinal;
    dwDepth: Cardinal;
    dwMipMapCount: Cardinal;
    dwReserved1: array[0..10] of Cardinal;
    ddspf: TDDS_PIXELFORMAT;
    dwCaps: Cardinal;
    dwCaps2: Cardinal;
    dwCaps3: Cardinal;
    dwCaps4: Cardinal;
    dwReserved2: Cardinal;
  end;

  TDDS_HEADER_DX10 = packed record
    dxgiFormat: Cardinal;
    resourceDimension: Cardinal;
    miscFlag: Cardinal;
    arraySize: Cardinal;
    miscFlags2: Cardinal;
  end;

  // KTX1 header
  TKTX1Header = packed record
    identifier: array[0..11] of Byte;
    endianness: Cardinal;
    glType: Cardinal;
    glTypeSize: Cardinal;
    glFormat: Cardinal;
    glInternalFormat: Cardinal;
    glBaseInternalFormat: Cardinal;
    pixelWidth: Cardinal;
    pixelHeight: Cardinal;
    pixelDepth: Cardinal;
    numberOfArrayElements: Cardinal;
    numberOfFaces: Cardinal;
    numberOfMipmapLevels: Cardinal;
    bytesOfKeyValueData: Cardinal;
  end;

  // KTX2 header (basic fields; simplified)
  TKTX2Header = packed record
    identifier: array[0..11] of Byte;
    vkFormat: Cardinal;
    typeSize: Cardinal;
    pixelWidth: Cardinal;
    pixelHeight: Cardinal;
    pixelDepth: Cardinal;
    layerCount: Cardinal;
    faceCount: Cardinal;
    levelCount: Cardinal;
    supercompressionScheme: Cardinal;
    // Note: KTX2 file has additional fields (dfdByteOffset, kvdByteOffset, etc.)
    // For full metadata extraction you'd parse those offsets. This unit reads levelCount
    // from the header and scans later bytes for an allocationGroupID text if present
    // in the following region (best-effort).
  end;

  TPVRv3Header = packed record
    version: Cardinal;       // magic 0x03525650
    flags: Cardinal;
    pixelFormatLo: Cardinal;
    pixelFormatHi: Cardinal;
    colourSpace: Cardinal;   // 0 = linear, 1 = sRGB
    channelType: Cardinal;
    height: Cardinal;
    width: Cardinal;
    depth: Cardinal;
    numSurfaces: Cardinal;
    numFaces: Cardinal;
    mipMapCount: Cardinal;
    metaDataSize: Cardinal;
  end;

  // QOI header is 14 bytes: magic(4), width(4 BE), height(4 BE), channels(1), colorspace(1)
  TQOIHeader = packed record
    magic: array[0..3] of Byte; // 'qoif'
    widthBE: array[0..3] of Byte;
    heightBE: array[0..3] of Byte;
    channels: Byte;
    colorspace: Byte; // 0 = sRGB with linear alpha, 1 = all channels linear
  end;

{ Helpers }

function BytesEqual(const A: array of Byte; Buffer: PByte; Count: Integer): Boolean;
var
  i: Integer;
begin
  if Count > Length(A) then Exit(False);
  for i := 0 to Count - 1 do
    if A[i] <> Buffer[i] then Exit(False);
  Result := True;
end;

function PeekBytes(AStream: TStream; Buffer: Pointer; Count: NativeInt): NativeInt;
var
  PosSaved: Int64;
begin
  Result := 0;
  if AStream = nil then Exit;
  PosSaved := AStream.Position;
  try
    Result := AStream.Read(Buffer^, Count);
  finally
    AStream.Position := PosSaved;
  end;
end;

procedure ReadExactly(AStream: TStream; var Buffer; Count: NativeInt);
begin
  if AStream = nil then
    raise Exception.Create('Stream is nil');
  if AStream.Read(Buffer, Count) <> Count then
    raise Exception.Create('Unexpected EOF while reading header');
end;

function LEToUInt32(const B: array of Byte): Cardinal;
begin
  Result := Cardinal(B[0]) or (Cardinal(B[1]) shl 8) or (Cardinal(B[2]) shl 16) or (Cardinal(B[3]) shl 24);
end;

function BEToUInt32(const B: array of Byte): Cardinal;
begin
  Result := (Cardinal(B[0]) shl 24) or (Cardinal(B[1]) shl 16) or (Cardinal(B[2]) shl 8) or Cardinal(B[3]);
end;

function MakeFourCC(a, b, c, d: AnsiChar): Cardinal;
begin
  Result := Cardinal(Byte(a)) or (Cardinal(Byte(b)) shl 8) or (Cardinal(Byte(c)) shl 16) or (Cardinal(Byte(d)) shl 24);
end;

function IsPNG(const Buf: PByte; Len: Integer): Boolean;
begin
  Result := (Len >= 8) and CompareMem(Buf, @PNG_SIG[0], 8);
end;

function IsDDS(const Buf: PByte; Len: Integer): Boolean;
begin
  Result := (Len >= 4) and CompareMem(Buf, @DDS_MAGIC[0], 4);
end;

function IsKTX1(const Buf: PByte; Len: Integer): Boolean;
begin
  Result := (Len >= 12) and CompareMem(Buf, @KTX1_IDENT[0], 12);
end;

function IsKTX2(const Buf: PByte; Len: Integer): Boolean;
begin
  Result := (Len >= 12) and CompareMem(Buf, @KTX2_IDENT[0], 12);
end;

function IsPVRv3(const Buf: PByte; Len: Integer): Boolean;
begin
  if Len < 4 then Exit(False);
  Result := Cardinal(Pointer(Buf)^) = PVRv3_MAGIC;
end;

function IsQOI(const Buf: PByte; Len: Integer): Boolean;
begin
  Result := (Len >= 4) and CompareMem(Buf, @QOI_MAGIC[0], 4);
end;

function IsRadianceHDR(const Buf: PByte; Len: Integer): Boolean;
begin
  Result := (Len >= 2) and (Buf[0] = Ord('#')) and (Buf[1] = Ord('?'));
end;

{ sRGB DXGI list (partial): these DXGI enum values correspond to sRGB formats.
  This is not exhaustive but covers common sRGB DXGI_FORMAT entries used in DDS/DX10. }
function DXGIFormatIsSRGB(dxgi: Cardinal): Boolean;
const
  DXGI_FORMAT_R8G8B8A8_UNORM_SRGB = 28;
  DXGI_FORMAT_BC1_UNORM_SRGB = 71;
  DXGI_FORMAT_BC2_UNORM_SRGB = 74;
  DXGI_FORMAT_BC3_UNORM_SRGB = 77;
  DXGI_FORMAT_BC7_UNORM_SRGB = 98;
  DXGI_FORMAT_R8G8B8A8_UNORM_SRGB_BC = 28; // alias
begin
  Result := dxgi in [DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,
                     DXGI_FORMAT_BC1_UNORM_SRGB,
                     DXGI_FORMAT_BC2_UNORM_SRGB,
                     DXGI_FORMAT_BC3_UNORM_SRGB,
                     DXGI_FORMAT_BC7_UNORM_SRGB];
end;

{ Parse key/value data as contiguous blob where each entry starts with u32 length (little-endian),
  then key\0value bytes padded to 4 bytes (KTX1 style). We'll scan the concatenated data for an ASCII
  'allocationGroupID=' substring and return the value if present. }
function ScanKTXKeyValueForAllocation(const Data: TBytes): string;
var
  idx, total: Integer;
  entrySize: Cardinal;
  s: string;
  pv: PByte;
  entryBytes: TBytes;
  posEq: Integer;
begin
  Result := '';
  total := Length(Data);
  idx := 0;
  pv := nil;
  while idx + 4 <= total do
  begin
    // read u32 little-endian length
    entrySize := Cardinal(Data[idx]) or (Cardinal(Data[idx+1]) shl 8) or (Cardinal(Data[idx+2]) shl 16) or (Cardinal(Data[idx+3]) shl 24);
    Inc(idx, 4);
    if entrySize = 0 then Continue;
    if idx + Integer(entrySize) > total then Break;
    SetLength(entryBytes, entrySize);
    Move(Data[idx], entryBytes[0], entrySize);
    // try to find "allocationGroupID=" in the ASCII block
    s := TEncoding.ASCII.GetString(entryBytes);
    posEq := Pos('allocationGroupID=', s);
    if posEq > 0 then
    begin
      // value may follow '=' to end of entry or until null
      var val := Copy(s, posEq + Length('allocationGroupID='), MaxInt);
      // trim at null if present
      var z := Pos(#0, val);
      if z > 0 then val := Copy(val, 1, z - 1);
      Result := val;
      Exit;
    end;
    // advance idx padded to 4
    Inc(idx, Integer((entrySize + 3) and not 3));
  end;
end;

{ Public inspector. It tries format detection then calls format-specific header readers.
  The routine is best-effort and intentionally conservative (returns unknown rather than guessing). }

function InspectTexture(AStream: TStream; out Info: TTextureInfo): Boolean;
var
  Buf: array[0..511] of Byte;
  n: Integer;
  p: PByte;
  // format-specific temporaries
  ddsHdr: TDDS_HEADER;
  ddsDx10: TDDS_HEADER_DX10;
  ktx1: TKTX1Header;
  ktx2: TKTX2Header;
  pvr: TPVRv3Header;
  qhdr: TQOIHeader;
  pngLenBE: Cardinal;
  chunkType: array[0..3] of AnsiChar;
  chunkLenBE: Cardinal;
  kvBytes: TBytes;
  readLen: Integer;
  strFound: string;
  pngChunkData: TBytes;
  tmpPos: Int64;
  scanBufSz,
  readSz:Int64;
  // helper lambda
  procedure SetUnknown;
  begin
    Info.FormatKind := tfUnknown;
    Info.Width := -1;
    Info.Height := -1;
    Info.MipMapCount := -1;
    Info.HasMipMaps := False;
    Info.IsSRGB := False;
    Info.AllocationGroupID := '';
  end;
begin
  Result := False;
  SetUnknown;
  if AStream = nil then Exit;

  // Peek head
  n := PeekBytes(AStream, @Buf[0], SizeOf(Buf));
  p := @Buf[0];

  // Default unknowns
  Info.Width := -1;
  Info.Height := -1;
  Info.MipMapCount := -1;
  Info.HasMipMaps := False;
  Info.IsSRGB := False;
  Info.AllocationGroupID := '';

  // DDS
  if IsDDS(p, n) then
  begin
    Info.FormatKind := tfDDS;
    try
      AStream.Position := 0;
      // skip magic
      AStream.Seek(4, soBeginning);
      ReadExactly(AStream, ddsHdr, SizeOf(ddsHdr));
      Info.Width := Integer(ddsHdr.dwWidth);
      Info.Height := Integer(ddsHdr.dwHeight);
      if ddsHdr.dwMipMapCount <> 0 then
        Info.MipMapCount := Integer(ddsHdr.dwMipMapCount)
      else
        Info.MipMapCount := -1;
      Info.HasMipMaps := (Info.MipMapCount > 1);
      // check DX10
      if ddsHdr.ddspf.dwFourCC = MakeFourCC('D','X','1','0') then
      begin
        ReadExactly(AStream, ddsDx10, SizeOf(ddsDx10));
        Info.IsSRGB := DXGIFormatIsSRGB(ddsDx10.dxgiFormat);
      end else
        Info.IsSRGB := False;
      // no standard allocationGroupID in DDS; leave empty
      Result := True;
      Exit;
    except
      Result := False;
      Exit;
    end;
  end;

  // KTX1
  if IsKTX1(p, n) then
  begin
    Info.FormatKind := tfKTX1;
    try
      AStream.Position := 0;
      ReadExactly(AStream, ktx1, SizeOf(ktx1));
      // header fields are little-endian per spec
      Info.Width := Integer(ktx1.pixelWidth);
      Info.Height := Integer(ktx1.pixelHeight);
      if ktx1.numberOfMipmapLevels <> 0 then
        Info.MipMapCount := Integer(ktx1.numberOfMipmapLevels)
      else
        Info.MipMapCount := -1; // 0 means "generate count from levels" (in spec).
      Info.HasMipMaps := (Info.MipMapCount > 1);
      // glInternalFormat common sRGB value check (GL_SRGB8_ALPHA8 = $8C43)
      Info.IsSRGB := (ktx1.glInternalFormat = $8C43);
      // Read key/value data if present
      if ktx1.bytesOfKeyValueData > 0 then
      begin
        SetLength(kvBytes, ktx1.bytesOfKeyValueData);
        AStream.Seek(SizeOf(ktx1), soBeginning);
        ReadExactly(AStream, kvBytes[0], Length(kvBytes));
        strFound := ScanKTXKeyValueForAllocation(kvBytes);
        if strFound <> '' then
          Info.AllocationGroupID := strFound;
      end;
      Result := True;
      Exit;
    except
      Result := False;
      Exit;
    end;
  end;

  // KTX2 (basic header read)
  if IsKTX2(p, n) then
  begin
    Info.FormatKind := tfKTX2;
    try
      AStream.Position := 0;
      ReadExactly(AStream, ktx2, SizeOf(ktx2));
      Info.Width := Integer(ktx2.pixelWidth);
      Info.Height := Integer(ktx2.pixelHeight);
      if ktx2.levelCount <> 0 then
        Info.MipMapCount := Integer(ktx2.levelCount)
      else
        Info.MipMapCount := -1;
      Info.HasMipMaps := (Info.MipMapCount > 1);
      // vkFormat values for sRGB exist: VK_FORMAT_R8G8B8A8_SRGB etc.
      // We do a conservative check for common vkFormat sRGB values (example values):
      const
        VK_FORMAT_R8G8B8A8_SRGB = 43; // example; you may want to expand this mapping
      begin
        Info.IsSRGB := (ktx2.vkFormat = VK_FORMAT_R8G8B8A8_SRGB);
      end;
      // Best-effort scan for ASCII "allocationGroupID=" in next 16KB of file (likely in key/value or supercompressionGlobalData)
      tmpPos := AStream.Position;
      try
        scanBufSz := System.Math.Min(AStream.Size - tmpPos, Int64(16384));
        if scanBufSz > 0 then
        begin
          SetLength(kvBytes, scanBufSz);
          AStream.ReadBuffer(kvBytes[0], scanBufSz);
          strFound := TEncoding.ASCII.GetString(kvBytes);
          var pidx := Pos('allocationGroupID=', strFound);
          if pidx > 0 then
          begin
            var rest := Copy(strFound, pidx + Length('allocationGroupID='), MaxInt);
            var z := Pos(#0, rest);
            if z > 0 then rest := Copy(rest, 1, z - 1);
            Info.AllocationGroupID := rest;
          end;
        end;
      finally
        AStream.Position := tmpPos;
      end;
      Result := True;
      Exit;
    except
      Result := False;
      Exit;
    end;
  end;

  // PVRv3
  if IsPVRv3(p, n) then
  begin
    Info.FormatKind := tfPVRv3;
    try
      AStream.Position := 0;
      ReadExactly(AStream, pvr, SizeOf(pvr));
      Info.Width := Integer(pvr.width);
      Info.Height := Integer(pvr.height);
      if pvr.mipMapCount <> 0 then
        Info.MipMapCount := Integer(pvr.mipMapCount)
      else
        Info.MipMapCount := -1;
      Info.HasMipMaps := (Info.MipMapCount > 1);
      Info.IsSRGB := (pvr.colourSpace = 1);
      // Read metadata block (metaDataSize bytes) and search ASCII allocationGroupID
      if pvr.metaDataSize > 0 then
      begin
        SetLength(kvBytes, pvr.metaDataSize);
        ReadExactly(AStream, kvBytes[0], Length(kvBytes));
        strFound := TEncoding.ASCII.GetString(kvBytes);
        var idx := Pos('allocationGroupID=', strFound);
        if idx > 0 then
        begin
          var rest := Copy(strFound, idx + Length('allocationGroupID='), MaxInt);
          var z := Pos(#0, rest);
          if z > 0 then rest := Copy(rest, 1, z - 1);
          Info.AllocationGroupID := rest;
        end;
      end;
      Result := True;
      Exit;
    except
      Result := False;
      Exit;
    end;
  end;

  // QOI
  if IsQOI(p, n) then
  begin
    Info.FormatKind := tfQOI;
    if n >= SizeOf(TQOIHeader) then
    begin
      Move(Buf[0], qhdr, SizeOf(qhdr));
      Info.Width := Integer(BEToUInt32(qhdr.widthBE));
      Info.Height := Integer(BEToUInt32(qhdr.heightBE));
      Info.MipMapCount := -1;
      Info.HasMipMaps := False;
      Info.IsSRGB := (qhdr.colorspace = 0); // 0 = sRGB with linear alpha, 1 = linear
      // QOI doesn't carry allocationGroupID
    end;
    Result := True;
    Exit;
  end;

  // PNG: check sRGB chunk and text chunks (tEXt/iTXt) for allocationGroupID
  if IsPNG(p, n) then
  begin
    Info.FormatKind := tfPNG;
    try
      AStream.Position := 8; // skip signature
      while AStream.Position + 8 <= AStream.Size do
      begin
        // read length (big-endian) and chunk type
        ReadExactly(AStream, chunkLenBE, 4);
        chunkLenBE := BEToUInt32(TBytes.Create(Byte(chunkLenBE shr 24), Byte((chunkLenBE shr 16) and $FF), Byte((chunkLenBE shr 8) and $FF), Byte(chunkLenBE and $FF))); // normalize
        ReadExactly(AStream, chunkType, 4);
        readLen := Integer(chunkLenBE);
        if readLen < 0 then Break;
        if readLen > 0 then
        begin
          SetLength(pngChunkData, readLen);
          ReadExactly(AStream, pngChunkData[0], readLen);
        end else
          pngChunkData := nil;
        // read CRC (4)
        if AStream.Position + 4 <= AStream.Size then
        begin
          AStream.Seek(4, soCurrent);
        end;
        var ctype := string(chunkType);
        if ctype = 'IHDR' then
        begin
          // IHDR contains width/height (big-endian)
          if Length(pngChunkData) >= 8 then
          begin
            var wBE := TBytes.Create(pngChunkData[0], pngChunkData[1], pngChunkData[2], pngChunkData[3]);
            var hBE := TBytes.Create(pngChunkData[4], pngChunkData[5], pngChunkData[6], pngChunkData[7]);
            Info.Width := Integer(BEToUInt32(wBE));
            Info.Height := Integer(BEToUInt32(hBE));
          end;
        end
        else if (ctype = 'sRGB') or (ctype = 'iCCP') then
        begin
          Info.IsSRGB := True;
        end
        else if (ctype = 'tEXt') or (ctype = 'iTXt') then
        begin
          // parse as text and look for allocationGroupID
          var s := TEncoding.ASCII.GetString(pngChunkData);
          var idx := Pos('allocationGroupID=', s);
          if idx > 0 then
          begin
            var rest := Copy(s, idx + Length('allocationGroupID='), MaxInt);
            var z := Pos(#0, rest);
            if z > 0 then rest := Copy(rest, 1, z - 1);
            Info.AllocationGroupID := rest;
          end;
        end
        else if ctype = 'IEND' then
        begin
          Break;
        end;
      end;
      Result := True;
      Exit;
    except
      Result := False;
      Exit;
    end;
  end;

  // Radiance HDR (ASCII header lines)
  if IsRadianceHDR(p, n) then
  begin
    Info.FormatKind := tfRadianceHDR;
    try
      // read first 4KB header (HDR headers are textual until a blank line)
      readSz :=  System.Math.Min(AStream.Size - AStream.Position, Int64(4096));
      if readSz <= 0 then readSz := n;
      SetLength(kvBytes, readSz);
      AStream.Position := 0;
      AStream.ReadBuffer(kvBytes[0], readSz);
      strFound := TEncoding.ASCII.GetString(kvBytes);
      // check for 'FORMAT=' or '#?RADIANCE'
      Info.IsSRGB := False; // Radiance headers don't typically indicate sRGB; treat as linear by default
      var idx := Pos('allocationGroupID=', strFound);
      if idx > 0 then
      begin
        var rest := Copy(strFound, idx + Length('allocationGroupID='), MaxInt);
        var z := Pos(#10, rest); // line end
        if z > 0 then rest := Trim(Copy(rest, 1, z - 1));
        Info.AllocationGroupID := rest;
      end;
      Result := True;
      Exit;
    except
      Result := False;
      Exit;
    end;
  end;

  // Fallback: unknown format; attempt to recognize PNG/JPEG/BMP/JPG by magic (already partly covered)
  // try to detect JPG magic
  if (n >= 3) and (Buf[0] = $FF) and (Buf[1] = $D8) and (Buf[2] = $FF) then
  begin
    Info.FormatKind := tfJPEG;
    Result := True;
    Exit;
  end;

  if (n >= 2) and (Buf[0] = Ord('B')) and (Buf[1] = Ord('M')) then
  begin
    Info.FormatKind := tfBMP;
    Result := True;
    Exit;
  end;

  // Unknown / unsupported
  Info.FormatKind := tfUnknown;
  Result := True;
end;

end.