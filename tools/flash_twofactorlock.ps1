[CmdletBinding()]
param(
    [string]$Port = 'COM4',
    [int]$Baud = 115200,
    [ValidateSet('bootloader','arduino-as-isp')]
    [string]$Mode = 'bootloader'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$asmDir = Join-Path $repoRoot 'arduino\TwoFactorLock\AssemblerApplication1'
$asmFile = Join-Path $asmDir 'main_final_real_lock.asm'
$hexFile = Join-Path $asmDir 'main_final_real_lock.hex'

if (-not (Test-Path -LiteralPath $asmFile)) {
    throw "ASM not found: $asmFile"
}

function Resolve-ToolPath(
    [Parameter(Mandatory=$true)][string]$name,
    [Parameter(Mandatory=$true)][string[]]$candidates,
    [Parameter(Mandatory=$true)][string]$hint
) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Path) {
        return $cmd.Path
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    throw "Missing '$name'. $hint"
}

$avrdudePath = Resolve-ToolPath -name 'avrdude' -candidates @(
    'C:\\msys64\\ucrt64\\bin\\avrdude.exe',
    'C:\\msys64\\usr\\bin\\avrdude.exe'
) -hint "Install via MSYS2: pacman -S mingw-w64-ucrt-x86_64-avrdude"

$avraCmd = Get-Command 'avra' -ErrorAction SilentlyContinue
$avraPath = if ($avraCmd) { $avraCmd.Path } else { $null }
$avrasm2Path = Resolve-ToolPath -name 'avrasm2' -candidates @(
    "${env:ProgramFiles(x86)}\\Atmel\\Studio\\7.0\\toolchain\\avr8\\avrassembler\\avrasm2.exe",
    "${env:ProgramFiles(x86)}\\Microchip\\Studio\\7.0\\toolchain\\avr8\\avrassembler\\avrasm2.exe",
    "${env:ProgramFiles}\\Microchip\\Studio\\7.0\\toolchain\\avr8\\avrassembler\\avrasm2.exe"
) -hint "Install Microchip/Atmel AVR assembler (avrasm2.exe) or provide 'avra' on PATH"

$includeDirs = New-Object System.Collections.Generic.List[string]
$includeDirs.Add($asmDir)

# Try to locate m328Pdef.inc from installed device packs (fast path)
$dfpRoots = @(
    "${env:ProgramFiles(x86)}\\Atmel\\Studio\\7.0\\Packs\\atmel\\ATmega_DFP",
    "${env:ProgramFiles(x86)}\\Microchip\\Studio\\Packs\\atmel\\ATmega_DFP",
    "${env:ProgramFiles}\\Microchip\\Studio\\Packs\\atmel\\ATmega_DFP"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

foreach ($root in $dfpRoots) {
    $incFile = Get-ChildItem -Path $root -Recurse -Filter 'm328Pdef.inc' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($incFile) {
        $includeDirs.Add($incFile.Directory.FullName)
        break
    }
}

# Extra common include locations (no-op if missing)
foreach ($p in @(
    'C:\\msys64\\ucrt64\\share\\avra',
    'C:\\msys64\\ucrt64\\share\\avra\\include',
    'C:\\msys64\\ucrt64\\share\\avra\\inc'
)) {
    if (Test-Path -LiteralPath $p) { $includeDirs.Add($p) }
}

$includeCandidates = $includeDirs | Select-Object -Unique

Write-Host "[1/2] Assembling -> $hexFile"
if ($avraPath) {
    $avraArgs = @()
    foreach ($inc in $includeCandidates) { $avraArgs += @('-I', $inc) }
    $avraArgs += @('-o', $hexFile, $asmFile)
    & $avraPath @avraArgs
    if ($LASTEXITCODE -ne 0) { throw "avra failed with exit code $LASTEXITCODE" }
} else {
    $listFile = [System.IO.Path]::ChangeExtension($hexFile, '.lss')
    $mapFile = [System.IO.Path]::ChangeExtension($hexFile, '.map')

    $asmArgs = @('-fI', '-o', $hexFile, '-l', $listFile, '-m', $mapFile)
    foreach ($inc in $includeCandidates) { $asmArgs += @('-I', $inc) }
    $asmArgs += @($asmFile)

    & $avrasm2Path @asmArgs
    if ($LASTEXITCODE -ne 0) { throw "avrasm2 failed with exit code $LASTEXITCODE" }
}
if (-not (Test-Path -LiteralPath $hexFile)) { throw "HEX not created: $hexFile" }

Write-Host "[2/2] Flashing $hexFile to ATmega328P on $Port ($Mode)"

function Get-UsbPortFromCom([string]$comPort) {
    try {
        $sp = Get-CimInstance Win32_SerialPort -ErrorAction Stop | Where-Object { $_.DeviceID -eq $comPort } | Select-Object -First 1
        if (-not $sp -or -not $sp.PNPDeviceID) { return $null }

        $mVid = [regex]::Match($sp.PNPDeviceID, 'VID_([0-9A-Fa-f]{4})')
        $mPid = [regex]::Match($sp.PNPDeviceID, 'PID_([0-9A-Fa-f]{4})')
        if (-not $mVid.Success -or -not $mPid.Success) { return $null }

        $vid = $mVid.Groups[1].Value.ToLowerInvariant()
        $pid = $mPid.Groups[1].Value.ToLowerInvariant()
        return "usb:${vid}:${pid}"
    } catch {
        return $null
    }
}

function Invoke-Avrdude([string]$programmer, [string]$portArg, [int]$baudArg) {
    $args = @('-c', $programmer, '-p', 'm328p', '-P', $portArg, '-D', '-U', ("flash:w:{0}:i" -f $hexFile))
    if ($baudArg -gt 0) {
        $args = @('-b', "$baudArg") + $args
    }
    & $avrdudePath @args
    return $LASTEXITCODE
}

$programmer = switch ($Mode) {
    'bootloader' { 'arduino' }
    'arduino-as-isp' { 'stk500v1' }
}

$attempts = New-Object System.Collections.Generic.List[hashtable]
$attempts.Add(@{ Port = $Port; Baud = $Baud })

if ($Mode -eq 'bootloader' -and $Baud -eq 115200) {
    # Some Uno clones use the old bootloader speed.
    $attempts.Add(@{ Port = $Port; Baud = 57600 })
}

if ($Port -match '^COM\d+$') {
    $usbPort = Get-UsbPortFromCom $Port
    if ($usbPort) {
        $attempts.Add(@{ Port = $usbPort; Baud = $Baud })
        if ($Mode -eq 'bootloader' -and $Baud -eq 115200) {
            $attempts.Add(@{ Port = $usbPort; Baud = 57600 })
        }
    }
}

$lastExit = 1
foreach ($attempt in $attempts) {
    Write-Host "Trying avrdude: -c $programmer -P $($attempt.Port) -b $($attempt.Baud)"
    $lastExit = Invoke-Avrdude -programmer $programmer -portArg $attempt.Port -baudArg $attempt.Baud
    if ($lastExit -eq 0) {
        Write-Host "Upload OK."
        break
    }
    Write-Host "Upload failed (exit $lastExit)."
}

if ($lastExit -ne 0) {
    throw "avrdude failed (exit $lastExit). If COM4 is correct, close Arduino Serial Monitor/IDE (port busy) and retry."
}

Write-Host "Done."