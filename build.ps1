param([switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$sourceDir = Join-Path $projectRoot 'src'
$godotExe = Join-Path $projectRoot 'tools\godot\Godot_v4.2.2-stable_win64_console.exe'
$templateExe = Join-Path $projectRoot 'tools\windows-runtime-template.exe'
$appDir = Join-Path $projectRoot 'dist\GriddyTranslate'
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
& $compiler -O2 -static -municode -mwindows -Wall -Wextra (Join-Path $projectRoot 'tools\launcher.c') -o (Join-Path $appDir 'GriddyTranslate.exe')
if ($LASTEXITCODE -ne 0) { throw 'Standalone launcher build failed.' }
Copy-Item -LiteralPath (Join-Path $sourceDir 'addons\luaAPI\bin\libluaapi.windows.template_debug.x86_64.dll') -Destination $appDir -Force
Copy-Item -LiteralPath (Join-Path $sourceDir '使用说明.md') -Destination $appDir -Force
Copy-Item -LiteralPath (Join-Path $sourceDir 'CHANGES-GriddyTranslate.md') -Destination $appDir -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\修复说明.md') -Destination $appDir -Force
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tools\licenses') -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $appDir -Force }

if (!$SkipTests) {
    foreach ($testName in @('regression','update')) {
        $env:GRIDDY_TEST_OUTPUT = Join-Path $qaDir ('packaged-' + $testName)
        $testLog = Join-Path $qaDir ('packaged-' + $testName + '.log')
        $testErr = Join-Path $qaDir ('packaged-' + $testName + '.err')
        $testArgs = ('--headless ' * [int]($testName -eq 'regression')) + '--resolution 1280x720 -- --test --' + $testName + '-test'
        $testProcess = Start-Process -FilePath $runtimeExe -ArgumentList $testArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $testLog -RedirectStandardError $testErr
        if (!$testProcess.WaitForExit(180000)) { $testProcess.Kill(); throw "Runtime test timed out: $testName" }
        $testOutput = Get-Content -LiteralPath $testLog -Raw
        $testErrors = Get-Content -LiteralPath $testErr -Raw
        $completion = if ($testName -eq 'regression') { 'FAITHFUL_REGRESSION_COMPLETE failures=0' } else { 'UPDATE_REGRESSION_COMPLETE failures=0' }
        if ($testProcess.ExitCode -ne 0 -or $testOutput -notmatch $completion -or $testOutput -match '(?m)^FAIL ' -or $testErrors -match 'SCRIPT ERROR|Parse Error') { throw "Runtime verification failed: $testName. See $testLog and $testErr" }
        Write-Output "Verified packaged $testName test."
    }
}
$zipPath = Join-Path $packageDir 'GriddyTranslate-Windows.zip'
Compress-Archive -LiteralPath $appDir -DestinationPath $zipPath -CompressionLevel Optimal -Force
$manifest = [ordered]@{ generatedAt=(Get-Date).ToString('o'); project=$projectRoot; zip=$zipPath; sha256=(Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash; bytes=(Get-Item -LiteralPath $zipPath).Length; tested=(!$SkipTests) }
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $packageDir 'manifest.json') -Encoding utf8
Write-Output "Portable ZIP: $zipPath"
