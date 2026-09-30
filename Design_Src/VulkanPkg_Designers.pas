(******************************************************************************
 *                                 DVVulkan                                  *
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

unit VulkanPkg_Designers;

interface
  Uses
        System.SysUtils,
        System.Classes,
        System.TypInfo,
        System.RTLConsts,
        System.Types,
        DesignIntf,
        DesignEditors,
        ToolsAPI,
        Winapi.Windows,
        Vcl.Dialogs,
        Vulkan,
        Vulkan_Components,
        Vulkan_Components_Lookups;

Var
    SortedEnumLists  : Boolean = False;

    AboutBoxServices  : IOTAAboutBoxServices = nil;
    AboutBoxIndex     : Integer = 0;

//    VersionString     : String = 'By Datavis Pty Ltd (Version %d.%d.%d.%d)';

//    AboutDialogTitle  : String = 'Datavis Vulkan API Component Library (Build %d.%d)';


//=== s =============================================
resourcestring
  vgENoAboutServices  = 'Unable to get Borland About Services';
  vgAboutCopyright   = 'Copyright (C) Datavis Pty Ltd 2022..2026';
  vgAboutTitle       = 'Datavis Vulkan API VCL';
  vgAboutDescription = 'Datavis Vulkan API Component Library https://www.datavis.com.au' + sLineBreak +
                       'Built on pasvulkan Open Source Library https://github.com/BeRo1985/pasvulkan' + sLineBreak +
                       'Released under the zlib License';
  vgAboutLicenceStatus = 'zlib';
    VersionString      = 'By Datavis Pty Ltd (Version 1.00)';
    AboutDialogTitle   = 'Datavis Vulkan API VCL (Build 1.0)';

Type

    TvgInstanceEditor = class(TComponentEditor)
     Public
        function GetVerbCount: Integer; override;
        function GetVerb(Index: Integer): string; override;
        procedure ExecuteVerb(Index: Integer); override;
     //   procedure Edit; override;

    end;

    TvgPhysicalDeviceEditor = class(TStringProperty)
    public
      function GetAttributes: TPropertyAttributes; override;
      procedure GetValues(Proc: TGetStrProc); override;
      procedure Edit; override;
    end;

    TvgDescriptorTypeEditor = class(TStringProperty)
    Protected
      fList : TStringList;
    public
      constructor Create(const ADesigner: IDesigner; APropCount: Integer); override;
      destructor Destroy; override;

      function GetAttributes: TPropertyAttributes; override;
      procedure GetValues(Proc: TGetStrProc); override;
    end;

    TvgPushConstantTypeEditor = class(TStringProperty)
    Protected
      fList : TStringList;
    public
      constructor Create(const ADesigner: IDesigner; APropCount: Integer); override;
      destructor Destroy; override;

      function GetAttributes: TPropertyAttributes; override;
      procedure GetValues(Proc: TGetStrProc); override;
    end;


    TvgShaderModuleFileNameEditor = class(TStringProperty)
    public

      function GetAttributes: TPropertyAttributes; override;
      procedure Edit; override;
    end;


  (*
    TvgImageColorSpaceEditor = class(TEnumProperty)
    public
    function GetAttributes: TPropertyAttributes; override;
    function GetValue: string; override;
    procedure GetValues(Proc: TGetStrProc); override;
    procedure SetValue(const Value: string); override;
    end;
  *)
    TvgDeviceEditor = class(TComponentEditor)
     Public
        function GetVerbCount: Integer; override;
        function GetVerb(Index: Integer): string; override;
        procedure ExecuteVerb(Index: Integer); override;
     //   procedure Edit; override;

    end;

    TvgLinkEditor = class(TComponentEditor)
     Public
        function GetVerbCount: Integer; override;
        function GetVerb(Index: Integer): string; override;
        procedure ExecuteVerb(Index: Integer); override;
     //   procedure Edit; override;

    end;

    TVulkanEnumLookUps = class(TEnumProperty)
      public
        function GetAttributes: TPropertyAttributes; override;
        function AllEqual     : Boolean; override;
     end;

  TvgAttachmentRefPropEditor = class(TComponentProperty)
  private
  protected
    function GetAttachment : TvgAttachment;
    Function GetRenderPass : TvgRenderPass;
    function GetComponentReference: TComponent;  Override;
  public
    function AllEqual: Boolean; override;
    function GetAttributes: TPropertyAttributes; override;
    function GetValue: string; override;
    procedure GetValues(Proc: TGetStrProc); override;
    procedure SetValue(const Value: string); override;
  End;

  TvgSubPassRefPropEditor = class(TComponentProperty)
  private
  protected
    function GetComponentReference: TComponent; override;
    function GetSubPass    : TvgSubPass;
    Function GetRenderPass : TvgRenderPass;
  public
    function AllEqual: Boolean; override;
    function GetAttributes: TPropertyAttributes; override;
    function GetValue: string; override;
    procedure GetValues(Proc: TGetStrProc); override;
    procedure SetValue(const Value: string); override;
  End;


(*
  TvgPipesPropEditor = class(TComponentProperty)
  private
    function GetComponentReference: TComponent;
  protected
    Function GetPipe : TvgGraphicPipe ;
    Function GetGraphicsPipeline : TvgGraphicsPipeline;
  public
    function AllEqual: Boolean; override;
    function GetAttributes: TPropertyAttributes; override;
    function GetValue: string; override;
    procedure GetValues(Proc: TGetStrProc); override;
    procedure SetValue(const Value: string); override;
  End;
  *)
procedure Register;

//Function GetVGFormatAsString(Value:TVkFormat):String;

implementation

(*
 Function GetVGFormatAsString(Value:TVkFormat):String;
 Begin
   Result := '';
// Use RTTI to fetch the enum identifier name as declared in the Vulkan unit.
// This will return names like 'VK_FORMAT_R8G8B8A8_UNORM' for known enum entries.
// If the Vulkan header in pasVulkan defines VkFormat as an enumerated type,
// TypInfo.GetEnumName will succeed.


   Result := GetEnumName(TypeInfo(TVkFormat), Ord(Value));



 End;
 *)

Var
  // Bitmaps handed to the IDE's about box and splash screen. The IDE keeps
  // using the handles, so they are only freed when the package unloads.
  AboutBoxImage     : HBITMAP = 0;
  SplashScreenImage : HBITMAP = 0;

(*
Function InitialiseWizard : TWizardTemplate;

Var
  Svcs : IOTAServices;

Begin
  Svcs := BorlandIDEServices As IOTAServices;
  ToolsAPI.BorlandIDEServices := BorlandIDEServices;
  Application.Handle := Svcs.GetParentHandle;

  // Aboutbox plugin
  bmSplashScreen := LoadBitmap(hInstance, 'SplashScreenBitMap');
  With VersionInfo Do
    iAboutPluginIndex := (BorlandIDEServices As IOTAAboutBoxServices).AddPluginInfo(
      Format(strSplashScreenName, [iMajor, iMinor, Copy(strRevision, iBugFix + 1, 1)]),
      '$WIZARDDESCRIPTION$.',
      bmSplashScreen,
      False,
      Format(strSplashScreenBuild, [iMajor, iMinor, iBugfix, iBuild]),
      Format('SKU Build %d.%d.%d.%d', [iMajor, iMinor, iBugfix, iBuild]));


End;
*)

procedure Register;
begin

   RegisterComponents('Vulkan Graphics', [TvgInstance,
                                            TvgPhysicalDevice,
                                            TvgLinker]);

   RegisterComponentEditor (TvgInstance,      TvgInstanceEditor);
   RegisterComponentEditor (TvgLogicalDevice, TvgDeviceEditor);
   RegisterComponentEditor (TvgLinker,    TvgLinkEditor);

   RegisterPropertyEditor (TypeInfo(string), TvgPhysicalDevice, 'PhysicalDevice',  TvgPhysicalDeviceEditor);

   RegisterPropertyEditor(TypeInfo(TvgAttachment), TvgSubPassAttachment, 'Attachment', TvgAttachmentRefPropEditor);

   RegisterPropertyEditor(TypeInfo(TvgSubPass), TvgSubPassDependency , 'SrcSubPass', TvgSubPassRefPropEditor);
   RegisterPropertyEditor(TypeInfo(TvgSubPass), TvgSubPassDependency , 'DstSubPass', TvgSubPassRefPropEditor);


   If SortedEnumLists=False then
   Begin
    //ImageColorSpace
     RegisterPropertyEditor(TypeInfo(TvgFormat), TvgImageFormatColorSpace, 'ImageFormat', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgColorSpaceKHR), TvgImageFormatColorSpace, 'ColorSpace', TVulkanEnumLookUps);
   (*
    //Image Buffer
     RegisterPropertyEditor(TypeInfo(TvgMemoryPropertyFlagBits), TvgImageBufferAsset, 'MemoryProperty', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgImageUsageFlagBits),     TvgImageBufferAsset, 'Usage', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgSampleCountFlagBits),    TvgImageBufferAsset, 'Samples', TVulkanEnumLookUps);
   *)
     RegisterPropertyEditor(TypeInfo(TvgDepthBufferFormat)     , TvgDepthStencilImageBufferAsset, 'Format', TVulkanEnumLookUps);

   //SwapChain
     RegisterPropertyEditor(TypeInfo(TvgComponentSwizzle), TvgSwapChain, 'ComponentRed', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgComponentSwizzle), TvgSwapChain, 'ComponentGreen', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgComponentSwizzle), TvgSwapChain, 'ComponentBlue', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgComponentSwizzle), TvgSwapChain, 'ComponentAlpha', TVulkanEnumLookUps);

   //dynamic state
     RegisterPropertyEditor(TypeInfo(TvgDynamicStateBit), TvgDynamicState, 'State', TVulkanEnumLookUps);

   //TvgDescriptorItem
     RegisterPropertyEditor (TypeInfo(String), TvgDescriptorItem, 'DescriptorName', TvgDescriptorTypeEditor);

   //TvgPushConstantItem
     RegisterPropertyEditor (TypeInfo(String), TvgPushConstantItem, 'PushConstantName', TvgPushConstantTypeEditor);

//TvgShaderModule
     RegisterPropertyEditor (TypeInfo(String), TvgShaderModule, 'FileName', TvgShaderModuleFileNameEditor);

   //TvgGraphicsPipeline
//     RegisterPropertyEditor(TypeInfo(TvgPrimitiveTopology), TvgGraphicPipe, 'Topology', TVulkanEnumLookUps);

   //GraphicsPipe
     RegisterPropertyEditor(TypeInfo(TvgPolygonMode), TvgRasterizerState, 'PolygonMode', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgCullMode), TvgRasterizerState, 'CullMode', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgFrontFace), TvgRasterizerState, 'FrontFace', TVulkanEnumLookUps);

     RegisterPropertyEditor(TypeInfo(TvgBlendOp), TvgColorBlendAttachment, 'ColorBlendOp', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgBlendOp), TvgColorBlendAttachment, 'AlphaBlendOp', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgBlendFactor), TvgColorBlendAttachment, 'SrcColorBlendFactor', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgBlendFactor), TvgColorBlendAttachment, 'DstColorBlendFactor', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgBlendFactor), TvgColorBlendAttachment, 'SrcAlphaBlendFactor', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgBlendFactor), TvgColorBlendAttachment, 'DstAlphaBlendFactor', TVulkanEnumLookUps);

     RegisterPropertyEditor(TypeInfo(TvgSampleCountFlagBits), TvgMultisamplingState, 'RasterizationSamples', TVulkanEnumLookUps);
//     RegisterPropertyEditor(TypeInfo(), TvgGraphicsPipeline, '', TVulkanEnumLookUps);

 //TvgVertexAttributeDesc
     RegisterPropertyEditor(TypeInfo(TvgFormat), TvgVertexAttributeDesc, 'Format', TVulkanEnumLookUps);

     //TvgRenderPassAttachment
     RegisterPropertyEditor(TypeInfo(TvgSampleCountFlagBits), TvgAttachment, 'Samples', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgAttachmentLoadOp),    TvgAttachment, 'LoadOp', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgAttachmentStoreOp),   TvgAttachment, 'StoreOp', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgAttachmentLoadOp),    TvgAttachment, 'StencilLoadOp', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgAttachmentStoreOp),   TvgAttachment, 'StencilStoreOp', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgImageLayout),         TvgAttachment, 'InitialLayout', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgImageLayout),         TvgAttachment, 'FinalLayout', TVulkanEnumLookUps);

     RegisterPropertyEditor(TypeInfo(TvgImageLayout),         TvgSubPassAttachment , 'Layout', TVulkanEnumLookUps);

     //TvgSubPass
     RegisterPropertyEditor(TypeInfo(TvgPipelineBindPoint), TvgSubPass, 'PipelineBindPoint', TVulkanEnumLookUps);

     //TvgSubPassDependency
     RegisterPropertyEditor(TypeInfo(TvgPipelineStageFlagBits), TvgSubPassDependency, 'SrcStageMask', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgPipelineStageFlagBits), TvgSubPassDependency, 'DstStageMask', TVulkanEnumLookUps);

     RegisterPropertyEditor(TypeInfo(TvgAccessFlagBits), TvgSubPassDependency, 'SrcAccessMask', TVulkanEnumLookUps);
     RegisterPropertyEditor(TypeInfo(TvgAccessFlagBits), TvgSubPassDependency, 'DstAccessMask', TVulkanEnumLookUps);

   end;

   RegisterPropertiesInCategory('QueueFamily', ['QueueUniversal',
                                                'QueuePresentation',
                                                'QueueGraphics',
                                                'QueueCompute',
                                                'QueueTransfer']);
   RegisterPropertiesInCategory('CommandsPool', ['CommandPools',
                                                'CommandPoolsCount',
                                                'CommandPoolsQueueFamilyType',
                                                'CommandPoolsQueueCreateFlags']);
end;


procedure TvgInstanceEditor.ExecuteVerb(Index: Integer);
begin
  case Index of
      0: ; // nothing to do
      1: MessageDlg ('This is a Vulkan Graphics Instance component '#13 + 'built by Datavis'#13 , mtInformation, [mbOK], 0);
      2: (Component as TvgInstance).BuildAllExtensionsAndLayers    ;
   //   4:;

    end;
end;

function TvgInstanceEditor.GetVerb(Index: Integer): string;
begin
  case Index of
      0: Result := ' Vulkan Graphics Instance (©Datavis)';
      1: Result := '&About this component...';
      2: Result := 'Add &Extensions and Layers...';
    end;
end;

function TvgInstanceEditor.GetVerbCount: Integer;
begin
  Result:=3;
end;


{ TvgPhysicalDeviceEditor }

procedure TvgPhysicalDeviceEditor.Edit;
begin
  inherited;

end;

function TvgPhysicalDeviceEditor.GetAttributes: TPropertyAttributes;

begin
  result:=inherited;
  result := result + [paValueList, paSortList];
end;

procedure TvgPhysicalDeviceEditor.GetValues(Proc: TGetStrProc);
  Var D:TvgPhysicalDevice;
      I:Integer;
      S:String;
      B:Boolean;
begin

  D:=TvgPhysicalDevice(GetComponent(0));
  If assigned(D) and assigned(D.Instance) then
  Begin
    If not D.Instance.Active then
    Begin
       D.Instance.Active:=True;
       B:=True;
    End else
       B:=False;

    Try
      If D.Instance.active then
      Begin
        For I:=0 to D.Instance.PhysicalDevices.Count-1 do
        Begin
           S:= TvgPhysDevice(D.Instance.PhysicalDevices.Items[I]).Description;
           Proc(S);
        End;
      end else
        Proc('Instance not Active');
    Finally
      If B then
        D.Instance.Active:=False;
    End;
  End;
end;

{ TvgDeviceEditor }

procedure TvgDeviceEditor.ExecuteVerb(Index: Integer);
begin
  case Index of
      0: ; // nothing to do
      1: MessageDlg ('Vulkan Graphics Device component '#13 + 'built by Datavis'#13 , mtInformation, [mbOK], 0);
      2: (Component as TvgLogicalDevice).BuildALLExtensions;
      3: (Component as TvgLogicalDevice).BuildALLLayers;
      4: (Component as TvgLogicalDevice).BuildALLFeatures;
    end;
end;

function TvgDeviceEditor.GetVerb(Index: Integer): string;
begin
  Result:='' ;
  case Index of
      0: Result := 'Vulkan Graphics Device (©Datavis)';
      1: Result := '&About this component...';
      2: Result := 'Add &Extensions...';
      3: Result := 'Add &Layers...';
      4: Result := 'Add &Features...';
    end;

end;

function TvgDeviceEditor.GetVerbCount: Integer;
begin
  Result:=5;
end;


{ TVulkanEnumLookUps }

function TVulkanEnumLookUps.AllEqual: Boolean;
begin
  Result:=True;
end;

function TVulkanEnumLookUps.GetAttributes: TPropertyAttributes;
begin
  Result := [paMultiSelect, paValueList, paRevertable];    //not sorted
end;

procedure RegisterAboutBox;
begin
  Supports(BorlandIDEServices,IOTAAboutBoxServices, AboutBoxServices);
  Assert(Assigned(AboutBoxServices), vgENoAboutServices);
  AboutBoxImage  := LoadBitmap(FindResourceHInstance(HInstance), 'Datavis');
  AboutBoxIndex := AboutBoxServices.AddPluginInfo(AboutDialogTitle,
      vgAboutDescription,
      AboutBoxImage,
      False,
      '',
      VersionString);
end;

procedure UnregisterAboutBox;
begin
  if (AboutBoxIndex <> 0) and Assigned(AboutBoxServices) then
  begin
    AboutBoxServices.RemovePluginInfo(AboutBoxIndex);
    AboutBoxIndex := 0;
    AboutBoxServices := nil;
  end;
  if AboutBoxImage <> 0 then
  begin
    DeleteObject(AboutBoxImage);
    AboutBoxImage := 0;
  end;
end;

procedure RegisterSplashScreen;
begin
  // SplashScreenServices is only valid while the IDE is starting up; it is nil
  // when the package is installed or rebuilt from a running IDE.
  If not Assigned(SplashScreenServices) then
    Exit;
  SplashScreenImage := LoadBitmap(FindResourceHInstance(HInstance), 'Datavis');
  SplashScreenServices.AddPluginBitmap(AboutDialogTitle,
      SplashScreenImage,
      False,
      '',
      VersionString);
end;

{ TvgAttachmentRefPropEditor }

function TvgAttachmentRefPropEditor.AllEqual: Boolean;
begin
  Result:=True;
end;

function TvgAttachmentRefPropEditor.GetAttachment: TvgAttachment;
begin
  If GetOrdValue<>0 then
     Result := TvgAttachment(GetOrdValue)
  else
     Result := Nil;
end;

function TvgAttachmentRefPropEditor.GetAttributes: TPropertyAttributes;
begin
    Result := [paValueList,  paRevertable] ;
end;

function TvgAttachmentRefPropEditor.GetComponentReference: TComponent;
begin
  Result:=nil;
end;

function TvgAttachmentRefPropEditor.GetRenderPass: TvgRenderPass;
  Var P:TPersistent;
begin
  Result:=Nil;
  P := GetComponent(0);    //this should be the    TvgRenderPassAttachmentRef
  If Not assigned(P) or Not (P is  TvgSubPassAttachment) then exit;

  Result:= TvgSubPassAttachment(P).GetRenderPass;

end;

function TvgAttachmentRefPropEditor.GetValue: string;
  Var C : TvgAttachment;
begin
    C := GetAttachment ;
    If assigned(C) then
      Result:= C.Name
    else
      Result:='(Not Set)';
end;

procedure TvgAttachmentRefPropEditor.GetValues(Proc: TGetStrProc);
  Var I :Integer;
      S : String;
      R : TvgRenderPass;
begin

  R := GetRenderPass;
  If not assigned(R) then exit;

  If R.Attachments.Count>0 then
  Begin
      For I:=0 to  R.Attachments.Count-1 do
      Begin
        S:= Trim(R.Attachments.Items[I].Name);
        If S='' then
          S:= Format('Attachment - %d',[I]);
        Proc(S);
      End;
  End;
end;

procedure TvgAttachmentRefPropEditor.SetValue(const Value: string);
  Var R:TvgRenderPass;
      S:String;
    //  A:TvgRenderPassAttachment;
      I:Integer;
begin
  //inherited;
   R:= GetRenderPass;

   If (Value<>'') and Assigned(R) and (R.Attachments.Count>0) then
   Begin
       For I:=0 to R.Attachments.count-1 do
       Begin
         S:= Trim(R.Attachments.Items[I].Name);
         If CompareText(S,Value)=0 then
         Begin
           SetOrdValue(NativeInt(R.Attachments.Items[I]));
           exit;
         End;
       End;
   end else
       SetOrdValue(0);

end;

{ TvgSubPassRefPropEditor }

function TvgSubPassRefPropEditor.AllEqual: Boolean;
begin
  Result:=True;
end;

function TvgSubPassRefPropEditor.GetAttributes: TPropertyAttributes;
begin
    Result := [paValueList,  paRevertable] ;
end;

function TvgSubPassRefPropEditor.GetComponentReference: TComponent;
begin
  Result:=nil;
end;

function TvgSubPassRefPropEditor.GetRenderPass: TvgRenderPass;
  Var P:TPersistent;
begin
  Result:=Nil;
  P := GetComponent(0);    //this should be the    TvgRenderPassAttachmentRef
  If Not assigned(P) or Not (P is  TvgSubPassDependency) then exit;

  Result:= TvgSubPassDependency(P).GetRenderPass;
end;

function TvgSubPassRefPropEditor.GetSubPass: TvgSubPass;
begin
  If GetOrdValue<>0 then
     Result := TvgSubPass(GetOrdValue)
  else
     Result:=Nil;
end;

function TvgSubPassRefPropEditor.GetValue: string;
  Var C : TvgSubPass;
begin
    C := GetSubPass ;
    If assigned(C) then
      Result:= C.Name
    else
      Result:='(Not Set)';
end;

procedure TvgSubPassRefPropEditor.GetValues(Proc: TGetStrProc);
  Var I :Integer;
      S : String;
      R : TvgRenderPass;
begin

  R := GetRenderPass;
  If not assigned(R) then exit;

  If R.SubPasses.Count>0 then
  Begin
      For I:=0 to  R.SubPasses.Count-1 do
      Begin
        S:= Trim(R.SubPasses.Items[I].Name);
        If S='' then
          S:= Format('SubPass - %d',[I]);
        Proc(S);
      End;
  End;
end;

procedure TvgSubPassRefPropEditor.SetValue(const Value: string);
  Var R:TvgRenderPass;
      S:String;
  //    A:TvgRenderPassAttachment;
      I:Integer;
begin
  //inherited;
   R:= GetRenderPass;

   If (Value<>'') and Assigned(R) and (R.SubPasses.Count>0) then
   Begin
       For I:=0 to R.SubPasses.count-1 do
       Begin
         S:= Trim(R.SubPasses.Items[I].Name);
         If CompareText(S,Value)=0 then
         Begin
           SetOrdValue(NativeInt(R.SubPasses.Items[I]));
           exit;
         End;
       End;
   end else
       SetOrdValue(0);

end;

{ TvgLinkEditor }

procedure TvgLinkEditor.ExecuteVerb(Index: Integer);
begin
  case Index of
      0: ; // nothing to do
      1: MessageDlg ('This is a Vulkan Graphics Link component '#13 + 'built by Datavis'#13 , mtInformation, [mbOK], 0);
      2: (Component as TvgLinker).BuildSwapChainColorSpaces;
      3: (Component as TvgLinker).BuildSwapChainPresentationModes;
     // 4: {(Component as TvgLinker).BuildRenderPassStructure};
   //   4: (Component as TvgLinker).BuildFeaturesStructure;
    end;
end;

function TvgLinkEditor.GetVerb(Index: Integer): string;
begin
  case Index of
      0: Result := ' Vulkan Graphics Link (©Datavis)';
      1: Result := '&About this component...';
      2: Result := 'Add All &Images and Color Spaces Modes...';
      3: Result := 'Add All &Presentation Modes...';
    //  4: Result := 'Build &Render Pass Structure...';
    //  4: Result := 'Update &Features...';
    end;
end;

function TvgLinkEditor.GetVerbCount: Integer;
begin
  Result := 4;
end;


{ TvgShaderDataTypeEditor }

constructor TvgDescriptorTypeEditor.Create(const ADesigner: IDesigner;  APropCount: Integer);
begin
  inherited;
  fList := TStringList.Create;
end;

destructor TvgDescriptorTypeEditor.Destroy;
begin
  If assigned(fList) then
    FreeAndNil(fList);
  inherited;
end;

function TvgDescriptorTypeEditor.GetAttributes: TPropertyAttributes;
begin
 // result:=inherited;
  result := {result +} [paValueList, paSortList];
end;

procedure TvgDescriptorTypeEditor.GetValues(Proc: TGetStrProc);
   Var I:Integer;
begin
   FillDescriptorNameList(fList);
   fList.Sort;
   If fList.Count>0 then
     For i:=0 to fList.Count-1 do
        Proc(fList.Strings[I]);
end;

{ TvgPushConstantTypeEditor }

constructor TvgPushConstantTypeEditor.Create(const ADesigner: IDesigner;  APropCount: Integer);
begin
  inherited;
  fList := TStringList.Create;
end;

destructor TvgPushConstantTypeEditor.Destroy;
begin
  If assigned(fList) then
    FreeAndNil(fList);
  inherited;
end;

function TvgPushConstantTypeEditor.GetAttributes: TPropertyAttributes;
begin
  result :=  [paValueList, paSortList];
end;

procedure TvgPushConstantTypeEditor.GetValues(Proc: TGetStrProc);
   Var I:Integer;
begin
   FillPushConstantNameList(fList);
   fList.Sort;
   If fList.Count>0 then
     For i:=0 to fList.Count-1 do
        Proc(fList.Strings[I]);
end;


{ TvgShaderModuleFileNameEditor }

procedure TvgShaderModuleFileNameEditor.Edit;
var
  OpenDialog: TOpenDialog;
begin
    OpenDialog := TOpenDialog.Create(nil);
  try
    OpenDialog.Title := 'Select Shader File';
    OpenDialog.Filter := 'Shader Compiled SPIR-V Files (*.spv)|*.spv';
    OpenDialog.Options := [ ofFileMustExist, ofHideReadOnly, ofEnableSizing] ;
    OpenDialog.InitialDir := ShaderFolderPath;
    OpenDialog.FileName := GetValue;
    if OpenDialog.Execute then
      SetValue( ExtractFileName(OpenDialog.FileName));
  finally
    OpenDialog.Free;
  end;
end;

function TvgShaderModuleFileNameEditor.GetAttributes: TPropertyAttributes;
begin
  Result := [paDialog, paRevertable];
end;


Initialization

  RegisterSplashScreen;
  RegisterAboutBox;


Finalization
  UnregisterAboutBox;
  if SplashScreenImage <> 0 then
    DeleteObject(SplashScreenImage);

end.
