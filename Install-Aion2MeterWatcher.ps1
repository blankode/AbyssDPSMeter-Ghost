$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$taskName = 'AION2 - Abyss DPS Meter Watcher'
$installDir = Join-Path $env:LOCALAPPDATA 'Aion2MeterWatcher'
$meterInstallDir = Join-Path $installDir 'Meter'
$legacyMeterTarget = Join-Path $installDir 'AbyssDPSMeter.exe'
$watcherSource = Join-Path $PSScriptRoot 'Aion2MeterWatcher.ps1'
$watcherTarget = Join-Path $installDir 'Aion2MeterWatcher.ps1'
$configTarget = Join-Path $installDir 'config.json'
$latestApiUrl = 'https://api.abysslogs.com/v1/meter/latest'
$manifestUrl = 'https://cdn.meter.abysslogs.com/manifest.json'
$stagingRoot = Join-Path $env:TEMP ('Aion2MeterWatcher-' + [Guid]::NewGuid().ToString('N'))

function Write-Step {
    param([string]$Message)
    Write-Host ("[AbyssDPSMeter Ghost] {0}" -f $Message) -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host ("[AbyssDPSMeter Ghost] WARNING: {0}" -f $Message) -ForegroundColor Yellow
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

function Get-JsonValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }

    return $null
}

function Find-JsonValue {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$Depth = 0
    )

    if ($null -eq $Object -or $Depth -gt 8) {
        return $null
    }

    if ($Object -is [string] -or $Object -is [ValueType]) {
        return $null
    }

    $direct = Get-JsonValue -Object $Object -Name $Name
    if ($null -ne $direct) {
        return $direct
    }

    if ($Object -is [System.Collections.IEnumerable]) {
        foreach ($item in $Object) {
            $found = Find-JsonValue -Object $item -Name $Name -Depth ($Depth + 1)
            if ($null -ne $found) {
                return $found
            }
        }
        return $null
    }

    foreach ($property in $Object.PSObject.Properties) {
        $found = Find-JsonValue -Object $property.Value -Name $Name -Depth ($Depth + 1)
        if ($null -ne $found) {
            return $found
        }
    }

    return $null
}

function Get-ExpectedSha256 {
    param($Metadata)

    if ($null -eq $Metadata) {
        return $null
    }

    foreach ($name in @('sha256', 'sha256Hash')) {
        $value = Find-JsonValue -Object $Metadata -Name $name
        if ($null -ne $value) {
            $text = ([string]$value).Trim()
            if ($text -match '^[A-Fa-f0-9]{64}$') {
                return $text.ToLowerInvariant()
            }
        }
    }

    return $null
}

function Resolve-OfficialRelease {
    $errors = New-Object System.Collections.Generic.List[string]

    # This is the same stable API fallback embedded in the official meter.
    try {
        Write-Step 'Checking the official Abyss Logs latest-release API...'
        $apiResult = Invoke-RestMethod `
            -Uri $latestApiUrl `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -Headers @{ 'Cache-Control' = 'no-cache'; 'Accept' = 'application/json' }

        $downloadRaw = Get-JsonValue -Object $apiResult -Name 'downloadUrl'
        $version = Get-JsonValue -Object $apiResult -Name 'version'

        if (-not [string]::IsNullOrWhiteSpace([string]$downloadRaw)) {
            return [pscustomobject]@{
                DownloadUrl = [string]$downloadRaw
                Version = if ([string]::IsNullOrWhiteSpace([string]$version)) { 'unknown' } else { [string]$version }
                Metadata = $apiResult
                SourceUrl = $latestApiUrl
            }
        }

        $errors.Add("$latestApiUrl returned no downloadUrl")
    }
    catch {
        $errors.Add("$latestApiUrl failed: $($_.Exception.Message)")
    }

    # Keep the CDN manifest only as a fallback. Its schema may be nested, so
    # search recursively rather than assuming downloadUrl is at the root.
    try {
        Write-Step 'Latest-release API unavailable; trying the official CDN manifest...'
        $manifest = Invoke-RestMethod `
            -Uri $manifestUrl `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -Headers @{ 'Cache-Control' = 'no-cache'; 'Accept' = 'application/json' }

        $downloadRaw = Find-JsonValue -Object $manifest -Name 'downloadUrl'
        $version = Find-JsonValue -Object $manifest -Name 'version'

        if (-not [string]::IsNullOrWhiteSpace([string]$downloadRaw)) {
            $manifestUri = [Uri]$manifestUrl
            $resolvedUri = [Uri]::new($manifestUri, [string]$downloadRaw)

            return [pscustomobject]@{
                DownloadUrl = $resolvedUri.AbsoluteUri
                Version = if ([string]::IsNullOrWhiteSpace([string]$version)) { 'unknown' } else { [string]$version }
                Metadata = $manifest
                SourceUrl = $manifestUrl
            }
        }

        $errors.Add("$manifestUrl returned no downloadUrl")
    }
    catch {
        $errors.Add("$manifestUrl failed: $($_.Exception.Message)")
    }

    throw ("Could not resolve the current official Abyss DPS Meter release.`n  - " + ($errors -join "`n  - "))
}

function Stop-InstalledMeter {
    Get-CimInstance Win32_Process -Filter "Name='AbyssDPSMeter.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            if (-not $_.ExecutablePath) {
                return $false
            }

            $path = [string]$_.ExecutablePath
            return $path.StartsWith($installDir + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function Stop-OldWatcher {
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
}

function Find-MeterExecutable {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return $null
    }

    $candidate = Get-ChildItem -LiteralPath $Root -Filter 'AbyssDPSMeter.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq 'AbyssDPSMeter.exe' } |
        Sort-Object FullName |
        Select-Object -First 1

    if ($null -eq $candidate) {
        return $null
    }

    return $candidate.FullName
}

function Install-NsisSetup {
    param([Parameter(Mandatory = $true)][string]$SetupPath)

    Write-Step 'Installing the official NSIS package silently into LocalAppData...'

    if (Test-Path -LiteralPath $meterInstallDir) {
        Remove-Item -LiteralPath $meterInstallDir -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $meterInstallDir -Force | Out-Null

    # Wails packages Windows releases using NSIS. /S is silent mode and /D
    # overrides $INSTDIR; /D must be the final command-line parameter.
    $argumentLine = "/S /D=$meterInstallDir"
    $process = Start-Process `
        -FilePath $SetupPath `
        -ArgumentList $argumentLine `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Official Abyss DPS Meter setup exited with code $($process.ExitCode)."
    }

    $meterExe = Find-MeterExecutable -Root $meterInstallDir
    if ([string]::IsNullOrWhiteSpace([string]$meterExe)) {
        throw "The official setup completed, but AbyssDPSMeter.exe was not found under $meterInstallDir."
    }

    return $meterExe
}

function Install-PortableMeter {
    param([Parameter(Mandatory = $true)][string]$ExecutablePath)

    if (Test-Path -LiteralPath $meterInstallDir) {
        Remove-Item -LiteralPath $meterInstallDir -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $meterInstallDir -Force | Out-Null

    $destination = Join-Path $meterInstallDir 'AbyssDPSMeter.exe'
    Copy-Item -LiteralPath $ExecutablePath -Destination $destination -Force
    Unblock-File -LiteralPath $destination -ErrorAction SilentlyContinue

    return $destination
}

function Install-DownloadedPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)][string]$OriginalFileName
    )

    if (Test-ZipArchive -Path $PackagePath) {
        Write-Step 'Extracting the official release package...'
        $extractDir = Join-Path $stagingRoot 'extracted'
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

        $zipPath = Join-Path $stagingRoot 'release.zip'
        Copy-Item -LiteralPath $PackagePath -Destination $zipPath -Force
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

        $portable = Get-ChildItem -LiteralPath $extractDir -Filter 'AbyssDPSMeter.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($null -ne $portable) {
            return Install-PortableMeter -ExecutablePath $portable.FullName
        }

        $setup = Get-ChildItem -LiteralPath $extractDir -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)(setup|installer)' } |
            Select-Object -First 1

        if ($null -ne $setup) {
            return Install-NsisSetup -SetupPath $setup.FullName
        }

        throw 'The official ZIP contained neither AbyssDPSMeter.exe nor a setup executable.'
    }

    if (-not (Test-PeExecutable -Path $PackagePath)) {
        throw 'The official download is not a valid Windows executable or ZIP archive.'
    }

    if ($OriginalFileName -match '(?i)(setup|installer)\.exe$') {
        return Install-NsisSetup -SetupPath $PackagePath
    }

    return Install-PortableMeter -ExecutablePath $PackagePath
}

if (-not (Test-Path -LiteralPath $watcherSource)) {
    throw "Missing watcher script: $watcherSource"
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch {
    # Modern Windows versions already negotiate a suitable TLS version.
}

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

try {
    $release = Resolve-OfficialRelease

    $downloadUri = [Uri]$release.DownloadUrl
    if ($downloadUri.Scheme -ne 'https') {
        throw "Refusing a non-HTTPS meter download URL: $($downloadUri.AbsoluteUri)"
    }

    $meterVersion = [string]$release.Version
    $originalFileName = [System.IO.Path]::GetFileName($downloadUri.AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($originalFileName)) {
        $originalFileName = 'AbyssDPSMeter-download.exe'
    }

    Write-Step ("Latest official meter version: {0}" -f $meterVersion)
    Write-Step ("Downloading {0} from {1}..." -f $originalFileName, $downloadUri.Host)

    $packagePath = Join-Path $stagingRoot $originalFileName
    Invoke-WebRequest `
        -Uri $downloadUri.AbsoluteUri `
        -OutFile $packagePath `
        -UseBasicParsing `
        -TimeoutSec 600

    $package = Get-Item -LiteralPath $packagePath
    if ($package.Length -lt 1024) {
        throw "Downloaded package is unexpectedly small ($($package.Length) bytes)."
    }

    $expectedSha256 = Get-ExpectedSha256 -Metadata $release.Metadata
    if ($null -ne $expectedSha256) {
        Write-Step 'Verifying SHA-256 supplied by the official release metadata...'
        $actualSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualSha256 -ne $expectedSha256) {
            throw "SHA-256 verification failed. Expected $expectedSha256 but received $actualSha256."
        }
    }

    Write-Step 'Stopping the previous watcher/meter instance, if present...'
    Stop-OldWatcher
    Stop-InstalledMeter

    # Remove the v4 layout where a downloaded PE was stored directly in the
    # watcher root. Current setup releases are installed into the Meter folder.
    Remove-Item -LiteralPath $legacyMeterTarget -Force -ErrorAction SilentlyContinue

    $meterTarget = Install-DownloadedPackage `
        -PackagePath $packagePath `
        -OriginalFileName $originalFileName

    if (-not (Test-PeExecutable -Path $meterTarget)) {
        throw "Installed meter is not a valid Windows PE executable: $meterTarget"
    }

    $meterInfo = Get-Item -LiteralPath $meterTarget
    if ($meterInfo.Length -lt 524288) {
        throw "Installed AbyssDPSMeter.exe is unexpectedly small ($($meterInfo.Length) bytes)."
    }

    Write-Step 'Installing the hidden AION2 watcher...'
    Copy-Item -LiteralPath $watcherSource -Destination $watcherTarget -Force

    $config = [ordered]@{
        MeterPath = $meterTarget
        MeterVersion = $meterVersion
        MeterReleaseApiUrl = $latestApiUrl
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
    Write-Host "Release metadata: $($release.SourceUrl)"
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
