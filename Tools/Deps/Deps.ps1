<#
.SYNOPSIS
    Installs, checks or updates the dependencies listed in a dependencies.json manifest.

.DESCRIPTION
    Each dependency in the manifest has a "type". A handler in Tools\Deps\Handlers\<type>.ps1
    knows how to test, install and update that type:

      git        a pinned clone, chosen submodules and local patches (PasVulkan)
      installer  a vendor installer, signature-checked and run elevated (Vulkan SDK)
      detect     something the tool only looks for and reports (GPU driver, Git)

    A manifest can include other manifests ("includes"), so a repository that builds on this
    one (for example the PRO repository) lists only its own dependencies and still sets up
    everything with one run. Dependencies outside the "core" feature are installed only when
    their feature is asked for with -Feature.

    Commands:
      install  (default) install what is missing; never changes anything already there
      check    report only; exit code 1 if a required dependency is missing or wrong
      update   also move existing dependencies to the pinned versions (refuses when a
               checkout has local work, unless -Force)

    After install/update, the tool writes Dependencies.local.props next to each manifest. The
    project files import it through Dependencies.props, so the search paths follow wherever the
    dependencies were installed. It also writes dependencies.lock.json with the exact versions
    it resolved.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Tools\Deps\Deps.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Tools\Deps\Deps.ps1 check
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Tools\Deps\Deps.ps1 install -DepsRoot E:\Deps -AcceptLicenses
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'check', 'update')]
    [string]$Command = 'install',

    # The manifest to run. Default: dependencies.json at the root of this repository.
    [string]$Manifest,

    # Where dependencies are installed. Default: $env:DEPS_ROOT, else the manifest's "depsRoot".
    [string]$DepsRoot,

    # Extra features to include (e.g. physics). "all" includes every feature.
    [string[]]$Feature = @(),

    # Only process these dependencies (by name).
    [string[]]$Only = @(),

    # Accept vendor licences (e.g. the Vulkan SDK's) without asking.
    [switch]$AcceptLicenses,

    # Answer yes to confirmations (e.g. installing Git with winget).
    [switch]$Yes,

    # update: also move checkouts that are on a branch or have local commits.
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar in 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$script:ToolDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------------------------------------
# Helpers shared by the engine and the handlers
# ---------------------------------------------------------------------------------------------

# Reads a property from a hashtable or a ConvertFrom-Json object, with a default.
function Get-Prop($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
        return $Default
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Write-Step([string]$Tag, [string]$Text, [string]$Color = 'Gray') {
    Write-Host ('  {0,-8} {1}' -f $Tag, $Text) -ForegroundColor $Color
}

# Runs a native program and captures stdout+stderr. Native tools write diagnostics to stderr
# even when nothing is wrong; under ErrorActionPreference=Stop PowerShell would treat that as
# a terminating error, so the preference is relaxed around the call.
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = @(& $Exe @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $prev }
    [pscustomobject]@{ Code = $code; Lines = $out; Text = ($out -join "`n").Trim() }
}

# Runs a native program with its output going straight to the console (for long operations
# such as a clone, so the user sees progress). Returns the exit code.
function Invoke-NativeLive([string]$Exe, [string[]]$Arguments) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Exe @Arguments | Out-Host; return $LASTEXITCODE }
    finally { $ErrorActionPreference = $prev }
}

function Invoke-Git([string]$Dir, [string[]]$Arguments) {
    $a = @()
    if ($Dir) { $a += @('-C', $Dir) }
    Invoke-Native 'git' ($a + $Arguments)
}

function Invoke-GitChecked([string]$Dir, [string[]]$Arguments) {
    $r = Invoke-Git $Dir $Arguments
    if ($r.Code -ne 0) { throw "git $($Arguments -join ' ') failed in ${Dir}:`n$($r.Text)" }
    $r
}

function Invoke-GitLive([string]$Dir, [string[]]$Arguments) {
    $a = @()
    if ($Dir) { $a += @('-C', $Dir) }
    $code = Invoke-NativeLive 'git' ($a + $Arguments)
    if ($code -ne 0) { throw "git $($Arguments -join ' ') failed ($code)." }
}

# Replaces {Token} placeholders. {env:NAME} reads an environment variable.
function Expand-Tokens([string]$Text, [hashtable]$Vars) {
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    foreach ($m in [regex]::Matches($Text, '\{([A-Za-z][A-Za-z0-9_]*(?::[A-Za-z0-9_]+)?)\}')) {
        [void]$sb.Append($Text.Substring($pos, $m.Index - $pos))
        $k = $m.Groups[1].Value
        if ($k -like 'env:*') { $v = [Environment]::GetEnvironmentVariable($k.Substring(4)) }
        elseif ($Vars.ContainsKey($k)) { $v = $Vars[$k] }
        else { throw "Unknown token {$k} in '$Text'." }
        [void]$sb.Append([string]$v)
        $pos = $m.Index + $m.Length
    }
    [void]$sb.Append($Text.Substring($pos))
    $sb.ToString()
}

function Resolve-FullPath([string]$Path, [string]$BaseDir) {
    if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $BaseDir $Path }
    [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

# The token values for one dependency: DepsRoot, ManifestDir, name, version, path, installDir.
function Get-DepVars($Dep, $Pin) {
    $vars = @{
        DepsRoot    = $script:Ctx.DepsRoot
        ManifestDir = $Dep._Manifest.Dir
        name        = $Dep.name
    }
    $version = Get-Prop $Pin 'version' (Get-Prop $Dep 'version')
    if ($version) { $vars.version = $version }
    foreach ($key in @('path', 'installDir')) {
        $raw = Get-Prop $Dep $key
        if ($raw) { $vars[$key] = Resolve-FullPath (Expand-Tokens $raw $vars) $Dep._Manifest.Dir }
    }
    $vars
}

function Expand-DepValue($Dep, $Pin, [string]$Text) { Expand-Tokens $Text (Get-DepVars $Dep $Pin) }

# A handler's Test result. Findings are ranked; the result's status is the worst one.
# A finding marked -Safe can be fixed without touching anything that already works (e.g. a
# patch not applied yet), so "install" fixes it too; anything else needs "update".
$script:Rank = @{ ok = 0; warn = 1; outdated = 2; mismatch = 3; missing = 4 }

function New-TestResult {
    @{ Status = 'ok'; Findings = New-Object System.Collections.ArrayList; Exports = @{}; Info = @{} }
}

function Add-Finding($Result, [string]$Level, [string]$Text, [switch]$Safe) {
    [void]$Result.Findings.Add([pscustomobject]@{ Level = $Level; Text = $Text; Safe = [bool]$Safe })
    if ($script:Rank[$Level] -gt $script:Rank[$Result.Status]) { $Result.Status = $Level }
}

function Confirm-Action([string]$Question) {
    if ($script:Ctx.Yes) { return $true }
    if (-not $script:Ctx.Interactive) { return $false }
    $a = Read-Host "  $Question [y/N]"
    return ($a -match '^(y|yes)$')
}

# Downloads a file into the cache (reused on later runs) and checks its SHA-256 if one is given.
function Get-CachedDownload([string]$Url, [string]$CacheName, [string]$Sha256) {
    $dir = Join-Path $script:Ctx.CacheDir $CacheName
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $file = Join-Path $dir ([IO.Path]::GetFileName(([uri]$Url).AbsolutePath))
    if (-not (Test-Path -LiteralPath $file)) {
        Write-Step 'DOWNLOAD' $Url Cyan
        $tmp = "$file.partial"
        Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
        Move-Item -LiteralPath $tmp -Destination $file -Force
    }
    else { Write-Step 'CACHED' $file }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant()
    if ($Sha256 -and $actual -ne $Sha256.ToLowerInvariant()) {
        throw "SHA-256 of $file is $actual, but the manifest pins $Sha256. Delete the file to download it again."
    }
    [pscustomobject]@{ Path = $file; Sha256 = $actual }
}

function ConvertTo-Hashtable($Object) {
    $h = [ordered]@{}
    if ($null -eq $Object) { return $h }
    if ($Object -is [System.Collections.IDictionary]) { foreach ($k in $Object.Keys) { $h[$k] = $Object[$k] }; return $h }
    foreach ($p in $Object.PSObject.Properties) { $h[$p.Name] = $p.Value }
    $h
}

# ---------------------------------------------------------------------------------------------
# Manifests
# ---------------------------------------------------------------------------------------------

function Read-Manifest([string]$Path, [hashtable]$Seen) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($Seen.ContainsKey($full)) { return $Seen[$full] }
    if (-not (Test-Path -LiteralPath $full)) { throw "Manifest not found: $full" }
    $json = [IO.File]::ReadAllText($full) | ConvertFrom-Json
    if ((Get-Prop $json 'schema' 0) -ne 1) { throw "$full has an unsupported schema (expected 1)." }
    $m = [pscustomobject]@{
        Path = $full; Dir = (Split-Path -Parent $full); Json = $json
        Includes = New-Object System.Collections.ArrayList
        Deps = New-Object System.Collections.ArrayList
    }
    $Seen[$full] = $m
    foreach ($inc in @(Get-Prop $json 'includes' @())) {
        $incPath = Resolve-FullPath $inc $m.Dir
        [void]$m.Includes.Add((Read-Manifest $incPath $Seen))
    }
    foreach ($d in @(Get-Prop $json 'dependencies' @())) {
        if (-not (Get-Prop $d 'name')) { throw "A dependency in $full has no name." }
        if (-not (Get-Prop $d 'type')) { throw "Dependency '$($d.name)' in $full has no type." }
        $d | Add-Member -NotePropertyName '_Manifest' -NotePropertyValue $m -Force
        [void]$m.Deps.Add($d)
    }
    $m
}

function Get-DepJson($Dep) { $Dep | Select-Object -Property * -ExcludeProperty _Manifest | ConvertTo-Json -Depth 20 -Compress }

# All dependencies of a manifest, its includes first, each name once.
function Get-AllDeps($M, [hashtable]$ByName, [hashtable]$Visited) {
    $list = New-Object System.Collections.ArrayList
    if ($Visited.ContainsKey($M.Path)) { return , $list }
    $Visited[$M.Path] = $true
    foreach ($inc in $M.Includes) { foreach ($d in (Get-AllDeps $inc $ByName $Visited)) { [void]$list.Add($d) } }
    foreach ($d in $M.Deps) {
        if ($ByName.ContainsKey($d.name)) {
            if ((Get-DepJson $ByName[$d.name]) -ne (Get-DepJson $d)) {
                throw "Dependency '$($d.name)' is declared differently in $($ByName[$d.name]._Manifest.Path) and $($M.Path)."
            }
            continue
        }
        $ByName[$d.name] = $d
        [void]$list.Add($d)
    }
    , $list
}

function Get-Sha256Text([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function Write-TextFileIfChanged([string]$Path, [string]$Text) {
    if ((Test-Path -LiteralPath $Path) -and ([IO.File]::ReadAllText($Path) -eq $Text)) { return $false }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
    $true
}

# Windows PowerShell's ConvertTo-Json indents erratically; re-indent with two spaces so the
# committed lock file diffs cleanly.
function Format-Json([string]$Json) {
    $indent = 0
    $out = foreach ($raw in ($Json -split "\r?\n")) {
        $line = $raw.Trim()
        if (-not $line) { continue }
        if ($line -match '^[\}\]]') { $indent-- }
        ('  ' * [Math]::Max($indent, 0)) + ($line -replace '^("(?:[^"\\]|\\.)*"):\s+', '$1: ')
        if ($line -match '[\{\[]$') { $indent++ }
    }
    ($out -join "`r`n") -replace '\{\r\n\s*\}', '{}'
}

function Read-Lock($M) {
    $p = Join-Path $M.Dir 'dependencies.lock.json'
    if (-not (Test-Path -LiteralPath $p)) { return @{} }
    $j = [IO.File]::ReadAllText($p) | ConvertFrom-Json
    ConvertTo-Hashtable (Get-Prop $j 'dependencies')
}

function Write-Lock($M, $Entries) {
    $deps = [ordered]@{}
    foreach ($d in $M.Deps) { if ($Entries.Contains($d.name)) { $deps[$d.name] = $Entries[$d.name] } }
    $doc = [ordered]@{
        schema       = 1
        comment      = 'Generated by Tools\Deps\Deps.ps1: the exact versions resolved for dependencies.json. Commit it.'
        dependencies = $deps
    }
    $p = Join-Path $M.Dir 'dependencies.lock.json'
    if (Write-TextFileIfChanged $p ((Format-Json ($doc | ConvertTo-Json -Depth 20)) + "`r`n")) { Write-Step 'WROTE' $p }
}

function Write-Props($M, [System.Collections.IDictionary]$Exports) {
    $lines = @(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<!-- Generated by Tools\Deps\Deps.ps1 for this machine. Do not edit and do not commit:'
        '     run the tool again instead. Dependencies.props imports it. -->'
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'
        '  <PropertyGroup>'
    )
    foreach ($k in ($Exports.Keys | Sort-Object)) {
        $v = [Security.SecurityElement]::Escape([string]$Exports[$k])
        $lines += "    <$k>$v</$k>"
    }
    $lines += @('  </PropertyGroup>', '</Project>', '')
    $p = Join-Path $M.Dir 'Dependencies.local.props'
    if (Write-TextFileIfChanged $p ($lines -join "`r`n")) { Write-Step 'WROTE' $p }
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

$exitCode = 0
# "powershell -File" passes "a,b" as one string; accept both forms.
$Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Feature = @($Feature | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
try {
    if (-not $Manifest) { $Manifest = Join-Path $script:ToolDir '..\..\dependencies.json' }
    $root = Read-Manifest $Manifest @{}

    if (-not $DepsRoot) { $DepsRoot = $env:DEPS_ROOT }
    if (-not $DepsRoot) { $DepsRoot = Get-Prop $root.Json 'depsRoot' '..' }
    $DepsRoot = Resolve-FullPath $DepsRoot $root.Dir
    if ($DepsRoot -match '^[A-Za-z]:$') { $DepsRoot += '\' }   # "D:" alone means the current dir on D:

    $cacheDir = $env:DEPS_CACHE
    if (-not $cacheDir) { $cacheDir = Join-Path $env:LOCALAPPDATA 'VulkanPackage\deps-cache' }

    $interactive = [Environment]::UserInteractive
    try { if ([Console]::IsInputRedirected) { $interactive = $false } } catch { }

    $script:Ctx = @{
        Command = $Command; DepsRoot = $DepsRoot; CacheDir = $cacheDir
        AcceptLicenses = [bool]$AcceptLicenses; Yes = [bool]$Yes; Force = [bool]$Force
        Interactive = $interactive; RestartNeeded = $false
    }

    # Handlers: each file returns @{ Type; Resolve; Test; Install; Update }.
    $script:Handlers = @{}
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $script:ToolDir 'Handlers') -Filter '*.ps1')) {
        $h = . $f.FullName
        $script:Handlers[$h.Type] = $h
    }

    $byName = @{}
    $deps = Get-AllDeps $root $byName @{}

    $wantAll = $Feature -contains 'all'
    $selected = @($deps | Where-Object {
            $feat = Get-Prop $_ 'feature' 'core'
            ($feat -eq 'core' -or $wantAll -or $Feature -contains $feat) -and
            ($Only.Count -eq 0 -or $Only -contains $_.name)
        })
    foreach ($o in $Only) { if (-not $byName.ContainsKey($o)) { throw "No dependency named '$o'." } }

    Write-Host ''
    Write-Host "Dependencies ($Command) - manifest $($root.Path)" -ForegroundColor White
    Write-Host "  root $DepsRoot   cache $cacheDir" -ForegroundColor DarkGray

    # Lock entries per manifest.
    $locks = @{}
    $manifests = @{}
    foreach ($d in $deps) {
        $mp = $d._Manifest.Path
        if (-not $locks.ContainsKey($mp)) { $locks[$mp] = Read-Lock $d._Manifest; $manifests[$mp] = $d._Manifest }
    }

    $exports = @{}       # dependency name -> its exports
    $summary = New-Object System.Collections.ArrayList

    foreach ($dep in $selected) {
        $handler = $script:Handlers[$dep.type]
        if (-not $handler) { throw "Dependency '$($dep.name)': no handler for type '$($dep.type)'." }
        $optional = [bool](Get-Prop $dep 'optional' $false)
        Write-Host ''
        Write-Host "[$($dep.name)] $(Get-Prop $dep 'description' $dep.type)" -ForegroundColor White

        $status = 'error'
        try {
            # Pin: the lock entry while the manifest entry is unchanged, else resolve it again.
            $lock = $locks[$dep._Manifest.Path]
            $hash = Get-Sha256Text (Get-DepJson $dep)
            $entry = $null
            if ($lock.Contains($dep.name)) { $entry = $lock[$dep.name] }
            if ($Command -ne 'update' -and $null -ne $entry -and (Get-Prop $entry 'manifestHash') -eq $hash) {
                $pin = Get-Prop $entry 'pin'
            }
            else {
                $pin = & $handler.Resolve $dep
            }

            $result = & $handler.Test $dep $pin
            $act = $null
            if ($Command -ne 'check') {
                if ($result.Status -eq 'missing') { $act = 'Install' }
                elseif ($script:Rank[$result.Status] -ge $script:Rank['outdated']) {
                    $unsafe = @($result.Findings | Where-Object { $script:Rank[$_.Level] -ge $script:Rank['outdated'] -and -not $_.Safe })
                    if ($Command -eq 'update' -or $unsafe.Count -eq 0) { $act = 'Update' }
                }
            }
            if ($act) {
                foreach ($f in $result.Findings) { if ($f.Level -ne 'ok') { Write-Step $f.Level.ToUpper() $f.Text Yellow } }
                $newPin = & $handler.$act $dep $pin
                if ($newPin) { $pin = $newPin }
                $result = & $handler.Test $dep $pin
            }

            foreach ($f in $result.Findings) {
                $color = switch ($f.Level) { 'ok' { 'Green' } 'warn' { 'Yellow' } default { 'Red' } }
                Write-Step $f.Level.ToUpper() $f.Text $color
            }
            $status = $result.Status
            if ($script:Rank[$status] -ge $script:Rank['outdated'] -and $Command -eq 'install') {
                Write-Step 'HINT' "Run 'update' to fix this (it will not discard local work)." DarkGray
            }

            if ($Command -ne 'check') {
                $lock[$dep.name] = [ordered]@{ type = $dep.type; manifestHash = $hash; pin = $pin }
            }
            if ($script:Rank[$status] -le $script:Rank['warn'] -and $result.Exports.Count -gt 0) {
                $exports[$dep.name] = $result.Exports
            }
        }
        catch {
            $status = 'error'
            Write-Step 'ERROR' $_.Exception.Message Red
        }
        $failed = $script:Rank.ContainsKey($status) -eq $false -or $script:Rank[$status] -ge $script:Rank['outdated']
        if ($failed -and -not $optional) { $exitCode = 1 }
        [void]$summary.Add([pscustomobject]@{ Name = $dep.name; Status = $status; Optional = $optional })
    }

    if ($Command -ne 'check') {
        foreach ($mp in $manifests.Keys) { Write-Lock $manifests[$mp] $locks[$mp] }
        # Each manifest's props get the exports of its own dependencies and of its includes.
        foreach ($mp in $manifests.Keys) {
            $m = $manifests[$mp]
            $props = [ordered]@{}
            foreach ($d in (Get-AllDeps $m @{} @{})) {
                if ($exports.ContainsKey($d.name)) { foreach ($k in $exports[$d.name].Keys) { $props[$k] = $exports[$d.name][$k] } }
            }
            if ($props.Count -gt 0) { Write-Props $m $props }
        }
    }

    Write-Host ''
    Write-Host 'Summary' -ForegroundColor White
    foreach ($s in $summary) {
        $color = switch ($s.Status) { 'ok' { 'Green' } 'warn' { 'Yellow' } default { if ($s.Optional) { 'Yellow' } else { 'Red' } } }
        $opt = ''
        if ($s.Optional) { $opt = ' (optional)' }
        Write-Host ('  {0,-16} {1}{2}' -f $s.Name, $s.Status, $opt) -ForegroundColor $color
    }
    if ($script:Ctx.RestartNeeded) {
        Write-Host ''
        Write-Host '  Restart Delphi and any open command prompts so they see the new environment variables.' -ForegroundColor Yellow
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 2
}
exit $exitCode
