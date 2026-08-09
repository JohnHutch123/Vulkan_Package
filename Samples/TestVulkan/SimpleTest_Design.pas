unit SimpleTest_Design;

interface

uses
 // FastMM5,
  System.SysUtils,
  System.Generics.Collections,   //MUST STAY HERE
  System.Generics.Defaults,
  System.Classes,
  Vcl.Dialogs,
//  Vulkan,
//  PasVulkan.Math,
//  Vulkan_Components_Lookups,
//  Vulkan_Components,
//  Vulkan_Components_Nodes,
//  Vulkan_Components_Resources,
  Vulkan_Renderer_Single;
//  Vulkan_Renderer_CommThread,
//  Vulkan_Render_Tests;                //MUST STAY HERE


procedure Register;

implementation

procedure Register;
Begin
   RegisterComponents('Vulkan Graphics', [  TvgRenderEngine_Single
                                        //    TvgCommThread_RenderEngine,
                                            ]);
                                         //   TvgCommandPool]);

 //  RegisterComponentEditor (TvgRenderEngine_Simple,      TvgRenderEngineEditor);
 //  RegisterComponentEditor (TvgRenderEngine_CommThread,  TvgRenderEngineEditor);


End;


end.
