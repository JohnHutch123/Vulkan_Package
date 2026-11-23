# Handler for "type": "detect": something the tool looks for but does not install itself,
# except through winget when an id is given.
#
#   "command"         a program on PATH, e.g. "git"
#   "versionArgs"     arguments that print its version, e.g. [ "--version" ]
#   "versionPattern"  regex whose first group is the version (default: first a.b[.c[.d]])
#   "minVersion"      older is "outdated"
#   "file"            a file that must exist, e.g. "{env:SystemRoot}\\System32\\vulkan-1.dll";
#                     its file version is reported
#   "registry"        registry keys; any one present counts, e.g. Delphi installs
#   "winget"          winget package id to offer when it is missing (asks first, or -Yes)
#   "hint"            what to tell the user when it is missing

function Update-DetectPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

@{
    Type = 'detect'

    Resolve = { param($Dep) [ordered]@{} }

    Test = {
        param($Dep, $Pin)
        $res = New-TestResult
        $hint = Get-Prop $Dep 'hint' ''
        $suffix = ''
        if ($hint) { $suffix = " - $hint" }

        $cmd = Get-Prop $Dep 'command'
        if ($cmd) {
            $c = Get-Command $cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $c) { Add-Finding $res missing "$cmd not found on PATH$suffix"; return $res }
            $verArgs = @(Get-Prop $Dep 'versionArgs' @())
            if ($verArgs.Count -gt 0) {
                $out = (Invoke-Native $c.Source $verArgs).Text
                $pattern = Get-Prop $Dep 'versionPattern' '(\d+\.\d+(?:\.\d+){0,2})'
                $v = $null
                if ($out -match $pattern) { [void][version]::TryParse($Matches[1], [ref]$v) }
                $min = $null
                $minText = Get-Prop $Dep 'minVersion'
                if ($minText) { $min = [version]$minText }
                if ($null -eq $v) { Add-Finding $res warn "$cmd found at $($c.Source), version unknown" }
                elseif ($min -and $v -lt $min) { Add-Finding $res outdated "$cmd $v is older than $min$suffix" }
                else { Add-Finding $res ok "$cmd $v" }
            }
            else { Add-Finding $res ok "$cmd at $($c.Source)" }
        }

        $file = Get-Prop $Dep 'file'
        if ($file) {
            $f = Expand-DepValue $Dep $Pin $file
            if (-not (Test-Path -LiteralPath $f)) { Add-Finding $res missing "$f not found$suffix" }
            else {
                $ver = (Get-Item -LiteralPath $f).VersionInfo.ProductVersion
                if ($ver) { Add-Finding $res ok "$f $ver" } else { Add-Finding $res ok $f }
            }
        }

        $keys = @(Get-Prop $Dep 'registry' @())
        if ($keys.Count -gt 0) {
            $found = @($keys | Where-Object { Test-Path -LiteralPath $_ })
            if ($found.Count -eq 0) { Add-Finding $res missing "none found$suffix" }
            else { Add-Finding $res ok "found $(($found | ForEach-Object { Split-Path -Leaf $_ }) -join ', ')" }
        }
        $res
    }

    Install = {
        param($Dep, $Pin)
        $id = Get-Prop $Dep 'winget'
        $hint = Get-Prop $Dep 'hint' 'install it by hand'
        if (-not $id) { throw "Cannot install $($Dep.name) automatically: $hint." }
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget is not available: $hint." }
        if (-not (Confirm-Action "Install $($Dep.name) with 'winget install --id $id'?")) {
            throw "$($Dep.name) not installed (run with -Yes to allow it): $hint."
        }
        $wargs = @('install', '--id', $id, '--exact', '--source', 'winget', '--disable-interactivity')
        if ($script:Ctx.AcceptLicenses) { $wargs += @('--accept-package-agreements', '--accept-source-agreements') }
        Write-Step 'WINGET' "install $id" Cyan
        $code = Invoke-NativeLive 'winget' $wargs
        if ($code -ne 0) { throw "winget exited with code $code." }
        Update-DetectPath
    }

    Update = {
        param($Dep, $Pin)
        $id = Get-Prop $Dep 'winget'
        if (-not $id) { throw "Cannot update $($Dep.name) automatically: $(Get-Prop $Dep 'hint' 'update it by hand')." }
        if (-not (Confirm-Action "Upgrade $($Dep.name) with 'winget upgrade --id $id'?")) { throw "$($Dep.name) not upgraded." }
        $wargs = @('upgrade', '--id', $id, '--exact', '--source', 'winget', '--disable-interactivity')
        if ($script:Ctx.AcceptLicenses) { $wargs += @('--accept-package-agreements', '--accept-source-agreements') }
        $code = Invoke-NativeLive 'winget' $wargs
        if ($code -ne 0) { throw "winget exited with code $code." }
        Update-DetectPath
    }
}
