param()
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$godotDir = Join-Path $projectRoot 'tools\godot'
$godotExe = Join-Path $godotDir 'Godot_v4.2.2-stable_win64_console.exe'
$templateExe = Join-Path $projectRoot 'tools\windows-runtime-template.exe'
$templateSha256 = 'EF43C89CE8E42975DE35709170D462E928A09C927CF2102E49F5922844F06D79'
$downloadDir = Join-Path ([IO.Path]::GetTempPath()) ('griddytranslate-build-' + [guid]::NewGuid().ToString('N'))

try {
    if (!(Test-Path -LiteralPath $godotExe)) {
        New-Item -ItemType Directory -Path $downloadDir,$godotDir -Force | Out-Null
        $godotZip = Join-Path $downloadDir 'godot.zip'
        Invoke-WebRequest -Uri 'https://github.com/godotengine/godot-builds/releases/download/4.2.2-stable/Godot_v4.2.2-stable_win64.exe.zip' -OutFile $godotZip
        Expand-Archive -LiteralPath $godotZip -DestinationPath $godotDir -Force
        if (!(Test-Path -LiteralPath $godotExe)) { throw 'Godot download did not contain the expected 4.2.2 console editor.' }
    }
    if (!(Test-Path -LiteralPath $templateExe)) {
        New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
        $portableZip = Join-Path $downloadDir 'portable.zip'
        Invoke-WebRequest -Uri 'https://github.com/Misaka08056/GriddyTranslate/releases/download/v0.1.0/GriddyTranslate-Windows.zip' -OutFile $portableZip
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($portableZip)
        try {
            $entry = $archive.GetEntry('GriddyTranslate/GriddyTranslate.runtime.exe')
            if (!$entry) { throw 'Portable package has no matching runtime template.' }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $templateExe, $false)
        } finally { $archive.Dispose() }
    }
    if ((Get-FileHash -LiteralPath $templateExe -Algorithm SHA256).Hash -ne $templateSha256) { throw 'Runtime template SHA-256 does not match the tested first release.' }
    Write-Output 'Build dependencies are ready. Ensure MinGW-w64 gcc.exe is in PATH, then run ./build.ps1.'
} finally {
    # This helper only removes the unique temporary folder it created.
    $resolvedDownload = [IO.Path]::GetFullPath($downloadDir)
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (!$resolvedDownload.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolvedDownload) -notmatch '^griddytranslate-build-[0-9a-f]{32}$') { throw 'Unexpected temporary directory; cleanup refused.' }
    if (Test-Path -LiteralPath $resolvedDownload) { Remove-Item -LiteralPath $resolvedDownload -Recurse -Force }
}
