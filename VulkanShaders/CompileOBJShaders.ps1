# Run from any folder; glslangValidator and spirv-val are supplied by Vulkan SDK.
$ErrorActionPreference = 'Stop'
function Build([string]$source, [string]$output, [string[]]$defines) {
    & glslangValidator -V @defines (Join-Path $PSScriptRoot $source) -o (Join-Path $PSScriptRoot $output)
    if ($LASTEXITCODE -ne 0) { throw "Shader compilation failed: $output" }
    & spirv-val (Join-Path $PSScriptRoot $output)
    if ($LASTEXITCODE -ne 0) { throw "Shader validation failed: $output" }
}
Build 'OBJ.vert' 'OBJ_vert.spv' @()
Build 'OBJ.vert' 'OBJDouble_vert.spv' @('-DOBJ_DOUBLE=1')
foreach ($texture in @($false, $true)) {
    $baseName = 'OBJ'
    $defines = @()
    if ($texture) { $baseName = 'OBJTexture'; $defines += '-DOBJ_TEXTURE=1' }
    Build 'OBJ.frag' ($baseName + '_frag.spv') $defines
    Build 'OBJ.frag' ($baseName + 'Pick_frag.spv') ($defines + '-DOBJ_PICK=1')
    Build 'OBJ.frag' ($baseName + 'PickImage_frag.spv') ($defines + '-DOBJ_PICK_IMAGE=1')
}
