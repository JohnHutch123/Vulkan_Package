# PasVulkan local patches

Fixes for upstream defects that block **Win32** builds, or builds on older
IDE versions, of the Vulkan packages.
They live here because upstream may not take a pull request.

Re-apply these after every `git pull` of PasVulkan.

| Patch | Target file | Problem fixed |
|-------|-------------|---------------|
| `0002-pasvulkan-lzma-win32-symbol.patch` | `src/PasVulkan.Compression.LZMA.pas` | `E2065 Unsatisfied forward or external declaration: 'C_LzmaDecode'` |
| `0003-pasvulkan-delphi11-changedisplaysettings.patch` | `src/PasVulkan.Application.pas` | `E2033 Types of actual and formal var parameters must be identical` (Delphi 11 and earlier) |

Numbering is historical and has a gap; see below.

## 0001 — PasMP 64-bit `Increment` on Win32 (withdrawn, fixed upstream)

Win32 builds used to fail with `E2250 There is no overloaded version of
'Increment' that can be called with these arguments`, because
`TPasMPInterlocked`'s `TPasMPInt64` / `TPasMPUInt64` overloads were guarded by
`{$ifdef CPU64}` and so vanished on 32-bit targets.

PasMP fixed this upstream in `d58e2e6` ("Fixed 64-bit atomics for 32-bit
targets", 2026-10-02) with a more general solution than the local workaround:
a new `PASMP_HAS_INT64_ATOMICS` symbol, defined for CPU64 and for 32-bit x86 /
ARM targets that have a double-native-machine-word atomic compare-exchange, now
guards all 64-bit atomic overloads rather than just `Increment`.

Delphi Win32 defines `CPU386`, which implies that compare-exchange, so the
symbol is defined and the overloads are present. The local patch was therefore
withdrawn and the vendored `externals/pasmp` updated to `d58e2e6`. Verified by
rebuilding every package on Delphi 11, 12 and 13 for Win32 and Win64 with no
PasMP patch applied.

Note `externals/pasmp` is an *uninitialised* git submodule in the PasVulkan
checkout, so git ignores its working-tree contents entirely. Any future change
there cannot be committed and would again have to live here as a patch.

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
