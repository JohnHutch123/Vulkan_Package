program DynamicRenderingTest;

{$APPTYPE CONSOLE}

{ The render-path decision behind dynamic rendering, without a Vulkan device.

  A renderer records either with vkCmdBeginRendering (rmDynamic) or inside a
  classic VkRenderPass (rmStandard).  What this covers is every input to that
  choice that can be exercised on the CPU:

    - the defaults on the instance, device and renderer;
    - switching RenderingMode between Dynamic and Standard before enabling,
      and ActiveRenderingMode reporting the path that would really be used;
    - each reason rmDynamic falls back to Standard: no linker, no screen
      device, the device's DynamicRenderingON request off, and a render pass
      with more than one subpass (dynamic rendering has no NextSubpass);
    - the device reporting only its request before a Vulkan device exists;
    - a standalone render pass having no handle and no dynamic path.

  Whether the device really GRANTED the feature, the latch taken in
  SetEnabled, and the recording itself need a GPU: DynamicRenderingGPUTest
  covers those. }

uses
  System.SysUtils,
  Vulkan,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_Scene_Renderer;

var
  Failures : Integer = 0;

procedure Check(const Name: string; Got, Expect: Boolean);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-58s %s', [Name, BoolToStr(Got, True)]))
  else
  begin
    Writeln(Format('  FAIL %-58s got %s expected %s',
      [Name, BoolToStr(Got, True), BoolToStr(Expect, True)]));
    Inc(Failures);
  end;
end;

function ModeName(M: TvgRenderingMode): string;
begin
  case M of
    rmDynamic  : Result := 'rmDynamic';
    rmStandard : Result := 'rmStandard';
  else
    Result := '?';
  end;
end;

procedure CheckMode(const Name: string; Got, Expect: TvgRenderingMode);
begin
  if Got = Expect then
    Writeln(Format('  ok   %-58s %s', [Name, ModeName(Got)]))
  else
  begin
    Writeln(Format('  FAIL %-58s got %s expected %s',
      [Name, ModeName(Got), ModeName(Expect)]));
    Inc(Failures);
  end;
end;

// ---------------------------------------------------------------------------
procedure TestDefaults;
var
  Inst : TvgInstance;
  Dev  : TvgLogicalDevice;
  Eng  : TvgRenderEngine;
begin
  Writeln('--- defaults ---');

  Inst := TvgInstance.Create(nil);
  try
    Check('instance DynamicRendering on', Inst.DynamicRendering, True);
    Check('instance API version is 1.3', Inst.APIVersion = VG_API_VERSION_1_3, True);
  finally
    Inst.Free;
  end;

  Dev := TvgLogicalDevice.Create(nil);
  try
    Check('device DynamicRenderingON on', Dev.DynamicRenderingON, True);
    // The request alone is not "active": Features.DynamicRendering is only
    // set when the device is set up (SetUpDynamicRendering).
    Check('device not active before features are requested',
          Dev.IsDynamicRenderingActive, False);
  finally
    Dev.Free;
  end;

  Eng := TvgRenderEngine.Create(nil);
  try
    CheckMode('renderer RenderingMode defaults to Dynamic', Eng.RenderingMode, rmDynamic);
    Check('renderer starts inactive', Eng.Active, False);
  finally
    Eng.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestDeviceRequest;
var
  Dev : TvgLogicalDevice;
begin
  Writeln('--- device request, before a Vulkan device exists ---');

  Dev := TvgLogicalDevice.Create(nil);
  try
    Dev.DynamicRenderingON := False;
    Check('ON False sticks', Dev.DynamicRenderingON, False);
    Check('Features.DynamicRendering follows it off', Dev.Features.DynamicRendering, False);
    Check('not active while off', Dev.IsDynamicRenderingActive, False);

    Dev.DynamicRenderingON := True;
    Check('ON True sticks', Dev.DynamicRenderingON, True);
    Check('Features.DynamicRendering follows it on', Dev.Features.DynamicRendering, True);
    // With no Vulkan device yet there is nothing to have been granted, so
    // the request is all that can be reported.
    Check('request reported as active with no device yet', Dev.IsDynamicRenderingActive, True);
  finally
    Dev.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestSwitchWithoutDevice;
var
  Eng : TvgRenderEngine;
begin
  Writeln('--- switching with no linker or device ---');

  Eng := TvgRenderEngine.Create(nil);
  try
    // Asking for Dynamic cannot be honoured with nothing to render through;
    // the renderer must say Standard rather than pretend.
    CheckMode('asked Dynamic', Eng.RenderingMode, rmDynamic);
    Check('no linker: not dynamic', Eng.UseDynamicRendering, False);
    CheckMode('no linker: active mode is Standard', Eng.ActiveRenderingMode, rmStandard);

    Eng.RenderingMode := rmStandard;
    CheckMode('switch to Standard sticks', Eng.RenderingMode, rmStandard);
    CheckMode('active mode Standard', Eng.ActiveRenderingMode, rmStandard);
    Check('switching left the renderer inactive', Eng.Active, False);

    Eng.RenderingMode := rmDynamic;
    CheckMode('switch back to Dynamic sticks', Eng.RenderingMode, rmDynamic);
  finally
    Eng.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestSwitchWithDevice;
var
  Dev    : TvgScreenRenderDevice;
  Linker : TvgLinker;
  Eng    : TvgRenderEngine;
begin
  Writeln('--- switching with a linker and screen device (not enabled) ---');

  Dev    := TvgScreenRenderDevice.Create(nil);
  Linker := TvgLinker.Create(nil);
  Eng    := TvgRenderEngine.Create(nil);
  try
    // Make the device's request explicit; its Features default to off.
    Dev.DynamicRenderingON := False;
    Dev.DynamicRenderingON := True;
    Check('device requests dynamic rendering', Dev.IsDynamicRenderingActive, True);

    Linker.ScreenDevice := Dev;
    Eng.Linker := Linker;
    Check('renderer sees the device', Assigned(Eng.Linker) and (Eng.Linker.ScreenDevice = Dev), True);

    // Default: Dynamic asked for and available.
    Check('Dynamic asked, device able: dynamic', Eng.UseDynamicRendering, True);
    CheckMode('active mode Dynamic', Eng.ActiveRenderingMode, rmDynamic);
    Check('render pass follows the renderer', Eng.RenderPass.UsesDynamicRendering, True);

    // The switch, before enabling.
    Eng.RenderingMode := rmStandard;
    Check('Standard asked: not dynamic', Eng.UseDynamicRendering, False);
    CheckMode('active mode Standard', Eng.ActiveRenderingMode, rmStandard);
    Check('render pass follows it to Standard', Eng.RenderPass.UsesDynamicRendering, False);

    Eng.RenderingMode := rmDynamic;
    Check('back to Dynamic: dynamic again', Eng.UseDynamicRendering, True);

    // Device request off: Dynamic falls back to Standard on its own.
    Dev.DynamicRenderingON := False;
    Check('device request off: not dynamic', Eng.UseDynamicRendering, False);
    CheckMode('device request off: active mode Standard', Eng.ActiveRenderingMode, rmStandard);
    CheckMode('...while RenderingMode still says Dynamic', Eng.RenderingMode, rmDynamic);
    Dev.DynamicRenderingON := True;
    Check('device request back on: dynamic', Eng.UseDynamicRendering, True);

    // One subpass is fine, two need a real VkRenderPass.
    Eng.RenderPass.SubPasses.Add;
    Check('one subpass: dynamic', Eng.UseDynamicRendering, True);
    Eng.RenderPass.SubPasses.Add;
    Check('two subpasses: not dynamic', Eng.UseDynamicRendering, False);
    CheckMode('two subpasses: active mode Standard', Eng.ActiveRenderingMode, rmStandard);
    Eng.RenderPass.ClearStructure;
    Check('structure cleared: dynamic again', Eng.UseDynamicRendering, True);

    Check('nothing here enabled the renderer', Eng.Active, False);
  finally
    Eng.Free;
    Linker.Free;
    Dev.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestStandaloneRenderPass;
var
  RP : TvgRenderPass;
begin
  Writeln('--- standalone render pass ---');

  RP := TvgRenderPass.Create(nil);
  try
    Check('handle starts null', RP.RenderPassHandle = VK_NULL_HANDLE, True);
    Check('no framebuffers', RP.FrameBufferHandles[0] = VK_NULL_HANDLE, True);
    Check('no engine, so no dynamic path', RP.UsesDynamicRendering, False);
  finally
    RP.Free;
  end;
  Writeln;
end;

begin
  try
    TestDefaults;
    TestDeviceRequest;
    TestSwitchWithoutDevice;
    TestSwitchWithDevice;
    TestStandaloneRenderPass;
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Inc(Failures);
    end;
  end;

  if Failures = 0 then
    Writeln('ALL CHECKS PASSED')
  else
    Writeln(Format('%d CHECK(S) FAILED', [Failures]));

  ExitCode := Ord(Failures <> 0);
end.
