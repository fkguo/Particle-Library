param([switch]$SkipValidation, [switch]$SkipBuild, [string]$InnoCompilerPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
$expectedSnapshotHash = 'c82dab0c0a7c5264f23508066cabb8df9eacc1dbfc83c8d20fade6053394ba8a'
$snapshotPath = Join-Path $repoRoot 'assets/pdgall-2026.0.sqlite'
$pubspec = Get-Content (Join-Path $repoRoot 'pubspec.yaml') -Raw
$version = ([regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')).Groups[1].Value
if (-not $version) { throw 'Could not read application version.' }
if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) { throw 'The PDG snapshot is missing.' }
if ((Get-FileHash $snapshotPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedSnapshotHash) { throw 'PDG snapshot SHA-256 mismatch.' }
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) { throw 'Flutter is not on PATH.' }
if (-not $SkipValidation) {
    & $flutter.Source pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
    & $flutter.Source analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed.' }
    & $flutter.Source test
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }
}
if (-not $SkipBuild) {
    & $flutter.Source build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
}
$buildDir = Join-Path $repoRoot 'build/windows/x64/runner/Release'
$requiredFiles = @('ParticleLibrary.exe', 'flutter_windows.dll', 'pdfium.dll', 'pdfrx_pdfium_gate.dll', 'sqlite3.dll', 'sqlite3_flutter_libs_plugin.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z', 'data/flutter_assets/assets/pdgall-2026.0.sqlite')
foreach ($relativePath in $requiredFiles) {
    $runtimeFile = Join-Path $buildDir $relativePath
    if (-not (Test-Path -LiteralPath $runtimeFile)) { throw 'Missing runtime file.' }
}
$distDir = Join-Path $repoRoot 'dist/release'
$stageDir = Join-Path $distDir 'Particle-Library-Windows-x64'
[System.IO.Directory]::CreateDirectory($distDir) | Out-Null
if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
[System.IO.Directory]::CreateDirectory($stageDir) | Out-Null
Copy-Item -Path (Join-Path $buildDir '*') -Destination $stageDir -Recurse -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination $stageDir
Copy-Item -LiteralPath (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md') -Destination $stageDir
Copy-Item -LiteralPath (Join-Path $repoRoot 'tool/windows/README.txt') -Destination (Join-Path $stageDir 'README.txt')
Copy-Item -LiteralPath (Join-Path $repoRoot 'windows/runner/resources/app_icon.ico') -Destination (Join-Path $stageDir 'app_icon.ico')
$portableZip = Join-Path $distDir Particle-Library-$version-Windows-x64-Portable.zip
$installer = Join-Path $distDir Particle-Library-$version-Windows-x64-Setup.exe
$checksums = Join-Path $distDir 'SHA256SUMS.txt'
if (Test-Path -LiteralPath $distDir -PathType Container) {
    Get-ChildItem -LiteralPath $distDir -File |
        Where-Object {
            $_.Name -match '^Particle-Library-[0-9]+\.[0-9]+\.[0-9]+-Windows-x64-(Setup\.exe|Portable\.zip)$' -and
            $_.Name -notin @((Split-Path -Leaf $portableZip), (Split-Path -Leaf $installer))
        } |
        Remove-Item -Force
}
foreach ($artifact in @($portableZip, $installer, $checksums)) {
    if (Test-Path -LiteralPath $artifact) { Remove-Item -LiteralPath $artifact -Force }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stageDir, $portableZip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
if (-not $InnoCompilerPath) {
    $innoCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($innoCommand) { $InnoCompilerPath = $innoCommand.Source }
}
if (-not $InnoCompilerPath) {
    $innoCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs/Inno Setup 6/ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6/ISCC.exe')
    )
    $InnoCompilerPath = $innoCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $InnoCompilerPath) { throw 'Inno Setup 6 compiler was not found.' }
$installerScript = Join-Path $repoRoot 'tool/windows/installer.iss'
& $InnoCompilerPath /DStagingDir=$stageDir /DOutputDir=$distDir /DAppVersion=$version $installerScript
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed.' }
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'Installer was not created.' }
$hashLines = @()
foreach ($artifact in @($portableZip, $installer)) {
    $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    $hashLines += ($hash + '  ' + [System.IO.Path]::GetFileName($artifact))
}
Set-Content -LiteralPath $checksums -Value $hashLines -Encoding ascii
if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
