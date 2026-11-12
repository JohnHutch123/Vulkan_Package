# Dependency setup

`SetupDependencies.bat` (at the repository root) installs, checks or updates everything this
repository needs to build: Git, PasVulkan with the externals the packages compile, the Vulkan
loader (from the GPU driver), the LunarG Vulkan SDK, and (optionally) Delphi. The list is in
[`dependencies.json`](../../dependencies.json); the tool itself is `Tools\Deps\Deps.ps1`.

```bat
SetupDependencies.bat                 :: install whatever is missing
SetupDependencies.bat check           :: report only (exit code 1 if something required is wrong)
SetupDependencies.bat update          :: move dependencies to the pinned versions
```

Options:

| Option | Meaning |
|---|---|
| `-DepsRoot <dir>` | Where dependencies are installed. Default: `DEPS_ROOT`, else the manifest's `depsRoot` (`..`, next to this repo, so PasVulkan is `D:\Vulkan`). |
| `-Feature a,b` | Also install the dependencies of these features (`all` for every one). `core` is always included. |
| `-Only a,b` | Only these dependencies, by name. |
| `-AcceptLicenses` | Accept vendor licences (the Vulkan SDK's) without asking. Without it the tool asks, or stops when it can't ask. |
| `-Yes` | Answer yes to other confirmations (installing Git with winget). |
| `-Force` | `update` may move a checkout that is on a branch or has commits that aren't on any remote. |
| `-Manifest <file>` | Run another manifest, e.g. the PRO repository's. |

Downloads are cached in `%LOCALAPPDATA%\VulkanPackage\deps-cache` (or `DEPS_CACHE`).

## What it never does

- **Change a working dependency during `install`.** `install` only adds what is missing, plus
  steps that are purely additive, such as applying a patch that isn't applied yet.
- **Discard local work.** `update` refuses to touch a checkout with uncommitted changes other
  than the pinned patches. It also refuses to move one with commits not on any remote, or one
  that has a branch checked out, unless you pass `-Force`. Branches and commits are never deleted.
- **Accept a licence for you**, or run an installer that isn't validly signed by the expected
  signer and doesn't match its pinned SHA-256.

So a development checkout such as `D:\Vulkan` on a fix branch shows up as a `WARN` ("N commits
after the pinned ...") and is left alone.

## Files it writes

| File | Commit it? | Content |
|---|---|---|
| `Dependencies.local.props` (next to each manifest) | no (ignored) | MSBuild properties with this machine's locations, e.g. `PASVULKAN_DIR`. |
| `dependencies.lock.json` (next to each manifest) | yes | The exact versions resolved: commit SHAs, SDK version and installer SHA-256. |

`Dependencies.props` (committed) imports `Dependencies.local.props` when it exists and otherwise
uses an environment variable of the same name, or the default `..\Vulkan`. Every `.dproj` imports
`Dependencies.props` and uses `$(PASVULKAN_DIR)` in its search paths, so the projects build
wherever the tool put PasVulkan. `Tests\RunTests.bat` reads the same file.

## The manifest

```json
{
  "schema": 1,
  "depsRoot": "..",
  "includes": [ "..\\Vulkan_Package\\dependencies.json" ],
  "dependencies": [ { "name": "...", "type": "...", ... } ]
}
```

- **`includes`**: other manifests, run first. A repository that builds on this one lists only its
  own dependencies and includes this manifest, so one run sets up everything. A name declared in
  two manifests must be declared identically.
- **`depsRoot`**: relative to the manifest. Only the manifest you run decides it, so included
  dependencies install under the same root.

Common fields of a dependency:

| Field | Meaning |
|---|---|
| `name`, `type`, `description` | `type` selects the handler (below). |
| `feature` | Default `core`. Others (e.g. `physics`) are installed only with `-Feature`. |
| `optional` | `true`: a failure is reported but doesn't fail the run. |
| `exports` | MSBuild properties for `Dependencies.local.props`, e.g. `{ "PASVULKAN_DIR": "{path}" }`. |

Strings can use `{DepsRoot}`, `{ManifestDir}`, `{name}`, `{version}`, `{path}`, `{installDir}`
and `{env:NAME}`.

### Types

- **`git`**: a clone pinned to `ref` (a commit SHA; a branch or tag is resolved and recorded in
  the lock), at `path`. Only the listed `submodules` are cloned, each at its own `ref` (or the
  commit the superproject records). `patches` are applied on top. See
  [`Handlers/git.ps1`](Handlers/git.ps1).
- **`installer`**: a vendor installer at `url`. The tool checks `sha256` (or `shaUrl`) and the
  Authenticode `signer`, then runs it with `args`, elevated if `elevate` is set. `detect` says how
  to find an installed copy; one at least `minVersion` counts as present. `version` may be `latest`.
  See [`Handlers/installer.ps1`](Handlers/installer.ps1).
- **`detect`**: something the tool only looks for: a `command` (with `minVersion`), a `file`, or
  `registry` keys. When it is missing, it prints `hint` and offers `winget` if an id is given.
  See [`Handlers/detect.ps1`](Handlers/detect.ps1).

### Adding a dependency

1. **Add an entry to the manifest of the repository that needs it.** A PRO-only library goes in
   the PRO repository's manifest, not this one.
2. **Pin it exactly** (commit SHA, version plus SHA-256), so a build can't change underneath you.
3. **If the projects need its location, add an `exports` entry.** Then add a default for the
   property in `Dependencies.props`, and use `$(NAME)` in the `.dproj` search paths.
4. **Run `SetupDependencies.bat`, then `SetupDependencies.bat check`, and commit the manifest and
   the updated `dependencies.lock.json`.**

### Adding a type

A handler is a file `Handlers\<type>.ps1` that returns a hashtable:

```powershell
@{
    Type    = 'mytype'
    Resolve = { param($Dep) ... }          # -> pin (exact version), stored in the lock file
    Test    = { param($Dep, $Pin) ... }    # -> New-TestResult with findings; never changes anything
    Install = { param($Dep, $Pin) ... }    # it is missing; may return an updated pin
    Update  = { param($Dep, $Pin) ... }    # it is there but wrong; must not discard local work
}
```

`Deps.ps1` loads every file in `Handlers`. The handlers can use its helpers: `Get-Prop`,
`Expand-DepValue`, `Add-Finding`, `Invoke-Git`, `Get-CachedDownload`, `Confirm-Action` and
`Write-Step`.

## PasVulkan pin

`pasvulkan` is pinned to upstream `5686db2d9`, the commit the packages were last built and
tested against. Patches 0004–0008 from [`Patches`](../../Patches/README.md) go on top. 0008 is
upstream PR #62, which isn't merged yet: it loads the Vulkan library only once.

0002 and 0003 aren't listed. Upstream fixed 0002's `_LzmaDecode` name in its own way, so the
patch no longer applies. 0003 is a Delphi 11 fix for `PasVulkan.Application`, which the packages
don't use, and Delphi 11 is no longer supported.
