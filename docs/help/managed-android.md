---
ids: [B2B-001, B2B-002]
---
# Managed devices and kiosks on Android

For IT teams who run Mediahro on company-owned Android devices, signage players and kiosks.

## Managed configuration

Set these app restrictions from your MDM console (Android Enterprise). The console shows each key with its title.

| Key | What it does |
|---|---|
| `allowed_sources` | Kinds of source people may add: device storage, SMB, SFTP, FTP, WebDAV, NFS, UPnP/DLNA, media servers. Empty means all. |
| `locked_settings` | Setting ids that people cannot change, separated by commas. |
| `kiosk` | Run as a kiosk (see below). |
| `branding_off` | Hide the app name and supporter prompts (enterprise licence). |
| `telemetry_off` | Keep diagnostics and crash reports off. |
| `playlist_url` | A playlist to start automatically. |
| `update_channel` | `stable` or `beta`. Informational, for your own deployment tooling: the app never checks for or installs updates. |

A setting that your MDM controls shows a lock in Settings and cannot be changed on the device. Changes in the console apply while the app is running.

## Kiosk mode

Kiosk mode fills the screen, hides the system bars, keeps the screen on and locks the device to Mediahro.

- **Lock to the app:** on a device where Mediahro is a lock-task app (set by your device-owner MDM), the device is locked without a prompt. On other devices Android pins the screen and asks once.
- **Restart if it stops:** if the app closes because of an error, it starts again after a few seconds. This needs "Alarms & reminders" to be allowed for exact timing, and a device owner or "Display over other apps" for starting from the background.
- **Start after the device boots:** available in the enterprise build. Provision the device so Mediahro may start itself (device owner, or "Display over other apps").

To leave kiosk mode, turn the `kiosk` key off in your console, or use the exit gesture in the app.
