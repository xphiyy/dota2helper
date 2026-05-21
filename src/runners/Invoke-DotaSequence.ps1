param(
    [string]$Tool = 'CreateLobby',
    [string]$ConfigPath = '',
    [string]$ToolConfigPath = '',
    [string]$ModGameName = '',
    [int]$StepDelayMs = 450,
    [switch]$InitializeConfig,
    [switch]$DryRun,
    [string]$LogPath = ''
)

function Write-Status {
    param([string]$Message)
    Write-Host $Message
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $stream = $null
        $writer = $null
        try {
            $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $LogPath))
            $stream = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
            $writer.WriteLine($line)
        }
        catch {
            # Logging should never stop an operation sequence.
        }
        finally {
            if ($null -ne $writer) { $writer.Dispose() }
            elseif ($null -ne $stream) { $stream.Dispose() }
        }
    }
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$localDir = Join-Path $projectRoot 'local'
[void][System.IO.Directory]::CreateDirectory($localDir)
$machineCalibrationPath = Join-Path $localDir 'machine-calibration.json'

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class Win32SequenceTool
{
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

    public const uint LEFTDOWN = 0x0002;
    public const uint LEFTUP = 0x0004;
}
"@

function Invoke-LeftClick {
    param([int]$X, [int]$Y)

    [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new($X, $Y)
    Start-Sleep -Milliseconds 35
    [Win32SequenceTool]::mouse_event([Win32SequenceTool]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 35
    [Win32SequenceTool]::mouse_event([Win32SequenceTool]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
}

function New-DefaultCreateLobbyConfig {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

    if ([string]::IsNullOrWhiteSpace($ToolConfigPath)) {
        $ToolConfigPath = Join-Path $projectRoot 'config\tools\create-lobby.tool.json'
    }

    if (Test-Path -LiteralPath $ToolConfigPath) {
        try {
            $toolConfig = Get-Content -LiteralPath $ToolConfigPath -Raw | ConvertFrom-Json
            $template = $toolConfig.sequenceTemplate
            $template.screenWidth = $screen.Width
            $template.screenHeight = $screen.Height
            return $template
        }
        catch {
            Write-Status "WARNING: Could not read tool template: $ToolConfigPath"
        }
    }

    [ordered]@{
        tool = 'CreateLobby'
        modGameName = 'DOTA2 IM'
        screenWidth = $screen.Width
        screenHeight = $screen.Height
        notes = 'Record real operations with Record-DotaSequence.ps1.'
        steps = @()
    }
}

function Get-CalibrationKey {
    param([string]$Value)
    ($Value -replace '[^\w]+', '_').Trim('_').ToLowerInvariant()
}

function Get-SafeName {
    param([string]$Value)
    $safe = ($Value -replace '[^\w.-]+', '-').Trim('-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'default' }
    return $safe
}

function Get-MachineCalibrationPoint {
    param(
        [object]$Calibration,
        [string]$Tool,
        [string]$Target
    )

    if ($null -eq $Calibration -or $null -eq $Calibration.tools) { return $null }

    $toolKey = Get-CalibrationKey $Tool
    $targetKey = Get-CalibrationKey $Target
    $toolNode = $Calibration.tools.$toolKey
    if ($null -eq $toolNode) { return $null }

    return $toolNode.$targetKey
}

function Test-CreateLobbyHasPlaceholderClicks {
    param([object]$Config)

    $steps = if ($Config.steps) { @($Config.steps) } elseif ($Config.Steps) { @($Config.Steps) } else { @() }
    foreach ($step in $steps) {
        $action = if ($step.action) { [string]$step.action } elseif ($step.Action) { [string]$step.Action } else { '' }
        if ($action -eq 'click' -and ([int]$step.x -eq 0 -or [int]$step.y -eq 0)) { return $true }

        $substeps = if ($step.flow) { @($step.flow) } elseif ($step.Flow) { @($step.Flow) } else { @() }
        foreach ($substep in $substeps) {
            $subAction = if ($substep.action) { [string]$substep.action } elseif ($substep.Action) { [string]$substep.Action } else { '' }
            if ($subAction -eq 'click' -and ([int]$substep.x -eq 0 -or [int]$substep.y -eq 0)) { return $true }
        }
    }

    return $false
}

function New-CalibratedCreateLobbyConfig {
    param([object]$ExistingConfig)

    if (-not (Test-Path -LiteralPath $machineCalibrationPath)) { return $null }

    try {
        $calibration = Get-Content -LiteralPath $machineCalibrationPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Status "WARNING: Could not read machine calibration: $machineCalibrationPath"
        return $null
    }

    $gameMod = if (-not [string]::IsNullOrWhiteSpace($ModGameName)) {
        $ModGameName
    }
    elseif ($ExistingConfig.modGameName) {
        [string]$ExistingConfig.modGameName
    }
    elseif ($ExistingConfig.ModGameName) {
        [string]$ExistingConfig.ModGameName
    }
    else {
        'DOTA2 IM'
    }

    $gameModTarget = "GAME MOD VALUE: $gameMod"
    $requiredTargets = @(
        'ARCADE',
        'LOBBY LIST',
        'CREATE CUSTOM LOBBY',
        'GAME MOD DROPDOWN',
        $gameModTarget,
        'SERVER LOCATION DROPDOWN',
        'SERVER LOCATION VALUE',
        'CREATE'
    )
    $points = @{}
    foreach ($target in $requiredTargets) {
        $point = Get-MachineCalibrationPoint -Calibration $calibration -Tool 'Create Lobby' -Target $target
        if ($null -eq $point) { return $null }
        $points[$target] = $point
    }

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

    [ordered]@{
        tool = 'CreateLobby'
        source = 'machine-calibration'
        modGameName = $gameMod
        screenWidth = $screen.Width
        screenHeight = $screen.Height
        notes = 'Generated from local machine calibration. Re-run Calibrate in the GUI to update coordinates.'
        flow = @(
            'assume dashboard activated',
            'click ARCADE',
            'click LOBBY LIST',
            'click CREATE CUSTOM LOBBY',
            "set Game Mod: $gameMod",
            'set Server Location',
            'click CREATE'
        )
        steps = @(
            [ordered]@{ name = 'Click ARCADE'; action = 'click'; x = [int]$points['ARCADE'].x; y = [int]$points['ARCADE'].y },
            [ordered]@{ name = 'Wait for arcade page'; action = 'wait'; milliseconds = 700 },
            [ordered]@{ name = 'Click LOBBY LIST'; action = 'click'; x = [int]$points['LOBBY LIST'].x; y = [int]$points['LOBBY LIST'].y },
            [ordered]@{ name = 'Wait for lobby list'; action = 'wait'; milliseconds = 700 },
            [ordered]@{ name = 'Click CREATE CUSTOM LOBBY'; action = 'click'; x = [int]$points['CREATE CUSTOM LOBBY'].x; y = [int]$points['CREATE CUSTOM LOBBY'].y },
            [ordered]@{ name = 'Wait for lobby settings'; action = 'wait'; milliseconds = 900 },
            [ordered]@{
                name = "Set Game Mod: $gameMod"
                action = 'subflow'
                flow = @(
                    [ordered]@{ name = 'Open Game Mod list'; action = 'click'; x = [int]$points['GAME MOD DROPDOWN'].x; y = [int]$points['GAME MOD DROPDOWN'].y },
                    [ordered]@{ name = "Select Game Mod: $gameMod"; action = 'click'; x = [int]$points[$gameModTarget].x; y = [int]$points[$gameModTarget].y },
                    [ordered]@{ name = 'Open Server Location list'; action = 'click'; x = [int]$points['SERVER LOCATION DROPDOWN'].x; y = [int]$points['SERVER LOCATION DROPDOWN'].y },
                    [ordered]@{ name = 'Select Server Location'; action = 'click'; x = [int]$points['SERVER LOCATION VALUE'].x; y = [int]$points['SERVER LOCATION VALUE'].y }
                )
            },
            [ordered]@{ name = 'Click CREATE'; action = 'click'; x = [int]$points['CREATE'].x; y = [int]$points['CREATE'].y }
        )
    }
}

function Update-CreateLobbyConfigFromCalibration {
    param([object]$Config)

    if ($Tool -ne 'CreateLobby') { return $Config }

    $shouldRefresh = $false
    if ($Config.source -eq 'machine-calibration') { $shouldRefresh = $true }
    if (Test-CreateLobbyHasPlaceholderClicks -Config $Config) { $shouldRefresh = $true }

    if (-not $shouldRefresh) { return $Config }

    $calibratedConfig = New-CalibratedCreateLobbyConfig -ExistingConfig $Config
    if ($null -eq $calibratedConfig) {
        Write-Status 'WARNING: Create Lobby calibration is incomplete. Using existing sequence config.'
        return $Config
    }

    $calibratedConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    Write-Status "Updated Create Lobby sequence from machine calibration: $ConfigPath"
    return [pscustomobject]$calibratedConfig
}

function Get-SequenceConfig {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $gameModForPath = if (-not [string]::IsNullOrWhiteSpace($ModGameName)) { $ModGameName } else { 'DOTA2 IM' }
        $ConfigPath = Join-Path $localDir ("create-lobby.{0}.config.json" -f (Get-SafeName $gameModForPath))
    }

    if ($InitializeConfig -or -not (Test-Path -LiteralPath $ConfigPath)) {
        $config = New-DefaultCreateLobbyConfig
        $config = Update-CreateLobbyConfigFromCalibration -Config ([pscustomobject]$config)
        $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
        Write-Status "Created sequence config: $ConfigPath"
        return [pscustomobject]$config
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        if (Test-LegacyGeneratedCreateLobbyConfig -Config $config) {
            $backupPath = "$ConfigPath.legacy-backup-{0:yyyyMMdd-HHmmss}" -f (Get-Date)
            Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
            $config = New-DefaultCreateLobbyConfig
            $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
            Write-Status "Updated legacy generated sequence config from current template. Backup: $backupPath"
        }
        $config = Update-CreateLobbyConfigFromCalibration -Config $config
        return $config
    }
    catch {
        throw "Could not read sequence config: $ConfigPath"
    }
}

function Test-LegacyGeneratedCreateLobbyConfig {
    param([object]$Config)

    $notes = if ($Config.Notes) { [string]$Config.Notes } elseif ($Config.notes) { [string]$Config.notes } else { '' }
    $steps = if ($Config.Steps) { $Config.Steps } elseif ($Config.steps) { $Config.steps } else { @() }
    $names = @($steps | ForEach-Object {
        if ($_.Name) { [string]$_.Name } elseif ($_.name) { [string]$_.name } else { '' }
    })

    return (
        $notes -eq 'Edit coordinates after calibration. Steps support wait, click, sendKeys, and text.' -and
        $names -contains 'Open play menu' -and
        $names -contains 'Open custom games' -and
        $names -contains 'Create lobby'
    )
}

function Resolve-StepText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $Text.Replace('{{ModGameName}}', $ModGameName)
}

function Test-ColorCluster {
    param([object]$Step)

    $region = if ($Step.Region) { $Step.Region } else { $Step.region }
    $color = if ($Step.Color) { $Step.Color } else { $Step.color }
    if ($null -eq $region -or $null -eq $color) { return $false }

    $tolerance = if ($Step.Tolerance) { [int]$Step.Tolerance } elseif ($Step.tolerance) { [int]$Step.tolerance } else { 24 }
    $minHits = if ($Step.MinHits) { [int]$Step.MinHits } elseif ($Step.minHits) { [int]$Step.minHits } else { 20 }
    $sampleStep = if ($Step.SampleStep) { [int]$Step.SampleStep } elseif ($Step.sampleStep) { [int]$Step.sampleStep } else { 4 }

    $r = if ($color.r -ne $null) { [int]$color.r } else { [int]$color.R }
    $g = if ($color.g -ne $null) { [int]$color.g } else { [int]$color.G }
    $b = if ($color.b -ne $null) { [int]$color.b } else { [int]$color.B }
    $rect = [System.Drawing.Rectangle]::new([int]$region.x, [int]$region.y, [int]$region.width, [int]$region.height)
    $bitmap = New-Object System.Drawing.Bitmap $rect.Width, $rect.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.CopyFromScreen($rect.Location, [System.Drawing.Point]::Empty, $rect.Size)
        $hits = 0
        for ($y = 0; $y -lt $rect.Height; $y += $sampleStep) {
            for ($x = 0; $x -lt $rect.Width; $x += $sampleStep) {
                $pixel = $bitmap.GetPixel($x, $y)
                if ([Math]::Abs($pixel.R - $r) -le $tolerance -and
                    [Math]::Abs($pixel.G - $g) -le $tolerance -and
                    [Math]::Abs($pixel.B - $b) -le $tolerance) {
                    $hits++
                    if ($hits -ge $minHits) { return $true }
                }
            }
        }

        return $false
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Invoke-Capture {
    param([object]$Step)

    $region = if ($Step.Region) { $Step.Region } else { $Step.region }
    $output = if ($Step.Output) { [string]$Step.Output } else { [string]$Step.output }
    if ([string]::IsNullOrWhiteSpace($output)) {
        $output = Join-Path $localDir ("captures\{0:yyyyMMdd-HHmmss}.png" -f (Get-Date))
    }
    if (-not [System.IO.Path]::IsPathRooted($output)) {
        $output = Join-Path $projectRoot $output
    }
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $output))
    $rect = [System.Drawing.Rectangle]::new([int]$region.x, [int]$region.y, [int]$region.width, [int]$region.height)
    $bitmap = New-Object System.Drawing.Bitmap $rect.Width, $rect.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rect.Location, [System.Drawing.Point]::Empty, $rect.Size)
        $bitmap.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Status "Captured: $output"
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Invoke-Verification {
    param(
        [object]$Rule,
        [string]$Label
    )

    $action = if ($Rule.Action) { [string]$Rule.Action } elseif ($Rule.action) { [string]$Rule.action } else { 'verifyColorCluster' }

    switch ($action) {
        'verifyColorCluster' {
            $timeoutMs = if ($Rule.TimeoutMs) { [int]$Rule.TimeoutMs } elseif ($Rule.timeoutMs) { [int]$Rule.timeoutMs } else { 3000 }
            $deadline = (Get-Date).AddMilliseconds($timeoutMs)
            while ((Get-Date) -lt $deadline) {
                if (Test-ColorCluster -Step $Rule) {
                    Write-Status "Verified: $Label"
                    return
                }
                Start-Sleep -Milliseconds 150
            }

            throw "Verification failed: $Label"
        }
        'capture' {
            Invoke-Capture -Step $Rule
        }
        default {
            throw "Unknown verification action '$action' for $Label"
        }
    }
}

function Invoke-Prerequisites {
    param([object]$Step)

    $prerequisites = if ($Step.Prerequisites) { $Step.Prerequisites } else { $Step.prerequisites }
    if ($null -eq $prerequisites) { return }

    $items = @($prerequisites)
    $count = 0
    foreach ($rule in $items) {
        $count++
        $ruleName = if ($rule.Name) { [string]$rule.Name } elseif ($rule.name) { [string]$rule.name } else { "Prerequisite $count" }
        Invoke-Verification -Rule $rule -Label $ruleName
    }
}

$config = Get-SequenceConfig
if ([string]::IsNullOrWhiteSpace($ModGameName) -and $config.modGameName) {
    $ModGameName = [string]$config.modGameName
}
if ([string]::IsNullOrWhiteSpace($ModGameName) -and $config.ModGameName) {
    $ModGameName = [string]$config.ModGameName
}

Write-Status "$Tool sequence starting. DryRun=$DryRun, StepDelayMs=$StepDelayMs"
Write-Status "Mod game: $ModGameName"

$index = 0
$steps = if ($config.steps) { $config.steps } else { $config.Steps }

function Invoke-SequenceSteps {
    param(
        [object[]]$Steps,
        [string]$Prefix = 'Step'
    )

    $localIndex = 0
    foreach ($step in $Steps) {
        $localIndex++
        $name = if ($step.Name) { [string]$step.Name } else { "$Prefix $localIndex" }
        $action = if ($step.Action) { [string]$step.Action } else { 'wait' }

        Write-Status "$Prefix ${localIndex}: $name [$action]"

        if ($DryRun) {
            Start-Sleep -Milliseconds 100
            if ($action -eq 'subflow') {
                $substeps = if ($step.flow) { $step.flow } elseif ($step.Flow) { $step.Flow } else { @() }
                Invoke-SequenceSteps -Steps @($substeps) -Prefix "$name"
            }
            continue
        }

        Invoke-Prerequisites -Step $step

        switch ($action) {
            'wait' {
                $ms = if ($step.Milliseconds) { [int]$step.Milliseconds } else { $StepDelayMs }
                Start-Sleep -Milliseconds $ms
            }
            'click' {
                Invoke-LeftClick -X ([int]$step.X) -Y ([int]$step.Y)
                Start-Sleep -Milliseconds $StepDelayMs
            }
            'sendKeys' {
                [System.Windows.Forms.SendKeys]::SendWait((Resolve-StepText ([string]$step.Keys)))
                Start-Sleep -Milliseconds $StepDelayMs
            }
            'text' {
                [System.Windows.Forms.SendKeys]::SendWait((Resolve-StepText ([string]$step.Text)))
                Start-Sleep -Milliseconds $StepDelayMs
            }
            'capture' {
                Invoke-Capture -Step $step
                Start-Sleep -Milliseconds $StepDelayMs
            }
            'verifyColorCluster' {
                Invoke-Verification -Rule $step -Label $name
            }
            'subflow' {
                $substeps = if ($step.flow) { $step.flow } elseif ($step.Flow) { $step.Flow } else { @() }
                Invoke-SequenceSteps -Steps @($substeps) -Prefix "$name"
            }
            default {
                Write-Status "WARNING: Unknown action '$action'; skipping."
            }
        }
    }
}

Invoke-SequenceSteps -Steps @($steps)

Write-Status "$Tool sequence completed."
