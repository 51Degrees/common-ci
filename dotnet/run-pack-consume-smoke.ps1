
<#
.SYNOPSIS
    Pack-and-consume smoke test for NuGet packages that ship native DLLs via
    runtimes/{rid}/native/ and a .targets file.

.DESCRIPTION
    Creates a minimal consumer project from a template, points it at a local
    NuGet feed containing the package under test, restores + builds (or
    publishes) the consumer, and asserts that:

      1. A native DLL lands at the expected path.
      2. The DLL's magic bytes match the expected runtime identifier (no
         Windows DLL masquerading as a Linux ELF, etc.).

    Covers two historical incidents:
      - PR #722: dotnet publish -r linux-x64 copied a Windows PE DLL.
      - Issue #736 / PR #738: SDK-style projects multi-targeting
        net48;net10.0 stopped receiving the native DLL for the net48 leg.

.PARAMETER NupkgDir
    Directory containing the packed .nupkg(s). All .nupkg files in this
    directory are pushed to a fresh local feed.

.PARAMETER PackageId
    NuGet package id (e.g. FiftyOne.DeviceDetection.Hash.Engine.OnPremise).

.PARAMETER PackageVersion
    Version of the package to reference from the consumer.

.PARAMETER Cell
    One of the 7 cell ids defined below. Drives template + build command +
    assertion shape.

.PARAMETER WorkDir
    Scratch directory for the generated consumer project and its build
    output. Wiped clean on entry.
#>
param(
    [Parameter(Mandatory)][string]$NupkgDir,
    [Parameter(Mandatory)][string]$PackageId,
    [Parameter(Mandatory)][string]$PackageVersion,
    [Parameter(Mandatory)][ValidateSet(
        "sdk-modern-win-x64",
        "sdk-modern-linux-x64",
        "sdk-modern-osx-arm64",
        "sdk-net48",
        "sdk-multi-net48-net10",
        "legacy-x64",
        "legacy-anycpu"
    )][string]$Cell,
    [Parameter(Mandatory)][string]$WorkDir,
    [string]$ModernTfm = "net10.0",
    [string]$NativeAssetName
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 1.0

if (-not $NativeAssetName) {
    $NativeAssetName = "$PackageId.Native.dll"
}

$ScriptRoot = $PSScriptRoot
$TemplateRoot = Join-Path $ScriptRoot "smoke-templates"

$CellConfig = @{
    "sdk-modern-win-x64"    = @{ Template = "sdk-modern";       Style = "sdk-publish"; Tfm = $ModernTfm; Rid = "win-x64";    Expected = "PE32plus-x64"   }
    "sdk-modern-linux-x64"  = @{ Template = "sdk-modern";       Style = "sdk-publish"; Tfm = $ModernTfm; Rid = "linux-x64";  Expected = "ELF64"          }
    "sdk-modern-osx-arm64"  = @{ Template = "sdk-modern";       Style = "sdk-publish"; Tfm = $ModernTfm; Rid = "osx-arm64";  Expected = "MachO64"        }
    "sdk-net48"             = @{ Template = "sdk-modern";       Style = "sdk-build";   Tfm = "net48";    Rid = $null;        Expected = "PE32plus-x64"   }
    "sdk-multi-net48-net10" = @{ Template = "sdk-multi";        Style = "sdk-build";   Tfm = $null;      Rid = $null;        Expected = "PE32plus-x64"   }
    "legacy-x64"            = @{ Template = "legacy-framework"; Style = "legacy";      Tfm = "net48";    Rid = $null;        Expected = "PE32plus-x64"; Platform = "x64"    }
    "legacy-anycpu"         = @{ Template = "legacy-framework"; Style = "legacy";      Tfm = "net48";    Rid = $null;        Expected = "PE32plus-x64"; Platform = "AnyCPU" }
}[$Cell]

if (-not $CellConfig) { throw "Unknown cell: $Cell" }

function Write-Header($msg) { Write-Host "`n::group::$msg" }
function Write-Footer()      { Write-Host "::endgroup::" }
function Write-Fail($msg)    { Write-Host "::error::$msg"; throw $msg }

# --- 1. Prepare workdir + local feed ------------------------------------

Write-Header "Prepare workspace"
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $WorkDir

$LocalFeed = Join-Path $WorkDir "local-feed"
$null = New-Item -ItemType Directory -Force -Path $LocalFeed

Write-Host "Pushing .nupkg files from '$NupkgDir' to local feed '$LocalFeed'"
$nupkgs = Get-ChildItem -Path $NupkgDir -Filter '*.nupkg' -File
if (-not $nupkgs) { throw "No .nupkg files found in '$NupkgDir'" }
foreach ($pkg in $nupkgs) {
    Write-Host "  push $($pkg.Name)"
    dotnet nuget push -s $LocalFeed $pkg.FullName | Out-Null
}
Write-Footer

# --- 2. Render consumer from template -----------------------------------

Write-Header "Render consumer project ($Cell)"
$Project = Join-Path $WorkDir "consumer"
$null = New-Item -ItemType Directory -Force -Path $Project

$Template = Join-Path $TemplateRoot $CellConfig.Template
Copy-Item -Path (Join-Path $Template '*') -Destination $Project -Recurse -Force

function Expand-Template {
    param([string]$Path, [hashtable]$Vars)
    $content = Get-Content -Raw -Path $Path
    foreach ($key in $Vars.Keys) {
        $content = $content.Replace("{{$key}}", $Vars[$key])
    }
    return $content
}

$vars = @{
    PACKAGE_ID      = $PackageId
    PACKAGE_VERSION = $PackageVersion
    LOCAL_FEED      = $LocalFeed
    MODERN_TFM      = $ModernTfm
    TFM             = ($CellConfig.Tfm ?? '')
}

# Render .template files into their target names inside the consumer dir.
Get-ChildItem -Path $Project -Filter '*.template' -File -Recurse | ForEach-Object {
    $out = $_.FullName -replace '\.template$', ''
    Expand-Template -Path $_.FullName -Vars $vars | Set-Content -Path $out -NoNewline
    Remove-Item $_.FullName
}

# Shared NuGet.config (used by SDK-style cells; legacy cells have their own in packages/)
Expand-Template -Path (Join-Path $TemplateRoot 'NuGet.config.template') -Vars $vars |
    Set-Content -Path (Join-Path $Project 'NuGet.config') -NoNewline

Write-Host "Consumer project rendered at '$Project'"
Get-ChildItem -Path $Project -File | ForEach-Object { Write-Host "  $($_.Name)" }
Write-Footer

# --- 3. Build or publish the consumer -----------------------------------

Write-Header "Build consumer ($($CellConfig.Style))"
Push-Location $Project
try {
    switch ($CellConfig.Style) {
        'sdk-build' {
            dotnet restore --verbosity minimal
            dotnet build --configuration Release --no-restore --verbosity minimal
        }
        'sdk-publish' {
            dotnet restore --runtime $CellConfig.Rid --verbosity minimal
            dotnet publish --configuration Release --runtime $CellConfig.Rid --self-contained false --no-restore --verbosity minimal
        }
        'legacy' {
            # nuget.exe handles packages.config restore into the local ./packages folder,
            # which is where the legacy csproj's <Import> for the .targets file looks.
            $nugetExe = Get-Command nuget.exe -ErrorAction SilentlyContinue
            if (-not $nugetExe) { Write-Fail "nuget.exe is required on PATH for legacy cells" }
            nuget.exe restore -PackagesDirectory packages -ConfigFile NuGet.config packages.config
            $msbuild = Get-Command msbuild.exe -ErrorAction SilentlyContinue
            if (-not $msbuild) { Write-Fail "msbuild.exe is required on PATH for legacy cells" }
            msbuild.exe /t:Build /p:Configuration=Release /p:Platform=$($CellConfig.Platform) /restore:false
        }
    }
} finally {
    Pop-Location
}
Write-Footer

# --- 4. Placement + format assertions -----------------------------------

# A single "expectation" is: one path (relative to the consumer project) that
# MUST exist, and the magic-byte shape that file MUST have. Multi-target cells
# have more than one expectation.

function Get-Expectations {
    param([string]$Cell, [hashtable]$Config, [string]$ModernTfm, [string]$NativeAssetName)

    # `dotnet publish -r <rid>` flattens the selected runtimes/{rid}/native/
    # assets into the publish root — it does not keep the runtimes/ subtree.
    switch ($Cell) {
        'sdk-modern-win-x64'   { @(@{ Path = "bin/Release/$ModernTfm/win-x64/publish/$NativeAssetName";   Expect = 'PE32plus-x64' }) }
        'sdk-modern-linux-x64' { @(@{ Path = "bin/Release/$ModernTfm/linux-x64/publish/$NativeAssetName"; Expect = 'ELF64' }) }
        'sdk-modern-osx-arm64' { @(@{ Path = "bin/Release/$ModernTfm/osx-arm64/publish/$NativeAssetName"; Expect = 'MachO64' }) }
        'sdk-net48'            { @(@{ Path = "bin/Release/net48/$NativeAssetName"; Expect = 'PE32plus-x64' }) }
        'sdk-multi-net48-net10' {
            # net48 leg must get the DLL via the .targets file manual copy.
            # The modern leg need not copy into bin/; NuGet will resolve it at publish time.
            # Assert placement only for the net48 leg (this is the #736/#738 regression path).
            @(@{ Path = "bin/Release/net48/$NativeAssetName"; Expect = 'PE32plus-x64' })
        }
        'legacy-x64'    { @(@{ Path = "bin/x64/Release/$NativeAssetName"; Expect = 'PE32plus-x64' }) }
        'legacy-anycpu' { @(@{ Path = "bin/Release/$NativeAssetName";     Expect = 'PE32plus-x64' }) }
    }
}

function Get-BinaryMagic {
    param([string]$Path)
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $head = New-Object byte[] 4
        $n = $fs.Read($head, 0, 4)
        if ($n -lt 4) { return 'SHORT' }
        # ELF: 7F 45 4C 46
        if ($head[0] -eq 0x7F -and $head[1] -eq 0x45 -and $head[2] -eq 0x4C -and $head[3] -eq 0x46) {
            $bits = New-Object byte[] 1
            $null = $fs.Seek(4, 'Begin')
            $null = $fs.Read($bits, 0, 1)
            return ($bits[0] -eq 2 ? 'ELF64' : 'ELF32')
        }
        # Mach-O 64-bit LE: CF FA ED FE
        if ($head[0] -eq 0xCF -and $head[1] -eq 0xFA -and $head[2] -eq 0xED -and $head[3] -eq 0xFE) {
            return 'MachO64'
        }
        if ($head[0] -eq 0xCE -and $head[1] -eq 0xFA -and $head[2] -eq 0xED -and $head[3] -eq 0xFE) {
            return 'MachO32'
        }
        # PE (Windows): MZ header, then DOS stub, then e_lfanew @ 0x3C -> PE\0\0 + COFF
        if ($head[0] -eq 0x4D -and $head[1] -eq 0x5A) {
            $null = $fs.Seek(0x3C, 'Begin')
            $lfanewBytes = New-Object byte[] 4
            $null = $fs.Read($lfanewBytes, 0, 4)
            $lfanew = [BitConverter]::ToInt32($lfanewBytes, 0)
            $null = $fs.Seek($lfanew, 'Begin')
            # "PE\0\0" signature
            $sig = New-Object byte[] 4
            $null = $fs.Read($sig, 0, 4)
            if (-not ($sig[0] -eq 0x50 -and $sig[1] -eq 0x45 -and $sig[2] -eq 0 -and $sig[3] -eq 0)) {
                return 'PE-invalid'
            }
            # COFF Machine field is the next 2 bytes
            $machineBytes = New-Object byte[] 2
            $null = $fs.Read($machineBytes, 0, 2)
            $machine = [BitConverter]::ToUInt16($machineBytes, 0)
            switch ($machine) {
                0x8664  { return 'PE32plus-x64' }
                0x014C  { return 'PE32-x86' }
                0xAA64  { return 'PE32plus-arm64' }
                default { return ('PE-machine-' + ('0x{0:X4}' -f $machine)) }
            }
        }
        return 'UNKNOWN-' + (($head | ForEach-Object { '{0:X2}' -f $_ }) -join '')
    } finally {
        $fs.Dispose()
    }
}

Write-Header "Assertions ($Cell)"
$expectations = Get-Expectations -Cell $Cell -Config $CellConfig -ModernTfm $ModernTfm -NativeAssetName $NativeAssetName
$failures = @()

foreach ($exp in $expectations) {
    $full = Join-Path $Project $exp.Path
    Write-Host "  check: $($exp.Path)  (expect $($exp.Expect))"
    if (-not (Test-Path $full)) {
        $failures += "MISSING: $($exp.Path)"
        continue
    }
    $actual = Get-BinaryMagic -Path $full
    if ($actual -ne $exp.Expect) {
        $failures += "FORMAT : $($exp.Path)  expected=$($exp.Expect) actual=$actual"
    }
}

if ($failures) {
    foreach ($f in $failures) { Write-Host "::error::$f" }
    Write-Footer
    throw "Smoke cell '$Cell' failed: $($failures.Count) assertion(s) failed"
}

Write-Host "OK: all assertions passed for cell '$Cell'"
Write-Footer
exit 0
