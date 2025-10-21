
Param(
  [string]$AddonName = $(Split-Path -Leaf $PWD.Path),
  [string]$OutFile = "$((Split-Path -Leaf $PWD.Path))-Release.zip"
)
$ErrorActionPreference = "Stop"
$OutFull = Join-Path $PWD.Path $OutFile

if (Test-Path $OutFull) { Remove-Item $OutFull -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($OutFull, 'Create')

# Common excludes (folders/files)
$commonExclude = '\.git(\\|$)|\.vscode(\\|$)|\.DS_Store$|thumbs\.db$'

Get-ChildItem -Recurse -File | ForEach-Object {
    # Skip output zip explicitly (robust in OneDrive/long paths)
    if ($_.FullName -eq $OutFull) { return }

    # Skip common excludes by regex
    if ($_.FullName -match $commonExclude) { return }

    $rel = $_.FullName.Substring($PWD.Path.Length + 1)
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel) | Out-Null
}

$zip.Dispose()
Write-Host "Created $OutFile"
