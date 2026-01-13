param (
    [Parameter(Mandatory)][string]$PackageName
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Write-Output "Building extension for $PackageName"

# Installing binary builder
npm i -g node-gyp@11.0.0

# Determine the operating system
if ($IsMacOS) {
    $os = "darwin"
} elseif ($IsLinux) {
    $os = "linux"
    sudo apt-get install g++ make libatomic1
} elseif ($IsWindows) {
    $os = "win32"
} else {
    $os = "unknown"
}
$arch = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLower()

# Creating folder for future build
New-Item -ItemType Directory -Path build | Out-Null

# Renaming buiding config file
Copy-Item binding.51d binding.gyp

# Run configuration
node-gyp configure

# Build configuration
node-gyp build

# Getting major node version
$nodeVersion = node --version
$nodeMajorVersion = $nodeVersion.TrimStart('v').Split('.')[0]

# Creating folder for binaries artifacts
New-Item -ItemType Directory -Path "../../package-files" | Out-Null

# Storing binary artifact (needs to be in both of these places for different tests)
Move-Item './build/Release/FiftyOneDeviceDetectionHashV4.node' './build/'
Copy-Item './build/FiftyOneDeviceDetectionHashV4.node'  "../../package-files/FiftyOneDeviceDetectionHashV4-$os-$arch-$nodeMajorVersion.node"

# Installing package for some examples
npm install n-readlines
