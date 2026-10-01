unit VulkanPkg_DesignersVCL;

interface

  Uses
  System.Classes,
  Vulkan_WindowVCL;



procedure Register;


implementation


procedure Register;
begin

   RegisterComponents('Vulkan Graphics', [TvgWindowVCL ]);

 //  RegisterComponentEditor (TvcInstance, TvcInstanceEditor);

end;

end.
