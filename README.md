# Dota Match Queue Auto Acceptor

Windows helper for detecting the Dota 2 match-found **Accept** popup and optionally clicking it for you.

The project includes a PowerShell WinForms GUI, a screen-scanning worker script, and a tiny EXE launcher that opens the GUI without leaving a console window behind.

## What It Does

- Watches a small center-screen region for the green Dota 2 Accept button.
- Can run in test mode so you can verify detection without clicking.
- Supports calibrated click coordinates for different displays and resolutions.
- Can restrict clicks to when Dota 2 is the foreground window.
- Can stop automatically after one accepted match.
- Keeps temporary runtime logs out of source control.

The key reference is `panorama\styles\popups\popup_accept_match.vcss_c`, where the Accept button is defined as `#Button0` with green colors around `#45715b` and `#48d07d`.

## Requirements

- Windows
- PowerShell 5.1 or newer
- .NET Framework support for `System.Drawing` and `System.Windows.Forms`
- Dota 2 running in a visible desktop session

## Quick Start

Double-click:

```text
DotaAutoAcceptor.exe
```

If Windows blocks the EXE, use:

```text
Launch GUI.cmd
```

Manual GUI launch:

```powershell
cd "D:\coding\git_repo\match_queue_auto_acceptor"
powershell -NoProfile -ExecutionPolicy Bypass -File .\AutoAcceptor-GUI.ps1
```

## Recommended First Run

1. Open the GUI with `DotaAutoAcceptor.exe`.
2. Click **Calibrate click**.
3. When the calibration console opens, place the mouse on the center of the real Dota 2 Accept button and press Enter.
4. Enable **Test mode: no click** and **Verbose detection**.
5. Click **Start capture** and confirm detection appears in the GUI log.
6. Disable test mode when detection looks correct.

Calibration creates a local, user-specific file:

```text
acceptor.config.json
```

That file is ignored by git because it stores machine-specific coordinates.

## Command Line

Active auto-click mode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Accept-DotaMatch.ps1
```

Test without clicking:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Accept-DotaMatch.ps1 -NoClick -VerboseDetection
```

Run once, click, then exit after the button disappears:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Accept-DotaMatch.ps1 -StopAfterAccept
```

Short smoke test:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Accept-DotaMatch.ps1 -NoClick -DurationSeconds 5
```

## Files

- `AutoAcceptor-GUI.ps1`: WinForms GUI for configuring and starting capture.
- `Accept-DotaMatch.ps1`: screen detector and click worker.
- `DotaAutoAcceptor.exe`: double-click launcher for the GUI.
- `DotaAutoAcceptorLauncher.cs`: source for the launcher EXE.
- `Launch GUI.cmd`: fallback launcher command.
- `.gitignore`: ignores runtime logs and local calibration.
- `acceptor.config.json`: generated local calibration file.
- `acceptor.runtime.log`: generated worker log.

## Git Notes

The repository should track the scripts, launcher source, launcher EXE, README, and `.gitignore`.

The following are intentionally ignored:

- `acceptor.config.json`
- `acceptor.runtime*.log`

## Performance And Reliability

The worker scans a small region at the configured interval instead of capturing the full screen. `PollMs` defaults to `450`, roughly two checks per second. Increase `PollMs` or `StableHits` to reduce CPU use and false positives; lower them only if you need faster reaction.

The worker disposes each screenshot bitmap after every scan. The GUI owns one timer, disposes stopped worker process handles, and kills the hidden worker when you stop capture or close the GUI. Runtime logging is file-based so verbose output can appear in the GUI without fragile async console callbacks.
