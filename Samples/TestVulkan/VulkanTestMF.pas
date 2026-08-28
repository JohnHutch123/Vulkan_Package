unit VulkanTestMF;

interface

{$INCLUDE VulkanPackage.inc}

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ComCtrls,  Vcl.Buttons, Vcl.ExtCtrls,
  Generics.Collections,
  Generics.Defaults,
  Vulkan,
  PasVulkan.Math,{PasVulkan.Application,}
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_WindowVCL ,
  Vulkan_Components_Nodes,
  Vulkan_Render_Tests,
  Vulkan_Components_Descriptors,
  Vulkan_Renderer_Single,
  Vulkan_Renderer_CommThread,
  Vulkan_Components_Scene_Renderer,
  Vulkan_Components_DataStore,
  Vulkan_Components_ShaderBuilder;

type
  TTestVulkan = class(TForm)
    Button2: TButton;
    Button3: TButton;
    StatusBar1: TStatusBar;
    BitBtn2: TBitBtn;
    WType: TRadioGroup;
    ValidationCB: TCheckBox;
    Button6: TButton;
    Button7: TButton;
    Button8: TButton;
    DeviceSel: TRadioGroup;
    TestRB: TRadioGroup;
    DBCB: TCheckBox;
    MSAACB: TCheckBox;
    SelectionCB: TCheckBox;
    RendRB: TRadioGroup;
    ThreadC: TEdit;
    MessagesTxt: TMemo;
    SceneResetCB: TCheckBox;
    RenderTargetRB: TRadioGroup;
    RotateCB: TCheckBox;
    Button10: TButton;
    OpenDialog1: TOpenDialog;
    BitBtn3: TBitBtn;
    TestRead: TRadioGroup;
    DataFolderDlg: TFileOpenDialog;
    Label1: TLabel;
    Button9: TButton;
    SupportFolderEDT: TEdit;
    BitBtn4: TBitBtn;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button5Click(Sender: TObject);
    procedure BitBtn1Click(Sender: TObject);
    procedure BitBtn2Click(Sender: TObject);
    procedure Button10Click(Sender: TObject);
    procedure Button6Click(Sender: TObject);
    procedure vgWindowLink1RenderPassBuild(Sender: TvgRenderPass);
    procedure Button7Click(Sender: TObject);
    procedure Button8Click(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure Button9Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormDestroy(Sender: TObject);
    procedure MSAACBClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure BitBtn3Click(Sender: TObject);
    procedure Panel1MouseMove(Sender: TObject; Shift: TShiftState; X,
      Y: Integer);
  private
    { Private declarations }
    fInstance : TvgInstance;
    fPhysicalDevice   : TvgPhysicalDevice;
    fScreenDevice     : TvgScreenRenderDevice;
    fLinker  : TvgLinker;
  //  fMVP      : TvgMVPBufferAsset;
    fVCLWin   : TvgWindowVCL ;
    fGP       : TvgGraphicPipeline;
    fRenderer   : TvgRenderEngine;
    fScene      : TvgScene;
    fToolManager:TvgToolManager;

    fMSAASample : TvgSampleCountFlagBits;
    procedure HandleMsg(const aLabel: String; const ThreadCount,
      aMsgCount: Integer);

    Procedure BuildShaders;

  public
    { Public declarations }

  //  Procedure HandleMsg(const aLabel:String; const ThreadCount : Integer; const aMsgCount:Integer) ;
    Procedure HandleLinkerMessages(aList:TStringList);
  end;

var
  TestVulkan: TTestVulkan;

implementation

{$R *.dfm}

function IsRenderDocActive: Boolean;
type
  PRENDERDOC_API_1_6_0 = Pointer;

  TRenderDocGetAPI = function(version: Integer; out outAPIPointers: Pointer): Integer; cdecl;

const
  RENDERDOC_API_VERSION_1_6_0 = 10600; // Matches RenderDoc header

var
  LibHandle: HMODULE;
  GetAPI: TRenderDocGetAPI;
  ApiPtr: Pointer;

begin
  Result := False;

  // Try to get handle to already-injected renderdoc.dll
  LibHandle := GetModuleHandle('renderdoc.dll');
  if LibHandle = 0 then
    Exit; // Not injected

  @GetAPI := GetProcAddress(LibHandle, 'RENDERDOC_GetAPI');
  if not Assigned(GetAPI) then
    Exit;

  ApiPtr := nil;
  if GetAPI(RENDERDOC_API_VERSION_1_6_0, ApiPtr) = 1 then
    Result := ApiPtr <> nil;
end;



procedure TTestVulkan.BitBtn1Click(Sender: TObject);
begin
  // if assigned(fScene) then
  //    fScene.ClearScene;

   If assigned(fInstance) then
   Begin
     fInstance.BuildAllExtensionsAndLayers;




     fInstance.Active:=False;
   End;

  MessagesTxt.lines.add(DebugString);
  DebugString := '';


end;

procedure TTestVulkan.BitBtn2Click(Sender: TObject);
begin

  Assert(assigned(fVCLWin),'fVCLWin not defined');
  fVCLWin.SetBounds(fVCLWin.Left, fVCLWin.Top, fVCLWin.Width+10, fVCLWin.Height+5);
end;

procedure TTestVulkan.BitBtn3Click(Sender: TObject);
var
  DS: TvgObjectStore;
  Scene : TvgScene;

  Obj, Obj1, Obj2 : TvgObject;
 // ObjIndex: Integer;
//  VertexSetIndex, IndexSetIndex: Integer;
//  vBinding, iBinding, idxBinding: Cardinal;
//  vIndex, instIndex, triIndex: Integer;
//  gHeader: string;

 // V3 : TvgVector3S;
 // V4 : TvgVector4S;

  ObjHigh,ObjLow : Longword;
  ObjPtr         : Uint64;

begin

  Scene:= TvgScene.create(nil);
  Scene.Load_Begin;

  DS := TvgObjectStore.Create(nil);
  If not Scene.AddDataStore(DS) then
  Begin
    DS.free;
    Scene.free;
    exit;
  End;

Case TestRead.ItemIndex of
     0:;
     1:Begin
              // NOTE: InitializeVulkan requires your pasVulkan device/queue/command-pool objects.
              // DS.InitializeVulkan(MyDevice, MyTransferQueue, MyCommandPool);

                   DS.Topology     := TRIANGLE_LIST;
                //   DS.IncInstance  := True;
                //   DS.InitializeIndexBuffer(itUInt32);

                    DS.SetUpVertexAttributes( [vdtPosition, vdtColor]);
                //    DS.AddInstanceAttributes( [idtObjID]);

                  Obj := DS.AddObject(True);

                    // Define vertex attributes for the vertex binding: position (loc0) + color (loc1)
                   // DS.AddVertexAttributes(vBinding, [vdtPosition, vdtColor], [0, 1]);
                //    If Obj.AddInstance<>-1 then
                //       Obj.SetInstanceObjID(99,98)  ;

                    // Define instance attributes for the object's instance binding: objID + instance color
                    // objID uses uvec2 (two uints) at location 2, color at location 3

                    // Allocate vertex storage and instance storage for this object's bindings
                    Obj.AllocateVertices( 6);    // 6 vertices for 2 triangles

                    // Initialize index buffer type and allocate indices for the index binding
                //    Obj.AllocateIndices( 6); // two triangles

                    If Obj.IncCurrentVertex then
                    Begin
                      Obj.SetVertexPosition( 0.0,-0.5,0.1) ;
                      Obj.SetVertexColor( 1.0, 0.0, 0.0) ;
                    End;

                    If Obj.IncCurrentVertex then
                    Begin
                    Obj.SetVertexPosition( 0.5,0.5,0.1) ;
                    Obj.SetVertexColor( 0.0,1.0,0.0) ;
                    End;

                    If Obj.IncCurrentVertex then
                    Begin
                    Obj.SetVertexPosition(-0.5,0.5,0.1) ;
                    Obj.SetVertexColor( 0.0,0.0,1.0) ;
                    End;

                    If Obj.IncCurrentVertex then
                    Begin
                    Obj.SetVertexPosition( 0.0,-0.5,0.1) ;
                    Obj.SetVertexColor( 1.0, 0.0, 0.0) ;
                    End;

                    If Obj.IncCurrentVertex then
                    Begin
                    Obj.SetVertexPosition( 0.5,0.5,0.1) ;
                    Obj.SetVertexColor( 0.0,1.0,0.0) ;
                    End;

                    If Obj.IncCurrentVertex then
                    Begin
                    Obj.SetVertexPosition(-0.5,0.5,0.1) ;
                    Obj.SetVertexColor( 0.0,0.0,1.0) ;
                    End;

                    Obj.AddIndex(0, 1, 2)  ;
                    Obj.AddIndex(2, 3, 0)  ;

                     MessagesTxt.Clear;
           (*

                    MessagesTxt.Clear;
                    MessagesTxt.Lines.Add(Format('Object example prepared: object index = %d',[ ObjIndex]));
                    MessagesTxt.Lines.Add(Format('Vertex binding = %d  Instance binding = %d Index binding = %d', [ Obj.VertexBinding,
                                                                                                                    Obj.InstanceBinding,
                                                                                                                    Obj.IndexBinding]));
                    MessagesTxt.Lines.Add(Format('Vertex count for binding: %d',   [DS.GetCount(Obj.VertexBinding)]));
                    MessagesTxt.Lines.Add(Format('Instance count for binding: %d', [DS.GetCount(Obj.InstanceBinding)]));
                    MessagesTxt.Lines.Add(Format('Index count for binding: %d',    [DS.GetIndexCount(Obj.IndexBinding)]));

                    gHeader := #10+#13+'GLSL Header for Data Store'+#10+#13;
                    gHeader := gHeader + #10+#13+ DS.WriteGLSLHeader;

                    MessagesTxt.Lines.Add('***********');
                    MessagesTxt.Lines.Add(gHeader);
                    MessagesTxt.Lines.Add('***********');

                    MessagesTxt.Lines.Add('------');
                    MessagesTxt.Lines.Add('');
                    DumpBindingDebug(DS,  MessagesTxt.Lines);
             *)
     End;
     2:Begin  //multiple object and index use

               //      DS := TvgObjectStore.Create;
                     DS.Topology     := TRIANGLE_LIST;
                 //    DS.InstanceDataON  := true;
                      //
                     DS.BaseVertName := 'TestTextureRect';
                     DS.BaseFragName := 'TestTextureRect';

                      DS.SetUpVertexAttributes( [vdtPosition, vdtColor]);
                      DS.SetUpInstanceAttributes( [idtObjID]);

                      Obj1 := DS.AddObject(True);
                      Obj2 := DS.AddObject(True);


                      // Allocate vertex storage and instance storage for this object's bindings
                      Obj1.AllocateVertices( 4);
                      Obj2.AllocateVertices( 4);    //set fCurrentvertex to -1

                   //obj1

                      Obj1.CurrentVertex := 0 ;
                      Obj1.SetVertexPosition(-0.75,-0.75,0.2);
                      Obj1.SetVertexColor(1.0,0.0,0.0);

                      Obj1.CurrentVertex := 1 ;
                        Obj1.SetVertexPosition(0.75,-0.75,0.22);
                        Obj1.SetVertexColor(0.0,1.0,0.0);


                      Obj1.CurrentVertex :=2 ;
                        Obj1.SetVertexPosition(0.75,0.75,0.25);
                        Obj1.SetVertexColor(0.0, 0.0, 1.0);


                      Obj1.CurrentVertex :=3 ;

                        Obj1.SetVertexPosition(-0.75,0.75,0.18);
                        Obj1.SetVertexColor(0.0,1.0,0.0);


                      Obj1.AddIndex(0, 1, 2);
                      Obj1.AddIndex(2, 3, 0);

                 //obj2
                      If Obj2.IncCurrentVertex then
                      Begin
                        Obj2.SetVertexPosition(0.0,-1.0,0.52);
                        Obj2.SetVertexColor(1.0,0.0,0.0);
                      End;

                      If Obj2.IncCurrentVertex then
                      Begin
                        Obj2.SetVertexPosition(1.0,0.0,0.55);
                        Obj2.SetVertexColor(0.0,1.0,0.0);
                      End;

                      If Obj2.IncCurrentVertex then
                      Begin
                        Obj2.SetVertexPosition(0.0,1.0,0.48);
                        Obj2.SetVertexColor(0.0,0.0,1.0);
                      End;

                      If Obj2.IncCurrentVertex then
                      Begin
                        Obj2.SetVertexPosition(-1.0,0.0,0.52);
                        Obj2.SetVertexColor(0.0,1.0,0.0);
                      End;

                      Obj2.AddIndex(0, 1, 2);
                      Obj2.AddIndex(2, 3, 0);

                     MessagesTxt.Clear;

             (*
                    MessagesTxt.Clear;
                    MessagesTxt.Lines.Add('*********Object 1 ***********');
                    MessagesTxt.Lines.Add(Format('Object example prepared: object index = %d',[ ObjIndex]));
                    MessagesTxt.Lines.Add(Format('Vertex binding = %d  Instance binding = %d Index binding = %d', [ Obj1.VertexBinding,
                                                                                                                    Obj1.InstanceBinding,
                                                                                                                    Obj1.IndexBinding]));
                    MessagesTxt.Lines.Add(Format('Vertex count for binding: %d',   [DS.GetCount(Obj1.VertexBinding)]));
                    MessagesTxt.Lines.Add(Format('Instance count for binding: %d', [DS.GetCount(Obj1.InstanceBinding)]));
                    MessagesTxt.Lines.Add(Format('Index count for binding: %d',    [DS.GetIndexCount(Obj1.IndexBinding)]));

                    MessagesTxt.Lines.Add('********Object 2 ************');

                    MessagesTxt.Lines.Add(Format('Object example prepared: object index = %d',[ ObjIndex]));
                    MessagesTxt.Lines.Add(Format('Vertex binding = %d  Instance binding = %d Index binding = %d', [ Obj2.VertexBinding,
                                                                                                                    Obj2.InstanceBinding,
                                                                                                                    Obj2.IndexBinding]));
                    MessagesTxt.Lines.Add(Format('Vertex count for binding: %d',   [DS.GetCount(Obj2.VertexBinding)]));
                    MessagesTxt.Lines.Add(Format('Instance count for binding: %d', [DS.GetCount(Obj2.InstanceBinding)]));
                    MessagesTxt.Lines.Add(Format('Index count for binding: %d',    [DS.GetIndexCount(Obj2.IndexBinding)]));

                    gHeader := #10+#13+'GLSL Header for Data Store'+#10+#13;
                    gHeader := gHeader + #10+#13+ DS.WriteGLSLHeader;

                    MessagesTxt.Lines.Add('***********');
                    MessagesTxt.Lines.Add(gHeader);
                    MessagesTxt.Lines.Add('***********');

                    MessagesTxt.Lines.Add('------');
                    MessagesTxt.Lines.Add('');

                    DumpBindingDebug(DS,  MessagesTxt.Lines);
              *)


     end;

  End;   //case

  Scene.Load_End;

  Scene.ClearScene;

  Scene.Free;

end;


procedure TTestVulkan.BuildShaders;
  Var I,J:Integer;
      SB :  TvgShaderBuilder;
      OS : TvgBaseObjectStore;
      GP : TvgGraphicPipeline;
      S:String;
begin
  If not assigned(fScene) then exit;
  If not fScene.GetObjectStoreCount=0 then exit;
  If not (fScene.SceneState =SS_READY) then exit;

  Fscene.BuildGraphicPipelinesForRenderer(self.fRenderer);


  SB :=  TvgShaderBuilder.Create(Self);
  SB.Scene := fScene;
  SB.IncludeComments := True;


  For I:=0 to  fScene.GetObjectStoreCount-1 do
  Begin
    OS := fScene.ObjectStore[I] ;
    If assigned(OS) and (OS.PipelineCount>0) then
    Begin
      SB.ObjectStore := OS;
      For J:=0 to OS.PipelineCount-1 do
      Begin
        GP:= OS.GraphicPipeline[J];
        If assigned(GP) then
        Begin
          SB.pipeline:=GP;

          S:=SB.BuildVertexShader(GP);
          MessagesTxt.Lines.add('***************************VERTEX SHADER TEMPLATE************');
          MessagesTxt.Lines.add(S);
          MessagesTxt.Lines.add('***************************VERTEX SHADER TEMPLATE************');

          S:=SB.BuildFragmentShader(GP);
          MessagesTxt.Lines.add('***************************FRAG SHADER TEMPLATE************');
          MessagesTxt.Lines.add(S);
          MessagesTxt.Lines.add('***************************FRAG SHADER TEMPLATE************');

        End;
      end;
    End;
  End;

  SB.free;

end;

procedure TTestVulkan.Button10Click(Sender: TObject);
begin
  If not assigned(fScene) then exit;

  fScene.ClearScene;


  MessagesTxt.Clear;

  MessagesTxt.Lines.add('Test Scene Unloaded');


 // Button6Click(nil);

end;

procedure TTestVulkan.Button1Click(Sender: TObject);
  Var
   //    I,L : Integer;

       TC:Integer;
    Procedure RunComponentTests(aComp:TvgBaseComponent);
    Begin
        aComp.Active := True;
        aComp.Active := False;
      (*

    //    aComp.Designing := True;
        aComp.Active    := True;
        aComp.Active    := False;
      *)
      Try
      //  aComp.Active    := True;
      //  aComp.Active    := False;
      Except
         On E:Exception do
           aComp.active := False;
      End;
    End;

begin
    WType.Enabled:=False;
    Assert(not assigned(fInstance), 'Instance already created');

    fInstance := TvgInstance.Create(self);
    fInstance.MemAllocation := VG_VULKAN_MANAGE;
    fInstance.Validation    := ValidationCB.Checked;
    fInstance.APIVersion    := VG_API_VERSION_1_3;
    fInstance.DescriptorIndexing  := True;

    //testing
  //  RunComponentTests(fInstance);

    fPhysicalDevice := TvgPhysicalDevice.Create(self);
    fPhysicalDevice.Instance := fInstance;

    fPhysicalDevice.DeviceSelect := vgdsIndex;
    fPhysicalDevice.DeviceIndex  := DeviceSel.ItemIndex;

 //   RunComponentTests(fInstance);


    fScreenDevice := TvgScreenRenderDevice.create(nil);
    fScreenDevice.PhysicalDevice := fPhysicalDevice;
 (*
    fInstance.BuildALLEXtensions;
    fInstance.BuildALLLayers;

    fScreenDevice.BuildALLExtensions;
    fScreenDevice.BuildALLLayers;

    fScreenDevice.BuildAllFeatures;
 *)
 //   RunComponentTests(fInstance);

    fLinker  := TvgLinker.Create(self);

    fLinker.RenderMessages   := HandleLinkerMessages;
    fLinker.MsgON            := True;

    fLinker.ScreenDevice  := fScreenDevice;;   //add winlink here to trigger RenderToScreen

  //  fLinker.BuildFeaturesStructure;

  //  RunComponentTests(fInstance);

    Case WType.ItemIndex of
       0:Begin
          fVCLWin        := TvgWindowVCL.Create(self) ;

          fVCLWin.Parent := Self;
          fVCLWin.Top    := 40;
          fVCLWin.Left   := 500;
          fVCLWin.Width  := 300;
          fVCLWin.Height := 320;
          fVCLWin.Color  := clBlack;

          fLinker.WindowIntf := fVCLWin;


       end;
       1:Begin
       //   fSDL2Win  := TvgSDL2Window.Create(self);

        //  fSurface.WindowIntf := fSDL2Win;
       End;
    End;


 //  RunComponentTests(fInstance);



    case RenderTargetRB.ItemIndex of
       0: fLinker.RenderTarget     := RT_SCREEN;
       1: Begin
           fLinker.RenderTarget    := RT_FRAME;
         //  fLinker.FrameResolution := 1;   //any thing larger than one slows frame prepare down significantly
       End;
    end;


    Case RendRB.ItemIndex of
      0: Begin
            fRenderer   := TvgRenderEngine_Single.create(self);
            fRenderer.SelectON := false;//SelectionCB.checked;


          //  fRenderer.CreateRenderPass;
         //   TvgRenderPass_Simple(fRenderer.RenderPass).RenderType := RP_TWOPASSRES;

      End;
      1: Begin
           fRenderer   := TvgCommThread_RenderEngine.Create(Self);

           If TryStrToInt(ThreadC.Text,TC) then
              fRenderer.WorkerCount := TC;
          // TvgRenderEngine_CommThread(fRenderer).OnHandleMessage :=  HandleMsg;
         End;
    End;

    fRenderer.Linker                := fLinker;
    fRenderer.RenderPass.MSAASample := fMSAASample;
    fRenderer.RenderPass.BufDepthON :=  DBCB.checked;
    fVCLWin.VulkanLink := fLinker;

    fRenderer.SelectON              := True;

    fRenderer.RenderPass.BuildStructure;

 //  RunComponentTests(fInstance);



    fScene        := TvgScene.Create(self);
    fScene.Linker := fLinker;
 //   fScene.ScreenDevice := fScreenDevice;
    fRenderer.Scene := fScene;
    fScene.ConnectRenderEngine(fRenderer) ;


    fToolManager:=TvgToolManager.create(self);
    fLinker.ToolManager := fToolManager;

    fToolManager.Linker   := fLinker;
    fToolManager.Scene    := fScene;
    fToolManager.Renderer := fRenderer;


    MessagesTxt.Lines.add('Build Instance complete');
end;

procedure TTestVulkan.Button2Click(Sender: TObject);
  //Var I:Integer;
begin
  If assigned(fToolManager) then
     FreeAndNil(fToolManager);

  if assigned(fScene) then
  Begin
     fScene.ClearScene;
     FreeAndNil(fScene);
  End;

  If assigned(fInstance) and fInstance.Active then
     fInstance.Active:=False;

  If assigned(fRenderer) then
    FreeAndNil(fRenderer);

  if assigned(fGP) then
    FreeandNil(fGP);

  If assigned(fLinker) then
    FreeAndNil(fLinker);

  if assigned(fVCLWin) then
    FreeandNil(fVCLWin);

  If assigned(fPhysicalDevice) then
    FreeAndNil(fPhysicalDevice);

  If assigned(fInstance) then
    FreeAndNil(fInstance);

   WType.Enabled :=True;

end;

procedure TTestVulkan.Button3Click(Sender: TObject);
begin
  If not assigned( fInstance) then exit;
  fInstance.BuildALLLayers;


end;

procedure TTestVulkan.Button4Click(Sender: TObject);
  Var TC : Integer;

begin


  If assigned(fRenderer) and (fRenderer.ClassType = TvgCommThread_RenderEngine) then
  Begin
    If TryStrToInt(ThreadC.Text,TC) then
       fRenderer.WorkerCount := TC;
  end;

Try
 //self.fRenderer.renderpass.


 MessagesTxt.lines.add('Activate Instancec')   ;

  If assigned(fInstance) then
    fInstance.Active := True;


 MessagesTxt.lines.add('Test for RenderDoc')   ;

 If IsRenderDocActive then
    MessagesTxt.lines.add('RenderDoc is ACTIVE')
 else
     MessagesTxt.lines.add('RenderDoc is INACTIVE');

Finally
 MessagesTxt.Lines.add('Enable Instance completed');
End;

end;

procedure TTestVulkan.Button5Click(Sender: TObject);
begin
  If not assigned( fInstance) then exit;
  fInstance.BuildALLExtensions;

  If not assigned(fPhysicalDevice) then exit;

  fPhysicalDevice.PhysicalDeviceName := 'Intel(R) UHD Graphics';
  fPhysicalDevice.DeviceSelect   := vgdsName;

  fLinker.ScreenDevice.BuildALLExtensions;

end;

procedure TTestVulkan.Button6Click(Sender: TObject);
  // Var I:Integer;
   //    N:TvgBaseObjectStore;
begin
  if NOT assigned(fLinker) then  exit;

  MessagesTxt.lines.Clear;
  if not assigned(fLinker) then exit;


  If assigned(fRenderer) then
  Begin
    If SceneResetCB.Checked then
      fRenderer.FlagRebuildALLFrames;
    fRenderer.TriggerWindowRepaint;
  End;

      MessagesTxt.Lines.add('Trigger Draw');

end;

procedure TTestVulkan.Button7Click(Sender: TObject);
   Var SLT : TvgSceneLoaderStorer_test;
       ObjStr:TvgObjectStore;
       I:Integer;
  //     B:Cardinal;

begin
  If not assigned(fScene) then exit;

  case TestRB.ItemIndex of
      0 : Begin
            if assigned(fScene) then
            Begin


                MessagesTxt.Lines.add('Test Scene Loaded');
            End;
          end ;
   else
           Begin
                SLT := TvgSceneLoaderStorer_test.Create(self);
                SLT.Scene := fScene;

                SLT.Mode := TestRB.ItemIndex;

                SLT.LoadScene;

                If fScene.SceneData.Count>0 then
                  For I:=0 to  fScene.SceneData.Count-1 do
                  Begin
                    ObjStr:= fScene.SceneData.Items[I] ;
                    If assigned(ObjStr) then
                    Begin

                     // DumpBindingDebug(ObjStr,  MessagesTxt.Lines);

                    End;
                  End;


                FreeAndNil(SLT);

                BuildShaders;

                MessagesTxt.Lines.add(Format('Test Scene Loaded #%d',[TestRB.ItemIndex]));

             //   MessagesTxt.lines.add(fScene.GetSceneGLSLHeaders);

           End;
  end; //case

  MessagesTxt.Lines.add('Scene loaded');

end;

procedure TTestVulkan.Button8Click(Sender: TObject);
begin
  If assigned(fVCLWin) then  fVCLWin.Active:=True
end;

procedure TTestVulkan.Button9Click(Sender: TObject);
  Var S:String;
begin
  S:= Trim(SupportFolderEDT.Text)  ;

  If s='' then
     S:= GetCurrentDir;

  If (S<>'') and DirectoryExists(S) then
     DataFolderDlg.DefaultFolder:= S;

 If DataFolderDlg.Execute then
 Begin
    S:= DataFolderDlg.FileName;
    SupportFolderEDT.Text  := S;


 end;

end;

procedure TTestVulkan.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Button2Click(nil);
end;

procedure TTestVulkan.FormCreate(Sender: TObject);
begin
  fMSAASample := COUNT_08_BIT;//COUNT_01_BIT;
end;

procedure TTestVulkan.FormDestroy(Sender: TObject);
begin
 // If assigned(vgWindowVCL1) then
  //   vgWindowVCL1.Active:=False;
end;

procedure TTestVulkan.FormShow(Sender: TObject);
begin
 // vgWindowVCL1.Active:=True;

 ExecutableFolderPath:=  ExtractFilePath(application.exename);

 SupportFolderEDT.text := ExecutableFolderPath;

 (*
 If AutoStartCB.Checked then
 Begin
   Button1Click(self);
   If assigned(fInstance) then
     fInstance.Active:=True;
 End;
 *)
end;

procedure TTestVulkan.HandleLinkerMessages(aList: TStringList);
begin
  MessagesTxt.Lines.Clear;
  if not assigned(aList) then exit;

  MessagesTxt.Lines.Assign(aList);

  PostMessage(MessagesTxt.Handle, EM_LINESCROLL, 0, MessagesTxt.Lines.Count);
end;

procedure TTestVulkan.HandleMsg(const aLabel:String; const ThreadCount, aMsgCount: Integer);
begin
  MessagesTxt.Lines.Add(Format('%s ; Thread ID : %d ; Remaining Task Count: %d',[aLabel, ThreadCount, aMsgCount]));
end;

procedure TTestVulkan.MSAACBClick(Sender: TObject);
begin

  If MSAACB.Checked then
     fMSAASample := COUNT_08_BIT
  else
     fMSAASample := COUNT_01_BIT;

end;

procedure TTestVulkan.Panel1MouseMove(Sender: TObject; Shift: TShiftState; X,  Y: Integer);
begin
  //
end;

procedure TTestVulkan.vgWindowLink1RenderPassBuild(Sender: TvgRenderPass);
begin
  Sender.ClearStructure;
end;

end.
