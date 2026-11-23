# Handler for "type": "git": a clone pinned to one commit, chosen submodules pinned to theirs,
# and local patches applied on top.
#
#   "url"         clone URL
#   "ref"         commit SHA (recommended), branch or tag; a branch/tag is resolved to a SHA
#                 and recorded in the lock file
#   "path"        where to clone, e.g. "{DepsRoot}\\Vulkan"
#   "partialClone" true (default) clones without file history (--filter=blob:none)
#   "submodules"  [ { "path": "externals/pasmp", "ref": "<sha>" } ]; a missing ref means the
#                 commit the superproject records. Other submodules are left alone.
#   "patches"     { "dir": "{ManifestDir}\\Patches", "files": [ "0004-....patch" ] }; without
#                 "files", every *.patch in dir. Paths in the patches are relative to "path".
#   "exports"     { "PASVULKAN_DIR": "{path}" } MSBuild properties for Dependencies.local.props
#
# The tool never moves a checkout that has local work: uncommitted changes other than the
# patches, commits not on any remote, or (without -Force) a checked-out branch.

function Get-GitDepPath($Dep, $Pin) { (Get-DepVars $Dep $Pin).path }

function Get-GitPatchFiles($Dep, $Pin) {
    $p = Get-Prop $Dep 'patches'
    if ($null -eq $p) { return @() }
    $dir = Resolve-FullPath (Expand-DepValue $Dep $Pin (Get-Prop $p 'dir')) $Dep._Manifest.Dir
    $files = @(Get-Prop $p 'files' @())
    if ($files.Count -gt 0) {
        return @($files | ForEach-Object {
                $f = Join-Path $dir $_
                if (-not (Test-Path -LiteralPath $f)) { throw "Patch not found: $f" }
                $f
            })
    }
    @(Get-ChildItem -LiteralPath $dir -Filter '*.patch' | Sort-Object Name | ForEach-Object { $_.FullName })
}

# Files a patch touches, relative to the repository root, with forward slashes.
function Get-GitPatchTargets([string]$Patch) {
    @([IO.File]::ReadAllLines($Patch) | ForEach-Object {
            if ($_ -match '^\+\+\+ b/(.+?)\s*$') { $Matches[1] }
        })
}

# applied | pending | conflict
function Get-GitPatchState([string]$Root, [string]$Patch) {
    if ((Invoke-Git $Root @('apply', '--check', '--reverse', '--', $Patch)).Code -eq 0) { return 'applied' }
    if ((Invoke-Git $Root @('apply', '--check', '--', $Patch)).Code -eq 0) { return 'pending' }
    'conflict'
}

function Test-GitCommit([string]$Dir, [string]$Sha) {
    (Invoke-Git $Dir @('cat-file', '-e', "$Sha^{commit}")).Code -eq 0
}

function Get-GitShort([string]$Sha) { if ($Sha.Length -gt 9) { $Sha.Substring(0, 9) } else { $Sha } }

# The commit a submodule should be at: its pin, or the commit the superproject records.
function Get-GitSubmoduleTarget([string]$Root, [string]$Commit, [string]$SubPath, $Pin) {
    $subs = Get-Prop $Pin 'submodules'
    $want = Get-Prop $subs $SubPath
    if ($want -and $want -ne 'recorded') { return $want }
    $r = Invoke-Git $Root @('ls-tree', $Commit, '--', $SubPath)
    if ($r.Code -ne 0 -or $r.Text -notmatch '^160000 commit ([0-9a-f]{40})') {
        throw "$SubPath is not a submodule at commit $(Get-GitShort $Commit)."
    }
    $Matches[1]
}

# Modified tracked files, relative to the repository root ("prefix/" for a submodule).
function Get-GitDirtyFiles([string]$Dir, [string]$Prefix) {
    $r = Invoke-Git $Dir @('status', '--porcelain', '--ignore-submodules=all', '--untracked-files=no')
    @($r.Lines | Where-Object { $_.Length -gt 3 } | ForEach-Object { $Prefix + $_.Substring(3).Trim('"') })
}

function Test-GitSubmoduleCloned([string]$Root, [string]$SubPath) {
    $d = Join-Path $Root $SubPath
    (Test-Path -LiteralPath (Join-Path $d '.git'))
}

@{
    Type = 'git'

    Resolve = {
        param($Dep)
        $ref = Get-Prop $Dep 'ref'
        if (-not $ref) { throw "Dependency '$($Dep.name)' has no ref." }
        if ($ref -match '^[0-9a-f]{40}$') { $commit = $ref }
        else {
            $r = Invoke-Git $null @('ls-remote', $Dep.url, $ref, "refs/tags/$ref^{}")
            if ($r.Code -ne 0) { throw "git ls-remote $($Dep.url) failed:`n$($r.Text)" }
            $lines = @($r.Lines | Where-Object { $_ -match '^[0-9a-f]{40}\s' })
            if ($lines.Count -eq 0) { throw "Ref '$ref' not found in $($Dep.url)." }
            # Prefer the peeled tag (^{}) when there is one.
            $peeled = @($lines | Where-Object { $_ -match '\^\{\}$' })
            if ($peeled.Count -gt 0) { $lines = $peeled }
            $commit = $lines[0].Substring(0, 40)
        }
        $subs = [ordered]@{}
        foreach ($s in @(Get-Prop $Dep 'submodules' @())) {
            $subs[$s.path] = Get-Prop $s 'ref' 'recorded'
        }
        [ordered]@{ commit = $commit; submodules = $subs }
    }

    Test = {
        param($Dep, $Pin)
        $res = New-TestResult
        $path = Get-GitDepPath $Dep $Pin
        $commit = Get-Prop $Pin 'commit'
        foreach ($k in (ConvertTo-Hashtable (Get-Prop $Dep 'exports')).GetEnumerator()) {
            $res.Exports[$k.Key] = Expand-DepValue $Dep $Pin $k.Value
        }

        if (-not (Test-Path -LiteralPath $path)) { Add-Finding $res missing "not found at $path"; return $res }
        if (-not (Test-Path -LiteralPath (Join-Path $path '.git'))) {
            if (@(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) { Add-Finding $res missing "$path is empty"; return $res }
            Add-Finding $res mismatch "$path exists but is not a git checkout; move it away or pick another -DepsRoot"
            return $res
        }

        if (-not (Test-Path -LiteralPath (Join-Path $path '.git\index'))) {
            Add-Finding $res mismatch "$path is cloned but nothing is checked out yet" -Safe
            return $res
        }

        # Commit
        $head = (Invoke-Git $path @('rev-parse', '--verify', '-q', 'HEAD')).Text
        $branch = (Invoke-Git $path @('symbolic-ref', '-q', '--short', 'HEAD')).Text
        $local = 0
        if ($head) { $local = [int](Invoke-Git $path @('rev-list', '--count', 'HEAD', '--not', '--remotes')).Text }
        $res.Info.Branch = $branch
        $res.Info.LocalCommits = $local
        if (-not $head) { Add-Finding $res mismatch 'nothing checked out yet' -Safe }
        elseif ($head -eq $commit) { Add-Finding $res ok "$path at the pinned $(Get-GitShort $commit)" }
        elseif (-not (Test-GitCommit $path $commit)) {
            Add-Finding $res mismatch "$path is at $(Get-GitShort $head); the pinned $(Get-GitShort $commit) is not in this clone yet"
        }
        elseif ((Invoke-Git $path @('merge-base', '--is-ancestor', $commit, 'HEAD')).Code -eq 0) {
            $n = (Invoke-Git $path @('rev-list', '--count', "$commit..HEAD")).Text
            $where = if ($branch) { "branch $branch" } else { 'a detached HEAD' }
            Add-Finding $res warn "$path is on $where, $n commit(s) after the pinned $(Get-GitShort $commit)"
        }
        else {
            Add-Finding $res mismatch "$path is at $(Get-GitShort $head), not the pinned $(Get-GitShort $commit)"
        }
        if (-not $head) { return $res }

        # Submodules
        $dirtyAllowed = @{}
        $dirty = New-Object System.Collections.ArrayList
        foreach ($f in (Get-GitDirtyFiles $path '')) { [void]$dirty.Add($f) }
        foreach ($s in @(Get-Prop $Dep 'submodules' @())) {
            $sp = $s.path
            $want = Get-GitSubmoduleTarget $path $commit $sp $Pin
            if (-not (Test-GitSubmoduleCloned $path $sp)) { Add-Finding $res mismatch "submodule $sp is not cloned" -Safe; continue }
            $sdir = Join-Path $path $sp
            $shead = (Invoke-Git $sdir @('rev-parse', 'HEAD')).Text
            if ($shead -eq $want) { Add-Finding $res ok "$sp at $(Get-GitShort $want)" }
            else { Add-Finding $res mismatch "$sp is at $(Get-GitShort $shead), not $(Get-GitShort $want)" }
            foreach ($f in (Get-GitDirtyFiles $sdir "$sp/")) { [void]$dirty.Add($f) }
        }

        # Patches
        foreach ($p in (Get-GitPatchFiles $Dep $Pin)) {
            foreach ($t in (Get-GitPatchTargets $p)) { $dirtyAllowed[$t] = $true }
            $name = Split-Path -Leaf $p
            switch (Get-GitPatchState $path $p) {
                'applied' { Add-Finding $res ok "patch $name applied" }
                'pending' { Add-Finding $res mismatch "patch $name not applied" -Safe }
                default { Add-Finding $res mismatch "patch $name does not apply: upstream changed the patched lines" }
            }
        }

        # Local changes the patches do not explain
        $extra = @($dirty | Where-Object { -not $dirtyAllowed.ContainsKey($_) })
        $res.Info.ExtraDirty = $extra
        if ($extra.Count -gt 0) { Add-Finding $res warn "local changes not from the patches: $($extra -join ', ')" }
        if ($local -gt 0) { Add-Finding $res warn "$local local commit(s) not on any remote" }
        $res
    }

    Install = {
        param($Dep, $Pin)
        $path = Get-GitDepPath $Dep $Pin
        if ((Test-Path -LiteralPath $path) -and @(Get-ChildItem -LiteralPath $path -Force).Count -gt 0) {
            throw "$path exists and is not empty."
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        $cloneArgs = @('clone', '--no-checkout')
        if (Get-Prop $Dep 'partialClone' $true) { $cloneArgs += '--filter=blob:none' }
        Write-Step 'CLONE' "$($Dep.url) -> $path" Cyan
        Invoke-GitLive $null ($cloneArgs + @($Dep.url, $path))
        & $script:Handlers['git'].Update $Dep $Pin
    }

    Update = {
        param($Dep, $Pin)
        $path = Get-GitDepPath $Dep $Pin
        $commit = Get-Prop $Pin 'commit'
        $state = & $script:Handlers['git'].Test $Dep $Pin
        $head = (Invoke-Git $path @('rev-parse', '--verify', '-q', 'HEAD')).Text
        $checkedOut = Test-Path -LiteralPath (Join-Path $path '.git\index')

        # Refuse to touch local work.
        $extraDirty = @(Get-Prop $state.Info 'ExtraDirty' @())
        if ($checkedOut -and $extraDirty.Count -gt 0) {
            throw "Not changing $path`: it has local changes ($($extraDirty -join ', ')). Commit or stash them first."
        }
        $moving = (-not $checkedOut) -or ($head -ne $commit)
        if ($moving -and $checkedOut -and -not $script:Ctx.Force) {
            $localCommits = [int](Get-Prop $state.Info 'LocalCommits' 0)
            $branch = Get-Prop $state.Info 'Branch' ''
            if ($localCommits -gt 0) { throw "Not moving $path`: it has $localCommits commit(s) not on any remote. Use -Force to move it anyway (the commits stay on their branch)." }
            if ($branch) { throw "Not moving $path`: branch $branch is checked out. Use -Force to detach it at the pinned commit (the branch is kept)." }
        }

        $patches = @(Get-GitPatchFiles $Dep $Pin)

        if (-not (Test-GitCommit $path $commit)) {
            Write-Step 'FETCH' $Dep.url Cyan
            Invoke-GitLive $path @('fetch', 'origin')
            if (-not (Test-GitCommit $path $commit)) { Invoke-GitLive $path @('fetch', 'origin', $commit) }
        }

        # Submodules that must move, so patches inside them come off first.
        $subMoves = @{}
        foreach ($s in @(Get-Prop $Dep 'submodules' @())) {
            $want = Get-GitSubmoduleTarget $path $commit $s.path $Pin
            if (Test-GitSubmoduleCloned $path $s.path) {
                $shead = (Invoke-Git (Join-Path $path $s.path) @('rev-parse', 'HEAD')).Text
                if ($shead -ne $want) { $subMoves[$s.path] = $want }
            }
        }

        if ($checkedOut -and ($moving -or $subMoves.Count -gt 0)) {
            [array]::Reverse($patches)
            foreach ($p in $patches) {
                if ((Get-GitPatchState $path $p) -eq 'applied') {
                    Write-Step 'UNPATCH' (Split-Path -Leaf $p)
                    Invoke-GitChecked $path @('apply', '--reverse', '--', $p) | Out-Null
                }
            }
            [array]::Reverse($patches)
        }

        if ($moving) {
            Write-Step 'CHECKOUT' "$(Get-GitShort $commit) in $path" Cyan
            Invoke-GitLive $path @('-c', 'advice.detachedHead=false', 'checkout', '--detach', $commit)
        }

        foreach ($s in @(Get-Prop $Dep 'submodules' @())) {
            $sp = $s.path
            $sdir = Join-Path $path $sp
            $want = Get-GitSubmoduleTarget $path $commit $sp $Pin
            if (-not (Test-GitSubmoduleCloned $path $sp)) {
                Write-Step 'SUBMOD' "$sp" Cyan
                Invoke-GitLive $path @('submodule', 'update', '--init', '--', $sp)
            }
            $shead = (Invoke-Git $sdir @('rev-parse', 'HEAD')).Text
            if ($shead -ne $want) {
                if (-not (Test-GitCommit $sdir $want)) { Invoke-GitLive $sdir @('fetch', 'origin') }
                Write-Step 'CHECKOUT' "$(Get-GitShort $want) in $sp" Cyan
                Invoke-GitLive $sdir @('-c', 'advice.detachedHead=false', 'checkout', '--detach', $want)
            }
        }

        foreach ($p in $patches) {
            $name = Split-Path -Leaf $p
            switch (Get-GitPatchState $path $p) {
                'applied' { }
                'pending' { Write-Step 'PATCH' $name Cyan; Invoke-GitChecked $path @('apply', '--', $p) | Out-Null }
                default { throw "Patch $name does not apply to $path. Upstream changed the patched lines; update the patch (see Patches\README.md)." }
            }
        }
    }
}
