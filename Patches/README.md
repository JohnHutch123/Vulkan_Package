# PasVulkan local patches

Fixes for upstream defects that block **Win32** builds, or builds on older
IDE versions, of the Vulkan packages.
They live here because upstream may not take a pull request, and because
`externals/pasmp` is an *uninitialised* git submodule in the PasVulkan checkout
(git ignores its working-tree contents, so the change cannot be committed there).

Re-apply these after every `git pull` of PasVulkan.

| Patch | Target file | Problem fixed |
|-------|-------------|---------------|
| `0001-pasmp-win32-int64-increment.patch` | `externals/pasmp/src/PasMP.pas` | `E2250 There is no overloaded version of 'Increment' that can be called with these arguments` |
| `0002-pasvulkan-lzma-win32-symbol.patch` | `src/PasVulkan.Compression.LZMA.pas` | `E2065 Unsatisfied forward or external declaration: 'C_LzmaDecode'` |
| `0003-pasvulkan-delphi11-changedisplaysettings.patch` | `src/PasVulkan.Application.pas` | `E2033 Types of actual and formal var parameters must be identical` (Delphi 11 and earlier) |

## 0001 — PasMP 64-bit `Increment` on Win32

`TPasMPInterlocked`'s `TPasMPInt64` / `TPasMPUInt64` `Increment` overloads are
guarded by `{$ifdef CPU64}`, so they vanish on Win32 and any 64-bit call site
fails to compile. The guard is widened to:

```pascal
{$if defined(CPU64) or defined(cpu386)}
```

This is safe: Delphi's Win32 compiler implements `AtomicIncrement` for `Int64`
via `cmpxchg8b` (verified by compiling a test program). Only the `Increment`
guard is widened — the ~44 other `{$ifdef CPU64}` guards in that file are left
alone to minimise risk to the third-party library.

## 0002 — LZMA external symbol name on Win32

The linked object files export different symbol names per platform:

* `lzmadec_windows_x86_32.o` exports `_LzmaDecode` (Win32 COFF decorates cdecl
  symbols with a leading underscore)
* `lzmadec_windows_x86_64.o` exports `LzmaDecode`

The Pascal declaration hardcoded the Win64 spelling. It is now:

```pascal
external name {$if defined(Windows) and defined(cpu386)}'_LzmaDecode'{$else}'LzmaDecode'{$ifend};
```

The underscore form is restricted to `Windows and cpu386` because ELF targets
(Linux / Android x86-32) do not use the leading underscore.

## 0003 — `ChangeDisplaySettingsW` on Delphi 11 and earlier

Delphi 12 added a pointer overload to the RTL:

```pascal
function ChangeDisplaySettingsW(var lpDevMode: TDeviceModeW; dwFlags: DWORD): Longint; overload;
function ChangeDisplaySettingsW(lpDevMode: PDeviceModeW; dwFlags: DWORD): Longint; overload;  // Delphi 12+ only
```

Delphi 11 declares only the `var` form, so the upstream calls
`ChangeDisplaySettingsW(nil,0)` and `ChangeDisplaySettingsW(@devMode,...)`
fail to compile there. Both call sites now use the `var` form, which exists in
every version:

```pascal
OK:=ChangeDisplaySettingsW(PDeviceModeW(nil)^,0)=DISP_CHANGE_SUCCESSFUL;
OK:=ChangeDisplaySettingsW(devMode,CDS_FULLSCREEN)=DISP_CHANGE_SUCCESSFUL;
```

`PDeviceModeW(nil)^` is the standard Delphi idiom for passing a nil pointer to a
`var` parameter — the compiler takes the address of the dereference, so nothing
is actually dereferenced. Behaviour is unchanged on Delphi 12/13; on Delphi 11
the unit now compiles.

## Applying

```powershell
powershell -ExecutionPolicy Bypass -File Patches\apply-pasvulkan-patches.ps1 -PasVulkanRoot D:\Vulkan
```

The script is idempotent: patches already present are skipped. Add `-Revert` to
undo them.

Patches are CRLF and were produced against PasVulkan `master` at commit
`bccc73408`.
