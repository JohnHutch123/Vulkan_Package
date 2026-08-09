{******************************************************************************
  ToolManager_Additions_Vulkan_Components.pas
  
  INSTRUCTIONS: This file contains all additions required for Vulkan_Components.pas.
  
  STEP 1 — Forward declaration (~line 234, in the existing forward decl block):
    Add:  TvgBase_ToolManager  = Class;

  STEP 2 — New types (insert BEFORE the TvgLinker class definition, ~line 4585):
    Paste the entire TYPE ADDITIONS block below.

  STEP 3 — Modify TvgLinker (insert fields/methods/property into the existing class):
    See the TLINKER MODIFICATIONS block below — apply each marked addition.

  STEP 4 — Implementation section (append BEFORE the final `end.`):
    Paste the entire IMPLEMENTATION ADDITIONS block below.

  STEP 5 — TvgLinker.MouseMove (replace the existing body at ~line 20893):
    See the UPDATED MOUSEMOVE block below.

  STEP 6 — TvgLinker.Notification (add inside the existing Notification body):
    See the NOTIFICATION ADDITIONS block below.
******************************************************************************}

{==============================================================================
  STEP 2 — TYPE ADDITIONS
  INSERT before:  TvgLinker  = Class(TvgBaseComponent)
==============================================================================}

type

  // -----------------------------------------------------------------------
  // Overall mode of the tool manager:
  //   TMM_CAMERA      — all mouse input is routed to camera manipulation
  //   TMM_OBJECT_EDIT — mouse input drives object selection / movement / add
  // -----------------------------------------------------------------------
  TvgToolManagerMode = (
    TMM_NONE,           // Disabled / pass-through
    TMM_CAMERA,         // Mouse input controls the active scene camera
    TMM_OBJECT_EDIT     // Mouse input selects and manipulates scene objects
  );

  // Mouse-button identifier — avoids a dependency on VCL.Controls
  TvgMouseButton  = ( vgmbLeft, vgmbRight, vgmbMiddle );
  TvgMouseButtons = set of TvgMouseButton;

  // -----------------------------------------------------------------------
  //  TvgBase_ToolManager
  //
  //  Base class for scene tool managers.  Drop on the same form as TvgLinker
  //  and set the Linker property in the Object Inspector; at run-time call
  //  HandleMouse* from the form's OnMouseDown / OnMouseMove / OnMouseUp /
  //  OnMouseWheel handlers (or via TvgLinker.MouseDown|MouseMove|MouseUp|
  //  MouseWheel which delegate here automatically).
  //
  //  Subclass in Vulkan_Components_Scene: TvgToolManager.
  // -----------------------------------------------------------------------
  TvgBase_ToolManager = class(TvgBaseComponent)
  private
    function  GetLinker   : TvgLinker;
    procedure SetLinker   (const Value: TvgLinker);
    procedure SetToolMode (const Value: TvgToolManagerMode);
    function  GetRenderer : TvgRenderEngine;

  protected
    fLinker           : TvgLinker;
    fToolMode         : TvgToolManagerMode;
    fMouseSensitivity : Single;      // Global multiplier (default 0.4)

    // --- Internal drag / button state ---
    fLastMouseX   : Integer;
    fLastMouseY   : Integer;
    fMouseButtons : TvgMouseButtons;
    fIsDragging   : Boolean;

    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

    Procedure SetDisabled;                              Override;
    Procedure SetEnabled(aComp: TvgBaseComponent=nil); Override;

    // --- Virtual mouse handlers — override in descendants ---
    procedure DoMouseDown (aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer); Virtual;
    procedure DoMouseMove (Shift: TShiftState; X, Y: Integer);                          Virtual;
    procedure DoMouseUp   (aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer); Virtual;
    procedure DoMouseWheel(Shift: TShiftState; WheelDelta: Integer);                    Virtual;

  public
    constructor Create(AOwner: TComponent); Override;
    destructor  Destroy; override;

    // --- Entry points — called by TvgLinker (or directly from VCL events) ---
    procedure HandleMouseDown (aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure HandleMouseMove (Shift: TShiftState; X, Y: Integer);
    procedure HandleMouseUp   (aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure HandleMouseWheel(Shift: TShiftState; WheelDelta: Integer);

    // Returns current viewport pixel size through the linked surface.
    // Returns False when the linker / surface is not yet available.
    function GetViewportSize(out aWidth, aHeight: Integer): Boolean;

    // Convenience read-only shortcut to the renderer on the Linker
    property Renderer : TvgRenderEngine read GetRenderer;

  Published
    property Linker           : TvgLinker          read GetLinker   write SetLinker;
    property ToolMode         : TvgToolManagerMode read fToolMode   write SetToolMode  default TMM_CAMERA;
    property MouseSensitivity : Single             read fMouseSensitivity write fMouseSensitivity;
  end;


{==============================================================================
  STEP 3 — TLINKER MODIFICATIONS
  Apply the following additions inside the existing TvgLinker class definition.
==============================================================================}

(*
  ---- A) In the PRIVATE section, add the two getter / setter prototypes: ----

    function  GetToolManager : TvgBase_ToolManager;
    procedure SetToolManager (const Value: TvgBase_ToolManager);


  ---- B) In the PROTECTED section (after fMsgEvent), add the field: --------

    fToolManager : TvgBase_ToolManager;


  ---- C) In the PUBLIC section (after the existing MouseMove), add: ---------

    procedure MouseDown (aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MouseUp   (aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer);


  ---- D) In the PUBLISHED section (anywhere), add: --------------------------

    Property ToolManager : TvgBase_ToolManager read GetToolManager write SetToolManager;
*)


{==============================================================================
  STEP 5 — UPDATED MOUSEMOVE
  Replace the body of the existing TvgLinker.MouseMove implementation.
==============================================================================}

(*
procedure TvgLinker.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  If not fActive then exit;
  If X < 0 then exit;
  If Y < 0 then exit;

  // Route through ToolManager if one is attached
  If Assigned(fToolManager) then
  Begin
    fToolManager.HandleMouseMove(Shift, X, Y);
    exit;
  End;

  // Legacy fallback: direct object-at-location query (no tool manager)
  If Assigned(fRenderer) then
    fRenderer.GetObjectAtLocation(TvkUint32(Max(0, fPresentFrameIndex)), Shift, X, Y);
end;
*)


{==============================================================================
  STEP 6 — NOTIFICATION ADDITIONS
  Inside the existing TvgLinker.Notification method, insert the following
  lines inside the Case Operation of block.

  Inside opInsert (after the existing TvgRenderEngine block), add:
==============================================================================}

(*
    // ---- inside opInsert ----
    If (aComponent is TvgBase_ToolManager) and not Assigned(fToolManager) then
      SetToolManager(TvgBase_ToolManager(aComponent));

    // ---- inside opRemove ----
    If (aComponent is TvgBase_ToolManager) and
       (TvgBase_ToolManager(aComponent) = fToolManager) then
      SetToolManager(nil);
*)


{==============================================================================
  STEP 4 — IMPLEMENTATION ADDITIONS
  Paste the following block inside the implementation section of
  Vulkan_Components.pas, BEFORE the final `end.`
==============================================================================}

implementation   // <-- already exists; add the code below WITHIN the existing section

{ TvgBase_ToolManager }

constructor TvgBase_ToolManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  fLinker           := nil;
  fToolMode         := TMM_CAMERA;
  fMouseSensitivity := 0.4;
  fLastMouseX       := 0;
  fLastMouseY       := 0;
  fMouseButtons     := [];
  fIsDragging       := False;
end;

destructor TvgBase_ToolManager.Destroy;
begin
  // Cleanly sever the link from the Linker side
  If Assigned(fLinker) and (fLinker.ToolManager = Self) then
    fLinker.SetToolManager(nil);
  inherited Destroy;
end;

// --- Private helpers -------------------------------------------------------

function TvgBase_ToolManager.GetLinker: TvgLinker;
begin
  Result := fLinker;
end;

procedure TvgBase_ToolManager.SetLinker(const Value: TvgLinker);
begin
  If fLinker = Value then exit;

  If Assigned(fLinker) then
  Begin
    fLinker.RemoveFreeNotification(Self);
    If fLinker.ToolManager = Self then
      fLinker.SetToolManager(nil);  // break reverse link
  End;

  fLinker := Value;

  If Assigned(fLinker) then
  Begin
    fLinker.FreeNotification(Self);
    If fLinker.ToolManager <> Self then
      fLinker.SetToolManager(Self);  // establish reverse link
  End;
end;

function TvgBase_ToolManager.GetRenderer: TvgRenderEngine;
begin
  Result := nil;
  If Assigned(fLinker) then
    Result := fLinker.Renderer;
end;

procedure TvgBase_ToolManager.SetToolMode(const Value: TvgToolManagerMode);
begin
  If fToolMode = Value then exit;
  fToolMode     := Value;
  fIsDragging   := False;
  fMouseButtons := [];
end;

// --- Lifecycle / Delphi Notification ---------------------------------------

procedure TvgBase_ToolManager.Notification(AComponent: TComponent;
                                            Operation: TOperation);
begin
  inherited;
  If (Operation = opRemove) and
     (AComponent is TvgLinker) and
     (TvgLinker(AComponent) = fLinker) then
  Begin
    fLinker := nil;   // Linker is being destroyed — clear without reverse-call
  End;
end;

procedure TvgBase_ToolManager.SetDisabled;
begin
  inherited;
  fIsDragging   := False;
  fMouseButtons := [];
end;

procedure TvgBase_ToolManager.SetEnabled(aComp: TvgBaseComponent);
begin
  inherited;
  // Nothing extra needed at base level; descendants may override
end;

// --- Virtual mouse handlers (no-op stubs; override in descendants) ---------

procedure TvgBase_ToolManager.DoMouseDown(aButton: TvgMouseButton;
                                           Shift: TShiftState; X, Y: Integer);
begin
  // Override in descendants
end;

procedure TvgBase_ToolManager.DoMouseMove(Shift: TShiftState; X, Y: Integer);
begin
  // Override in descendants
end;

procedure TvgBase_ToolManager.DoMouseUp(aButton: TvgMouseButton;
                                         Shift: TShiftState; X, Y: Integer);
begin
  // Override in descendants
end;

procedure TvgBase_ToolManager.DoMouseWheel(Shift: TShiftState;
                                            WheelDelta: Integer);
begin
  // Override in descendants
end;

// --- Public entry points (called by TvgLinker) ----------------------------

procedure TvgBase_ToolManager.HandleMouseDown(aButton: TvgMouseButton;
                                               Shift: TShiftState;
                                               X, Y: Integer);
begin
  Include(fMouseButtons, aButton);
  fLastMouseX := X;
  fLastMouseY := Y;
  fIsDragging := False;
  DoMouseDown(aButton, Shift, X, Y);
end;

procedure TvgBase_ToolManager.HandleMouseMove(Shift: TShiftState;
                                               X, Y: Integer);
begin
  // Latch drag state: any button held during a move is a drag
  If fMouseButtons <> [] then
    fIsDragging := True;

  DoMouseMove(Shift, X, Y);

  // Update last position AFTER the virtual call so descendants can read
  // both fLastMouseX/Y (previous) and the new X, Y in a single DoMouseMove call.
  fLastMouseX := X;
  fLastMouseY := Y;
end;

procedure TvgBase_ToolManager.HandleMouseUp(aButton: TvgMouseButton;
                                             Shift: TShiftState;
                                             X, Y: Integer);
begin
  DoMouseUp(aButton, Shift, X, Y);
  Exclude(fMouseButtons, aButton);
  If fMouseButtons = [] then
    fIsDragging := False;
end;

procedure TvgBase_ToolManager.HandleMouseWheel(Shift: TShiftState;
                                                WheelDelta: Integer);
begin
  DoMouseWheel(Shift, WheelDelta);
end;

function TvgBase_ToolManager.GetViewportSize(out aWidth, aHeight: Integer): Boolean;
  Var W, H : TvkUint32;
begin
  Result  := False;
  aWidth  := 0;
  aHeight := 0;
  If not Assigned(fLinker) then exit;
  If not Assigned(fLinker.Surface) then exit;
  If fLinker.Surface.GetWindowSize(W, H) then
  Begin
    aWidth  := Integer(W);
    aHeight := Integer(H);
    Result  := (aWidth > 0) and (aHeight > 0);
  End;
end;

// ---------------------------------------------------------------------------
// TvgLinker — new methods (add these implementations to the existing
//             TvgLinker implementation block)
// ---------------------------------------------------------------------------

function TvgLinker.GetToolManager: TvgBase_ToolManager;
begin
  Result := fToolManager;
end;

procedure TvgLinker.SetToolManager(const Value: TvgBase_ToolManager);
begin
  If fToolManager = Value then exit;

  If Assigned(fToolManager) then
    fToolManager.fLinker := nil;   // clear back-pointer without recursion

  fToolManager := Value;

  If Assigned(fToolManager) then
    fToolManager.fLinker := Self;
end;

procedure TvgLinker.MouseDown(aButton: TvgMouseButton;
                               Shift: TShiftState; X, Y: Integer);
begin
  If not fActive        then exit;
  If X < 0              then exit;
  If Y < 0              then exit;
  If Assigned(fToolManager) then
    fToolManager.HandleMouseDown(aButton, Shift, X, Y);
end;

procedure TvgLinker.MouseUp(aButton: TvgMouseButton;
                             Shift: TShiftState; X, Y: Integer);
begin
  If not fActive then exit;
  If Assigned(fToolManager) then
    fToolManager.HandleMouseUp(aButton, Shift, X, Y);
end;

procedure TvgLinker.MouseWheel(Shift: TShiftState; WheelDelta: Integer);
begin
  If not fActive then exit;
  If Assigned(fToolManager) then
    fToolManager.HandleMouseWheel(Shift, WheelDelta);
end;