[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("service", "subsystem")]
    [string]$Flow,
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

function Resolve-IsolatedFile {
    param(
        [Parameter(Mandatory = $true)][string]$SparseRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )
    $item = Get-Item -LiteralPath (Join-Path $SparseRoot $RelativePath) -Force
    if ($item.PSIsContainer) {
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
        throw "CP6_ISOLATION_FAIL: input escaped sparse_memory_v1: $($item.FullName)"
    }
    return $item.FullName
}

function Invoke-LoggedNative {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$LogPath
    )
    # Windows PowerShell wraps any native stderr line as a non-terminating
    # NativeCommandError. Vivado emits a benign cpuprofiler notice on stderr,
    # so capture all streams without allowing that notice to bypass the real
    # process exit-code gate.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $Executable @Arguments *> $LogPath
        $nativeExit = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    return $nativeExit
}

function Read-KeyValueSummary {
    param([Parameter(Mandatory = $true)][string]$Path)
    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^([^=]+)=(.*)$') {
            $values[$Matches[1]] = $Matches[2]
        }
    }
    return $values
}

function Require-SummaryValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Values,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Expected
    )
    if (-not $Values.ContainsKey($Key)) {
        throw "missing_summary_key_$Key"
    }
    if ($Values[$Key] -cne $Expected) {
        throw "unexpected_summary_${Key}_$($Values[$Key])"
    }
}

function Clean-OneLine {
    param([Parameter(Mandatory = $true)][string]$Text)
    return $Text.Replace("`r", " ").Replace("`n", " ")
}

$launcherPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Parent $launcherPath
$sparseRoot = (Get-Item -LiteralPath (Join-Path $scriptDir "..") -Force).FullName
$reportDir = Join-Path $sparseRoot "reports\cp6"
$buildRoot = Join-Path $sparseRoot "build"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

if ($Flow -eq "service") {
    $tclRelative = "scripts\run_cp6_service_ooc.tcl"
    $flowSummaryName = "cp6_service_ooc_summary.txt"
    $consoleName = "cp6_service_ooc_vivado_console.txt"
    $launcherSummaryName = "cp6_service_ooc_launcher_summary.txt"
    $gateSignature = "CP6_SERVICE_OOC_GATE_PASS"
    $shortFlow = "s"
}
else {
    $tclRelative = "scripts\run_cp6_subsystem_route.tcl"
    $flowSummaryName = "cp6_subsystem_ooc_summary.txt"
    $consoleName = "cp6_subsystem_ooc_vivado_console.txt"
    $launcherSummaryName = "cp6_subsystem_ooc_launcher_summary.txt"
    $gateSignature = "CP6_SUBSYSTEM_OOC_GATE_PASS"
    $shortFlow = "u"
}

$shortStamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
$runId = "${Flow}_vivado_${shortStamp}_$PID"
$startedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$workDir = Join-Path $buildRoot "c6v${shortFlow}_${shortStamp}_$PID"
$flowSummaryPath = Join-Path $reportDir $flowSummaryName
$fixedConsolePath = Join-Path $reportDir $consoleName
$launcherSummaryPath = Join-Path $reportDir $launcherSummaryName

# Invalidate both the launcher and flow summaries before any old console is
# removed.  A failed startup therefore cannot leave an earlier PASS visible.
Write-AtomicText -Path $launcherSummaryPath -Lines @(
    "checkpoint=CP6",
    "run_id=$runId",
    "flow=$Flow",
    "started_utc=$startedUtc",
    "status=IN_PROGRESS",
    "gate_pass=0",
    "failure_detail=run_not_completed"
)
Write-AtomicText -Path $flowSummaryPath -Lines @(
    "checkpoint=CP6",
    "launcher_run_id=$runId",
    "started_utc=$startedUtc",
    "status=IN_PROGRESS",
    "gate_pass=0",
    "failure_detail=vivado_not_started"
)
if (Test-Path -LiteralPath $fixedConsolePath) {
    Remove-Item -LiteralPath $fixedConsolePath -Force
}

$nativeExit = -1
$passSignatureCount = -1
$failureSignatureCount = -1
$flowSummarySha256 = "NA"
$consoleSha256 = "NA"
$tclHashStable = 0
$launcherHashStable = 0
$innerRunId = "NA"
$failureDetail = "runner_not_completed"
$cleanupDetail = "workdir_retained_after_failure"
$finishedUtc = "NA"
$tclSha256 = "NA"
$launcherSha256 = (Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash.ToLowerInvariant()

try {
    New-Item -ItemType Directory -Path $workDir | Out-Null
    $tclPath = Resolve-IsolatedFile -SparseRoot $sparseRoot -RelativePath $tclRelative
    $tclSha256 = (Get-FileHash -LiteralPath $tclPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $vivado = (Get-Item -LiteralPath (Join-Path $VivadoBin "vivado.bat") -Force).FullName
    $consolePath = Join-Path $workDir "vivado_console.txt"

    Push-Location $workDir
    try {
        $nativeExit = Invoke-LoggedNative -Executable $vivado -Arguments @(
            "-mode", "batch", "-nojournal", "-nolog", "-notrace",
            "-source", $tclPath
        ) -LogPath $consolePath
    }
    finally {
        Pop-Location
    }
    if ($nativeExit -ne 0) { throw "vivado_exit_$nativeExit" }
    if (-not (Test-Path -LiteralPath $flowSummaryPath -PathType Leaf)) {
        throw "flow_summary_missing"
    }

    $summaryValues = Read-KeyValueSummary -Path $flowSummaryPath
    Require-SummaryValue -Values $summaryValues -Key "status" -Expected "PASS"
    Require-SummaryValue -Values $summaryValues -Key "gate_pass" -Expected "1"
    Require-SummaryValue -Values $summaryValues -Key "vivado_version" -Expected "2018.3"
    Require-SummaryValue -Values $summaryValues -Key "part" -Expected "xc7z020clg400-1"
    Require-SummaryValue -Values $summaryValues -Key "target_frequency_mhz" -Expected "100"
    Require-SummaryValue -Values $summaryValues -Key "source_hash_stable" -Expected "1"
    Require-SummaryValue -Values $summaryValues -Key "runner_hash_stable" -Expected "1"
    Require-SummaryValue -Values $summaryValues -Key "runner_sha256" -Expected $tclSha256
    if (-not $summaryValues.ContainsKey("run_id")) { throw "missing_summary_key_run_id" }
    $innerRunId = $summaryValues["run_id"]
    $flowSummarySha256 = (Get-FileHash -LiteralPath $flowSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $consoleText = [IO.File]::ReadAllText($consolePath)
    $passSignatureCount = [regex]::Matches(
        $consoleText, "(?m)^$([regex]::Escape($gateSignature))\s*$"
    ).Count
    $failureSignatureCount = [regex]::Matches(
        $consoleText, '(?im)^CP6_(?:SERVICE|SUBSYSTEM)_OOC_GATE_FAIL\b'
    ).Count
    if ($passSignatureCount -ne 1) {
        throw "pass_signature_count_$passSignatureCount"
    }
    if ($failureSignatureCount -ne 0) {
        throw "failure_signature_count_$failureSignatureCount"
    }

    $postTclSha256 = (Get-FileHash -LiteralPath $tclPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $postLauncherSha256 = (Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $tclHashStable = [int]($postTclSha256 -eq $tclSha256)
    $launcherHashStable = [int]($postLauncherSha256 -eq $launcherSha256)
    if (-not $tclHashStable) { throw "tcl_hash_changed_during_run" }
    if (-not $launcherHashStable) { throw "launcher_hash_changed_during_run" }

    $consoleSha256 = (Get-FileHash -LiteralPath $consolePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Publish-AtomicFile -Source $consolePath -Destination $fixedConsolePath
    $failureDetail = "none"
    $finishedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

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

    Write-AtomicText -Path $launcherSummaryPath -Lines @(
        "checkpoint=CP6",
        "evidence_type=Vivado_2018.3_native_launcher",
        "flow=$Flow",
        "run_id=$runId",
        "inner_run_id=$innerRunId",
        "started_utc=$startedUtc",
        "finished_utc=$finishedUtc",
        "workdir_policy=sparse_memory_v1/build",
        "vivado_nojournal=1",
        "vivado_nolog=1",
        "vivado_notrace=1",
        "native_exit=$nativeExit",
        "pass_signature_count=$passSignatureCount",
        "failure_signature_count=$failureSignatureCount",
        "tcl_sha256=$tclSha256",
        "launcher_sha256=$launcherSha256",
        "flow_summary_sha256=$flowSummarySha256",
        "console_sha256=$consoleSha256",
        "tcl_hash_stable=$tclHashStable",
        "launcher_hash_stable=$launcherHashStable",
        "status=PASS",
        "failure_detail=$failureDetail",
        "cleanup_detail=$cleanupDetail",
        "gate_pass=1"
    )
}
catch {
    $failureDetail = Clean-OneLine -Text $_.Exception.Message
    $finishedUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    if (Test-Path -LiteralPath $flowSummaryPath -PathType Leaf) {
        try {
            if ($flowSummarySha256 -eq "NA") {
                $flowSummarySha256 = (Get-FileHash -LiteralPath $flowSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            if (Test-Path -LiteralPath $workDir -PathType Container) {
                Copy-Item -LiteralPath $flowSummaryPath -Destination `
                    (Join-Path $workDir "flow_summary_before_invalidation.txt") -Force
            }
        }
        catch {
            # The INVALIDATED marker remains authoritative even if preserving
            # the prior diagnostic copy fails.
        }
    }
    Write-AtomicText -Path $flowSummaryPath -Lines @(
        "checkpoint=CP6",
        "launcher_run_id=$runId",
        "started_utc=$startedUtc",
        "finished_utc=$finishedUtc",
        "status=INVALIDATED",
        "gate_pass=0",
        "failure_detail=$failureDetail",
        "prior_flow_summary_sha256=$flowSummarySha256",
        "workdir=$workDir"
    )
    Write-AtomicText -Path $launcherSummaryPath -Lines @(
        "checkpoint=CP6",
        "evidence_type=Vivado_2018.3_native_launcher",
        "flow=$Flow",
        "run_id=$runId",
        "inner_run_id=$innerRunId",
        "started_utc=$startedUtc",
        "finished_utc=$finishedUtc",
        "workdir_policy=sparse_memory_v1/build",
        "vivado_nojournal=1",
        "vivado_nolog=1",
        "vivado_notrace=1",
        "native_exit=$nativeExit",
        "pass_signature_count=$passSignatureCount",
        "failure_signature_count=$failureSignatureCount",
        "tcl_sha256=$tclSha256",
        "launcher_sha256=$launcherSha256",
        "flow_summary_sha256=$flowSummarySha256",
        "console_sha256=$consoleSha256",
        "tcl_hash_stable=$tclHashStable",
        "launcher_hash_stable=$launcherHashStable",
        "status=FAIL",
        "failure_detail=$failureDetail",
        "workdir=$workDir",
        "gate_pass=0"
    )
    throw
}

Write-Host "CP6_VIVADO_OOC_PASS flow=$Flow run_id=$runId inner_run_id=$innerRunId"
