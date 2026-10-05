# AbyssDPSMeter Ghost

A small Windows watcher for AION 2 that automatically starts the official Abyss DPS Meter when `AION2.exe` is detected, removes the meter window from the Windows taskbar, and closes the meter again when the game exits.

## What it does

- Resolves the latest official Abyss DPS Meter release automatically during installation.
- Uses `https://api.abysslogs.com/v1/meter/latest` as the primary latest-release endpoint.
- Keeps `https://cdn.meter.abysslogs.com/manifest.json` only as a fallback and supports nested manifest fields.
- Downloads short-lived signed release URLs immediately instead of hardcoding them.
- Supports the current official `AbyssDPSMeter-vX.Y.Z-setup.exe` release format.
- Installs the official Wails/NSIS package silently under `%LOCALAPPDATA%\Aion2MeterWatcher\Meter`.
- Starts `AbyssDPSMeter.exe` automatically when `AION2.exe` is detected.
- Runs the watcher itself hidden at Windows logon.
- Removes AbyssDPSMeter windows from the Windows taskbar while keeping the overlay usable.
- Runs through a highest-privilege scheduled task so the meter can keep the administrator rights required for Npcap packet capture.
- Stops `AbyssDPSMeter.exe` automatically when `AION2.exe` is no longer running.
- Reloads `config.json` while the watcher is running.
- Does **not** modify, patch, inject into, or touch `AION2.exe`.
- Does **not** patch or modify the official Abyss DPS Meter executable.

## Install

1. Download or clone this repository.
2. Double-click `Install.cmd`.
3. Accept the UAC prompt.
4. The installer resolves the current official release, downloads it to a temporary staging directory, installs the meter under `%LOCALAPPDATA%\Aion2MeterWatcher\Meter`, and creates the hidden watcher task.
5. After installation succeeds, the downloaded/cloned repository folder can be deleted.

You do **not** need to download `AbyssDPSMeter.exe` manually or keep it beside `Install.cmd`.

The installer creates a scheduled task named:

`AION2 - Abyss DPS Meter Watcher`

Runtime files are stored under:

`%LOCALAPPDATA%\Aion2MeterWatcher`

Typical layout:

```text
Aion2MeterWatcher\
├── Aion2MeterWatcher.ps1
├── config.json
├── watcher.log
└── Meter\
    ├── AbyssDPSMeter.exe
    └── ...files created by the official installer
```

Temporary download files are created under `%TEMP%` only while the installer runs and are removed afterwards.

## Official download source

Primary release metadata endpoint:

`https://api.abysslogs.com/v1/meter/latest`

Fallback release manifest:

`https://cdn.meter.abysslogs.com/manifest.json`

The API provides the current version and a fresh `downloadUrl`. The download URL may point to a short-lived signed Cloudflare R2 URL, so the installer resolves it every time instead of storing or hardcoding a signed link.

The current Windows release is an NSIS setup executable. Wails uses NSIS for Windows packaging, so the installer runs it silently with `/S` and overrides the destination with `/D=...`, installing it inside the Ghost LocalAppData directory.

If Abyss Logs changes back to a portable EXE or ZIP release, the installer also supports those formats.

## Default behaviour

- `AION2.exe` starts -> `AbyssDPSMeter.exe` starts automatically if it is not already running.
- The meter is removed from the Windows taskbar.
- `AION2.exe` closes -> `AbyssDPSMeter.exe` is force-closed.

Example generated config:

```json
{
  "MeterPath": "C:\\Users\\<user>\\AppData\\Local\\Aion2MeterWatcher\\Meter\\AbyssDPSMeter.exe",
  "MeterVersion": "<downloaded version>",
  "MeterReleaseApiUrl": "https://api.abysslogs.com/v1/meter/latest",
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

1. Resolve the current official Abyss Logs release.
2. Request a fresh download URL.
3. Download the currently published release.
4. Stop the old watcher and installed meter.
5. Reinstall the official meter under `%LOCALAPPDATA%\Aion2MeterWatcher\Meter`.
6. Recreate and restart the scheduled task.

The Abyss DPS Meter also has its own updater. Re-running Ghost's installer guarantees a fresh install from the current official release channel.

## Troubleshooting

Watcher log:

`%LOCALAPPDATA%\Aion2MeterWatcher\watcher.log`

Installed config:

`%LOCALAPPDATA%\Aion2MeterWatcher\config.json`

Installed meter is normally:

`%LOCALAPPDATA%\Aion2MeterWatcher\Meter\AbyssDPSMeter.exe`

The exact detected executable path is stored in `config.json` as `MeterPath`.

## Uninstall

Double-click `Uninstall.cmd`.

This stops the watcher, stops the LocalAppData-installed meter instance, removes the scheduled task, and deletes `%LOCALAPPDATA%\Aion2MeterWatcher`.

## Version 5

- Fixed the incorrect assumption that the CDN manifest always exposes a root-level `downloadUrl`.
- Uses the official meter's stable `/v1/meter/latest` API as the primary release resolver.
- CDN manifest is now fallback-only and searched recursively.
- Correctly handles signed Cloudflare R2 URLs that expire.
- Correctly handles current `*-setup.exe` releases instead of renaming the installer to `AbyssDPSMeter.exe`.
- Runs the official Wails/NSIS installer silently into the Ghost LocalAppData directory.
- Automatically migrates away from the old v4 root-level meter layout.

## Version 4

- `Install.cmd` no longer requires a manually downloaded `AbyssDPSMeter.exe`.
- Official package is downloaded to a temporary staging directory.
- ZIP and direct EXE release formats are supported.
- The source/download folder can be deleted after installation.
- Uninstall removes the locally installed meter as well.

## Version 3

- Uses the exact executable name `AbyssDPSMeter.exe`.
- `StopMeterWhenGameExits` defaults to `true`.
- Config is reloaded live when `config.json` changes.
- Shutdown no longer depends on catching a single running -> stopped transition.
- If `StopMeterWhenGameExits=true` and `AION2.exe` is absent, any running `AbyssDPSMeter.exe` process is stopped.
