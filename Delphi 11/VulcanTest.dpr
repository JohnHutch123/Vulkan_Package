program VulcanTest;

uses
  FastMM5 in '..\FastMM5\FastMM5.pas',
  Vcl.Forms,
  VulkanTestMF in 'VulkanTestMF.pas' {Form8},
  Vulkan_Components in 'RunTime_Src\Vulkan_Components.pas',
  Vulkan_WindowVCL in 'RunTime_Src\Vulkan_WindowVCL.pas',
  VulkanTestDM in 'VulkanTestDM.pas' {DataModule2: TDataModule},
  VulkanGraphicsEdit in 'VulkanGraphicsEdit.pas' {VGEditor},
  TestVulkanTestMF in 'TestVulkanTestMF.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm8, Form8);
  Application.CreateForm(TDataModule2, DataModule2);
  Application.CreateForm(TVGEditor, VGEditor);
  Application.Run;
end.
