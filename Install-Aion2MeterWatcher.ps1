$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$taskName = 'AION2 - Abyss DPS Meter Watcher'
$installDir = Join-Path $env:LOCALAPPDATA 'Aion2MeterWatcher'
$watcherSource = Join-Path $PSScriptRoot 'Aion2MeterWatcher.ps1'
$watcherTarget = Join-Path $installDir 'Aion2MeterWatcher.ps1'
$meterTarget = Join-Path $installDir 'AbyssDPSMeter.exe'
$configTarget = Join-Path $installDir 'config.json'
$manifestUrl = 'https://cdn.meter.abysslogs.com/manifest.json'
$stagingRoot = Join-Path $env:TEMP ('Aion2MeterWatcher-' + [Guid]::NewGuid().ToString('N'))

function Write-Step {
    param([string]$Message)
    Write-Host ("[AbyssDPSMeter Ghost] {0}" -f $Message) -ForegroundColor Cyan
}

function Test-PeExecutable {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 2) {
            return $false
        }

        return ($stream.ReadByte() -eq 0x4D -and $stream.ReadByte() -eq 0x5A)
    }
    finally {
        $stream.Dispose()
    }
}

function Test-ZipArchive {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 2) {
            return $false
        }

        return ($stream.ReadByte() -eq 0x50 -and $stream.ReadByte() -eq 0x4B)
    }
    finally {
        $stream.Dispose()
    }
}

function Get-ManifestValue {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $Manifest.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-ExpectedSha256 {
    param([Parameter(Mandatory = $true)]$Manifest)

    foreach ($name in @('sha256', 'sha256Hash', 'checksum', 'hash')) {
        $value = Get-ManifestValue -Manifest $Manifest -Name $name
        if ($null -ne $value) {
            $text = ([string]$value).Trim()
            if ($text -match '^[A-Fa-f0-9]{64}$') {
                return $text.ToLowerInvariant()
            }
        }
    }

    return $null
}

function Stop-InstalledMeter {
    if (-not (Test-Path -LiteralPath $meterTarget)) {
        return
    }

    Get-CimInstance Win32_Process -Filter "Name='AbyssDPSMeter.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            [string]::Equals($_.ExecutablePath, $meterTarget, [System.StringComparison]::OrdinalIgnoreCase)
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

if (-not (Test-Path -LiteralPath $watcherSource)) {
    throw "Missing watcher script: $watcherSource"
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch {
    # Windows 11 already negotiates a modern TLS version; keep going if this compatibility hint is unavailable.
}

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

try {
    Write-Step 'Checking the official Abyss Logs release manifest...'
    $manifest = Invoke-RestMethod -Uri $manifestUrl -UseBasicParsing -Headers @{ 'Cache-Control' = 'no-cache' }

    $downloadRaw = Get-ManifestValue -Manifest $manifest -Name 'downloadUrl'
    if ([string]::IsNullOrWhiteSpace([string]$downloadRaw)) {
        throw "The official manifest did not contain a downloadUrl: $manifestUrl"
    }

    $manifestUri = [Uri]$manifestUrl
    $downloadUri = New-Object System.Uri($manifestUri, [string]$downloadRaw)
    if ($downloadUri.Scheme -ne 'https') {
        throw "Refusing a non-HTTPS meter download URL: $($downloadUri.AbsoluteUri)"
    }

    $meterVersion = Get-ManifestValue -Manifest $manifest -Name 'version'
    if ([string]::IsNullOrWhiteSpace([string]$meterVersion)) {
        $meterVersion = 'unknown'
    }

    Write-Step ("Latest official meter version: {0}" -f $meterVersion)
    Write-Step ("Downloading from {0}..." -f $downloadUri.Host)

    $packagePath = Join-Path $stagingRoot 'meter-download.bin'
    Invoke-WebRequest -Uri $downloadUri.AbsoluteUri -OutFile $packagePath -UseBasicParsing

    $package = Get-Item -LiteralPath $packagePath
    if ($package.Length -lt 1024) {
        throw "Downloaded package is unexpectedly small ($($package.Length) bytes)."
    }

    $expectedSha256 = Get-ExpectedSha256 -Manifest $manifest
    if ($null -ne $expectedSha256) {
        Write-Step 'Verifying SHA-256 from the official manifest...'
        $actualSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualSha256 -ne $expectedSha256) {
            throw "SHA-256 verification failed. Expected $expectedSha256 but received $actualSha256."
        }
    }

    $candidateExe = $null

    if (Test-ZipArchive -Path $packagePath) {
        Write-Step 'Extracting the official meter package...'
        $zipPath = Join-Path $stagingRoot 'AbyssDPSMeter.zip'
        Move-Item -LiteralPath $packagePath -Destination $zipPath -Force

        $extractDir = Join-Path $stagingRoot 'extracted'
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

        $candidateExe = Get-ChildItem -LiteralPath $extractDir -Filter 'AbyssDPSMeter.exe' -File -Recurse |
            Select-Object -First 1

        if ($null -eq $candidateExe) {
            throw 'The official ZIP did not contain AbyssDPSMeter.exe.'
        }

        $candidateExe = $candidateExe.FullName
    }
    elseif (Test-PeExecutable -Path $packagePath) {
        $candidateExe = $packagePath
    }
    else {
        throw 'The official download was neither a Windows executable nor a ZIP archive.'
    }

    if (-not (Test-PeExecutable -Path $candidateExe)) {
        throw 'The extracted AbyssDPSMeter.exe is not a valid Windows PE executable.'
    }

    $candidateInfo = Get-Item -LiteralPath $candidateExe
    if ($candidateInfo.Length -lt 524288) {
        throw "AbyssDPSMeter.exe is unexpectedly small ($($candidateInfo.Length) bytes)."
    }

    Write-Step 'Stopping the previous watcher/meter instance, if present...'
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^powershell(\.exe)?$' -and
            $_.CommandLine -like '*Aion2MeterWatcher.ps1*'
        } |
        ForEach-Object {
            if ($_.ProcessId -ne $PID) {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }

    Stop-InstalledMeter

    Write-Step 'Installing AbyssDPSMeter.exe into LocalAppData...'
    Copy-Item -LiteralPath $candidateExe -Destination $meterTarget -Force
    Unblock-File -LiteralPath $meterTarget -ErrorAction SilentlyContinue

    Copy-Item -LiteralPath $watcherSource -Destination $watcherTarget -Force

    $config = [ordered]@{
        MeterPath = $meterTarget
        MeterVersion = [string]$meterVersion
        MeterManifestUrl = $manifestUrl
        GameProcessName = 'AION2'
        HideFromTaskbar = $true
        StopMeterWhenGameExits = $true
        PollMilliseconds = 350
    }
    $config | ConvertTo-Json | Set-Content -LiteralPath $configTarget -Encoding UTF8

    $powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watcherTarget`" -ConfigPath `"$configTarget`""

    $action = New-ScheduledTaskAction -Execute $powerShellExe -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
    Start-ScheduledTask -TaskName $taskName

    Write-Host ''
    Write-Host 'Installed successfully.' -ForegroundColor Green
    Write-Host "Official meter version: $meterVersion"
    Write-Host "Meter: $meterTarget"
    Write-Host "Watcher: $watcherTarget"
    Write-Host "Task: $taskName"
    Write-Host ''
    Write-Host 'You can now delete the folder you ran Install.cmd from.' -ForegroundColor Green
    Write-Host 'Everything required at runtime is stored under:'
    Write-Host "  $installDir"
    Write-Host ''
    Write-Host 'Behavior:'
    Write-Host '  - Starts Abyss DPS Meter automatically when AION2.exe is detected.'
    Write-Host '  - Watcher itself runs hidden.'
    Write-Host '  - Removes Abyss DPS Meter windows from the Windows taskbar.'
    Write-Host '  - Stops Abyss DPS Meter automatically when AION2.exe is no longer running.'
    Write-Host ''
    Write-Host "Config: $configTarget"
}
finally {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
}
