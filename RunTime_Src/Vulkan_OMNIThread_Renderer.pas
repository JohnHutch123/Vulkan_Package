unit Vulkan_OMNIThread_Renderer;

interface

uses
 // FastMM5,
  System.SysUtils,
  System.Generics.Collections,   //MUST STAY HERE
  System.Generics.Defaults,
  System.Classes,                //MUST STAY HERE
  System.Math,
  Messages,
  typinfo,
  OtlComm,
  OtlTaskControl,
  Vulkan_Components;

  const
    WM_LOG = WM_USER + 1000;

  Type

  TvgOMNIRenderer = Class(TvgRenderEngine)
  private

  protected
    FOwnerTask : IOmniTaskControl;
    FThread    : TThread;

    Procedure SetDisabled;  override;
    Procedure SetEnabled(aComp:TvgBaseComponent=nil);   override  ;

    procedure Log(const msg: string);
    procedure TaskTerminated;
    procedure ThreadTerminated(Sender: TObject);
    procedure WMLog(var msg: TOmniMessage); message WM_LOG;

  Public
    constructor Create(AOwner: TComponent); Override;
    destructor Destroy; override;



  end;


implementation

Uses   DSiWin32,
       OtlCommon,
       OtlTask,
       OtlParallel;

type
  TWorker = class(TOmniWorker)
  strict private const
    MSG_STATUS = 1;
  var
    FCalc: IOmniFuture<integer>;
  strict protected
    function Asy_DoTheCalculation(const task: IOmniTask): integer;
  public
    function Initialize: boolean; override;
  end;
  TRenderThread = class(TThread)
  strict private const
    MSG_STATUS = 1;
  strict protected
    function Asy_DoTheCalculation(const task: IOmniTask): integer;
    procedure Log(const msg: string);
  public
    procedure Execute; override;
  end;


{ TvgOMNIRenderer }

constructor TvgOMNIRenderer.Create(AOwner: TComponent);
begin
  inherited;

end;

destructor TvgOMNIRenderer.Destroy;
begin

  inherited;
end;

procedure TvgOMNIRenderer.Log(const msg: string);
begin

end;

procedure TvgOMNIRenderer.SetDisabled;
begin


end;

procedure TvgOMNIRenderer.SetEnabled(aComp: TvgBaseComponent);
begin

  FThread                 := TRenderThread.Create(true);
  FThread.OnTerminate     := ThreadTerminated;
  FThread.FreeOnTerminate := true;
  FThread.Start;

  FOwnerTask := CreateTask(TWorker.Create(), 'Renderer owner')
    .OnMessage(Self)
    .OnTerminated(TaskTerminated)
    .MsgWait // critical, this allows OTL task to process messages
    .Run;

end;

procedure TvgOMNIRenderer.TaskTerminated;
begin

end;

procedure TvgOMNIRenderer.ThreadTerminated(Sender: TObject);
begin

end;

procedure TvgOMNIRenderer.WMLog(var msg: TOmniMessage);
begin

end;

{ TWorker }

function TWorker.Asy_DoTheCalculation(const task: IOmniTask): integer;
begin

end;

function TWorker.Initialize: boolean;
begin

end;

{ TWorkerThread }

function TRenderThread.Asy_DoTheCalculation(const task: IOmniTask): integer;
begin

end;

procedure TRenderThread.Execute;
begin
  inherited;

end;

procedure TRenderThread.Log(const msg: string);
begin

end;

end.
