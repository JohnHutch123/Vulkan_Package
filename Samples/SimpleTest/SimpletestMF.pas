unit SimpletestMF;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Buttons,
  Vcl.ExtCtrls,
  Generics.Collections,
  Generics.Defaults,
  System.IOUtils,
  Vulkan,
  PasVulkan.Math,{PasVulkan.Application,}
  PasVulkan.Math.double,{PasVulkan.Application,}

  Vulkan_Components,
  Vulkan_Components_Nodes,
  Vulkan_Components_Descriptors,
  Vulkan_Renderer_Single,
  Vulkan_Components_Scene_Renderer,
  Vulkan_Components_DataStore,
  Vulkan_Components_ShaderCompiler,
  Vulkan_WindowVCL;


type
  TForm8 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }

    fInstance : TvgInstance;
    fPhysicalDevice   : TvgPhysicalDevice;
    fScreenDevice     : TvgScreenRenderDevice;
    fLinker  : TvgLinker;
    fVCLWin   : TvgWindowVCL ;
    fGP       : TvgGraphicPipeline;
    fRenderer   : TvgRenderEngine;
    fScene      : TvgScene;
    fToolManager:TvgToolManager;


  public
    { Public declarations }
  end;

var
  Form8: TForm8;

implementation

{$R *.dfm}

procedure TForm8.Button1Click(Sender: TObject);
  Var
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
  //  WType.Enabled:=False;
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

    //Ask the device for the dynamic rendering feature either way: the
    //renderer's RenderingMode below picks the path.
    fScreenDevice.DynamicRenderingON := True;
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

    fLinker.HUDEnabled := True;
    fLinker.HUDPanelOpaque := True;

    fLinker.ScreenDevice  := fScreenDevice;;   //add winlink here to trigger RenderToScreen

  //  fLinker.BuildFeaturesStructure;

  //  RunComponentTests(fInstance);

    Case WType.ItemIndex of
       0:Begin
          fVCLWin        := TvgWindowVCL.Create(self) ;

          fVCLWin.Parent := Self;
          fVCLWin.Top    := 40;
          fVCLWin.Left   := 500;
          fVCLWin.Width  := 600;
          fVCLWin.Height := 600;
          fVCLWin.Color  := clBlack;

          fVCLwin.Cursor := crCross;

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

      End;
      1: Begin
           fRenderer   := TvgCommThread_RenderEngine.Create(Self);

           If TryStrToInt(ThreadC.Text,TC) then
              fRenderer.WorkerCount := TC;

         End;
    End;

    fRenderer.Linker                := fLinker;
    fRenderer.SelectMode            := smStorageBuffer;
    fRenderer.RenderPass.MSAASample := fMSAASample;
    fRenderer.RenderPass.BufDepthON := DBCB.checked;
    fRenderer.ShaderUseDouble       := True;

    //Dynamic or Standard - chosen here, before anything is enabled.
    case RenderPathRB.ItemIndex of
      1: fRenderer.RenderingMode := rmStandard;
    else
      fRenderer.RenderingMode := rmDynamic;
    end;

    fVCLWin.VulkanLink   := fLinker;

    fRenderer.RenderPass.BuildStructure;


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

    fScene.Cameras.AddBaseCamera('Default') ;

    fToolManager.ToolMode   :=  TMM_CAMERA ;
    fToolManager.ActionMode := TAM_CAMERA_ORBIT;
    fToolManager.OnWorkPlaneChanged := WorkPlaneChanged;
    CameraPlaneCBClick(nil);


    MessagesTxt.Lines.add('Build Instance complete');
end;

end.
