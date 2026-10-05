param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    exit 2
}

$configLastWriteUtc = [datetime]::MinValue
$meterPath = ''
$gameProcessName = 'AION2'
$hideFromTaskbar = $true
$stopWithGame = $false
$pollMilliseconds = 350

function Load-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return $false
    }

    try {
        $item = Get-Item -LiteralPath $ConfigPath -ErrorAction Stop
        if ($item.LastWriteTimeUtc -eq $script:configLastWriteUtc -and $script:meterPath) {
            return $false
        }

        $config = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $script:meterPath = [string]$config.MeterPath
        $script:gameProcessName = if ($config.GameProcessName) { [string]$config.GameProcessName } else { 'AION2' }
        $script:hideFromTaskbar = if ($null -ne $config.HideFromTaskbar) { [bool]$config.HideFromTaskbar } else { $true }
        $script:stopWithGame = if ($null -ne $config.StopMeterWhenGameExits) { [bool]$config.StopMeterWhenGameExits } else { $false }
        $script:pollMilliseconds = if ($config.PollMilliseconds) { [int]$config.PollMilliseconds } else { 350 }
        $script:configLastWriteUtc = $item.LastWriteTimeUtc
        return $true
    }
    catch {
        return $false
    }
}

[void](Load-Config)

$logPath = Join-Path $PSScriptRoot 'watcher.log'

function Write-Log([string]$Message) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') | $Message"
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class TaskbarWindowHider
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    private const int GWL_EXSTYLE = -20;
    private const long WS_EX_TOOLWINDOW = 0x00000080L;
    private const long WS_EX_APPWINDOW  = 0x00040000L;

    private const uint SWP_NOSIZE       = 0x0001;
    private const uint SWP_NOMOVE       = 0x0002;
    private const uint SWP_NOZORDER     = 0x0004;
    private const uint SWP_NOACTIVATE   = 0x0010;
    private const uint SWP_FRAMECHANGED = 0x0020;

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags
    );

    public static int HideWindowsForProcess(int processId)
    {
        int changed = 0;

        EnumWindows(delegate (IntPtr hWnd, IntPtr lParam)
        {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid != (uint)processId)
                return true;

            long exStyle = GetWindowLongPtr64(hWnd, GWL_EXSTYLE).ToInt64();
            long newStyle = (exStyle & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW;

            if (newStyle != exStyle)
            {
                SetWindowLongPtr64(hWnd, GWL_EXSTYLE, new IntPtr(newStyle));
                SetWindowPos(
                    hWnd,
                    IntPtr.Zero,
                    0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED
                );
                changed++;
            }

            return true;
        }, IntPtr.Zero);

        return changed;
    }
}
'@

function Get-GameRunning {
    return $null -ne (Get-Process -Name $gameProcessName -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-MeterProcesses {
    # Track only the configured executable. With the standard setup this is
    # exactly AbyssDPSMeter.exe / process name AbyssDPSMeter.
    $exactName = [System.IO.Path]::GetFileNameWithoutExtension($meterPath)
    return @(Get-Process -Name $exactName -ErrorAction SilentlyContinue)
}

function Start-Meter {
    if (-not (Test-Path -LiteralPath $meterPath)) {
        Write-Log "Meter executable not found: $meterPath"
        return
    }

    try {
        $p = Start-Process -FilePath $meterPath -WorkingDirectory ([System.IO.Path]::GetDirectoryName($meterPath)) -PassThru
        Write-Log "Started meter PID=$($p.Id) because $gameProcessName.exe is running."
    }
    catch {
        Write-Log "Failed to start meter: $($_.Exception.Message)"
    }
}

Write-Log "Watcher started. Game=$gameProcessName.exe Meter=$meterPath HideFromTaskbar=$hideFromTaskbar StopWithGame=$stopWithGame"

while ($true) {
    if (Load-Config) {
        Write-Log "Config reloaded. Game=$gameProcessName.exe Meter=$meterPath HideFromTaskbar=$hideFromTaskbar StopWithGame=$stopWithGame"
    }

    $gameRunning = Get-GameRunning
    $meterProcesses = Get-MeterProcesses

    if ($gameRunning -and $meterProcesses.Count -eq 0) {
        Start-Meter
        Start-Sleep -Milliseconds 250
        $meterProcesses = Get-MeterProcesses
    }

    if ($hideFromTaskbar -and $meterProcesses.Count -gt 0) {
        foreach ($proc in $meterProcesses) {
            try {
                [void][TaskbarWindowHider]::HideWindowsForProcess($proc.Id)
            }
            catch {
                # Keep the watcher alive even if a window disappears during enumeration.
            }
        }
    }

    # Enforce the configured lifecycle instead of depending on a single
    # running -> stopped transition. This also handles watcher restarts,
    # config changes while it is running, crashes, and missed polling edges.
    if ($stopWithGame -and -not $gameRunning -and $meterProcesses.Count -gt 0) {
        foreach ($proc in $meterProcesses) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-Log "Stopped meter PID=$($proc.Id) because $gameProcessName.exe is not running."
            }
            catch {
                Write-Log "Failed to stop meter PID=$($proc.Id): $($_.Exception.Message)"
            }
        }
    }

    Start-Sleep -Milliseconds $pollMilliseconds
}
