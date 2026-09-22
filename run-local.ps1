param(
    [string]$DataDir = "",
    [int]$Port = 9000
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($DataDir)) {
    if (-not [string]::IsNullOrWhiteSpace($env:EV_DATA_DIR)) {
        $DataDir = $env:EV_DATA_DIR
    } elseif (Test-Path (Join-Path $ProjectRoot "data_manual")) {
        # Prefer the existing local demo database when it is available.
        $DataDir = Join-Path $ProjectRoot "data_manual"
    } else {
        $DataDir = Join-Path $ProjectRoot "data"
    }
}

if (-not [IO.Path]::IsPathRooted($DataDir)) {
    $DataDir = Join-Path $ProjectRoot $DataDir
}

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
$DataDir = (Resolve-Path $DataDir).Path
$DbPath = Join-Path $DataDir "ocpp.db"

if (Test-Path $DbPath) {
    $DbSize = (Get-Item $DbPath).Length
    Write-Host "Using SQLite database: $DbPath ($DbSize bytes)" -ForegroundColor Cyan
} else {
    Write-Warning "No ocpp.db found in $DataDir. The application will create a new empty database."
}

$Python = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $Python)) {
    $Python = Join-Path $ProjectRoot "venv\Scripts\python.exe"
}
if (-not (Test-Path $Python)) {
    $Python = "python"
}

$env:DATA_DIR = $DataDir
Write-Host "Dashboard: http://127.0.0.1:$Port" -ForegroundColor Green
Write-Host "DATA_DIR:  $env:DATA_DIR" -ForegroundColor DarkGray
Write-Host "Stop with Ctrl+C" -ForegroundColor DarkGray

& $Python -m uvicorn app.main:app --host 0.0.0.0 --port $Port --reload
exit $LASTEXITCODE
