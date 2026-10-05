$ErrorActionPreference = 'Stop'

$taskName = 'AION2 - Abyss DPS Meter Watcher'
$installDir = Join-Path $env:LOCALAPPDATA 'Aion2MeterWatcher'
$watcherSource = Join-Path $PSScriptRoot 'Aion2MeterWatcher.ps1'
$watcherTarget = Join-Path $installDir 'Aion2MeterWatcher.ps1'
$configTarget = Join-Path $installDir 'config.json'

if (-not (Test-Path -LiteralPath $watcherSource)) {
    throw "Missing watcher script: $watcherSource"
}

$meterPath = Join-Path $PSScriptRoot 'AbyssDPSMeter.exe'
if (-not (Test-Path -LiteralPath $meterPath)) {
    throw "AbyssDPSMeter.exe was not found next to this installer. Keep the executable named exactly AbyssDPSMeter.exe and run Install.cmd again."
}
$meter = Get-Item -LiteralPath $meterPath

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item -LiteralPath $watcherSource -Destination $watcherTarget -Force

$config = [ordered]@{
    MeterPath = $meter.FullName
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

# Replace any previous installation cleanly.
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $taskName

Write-Host ''
Write-Host 'Installed successfully.' -ForegroundColor Green
Write-Host "Meter: $($meter.FullName)"
Write-Host "Watcher: $watcherTarget"
Write-Host "Task: $taskName"
Write-Host ''
Write-Host 'Behavior:'
Write-Host '  - Starts Abyss DPS Meter automatically when AION2.exe is detected.'
Write-Host '  - Watcher itself runs hidden.'
Write-Host '  - Removes Abyss DPS Meter windows from the Windows taskbar.'
Write-Host '  - Stops Abyss DPS Meter automatically when AION2.exe is no longer running.'
Write-Host ''
Write-Host "Config: $configTarget"
