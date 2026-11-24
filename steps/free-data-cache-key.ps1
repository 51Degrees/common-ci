param (
    [Parameter(Mandatory)][string]$Repository
)
$ErrorActionPreference = 'Stop'

# Prints the key of the free data files downloaded into a fresh clone of the
# data repository. The entry is restored over the clone, so the key covers
# every file in it, the .link files among them, and changes when any of them
# does. It also changes with the day, because a link names a fixed address
# whose file is updated in place.
$files = Get-ChildItem -LiteralPath $Repository -Recurse -File -Force |
    ForEach-Object {
        $name = [IO.Path]::GetRelativePath($Repository, $_.FullName) -replace '\\', '/'
        if ($name -notlike '.git/*') { $name + "`n" + (Get-Content -Raw -LiteralPath $_.FullName) }
    } |
    Sort-Object -CaseSensitive
$sha1 = [Security.Cryptography.SHA1]::Create()
$hash = [Convert]::ToHexString($sha1.ComputeHash([Text.Encoding]::UTF8.GetBytes(($files -join "`n"))))
"free-data-$(Get-Date -Format FileDate)-$hash"
