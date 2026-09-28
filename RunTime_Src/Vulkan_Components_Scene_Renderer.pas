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
  PasVulkan.Math.Double,
//  PasVulkan.Collections,
  PasVulkan.Framework,
  Vulkan_Assert,
  Vulkan_Components_Lookups,
  Vulkan_Components,
  Vulkan_Components_Descriptors,
  Vulkan_Components_DataStore,
  Vulkan_Components_Nodes,
  Vulkan_Components_Camera,
  Vulkan_Components_Light,
  Vulkan_WorldAxes,
  Vulkan_Components_PointerValidation,
  Vulkan_PixelInfo;

const
  // How far from TvgScene.WorldOrigin a vertex can be while float32 still
  // holds every value with three decimals exactly: the float32 step reaches
  // 1 mm at 16,384, and past it about a quarter of millimetre values come
  // back wrong.  TvgObject.SetVertexWorldPosition asserts it.
  VG_LOCAL_COORD_LIMIT = 16384.0;

type
  EvgSceneEditException = class(Exception);

  // What an edit layer holds - see TvgScene.GetEditStore.
  TvgEditLayerKind = (elkPoints, elkLines, elkTriangles);

  TvgScene = Class;
  TvgObjectStore = Class;
  TvgRenderEngine = Class;
  TvgToolManager = Class;

  TvgObject = Class(TvgObject_Base)
  private
    procedure SetCurrentVertex(const Value: Integer);

    // aWorld relative to the scene's WorldOrigin, asserting it is near
    // enough for float32 to keep millimetres (VG_LOCAL_COORD_LIMIT).
    function  LocalFromWorld(const aWorld: TpvVector3D): TpvVector3D;
    function  WorldFromLocal(const aLocal: TpvVector3): TpvVector3D;
    function  GetVertexCount: Integer;
    procedure NotifyEdited;
  protected
    fDataStore      : TvgObjectStore;
    fObjIndex       : Integer;           // Index in DataStore's object list
    
    fCurrentVertex  : Integer;     // Current local vertex index for adding
    fCurrentInstance: Integer;     // Current local instance index for adding


    Procedure SetDisabled; Override;
    Procedure SetEnabled; Override;

    // VisibleON False also stops the store drawing the object
    // (TvgVulkanDataStore.SetObjectHidden), so it is hidden everywhere: not
    // drawn, not picked, not in GetDataBounds.  Its data is kept.
    procedure SetVisibleON(const Value: Boolean); Override;

    procedure SetInstanceObjID(ID1, ID2: Cardinal);

  Public
    Constructor Create;
    // Leaves its scene's live-object list (see TvgScene.IsLiveObject).
    Destructor Destroy; Override;

    // Empties this object's vertex/instance/index ranges so it can be filled
    // again with AddVertex/AddInstance/AddIndex, without touching its store's
    // graphic pipeline - see TvgVulkanDataStore.ResetObject, which this
    // calls.  Works for any object in the store.  Also
    // resets CurrentVertex/CurrentInstance, so the object is exactly as it
    // was right after AddObject.
    procedure Reset;

    // Allocation methods
    procedure AllocateVertices(ACount: Integer;  AMode: TAllocationMode = amClear);
    procedure AllocateInstances(ACount: Integer; AMode: TAllocationMode = amClear);
    procedure AllocateIndices(ACount: Integer;   AMode: TAllocationMode = amClear);

    // Adding elements (auto-increments current index)
    function AddInstance : Integer;
    function AddVertex   : Integer;

    // Setters using current vertex/instance
    procedure SetVertexPosition(X, Y, Z: Single);

    // Real-world position: subtracts the scene's WorldOrigin in double, then
    // stores the offset as float32.  Asserts the offset is within
    // VG_LOCAL_COORD_LIMIT, beyond which three decimals no longer survive.
    procedure SetVertexWorldPosition(const aWorld: TpvVector3D);
    procedure SetVertexColor(R, G, B: Single; A: Single = 1.0);
    procedure SetVertexNormal(X, Y, Z: Single);
    procedure SetVertexTexCoord(U, V: Single);
    procedure SetVertexTangent(X, Y, Z: Single);
    procedure SetVertexBiTangent(X, Y, Z: Single);
    procedure SetVertexIndex(I: Cardinal);


    procedure SetInstanceColor(R, G, B: Single; A: Single = 1.0);
    procedure SetInstanceNormal(X, Y, Z: Single);
    procedure SetInstanceTangent(X, Y, Z: Single);
    procedure SetInstanceVector(X, Y, Z: Single);
    procedure SetInstanceMatrix(M: TvgMatrix4x4S);
    procedure SetInstanceIndex(I: Cardinal);

    Procedure AddObjectID;      //will add the Object ID ie pointer to object

    // Index methods
    function AddIndex(AIndex: Cardinal): Integer; overload;
    function AddIndex(I1, I2, I3: Cardinal): Integer; overload;
    function AddIndices(const AIndices: array of Cardinal): Integer;

    procedure SetIndex(AIndexPos: Integer; AValue: Cardinal);
    procedure SetTriangle(ATriangleIndex: Integer; I1, I2, I3: Cardinal);

    Function IncCurrentVertex  :Boolean;

    // --- Editing ------------------------------------------------------------
    //
    // World coordinates, in double, as the tool manager works in.  Each call
    // rebuilds the object's bounds and ends with TvgScene.NotifyDataChanged,
    // so it is drawn as edited.  Main thread.
    //
    // An object that is LockON or FrozenON refuses every edit: the Boolean
    // ones return False and change nothing.

    { Not locked, not frozen, and still in a store. }
    function  CanEdit: Boolean;

    function  GetVertexWorldPosition(aLocal: Integer): TpvVector3D;
    { Every vertex's world position, read in one call - for walking a whole
      object, where GetVertexWorldPosition per vertex locks per vertex. }
    function  GetVertexWorldPositions: TArray<TpvVector3D>;
    function  MoveVertex(aLocal: Integer; const aWorld: TpvVector3D): Boolean;

    { Moves every vertex by aDelta. }
    function  Translate(const aDelta: TpvVector3D): Boolean;

    { TvgVulkanDataStore.RemoveObjectVertex for this object: primitives that
      used the vertex go too.  Local vertex numbers above it move down. }
    function  DeleteVertex(aLocal: Integer): Boolean;

    { Splits the segment between local vertices aFrom and aTo with a new
      vertex at aWorld, so it becomes aFrom-new-aTo.  For line objects:

        LINE_LIST, indexed - one vertex added at the end; the segment's
                             index pair becomes two.
        LINE_LIST, plain   - the segment's two vertices become four (the
                             two in the middle both at aWorld).
        LINE_STRIP         - the vertex goes in between (indexed: its index
                             does).

      The new vertex copies aFrom's attributes - colour and the rest - and
      takes aWorld as its position.  Returns its local number (the first of
      the two for a plain list); -1, changing nothing, when the object cannot
      be edited, is not a line object, or has no segment aFrom-aTo (either
      way round).  Local numbers above it move up for the plain and strip
      cases. }
    function  SplitSegment(aFrom, aTo: Integer; const aWorld: TpvVector3D): Integer;

    { Mean of the vertex positions; the origin for an object with none. }
    function  Centroid: TpvVector3D;

    { Local index of the vertex nearest aWorld and its distance; -1 if the
      object has no vertices. }
    function  NearestVertex(const aWorld: TpvVector3D; out aDistance: Double): Integer;

    { TvgObjectStore.RemoveObject(Self): the object is freed. }
    procedure Delete;

    { The object's primitives as local vertex numbers, whatever the store's
      topology and indexing: aIndices holds Result numbers per primitive -
      1 for points, 2 for line segments, 3 for triangles.  Strips and fans
      come out as separate segments / triangles; the adjacency and patch
      topologies without a simple reading come out as points.  Primitives
      naming a vertex the object does not have (a strip's restart index,
      say) are left out.  Instancing is not applied. }
    function  GetPrimitives(out aIndices: TArray<Integer>): Integer;

    { Everything the object holds, byte for byte, and the reverse (see
      TvgVulkanDataStore.GetObjectData).  SetData keeps this object's own ID
      in its instances, so data taken from another object - one since
      deleted - can be put back into a new one.  It rebuilds the bounds and
      notifies the scene, and ignores LockON: it is for undo. }
    function  GetData: TvgObjectData;
    procedure SetData(const aData: TvgObjectData);

    { Draws the object in aColor in place of its own colour, leaving its data
      as it is (TvgVulkanDataStore.SetObjectColorOverride) - for a layer
      colour, a highlight.  Needs the store's ColorOverrideON (the default)
      and a shader that reads the override.  Alpha 0 clears it, as does
      ClearColorOverride.  Not an edit: works on a locked or frozen object.
      Notifies once per change.  Nothing happens for an object not in a
      store. }
    procedure SetColorOverride(const aColor: TpvVector4);
    procedure ClearColorOverride;
    { False, aColor untouched, for none. }
    function  GetColorOverride(out aColor: TpvVector4): Boolean;

    Property VertexCount : Integer read GetVertexCount;

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
    fDefaultColor  : TpvVector4;

    fInDataBounds  : Boolean;
    fDepthTest     : Boolean;
    fColorOverrideON : Boolean;

    // Builds one object from world points for AddPoint/AddLine/AddPolyline.
    function  AddShape(const aPoints: array of TpvVector3D; aClosed: Boolean;
                       const aColor: TpvVector4): TvgObject;
    // Fills an empty aObject with the shape: vertices, indices, colour and
    // object ID as the store's layout has them.
    procedure FillShape(aObject: TvgObject; const aPoints: array of TpvVector3D;
                        aClosed: Boolean; const aColor: TpvVector4);
    procedure CheckPolyline(const aPoints: array of TpvVector3D; aClosed: Boolean);

    Procedure SetEnabled; Override;
    Procedure SetDisabled; Override;

    Procedure ObjectsListOfPipes_Update;
    Procedure ObjectsListOfPipes_Clear;

    Procedure  ConfigureGraphicPipeline(GP:TvgGraphicPipeline); Override;

    // Size used for gl_PointSize when Topology is POINT_LIST.  Emitted as a
    // literal into the generated vertex shader.
    function GetShaderPointSizeExpression: String; Override;

    function GetEditable: Boolean;  Override;
    function GetFrozen: Boolean;  Override;
    function GetLocked: Boolean;    Override;
    function GetSelectable: Boolean; Override;
    function GetVisible: Boolean;  Override;

    // Every renderer of the scene records its frames again.
    procedure GPUBuffersReplaced; Override;

    { Appends a TvgPushConstant_ObjectColor to aPipe's push constants, once,
      with its GLSL offset set.  UpdateGraphicPipeline calls it when
      ColorOverrideON. }
    class procedure AddColorOverridePushConstant(aPipe: TvgGraphicPipeline); static;

  public
    constructor Create(AOwner: TComponent);  Override;
    destructor Destroy; override;

    // Last word on a pipeline, after the render pass has set its depth test
    // (see DepthTest).
    Procedure UpdateGraphicPipeline(aPipe: TvgGraphicPipeline); Override;

    Procedure ClearData;
    Procedure ClearGraphicPipes;     Override;

    // Object creation
    Function AddObject(aWithInstances:Boolean): TvgObject;   // aWithInstances: the object gets instance data (AddDataObject)

    // --- Shapes from world points --------------------------------------------
    //
    // Each builds one TvgObject through SetVertexWorldPosition, colours it
    // (if the store has vdtColor), gives it an object ID so it can be picked
    // (if the store has idtObjID), and ends with TvgScene.NotifyDataChanged.
    // Main thread.  The store's Topology must suit the shape, or
    // EvgSceneEditException is raised: POINT_LIST for AddPoint, LINE_LIST or
    // LINE_STRIP for the others.  A LINE_LIST store with an index type shares
    // each inner vertex between its two segments; without one, it repeats it.
    // Without a colour, DefaultColor is used.

    Function AddPoint(const aWorld: TpvVector3D): TvgObject; overload;
    Function AddPoint(const aWorld: TpvVector3D; const aColor: TpvVector4): TvgObject; overload;
    Function AddLine(const aFrom, aTo: TpvVector3D): TvgObject; overload;
    Function AddLine(const aFrom, aTo: TpvVector3D; const aColor: TpvVector4): TvgObject; overload;

    { At least two points; aClosed joins the last back to the first, and
      needs at least three. }
    Function AddPolyline(const aPoints: array of TpvVector3D; aClosed: Boolean): TvgObject; overload;
    Function AddPolyline(const aPoints: array of TpvVector3D; aClosed: Boolean;
                         const aColor: TpvVector4): TvgObject; overload;

    { Replaces aObject's shape with a new polyline, in place: same object,
      same index, same ID.  For geometry rewritten on every mouse move - a
      rubber band - where AddPolyline would leave a tombstone per move.
      aObject must belong to this store. }
    Procedure RefillPolyline(aObject: TvgObject; const aPoints: array of TpvVector3D;
                             aClosed: Boolean); overload;
    Procedure RefillPolyline(aObject: TvgObject; const aPoints: array of TpvVector3D;
                             aClosed: Boolean; const aColor: TpvVector4); overload;

    { Replaces aObject's shape with separate segments, in place, as
      RefillPolyline does: aSegments holds them as pairs of points, 0-1, 2-3
      ...  For overlays made of many unconnected lines - a selection
      highlight, vertex handles.  Needs an indexed LINE_LIST store and an even
      number of points (none empties the object). }
    Procedure RefillSegments(aObject: TvgObject; const aSegments: array of TpvVector3D); overload;
    Procedure RefillSegments(aObject: TvgObject; const aSegments: array of TpvVector3D;
                             const aColor: TpvVector4); overload;

    { Deletes aObject: its geometry stops drawing (TvgVulkanDataStore.
      DeleteDataObject), the scene forgets it - so a click on the last frame
      drawn with it cannot pick it - and the tool manager lets go of it if it
      held it.  Then frees it: aObject is invalid on return.  Every other
      object in the store keeps its ObjIndex.  Main thread. }
    Procedure RemoveObject(aObject: TvgObject);
    function GetObjectCount: Integer; Override;
    // The Index'th object this store holds, 0 .. GetObjectCount - 1.
    function GetObjectItem(Index: Integer): TvgObject;

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

    // Point sprite size used when Topology is POINT_LIST.  Read by
    // GetShaderPointSizeExpression when the vertex shader is generated, so it
    // must be set before the graphic pipeline is built.
    Property PointSize : Single read fPointSize write fPointSize;

    // Rasterizer line width for LINE_LIST/LINE_STRIP topologies.  Read by
    // ConfigureGraphicPipeline, so it must be set before the graphic pipeline
    // is built.  A value other than 1.0 needs the device's wideLines feature.
    Property LineWidth : Single read fLineWidth write fLineWidth;

    // RGBA the shape builders use when no colour is given.  White.
    Property DefaultColor : TpvVector4 read fDefaultColor write fDefaultColor;

    // False keeps this store out of TvgScene.GetDataBounds, and so out of
    // ZoomAll - for a store of helpers rather than data, like the preview.
    Property InDataBounds : Boolean read fInDataBounds write fInDataBounds;

    // False draws the store over whatever is already drawn: no depth test,
    // no depth write.  Default True.  Read when the pipeline is built, so set
    // it before the store is connected.
    Property DepthTest : Boolean read fDepthTest write fDepthTest;

    // True (the default) gives every pipeline of the store a
    // TvgPushConstant_ObjectColor, so an object's colour override
    // (TvgObject.SetColorOverride) reaches a shader that declares it.  Read
    // when the pipeline is built, so set it before the store is connected.
    Property ColorOverrideON : Boolean read fColorOverrideON write fColorOverrideON;

    Property Scene: TvgScene read fScene ;
    Property Active: Boolean read GetActive write SetActiveState;
  End;



  TvgSceneMouseOverObject = procedure(Sender: TvgBaseScene; const aObject: TvgObject) of object;

  // aDataStore is the store that changed, or nil for a change to the scene
  // as a whole.
  TvgSceneDataChanged = procedure(Sender: TvgScene; aDataStore: TvgObjectStore) of object;

  { TvgScene: WorldOrigin

    Vertex data is float32 and cannot hold survey coordinates: at six digits
    before the decimal float32 steps are 62.5 mm.  A scene therefore keeps its
    vertices RELATIVE to WorldOrigin, a double-precision point near the middle
    of the data, and the renderer adds the origin back on the CPU, in double,
    as part of the view-projection matrix.  Offsets within
    VG_LOCAL_COORD_LIMIT keep millimetres exact.

    Three coordinate spaces follow from that:
      world  - real coordinates, double: the camera, ToolManager positions
      local  - world minus WorldOrigin: vertex data, bounds, the cull volume
      clip   - what the view-projection produces

    With the default origin (0,0,0) local and world are the same, which is
    how scenes behaved before WorldOrigin existed.

    Set WorldOrigin BEFORE adding data.  Changing it would move every vertex
    already stored, so it is refused while the scene holds any object store. }

  TvgScene = Class(TvgBaseScene)
  private
    procedure SetOnMouseOver(const Value: TvgSceneMouseOverObject);
    procedure SetWorldOrigin(const Value: TpvVector3D);
    function  GetWorldOriginX: Double;
    function  GetWorldOriginY: Double;
    function  GetWorldOriginZ: Double;
    procedure SetWorldOriginX(const Value: Double);
    procedure SetWorldOriginY(const Value: Double);
    procedure SetWorldOriginZ(const Value: Double);

//Scene holds and owns RenderNodes in a list
 //RenderNodes are added to the renderers for use
 //disable the Scene will Free all RenderNodes Scene NOT disabled by Instance disabling
 //Nodes are added by the TvgSceneLoaderStorer during the
 //Scene will provide a NodeID which can be used in ObjectPicking

   Protected

    fSceneData   : TObjectList<TvgObjectStore>;
    fCameras     : TvgCameraManager;
    fWorldOrigin : TpvVector3D;
    fLights      : TList<TvgLight>;

    fOnMouseOver : TvgSceneMouseOverObject;
    fOnDataChanged : TvgSceneDataChanged;

    // BeginUpdate / EndUpdate: nesting depth, and what NotifyDataChanged was
    // asked for meanwhile (fUpdateStore nil once two stores have changed).
    fUpdateDepth   : Integer;
    fUpdatePending : Boolean;
    fUpdateStore   : TvgObjectStore;

    // Every TvgObject in a store of this scene, by address.  An object ID
    // read back from the picking target is a raw address, and the object it
    // named may have been deleted since that frame was drawn - see
    // IsLiveObject.
    fLiveObjects : TDictionary<Pointer, TvgObject>;

    fEditStores       : array[TvgEditLayerKind] of TvgObjectStore;
    fEditColor        : TpvVector4;
    fEditLineWidth    : Single;
    fEditPointSize    : Single;
    fEditShaderPrefix : String;
    fDeferLiveActivation : Boolean;

    fPreviewStore     : TvgObjectStore;
    fPreviewObj       : TvgObject;
    fEditPreviewColor : TpvVector4;

    // Tool managers whose Scene is this one (see GetToolManagers).
    fToolManagers     : TList<TvgToolManager>;
    Procedure AttachToolManager(aManager: TvgToolManager);
    Procedure DetachToolManager(aManager: TvgToolManager);

    // Forgets an edit layer that is being freed, so GetEditStore makes a
    // new one rather than hand back a dangling pointer.
    Procedure ForgetEditStore(aDataStore: TvgObjectStore);

    // Makes the preview store and its one object if missing.  False when it
    // cannot be made now (scene state) or the scene is being destroyed.
    Function EnsurePreview: Boolean;

    Procedure RegisterObject(aObject: TvgObject);
    Procedure UnregisterObject(aObject: TvgObject);
    Procedure RegisterStoreObjects(aDataStore: TvgObjectStore);
    Procedure UnregisterStoreObjects(aDataStore: TvgObjectStore);

    // Adds aDataStore to fSceneData and links it to the scene, whatever the
    // scene state.  AddDataStore and AddDataStoreLive decide when to call it.
    Procedure DoAddDataStore(aDataStore: TvgObjectStore);

    // Unlinks aDataStore from the scene and takes it out of fSceneData
    // WITHOUT freeing it.  RemoveDataStore frees it afterwards; a store being
    // freed some other way (its owner, or directly) calls this from its
    // destructor so the scene is not left holding a dangling pointer.
    // False when the store is not in this scene.
    Function DetachDataStore(aDataStore: TvgObjectStore): Boolean;

    Function SetDisabled :Boolean; Override;
    Function SetEnabled  :Boolean; Override;

    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

    Procedure ClearGraphicPipelines(aRenderer:TvgBaseRenderEngine; aSubPass:TvgSubpass);Override;
    function GetObjectStore(Index: Integer): TvgBaseObjectStore; Override;

   Procedure ConnectRenderEngine(aRenderEngine : TvgBaseRenderEngine);    Override;
   //called attaching a RenderEngine to Scene
   Procedure DisConnectRenderEngine(aRenderEngine:TvgBaseRenderEngine);   Override;
   //called attaching a RenderEngine to Scene
   Procedure ReConnectRenderEngines;          Override;

   Function GetToolManager:TvgToolManager  ;

 Public
   { Every tool manager working on this scene: the linker's, and each one
     whose Scene is this one.  They are told when objects go (ForgetObject)
     and when the scene is cleared. }
   Function GetToolManagers: TArray<TvgToolManager>;


   constructor Create(AOwner: TComponent); Override;
   destructor Destroy; override;

   Function AddDataStore(aDataStore: TvgObjectStore):Boolean;

   // --- Editing a loaded scene ---------------------------------------------
   //
   // Load_Begin clears the whole scene, so a scene being edited adds and
   // removes stores with these instead.  Main thread.

   { Adds a store to a scene that is already loaded and makes it drawable
     straight away: it is activated if the scene is active, and its graphic
     pipelines are built on every active renderer (ConnectStoreLive).
     Between Load_Begin and Load_End it is the same as AddDataStore.  False
     if aDataStore is nil or the scene is neither loaded nor loading. }
   Function AddDataStoreLive(aDataStore: TvgObjectStore): Boolean;

   { Builds aDataStore's graphic pipelines on every active renderer and
     activates them - what Load_End does for every store, scoped to one.  A
     store that already has a pipeline for a renderer/subpass keeps it, so
     this is safe to repeat.  It does not change aDataStore.Active. }
   Procedure ConnectStoreLive(aDataStore: TvgObjectStore);

   { While True, AddDataStoreLive and ConnectStoreLive build a store's
     pipelines but leave them inactive, so they draw nothing and have not
     loaded their shaders yet.  For stores whose SPIR-V is generated from
     their own pipelines (TvgShaderBuilder): a pipeline activated with a
     missing or empty shader file fails in Vulkan.  Set it, add the stores
     (GetEditStore, ShowPreview...), clear it, write the shaders, then
     ConnectStoreLive each store to activate it.  Default False. }
   Property DeferLiveActivation : Boolean read fDeferLiveActivation write fDeferLiveActivation;

   { Takes a store out of the scene and frees it, waiting first for any
     frame that is drawing it.  The tool manager lets go of its objects. }
   Procedure RemoveDataStore(aDataStore: TvgObjectStore);

   { To call after changing a store's data: every renderer re-records its
     frames and repaints, and OnDataChanged fires.  The TvgObject and
     TvgVulkanDataStore edit calls already mark the data for upload; this is
     what gets it drawn.  aDataStore may be nil for a change to the scene as
     a whole. }
   Procedure NotifyDataChanged(aDataStore: TvgObjectStore = nil);

   { Brackets a group of edits that should reach the screen as one.  Each
     repaint renders a whole frame at once, so without this an edit made in
     steps is drawn after every step: a Move restores an object's start data
     and then moves it, and a frame of each showed as jitter.  Inside, a
     NotifyDataChanged still flags the frames, but the repaint and
     OnDataChanged wait for the outermost EndUpdate, which does them once.
     Nests.  TvgToolManager brackets every input event with it. }
   Procedure BeginUpdate;
   Procedure EndUpdate;

   { True if aObject is a TvgObject in one of this scene's stores right now.
     Takes any pointer, including one read back from the picking target
     whose object has since been deleted - it is never dereferenced. }
   Function IsLiveObject(aObject: Pointer): Boolean;

   { The scene's store for new geometry of one kind, made on first use and
     added with AddDataStoreLive, so while the scene is loaded or loading.
     nil in any other state.  Freed like any store by ClearScene (and so by
     Load_Begin) or RemoveDataStore; the next call makes a new one.

       elkPoints    - POINT_LIST
       elkLines     - LINE_LIST, indexed (a polyline shares its vertices)
       elkTriangles - TRIANGLE_LIST, indexed

     Each has vdtPosition and vdtColor per vertex and idtObjID per object,
     so what is drawn into it can be picked.  Its shaders are named
     EditShaderPrefix + 'Points' / 'Lines' / 'Triangles' - EditLines_vert.spv
     and EditLines_frag.spv by default - built from its layout like any
     store's (TvgShaderBuilder).  EditColor, EditLineWidth and EditPointSize
     are applied when it is made. }
   Function GetEditStore(aKind: TvgEditLayerKind): TvgObjectStore;

   // --- Preview ------------------------------------------------------------
   //
   // What a tool shows while it works - the rubber band of a line being
   // drawn, say - in a store of its own: LINE_LIST, not pickable, not in
   // GetDataBounds, shaders EditShaderPrefix + 'Preview' (EditPreview_vert.spv
   // by default), colour EditPreviewColor.  Made on first use, and freed like
   // any store by ClearScene or RemoveDataStore.  One preview at a time.
   // Drawn with no depth test (DepthTest False), so it shows over the data
   // it outlines - though a store drawn after it can still cover it.

   { Shows aPoints as a polyline (closed if aClosed), replacing whatever the
     preview showed.  Fewer than two points clears it. }
   Procedure ShowPreview(const aPoints: array of TpvVector3D; aClosed: Boolean);

   // The same, as separate segments: pairs of points (see TvgObjectStore.
   // RefillSegments).  None clears it.
   Procedure ShowPreviewSegments(const aSegments: array of TpvVector3D);
   Procedure ClearPreview;

   Procedure PrepareFrameGlobalData(aTarget  : IvgGlobalDataTarget; aFrameIndex : TvkUint32); Override;

   Function GetObjectCount : Integer; Override;
   Function GetObjectStoreCount   : Integer; Override;

   Procedure ClearScene; Override;

 //virtual abstract from BaseScene
   Procedure ConnectDataToRenderer(aRenderEngine : TvgBaseRenderEngine);Override;
   //Called when connecting a RenderEngine
   Procedure DisConnectDataFromRenderer(aRenderEngine : TvgBaseRenderEngine);Override;
   //Called when Disconnecting a RenderEngine
   Procedure ConnectDataToVulkanDevice(aScreenDevice:TvgScreenRenderDevice); Override;
   Procedure BuildGraphicPipelinesForRenderer(aRenderer: TvgBaseRenderEngine);  Override;


   // World <-> local, in double.  Narrow to float32 only when writing vertex
   // data, ideally through TvgObject.SetVertexWorldPosition.
   Function WorldToLocal(const aWorld: TpvVector3D): TpvVector3D;
   Function LocalToWorld(const aLocal: TpvVector3D): TpvVector3D;

   { World-space bounds of every object in the scene, in double.

     Unions TvgVulkanDataStore.GetObjectWorldBounds over every object of every
     store - which rebuilds any stale box on the way - and then converts the
     two corners with LocalToWorld.  The union is taken in LOCAL space, where
     the float32 boxes already live: adding WorldOrigin to a float32 corner
     would round a survey coordinate to the nearest 62.5 mm, which is the very
     thing WorldOrigin exists to avoid.

     Objects with no usable bounds contribute nothing - an empty box, and
     cmNever, whose bounds the application has said not to trust.  Geometry a
     compute shader owns can still be included by giving it bounds through
     TvgVulkanDataStore.SetObjectBounds (cmManual).

     aVisibleOnly skips stores that are not Visible, so hiding a layer also
     takes it out of the zoom.

     Returns False when no object has usable bounds: an empty scene, or one
     built entirely from cmNever geometry.  aMin/aMax mean nothing then -
     callers must not zoom to a box they did not get. }
   Function GetDataBounds(out aMin, aMax: TpvVector3D; aVisibleOnly: Boolean = True): Boolean; Overload;

   { The same union left in LOCAL space and float32, for callers already
     working there - culling, or anything comparing against a store's own
     bounds.  aBox comes back invalid (Valid False) when there is nothing. }
   Function GetDataBounds(out aBox: TvgAABB; aVisibleOnly: Boolean = True): Boolean; Overload;

   Property SceneData : TObjectList<TvgObjectStore> Read fSceneData  ;
   Property Cameras   : TvgCameraManager read fCameras;

   // Punctual lights (KHR_lights_punctual) a loader found in the scene, in
   // world space.  Data only - nothing here uploads them to the GPU or
   // shades anything with them yet.  Cleared by ClearScene, same as SceneData.
   Property Lights    : TList<TvgLight> Read fLights;

   // See the note above TvgScene.  Refused while the scene holds data.
   Property WorldOrigin : TpvVector3D read fWorldOrigin write SetWorldOrigin;

   Property OnMouseOver  : TvgSceneMouseOverObject read fOnMouseOver write SetOnMouseOver;

   // Fires from NotifyDataChanged.
   Property OnDataChanged : TvgSceneDataChanged read fOnDataChanged write fOnDataChanged;

   // Settings an edit layer takes when GetEditStore makes it.  Changing them
   // later does not touch a layer that already exists.
   Property EditColor        : TpvVector4 read fEditColor write fEditColor;
   Property EditLineWidth    : Single read fEditLineWidth write fEditLineWidth;
   Property EditPointSize    : Single read fEditPointSize write fEditPointSize;
   Property EditShaderPrefix : String read fEditShaderPrefix write fEditShaderPrefix;
   Property EditPreviewColor : TpvVector4 read fEditPreviewColor write fEditPreviewColor;

   // nil until the first ShowPreview.
   Property PreviewStore     : TvgObjectStore read fPreviewStore;

  Published
   // WorldOrigin by component, so it can be set in the Object Inspector and
   // stored in a DFM.
   Property WorldOriginX : Double read GetWorldOriginX write SetWorldOriginX;
   Property WorldOriginY : Double read GetWorldOriginY write SetWorldOriginY;
   Property WorldOriginZ : Double read GetWorldOriginZ write SetWorldOriginZ;

  End;


TvgSceneLoaderStorer = Class(TvgBaseComponent)
 //descendants handles read/write of scene data and conversion to TvgSceneData which are then added to the Scene

  private
    procedure SetScene(const Value: TvgScene);
 //Descendant will load /Store data To/From the Scene using the local format
   protected
     fScene             : TvgScene;
     fCurrentObjectStore: TvgObjectStore;

     // Adds a new texture descriptor named aDescriptorName to
     // fCurrentObjectStore and returns it, ready for AddSharedTexture; nil if
     // there is no current store or the descriptor could not be created.
     // Shared by both AddDescriptor_Texture overloads.
     Function PrepareTextureDescriptor(aDescriptorName: String): TvgDescriptorArray_Texture;

   public

     Procedure LoadScene;Virtual;Abstract;
     //load scene into TvgScene
     Procedure StoreScene;Virtual;Abstract;

     Function AddObjectStore:TvgObjectStore;


     Procedure AddDescriptor_Texture( aDescriptorName : String;
                                     aImageFileName  : String); Overload;

     // aImageStream is read (not owned/freed) - the caller frees it once this
     // returns.  For glTF images that are embedded (a data: URI, or a GLB
     // bufferView) rather than a file on disk - see TPasGLTF.TImage.GetResourceData.
     Procedure AddDescriptor_Texture( aDescriptorName : String;
                                     aImageStream    : TStream); Overload;

     Property CurrentObjectStore : TvgObjectStore Read fCurrentObjectStore;


   published
     Property Scene : TvgScene Read fScene write SetScene;

 End;

 TvgRenderEngine= Class(TvgBaseRenderEngine)
 Private
    procedure SetScene(const Value: TvgScene);



 Protected

   fScene                  : TvgScene;

   fObjectIDImage          : TvgDescriptorArray_StorageImage;
   fObjectIDBuffer         : TvgDescriptorArray_SB_2UI;
   fLightsBuffer           : TvgDescriptorArray_SB_Light;

    Function SetDisabled :Boolean; Override;
    Function SetEnabled  :Boolean; Override;

    procedure Notification(AComponent: TComponent; Operation: TOperation); override;


    Procedure VaildateGlobalResources;     Override;
    Procedure ConfigureGraphicPipelineFromRenderPass(GP:TvgGraphicPipeline);  Override;

    { Makes the global view-projection descriptor a dmat4 or a mat4 to match
      UsesDoubleViewProjection, creating it if missing.  An existing item is
      re-typed in place, so the descriptor keeps its binding. }
    Procedure ValidateViewProjectionDescriptor;

    { Creates the global lights storage buffer if missing (unconditionally -
      unlike the ObjectID buffer/image, this does not depend on SelectMode),
      and points fLightsBuffer at it either way. }
    Procedure ValidateLightsDescriptor;

    procedure SetViewProjectMatrix(aFrameIndex : TvkUint32; const aMat  : TpvMatrix4x4D); Override;
    procedure SetLightData(aFrameIndex : TvkUint32; const aLights : TArray<TvgLightGPUData>); Override;



 Public

    Function GetObjectAtLocation(aFrameIndex : TvkUint32; Shift: TShiftState; X, Y: Integer):TvgObject;  Virtual;

    function GetHUDCamera: TvgCamera; Override;

    { ShaderUseDouble, unless the device is known and cannot do it: a dmat4
      needs shaderFloat64 supported by the GPU and enabled on the logical
      device.  Before the device exists this cannot be known and follows
      ShaderUseDouble; SetEnabled checks again once it can.

      Falling back to a mat4 is safe for a TvgScene: the matrix it publishes
      is relative to WorldOrigin, which float32 carries to about 1 mm. }
    Function UsesDoubleViewProjection : Boolean; Override;


 Published

//   Property MVPMatrixON   : Boolean read FFlags.MVPMatrixON write SetMVPMatrixON;
//   Property ObjSelectON   : Boolean read FFlags.SelectON write SetSelectON;

   Property Scene :TvgScene Read fScene write SetScene;
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
  //
  // Positions in both events are real-world coordinates, in double.  Vertex
  // data is relative to TvgScene.WorldOrigin: write it back with
  // TvgObject.SetVertexWorldPosition, or subtract the origin with
  // TvgScene.WorldToLocal first.
  TvgObjectMovedEvent      = procedure(Sender: TObject;
                                        aObject: TvgObject;
                                        const aNewWorldPos: TpvVector3D) of object;

  // Fired when the user clicks in TAM_OBJECT_ADD mode without dragging.
  // aWorldPos is the world-space ray-plane intersection point.
  TvgObjectAddRequestEvent = procedure(Sender: TObject;
                                        const aWorldPos: TpvVector3D) of object;

  // Fired before a tool deletes aObject; clear aAllow to keep it.
  TvgObjectDeletingEvent   = procedure(Sender: TObject; aObject: TvgObject;
                                        var aAllow: Boolean) of object;

  // Scene-local positions to client pixels, for one camera and viewport.
  TvgScreenProjector = record
    VP      : TpvMatrix4x4D;   // for positions relative to WorldOrigin
    W, H    : Double;
    Fwd     : TpvVector3D;     // the camera's view direction
    DepthC  : Double;          // distance along it from the eye to WorldOrigin
    // False behind a perspective camera.  aDepth: distance from the eye
    // along the view direction.
    function Project(const aLocal: TpvVector3D; out aX, aY, aDepth: Double): Boolean;
  end;

  // What TvgToolManager.PickAt found under the cursor.
  TvgPickHit = record
    Obj      : TvgObject;
    Pixels   : Double;        // from the cursor to the object, on screen
    Vertex   : Integer;       // the object's vertex nearest the cursor (local)
    World    : TpvVector3D;   // the point of the object under the cursor
  end;

  TvgMouseState = Record
    ButtonON      : Boolean;  //True if a button is currently down
    ButtonDown    : TvgMouseButton;   //Which button is down valid ONLy if fButtonON
    CaptureMouse  : Boolean;  //if true then capture ALL Mouse Moves
    MouseCaptured : Boolean;

  end;

  { One object's vertices on screen, as TvgToolManager's picking and snapping
    use them, kept from one mouse move to the next.  Good while the view (VP,
    W, H) and the store's data (ChangeStamp) are what they were: hovering over
    a big surface then costs a pass over these arrays, not a projection - and
    a read of the store - of every vertex on every move. }
  TvgObjectProjection = class
    Store    : TvgObjectStore;
    ObjIndex : Integer;
    Stamp    : Cardinal;
    VP       : TpvMatrix4x4D;
    W, H     : Double;
    Local    : TArray<TpvVector3>;   // positions relative to WorldOrigin
    SX, SY   : TArray<Double>;       // on screen
    SD       : TArray<Double>;       // depth
    OK       : TArray<Boolean>;      // False behind the camera
    HasPrims : Boolean;              // Prims / PrimSize read yet
    PrimSize : Integer;              // TvgObject.GetPrimitives
    Prims    : TArray<Integer>;
  end;

  // -----------------------------------------------------------------------
  //  TvgToolManager
  //
  //  Scene tool manager: camera control, picking and selection.  Inherits
  //  raw mouse plumbing from TvgBaseToolManager.
  //
  //  Interactive editing - edit tools, undo/redo, snapping - is added by a
  //  descendant (TvgEditToolManager in the PRO package) through the virtual
  //  hooks below.  The scene talks to every tool manager through them:
  //  ForgetObject before an object is freed, StoreGone before a store is,
  //  SceneCleared when the scene's data goes.
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

    fMouseState    : TvgMouseState;

    // Object editing state
    fSelectedObject   : TvgObject;
    fDragPlaneAxis    : Integer;       // 0=horizontal, 1=front, 2=side (TvgWorldPlane order)
    fDragStartHitPt   : TpvVector3D;   // World-space ray-plane hit at pick time
    fDragPlaneValid   : Boolean;       // True when fDragStartHitPt is usable

    // Events
    fOnObjectPicked   : TvgObjectPickedEvent;
    fOnObjectMoved    : TvgObjectMovedEvent;
    fOnObjectAddReq   : TvgObjectAddRequestEvent;
    fOnSelectionChanged : TNotifyEvent;
    fPickRadius         : Integer;

    // Every selected object; SelectedObject is the last one selected.
    fSelection          : TList<TvgObject>;

    fProjections        : TObjectDictionary<TvgObject, TvgObjectProjection>;
    fProjectedVertices  : Int64;     // in fProjections, to bound its memory

    // BeginInput / EndInput: nesting, and the scene whose BeginUpdate the
    // outermost one called.
    fInputDepth         : Integer;
    fInputScene         : TvgScene;

    // Every input event's scene edits reach the screen as one repaint
    // (TvgScene.BeginUpdate).  A descendant also brackets edits made from
    // code with them - Undo, Redo, DeleteSelection.
    procedure BeginInput; Override;
    procedure EndInput;   Override;
    // Ends an input bracket's scene update early - the scene is changing.
    procedure ReleaseInputScene;

    // Fires OnSelectionChanged.  A descendant tells its active tool first.
    procedure DoSelectionChanged; virtual;

    // Picking: whether aObject takes part, and its vertices on screen.
    function  CanPick(aStore: TvgObjectStore; aObject: TvgObject): Boolean;
    function  ObjectScreenRect(const aP: TvgScreenProjector; aObject: TvgObject;
                               out aX1, aY1, aX2, aY2: Double): Boolean;
    { aObject's vertices on screen for the view aP: from the cache when
      neither the view nor the object's store has changed since, projected
      afresh otherwise.  Owned by the cache - do not free, and do not keep
      across calls that may edit the scene. }
    function  ProjectObject(const aP: TvgScreenProjector; aObject: TvgObject): TvgObjectProjection;
    // Its primitives (TvgObject.GetPrimitives), read once per projection.
    function  ProjectionPrims(aProj: TvgObjectProjection; aObject: TvgObject): Integer;
    procedure ClearProjections;
    function  MakeProjector(out aP: TvgScreenProjector): Boolean;

    function  GetSelectionCount: Integer;
    function  GetSelection(Index: Integer): TvgObject;

    procedure Notification(AComponent: TComponent;  Operation: TOperation); override;

    Function SetDisabled :Boolean; Override;
    Function SetEnabled  :Boolean; Override;

    // --- Camera operations ---
    procedure DoCameraOrbit(aDeltaX, aDeltaY: Single);
    procedure DoCameraPan(aDeltaX, aDeltaY: Single);
    procedure DoCameraDolly(aDelta: Single);
    procedure DoCameraZoom(aWheelDelta: Integer);

    // --- Object operations ---
    procedure DoPickObject(aFrameIndex: TvkUint32; Shift: TShiftState; X, Y: Integer);

    procedure DoDragObject(X, Y: Integer);
    procedure DoAddObjectRequest(X, Y: Integer);

    // --- Helpers ---
    function GetActiveCamera: TvgCamera;
    function GetCurrentFrameIndex: TvkUint32;
    function GetDragPlaneNormal: TpvVector3D;
    // Where a new drag plane passes through: the scene's WorldOrigin.
    function GetDragPlaneAnchor: TpvVector3D;
    function ScreenRayHitsPlane(aX, aY: Integer;
                                 const aPlaneNormal: TpvVector3D;
                                 const aPlanePoint:  TpvVector3D;
                                 out   aHitPoint:    TpvVector3D): Boolean;

    // Decides the active camera gesture from button/shift state
    procedure DispatchCameraGesture(Shift: TShiftState; aDeltaX, aDeltaY: Single);

    // --- Hooks for a descendant that adds interactive tools ---------------

    { Offered each event before the manager's own handling; True if it was
      used, which ends it there.  The base uses none.  Mouse moves arrive
      with or without a button held. }
    function  ToolMouseDown(aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer): Boolean; virtual;
    function  ToolMouseMove(Shift: TShiftState; X, Y: Integer): Boolean; virtual;
    function  ToolMouseUp  (aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer): Boolean; virtual;
    // The wheel, before the camera zooms with it.
    function  ToolMouseWheel(Shift: TShiftState; WheelDelta: Integer): Boolean; virtual;

    { A drag of aDeltaX, aDeltaY (sensitivity applied) that ToolMouseMove
      left: the camera or an object move, by ToolMode and ActionMode. }
    procedure DoCameraDrag(Shift: TShiftState; aDeltaX, aDeltaY: Single; X, Y: Integer); virtual;

    // --- Override base virtual mouse handlers ---
    procedure DoMouseDown (aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    procedure DoMouseMove (Shift: TShiftState; X, Y: Integer);                          Override;
    procedure DoMouseUp   (aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer); Override;
    procedure DoMouseWheel(Shift: TShiftState; WheelDelta: Integer);                    Override;

  public
    constructor Create(AOwner: TComponent); Override;
    destructor  Destroy; override;

    // Clears the selection and resets drag state
    procedure ClearSelection;

    // --- Selection --------------------------------------------------------
    //
    // A list of objects, which the editing tools act on and highlight.
    // SelectedObject is the last one selected.  A deleted object leaves it by
    // itself.  Each change fires OnSelectionChanged.  Only live, Selectable
    // objects can be selected.

    { Makes aObject the selection, or adds it with aAdd.  False if it
      cannot be selected. }
    function  SelectObject(aObject: TvgObject; aAdd: Boolean = False): Boolean;
    procedure DeselectObject(aObject: TvgObject);
    procedure ToggleSelected(aObject: TvgObject);
    function  IsSelected(aObject: TvgObject): Boolean;
    { Replaces the selection with aObjects, or adds them. }
    procedure SelectObjects(const aObjects: array of TvgObject; aAdd: Boolean = False);

    // --- Picking on the CPU -----------------------------------------------
    //
    // From the vertex data in the stores, not the GPU's object-ID image, so
    // it needs no device and no frame drawn, reaches lines and points within
    // PickRadius pixels rather than only the exact pixels they cover, and
    // sees an edit at once.  The cost is a pass over the vertices of each
    // object whose bounds are near the cursor.  Instancing is not applied:
    // an instanced object is found where its vertices are, not its instances.

    { The object nearest the cursor within PickRadius pixels, in any store
      the scene shows (a store made inactive while the scene is active is
      hidden) other than the preview: points and lines by their distance on
      screen, a triangle when the cursor is inside it, so a line drawn on a
      surface wins over the surface.  Among equals the nearer one to the eye.
      Only Visible and Selectable objects. }
    function  PickAt(X, Y: Integer; out aHit: TvgPickHit): Boolean;
    function  PickObject(X, Y: Integer): TvgObject;

    { Every live, Visible, Selectable object with a vertex or an edge in the
      screen rectangle - for a box selection. }
    function  ObjectsInRect(X1, Y1, X2, Y2: Integer): TArray<TvgObject>;

    { aObject's vertex nearest the cursor on screen, and its distance in
      pixels; -1 if none is on screen. }
    function  NearestVertexOnScreen(aObject: TvgObject; X, Y: Integer; out aPixels: Double): Integer;

    { Where aWorld is on screen, in client pixels.  False if there is no
      camera or viewport, or it is behind a perspective camera. }
    function  WorldToScreen(const aWorld: TpvVector3D; out aX, aY: Double): Boolean;

    { The world size of one pixel at aWorld, for drawing overlays a fixed
      number of pixels across.  0 without a camera or viewport. }
    function  PixelSizeAt(const aWorld: TpvVector3D): Double;

    { A world point under client pixel X, Y, on the plane through aAnchor
      with aNormal - the plane a drag moves on. }
    function  PointOnPlane(X, Y: Integer; const aNormal, aAnchor: TpvVector3D;
                           out aWorld: TpvVector3D): Boolean;

    // --- Scene notifications (virtual, for descendants) --------------------

    // Drops every reference this tool manager holds to aObject - selection
    // included.  Called by the scene before aObject is freed.
    procedure ForgetObject(aObject: TvgObject); virtual;

    // aStore is about to be freed by the scene (after ForgetObject for each
    // of its objects).  The base holds nothing per store.
    procedure StoreGone(aStore: TvgObjectStore); virtual;

    // The scene's data is going - cleared, reloaded, or the scene itself
    // freed or replaced.  The base clears the selection.
    procedure SceneCleared; virtual;

    // The view changed - the camera orbited, panned or zoomed - or, with
    // aPlane, the plane a descendant draws on moved.  The base does nothing;
    // a descendant redraws what its tool drew in screen-sized terms.
    procedure ViewChanged(aPlane: Boolean = False); virtual;

    // The camera the tool manager works with: the scene's active one.
    property ActiveCamera : TvgCamera read GetActiveCamera;

    // --- Zoom to all data ----------------------------------------------
    // Moves the active camera so every object in the scene is on screen,
    // fitted to this tool manager's current viewport.  Not gestures - call
    // them from a button, a menu item, a hotkey, or right after loading data.
    //
    // aMargin is the fraction of empty space left around the data; 1.0
    // touches the data to the edge of the viewport.
    //
    // All three return False, and move nothing, when there is no scene, no
    // active camera, or no data with usable bounds (see
    // TvgScene.GetDataBounds).

    { Frames all the data without turning the camera - the current view
      direction is kept and only the eye moves. }
    function ZoomAll(aMargin: Double = CAMERA_DEFAULT_ZOOM_MARGIN): Boolean;

    { Frames all the data looking straight down: a plan view, in whichever
      world axis convention is active. }
    function ZoomAllLookDown(aMargin: Double = CAMERA_DEFAULT_ZOOM_MARGIN): Boolean;

    { Switches the active camera to orthographic and frames all the data
      looking down - the survey/map view.  Perspective foreshortening is what
      makes a plan view hard to read, so this is the combination a "look down
      at everything" button usually wants. }
    function ZoomAllPlanView(aMargin: Double = CAMERA_DEFAULT_ZOOM_MARGIN): Boolean;

    { The aspect ratio the fit is computed for: this tool manager's viewport,
      falling back to the renderer's and then to square.  Public because an
      application calling TvgCamera.ZoomAll directly needs the same number. }
    function GetViewportAspectRatio: Double;

    // Read-only: the currently selected TvgObject (nil if none) - the last
    // one selected.
    property SelectedObject : TvgObject read fSelectedObject;
    property SelectionCount : Integer read GetSelectionCount;
    property Selection[Index: Integer] : TvgObject read GetSelection;

  published
    property Scene         : TvgScene          read fScene         write SetScene;
    Property Renderer      : TvgRenderEngine    Read fRenderer     write SetRenderer;

    property ActionMode    : TvgToolActionMode  read fActionMode   write SetActionMode  default TAM_OBJECT_SELECT;
    property OrbitButton   : TvgMouseButton     read fOrbitButton  write SetOrbitButton  default vgmbLeft;
    property PanButton     : TvgMouseButton     read fPanButton    write SetPanButton    default vgmbMiddle;
    property DollyButton   : TvgMouseButton     read fDollyButton  write SetDollyButton  default vgmbRight;
    // 0=horizontal, 1=front (vertical), 2=side (vertical), in the active world
    // axis convention (see Vulkan_WorldAxes).  Used for object drag.
    property DragPlaneAxis : Integer            read fDragPlaneAxis write SetDragPlaneAxis default 0;

    property OnObjectPicked : TvgObjectPickedEvent     read fOnObjectPicked write fOnObjectPicked;
    property OnObjectMoved  : TvgObjectMovedEvent      read fOnObjectMoved  write fOnObjectMoved;
    property OnObjectAddReq : TvgObjectAddRequestEvent read fOnObjectAddReq  write fOnObjectAddReq;

    property OnSelectionChanged : TNotifyEvent read fOnSelectionChanged write fOnSelectionChanged;

    // How near, in pixels, the cursor must be to pick a point or a line, or
    // grab a vertex.  Default 6.
    property PickRadius : Integer read fPickRadius write fPickRadius default 6;
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

destructor TvgObject.Destroy;
var
  TM : TvgToolManager;
begin
  if Assigned(fDataStore) and Assigned(fDataStore.fScene) then
  begin
    // Freed without RemoveObject - with its store's ClearData, say: no tool
    // manager may keep it, and its address may come back as a new object.
    for TM in fDataStore.fScene.GetToolManagers do
      TM.ForgetObject(Self);
    fDataStore.fScene.UnregisterObject(Self);
  end;
  inherited;
end;

procedure TvgObject.Reset;
begin
  if not Assigned(fDataStore) then Exit;
  if fObjIndex = -1 then Exit;

  fDataStore.ResetObject(fObjIndex);
  fCurrentVertex   := -1;
  fCurrentInstance := -1;
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

procedure TvgObject.AddObjectID;
  Var I:Integer;
begin
  I:=AddInstance;
  If I<>-1 then
  Begin
    SetUpObjectID;
    SetInstanceObjID(fObjHigh,fObjLow);
  End;
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

procedure TvgObject.SetVertexWorldPosition(const aWorld: TpvVector3D);
var
  L : TpvVector3D;
begin
  if not Assigned(fDataStore) then
    Exit;

  L := LocalFromWorld(aWorld);
  SetVertexPosition(L.x, L.y, L.z);
end;

function TvgObject.LocalFromWorld(const aWorld: TpvVector3D): TpvVector3D;
begin
  if Assigned(fDataStore) and Assigned(fDataStore.Scene) then
    Result := fDataStore.Scene.WorldToLocal(aWorld)
  else
    Result := aWorld;

  CustomAssert((Abs(Result.x) < VG_LOCAL_COORD_LIMIT) and
               (Abs(Result.y) < VG_LOCAL_COORD_LIMIT) and
               (Abs(Result.z) < VG_LOCAL_COORD_LIMIT),
    Format('SetVertexWorldPosition: (%.3f, %.3f, %.3f) is more than %.0f from ' +
           'the scene''s WorldOrigin, so float32 cannot store it to the ' +
           'millimetre.  Move WorldOrigin nearer the data.',
           [aWorld.x, aWorld.y, aWorld.z, VG_LOCAL_COORD_LIMIT]), fDataStore);
end;

function TvgObject.WorldFromLocal(const aLocal: TpvVector3): TpvVector3D;
begin
  // Widened to double first, then shifted: adding the origin in float32
  // would round a survey coordinate.
  Result := TpvVector3D.Create(aLocal.x, aLocal.y, aLocal.z);
  if Assigned(fDataStore) and Assigned(fDataStore.Scene) then
    Result := fDataStore.Scene.LocalToWorld(Result);
end;

function TvgObject.GetVertexCount: Integer;
begin
  Result := 0;
  if Assigned(fDataStore) and (fObjIndex >= 0) then
    Result := fDataStore.GetObjectVertexCount(fObjIndex);
end;

procedure TvgObject.NotifyEdited;
begin
  if Assigned(fDataStore) and Assigned(fDataStore.Scene) then
    fDataStore.Scene.NotifyDataChanged(fDataStore);
end;

procedure TvgObject.SetVisibleON(const Value: Boolean);
begin
  if Value = VisibleON then Exit;
  inherited SetVisibleON(Value);

  // Not in a store (yet, or any more): the flag is all there is.  A deleted
  // object's record is a tombstone that draws nothing anyway.
  if not Assigned(fDataStore) or (fObjIndex < 0) or
     fDataStore.IsObjectDeleted(fObjIndex) then
    Exit;

  fDataStore.SetObjectHidden(fObjIndex, not Value);
  // The data did not change, but the frames must be recorded again without
  // (or with) the object.
  NotifyEdited;
end;

procedure TvgObject.SetColorOverride(const aColor: TpvVector4);
var
  Before : Cardinal;
begin
  if not Assigned(fDataStore) or (fObjIndex < 0) or
     fDataStore.IsObjectDeleted(fObjIndex) then
    Exit;

  Before := fDataStore.GetObjectColorOverridePacked(fObjIndex);
  fDataStore.SetObjectColorOverride(fObjIndex, aColor);
  if fDataStore.GetObjectColorOverridePacked(fObjIndex) <> Before then
    NotifyEdited;   // recorded again with the new colour
end;

procedure TvgObject.ClearColorOverride;
begin
  SetColorOverride(TpvVector4.Create(0, 0, 0, 0));
end;

function TvgObject.GetColorOverride(out aColor: TpvVector4): Boolean;
begin
  Result := Assigned(fDataStore) and (fObjIndex >= 0) and
            not fDataStore.IsObjectDeleted(fObjIndex) and
            fDataStore.GetObjectColorOverride(fObjIndex, aColor);
end;

function TvgObject.CanEdit: Boolean;
begin
  Result := Assigned(fDataStore) and (fObjIndex >= 0) and
            not LockON and not FrozenON;
end;

function TvgObject.GetVertexWorldPosition(aLocal: Integer): TpvVector3D;
begin
  if not Assigned(fDataStore) or (fObjIndex < 0) then
    raise EvgSceneEditException.Create('GetVertexWorldPosition: object is not in a store');
  Result := WorldFromLocal(fDataStore.GetObjectVertexPosition(fObjIndex, aLocal));
end;

function TvgObject.GetVertexWorldPositions: TArray<TpvVector3D>;
var
  L : TArray<TpvVector3>;
  I : Integer;
begin
  Result := nil;
  if not Assigned(fDataStore) or (fObjIndex < 0) then Exit;
  L := fDataStore.GetObjectVertexPositions(fObjIndex);
  SetLength(Result, Length(L));
  for I := 0 to High(L) do
    Result[I] := WorldFromLocal(L[I]);
end;

function TvgObject.MoveVertex(aLocal: Integer; const aWorld: TpvVector3D): Boolean;
var
  L : TpvVector3D;
begin
  Result := False;
  if not CanEdit then Exit;
  if (aLocal < 0) or (aLocal >= GetVertexCount) then Exit;

  L := LocalFromWorld(aWorld);
  fDataStore.SetObjectVertexPosition(fObjIndex, aLocal, L.x, L.y, L.z);

  // A position write only ever grows the bounds; a move has to rescan.
  fDataStore.RebuildObjectBounds(fObjIndex);
  NotifyEdited;
  Result := True;
end;

function TvgObject.Translate(const aDelta: TpvVector3D): Boolean;
var
  I    : Integer;
  P    : TArray<TpvVector3>;
  W    : TpvVector3D;
  L    : TpvVector3D;
begin
  Result := False;
  if not CanEdit then Exit;

  P := fDataStore.GetObjectVertexPositions(fObjIndex);
  for I := 0 to High(P) do
  begin
    // Through world coordinates, in double, so the local limit is checked
    // where the vertex lands - the same rule as every other world write.
    W := WorldFromLocal(P[I]) + aDelta;
    L := LocalFromWorld(W);
    fDataStore.SetObjectVertexPosition(fObjIndex, I, L.x, L.y, L.z);
  end;

  fDataStore.RebuildObjectBounds(fObjIndex);
  NotifyEdited;
  Result := True;
end;

function TvgObject.DeleteVertex(aLocal: Integer): Boolean;
begin
  Result := False;
  if not CanEdit then Exit;
  if (aLocal < 0) or (aLocal >= GetVertexCount) then Exit;

  fDataStore.RemoveObjectVertex(fObjIndex, aLocal);   // rebuilds the bounds

  // The vertex CurrentVertex named may be gone, or renumbered.
  if fCurrentVertex >= GetVertexCount then
    fCurrentVertex := GetVertexCount - 1;

  NotifyEdited;
  Result := True;
end;

function TvgObject.SplitSegment(aFrom, aTo: Integer; const aWorld: TpvVector3D): Integer;
var
  D          : TvgObjectData;
  VC, IC     : Integer;
  VS, IS_    : Integer;     // bytes per vertex / per index
  Indexed    : Boolean;
  K          : Integer;
  Pos        : Integer;     // where the segment is: index entry or vertex
  NewV       : Integer;

  function Idx(aEntry: Integer): Integer;
  begin
    if IS_ = 2 then
      Result := PWord(@D.Indices[aEntry * 2])^
    else
      Result := Integer(PCardinal(@D.Indices[aEntry * 4])^);
  end;

  function IndexBytes(aValue: Integer): TBytes;
  begin
    SetLength(Result, IS_);
    if IS_ = 2 then
      PWord(@Result[0])^ := Word(aValue)
    else
      PCardinal(@Result[0])^ := Cardinal(aValue);
  end;

  function VertexBytes(aVertex: Integer): TBytes;
  begin
    SetLength(Result, VS);
    Move(D.Vertices[aVertex * VS], Result[0], VS);
  end;

  // aBytes inserted into aArray at byte offset aAt.
  procedure InsertBytes(var aArray: TBytes; aAt: Integer; const aBytes: TBytes);
  var
    Old : Integer;
  begin
    Old := Length(aArray);
    SetLength(aArray, Old + Length(aBytes));
    if aAt < Old then
      Move(aArray[aAt], aArray[aAt + Length(aBytes)], Old - aAt);
    Move(aBytes[0], aArray[aAt], Length(aBytes));
  end;

  function IsPair(A, B: Integer): Boolean;
  begin
    Result := ((A = aFrom) and (B = aTo)) or ((A = aTo) and (B = aFrom));
  end;

begin
  Result := -1;
  if not CanEdit then Exit;
  if not (fDataStore.Topology in [LINE_LIST, LINE_STRIP]) then Exit;
  VC := GetVertexCount;
  if (aFrom < 0) or (aFrom >= VC) or (aTo < 0) or (aTo >= VC) or (aFrom = aTo) then Exit;

  D       := GetData;
  VS      := Length(D.Vertices) div VC;
  Indexed := fDataStore.GetIndexType <> itNONE;
  IC      := fDataStore.GetObjectIndexCount(fObjIndex);
  IS_     := 0;
  if Indexed and (IC > 0) then
    IS_ := Length(D.Indices) div IC;
  if Indexed and (IS_ = 0) then Exit;

  // Find the segment.
  Pos := -1;
  if Indexed then
  begin
    if fDataStore.Topology = LINE_LIST then
    begin
      K := 0;
      while (Pos < 0) and (K + 1 < IC) do
      begin
        if IsPair(Idx(K), Idx(K + 1)) then Pos := K;
        Inc(K, 2);
      end;
    end
    else
      for K := 0 to IC - 2 do
        if (Pos < 0) and IsPair(Idx(K), Idx(K + 1)) then
          Pos := K;
  end
  else
  begin
    if fDataStore.Topology = LINE_LIST then
    begin
      K := 0;
      while (Pos < 0) and (K + 1 < VC) do
      begin
        if IsPair(K, K + 1) then Pos := K;
        Inc(K, 2);
      end;
    end
    else
      for K := 0 to VC - 2 do
        if (Pos < 0) and IsPair(K, K + 1) then
          Pos := K;
  end;
  if Pos < 0 then Exit;

  if Indexed then
  begin
    // The new vertex at the end; nothing else renumbers.
    NewV := VC;
    InsertBytes(D.Vertices, Length(D.Vertices), VertexBytes(aFrom));
    if fDataStore.Topology = LINE_LIST then
    begin
      // The pair P Q becomes P N N Q: P-N and N-Q, either way round.
      InsertBytes(D.Indices, (Pos + 1) * IS_, IndexBytes(NewV));
      InsertBytes(D.Indices, (Pos + 1) * IS_, IndexBytes(NewV));
    end
    else
      InsertBytes(D.Indices, (Pos + 1) * IS_, IndexBytes(NewV));
  end
  else
  begin
    if fDataStore.Topology = LINE_LIST then
    begin
      // A B -> A N N B: two copies in the middle.
      NewV := Pos + 1;
      InsertBytes(D.Vertices, (Pos + 1) * VS, VertexBytes(aFrom));
      InsertBytes(D.Vertices, (Pos + 1) * VS, VertexBytes(aFrom));
    end
    else
    begin
      NewV := Pos + 1;
      InsertBytes(D.Vertices, (Pos + 1) * VS, VertexBytes(aFrom));
    end;
  end;

  SetData(D);

  // The copies took aFrom's position; now the new one's.  The instances and
  // bounds are right already (SetData).
  MoveVertex(NewV, aWorld);
  if not Indexed and (fDataStore.Topology = LINE_LIST) then
    MoveVertex(NewV + 1, aWorld);     // its twin

  Result := NewV;
end;

function TvgObject.Centroid: TpvVector3D;
var
  I : Integer;
  W : TArray<TpvVector3D>;
begin
  Result := TpvVector3D.Create(0, 0, 0);
  W := GetVertexWorldPositions;
  if Length(W) = 0 then Exit;

  for I := 0 to High(W) do
    Result := Result + W[I];
  Result := Result * (1.0 / Length(W));
end;

function TvgObject.NearestVertex(const aWorld: TpvVector3D; out aDistance: Double): Integer;
var
  I : Integer;
  D : Double;
  W : TArray<TpvVector3D>;
begin
  Result    := -1;
  aDistance := 0;
  W := GetVertexWorldPositions;
  for I := 0 to High(W) do
  begin
    D := (W[I] - aWorld).Length;
    if (Result < 0) or (D < aDistance) then
    begin
      Result    := I;
      aDistance := D;
    end;
  end;
end;

procedure TvgObject.Delete;
begin
  if Assigned(fDataStore) then
    fDataStore.RemoveObject(Self);
end;

function TvgObject.GetData: TvgObjectData;
begin
  if not Assigned(fDataStore) or (fObjIndex < 0) then
    raise EvgSceneEditException.Create('GetData: object is not in a store');
  Result := fDataStore.GetObjectData(fObjIndex);
end;

procedure TvgObject.SetData(const aData: TvgObjectData);
var
  I : Integer;
begin
  if not Assigned(fDataStore) or (fObjIndex < 0) then
    raise EvgSceneEditException.Create('SetData: object is not in a store');

  fDataStore.SetObjectData(fObjIndex, aData);

  // The instances name the object they came from; they must name this one.
  if fDataStore.IsInstanceTypeSet(idtObjID) then
  begin
    SetUpObjectID;
    for I := 0 to fDataStore.GetObjectInstanceCount(fObjIndex) - 1 do
      fDataStore.SetObjectInstanceObjID(fObjIndex, I, fObjHigh, fObjLow);
  end;

  fCurrentVertex   := fDataStore.GetObjectVertexCount(fObjIndex) - 1;
  fCurrentInstance := fDataStore.GetObjectInstanceCount(fObjIndex) - 1;
  NotifyEdited;
end;

function TvgObject.GetPrimitives(out aIndices: TArray<Integer>): Integer;
var
  VC, N, I, K, C : Integer;
  Src            : TArray<Integer>;
  Raw            : TArray<Cardinal>;

  procedure Put(const aPrim: array of Integer);
  var
    J : Integer;
  begin
    for J := 0 to High(aPrim) do
      if (aPrim[J] < 0) or (aPrim[J] >= VC) then
        Exit;               // a restart index, or data that is not there
    for J := 0 to High(aPrim) do
    begin
      aIndices[C] := aPrim[J];
      Inc(C);
    end;
  end;

begin
  aIndices := nil;
  Result   := 1;
  if not Assigned(fDataStore) or (fObjIndex < 0) then Exit;

  VC := fDataStore.GetObjectVertexCount(fObjIndex);

  // The vertex numbers in draw order: the index list, or 0..VC-1.
  if fDataStore.GetIndexType <> itNONE then
  begin
    // All at once: a call per index takes the store's lock per index.
    Raw := fDataStore.GetObjectIndices(fObjIndex);
    N   := Length(Raw);
    SetLength(Src, N);
    for I := 0 to N - 1 do
      Src[I] := Integer(Raw[I] and $7FFFFFFF);
  end
  else
  begin
    N := VC;
    SetLength(Src, N);
    for I := 0 to N - 1 do
      Src[I] := I;
  end;

  case fDataStore.Topology of
    LINE_LIST, LINE_STRIP, LINE_LIST_WITH_ADJACENCY, LINE_STRIP_WITH_ADJACENCY:
      Result := 2;
    TRIANGLE_LIST, TRIANGLE_STRIP, TRIANGLE_FAN, TRIANGLE_LIST_WITH_ADJACENCY:
      Result := 3;
  else
    Result := 1;
  end;

  // No primitive has more corners than the source has entries.
  SetLength(aIndices, Result * N);
  C := 0;

  case fDataStore.Topology of
    LINE_LIST:
      for K := 0 to (N div 2) - 1 do
        Put([Src[2 * K], Src[2 * K + 1]]);
    LINE_STRIP:
      for K := 0 to N - 2 do
        Put([Src[K], Src[K + 1]]);
    LINE_LIST_WITH_ADJACENCY:
      for K := 0 to (N div 4) - 1 do
        Put([Src[4 * K + 1], Src[4 * K + 2]]);
    LINE_STRIP_WITH_ADJACENCY:
      for K := 1 to N - 3 do
        Put([Src[K], Src[K + 1]]);
    TRIANGLE_LIST:
      for K := 0 to (N div 3) - 1 do
        Put([Src[3 * K], Src[3 * K + 1], Src[3 * K + 2]]);
    TRIANGLE_STRIP:
      for K := 0 to N - 3 do
        Put([Src[K], Src[K + 1], Src[K + 2]]);
    TRIANGLE_FAN:
      for K := 1 to N - 2 do
        Put([Src[0], Src[K], Src[K + 1]]);
    TRIANGLE_LIST_WITH_ADJACENCY:
      for K := 0 to (N div 6) - 1 do
        Put([Src[6 * K], Src[6 * K + 2], Src[6 * K + 4]]);
  else
    for K := 0 to N - 1 do
      Put([Src[K]]);
  end;

  SetLength(aIndices, C);
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
  fDefaultColor  := TpvVector4.Create(1, 1, 1, 1);
  fInDataBounds  := True;
  fDepthTest     := True;
  fColorOverrideON := True;


//  fInstanceDataON   := False;

  fScene := nil;

end;

destructor TvgObjectStore.Destroy;
begin
  // A store freed by anything other than its scene (a TComponent owner, or a
  // direct Free) must leave the scene's owning list, or ClearScene later
  // runs ClearData on the freed store.  A no-op when the scene is the one
  // freeing it.
  If assigned(fScene) then
    fScene.DetachDataStore(Self);

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

  //Frees this store's pipeline(s) and GPU buffers, which a frame still
  //recording or executing uses - a live PointSize change comes this way
  //(TvgDelaunayDisplay.RebuildStorePipeline).
  FinishFramesInFlight;

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

function TvgObjectStore.GetObjectItem(Index: Integer): TvgObject;
begin
  Result := fObjects.Items[Index];
end;

function TvgObjectStore.GetSelectable: Boolean;
  Var I,L:Integer;
begin
  Result := False;
  L:= self.fObjects.Count;
  If L=0 then exit;
  For I:=0 to L-1 do
    If fObjects.Items[I].Selectable then
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


function TvgObjectStore.AddObject(aWithInstances:Boolean): TvgObject;
var
  Obj: TvgObject;
begin
  Obj            := TvgObject.Create;
  Obj.fDataStore := Self;
  
  // Add to data store and get index
  Obj.fObjIndex  := AddDataObject(aWithInstances);

  // Add to our object list
  fObjects.Add(Obj);

  if Assigned(fScene) then
    fScene.RegisterObject(Obj);

  Result := Obj;
end;

procedure TvgObjectStore.RemoveObject(aObject: TvgObject);
var
  TM : TvgToolManager;
begin
  if not Assigned(aObject) then
    Exit;
  if fObjects.IndexOf(aObject) < 0 then
    Exit;    // not ours

  // Before anything is freed: from here on a click that lands on the last
  // frame drawn with this object must not find it, and no tool may still
  // be holding it.
  if Assigned(fScene) then
  begin
    fScene.UnregisterObject(aObject);
    for TM in fScene.GetToolManagers do
      TM.ForgetObject(aObject);
  end;

  // Its geometry stops drawing.  The record stays as a tombstone, so every
  // other object's ObjIndex still holds.
  if aObject.fObjIndex >= 0 then
    DeleteDataObject(aObject.fObjIndex);

  // TvgBaseObject.Destroy requires it inactive.  Freeing it at once is safe
  // for rendering: a draw reads the store's records, never TvgObjects.
  aObject.Active := False;
  aObject.fObjIndex  := -1;
  aObject.fDataStore := nil;
  fObjects.Remove(aObject);   // owned: frees it

  if Assigned(fScene) then
    fScene.NotifyDataChanged(Self);
end;

procedure TvgObjectStore.FillShape(aObject: TvgObject; const aPoints: array of TpvVector3D;
                                   aClosed: Boolean; const aColor: TpvVector4);
var
  N, I     : Integer;
  Colour   : Boolean;
  Indexed  : Boolean;

  procedure V(const P: TpvVector3D);
  begin
    aObject.AddVertex;
    aObject.SetVertexWorldPosition(P);
    if Colour then
      aObject.SetVertexColor(aColor.x, aColor.y, aColor.z, aColor.w);
  end;

begin
  N := Length(aPoints);

  Colour   := IsVertexTypeSet(vdtColor);
  Indexed  := GetIndexType <> itNONE;

  // An object in a store with instance data must have an instance, or the
  // draw has nothing to bind - so a pickable store's objects get their ID.
  if IsInstanceTypeSet(idtObjID) then
    aObject.AddObjectID;

  case Topology of
    POINT_LIST:
      for I := 0 to N - 1 do
        V(aPoints[I]);

    LINE_STRIP:
      begin
        for I := 0 to N - 1 do
          V(aPoints[I]);
        if aClosed then
          V(aPoints[0]);
      end;

    LINE_LIST:
      if Indexed then
      begin
        // Each inner vertex once, shared by the two segments meeting there.
        for I := 0 to N - 1 do
          V(aPoints[I]);
        for I := 0 to N - 2 do
          aObject.AddIndices([I, I + 1]);
        if aClosed then
          aObject.AddIndices([N - 1, 0]);
      end
      else
      begin
        for I := 0 to N - 2 do
        begin
          V(aPoints[I]);
          V(aPoints[I + 1]);
        end;
        if aClosed then
        begin
          V(aPoints[N - 1]);
          V(aPoints[0]);
        end;
      end;
  else
    raise EvgSceneEditException.CreateFmt(
      'AddShape: a %s store cannot hold points or lines',
      [GetEnumName(TypeInfo(TvgPrimitiveTopology), Ord(Topology))]);
  end;
end;

function TvgObjectStore.AddShape(const aPoints: array of TpvVector3D; aClosed: Boolean;
                                 const aColor: TpvVector4): TvgObject;
begin
  Result := AddObject(IsInstanceTypeSet(idtObjID));
  try
    FillShape(Result, aPoints, aClosed, aColor);
  except
    RemoveObject(Result);
    raise;
  end;

  if Assigned(fScene) then
    fScene.NotifyDataChanged(Self);
end;

procedure TvgObjectStore.CheckPolyline(const aPoints: array of TpvVector3D; aClosed: Boolean);
begin
  if not (Topology in [LINE_LIST, LINE_STRIP]) then
    raise EvgSceneEditException.Create('AddLine/AddPolyline need a LINE_LIST or LINE_STRIP store');
  if Length(aPoints) < 2 then
    raise EvgSceneEditException.Create('AddPolyline needs at least two points');
  if aClosed and (Length(aPoints) < 3) then
    raise EvgSceneEditException.Create('A closed polyline needs at least three points');
end;

procedure TvgObjectStore.RefillPolyline(aObject: TvgObject; const aPoints: array of TpvVector3D;
                                        aClosed: Boolean);
begin
  RefillPolyline(aObject, aPoints, aClosed, fDefaultColor);
end;

procedure TvgObjectStore.RefillPolyline(aObject: TvgObject; const aPoints: array of TpvVector3D;
                                        aClosed: Boolean; const aColor: TpvVector4);
begin
  if not Assigned(aObject) or (fObjects.IndexOf(aObject) < 0) then
    raise EvgSceneEditException.Create('RefillPolyline: the object is not in this store');
  CheckPolyline(aPoints, aClosed);

  aObject.Reset;     // empty ranges, same object; see TvgVulkanDataStore.ResetObject
  FillShape(aObject, aPoints, aClosed, aColor);

  if Assigned(fScene) then
    fScene.NotifyDataChanged(Self);
end;

procedure TvgObjectStore.RefillSegments(aObject: TvgObject; const aSegments: array of TpvVector3D);
begin
  RefillSegments(aObject, aSegments, fDefaultColor);
end;

procedure TvgObjectStore.RefillSegments(aObject: TvgObject; const aSegments: array of TpvVector3D;
                                        const aColor: TpvVector4);
var
  I      : Integer;
  Colour : Boolean;
begin
  if not Assigned(aObject) or (fObjects.IndexOf(aObject) < 0) then
    raise EvgSceneEditException.Create('RefillSegments: the object is not in this store');
  if (Topology <> LINE_LIST) or (GetIndexType = itNONE) then
    raise EvgSceneEditException.Create('RefillSegments needs an indexed LINE_LIST store');
  if Odd(Length(aSegments)) then
    raise EvgSceneEditException.Create('RefillSegments needs pairs of points');

  Colour := IsVertexTypeSet(vdtColor);

  aObject.Reset;
  if Length(aSegments) > 0 then
  begin
    if IsInstanceTypeSet(idtObjID) then
      aObject.AddObjectID;

    for I := 0 to High(aSegments) do
    begin
      aObject.AddVertex;
      aObject.SetVertexWorldPosition(aSegments[I]);
      if Colour then
        aObject.SetVertexColor(aColor.x, aColor.y, aColor.z, aColor.w);
    end;
    for I := 0 to (Length(aSegments) div 2) - 1 do
      aObject.AddIndices([2 * I, 2 * I + 1]);
  end;

  if Assigned(fScene) then
    fScene.NotifyDataChanged(Self);
end;

function TvgObjectStore.AddPoint(const aWorld: TpvVector3D): TvgObject;
begin
  Result := AddPoint(aWorld, fDefaultColor);
end;

function TvgObjectStore.AddPoint(const aWorld: TpvVector3D; const aColor: TpvVector4): TvgObject;
begin
  if Topology <> POINT_LIST then
    raise EvgSceneEditException.Create('AddPoint needs a POINT_LIST store');
  Result := AddShape([aWorld], False, aColor);
end;

function TvgObjectStore.AddLine(const aFrom, aTo: TpvVector3D): TvgObject;
begin
  Result := AddLine(aFrom, aTo, fDefaultColor);
end;

function TvgObjectStore.AddLine(const aFrom, aTo: TpvVector3D; const aColor: TpvVector4): TvgObject;
begin
  Result := AddPolyline([aFrom, aTo], False, aColor);
end;

function TvgObjectStore.AddPolyline(const aPoints: array of TpvVector3D; aClosed: Boolean): TvgObject;
begin
  Result := AddPolyline(aPoints, aClosed, fDefaultColor);
end;

function TvgObjectStore.AddPolyline(const aPoints: array of TpvVector3D; aClosed: Boolean;
                                    const aColor: TpvVector4): TvgObject;
begin
  CheckPolyline(aPoints, aClosed);
  Result := AddShape(aPoints, aClosed, aColor);
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

// ClearGraphicPipes is unsafe � use DisConnectDataFromSceneandRenderer instead
  // which calls SP.RemoveGraphicPipe before clearing the dictionary.
  If assigned(fScene) and assigned(fScene.fRendererList) then
    for J := 0 to fScene.fRendererList.Count-1 do
      DisConnectDataFromSceneandRenderer(fScene.fRendererList.Items[J]);

  If assigned(fObjects ) then
  Begin
    If fObjects.Count>0 then
      For I:=0 to fObjects.Count-1 do
        fObjects.Items[I].Active := False;

    fObjects.Clear;
  End;

  ClearAll(True);

end;

procedure TvgObjectStore.ClearGraphicPipes;
begin
  inherited;

end;

function TvgObjectStore.GetShaderPointSizeExpression: String;
begin
  if fPointSize > 0 then
    // Fixed decimals give a clean GLSL float literal; FloatToStr would spell a
    // Single out as its full binary expansion (6.30000019073486).  Invariant
    // settings so the result never picks up a comma decimal separator from
    // the machine's locale.
    Result := Format('%.4f', [fPointSize], TFormatSettings.Invariant)
  else
    Result := inherited GetShaderPointSizeExpression;
end;

procedure TvgObjectStore.ConfigureGraphicPipeline(GP: TvgGraphicPipeline);
var
  SHS: TvgShaderSpecialisationItem;
begin

    // Shader files � ObjectStore owns these
    CustomAssert(GP.BuildShaderNames(fShaderBaseVertName, fShaderBaseGeomName, fShaderBaseFragName),  'Shader file names not assigned', GP);

    GP.UseShaders         := fUseShaders;        // new property, not hardcoded [PS_VERTEX, PS_FRAGMENT]

    // Topology � ObjectStore owns this
    GP.InputAssembly.Topology := GetVGPrimitiveTopology(fTopology);

    if GP.InputAssembly.Topology = POINT_LIST then
    begin
      SHS := GP.VertexS.SpecialConst.Add;
      SHS.Name := SC_POINT_SIZE_ON;
      SHS.SpecType := TS_BOOLEAN;
      SHS.SpecTValue := 'TRUE';
      SHS.ConstantID := CI_POINT_SIZE_ON;
    end;

    // Rasterizer � ObjectStore owns these (new properties)
    GP.Rasterizer.PolygonMode := GetVGPolygonMode(fPolygonMode);   // default POLYGON_FILL
    GP.Rasterizer.CullMode    := GetVGCullMode(fCullMode);      // default CULL_BACK (not NONE)
    GP.Rasterizer.FrontFace   := GetVGFrontFace(fFrontFace);     // default FF_CLOCKWISE
    GP.Rasterizer.LineWidth   := fLineWidth;     // default 1.0

end;

procedure TvgObjectStore.GPUBuffersReplaced;
var
  I : Integer;
begin
  inherited;
  // Not NotifyDataChanged: this is the middle of an edit, which notifies
  // when it is done.  Only the recorded frames cannot wait for that.
  if Assigned(fScene) and Assigned(fScene.RendererList) then
    for I := 0 to fScene.RendererList.Count - 1 do
      if Assigned(fScene.RendererList.Items[I]) then
        fScene.RendererList.Items[I].FlagRebuildALLFrames;
end;

procedure TvgObjectStore.UpdateGraphicPipeline(aPipe: TvgGraphicPipeline);
begin
  inherited UpdateGraphicPipeline(aPipe);
  if not Assigned(aPipe) then Exit;

  // After the renderer's ConfigureGraphicPipelineFromRenderPass, which turns
  // the depth test on for every pipeline of a render pass with a depth
  // buffer.
  if not fDepthTest then
  begin
    aPipe.DepthStencil.DepthTestEnable  := False;
    aPipe.DepthStencil.DepthWriteEnable := False;
  end;

  // Last, after the renderer's push constants: theirs are declared at
  // offset 0 in their shaders, so nothing may go in front of them.
  if fColorOverrideON then
    AddColorOverridePushConstant(aPipe);
end;

class procedure TvgObjectStore.AddColorOverridePushConstant(aPipe: TvgGraphicPipeline);
var
  Off    : TVkUInt32;
  Stages : TVkShaderStageFlags;
  PCI    : TvgPushConstantItem;
begin
  if not Assigned(aPipe) or not Assigned(aPipe.PushConstantCol) then Exit;
  // Once: the pipeline may be updated again.
  if TvgVulkanDataStore.FindObjectColorPushConstant(aPipe, Off, Stages) then Exit;

  PCI := aPipe.PushConstantCol.Add;
  PCI.Name             := 'inObjectColor';
  PCI.PushConstantName := TvgPushConstant_ObjectColor.GetPropertyName;
  aPipe.PushConstantCol.UpdateOffsets;
  if PCI.PushConstant is TvgPushConstant_ObjectColor then
    TvgPushConstant_ObjectColor(PCI.PushConstant).Offset := PCI.Offset;
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
begin
  Result := False;

  If not (fSceneState = SS_LOADING   ) then exit;
  If not assigned( aDataStore) then exit;

  DoAddDataStore(aDataStore);

  Result := True;

end;

Procedure TvgScene.DoAddDataStore(aDataStore: TvgObjectStore);
begin
  CustomAssert(Assigned(fSceneData),'Scene Data list NOT created',self);

  If fSceneData.IndexOf(aDataStore)=-1 then
    Begin

      fSceneData.Add(aDataStore);
      aDataStore.fScene     := Self;
      aDataStore.fBaseScene := self;  //important

      aDataStore.FVulkanDevice :=  GetVulkanDevice;

      // A store filled before it joined the scene brings its objects along.
      RegisterStoreObjects(aDataStore);
    End;
end;

Function TvgScene.AddDataStoreLive(aDataStore: TvgObjectStore): Boolean;
begin
  Result := False;
  If not assigned(aDataStore) then exit;

  Case fSceneState of
    SS_LOADING : Begin
                   // Load_End builds and activates it with everything else.
                   Result := AddDataStore(aDataStore);
                   exit;
                 End;
    SS_READY   : ;
  else
    exit;
  End;

  DoAddDataStore(aDataStore);

  // What Load_End does for every store, for this one: TvgScene.SetEnabled
  // activates each store of an active scene.
  If Active and not aDataStore.Active then
    aDataStore.Active := True;

  ConnectStoreLive(aDataStore);
  NotifyDataChanged(aDataStore);

  Result := True;
end;

Procedure TvgScene.ConnectStoreLive(aDataStore: TvgObjectStore);
  Var I, J : Integer;
      RE   : TvgBaseRenderEngine;
      SP   : TvgSubPass;
      GP   : TvgGraphicPipeline;
begin
  If not assigned(aDataStore) then exit;
  If not assigned(fRendererList) then exit;

  For I := 0 to fRendererList.Count - 1 do
  Begin
    RE := fRendererList.Items[I];
    If not (assigned(RE) and RE.Active) then Continue;
    If not assigned(RE.RenderPass) then Continue;

    For J := 0 to RE.RenderPass.SubPasses.Count - 1 do
    Begin
      SP := RE.RenderPass.SubPasses.Items[J];
      If not assigned(SP) then Continue;

      // Returns the existing pipe if there is one - the same idempotent call
      // BuildGraphicPipelinesForRenderer makes for every store.
      GP := aDataStore.BuildAGraphicPipeline(RE, SP);

      // Only this store's pipe: TvgBaseRenderEngine.ActivateGraphicPipeLines
      // would activate every store's, and the same "skip if already active"
      // check TvgSubPass.ActivateGraphicPipelines makes per pipe.
      If assigned(GP) and not GP.Active and not fDeferLiveActivation then
        GP.Active := True;
    End;
  End;
end;

Procedure TvgScene.RemoveDataStore(aDataStore: TvgObjectStore);
begin
  If not DetachDataStore(aDataStore) then exit;

  aDataStore.Free;   // detached, so its destructor finds nothing left to undo
end;

Function TvgScene.DetachDataStore(aDataStore: TvgObjectStore): Boolean;
  Var I  : Integer;
      TM : TvgToolManager;
begin
  Result := False;
  If not assigned(aDataStore) then exit;
  // Nil while the scene is being destroyed: FreeAndNil clears the field
  // before the list frees its stores.
  If not assigned(fSceneData) then exit;
  // The list takes an item out before freeing it, so a store freed by
  // ClearScene or RemoveDataStore is no longer found here.
  If fSceneData.IndexOf(aDataStore) < 0 then exit;

  // A frame may be recording or executing from this store's pipelines and
  // buffers.
  FinishFramesInFlight;

  For TM in GetToolManagers do
  Begin
    If assigned(aDataStore.fObjects) then
      For I := 0 to aDataStore.fObjects.Count - 1 do
        TM.ForgetObject(aDataStore.fObjects.Items[I]);
    // Its commands must not find a later store at the same address.
    TM.StoreGone(aDataStore);
  End;

  UnregisterStoreObjects(aDataStore);

  // As ClearScene does for every store: off every renderer, then ClearData,
  // which also deactivates the objects - TvgBaseObject.Destroy requires it -
  // before freeing them.
  If assigned(fRendererList) then
    For I := 0 to fRendererList.Count - 1 do
      If assigned(fRendererList.Items[I]) then
        aDataStore.DisConnectDataFromSceneandRenderer(fRendererList.Items[I]);

  aDataStore.ClearData;
  aDataStore.Active := False;
  ForgetEditStore(aDataStore);

  fSceneData.Extract(aDataStore);   // out of the owning list, not freed

  NotifyDataChanged(nil);
  Result := True;
end;

Procedure TvgScene.NotifyDataChanged(aDataStore: TvgObjectStore);
  Var I  : Integer;
      RE : TvgBaseRenderEngine;
begin
  If assigned(fRendererList) then
    For I := 0 to fRendererList.Count - 1 do
    Begin
      RE := fRendererList.Items[I];
      If not assigned(RE) then Continue;

      // An offscreen target re-blits its last image unless its frames are
      // flagged; a data edit is invisible without this.
      RE.FlagRebuildALLFrames;
      If RE.Active and (fUpdateDepth = 0) then
        RE.TriggerWindowRepaint;
    End;

  If fUpdateDepth > 0 then
  Begin
    // Once for the lot, at EndUpdate.
    If not fUpdatePending then
      fUpdateStore := aDataStore
    else If fUpdateStore <> aDataStore then
      fUpdateStore := nil;
    fUpdatePending := True;
    exit;
  End;

  If assigned(fOnDataChanged) then
    fOnDataChanged(Self, aDataStore);
end;

Procedure TvgScene.BeginUpdate;
begin
  Inc(fUpdateDepth);
end;

Procedure TvgScene.EndUpdate;
  Var Store : TvgObjectStore;
begin
  If fUpdateDepth <= 0 then exit;
  Dec(fUpdateDepth);
  If (fUpdateDepth > 0) or not fUpdatePending then exit;

  fUpdatePending := False;
  Store          := fUpdateStore;
  fUpdateStore   := nil;
  // A store removed meanwhile is not passed on.
  If assigned(Store) and (fSceneData.IndexOf(Store) < 0) then
    Store := nil;
  NotifyDataChanged(Store);
end;

Procedure TvgScene.RegisterObject(aObject: TvgObject);
begin
  If assigned(aObject) and assigned(fLiveObjects) then
    fLiveObjects.AddOrSetValue(Pointer(aObject), aObject);
end;

Procedure TvgScene.UnregisterObject(aObject: TvgObject);
begin
  If assigned(aObject) and assigned(fLiveObjects) then
    fLiveObjects.Remove(Pointer(aObject));
end;

Procedure TvgScene.RegisterStoreObjects(aDataStore: TvgObjectStore);
  Var I : Integer;
begin
  If not assigned(aDataStore.fObjects) then exit;
  For I := 0 to aDataStore.fObjects.Count - 1 do
    RegisterObject(aDataStore.fObjects.Items[I]);
end;

Procedure TvgScene.UnregisterStoreObjects(aDataStore: TvgObjectStore);
  Var I : Integer;
begin
  If not assigned(aDataStore.fObjects) then exit;
  For I := 0 to aDataStore.fObjects.Count - 1 do
    UnregisterObject(aDataStore.fObjects.Items[I]);
end;

Function TvgScene.IsLiveObject(aObject: Pointer): Boolean;
begin
  Result := assigned(aObject) and assigned(fLiveObjects) and
            fLiveObjects.ContainsKey(aObject);
end;

Procedure TvgScene.ForgetEditStore(aDataStore: TvgObjectStore);
  Var K : TvgEditLayerKind;
begin
  For K := Low(TvgEditLayerKind) to High(TvgEditLayerKind) do
    If fEditStores[K] = aDataStore then
      fEditStores[K] := nil;

  If fPreviewStore = aDataStore then
  Begin
    fPreviewStore := nil;
    fPreviewObj   := nil;
  End;
end;

Function TvgScene.EnsurePreview: Boolean;
begin
  Result := False;
  If csDestroying in ComponentState then exit;

  If not assigned(fPreviewStore) then
  Begin
    If not (fSceneState in [SS_READY, SS_LOADING]) then exit;

    fPreviewStore := TvgObjectStore.Create(nil);   // the scene owns it once added
    fPreviewStore.SetupVertexAttributes([vdtPosition, vdtColor]);
    fPreviewStore.SetIndexType(itUInt32);
    fPreviewStore.Topology     := LINE_LIST;
    fPreviewStore.BaseVertName := fEditShaderPrefix + 'Preview';
    fPreviewStore.BaseFragName := fEditShaderPrefix + 'Preview';
    fPreviewStore.LineWidth    := fEditLineWidth;
    fPreviewStore.DefaultColor := fEditPreviewColor;
    fPreviewStore.InDataBounds := False;
    fPreviewStore.DepthTest    := False;    // over what it outlines

    If not AddDataStoreLive(fPreviewStore) then
    Begin
      FreeAndNil(fPreviewStore);
      exit;
    End;
  End;

  // One object, refilled in place, so a rubber band redrawn on every mouse
  // move leaves no tombstones behind.
  If not assigned(fPreviewObj) then
    fPreviewObj := fPreviewStore.AddObject(False);

  Result := True;
end;

Procedure TvgScene.ShowPreview(const aPoints: array of TpvVector3D; aClosed: Boolean);
begin
  If Length(aPoints) < 2 then
  Begin
    ClearPreview;
    exit;
  End;
  If aClosed and (Length(aPoints) < 3) then
    aClosed := False;

  If not EnsurePreview then exit;
  fPreviewStore.RefillPolyline(fPreviewObj, aPoints, aClosed);
end;

Procedure TvgScene.ShowPreviewSegments(const aSegments: array of TpvVector3D);
begin
  If Length(aSegments) < 2 then
  Begin
    ClearPreview;
    exit;
  End;

  If not EnsurePreview then exit;
  fPreviewStore.RefillSegments(fPreviewObj, aSegments);
end;

Procedure TvgScene.ClearPreview;
begin
  If csDestroying in ComponentState then exit;
  If not (assigned(fPreviewStore) and assigned(fPreviewObj)) then exit;
  If fPreviewObj.VertexCount = 0 then exit;

  fPreviewObj.Reset;
  NotifyDataChanged(fPreviewStore);
end;

Function TvgScene.GetEditStore(aKind: TvgEditLayerKind): TvgObjectStore;
  Const
    NAMES : array[TvgEditLayerKind] of String = ('Points', 'Lines', 'Triangles');
    TOPOS : array[TvgEditLayerKind] of TvgPrimitiveTopology = (POINT_LIST, LINE_LIST, TRIANGLE_LIST);
begin
  Result := fEditStores[aKind];
  If assigned(Result) then exit;

  If not (fSceneState in [SS_READY, SS_LOADING]) then exit;

  Result := TvgObjectStore.Create(nil);   // the scene owns it once added
  Result.SetupVertexAttributes([vdtPosition, vdtColor]);
  Result.SetupInstanceAttributes([idtObjID]);
  If aKind <> elkPoints then
    Result.SetIndexType(itUInt32)
  else
    Result.SetIndexType(itNONE);
  Result.Topology     := TOPOS[aKind];
  Result.BaseVertName := fEditShaderPrefix + NAMES[aKind];
  Result.BaseFragName := fEditShaderPrefix + NAMES[aKind];
  Result.LineWidth    := fEditLineWidth;
  Result.PointSize    := fEditPointSize;
  Result.DefaultColor := fEditColor;

  If not AddDataStoreLive(Result) then
  Begin
    Result.Free;
    Result := nil;
    exit;
  End;

  fEditStores[aKind] := Result;
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
        // Note: do NOT activate here � ActivateGraphicPipeLines does that
        // Note: do NOT set ObjStr.Active := True here � it may already be active
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
  TM   : TvgToolManager;
begin
  If NOT (fSceneState = SS_READY) then exit;

  // Cleared unconditionally (unlike fSceneData below): a scene with lights
  // but no mesh data must not carry them over into the next Load_Begin.
  If assigned(fLights) then
     fLights.Clear;

  CustomAssert(Assigned(fSceneData), 'Scene Data List NOT assigned',self);
  if fSceneData.Count = 0 then Exit;

  //A renderer recording on its own thread may be drawing these stores.
  FinishFramesInFlight;

  SetActiveState(False);

  // Selection, a tool's preview, its history: all name the stores.
  For TM in GetToolManagers do
     TM.SceneCleared;

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
  FillChar(fEditStores, SizeOf(fEditStores), 0);
  fPreviewStore := nil;
  fPreviewObj   := nil;

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

procedure TvgScene.ConnectRenderEngine(aRenderEngine: TvgBaseRenderEngine);
begin
  inherited;

  // The base refuses an engine already linked to another scene, so only take
  // it if the link was really made.  Scene and BaseScene then agree however
  // the engine was connected: through Scene, BaseScene, or the design-time
  // auto-link when both sit on one form.
  If  (aRenderEngine is TvgRenderEngine) and (aRenderEngine.BaseScene=self) and
      (TvgRenderEngine(aRenderEngine).fScene=nil) then
      TvgRenderEngine(aRenderEngine).fScene:= self;
end;

constructor TvgScene.Create(AOwner: TComponent);
begin
  inherited;

  fSceneData             := TObjectList<TvgObjectStore>.Create;
  fSceneData.OwnsObjects := True;
  //important

  fCameras   := TvgCameraManager.Create;
  fLights    := TList<TvgLight>.Create;

  fLiveObjects := TDictionary<Pointer, TvgObject>.Create;

  fEditColor        := TpvVector4.Create(1, 1, 0, 1);    // yellow
  fEditLineWidth    := 1.0;
  fEditPointSize    := 5.0;
  fEditShaderPrefix := 'Edit';
  fEditPreviewColor := TpvVector4.Create(1, 1, 1, 1);    // white

end;

destructor TvgScene.Destroy;
  Var TM : TvgToolManager;
begin
  SetActiveState(False);   //disables the nodes

  // Whatever the tool managers hold of this scene goes with it, loaded or
  // not (ClearScene below only runs on a loaded one).
  For TM in GetToolManagers do
    TM.SceneCleared;

  ClearScene;  //clears the scene

  if assigned(fSceneData) then
     FreeAndNil(fSceneData);

  // The stores are gone, whichever way they went (ClearScene only runs on a
  // loaded scene).  A tool manager told of this scene's end afterwards -
  // TComponent sends the notices after this destructor - may still ask for
  // the preview to be cleared.
  FillChar(fEditStores, SizeOf(fEditStores), 0);
  fPreviewStore := nil;
  fPreviewObj   := nil;

  If assigned(fCameras) then
     FreeAndNil(fCameras);

  If assigned(fLights) then
     FreeAndNil(fLights);

  // Last: freeing fSceneData above frees objects, which leave this list.
  If assigned(fLiveObjects) then
     FreeAndNil(fLiveObjects);

  If assigned(fToolManagers) then
     FreeAndNil(fToolManagers);

  inherited;
end;

procedure TvgScene.SetWorldOrigin(const Value: TpvVector3D);
var
  HasData : Boolean;
begin
  if (Value.x = fWorldOrigin.x) and
     (Value.y = fWorldOrigin.y) and
     (Value.z = fWorldOrigin.z) then
    Exit;

  // Vertex data is stored relative to the origin, so moving the origin
  // would move everything already loaded.  Same set-before-loading rule as
  // vgSetAxisConvention.
  HasData := Assigned(fSceneData) and (fSceneData.Count > 0);
  CustomAssert(not HasData, 'TvgScene.WorldOrigin cannot change while the scene holds object stores: ' +
                            'their vertices are relative to the current origin.  Set it before ' +
                            'adding data, or clear the scene first.', Self);
  if HasData then
    Exit;

  fWorldOrigin := Value;
end;

function TvgScene.GetWorldOriginX: Double;
begin
  Result := fWorldOrigin.x;
end;

function TvgScene.GetWorldOriginY: Double;
begin
  Result := fWorldOrigin.y;
end;

function TvgScene.GetWorldOriginZ: Double;
begin
  Result := fWorldOrigin.z;
end;

procedure TvgScene.SetWorldOriginX(const Value: Double);
begin
  SetWorldOrigin(TpvVector3D.Create(Value, fWorldOrigin.y, fWorldOrigin.z));
end;

procedure TvgScene.SetWorldOriginY(const Value: Double);
begin
  SetWorldOrigin(TpvVector3D.Create(fWorldOrigin.x, Value, fWorldOrigin.z));
end;

procedure TvgScene.SetWorldOriginZ(const Value: Double);
begin
  SetWorldOrigin(TpvVector3D.Create(fWorldOrigin.x, fWorldOrigin.y, Value));
end;

function TvgScene.WorldToLocal(const aWorld: TpvVector3D): TpvVector3D;
begin
  Result := aWorld - fWorldOrigin;
end;

function TvgScene.LocalToWorld(const aLocal: TpvVector3D): TpvVector3D;
begin
  Result := aLocal + fWorldOrigin;
end;

Function TvgScene.GetDataBounds(out aBox: TvgAABB; aVisibleOnly: Boolean): Boolean;
  Var I, J    : Integer;
      Store   : TvgObjectStore;
      Obj     : TvgObject;
begin
  aBox.Reset;
  Result := False;

  If not assigned(fSceneData) then exit;     //nil during the scene's destroy

  For I:=0 to fSceneData.Count-1 do
  Begin
    Store := fSceneData.Items[I];
    If not assigned(Store) then Continue;
    If not assigned(Store.fObjects) then Continue;
    If not Store.fInDataBounds then Continue;    // helpers, not data

    For J:=0 to Store.fObjects.Count-1 do
    Begin
      Obj := Store.fObjects.Items[J];
      If not assigned(Obj) then Continue;

      // Per object, not per store: a store reports itself visible when ANY of
      // its objects is, so filtering at store level would drag hidden objects
      // back into the box.
      If aVisibleOnly and (not Obj.VisibleON) then Continue;

      // cmNever means the application has said its bounds cannot be trusted -
      // typically geometry a compute shader owns.  Including them would zoom
      // to a box built from whatever the CPU last happened to write.  Such an
      // object can still take part by supplying bounds through
      // SetObjectBounds, which switches it to cmManual.
      If Store.GetObjectCullMode(Obj.ObjIndex) = cmNever then Continue;

      // An object with no bounds yet returns an empty box, and growing by an
      // empty box is a no-op - so it contributes nothing rather than dragging
      // the union onto the local origin.
      aBox.GrowAABB( Store.GetObjectWorldBounds(Obj.ObjIndex) );
    End;
  End;

  Result := aBox.Valid;
end;

Function TvgScene.GetDataBounds(out aMin, aMax: TpvVector3D; aVisibleOnly: Boolean): Boolean;
  Var Box : TvgAABB;
begin
  Result := GetDataBounds(Box, aVisibleOnly);
  If not Result then exit;

  // The union happened in local float32, where the stores' boxes live.  Only
  // now, on two corners, does it become double and absolute - so a survey
  // coordinate is never held in a float32 that cannot carry it.
  aMin := LocalToWorld(TpvVector3D.Create(Box.Min.x, Box.Min.y, Box.Min.z));
  aMax := LocalToWorld(TpvVector3D.Create(Box.Max.x, Box.Max.y, Box.Max.z));
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

procedure TvgScene.DisConnectRenderEngine(aRenderEngine: TvgBaseRenderEngine);
begin
  inherited;

  If  (aRenderEngine is TvgRenderEngine) and (TvgRenderEngine(aRenderEngine).fScene=self) then
      TvgRenderEngine(aRenderEngine).fScene:= nil;
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

Procedure TvgScene.AttachToolManager(aManager: TvgToolManager);
begin
  If not assigned(aManager) or (csDestroying in ComponentState) then exit;
  If not assigned(fToolManagers) then
    fToolManagers := TList<TvgToolManager>.Create;
  If fToolManagers.IndexOf(aManager) < 0 then
    fToolManagers.Add(aManager);
end;

Procedure TvgScene.DetachToolManager(aManager: TvgToolManager);
begin
  If assigned(fToolManagers) then
    fToolManagers.Remove(aManager);
end;

Function TvgScene.GetToolManagers: TArray<TvgToolManager>;
  Var L  : TList<TvgToolManager>;
      TM : TvgToolManager;
begin
  L := TList<TvgToolManager>.Create;
  try
    TM := GetToolManager;
    If assigned(TM) then
      L.Add(TM);
    If assigned(fToolManagers) then
      For TM in fToolManagers do
        If L.IndexOf(TM) < 0 then
          L.Add(TM);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function TvgScene.GetToolManager: TvgToolManager;
begin
 If assigned(fLinker) and
    assigned(fLinker.ToolManager) and
    (fLinker.ToolManager is TvgToolManager) then
    Result := TvgToolManager(fLinker.ToolManager)
 else
    Result := nil;

end;

procedure TvgScene.Notification(AComponent: TComponent; Operation: TOperation);
  Var R:TvgBaseRenderEngine;
begin
  inherited Notification(AComponent, Operation);
  If aComponent=self then exit;

  Case Operation of
     opInsert : Begin
                  If aComponent=self then exit;

                  If NotificationTestON and Not (csDesigning in ComponentState) then exit;     //don't mess with links at runtime

                  If (aComponent is TvgRenderEngine) and (Not assigned(TvgRenderEngine(aComponent).Scene)) then
                     ConnectRenderEngine(TvgBaseRenderEngine(aComponent)) ;

                End;
     opRemove : Begin

                  If (aComponent is TvgRenderEngine) and (TvgRenderEngine(aComponent).fScene=self)  then
                  Begin
                    R:= TvgBaseRenderEngine(aComponent);

                    DisConnectDataFromRenderer(R);
                    DisConnectRenderEngine(R);
                  End;

                end;
  End;

end;

Procedure TvgScene.PrepareFrameGlobalData(aTarget : IvgGlobalDataTarget; aFrameIndex : TvkUint32);

var
  Cam       : TvgCamera;
  Aspect    : Single;
  GPULights : TArray<TvgLightGPUData>;
  I         : Integer;
begin
  // No camera means no cull volume.  PrepareGlobalAndSceneDescriptors has
  // already invalidated the previous one, so leaving now draws everything -
  // which is the only safe answer when we cannot say what is in view.
  if not Assigned(fCameras) then exit;

  Cam := fCameras.GetActiveCamera;
  if not Assigned(Cam) then exit;

  // Ask this renderer for its own current aspect ratio.
  // Every renderer calling PrepareFrameGlobalData gets its own value here,
  // so a scene shared across a 16:9 window and a 4:3 window is handled
  // correctly with no coordination between renderers required.
  Aspect := aTarget.GetViewportAspect;

  // Build a VP matrix correct for this renderer's viewport.
  // FAspectRatio on the camera is NEVER written � it remains the camera's
  // "design" aspect (used for tools, ray-casting, frustum culling etc.)
  // Each renderer gets its own freshly-computed projection every frame.
  //
  // The vertices are relative to WorldOrigin, so the matrix is too: it maps
  // local coordinates to clip space, with the origin added in double here
  // on the CPU.  The GPU never sees a survey-sized number.
  aTarget.SetViewProjectMatrix(aFrameIndex,  Cam.GetViewProjectionMatrixForAspect(Aspect, fWorldOrigin));

  // Cull volume for this renderer, from the SAME aspect the VP above uses.
  // Building it from any other aspect - the camera's own stored FAspectRatio,
  // say - would cull geometry that this renderer is about to draw on screen.
  // Same origin too: the planes come out in local coordinates, which is the
  // space the data stores build their float32 bounds in.
  aTarget.SetFrustumPlanes( Cam.GetFrustumPlanesForAspect(Aspect, fWorldOrigin) );

  // Lights are already world-space (see TvgLight); narrowed to GPU layout
  // and made WorldOrigin-relative here, same as the VP matrix and vertex
  // data, so the shader never sees a survey-sized number.
  if Assigned(fLights) then
  begin
    SetLength(GPULights, fLights.Count);
    for I := 0 to fLights.Count - 1 do
      GPULights[I] := TvgLightToGPUData(fLights[I], fWorldOrigin);
  end;
  aTarget.SetLightData(aFrameIndex, GPULights);

  // Future global data � each also receives the correct per-renderer context:
  // aTarget.SetTimeData(aFrameIndex, fTimeAccumulator);
end;

procedure TvgScene.ReConnectRenderEngines;
begin
  inherited;

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

Function TvgSceneLoaderStorer.PrepareTextureDescriptor(aDescriptorName: String): TvgDescriptorArray_Texture;
   Var R:TvgResourceUse;
      DI:TvgDescriptorItem;
      S: String;
begin
  Result := nil;

  If not assigned(fCurrentObjectStore) then exit;
  If (aDescriptorName='') then exit;
  If not assigned(fCurrentObjectStore.ObjectStoreRes) then exit;

  If not (RU_OBJECTSTORE in fCurrentObjectStore.ResourceUse) then
  Begin
     R:=  fCurrentObjectStore.ResourceUse;
     Include(R, RU_OBJECTSTORE);
     fCurrentObjectStore.ResourceUse:=R;
  End;

  DI := fCurrentObjectStore.ObjectStoreRes.Descriptors.Add;
  If not assigned(DI) then exit;

  S := TvgDescriptorArray_Texture.GetPropertyName;
  DI.DescriptorName := S;

  If not assigned(DI.Descriptor) then exit;
  DI.Name := aDescriptorName;

  If not (DI.Descriptor is TvgDescriptorArray_Texture) then exit;

  Result              := TvgDescriptorArray_Texture(DI.Descriptor);
  Result.Name         := aDescriptorName;
  Result.ResourceType := RT_GROUPTEX;
  Result.FrameCount   := 1;
  Result.BindingCount := 1;
end;

Procedure TvgSceneLoaderStorer.AddDescriptor_Texture(aDescriptorName : String;
                                                     aImageFileName  : String);
   Var Tex:TvgDescriptorArray_Texture;
begin
  If (aImageFileName='') then exit;

  Tex := PrepareTextureDescriptor(aDescriptorName);
  If assigned(Tex) then
    Tex.AddSharedTexture(aDescriptorName, aImageFileName);
end;

Procedure TvgSceneLoaderStorer.AddDescriptor_Texture(aDescriptorName : String;
                                                     aImageStream    : TStream);
   Var Tex:TvgDescriptorArray_Texture;
begin
  If not assigned(aImageStream) then exit;

  Tex := PrepareTextureDescriptor(aDescriptorName);
  If assigned(Tex) then
    Tex.AddSharedTexture(aDescriptorName, aImageStream);
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
  fActionMode     := TAM_OBJECT_SELECT;
  fOrbitButton    := vgmbLeft;
  fPanButton      := vgmbMiddle;
  fDollyButton    := vgmbRight;
  fSelectedObject := nil;
  fDragPlaneAxis  := 0;
  fDragStartHitPt := TpvVector3.Create(0, 0, 0);
  fDragPlaneValid := False;
  fSelection      := TList<TvgObject>.Create;
  fPickRadius     := 6;
  fProjections    := TObjectDictionary<TvgObject, TvgObjectProjection>.Create([doOwnsValues]);
end;

destructor TvgToolManager.Destroy;
begin
  fSelectedObject := nil;   // not owned
  FreeAndNil(fSelection);
  FreeAndNil(fProjections);
  if Assigned(fScene) then
    fScene.DetachToolManager(Self);
  fScene          := nil;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
//  Private setters
// ---------------------------------------------------------------------------

procedure TvgToolManager.BeginInput;
begin
  Inc(fInputDepth);
  If (fInputDepth = 1) and Assigned(fScene) and not (csDestroying in fScene.ComponentState) then
  Begin
    fInputScene := fScene;
    fInputScene.BeginUpdate;
  End;
end;

procedure TvgToolManager.EndInput;
begin
  If fInputDepth <= 0 then exit;
  Dec(fInputDepth);
  If fInputDepth = 0 then
    ReleaseInputScene;
end;

procedure TvgToolManager.ReleaseInputScene;
  Var S : TvgScene;
begin
  S           := fInputScene;
  fInputScene := nil;
  If Assigned(S) and not (csDestroying in S.ComponentState) then
    S.EndUpdate;
end;

procedure TvgToolManager.SetScene(const Value: TvgScene);
begin
  If fScene = Value then exit;
  // An input event still open on the old scene: its edits are drawn now,
  // while it is still there to draw them.
  If fInputScene = fScene then
    ReleaseInputScene;
  // Whatever was held of the old scene - the selection, and in a descendant
  // a tool's preview and its history - goes while it can still be cleared
  // there.
  SceneCleared;
  ClearProjections;
  If Assigned(fScene) then
  Begin
    fScene.DetachToolManager(Self);
    fScene.RemoveFreeNotification(Self);
  End;
  fScene := Value;
  If Assigned(fScene) then
  Begin
    fScene.FreeNotification(Self);
    fScene.AttachToolManager(Self);
  End;

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
  If Assigned(fRenderer) then
    fRenderer.RemoveFreeNotification(Self);
  fRenderer := Value;
  If Assigned(fRenderer) then
    fRenderer.FreeNotification(Self);
  ClearSelection;
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
var
  Had : Boolean;
begin
  Had := Assigned(fSelectedObject) or (Assigned(fSelection) and (fSelection.Count > 0));
  fSelectedObject := nil;
  if Assigned(fSelection) then
    fSelection.Clear;
  fDragPlaneValid := False;
  if Had then
    DoSelectionChanged;
end;

procedure TvgToolManager.ForgetObject(aObject: TvgObject);
var
  Was : Boolean;
begin
  if not Assigned(aObject) then Exit;

  Was := Assigned(fSelection) and (fSelection.Remove(aObject) >= 0);
  if fSelectedObject = aObject then
  begin
    fSelectedObject := nil;
    if Assigned(fSelection) and (fSelection.Count > 0) then
      fSelectedObject := fSelection.Last;
    fDragPlaneValid := False;
    Was := True;
  end;

  if fMouseOverPtr = aObject then fMouseOverPtr := nil;
  if fMouseDownPtr = aObject then fMouseDownPtr := nil;
  if fMouseUpPtr   = aObject then fMouseUpPtr   := nil;

  if Assigned(fProjections) and fProjections.ContainsKey(aObject) then
  begin
    Dec(fProjectedVertices, Length(fProjections[aObject].Local));
    fProjections.Remove(aObject);
  end;

  if Was then
    DoSelectionChanged;
end;

procedure TvgToolManager.StoreGone(aStore: TvgObjectStore);
begin
  // Nothing held per store here; see TvgEditToolManager.
end;

procedure TvgToolManager.SceneCleared;
begin
  ClearSelection;
end;

procedure TvgToolManager.ViewChanged(aPlane: Boolean);
begin
  // Nothing drawn in screen terms here; see TvgEditToolManager.
end;

// ---------------------------------------------------------------------------
//  Selection
// ---------------------------------------------------------------------------

procedure TvgToolManager.DoSelectionChanged;
begin
  if csDestroying in ComponentState then Exit;
  if Assigned(fOnSelectionChanged) then
    fOnSelectionChanged(Self);
end;

function TvgToolManager.GetSelectionCount: Integer;
begin
  Result := 0;
  if Assigned(fSelection) then
    Result := fSelection.Count;
end;

function TvgToolManager.GetSelection(Index: Integer): TvgObject;
begin
  Result := fSelection[Index];
end;

function TvgToolManager.IsSelected(aObject: TvgObject): Boolean;
begin
  Result := Assigned(aObject) and Assigned(fSelection) and (fSelection.IndexOf(aObject) >= 0);
end;

function TvgToolManager.SelectObject(aObject: TvgObject; aAdd: Boolean): Boolean;
begin
  Result := False;
  if not Assigned(aObject) or not Assigned(fScene) or not Assigned(fSelection) then Exit;
  if not fScene.IsLiveObject(aObject) then Exit;
  if not aObject.Selectable then Exit;

  if not aAdd then
    fSelection.Clear;
  if fSelection.IndexOf(aObject) < 0 then
    fSelection.Add(aObject);
  fSelectedObject := aObject;
  Result := True;
  DoSelectionChanged;
end;

procedure TvgToolManager.SelectObjects(const aObjects: array of TvgObject; aAdd: Boolean);
var
  I : Integer;
  O : TvgObject;
begin
  if not Assigned(fScene) or not Assigned(fSelection) then Exit;

  if not aAdd then
  begin
    fSelection.Clear;
    fSelectedObject := nil;
  end;

  for I := 0 to High(aObjects) do
  begin
    O := aObjects[I];
    if Assigned(O) and fScene.IsLiveObject(O) and O.Selectable and
       (fSelection.IndexOf(O) < 0) then
    begin
      fSelection.Add(O);
      fSelectedObject := O;
    end;
  end;
  DoSelectionChanged;
end;

procedure TvgToolManager.DeselectObject(aObject: TvgObject);
begin
  if not IsSelected(aObject) then Exit;
  fSelection.Remove(aObject);
  if fSelectedObject = aObject then
  begin
    fSelectedObject := nil;
    if fSelection.Count > 0 then
      fSelectedObject := fSelection.Last;
  end;
  DoSelectionChanged;
end;

procedure TvgToolManager.ToggleSelected(aObject: TvgObject);
begin
  if IsSelected(aObject) then
    DeselectObject(aObject)
  else
    SelectObject(aObject, True);
end;

// ---------------------------------------------------------------------------
//  Picking on the CPU
// ---------------------------------------------------------------------------

function TvgScreenProjector.Project(const aLocal: TpvVector3D; out aX, aY, aDepth: Double): Boolean;
var
  C : TpvVector4D;
begin
  C := VP * TpvVector4D.Create(aLocal.x, aLocal.y, aLocal.z, 1.0);
  // w is the eye depth for a perspective camera, 1 for an orthographic one.
  Result := C.w > 1e-12;
  if not Result then
  begin
    aX := 0; aY := 0; aDepth := 0;
    Exit;
  end;
  aX     := (C.x / C.w + 1.0) * 0.5 * W;
  aY     := (C.y / C.w + 1.0) * 0.5 * H;
  aDepth := Fwd.Dot(aLocal) + DepthC;
end;

// Distance from P to segment AB on screen; aT is where along AB (0..1).
function vgScreenSegDist(PX, PY, AX, AY, BX, BY: Double; out aT: Double): Double;
var
  DX, DY, L2 : Double;
begin
  DX := BX - AX;
  DY := BY - AY;
  L2 := DX * DX + DY * DY;
  if L2 <= 0 then
    aT := 0
  else
    aT := EnsureRange(((PX - AX) * DX + (PY - AY) * DY) / L2, 0.0, 1.0);
  Result := Hypot(PX - (AX + aT * DX), PY - (AY + aT * DY));
end;

// Barycentric weights of P in triangle ABC on screen; False outside it (or
// for a triangle seen edge-on).
function vgScreenInTriangle(PX, PY, AX, AY, BX, BY, CX, CY: Double;
                            out aU, aV, aW: Double): Boolean;
var
  D : Double;
begin
  D := (BY - CY) * (AX - CX) + (CX - BX) * (AY - CY);
  Result := Abs(D) > 1e-12;
  if not Result then Exit;
  aU := ((BY - CY) * (PX - CX) + (CX - BX) * (PY - CY)) / D;
  aV := ((CY - AY) * (PX - CX) + (AX - CX) * (PY - CY)) / D;
  aW := 1.0 - aU - aV;
  Result := (aU >= 0) and (aV >= 0) and (aW >= 0);
end;

// Whether segment AB crosses or lies in the rectangle (Liang-Barsky).
function vgScreenSegInRect(AX, AY, BX, BY, X1, Y1, X2, Y2: Double): Boolean;
var
  T0, T1 : Double;

  function Clip(P, Q: Double): Boolean;
  var
    R : Double;
  begin
    Result := True;
    if P = 0 then
      Result := Q >= 0
    else
    begin
      R := Q / P;
      if P < 0 then
      begin
        if R > T1 then Result := False
        else if R > T0 then T0 := R;
      end
      else
      begin
        if R < T0 then Result := False
        else if R < T1 then T1 := R;
      end;
    end;
  end;

begin
  T0 := 0;
  T1 := 1;
  Result := Clip(-(BX - AX), AX - X1) and Clip(BX - AX, X2 - AX) and
            Clip(-(BY - AY), AY - Y1) and Clip(BY - AY, Y2 - AY);
end;

function TvgToolManager.MakeProjector(out aP: TvgScreenProjector): Boolean;
var
  Cam  : TvgCamera;
  W, H : Integer;
begin
  Result := False;
  aP.W := 0; aP.H := 0;
  if not Assigned(fScene) then Exit;
  Cam := GetActiveCamera;
  if not Assigned(Cam) then Exit;
  if not GetViewportSize(W, H) or (W <= 0) or (H <= 0) then Exit;

  aP.W      := W;
  aP.H      := H;
  aP.VP     := Cam.GetViewProjectionMatrixForAspect(W / H, fScene.WorldOrigin);
  aP.Fwd    := Cam.ForwardVector.Normalize;
  aP.DepthC := aP.Fwd.Dot(fScene.WorldOrigin - Cam.Position);
  Result := True;
end;

function TvgToolManager.WorldToScreen(const aWorld: TpvVector3D; out aX, aY: Double): Boolean;
var
  P : TvgScreenProjector;
  D : Double;
begin
  aX := 0; aY := 0;
  Result := MakeProjector(P) and P.Project(aWorld - fScene.WorldOrigin, aX, aY, D);
end;

function TvgToolManager.PointOnPlane(X, Y: Integer; const aNormal, aAnchor: TpvVector3D;
                                     out aWorld: TpvVector3D): Boolean;
begin
  Result := ScreenRayHitsPlane(X, Y, aNormal, aAnchor, aWorld);
end;

function TvgToolManager.PixelSizeAt(const aWorld: TpvVector3D): Double;
var
  Cam    : TvgCamera;
  SX, SY : Double;
  A, B   : TpvVector3D;
  IX, IY : Integer;
begin
  Result := 0;
  Cam := GetActiveCamera;
  if not Assigned(Cam) then Exit;
  if not WorldToScreen(aWorld, SX, SY) then Exit;

  // Two pixels ten apart, on the plane through aWorld facing the camera.
  IX := Round(SX);
  IY := Round(SY);
  if ScreenRayHitsPlane(IX, IY, Cam.ForwardVector, aWorld, A) and
     ScreenRayHitsPlane(IX + 10, IY, Cam.ForwardVector, aWorld, B) then
    Result := (B - A).Length / 10.0;
end;

function TvgToolManager.CanPick(aStore: TvgObjectStore; aObject: TvgObject): Boolean;
begin
  Result := Assigned(aObject) and (aObject.fObjIndex >= 0) and
            aObject.VisibleON and aObject.Selectable and
            aStore.IsVertexTypeSet(vdtPosition) and
            not aStore.IsObjectDeleted(aObject.fObjIndex) and
            (aStore.GetObjectVertexCount(aObject.fObjIndex) > 0);
end;

function TvgToolManager.ObjectScreenRect(const aP: TvgScreenProjector; aObject: TvgObject;
                                         out aX1, aY1, aX2, aY2: Double): Boolean;
var
  B       : TvgAABB;
  I       : Integer;
  C       : TpvVector3D;
  X, Y, D : Double;
begin
  // False when the box cannot rule the object out: no bounds, or a corner
  // behind the camera.
  Result := False;
  B := aObject.fDataStore.GetObjectLocalBounds(aObject.fObjIndex);
  if not B.Valid then Exit;

  for I := 0 to 7 do
  begin
    if (I and 1) = 0 then C.x := B.Min.x else C.x := B.Max.x;
    if (I and 2) = 0 then C.y := B.Min.y else C.y := B.Max.y;
    if (I and 4) = 0 then C.z := B.Min.z else C.z := B.Max.z;
    if not aP.Project(C, X, Y, D) then Exit;
    if I = 0 then
    begin
      aX1 := X; aX2 := X; aY1 := Y; aY2 := Y;
    end
    else
    begin
      aX1 := Min(aX1, X); aX2 := Max(aX2, X);
      aY1 := Min(aY1, Y); aY2 := Max(aY2, Y);
    end;
  end;
  Result := True;
end;

const
  // Vertices the projection cache may hold, all objects together (about 40
  // bytes each).  Past it the cache starts again.
  VG_MAX_PROJECTED_VERTICES = 8 * 1024 * 1024;

procedure TvgToolManager.ClearProjections;
begin
  if Assigned(fProjections) then
    fProjections.Clear;
  fProjectedVertices := 0;
end;

function TvgToolManager.ProjectObject(const aP: TvgScreenProjector; aObject: TvgObject): TvgObjectProjection;
var
  I, N  : Integer;
  Store : TvgObjectStore;
begin
  Store := aObject.fDataStore;

  // Still good: same object in the same place, nothing in its store changed,
  // same view.  The address alone could be a new object's, hence the rest.
  if fProjections.TryGetValue(aObject, Result) then
  begin
    if (Result.Store = Store) and (Result.ObjIndex = aObject.fObjIndex) and
       (Result.Stamp = Store.ChangeStamp) and (Result.W = aP.W) and (Result.H = aP.H) and
       CompareMem(@Result.VP, @aP.VP, SizeOf(aP.VP)) then
      Exit;
    Dec(fProjectedVertices, Length(Result.Local));
    fProjections.Remove(aObject);
  end;

  Result := TvgObjectProjection.Create;
  try
    Result.Store    := Store;
    Result.ObjIndex := aObject.fObjIndex;
    Result.Stamp    := Store.ChangeStamp;
    Result.VP       := aP.VP;
    Result.W        := aP.W;
    Result.H        := aP.H;
    Result.Local    := Store.GetObjectVertexPositions(aObject.fObjIndex);

    N := Length(Result.Local);
    SetLength(Result.SX, N);
    SetLength(Result.SY, N);
    SetLength(Result.SD, N);
    SetLength(Result.OK, N);
    for I := 0 to N - 1 do
      Result.OK[I] := aP.Project(TpvVector3D.Create(Result.Local[I].x, Result.Local[I].y,
                                                    Result.Local[I].z),
                                 Result.SX[I], Result.SY[I], Result.SD[I]);
  except
    Result.Free;
    raise;
  end;

  if fProjectedVertices + N > VG_MAX_PROJECTED_VERTICES then
    ClearProjections;
  fProjections.Add(aObject, Result);
  Inc(fProjectedVertices, N);
end;

function TvgToolManager.ProjectionPrims(aProj: TvgObjectProjection; aObject: TvgObject): Integer;
begin
  if not aProj.HasPrims then
  begin
    aProj.PrimSize := aObject.GetPrimitives(aProj.Prims);
    aProj.HasPrims := True;
  end;
  Result := aProj.PrimSize;
end;

function TvgToolManager.PickAt(X, Y: Integer; out aHit: TvgPickHit): Boolean;
var
  P                  : TvgScreenProjector;
  I, J, K, Q, N      : Integer;
  Store              : TvgObjectStore;
  Obj                : TvgObject;
  SX, SY, SD         : TArray<Double>;
  OK                 : TArray<Boolean>;
  Prim               : TArray<Integer>;
  R, PX, PY          : Double;
  X1, Y1, X2, Y2     : Double;
  Dist, Depth, T     : Double;
  U, V, W            : Double;
  A, B, C            : Integer;
  BestDist, BestDepth: Double;
  BestWorld          : TpvVector3D;
  Pts                : array[0..2] of TpvVector3D;
  Proj               : TvgObjectProjection;
  Loc                : TArray<TpvVector3>;

  function Better(aDist, aDepth: Double): Boolean;
  begin
    Result := (aHit.Obj = nil) or (aDist < BestDist - 1e-9) or
              ((Abs(aDist - BestDist) <= 1e-9) and (aDepth < BestDepth));
  end;

  procedure Take(aDist, aDepth: Double; const aWorld: TpvVector3D);
  begin
    aHit.Obj  := Obj;
    BestDist  := aDist;
    BestDepth := aDepth;
    BestWorld := aWorld;
  end;

  function LocalOf(aVertex: Integer): TpvVector3D;
  begin
    Result := TpvVector3D.Create(Loc[aVertex].x, Loc[aVertex].y, Loc[aVertex].z);
  end;

begin
  Result          := False;
  aHit.Obj        := nil;
  aHit.Pixels     := 0;
  aHit.Vertex     := -1;
  aHit.World      := TpvVector3D.Create(0, 0, 0);
  BestDist        := 0;
  BestDepth       := 0;
  if not MakeProjector(P) then Exit;

  R  := Max(fPickRadius, 0);
  PX := X;
  PY := Y;

  for I := 0 to fScene.SceneData.Count - 1 do
  begin
    Store := fScene.SceneData.Items[I];
    if not Assigned(Store) or (Store = fScene.fPreviewStore) then
      Continue;
    // A store the scene has hidden - a layer switched off.  A scene not
    // running on a device yet has every store inactive.
    if fScene.Active and not Store.Active then
      Continue;

    for J := 0 to Store.fObjects.Count - 1 do
    begin
      Obj := Store.fObjects.Items[J];
      if not CanPick(Store, Obj) then Continue;

      // Most objects are nowhere near the cursor: their bounds say so.
      if ObjectScreenRect(P, Obj, X1, Y1, X2, Y2) and
         ((PX < X1 - R) or (PX > X2 + R) or (PY < Y1 - R) or (PY > Y2 + R)) then
        Continue;

      Proj := ProjectObject(P, Obj);
      SX   := Proj.SX;
      SY   := Proj.SY;
      SD   := Proj.SD;
      OK   := Proj.OK;
      Loc  := Proj.Local;
      K    := ProjectionPrims(Proj, Obj);
      Prim := Proj.Prims;
      N    := Length(Prim) div K;

      for Q := 0 to N - 1 do
        case K of
          1:
            begin
              A := Prim[Q];
              if not OK[A] then Continue;
              Dist := Hypot(PX - SX[A], PY - SY[A]);
              if (Dist <= R) and Better(Dist, SD[A]) then
                Take(Dist, SD[A], LocalOf(A));
            end;
          2:
            begin
              A := Prim[2 * Q];
              B := Prim[2 * Q + 1];
              if not (OK[A] and OK[B]) then Continue;
              Dist  := vgScreenSegDist(PX, PY, SX[A], SY[A], SX[B], SY[B], T);
              Depth := SD[A] + (SD[B] - SD[A]) * T;
              if (Dist <= R) and Better(Dist, Depth) then
              begin
                Pts[0] := LocalOf(A);
                Pts[1] := LocalOf(B);
                Take(Dist, Depth, Pts[0] + (Pts[1] - Pts[0]) * T);
              end;
            end;
          3:
            begin
              A := Prim[3 * Q];
              B := Prim[3 * Q + 1];
              C := Prim[3 * Q + 2];
              if not (OK[A] and OK[B] and OK[C]) then Continue;
              if not vgScreenInTriangle(PX, PY, SX[A], SY[A], SX[B], SY[B],
                                        SX[C], SY[C], U, V, W) then
                Continue;
              // A surface only wins when no point or line is in range.
              Depth := U * SD[A] + V * SD[B] + W * SD[C];
              if Better(R, Depth) then
              begin
                Pts[0] := LocalOf(A);
                Pts[1] := LocalOf(B);
                Pts[2] := LocalOf(C);
                Take(R, Depth, Pts[0] * U + Pts[1] * V + Pts[2] * W);
              end;
            end;
        end;
    end;
  end;

  Result := Assigned(aHit.Obj);
  if not Result then Exit;

  aHit.Pixels := BestDist;
  aHit.World  := fScene.LocalToWorld(BestWorld);
  aHit.Vertex := NearestVertexOnScreen(aHit.Obj, X, Y, Dist);
end;

function TvgToolManager.PickObject(X, Y: Integer): TvgObject;
var
  H : TvgPickHit;
begin
  if PickAt(X, Y, H) then
    Result := H.Obj
  else
    Result := nil;
end;

function TvgToolManager.NearestVertexOnScreen(aObject: TvgObject; X, Y: Integer;
                                              out aPixels: Double): Integer;
var
  P          : TvgScreenProjector;
  Proj       : TvgObjectProjection;
  SX, SY     : TArray<Double>;
  OK         : TArray<Boolean>;
  I          : Integer;
  D          : Double;
begin
  Result  := -1;
  aPixels := 0;
  if not Assigned(aObject) or not Assigned(aObject.fDataStore) or (aObject.fObjIndex < 0) then Exit;
  if not MakeProjector(P) then Exit;

  Proj := ProjectObject(P, aObject);
  SX   := Proj.SX;
  SY   := Proj.SY;
  OK   := Proj.OK;
  for I := 0 to High(OK) do
    if OK[I] then
    begin
      D := Hypot(X - SX[I], Y - SY[I]);
      if (Result < 0) or (D < aPixels) then
      begin
        Result  := I;
        aPixels := D;
      end;
    end;
end;

function TvgToolManager.ObjectsInRect(X1, Y1, X2, Y2: Integer): TArray<TvgObject>;
var
  P                  : TvgScreenProjector;
  I, J, K, Q, N, M   : Integer;
  Store              : TvgObjectStore;
  Obj                : TvgObject;
  Proj               : TvgObjectProjection;
  SX, SY             : TArray<Double>;
  OK                 : TArray<Boolean>;
  Prim               : TArray<Integer>;
  L, T, Rt, Bm       : Double;
  BX1, BY1, BX2, BY2 : Double;
  Hit                : Boolean;
  A, B               : Integer;
  Res                : TList<TvgObject>;
begin
  Result := nil;
  if not MakeProjector(P) then Exit;

  L  := Min(X1, X2);  Rt := Max(X1, X2);
  T  := Min(Y1, Y2);  Bm := Max(Y1, Y2);

  Res := TList<TvgObject>.Create;
  try
    for I := 0 to fScene.SceneData.Count - 1 do
    begin
      Store := fScene.SceneData.Items[I];
      if not Assigned(Store) or (Store = fScene.fPreviewStore) then
        Continue;
      if fScene.Active and not Store.Active then
        Continue;

      for J := 0 to Store.fObjects.Count - 1 do
      begin
        Obj := Store.fObjects.Items[J];
        if not CanPick(Store, Obj) then Continue;
        if ObjectScreenRect(P, Obj, BX1, BY1, BX2, BY2) and
           ((BX2 < L) or (BX1 > Rt) or (BY2 < T) or (BY1 > Bm)) then
          Continue;

        Proj := ProjectObject(P, Obj);
        SX   := Proj.SX;
        SY   := Proj.SY;
        OK   := Proj.OK;

        // A vertex in the box...
        Hit := False;
        for M := 0 to High(OK) do
          if OK[M] and (SX[M] >= L) and (SX[M] <= Rt) and (SY[M] >= T) and (SY[M] <= Bm) then
          begin
            Hit := True;
            Break;
          end;

        // ...or an edge through it.
        if not Hit then
        begin
          K    := ProjectionPrims(Proj, Obj);
          Prim := Proj.Prims;
          if K > 1 then
          begin
            N := Length(Prim) div K;
            for Q := 0 to N - 1 do
            begin
              for M := 0 to K - 1 do
              begin
                A := Prim[K * Q + M];
                B := Prim[K * Q + ((M + 1) mod K)];
                if OK[A] and OK[B] and
                   vgScreenSegInRect(SX[A], SY[A], SX[B], SY[B], L, T, Rt, Bm) then
                begin
                  Hit := True;
                  Break;
                end;
                if K = 2 then Break;   // a segment has one edge
              end;
              if Hit then Break;
            end;
          end;
        end;

        if Hit then
          Res.Add(Obj);
      end;
    end;
    Result := Res.ToArray;
  finally
    Res.Free;
  end;
end;

// ---------------------------------------------------------------------------
//  Zoom to all data
// ---------------------------------------------------------------------------

function TvgToolManager.GetViewportAspectRatio: Double;
  Var W, H : Integer;
begin
  If GetViewportSize(W, H) and (H > 0) then
    Result := W / H
  else
  If Assigned(fRenderer) then
    // No surface yet - during start-up, say.  The renderer reads the swap
    // chain instead, which may already be sized.
    Result := fRenderer.GetViewportAspect
  else
    Result := 1.0;   // square: the same safe default GetViewportAspect uses

  If Result <= 0 then
    Result := 1.0;
end;

function TvgToolManager.ZoomAll(aMargin: Double): Boolean;
  Var Cam       : TvgCamera;
      BMin,BMax : TpvVector3D;
begin
  Result := False;

  Cam := GetActiveCamera;
  If not Assigned(Cam) then exit;
  If not Assigned(fScene) then exit;

  // World coordinates in double - the space the camera works in.
  If not fScene.GetDataBounds(BMin, BMax) then exit;

  Result := Cam.ZoomAll(BMin, BMax, GetViewportAspectRatio, aMargin);
end;

function TvgToolManager.ZoomAllLookDown(aMargin: Double): Boolean;
  Var Cam       : TvgCamera;
      BMin,BMax : TpvVector3D;
begin
  Result := False;

  Cam := GetActiveCamera;
  If not Assigned(Cam) then exit;
  If not Assigned(fScene) then exit;

  If not fScene.GetDataBounds(BMin, BMax) then exit;

  Result := Cam.ZoomAllLookDown(BMin, BMax, GetViewportAspectRatio, aMargin);
end;

function TvgToolManager.ZoomAllPlanView(aMargin: Double): Boolean;
  Var Cam       : TvgCamera;
      BMin,BMax : TpvVector3D;
begin
  Result := False;

  Cam := GetActiveCamera;
  If not Assigned(Cam) then exit;
  If not Assigned(fScene) then exit;

  If not fScene.GetDataBounds(BMin, BMax) then exit;

  // Switch the projection BEFORE fitting: TvgCamera.FitToBounds reads
  // ProjectionType to decide whether it is solving for a distance or for an
  // orthographic extent, so doing it the other way round would fit the camera
  // as a perspective one and then change the projection out from under it.
  Cam.ProjectionType := ptOrthographic;

  Result := Cam.ZoomAllLookDown(BMin, BMax, GetViewportAspectRatio, aMargin);
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

function TvgToolManager.GetDragPlaneNormal: TpvVector3D;
begin
  // DragPlaneAxis follows TvgWorldPlane, so "horizontal" is the ground plane
  // in whichever world axis convention is active.
  case fDragPlaneAxis of
    1 : Result := vgPlaneNormal(wpFront);     // vertical, facing the default camera
    2 : Result := vgPlaneNormal(wpSide);      // vertical, facing +X
  else
    Result := vgPlaneNormal(wpHorizontal);    // ground plane
  end;
end;

function TvgToolManager.GetDragPlaneAnchor: TpvVector3D;
begin
  // Was the world origin (0,0,0).  With survey coordinates that is a plane
  // at elevation 0 through the grid origin, possibly hundreds of kilometres
  // from the data; the scene's WorldOrigin sits in the middle of it.
  if Assigned(fScene) then
    Result := fScene.WorldOrigin
  else
    Result := TpvVector3D.Create(0, 0, 0);
end;

function TvgToolManager.ScreenRayHitsPlane(aX, aY: Integer;
                                            const aPlaneNormal: TpvVector3D;
                                            const aPlanePoint:  TpvVector3D;
                                            out   aHitPoint:    TpvVector3D): Boolean;
  Var
    Cam   : TvgCamera;
    Ray   : TpvVector3D;
    Orig  : TpvVector3D;
    W, H  : Integer;
    Denom : Double;
    T     : Double;
    Diff  : TpvVector3D;
begin
  Result    := False;
  aHitPoint := TpvVector3D.Create(0, 0, 0);

  Cam := GetActiveCamera;
  If not Assigned(Cam) then exit;
  If not GetViewportSize(W, H) then exit;
  If (W <= 0) or (H <= 0) then exit;

  // The ray's own origin, not Cam.Position: for an orthographic camera every
  // pixel's ray starts somewhere different.
  Ray := Cam.ScreenToWorldRay(aX, aY, W, H, Orig);

  // Ray�plane intersection:  t = dot(planePoint - rayOrigin, planeNormal)
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

  // On an axis-aligned plane the hit's own coordinate is the plane's, exactly:
  // computed, it carries rounding (1e-17 off a plane at 0), and points meant
  // to be at one elevation would then differ in their last bits.
  If Abs(aPlaneNormal.x) = 1 then aHitPoint.x := aPlanePoint.x;
  If Abs(aPlaneNormal.y) = 1 then aHitPoint.y := aPlanePoint.y;
  If Abs(aPlaneNormal.z) = 1 then aHitPoint.z := aPlanePoint.z;
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
  // Camera yaw uses the opposite sign from screen-space X: dragging right
  // should rotate the view toward the right, as in the usual orbit control.
  Cam.Orbit(-aDeltaX, aDeltaY, True);
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

procedure TvgToolManager.DoPickObject(aFrameIndex: TvkUint32; Shift: TShiftState; X, Y: Integer);
  Var
    Obj       : TvgObject;
    PlaneNorm : TpvVector3D;
    W, H      : Integer;

begin
  If not Assigned(fLinker)           then exit;
  If not Assigned(fRenderer)         then exit;
  If not Assigned(fScene)            then exit;

  // A captured drag can report positions outside the viewport; there is no
  // object-ID pixel to read there.
  If not GetViewportSize(W, H)       then exit;
  If (X < 0) or (Y < 0) or (X >= W) or (Y >= H) then exit;

  // Query the object-ID storage image at this pixel
  Obj := fRenderer.GetObjectAtLocation(aFrameIndex, Shift, X, Y);

  If Assigned(Obj) then
  Begin

    If Assigned(Obj) and Obj.Selectable then
    Begin
      SelectObject(Obj);

      // Pre-compute the world-space hit point on the drag plane so that
      // DoDragObject can track deltas without per-frame camera queries.
      PlaneNorm       := GetDragPlaneNormal;
      fDragPlaneValid := ScreenRayHitsPlane(X, Y, PlaneNorm,
                                             GetDragPlaneAnchor,
                                             fDragStartHitPt);

      If Assigned(fOnObjectPicked) then
        fOnObjectPicked(Self, fSelectedObject);
    End;
  End
  else
  Begin
    // Clicked on background � deselect
    ClearSelection;
  End;
end;

procedure TvgToolManager.DoDragObject(X, Y: Integer);
  Var
    PlaneNorm : TpvVector3D;
    HitPoint  : TpvVector3D;
    NewPos    : TpvVector3D;
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
    PlaneNorm : TpvVector3D;
    HitPoint  : TpvVector3D;
begin
  PlaneNorm := GetDragPlaneNormal;
  If ScreenRayHitsPlane(X, Y, PlaneNorm, GetDragPlaneAnchor, HitPoint) then
  Begin
    If Assigned(fOnObjectAddReq) then
      fOnObjectAddReq(Self, HitPoint);
  End;
end;

// ---------------------------------------------------------------------------
//  Virtual mouse handler overrides
// ---------------------------------------------------------------------------

function TvgToolManager.ToolMouseDown(aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer): Boolean;
begin
  Result := False;
end;

function TvgToolManager.ToolMouseMove(Shift: TShiftState; X, Y: Integer): Boolean;
begin
  Result := False;
end;

function TvgToolManager.ToolMouseUp(aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer): Boolean;
begin
  Result := False;
end;

function TvgToolManager.ToolMouseWheel(Shift: TShiftState; WheelDelta: Integer): Boolean;
begin
  Result := False;
end;

procedure TvgToolManager.DoMouseDown(aButton: TvgMouseButton; Shift: TShiftState; X, Y: Integer);
begin

  fMouseState.ButtonON   := True;
  fMouseState.ButtonDown := aButton;
  If fMouseState.CaptureMouse then
  Begin
    fMouseState.MouseCaptured:=True;


  End;

  // A descendant's tool first; what it leaves falls through to the camera.
  If ToolMouseDown(aButton, Shift, X, Y) then
    exit;




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
            ; // Camera-gesture sub-modes - handled in DoMouseMove
        end;
      End;
    end;
  end;
end;

procedure TvgToolManager.DoMouseMove(Shift: TShiftState; X, Y: Integer);
  Var
    dX, dY : Single;
begin

  // A descendant's tool sees every move, button or not, so it can follow
  // the cursor between clicks.
  If ToolMouseMove(Shift, X, Y) then
    exit;

  // Mouse movement without a held button is not a camera gesture.  The base
  // manager tracks buttons across down/move/up events, which also works when
  // the platform's Shift state omits a button during captured movement.
  If fMouseButtons = [] then exit;

  // Scale pixel deltas by global sensitivity
  dX := (X - fLastMouseX) * fMouseSensitivity;
  dY := (Y - fLastMouseY) * fMouseSensitivity;

  If (dX = 0.0) and (dY = 0.0) then exit;

  DoCameraDrag(Shift, dX, dY, X, Y);
end;

procedure TvgToolManager.DoCameraDrag(Shift: TShiftState; aDeltaX, aDeltaY: Single; X, Y: Integer);
begin
  case fToolMode of

    TMM_CAMERA:
      DispatchCameraGesture(Shift, aDeltaX, aDeltaY);

    TMM_OBJECT_EDIT:
    begin
      case fActionMode of

        TAM_CAMERA_ORBIT,
        TAM_CAMERA_PAN,
        TAM_CAMERA_DOLLY:
          // Camera gesture sub-modes used while staying in OBJECT_EDIT
          DispatchCameraGesture(Shift, aDeltaX, aDeltaY);

        TAM_OBJECT_SELECT:
          // Selection is click-only; allow camera pan with middle button
          If fPanButton in fMouseButtons then
            DoCameraPan(aDeltaX, aDeltaY);

        TAM_OBJECT_MOVE:
        Begin
          If (fOrbitButton in fMouseButtons) and Assigned(fSelectedObject) then
            // Left drag on a selected object - move it
            DoDragObject(X, Y)
          else
            // Otherwise treat as camera gesture (pan/dolly with other buttons)
            DispatchCameraGesture(Shift, aDeltaX, aDeltaY);
        End;

        TAM_OBJECT_ADD:
          // Allow camera panning while hovering in add mode
          If fPanButton in fMouseButtons then
            DoCameraPan(aDeltaX, aDeltaY);

      end;  // case fActionMode
    end;    // TMM_OBJECT_EDIT

  end;  // case fToolMode
end;

procedure TvgToolManager.DoMouseUp(aButton: TvgMouseButton;
                                    Shift: TShiftState; X, Y: Integer);
begin
  If ToolMouseUp(aButton, Shift, X, Y) then
    exit;

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
  // A descendant's tool first (Add Line sets the camera plane's depth with
  // it); otherwise the wheel zooms, whatever the mode.
  If ToolMouseWheel(Shift, WheelDelta) then
    exit;

  DoCameraZoom(WheelDelta);
  ViewChanged;
end;



{ TvgRenderEngine }

procedure TvgRenderEngine.VaildateGlobalResources;

//called in Create
 var     DI   : TvgDescriptorItem;
           DA  :TvgDescriptorArray;
         FC : Integer;
         GI : Integer;
   NextFree : Integer;

    // Freeing the item frees its descriptor too.  The engine is inactive
    // here (every caller deactivates first), so nothing holds it.
    Procedure RemoveGlobal(const aName: String);
      Var RI : TvgDescriptorItem;
    Begin
      RI := fGlobalRes.GetDescriptorItem(aName);
      If not assigned(RI) then exit;
      If assigned(fObjectIDBuffer) and (RI.Descriptor = fObjectIDBuffer) then
        fObjectIDBuffer := nil;
      If assigned(fObjectIDImage) and (RI.Descriptor = fObjectIDImage) then
        fObjectIDImage := nil;
      RI.Free;
    End;

    Procedure SetUpForStorageImage;
       var     SI  : TvgDescriptorArray_StorageImage;
               SID : TvgDescriptor_Data_StorageImage;

    Begin
    //tidy up
        DI := fGlobalRes.GetDescriptorItem(GlobalObjectIDDescriptorBuf);
        if Assigned(DI) and assigned(fObjectIDBuffer) and (fObjectIDBuffer.ClassType = DI.ClassType) then
           FreeAndNil(fObjectIDBuffer);   //will free from TCollection

        DI := fGlobalRes.GetDescriptorItem(GlobalObjectIDDescriptorImg);
        If not assigned(DI) then
          DI               := fGlobalRes.Descriptors.Add ;

        if Assigned(DI) and
           (DI.Descriptor is TvgDescriptorArray_SB_2UI)
           and assigned(fObjectIDBuffer) then
        Begin
          fObjectIDBuffer.free;
          fObjectIDBuffer:=nil;
        End;

        If assigned(DI) then
        Begin
          DI.Name          := GlobalObjectIDDescriptorImg;
          If assigned(fLinker) then
              DI.Device    := fLinker.ScreenDevice;

          DI.DescriptorName := TvgDescriptorArray_StorageImage.GetPropertyName;
          DA:= DI.Descriptor;

          If assigned(DA) then
          Begin

            DA.ResourceType := RT_STORAGEIMAGE;
            DA.DataFlow     := [DF_DOWN, DF_SAMPLING];
            DA.SetStageFlags(TVkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT));
            DA.FrameCount   := FC;
            DA.BindingMode  := vgdbmSingle;

            If DA is TvgDescriptorArray_StorageImage then
            Begin
              SI := TvgDescriptorArray_StorageImage(DA);
              SI.ImageFormat := R32G32_UINT;

              SID := TvgDescriptor_Data_StorageImage.Create;

           //   image width  set to swap chain size with WindowSync ON
              SID.WindowSync  := True;
              SID.PixelSample := True;
              SID.PixRadius   := psr_1x1;

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

        DI := fGlobalRes.GetDescriptorItem(GlobalObjectIDDescriptorImg);
        if Assigned(DI) and
           (DI.Descriptor is TvgDescriptorArray_StorageImage) then
          fObjectIDImage := TvgDescriptorArray_StorageImage(DI.Descriptor);

    End;

    Procedure SetUpForStorageBuffer;
      Var SB:TvgDescriptorArray_SB_2UI;
          DD:TvgDescriptorData_SB_2UI;
           I:Integer;


          GP : TvgGraphicPipeline;

    Begin

    //tidy up
        DI := fGlobalRes.GetDescriptorItem(GlobalObjectIDDescriptorImg);
        if Assigned(DI) and assigned(fObjectIDImage) and  (fObjectIDImage.ClassType = DI.ClassType) then
           FreeAndNil(fObjectIDImage);

        DI := fGlobalRes.GetDescriptorItem(GlobalObjectIDDescriptorBuf);
        If not assigned(DI) then
          DI               := fGlobalRes.Descriptors.Add ;


        If assigned(DI) then
        Begin
          DI.Name          := GlobalObjectIDDescriptorBuf;
          If assigned(fLinker) then
              DI.Device    := fLinker.ScreenDevice;

          DI.DescriptorName := TvgDescriptorArray_SB_2UI.GetPropertyName;
          DA:= DI.Descriptor;

          If assigned(DA) then
          Begin

            DA.ResourceType := RT_SELECTVEC2;
            DA.DataFlow     := [ DF_DOWN, DF_SAMPLING];
            DA.SetStageFlags(TVkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT));
            DA.FrameCount   := FC;
            DA.BindingMode  := vgdbmSingle;

            If DA is TvgDescriptorArray_SB_2UI then
            Begin

              SB := TvgDescriptorArray_SB_2UI(DA);

              DD := SB.AddBuffer;
              If assigned(DD) then
              Begin
                DD.WindowSync := True;   //important to track render window size
                DD.SamplingON := True;
              //  DD.SamplingDimension :=  esdGrid2D;   not needed

              End;


            End;
          end;
        End;

        DI := fGlobalRes.GetDescriptorItem(GlobalObjectIDDescriptorBuf);
        if Assigned(DI) and
           (DI.Descriptor is TvgDescriptorArray_SB_2UI) then
        Begin
          fObjectIDBuffer := TvgDescriptorArray_SB_2UI(DI.Descriptor);
        end;



    End;


begin
  CustomAssert(assigned(fGlobalRes),'Global Resource not assigned',Self);

  fObjectIDImage :=nil;
  fObjectIDBuffer:=nil;
  fLightsBuffer  :=nil;

  //simple Model/View/Proj Matrix
  //Should to the initial Model/View/Project multiplation in Dpouble precision in CPU
  If assigned(fLinker) then
  Begin
    FC:= fLinker.FrameCount  ;
  end else
    FC:=MaxFramesInFlight;


  ValidateViewProjectionDescriptor;
  ValidateLightsDescriptor;


  If SelectON  then     //all OK
  Begin

    Case fFlags.SelectMode of
       smImageBuffer  :  SetUpForStorageImage;
       smStorageBuffer:  SetUpForStorageBuffer;
       smCustom: Begin
       End;
    End;

  end;

  // Only the current mode's object-ID target stays; with selection off,
  // neither.  Both share GlobalBindingObjectID, so a leftover from the last
  // mode would be a duplicate binding.  (The "tidy up" in the SetUp
  // procedures compares a descriptor's class with an item's, so it never
  // removed anything.)  smCustom is left as the caller set it up.
  If fFlags.SelectMode <> smCustom then
  Begin
    If not (SelectON and (fFlags.SelectMode = smStorageBuffer)) then
      RemoveGlobal(GlobalObjectIDDescriptorBuf);
    If not (SelectON and (fFlags.SelectMode = smImageBuffer)) then
      RemoveGlobal(GlobalObjectIDDescriptorImg);
  End;

  // Fixed bindings, whatever SelectMode is: 0 view-projection, 1 object-ID
  // target, 2 lights.  A binding is only stamped (from the item's Index)
  // when an item is made, and items come and go as SelectMode changes; the
  // layout, the writes and the generated shaders all read Binding, so it is
  // set here every time.  Anything else takes the next free one from
  // GlobalBindingFirstFree.
  NextFree := GlobalBindingFirstFree;
  For GI := 0 to fGlobalRes.Descriptors.Count - 1 do
  Begin
    DI := fGlobalRes.Descriptors.Items[GI];
    If not (assigned(DI) and assigned(DI.Descriptor)) then Continue;

    If SameText(DI.Name, GlobalViewProjectDescriptor) then
      DI.Descriptor.Binding := GlobalBindingViewProject
    else If SameText(DI.Name, GlobalObjectIDDescriptorBuf) or
            SameText(DI.Name, GlobalObjectIDDescriptorImg) then
      DI.Descriptor.Binding := GlobalBindingObjectID
    else If SameText(DI.Name, GlobalLightsDescriptor) then
      DI.Descriptor.Binding := GlobalBindingLights
    else
    Begin
      DI.Descriptor.Binding := NextFree;
      Inc(NextFree);
    End;
  End;

end;

procedure TvgRenderEngine.ConfigureGraphicPipelineFromRenderPass( GP: TvgGraphicPipeline);
   Var SHS : TvgShaderSpecialisationItem;
       PCI:TvgPushConstantItem;
       PCUI: TvgPushConstant_2UI;
       V:   TvgVector2I;
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
      SHS.Name       := SC_USE_OBJECTID;
      SHS.SpecType   := TS_BOOLEAN;
      SHS.SpecTValue := 'TRUE';
      SHS.ConstantID := CI_USE_OBJECTID;
    end;

    SHS := GP.FragmentS.SpecialConst.add;  //Fragment
    If assigned(SHS) then
    Begin
      SHS.Name       := SC_USE_OBJECTID;
      SHS.SpecType   := TS_BOOLEAN;
      SHS.SpecTValue := 'TRUE';
      SHS.ConstantID := CI_USE_OBJECTID;
    end;

    If fFlags.SelectMode = smStorageBuffer then
    Begin
      PCI:=GP.PushConstantCol.add;
      PCI.Name := 'inScreenSize';

      If assigned(PCI) then
      Begin
        PCI.PushConstantName := TvgPushConstant_2UI.GetPropertyName;

        If assigned(PCI.PushConstant) and (PCI.PushConstant is  TvgPushConstant_2UI) then
        Begin
          PCUI := TvgPushConstant_2UI(PCI.PushConstant);
          PCUI.ShaderFlags := [SS_FRAGMENT_BIT];
        End;
      End;
    End;
  end;

  if UsesDoubleViewProjection then
  begin
    SHS := GP.VertexS.SpecialConst.add;    //vertex only
    If assigned(SHS) then
    Begin
      SHS.Name       := SC_USE_DOUBLE;
      SHS.SpecType   := TS_BOOLEAN;
      SHS.SpecTValue := 'TRUE';
      SHS.ConstantID := CI_USE_DOUBLE;
    end;
  end;


end;

function TvgRenderEngine.GetObjectAtLocation(aFrameIndex: TvkUint32; Shift: TShiftState; X, Y: Integer): TvgObject;
var
  Candidate: TObject;
  SampleX, SampleY: Integer;
      ObjectAddress: UInt64;


  Procedure HandleImageLookup;
  Var
      DD: TvgDescriptor_Data_StorageImage;
      Pixel: TvgPixelData;

  Begin
       CustomAssert(Assigned(fObjectIDImage), 'Object Select image NOT created', self);

       if Assigned(fLinker) and (fLinker.RenderTarget = RT_FRAME) then
       begin
         SampleX := (X * Integer(fLinker.FrameResolution)) + (Integer(fLinker.FrameResolution) div 2);
         SampleY := (Y * Integer(fLinker.FrameResolution)) + (Integer(fLinker.FrameResolution) div 2);
       end else
       Begin
         SampleX := X;
         SampleY := Y ;
       End;

       DD := fObjectIDImage.StorageImageData[0];    //MUST be zero
       if not Assigned(DD) or
          not DD.GetPixelData(aFrameIndex, Shift, SampleX, SampleY, Pixel) then
         Exit;

       ObjectAddress := Combine32BitTo64Bit(UInt64(Pixel.R32G32_UINT.G), UInt64(Pixel.R32G32_UINT.R));   //low/high  CHECK
  End;

  Procedure HandleBufferLookup;
    Var DD: TvgDescriptorData_SB_2UI;
        aData:Pointer;
        aDataSize:TvkUint32;
        Vec2 : TvgVector2I;

  Begin
       CustomAssert(Assigned(fObjectIDBuffer), 'Object Select BUFFER NOT created', self);

       if Assigned(fLinker) and (fLinker.RenderTarget = RT_FRAME) then
       begin
         SampleX := (X * Integer(fLinker.FrameResolution)) + (Integer(fLinker.FrameResolution) div 2);
         SampleY := (Y * Integer(fLinker.FrameResolution)) + (Integer(fLinker.FrameResolution) div 2);
       end else
       Begin
         SampleX := X;
         SampleY := Y ;
       End;

       DD := TvgDescriptorData_SB_2UI(fObjectIDBuffer.SB_Descriptor[0]);    //MUST be zero
       if Assigned(DD) and
          DD.GetElementData2D(aFrameIndex,  SampleX, SampleY, aData, aDataSize) and
          (aDataSize=SizeOf(TvgVector2I)) then
       Begin
          Vec2:= TvgVector2I(aData^);
          ObjectAddress := Combine32BitTo64Bit(UInt64(Vec2.Y), UInt64(Vec2.X));   //low/high  CHECK
       End;

  End;

  Procedure HandleCustomLookup;
  Begin


  End;
begin
  Result := Nil;

  If State = vgcsInactive then exit;
  if not SelectON then exit;
  If not assigned(fScene) or (fScene.GetObjectCount=0) then exit;

  ObjectAddress:=0;

 // fix image/buffer

  case self.FFlags.SelectMode of
      smImageBuffer   : HandleImageLookup;      //use an image buffer to manage Object IDs
      smStorageBuffer : HandleBufferLookup;    /// use a storage Buffer to manage Object IDs
      smCustom        : HandleCustomLookup;            //use a costom method


  end;


 if ObjectAddress = 0 then
   Exit;

 Candidate := TObject(Pointer(NativeUInt(ObjectAddress)));

 // The address was written when that frame was drawn; the object may have
 // been deleted since, and its memory reused.  The scene's live-object list
 // answers without touching the memory, where IsValidObjectOfClass would
 // have to read it.
 if fScene.IsLiveObject(Pointer(Candidate)) then
   Result := TvgObject(Candidate);
end;

procedure TvgRenderEngine.Notification(AComponent: TComponent;  Operation: TOperation);
begin
    inherited Notification(AComponent, Operation);     //important

    Case Operation of
       opInsert : Begin
                    If aComponent=self then exit;
                    If NotificationTestON and Not (csDesigning in ComponentState) then exit;     //don't mess with links at runtime

                    If (aComponent is TvgScene) and (fScene=Nil) then
                      SetScene(TvgScene(aComponent) );
                  End;

       opRemove : Begin

                    If (aComponent is TvgScene) and (fScene=aComponent) then
                      SetScene(nil );
                  end;

    End;
end;

function TvgRenderEngine.SetDisabled: Boolean;
begin
  Result := Inherited;


end;

function TvgRenderEngine.SetEnabled: Boolean;
begin
  // The device exists by now, so this is the first point at which
  // UsesDoubleViewProjection can see whether shaderFloat64 is available.
  // Re-type the descriptor before the global resources go live and before
  // any pipeline generates a shader against it.
  ValidateViewProjectionDescriptor;

  Result := Inherited;
end;

function TvgRenderEngine.UsesDoubleViewProjection: Boolean;
var
  Dev : TvgScreenRenderDevice;
  PD  : TvgPhysicalDevice;
begin
  Result := Inherited;          // ShaderUseDouble
  if not Result then
    Exit;

  if not Assigned(fLinker) then
    Exit;
  Dev := fLinker.ScreenDevice;
  if not Assigned(Dev) or not Assigned(Dev.Features) or not Dev.Features.Active then
    Exit;
  PD := GetPhysicalDevice;
  if not Assigned(PD) or not Assigned(PD.VulkanPhysicalDevice) then
    Exit;

  // Requested on the device AND supported by the GPU - the same AND that
  // TvgFeatures applies when it builds the device's feature records.
  Result := Dev.Features.ShaderFloat64 and
            (PD.VulkanPhysicalDevice.Features.shaderFloat64 <> VK_FALSE);
end;

function TvgRenderEngine.GetHUDCamera: TvgCamera;
begin
  Result := nil;
  if Assigned(fScene) and Assigned(fScene.Cameras) then
    Result := fScene.Cameras.GetActiveCamera;
end;

procedure TvgRenderEngine.ValidateViewProjectionDescriptor;
var
  DI       : TvgDescriptorItem;
  DA       : TvgDescriptorArray;
  WantType : TvgDescriptorArrayType;
begin
  if not Assigned(fGlobalRes) then
    Exit;

  if UsesDoubleViewProjection then
    WantType := TvgDescriptorArray_UBO_4x4MatrixD
  else
    WantType := TvgDescriptorArray_UBO_4x4MatrixS;

  DI := fGlobalRes.GetDescriptorItem(GlobalViewProjectDescriptor);
  if Assigned(DI) and Assigned(DI.Descriptor) and
     (DI.Descriptor.ClassType = WantType) then
    Exit;

  if not Assigned(DI) then
  begin
    DI := fGlobalRes.Descriptors.Add;
    if not Assigned(DI) then
      Exit;
    DI.Name := GlobalViewProjectDescriptor;
  end;

  // Setting DescriptorName replaces the item's descriptor array with one of
  // the new type.
  DI.DescriptorName := WantType.GetPropertyName;

  If assigned(fLinker) then
    DI.Device := fLinker.ScreenDevice;

  DA := DI.Descriptor;
  if not Assigned(DA) then
    Exit;

  DA.DescriptorItem := DI;
  DA.ResourceType   := RT_VIEWPROJECTMAT;
  If assigned(fLinker) then
    DA.FrameCount := fLinker.FrameCount
  else
    DA.FrameCount := MaxFramesInFlight;

  // AddMatrix fills every frame slot with the identity.
  if DA is TvgDescriptorArray_UBO_4x4MatrixD then
    TvgDescriptorArray_UBO_4x4MatrixD(DA).AddMatrix
  else if DA is TvgDescriptorArray_UBO_4x4MatrixS then
    TvgDescriptorArray_UBO_4x4MatrixS(DA).AddMatrix;

  DA.SetUploadFlags;
end;

procedure TvgRenderEngine.ValidateLightsDescriptor;
var
  DI : TvgDescriptorItem;
  DA : TvgDescriptorArray;
  SB : TvgDescriptorArray_SB_Light;
  DD : TvgDescriptorData_SB_Light;
begin
  if not Assigned(fGlobalRes) then
    Exit;

  DI := fGlobalRes.GetDescriptorItem(GlobalLightsDescriptor);
  if Assigned(DI) and Assigned(DI.Descriptor) and
     (DI.Descriptor is TvgDescriptorArray_SB_Light) then
  begin
    fLightsBuffer := TvgDescriptorArray_SB_Light(DI.Descriptor);
    Exit;
  end;

  if not Assigned(DI) then
  begin
    DI := fGlobalRes.Descriptors.Add;
    if not Assigned(DI) then
      Exit;
    DI.Name := GlobalLightsDescriptor;
  end;

  DI.DescriptorName := TvgDescriptorArray_SB_Light.GetPropertyName;

  If assigned(fLinker) then
    DI.Device := fLinker.ScreenDevice;

  DA := DI.Descriptor;
  if not Assigned(DA) then
    Exit;

  DA.DescriptorItem := DI;
  DA.ResourceType   := RT_LIGHTSBUFFER;
  DA.DataFlow       := [DF_UP];     // CPU -> GPU; DF_DOWN (read-back) never uploads
  DA.SetStageFlags(TVkShaderStageFlags(VK_SHADER_STAGE_FRAGMENT_BIT));
  DA.BindingMode    := vgdbmSingle;   // one buffer holding every light, not one binding per light
  If assigned(fLinker) then
    DA.FrameCount := fLinker.FrameCount
  else
    DA.FrameCount := MaxFramesInFlight;

  if DA is TvgDescriptorArray_SB_Light then
  begin
    SB := TvgDescriptorArray_SB_Light(DA);
    DD := SB.AddBuffer;
    if Assigned(DD) then
    begin
      // Fixed size: with ElementCount 0 no VkBuffer is made, so the binding
      // was never written and any shader reading it hit an unbound slot.
      DD.ElementCount := MaxGlobalLights;
      // Plain data, not a picking target: without this the default (on)
      // builds a pixel sampler for it now that ElementCount is non-zero.
      DD.SamplingON   := False;
      fLightsBuffer := SB;
    end;
  end;

  DA.SetUploadFlags;
end;

procedure TvgRenderEngine.SetScene(const Value: TvgScene);
begin
  If fScene=Value then exit;
  SetActiveState(False);

  If assigned(fScene) then
  Begin
     fScene.RemoveFreeNotification(self) ;
     fScene.DisConnectRenderEngine(Self);
  End;

  fScene := Value;

  If assigned(fScene) then
  Begin
     fScene.FreeNotification(self) ;
     fScene.ConnectRenderEngine(Self);
  End;
end;

procedure TvgRenderEngine.SetViewProjectMatrix(aFrameIndex: TvkUint32; const aMat: TpvMatrix4x4D);
var
  DI   : TvgDescriptorItem;
begin

  if not Assigned(fGlobalRes) then exit;

  DI := fGlobalRes.GetDescriptorItem(GlobalViewProjectDescriptor);

  if not Assigned(DI)            then exit;
  if not Assigned(DI.Descriptor) then exit;

  // Whichever precision ValidateViewProjectionDescriptor chose.  The mat4
  // path narrows here and nowhere earlier.
  if DI.Descriptor is TvgDescriptorArray_UBO_4x4MatrixD then
    TvgDescriptorArray_UBO_4x4MatrixD(DI.Descriptor).UpdateMatrixValues(0, aFrameIndex, 0, aMat)
  else if DI.Descriptor is TvgDescriptorArray_UBO_4x4MatrixS then
    TvgDescriptorArray_UBO_4x4MatrixS(DI.Descriptor).UpdateMatrixValues(0, aFrameIndex, 0, aMat)
  else
    exit;

  DI.Descriptor.SetUploadFlag(aFrameIndex, 0, True);

end;

procedure TvgRenderEngine.SetLightData(aFrameIndex: TvkUint32; const aLights: TArray<TvgLightGPUData>);
var
  DD : TvgDescriptor_Data_StorageBuffer<TvgLightGPUData>;
  DF : TvgDescriptor_PerFrame_StorageBuffer<TvgLightGPUData>;
  I  : Integer;
begin
  if not Assigned(fGlobalRes)   then exit;
  if not Assigned(fLightsBuffer) then exit;

  DD := fLightsBuffer.SB_Descriptor[0];
  if not Assigned(DD) then exit;

  DF := DD.StorageBufferFrameData[aFrameIndex];
  if not Assigned(DF) then exit;

  // Always exactly MaxGlobalLights entries, matching the fixed-size
  // VkBuffer: uploading more would write past it.  Live lights first, the
  // rest zeroed - LightType 0 is None - so a scene with fewer lights than
  // last frame leaves no stale entries behind.  lights.length() in GLSL is
  // the slot count, not the live count; shaders skip type-None slots.
  DF.Data.Clear;
  DF.Data.SetItemCapacity(MaxGlobalLights);
  for I := 0 to MaxGlobalLights - 1 do
    if I < Length(aLights) then
      DF.Data[I] := aLights[I]
    else
      DF.Data[I] := Default(TvgLightGPUData);

  fLightsBuffer.SetUploadFlag(aFrameIndex, 0, True);
end;





end.

