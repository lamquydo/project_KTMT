# =============================================================================
# File: scripts/run_sim.ps1
# Description: Automated Build & Verification Script for 4KB 2-Way Cache Project
# Usage: .\scripts\run_sim.ps1 [-Wave]
# =============================================================================

param (
    [switch]$Wave = $false
)

$ErrorActionPreference = "Stop"

# Move to project root directory
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  BUILDING & RUNNING RTL SIMULATION: 4KB 2-WAY SET-ASSOCIATIVE CACHE" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# Locate Icarus Verilog tools
$IverilogExe = "iverilog"
$VvpExe      = "vvp"
$GtkwaveExe  = "gtkwave"

if (-not (Get-Command $IverilogExe -ErrorAction SilentlyContinue)) {
    if (Test-Path "C:\iverilog\bin\iverilog.exe") {
        $IverilogExe = "C:\iverilog\bin\iverilog.exe"
        $VvpExe      = "C:\iverilog\bin\vvp.exe"
        $GtkwaveExe  = "C:\iverilog\gtkwave\bin\gtkwave.exe"
    } else {
        Write-Error "Could not find iverilog in PATH or C:\iverilog\bin!"
        exit 1
    }
}

$RtlFiles = @(
    "rtl/cache_top.v",
    "rtl/cache_controller.v",
    "rtl/tag_array.v",
    "rtl/data_array.v",
    "rtl/lru_logic.v"
)

$SimFiles = @(
    "sim/main_memory_model.v",
    "sim/tb_cache_top.v"
)

$OutFile = "sim/cache_sim.out"

Write-Host "[1/2] Compiling Verilog RTL & Testbench with Icarus Verilog..." -ForegroundColor Yellow
& $IverilogExe -I rtl -o $OutFile $RtlFiles $SimFiles
if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed!"
    exit $LASTEXITCODE
}
Write-Host "      -> Compilation successful: $OutFile" -ForegroundColor Green

Write-Host "[2/2] Executing Simulation via VVP..." -ForegroundColor Yellow
& $VvpExe $OutFile
if ($LASTEXITCODE -ne 0) {
    Write-Error "Simulation execution failed!"
    exit $LASTEXITCODE
}

if ($Wave) {
    if (Test-Path $GtkwaveExe) {
        Write-Host "[INFO] Launching GTKWave with cache_sim.vcd..." -ForegroundColor Cyan
        & $GtkwaveExe "cache_sim.vcd"
    } elseif (Get-Command "gtkwave" -ErrorAction SilentlyContinue) {
        Write-Host "[INFO] Launching GTKWave with cache_sim.vcd..." -ForegroundColor Cyan
        gtkwave "cache_sim.vcd"
    } else {
        Write-Warning "GTKWave executable not found. Waveform saved at: $ProjectRoot\cache_sim.vcd"
    }
}
