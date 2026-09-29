(******************************************************************************
 *                                 DVVulkan                                   *
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
 ******************************************************************************)

{ Scene loader registry.

  TvgSceneLoaderStorer is abstract: each file format has its own descendant
  (the glTF one, TvgSceneLoaderStorer_GLTF, is in the PRO package).  A loader
  registers itself here once, so that a data module, the Object Inspector and
  the designer can offer "load this file with that loader" without knowing
  the loader's class:

      initialization
        RegisterSceneLoader(TvgSceneLoaderStorer_GLTF, 'glTF',
                            'glTF 2.0 scene', '.gltf;.glb', 'FileName');
      finalization
        UnregisterSceneLoader(TvgSceneLoaderStorer_GLTF);

  aFileNameProp names the loader's published string property that takes the
  file to load; vgLoadSceneFile sets it through RTTI and calls LoadScene.

  Core runtime unit (VulkanPkgR280): no VCL, no design-time units. }

unit Vulkan_SceneLoaders;

interface

uses
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  System.Generics.Collections,
  Vulkan_Components_Scene_Renderer;

type
  TvgSceneLoaderStorerClass = class of TvgSceneLoaderStorer;

  TvgSceneLoaderInfo = record
    Name         : string;                     //'glTF' - what SceneLoaderType holds
    Description  : string;                     //'glTF 2.0 scene'
    Extensions   : string;                     //'.gltf;.glb'
    FileNameProp : string;                     //published string property taking the file
    LoaderClass  : TvgSceneLoaderStorerClass;

    Function HandlesFile(const aFileName: string): Boolean;
    Function DialogFilter: string;             //'glTF 2.0 scene (*.gltf;*.glb)|*.gltf;*.glb'
  end;

  EvgSceneLoaderError = class(Exception);

procedure RegisterSceneLoader(aClass: TvgSceneLoaderStorerClass;
                              const aName, aDescription, aExtensions: string;
                              const aFileNameProp: string = 'FileName');
procedure UnregisterSceneLoader(aClass: TvgSceneLoaderStorerClass);

function  SceneLoaders: TArray<TvgSceneLoaderInfo>;
function  FindSceneLoader(const aName: string; out aInfo: TvgSceneLoaderInfo): Boolean;
function  FindSceneLoaderClass(aClass: TClass; out aInfo: TvgSceneLoaderInfo): Boolean;
function  FindSceneLoaderForFile(const aFileName: string; out aInfo: TvgSceneLoaderInfo): Boolean;

{ Open-dialog filter: every registered format first, then each one, then
  all files. }
function  SceneLoaderDialogFilter: string;

{ Loads aFileName into aScene.

    aLoader       a loader to use (e.g. one dropped on a form, carrying its
                  own settings) - or nil to create one of aLoaderType just
                  for this load.
    aLoaderType   registered loader name; '' picks one by aLoader's class or
                  by the file's extension.

  Raises EvgSceneLoaderError with the reason when it can't. }
procedure vgLoadSceneFile(aScene: TvgScene; const aFileName: string;
                          aLoader: TvgSceneLoaderStorer = nil;
                          const aLoaderType: string = '');

resourcestring
  vgSLNoScene       = 'No scene to load into.';
  vgSLNoFile        = 'No scene file given.';
  vgSLFileMissing   = 'Scene file not found: %s';
  vgSLNoLoaderType  = 'No scene loader is registered with the name "%s".';
  vgSLNoLoaderExt   = 'No scene loader is registered for "%s" files.  Install the package that provides one (glTF is in the PRO package).';
  vgSLNoFileProp    = '%s has no published string property "%s" to take the file name.';

implementation

var
  gLoaders : TList<TvgSceneLoaderInfo> = nil;

function Loaders: TList<TvgSceneLoaderInfo>;
begin
  If not assigned(gLoaders) then
    gLoaders := TList<TvgSceneLoaderInfo>.Create;
  Result := gLoaders;
end;

{ TvgSceneLoaderInfo }

function TvgSceneLoaderInfo.HandlesFile(const aFileName: string): Boolean;
  Var Ext : string;
begin
  Ext := LowerCase(ExtractFileExt(aFileName));
  Result := (Ext <> '') and (Pos(';' + Ext + ';', ';' + LowerCase(Extensions) + ';') > 0);
end;

function TvgSceneLoaderInfo.DialogFilter: string;
  Var Mask : string;
begin
  //'.gltf;.glb' -> '*.gltf;*.glb'
  Mask   := '*' + StringReplace(Extensions, ';', ';*', [rfReplaceAll]);
  Result := Format('%s (%s)|%s', [Description, Mask, Mask]);
end;

{ registry }

procedure RegisterSceneLoader(aClass: TvgSceneLoaderStorerClass;
                              const aName, aDescription, aExtensions: string;
                              const aFileNameProp: string = 'FileName');
  Var Info : TvgSceneLoaderInfo;
      I    : Integer;
begin
  If not assigned(aClass) then exit;

  Info.Name         := aName;
  Info.Description  := aDescription;
  Info.Extensions   := aExtensions;
  Info.FileNameProp := aFileNameProp;
  Info.LoaderClass  := aClass;

  If Info.Name = '' then
    Info.Name := aClass.ClassName;
  If Info.Description = '' then
    Info.Description := Info.Name;

  //re-registering replaces (a package reloaded in the IDE)
  For I := Loaders.Count - 1 downto 0 do
    If (Loaders[I].LoaderClass = aClass) or SameText(Loaders[I].Name, Info.Name) then
      Loaders.Delete(I);

  Loaders.Add(Info);

  //a dropped loader must stream from a .dfm
  RegisterClass(aClass);
end;

procedure UnregisterSceneLoader(aClass: TvgSceneLoaderStorerClass);
  Var I : Integer;
begin
  If not assigned(gLoaders) then exit;

  For I := gLoaders.Count - 1 downto 0 do
    If gLoaders[I].LoaderClass = aClass then
      gLoaders.Delete(I);
end;

function SceneLoaders: TArray<TvgSceneLoaderInfo>;
begin
  Result := Loaders.ToArray;
end;

function FindSceneLoader(const aName: string; out aInfo: TvgSceneLoaderInfo): Boolean;
  Var Info : TvgSceneLoaderInfo;
begin
  For Info in Loaders do
    If SameText(Info.Name, aName) then
    Begin
      aInfo := Info;
      Exit(True);
    End;
  Result := False;
end;

function FindSceneLoaderClass(aClass: TClass; out aInfo: TvgSceneLoaderInfo): Boolean;
  Var Info : TvgSceneLoaderInfo;
begin
  //most derived registration wins: exact class first, then an ancestor
  For Info in Loaders do
    If Info.LoaderClass = aClass then
    Begin
      aInfo := Info;
      Exit(True);
    End;

  For Info in Loaders do
    If assigned(aClass) and aClass.InheritsFrom(Info.LoaderClass) then
    Begin
      aInfo := Info;
      Exit(True);
    End;

  Result := False;
end;

function FindSceneLoaderForFile(const aFileName: string; out aInfo: TvgSceneLoaderInfo): Boolean;
  Var Info : TvgSceneLoaderInfo;
begin
  For Info in Loaders do
    If Info.HandlesFile(aFileName) then
    Begin
      aInfo := Info;
      Exit(True);
    End;
  Result := False;
end;

function SceneLoaderDialogFilter: string;
  Var Info    : TvgSceneLoaderInfo;
      AllMask : string;
begin
  Result  := '';
  AllMask := '';

  For Info in Loaders do
  Begin
    If AllMask <> '' then AllMask := AllMask + ';';
    AllMask := AllMask + '*' + StringReplace(Info.Extensions, ';', ';*', [rfReplaceAll]);
    Result  := Result + '|' + Info.DialogFilter;
  End;

  If AllMask <> '' then
    Result := 'All scene files|' + AllMask + Result + '|';

  Result := Result + 'All files (*.*)|*.*';
end;

procedure vgLoadSceneFile(aScene: TvgScene; const aFileName: string;
                          aLoader: TvgSceneLoaderStorer = nil;
                          const aLoaderType: string = '');
  Var Info     : TvgSceneLoaderInfo;
      Loader   : TvgSceneLoaderStorer;
      Owned    : Boolean;
      PropInfo : PPropInfo;
begin
  If not assigned(aScene) then
    raise EvgSceneLoaderError.Create(vgSLNoScene);

  If Trim(aFileName) = '' then
    raise EvgSceneLoaderError.Create(vgSLNoFile);

  If not FileExists(aFileName) then
    raise EvgSceneLoaderError.CreateFmt(vgSLFileMissing, [aFileName]);

  //which loader: the named type, else the given loader's, else by extension
  If aLoaderType <> '' then
  Begin
    If not FindSceneLoader(aLoaderType, Info) then
      raise EvgSceneLoaderError.CreateFmt(vgSLNoLoaderType, [aLoaderType]);
  End
  else
  If assigned(aLoader) then
  Begin
    If not FindSceneLoaderClass(aLoader.ClassType, Info) then
    Begin
      //unregistered loader component: assume the usual property name
      Info := Default(TvgSceneLoaderInfo);
      Info.Name         := aLoader.ClassName;
      Info.FileNameProp := 'FileName';
      Info.LoaderClass  := TvgSceneLoaderStorerClass(aLoader.ClassType);
    End;
  End
  else
  If not FindSceneLoaderForFile(aFileName, Info) then
    raise EvgSceneLoaderError.CreateFmt(vgSLNoLoaderExt, [ExtractFileExt(aFileName)]);

  //a given loader of another type can't do this file: use a fresh one
  Owned := not assigned(aLoader) or not aLoader.InheritsFrom(Info.LoaderClass);
  If Owned then
    Loader := Info.LoaderClass.Create(nil)
  else
    Loader := aLoader;

  Try
    PropInfo := GetPropInfo(Loader, Info.FileNameProp);
    If not assigned(PropInfo) or not assigned(PropInfo^.SetProc) or
       not (PropInfo^.PropType^.Kind in [tkString, tkLString, tkUString, tkWString]) then
      raise EvgSceneLoaderError.CreateFmt(vgSLNoFileProp, [Loader.ClassName, Info.FileNameProp]);

    SetStrProp(Loader, PropInfo, aFileName);

    //TvgSceneLoaderStorer.SetScene clears the loader's previous scene, so
    //only point it at the scene when it changes
    If Loader.Scene <> aScene then
      Loader.Scene := aScene;

    Loader.LoadScene;
  Finally
    If Owned then
      Loader.Free;
  End;
end;

initialization

finalization
  FreeAndNil(gLoaders);

end.
