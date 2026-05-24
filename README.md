# Dota 2 Helper

Windows helper for small Dota 2 automation tools.

The GUI uses the same four-section layout for every tool: **Status**, **Mode**, **Buttons**, and **Log**. The current tools are:

- **Auto Accept**: detects the match-found Accept button and optionally clicks it.
- **Create Lobby**: runs a configurable sequence for creating a custom game lobby.
- **Operation Recorder**: records guided clicks and translates them into a runnable sequence JSON file.

Calibration is a shared button function, not a separate tool. It saves machine-local default positions for whichever tool is selected.

## Folder Layout

```text
.
|-- AutoAcceptor-GUI.ps1              # Root wrapper kept for the EXE launcher
|-- DotaAutoAcceptor.exe              # Double-click launcher
|-- DotaAutoAcceptorLauncher.cs       # Launcher source
|-- Launch GUI.cmd                    # Batch fallback launcher
|-- config
|   |-- targets
|   |   `-- dota-default.targets.json # Shared Auto Accept visual rules
|   `-- tools
|       |-- auto-accept.tool.json     # Auto Accept presets
|       `-- create-lobby.tool.json    # Create Lobby sequence template
|-- src
|   |-- gui
|   |   `-- Dota2Helper-GUI.ps1       # Main GUI
|   `-- runners
|       |-- Accept-DotaMatch.ps1      # Auto Accept runner
|       |-- Invoke-DotaSequence.ps1   # Generic sequence runner
|       `-- Record-DotaSequence.ps1   # Lower-level console recorder
`-- local                             # Ignored local/generated state
```

`local/` is ignored by git. It stores calibration, generated sequence files, screenshots, and runtime logs.

## Practical Model

The simple model is:

```text
user knows the operation flow
-> Operation Recorder records real click coordinates
-> local runnable JSON is created
-> runner executes it on this machine
```

This avoids depending on Dota source files. Different machines can record their own local JSON for the same tool.

Tracked templates in `config\tools\` are only starting points. They describe the tool and expected sequence shape. They should not contain personal coordinates.

Local generated files in `local\` contain the real coordinates and visual checks for your machine.

## Calibration

Calibration is a shared sub-function for tools.

Use it when you want to save default positions on this machine without editing JSON by hand.

In the GUI:

1. Select the tool you want to calibrate, such as **Auto Accept** or **Create Lobby**.
2. Click **Calibrate** in the **Buttons** section.
3. Follow the log prompt.
4. Click the requested position in Dota.
5. Repeat until the log says calibration is complete.

The GUI does not open a separate calibration page. It records each left-click position in order and writes progress to the log.

For **Auto Accept**, the flow records:

- **Accept button**

For **Create Lobby**, the flow records:

- **ARCADE**
- **LOBBY LIST**
- **CREATE CUSTOM LOBBY**
- **GAME MOD DROPDOWN**
- **GAME MOD VALUE: DOTA2 IM** or the current **Mod game** value in the GUI
- **SERVER LOCATION DROPDOWN**
- **SERVER LOCATION VALUE**
- **CREATE**

Saved machine defaults live in:

```text
local\machine-calibration.json
```

For Auto Accept, saving **Auto Accept / Accept button** also updates:

```text
local\acceptor.config.json
```

That keeps the existing Auto Accept runner compatible.

## Operation Model

Every sequence operation should be treated as:

```text
prerequisites -> action -> optional verification
```

Before clicking or typing, the runner should verify that Dota is currently on the expected page. Otherwise a click can land on the wrong screen.

Example:

```json
{
  "name": "Create lobby",
  "action": "click",
  "x": 1040,
  "y": 705,
  "prerequisites": [
    {
      "name": "Lobby config page is visible",
      "action": "verifyColorCluster",
      "region": { "x": 900, "y": 120, "width": 360, "height": 180 },
      "color": { "r": 210, "g": 190, "b": 140 },
      "tolerance": 24,
      "minHits": 20,
      "sampleStep": 4,
      "timeoutMs": 3000
    }
  ]
}
```

If the prerequisite fails, the click is not executed.

Use prerequisites for:

- page checks before navigation clicks
- dialog checks before confirm/create buttons
- search-ready checks before typing
- lobby-created checks before later lobby operations
- player-list-visible checks before future kick/player actions

## Quick Start

Double-click:

```text
DotaAutoAcceptor.exe
```

Manual GUI launch:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\AutoAcceptor-GUI.ps1
```

Only one Dota 2 Helper instance can run at a time, and only one tool can run at a time.

## Auto Accept

Auto Accept uses:

- Tool template: `config\tools\auto-accept.tool.json`
- Target rules: `config\targets\dota-default.targets.json`
- Local calibration: `local\acceptor.config.json`
- Shared machine defaults: `local\machine-calibration.json`

Modes:

- `Ready: click once`: clicks when a match is detected, then stops.
- `Test: detect only`: logs and beeps without clicking.
- `Fast: lower delay`: faster polling and fewer stable hits.
- `Custom`: exposes tuning options.

Use the **Calibrate** button from the GUI to create or update your click coordinate.

The GUI can use the Windows foreground signal for queue pops. In **Custom** mode, **Start when Dota foregrounds** is visible and checked by default. When enabled, the helper watches for the foreground app moving from another app into `dota2.exe`, checks the user's mouse working area once at that transition, and starts Auto Accept only if the mouse is outside the Dota window. Clicking **Stop** suppresses auto-start until Dota leaves foreground again.

## Create Lobby

Create Lobby uses:

- Tool template: `config\tools\create-lobby.tool.json`
- Sequence runner: `src\runners\Invoke-DotaSequence.ps1`
- Local runnable sequence per Game mod, such as `local\create-lobby.dota2-im.config.json`
- Shared machine defaults: `local\machine-calibration.json`

The intended flow is:

```text
assume dashboard activated
-> click ARCADE
-> click LOBBY LIST
-> click CREATE CUSTOM LOBBY
-> set Game Mod
-> set Server Location
-> click CREATE
```

The template contains placeholder coordinates. Use **Operation Recorder** to generate the real local sequence for your Dota layout.

The simpler path is **Calibrate**. After Create Lobby calibration is complete, the next Create Lobby run or dry run refreshes the Game mod specific config from `local\machine-calibration.json`. For `DOTA2 IM`, that file is `local\create-lobby.dota2-im.config.json`. The generated sequence clicks the calibrated navigation targets, selects the calibrated Game Mod value, selects the calibrated Server Location value, then clicks **CREATE**.

For example, if the GUI **Mod game** field is `DOTA2 IM`, calibration records a target named **GAME MOD VALUE: DOTA2 IM**. That lets other game mods have their own calibrated value click later.

Changing the **Game mod** field changes both:

- the calibrated Game mod value target, such as **GAME MOD VALUE: DOTA2 IM**
- the runnable config file, such as `local\create-lobby.dota2-im.config.json`

The GUI keeps a local saved Game mod list in:

```text
local\game-modes.json
```

Use the **Game mod** dropdown to select a saved mode. Type a new Game mod name and click **Save** to add it to that local list. Each saved Game mod can be calibrated separately because the value target includes the mode name.

The Game Mod and Server Location setup subflow is:

```text
click Game Mod dropdown
-> click calibrated Game Mod value
-> click Server Location dropdown
-> click calibrated Server Location value
```

Supported sequence actions:

- `click`: move to an x/y coordinate and left-click.
- `wait`: pause for a configured number of milliseconds.
- `text`: send text, including placeholders like `{{ModGameName}}`.
- `sendKeys`: send a Windows Forms SendKeys expression.
- `capture`: save a screenshot region for inspection.
- `verifyColorCluster`: wait until a region contains enough pixels matching a recorded color rule.
- `subflow`: group nested operations, such as Game Mod and Server Location setup.

## Operation Recorder

Select **Operation Recorder** in the GUI and click **Record**. The recorder stays inside the GUI and writes instructions to the log.

For now, it records click operations only. It is for undefined/new tools, not Auto Accept or Create Lobby. Each user click is translated back into a runnable JSON step.

Example generated step:

```json
{
  "name": "Click 1",
  "action": "click",
  "target": "click_1",
  "x": 1149,
  "y": 39
}
```

Generic recording flow:

1. Open Dota 2 to the screen where the workflow should start.
2. Select **Operation Recorder**.
3. Select a saved tool name from the editable dropdown, or type a new one such as `kick-player`.
4. Click **Save** to store the new recorder tool in the local dropdown list.
5. Set output to a new local file, such as `local\kick-player.config.json`. The default output follows the selected tool name.
6. Click **Record**.
7. Click each real Dota UI position in order.
8. Click **Finish** to write the JSON.
9. Click **Stop** to cancel without saving.

Saved Operation Recorder tool names live in:

```text
local\recorder-tools.json
```

Calibration and Operation Recorder are related but different:

- **Calibration** saves reusable machine target points to `local\machine-calibration.json`.
- **Operation Recorder** writes a runnable sequence JSON for a new/undefined tool.

## Git Notes

Tracked:

- `src/`
- `config/`
- launchers
- README

Ignored:

- `local/`
- legacy root `acceptor.config.json`
- legacy root `create-lobby.config.json`
- legacy root `acceptor.runtime*.log`
