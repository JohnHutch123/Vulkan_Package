unit TestVulkanDynamicRendering;

interface

uses
  TestFramework,
  System.SysUtils,
  System.Classes,
  Vulkan,
  Vulkan_Components,
  Vulkan_Components_Lookups;

type
  TTestDynamicRenderingFlags = class(TTestCase)
  published
    procedure TestInstanceDefaultsToDynamicRendering;
    procedure TestInstanceDynamicRenderingBumpsAPIVersion;
    procedure TestDeviceDefaultsToDynamicRenderingON;
    procedure TestDeviceDynamicRenderingONSyncsFeatures;
    procedure TestRenderPassHandleStartsNull;
  end;

implementation

procedure TTestDynamicRenderingFlags.TestInstanceDefaultsToDynamicRendering;
var
  Inst: TvgInstance;
begin
  Inst := TvgInstance.Create(nil);
  try
    CheckTrue(Inst.DynamicRendering, 'Instance.DynamicRendering should default True');
    CheckTrue(Inst.APIVersion = VG_API_VERSION_1_3, 'Instance.APIVersion should default to 1.3');
  finally
    Inst.Free;
  end;
end;

procedure TTestDynamicRenderingFlags.TestInstanceDynamicRenderingBumpsAPIVersion;
var
  Inst: TvgInstance;
begin
  Inst := TvgInstance.Create(nil);
  try
    Inst.DynamicRendering := False;
    Inst.APIVersion := VG_API_VERSION_1_2;
    CheckTrue(Inst.APIVersion = VG_API_VERSION_1_2, 'APIVersion 1.2 should stick while DynamicRendering is off');
    Inst.DynamicRendering := True;
    CheckTrue(Inst.DynamicRendering, 'DynamicRendering should be enabled');
    CheckTrue(Inst.APIVersion = VG_API_VERSION_1_3,
              'Enabling DynamicRendering must bump APIVersion to 1.3');
  finally
    Inst.Free;
  end;
end;

procedure TTestDynamicRenderingFlags.TestDeviceDefaultsToDynamicRenderingON;
var
  Dev: TvgLogicalDevice;
begin
  Dev := TvgLogicalDevice.Create(nil);
  try
    CheckTrue(Dev.DynamicRenderingON, 'LogicalDevice.DynamicRenderingON should default True');
    CheckFalse(Dev.IsDynamicRenderingActive,
               'IsDynamicRenderingActive requires Features.DynamicRendering as well');
  finally
    Dev.Free;
  end;
end;

procedure TTestDynamicRenderingFlags.TestDeviceDynamicRenderingONSyncsFeatures;
var
  Dev: TvgLogicalDevice;
begin
  Dev := TvgLogicalDevice.Create(nil);
  try
    CheckTrue(Assigned(Dev.Features), 'LogicalDevice.Features must exist');
    Dev.DynamicRenderingON := False;
    CheckFalse(Dev.DynamicRenderingON, 'DynamicRenderingON False should stick');
    CheckFalse(Dev.Features.DynamicRendering, 'Features.DynamicRendering should follow the device flag');
    Dev.DynamicRenderingON := True;
    CheckTrue(Dev.DynamicRenderingON, 'DynamicRenderingON True should stick');
    CheckTrue(Dev.Features.DynamicRendering,
              'DynamicRenderingON True must request Features.DynamicRendering');
    CheckTrue(Dev.IsDynamicRenderingActive,
              'ON plus Features.DynamicRendering should report active');
  finally
    Dev.Free;
  end;
end;

procedure TTestDynamicRenderingFlags.TestRenderPassHandleStartsNull;
var
  RP: TvgRenderPass;
begin
  RP := TvgRenderPass.Create(nil);
  try
    CheckTrue(RP.RenderPassHandle = VK_NULL_HANDLE,
              'RenderPass handle must stay NULL until classic vkCreateRenderPass');
    CheckTrue(RP.FrameBufferHandles[0] = VK_NULL_HANDLE,
              'Framebuffers must be absent until FrameBuffersSetUp');
    CheckFalse(RP.UsesDynamicRendering,
               'A standalone RenderPass has no engine, so it cannot use dynamic rendering');
  finally
    RP.Free;
  end;
end;

initialization
  RegisterTest(TTestDynamicRenderingFlags.Suite);

end.
