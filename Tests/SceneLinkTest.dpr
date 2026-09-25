program SceneLinkTest;

{$APPTYPE CONSOLE}

{ How a TvgRenderEngine is linked to its TvgScene, without a Vulkan device.

  TvgRenderEngine.Scene used to read a private field that nothing ever wrote,
  so Eng.Scene came back nil straight after Eng.Scene := S, even though the
  link had been made.  The Object Inspector showed Scene empty, and a property
  whose getter returns nil is never written to a DFM.  Only BaseScene was
  written, and its setter set the field without telling the scene, so a
  reloaded renderer was missing from the scene's RendererList.

  A link has three parts that must agree: Scene, BaseScene, and the scene
  listing the renderer exactly once.  This checks all three after:

    - assigning Scene, moving it to a second scene, and clearing it;
    - assigning BaseScene the same way;
    - TvgScene.ConnectRenderEngine, which is what the design-time auto-link
      calls when a renderer and a scene sit on the same form;
    - freeing either end;
    - a DFM round trip (WriteComponent then ReadComponent, as a form loads at
      runtime), with the scene ahead of the engine in the stream and behind
      it, and a DFM written before the fix that holds only BaseScene. }

uses
  System.SysUtils,
  System.Classes,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_Descriptors,
  Vulkan_Components_Light,
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

// How many times aScene's RendererList holds aEng.  One is right; two would
// mean a second connect was not refused.
function Listed(aScene: TvgScene; aEng: TvgRenderEngine): Integer;
var
  I : Integer;
begin
  Result := 0;
  for I := 0 to aScene.RendererList.Count - 1 do
    if aScene.RendererList[I] = aEng then
      Inc(Result);
end;

procedure CheckLinked(const Prefix: string; aEng: TvgRenderEngine; aScene: TvgScene);
begin
  Check(Prefix + ': Scene is the scene', aEng.Scene = aScene, True);
  Check(Prefix + ': BaseScene is the same scene', aEng.BaseScene = aScene, True);
  Check(Prefix + ': scene lists the engine once', Listed(aScene, aEng) = 1, True);
end;

procedure CheckUnlinked(const Prefix: string; aEng: TvgRenderEngine);
begin
  Check(Prefix + ': Scene is nil', aEng.Scene = nil, True);
  Check(Prefix + ': BaseScene is nil', aEng.BaseScene = nil, True);
end;

// ---------------------------------------------------------------------------
procedure TestAssignScene;
var
  Eng    : TvgRenderEngine;
  S1, S2 : TvgScene;
begin
  Writeln('--- assigning Scene ---');

  Eng := TvgRenderEngine.Create(nil);
  S1  := TvgScene.Create(nil);
  S2  := TvgScene.Create(nil);
  try
    CheckUnlinked('new engine', Eng);

    Eng.Scene := S1;
    CheckLinked('assigned', Eng, S1);

    Eng.Scene := S1;
    CheckLinked('same scene again', Eng, S1);

    Eng.Scene := S2;
    CheckLinked('moved', Eng, S2);
    Check('moved: old scene no longer lists it', Listed(S1, Eng) = 0, True);

    Eng.Scene := nil;
    CheckUnlinked('cleared', Eng);
    Check('cleared: scene no longer lists it', Listed(S2, Eng) = 0, True);
  finally
    Eng.Free;
    S2.Free;
    S1.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestAssignBaseScene;
var
  Eng    : TvgRenderEngine;
  S1, S2 : TvgScene;
begin
  Writeln('--- assigning BaseScene ---');

  Eng := TvgRenderEngine.Create(nil);
  S1  := TvgScene.Create(nil);
  S2  := TvgScene.Create(nil);
  try
    Eng.BaseScene := S1;
    CheckLinked('assigned', Eng, S1);

    Eng.BaseScene := S2;
    CheckLinked('moved', Eng, S2);
    Check('moved: old scene no longer lists it', Listed(S1, Eng) = 0, True);

    // The two properties are one link: setting either moves both.
    Eng.Scene := S1;
    CheckLinked('Scene after BaseScene', Eng, S1);
    Check('Scene after BaseScene: old scene no longer lists it', Listed(S2, Eng) = 0, True);

    Eng.BaseScene := nil;
    CheckUnlinked('cleared', Eng);
    Check('cleared: scene no longer lists it', Listed(S1, Eng) = 0, True);
  finally
    Eng.Free;
    S2.Free;
    S1.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestConnectFromScene;
var
  Eng    : TvgRenderEngine;
  S1, S2 : TvgScene;
begin
  Writeln('--- TvgScene.ConnectRenderEngine (the design-time auto-link) ---');

  Eng := TvgRenderEngine.Create(nil);
  S1  := TvgScene.Create(nil);
  S2  := TvgScene.Create(nil);
  try
    S1.ConnectRenderEngine(Eng);
    CheckLinked('connected', Eng, S1);

    S1.ConnectRenderEngine(Eng);
    CheckLinked('connected again', Eng, S1);

    // An engine belongs to one scene; a second scene must not claim it.
    S2.ConnectRenderEngine(Eng);
    CheckLinked('second scene refused', Eng, S1);
    Check('second scene refused: it does not list the engine', Listed(S2, Eng) = 0, True);

    S1.DisConnectRenderEngine(Eng);
    CheckUnlinked('disconnected', Eng);
    Check('disconnected: scene no longer lists it', Listed(S1, Eng) = 0, True);
  finally
    Eng.Free;
    S2.Free;
    S1.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
procedure TestFree;
var
  Eng : TvgRenderEngine;
  S   : TvgScene;
begin
  Writeln('--- freeing one end of the link ---');

  Eng := TvgRenderEngine.Create(nil);
  S   := TvgScene.Create(nil);
  try
    Eng.Scene := S;
    FreeAndNil(S);
    CheckUnlinked('scene freed', Eng);
  finally
    Eng.Free;
    S.Free;
  end;

  S   := TvgScene.Create(nil);
  Eng := TvgRenderEngine.Create(nil);
  try
    Eng.Scene := S;
    FreeAndNil(Eng);
    Check('engine freed: scene no longer lists it', S.RendererList.Count = 0, True);
  finally
    Eng.Free;
    S.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
// Reads aBin into a fresh data module and checks Engine1 is linked to Scene1.
procedure CheckReload(aBin: TStream);
var
  Root : TDataModule;
  S    : TvgScene;
  Eng  : TvgRenderEngine;
begin
  Root := TDataModule.CreateNew(nil);
  try
    aBin.Position := 0;
    aBin.ReadComponent(Root);

    S   := Root.FindComponent('Scene1')  as TvgScene;
    Eng := Root.FindComponent('Engine1') as TvgRenderEngine;
    Check('reloaded: both components exist', Assigned(S) and Assigned(Eng), True);
    if Assigned(S) and Assigned(Eng) then
      CheckLinked('reloaded', Eng, S);
  finally
    Root.Free;
  end;
end;

procedure TestStreaming(EngineFirst: Boolean);
var
  Root   : TDataModule;
  S      : TvgScene;
  Eng    : TvgRenderEngine;
  Bin    : TMemoryStream;
  Txt    : TStringStream;
  Before : Integer;
begin
  if EngineFirst then
    Writeln('--- DFM round trip, engine ahead of the scene ---')
  else
    Writeln('--- DFM round trip, scene ahead of the engine ---');

  Before := Failures;
  Root   := TDataModule.CreateNew(nil);
  Bin    := TMemoryStream.Create;
  Txt    := TStringStream.Create('');
  try
    // Children are streamed in creation order.
    if EngineFirst then
    begin
      Eng := TvgRenderEngine.Create(Root);
      S   := TvgScene.Create(Root);
    end
    else
    begin
      S   := TvgScene.Create(Root);
      Eng := TvgRenderEngine.Create(Root);
    end;
    S.Name   := 'Scene1';
    Eng.Name := 'Engine1';
    Eng.Scene := S;

    Bin.WriteComponent(Root);
    Bin.Position := 0;
    ObjectBinaryToText(Bin, Txt);
    // The leading space keeps "BaseScene = Scene1" from matching.
    Check('DFM stores Scene = Scene1', Pos(' Scene = Scene1', Txt.DataString) > 0, True);

    CheckReload(Bin);

    if Failures > Before then
    begin
      Writeln('  DFM written:');
      Writeln(Txt.DataString);
    end;
  finally
    Txt.Free;
    Bin.Free;
    Root.Free;
  end;
  Writeln;
end;

// A DFM saved before the fix: the getter returned nil, so only BaseScene was
// written.  It must still load into a whole link.
procedure TestOldDFM;
const
  OldDFM =
    'object TDataModule'#13#10 +
    '  object Scene1: TvgScene'#13#10 +
    '  end'#13#10 +
    '  object Engine1: TvgRenderEngine'#13#10 +
    '    BaseScene = Scene1'#13#10 +
    '  end'#13#10 +
    'end'#13#10;
var
  Txt : TStringStream;
  Bin : TMemoryStream;
begin
  Writeln('--- DFM written before the fix (BaseScene only) ---');

  Txt := TStringStream.Create(OldDFM);
  Bin := TMemoryStream.Create;
  try
    ObjectTextToBinary(Txt, Bin);
    CheckReload(Bin);
  finally
    Bin.Free;
    Txt.Free;
  end;
  Writeln;
end;

// ---------------------------------------------------------------------------
// The renderer's global descriptors sit at fixed bindings - 0 view-projection,
// 1 object-ID target, 2 lights - whatever SelectMode is, so a shader compiled
// in one mode still matches another.  Lights once took binding 1 and pushed
// the object-ID target to 2: a RenderDoc capture showed outObjectIDBuffer
// "not connected", its writes going to an unbound slot.  Switching modes
// must also drop the last mode's object-ID item, or two items share 1.
procedure TestGlobalBindings;
var
  Eng : TvgRenderEngine;

  function B(const aName: string): Integer;
  var
    DI : TvgDescriptorItem;
  begin
    Result := -1;
    DI := Eng.GlobalRes.GetDescriptorItem(aName);
    if Assigned(DI) and Assigned(DI.Descriptor) then
      Result := Integer(DI.Descriptor.Binding);
  end;

  // No two globals share a binding - a leftover object-ID item from the
  // last SelectMode would.
  function NoDuplicates: Boolean;
  var
    I, J : Integer;
  begin
    Result := True;
    for I := 0 to Eng.GlobalRes.Descriptors.Count - 1 do
      for J := I + 1 to Eng.GlobalRes.Descriptors.Count - 1 do
        if Assigned(Eng.GlobalRes.Descriptors.Items[I].Descriptor) and
           Assigned(Eng.GlobalRes.Descriptors.Items[J].Descriptor) and
           (Eng.GlobalRes.Descriptors.Items[I].Descriptor.Binding =
            Eng.GlobalRes.Descriptors.Items[J].Descriptor.Binding) then
          Result := False;
  end;

  // The fixed slots, whatever the mode.
  function Fixed: Boolean;
  begin
    Result := (B(GlobalViewProjectDescriptor) = GlobalBindingViewProject) and
              (B(GlobalLightsDescriptor)      = GlobalBindingLights);
  end;

begin
  Writeln('--- global descriptor bindings ---');

  Eng := TvgRenderEngine.Create(nil);
  try
    Check('no selection: view-projection at 0, lights at 2', Fixed, True);
    Check('...binding 1 left empty', (B(GlobalObjectIDDescriptorBuf) = -1) and
                                     (B(GlobalObjectIDDescriptorImg) = -1), True);

    Eng.SelectMode := smStorageBuffer;
    Check('storage buffer: object-ID buffer at 1', B(GlobalObjectIDDescriptorBuf) = GlobalBindingObjectID, True);
    Check('...lights still 2, view-projection still 0', Fixed, True);
    Check('...no shared bindings', NoDuplicates, True);

    Eng.SelectMode := smImageBuffer;
    Check('image: object-ID image at 1', B(GlobalObjectIDDescriptorImg) = GlobalBindingObjectID, True);
    Check('...old object-ID buffer removed', B(GlobalObjectIDDescriptorBuf) = -1, True);
    Check('...lights still 2, view-projection still 0', Fixed, True);
    Check('...no shared bindings', NoDuplicates, True);

    Eng.SelectMode := smStorageBuffer;
    Check('back to buffer: object-ID buffer at 1', B(GlobalObjectIDDescriptorBuf) = GlobalBindingObjectID, True);
    Check('...old object-ID image removed', B(GlobalObjectIDDescriptorImg) = -1, True);
    Check('...no shared bindings', NoDuplicates, True);

    Eng.SelectMode := smNone;
    Check('selection off again: binding 1 empty', (B(GlobalObjectIDDescriptorBuf) = -1) and
                                                  (B(GlobalObjectIDDescriptorImg) = -1), True);
    Check('...lights still 2, view-projection still 0', Fixed, True);
  finally
    Eng.Free;
  end;
  Writeln;
end;

type
  // Reaches the protected SetLightData, which the linker normally calls.
  TEngineAccess = class(TvgRenderEngine);

procedure TestLightsBuffer;
var
  Eng : TvgRenderEngine;
  DI  : TvgDescriptorItem;
  SB  : TvgDescriptorArray_SB_Light;
  DD  : TvgDescriptor_Data_StorageBuffer<TvgLightGPUData>;
  L   : TArray<TvgLightGPUData>;
  I   : Integer;

  function Slots: Integer;
  begin
    Result := DD.StorageBufferFrameData[0].Data.ItemCount;
  end;

  function SlotType(aIndex: Integer): Single;
  begin
    Result := DD.StorageBufferFrameData[0].Data[aIndex].DirectionType[3];
  end;

begin
  Writeln('--- lights buffer ---');

  Eng := TvgRenderEngine.Create(nil);
  try
    DI := Eng.GlobalRes.GetDescriptorItem(GlobalLightsDescriptor);
    SB := nil;
    if Assigned(DI) and (DI.Descriptor is TvgDescriptorArray_SB_Light) then
      SB := TvgDescriptorArray_SB_Light(DI.Descriptor);
    Check('lights descriptor exists', Assigned(SB), True);
    if not Assigned(SB) then exit;

    DD := SB.SB_Descriptor[0];
    Check('uploads (DF_UP), so light data reaches the GPU', DF_UP in SB.DataFlow, True);
    Check('fixed size, so a VkBuffer exists even with no lights',
          DD.ElementCount = MaxGlobalLights, True);
    Check('...plain data, no pixel sampler', DD.SamplingON, False);

    SetLength(L, 2);
    L[0] := Default(TvgLightGPUData);
    L[0].DirectionType[3] := 2;   // Point
    L[1] := Default(TvgLightGPUData);
    L[1].DirectionType[3] := 3;   // Spot
    TEngineAccess(Eng).SetLightData(0, L);
    Check('two lights: still every slot filled', Slots = MaxGlobalLights, True);
    Check('...live lights first', (SlotType(0) = 2) and (SlotType(1) = 3), True);
    Check('...the rest type None', SlotType(2) = 0, True);

    SetLength(L, 0);
    TEngineAccess(Eng).SetLightData(0, L);
    Check('no lights: no stale entries left', (Slots = MaxGlobalLights) and (SlotType(0) = 0), True);

    SetLength(L, MaxGlobalLights + 3);
    for I := 0 to High(L) do
    begin
      L[I] := Default(TvgLightGPUData);
      L[I].DirectionType[3] := 1;   // Directional
    end;
    TEngineAccess(Eng).SetLightData(0, L);
    Check('too many lights: clamped to the buffer', Slots = MaxGlobalLights, True);
    Check('...last slot kept', SlotType(MaxGlobalLights - 1) = 1, True);
  finally
    Eng.Free;
  end;
  Writeln;
end;

begin
  RegisterClasses([TvgScene, TvgRenderEngine]);
  try
    TestAssignScene;
    TestAssignBaseScene;
    TestConnectFromScene;
    TestFree;
    TestStreaming(False);
    TestStreaming(True);
    TestOldDFM;
    TestGlobalBindings;
    TestLightsBuffer;
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
