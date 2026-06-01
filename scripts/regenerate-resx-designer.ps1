<#
.SYNOPSIS
    Regenerate a strongly-typed *.Designer.cs from its *.resx on the command line.

.DESCRIPTION
    Most 51Degrees projects wire their resource files with the Visual Studio
    design-time custom tool (<Generator>ResXFileCodeGenerator</Generator>).
    That generator only runs inside Visual Studio, so a plain `dotnet build`
    never refreshes the checked-in *.Designer.cs after you edit the *.resx.
    On macOS/Linux (or any VS-less box) that leaves you hand-editing generated
    code, which the team forbids.

    This script regenerates the Designer using MSBuild's own GenerateResource
    task (the same StronglyTypedResourceBuilder VS uses under the hood) inside a
    throwaway project, then copies the result next to the resx. You only ever
    edit the source .resx; the tool emits the generated file.

    It preserves the things that matter for a clean diff and a working build:
      - the class name (defaults to the resx file name, e.g. Messages.resx -> Messages),
      - the namespace (detected from the existing Designer, or pass -Namespace),
      - the access modifier (public vs internal, detected from the existing
        Designer, or pass -Access). MSBuild emits `internal`; we promote to
        `public` by flipping only the class/member modifiers, leaving the
        always-internal constructor as-is so the output matches VS exactly.

    The only unavoidable difference from VS output is cosmetic: the header
    comment and the [GeneratedCodeAttribute] tool-name string. Both compile
    identically.

.PARAMETER ResxPath
    Path to the .resx file to regenerate the Designer for.

.PARAMETER Namespace
    Namespace for the generated class. Auto-detected from the existing
    *.Designer.cs when omitted. Required only for a brand-new resx that has no
    Designer yet.

.PARAMETER ClassName
    Class name for the generated accessors. Defaults to the resx file name
    without extension.

.PARAMETER Access
    'Auto' (default) detects public/internal from the existing Designer (or the
    csproj generator) and falls back to internal. Force with 'Public'/'Internal'.

.EXAMPLE
    ./regenerate-resx-designer.ps1 host/FiftyOne.Pipeline.CloudService/Messages.resx

.EXAMPLE
    ./regenerate-resx-designer.ps1 ./Foo.resx -Namespace My.Lib -Access Public
#>
param (
    [Parameter(Mandatory)][string]$ResxPath,
    [string]$Namespace,
    [string]$ClassName,
    [ValidateSet('Auto', 'Public', 'Internal')][string]$Access = 'Auto'
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$resx = (Resolve-Path -LiteralPath $ResxPath).Path
if (-not $ClassName) { $ClassName = [IO.Path]::GetFileNameWithoutExtension($resx) }
$resxDir = Split-Path -Parent $resx
$designerPath = Join-Path $resxDir "$ClassName.Designer.cs"
$existingDesigner = Test-Path -LiteralPath $designerPath

# Detect namespace + access modifier from the committed Designer so the
# regenerated file drops in cleanly. These are the only two things the VS
# generator knows that the bare .resx doesn't.
if ($existingDesigner) {
    $designerText = Get-Content -LiteralPath $designerPath -Raw
    if (-not $Namespace) {
        $m = [regex]::Match($designerText, '(?m)^\s*namespace\s+([\w.]+)')
        if ($m.Success) { $Namespace = $m.Groups[1].Value }
    }
    if ($Access -eq 'Auto') {
        if ($designerText -match "(?m)^\s*public\s+class\s+$([regex]::Escape($ClassName))\b") {
            $Access = 'Public'
        } elseif ($designerText -match "(?m)^\s*internal\s+class\s+$([regex]::Escape($ClassName))\b") {
            $Access = 'Internal'
        }
    }
}

# No Designer yet: fall back to the csproj generator (PublicResXFileCodeGenerator
# => public) for the access modifier. Namespace can't be guessed reliably here.
if ($Access -eq 'Auto') {
    $csproj = Get-ChildItem -LiteralPath $resxDir -Filter *.csproj -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($csproj -and (Select-String -LiteralPath $csproj.FullName -Pattern 'PublicResXFileCodeGenerator' -Quiet)) {
        $Access = 'Public'
    } else {
        $Access = 'Internal'
    }
}
if (-not $Namespace) {
    throw "Could not detect the namespace (no existing $ClassName.Designer.cs). Re-run with -Namespace <ns>."
}

Write-Host "Regenerating $ClassName.Designer.cs" -ForegroundColor Cyan
Write-Host "  resx:      $resx"
Write-Host "  namespace: $Namespace"
Write-Host "  access:    $Access"

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("resxgen-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Copy-Item -LiteralPath $resx -Destination (Join-Path $tmp "$ClassName.resx")

    # Target the SDK that `dotnet` resolves here. The throwaway project lives in
    # the OS temp dir (not the repo) so it inherits no Directory.Build.props,
    # global.json, or private package feeds - the build is offline and fast.
    $sdkVersion = (& dotnet --version).Trim()
    $tfm = "net$([int]($sdkVersion.Split('.')[0])).0"

    $csprojBody = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>$tfm</TargetFramework>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
  </PropertyGroup>
  <ItemGroup>
    <EmbeddedResource Update="$ClassName.resx">
      <Generator></Generator>
      <StronglyTypedLanguage>CSharp</StronglyTypedLanguage>
      <StronglyTypedNamespace>$Namespace</StronglyTypedNamespace>
      <StronglyTypedClassName>$ClassName</StronglyTypedClassName>
      <StronglyTypedFileName>`$(IntermediateOutputPath)$ClassName.Designer.cs</StronglyTypedFileName>
    </EmbeddedResource>
  </ItemGroup>
</Project>
"@
    Set-Content -LiteralPath (Join-Path $tmp "gen.csproj") -Value $csprojBody -Encoding utf8

    Push-Location $tmp
    try {
        $buildLog = & dotnet build gen.csproj -v:q --nologo 2>&1
        if ($LASTEXITCODE -ne 0) {
            $buildLog | Write-Host
            throw "Generation build failed (exit $LASTEXITCODE)."
        }
    } finally {
        Pop-Location
    }

    $generated = Get-ChildItem -Path (Join-Path $tmp "obj") -Recurse -Filter "$ClassName.Designer.cs" |
        Select-Object -First 1
    if (-not $generated) { throw "Generated $ClassName.Designer.cs not found under obj/." }

    $content = Get-Content -LiteralPath $generated.FullName -Raw

    # MSBuild emits an internal class. Promote to public when required by
    # flipping only `<modifier> class` and `<modifier> static` - never the
    # `internal <Class>()` constructor, which stays internal even in VS's
    # public output.
    if ($Access -eq 'Public') {
        $content = $content -replace '(?m)^(\s*)internal(\s+class\s)', '$1public$2'
        $content = $content -replace '(?m)^(\s*)internal(\s+static\s)', '$1public$2'
    }

    # Match the existing file's encoding/newlines to keep the diff to real
    # content changes only. VS writes UTF-8 BOM + CRLF, so default to that.
    $useBom = $true
    $newline = "`r`n"
    if ($existingDesigner) {
        $bytes = [IO.File]::ReadAllBytes($designerPath)
        $useBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $sample = Get-Content -LiteralPath $designerPath -Raw
        if ($sample -notmatch "`r`n") { $newline = "`n" }
    }
    $content = $content -replace "`r`n", "`n" -replace "`n", $newline
    $encoding = New-Object System.Text.UTF8Encoding($useBom)
    [IO.File]::WriteAllText($designerPath, $content, $encoding)

    Write-Host "Wrote $designerPath" -ForegroundColor Green
    Write-Host "Note: header comment + [GeneratedCodeAttribute] tool name differ from VS output (cosmetic, compiles identically)." -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
