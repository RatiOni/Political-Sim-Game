param([string]$Python = "python")
$ErrorActionPreference = "Stop"
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$buildDir = [IO.Path]::GetFullPath((Join-Path $repoRoot "build"))
$distDir = [IO.Path]::GetFullPath((Join-Path $repoRoot "dist"))

function Assert-RepositoryChild([string]$Candidate) {
    $full = [IO.Path]::GetFullPath($Candidate)
    $prefix = $repoRoot.TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing packaging operation outside repository: $full"
    }
    return $full
}

$buildDir = Assert-RepositoryChild $buildDir
$distDir = Assert-RepositoryChild $distDir
$verifyData = Assert-RepositoryChild (Join-Path $buildDir "verify-user-data")
$oldQt = $env:QT_QPA_PLATFORM
$oldData = $env:ARDENIA_USER_DATA_DIR

function Invoke-Checked([scriptblock]$Command, [string]$Label) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" }
}

Push-Location $repoRoot
try {
    $toolchain = & $Python -c `
        "import platform,struct,sys,PySide6,PyInstaller; bits=struct.calcsize('P')*8; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}|{PySide6.__version__}|{PyInstaller.__version__}|{platform.machine()}|{bits}')"
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect packaging toolchain" }
    if ($toolchain.Trim() -ne "3.14.6|6.11.1|6.16.0|AMD64|64") {
        throw "Unsupported packaging toolchain: $toolchain"
    }

    foreach ($target in @($buildDir, $distDir)) {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Path $buildDir | Out-Null

    Invoke-Checked {
        & $Python packaging\render_windows_version.py build\windows-version.txt
    } "Windows version rendering"
    Invoke-Checked {
        & $Python -m PyInstaller --clean --noconfirm packaging\ardenia.spec
    } "PyInstaller"

    $packageDir = Join-Path $distDir "Ardenia"
    if (-not (Test-Path -LiteralPath (Join-Path $packageDir "Ardenia.exe"))) {
        throw "PyInstaller did not produce dist\Ardenia\Ardenia.exe"
    }
    Copy-Item -LiteralPath distribution\PLAYTEST_README.txt -Destination $packageDir
    Copy-Item -LiteralPath distribution\FEEDBACK_TEMPLATE.txt -Destination $packageDir

    New-Item -ItemType Directory -Path $verifyData | Out-Null
    $env:QT_QPA_PLATFORM = "offscreen"
    $env:ARDENIA_USER_DATA_DIR = $verifyData
    $process = Start-Process -FilePath (Join-Path $packageDir "Ardenia.exe") `
        -ArgumentList "--verify-build" -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "Packaged verification failed with exit code $($process.ExitCode)"
    }
    Remove-Item -LiteralPath $verifyData -Recurse -Force

    $archiveName = (& $Python -c "import version; print(version.ARCHIVE_FILENAME)").Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not read archive version" }
    $archivePath = Assert-RepositoryChild (Join-Path $distDir $archiveName)
    Compress-Archive -LiteralPath $packageDir -DestinationPath $archivePath
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLower()
    $checksumPath = Assert-RepositoryChild "$archivePath.sha256"
    Set-Content -LiteralPath $checksumPath `
        -Value "$hash  $([IO.Path]::GetFileName($archivePath))" -Encoding ascii
    Write-Host "Package: $archivePath"
    Write-Host "Checksum: $checksumPath"
}
finally {
    if ($null -eq $oldQt) { Remove-Item Env:QT_QPA_PLATFORM -ErrorAction SilentlyContinue }
    else { $env:QT_QPA_PLATFORM = $oldQt }
    if ($null -eq $oldData) { Remove-Item Env:ARDENIA_USER_DATA_DIR -ErrorAction SilentlyContinue }
    else { $env:ARDENIA_USER_DATA_DIR = $oldData }
    Pop-Location
}
