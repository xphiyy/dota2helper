Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

if ($PSScriptRoot) { $scriptDir = $PSScriptRoot } else { $scriptDir = (Get-Location).Path }
$workerScript = Join-Path $scriptDir 'Accept-DotaMatch.ps1'
$configPath = Join-Path $scriptDir 'acceptor.config.json'
$runtimeLogPath = Join-Path $scriptDir 'acceptor.runtime.log'
$state = [ordered]@{ Process = $null; Closing = $false; LogOffset = 0 }

function Quote-Arg {
    param([string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Join-Args {
    param([string[]]$Values)
    return (($Values | ForEach-Object { Quote-Arg $_ }) -join ' ')
}

function Add-Log {
    param([string]$Message)
    if ($null -eq $txtLog -or $txtLog.IsDisposed) { return }
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $txtLog.AppendText("[$timestamp] $Message`r`n")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}

function Sync-WorkerLog {
    if (-not (Test-Path -LiteralPath $runtimeLogPath)) { return }

    try {
        $stream = [System.IO.File]::Open($runtimeLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            if ($state.LogOffset -gt $stream.Length) { $state.LogOffset = 0 }
            [void]$stream.Seek([int64]$state.LogOffset, [System.IO.SeekOrigin]::Begin)
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $newText = $reader.ReadToEnd()
            $state.LogOffset = $stream.Position
            $reader.Dispose()
        }
        finally {
            $stream.Dispose()
        }

        if (-not [string]::IsNullOrWhiteSpace($newText)) {
            foreach ($line in ($newText -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { Add-Log $line }
            }
        }
    }
    catch {
        Add-Log "Log sync failed: $($_.Exception.Message)"
    }
}

function Get-CalibrationText {
    if (-not (Test-Path -LiteralPath $configPath)) { return 'Calibration: none' }
    try {
        $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        return "Calibration: $($cfg.ClickX),$($cfg.ClickY) on $($cfg.ScreenWidth)x$($cfg.ScreenHeight)"
    }
    catch {
        return 'Calibration: unreadable config'
    }
}

function Set-RunningState {
    param([bool]$Running)
    if ($null -eq $btnStart -or $btnStart.IsDisposed) { return }
    $btnStart.Enabled = -not $Running
    $btnStop.Enabled = $Running
    $lblStatus.Text = if ($Running) { 'Status: running' } else { 'Status: stopped' }
}

function Stop-Worker {
    try {
        if ($null -ne $state.Process -and -not $state.Process.HasExited) {
            $state.Process.Kill()
            [void]$state.Process.WaitForExit(1500)
            Sync-WorkerLog
            if (-not $state.Closing) { Add-Log 'Stopped capture process.' }
        }
        if ($null -ne $state.Process) {
            $state.Process.Dispose()
        }
    }
    catch {
        if (-not $state.Closing) { Add-Log "Stop failed: $($_.Exception.Message)" }
    }
    finally {
        $state.Process = $null
        if (-not $state.Closing) { Set-RunningState $false }
    }
}

function Start-HiddenWorker {
    param([string[]]$WorkerArgs)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = Join-Args $WorkerArgs
    $psi.WorkingDirectory = $scriptDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    return $proc
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Dota Match Queue Auto Acceptor'
$form.Size = [System.Drawing.Size]::new(640, 560)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = [System.Drawing.Point]::new(16, 16)
$lblStatus.Size = [System.Drawing.Size]::new(260, 24)
$lblStatus.Text = 'Status: stopped'
$form.Controls.Add($lblStatus)

$lblCalibration = New-Object System.Windows.Forms.Label
$lblCalibration.Location = [System.Drawing.Point]::new(300, 16)
$lblCalibration.Size = [System.Drawing.Size]::new(310, 24)
$lblCalibration.Text = Get-CalibrationText
$form.Controls.Add($lblCalibration)

$grpOptions = New-Object System.Windows.Forms.GroupBox
$grpOptions.Location = [System.Drawing.Point]::new(16, 52)
$grpOptions.Size = [System.Drawing.Size]::new(592, 170)
$grpOptions.Text = 'Auto accept options'
$form.Controls.Add($grpOptions)

$chkNoClick = New-Object System.Windows.Forms.CheckBox
$chkNoClick.Location = [System.Drawing.Point]::new(18, 28)
$chkNoClick.Size = [System.Drawing.Size]::new(160, 24)
$chkNoClick.Text = 'Test mode: no click'
$grpOptions.Controls.Add($chkNoClick)

$chkVerbose = New-Object System.Windows.Forms.CheckBox
$chkVerbose.Location = [System.Drawing.Point]::new(200, 28)
$chkVerbose.Size = [System.Drawing.Size]::new(150, 24)
$chkVerbose.Text = 'Verbose detection'
$grpOptions.Controls.Add($chkVerbose)

$chkAnyForeground = New-Object System.Windows.Forms.CheckBox
$chkAnyForeground.Location = [System.Drawing.Point]::new(380, 28)
$chkAnyForeground.Size = [System.Drawing.Size]::new(180, 24)
$chkAnyForeground.Text = 'Allow any foreground'
$grpOptions.Controls.Add($chkAnyForeground)

$chkStopAfter = New-Object System.Windows.Forms.CheckBox
$chkStopAfter.Location = [System.Drawing.Point]::new(18, 62)
$chkStopAfter.Size = [System.Drawing.Size]::new(260, 24)
$chkStopAfter.Text = 'Stop after accept and disappear'
$chkStopAfter.Checked = $true
$grpOptions.Controls.Add($chkStopAfter)

$lblPoll = New-Object System.Windows.Forms.Label
$lblPoll.Location = [System.Drawing.Point]::new(18, 105)
$lblPoll.Size = [System.Drawing.Size]::new(80, 22)
$lblPoll.Text = 'Poll ms'
$grpOptions.Controls.Add($lblPoll)

$numPoll = New-Object System.Windows.Forms.NumericUpDown
$numPoll.Location = [System.Drawing.Point]::new(98, 103)
$numPoll.Size = [System.Drawing.Size]::new(80, 24)
$numPoll.Minimum = 100
$numPoll.Maximum = 3000
$numPoll.Increment = 50
$numPoll.Value = 450
$grpOptions.Controls.Add($numPoll)

$lblStable = New-Object System.Windows.Forms.Label
$lblStable.Location = [System.Drawing.Point]::new(200, 105)
$lblStable.Size = [System.Drawing.Size]::new(80, 22)
$lblStable.Text = 'Stable hits'
$grpOptions.Controls.Add($lblStable)

$numStable = New-Object System.Windows.Forms.NumericUpDown
$numStable.Location = [System.Drawing.Point]::new(280, 103)
$numStable.Size = [System.Drawing.Size]::new(80, 24)
$numStable.Minimum = 1
$numStable.Maximum = 10
$numStable.Value = 3
$grpOptions.Controls.Add($numStable)

$lblCooldown = New-Object System.Windows.Forms.Label
$lblCooldown.Location = [System.Drawing.Point]::new(382, 105)
$lblCooldown.Size = [System.Drawing.Size]::new(80, 22)
$lblCooldown.Text = 'Cooldown s'
$grpOptions.Controls.Add($lblCooldown)

$numCooldown = New-Object System.Windows.Forms.NumericUpDown
$numCooldown.Location = [System.Drawing.Point]::new(468, 103)
$numCooldown.Size = [System.Drawing.Size]::new(80, 24)
$numCooldown.Minimum = 1
$numCooldown.Maximum = 120
$numCooldown.Value = 15
$grpOptions.Controls.Add($numCooldown)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Location = [System.Drawing.Point]::new(16, 240)
$btnStart.Size = [System.Drawing.Size]::new(130, 34)
$btnStart.Text = 'Start capture'
$form.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Location = [System.Drawing.Point]::new(158, 240)
$btnStop.Size = [System.Drawing.Size]::new(130, 34)
$btnStop.Text = 'Stop capture'
$btnStop.Enabled = $false
$form.Controls.Add($btnStop)

$btnCalibrate = New-Object System.Windows.Forms.Button
$btnCalibrate.Location = [System.Drawing.Point]::new(300, 240)
$btnCalibrate.Size = [System.Drawing.Size]::new(130, 34)
$btnCalibrate.Text = 'Calibrate click'
$form.Controls.Add($btnCalibrate)

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Location = [System.Drawing.Point]::new(442, 240)
$btnOpenFolder.Size = [System.Drawing.Size]::new(130, 34)
$btnOpenFolder.Text = 'Open folder'
$form.Controls.Add($btnOpenFolder)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = [System.Drawing.Point]::new(16, 292)
$txtLog.Size = [System.Drawing.Size]::new(592, 210)
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($txtLog)

$btnStart.Add_Click({
    try {
        if ($null -ne $state.Process -and -not $state.Process.HasExited) {
            Add-Log 'Capture is already running.'
            return
        }

        Set-Content -LiteralPath $runtimeLogPath -Value '' -Encoding UTF8
        $state.LogOffset = 0

        $argsList = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $workerScript,
            '-PollMs', [string][int]$numPoll.Value,
            '-StableHits', [string][int]$numStable.Value,
            '-CooldownSeconds', [string][int]$numCooldown.Value,
            '-LogPath', $runtimeLogPath
        )

        if ($chkNoClick.Checked) { $argsList += '-NoClick' }
        if ($chkVerbose.Checked) { $argsList += '-VerboseDetection' }
        if ($chkAnyForeground.Checked) { $argsList += '-AllowAnyForeground' }
        if ($chkStopAfter.Checked) { $argsList += '-StopAfterAccept' }

        $state.Process = Start-HiddenWorker -WorkerArgs $argsList
        Set-RunningState $true
        Add-Log "Started hidden capture process, PID $($state.Process.Id)."
    }
    catch {
        Add-Log "Start failed: $($_.Exception.Message)"
    }
})

$btnStop.Add_Click({ Stop-Worker })

$btnCalibrate.Add_Click({
    try {
        Add-Log 'Opening calibration console. Put mouse on Accept button and press Enter there.'
        $argsList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $workerScript, '-Calibrate')
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = Join-Args $argsList
        $psi.WorkingDirectory = $scriptDir
        $psi.UseShellExecute = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
        [void][System.Diagnostics.Process]::Start($psi)
    }
    catch {
        Add-Log "Calibration failed: $($_.Exception.Message)"
    }
})

$btnOpenFolder.Add_Click({
    try { Start-Process -FilePath $scriptDir }
    catch { Add-Log "Open folder failed: $($_.Exception.Message)" }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    try {
        if ($state.Closing) { return }
        Sync-WorkerLog
        if ($null -ne $state.Process -and $state.Process.HasExited) {
            Sync-WorkerLog
            Add-Log "Capture process exited with code $($state.Process.ExitCode)."
            $state.Process.Dispose()
            $state.Process = $null
            Set-RunningState $false
        }
        $lblCalibration.Text = Get-CalibrationText
    }
    catch {
        Add-Log "Timer error: $($_.Exception.Message)"
    }
})
$timer.Start()

$form.Add_FormClosing({
    $state.Closing = $true
    $timer.Stop()
    Stop-Worker
    $timer.Dispose()
})

Add-Log 'GUI ready.'
[void]$form.ShowDialog()

