unit Vulkan_PixelInfo;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Math,
  Vulkan; // adjust if necessary for PasVulkan unit names

type


  TvgPixelKind = (
    pkUnknown,
    // 8-bit family (normalized/scaled/signed)
    pkR8, pkR8G8, pkR8G8B8, pkB8G8R8, pkR8G8B8A8, pkB8G8R8A8,
    // 8-bit UINT family
    pkR8_UINT, pkR8G8_UINT, pkR8G8B8_UINT, pkB8G8R8_UINT, pkR8G8B8A8_UINT, pkB8G8R8A8_UINT,
    // Packed 16 / 32
    pkR5G6B5, pkB5G6R5, pkR5G5B5A1, pkB5G5R5A1, pkA1R5G5B5,
    pkA2R10G10B10, pkA2B10G10R10, 
    pkA2R10G10B10_UINT, pkA2B10G10R10_UINT,
    pkB10G11R11_UFLOAT, pkE5B9G9R9_UFLOAT,
    // 16-bit components (normalized/scaled/signed/float)
    pkR16, pkR16G16, pkR16G16B16, pkR16G16B16A16,
    // 16-bit UINT family
    pkR16_UINT, pkR16G16_UINT, pkR16G16B16_UINT, pkR16G16B16A16_UINT,
    // 32-bit components (includes UINT/SINT/SFLOAT)
    pkR32, pkR32G32, pkR32G32B32, pkR32G32B32A32,
    // 32-bit UINT family (explicit)
    pkR32_UINT, pkR32G32_UINT, pkR32G32B32_UINT, pkR32G32B32A32_UINT,
    // 64-bit components (includes UINT/SINT/SFLOAT)
    pkR64, pkR64G64, pkR64G64B64, pkR64G64B64A64,
    // 64-bit UINT family (explicit)
    pkR64_UINT, pkR64G64_UINT, pkR64G64B64_UINT, pkR64G64B64A64_UINT,
    // Depth / Stencil
    pkD16_UNORM, pkD32_SFLOAT, pkS8_UINT, pkD24_UNORM_S8_UINT, pkD16_UNORM_S8_UINT, pkD32_SFLOAT_S8_UINT
  );

  TvgPixelData = packed record
    case TvgPixelKind of
      // 8-bit normalized/scaled/signed variants
      pkR8:               (R8: packed record R: UInt8; end);
      pkR8G8:             (R8G8: packed record R, G: UInt8; end);
      pkR8G8B8:           (R8G8B8: packed record R, G, B: UInt8; end);
      pkB8G8R8:           (B8G8R8: packed record B, G, R: UInt8; end);
      pkR8G8B8A8:         (R8G8B8A8: packed record R, G, B, A: UInt8; end);
      pkB8G8R8A8:         (B8G8R8A8: packed record B, G, R, A: UInt8; end);

      // 8-bit UINT variants (same storage, different semantic)
      pkR8_UINT:          (R8_UINT: packed record R: UInt8; end);
      pkR8G8_UINT:        (R8G8_UINT: packed record R, G: UInt8; end);
      pkR8G8B8_UINT:      (R8G8B8_UINT: packed record R, G, B: UInt8; end);
      pkB8G8R8_UINT:      (B8G8R8_UINT: packed record B, G, R: UInt8; end);
      pkR8G8B8A8_UINT:    (R8G8B8A8_UINT: packed record R, G, B, A: UInt8; end);
      pkB8G8R8A8_UINT:    (B8G8R8A8_UINT: packed record B, G, R, A: UInt8; end);

      // Packed 16-bit
      pkR5G6B5:           (R5G6B5: packed record RG: UInt16; end);
      pkB5G6R5:           (B5G6R5: packed record RG: UInt16; end);
      pkR5G5B5A1:         (R5G5B5A1: packed record RG: UInt16; end);
      pkB5G5R5A1:         (B5G5R5A1: packed record RG: UInt16; end);
      pkA1R5G5B5:         (A1R5G5B5: packed record RG: UInt16; end);

      // Packed 32-bit
      pkA2R10G10B10:      (A2R10G10B10: UInt32);
      pkA2B10G10R10:      (A2B10G10R10: UInt32);
      pkA2R10G10B10_UINT: (A2R10G10B10_UINT: UInt32);
      pkA2B10G10R10_UINT: (A2B10G10R10_UINT: UInt32);
      pkB10G11R11_UFLOAT: (B10G11R11: UInt32);
      pkE5B9G9R9_UFLOAT:  (E5B9G9R9: UInt32);

      // 16-bit components (normalized/scaled/signed/float)
      pkR16:              (R16: UInt16);
      pkR16G16:           (R16G16: packed record R, G: UInt16; end);
      pkR16G16B16:        (R16G16B16: packed record R, G, B: UInt16; end);
      pkR16G16B16A16:     (R16G16B16A16: packed record R, G, B, A: UInt16; end);

      // 16-bit UINT variants
      pkR16_UINT:         (R16_UINT: UInt16);
      pkR16G16_UINT:      (R16G16_UINT: packed record R, G: UInt16; end);
      pkR16G16B16_UINT:   (R16G16B16_UINT: packed record R, G, B: UInt16; end);
      pkR16G16B16A16_UINT:(R16G16B16A16_UINT: packed record R, G, B, A: UInt16; end);

      // 32-bit components (mixed UINT/SINT/SFLOAT)
      pkR32:              (R32: UInt32);
      pkR32G32:           (R32G32: packed record R, G: UInt32; end);
      pkR32G32B32:        (R32G32B32: packed record R, G, B: UInt32; end);
      pkR32G32B32A32:     (R32G32B32A32: packed record R, G, B, A: UInt32; end);

      // 32-bit UINT variants (explicit)
      pkR32_UINT:         (R32_UINT: UInt32);
      pkR32G32_UINT:      (R32G32_UINT: packed record R, G: UInt32; end);
      pkR32G32B32_UINT:   (R32G32B32_UINT: packed record R, G, B: UInt32; end);
      pkR32G32B32A32_UINT:(R32G32B32A32_UINT: packed record R, G, B, A: UInt32; end);

      // 64-bit components (mixed UINT/SINT/SFLOAT)
      pkR64:              (R64: UInt64);
      pkR64G64:           (R64G64: packed record R, G: UInt64; end);
      pkR64G64B64:        (R64G64B64: packed record R, G, B: UInt64; end);
      pkR64G64B64A64:     (R64G64B64A64: packed record R, G, B, A: UInt64; end);

      // 64-bit UINT variants (explicit)
      pkR64_UINT:         (R64_UINT: UInt64);
      pkR64G64_UINT:      (R64G64_UINT: packed record R, G: UInt64; end);
      pkR64G64B64_UINT:   (R64G64B64_UINT: packed record R, G, B: UInt64; end);
      pkR64G64B64A64_UINT:(R64G64B64A64_UINT: packed record R, G, B, A: UInt64; end);

      // Depth / Stencil
      pkD16_UNORM:        (D16: UInt16);
      pkD32_SFLOAT:       (D32: Single);
      pkS8_UINT:          (S8: UInt8);
      pkD24_UNORM_S8_UINT:(D24S8: UInt32);
      pkD16_UNORM_S8_UINT:(D16S8: packed record DS: UInt32; end);
      pkD32_SFLOAT_S8_UINT:(D32S8: packed record DS0, DS1: UInt32; end);

      pkUnknown:          (Raw: array[0..31] of Byte);
  end;

 // Sampling radius options
  TvgPixelSampleRadius = (
    psr_1x1,    // 1x1 = single pixel (center only)
    psr_3x3,    // 3x3 = 1 pixel radius around center (9 pixels total)
    psr_5x5,    // 5x5 = 2 pixel radius around center (25 pixels total)
    psr_7x7,    // 7x7 = 3 pixel radius around center (49 pixels total)
    psr_9x9     // 9x9 = 4 pixel radius around center (81 pixels total)
  );


  TVkFormatPixelInfo = record
    Kind: TvgPixelKind;
    BytesPerPixel: Integer;
    BytesPerBlock: Integer;
    BlockWidth: Integer;
    BlockHeight: Integer;
    IsCompressed: Boolean;
  end;


  TvgPixelDataArray = array of array of TvgPixelData;


  // Structure to hold Object ID with its count
  TObjectIDCount = record
    ObjectID: UInt32;
    Count: Integer;
  end;

  // Result of Object ID analysis
  TObjectIDResult = record
    MostFrequentID : UInt64;
    Frequency      : Integer;
    TotalPixels    : Integer;
    UniqueIDs      : Integer;
    IsValid        : Boolean;
  end;

  // Helper class for Object ID analysis
  TvgObjectIDAnalyzer = class
  private
    class function ExtractObjectID(const Pixel: TvgPixelData;
                                  const Info: TVkFormatPixelInfo): UInt64; static;
  public
    // METHOD 1: Fast hash-based counting (recommended for most cases)
    class function FindMostFrequentID_Hash(
        const PixelArray: TvgPixelDataArray;
        const PixelInfo: TVkFormatPixelInfo;
        SampleSize: Integer): TObjectIDResult; static;

    // METHOD 2: Array-based counting (faster for small arrays, less memory)
    class function FindMostFrequentID_Array(
        const PixelArray: TvgPixelDataArray;
        const PixelInfo: TVkFormatPixelInfo;
        SampleSize: Integer): TObjectIDResult; static;

    // METHOD 3: Center-weighted algorithm (prioritizes center pixel)
    class function FindMostFrequentID_Weighted(
        const PixelArray: TvgPixelDataArray;
        const PixelInfo: TVkFormatPixelInfo;
        SampleSize: Integer;
        CenterWeight: Integer = 3): TObjectIDResult; static;

    // METHOD 4: Ignore background ID (e.g., ID 0 or $FFFFFFFF)
    class function FindMostFrequentID_NoBackground(
        const PixelArray: TvgPixelDataArray;
        const PixelInfo: TVkFormatPixelInfo;
        SampleSize: Integer;
        BackgroundID: UInt32 = 0): TObjectIDResult; static;

    // Helper: Get all unique IDs with their counts
    class function GetIDFrequencies(
        const PixelArray: TvgPixelDataArray;
        const PixelInfo: TVkFormatPixelInfo;
        SampleSize: Integer): TArray<TObjectIDCount>; static;
  end;

function GetVkFormatPixelInfo(const aFormat: TVkFormat): TVkFormatPixelInfo; inline;
function VkFormatEffectiveBytesPerPixelF(const Info: TVkFormatPixelInfo): Single; inline;
function VkCompressedImageSize(const Width, Height: Integer; const Info: TVkFormatPixelInfo): Integer; inline;
procedure LoadPixel(const Src; out Dst: TvgPixelData; const Info: TVkFormatPixelInfo); inline;

implementation

function GetVkFormatPixelInfo(const aFormat: TVkFormat): TVkFormatPixelInfo;
begin
  Result.Kind := pkUnknown;
  Result.BytesPerPixel := 0;
  Result.BytesPerBlock := 0;
  Result.BlockWidth := 1;
  Result.BlockHeight := 1;
  Result.IsCompressed := False;

  case aFormat of
    // ─ 8-bit components (UNORM/SNORM/USCALED/SSCALED/SINT/SRGB) ─
    VK_FORMAT_R8_UNORM, VK_FORMAT_R8_SNORM, VK_FORMAT_R8_USCALED,
    VK_FORMAT_R8_SSCALED, VK_FORMAT_R8_SINT, VK_FORMAT_R8_SRGB:
      begin Result.Kind := pkR8; Result.BytesPerPixel := 1; end;

    VK_FORMAT_R8G8_UNORM, VK_FORMAT_R8G8_SNORM, VK_FORMAT_R8G8_USCALED,
    VK_FORMAT_R8G8_SSCALED, VK_FORMAT_R8G8_SINT, VK_FORMAT_R8G8_SRGB:
      begin Result.Kind := pkR8G8; Result.BytesPerPixel := 2; end;

    VK_FORMAT_R8G8B8_UNORM, VK_FORMAT_R8G8B8_SNORM, VK_FORMAT_R8G8B8_USCALED,
    VK_FORMAT_R8G8B8_SSCALED, VK_FORMAT_R8G8B8_SINT, VK_FORMAT_R8G8B8_SRGB:
      begin Result.Kind := pkR8G8B8; Result.BytesPerPixel := 3; end;

    VK_FORMAT_B8G8R8_UNORM, VK_FORMAT_B8G8R8_SNORM, VK_FORMAT_B8G8R8_USCALED,
    VK_FORMAT_B8G8R8_SSCALED, VK_FORMAT_B8G8R8_SINT, VK_FORMAT_B8G8R8_SRGB:
      begin Result.Kind := pkB8G8R8; Result.BytesPerPixel := 3; end;

    VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_R8G8B8A8_SNORM,
    VK_FORMAT_R8G8B8A8_USCALED, VK_FORMAT_R8G8B8A8_SSCALED,
    VK_FORMAT_R8G8B8A8_SINT, VK_FORMAT_R8G8B8A8_SRGB:
      begin Result.Kind := pkR8G8B8A8; Result.BytesPerPixel := 4; end;

    VK_FORMAT_B8G8R8A8_UNORM, VK_FORMAT_B8G8R8A8_SNORM,
    VK_FORMAT_B8G8R8A8_USCALED, VK_FORMAT_B8G8R8A8_SSCALED,
    VK_FORMAT_B8G8R8A8_SINT, VK_FORMAT_B8G8R8A8_SRGB:
      begin Result.Kind := pkB8G8R8A8; Result.BytesPerPixel := 4; end;

    // ─ 8-bit UINT variants ─
    VK_FORMAT_R8_UINT:
      begin Result.Kind := pkR8_UINT; Result.BytesPerPixel := 1; end;

    VK_FORMAT_R8G8_UINT:
      begin Result.Kind := pkR8G8_UINT; Result.BytesPerPixel := 2; end;

    VK_FORMAT_R8G8B8_UINT:
      begin Result.Kind := pkR8G8B8_UINT; Result.BytesPerPixel := 3; end;

    VK_FORMAT_B8G8R8_UINT:
      begin Result.Kind := pkB8G8R8_UINT; Result.BytesPerPixel := 3; end;

    VK_FORMAT_R8G8B8A8_UINT:
      begin Result.Kind := pkR8G8B8A8_UINT; Result.BytesPerPixel := 4; end;

    VK_FORMAT_B8G8R8A8_UINT:
      begin Result.Kind := pkB8G8R8A8_UINT; Result.BytesPerPixel := 4; end;

    // ─ Packed 16-bit ─
    VK_FORMAT_R5G6B5_UNORM_PACK16:
      begin Result.Kind := pkR5G6B5; Result.BytesPerPixel := 2; end;
    VK_FORMAT_B5G6R5_UNORM_PACK16:
      begin Result.Kind := pkB5G6R5; Result.BytesPerPixel := 2; end;
    VK_FORMAT_R5G5B5A1_UNORM_PACK16:
      begin Result.Kind := pkR5G5B5A1; Result.BytesPerPixel := 2; end;
    VK_FORMAT_B5G5R5A1_UNORM_PACK16:
      begin Result.Kind := pkB5G5R5A1; Result.BytesPerPixel := 2; end;
    VK_FORMAT_A1R5G5B5_UNORM_PACK16:
      begin Result.Kind := pkA1R5G5B5; Result.BytesPerPixel := 2; end;

    // ─ Packed 32-bit (UNORM/SNORM/USCALED/SSCALED/SINT) ─
    VK_FORMAT_A2R10G10B10_UNORM_PACK32, VK_FORMAT_A2R10G10B10_SNORM_PACK32,
    VK_FORMAT_A2R10G10B10_USCALED_PACK32, VK_FORMAT_A2R10G10B10_SSCALED_PACK32,
    VK_FORMAT_A2R10G10B10_SINT_PACK32:
      begin Result.Kind := pkA2R10G10B10; Result.BytesPerPixel := 4; end;

    VK_FORMAT_A2B10G10R10_UNORM_PACK32, VK_FORMAT_A2B10G10R10_SNORM_PACK32,
    VK_FORMAT_A2B10G10R10_USCALED_PACK32, VK_FORMAT_A2B10G10R10_SSCALED_PACK32,
    VK_FORMAT_A2B10G10R10_SINT_PACK32:
      begin Result.Kind := pkA2B10G10R10; Result.BytesPerPixel := 4; end;

    // ─ Packed 32-bit UINT variants ─
    VK_FORMAT_A2R10G10B10_UINT_PACK32:
      begin Result.Kind := pkA2R10G10B10_UINT; Result.BytesPerPixel := 4; end;

    VK_FORMAT_A2B10G10R10_UINT_PACK32:
      begin Result.Kind := pkA2B10G10R10_UINT; Result.BytesPerPixel := 4; end;

    VK_FORMAT_B10G11R11_UFLOAT_PACK32:
      begin Result.Kind := pkB10G11R11_UFLOAT; Result.BytesPerPixel := 4; end;
    VK_FORMAT_E5B9G9R9_UFLOAT_PACK32:
      begin Result.Kind := pkE5B9G9R9_UFLOAT; Result.BytesPerPixel := 4; end;

    // ─ 16-bit components (UNORM/SNORM/USCALED/SSCALED/SINT/SFLOAT) ─
    VK_FORMAT_R16_UNORM, VK_FORMAT_R16_SNORM, VK_FORMAT_R16_USCALED,
    VK_FORMAT_R16_SSCALED, VK_FORMAT_R16_SINT, VK_FORMAT_R16_SFLOAT:
      begin Result.Kind := pkR16; Result.BytesPerPixel := 2; end;

    VK_FORMAT_R16G16_UNORM, VK_FORMAT_R16G16_SNORM, VK_FORMAT_R16G16_USCALED,
    VK_FORMAT_R16G16_SSCALED, VK_FORMAT_R16G16_SINT, VK_FORMAT_R16G16_SFLOAT:
      begin Result.Kind := pkR16G16; Result.BytesPerPixel := 4; end;

    VK_FORMAT_R16G16B16_UNORM, VK_FORMAT_R16G16B16_SNORM, VK_FORMAT_R16G16B16_USCALED,
    VK_FORMAT_R16G16B16_SSCALED, VK_FORMAT_R16G16B16_SINT, VK_FORMAT_R16G16B16_SFLOAT:
      begin Result.Kind := pkR16G16B16; Result.BytesPerPixel := 6; end;

    VK_FORMAT_R16G16B16A16_UNORM, VK_FORMAT_R16G16B16A16_SNORM,
    VK_FORMAT_R16G16B16A16_USCALED, VK_FORMAT_R16G16B16A16_SSCALED,
    VK_FORMAT_R16G16B16A16_SINT, VK_FORMAT_R16G16B16A16_SFLOAT:
      begin Result.Kind := pkR16G16B16A16; Result.BytesPerPixel := 8; end;

    // ─ 16-bit UINT variants ─
    VK_FORMAT_R16_UINT:
      begin Result.Kind := pkR16_UINT; Result.BytesPerPixel := 2; end;

    VK_FORMAT_R16G16_UINT:
      begin Result.Kind := pkR16G16_UINT; Result.BytesPerPixel := 4; end;

    VK_FORMAT_R16G16B16_UINT:
      begin Result.Kind := pkR16G16B16_UINT; Result.BytesPerPixel := 6; end;

    VK_FORMAT_R16G16B16A16_UINT:
      begin Result.Kind := pkR16G16B16A16_UINT; Result.BytesPerPixel := 8; end;

    // ─ 32-bit components (SINT/SFLOAT) ─
    VK_FORMAT_R32_SINT, VK_FORMAT_R32_SFLOAT:
      begin Result.Kind := pkR32; Result.BytesPerPixel := 4; end;

    VK_FORMAT_R32G32_SINT, VK_FORMAT_R32G32_SFLOAT:
      begin Result.Kind := pkR32G32; Result.BytesPerPixel := 8; end;

    VK_FORMAT_R32G32B32_SINT, VK_FORMAT_R32G32B32_SFLOAT:
      begin Result.Kind := pkR32G32B32; Result.BytesPerPixel := 12; end;

    VK_FORMAT_R32G32B32A32_SINT, VK_FORMAT_R32G32B32A32_SFLOAT:
      begin Result.Kind := pkR32G32B32A32; Result.BytesPerPixel := 16; end;

    // ─ 32-bit UINT variants ─
    VK_FORMAT_R32_UINT:
      begin Result.Kind := pkR32_UINT; Result.BytesPerPixel := 4; end;

    VK_FORMAT_R32G32_UINT:
      begin Result.Kind := pkR32G32_UINT; Result.BytesPerPixel := 8; end;

    VK_FORMAT_R32G32B32_UINT:
      begin Result.Kind := pkR32G32B32_UINT; Result.BytesPerPixel := 12; end;

    VK_FORMAT_R32G32B32A32_UINT:
      begin Result.Kind := pkR32G32B32A32_UINT; Result.BytesPerPixel := 16; end;

    // ─ 64-bit components (SINT/SFLOAT) ─
    VK_FORMAT_R64_SINT, VK_FORMAT_R64_SFLOAT:
      begin Result.Kind := pkR64; Result.BytesPerPixel := 8; end;

    VK_FORMAT_R64G64_SINT, VK_FORMAT_R64G64_SFLOAT:
      begin Result.Kind := pkR64G64; Result.BytesPerPixel := 16; end;

    VK_FORMAT_R64G64B64_SINT, VK_FORMAT_R64G64B64_SFLOAT:
      begin Result.Kind := pkR64G64B64; Result.BytesPerPixel := 24; end;

    VK_FORMAT_R64G64B64A64_SINT, VK_FORMAT_R64G64B64A64_SFLOAT:
      begin Result.Kind := pkR64G64B64A64; Result.BytesPerPixel := 32; end;

    // ─ 64-bit UINT variants ─
    VK_FORMAT_R64_UINT:
      begin Result.Kind := pkR64_UINT; Result.BytesPerPixel := 8; end;

    VK_FORMAT_R64G64_UINT:
      begin Result.Kind := pkR64G64_UINT; Result.BytesPerPixel := 16; end;

    VK_FORMAT_R64G64B64_UINT:
      begin Result.Kind := pkR64G64B64_UINT; Result.BytesPerPixel := 24; end;

    VK_FORMAT_R64G64B64A64_UINT:
      begin Result.Kind := pkR64G64B64A64_UINT; Result.BytesPerPixel := 32; end;

    // ─ Depth / Stencil ─
    VK_FORMAT_D16_UNORM:
      begin Result.Kind := pkD16_UNORM; Result.BytesPerPixel := 2; end;
    VK_FORMAT_D32_SFLOAT:
      begin Result.Kind := pkD32_SFLOAT; Result.BytesPerPixel := 4; end;
    VK_FORMAT_S8_UINT:
      begin Result.Kind := pkS8_UINT; Result.BytesPerPixel := 1; end;
    VK_FORMAT_D24_UNORM_S8_UINT:
      begin Result.Kind := pkD24_UNORM_S8_UINT; Result.BytesPerPixel := 4; end;
    VK_FORMAT_D16_UNORM_S8_UINT:
      begin Result.Kind := pkD16_UNORM_S8_UINT; Result.BytesPerPixel := 4; end;
    VK_FORMAT_D32_SFLOAT_S8_UINT:
      begin Result.Kind := pkD32_SFLOAT_S8_UINT; Result.BytesPerPixel := 8; end;

    // ─ Compressed block formats ─

    VK_FORMAT_BC1_RGB_UNORM_BLOCK, VK_FORMAT_BC1_RGB_SRGB_BLOCK,
    VK_FORMAT_BC1_RGBA_UNORM_BLOCK, VK_FORMAT_BC1_RGBA_SRGB_BLOCK,
    VK_FORMAT_BC4_UNORM_BLOCK, VK_FORMAT_BC4_SNORM_BLOCK:
      begin
        Result.IsCompressed := True;
        Result.BytesPerBlock := 8; Result.BlockWidth := 4; Result.BlockHeight := 4;
      end;

    VK_FORMAT_BC2_UNORM_BLOCK, VK_FORMAT_BC2_SRGB_BLOCK,
    VK_FORMAT_BC3_UNORM_BLOCK, VK_FORMAT_BC3_SRGB_BLOCK,
    VK_FORMAT_BC5_UNORM_BLOCK, VK_FORMAT_BC5_SNORM_BLOCK,
    VK_FORMAT_BC6H_UFLOAT_BLOCK, VK_FORMAT_BC6H_SFLOAT_BLOCK,
    VK_FORMAT_BC7_UNORM_BLOCK, VK_FORMAT_BC7_SRGB_BLOCK:
      begin
        Result.IsCompressed := True;
        Result.BytesPerBlock := 16; Result.BlockWidth := 4; Result.BlockHeight := 4;
      end;

    VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK, VK_FORMAT_ETC2_R8G8B8_SRGB_BLOCK,
    VK_FORMAT_ETC2_R8G8B8A1_UNORM_BLOCK, VK_FORMAT_ETC2_R8G8B8A1_SRGB_BLOCK:
      begin
        Result.IsCompressed := True;
        Result.BytesPerBlock := 8; Result.BlockWidth := 4; Result.BlockHeight := 4;
      end;

    VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK, VK_FORMAT_ETC2_R8G8B8A8_SRGB_BLOCK:
      begin
        Result.IsCompressed := True;
        Result.BytesPerBlock := 16; Result.BlockWidth := 4; Result.BlockHeight := 4;
      end;

    VK_FORMAT_EAC_R11_UNORM_BLOCK, VK_FORMAT_EAC_R11_SNORM_BLOCK:
      begin
        Result.IsCompressed := True;
        Result.BytesPerBlock := 8; Result.BlockWidth := 4; Result.BlockHeight := 4;
      end;

    VK_FORMAT_EAC_R11G11_UNORM_BLOCK, VK_FORMAT_EAC_R11G11_SNORM_BLOCK:
      begin
        Result.IsCompressed := True;
        Result.BytesPerBlock := 16; Result.BlockWidth := 4; Result.BlockHeight := 4;
      end;

    VK_FORMAT_ASTC_4x4_UNORM_BLOCK, VK_FORMAT_ASTC_4x4_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 4;  Result.BlockHeight := 4;  end;
    VK_FORMAT_ASTC_5x4_UNORM_BLOCK, VK_FORMAT_ASTC_5x4_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 5;  Result.BlockHeight := 4;  end;
    VK_FORMAT_ASTC_5x5_UNORM_BLOCK, VK_FORMAT_ASTC_5x5_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 5;  Result.BlockHeight := 5;  end;
    VK_FORMAT_ASTC_6x5_UNORM_BLOCK, VK_FORMAT_ASTC_6x5_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 6;  Result.BlockHeight := 5;  end;
    VK_FORMAT_ASTC_6x6_UNORM_BLOCK, VK_FORMAT_ASTC_6x6_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 6;  Result.BlockHeight := 6;  end;
    VK_FORMAT_ASTC_8x5_UNORM_BLOCK, VK_FORMAT_ASTC_8x5_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 8;  Result.BlockHeight := 5;  end;
    VK_FORMAT_ASTC_8x6_UNORM_BLOCK, VK_FORMAT_ASTC_8x6_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 8;  Result.BlockHeight := 6;  end;
    VK_FORMAT_ASTC_8x8_UNORM_BLOCK, VK_FORMAT_ASTC_8x8_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 8;  Result.BlockHeight := 8;  end;
    VK_FORMAT_ASTC_10x5_UNORM_BLOCK, VK_FORMAT_ASTC_10x5_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 10; Result.BlockHeight := 5;  end;
    VK_FORMAT_ASTC_10x6_UNORM_BLOCK, VK_FORMAT_ASTC_10x6_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 10; Result.BlockHeight := 6;  end;
    VK_FORMAT_ASTC_10x8_UNORM_BLOCK, VK_FORMAT_ASTC_10x8_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 10; Result.BlockHeight := 8;  end;
    VK_FORMAT_ASTC_10x10_UNORM_BLOCK, VK_FORMAT_ASTC_10x10_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 10; Result.BlockHeight := 10; end;
    VK_FORMAT_ASTC_12x10_UNORM_BLOCK, VK_FORMAT_ASTC_12x10_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 12; Result.BlockHeight := 10; end;
    VK_FORMAT_ASTC_12x12_UNORM_BLOCK, VK_FORMAT_ASTC_12x12_SRGB_BLOCK:
      begin Result.IsCompressed := True; Result.BytesPerBlock := 16; Result.BlockWidth := 12; Result.BlockHeight := 12; end;
  end;
end;

function VkFormatEffectiveBytesPerPixelF(const Info: TVkFormatPixelInfo): Single;
begin
  if not Info.IsCompressed then
    Result := Info.BytesPerPixel
  else
    Result := Info.BytesPerBlock / (Info.BlockWidth * Info.BlockHeight);
end;

function VkCompressedImageSize(const Width, Height: Integer; const Info: TVkFormatPixelInfo): Integer;
var
  BlocksX, BlocksY: Integer;
begin
  if not Info.IsCompressed then
    Exit(Width * Height * Info.BytesPerPixel);

  BlocksX := (Width  + Info.BlockWidth  - 1) div Info.BlockWidth;
  BlocksY := (Height + Info.BlockHeight - 1) div Info.BlockHeight;
  Result := BlocksX * BlocksY * Info.BytesPerBlock;
end;

procedure LoadPixel(const Src; out Dst: TvgPixelData; const Info: TVkFormatPixelInfo);
begin
  if Info.IsCompressed then
    raise Exception.Create('Cannot LoadPixel: compressed formats are block-based.');
  Move(Src, Dst, Info.BytesPerPixel);
end;


class function TvgObjectIDAnalyzer.ExtractObjectID(  const Pixel: TvgPixelData;
                                                     const Info: TVkFormatPixelInfo): UInt64;
begin
  Result := 0;

  case Info.Kind of
    // 8-bit UINT formats (ID stored in R channel)
    pkR8_UINT:
      Result := Pixel.R8_UINT.R;

    pkR8G8_UINT:

      Result := Int64(Pixel.R8G8_UINT.G) shl 32 or Pixel.R8G8_UINT.R;

    pkR8G8B8_UINT:
      Result := Int64(Pixel.R8G8_UINT.G) shl 32 or Pixel.R8G8_UINT.R;

    pkR8G8B8A8_UINT:
      Result := Int64(Pixel.R8G8_UINT.G) shl 32 or Pixel.R8G8_UINT.R;

    // 16-bit UINT formats
    pkR16_UINT:
      Result := Pixel.R16_UINT;

    pkR16G16_UINT:
      Result := Int64(Pixel.R16G16_UINT.G) shl 32 or Pixel.R16G16_UINT.R;

    pkR16G16B16A16_UINT:
      Result := Int64(Pixel.R16G16_UINT.G) shl 32 or Pixel.R16G16_UINT.R;

  // 32-bit UINT formats (ideal for Object IDs)
    pkR32_UINT:
      Result := Pixel.R32_UINT;

    pkR32G32_UINT:
      Result := Int64(Pixel.R32G32_UINT.G) shl 32 or Pixel.R32G32_UINT.R;

    pkR32G32B32_UINT:
      Result := Int64(Pixel.R32G32_UINT.G) shl 32 or Pixel.R32G32_UINT.R;

    pkR32G32B32A32_UINT:
      Result := Int64(Pixel.R32G32_UINT.G) shl 32 or Pixel.R32G32_UINT.R;

    // Packed formats (if using packed Object IDs)
    pkA2R10G10B10_UINT:
      Result := Pixel.A2R10G10B10_UINT and $3FFFFFFF;  // Mask to get RGB bits

    pkA2B10G10R10_UINT:
      Result := Pixel.A2B10G10R10_UINT and $3FFFFFFF;

    // Default: try to read as UInt32
    else
      Move(Pixel.Raw[0], Result, Min(SizeOf(Result), Info.BytesPerPixel));
  end;
end;

// ============================================================================
// METHOD 1: Hash-based counting using TDictionary
// Best for: Most general cases, especially larger sample sizes
// Performance: O(n) time, O(k) space where k = unique IDs
// ============================================================================
class function TvgObjectIDAnalyzer.FindMostFrequentID_Hash(
    const PixelArray: TvgPixelDataArray;
    const PixelInfo: TVkFormatPixelInfo;
    SampleSize: Integer): TObjectIDResult;
var
  IDCounts: TDictionary<UInt32, Integer>;
  Row, Col: Integer;
  ObjectID: UInt64;
  MaxCount: Integer;
  CurrentCount: Integer;
begin
  // Initialize result
  FillChar(Result, SizeOf(Result), 0);
  Result.IsValid := False;

  if (SampleSize <= 0) or (Length(PixelArray) = 0) then
    Exit;

  IDCounts := TDictionary<UInt32, Integer>.Create;
  try
    MaxCount := 0;
    Result.MostFrequentID := 0;

    // Count occurrences of each ID
    for Row := 0 to SampleSize - 1 do
    begin
      for Col := 0 to SampleSize - 1 do
      begin
        ObjectID := ExtractObjectID(PixelArray[Col, Row], PixelInfo);

        // Increment count for this ID
        if IDCounts.TryGetValue(ObjectID, CurrentCount) then
          IDCounts[ObjectID] := CurrentCount + 1
        else
          IDCounts.Add(ObjectID, 1);

        // Check if this is the new maximum
        CurrentCount := IDCounts[ObjectID];
        if CurrentCount > MaxCount then
        begin
          MaxCount := CurrentCount;
          Result.MostFrequentID := ObjectID;
        end;

        Inc(Result.TotalPixels);
      end;
    end;

    Result.Frequency := MaxCount;
    Result.UniqueIDs := IDCounts.Count;
    Result.IsValid := True;

  finally
    IDCounts.Free;
  end;
end;

// ============================================================================
// METHOD 2: Array-based counting (pre-allocated)
// Best for: 3x3 or 5x5 samples where you expect few unique IDs
// Performance: O(n²) worst case, but very cache-friendly
// ============================================================================
class function TvgObjectIDAnalyzer.FindMostFrequentID_Array(
    const PixelArray: TvgPixelDataArray;
    const PixelInfo: TVkFormatPixelInfo;
    SampleSize: Integer): TObjectIDResult;
var
  MaxPossibleIDs: Integer;
  IDs: array of UInt64;
  Counts: array of Integer;
  UniqueCount: Integer;
  Row, Col, i: Integer;
  ObjectID: UInt64;
  Found: Boolean;
  MaxCount: Integer;
  MaxIndex: Integer;
begin
  // Initialize result
  FillChar(Result, SizeOf(Result), 0);
  Result.IsValid := False;

  if (SampleSize <= 0) or (Length(PixelArray) = 0) then
    Exit;

  // Pre-allocate arrays for worst case (all unique IDs)
  MaxPossibleIDs := SampleSize * SampleSize;
  SetLength(IDs, MaxPossibleIDs);
  SetLength(Counts, MaxPossibleIDs);
  UniqueCount := 0;

  // Count occurrences
  for Row := 0 to SampleSize - 1 do
  begin
    for Col := 0 to SampleSize - 1 do
    begin
      ObjectID := ExtractObjectID(PixelArray[Col, Row], PixelInfo);

      // Search for this ID in our array
      Found := False;
      for i := 0 to UniqueCount - 1 do
      begin
        if IDs[i] = ObjectID then
        begin
          Inc(Counts[i]);
          Found := True;
          Break;
        end;
      end;

      // New unique ID
      if not Found then
      begin
        IDs[UniqueCount] := ObjectID;
        Counts[UniqueCount] := 1;
        Inc(UniqueCount);
      end;

      Inc(Result.TotalPixels);
    end;
  end;

  // Find maximum count
  MaxCount := 0;
  MaxIndex := -1;
  for i := 0 to UniqueCount - 1 do
  begin
    if Counts[i] > MaxCount then
    begin
      MaxCount := Counts[i];
      MaxIndex := i;
    end;
  end;

  if MaxIndex >= 0 then
  begin
    Result.MostFrequentID := IDs[MaxIndex];
    Result.Frequency := MaxCount;
    Result.UniqueIDs := UniqueCount;
    Result.IsValid := True;
  end;
end;

// ============================================================================
// METHOD 3: Center-weighted frequency
// Best for: When center pixel should have more influence
// Gives extra weight to pixels closer to center
// ============================================================================
class function TvgObjectIDAnalyzer.FindMostFrequentID_Weighted(
    const PixelArray: TvgPixelDataArray;
    const PixelInfo: TVkFormatPixelInfo;
    SampleSize: Integer;
    CenterWeight: Integer = 3): TObjectIDResult;
var
  IDCounts: TDictionary<UInt32, Integer>;
  Row, Col: Integer;
  ObjectID: UInt64;
  MaxCount: Integer;
  CurrentCount: Integer;
  CenterX, CenterY: Integer;
  Distance: Integer;
  Weight: Integer;
begin
  // Initialize result
  FillChar(Result, SizeOf(Result), 0);
  Result.IsValid := False;

  if (SampleSize <= 0) or (Length(PixelArray) = 0) then
    Exit;

  IDCounts := TDictionary<UInt32, Integer>.Create;
  try
    MaxCount := 0;
    Result.MostFrequentID := 0;
    CenterX := SampleSize div 2;
    CenterY := SampleSize div 2;

    // Count occurrences with distance-based weighting
    for Row := 0 to SampleSize - 1 do
    begin
      for Col := 0 to SampleSize - 1 do
      begin
        ObjectID := ExtractObjectID(PixelArray[Col, Row], PixelInfo);

        // Calculate Manhattan distance from center
        Distance := Abs(Col - CenterX) + Abs(Row - CenterY);

        // Weight: center = CenterWeight, decreases with distance
        if Distance = 0 then
          Weight := CenterWeight
        else
          Weight := Max(1, CenterWeight - Distance);

        // Add weighted count
        if IDCounts.TryGetValue(ObjectID, CurrentCount) then
          IDCounts[ObjectID] := CurrentCount + Weight
        else
          IDCounts.Add(ObjectID, Weight);

        // Check if this is the new maximum
        CurrentCount := IDCounts[ObjectID];
        if CurrentCount > MaxCount then
        begin
          MaxCount := CurrentCount;
          Result.MostFrequentID := ObjectID;
        end;

        Inc(Result.TotalPixels);
      end;
    end;

    Result.Frequency := MaxCount;
    Result.UniqueIDs := IDCounts.Count;
    Result.IsValid := True;

  finally
    IDCounts.Free;
  end;
end;

// ============================================================================
// METHOD 4: Ignore background/null ID
// Best for: When you want to ignore empty space (ID 0 or $FFFFFFFF)
// ============================================================================
class function TvgObjectIDAnalyzer.FindMostFrequentID_NoBackground(
    const PixelArray: TvgPixelDataArray;
    const PixelInfo: TVkFormatPixelInfo;
    SampleSize: Integer;
    BackgroundID: UInt32 = 0): TObjectIDResult;
var
  IDCounts: TDictionary<UInt32, Integer>;
  Row, Col: Integer;
  ObjectID: UInt64;
  MaxCount: Integer;
  CurrentCount: Integer;
begin
  // Initialize result
  FillChar(Result, SizeOf(Result), 0);
  Result.IsValid := False;

  if (SampleSize <= 0) or (Length(PixelArray) = 0) then
    Exit;

  IDCounts := TDictionary<UInt32, Integer>.Create;
  try
    MaxCount := 0;
    Result.MostFrequentID := BackgroundID;  // Default to background if all are background

    // Count occurrences, skipping background ID
    for Row := 0 to SampleSize - 1 do
    begin
      for Col := 0 to SampleSize - 1 do
      begin
        ObjectID := ExtractObjectID(PixelArray[Col, Row], PixelInfo);

        Inc(Result.TotalPixels);

        // Skip background ID
        if ObjectID = BackgroundID then
          Continue;

        // Increment count for this ID
        if IDCounts.TryGetValue(ObjectID, CurrentCount) then
          IDCounts[ObjectID] := CurrentCount + 1
        else
          IDCounts.Add(ObjectID, 1);

        // Check if this is the new maximum
        CurrentCount := IDCounts[ObjectID];
        if CurrentCount > MaxCount then
        begin
          MaxCount := CurrentCount;
          Result.MostFrequentID := ObjectID;
        end;
      end;
    end;

    Result.Frequency := MaxCount;
    Result.UniqueIDs := IDCounts.Count;
    Result.IsValid := (MaxCount > 0);  // Valid only if we found non-background IDs

  finally
    IDCounts.Free;
  end;
end;

// ============================================================================
// Get all unique IDs with their frequencies (for analysis/debugging)
// ============================================================================
class function TvgObjectIDAnalyzer.GetIDFrequencies(
    const PixelArray: TvgPixelDataArray;
    const PixelInfo: TVkFormatPixelInfo;
    SampleSize: Integer): TArray<TObjectIDCount>;
var
  IDCounts: TDictionary<UInt32, Integer>;
  Row, Col: Integer;
  ObjectID: UInt64;
  CurrentCount: Integer;
  Pair: TPair<UInt32, Integer>;
  i: Integer;
begin
  SetLength(Result, 0);

  if (SampleSize <= 0) or (Length(PixelArray) = 0) then
    Exit;

  IDCounts := TDictionary<UInt32, Integer>.Create;
  try
    // Count occurrences
    for Row := 0 to SampleSize - 1 do
    begin
      for Col := 0 to SampleSize - 1 do
      begin
        ObjectID := ExtractObjectID(PixelArray[Col, Row], PixelInfo);

        if IDCounts.TryGetValue(ObjectID, CurrentCount) then
          IDCounts[ObjectID] := CurrentCount + 1
        else
          IDCounts.Add(ObjectID, 1);
      end;
    end;

    // Convert to array
    SetLength(Result, IDCounts.Count);
    i := 0;
    for Pair in IDCounts do
    begin
      Result[i].ObjectID := Pair.Key;
      Result[i].Count := Pair.Value;
      Inc(i);
    end;

    // Sort by count (descending)
    TArray.Sort<TObjectIDCount>(Result,
      TComparer<TObjectIDCount>.Construct(
        function(const Left, Right: TObjectIDCount): Integer
        begin
          Result := Right.Count - Left.Count;  // Descending order
        end
      )
    );

  finally
    IDCounts.Free;
  end;
end;

end.