unit Vulkan_Components_Scene_Renderer;

{------------------------------------------------------------------------------
  Vulkan_Components_Scene.pas - REFACTORED VERSION
  Simplified scene and object management working with refactored DataStore
  
  KEY SIMPLIFICATIONS:
  - Objects directly track their start/count in global buffers
  - No more binding lookups - objects know their ranges
  - Removed multi-vertex-set and multi-index-set complexity
  - Simpler API - just object index + local index
------------------------------------------------------------------------------}

interface

{$INCLUDE VulkanPackage.inc}

uses
  {$IFDEF FASTMM5}
  FastMM5,
  {$ENDIF}
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Classes,
  System.TypInfo,
  System.Math,
  System.SyncObjs,
  {$IFDEF TIMINGON}
  System.Diagnostics,
  {$ENDIF}
  Vulkan,
//  PasVulkan.Types,
  PasVulkan.Math,
//  PasVulkan.Collections,
  PasVulkan.Framework,
  Vulkan_Assert,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_Descriptors,
  Vulkan_Components_DataStore,
  Vulkan_Components_Nodes,
  Vulkan_Components_Camera,
  Vulkan_Components_PointerValidation,
  Vulkan_PixelInfo;

type
  TvgScene = Class;
  TvgObjectStore = Class;
  TvgRenderEngine = Class;

  TvgObject = Class(TvgObject_Base)
  private
    procedure SetCurrentVertex(const Value: Integer);
  protected
    fDataStore      : TvgObjectStore;
    fObjIndex       : Integer;           // Index in DataStore's object list
    
    fCurrentVertex  : Integer;     // Current local vertex index for adding
    fCurrentInstance: Integer;     // Current local instance index for adding


    Procedure SetDisabled; Override;
    Procedure SetEnabled; Override;


  Public
    Constructor Create;

    // Allocation methods
    procedure AllocateVertices(ACount: Integer;  AMode: TAllocationMode = amClear);
    procedure AllocateInstances(ACount: Integer; AMode: TAllocationMode = amClear);
    procedure AllocateIndices(ACount: Integer;   AMode: TAllocationMode = amClear);

    // Adding elements (auto-increments current index)
    function AddInstance : Integer;
    function AddVertex   : Integer;

    // Setters using current vertex/instance
    procedure SetVertexPosition(X, Y, Z: Single);
    procedure SetVertexColor(R, G, B: Single; A: Single = 1.0);
    procedure SetVertexNormal(X, Y, Z: Single);
    procedure SetVertexTexCoord(U, V: Single);
    procedure SetVertexTangent(X, Y, Z: Single);
    procedure SetVertexBiTangent(X, Y, Z: Single);
    procedure SetVertexIndex(I: Cardinal);

    procedure SetInstanceObjID(ID1, ID2: Cardinal);
    procedure SetInstanceColor(R, G, B: Single; A: Single = 1.0);
    procedure SetInstanceNormal(X, Y, Z: Single);
    procedure SetInstanceTangent(X, Y, Z: Single);
    procedure SetInstanceVector(X, Y, Z: Single);
    procedure SetInstanceMatrix(M: TvgMatrix4x4S);
    procedure SetInstanceIndex(I: Cardinal);

    // Index methods
    function AddIndex(AIndex: Cardinal): Integer; overload;
    function AddIndex(I1, I2, I3: Cardinal): Integer; overload;
    function AddIndices(const AIndices: array of Cardinal): Integer;

    procedure SetIndex(AIndexPos: Integer; AValue: Cardinal);
    procedure SetTriangle(ATriangleIndex: Integer; I1, I2, I3: Cardinal);

    Function IncCurrentVertex  :Boolean;

    // Properties
    Property DataStore: TvgObjectStore read fDataStore;
    Property ObjIndex : Integer read fObjIndex;

    Property CurrentVertex : Integer Read fCurrentVertex write SetCurrentVertex;


  End;

  TvgObjectStore = Class(TvgVulkanDataStore)
  private
    function GetActive: Boolean;
 //   procedure SetActiveState(const Value: Boolean);

  protected
    fScene               : TvgScene;
    fObjects             : TObjectList<TvgObject>;  // Owns these objects

    //Graphicpipeline properties

    fUseShaders    : TvgPipelineShaders;

    fPolygonMode   : TVkPolygonMode;
    fCullMode      : TVkCullModeFlags;
    fFrontFace     : TVkFrontFace;
    fLineWidth     : Single;
    fPointSize     : Single;

//    fObjectSelectON   : Boolean;
//    fShadersUseDouble : Boolean;

    Procedure SetEnabled; Override;
    Procedure SetDisabled; Override;

    Procedure ObjectsListOfPipes_Update;
    Procedure ObjectsListOfPipes_Clear;

    Procedure  ConfigureGraphicPipeline(GP:TvgGraphicPipeline); Override;

    function GetEditable: Boolean;  Override;
    function GetFrozen: Boolean;  Override;
    function GetLocked: Boolean;    Override;
    function GetSelectable: Boolean; Override;
    function GetVisible: Boolean;  Override;


  public
    constructor Create(AOwner: TComponent);  Override;
    destructor Destroy; override;

    Procedure ClearData;
    Procedure ClearGraphicPipes;     Override;

    // Object creation
    Function AddObject: TvgObject;
    Procedure RemoveObject(aObject: TvgObject);
    function GetObjectCount: Integer; Override;

    procedure ReleaseFromScene;

   Procedure ConnectDataToRenderer(aRenderer:TvgBaseRenderEngine);
   //create and connect graphic pipelines to Scene/RednerEngine/SubPass (SceneData OWNS the GraphicPipelines)
   //If RenderEngine ACTIVE the Activate GraphicPipeline
   //Connect ObjectStore to GraphicPipelines (SceneData OWNs ObjectStores)

   Procedure DisConnectDataFromSceneandRenderer(aRenderer:TvgBaseRenderEngine);
   //remove GraphicPipelines from SubPasses
   //Free GraphicPipelines

    // Configuration
//    Property InstanceDataON : Boolean read fInstanceDataON write SetIncInstanceData;
 //   Property ObjectSelectON : Boolean read fObjectSelectON write SetObjectSelectON ;

    Property Scene: TvgScene read fScene ;
    Property Active: Boolean read GetActive write SetActiveState;
  End;



  TvgSceneMouseOverObject = procedure(Sender: TvgBaseScene; const aObject: TvgObject) of object;

  TvgScene = Class(TvgBaseScene)
  private
    procedure SetOnMouseOver(const Value: TvgSceneMouseOverObject);
//Scene holds and owns RenderNodes in a list
 //RenderNodes are added to the renderers for use
 //disable the Scene will Free all RenderNodes Scene NOT disabled by Instance disabling
 //Nodes are added by the TvgSceneLoaderStorer during the
 //Scene will provide a NodeID which can be used in ObjectPicking

   Protected

    fSceneData   : TObjectList<TvgObjectStore>;
    fCameras     : TvgCameraManager;


    fOnMouseOver : TvgSceneMouseOverObject;

    Function SetDisabled :Boolean; Override;
    Function SetEnabled  :Boolean; Override;

    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

   Procedure ClearGraphicPipelines(aRenderer:TvgBaseRenderEngine; aSubPass:TvgSubpass);Override;
    function GetObjectStore(Index: Integer): TvgBaseObjectStore; Override;


 Public

   constructor Create(AOwner: TComponent); Override;
   destructor Destroy; override;

   Function AddDataStore(aDataStore: TvgObjectStore):Boolean;

   Procedure PrepareFrameGlobalData(aTarget  : IvgGlobalDataTarget; aFrameIndex : TvkUint32); Override;

   Function GetObjectCount : Integer; Override;
   Function GetObjectStoreCount   : Integer; Override;


//   Function GetObjectAtPointer(aPointer:Pointer): TvgObject;

 //  Function GetSceneGLSLHeaders:String;

   Procedure ClearScene; Override;

 //virtual abstract from BaseScene
   Procedure ConnectDataToRenderer(aRenderEngine : TvgBaseRenderEngine);Override;
   //Called when connecting a RenderEngine
   Procedure DisConnectDataFromRenderer(aRenderEngine : TvgBaseRenderEngine);Override;
   //Called when Disconnecting a RenderEngine
   Procedure ConnectDataToVulkanDevice(aScreenDevice:TvgScreenRenderDevice); Override;
   Procedure BuildGraphicPipelinesForRenderer(aRenderer: TvgBaseRenderEngine);  Override;


   Property SceneData : TObjectList<TvgObjectStore> Read fSceneData  ;
   Property Cameras   : TvgCameraManager read fCameras;

   Property OnMouseOver  : TvgSceneMouseOverObject read fOnMouseOver write SetOnMouseOver;

  End;


TvgSceneLoaderStorer = Class(TvgBaseComponent)
 //descendants handles read/write of scene data and conversion to TvgSceneData which are then added to the Scene

  private
    procedure SetScene(const Value: TvgScene);
 //Descendant will load /Store data To/From the Scene using the local format
   protected
     fScene             : TvgScene;
     fCurrentObjectStore: TvgObjectStore;


   public

     Procedure LoadScene;Virtual;Abstract;
     //load scene into TvgScene
     Procedure StoreScene;Virtual;Abstract;

     Function AddObjectStore:TvgObjectStore;


     Procedure AddDescriptor_Texture( aDescriptorName : String;
                                     aImageFileName  : String);

     Property CurrentObjectStore : TvgObjectStore Read fCurrentObjectStore;


   published
     Property Scene : TvgScene Read fScene write SetScene;

 End;

 TvgRenderEngine= Class(TvgBaseRenderEngine)
 Private


 Protected

   fScene                  : TvgScene;

   fObjectIDImage          : TvgDescriptorArray_StorageImage;

    Function SetDisabled :Boolean; Override;
    Function SetEnabled  :Boolean; Override;

    procedure Notification(AComponent: TComponent; Operation: TOperation); override;


    Procedure VaildateGlobalResources;     Override;
    Procedure ConfigureGraphicPipelineFromRenderPass(GP:TvgGraphicPipeline);  Override;


 Public

    Function GetObjectAtLocation(aFrameIndex : TvkUint32; Shift: TShiftState; X, Y: Integer):TvgObject;  Virtual;


 Published

//   Property MVPMatrixON   : Boolean read FFlags.MVPMatrixON write SetMVPMatrixON;
//   Property ObjSelectON   : Boolean read FFlags.SelectON write SetSelectON;

 End;



 // -----------------------------------------------------------------------
  //  Sub-mode used when ToolMode = TMM_OBJECT_EDIT (or to force a specific
  //  camera gesture inside OBJECT_EDIT).
  // -----------------------------------------------------------------------
  TvgToolActionMode = (
    TAM_CAMERA_ORBIT,  // Left-drag: orbit camera around its target
    TAM_CAMERA_PAN,    // Middle or Shift+Left drag: pan camera laterally
    TAM_CAMERA_DOLLY,  // Right or Ctrl+Left drag: dolly camera forward/back
    TAM_OBJECT_SELECT, // Left click: pick object under cursor
    TAM_OBJECT_MOVE,   // Left drag on selection: move object on drag plane
    TAM_OBJECT_ADD     // Left click (no drag): request add at world position
  );

  // -----------------------------------------------------------------------
  //  Event signatures
  // -----------------------------------------------------------------------
  // Fired when the user successfully picks a scene object
  TvgObjectPickedEvent     = procedure(Sender: TObject;
                                        aObject: TvgObject) of object;

  // Fired every mouse-move frame while dragging a selected object.
  // aNewWorldPos is the recalculated world position on the drag plane;
  // the handler is responsible for applying that position to the object
  // (e.g. translate all vertices by (aNewWorldPos - previously stored pos)).
  TvgObjectMovedEvent      = procedure(Sender: TObject;
                                        aObject: TvgObject;
                                        const aNewWorldPos: TpvVector3) of object;

  // Fired when the user clicks in TAM_OBJECT_ADD mode without dragging.
  // aWorldPos is the world-space ray-plane intersection point.
  TvgObjectAddRequestEvent = procedure(Sender: TObject;
                                        const aWorldPos: TpvVector3) of object;

  // -----------------------------------------------------------------------
  //  TvgToolManager
  //
  //  Full scene tool manager.  Inherits raw mouse plumbing from
  //  TvgBase_ToolManager; adds camera control and scene-object interaction.
  // -----------------------------------------------------------------------

  TvgToolManager = class(TvgBaseToolManager)
  private
    procedure SetScene(const Value: TvgScene);
    procedure SetActionMode(const Value: TvgToolActionMode);
    procedure SetOrbitButton(const Value: TvgMouseButton);
    procedure SetPanButton(const Value: TvgMouseButton);
    procedure SetDollyButton(const Value: TvgMouseButton);
    procedure SetDragPlaneAxis(const Value: Integer);
    procedure SetRenderer(const Value: TvgRenderEngine);

  protected
    fScene         : TvgScene;
    fRenderer      : TvgRenderEngine;

    fMouseOverPtr,
    fMouseDownPtr,
    fMouseUpPtr   : TvgObject;   //pointers

    fActionMode    : TvgToolActionMode;

    // Configurable button-to-gesture bindings
    fOrbitButton   : TvgMouseButton;   // Default: vgmbLeft
    fPanButton     : TvgMouseButton;   // Default: vgmbMiddle
    fDollyButton   : TvgMouseButton;   // Default: vgmbRight

    // Object editing state
    fSelectedObject   : TvgObject;
    fDragPlaneAxis    : Integer;       // 0=XZ, 1=XY, 2=YZ (see header)
    fDragStartHitPt   : TpvVector3;   // World-space ray-plane hit at pick time
    fDragPlaneValid   : Boolean;       // True when fDragStartHitPt is usable

    // Events
    fOnObjectPicked   : TvgObjectPickedEvent;
    fOnObjectMoved    : TvgObjectMovedEvent;
    fOnObjectAddReq   : TvgObjectAddRequestEvent;

    procedure Notification(AComponent: TComponent;  Operation: TOperation); override;

    Function SetDisabled :Boolean; Override;
    Function SetEnabled  :Boolean; Override;

    // --- Camera operations ---
    procedure DoCameraOrbit(aDeltaX, aDeltaY: Single);
    procedure DoCameraPan(aDeltaX, aDeltaY: Single);
    procedure DoCameraDolly(aDelta: Single);
    procedure DoCameraZoom(aWheelDelta: Integer);

    // --- Object operations ---
    procedure DoPickObject(aFrameIndex: TvkUint32;
                            Shift: TShiftState; X, Y: Integer);
    procedure DoDragObject(X, Y: Integer);
    procedure DoAddObjectRequest(X, Y: Integer);

    // --- Helpers ---
    function GetActiveCamera: TvgCamera;
    function GetCurrentFrameIndex: TvkUint32;
    function GetDragPlaneNormal: TpvVector3;
    function ScreenRayHitsPlane(aX, aY: Integer;
                                 const aPlaneNormal: TpvVector3;
                                 const aPlanePoint:  TpvVector3;
                                 out   aHitPoint:    TpvVector3): Boolean;

    // Decides the active camera gesture from button/shift state
    procedure DispatchCameraGesture(Shift: TShiftState;
                                     aDeltaX, aDeltaY: Single);

    // --- Override base virtual mouse handlers ---
    procedure DoMouseDown (aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    procedure DoMouseMove (Shift: TShiftState; X, Y: Integer);                          Override;
    procedure DoMouseUp   (aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    procedure DoMouseWheel(Shift: TShiftState; WheelDelta: Integer);                    Override;

  public
    constructor Create(AOwner: TComponent); Override;
    destructor  Destroy; override;

    // Clears the selected object and resets drag state
    procedure ClearSelection;

    // Read-only: the currently selected TvgObject (nil if none)
    property SelectedObject : TvgObject read fSelectedObject;

  published
    property Scene         : TvgScene          read fScene         write SetScene;
    Property Renderer      : TvgRenderEngine    Read fRenderer     write SetRenderer;

    property ActionMode    : TvgToolActionMode  read fActionMode   write SetActionMode  default TAM_CAMERA_ORBIT;
    property OrbitButton   : TvgMouseButton     read fOrbitButton  write SetOrbitButton  default vgmbLeft;
    property PanButton     : TvgMouseButton     read fPanButton    write SetPanButton    default vgmbMiddle;
    property DollyButton   : TvgMouseButton     read fDollyButton  write SetDollyButton  default vgmbRight;
    // 0=XZ(horizontal), 1=XY(vertical), 2=YZ(side) — used for object drag
    property DragPlaneAxis : Integer            read fDragPlaneAxis write SetDragPlaneAxis default 0;

    property OnObjectPicked : TvgObjectPickedEvent     read fOnObjectPicked write fOnObjectPicked;
    property OnObjectMoved  : TvgObjectMovedEvent      read fOnObjectMoved  write fOnObjectMoved;
    property OnObjectAddReq : TvgObjectAddRequestEvent read fOnObjectAddReq  write fOnObjectAddReq;
  end;



implementation

{ TvgObject }

constructor TvgObject.Create;
begin
  inherited;
  fDataStore       := nil;
  fObjIndex        := -1;
  fCurrentVertex   := -1;
  fCurrentInstance := -1;

  fFlags.Selectable := True;
  fFlags.Visible    := True;

  SetUpObjectID;
end;

function TvgObject.IncCurrentVertex: Boolean;
   Var C,NewV:Integer;
begin
  Result := False;
  If not assigned(fDataStore) then exit;

  C:= fDataStore.GetObjectVertexCount(self.fObjIndex);
  NewV := fCurrentVertex;
  Inc(NewV);
  If (NewV>=0) and (NewV<C) then
  Begin
    fCurrentVertex := NewV;
    Result := True;
  End;
end;

procedure TvgObject.SetCurrentVertex(const Value: Integer);
   Var C:Integer;
begin

  If assigned(fDataStore) then
     C:= fDataStore.GetObjectVertexCount(self.fObjIndex)
  else
     C:=0;

  If (Value>=0) and (Value<C) then
    fCurrentVertex := Value;  //no checks on this
end;

procedure TvgObject.SetDisabled;
begin
  inherited;
end;

procedure TvgObject.SetEnabled;
begin
  inherited;

  SetUpObjectID;
  // Object-specific enable logic
end;

procedure TvgObject.AllocateVertices(ACount: Integer; AMode: TAllocationMode);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;

  fCurrentVertex := -1;  // Reset to allow adding
  fDataStore.AllocateVertices(fObjIndex, ACount, AMode);
end;

procedure TvgObject.AllocateInstances(ACount: Integer; AMode: TAllocationMode);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;

  fCurrentInstance := -1;  // Reset to allow adding
  fDataStore.AllocateInstances(fObjIndex, ACount, AMode);
end;

procedure TvgObject.AllocateIndices(ACount: Integer; AMode: TAllocationMode);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;

  fDataStore.AllocateIndices(fObjIndex, ACount, AMode);
end;

function TvgObject.AddVertex: Integer;
begin
  if not Assigned(fDataStore) then
  begin
    Result := -1;
    Exit;
  end;
  if fObjIndex = -1 then
  begin
    Result := -1;
    Exit;
  end;

  fCurrentVertex := fDataStore.AddObjectVertex(fObjIndex);
  Result := fCurrentVertex;
end;

function TvgObject.AddInstance: Integer;
begin
  if not Assigned(fDataStore) then
  begin
    Result := -1;
    Exit;
  end;
  if fObjIndex = -1 then
  begin
    Result := -1;
    Exit;
  end;


  fCurrentInstance := fDataStore.AddObjectInstance(fObjIndex);
  Result           := fCurrentInstance;
end;

function TvgObject.AddIndex(AIndex: Cardinal): Integer;
begin
  if not Assigned(fDataStore) then
  begin
    Result := -1;
    Exit;
  end;
  if fObjIndex = -1 then
  begin
    Result := -1;
    Exit;
  end;

  Result := fDataStore.AddObjectIndex(fObjIndex, AIndex);
end;

function TvgObject.AddIndex(I1, I2, I3: Cardinal): Integer;
begin
  Result := AddIndex(I1);
  AddIndex(I2);
  AddIndex(I3);
end;

function TvgObject.AddIndices(const AIndices: array of Cardinal): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := Low(AIndices) to High(AIndices) do
  begin
    if I = Low(AIndices) then
      Result := AddIndex(AIndices[I])
    else
      AddIndex(AIndices[I]);
  end;
end;

procedure TvgObject.SetIndex(AIndexPos: Integer; AValue: Cardinal);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;

  fDataStore.SetObjectIndex(fObjIndex, AIndexPos, AValue);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetTriangle(ATriangleIndex: Integer; I1, I2, I3: Cardinal);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;

  fDataStore.SetObjectTriangle(fObjIndex, ATriangleIndex, I1, I2, I3);
  fDataStore.SetDataDirty;
end;

{ Vertex Setters - use current vertex }

procedure TvgObject.SetVertexPosition(X, Y, Z: Single);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentVertex = -1 then
    Exit;

  fDataStore.SetObjectVertexPosition(fObjIndex, fCurrentVertex, X, Y, Z);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetVertexColor(R, G, B: Single; A: Single);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentVertex = -1 then
    Exit;

  fDataStore.SetObjectVertexColor(fObjIndex, fCurrentVertex, R, G, B, A);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetVertexNormal(X, Y, Z: Single);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentVertex = -1 then
    Exit;

  fDataStore.SetObjectVertexNormal(fObjIndex, fCurrentVertex, X, Y, Z);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetVertexTexCoord(U, V: Single);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentVertex = -1 then
    Exit;

  fDataStore.SetObjectVertexTexCoord(fObjIndex, fCurrentVertex, U, V);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetVertexTangent(X, Y, Z: Single);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentVertex = -1 then
    Exit;

  fDataStore.SetObjectVertexTangent(fObjIndex, fCurrentVertex, X, Y, Z);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetVertexBiTangent(X, Y, Z: Single);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentVertex = -1 then
    Exit;

  fDataStore.SetObjectVertexBiTangent(fObjIndex, fCurrentVertex, X, Y, Z);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetVertexIndex(I: Cardinal);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentVertex = -1 then
    Exit;

  fDataStore.SetObjectVertexIndex(fObjIndex, fCurrentVertex, I);
  fDataStore.SetDataDirty;
end;

{ Instance Setters - use current instance }

procedure TvgObject.SetInstanceObjID(ID1, ID2: Cardinal);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentInstance = -1 then
    Exit;

  fDataStore.SetObjectInstanceObjID(fObjIndex, fCurrentInstance, ID1, ID2);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetInstanceColor(R, G, B: Single; A: Single);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentInstance = -1 then
    Exit;

  fDataStore.SetObjectInstanceColor(fObjIndex, fCurrentInstance, R, G, B, A);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetInstanceNormal(X, Y, Z: Single);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentInstance = -1 then
    Exit;

  fDataStore.SetObjectInstanceNormal(fObjIndex, fCurrentInstance, X, Y, Z);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetInstanceTangent(X, Y, Z: Single);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentInstance = -1 then
    Exit;

  fDataStore.SetObjectInstanceTangent(fObjIndex, fCurrentInstance, X, Y, Z);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetInstanceVector(X, Y, Z: Single);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentInstance = -1 then
    Exit;

  fDataStore.SetObjectInstanceVector(fObjIndex, fCurrentInstance, X, Y, Z);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetInstanceMatrix(M: TvgMatrix4x4S);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentInstance = -1 then
    Exit;

  fDataStore.SetObjectInstanceMatrix(fObjIndex, fCurrentInstance, M);
  fDataStore.SetDataDirty;
end;

procedure TvgObject.SetInstanceIndex(I: Cardinal);
begin
  if not Assigned(fDataStore) then
    Exit;
  if fObjIndex = -1 then
    Exit;
  if fCurrentInstance = -1 then
    Exit;

  fDataStore.SetObjectInstanceIndex(fObjIndex, fCurrentInstance, I);
  fDataStore.SetDataDirty;
end;

{ TvgObjectStore }

constructor TvgObjectStore.Create(AOwner: TComponent);
begin
  inherited Create(aOwner);
  fObjects        := TObjectList<TvgObject>.Create(True);  // Owns objects


  fUseShaders    := [PS_VERTEX, PS_FRAGMENT];           // TvgPipelineShaders;
  fPolygonMode   := VK_POLYGON_MODE_FILL;               // TVkPolygonMode;
  fCullMode      := TVkCullModeFlags(VK_CULL_MODE_NONE);// TVkCullModeFlags;
  fFrontFace     := VK_FRONT_FACE_CLOCKWISE ;           // TVkFrontFace;
  fLineWidth     := 5;// Single;
  fPointSize     := 5;// Single;


//  fInstanceDataON   := False;

  fScene := nil;

end;

destructor TvgObjectStore.Destroy;
begin
  ReleaseFromScene;
  FreeAndNil(fObjects);
  inherited;
end;

procedure TvgObjectStore.DisConnectDataFromSceneandRenderer( aRenderer: TvgBaseRenderEngine);
var
  Pair          : TPair<TvgGraphicPipeRecord, TvgGraphicPipeline>;
  GP            : TvgGraphicPipeline;
  SP            : TvgSubPass;
  ToRemove      : TList<TvgGraphicPipeRecord>;
  J             : Integer;

begin
  if not assigned(fGraphicPipes) or (fGraphicPipes.Count = 0) then exit;

  ToRemove := TList<TvgGraphicPipeRecord>.Create;
  try
    for Pair in fGraphicPipes do
    begin
      if Pair.Key.Renderer <> aRenderer then continue;
      GP := Pair.Value;
      SP := Pair.Key.SubPass;
      if assigned(SP) and assigned(GP) then
        SP.RemoveGraphicPipe(GP);
      if assigned(GP) then
      begin
        if GP.Active then GP.Active := False;
        for J := 0 to fObjects.Count - 1 do
          fObjects.Items[J].DisconnectGraphicPipeline(GP);
      end;
      ToRemove.Add(Pair.Key);
    end;
    for var R in ToRemove do
      fGraphicPipes.Remove(R);
  finally
    ToRemove.Free;
  end;


  DeleteVulkanDataBuffers;   // frees TpvVulkanBuffer handles
  SetDataDirty;


end;


procedure TvgObjectStore.SetEnabled;
  var I:Integer;
begin
  inherited;
  fActive := True;

  ObjectsListOfPipes_Update;

  CustomAssert(assigned(fScene), 'Scene NOT assigned');

   FVulkanDevice := fScene.GetVulkanDevice;

   If assigned(FVulkanDevice) and (fObjects.Count>0)  then
     For I:=0 to fObjects.count-1 do
           fObjects.Items[I].Active := True;
end;

procedure TvgObjectStore.SetDisabled;
  Var I:Integer;
begin
  Inherited;
  fActive := False;

   FVulkanDevice := Nil;

  // Skip child deactivation when scene is in a global tear-down.
  if Assigned(fScene) and
     (csDestroying in fScene.ComponentState) and
     (fScene.fSceneState = SS_READY) then
  begin
    if Assigned(fObjects) and (fObjects.Count > 0) then
      for I := 0 to fObjects.Count - 1 do
        fObjects.Items[I].Active := False;
  end;


end;

function TvgObjectStore.GetObjectCount: Integer;
begin
  Result := fObjects.Count;
end;

function TvgObjectStore.GetSelectable: Boolean;
  Var I,L:Integer;
begin
  Result := False;
  L:= self.fObjects.Count;
  If L=0 then exit;
  For I:=0 to L-1 do
    If fObjects.Items[I].SelectON then
    Begin
      Result := True;
      Exit;
    End;
end;

function TvgObjectStore.GetVisible: Boolean;
  Var I,L:Integer;
begin
  Result := False;
  L:= self.fObjects.Count;
  If L=0 then exit;
  For I:=0 to L-1 do
    If fObjects.Items[I].VisibleON then
    Begin
      Result := True;
      Exit;
    End;
end;

function TvgObjectStore.GetActive: Boolean;
begin
  Result := fActive;
end;

function TvgObjectStore.GetEditable: Boolean;
  Var I,L:Integer;
begin
  Result := False;
  L:= self.fObjects.Count;
  If L=0 then exit;
  For I:=0 to L-1 do
    If fObjects.Items[I].EditON then
    Begin
      Result := True;
      Exit;
    End;
end;

function TvgObjectStore.GetFrozen: Boolean;
  Var I,L:Integer;
begin
  Result := False;
  L:= self.fObjects.Count;
  If L=0 then exit;
  For I:=0 to L-1 do
    If fObjects.Items[I].FrozenON then
    Begin
      Result := True;
      Exit;
    End;
end;

function TvgObjectStore.GetLocked: Boolean;
  Var I,L:Integer;
begin
  Result := False;
  L:= self.fObjects.Count;
  If L=0 then exit;
  For I:=0 to L-1 do
    If fObjects.Items[I].LockON then
    Begin
      Result := True;
      Exit;
    End;
end;


function TvgObjectStore.AddObject: TvgObject;
var
  Obj: TvgObject;
begin
  Obj            := TvgObject.Create;
  Obj.fDataStore := Self;
  
  // Add to data store and get index
  Obj.fObjIndex  := AddDataObject(SelectON);

  // Add to our object list
  fObjects.Add(Obj);
  
  Result := Obj;
end;

procedure TvgObjectStore.RemoveObject(aObject: TvgObject);
begin
  if not Assigned(aObject) then
    Exit;
    
  // Remove from our list (will free it since we own it)
  fObjects.Remove(aObject);
  
  // Note: This doesn't remove from the data store's internal object list
  // In a full implementation, you might want to mark objects as deleted
  // or rebuild the data store when objects are removed
end;

procedure TvgObjectStore.ReleaseFromScene;
var
  I : Integer;
 // Renderer : TvgBaseRenderEngine;
begin
  if not Assigned(fObjects) then Exit;

  if Assigned(fScene) and assigned(fScene.RendererList) then
    for I := 0 to fScene.RendererList.Count - 1 do
      if Assigned(fScene.RendererList.Items[I]) then
        DisConnectDataFromSceneandRenderer(fScene.RendererList.Items[I]);

  // Assert the invariant: fGraphicPipes must be empty after disconnect loop
  CustomAssert(fGraphicPipes.Count = 0, 'Pipelines remain after full renderer disconnect');

  try ClearAll(True); except end;
  try fObjects.Clear; except end;
  fActive := False;
end;


procedure TvgObjectStore.ClearData;
  Var J,I:Integer;
begin

// ClearGraphicPipes is unsafe — use DisConnectDataFromSceneandRenderer instead
  // which calls SP.RemoveGraphicPipe before clearing the dictionary.
  If assigned(fScene) and assigned(fScene.fRendererList) then
    for J := 0 to fScene.fRendererList.Count-1 do
      DisConnectDataFromSceneandRenderer(fScene.fRendererList.Items[J]);

  If fObjects.Count>0 then
    For I:=0 to fObjects.Count-1 do
      fObjects.Items[I].Active := False;


  fObjects.Clear;

  ClearAll(True);

end;

procedure TvgObjectStore.ClearGraphicPipes;
begin
  inherited;

end;

procedure TvgObjectStore.ConfigureGraphicPipeline(GP: TvgGraphicPipeline);
var
  SHS: TvgShaderSpecialisationItem;
begin

    // Shader files — ObjectStore owns these
    GP.BuildShaderVertexName( fShaderBaseVertName);
 //   GP.GeometryS.FileName := fGe                      FINISH
    GP.BuildShaderFRagmentName(fShaderBaseFragName);

    GP.UseShaders         := fUseShaders;        // new property, not hardcoded [PS_VERTEX, PS_FRAGMENT]

    // Topology — ObjectStore owns this
    GP.InputAssembly.Topology := GetVGPrimitiveTopology(fTopology);

    if GP.InputAssembly.Topology = POINT_LIST then
    begin
      SHS := GP.VertexS.SpecialConst.Add;
      SHS.Name := 'POINT_SIZE_ON';
      SHS.SpecType := TS_BOOLEAN;
      SHS.SpecTValue := 'TRUE';
      SHS.ConstantID := CI_POINT_SIZE_ON;
    end;

    // Rasterizer — ObjectStore owns these (new properties)
    GP.Rasterizer.PolygonMode := GetVGPolygonMode(fPolygonMode);   // default POLYGON_FILL
    GP.Rasterizer.CullMode    := GetVGCullMode(fCullMode);      // default CULL_BACK (not NONE)
    GP.Rasterizer.FrontFace   := GetVGFrontFace(fFrontFace);     // default FF_CLOCKWISE
    GP.Rasterizer.LineWidth   := fLineWidth;     // default 1.0

end;

procedure TvgObjectStore.ConnectDataToRenderer(aRenderer: TvgBaseRenderEngine);

begin

end;

procedure TvgObjectStore.ObjectsListOfPipes_Update;
begin
  // Update graphics pipelines for all objects
  // This would connect objects to their respective pipelines
  UpdateGraphicPipelines;
end;

procedure TvgObjectStore.ObjectsListOfPipes_Clear;
begin
  // Clear pipeline connections
  // This would disconnect objects from pipelines
end;


{ TvgScene }

Function TvgScene.AddDataStore(aDataStore: TvgObjectStore):Boolean;
 // Var I:Integer;
begin
  Result := False;

  If not (fSceneState = SS_LOADING   ) then exit;
  If not assigned( aDataStore) then exit;

  CustomAssert(Assigned(fSceneData),'Scene Data list NOT created',self);

  If fSceneData.IndexOf(aDataStore)=-1 then
    Begin

      fSceneData.Add(aDataStore);
      aDataStore.fScene     := Self;
      aDataStore.fBaseScene := self;  //important

      aDataStore.FVulkanDevice :=  GetVulkanDevice;
    End;

  Result := True;

end;

procedure TvgScene.BuildGraphicPipelinesForRenderer(aRenderer: TvgBaseRenderEngine);
var
  J, K  : Integer;
  SP    : TvgSubPass;
  ObjStr: TvgObjectStore;
begin
  if not assigned(aRenderer) then exit;
  if not assigned(aRenderer.RenderPass) then exit;
  if aRenderer.RenderPass.SubPasses.Count = 0 then exit;
  if not assigned(fSceneData) or (fSceneData.Count = 0) then exit;

  for J := 0 to aRenderer.RenderPass.SubPasses.Count - 1 do
  begin
    SP := aRenderer.RenderPass.SubPasses.Items[J];
    if not assigned(SP) then continue;

    for K := 0 to fSceneData.Count - 1 do
    begin
      ObjStr := fSceneData.Items[K];
      if assigned(ObjStr) then
      begin
        ObjStr.BuildAGraphicPipeline(aRenderer, SP);
        // Note: do NOT activate here — ActivateGraphicPipeLines does that
        // Note: do NOT set ObjStr.Active := True here — it may already be active
        //       for another renderer and its SetEnabled would re-run UpdateGraphicPipelines
      end;
    end;
  end;
end;

procedure TvgScene.ClearGraphicPipelines(aRenderer: TvgBaseRenderEngine;  aSubPass: TvgSubpass);
  Var I:Integer;
    // OS:TvgObjectStore;
begin
  CustomAssert(assigned(aRenderer),'Renderer NOT assigned',self);
  CustomAssert(assigned(aSubPass),'SubPass NOT assigned',self);

  If self.fSceneData.Count=0 then exit;

  For I:=0 to  fSceneData.count-1 do
    fSceneData.items[I].FreeGraphicPipeline(aRenderer ,aSubPass);

end;

// CORRECTED ClearScene implementation

procedure TvgScene.ClearScene;
var
  I, J : Integer;
  SD   : TvgObjectStore;
  R    : TvgBaseRenderEngine;
begin
  If NOT (fSceneState = SS_READY) then exit;

  CustomAssert(Assigned(fSceneData), 'Scene Data List NOT assigned',self);
  if fSceneData.Count = 0 then Exit;

  SetActiveState(False);

  // STEP 1: Disconnect all stores from all renderers
  if Assigned(fRendererList) then
    for J := 0 to fRendererList.Count - 1 do
      for I := 0 to fSceneData.Count - 1 do
      begin
        SD := fSceneData.Items[I];
        if Assigned(SD) then
          SD.DisConnectDataFromSceneandRenderer(fRendererList.Items[J]);
      end;

  // STEP 2: Clear each store safely
  for I := 0 to fSceneData.Count - 1 do
  begin
    SD := fSceneData.Items[I];
    if Assigned(SD) then
      SD.ClearData;   // handles objects + GPU buffers + pipes
  end;

  // STEP 3: Destroy stores (OwnsObjects = True)
  fSceneData.Clear;

  // STEP 4: Request rebuild of ALL frames
  if Assigned(fRendererList) then
    for J := 0 to fRendererList.Count - 1 do
    begin
      R := fRendererList.Items[J];
      if Assigned(R) then
      Begin
        R.FlagRebuildALLFrames;
        If R.Active then
           R.TriggerWindowRepaint;
      End;
    end;

end;


procedure TvgScene.ConnectDataToRenderer(  aRenderEngine: TvgBaseRenderEngine);
  Var I:Integer;
begin
  If not assigned(aRenderEngine) then exit;
  CustomAssert(assigned(fSceneData),'Scene Data List NOT created',self);
  If fSceneData.Count=0 then exit;
  CustomAssert(assigned(fRendererList),'Renderers List NOT created',self);

  For I:=0 to fSceneData.Count-1 do
    fSceneData.Items[I].ConnectDataToRenderer(aRenderEngine)  ;

end;

procedure TvgScene.ConnectDataToVulkanDevice( aScreenDevice: TvgScreenRenderDevice);
  Var I:Integer;
begin
  CustomAssert(assigned(aScreenDevice),'Screen Device NOT supplied',self) ;
  CustomAssert(aScreenDevice.Active,'Screen Device NOT active',self) ;
  CustomAssert(assigned(aScreenDevice.VulkanDevice),'VULKAN Screen Device NOT supplied',self) ;

  If fSceneData.Count=0 then exit;

  For I:= 0 to  fSceneData.Count-1 do
     fSceneData.Items[I].FVulkanDevice := GetVulkanDevice;

end;

constructor TvgScene.Create(AOwner: TComponent);
begin
  inherited;

  fSceneData             := TObjectList<TvgObjectStore>.Create;
  fSceneData.OwnsObjects := True;
  //important

  fCameras   := TvgCameraManager.Create;

end;

destructor TvgScene.Destroy;
begin
  SetActiveState(False);   //disables the nodes

  ClearScene;  //clears the scene

  if assigned(fSceneData) then
     FreeAndNil(fSceneData);

  If assigned(fCameras) then
     FreeAndNil(fCameras);

  inherited;
end;

procedure TvgScene.DisConnectDataFromRenderer( aRenderEngine: TvgBaseRenderEngine);
  Var I:Integer;
begin
  If not assigned(aRenderEngine) then exit;

  If not assigned(fSceneData) then exit;     //may be nil during the DESTROY of the Scene
  If fSceneData.Count=0 then exit;

  For I:=0 to fSceneData.Count-1 do
    fSceneData.Items[I].DisConnectDataFromSceneandRenderer(aRenderEngine)  ;

  If (csDestroying in aRenderEngine.componentState) then
    DisConnectRenderEngine( aRenderEngine);

  If (fRendererList.count=0) or
     (assigned(fScreenDevice) and (fScreenDevice.StateChanging)) then
  Begin
     SetActiveState(False);
  End;

end;

function TvgScene.GetObjectCount: Integer;
  Var I:Integer;
begin
  Result := 0;
  If fSceneData.Count=0 then exit;


  For I:=0 to fSceneData.Count-1 do
  Begin
    Result := Result + fSceneData.Items[I].GetObjectCount;
  End;
end;

function TvgScene.GetObjectStore(Index: Integer): TvgBaseObjectStore;
begin
  If (Index>=0) and (Index<fSceneData.Count) then
     Result := fSceneData.Items[Index]
  else
     Result := Nil;
end;

function TvgScene.GetObjectStoreCount: Integer;
begin
  Result := fSceneData.count;
end;

procedure TvgScene.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;

end;

Procedure TvgScene.PrepareFrameGlobalData(aTarget : IvgGlobalDataTarget; aFrameIndex : TvkUint32);

var
  Cam    : TvgCamera;
  Aspect : Single;
begin
  if not Assigned(fCameras) then exit;

  Cam := fCameras.GetActiveCamera;
  if not Assigned(Cam) then exit;

  // Ask this renderer for its own current aspect ratio.
  // Every renderer calling PrepareFrameGlobalData gets its own value here,
  // so a scene shared across a 16:9 window and a 4:3 window is handled
  // correctly with no coordination between renderers required.
  Aspect := aTarget.GetViewportAspect;

  // Build a VP matrix correct for this renderer's viewport.
  // FAspectRatio on the camera is NEVER written — it remains the camera's
  // "design" aspect (used for tools, ray-casting, frustum culling etc.)
  // Each renderer gets its own freshly-computed projection every frame.
  aTarget.SetViewProjectMatrix(aFrameIndex,  Cam.GetViewProjectionMatrixForAspect(Aspect));

  // Future global data — each also receives the correct per-renderer context:
  // aTarget.SetLightData(aFrameIndex, fLights.BuildShaderBlock);
  // aTarget.SetTimeData(aFrameIndex, fTimeAccumulator);
end;

Function TvgScene.SetDisabled:Boolean;
  Var I:Integer;
begin

  Inherited;
  Result := True;

  If (csDestroying in ComponentState) then exit;

  CustomAssert(assigned(fSceneData),'Scene Data List NOT available',self);

  If  fSceneData.Count>0 then
    For I:=0 to fSceneData.Count-1 do
      fSceneData.Items[I].Active := False;

  If fCameras.GetCameraCount>0 then
  Begin
    //maybe need to deactivate cameras
  End;

end;

Function TvgScene.SetEnabled:Boolean;

 var I : Integer;
     ObjStr : TvgObjectStore;

begin
  Result := inherited;

  CustomAssert(assigned(fSceneData),'Scene Data List NOT available',self);
  CustomAssert(assigned(fRendererList),'Renderer List NOT available',self);

 // If fRendererList.count=0 then exit;

  If fSceneData.Count>0 then
    For I:=0 to fSceneData.count-1 do
    Begin
      ObjStr := fSceneData.items[I];
      If assigned(ObjStr) then
        ObjStr.Active := True;
    End;

  Result := True;

end;


procedure TvgScene.SetOnMouseOver(const Value: TvgSceneMouseOverObject);
begin
  fOnMouseOver := Value;
end;

{ TvgSceneLoaderStorer }

Procedure TvgSceneLoaderStorer.AddDescriptor_Texture(aDescriptorName : String;
                                                     aImageFileName  : String);
   Var R:TvgResourceUse;
      DI:TvgDescriptorItem;
      S: String;
      Tex:TvgDescriptorArray_Texture;


      aGLSLIndex:TvkUint32;
begin

    If not assigned(fCurrentObjectStore) then exit;
    If (aDescriptorName='') then exit;
    If (aImageFileName='') then exit;


   If not (RU_OBJECTSTORE in fCurrentObjectStore.ResourceUse) then
   Begin
      R:=  fCurrentObjectStore.ResourceUse;
      Include(R, RU_OBJECTSTORE);
      fCurrentObjectStore.ResourceUse:=R;
   End;

    If assigned(fCurrentObjectStore.ObjectStoreRes) then
    Begin
      DI := fCurrentObjectStore.ObjectStoreRes.Descriptors.Add ;

      If assigned(DI) then
      Begin
        S := TvgDescriptorArray_Texture.GetPropertyName ;
        DI.DescriptorName := S;
        If assigned(DI.Descriptor) then
        Begin
          DI.Name       := aDescriptorName;

          If assigned(DI.Descriptor) and (DI.Descriptor is TvgDescriptorArray_Texture) then
          Begin
            Tex              := TvgDescriptorArray_Texture(DI.Descriptor);
            Tex.Name         := aDescriptorName;
            Tex.ResourceType := RT_GROUPTEX;
            Tex.FrameCount   := 1;
            Tex.BindingCount := 1;



            Tex.AddTexture('ObjectStoreTexture',aImageFileName)   ;


          //  DI.GLSLIndex := aGLSLIndex;

          End;
        end;
      End;

    End;


end;

function TvgSceneLoaderStorer.AddObjectStore: TvgObjectStore;
begin
  Result := TvgObjectStore.Create(nil);
  fCurrentObjectStore := Result;

  If assigned(fScene) then
     fScene.AddDataStore(Result) ;
end;

procedure TvgSceneLoaderStorer.SetScene(const Value: TvgScene);
begin
  if assigned(fScene) then
     fScene.ClearScene;

  fScene := Value;
end;


{ TvgToolManager }

constructor TvgToolManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  fScene          := nil;
  fActionMode     := TAM_CAMERA_ORBIT;
  fOrbitButton    := vgmbLeft;
  fPanButton      := vgmbMiddle;
  fDollyButton    := vgmbRight;
  fSelectedObject := nil;
  fDragPlaneAxis  := 0;
  fDragStartHitPt := TpvVector3.Create(0, 0, 0);
  fDragPlaneValid := False;
end;

destructor TvgToolManager.Destroy;
begin
  fSelectedObject := nil;   // not owned
  fScene          := nil;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
//  Private setters
// ---------------------------------------------------------------------------

procedure TvgToolManager.SetScene(const Value: TvgScene);
begin
  If fScene = Value then exit;
  If Assigned(fScene) then
    fScene.RemoveFreeNotification(Self);
  fScene := Value;
  If Assigned(fScene) then
    fScene.FreeNotification(Self);
  ClearSelection;
end;

procedure TvgToolManager.SetActionMode(const Value: TvgToolActionMode);
begin
  If fActionMode = Value then exit;
  fActionMode := Value;
  ClearSelection;
end;

procedure TvgToolManager.SetOrbitButton(const Value: TvgMouseButton);
begin
  fOrbitButton := Value;
end;

procedure TvgToolManager.SetPanButton(const Value: TvgMouseButton);
begin fPanButton := Value; end;

procedure TvgToolManager.SetRenderer(const Value: TvgRenderEngine);
begin
   If fRenderer = Value then exit;
   SetActiveState(False) ;

  fRenderer := Value;
end;

procedure TvgToolManager.SetDollyButton(const Value: TvgMouseButton);
begin fDollyButton := Value; end;

procedure TvgToolManager.SetDragPlaneAxis(const Value: Integer);
begin
  fDragPlaneAxis := EnsureRange(Value, 0, 2);
  fDragPlaneValid := False;
end;

function TvgToolManager.SetEnabled: Boolean;
begin
  Inherited;
  Result := True;

end;

procedure TvgToolManager.Notification(AComponent: TComponent;
                                       Operation: TOperation);
begin
  inherited  Notification(AComponent, Operation);;

  Case Operation of
     opInsert:
     Begin
       If (AComponent is TvgScene) and not assigned(fScene) then
       Begin
         Scene := TvgScene(AComponent) ;
       End;

       If (AComponent is TvgRenderEngine) and not assigned(fRenderer) then
       Begin
         Renderer := TvgRenderEngine(AComponent) ;
       End;
     End;

     opRemove:
     Begin
       If (AComponent is TvgScene) and (fScene = TvgScene(AComponent)) then
       Begin
         Scene := Nil;
       End;

       If (AComponent is TvgRenderEngine) and (fRenderer = TvgRenderEngine(AComponent)) then
       Begin
         Renderer := Nil ;
       End;

     End;
  End;

end;

Function TvgToolManager.SetDisabled:Boolean;
begin
  inherited;
  Result := True;
  ClearSelection;
end;

// ---------------------------------------------------------------------------
//  Public helpers
// ---------------------------------------------------------------------------

procedure TvgToolManager.ClearSelection;
begin
  fSelectedObject := nil;
  fDragPlaneValid := False;
end;

// ---------------------------------------------------------------------------
//  Private helpers
// ---------------------------------------------------------------------------

function TvgToolManager.GetActiveCamera: TvgCamera;
begin
  Result := nil;
  If not Assigned(fScene) then exit;
  If not Assigned(fScene.Cameras) then exit;
  Result := fScene.Cameras.GetActiveCamera;
end;

function TvgToolManager.GetCurrentFrameIndex: TvkUint32;
begin
  Result := 0;
  If Assigned(fLinker) then
    Result := TvkUint32(Max(0, fLinker.PresentFrameIndex));
end;

function TvgToolManager.GetDragPlaneNormal: TpvVector3;
begin
  case fDragPlaneAxis of
    0 : Result := TpvVector3.Create(0, 1, 0);   // XZ  — horizontal (Y-up world)
    1 : Result := TpvVector3.Create(0, 0, 1);   // XY  — vertical, facing +Z
    2 : Result := TpvVector3.Create(1, 0, 0);   // YZ  — vertical, facing +X
  else
    Result := TpvVector3.Create(0, 1, 0);
  end;
end;

function TvgToolManager.ScreenRayHitsPlane(aX, aY: Integer;
                                            const aPlaneNormal: TpvVector3;
                                            const aPlanePoint:  TpvVector3;
                                            out   aHitPoint:    TpvVector3): Boolean;
  Var
    Cam   : TvgCamera;
    Ray   : TpvVector3;
    Orig  : TpvVector3;
    W, H  : Integer;
    Denom : Single;
    T     : Single;
    Diff  : TpvVector3;
begin
  Result    := False;
  aHitPoint := TpvVector3.Create(0, 0, 0);

  Cam := GetActiveCamera;
  If not Assigned(Cam) then exit;
  If not GetViewportSize(W, H) then exit;
  If (W <= 0) or (H <= 0) then exit;

  Ray  := Cam.ScreenToWorldRay(aX, aY, W, H);
  Orig := Cam.Position;

  // Ray–plane intersection:  t = dot(planePoint - rayOrigin, planeNormal)
  //                              / dot(ray, planeNormal)
  Denom := aPlaneNormal.x * Ray.x +
           aPlaneNormal.y * Ray.y +
           aPlaneNormal.z * Ray.z;

  If Abs(Denom) < 1e-6 then exit;  // Ray nearly parallel to plane

  Diff.x := aPlanePoint.x - Orig.x;
  Diff.y := aPlanePoint.y - Orig.y;
  Diff.z := aPlanePoint.z - Orig.z;

  T := (aPlaneNormal.x * Diff.x +
        aPlaneNormal.y * Diff.y +
        aPlaneNormal.z * Diff.z) / Denom;

  If T < 0 then exit;  // Intersection behind camera

  aHitPoint.x := Orig.x + Ray.x * T;
  aHitPoint.y := Orig.y + Ray.y * T;
  aHitPoint.z := Orig.z + Ray.z * T;
  Result := True;
end;

// ---------------------------------------------------------------------------
//  DispatchCameraGesture
//  Centralises the logic: which button + shift ? which camera action.
//  Called from DoMouseMove with the scaled pixel deltas.
// ---------------------------------------------------------------------------
procedure TvgToolManager.DispatchCameraGesture(Shift: TShiftState;
                                                aDeltaX, aDeltaY: Single);
begin
  // Shift+button or middle button ? pan
  If (fPanButton in fMouseButtons) or
     ((fOrbitButton in fMouseButtons) and (ssShift in Shift)) then
  Begin
    DoCameraPan(aDeltaX, aDeltaY);
    exit;
  End;

  // Ctrl+button or dolly button ? dolly
  If (fDollyButton in fMouseButtons) or
     ((fOrbitButton in fMouseButtons) and (ssCtrl in Shift)) then
  Begin
    DoCameraDolly(aDeltaY);
    exit;
  End;

  // Orbit button (plain) ? orbit
  If fOrbitButton in fMouseButtons then
    DoCameraOrbit(aDeltaX, aDeltaY);
end;

// ---------------------------------------------------------------------------
//  Camera operations
// ---------------------------------------------------------------------------

procedure TvgToolManager.DoCameraOrbit(aDeltaX, aDeltaY: Single);
  Var Cam : TvgCamera;
begin
  Cam := GetActiveCamera;
  If not Assigned(Cam) then exit;
  // Orbit: yaw = horizontal mouse, pitch = vertical mouse.
  // Sensitivity is already baked into the delta by the caller.
  Cam.Orbit(aDeltaX, aDeltaY, True);
end;

procedure TvgToolManager.DoCameraPan(aDeltaX, aDeltaY: Single);
  Var Cam : TvgCamera;
begin
  Cam := GetActiveCamera;
  If not Assigned(Cam) then exit;
  // TvgCamera.Pan already scales by distance * 0.01 internally,
  // so we pass the raw (sensitivity-scaled) pixel delta.
  Cam.Pan(aDeltaX, aDeltaY);
end;

procedure TvgToolManager.DoCameraDolly(aDelta: Single);
  Var Cam : TvgCamera;
begin
  Cam := GetActiveCamera;
  If not Assigned(Cam) then exit;
  // aDelta: positive = forward into the scene.
  Cam.Dolly(aDelta * 0.05);
end;

procedure TvgToolManager.DoCameraZoom(aWheelDelta: Integer);
  Var Cam        : TvgCamera;
      NormDelta  : Single;
begin
  Cam := GetActiveCamera;
  If not Assigned(Cam) then exit;
  // Standard Windows wheel: 120 units per notch.
  // TvgCamera.Zoom uses (1 - delta * 0.1), so 1 notch ? 10% distance change.
  NormDelta := aWheelDelta / 120.0;
  Cam.Zoom(NormDelta);
end;

// ---------------------------------------------------------------------------
//  Object operations
// ---------------------------------------------------------------------------

procedure TvgToolManager.DoPickObject(aFrameIndex: TvkUint32;
                                       Shift: TShiftState; X, Y: Integer);
  Var
    Obj     : TvgObject;
    PlaneNorm : TpvVector3;
   // WorldHit  : TpvVector3;
begin
  If not Assigned(fLinker)           then exit;
  If not Assigned(fLinker.Renderer)  then exit;
  If not Assigned(fScene)            then exit;

  // Query the object-ID storage image at this pixel
  Obj := fRenderer.GetObjectAtLocation(aFrameIndex, Shift, X, Y);

  If Assigned(Obj) then
  Begin

    If Assigned(Obj) and Obj.SelectON then
    Begin
      fSelectedObject := Obj;

      // Pre-compute the world-space hit point on the drag plane so that
      // DoDragObject can track deltas without per-frame camera queries.
      PlaneNorm       := GetDragPlaneNormal;
      fDragPlaneValid := ScreenRayHitsPlane(X, Y, PlaneNorm,
                                             TpvVector3.Create(0, 0, 0),
                                             fDragStartHitPt);

      If Assigned(fOnObjectPicked) then
        fOnObjectPicked(Self, fSelectedObject);
    End;
  End
  else
  Begin
    // Clicked on background — deselect
    ClearSelection;
  End;
end;

procedure TvgToolManager.DoDragObject(X, Y: Integer);
  Var
    PlaneNorm : TpvVector3;
    HitPoint  : TpvVector3;
    NewPos    : TpvVector3;
begin
  If not Assigned(fSelectedObject) then exit;
  If not fDragPlaneValid           then exit;

  PlaneNorm := GetDragPlaneNormal;

  // Re-intersect the current mouse ray with the same drag plane.
  // fDragStartHitPt is used as the plane anchor so the plane stays fixed.
  If ScreenRayHitsPlane(X, Y, PlaneNorm, fDragStartHitPt, HitPoint) then
  Begin
    // Translate: new position = start position + movement delta on plane
    NewPos.x := fDragStartHitPt.x + (HitPoint.x - fDragStartHitPt.x);
    NewPos.y := fDragStartHitPt.y + (HitPoint.y - fDragStartHitPt.y);
    NewPos.z := fDragStartHitPt.z + (HitPoint.z - fDragStartHitPt.z);

    // The handler receives the running world position.
    // It should apply:  object.translate(newPos - lastPos) on each call, or
    // store the initial vertex centroid and set absolute position.
    If Assigned(fOnObjectMoved) then
      fOnObjectMoved(Self, fSelectedObject, NewPos);
  End;
end;

procedure TvgToolManager.DoAddObjectRequest(X, Y: Integer);
  Var
    PlaneNorm : TpvVector3;
    HitPoint  : TpvVector3;
begin
  PlaneNorm := GetDragPlaneNormal;
  If ScreenRayHitsPlane(X, Y, PlaneNorm, TpvVector3.Create(0, 0, 0), HitPoint) then
  Begin
    If Assigned(fOnObjectAddReq) then
      fOnObjectAddReq(Self, HitPoint);
  End;
end;

// ---------------------------------------------------------------------------
//  Virtual mouse handler overrides
// ---------------------------------------------------------------------------

procedure TvgToolManager.DoMouseDown(aButton: TvgMouseButton;
                                      Shift: TShiftState; X, Y: Integer);
begin
  case fToolMode of

    TMM_CAMERA:
      ; // Camera dragging starts on MouseMove; nothing to do on Down.

    TMM_OBJECT_EDIT:
    begin
      // In object-edit mode, a left-button press picks an object immediately
      // (so we have selection before any drag begins).
      If aButton = vgmbLeft then
      Begin
        case fActionMode of
          TAM_OBJECT_SELECT,
          TAM_OBJECT_MOVE:
            DoPickObject(GetCurrentFrameIndex, Shift, X, Y);

          TAM_OBJECT_ADD:
            ; // Handled on MouseUp so accidental micro-moves don't trigger

          TAM_CAMERA_ORBIT,
          TAM_CAMERA_PAN,
          TAM_CAMERA_DOLLY:
            ; // Camera-gesture sub-modes — handled in DoMouseMove
        end;
      End;
    end;
  end;
end;

procedure TvgToolManager.DoMouseMove(Shift: TShiftState; X, Y: Integer);
  Var
    dX, dY : Single;
begin
  If not fIsDragging then exit;  // No button currently held

  // Scale pixel deltas by global sensitivity
  dX := (X - fLastMouseX) * fMouseSensitivity;
  dY := (Y - fLastMouseY) * fMouseSensitivity;

  If (dX = 0.0) and (dY = 0.0) then exit;

  case fToolMode of

    TMM_CAMERA:
      DispatchCameraGesture(Shift, dX, dY);

    TMM_OBJECT_EDIT:
    begin
      case fActionMode of

        TAM_CAMERA_ORBIT,
        TAM_CAMERA_PAN,
        TAM_CAMERA_DOLLY:
          // Camera gesture sub-modes used while staying in OBJECT_EDIT
          DispatchCameraGesture(Shift, dX, dY);

        TAM_OBJECT_SELECT:
          // Selection is click-only; allow camera pan with middle button
          If fPanButton in fMouseButtons then
            DoCameraPan(dX, dY);

        TAM_OBJECT_MOVE:
        Begin
          If (fOrbitButton in fMouseButtons) and Assigned(fSelectedObject) then
            // Left drag on a selected object ? move it
            DoDragObject(X, Y)
          else
            // Otherwise treat as camera gesture (pan/dolly with other buttons)
            DispatchCameraGesture(Shift, dX, dY);
        End;

        TAM_OBJECT_ADD:
          // Allow camera panning while hovering in add mode
          If fPanButton in fMouseButtons then
            DoCameraPan(dX, dY);

      end;  // case fActionMode
    end;    // TMM_OBJECT_EDIT

  end;  // case fToolMode
end;

procedure TvgToolManager.DoMouseUp(aButton: TvgMouseButton;
                                    Shift: TShiftState; X, Y: Integer);
begin
  case fToolMode of

    TMM_OBJECT_EDIT:
    begin
      // Fire add-request on left-button release only when no drag occurred
      If (aButton = vgmbLeft) and
         (fActionMode = TAM_OBJECT_ADD) and
         (not fIsDragging) then
        DoAddObjectRequest(X, Y);

      // Reset drag plane validity when button is released
      If aButton = vgmbLeft then
        fDragPlaneValid := False;
    end;
  end;
end;

procedure TvgToolManager.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer);
begin
  // Mouse wheel always zooms regardless of tool mode
  DoCameraZoom(WheelDelta);
end;



{ TvgRenderEngine }

procedure TvgRenderEngine.VaildateGlobalResources;

//called in Create
 var     DI   : TvgDescriptorItem;
           DA  :TvgDescriptorArray;
          SI  : TvgDescriptorArray_StorageImage;
          SID : TvgDescriptor_Data_StorageImage;

          Mat4: TvgDescriptorArray_UBO_4x4MatrixD;
          I: Integer;
          FC :Integer;
          M:TvgMatrix4x4D;
begin
  CustomAssert(assigned(fGlobalRes),'Global Resource not assigned',Self);


  //simple Model/View/Proj Matrix
  //Should to the initial Model/View/Project multiplation in Dpouble precision in CPU
  If assigned(fLinker) then
  Begin
    FC:= fLinker.FrameCount  ;
  end else
    FC:=MaxFramesInFlight;


  If (fGlobalRes.GetDescriptorItem(GlobalViewProjectDescriptor)=nil) then
  Begin

    DI:=fGlobalRes.Descriptors.Add ;

    If assigned(DI) then
    Begin
      DI.Name           := GlobalViewProjectDescriptor;
      DI.DescriptorName := TvgDescriptorArray_UBO_4x4MatrixD.GetPropertyName;   //will create the DA

      If assigned(fLinker) then
          DI.Device      := fLinker.ScreenDevice;

      DA                 := DI.Descriptor;

      If assigned(DA) then
      Begin
        DA.DescriptorItem   := DI;

        DA.ResourceType :=  RT_VIEWPROJECTMAT;
        DA.FrameCount   :=  FC;


        If (DA is TvgDescriptorArray_UBO_4x4MatrixD)  then
        Begin
          Mat4 :=  TvgDescriptorArray_UBO_4x4MatrixD(DA );

          Mat4.AddMatrix;      //add an new descriptor Data/frame data

          M:=TvgMatrix4x4D.Identity;

          For I:=0 to Mat4.frameCount-1 do
            Mat4.Matrix[0, I, 0 ]:= M;
        end;
        DA.SetUploadFlags;
      end;
    End;
  end else
  Begin


  End;


  If SelectON and (fGlobalRes.GetDescriptorItem(GlobalObjectIDDescriptor)=nil)  then     //all OK
  Begin

    DI:=fGlobalRes.Descriptors.Add ;
    If assigned(DI) then
    Begin

      DI.Name          := GlobalObjectIDDescriptor;
      If assigned(fLinker) then
          DI.Device    := fLinker.ScreenDevice;

      DI.DescriptorName := TvgDescriptorArray_StorageImage.GetPropertyName;
      DA:= DI.Descriptor;

      If assigned(DA) then
      Begin

        DA.ResourceType := RT_STORAGEIMAGE;
        DA.DataFlow     := [DF_DOWN, DF_SAMPLING];
        DA.FrameCount   := FC;
        DA.SetStageFlags(TVkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT));

        If DA is TvgDescriptorArray_StorageImage then
        Begin
          SI := TvgDescriptorArray_StorageImage(DA);
          SI.ImageFormat := R32G32_UINT;
          SID := TvgDescriptor_Data_StorageImage.Create;
          SID.PixelSample := True;
          SID.PixRadius := psr_1x1;
          if SI.AddStorageImage(SID) < 0 then
          Begin
            SID.Free;
            raise EInvalidOperation.Create(
              'Unable to create the global ObjectID storage image descriptor');
          End;
          fObjectIDImage := SI;
        End;
      end;
    End;

    DI := fGlobalRes.GetDescriptorItem(GlobalObjectIDDescriptor);
    if Assigned(DI) and
       (DI.Descriptor is TvgDescriptorArray_StorageImage) then
      fObjectIDImage := TvgDescriptorArray_StorageImage(DI.Descriptor);

  end;



  //screen size UBO
  (*
    DI:=fGlobalRes.Descriptors.Add ;
    If assigned(DI) then
    Begin
      DI.DescriptorName :=TvgDescriptor_UBO_2UI.GetPropertyName;

      If not assigned(DI.Descriptor) then
         DI.Descriptor := TvgDescriptor_UBO_2UI.create(nil);

      DI.Name          := GlobalObjectScreenSize;
      If assigned(fLinker) then
          DI.Device    := fLinker.ScreenDevice;

      D:= DI.Descriptor;
      If assigned(D) then
      Begin

        D.Name         := GlobalObjectScreenSize;
        D.ResourceType := RT_UBO;
        D.FrameCount   := FC;                  //one image per frame
        D.DataFlow     := [DF_UP];


        If  (D is TvgDescriptor_UBO_2UI) then
        Begin
          UB              := TvgDescriptor_UBO_2UI(D);
        //  UB.ElementCount := 1;
          UB.setupData;
        End;

      // IMPORTANT: force upload for all frames
       // D.SetUploadFlags;

      end;
    End;

  end;
 *)

  //StorageImage
(*
    DI:=fGlobalRes.Descriptors.Add ;
    If assigned(DI) then
    Begin
      DI.DescriptorName := TvgDescriptor_StorageImage.GetPropertyName;

      If not assigned(DI.Descriptor) then
         DI.Descriptor := TvgDescriptor_StorageImage.create(nil);

      DI.Name          := GlobalObjectIDDescriptor;
      If assigned(fLinker) then
          DI.Device    := fLinker.ScreenDevice;

      D:= DI.Descriptor;
      If assigned(D) then
      Begin

        D.Name         := GlobalObjectIDDescriptor;
        D.ResourceType := RT_STORAGEIMAGE;
        D.FrameCount   := FC;                  //one image per frame


        If  (D is TvgDescriptor_StorageImage) then
        Begin
          SI             := TvgDescriptor_StorageImage(D);
          fObjectIDImage := SI;        //flag object Image in Render Engine

          SI.PixFormat   := R32G32_UINT;  //unsigned integer pair
          SI.PixelSample := True;
          SI.PixRadius   := psr_1x1;

          SI.SetStageFlags(TVkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT));

        End;

      // IMPORTANT: force upload for all frames
        D.SetUploadFlags;

      end;

    End;

    *)


end;

procedure TvgRenderEngine.ConfigureGraphicPipelineFromRenderPass( GP: TvgGraphicPipeline);
   Var SHS : TvgShaderSpecialisationItem;

begin
  // MSAA from RenderPass
  if fRenderPass.MSAAOn then
  begin
    GP.Multisampling.SampleShadingEnable    := True;
    GP.Multisampling.RasterizationSamples   := fRenderPass.MSAASample;
  end;

  // Depth from RenderPass (SubPass may have already disabled this above)
  if fRenderPass.DepthBufOn and GP.DepthStencil.DepthTestEnable then
    GP.SetUpDepthStencilState(True, fRenderPass.StencilBufOn, fRenderPass.DepthCompare);

  // Feature flags are owned by the renderer and propagated to each pipeline.
  if SelectON then
  begin

    SHS := GP.VertexS.SpecialConst.add;    //vertex
    If assigned(SHS) then
    Begin
      SHS.Name       :=  'USE_OBJECTID' ;
      SHS.SpecType   :=  TS_BOOLEAN;
      SHS.SpecTValue := 'TRUE';
      SHS.ConstantID := CI_USE_OBJECTID;
    end;

    SHS := GP.FragmentS.SpecialConst.add;  //Fragment
    If assigned(SHS) then
    Begin
      SHS.Name       := 'USE_OBJECTID';
      SHS.SpecType   :=  TS_BOOLEAN;
      SHS.SpecTValue := 'TRUE';
      SHS.ConstantID := CI_USE_OBJECTID;
    end;
  end;

  if ShaderUseDouble then
  begin
    SHS := GP.VertexS.SpecialConst.add;    //vertex only
    If assigned(SHS) then
    Begin
      SHS.Name       :=  'USE_DOUBLE' ;
      SHS.SpecType   :=  TS_BOOLEAN;
      SHS.SpecTValue := 'TRUE';
      SHS.ConstantID := CI_USE_DOUBLE;
    end;
  end;
end;

function TvgRenderEngine.GetObjectAtLocation(aFrameIndex: TvkUint32; Shift: TShiftState; X, Y: Integer): TvgObject;
var
  DD: TvgDescriptor_Data_StorageImage;
  Pixel: TvgPixelData;
  ObjectAddress: UInt64;
  Candidate: TObject;
  SampleX, SampleY: Integer;
begin
  Result := Nil;

  If State = vgcsInactive then exit;
  if not SelectON then exit;
  If not assigned(fScene) or (fScene.GetObjectCount=0) then exit;

 CustomAssert(Assigned(fScene),'Scene NOT connected',self);
 CustomAssert(Assigned(fObjectIDImage),
   'Object Select image NOT created', self);

 SampleX := X;
 SampleY := Y;
 if Assigned(fLinker) and (fLinker.RenderTarget = RT_FRAME) then
 begin
   SampleX := (X * Integer(fLinker.FrameResolution)) +
     (Integer(fLinker.FrameResolution) div 2);
   SampleY := (Y * Integer(fLinker.FrameResolution)) +
     (Integer(fLinker.FrameResolution) div 2);
 end;

 DD := fObjectIDImage.StorageImageData[0];
 if not Assigned(DD) or
    not DD.GetPixelData(aFrameIndex, Shift, SampleX, SampleY, Pixel) then
   Exit;

 ObjectAddress := (UInt64(Pixel.R32G32_UINT.G) shl 32) or
   UInt64(Pixel.R32G32_UINT.R);
 if ObjectAddress = 0 then
   Exit;

 Candidate := TObject(Pointer(NativeUInt(ObjectAddress)));
 if IsValidObjectOfClass(Candidate, TvgObject) then
   Result := TvgObject(Candidate);
end;

procedure TvgRenderEngine.Notification(AComponent: TComponent;  Operation: TOperation);
begin
    inherited Notification(AComponent, Operation);

    Case Operation of
       opInsert : Begin
                    If aComponent=self then exit;
                    If NotificationTestON and Not (csDesigning in ComponentState) then exit;     //don't mess with links at runtime

                    If (aComponent is TvgScene) and (fScene=Nil) then
                    Begin
                      SetActiveState(False);
                      TvgBaseScene(aComponent).ConnectRenderEngine(Self);
                      fScene := TvgScene(aComponent);
                    End;
                  End;

       opRemove : Begin

                    If (aComponent is TvgScene) and (fScene=aComponent) then
                    Begin
                      SetActiveState(False);
                      TvgBaseScene(aComponent).DisConnectRenderEngine(Self);
                      fScene := nil;
                    End;
                  end;

    End;
end;

function TvgRenderEngine.SetDisabled: Boolean;
begin
  Result := Inherited;


end;

function TvgRenderEngine.SetEnabled: Boolean;
begin
  Result := Inherited;




end;

end.
