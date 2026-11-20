param(
    [string]$VivadoBin = "C:\Xilinx\Vivado\2018.3\bin"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$rtlRoot = Join-Path $repoRoot "rtl"
$workRoot = Join-Path $env:TEMP "zephyr_hybrid_pe_deepfilter_equivalence_$PID"

$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Missing Vivado simulator tool: $tool"
    }
}

$sources = @(
    (Join-Path $rtlRoot "leaf\deepfilter_complex_mac.v"),
    (Join-Path $rtlRoot "integration\sequential_deepfilter_engine.v"),
    (Join-Path $rtlRoot "integration\hybrid_pe_deepfilter_controller.v"),
    (Join-Path $rtlRoot "pe_array\rtl\pe\pe_cdf_sequencer.v"),
    (Join-Path $rtlRoot "pe_array\rtl\pe\pe_hybrid_mac.sv"),
    (Join-Path $rtlRoot "tb\tb_hybrid_pe_deepfilter_equivalence.sv")
)
foreach ($source in $sources) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing Hybrid-PE DeepFilter equivalence input: $source"
    }
}

New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
Push-Location $workRoot
try {
    & $xvlog --sv @sources
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed with exit code $LASTEXITCODE"
    }

    & $xelab tb_hybrid_pe_deepfilter_equivalence `
        -s tb_hybrid_pe_deepfilter_equivalence_sim
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed with exit code $LASTEXITCODE"
    }

    & $xsim tb_hybrid_pe_deepfilter_equivalence_sim -runall -log xsim.log
    if ($LASTEXITCODE -ne 0) {
        throw "xsim failed with exit code $LASTEXITCODE"
    }

    $passMarker = "PASS tb_hybrid_pe_deepfilter_equivalence frames=5 checks=1305"
    if (-not (Select-String -LiteralPath "xsim.log" -SimpleMatch $passMarker -Quiet)) {
        throw "XSim completed without the expected pass marker"
    }

    Write-Output "HYBRID_PE_DEEPFILTER_EQUIVALENCE_XSIM_PASS"
    Write-Output "xsim_log=$workRoot\xsim.log"
}
finally {
    Pop-Location
}
