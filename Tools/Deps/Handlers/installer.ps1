# Handler for "type": "installer": a vendor installer, downloaded, checked and run (elevated).
#
#   "version"      version to install, or "latest" (looked up at "versionUrl")
#   "minVersion"   an installed version at least this new counts as present
#   "versionUrl"   JSON giving the latest version; "versionKey" picks the field (e.g. "windows")
#   "url"          installer URL; may use {version}
#   "sha256"       pinned SHA-256 of the installer (for the pinned version)
#   "shaUrl"       JSON with a "sha" field, used when "sha256" is not given (e.g. for "latest")
#   "signer"       text that must appear in the Authenticode signer's subject
#   "installDir"   where it installs, e.g. "C:\\VulkanSDK\\{version}"
#   "args"         installer arguments; may use {installDir} and {version}
#   "elevate"      true: run the installer as administrator (UAC prompt)
#   "license"      { "name": "...", "url": "..." } accepted with -AcceptLicenses or at a prompt
#   "detect"       { "env": "VULKAN_SDK", "file": "Bin\\glslangValidator.exe" }: where an
#                  installed copy is found; its version is the folder name
#   "restart"      true: the installer sets environment variables, so running programs
#                  (Delphi, shells) need a restart

function Get-InstallerEnv([string]$Name) {
    [ordered]@{
        Process = [Environment]::GetEnvironmentVariable($Name, 'Process')
        User    = [Environment]::GetEnvironmentVariable($Name, 'User')
        Machine = [Environment]::GetEnvironmentVariable($Name, 'Machine')
    }
}

function ConvertTo-InstallerVersion([string]$Text) {
    $v = $null
    if ($Text -and [version]::TryParse($Text, [ref]$v)) { return $v }
    $null
}

function Get-InstallerJson([string]$Url) {
    (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content | ConvertFrom-Json
}

function Format-InstallerArg([string]$a) {
    if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
}

@{
    Type = 'installer'

    Resolve = {
        param($Dep)
        $version = Get-Prop $Dep 'version'
        if (-not $version) { throw "Dependency '$($Dep.name)' has no version." }
        if ($version -eq 'latest') {
            $j = Get-InstallerJson (Get-Prop $Dep 'versionUrl')
            $version = Get-Prop $j (Get-Prop $Dep 'versionKey' 'version')
            if (-not $version) { throw "Could not read the latest version from $($Dep.versionUrl)." }
        }
        $pin = [ordered]@{ version = $version }
        $vars = Get-DepVars $Dep $pin
        $pin.url = Expand-Tokens $Dep.url $vars
        $sha = $null
        if ((Get-Prop $Dep 'version') -ne 'latest') { $sha = Get-Prop $Dep 'sha256' }
        if (-not $sha -and (Get-Prop $Dep 'shaUrl')) {
            $sha = Get-Prop (Get-InstallerJson (Expand-Tokens $Dep.shaUrl $vars)) 'sha'
        }
        if ($sha) { $pin.sha256 = $sha.ToLowerInvariant() }
        $pin
    }

    Test = {
        param($Dep, $Pin)
        $res = New-TestResult
        $detect = Get-Prop $Dep 'detect'
        $envName = Get-Prop $detect 'env'
        $file = Get-Prop $detect 'file' ''
        $minVersion = ConvertTo-InstallerVersion (Get-Prop $Dep 'minVersion' (Get-Prop $Pin 'version'))
        $pinned = Get-Prop $Pin 'version'

        $dir = $null
        if ($envName) {
            $vals = Get-InstallerEnv $envName
            $dir = $vals.Process
            if (-not $dir) {
                $dir = $vals.User
                if (-not $dir) { $dir = $vals.Machine }
                if ($dir) { Add-Finding $res warn "$envName is set to $dir, but not in this process: restart Delphi and open shells" }
            }
            elseif ($vals.Machine -and $vals.Machine.TrimEnd('\') -ne $dir.TrimEnd('\') -and -not $vals.User) {
                Add-Finding $res warn "$envName here is $dir, but the system value is now $($vals.Machine): restart Delphi and open shells"
            }
        }
        if (-not $dir) {
            $installDir = (Get-DepVars $Dep $Pin).installDir
            if ($installDir -and (Test-Path -LiteralPath (Join-Path $installDir $file))) {
                Add-Finding $res warn "found at $installDir, but $envName is not set"
                $dir = $installDir
            }
            else {
                $what = 'not installed'
                if ($envName) { $what = "not installed ($envName is not set)" }
                Add-Finding $res missing $what
                return $res
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $dir $file))) {
            Add-Finding $res missing "$dir has no $file"
            return $res
        }
        $res.Info.Dir = $dir
        $v = ConvertTo-InstallerVersion (Split-Path -Leaf $dir.TrimEnd('\'))
        if ($null -eq $v) { Add-Finding $res warn "found at $dir, but its version cannot be read from the folder name"; return $res }
        $res.Info.Version = "$v"
        if ($minVersion -and $v -lt $minVersion) { Add-Finding $res outdated "$v at $dir is older than the required $minVersion" }
        elseif ($pinned -and "$v" -ne $pinned) { Add-Finding $res ok "$v at $dir (pinned $pinned; this one is new enough)" }
        else { Add-Finding $res ok "$v at $dir" }
        $res
    }

    Install = {
        param($Dep, $Pin)
        $vars = Get-DepVars $Dep $Pin
        $version = $vars.version
        $lic = Get-Prop $Dep 'license'
        if ($lic -and -not $script:Ctx.AcceptLicenses) {
            $licName = Get-Prop $lic 'name' $Dep.name
            Write-Step 'LICENCE' "$licName - $(Get-Prop $lic 'url' '')" Yellow
            if (-not $script:Ctx.Interactive) { throw "Installing $($Dep.name) means accepting the $licName. Read it, then run again with -AcceptLicenses." }
            if (-not (Confirm-Action "Do you accept the $licName?")) { throw "Licence not accepted; $($Dep.name) was not installed." }
        }

        $dl = Get-CachedDownload (Get-Prop $Pin 'url') "$($Dep.name)\$version" (Get-Prop $Pin 'sha256')
        if (-not (Get-Prop $Pin 'sha256')) { Write-Step 'WARN' "no SHA-256 pinned; the download was checked by signature only ($($dl.Sha256))" Yellow }

        $signer = Get-Prop $Dep 'signer'
        $sig = Get-AuthenticodeSignature -LiteralPath $dl.Path
        if ($sig.Status -ne 'Valid') { throw "$($dl.Path) is not validly signed ($($sig.Status)). Not running it." }
        if ($signer -and $sig.SignerCertificate.Subject -notmatch [regex]::Escape($signer)) {
            throw "$($dl.Path) is signed by '$($sig.SignerCertificate.Subject)', not '$signer'. Not running it."
        }
        Write-Step 'SIGNED' $sig.SignerCertificate.Subject Green

        $argList = @(@(Get-Prop $Dep 'args' @()) | ForEach-Object { Format-InstallerArg (Expand-Tokens $_ $vars) })
        $start = @{ FilePath = $dl.Path; Wait = $true; PassThru = $true }
        if ($argList.Count -gt 0) { $start.ArgumentList = ($argList -join ' ') }
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ((Get-Prop $Dep 'elevate' $false) -and -not $isAdmin) {
            $start.Verb = 'RunAs'
            Write-Step 'INSTALL' "$($Dep.name) $version (accept the Windows administrator prompt)" Cyan
        }
        else { Write-Step 'INSTALL' "$($Dep.name) $version" Cyan }
        $p = Start-Process @start
        if ($p.ExitCode -ne 0) { throw "The installer exited with code $($p.ExitCode)." }

        # Pick up what the installer set machine-wide, for the rest of this run.
        $envName = Get-Prop (Get-Prop $Dep 'detect') 'env'
        if ($envName) {
            $vals = Get-InstallerEnv $envName
            $new = $vals.User
            if (-not $new) { $new = $vals.Machine }
            if ($new) { [Environment]::SetEnvironmentVariable($envName, $new, 'Process') }
        }
        if (Get-Prop $Dep 'restart' $false) { $script:Ctx.RestartNeeded = $true }
        $pin = ConvertTo-Hashtable $Pin
        $pin.sha256 = $dl.Sha256
        $pin
    }

    # A newer version installs side by side; the installer repoints the environment variable.
    Update = { param($Dep, $Pin) & $script:Handlers['installer'].Install $Dep $Pin }
}
