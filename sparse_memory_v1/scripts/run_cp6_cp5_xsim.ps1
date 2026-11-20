[CmdletBinding()]
param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.3\bin",
    [switch]$KeepWork
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-AtomicText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Lines
    )
    $temporary = "$Path.tmp.$PID"
    [IO.File]::WriteAllLines(
        $temporary, $Lines, [Text.UTF8Encoding]::new($false)
    )
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Publish-AtomicFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $temporary = "$Destination.tmp.$PID"
    Copy-Item -LiteralPath $Source -Destination $temporary -Force
    Move-Item -LiteralPath $temporary -Destination $Destination -Force
}

function Get-TextSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString(
            $algorithm.ComputeHash($bytes)
        )).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function Resolve-IsolatedInput {
    param(
        [Parameter(Mandatory = $true)][string]$SparseRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Kind,
        [switch]$Directory
    )
    $item = Get-Item -LiteralPath (Join-Path $SparseRoot $RelativePath) -Force
    if ($Directory -and -not $item.PSIsContainer) {
        throw "CP6_INCLUDE_NOT_DIRECTORY: $($item.FullName)"
    }
    if (-not $Directory -and $item.PSIsContainer) {
        throw "CP6_INPUT_NOT_FILE: $($item.FullName)"
    }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "CP6_ISOLATION_FAIL: reparse input is forbidden: $($item.FullName)"
    }
    $rootItem = Get-Item -LiteralPath $SparseRoot -Force
    $separator = [IO.Path]::DirectorySeparatorChar
    $alternate = [IO.Path]::AltDirectorySeparatorChar
    $prefix = $rootItem.FullName.TrimEnd($separator, $alternate) + $separator
    if (-not $item.FullName.StartsWith(
        $prefix, [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "CP6_ISOLATION_FAIL: $Kind escaped sparse_memory_v1: $($item.FullName)"
    }
    return $item.FullName
}

function Invoke-LoggedNative {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$LogPath
    )
    # Keep high-volume simulator output on the isolated Windows-visible
    # filesystem instead of the PowerShell/WSL interop pipe.
    & $Executable @Arguments *> $LogPath
    return [int]$LASTEXITCODE
}

function Clean-OneLine {
    param([Parameter(Mandatory = $true)][string]$Text)
    return $Text.Replace("`r", " ").Replace("`n", " ")
}

$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Parent $scriptPath
$sparseRoot = (Get-Item -LiteralPath (Join-Path $scriptDir "..") -Force).FullName
$reportDir = Join-Path $sparseRoot "reports\cp6"
$buildRoot = Join-Path $sparseRoot "build"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

$shortStamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
$runId = "cp5_xsim_${shortStamp}_$PID"
$startedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$workDir = Join-Path $buildRoot "c6x_${shortStamp}_$PID"
$summaryPath = Join-Path $reportDir "cp6_cp5_xsim_summary.txt"
$fixedEvidence = @{
    resolved = Join-Path $reportDir "cp6_cp5_xsim_resolved_inputs.txt"
    xvlog = Join-Path $reportDir "cp6_cp5_xvlog_console.txt"
    xelab = Join-Path $reportDir "cp6_cp5_xelab_console.txt"
    console = Join-Path $reportDir "cp6_cp5_xsim_console.txt"
    xsim = Join-Path $reportDir "cp6_cp5_xsim.log"
}

# Fixed evidence from an older run must never remain visible while this run is
# in progress. Only the marker exists until every current-run gate passes.
foreach ($path in @($summaryPath) + @($fixedEvidence.Values)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}
Write-AtomicText -Path $summaryPath -Lines @(
    "checkpoint=CP6",
    "run_id=$runId",
    "started_utc=$startedUtc",
    "status=IN_PROGRESS",
    "gate_pass=0",
    "failure_detail=run_not_completed"
)

$xvlogExit = -1
$xelabExit = -1
$xsimExit = -1
$checks = "NA"
$denseBytes = "NA"
$sparseBytes = "NA"
$passSignatureCount = -1
$failureSignatureCount = -1
$inputSetSha256 = "NA"
$xsimLogSha256 = "NA"
$runnerSha256 = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sourceHashStable = 0
$runnerHashStable = 0
$failureDetail = "runner_not_completed"
$cleanupDetail = "workdir_retained_after_failure"
$finishedUtc = "NA"

try {
    New-Item -ItemType Directory -Path $workDir | Out-Null
    $specs = @(
        [pscustomobject]@{ Kind = "source"; Relative = "tb\cp6_xsim_glbl.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\arithmetic\pe_requant_lane.sv" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\arithmetic\pe_local_requant_bank_4lane.sv" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\pe\pe_hybrid_mac.sv" },
        [pscustomobject]@{ Kind = "source"; Relative = "rtl\sparse_memory_dma_v1.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "rtl\sparse_memory_v4_table_v1.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "rtl\sparse_memory_service_v1.sv" },
        [pscustomobject]@{ Kind = "source"; Relative = "rtl\sparse_stage_map_v1.sv" },
        [pscustomobject]@{ Kind = "source"; Relative = "rtl\sparse_union_planner_v1.sv" },
        [pscustomobject]@{ Kind = "source"; Relative = "rtl\sparse_recurrent_context_store_core_v1.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "rtl\sparse_recurrent_context_store_v1.sv" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\memory_v4\memory\sequential_pe_job_controller.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\nonlinear\pe_sigmoid_lut_255.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\postprocess\pe_gate_postprocess.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\pe\pe_membrane_sequencer.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\stream\pe_output_serializer.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\stream\pe_shared_requant_engine.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\index\pe_spike_decision.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\index\pe_active_index_writer.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\pe\pe_cdf_sequencer.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "imports\pe_v1\rtl\top\pe_array_datapath.v" },
        [pscustomobject]@{ Kind = "source"; Relative = "rtl\sequential_v4_sparse_memory_subsystem.sv" },
        [pscustomobject]@{ Kind = "source"; Relative = "tb\tb_sequential_v4_sparse_memory_subsystem.sv" },
        [pscustomobject]@{ Kind = "include_file"; Relative = "rtl\sparse_memory_v4_map_v1.vh" },
        [pscustomobject]@{ Kind = "include_file"; Relative = "imports\memory_v4\memory\model_memory_v4_map.vh" },
        [pscustomobject]@{ Kind = "data"; Relative = "imports\fixtures\v4\parameters_v4.bin" }
    )
    $resolved = foreach ($spec in $specs) {
        [pscustomobject]@{
            Kind = $spec.Kind
            Relative = $spec.Relative
            Path = Resolve-IsolatedInput -SparseRoot $sparseRoot `
                -RelativePath $spec.Relative -Kind $spec.Kind
        }
    }
    $rtlIncludeDir = Resolve-IsolatedInput -SparseRoot $sparseRoot `
        -RelativePath "rtl" -Kind "include_dir" -Directory
    $memoryIncludeDir = Resolve-IsolatedInput -SparseRoot $sparseRoot `
        -RelativePath "imports\memory_v4" -Kind "include_dir" -Directory

    $hashMaterial = [Collections.Generic.List[string]]::new()
    $hashMaterial.Add("include_dir|rtl")
    $hashMaterial.Add("include_dir|imports/memory_v4")
    foreach ($item in $resolved) {
        $hash = (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        $hashMaterial.Add("$($item.Kind)|$hash|$($item.Relative.Replace('\', '/'))")
    }
    $inputSetSha256 = Get-TextSha256 -Text (($hashMaterial -join "`n") + "`n")
    $resolvedPath = Join-Path $workDir "resolved_inputs.txt"
    $resolvedLines = @(
        "checkpoint=CP6",
        "run_id=$runId",
        "scope=CP5_connected_XSim_regression",
        "sparse_root=$sparseRoot",
        "input_set_sha256=$inputSetSha256",
        "include_dir=$rtlIncludeDir",
        "include_dir=$memoryIncludeDir"
    ) + @($resolved | ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        "$($_.Kind)|$hash|$($_.Path)"
    })
    Write-AtomicText -Path $resolvedPath -Lines $resolvedLines

    $sourcePaths = @($resolved | Where-Object Kind -eq "source" | ForEach-Object Path)
    $imagePath = ($resolved | Where-Object Kind -eq "data").Path
    Copy-Item -LiteralPath $imagePath -Destination (Join-Path $workDir "parameters_v4.bin")

    $xvlog = (Get-Item -LiteralPath (Join-Path $VivadoBin "xvlog.bat") -Force).FullName
    $xelab = (Get-Item -LiteralPath (Join-Path $VivadoBin "xelab.bat") -Force).FullName
    $xsim = (Get-Item -LiteralPath (Join-Path $VivadoBin "xsim.bat") -Force).FullName
    $xvlogLog = Join-Path $workDir "xvlog_console.txt"
    $xelabLog = Join-Path $workDir "xelab_console.txt"
    $xsimConsole = Join-Path $workDir "xsim_console.txt"
    $xsimLog = Join-Path $workDir "xsim.log"

    Push-Location $workDir
    try {
        $xvlogExit = Invoke-LoggedNative -Executable $xvlog -Arguments `
            (@("--sv", "--relax", "-i", $rtlIncludeDir,
                "-i", $memoryIncludeDir) + $sourcePaths) `
            -LogPath $xvlogLog
        if ($xvlogExit -ne 0) { throw "xvlog_exit_$xvlogExit" }

        $xelabExit = Invoke-LoggedNative -Executable $xelab -Arguments @(
            "tb_sequential_v4_sparse_memory_subsystem", "glbl",
            "-L", "unisims_ver", "-s", "c6x", "--debug", "typical"
        ) -LogPath $xelabLog
        if ($xelabExit -ne 0) { throw "xelab_exit_$xelabExit" }

        $xsimExit = Invoke-LoggedNative -Executable $xsim -Arguments @(
            "c6x", "-runall", "-log", $xsimLog
        ) -LogPath $xsimConsole
        if ($xsimExit -ne 0) { throw "xsim_exit_$xsimExit" }
    }
    finally {
        Pop-Location
    }

    $logText = [IO.File]::ReadAllText($xsimLog)
    $passMatches = [regex]::Matches(
        $logText,
        '(?m)^\s*PASS tb_sequential_v4_sparse_memory_subsystem checks=([0-9]+) dense_bytes=([0-9]+) sparse_bytes=([0-9]+)\s*$'
    )
    $failureMatches = [regex]::Matches(
        $logText, '(?im)^\s*(?:FAIL|FATAL)(?:\b|_)'
    )
    $passSignatureCount = $passMatches.Count
    $failureSignatureCount = $failureMatches.Count
    if ($passSignatureCount -ne 1) {
        throw "pass_signature_count_$passSignatureCount"
    }
    if ($failureSignatureCount -ne 0) {
        throw "fail_or_fatal_signature_count_$failureSignatureCount"
    }
    $checks = [int64]$passMatches[0].Groups[1].Value
    $denseBytes = [int64]$passMatches[0].Groups[2].Value
    $sparseBytes = [int64]$passMatches[0].Groups[3].Value

    $postHashMaterial = [Collections.Generic.List[string]]::new()
    $postHashMaterial.Add("include_dir|rtl")
    $postHashMaterial.Add("include_dir|imports/memory_v4")
    foreach ($item in $resolved) {
        $hash = (Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        $postHashMaterial.Add("$($item.Kind)|$hash|$($item.Relative.Replace('\', '/'))")
    }
    $postInputSetSha256 = Get-TextSha256 -Text (($postHashMaterial -join "`n") + "`n")
    $postRunnerSha256 = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sourceHashStable = [int]($postInputSetSha256 -eq $inputSetSha256)
    $runnerHashStable = [int]($postRunnerSha256 -eq $runnerSha256)
    if (-not $sourceHashStable) { throw "source_hash_changed_during_run" }
    if (-not $runnerHashStable) { throw "runner_hash_changed_during_run" }

    # The registered CP6 command-bounds decision adds one sampled cycle per
    # copy command.  The testbench deliberately counts cycle-by-cycle safety
    # invariants, so pin the resulting deterministic total as well as traffic.
    # The isolated context/list, planner-admission, run-command, and consumer
    # issue registers add fixed ready/valid latency. Pin the resulting monitor
    # count so later latency drift cannot be mistaken for equivalence.
    if ($checks -ne 12446067) { throw "unexpected_check_count_$checks" }
    if ($denseBytes -ne 2101088) { throw "unexpected_dense_bytes_$denseBytes" }
    if ($sparseBytes -ne 1052208) { throw "unexpected_sparse_bytes_$sparseBytes" }

    $xsimLogSha256 = (Get-FileHash -LiteralPath $xsimLog -Algorithm SHA256).Hash.ToLowerInvariant()
    $failureDetail = "none"
    $finishedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

    Publish-AtomicFile -Source $resolvedPath -Destination $fixedEvidence.resolved
    Publish-AtomicFile -Source $xvlogLog -Destination $fixedEvidence.xvlog
    Publish-AtomicFile -Source $xelabLog -Destination $fixedEvidence.xelab
    Publish-AtomicFile -Source $xsimConsole -Destination $fixedEvidence.console
    Publish-AtomicFile -Source $xsimLog -Destination $fixedEvidence.xsim

    $cleanupDetail = "workdir_retained"
    if (-not $KeepWork) {
        try {
            Remove-Item -LiteralPath $workDir -Recurse -Force
            $cleanupDetail = "workdir_removed"
        }
        catch {
            $cleanupDetail = "workdir_cleanup_failed:$(Clean-OneLine -Text $_.Exception.Message)"
        }
    }

    Write-AtomicText -Path $summaryPath -Lines @(
        "checkpoint=CP6",
        "evidence_type=Vivado_2018.3_XSim",
        "design_scope=CP5_isolated_connected_subsystem",
        "top=tb_sequential_v4_sparse_memory_subsystem",
        "run_id=$runId",
        "started_utc=$startedUtc",
        "finished_utc=$finishedUtc",
        "accelerator_top_included=0",
        "project_source_count=$($sourcePaths.Count)",
        "tool_library=unisims_ver",
        "tool_library_is_project_source=0",
        "global_module=glbl",
        "global_module_source=tb/cp6_xsim_glbl.v",
        "runtime_image_copy=parameters_v4.bin",
        "resolved_inputs_sha256=$inputSetSha256",
        "runner_sha256=$runnerSha256",
        "source_hash_stable=$sourceHashStable",
        "runner_hash_stable=$runnerHashStable",
        "xsim_log_sha256=$xsimLogSha256",
        "xvlog_exit=$xvlogExit",
        "xelab_exit=$xelabExit",
        "xsim_exit=$xsimExit",
        "pass_signature_count=$passSignatureCount",
        "fail_or_fatal_signature_count=$failureSignatureCount",
        "checks=$checks",
        "dense_bytes=$denseBytes",
        "sparse_bytes=$sparseBytes",
        "status=PASS",
        "failure_detail=$failureDetail",
        "cleanup_detail=$cleanupDetail",
        "gate_pass=1"
    )
}
catch {
    $failureDetail = Clean-OneLine -Text $_.Exception.Message
    $finishedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    Write-AtomicText -Path $summaryPath -Lines @(
        "checkpoint=CP6",
        "evidence_type=Vivado_2018.3_XSim",
        "design_scope=CP5_isolated_connected_subsystem",
        "run_id=$runId",
        "started_utc=$startedUtc",
        "finished_utc=$finishedUtc",
        "resolved_inputs_sha256=$inputSetSha256",
        "runner_sha256=$runnerSha256",
        "source_hash_stable=$sourceHashStable",
        "runner_hash_stable=$runnerHashStable",
        "xsim_log_sha256=$xsimLogSha256",
        "xvlog_exit=$xvlogExit",
        "xelab_exit=$xelabExit",
        "xsim_exit=$xsimExit",
        "pass_signature_count=$passSignatureCount",
        "fail_or_fatal_signature_count=$failureSignatureCount",
        "checks=$checks",
        "dense_bytes=$denseBytes",
        "sparse_bytes=$sparseBytes",
        "status=FAIL",
        "failure_detail=$failureDetail",
        "workdir=$workDir",
        "gate_pass=0"
    )
    throw
}

Write-Host "CP6_CP5_XSIM_PASS run_id=$runId checks=$checks dense=$denseBytes sparse=$sparseBytes"
