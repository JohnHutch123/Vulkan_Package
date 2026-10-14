# PasVulkan local patches

Fixes for upstream defects that block **Win32** builds, builds on older IDE
versions, or **Android64** builds of the Vulkan packages.
They live here because upstream may not take a pull request.

Re-apply these after every `git pull` of PasVulkan.

| Patch | Target file | Problem fixed |
|-------|-------------|---------------|
| `0002-pasvulkan-lzma-win32-symbol.patch` | `src/PasVulkan.Compression.LZMA.pas` | `E2065 Unsatisfied forward or external declaration: 'C_LzmaDecode'` |
| `0003-pasvulkan-delphi11-changedisplaysettings.patch` | `src/PasVulkan.Application.pas` | `E2033 Types of actual and formal var parameters must be identical` (Delphi 11 and earlier) |
| `0004-pasvulkan-fixed-size-32bit-ints.patch` | `src/Vulkan.pas` | `TVkUInt32`/`TVkInt32` were `LongWord`/`LongInt`, which are **64-bit** on Delphi Android64, iOS and Linux (`E2250` in the framework, and wrong Vulkan struct layouts) |
| `0005-pasvulkan-crashreport-delphi-libdl.patch` | `src/PasVulkan.CrashReport.pas` | `ld: cannot find dl` linking for Android: `external 'dl'` is FreePascal's spelling |
| `0006-pasmp-delphi-arm64.patch` | `externals/pasmp/src/PasMP.pas` | `E2250` on `TPasMPInterlocked.Add`/`CompareExchange` and `E2034` on `TThread.Create` for Delphi Android64 |
| `0007-pasdblstrutils-delphi-llvm-fpu.patch` | `externals/pasdblstrutils/src/PasDblStrUtils.pas` | `E2003 Undeclared identifier: 'TFPURoundingMode'` (and `TFPUExceptionMask`, `GetPrecisionMode`) on Delphi's LLVM targets |

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

### Caution: PasVulkan pins the *pre-fix* commit

`externals/pasmp` is a git submodule, and PasVulkan's `master` still records
`f588790` — the commit immediately **before** the fix. A plain

```
git submodule update --init
```

therefore checks out `f588790` and reintroduces the `E2250` error on Win32.

After initialising the submodule, advance it and record the new pointer:

```
git -C externals/pasmp fetch origin
git -C externals/pasmp checkout d58e2e6
git add externals/pasmp
git commit -m "Bump externals/pasmp to d58e2e6"
```

This is done in the local PasVulkan checkout (commit `4cdbf057`). Re-check it
after any `git pull` that moves the submodule pointer back.

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

## 0004 — fixed-size 32-bit integers in `Vulkan.pas`

For Delphi, `Vulkan.pas` declared

```pascal
TVkInt32={$ifdef FPC}Int32{$else}LongInt{$endif};
TVkUInt32={$ifdef FPC}UInt32{$else}LongWord{$endif};
```

`LongInt` and `LongWord` are 32-bit on Windows but **64-bit** on Delphi's
64-bit POSIX targets (Android64, iOS, Linux64). Every Vulkan struct field typed
`TVkUInt32` would then be the wrong size. The visible symptom is
`E2250 There is no overloaded version of 'Create'` in `PasVulkan.Framework`
(an `array of TVkUInt32` no longer matches `array of TpvUInt32`), but the real
danger is silent: structs that do not match the C ABI. Both are now `Int32` /
`UInt32`, which every Delphi since XE2 and FreePascal define as 32-bit. No
change on Windows.

## 0005 — `libdl` for Delphi in `PasVulkan.CrashReport`

`dladdr`, `dlopen` and `dlsym` were declared `external 'dl'`. FreePascal turns
that into `-ldl`; Delphi's Android linker takes it as a file named `dl` and
fails with `cannot find dl: No such file or directory`. A constant now gives
`'dl'` for FreePascal and the library path for Delphi, as Delphi's own
`Posix.Base` does (`/system/lib64/libdl.so` on Android64).
`PasVulkan.CrashReport.MiniDump.pas` has the same declarations but is not
linked into the packages, so it is left alone.

## 0006 — PasMP on Delphi ARM64

* Under Delphi, PasMP sets its own `CPU64` symbol only for `CPUx64`. On ARM64
  Delphi defines `CPU64BITS` (and `CPUARM64`), so PasMP took the target for
  32-bit and left out the 64-bit atomics its queues use (`E2250` on `Add` and
  `CompareExchange`). `CPU64` is now also defined from `CPU64BITS`.
  Win64 already defined it, so nothing changes there.
* `TThread.Create(CreateSuspended, StackSize)` exists in Delphi only on
  Windows (`E2034 Too many actual parameters`). Elsewhere the worker threads
  now use the default stack size.

## 0007 — PasDblStrUtils on Delphi's LLVM targets

`System.Math` on Delphi's LLVM-based compilers (`EXTERNALLINKER`: Android, iOS,
Linux) has `TRoundingMode` and `TArithmeticExceptionMask`, but not the x87
`TFPURoundingMode`, `TFPUExceptionMask` or `TFPUPrecisionMode`, nor
`Get`/`SetPrecisionMode`. There the rounding mode type is `TRoundingMode`, the
exception mask `TArithmeticExceptionMask`, and precision control (x87-only
anyway) is skipped.

### Submodule patches

0006 and 0007 change files inside the `externals/pasmp` and
`externals/pasdblstrutils` submodules. Their paths are relative to the PasVulkan
root, so the script applies them like the others, but the changes show up in
the submodules' own `git status`, not PasVulkan's.

## Applying

```powershell
powershell -ExecutionPolicy Bypass -File Patches\apply-pasvulkan-patches.ps1 -PasVulkanRoot D:\Vulkan
```

The script is idempotent: patches already present are skipped. Add `-Revert` to
undo them.

Patches 0002 and 0003 are CRLF and were produced against PasVulkan `master` at
commit `bccc73408`. 0004–0007 were produced against the local checkout on
2026-10-15 (PasVulkan branch `fix/load-vulkan-library-once`, `externals/pasmp`
at `d58e2e6`).
