$ErrorActionPreference = 'SilentlyContinue'
$taskName = 'AION2 - Abyss DPS Meter Watcher'
$installDir = Join-Path $env:LOCALAPPDATA 'Aion2MeterWatcher'
$meterPath = Join-Path $installDir 'AbyssDPSMeter.exe'

Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Get-CimInstance Win32_Process |
    Where-Object {
        $_.Name -match '^powershell(\.exe)?$' -and
        $_.CommandLine -like '*Aion2MeterWatcher.ps1*'
    } |
    ForEach-Object {
        if ($_.ProcessId -ne $PID) {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }

Get-CimInstance Win32_Process -Filter "Name='AbyssDPSMeter.exe'" |
    Where-Object {
        $_.ExecutablePath -and
        [string]::Equals($_.ExecutablePath, $meterPath, [System.StringComparison]::OrdinalIgnoreCase)
    } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

Start-Sleep -Milliseconds 250
Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'AbyssDPSMeter Ghost removed.' -ForegroundColor Green
Write-Host "Removed runtime files from: $installDir"
