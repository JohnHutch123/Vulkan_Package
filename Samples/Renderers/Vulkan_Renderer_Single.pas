(******************************************************************************
 *                                 vgVulkan                                  *
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

unit Vulkan_Renderer_Single;

interface

{$INCLUDE VulkanPackage.inc}

uses
  {$IFDEF FASTMM5}
  FastMM5,
  {$ENDIF}
  System.SysUtils,
  System.Generics.Collections,   //MUST STAY HERE
  System.Generics.Defaults,
  System.Classes,                //MUST STAY HERE
  System.Math,
  System.SyncObjs,
  typinfo,
  Vulkan,
  PasVulkan.Math,
  PasVulkan.Collections,
  PasVulkan.Framework,
  Vulkan_Components,
  Vulkan_Assert,
  Vulkan_Components_Lookups,
  Vulkan_Components_Descriptors,
  Vulkan_Components_Nodes,
  Vulkan_PixelInfo,
  Vulkan_Components_Scene_Renderer  ;

Type


 //simple renderer which uses a single worker and processes ALL tasks in the MainThread

  TvgRenderEngine_Single  =  class(TvgRenderEngine)

  Protected
     fCurrentSubPass   : Integer;

    Procedure BuildAndSetUpWorkers;   override;
    //used to create set of workers to handle rendering

    //tidy up

  Public

    constructor Create(AOwner: TComponent); Override;

    Procedure AddSceneRenderCommands(ImageIndex:TvkUint32; aFrame:TvgFrame; aSubPass : TvkUint32);  Override;
    Procedure CreateRenderPass;            Override;

  Published

  end;

implementation

{ TvgRenderEngine_Simple }

procedure TvgRenderEngine_Single.AddSceneRenderCommands(ImageIndex:TvkUint32; aFrame:TvgFrame; aSubPass : TvkUint32);
  Var     RW             : TvgRenderWorker;
          aTask          : TvgRenderTask;
          I            : Integer;
          SP:TvgSubPass;

Begin
      CustomAssert(assigned(fLinker),'Window Link not connected', Self);
      CustomAssert(assigned(fRenderPass),'RenderPass not created',Self);

      If not assigned(fBaseScene) or (fBaseScene.GetObjectCount=0) then exit;


      RW := fRenderWorkers.Items[0];

      CustomAssert(assigned(RW),'Render Worker not created',Self);
//      VulkanCommands := fLinker.ScreenDevice.VulkanDevice.Commands ;

      FillChar(aTask,SizeOf(aTask),#0);    //important
//      aTask.Linker            := fLinker;
      aTask.Frame             := aFrame;

      aTask.RenderPassHandle  := fRenderPass.RenderPassHandle;
      aTask.SubPassIndex      := aSubPass;  //current pass index
      aTask.TaskJob           := TM_NONE;
      aTask.UploadData        := True;
      aTask.UploadResourceData:= True;
      aTask.GlobalRes         := fGlobalRes ;
      aTask.FrameBufferHandle := fRenderPass.FrameBufferHandles[ImageIndex];


      If Not RW.Active then
         RW.Active            := True;     //Setup the Worker


      If fRenderPass.SubPasses.Count>0 then
        For I :=0 to fRenderPass.SubPasses.Count-1 do
        begin
          SP := fRenderPass.SubPasses.Items[I];
          If Assigned(SP) then
          Begin
            SP.UploadGraphicPipeDescriptorSet(aTask,RW) ;
            SP.UpLoadRenderNodeData(aTask, RW) ;
          End;
        end;

      if assigned(fLinker) and fLinker.MsgON then
         fLinker.AddMsgToList('Begin Recording');

      aTask.TaskJob    := TM_BEGIN_RECORDING_FRAME;
      RW.CompleteTask(aTask);

      If fRenderPass.SubPasses.Count>0 then
        For I :=0 to fRenderPass.SubPasses.Count-1 do
        begin
          SP := fRenderPass.SubPasses.Items[I];
          If Assigned(SP) then
            SP.AddObjectStoreToCommand(aTask, RW) ;
        end;


      aTask.TaskJob    := TM_END_RECORDING_FRAME; //end recording the SECONDARY worker buffer
      RW.CompleteTask(aTask);

      if assigned(fLinker) and fLinker.MsgON then
         fLinker.AddMsgToList('End Recording');

      aTask.TaskJob    := TM_EXECUTE_SECONDARY;   //execute SECONDARY buffer on PRIMARY frame buffer
      RW.CompleteTask(aTask);

      aTask.TaskJob    := TM_RESET;
      RW.CompleteTask(aTask);

End;


procedure TvgRenderEngine_Single.BuildAndSetUpWorkers;
  Var RW : TvgrenderWorker;
begin
  If fRenderWorkers.count=1 then exit;

  RW          := TvgRenderWorker.Create(0);
  RW.Renderer := Self ;

  RW.Active:=True;

  fRenderWorkers.add(RW);
end;

constructor TvgRenderEngine_Single.Create(AOwner: TComponent);
begin
  inherited;

  fRenderWorkerCount := 1;

end;

procedure TvgRenderEngine_Single.CreateRenderPass;
begin
  If assigned(fRenderPass) then exit;

  fRenderPass := TvgRenderPass.Create(self);

end;



Initialization


Finalization


end.
