 (*                                 vgVulkan                                  *
 ******************************************************************************
 *                        Version 2021-05-01-01-01-0000                       *
 ******************************************************************************
 *                                zlib license                                *
 *============================================================================*
 *                                                                            *
 * Copyright (C) 2021 Datavis (www.datavis.com.au) johnh@datavis.com.au       *
 *                                                                            *
 * This software is provided 'as-is', without any express or implied          *
 * warranty. In no event will the authors be held liable for any damages      *
 * arising from the use of this software.                                     *
 *                                                                            *
 * Permission is granted to anyone to use this software for any purpose,      *
 * including commercial applications, and to alter it and redistribute it     *
 * freely, subject to the following restrictions:                             *
 *                                                                            *
 * 1. The origin of this software must not be misrepresented; you must not    *
 *    claim that you wrote the original software. If you use this software    *
 *    in a product, an acknowledgement in the product documentation would be  *
 *    appreciated but is not required.                                        *
 * 2. Altered source versions must be plainly marked as such, and must not be *
 *    misrepresented as being the original software.                          *
 * 3. This notice may not be removed or altered from any source distribution. *
 *                                                                            *
 ******************************************************************************
 *                  General guidelines for code contributors                  *
 *============================================================================*
 *                                                                            *
 * 1. Make sure you are legally allowed to make a contribution under the zlib *
 *    license.                                                                *
 * 2. The zlib license header goes at the top of each source file, with       *
 *    appropriate copyright notice.                                           *
 * 3. This PasVulkan wrapper may be used only with the PasVulkan-own Vulkan   *
 *    Pascal header.                                                          *
 * 4. After a pull request, check the status of your pull request on          *
      http://github.com/BeRo1985/pasvulkan                                    *
 * 5. Write code which's compatible with Delphi >= 2009 and FreePascal >=     *
 *    3.1.1                                                                   *
 * 6. Don't use Delphi-only, FreePascal-only or Lazarus-only libraries/units, *
 *    but if needed, make it out-ifdef-able.                                  *
 * 7. No use of third-party libraries/units as possible, but if needed, make  *
 *    it out-ifdef-able.                                                      *
 * 8. Try to use const when possible.                                         *
 * 9. Make sure to comment out writeln, used while debugging.                 *
 * 10. Make sure the code compiles on 32-bit and 64-bit platforms (x86-32,    *
 *     x86-64, ARM, ARM64, etc.).                                             *
 * 11. Make sure the code runs on all platforms with Vulkan support           *
 *                                                                            *
 ******************************************************************************)

unit Vulkan_Components_Descriptors;

{$INCLUDE VulkanPackage.inc}

interface
Uses
  System.Classes,
  System.TypInfo,
  System.Rtti,               //MUST STAY HERE
  SysUtils,
  Vulkan,
  PasVulkan.Types,
  PasVulkan.Math,
  PasVulkan.Framework,
  Vulkan_Assert,
  Vulkan_Components,
  Vulkan_Components_Lookups,
  Vulkan_PixelInfo,
  Vulkan_Components_TextureInspector;

  {$A-}    //important

var

   LocationVKFormat : TvgFormat = R32G32B32_SFLOAT;//R64G64B64_SFLOAT;   send data as float

Type

  PvgScalarS = ^TvgScalarS;
  TvgScalarS = Single;

  PvgScalarD =^TvgScalarD;
  TvgScalarD = Double;

  TvgVector1I = packed record
    X : FixedUInt;    //always 32bit
  end;

  TvgVector2I = packed record
    X,Y : FixedUInt;    //always 32bit
  end;

  TvgVector3I = packed record
    X,Y,Z : FixedUInt;  //always 32bit
  end;

  TvgVector2S = packed record
      public
      X,Y : TvgScalarS;
      constructor Create(const aX,aY:TvgScalarS); Overload;
      constructor Create(const aVec:TpvVector2);  Overload;
  end;

  TvgVector3S = packed record
      public
      X,Y,Z : TvgScalarS;

      constructor Create(const aX,aY,aZ:TvgScalarS); Overload;
      constructor Create(const aVec:TpvVector3);     Overload;

  end;

  TvgVector4S = packed record
      public
      X,Y,Z, W : TvgScalarS;

      constructor Create(const aX,aY,aZ,aW:TvgScalarS); Overload;
      constructor Create(const aVec:TpvVector4);     Overload;

  end;
  TvgVector3D = packed record
      public
      X,Y,Z : TvgScalarD;

      constructor Create(const aX,aY,aZ:TvgScalarD); Overload;
      constructor Create(const aVec:TpvVector3); Overload;

  end;

  PvgMatrix4x4S = ^TvgMatrix4x4S;
  TvgMatrix4x4S = packed record
    case Integer of
    0: (RawComponents: array[0..3, 0..3] of TvgScalarS); // 4x4 array
    1: (Flat: array[0..15] of TvgScalarS);               // Flat array for Vulkan
    2: (M11, M12, M13, M14,
        M21, M22, M23, M24,
        M31, M32, M33, M34,
        M41, M42, M43, M44: TvgScalarS);

  end;

 TvgMatrix4x4SHelper = record helper for TvgMatrix4x4S
  public
   const Null    :TvgMatrix4x4S = (RawComponents:((0.0,0.0,0.0,0.0),(0.0,0.0,0.0,0.0),(0.0,0.0,0.0,0.0),(0.0,0.0,0.0,0.0)));
         Identity:TvgMatrix4x4S = (RawComponents:((1.0,0.0,0.0,0.0),(0.0,1.0,0.0,0.0),(0.0,0.0,1.0,0.0),(0.0,0.0,0.0,1.0)));
 end;

  PvgMatrix4x4D = ^TvgMatrix4x4D;
  TvgMatrix4x4D = packed record

    constructor Create(const aMat : TpvMatrix4x4);

    case Integer of
    0: (RawComponents: array[0..3, 0..3] of TvgScalarD); // 4x4 array
    1: (Flat: array[0..15] of TvgScalarD);               // Flat array for Vulkan
    2: (M11, M12, M13, M14,
        M21, M22, M23, M24,
        M31, M32, M33, M34,
        M41, M42, M43, M44: TvgScalarD);

  end;

 TvgMatrix4x4DHelper = record helper for TvgMatrix4x4D
  public
   const Null    :TvgMatrix4x4D = (RawComponents:((0.0,0.0,0.0,0.0),(0.0,0.0,0.0,0.0),(0.0,0.0,0.0,0.0),(0.0,0.0,0.0,0.0)));
         Identity:TvgMatrix4x4D = (RawComponents:((1.0,0.0,0.0,0.0),(0.0,1.0,0.0,0.0),(0.0,0.0,1.0,0.0),(0.0,0.0,0.0,1.0)));
 end;

  TvgGenericDataArray<T>  = record
  private
    FItems            : array of T;

    function GetCount: Integer;
    function GetItem(Index: Integer): T;
    procedure SetItem(Index: Integer; const Value: T);

  public
    procedure Add(const Item: T);
    procedure Clear;
    Procedure SetItemCapacity(aCapacity:Integer);

 // New methods for Vulkan API
    function GetDataPointer: Pointer;
    function GetDataSize: Integer;
    function GetDataStride : Integer;
    Function GetDataPointerForIndex(aItemIndex:Integer): Pointer;

    property ItemCount: Integer read GetCount;
    property Items[Index: Integer]: T read GetItem write SetItem; default;
 //   property ItemIndex: TvkUint32 read fCurrentItemIndex write fCurrentItemIndex ;

  end;

  TvgPushConstant_Data<T> = Class(TvgPushConstant)
  private
    function GetItem(Index: Integer): T;
    procedure SetItem(Index: Integer; const Value: T);
  Protected

    fDataArray    : Array of TvgGenericDataArray<T>;  //frame data

    Function SetDisabled :Boolean; Override;
    Function SetEnabled  :Boolean; Override;

    procedure SetFrameCount(const Value: TvkUint32);  Override;
  Public
    Class Function GetPropertyName : String; Override;

    Constructor Create(AOwner: TComponent);  Override;
    Destructor Destroy; Override;
    Procedure Assign(Source: TPersistent); override;

    function GetDataStride: TVkUInt32;                      Override; //size of record
    function GetDataPointer: Pointer; Override;


    property Items[Index: Integer]  : T read GetItem  write SetItem; default;
  End;


 //Descriptors
{*********************  UBO  *********************************}

  TvgDescriptor_PerFrame_UniformBuffer<T> = Class(TvgDescriptorPerFrameData)

  Protected

    fVulkanBuffer        : TpvVulkanBuffer;         //one per index Desriptor
    fData                : TvgGenericDataArray<T>; //One per frame of Descriptor Data with Data Items

    Procedure SetDisabled ; Override;
    Procedure SetEnabled  ; Override;
    function HasPayload: Boolean; override;

    function GetWriteDescriptorPayload( out aBufInfo   : TVkDescriptorBufferInfo;
                                        out aImgInfo   : TVkDescriptorImageInfo  ): Boolean; Override;

  Public

    Constructor Create;

    Procedure UpLoadDescriptorData (aFrameIndex:TvkUint32;
                                    aGraphicPool:TvgCommandBufferPool;
                                    aTransferPool:TvgCommandBufferPool);   Override;
     procedure ClearDataOnGPU(aIndex:Integer; aTransferPool: TvgCommandBufferPool; aCommandBuffer: TvgCommandBuffer = nil); Override;


    Property Data : TvgGenericDataArray<T> Read fData;
  End;

  TvgDescriptor_Data_UniformBuffer<T>  = Class(TvgDescriptorData)
  private
    function GetUBOFrame(Index: Integer): TvgDescriptor_PerFrame_UniformBuffer<T>;

  Protected

    Procedure SetDisabled; override;
    Procedure SetEnabled; override;

    Procedure SetFrameCount(aCount:Integer);

    Function GetOrAddFrameDataObject(aFrameIndex:Integer) : TvgDescriptorPerFrameData; Override;  //descendant builds correct frameData type
    function GetGLSLBaseTypeName: String; override;


  Public
    constructor Create;

    Property UBOFrameData[Index :Integer]:TvgDescriptor_PerFrame_UniformBuffer<T>  read GetUBOFrame;
  End;

  TvgDescriptorArray_UniformBuffer<T> = class(TvgDescriptorArray)
  private
    function GetDescriptor_Data_UBO(Index: Integer): TvgDescriptor_Data_UniformBuffer<T>;

  Protected

    function GetGLSLDeclarationBody: String; Override;
    function GetGLSLLayoutQualifier: String; Override;

  Public
    constructor Create(AOwner: TComponent); override;

    Function AddUniformBuffer( aDescriptorData: TvgDescriptor_Data_UniformBuffer<T>):Integer;
    Function RemoveUBO(aDD_UBO : TvgDescriptor_Data_UniformBuffer<T>):Boolean;
    function GetGLSLValueExpression(const aArrayIndexExpr : String = '';  aIndexExpr: String = ''): String; Override;

    Property UBODescriptor[Index:Integer] : TvgDescriptor_Data_UniformBuffer<T>  Read GetDescriptor_Data_UBO  ;

  end;


{*********************  TEXTURE *********************************}

{Texture Stuff}

  TvgTextureSource = record
      FileName : string;
      Stream   : TMemoryStream;
      DataSize : Int64;
      DataOK   : Boolean;
      Info     : TTextureInfo;
  end;

  TvgDescriptor_PerFrame_Texture = Class(TvgDescriptorPerFrameData)
  private

  Protected
   //vulkan data
   // holds data for transfer
     fVulkanTexture   : TpvVulkanTexture;

     fTextureSource   : TvgTextureSource;

    Procedure SetDisabled ;  Override;
    Procedure SetEnabled ;   Override;
    function HasPayload: Boolean; override;
    function IsWriteReady: Boolean; override;
    procedure InvalidateForUpload; override;

    function GetWriteDescriptorPayload( out aBufInfo   : TVkDescriptorBufferInfo;
                                        out aImgInfo   : TVkDescriptorImageInfo  ): Boolean; Override;


  Public
  // Class Function GetPropertyName : String; Override;

    Constructor Create;
    Destructor Destroy; Override;

    Procedure UpLoadDescriptorData(aFrameIndex:TvkUint32;
                                   aGraphicPool:TvgCommandBufferPool;
                                   aTransferPool:TvgCommandBufferPool);  Override;

     procedure ClearDataOnGPU(aIndex:Integer;aTransferPool: TvgCommandBufferPool; aCommandBuffer: TvgCommandBuffer = nil); Override;



    Function LoadTexture(aFileName:String;    Var aGLSLIndex:TvkUint32):Boolean;   Overload;
    Function LoadTexture(aFileStream:TStream; Var aGLSLIndex:TvkUint32):Boolean;   Overload; //owns the FileStream

    Function HasTextureSource : Boolean;   //texture data has been loaded into this frame object

  End;

  TvgDescriptor_Data_Texture  = Class(TvgDescriptorData)
    private
      function GetBorderColor: TvgBorderColor;
      function GetWrapModeU: TpvVulkanTextureWrapMode;
      function GetWrapModeV: TpvVulkanTextureWrapMode;
      function GetWrapModeW: TpvVulkanTextureWrapMode;
      procedure SetBorderColor(const Value: TvgBorderColor);
      procedure SetWrapModeU(const Value: TpvVulkanTextureWrapMode);
      procedure SetWrapModeV(const Value: TpvVulkanTextureWrapMode);
      procedure SetWrapModeW(const Value: TpvVulkanTextureWrapMode);
    function GetTextureFrame(Index: Integer): TvgDescriptor_PerFrame_Texture;


    Protected
     fSampler         : TvgSampler;  //used as a common sampler for all indexed descriptors

     fWrapModeU       : TpvVulkanTextureWrapMode;
     fWrapModeV       : TpvVulkanTextureWrapMode;
     fWrapModeW       : TpvVulkanTextureWrapMode;
     fBorderColor     : TVkBorderColor;

    Procedure SetDisabled ;  Override;
    Procedure SetEnabled ;   Override;

    function GetOrAddFrameDataObject(aFrameIndex: Integer): TvgDescriptorPerFrameData; override;

    function GetGLSLBaseTypeName: String; override;
    Procedure SetFrameCount(aCount:Integer);

    // If only ONE frame object actually holds texture data, release the empty
    // ones and flag this data as shared so every frame resolves to it.
    Procedure CollapseToSharedTexture;

    Public

    Constructor Create;
    Destructor Destroy; Override;

    Function LoadSharedTexture(aFileName:String):Boolean;  //ONE texture used by every frame

    Property Sampler     : TvgSampler Read fSampler;

    Property BorderColor : TvgBorderColor Read  GetBorderColor  Write SetBorderColor  ;
    Property WrapModeU   : TpvVulkanTextureWrapMode Read  GetWrapModeU  Write SetWrapModeU  ;
    Property WrapModeV   : TpvVulkanTextureWrapMode Read  GetWrapModeV  Write SetWrapModeV  ;
    Property WrapModeW   : TpvVulkanTextureWrapMode Read  GetWrapModeW  Write SetWrapModeW  ;

    Property TextureFrame[Index:Integer]:  TvgDescriptor_PerFrame_Texture read GetTextureFrame;

  End;

  TvgDescriptorArray_Texture = class(TvgDescriptorArray)
  private
    function GetDescriptor_Data_Texture( Index: Integer): TvgDescriptor_Data_Texture;

  protected
    function GetGLSLDeclarationBody: String; Override;


  Public
    class function GetPropertyName: String; override;

    constructor Create(AOwner: TComponent); override;

    Function AddTexture(aTextureName, aFileName:String ) : Integer;
    Function AddSharedTexture(aTextureName, aFileName: String): Integer;
    Function RemoveTexture(aDataTexture : TvgDescriptor_Data_Texture):Boolean;


    Property TextureData[Index:Integer] : TvgDescriptor_Data_Texture  Read GetDescriptor_Data_Texture ;

  end;


TvgElementSamplingDimension = (esdLinear1D, esdGrid2D);
//============================================================
  // TvgElementSampler
  // Analogous to TvgPixelSampler but for linear GPU storage buffer data.
  // Performs CPU-side readback of a contiguous window of elements
  // centred on a caller-supplied index, using a host-visible staging
  // buffer and a dedicated transfer command buffer.
  //============================================================
  TvgElementSampler = class(TvgBaseObject)
  private

    procedure SetSampleRadius(const Value : TvgPixelSampleRadius);
    function  GetSampleSize : Integer;
    procedure SetSamplingDimension(const Value : TvgElementSamplingDimension);
    procedure SetStrideWidth(const Value : TvkUint32);

    function GetSourceBuffer(Index: Integer): TpvVulkanBuffer;
    procedure SetCurrentFrame(const Value: TvkUint32);
    procedure SetFrameCount(const Value: TvkUint32);
    procedure SetSourceBuffer(Index: Integer; const Value: TpvVulkanBuffer);

    function  GetStagingElementCount : Integer;

  protected
    fFrameCount,
    fCurrentFrame    : TvkUint32;
    fSourceBuffer    : Array of TpvVulkanBuffer;   // Device-local source (NOT owned) one per frame
    fDevice          : TvgLogicalDevice;  // NOT owned

    fElementStride   : TvkUint32;         // Bytes per element
    fElementCount    : TvkUint32;         // Total elements in source buffer

    fSampleRadius    : TvgPixelSampleRadius;
    fSampleSize      : Integer;   // Number of elements captured (1, 3, 5, 7 or 9)
    fSamplingDimension : TvgElementSamplingDimension;
    fStrideWidth        : TvkUint32;

    fLastSampleX, fLastSampleY : Integer;

    fSampledData     : TBytes;            // Raw bytes of most-recently sampled window
    fLastSampleIndex : Integer;           // Centre index of last sample

    fStagingBuffer   : TpvVulkanBuffer;
    fCommandPool     : TvgCommandBufferPool;
    fCommandBuffer   : TvgCommandBuffer;

    Procedure SetDisabled; Override;
    Procedure SetEnabled;  Override;

    procedure CreateStagingBuffer;

    procedure CopyElementsToStaging(CentreIndex : Integer);
    procedure CopyElementsToStaging2D(CentreX, CentreY : Integer);

    function  ReadElementsFromStaging : Boolean;

  public
    constructor Create;
    destructor  Destroy; override;

    // Sample SampleSize elements centred on CentreIndex from the GPU buffer
    function SampleElement(CentreIndex : Integer) : Boolean;
    function SampleElementXY(CentreX, CentreY : Integer) : Boolean;

    // Return a pointer to a relative element within the last sampled window.
    // RelativeOffset 0 = centre element; -1 = one before centre, etc.
    function GetElementBytes(RelativeOffset : Integer;
                             out Data       : Pointer;
                             out ByteCount  : TvkUint32) : Boolean;
    function GetElementBytesXY(RelativeX, RelativeY : Integer;
                               out Data: Pointer;
                               out ByteCount: TvkUint32) : Boolean;

    Property SourceBuffer[Index:Integer]    : TpvVulkanBuffer    read GetSourceBuffer    write SetSourceBuffer;
    Property Device          : TvgLogicalDevice   read fDevice          write fDevice;
    Property FrameCount      : TvkUint32          Read fFrameCount write SetFrameCount;
    Property CurrentFrame      : TvkUint32        Read fCurrentFrame write SetCurrentFrame;
    Property ElementStride   : TvkUint32          read fElementStride   write fElementStride;
    Property ElementCount    : TvkUint32          read fElementCount    write fElementCount;
    Property SampledData     : TBytes             read fSampledData;
    Property LastSampleIndex : Integer            read fLastSampleIndex;
    Property SampleRadius    : TvgPixelSampleRadius read fSampleRadius  write SetSampleRadius;
    Property SampleSize      : Integer            read GetSampleSize;

    Property SamplingDimension : TvgElementSamplingDimension read fSamplingDimension write SetSamplingDimension;
    Property StrideWidth        : TvkUint32                   read fStrideWidth       write SetStrideWidth;
    Property LastSampleX        : Integer                     read fLastSampleX;
    Property LastSampleY        : Integer                     read fLastSampleY;

  end;


{*********************  STORAGE BUFFER  *********************************}

  //============================================================
  // TvgDescriptor_StorageBuffer
  //
  // A Vulkan Storage Buffer descriptor (VK_DESCRIPTOR_TYPE_STORAGE_BUFFER)
  // with optional CPU-side element readback, mirroring the pixel-sampling
  // pattern of TvgDescriptor_StorageImage.
  //
  // Analogue map:
  //   fElementSamplingON  ↔  fPixelSamplingON
  //   fSampleRadius       ↔  fPixelSampleRadius
  //   fElementSampler[]   ↔  TvgResourceImageBuffer[].fPixelSampler
  //   GetElementData()    ↔  GetPixelData()
  //
  // Concrete data is supplied by subclasses (see TvgDescriptor_SB_Data<T>).
  //============================================================

  TvgDescriptor_PerFrame_StorageBuffer<T> = Class(TvgDescriptorPerFrameData)

  protected
    // device-local Vulkan buffers (owned)
    fVulkanBuffer  : TpvVulkanBuffer ;
    fData          : TvgGenericDataArray<T>; //One per frame of Descriptor Data with Data Items


    Procedure SetDisabled ; Override;
    Procedure SetEnabled ; Override;
    function HasPayload: Boolean; override;

    function GetWriteDescriptorPayload( out aBufInfo   : TVkDescriptorBufferInfo;
                                        out aImgInfo   : TVkDescriptorImageInfo  ): Boolean; Override;


  public

    Procedure UpLoadDescriptorData(aFrameIndex        : TvkUint32;
                                    aGraphicPool  : TvgCommandBufferPool;
                                    aTransferPool : TvgCommandBufferPool); Override;

    procedure ClearDataOnGPU(aIndex:Integer; aTransferPool: TvgCommandBufferPool; aCommandBuffer: TvgCommandBuffer = nil); Override;


    Property Data : TvgGenericDataArray<T> Read fData;

  End;

  TvgDescriptor_Data_StorageBuffer<T>   = Class(TvgDescriptorData)
  private
    function GetStorageBufferFrame(Index: Integer): TvgDescriptor_PerFrame_StorageBuffer<T>;
    procedure SetStrideWidth(const Value: TvkUint32);
    procedure SetSamplingDimension(const Value: TvgElementSamplingDimension);
    procedure SetElementCount(const Value: TvkUint32);
    procedure SetElementSamplingON(const Value: Boolean);
    procedure SetWindowSync(const Value: Boolean);

  Protected

    fElementCount        : TvkUint32;    //count of data elements or size of
    fElementSub          : TvkUint32;    //Use for including Data Width eg Width and height
    fElementCountChanged : Boolean;
    fWindowSync          : Boolean;

    fElementSamplingON : Boolean;
    fElementSampler    : TvgElementSampler;
    fSampleRadius      : TvgPixelSampleRadius;
    fSamplingDimension : TvgElementSamplingDimension;

    Procedure SetDisabled; override;
    Procedure SetEnabled; override;

    Procedure SetFrameCount(aCount:Integer);

    Procedure RefreshSamplerSourceBuffers;

    Function GetOrAddFrameDataObject(aFrameIndex:Integer) : TvgDescriptorPerFrameData; Override;  //descendant builds correct frameData type

    function GetGLSLBaseTypeName: String; override;

    Procedure VaildateWindowSize;

  Public
    constructor Create;
    destructor Destroy; override;

    // Trigger a GPU→CPU readback of elements around ElementIndex for frame aFrameIndex.
    // On return Data points into the sampler's internal staging buffer for the
    // centre element; DataSize is ElementStride bytes.
    // Returns False when sampling is disabled, inactive, or out of range.

    Function GetElementData(aFrameIndex  : TvkUint32; ElementIndex : Integer; out Data : Pointer; out DataSize : TvkUint32) : Boolean;
  // Convenience 2D readback for this descriptor's current frame data
    Function GetElementData2D(aFrameIndex:TvkUint32; X, Y:Integer; out Data:Pointer; out DataSize:TvkUint32): Boolean;

    Property ElementCount      : TvkUint32 read fElementCount write SetElementCount;
    Property StrideWidth       : TvkUint32                  read fElementSub        write SetStrideWidth;
    Property SamplingDimension : TvgElementSamplingDimension read fSamplingDimension write SetSamplingDimension;
    Property SamplingON        : Boolean read fElementSamplingON write SetElementSamplingON;
    Property WindowSync        : Boolean read fWindowSync write SetWindowSync;

    Property StorageBufferFrameData[Index :Integer]:TvgDescriptor_PerFrame_StorageBuffer<T>  read GetStorageBufferFrame;

  End;

  TvgDescriptorArray_StorageBuffer<T> = class(TvgDescriptorArray)
  private
    function GetDescriptor_Data_StorageBuffer(Index: Integer): TvgDescriptor_Data_StorageBuffer<T>;

  Protected

    function GetGLSLDeclarationBody: String; Override;
    function GetGLSLLayoutQualifier: String; Override;

  Public
    constructor Create(AOwner: TComponent); override;

    Function AddStorageBuffer( aData_SB: TvgDescriptor_Data_StorageBuffer<T>):Integer;
    Function RemoveStorageBuffer(aData_SB : TvgDescriptor_Data_StorageBuffer<T>):Boolean;

    function GetGLSLValueExpression(const aArrayIndexExpr : String = '';  aIndexExpr: String = ''): String; Override;

    Property SB_Descriptor[Index:Integer] : TvgDescriptor_Data_StorageBuffer<T>  Read GetDescriptor_Data_StorageBuffer  ;


  end;


{*********************  STORAGE IMAGE  *********************************}

  TvgDescriptor_PerFrame_StorageImage = Class(TvgDescriptorPerFrameData)

  protected
      fStorageImageBuffer   : TvgResourceImageBuffer;
      fImageLayoutSet       : Boolean ;


    Procedure SetDisabled ; Override;
    Procedure SetEnabled  ; Override;
    function HasPayload: Boolean; override;

    function GetWriteDescriptorPayload( out aBufInfo   : TVkDescriptorBufferInfo;
                                        out aImgInfo   : TVkDescriptorImageInfo  ): Boolean; Override;


  Public

    Constructor Create;
    Destructor Destroy; Override;

  //  Procedure ClearDescriptor(aCommandBuffer:TvgCommandBuffer) ;  //Clear the value in Vulkan


    Procedure UpLoadDescriptorData (aFrameIndex:TvkUint32;
                                    aGraphicPool:TvgCommandBufferPool;
                                    aTransferPool:TvgCommandBufferPool);   Override;
     procedure ClearDataOnGPU(aIndex:Integer;aTransferPool: TvgCommandBufferPool; aCommandBuffer: TvgCommandBuffer = nil); Override;


  End;

  TvgDescriptor_Data_StorageImage  = Class(TvgDescriptorData)
  private
    function GetPixelSampler(FrameIndex: Integer): TvgPixelSampler;
    procedure SetfPixelSamplingON(const Value: Boolean);
    procedure SetImageHeight(const Value: TvkUint32);
    procedure SetImageWidth(const Value: TvkUint32);
    procedure SetPixelSampleRadius(const Value: TvgPixelSampleRadius);
    procedure SetWindowSync(const Value: Boolean);

  Protected
    fImageWidth,
    fImageHeight          : TvkUint32;
    fWindowSync           : Boolean;  //size to match render swapchain size

    fPixelSamplingON      : Boolean;
    fPixelSampleRadius    : TvgPixelSampleRadius;

    fSubRange       : TVkImageSubresourceRange;
    fInitialBarrier : TVkImageMemoryBarrier;
    fPreBarrier     : TVkImageMemoryBarrier;
    fPostBarrier    : TVkImageMemoryBarrier;
    fClearCol       : TVkClearColorValue;

    Procedure SetDisabled; override;
    Procedure SetEnabled; override;

    Function GetOrAddFrameDataObject(aFrameIndex:Integer) : TvgDescriptorPerFrameData; Override;  //descendant builds correct frameData type
    function GetGLSLBaseTypeName: String; override;

    Procedure VaildateWindowSize;

  Public
    constructor Create;
    destructor Destroy; override;

    procedure SetClearColor(R, G, B : Single; A:Single=1);
    Function GetPixelData(aFrameIndex: TvkUint32;  Shift: TShiftState; X, Y: Integer; out Data : TvgPixelData):Boolean;


    Property PixelSample : Boolean read fPixelSamplingON write SetfPixelSamplingON;
    Property PixRadius   : TvgPixelSampleRadius  Read fPixelSampleRadius write SetPixelSampleRadius ;

    Property PixelSampler[FrameIndex:Integer] : TvgPixelSampler Read GetPixelSampler;

    Property ImageWidth  : TvkUint32 Read fImageWidth Write SetImageWidth;
    Property ImageHeight : TvkUint32 Read fImageHeight Write SetImageHeight;

    Property WindowSync : Boolean read fWindowSync write SetWindowSync;

  End;


  TvgDescriptorArray_StorageImage = class(TvgDescriptorArray)
  private
    function GetDescriptorDataStorageImage(Index: Integer): TvgDescriptor_Data_StorageImage;
    function GetImageFormat: TvgFormat;
    procedure SetImageFormat(const Value: TvgFormat);

  protected

    function GetGLSLDeclarationBody: String; override;
    function GetGLSLLayoutQualifier: String; override;

  public
    class function GetPropertyName: String; override;
    constructor Create(AOwner: TComponent); override;
  //  procedure ClearDescriptor(aCommandBuffer: TvgCommandBuffer); override;

    function AddStorageImage(aStorageImageData: TvgDescriptor_Data_StorageImage): Integer;
    function RemoveStorageImage(aStorageImageData: TvgDescriptor_Data_StorageImage): Boolean;

    property StorageImageData[Index: Integer]: TvgDescriptor_Data_StorageImage read GetDescriptorDataStorageImage;

  published
    property ImageFormat: TvgFormat read GetImageFormat write SetImageFormat;
  end;


 //4x4 Matrix as resource UBO data  DOUBLE Precision Check

  TvgDescriptorArray_UBO_4x4MatrixD = class(TvgDescriptorArray_UniformBuffer<TvgMatrix4x4D> )
  private
    function GetMatrix( aDescriptorIndex, aFrameIndex:TvkUint32; aDataIndex:TvkUint32=0): TvgMatrix4x4D;
    procedure SetMatrix(aDescriptorIndex, aFrameIndex:TvkUint32; aDataIndex:TvkUint32;const Value: TvgMatrix4x4D);

  Public
    Class Function GetPropertyName : String; override;

    Function AddMatrix : Integer;   //returns the DescriptorIndex

    Property Matrix[aDescriptorIndex, aFrameIndex, aDataIndex:TvkUint32]: TvgMatrix4x4D read GetMatrix write SetMatrix;

  end;

  TvgDescriptorData_SB_2UI = Class(TvgDescriptor_Data_StorageBuffer<TvgVector2I>)

  End;


  TvgDescriptorArray_SB_2UI = Class(TvgDescriptorArray_StorageBuffer<TvgVector2I>)
  Public
    Class Function GetPropertyName : String; override;

    Function AddBuffer: TvgDescriptorData_SB_2UI;   //returns the DescriptorIndex

 //   Property Buffer[aDescriptorIndex, aFrameIndex :TvkUint32]: TvgVector2I read GetBuffer write SetBuffer;

//    Constructor Create;
//    Procedure Assign(Source: TPersistent) ;  Override;
  End;




  //2x Unsigned Integer Push Constant (e.g. object/instance IDs, per-draw indices, etc.)
  //Shader-stage visibility is inherited from TvgPushConstant.ShaderFlags -
  //set that (design-time in the Object Inspector, or in code) to target
  //the Vertex Shader, Fragment Shader, or both.

  TvgPushConstant_2UI = Class(TvgPushConstant_Data<TvgVector2I>)
  Private
    Function  GetValue : TvgVector2I;
    Procedure SetValue(const Value : TvgVector2I);

  Protected


  Public
    Class Function GetPropertyName : String; Override;

    Constructor Create(AOwner: TComponent);  Override;

    function GetGLSLDeclaration(const aBlockName: String): String; Override;

    Procedure SetValues(const aX, aY : Cardinal);  //convenience helper - sets both components in one call

    Procedure SetupData(FrameIndex:TvkUint32;Linker:TvgLinker);Override;

    Property Value : TvgVector2I read GetValue write SetValue;  //the single struct pushed to the shader
  End;


function GetGLSLTypeNameForPascalType(const aTypeName: String): String;  //must be global

implementation


function GetGLSLTypeNameForPascalType(const aTypeName: String): String;
begin
  // Maps the record types declared in this unit (and common scalars) to
  // their GLSL equivalent. Anything not listed falls back to the raw
  // Pascal type name - if that's wrong for a custom T, override
  // GetGLSLBaseTypeName in a leaf class instead (see
  // TvgDescriptor_Data_UBO_4x4MatrixD for the pattern).
  if      aTypeName = 'TvgMatrix4x4D' then Result := 'dmat4'
  else if aTypeName = 'TvgMatrix4x4S' then Result := 'mat4'
  else if aTypeName = 'TvgVector2S'   then Result := 'vec2'
  else if aTypeName = 'TvgVector3S'   then Result := 'vec3'
  else if aTypeName = 'TvgVector4S'   then Result := 'vec4'
  else if aTypeName = 'TvgVector3D'   then Result := 'dvec3'
  else if aTypeName = 'TvgVector1I'   then Result := 'uint'
  else if aTypeName = 'TvgVector2I'   then Result := 'uvec2'
  else if aTypeName = 'TvgVector3I'   then Result := 'uvec3'
  else if aTypeName = 'Single'        then Result := 'float'
  else if aTypeName = 'Double'        then Result := 'double'
  else if aTypeName = 'Integer'       then Result := 'int'
  else if aTypeName = 'Cardinal'      then Result := 'uint'
  else Result := aTypeName;
end;

//Pipeline cache management

procedure SavePipelineCacheDataToFile(Device: TVkDevice; PipelineCache: TVkPipelineCache; const FileName: string);
var
  DataSize: TvkUint32;
  Data: Pointer;
  FS: TFileStream;
begin
  // Query the size of the cache data
  vkGetPipelineCacheData(Device, PipelineCache, @DataSize, nil);
  if DataSize = 0 then Exit;

  // Allocate memory for the cache data
  GetMem(Data, DataSize);
  try
    // Retrieve the cache data
    if vkGetPipelineCacheData(Device, PipelineCache, @DataSize, Data) = VK_SUCCESS then
    begin
      FS := TFileStream.Create(FileName, fmCreate);
      try
        FS.WriteBuffer(Data^, DataSize);
      finally
        FS.Free;
      end;
    end;
  finally
    FreeMem(Data);
  end;
end;

function LoadPipelineCacheDataFromFile(const FileName: string; out Data: Pointer; out DataSize: TvkUint32): Boolean;
var
  FS: TFileStream;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    DataSize := FS.Size;
    if DataSize = 0 then Exit;
    GetMem(Data, DataSize);
    FS.ReadBuffer(Data^, DataSize);
    Result := True;
  finally
    FS.Free;
  end;
end;

function CreatePipelineCacheWithData(Device: TVkDevice; const FileName: string): TVkPipelineCache;
var
  CacheData: Pointer;
  CacheDataSize: TvkUint32;
  PipelineCacheInfo: TVkPipelineCacheCreateInfo;
  PipelineCache: TVkPipelineCache;
begin
  FillChar(PipelineCacheInfo, SizeOf(PipelineCacheInfo), 0);
  PipelineCacheInfo.sType := VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO;
  if LoadPipelineCacheDataFromFile(FileName, CacheData, CacheDataSize) then
  begin
    PipelineCacheInfo.initialDataSize := CacheDataSize;
    PipelineCacheInfo.pInitialData := CacheData;
  end
  else
  begin
    PipelineCacheInfo.initialDataSize := 0;
    PipelineCacheInfo.pInitialData := nil;
  end;

  if vkCreatePipelineCache(Device, @PipelineCacheInfo, nil, @PipelineCache) <> VK_SUCCESS then
    raise Exception.Create('Failed to create pipeline cache');

  if PipelineCacheInfo.pInitialData <> nil then
    FreeMem(CacheData);

  Result := PipelineCache;
end;


{ TvgVector2 }
constructor TvgVector2S.Create(const aX, aY: TvgScalarS);
begin
  X:=aX;
  Y:=aY;
end;

constructor TvgVector2S.Create(const aVec: TpvVector2);
begin
  X:=aVec.x;
  Y:=aVec.y;
end;

{ TvgVector3S }

constructor TvgVector3S.Create(const aX, aY, aZ: TvgScalarS);
begin
  X:=aX;
  Y:=aY;
  Z:=aZ;
end;

constructor TvgVector3S.Create(const aVec: TpvVector3);
begin
  X:=aVec.x;
  Y:=aVec.y;
  Z:=aVec.z;
end;

{ TvgVector3D }

constructor TvgVector3D.Create(const aVec: TpvVector3);
begin
  X:=aVec.X;
  Y:=aVec.Y;
  Z:=aVec.Z;
end;

constructor TvgVector3D.Create(const aX, aY, aZ: TvgScalarD);
begin
  X:=aX;
  Y:=aY;
  Z:=aZ;
end;

constructor TvgMatrix4x4D.Create(const aMat : TpvMatrix4x4);
Begin
   RawComponents[0,0]:=aMat.RawComponents[0,0];
   RawComponents[0,1]:=aMat.RawComponents[0,1];
   RawComponents[0,2]:=aMat.RawComponents[0,2];
   RawComponents[0,3]:=aMat.RawComponents[0,3];
   RawComponents[1,0]:=aMat.RawComponents[1,0];
   RawComponents[1,1]:=aMat.RawComponents[1,1];
   RawComponents[1,2]:=aMat.RawComponents[1,2];
   RawComponents[1,3]:=aMat.RawComponents[1,3];
   RawComponents[2,0]:=aMat.RawComponents[2,0];
   RawComponents[2,1]:=aMat.RawComponents[2,1];
   RawComponents[2,2]:=aMat.RawComponents[2,2];
   RawComponents[2,3]:=aMat.RawComponents[2,3];
   RawComponents[3,0]:=aMat.RawComponents[3,0];
   RawComponents[3,1]:=aMat.RawComponents[3,1];
   RawComponents[3,2]:=aMat.RawComponents[3,2];
   RawComponents[3,3]:=aMat.RawComponents[3,3];
End;

{ TvgGenericArray  }

procedure TvgGenericDataArray<T>.Add(const Item: T);
begin
  SetLength(FItems, Length(FItems) + 1);
  FItems[High(FItems)] := Item;
//  fCurrentItemIndex:=High(FItems);
end;

procedure TvgGenericDataArray<T>.Clear;
begin
  If (Length(FItems)=0) then exit;
  SetLength(FItems, 0);
end;

function TvgGenericDataArray<T>.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function TvgGenericDataArray<T>.GetItem(Index: Integer): T;
begin
  if (Index < 0) or (Index >= Length(FItems)) then
    raise EArgumentOutOfRangeException.Create('Index out of range');
  Result := FItems[Index];
end;

procedure TvgGenericDataArray<T>.SetItemCapacity(aCapacity: Integer);
begin
  if aCapacity=Length(FItems) then exit;
  SetLength(FItems, aCapacity);
end;

procedure TvgGenericDataArray<T>.SetItem(Index: Integer; const Value: T);
begin
  if (Index < 0) or (Index >= Length(FItems)) then
    raise EArgumentOutOfRangeException.Create('Index out of range');
  FItems[Index] := Value;
end;

function TvgGenericDataArray<T>.GetDataPointer: Pointer;
begin
  if Length(FItems) = 0 then
    Result := nil
  else
    Result := @FItems[0];
end;

function TvgGenericDataArray<T>.GetDataPointerForIndex(aItemIndex:Integer): Pointer;
begin
  if (Itemcount=0) or (aItemIndex<0)  or (aItemIndex>= ItemCount)then
     Result := Nil
  else
     Result := @FItems[aItemIndex] ;
end;

function TvgGenericDataArray<T>.GetDataSize: Integer;
begin
  Result := Length(FItems) * SizeOf(T);
end;


function TvgGenericDataArray<T>.GetDataStride: Integer;
begin
   Result :=  SizeOf(T);
end;


procedure TvgDescriptor_PerFrame_UniformBuffer<T>.ClearDataOnGPU(aIndex:Integer; aTransferPool: TvgCommandBufferPool; aCommandBuffer: TvgCommandBuffer = nil);
begin


end;

{TvgDescriptor_FrameData_UBO<T>}

constructor TvgDescriptor_PerFrame_UniformBuffer<T>.Create;
begin
  inherited;

  fUploadNeeded:=True;
end;

function TvgDescriptor_PerFrame_UniformBuffer<T>.HasPayload: Boolean;
begin
  Result := assigned(fVulkanBuffer);
end;

function TvgDescriptor_PerFrame_UniformBuffer<T>.GetWriteDescriptorPayload( out aBufInfo: TVkDescriptorBufferInfo;
                                                                  out aImgInfo: TVkDescriptorImageInfo): Boolean;
begin
  Result := False;
  aBufInfo := Default(TVkDescriptorBufferInfo);   //never any data
  aImgInfo := Default(TVkDescriptorImageInfo);   //never any data

  If not assigned(fVulkanBuffer) then exit;

  aBufInfo := fVulkanBuffer.DescriptorBufferInfo;
  Result := True;
end;

Procedure TvgDescriptor_PerFrame_UniformBuffer<T>.SetDisabled;
begin
  Inherited;

  If assigned(fVulkanBuffer) then
     FreeAndNil(fVulkanBuffer);

end;

Procedure TvgDescriptor_PerFrame_UniformBuffer<T>.SetEnabled;
  Var SZ,SZ1  : TVkDeviceSize;
      I,L,J : Integer;
      DC:Integer;
      Device : TvgLogicalDevice;
      DD : TvgDescriptor_Data_UniformBuffer<T>;
begin
  Inherited;

  If not ((DF_UP in GetDataFlow) or (DF_DOWN in GetDataFlow)) then exit;

  SZ := fData.GetDataSize;
  If (SZ=0) then exit;

  Device := getDevice;
  CustomAssert(assigned(Device),'Device NOT connected.');

  If assigned(fDescriptorData) and (fDescriptorData is TvgDescriptor_Data_UniformBuffer<T>) then
    DD:=  TvgDescriptor_Data_UniformBuffer<T>(fDescriptorData)
  else
    DD:=nil;

  CustomAssert(assigned(DD),'Owner Descriptor Data NOT connected.');

  Try

      fVulkanBuffer := TpvVulkanBuffer.Create(Device.VulkanDevice,                  //TpvVulkanDevice;
                                              SZ,                   //TVkDeviceSize;
                                              DD.fBufferUsageFlags,    //TVkBufferUsageFlags;
                                              DD.fBufferSharingMode,   // TVkSharingMode;
                                              [],         // QueueFamilyIndices:array of TvkUint32;
                                              TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) or
                                              TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT), // MemoryRequiredPropertyFlags:TVkMemoryPropertyFlags;
                                              0,                                                  // MemoryPreferredPropertyFlags:TVkMemoryPropertyFlags;
                                              0,                                                  // MemoryAvoidPropertyFlags:TVkMemoryPropertyFlags;
                                              0,//TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT),   // MemoryPreferredNotPropertyFlags:TVkMemoryPropertyFlags;
                                              0,                                                  // MemoryRequiredHeapFlags:TVkMemoryHeapFlags;
                                              0,                                                  // MemoryAvoidHeapFlags:TVkMemoryHeapFlags;
                                              0,                                                  // MemoryPreferredNotHeapFlags:TVkMemoryHeapFlags;
                                              0,                                                  // MemoryPreferredNotHeapFlags:TVkMemoryHeapFlags;
                                              [TpvVulkanBufferFlag.PersistentMapped]);           // TpvVulkanBufferFlags


  Finally

  End;

end;

procedure TvgDescriptor_PerFrame_UniformBuffer<T>.UpLoadDescriptorData(aFrameIndex     :TvkUint32;
                                                aGraphicPool:TvgCommandBufferPool;
                                               aTransferPool:TvgCommandBufferPool);


  Var Queue      : TpvVulkanQueue;
      aCommand   : TvgCommandBuffer;
      Data       : Pointer;
      DSize      : TvkUint32;
      StageMode  : TpvVulkanBufferUseTemporaryStagingBufferMode;
      B          : Boolean;
      Device : TvgLogicalDevice;
      DD : TvgDescriptor_Data_UniformBuffer<T>;

begin

    If not (DF_UP in GetDataFlow) then exit;
    If not fUploadNeeded then exit;

    DSize :=  fData.GetDataSize;
    If DSize=0 then exit;

    if not (Active) then
       SetActiveState(True);

    CustomAssert(assigned(aTransferPool),'Transfer Buffer Pool NOT assigned');

    Device := getDevice;
    CustomAssert(assigned(Device),'Device NOT connected.');

    If assigned(fDescriptorData) and (fDescriptorData is TvgDescriptor_Data_UniformBuffer<T>) then
      DD:=  TvgDescriptor_Data_UniformBuffer<T>(fDescriptorData)
    else
      DD:=nil;

    CustomAssert(assigned(DD),'Owner Descriptor Data NOT connected.');

    Queue := aTransferPool.Queue[aFrameIndex];
    CustomAssert(Assigned(Queue),'Queue NOT available.');

  Try

          Data := fData.GetDataPointer;
          CustomAssert( (Data<>Nil),'No data available');

          aCommand        := aTransferPool.AcquireUploadCommand(0);//   RequestCommand(0,
          aCommand.Active := True;

          If GetStaging then
            StageMode     :=  TpvVulkanBufferUseTemporaryStagingBufferMode.Yes
          else
            StageMode     :=  TpvVulkanBufferUseTemporaryStagingBufferMode.Automatic;


             if Device.VulkanDevice.MemoryManager.CompleteTotalMemoryMappable then
               begin
                  fVulkanBuffer.UploadData(Queue,
                                            aCommand.VulkanCommandBuffer,
                                            aCommand.BufferFence,
                                            Data^,
                                            0,
                                            DSize,
                                            StageMode);  //TpvVulkanBufferUseTemporaryStagingBufferMode.No);

               end else
               begin
                  Device.VulkanDevice.MemoryStaging.Upload(Queue,
                                                           aCommand.VulkanCommandBuffer,
                                                           aCommand.BufferFence,
                                                           Data^,
                                                           fVulkanBuffer,
                                                           0,
                                                           DSize);

               end;


            fUploadNeeded := False;

  Finally
    aTransferPool.ReleaseCommand(aCommand);

  End;
end;

 { TvgDescriptorArray_Texture }

function TvgDescriptorArray_Texture.AddSharedTexture(aTextureName, aFileName: String): Integer;
var
  TD: TvgDescriptor_Data_Texture;
begin
  Result := -1;
  TD := TvgDescriptor_Data_Texture.Create;

  if AddDescriptorDataToArray(TD) then
  begin
    Result := IndexOfDescriptorData(TD);

    // ONE TvgDescriptor_PerFrame_Texture is created and loaded; every frame
    // in flight resolves to it, so no empty/invalid per frame texture exists.
    TD.LoadSharedTexture(aFileName);
  end else
    TD.Free;
end;

function TvgDescriptorArray_Texture.AddTexture(aTextureName,  aFileName: String): Integer;
  Var TD:TvgDescriptor_Data_Texture;
      TF : TvgDescriptorPerFrameData;
      TT:TvgDescriptor_PerFrame_Texture;
      I :Integer;
      GLSLIndex:TvkUint32;
begin
  Result := -1;

  TD:= TvgDescriptor_Data_Texture.Create;


  If AddDescriptorDataToArray(TD) then
  Begin
     Result := IndexOfDescriptorData(TD);
     For I:=0 to FrameCount-1 do
     Begin
       TF := TD.GetOrAddFrameDataObject(I);
       If assigned(TF) and (TF is TvgDescriptor_PerFrame_Texture) then
       Begin
         TT := TvgDescriptor_PerFrame_Texture(TF);
       //  TT.
         If assigned(TT) then
           TT.LoadTexture(aFileName, GLSLIndex);
       End;
     End;
  end else
     TD.Free;


 // TD.
 // self.add


end;

constructor TvgDescriptorArray_Texture.Create(AOwner: TComponent);
begin
  inherited Create(aOwner);

  fDescriptorType    := VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;//VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;

  fStageFlags        :=  TVkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT);

  fResourceType      :=    RT_TEXTURE;
  fDataFlow          := [DF_UP];


end;

function TvgDescriptorArray_Texture.GetDescriptor_Data_Texture( Index: Integer): TvgDescriptor_Data_Texture;
begin

end;

function TvgDescriptorArray_Texture.GetGLSLDeclarationBody: String;
begin
  Result := 'uniform sampler2D';  // or combined-image-sampler equivalent
end;

class function TvgDescriptorArray_Texture.GetPropertyName: String;
begin
  Result := 'Descriptor_Texture';
end;

function TvgDescriptorArray_Texture.RemoveTexture( aDataTexture: TvgDescriptor_Data_Texture): Boolean;
begin

end;


constructor TvgDescriptor_Data_Texture.Create;
begin
  inherited;

  fSampler      := TvgSampler.Create(nil);
  fSampler.SetSubComponent(True);
  fSampler.Name := 'Sampler';


  fWrapModeU    := TpvVulkanTextureWrapMode.ClampToBorder;
  fWrapModeV    := TpvVulkanTextureWrapMode.ClampToBorder;
  fWrapModeW    := TpvVulkanTextureWrapMode.ClampToBorder;
  fBorderColor  := VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK;

end;

destructor TvgDescriptor_Data_Texture.Destroy;
begin
  SetActiveState(False); //must stay here

  If assigned(fSampler) then
    FreeAndNil(fSampler);

  inherited;
end;

function TvgDescriptor_Data_Texture.GetBorderColor: TvgBorderColor;
begin
  Result := GetVGBorderColor(fBorderColor);
end;

function TvgDescriptor_Data_Texture.GetGLSLBaseTypeName: String;
begin
  if Assigned(fDescriptor) and
     (fDescriptor.DescriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER) then
    Result := 'sampler2D'
  else
    Result := 'texture2D';
end;

function TvgDescriptor_Data_Texture.GetOrAddFrameDataObject( aFrameIndex: Integer): TvgDescriptorPerFrameData;
  Var DT: TvgDescriptor_PerFrame_Texture;
begin
  If (aFrameIndex>=0) and (aFrameIndex<Length(fFrameData)) then
  Begin

    If Not assigned(fFrameData[aFrameIndex]) then
    Begin
       DT:= TvgDescriptor_PerFrame_Texture.Create;
       DT.fDescriptorData      := Self;
       fFrameData[aFrameIndex] := DT;

       Result := DT;
    End else
      Result:=  fFrameData[aFrameIndex];

  End else
    Result := Nil;
end;

function TvgDescriptor_Data_Texture.GetTextureFrame(Index: Integer): TvgDescriptor_PerFrame_Texture;
var
  DF: TvgDescriptorPerFrameData;
begin
  Result := nil;
  DF := GetFrameData(Index);
  if DF is TvgDescriptor_PerFrame_Texture then
    Result := TvgDescriptor_PerFrame_Texture(DF);
end;

function TvgDescriptor_Data_Texture.GetWrapModeU: TpvVulkanTextureWrapMode;
begin
  Result := fWrapModeU;
end;

function TvgDescriptor_Data_Texture.GetWrapModeV: TpvVulkanTextureWrapMode;
begin
  Result := fWrapModeV;
end;

function TvgDescriptor_Data_Texture.GetWrapModeW: TpvVulkanTextureWrapMode;
begin
  Result := fWrapModeW;
end;

procedure TvgDescriptor_Data_Texture.SetBorderColor(const Value: TvgBorderColor);
  Var V: TvkBorderColor ;
begin
  V:= GetVKBorderColor(Value);
  If fBorderColor=V then exit;
  SetActiveState(False);
  fBorderColor := V;
end;

Procedure TvgDescriptor_Data_Texture.SetDisabled;
  Var I,L:Integer;
begin
  Inherited;

  If assigned(fSampler) then
     fSampler.Active := False;

  L:=Length(fFrameData);
  If L>0 then
    For I:=0 to L-1 do
      If assigned(fFrameData[I]) then
        fFrameData[I].Active := False;

end;

Procedure TvgDescriptor_Data_Texture.SetEnabled;

  Var I,L:Integer;
begin

  //ONE loaded texture serves every frame : drop the empty frame objects BEFORE
  //they are activated, so no invalid texture is ever created or written.
  CollapseToSharedTexture;

  Inherited;

  If assigned(fSampler) then
  Begin
     fSampler.Device := GetDevice;
     fSampler.Active := TRue;

  End;

  L:=Length(fFrameData);
  If L>0 then
    For I:=0 to L-1 do
      If assigned(fFrameData[I]) then
        fFrameData[I].Active := True ;
end;

Procedure TvgDescriptor_Data_Texture.CollapseToSharedTexture;
  Var I, L, FoundIndex, FoundCount:Integer;
      TF:TvgDescriptor_PerFrame_Texture;
begin
  L := Length(fFrameData);
  If L<=1 then exit;

  FoundIndex := -1;
  FoundCount := 0;

  For I:=0 to L-1 do
    If (fFrameData[I] is TvgDescriptor_PerFrame_Texture) then
    Begin
      TF := TvgDescriptor_PerFrame_Texture(fFrameData[I]);
      If TF.HasPayload then
      Begin
        If FoundIndex<0 then
           FoundIndex := I;
        Inc(FoundCount);
      End;
    End;

  //More than one frame carries its own texture : this is the classic
  //one-texture-per-frame setup, leave it alone.
  If (FoundCount<>1) or (FoundIndex<0) then exit;

  fSharedFrameData := True;
  DropSurplusFrameData(FoundIndex);
end;

function TvgDescriptor_Data_Texture.LoadSharedTexture(aFileName: String): Boolean;
  Var TF:TvgDescriptorPerFrameData;
      GLSLIndex:TvkUint32;
begin
  Result := False;

  SharedFrameData := True;   //keeps/creates a single frame object only

  If Length(fFrameData)=0 then
     FrameCount := 1;        //nothing sized yet - one slot is all that is needed

  TF := GetFrameData(0);
  If not (TF is TvgDescriptor_PerFrame_Texture) then exit;

  GLSLIndex := fGLSLIndex;
  Result    := TvgDescriptor_PerFrame_Texture(TF).LoadTexture(aFileName, GLSLIndex);
end;

procedure TvgDescriptor_Data_Texture.SetFrameCount(aCount: Integer);
  Var L,I:Integer;
begin

  If  (aCount<0) or (aCount > MaxFramesInFlight) then exit;
  L:=Length(fFrameData);

  If L=aCount then exit
  else
  If (aCount>L) then
  Begin
    SetLength(fFrameData, aCount);

    If fSharedFrameData then
    Begin
      //ONE object only, every frame resolves to it
      If (Length(fFrameData)>0) and not assigned(fFrameData[0]) then
         GetOrAddFrameDataObject(0);
      DropSurplusFrameData(0);
    End else
      For I:=0 to aCount-1 do
          GetOrAddFrameDataObject(I);
  end else
  //aCount<L
  Begin
    For I:= aCount to L-1 do
       If assigned(fFrameData[I]) then
          FreeAndNil(fFrameData[I]);

    SetLength(fFrameData, aCount);
  End;

end;

procedure TvgDescriptor_Data_Texture.SetWrapModeU( const Value: TpvVulkanTextureWrapMode);
begin
  If fWrapModeU = Value then exit;
  SetActiveState(False);
  fWrapModeU := Value;
end;

procedure TvgDescriptor_Data_Texture.SetWrapModeV( const Value: TpvVulkanTextureWrapMode);
begin
  If fWrapModeV = Value then exit;
  SetActiveState(False);
  fWrapModeV := Value;
end;

procedure TvgDescriptor_Data_Texture.SetWrapModeW( const Value: TpvVulkanTextureWrapMode);
begin
  If fWrapModeW = Value then exit;
  SetActiveState(False);
  fWrapModeW := Value;
end;


{ TvgVector4S }

constructor TvgVector4S.Create(const aVec: TpvVector4);
begin
 X:=aVec.x;
 Y:=aVec.Y;
 Z:=aVec.Z;
 W:=aVec.W;
end;

constructor TvgVector4S.Create(const aX, aY, aZ, aW: TvgScalarS);
begin
  X:=aX;
  Y:=aY;
  Z:=aZ;
  W:=aW;
end;


{ TvgElementSampler }

procedure TvgElementSampler.CopyElementsToStaging2D(CentreX, CentreY : Integer);
var
  HalfSize            : Integer;
  StartX, StartY       : Integer;
  RowCount             : Integer;
  Row                  : Integer;
  RowBytes             : TVkDeviceSize;
  CopyRegions          : array of TVkBufferCopy;
  BufferBarrierPre, BufferBarrierPost : TVkBufferMemoryBarrier;
begin
  CustomAssert(assigned(fCommandBuffer), 'Command Buffer NOT assigned in TvgElementSampler');
  CustomAssert(fStrideWidth > 0,          'StrideWidth must be > 0 for 2D sampling in TvgElementSampler');

  HalfSize := fSampleSize div 2;
  RowCount := Integer(fElementCount) div Integer(fStrideWidth);

  // Clamp X and Y independently to their own axis - this is the key
  // difference from the 1D path, which only had one axis to clamp.
  StartX := CentreX - HalfSize;
  if StartX < 0 then StartX := 0;
  if StartX + fSampleSize > Integer(fStrideWidth) then
    StartX := Integer(fStrideWidth) - fSampleSize;
  if StartX < 0 then StartX := 0;

  StartY := CentreY - HalfSize;
  if StartY < 0 then StartY := 0;
  if StartY + fSampleSize > RowCount then
    StartY := RowCount - fSampleSize;
  if StartY < 0 then StartY := 0;

  fLastSampleX     := CentreX;
  fLastSampleY     := CentreY;
  fLastSampleIndex := (CentreY * Integer(fStrideWidth)) + CentreX;  // Y*StrideWidth+X, kept for bookkeeping/logging

  RowBytes := TVkDeviceSize(fSampleSize) * TVkDeviceSize(fElementStride);

  // One copy region per row of the window - rows are contiguous
  // internally (fSampleSize elements), but consecutive rows are
  // StrideWidth elements apart in the source buffer.
  SetLength(CopyRegions, fSampleSize);
  for Row := 0 to fSampleSize - 1 do
  begin
    CopyRegions[Row].srcOffset :=
      (TVkDeviceSize(StartY + Row) * TVkDeviceSize(fStrideWidth) + TVkDeviceSize(StartX)) *
      TVkDeviceSize(fElementStride);
    CopyRegions[Row].dstOffset := TVkDeviceSize(Row) * RowBytes;
    CopyRegions[Row].size      := RowBytes;
  end;

  // Barrier covers the full bounding box from the first row's start to the
  // last row's end - conservatively includes the gaps between rows too,
  // which is harmless for a barrier (just slightly wider than strictly needed).
  FillChar(BufferBarrierPre, SizeOf(BufferBarrierPre), 0);
  BufferBarrierPre.sType               := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
  BufferBarrierPre.srcAccessMask       := TVkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT);
  BufferBarrierPre.dstAccessMask       := TVkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT);
  BufferBarrierPre.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  BufferBarrierPre.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  BufferBarrierPre.buffer              := fSourceBuffer[fCurrentFrame].Handle;
  BufferBarrierPre.offset              := CopyRegions[0].srcOffset;
  BufferBarrierPre.size                :=
    (TVkDeviceSize(fSampleSize - 1) * TVkDeviceSize(fStrideWidth) * TVkDeviceSize(fElementStride)) + RowBytes;

  BufferBarrierPost               := BufferBarrierPre;
  BufferBarrierPost.srcAccessMask := TVkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT);
  BufferBarrierPost.dstAccessMask := TVkAccessFlags(VK_ACCESS_SHADER_READ_BIT) or
                                      TVkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT);

  fCommandBuffer.Reset;
  fCommandBuffer.PrepareForRecording;
  fCommandBuffer.BeginRecording;

  fCommandBuffer.CmdPipelineBarrier(
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT) or
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT),
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
      0, 0, nil, 1, @BufferBarrierPre, 0, nil);

  fCommandBuffer.CmdCopyBuffer(
      fSourceBuffer[fCurrentFrame].Handle,
      fStagingBuffer.Handle,
      fSampleSize, @CopyRegions[0]);          // one region per row, single call

  fCommandBuffer.CmdPipelineBarrier(
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT) or
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT),
      0, 0, nil, 1, @BufferBarrierPost, 0, nil);

  fCommandBuffer.EndRecording;

  fCommandBuffer.ExecuteCommand(
      fDevice.VulkanDevice.TransferQueue,
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT),
      nil, nil, True, True);
end;


constructor TvgElementSampler.Create;
begin
inherited;
  fSampleRadius       := psr_1x1;
  fSampleSize         := 1;
  fSamplingDimension  := esdLinear1D;
  fStrideWidth        := 0;
  fLastSampleIndex    := -1;
  fLastSampleX        := -1;
  fLastSampleY         := -1;
  fElementStride       := 0;
  fElementCount        := 0;
end;

destructor TvgElementSampler.Destroy;
begin
  SetActiveState(False);
  SetLength(fSampledData, 0);
  inherited;
end;

procedure TvgElementSampler.SetSampleRadius(const Value : TvgPixelSampleRadius);
begin
  if fSampleRadius = Value then Exit;

  if Active then
  begin
    SetActiveState(False);
    fSampleRadius := Value;
    case fSampleRadius of
      psr_1x1 : fSampleSize := 1;
      psr_3x3 : fSampleSize := 3;
      psr_5x5 : fSampleSize := 5;
      psr_7x7 : fSampleSize := 7;
      psr_9x9 : fSampleSize := 9;
    end;
   // SetActiveState(True);
  end
  else
  begin
    fSampleRadius := Value;
    case fSampleRadius of
      psr_1x1 : fSampleSize := 1;
      psr_3x3 : fSampleSize := 3;
      psr_5x5 : fSampleSize := 5;
      psr_7x7 : fSampleSize := 7;
      psr_9x9 : fSampleSize := 9;
    end;
  end;

  // Resize staging data array to match new window
  SetLength(fSampledData, TvkUint32(fSampleSize) * fElementStride)
end;

procedure TvgElementSampler.SetSamplingDimension( const Value: TvgElementSamplingDimension);
begin
  if fSamplingDimension = Value then Exit;
  CustomAssert((Active=False),'You can''t change the Sampling Dimension when active');
 // SetActiveState(False);
  fSamplingDimension := Value;
end;

procedure TvgElementSampler.SetSourceBuffer(Index: Integer; const Value: TpvVulkanBuffer);
begin
  If (Index<0) or (Index>=Length(fSourceBuffer)) then exit;

  If  fSourceBuffer[Index]=Value then exit;
  self.SetActiveState(False);

  fSourceBuffer[Index]:=Value ;
end;

procedure TvgElementSampler.SetStrideWidth(const Value: TvkUint32);
begin
  if fStrideWidth = Value then Exit;
  CustomAssert((Active=False),'You can''t change the Stride Width when active');
//  SetActiveState(False);
  fStrideWidth := Value;
end;

function TvgElementSampler.GetSampleSize : Integer;
begin
  Result := fSampleSize;
end;

function TvgElementSampler.GetSourceBuffer(Index: Integer): TpvVulkanBuffer;
begin
  If (Index<0) or (Index>=Length(fSourceBuffer)) then
    Result :=nil
  else
    Result :=  fSourceBuffer[Index];
end;

function TvgElementSampler.GetStagingElementCount: Integer;
begin
  if fSamplingDimension = esdGrid2D then
    Result := fSampleSize * fSampleSize
  else
    Result := fSampleSize;
end;

procedure TvgElementSampler.CreateStagingBuffer;
var
  BufferSize : TVkDeviceSize;
begin
  if not assigned(fSourceBuffer) then exit;
  if (fElementStride = 0)        then exit;

  CustomAssert(assigned(fDevice),               'Device not connected to TvgElementSampler');
  CustomAssert(assigned(fDevice.VulkanDevice),   'Vulkan Device not active in TvgElementSampler');

  // Staging buffer holds SampleSize contiguous elements
  BufferSize := TVkDeviceSize(GetStagingElementCount) * TVkDeviceSize(fElementStride);

  fStagingBuffer :=
      TpvVulkanBuffer.Create(
          fDevice.VulkanDevice,
          BufferSize,
          TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_DST_BIT),
          TVkSharingMode(VK_SHARING_MODE_EXCLUSIVE),
          [],
          TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) or
          TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
          0, 0, 0, 0, 0, 0, 0,
          [TpvVulkanBufferFlag.PersistentMapped]);
end;

procedure TvgElementSampler.CopyElementsToStaging(CentreIndex : Integer);
var
  HalfSize    : Integer;
  StartIndex  : Integer;
  SrcOffset   : TVkDeviceSize;
  CopySize    : TVkDeviceSize;
  CopyRegion  : TVkBufferCopy;
  BufferBarrierPre, BufferBarrierPost : TVkBufferMemoryBarrier;
begin
  CustomAssert(assigned(fCommandBuffer), 'Command Buffer NOT assigned in TvgElementSampler');

  // ----- Clamp source window to buffer bounds ---------------------------------
  HalfSize   := fSampleSize div 2;
  StartIndex := CentreIndex - HalfSize;
  if StartIndex < 0 then
    StartIndex := 0;
  if StartIndex + fSampleSize > Integer(fElementCount) then
    StartIndex := Integer(fElementCount) - fSampleSize;
  if StartIndex < 0 then
    StartIndex := 0;

  fLastSampleIndex := CentreIndex;

  SrcOffset := TVkDeviceSize(StartIndex) * TVkDeviceSize(fElementStride);
  CopySize  := TVkDeviceSize(fSampleSize) * TVkDeviceSize(fElementStride);

  // ----- Pre-copy barrier: shader write → transfer read ----------------------
  FillChar(BufferBarrierPre, SizeOf(BufferBarrierPre), 0);
  BufferBarrierPre.sType               := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
  BufferBarrierPre.srcAccessMask       := TVkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT);
  BufferBarrierPre.dstAccessMask       := TVkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT);
  BufferBarrierPre.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  BufferBarrierPre.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  BufferBarrierPre.buffer              := fSourceBuffer[fCurrentFrame].Handle;
  BufferBarrierPre.offset              := SrcOffset;
  BufferBarrierPre.size                := CopySize;

  // ----- Post-copy barrier: transfer read → shader read/write ---------------
  FillChar(BufferBarrierPost, SizeOf(BufferBarrierPost), 0);
  BufferBarrierPost.sType               := VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
  BufferBarrierPost.srcAccessMask       := TVkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT);
  BufferBarrierPost.dstAccessMask       := TVkAccessFlags(VK_ACCESS_SHADER_READ_BIT) or
                                           TVkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT);
  BufferBarrierPost.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  BufferBarrierPost.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
  BufferBarrierPost.buffer              := fSourceBuffer[fCurrentFrame].Handle;
  BufferBarrierPost.offset              := SrcOffset;
  BufferBarrierPost.size                := CopySize;

  // ----- Copy region ---------------------------------------------------------
  FillChar(CopyRegion, SizeOf(CopyRegion), 0);
  CopyRegion.srcOffset := SrcOffset;
  CopyRegion.dstOffset := 0;
  CopyRegion.size      := CopySize;

  // ----- Record and submit ---------------------------------------------------
  fCommandBuffer.Reset;
  fCommandBuffer.PrepareForRecording;
  fCommandBuffer.BeginRecording;

  fCommandBuffer.CmdPipelineBarrier(
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT) or
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT),
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
      0,
      0, nil,
      1, @BufferBarrierPre,
      0, nil);

  fCommandBuffer.CmdCopyBuffer(
      fSourceBuffer[fCurrentFrame].Handle,
      fStagingBuffer.Handle,
      1, @CopyRegion);

  fCommandBuffer.CmdPipelineBarrier(
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT) or
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT),
      0,
      0, nil,
      1, @BufferBarrierPost,
      0, nil);

  fCommandBuffer.EndRecording;

  fCommandBuffer.ExecuteCommand(
      fDevice.VulkanDevice.TransferQueue,
      TVkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT),
      nil, nil,
      True,   // wait fence
      True);  // submit
end;

function TvgElementSampler.ReadElementsFromStaging : Boolean;
var
  ReadSize : TvkUint32;
begin
  Result := False;
  if not Active           then exit;
  if fElementStride = 0    then exit;
  if not assigned(fStagingBuffer) then exit;

  ReadSize := TvkUint32(GetStagingElementCount) * fElementStride;
  SetLength(fSampledData, ReadSize);

  // PersistentMapped buffer: fetch directly via FetchData
  fStagingBuffer.FetchData(fSampledData[0], 0, ReadSize);

  Result := True;
end;

function TvgElementSampler.SampleElement(CentreIndex : Integer) : Boolean;
begin
  Result := False;
  if not Active then exit;
  CustomAssert(fSamplingDimension = esdLinear1D,
    'SampleElement is for esdLinear1D - use SampleElementXY when SamplingDimension = esdGrid2D');   // NEW

  CopyElementsToStaging(CentreIndex);
  Result := ReadElementsFromStaging;
end;

function TvgElementSampler.SampleElementXY(CentreX, CentreY: Integer): Boolean;
begin
  Result := False;
  if not Active then exit;

  CustomAssert(fSamplingDimension = esdGrid2D, 'SampleElementXY requires SamplingDimension = esdGrid2D');

  CopyElementsToStaging2D(CentreX, CentreY);
  Result := ReadElementsFromStaging;
end;

function TvgElementSampler.GetElementBytes(RelativeOffset : Integer;
                                            out Data      : Pointer;
                                            out ByteCount : TvkUint32) : Boolean;
var
  AbsoluteOffset : Integer;
  ByteOffset     : TvkUint32;
begin
  Result    := False;
  Data      := nil;
  ByteCount := 0;

  if fElementStride = 0         then exit;
  if Length(fSampledData) = 0   then exit;

  // Centre element sits at index (fSampleSize div 2) in the sampled window
  AbsoluteOffset := (fSampleSize div 2) + RelativeOffset;

  if (AbsoluteOffset < 0) or (AbsoluteOffset >= fSampleSize) then exit;

  ByteOffset := TvkUint32(AbsoluteOffset) * fElementStride;
  if (ByteOffset + fElementStride) > TvkUint32(Length(fSampledData)) then exit;

  Data      := @fSampledData[ByteOffset];
  ByteCount := fElementStride;
  Result    := True;
end;

function TvgElementSampler.GetElementBytesXY(RelativeX, RelativeY: Integer;  out Data: Pointer; out ByteCount: TvkUint32): Boolean;
var
  Col, Row       : Integer;
  ByteOffset     : TvkUint32;
begin
  Result    := False;
  Data      := nil;
  ByteCount := 0;

  if fElementStride = 0       then exit;
  if Length(fSampledData) = 0 then exit;

  Col := (fSampleSize div 2) + RelativeX;
  Row := (fSampleSize div 2) + RelativeY;

  if (Col < 0) or (Col >= fSampleSize) then exit;
  if (Row < 0) or (Row >= fSampleSize) then exit;

  // Matches the row-major layout CopyElementsToStaging2D wrote into
  // fSampledData: row * fSampleSize + col, in elements.
  ByteOffset := TvkUint32((Row * fSampleSize) + Col) * fElementStride;
  if (ByteOffset + fElementStride) > TvkUint32(Length(fSampledData)) then exit;

  Data      := @fSampledData[ByteOffset];
  ByteCount := fElementStride;
  Result    := True;
end;

procedure TvgElementSampler.SetCurrentFrame(const Value: TvkUint32);
   Var V:TvkUint32;
begin
  If fCurrentFrame=Value then exit;
  V:=Value;

  If V>FrameCount-1 then
     V := FrameCount-1;

  fCurrentFrame := V;
end;

procedure TvgElementSampler.SetDisabled;
begin
  Inherited;

  if assigned(fStagingBuffer) then
    FreeAndNil(fStagingBuffer);

  fCommandBuffer := nil;

  if assigned(fCommandPool) then
  begin
    fCommandPool.ReleaseAllCommands(True);
    fCommandPool.Active := False;
    FreeAndNil(fCommandPool);
  end;

  SetLength(fSampledData, 0);
  Active := False;
end;

procedure TvgElementSampler.SetEnabled;
begin
  Inherited;
  Active := False;

  CustomAssert(assigned(fSourceBuffer),          'Source Buffer NOT assigned to TvgElementSampler');
  CustomAssert(assigned(fDevice),                'Device NOT assigned to TvgElementSampler');
  CustomAssert(assigned(fDevice.VulkanDevice),   'Vulkan Device NOT active in TvgElementSampler');
  CustomAssert(fElementStride > 0,               'ElementStride must be > 0 in TvgElementSampler');
  CustomAssert(fElementCount  > 0,               'ElementCount must be > 0 in TvgElementSampler');

  if fSamplingDimension = esdGrid2D then
  begin
    CustomAssert(fStrideWidth > 0, 'StrideWidth must be > 0 when SamplingDimension = esdGrid2D in TvgElementSampler');
    CustomAssert(fStrideWidth >= TvkUint32(fSampleSize),
      'StrideWidth must be >= the sample window size (fSampleSize) for 2D sampling - window would overrun into the next row');
    CustomAssert((fElementCount div fStrideWidth) >= TvkUint32(fSampleSize),
      'Row count (ElementCount / StrideWidth) must be >= the sample window size (fSampleSize) for 2D sampling');
  end;

  // Resolve sample size from radius
  case fSampleRadius of
    psr_1x1 : fSampleSize := 1;
    psr_3x3 : fSampleSize := 3;
    psr_5x5 : fSampleSize := 5;
    psr_7x7 : fSampleSize := 7;
    psr_9x9 : fSampleSize := 9;
  end;

  SetLength(fSampledData, TvkUint32(fSampleSize) * fElementStride);

  CreateStagingBuffer;

  fCommandPool                 := TvgCommandBufferPool.Create(nil);
  fCommandPool.Device          := fDevice;
  fCommandPool.QueueFamilyType := VGT_TRANSFER;
  fCommandPool.QueueCreateFlags:= [CP_RESET_COMMAND_BUFFER];
  fCommandPool.SetUpBufferArrays(1);
  fCommandPool.Active          := True;

  if fCommandPool.Active then
  begin
    fCommandBuffer := fCommandPool.AcquireUploadCommand(0);
    if assigned(fCommandBuffer) then
      fCommandBuffer.Active := True;
  end;

  Active := True;
end;


procedure TvgElementSampler.SetFrameCount(const Value: TvkUint32);
begin
  If fFrameCount=Value then exit;
  SetActiveState(False);

  fFrameCount := Value;

  SetLength(fSourceBuffer, fFrameCount);

end;

Procedure TvgDescriptor_PerFrame_StorageBuffer<T>.SetDisabled ;
begin
  // Destroy device-local Vulkan buffers
  Inherited;

  If assigned(fVulkanBuffer) then
     FreeAndNil(fVulkanBuffer);


end;

Procedure TvgDescriptor_PerFrame_StorageBuffer<T>.SetEnabled;
var
  SZ     : TVkDeviceSize;
  Device : TvgLogicalDevice;
  DD     : TvgDescriptor_Data_StorageBuffer<T>;
begin
  Inherited;

  If Not(DF_UP   in GetDataFlow) and
     Not(DF_DOWN in GetDataFlow) then exit;

  If assigned(fDescriptorData) and (fDescriptorData is TvgDescriptor_Data_StorageBuffer<T>) then
    DD := TvgDescriptor_Data_StorageBuffer<T>(fDescriptorData)
  else
    DD := nil;

  CustomAssert(assigned(DD), 'Owner Descriptor Data NOT connected.');

// Keep this frame's CPU-side array sized to match the owning descriptor's
  // ElementCount. Existing items are preserved; new slots are zero-filled.
  fData.SetItemCapacity(DD.fElementCount);

  SZ := TVkDeviceSize(DD.fElementCount) * TVkDeviceSize(SizeOf(T));
  If (SZ = 0) then exit;

  Device := GetDevice;
  CustomAssert(assigned(Device), 'Device NOT connected.');

  Try

    fVulkanBuffer := TpvVulkanBuffer.Create(Device.VulkanDevice,               //TpvVulkanDevice;
                                             SZ,                               //TVkDeviceSize;
                                             DD.fBufferUsageFlags,             //TVkBufferUsageFlags;
                                             DD.fBufferSharingMode,            //TVkSharingMode;
                                             [],                               //QueueFamilyIndices
                                             TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) or
                                             TVkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT), //MemoryRequiredPropertyFlags
                                             0,                                //MemoryPreferredPropertyFlags
                                             0,                                //MemoryAvoidPropertyFlags
                                             0,                                //MemoryPreferredNotPropertyFlags
                                             0,                                //MemoryRequiredHeapFlags
                                             0,                                //MemoryAvoidHeapFlags
                                             0,
                                             0,                                //MemoryPreferredNotHeapFlags
                                             [TpvVulkanBufferFlag.PersistentMapped]);
  Finally

  End;
end;


// ---------------------------------------------------------------------------
// Data upload (identical to TvgDescriptor_SSBO pattern)
// ---------------------------------------------------------------------------

procedure TvgDescriptor_PerFrame_StorageBuffer<T>.UpLoadDescriptorData( aFrameIndex   : TvkUint32;
                                                                    aGraphicPool  : TvgCommandBufferPool;
                                                                    aTransferPool : TvgCommandBufferPool);
var
  Queue      : TpvVulkanQueue;
  aCommand   : TvgCommandBuffer;
  Data       : Pointer;
  DSize      : TvkUint32;
  StageMode  : TpvVulkanBufferUseTemporaryStagingBufferMode;

  Device :TvgLogicalDevice;
begin
    CustomAssert(assigned(fVulkanBuffer),  'Vulkan Buffer NOT assigned');


    If not (DF_UP in GetDataFlow) then exit;
    If not fUploadNeeded then exit;

    Device := GetDevice;
    CustomAssert(assigned(Device),  'Device NOT assigned');

  //  If not IsDataUploadNeeded(aFrameIndex) then exit;

  if not (Active) then
    SetActiveState(True);

  CustomAssert(assigned(aTransferPool),           'Transfer Buffer Pool NOT assigned');
  CustomAssert(assigned(fDescriptorData),'Descriptor NOT assigned');
  CustomAssert(assigned(fDescriptorData.Descriptor),'Descriptor Array NOT assigned');
  CustomAssert(assigned(fDescriptorData.Descriptor.DescriptorItem),'Descriptor Array NOT assigned');

  if not assigned(Device.VulkanDevice) then
    Device.Active := True;

  CustomAssert(assigned(Device.VulkanDevice), 'Vulkan Device not available.');

  Queue := aTransferPool.Queue[aFrameIndex];
  CustomAssert(Assigned(Queue), 'Queue NOT available.');



  DSize := fData.GetDataSize;//GetStride;    //correct
  if DSize = 0 then exit;

  Data := fData.GetDataPointer;

  aCommand := aTransferPool.AcquireUploadCommand(0);

  if GetStaging then
    StageMode := TpvVulkanBufferUseTemporaryStagingBufferMode.Yes
  else
    StageMode := TpvVulkanBufferUseTemporaryStagingBufferMode.Automatic;

  Try
    if Device.VulkanDevice.MemoryManager.CompleteTotalMemoryMappable then
    begin
      fVulkanBuffer.UploadData(   Queue,
                                  aCommand.VulkanCommandBuffer,
                                  aCommand.BufferFence,
                                  Data^,
                                  0,
                                  DSize,
                                  StageMode);

    end
    else
    begin
      Device.VulkanDevice.MemoryStaging.Upload(
                                                Queue,
                                                aCommand.VulkanCommandBuffer,
                                                aCommand.BufferFence,
                                                Data^,
                                                fVulkanBuffer,
                                                0,
                                                DSize);

    end;

    fUploadNeeded:=False;

  Finally
    aTransferPool.ReleaseCommand(aCommand);
  End;
end;

procedure TvgDescriptor_PerFrame_StorageBuffer<T>.ClearDataOnGPU(aIndex:Integer; aTransferPool: TvgCommandBufferPool; aCommandBuffer: TvgCommandBuffer = nil);
var
  aCommand : TvgCommandBuffer;
  Queue    : TpvVulkanQueue;
  Barrier  : TVkBufferMemoryBarrier;
  Size     : TVkDeviceSize;
  aFrameIndex : Integer;
begin

  if not Assigned(fVulkanBuffer) then   Exit;
  If aIndex<0 then exit;

  Size := fVulkanBuffer.Size;

  if Size = 0 then  Exit;

  If assigned(aCommandBuffer) then
  Begin
     aCommand := aCommandBuffer  ;

  end else
  Begin
     if not Assigned(aTransferPool) then  Exit;
     Queue := aTransferPool.Queue[aIndex];
     CustomAssert(Assigned(Queue), 'Transfer Queue NOT available.');

     aCommand := aTransferPool.AcquireUploadCommand(aIndex);
     aCommand.Active := True;
     aCommand.BeginRecording;

  End;
  if not Assigned(aCommand) then   Exit;

  try

    // ------------------------------------------------------------
    // 1. Make previous buffer accesses visible to the transfer
    //    operation.
    //
    //    This is important if this particular per-frame buffer
    //    has previously been used as a shader storage buffer.
    // ------------------------------------------------------------
    Barrier                     := Default(TVkBufferMemoryBarrier);

    Barrier.sType               :=  VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
    Barrier.srcAccessMask       := TVkAccessFlags(VK_ACCESS_SHADER_READ_BIT) or
                                   TVkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT);
    Barrier.dstAccessMask       := TVkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT);
    Barrier.srcQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    Barrier.dstQueueFamilyIndex := VK_QUEUE_FAMILY_IGNORED;
    Barrier.buffer              :=   fVulkanBuffer.Handle;
    Barrier.offset              := 0;
    Barrier.size                := Size;

    aCommand.CmdPipelineBarrier(  TVkPipelineStageFlags(VK_PIPELINE_STAGE_VERTEX_SHADER_BIT) or
                                  TVkPipelineStageFlags(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT) or
                                  TVkPipelineStageFlags(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT),
                                  TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
                                  0,
                                  0, nil,
                                  1, @Barrier,
                                  0, nil
                                );


    // ------------------------------------------------------------
    // 2. Fill the entire buffer with zero.
    // ------------------------------------------------------------
    aCommand.CmdFillBuffer(fVulkanBuffer.Handle,
                            0,
                            Size,
                            0
                          );


    // ------------------------------------------------------------
    // 3. Make the transfer writes available to subsequent shader
    //    reads/writes.
    // ------------------------------------------------------------
    Barrier.srcAccessMask := TVkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT);
    Barrier.dstAccessMask :=  TVkAccessFlags(VK_ACCESS_SHADER_READ_BIT) or
                              TVkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT);

    aCommand.CmdPipelineBarrier( TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
                                TVkPipelineStageFlags(VK_PIPELINE_STAGE_VERTEX_SHADER_BIT) or
                                TVkPipelineStageFlags(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT) or
                                TVkPipelineStageFlags(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT),
                                0,
                                0, nil,
                                1, @Barrier,
                                0, nil
                              );


    If NOT assigned(aCommandBuffer) then
    Begin

      aCommand.EndRecording;
      if aCommand.CommandCount > 0 then

        aCommand.ExecuteCommand(  Queue,
                                  TVkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT),
                                  nil,
                                  nil,
                                  True,
                                  True
                                );

      aTransferPool.ReleaseCommand(aCommand);
    End;

  finally

  end;

end;

function TvgDescriptor_PerFrame_StorageBuffer<T>.GetWriteDescriptorPayload(
  out aBufInfo: TVkDescriptorBufferInfo;
  out aImgInfo: TVkDescriptorImageInfo): Boolean;
begin
  Result := False;
  aBufInfo := Default(TVkDescriptorBufferInfo);
  aImgInfo := Default(TVkDescriptorImageInfo);

  CustomAssert(Assigned(fVulkanBuffer),'Vulkan Buffer NOT assigned');

  aBufInfo := fVulkanBuffer.DescriptorBufferInfo;
  Result := True;
end;

function TvgDescriptor_PerFrame_StorageBuffer<T>.HasPayload: Boolean;
begin
  Result := assigned(fVulkanBuffer);
end;

{ TvgDescriptor_PerFrame_StorageImage }

procedure TvgDescriptor_PerFrame_StorageImage.ClearDataOnGPU(aIndex:Integer; aTransferPool: TvgCommandBufferPool; aCommandBuffer: TvgCommandBuffer = nil);
var
 DD            : TvgDescriptor_Data_StorageImage;
 Barrier       : TVkImageMemoryBarrier;
 aCommand    : TvgCommandBuffer;
  Queue    : TpvVulkanQueue;


begin
   if not Active or
      not Assigned(fStorageImageBuffer) or
      not (DescriptorData is TvgDescriptor_Data_StorageImage) then  Exit;

    If assigned(aCommandBuffer) then
    Begin
       aCommand:=aCommandBuffer;
    end else
    Begin
       if not Assigned(aTransferPool) then  Exit;
       Queue := aTransferPool.Queue[aIndex];
       CustomAssert(Assigned(Queue), 'Transfer Queue NOT available.');

       aCommand := aTransferPool.AcquireUploadCommand(aIndex);
       aCommand.Active := True;
       aCommand.BeginRecording;

    End;

    if not Assigned(aCommand) then   Exit;


    DD := TvgDescriptor_Data_StorageImage(DescriptorData);

     Barrier                      := Default(TVkImageMemoryBarrier);
     Barrier.sType                := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
     Barrier.srcAccessMask        := TVkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT);
     Barrier.dstAccessMask        := TVkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT);
     Barrier.oldLayout            := VK_IMAGE_LAYOUT_GENERAL;
     Barrier.newLayout            := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
     Barrier.srcQueueFamilyIndex  := VK_QUEUE_FAMILY_IGNORED;
     Barrier.dstQueueFamilyIndex  := VK_QUEUE_FAMILY_IGNORED;
     Barrier.image                := fStorageImageBuffer.Image.Handle;
     Barrier.subresourceRange     := DD.fSubRange;

     aCommand.CmdPipelineBarrier( TVkPipelineStageFlags(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT),
                                       TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
                                       0, 0, nil, 0, nil, 1, @Barrier);

     aCommand.CmdClearColorImage( fStorageImageBuffer.Image.Handle,
                                       VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                       @DD.fClearCol,
                                       1, @DD.fSubRange);

     Barrier.srcAccessMask := TVkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT);
     Barrier.dstAccessMask := TVkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT);
     Barrier.oldLayout     := VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
     Barrier.newLayout     := VK_IMAGE_LAYOUT_GENERAL;

     aCommand.CmdPipelineBarrier( TVkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT),
                                       TVkPipelineStageFlags(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT),
                                       0, 0, nil, 0, nil, 1, @Barrier);


    If NOT assigned(aCommandBuffer) then
    Begin

      aCommand.EndRecording;
      if aCommand.CommandCount > 0 then

        aCommand.ExecuteCommand(  Queue,
                                  TVkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT),
                                  nil,
                                  nil,
                                  True,
                                  True
                                );

      aTransferPool.ReleaseCommand(aCommand);
    End;

end;

constructor TvgDescriptor_PerFrame_StorageImage.Create;
begin
  inherited;
end;

destructor TvgDescriptor_PerFrame_StorageImage.Destroy;
begin
  SetActiveState(False);
  inherited;
end;

function TvgDescriptor_PerFrame_StorageImage.GetWriteDescriptorPayload(  out aBufInfo: TVkDescriptorBufferInfo;
                                                                         out aImgInfo: TVkDescriptorImageInfo): Boolean;
begin
  Result := False;
  aBufInfo := Default(TVkDescriptorBufferInfo);
  aImgInfo := Default(TVkDescriptorImageInfo);

  If not assigned(fStorageImageBuffer) then exit;

  aImgInfo.imageLayout := VK_IMAGE_LAYOUT_GENERAL;
  aImgInfo.imageView   := fStorageImageBuffer.ImageView.Handle;
  aImgInfo.sampler     := VK_NULL_HANDLE;
  Result := True;
end;

function TvgDescriptor_PerFrame_StorageImage.HasPayload: Boolean;
begin
  Result := assigned(fStorageImageBuffer);
end;

Procedure TvgDescriptor_PerFrame_StorageImage.SetDisabled;
begin

  Inherited;

  If assigned(fStorageImageBuffer) then
     FreeAndNil(fStorageImageBuffer);

  fImageLayoutSet:=False;

end;

Procedure TvgDescriptor_PerFrame_StorageImage.SetEnabled;
  Var I      : Integer;
      Linker : TvgLinker;

     CmdPool   : TvgCommandBufferPool;
     Cmd       : TvgCommandBuffer;
     Barrier   : TVkImageMemoryBarrier;

     Device    : TvgLogicalDevice;

     DD        : TvgDescriptor_Data_StorageImage;


    Procedure CreateStorageImage;
       Var SI :  TvgResourceImageBuffer;
    Begin

      fStorageImageBuffer := TvgResourceImageBuffer.Create(nil);
      SI := fStorageImageBuffer;
      SI.Linker      := Linker;
      If Assigned(DescriptorData) then
         SI.Descriptor  := DescriptorData.Descriptor;

      SI.ImageMode   := imStorageImage;

      SI.ImageWidth  := DD.ImageWidth;
      SI.ImageHeight := DD.ImageHeight;

      If  DD.PixelSample then
      Begin
      //  SI.Format            := DD.PixFormat;//IMPORTANT MUST be called AFTER Set ImageMode;
        SI.PixelSampleRadius := DD.PixRadius;
        SI.PixelSamplerON    := DD.PixelSample;
      end;
      SI.Active      := True;

      fUploadNeeded := True;
    End;

begin

  Inherited;

  Device := GetDevice;
  CustomAssert(assigned( Device),'Device Not assigned');

  CustomAssert(assigned( DescriptorData),'Descriptor Data Not assigned');
  CustomAssert(( DescriptorData is TvgDescriptor_Data_StorageImage),'Descriptor Data Not correct type');

  DD:= TvgDescriptor_Data_StorageImage(DescriptorData);
  CustomAssert(Assigned(DescriptorData.Descriptor),                             'Storage image descriptor array not assigned');
  CustomAssert(Assigned(DescriptorData.Descriptor.DescriptorItem),              'Storage image descriptor item not assigned');
  CustomAssert(Assigned(DescriptorData.Descriptor.DescriptorItem.DescriptorSet),'Storage image descriptor set not assigned');

  Linker := DescriptorData.Descriptor.DescriptorItem.DescriptorSet.Linker;
  CustomAssert(Assigned(Linker), 'Storage image linker not assigned');

  DD.VaildateWindowSize;


   If assigned(fStorageImageBuffer) then
      FreeAndNil(fStorageImageBuffer);
   fImageLayoutSet:=False;

   CreateStorageImage;

// ── NEW: transition every image UNDEFINED → GENERAL before first shader use ──
  CmdPool                   := TvgCommandBufferPool.Create(nil);
  CmdPool.Device            := Device;
  CmdPool.QueueFamilyType   := VGT_GRAPHIC;
  CmdPool.QueueCreateFlags  := [CP_RESET_COMMAND_BUFFER];
  CmdPool.SetUpBufferArrays(1);
  CmdPool.Active            := True;
  Try
    Cmd        := CmdPool.AcquireUploadCommand(0);
    Cmd.Active := True;

    Cmd.PrepareForRecording;
    Cmd.BeginRecording;

    Barrier                         := Default(TVkImageMemoryBarrier);
    Barrier.sType                   := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    Barrier.srcAccessMask           := 0;
    Barrier.dstAccessMask           := TVkAccessFlags(VK_ACCESS_SHADER_READ_BIT) or
                                       TVkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT);
    Barrier.oldLayout               := VK_IMAGE_LAYOUT_UNDEFINED;
    Barrier.newLayout               := VK_IMAGE_LAYOUT_GENERAL;
    Barrier.srcQueueFamilyIndex     := VK_QUEUE_FAMILY_IGNORED;
    Barrier.dstQueueFamilyIndex     := VK_QUEUE_FAMILY_IGNORED;
    Barrier.subresourceRange        := DD.fSubRange;       //fix

    Barrier.image := fStorageImageBuffer.Image.Handle;

    Cmd.CmdPipelineBarrier(
        TVkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT),      // nothing before
        TVkPipelineStageFlags(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT) or
        TVkPipelineStageFlags(VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT),   // shader can now use it
        0,
        0, nil,
        0, nil,
        1, @Barrier);

    Cmd.EndRecording;
    Cmd.ExecuteCommand(Device.VulkanDevice.GraphicsQueue,
                       TVkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT),
                       nil, nil,
                       True,   // wait fence
                       True);  // submit
  Finally
    CmdPool.ReleaseAllCommands(True);
    CmdPool.Active := False;
    FreeAndNil(CmdPool);
  End;

end;

procedure TvgDescriptor_PerFrame_StorageImage.UpLoadDescriptorData( aFrameIndex: TvkUint32; aGraphicPool, aTransferPool: TvgCommandBufferPool);

begin
  CustomAssert(Assigned(fStorageImageBuffer), 'Vulkan Storage Image Buffer NOT assigned');
  if not Assigned(fStorageImageBuffer) then
    Exit;   // release-build safety net: CustomAssert no-ops outside DEBUG/design-time

  if not ((DF_UP in GetDataFlow) or (DF_DOWN in GetDataFlow)) then
    Exit;

  if not fUploadNeeded then
    Exit;

  if not Active then
    SetActiveState(True);

  fUploadNeeded := False;

end;

{ TvgPushConstant_Data }

procedure TvgPushConstant_Data<T>.Assign(Source: TPersistent);
  Var PC : TvgPushConstant_Data<T>;
       I,J : Integer;
begin
  inherited;

  If assigned(Source) and (source is  TvgPushConstant_Data<T>)  then
  Begin
    PC := TvgPushConstant_Data<T>(Source);
    If assigned(PC) then
    Begin
      PC.FrameCount :=  PC.FrameCount;

      For J:=0 to length(PC.fDataArray)-1 do
      Begin
        for I := 0 to PC.fDataArray[J].ItemCount-1 do
            self.Items[I] := PC.Items[I];
           //no need to assigne data

      End;
    End;
  End;
end;

constructor TvgPushConstant_Data<T>.Create(AOwner: TComponent);
begin
  inherited;

 // Name := 'Matrix4x4';
end;

destructor TvgPushConstant_Data<T>.Destroy;
  Var I:Integer;
begin
  //SetLength(fMatrix4x4,0);
  For I:=0 to Length(fDataArray)-1 do
    fDataArray[I].Clear;
  SetLength(fDataArray, 0);
  inherited;
end;

function TvgPushConstant_Data<T>.GetDataPointer: Pointer;
begin
  Result := fDataArray[fCurrentFrameIndex].GetDataPointer;
end;

function TvgPushConstant_Data<T>.GetDataStride: TVkUInt32;
begin
  Result := fDataArray[fCurrentFrameIndex].GetDataStride;  //OK important as only want size of frame related record
end;

function TvgPushConstant_Data<T>.GetItem(Index: Integer): T;
begin
 Result := fDataArray[fCurrentFrameIndex][Index];
end;

class function TvgPushConstant_Data<T>.GetPropertyName: String;
begin
  Result := 'PushConstant_Data';
end;

Function TvgPushConstant_Data<T>.SetDisabled:Boolean;
  Var I:Integer;
begin
  Result := False;


  For I:=0 to Length(fDataArray)-1 do
    fDataArray[I].Clear;

  Result := Inherited;
  CustomAssert(Result,System.SysUtils.Format('%S : Fail to set State %d',[self.ClassName, ord(Result)]),self);
end;

Function TvgPushConstant_Data<T>.SetEnabled:Boolean;
  Var I:Integer;
begin
  inherited;  //important
  Result := True;

  If fFrameCount=0 then
     fFrameCount := MaxFramesInFlight;

  SetLength(fDataArray, fFrameCount);            //one slot per frame-in-flight - was never sized before, so Items[] always raised "Index out of range"
  For I:=0 to Length(fDataArray)-1 do
    fDataArray[I].SetItemCapacity(1) ;            //one struct per frame - was wrongly using fFrameCount as the item count

end;

procedure TvgPushConstant_Data<T>.SetFrameCount(const Value: TvkUint32);
  Var I:Integer;
begin
  inherited;

  SetLength(fDataArray, Value);                   //resize to match the new frame count
  For I:=0 to Length(fDataArray)-1 do
    fDataArray[I].SetItemCapacity(1) ;             //one struct per frame - was wrongly using Value (frame count) as the item count
end;

procedure TvgPushConstant_Data<T>.SetItem(Index: Integer; const Value: T);
begin
  fDataArray[fCurrentFrameIndex].Items[Index] := Value  ;
end;


{ TvgPushConstant_2UI }

function TvgPushConstant_2UI.GetValue: TvgVector2I;
begin
  Result := Items[0];
end;

constructor TvgPushConstant_2UI.Create(AOwner: TComponent);
begin
  inherited;

  ShaderFlags := [SS_VERTEX_BIT];

end;

function TvgPushConstant_2UI.GetGLSLDeclaration(  const aBlockName: String): String;
begin

 Result :=
    'layout(push_constant) uniform ' + GetPropertyName +   sLineBreak +
    '{' + sLineBreak +
    '    ivec2 value;' + sLineBreak +
    '} ' + aBlockName + ';' + sLineBreak;

end;

class function TvgPushConstant_2UI.GetPropertyName: String;
begin
  Result := 'PushConstant_2UI';
end;

procedure TvgPushConstant_2UI.SetupData(FrameIndex: TvkUint32; Linker: TvgLinker);
  Var W,H:Cardinal;
begin
  inherited;

  If assigned(Linker) and
     assigned(Linker.SwapChain) then

  Begin
    W:= Linker.SwapChain.ImageWidth;
    H:= Linker.SwapChain.ImageHeight;
    SetValues(W,H);
  End;

end;

procedure TvgPushConstant_2UI.SetValue(const Value: TvgVector2I);
begin
  Items[0] := Value;
end;

procedure TvgPushConstant_2UI.SetValues(const aX, aY: Cardinal);
  Var V : TvgVector2I;
begin
  V.X := aX;
  V.Y := aY;
  Items[0] := V;
end;


{ TvgDescriptor_Data_StorageImage }

constructor TvgDescriptor_Data_StorageImage.Create;
begin
  inherited;
  fPixelSampleRadius := psr_1x1;
  fSubRange := Default(TVkImageSubresourceRange);
  fSubRange.aspectMask := TVkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT);
  fSubRange.levelCount := 1;
  fSubRange.layerCount := 1;
  fWindowSync          := True;
end;

destructor TvgDescriptor_Data_StorageImage.Destroy;
begin

  inherited;
end;

function TvgDescriptor_Data_StorageImage.GetGLSLBaseTypeName: String;
begin
  // Only 2D storage images are currently supported (fImageProps.ImageType
  // is hardcoded to VK_IMAGE_TYPE_2D in SetEnabled). Extend this if/when
  // 1D/3D/cube storage images are added.
  Result := 'image2D';
end;

function TvgDescriptor_Data_StorageImage.GetOrAddFrameDataObject(  aFrameIndex: Integer): TvgDescriptorPerFrameData;
Var DI: TvgDescriptor_PerFrame_StorageImage;
begin
  If (aFrameIndex>=0) and (aFrameIndex<Length(fFrameData)) then
  Begin
    If Not assigned(fFrameData[aFrameIndex]) then
    Begin
       DI := TvgDescriptor_PerFrame_StorageImage.Create;
       DI.fDescriptorData := Self;
       fFrameData[aFrameIndex] := DI;
       Result := DI;
    End else
      Result := fFrameData[aFrameIndex];
  End else
    Result := Nil;
end;

function TvgDescriptor_Data_StorageImage.GetPixelData(aFrameIndex: TvkUint32; Shift: TShiftState; X, Y: Integer; out Data: TvgPixelData): Boolean;
var
  PS: TvgPixelSampler;
begin
  Result := False;
  Data := Default(TvgPixelData);
  if not fPixelSamplingON then
    Exit;

  PS := GetPixelSampler(aFrameIndex);
  if Assigned(PS) and PS.SamplePixel(X, Y) then
  Begin
    Data   := PS.PixelData;
    Result := True;
  end;
end;

function TvgDescriptor_Data_StorageImage.GetPixelSampler(  FrameIndex: Integer): TvgPixelSampler;
var
  DF: TvgDescriptorPerFrameData;
  FrameData: TvgDescriptor_PerFrame_StorageImage;
begin
  Result := Nil;
  If not (Active) then exit;

  DF := GetFrameData(FrameIndex);
  if DF is TvgDescriptor_PerFrame_StorageImage then
  begin
    FrameData := TvgDescriptor_PerFrame_StorageImage(DF);
    if Assigned(FrameData.fStorageImageBuffer) then
      Result := FrameData.fStorageImageBuffer.PixelSampler;
  end;
end;


procedure TvgDescriptor_Data_StorageImage.SetDisabled;
  Var I,L:Integer;
begin
  inherited;

  L:=Length(fFrameData);
  If L>0 then
    For I:=0 to L-1 do
     If assigned(fFRameData[I]) then
       fFRameData[I].Active := False;
end;

procedure TvgDescriptor_Data_StorageImage.SetEnabled;
  Var I,L:Integer;
begin
  VaildateWindowSize; //stay here

  inherited;

end;

procedure TvgDescriptor_Data_StorageImage.SetClearColor(R, G, B: Single; A:Single);
begin
  fClearCol.float32[0] := R;
  fClearCol.float32[1] := G;
  fClearCol.float32[2] := B;
  fClearCol.float32[3] := A;
end;

procedure TvgDescriptor_Data_StorageImage.SetfPixelSamplingON( const Value: Boolean);
begin
  fPixelSamplingON := Value;
end;

procedure TvgDescriptor_Data_StorageImage.SetImageHeight(  const Value: TvkUint32);
begin
  If fImageHeight = Value then exit;
  SetActiveState(False);
  fImageHeight := Value;
end;

procedure TvgDescriptor_Data_StorageImage.SetImageWidth(const Value: TvkUint32);
Begin
  If fImageHeight = Value then exit;
  SetActiveState(False);
  fImageWidth := Value;
end;

procedure TvgDescriptor_Data_StorageImage.SetPixelSampleRadius(  const Value: TvgPixelSampleRadius);
begin
  fPixelSampleRadius := Value;
end;


procedure TvgDescriptor_Data_StorageImage.SetWindowSync(const Value: Boolean);
begin
  If  fWindowSync = Value then exit;
  SetActiveState(False)  ;
  fWindowSync := Value;
end;

procedure TvgDescriptor_Data_StorageImage.VaildateWindowSize;
  Var Linker:TvgLinker;
begin
    If NOT fWindowSync then exit;

    If assigned(fDescriptor) and
       assigned(fDescriptor.DescriptorItem) and
       assigned(fDescriptor.DescriptorItem.DescriptorSet) and
       assigned(fDescriptor.DescriptorItem.DescriptorSet.Linker) and
       assigned(fDescriptor.DescriptorItem.DescriptorSet.Linker.SwapChain) then
    Begin
       Linker :=  fDescriptor.DescriptorItem.DescriptorSet.Linker;

       fImageWidth  := Linker.SwapChain.ImageWidth;
       fImageHeight := Linker.SwapChain.ImageHeight;

       if (Linker.RenderTarget = RT_FRAME) and ( Linker.FrameResolution<>1) then
       begin
         fImageWidth  := fImageWidth  * Linker.FrameResolution;         //check
         fImageHeight := fImageHeight * Linker.FrameResolution;         //check
       End;

    End;

end;

{ TvgDescriptorArray_UniformBuffer<T> }

function TvgDescriptorArray_UniformBuffer<T>.AddUniformBuffer(aDescriptorData: TvgDescriptor_Data_UniformBuffer<T>):Integer;
  Var L:Integer;
begin
  Result := -1;

  If not assigned(aDescriptorData) then
     aDescriptorData:= TvgDescriptor_Data_UniformBuffer<T>.Create;

  If AddDescriptorDataToArray(aDescriptorData) then
    Result := IndexOfDescriptorData(aDescriptorData);

end;

constructor TvgDescriptorArray_UniformBuffer<T>.Create(AOwner: TComponent);
begin
  inherited;

  fDescriptorType    := VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;

  fStageFlags         :=  TVkShaderStageFlags(VK_SHADER_STAGE_VERTEX_BIT) or
                          TVkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT);

end;

function TvgDescriptorArray_UniformBuffer<T>.GetDescriptor_Data_UBO( Index: Integer): TvgDescriptor_Data_UniformBuffer<T>;
begin
  If (index>=0) and (index<Length(fDescriptorArray)) and (fDescriptorArray[Index] is TvgDescriptor_Data_UniformBuffer<T>) then
     Result := TvgDescriptor_Data_UniformBuffer<T>(fDescriptorArray[Index])
  else
     Result := Nil;
end;

function TvgDescriptorArray_UniformBuffer<T>.GetGLSLDeclarationBody: String;
var
  ElementType: String;
  ElementTypeInfo: PTypeInfo;
Begin
  ElementTypeInfo := TypeInfo(T);
  ElementType := GetGLSLTypeNameForPascalType(ElementTypeInfo.Name);
  if SameText(ElementType, 'vec3') or SameText(ElementType, 'ivec3') or
     SameText(ElementType, 'uvec3') or SameText(ElementType, 'dvec3') then
    raise EArgumentException.CreateFmt(
      '%s requires a padded std140 GPU type; SizeOf(T) is not layout-compatible',
      [ClassName]);

  Result := 'uniform ' + Name + 'Block {' + sLineBreak +
            '    ' + ElementType + ' value;' + sLineBreak +
            '}';
end;

function TvgDescriptorArray_UniformBuffer<T>.GetGLSLLayoutQualifier: String;
begin
  Result := 'std140';
end;

function TvgDescriptorArray_UniformBuffer<T>.GetGLSLValueExpression(const aArrayIndexExpr : String = '';  aIndexExpr: String = ''): String;
begin
  Result := Name + '.value';
end;

function TvgDescriptorArray_UniformBuffer<T>.RemoveUBO( aDD_UBO: TvgDescriptor_Data_UniformBuffer<T>): Boolean;

begin
  Result := RemoveAndFreeDescriptor(aDD_UBO);
end;

{ TvgDescriptor_Data_UniformBuffer<T> }

constructor TvgDescriptor_Data_UniformBuffer<T>.Create;
begin
  Inherited;

  fBufferUsageFlags := TVkBufferUsageFlags(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT) or
                       TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_DST_BIT);

  fBufferSharingMode:= VK_SHARING_MODE_EXCLUSIVE;

end;

function TvgDescriptor_Data_UniformBuffer<T>.GetUBOFrame( Index: Integer): TvgDescriptor_PerFrame_UniformBuffer<T>;
var
  DF: TvgDescriptorPerFrameData;
begin
  Result := nil;
  DF := GetFrameData(Index);
  if DF is TvgDescriptor_PerFrame_UniformBuffer<T> then
    Result := TvgDescriptor_PerFrame_UniformBuffer<T>(DF);
end;

function TvgDescriptor_Data_UniformBuffer<T>.GetGLSLBaseTypeName: String;
  Var aType:pTypeInfo ;
begin
   aType:= TypeInfo(T) ;
   Result := GetGLSLTypeNameForPascalType(aType.Name);
end;

function TvgDescriptor_Data_UniformBuffer<T>.GetOrAddFrameDataObject(aFrameIndex:Integer): TvgDescriptorPerFrameData;
  Var DD: TvgDescriptor_PerFrame_UniformBuffer<T>;
begin
  If (aFrameIndex>=0) and (aFrameIndex<Length(fFrameData)) then
  Begin

    If Not assigned(fFrameData[aFrameIndex]) then
    Begin
       DD:= TvgDescriptor_PerFrame_UniformBuffer<T>.Create;
       DD.fDescriptorData      := Self;
       fFrameData[aFrameIndex] := DD;

     //  fFrameData[aFrameIndex].fDescriptorData := Self;
       //fix
      Result := DD;
    End else
      Result:=  fFrameData[aFrameIndex];

  End else
    Result := Nil;
end;

procedure TvgDescriptor_Data_UniformBuffer<T>.SetDisabled;
  Var I,L:Integer;
begin
  inherited;

  L:=Length(fFrameData);
  If L>0 then
    For I:=0 to L-1 do
      If assigned(fFRameData[I]) then
        fFRameData[I].Active := False;

end;

procedure TvgDescriptor_Data_UniformBuffer<T>.SetEnabled;
  Var I,L:Integer;
begin
  inherited;

  L:=Length(fFrameData);
  If L>0 then
    For I:=0 to L-1 do
      If assigned(fFRameData[I]) then
        fFRameData[I].Active := True;

end;

procedure TvgDescriptor_Data_UniformBuffer<T>.SetFrameCount(aCount: Integer);
  Var L,I:Integer;
begin

  If  (aCount<0) or (aCount > MaxFramesInFlight) then exit;
  L:=Length(fFrameData);

  If L=aCount then exit
  else
  If (aCount>L) then
  Begin
    SetLength(fFrameData, aCount);
    For I:=0 to aCount-1 do
        GetOrAddFrameDataObject(I);
  end else
  //aCount<L
  Begin
    For I:= aCount to L-1 do
       If assigned(fFrameData[I]) then
          FreeAndNil(fFrameData[I]);

    SetLength(fFrameData, aCount);
  End;

end;

{ TvgDescriptor_PerFrame_Texture }

function TvgDescriptor_PerFrame_Texture.LoadTexture(aFileStream: TStream;  var aGLSLIndex: TvkUint32): Boolean;
begin

  Result := False;
  CustomAssert(assigned(aFileStream),'File Stream NOT assigned')  ;
  CustomAssert(aFileStream.Size<>0,'Data Size is Zero')  ;

  fTextureSource.FileName:='';

  If not assigned( fTextureSource.Stream) then
     fTextureSource.Stream:= TMemorySTream.Create;

  fTextureSource.Stream.LoadFromStream(aFileStream);

  fTextureSource.DataOK  := InspectTexture(fTextureSource.Stream,fTextureSource.Info);

  If not fTextureSource.DataOK then
  Begin
    CustomAssert((fTextureSource.DataOK),SysUtils.Format('Data in FileStream NOT a valid texture format %s',[GetEnumName(TypeInfo(TTextureFormatKind),Ord(fTextureSource.Info.FormatKind))]));
    FreeAndNil(fTextureSource.Stream);
    fTextureSource:=Default(TvgTextureSource);
    fUploadNeeded :=False;

  End else
  Begin

    If assigned(fDescriptorData) then
       aGLSLIndex := fDescriptorData.GLSLIndex;    //check
    fTextureSource.DataSize:=   fTextureSource.Stream.Size;
    fUploadNeeded:=True;
    Result := True;
  End;
end;

function TvgDescriptor_PerFrame_Texture.LoadTexture(aFileName: String;  var aGLSLIndex: TvkUint32): Boolean;
  Var F:String;
      FS:TFileStream;
begin
  Result := False;

  F:= Trim(aFileName) ;
  fTextureSource.DataOK   := False;
  fTextureSource.DataSize := 0;
  CustomAssert((F<>''),'File Name is Blank');

  if not FileExists(F) then
  Begin
    F := TextureFolderPath + F;
    if not FileExists(F) then
      Exit;
  end;

  fTextureSource.FileName := F;

  FS := TFileStream.Create(fTextureSource.FileName, fmOpenRead or fmShareDenyWrite);

  If FS.Size=0 then
  Begin
    FreeAndNil(FS);
    exit;
  End;

  Result := LoadTexture(FS, aGLSLIndex);

  FreeAndNil(FS);
end;

procedure TvgDescriptor_PerFrame_Texture.ClearDataOnGPU(aIndex:Integer; aTransferPool: TvgCommandBufferPool; aCommandBuffer: TvgCommandBuffer = nil);
begin


end;

constructor TvgDescriptor_PerFrame_Texture.Create;
begin
  Inherited;

  fTextureSource := Default(TvgTextureSource);



end;

destructor TvgDescriptor_PerFrame_Texture.Destroy;
begin
  SetActiveState(False) ;

  If assigned(fTextureSource.Stream) then
     FreeAndNil(fTextureSource.Stream );

  inherited;
end;

function TvgDescriptor_PerFrame_Texture.GetWriteDescriptorPayload( out aBufInfo: TVkDescriptorBufferInfo;
                                                                   out aImgInfo: TVkDescriptorImageInfo): Boolean;
begin
  Result := False;
  aBufInfo:= Default(TVkDescriptorBufferInfo);
  aImgInfo:= Default(TVkDescriptorImageInfo);

  CustomAssert(assigned(fDescriptorData),'Owner DescriptorData NOT assigned');

  // NOT an error condition : a frame object can legitimately be waiting for
  // its upload (Finish) or be an empty slot that shares another frame's
  // texture. Returning False leaves the caller with a zeroed image info so
  // it can skip the write instead of publishing invalid handles.
  If not IsWriteReady then exit;

  aImgInfo.imageLayout := fVulkanTexture.ImageLayout;
  aImgInfo.imageView   := fVulkanTexture.ImageView.Handle;
  aImgInfo.sampler     := fVulkanTexture.Sampler.Handle;

  Result := True;
end;

function TvgDescriptor_PerFrame_Texture.HasTextureSource: Boolean;
begin
  Result := fTextureSource.DataOK and
            (fTextureSource.DataSize > 0) and
            assigned(fTextureSource.Stream);
end;

function TvgDescriptor_PerFrame_Texture.HasPayload: Boolean;
begin
  // "This object owns real texture content."  The source data is included so
  // the owning TvgDescriptorData can resolve to the single loaded frame object
  // BEFORE activation creates the TpvVulkanTexture.
  Result := assigned(fVulkanTexture) or HasTextureSource;
end;

function TvgDescriptor_PerFrame_Texture.IsWriteReady: Boolean;
begin
  // A texture may only be written into a descriptor set once it has been
  // built (LoadFromImage) AND uploaded (Finish + Sampler bound).
  Result := assigned(fVulkanTexture) and
            assigned(fVulkanTexture.ImageView) and
            assigned(fVulkanTexture.Sampler);
end;

procedure TvgDescriptor_PerFrame_Texture.InvalidateForUpload;
begin
  // Deliberately does NOT deactivate. The texture is built from the loaded
  // source, not from per frame data, so tearing it down here left an active
  // object holding a nil / half built TpvVulkanTexture - which is exactly what
  // produced invalid ImageLayout, ImageView and Sampler values at write time.
  // This also keeps a SINGLE shared texture alive for every frame that uses it.
end;

procedure TvgDescriptor_PerFrame_Texture.SetDisabled;
begin
  inherited;

  If assigned(fVulkanTexture) then
    FreeAndNil(fVulkanTexture);

end;

procedure TvgDescriptor_PerFrame_Texture.SetEnabled;
  Var Sampler:TvgSampler;
      Device :TvgLogicalDevice;

begin
  inherited;

  Device := GetDevice;

  CustomAssert(Assigned(Device),'Device NOT assigned');
  CustomAssert(Assigned(Device.VulkanDevice),'Vulkan Device NOT assigned');

  If fTextureSource.DataOK and (fTextureSource.DataSize>0) and assigned(fTextureSource.Stream) then
  Begin
      fVulkanTexture := TpvVulkanTexture.Create(Device.VulkanDevice);

      fVulkanTexture.LoadFromImage(fTextureSource.Stream,
                                   fTextureSource.Info.HasMipMaps,//   True,
                                   fTextureSource.Info.IsSRGB);   //   False,

      fUploadNeeded := True;

  end;

end;

procedure TvgDescriptor_PerFrame_Texture.UpLoadDescriptorData( aFrameIndex: TvkUint32; aGraphicPool, aTransferPool: TvgCommandBufferPool);

  Var //J,I : Integer;
      GQ,
      TQ: TpvVulkanQueue;
      GV,
      TV: TvgCommandBuffer;
      Sampler:TvgSampler;
      VS:TpvVulkanSampler;
begin

  // An empty frame slot (its texture lives in the shared frame object) has
  // nothing to upload - this is a normal state, not a failure.
  If not assigned(fVulkanTexture) then exit;
  If not UploadNeeded then exit;

  CustomAssert(assigned( aGraphicPool   ),'Graphic Pool not assigned');
  CustomAssert(assigned( aTransferPool   ),'Transfer Pool not assigned');

  CustomAssert(assigned(fDescriptorData),'Descriptor Data not assigned');
  CustomAssert((fDescriptorData is TvgDescriptor_Data_Texture),'Descriptor Data incorrect type');
  CustOmAssert(assigned(TvgDescriptor_Data_Texture(fDescriptorData).Sampler),'Sampler not assigned');
  Sampler:= TvgDescriptor_Data_Texture(fDescriptorData).Sampler;

  CustomAssert((Sampler.State = vgcsActive),'Sampler NOT active');

  Try
   // D := fDescriptorItem.Device.VulkanDevice;

    GQ := aGraphicPool.Queue[-1] ;//   D.GraphicsQueue;
     CustomAssert(assigned(GQ), 'GQ Queue not assigned');
    TQ := aTransferPool.Queue[-1];
     CustomAssert(assigned(TQ), 'TQ Queue not assigned');

    GV := aGraphicPool.AcquireUploadCommand(0);//  RequestCommand(0,CB_PRIMARY,[BU_SIMULTANEOUS_USE_BIT]);
     CustomAssert(assigned(GV), 'GV Command buffer not assigned');

    TV := aTransferPool.AcquireUploadCommand(0);//  RequestCommand(0,CB_PRIMARY,[BU_SIMULTANEOUS_USE_BIT]);
     CustomAssert(assigned(TV), 'TV Command buffer not assigned');

     CustomAssert(GV.BufferState in [cbsINITIAL, cbsRECORDING],
             'GV Command buffer not in INITIAL state before TpvVulkanTexture.Finish');

     CustomAssert(TV.BufferState in [cbsINITIAL, cbsRECORDING],
             'TV Command buffer not in INITIAL state before TpvVulkanTexture.Finish');


    // The sampler is deliberately taken from slot 0 : ONE sampler serves every
    // frame, exactly like the shared texture it is bound to.
    VS := Sampler.VulkanSampler[0];
    CustomAssert(assigned(VS),'Vulkan Sampler NOT created');

    If fVulkanTexture.Sampler <> VS then
      fVulkanTexture.Sampler := VS;


     fVulkanTexture.Finish (GQ,
                            GV.VulkanCommandBuffer,   //MUST BE ABLE TO RESET
                            GV.BufferFence,
                            TQ,
                            TV.VulkanCommandBuffer,  //MUST BE ABLE TO RESET
                            TV.BufferFence);


    fUploadNeeded := False;

  Finally
       aGraphicPool.ReleaseCommand(GV);
       aTransferPool.ReleaseCommand(TV);
  End;

end;


{ TvgDescriptor_Data_StorageBuffer<T> }

constructor TvgDescriptor_Data_StorageBuffer<T>.Create;
begin
  Inherited;

  fBufferUsageFlags :=
      TVkBufferUsageFlags(VK_BUFFER_USAGE_STORAGE_BUFFER_BIT) or
      TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_DST_BIT) or
      TVkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_SRC_BIT);

  fBufferSharingMode := VK_SHARING_MODE_EXCLUSIVE;

  fElementCount        := 0;
  fElementSub          := 0;
  fElementCountChanged := False;

  fElementSamplingON   := True;
  fSampleRadius        := psr_3x3;

end;

destructor TvgDescriptor_Data_StorageBuffer<T>.Destroy;
begin
  SetActiveState(False) ;


  inherited;
end;

function TvgDescriptor_Data_StorageBuffer<T>.GetElementData(  aFrameIndex: TvkUint32; ElementIndex: Integer; out Data: Pointer;
                                        out DataSize: TvkUint32): Boolean;
var
  ByteCount : TvkUint32;
begin
  Result   := False;
  Data     := nil;
  DataSize := 0;

  if not assigned(fElementSampler) then exit;

  RefreshSamplerSourceBuffers;
  fElementSampler.CurrentFrame := aFrameIndex;

  if not fElementSampler.SampleElement(ElementIndex)then exit;

  Result := fElementSampler.GetElementBytes(ElementIndex, Data, ByteCount);
  if Result then
    DataSize := ByteCount;
end;

function TvgDescriptor_Data_StorageBuffer<T>.GetElementData2D(aFrameIndex:TvkUint32; X, Y:Integer;
                                                                out Data:Pointer; out DataSize:TvkUint32): Boolean;
var
  ByteCount : TvkUint32;
begin
  Result   := False;
  Data     := nil;
  DataSize := 0;

  if not assigned(fElementSampler) then exit;

  RefreshSamplerSourceBuffers;
  fElementSampler.CurrentFrame := aFrameIndex;

  if not fElementSampler.SampleElementXY(X, Y) then exit;

  Result := fElementSampler.GetElementBytesXY(0, 0, Data, ByteCount);
  if Result then
    DataSize := ByteCount;
end;

function TvgDescriptor_Data_StorageBuffer<T>.GetGLSLBaseTypeName: String;
  Var aType:pTypeInfo;
begin
  aType:= TypeInfo(T);
  Result := GetGLSLTypeNameForPascalType(aType.name);
end;

function TvgDescriptor_Data_StorageBuffer<T>.GetOrAddFrameDataObject( aFrameIndex: Integer): TvgDescriptorPerFrameData;
  Var DD: TvgDescriptor_PerFrame_StorageBuffer<T>;
begin
  If (aFrameIndex>=0) and (aFrameIndex<Length(fFrameData)) then
  Begin

    If Not assigned(fFrameData[aFrameIndex]) then
    Begin
       DD:= TvgDescriptor_PerFrame_StorageBuffer<T>.Create;
       DD.fDescriptorData      := Self;
       fFrameData[aFrameIndex] := DD;

     //  fFrameData[aFrameIndex].fDescriptorData := Self;
       //fix
      Result := DD;
    End else
      Result:=  fFrameData[aFrameIndex];

  End else
    Result := Nil;
end;

function TvgDescriptor_Data_StorageBuffer<T>.GetStorageBufferFrame( Index: Integer): TvgDescriptor_PerFrame_StorageBuffer<T>;
var
  DF: TvgDescriptorPerFrameData;
begin
  Result := nil;
  DF := GetFrameData(Index);
  if DF is TvgDescriptor_PerFrame_StorageBuffer<T> then
    Result := TvgDescriptor_PerFrame_StorageBuffer<T>(DF);

end;
procedure TvgDescriptor_Data_StorageBuffer<T>.RefreshSamplerSourceBuffers;
var
  I  : Integer;
  DF : TvgDescriptor_PerFrame_StorageBuffer<T>;
begin
  if not assigned(fElementSampler) then exit;
  for I := 0 to Length(fFrameData) - 1 do
  begin
    DF := TvgDescriptor_PerFrame_StorageBuffer<T>(GetFrameData(I));
    if assigned(DF) then
      fElementSampler.SourceBuffer[I] := DF.fVulkanBuffer;
  end;
end;

procedure TvgDescriptor_Data_StorageBuffer<T>.SetElementCount( const Value: TvkUint32);
begin

  if fElementCount = Value then exit;
  SetActiveState(False);
  fElementCount := Value;

end;

procedure TvgDescriptor_Data_StorageBuffer<T>.SetElementSamplingON(const Value: Boolean);
begin
  If fElementSamplingON = Value then exit;
  SetActiveState(False);

  fElementSamplingON := Value;


end;

Procedure TvgDescriptor_Data_StorageBuffer<T>.SetEnabled;
  Var I:Integer;
      DF :TvgDescriptor_PerFrame_StorageBuffer<T> ;
begin
  VaildateWindowSize;    //if WindowSync then

  inherited;   // activates fFrameData[] children, creating each fVulkanBuffer

  for I := 0 to Length(fFrameData) - 1 do
  begin
    If assigned(fFrameData[I]) and (fFrameData[I] is TvgDescriptor_PerFrame_StorageBuffer<T>) then
    Begin
      DF := TvgDescriptor_PerFrame_StorageBuffer<T>(fFrameData[I]);
      if assigned(DF) then
        fElementSampler.SourceBuffer[I] := DF.fVulkanBuffer;
    End;
  end;

  If assigned(fElementSampler) then
  Begin
    fElementSampler.SamplingDimension := fSamplingDimension;
    fElementSampler.SetActiveState(True);
  End;

end;

Procedure TvgDescriptor_Data_StorageBuffer<T>.SetDisabled;

begin
  inherited;   // deactivates fFrameData[] children, freeing each fVulkanBuffer

  if assigned(fElementSampler) then
    fElementSampler.SetActiveState(False);   // deactivate before children's buffers go away


end;

procedure TvgDescriptor_Data_StorageBuffer<T>.SetFrameCount(aCount: Integer);
  Var L,I:Integer;
begin

  If  (aCount<0) or (aCount > MaxFramesInFlight) then exit;
  L:=Length(fFrameData);

  If L=aCount then
    exit
  else
  If (aCount>L) then
  Begin
    SetLength(fFrameData, aCount);
    For I:=0 to aCount-1 do
        GetOrAddFrameDataObject(I);
  end else
  Begin
    For I:= aCount to L-1 do
       If assigned(fFrameData[I]) then
          FreeAndNil(fFrameData[I]);

    SetLength(fFrameData, aCount);
  End;

end;

procedure TvgDescriptor_Data_StorageBuffer<T>.SetSamplingDimension(  const Value: TvgElementSamplingDimension);
begin
if fSamplingDimension = Value then exit;
  SetActiveState(False);
  fSamplingDimension := Value;

end;

procedure TvgDescriptor_Data_StorageBuffer<T>.SetStrideWidth(  const Value: TvkUint32);
begin
  if fElementSub = Value then exit;
  SetActiveState(False);
  fElementSub := Value;
end;

procedure TvgDescriptor_Data_StorageBuffer<T>.SetWindowSync(  const Value: Boolean);
begin
  If  fWindowSync = Value then exit;
  SetActiveState(False) ;

  fWindowSync := Value;

  If fWindowSync then
     fSamplingDimension :=  esdGrid2D
  else
     fSamplingDimension :=  esdLinear1D;
end;

procedure TvgDescriptor_Data_StorageBuffer<T>.VaildateWindowSize;
  Var Linker : TvgLinker;
      I:Integer;
      DF : TvgDescriptor_PerFrame_StorageBuffer<T>;
Begin

    If fWindowSync and
       assigned(fDescriptor) and
       assigned(fDescriptor.DescriptorItem) and
       assigned(fDescriptor.DescriptorItem.DescriptorSet) and
       assigned(fDescriptor.DescriptorItem.DescriptorSet.Linker) and
       assigned(fDescriptor.DescriptorItem.DescriptorSet.Linker.SwapChain) then
    Begin
       Linker :=  fDescriptor.DescriptorItem.DescriptorSet.Linker;

       fElementCount :=  Linker.SwapChain.ImageWidth * Linker.SwapChain.ImageHeight;
       fElementSub   :=  Linker.SwapChain.ImageWidth;

       if (Linker.RenderTarget = RT_FRAME) and ( Linker.FrameResolution<>1) then
       begin
         fElementCount  := fElementCount  * Linker.FrameResolution * Linker.FrameResolution;         //check
         fElementSub    := fElementSub * Linker.FrameResolution;         //check
       End;

    End;


    if fElementSamplingON and (fElementCount > 0) then
    begin
      if not assigned(fElementSampler) then
        fElementSampler := TvgElementSampler.Create
      else
        fElementSampler.SetActiveState(False);

      fElementSampler.Device            := GetDevice;
      fElementSampler.FrameCount        := Length(fFrameData);
      fElementSampler.ElementStride     := SizeOf(T);
      fElementSampler.ElementCount      := fElementCount;
      fElementSampler.SampleRadius      := fSampleRadius;
      fElementSampler.SamplingDimension := fSamplingDimension;
      fElementSampler.StrideWidth       := fElementSub;

    end;


end;

{ TvgDescriptorArray_StorageBuffer<T> }

function TvgDescriptorArray_StorageBuffer<T>.AddStorageBuffer(  aData_SB: TvgDescriptor_Data_StorageBuffer<T>): Integer;
  Var L:Integer;
begin
  Result := -1;
  If not assigned(aData_SB) then
     aData_SB := TvgDescriptor_Data_StorageBuffer<T>.Create;

  If AddDescriptorDataToArray(aData_SB) then
    Result := IndexOfDescriptorData(aData_SB);
end;

constructor TvgDescriptorArray_StorageBuffer<T>.Create(AOwner: TComponent);
begin
  inherited;

  fDescriptorType := VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;

  BindingMode     := vgdbmFixedArray;
  BindingCount    := 64;  //MAX_SLOTS;          // e.g. 64
  PartiallyBound  := True;               // dioPartiallyBound
  UpdateAfterBind := True;              // dioUpdateAfterBind  (optional)


  fStageFlags     :=  TVkShaderStageFlags(VK_SHADER_STAGE_VERTEX_BIT) or
                      TVkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT);

  FrameCount      := MaxFramesInFlight;


end;

function TvgDescriptorArray_StorageBuffer<T>.GetDescriptor_Data_StorageBuffer( Index: Integer): TvgDescriptor_Data_StorageBuffer<T>;
begin
  If (index>=0) and (index<Length(fDescriptorArray)) and (fDescriptorArray[Index] is TvgDescriptor_Data_StorageBuffer<T>) then
     Result := TvgDescriptor_Data_StorageBuffer<T>(fDescriptorArray[Index])
  else
     Result := Nil;
end;

function TvgDescriptorArray_StorageBuffer<T>.GetGLSLDeclarationBody: String;
var
  ElementType: String;
  ElementTypeInfo: PTypeInfo;
begin
  ElementTypeInfo := TypeInfo(T);
  ElementType := GetGLSLTypeNameForPascalType(ElementTypeInfo.Name);

  if SameText(ElementType, 'vec3') or
     SameText(ElementType, 'ivec3') or
     SameText(ElementType, 'uvec3') or
     SameText(ElementType, 'dvec3') then
    raise EArgumentException.CreateFmt(  '%s requires a padded std430 GPU type; SizeOf(T) is not layout-compatible', [ClassName]);

  Result := 'buffer ' + Name + 'Block {' + sLineBreak +
            '    ' + ElementType + ' values[];' + sLineBreak +
            '}';
end;

function TvgDescriptorArray_StorageBuffer<T>.GetGLSLLayoutQualifier: String;
begin
  Result := 'std430';
end;

function TvgDescriptorArray_StorageBuffer<T>.GetGLSLValueExpression(const aArrayIndexExpr : String = '';  aIndexExpr: String = ''): String;
begin
  if aIndexExpr = '' then
      Result := Name + '.values'
  else
  Begin
      case fBindingMode of
        vgdbmSingle       : Result := Name + '.values[' + aIndexExpr + ']';
        vgdbmFixedArray   : Result := Name + '[nonuniformEXT('+aArrayIndexExpr+')].values[' + aIndexExpr + ']';
        vgdbmVariableArray,
        vgdbmRuntimeArray : Result := Name + '[nonuniformEXT('+aArrayIndexExpr+')].values[' + aIndexExpr + ']';
      else
         Result := Name + '.values[' + aIndexExpr + ']';
      end;
  End;
end;

function TvgDescriptorArray_StorageBuffer<T>.RemoveStorageBuffer(  aData_SB: TvgDescriptor_Data_StorageBuffer<T>): Boolean;
begin
  Result := RemoveAndFreeDescriptor(aData_SB);
end;

{ TvgDescriptorArray_StorageImage }

function TvgDescriptorArray_StorageImage.AddStorageImage(  aStorageImageData: TvgDescriptor_Data_StorageImage): Integer;
begin
  Result := -1;
  if not Assigned(aStorageImageData) then
    Exit;

  if AddDescriptorDataToArray(aStorageImageData) then
  Begin
    Result := IndexOfDescriptorData(aStorageImageData);
  End;
end;
(*
procedure TvgDescriptorArray_StorageImage.ClearDescriptor( aCommandBuffer: TvgCommandBuffer);
var
  I: Integer;
  DD: TvgDescriptor_Data_StorageImage;
  FrameData: TvgDescriptorPerFrameData;
begin
  if not Assigned(aCommandBuffer) then
    Exit;

  for I := 0 to High(fDescriptorArray) do
    if fDescriptorArray[I] is TvgDescriptor_Data_StorageImage then
    begin
      DD := TvgDescriptor_Data_StorageImage(fDescriptorArray[I]);
      FrameData := DD.GetFrameData(fCurrentFrameIndex);
      if FrameData is TvgDescriptor_PerFrame_StorageImage then
        TvgDescriptor_PerFrame_StorageImage(FrameData).ClearDescriptor(
          aCommandBuffer);
    end;
end;
*)
constructor TvgDescriptorArray_StorageImage.Create(AOwner: TComponent);
begin

  inherited Create(AOwner);
  fDescriptorType := VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
  fStageFlags           := TVkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT) or TVkShaderStageFlags(VK_SHADER_STAGE_COMPUTE_BIT);
  fImageProps.ImageType := VK_IMAGE_TYPE_2D;
  fImageProps.Tiling    := VK_IMAGE_TILING_OPTIMAL;
  fImageProps.Usage     := TVkImageUsageFlags(VK_IMAGE_USAGE_STORAGE_BIT) or
                           TVkImageUsageFlags(VK_IMAGE_USAGE_TRANSFER_SRC_BIT) or
                           TVkImageUsageFlags(VK_IMAGE_USAGE_TRANSFER_DST_BIT);
  fImageProps.Samples := VK_SAMPLE_COUNT_1_BIT;
end;

class function TvgDescriptorArray_StorageImage.GetPropertyName: String;
begin
  Result := 'StorageImage';
end;

function TvgDescriptorArray_StorageImage.GetImageFormat: TvgFormat;
begin
  Result := GetVGFormat(fImageProps.Format);
end;

function TvgDescriptorArray_StorageImage.GetGLSLDeclarationBody: String;
begin
  case fImageProps.Format of
    VK_FORMAT_R32_UINT,
    VK_FORMAT_R32G32_UINT,
    VK_FORMAT_R32G32B32A32_UINT: Result := 'uniform uimage2D';

    VK_FORMAT_R32_SINT,
    VK_FORMAT_R32G32_SINT,
    VK_FORMAT_R32G32B32A32_SINT: Result := 'uniform iimage2D';

    VK_FORMAT_R32_SFLOAT,
    VK_FORMAT_R32G32_SFLOAT,
    VK_FORMAT_R32G32B32A32_SFLOAT,
    VK_FORMAT_R8G8B8A8_UNORM:    Result := 'uniform image2D';
  else
    raise EArgumentException.CreateFmt(
      '%s does not support storage-image format %d',
      [ClassName, Ord(fImageProps.Format)]);
  end;
end;

function TvgDescriptorArray_StorageImage.GetGLSLLayoutQualifier: String;
begin
  case fImageProps.Format of
    VK_FORMAT_R32_UINT:             Result := 'r32ui';
    VK_FORMAT_R32_SINT:             Result := 'r32i';
    VK_FORMAT_R32_SFLOAT:           Result := 'r32f';
    VK_FORMAT_R32G32_UINT:          Result := 'rg32ui';
    VK_FORMAT_R32G32_SINT:          Result := 'rg32i';
    VK_FORMAT_R32G32_SFLOAT:        Result := 'rg32f';
    VK_FORMAT_R32G32B32A32_UINT:    Result := 'rgba32ui';
    VK_FORMAT_R32G32B32A32_SINT:    Result := 'rgba32i';
    VK_FORMAT_R32G32B32A32_SFLOAT:  Result := 'rgba32f';
    VK_FORMAT_R8G8B8A8_UNORM:       Result := 'rgba8';
  else
    raise EArgumentException.CreateFmt(
      '%s does not support storage-image format %d',
      [ClassName, Ord(fImageProps.Format)]);
  end;
end;

procedure TvgDescriptorArray_StorageImage.SetImageFormat(
  const Value: TvgFormat);
var
  VulkanFormat: TVkFormat;
begin
  VulkanFormat := GetVKFormat(Value);
  if fImageProps.Format = VulkanFormat then
    Exit;
  SetActiveState(False);
  fImageProps.Format := VulkanFormat;
end;


function TvgDescriptorArray_StorageImage.GetDescriptorDataStorageImage( Index: Integer): TvgDescriptor_Data_StorageImage;
begin
if (Index >= 0) and (Index < Length(fDescriptorArray)) and
     Assigned(fDescriptorArray[Index]) and
     (fDescriptorArray[Index] is TvgDescriptor_Data_StorageImage) then
    Result := TvgDescriptor_Data_StorageImage(fDescriptorArray[Index])
  else
    Result := nil;
end;

function TvgDescriptorArray_StorageImage.RemoveStorageImage(  aStorageImageData: TvgDescriptor_Data_StorageImage): Boolean;
begin
  Result := self.RemoveAndFreeDescriptor(aStorageImageData);
end;

{ TvgDescriptorArray_UBO_4x4MatrixD }

function TvgDescriptorArray_UBO_4x4MatrixD.AddMatrix: Integer;
var
  DDM : TvgDescriptor_Data_UniformBuffer<TvgMatrix4x4D>;
  DFM : TvgDescriptor_PerFrame_UniformBuffer <TvgMatrix4x4D>;
  I   : Integer;
begin
  Result := -1;

  DDM := TvgDescriptor_Data_UniformBuffer<TvgMatrix4x4D>.create;

  Result := AddUniformBuffer(DDM);

  If Result<>-1 then
  Begin
    For I:=0 to Length(DDM.fFrameData)-1 do
    Begin
      DFM := TvgDescriptor_PerFrame_UniformBuffer <TvgMatrix4x4D>(DDM.fFrameData[I]);
      If assigned(DFM) then
        DFM.Data.Add(TvgMatrix4x4D.Identity);
    end;
  End else
    FreeAndNil(DDM);

end;

function TvgDescriptorArray_UBO_4x4MatrixD.GetMatrix(aDescriptorIndex,  aFrameIndex, aDataIndex: TvkUint32): TvgMatrix4x4D;
Var L:Integer;
      DD  : TvgDescriptorData;
      DF  : TvgDescriptorPerFrameData;
begin
  Result := Default(TvgMatrix4x4D);
  L:= Length(fDescriptorArray);
  If (aDescriptorIndex<0) or (aDescriptorIndex>=L) then exit;
  DD:= fDescriptorArray[aDescriptorIndex];

  If not assigned(DD) then exit;

  DF:= DD.FrameData[aFrameIndex];
  If assigned(DF) and (DF is TvgDescriptor_PerFrame_UniformBuffer <TvgMatrix4x4D>) then
  Begin
     If (aDataIndex < TvgDescriptor_PerFrame_UniformBuffer <TvgMatrix4x4D>(DF).Data.ItemCount) then
       Result := TvgDescriptor_PerFrame_UniformBuffer <TvgMatrix4x4D>(DF).Data.Items[aDataIndex];
  End;
end;

class function TvgDescriptorArray_UBO_4x4MatrixD.GetPropertyName: String;
begin
  Result := 'UBO_4x4MatrixD';
end;

procedure TvgDescriptorArray_UBO_4x4MatrixD.SetMatrix(aDescriptorIndex, aFrameIndex, aDataIndex: TvkUint32; const Value: TvgMatrix4x4D);
Var L:Integer;
      DD  : TvgDescriptorData;
      DF  : TvgDescriptorPerFrameData;
begin
  L:= Length(fDescriptorArray);
  If (aDescriptorIndex<0) or (aDescriptorIndex>=L) then exit;
  DD:= fDescriptorArray[aDescriptorIndex];

  If not assigned(DD) then exit;

  DF:= DD.FrameData[aFrameIndex];
  If assigned(DF) and (DF is TvgDescriptor_PerFrame_UniformBuffer <TvgMatrix4x4D>) then
  Begin
    If (aDataIndex<TvgDescriptor_PerFrame_UniformBuffer <TvgMatrix4x4D>(DF).Data.ItemCount) then
        TvgDescriptor_PerFrame_UniformBuffer <TvgMatrix4x4D>(DF).Data.Items[aDataIndex] := Value;
  End;

end;


{ TvgDescriptorArray_SB_2UI }

function TvgDescriptorArray_SB_2UI.AddBuffer : TvgDescriptorData_SB_2UI;
var
  SB : TvgDescriptorData_SB_2UI;
  I:Integer;
begin
  Result := nil;

  SB := TvgDescriptorData_SB_2UI.create;

  I := AddStorageBuffer(SB);

  If I=-1 then
    FreeAndNil(SB)
  else
    Result := SB;
end;

class function TvgDescriptorArray_SB_2UI.GetPropertyName: String;
begin
  Result := 'StorageBuffer_2UI';
end;

Initialization

  RegisterDescriptorType(TvgDescriptorArray_Texture);
  RegisterDescriptorType(TvgDescriptorArray_StorageImage);

  RegisterDescriptorType(TvgDescriptorArray_UBO_4x4MatrixD);
  RegisterDescriptorType(TvgDescriptorArray_SB_2UI);


  RegisterPushConstantType(TvgPushConstant_2UI);


Finalization



end.
