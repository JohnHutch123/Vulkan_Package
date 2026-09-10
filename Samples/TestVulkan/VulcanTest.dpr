program VulcanTest;

{$INCLUDE VulkanPackage.inc}

uses
  {$IFDEF FASTMM5}
  FastMM5,
  {$ENDIF }
  Vcl.Forms,
  VulkanTestMF in 'VulkanTestMF.pas' {TestVulkan},
  Vulkan_Render_Tests in 'Vulkan_Render_Tests.pas',
  Vulkan_Components_Scene_Renderer in '..\..\RunTime_Src\Vulkan_Components_Scene_Renderer.pas',
  Vulkan_LoaderStorer_glTF in 'Vulkan_LoaderStorer_glTF.pas',
  Vulkan_Renderer_CommThread in 'Vulkan_Renderer_CommThread.pas',
  Vulkan_Renderer_Single in 'Vulkan_Renderer_Single.pas',
  Vulkan_Components_Descriptors in '..\..\RunTime_Src\Vulkan_Components_Descriptors.pas',
  Vulkan_Components in '..\..\RunTime_Src\Vulkan_Components.pas',
  Vulkan_Components_Lookups in '..\..\RunTime_Src\Vulkan_Components_Lookups.pas',
  Vulkan_Components_DataStore in '..\..\RunTime_Src\Vulkan_Components_DataStore.pas',
  Vulkan_Components_Camera in '..\..\RunTime_Src\Vulkan_Components_Camera.pas',
  Vulkan_WindowVCL in '..\..\RunTime_Src\Vulkan_WindowVCL.pas',
  Vulkan_Components_PointerValidation in '..\..\RunTime_Src\Vulkan_Components_PointerValidation.pas',
  Vulkan_Components_VulkanAPI in '..\..\RunTime_Src\Vulkan_Components_VulkanAPI.pas',
  Vulkan_Components_ShaderBuilder in '..\..\RunTime_Src\Vulkan_Components_ShaderBuilder.pas',
  Vulkan_Components_Particles in '..\..\RunTime_Src\Vulkan_Components_Particles.pas',
  Vulkan_Components_Compute in '..\..\RunTime_Src\Vulkan_Components_Compute.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TTestVulkan, TestVulkan);
  Application.Run;
end.
