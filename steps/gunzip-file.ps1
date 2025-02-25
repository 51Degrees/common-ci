using namespace System.IO

param(
    [Parameter(Mandatory, Position=0)]
    [string]$Source,
    [string]$Destination = ($Source -replace '\.gz$','')
)

Write-Host "Extracting '$Source' to '$Destination'..."
try {
    $src = [File]::OpenRead($Source)
    $dest = [File]::Create($Destination)
    $gunzip = [Compression.GZipStream]::new($src, [Compression.CompressionMode]::Decompress)
    $gunzip.copyTo($dest)
} finally {
    # Avoid calling Close on nulls
    if ($gunzip) { $gunzip.Close() }
    if ($dest) { $dest.Close() }
    if ($src) { $src.Close() }
}
