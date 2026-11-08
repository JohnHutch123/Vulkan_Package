# VulkanEnumCheck

`RunTime_Src/Vulkan_Components_Lookups.pas` keeps its own short-named copy of
many Vulkan enums (`TvgBorderColor` for `TVkBorderColor`, and so on) so they
can be published properties. When a new PasVulkan `Vulkan.pas` arrives, this
console program finds the Vulkan values those copies are missing, and can add
them.

There is no list of types to maintain. Each `Tvg` type is paired with its `TVk`
type through the conversion functions that already exist:

```pascal
Function GetVKBorderColor(Value: TvgBorderColor) : TVkBorderColor;
Function GetVGBorderColor(Value: TVkBorderColor) : TvgBorderColor;
```

## Build

Open `VulkanEnumCheck.dpr` in RAD Studio and build it (Delphi creates the
`.dproj`); tested with Delphi 12. It uses only `SysUtils` and `Classes`, so it
needs no PasVulkan search path. It also builds with Free Pascal
(`fpc VulkanEnumCheck.dpr`). Run from the IDE, it waits for Enter before
closing.

## Run

```
VulkanEnumCheck [Vulkan.pas] [Vulkan_Components_Lookups.pas] [-update] [-verbose] [-config=File] [-report=File]
```

With no paths it finds the lookups unit in `RunTime_Src` above the exe, and
`Vulkan.pas` under `%PASVULKAN%\src`, a `Vulkan` folder beside the repository,
`D:\Vulkan` or `C:\Vulkan` (the same places as `Tests\RunTests.bat`).

| Option | |
|---|---|
| `-update` | Add the new values to the lookups unit. The original is kept as `Vulkan_Components_Lookups.pas.bak`. |
| `-verbose` | Also list members a conversion function does not handle, reserved values, and types with no conversion functions. |
| `-config=File` | Exceptions file. Default: `VulkanEnumCheck.cfg` beside the exe, or in this folder. |
| `-report=File` | Also write the report to a file. |

Exit code: 0 nothing to do, 1 new values or problems found, 2 error.

## What it reports

```
  OK    TvgBorderColor  <->  TVkBorderColor

  NEW   TvgImageTiling  <->  TVkImageTiling   1 new value(s)
        GetVKImageTiling / GetVGImageTiling
          + VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT   = 1000158000  -> TL_DRM_FORMAT_MODIFIER_EXT

  CHECK TvgFormat  <->  TVkFormat
        GetVKFormat / GetVGFormat
          ! GetVKFormat maps R8G8B8_SRGB to VK_FORMAT_B8G8R8_UNORM - by its name it should be VK_FORMAT_R8G8B8_SRGB
```

- `+` a Vulkan value with no mapping, and the short name it would get.
- `!` a problem:
  - a `VK_` name the lookups use that is no longer in `Vulkan.pas`, so the
    unit will not compile;
  - `GetVKxxx` and `GetVGxxx` disagreeing about a value;
  - a member whose name says one value but which is mapped to another (usually
    a copy-paste slip).

Aliases count as the same value. `VK_..._KHR` that equals the core value is not
"new", and two `Tvg` members that share a value are fine.

Not reported as new: `_MAX_ENUM`, `RESERVED` values, and for set types any
value that is not a single bit (`VK_ACCESS_NONE`, `VK_SHADER_STAGE_ALL`):
"none" is `[]` and a mask is a combination of members.

## What -update changes

For each type with new values:

1. The new members go at the end of the `Tvg` type, in Vulkan's order.
2. Each `GetVKxxx` / `GetVGxxx` function gets one line per value, copied from
   the last mapping line already in that function. Case lines, `If ... in Value`
   lines and `TestValue` lines all work.

Names follow the pattern of the existing members. For `TvgBorderColor`,
`BC_INT_OPAQUE_BLACK` from `VK_BORDER_COLOR_INT_OPAQUE_BLACK` gives "drop
`VK_BORDER_COLOR_`, add `BC_`". Some types also drop `_BIT` or a vendor suffix
(`PM_FIFO` from `VK_PRESENT_MODE_FIFO_KHR`). If the name is already declared in
the type but no conversion line uses it (for example `DS_VERTEX_INPUT`), only the
conversion lines are added. If the name is used anywhere else, the long name
without `VK_` is used and the report says to check it.

A published set can hold at most 32 members. If adding the new values would go
past that, nothing is added to that set; add the ones you need by hand and list
the rest as `ignore` in the config.

After `-update`, rebuild the package, then run the check again. It should show
no new values apart from anything it could not add.

## Config file

`VulkanEnumCheck.cfg`:

```
subset TvgDepthBufferFormat               # holds only some values on purpose
skip   TvgSomeType                        # do not check at all
ignore TvgDependencyFlagBits VK_DEPENDENCY_EXTENSION_586_BIT_IMG
ignore * VK_SOME_VALUE                    # for every type
name   VK_ATTACHMENT_LOAD_OP_NONE LOAD_OP_NONE
```

`subset` types are still checked for wrong or removed values; only missing
values are not reported.
