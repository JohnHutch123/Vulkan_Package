program VulkanEnumCheck;

(*  Checks the short enum and set types in Vulkan_Components_Lookups.pas
    against the Vulkan enums in PasVulkan's Vulkan.pas.

    Vulkan_Components_Lookups.pas keeps its own copy of many Vulkan enums
    (TvgBorderColor for TVkBorderColor, and so on) with short names, so they
    work as published properties. When a new Vulkan.pas arrives, Vulkan may
    have added values those copies do not have yet. This program finds them.

    It needs no list of types: each Tvg type is paired with its TVk type
    through the existing GetVKxxx / GetVGxxx conversion functions, e.g.

        Function GetVKBorderColor(Value: TvgBorderColor) : TVkBorderColor;

    For every pair it reports
      - Vulkan values with no mapping yet (with the short name it would use)
      - VK_ names the lookups use that are no longer in Vulkan.pas
      - Tvg members that GetVKxxx or GetVGxxx do not handle
      - GetVKxxx and GetVGxxx disagreeing about a value

    With -update it also adds the new values: a member at the end of each
    Tvg type, and a line in each conversion function, copied from the last
    mapping line already there. A .bak of the unit is written first.

    Usage
      VulkanEnumCheck [Vulkan.pas] [Vulkan_Components_Lookups.pas]
                      [-update] [-verbose] [-config=File] [-report=File]

    Without paths it looks for the lookups unit in RunTime_Src above the exe
    or current folder, and for Vulkan.pas in %PASVULKAN%\src, or in a Vulkan
    folder beside the repository, D:\Vulkan or C:\Vulkan (as Tests\RunTests.bat).

    Exit code: 0 nothing to do, 1 new values or problems found, 2 error.

    Written to compile with Delphi (RAD Studio 12) and Free Pascal.
*)

{$APPTYPE CONSOLE}
{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
{$ENDIF}

uses
  SysUtils,
  Classes;

const
  MaxPublishedSetSize = 32;   // published set properties must fit in 4 bytes

type
  TStrArray = array of string;
  TInt64Array = array of Int64;
  {$IFDEF FPC}
  TIdx = PtrInt;
  {$ELSE}
  TIdx = NativeInt;
  {$ENDIF}

  { A source file. Code is the text with comments blanked out; Tok also has
    string literals blanked out. Blanking keeps every column where it was, so
    a position found in Tok or Code is the same position in Lines. }
  TSource = class
  public
    FileName: string;
    Lines: TStringList;
    Code: TStringList;
    Tok: TStringList;
    constructor Create(const AFileName: string);
    destructor Destroy; override;
  end;

  TWord = record
    Text: string;
    Col: Integer;          // 1-based column of the first character
  end;
  TWordArray = array of TWord;

  { One comma separated item of a parenthesised list }
  TListItem = record
    Name: string;          // first identifier of the item
    NameLine: Integer;
    NameEnd: Integer;      // column just after the identifier
    Text: string;          // the whole item
  end;
  TListItems = array of TListItem;

  TVkMember = record
    Name: string;
    Value: Int64;
    AliasOf: string;
    Resolved: Boolean;
  end;

  TVkEnum = record
    Name: string;
    Members: array of TVkMember;
  end;

  TVgType = record
    Name: string;
    IsSet: Boolean;
    Members: TStrArray;
    MemberList: TStringList;   // sorted, for lookups
    LastLine: Integer;         // line of the last member
    LastEnd: Integer;          // column just after the last member
    CloseLine: Integer;        // line of the closing ')'
  end;

  TDirection = (dirToVk, dirToVg);

  TConvFunc = record
    Name: string;
    Dir: TDirection;
    VgType: string;
    VkType: string;
    FirstLine: Integer;
    LastLine: Integer;
    // the last line mapping one Tvg member to one VK value, used as template
    TplLine: Integer;
    TplVg, TplVk: string;
    TplVgCol, TplVkCol: Integer;
  end;

  TPair = record
    Vg: string;
    VkName: string;
    VkValue: Int64;
  end;
  TPairArray = array of TPair;

  TNewValue = record
    VkName: string;
    Value: Int64;
    VgName: string;
    Note: string;
    InType: Boolean;       // already declared in the Tvg type, only unmapped
  end;

  TNameRule = record
    VkPrefix: string;
    VgPrefix: string;
    DropBit: Boolean;
    DropVendor: Boolean;   // drop a trailing KHR, EXT, NV ...
    Votes: Integer;
  end;
  TNameRules = array of TNameRule;

  TEdit = record
    Line: Integer;
    Col: Integer;          // 0 = no in-line insert
    InsText: string;
    NewLines: TStrArray;   // inserted after Line
  end;

var
  VkEnums: array of TVkEnum;
  VkEnumIndex: TStringList;      // enum name -> index
  VkMemberIndex: TStringList;    // member name -> enum shl 16 + member

  VgTypes: array of TVgType;
  VgIndex: TStringList;          // type name -> index
  Funcs: array of TConvFunc;
  LookupWords: TStringList;      // every identifier in the lookups unit
  NewNamesUsed: TStringList;

  CfgSubset, CfgSkip, CfgIgnore, CfgNames: TStringList;

  Report: TStringList;
  Edits: array of TEdit;
  Verbose: Boolean = False;
  DoUpdate: Boolean = False;

  CountChecked, CountNew, CountNewTypes, CountProblems, CountAdded: Integer;

const
  ReservedWords: array[0..64] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const',
    'constructor', 'destructor', 'dispinterface', 'div', 'do', 'downto',
    'else', 'end', 'except', 'exports', 'file', 'finalization', 'finally',
    'for', 'function', 'goto', 'if', 'implementation', 'in', 'inherited',
    'initialization', 'inline', 'interface', 'is', 'label', 'library', 'mod',
    'nil', 'not', 'object', 'of', 'or', 'out', 'packed', 'procedure',
    'program', 'property', 'raise', 'record', 'repeat', 'resourcestring',
    'set', 'shl', 'shr', 'string', 'then', 'threadvar', 'to', 'try', 'type',
    'unit', 'until', 'uses', 'var', 'while', 'with', 'xor');

{ ---------------------------------------------------------------------------
  Output
  --------------------------------------------------------------------------- }

procedure Say(const S: string); overload;
begin
  Writeln(S);
  Report.Add(S);
end;

procedure Say(const Fmt: string; const Args: array of const); overload;
begin
  Say(Format(Fmt, Args));
end;

{ ---------------------------------------------------------------------------
  Text helpers
  --------------------------------------------------------------------------- }

function IsIdStart(C: Char): Boolean;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or (C = '_');
end;

function IsIdChar(C: Char): Boolean;
begin
  Result := IsIdStart(C) or ((C >= '0') and (C <= '9'));
end;

function IsIdent(const S: string): Boolean;
var
  i: Integer;
begin
  Result := (S <> '') and IsIdStart(S[1]);
  if Result then
    for i := 2 to Length(S) do
      if not IsIdChar(S[i]) then
        Exit(False);
end;

function IsReservedWord(const S: string): Boolean;
var
  i: Integer;
begin
  for i := Low(ReservedWords) to High(ReservedWords) do
    if SameText(S, ReservedWords[i]) then
      Exit(True);
  Result := False;
end;

function StartsText(const SubText, S: string): Boolean;
begin
  Result := SameText(Copy(S, 1, Length(SubText)), SubText);
end;

function EndsText(const SubText, S: string): Boolean;
begin
  Result := (Length(S) >= Length(SubText)) and
            SameText(Copy(S, Length(S) - Length(SubText) + 1, Length(SubText)), SubText);
end;

function GetWords(const S: string): TWordArray;
var
  p, n, st, k: Integer;
begin
  SetLength(Result, 0);
  n := Length(S);
  p := 1;
  while p <= n do
  begin
    if IsIdStart(S[p]) then
    begin
      st := p;
      while (p <= n) and IsIdChar(S[p]) do
        Inc(p);
      k := Length(Result);
      SetLength(Result, k + 1);
      Result[k].Text := Copy(S, st, p - st);
      Result[k].Col := st;
    end
    else if IsIdChar(S[p]) or (S[p] = '$') or (S[p] = '#') or (S[p] = '&') then
    begin
      // a number such as 12, $00FF or #13: skip it whole
      Inc(p);
      while (p <= n) and IsIdChar(S[p]) do
        Inc(p);
    end
    else
      Inc(p);
  end;
end;

function SplitUnderscore(const S: string): TStrArray;
var
  p, k: Integer;
  Rest: string;
begin
  SetLength(Result, 0);
  Rest := S;
  repeat
    p := Pos('_', Rest);
    k := Length(Result);
    SetLength(Result, k + 1);
    if p = 0 then
    begin
      Result[k] := Rest;
      Rest := '';
    end
    else
    begin
      Result[k] := Copy(Rest, 1, p - 1);
      Rest := Copy(Rest, p + 1, MaxInt);
    end;
  until (p = 0);
end;

function IsVendorTag(const S: string): Boolean;
const
  Tags: array[0..23] of string = ('KHR', 'EXT', 'NV', 'NVX', 'AMD', 'AMDX', 'INTEL',
    'QCOM', 'HUAWEI', 'ARM', 'IMG', 'GOOGLE', 'VALVE', 'MESA', 'FUCHSIA', 'QNX',
    'MSFT', 'SEC', 'LUNARG', 'ANDROID', 'GGP', 'NN', 'MVK', 'OHOS');
var
  i: Integer;
begin
  for i := Low(Tags) to High(Tags) do
    if SameText(S, Tags[i]) then
      Exit(True);
  Result := False;
end;

function JoinTokens(const T: TStrArray; First: Integer; DropBit: Boolean;
  DropVendor: Boolean = False): string;
var
  i, Last: Integer;
begin
  Result := '';
  Last := High(T);
  if DropVendor and (Last >= First) and IsVendorTag(T[Last]) then
    Dec(Last);
  for i := First to Last do
  begin
    if DropBit and SameText(T[i], 'BIT') then
      Continue;
    if Result <> '' then
      Result := Result + '_';
    Result := Result + T[i];
  end;
end;

function LeadingSpaces(const S: string): string;
var
  i: Integer;
begin
  i := 1;
  while (i <= Length(S)) and ((S[i] = ' ') or (S[i] = #9)) do
    Inc(i);
  Result := Copy(S, 1, i - 1);
end;

function ValueIn(const A: TInt64Array; V: Int64): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(A) do
    if A[i] = V then
      Exit(True);
  Result := False;
end;

procedure AddValue(var A: TInt64Array; V: Int64);
begin
  if not ValueIn(A, V) then
  begin
    SetLength(A, Length(A) + 1);
    A[High(A)] := V;
  end;
end;

function NewSortedList: TStringList;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Result.Duplicates := dupIgnore;
  Result.Sorted := True;
end;

{ ---------------------------------------------------------------------------
  TSource
  --------------------------------------------------------------------------- }

constructor TSource.Create(const AFileName: string);
var
  i, p, n, State: Integer;   // State 0 code, 1 inside { }, 2 inside (* *)
  S, C, T: string;
  InStr: Boolean;
begin
  inherited Create;
  FileName := AFileName;
  Lines := TStringList.Create;
  Code := TStringList.Create;
  Tok := TStringList.Create;
  Lines.LoadFromFile(FileName);

  State := 0;
  for i := 0 to Lines.Count - 1 do
  begin
    S := Lines[i];
    C := S;
    T := S;
    n := Length(S);
    InStr := False;
    p := 1;
    while p <= n do
    begin
      if State = 1 then
      begin
        if S[p] = '}' then
          State := 0;
        C[p] := ' ';
        T[p] := ' ';
        Inc(p);
      end
      else if State = 2 then
      begin
        if (S[p] = '*') and (p < n) and (S[p + 1] = ')') then
        begin
          C[p] := ' '; T[p] := ' ';
          C[p + 1] := ' '; T[p + 1] := ' ';
          Inc(p, 2);
          State := 0;
        end
        else
        begin
          C[p] := ' ';
          T[p] := ' ';
          Inc(p);
        end;
      end
      else if InStr then
      begin
        if S[p] = '''' then
          InStr := False
        else
          T[p] := ' ';
        Inc(p);
      end
      else if S[p] = '''' then
      begin
        InStr := True;
        Inc(p);
      end
      else if (S[p] = '/') and (p < n) and (S[p + 1] = '/') then
      begin
        while p <= n do
        begin
          C[p] := ' ';
          T[p] := ' ';
          Inc(p);
        end;
      end
      else if S[p] = '{' then
      begin
        State := 1;
        C[p] := ' ';
        T[p] := ' ';
        Inc(p);
      end
      else if (S[p] = '(') and (p < n) and (S[p + 1] = '*') then
      begin
        State := 2;
        C[p] := ' '; T[p] := ' ';
        C[p + 1] := ' '; T[p + 1] := ' ';
        Inc(p, 2);
      end
      else
        Inc(p);
    end;
    Code.Add(C);
    Tok.Add(T);
  end;
end;

destructor TSource.Destroy;
begin
  Lines.Free;
  Code.Free;
  Tok.Free;
  inherited;
end;

{ Reads a parenthesised list starting at the '(' at Line/Col of Src.
  Items are split on commas at the outer level. }
function ScanList(Src: TStringList; Line, Col: Integer; out Items: TListItems;
  out CloseLine: Integer): Boolean;
var
  Depth, p, n, st, k: Integer;
  S, Cur, CurName: string;
  CurLine, CurEnd: Integer;
  HaveName: Boolean;

  procedure Flush;
  begin
    if HaveName then
    begin
      k := Length(Items);
      SetLength(Items, k + 1);
      Items[k].Name := CurName;
      Items[k].NameLine := CurLine;
      Items[k].NameEnd := CurEnd;
      Items[k].Text := Trim(Cur);
    end;
    Cur := '';
    HaveName := False;
  end;

begin
  SetLength(Items, 0);
  Result := False;
  CloseLine := -1;
  Depth := 0;
  Cur := '';
  HaveName := False;
  CurName := '';
  CurLine := -1;
  CurEnd := 0;
  while Line < Src.Count do
  begin
    S := Src[Line];
    n := Length(S);
    p := Col;
    while p <= n do
    begin
      if S[p] = '(' then
      begin
        Inc(Depth);
        if Depth > 1 then
          Cur := Cur + S[p];
        Inc(p);
      end
      else if S[p] = ')' then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Flush;
          CloseLine := Line;
          Exit(True);
        end;
        Cur := Cur + S[p];
        Inc(p);
      end
      else if (S[p] = ',') and (Depth = 1) then
      begin
        Flush;
        Inc(p);
      end
      else if (Depth = 1) and (not HaveName) and IsIdStart(S[p]) and (Trim(Cur) = '') then
      begin
        st := p;
        while (p <= n) and IsIdChar(S[p]) do
          Inc(p);
        CurName := Copy(S, st, p - st);
        CurLine := Line;
        CurEnd := p;
        HaveName := True;
        Cur := Cur + CurName;
      end
      else
      begin
        Cur := Cur + S[p];
        Inc(p);
      end;
    end;
    Cur := Cur + ' ';
    Inc(Line);
    Col := 1;
  end;
end;

{ Finds the '(' that opens a type's list: on the same line after Col, or as
  the first thing on the next non-blank line. }
function FindOpenParen(Src: TStringList; Line, Col: Integer; out OpenLine, OpenCol: Integer): Boolean;
var
  S: string;
begin
  Result := False;
  S := Src[Line];
  while (Col <= Length(S)) and (S[Col] = ' ') do
    Inc(Col);
  if Col <= Length(S) then
  begin
    if S[Col] = '(' then
    begin
      OpenLine := Line;
      OpenCol := Col;
      Result := True;
    end;
    Exit;
  end;
  Inc(Line);
  while (Line < Src.Count) and (Trim(Src[Line]) = '') do
    Inc(Line);
  if (Line < Src.Count) and (Copy(Trim(Src[Line]), 1, 1) = '(') then
  begin
    OpenLine := Line;
    OpenCol := Pos('(', Src[Line]);
    Result := True;
  end;
end;

{ ---------------------------------------------------------------------------
  Vulkan.pas
  --------------------------------------------------------------------------- }

function ParseValue(S: string; out V: Int64; out AliasOf: string): Boolean;
var
  p: Integer;
  W, Rest: string;
  Is32: Boolean;
begin
  Result := False;
  AliasOf := '';
  V := 0;
  Is32 := False;
  S := Trim(S);
  if (S <> '') and IsIdStart(S[1]) then
  begin
    p := 1;
    while (p <= Length(S)) and IsIdChar(S[p]) do
      Inc(p);
    W := Copy(S, 1, p - 1);
    Rest := Trim(Copy(S, p, MaxInt));
    if Rest = '' then
    begin
      AliasOf := W;      // NAME=OTHER_NAME
      Exit;
    end;
    if (Rest[1] = '(') and (Rest[Length(Rest)] = ')') then
    begin
      // a cast such as TVkInt32($80000000)
      Is32 := SameText(W, 'TVkInt32') or SameText(W, 'Int32') or SameText(W, 'LongInt');
      S := Trim(Copy(Rest, 2, Length(Rest) - 2));
    end
    else
      Exit;
  end;
  Result := TryStrToInt64(S, V);
  if Result and Is32 and (V > $7FFFFFFF) then
    V := V - $100000000;
end;

procedure LoadVulkan(Src: TSource);
var
  i, j, p, e, OpenLine, OpenCol, CloseLine: Integer;
  T, Name: string;
  Items: TListItems;
  Prev: Int64;
  PrevOk, Changed: Boolean;
  V: Int64;
  Alias, ValText: string;
begin
  i := 0;
  while i < Src.Tok.Count do
  begin
    T := Src.Tok[i];
    p := Pos('=', T);
    if (p > 0) and StartsText('TVk', Trim(T)) then
    begin
      Name := Trim(Copy(T, 1, p - 1));
      if IsIdent(Name) and FindOpenParen(Src.Tok, i, p + 1, OpenLine, OpenCol) and
         ScanList(Src.Tok, OpenLine, OpenCol, Items, CloseLine) and (Length(Items) > 0) then
      begin
        e := Length(VkEnums);
        SetLength(VkEnums, e + 1);
        VkEnums[e].Name := Name;
        SetLength(VkEnums[e].Members, Length(Items));
        Prev := -1;
        PrevOk := True;
        for j := 0 to High(Items) do
        begin
          VkEnums[e].Members[j].Name := Items[j].Name;
          p := Pos('=', Items[j].Text);
          if p = 0 then
          begin
            // no value given: one more than the previous member
            VkEnums[e].Members[j].Value := Prev + 1;
            VkEnums[e].Members[j].Resolved := PrevOk;
          end
          else
          begin
            ValText := Copy(Items[j].Text, p + 1, MaxInt);
            VkEnums[e].Members[j].Resolved := ParseValue(ValText, V, Alias);
            VkEnums[e].Members[j].Value := V;
            VkEnums[e].Members[j].AliasOf := Alias;
          end;
          Prev := VkEnums[e].Members[j].Value;
          PrevOk := VkEnums[e].Members[j].Resolved;
          VkMemberIndex.AddObject(Items[j].Name, TObject(TIdx((e shl 16) or j)));
        end;
        VkEnumIndex.AddObject(Name, TObject(TIdx(e)));
        i := CloseLine;
      end;
    end;
    Inc(i);
  end;

  // resolve NAME=OTHER_NAME aliases
  for e := 0 to High(VkEnums) do
    repeat
      Changed := False;
      for i := 0 to High(VkEnums[e].Members) do
        if (not VkEnums[e].Members[i].Resolved) and (VkEnums[e].Members[i].AliasOf <> '') then
          for j := 0 to High(VkEnums[e].Members) do
            if VkEnums[e].Members[j].Resolved and
               SameText(VkEnums[e].Members[j].Name, VkEnums[e].Members[i].AliasOf) then
            begin
              VkEnums[e].Members[i].Value := VkEnums[e].Members[j].Value;
              VkEnums[e].Members[i].Resolved := True;
              Changed := True;
              Break;
            end;
    until not Changed;
end;

function FindVkEnum(const Name: string): Integer;
var
  i, p: Integer;
  Alt: string;
begin
  Result := -1;
  if VkEnumIndex.Find(Name, i) then
    Exit(TIdx(VkEnumIndex.Objects[i]));
  // TVkCullModeFlags -> TVkCullModeFlagBits, TVkSurfaceTransformFlagsKHR -> ...FlagBitsKHR
  p := Length(Name) - 4;
  while (p > 0) and not SameText(Copy(Name, p, 5), 'Flags') do
    Dec(p);
  if p > 0 then
  begin
    Alt := Copy(Name, 1, p - 1) + 'FlagBits' + Copy(Name, p + 5, MaxInt);
    if VkEnumIndex.Find(Alt, i) then
      Result := TIdx(VkEnumIndex.Objects[i]);
  end;
end;

function FindVkMember(const Name: string; out E, M: Integer): Boolean;
var
  i: Integer;
  Code: TIdx;
begin
  Result := VkMemberIndex.Find(Name, i);
  if Result then
  begin
    Code := TIdx(VkMemberIndex.Objects[i]);
    E := Code shr 16;
    M := Code and $FFFF;
  end;
end;

{ ---------------------------------------------------------------------------
  Vulkan_Components_Lookups.pas
  --------------------------------------------------------------------------- }

{ Line of the 'end' that closes the routine whose header is on HeaderLine.
  Nested routines (the TestValue helpers) are counted so their 'end' is
  not taken for the end of the outer one. }
function FindRoutineEnd(Tok: TStringList; HeaderLine: Integer): Integer;
var
  L, k, Depth, Nested, Blocks: Integer;
  W: TWordArray;
  lw: string;
begin
  Depth := 0;
  Nested := 0;
  Blocks := 0;
  for L := HeaderLine + 1 to Tok.Count - 1 do
  begin
    W := GetWords(Tok[L]);
    for k := 0 to High(W) do
    begin
      lw := LowerCase(W[k].Text);
      if (lw = 'function') or (lw = 'procedure') then
      begin
        if Depth = 0 then
          Inc(Nested);
      end
      else if (lw = 'begin') or (lw = 'case') or (lw = 'try') or (lw = 'asm') or (lw = 'record') then
        Inc(Depth)
      else if lw = 'end' then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Inc(Blocks);
          if Blocks > Nested then
            Exit(L);
        end;
      end;
    end;
  end;
  Result := Tok.Count - 1;
end;

procedure LoadLookups(Src: TSource);
var
  i, j, k, p, ImplLine, OpenLine, OpenCol, CloseLine: Integer;
  T, Name, W1: string;
  W: TWordArray;
  Items: TListItems;
  IsSet: Boolean;
  F: TConvFunc;
begin
  ImplLine := -1;
  for i := 0 to Src.Tok.Count - 1 do
    if SameText(Trim(Src.Tok[i]), 'implementation') then
    begin
      ImplLine := i;
      Break;
    end;
  if ImplLine < 0 then
    raise Exception.Create('No implementation section found in ' + Src.FileName);

  for i := 0 to Src.Tok.Count - 1 do
  begin
    W := GetWords(Src.Tok[i]);
    for j := 0 to High(W) do
      LookupWords.Add(W[j].Text);
  end;

  // enum and set types:  TName = (...)   or   TName = Set of (...)
  i := 0;
  while i < ImplLine do
  begin
    T := Src.Tok[i];
    W := GetWords(T);
    if (Length(W) > 0) and StartsText('T', W[0].Text) then
    begin
      p := W[0].Col + Length(W[0].Text);
      while (p <= Length(T)) and (T[p] = ' ') do
        Inc(p);
      if (p <= Length(T)) and (T[p] = '=') then
      begin
        Inc(p);
        IsSet := False;
        if (Length(W) >= 3) and SameText(W[1].Text, 'set') and SameText(W[2].Text, 'of') then
        begin
          IsSet := True;
          p := W[2].Col + 2;
        end;
        if FindOpenParen(Src.Tok, i, p, OpenLine, OpenCol) and
           ScanList(Src.Tok, OpenLine, OpenCol, Items, CloseLine) and (Length(Items) > 0) then
        begin
          k := Length(VgTypes);
          SetLength(VgTypes, k + 1);
          VgTypes[k].Name := W[0].Text;
          VgTypes[k].IsSet := IsSet;
          VgTypes[k].MemberList := NewSortedList;
          SetLength(VgTypes[k].Members, Length(Items));
          for j := 0 to High(Items) do
          begin
            VgTypes[k].Members[j] := Items[j].Name;
            VgTypes[k].MemberList.Add(Items[j].Name);
          end;
          VgTypes[k].LastLine := Items[High(Items)].NameLine;
          VgTypes[k].LastEnd := Items[High(Items)].NameEnd;
          VgTypes[k].CloseLine := CloseLine;
          VgIndex.AddObject(W[0].Text, TObject(TIdx(k)));
          i := CloseLine;
        end;
      end;
    end;
    Inc(i);
  end;

  // conversion functions:  Function GetVKxxx(Value: Tvgxxx) : TVkxxx;
  for i := ImplLine + 1 to Src.Tok.Count - 1 do
  begin
    W := GetWords(Src.Tok[i]);
    if (Length(W) = 5) and SameText(W[0].Text, 'function') and SameText(W[2].Text, 'Value') then
    begin
      Name := W[1].Text;
      W1 := '';
      if StartsText('GetVK', Name) then
      begin
        F.Dir := dirToVk;
        F.VgType := W[3].Text;
        F.VkType := W[4].Text;
        W1 := 'ok';
      end
      else if StartsText('GetVG', Name) then
      begin
        F.Dir := dirToVg;
        F.VkType := W[3].Text;
        F.VgType := W[4].Text;
        W1 := 'ok';
      end;
      if (W1 <> '') and VgIndex.Find(F.VgType, k) then
      begin
        F.VgType := VgTypes[TIdx(VgIndex.Objects[k])].Name;
        F.Name := Name;
        F.FirstLine := i;
        F.LastLine := FindRoutineEnd(Src.Tok, i);
        F.TplLine := -1;
        F.TplVg := '';
        F.TplVk := '';
        F.TplVgCol := 0;
        F.TplVkCol := 0;
        SetLength(Funcs, Length(Funcs) + 1);
        Funcs[High(Funcs)] := F;
      end;
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  Config file
  --------------------------------------------------------------------------- }

procedure LoadConfig(const FileName: string);
var
  L: TStringList;
  i: Integer;
  S: string;
  W: TWordArray;
begin
  if (FileName = '') or not FileExists(FileName) then
    Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    for i := 0 to L.Count - 1 do
    begin
      S := Trim(L[i]);
      if (S = '') or (S[1] = '#') or (S[1] = ';') or (Copy(S, 1, 2) = '//') then
        Continue;
      if Copy(S, 1, 2) = '* ' then
        S := 'ANYTYPE' + Copy(S, 2, MaxInt);
      W := GetWords(S);
      if Length(W) = 0 then
        Continue;
      if SameText(W[0].Text, 'subset') and (Length(W) >= 2) then
        CfgSubset.Add(W[1].Text)
      else if SameText(W[0].Text, 'skip') and (Length(W) >= 2) then
        CfgSkip.Add(W[1].Text)
      else if SameText(W[0].Text, 'ignore') and (Length(W) >= 3) then
        CfgIgnore.Add(UpperCase(W[1].Text) + '=' + UpperCase(W[2].Text))
      else if SameText(W[0].Text, 'name') and (Length(W) >= 3) then
        CfgNames.Values[UpperCase(W[1].Text)] := W[2].Text
      else
        Writeln('Config line ', i + 1, ' not understood: ', S);
    end;
  finally
    L.Free;
  end;
end;

function IsIgnored(const VgType, VkName: string): Boolean;
begin
  Result := (CfgIgnore.IndexOf(UpperCase(VgType) + '=' + UpperCase(VkName)) >= 0) or
            (CfgIgnore.IndexOf('*=' + UpperCase(VkName)) >= 0) or
            (CfgIgnore.IndexOf('ANYTYPE=' + UpperCase(VkName)) >= 0);
end;

{ ---------------------------------------------------------------------------
  Short names for new values, learnt from the existing pairs.
  For BorderColor the pairs  BC_INT_OPAQUE_BLACK <- VK_BORDER_COLOR_INT_OPAQUE_BLACK
  give the rule "drop VK_BORDER_COLOR_, add BC_". Some types also drop _BIT.
  --------------------------------------------------------------------------- }

function LearnRules(const Pairs: TPairArray): TNameRules;
var
  i, j, n, k, r: Integer;
  T: TStrArray;
  Core, VgU, Prefix, VkPrefix: string;
  Drop, DropV: Boolean;
  Tmp: TNameRule;
begin
  SetLength(Result, 0);
  for i := 0 to High(Pairs) do
  begin
    T := SplitUnderscore(Pairs[i].VkName);
    VgU := UpperCase(Pairs[i].Vg);
    for n := 1 to High(T) do
      for k := 0 to 3 do
      begin
        Drop := (k and 1) <> 0;
        DropV := (k and 2) <> 0;
        if Drop and (Pos('_BIT', UpperCase(Pairs[i].VkName)) = 0) then
          Continue;
        if DropV and not IsVendorTag(T[High(T)]) then
          Continue;
        Core := UpperCase(JoinTokens(T, n, Drop, DropV));
        if (Core = '') or not EndsText(Core, VgU) then
          Continue;
        Prefix := Copy(Pairs[i].Vg, 1, Length(VgU) - Length(Core));
        if (Prefix <> '') and (Prefix[Length(Prefix)] <> '_') then
          Continue;
        VkPrefix := JoinTokens(Copy(T, 0, n), 0, False) + '_';
        r := -1;
        for j := 0 to High(Result) do
          if SameText(Result[j].VkPrefix, VkPrefix) and SameText(Result[j].VgPrefix, Prefix) and
             (Result[j].DropBit = Drop) and (Result[j].DropVendor = DropV) then
          begin
            r := j;
            Break;
          end;
        if r < 0 then
        begin
          r := Length(Result);
          SetLength(Result, r + 1);
          Result[r].VkPrefix := VkPrefix;
          Result[r].VgPrefix := Prefix;
          Result[r].DropBit := Drop;
          Result[r].DropVendor := DropV;
          Result[r].Votes := 0;
        end;
        Inc(Result[r].Votes);
      end;
  end;
  // most votes first; on a tie keep _BIT and the suffix, and prefer the shorter VK prefix
  for i := 0 to High(Result) do
    for j := i + 1 to High(Result) do
      if (Result[j].Votes > Result[i].Votes) or
         ((Result[j].Votes = Result[i].Votes) and
          ((Ord(Result[j].DropBit) + Ord(Result[j].DropVendor) <
            Ord(Result[i].DropBit) + Ord(Result[i].DropVendor)) or
           ((Ord(Result[j].DropBit) + Ord(Result[j].DropVendor) =
             Ord(Result[i].DropBit) + Ord(Result[i].DropVendor)) and
            (Length(Result[j].VkPrefix) < Length(Result[i].VkPrefix))))) then
      begin
        Tmp := Result[i];
        Result[i] := Result[j];
        Result[j] := Tmp;
      end;
end;

function ApplyRules(const Rules: TNameRules; const VkName: string): string;
var
  i, n: Integer;
  T: TStrArray;
begin
  Result := '';
  for i := 0 to High(Rules) do
    if StartsText(Rules[i].VkPrefix, VkName) then
    begin
      n := Length(SplitUnderscore(Copy(Rules[i].VkPrefix, 1, Length(Rules[i].VkPrefix) - 1)));
      T := SplitUnderscore(VkName);
      Result := Rules[i].VgPrefix + JoinTokens(T, n, Rules[i].DropBit, Rules[i].DropVendor);
      if (Result <> '') and IsIdent(Result) and not IsReservedWord(Result) then
        Exit;
      Result := '';
    end;
end;

function IndexOfMember(const Vg: TVgType; const Name: string): Integer;
begin
  for Result := 0 to High(Vg.Members) do
    if SameText(Vg.Members[Result], Name) then
      Exit;
  Result := -1;
end;

function IsSingleBit(V: Int64): Boolean;
begin
  V := V and $FFFFFFFF;
  Result := (V <> 0) and ((V and (V - 1)) = 0);
end;

function NameIsTaken(const Name: string): Boolean;
var
  i: Integer;
  E, M: Integer;
begin
  Result := LookupWords.Find(Name, i) or NewNamesUsed.Find(Name, i) or
            VkEnumIndex.Find(Name, i) or FindVkMember(Name, E, M);
end;

function MakeNewName(const Rules: TNameRules; const VkName: string; const Vg: TVgType;
  Unmapped: TStringList; out Note: string; out InType: Boolean): string;
var
  Fallback, Short: string;
  T: TStrArray;
  n: Integer;
begin
  Note := '';
  InType := False;
  Result := CfgNames.Values[UpperCase(VkName)];
  if Result <> '' then
    Note := 'name from config'
  else
    Result := ApplyRules(Rules, VkName);

  // declared in the type already (with or without the vendor suffix), but no
  // conversion line uses it: just wire it up
  if Result <> '' then
  begin
    T := SplitUnderscore(Result);
    Short := JoinTokens(T, 0, False, True);
    if Unmapped.IndexOf(Result) < 0 then
      if (Short <> Result) and (Unmapped.IndexOf(Short) >= 0) then
        Result := Short;
    if Unmapped.IndexOf(Result) >= 0 then
    begin
      Result := Vg.Members[IndexOfMember(Vg, Result)];
      Unmapped.Delete(Unmapped.IndexOf(Result));
      InType := True;
      Note := 'already in ' + Vg.Name + ', only the conversion lines are added';
      Exit;
    end;
  end;

  Fallback := Copy(VkName, 4, MaxInt);   // VK_SOME_VALUE -> SOME_VALUE
  if Result = '' then
  begin
    Result := Fallback;
    Note := 'no naming pattern matched - check the name';
  end;
  if NameIsTaken(Result) then
  begin
    Note := Result + ' is already used - check the name';
    Result := Fallback;
    n := 2;
    while NameIsTaken(Result) do
    begin
      Result := Fallback + '_' + IntToStr(n);
      Inc(n);
    end;
  end;
  NewNamesUsed.Add(Result);
end;

{ ---------------------------------------------------------------------------
  Editing
  --------------------------------------------------------------------------- }

procedure AddEdit(Line, Col: Integer; const InsText: string; const NewLines: TStrArray);
var
  k: Integer;
begin
  k := Length(Edits);
  SetLength(Edits, k + 1);
  Edits[k].Line := Line;
  Edits[k].Col := Col;
  Edits[k].InsText := InsText;
  Edits[k].NewLines := NewLines;
end;

{ Replaces OldText at Col with NewText; pads a shorter name with spaces when
  spaces follow, so columns stay lined up. }
function ReplaceAt(const S: string; Col: Integer; const OldText, NewText: string): string;
var
  NewT: string;
  After: Integer;
begin
  NewT := NewText;
  After := Col + Length(OldText);
  if (Length(NewT) < Length(OldText)) and (After <= Length(S)) and (S[After] = ' ') then
    NewT := NewT + StringOfChar(' ', Length(OldText) - Length(NewT));
  Result := Copy(S, 1, Col - 1) + NewT + Copy(S, After, MaxInt);
end;

function CloneTemplate(Src: TSource; const F: TConvFunc; const NewVg, NewVk: string): string;
var
  S: string;
begin
  S := Src.Code[F.TplLine];
  if F.TplVkCol > F.TplVgCol then
  begin
    S := ReplaceAt(S, F.TplVkCol, F.TplVk, NewVk);
    S := ReplaceAt(S, F.TplVgCol, F.TplVg, NewVg);
  end
  else
  begin
    S := ReplaceAt(S, F.TplVgCol, F.TplVg, NewVg);
    S := ReplaceAt(S, F.TplVkCol, F.TplVk, NewVk);
  end;
  Result := TrimRight(S);
end;

procedure ApplyEdits(Src: TSource);
var
  i, j, k: Integer;
  Tmp: TEdit;
  S: string;
begin
  // bottom up, so earlier line numbers stay valid
  for i := 0 to High(Edits) do
    for j := i + 1 to High(Edits) do
      if Edits[j].Line > Edits[i].Line then
      begin
        Tmp := Edits[i];
        Edits[i] := Edits[j];
        Edits[j] := Tmp;
      end;
  for i := 0 to High(Edits) do
  begin
    if Edits[i].Col > 0 then
    begin
      S := Src.Lines[Edits[i].Line];
      Src.Lines[Edits[i].Line] := Copy(S, 1, Edits[i].Col - 1) + Edits[i].InsText +
                                  Copy(S, Edits[i].Col, MaxInt);
    end;
    for k := High(Edits[i].NewLines) downto 0 do
      Src.Lines.Insert(Edits[i].Line + 1, Edits[i].NewLines[k]);
  end;
end;

procedure CopyFile(const FromName, ToName: string);
var
  A, B: TFileStream;
begin
  A := TFileStream.Create(FromName, fmOpenRead or fmShareDenyWrite);
  try
    B := TFileStream.Create(ToName, fmCreate);
    try
      B.CopyFrom(A, 0);
    finally
      B.Free;
    end;
  finally
    A.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  The check
  --------------------------------------------------------------------------- }

function FuncNames(const Idx: array of Integer; Dir: TDirection): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(Idx) do
    if Funcs[Idx[i]].Dir = Dir then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Funcs[Idx[i]].Name;
    end;
end;

procedure CheckPair(Src: TSource; VgI, EnumI: Integer; const FIdx: array of Integer);
var
  Vg: TVgType;
  En: TVkEnum;
  i, j, k, L, E, M, VgCount, VkCount, VgPos, VkPos: Integer;
  W: TWordArray;
  Covered, Emitted: TInt64Array;
  Problems, Info, UsedToVk, UsedToVg, Reserved: TStringList;
  PairsVk, PairsVg, LearnFrom: TPairArray;
  NewVals: array of TNewValue;
  Rules: TNameRules;
  HasToVk, HasToVg, IsSubset, Found: Boolean;
  S, Header: string;
  NewLines: TStrArray;
  Name: string;
  RuleNames: TStrArray;
  Unmapped, Masks: TStringList;
  TypeAdds: Integer;

  procedure AddPair(var A: TPairArray; const AVg, AVk: string; AVal: Int64);
  begin
    SetLength(A, Length(A) + 1);
    A[High(A)].Vg := AVg;
    A[High(A)].VkName := AVk;
    A[High(A)].VkValue := AVal;
  end;

begin
  Vg := VgTypes[VgI];
  En := VkEnums[EnumI];
  IsSubset := CfgSubset.IndexOf(Vg.Name) >= 0;
  Inc(CountChecked);

  Problems := TStringList.Create;
  Info := TStringList.Create;
  UsedToVk := NewSortedList;
  UsedToVg := NewSortedList;
  Reserved := TStringList.Create;
  Masks := TStringList.Create;
  try
    SetLength(Covered, 0);
    SetLength(Emitted, 0);
    SetLength(PairsVk, 0);
    SetLength(PairsVg, 0);
    SetLength(NewVals, 0);
    HasToVk := False;
    HasToVg := False;

    // what the conversion functions use
    for i := 0 to High(FIdx) do
    begin
      if Funcs[FIdx[i]].Dir = dirToVk then HasToVk := True else HasToVg := True;
      for L := Funcs[FIdx[i]].FirstLine + 1 to Funcs[FIdx[i]].LastLine do
      begin
        W := GetWords(Src.Tok[L]);
        VgCount := 0;
        VkCount := 0;
        VgPos := -1;
        VkPos := -1;
        for k := 0 to High(W) do
        begin
          if Vg.MemberList.IndexOf(W[k].Text) >= 0 then
          begin
            Inc(VgCount);
            VgPos := k;
            if Funcs[FIdx[i]].Dir = dirToVk then
              UsedToVk.Add(W[k].Text)
            else
              UsedToVg.Add(W[k].Text);
          end
          else if FindVkMember(W[k].Text, E, M) then
          begin
            if E = EnumI then
            begin
              Inc(VkCount);
              VkPos := k;
              if En.Members[M].Resolved then
                AddValue(Covered, En.Members[M].Value);
            end
            else if StartsText('VK_', W[k].Text) then
              Problems.Add(Format('%s (line %d) uses %s, which is in %s, not %s',
                [Funcs[FIdx[i]].Name, L + 1, W[k].Text, VkEnums[E].Name, En.Name]));
          end
          else if StartsText('VK_', W[k].Text) and (W[k].Text = UpperCase(W[k].Text)) then
            Problems.Add(Format('%s (line %d) uses %s, which is not in Vulkan.pas (removed or renamed?)',
              [Funcs[FIdx[i]].Name, L + 1, W[k].Text]));
        end;

        if (VgCount = 1) and (VkCount = 1) then
        begin
          FindVkMember(W[VkPos].Text, E, M);
          if Funcs[FIdx[i]].Dir = dirToVk then
            AddPair(PairsVk, W[VgPos].Text, W[VkPos].Text, En.Members[M].Value)
          else
            AddPair(PairsVg, W[VgPos].Text, W[VkPos].Text, En.Members[M].Value);
          Funcs[FIdx[i]].TplLine := L;
          Funcs[FIdx[i]].TplVg := W[VgPos].Text;
          Funcs[FIdx[i]].TplVgCol := W[VgPos].Col;
          Funcs[FIdx[i]].TplVk := W[VkPos].Text;
          Funcs[FIdx[i]].TplVkCol := W[VkPos].Col;
        end;
      end;
    end;

    // Tvg members a conversion function never mentions
    for i := 0 to High(Vg.Members) do
    begin
      if HasToVk and (UsedToVk.IndexOf(Vg.Members[i]) < 0) then
        Info.Add(Format('%s is not handled in %s', [Vg.Members[i], FuncNames(FIdx, dirToVk)]));
      if HasToVg and (UsedToVg.IndexOf(Vg.Members[i]) < 0) then
        Info.Add(Format('%s is never returned by %s', [Vg.Members[i], FuncNames(FIdx, dirToVg)]));
    end;

    // GetVK and GetVG should agree. Two members may share a value (an
    // alias such as SR_MAX_EXT), so only flag GetVG returning a member whose
    // own GetVK line gives a different value.
    if HasToVk and HasToVg then
      for j := 0 to High(PairsVg) do
      begin
        Found := False;
        k := -1;
        for i := 0 to High(PairsVk) do
          if SameText(PairsVk[i].Vg, PairsVg[j].Vg) then
          begin
            k := i;
            if PairsVk[i].VkValue = PairsVg[j].VkValue then
              Found := True;
          end;
        if (k >= 0) and not Found then
          Problems.Add(Format('%s maps %s to %s, but %s maps %s to %s',
            [FuncNames(FIdx, dirToVg), PairsVg[j].VkName, PairsVg[j].Vg,
             FuncNames(FIdx, dirToVk), PairsVk[k].Vg, PairsVk[k].VkName]));
      end;

    // the naming rule, learnt from the existing lines
    if Length(PairsVk) > 0 then LearnFrom := PairsVk else LearnFrom := PairsVg;
    Rules := LearnRules(LearnFrom);

    // a member whose name matches one Vulkan value but is mapped to another
    // with a different value is most likely a copy-paste slip
    if (Length(Rules) > 0) and (Rules[0].Votes * 10 >= Length(LearnFrom) * 8) then
    begin
      SetLength(RuleNames, Length(En.Members));
      for i := 0 to High(En.Members) do
        RuleNames[i] := ApplyRules(Rules, En.Members[i].Name);
      for i := 0 to High(PairsVk) do
      begin
        Found := False;
        k := -1;
        for j := 0 to High(En.Members) do
          if (RuleNames[j] <> '') and SameText(RuleNames[j], PairsVk[i].Vg) and En.Members[j].Resolved then
          begin
            if k < 0 then
              k := j;
            if En.Members[j].Value = PairsVk[i].VkValue then
              Found := True;
          end;
        if (k >= 0) and not Found then
          Problems.Add(Format('%s maps %s to %s - by its name it should be %s',
            [FuncNames(FIdx, dirToVk), PairsVk[i].Vg, PairsVk[i].VkName, En.Members[k].Name]));
      end;
    end;

    // members declared in the type but used by no conversion line
    Unmapped := NewSortedList;
    try
      for i := 0 to High(Vg.Members) do
        if (UsedToVk.IndexOf(Vg.Members[i]) < 0) and (UsedToVg.IndexOf(Vg.Members[i]) < 0) then
          Unmapped.Add(Vg.Members[i]);

      // Vulkan values with no mapping
      if not IsSubset then
        for i := 0 to High(En.Members) do
        begin
          Name := En.Members[i].Name;
          if not En.Members[i].Resolved then Continue;
          if EndsText('_MAX_ENUM', Name) or (Copy(Name, 1, 1) = '_') or (Pos('DummyValue', Name) > 0) then Continue;
          if ValueIn(Covered, En.Members[i].Value) or ValueIn(Emitted, En.Members[i].Value) then Continue;
          AddValue(Emitted, En.Members[i].Value);
          if IsIgnored(Vg.Name, Name) then Continue;
          if Pos('_RESERVED_', UpperCase(Name)) > 0 then
          begin
            Reserved.Add(Name);
            Continue;
          end;
          // a set holds single bits; none is [] and masks are combinations
          if Vg.IsSet and not IsSingleBit(En.Members[i].Value) then
          begin
            Masks.Add(Name);
            Continue;
          end;
          k := Length(NewVals);
          SetLength(NewVals, k + 1);
          NewVals[k].VkName := Name;
          NewVals[k].Value := En.Members[i].Value;
          NewVals[k].VgName := MakeNewName(Rules, Name, Vg, Unmapped, NewVals[k].Note, NewVals[k].InType);
        end;
    finally
      Unmapped.Free;
    end;

    // report
    Header := Format('%s  <->  %s', [Vg.Name, En.Name]);
    if IsSubset then
      Header := Header + '   (subset - only existing values checked)';
    if (Length(NewVals) = 0) and (Problems.Count = 0) then
    begin
      Say('  OK    %s', [Header]);
      if Verbose then
        for i := 0 to Info.Count - 1 do
          Say('          note: %s', [Info[i]]);
      if Verbose and (Reserved.Count > 0) then
        Say('          %d reserved value(s) not mapped (ignored)', [Reserved.Count]);
      if Verbose and (Masks.Count > 0) then
        Say('          not a single bit, so not a set member: %s', [Masks.CommaText]);
      Exit;
    end;

    Say('');
    if Length(NewVals) > 0 then
      Say('  NEW   %s   %d new value(s)', [Header, Length(NewVals)])
    else
      Say('  CHECK %s', [Header]);
    Say('        %s', [FuncNames(FIdx, dirToVk) + ' / ' + FuncNames(FIdx, dirToVg)]);
    for i := 0 to High(NewVals) do
    begin
      S := Format('          + %-58s = %-11s -> %s', [NewVals[i].VkName, IntToStr(NewVals[i].Value), NewVals[i].VgName]);
      if NewVals[i].Note <> '' then
        S := S + '   (' + NewVals[i].Note + ')';
      Say(S);
    end;
    for i := 0 to Problems.Count - 1 do
      Say('          ! %s', [Problems[i]]);
    if Verbose then
    begin
      for i := 0 to Info.Count - 1 do
        Say('          note: %s', [Info[i]]);
      if Reserved.Count > 0 then
        Say('          %d reserved value(s) not mapped (ignored)', [Reserved.Count]);
      if Masks.Count > 0 then
        Say('          not a single bit, so not a set member: %s', [Masks.CommaText]);
    end;

    if Length(NewVals) > 0 then
    begin
      Inc(CountNewTypes);
      Inc(CountNew, Length(NewVals));
    end;
    Inc(CountProblems, Problems.Count);

    // edits
    if DoUpdate and (Length(NewVals) > 0) then
    begin
      TypeAdds := 0;
      for i := 0 to High(NewVals) do
        if not NewVals[i].InType then
          Inc(TypeAdds);
      if Vg.IsSet and (Length(Vg.Members) + TypeAdds > MaxPublishedSetSize) then
      begin
        Say('          NOT ADDED: %s would have %d members; a published set can hold %d.',
          [Vg.Name, Length(Vg.Members) + TypeAdds, MaxPublishedSetSize]);
        Say('          Add the ones you need by hand, and list the rest as "ignore" in the config.');
        Exit;
      end;

      // the type itself
      if TypeAdds > 0 then
      begin
        if Vg.CloseLine = Vg.LastLine then
        begin
          S := '';
          for i := 0 to High(NewVals) do
            if not NewVals[i].InType then
              S := S + ', ' + NewVals[i].VgName;
          SetLength(NewLines, 0);
          AddEdit(Vg.LastLine, Vg.LastEnd, S, NewLines);
        end
        else
        begin
          SetLength(NewLines, 0);
          for i := 0 to High(NewVals) do
            if not NewVals[i].InType then
            begin
              SetLength(NewLines, Length(NewLines) + 1);
              NewLines[High(NewLines)] := LeadingSpaces(Src.Lines[Vg.LastLine]) + NewVals[i].VgName + ',';
            end;
          S := NewLines[High(NewLines)];
          NewLines[High(NewLines)] := Copy(S, 1, Length(S) - 1);   // no comma after the last
          AddEdit(Vg.LastLine, Vg.LastEnd, ',', NewLines);
        end;
      end;

      // a line in each conversion function, copied from its last mapping line
      for j := 0 to High(FIdx) do
      begin
        if Funcs[FIdx[j]].TplLine < 0 then
        begin
          Say('          %s: no line to copy from - add the new values there by hand', [Funcs[FIdx[j]].Name]);
          Continue;
        end;
        SetLength(NewLines, Length(NewVals));
        for i := 0 to High(NewVals) do
          NewLines[i] := CloneTemplate(Src, Funcs[FIdx[j]], NewVals[i].VgName, NewVals[i].VkName);
        AddEdit(Funcs[FIdx[j]].TplLine, 0, '', NewLines);
      end;
      Inc(CountAdded, Length(NewVals));
    end;
  finally
    Problems.Free;
    Info.Free;
    UsedToVk.Free;
    UsedToVg.Free;
    Reserved.Free;
    Masks.Free;
  end;
end;

procedure CheckAll(Src: TSource);
var
  i, j, k, VgI, EnumI: Integer;
  Keys: TStringList;
  Idx: array of Integer;
  Key: string;
  NotChecked, Seen: TStringList;
begin
  Keys := TStringList.Create;      // "vg:enum" in order of first appearance
  NotChecked := TStringList.Create;
  Seen := NewSortedList;
  try
    for i := 0 to High(Funcs) do
    begin
      VgIndex.Find(Funcs[i].VgType, k);
      VgI := TIdx(VgIndex.Objects[k]);
      if CfgSkip.IndexOf(Funcs[i].VgType) >= 0 then
        Continue;
      EnumI := FindVkEnum(Funcs[i].VkType);
      if EnumI < 0 then
      begin
        Key := Format('%s (%s is not an enum in Vulkan.pas)', [Funcs[i].VgType, Funcs[i].VkType]);
        if NotChecked.IndexOf(Key) < 0 then
          NotChecked.Add(Key);
        Continue;
      end;
      Key := IntToStr(VgI) + ':' + IntToStr(EnumI);
      if Keys.IndexOf(Key) < 0 then
        Keys.Add(Key);
    end;

    for i := 0 to Keys.Count - 1 do
    begin
      Key := Keys[i];
      VgI := StrToInt(Copy(Key, 1, Pos(':', Key) - 1));
      EnumI := StrToInt(Copy(Key, Pos(':', Key) + 1, MaxInt));
      SetLength(Idx, 0);
      for j := 0 to High(Funcs) do
        if SameText(Funcs[j].VgType, VgTypes[VgI].Name) and (FindVkEnum(Funcs[j].VkType) = EnumI) then
        begin
          SetLength(Idx, Length(Idx) + 1);
          Idx[High(Idx)] := j;
        end;
      Seen.Add(VgTypes[VgI].Name);
      CheckPair(Src, VgI, EnumI, Idx);
    end;

    if NotChecked.Count > 0 then
    begin
      Say('');
      Say('Not checked:');
      for i := 0 to NotChecked.Count - 1 do
        Say('        %s', [NotChecked[i]]);
    end;
    if Verbose then
    begin
      Say('');
      Say('Types with no GetVK/GetVG functions (not checked):');
      for i := 0 to High(VgTypes) do
        if not Seen.Find(VgTypes[i].Name, k) then
          Say('        %s', [VgTypes[i].Name]);
    end;
  finally
    Keys.Free;
    NotChecked.Free;
    Seen.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Finding the files
  --------------------------------------------------------------------------- }

function FindUp(const StartDir, RelPath: string; Levels: Integer): string;
var
  Dir, Parent: string;
  i: Integer;
begin
  Dir := ExcludeTrailingPathDelimiter(ExpandFileName(StartDir));
  for i := 0 to Levels do
  begin
    Result := IncludeTrailingPathDelimiter(Dir) + RelPath;
    if FileExists(Result) then
      Exit;
    Parent := ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
    if (Parent = '') or (Parent = Dir) then
      Break;
    Dir := Parent;
  end;
  Result := '';
end;

function DefaultLookups: string;
var
  Rel: string;
begin
  Rel := 'RunTime_Src' + PathDelim + 'Vulkan_Components_Lookups.pas';
  Result := FindUp(ExtractFilePath(ParamStr(0)), Rel, 8);
  if Result = '' then
    Result := FindUp(GetCurrentDir, Rel, 8);
end;

function DefaultVulkanPas: string;
var
  Rel: string;
begin
  Rel := 'src' + PathDelim + 'Vulkan.pas';
  Result := GetEnvironmentVariable('PASVULKAN');
  if Result <> '' then
  begin
    Result := IncludeTrailingPathDelimiter(Result) + Rel;
    if FileExists(Result) then
      Exit;
  end;
  Result := FindUp(ExtractFilePath(ParamStr(0)), 'Vulkan' + PathDelim + Rel, 8);
  if Result = '' then
    Result := FindUp(GetCurrentDir, 'Vulkan' + PathDelim + Rel, 8);
  {$IFDEF MSWINDOWS}
  if (Result = '') and FileExists('D:\Vulkan\src\Vulkan.pas') then
    Result := 'D:\Vulkan\src\Vulkan.pas';
  if (Result = '') and FileExists('C:\Vulkan\src\Vulkan.pas') then
    Result := 'C:\Vulkan\src\Vulkan.pas';
  {$ENDIF}
end;

function DefaultConfig: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'VulkanEnumCheck.cfg';
  if FileExists(Result) then
    Exit;
  Result := FindUp(ExtractFilePath(ParamStr(0)),
    'Tools' + PathDelim + 'VulkanEnumCheck' + PathDelim + 'VulkanEnumCheck.cfg', 8);
  if Result = '' then
    Result := FindUp(GetCurrentDir,
      'Tools' + PathDelim + 'VulkanEnumCheck' + PathDelim + 'VulkanEnumCheck.cfg', 8);
end;

procedure ShowUsage;
begin
  Writeln('Usage: VulkanEnumCheck [Vulkan.pas] [Vulkan_Components_Lookups.pas]');
  Writeln('                       [-update] [-verbose] [-config=File] [-report=File]');
  Writeln;
  Writeln('  -update    add new Vulkan values to the lookups unit (a .bak is kept)');
  Writeln('  -verbose   also list unhandled members, reserved values and unchecked types');
  Writeln('  -config    exceptions file (default VulkanEnumCheck.cfg beside the exe)');
  Writeln('  -report    also write the report to this file');
end;

{ ---------------------------------------------------------------------------
  Main
  --------------------------------------------------------------------------- }

function Run: Integer;
var
  i: Integer;
  A, VulkanPas, LookupsPas, ConfigFile, ReportFile: string;
  Positional: TStringList;
  VkSrc, LookSrc: TSource;
begin
  Result := 0;
  ConfigFile := '';
  ReportFile := '';
  Positional := TStringList.Create;
  try
    for i := 1 to ParamCount do
    begin
      A := ParamStr(i);
      if (A <> '') and ((A[1] = '-') or (A[1] = '/')) and not FileExists(A) then
      begin
        A := Copy(A, 2, MaxInt);
        if SameText(A, 'update') then DoUpdate := True
        else if SameText(A, 'verbose') or SameText(A, 'v') then Verbose := True
        else if StartsText('config=', A) then ConfigFile := Copy(A, 8, MaxInt)
        else if StartsText('report=', A) then ReportFile := Copy(A, 8, MaxInt)
        else if SameText(A, 'help') or SameText(A, '?') or SameText(A, 'h') then
        begin
          ShowUsage;
          Exit(0);
        end
        else
        begin
          Writeln('Unknown option -', A);
          ShowUsage;
          Exit(2);
        end;
      end
      else
        Positional.Add(A);
    end;
    if Positional.Count > 0 then VulkanPas := Positional[0] else VulkanPas := DefaultVulkanPas;
    if Positional.Count > 1 then LookupsPas := Positional[1] else LookupsPas := DefaultLookups;
  finally
    Positional.Free;
  end;
  if ConfigFile = '' then
    ConfigFile := DefaultConfig;

  if (VulkanPas = '') or not FileExists(VulkanPas) then
  begin
    Writeln('ERROR: Vulkan.pas not found. Pass its path, or set PASVULKAN to the PasVulkan folder.');
    ShowUsage;
    Exit(2);
  end;
  if (LookupsPas = '') or not FileExists(LookupsPas) then
  begin
    Writeln('ERROR: Vulkan_Components_Lookups.pas not found. Pass its path as the second argument.');
    ShowUsage;
    Exit(2);
  end;

  Say('Vulkan.pas : %s', [ExpandFileName(VulkanPas)]);
  Say('Lookups    : %s', [ExpandFileName(LookupsPas)]);
  if FileExists(ConfigFile) then
    Say('Config     : %s', [ExpandFileName(ConfigFile)])
  else
    Say('Config     : (none)');
  Say('');
  LoadConfig(ConfigFile);

  VkSrc := TSource.Create(VulkanPas);
  try
    VkMemberIndex.Sorted := False;
    VkEnumIndex.Sorted := False;
    LoadVulkan(VkSrc);
    VkMemberIndex.Sorted := True;
    VkEnumIndex.Sorted := True;
  finally
    VkSrc.Free;
  end;
  Say('Vulkan.pas has %d enums with %d values.', [Length(VkEnums), VkMemberIndex.Count]);

  LookSrc := TSource.Create(LookupsPas);
  try
    LoadLookups(LookSrc);
    Say('Lookups unit has %d enum/set types and %d conversion functions.', [Length(VgTypes), Length(Funcs)]);
    Say('');

    CheckAll(LookSrc);

    Say('');
    Say('Checked %d types: %d new value(s) in %d type(s), %d problem(s).',
      [CountChecked, CountNew, CountNewTypes, CountProblems]);

    if DoUpdate and (Length(Edits) > 0) then
    begin
      CopyFile(LookupsPas, LookupsPas + '.bak');
      ApplyEdits(LookSrc);
      LookSrc.Lines.SaveToFile(LookupsPas);
      Say('Added %d value(s) to %s (original saved as %s).',
        [CountAdded, ExtractFileName(LookupsPas), ExtractFileName(LookupsPas) + '.bak']);
      Say('Rebuild the package to check it compiles, then run this again.');
    end
    else if (CountNew > 0) and not DoUpdate then
      Say('Run with -update to add them.');
  finally
    LookSrc.Free;
  end;

  if ReportFile <> '' then
    Report.SaveToFile(ReportFile);

  if (CountProblems > 0) or ((CountNew > 0) and (CountAdded < CountNew)) then
    Result := 1;
end;

procedure FreeAll;
var
  i: Integer;
begin
  for i := 0 to High(VgTypes) do
    VgTypes[i].MemberList.Free;
  VkEnumIndex.Free;
  VkMemberIndex.Free;
  VgIndex.Free;
  LookupWords.Free;
  NewNamesUsed.Free;
  CfgSubset.Free;
  CfgSkip.Free;
  CfgIgnore.Free;
  CfgNames.Free;
  Report.Free;
end;

begin
  VkEnumIndex := NewSortedList;
  VkMemberIndex := NewSortedList;
  VgIndex := NewSortedList;
  LookupWords := NewSortedList;
  NewNamesUsed := NewSortedList;
  CfgSubset := NewSortedList;
  CfgSkip := NewSortedList;
  CfgIgnore := NewSortedList;
  CfgNames := TStringList.Create;
  Report := TStringList.Create;
  try
    try
      ExitCode := Run;
    except
      on E: Exception do
      begin
        Writeln('ERROR: ', E.Message);
        ExitCode := 2;
      end;
    end;
  finally
    FreeAll;
  end;
  {$IFNDEF FPC}
  if DebugHook <> 0 then   // started from the IDE: keep the window open
  begin
    Write('Press Enter to close...');
    Readln;
  end;
  {$ENDIF}
end.
