$ErrorActionPreference = 'SilentlyContinue'
$taskName = 'AION2 - Abyss DPS Meter Watcher'
$installDir = Join-Path $env:LOCALAPPDATA 'Aion2MeterWatcher'

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

Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'AION2 meter watcher removed.' -ForegroundColor Green
Write-Host 'The Abyss DPS Meter executable itself was not deleted.'
