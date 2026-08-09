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
unit Vulkan_Renderer_CommThread;

interface

{$INCLUDE VulkanPackage.inc}

uses
  {$IFDEF FASTMM5}
  FastMM5,
  {$ENDIF}
  System.SysUtils,
  System.Generics.Collections,   //MUST STAY HERE
  System.Generics.Defaults,
  System.Classes,                //MUST STAY HERE
  System.Math,
  System.SyncObjs,
  typinfo,
  CommThread,
  Vulkan,
  PasVulkan.Math,
  PasVulkan.Collections,
  PasVulkan.Framework,
  Vulkan_Components,
  Vulkan_Assert,
  Vulkan_Components_Lookups,
  Vulkan_Components_Descriptors,
  Vulkan_Components_Nodes,
  Vulkan_Components_Scene_Renderer;

Type

  TvgCommThread_RenderEngine = class;

  TWorkerThread = class(TCommThread<TvgRenderTask, TvgRenderComplete>)
  private
    function GetActive: Boolean;

  protected
    fActive          : Boolean;
    fRenderWorker    : TvgRenderWorker;                          //handles all the work
    fWorkerIndex     : TvkUint32;

    fCriticalSection : TCriticalSection;    //local

    fTaskComplete    :TvgRenderComplete;                        //hold task complete data for Processmessage

    procedure ProcessMessage(const data: TvgRenderTask); Override;

  public
    constructor Create(AQueueToThread: TMessageQueue<TvgRenderTask>;
                       AQueueToMain  : TMessageQueue<TvgRenderComplete> ;
                       aIndex        : TvkUint32;
                       aName         : String ;
                       aOwnsThreadQueue, aOwnsMainQueue    : Boolean);

    Destructor Destroy; Override;
    procedure Execute; override;
    Property Active       : Boolean read GetActive;
    Property RenderWorker : TvgRenderWorker read fRenderWorker;

  end;

  TvgRenderState =
        (
        RS_INITIAL,
        RS_RES_UPLOAD,
        RS_BEGIN_RECORDING,
        RS_SET_SUBPASS,
        RS_SET_GRAPHICPIPELINE,
        RS_RENDER_NODES,
        RS_END_RECORDING,        //end recording of WORKER secondary buffer
        RS_EXECUTESECONDARY,     //execute the worker secondary buffer onto the Frame Primary buffer
        RS_RESET,
        RS_COMPLETE
        );

  TvgRenderWorker_Message = procedure(const aLabel:String; const ThreadCount : Integer; const aMsgCount:Integer; const TaskCount:Integer) of object;

  TvgWorkerID = Integer;

  TvgWorkerInfo<TvgRenderTask, TvgRenderComplete> = record
    WorkerID : TvgWorkerID;
    Thread   : TWorkerThread;
    TaskCount: Integer;
    Event    : TEvent;
  end;

  TvgCommStateSendType =
      (CS_ALL,
       CS_NEXT,
       CS_SPECIFIC);

  TvgFrameJob =
      (FJ_PREPAREFRAME_START,
       FJ_PREPAREFRAME_FINISH,
       FJ_PREPAREFRAME_CANCEL,
       FJ_PRESENTFRAME);

  TvgFrameTask = record
     FrameJob   : TvgFrameJob;
     Frame      : TvgFrame;
     ImageIndex : Integer;
  end;

  TvgFrameStatus =
      (FS_PREPAREFRAME_RUNNING,
       FS_PREPAREFRAME_COMPLETE,
       FS_PREPAREFRAME_ERROR,
       FS_PREPAREFRAME_CANCELED);

  TvgThreadMode =
     (TM_SINGLE,
      TM_MULTITASK
      );


  PvgFrameComplete = ^TvgFrameComplete;    //record returned on completion of a Task in a Worker Thread
  TvgFrameComplete = record
     ImageIndex         : Integer;  //current Worker(Thread) worker completing task data returned
     PrepareFrameStatus : TvgFrameStatus;
     Frame              : TvgFrame;
     TaskID             : Integer;
     TaskStatus         : TvgRenderTaskStatus;
     TaskComment        : String;
  end;


  TvgRenderWorkerThreadManager =  class(TCommThread<TvgFrameTask, TvgFrameComplete>)
  private
    procedure SetThreadMode(const Value: TvgThreadMode);
  //used to prepare the next frame with scene building and HUD completed by threads

  Protected

    fOwnsQueues          : Boolean;

    fRenderEngine        : TvgBaseRenderEngine;

    fThreadMode          : TvgThreadMode;

    fCurrentPrepareFrame :TvgFrame;

    fMsgQueueCount         : Integer;    //should match number of Tasks/Nodes
    fWorkerCount           : Integer;
    fCurrentWorkerIndex    : Integer;
    fImageIndex            : Integer;


    fWorkerTaskCount       : Integer;
    fWorkerTaskIndex       : Integer;
    fWorkerTaskListStepSize: Integer; //start size and inc size
    fLastTaskIndex         : Integer;

      //hold count of ACTIVE tasks (started but not finished

  //  fQueueToWorkers      : TMessageQueue<TvgRenderTask> ;

    fWorkerThreads       : Array of TvgWorkerInfo<TvgRenderTask, TvgRenderComplete>;

    fWorkerTaskList      : Array of TvgRenderTask;

    //handles local and small tasks
    fWorkerRenderState     : TvgRenderState;

    fWorkerCriticalSection : TCriticalSection;

    fPrepareFrameRunning         : Boolean;     //prepare frame task request received  Set To True once prepare underway
    fPrepareFrameLock,
    fPrepareFrameRequested       : Boolean;
    fDisableSleepCount           : Integer;
    fCurrentGraphicPipelineIndex : TvkUint32;
    fCurrentGraphicPipeline      : TvgGraphicPipeline;
    fCurrentSubPassIndex         : TvkUint32;

    fNextTask                    : TvgFrameTask;

    fTimeOutCount,
    fTimeOutMax                  : Integer;

    fRenderWorker                : TvgRenderWorker;                          //handles all the work

    procedure ProcessMessage(const data: TvgFrameTask); Override;

    Procedure BuildAndSetUpWorkers;
    //used to create set of workers to handle rendering duing class creation
    Procedure CleanUpAndFreeWorkers;
    //tidy up   on destroy

    Function SendTaskToThreads(TaskIndex:Integer; SendType:TvgCommStateSendType; SendIndex:Integer=-1):Boolean;
 //   Function SendTaskBlockToThreads(TaskStartIndex, TaskStopIndex:Integer):Boolean;
    Function CheckTaskCompleteStatus(var aComplete, aIncomplete, aError:Integer):Boolean;

    procedure HandleWorkerMessage(const Task: TvgRenderComplete);

    Function GetATask:Integer;
    Procedure FreeAllTasks;

  //all thread worker tasks

    Procedure Render_UploadResourceData;
    Procedure Render_BeginRecording;   //begin recording of SECONDARY worker buffer
    Procedure Render_SetRenderSubPass;
    Procedure Render_SetPipeline;
    Procedure Render_RenderLoop;
    Procedure Render_EndRecording; //end recording of SECONDARY worker buffer
    Procedure Render_Execute;     //execute Worker SECONDARY on Frame PRIMARY buffer
    Procedure Render_RESET;

    procedure ProcessFramePrepareMessage(const data: TvgFrameTask);

    Procedure ProcessCompletedTasks;

    //allow the Render Engine descendants to build a specific set of Graphic Pipelines
    Procedure StartPrepare(ImageIndex:Integer; aFrame:TvgFrame);
    Procedure FinishPrepare;
 //   Procedure CancelPrepare;

    Procedure RenderRunTasks;
    //will pass the required task to the threads so next stage cab be completed

    //used for SINGLE  Thread mode

    Procedure RenderFrame(ImageIndex:TvkUint32; aFrame:TvgFrame; aSubPass : TvkUint32);

  Public
     constructor Create(aRenderEngine  : TvgBaseRenderEngine;
                       AQueueToThread  : TMessageQueue<TvgFrameTask>;
                       AQueueToMain    : TMessageQueue<TvgFrameComplete> ;
                       aOwnsThreadQueue, aOwnsMainQueue      : Boolean;
                       numWorkers      : Integer ;
                       ThreadMode      : TvgThreadMode);
    destructor Destroy; Override;

    procedure Execute; override;

    Function SendFrameTask(aFrameTask : TvgFrameTask) : Boolean;

    Property ThreadMode          : TvgThreadMode Read fThreadMode write SetThreadMode;


  end;

   TvgCommThread_RenderEngine = Class(TvgRenderEngine)
   //runs in Main Thread
  private
    procedure SetThreadMode(const Value: TvgThreadMode);

    Protected
       fWorkerThreadManager : TvgRenderWorkerThreadManager;   //runs threads for render tasks
       fThreadMode          : TvgThreadMode;
       fMsgCount            : Integer;

    Function SetDisabled :Boolean; Override;
    Function SetEnabled  :Boolean; Override;

    procedure HandlePrepareFrameMessage(const Task: TvgFrameComplete);

    Protected

    Procedure BuildAndSetUpWorkers;   override;


    Public

    constructor Create(AOwner: TComponent); Override;
    destructor Destroy; override;

    Procedure StartRenderEnginePrepare( ImageIndex:Integer; aFrame:TvgFrame);  Override;
    Procedure FinishRenderEnginePrepare;                                       Override;

    Procedure AddSceneRenderCommands(ImageIndex:TvkUint32; aFrame:TvgFrame; aSubPass : TvkUint32);  Override;


    Procedure CreateRenderPass;            Override;

    Property  ThreadMode          : TvgThreadMode Read fThreadMode write SetThreadMode;


   End;


implementation


{ TRenderTaskThread }

constructor TWorkerThread.Create(AQueueToThread: TMessageQueue<TvgRenderTask>;
                                 AQueueToMain  : TMessageQueue<TvgRenderComplete> ;
                                 aIndex        : TvkUint32;
                                 aName         : String ;
                                 aOwnsThreadQueue, aOwnsMainQueue    : Boolean);
begin


  fRenderWorker   := TvgRenderWorker.Create(aIndex);
  fWorkerIndex    := aIndex;

  fCriticalSection:= TCriticalSection.Create;
  fActive         := False;

  inherited Create(AQueueToThread, AQueueToMain, aName, aOwnsThreadQueue, aOwnsMainQueue);

  if aName<>'' then
      NameThreadForDebugging(aName, ThreadID);

end;

destructor TWorkerThread.Destroy;
begin
  If assigned(fRenderWorker) then
     FreeAndNil(fRenderWorker);

  If assigned(fCriticalSection) then
     FreeAndNil(fCriticalSection);

  inherited;
end;

procedure TWorkerThread.Execute;
//var
  //data: TvgRenderTaskJob;
begin

  fActive   := True;

   Inherited;

  //shut down
  If assigned(fRenderWorker) then
  Begin
     fRenderWorker.SetDisabled;

   //  If assigned(fCriticalSection) then
   //     fCriticalSection.BeginWrite;
     fActive   := False;
  //   If assigned(fCriticalSection) then
  //      fCriticalSection.EndWrite;
  End;

end;

function TWorkerThread.GetActive: Boolean;
begin
//     If assigned(fCriticalSection) then
//        fCriticalSection.BeginRead;
     Result := fActive ;
//     If assigned(fCriticalSection) then
//        fCriticalSection.EndRead;
end;

procedure TWorkerThread.ProcessMessage(const data: TvgRenderTask);
  Var   RS  : TvgRenderTaskStatus;
        CT  : TvgRenderTask;
begin
  CT := Data;

 Try
  If assigned( fRenderWorker) then
  Begin
    RS := fRenderWorker.CompleteTask(CT);
    fTaskComplete.TaskStatus  := RS;
  End else
  Begin
    fTaskComplete.TaskStatus  := TS_FAIL;
    fTaskComplete.Workerindex := 9999;
  End;

  fTaskComplete.Workerindex := fWorkerIndex;
  fTaskComplete.TaskJob     := Data.TaskJob;

  fTaskComplete.TaskID      := CT.TaskID;

  SendToMain(fTaskComplete);

 Except

 End;

end;

{ TvgRenderWorkerManager }

procedure TvgRenderWorkerThreadManager.BuildAndSetUpWorkers;
  Var I,NC:Integer;
    aQueueToWorkers : TMessageQueue<TvgRenderTask>;
    aQueueToMain    : TMessageQueue<TvgRenderComplete>;
    aWorker         : TWorkerThread;

begin
  Assert(assigned( fRenderEngine), 'Render Engine NOT assigned');
  Assert(assigned(fRenderEngine.GlobalRes),'Global Resource not assigned');
  Assert(assigned(fRenderEngine.BaseScene),'Scene not connected');


case fThreadMode of
   TM_SINGLE     : Begin
                      fRenderWorker          := TvgRenderWorker.Create(0);
                      fRenderWorker.Renderer := Self.fRenderEngine ;

                      //Vulkan should be ACTIVE here

                      fRenderWorker.Active:=True;

                   end;    //single mode
   TM_MULTITASK  : Begin

                      if fWorkerCount=0 then
                         fWorkerCount:=1;


                      NC :=  fRenderEngine.basescene.GetObjectCount  ;
                    (*
                      fMsgQueueCount := NC div fWorkerCount;      //need to refine this later

                      If fRenderEngine.GraphicPipes.Count>fMsgQueueCount then
                        fMsgQueueCount := fRenderEngine.GraphicPipes.Count * 2;

                      If fMsgQueueCount>100 then
                         fMsgQueueCount := 100;

                      If fMsgQueueCount<10 then
                         fMsgQueueCount := 10;
                     *)
                      fMsgQueueCount := NC + 20;

                      fWorkerCriticalSection:= TCriticalSection.Create;

                      SetLength(fWorkerThreads, fWorkerCount);

                      for I := 0 to Length(fWorkerThreads)-1 do
                      Begin

                      //workerthread OWNS message queues
                        aQueueToWorkers       := TMessageQueue<TvgRenderTask>.Create(fMsgQueueCount,nil);   //no receiver just events
                        aQueueToMain          := TMessageQueue<TvgRenderComplete>.Create(fMsgQueueCount, nil); //no receiver just events

                        aWorker               := TWorkerThread.Create(aQueueToWorkers, aQueueToMain,
                                                                      I,
                                                                      Format('Render Worker (%d)',[I]),
                                                                      True,
                                                                      True);  //owns queues

                        fWorkerThreads[I].WorkerID := I;
                        fWorkerThreads[I].Thread   := aWorker;
                        fWorkerThreads[I].TaskCount:= 0;
                        fWorkerThreads[I].Event    := aQueueToMain.Event ;

                        If assigned(aWorker.RenderWorker) then
                        Begin
                          aWorker.RenderWorker.Renderer  := fRenderEngine;
                          aWorker.RenderWorker.Active    := True;
                        End;
                      End;

                      If fWorkerTaskListStepSize=0 then
                         fWorkerTaskListStepSize := 100;

                      SetLength(fWorkerTaskList, fWorkerTaskListStepSize) ;
                      FillChar(fWorkerTaskList[0], SizeOf(TvgREnderTask) * fWorkerTaskListStepSize,#0);

                      fCurrentWorkerIndex := 0;
                      fWorkerTaskIndex    := 0;
                      fWorkerTaskCount    := 0;

                   end; //end multi task
end;


end;

function TvgRenderWorkerThreadManager.CheckTaskCompleteStatus(var aComplete, aIncomplete, aError: Integer): Boolean;
  Var I,L:Integer;
begin
  Result := False;

  aComplete  := 0;
  aInComplete:= 0;
  aError     := 0;

  if fThreadMode = TM_MULTITASK then
  Begin
    L:=Length(fWorkerTaskList);

    if L=0 then exit;

    for I := 0 to fWorkerTaskIndex-1 do
    Begin
      If (fWorkerTaskList[I].TaskStatus = TS_COMPLETE) then
          Inc(aComplete)
      else
      If (fWorkerTaskList[I].TaskStatus = TS_FAIL) then
        Inc(aError)
      else
        Inc(aInComplete);
    End;

    Result := True;
  End; //finish

end;

procedure TvgRenderWorkerThreadManager.CleanUpAndFreeWorkers;
var
  i,L: integer;
begin
  Assert(assigned( fRenderEngine), 'Render Engine NOT assigned');

  case fThreadMode of
             TM_SINGLE    : Begin
                                If assigned(fRenderWorker) then
                                   FreeAndNil(fRenderWorker);
                            end;    //single task
             TM_MULTITASK : Begin
                                  L :=  Length(fWorkerThreads)  ;
                                  If (L > 0) then
                                  Begin

                                    for i := 0 to L-1 do
                                    begin
                                      fWorkerThreads[i].Thread.Terminate;  //will disable the workers and free Vulkan Memory
                                      fWorkerThreads[i].Thread.WaitFor;
                                    end;

                                    for i := 0 to L-1 do
                                      if assigned(fWorkerThreads[i].Thread)  then
                                         FreeAndNil(fWorkerThreads[i].Thread);

                                    SetLength(fWorkerThreads,0);
                                 end;

                                  SetLength(fWorkerTaskList,0);

                                  fWorkerTaskIndex    := 0;
                                  fWorkerTaskCount    := 0;
                                  fCurrentWorkerIndex := 0;
                            end;    //multi task
  end;


end;

constructor TvgRenderWorkerThreadManager.Create(aRenderEngine   : TvgBaseRenderEngine;
                                                 AQueueToThread : TMessageQueue<TvgFrameTask>;
                                                 AQueueToMain   : TMessageQueue<TvgFrameComplete> ;
                                                 aOwnsThreadQueue, aOwnsMainQueue     : Boolean;
                                                 numWorkers     : Integer ;
                                                 ThreadMode      : TvgThreadMode);

begin

  Inherited Create(AQueueToThread, AQueueToMain, 'RenderWorkerManager', aOwnsThreadQueue, aOwnsMainQueue);
 // SetFreeOnTerminate(False);

  fRenderEngine := aRenderEngine;
  Assert(Assigned(fRenderEngine),'Render Engine not assigned');

  fWorkerTaskListStepSize := 100;

  fWorkerCount    := numWorkers;
  if fWorkerCount<1 then
     fWorkerCount:=1;


  fDisableSleepCount := 2;
  fLastTaskIndex     := -1;

  fTimeOutCount :=0;
  fTimeOutMax   :=10;

  fThreadMode := ThreadMode;
end;

destructor TvgRenderWorkerThreadManager.Destroy;
begin


  inherited;
end;


procedure TvgRenderWorkerThreadManager.Execute;
const
  POLL_TIMEOUT = 0;

  Procedure ExecuteSingleMode;
    Var    waitResult      : TWaitResult;
          aTask            : TvgFrameTask;
  Begin

        while not Terminated do
        begin
            waitResult := FToThread.Event.WaitFor(POLL_TIMEOUT);

            if waitResult= wrSignaled then
            Begin
                while FToThread.Receive(atask) do
                Begin
                    if aTask.FrameJob = FJ_PREPAREFRAME_START then
                    Begin
                      StartPrepare(atask.ImageIndex, atask.Frame);
                      FinishPrepare;
                    End;
                end;
                if not FToThread.Receive(atask) then
                  FToThread.Event.ResetEvent;

            End;

            if not fPrepareFrameRunning then
                Sleep(1);
        end;
  End;

  Procedure ExecuteMultiTaskMode;

        var
          I, L : Integer;
          aTask           : TvgFrameTask;
          waitResult      : TWaitResult;
          FC              : TvgFrameComplete;
           Complete,Incomplete,aError  : Integer;

  Begin
        L := Length(fWorkerThreads);   //include Main Thread posting event

        while not Terminated do
        begin

           if fPrepareFrameRunning then
           Begin
             Try

               if fWorkerTaskCount>0 then   //tasks running
                 ProcessCompletedTasks;

               If (fWorkerTaskCount<=0) then
                Begin
                //clear the task list
                  If CheckTaskCompleteStatus(Complete,Incomplete,aError) then
                  Begin

                    FC.PrepareFrameStatus := FS_PREPAREFRAME_RUNNING;
                    FC.Frame              := nil;
                    FC.TaskID             := -1;
                    FC.TaskComment        := Format('Task Complete Status Complete = %d, Incomplete = %d and Error = %d in %d tasks',
                                                    [Complete, Incomplete, aError, fWorkerTaskIndex ]);

                    SendToMain(FC);
                  End;

                  FreeAllTasks;
                  fWorkerTaskCount := 0;

                  For I:=0 to L-1 do
                     fWorkerThreads[I].TaskCount := 0;

                 //render next stage OR finish
                  If (fWorkerRenderState = RS_COMPLETE) then
                  Begin
                    if assigned(fRenderEngine.Linker)and (fRenderEngine.Linker.MsgON)  then
                       fRenderEngine.Linker.AddMsgToList('Frame Render complete');

                    FinishPrepare;

                    if not fPrepareFrameRunning then
                    Begin

                    FC.ImageIndex         := fCurrentPrepareFrame.ImageIndex;
                    FC.PrepareFrameStatus := FS_PREPAREFRAME_COMPLETE;
                    FC.Frame              := fCurrentPrepareFrame;

                    fPrepareFrameRunning := False;

                    SendToMain(FC);

                    end;

                  end;
                End;

             Except

             End;

           end;    //prepareFrameRunning

         //handle Main Thread task requests

            waitResult := FToThread.Event.WaitFor(POLL_TIMEOUT);

            if waitResult=wrSignaled then
            Begin
                while FToThread.Receive(atask) do
                   ProcessFramePrepareMessage(aTask);

                if not FToThread.Receive(atask) then
                  FToThread.Event.ResetEvent;

            End;

            if not fPrepareFrameRunning then
                Sleep(1);

        end;  //not terminated  LOOP
  End;     //end Multi task

begin

  BuildAndSetUpWorkers;

  //execute loop in these procedures
  case fThreadMode of
      TM_SINGLE     : ExecuteSingleMode;
      TM_MULTITASK  : ExecuteMultiTaskMode;
  end;

  CleanUpAndFreeWorkers;
end;

procedure TvgRenderWorkerThreadManager.FreeAllTasks;
begin
  SetLength(fWorkerTaskList, fWorkerTaskListStepSize);
  FillChar(fWorkerTaskList[0],SizeOf(TvgREnderTask) * fWorkerTaskListStepSize,#0);
  fWorkerTaskIndex := 0;
  fWorkerTaskCount := 0;
end;

function TvgRenderWorkerThreadManager.GetATask: Integer;

begin
  //  Result := -1;

    If fWorkerTaskListStepSize=0 then
       fWorkerTaskListStepSize := 100;

    If (fWorkerTaskIndex >= Length(fWorkerTaskList)) then
      SetLength(fWorkerTaskList, Length(fWorkerTaskList) + fWorkerTaskListStepSize);

    //task must be DISPOSEd of after completion of task by worker

    FillChar(fWorkerTaskList[fWorkerTaskIndex], SizeOf(TvgRenderTask), #0);

    fWorkerTaskList[fWorkerTaskIndex].TaskID            := fWorkerTaskIndex;
    fWorkerTaskList[fWorkerTaskIndex].RenderPassHandle  := fRenderEngine.RenderPass.RenderPassHandle;
    fWorkerTaskList[fWorkerTaskIndex].SubPassIndex      := fCurrentSubPassIndex;   //fRenderPass.SubPasses.count;  //need to set
    fWorkerTaskList[fWorkerTaskIndex].FrameIndex        := fRenderEngine.Linker.CurrentPrepareFrame.FrameIndex;
    fWorkerTaskList[fWorkerTaskIndex].Frame             := fRenderEngine.Linker.CurrentPrepareFrame;
    fWorkerTaskList[fWorkerTaskIndex].TaskJob           := TM_NONE;
    fWorkerTaskList[fWorkerTaskIndex].UploadData        := True;
    fWorkerTaskList[fWorkerTaskIndex].UploadResourceData:= True;
    fWorkerTaskList[fWorkerTaskIndex].GlobalRes         := fRenderEngine.GlobalRes ;
    fWorkerTaskList[fWorkerTaskIndex].CriticalSection   := fWorkerCriticalSection ;

    Result := fWorkerTaskIndex;

    inc(fWorkerTaskIndex);

end;

procedure TvgRenderWorkerThreadManager.HandleWorkerMessage( const Task: TvgRenderComplete);
  Var S,s1:String;
      AT:TvgRenderComplete;
   //   I,L:Integer;
      FT : TvgFrameComplete;
begin
//running in main thread

 // if not assigned(fRenderEngine.Linker) and fRenderEngine.Linker.MsgON then exit;

  AT := Task;

  If (AT.TaskStatus = TS_COMPLETE) then
  Begin

        S:='';
        Case AT.TaskJob of
          TM_NONE                :S:='None';
          TM_UPLOADOBJECTDATA          :S:='Upload data';
          TM_UPLOADRESOURCEDATA  :S:='Upload resource data';
          TM_BEGIN_RECORDING_FRAME:S:='Begin recording';
          TM_BIND_PIPELINE       :S:='Bind pipeline';
          TM_RENDER_OBJECTSTORE  :S:='Render NODE';
          TM_EXECUTE_SECONDARY   :S:='Execute Secondary';
          TM_END_RECORDING_FRAME :S:='End recording';
          TM_RESET               :S:='Reset';
        else
          S := '<Unknown>';
        End;

       S1 := Format('%s : Thread ID : %d , Task # : %d, ',[S, AT.WorkerIndex, AT.TaskID]) ;
     //  fRenderEngine.Linker.AddMsgToList(S1);

  End else
  Begin
      // fRenderEngine.Linker.AddMsgToList(Format('Incomplete Task : Thread ID : %d , Task # : %d',[ AT.WorkerIndex, fWorkerTaskCount]));
  End;


  FT.PrepareFrameStatus := FS_PREPAREFRAME_RUNNING;    //important
  FT.TaskID             := AT.TaskID;
  FT.TaskStatus         := AT.TaskStatus;
  FT.TaskComment        := S1;

  SendToMain(FT) ;

  fWorkerTaskList[AT.TaskID].TaskStatus := AT.TaskStatus;

end;

procedure TvgRenderWorkerThreadManager.ProcessCompletedTasks;
  Var I,L:Integer;
  aRenderMsg      : TvgRenderComplete;
  waitResult      : TWaitResult;

  Const
     POLL_TIMEOUT = 0;

begin
      L:=Length(fWorkerThreads);

      for i := 0 to L-1 do   //loop through the thread events
      begin

        If (fWorkerThreads[i].TaskCount>0) then      //worker has tasks
        Begin
            waitResult := fWorkerThreads[i].Event.WaitFor(POLL_TIMEOUT);

            if waitResult = wrSignaled then
            begin

                while FWorkerThreads[I].Thread.FToMain.Receive(aRenderMsg) do
                Begin
                    FWorkerThreads[I].TaskCount := FWorkerThreads[I].TaskCount-1;
                    fWorkerTaskCount            := fWorkerTaskCount - 1;
                    HandleWorkerMessage(aRenderMsg);
                End;

                if not FWorkerThreads[I].Thread.FToMain.Receive(aRenderMsg) then
                  FWorkerThreads[I].Event.ResetEvent;
            End;


        End;  //worker running tasks

      end;  //For loop

end;

procedure TvgRenderWorkerThreadManager.ProcessFramePrepareMessage(const data: TvgFrameTask);
  Var T : TvgFrameTask;
begin

  T:=Data;

  if Not assigned(T.Frame) then  exit;


  case T.FrameJob of
    FJ_PREPAREFRAME_START  : Begin
                               StartPrepare(T.ImageIndex, T.Frame);
                             End;
    FJ_PREPAREFRAME_FINISH : Begin
                               FinishPrepare;
                               fPrepareFrameRunning := False;
                             End;
    FJ_PREPAREFRAME_CANCEL : Begin
                             //  CancelPrepare;
                               fPrepareFrameRunning := False;
                             End;
    FJ_PRESENTFRAME: ;
  end;
end;

procedure TvgRenderWorkerThreadManager.ProcessMessage(const data: TvgFrameTask);
begin
  //finish
end;

procedure TvgRenderWorkerThreadManager.FinishPrepare;
 var   VK_ClearToPresent  : TVkImageMemoryBarrier  ;
      VK_ImageSub        : TVkImageSubresourceRange;
      RenderImage        : TVkImage;
      FC : TvgFrameComplete;

begin

  if not fPrepareFrameLock then exit;

  fWorkerRenderState := RS_COMPLETE;

  Assert(Assigned(fCurrentPrepareFrame),'Current Frame not assigned.');

  Try

      fCurrentPrepareFrame.FrameCommandBuffer.CmdEndRenderPass;


      If (fRenderEngine.Linker.ScreenDevice.QueuePresentation.FamilyIndex <> fRenderEngine.Linker.ScreenDevice.QueueGraphics.FamilyIndex) then
      Begin
          FillChar(VK_ImageSub,SizeOf(TVkImageSubresourceRange),#0);
          FillChar(VK_ClearToPresent,SizeOf(TVkImageMemoryBarrier),#0);

          case fRenderEngine.Linker.RenderTarget of
              RT_SCREEN : Begin
                            RenderImage     := fRenderEngine.Linker.SwapChain.VulkanSwapChain.Images[fImageIndex].Handle ;
                          End;
              RT_FRAME  : Begin
                            RenderImage     := fCurrentPrepareFrame.FrameImageBuffer.FrameBufferAttachment.ImageView.Handle ;
                          End;
              else
                  RenderImage:=VK_NULL_HANDLE;
          end;

          VK_ImageSub.aspectMask     := TVkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT);
          VK_ImageSub.baseMipLevel   := 0;
          VK_ImageSub.levelCount     := 1;
          VK_ImageSub.baseArrayLayer := 0;
          VK_ImageSub.layerCount     := 1;

          VK_ClearToPresent.sType         := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
          VK_ClearToPresent.pNext         := nil;
          VK_ClearToPresent.srcAccessMask := TVkAccessFlags(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT);
          VK_ClearToPresent.dstAccessMask := TVkAccessFlags(VK_ACCESS_MEMORY_READ_BIT);
          VK_ClearToPresent.oldLayout     := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
          VK_ClearToPresent.newLayout     := VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
          VK_ClearToPresent.srcQueueFamilyIndex := fRenderEngine.Linker.ScreenDevice.QueueGraphics.FamilyIndex;   //check
          VK_ClearToPresent.dstQueueFamilyIndex := fRenderEngine.Linker.ScreenDevice.QueuePresentation.FamilyIndex;   //check
          VK_ClearToPresent.subresourceRange    := VK_ImageSub;


          VK_ClearToPresent.image  := RenderImage;

          fCurrentPrepareFrame.FrameCommandBuffer.CmdPipelineBarrier(
                                TVkPipelineStageFlags(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),//srcStageMask:TVkPipelineStageFlags;
                                TVkPipelineStageFlags(VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT),         //dstStageMask:TVkPipelineStageFlags;
                                0,   //dependencyFlags:TVkDependencyFlags;
                                0,   //memoryBarrierCount:TvkUint32;
                                nil, //aMemoryBarriers:PVkMemoryBarrier;
                                0,   //bufferMemoryBarrierCount:TvkUint32
                                nil, //aBufferMemoryBarriers:PVkBufferMemoryBarrier
                                1,     //imageMemoryBarrierCount:TvkUint32
                               @VK_ClearToPresent);  // aImageMemoryBarriers:PVkImageMemoryBarrier

      end;

      fCurrentPrepareFrame.FrameCommandBuffer.EndRecording;

      FC.ImageIndex         := -1;
      FC.PrepareFrameStatus := FS_PREPAREFRAME_COMPLETE;
      FC.Frame              := fCurrentPrepareFrame ;

      FToMain.Send(FC)  ;    //signal Main Thread

  Finally
    fPrepareFrameLock    := False;
    fPrepareFrameRunning := False;
  End;

  if fPrepareFrameRequested  and (fNextTask.FrameJob = FJ_PREPAREFRAME_START ) then
  Begin
     fPrepareFrameRequested := False;
     StartPrepare(fNextTask.ImageIndex, fNextTask.Frame) ;
  End;

end;

procedure TvgRenderWorkerThreadManager.RenderFrame(  ImageIndex: TvkUint32; aFrame: TvgFrame; aSubPass: TvkUint32);
  Var     RW             : TvgRenderWorker;
          aTask          : TvgRenderTask;
       //   VulkanCommands : TVulkan;
       //   J              : Integer;
       //   GP             : TvgGraphicPipeline;

    Procedure UploadGlobalDescriptorSet;
    Begin
      If not assigned(fRenderEngine.GlobalRes) then exit;

      aTask.Resources := fRenderEngine.GlobalRes;
      aTask.TaskJob   := TM_UPLOADRESOURCEDATA;
      RW.CompleteTask(aTask);
    End;

    Procedure UploadGraphicPipeDescriptorSetData(aPipe:TvgGraphicPipeline);
    Begin
      If not assigned(aPipe) then exit;
      If not assigned(aPipe.ObjectStore) then exit;
      If not assigned(aPipe.ObjectStore.ObjectStoreRes) then exit;

      aTask.Resources := (aPipe.ObjectStore.ObjectStoreRes);
      aTask.TaskJob   := TM_UPLOADRESOURCEDATA;
      RW.CompleteTask(aTask);
    End;
 (*
    Procedure UploadData(aRenderNodeList:TvgObjectDataList);
      Var I:Integer;
          RN : TvgObject_Base;
    Begin
      If not assigned( aRenderNodeList) then exit;
      If aRenderNodeList.Count=0 then exit;

      For I:=0 to aRenderNodeList.Count-1 do
      Begin
        RN:= aRenderNodeList.Items[I];
        If assigned(RN) then
        Begin
         // If RN.Renderer <> fRenderEngine then
         //    RN.Renderer   := fRenderEngine;


          If assigned(RN.MaterialRes[aSubPass]) then
          Begin
          //  If Not RN.MaterialRes.active then
            aTask.Resources := RN.MaterialRes[aSubPass];
            aTask.TaskJob   := TM_UPLOADRESOURCEDATA;
            RW.CompleteTask(aTask);
          End;

          If assigned(RN.ModelRes[aSubPass]) then
          Begin
            aTask.Resources := RN.ModelRes[aSubPass];
            aTask.TaskJob   := TM_UPLOADRESOURCEDATA;
            RW.CompleteTask(aTask);
          End;

          aTask.RenderObject := RN;
          aTask.TaskJob    := TM_UPLOADDATA;
          RW.CompleteTask(aTask);

        End;
      End;
    End;
 *)
 (*
    Procedure AddNodesToCommand(aRenderNodeList:TvgObjectDataList);
      Var I:Integer;
          RN:TvgObjectStore_Base;
    Begin
      If not assigned( aRenderNodeList) then exit;
      If aRenderNodeList.Count=0 then exit;

      For I:=0 to aRenderNodeList.Count-1 do
      Begin
        RN:= aRenderNodeList.Items[I];
        If assigned(RN) then
        Begin
          aTask.ObjectStore := RN;
          aTask.TaskJob    := TM_RENDER_NODE;
          RW.CompleteTask(aTask);

        End;
      End;
    End;
  *)
Begin
      Assert(assigned(fRenderEngine.Linker),'Window Link not connected');

      RW := fRenderWorker;

      Assert(assigned(RW),'Render Worker not created');
//      VulkanCommands := fLinker.ScreenDevice.VulkanDevice.Commands ;

      FillChar(aTask,SizeOf(aTask),#0);    //important
//      aTask.Linker            := fLinker;
      aTask.Frame             := aFrame;

      aTask.RenderPassHandle  := fRenderEngine.RenderPass.RenderPassHandle;
      aTask.SubPassIndex      := aSubPass;  //current pass index
      aTask.TaskJob           := TM_NONE;
      aTask.UploadData        := True;
      aTask.UploadResourceData:= True;
      aTask.GlobalRes         := fRenderEngine.GlobalRes ;
      aTask.FrameBufferHandle := fRenderEngine.RenderPass.FrameBufferHandles[ImageIndex];


      If Not RW.Active then
         RW.Active            := True;     //Setup the Worker

      fRenderEngine.GlobalRes.CurrentFrame := aFrame.FrameIndex;

      UploadGlobalDescriptorSet;
     (*
      For J:=0 to fRenderEngine.GraphicPipes.Count-1 do
      Begin
          GP :=  fRenderEngine.GraphicPipes.Items[J].GraphicPipe ;
          GP.CurrentFrameIndex := aFrame.FrameIndex;
          UploadGraphicPipeDescriptorSetData(GP);

          aTask.GraphicPipe := GP;

          UploadData(GP.UnderlayNodes);
          UploadData(GP.StaticNodes);
          UploadData(GP.DynamicNodes);
          UploadData(GP.OverlayNodes);

      end;
      *)
      if assigned(fRenderEngine.Linker) and fRenderEngine.Linker.MsgON then
         fRenderEngine.Linker.AddMsgToList('Begin Recording');

      aTask.TaskJob    := TM_BEGIN_RECORDING_FRAME;
      RW.CompleteTask(aTask);
    (*
      For J:=0 to fRenderEngine.GraphicPipes.Count-1 do
      Begin
          GP :=  fRenderEngine.GraphicPipes.Items[J].GraphicPipe ;

          If assigned(GP) and
             (GP.NodeCount>0)  then
          Begin

            GP.CurrentFrameIndex := fRenderEngine.Linker.CurrentPrepareFrame.FrameIndex;
            UploadGraphicPipeDescriptorSetData(GP);

            aTask.GraphicPipe := GP;

            aTask.TaskJob     := TM_BIND_PIPELINE;
            RW.CompleteTask(aTask);

            AddNodesToCommand(GP.UnderlayNodes);
            AddNodesToCommand(GP.StaticNodes);
            AddNodesToCommand(GP.DynamicNodes);
            AddNodesToCommand(GP.OverlayNodes);

          end;
      end;
     *)
      aTask.TaskJob    := TM_END_RECORDING_FRAME; //end recording the SECONDARY worker buffer
      RW.CompleteTask(aTask);

      if assigned(fRenderEngine.Linker) and fRenderEngine.Linker.MsgON then
         fRenderEngine.Linker.AddMsgToList('End Recording');

      aTask.TaskJob    := TM_EXECUTE_SECONDARY;   //execute SECONDARY buffer on PRIMARY frame buffer
      RW.CompleteTask(aTask);

      aTask.TaskJob    := TM_RESET;
      RW.CompleteTask(aTask);


end;



procedure TvgRenderWorkerThreadManager.StartPrepare(ImageIndex:Integer; aFrame: TvgFrame);
  Var
      VK_presentToClear  : TVkImageMemoryBarrier  ;
      VK_ImageSub        : TVkImageSubresourceRange;
      RP                 : TVkRenderPassBeginInfo;
      aRenderArea         : TVkRect2D;
      RenderImage        : TVkImage;
   //   CurrentPrepareFrame:TvgFrame;
   //   ImageIndex         :
begin

//  If not fActive then exit;
 // exit;
 if fPrepareFrameLock then
 Begin
   exit;
 End;

  Assert(assigned(fRenderEngine.Linker),'Vulkan Link not attached');
  Assert(assigned(fRenderEngine.RenderPass),'Render Pass not created');
  Assert((fRenderEngine.RenderPass.RenderPassHandle <> VK_NULL_HANDLE),'Render Pass not active');

  Assert(assigned(aFrame),'A Frame not provided.');
  Assert(assigned(aFrame.FrameCommandBuffer),'A Frame Command not provided.');

  Assert(assigned(fRenderEngine.Linker.ScreenDevice),'Internal Screen Device not available.');
  Assert(assigned(fRenderEngine.Linker.ScreenDevice.VulkanDevice),'Internal Screen Vulkan Device not available.');

  Assert(assigned(fRenderEngine.Linker.SwapChain),'Internal Swap Chain not available.');
  If not assigned(fRenderEngine.Linker.SwapChain.VulkanSwapChain) then exit;
  Assert(fRenderEngine.Linker.SwapChain.VulkanSwapChain.CountImages<>0,'No Images available in Swap Chain.');

  if fCurrentPrepareFrame <> aFrame then  //frame change
     fCurrentPrepareFrame := aFrame;

  FreeAllTasks;

  fPrepareFrameLock    := True;
  fWorkerRenderState   := RS_INITIAL;
  fImageIndex          := ImageIndex;


  fCurrentSubPassIndex := 0;

  FillChar(VK_ImageSub,SizeOf(TVkImageSubresourceRange),#0);
  FillChar(VK_presentToClear,SizeOf(TVkImageMemoryBarrier),#0);

  If (fRenderEngine.Linker.ScreenDevice.QueuePresentation.FamilyIndex <> fRenderEngine.Linker.ScreenDevice.QueueGraphics.FamilyIndex) then
  Begin

      VK_ImageSub.aspectMask     := TVkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT);
      VK_ImageSub.baseMipLevel   := 0;
      VK_ImageSub.levelCount     := 1;
      VK_ImageSub.baseArrayLayer := 0;
      VK_ImageSub.layerCount     := 1;

      VK_presentToClear.sType         := VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
      VK_presentToClear.pNext         := nil;
      VK_presentToClear.srcAccessMask := TVkAccessFlags(VK_ACCESS_MEMORY_READ_BIT);
      VK_presentToClear.dstAccessMask := TVkAccessFlags(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT);
      VK_presentToClear.oldLayout     := VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
      VK_presentToClear.newLayout     := VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
      VK_presentToClear.srcQueueFamilyIndex := fRenderEngine.Linker.ScreenDevice.QueuePresentation.FamilyIndex;   //check
      VK_presentToClear.dstQueueFamilyIndex := fRenderEngine.Linker.ScreenDevice.QueueGraphics.FamilyIndex;   //check
      VK_presentToClear.subresourceRange    := VK_ImageSub;

  end;

  aRenderArea.offset.x := 0;
  aRenderArea.offset.y := 0;

  FillChar(RP, SizeOf(TVkRenderPassBeginInfo),#0);
  RP.sType            := VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
  RP.pNext            := nil;
  RP.renderPass       := fRenderEngine.RenderPass.RenderPassHandle;


  if fRenderEngine.Linker.RenderTarget = RT_FRAME then
  Begin
    aRenderArea.extent.width := fRenderEngine.Linker.SwapChain.ImageWidth  * fRenderEngine.Linker.FrameResolution;
    aRenderArea.extent.height:= fRenderEngine.Linker.SwapChain.ImageHeight * fRenderEngine.Linker.FrameResolution;
    RenderImage              := fCurrentPrepareFrame.FrameImageBuffer.FrameBufferAttachment.ImageView.Handle ;
    RP.framebuffer           := fRenderEngine.RenderPass.FrameBufferHandles[fCurrentPrepareFrame.FrameIndex];
  end else
  Begin
    aRenderArea.extent.width := fRenderEngine.Linker.SwapChain.ImageWidth;
    aRenderArea.extent.height:= fRenderEngine.Linker.SwapChain.ImageHeight;
    RenderImage              := fRenderEngine.Linker.SwapChain.VulkanSwapChain.Images[fImageIndex].Handle ;
    RP.framebuffer           := fRenderEngine.RenderPass.FrameBufferHandles[fImageIndex];
  End;

  RP.renderArea       := aRenderArea;
  RP.clearValueCount  := fRenderEngine.RenderPass.ClearColCount;
  RP.pClearValues     := fRenderEngine.RenderPass.ClearColArray;

  If not fCurrentPrepareFrame.Active then
     fCurrentPrepareFrame.Active:=True;

  Try
    If Assigned(fCurrentPrepareFrame.FrameCommandBuffer.VulkanCommandBuffer) then
    Begin

     //   If (fCurrentPrepareFrame.FrameCommandBuffer.BufferState<>BS_INITIAL) then
        fCurrentPrepareFrame.FrameCommandBuffer.Reset;

        fCurrentPrepareFrame.FrameCommandBuffer.BeginRecording;

        If (fRenderEngine.Linker.ScreenDevice.QueuePresentation.FamilyIndex <> fRenderEngine.Linker.ScreenDevice.QueueGraphics.FamilyIndex) then
        Begin
          VK_presentToClear.image   := RenderImage;

          fCurrentPrepareFrame.FrameCommandBuffer.CmdPipelineBarrier(
                                TVkPipelineStageFlags(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),   //srcStageMask:TVkPipelineStageFlags;
                                TVkPipelineStageFlags(VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),   //dstStageMask:TVkPipelineStageFlags;
                                0,   //dependencyFlags:TVkDependencyFlags;
                                0,   //memoryBarrierCount:TvkUint32;
                                nil, //aMemoryBarriers:PVkMemoryBarrier;
                                0,   //bufferMemoryBarrierCount:TvkUint32
                                nil, //aBufferMemoryBarriers:PVkBufferMemoryBarrier
                                1,     //imageMemoryBarrierCount:TvkUint32
                                @VK_PresentToClear);  // aImageMemoryBarriers:PVkImageMemoryBarrier

        end;

        fCurrentPrepareFrame.FrameCommandBuffer.CmdBeginRenderPass( @RP, VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS);

        Assert(assigned(fRenderEngine.Linker),'Linker not connected');

        RenderRunTasks;

      //Finish job when threads return
    End;


  Except
     On E:EpvVulkanResultException do
     Begin
       fPrepareFrameLock := False;
       Raise(E);
     End;

  End;

end;

procedure TvgRenderWorkerThreadManager.Render_BeginRecording;
  Var TI : Integer;
begin

  TI := GetATask;
  fWorkerTaskList[TI].TaskJob := TM_BEGIN_RECORDING_FRAME;

  SendTaskToThreads(TI,CS_ALL);

  fWorkerRenderState := RS_BEGIN_RECORDING;
end;

procedure TvgRenderWorkerThreadManager.Render_EndRecording;

  Var TI : Integer;
begin

  TI := GetATask;
  fWorkerTaskList[TI].TaskJob := TM_END_RECORDING_FRAME;

  SendTaskToThreads(TI,CS_ALL);

  fWorkerRenderState := RS_END_RECORDING;

end;

procedure TvgRenderWorkerThreadManager.Render_Execute;
  Var TI:Integer;
begin

  TI := GetATask;
  fWorkerTaskList[TI].TaskJob := TM_EXECUTE_SECONDARY;

  SendTaskToThreads(TI,CS_ALL);

  fWorkerRenderState := RS_EXECUTESECONDARY;
end;

procedure TvgRenderWorkerThreadManager.Render_RenderLoop;
 Var  // TI  : Integer;
       GP  : TvgGraphicPipeline;
     //  I   : Integer;
     //  RN  : TvgRenderNode;
(*
    Procedure AddNodesToCommand(aRenderNodeList:TvgObjectDataList);
      Var I :Integer;
          RN:TvgObjectStore_Base;
          TI:Integer;

    Begin
      If not assigned( aRenderNodeList) then exit;
      If aRenderNodeList.Count=0 then exit;


      For I:=0 to aRenderNodeList.Count-1 do
      Begin
        RN:= aRenderNodeList.Items[I];

        If assigned(RN) then
        Begin
          TI := GetATask;

          fWorkerTaskList[TI].GlobalRes          := nil;
          fWorkerTaskList[TI].Resources          := nil;
          fWorkerTaskList[TI].UploadData         := False;
          fWorkerTaskList[TI].UploadResourceData := False;

          fWorkerTaskList[TI].RenderObject         := RN;
          fWorkerTaskList[TI].GraphicPipe        := GP;
          fWorkerTaskList[TI].TaskJob            := TM_RENDER_NODE;

          SendTaskToThreads(TI,CS_NEXT);

        End;


      End;


    //  SendTaskBlockToThreads(T0,TN);
    End;
    *)
Begin

  assert(assigned(fCurrentGraphicPipeline),'GraphicPipeline not assigned');

  GP := fCurrentGraphicPipeline;

  GP.CurrentFrameIndex := fRenderEngine.Linker.CurrentPrepareFrame.FrameIndex;

//  AddNodesToCommand(GP.UnderlayNodes);
//  AddNodesToCommand(GP.StaticNodes);
//  AddNodesToCommand(GP.DynamicNodes);
//  AddNodesToCommand(GP.OverlayNodes);

 (*
  If (fCurrentGraphicPipelineIndex < fRenderEngine.GraphicPipes.Count-1)   then
  Begin
    fCurrentGraphicPipeline := nil;
    fWorkerRenderState := RS_SET_SUBPASS;
    //loop back to set next pipeline
  End else
  If (fCurrentSubPassIndex < fRenderEngine.RenderPass.SubPasses.count-1) then
  Begin
    fCurrentGraphicPipelineIndex := 0;
    fWorkerRenderState := RS_BEGIN_RECORDING;
    //loop back to set next subpass
  End else
    fWorkerRenderState := RS_RENDER_NODES;
  *)

end;

procedure TvgRenderWorkerThreadManager.Render_RESET;
  Var TI:Integer;
begin

  TI := GetATask;
  fWorkerTaskList[TI].TaskJob := TM_RESET;

  SendTaskToThreads(TI,CS_ALL);

  fCurrentGraphicPipelineIndex :=0;
  fCurrentSubPassIndex         :=0;

  fWorkerRenderState := RS_RESET;
end;

procedure TvgRenderWorkerThreadManager.RenderRunTasks;
begin
  if not fPrepareFrameLock then exit;

  fPrepareFrameRunning := True;

  Render_UploadResourceData;
  Render_BeginRecording;
  Render_SetRenderSubPass;
  Render_SetPipeline;
  Render_RenderLoop;
  Render_EndRecording;
  Render_Execute;
  Render_Reset;

  fWorkerRenderState := RS_COMPLETE;


  (*

  Repeat

      Case fWorkerRenderState of
          RS_INITIAL             : Render_UploadResourceData;
          RS_RES_UPLOAD          : Render_BeginRecording;
          RS_BEGIN_RECORDING     : Render_SetRenderSubPass;
          RS_SET_SUBPASS         : Render_SetPipeline;
          RS_SET_GRAPHICPIPELINE : Render_RenderLoop;
          RS_RENDER_NODES        : Render_EndRecording      ;
          RS_END_RECORDING       : Render_Execute  ;
          RS_EXECUTESECONDARY    : Render_Reset  ;
          RS_RESET               : fWorkerRenderState := RS_COMPLETE;//  FinishPrepare;
          RS_COMPLETE            : fWorkerRenderState := RS_INITIAL;
        else
          fWorkerRenderState := RS_INITIAL;
      End;

  Until fWorkerRenderState = RS_COMPLETE;
  *)

end;

procedure TvgRenderWorkerThreadManager.Render_SetPipeline;
 // Var //TI:Integer;
     // GP:TvgGraphicPipeline;

begin
  (*

  If (fCurrentGraphicPipelineIndex < fRenderEngine.GraphicPipes.count-1) then
  Begin
      For J := fCurrentGraphicPipelineIndex to fRenderEngine.GraphicPipes.count-1 do
      ///find next valid pipe to bind/render with
      Begin

          If (fRenderEngine.GraphicPipes.Items[J].SubPassIndex = fCurrentSubPassIndex) then
          //SubPass Match
          Begin

            GP := fRenderEngine.GraphicPipes.Items[J].GraphicPipe;

            If assigned(GP) and (GP.NodeCount>0) then
            Begin

                TI := GetATask;

                fWorkerTaskList[TI].GraphicPipe := GP;
                fWorkerTaskList[TI].TaskJob     := TM_BIND_PIPELINE;
                SendTaskToThreads(TI, CS_ALL);

                fCurrentGraphicPipeline      := GP;
                fCurrentGraphicPipelineIndex := J + 1;
                fWorkerRenderState           := RS_SET_GRAPHICPIPELINE;
                //set state for node render
                Break;
            end;
          end;

      End;


  end else
  Begin
    fWorkerRenderState           :=  RS_RENDER_NODES;
    fCurrentGraphicPipelineIndex := 0;
    fCurrentSubPassIndex         := 0;

  //  Render_RunNextStage;
    //loop back for next subpass
  End;

  *)

end;

procedure TvgRenderWorkerThreadManager.Render_SetRenderSubPass;

begin

  fCurrentSubPassIndex := 0;
  fWorkerRenderState := RS_SET_SUBPASS;
//  Render_RunNextStage; //should remove later

end;

procedure TvgRenderWorkerThreadManager.Render_UploadResourceData;
  Var TI : Integer;
begin

  If assigned(fRenderEngine.GlobalRes) then
  Begin
    TI := GetATask;
    fWorkerTaskList[TI].Resources := fRenderEngine.GlobalRes;
    fWorkerTaskList[TI].TaskJob   := TM_UPLOADRESOURCEDATA;
    SendTaskToThreads(TI,CS_NEXT);
  end;
(*
  For I:=0 to fRenderEngine.GraphicPipes.Count-1 do
    If assigned(fRenderEngine.GraphicPipes.Items[I].GraphicPipe) and
       assigned(fRenderEngine.GraphicPipes.Items[I].GraphicPipe.GraphicPipeRes) then
    Begin
      TI := GetATask;
      fWorkerTaskList[TI].Resources := fRenderEngine.GraphicPipes.Items[I].GraphicPipe.GraphicPipeRes;
      fWorkerTaskList[TI].TaskJob   := TM_UPLOADRESOURCEDATA;
      SendTaskToThreads(TI,CS_NEXT);
    End;
 *)
  fWorkerRenderState := RS_RES_UPLOAD;
end;

function TvgRenderWorkerThreadManager.SendFrameTask(  aFrameTask: TvgFrameTask): Boolean;
begin
  Result := False;


end;

Function TvgRenderWorkerThreadManager.SendTaskToThreads(TaskIndex: Integer; SendType:TvgCommStateSendType; SendIndex:Integer=-1):Boolean;
  Var L:Integer;
      MinIndex:Integer;

   Procedure SendALL_MULTI;
     Var I:Integer;
   Begin
     Result := True;

     for I := 0 to L-1 do
       if fWorkerThreads[I].Thread.SendToThread(fWorkerTaskList[TaskIndex]) then
       Begin
         fWorkerThreads[I].TaskCount :=  fWorkerThreads[I].TaskCount + 1;
         fWorkerTaskCount := fWorkerTaskCount + 1;
       End;

   End;

   Procedure SendNext_MULTI;
     Var I,MinTask,MinIndex:Integer;
   Begin
          MinTask  := High(Integer);
          MinIndex := -1;

          for I := 0 to L-1 do
          Begin
                  if (I<>fLastTaskIndex) and (FWorkerThreads[I].TaskCount < MinTask) then
                  Begin
                     MinIndex    := I;
                     MinTask     := FWorkerThreads[I].TaskCount;
                  End;
          end;

          If  (MinIndex<0) or (MinIndex>=L) then
               MinIndex := 0;

          If fWorkerThreads[MinIndex].Thread.SendToThread(fWorkerTaskList[TaskIndex]) then
          Begin
            FWorkerThreads[MinIndex].TaskCount := FWorkerThreads[MinIndex].TaskCount +1;
            fWorkerTaskCount := fWorkerTaskCount + 1;
            fLastTaskIndex   := MinIndex;
            Result           := True;
          End else
          Begin
            for I := 0 to L-1 do
              if (I<>MinIndex) and FWorkerThreads[I].Thread.SendToThread(fWorkerTaskList[TaskIndex]) then
              Begin
                FWorkerThreads[I].TaskCount := FWorkerThreads[I].TaskCount + 1;
                fWorkerTaskCount            := fWorkerTaskCount + 1;
                fLastTaskIndex              := I;
                Result                      := True ;
                Break;
              End;
          End;

   End;

   Procedure SendSpecific_MULTI;
   Begin
      If (SendIndex>=0) and (SendIndex >= L) then exit;

      if FWorkerThreads[SendIndex].Thread.SendToThread(fWorkerTaskList[TaskIndex]) then
      Begin
        FWorkerThreads[SendIndex].TaskCount := FWorkerThreads[MinIndex].TaskCount +1;
        fWorkerTaskCount := fWorkerTaskCount + 1;
        fLastTaskIndex   := SendIndex;
        Result := True ;
      End;

   End;

begin

   Result := False;
   if TaskIndex<0 then exit;

//   ProcessCompletedTasks;

  if fThreadMode=TM_MULTITASK then
  Begin
     L:=Length(self.fWorkerThreads);
     if L=0 then exit;

     case SendType of
       CS_ALL      : SendALL_MULTI  ;
       CS_NEXT     : SendNext_MULTI;
       CS_SPECIFIC : SendSpecific_MULTI;
       else
         SendNext_MULTI;
     end;
  End else
  if fThreadMode=TM_SINGLE then
  Begin
    If not assigned(fRenderWorker) then exit;
    fRenderWorker.CompleteTask(fWorkerTaskList[TaskIndex]);
  //  fWorkerTaskCount := fWorkerTaskCount + 1;

  End;

end;

procedure TvgRenderWorkerThreadManager.SetThreadMode( const Value: TvgThreadMode);
begin
  If Value = fThreadMode then exit;
  CleanUpAndFreeWorkers;

  fThreadMode := Value;
end;

{ TvgCommThread_RenderEngine }

procedure TvgCommThread_RenderEngine.AddSceneRenderCommands(  ImageIndex: TvkUint32; aFrame: TvgFrame; aSubPass: TvkUint32);
begin


end;

procedure TvgCommThread_RenderEngine.BuildAndSetUpWorkers;
Begin

end;

constructor TvgCommThread_RenderEngine.Create(AOwner: TComponent);
//  Var     DI :  TvgDescriptorItem;
   //       L,I :   Integer;
       //   M:   TvgResource_Data_4x4MatrixD;
begin
  inherited;

  //ADD as properties
  fMsgCount := 10;
 (*
  If (fGlobalRes.Descriptors.Count=0) then
  Begin
      DI := fGlobalRes.Descriptors.Add ;
      If assigned(DI) then
      Begin
        DI.DescriptorName := TvgDescriptor_UBO_4x4MatrixD.GetPropertyName;
        If assigned(DI.Descriptor) then
        Begin
          DI.Name                    := 'ViewProjection';
          DI.Descriptor.Name         := 'ViewProj';
          DI.Descriptor.ResourceType := RT_VIEWPROJECTMAT;

          L :=  TvgDescriptor_UBO_4x4MatrixD(DI.Descriptor).Count;
          For I:=0 to L-1 do
          Begin
            TvgDescriptor_UBO_4x4MatrixD(DI.Descriptor).Items[I] := TvgMatrix4x4D.Identity;
          end;
        end;
      End;
  end;
*)
  fThreadMode := TM_SINGLE;


end;

procedure TvgCommThread_RenderEngine.CreateRenderPass;
begin
  If assigned(fRenderPass) then exit;

  fRenderPass := TvgRenderPass.Create(self);
end;

destructor TvgCommThread_RenderEngine.Destroy;
begin
(*
  if assigned(fWorkerThreadManager) then
  Begin
    fWorkerThreadManager.Terminate;
    fWorkerThreadManager.WaitFor;

    FreeAndNil(fWorkerThreadManager);
  End;
 *)
  inherited;
end;

procedure TvgCommThread_RenderEngine.FinishRenderEnginePrepare;
begin
  fRenderLock := False;

 // inherited;

end;

procedure TvgCommThread_RenderEngine.HandlePrepareFrameMessage( const Task: TvgFrameComplete);
begin

  if not fRenderLock then exit;

  if assigned(Linker)and Linker.MsgON then
     Linker.AddMsgToList(Task.TaskComment);

  If assigned(Task.Frame ) and (task.PrepareFrameStatus=FS_PREPAREFRAME_COMPLETE) then
  Begin
    fRenderLock:=False;
    if assigned(Linker) and Linker.MsgON then
      Linker.AddMsgToList('Finish Prepare Frame Triggered') ;

    Task.Frame.FinishFramePrepare;    //looping back up the tree NEED to force Finish
  end;

end;

Function TvgCommThread_RenderEngine.SetDisabled:Boolean;
begin
  inherited;
  Result := True;

  if assigned(fWorkerThreadManager)  then
  Begin
     fWorkerThreadManager.Terminate;
     fWorkerThreadManager.WaitFor;
     FreeAndNil(fWorkerThreadManager);

  //   FreeAndNil(fWorkerMsgQueue);
  End;
end;

Function TvgCommThread_RenderEngine.SetEnabled:Boolean;
begin


  inherited;
  Result := True;

  //simple View/Proj Matrix

  fWorkerThreadManager := TvgRenderWorkerThreadManager.Create(self, TMessageQueue<TvgFrameTask>.Create(fMsgCount, nil),
                                                                    TMessageQueue<TvgFrameComplete>.Create(fMsgCount, HandlePrepareFrameMessage),
                                                                    True,
                                                                    True,
                                                                    fRenderWorkerCount,
                                                                    fThreadMode);

end;

procedure TvgCommThread_RenderEngine.SetThreadMode(const Value: TvgThreadMode);
begin
  If fThreadMode = Value then exit;
  SetDisabled;
  fThreadMode := Value;
end;

procedure TvgCommThread_RenderEngine.StartRenderEnginePrepare(ImageIndex: Integer; aFrame: TvgFrame);
  Var FT : TvgFrameTask;
begin
  //inherited;
  if not assigned(fWorkerThreadManager) then exit;

  Assert(assigned(aFrame),'FRAME not assigned') ;
//  Assert((ImageIndex>=0), 'Image Index NOT valid') ;

  if fRenderLock then exit;
  fRenderLock:=True;

  FT.FrameJob   := FJ_PREPAREFRAME_START;
  FT.Frame      := aFrame;
  FT.ImageIndex := ImageIndex;

  fWorkerThreadManager.SendToThread(FT) ;

  if assigned(Linker) and (Linker.MsgON) then
    Linker.AddMsgToList('Start Prepare Frame Triggered')  ;


end;

Initialization

Finalization


end.
