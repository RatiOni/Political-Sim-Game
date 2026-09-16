$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$python = Join-Path $repositoryRoot ".venv\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) {
    throw "Godot 4.7.2 was not found at $godot"
}

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    $commonGitDirectory = (& git -C $repositoryRoot rev-parse --path-format=absolute --git-common-dir).Trim()
    $python = Join-Path (Split-Path -Parent $commonGitDirectory) ".venv\Scripts\python.exe"
}

if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw "The Ardenia Python environment was not found at $python"
}

Push-Location $repositoryRoot
try {
    & $python "godot_bridge_test.py"
    if ($LASTEXITCODE -ne 0) {
        throw "Godot bridge checks failed with exit code $LASTEXITCODE"
    }
    $env:ARDENIA_PYTHON_EXECUTABLE = $python
    $env:PYTHONPATH = if ([string]::IsNullOrEmpty($env:PYTHONPATH)) {
        $repositoryRoot
    }
    else {
        "$repositoryRoot;$env:PYTHONPATH"
    }
    & $godot --path godot
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
