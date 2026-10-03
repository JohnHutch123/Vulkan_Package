# Using TvgVulkanDataModule

`TvgVulkanDataModule` (unit `Vulkan_DataModule`) is a `TDataModule` that holds a
complete Vulkan session, in the same way that a data module holds a database
connection and its datasets. You set up the session once in the module. Any
form with a `TvgWindowVCL` can then show it.

```
TvgInstance
  +- TvgPhysicalDevice
       +- TvgScreenRenderDevice
            +- TvgLinker  ->  TvgWindowVCL (any form)
                 +- TvgRenderEngine (e.g. TvgRenderEngine_Single)
                 +- TvgScene
                 +- TvgToolManager
```

Runtime code is in the VCL runtime package (`VulkanPkg_VCLRxxx`, e.g. `VulkanPkg_VCLR290` for
Delphi 12). The IDE support (wizard, menu verbs and the session editor) is in the VCL design
package (`VulkanPkg_VCLDxxx`).

---

## 1. Design-time setup

1. **Create the module:** choose *File > New > Other > Delphi Files >
   Vulkan Session Data Module*.
2. **Build the session:** right-click the module and choose *Build Vulkan
   Session*. This creates and connects the Instance, Physical Device, Screen
   Render Device and Linker.
3. **Connect a window:** drop a `TvgWindowVCL` on a form. Then set the module's
   `Window` property to that window. You can also set the window's
   `VulkanLink` to the linker.
4. **Add a renderer:** drop a renderer such as `TvgRenderEngine_Single` on the
   module and assign it to the module's `Renderer` property.
5. **Add a scene:** right-click the module and choose *Add Scene*.
6. **Add mouse/keyboard tools:** right-click the module and choose *Add Tool
   Manager*. This adds a camera-orbit `TvgToolManager`.
7. **Test it:** right-click the module and choose *Enable Vulkan Session*, or
   set `SessionActive` to True. If the session can't start, a message explains
   why.

The *Edit Vulkan Session...* verb opens an editor with the whole session tree
and each component's properties. The properties are read-only while the
session is running.

### Context-menu verbs

| Verb | Action |
|------|--------|
| Edit Vulkan Session... | Opens the session editor |
| Build Vulkan Session | Creates any missing core components and connects them |
| Add Linker (another window) | Adds a linker for a second window |
| Add Scene | Creates and connects a `TvgScene` |
| Load Scene File... | Opens a file and loads it into the scene |
| Add Tool Manager | Creates and connects a `TvgToolManager` |
| Enable / Disable Vulkan Session | Starts or stops the session |

---

## 2. Key properties

| Property | Purpose |
|----------|---------|
| `Instance`, `PhysicalDevice`, `ScreenDevice`, `Linker` | The primary session chain |
| `Window` | The primary linker's `TvgWindowVCL`, usually on another form |
| `Renderer`, `Scene` | The primary linker's renderer and scene |
| `ToolManager` | Camera, picking and selection for the primary window |
| `SceneFileName` | File to load. In the IDE it has a file-open button |
| `SceneLoaderType` | Registered loader name, e.g. `'glTF'`. Leave it blank to choose by file extension |
| `SceneLoader` | Optional loader component with its own settings |
| `LoadSceneOnEnable` | Loads `SceneFileName` each time the session is enabled, including at design time (default `False`) |
| `ZoomAllOnLoad` | Frames the scene after each load (default `True`) |
| `SessionActive` | Starts or stops the whole session. This property is never stored |
| `OnSessionEnabled` / `OnSessionDisabled` | Run-time events |

---

## 3. Run-time use

The session always starts disabled. Enable it after the form that holds the
window has a handle, for example in the main form's `OnShow`:

```pascal
procedure TMainForm.FormShow(Sender: TObject);
begin
  VulkanDM.EnableSession;          // raises EvgVulkanSessionError if it can't start
  VulkanDM.LoadScene('C:\Models\Box.glb');
end;

procedure TMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  VulkanDM.DisableSession;
end;
```

To check whether the session can start without raising an exception:

```pascal
if not VulkanDM.CanEnableSession then
  ShowMessage(VulkanDM.SessionProblem)
else
  VulkanDM.EnableSession;
```

`EnableSession` is all-or-nothing. If any part of the session fails, the
whole session is disabled again and the exception reports the reason.

---

## 4. Building a session entirely in code

Every `TDataModule` descendant needs a `.dfm`. To create a module without one,
use `CreateNew`:

```pascal
DM := TvgVulkanDataModule.CreateNew(Self);
DM.BuildSession;                                   // Instance -> Device -> Screen Device -> Linker
DM.Window   := VulkanWindow1;
DM.Renderer := TvgRenderEngine_Single.Create(DM);
DM.BuildScene;
DM.BuildToolManager;
DM.EnableSession;
DM.LoadScene('C:\Models\Box.glb');                 // loader chosen by extension
```

---

## 5. Multiple windows

Each window needs its own linker on the same screen device:

```pascal
DM.AddLinker(VulkanWindow2);
```

At design time, use *Add Linker*. You can also drop a `TvgLinker`, set its
`ScreenDevice`, and then set the second window's `VulkanLink` to it. Every
linker connected under the instance belongs to the session and is enabled and
disabled with it.

The second window needs its own tool manager. Set that linker's `ToolManager`
property, or set the tool manager's `Linker` property.

---

## 6. Scene loading

- `LoadScene(FileName)` loads into `Scene`. With no argument it loads
  `SceneFileName`. The loader is chosen in this order: `SceneLoader`, then
  `SceneLoaderType`, then the file extension.
- `ClearScene` empties the scene.
- Loaders register themselves in `Vulkan_SceneLoaders`, for example:

  ```pascal
  RegisterSceneLoader(TvgSceneLoaderStorer_GLTF, 'glTF', 'glTF 2.0 scene',
                      '.gltf;.glb', 'FileName');
  ```

If a load fails, `EvgSceneLoaderError` is raised. When the load runs from
`LoadSceneOnEnable`, the session stays enabled even if the load fails.

---

## 7. Useful methods

| Method | Description |
|--------|-------------|
| `BuildSession` | Creates any missing core components and connects them |
| `ConnectSession` / `ConnectScene` | Re-connect existing components |
| `AddLinker(Window)` | Adds a linker for another window |
| `BuildScene` / `BuildToolManager` | Create the scene or tool manager if missing |
| `EnableSession` / `DisableSession` | Start or stop the whole session |
| `SessionProblem` / `CanEnableSession` | Report why the session can't start |
| `SessionLinkers` | Every linker in the session |
| `GetSessionComponents(List)` | Every component connected under `Instance` |

The standalone helpers `vgSessionInstance`, `vgEnableSession`,
`vgDisableSession` and `vgSessionProblem` work on any instance's tree, even
when it is not in a data module.
