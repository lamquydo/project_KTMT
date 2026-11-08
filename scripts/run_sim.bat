@echo off
REM =============================================================================
REM File: scripts/run_sim.bat
REM Description: One-click Windows Batch Script to Compile & Simulate Cache RTL
REM =============================================================================

pushd "%~dp0.."

set IVERILOG=iverilog
set VVP=vvp

where iverilog >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    if exist "C:\iverilog\bin\iverilog.exe" (
        set IVERILOG="C:\iverilog\bin\iverilog.exe"
        set VVP="C:\iverilog\bin\vvp.exe"
    ) else (
        echo [ERROR] Cannot find Icarus Verilog ^(iverilog^) on this system.
        popd
        exit /b 1
    )
)

echo [1/2] Compiling Verilog RTL and Testbench...
%IVERILOG% -I rtl -o sim/cache_sim.out rtl/cache_top.v rtl/cache_controller.v rtl/tag_array.v rtl/data_array.v rtl/lru_logic.v sim/main_memory_model.v sim/tb_cache_top.v
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Verilog compilation failed!
    popd
    exit /b 1
)

echo [2/2] Running VVP Simulation...
%VVP% sim/cache_sim.out

popd
