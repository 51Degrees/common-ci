param(
    [string[]]$Packages = @("gcc-multilib", "g++-multilib")
)

<#
.SYNOPSIS
Installs the 32 bit build libraries on Linux, where they exist.

.DESCRIPTION
gcc-multilib and g++-multilib supply the 32 bit libraries an x86 build links
against. Neither exists for arm64 under any name, so on an ARM runner apt
answers "has no installation candidate", and this script returns without
installing anything.

When apt fails on the runner's own mirror, azure.archive.ubuntu.com, the
script points apt at the main Ubuntu archive, which holds the same packages,
and tries once more before failing.

.PARAMETER Packages
The packages to install. Defaults to both, which is what a project building
32 bit C and C++ needs.
#>

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$RunnerMirror = "azure.archive.ubuntu.com"
$MainArchive = "archive.ubuntu.com"
# The files that name the runner's mirror on the Ubuntu images GitHub runs.
$AptSourceFiles = @(
    "/etc/apt/apt-mirrors.txt",
    "/etc/apt/sources.list.d/ubuntu.sources",
    "/etc/apt/sources.list"
)

if (-not $IsLinux) {
    Write-Output "Not Linux, so there is no multilib to install."
    return
}

# Read from the runner rather than from any build parameter, because it is
# apt that has to find the packages and apt answers for the machine it is on.
$architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
if ($architecture -ne [Runtime.InteropServices.Architecture]::X64) {
    Write-Output "Skipping multilib on $architecture, where these packages do not exist."
    return
}

Write-Output "Installing $($Packages -join ' ')"
try {
    sudo apt-get update
    sudo apt-get install -y @Packages
} catch {
    Write-Output "apt failed on $RunnerMirror, so trying $MainArchive"
    foreach ($file in $AptSourceFiles) {
        if (Test-Path $file) {
            sudo sed -i "s#$RunnerMirror#$MainArchive#g" $file
        }
    }
    sudo apt-get update
    sudo apt-get install -y @Packages
}
