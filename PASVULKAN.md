# PasVulkan dependency

This package is built on [PasVulkan](https://github.com/BeRo1985/pasvulkan), checked out next to this repo
as `D:\Vulkan` (the `.dproj` search paths and `VulkanPkgR280`'s `contains` list point there).

## Version

Tested with PasVulkan `master` at `bccc734` ("More work", 2026-09-30) **plus five fixes** on the branch
`fix/delphi-win32-and-aftermath-deps` of that checkout. Without them, the latest PasVulkan does not build
with Delphi for Win32, nor with Delphi 11, and it drags its whole application framework into
`VulkanPkgR280`. The fixes are proposed upstream; until they are merged, build against that branch.

| # | Problem in PasVulkan `master` | Where it bites | Fix on the branch |
|---|---|---|---|
| 1 | `TPasMPInterlocked.Increment` on 64-bit counters. PasMP declares its 64-bit `Increment`/`Decrement`/`Add` only for `CPU64`, so this is **E2250** on Win32. | `PasVulkan.Framework` (`TpvVulkanTexture`), `PasVulkan.VectorPath`, `PasVulkan.FrameTrace`: every Win32 build. | `pvAtomicIncrement64` in `PasVulkan.Types`: PasMP's `Increment` on 64-bit targets, a `CompareExchange` loop on 32-bit. |
| 2 | `PasVulkan.Compression.LZMA` links `lzma_c\lzmadec_windows_x86_32.o`, whose symbol is `_LzmaDecode`, but declares it as `LzmaDecode`: **E2065** on Win32. | Anything using `PasVulkan.Compression` (e.g. `PasVulkan.Application`) for Win32. | Use `'_LzmaDecode'` for Delphi on Windows x86-32. FreePascal keeps the plain name (not tested here). |
| 3 | `PasVulkan.NVIDIA.AfterMath` uses `PasVulkan.Application`, and `PasVulkan.Framework` uses `AfterMath`. | Any user of `PasVulkan.Framework`, including `VulkanPkgR280`, compiles about 25 extra units: application, audio, VR, resources, assets, compression, crash dumps and game input. | `AfterMath` gets two optional hooks, for the application name and to describe a device address. `PasVulkan.Application` sets them. |
| 4 | `ChangeDisplaySettingsW(nil, 0)` / `(@devMode, …)`: Delphi 11 declares the parameter `var TDeviceModeW`. **E2033** on Delphi 11. | `PasVulkan.Application` with Delphi 11. | A private `pvChangeDisplaySettingsW` import with an untyped pointer. |
| 5 | `PasVulkan.Framework` lists `PasVulkan.XML` but uses nothing from it. | Every user of the framework links the XML parser. | Removed from the uses clause. |

All five were checked with Delphi 11, 12 and 13, Win32 and Win64. Two kinds of build were used: this repo's
packages, and a program using `PasVulkan.Framework`, `AfterMath`, `FrameTrace`, `VectorPath` and
`PasVulkan.Application`.

## What this package uses

The runtime units use only six PasVulkan units directly: `Vulkan`, `PasVulkan.Types`, `PasVulkan.Math`,
`PasVulkan.Math.Double`, `PasVulkan.Collections` and `PasVulkan.Framework`. `VulkanPkg_SDL2R280` adds
`PasVulkan.SDL2`. Everything else comes in through `PasVulkan.Framework`'s own uses.

`VulkanPkgR280` lists every unit it compiles in its `contains` clause, so none is "implicitly imported"
(W1033). With the fixes above, that is 24 PasVulkan units, down from about 49 with PasVulkan `master`:

- **Bindings and core:** `Vulkan`, `PasVulkan.Types`, `.Math`, `.Math.Double`, `.Collections`, `.Utils`, `.Streams`, `.CPU.Info`,
  `.HighResolutionTimer`, `.Framework`, `.NVIDIA.AfterMath`
- **Image loaders**, used by `TpvVulkanTexture`: `.Image.BMP`, `.JPEG`, `.PNG`, `.QOI`, `.TGA`, `.Image.Utils`, and
  `.Compression.Deflate` for PNG
- **Crash reporting:** `.CrashReport`, `.SymbolTable`. `PasVulkan.Utils.DumpExceptionCallStack` delegates to it.
- **Externals:** `PasMP`, `PasJSON` (the framework's memory reports), `PUCU` (Unicode, used by `PasVulkan.Types`),
  `PasDblStrUtils`

## Keeping the PasVulkan footprint small

- **Done (fixes 3 and 5):** cutting `AfterMath` loose from `PasVulkan.Application` and dropping the unused
  `PasVulkan.XML` take `VulkanPkgR280` from about 49 PasVulkan units to 24.
- **Possible next step upstream:** `PasVulkan.Utils` → `PasVulkan.CrashReport` → `PasVulkan.SymbolTable` is
  about 5,500 lines that only `DumpExceptionCallStack` needs. The same hook pattern as `AfterMath` would make
  it optional. It was left alone because upstream deliberately merged two copies into `CrashReport`.
- **Not worth changing:** the image loaders (texture loading), `PasJSON` (the framework uses it), and `PUCU`
  (everything in PasVulkan depends on it through `PasVulkan.Types`).
- **In this repo:** keep new code to the six units above. Use a PasVulkan unit only when the feature needs it,
  and add any new one to `VulkanPkgR280`'s `contains` list (and the `.dproj`).

## After updating PasVulkan

1. Build the four core packages and `VulkanPkg_SDL2R280` with MSBuild for every Delphi version and platform,
   R280 first. Use `/t:Rebuild /p:Platform=Win32|Win64` after `rsvars.bat`.
2. A **W1033 "implicitly imported"** warning on `VulkanPkgR280.dpk` means PasVulkan started pulling in
   another unit. Find out why before adding it to `contains`: fix 3 was found this way.
3. Restore the project `.res` files the builds rewrite (`git checkout -- "Delphi */*.res"`).
