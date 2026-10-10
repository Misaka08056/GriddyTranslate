param([switch]$SkipTests, [switch]$StartupOnly, [string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$sourceDir = Join-Path $projectRoot 'src'
$godotExe = Join-Path $projectRoot 'tools\godot\Godot_v4.2.2-stable_win64_console.exe'
$templateExe = Join-Path $projectRoot 'tools\windows-runtime-template.exe'
$appDir = if ($OutputDirectory) { [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory)) } else { Join-Path $projectRoot 'dist\GriddyTranslate' }
# Never replace a live user's PCK/runtime: their current text is memory-only.
$activeRuntime = Get-CimInstance Win32_Process -Filter "Name = 'GriddyTranslate.runtime.exe'" | Where-Object {
    $_.ExecutablePath -and [IO.Path]::GetDirectoryName($_.ExecutablePath) -eq $appDir
}
if ($activeRuntime) { throw "Application is running from $appDir. Use -OutputDirectory 'dist\GriddyTranslate-update' to build separately without closing it." }
$qaDir = Join-Path $projectRoot 'qa'
$packageDir = Join-Path $projectRoot 'packages'
foreach ($folder in @($appDir,$qaDir,$packageDir)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
$env:DISABLE_RTSS_LAYER = '1'
$env:VK_LOADER_LAYERS_DISABLE = 'VK_LAYER_RTSS'

# Resolve the template relative to this script, so future directory moves work.
$presetPath = Join-Path $sourceDir 'export_presets.cfg'
$preset = Get-Content -LiteralPath $presetPath -Raw
$templateForGodot = $templateExe.Replace('\','/')
$preset = [regex]::Replace($preset,'custom_template/(debug|release)="[^"]*"', ('custom_template/$1="' + $templateForGodot + '"'))
[IO.File]::WriteAllText($presetPath, $preset, [Text.UTF8Encoding]::new($false))
$runtimeExe = Join-Path $appDir 'GriddyTranslate.runtime.exe'
$exportLog = Join-Path $qaDir 'export.log'
$exportErr = Join-Path $qaDir 'export.err'
$exportArgs = '--headless --path "' + $sourceDir + '" --export-debug "Windows Desktop" "' + $runtimeExe + '"'
$exportProcess = Start-Process -FilePath $godotExe -ArgumentList $exportArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $exportLog -RedirectStandardError $exportErr
$exportOutput = Get-Content -LiteralPath $exportLog -Raw
$exportErrors = Get-Content -LiteralPath $exportErr -Raw
if ($exportErrors -match 'Parse Error|Failed to load|Export failed') { throw "Source compilation failed. See $exportErr" }
if ($exportProcess.ExitCode -ne 0) {
    # LuaAPI 4.2's editor extension may crash on unload after a complete export.
    # A completed pack is only accepted after the actual exported runtime passes.
    if ($exportOutput -notmatch 'savepack: end' -or $exportErrors -match 'Parse Error|Failed to load|Export failed') { throw "Export failed. See $exportLog and $exportErr" }
    if ($SkipTests) { throw 'Nonzero exporter exit requires runtime validation; run without -SkipTests.' }
    Write-Warning 'Exporter exited during native-extension shutdown. Validating the exported application before accepting the build.'
}
if (!(Test-Path -LiteralPath $runtimeExe) -or !(Test-Path -LiteralPath (Join-Path $appDir 'GriddyTranslate.runtime.pck'))) { throw 'Export did not create both runtime and pack.' }
$compiler = (Get-Command gcc.exe -ErrorAction Stop).Source
& $compiler -O2 -static -municode -mwindows -Wall -Wextra (Join-Path $projectRoot 'tools\launcher.c') -o (Join-Path $appDir 'GriddyTranslate.exe') -lole32 -lwindowscodecs -lgdi32 -luser32
if ($LASTEXITCODE -ne 0) { throw 'Standalone launcher build failed.' }
Copy-Item -LiteralPath (Join-Path $projectRoot 'tools\native-startup.frames') -Destination $appDir -Force
Copy-Item -LiteralPath (Join-Path $sourceDir 'addons\luaAPI\bin\libluaapi.windows.template_debug.x86_64.dll') -Destination $appDir -Force
Copy-Item -LiteralPath (Join-Path $sourceDir '使用说明.md') -Destination $appDir -Force
Copy-Item -LiteralPath (Join-Path $sourceDir 'CHANGES-GriddyTranslate.md') -Destination $appDir -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\修复说明.md') -Destination $appDir -Force
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tools\licenses') -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $appDir -Force }

if (!$SkipTests) {
    $suites = if ($StartupOnly) { @('startup-wrap') } else { @('regression','update','slider','pronunciation','menu','startup-wrap','theme-rendering','dispatch','translation-performance','wordbook-storage','obsidian','wordbook-ui','wordbook','notice') }
    foreach ($testName in $suites) {
        $env:GRIDDY_TEST_OUTPUT = Join-Path $qaDir ('packaged-' + $testName)
        $testLog = Join-Path $qaDir ('packaged-' + $testName + '.log')
        $testErr = Join-Path $qaDir ('packaged-' + $testName + '.err')
        $testArgs = ('--headless ' * [int]($testName -in @('regression','dispatch','translation-performance','wordbook-storage','obsidian'))) + '--resolution 1280x720 -- --test --' + $testName + '-test'
        if ($testName -eq 'startup-wrap') { $testArgs += ' --startup-animation --startup-profile' }
        $testProcess = Start-Process -FilePath $runtimeExe -ArgumentList $testArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $testLog -RedirectStandardError $testErr
        $testHandle = $testProcess.Handle
        if (!$testProcess.WaitForExit(180000)) { $testProcess.Kill(); throw "Runtime test timed out: $testName" }
        $testOutput = Get-Content -LiteralPath $testLog -Raw
        $testErrors = Get-Content -LiteralPath $testErr -Raw
        $completion = switch ($testName) {
            'regression' { 'FAITHFUL_REGRESSION_COMPLETE failures=0' }
            'update' { 'UPDATE_REGRESSION_COMPLETE failures=0' }
            'slider' { 'SLIDER_REGRESSION_COMPLETE failures=0' }
            'pronunciation' { 'PRONUNCIATION_REGRESSION_COMPLETE failures=0' }
            'menu' { 'MENU_REGRESSION_COMPLETE failures=0' }
            'startup-wrap' { 'STARTUP_WRAP_COMPLETE failures=0' }
            'theme-rendering' { 'THEME_RENDERING_COMPLETE failures=0' }
            'dispatch' { 'DISPATCH_REGRESSION_COMPLETE failures=0' }
            'translation-performance' { 'TRANSLATION_PERFORMANCE_COMPLETE failures=0' }
            'wordbook-storage' { 'WORDBOOK_STORAGE_COMPLETE failures=0' }
            'obsidian' { 'OBSIDIAN_REGRESSION_COMPLETE failures=0' }
            'wordbook-ui' { 'WORD_BOOK_UI_TEST_PASS' }
            'wordbook' { 'WORDBOOK_REGRESSION_COMPLETE failures=0' }
            'notice' { 'NOTICE_REGRESSION_COMPLETE failures=0' }
        }
        if ($testProcess.ExitCode -ne 0 -or $testOutput -notmatch $completion -or $testOutput -match '(?m)^FAIL ' -or $testErrors -match 'SCRIPT ERROR|Parse Error') { throw "Runtime verification failed: $testName. See $testLog and $testErr" }
        Write-Output "Verified packaged $testName test."
    }
    foreach ($mode in @('skip','disabled')) {
        $env:GRIDDY_TEST_OUTPUT = Join-Path $qaDir ('packaged-startup-' + $mode)
        $testLog = Join-Path $qaDir ('packaged-startup-' + $mode + '.log')
        $testErr = Join-Path $qaDir ('packaged-startup-' + $mode + '.err')
        $testArgs = '--resolution 1280x720 -- --test --startup-wrap-test --startup-profile'
        if ($mode -eq 'skip') { $testArgs += ' --startup-animation --startup-skip' }
        $testProcess = Start-Process -FilePath $runtimeExe -ArgumentList $testArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $testLog -RedirectStandardError $testErr
        $testHandle = $testProcess.Handle
        if (!$testProcess.WaitForExit(45000)) { $testProcess.Kill(); throw "Runtime startup test timed out: $mode" }
        $testOutput = Get-Content -LiteralPath $testLog -Raw
        $testErrors = Get-Content -LiteralPath $testErr -Raw
        if ($testProcess.ExitCode -ne 0 -or $testOutput -notmatch 'STARTUP_WRAP_COMPLETE failures=0' -or $testOutput -match '(?m)^FAIL ' -or $testErrors -match 'SCRIPT ERROR|Parse Error') { throw "Runtime startup verification failed: $mode" }
        Write-Output "Verified packaged startup $mode test."
    }
    foreach ($mode in @('natural','skip','disabled')) {
        $env:GRIDDY_TEST_OUTPUT = Join-Path $qaDir ('packaged-native-' + $mode)
        New-Item -ItemType Directory -Path $env:GRIDDY_TEST_OUTPUT -Force | Out-Null
        $testArgs = '--resolution 1280x720 -- --test --native-startup-test --startup-profile'
        if ($mode -ne 'disabled') { $testArgs += ' --startup-animation' }
        if ($mode -eq 'skip') { $testArgs += ' --native-startup-auto-skip' }
        $launcher = Start-Process -FilePath (Join-Path $appDir 'GriddyTranslate.exe') -ArgumentList $testArgs -WindowStyle Hidden -PassThru
        $testHandle = $launcher.Handle
        if (!$launcher.WaitForExit(50000)) { $launcher.Kill(); throw "Native startup test timed out: $mode" }
        $native = Get-Content -LiteralPath (Join-Path $env:GRIDDY_TEST_OUTPUT 'native-timing.json') -Raw | ConvertFrom-Json
        $runtime = Get-Content -LiteralPath (Join-Path $env:GRIDDY_TEST_OUTPUT 'runtime-result.json') -Raw | ConvertFrom-Json
        if ($launcher.ExitCode -ne 0 -or $runtime.failures -ne 0 -or $native.launcher_pid -ne $launcher.Id -or $native.runtime_pid -ne $runtime.process_id) { throw "Native startup validation failed: $mode" }
        if ($mode -ne 'disabled') {
            if (!$native.first_window_visible -or !$native.owner_attached) { throw "Native splash was not visibly covering its runtime: $mode" }
            if ($native.first_paint_ms -gt 250 -or $native.first_paint_ms -le 0) { throw "Early splash did not paint promptly: $mode" }
            if ($native.width -ne 1920 -or $native.height -ne 1080 -or $native.frame_count -ne 330) { throw 'Native startup frame pack is not the verified Full HD sequence.' }
            if ($native.exit_start_ms - $native.logo_complete_ms -lt 500 -or $native.exit_start_ms -lt $native.ready_ms -or $native.exit_end_ms - $native.exit_start_ms -lt 450) { throw "Native startup skipped the logo hold, ready handoff or exit: $mode" }
            if ($native.rejected_inputs -lt 1 -or $native.exit_inputs -lt 1) { throw "Native startup did not exercise blocked and exit input: $mode" }
            if (($mode -eq 'skip') -ne [bool]$native.skip_requested) { throw "Native startup chose the wrong completion mode: $mode" }
            if ($mode -eq 'natural' -and $native.exit_start_ms -lt 10500) { throw 'Native startup ended before the full reference sequence.' }
        } elseif ($runtime.native -or $native.first_paint_ms -ne 0) { throw 'Disabled startup unexpectedly loaded the native animation.' }
        Write-Output "Verified portable launcher $mode test (first paint: $($native.first_paint_ms) ms)."
    }
}
$zipPath = Join-Path $packageDir 'GriddyTranslate-Windows.zip'
# A separate update checkout must still unpack to the usual portable folder.
# Build away from an active runtime without changing the package's entry path.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipTemporary = Join-Path $packageDir 'GriddyTranslate-Windows.building.zip'
if (Test-Path -LiteralPath $zipTemporary) { Remove-Item -LiteralPath $zipTemporary -Force }
$archive = [IO.Compression.ZipFile]::Open($zipTemporary, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in (Get-ChildItem -LiteralPath $appDir -Recurse -File)) {
        $relative = $file.FullName.Substring($appDir.Length).TrimStart([char[]]'\/').Replace('\','/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, ('GriddyTranslate/' + $relative), [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }
Move-Item -LiteralPath $zipTemporary -Destination $zipPath -Force
$manifest = [ordered]@{ generatedAt=(Get-Date).ToString('o'); project=$projectRoot; zip=$zipPath; sha256=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash; bytes=(Get-Item -LiteralPath $zipPath).Length; tested=(!$SkipTests); verification=$(if ($StartupOnly) { 'startup' } else { 'full' }) }
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packageDir 'manifest.json') -Encoding utf8
($manifest.sha256.ToLowerInvariant() + '  GriddyTranslate-Windows.zip') | Set-Content -LiteralPath (Join-Path $packageDir 'SHA256SUMS.txt') -Encoding ascii
Write-Output "Portable ZIP: $zipPath"
