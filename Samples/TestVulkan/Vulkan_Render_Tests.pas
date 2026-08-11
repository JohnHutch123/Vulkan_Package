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
unit Vulkan_Render_Tests;

interface

{$INCLUDE VulkanPackage.inc}

uses
 // FastMM5,
  System.SysUtils,
  System.Generics.Collections,   //MUST STAY HERE
  System.Generics.Defaults,
  System.Classes,
  Vulkan,
  PasVulkan.Math,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_Nodes,
  Vulkan_Components_Descriptors,
  Vulkan_Renderer_Single,
//  Vulkan_Renderer_CommThread,
  Vulkan_Assert,
  Vulkan_Components_DataStore,
  Vulkan_Components_Camera,
  Vulkan_Components_Scene_Renderer;                //MUST STAY HERE

Var
  UboOn : Boolean = True;

Type


 TvgSceneLoaderStorer_Test = Class(TvgSceneLoaderStorer)
  private
    procedure SetMode(const Value: Integer);

 //Descendant will load /Store data To/From the Scene using the local format
   protected
     fMode : Integer;

   public

     Procedure LoadScene; Override;
     //load scene into TvgScene
     Procedure StoreScene; Override;

     Property Mode:Integer read fMode write SetMode;
 End;



implementation



{ TvgSceneLoaderStorer_Test }


procedure TvgSceneLoaderStorer_Test.LoadScene;
  Var ObjStore : TvgObjectStore;
   //   C:TvgCamera;

    //  aPosition,
   //   aTarget,
   //   aUpVector: TpvVector3;
   //   aFOV: Single;
   //   aNear: Single;
  //    aFar: Single;
  //    aAspect: Single;

  Obj,Obj1,Obj2 : TvgObject;



   Procedure AddSimpleTriangle;
   Begin

      If Obj.AddVertex<>-1 then
      Begin
        Obj.SetVertexPosition( 0.0,-0.5,0.1) ;
        Obj.SetVertexColor( 1.0, 0.0, 0.0) ;
      End;

      If Obj.AddVertex<>-1 then
      Begin
        Obj.SetVertexPosition( 0.5,0.5,0.1) ;
        Obj.SetVertexColor( 0.0,1.0,0.0) ;
      End;

      If Obj.AddVertex<>-1 then
      Begin
        Obj.SetVertexPosition(-0.5,0.5,0.1) ;
        Obj.SetVertexColor( 0.0,0.0,1.0) ;
      End;

   End;


begin

   if Not assigned(fScene) then exit;

   If fScene.Load_Begin then
   Begin
   Try
     ObjStore:=self.AddObjectStore  ;


   case fMode of
     0 : Begin

         End;
     1 : Begin


            ObjStore.Topology        := TRIANGLE_LIST;
            ObjStore.InstanceDataON  := true;
            ObjStore.ObjectSelectON  := True;

         //  ObjStore.InitializeIndexBuffer(itUInt32);
            ObjStore.BaseVertName := 'TestTriangleWithData';
            ObjStore.BaseFragName := 'TestTriangleWithData';

            ObjStore.SetupVertexAttributes( [vdtPosition, vdtColor]);
            ObjStore.SetUpInstanceAttributes( [idtObjID]);

            Obj := ObjStore.AddObject;   //no index data

            // Define vertex attributes for the vertex binding: position (loc0) + color (loc1)
           // DS.AddVertexAttributes(vBinding, [vdtPosition, vdtColor], [0, 1]);

            Obj.SetUpObjectID;

            // Define instance attributes for the object's instance binding: objID + instance color
            // objID uses uvec2 (two uints) at location 2, color at location 3

            // Allocate vertex storage and instance storage for this object's bindings
            Obj.AllocateVertices( 6);    // 6 vertices for 2 triangles

           AddSimpleTriangle;
           AddSimpleTriangle;

         End;

     2 : Begin

            AddDescriptor_Texture('SimpleText', 'Image1.bmp');


            ObjStore.Topology        := TRIANGLE_LIST;
            ObjStore.InstanceDataON  := true;
            ObjStore.ObjectSelectON  := True;

           ObjStore.BaseVertName := 'TestTextureRect';
           ObjStore.BaseFragName := 'TestTextureRect';

            ObjStore.SetUpVertexAttributes( [vdtPosition, vdtColor, vdtTexCoord]);
            ObjStore.SetUpInstanceAttributes( [idtObjID]);

            Obj1 := ObjStore.AddObject;
            Obj2 := ObjStore.AddObject;

            Obj1.SetUpObjectID;
            Obj2.SetUpObjectID;

            // Allocate vertex storage and instance storage for this object's bindings
            Obj1.AllocateVertices( 4);
            Obj2.AllocateVertices( 4);

         //obj1

            If Obj1.IncCurrentVertex then
            Begin
              Obj1.SetVertexPosition(-0.75,-0.75,0.2);
              Obj1.SetVertexColor(1.0,1.0,1.0);
              Obj1.SetVertexTexCoord(0.0,0.0) ;
            End;

            If Obj1.IncCurrentVertex then
            Begin
              Obj1.SetVertexPosition(0.75,-0.75,0.22);
              Obj1.SetVertexColor(1.0,1.0,1.0);
              Obj1.SetVertexTexCoord(0.0,1.0) ;
            End;

            If Obj1.IncCurrentVertex then
            Begin
              Obj1.SetVertexPosition(0.75,0.75,0.25);
              Obj1.SetVertexColor(1.0,1.0,1.0);
              Obj1.SetVertexTexCoord(1.0,1.0) ;
            End;

            If Obj1.IncCurrentVertex then
            Begin
              Obj1.SetVertexPosition(-0.75,0.75,0.18);
              Obj1.SetVertexColor(1.0,1.0,1.0);
              Obj1.SetVertexTexCoord(1.0,0.0) ;
            End;

            Obj1.AddIndex(0, 1, 2);
            Obj1.AddIndex(2, 3, 0);

       //obj2
            If Obj2.IncCurrentVertex then
            Begin
              Obj2.SetVertexPosition(0.0,-1.0,0.52);
              Obj2.SetVertexColor(1.0,1.0,1.0);
              Obj2.SetVertexTexCoord(0.0,0.0) ;
            End;

            If Obj2.IncCurrentVertex then
            Begin
              Obj2.SetVertexPosition(1.0,0.0,0.55);
              Obj2.SetVertexColor(1.0,1.0,1.0);
              Obj2.SetVertexTexCoord(0.0,1.0) ;
            End;

            If Obj2.IncCurrentVertex then
            Begin
              Obj2.SetVertexPosition(0.0,1.0,0.48);
              Obj2.SetVertexColor(1.0,1.0,1.0);
              Obj2.SetVertexTexCoord(1.0,1.0) ;
            End;

            If Obj2.IncCurrentVertex then
            Begin
              Obj2.SetVertexPosition(-1.0,0.0,0.52);
              Obj2.SetVertexColor(1.0,1.0,1.0);
              Obj2.SetVertexTexCoord(1.0,0.0) ;
            End;

            Obj2.AddIndex(0, 1, 2);
            Obj2.AddIndex(2, 3, 0);

         End;

     3:  Begin
     (*
           NLT := TvgSceneData_TextureTriangle.Create;
           AddTextureRectangle;

           fScene.AddSceneData(NLT);

           NLT.TransferDataToScene(fScene, True);      //will setup GraphicPipeline/s during the transfer
           //will setup GraphicPipelines
           NLT.Free;
       *)
         End;

     4:  Begin
     (*
           NLT := TvgSceneData_TextureTriangle.Create;

           for I := 0 to 99 do

              AddTextureRectangle;

           fScene.AddSceneData(NLT) ;
         //  NLT.TransferDataToScene(fScene, True);      //will setup GraphicPipeline/s during the transfer
           //will setup GraphicPipelines
         //  NLT.Free;

         *)
         End;

   end;


 Finally
   fScene.Load_End;
 end;

 End;

 //  fScene.ReConnectRenderEngines;
end;

{ TvgSceneDataLoader }

procedure TvgSceneLoaderStorer_Test.SetMode(const Value: Integer);
begin
  fMode := Value;
end;

procedure TvgSceneLoaderStorer_Test.StoreScene;
begin
  //do nothing
end;

Initialization


Finalization


end.

