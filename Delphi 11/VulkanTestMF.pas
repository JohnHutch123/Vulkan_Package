unit VulkanTestMF;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vulkan,
  Vulkan_Components, Vulkan_WindowVCL,
  Data.DB, Datasnap.DBClient, Datasnap.Provider,
  Data.Win.ADODB,  Vcl.StdCtrls, Vcl.ComCtrls,
  Vcl.Buttons, VulkanTestDM;

type
  TForm8 = class(TForm)
    Button2: TButton;
    Button3: TButton;
    StatusBar1: TStatusBar;
    BitBtn2: TBitBtn;
    Edit1: TEdit;
    bitBtn3:TBitBtn;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button5Click(Sender: TObject);
    procedure BitBtn1Click(Sender: TObject);
    procedure BitBtn2Click(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure BitBtn3Click(Sender: TObject);
  private
    { Private declarations }
    fInstance : TvgInstance;
    fDevice   : TvgDevice;
    fSurface  : TvgSurface;
    fVCLWin   : TvgWindowVCL ;
    fGP       : TvgGraphicsPipeline;
  //  fSwapChain: TvgSwapChain;
  //  fRenderEng : TvgRenderEngine;
  public
    { Public declarations }
  end;

var
  Form8: TForm8;

implementation

{$R *.dfm}

procedure TForm8.BitBtn1Click(Sender: TObject);
//  Var W:TWriter;
   //   R:TReader;
begin
  //
end;

procedure TForm8.BitBtn2Click(Sender: TObject);
begin
  If not assigned(fSurface) or Not fSurface.Active   then exit;

  If assigned(fVCLWin) then
  Begin
    fVCLWin.SetBounds(fVCLWin.Left,fVCLWin.Top, fVCLWin.Width+10, fVCLWin.Height+10);

  End;

end;

procedure TForm8.BitBtn3Click(Sender: TObject);
begin
  If assigned(fInstance) and fInstance.active then
     fInstance.Active:=False;
end;

procedure TForm8.Button1Click(Sender: TObject);
begin
    fInstance := TvgInstance.Create(self);

    fInstance.BuildALLEXtensions;
    fInstance.BuildALLLayers;

    fSurface := TvgSurface.Create(self);
    fSurface.Instance := fInstance;

    fVCLWin        := TvgWindowVCL.Create(self) ;
    fVCLWin.Parent := Self;
    fVCLWin.Top    := 40;
    fVCLWin.Left   := 500;
    fVCLWin.Width  := 260;
    fVCLWin.Height := 200;

    fVCLWin.Surface:= fSurface;
    //fSurface.VulkanWindow :=  (fVCLWin as IvgVulkanWindow);

    fDevice := TvgDevice.Create(self);
    fDevice.Instance:= fInstance;
    fDevice.Surface := fSurface;
    fDevice.BuildALLExtensions;

//    fSwapChain := TvgSwapChain.Create(self);
//    fSwapChain.Device:=fDevice;

//    fSwapChain.BuildALLImagesColorSpaces;
//    fSwapChain.BuildALLPresentationModes;

    fGP       := TvgGraphicsPipeline.Create(self);
    fGP.Device:=fDevice;



end;

procedure TForm8.Button2Click(Sender: TObject);
begin
  If assigned(fInstance) and fInstance.Active then
     fInstance.Active:=False;

//  if Assigned(fRenderEng) then
//     FreeAndNil(fRenderEng);

//  if assigned(fSwapChain) then
//    FreeandNil(fSwapChain);
  if assigned(fGP) then
    FreeandNil(fGP);

  if assigned(fVCLWin) then
    FreeandNil(fVCLWin);
  If assigned(fDevice) then
    FreeAndNil(fDevice);
  If assigned(fSurface) then
    FreeAndNil(fSurface);
  If assigned(fInstance) then
    FreeAndNil(fInstance);
end;

procedure TForm8.Button3Click(Sender: TObject);
begin
  If not assigned( fInstance) then exit;
  fInstance.BuildALLLayers;
end;

procedure TForm8.Button4Click(Sender: TObject);
begin

 // If assigned(fInstance) then
 //   fInstance.Active := True;
 (*
  If assigned(fSurface) then
     fSurface.Active:=True;

  if assigned(fSwapChain) then
  Begin
     fSwapChain.Active:=True;
     fSwapChain.VulkanPaint;
  End;

  If assigned(fDevice) then
     fDevice.Active:=True;

 *)
 // If assigned(fVCLWin) then
 //    fVCLWin.Invalidate;

//  If assigned(fSwapChain)

 // GP1.Active:=True;
end;

procedure TForm8.Button5Click(Sender: TObject);
begin
  If not assigned( fInstance) then exit;
  fInstance.BuildALLExtensions;
end;

procedure TForm8.FormShow(Sender: TObject);
begin
  //
end;

end.
