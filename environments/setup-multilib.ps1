param(
    [string[]]$Packages = @("gcc-multilib", "g++-multilib")
)

<#
.SYNOPSIS
Installs the 32 bit build libraries on Linux, where they exist.

.DESCRIPTION
gcc-multilib and g++-multilib supply the 32 bit libraries an x86 build links
against. Neither exists for arm64 under any name, so on an ARM runner apt
answers "has no installation candidate" and "Unable to locate package". That
was harmless while a failing script was ignored, and it now stops the step
and everything downstream of it, including the package build.

Repositories called apt directly and each carried the same fault, so the
architecture test lives here rather than in five copies. The packages are a
parameter because they are not the same everywhere, and this script is not
the place to change what a repository installs.

.PARAMETER Packages
The packages to install. Defaults to both, which is what a project building
32 bit C and C++ needs.
#>

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

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
sudo apt-get update
sudo apt-get install -y @Packages
