unit VulkanPkg_DesignersVCL;

interface

  Uses
  System.SysUtils,
  System.Classes,
  DesignIntf,
  DesignEditors,
//  Vcl.Dialogs,
  Vulkan_WindowVCL;



procedure Register;


implementation


procedure Register;
begin

   RegisterComponents('Vulkan Graphics', [TvgWindowVCL ]);

 //  RegisterComponentEditor (TvcInstance, TvcInstanceEditor);

end;

end.
