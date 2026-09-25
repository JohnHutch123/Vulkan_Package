

unit Vulkan_MemoryPool;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.DateUtils,
  System.SyncObjs,
  System.Math,
  Vulkan,
  PasVulkan.Types,
  PasVulkan.Framework,
  Vulkan_Components;

const
  DEFAULT_POOL_SIZE = 16 * 1024 * 1024;  // 16MB default pool size
  MIN_BLOCK_SIZE = 256;                   // Minimum allocation size
  DEFAULT_ALIGNMENT = 256;                // Default memory alignment
  DEFRAG_THRESHOLD = 30;                  // Defragmentation threshold percentage

type
  // Memory block status
  TMemoryBlockState = (
    mbsFree,      // Block is available
    mbsAllocated, // Block is in use
    mbsFragmented // Block needs defragmentation
  );

  // Memory block structure
  PMemoryBlock = ^TMemoryBlock;
  TMemoryBlock = record
    Offset: TVkDeviceSize;
    Size: TVkDeviceSize;
    Memory: TVkDeviceMemory;
    State: TMemoryBlockState;
    Next: PMemoryBlock;
    Previous: PMemoryBlock;
    AllocationID: Cardinal;
    LastUsed: TDateTime;
    Alignment: TVkDeviceSize;
  end;

  // Pool statistics
  TPoolStats = record
    TotalSize: TVkDeviceSize;
    UsedSize: TVkDeviceSize;
    FreeSize: TVkDeviceSize;
    BlockCount: Integer;
    FragmentationPercent: Single;
    LargestFreeBlock: TVkDeviceSize;
    AllocationCount: Integer;
  end;

  // Memory allocation result
  TMemoryAllocationResult = record
    Success: Boolean;
    Memory: TVkDeviceMemory;
    Offset: TVkDeviceSize;
    Size: TVkDeviceSize;
    Block: PMemoryBlock;
  end;

  TvgMemoryPool = class
  private
    fDevice: TvgLogicalDevice;
    fMemoryTypeIndex: Cardinal;
    fPoolSize: TVkDeviceSize;
    fAlignment: TVkDeviceSize;
    fBlocks: TList<PMemoryBlock>;
    fLock: TCriticalSection;
    fStats: TPoolStats;
    fLastDefrag: TDateTime;
    fAllocationCounter: Cardinal;
    fVulkanMemory: TVkDeviceMemory;

    procedure UpdateStats;
    function AlignSize(Size: TVkDeviceSize): TVkDeviceSize;
    function FindFreeBlock(Size: TVkDeviceSize; Alignment: TVkDeviceSize): PMemoryBlock;
    function SplitBlock(Block: PMemoryBlock; Size: TVkDeviceSize): PMemoryBlock;
    procedure MergeAdjacentFreeBlocks;
    function NeedsDefragmentation: Boolean;
    procedure AllocateVulkanMemory;
    procedure ReleaseVulkanMemory;

  protected
    function CreateNewBlock(Size: TVkDeviceSize): PMemoryBlock;
    procedure FreeBlock(Block: PMemoryBlock);

  public
    constructor Create(ADevice: TvgLogicalDevice;
                      AMemoryTypeIndex: Cardinal;
                      APoolSize: TVkDeviceSize = DEFAULT_POOL_SIZE;
                      AAlignment: TVkDeviceSize = DEFAULT_ALIGNMENT);
    destructor Destroy; override;

    // Main allocation method
    function Allocate(Size: TVkDeviceSize;
                     Alignment: TVkDeviceSize = DEFAULT_ALIGNMENT): TMemoryAllocationResult;

    // Memory management methods
    procedure Free(Memory: TVkDeviceMemory; Offset: TVkDeviceSize);
    procedure Defragment;
    procedure Trim;
    function GetMemoryTypeProperties: TVkMemoryPropertyFlags;

    // Statistics and information
    function GetAllocationCount: Cardinal;
    function GetLargestFreeBlock: TVkDeviceSize;
    function GetFragmentationPercentage: Single;

    property Stats: TPoolStats read fStats;
  end;

 // Pool manager that handles different memory types

  TvgMemoryPoolManager = class
  private
    fDevice: TvgLogicalDevice;
    fPools: array[0..31] of TvgMemoryPool; // Max 32 memory types in Vulkan
    fLock: TCriticalSection;
    function GetPool(MemoryTypeIndex: Cardinal): TvgMemoryPool;

  public
    constructor Create(ADevice: TvgLogicalDevice);
    destructor Destroy; override;

    // Main allocation method
    function AllocateMemory(const AllocateInfo: TVkMemoryAllocateInfo;
                            out Memory: TVkDeviceMemory): TVkResult;
    // Free memory
    procedure FreeMemory(Memory: TVkDeviceMemory);

    // Management methods
    procedure DefragmentAll;
    procedure TrimAll;
    function GetStats(MemoryTypeIndex: Cardinal): TPoolStats;
  end;


// Add this after your existing type declarations
  TvgMemoryManager = class(TvgBaseComponent)
  private
    fPoolManager: TvgMemoryPoolManager;
    fLogicalDevice: TvgLogicalDevice;
    fAllocationSize: TVkDeviceSize;
    fStatsUpdateInterval: Cardinal;
    fLastStatsUpdate: TDateTime;

    procedure SetLogicalDevice(const Value: TvgLogicalDevice);
    function GetPoolStats(MemoryTypeIndex: Cardinal): TPoolStats;
    procedure UpdateStats;

  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure SetDisabled; override;
    procedure SetEnabled(aComp: TvgBaseComponent = nil); override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function AllocateMemory(const AllocInfo: TVkMemoryAllocateInfo;
                           out Memory: TVkDeviceMemory): TVkResult;
    procedure FreeMemory(Memory: TVkDeviceMemory);
    procedure DefragmentPools;
    procedure TrimPools;

  published
    property LogicalDevice: TvgLogicalDevice read fLogicalDevice write SetLogicalDevice;
    property AllocationSize: TVkDeviceSize read fAllocationSize write fAllocationSize default DEFAULT_POOL_SIZE;
    property StatsUpdateInterval: Cardinal read fStatsUpdateInterval write fStatsUpdateInterval default 1000;
  end;

implementation

{ TvgMemoryPool }

constructor TvgMemoryPool.Create(ADevice: TvgLogicalDevice;
                               AMemoryTypeIndex: Cardinal;
                               APoolSize: TVkDeviceSize;
                               AAlignment: TVkDeviceSize);
begin
  inherited Create;

  fDevice := ADevice;
  fMemoryTypeIndex := AMemoryTypeIndex;
  fPoolSize := APoolSize;
  fAlignment := AAlignment;
  fBlocks := TList<PMemoryBlock>.Create;
  fLock := TCriticalSection.Create;
  fAllocationCounter := 0;

  // Initialize statistics
  FillChar(fStats, SizeOf(TPoolStats), 0);
  fLastDefrag := Now;

  // Allocate initial Vulkan memory
  AllocateVulkanMemory;

  // Create initial free block
  CreateNewBlock(fPoolSize);
  UpdateStats;
end;

function TvgMemoryPool.CreateNewBlock(Size: TVkDeviceSize): PMemoryBlock;
begin

end;

procedure TvgMemoryPool.Defragment;
begin

end;

destructor TvgMemoryPool.Destroy;
begin
  fLock.Enter;
  try
    // Free all blocks
    for var Block in fBlocks do
      Dispose(Block);
    FreeAndNil(fBlocks);

    // Release Vulkan memory
    ReleaseVulkanMemory;
  finally
    fLock.Leave;
    FreeAndNil(fLock);
  end;

  inherited;
end;

procedure TvgMemoryPool.AllocateVulkanMemory;
var
  AllocInfo: TVkMemoryAllocateInfo;
  aResult: TVkResult;
begin
  FillChar(AllocInfo, SizeOf(AllocInfo), 0);
  AllocInfo.sType := VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
  AllocInfo.allocationSize := fPoolSize;
  AllocInfo.memoryTypeIndex := fMemoryTypeIndex;

  aResult := vkAllocateMemory(fDevice.VulkanDevice.Handle,
                            @AllocInfo,
                            nil,
                            @fVulkanMemory);

  if aResult <> VK_SUCCESS then
    raise EvgVulkanException.Create('Failed to allocate Vulkan memory for pool');
end;

procedure TvgMemoryPool.ReleaseVulkanMemory;
begin
  if fVulkanMemory <> VK_NULL_HANDLE then
  begin
    vkFreeMemory(fDevice.VulkanDevice.Handle, fVulkanMemory, nil);
    fVulkanMemory := VK_NULL_HANDLE;
  end;
end;

function TvgMemoryPool.AlignSize(Size: TVkDeviceSize): TVkDeviceSize;
begin
  Result := (Size + fAlignment - 1) and not (fAlignment - 1);
end;

function TvgMemoryPool.Allocate(Size: TVkDeviceSize;
                               Alignment: TVkDeviceSize): TMemoryAllocationResult;
begin
  FillChar(Result, SizeOf(Result), 0);

  fLock.Enter;
  try
    // Align the requested size
    var AlignedSize := AlignSize(Size);

    // Find a suitable block
    var Block := FindFreeBlock(AlignedSize, Alignment);
    if Block = nil then
    begin
      // Try defragmentation if needed
      if NeedsDefragmentation then
      begin
        Defragment;
        Block := FindFreeBlock(AlignedSize, Alignment);
      end;

      // If still no block, try to create new one
      if Block = nil then
        Block := CreateNewBlock(Max(AlignedSize, fPoolSize));
    end;

    if Block <> nil then
    begin
      // Split block if it's too large
      if (Block.Size > AlignedSize + MIN_BLOCK_SIZE) then
        SplitBlock(Block, AlignedSize);

      // Mark block as allocated
      Block.State := mbsAllocated;
      Block.LastUsed := Now;
      Block.AllocationID := InterlockedIncrement(fAllocationCounter);
      Block.Alignment := Alignment;

      // Prepare result
      Result.Success := True;
      Result.Memory := fVulkanMemory;
      Result.Offset := Block.Offset;
      Result.Size := Block.Size;
      Result.Block := Block;

      UpdateStats;
    end;
  finally
    fLock.Leave;
  end;
end;

procedure TvgMemoryPool.Free(Memory: TVkDeviceMemory; Offset: TVkDeviceSize);
begin
  if Memory <> fVulkanMemory then
    Exit;

  fLock.Enter;
  try
    // Find block by offset
    for var Block in fBlocks do
    begin
      if (Block.State = mbsAllocated) and (Block.Offset = Offset) then
      begin
        FreeBlock(Block);
        UpdateStats;
        Break;
      end;
    end;
  finally
    fLock.Leave;
  end;
end;

procedure TvgMemoryPool.FreeBlock(Block: PMemoryBlock);
begin
  Block.State := mbsFree;
  Block.LastUsed := 0;
  Block.AllocationID := 0;

  // Try to merge with adjacent blocks
  MergeAdjacentFreeBlocks;
end;

function TvgMemoryPool.GetAllocationCount: Cardinal;
begin

end;

function TvgMemoryPool.GetFragmentationPercentage: Single;
begin

end;

function TvgMemoryPool.GetLargestFreeBlock: TVkDeviceSize;
begin

end;

function TvgMemoryPool.GetMemoryTypeProperties: TVkMemoryPropertyFlags;
begin

end;

procedure TvgMemoryPool.MergeAdjacentFreeBlocks;
var
  Current, Next: PMemoryBlock;
  i: Integer;
begin
  i := 0;
  while i < fBlocks.Count - 1 do
  begin
    Current := fBlocks[i];
    Next := fBlocks[i + 1];

    if (Current.State = mbsFree) and (Next.State = mbsFree) and
       (Current.Offset + Current.Size = Next.Offset) then
    begin
      // Merge blocks
      Current.Size := Current.Size + Next.Size;
      Current.Next := Next.Next;
      if Next.Next <> nil then
        Next.Next.Previous := Current;

      fBlocks.Delete(i + 1);
      Dispose(Next);
      Continue;
    end;

    Inc(i);
  end;
end;

function TvgMemoryPool.NeedsDefragmentation: Boolean;
const
  // Defragmentation thresholds
  HIGH_FRAGMENTATION_PERCENT = 30.0;      // 30% fragmentation
  CRITICAL_FRAGMENTATION_PERCENT = 50.0;   // 50% fragmentation
  MIN_FREE_BLOCK_THRESHOLD = 5;            // Minimum number of free blocks before considering defrag
  TIME_BETWEEN_DEFRAGS = 5 * 60;          // 5 minutes minimum between defrags
  LARGE_ALLOCATION_THRESHOLD = 1024 * 1024; // 1MB - size considered "large"
var
  CurrentTime: TDateTime;
  TimeSinceLastDefrag: Double;
  ConsecutiveSmallBlocks: Integer;
  PrevBlock, Block: PMemoryBlock;
  AvgFreeBlockSize: TVkDeviceSize;
  LargeBlocksNeeded: Boolean;
begin
  Result := False;

  fLock.Enter;
  try
    // Skip check if pool is too small or empty
    if (fBlocks.Count < 2) or (fStats.TotalSize < MIN_BLOCK_SIZE * 2) then
      Exit(False);

    CurrentTime := Now;
    TimeSinceLastDefrag := SecondsBetween(CurrentTime, fLastDefragTime);

    // Don't defragment too frequently
    if TimeSinceLastDefrag < TIME_BETWEEN_DEFRAGS then
      Exit(False);

    // Always defragment if fragmentation is critical
    if fStats.FragmentationPercent >= CRITICAL_FRAGMENTATION_PERCENT then
      Exit(True);

    // Check if we have too many small, fragmented blocks
    ConsecutiveSmallBlocks := 0;
    AvgFreeBlockSize := fStats.FreeSize div fStats.FreeBlockCount;
    LargeBlocksNeeded := False;

    // Analyze block patterns
    for var i := 0 to fBlocks.Count - 1 do
    begin
      Block := fBlocks[i];

      // Skip allocated blocks
      if Block.State = mbsAllocated then
        Continue;

      // Check for small blocks pattern
      if Block.Size < MIN_BLOCK_SIZE then
        Inc(ConsecutiveSmallBlocks)
      else
        ConsecutiveSmallBlocks := 0;

      // Check if we have pending large allocations that need bigger blocks
      for var PendingAlloc in fPendingAllocations do
      begin
        if (PendingAlloc.Size > LARGE_ALLOCATION_THRESHOLD) and
           (PendingAlloc.Size > fStats.LargestFreeBlock) then
        begin
          LargeBlocksNeeded := True;
          Break;
        end;
      end;

      // Check for fragmentation between blocks
      if i > 0 then
      begin
        PrevBlock := fBlocks[i-1];
        if (PrevBlock.State = mbsFree) and (Block.State = mbsFree) and
           (PrevBlock.Offset + PrevBlock.Size < Block.Offset) then
        begin
          // Gap between free blocks indicates fragmentation
          Exit(True);
        end;
      end;
    end;

    // Determine if defragmentation is needed based on collected metrics
    Result :=
      // High fragmentation with sufficient free blocks
      ((fStats.FragmentationPercent >= HIGH_FRAGMENTATION_PERCENT) and
       (fStats.FreeBlockCount >= MIN_FREE_BLOCK_THRESHOLD)) or

      // Too many consecutive small blocks
      (ConsecutiveSmallBlocks >= MIN_FREE_BLOCK_THRESHOLD) or

      // Large blocks needed but not available due to fragmentation
      (LargeBlocksNeeded and (fStats.FreeSize > LARGE_ALLOCATION_THRESHOLD)) or

      // Average free block size is too small compared to total free space
      ((AvgFreeBlockSize < MIN_BLOCK_SIZE) and
       (fStats.FreeSize > MIN_BLOCK_SIZE * MIN_FREE_BLOCK_THRESHOLD)) or

      // Free space is heavily fragmented
      (fStats.FreeBlockCount > (fStats.FreeSize div MIN_BLOCK_SIZE) * 2);

    // Update last check time if defragmentation is needed
    if Result then
      fLastDefragCheckTime := CurrentTime;

  finally
    fLock.Leave;
  end;
end;

function TvgMemoryPool.FindFreeBlock(Size: TVkDeviceSize;
                                    Alignment: TVkDeviceSize): PMemoryBlock;
var
  AlignedOffset: TVkDeviceSize;
begin
  Result := nil;

  // First fit strategy
  for var Block in fBlocks do
  begin
    if (Block.State = mbsFree) then
    begin
      // Calculate aligned offset
      AlignedOffset := (Block.Offset + Alignment - 1) and not (Alignment - 1);

      // Check if block is large enough including alignment
      if (Block.Size >= Size + (AlignedOffset - Block.Offset)) then
      begin
        Result := Block;
        Break;
      end;
    end;
  end;
end;

function TvgMemoryPool.SplitBlock(Block: PMemoryBlock;
                                 Size: TVkDeviceSize): PMemoryBlock;
var
  NewBlock: PMemoryBlock;
begin
  // Create new block for remaining space
  New(NewBlock);
  NewBlock.Offset := Block.Offset + Size;
  NewBlock.Size := Block.Size - Size;
  NewBlock.Memory := Block.Memory;
  NewBlock.State := mbsFree;
  NewBlock.Previous := Block;
  NewBlock.Next := Block.Next;
  NewBlock.AllocationID := 0;
  NewBlock.LastUsed := 0;

  // Update original block
  Block.Size := Size;
  Block.Next := NewBlock;

  // Insert new block into list
  fBlocks.Insert(fBlocks.IndexOf(Block) + 1, NewBlock);

  Result := Block;
end;

procedure TvgMemoryPool.Trim;
begin

end;

procedure TvgMemoryPool.UpdateStats;
var
  Block: PMemoryBlock;
  FreeRegions: Integer;
  UsedRegions: Integer;
  LargestFree: TVkDeviceSize;
  TotalFreeSize: TVkDeviceSize;
  LastBlockEnd: TVkDeviceSize;
  FragmentedSpace: TVkDeviceSize;
begin
  fLock.Enter;
  try
    // Initialize counters
    FreeRegions := 0;
    UsedRegions := 0;
    LargestFree := 0;
    TotalFreeSize := 0;
    FragmentedSpace := 0;
    LastBlockEnd := 0;

    // Reset stats
    FillChar(fStats, SizeOf(TPoolStats), 0);
    fStats.TotalSize := fPoolSize;

    // Analyze each block
    for Block in fBlocks do
    begin
      // Check for fragmentation between blocks
      if LastBlockEnd > 0 then
        FragmentedSpace := FragmentedSpace + (Block.Offset - LastBlockEnd);

      case Block.State of
        mbsFree:
          begin
            Inc(FreeRegions);
            TotalFreeSize := TotalFreeSize + Block.Size;
            LargestFree := Max(LargestFree, Block.Size);
          end;

        mbsAllocated:
          begin
            Inc(UsedRegions);
            fStats.UsedSize := fStats.UsedSize + Block.Size;
          end;

        mbsFragmented:
          begin
            Inc(FreeRegions);
            TotalFreeSize := TotalFreeSize + Block.Size;
            FragmentedSpace := FragmentedSpace + Block.Size;
          end;
      end;

      LastBlockEnd := Block.Offset + Block.Size;
    end;

    // Update statistics
    fStats.BlockCount := fBlocks.Count;
    fStats.FreeSize := TotalFreeSize;
    fStats.AllocatedBlockCount := UsedRegions;
    fStats.FreeBlockCount := FreeRegions;
    fStats.LargestFreeBlock := LargestFree;

    // Calculate fragmentation percentage
    if fStats.TotalSize > 0 then
      fStats.FragmentationPercent := (FragmentedSpace / fStats.TotalSize) * 100.0
    else
      fStats.FragmentationPercent := 0;

  finally
    fLock.Leave;
  end;
end;


{ Implementation of smart allocation strategies }

constructor TvgMemoryPool.Create(ADevice: TvgLogicalDevice;
                               AMemoryTypeIndex: Cardinal;
                               APoolSize: TVkDeviceSize);
begin
  inherited Create;
  fDevice := ADevice;
  fMemoryTypeIndex := AMemoryTypeIndex;
  fPoolSize := APoolSize;
  fBlocks := TList<PMemoryBlock>.Create;
  fLock := TCriticalSection.Create;

  // Initialize first block
  CreateNewBlock(fPoolSize);
  UpdateStats;
end;

function TvgMemoryPool.Allocate(Size: TVkDeviceSize;
                               Alignment: TVkDeviceSize;
                               out Memory: TVkDeviceMemory;
                               out Offset: TVkDeviceSize): Boolean;
begin
  fLock.Enter;
  try
    // Find suitable block
    var Block := FindFreeBlock(Size, Alignment);
    if Block = nil then
    begin
      // Create new block if needed
      Block := CreateNewBlock(Max(Size, fPoolSize));
      if Block = nil then
        Exit(False);
    end;

    // Allocate from block
    Memory := Block.Memory;
    Offset := Block.Offset;
    Block.State := mbsAllocated;
    Block.LastUsed := Now;

    UpdateStats;
    Result := True;

    // Check if defragmentation is needed
    if fStats.FragmentationPercent > 30 then
      DefragmentIfNeeded;
  finally
    fLock.Leave;
  end;
end;

procedure TvgMemoryPool.Defragment;
begin
  fLock.Enter;
  try
    // Collect free blocks
    var FreeBlocks := TList<PMemoryBlock>.Create;
    try
      for var Block in fBlocks do
        if Block.State = mbsFree then
          FreeBlocks.Add(Block);

      // Merge adjacent free blocks
      for var i := 0 to FreeBlocks.Count - 2 do
      begin
        var Current := FreeBlocks[i];
        var Next := FreeBlocks[i + 1];

        if Current.Offset + Current.Size = Next.Offset then
        begin
          // Merge blocks
          Current.Size := Current.Size + Next.Size;
          Current.Next := Next.Next;
          if Next.Next <> nil then
            Next.Next.Previous := Current;
          fBlocks.Remove(Next);
          Dispose(Next);
        end;
      end;
    finally
      FreeBlocks.Free;
    end;

    UpdateStats;
  finally
    fLock.Leave;
  end;
end;

{ TvgMemoryPoolManager }

constructor TvgMemoryPoolManager.Create(ADevice: TvgLogicalDevice);
begin
  inherited Create;
  fDevice := ADevice;
  fLock := TCriticalSection.Create;

  // Initialize memory pools
  FillChar(fPools, SizeOf(fPools), 0);
end;

destructor TvgMemoryPoolManager.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(fPools) do
  begin
    if fPools[i] <> nil then
      fPools[i].Free;
  end;
  fLock.Free;
  inherited;
end;

function TvgMemoryPoolManager.GetPool(MemoryTypeIndex: Cardinal): TvgMemoryPool;
begin
  if MemoryTypeIndex > High(fPools) then
    raise Exception.CreateFmt('Invalid memory type index: %d', [MemoryTypeIndex]);

  fLock.Enter;
  try
    if fPools[MemoryTypeIndex] = nil then
    begin
      // Create a new memory pool for this memory type
      fPools[MemoryTypeIndex] := TvgMemoryPool.Create(fDevice, MemoryTypeIndex);
    end;
    Result := fPools[MemoryTypeIndex];
  finally
    fLock.Leave;
  end;
end;

function TvgMemoryPoolManager.AllocateMemory(const AllocateInfo: TVkMemoryAllocateInfo;
                                             out Memory: TVkDeviceMemory): TVkResult;
var
  Pool: TvgMemoryPool;
begin
  Pool := GetPool(AllocateInfo.memoryTypeIndex);
  Result := Pool.AllocateMemory(AllocateInfo, Memory);
end;

procedure TvgMemoryPoolManager.FreeMemory(Memory: TVkDeviceMemory);
var
  MemoryTypeIndex: Cardinal;
  Pool: TvgMemoryPool;
begin
  // Find the memory type index for the given memory
  MemoryTypeIndex := fDevice.GetMemoryTypeIndex(Memory);
  Pool := GetPool(MemoryTypeIndex);
  Pool.FreeMemory(Memory);
end;

procedure TvgMemoryPoolManager.DefragmentAll;
var
  i: Integer;
begin
  fLock.Enter;
  try
    for i := 0 to High(fPools) do
    begin
      if fPools[i] <> nil then
        fPools[i].Defragment;
    end;
  finally
    fLock.Leave;
  end;
end;

procedure TvgMemoryPoolManager.TrimAll;
var
  i: Integer;
begin
  fLock.Enter;
  try
    for i := 0 to High(fPools) do
    begin
      if fPools[i] <> nil then
        fPools[i].Trim;
    end;
  finally
    fLock.Leave;
  end;
end;

function TvgMemoryPoolManager.GetStats(MemoryTypeIndex: Cardinal): TPoolStats;
var
  Pool: TvgMemoryPool;
begin
  Pool := GetPool(MemoryTypeIndex);
  Result := Pool.Stats;
end;

{ TvgMemoryManager }

constructor TvgMemoryManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  fAllocationSize := DEFAULT_POOL_SIZE;
  fStatsUpdateInterval := 1000;
  fLastStatsUpdate := Now;
end;

destructor TvgMemoryManager.Destroy;
begin
  fPoolManager.Free;
  inherited;
end;

procedure TvgMemoryManager.SetLogicalDevice(const Value: TvgLogicalDevice);
begin
  if fLogicalDevice <> Value then
  begin
    fLogicalDevice := Value;
    if Assigned(fLogicalDevice) then
    begin
      fPoolManager.Free;
      fPoolManager := TvgMemoryPoolManager.Create(fLogicalDevice);
    end;
  end;
end;

function TvgMemoryManager.AllocateMemory(const AllocInfo: TVkMemoryAllocateInfo;
                                         out Memory: TVkDeviceMemory): TVkResult;
begin
  if not Assigned(fPoolManager) then
    raise Exception.Create('Memory pool manager is not initialized.');

  Result := fPoolManager.AllocateMemory(AllocInfo, Memory);

  // Optionally update stats if the interval has passed
  if MilliSecondsBetween(Now, fLastStatsUpdate) >= fStatsUpdateInterval then
    UpdateStats;
end;

procedure TvgMemoryManager.FreeMemory(Memory: TVkDeviceMemory);
begin
  if not Assigned(fPoolManager) then
    raise Exception.Create('Memory pool manager is not initialized.');

  fPoolManager.FreeMemory(Memory);
end;

procedure TvgMemoryManager.DefragmentPools;
begin
  if not Assigned(fPoolManager) then
    raise Exception.Create('Memory pool manager is not initialized.');

  fPoolManager.DefragmentAll;
end;

procedure TvgMemoryManager.TrimPools;
begin
  if not Assigned(fPoolManager) then
    raise Exception.Create('Memory pool manager is not initialized.');

  fPoolManager.TrimAll;
end;

function TvgMemoryManager.GetPoolStats(MemoryTypeIndex: Cardinal): TPoolStats;
begin
  if not Assigned(fPoolManager) then
    raise Exception.Create('Memory pool manager is not initialized.');

  Result := fPoolManager.GetStats(MemoryTypeIndex);
end;

procedure TvgMemoryManager.UpdateStats;
begin
  // Update statistics logic can be implemented here
  fLastStatsUpdate := Now;
end;

procedure TvgMemoryManager.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  // Additional notification handling can be implemented here
end;

procedure TvgMemoryManager.SetDisabled;
begin
  inherited SetDisabled;
  // Additional logic for disabling the component can be implemented here
end;

procedure TvgMemoryManager.SetEnabled(aComp: TvgBaseComponent);
begin
  inherited SetEnabled(aComp);
  // Additional logic for enabling the component can be implemented here
end;

end.
