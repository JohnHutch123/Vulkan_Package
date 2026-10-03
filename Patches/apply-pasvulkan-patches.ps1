<#
.SYNOPSIS
    Applies (or reverts) the local PasVulkan patches needed to build the Vulkan packages.
.DESCRIPTION
    Idempotent: a patch that is already present is reported and skipped.
    Run this after every `git pull` of PasVulkan.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File apply-pasvulkan-patches.ps1 -PasVulkanRoot D:\Vulkan
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File apply-pasvulkan-patches.ps1 -Revert
#>
[CmdletBinding()]
param(
    [string]$PasVulkanRoot = 'D:\Vulkan',
    [switch]$Revert
)

$ErrorActionPreference = 'Stop'

# git writes diagnostics to stderr even on expected failures (e.g. a --check that
# legitimately does not apply). Under $ErrorActionPreference = 'Stop' PowerShell
# turns that stderr into a terminating error, so native git is always called
# through this helper, which captures both streams and returns the exit code.
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $script:GitOutput = & git @Arguments 2>&1 | Out-String
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prev
    }
}

if (-not (Test-Path -LiteralPath $PasVulkanRoot)) {
    throw "PasVulkan root not found: $PasVulkanRoot"
}

$patchDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$patches = @(Get-ChildItem -LiteralPath $patchDir -Filter '*.patch' | Sort-Object Name)
if ($patches.Count -eq 0) { throw "No .patch files found in $patchDir" }

$failed = 0

Push-Location -LiteralPath $PasVulkanRoot
try {
    foreach ($p in $patches) {
        # A patch that reverse-applies cleanly is already present in the tree.
        $alreadyApplied = (Invoke-Git apply --check --reverse -- $p.FullName) -eq 0

        if ($Revert) {
            if (-not $alreadyApplied) {
                Write-Host "SKIP    $($p.Name) (not applied)"
                continue
            }
            if ((Invoke-Git apply --reverse -- $p.FullName) -ne 0) {
                $failed++
                Write-Warning "Failed to revert $($p.Name):`n$script:GitOutput"
                continue
            }
            Write-Host "REVERT  $($p.Name)"
            continue
        }

        if ($alreadyApplied) {
            Write-Host "SKIP    $($p.Name) (already applied)"
            continue
        }

        if ((Invoke-Git apply --check -- $p.FullName) -ne 0) {
            $failed++
            Write-Warning "$($p.Name) does not apply cleanly - upstream has probably changed. Apply it by hand (see README.md).`n$script:GitOutput"
            continue
        }
        if ((Invoke-Git apply -- $p.FullName) -ne 0) {
            $failed++
            Write-Warning "Failed to apply $($p.Name):`n$script:GitOutput"
            continue
        }
        Write-Host "APPLY   $($p.Name)"
    }
}
finally {
    Pop-Location
}

if ($failed -gt 0) {
    Write-Error "$failed patch(es) could not be processed."
    exit 1
}
exit 0
