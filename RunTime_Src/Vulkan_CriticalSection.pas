Unit Vulkan_CriticalSection ;

interface

 // {$DEFINE DEBUGCS}
uses
 {$IFDEF DEBUGCS}
  Windows,
 {$ENDIF}
  System.SysUtils,
  System.Classes,
 {$IFDEF DEBUGCS}
  System.Types,
  {$ENDIF}
  System.Generics.Collections,   //MUST STAY HERE
  System.Generics.Defaults,
  System.SyncObjs,
  System.Diagnostics,
  System.TimeSpan,
  DateUtils;


type
  TThreadInfo = record
    ThreadID: TThreadID;
    LockCount: Integer;
    LastLockTime: TDateTime;
    StackTrace: string;
  end;

  TLockAcquisitionInfo = record
    ThreadID: TThreadID;        // The ID of the thread that acquired the lock
    LockCount: Integer;         // The recursive lock count
    WaitingThreads: Integer;    // The number of threads waiting for the lock
    StackTrace: string;         // The stack trace at the time of lock acquisition
  end;

  TLockAcquiredEvent = procedure(Sender: TObject; const Info: TLockAcquisitionInfo) of object;

  // Enhanced critical section with debugging and deadlock detection
  TvgCriticalSection = class(TCriticalSection)
  private
  //  FDummy : array [0..95] of Byte;   //fixes issue of object size and  CPU cache.  Not used for anything else

    fOwnerThread: TThreadID;           // Current owner thread ID
    fLockCount: Integer;               // Recursive lock count
    fLastLockTime: TDateTime;          // Time of last successful lock
    fWaitingThreads: TList<TThreadInfo>; // List of waiting threads
    fName: string;                     // Identifier for debugging
    fTimeout: Cardinal;                // Timeout in milliseconds
    fDeadlockCheckEnabled: Boolean;    // Enable deadlock detection
    fStopwatch: TStopwatch;            // Performance timing
    fLock: TCriticalSection;           // Protects access to shared resources
    fOnLockAcquired: TLockAcquiredEvent; // Event triggered when a lock is acquired

    // Debug fields - only used when DEBUGCS is defined
    {$IFDEF DEBUGCS}
    fAcquisitionStack: string;         // Stack trace of lock acquisition
    fTotalWaitTime: Int64;             // Total time spent waiting
    fMaxWaitTime: Int64;               // Maximum single wait time
    fLockAttempts: Int64;              // Number of lock attempts
    fContentionCount: Int64;           // Number of contentions
    {$ENDIF}


    procedure RecordThreadInfo;
    function GetCurrentThreadID: TThreadID;
    procedure CheckForDeadlock;

    {$IFDEF DEBUGCS}
    function GetStackTrace: string;

    {$ENDIF}

  protected
    procedure HandleTimeout;
    procedure UpdateWaitingThreads;
    procedure RemoveWaitingThread(ThreadID: TThreadID);

  public
    constructor Create(const AName: string = ''); reintroduce;
    destructor Destroy; override;

    // Enhanced Enter method with timeout and deadlock detection
    procedure Enter;
    function TryEnter(Timeout: Cardinal = INFINITE): Boolean; virtual;
    procedure Leave;

    // Thread safety verification
    procedure AssertLocked(const Source: string = '');
    procedure AssertNotLocked(const Source: string = '');

    // Diagnostic methods
    function GetLockInfo: string;
    procedure ResetStatistics;

    // Properties
    property Name: string read fName write fName;
    property OwnerThread: TThreadID read fOwnerThread;
    property LockCount: Integer read fLockCount;
    property Timeout: Cardinal read fTimeout write fTimeout;
    property DeadlockCheckEnabled: Boolean read fDeadlockCheckEnabled write fDeadlockCheckEnabled;

    {$IFDEF DEBUGCS}
    property TotalWaitTime: Int64 read fTotalWaitTime;
    property MaxWaitTime: Int64 read fMaxWaitTime;
    property LockAttempts: Int64 read fLockAttempts;
    property ContentionCount: Int64 read fContentionCount;
    {$ENDIF}
  end;

implementation

{$IFDEF DEBUGCS}

function CaptureStackBackTrace(
  FramesToSkip: DWORD;
  FramesToCapture: DWORD;
  BackTrace: PPointer;
  BackTraceHash: PDWORD
): WORD; stdcall; external 'kernel32.dll' name 'RtlCaptureStackBackTrace';


function GetCallStack(var Stack: array of Pointer; MaxDepth: Integer): Integer;
begin
  Result := 0;
  {$IFDEF MSWINDOWS}
  // Windows-specific implementation
  Result := CaptureStackBackTrace(0, MaxDepth, @Stack[0], nil);
  {$ELSE}
  // Other platforms implementation
  // This is a placeholder; actual implementation may vary
  {$ENDIF}
end;

function GetStackTraceInfo(Address: Pointer; out ModuleName, ProcName: string): Boolean;
begin
  Result := False;
  {$IFDEF MSWINDOWS}
  // Windows-specific implementation to retrieve module and procedure names
  // This is a placeholder; actual implementation may involve using the Windows API
  ModuleName := 'ModuleName'; // Placeholder
  ProcName := 'ProcName';     // Placeholder
  Result := True;
  {$ELSE}
  // Other platforms implementation
  // This is a placeholder; actual implementation may vary
  {$ENDIF}
end;

function FormatStackTrace(const Stack: TArray<Pointer>): string;
var
  SB: TStringBuilder;
  ModuleName, ProcName: string;
begin
  SB := TStringBuilder.Create;
  try
    for var i := 0 to Length(Stack) - 1 do
    begin
      var Address := NativeUInt(Stack[i]);
      if Address = 0 then
        Break;

      if GetStackTraceInfo(Pointer(Address), ModuleName, ProcName) then
        SB.AppendLine(Format('%2d: %s::%s at 0x%p', [i, ModuleName, ProcName, Pointer(Address)]))
      else
        SB.AppendLine(Format('%2d: 0x%p', [i, Pointer(Address)]));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;
{$ENDIF}

constructor TvgCriticalSection.Create(const AName: string = '');
begin
  inherited Create;
  fName := AName;
  fTimeout := INFINITE;
  fDeadlockCheckEnabled := True;
  fWaitingThreads := TList<TThreadInfo>.Create;
  fStopwatch := TStopwatch.Create;
  fLock := TCriticalSection.Create;

  {$IFDEF DEBUGCS}
  fTotalWaitTime := 0;
  fMaxWaitTime := 0;
  fLockAttempts := 0;
  fContentionCount := 0;
  {$ENDIF}
end;

destructor TvgCriticalSection.Destroy;
begin
  {$IFDEF DEBUGCS}
  if fLockCount > 0 then
    raise Exception.CreateFmt('Critical section "%s" destroyed while locked', [fName]);
  {$ENDIF}

  if assigned(fLock)  then
     FreeAndNil(fLock);

  FreeAndNil(fWaitingThreads);
  inherited;
end;

procedure TvgCriticalSection.Enter;
//var
//  StartTime: Int64;
//  WaitTime: Int64;
begin
  {$IFDEF DEBUGCS}
  Inc(fLockAttempts);
  StartTime := fStopwatch.ElapsedMilliseconds;
  {$ENDIF}

  if fDeadlockCheckEnabled then
    CheckForDeadlock;

  if not TryEnter(fTimeout) then
  begin
    HandleTimeout;
    Exit;
  end;

  {$IFDEF DEBUGCS}
  WaitTime := fStopwatch.ElapsedMilliseconds - StartTime;
  if WaitTime > 0 then
  begin
    Inc(fContentionCount);
    Inc(fTotalWaitTime, WaitTime);
    if WaitTime > fMaxWaitTime then
      fMaxWaitTime := WaitTime;
  end;
  fAcquisitionStack := GetStackTrace;
  {$ENDIF}

  RecordThreadInfo;
end;

function TvgCriticalSection.TryEnter(Timeout: Cardinal = INFINITE): Boolean;
var
  CurrentThread: TThreadID;
begin
  CurrentThread := GetCurrentThreadID;

  // Check if already owned by current thread
  if fOwnerThread = CurrentThread then
  begin
    Inc(fLockCount);
    Result := True;
    Exit;
  end;

  // Try to acquire the lock
  Result := inherited TryEnter;
  if Result then
  begin
    fOwnerThread := CurrentThread;
    fLockCount := 1;
    fLastLockTime := Now;
    RemoveWaitingThread(CurrentThread);
  end
  else if Timeout <> 0 then
  begin
    UpdateWaitingThreads;
    Result := inherited TryEnter;
    if Result then
    begin
      fOwnerThread := CurrentThread;
      fLockCount := 1;
      fLastLockTime := Now;
      RemoveWaitingThread(CurrentThread);
    end;
  end;
end;

procedure TvgCriticalSection.Leave;
begin
  if fOwnerThread <> GetCurrentThreadID then
    raise Exception.CreateFmt('Critical section "%s" Leave called from wrong thread', [fName]);

  Dec(fLockCount);
  if fLockCount = 0 then
  begin
    fOwnerThread := 0;
    fLastLockTime := 0;
    {$IFDEF DEBUGCS}
    fAcquisitionStack := '';
    {$ENDIF}
  end;

  inherited Leave;
end;

procedure TvgCriticalSection.AssertLocked(const Source: string = '');
begin
  if fOwnerThread <> GetCurrentThreadID then
    raise Exception.CreateFmt('Critical section "%s" assert locked failed at %s', [fName, Source]);
end;

procedure TvgCriticalSection.AssertNotLocked(const Source: string = '');
begin
  if fOwnerThread = GetCurrentThreadID then
    raise Exception.CreateFmt('Critical section "%s" assert not locked failed at %s', [fName, Source]);
end;

function TvgCriticalSection.GetCurrentThreadID: TThreadID;
begin
  Result := TThread.CurrentThread.ThreadID;
end;

function TvgCriticalSection.GetLockInfo: string;
begin
  Result := Format('CS "%s": Owner=%d, Count=%d, Waiting=%d',
    [fName, fOwnerThread, fLockCount, fWaitingThreads.Count]);

  {$IFDEF DEBUGCS}
  Result := Result + Format(', Contentions=%d, MaxWait=%dms',
    [fContentionCount, fMaxWaitTime]);
  {$ENDIF}
end;

{$IFDEF DEBUGCS}
function TvgCriticalSection.GetStackTrace: string;
var
  SB: TStringBuilder;
  DebugStackTrace: TArray<Pointer>;
  StackTraceSize: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine(Format('[Thread %d] Stack trace:', [GetCurrentThreadID]));

    SetLength(DebugStackTrace, 32); // Capture up to 32 stack frames
    StackTraceSize := GetCallStack(DebugStackTrace[0], Length(DebugStackTrace));
    if StackTraceSize > 0 then
    begin
      SetLength(DebugStackTrace, StackTraceSize);
      for var i := 0 to Length(DebugStackTrace) - 1 do
      begin
        var Address := NativeUInt(DebugStackTrace[i]);
        if Address = 0 then
          Break;

        // Get module and procedure name if available
        var ModuleName: string := '';
        var ProcName: string := '';

        if GetStackTraceInfo(Pointer(Address), ModuleName, ProcName) then
          SB.AppendLine(Format('  %2d: %s::%s at 0x%p',
            [i, ModuleName, ProcName, Pointer(Address)]))
        else
          SB.AppendLine(Format('  %2d: 0x%p', [i, Pointer(Address)]));
      end;
    end
    else
      SB.AppendLine('[Stack trace not available]');

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;
{$ENDIF}

procedure TvgCriticalSection.CheckForDeadlock;
var
  CurrentThread: TThreadID;
  WaitTime: Int64;
begin
  CurrentThread := GetCurrentThreadID;

  if (fOwnerThread <> 0) and (fOwnerThread <> CurrentThread) then
  begin
    WaitTime := MilliSecondsBetween(Now, fLastLockTime);
    if WaitTime > 5000 then // 5 seconds threshold
    begin
      raise Exception.CreateFmt(
        'Potential deadlock detected in CS "%s"'#13#10 +
        'Owner thread: %d, Waiting thread: %d'#13#10 +
        'Lock held for: %d ms'#13#10 +
        'Owner stack: %s',
        [fName, fOwnerThread, CurrentThread, WaitTime,
         {$IFDEF DEBUGCS}fAcquisitionStack{$ELSE}'Stack trace not available'{$ENDIF}]);
    end;
  end;
end;

procedure TvgCriticalSection.HandleTimeout;
begin
  raise Exception.CreateFmt('Critical section "%s" timeout', [fName]);
end;

procedure TvgCriticalSection.UpdateWaitingThreads;
var
  ThreadInfo: TThreadInfo;
begin
  ThreadInfo.ThreadID := GetCurrentThreadID;
  ThreadInfo.LockCount := 1;
  ThreadInfo.LastLockTime := Now;
  {$IFDEF DEBUGCS}
  ThreadInfo.StackTrace := GetStackTrace;
  {$ELSE}
  ThreadInfo.StackTrace := '';
  {$ENDIF}

  fLock.Enter;
  try
    fWaitingThreads.Add(ThreadInfo);
  finally
    fLock.Leave;
  end;
end;

procedure TvgCriticalSection.RemoveWaitingThread(ThreadID: TThreadID);
  Var I:Integer;
begin
  fLock.Enter;
  try
    for i := fWaitingThreads.Count - 1 downto 0 do
    begin
      if fWaitingThreads[i].ThreadID = ThreadID then
      begin
        fWaitingThreads.Delete(i);
        Break;
      end;
    end;
  finally
    fLock.Leave;
  end;
end;

procedure TvgCriticalSection.RecordThreadInfo;
var
  ThreadInfo,UpdateThreadInfo: TThreadInfo;
  ExistingIndex: Integer;
  CurrentThread: TThreadID;
  {$IFDEF DEBUGCS}
  DebugStackTrace: TArray<Pointer>;
  StackTraceSize: Integer;
  {$ENDIF}
  I:Integer;
  TimeThreshold : Integer;
begin
  CurrentThread := GetCurrentThreadID;

  // Early exit if this is a recursive lock from same thread
  if (fOwnerThread = CurrentThread) and (fLockCount > 1) then
    Exit;

  // Create new thread info record
  ThreadInfo.ThreadID := CurrentThread;
  ThreadInfo.LockCount := 1;
  ThreadInfo.LastLockTime := Now;

  {$IFDEF DEBUGCS}
  try
    // Get stack trace for debugging
    SetLength(DebugStackTrace, 32); // Capture up to 32 stack frames
    StackTraceSize := GetCallStack(DebugStackTrace[0], Length(DebugStackTrace));
    if StackTraceSize > 0 then
    begin
      SetLength(DebugStackTrace, StackTraceSize);
      ThreadInfo.StackTrace := FormatStackTrace(DebugStackTrace);
    end
    else
      ThreadInfo.StackTrace := Format('[Thread %d] Stack trace unavailable', [CurrentThread]);
  except
    // Fail safe if stack trace capture fails
    ThreadInfo.StackTrace := Format('[Thread %d] Stack trace collection failed', [CurrentThread]);
  end;
  {$ELSE}
  ThreadInfo.StackTrace := '';
  {$ENDIF}

  fLock.Enter; // Protect thread info list access
  try
    // Check if thread already exists in waiting list
    ExistingIndex := -1;
    for i := 0 to fWaitingThreads.Count - 1 do
    begin
      if fWaitingThreads[i].ThreadID = CurrentThread then
      begin
        ExistingIndex := i;
        Break;
      end;
    end;

    // Update or add thread info
    if ExistingIndex >= 0 then
    begin

      // Update existing record
      UpdateThreadInfo:= fWaitingThreads[ExistingIndex];
      Inc(UpdateThreadInfo.LockCount);
      UpdateThreadInfo.LastLockTime := ThreadInfo.LastLockTime;
      if ThreadInfo.StackTrace <> '' then
        UpdateThreadInfo.StackTrace := ThreadInfo.StackTrace;
      fWaitingThreads[ExistingIndex]:= UpdateThreadInfo;

    end
    else
      // Add new record
      fWaitingThreads.Add(ThreadInfo);

    // Cleanup old records (older than 1 minute)
    TimeThreshold := Trunc(Now - (1 / (24 * 60))); // 1 minute ago
    for i := fWaitingThreads.Count - 1 downto 0 do
    begin
      if (fWaitingThreads[i].ThreadID <> CurrentThread) and
         (fWaitingThreads[i].LastLockTime < TimeThreshold) then
        fWaitingThreads.Delete(i);
    end;

  finally
    fLock.Leave;
  end;

  // Update owner information
  fOwnerThread := CurrentThread;
  fLastLockTime := ThreadInfo.LastLockTime;

  {$IFDEF DEBUGCS}
  // Log acquisition if enabled

  if Assigned(fOnLockAcquired) then
  begin
    var AcquisitionInfo: TLockAcquisitionInfo;
    AcquisitionInfo.ThreadID := CurrentThread;
    AcquisitionInfo.LockCount := fLockCount;
    AcquisitionInfo.WaitingThreads := fWaitingThreads.Count;
    AcquisitionInfo.StackTrace := ThreadInfo.StackTrace;
    fOnLockAcquired(Self, AcquisitionInfo);
  end;
  {$ENDIF}
end;

procedure TvgCriticalSection.ResetStatistics;
begin
  {$IFDEF DEBUGCS}
  fTotalWaitTime := 0;
  fMaxWaitTime := 0;
  fLockAttempts := 0;
  fContentionCount := 0;
  {$ENDIF}
end;

end.
