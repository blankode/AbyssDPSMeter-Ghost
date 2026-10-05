# AbyssDPSMeter Ghost

A small Windows watcher for AION 2 that automatically starts `AbyssDPSMeter.exe` when `AION2.exe` is detected, removes the meter window from the Windows taskbar, and closes the meter again when the game exits.

## What it does

- Starts `AbyssDPSMeter.exe` automatically when `AION2.exe` is detected.
- Runs the watcher itself hidden at Windows logon.
- Removes AbyssDPSMeter windows from the Windows taskbar while keeping the overlay usable.
- Runs through a highest-privilege scheduled task so the meter can keep the administrator rights required for Npcap packet capture.
- Stops `AbyssDPSMeter.exe` automatically when `AION2.exe` is no longer running.
- Reloads `config.json` while the watcher is running, so lifecycle settings can be changed without restarting the scheduled task.
- Does **not** modify, patch, inject into, or touch `AION2.exe`.
- Does **not** modify the AbyssDPSMeter executable.

## Install

1. Put these files in the same folder as your meter executable.
2. Keep the meter executable named exactly `AbyssDPSMeter.exe`.
3. Double-click `Install.cmd`.
4. Accept the UAC prompt.

The installer creates a hidden scheduled task named:

`AION2 - Abyss DPS Meter Watcher`

The installed watcher/config are stored in:

`%LOCALAPPDATA%\Aion2MeterWatcher`

## Default behaviour

- `AION2.exe` starts -> `AbyssDPSMeter.exe` starts automatically if it is not already running.
- The meter is removed from the Windows taskbar.
- `AION2.exe` closes -> `AbyssDPSMeter.exe` is force-closed.

Default config:

```json
{
  "GameProcessName": "AION2",
  "HideFromTaskbar": true,
  "StopMeterWhenGameExits": true,
  "PollMilliseconds": 350
}
```

`MeterPath` is written automatically by the installer.

## Troubleshooting

Watcher log:

`%LOCALAPPDATA%\Aion2MeterWatcher\watcher.log`

Installed config:

`%LOCALAPPDATA%\Aion2MeterWatcher\config.json`

## Uninstall

Double-click `Uninstall.cmd`.

This removes the scheduled task and watcher files under `%LOCALAPPDATA%\Aion2MeterWatcher`. It does not delete `AbyssDPSMeter.exe`.

## Version 3

- Uses the exact executable name `AbyssDPSMeter.exe`.
- `StopMeterWhenGameExits` defaults to `true`.
- Config is reloaded live when `config.json` changes.
- Shutdown no longer depends on catching a single running -> stopped transition.
- If `StopMeterWhenGameExits=true` and `AION2.exe` is absent, any running `AbyssDPSMeter.exe` process is stopped.
