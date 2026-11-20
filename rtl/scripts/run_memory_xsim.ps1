[CmdletBinding()]
param(
    [string]$VivadoBin = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($VivadoBin)) {
    if ($env:XILINX_VIVADO) {
        $VivadoBin = Join-Path $env:XILINX_VIVADO "bin"
    } else {
        $VivadoBin = "C:\Xilinx\Vivado\2018.3\bin"
    }
}

$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Vivado simulator tool not found: $tool"
    }
}

$rtlRoot = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Path (Join-Path $rtlRoot "build") -Force | Out-Null
Push-Location $rtlRoot
try {
    & $xvlog --sv memory/memory.v tb/tb_memory.v
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog failed with exit code $LASTEXITCODE"
    }

    & $xelab tb_memory -s tb_memory_sim --debug typical
    if ($LASTEXITCODE -ne 0) {
        throw "xelab failed with exit code $LASTEXITCODE"
    }

    & $xsim tb_memory_sim -runall
    if ($LASTEXITCODE -ne 0) {
        throw "xsim failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
