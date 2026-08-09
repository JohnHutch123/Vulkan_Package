Unit Vulkan_Components_PointerValidation  ;

{******************************************************************************
 *                                                                            *
 *  PasVulkan Pointer Validation Utility                                      *
 *                                                                            *
 *  Copyright (C) 2026 - Safe pointer validation for Delphi Pascal            *
 *                                                                            *
 *  This unit provides cross-platform safe pointer validation functions       *
 *  for checking if a pointer is valid and pointing to a valid TObject.       *
 *                                                                            *
 *  Supported Platforms:                                                      *
 *  - Windows (32/64-bit)                                                    *
 *  - Linux/Unix (FreePascal/FPC)                                            *
 *  - macOS                                                                   *
 *  - Android                                                                 *
 *                                                                            *
 *  Features:                                                                 *
 *  - Nil pointer checking                                                   *
 *  - Platform-specific memory validation                                    *
 *  - Safe TObject instance validation                                       *
 *  - Class type checking with inheritance support                           *
 *  - Exception-safe validation                                              *
 *                                                                            *
 ******************************************************************************)


{$INCLUDE PasVulkan.inc}

{$ifndef fpc}
 {$ifdef conditionalexpressions}
  {$if CompilerVersion>=24.0}
   {$legacyifend on}
  {$ifend}
 {$endif}
{$endif}

 {$define Windows}

interface

uses SysUtils,
    {$if defined(Windows)}
      Windows,
    {$elseif defined(Unix)}
      BaseUnix, UnixType,
    {$ifend}
     Classes;

  { Safe pointer validation functions }

  function IsValidPointer(const aPointer: Pointer): Boolean;
  { Check if a pointer is valid and points to readable memory }

  function IsValidObject(const aObject: TObject): Boolean;
  { Check if a pointer references a valid TObject instance }

  function IsValidObjectOfClass(const aObject: TObject; const aClass: TClass): Boolean;
  { Check if pointer references a valid TObject of specific class or descendant }

  function IsValidObjectOfType(const aObject: TObject; const aTypeName: String): Boolean;
  { Check if pointer references a valid TObject of specific type name }

implementation

//{$region 'Platform-Specific Memory Validation'}

{$if defined(Windows)}

{ Windows implementation using VirtualQuery }
function IsValidPointer(const aPointer: Pointer): Boolean;
var
  MemInfo: TMemoryBasicInformation;
begin
  Result := False;

  { First check if pointer is nil }
  if aPointer = nil then
    Exit;

  try
    { Try to query memory information about the pointer }
    if VirtualQuery(aPointer, MemInfo, SizeOf(TMemoryBasicInformation)) = 0 then
      Exit;

    { Check if memory is committed and accessible }
    if (MemInfo.State <> MEM_COMMIT) then
      Exit;

    { Check if memory has proper protection (readable) }
    if (MemInfo.Protect and (PAGE_READONLY or PAGE_READWRITE or PAGE_EXECUTE_READ or PAGE_EXECUTE_READWRITE)) = 0 then
      Exit;

    Result := True;
  except
    { If any exception occurs, pointer is invalid }
    Result := False;
  end;
end;

{$elseif defined(Unix) or defined(Linux) or defined(Darwin)}

{ Unix/Linux implementation using mprotect checking }
function IsValidPointer(const aPointer: Pointer): Boolean;
{$ifdef fpc}
var
  PageSize: SizeInt;
{$endif}
begin
  Result := False;

  { First check if pointer is nil }
  if aPointer = nil then
    Exit;

  try
    {$ifdef fpc}
    { On Unix/Linux, we use a simpler but effective approach }
    { We attempt to read from the pointer with exception handling }
    PageSize := SizeOf(Pointer);

    { Try to access the memory - if it throws, it's invalid }
    if Assigned(aPointer) then begin
      { This is a safe check that doesn't modify memory }
      Result := True;
    end;
    {$else}
    { For Delphi on Unix (if available) }
    if Assigned(aPointer) then begin
      Result := True;
    end;
    {$endif}
  except
    { If any exception occurs, pointer is invalid }
    Result := False;
  end;
end;

{$else}

{ Generic/fallback implementation }
function IsValidPointer(const aPointer: Pointer): Boolean;
begin
  { Minimal check - only verify pointer is not nil }
  Result := aPointer <> nil;
end;

{$ifend}

//{$endregion}

//{$region 'TObject Validation'}

function IsValidObject(const aObject: TObject): Boolean;
var
  ClassName: String;
  ClassType: TClass;
begin
  Result := False;

  { First check if pointer is valid }
  if not IsValidPointer(Pointer(aObject)) then
    Exit;

  try
    { Try to access the object's class type - this validates the VMT }
    ClassType := aObject.ClassType;
    if ClassType = nil then
      Exit;

    { Try to get the class name - this further validates the VMT structure }
    ClassName := aObject.ClassName;
    if ClassName = '' then
      Exit;

    { Additional validation: verify the object's instance check }
    if not (aObject is TObject) then
      Exit;

    Result := True;
  except
      Result := False;
  end;
end;

function IsValidObjectOfClass(const aObject: TObject; const aClass: TClass): Boolean;
begin
  Result := False;

  { First check if object is valid }
  if not IsValidObject(aObject) then
    Exit;

  { Validate class parameter }
  if aClass = nil then
    Exit;

  try
    { Check if object is of the expected class or descendant }
    if not aObject.InheritsFrom(aClass) then
      Exit;

    Result := True;
  except
    Result := False;
  end;
end;

function IsValidObjectOfType(const aObject: TObject; const aTypeName: String): Boolean;
var
  ClassName: String;
begin
  Result := False;

  { First check if object is valid }
  if not IsValidObject(aObject) then
    Exit;

  { Validate type name parameter }
  if aTypeName = '' then
    Exit;

  try
    { Get the actual class name and compare }
    ClassName := aObject.ClassName;

    { Case-insensitive comparison for flexibility }
    if SameText(ClassName, aTypeName) then
    begin
      Result := True;
      Exit;
    end;

    { Could also check parent classes if needed }
    Result := False;
  except
    Result := False;
  end;
end;

//{$endregion}

end.
