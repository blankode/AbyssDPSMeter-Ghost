# AbyssDPSMeter Ghost

A small Windows watcher for AION 2 that automatically starts the official Abyss DPS Meter when `AION2.exe` is detected, removes the meter window from the Windows taskbar, and closes the meter again when the game exits.

## What it does

- Downloads the latest official Abyss DPS Meter during installation.
- Uses the meter's official release manifest at `https://cdn.meter.abysslogs.com/manifest.json`.
- Stores the runtime copy as `%LOCALAPPDATA%\Aion2MeterWatcher\AbyssDPSMeter.exe`.
- Starts `AbyssDPSMeter.exe` automatically when `AION2.exe` is detected.
- Runs the watcher itself hidden at Windows logon.
- Removes AbyssDPSMeter windows from the Windows taskbar while keeping the overlay usable.
- Runs through a highest-privilege scheduled task so the meter can keep the administrator rights required for Npcap packet capture.
- Stops `AbyssDPSMeter.exe` automatically when `AION2.exe` is no longer running.
- Reloads `config.json` while the watcher is running, so lifecycle settings can be changed without restarting the scheduled task.
- Does **not** modify, patch, inject into, or touch `AION2.exe`.
- Does **not** patch or modify the downloaded AbyssDPSMeter executable.

## Install

1. Download or clone this repository.
2. Double-click `Install.cmd`.
3. Accept the UAC prompt.
4. The installer checks the official Abyss Logs release manifest, downloads the latest meter package, extracts `AbyssDPSMeter.exe` if required, and installs everything under `%LOCALAPPDATA%\Aion2MeterWatcher`.
5. After installation succeeds, the downloaded/cloned repository folder can be deleted.

You do **not** need to download `AbyssDPSMeter.exe` manually or keep it beside `Install.cmd`.

The installer creates a hidden scheduled task named:

`AION2 - Abyss DPS Meter Watcher`

Runtime files are stored in:

`%LOCALAPPDATA%\Aion2MeterWatcher`

Typical contents:

```text
Aion2MeterWatcher.ps1
AbyssDPSMeter.exe
config.json
watcher.log
```

Temporary download/extraction files are created under `%TEMP%` only while the installer is running and are removed afterwards.

## Official download source

The installer does not scrape the website UI. It reads the same official Abyss Logs release channel used by the meter:

`https://cdn.meter.abysslogs.com/manifest.json`

The manifest's `downloadUrl` is used to retrieve the current release. The installer requires HTTPS, accepts either an EXE or ZIP package, and verifies that the final `AbyssDPSMeter.exe` is a Windows PE executable before installing it.

If the manifest exposes a SHA-256 checksum field, the installer verifies it before installation as well.

## Default behaviour

- `AION2.exe` starts -> `AbyssDPSMeter.exe` starts automatically if it is not already running.
- The meter is removed from the Windows taskbar.
- `AION2.exe` closes -> `AbyssDPSMeter.exe` is force-closed.

Default config:

```json
{
  "MeterPath": "%LOCALAPPDATA%\\Aion2MeterWatcher\\AbyssDPSMeter.exe",
  "MeterVersion": "<downloaded version>",
  "MeterManifestUrl": "https://cdn.meter.abysslogs.com/manifest.json",
  "GameProcessName": "AION2",
  "HideFromTaskbar": true,
  "StopMeterWhenGameExits": true,
  "PollMilliseconds": 350
}
```

`MeterPath` and `MeterVersion` are written automatically by the installer.

## Reinstall / update

Run `Install.cmd` again at any time.

It will:

1. Check the current official Abyss Logs manifest.
2. Download the currently published meter release.
3. Stop the old watcher and the installed meter if necessary.
4. Replace `%LOCALAPPDATA%\Aion2MeterWatcher\AbyssDPSMeter.exe`.
5. Recreate and restart the scheduled task.

The Abyss DPS Meter also has its own in-app updater; this installer flow simply guarantees that a fresh/reinstall starts from the current official release.

## Troubleshooting

Watcher log:

`%LOCALAPPDATA%\Aion2MeterWatcher\watcher.log`

Installed config:

`%LOCALAPPDATA%\Aion2MeterWatcher\config.json`

Installed meter:

`%LOCALAPPDATA%\Aion2MeterWatcher\AbyssDPSMeter.exe`

## Uninstall

Double-click `Uninstall.cmd`.

This stops the watcher, stops the LocalAppData-installed meter instance, removes the scheduled task, and deletes `%LOCALAPPDATA%\Aion2MeterWatcher` including the downloaded `AbyssDPSMeter.exe`.

## Version 4

- `Install.cmd` no longer requires a manually downloaded `AbyssDPSMeter.exe`.
- Installer resolves the latest release from the official Abyss Logs meter manifest.
- Official package is downloaded to a temporary staging directory.
- ZIP and direct EXE release formats are supported.
- Runtime `AbyssDPSMeter.exe` is installed under `%LOCALAPPDATA%\Aion2MeterWatcher`.
- The source/download folder can be deleted after installation.
- Re-running the installer refreshes the locally installed meter from the official release channel.
- Uninstall now removes the locally installed meter as well.

## Version 3

- Uses the exact executable name `AbyssDPSMeter.exe`.
- `StopMeterWhenGameExits` defaults to `true`.
- Config is reloaded live when `config.json` changes.
- Shutdown no longer depends on catching a single running -> stopped transition.
- If `StopMeterWhenGameExits=true` and `AION2.exe` is absent, any running `AbyssDPSMeter.exe` process is stopped.
