unit Vulkan_Assert;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type

TvgAssertLogger = class
  private
    fLock     : TCriticalSection;
    fSeen     : TDictionary<String,Boolean>;  // dedup: log each distinct failure once per run
    fFileName : String;
    procedure SetFileName(const Value: String);
  public
    constructor Create(const aFileName: String);
    destructor Destroy; override;
    procedure LogFailure(const aErrorMsg, aComponentName, aMode: String);

    Procedure SaveLogFile;

    Property FileName:String read fFileName write SetFileName;
  end;

   EvgVulkanAssertException = class(Exception);


var
  gAssertLogger   : TvgAssertLogger = nil;
  LogFilePathAndName : String = 'C:\ProgramData\Datavis\ErrorLogFile.txt';   //make sure to add the last backslash


procedure CustomAssert(Condition: Boolean;  const Message: string = 'Custom Assert'; AComponent: TComponent=nil; const LogToFile: Boolean = True);

implementation

{ TvgAssertLogger }

constructor TvgAssertLogger.Create(const aFileName: String);
begin
  inherited Create;
  fLock     := TCriticalSection.Create;
  fSeen     := TDictionary<String,Boolean>.Create;
  fFileName := aFileName;
end;

destructor TvgAssertLogger.Destroy;
begin
  FreeAndNil(fSeen);
  FreeAndNil(fLock);
  inherited;
end;

procedure TvgAssertLogger.LogFailure(const aErrorMsg, aComponentName, aMode: String);
var
  Key     : String;
  LogFile : TextFile;
begin
  Key := aComponentName + '|' + aErrorMsg;

  fLock.Enter;
  try
    // A condition that fails every frame (e.g. a permanently stuck
    // descriptor) must not turn into an unbounded log file - only the
    // first occurrence of each distinct (component, message) is written.
    if fSeen.ContainsKey(Key) then
      Exit;
    fSeen.Add(Key, True);

    try
      AssignFile(LogFile, fFileName);
      if FileExists(fFileName) then
        Append(LogFile)
      else
        Rewrite(LogFile);
      try
        WriteLn(LogFile, Format('[%s] %s (Component: %s, Mode: %s)',
                                 [DateTimeToStr(Now), aErrorMsg, aComponentName, aMode]));
      finally
        CloseFile(LogFile);
      end;
    except
      // A locked/read-only log file must never turn an assertion
      // failure into an unrelated secondary crash.
    end;
  finally
    fLock.Leave;
  end;
end;

procedure TvgAssertLogger.SaveLogFile;
  Var F:TFileStream;
begin
  If fFileName='' then exit;
  If fSeen.Count=0 then exit;

end;

procedure TvgAssertLogger.SetFileName(const Value: String);
begin
  fFileName := Value;
end;

procedure CustomAssert(Condition: Boolean; const Message: string = 'Custom Assert';
                        AComponent: TComponent = nil; const LogToFile: Boolean = True);
var
  IsDesigning : Boolean;
  IsDebugMode : Boolean;
  ErrorMsg    : String;
  CompName    : String;
  Mode        : String;
begin
  if Condition then
    Exit;   // nothing failed - never raise, never log

  IsDesigning := (AComponent <> nil) and (csDesigning in AComponent.ComponentState);
  {$IFDEF DEBUG}
  IsDebugMode := True;
  {$ELSE}
  IsDebugMode := False;
  {$ENDIF}

  if Message = '' then
    ErrorMsg := 'Assertion failed'
  else
    ErrorMsg := 'Assertion failed: ' + Message;

  if AComponent <> nil then
    CompName := AComponent.Name
  else
    CompName := '<NONE>';

  if IsDesigning then
    Mode := 'Design'
  else if IsDebugMode then
    Mode := 'Debug'
  else
    Mode := 'Release';

  if LogToFile then
  begin
    if not Assigned(gAssertLogger) then
      gAssertLogger := TvgAssertLogger.Create(LogFilePathAndName);
    gAssertLogger.LogFailure(ErrorMsg, CompName, Mode);
  end;

  // Still only *stops* execution in Debug/Design, matching the existing
  // convention that CustomAssert never crashes shipped code - it can now
  // just also leave a trace when it doesn't.
  if IsDebugMode or IsDesigning then
    raise EvgVulkanAssertException.Create(ErrorMsg);

end;

 Initialization


 finalization
  If assigned(gAssertLogger) then
   FreeAndNil(gAssertLogger);

end.


