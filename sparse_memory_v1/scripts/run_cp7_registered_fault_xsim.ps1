[CmdletBinding()]
param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.3\bin",
    [switch]$KeepWork
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Utf8Lines {
    param([string]$Path, [string[]]$Lines)
    [IO.File]::WriteAllLines($Path, $Lines, [Text.UTF8Encoding]::new($false))
}

function Invoke-LoggedNative {
    param([string]$Executable, [string[]]$Arguments, [string]$LogPath)
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $Executable @Arguments *> $LogPath
        return [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
}

function Relative-Path {
    param([string]$Root, [string]$Path)
    $rootUri = [Uri]::new($Root.TrimEnd('\') + '\')
    return [Uri]::UnescapeDataString(
        $rootUri.MakeRelativeUri([Uri]::new($Path)).ToString()
    ).Replace('\', '/')
}

$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Parent $scriptPath
$sparseRoot = (Get-Item -LiteralPath (Join-Path $scriptDir "..") -Force).FullName
$reportDir = Join-Path $sparseRoot "reports\cp7"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

$stamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
$runId = "cp7_fault_xsim_${stamp}_$PID"
# Xilinx *.bat launchers pass through cmd.exe, which cannot use a UNC path as
# its current directory.  Keep all generated simulator state in Windows-local
# TEMP while source and final evidence remain inside the isolated subtree.
$workDir = Join-Path $env:TEMP "zephyr_c7x_${stamp}_$PID"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

$relativeSources = @(
    "tb\cp6_xsim_glbl.v",
    "imports\pe_v1\rtl\arithmetic\pe_requant_lane.sv",
    "imports\pe_v1\rtl\arithmetic\pe_local_requant_bank_4lane.sv",
    "imports\pe_v1\rtl\pe\pe_hybrid_mac.sv",
    "rtl\sparse_memory_dma_v1.v",
    "rtl\sparse_memory_v4_table_v1.v",
    "rtl\sparse_memory_service_v1.sv",
    "rtl\sparse_stage_map_v1.sv",
    "rtl\sparse_union_planner_v1.sv",
    "rtl\sparse_recurrent_context_store_core_v1.v",
    "rtl\sparse_recurrent_context_store_v1.sv",
    "imports\memory_v4\memory\sequential_pe_job_controller.v",
    "imports\pe_v1\rtl\nonlinear\pe_sigmoid_lut_255.v",
    "imports\pe_v1\rtl\postprocess\pe_gate_postprocess.v",
    "imports\pe_v1\rtl\pe\pe_membrane_sequencer.v",
    "imports\pe_v1\rtl\stream\pe_output_serializer.v",
    "imports\pe_v1\rtl\stream\pe_shared_requant_engine.v",
    "imports\pe_v1\rtl\index\pe_spike_decision.v",
    "imports\pe_v1\rtl\index\pe_active_index_writer.v",
    "imports\pe_v1\rtl\pe\pe_cdf_sequencer.v",
    "imports\pe_v1\rtl\top\pe_array_datapath.v",
    "rtl\sequential_v4_sparse_memory_subsystem.sv",
    "tb\tb_sequential_v4_sparse_memory_subsystem.sv"
)
$sourcePaths = @($relativeSources | ForEach-Object {
    (Get-Item -LiteralPath (Join-Path $sparseRoot $_) -Force).FullName
})
$rtlInclude = (Get-Item -LiteralPath (Join-Path $sparseRoot "rtl") -Force).FullName
$memoryInclude = (Get-Item -LiteralPath (
    Join-Path $sparseRoot "imports\memory_v4"
) -Force).FullName
$imagePath = (Get-Item -LiteralPath (
    Join-Path $sparseRoot "imports\fixtures\v4\parameters_v4.bin"
) -Force).FullName
Copy-Item -LiteralPath $imagePath -Destination (
    Join-Path $workDir "parameters_v4.bin"
)

$hashTargets = @($sourcePaths) + @(
    (Join-Path $sparseRoot "rtl\sparse_memory_v4_map_v1.vh"),
    (Join-Path $sparseRoot "imports\memory_v4\memory\model_memory_v4_map.vh"),
    $imagePath,
    $scriptPath
)
$beforeHashes = @{}
foreach ($path in $hashTargets) {
    $beforeHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$xvlogLog = Join-Path $workDir "xvlog_console.txt"
$xelabLog = Join-Path $workDir "xelab_console.txt"
$xsimConsole = Join-Path $workDir "xsim_console.txt"
$xsimLog = Join-Path $workDir "xsim.log"
$xvlog = (Get-Item -LiteralPath (Join-Path $VivadoBin "xvlog.bat") -Force).FullName
$xelab = (Get-Item -LiteralPath (Join-Path $VivadoBin "xelab.bat") -Force).FullName
$xsim = (Get-Item -LiteralPath (Join-Path $VivadoBin "xsim.bat") -Force).FullName

Push-Location $workDir
try {
    $xvlogExit = Invoke-LoggedNative $xvlog (
        @("--sv", "--relax", "-i", $rtlInclude, "-i", $memoryInclude) +
        $sourcePaths
    ) $xvlogLog
    if ($xvlogExit -ne 0) { throw "xvlog_exit_$xvlogExit" }
    $xelabExit = Invoke-LoggedNative $xelab @(
        "tb_sequential_v4_sparse_memory_subsystem", "glbl", "-L",
        "unisims_ver", "-s", "c7x", "--debug", "typical"
    ) $xelabLog
    if ($xelabExit -ne 0) { throw "xelab_exit_$xelabExit" }
    $xsimExit = Invoke-LoggedNative $xsim @(
        "c7x", "-runall", "-log", $xsimLog
    ) $xsimConsole
    if ($xsimExit -ne 0) { throw "xsim_exit_$xsimExit" }
}
finally {
    Pop-Location
}

$logText = [IO.File]::ReadAllText($xsimLog)
$pass = [regex]::Match($logText,
    '(?m)^\s*PASS tb_sequential_v4_sparse_memory_subsystem checks=([0-9]+) dense_bytes=([0-9]+) sparse_bytes=([0-9]+)\s*$')
if (-not $pass.Success) { throw "pass_signature_missing" }
if ([regex]::IsMatch($logText, '(?im)^\s*(?:FAIL|FATAL)(?:\b|_)')) {
    throw "fail_or_fatal_signature_present"
}
$checks = [int64]$pass.Groups[1].Value
$denseBytes = [int64]$pass.Groups[2].Value
$sparseBytes = [int64]$pass.Groups[3].Value
if ($checks -ne 12450755) { throw "unexpected_check_count_$checks" }
if ($denseBytes -ne 2101088) { throw "unexpected_dense_bytes_$denseBytes" }
if ($sparseBytes -ne 1052208) { throw "unexpected_sparse_bytes_$sparseBytes" }

foreach ($path in $hashTargets) {
    $after = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($after -cne $beforeHashes[$path]) { throw "input_changed_during_run_$path" }
}

$resolved = @(
    "checkpoint=CP7",
    "run_id=$runId",
    "scope=registered_internal_fault_abort_connected_XSim",
    "include_dir=rtl",
    "include_dir=imports/memory_v4"
)
foreach ($path in $hashTargets) {
    $relative = Relative-Path $sparseRoot $path
    $resolved += "sha256=$($beforeHashes[$path])|$relative"
}
Write-Utf8Lines (Join-Path $reportDir "cp7_registered_fault_xsim_inputs.txt") $resolved
Copy-Item -LiteralPath $xvlogLog -Destination (
    Join-Path $reportDir "cp7_registered_fault_xvlog_console.txt"
) -Force
Copy-Item -LiteralPath $xelabLog -Destination (
    Join-Path $reportDir "cp7_registered_fault_xelab_console.txt"
) -Force
Copy-Item -LiteralPath $xsimConsole -Destination (
    Join-Path $reportDir "cp7_registered_fault_xsim_console.txt"
) -Force
Copy-Item -LiteralPath $xsimLog -Destination (
    Join-Path $reportDir "cp7_registered_fault_xsim.log"
) -Force
Write-Utf8Lines (Join-Path $reportDir "cp7_registered_fault_xsim_summary.txt") @(
    "checkpoint=CP7",
    "run_id=$runId",
    "evidence_type=Vivado_2018.3_connected_XSim",
    "registered_fault_cut=PASS",
    "public_fault_visible_same_cycle=PASS",
    "same_cycle_done_suppressed=PASS",
    "internal_fault_control_asserts_after_register=PASS",
    "job_launch_register_slice=PASS",
    "checks=$checks",
    "dense_bytes=$denseBytes",
    "sparse_bytes=$sparseBytes",
    "source_hash_stable=1",
    "runner_hash_stable=1",
    "status=PASS",
    "gate_pass=1"
)

if (-not $KeepWork) {
    Remove-Item -LiteralPath $workDir -Recurse -Force
}
Write-Host "CP7_REGISTERED_FAULT_XSIM_PASS run_id=$runId checks=$checks"
