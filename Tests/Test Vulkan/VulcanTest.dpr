program VulcanTest;

{$INCLUDE VulkanPackage.inc}

uses
  {$IFDEF FASTMM5}
  FastMM5,
  {$ENDIF }
  Vcl.Forms,
  VulkanTestMF in 'VulkanTestMF.pas' {TestVulkan},
  Vulkan_Render_Tests in 'Vulkan_Render_Tests.pas',
  Vulkan_Renderer_Single,
  Vulkan_Components_Descriptors,
  Vulkan_Components,
  Vulkan_Components_Lookups,
  Vulkan_Components_DataStore,
  Vulkan_WorldAxes,
  Vulkan_Components_Camera,
  Vulkan_WindowVCL,
  Vulkan_Components_PointerValidation,
  Vulkan_Components_VulkanAPI,
  Vulkan_Components_Scene_Renderer,
  Vulkan_Components_Compute,
  Vulkan_HUD;

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TTestVulkan, TestVulkan);
  Application.Run;
end.
