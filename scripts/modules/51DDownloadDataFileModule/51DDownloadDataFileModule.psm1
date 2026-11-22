<#
  ==================== Download =====================
  .Description
  This module contains a function to download a data file
  from the 51Degrees Distributor.
#>

# Download a data file.
function Get-DataFile {

    param (
        [Parameter(Mandatory=$true)]
        [string]$licenseKey,

        [Parameter(Mandatory=$true)]
        [string]$dataType,

        [Parameter(Mandatory=$true)]
        [string]$product,

        [Parameter(Mandatory=$true)]
        [string]$fullFilePath
    )
    
    Add-Type -AssemblyName System.Net.Http

    $webClient = New-Object System.Net.Http.HttpClient;
    $webClient.Timeout = New-TimeSpan -Seconds 240
    $url ="https://distributor.51degrees.com/api/v2/download?LicenseKeys=$($licenseKey)&Type=$($dataType)&Download=True&Product=$($product)"
    $start_time = Get-Date
    $complete = $false
    $tryCount = 0

    DO
    {
        $tryCount++;
        Write-Host "Attempt: $tryCount"
        
        try
        {
            # Get download stream
            $stream = $webClient.GetStreamAsync($url)
            $stream.ConfigureAwait($false) > $null
            if ($null -ne $stream.Exception){ throw $stream.Exception }

            # Save stream to path
            try
            {
                $fileStream = [System.IO.File]::Create($fullFilePath)
                $stream.Result.CopyTo($fileStream)            
                $complete = $true
            }
            finally
            {
                if ($null -ne $fileStream){ $fileStream.Dispose() }
                if (($null -ne $stream) -and ($stream.IsCompleted -eq $true)){ $stream.Dispose() }
            }
        }
        catch
        {
            Write-Host "# ERROR downloading data file:"
            Write-Host $_
        }        
    } While (($complete -eq $false) -and ($tryCount -le 10))
    
    if($complete -eq $false)
    {        
		throw "# ERROR: Data file download failed after $tryCount attempts."
    }

    Write-Output "Time taken: $((Get-Date).Subtract($start_time).Seconds) second(s)"
}

Function Gunzip{
    Param(
        $Source,
        $Destination = ($Source -replace '\.gz$','')
        )

    $FileLength = $(Get-Item $Source).Length
    try {
        $In = New-Object System.IO.FileStream $Source, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
        $Out = New-Object System.IO.FileStream $Destination, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
        $GzipStream = New-Object System.IO.Compression.GzipStream $In, ([IO.Compression.CompressionMode]::Decompress)

        $Buffer = New-Object byte[](1024)
        $Progress = 0
        while ($True) {
            $Read = $Gzipstream.Read($Buffer, 0, 1024)
            if ($Read -le 0) { break }
            $Out.Write($Buffer, 0, $Read)
            if ($Progress -lt $($GzipStream.BaseStream.Position / $FileLength)) {
                $Progress = $GzipStream.BaseStream.Position / $FileLength
                Write-Progress -Activity "Extracting" -PercentComplete $($Progress * 100)
            }
        }
    }
    finally {
        $GzipStream.Close()
        $Out.Close()
        $In.Close()
    }
}

Export-ModuleMember -Function Get-DataFile
Export-ModuleMember -Function Gunzip